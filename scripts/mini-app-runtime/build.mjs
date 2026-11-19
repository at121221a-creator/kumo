// Builds the files 我的应用 (mini apps) load from the app bundle: React as ES
// modules, which an app's import map points `react`, `react-dom`,
// `react-dom/client` and `react/jsx-runtime` at, and Sucrase, which the app
// runs in JavaScriptCore to turn an app's JSX and TypeScript into JavaScript.
//
// React ships CommonJS only, so each module is a small wrapper that lists its
// exports by name; they share one chunk, so every module of a page sees the
// same React.
//
// usage: node build.mjs <esbuild main.js> <node_modules> <out dir>
import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';

const [esbuildPath, modules, out] = process.argv.slice(2);
const { build } = await import(esbuildPath);
const require = createRequire(path.join(modules, 'noop.js'));

// MIT asks for the license with every copy: each file starts with its packages' licenses.
const license = (...ids) => ids.map((id) => {
  const dir = path.dirname(require.resolve(`${id}/package.json`));
  const { version } = JSON.parse(fs.readFileSync(path.join(dir, 'package.json'), 'utf8'));
  const file = fs.readdirSync(dir).find((name) => /^licen[cs]e/i.test(name));
  if (!file) throw new Error(`${id} has no license file`);
  const text = fs.readFileSync(path.join(dir, file), 'utf8').trim().replaceAll('*/', '* /');
  return `/*\n${id} ${version}\n\n${text}\n*/`;
}).join('\n');

// Beside node_modules, under fixed names: the shared chunk's name is a hash of its inputs' paths.
const base = path.dirname(modules);
const work = path.join(base, 'entries');
fs.mkdirSync(work, { recursive: true });
const named = (id) => Object.keys(require(id)).filter((key) => key !== 'default' && /^[A-Za-z_$][\w$]*$/.test(key));
const wrapper = (id) => {
  const names = named(id);
  return `import m from ${JSON.stringify(id)};\nexport default m;\nexport const { ${names.join(', ')} } = m;\n`;
};

const entries = {
  'miniapp-react': 'react',
  'miniapp-react-dom': 'react-dom',
  'miniapp-react-dom-client': 'react-dom/client',
  'miniapp-jsx-runtime': 'react/jsx-runtime',
};
for (const [name, id] of Object.entries(entries)) fs.writeFileSync(path.join(work, `${name}.js`), wrapper(id));

fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(out, { recursive: true });

try {
  await build({
    entryPoints: Object.keys(entries).map((name) => path.join(work, `${name}.js`)),
    bundle: true,
    splitting: true,
    format: 'esm',
    minify: true,
    target: 'safari17',
    nodePaths: [modules],
    absWorkingDir: base,
    define: { 'process.env.NODE_ENV': '"production"' },
    chunkNames: 'miniapp-shared-[hash]',
    banner: { js: license('react', 'react-dom', 'scheduler') },
    outdir: out,
    legalComments: 'none',
  });

  // JavaScriptCore has no modules: a script that leaves `sucrase` on the global object.
  fs.writeFileSync(path.join(work, 'sucrase.js'), "export { transform } from 'sucrase';\n");
  await build({
    entryPoints: [path.join(work, 'sucrase.js')],
    bundle: true,
    format: 'iife',
    globalName: 'sucrase',
    minify: true,
    target: 'safari17',
    platform: 'neutral',
    mainFields: ['module', 'main'],
    nodePaths: [modules],
    outfile: path.join(out, 'miniapp-sucrase.js'),
    // Sucrase and what its transform pulls in.
    banner: { js: license('sucrase', 'lines-and-columns', 'ts-interface-checker', '@jridgewell/gen-mapping',
      '@jridgewell/sourcemap-codec', '@jridgewell/trace-mapping', '@jridgewell/resolve-uri') },
    legalComments: 'none',
  });
} finally {
  fs.rmSync(work, { recursive: true, force: true });
}
