import test from 'node:test';
import assert from 'node:assert/strict';
import { parseMoney, formatMoney, validateTransaction, validateTransactions, summarize, parseCSV, parseCapture } from '../src/core.js';

const base = (overrides = {}) => ({ id: '4eb63678-8f71-414e-b8db-52f869a30574', amountMinor: 12345, currency: 'BRL', merchant: 'Loja fictícia', date: '2026-10-31T12:00:00-03:00', kind: 'expense', category: 'Outros', account: 'Principal', source: 'manual', note: '', ...overrides });

test('money uses exact integer cents and rejects ambiguous or unsafe values', () => {
  for (const [input, expected] of [['123', 12300], ['123,4', 12340], ['1.234,56', 123456], ['0,01', 1], ['90.071.992.547.409,91', Number.MAX_SAFE_INTEGER]]) assert.equal(parseMoney(input), expected);
  for (const input of ['0', '-1,00', '+1', '1.23', '1,234', '1,234.56', 'R$ 12,00', '1e3', '', '90.071.992.547.409,92', '1.0000,01', '0.123,45']) assert.throws(() => parseMoney(input), undefined, input);
  assert.throws(() => parseMoney(123));
  assert.equal(formatMoney(123456n), 'R$ 1.234,56');
  assert.equal(formatMoney(-123n), '-R$ 1,23');
  assert.equal(formatMoney(18014398509481982n), 'R$ 180.143.985.094.819,82');
  assert.throws(() => formatMoney(1.2));
});

test('transactions are copied, normalized and strictly validated', () => {
  const original = base({ id: base().id.toUpperCase(), merchant: '  Mercado fictício  ', hidden: 'omitido' });
  const normalized = validateTransaction(original);
  assert.equal(normalized.id, original.id.toLowerCase());
  assert.equal(normalized.date, '2026-10-31T15:00:00.000Z');
  assert.equal(normalized.merchant, 'Mercado fictício');
  assert.equal(Object.hasOwn(normalized, 'hidden'), false);
  normalized.merchant = 'Outro'; assert.equal(original.merchant, '  Mercado fictício  ');
  for (const changes of [{ amountMinor: 0 }, { amountMinor: 1.1 }, { amountMinor: Number.MAX_SAFE_INTEGER + 1 }, { currency: 'USD' }, { id: '123' }, { kind: 'refund' }, { source: 'bank' }, { merchant: '' }, { merchant: 'x'.repeat(201) }, { account: 'x'.repeat(101) }, { note: 'x'.repeat(4001) }, { date: '2026-02-29T10:00:00Z' }, { date: '2026-01-01' }, { date: '2026-01-01T24:00:00Z' }]) assert.throws(() => validateTransaction(base(changes)), undefined, JSON.stringify(changes));
  assert.equal(validateTransaction(base({ date: '2024-02-29T00:00:00Z' })).date, '2024-02-29T00:00:00.000Z');
});

test('summaries use BigInt, count transfers without adding them, and use local calendar month', () => {
  const date = '2026-11-01T01:00:00Z';
  const d = new Date(date); const month = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
  const txs = [base({ date, kind: 'income', amountMinor: Number.MAX_SAFE_INTEGER }), base({ date, kind: 'income', amountMinor: Number.MAX_SAFE_INTEGER }), base({ date, kind: 'expense', amountMinor: 100 }), base({ date, kind: 'transfer', amountMinor: 700 })];
  assert.deepEqual(summarize(txs, month), { income: 18014398509481982n, expense: 100n, flow: 18014398509481882n, count: 4 });
  assert.equal(summarize(txs, '2025-01').count, 0);
  assert.throws(() => summarize(txs, '2026-13'));
});

