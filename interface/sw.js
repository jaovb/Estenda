// Estenda: deixa a página instalável como app. Busca sempre na rede primeiro (para pegar a versão
// nova) e usa a cópia guardada só se estiver sem internet. A conexão com o PC não passa por aqui.
const CAIXA = "estenda-v1";
self.addEventListener("install", e => self.skipWaiting());
self.addEventListener("activate", e => e.waitUntil(self.clients.claim()));
self.addEventListener("fetch", e => {
  const url = new URL(e.request.url);
  if (e.request.method !== "GET" || url.origin !== location.origin || url.pathname.startsWith("/sala/")) return;
  e.respondWith(fetch(e.request).then(r => {
    if (r.ok) { const copia = r.clone(); caches.open(CAIXA).then(c => c.put(e.request, copia)); }
    return r;
  }).catch(() => caches.match(e.request).then(r => r || caches.match("/"))));
});
