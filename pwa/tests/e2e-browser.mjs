// Teste de navegador (Playwright + Chromium). Usa apenas dados FICTÍCIOS.
// Execução: npm run test:browser  (requer o pacote "playwright" instalado fora do package.json).
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(import.meta.url);
function loadPlaywright() {
  try { return require('playwright'); } catch {}
  try {
    const globalRoot = execFileSync('npm', ['root', '-g'], { encoding: 'utf8' }).trim();
    return createRequire(path.join(globalRoot, 'noop.js'))('playwright');
  } catch {}
  console.error('Playwright não encontrado. Instale com: npm install --no-save --prefix /tmp/pw playwright@1.63.0 (ou globalmente).');
  process.exit(2);
}
const { chromium, devices } = loadPlaywright();

const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.webmanifest': 'application/manifest+json', '.png': 'image/png', '.svg': 'image/svg+xml', '.json': 'application/json' };
const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  let file = path.normalize(path.join(ROOT, decodeURIComponent(url.pathname)));
  if (file !== ROOT && !file.startsWith(ROOT + path.sep)) { res.writeHead(403).end(); return; }
  if (url.pathname.endsWith('/')) file = path.join(file, 'index.html');
  fs.readFile(file, (error, data) => {
    if (error) { res.writeHead(404).end('não encontrado'); return; }
    res.writeHead(200, { 'content-type': MIME[path.extname(file)] || 'application/octet-stream' });
    res.end(data);
  });
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const BASE = `http://localhost:${server.address().port}/`;
// "localhost" é contexto seguro; o servidor escuta em 127.0.0.1 e localhost resolve para ele.

const PASSWORD = 'frase-ficticia-de-teste-123';
const WRONG = 'senha-errada-ficticia-999';
const SECRET = 'Mercado teste';
const CAPTURE_ID = '3f2b8c1e-5a47-4d0e-9b6a-1c2d3e4f5a6b';
const results = [];
const problems = [];
const ok = name => { results.push(name); console.log(`  ok  ${name}`); };
function assert(cond, message) { if (!cond) throw new Error(message); }

function watch(page, label) {
  page.on('pageerror', error => problems.push(`[${label}] pageerror: ${error.message}`));
  page.on('console', msg => { if (msg.type() === 'error') problems.push(`[${label}] console.error: ${msg.text()}`); });
}
function localInput(date = new Date()) {
  const pad = n => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}
async function createVault(page, password) {
  await page.goto(BASE, { waitUntil: 'load' });
  await page.waitForSelector('#gate-form', { state: 'visible' });
  await page.fill('#password', password);
  await page.fill('#password-confirm', password);
  await page.click('#gate-submit');
  await page.waitForSelector('#app', { state: 'visible' });
}
async function addRecord(page, { kind, amount, merchant, category, account }) {
  await page.locator('.new-record:visible').first().click();
  await page.waitForSelector('#record-dialog[open]');
  await page.selectOption('#record-kind', kind);
  await page.fill('#record-amount', amount);
  await page.fill('#record-date', localInput());
  await page.fill('#record-merchant', merchant);
  await page.fill('#record-category', category);
  await page.fill('#record-account', account);
  await page.click('#record-form button[type="submit"]');
  await page.waitForSelector('#record-dialog:not([open])', { state: 'attached' });
}
async function dumpIndexedDB(page) {
  return page.evaluate(async () => {
    const replacer = (_k, v) => {
      if (v instanceof ArrayBuffer) v = new Uint8Array(v);
      if (ArrayBuffer.isView(v)) return Array.from(new Uint8Array(v.buffer, v.byteOffset, v.byteLength)).map(c => String.fromCharCode(c)).join('');
      return v;
    };
    const dbs = (await indexedDB.databases()).map(d => d.name);
    const out = {};
    for (const name of dbs) {
      const db = await new Promise((res, rej) => { const r = indexedDB.open(name); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });
      out[name] = {};
      for (const store of Array.from(db.objectStoreNames)) {
        const tx = db.transaction(store, 'readonly');
        const keys = await new Promise((res, rej) => { const r = tx.objectStore(store).getAllKeys(); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });
        const values = await new Promise((res, rej) => { const r = tx.objectStore(store).getAll(); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });
        out[name][store] = JSON.stringify({ keys, values }, replacer);
      }
      db.close();
    }
    return out;
  });
}
async function unlock(page, password) {
  await page.waitForSelector('#gate-form', { state: 'visible' });
  await page.fill('#password', password);
  await page.click('#gate-submit');
}
async function text(page, selector) { return (await page.textContent(selector)).trim(); }

