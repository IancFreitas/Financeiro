import { validateTransactions, validateTransaction, MAX_FILE_BYTES, MAX_PLAINTEXT_BYTES } from './core.js';

const DB_NAME = 'financeiro-private-v1';
const STORE = 'vault';
const RECORD = 'primary';
const ITERATIONS = 600_000;
const encoder = new TextEncoder();
const decoder = new TextDecoder('utf-8', { fatal: true });
const fail = message => { throw new Error(message); };
const clone = value => structuredClone(value);
const CONFLICT = 'O cofre mudou em outra janela. Bloqueie e desbloqueie para carregar a versão atual antes de tentar novamente.';

function passwordBytes(password) {
  if (typeof password !== 'string' || [...password].length < 12) fail('Use uma senha com pelo menos 12 caracteres.');
  const bytes = encoder.encode(password);
  if (bytes.byteLength > 1024) fail('A senha excede o limite de 1024 bytes.');
  return bytes;
}

function toBase64(bytes) {
  let binary = '';
  for (let index = 0; index < bytes.length; index += 8192) binary += String.fromCharCode(...bytes.subarray(index, index + 8192));
  return btoa(binary);
}

function fromBase64(value, exactLength, maxLength) {
  if (typeof value !== 'string' || !value.length || value.length % 4 || value.length > Math.ceil(maxLength / 3) * 4 || !/^[A-Za-z0-9+/]*={0,2}$/.test(value)) fail('Arquivo criptografado inválido.');
  let binary;
  try { binary = atob(value); } catch { fail('Arquivo criptografado inválido.'); }
  const bytes = Uint8Array.from(binary, char => char.charCodeAt(0));
  if ((exactLength !== undefined && bytes.length !== exactLength) || bytes.length > maxLength || toBase64(bytes) !== value) fail('Arquivo criptografado inválido.');
  return bytes;
}

function header(envelope) {
  return {
    kind: envelope.kind, version: envelope.version, algorithm: envelope.algorithm,
    kdf: envelope.kdf, iterations: envelope.iterations, salt: envelope.salt,
    iv: envelope.iv, revision: envelope.revision,
  };
}

function inspectEnvelope(value) {
  let envelope = value;
  if (typeof value === 'string') {
    if (encoder.encode(value).length > MAX_FILE_BYTES) fail('O backup excede 20 MiB.');
    try { envelope = JSON.parse(value); } catch { fail('O backup não contém JSON válido.'); }
  }
  const keys = ['kind', 'version', 'algorithm', 'kdf', 'iterations', 'salt', 'iv', 'revision', 'ciphertext'];
  if (!envelope || typeof envelope !== 'object' || Array.isArray(envelope) || Object.keys(envelope).length !== keys.length || keys.some(key => !Object.hasOwn(envelope, key))) fail('Formato do backup inválido.');
  if (envelope.kind !== 'financeiro-vault' || envelope.version !== 1 || envelope.algorithm !== 'AES-256-GCM' || envelope.kdf !== 'PBKDF2-SHA256' || envelope.iterations !== ITERATIONS || !Number.isSafeInteger(envelope.revision) || envelope.revision < 1) fail('Versão ou parâmetros criptográficos não suportados.');
  const salt = fromBase64(envelope.salt, 16, 16);
  const iv = fromBase64(envelope.iv, 12, 12);
  const ciphertext = fromBase64(envelope.ciphertext, undefined, MAX_PLAINTEXT_BYTES + 16);
  if (ciphertext.length < 16) fail('Arquivo criptografado incompleto.');
  // Copy only validated public fields, in a stable order for authenticated data.
  return { envelope: { ...header(envelope), ciphertext: envelope.ciphertext }, salt, iv, ciphertext };
}

