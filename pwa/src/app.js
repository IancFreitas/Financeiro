import { parseMoney, formatMoney, validateTransaction, summarize, parseCSV, parseCapture } from './core.js';
import { Vault } from './vault.js';
import { readIntakeFragment } from './intake.js';

const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];
const escapeHTML = (value) => String(value ?? '').replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
const kinds = { income: 'Entrada', expense: 'Saída', transfer: 'Transferência' };
const sources = { manual: 'Registro manual', shortcut: 'Captura pelo Atalhos', imported: 'Importação' };
const dateFormatter = new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: 'short' });
const dateTimeFormatter = new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' });
let vault;
let transactions = [];
let isCreating = false;
let reviewItems = [];
let backupText = '';
let preparedFile = null;
let preparedURL = null;
let editingSource = 'manual';
let editingCurrency = 'BRL';
let editingOriginalDate = null;
let editingDisplayDate = null;
let pending = Promise.resolve();
let locking = false;
let toastTimer;
let incomingCapture = null;
let intakeError = null;
let sessionEpoch = 0;
try { incomingCapture = readIntakeFragment(); } catch (error) { intakeError = error; }

function money(value) { return formatMoney(value); }
function showError(selector, error) {
  const element = $(selector);
  element.textContent = error instanceof Error ? error.message : String(error || 'Não foi possível concluir. Tente novamente.');
  element.hidden = false;
}
function clearError(selector) { $(selector).textContent = ''; $(selector).hidden = true; }
function toast(message, error = false) {
  if (locking) return;
  clearTimeout(toastTimer);
  $('#toast').textContent = message;
  $('#toast').classList.toggle('error', error);
  $('#toast').hidden = false;
  toastTimer = setTimeout(() => { $('#toast').hidden = true; $('#toast').textContent = ''; }, 6500);
}
function requireUnlocked() {
  if (locking || !vault?.isUnlocked) throw new Error('Abra o cofre novamente para continuar.');
}
function enqueue(operation, allowLocked = false) {
  if (locking || (!allowLocked && !vault?.isUnlocked)) return Promise.reject(new Error('Abra o cofre novamente para continuar.'));
  const result = pending.then(operation);
  pending = result.catch(() => {});
  return result;
}
function on(selector, event, handler, errorTarget) {
  $(selector).addEventListener(event, async eventObject => {
    try { await handler(eventObject); }
    catch (error) { if (errorTarget) showError(errorTarget, error); else toast(error?.message || 'Não foi possível concluir. Tente novamente.', true); }
  });
}
async function busy(button, operation) {
  if (button.disabled) return;
  button.disabled = true;
  try { return await operation(); }
  finally { button.disabled = false; }
}
function setTab(name) {
  ['summary','records','vault'].forEach(tab => {
    $(`#${tab}-view`).hidden = tab !== name;
    const button = $(`[data-tab="${tab}"]`);
    button.classList.toggle('active', tab === name);
    if (tab === name) button.setAttribute('aria-current', 'page'); else button.removeAttribute('aria-current');
  });
  window.scrollTo({ top: 0, behavior: 'instant' });
}
function localDateTime(date = new Date()) {
  const pad = value => String(value).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth()+1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}
