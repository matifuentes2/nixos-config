import { createHash } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';

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

// Counts include the optional integration pass. Only validated verdicts advance
// completed; diagnostics never grant completion or expose model reasoning.
export function reviewForDisplay(execution) {
  const { attemptId, headSha, provider, model, status, reason, failurePhase, progress } = execution;
  return { attemptId, headSha, provider, model, status, reason, failurePhase,
    consecutiveFailures: execution.consecutiveFailures ?? 0, recovery: execution.recovery, category: execution.category, retryable: execution.retryable, progress: structuredClone(progress) };
}

export function formatReviewProgress(execution) {
  const p = execution.progress;
  return `Review ${p.phase}: ${p.completed}/${p.total ?? '?'} validated` +
    (p.current ? ` · step ${p.current}` : '') +
    ` · attempt ${execution.attemptId} · ${execution.provider ?? '?'}/${execution.model ?? '?'}` +
    ` · head ${execution.headSha || 'pending'} · started ${p.startedAt}` +
    (p.sectionStartedAt ? ` · step started ${p.sectionStartedAt}` : '') +
    (p.lastCompletedAt ? ` · last completed ${p.lastCompletedAt}` : '') +
    (p.subprocess ? ` · process ${p.subprocess.exitCode === undefined ? (execution.status === 'running' ? 'running' : 'unobserved') : 'exited'} ${Math.floor(p.subprocess.elapsedMs / 1000)}s` +
      ` · events ${p.subprocess.events} · last ${p.subprocess.lastEvent ?? 'none'}` +
      (p.subprocess.lastEventAt ? ` at ${p.subprocess.lastEventAt}` : '') +
      ` · stdout ${p.subprocess.stdoutBytes}B · stderr ${p.subprocess.stderrBytes}B` : '') +
    (execution.reason ? ` · ${execution.reason}` : '');
}

export async function runReviewSections(input, run, signal, onProgress = () => {}) {
  const prompts = input.prompts ?? [input.prompt];
  if (!Array.isArray(prompts) || !prompts.length || prompts.some(p => typeof p !== 'string' || !p.trim())) {
    throw new Error('Missing trusted review sections.');
  }
  // Only the host passes checkpoints. Tool arguments cannot supply review evidence.
  const normalize = prompt => prompt.split(input.attemptId).join('<attempt>')
    .split(input.cwd || '\0').join('<snapshot>');
  const key = createHash('sha256').update(JSON.stringify({ version: 2,
    identity: input.identity, headSha: input.headSha, baseSha: input.baseSha,
    reviewer: input.reviewer, policy: input.policy, goalId: input.goalId,
    integrationIndex: input.integrationIndex, prompts: prompts.map(normalize) })).digest('hex');
  const checkpoint = input.checkpoint?.key === key ? structuredClone(input.checkpoint) : { key, verdicts: [] };
  if (!Array.isArray(checkpoint.verdicts) || checkpoint.verdicts.length > prompts.length)
    throw new Error('Invalid host review checkpoint.');
  const valid = (v, attemptId) => v && Object.keys(v).sort().join(',') === 'attemptId,decision,findings,headSha,schemaVersion' &&
    v.schemaVersion === 1 && v.attemptId === attemptId && typeof attemptId === 'string' && attemptId.trim() &&
    v.headSha === input.headSha && ['clean', 'changes_requested'].includes(v.decision) &&
    Array.isArray(v.findings) && v.findings.every(f => typeof f === 'string' && f.trim()) &&
    (v.decision === 'clean' ? v.findings.length === 0 : v.findings.length > 0);
  if (checkpoint.verdicts.some(v => !valid(v, v?.attemptId))) throw new Error('Invalid host section evidence.');
  const verdicts = checkpoint.verdicts;
  input.onCheckpoint?.(structuredClone(checkpoint));
  if (verdicts.length) onProgress({ phase: 'resuming', completed: verdicts.length, total: prompts.length });
  for (const [index, prompt] of prompts.entries()) {
    if (signal?.aborted) throw new Error('Reviewer interrupted.');
    if (index < verdicts.length) continue;
    onProgress({ phase: index === input.integrationIndex ? 'integration' : 'section',
      current: index + 1, total: prompts.length, completed: verdicts.length,
      subprocess: null, retry: 0, retryCategory: null, sectionStartedAt: new Date().toISOString() });
    let result;
    const retryHistory = [];
    for (let retry = 0; ; retry++) {
      try { result = await run(prompt, onProgress); break; }
      catch (error) {
        if (signal?.aborted || !error.retryable || retry >= 2) throw error;
        retryHistory.push({ retry: retry + 1, category: error.category, diagnostics: error.reviewDiagnostics });
        onProgress({ retry: retry + 1, retryCategory: error.category, retryHistory: structuredClone(retryHistory) });
        await delay(1000 * 2 ** retry, undefined, { signal });
      }
    }
    if (signal?.aborted) throw new Error('Reviewer interrupted.');
    let v;
    try { v = JSON.parse(result.verdict); } catch { throw new Error("Malformed section verdict; review remains incomplete."); }
    if (!valid(v, input.attemptId)) throw new Error('Invalid section verdict; review remains incomplete.');
    verdicts.push(v);
    input.onCheckpoint?.(structuredClone(checkpoint));
    onProgress({ completed: verdicts.length, lastCompletedAt: new Date().toISOString() });
  }
  const findings = verdicts.flatMap(v => v.findings);
  return { verdict: JSON.stringify({ schemaVersion: 1, attemptId: input.attemptId,
    headSha: input.headSha, decision: findings.length ? 'changes_requested' : 'clean', findings }),
    sections: verdicts };
}
