import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
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
let count = 0;
const result = await runReviewSections(input, async () => { await Promise.resolve(); count++; return verdict(); });
assert.equal(count, sections.length);
assert.equal(result.sections.length, sections.length);
assert.equal(JSON.parse(result.verdict).decision, 'clean');
count = 0;
const findings = await runReviewSections(input, async () => ++count === 1 ? verdict('changes_requested', ['file:1 defect']) : verdict());
assert.deepEqual(JSON.parse(findings.verdict).findings, ['file:1 defect']);
for (const bad of [verdict('changes_requested'), { verdict: '{}' }, { verdict: verdict().verdict.replace(headSha, 'b'.repeat(40)) }, { verdict: verdict().verdict.replace(attemptId, 'stale') }]) {
  await assert.rejects(runReviewSections(input, async () => bad));
}
await assert.rejects(runReviewSections(input, async () => { throw Error('launch failed'); }), /launch failed/);
const abort = new AbortController();
await assert.rejects(runReviewSections(input, async () => { abort.abort(); return verdict(); }, abort.signal), /interrupted/);
console.log('Section coverage, aggregation, malformed/stale verdicts, launch failure and interruption passed.');
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
await assert.rejects(runReviewSections({ ...input, prompts: ['one'] }, async () => ({ verdict: '{}' }), undefined,
  update => invalidProgress.push(update)));
assert(invalidProgress.every(update => !update.completed), 'Malformed verdict must not advance progress');
assert.equal(invalidProgress.filter(update => update.retryCategory === 'invalid_verdict').length, 2);
const cancelledProgress = [];
const cancelled = new AbortController();
await assert.rejects(runReviewSections({ ...input, prompts: ['only'] }, async () => {
  cancelled.abort(); return verdict();
}, cancelled.signal, update => cancelledProgress.push(update)), /interrupted/);
assert.equal(cancelledProgress.length, 1, 'Cancellation during final section must not advance progress');
console.log('Progress counts, integration phase, invalid verdict and final-section cancellation passed.');

// Sections run concurrently up to the limit; integration waits for all of them.
{
  const { SECTION_CONCURRENCY } = await import(process.argv[2] ?? '../patches/pi-goals/review-batches.mjs');
  assert.equal(SECTION_CONCURRENCY, 4);
  const prompts = Array.from({ length: 9 }, (_, i) => i === 8 ? 'integration' : `section ${i}`);
  let active = 0, peak = 0, integrationActive = 0;
  const finished = [];
  const updates = [];
  const parallel = await runReviewSections({ ...input, prompts, integrationIndex: 8 }, async prompt => {
    if (prompt === 'integration') { integrationActive = active; assert.equal(finished.length, 8); }
    active++; peak = Math.max(peak, active);
    // Later sections finish first, so completion order differs from launch order.
    await delay(prompt === 'integration' ? 1 : 40 - 4 * Number(prompt.split(' ')[1]));
    active--; finished.push(prompt);
    return verdict(prompt === 'section 5' ? 'changes_requested' : 'clean', prompt === 'section 5' ? ['five.ts:1 defect'] : []);
  }, undefined, update => updates.push(update));
  assert.equal(peak, SECTION_CONCURRENCY);
  assert.equal(integrationActive, 0, 'Integration must start after every section is validated');
  assert.notDeepEqual(finished.slice(0, 8), prompts.slice(0, 8), 'Fixture must complete sections out of order');
  assert.equal(parallel.sections.length, 9);
  assert.deepEqual(JSON.parse(parallel.verdict).findings, ['five.ts:1 defect']);
  assert(updates.some(u => u.running?.length === SECTION_CONCURRENCY));
  const completions = updates.filter(u => u.lastCompletedAt).map(u => u.completed);
  assert.deepEqual(completions, [1, 2, 3, 4, 5, 6, 7, 8, 9], 'Validated counts must increase by one per section');
  let serial = 0, serialPeak = 0;
  await runReviewSections({ ...input, prompts, integrationIndex: 8, concurrency: 1 }, async () => {
    serialPeak = Math.max(serialPeak, ++serial); await delay(1); serial--; return verdict();
  });
  assert.equal(serialPeak, 1);

  // A failure stops new launches. Running sections finish and are saved out of
  // order, and the lowest failed step is reported regardless of timing.
  let saved, launched = [];
  const failureUpdates = [];
  const durableFailure = { ...input, prompts, integrationIndex: 8, concurrency: 3, onCheckpoint: c => { saved = c; } };
  await assert.rejects(runReviewSections(durableFailure, async prompt => {
    launched.push(prompt);
    if (prompt === 'section 2') { await delay(1); throw Error('second failure'); }
    if (prompt === 'section 1') { await delay(5); throw Error('first failure'); }
    await delay(15);
    return verdict();
  }, undefined, update => failureUpdates.push(update)), /first failure/);
  assert.deepEqual(launched, ['section 0', 'section 1', 'section 2']);
  assert.equal(failureUpdates.at(-1).current, 2, 'The lowest failed step must be reported');
  assert.equal(saved.verdicts.length, 1);
  assert.equal(saved.outOfOrder, undefined);
  launched = [];
  await assert.rejects(runReviewSections({ ...durableFailure, checkpoint: saved }, async prompt => {
    launched.push(prompt);
    if (prompt === 'section 1') { await delay(5); throw Error('still failing'); }
    await delay(15);
    return verdict();
  }), /still failing/);
  assert.deepEqual(launched, ['section 1', 'section 2', 'section 3']);
  assert.equal(saved.verdicts.length, 1);
  assert.deepEqual(Object.keys(saved.outOfOrder), ['2', '3']);
  // Resume runs only the missing sections, then integration.
  launched = [];
  const resumedParallel = await runReviewSections({ ...durableFailure, checkpoint: saved }, async prompt => {
    launched.push(prompt); return verdict();
  });
  assert.deepEqual(launched.slice(0, -1).sort(), ['section 1', 'section 4', 'section 5', 'section 6', 'section 7']);
  assert.equal(launched.at(-1), 'integration');
  assert.equal(resumedParallel.sections.length, 9);
  assert.equal(saved.verdicts.length, 9);
  assert.equal(saved.outOfOrder, undefined);
  // Out-of-order evidence is validated like the prefix and never trusted blindly.
  for (const outOfOrder of [{ '1': saved.verdicts[1] }, { '9': saved.verdicts[1] }, { x: saved.verdicts[1] }, []]) {
    await assert.rejects(runReviewSections({ ...durableFailure, checkpoint: { key: saved.key, verdicts: [saved.verdicts[0]], outOfOrder } },
      async () => assert.fail('Invalid checkpoint must not launch reviewers')), /Invalid host review checkpoint/);
  }
  await assert.rejects(runReviewSections({ ...durableFailure, checkpoint: { key: saved.key, verdicts: [saved.verdicts[0]],
    outOfOrder: { '3': { ...saved.verdicts[3], findings: ['contradicts clean'] } } } },
    async () => assert.fail('Corrupt evidence must never be used')), /Invalid host section evidence/);
  // Cancellation stops new launches and reports interruption.
  const stop = new AbortController();
  launched = [];
  await assert.rejects(runReviewSections({ ...input, prompts, integrationIndex: 8 }, async prompt => {
    launched.push(prompt);
    if (prompt === 'section 3') stop.abort();
    await delay(1);
    return verdict();
  }, stop.signal), /interrupted/);
  assert.equal(launched.length, SECTION_CONCURRENCY);
}
console.log('Bounded concurrent sections, integration ordering, out-of-order checkpoints, failure and cancellation passed.');

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

