/** Financial values are positive integer cents. No network or implicit currency conversion. */
export const MAX_RECORDS = 20_000;
export const MAX_PLAINTEXT_BYTES = 14 * 1024 * 1024;
export const MAX_FILE_BYTES = 20 * 1024 * 1024;
const encoder = new TextEncoder();
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const kinds = new Set(['income', 'expense', 'transfer']);
const sources = new Set(['manual', 'shortcut', 'imported']);
const fail = message => { throw new Error(message); };
const utf8Size = value => encoder.encode(value).byteLength;

export function parseMoney(text) {
  if (typeof text !== 'string') fail('Informe o valor em reais como texto.');
  const value = text.trim();
  if (value.length > 32 || !/^(?:[0-9]+|[1-9][0-9]{0,2}(?:\.[0-9]{3})+)(?:,[0-9]{1,2})?$/.test(value)) {
    fail('Valor inválido. Use 123,45 ou 1.234,56, sem sinal ou símbolo.');
  }
  const [whole, fraction = ''] = value.replaceAll('.', '').split(',');
  const cents = BigInt(whole) * 100n + BigInt(fraction.padEnd(2, '0') || '0');
  if (cents <= 0n || cents > BigInt(Number.MAX_SAFE_INTEGER)) fail('O valor deve ser positivo e estar dentro do limite permitido.');
  return Number(cents);
}

export function formatMoney(value) {
  if (typeof value === 'number' && !Number.isSafeInteger(value)) fail('Valor monetário inválido.');
  if (typeof value !== 'number' && typeof value !== 'bigint') fail('Valor monetário inválido.');
  const cents = BigInt(value);
  const absolute = cents < 0n ? -cents : cents;
  return `${cents < 0n ? '-' : ''}R$ ${(absolute / 100n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, '.')},${(absolute % 100n).toString().padStart(2, '0')}`;
}

function field(value, label, max, fallback = '') {
  if (value === undefined) value = fallback;
  if (typeof value !== 'string') fail(`${label} deve ser texto.`);
  const normalized = value.trim();
  if (normalized.length > max) fail(`${label} excede ${max} caracteres.`);
  return normalized;
}

function normalizedDate(value) {
  if (typeof value !== 'string') fail('A data deve incluir horário e fuso.');
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,3}))?)?(Z|([+-])(\d{2}):(\d{2}))$/.exec(value);
  if (!match) fail('Data inválida. Use data ISO com horário e fuso, por exemplo 2026-10-31T12:00:00-03:00.');
  const [, year, month, day, hour, minute, second = '0', , , , offsetHour = '0', offsetMinute = '0'] = match;
  const leap = +year % 4 === 0 && (+year % 100 !== 0 || +year % 400 === 0);
  const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (+month < 1 || +month > 12 || +day < 1 || +day > days[+month - 1] || +hour > 23 || +minute > 59 || +second > 59 || +offsetHour > 23 || +offsetMinute > 59 || !Number.isFinite(Date.parse(value))) fail('Data ou horário inválido.');
  return new Date(value).toISOString();
}

export function validateTransaction(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) fail('Lançamento inválido.');
  if (typeof input.id !== 'string' || !UUID.test(input.id)) fail('O identificador deve ser um UUID válido.');
  if (!Number.isSafeInteger(input.amountMinor) || input.amountMinor <= 0) fail('O valor em centavos deve ser um inteiro positivo seguro.');
  if (input.currency !== 'BRL') fail('Somente lançamentos em BRL são aceitos.');
  if (!kinds.has(input.kind)) fail('Tipo inválido: use income, expense ou transfer.');
  if (!sources.has(input.source)) fail('Origem do lançamento inválida.');
  const merchant = field(input.merchant, 'Estabelecimento', 200);
  if (!merchant) fail('Informe o estabelecimento ou descrição.');
  return {
    id: input.id.toLowerCase(), amountMinor: input.amountMinor, currency: 'BRL', merchant,
    date: normalizedDate(input.date), kind: input.kind,
    category: field(input.category, 'Categoria', 100, 'Outros'),
    account: field(input.account, 'Conta', 100, 'Principal'), source: input.source,
    note: field(input.note, 'Observação', 4000),
  };
}

export function validateTransactions(input) {
  if (!Array.isArray(input) || input.length > MAX_RECORDS) fail(`O arquivo deve conter até ${MAX_RECORDS} lançamentos.`);
  const ids = new Set();
  const result = input.map(item => {
    const tx = validateTransaction(item);
    if (ids.has(tx.id)) fail('Há UUIDs duplicados no arquivo.');
    ids.add(tx.id);
    return tx;
  });
  const serialized = JSON.stringify({ schema: 1, transactions: result });
  if (utf8Size(serialized) > MAX_PLAINTEXT_BYTES) fail('Os dados ultrapassam o limite de 14 MiB.');
  return result;
}

export function summarize(transactions, month = (() => { const now = new Date(); return `${String(now.getFullYear()).padStart(4, '0')}-${String(now.getMonth() + 1).padStart(2, '0')}`; })()) {
  if (month !== undefined && !/^\d{4}-(0[1-9]|1[0-2])$/.test(month)) fail('Mês inválido.');
  let income = 0n, expense = 0n, count = 0;
  for (const input of transactions) {
    const tx = validateTransaction(input);
    const date = new Date(tx.date);
    const localMonth = `${String(date.getFullYear()).padStart(4, '0')}-${String(date.getMonth() + 1).padStart(2, '0')}`;
    if (month && localMonth !== month) continue;
    count++;
    if (tx.kind === 'income') income += BigInt(tx.amountMinor);
    if (tx.kind === 'expense') expense += BigInt(tx.amountMinor);
  }
  return { income, expense, flow: income - expense, count };
}

