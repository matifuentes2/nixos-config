"""Exercise MCP discovery against the real pinned driver without any desktop."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

with tempfile.TemporaryDirectory(prefix="cua-mcp-test-") as directory:
    root = Path(directory)
    config = root / "config.json"
    config.write_text(json.dumps(dict(driver=sys.argv[2], runtimeDirectory="unallocated")))
    env = dict(os.environ, XDG_RUNTIME_DIR=str(root))
    env.pop("CUA_POOL_LEASE", None)
    env.pop("CUA_POOL_ROOT", None)
    requests = [
        dict(jsonrpc="2.0", id=1, method="initialize", params={
            "protocolVersion": "2024-11-05", "capabilities": {},
            "clientInfo": {"name": "discovery-test", "version": "1"}}),
        dict(jsonrpc="2.0", method="notifications/initialized"),
        dict(jsonrpc="2.0", id=2, method="tools/list"),
        dict(jsonrpc="2.0", id=3, method="ping"),
    ]
    result = subprocess.run([sys.executable, sys.argv[1], "--config", str(config), "mcp"],
                            input="".join(json.dumps(message) + "\n" for message in requests),
                            capture_output=True, text=True, timeout=30, env=env, check=True)
    responses = {message["id"]: message for message in map(json.loads, result.stdout.splitlines())}
    assert responses[1]["result"]["capabilities"] == {"tools": {}}
    tools = responses[2]["result"]["tools"]
    assert len(tools) > 30
    assert all(isinstance(tool["inputSchema"], dict) and tool["description"] for tool in tools)
    assert any(tool["name"] == "get_window_state" for tool in tools)
    assert responses[3]["result"] == {}
    assert not (root / "unallocated").exists(), "Discovery allocated pool resources"
    print("PASS real driver schemas and MCP discovery without a desktop or broker")
