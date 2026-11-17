import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, readFileSync, existsSync, rmSync, mkdirSync, truncateSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
const { reviewSnapshot, reviewInputKey, MAX_DIFF_BYTES } = await import(process.argv[2] ? pathToFileURL(join(process.argv[2], 'src/review-snapshot.mjs')) : '../patches/pi-goals/review-snapshot.mjs');
const temporary = mkdtempSync(join(tmpdir(), 'snapshot-test-'));
const run = async (command, args) => execFileSync(command, args, { cwd: temporary, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
try {
  await run('git', ['init', '-q']);
  writeFileSync(join(temporary, 'source.txt'), 'committed source');
  writeFileSync(join(temporary, '.gitattributes'), 'source.txt export-ignore\n');
  await run('git', ['add', '.']);
  await run('git', ['-c', 'user.name=Fixture', '-c', 'user.email=55928941+matifuentes2@users.noreply.github.com',
    '-c', 'commit.gpgsign=false', 'commit', '-qm', 'fixture']);
  const head = (await run('git', ['rev-parse', 'HEAD'])).trim();
  writeFileSync(join(temporary, 'source.txt'), 'uncommitted changes');
  writeFileSync(join(temporary, 'browser.log'), 'unrelated artifact');
  const before = await run('git', ['status', '--porcelain']);
  const snapshot = await reviewSnapshot(temporary, head, run);
  assert.equal(readFileSync(join(snapshot.cwd, 'source.txt'), 'utf8'), 'committed source');
  assert(!existsSync(join(snapshot.cwd, 'browser.log')));
  assert(!existsSync(join(snapshot.cwd, '.git')));
  assert.equal(await run('git', ['status', '--porcelain']), before);
  assert.equal(readFileSync(join(temporary, 'browser.log'), 'utf8'), 'unrelated artifact');
  await snapshot.cleanup();
  assert(!existsSync(snapshot.cwd));
  let created;
  await assert.rejects(reviewSnapshot(temporary, head, async (cmd, args) => {
    if (args[0] === 'clone') created = args.at(-1);
    throw Error('setup fixture');
  }), /setup fixture/);
  assert(!existsSync(created));

  // A complete three-dot diff covers 317 files, base-only changes are excluded.
  await run('git', ['checkout', '-qb', 'base']);
  const common = head;
  writeFileSync(join(temporary, 'base-only.txt'), 'base only');
  await run('git', ['add', 'base-only.txt']);
  const commit = async () => run('git', ['-c', 'user.name=Fixture', '-c', 'user.email=55928941+matifuentes2@users.noreply.github.com', '-c', 'commit.gpgsign=false', 'commit', '-qm', 'fixture']);
  await commit();
  const baseSha = (await run('git', ['rev-parse', 'HEAD'])).trim();
  await run('git', ['checkout', '-qb', 'pr', common]);
  mkdirSync(join(temporary, 'files'));
  for (let i = 0; i < 317; i++) writeFileSync(join(temporary, 'files', `file-${i}.txt`), `change ${i}\n`);
  await run('git', ['add', 'files']); await commit();
  const headSha = (await run('git', ['rev-parse', 'HEAD'])).trim();
  const options = { baseSha, repositoryUrl: 'https://github.com/fixture/repository/pull/7' };
  const large = await reviewSnapshot(temporary, headSha, run, options);
  assert.equal(large.diff.match(/^diff --git /gm).length, 317);
  assert(!large.diff.includes('base-only.txt'));
  assert.equal(large.mergeBaseSha, common);
  const fullDiff = large.diff;
  assert.match(large.diffHash, /^[a-f0-9]{64}$/);
  await large.cleanup();

  // Shallow history is repaired inside the snapshot with exact pinned fetches.
  // Map only the fixture HTTPS remote to the local repo; no network required.
  const shallow = join(temporary, 'shallow');
  await run('git', ['clone', '-q', '--depth=1', '--branch=pr', `file://${temporary}`, shallow]);
  const shallowBefore = execFileSync('git', ['status', '--porcelain'], { cwd: shallow, encoding: 'utf8' });
  let fetched = 0;
  const shallowRun = async (cmd, args) => {
    if (args.includes('fetch')) {
      fetched++;
      assert(args.includes('--unshallow'));
      assert.deepEqual(args.slice(-2), [headSha, baseSha]);
      args = args.map(arg => arg === 'https://github.com/fixture/repository.git' ? `file://${temporary}` : arg);
    }
    return execFileSync(cmd, args, { cwd: shallow, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  };
  const repaired = await reviewSnapshot(shallow, headSha, shallowRun, options);
  assert.equal(repaired.diff, fullDiff); assert.equal(fetched, 1);
  assert.equal(execFileSync('git', ['rev-parse', '--is-shallow-repository'], { cwd: shallow, encoding: 'utf8' }).trim(), 'true');
  assert.equal(execFileSync('git', ['status', '--porcelain'], { cwd: shallow, encoding: 'utf8' }), shallowBefore);
  await repaired.cleanup();

  // A full single-branch clone missing the base object fetches only in its copy.
  const single = join(temporary, 'single');
  await run('git', ['clone', '-q', '--single-branch', '--branch=pr', `file://${temporary}`, single]);
  let missingFetch = 0;
  const singleRun = async (cmd, args) => {
    if (args.includes('fetch')) {
      missingFetch++; assert(!args.includes('--unshallow'));
      args = args.map(arg => arg === 'https://github.com/fixture/repository.git' ? `file://${temporary}` : arg);
    }
    return execFileSync(cmd, args, { cwd: single, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  };
  const acquired = await reviewSnapshot(single, headSha, singleRun, options);
  assert.equal(acquired.diff, fullDiff); assert.equal(missingFetch, 1);
  await acquired.cleanup();

  // Oversize diff output cannot authorize partial review. A repeated call is
  // rejected before cloning until the pinned input or object state changes.
  let deterministic;
  const oversized = async (cmd, args) => {
    const output = args.find(arg => arg.startsWith('--output='));
    if (output) { writeFileSync(output.slice(9), ''); truncateSync(output.slice(9), MAX_DIFF_BYTES + 1); return ''; }
    return run(cmd, args);
  };
  await assert.rejects(reviewSnapshot(temporary, headSha, oversized, options), error => {
    deterministic = error; return error.category === 'input_limit' && error.retryable === false;
  });
  await assert.rejects(reviewSnapshot(temporary, headSha, async (cmd, args) => {
    assert(!args.includes('clone')); return run(cmd, args);
  }, { ...options, previousFailure: deterministic }), /Unchanged review preparation/);
  assert.equal(deterministic.recovery, 'reduce_pr_scope');
  await assert.rejects(reviewSnapshot(temporary, headSha, async (cmd, args) => {
    const output = args.find(arg => arg.startsWith('--output='));
    if (output) { writeFileSync(output.slice(9), Buffer.from([0xff])); return ''; }
    return run(cmd, args);
  }, options), error => error.category === 'invalid_diff_encoding');
  assert.equal(deterministic.repairKey, await reviewInputKey(headSha, baseSha, run));
  assert.notEqual(deterministic.repairKey, await reviewInputKey(headSha, common, run));
  await assert.rejects(reviewSnapshot(temporary, headSha, async (cmd, args) => {
    if (args.includes('merge-base')) throw Error('missing history');
    return run(cmd, args);
  }, options), error => error.category === 'missing_history');
  await assert.rejects(reviewSnapshot(shallow, headSha, async (cmd, args) => {
    if (args.includes('fetch')) throw Error('fixture fetch unavailable');
    return shallowRun(cmd, args);
  }, options), /fetch unavailable/);
  await assert.rejects(reviewSnapshot(shallow, headSha, shallowRun, {
    ...options, repositoryUrl: 'https://user:password@example.invalid/fixture/repository/pull/7',
  }), error => error.category === 'invalid_inputs');
  await assert.rejects(reviewSnapshot(temporary, headSha, async (cmd, args) => {
    if (args.includes('merge-base')) return `${common}\n${baseSha}\n`;
    return run(cmd, args);
  }, options), error => error.category === 'missing_history');
  // Deleted paths, rename sides, binary contents and quoted filenames remain
  // visible in the diff even when the provider cannot render GitHub patches.
  await run('git', ['mv', 'source.txt', 'renamed source.txt']);
  await run('git', ['rm', '.gitattributes']);
  writeFileSync(join(temporary, 'binary.dat'), Buffer.from([0, 1, 2, 255]));
  writeFileSync(join(temporary, 'unusual\tname.txt'), 'quoted path');
  await run('git', ['add', 'renamed source.txt', 'binary.dat', 'unusual\tname.txt']);
  await commit();
  const changedHead = (await run('git', ['rev-parse', 'HEAD'])).trim();
  const coverage = await reviewSnapshot(temporary, changedHead, run, options);
  assert(coverage.diff.includes('deleted file mode'));
  assert(coverage.diff.includes('GIT binary patch'));
  assert(coverage.diff.includes('renamed source.txt'));
  assert(coverage.diff.includes('source.txt'));
  assert(coverage.diff.includes('unusual\\tname.txt'));
  await coverage.cleanup();
  console.log('317-file coverage, merge-base semantics, shallow/missing-object repair, output limits and unchanged-failure rejection passed.');
  console.log('Snapshot isolation, committed source, export-ignore coverage, artifact preservation and cleanup passed.');
} finally { rmSync(temporary, { recursive: true, force: true }); }
