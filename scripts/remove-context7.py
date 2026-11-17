"""Remove obsolete Context7 registrations without replacing unrelated settings."""

import json
import re
from pathlib import Path


# Tokenize JSON/JSONC so braces, commas and URLs inside strings/comments are safe.
TOKEN = re.compile(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*[\s\S]*?\*/|[^\s]', re.DOTALL)


def remove_json_server(text):
    tokens = [m for m in TOKEN.finditer(text) if not m[0].startswith(('//', '/*'))]
    spans = []
    for i, token in enumerate(tokens[:-2]):
        if token[0] != '"context7"' or tokens[i + 1][0] != ':':
            continue
        end = i + 2
        depth = 0
        while end < len(tokens):
            value = tokens[end][0]
            if value in ('{', '['):
                depth += 1
            elif value in ('}', ']'):
                depth -= 1
            if depth == 0:
                break
            end += 1
        start_pos, end_pos = token.start(), tokens[end].end()
        if end + 1 < len(tokens) and tokens[end + 1][0] == ',':
            end_pos = tokens[end + 1].end()
        elif i and tokens[i - 1][0] == ',':
            start_pos = tokens[i - 1].start()
        spans.append((start_pos, end_pos))
    for start, end in reversed(spans):
        text = text[:start] + text[end:]
    return text


def remove_toml_server(text):
    lines = text.splitlines(keepends=True)
    result = []
    skip = False
    for line in lines:
        if line.lstrip().startswith('['):
            table = line.strip().strip('[]').replace('"', '').replace("'", '')
            skip = table == 'mcp_servers.context7' or table.startswith('mcp_servers.context7.')
        if not skip:
            result.append(line)
    return ''.join(result)


def clean(path, transform):
    if not path.is_file():
        return
    old = path.read_text()
    new = transform(old)
    if old != new:
        # Follow writable dotfile symlinks back to their source. Never modify
        # generated store files; those must be changed in their owning module.
        if str(path.resolve()).startswith('/nix/store/'):
            raise RuntimeError(f'Context7 remains in a Nix-managed file: {path}')
        path.write_text(new)
        print(f'Removed Context7 from {path}')


def main(home):
    clean(home / '.codex/config.toml', remove_toml_server)
    for relative in (
        '.cursor/mcp.json',
        '.windsurf/mcp.json',
        '.codeium/windsurf/mcp_config.json',
        '.gemini/settings.json',
        '.gemini/antigravity/mcp_config.json',
        '.config/opencode/opencode.json',
        '.config/opencode/opencode.jsonc',
        '.claude.json',
        '.claude/settings.json',
        '.mcp.json',
        '.pi/agent/mcp.json',
        '.config/Code/User/mcp.json',
        '.config/VSCodium/User/mcp.json',
        '.config/zed/settings.json',
        'Library/Application Support/Code/User/mcp.json',
        'Library/Application Support/VSCodium/User/mcp.json',
        'Library/Application Support/Claude/claude_desktop_config.json',
        'Library/Application Support/Zed/settings.json',
    ):
        clean(home / relative, remove_json_server)
    # Older Pi caches sometimes stored Context7 under a generic server alias.
    def prune_cache(text):
        data = json.loads(text)
        servers = data.get('servers', {})
        stale = [name for name, entry in servers.items()
                 if 'context7' in (name + json.dumps(entry)).lower()]
        if not stale:
            return text
        for name in stale:
            del servers[name]
        return json.dumps(data, indent=2) + '\n'

    clean(home / '.pi/agent/mcp-cache.json', prune_cache)
    for relative in ('.codex/AGENTS.md', '.config/opencode/AGENTS.md'):
        clean(home / relative, lambda text: re.sub(
            r'(?im)^(?:## Documentation Source Rule\n\s*\n)?'
            r'Whenever you require documentation from a package(?:/library| or library),? '
            r'use the context7 mcp server\.\n?', '', text,
        ).lstrip('\n'))


if __name__ == '__main__':
    main(Path.home())
