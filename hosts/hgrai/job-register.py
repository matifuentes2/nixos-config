#!/usr/bin/env python3
"""Manage only the support provider; preserve interactive T3 preferences."""
import json
import os
from pathlib import Path

path = Path.home() / ".t3" / "userdata" / "settings.json"
settings = json.loads(path.read_text()) if path.exists() else {}
settings.setdefault("providerInstances", {})["support-sandbox"] = {
    "driver": "codex",
    "displayName": "Support sandbox",
    "enabled": True,
    "config": {
        "setupMode": "existing",
        "binaryPath": "/etc/grai-support-job-launcher",
        "homePath": str(Path.home() / ".codex-support"),
        "customModels": ["gpt-6.1-sol"],
    },
}
path.parent.mkdir(parents=True, exist_ok=True)
temporary = path.with_suffix(".json.support-tmp")
temporary.write_text(json.dumps(settings))
os.chmod(temporary, 0o600)
os.replace(temporary, path)
