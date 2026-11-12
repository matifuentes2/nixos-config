#!/usr/bin/env python3
"""Lease independent Cua desktops through a private per-user broker."""
import argparse
import fcntl
import json
import os
import queue
from pathlib import Path
import secrets
import re
import shutil
import signal
import socket
import socketserver
import struct
import subprocess
import sys
import threading
import time


class PoolError(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code


def manager_environment(environment=None):
    env = dict(os.environ if environment is None else environment)
    user_runtime = env.get("CUA_POOL_USER_RUNTIME")
    if user_runtime:
        env["XDG_RUNTIME_DIR"] = user_runtime
        env["DBUS_SESSION_BUS_ADDRESS"] = "unix:path=" + user_runtime + "/bus"
        env.pop("AT_SPI_BUS_ADDRESS", None)
    return env


def systemctl(*args, check=True):
    result = subprocess.run(["systemctl", "--user", *args], capture_output=True,
                            text=True, timeout=70, env=manager_environment())
    if check and result.returncode:
        raise PoolError("service_failed", result.stderr.strip()[:1500])
    return result.stdout.strip()


def remove_path(path):
    """Remove generated state without following a substituted symlink."""
    if path.is_symlink():
        path.unlink()
    elif path.exists():
        shutil.rmtree(path)


def clean_task(workspace):
    for name in ("profile", "cache", "config", "data"):
        remove_path(workspace / name)


class Broker:
    def __init__(self, config, root):
        self.config, self.root = config, root
        self.condition = threading.Condition()
        self.leases = {}
        self.closed = False
        # A broker restart invalidates every old token. Never adopt a desktop
        # whose prior task/focus/profile state cannot be proved.
        # The parent slice also contains slots removed by a configuration change.
        systemctl("stop", "cua-pool.slice")
        for slot in config["slots"]:
            systemctl("stop", slot["slice"])
        # RuntimeDirectory can disappear on a crash; durable task directories
        # are the recovery inventory. Stop every slice before touching state.
        tasks = Path(config["workspaceRoot"])
        if tasks.exists():
            for task in tasks.iterdir():
                if re.fullmatch(r"[0-9a-f]{32}", task.name) and not task.is_symlink() and task.is_dir():
                    clean_task(task)
        for slot in config["slots"]:
            remove_path(root / "slots" / str(slot["id"]))
        self.monitor = threading.Thread(target=self.reap, daemon=True)
        self.monitor.start()

    def description(self, lease):
        slot = lease["slot"]
        runtime = self.root / "slots" / str(slot["id"])
        work = lease["workspace"]
        env = dict(slot["environment"], XDG_RUNTIME_DIR=str(runtime),
                   CUA_LEGACY_DESKTOP="0",
                   PATH=os.environ.get("CUA_POOL_CLIENT_PATH", os.environ["PATH"]),
                   XAUTHORITY=str(runtime / "authority"),
                   CUA_POOL_ROOT=str(self.root), CUA_POOL_LEASE=lease["token"],
                   CUA_POOL_USER_RUNTIME=os.environ.get("CUA_POOL_USER_RUNTIME", os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")),
                   CUA_POOL_SLOT=str(slot["id"]), CUA_POOL_WORKSPACE=str(work / "work"),
                   CUA_POOL_DOWNLOADS=str(work / "downloads"),
                   XDG_CACHE_HOME=str(work / "cache"), XDG_CONFIG_HOME=str(work / "config"),
                   XDG_DATA_HOME=str(work / "data"))
        return dict(lease=lease["token"], slot=slot["id"], display=slot["environment"]["DISPLAY"],
                    socket=str(runtime / f'driver-{lease["token"]}.sock'), workspace=str(work / "work"),
                    downloads=str(work / "downloads"), profile=str(work / "profile"),
                    runtime=str(runtime), run=slot["run"], unit=slot["unit"],
                    slice=slot["slice"], environment=env, idleSeconds=self.config["idleSeconds"])

    def acquire(self, name, wait):
        if not isinstance(name, str) or len(name) > 80 or any(ord(c) < 32 for c in name):
            raise PoolError("invalid_name", "Use a task name of at most 80 printable characters")
        if not isinstance(wait, (int, float)) or not 0 <= wait <= 3600:
            raise PoolError("invalid_wait", "Wait must be between 0 and 3600 seconds")
        deadline = time.monotonic() + wait
        with self.condition:
            while True:
                if self.closed:
                    raise PoolError("broker_stopping", "Pool is stopping")
                used = {lease["slot"]["id"] for lease in self.leases.values()}
                slot = next((slot for slot in self.config["slots"] if slot["id"] not in used), None)
                if slot:
                    break
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise PoolError("pool_exhausted", "All desktops are leased; use --wait or release your task")
                self.condition.wait(remaining)
            token = secrets.token_hex(16)
            lease = dict(token=token, name=name, slot=slot, state="starting", touched=time.monotonic(),
                         workspace=Path(self.config["workspaceRoot"]) / token)
            self.leases[token] = lease
        try:
            desc = self.description(lease)
            runtime = Path(desc["runtime"])
            runtime.mkdir(parents=True, exist_ok=True, mode=0o700)
            lease["workspace"].mkdir(parents=True, mode=0o700)
            for directory in ("work", "downloads", "profile/Default", "cache", "config", "data"):
                (lease["workspace"] / directory).mkdir(parents=True, exist_ok=True, mode=0o700)
            (lease["workspace"] / "profile/Default/Preferences").write_text(json.dumps({
                "download": {"default_directory": desc["downloads"], "prompt_for_download": False},
            }))
            # Only generated values go in this private systemd EnvironmentFile.
            file = runtime / "lease.env"
            file.write_text("".join(f'{key}={json.dumps(value, ensure_ascii=False)}\n'
                                    for key, value in desc["environment"].items()))
            file.chmod(0o600)
            marker = runtime / "lease.id"
            marker.write_text(token + "\n")
            marker.chmod(0o600)
            systemctl("start", slot["unit"])
            invocation = systemctl("show", slot["unit"], "-p", "InvocationID", "--value")
            with self.condition:
                if self.closed or lease["state"] != "starting":
                    raise PoolError("lease_lost", "Pool stopped during acquisition")
                lease.update(state="active", invocation=invocation, touched=time.monotonic())
            return desc
        except Exception:
            self.release(token)
            raise

    def resolve(self, token):
        with self.condition:
            lease = self.leases.get(token)
            if lease is None or lease["state"] != "active":
                raise PoolError("lease_lost", "Lease is absent or no longer active; acquire a new desktop")
            expired = time.monotonic() - lease["touched"] > self.config["idleSeconds"]
            if not expired:
                lease["touched"] = time.monotonic()
        if expired:
            self.release(token)
            raise PoolError("lease_expired", "Lease expired; acquire a fresh desktop")
        values = systemctl("show", lease["slot"]["unit"], "-p", "ActiveState", "-p", "InvocationID")
        fields = dict(line.split("=", 1) for line in values.splitlines() if "=" in line)
        if fields.get("ActiveState") != "active" or fields.get("InvocationID") != lease["invocation"]:
            self.release(token)
            raise PoolError("desktop_lost", "Desktop stopped or restarted; old task state is invalid")
        with self.condition:
            if self.leases.get(token) is not lease or lease["state"] != "active":
                raise PoolError("lease_lost", "Lease ended during validation")
            return self.description(lease)

    def release(self, token, expired_only=False):
        with self.condition:
            lease = self.leases.get(token)
            if lease is None:
                return {"released": False}
            if lease["state"] == "stopping":
                return {"released": False}
            if expired_only and (lease["state"] != "active" or
                                 time.monotonic() - lease["touched"] <= self.config["idleSeconds"]):
                return {"released": False}
            lease["state"] = "stopping"
        # The slot is not allocatable while the slice and all its app jobs stop.
        try:
            (self.root / "slots" / str(lease["slot"]["id"]) / "lease.id").unlink(missing_ok=True)
            systemctl("stop", lease["slot"]["slice"])
            # Preserve task outputs, but never reuse a browser profile or caches
            # across leases. Apps have stopped before their profiles are removed.
            clean_task(lease["workspace"])
        except Exception:
            # Fail closed: leave a quarantined slot rather than reuse live apps.
            with self.condition:
                lease["state"] = "quarantined"
            raise
        with self.condition:
            self.leases.pop(token, None)
            self.condition.notify_all()
        return {"released": True}

    def status(self):
        with self.condition:
            return [dict(slot=lease["slot"]["id"], name=lease["name"], state=lease["state"],
                         idleSeconds=max(0, int(time.monotonic() - lease["touched"])))
                    for lease in self.leases.values()]

    def watch(self, slot):
        with self.condition:
            token = next((lease["token"] for lease in self.leases.values()
                          if lease["slot"]["id"] == slot and lease["state"] == "active"), None)
        if token is None:
            raise PoolError("slot_idle", "That slot has no active desktop")
        return self.resolve(token)

    def reap(self):
        while True:
            with self.condition:
                if self.closed:
                    return
                active = [lease for lease in self.leases.values() if lease["state"] == "active"]
            for lease in active:
                try:
                    expired = time.monotonic() - lease["touched"] > self.config["idleSeconds"]
                    values = systemctl("show", lease["slot"]["unit"], "-p", "ActiveState", "-p", "InvocationID")
                    fields = dict(line.split("=", 1) for line in values.splitlines() if "=" in line)
                    failed = fields.get("ActiveState") != "active" or fields.get("InvocationID") != lease["invocation"]
                    if expired or failed:
                        self.release(lease["token"], expired_only=not failed)
                except Exception as error:
                    print(f"Lease cleanup failed: {error}", file=sys.stderr)
            time.sleep(1)

    def close(self):
        with self.condition:
            self.closed = True
            tokens = list(self.leases)
            self.condition.notify_all()
        for token in tokens:
            try:
                self.release(token)
            except Exception as error:
                print(f"Lease cleanup failed: {error}", file=sys.stderr)


def serve(config, root):
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    root.chmod(0o700)
    lock = (root / "manager.lock").open("a+")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError as error:
        lock.close()
        raise PoolError("broker_running", "A pool broker already owns this runtime directory") from error
    broker = Broker(config, root)
    address = root / "manager.sock"
    address.unlink(missing_ok=True)

    class Handler(socketserver.StreamRequestHandler):
        def handle(self):
            uid = struct.unpack("3i", self.request.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))[1]
            if uid != os.getuid():
                return
            message = {}
            try:
                message = json.loads(self.rfile.readline(1048577))
                op = message.get("op")
                if op == "acquire":
                    result = broker.acquire(message.get("name", "task"), message.get("wait", 0))
                elif op in ("resolve", "renew"):
                    result = broker.resolve(message["lease"])
                elif op == "release":
                    result = broker.release(message["lease"])
                elif op == "status":
                    result = broker.status()
                elif op == "watch":
                    result = broker.watch(message["slot"])
                else:
                    raise PoolError("invalid_operation", "Unknown pool operation")
                response = {"ok": True, "result": result}
            except PoolError as error:
                response = {"ok": False, "code": error.code, "error": str(error)}
            except Exception as error:
                response = {"ok": False, "code": "request_failed", "error": str(error)[:1500]}
            try:
                self.wfile.write((json.dumps(response) + "\n").encode())
            except (BrokenPipeError, ConnectionResetError):
                # An acquisition abandoned during startup must not occupy a slot.
                if message.get("op") == "acquire" and response.get("ok"):
                    broker.release(response["result"]["lease"])

    class Server(socketserver.ThreadingUnixStreamServer):
        daemon_threads = True

    with Server(str(address), Handler) as server:
        address.chmod(0o600)
        def stop(_signum, _frame):
            threading.Thread(target=server.shutdown, daemon=True).start()
        signal.signal(signal.SIGTERM, stop)
        signal.signal(signal.SIGINT, stop)
        try:
            server.serve_forever(poll_interval=0.2)
        finally:
            broker.close()
            address.unlink(missing_ok=True)
            lock.close()


def request(root, op, **kwargs):
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.settimeout(kwargs.get("wait", 0) + 100)
            client.connect(str(root / "manager.sock"))
            client.sendall((json.dumps(dict(op=op, **kwargs)) + "\n").encode())
            with client.makefile("rb") as stream:
                response = json.loads(stream.readline(1048577))
    except (OSError, ValueError) as error:
        raise PoolError("broker_unavailable", f"Pool is unavailable: {error}; check cua-pool-manager.service") from error
    if not response["ok"]:
        raise PoolError(response["code"], response["error"])
    return response["result"]


def execute(config, root, desc, command):
    # Nested helpers already belong to this lease's cgroup. Preserve their PID
    # (discovery tests and GUI launchers depend on exec semantics).
    if desc["slice"] in Path("/proc/self/cgroup").read_text().split("/"):
        env = dict(os.environ, **desc["environment"])
        os.execve(desc["run"], [desc["run"], *command], env)
    # Every descendant belongs to the leased slice, including app processes
    # launched through CLI helpers rather than the driver's launch_app tool.
    unit = "cua-pool-job-" + secrets.token_hex(12)
    terminal = "--pty" if sys.stdin.isatty() and sys.stdout.isatty() else "--pipe"
    argv = ["systemd-run", "--user", "--quiet", "--wait", terminal, "--collect",
            "--service-type=exec", "--unit=" + unit, "--slice=" + desc["slice"],
            "--property=BindsTo=" + desc["unit"], "--property=After=" + desc["unit"],
            "--property=NoNewPrivileges=yes", "--property=KillMode=control-group",
            "--property=TimeoutStopSec=5", "--working-directory=" + os.getcwd()]
    # Forward the caller's agent/auth environment without putting values in
    # command-line arguments. Route GUI and XDG state through the lease.
    child_env = dict(os.environ, **desc["environment"])
    for key in ("NOTIFY_SOCKET", "INVOCATION_ID", "SYSTEMD_EXEC_PID", "JOURNAL_STREAM",
                "LISTEN_FDS", "LISTEN_PID", "WATCHDOG_PID", "WATCHDOG_USEC"):
        child_env.pop(key, None)
    argv += ["--setenv=" + key for key in child_env
             if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key)
             and key not in ("XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS", "AT_SPI_BUS_ADDRESS")]
    argv += ["--setenv=XDG_RUNTIME_DIR=" + desc["runtime"]]
    argv += ["--property=UnsetEnvironment=" + " ".join(config["unsetEnvironment"])]
    argv += ["--", desc["run"], *command]
    child = subprocess.Popen(argv, env=manager_environment(child_env))
    done = threading.Event()
    lost = threading.Event()
    def heartbeat():
        while not done.wait(max(0.2, min(10, desc["idleSeconds"] / 3))):
            try:
                request(root, "renew", lease=desc["lease"])
            except PoolError:
                lost.set()
                systemctl("stop", unit, check=False)
                return
    thread = threading.Thread(target=heartbeat, daemon=True)
    thread.start()
    previous = {}
    cancelled = []
    def cancel(signum, _frame):
        cancelled.append(signum)
        if child.poll() is None:
            child.terminate()
        systemctl("stop", unit, check=False)
    for sig in (signal.SIGINT, signal.SIGTERM):
        previous[sig] = signal.signal(sig, cancel)
    try:
        code = child.wait()
        done.set()
        if cancelled:
            return 128 + cancelled[0]
        if lost.is_set():
            raise PoolError("lease_lost", "Lease was lost while the task was running")
        if code == 0:
            # systemd-run can return success when BindsTo or an external stop
            # interrupted the job before the next heartbeat. Validate both the
            # token and desktop invocation before accepting that exit status.
            try:
                request(root, "resolve", lease=desc["lease"])
            except PoolError as error:
                raise PoolError("lease_lost", "Cannot confirm task completion on an active desktop: " + str(error)) from error
        return code
    finally:
        done.set()
        thread.join(timeout=2)
        if child.poll() is None:
            systemctl("stop", unit, check=False)
            child.wait(timeout=10)
        for sig, handler in previous.items():
            signal.signal(sig, handler)


