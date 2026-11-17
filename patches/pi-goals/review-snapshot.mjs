import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

// A private, disposable checkout includes every tracked file (even export-ignore
// paths), excludes caller artifacts, and never changes the caller's index/config.
export async function reviewSnapshot(repoRoot, headSha, run) {
  const directory = await mkdtemp(join(tmpdir(), 'pi-review-source-'));
  const cwd = join(directory, 'source');
  const cleanup = () => rm(directory, { recursive: true, force: true });
  try {
    await run('git', ['clone', '--template=', '--no-hardlinks', '--no-checkout', '--local', '--', repoRoot, cwd]);
    await run('git', ['-C', cwd, '-c', 'core.hooksPath=/dev/null', 'checkout', '--detach', headSha, '--']);
    const submodules = await run('git', ['-C', cwd, 'ls-files', '--stage']);
    if (/^160000 /m.test(submodules)) throw new Error('Review snapshot requires materialized submodules; review preparation is incomplete.');
    await rm(join(cwd, '.git'), { recursive: true, force: true });
    return { cwd, cleanup };
  } catch (error) {
    await cleanup();
    throw error;
  }
}
