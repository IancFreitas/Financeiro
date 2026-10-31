/** Browser-only QA, with an isolated synthetic database; never include tests in dist. */
import { Vault } from '../src/vault.js';
import { validateTransaction } from '../src/core.js';

const assert = (condition, message) => { if (!condition) throw new Error(message); };
const same = (left, right) => JSON.stringify(left) === JSON.stringify(right);
async function rejects(operation, expected) {
  try { await operation(); } catch (error) {
    if (expected && !expected.test(String(error.message))) throw new Error(`Erro inesperado: ${error.message}`);
    return;
  }
  throw new Error('A operação deveria ter sido recusada.');
}
async function storedEnvelope(databaseName) {
  const database = await new Promise((resolve, reject) => {
    const request = indexedDB.open(databaseName, 1);
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
  try {
    return await new Promise((resolve, reject) => {
      const transaction = database.transaction('vault', 'readonly');
      const request = transaction.objectStore('vault').get('primary');
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  } finally { database.close(); }
}

/**
 * Writes only synthetic records in a unique QA database. Never opens the production database.
 * Returns check names and statuses, without passwords, keys or financial contents.
 */
export async function runVaultBrowserChecks() {
  const checks = [];
  const check = async (name, action) => {
    await action(); checks.push({ name, passed: true });
  };
  const databaseName = `financeiro-qa-${crypto.randomUUID()}`;
  const first = await Vault.open(databaseName);
  assert(!(await first.exists()), 'O banco de QA já existe. A execução foi cancelada.');
  const password = `QA-SYNTHETIC-${crypto.randomUUID()}`;
  const tx = (index, overrides = {}) => validateTransaction({
    id: `00000000-0000-4000-8000-${String(index).padStart(12, '0')}`,
    amountMinor: 100 + index, currency: 'BRL', merchant: `QA-SYNTHETIC-ONLY-${index}`,
    date: '2026-10-31T15:00:00.000Z', kind: 'expense', category: 'QA fictícia',
    account: 'Conta de QA fictícia', source: 'manual', note: 'QA-NOTE-SYNTHETIC-ONLY', ...overrides,
  });
  let second;
  try {
    await check('Criação cifrada e desbloqueio inicial', async () => {
      await first.create(password);
      assert(first.isUnlocked && same(await first.list(), []), 'A criação não abriu um cofre vazio.');
    });
    await check('Fila local preserva duas gravações simultâneas', async () => {
      await Promise.all([first.save(tx(1)), first.save(tx(2))]);
      assert((await first.list()).length === 2, 'A fila perdeu uma gravação concorrente.');
    });
    second = await Vault.open(databaseName);
    await second.unlock(password);
    await check('Revisão CAS rejeita escrita de uma segunda instância desatualizada', async () => {
      await first.save(tx(3));
      await rejects(() => second.save(tx(4)), /outra janela/);
      await second.unlock(password);
      assert((await second.list()).length === 3 && !(await second.list()).some(item => item.id === tx(4).id), 'A escrita desatualizada alterou os dados.');
    });
    await check('Merge inválido tem rollback integral e UUID repetido é idempotente', async () => {
      const before = await first.list();
      await rejects(() => first.merge([tx(5), { ...tx(6), amountMinor: -1 }]));
      assert(same(await first.list(), before), 'Um lote parcialmente inválido foi gravado.');
      const result = await first.merge(before);
      assert(result.added === 0 && result.skipped === before.length, 'IDs existentes não foram ignorados.');
      assert(same(await first.list(), before), 'O merge sem alterações modificou os dados.');
    });
    await check('IndexedDB armazena somente envelope cifrado', async () => {
      const envelope = await storedEnvelope(databaseName);
      const serialized = JSON.stringify(envelope);
      assert(envelope.version === 1 && envelope.algorithm === 'AES-256-GCM', 'Envelope ausente.');
      for (const forbidden of ['QA-SYNTHETIC-ONLY', 'QA-NOTE-SYNTHETIC-ONLY', 'amountMinor', 'transactions', password]) assert(!serialized.includes(forbidden), 'O armazenamento contém conteúdo em texto claro.');
      assert(Object.keys(envelope).length === 9, 'Campos inesperados no armazenamento.');
    });
    let backup;
    await check('Backup gera nonce novo, usa o mesmo salt e restaura a fotografia íntegra', async () => {
      const stored = await storedEnvelope(databaseName);
      backup = await first.exportBackup();
      const envelope = JSON.parse(backup);
      assert(envelope.iv !== stored.iv && envelope.ciphertext !== stored.ciphertext && envelope.salt === stored.salt, 'O backup reutilizou nonce ou perdeu o salt.');
      assert(same(await first.inspectBackup(backup, password), await first.list()), 'O backup não restaura o estado exportado.');
    });
    await check('Senha errada e adulteração de ciphertext/header são recusadas sem mutação', async () => {
      const before = await first.list();
      await rejects(() => first.inspectBackup(backup, `${password}-errada`), /incorreta|alterado/);
      const envelope = JSON.parse(backup);
      const bytes = Uint8Array.from(atob(envelope.ciphertext), char => char.charCodeAt(0)); bytes[0] ^= 1;
      let binary = ''; for (const byte of bytes) binary += String.fromCharCode(byte);
      await rejects(() => first.inspectBackup(JSON.stringify({ ...envelope, ciphertext: btoa(binary) }), password), /alterado/);
      await rejects(() => first.inspectBackup(JSON.stringify({ ...envelope, revision: envelope.revision + 1 }), password), /alterado/);
      assert(same(await first.list(), before), 'A inspeção de backup alterou o cofre.');
    });
    await check('Merge de restauração adiciona ausentes e preserva edição existente', async () => {
      await first.save(tx(1, { merchant: 'QA-SYNTHETIC-ONLY-EDITADO' }));
      await first.remove(tx(2).id);
      const result = await first.merge(await first.inspectBackup(backup, password));
      const restored = await first.list();
      assert(result.added === 1 && result.skipped === 2 && restored.length === 3, 'A restauração não preservou os IDs.');
      assert(restored.find(item => item.id === tx(1).id).merchant === 'QA-SYNTHETIC-ONLY-EDITADO', 'A restauração sobrescreveu uma edição.');
      restored[0].merchant = 'Mutação externa';
      assert(!(await first.list()).some(item => item.merchant === 'Mutação externa'), 'A listagem expõe referências mutáveis internas.');
    });
    await check('Novo save mantém salt e aumenta revisão com nonce único', async () => {
      const before = await storedEnvelope(databaseName); await first.save(tx(7)); const after = await storedEnvelope(databaseName);
      assert(after.revision === before.revision + 1 && after.salt === before.salt && after.iv !== before.iv, 'Revisão, salt ou nonce incorreto.');
    });
    await check('Lock no mesmo tick cancela desbloqueio enfileirado', async () => {
      second.lock(); const unlocking = second.unlock(password); second.lock();
      await rejects(() => unlocking, /cancelado/);
      assert(!second.isUnlocked, 'O desbloqueio reabriu um cofre já bloqueado.');
      await rejects(() => second.list(), /bloqueado/);
    });
    await check('Lock após início assíncrono cancela o resultado do desbloqueio', async () => {
      const unlocking = second.unlock(password); await Promise.resolve(); second.lock();
      await rejects(() => unlocking, /cancelado/);
      assert(!second.isUnlocked, 'Um resultado assíncrono tardio reabriu o cofre.');
    });
    await check('Estado bloqueado rejeita leitura e mutação', async () => {
      first.lock();
      await rejects(() => first.list(), /bloqueado/);
      await rejects(() => first.save(tx(8)), /bloqueado/);
      await rejects(() => first.exportBackup(), /bloqueado/);
    });
    return { passed: checks.length, total: checks.length, checks };
  } catch (error) {
    error.browserChecks = { passed: checks.length, checks };
    throw error;
  } finally { first.lock(); second?.lock(); }
}
