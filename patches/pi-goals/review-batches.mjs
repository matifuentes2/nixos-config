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
    (p.running?.length > 1 ? ` · steps ${p.running.join(',')}` : p.current ? ` · step ${p.current}` : '') +
    (p.usage ? ` · tokens ${p.usage.totalTokens}` : '') +
    ` · attempt ${execution.attemptId} · ${execution.provider ?? '?'}/${execution.model ?? '?'}` +
    ` · head ${execution.headSha || 'pending'} · started ${p.startedAt}` +
    (p.sectionStartedAt ? ` · step started ${p.sectionStartedAt}` : '') +
    (p.lastCompletedAt ? ` · last completed ${p.lastCompletedAt}` : '') +
    (p.subprocess ? ` · process${p.subprocess.step ? ` (step ${p.subprocess.step})` : ''} ${p.subprocess.exitCode === undefined ? (execution.status === 'running' ? 'running' : 'unobserved') : 'exited'} ${Math.floor(p.subprocess.elapsedMs / 1000)}s` +
      ` · events ${p.subprocess.events} · last ${p.subprocess.lastEvent ?? 'none'}` +
      (p.subprocess.lastEventAt ? ` at ${p.subprocess.lastEventAt}` : '') +
      ` · stdout ${p.subprocess.stdoutBytes}B · stderr ${p.subprocess.stderrBytes}B` : '') +
    (execution.reason ? ` · ${execution.reason}` : '');
}

const VERDICT_KEYS = ['attemptId', 'decision', 'findings', 'headSha', 'schemaVersion'];
const noteText = item => typeof item === 'string' ? item.trim()
  : item && typeof item === 'object' && !Array.isArray(item) ? JSON.stringify(item) : item;

// Repairs only unambiguous shapes, and never toward approval: structured notes
// become text, blank advisories are dropped, and "clean" with findings blocks.
export function normalizeSectionVerdict(v) {
  if (!v || typeof v !== 'object' || Array.isArray(v)) return v;
  const out = { ...v };
  if (Array.isArray(v.findings)) out.findings = v.findings.map(noteText);
  if (Array.isArray(v.advisories)) out.advisories = v.advisories.map(noteText).filter(a => a !== '');
  if (out.decision === 'clean' && Array.isArray(out.findings) && out.findings.length) out.decision = 'changes_requested';
  return out;
}

// Names the first broken rule without echoing reviewer content.
export function sectionVerdictProblem(v, attemptId, headSha) {
  if (!v || typeof v !== 'object' || Array.isArray(v)) return 'the verdict is not a JSON object';
  const keys = Object.keys(v);
  const missing = VERDICT_KEYS.filter(key => !keys.includes(key));
  if (missing.length) return `missing keys: ${missing.join(', ')}`;
  const extra = keys.filter(key => key !== 'advisories' && !VERDICT_KEYS.includes(key));
  if (extra.length) return `unexpected keys: ${extra.slice(0, 5).map(key => JSON.stringify(key.slice(0, 40))).join(', ')}`;
  if (v.schemaVersion !== 1) return 'schemaVersion must be 1';
  if (typeof attemptId !== 'string' || !attemptId.trim() || v.attemptId !== attemptId) return 'attemptId does not match this review attempt';
  if (v.headSha !== headSha) return 'headSha does not match the reviewed head';
  if (!['clean', 'changes_requested'].includes(v.decision)) return 'decision must be "clean" or "changes_requested"';
  for (const field of ['findings', 'advisories']) {
    if (field === 'advisories' && v.advisories === undefined) continue;
    if (!Array.isArray(v[field])) return `${field} must be an array`;
    const bad = v[field].findIndex(item => typeof item !== 'string' || !item.trim());
    if (bad >= 0) return `${field}[${bad}] must be a non-empty string`;
  }
  // Fresh verdicts are normalized first; stored evidence is never repaired.
  if (v.decision === 'clean' && v.findings.length) return 'decision is clean but findings is nonempty';
  if (v.decision === 'changes_requested' && !v.findings.length)
    return 'decision is changes_requested but findings is empty; non-blocking notes belong in advisories with decision clean';
  return null;
}

