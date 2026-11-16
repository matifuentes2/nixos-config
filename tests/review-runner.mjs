import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
const root = resolve(process.argv[2] ?? 'patches/pi-goals');
const { runReviewer } = await import(pathToFileURL(join(root, process.argv[2] ? 'dist/review-runner.mjs' : 'review-runner.mjs')));
const temporary = mkdtempSync(join(tmpdir(), 'review-runner-test-'));
const fixture = join(temporary, 'runner.mjs');
const message = { role: 'assistant', provider: 'fixture', model: 'exact', stopReason: 'stop', content: [{ type: 'text', text: '{}' }] };
const output = (...events) => events.map(event => `console.log(${JSON.stringify(JSON.stringify(event))});`).join('\n');
const ending = output({ type: 'message_end', message }, { type: 'agent_end' });
const run = (script, signal, updates = []) => {
  writeFileSync(fixture, `process.stdin.resume();\n${script}`);
  return runReviewer('fixture', 'exact', 'private prompt', signal, process.execPath,
    update => updates.push(structuredClone(update)), [fixture]);
};
try {
  const updates = [];
  assert.equal((await run(ending, undefined, updates)).verdict, '{}');
  assert.equal(updates.at(-1).subprocess.exitCode, 0);
  assert.equal(updates.at(-1).subprocess.events, 2);
  assert(!JSON.stringify(updates).includes('private prompt'));
  const assistant = value => ({ type: 'message_end', message: value });
  const failedTurn = stopReason => assistant({ ...message, stopReason, errorMessage: 'Request timed out.' });
  const agentEnd = { type: 'agent_end' };
  const retryStart = attempt => ({ type: 'auto_retry_start', attempt, maxAttempts: 3 });
  const retryEnd = attempt => ({ type: 'auto_retry_end', attempt, success: true });
  const toolTurn = assistant({ ...message, stopReason: 'toolUse', content: [] });
  // Real Pi ordering: a failed agent ends before retrying; success is reported
  // after the retry's first assistant turn, which may itself request a tool.
  const recovered = [failedTurn('error'), agentEnd, retryStart(1), toolTurn,
    retryEnd(1), assistant(message), agentEnd];
  assert.equal((await run(output(...recovered))).verdict, '{}');
  assert.equal((await run(output(failedTurn('error'), agentEnd, retryStart(1),
    assistant(message), retryEnd(1), agentEnd))).verdict, '{}');
  assert.equal((await run(output(failedTurn('error'), agentEnd, retryStart(1),
    failedTurn('error'), agentEnd, retryStart(2), toolTurn, retryEnd(2),
    assistant(message), agentEnd))).verdict, '{}');
  for (const [name, events] of [
    ['later verdict without retry', [failedTurn('error'), assistant(message), agentEnd]],
    ['unpaired recovery', [failedTurn('error'), toolTurn, retryEnd(1), assistant(message), agentEnd]],
    ['wrong recovery attempt', [failedTurn('error'), retryStart(1), toolTurn, retryEnd(2), assistant(message), agentEnd]],
    ['missing attempt', [failedTurn('error'), { type: 'auto_retry_start' }, toolTurn, retryEnd(1), assistant(message), agentEnd]],
    ['unfinished retry', [failedTurn('error'), retryStart(1), assistant(message), agentEnd]],
    ['no successful retry turn', [failedTurn('error'), retryStart(1), retryEnd(1), assistant(message), agentEnd]],
    ['exhausted retry', [failedTurn('error'), retryStart(1), toolTurn, { ...retryEnd(1), success: false }, assistant(message), agentEnd]],
    ['malformed retry result', [failedTurn('error'), retryStart(1), toolTurn, { type: 'auto_retry_end', attempt: 1 }, assistant(message), agentEnd]],
    ['subsequent error', [...recovered, failedTurn('error'), assistant(message), agentEnd]],
    ['missing final agent end', recovered.slice(0, -1)],
    ['cancellation is permanent', [{ ...recovered[0], message: { ...message, stopReason: 'aborted' } }, ...recovered.slice(1)]],
    ['truncation is permanent', [{ ...recovered[0], message: { ...message, stopReason: 'length' } }, ...recovered.slice(1)]],
    ['extension failure is permanent', [{ type: 'extension_error' }, ...recovered]],
    ['intermediate model substitution', [assistant({ ...message, model: 'other', stopReason: 'toolUse' }), assistant(message), agentEnd]],
    ['intermediate provider substitution', [assistant({ ...message, provider: 'other', stopReason: 'toolUse' }), assistant(message), agentEnd]],
  ]) {
    await assert.rejects(run(output(...events)), /exact requested/, name);
  }
  for (const [script, expected] of [
    [output({ type: 'message_end', message: { ...message, stopReason: 'error', errorMessage: 'provider rate limit' } }, { type: 'agent_end' }), /stop=error.*provider rate limit/],
    [output({ type: 'message_end', message }), /stop=stop/],
    [output({ type: 'message_end', message: { ...message, model: 'wrong' } }, { type: 'agent_end' }), /exact requested/],
    ["console.log('not-json');", /JSON/],
    ["console.error('service unavailable'); process.exitCode = 7;", /exit=7.*service unavailable/],
    [ending + output({ type: 'auto_retry_end', success: false }), /exact requested/],
  ]) {
    await assert.rejects(run(script), error => {
      assert.match(error.message, expected);
      assert(error.reviewDiagnostics.elapsedMs >= 0);
      assert.equal(typeof error.reviewDiagnostics.stdoutBytes, 'number');
      return true;
    });
  }
  await assert.rejects(run("console.error('authorization=private-value https://example.invalid/private'); process.exitCode = 1;"), error => {
    assert(!JSON.stringify(error.reviewDiagnostics).includes('private-value'));
    assert(!JSON.stringify(error.reviewDiagnostics).includes('example.invalid'));
    return true;
  });
  const cancellation = new AbortController();
  const cancelled = run('setInterval(() => {}, 1000);', cancellation.signal);
  setTimeout(() => cancellation.abort(), 100);
  await assert.rejects(cancelled, /interrupted/);
  await assert.rejects(runReviewer('fixture', 'exact', '', undefined, join(temporary, 'missing')), error => {
    assert.equal(error.reviewDiagnostics.events, 0);
    return /ENOENT/.test(error.message);
  });
  const pulse = [];
  await run(output({ type: 'tool_execution_start', toolName: 'read', args: { path: 'private-file' } }) +
    `setTimeout(() => { ${ending} }, 10500);`, undefined, pulse);
  const heartbeat = pulse.find(update => update.subprocess.exitCode === undefined && update.subprocess.events === 1);
  assert(heartbeat, 'Quiet subprocess must publish a pulse before exit');
  assert(heartbeat.subprocess.lastEventAt);
  assert(!JSON.stringify(pulse).includes('private-file'));
  console.log('Reviewer subprocess diagnostics, redaction, quiet pulse, failure and cancellation passed.');
} finally { rmSync(temporary, { recursive: true, force: true }); }
