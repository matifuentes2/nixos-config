import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';
import { join } from 'node:path';
const { reviewInput } = await import(process.argv[2] ? pathToFileURL(join(process.argv[2], 'src/review-input.mjs')) : '../patches/pi-goals/review-input.mjs');
const old = 'a'.repeat(40), next = 'b'.repeat(40);
const diff = (name, body = '-old\n+new\n'.repeat(200)) => `diff --git a/${name} b/${name}\nindex ${old}..${next} 100644\n--- a/${name}\n+++ b/${name}\n@@ -1 +1 @@\n${body}`;
const base = { lockfileVersion: 3, packages: { 'node_modules/example': { version: '1', resolved: 'https://registry.npmjs.org/example', integrity: 'old', hasInstallScript: false } }, unchanged: 'x'.repeat(3000) };
const changed = structuredClone(base);
Object.assign(changed.packages['node_modules/example'], { version: '2', resolved: 'https://example.invalid/package', integrity: 'new', hasInstallScript: true, unexpected: ['b', 'a'] });
const summarize = (name, a, b) => reviewInput(diff(name), async oid => oid === old ? a : b);
for (const name of ['flake.lock', 'nested/package-lock.json', 'npm-shrinkwrap.json']) {
  const result = await summarize(name, JSON.stringify(base), JSON.stringify(changed));
  assert(result.length < diff(name).length);
  assert(result.includes('Structured lockfile review'));
  for (const value of ['https://example.invalid/package', 'integrity', 'hasInstallScript', 'unexpected', 'node_modules~1example']) assert(result.includes(value));
  assert(!result.includes('x'.repeat(100)));
}
assert.match(await summarize('flake.lock', '{"a":1,"b":2}', '{ "b":2,"a":1 }'), /No JSON value changes/);
const removed = await summarize('flake.lock', '{"gone":{"hash":"abc"}}', '{"added":null}');
assert(removed.includes('"removed":{"hash":"abc"}')); assert(removed.includes('"added":null'));
for (const invalid of ['{bad}', '{"a":1,"a":2}', '{"a":{"x":1,"\\u0078":2}}', '{"a":9007199254740993}', '[]']) {
  assert.equal(await summarize('flake.lock', invalid, '{}'), diff('flake.lock'));
}
assert.equal(await summarize('source.json', '{}', '{}'), diff('source.json'));
assert.equal(await summarize('generated.min.js', '{}', '{}'), diff('generated.min.js'));
assert.equal(await reviewInput(diff('flake.lock'), async () => { throw Error('capped'); }), diff('flake.lock'));
for (const file of [diff('flake.lock').replace('100644', '120000'), diff('flake.lock').replace(`index ${old}`, `new file mode 100644\nindex ${old}`), diff('space name/flake.lock')]) {
  assert.equal(await reviewInput(file, async () => '{}'), file);
}
assert.equal(await reviewInput(diff('flake.lock', '-1\n+2\n'), async () => '{}'), diff('flake.lock', '-1\n+2\n'));
const mixed = await reviewInput(diff('source.js') + diff('flake.lock'), async oid => JSON.stringify(oid === old ? base : changed));
assert(mixed.startsWith(diff('source.js'))); assert.equal(mixed.match(/^diff --git /gm).length, 2);
console.log('Lockfile coverage, token reduction, metadata preservation and conservative fallbacks passed.');