const browser = await chromium.launch();
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'entrecontas-e2e-'));
let failure = null;
try {
  // a) testes sintéticos de IndexedDB
  console.log('Testes de navegador (browser-checks.html)');
  {
    const ctx = await browser.newContext();
    const page = await ctx.newPage(); watch(page, 'checks');
    await page.goto(`${BASE}tests/browser-checks.html`);
    await page.click('#run');
    await page.waitForFunction(() => /aprovados\.|FALHOU/.test(document.querySelector('#status').textContent), null, { timeout: 120000 });
    const status = await text(page, '#status');
    const m = status.match(/^(\d+)\/(\d+) testes de navegador aprovados\.$/);
    assert(m, `Testes de navegador falharam: ${status}`);
    assert(Number(m[2]) > 0 && m[1] === m[2], `Esperado passed===total>0, obtido: ${status}`);
    ok(`browser-checks: ${m[1]}/${m[2]} aprovados`);
    await ctx.close();
  }

  // b) roteiro de aceite em viewport de iPhone
  console.log('Roteiro de aceite (iPhone 13)');
  const ctx = await browser.newContext({ ...devices['iPhone 13'] });
  const page = await ctx.newPage(); watch(page, 'app');
  await createVault(page, PASSWORD);
  ok('cofre criado e app visível');

  await addRecord(page, { kind: 'income', amount: '100,00', merchant: 'Salário teste', category: 'Trabalho', account: 'Conta teste' });
  await addRecord(page, { kind: 'expense', amount: '25,50', merchant: SECRET, category: 'Alimentação', account: 'Conta teste' });
  await addRecord(page, { kind: 'transfer', amount: '10,00', merchant: 'Transferência teste', category: 'Outros', account: 'Conta teste' });
  await page.waitForFunction(() => document.querySelector('#total-flow').textContent.includes('74,50'));
  assert((await text(page, '#total-flow')).includes('74,50'), 'Fluxo deveria conter 74,50');
  ok('receita, despesa e transferência criadas; fluxo 74,50');

  const dump = await dumpIndexedDB(page);
  const stores = Object.entries(dump).flatMap(([db, s]) => Object.entries(s).map(([name, body]) => ({ db, name, body })));
  assert(stores.length > 0, 'Nenhum store do IndexedDB encontrado');
  for (const s of stores) assert(!s.body.includes(SECRET) && !s.body.includes('Salário teste'), `Texto em claro no IndexedDB (${s.db}/${s.name})`);
  ok(`IndexedDB sem texto em claro (${stores.length} stores verificados)`);

  await page.reload({ waitUntil: 'load' });
  await unlock(page, WRONG);
  await page.waitForSelector('#gate-error', { state: 'visible' });
  assert(await page.isHidden('#app'), 'App não deveria abrir com senha errada');
  ok('senha errada mostra #gate-error');
  await page.fill('#password', PASSWORD);
  await page.click('#gate-submit');
  await page.waitForSelector('#app', { state: 'visible' });
  await page.waitForFunction(() => document.querySelector('#total-flow').textContent.includes('74,50'));
  ok('reload + senha correta: fluxo 74,50');

  // captura (Cofre)
  const capture = JSON.stringify({ transactions: [{ id: CAPTURE_ID, amount: '4,50', merchant: 'Padaria teste', kind: 'expense', date: new Date().toISOString(), account: 'Conta teste', category: 'Alimentação' }] });
  async function submitCapture(expectEnabled) {
    await page.click('.tab[data-tab=vault]');
    await page.fill('#capture-text', capture);
    await page.click('#review-capture');
    await page.waitForSelector('#review-dialog[open]');
    const desc = await text(page, '#review-description');
    assert(await page.isEnabled('#confirm-import') === expectEnabled, `#confirm-import deveria estar ${expectEnabled ? 'habilitado' : 'desabilitado'} (${desc})`);
    if (expectEnabled) {
      assert(!/já exist/.test(desc), `Captura nova não deveria dizer que já existe: ${desc}`);
      await page.click('#confirm-import');
    } else {
      assert(/já existe no cofre; nada será adicionado/.test(desc), `Texto de captura repetida inesperado: ${desc}`);
      await page.click('#review-dialog .close-dialog');
    }
    await page.waitForSelector('#review-dialog:not([open])', { state: 'attached' });
  }
  await submitCapture(true);
  await submitCapture(false);
  await page.click('.tab[data-tab=records]');
  await page.waitForFunction(() => document.querySelector('#records-count').textContent.trim() === '4 registros');
  ok('captura revisada e importada; reenvio não duplica (4 registros)');

  // backup
  await page.click('.tab[data-tab=vault]');
  await page.click('#prepare-backup');
  await page.waitForSelector('#backup-ready', { state: 'visible' });
  const [download] = await Promise.all([page.waitForEvent('download'), page.click('#download-backup')]);
  const backupPath = path.join(tmp, 'backup.json');
  await download.saveAs(backupPath);
  const backupRaw = fs.readFileSync(backupPath, 'utf8');
  assert(backupRaw.length > 0, 'Backup vazio');
  for (const s of [SECRET, 'Salário teste', 'Padaria teste']) assert(!backupRaw.includes(s), `Backup contém texto em claro: ${s}`);
  ok('backup baixado e sem texto em claro');

  // service worker + offline
  await page.evaluate(() => navigator.serviceWorker.ready.then(() => true));
  await page.reload({ waitUntil: 'load' });
  await page.waitForFunction(() => !!navigator.serviceWorker.controller, null, { timeout: 15000 });
  await ctx.setOffline(true);
  await page.reload({ waitUntil: 'load' });
  await page.waitForSelector('#gate-form', { state: 'visible' });
  ok('offline com service worker: #gate-form visível após reload');
  await ctx.setOffline(false);
  await ctx.close();

  // restauração em contexto novo
  console.log('Restauração (contexto novo)');
  const ctx2 = await browser.newContext({ ...devices['iPhone 13'] });
  const page2 = await ctx2.newPage(); watch(page2, 'restore');
  await createVault(page2, PASSWORD);
  await page2.click('.tab[data-tab=records]');
  await page2.waitForFunction(() => !document.querySelector('#records-count').textContent.trim() || /^0 /.test(document.querySelector('#records-count').textContent.trim()));
  await page2.click('.tab[data-tab=vault]');
  await page2.setInputFiles('#backup-file', backupPath);
  await page2.waitForSelector('#restore-dialog[open]');
  await page2.fill('#restore-password', WRONG);
  await page2.click('#restore-form button[type="submit"]');
  await page2.waitForSelector('#restore-error', { state: 'visible' });
  assert(await page2.locator('#review-dialog[open]').count() === 0, 'Revisão não deveria abrir com senha errada');
  assert(await page2.locator('#restore-dialog[open]').count() === 1, 'Diálogo de restore deveria continuar aberto');
  ok('senha errada no restore mostra #restore-error sem abrir revisão');
  await page2.fill('#restore-password', PASSWORD);
  await page2.click('#restore-form button[type="submit"]');
  await page2.waitForSelector('#review-dialog[open]');
  await page2.click('#confirm-import');
  await page2.waitForSelector('#review-dialog:not([open])', { state: 'attached' });
  await page2.click('.tab[data-tab=records]');
  await page2.waitForFunction(() => document.querySelector('#records-count').textContent.trim() === '4 registros');
  const list = await text(page2, '#records-list');
  for (const s of [SECRET, 'Salário teste', 'Padaria teste', 'Transferência teste']) assert(list.includes(s), `Registro restaurado ausente: ${s}`);
  await page2.click('.tab[data-tab=summary]');
  await page2.waitForFunction(() => document.querySelector('#total-flow').textContent.includes('70,00'));
  ok('restore: 4 registros restaurados, fluxo 70,00');
  await ctx2.close();
} catch (error) {
  failure = error;
} finally {
  await browser.close().catch(() => {});
  server.close();
  fs.rmSync(tmp, { recursive: true, force: true });
}

console.log(`\nResumo: ${results.length} verificações aprovadas`);
if (problems.length) { console.error('Erros de página/console:\n' + problems.map(p => '  - ' + p).join('\n')); }
if (failure) { console.error(`FALHOU: ${failure.message}`); process.exit(1); }
if (problems.length) process.exit(1);
