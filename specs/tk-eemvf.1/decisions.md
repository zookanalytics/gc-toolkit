---
name: U5 SPA scaffold — decisions and rejected alternatives
description: Why the helm web app is served the way it is — mount-prefix safety, the two-audience bare mount, the committed bundle, and where the embed had to live. Read before changing how helm-svc serves the app (U6/U7/U8/U9).
---

# U5 SPA scaffold — decisions

Work record for `tk-eemvf.1` (U5 of the Attention Canvas plan,
`specs/tk-eemvf/2026-06-30-001-feat-attention-canvas-plan.md`). What is true
*now* about the app — how to build it, why `base: './'`, why `dist/` is
committed — is in `services/helm/README.md` under *Web UI*. This file records
what was decided and what was rejected, for whoever lands U6 on top.

The leg was scoped structure-only: no canvas library, no visual design system,
no spatial layout. The visual direction gates U6 and has not been chosen. A
plain readable table over the board contract is the deliverable.

## 1. The bare mount serves two representations, not one

**Decision.** `GET /` returns the app shell to a client that asks for HTML
(`Accept: text/html` — a browser navigation) and the board JSON to everything
else (curl, `fetch`, any script, `Accept: */*`). `/helm` returns JSON
unconditionally, whatever the Accept header says.

**Why.** Two facts collide. A workspace-service gets exactly one mount from the
supervisor, so the app has nowhere else to live; and the bare mount has always
returned the board JSON — the operator curls it and it is the address of the
whole service. Serving only the app there would silently change what an
existing caller receives.

**Rejected: SPA at `/`, JSON only at `/helm`.** The simpler routing, and what a
narrow reading of "static serve at mount root" implies. It breaks every current
reader of the bare mount, including the verification snippets recorded on the
epic, and the break is invisible to the service — the caller just starts
getting HTML.

**Consequence for later units.** Do not move `/helm`. It is the contract U7
mirrors and U8/U9 consume, and it is deliberately insensitive to Accept so a
browser-side `fetch` cannot accidentally negotiate itself into HTML.

## 2. Trailing-slash normalization is client-side, because the server cannot do it

**Decision.** An inline script in `index.html` redirects to the slash-suffixed
path when `location.pathname` has no trailing slash, before the deferred module
scripts run. `base: './'` (KTD5) handles everything else.

**Why.** The supervisor's proxy maps *both* `.../svc/helm` and `.../svc/helm/`
onto the subpath `/` before helm-svc sees the request (`serviceSubpath`,
gascity `internal/workspacesvc/manager.go`). The service therefore cannot tell
the two forms apart, and cannot learn its own external prefix — so it cannot
emit the redirect an ordinary origin server would. Without the trailing slash
the document base drops the last segment and every relative asset resolves one
directory too high: a blank page behind 404s. That is exactly the KTD5 failure
the plan's Risks section names.

**Rejected: a server-side redirect.** Not expressible. The information needed
to build the `Location` was stripped before the request arrived.

**Rejected: injecting `<base href>` from `GC_SERVICE_URL_PREFIX`.** The
supervisor does inject that variable, so this would work — but it couples the
served HTML to an environment variable whose drift produces a totally broken
app, and it buys nothing the prefix-agnostic client check doesn't already give.

**Consequence for later units.** The normalizer assumes a single route. A unit
that adds client-side routing has to replace it with real basename detection —
appending a slash to `<mount>/tile/42` is wrong.

## 3. The built bundle is committed

**Decision.** `services/helm/web/dist/` is tracked, and the launcher
(`assets/scripts/gc-helm-svc.sh`) now treats `web/dist/**` as build input
alongside `*.go`.

**Why.** The launcher rebuilds the Go binary on demand but never runs npm, so
an untracked bundle means a Node-less build ships a service with no UI. The
stock dashboard SPA commits its bundle for the same reason. The launcher change
is the other half: `go:embed` compiles the bundle in, so a bundle-only edit that
doesn't touch a `.go` file would otherwise keep serving the SPA embedded at the
last Go edit — stale, with nothing to indicate it.

`node_modules` is pruned from the launcher's staleness walk; nothing there is
built from and walking it costs more than the rest of the module together.

## 4. The embed lives in `services/helm/web/`, not `cmd/helm-svc/`

**Deviation from the plan, forced.** The plan (and this bead) place the
`go:embed` of `web/dist` in the command package. `go:embed` cannot reference a
parent directory, so a directive in `cmd/helm-svc/` cannot reach `../../web/dist`.

The app source, its build output, and the embed therefore share one directory:
`services/helm/web/` is both the Vite project root and the Go package `web`.
This keeps the app at the path the plan specifies with no copy step and no
out-of-root `outDir`. The stock dashboard splits these (source under `web/`,
bundle copied to a sibling `dist/`) and pays a manual copy for it.

## 5. A broken bundle degrades the UI, not the service

**Decision.** `web.NewHandler()` failing is logged and the service serves board
JSON alone — the routing it had before the app existed.

**Why.** The board is load-bearing and live; the app is additive. Refusing to
start would convert a cosmetic failure into an outage of the operator's current
surface. The embed is compile-time checked, so this only fires on a `dist/` that
built badly.

## What was deliberately not built

- **`src/contract.ts`** — the typed contract mirror is U7 (`tk-eemvf.2`).
  `App.tsx` carries a minimal local shape with a comment saying so; it must be
  replaced by an import, not grown into a second contract.
- **A client-side route table, canvas, or design system** — U6, gated on the
  Claude Design handoff bundle.
- **Any `[[service]]` declaration or `city.toml` change** — U10, operator-gated,
  and it bounces the town. Embedding the app into the existing binary reaches
  the existing mount with neither.
- **A JS test runner.** The leg's test scenarios are "build embeds" and "assets
  resolve under a prefix", both proven server-side in Go
  (`TestAssetsResolveUnderMountPrefix` resolves the shell's references the way a
  browser does and fetches them back through a simulated mount). Visual
  behaviour is tested in U6, which is when a component runner earns its keep.

## Verification performed

Built binary run over a unix socket exactly as the supervisor runs it
(`GC_SERVICE_SOCKET`), against the live city via the supervisor source:

| Request | Result |
|---|---|
| `GET /healthz` | 200 `{"status":"ok"}` |
| `GET /helm` | 200 `application/json`, 21 real tiles |
| `GET /helm` with `Accept: text/html` | 200 `application/json` |
| `GET /` with `Accept: */*` | 200 `application/json`, byte-identical to `/helm` |
| `GET /` with a browser Accept | 200 `text/html`, the app shell |
| `GET /assets/index-*.js` / `*.css` | 200, `immutable` cache, correct content types |
| `GET /nope` | 404 |

Plus `go test ./...`, `go vet ./...`, `bash -n` and shellcheck on the launcher,
and a functional check that the launcher's staleness walk fires on a
`dist/`-only change and ignores `node_modules`.
