const SHELL = "whami-shell-v12";
const TILES = "whami-tiles-v2";
const SHELL_URLS = [
  "./",
  "./index.html",
  "./manifest.json",
  "./css/app.css?v=12",
  "./js/storage.js?v=7",
  "./js/trust.js?v=7",
  "./js/sensors.js?v=7",
  "./js/map.js?v=7",
  "./js/app.js?v=11",
  "./icons/app_icon.png",
  "./icons/Icon-192.png",
  "./icons/Icon-512.png",
  "./favicon.png",
];

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(SHELL).then((cache) => cache.addAll(SHELL_URLS)));
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys
          .filter((k) => k !== SHELL && k !== TILES)
          .map((k) => caches.delete(k)),
      ),
    ),
  );
  self.clients.claim();
});

self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);
  if (event.request.method !== "GET") return;

  if (
    url.hostname.includes("tile.openstreetmap.fr") ||
    url.hostname.includes("basemaps.cartocdn.com") ||
    url.hostname.includes("unpkg.com") ||
    url.hostname.includes("jsdelivr.net")
  ) {
    event.respondWith(staleWhileRevalidate(event.request, TILES));
    return;
  }

  if (url.origin === self.location.origin) {
    event.respondWith(
      caches.match(event.request).then((cached) => cached || fetch(event.request)),
    );
  }
});

async function staleWhileRevalidate(request, cacheName) {
  const cache = await caches.open(cacheName);
  const cached = await cache.match(request);
  const network = fetch(request)
    .then((res) => {
      if (res.ok) cache.put(request, res.clone());
      return res;
    })
    .catch(() => cached);
  return cached || network;
}
