import assert from 'node:assert/strict';
const { reviewSections, runReviewSections } = await import(process.argv[2] ?? '../patches/pi-goals/review-batches.mjs');
const headSha = 'a'.repeat(40), attemptId = 'attempt';
const diff = 'diff --git a/one b/one\n' + '+a\n'.repeat(30) + 'diff --git a/two b/two\n+b\n';
const sections = reviewSections(diff, 64);
assert(sections.length > 1);
assert.equal(sections.map(s => s.replace(/^diff --git .*\n\[continued diff\]\n/, '')).join(''), diff);
assert.throws(() => reviewSections(''), /empty/);
assert.equal(reviewSections('diff --git a/one b/one\n+a\n').length, 1);
const input = { prompts: sections, attemptId, headSha };
const verdict = (decision = 'clean', findings = []) => ({ verdict: JSON.stringify({ schemaVersion: 1, attemptId, headSha, decision, findings }) });
let running = 0, count = 0;
const result = await runReviewSections(input, async () => {
  assert.equal(running++, 0);
  await Promise.resolve();
  running--; count++;
  return verdict();
});
assert.equal(count, sections.length);
assert.equal(result.sections.length, sections.length);
assert.equal(JSON.parse(result.verdict).decision, 'clean');
count = 0;
const findings = await runReviewSections(input, async () => ++count === 1 ? verdict('changes_requested', ['file:1 defect']) : verdict());
assert.deepEqual(JSON.parse(findings.verdict).findings, ['file:1 defect']);
for (const bad of [verdict('clean', ['contradiction']), verdict('changes_requested'), { verdict: '{}' }, { verdict: verdict().verdict.replace(headSha, 'b'.repeat(40)) }, { verdict: verdict().verdict.replace(attemptId, 'stale') }]) {
  await assert.rejects(runReviewSections(input, async () => bad));
}
await assert.rejects(runReviewSections(input, async () => { throw Error('launch failed'); }), /launch failed/);
const abort = new AbortController();
await assert.rejects(runReviewSections(input, async () => { abort.abort(); return verdict(); }, abort.signal), /interrupted/);
console.log('Section coverage, sequential execution, aggregation, malformed/stale verdicts, launch failure and interruption passed.');
const progress = [];
await runReviewSections({ ...input, integrationIndex: sections.length - 1 }, async () => verdict(), undefined,
  update => progress.push(update));
assert.equal(progress.length, sections.length * 2);
assert.equal(progress[0].completed, 0);
assert.equal(progress[0].total, sections.length);
assert.equal(progress.at(-2).phase, 'integration');
assert.equal(progress.at(-1).completed, sections.length);
assert(progress.at(-1).lastCompletedAt);
const invalidProgress = [];
await assert.rejects(runReviewSections(input, async () => ({ verdict: '{}' }), undefined,
  update => invalidProgress.push(update)));
assert.equal(invalidProgress.length, 1, 'Malformed verdict must not advance progress');
const cancelledProgress = [];
const cancelled = new AbortController();
await assert.rejects(runReviewSections({ ...input, prompts: ['only'] }, async () => {
  cancelled.abort(); return verdict();
}, cancelled.signal, update => cancelledProgress.push(update)), /interrupted/);
assert.equal(cancelledProgress.length, 1, 'Cancellation during final section must not advance progress');
console.log('Progress counts, integration phase, invalid verdict and final-section cancellation passed.');

// Checkpoints are host evidence, survive a retry/reload, and never rebind raw
// reviewer verdicts to a different attempt. Only the aggregate uses the new ID.
let checkpoint;
const durable = { ...input, prompts: ['one attempt /snapshot/old', 'two attempt /snapshot/old', 'integration attempt /snapshot/old'],
  cwd: '/snapshot/old', reviewer: { provider: 'fixture', model: 'exact' }, policy: 'v1', goalId: 'goal', baseSha: 'c'.repeat(40),
  integrationIndex: 2, onCheckpoint: saved => { checkpoint = saved; } };
let calls = 0;
await assert.rejects(runReviewSections(durable, async () => {
  if (++calls === 2) throw Error('interrupted transport');
  return verdict();
}), /transport/);
assert.equal(checkpoint.verdicts.length, 1);
const saved = structuredClone(checkpoint);
const resumed = { ...durable, attemptId: 'next', cwd: '/snapshot/new',
  prompts: durable.prompts.map(p => p.replaceAll('attempt', 'next').replaceAll('/snapshot/old', '/snapshot/new')),
  checkpoint: saved };
const response = id => ({ verdict: JSON.stringify({ schemaVersion: 1, attemptId: id, headSha, decision: 'clean', findings: [] }) });
calls = 0;
const completed = await runReviewSections(resumed, async () => { calls++; return response('next'); });
assert.equal(calls, 2);
assert.equal(completed.sections[0].attemptId, 'attempt');
assert.equal(JSON.parse(completed.verdict).attemptId, 'next');
for (const change of [
  { headSha: 'b'.repeat(40) }, { baseSha: 'd'.repeat(40) }, { reviewer: { provider: 'fixture', model: 'other' } },
  { policy: 'v2' }, { goalId: 'other' }, { prompts: ['changed', 'two', 'integration'] },
  { identity: { baseBranch: 'release' } }, { integrationIndex: 1 },
]) {
  calls = 0;
  const altered = { ...resumed, ...change };
  await runReviewSections(altered, async () => { calls++; return { verdict: JSON.stringify({
    schemaVersion: 1, attemptId: 'next', headSha: altered.headSha, decision: 'clean', findings: [] }) }; });
  assert.equal(calls, 3, 'Changed review inputs must invalidate every checkpoint');
}
let retries = 0;
await runReviewSections({ ...input, prompts: ['one'] }, async () => {
  if (++retries < 3) throw Object.assign(Error('503'), { category: 'transient_provider', retryable: true });
  return verdict();
});
assert.equal(retries, 3);
retries = 0;
await assert.rejects(runReviewSections({ ...input, prompts: ['one'] }, async () => {
  retries++; throw Object.assign(Error('persistent 503'), { category: 'transient_provider', retryable: true });
}), /persistent/);
assert.equal(retries, 3);
console.log('Durable checkpoint resume/invalidation and bounded transient section recovery passed.');
const corrupt = structuredClone(saved);
corrupt.verdicts[0].findings = ['contradicts clean'];
await assert.rejects(runReviewSections({ ...resumed, checkpoint: corrupt }, async () => assert.fail('Corrupt evidence must never be used')),
  /Invalid host section evidence/);
const backoffAbort = new AbortController();
let backoffCalls = 0;
await assert.rejects(runReviewSections({ ...input, prompts: ['one'] }, async () => {
  backoffCalls++;
  throw Object.assign(Error('503'), { category: 'transient_provider', retryable: true });
}, backoffAbort.signal, progress => { if (progress.retry) backoffAbort.abort(); }), /abort/i);
assert.equal(backoffCalls, 1, 'Cancellation during backoff must prevent the next launch');
let authCalls = 0;
await assert.rejects(runReviewSections({ ...input, prompts: ['one'] }, async () => {
  authCalls++;
  throw Object.assign(Error('authentication'), { category: 'authentication', retryable: false });
}), /authentication/);
assert.equal(authCalls, 1);
console.log('Corrupt checkpoint rejection, authentication fail-fast and cancellation during backoff passed.');