// Later rounds cover the fix diff and every prior blocker, never just the diff.
const { reviewPlan, usableBaseline, nextReviewBaseline, addUsage, reviewResultText, sectionVerdictProblem } =
  await import(process.argv[2] ?? '../patches/pi-goals/review-batches.mjs');
const reviewer = { provider: 'fixture', model: 'exact' };
const baseline = { version: 1, headSha, baseSha: 'c'.repeat(40), mergeBaseSha: 'd'.repeat(40), reviewer, findings: [] };
const fullPlan = reviewPlan({ prefix: 'P ', diff, limit: 64 });
assert.equal(fullPlan.scope, 'full');
assert.equal(fullPlan.integrationIndex, fullPlan.prompts.length - 1);
const fixDiff = 'diff --git a/one b/one\n+fixed\n';
const fixPlan = reviewPlan({ prefix: 'P ', diff, baseline: { ...baseline, findings: ['other.ts:9 still broken'] }, fixDiff });
assert.equal(fixPlan.scope, 'fixes');
assert.equal(fixPlan.prompts.length, 1);
assert.match(fixPlan.prompts[0], /other\.ts:9 still broken/);
assert.match(fixPlan.prompts[0], /\+fixed/);
assert(!fixPlan.prompts[0].includes('diff --git a/two'), 'Unchanged files must stay out of a fix round');
const recheck = reviewPlan({ prefix: 'P ', diff, baseline: { ...baseline, findings: ['disputed'] }, fixDiff: '' });
assert.equal(recheck.prompts.length, 1);
assert.match(recheck.prompts[0], /disputed/);
const manyPriors = reviewPlan({ prefix: 'P ', diff, baseline: { ...baseline, findings: ['a'.repeat(40), 'b'.repeat(40)] }, fixDiff: '', limit: 64 });
assert.equal(manyPriors.prompts.length, 2, 'Oversized prior findings must be split, not dropped');
const unchanged = reviewPlan({ prefix: 'P ', diff, baseline, fixDiff: '' });
assert.equal(unchanged.carryClean, true);
assert.equal(unchanged.prompts.length, 0);
assert.equal(reviewPlan({ prefix: 'P ', diff, baseline: { ...baseline, findings: ['open'] }, fixDiff: '' }).carryClean, undefined,
  'Open blockers must never carry forward as clean');
