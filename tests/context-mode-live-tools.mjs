// node tests/context-mode-live-tools.mjs <built-context-mode-root>
// Exercises the installed renderers and executor, without model calls.
import assert from "node:assert/strict";
import { test } from "node:test";
import { mkdtemp, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { createRequire } from "node:module";
import { realpathSync, existsSync, readFileSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";

const packagePath = process.argv[2];
assert(packagePath, "Pass the built context-mode package root");
// Resolve registry symlinks before looking up sibling Pi peers, as imports do.
const root = realpathSync(packagePath);

const { createContextModeExecutor, createContextModeCallRenderer, createContextModeResultRenderer } = await import(pathToFileURL(join(root, "pi/live-tools.mjs")));
const theme = { fg: (_, text) => text, bold: text => text };
const context = (expanded = false) => ({ expanded, state: {}, isError: false });
const rendered = component => component.render(80).join("\n");

const directory = await mkdtemp(join(tmpdir(), "ctx-live-test-"));
const tools = new Map();

try {
  for (const name of ['ctx_execute', 'ctx_execute_file', 'ctx_batch_execute']) {
    tools.set(name, {
      name, renderCall: createContextModeCallRenderer(name), renderResult: createContextModeResultRenderer(name),
      execute: createContextModeExecutor(name, async (_name, args) => {
        await delay(args.delay ?? 1200);
        return { content: [{ type: 'text', text: 'compressed result' }], isError: !!args.fail };
      }),
    });
  }
  const installed = await import(pathToFileURL(join(root, "pi/index.js")));
  const registered = new Map(), events = new Map();
  installed.default({ registerTool: tool => registered.set(tool.name, tool), on: (name, handler) => events.set(name, handler) });
  await events.get("before_agent_start")({ systemPrompt: "" }, { cwd: directory });
  assert(registered.has("ctx_execute"), "Installed adapter registers direct tools");
  for (const tool of registered.values()) {
    assert.equal(typeof tool.renderCall, "function");
    assert.equal(typeof tool.renderResult, "function");
  }
  await test("goal control and nested codemode results remain exact", async () => {
    const content = [{ type: "text", text: JSON.stringify({ goal: { objective: "required browser checks\n".repeat(400), status: "active" } }) }];
    for (const toolName of ["get_goal", "create_goal", "update_goal", "pause_goal", "resume_goal", "run_goal_review", "codemode"]) {
      const result = await events.get("tool_result")({ toolName, toolCallId: "goal-state", input: {}, content, isError: false }, { cwd: directory });
      assert.equal(result, undefined, `${toolName} must pass through without rewriting`);
    }
  });
  const tool = tools.get("ctx_execute");
  await test("real Pi transcript row expands arguments while execution is pending", async () => {
    const require = createRequire(join(root, "package.json"));
    const peerRoot = name => {
      const path = require.resolve.paths(name).map(base => join(base, name)).find(path => existsSync(join(path, "package.json")));
      assert(path, `Missing Pi peer: ${name}`);
      return realpathSync(path);
    };
    const apiDist = join(peerRoot("@earendil-works/pi-coding-agent"), "dist");
    const { initTheme } = await import(pathToFileURL(join(apiDist, "modes/interactive/theme/theme.js")));
    const { ToolExecutionComponent } = await import(pathToFileURL(join(apiDist, "modes/interactive/components/tool-execution.js")));
    const tuiRoot = peerRoot("@earendil-works/pi-tui");
    const tuiManifest = JSON.parse(readFileSync(join(tuiRoot, "package.json"), "utf8"));
    const { visibleWidth } = await import(pathToFileURL(join(tuiRoot, tuiManifest.main)));
    initTheme("dark", false);
    const args = { language: "shell", code: "sleep 2\none\ntwo\nthree\nlast-command " + "界🙂".repeat(30) + " END" };
    const row = new ToolExecutionComponent("ctx_execute", "row", args, {}, tool, { requestRender() {} }, directory);
    row.markExecutionStarted();
    row.setArgsComplete();
    let output = row.render(40).join("\n");
    assert.match(output, /sleep 2/);
    assert.doesNotMatch(output, /last-command/);
    row.updateResult({ content: [], details: { elapsedMs: 3000 } }, true);
    row.setExpanded(true);
    const lines = row.render(40);
    output = lines.join("\n");
    assert.match(output, /last-command/);
    assert.match(output, /END/);
    assert.match(output, /Running/);
    assert(lines.every(line => visibleWidth(line) <= 40));
    row.invalidate();
    assert(row.render(20).every(line => visibleWidth(line) <= 20));
    row.updateResult({ content: [{ type: "text", text: "done" }], details: {}, isError: false }, false);
    assert.doesNotMatch(row.render(80).join("\n"), /waiting for result/);
  });

  await test("silent running call shows arguments and heartbeat before completion", async () => {
    const args = { language: "shell", code: "sleep 2\nprintf done" };
    const updates = [];
    let finished = false;
    const work = tool.execute("silent", args, undefined, update => updates.push(update))
      .then(result => { finished = true; return result; });
    assert.match(rendered(tool.renderCall(args, theme, context())), /sleep 2/);
    assert.match(rendered(tool.renderCall(args, theme, context(true))), /printf done/);
    assert.equal(updates.length, 1, "immediate update, even without stdout");
    await delay(1050);
    assert.equal(finished, false);
    assert(updates.length >= 2);
    assert.match(rendered(tool.renderResult(updates.at(-1), { isPartial: true }, theme, context())), /Running · 1s/);
    const result = await work;
    assert.deepEqual(result, { content: [{ type: "text", text: "compressed result" }], details: {} });
    const count = updates.length;
    await delay(1050);
    assert.equal(updates.length, count, "heartbeat stops after completion");
  });

  await test("collapsed preview, expanded full code, long-line wrapping and terminal safety", () => {
    const args = { language: "javascript", code: "one\ntwo\nthree\nfour\nfive\n" + "界🙂".repeat(50) + "END\u001b[2J\u0007" };
    const ctx = context();
    const component = tool.renderCall(args, theme, ctx);
    assert.match(rendered(component), /2 more lines/);
    assert.doesNotMatch(rendered(component), /five/);
    const expanded = tool.renderCall(args, theme, { ...context(true), lastComponent: component });
    assert.equal(expanded, component);
    const lines = expanded.render(20);
    assert.match(lines.join("\n"), /END/);
    assert(!lines.join("").includes("\u001b"));
    assert(!lines.join("").includes("\u0007"));
    expanded.invalidate();
    assert.match(expanded.render(120).join("\n"), /END/);
    assert.doesNotThrow(() => tool.renderCall(undefined, theme, context()).render(1));
  });

  await test("file and batch arguments are visible, not invented runtime status", () => {
    const file = tools.get("ctx_execute_file");
    assert.match(rendered(file.renderCall({ path: "input.json", code: "print(file_content)", language: "python" }, theme, context(true))), /input.json[\s\S]*print\(file_content\)/);
    const batch = tools.get("ctx_batch_execute");
    const text = rendered(batch.renderCall({ commands: [{ label: "Tests", command: "npm test" }, { label: "Build", command: "npm run build" }] }, theme, context(true)));
    assert.match(text, /Tests[\s\S]*npm test[\s\S]*Build[\s\S]*npm run build/);
    assert.doesNotMatch(text, /completed|running/i);
  });

  await test("parallel calls have independent elapsed updates and final results", async () => {
    const a = [], b = [];
    const first = tool.execute("a", { delay: 10 }, undefined, update => a.push(update));
    const second = tool.execute("b", { delay: 1200 }, undefined, update => b.push(update));
    await first;
    await second;
    assert.equal(a.length, 1);
    assert(b.length >= 2);
  });

  await test("server errors keep failure semantics and stop heartbeats", async () => {
    const updates = [];
    await assert.rejects(tool.execute("failure", { fail: true, delay: 10 }, undefined, u => updates.push(u)), /compressed result/);
    await delay(1050);
    assert.equal(updates.length, 1);
    assert.match(rendered(tool.renderResult({ content: [{ type: "text", text: "failure" }] }, { expanded: true }, theme, { ...context(), isError: true })), /failure/);
  });

  await test("abort stops UI updates, without pretending remote work was killed", async () => {
    const updates = [];
    const abort = new AbortController();
    const work = tool.execute("abort", { delay: 1200 }, abort.signal, u => updates.push(u));
    abort.abort();
    await work;
    assert.equal(updates.length, 1);
    await assert.rejects(tool.execute("already-aborted", {}, abort.signal), { name: "AbortError" });
  });

  await test("transport rejection cleans up; headless calls need no update callback", async () => {
    const updates = [];
    const execute = createContextModeExecutor("ctx_execute", async () => { throw Error("transport failed"); });
    await assert.rejects(execute("transport", {}, undefined, u => updates.push(u)), /transport failed/);
    await delay(1050);
    assert.equal(updates.length, 1);
    assert.deepEqual(await tool.execute("headless", { delay: 1 }), { content: [{ type: "text", text: "compressed result" }], details: {} });
  });
} finally {

  await rm(directory, { recursive: true, force: true });
}
