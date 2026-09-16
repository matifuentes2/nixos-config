# Declarative Pi extensions

Each directory here is an independent `buildNpmPackage` source with its own
`package.json`, `package-lock.json`, and dependency cache hash (in
`packages/pi-extensions.nix`). The root `package.json` is **only a Pi resource
registry**: its derivation copies that manifest and links the selected packages.
It does not run npm or build any extensions.

Changing registration only rebuilds that tiny registry and the affected Home
Manager/system wrappers. Updating an extension's files or lockfile rebuilds
only that extension. A shared dependency may be present in several npm trees;
this modest duplication avoids making unrelated extensions depend on one
another's complete lockfile. Pi-owned APIs are linked from the packaged Pi
runtime, also for the separately pinned Git extensions. Updating Pi or nixpkgs
can legitimately invalidate more packages.

## Add or update an npm extension

1. Create/update `pi-extensions/<name>/package.json`. Pin the extension's exact
   version, use `<name>-package` as the wrapper name, and include the dependency
   in `bundledDependencies`. See `pi-vim` for a minimal example.
2. From that directory, generate the lockfile without running lifecycle scripts:

   ```sh
   npm install --package-lock-only --ignore-scripts --legacy-peer-deps
   ```

   This is lockfile maintenance, **not** a global/imperative installation.
   Review the diff; keep `bundledDependencies` and remove npm's duplicate
   `bundleDependencies` alias if it adds one to the manifest. Pi's peer APIs are
   supplied by Nix; any other required runtime peer must be an explicit pinned
   dependency (e.g. Ollama's legacy `@sinclair/typebox`).
3. Add/update the package's `npmDepsHash` in `packages/pi-extensions.nix` using
   `prefetch-npm-deps pi-extensions/<name>/package-lock.json`. Add a bundling
   entry only if needed. Native dependencies still build in Nix's sandbox;
   do not copy native artifacts from a developer's npm directory.
4. Register the desired extensions, skills and prompts in the root
   `pi-extensions/package.json`, following its `node_modules/<name>/...` paths.
   Registration is explicit so upstream manifest changes cannot silently
   enable additional resources. Git extensions remain registered separately
   in `modules/home/common.nix`.
5. Track new files so flakes can see them, then validate just the new package:

   ```sh
   nix build --no-link .#pi-extension-pi-ollama-cloud  # replace the name
   nix build --no-link .#pi-extensions              # all enabled registrations
   python3 tests/test-pi-extension-isolation.py
   bun tests/pi-extensions-smoke.mjs "$(nix build --no-link --print-out-paths .#pi-extensions)"
   ```

   The smoke test uses temporary Pi state, loads the registered extensions
   without model requests, and checks API sharing and native SQLite/keyring.
   Use the packaged Bun and a Node matching the build's major version; set
   `PI_TEST_NODE=/path/to/node` if the default `node` differs. Optional additional
   arguments are built Git-extension package roots to check alongside npm ones.

To disable an extension, remove **all** its extension/skill/prompt paths from
the root registry. The package drops out of the registry's dependency closure;
no remaining extension recompiles. To delete it entirely, also remove its
package directory and definition in `packages/pi-extensions.nix`.
`chrome-devtools-mcp` has no Pi resources: it is independently built for the
MCP launcher, so removing a Pi extension cannot rebuild Chrome's MCP server.

Finally rebuild the host to activate the new registry. This still requires Nix
and Home Manager evaluation/activation; splitting packages does not eliminate
those costs. The first migration from the old monolithic bundle builds each
new package once. No credentials or mutable Pi sessions belong here.
