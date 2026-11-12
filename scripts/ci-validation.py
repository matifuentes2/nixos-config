#!/usr/bin/env python3
"""Select CI work conservatively and enforce the required aggregate check."""

import argparse
import json
import os
import subprocess


HOSTS = {
    "raspberry-pi": "raspberry_pi",
    "amd64-lenovo-legion-y720": "legion",
    "wsl2": "wsl2",
    "hgrai": "hgrai",
    "macbook": "macbook",
}
LINUX_HOSTS = ("raspberry_pi", "legion", "wsl2", "hgrai")
SELECTIONS = ("flake", "macbook", *LINUX_HOSTS, "linux")


def plan(paths, full=False):
    selected = dict.fromkeys(SELECTIONS, full)
    for path in paths:
        # Only documentation locations known not to feed configuration are exempt.
        # Markdown elsewhere (e.g. pi-prompts/) can be a runtime dependency.
        if path in ("README.md", "AGENTS.md") or (
            path.startswith("docs/") and path.endswith(".md")
        ):
            continue
        parts = path.split("/")
        if len(parts) >= 3 and parts[0] == "hosts" and parts[1] in HOSTS:
            selected[HOSTS[parts[1]]] = True
        else:
            # Includes shared modules, inputs, tests, CI logic and unknown paths.
            selected = dict.fromkeys(SELECTIONS, True)
    selected["linux"] = any(selected[host] for host in LINUX_HOSTS)
    return selected


def check_results(needs):
    for job in ("plan", "quick"):
        if needs[job]["result"] != "success":
            raise ValueError(f"{job} must succeed: {needs[job]['result']}")
    outputs = needs["plan"]["outputs"]
    for selection in SELECTIONS:
        if outputs.get(selection) not in ("true", "false"):
            raise ValueError(f"Missing or invalid plan output: {selection}")
    if (outputs["linux"] == "true") != any(
        outputs[host] == "true" for host in LINUX_HOSTS
    ):
        raise ValueError("Linux selection disagrees with host selections")
    for job in ("flake", "macbook", "linux"):
        expected = "success" if outputs[job] == "true" else "skipped"
        if needs[job]["result"] != expected:
            raise ValueError(f"{job}: expected {expected}, got {needs[job]['result']}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    selector = commands.add_parser("plan")
    selector.add_argument("--full", action="store_true")
    selector.add_argument("--base")
    selector.add_argument("--head")
    commands.add_parser("gate")
    args = parser.parse_args()
    if args.command == "gate":
        check_results(json.loads(os.environ["CI_NEEDS"]))
        print("All selected checks succeeded.")
        return
    if args.full:
        paths = []
    else:
        if not args.base or not args.head:
            parser.error("plan requires --full or both --base and --head")
        # No rename detection: a move between hosts must validate both sides.
        # NUL separation preserves filenames with whitespace and newlines.
        paths = subprocess.check_output(
            ["git", "diff", "--name-only", "-z", "--no-renames",
             args.base, args.head, "--"]
        ).decode("utf-8", errors="surrogateescape").split("\0")
        paths = [path for path in paths if path]
    for key, value in plan(paths, args.full).items():
        print(f"{key}={str(value).lower()}")


if __name__ == "__main__":
    main()
