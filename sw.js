// Memory Lanes service worker: app-shell caching (stale-while-revalidate).
// Bump CACHE on each deploy so clients pick up fresh files.
const CACHE = 'memory-lanes-v40';
const CORE = [
  './',
  './index.html',
  './dashboard.html',
  './stats.html',
  './journal.html',
  './style.css?v=40',
  './script.js?v=40',
  './icons.js?v=40',
  './theme.js?v=40',
  './riderskills.js?v=40',
  './dashboard.js?v=40',
  './stats.js?v=40',
  './supabaseClient.js',
  './manifest.webmanifest',
  './assets/demo-ride.gpx',
  './assets/logo/icon-192.png',
  './assets/logo/favicon.png'
];

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE)
      .then(cache => Promise.allSettled(CORE.map(url => cache.add(url))))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', event => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return; // CDN/API traffic goes straight to network
  event.respondWith(
    caches.match(req).then(cached => {
      const fresh = fetch(req).then(res => {
        if (res && res.ok) {
          const copy = res.clone();
          caches.open(CACHE).then(c => c.put(req, copy));
        }
        return res;
      }).catch(() => cached);
      return cached || fresh;
    })
  );
});
