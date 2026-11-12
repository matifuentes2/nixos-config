#!/usr/bin/env python3
"""Prove concurrent keyboard, clipboard and discovery isolation on two leases."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zenity", required=True)
    args = parser.parse_args()
    leases = []
    def command(*args):
        result = subprocess.run(["cua-pool", *args], capture_output=True, text=True, timeout=100)
        if result.returncode:
            raise RuntimeError(result.stderr[:2000])
        return json.loads(result.stdout)
    def call(lease, tool, **kwargs):
        result = command("call", lease["lease"], tool, json.dumps(dict(session="pool-smoke", **kwargs)))
        if result.get("ok") is False or "error" in result:
            raise RuntimeError(f"{tool} failed: {result.get('steps', result.get('error'))}")
        return result
    def wait(predicate):
        deadline = time.monotonic() + 10
        while True:
            result = predicate()
            if result:
                return result
            if time.monotonic() > deadline:
                raise RuntimeError("Timed out waiting for test window")
            time.sleep(.2)
    def read(lease):
        return call(lease, "get_window_state", **lease["target"], tree_format="elements",
                    include_screenshot=False, max_elements=60)
    def entry(state):
        return next(e for e in state["elements"] if e.get("role", "").lower() in
                    ("entry", "text", "text field", "textfield", "text box"))
    def steps(lease, *items):
        return call(lease, "run_steps", **lease["target"], delivery_mode="foreground", steps=list(items))
    def key(name, **kwargs):
        return dict(tool="press_key", args=dict(key=name, **kwargs))
    try:
        # Record each lease as it arrives so a partial acquisition is cleaned up.
        with ThreadPoolExecutor(2) as workers:
            futures = [workers.submit(command, "acquire", "--name", f"isolation-test-{i}") for i in range(2)]
            error = None
            for future in futures:
                try:
                    leases.append(future.result())
                except Exception as failure:
                    error = failure
            if error:
                raise error
        for name in ("slot", "display", "socket", "profile", "workspace"):
            assert leases[0][name] != leases[1][name], name
        for i, lease in enumerate(leases):
            lease["title"] = f"CUA isolated task {i}"
            lease["text"] = f"Task {i} café clipboard"
            call(lease, "launch_app", name=args.zenity,
                 additional_arguments=["--entry", "--title=" + lease["title"], "--text=Disposable isolation test"])
            window = wait(lambda: next((w for w in call(lease, "list_windows")["windows"]
                                       if w["title"] == lease["title"]), None))
            lease["target"] = dict(pid=window["pid"], window_id=window["window_id"])
            try:
                wait(lambda: any(e.get("role", "").lower() in
                                 ("entry", "text", "text field", "textfield", "text box")
                                 for e in read(lease).get("elements", [])))
            except RuntimeError:
                raise RuntimeError(f"Accessible entry missing: {read(lease)}") from None
        for lease in leases:
            titles = [w["title"] for w in call(lease, "list_windows")["windows"]]
            assert all(other["title"] not in titles for other in leases if other is not lease)
        print("PASS independent displays, sockets, profiles and window discovery", flush=True)
        def copy(lease):
            steps(lease, dict(tool="type_text", args=dict(text=lease["text"])),
                  key("a", modifiers=["ctrl"]), key("c", modifiers=["ctrl"]))
        def paste_and_check(lease):
            steps(lease, key("backspace"), key("v", modifiers=["ctrl"]))
            assert entry(read(lease)).get("value") == lease["text"]
        with ThreadPoolExecutor(2) as workers:
            list(workers.map(copy, leases))
            # Both copies finish before either paste, so a shared clipboard
            # would make at least one distinct-value assertion fail.
            list(workers.map(paste_and_check, leases))
        print("PASS concurrent foreground keyboard and distinct clipboard values", flush=True)
        first = leases.pop(0)
        command("release", first["lease"])
        assert not Path(first["profile"]).exists()
        assert Path(first["workspace"]).is_dir()
        result = subprocess.run(["cua-pool", "call", first["lease"], "list_windows"], capture_output=True)
        assert result.returncode != 0
        assert entry(read(leases[0])).get("value") == leases[0]["text"]
        print("PASS stale-token refusal, profile cleanup and surviving task independence", flush=True)
    finally:
        for lease in leases:
            command("release", lease["lease"])


if __name__ == "__main__":
    main()
