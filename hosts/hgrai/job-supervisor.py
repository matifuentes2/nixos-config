#!/usr/bin/env python3
"""Privileged, narrow job launcher. No commands or environment from ticket data."""
import hashlib
import grp
import json
import math
import os
from pathlib import Path
import pwd
import re
import shutil
import socket
import select
import struct
import stat
import subprocess
import sys
import threading
import time
import tempfile
import uuid
import urllib.request

JOB_UNIT_PATTERN = "grai-job-run-*.service"


class Supervisor:
    def __init__(self, config, clock=time.monotonic):
        self.config = config
        Path(config["state"]).mkdir(parents=True, exist_ok=True)
        self.clock = clock
        self.lock = threading.RLock()
        self.active = None
        self.retired = set()
        self.bridge_uid = pwd.getpwnam("support-bridge").pw_uid
        self.controller_uid = pwd.getpwnam("coding-agent").pw_uid

    def unit(self, key):
        return "grai-job-run-" + hashlib.sha256(key.encode()).hexdigest()[:24] + ".service"

    def revoked_path(self, key):
        return Path(self.config["state"]) / "revoked" / hashlib.sha256(key.encode()).hexdigest()

    def retire(self, key):
        marker = self.revoked_path(key)
        marker.parent.mkdir(mode=0o700, exist_ok=True)
        marker.touch()
        self.retired.add(key)

    def export(self, archive, worktree):
        # Allocated disk blocks alone do not bound sparse-file expansion during
        # export. Limit logical size and entry count before privileged copying.
        size = entries = 0
        for directory, dirs, files in os.walk(archive / "data" / "repo", followlinks=False):
            dirs[:] = [name for name in dirs if name != ".git"]
            entries += len(dirs) + len(files)
            for name in files:
                info = (Path(directory) / name).lstat()
                if stat.S_ISREG(info.st_mode):
                    size += info.st_size
            if size > 2 * 1024**3 or entries > 100000:
                raise RuntimeError("Export budget exceeded")
        export_parent = Path(self.config["state"]) / "exports"
        export_parent.mkdir(mode=0o711, exist_ok=True)
        os.chmod(export_parent, 0o711)
        if min(shutil.disk_usage(export_parent).free, shutil.disk_usage(worktree).free) < 5 * 1024**3:
            raise RuntimeError("Insufficient export storage")
        with tempfile.TemporaryDirectory(dir=export_parent) as temporary:
            subprocess.run(["rsync", "-aS", "--chown=root:root", "--chmod=Du=rwx,Dgo=,Fu+rw,Fgo=", "--safe-links", "--no-devices", "--no-specials", "--exclude=.git", str(archive / "data" / "repo") + "/", temporary + "/"], check=True, timeout=60)
            controller = pwd.getpwnam("coding-agent")
            for root, dirs, files in os.walk(temporary, followlinks=False):
                for name in dirs + files:
                    os.chown(Path(root) / name, controller.pw_uid, controller.pw_gid, follow_symlinks=False)
            os.chown(temporary, controller.pw_uid, controller.pw_gid)
            subprocess.run(["runuser", "-u", "coding-agent", "--", "rsync", "-aS", "--no-owner", "--no-group", "--safe-links", "--no-devices", "--no-specials", "--delete", "--exclude=.git", temporary + "/", str(worktree) + "/"], check=True, timeout=60)

    def stop(self):
        if self.active:
            key = self.active["key"]
            result = subprocess.run(["systemctl", "stop", self.unit(key)], capture_output=True, timeout=20)
            # A never-started unit is already stopped. Any other failure is a
            # quarantine: do not admit another claim until stop is confirmed.
            state = subprocess.run(["systemctl", "show", self.unit(key), "-p", "ActiveState", "--value"], capture_output=True, text=True, timeout=10)
            if state.stdout.strip() not in ("", "inactive", "failed"):
                raise RuntimeError("Job stop is unconfirmed")
            group = subprocess.run(["systemctl", "show", self.unit(key), "-p", "ControlGroup", "--value"], capture_output=True, text=True, timeout=10).stdout.strip()
            if group:
                events = Path("/sys/fs/cgroup") / group.lstrip("/") / "cgroup.events"
                if events.exists() and "populated 1" in events.read_text():
                    raise RuntimeError("Job processes remain alive")
            if self.active.get("archive"):
                # rsync runs as the unprivileged controller and never transfers
                # sandbox Git hooks/config into T3's real repository metadata.
                archive = Path(self.active["archive"])
                for profile in (archive / "data" / "home").glob("cua-profile-*"):
                    if profile.is_symlink():
                        profile.unlink()
                    elif profile.is_dir():
                        shutil.rmtree(profile)
                try:
                    self.export(archive, self.active["worktree"])
                except Exception as error:
                    # Execution is already stopped. Preserve its complete disk
                    # for review and report failed delivery without blocking
                    # every subsequent ticket on a non-retryable export.
                    (archive / "export_failed").write_text(type(error).__name__)
                    print("execution_export_failed", file=sys.stderr, flush=True)
                (archive / "finished").touch()
                subprocess.run(["umount", str(archive / "data")], check=True, timeout=15)
            self.retire(key)
            self.active = None

    def admit(self, for_execution=False):
        if self.active and not for_execution:
            raise RuntimeError("An execution still requires reconciliation")
        if self.config.get("proxySocket"):
            connection = socket.socket(socket.AF_UNIX)
            connection.settimeout(25)
            try:
                connection.connect(self.config["proxySocket"])
                connection.sendall(b"GET /health HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
                if not connection.recv(4096).startswith(b"HTTP/1.1 200 "):
                    raise RuntimeError("Model authentication is unavailable")
            finally:
                connection.close()
        # Refuse new work before disk pressure can compromise durable state.
        images = list(Path(self.config["state"]).glob("*/disk.img"))
        if len(images) >= 16 or shutil.disk_usage(self.config["state"]).free < 10 * 1024**3:
            raise RuntimeError("Storage admission refused; archive reviewed jobs")

    def cleanup(self):
        # Closed/resolved tickets have completed human review. Keep seven days
        # of local recovery artifacts; T3's original messages remain retained.
        cutoff = time.time() - 7 * 86400
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, *args, **kwargs):
                return None
        opener = urllib.request.build_opener(NoRedirect)
        token = Path(self.config["supportToken"]).read_text().strip()
        reviewed = set()
        for directory in Path(self.config["evidence"]).iterdir():
            if not directory.is_dir() or directory.is_symlink() or not re.fullmatch(r"[a-f0-9]{64}", directory.name):
                continue
            try:
                record = json.loads((directory / "retention.json").read_text())
                if record.get("completed", time.time() * 1000) / 1000 > cutoff:
                    continue
                ticket = record["ticket"]
                if not re.fullmatch(r"[a-zA-Z0-9-]{1,100}", ticket):
                    continue
                request = urllib.request.Request(self.config["supportUrl"] + "/api/tickets/" + ticket, headers={"Authorization": "Bearer " + token})
                with opener.open(request, timeout=10) as response:
                    detail = json.load(response)
                if detail["ticket"]["status"] not in ("resolved", "closed"):
                    continue
                with self.lock:
                    if self.active and hashlib.sha256(self.active["key"].encode()).hexdigest() == directory.name:
                        continue
                    reviewed.add(directory.name)
            except (OSError, ValueError, KeyError):
                continue
        for archive in Path(self.config["state"]).iterdir():
            if archive.name not in reviewed or archive.is_symlink() or not (archive / "finished").exists() or os.path.ismount(archive / "data"):
                continue
            metadata = json.loads((archive / "metadata.json").read_text())
            worktree = Path(metadata["worktree"])
            if worktree.is_relative_to(Path(self.config["worktrees"])):
                subprocess.run(["runuser", "-u", "coding-agent", "--", self.config["git"], "-C", self.config["repository"], "worktree", "remove", "--force", str(worktree)], check=True, timeout=30)
                shutil.rmtree(archive)
        for key in reviewed:
            if not (Path(self.config["state"]) / key).exists():
                shutil.rmtree(Path(self.config["evidence"]) / key)
                (Path(self.config["state"]) / "revoked" / key).unlink(missing_ok=True)
                self.retired = {claim for claim in self.retired if hashlib.sha256(claim.encode()).hexdigest() != key}

    def maintain(self):
        while True:
            try:
                self.cleanup()
            except Exception:
                print("retention_cleanup_failed", file=sys.stderr, flush=True)
            time.sleep(3600)

    def lease(self, request):
        key = request["key"]
        if not re.fullmatch(r"grai:[A-Za-z0-9-]{1,100}:[A-Za-z0-9-]{1,100}", key):
            raise ValueError("Invalid claim")
        if key in self.retired or self.revoked_path(key).exists():
            raise ValueError("Execution lease was revoked")
        now = self.clock()
        if self.active and (now >= self.active["until"] or now >= self.active["deadline"]):
            self.stop()
        if key in self.retired:
            raise ValueError("Execution lease was revoked")
        if self.active and self.active["key"] != key:
            raise ValueError("Another execution is still owned")
        if not self.active:
            if not isinstance(request["deadline"], (int, float)) or not math.isfinite(request["deadline"]):
                raise ValueError("Invalid execution deadline")
            remaining = min(1800, request["deadline"] / 1000 - time.time())
            if remaining <= 0:
                raise ValueError("Execution deadline passed")
            if not re.fullmatch(r"[a-zA-Z0-9-]{1,100}", request["job"]) or not isinstance(request["attempt"], int) or not 1 <= request["attempt"] <= 3:
                raise ValueError("Invalid job")
            if key.split(":")[1] != request["job"]:
                raise ValueError("Claim does not match job")
            self.active = dict(key=key, job=request["job"], attempt=request["attempt"], deadline=now + remaining, until=now + 60)
        self.active["until"] = min(now + 60, self.active["deadline"])

    def worktree(self):
        lease = self.active
        if not lease or self.clock() >= min(lease["until"], lease["deadline"]):
            raise ValueError("No live execution lease")
        result = subprocess.run(["runuser", "-u", "coding-agent", "--", self.config["git"], "-C", self.config["repository"], "worktree", "list", "--porcelain"], capture_output=True, text=True, check=True, timeout=10)
        branch = f"refs/heads/support/{lease['job']}/{lease['attempt']}"
        matches = []
        for block in result.stdout.strip().split("\n\n"):
            fields = dict(line.split(" ", 1) for line in block.splitlines() if " " in line)
            if fields.get("branch") == branch:
                matches.append(Path(fields["worktree"]).resolve(strict=True))
        if len(matches) != 1:
            raise ValueError("Expected the claim's exact worktree")
        worktree = matches[0]
        if not re.fullmatch(r"[A-Za-z0-9_./-]+", str(worktree)):
            raise ValueError("Unsupported worktree path")
        if not worktree.is_relative_to(Path(self.config["worktrees"]).resolve()):
            raise ValueError("Worktree escaped enrollment")
        return worktree

    def launch(self, connection, probe=False, expected_cwd=None):
        with self.lock:
            if probe:
                worktree = Path(self.config["state"]) / "probe"
                worktree.mkdir(mode=0o755, exist_ok=True)
                lease = dict(key="probe:" + uuid.uuid4().hex, job="probe", attempt=0, deadline=self.clock() + 30)
            else:
                worktree = self.worktree()
                if expected_cwd != str(worktree):
                    raise ValueError("Provider worktree does not match the live claim")
                lease = dict(self.active)
            unit = self.unit(lease["key"])
            archive = Path(self.config["state"]) / hashlib.sha256(lease["key"].encode()).hexdigest()
            jobroot = archive / "data"
            if not probe and not (archive / "disk.img").exists():
                if not probe:
                    self.admit(for_execution=True)
                archive.mkdir(mode=0o700, parents=True, exist_ok=True)
                subprocess.run(["fallocate", "-l", "2G", str(archive / "disk.img")], check=True, timeout=20)
                subprocess.run(["mkfs.ext4", "-q", "-F", "-m", "0", str(archive / "disk.img")], check=True, timeout=30)
            jobroot.mkdir(mode=0o700, parents=True, exist_ok=True)
            if not probe and not os.path.ismount(jobroot):
                subprocess.run(["mount", "-o", "loop,nosuid,nodev", str(archive / "disk.img"), str(jobroot)], check=True, timeout=15)
            if not (jobroot / "repo").exists():
                shutil.copytree(worktree, jobroot / "repo", ignore=shutil.ignore_patterns(".git"), symlinks=True)
                (jobroot / "home").mkdir(mode=0o700, exist_ok=True)
                account = pwd.getpwnam("support-job")
                for root, dirs, files in os.walk(jobroot, followlinks=False):
                    os.chown(root, account.pw_uid, account.pw_gid)
                    os.chmod(root, 0o755)
                    for name in dirs + files:
                        target = Path(root) / name
                        os.chown(target, account.pw_uid, account.pw_gid, follow_symlinks=False)
                        if not target.is_symlink():
                            os.chmod(target, 0o755 if target.is_dir() or target.stat().st_mode & 0o111 else 0o644)
            # An allowlisted root prevents filesystem sockets (notably the Nix
            # daemon) or other host mounts from bypassing the execution cgroup.
            # Generate NSS entries so desktop software can resolve this UID
            # even during tests using a systemd DynamicUser.
            account = pwd.getpwnam("support-job")
            jail = jobroot / "root"
            jail.mkdir(mode=0o755, exist_ok=True)
            os.chmod(jail, 0o755)
            for directory in ("etc", "bin", "usr", "usr/bin", "nix", "nix/store", "tmp", "tmp/.X11-unix", "run", "var", "home", "proc", "dev", "sys"):
                (jail / directory).mkdir(parents=True, exist_ok=True)
                os.chmod(jail / directory, 0o755)
            (jobroot / "x11").mkdir(exist_ok=True)
            os.chmod(jobroot / "x11", 0o1777)
            (jail / "etc" / "passwd").write_text(f"root:x:0:0::/:/bin/sh\nsupport-job:x:{account.pw_uid}:{account.pw_gid}::/home/job:/bin/sh\nnobody:x:65534:65534::/:/bin/sh\n")
            (jail / "etc" / "group").write_text(f"root:x:0:\nsupport-job:x:{account.pw_gid}:\ncoding-agent:x:{grp.getgrnam('coding-agent').gr_gid}:\nnogroup:x:65534:\n")
            (jail / "etc" / "nsswitch.conf").write_text("passwd: files\ngroup: files\nhosts: files dns\n")
            (jail / "etc" / "hosts").write_text("127.0.0.1 localhost\n::1 localhost\n")
            (jail / "etc" / "resolv.conf").write_text("nameserver 127.0.0.1\noptions timeout:1 attempts:1\n")
            (jail / "etc" / "machine-id").write_text(hashlib.sha256(lease["key"].encode()).hexdigest()[:32]+"\n")
            for file in (jail / "etc").iterdir():
                os.chmod(file, 0o644)
            # Copies are disk-quota bounded, with isolated Git metadata. The
            # controller receives the working files only after a confirmed stop.
            lease["archive"] = str(archive)
            lease["worktree"] = str(worktree)
            if not probe:
                self.active.update(lease)
            (archive / "metadata.json").write_text(json.dumps({"worktree": str(worktree), "job": lease["job"], "created": time.time()}))
            # Persist claim identity before starting anything, so a supervisor
            # restart can revoke it after losing in-memory state.
            if not probe:
                self.revoked_path(lease["key"]).parent.mkdir(mode=0o700, exist_ok=True)
                (archive / "claim").write_text(lease["key"])
                if self.clock() >= min(lease["until"], lease["deadline"]):
                    self.stop()
                    raise ValueError("Execution lease expired during preparation")
            evidence = Path(self.config["evidence"]) / hashlib.sha256(lease["key"].encode()).hexdigest()
            args = ["systemd-run", "--quiet", "--pipe", "--wait", "--collect", "--service-type=exec", "--unit=" + unit]
            properties = [
                "User=support-job", "Group=support-job", "SupplementaryGroups=coding-agent", "Slice=grai-jobs.slice",
                "KillMode=control-group", "TimeoutStopSec=5", "SendSIGKILL=yes", "LimitCORE=0",
                "RuntimeMaxSec=" + str(max(1, int(lease["deadline"] - self.clock()))),
                "MemoryMax=3G", "MemorySwapMax=256M", "TasksMax=512", "CPUQuota=150%", "OOMPolicy=kill", "OOMScoreAdjust=800",
                "PrivateNetwork=yes", "PrivateDevices=yes", "PrivateIPC=yes", "PrivatePIDs=yes",
                "RootDirectory=" + str(jail), "MountAPIVFS=yes",
                "ProtectSystem=strict", "ProtectProc=invisible",
                "NoNewPrivileges=yes", "CapabilityBoundingSet=",
                "ProtectKernelTunables=yes", "ProtectKernelModules=yes", "ProtectControlGroups=yes",
                "TemporaryFileSystem=/var:size=128M /run:size=64M /tmp:size=256M,mode=1777",
                "BindReadOnlyPaths=/nix/store /etc/ssl/certs /etc/static/ssl/certs /etc/fonts /etc/static/fonts /etc/dbus-1 /etc/static/dbus-1 /etc/os-release",
                "BindReadOnlyPaths=" + self.config["shell"] + ":/bin/sh",
                "BindReadOnlyPaths=" + self.config["env"] + ":/usr/bin/env",
                # NixOS AT-SPI's installed activation config names this path.
                # Mount just the executable, never the host runtime directory.
                "BindReadOnlyPaths=" + self.config["dbusDaemon"] + ":/run/current-system/sw/bin/dbus-daemon",
                "BindPaths=" + str(jobroot / "x11") + ":/tmp/.X11-unix",
                "BindPaths=" + str(jobroot / "repo") + ":" + str(worktree),
                "BindPaths=" + str(jobroot / "home") + ":/home/job",
                "BindReadOnlyPaths=" + self.config["proxySocket"] + ":/run/model-proxy.sock",
                "WorkingDirectory=" + str(worktree), "UMask=0077",
            ]
            if evidence.exists():
                properties.append("BindReadOnlyPaths=" + str(evidence))
            for prop in properties:
                args += ["--property=" + prop]
            args += ["--", self.config["runtime"], str(worktree)]
            connection.sendall(b'{"ok":true}\n')
            # Stdio carries only the Codex protocol; never caller-supplied argv.
            # Separate pipe descriptions are essential: Tokio sets stdout
            # nonblocking, which would otherwise also change a shared socket's
            # stdin flags and make Codex fail with EAGAIN.
            # Codex's stdio writer sets O_NONBLOCK and can drop JSON above
            # pipe capacity. A quota-bounded regular spool has blocking write
            # semantics even with that flag; tail it over the control socket.
            output_path = jobroot / ("protocol-" + uuid.uuid4().hex + ".jsonl")
            output = open(output_path, "xb", buffering=0)
            reader = open(output_path, "rb", buffering=0)
            process = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=output, stderr=None)
            output.close()
        def forward_input():
            try:
                while chunk := connection.recv(65536):
                    process.stdin.write(chunk)
                    process.stdin.flush()
            except (OSError, BrokenPipeError):
                pass
            finally:
                process.stdin.close()
        threading.Thread(target=forward_input, daemon=True).start()
        try:
            while True:
                chunk = reader.read(65536)
                if chunk:
                    connection.sendall(chunk)
                elif process.poll() is not None:
                    break
                else:
                    time.sleep(0.01)
        except OSError:
            process.stdin.close()
        process.wait()
        reader.close()
        try:
            connection.shutdown(socket.SHUT_RD)
        except OSError:
            pass
        if probe:
            shutil.rmtree(archive)

    def handle(self, connection):
        try:
            connection.settimeout(10)
            _, uid, _ = struct.unpack("3i", connection.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))
            data = bytearray()
            while not data.endswith(b"\n"):
                chunk = connection.recv(1)
                if not chunk or len(data) >= 4096:
                    raise ValueError("Invalid request")
                data.extend(chunk)
            request = json.loads(data)
            operation = request["operation"]
            if operation == "launch" and uid == self.controller_uid:
                connection.settimeout(None)
                self.launch(connection, probe=request.get("probe") is True, expected_cwd=request.get("cwd"))
                return
            if uid != self.bridge_uid:
                raise PermissionError("Only the bridge may change execution leases")
            with self.lock:
                if operation == "admit":
                    self.admit()
                elif operation in ("arm", "renew"):
                    self.lease(request)
                elif operation == "stop":
                    if self.active and self.active["key"] == request["key"]:
                        self.stop()
                    self.retire(request["key"])
                else:
                    raise ValueError("Unknown operation")
            response = {"ok": True}
            if operation == "stop":
                archive = Path(self.config["state"]) / hashlib.sha256(request["key"].encode()).hexdigest()
                response["export_failed"] = (archive / "export_failed").exists()
            connection.sendall(json.dumps(response).encode() + b"\n")
        except Exception as error:
            # Only a class name is logged: requests may contain private IDs.
            print(type(error).__name__, file=sys.stderr, flush=True)
            try:
                connection.sendall(b'{"ok":false}\n')
            except OSError:
                pass
        finally:
            connection.close()

    def reap(self):
        while True:
            time.sleep(1)
            with self.lock:
                if self.active and self.clock() >= min(self.active["until"], self.active["deadline"]):
                    try:
                        self.stop()
                    except Exception:
                        print("execution_stop_unconfirmed", file=sys.stderr, flush=True)

    def serve(self):
        # A supervisor restart revokes every surviving execution. Never adopt
        # orphan processes or recover a lease from stale wall-clock state.
        subprocess.run(["systemctl", "stop", JOB_UNIT_PATTERN], check=True, timeout=30)
        for claim in Path(self.config["state"]).glob("*/claim"):
            self.retire(claim.read_text())
        path = self.config["socket"]
        Path(path).unlink(missing_ok=True)
        listener = socket.socket(socket.AF_UNIX)
        listener.bind(path)
        os.chmod(path, 0o660)
        import grp
        os.chown(path, 0, grp.getgrnam("coding-agent").gr_gid)
        listener.listen(8)
        threading.Thread(target=self.reap, daemon=True).start()
        threading.Thread(target=self.maintain, daemon=True).start()
        while True:
            connection, _ = listener.accept()
            threading.Thread(target=self.handle, args=(connection,), daemon=True).start()


if __name__ == "__main__":
    Supervisor(json.loads(Path(sys.argv[1]).read_text())).serve()
