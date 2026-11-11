#!/usr/bin/env python3
"""Exercise Cua against a disposable dialog on the isolated agent desktop."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zenity", required=True)
    parser.add_argument("--socket", help="Explicit daemon socket for isolated validation")
    args = parser.parse_args()
    session = f"cua-smoke-{os.getpid()}"

    def call(tool, **kwargs):
        command = ["cua-driver", "call"]
        if args.socket:
            command += ["--socket", args.socket]
        result = subprocess.run(
            command + [tool, json.dumps(dict(session=session, **kwargs))],
            capture_output=True, text=True, timeout=35,
        )
        if result.returncode:
            raise RuntimeError(f"{tool}: {result.stdout} {result.stderr}")
        value = json.loads(result.stdout)
        if value.get("ok") is False or "error" in value:
            raise RuntimeError(f"{tool}: {value}")
        return value

    def entry(state):
        matches = [e for e in state.get("elements", [])
                   if e.get("role", "").lower() in
                   ("text", "entry", "text field", "textfield", "text box")]
        if len(matches) != 1:
            raise RuntimeError(f"Expected one editable entry, got {state}")
        return matches[0]

    deadline = time.monotonic() + 15
    while True:
        try:
            call("list_windows")
            break
        except RuntimeError:
            if time.monotonic() >= deadline:
                raise
            time.sleep(0.2)

    # No credentials or user documents are read. Artifacts disappear on exit.
    with tempfile.TemporaryDirectory(prefix="cua-smoke-") as directory:
        output = Path(directory) / "submitted.txt"
        with output.open("w+") as stream:
            app = subprocess.Popen(
                ["cua-agent-run", args.zenity, "--entry", "--title=CUA smoke test",
                 "--text=Disposable computer-use validation", "--ok-label=Submit CUA test"],
                stdout=stream, stderr=subprocess.DEVNULL,
            )
            try:
                deadline = time.monotonic() + 15
                window = None
                while time.monotonic() < deadline:
                    windows = call("list_windows").get("windows", [])
                    window = next((w for w in windows if w.get("pid") == app.pid), None)
                    if window:
                        break
                    if app.poll() is not None:
                        raise RuntimeError("Test dialog exited before discovery")
                    time.sleep(0.2)
                if window is None:
                    raise RuntimeError("Driver cannot discover the agent desktop dialog")
                target = dict(pid=app.pid, window_id=window["window_id"])
                # A mapped window can precede the toolkit's AT-SPI registration.
                deadline = time.monotonic() + 10
                while True:
                    state = call("get_window_state", **target, include_screenshot=False,
                                 tree_format="elements", max_elements=50)
                    try:
                        field = entry(state)
                        break
                    except RuntimeError:
                        if time.monotonic() >= deadline:
                            raise
                        time.sleep(0.2)
                print("PASS window discovery and accessible entry")

                # Verify semantic editing with non-ASCII text, independently
                # of raw key events and the action's own success acknowledgement.
                expected = "CUA café 123"
                call("run_steps", **target, steps=[{
                    "tool": "set_value", "args": {
                        "element_token": field["element_token"], "value": expected,
                    },
                }], observe={})
                state = call("get_window_state", **target, include_screenshot=False,
                             tree_format="elements", max_elements=50)
                field = entry(state)
                if field.get("value") != expected:
                    raise RuntimeError(f"Semantic value readback failed: {field}")
                print("PASS semantic editing and Unicode readback")

                # The dialog initially focuses its only entry. Ctrl+A plus
                # typing proves key delivery, with readback before submission.
                expected = "CUA keyboard 456"
                call("run_steps", **target, delivery_mode="foreground", steps=[
                    {"tool": "press_key", "args": {"key": "a", "modifiers": ["ctrl"]}},
                    {"tool": "type_text", "args": {"text": expected}},
                ], observe={})
                state = call("get_window_state", **target, include_screenshot=False,
                             tree_format="elements", max_elements=50)
                if entry(state).get("value") != expected:
                    raise RuntimeError(f"Keyboard value readback failed: {state}")
                print("PASS foreground shortcut and keyboard input")

                call("run_steps", **target, delivery_mode="foreground", steps=[
                    {"tool": "press_key", "args": {"key": "a", "modifiers": ["ctrl"]}},
                    {"tool": "press_key", "args": {"key": "c", "modifiers": ["ctrl"]}},
                    {"tool": "press_key", "args": {"key": "backspace"}},
                    {"tool": "press_key", "args": {"key": "v", "modifiers": ["ctrl"]}},
                ], observe={})
                state = call("get_window_state", **target, include_screenshot=False,
                             tree_format="elements", max_elements=50)
                if entry(state).get("value") != expected:
                    raise RuntimeError(f"Clipboard round trip failed: {state}")
                print("PASS isolated clipboard round trip")

                # Zenity's dialog is fixed-size. Check movement here; resize is
                # exercised separately against the resizable browser fixture.
                bounds = window["bounds"]
                call("set_window_frame", **target, x=80, y=90,
                     width=bounds["width"], height=bounds["height"])
                moved = next(w for w in call("list_windows")["windows"]
                             if w["window_id"] == target["window_id"])
                for name, expected_bound in dict(x=80, y=90).items():
                    if abs(moved["bounds"][name] - expected_bound) > 8:
                        raise RuntimeError(f"Window geometry readback failed: {moved}")
                print("PASS window move readback")

                screenshot = Path(directory) / "window.png"
                call("get_window_state", **target, include_accessibility_tree=False,
                     screenshot_out_file=str(screenshot))
                if screenshot.read_bytes()[:8] != b"\x89PNG\r\n\x1a\n":
                    raise RuntimeError("Window screenshot was not a PNG")
                print("PASS window capture")

                state = call("get_window_state", **target, include_screenshot=False,
                             tree_format="elements", max_elements=50)
                button = next(e for e in state["elements"]
                              if e.get("role") == "button" and e.get("label") == "Submit CUA test")
                call("run_steps", **target, delivery_mode="background", steps=[
                    {"tool": "click", "args": {"element_token": button["element_token"]}},
                ])
                if app.wait(timeout=10) != 0:
                    raise RuntimeError("Dialog did not submit successfully")
                stream.flush()
                if output.read_text().strip() != expected:
                    raise RuntimeError("Submitted value did not match typed text")
                print("PASS submission and independent output verification")
            finally:
                if app.poll() is None:
                    app.terminate()
                    try:
                        app.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        app.kill()
                        app.wait()
                try:
                    call("end_session")
                except RuntimeError as error:
                    print(f"Session cleanup failed: {error}", file=sys.stderr)


if __name__ == "__main__":
    main()
