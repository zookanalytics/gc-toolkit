// Where the drill plane's supervisor requests go.
//
// THE SHORT ANSWER: same origin as the document, always. Never an absolute
// http://127.0.0.1:8372.
//
// This is worth spelling out because the obvious reading of "reuse the stock
// dashboard's pattern" points the other way. The stock `gc dashboard` is served
// by its own server on :8080 and therefore MUST reach cross-origin to the
// supervisor on :8372. helm is not in that position: helm-svc is reverse-proxied
// BY the supervisor, so the SPA and the typed API are already the same origin.
// Two independent things make same-origin the only workable choice here:
//
//  1. The tailscale origin. The operator opens this board from a phone or a
//     laptop that is not the city host. There, 127.0.0.1 is *their* machine —
//     the supervisor is unreachable at that address by construction. The board
//     is meant to be read from anywhere, so hardcoding loopback breaks the
//     primary use.
//  2. The Content-Security-Policy the app is served under. web/handler.go sets
//     `connect-src 'self'` (buildCSP). A fetch or EventSource to any other
//     origin is refused by the browser before it leaves the page — including
//     from loopback, whenever the document origin differs.
//
// So the plane addresses `/v0/city/<city>/...` relative to the document, and
// the only thing it must discover is the CITY NAME. That is recoverable from
// the mount path, because the supervisor mounts services at a path that carries
// it: /v0/city/<city>/svc/helm/. The server cannot read its own external prefix
// (the proxy strips it before helm-svc sees the request — see the normalizer in
// index.html), but the browser can: it is sitting in location.pathname.

/** The supervisor coordinates the drill plane resolved from the document. */
export interface SupervisorOrigin {
  /**
   * Absolute base every `/v0/...` path hangs off — the DOCUMENT'S OWN origin,
   * plus any path prefix that precedes the mount.
   *
   * Absolute rather than relative, despite always pointing at the same origin
   * the page came from: openapi-fetch constructs a `Request`, and a Request
   * resolves a relative URL only where there is a document to resolve against.
   * Spelling out `location.origin` keeps one code path that works in a browser,
   * in a test environment, and anywhere else, without ever naming a host — the
   * value is whatever origin the operator actually loaded the board from, which
   * is the tailscale host in normal use.
   */
  baseUrl: string;
  /** City name segment of the mount, e.g. 'loomington'. */
  city: string;
}

/** The parts of `window.location` this module reads. */
export interface LocationLike {
  origin: string;
  pathname: string;
}

// /v0/city/<city>/svc/<service>/...  — non-greedy prefix so the FIRST /v0/city
// wins, which is the real mount even if a later path segment repeats it.
const MOUNT_RE = /^(.*?)\/v0\/city\/([^/]+)\/svc\/[^/]+(?:\/|$)/;

/** What a service-mount path yields: the prefix before /v0, and the city. */
export interface MountPath {
  /**
   * Path prefix preceding `/v0`. Normally '' — the supervisor serves /v0 at its
   * root. Non-empty only when the whole supervisor sits behind a path-prefixing
   * reverse proxy, in which case the same prefix precedes the service mount and
   * is recovered from it here.
   */
  pathPrefix: string;
  city: string;
}

/**
 * Recover the mount's prefix and city from a service-mount pathname. Returns
 * null when the path is not a service mount — the dev server at '/', or the
 * bundle loaded from somewhere unexpected. Callers decide what a null means;
 * this function never guesses a city.
 */
export function parseMountPath(pathname: string): MountPath | null {
  const match = MOUNT_RE.exec(pathname);
  if (match === null) return null;
  const [, pathPrefix, city] = match;
  // A path segment is percent-encoded in location.pathname; the city name is a
  // plain identifier today, but decode so a name that ever needs escaping does
  // not silently address the wrong city.
  let decoded: string;
  try {
    decoded = decodeURIComponent(city);
  } catch {
    return null;
  }
  if (decoded === '') return null;
  return { pathPrefix, city: decoded };
}

/**
 * The drill plane's supervisor coordinates for the running document.
 *
 * In a production bundle this is exactly {@link parseMountPath}: resolve, or
 * fail honestly. The dev-server fallback is compiled out of production builds —
 * `import.meta.env.DEV` is statically false there, so neither the branch nor
 * __HELM_DEV_CITY__ survives into the shipped bundle. That matters: a fallback
 * city that could fire in production would silently point the board at the
 * wrong city rather than showing the operator an error.
 */
export function resolveSupervisorOrigin(location: LocationLike): SupervisorOrigin | null {
  const mounted = parseMountPath(location.pathname);
  if (mounted !== null) {
    return { baseUrl: location.origin + mounted.pathPrefix, city: mounted.city };
  }
  if (import.meta.env.DEV) {
    // `npm run dev` serves the app at '/', with vite proxying /v0 to the
    // loopback supervisor. The city comes from the same HELM_DEV_MOUNT that
    // configures that proxy, so dev has one source of truth (vite.config.ts).
    return { baseUrl: location.origin, city: __HELM_DEV_CITY__ };
  }
  return null;
}

/** Absolute-on-this-origin URL for a city-scoped supervisor path. */
export function cityUrl(origin: SupervisorOrigin, path: string): string {
  return `${origin.baseUrl}/v0/city/${encodeURIComponent(origin.city)}${path}`;
}