// Sections run in separate fresh reviewers, so up to this many run at once.
export const SECTION_CONCURRENCY = 4;

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
  // `verdicts` is the validated prefix. Sections that finish ahead of an earlier
  // one wait in `outOfOrder`, keyed by index; older hosts ignore it and rerun them.
  const later = checkpoint.outOfOrder ?? {};
  if (!Array.isArray(checkpoint.verdicts) || checkpoint.verdicts.length > prompts.length ||
      !later || typeof later !== 'object' || Array.isArray(later) ||
      Object.keys(later).some(k => !/^\d+$/.test(k) || Number(k) <= checkpoint.verdicts.length || Number(k) >= prompts.length))
    throw new Error('Invalid host review checkpoint.');
  const done = new Map([...checkpoint.verdicts.entries(), ...Object.entries(later).map(([k, v]) => [Number(k), v])]);
  if ([...done.values()].some(v => sectionVerdictProblem(v, v?.attemptId, input.headSha)))
    throw new Error('Invalid host section evidence.');
  const save = () => {
    const verdicts = [];
    while (done.has(verdicts.length)) verdicts.push(done.get(verdicts.length));
    const outOfOrder = Object.fromEntries([...done].filter(([i]) => i > verdicts.length)
      .sort(([a], [b]) => a - b).map(([i, v]) => [String(i), v]));
    checkpoint.verdicts = verdicts;
    if (Object.keys(outOfOrder).length) checkpoint.outOfOrder = outOfOrder; else delete checkpoint.outOfOrder;
    input.onCheckpoint?.(structuredClone(checkpoint));
  };
  let spent;
  const recordUsage = usage => {
    if (!usage) return;
    spent = addUsage(spent, usage);
    onProgress({ usage: spent });
  };
  save();
  if (done.size) onProgress({ phase: 'resuming', completed: done.size, total: prompts.length });
  const running = new Set();
  const runningSteps = () => [...running].sort((a, b) => a - b);
  const reviewSection = async index => {
    const prompt = prompts[index], step = index + 1;
    // Subprocess pulses from concurrent sections name their step.
    const sectionProgress = update => onProgress(update?.subprocess ? { ...update, subprocess: { ...update.subprocess, step } } : update);
    running.add(step);
    onProgress({ phase: index === input.integrationIndex ? 'integration' : 'section',
      current: step, running: runningSteps(), total: prompts.length, completed: done.size,
      subprocess: null, retry: 0, retryCategory: null, sectionStartedAt: new Date().toISOString() });
    const retryHistory = [];
    let v, problem, malformed;
    try {
      // A rejected verdict reruns the section in a fresh reviewer, told only which
      // rule its answer broke. The evidence standard is unchanged.
      for (let verdictRetry = 0; ; verdictRetry++) {
        const attemptPrompt = problem ? `${prompt}\n\nThe host rejected your previous answer for this section: ${problem}. ` +
          'Review the section again and return only the JSON object with exactly the keys described above.' : prompt;
        let result;
        for (let retry = 0; ; retry++) {
          try { result = await run(attemptPrompt, sectionProgress); recordUsage(result.usage); break; }
          catch (error) {
            recordUsage(error.reviewDiagnostics?.usage);
            if (signal?.aborted || !error.retryable || retry >= 2) throw error;
            retryHistory.push({ retry: retry + 1, category: error.category, diagnostics: error.reviewDiagnostics });
            onProgress({ current: step, retry: retry + 1, retryCategory: error.category, retryHistory: structuredClone(retryHistory) });
            await delay(1000 * 2 ** retry, undefined, { signal });
          }
        }
        if (signal?.aborted) throw new Error('Reviewer interrupted.');
        malformed = false;
        try { v = normalizeSectionVerdict(JSON.parse(result.verdict)); problem = sectionVerdictProblem(v, input.attemptId, input.headSha); }
        catch { malformed = true; problem = 'the final answer is not a single JSON object'; }
        if (!problem) break;
        if (verdictRetry >= 2) throw Object.assign(new Error(`${malformed ? 'Malformed' : 'Invalid'} section verdict ` +
          `(${problem}); review remains incomplete.`), { category: 'invalid_verdict', retryable: false });
        retryHistory.push({ retry: retryHistory.length + 1, category: 'invalid_verdict', problem });
        onProgress({ current: step, retry: retryHistory.length, retryCategory: 'invalid_verdict', retryHistory: structuredClone(retryHistory) });
      }
    } finally { running.delete(step); }
    done.set(index, v);
    save();
    onProgress({ completed: done.size, running: runningSteps(), lastCompletedAt: new Date().toISOString() });
  };
  // A failure stops new launches; sections already running finish and keep their
  // validated verdicts. The lowest failed step is reported, so the result does
  // not depend on which reviewer happened to fail first.
  const failures = new Map();
  const raise = () => {
    if (failures.size) {
      const [index, error] = [...failures].sort(([a], [b]) => a - b)[0];
      if (!signal?.aborted) onProgress({ current: index + 1, running: runningSteps() });
      throw error;
    }
    if (signal?.aborted) throw new Error('Reviewer interrupted.');
  };
  const integration = Number.isInteger(input.integrationIndex) && input.integrationIndex < prompts.length ? input.integrationIndex : null;
  const queue = prompts.map((_, i) => i).filter(i => !done.has(i) && i !== integration);
  const limit = Math.max(1, Math.floor(input.concurrency ?? SECTION_CONCURRENCY));
  const worker = async () => {
    while (queue.length && !failures.size && !signal?.aborted) {
      const index = queue.shift();
      try { await reviewSection(index); } catch (error) { failures.set(index, error); }
    }
  };
  await Promise.all(Array.from({ length: Math.min(limit, queue.length) }, worker));
  raise();
  // Integration reviews cross-file contracts after every section is validated.
  if (integration !== null && !done.has(integration)) {
    try { await reviewSection(integration); } catch (error) { failures.set(integration, error); }
    raise();
  }
  const verdicts = prompts.map((_, i) => done.get(i));
  const findings = verdicts.flatMap(v => v.findings);
  return { verdict: JSON.stringify({ schemaVersion: 1, attemptId: input.attemptId,
    headSha: input.headSha, decision: findings.length ? 'changes_requested' : 'clean', findings }),
    sections: verdicts, advisories: [...new Set(verdicts.flatMap(v => v.advisories ?? []))] };
}
