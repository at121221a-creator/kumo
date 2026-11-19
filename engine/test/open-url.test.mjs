import { test } from 'node:test';
import assert from 'node:assert/strict';
import { runOpen } from '../runtime/open-url.mjs';

test('open hands each URL operand to the capability and skips options', async () => {
  const opened = [];
  const result = await runOpen('open', ['-a', 'Safari', 'https://example.com/a?b=1'], async (url) => { opened.push(url); });
  assert.deepEqual(opened, ['https://example.com/a?b=1']);
  assert.deepEqual(result, { stdout: '', stderr: '', exitCode: 0 });
});

test('xdg-open with a file path fails instead of pretending', async () => {
  const result = await runOpen('xdg-open', ['/tmp/report.pdf'], async () => assert.fail('nothing to open'));
  assert.equal(result.exitCode, 1);
  assert.match(result.stderr, /^xdg-open: only URLs/);
});

test('a refusal from the capability is the command failing, with its message', async () => {
  const result = await runOpen('open', ['facetime:123'], async () => { throw new Error("'facetime' links are not opened from here"); });
  assert.equal(result.exitCode, 1);
  assert.match(result.stderr, /facetime/);
});
