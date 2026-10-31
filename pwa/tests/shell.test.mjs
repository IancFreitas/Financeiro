import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, access, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
const root = new URL('../', import.meta.url);
test('all referenced app shell resources and icons exist', async () => {
  const index = await readFile(new URL('index.html', root), 'utf8');
  const refs = [...index.matchAll(/(?:src|href)="([^"#]+)"/g)].map(match=>match[1]);
  for (const path of refs) { if(!/^[a-z]+:/i.test(path)) await access(new URL(path, root)); }
  const manifest = JSON.parse(await readFile(new URL('manifest.webmanifest',root),'utf8'));
  assert.equal(manifest.display,'standalone');
  for(const icon of manifest.icons) await access(new URL(icon.src,root));
  const sw = await readFile(new URL('sw.js',root),'utf8');
  const shell = [...sw.slice(sw.indexOf('const SHELL'),sw.indexOf('const ALLOWED')).matchAll(/'([^']+)'/g)].map(x=>x[1]);
  for(const path of shell) await access(new URL(path==='./'?'index.html':path,root));
  assert.ok(!shell.some(path=>/tests|backup|\.financeiro/.test(path)));
});
test('runtime has restrictive CSP and no outbound finance or analytics client', async () => {
  const html = await readFile(new URL('index.html',root),'utf8');
  assert.match(html,/connect-src 'none'/);
  assert.match(html,/form-action 'none'/);
  assert.ok(!/<script(?![^>]*src=)[^>]*>\s*\S/.test(html));
  for(const name of await readdir(new URL('src/',root))) {
    if(!name.endsWith('.js')) continue;
    const js = await readFile(new URL('src/'+name,root),'utf8');
    assert.ok(!/\b(?:fetch|XMLHttpRequest|WebSocket|sendBeacon|eval)\s*\(/.test(js),name+' introduces outbound execution');
    assert.ok(!/localStorage\.setItem\([^\n]*(?:password|transactions)/.test(js));
  }
});
