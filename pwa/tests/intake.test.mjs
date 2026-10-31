import test from 'node:test';
import assert from 'node:assert/strict';
import { decodeIntakeFragment, readIntakeFragment } from '../src/intake.js';

test('fragment transports UTF-8 JSON without query parameters', () => {
  const json = JSON.stringify({ merchant: 'Café fictício', amount: '1,23', kind: 'expense' });
  const b64 = Buffer.from(json).toString('base64url');
  assert.equal(decodeIntakeFragment('#/capture?data=' + b64), json);
  assert.equal(decodeIntakeFragment('#/'), null);
  assert.throws(() => decodeIntakeFragment('#/capture?data=%notvalid'));
});

test('capture data is removed from the visible URL even when malformed', () => {
  let replaced = null;
  globalThis.window = { location: { hash: '#/capture?data=!!', pathname: '/app/' },
    history: { replaceState: (...args) => { replaced = args[2]; } } };
  try {
    assert.throws(() => readIntakeFragment());
    assert.equal(replaced, '/app/#/');
  } finally { delete globalThis.window; }
});
