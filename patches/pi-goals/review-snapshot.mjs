import { mkdtemp, readFile, stat, rm } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const sha = /^[a-f0-9]{40}$/;
const digest = value => createHash('sha256').update(value).digest('hex');
export const MAX_DIFF_BYTES = 64 * 1024 * 1024;

// Immutable inputs and local object state identify deterministic setup failures.
// This opaque key never exposes refs, remote credentials or source contents.
export async function reviewInputKey(headSha, baseSha, run) {
  return digest(JSON.stringify([2, MAX_DIFF_BYTES, headSha, baseSha,
    await run('git', ['rev-parse', '--is-shallow-repository']),
    await run('git', ['count-objects', '-v'])]));
}

export function preparationFailure(message, category, repairKey) {
  return Object.assign(new Error(message), { category, retryable: false, repairKey, repairReason: message,
    recovery: ({ input_limit: 'reduce_pr_scope', missing_history: 'repair_history', submodules: 'materialize_submodules',
      empty_diff: 'verify_pr_scope' })[category] ?? 'repair_setup' });
}

// A private checkout includes export-ignore files, excludes caller artifacts,
// and never changes the caller's index, refs, shallow boundary or configuration.
export async function reviewSnapshot(repoRoot, headSha, run, options = {}) {
  const { baseSha, repositoryUrl, previousFailure } = options;
  if (!sha.test(headSha) || (baseSha !== undefined && !sha.test(baseSha)))
    throw preparationFailure('Invalid pinned review commits.', 'invalid_inputs');
  const repairKey = baseSha ? await reviewInputKey(headSha, baseSha, run) : undefined;
  if (repairKey && previousFailure?.repairKey === repairKey && previousFailure.retryable === false) {
    const reason = previousFailure.repairReason || 'Repair the recorded prerequisite.';
    const error = preparationFailure(`Unchanged review preparation inputs after a deterministic failure: ${reason} Continue independent CI repairs and validation.`, previousFailure.category, repairKey);
    error.repairReason = reason;
    throw error;
  }
  const directory = await mkdtemp(join(tmpdir(), 'pi-review-source-'));
  const cwd = join(directory, 'source');
  const cleanup = () => rm(directory, { recursive: true, force: true });
  const git = args => run('git', ['-C', cwd, '-c', 'core.hooksPath=/dev/null', ...args]);
  try {
    await run('git', ['clone', '--template=', '--no-hardlinks', '--no-checkout', '--local', '--', repoRoot, cwd]);
    let diff, mergeBaseSha, diffHash;
    if (baseSha) {
      const shallow = (await git(['rev-parse', '--is-shallow-repository'])).trim() === 'true';
      let missing = false;
      try { await git(['cat-file', '-e', `${baseSha}^{commit}`]); }
      catch { missing = true; }
      if (shallow || missing) {
        // Fetch only into our clone. Unshallow before choosing a merge base:
        // an apparently valid shallow merge base can omit older PR changes.
        const url = new URL(repositoryUrl);
        if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash ||
            !/^\/[^/]+\/[^/]+\/pull\/[0-9]+$/.test(url.pathname))
          throw preparationFailure('PR repository URL is invalid; cannot acquire pinned history.', 'invalid_inputs', repairKey);
        url.pathname = url.pathname.replace(/\/pull\/[0-9]+$/, '.git');
        await git(['-c', 'credential.helper=!gh auth git-credential', 'fetch', '--no-tags',
          ...(shallow ? ['--unshallow'] : []), '--', url.href, headSha, baseSha]);
      }
      try {
        mergeBaseSha = (await git(['merge-base', '--all', baseSha, headSha])).trim();
        if (!sha.test(mergeBaseSha)) throw Error('Missing or ambiguous merge base.');
      } catch {
        throw preparationFailure('Pinned PR commits require one complete merge base; repair missing or unrelated history.', 'missing_history', repairKey);
      }
      const path = join(directory, 'review.diff');
      // Avoid Pi exec's output cap: Git writes the complete diff to a private
      // file. Reject oversize inputs explicitly, never review a truncated prefix.
      await git(['-c', 'core.quotePath=true', 'diff', '--no-ext-diff', '--no-textconv',
        '--no-renames', '--binary', '--full-index', '--no-color', '--no-relative', '--ignore-submodules=none',
        '--src-prefix=a/', '--dst-prefix=b/', '--unified=3', `--output=${path}`, mergeBaseSha, headSha, '--']);
      if ((await stat(path)).size > MAX_DIFF_BYTES)
        throw preparationFailure('Complete PR diff exceeds the 64 MiB review input limit; reduce the PR scope.', 'input_limit', repairKey);
      try { diff = new TextDecoder('utf-8', { fatal: true }).decode(await readFile(path)); }
      catch { throw preparationFailure('PR diff is not valid UTF-8; review input cannot be decoded without loss.', 'invalid_diff_encoding', repairKey); }
      if (!diff.trim()) throw preparationFailure('PR diff is empty; cannot establish review coverage.', 'empty_diff', repairKey);
      diffHash = digest(diff);
    }
    await git(['checkout', '--detach', headSha, '--']);
    const submodules = await git(['ls-files', '--stage']);
    if (/^160000 /m.test(submodules)) throw preparationFailure('Review snapshot requires materialized submodules; review preparation is incomplete.', 'submodules', repairKey);
    await rm(join(cwd, '.git'), { recursive: true, force: true });
    return { cwd, cleanup, diff, mergeBaseSha, diffHash };
  } catch (error) {
    await cleanup();
    throw error;
  }
}
