#!/usr/bin/env node
// Checks a mini app the way the app will load it: app.json, the entry, every
// module compiled with the same Sucrase the app runs, and every import
// resolved. It cannot render the app: what it passes may still fail at run time.
//
// usage: node check.mjs <id or folder>
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
// In the app the bundle is /opt/dsh; in the repository, the committed runtime.
const compilers = ['/opt/dsh/miniapp-sucrase.js', path.join(here, '../../../../app/DshIOS/MiniApps/Runtime/miniapp-sucrase.js')];
const builtIn = new Set(['react', 'react-dom', 'react-dom/client', 'react/jsx-runtime', 'react/jsx-dev-runtime']);
const modules = new Set(['.js', '.jsx', '.ts', '.tsx', '.mjs']);

const arg = process.argv[2];
if (!arg) {
  console.error('usage: node check.mjs <id or folder>');
  process.exit(2);
}
const folder = path.resolve(arg.includes('/') ? arg.replace(/^~(?=\/)/, os.homedir()) : path.join(os.homedir(), 'apps', arg));
const problems = [];
const problem = (file, message) => problems.push(`${file ? path.relative(folder, file) + ': ' : ''}${message}`);

const sucrase = (() => {
  const file = compilers.find((candidate) => fs.existsSync(candidate));
  if (!file) return null;
  const context = vm.createContext({});
  vm.runInContext(fs.readFileSync(file, 'utf8'), context);
  return context.sucrase;
})();

if (!fs.existsSync(folder)) {
  console.error(`no app at ${folder}`);
  process.exit(1);
}
const id = path.basename(folder);
if (!/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(id)) problem(null, `folder name "${id}" must be lower-case letters, digits and hyphens`);

const manifest = path.join(folder, 'app.json');
try {
  const json = JSON.parse(fs.readFileSync(manifest, 'utf8'));
  // A name, or names by language ({"zh-Hans": …, "en": …}): the app's own examples use those.
  const names = typeof json.name === 'object' && json.name ? Object.values(json.name) : [json.name];
  if (!names.length || names.some((name) => typeof name !== 'string' || !name.trim())) problem(manifest, '"name" is missing');
  if (typeof json.icon !== 'string' || !/\p{Extended_Pictographic}/u.test(json.icon)) problem(manifest, '"icon" should be one emoji');
  if (json.color !== undefined && !/^#[0-9a-fA-F]{6}$/.test(json.color)) problem(manifest, '"color" should be #RRGGBB');
} catch (error) {
  problem(manifest, fs.existsSync(manifest) ? `not valid JSON: ${error.message}` : 'missing');
}

const entries = ['index.html', 'App.jsx', 'App.tsx', 'App.js', 'App.ts'].map((name) => path.join(folder, name)).filter((file) => fs.existsSync(file));
if (entries.length === 0) problem(null, 'no entry: write App.jsx (or App.tsx), or index.html');

// Follow the module graph from the entry: what the page will actually load.
const seen = new Set();
const queue = [];
const entry = entries[0];
if (entry?.endsWith('.html')) {
  const html = fs.readFileSync(entry, 'utf8');
  for (const match of html.matchAll(/<script\b[^>]*\bsrc=["']([^"']+)["']/gi)) {
    if (!/^[a-z]+:|^\/\//i.test(match[1])) queue.push(path.resolve(folder, match[1].replace(/^\//, '')));
  }
  const inline = [...html.matchAll(/<script\b[^>]*type=["']module["'][^>]*>([\s\S]*?)<\/script>/gi)].map((match) => match[1]);
  inline.forEach((code, index) => check(code, `${path.basename(entry)} (inline module ${index + 1})`, entry));
} else if (entry) {
  queue.push(entry);
  const source = fs.readFileSync(entry, 'utf8');
  if (!/export\s+default\b/.test(source)) problem(entry, 'needs a default export: the component to render');
}

while (queue.length) {
  const file = queue.shift();
  if (seen.has(file)) continue;
  seen.add(file);
  if (!fs.existsSync(file)) continue;
  if (modules.has(path.extname(file))) check(fs.readFileSync(file, 'utf8'), path.basename(file), file);
}

function check(source, name, file) {
  const ext = path.extname(file);
  let code = source;
  if (sucrase && !file.endsWith('.min.js') && ext !== '.mjs' && ext !== '.html') {
    try {
      code = sucrase.transform(source, {
        transforms: ext === '.ts' || ext === '.tsx' ? ['jsx', 'typescript'] : ['jsx'],
        jsxRuntime: 'automatic', production: true, filePath: name,
      }).code;
    } catch (error) {
      problem(file, error.message);
      return;
    }
  }
  // Syntax of the compiled module: as CommonJS, which a plain script can parse.
  if (sucrase) {
    try {
      new vm.Script(sucrase.transform(code, { transforms: ['imports'] }).code, { filename: name });
    } catch (error) {
      problem(file, `${error.name}: ${error.message}`);
    }
  }
  const imports = [...code.matchAll(/(?:\bimport\s*(?:[\w*{}\s,$]+\s*from\s*)?|\bexport\s*[\w*{}\s,$]+\s*from\s*|\bimport\s*\(\s*)(["'])([^"']+)\1/g)].map((match) => match[2]);
  for (const spec of imports) {
    if (/^https?:\/\//.test(spec)) continue;
    if (spec.startsWith('.') || spec.startsWith('/')) {
      const target = spec.startsWith('/') ? path.join(folder, spec) : path.resolve(path.dirname(file), spec);
      if (!target.startsWith(folder + path.sep)) problem(file, `"${spec}" is outside the app's folder`);
      else if (!fs.existsSync(target)) problem(file, `"${spec}" does not exist${path.extname(spec) ? '' : ' (write the extension)'}`);
      else queue.push(target);
    } else if (!builtIn.has(spec)) {
      problem(file, `"${spec}" is not built in: use a full URL (https://esm.sh/${spec}) or write it yourself`);
    }
  }
}

if (!sucrase) console.log('note: the compiler was not found, so JSX and TypeScript were not compiled');
if (problems.length) {
  console.log(`${problems.length} problem${problems.length > 1 ? 's' : ''} in ${id}:`);
  for (const line of problems) console.log(`- ${line}`);
  process.exit(1);
}
const checked = [...seen].filter((file) => modules.has(path.extname(file))).length;
console.log(`${id}: OK (${checked} module${checked === 1 ? '' : 's'} checked). Open it with [name](fishapp://${id}).`);
