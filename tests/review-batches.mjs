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
