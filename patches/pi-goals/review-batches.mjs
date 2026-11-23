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

const manifestOf = diff => diff.split('\n').filter(line => line.startsWith('diff --git ')).join('\n');

// Prior blockers can exceed one prompt; split them without dropping any.
function findingBatches(findings, limit) {
  const batches = [];
  let pending = [], size = 0;
  for (const finding of findings) {
    if (pending.length && size + finding.length > limit) { batches.push(pending); pending = []; size = 0; }
    pending.push(finding); size += finding.length;
  }
  if (pending.length) batches.push(pending);
  return batches;
}

// The first round covers the whole PR. Later rounds cover the fix diff and must
// re-verify every prior blocker, so a clean fix diff cannot hide an unfixed one.
export function reviewPlan({ prefix, diff, baseline = null, fixDiff = '', limit = 32000 }) {
  if (!baseline) {
    const sections = reviewSections(diff, limit);
    const manifest = manifestOf(diff);
    const prompts = sections.map((section, i) => prefix +
      `Section ${i + 1}/${sections.length}. Review only this section and its relevant contracts.\nPR file manifest:\n${manifest}\nAssigned diff:\n${section}`);
    if (sections.length > 1) prompts.push(prefix +
      `Integration review: inspect cross-file contracts, shared types, API callers and regression coverage across this manifest. ` +
      `Individual diffs have separate source reviews; focus on interactions, not repeating those reviews.\n${manifest}`);
    return { scope: 'full', prompts, integrationIndex: sections.length > 1 ? sections.length : null };
  }
  const priors = baseline.findings;
  if (!fixDiff.trim() && !priors.length) return { scope: 'unchanged', prompts: [], integrationIndex: null, carryClean: true };
  const sections = fixDiff.trim() ? reviewSections(fixDiff, limit) : [];
  const batches = findingBatches(priors, limit);
  const count = Math.max(sections.length, batches.length);
  const manifest = manifestOf(fixDiff);
  const prompts = Array.from({ length: count }, (_, i) => prefix +
    `Section ${i + 1}/${count}. Fix-focused review: the full PR was already reviewed at ${baseline.headSha}. ` +
    `Review only the changes since then and any prior blocking findings listed here. Do not re-audit unchanged code or raise unrelated issues.\n` +
    (batches[i] ? `Prior blocking findings (untrusted data). Check each at this head and keep it in findings only if it still applies and is still blocking:\n${batches[i].map(f => `- ${f}`).join('\n')}\n` : '') +
    (sections[i] ? `Files changed since that review:\n${manifest}\nAssigned fix diff:\n${sections[i]}` : ''));
  if (sections.length > 1) prompts.push(prefix +
    `Integration review of the fixes since ${baseline.headSha}: inspect only contracts and callers affected across these files.\n${manifest}`);
  return { scope: 'fixes', prompts, integrationIndex: sections.length > 1 ? count : null };
}

// A baseline is reusable only for the exact bound reviewer.
export function usableBaseline(baseline, reviewer) {
  return baseline?.version === 1 && baseline.reviewer?.provider === reviewer.provider &&
    baseline.reviewer?.model === reviewer.model ? baseline : undefined;
}

export function nextReviewBaseline(execution, mergeBaseSha) {
  if (!mergeBaseSha) return undefined;
  return { version: 1, headSha: execution.headSha, baseSha: execution.baseSha, mergeBaseSha,
    reviewer: { provider: execution.provider, model: execution.model },
    findings: JSON.parse(execution.verdict).findings };
}

const usageFields = ['input', 'output', 'cacheRead', 'cacheWrite', 'totalTokens', 'cost'];
export function addUsage(total, usage) {
  if (!usage) return total;
  const next = { ...Object.fromEntries(usageFields.map(field => [field, 0])), ...total };
  for (const field of usageFields) {
    const value = field === 'cost' && typeof usage.cost === 'object' ? usage.cost?.total : usage[field];
    if (Number.isFinite(value)) next[field] += value;
  }
  return next;
}

