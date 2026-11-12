"""Lease protocol tests; the live smoke test covers the actual GUI runtimes."""
import concurrent.futures
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import Mock, patch

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("cua_pool", sys.argv.pop(1))
pool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pool)


class Leases(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.states = {}
        self.lock = threading.Lock()
        self.fail_start = False
        self.sequence = 0
        def systemctl(*args, check=True):
            with self.lock:
                if args[0] == "start":
                    if self.fail_start:
                        raise pool.PoolError("service_failed", "injected startup failure")
                    self.sequence += 1
                    self.states[args[1]] = {"ActiveState": "active", "InvocationID": str(self.sequence)}
                elif args[0] == "stop":
                    if args[1] == "cua-pool.slice":
                        self.states.clear()
                    else:
                        unit = args[1].replace("slice", "service")
                        self.states.pop(unit, None)
                elif args[0] == "show":
                    state = self.states.get(args[1], {"ActiveState": "inactive", "InvocationID": ""})
                    if "--value" in args:
                        return state["InvocationID"]
                    return "\n".join(f"{key}={value}" for key, value in state.items())
                return ""
        pool.systemctl = systemctl
        config = dict(slots=[dict(id=i, slice=f"slot{i}.slice", unit=f"slot{i}.service",
                                  run="/unused", environment={"DISPLAY": f":{48+i}"}) for i in (1, 2)],
                      workspaceRoot=str(self.root / "tasks"), idleSeconds=100)
        self.broker = pool.Broker(config, self.root)

    def tearDown(self):
        self.broker.close()
        self.broker.monitor.join(timeout=2)
        self.directory.cleanup()

    def test_concurrent_exclusivity_and_exhaustion(self):
        barrier = threading.Barrier(2)
        def acquire(number):
            barrier.wait()
            return self.broker.acquire(f"task-{number}", 0)
        with concurrent.futures.ThreadPoolExecutor(2) as executor:
            leases = list(executor.map(acquire, (1, 2)))
        for key in ("lease", "slot", "display", "socket", "profile", "workspace"):
            self.assertNotEqual(leases[0][key], leases[1][key])
        with self.assertRaisesRegex(pool.PoolError, "All desktops"):
            self.broker.acquire("third", 0)
        with concurrent.futures.ThreadPoolExecutor(1) as executor:
            waiting = executor.submit(self.broker.acquire, "queued", 3)
            time.sleep(.1)
            self.assertFalse(waiting.done())
            self.broker.release(leases[0]["lease"])
            replacement = waiting.result(timeout=3)
        self.assertEqual(replacement["slot"], leases[0]["slot"])
        self.assertNotEqual(replacement["lease"], leases[0]["lease"])
        with self.assertRaises(pool.PoolError):
            self.broker.resolve(leases[0]["lease"])
        self.assertEqual(self.broker.resolve(leases[1]["lease"])["slot"], leases[1]["slot"])

    def test_release_preserves_outputs_and_removes_profiles(self):
        lease = self.broker.acquire("outputs", 0)
        (Path(lease["workspace"]) / "result.txt").write_text("keep")
        self.broker.release(lease["lease"])
        self.assertEqual((Path(lease["workspace"]) / "result.txt").read_text(), "keep")
        self.assertFalse(Path(lease["profile"]).exists())
        self.assertFalse((Path(lease["runtime"]) / "lease.id").exists())
        self.assertFalse(self.broker.release(lease["lease"])["released"])
        replacement = self.broker.acquire("replacement", 0)
        self.assertNotEqual(lease["socket"], replacement["socket"])
        self.assertEqual((Path(replacement["runtime"]) / "lease.id").read_text().strip(), replacement["lease"])

    def test_slow_desktop_does_not_block_another_slot(self):
        original = pool.systemctl
        started, proceed = threading.Event(), threading.Event()
        def slow(*args, **kwargs):
            if args[:2] == ("start", "slot1.service"):
                started.set()
                self.assertTrue(proceed.wait(timeout=3))
            return original(*args, **kwargs)
        pool.systemctl = slow
        with concurrent.futures.ThreadPoolExecutor(2) as executor:
            first = executor.submit(self.broker.acquire, "slow", 0)
            self.assertTrue(started.wait(timeout=2))
            try:
                second = executor.submit(self.broker.acquire, "fast", 0).result(timeout=2)
                self.assertEqual(second["slot"], 2)
            finally:
                proceed.set()
            first.result(timeout=2)
        pool.systemctl = original

    def test_failed_start_releases_reservation(self):
        self.fail_start = True
        with self.assertRaises(pool.PoolError):
            self.broker.acquire("failed", 0)
        self.assertEqual(self.broker.status(), [])
        self.fail_start = False
        self.assertEqual(self.broker.acquire("next", 0)["slot"], 1)

    def test_restarted_desktop_invalidates_lease(self):
        lease = self.broker.acquire("old", 0)
        self.states["slot1.service"]["InvocationID"] = "different"
        with self.assertRaisesRegex(pool.PoolError, "old task state"):
            self.broker.resolve(lease["lease"])
        self.assertEqual(self.broker.status(), [])

    def test_idle_expiration(self):
        self.broker.config["idleSeconds"] = .1
        lease = self.broker.acquire("abandoned", 0)
        deadline = time.monotonic() + 3
        while self.broker.status() and time.monotonic() < deadline:
            time.sleep(.1)
        with self.assertRaises(pool.PoolError):
            self.broker.resolve(lease["lease"])

    def test_cleanup_failure_quarantines_slot(self):
        lease = self.broker.acquire("cleanup", 0)
        original = pool.systemctl
        def broken(*args, **kwargs):
            if args[0] == "stop":
                raise pool.PoolError("service_failed", "injected stop failure")
            return original(*args, **kwargs)
        pool.systemctl = broken
        with self.assertRaises(pool.PoolError):
            self.broker.release(lease["lease"])
        self.assertEqual(self.broker.status()[0]["state"], "quarantined")
        self.assertEqual(self.broker.acquire("other", 0)["slot"], 2)
        pool.systemctl = original

    def test_restart_cleans_abandoned_state_preserving_outputs(self):
        lease = self.broker.acquire("crashed", 0)
        workspace = Path(lease["workspace"]).parent
        for name in ("work", "downloads", "profile", "cache", "config", "data"):
            (workspace / name / "marker").write_text(name)
        # Simulate loss of in-memory records, including the runtime directory.
        self.broker.closed = True
        self.broker.monitor.join(timeout=2)
        pool.shutil.rmtree(self.root / "slots")
        self.states["removed-slot.service"] = {"ActiveState": "active", "InvocationID": "old"}
        self.broker = pool.Broker(self.broker.config, self.root)
        self.assertNotIn("removed-slot.service", self.states)
        for name in ("work", "downloads"):
            self.assertEqual((workspace / name / "marker").read_text(), name)
        for name in ("profile", "cache", "config", "data"):
            self.assertFalse((workspace / name).exists())
        self.assertEqual(self.broker.acquire("new", 0)["slot"], 1)
        with self.assertRaises(pool.PoolError):
            self.broker.resolve(lease["lease"])

    def test_startup_stop_failure_preserves_state_and_refuses_start(self):
        lease = self.broker.acquire("running", 0)
        original = pool.systemctl
        def broken(*args, **kwargs):
            if args[0] == "stop":
                raise pool.PoolError("service_failed", "cannot stop old processes")
            return original(*args, **kwargs)
        pool.systemctl = broken
        try:
            with self.assertRaises(pool.PoolError):
                pool.Broker(self.broker.config, self.root)
            self.assertTrue(Path(lease["profile"]).exists())
        finally:
            pool.systemctl = original

    def test_cleanup_unlinks_symlinks_without_touching_target(self):
        lease = self.broker.acquire("symlink", 0)
        target = self.root / "keep"
        target.mkdir()
        (target / "marker").write_text("keep")
        profile = Path(lease["profile"])
        pool.shutil.rmtree(profile)
        profile.symlink_to(target, target_is_directory=True)
        self.broker.release(lease["lease"])
        self.assertFalse(profile.is_symlink())
        self.assertEqual((target / "marker").read_text(), "keep")

    def test_cleanup_error_is_not_silently_ignored(self):
        lease = self.broker.acquire("cleanup", 0)
        original = pool.clean_task
        def broken(_workspace):
            raise PermissionError("injected profile cleanup failure")
        pool.clean_task = broken
        try:
            with self.assertRaises(PermissionError):
                self.broker.release(lease["lease"])
            self.assertEqual(self.broker.status()[0]["state"], "quarantined")
        finally:
            pool.clean_task = original

    def test_expiration_cannot_release_a_renewed_lease(self):
        lease = self.broker.acquire("renewed", 0)
        self.broker.leases[lease["lease"]]["touched"] -= 200
        self.broker.leases[lease["lease"]]["touched"] = time.monotonic()
        self.assertFalse(self.broker.release(lease["lease"], expired_only=True)["released"])
        self.assertEqual(self.broker.resolve(lease["lease"])["lease"], lease["lease"])


class Execution(unittest.TestCase):
    def execute(self, code, resolve_error=None):
        child = Mock()
        child.wait.return_value = code
        child.poll.return_value = code
        desc = dict(slice="cua-test-execution.slice", unit="desktop.service",
                    environment={}, runtime="/unused", run="/unused/run",
                    idleSeconds=3600, lease="test")
        with patch.object(pool.subprocess, "Popen", return_value=child), \
                patch.object(pool, "request", side_effect=resolve_error) as request:
            result = pool.execute({"unsetEnvironment": []}, Path("/unused"), desc, ["task"])
            if code == 0:
                request.assert_called_once_with(Path("/unused"), "resolve", lease="test")
            else:
                request.assert_not_called()
            return result

    def test_success_requires_a_valid_lease(self):
        self.assertEqual(self.execute(0), 0)

    def test_external_stop_before_first_heartbeat_cannot_report_success(self):
        # systemd-run reports 0 on an external stop. No heartbeat has run yet.
        for code in ("lease_lost", "desktop_lost", "broker_unavailable"):
            with self.subTest(code=code), self.assertRaises(pool.PoolError) as error:
                self.execute(0, pool.PoolError(code, "injected lease validation failure"))
            self.assertEqual(error.exception.code, "lease_lost")

    def test_preserves_command_failure(self):
        self.assertEqual(self.execute(7), 7)


unittest.main()
