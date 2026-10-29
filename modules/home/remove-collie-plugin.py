#!/usr/bin/env python3
"""Unlink Collie through Herdr, or migrate its registry when Herdr is offline."""
import fcntl
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile


def remove_offline(config_dir):
    registry = config_dir / "plugins.json"
    if not registry.exists():
        return
    # Match the pinned Herdr registry's lock and array schema. Resolve symlinks
    # before atomic replacement, preserving stow-style registries and file mode.
    with (config_dir / ".plugins.lock").open("a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        target = registry.resolve()
        try:
            entries = json.loads(target.read_text())
        except FileNotFoundError:
            return
        if not isinstance(entries, list) or not all(isinstance(p, dict) for p in entries):
            raise ValueError("Unexpected Herdr plugin registry format; refusing to modify it")
        remaining = [p for p in entries if p.get("plugin_id") != "herdr.collie"]
        if remaining == entries:
            return
        mode = stat.S_IMODE(target.stat().st_mode)
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(mode="w", dir=target.parent, delete=False) as output:
                temporary = Path(output.name)
                os.fchmod(output.fileno(), mode)
                json.dump(remaining, output, indent=2)
                output.write("\n")
                output.flush()
                os.fsync(output.fileno())
            os.replace(temporary, target)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
    print("Removed Collie's offline Herdr registration; other plugins and data preserved.")


def main():
    config_dir, herdr = sys.argv[1:]
    result = subprocess.run(
        [herdr, "plugin", "unlink", "herdr.collie"], capture_output=True, text=True,
    )
    if result.returncode == 0:
        print(result.stdout, end="")
        return
    # Never bypass permissions, malformed registries, or arbitrary server errors.
    for line in (result.stdout + "\n" + result.stderr).splitlines():
        try:
            response = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(response, dict) and response.get("error", {}).get("code") == "server_not_running":
            remove_offline(Path(config_dir))
            return
    sys.stderr.write(result.stdout + result.stderr)
    raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
