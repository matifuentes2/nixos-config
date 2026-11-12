#!/usr/bin/env python3
"""Exercise native Cua input against a disposable Chromium profile and local page."""

import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time


def compact(value):
    """Never print embedded screenshots in an error response."""
    if isinstance(value, dict):
        return {k: compact(v) for k, v in value.items()
                if not k.startswith("screenshot") and k != "elements"}
    if isinstance(value, list):
        return [compact(v) for v in value]
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chromium", required=True)
    parser.add_argument("--fixture", required=True, type=Path)
    parser.add_argument("--socket", help="Explicit driver socket")
    parser.add_argument("--require-context-menu", action="store_true",
                        help="Fail if the popup does not expose accessible menu items")
    parser.add_argument("--artifacts", type=Path,
                        help="Keep diagnostic PNGs, states and browser log here on failure")
    args = parser.parse_args()
    session = f"cua-browser-smoke-{os.getpid()}"

    def call(tool, **kwargs):
        command = ["cua-driver", "call"]
        if args.socket:
            command += ["--socket", args.socket]
        result = subprocess.run(command + [tool, json.dumps(dict(session=session, **kwargs))],
                                capture_output=True, text=True, timeout=35)
        if result.returncode:
            raise RuntimeError(f"{tool}: {result.stderr[:1000]}")
        value = json.loads(result.stdout)
        if value.get("ok") is False or "error" in value:
            raise RuntimeError(f"{tool}: {compact(value)}")
        return value

    def wait_for(description, predicate, timeout=10):
        deadline = time.monotonic() + timeout
        while True:
            value = predicate()
            if value:
                return value
            if time.monotonic() >= deadline:
                raise RuntimeError(f"Timed out: {description}")
            time.sleep(0.2)

    def find(state, label):
        matches = [e for e in state.get("elements", []) if e.get("label") == label]
        if len(matches) != 1:
            raise RuntimeError(f"Expected one {label!r}, found {len(matches)}")
        return matches[0]

    def action(tool, **kwargs):
        return dict(tool=tool, args=kwargs)

    with tempfile.TemporaryDirectory(prefix="cua-browser-smoke-") as directory:
        root = Path(directory)
        profile = root / "profile"
        (profile / "Default").mkdir(parents=True)
        downloads = root / "downloads"
        downloads.mkdir()
        (profile / "Default/Preferences").write_text(json.dumps({
            "download": {"default_directory": str(downloads), "prompt_for_download": False},
        }))
        upload = root / "cua-upload.txt"
        upload.write_text("CUA upload verified\n")
        log = (root / "browser.log").open("w")
        app = subprocess.Popen([
            "cua-agent-run", args.chromium, f"--user-data-dir={profile}",
            "--class=CUASmoke", "--force-renderer-accessibility", "--ozone-platform=x11",
            "--no-first-run", "--no-default-browser-check", args.fixture.resolve().as_uri(),
        ], stdout=log, stderr=log, start_new_session=True)
        target = None
        chooser = None
        passed = False
        try:
            def discover():
                if app.poll() is not None:
                    raise RuntimeError("Chromium exited before discovery")
                return next((w for w in call("list_windows").get("windows", [])
                             if w.get("pid") == app.pid), None)

            window = wait_for("Chromium window", discover, timeout=15)
            target = dict(pid=app.pid, window_id=window["window_id"])

            def read(exact=None, name="current"):
                state = call("get_window_state", **(exact or target), tree_format="elements",
                             max_elements=200, screenshot_out_file=str(root / f"{name}.png"))
                (root / f"{name}.json").write_text(json.dumps(state))
                return state

            def steps(*items, exact=None):
                return call("run_steps", **(exact or target), delivery_mode="foreground",
                            steps=list(items))

            def click(state, label):
                return steps(action("click", element_token=find(state, label)["element_token"]))

            def expect_label(label):
                state = read()
                return state if any(e.get("label") == label for e in state.get("elements", [])) else None

            state = wait_for("page accessibility", lambda: expect_label("Message"))
            click(state, "Message")
            steps(action("type_text", text="CUA café 789"))
            state = read()
            steps(action("click", element_token=find(state, "Choice")["element_token"]),
                  action("press_key", key="down"), action("press_key", key="Return"))
            state = read()
            steps(action("click", element_token=find(state, "Enabled")["element_token"]),
                  action("click", element_token=find(state, "Submit test form")["element_token"]))
            wait_for("submitted form", lambda: expect_label("Submitted: CUA café 789 | Two | true"))
            print("PASS native Unicode input, select, checkbox and exact form result", flush=True)

            state = read()
            click(state, "Download test file")
            downloaded = downloads / "cua-test.txt"
            wait_for("download completion", downloaded.is_file)
            if downloaded.read_bytes() != b"CUA download verified\n":
                raise RuntimeError("Downloaded contents did not match")
            print("PASS download with independent byte verification", flush=True)

            known_windows = {w["window_id"] for w in call("list_windows")["windows"]}
            state = read()
            buttons = [e for e in state["elements"] if e.get("role") == "button"
                       and e.get("label", "").startswith("Upload test file:")]
            if len(buttons) != 1:
                raise RuntimeError("Expected one upload control")
            steps(action("click", element_token=buttons[0]["element_token"]))

            def discover_chooser():
                candidates = [w for w in call("list_windows")["windows"]
                              if w["window_id"] not in known_windows
                              and w.get("title") == "Open File"]
                if len(candidates) > 1:
                    raise RuntimeError("Ambiguous file chooser")
                return candidates[0] if candidates else None

            window = wait_for("native file chooser", discover_chooser)
            chooser = dict(pid=window["pid"], window_id=window["window_id"])
            read(chooser, name="chooser")
            steps(action("press_key", key="l", modifiers=["ctrl"]),
                  action("type_text", text=str(upload)), action("press_key", key="Return"),
                  exact=chooser)
            wait_for("uploaded file result", lambda: expect_label("Uploaded: cua-upload.txt"))
            chooser = None
            print("PASS upload through native file chooser and page readback", flush=True)

            state = read()
            result = steps(action("right_click", element_token=find(state, "Message")["element_token"]))
            popup_id = next((step.get("popup", {}).get("window_id") for step in result.get("steps", [])
                             if step.get("popup", {}).get("window_id")), None)
            # Without window_id, Cua can inspect an open popup rather than the
            # main window. Do not mistake an unchanged main tree for no popup.
            popup_target = dict(pid=app.pid)
            if popup_id:
                popup_target["window_id"] = popup_id
            popup = read(popup_target, name="context")
            menu_items = [e for e in popup.get("elements", [])
                          if "menu item" in e.get("role", "")]
            if menu_items:
                print("PASS context menu discovered through popup accessibility", flush=True)
            else:
                print("LIMIT context-menu accessibility unavailable", flush=True)
            steps(action("press_key", key="Escape"))

            call("set_window_frame", **target, x=50, y=50, width=1100, height=900)
            state = read()
            bounds = state["window_bounds"]
            if any(abs(bounds[k] - v) > 8 for k, v in
                   dict(x=50, y=50, width=1100, height=900).items()):
                raise RuntimeError(f"Resize readback failed: {bounds}")
            print("PASS window move and resize readback", flush=True)

            start = find(state, "Drag this test item")["screenshot_frame"]
            end = find(state, "Drop test item here")["screenshot_frame"]
            steps(action("drag", from_x=start["x"] + start["w"] / 2,
                         from_y=start["y"] + start["h"] / 2, to_x=end["x"] + end["w"] / 2,
                         to_y=end["y"] + end["h"] / 2, duration_ms=800))
            wait_for("drop result", lambda: expect_label("Dropped: CUA test item"))
            print("PASS native drag and drop result", flush=True)

            state = read()
            document = next(e for e in state["elements"] if e.get("role") == "document web")
            frame = document["screenshot_frame"]
            offscreen = find(state, "Scroll verification target")["screenshot_frame"]
            if offscreen["y"] < frame["y"] + frame["h"]:
                raise RuntimeError("Scroll target was already visible")
            x, y = frame["x"] + frame["w"] / 2, frame["y"] + frame["h"] / 2
            steps(action("scroll", direction="down", amount=30, x=x, y=y))

            def scrolled():
                current = read()
                marker = find(current, "Scroll verification target")["screenshot_frame"]
                return frame["y"] <= marker["y"] and marker["y"] + marker["h"] <= frame["y"] + frame["h"]

            wait_for("scroll target inside viewport", scrolled)
            print("PASS scrolling with viewport verification", flush=True)
            steps(action("scroll", direction="up", amount=50, x=x, y=y))
            for number in range(3):
                state = read()
                click(state, "Message")
                text = f"Round {number} café"
                steps(action("press_key", key="a", modifiers=["ctrl"]), action("type_text", text=text))
                state = read()
                click(state, "Submit test form")
                wait_for("repeated submission", lambda: expect_label(f"Submitted: {text} | Two | true"))
            print("PASS repeated Unicode input after transfers, resize and scrolling", flush=True)
            if args.require_context_menu and not menu_items:
                raise RuntimeError("Context menu did not expose accessible menu items")
            passed = True
        finally:
            if not passed and args.artifacts:
                if target:
                    try:
                        call("get_window_state", **(chooser or target),
                             include_accessibility_tree=False,
                             screenshot_out_file=str(root / "failure.png"))
                    except (RuntimeError, subprocess.TimeoutExpired):
                        pass
                # Diagnostic output is opt-in: the chooser may contain names
                # from the user's home directory. Never stage these artifacts.
                destination = args.artifacts.expanduser().resolve()
                destination.mkdir(parents=True, exist_ok=True, mode=0o700)
                for source in root.iterdir():
                    if source.is_file() and source.suffix in (".png", ".json", ".log"):
                        shutil.copyfile(source, destination / source.name)
                        (destination / source.name).chmod(0o600)
                print(f"Failure diagnostics: {destination}", file=sys.stderr)
            if chooser:
                try:
                    call("run_steps", **chooser, delivery_mode="foreground",
                         steps=[action("press_key", key="Escape")])
                except (RuntimeError, subprocess.TimeoutExpired):
                    pass
            if app.poll() is None:
                os.killpg(app.pid, signal.SIGTERM)
                try:
                    app.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(app.pid, signal.SIGKILL)
                    app.wait()
            log.close()
            try:
                call("end_session")
            except (RuntimeError, subprocess.TimeoutExpired) as error:
                print(f"Session cleanup failed: {error}", file=sys.stderr)


if __name__ == "__main__":
    main()
