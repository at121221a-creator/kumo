// New sessions default to full access, and the default stays the user's to change
// in 设置 (runtime/permission-default.mjs). The overlay used to carry it, which the
// config editor then refused to override; these compose the real profile with the
// iOS overlay, the way `dsh web` does, to check what a session would start in.
import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseDocument } from 'yaml';
import { ENTRY, PRESET, seedPermissionDefault } from '../runtime/permission-default.mjs';

const engine = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const bin = path.join(engine, 'node_modules/@deepseek-ai/dsh/lib/bin.js');
const installAnchor = path.join(engine, 'node_modules/@deepseek-ai/dsh/package.json');
const overlay = path.join(engine, 'ios.patch.yml');

function setup(t) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'dsh-permission-'));
  t.after(() => fs.rmSync(home, { recursive: true, force: true }));
  const marker = path.join(home, '.ios-permission-default');
  const patchFile = path.join(home, 'profiles/web/cordis.patch.yml');
  return { home, marker, patchFile, seed: () => seedPermissionDefault({ home, marker, installAnchor }) };
}

/** The `permission` entry's composed config under `home`, with or without the iOS overlay. */
function permission(home, ...flags) {
  const dump = execFileSync(process.execPath, [bin, 'web', ...flags], {
    encoding: 'utf8',
    env: { ...process.env, DSH_HOME: home, DSH_IOS_DOCUMENTS: home },
  });
  // The dump keeps `!!js` expressions as tagged scalars; none sit in this entry.
  const entries = parseDocument(dump, { logLevel: 'silent' }).toJS();
  return entries.find((entry) => entry.id === ENTRY).config;
}
const composed = (home) => permission(home, '--patch', overlay, '--dump-config');

/** Rewrite the profile's own `permission` row, as a 设置 write would. */
function choose(patchFile, preset) {
  const document = parseDocument(fs.readFileSync(patchFile, 'utf8'));
  const row = document.contents.items.find((item) => item.get('id') === ENTRY);
  row.setIn(['config', 'defaultPreset'], preset);
  fs.writeFileSync(patchFile, String(document));
}

test('the iOS overlay leaves permission alone, so 设置 can write it', () => {
  const rows = parseDocument(fs.readFileSync(overlay, 'utf8')).toJS();
  assert.equal(rows.some((row) => row.id === ENTRY), false);
});

test('a first launch seeds full access, with the shipped preset table', async (t) => {
  const { home, marker, seed } = setup(t);
  assert.equal(await seed(), 'seeded');
  assert.equal(fs.readFileSync(marker, 'utf8'), 'seeded\n');
  const shipped = permission(home, '--dump-default-config');
  const config = composed(home);
  assert.equal(config.defaultPreset, PRESET);
  assert.deepEqual(config.presets, shipped.presets);
  assert.deepEqual(Object.keys(config.presets), Object.keys(shipped.presets));
});

test('after seeding, another default chosen in 设置 is the one that composes', async (t) => {
  // The config editor refuses a write unless the composed config then equals it.
  const { home, patchFile, seed } = setup(t);
  await seed();
  for (const preset of ['workspace-write', 'read-only', PRESET]) {
    choose(patchFile, preset);
    assert.equal(composed(home).defaultPreset, preset);
  }
});

test("a default the user already chose is kept, and the rest of the file too", async (t) => {
  const { home, marker, patchFile, seed } = setup(t);
  await seed();
  choose(patchFile, 'workspace-write');
  const text = `# mine\n${fs.readFileSync(patchFile, 'utf8')}- id: shell-env\n  config:\n    home: !!js process.env.HOME\n`;
  fs.writeFileSync(patchFile, text);
  fs.rmSync(marker);
  assert.equal(await seed(), 'kept');
  assert.equal(fs.readFileSync(patchFile, 'utf8'), text);
  assert.equal(composed(home).defaultPreset, 'workspace-write');
});

test('it runs once: a default removed later is not seeded again', async (t) => {
  const { home, patchFile, seed } = setup(t);
  await seed();
  fs.writeFileSync(patchFile, '[]\n');
  assert.equal(await seed(), 'done');
  assert.equal(fs.readFileSync(patchFile, 'utf8'), '[]\n');
  assert.equal(composed(home).defaultPreset, undefined);
});

test('an existing profile without a permission row is seeded, its other rows kept', async (t) => {
  const { home, patchFile, seed } = setup(t);
  permission(home, '--dump-config'); // creates the profile, as an earlier launch did
  fs.writeFileSync(patchFile, '# mine\n- id: shell-env\n  config:\n    home: !!js process.env.HOME\n');
  assert.equal(await seed(), 'seeded');
  const text = fs.readFileSync(patchFile, 'utf8');
  assert.match(text, /^# mine\n- id: shell-env\n {2}config:\n {4}home: !!js process\.env\.HOME\n/);
  assert.equal(composed(home).defaultPreset, PRESET);
});
