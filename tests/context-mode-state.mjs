// Exercise real SQLite and the installed adapter, never the user's state.
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
const root = resolve(process.argv[2]);
const dir = mkdtempSync(join(tmpdir(), 'context-state-'));
process.env.HOME = dir;
process.env.XDG_CONFIG_HOME = join(dir, 'config');
process.env.PI_CODING_AGENT_DIR = join(dir, 'pi');
try {
  const registry = join(dir, 'registry');
  mkdirSync(registry);
  mkdirSync(process.env.PI_CODING_AGENT_DIR);
  writeFileSync(join(registry, 'package.json'), JSON.stringify({ pi: { extensions: [join(root, 'pi/index.js')] } }));
  writeFileSync(join(process.env.PI_CODING_AGENT_DIR, 'settings.json'), JSON.stringify({ packages: [registry] }));
  const tools = new Map(), events = new Map();
  const { default: extension } = await import(pathToFileURL(join(root, 'pi/index.js')));
  extension({ registerTool: tool => tools.set(tool.name, tool), on: (name, handler) => events.set(name, handler) });
  let cwd = join(dir, 'first'), session = 'first';
  mkdirSync(cwd);
  const ctx = () => ({ cwd, sessionManager: { getSessionId: () => session } });
  await events.get('session_start')({}, ctx());
  await events.get('before_agent_start')({ systemPrompt: '' }, ctx());
  const call = async name => (await tools.get(name).execute('state-test', {}, undefined)).content.map(c => c.text ?? '').join('\n');
  await call('ctx_stats');
  assert.match(await call('ctx_resume'), /session="first"/);
  const doctor = await call('ctx_doctor');
  for (const check of ['D3 host config', 'D7 project and worktree', 'D8 context.db', 'D9 index']) {
    assert(doctor.includes(`| ${check} | PASS |`), doctor);
  }
  cwd = join(dir, 'second'); session = 'second'; mkdirSync(cwd);
  await events.get('session_start')({}, ctx());
  await events.get('before_agent_start')({ systemPrompt: '' }, ctx());
  await call('ctx_stats');
  const resumed = await call('ctx_resume');
  assert.match(resumed, /session="second"/);
  assert.doesNotMatch(resumed, /session="first"/);
  console.log('SQLite persistence, Nix registry recognition, live cwd and session switching passed.');
} finally { rmSync(dir, { recursive: true, force: true }); }
