// Run with Bun: bun tests/pi-mcp-config-smoke.mjs <generated-settings> <generated-mcp>
// Uses isolated state; never starts MCP servers or sends model requests.
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [settingsArg, mcpArg] = process.argv.slice(2);
assert(settingsArg && mcpArg, "Pass the generated settings.json and mcp.json");
const settingsPath = realpathSync(resolve(settingsArg));
const mcpPath = realpathSync(resolve(mcpArg));
const settingsText = readFileSync(settingsPath, "utf8");
const settings = JSON.parse(settingsText);
assert(settings.extensions.includes("+builtin:mcp"), "Enable native MCP declaratively");
assert(!settings.extensions.includes("-builtin:mcp"));
const registry = settings.packages.find(source => {
  const manifest = JSON.parse(readFileSync(join(source, "package.json"), "utf8"));
  return manifest.name === "pi-extensions";
});
assert(registry, "Missing extension registry");
const manifest = JSON.parse(readFileSync(join(registry, "package.json"), "utf8"));
assert(!JSON.stringify(manifest).includes("pi-mcp-adapter"), "Remove the competing /mcp owner");
const extensionRoot = realpathSync(join(registry, "node_modules/context-mode"));
const pi = realpathSync(join(dirname(extensionRoot), "@earendil-works/pi-coding-agent"));
const temporary = mkdtempSync(join(tmpdir(), "pi-mcp-config-smoke-"));
process.env.PI_CODING_AGENT_DIR = temporary;
process.env.HOME = temporary;
try {
  // Exercise the native parser against the immutable generated configuration.
  symlinkSync(settingsPath, join(temporary, "settings.json"));
  symlinkSync(mcpPath, join(temporary, "mcp.json"));
  const { loadMcpConfig } = await import(pathToFileURL(join(pi, "dist/extensions/mcp/config.js")));
  const loaded = loadMcpConfig({ agentDir: temporary, cwd: temporary, projectTrusted: false });
  assert.deepEqual(loaded.errors, []);
  assert.deepEqual(loaded.servers.map(server => server.name).sort(), ["chrome-devtools", "nixos", "playwright"]);
  for (const server of Object.values(JSON.parse(readFileSync(mcpPath, "utf8")).mcpServers)) {
    assert(!("lifecycle" in server), "Remove adapter-only lifecycle settings");
  }
  const { loadExtensions } = await import(pathToFileURL(join(pi, "dist/core/extensions/loader.js")));
  const native = await loadExtensions([join(pi, "dist/extensions/mcp/index.js")], temporary);
  assert.deepEqual(native.errors, []);
  assert.equal(native.extensions.length, 1);
  assert.equal(readFileSync(settingsPath, "utf8"), settingsText);
  console.log("Native MCP enabled and loads; no adapter registered; all three server configurations parse without errors.");
} finally {
  rmSync(temporary, { recursive: true, force: true });
}
