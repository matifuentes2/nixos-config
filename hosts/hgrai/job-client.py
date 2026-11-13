#!/usr/bin/env python3
"""Protocol boundary: bind a provider session to its actual worktree and strip
controller MCP credentials before any message reaches untrusted execution.
"""
import json
import os
import socket
import sys
import threading


def clean(message):
    params = message.get("params")
    if isinstance(params, dict):
        if isinstance(params.get("config"), dict):
            allowed = {"tools.update_plan.enabled", "mcp_optional_startup_grace_ms", "features.concurrent_reasoning_summaries", "model_reasoning_effort", "model_reasoning_summary", "model_verbosity"}
            params["config"] = {key: value for key, value in params["config"].items() if key in allowed}
        if "sandboxPolicy" in params:
            # The outer service enforces filesystem/network/process boundaries.
            params["sandboxPolicy"] = {"type": "dangerFullAccess"}
        if "approvalPolicy" in params:
            params["approvalPolicy"] = "never"
    return message


input_buffer = bytearray()

def read():
    # Do not leave a daemon thread holding Python's buffered stdin lock during
    # interpreter shutdown after a remote process exits.
    while b"\n" not in input_buffer:
        chunk = os.read(sys.stdin.fileno(), 65536)
        if not chunk: raise EOFError("Provider disconnected")
        input_buffer.extend(chunk)
        if len(input_buffer) > 8 * 1024 * 1024: raise ValueError("Protocol message exceeds limit")
    line, _, remaining = input_buffer.partition(b"\n")
    input_buffer[:] = remaining
    return json.loads(line)


def encode(value):
    return json.dumps(value).encode() + b"\n"


def main():
    initialize = read()
    if initialize.get("method") != "initialize":
        raise RuntimeError("Initialization required")
    # T3 sends the cwd on thread/start, after initialization. Delay privileged
    # launch until that identity is known; a late old session must never inherit
    # a newer claim's worktree. The pinned native response has these four fields.
    sys.stdout.buffer.write(encode(dict(id=initialize["id"], result=dict(codexHome="/home/job/.codex", platformFamily="unix", platformOs="linux", userAgent="codex/0.167.0"))))
    sys.stdout.buffer.flush()
    first = read()
    while "id" not in first:
        first = read()
    execution = first.get("method") in ("thread/start", "thread/resume", "thread/fork")
    probes = {"account/read", "account/rateLimits/read", "model/list", "skills/list", "config/read", "mcpServerStatus/list"}
    if not execution and first.get("method") not in probes:
        raise ValueError("Unsupported provider probe")
    connection = socket.socket(socket.AF_UNIX)
    connection.connect("/run/grai-job-supervisor/control.sock")
    connection.sendall(encode(dict(operation="launch", probe=not execution, cwd=(first.get("params") or {}).get("cwd"))))
    reply = bytearray()
    while not reply.endswith(b"\n"):
        chunk = connection.recv(1)
        if not chunk or len(reply) > 4096:
            raise RuntimeError("Invalid supervisor response")
        reply.extend(chunk)
    if not json.loads(reply)["ok"]:
        raise RuntimeError("No authorized execution lease")
    connection.sendall(encode(initialize))
    pending_output = bytearray()
    while True:
        while b"\n" not in pending_output:
            chunk = connection.recv(65536)
            if not chunk: raise EOFError("Native initialization disconnected")
            pending_output.extend(chunk)
        line, _, remaining = pending_output.partition(b"\n")
        pending_output[:] = remaining
        response = json.loads(line)
        if response.get("id") == initialize["id"]:
            if "error" in response:
                raise RuntimeError("Native initialization failed")
            break
    connection.sendall(encode(dict(method="initialized")))
    connection.sendall(encode(clean(first)))

    send_lock = threading.Lock()
    def native_send(message):
        with send_lock:
            connection.sendall(encode(message))

    def send():
        try:
            while True:
                message = read()
                # A session is tied to one worktree. Protocol callers cannot
                # redirect later turns or add a second repository to the jail.
                params = message.get("params") or {}
                if not isinstance(params, dict):
                    raise ValueError("Invalid protocol params")
                cwd = params.get("cwd")
                if cwd and execution and cwd != first["params"]["cwd"]:
                    raise ValueError("Worktree changed")
                if not execution and message.get("method") not in probes:
                    raise ValueError("Probe cannot execute work")
                native_send(clean(message))
        except (OSError, EOFError, ValueError):
            connection.shutdown(socket.SHUT_WR)

    threading.Thread(target=send, daemon=True).start()
    os.set_blocking(sys.stdout.fileno(), True)
    def output(data):
        view = memoryview(data)
        while view:
            written = os.write(sys.stdout.fileno(), view)
            view = view[written:]
    while True:
        while b"\n" in pending_output:
            line, _, remaining = pending_output.partition(b"\n")
            pending_output[:] = remaining
            message = json.loads(line)
            # Existing provider mode must never grant a job access to T3's
            # managed-auth broker, dynamic host tools, or controller MCP.
            if "method" in message and "id" in message and message["method"] != "item/tool/requestUserInput":
                native_send(dict(id=message["id"], error=dict(code=-32601, message="isolated_job_host_request_denied")))
                continue
            output(encode(message))
        chunk = connection.recv(65536)
        if not chunk:
            break
        pending_output.extend(chunk)
        if len(pending_output) > 8 * 1024 * 1024:
            raise ValueError("Native message exceeds limit")


if __name__ == "__main__":
    main()
