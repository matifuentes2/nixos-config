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
let aborts = 0;
const pi = {
  on(name, handler) {
    const list = handlers.get(name) || [];
    list.push(handler);
    handlers.set(name, list);
  },
  registerTool(tool) { tools.set(tool.name, tool); },
  registerCommand() {},
  registerShortcut() {},
  events: { on: () => () => {} },
  appendEntry(customType, data) {
    entries.push({ type: "custom", id: `entry-${entries.length}`, customType, data,
      parentId: null, timestamp: new Date().toISOString() });
  },
  sendMessage(message, options) { sent.push({ message, options }); },
  sendUserMessage() { assert.fail("This headless lifecycle must not send user messages"); },
};
const ctx = {
  cwd: temporary,
  hasUI: false,
  mode: "rpc",
  isIdle: () => true,
  hasPendingMessages: () => false,
  getContextUsage: () => undefined,
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
  console.log("Shipped goal lifecycle passed: user/custom starts, continuation, pause/resume, and budget enforcement.");
} finally {
  if (handlers.has("session_shutdown")) await emit("session_shutdown");
  rmSync(temporary, { recursive: true, force: true });
}
