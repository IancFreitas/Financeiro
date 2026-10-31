import test from 'node:test';
import assert from 'node:assert/strict';
import { encryptPayload, decryptPayload, Vault } from '../src/vault.js';

const password = 'somente-exemplo-ficticio-2026';
const tx = { id: '4eb63678-8f71-414e-b8db-52f869a30574', amountMinor: 12345, currency: 'BRL', merchant: 'Loja fictícia', date: '2026-10-31T15:00:00.000Z', kind: 'expense', category: 'Outros', account: 'Principal', source: 'manual', note: 'Dado sintético' };

async function encryptedRaw(state) {
  const envelope = await encryptPayload([], password);
  const salt = Uint8Array.from(atob(envelope.salt), c => c.charCodeAt(0));
  const material = await crypto.subtle.importKey('raw', new TextEncoder().encode(password), 'PBKDF2', false, ['deriveKey']);
  const key = await crypto.subtle.deriveKey({ name: 'PBKDF2', salt, iterations: envelope.iterations, hash: 'SHA-256' }, material, { name: 'AES-GCM', length: 256 }, false, ['encrypt']);
  const { ciphertext, ...header } = envelope;
  const result = await crypto.subtle.encrypt({ name: 'AES-GCM', iv: Uint8Array.from(atob(envelope.iv), c => c.charCodeAt(0)), additionalData: new TextEncoder().encode(JSON.stringify(header)), tagLength: 128 }, key, new TextEncoder().encode(JSON.stringify(state)));
  return { ...header, ciphertext: Buffer.from(result).toString('base64') };
}

test('encrypted backup round trip and independent nonce/salt generation', async () => {
  const first = await encryptPayload([tx], password); const second = await encryptPayload([tx], password);
  assert.equal(first.iterations, 600_000); assert.equal(first.algorithm, 'AES-256-GCM');
  assert.equal(Buffer.from(first.salt, 'base64').length, 16); assert.equal(Buffer.from(first.iv, 'base64').length, 12);
  assert.notEqual(first.salt, second.salt); assert.notEqual(first.iv, second.iv); assert.notEqual(first.ciphertext, second.ciphertext);
  const serialized = JSON.stringify(first);
  for (const plaintext of [tx.merchant, tx.note, 'amountMinor', password]) assert.equal(serialized.includes(plaintext), false);
  assert.deepEqual(await decryptPayload(serialized, password), [tx]);
});

test('wrong password, ciphertext changes, IV changes and authenticated revision tampering fail', async () => {
  const envelope = await encryptPayload([tx], password);
  await assert.rejects(decryptPayload(envelope, 'outra-senha-ficticia-2026'), /Senha incorreta/);
  const bytes = Buffer.from(envelope.ciphertext, 'base64'); bytes[0] ^= 1;
  await assert.rejects(decryptPayload({ ...envelope, ciphertext: bytes.toString('base64') }, password), /alterado/);
  const iv = Buffer.from(envelope.iv, 'base64'); iv[0] ^= 1;
  await assert.rejects(decryptPayload({ ...envelope, iv: iv.toString('base64') }, password), /alterado/);
  await assert.rejects(decryptPayload({ ...envelope, revision: 2 }, password), /alterado/);
});

test('unsupported or malformed envelopes are rejected before key derivation', async () => {
  const envelope = await encryptPayload([], password);
  for (const changes of [{ version: 2 }, { iterations: 1 }, { iterations: 999999999 }, { algorithm: 'AES-CBC' }, { revision: 0 }, { revision: Number.MAX_SAFE_INTEGER + 1 }, { salt: 'AAAA' }, { iv: 'not base64' }, { ciphertext: 'A===' }, { ciphertext: 'AA==' }, { extra: true }, { salt: envelope.salt.slice(0, -1) }, { ciphertext: 'A'.repeat((14 * 1024 * 1024 + 16) * 2) }]) await assert.rejects(decryptPayload({ ...envelope, ...changes }, ''), undefined, JSON.stringify(Object.keys(changes)));
  await assert.rejects(decryptPayload('x'.repeat(20 * 1024 * 1024 + 1), password), /20 MiB/);
});

test('password limits and invalid financial data prevent encryption', async () => {
  for (const value of ['', 'curta', 'x'.repeat(1025), '🔐'.repeat(300)]) await assert.rejects(encryptPayload([tx], value));
  await assert.rejects(encryptPayload([{ ...tx, amountMinor: -1 }], password));
  await assert.rejects(encryptPayload([tx, tx], password), /duplicados/);
});

test('authenticated but invalid schema, financial data or duplicate UUIDs cannot be restored', async () => {
  for (const state of [{ schema: 2, transactions: [] }, { schema: 1, transactions: [], extra: true }, { schema: 1, transactions: [{ ...tx, currency: 'USD' }] }, { schema: 1, transactions: [tx, tx] }]) await assert.rejects(decryptPayload(await encryptedRaw(state), password));
});

test('database names are bounded and reject invalid inputs', async () => {
  for (const name of ['', null, 'x'.repeat(129), 'nome com espaço']) await assert.rejects(Vault.open(name), /Nome do armazenamento inválido/);
});

test('IndexedDB absence fails explicitly without memory or plaintext fallback', async () => {
  if (!globalThis.indexedDB) await assert.rejects(Vault.open(), /IndexedDB/);
});