async function deriveKey(password, salt) {
  const bytes = passwordBytes(password);
  try {
    const material = await crypto.subtle.importKey('raw', bytes, 'PBKDF2', false, ['deriveKey']);
    return await crypto.subtle.deriveKey({ name: 'PBKDF2', salt, iterations: ITERATIONS, hash: 'SHA-256' }, material, { name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
  } finally { bytes.fill(0); }
}

async function encryptWithKey(transactions, key, salt, revision) {
  const normalized = validateTransactions(transactions);
  const plaintext = encoder.encode(JSON.stringify({ schema: 1, transactions: normalized }));
  const envelope = {
    kind: 'financeiro-vault', version: 1, algorithm: 'AES-256-GCM',
    kdf: 'PBKDF2-SHA256', iterations: ITERATIONS,
    salt: toBase64(salt), iv: toBase64(crypto.getRandomValues(new Uint8Array(12))), revision,
  };
  try {
    const ciphertext = await crypto.subtle.encrypt({ name: 'AES-GCM', iv: fromBase64(envelope.iv, 12, 12), additionalData: encoder.encode(JSON.stringify(header(envelope))), tagLength: 128 }, key, plaintext);
    const result = { ...envelope, ciphertext: toBase64(new Uint8Array(ciphertext)) };
    if (encoder.encode(JSON.stringify(result)).length > MAX_FILE_BYTES) fail('O backup excede 20 MiB.');
    return result;
  } finally { plaintext.fill(0); }
}

async function decryptWithKey(parts, key) {
  let plaintext;
  try {
    plaintext = new Uint8Array(await crypto.subtle.decrypt({ name: 'AES-GCM', iv: parts.iv, additionalData: encoder.encode(JSON.stringify(header(parts.envelope))), tagLength: 128 }, key, parts.ciphertext));
  } catch { fail('Senha incorreta ou arquivo criptografado alterado.'); }
  try {
    if (plaintext.length > MAX_PLAINTEXT_BYTES) fail('Os dados ultrapassam o limite de 14 MiB.');
    let state;
    try { state = JSON.parse(decoder.decode(plaintext)); } catch { fail('O conteúdo do cofre é inválido.'); }
    if (!state || typeof state !== 'object' || Array.isArray(state) || state.schema !== 1 || Object.keys(state).length !== 2 || !Object.hasOwn(state, 'transactions')) fail('Versão dos dados não suportada.');
    return validateTransactions(state.transactions);
  } finally { plaintext.fill(0); }
}

/** Testable encrypted format helpers; neither accesses IndexedDB nor retains passwords. */
export async function encryptPayload(transactions, password) {
  const normalized = validateTransactions(transactions);
  passwordBytes(password).fill(0);
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const key = await deriveKey(password, salt);
  return encryptWithKey(normalized, key, salt, 1);
}

export async function decryptPayload(value, password) {
  const parts = inspectEnvelope(value); // Validate work factor and lengths before deriving a key.
  const key = await deriveKey(password, parts.salt);
  return decryptWithKey(parts, key);
}

function transactionResult(db, mode, operation) {
  return new Promise((resolve, reject) => {
    let transaction;
    try { transaction = db.transaction(STORE, mode); } catch (error) { reject(error); return; }
    let result; let operationError;
    transaction.oncomplete = () => resolve(result);
    transaction.onabort = () => reject(operationError || transaction.error || new Error('A operação no armazenamento foi interrompida.'));
    transaction.onerror = () => { /* onabort reports the transaction failure. */ };
    try {
      operation(transaction.objectStore(STORE), value => { result = value; }, error => { operationError = error; transaction.abort(); });
    } catch (error) { operationError = error; transaction.abort(); }
  });
}

export class Vault {
  #db;
  #key = null;
  #salt = null;
  #transactions = null;
  #envelope = null;
  #epoch = 0;
  #queue = Promise.resolve();

  constructor(db) { this.#db = db; }

  static async open(databaseName = DB_NAME) {
    if (typeof databaseName !== 'string' || !/^[A-Za-z0-9._-]{1,128}$/.test(databaseName)) fail('Nome do armazenamento inválido.');
    if (!globalThis.indexedDB) fail('Este navegador não oferece IndexedDB. O cofre não pode ser aberto.');
    const db = await new Promise((resolve, reject) => {
      const request = indexedDB.open(databaseName, 1);
      request.onupgradeneeded = () => { request.result.createObjectStore(STORE); };
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error || new Error('Não foi possível abrir o armazenamento.'));
      request.onblocked = () => reject(new Error('Feche outras janelas antigas do app para abrir o armazenamento.'));
    });
    const vault = new Vault(db);
    db.onversionchange = () => { vault.lock(); db.close(); };
    return vault;
  }

  get isUnlocked() { return this.#key !== null; }

  #read() {
    return transactionResult(this.#db, 'readonly', (store, done) => {
      const request = store.get(RECORD); request.onsuccess = () => done(request.result);
    });
  }

  async exists() { return (await this.#read()) !== undefined; }

  #enqueue(operation) {
    const promise = this.#queue.then(operation);
    this.#queue = promise.catch(() => {});
    return promise;
  }

  #assertUnlocked(epoch = this.#epoch) {
    if (!this.isUnlocked || epoch !== this.#epoch) fail('O cofre está bloqueado. Desbloqueie para continuar.');
  }

  #assertCurrent(latest) {
    if (!latest || latest.revision !== this.#envelope.revision || latest.ciphertext !== this.#envelope.ciphertext || latest.salt !== this.#envelope.salt) fail(CONFLICT);
  }

  async create(password) {
    this.lock(); const epoch = this.#epoch;
    return this.#enqueue(async () => {
      if (epoch !== this.#epoch) fail('A criação do cofre foi cancelada.');
      passwordBytes(password).fill(0);
      const salt = crypto.getRandomValues(new Uint8Array(16));
      const key = await deriveKey(password, salt);
      const envelope = await encryptWithKey([], key, salt, 1);
      if (epoch !== this.#epoch) fail('A abertura do cofre foi cancelada.');
      await transactionResult(this.#db, 'readwrite', (store, done, abort) => {
        const request = store.get(RECORD);
        request.onsuccess = () => {
          if (request.result !== undefined) { abort(new Error('Já existe um cofre neste navegador.')); return; }
          store.add(envelope, RECORD); done();
        };
      });
      if (epoch !== this.#epoch) return;
      this.#key = key; this.#salt = salt; this.#transactions = []; this.#envelope = envelope;
    });
  }

  async unlock(password) {
    this.lock(); const epoch = this.#epoch;
    return this.#enqueue(async () => {
      if (epoch !== this.#epoch) fail('O desbloqueio foi cancelado.');
      const value = await this.#read();
      if (value === undefined) fail('Nenhum cofre foi criado neste navegador.');
      const parts = inspectEnvelope(value);
      const key = await deriveKey(password, parts.salt);
      const transactions = await decryptWithKey(parts, key);
      if (epoch !== this.#epoch) fail('O desbloqueio foi cancelado.');
      this.#key = key; this.#salt = parts.salt; this.#transactions = transactions; this.#envelope = parts.envelope;
      return clone(transactions);
    });
  }

  async list() { this.#assertUnlocked(); return clone(this.#transactions); }

  async #write(next, epoch) {
    this.#assertUnlocked(epoch);
    const validated = validateTransactions(next);
    const expected = this.#envelope;
    if (expected.revision === Number.MAX_SAFE_INTEGER) fail('O limite de revisões do cofre foi alcançado.');
    const envelope = await encryptWithKey(validated, this.#key, this.#salt, expected.revision + 1);
    this.#assertUnlocked(epoch);
    await transactionResult(this.#db, 'readwrite', (store, done, abort) => {
      const request = store.get(RECORD);
      request.onsuccess = () => {
        try { this.#assertUnlocked(epoch); this.#assertCurrent(request.result); }
        catch (error) { abort(error); return; }
        store.put(envelope, RECORD); done();
      };
    });
    if (epoch === this.#epoch) { this.#transactions = validated; this.#envelope = envelope; }
  }

  async save(input) {
    const tx = validateTransaction(input); const epoch = this.#epoch;
    return this.#enqueue(async () => {
      this.#assertUnlocked(epoch);
      const next = this.#transactions.map(item => ({ ...item }));
      const index = next.findIndex(item => item.id === tx.id);
      if (index === -1) next.push(tx); else next[index] = tx;
      await this.#write(next, epoch);
    });
  }

  async remove(id) {
    if (typeof id !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)) fail('UUID inválido.');
    const normalized = id.toLowerCase(); const epoch = this.#epoch;
    return this.#enqueue(async () => {
      this.#assertUnlocked(epoch);
      await this.#write(this.#transactions.filter(item => item.id !== normalized), epoch);
    });
  }

  async merge(input) {
    const incoming = validateTransactions(input); const epoch = this.#epoch;
    return this.#enqueue(async () => {
      this.#assertUnlocked(epoch);
      const ids = new Set(this.#transactions.map(tx => tx.id));
      const additions = incoming.filter(tx => !ids.has(tx.id));
      // Even a no-op checks the current revision, so stale previews fail visibly.
      if (additions.length) await this.#write([...this.#transactions, ...additions], epoch);
      else { const latest = await this.#read(); this.#assertUnlocked(epoch); this.#assertCurrent(latest); }
      return { added: additions.length, skipped: incoming.length - additions.length };
    });
  }

  async exportBackup() {
    const epoch = this.#epoch;
    return this.#enqueue(async () => {
      this.#assertUnlocked(epoch);
      const latest = await this.#read(); this.#assertUnlocked(epoch); this.#assertCurrent(latest);
      const envelope = await encryptWithKey(this.#transactions, this.#key, this.#salt, latest.revision);
      this.#assertUnlocked(epoch);
      return JSON.stringify(envelope);
    });
  }

  async inspectBackup(text, password) { return decryptPayload(text, password); }

  lock() {
    this.#epoch++;
    this.#key = null;
    if (this.#salt) this.#salt.fill(0);
    this.#salt = null; this.#transactions = null; this.#envelope = null;
  }
}
