/* =====================================================================
   LogiSync Service Worker — NETWORK-ONLY.

   We intentionally do NOT cache the app shell anymore. Cache-first /
   stale-while-revalidate caused the UI to load stale builds, so this worker
   simply stays out of the way: it claims clients, deletes any old caches
   left over from previous versions, and lets every request go to the network.
   The app is an online tool (Supabase-backed), so offline support isn't
   needed and isn't worth the stale-content risk.
   ===================================================================== */

const CACHE = 'logisync-shell-v4';

self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    // Remove every cache from older service-worker versions.
    const keys = await caches.keys();
    await Promise.all(keys.map((k) => caches.delete(k)));
    await self.clients.claim();
  })());
});

// No 'fetch' handler on purpose — the browser goes straight to the network
// for everything, so a new deploy is always served fresh on reload.