function empty(title, description, action = false) {
  return `<div class="empty-state"><span class="empty-symbol" aria-hidden="true">↗</span><strong>${escapeHTML(title)}</strong><p>${escapeHTML(description)}</p>${action ? '<button class="button secondary new-record">Adicionar primeiro registro</button>' : ''}</div>`;
}
function rowHTML(tx, editable = true) {
  const signed = tx.kind === 'income' ? '+ ' : tx.kind === 'expense' ? '− ' : '';
  const symbol = tx.kind === 'income' ? '↙' : tx.kind === 'expense' ? '↗' : '⇄';
  const tag = editable ? 'button' : 'div';
  const attrs = editable ? ` type="button" data-id="${escapeHTML(tx.id)}" aria-label="Editar ${escapeHTML(tx.merchant)}, ${escapeHTML(money(tx.amountMinor))}"` : '';
  return `<${tag} class="transaction-row"${attrs}><span class="transaction-symbol ${escapeHTML(tx.kind)}" aria-hidden="true">${symbol}</span><span class="transaction-copy"><span class="transaction-title">${escapeHTML(tx.merchant)}</span><span class="transaction-meta">${escapeHTML(tx.category)} · ${escapeHTML(tx.account)} · ${escapeHTML(dateFormatter.format(new Date(tx.date)))}</span></span><span class="transaction-amount ${escapeHTML(tx.kind)}">${signed}${escapeHTML(money(tx.amountMinor))}</span></${tag}>`;
}
function bindRows(container) {
  container.querySelectorAll('[data-id]').forEach(button => button.addEventListener('click', () => openRecord(transactions.find(tx => tx.id === button.dataset.id))));
  container.querySelectorAll('.new-record').forEach(button => button.addEventListener('click', () => openRecord()));
}
function renderCategories(monthTransactions) {
  const categories = new Map();
  for (const tx of monthTransactions) {
    if (tx.kind !== 'expense') continue;
    categories.set(tx.category, (categories.get(tx.category) || 0n) + BigInt(tx.amountMinor));
  }
  const entries = [...categories].sort((a,b) => a[1] > b[1] ? -1 : a[1] < b[1] ? 1 : 0);
  const total = entries.reduce((sum, item) => sum + item[1], 0n);
  $('#categories').replaceChildren();
  if (!entries.length) { $('#categories').innerHTML = empty('Seu mês começa aqui', 'As categorias aparecem conforme você registra suas saídas.'); return; }
  for (const [category, amount] of entries) {
    const wrapper = document.createElement('div'); wrapper.className = 'category-row';
    const label = document.createElement('div'); label.className = 'category-label';
    const title = document.createElement('span'); title.textContent = category;
    const value = document.createElement('span');
    const percentage = total ? Number(amount * 10000n / total) / 100 : 0;
    value.textContent = `${money(amount)} · ${percentage.toLocaleString('pt-BR', { maximumFractionDigits: 1 })}%`;
    label.append(title, value);
    const bar = document.createElement('progress'); bar.className = 'category-progress'; bar.max = 10000; bar.value = total ? Number(amount * 10000n / total) : 0; bar.setAttribute('aria-label', `${category}: ${percentage.toLocaleString('pt-BR')}%`);
    wrapper.append(label, bar); $('#categories').append(wrapper);
  }
}
function monthlyRecords() {
  return transactions.filter(tx => localDateTime(new Date(tx.date)).slice(0,7) === $('#month').value);
}
function renderSummary() {
  const monthRecords = monthlyRecords();
  // Pass only this local-calendar month's records so timezone boundaries agree with the UI.
  const totals = summarize(monthRecords, $('#month').value);
  $('#total-flow').textContent = money(totals.flow);
  $('#total-income').textContent = money(totals.income);
  $('#total-expense').textContent = money(totals.expense);
  renderCategories(monthRecords);
  const recent = monthRecords.slice(0,4);
  $('#recent-records').innerHTML = recent.length ? recent.map(tx => rowHTML(tx)).join('') : empty('Um começo leve', 'Adicione uma entrada ou saída para acompanhar seu mês.', true);
  bindRows($('#recent-records'));
}
function syncFilter(selector, values, firstLabel) {
  const selected = $(selector).value;
  $(selector).replaceChildren(new Option(firstLabel, ''));
  [...new Set(values)].sort((a,b) => a.localeCompare(b, 'pt-BR')).forEach(value => $(selector).add(new Option(value, value)));
  if ([...$(selector).options].some(option => option.value === selected)) $(selector).value = selected;
}
function renderRecords() {
  const search = $('#search').value.trim().toLocaleLowerCase('pt-BR');
  const kind = $('#filter-kind').value, account = $('#filter-account').value, category = $('#filter-category').value;
  const filtered = transactions.filter(tx => (!kind || tx.kind === kind) && (!account || tx.account === account) && (!category || tx.category === category) && (!search || `${tx.merchant} ${tx.note || ''}`.toLocaleLowerCase('pt-BR').includes(search)));
  $('#records-count').textContent = `${filtered.length} ${filtered.length === 1 ? 'registro' : 'registros'}`;
  if (!filtered.length) {
    $('#records-list').innerHTML = transactions.length ? empty('Nada por aqui com esses filtros', 'Experimente outro termo ou selecione todas as contas e categorias.') : empty('O primeiro passo é simples', 'Registre uma movimentação e comece a cuidar do seu dia a dia.', true);
  } else {
    let previousDate = '';
    $('#records-list').innerHTML = filtered.map(tx => {
      const date = new Date(tx.date).toLocaleDateString('pt-BR', { day:'numeric', month:'long', year:'numeric' });
      const heading = date !== previousDate ? `<div class="record-group-title">${escapeHTML(date)}</div>` : '';
      previousDate = date;
      return heading + rowHTML(tx);
    }).join('');
  }
  bindRows($('#records-list'));
}
async function refresh() {
  const fresh = await vault.list();
  if (locking || document.hidden) return;
  transactions = fresh.sort((a,b) => new Date(b.date)-new Date(a.date));
  syncFilter('#filter-account', transactions.map(tx => tx.account), 'Todas as contas');
  syncFilter('#filter-category', transactions.map(tx => tx.category), 'Todas as categorias');
  $('#account-options').replaceChildren(...[...new Set(transactions.map(tx => tx.account))].map(value => new Option(value)));
  renderSummary(); renderRecords();
}
function openRecord(tx) {
  if (!vault?.isUnlocked || locking) return;
  $('#record-form').reset(); clearError('#record-error');
  $('#record-id').value = tx?.id || '';
  $('#record-dialog-title').textContent = tx ? 'Editar registro' : 'Novo registro';
  $('#record-kind').value = tx?.kind || 'expense';
  $('#record-amount').value = tx ? `${BigInt(tx.amountMinor) / 100n},${String(BigInt(tx.amountMinor) % 100n).padStart(2, '0')}` : '';
  $('#record-date').value = localDateTime(tx ? new Date(tx.date) : new Date());
  editingOriginalDate = tx?.date || null;
  editingDisplayDate = $('#record-date').value;
  $('#record-merchant').value = tx?.merchant || '';
  $('#record-category').value = tx?.category || '';
  $('#record-account').value = tx?.account || '';
  $('#record-note').value = tx?.note || '';
  editingSource = tx?.source || 'manual'; editingCurrency = tx?.currency || 'BRL';
  $('#record-source').textContent = tx ? `${sources[tx.source] || 'Registro'} · Data e hora: ${dateTimeFormatter.format(new Date(tx.date))}.` : 'Registro manual. A data e hora podem ser ajustadas antes de salvar.';
  $('#delete-record').hidden = !tx;
  $('#record-dialog').showModal();
}
function clearPreparedBackup() {
  preparedFile = null;
  if (preparedURL) URL.revokeObjectURL(preparedURL);
  preparedURL = null;
  $('#backup-ready').hidden = true;
}
function clearReview() { reviewItems = []; $('#review-list').replaceChildren(); $('#review-totals').replaceChildren(); $('#review-description').textContent = ''; clearError('#review-error'); }
function closeDialog(dialog) {
  dialog.close();
  if (dialog.id === 'record-dialog') { $('#record-form').reset(); $('#record-source').textContent = ''; editingOriginalDate = null; editingDisplayDate = null; clearError('#record-error'); }
  if (dialog.id === 'restore-dialog') { backupText = ''; $('#restore-form').reset(); clearError('#restore-error'); }
  if (dialog.id === 'review-dialog') { clearReview(); $('#capture-text').value = ''; incomingCapture = null; }
}
function renderReview(items, description) {
  if (locking || document.hidden || !vault?.isUnlocked) return;
  if (!Array.isArray(items) || !items.length) throw new Error('Nenhum registro foi encontrado neste conteúdo.');
  reviewItems = items;
  const total = items.reduce((totals, tx) => {
    if (tx.kind === 'income') totals.income += BigInt(tx.amountMinor);
    if (tx.kind === 'expense') totals.expense += BigInt(tx.amountMinor);
    return totals;
  }, { income: 0n, expense: 0n });
  const knownIds = new Set(transactions.map(tx => tx.id));
  const fresh = items.filter(tx => !knownIds.has(tx.id)).length;
  const existing = items.length - fresh;
  const found = `${items.length} ${items.length === 1 ? 'registro encontrado' : 'registros encontrados'}`;
  let detail;
  if (!fresh) detail = `${found}, ${items.length === 1 ? 'já existe' : 'todos já existem'} no cofre; nada será adicionado.`;
  else if (existing) detail = `${found}: ${fresh} ${fresh === 1 ? 'novo' : 'novos'} e ${existing} ${existing === 1 ? 'já existe' : 'já existem'} no cofre (${existing === 1 ? 'será preservado' : 'serão preservados'}).`;
  else detail = `${found}.`;
  $('#review-description').textContent = `${description} ${detail}`;
  $('#confirm-import').disabled = !fresh;
  $('#review-totals').innerHTML = `<div>Entradas<strong>${escapeHTML(money(total.income))}</strong></div><div>Saídas<strong>${escapeHTML(money(total.expense))}</strong></div><div>Transferências<strong>${items.filter(tx => tx.kind === 'transfer').length}</strong></div>`;
  $('#review-list').innerHTML = items.slice(0,100).map(tx => rowHTML(tx, false)).join('');
  clearError('#review-error');
  $('#review-dialog').showModal();
}
async function reviewCapture(raw) {
  const items = await parseCapture(raw);
  renderReview(items, 'Captura recebida.');
  $('#capture-text').value = ''; incomingCapture = null;
}
async function readFile(file) {
  if (!file) return null;
  if (file.size > 20 * 1024 * 1024) throw new Error('Este arquivo ultrapassa o limite de 20 MB.');
  if (!file.size) throw new Error('O arquivo está vazio.');
  return await file.text();
}
function updateLastBackup() {
  try {
    const stored = localStorage.getItem('entrecontas:last-export');
    $('#last-backup').textContent = stored && Number.isFinite(new Date(stored).getTime()) ? `Última exportação solicitada: ${dateTimeFormatter.format(new Date(stored))}. Confirme se o arquivo foi salvo.` : 'Nenhuma exportação solicitada neste aparelho.';
  } catch { $('#last-backup').textContent = 'Confirme sempre se seu arquivo foi salvo.'; }
}
function recordExport() { try { localStorage.setItem('entrecontas:last-export', new Date().toISOString()); } catch {} updateLastBackup(); }
async function configureGate() {
  isCreating = !(await vault.exists());
  $('#gate-title').textContent = isCreating ? 'Vamos criar seu cofre.' : 'Bem-vindo de volta.';
  $('#gate-description').textContent = isCreating ? 'Escolha uma senha para proteger seus registros.' : 'Abra seu espaço. Seus registros esperam por você.';
  $('#confirm-wrap').hidden = !isCreating;
  $('#password-confirm').required = isCreating;
  $('#password-help').hidden = !isCreating;
  $('#recovery-note').hidden = !isCreating;
  $('#password').autocomplete = isCreating ? 'new-password' : 'current-password';
  $('#password').minLength = isCreating ? 12 : 1;
  $('#gate-submit').textContent = isCreating ? 'Criar meu cofre →' : 'Abrir meu cofre →';
  $('#gate-form').hidden = false;
}
async function lock() {
  if (!vault || locking) return;
  const wasUnlocked = vault.isUnlocked;
  locking = true;
  sessionEpoch++;
  // Cancel an opening derivation immediately; accepted mutations of an open
  // vault still finish before their key is discarded below.
  if (!wasUnlocked) vault.lock();
  $('#app').hidden = true; $('#gate').hidden = false;
  $$('dialog[open]').forEach(closeDialog);
  $('#gate-form').reset(); $('#password').type = 'password'; $('#show-password').textContent = 'Mostrar'; $('#show-password').setAttribute('aria-label', 'Mostrar senha');
  clearTimeout(toastTimer); $('#toast').hidden = true; $('#toast').textContent = '';
  // Operations already accepted finish before key material is discarded.
  await pending;
  vault.lock();
  transactions = []; reviewItems = []; backupText = ''; incomingCapture = null;
  clearPreparedBackup();
  $$('dialog[open]').forEach(closeDialog);
  $('#capture-text').value = ''; $('#search').value = '';
  $('#gate-form').reset(); $('#password').type = 'password'; $('#show-password').textContent = 'Mostrar'; $('#show-password').setAttribute('aria-label', 'Mostrar senha');
  ['#categories','#recent-records','#records-list','#review-list','#review-totals','#account-options'].forEach(selector => $(selector).replaceChildren());
  ['#total-income','#total-expense','#total-flow'].forEach(selector => $(selector).textContent = money(0n));
  $('#records-count').textContent = '';
  syncFilter('#filter-account', [], 'Todas as contas'); syncFilter('#filter-category', [], 'Todas as categorias');
  clearError('#gate-error'); clearTimeout(toastTimer); $('#toast').hidden = true; $('#toast').textContent = '';
  $('#app').hidden = true; $('#gate').hidden = false;
  locking = false;
  await configureGate();
}