def start_mcp(config, args, desc):
    return subprocess.Popen([
        sys.executable, str(Path(__file__).resolve()), "--config", str(args.config),
        "run", desc["lease"], "--", config["driver"], "mcp", "--socket", desc["socket"],
    ], stdin=subprocess.PIPE, stdout=subprocess.PIPE)


def mcp(config, root, args):
    """Discover offline and proxy native messages while reclaiming idle leases."""
    schemas = None
    initialize = None
    child = None
    desc = None
    automatic = not os.environ.get("CUA_POOL_LEASE")
    events = queue.Queue()
    pending = {}
    ready = False
    started_at = None
    waiting = []
    reset_reason = None
    last_activity = time.monotonic()
    idle_seconds = config.get("mcpIdleSeconds", 600)
    release_tool = "pool_release_desktop"

    def send(message):
        sys.stdout.write(json.dumps(message) + "\n")
        sys.stdout.flush()

    def tool_result(identifier, text, error=False):
        send(dict(jsonrpc="2.0", id=identifier, result={
            "isError": error, "content": [{"type": "text", "text": text}],
        }))

    def read_stream(stream, source):
        try:
            for line in stream:
                events.put((source, line))
        finally:
            events.put((source, None))

    def dispose(reason=None):
        nonlocal child, desc, ready, reset_reason
        old_child, old_desc = child, desc
        child, desc, ready = None, None, False
        waiting.clear()
        release_error = None
        try:
            if old_child is not None:
                if old_child.poll() is None:
                    old_child.terminate()
                    try:
                        old_child.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        old_child.kill()
                        old_child.wait()
                old_child.stdin.close()
                old_child.stdout.close()
        finally:
            if old_desc is not None and automatic:
                try:
                    request(root, "release", lease=old_desc["lease"])
                except PoolError as error:
                    # The broker owns quarantine and restart cleanup. An outage
                    # must not prevent reporting lost state or close this MCP
                    # connection; never claim cleanup succeeded in that case.
                    release_error = error
                    reason = (reason or "desktop_lost: Desktop detached.") + f" Cleanup not confirmed ({error.code}): {error}"
                    print(reason, file=sys.stderr)
        if reason:
            reset_reason = reason
        for identifier in pending:
            tool_result(identifier, reason or "Desktop released", True)
        pending.clear()
        return release_error

    def tools():
        nonlocal schemas
        if schemas is None:
            listing = subprocess.check_output([config["driver"], "list-tools"], text=True)
            schemas = []
            for line in listing.splitlines():
                name = line.split(":", 1)[0]
                if not re.fullmatch(r"[a-z_][a-z0-9_]*", name):
                    continue
                description = subprocess.check_output([config["driver"], "describe", name], text=True)
                heading, schema = description.split("\n\ninput_schema:\n", 1)
                schemas.append(dict(name=name, description=heading.split("\ndescription:\n", 1)[1].strip(),
                                    inputSchema=json.loads(schema)))
            schemas.append(dict(name=release_tool,
                                description="Release this connection's desktop when GUI work is complete. Closes its apps and discards profiles; preserves task outputs. The next GUI call gets a fresh desktop: discover windows again. Refused while requests are pending or the lease belongs to a parent command.",
                                inputSchema={"type": "object", "properties": {}, "additionalProperties": False}))
        return schemas

    threading.Thread(target=read_stream, args=(sys.stdin.buffer, "client"), daemon=True).start()
    try:
        while True:
            if child is not None and automatic and not pending and time.monotonic() - last_activity >= idle_seconds:
                dispose("desktop_expired: Idle desktop released. Its windows and sessions no longer exist. Retry with fresh discovery to acquire a new desktop.")
            if child is not None and not ready and time.monotonic() - started_at > 30:
                dispose("desktop_lost: Native MCP initialization timed out.")
            try:
                source, line = events.get(timeout=0.1)
            except queue.Empty:
                continue
            if source != "client" and source is not child:
                continue  # Output/EOF from an already retired native process.
            if line is None:
                if source == "client":
                    return 0
                dispose("desktop_lost: Native MCP process exited. Retry with fresh discovery to acquire a new desktop.")
                continue
            try:
                message = json.loads(line)
            except (ValueError, UnicodeError):
                if source == "client":
                    send(dict(jsonrpc="2.0", id=None, error={"code": -32700, "message": "Invalid JSON"}))
                    continue
                dispose("desktop_lost: Invalid native MCP response; acquire a fresh desktop.")
                continue
            if source is child:
                if not ready:
                    if "method" in message:
                        send(message)
                        continue
                    if message.get("id") != "cua-pool-initialize" or "error" in message:
                        dispose("desktop_lost: Native MCP initialization failed.")
                        continue
                    ready = True
                    try:
                        child.stdin.write(b'{"jsonrpc":"2.0","method":"notifications/initialized"}\n')
                        for queued in waiting:
                            child.stdin.write(queued)
                        waiting.clear()
                        child.stdin.flush()
                    except OSError:
                        dispose("desktop_lost: Native MCP connection failed during initialization.")
                    continue
                if "id" in message and "method" not in message:
                    pending.pop(message["id"], None)
                    last_activity = time.monotonic()
                send(message)  # Preserve native image and structured content.
                continue
            identifier = message.get("id")
            method = message.get("method")
            try:
                if method == "initialize":
                    initialize = message
                    guidance = Path(config["guide"]).read_text() + "\n\n" if config.get("guide") else ""
                    result = dict(protocolVersion=message.get("params", {}).get("protocolVersion", "2024-11-05"),
                                  capabilities={"tools": {}}, serverInfo={"name": "cua-pool", "version": "1"},
                                  instructions=guidance + f"Cua tools use a private leased X11 desktop. Use exact window targets, fresh snapshots and verified outcomes. Call {release_tool} when GUI work is finished. Automatically owned desktops expire after {idle_seconds} idle seconds with no pending requests. After release or expiry, windows and session IDs are invalid: acquire through a fresh discovery call. A lease owned by cua-pool exec lasts until that command exits.")
                elif method == "tools/list":
                    result = {"tools": tools()}
                elif method in ("resources/list", "resources/templates/list", "prompts/list"):
                    result = {"resources/list": {"resources": []},
                              "resources/templates/list": {"resourceTemplates": []},
                              "prompts/list": {"prompts": []}}[method]
                elif method == "ping":
                    result = {}
                elif method == "tools/call" and message.get("params", {}).get("name") == release_tool:
                    if not automatic:
                        raise PoolError("parent_owned", "The parent command owns this lease; finish that command to release it")
                    if pending:
                        raise PoolError("desktop_busy", "Wait for pending requests before releasing the desktop")
                    release_error = dispose()
                    if release_error is not None:
                        raise release_error
                    reset_reason = None
                    result = {"content": [{"type": "text", "text": "Desktop released. Discover fresh windows on the next GUI call."}]}
                elif method == "tools/call":
                    if initialize is None:
                        raise PoolError("not_initialized", "Initialize MCP before calling tools")
                    if reset_reason:
                        reason, reset_reason = reset_reason, None
                        raise PoolError("desktop_reset", reason)
                    if child is None:
                        desc = (request(root, "acquire", name=args.name, wait=args.wait) if automatic else
                                request(root, "resolve", lease=os.environ["CUA_POOL_LEASE"]))
                        child = start_mcp(config, args, desc)
                        started_at = time.monotonic()
                        native_initialize = dict(initialize, id="cua-pool-initialize")
                        child.stdin.write((json.dumps(native_initialize) + "\n").encode())
                        child.stdin.flush()
                        threading.Thread(target=read_stream, args=(child.stdout, child), daemon=True).start()
                    pending[identifier] = True
                    last_activity = time.monotonic()
                    if ready:
                        child.stdin.write(line)
                        child.stdin.flush()
                    else:
                        waiting.append(line)
                    continue
                elif child is not None:
                    if ready:
                        child.stdin.write(line)
                        child.stdin.flush()
                    else:
                        waiting.append(line)
                    continue
                elif identifier is None:
                    continue
                else:
                    send(dict(jsonrpc="2.0", id=identifier, error={"code": -32601, "message": "Method not found"}))
                    continue
                if identifier is not None:
                    send(dict(jsonrpc="2.0", id=identifier, result=result))
            except PoolError as error:
                tool_result(identifier, json.dumps({"code": error.code, "error": str(error)}), True)
            except (BrokenPipeError, OSError) as error:
                # The failed call may have executed. Never replay it on a new desktop.
                if identifier not in pending:
                    tool_result(identifier, str(error), True)
                dispose("desktop_lost: Native MCP connection failed. Observe fresh state before retrying.")
    finally:
        dispose()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, type=Path)
    sub = parser.add_subparsers(dest="operation", required=True)
    sub.add_parser("serve")
    sub.add_parser("status")
    for name in ("acquire", "exec", "mcp"):
        command = sub.add_parser(name)
        command.add_argument("--name", default="task" if name != "mcp" else "mcp")
        command.add_argument("--wait", type=float, default=0)
        if name == "exec":
            command.add_argument("command", nargs=argparse.REMAINDER)
    view = sub.add_parser("view")
    view.add_argument("--slot", type=int, help="Watch a slot from status without needing its lease token")
    view.add_argument("lease", nargs="?")
    view.add_argument("command", nargs=argparse.REMAINDER)
    for name in ("release", "renew", "run", "browser", "call"):
        command = sub.add_parser(name)
        command.add_argument("lease")
        if name in ("run", "browser", "call"):
            command.add_argument("command", nargs=argparse.REMAINDER)
    sub.add_parser("driver").add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    config = json.loads(args.config.read_text())
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
    root = Path(os.environ.get("CUA_POOL_ROOT", str(runtime / config["runtimeDirectory"])))
    op = args.operation
    if op == "serve":
        serve(config, root)
        return 0
    if op == "status":
        print(json.dumps(request(root, op)))
        return 0
    if op == "mcp":
        return mcp(config, root, args)
    if op == "acquire":
        print(json.dumps(request(root, op, name=args.name, wait=args.wait)))
        return 0
    if op in ("release", "renew"):
        print(json.dumps(request(root, op, lease=args.lease)))
        return 0
    automatic = op in ("exec", "mcp") and not os.environ.get("CUA_POOL_LEASE")
    if automatic:
        desc = request(root, "acquire", name=args.name, wait=args.wait)
    elif op == "view" and args.slot is not None:
        desc = request(root, "watch", slot=args.slot)
    else:
        token = getattr(args, "lease", None) or os.environ.get("CUA_POOL_LEASE")
        if not token:
            raise PoolError("lease_required", "Acquire a lease or use cua-pool exec/mcp")
        desc = request(root, "resolve", lease=token)
    try:
        command = getattr(args, "command", [])
        if command[:1] == ["--"]:
            command = command[1:]
        if op == "mcp":
            command = [config["driver"], "mcp", "--socket", desc["socket"]]
        elif op == "driver":
            if not command:
                command = ["--help"]
            if command[0] in ("call", "mcp"):
                if "--socket" in command:
                    index = command.index("--socket")
                    if index + 1 >= len(command) or command[index + 1] != desc["socket"]:
                        raise PoolError("socket_override", "Do not override a leased driver's socket")
                    del command[index:index + 2]
                if any(arg.startswith("--socket=") for arg in command) or "--socket" in command:
                    raise PoolError("socket_override", "Do not override a leased driver's socket")
                command = [command[0], "--socket", desc["socket"], *command[1:]]
            elif command[0] not in ("describe", "list-tools", "--help", "--version", "manifest"):
                raise PoolError("unsupported_command", "Use call or mcp on a leased driver")
            command = [config["driver"], *command]
        elif op == "call":
            if not command:
                raise PoolError("tool_required", "Specify a driver tool and optional JSON arguments")
            command = [config["driver"], "call", "--socket", desc["socket"], *command]
        elif op == "browser":
            if any(arg.startswith(("--user-data-dir", "--profile-directory")) for arg in command):
                raise PoolError("profile_override", "Each lease owns its own browser profile")
            command = [config["chromium"], "--user-data-dir=" + desc["profile"],
                       "--force-renderer-accessibility", "--ozone-platform=x11",
                       "--password-store=gnome-libsecret", "--no-first-run",
                       "--no-default-browser-check", *command]
        elif op == "view":
            # The human viewer belongs on the caller's graphical session.
            return subprocess.call([config["viewer"], *command,
                                    str(Path(desc["runtime"]) / "vnc.sock")])
        if not command:
            raise PoolError("command_required", "Supply a command after --")
        return execute(config, root, desc, command)
    finally:
        if automatic:
            request(root, "release", lease=desc["lease"])


if __name__ == "__main__":
    def terminate(signum, _frame):
        raise SystemExit(128 + signum)
    signal.signal(signal.SIGTERM, terminate)
    try:
        sys.exit(main())
    except PoolError as error:
        print(json.dumps(dict(ok=False, code=error.code, error=str(error))), file=sys.stderr)
        sys.exit(2)