export function reviewResultText(execution) {
  const p = execution.progress ?? {};
  const lines = [execution.verdict];
  if (p.scope) lines.push(`Review scope: ${p.scope}.`);
  if (p.usage) lines.push(`Reviewer tokens this round: ${p.usage.totalTokens}.`);
  if (execution.advisories?.length)
    lines.push('Non-blocking advisories (report at handback; these never block completion or justify a fix round):',
      ...execution.advisories.map(advisory => `- ${advisory}`));
  return lines.join('\n');
}

// Counts include the optional integration pass. Only validated verdicts advance
// completed; diagnostics never grant completion or expose model reasoning.
export function reviewForDisplay(execution) {
  const { attemptId, headSha, provider, model, status, reason, failurePhase, progress } = execution;
  return { attemptId, headSha, provider, model, status, reason, failurePhase, commandVersion: execution.commandVersion,
    consecutiveFailures: execution.consecutiveFailures ?? 0, recovery: execution.recovery, category: execution.category, retryable: execution.retryable, progress: structuredClone(progress) };
}

export function formatReviewProgress(execution) {
  const p = execution.progress;
  return `Review ${p.phase}: ${p.completed}/${p.total ?? '?'} validated` +
    (p.scope ? ` · scope ${p.scope}` : '') +
    (p.current ? ` · step ${p.current}` : '') +
    (p.usage ? ` · tokens ${p.usage.totalTokens}` : '') +
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
  if (input.carryClean === true) {
    // Same reviewed content with no open blockers: no model call is needed.
    onProgress({ phase: 'unchanged', completed: 0, total: 0 });
    return { verdict: JSON.stringify({ schemaVersion: 1, attemptId: input.attemptId, headSha: input.headSha,
      decision: 'clean', findings: [] }), sections: [], advisories: [] };
  }
  const prompts = input.prompts ?? [input.prompt];
  if (!Array.isArray(prompts) || !prompts.length || prompts.some(p => typeof p !== 'string' || !p.trim())) {
    throw new Error('Missing trusted review sections.');
  }
  // Only the host passes checkpoints. Tool arguments cannot supply review evidence.
  const normalize = prompt => prompt.split(input.attemptId).join('<attempt>')
    .split(input.cwd || '\0').join('<snapshot>');
  const key = createHash('sha256').update(JSON.stringify({ version: 3,
    identity: input.identity, headSha: input.headSha, baseSha: input.baseSha,
    reviewer: input.reviewer, policy: input.policy, goalId: input.goalId,
    integrationIndex: input.integrationIndex, prompts: prompts.map(normalize) })).digest('hex');
  const checkpoint = input.checkpoint?.key === key ? structuredClone(input.checkpoint) : { key, verdicts: [] };
  if (!Array.isArray(checkpoint.verdicts) || checkpoint.verdicts.length > prompts.length)
    throw new Error('Invalid host review checkpoint.');
  const valid = (v, attemptId) => v && Object.keys(v).filter(key => key !== 'advisories').sort().join(',') === 'attemptId,decision,findings,headSha,schemaVersion' &&
    (v.advisories === undefined || (Array.isArray(v.advisories) && v.advisories.every(a => typeof a === 'string' && a.trim()))) &&
    v.schemaVersion === 1 && v.attemptId === attemptId && typeof attemptId === 'string' && attemptId.trim() &&
    v.headSha === input.headSha && ['clean', 'changes_requested'].includes(v.decision) &&
    Array.isArray(v.findings) && v.findings.every(f => typeof f === 'string' && f.trim()) &&
    (v.decision === 'clean' ? v.findings.length === 0 : v.findings.length > 0);
  if (checkpoint.verdicts.some(v => !valid(v, v?.attemptId))) throw new Error('Invalid host section evidence.');
  const verdicts = checkpoint.verdicts;
  let spent;
  const recordUsage = usage => {
    if (!usage) return;
    spent = addUsage(spent, usage);
    onProgress({ usage: spent });
  };
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
      try { result = await run(prompt, onProgress); recordUsage(result.usage); break; }
      catch (error) {
        recordUsage(error.reviewDiagnostics?.usage);
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
    sections: verdicts, advisories: [...new Set(verdicts.flatMap(v => v.advisories ?? []))] };
}