$$('.tab').forEach(button => button.addEventListener('click', () => setTab(button.dataset.tab)));
$$('.new-record').forEach(button => button.addEventListener('click', () => openRecord()));
$$('.close-dialog').forEach(button => button.addEventListener('click', () => closeDialog(button.closest('dialog'))));
$$('dialog').forEach(dialog => dialog.addEventListener('cancel', event => { event.preventDefault(); closeDialog(dialog); }));
on('#show-password','click', () => {
  const showing = $('#password').type === 'password';
  $('#password').type = showing ? 'text' : 'password';
  $('#show-password').textContent = showing ? 'Ocultar' : 'Mostrar';
  $('#show-password').setAttribute('aria-label', showing ? 'Ocultar senha' : 'Mostrar senha');
});
on('#gate-form', 'submit', async event => {
  event.preventDefault(); clearError('#gate-error');
  await busy($('#gate-submit'), async () => {
    const openingEpoch = sessionEpoch;
    let password = $('#password').value;
    if (new TextEncoder().encode(password).length > 1024) throw new Error('Use uma senha de até 1.024 bytes.');
    if (isCreating && (password.length < 12 || password !== $('#password-confirm').value)) throw new Error(password.length < 12 ? 'Use pelo menos 12 caracteres na senha.' : 'As duas senhas precisam ser iguais.');
    await enqueue(async () => {
      if (openingEpoch !== sessionEpoch || document.hidden) throw new Error('A abertura do cofre foi cancelada. Digite sua senha para continuar.');
      if (isCreating) await vault.create(password); else await vault.unlock(password);
      password = '';
      $('#gate-form').reset();
      if (openingEpoch !== sessionEpoch || document.hidden) { vault.lock(); return; }
      await refresh();
      if (!locking && !document.hidden) {
        $('#gate').hidden = true; $('#app').hidden = false; setTab('summary');
        if (incomingCapture) {
          const raw = incomingCapture; incomingCapture = null;
          try { await reviewCapture(raw); } catch (error) { toast(error.message || 'Não foi possível ler a captura. Cole o conteúdo no Cofre para tentar novamente.', true); }
        }
      }
    }, true);
    if (document.hidden) await lock();
  });
}, '#gate-error');
on('#month','change', renderSummary);
on('#search','input', renderRecords);
['#filter-kind','#filter-account','#filter-category'].forEach(selector => on(selector,'change',renderRecords));
on('#see-records','click', () => setTab('records'));
on('#lock-button','click', lock);
document.addEventListener('visibilitychange', () => { if (document.hidden) lock().catch(() => { vault?.lock(); location.reload(); }); });
on('#record-form','submit', async event => {
  event.preventDefault(); clearError('#record-error');
  await busy($('#record-form button[type="submit"]'), async () => {
    const amountMinor = Number(parseMoney($('#record-amount').value));
    const date = new Date($('#record-date').value);
    if (!Number.isFinite(date.getTime())) throw new Error('Escolha uma data e hora válidas.');
    const preservedDate = editingOriginalDate && $('#record-date').value === editingDisplayDate ? editingOriginalDate : date.toISOString();
    const tx = { id: $('#record-id').value || crypto.randomUUID(), amountMinor, currency: editingCurrency, merchant: $('#record-merchant').value.trim(), date: preservedDate, kind: $('#record-kind').value, category: $('#record-category').value.trim(), account: $('#record-account').value.trim(), source: editingSource, note: $('#record-note').value.trim() };
    const validation = validateTransaction(tx);
    if (validation === false) throw new Error('Revise os dados do registro.');
    await enqueue(async () => { await vault.save(tx); await refresh(); });
    closeDialog($('#record-dialog')); toast('Registro salvo. Um passo a mais de clareza.');
  });
}, '#record-error');
on('#delete-record','click',async () => {
  if (!confirm('Excluir este registro? Ele será removido do cofre deste aparelho.')) return;
  await busy($('#delete-record'), async () => {
    const id = $('#record-id').value;
    await enqueue(async () => { await vault.remove(id); await refresh(); });
    closeDialog($('#record-dialog')); toast('Registro excluído.');
  });
}, '#record-error');
on('#prepare-backup','click',async () => {
  await busy($('#prepare-backup'), async () => {
    await enqueue(async () => {
      clearPreparedBackup();
      const data = await vault.exportBackup();
      const name = `entrecontas-backup-${new Date().toISOString().slice(0,10)}.json`;
      preparedFile = new File([data], name, { type:'application/json' });
      preparedURL = URL.createObjectURL(preparedFile);
      $('#share-backup').hidden = !navigator.canShare?.({ files:[preparedFile] });
      $('#backup-ready').hidden = false;
    });
  });
});
on('#share-backup','click', async () => {
  if (!preparedFile) throw new Error('Prepare um novo backup para continuar.');
  try { await navigator.share({ files:[preparedFile], title:'Backup Entrecontas' }); recordExport(); }
  catch (error) { if (error.name !== 'AbortError') throw new Error('O compartilhamento não foi concluído. Use “Baixar arquivo” para guardar uma cópia.'); }
});
on('#download-backup','click', () => {
  if (!preparedURL || !preparedFile) throw new Error('Prepare um novo backup para continuar.');
  const link = document.createElement('a'); link.href = preparedURL; link.download = preparedFile.name; document.body.append(link); link.click(); link.remove();
  recordExport();
  toast('Arquivo enviado para download. Confira onde ele foi salvo.');
});
on('#backup-file','change', async event => {
  const epoch = sessionEpoch;
  const file = event.target.files[0]; event.target.value = '';
  const content = await readFile(file); if (content === null) return;
  if (epoch !== sessionEpoch) return;
  requireUnlocked();
  backupText = content; $('#restore-form').reset(); clearError('#restore-error'); $('#restore-dialog').showModal();
});
on('#restore-form','submit', async event => {
  event.preventDefault(); clearError('#restore-error');
  await busy($('#restore-form button[type="submit"]'), async () => {
    const inputBackup = backupText, inputPassword = $('#restore-password').value;
    const items = await enqueue(() => vault.inspectBackup(inputBackup, inputPassword));
    closeDialog($('#restore-dialog'));
    renderReview(items, 'Backup aberto com segurança.');
  });
}, '#restore-error');
on('#csv-file','change', async event => {
  const epoch = sessionEpoch;
  const file = event.target.files[0]; event.target.value = '';
  const content = await readFile(file); if (content === null) return;
  if (epoch !== sessionEpoch) return;
  requireUnlocked();
  await enqueue(async () => { const items = await parseCSV(content); renderReview(items, 'Planilha lida.'); });
});
on('#paste-capture','click', async () => {
  const epoch = sessionEpoch;
  requireUnlocked();
  if (!navigator.clipboard?.readText) { $('#capture-text').focus(); toast('Toque no campo e use Colar para inserir a captura.'); return; }
  try {
    const text = await navigator.clipboard.readText();
    if (epoch !== sessionEpoch) return;
    requireUnlocked();
    $('#capture-text').value = text;
  }
  catch { if (epoch !== sessionEpoch) return; $('#capture-text').focus(); toast('Cole manualmente no campo abaixo. Seu navegador não liberou a leitura.'); }
});
on('#review-capture','click',async () => {
  const raw = $('#capture-text').value.trim();
  if (!raw) throw new Error('Cole o conteúdo da captura antes de revisar.');
  if (new TextEncoder().encode(raw).length > 20 * 1024 * 1024) throw new Error('A captura ultrapassa o limite de 20 MB.');
  await busy($('#review-capture'), () => enqueue(() => reviewCapture(raw)));
});
on('#confirm-import','click', async () => {
  clearError('#review-error');
  try { await busy($('#confirm-import'), async () => {
    if (!reviewItems.length) throw new Error('Não há registros para adicionar.');
    const knownIds = new Set(transactions.map(tx => tx.id));
    if (reviewItems.every(tx => knownIds.has(tx.id))) throw new Error('Todos os registros já existem no cofre; nada será adicionado.');
    const itemsToImport = reviewItems;
    let result;
    await enqueue(async () => { result = await vault.merge(itemsToImport); await refresh(); });
    closeDialog($('#review-dialog')); setTab('records');
    toast(`${result.added} ${result.added === 1 ? 'registro adicionado' : 'registros adicionados'}.${result.skipped ? ` ${result.skipped} já existiam e foram preservados.` : ''}`);
  }); } finally {
    // busy() reabilita o botão; se a revisão ficou obsoleta (tudo já existe), mantém desabilitado.
    const known = new Set(transactions.map(tx => tx.id));
    if (reviewItems.length && reviewItems.every(tx => known.has(tx.id))) $('#confirm-import').disabled = true;
  }
}, '#review-error');

$('#month').value = localDateTime().slice(0,7);
updateLastBackup();
if (!globalThis.crypto?.subtle || !globalThis.isSecureContext) {
  $('#gate-title').textContent = 'Abra seu cofre com segurança.';
  $('#gate-description').textContent = 'Este cofre exige uma conexão HTTPS segura. Abra o endereço publicado do aplicativo.';
  $('#gate-form').hidden = true;
  $('#gate-submit').disabled = true;
  incomingCapture = null;
} else {
  try {
    vault = await Vault.open(); await configureGate();
    if (intakeError) { toast(intakeError.message || 'A captura recebida não pôde ser lida. Cole o conteúdo manualmente no Cofre.', true); intakeError = null; }
  }
  catch (error) { $('#gate-title').textContent = 'Não foi possível abrir o cofre.'; $('#gate-description').textContent = 'Confirme se o navegador permite armazenamento local e tente recarregar a página.'; showError('#gate-error', error); }
}
