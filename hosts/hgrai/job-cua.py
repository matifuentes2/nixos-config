#!/usr/bin/env python3
"""Lazy, job-local CUA desktop. No host broker or user-manager socket."""
import json
import os
from pathlib import Path
import queue
import re
import signal
import select
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time

config = json.loads(Path(sys.argv[1]).read_text())
events = queue.Queue()
child = desktop = None
profile = None
pending = set()
last_use = time.monotonic()
schemas = None


def send(value):
    print(json.dumps(value), flush=True)


def read(stream, source):
    for line in stream:
        events.put((source, line))
    events.put((source, None))


def release():
    global child, desktop, profile
    for process in (child, desktop):
        if process:
            try:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=5)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                pass
    child = desktop = None
    if profile:
        shutil.rmtree(profile, ignore_errors=True)
        profile = None


def tools():
    global schemas
    if schemas is None:
        if config.get("schemasFile"):
            schemas = json.loads(Path(config["schemasFile"]).read_text())
            return schemas
        schemas = []
        listing = subprocess.check_output([config["driver"], "list-tools"], text=True, timeout=20)
        for line in listing.splitlines():
            name = line.split(":", 1)[0]
            if not re.fullmatch(r"[a-z_][a-z0-9_]*", name):
                continue
            description = subprocess.check_output([config["driver"], "describe", name], text=True, timeout=10)
            heading, schema = description.split("\n\ninput_schema:\n", 1)
            schemas.append(dict(name=name, description=heading.split("\ndescription:\n", 1)[1].strip(), inputSchema=json.loads(schema)))
        schemas.append(dict(name="pool_release_desktop", description="Release this job's desktop and discard its browser profiles. Preserve repository files and downloads. The next GUI call starts a fresh desktop.", inputSchema={"type":"object","properties":{},"additionalProperties":False}))
    return schemas


def start():
    global child, desktop, profile
    if child:
        return
    profile = tempfile.mkdtemp(prefix="cua-profile-", dir=os.environ["HOME"])
    downloads = Path(os.environ["HOME"]) / "Downloads"
    downloads.mkdir(exist_ok=True)
    (Path(profile) / "Downloads").symlink_to(downloads)
    (Path(profile) / ".config").mkdir()
    (Path(profile) / ".config" / "user-dirs.dirs").write_text('XDG_DOWNLOAD_DIR="' + str(downloads) + '"\n')
    runtime = Path(tempfile.mkdtemp(prefix="cua-", dir=os.environ["XDG_RUNTIME_DIR"]))
    runtime.mkdir(parents=True, exist_ok=True)
    (runtime / "lease.id").write_text("job")
    notification = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
    notification.bind(str(runtime / "notify.sock"))
    env = {**os.environ, "NOTIFY_SOCKET": str(runtime / "notify.sock"), "CUA_POOL_LEASE": "job", "XDG_RUNTIME_DIR":str(runtime), "HOME":profile, "XDG_CONFIG_HOME":profile+"/.config", "XDG_CACHE_HOME":profile+"/.cache", "XDG_DATA_HOME":profile+"/.local/share"}
    # Readiness probes must see EOF on stdin. Inheriting the MCP input pipe
    # makes native CLI probes wait for a JSON argument forever.
    with (Path(os.environ["HOME"]) / "cua-desktop.log").open("wb") as log:
        desktop = subprocess.Popen([config["desktop"]], env=env, stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)
    notification.settimeout(30)
    try:
        notification.recv(4096)
    finally:
        notification.close()
        (runtime / "notify.sock").unlink(missing_ok=True)
    driver_socket = str(runtime / "driver-job.sock")
    child = subprocess.Popen([config["run"], config["driver"], "mcp", "--socket", driver_socket], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, start_new_session=True)
    child.stdin.write(json.dumps(dict(jsonrpc="2.0", id="job-init", method="initialize", params=dict(protocolVersion="2024-11-05", capabilities={}, clientInfo=dict(name="support-job", version="1")))) + "\n")
    child.stdin.flush()
    # Drain the native initialization response before forwarding tool traffic.
    if not select.select([child.stdout], [], [], 10)[0]:
        raise RuntimeError("CUA initialization timed out")
    line = child.stdout.readline()
    if not line or json.loads(line).get("id") != "job-init":
        raise RuntimeError("CUA initialization failed")
    child.stdin.write(json.dumps(dict(jsonrpc="2.0", method="notifications/initialized", params={})) + "\n")
    child.stdin.flush()
    threading.Thread(target=read, args=(child.stdout, "native:" + str(child.pid)), daemon=True).start()


if len(sys.argv) > 2 and sys.argv[2] == "--schema":
    print(json.dumps(tools()))
    sys.exit(0)

threading.Thread(target=read, args=(sys.stdin, "client"), daemon=True).start()
try:
    while True:
        if child and not pending and time.monotonic() - last_use > 600:
            release()
        try:
            source, line = events.get(timeout=1)
        except queue.Empty:
            continue
        if source.startswith("native:"):
            if child is None or source != "native:" + str(child.pid):
                continue
            if line is None:
                for identifier in pending:
                    send(dict(jsonrpc="2.0", id=identifier, result=dict(isError=True, content=[dict(type="text", text="desktop_lost")])) )
                pending.clear()
                release()
            else:
                value = json.loads(line)
                pending.discard(value.get("id"))
                send(value)
            continue
        if line is None:
            break
        value = json.loads(line)
        identifier, method = value.get("id"), value.get("method")
        try:
            if method == "initialize":
                result = dict(protocolVersion=value["params"]["protocolVersion"], capabilities=dict(tools={}), serverInfo=dict(name="support-job-cua", version="1"))
            elif method == "tools/list":
                result = dict(tools=tools())
            elif method == "tools/call":
                if value.get("params",{}).get("name") == "pool_release_desktop":
                    if pending:
                        raise RuntimeError("desktop_busy")
                    release()
                    send(dict(jsonrpc="2.0", id=identifier, result=dict(content=[dict(type="text",text="desktop_released")])) )
                    continue
                start()
                pending.add(identifier)
                last_use = time.monotonic()
                child.stdin.write(line)
                child.stdin.flush()
                continue
            elif identifier is None:
                continue
            else:
                result = {}
            send(dict(jsonrpc="2.0", id=identifier, result=result))
        except Exception as error:
            release()
            send(dict(jsonrpc="2.0", id=identifier, result=dict(isError=True, content=[dict(type="text", text="desktop_unavailable:" + type(error).__name__)])) )
finally:
    release()
