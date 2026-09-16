// Run with the packaged Bun: bun tests/pi-extensions-smoke.mjs <registry> [git-package ...]
// Uses temporary Pi state; never sends a model request or runs session hooks.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, realpathSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [registry, ...gitPackages] = process.argv.slice(2);
assert(registry, "Pass the built pi-extensions registry store path");
const temporary = mkdtempSync(join(tmpdir(), "pi-extension-smoke-"));
process.env.PI_CODING_AGENT_DIR = temporary;
process.env.HOME = temporary;
try {
  const manifest = JSON.parse(readFileSync(join(registry, "package.json")));
  for (const paths of Object.values(manifest.pi)) {
    for (const path of paths) assert(statSync(join(registry, path)), `Missing resource: ${path}`);
  }
  const names = [...new Set(Object.values(manifest.pi).flat().map(path => path.split("/")[1]))];
  const roots = names.map(name => realpathSync(join(registry, "node_modules", name)));
  const apiRoots = roots.map(root => realpathSync(join(dirname(root), "@earendil-works/pi-coding-agent")));
  assert.equal(new Set(apiRoots).size, 1, "Extensions must share Pi's API instance");
  for (const root of gitPackages) {
    assert.equal(realpathSync(join(root, "node_modules/@earendil-works/pi-coding-agent")), apiRoots[0]);
  }
  const { loadExtensions } = await import(pathToFileURL(join(apiRoots[0], "dist/core/extensions/loader.js")));
  const files = manifest.pi.extensions.map(path => resolve(registry, path));
  for (const root of gitPackages) {
    const gitManifest = JSON.parse(readFileSync(join(root, "package.json")));
    for (const entry of gitManifest.pi.extensions) {
      const path = resolve(root, entry);
      if (statSync(path).isDirectory()) {
        const { readdirSync } = await import("node:fs");
        files.push(...readdirSync(path).filter(name => /\.(ts|js)$/.test(name)).map(name => join(path, name)));
      } else files.push(path);
    }
  }
  const loaded = await loadExtensions(files, temporary);
  assert.deepEqual(loaded.errors, []);
  assert.equal(loaded.extensions.length, files.length);

  // Native dependencies must survive npm packing and isolation, not just import
  // successfully through Pi's TS loader. Use Node for better-sqlite3's ABI.
  const contextRoot = realpathSync(join(registry, "node_modules/context-mode"));
  execFileSync(process.env.PI_TEST_NODE || "node", ["--input-type=commonjs", "-e", `
    const requireFromPackage = require('node:module').createRequire(${JSON.stringify(join(contextRoot, "package.json"))});
    const Database = requireFromPackage('better-sqlite3');
    const db = new Database(':memory:');
    require('node:assert/strict').equal(db.prepare('select 42 as answer').get().answer, 42);
    db.close();
  `], { stdio: "pipe" });
  const mcpRoot = realpathSync(join(registry, "node_modules/pi-mcp-adapter"));
  const { createRequire } = await import("node:module");
  createRequire(join(mcpRoot, "package.json"))("@napi-rs/keyring");
  console.log(`Loaded ${files.length} extensions; all resources and shared Pi APIs present; native SQLite and keyring passed.`);
} finally {
  rmSync(temporary, { recursive: true, force: true });
}
