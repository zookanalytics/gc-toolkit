import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { defineConfig, type Plugin } from 'vite';
import react from '@vitejs/plugin-react';

// The dev server proxies the page's reads to a running helm service mount, so
// `npm run dev` renders live data. The mount defaults to the supervisor's
// loopback port and the city a Gas City session runs in, which GC_CITY names
// by its path or by its name. Point it at another city (or another supervisor
// port) with HELM_DEV_MOUNT. A build proxies nothing and folds the dev city out
// of the bundle, so only the dev server needs a city: the helm-dev-city plugin
// below refuses to start one without it.
const DEFAULT_DEV_CITY = (process.env.GC_CITY ?? '').replace(/\/+$/, '').split('/').pop() ?? '';
const NO_DEV_CITY = process.env.HELM_DEV_MOUNT === undefined && DEFAULT_DEV_CITY === '';
const DEFAULT_DEV_MOUNT = `http://127.0.0.1:8372/v0/city/${encodeURIComponent(DEFAULT_DEV_CITY || '_')}/svc/helm`;
const LOOPBACK_HOSTS = new Set(['127.0.0.1', 'localhost', '::1']);

// The supervisor binds loopback only and must never be exposed, so a custom dev
// target must still resolve to loopback. Validate at config load:
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

// The city name the page's supervisor read addresses in dev. In production it
// is read from the mount path (/v0/city/<city>/svc/helm/); the dev server has
// no such path, so it comes from the same HELM_DEV_MOUNT that configures the
// proxy below — one source of truth rather than a second hardcoded city. See
// src/supervisor/origin.ts.
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

// The page bundles IBM Plex Sans and IBM Plex Mono (src/fonts.css), licensed
// under the SIL Open Font License, which asks that the licence travel with the
// fonts. The build writes each package's own licence beside the page, so the
// licence served is always the one of the fonts bundled.
const require = createRequire(import.meta.url);
function fontLicences(): Plugin {
  return {
    name: 'helm-font-licences',
    apply: 'build',
    generateBundle() {
      for (const [pkg, name] of [
        ['@fontsource/ibm-plex-sans', 'IBM-Plex-Sans'],
        ['@fontsource/ibm-plex-mono', 'IBM-Plex-Mono'],
      ]) {
        this.emitFile({
          type: 'asset',
          fileName: `fonts/${name}-LICENSE.txt`,
          source: readFileSync(require.resolve(`${pkg}/LICENSE`)),
        });
      }
    },
  };
}

export default defineConfig({
  plugins: [
    react(),
    fontLicences(),
    {
      name: 'helm-dev-city',
      configureServer() {
        if (NO_DEV_CITY) {
          throw new Error('HELM_DEV_MOUNT is unset, and no GC_CITY names a city to default it to');
        }
      },
    },
  ],

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
      // The page reads and writes document-relative 'helm/...', which is
      // '/helm/...' when served from the dev root.
      '/helm': { target: devMount, changeOrigin: true },
      // Details reads a bead from the supervisor same-origin (see
      // src/supervisor/origin.ts). In production that is literally the same
      // server; in dev the proxy stands in for it, so /v0/... reaches the real
      // supervisor.
      '/v0': {
        target: new URL(devMount).origin,
        changeOrigin: true,
        ws: false,
      },
    },
  },
});