function checkText(text) {
  if (typeof text !== 'string' || utf8Size(text) > MAX_FILE_BYTES) fail('Arquivo inválido ou maior que 20 MiB.');
  return text.replace(/^\uFEFF/, '');
}

function csvRows(text) {
  // Choose the separator from the first record, ignoring quoted fields.
  let delimiter = ',', quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (c === '"') { if (quoted && text[i + 1] === '"') i++; else quoted = !quoted; }
    if (!quoted && c === ';') { delimiter = ';'; break; }
    if (!quoted && (c === '\r' || c === '\n')) break;
  }
  const rows = []; let row = [], value = '', state = 'start';
  const pushRow = () => {
    row.push(value);
    if (row.some(cell => cell.trim() !== '')) rows.push(row);
    if (rows.length > MAX_RECORDS + 1) fail('O CSV ultrapassa o limite de lançamentos.');
    row = []; value = ''; state = 'start';
  };
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (state === 'quoted') {
      if (c === '"') { if (text[i + 1] === '"') { value += '"'; i++; } else state = 'closed'; }
      else if (c === '\r') { value += '\n'; if (text[i + 1] === '\n') i++; }
      else value += c;
      continue;
    }
    if (c === delimiter) { row.push(value); value = ''; state = 'start'; continue; }
    if (c === '\r' || c === '\n') { pushRow(); if (c === '\r' && text[i + 1] === '\n') i++; continue; }
    if (state === 'closed') fail('CSV inválido: há texto após o fechamento das aspas.');
    if (c === '"') { if (state !== 'start') fail('CSV inválido: aspas em campo sem escape.'); state = 'quoted'; }
    else { value += c; state = 'plain'; }
  }
  if (state === 'quoted') fail('CSV inválido: campo com aspas não foi fechado.');
  if (row.length || value.length || state === 'closed') pushRow();
  return rows;
}

async function stableUUID(canonical, occurrence) {
  const bytes = new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(`financeiro-csv-v1\n${canonical}\n${occurrence}`)));
  bytes[6] = (bytes[6] & 0x0f) | 0x50; bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = [...bytes.slice(0, 16)].map(byte => byte.toString(16).padStart(2, '0')).join('');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

export async function parseCSV(text) {
  const rows = csvRows(checkText(text));
  if (!rows.length) fail('CSV vazio.');
  const headers = rows.shift().map(cell => cell.trim().toLowerCase());
  const allowed = new Set(['id', 'date', 'merchant', 'amount', 'kind', 'category', 'account', 'currency', 'note']);
  if (new Set(headers).size !== headers.length || headers.some(header => !allowed.has(header)) || ['date', 'merchant', 'amount', 'kind'].some(header => !headers.includes(header))) fail('Cabeçalho CSV inválido. Exigidos: date, merchant, amount e kind.');
  const occurrences = new Map(); const result = [];
  for (let index = 0; index < rows.length; index++) {
    const row = rows[index];
    if (row.length !== headers.length) fail(`A linha ${index + 2} tem quantidade incorreta de campos.`);
    const item = Object.fromEntries(headers.map((header, i) => [header, row[i]]));
    const provisional = validateTransaction({ ...item, id: item.id?.trim() || '00000000-0000-4000-8000-000000000000', amountMinor: parseMoney(item.amount), currency: item.currency?.trim() || 'BRL', source: 'imported' });
    if (!item.id?.trim()) {
      const { id, ...identity } = provisional;
      const canonical = JSON.stringify(identity); const occurrence = (occurrences.get(canonical) || 0) + 1;
      occurrences.set(canonical, occurrence); provisional.id = await stableUUID(canonical, occurrence);
    }
    result.push(provisional);
  }
  return validateTransactions(result);
}

export async function parseCapture(text) {
  let input;
  try { input = JSON.parse(checkText(text)); } catch (error) { fail(error instanceof SyntaxError ? 'O Atalho deve fornecer JSON com campos explícitos.' : error.message); }
  if (input && !Array.isArray(input) && Object.hasOwn(input, 'transactions')) {
    if (Object.keys(input).some(key => key !== 'transactions')) fail('Envelope do Atalho inválido.');
    input = input.transactions;
  }
  const rows = Array.isArray(input) ? input : [input];
  if (rows.length > MAX_RECORDS) fail('O Atalho ultrapassa o limite de lançamentos.');
  const now = new Date().toISOString();
  const allowed = new Set(['id', 'amount', 'amountMinor', 'currency', 'merchant', 'kind', 'date', 'account', 'category', 'note']);
  return validateTransactions(rows.map(item => {
    if (!item || typeof item !== 'object' || Array.isArray(item) || Object.keys(item).some(key => !allowed.has(key))) fail('O Atalho deve fornecer campos estruturados, sem texto de notificação.');
    if (Object.hasOwn(item, 'amount') === Object.hasOwn(item, 'amountMinor')) fail('Informe apenas amount em reais ou amountMinor em centavos.');
    const missingDate = item.date === undefined;
    let note = field(item.note, 'Observação', 4000);
    if (missingDate) note += `${note ? '\n' : ''}Atalho sem data original; usada a data de recebimento.`;
    return { ...item, id: item.id || crypto.randomUUID(), amountMinor: Object.hasOwn(item, 'amount') ? parseMoney(item.amount) : item.amountMinor, currency: item.currency ?? 'BRL', date: missingDate ? now : item.date, source: 'shortcut', note };
  }));
}
