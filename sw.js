// Guarda o app no aparelho para abrir rápido e funcionar sem internet.
// Quando mudar algo no app, troque o número da versão abaixo.
const CACHE = 'okada-v51';
const ARQUIVOS = [
  './', 'index.html', 'dados.enc', 'dados.js', 'tabelas_padrao.json', 'tabelas_padrao.js', 'pdfjs/pdf.min.js', 'pdfjs/pdf.worker.min.js', 'fonts/plus-jakarta-sans-latin.woff2', 'manifest.webmanifest', 'icon-192.png', 'icon-512.png', 'logo-okada.webp', 'logo-okada-pdf.webp',
  'logos/adelmar.webp', 'logos/aec.webp', 'logos/avionix.webp', 'logos/bortec.webp',
  'logos/brosol.webp', 'logos/ds.webp', 'logos/iam.webp', 'logos/julijac.webp',
  'logos/lion.webp', 'logos/ls.webp', 'logos/proauto.webp', 'logos/schuck.webp',
  'logos/top-relay.webp'
];

self.addEventListener('install', (e) => {
  self.skipWaiting();
  e.waitUntil(
    caches.open(CACHE).then((c) =>
      Promise.all(ARQUIVOS.map((a) => c.add(a).catch(() => {})))
    )
  );
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((chaves) =>
      Promise.all(chaves.map((k) => (k !== CACHE ? caches.delete(k) : null)))
    ).then(() => self.clients.claim())
  );
});

// Para HTML / navegação: tenta a rede primeiro (para pegar atualizações na hora). Se falhar (offline), usa o cache.
self.addEventListener('fetch', (e) => {
  if (e.request.method !== 'GET') return;
  const url = e.request.url;
  const isHtml = e.request.mode === 'navigate' || e.request.destination === 'document' || url.endsWith('.html') || url.endsWith('/') || url.includes('index.html');

  if (isHtml) {
    e.respondWith(
      fetch(e.request)
        .then((r) => {
          if (r && r.ok) {
            const clone = r.clone();
            caches.open(CACHE).then((c) => c.put(e.request, clone));
          }
          return r;
        })
        .catch(() => caches.match(e.request, { ignoreSearch: true }))
    );
    return;
  }

  // Demais recursos: cache primeiro, rede em segundo plano
  e.respondWith(
    caches.match(e.request, { ignoreSearch: true }).then((guardado) => {
      const daRede = fetch(e.request)
        .then((r) => {
          if (r && r.ok) {
            const clone = r.clone();
            caches.open(CACHE).then((c) => c.put(e.request, clone));
          }
          return r;
        })
        .catch(() => guardado);
      return guardado || daRede;
    })
  );
});
