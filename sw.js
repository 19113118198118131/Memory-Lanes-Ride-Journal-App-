// Memory Lanes service worker: app-shell caching (stale-while-revalidate).
// Bump CACHE on each deploy so clients pick up fresh files.
const CACHE = 'memory-lanes-v87';
const CORE = [
  './',
  './index.html',
  './dashboard.html',
  './stats.html',
  './journal.html',
  './planner.html',
  './ride-live.html',
  './route.html',
  './group.html',
  './style.css?v=87',
  './script.js?v=87',
  './insights.js?v=87',
  './icons.js?v=87',
  './theme.js?v=87',
  './riderskills.js?v=87',
  './dashboard.js?v=87',
  './stats.js?v=87',
  './journal.js?v=87',
  './planner.js?v=87',
  './planner-engine.js?v=87',
  './route.js?v=87',
  './group.js?v=87',
  './ride-live.js?v=87',
  './ai/feature-schema.js?v=87',
  './ai/feature-extractor.js?v=87',
  './ai/recommender.js?v=87',
  './ai/ride-feedback.js?v=87',
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

  // HTML pages: NETWORK FIRST. The pages reference versioned assets (style.css?v=N),
  // so a stale page would keep asking for the old asset URLs and a deploy would never
  // appear. Always try the network for documents, and fall back to cache only offline.
  const isDoc = req.mode === 'navigate' ||
                (req.headers.get('accept') || '').includes('text/html');
  if (isDoc) {
    event.respondWith(
      fetch(req)
        .then(res => {
          if (res && res.ok) {
            const copy = res.clone();
            caches.open(CACHE).then(c => c.put(req, copy));
          }
          return res;
        })
        .catch(() => caches.match(req).then(c => c || caches.match('./index.html')))
    );
    return;
  }

  // Versioned assets: cache first, refresh in the background.
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
