// Exercise the shipped dist entry, not TypeScript sources or a model-backed session.
// Run with the packaged Bun: bun tests/pi-goal-lifecycle-smoke.mjs <goal-package>
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const root = resolve(process.argv[2] || assert.fail("Pass the built pi-codex-goal package"));
const temporary = mkdtempSync(join(tmpdir(), "pi-goal-lifecycle-"));
process.env.HOME = temporary;
process.env.PI_CODING_AGENT_DIR = temporary;

const handlers = new Map();
const tools = new Map();
const entries = [];
const sent = [];
const userSent = [];
const commands = new Map();
const bus = new Map();
let aborts = 0;
const pi = {
  on(name, handler) {
    const list = handlers.get(name) || [];
    list.push(handler);
    handlers.set(name, list);
  },
  registerTool(tool) { tools.set(tool.name, tool); },
  registerCommand(name, command) { commands.set(name, command); },
  registerShortcut() {},
  getCommands: () => [{ name: "goal", sourceInfo: { path: root } }],
  events: {
    on(name, listener) {
      const listeners = bus.get(name) || new Set();
      listeners.add(listener); bus.set(name, listeners);
      return () => listeners.delete(listener);
    },
    emit(name, payload) { for (const listener of bus.get(name) || []) listener(payload); },
  },
  exec: async (program, args) => ({ code: 0, killed: false, stderr: "", stdout:
    program === "git" && args[0] === "rev-parse" ? temporary :
    program === "gh" && args[1] === "view" ? JSON.stringify({ baseRefName: "main", headRefOid: "a".repeat(40), mergeable: "MERGEABLE" }) : "" }),
  appendEntry(customType, data) {
    entries.push({ type: "custom", id: `entry-${entries.length}`, customType, data,
      parentId: null, timestamp: new Date().toISOString() });
  },
  sendMessage(message, options) { sent.push({ message, options }); },
  sendUserMessage(message) { userSent.push(message); },
};
const ctx = {
  cwd: temporary,
  hasUI: false,
  mode: "rpc",
  isIdle: () => true,
  hasPendingMessages: () => false,
  getContextUsage: () => undefined,
  model: { provider: "smoke", id: "review-model", contextWindow: 128000 },
  modelRegistry: { find: (provider, model) => provider === "smoke" && model === "review-model" ? ctx.model : undefined },
  abort() { aborts++; },
  ui: { setStatus() {}, notify() {}, confirm() { assert.fail("Unexpected UI prompt"); } },
  sessionManager: {
    getBranch: () => entries,
    getEntries: () => entries,
    getSessionId: () => "lifecycle-smoke",
  },
};
async function emit(type, fields = {}) {
  assert(handlers.has(type), `Missing lifecycle handler: ${type}`);
  for (const handler of handlers.get(type)) await handler({ type, ...fields }, ctx);
}
async function call(name, params = {}) {
  assert(tools.has(name), `Shipped extension must expose ${name}`);
  return tools.get(name).execute("smoke-call", params, undefined, undefined, ctx);
}
const goal = async () => (await call("get_goal")).details.goal;
const assistant = (input, output) => ({
  role: "assistant", content: [{ type: "text", text: "Waiting for external work." }],
  stopReason: "stop", usage: { input, output, cacheRead: 0, cacheWrite: 0 },
});
async function finishTurn(index, input = 0, output = 0) {
  const message = assistant(input, output);
  await emit("turn_start", { turnIndex: index, timestamp: Date.now() });
  await emit("turn_end", { turnIndex: index, message, toolResults: [] });
  await emit("agent_end", { messages: [message] });
}

