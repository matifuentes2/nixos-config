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
for (const bad of [verdict('changes_requested'), { verdict: '{}' }, { verdict: verdict().verdict.replace(headSha, 'b'.repeat(40)) }, { verdict: verdict().verdict.replace(attemptId, 'stale') }]) {
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
assert(invalidProgress.every(update => !update.completed), 'Malformed verdict must not advance progress');
assert.equal(invalidProgress.filter(update => update.retryCategory === 'invalid_verdict').length, 2);
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
