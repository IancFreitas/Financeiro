const MAX_BYTES = 20 * 1024 * 1024;

// Financial data belongs in the fragment only. It is removed before parsing,
// rendering, network activity, or waiting for the user to unlock the vault.
export function decodeIntakeFragment(hash) {
  if (!/^#\/?capture\?/.test(hash)) return null;
  if (hash.length > MAX_BYTES * 1.4) throw new Error('O conteúdo do link é grande demais. Importe um arquivo.');
  const value = new URLSearchParams(hash.slice(hash.indexOf('?') + 1)).get('data');
  if (!value || !/^[A-Za-z0-9_-]+={0,2}$/.test(value)) throw new Error('O link não contém dados válidos. Use Colar JSON ou importar arquivo.');
  try {
    const raw = value.replace(/-/g, '+').replace(/_/g, '/');
    const bytes = Uint8Array.from(atob(raw.padEnd(Math.ceil(raw.length / 4) * 4, '=')), c => c.charCodeAt(0));
    if (bytes.length > MAX_BYTES) throw new Error();
    return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  } catch { throw new Error('Não foi possível ler o conteúdo do link. Use Colar JSON ou importar arquivo.'); }
}

export function readIntakeFragment() {
  const hash = window.location.hash;
  if (!/^#\/?capture\?/.test(hash)) return null;
  window.history.replaceState(null, '', window.location.pathname + '#/');
  return decodeIntakeFragment(hash);
}
