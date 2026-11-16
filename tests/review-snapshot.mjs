import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, readFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
const { reviewSnapshot } = await import(process.argv[2] ? pathToFileURL(join(process.argv[2], 'src/review-snapshot.mjs')) : '../patches/pi-goals/review-snapshot.mjs');
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
  console.log('Snapshot isolation, committed source, export-ignore coverage, artifact preservation and cleanup passed.');
} finally { rmSync(temporary, { recursive: true, force: true }); }
