// Host-owned partitioning. Every byte of the diff belongs to a review section.
export function reviewSections(diff, limit = 32000) {
  if (!diff.trim()) throw new Error('PR diff is empty; cannot establish review coverage.');
  const files = diff.split(/(?=^diff --git )/m).filter(Boolean);
  const sections = [];
  let pending = '';
  for (const file of files) {
    if (pending && pending.length + file.length > limit) {
      sections.push(pending);
      pending = '';
    }
    if (file.length > limit) {
      if (pending) { sections.push(pending); pending = ''; }
      // Large files are split without dropping text. Reviewers can read the full
      // source path and callers; the header identifies continuation sections.
      const header = file.slice(0, file.indexOf('\n') + 1);
      for (let offset = 0; offset < file.length; offset += limit) {
        sections.push((offset ? `${header}[continued diff]\n` : '') + file.slice(offset, offset + limit));
      }
    } else pending += file;
  }
  if (pending) sections.push(pending);
  return sections;
}

export async function runReviewSections(input, run, signal) {
  const prompts = input.prompts ?? [input.prompt];
  if (!Array.isArray(prompts) || !prompts.length || prompts.some(p => typeof p !== 'string' || !p.trim())) {
    throw new Error('Missing trusted review sections.');
  }
  const verdicts = [];
  for (const prompt of prompts) {
    if (signal?.aborted) throw new Error('Reviewer interrupted.');
    const result = await run(prompt);
    const v = JSON.parse(result.verdict);
    if (!v || Object.keys(v).sort().join(',') !== 'attemptId,decision,findings,headSha,schemaVersion' ||
        v.schemaVersion !== 1 || v.attemptId !== input.attemptId || v.headSha !== input.headSha ||
        !['clean', 'changes_requested'].includes(v.decision) || !Array.isArray(v.findings) ||
        !v.findings.every(f => typeof f === 'string' && f.trim()) ||
        (v.decision === 'clean' ? v.findings.length !== 0 : v.findings.length === 0)) {
      throw new Error('Invalid section verdict; review remains incomplete.');
    }
    verdicts.push(v);
  }
  const findings = verdicts.flatMap(v => v.findings);
  return { verdict: JSON.stringify({ schemaVersion: 1, attemptId: input.attemptId,
    headSha: input.headSha, decision: findings.length ? 'changes_requested' : 'clean', findings }),
    sections: verdicts };
}
