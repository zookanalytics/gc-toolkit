import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// The dev server proxies the board fetch to a running helm service mount, so
// `npm run dev` renders live data. Point it at another city (or another
// supervisor port) with HELM_DEV_MOUNT.
const DEFAULT_DEV_MOUNT = 'http://127.0.0.1:8372/v0/city/loomington/svc/helm';
const LOOPBACK_HOSTS = new Set(['127.0.0.1', 'localhost', '::1']);

// The supervisor binds loopback only and must never be exposed, so a custom dev
// target must still resolve to loopback. Validate at config load: a malformed
// or off-host HELM_DEV_MOUNT fails here rather than silently proxying dev
// traffic somewhere it should not go.
function resolveDevMount(): string {
  const raw = process.env.HELM_DEV_MOUNT;
  if (raw === undefined) return DEFAULT_DEV_MOUNT;
  let hostname: string;
  try {
    hostname = new URL(raw).hostname;
  } catch {
    throw new Error(`HELM_DEV_MOUNT is not a valid URL: ${JSON.stringify(raw)}`);
  }
  // URL parsing wraps IPv6 hosts in brackets ([::1]); strip them before compare.
  const normalized = hostname.replace(/^\[|\]$/g, '');
  if (!LOOPBACK_HOSTS.has(normalized)) {
    throw new Error(
      `HELM_DEV_MOUNT must resolve to loopback (127.0.0.1, localhost, or ::1); got ${JSON.stringify(hostname)}`,
    );
  }
  return raw;
}

export default defineConfig({
  plugins: [react()],

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
      '/helm': { target: resolveDevMount(), changeOrigin: true },
    },
  },
});
