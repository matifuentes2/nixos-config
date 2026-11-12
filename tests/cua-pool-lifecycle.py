"""Exercise the real MCP proxy over pipes with a controlled native server."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import queue
import subprocess
import sys
import tempfile
import threading
import time
import unittest

sys.dont_write_bytecode = True


def load_pool(path):
    spec = importlib.util.spec_from_file_location("cua_pool", path)
    pool = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(pool)
    return pool


def native():
    lock = threading.Lock()
    def respond(message):
        if message.get("params", {}).get("name") == "crash":
            os._exit(1)
        if message.get("params", {}).get("name") == "slow":
            time.sleep(.8)
        if message["method"] == "initialize":
            result = {"protocolVersion": "2024-11-05", "capabilities": {"tools": {}}}
        else:
            result = {"content": [{"type": "image", "data": "fixture", "mimeType": "image/png"}],
                      "structuredContent": {"pid": os.getpid()}}
        with lock:
            print(json.dumps(dict(jsonrpc="2.0", id=message["id"], result=result)), flush=True)
    for line in sys.stdin:
        message = json.loads(line)
        if "id" in message:
            threading.Thread(target=respond, args=(message,)).start()
        elif message.get("method") == "notifications/cancelled":
            with lock:
                print(json.dumps(dict(jsonrpc="2.0", method="test/cancelled", params=message["params"])), flush=True)


def harness(script, directory, borrowed):
    pool = load_pool(script)
    sequence = 0
    def request(_root, op, **kwargs):
        nonlocal sequence
        with (directory / "events").open("a") as log:
            log.write(op + "\n")
        if (directory / "broker-down").exists():
            raise pool.PoolError("broker_unavailable", "injected broker outage")
        if op == "release" and (directory / "cleanup-failed").exists():
            raise pool.PoolError("service_failed", "injected quarantine")
        if op == "acquire":
            sequence += 1
        return {"lease": str(sequence)}
    pool.request = request
    pool.start_mcp = lambda *_args: subprocess.Popen(
        [sys.executable, __file__, "--native"], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    if borrowed:
        os.environ["CUA_POOL_LEASE"] = "parent"
    else:
        os.environ.pop("CUA_POOL_LEASE", None)
    return pool.mcp({"mcpIdleSeconds": .3}, directory,
                    argparse.Namespace(name="test", wait=0, config="unused"))


class Lifecycle(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.process = None
        self.messages = queue.Queue()
        self.sequence = 0

    def tearDown(self):
        if self.process:
            self.process.stdin.close()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()
                self.fail("Proxy failed to exit on EOF")
            self.reader.join(timeout=2)
            self.assertEqual(self.process.returncode, 0, self.process.stderr.read())
            self.process.stdout.close()
            self.process.stderr.close()
        self.directory.cleanup()

    def start(self, borrowed=False):
        self.process = subprocess.Popen([sys.executable, __file__, "--harness", SCRIPT,
                                         str(self.root), str(int(borrowed))],
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        def read():
            for line in self.process.stdout:
                self.messages.put(json.loads(line))
        self.reader = threading.Thread(target=read, daemon=True)
        self.reader.start()
        self.send("initialize", {"protocolVersion": "2024-11-05"})
        self.receive()

    def send(self, method="tools/call", params=None):
        self.sequence += 1
        self.process.stdin.write((json.dumps(dict(jsonrpc="2.0", id=self.sequence,
                                                  method=method, params=params or {})) + "\n").encode())
        self.process.stdin.flush()
        return self.sequence

    def call(self, name="fast"):
        return self.send(params={"name": name, "arguments": {}})

    def receive(self):
        return self.messages.get(timeout=5)

    def events(self):
        file = self.root / "events"
        return file.read_text().splitlines() if file.exists() else []

    def wait_release(self):
        deadline = time.monotonic() + 3
        while "release" not in self.events() and time.monotonic() < deadline:
            time.sleep(.02)
        self.assertIn("release", self.events())

    def test_idle_releases_and_requires_acknowledgement_before_reacquisition(self):
        self.start()
        self.assertEqual(self.events(), [])
        self.call()
        first = self.receive()["result"]
        self.assertEqual(first["content"][0]["type"], "image")
        self.wait_release()
        self.send("ping")
        self.assertEqual(self.receive()["result"], {})
        self.call()
        self.assertIn("desktop_expired", self.receive()["result"]["content"][0]["text"])
        self.assertEqual(self.events().count("acquire"), 1)
        self.call()
        second = self.receive()["result"]
        self.assertNotEqual(first["structuredContent"], second["structuredContent"])
        self.assertEqual(self.events().count("acquire"), 2)

    def test_pending_calls_prevent_idle_release_and_explicit_release(self):
        self.start()
        first = self.call("slow")
        second = self.call("slow")
        time.sleep(.45)
        self.assertNotIn("release", self.events())
        release = self.call("pool_release_desktop")
        response = self.receive()
        self.assertEqual(response["id"], release)
        self.assertTrue(response["result"]["isError"])
        responses = {self.receive()["id"], self.receive()["id"]}
        self.assertEqual(responses, {first, second})
        self.wait_release()

    def test_explicit_release_reacquires_and_eof_cleans_up(self):
        self.start()
        self.call()
        self.receive()
        self.call("pool_release_desktop")
        self.assertNotIn("isError", self.receive()["result"])
        self.assertEqual(self.events().count("release"), 1)
        self.call()
        self.receive()
        self.process.stdin.close()
        self.process.wait(timeout=5)
        self.assertEqual(self.events().count("release"), 2)
        # tearDown can close an already closed stream.

    def test_parent_owned_lease_is_never_released_by_proxy(self):
        self.start(borrowed=True)
        self.call()
        self.receive()
        time.sleep(.5)
        self.assertNotIn("release", self.events())
        self.call("pool_release_desktop")
        self.assertIn("parent_owned", self.receive()["result"]["content"][0]["text"])
        self.process.stdin.close()
        self.process.wait(timeout=5)
        self.assertNotIn("release", self.events())

    def test_native_failure_fails_pending_request_without_replaying_it(self):
        self.start()
        identifier = self.call("crash")
        response = self.receive()
        self.assertEqual(response["id"], identifier)
        self.assertTrue(response["result"]["isError"])
        self.wait_release()
        self.call()
        self.assertIn("desktop_lost", self.receive()["result"]["content"][0]["text"])
        self.assertEqual(self.events().count("acquire"), 1)
        self.call()
        self.assertEqual(self.receive()["result"]["content"][0]["type"], "image")

    def test_cancellation_is_forwarded_while_a_tool_is_pending(self):
        self.start()
        identifier = self.call("slow")
        self.process.stdin.write((json.dumps(dict(jsonrpc="2.0", method="notifications/cancelled",
                                                  params={"requestId": identifier})) + "\n").encode())
        self.process.stdin.flush()
        self.assertEqual(self.receive()["method"], "test/cancelled")
        self.assertEqual(self.receive()["id"], identifier)

    def test_broker_outage_during_native_failure_keeps_connection_usable(self):
        self.start()
        self.call()
        self.receive()
        (self.root / "broker-down").touch()
        identifier = self.call("crash")
        response = self.receive()
        self.assertEqual(response["id"], identifier)
        self.assertTrue(response["result"]["isError"])
        self.assertIn("Cleanup not confirmed", response["result"]["content"][0]["text"])
        self.send("ping")
        self.assertEqual(self.receive()["result"], {})
        self.call()
        self.assertIn("desktop_lost", self.receive()["result"]["content"][0]["text"])
        self.call()
        self.assertIn("broker_unavailable", self.receive()["result"]["content"][0]["text"])
        (self.root / "broker-down").unlink()
        self.call()
        self.assertEqual(self.receive()["result"]["content"][0]["type"], "image")
        self.assertEqual(self.events().count("acquire"), 3)

    def test_idle_release_failure_reports_state_loss_and_recovers(self):
        self.start()
        (self.root / "cleanup-failed").touch()
        self.call()
        self.receive()
        self.wait_release()
        self.send("ping")
        self.assertEqual(self.receive()["result"], {})
        self.call()
        response = self.receive()["result"]
        self.assertTrue(response["isError"])
        self.assertIn("desktop_expired", response["content"][0]["text"])
        self.assertIn("Cleanup not confirmed", response["content"][0]["text"])
        (self.root / "cleanup-failed").unlink()
        self.call()
        self.assertEqual(self.receive()["result"]["content"][0]["type"], "image")

    def test_explicit_release_does_not_claim_success_after_cleanup_failure(self):
        self.start()
        self.call()
        self.receive()
        (self.root / "cleanup-failed").touch()
        self.call("pool_release_desktop")
        response = self.receive()["result"]
        self.assertTrue(response["isError"])
        self.assertIn("service_failed", response["content"][0]["text"])
        self.call()
        self.assertIn("desktop_lost", self.receive()["result"]["content"][0]["text"])
        (self.root / "cleanup-failed").unlink()
        self.call()
        self.assertEqual(self.receive()["result"]["content"][0]["type"], "image")


if __name__ == "__main__":
    if sys.argv[1] == "--native":
        native()
    elif sys.argv[1] == "--harness":
        sys.exit(harness(sys.argv[2], Path(sys.argv[3]), bool(int(sys.argv[4]))))
    else:
        SCRIPT = sys.argv.pop(1)
        unittest.main()