test('CSV handles BOM, CRLF, escaped quotes and multiline notes atomically', async () => {
  const csv = '\uFEFFdate;merchant;amount;kind;note\r\n2026-10-31T12:00:00-03:00;"Loja; \"\"fictícia\"\"";1.234,56;expense;"linha 1\r\nlinha 2"\r\n';
  const txs = await parseCSV(csv);
  assert.equal(txs.length, 1); assert.equal(txs[0].merchant, 'Loja; "fictícia"');
  assert.equal(txs[0].note, 'linha 1\nlinha 2'); assert.equal(txs[0].amountMinor, 123456);
  assert.equal(txs[0].source, 'imported'); assert.deepEqual(await parseCSV(csv), txs);
  const commas = 'date,merchant,amount,kind\n2026-10-31T12:00:00Z,Loja,"123,45",expense';
  assert.equal((await parseCSV(commas))[0].amountMinor, 12345);
  await assert.rejects(parseCSV(csv + '2026-10-31T12:00:00Z;Outra;inválido;expense;nota'));
});

test('CSV derives stable distinct occurrence IDs, honors explicit IDs and rejects repeated UUIDs', async () => {
  const header = 'date;merchant;amount;kind\n'; const row = '2026-10-31T12:00:00Z;Loja;1,00;expense';
  const rows = await parseCSV(header + row + '\n' + row);
  assert.notEqual(rows[0].id, rows[1].id); assert.deepEqual(await parseCSV(header + row + '\n' + row), rows);
  const explicit = `id;${header}${base().id};${row}\n${base().id};${row}`;
  await assert.rejects(parseCSV(explicit), /duplicados/);
});

test('CSV rejects malformed syntax, columns, dates and currencies', async () => {
  for (const csv of ['', 'date;merchant;amount\n2026-01-01;Loja;1', 'date;merchant;amount;kind\n2026-10-31T12:00:00Z;"Loja;1,00;expense', 'date;merchant;amount;kind\n2026-10-31T12:00:00Z;"Loja"x;1,00;expense', 'date;merchant;amount;kind\n2026-10-31T12:00:00Z;Lo"ja;1,00;expense', 'date;merchant;amount;kind\n2026-10-31T12:00:00Z;Loja;1,00;expense;extra', 'date;merchant;amount;kind;currency\n2026-10-31T12:00:00Z;Loja;1,00;expense;USD']) await assert.rejects(parseCSV(csv), undefined, csv);
});

test('shortcut requires explicit structured fields and records missing date', async () => {
  const payload = { amount: '25,90', merchant: 'Padaria fictícia', kind: 'expense' };
  const [tx] = await parseCapture(JSON.stringify(payload));
  assert.equal(tx.amountMinor, 2590); assert.equal(tx.source, 'shortcut');
  assert.match(tx.note, /sem data original/); assert.ok(Number.isFinite(Date.parse(tx.date)));
  const [explicit] = await parseCapture(JSON.stringify({ transactions: [{ ...payload, id: base().id, date: base().date, note: 'Exemplo' }] }));
  assert.equal(explicit.id, base().id); assert.equal(explicit.note, 'Exemplo');
  assert.equal((await parseCapture(JSON.stringify({ ...payload, amount: undefined, amountMinor: 100 })))[0].amountMinor, 100);
  for (const input of ['Compra aprovada R$ 25,90', '{}', 'null', JSON.stringify({ notification: 'Compra fictícia' }), JSON.stringify({ ...payload, kind: undefined }), JSON.stringify({ ...payload, amountMinor: 100 }), JSON.stringify({ ...payload, amount: 1.23 }), JSON.stringify([ { ...payload, id: base().id }, { ...payload, id: base().id } ])]) await assert.rejects(parseCapture(input));
});

test('record and plaintext capacity are enforced before acceptance', () => {
  assert.throws(() => validateTransactions(Array(20_001).fill(base())), /20000/);
  assert.throws(() => validateTransactions([base(), base()]), /duplicados/);
  const large = Array.from({ length: 3600 }, (_, index) => base({ id: `00000000-0000-4000-8000-${String(index).padStart(12, '0')}`, note: 'x'.repeat(4000) }));
  assert.throws(() => validateTransactions(large), /14 MiB/);
});
