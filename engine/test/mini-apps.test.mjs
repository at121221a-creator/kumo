import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

const script = new URL('../skills/mini-apps/scripts/check.mjs', import.meta.url).pathname;

function app(files) {
  const folder = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'mini-apps-')), 'sample');
  for (const [name, text] of Object.entries(files)) {
    fs.mkdirSync(path.dirname(path.join(folder, name)), { recursive: true });
    fs.writeFileSync(path.join(folder, name), text);
  }
  return folder;
}

function check(folder) {
  try {
    return { code: 0, out: execFileSync(process.execPath, [script, folder], { encoding: 'utf8' }) };
  } catch (error) {
    return { code: error.status, out: error.stdout };
  }
}

const manifest = JSON.stringify({ name: '示例', icon: '🧪', color: '#336699' });

test('a React app with TypeScript, CSS, JSON and a second module passes', () => {
  const { code, out } = check(app({
    'app.json': manifest,
    'App.tsx': "import { useState } from 'react';\nimport './a.css';\nimport data from './d.json';\nimport { f } from './lib/f.ts';\nexport default function App() { const [n] = useState<number>(data.n); return <p>{f(n)}</p>; }\n",
    'a.css': 'p{color:red}',
    'd.json': '{"n":1}',
    'lib/f.ts': 'export const f = (n: number): string => String(n);\n',
  }));
  assert.equal(code, 0, out);
  assert.match(out, /OK \(2 modules checked\)/);
  assert.match(out, /fishapp:\/\/sample/);
});

test('syntax errors, missing files, packages and a bad manifest are reported', () => {
  const { code, out } = check(app({
    'app.json': '{"name":"x","icon":"x"}',
    'App.jsx': "import _ from 'lodash';\nimport b from './missing';\nexport default function App() { return <div />; }\n",
  }));
  assert.equal(code, 1);
  assert.match(out, /"icon" should be one emoji/);
  assert.match(out, /"lodash" is not built in/);
  assert.match(out, /"\.\/missing" does not exist \(write the extension\)/);

  const broken = check(app({ 'app.json': manifest, 'App.jsx': 'export default function App() { return <div><span></div>; }\n' }));
  assert.equal(broken.code, 1);
  assert.match(broken.out, /App\.jsx: .*JSX/);
});

test('an app needs an entry with a default export', () => {
  assert.match(check(app({ 'app.json': manifest })).out, /no entry/);
  assert.match(check(app({ 'app.json': manifest, 'App.jsx': 'export function App() { return null; }\n' })).out, /default export/);
});
