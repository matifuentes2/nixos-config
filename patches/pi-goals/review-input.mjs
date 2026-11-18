// Deterministic lockfile summaries, never model-selected exclusions. Unknown
// formats and any ambiguity retain their original diff. Values are not elided.
function parseLock(text) {
  const value = JSON.parse(text);
  // Validate duplicate keys and numeric fidelity before trusting JSON.parse.
  const tokens = text.match(/"(?:[^"\\]|\\.)*"|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|true|false|null|[{}\[\]:,]/g) ?? [];
  let i = 0;
  function visit() {
    const token = tokens[i++];
    if (token === '{') {
      const keys = new Set();
      if (tokens[i] === '}') { i++; return; }
      do {
        const key = JSON.parse(tokens[i++]);
        if (keys.has(key)) throw Error('Duplicate JSON key');
        keys.add(key);
        if (tokens[i++] !== ':') throw Error('Invalid object');
        visit();
      } while (tokens[i++] === ',');
    } else if (token === '[') {
      if (tokens[i] === ']') { i++; return; }
      do { visit(); } while (tokens[i++] === ',');
    } else if (/^-?\d/.test(token)) {
      if (JSON.stringify(JSON.parse(token)) !== token) throw Error('Lossy numeric representation');
    }
  }
  visit();
  return value;
}

const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const own = (value, key) => Object.prototype.hasOwnProperty.call(value, key);
function changes(before, after, path = '') {
  if (object(before) && object(after)) {
    return [...new Set([...Object.keys(before), ...Object.keys(after)])].sort().flatMap(key => {
      const pointer = `${path}/${key.replaceAll('~', '~0').replaceAll('/', '~1')}`;
      if (!own(before, key)) return [{ path: pointer, added: after[key] }];
      if (!own(after, key)) return [{ path: pointer, removed: before[key] }];
      return changes(before[key], after[key], pointer);
    });
  }
  // Arrays retain ordering and all entries. No dependency fields are allowlisted.
  if (JSON.stringify(before) === JSON.stringify(after)) return [];
  return [{ path, before, after }];
}

export async function reviewInput(diff, readBlob) {
  const files = diff.split(/(?=^diff --git )/m).filter(Boolean);
  const result = [];
  for (const file of files) {
    // Restrict to ordinary modified files with unambiguous paths and modes.
    // Added/deleted files, symlinks, renames and unusual paths get full review.
    const match = /^diff --git a\/([\w./-]+) b\/\1\nindex ([a-f0-9]{40})\.\.([a-f0-9]{40}) 100644\n--- a\/\1\n\+\+\+ b\/\1\n/.exec(file);
    const name = match?.[1].split('/').at(-1);
    if (!['flake.lock', 'package-lock.json', 'npm-shrinkwrap.json'].includes(name)) {
      result.push(file); continue;
    }
    try {
      const before = parseLock(await readBlob(match[2]));
      const after = parseLock(await readBlob(match[3]));
      if (!object(before) || !object(after)) throw Error('Not a lockfile object');
      const entries = changes(before, after);
      const summary = file.slice(0, file.indexOf('\n') + 1) +
        'Structured lockfile review (JSON Pointer paths; every changed value included).\n' +
        'Check dependency sources, versions, integrity, metadata and consistency with manifests. ' +
        'Unchanged values, object key order and whitespace omitted. Arrays retain order.\n' +
        `Original Git blobs: ${match[2]} -> ${match[3]}.\n` +
        (entries.length ? entries.map(entry => JSON.stringify(entry)).join('\n') : 'No JSON value changes; formatting/key order only.') + '\n';
      result.push(summary.length < file.length ? summary : file);
    } catch {
      // Includes capped/unavailable blobs and invalid JSON. Never partial coverage.
      result.push(file);
    }
  }
  return result.join('');
}
