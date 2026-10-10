// Headers the Helm board's write POSTs carry.
//
// A board write (open, accept, engage, dismiss) reaches helm-svc through the
// supervisor's /svc/<name>/ reverse proxy, which guards mutations to a private
// workspace-service with a CSRF check: a request without the X-GC-Request header
// is refused at the supervisor with 403 "csrf: X-GC-Request header required" and
// never reaches helm-svc. The gc API client sends the same header on its own
// mutations. These writes are same-origin with the board document, so the custom
// header triggers no CORS preflight; a cross-site page, by contrast, cannot add
// it without one.
export const SVC_WRITE_HEADERS: Readonly<Record<string, string>> = {
  'Content-Type': 'application/json',
  Accept: 'application/json',
  'X-GC-Request': 'true',
};
