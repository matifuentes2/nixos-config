// Exercise the shipped dist entry, not TypeScript sources or a model-backed session.
// Run with the packaged Bun: bun tests/pi-goal-lifecycle-smoke.mjs <goal-package>
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
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
const head = "a".repeat(40);
const mixedChecks = [
  ...Array.from({ length: 22 }, (_, i) => ({ name: `passing-${i}`, state: "SUCCESS", bucket: "pass" })),
  ...Array.from({ length: 11 }, (_, i) => ({ name: `conditional-${i}`, state: "SKIPPED", bucket: "skipping" })),
];
let checks = mixedChecks;

const originalPath = process.env.PATH;
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
    program === "git" && args[0] === "rev-parse" ? (args[1] === "HEAD" ? head : temporary) :
    program === "gh" && args[1] === "view" ? JSON.stringify({ baseRefName: "main", headRefOid: head, mergeable: "MERGEABLE" }) :
    program === "gh" && args[1] === "checks" ? JSON.stringify(checks) : "" }),
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
    // Replacement is cancellation, not completion: the model must not swap the
    // protected goal for a generic one that it could then complete instead.
    const protectedGoalId = (await goal()).goalId;
    await assert.rejects(() => call("create_goal", { objective: "Declare review done", replace_existing: true }),
      /protected goal cannot be replaced/);
    assert.equal((await goal()).goalId, protectedGoalId);
    assert.equal(protectedSnapshot().completionPolicy.id, "pi-pr-review-goal/reviewer-success/v1");
    console.log("Shipped PR-review policy passed: model-initiated replacement of the protected goal is refused.");
    // A transient setup error must give the parent a bounded repair opportunity.
    // The first prior failure was already recorded while the goal was paused.
    await call("resume_goal");
    await assert.rejects(() => call("run_goal_review"), /attempt 2\/3; goal remains active/);
    assert.equal((await goal()).status, "active");
    await emit("session_start", { reason: "resume" });
    await assert.rejects(() => call("run_goal_review"), /Goal paused/);
    assert.equal((await goal()).status, "paused");
    assert.equal(protectedSnapshot().reviewExecution.consecutiveFailures, 3);
    assert.match((await goal()).objective, /CI and a clean code verdict do not substitute/);
    assert.doesNotMatch((await goal()).objective, /codex|chatgpt-codex-connector/i);
    assert.match((await goal()).objective, /fresh review -> fixes/);
    console.log("Shipped recovery passed: bounded repair attempts survive session reload and pause after three failures.");
    ctx.modelRegistry.find = (provider, model) => provider === "smoke" && model === "review-model" ? ctx.model : undefined;
    const successfulExec = pi.exec;
    pi.exec = async () => ({ code: 1, killed: false, truncated: false, stdout: "", stderr: "temporary GitHub API failure" });
    await assert.rejects(() => call("run_goal_review"), /exit=1.*temporary GitHub API failure/);
    pi.exec = successfulExec;
    console.log("Shipped diagnostics passed: failed gh preparation preserves exit and stderr.");
    // A deterministic subprocess fixture, not a paid/external model review. Exercise
    // successful execution and actual protected persistence in the shipped pair.
    writeFileSync(join(temporary, "pi"), `#!${process.execPath}
let prompt = '';
for await (const chunk of process.stdin) prompt += chunk;
const verdict = JSON.parse(prompt.match(/exactly these keys: (\\{.*?\\})\\. Use/)[1]);
const args = process.argv;
const message = { role: 'assistant', provider: args[args.indexOf('--provider') + 1], model: args[args.indexOf('--model') + 1],
  stopReason: 'stop', content: [{ type: 'text', text: JSON.stringify(verdict) }] };
console.log(JSON.stringify({ type: 'message_end', message }));
console.log(JSON.stringify({ type: 'agent_end', messages: [message] }));
`, { mode: 0o755 });
    process.env.PATH = `${temporary}:${originalPath || ""}`;
    ctx.modelRegistry.find = (provider, model) => provider === "smoke" && model === "review-model" ? ctx.model : undefined;
    await call("resume_goal");
    await call("run_goal_review");
    const review = structuredClone(protectedSnapshot().reviewExecution);
    assert.equal(review.status, "completed");
    assert.equal(review.headSha, head);
    assert.equal(JSON.parse(review.verdict).attemptId, review.attemptId);
    for (const blockedChecks of [
      [...mixedChecks, { name: "prerequisite", state: "FAILURE", bucket: "fail" }],
      [...mixedChecks, { name: "prerequisite", state: "PENDING", bucket: "pending" }],
      [...mixedChecks, { name: "prerequisite", state: "CANCELLED", bucket: "cancel" }],
      mixedChecks.filter(row => row.state === "SKIPPED"), [],
    ]) {
      checks = blockedChecks;
      await assert.rejects(() => call("update_goal", { status: "complete" }), /ci-blocked/);
      assert.notEqual((await goal()).status, "complete");
    }
    await call("pause_goal");
    assert.equal((await goal()).status, "paused");
    await emit("session_start", { reason: "resume" });
    checks = mixedChecks;
    await call("update_goal", { status: "complete" });
    assert.equal((await goal()).status, "complete");
    assert.deepEqual(protectedSnapshot().reviewExecution, review);
    console.log("Shipped CI policy passed: 22 passing + 11 skipped complete; failure/pending/cancelled, absent and all-skipped CI block; durable review survives restore and recovery.");
  }
} finally {
  if (originalPath === undefined) delete process.env.PATH;
  else process.env.PATH = originalPath;
  if (handlers.has("session_shutdown")) await emit("session_shutdown");
  rmSync(temporary, { recursive: true, force: true });
}
