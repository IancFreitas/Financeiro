import { runVaultBrowserChecks } from './browser-checks.js';
const button = document.querySelector('#run');
const status = document.querySelector('#status');
const list = document.querySelector('#checks');
button.addEventListener('click', async () => {
  button.disabled = true;
  status.textContent = 'Executando testes com dados sintéticos…';
  list.replaceChildren();
  try {
    const result = await runVaultBrowserChecks();
    for (const check of result.checks) {
      const item = document.createElement('li'); item.textContent = `PASSOU: ${check.name}`; list.append(item);
    }
    status.textContent = `${result.passed}/${result.total} testes de navegador aprovados.`;
  } catch (error) {
    for (const check of error.browserChecks?.checks || []) {
      const item = document.createElement('li'); item.textContent = `PASSOU: ${check.name}`; list.append(item);
    }
    status.textContent = `FALHOU após ${error.browserChecks?.passed || 0} testes: ${error.message}`;
  }
});
