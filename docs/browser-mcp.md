# Browser MCP: Playwright first

Pi defaults to the lazy `playwright` MCP server for ordinary browser automation.
The shared Home Manager module installs a pinned Playwright MCP 0.0.82 with a
locked dependency tree and launches it with `--extension`. It does not download
browsers or launch a separate automation profile.

`pi-prompts/browser-routing.md` is installed as
`~/.pi/agent/APPEND_SYSTEM.md`, so the preference applies automatically in new Pi
sessions without replacing existing global `AGENTS.md` instructions. This is
instruction-based routing, not access control. Explicit requests for Orca's
embedded browser or native desktop control still use their respective tools.

## macOS setup

1. Apply the configuration with
   `sudo darwin-rebuild switch --flake ~/nixos-config#macbook`.
2. Restart Chrome. Home Manager declares the official Playwright extension
   (`mmlmfjhmonkocbjadbfplnigmagldckm`) using Chrome's per-user external-extension
   manifest. Accept Chrome's extension-enable confirmation in the intended
   profile. Chrome manages Web Store updates; the extension binary is not pinned
   by Nix. Organization browser policies may prevent external installation.
3. Restart Pi so it loads the new MCP configuration and routing instructions.
4. Ask Pi to open a harmless page using Playwright. Approve the connection and
   choose the task tab. Check that it appears in the client's tab group.

The extension reuses that profile's existing sessions and logins. Current
upstream extension documentation describes a separately named/colored group
per connected client and access limited to tabs in that group. This is not a
separate cookie store or an authorization boundary for website actions. Multiple
conversations sharing a client connection may share a group.

If more than one Chrome profile has the extension, Playwright defaults to the
last-used profile. To select one explicitly, add `--profile-dir-name` and its
profile directory name to the declarative MCP arguments (see `chrome://version`
locally). Do not commit private profile paths or account identifiers.

Do not set `PLAYWRIGHT_MCP_EXTENSION_TOKEN` by default: connection approval is
intentional. Never put such a token in tracked files or the world-readable Nix
store. No remote-debugging Chrome flag is required for Playwright extension mode.

The server and routing instructions are shared across hosts. The external
extension declaration is macOS-only; Linux/WSL users need a compatible local
browser/extension setup before this server can connect. It does not automatically
bridge a WSL process to Windows Chrome or a remote host to the Mac.

## Specialized diagnostics

Keep `chrome-devtools` lazy and reserve it for performance traces, CPU/memory
profiling, DevTools-only diagnostics, or explicit requests. Its wrapper uses
`--autoConnect --channel=stable` to reuse running Chrome sessions and logins,
with explicit page-ID routing and sensitive network-header redaction enabled.
It does not launch an isolated browser.

For DevTools, use Chrome 144+ and enable remote debugging at
`chrome://inspect/#remote-debugging`, then approve Chrome's connection prompt.
Auto-connect uses Chrome's default profile; with multiple profiles this may
not be the same profile selected by Playwright. Verify the intended profile and
tab before profiling. DevTools can access all windows in the connected profile,
not just Playwright's tab group. Do not silently use it as a fallback when
Playwright extension approval fails.

## Verification

- Build `packages/playwright-mcp.nix` with the host's pinned `pkgs`.
- Run the built `playwright-mcp --version` and `--help`; expect 0.0.82 and
  `--extension` support.
- Verify MCP initialization and `tools/list` without connecting to Chrome.
- After activation, test a new tab, a screenshot, and two independent clients to
  verify extension approval, existing-session reuse, and separate tab groups.
  These browser checks require the user's approval; a package build cannot
  prove them.

Upstream references:

- https://github.com/microsoft/playwright/tree/main/packages/extension
- https://github.com/microsoft/playwright-mcp
- https://developer.chrome.com/docs/extensions/how-to/distribute/install-extensions
