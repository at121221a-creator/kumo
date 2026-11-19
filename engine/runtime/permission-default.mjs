// New sessions start in full access instead of the stock workspace-write + ask,
// and the default stays the user's to change in 设置.
//
// So the default cannot go into ios.patch.yml: `--patch` is the command-line
// overlay, above the profile layer 设置 writes, and the config editor refuses
// any write an overlay would override ("Configuration for "permission" is
// overridden by a home patch or command-line overlay"). Every value but full
// access was then refused, and a default chosen before the overlay was
// silently overridden.
//
// Instead, once per install, the profile's own patch file (the layer 设置
// writes) gets the row a 设置 write of full access would leave, unless it
// already has one: then the user chose, and it stays. From then on the value is
// the user's like any other they set. A marker records that this ran, so a
// later reset in the web settings is not undone at the next boot.
import { existsSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { composeEntries, loadProfile } from '@deepseek-ai/dsh-app-boot';
import { writeFileAtomic } from '@deepseek-ai/dsh-atomic-write';
import { isSeq, parseDocument } from 'yaml';

export const ENTRY = 'permission';
export const PRESET = 'danger-full-access';

/** Rows of a composed list, with those nested in groups (as the config editor reads them). */
const flatten = (rows) => rows.flatMap((row) => [row, ...(row.group && Array.isArray(row.config) ? flatten(row.config) : [])]);

/**
 * Give the `web` profile a full-access default unless it has a permission config of its own.
 * @param {object} options
 * @param {string} options.home - DSH_HOME.
 * @param {string} options.marker - the file that records this ran.
 * @param {string} options.installAnchor - the dsh package's package.json, where profile bundles resolve from.
 * @returns {Promise<'seeded' | 'kept' | 'done'>} what it found: wrote the default,
 *   left the user's own, or had already run.
 */
export async function seedPermissionDefault({ home, marker, installAnchor }) {
  if (existsSync(marker)) return 'done';
  // What `dsh web` does first: creates the profile on a first launch, otherwise only reads it.
  const profile = loadProfile('dsh', 'web', installAnchor, home);
  const own = profile.patches.some((row) => row.id === ENTRY && row.insert === undefined && Object.hasOwn(row, 'config'));
  let outcome = 'kept';
  if (!own) {
    // The layers beneath the profile patch, composed as the config editor's `inherited`.
    const row = flatten(composeEntries([...profile.layers.map((layer) => layer.patches), profile.patches]))
      .find((entry) => entry.id === ENTRY);
    if (row !== undefined) {
      // A patch config replaces the whole config, so it carries the shipped preset table too.
      await append(profile.patchPath, { id: ENTRY, name: row.name, config: { ...row.config, defaultPreset: PRESET } });
      outcome = 'seeded';
    }
  }
  await writeFileAtomic(marker, `${outcome}\n`, { mode: 0o600 });
  return outcome;
}

/** Add one row to a patch file, keeping what is there (comments and `!!js` tags included). */
async function append(file, row) {
  let text;
  try {
    text = await readFile(file, 'utf8');
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
    text = '[]\n';
  }
  const document = parseDocument(text, {
    customTags: [{ tag: 'tag:yaml.org,2002:js', resolve: (value) => value }],
  });
  if (document.errors[0] !== undefined) throw document.errors[0];
  if (document.contents === null) document.contents = document.createNode([]);
  if (!isSeq(document.contents)) throw new Error(`${file}: a profile patch must be a YAML sequence`);
  document.contents.flow = false;
  document.add(document.createNode(row));
  // The config editor's own form: owner-only.
  await writeFileAtomic(file, String(document), { mode: 0o600 });
}