try {
  const manifest = JSON.parse(readFileSync(join(root, "package.json"), "utf8"));
  assert.deepEqual(manifest.pi.extensions, ["./dist/index.js"]);
  const { default: extension } = await import(pathToFileURL(join(root, manifest.pi.extensions[0])));
  extension(pi);
  await emit("session_start", { reason: "startup" });
  await call("create_goal", { objective: "Wait for a review, then finish the requested work", token_budget: 100 });
  const initial = await goal();

  // Pi 1.4 user starts and Pi 1.5 discriminated starts must both work.
  await emit("before_agent_start", { prompt: "continue", systemPrompt: "", systemPromptOptions: {} });
  await emit("before_agent_start", { messageType: "user", prompt: "continue",
    systemPrompt: "", systemPromptOptions: {} });
  await emit("before_agent_start", { messageType: "custom",
    message: { role: "custom", customType: "unrelated-extension", content: "hello", display: false },
    systemPrompt: "", systemPromptOptions: {} });
  assert.equal((await goal()).goalId, initial.goalId);

  // A completed turn must generate an actual continuation, which can start
  // another turn without the missing-prompt crash seen on Pi 1.5.
  await finishTurn(0, 8, 2);
  const continuation = sent.find(({ message }) => message.details?.kind === "continuation");
  assert(continuation, "Active goals must queue an automatic continuation");
  assert.equal(continuation.options.triggerTurn, true);
  await emit("before_agent_start", { messageType: "custom",
    message: { ...continuation.message, role: "custom" }, systemPrompt: "", systemPromptOptions: {} });
  await emit("message_start", { message: { ...continuation.message, role: "custom" } });
  assert.equal((await goal()).tokensUsed, 10);

  const beforePause = await goal();
  await call("pause_goal");
  const paused = await goal();
  assert.equal(paused.status, "paused");
  for (const key of ["goalId", "objective", "tokenBudget", "createdAt"]) {
    assert.deepEqual(paused[key], beforePause[key], `Pause must preserve ${key}`);
  }
  assert.equal(paused.tokensUsed, beforePause.tokensUsed);
  assert(paused.timeUsedSeconds >= beforePause.timeUsedSeconds);
  sent.length = 0;
  await finishTurn(1);
  await finishTurn(2);
  assert.equal(sent.length, 0, "Paused waiting goals must not queue repeated continuations");
  assert.equal((await goal()).status, "paused");

  await call("resume_goal");
  const resumed = await goal();
  assert.equal(resumed.status, "active");
  for (const key of ["goalId", "objective", "tokenBudget", "createdAt", "tokensUsed", "timeUsedSeconds"]) {
    assert.deepEqual(resumed[key], paused[key], `Resume must preserve ${key}`);
  }

  // Resuming never grants a new token budget, nor revives a limited goal.
  await finishTurn(3, 80, 10);
  const limited = await goal();
  assert.equal(limited.status, "budgetLimited");
  assert.equal(limited.tokensUsed, 100);
  await assert.rejects(() => call("resume_goal"));
  assert.equal((await goal()).status, "budgetLimited");
  assert.equal((await goal()).goalId, initial.goalId);
  assert.equal(aborts, 0, "Live continuations must not be mistaken for stale work");
  assert.equal(userSent.length, 0, "Generic lifecycle must not enqueue user messages");
  console.log("Shipped goal lifecycle passed: user/custom starts, continuation, pause/resume, and budget enforcement.");

  if (process.argv[3]) {
    // Test both actual packaged entrypoints, with no model/network dependency.
    await call("update_goal", { status: "complete" });
    const reviewRoot = resolve(process.argv[3]);
    const reviewManifest = JSON.parse(readFileSync(join(reviewRoot, "package.json"), "utf8"));
    const { default: reviewExtension } = await import(pathToFileURL(join(reviewRoot, reviewManifest.pi.extensions[0], "pr-review-goal.ts")));
    reviewExtension(pi);
    await emit("session_start", { reason: "resume" });
    // Historical generic completion stays complete; the new protected start works.
    await commands.get("pr-review-goal").handler("7 --base main", ctx);
    assert.equal((await goal()).status, "active");
    const protectedSnapshot = () => entries.filter(entry => entry.data?.kind === "set").at(-1).data.goal;
    assert.equal(protectedSnapshot().completionPolicy.id, "pi-pr-review-goal/reviewer-success/v1");
    await assert.rejects(() => call("update_goal", { status: "complete" }), /No fresh reviewer execution evidence/);
    assert.equal((await goal()).status, "paused");
    assert.deepEqual(protectedSnapshot().completionPolicy.reviewer, { provider: "smoke", model: "review-model" });
    assert.deepEqual((await goal()).reviewer, { provider: "smoke", model: "review-model" });
    // The default command supplies the selection. If it later becomes unavailable,
    // the zero-argument tool fails on that same model rather than choosing another.
    ctx.modelRegistry.find = () => undefined;
    await assert.rejects(() => call("run_goal_review"), /Unknown exact reviewer model/);
    assert.equal(protectedSnapshot().reviewExecution.status, "launch_failed");
    await emit("session_start", { reason: "resume" });
    await assert.rejects(() => call("update_goal", { status: "complete" }), /review-failed/);
    assert.equal((await goal()).status, "paused");
    console.log("Shipped PR-review policy passed: protected start, missing evidence, failed model launch, durable ledger, and fail-closed restore.");
  }
} finally {
  if (handlers.has("session_shutdown")) await emit("session_shutdown");
  rmSync(temporary, { recursive: true, force: true });
}
