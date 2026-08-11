import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// The dev server proxies the board fetch to a running helm service mount, so
// `npm run dev` renders live data. Point it at another city (or another
// supervisor port) with HELM_DEV_MOUNT.
const DEFAULT_DEV_MOUNT = 'http://127.0.0.1:8372/v0/city/loomington/svc/helm';
// ttyd's own loopback port. In deployment the board reaches ttyd because a
// tailscale-serve mapping publishes both under one origin; the dev server has
// no such mapping, so it proxies /terminal itself to reproduce that same-origin
// shape. Point it elsewhere with HELM_DEV_TTYD.
const DEFAULT_DEV_TTYD = 'http://127.0.0.1:7681';
const LOOPBACK_HOSTS = new Set(['127.0.0.1', 'localhost', '::1']);

// The supervisor and ttyd both bind loopback only and must never be exposed, so
// a custom dev target must still resolve to loopback. Validate at config load:
// a malformed or off-host value fails here rather than silently proxying dev
// traffic somewhere it should not go.
function resolveLoopbackTarget(envName: string, fallback: string): string {
  const raw = process.env[envName];
  if (raw === undefined) return fallback;
  let hostname: string;
  try {
    hostname = new URL(raw).hostname;
  } catch {
    throw new Error(`${envName} is not a valid URL: ${JSON.stringify(raw)}`);
  }
  // URL parsing wraps IPv6 hosts in brackets ([::1]); strip them before compare.
  const normalized = hostname.replace(/^\[|\]$/g, '');
  if (!LOOPBACK_HOSTS.has(normalized)) {
    throw new Error(
      `${envName} must resolve to loopback (127.0.0.1, localhost, or ::1); got ${JSON.stringify(hostname)}`,
    );
  }
  return raw;
}

// The city name the drill plane addresses in dev. In production it is read from
// the mount path (/v0/city/<city>/svc/helm/); the dev server has no such path,
// so it comes from the same HELM_DEV_MOUNT that configures the proxy below —
// one source of truth rather than a second hardcoded city. See src/drill/origin.ts.
function resolveDevCity(mount: string): string {
  const match = /\/v0\/city\/([^/]+)\//.exec(new URL(mount).pathname);
  if (match === null) {
    throw new Error(
      `HELM_DEV_MOUNT must contain a /v0/city/<city>/ segment; got ${JSON.stringify(mount)}`,
    );
  }
  return decodeURIComponent(match[1]);
}

const devMount = resolveLoopbackTarget('HELM_DEV_MOUNT', DEFAULT_DEV_MOUNT);

export default defineConfig({
  plugins: [react()],

  define: {
    // Only ever read behind `import.meta.env.DEV`, so this is constant-folded
    // out of production bundles.
    __HELM_DEV_CITY__: JSON.stringify(resolveDevCity(devMount)),
  },

  // KTD5, the load-bearing setting for this app. helm-svc is reached through
  // the supervisor's service proxy at a runtime-city-named prefix
  // (/v0/city/<city>/svc/helm/), never at the origin root, and the proxy strips
  // that prefix before the request arrives — so the server cannot know it and
  // cannot rewrite absolute asset URLs. A relative base makes every emitted
  // asset URL resolve against the document, at whatever mount depth it is
  // served from. base: '/' is the known failure mode for this service: it
  // works on a dev server at the root and 404s everything under the mount.
  base: './',

  build: {
    outDir: 'dist',
    emptyOutDir: true,
    // The bundle is committed (Go embeds it; the launcher never runs npm), so
    // no source maps — they would multiply the tracked bytes for no operator
    // gain on a loopback-private board.
    sourcemap: false,
  },

  server: {
    port: 5175,
    strictPort: true,
    host: '127.0.0.1',
    proxy: {
      // The app fetches the board as a document-relative 'helm', which is
      // '/helm' when served from the dev root.
      '/helm': { target: devMount, changeOrigin: true },
      // ws: true is required — the terminal is a WebSocket at /terminal/ws, and
      // without it the upgrade is not proxied and the tile never attaches.
      '/terminal': {
        target: resolveLoopbackTarget('HELM_DEV_TTYD', DEFAULT_DEV_TTYD),
        changeOrigin: true,
        ws: true,
      },
      // The drill plane addresses the supervisor same-origin (see
      // src/drill/origin.ts). In production that is literally the same server;
      // in dev the proxy stands in for it, so /v0/... reaches the real
      // supervisor — including the SSE stream, which needs buffering off to
      // arrive as frames rather than in one lump at the end.
      '/v0': {
        target: new URL(devMount).origin,
        changeOrigin: true,
        ws: false,
        configure: (proxy) => {
          proxy.on('proxyRes', (proxyRes) => {
            if (proxyRes.headers['content-type']?.includes('text/event-stream')) {
              proxyRes.headers['x-accel-buffering'] = 'no';
            }
          });
        },
      },
    },
  },
});
