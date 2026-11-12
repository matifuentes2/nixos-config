"""Check real X11/WM/AT-SPI readiness with a delayed or failed session bus."""
import array
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import tempfile
import time


def check(desktop, run, true, fail):
    with tempfile.TemporaryDirectory(prefix="cua-ready-") as directory:
        root = Path(directory)
        runtime = root / "runtime"
        (runtime / "cua-agent").mkdir(parents=True, mode=0o700)
        notify = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        notify.bind(str(root / "notify"))
        notify.settimeout(0.1)
        env = dict(os.environ, HOME="/build/cua-home", XDG_RUNTIME_DIR=str(runtime),
                   NOTIFY_SOCKET=str(root / "notify"), DISPLAY=":47",
                   GDK_BACKEND="x11", GTK_A11Y="atspi", GSK_RENDERER="cairo",
                   ATSPI_DBUS_IMPLEMENTATION="dbus-daemon",
                   CUA_READINESS_TEST_FAIL="1" if fail else "0")
        for name in ("WAYLAND_DISPLAY", "DBUS_SESSION_BUS_ADDRESS", "AT_SPI_BUS_ADDRESS"):
            env.pop(name, None)
        started = time.monotonic()
        launcher = None if fail else subprocess.Popen([run, true], env=env)
        with (root / "desktop.log").open("w+") as log:
            app = subprocess.Popen([desktop], env=env, stdout=log, stderr=log,
                                   start_new_session=True)
            try:
                ready = False
                while time.monotonic() - started < 25:
                    try:
                        data, ancillary, _, _ = notify.recvmsg(4096, socket.CMSG_SPACE(16))
                        # systemd-notify's barrier is acknowledged by closing
                        # the fd it passes, just as the service manager does.
                        for level, kind, payload in ancillary:
                            if level == socket.SOL_SOCKET and kind == socket.SCM_RIGHTS:
                                fds = array.array("i")
                                fds.frombytes(payload[:len(payload) - len(payload) % fds.itemsize])
                                for fd in fds:
                                    os.close(fd)
                        if b"READY=1" in data.splitlines():
                            assert not fail, "Failed session announced readiness"
                            assert time.monotonic() - started >= 2, "Readiness preceded delayed bus"
                            assert (runtime / "cua-agent/bus-address").is_file(), "Premature readiness"
                            assert launcher.wait(timeout=15) == 0, "Early launcher did not wait for bus"
                            ready = True
                            break
                    except socket.timeout:
                        pass
                    if app.poll() is not None:
                        break
                if fail:
                    assert app.poll() is not None and app.returncode != 0, "Failed child not supervised"
                else:
                    assert ready and app.poll() is None, "Desktop never became ready"
                print("PASS", "failed session withheld readiness" if fail else "delayed session readiness and launcher")
            except Exception:
                log.seek(0)
                print(log.read(), file=sys.stderr)
                raise
            finally:
                if launcher is not None and launcher.poll() is None:
                    launcher.terminate()
                    launcher.wait(timeout=5)
                try:
                    os.killpg(app.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                app.wait(timeout=5)
                notify.close()


for failed in (False, True):
    check(*sys.argv[1:], fail=failed)
