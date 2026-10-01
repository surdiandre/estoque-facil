const VERSION = '187';
const CACHE = 'estoque-facil-v187-interface-padronizada';
const CORE = [
  './assets/app-updates.js?v=187', './assets/stock-readability.css?v=141',
  './assets/stock-cards-polish.css?v=170',
  './assets/stock-background.css?v=140', './assets/stock-landscape-realista.png?v=140',
  '/', './index.html', './estoque-facil.html', './manifest.webmanifest',
  './assets/dashboard-polish.css?v=71', './assets/weather-card.css?v=79',
  './assets/weather-card.js?v=79', './assets/product-codes.js?v=7', './assets/qr-baixa.js?v=7', './assets/overview-info.css?v=75',
  './assets/overview-info.js?v=73', 
  './icons/icon-192.png', './icons/icon-512.png', './icons/icon-1024.png',
  './icons/estoque-facil-icon.svg', './icons/estoque-facil-logo.svg',
  './icons/estoque-facil-logo-mobile.svg', './icons/estoque-facil-logo-sidebar.svg',
  './assets/hero-lavoura-opcao6.jpg?v=29', './assets/hero-pulverizacao.jpg?v=29',
  './assets/hero-colheita.jpg?v=29', './assets/hero-cooperativa-v4.png?v=43',
  './assets/hero-plantio.jpg?v=29', './assets/hero-carousel.css?v=29',
  './assets/hero-carousel.js?v=29',
];
const VENDOR = [
  'https://cdn.tailwindcss.com',
  'https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js',
  'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2',
  'https://cdn.jsdelivr.net/npm/xlsx-js-style@1.2.0/dist/xlsx.bundle.js',
  'https://cdn.jsdelivr.net/npm/tesseract.js@5/dist/tesseract.min.js',
  'https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css',
  'https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/webfonts/fa-solid-900.woff2',
  'https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/webfonts/fa-regular-400.woff2'
];
const staticVendor = url => VENDOR.includes(url.href) ||
  (url.hostname === 'cdnjs.cloudflare.com' && url.pathname.startsWith('/ajax/libs/font-awesome/6.4.0/webfonts/'));

self.addEventListener('install', event => event.waitUntil((async () => {
  const cache = await caches.open(CACHE);
  for (const url of CORE) {
    const request = new Request(url, {cache:'reload'});
    const response = await fetch(request);
    if (!response.ok) throw new Error('Arquivo indisponível: '+url);
    await cache.put(request,response);
  }
  await Promise.allSettled(VENDOR.map(async url => {
    try {
      const request = new Request(url, {mode:'no-cors'});
      const response = await fetch(request, {signal:AbortSignal.timeout(4500)});
      await cache.put(request, response);
    } catch (e) { /* CDN indisponível: a instalação pode continuar. */ }
  }));
  await self.skipWaiting();
})()));

self.addEventListener('activate', event => event.waitUntil((async () => {
  const keys = await caches.keys();
  await Promise.all(keys.filter(key => key.startsWith('estoque-facil-') && key !== CACHE).map(key => caches.delete(key)));
  await self.clients.claim();
  const clients = await self.clients.matchAll({type:'window'});
  clients.forEach(client => client.postMessage({type:'APP_UPDATED',version:VERSION}));
})()));

self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;
  const url = new URL(event.request.url);
  if (url.origin === self.location.origin && url.pathname.endsWith('/app-version.json')) return;
  const sameOrigin = url.origin === self.location.origin;
  if (!sameOrigin && !staticVendor(url)) return;
  event.respondWith((async () => {
    const cached = await caches.match(event.request);
    if (cached) return cached;
    try {
      const response = await fetch(event.request);
      if (response.ok || (staticVendor(url) && response.type === 'opaque')) {
        const cache = await caches.open(CACHE);
        await cache.put(event.request, response.clone());
      }
      return response;
    } catch (e) {
      if (event.request.mode === 'navigate') return caches.match('./index.html');
      return new Response('', {status:503, statusText:'Offline'});
    }
  })());
});
