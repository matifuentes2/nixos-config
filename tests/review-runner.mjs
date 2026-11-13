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