let carriedCalls = 0;
const carried = await runReviewSections({ ...input, prompts: [], carryClean: true }, async () => { carriedCalls++; return verdict(); });
assert.equal(carriedCalls, 0);
assert.equal(JSON.parse(carried.verdict).decision, 'clean');
assert.equal(usableBaseline(baseline, reviewer), baseline);
assert.equal(usableBaseline(baseline, { ...reviewer, model: 'other' }), undefined);
assert.equal(usableBaseline({ ...baseline, version: 0 }, reviewer), undefined);
assert.deepEqual(nextReviewBaseline({ headSha, baseSha: baseline.baseSha, provider: 'fixture', model: 'exact',
  verdict: JSON.stringify({ findings: ['open'] }) }, baseline.mergeBaseSha).findings, ['open']);
assert.equal(nextReviewBaseline({ verdict: '{}' }, undefined), undefined);

// Advisories are reported but never affect the verdict or its strict aggregate.
const advised = await runReviewSections({ ...input, prompts: ['one', 'two'] }, async () => ({
  verdict: JSON.stringify({ schemaVersion: 1, attemptId, headSha, decision: 'clean', findings: [], advisories: ['rename x'] }),
  usage: { input: 10, output: 2, cacheRead: 1, cacheWrite: 0, totalTokens: 13, cost: { total: 0.5 } },
}));
assert.deepEqual(Object.keys(JSON.parse(advised.verdict)).sort(), ['attemptId', 'decision', 'findings', 'headSha', 'schemaVersion']);
assert.equal(JSON.parse(advised.verdict).decision, 'clean');
assert.deepEqual(advised.advisories, ['rename x']);
await assert.rejects(runReviewSections({ ...input, prompts: ['one'] }, async () => ({
  verdict: JSON.stringify({ schemaVersion: 1, attemptId, headSha, decision: 'clean', findings: [], advisories: [3] }) })),
  /Invalid section verdict \(advisories\[0\] must be a non-empty string\)/);
const blank = await runReviewSections({ ...input, prompts: ['one'] }, async () => ({
  verdict: JSON.stringify({ schemaVersion: 1, attemptId, headSha, decision: 'clean', findings: [], advisories: [' ', 'keep'] }) }));
assert.deepEqual(blank.advisories, ['keep']);

// Rejected verdicts name the broken rule and rerun with that feedback; repairs never approve.
const seen = [];
const repaired = await runReviewSections({ ...input, prompts: ['one'] }, async prompt => {
  seen.push(prompt);
  return seen.length === 1 ? { verdict: JSON.stringify({ schemaVersion: 1, attemptId, headSha, decision: 'changes_requested', findings: [], advisories: ['nit'] }) } : verdict();
});
assert.equal(seen.length, 2);
assert.equal(seen[0], 'one');
assert.match(seen[1], /^one\n\nThe host rejected your previous answer for this section: decision is changes_requested but findings is empty/);
assert.equal(JSON.parse(repaired.verdict).decision, 'clean');
let stubborn = 0;
await assert.rejects(runReviewSections({ ...input, prompts: ['one'] }, async () => {
  stubborn++; return { verdict: JSON.stringify({ schemaVersion: 1, attemptId, headSha, decision: 'clean', findings: [], summary: 'ok' }) };
}), error => error.category === 'invalid_verdict' && /Invalid section verdict \(unexpected keys: "summary"\)/.test(error.message));
assert.equal(stubborn, 3);
let fenced = 0;
await assert.rejects(runReviewSections({ ...input, prompts: ['one'] }, async () => { fenced++; return { verdict: '```json\n{}\n```' }; }),
  /Malformed section verdict \(the final answer is not a single JSON object\)/);
assert.equal(fenced, 3);
const contradiction = await runReviewSections({ ...input, prompts: ['one'] }, async () => verdict('clean', ['file:2 defect']));
assert.equal(JSON.parse(contradiction.verdict).decision, 'changes_requested');
const structured = await runReviewSections({ ...input, prompts: ['one'] }, async () => verdict('changes_requested', [{ file: 'a.ts', line: 3, issue: 'null deref' }]));
assert.deepEqual(JSON.parse(structured.verdict).findings, ['{"file":"a.ts","line":3,"issue":"null deref"}']);
assert.equal(sectionVerdictProblem({ schemaVersion: 1, attemptId, headSha, decision: 'changes_requested', findings: [''] }, attemptId, headSha),
  'findings[0] must be a non-empty string');
assert.deepEqual(addUsage(addUsage(undefined, { input: 1, totalTokens: 1, cost: { total: 0.25 } }), { output: 2, totalTokens: 2, cost: 0.25 }),
  { input: 1, output: 2, cacheRead: 0, cacheWrite: 0, totalTokens: 3, cost: 0.5 });
let reported;
await runReviewSections({ ...input, prompts: ['one', 'two'] }, async () => ({ ...verdict(), usage: { totalTokens: 5 } }), undefined,
  update => { if (update.usage) reported = update.usage; });
assert.equal(reported.totalTokens, 10);
const resultText = reviewResultText({ verdict: '{}', advisories: ['rename x'], progress: { scope: 'fixes', usage: { totalTokens: 7 } } });
assert.match(resultText, /scope: fixes/);
assert.match(resultText, /tokens this round: 7/);
assert.match(resultText, /never block/);
console.log('Fix-scoped planning, prior-blocker recheck, clean carry-forward, advisories and token accounting passed.');
