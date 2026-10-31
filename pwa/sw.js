const VERSION = 'financeiro-local-v4';
const SHELL = [
  './', './index.html', './styles.css', './manifest.webmanifest',
  './src/app.js', './src/core.js', './src/vault.js', './src/intake.js', './src/sw-register.js',
  './atalhos.html', './guide.css', './assets/icon-192.png', './assets/icon-512.png',
];
const ALLOWED = new Set(SHELL.map(path => new URL(path, self.registration.scope).pathname));

self.addEventListener('install', event => {
  event.waitUntil(caches.open(VERSION).then(cache => cache.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(keys
    .filter(key => key.startsWith('financeiro-local-') && key !== VERSION)
    .map(key => caches.delete(key)))).then(() => self.clients.claim()));
});

self.addEventListener('fetch', event => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== self.location.origin || !ALLOWED.has(url.pathname)) return;
  // Cache only the known app shell. No payloads, query strings, API responses,
  // imports or exported backups are ever put into Cache Storage.
  if (url.search) return;
  event.respondWith(caches.open(VERSION).then(async cache => {
    const cached = await cache.match(request);
    if (cached) return cached;
    const response = await fetch(request);
    if (response.ok && response.type !== 'opaqueredirect' && !response.redirected) {
      await cache.put(request, response.clone());
    }
    return response;
  }));
});
