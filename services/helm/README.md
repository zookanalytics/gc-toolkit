# helm — Attention Canvas backend spine (spike: tk-sy3vj)

A long-lived Go sidecar that serves a ranked **Helm board** as JSON, sourced live
from the city's bead state. It is the backend data + serving plane for the
Attention Canvas operator dashboard (epic `tk-eemvf`) and the Go port of the
board MODEL in `assets/scripts/gc-helm.sh` (the bash PoC, which this replaces —
the bash dies).

The spine came from the `tk-sy3vj` spike; `tk-x89rn` then widened the source seam
so the board can read `updated_at` and bead metadata, which is what makes
`stale_days` real. The model port is still partial — see *Still deferred*, below.

## What it does

```
GET /helm   -> { generated_at, total, tiles:[ {id,rig,kind,title,severity,
                      n_closed,m_total,open,in_progress,frontier,needs,
                      stale_days,updated_at,rank_score}, ... ],
                 partial?, partial_errors? }
GET /healthz     -> { "status":"ok" }   (liveness probe; no gather)
GET /            -> the board JSON, or the embedded web app for a browser
                    (Accept: text/html) — see *Web UI*
GET /assets/...  -> the web app's bundle
```

Tiles are ranked `rank_score` descending and deduplicated by id. Three anchor
kinds are gathered: **epic**, **decision**, and **convoy** (owned, floating).

## Architecture

Three packages, a clean dependency line `board <- source <- server <- cmd`:

| Package | Responsibility |
|---|---|
| `internal/board` | The MODEL. Pure, I/O-free: severity, counts, frontier/needs, `rank_score`, sort+dedup. Ported field-for-field from `gc-helm.sh`. |
| `internal/source` | The data-access **seam**. `Source` interface + two backends: `BeadsSource` (in-process beads library, the default) and `SupervisorSource` (HTTP client against the supervisor API). |
| `internal/server` | HTTP routes + a server-side TTL cache of the computed board. |
| `web` | The operator's web app (Vite + React + TS) and the `go:embed` that compiles its built bundle into the binary. |
| `cmd/helm-svc` | Entrypoint: listen on the `GC_SERVICE_SOCKET` unix socket, wire source→server, graceful SIGTERM. |

### Data-access contract (hard constraint)

All bead/Dolt access goes through a Gas City API — **never raw Dolt**. There is
no `sql.Open("mysql")`, no `JSON_EXTRACT` against bead DBs. The `source.Source`
interface is the seam, and both shipped backends sit behind it without the model
or serving code knowing which one is live.

**`BeadsSource` — the in-process beads library (default).** Opens each rig's own
`.beads` store through `beads.OpenFromConfig`, the same library the `bd` CLI uses
and the same access pattern the bash PoC always had (`bd list --db
<rig>/.beads`). Rigs are enumerated from `<city>/rigs/*/.beads`, so it needs the
city root on disk and no HTTP at all. Store handles are opened lazily and reused
for the process lifetime; the rig *set* is re-read each gather, so a rig added
later is picked up without a restart.

**`SupervisorSource` — the loopback HTTP API (fallback).** Endpoints consumed
(all under `/v0/city/<city>/`): `/rigs`, `/beads?type=epic`, `/beads/graph/{id}`
(all-status child roll-up), `/beads?type=decision`, `/convoys` + `/convoy/{id}`.

Either way, cross-rig `partial` / `partial_errors` are propagated to the board
envelope, and a total outage (no rig or no endpoint readable) surfaces as a 502
from `/helm` rather than an empty board that reads as "nothing needs attention".

### Why there are two backends

`SupervisorSource` cannot see two facts the model needs, and this is a property
of the API, not of the client:

- **`updated_at` reaches no endpoint at all** — not `/beads`, `/beads/graph/{id}`,
  `/beads/ready`, `/bead/{id}` or `/convoy/{id}`. The `Bead` schema declares the
  field, but it serializes `omitzero`, arrives zero everywhere, and there is no
  `fields`/`full` parameter to widen the projection. Without it `stale_days` is
  pinned to 0 and **no tile can ever age**.
- **metadata reaches only the single-bead reads** (`/bead/{id}`, `/convoy/{id}`),
  so a gather would pay one extra round trip per anchor to see it.

`BeadsSource` reads both directly. Choosing it over a new supervisor endpoint —
the other sanctioned path — is recorded, with the measurements, in
`specs/tk-x89rn/source-backend-decision.md`; the short version is that the
supervisor is the `gc` binary in the **gascity** rig and cannot be changed from
this repository.

**Costs of the library backend, paid at build and startup, not per request:** the
module went from zero dependencies to ~170 (the Dolt / go-mysql-server stack),
`helm-svc` is ~158 MB, a *cold* build takes minutes (the build cache keeps
restarts instant thereafter), and the Go floor moved to 1.26.5.

**One behavioural difference.** The HTTP backend reports one extra anchor,
because gascity's `mapBdStatus` flattens every status that is not
`closed`/`in_progress` into `open` — so a **deferred** epic arrives over HTTP
looking open and is admitted. The library backend sees the real status and
filters to `open`, matching `gc-helm.sh` (`bd list --status open`). A
deliberately-parked epic is not an attention item, so the library behaviour is
the faithful one. Child counts are unaffected: the board already treats every
non-closed, non-in-progress child as open.

### Picking a backend

Selected once at startup and logged — never silently per request, because a
per-request fallback could drop the staleness lane while the board still looked
healthy.

| `GC_HELM_SOURCE` | Behaviour |
|---|---|
| unset (default) | beads library if `<city>/rigs/*/.beads` is readable; otherwise the HTTP API, with a log line naming the consequence |
| `beads` | force the library; **fatal** if the stores are unreadable, rather than a quiet downgrade |
| `supervisor` | force the HTTP API (accepting `stale_days = 0`) |

## Wiring it as a workspace-service

The service is a `proxy_process`: the supervisor spawns the launcher, hands it a
unix socket in `GC_SERVICE_SOCKET`, and reverse-proxies
`/v0/city/<city>/svc/helm/helm` → `GET /helm` (path-stripped).

**Placement (important).** `[[service]]` is **forbidden in rig-imported packs**
(`internal/config/pack.go` — gc-toolkit is rig-imported by four rigs), so the
declaration must live in a **city-scoped** location: `city.toml` itself or the
city-root `pack.toml`. The Go binary stays in the rig; the `command` resolves
relative to the declaring pack's `SourceDir`, which for a city-scoped service is
the **city root** — hence the relative `rigs/gc-toolkit/...` path below.

Add this to the city's `city.toml` (town repo — **operator/keeper action**, see
*Handoff*):

```toml
[[service]]
name = "helm"
kind = "proxy_process"

  [service.process]
  command = ["bash", "rigs/gc-toolkit/assets/scripts/gc-helm-svc.sh"]
  health_path = "/healthz"
```

`publish_mode` defaults to `private` (a pack must not set `direct`), and
`state_root` defaults to `.gc/services/helm`. The launcher
(`assets/scripts/gc-helm-svc.sh`) builds the binary on demand (Go's build
cache makes restarts instant) and `exec`s it so SIGTERM reaches the Go process.

Once declared, the board is reachable:

```bash
curl http://127.0.0.1:8372/v0/city/<city>/svc/helm/helm   # ranked board
open http://127.0.0.1:8372/v0/city/<city>/svc/helm/       # the web app
# and through the same tailscale origin the gc dashboard uses (:8372).
```

## Web UI

`web/` is a Vite + React + TypeScript app — the operator's board surface —
embedded in the binary and served at the service mount. This is the U5 scaffold
(`tk-eemvf.1`): **structure only**. It renders the board contract as a plain
readable table. The spatial canvas, and the visual direction it implements, are
U6 and land on top of this.

Three things about it are load-bearing.

**`base: './'` (KTD5).** The app is served under a runtime-city-named prefix
(`/v0/city/<city>/svc/helm/`), never at an origin root, and the supervisor's
service proxy strips that prefix before the request arrives — so the server
cannot know it and cannot rewrite absolute URLs. Every asset reference must be
document-relative. `base: '/'` is the known failure for this service: it works
on a dev server and 404s everything under the mount. `TestAssetsResolveUnderMountPrefix`
resolves the shell's references the way a browser does and fetches them back
through a simulated mount, so a regression fails the build rather than the
board.

The same proxy maps both `.../svc/helm` and `.../svc/helm/` to `/`, so the
server cannot redirect the slash-less form either. An inline script in
`index.html` normalizes it client-side, before the deferred module scripts run.

**`dist/` is committed.** The launcher rebuilds the Go binary on demand but
never runs npm, so the built bundle is tracked — same contract as the stock
dashboard SPA. After changing anything under `web/`, rebuild and commit the
output:

```bash
cd services/helm/web
npm install        # first time (or npm ci)
npm run build      # tsc + vite build -> dist/
git add dist       # the bundle ships in the repo
```

The launcher treats `web/dist/**` as build input alongside `*.go`, so a
bundle-only change still triggers a rebuild of the binary that embeds it.

**The bare mount answers two audiences.** It has always returned the board
JSON, and the app has to live at that same path because a workspace-service
gets exactly one mount. So the representation follows the request: a browser
navigation (`Accept: text/html`) gets the app, everything else — curl, `fetch`,
any script — gets the JSON it always got. `/helm` is JSON unconditionally; that
is the contract U7 mirrors and U8/U9 consume, and no Accept header changes it.

```bash
npm run dev        # http://127.0.0.1:5175, proxying the board fetch to a live mount
HELM_DEV_MOUNT=http://127.0.0.1:8372/v0/city/<city>/svc/helm npm run dev
```

`HELM_DEV_MOUNT` must resolve to loopback — the supervisor binds loopback only
and the dev proxy refuses to send traffic off-host.

## Build / run / test

```bash
cd services/helm
go test ./...                 # unit tests (model golden cases + mock-supervisor source + server/cache + the embedded app)
go build ./cmd/helm-svc  # or let the launcher build it

# Run standalone against the live supervisor (no [[service]] needed):
GC_SERVICE_SOCKET=/tmp/helm.sock \
GC_SERVICE_URL_PREFIX=/v0/city/<city>/svc/helm \
GC_CITY_PATH=$GC_CITY_PATH \
  ./helm-svc &
curl --unix-socket /tmp/helm.sock http://x/helm | jq .
```

Discovery env:

- `GC_HELM_SOURCE` — `beads` | `supervisor`; see *Picking a backend* above.
- `GC_HELM_CITY_PATH` (else `GC_CITY_PATH`, else `GC_CITY`) — the city root the
  beads backend enumerates `rigs/*/.beads` under.
- `GC_HELM_SUPERVISOR_URL` (else supervisor.toml port, default `127.0.0.1:8372`)
  and `GC_HELM_CITY` (else parsed from `GC_SERVICE_URL_PREFIX`, else the
  `GC_CITY_PATH` basename) — the HTTP backend's target.
- `GC_HELM_CACHE_TTL` — seconds or a Go duration; default 45s.

The standalone invocation above reaches the supervisor over HTTP; to run it on
the library backend instead, pass `GC_CITY_PATH` (the supervisor already injects
it under a real service mount) and leave `GC_HELM_SOURCE` unset.

## What's proven vs. deferred

**Proven** (the `tk-sy3vj` spike): the spine works end-to-end against the live
city — auto-buildable launcher, unix-socket serving, `/healthz`, a real cross-rig
ranked board, instant crash-restart, TTL cache, contract-compliant data access,
unit tests over the model and a mock supervisor.

**Delivered since** (tk-x89rn, the source-seam widening):

- **`stale_days`** and the NORMAL→ELEVATED stale bump are real under
  `BeadsSource`. `updated_at` rides on the tile alongside it, because
  `stale_days: 0` alone cannot distinguish "touched today" from "the source
  could not read it".
- **`assignee`** is carried on children.
- **metadata** is carried on every anchor and child — but *carried, not spent*:
  no derivation reads it yet. That is deliberate, so the three consumers below
  stay separately reviewable.

**Delivered since** (tk-eemvf.1, the U5 scaffold): a mount-prefix-safe Vite +
React + TS app embedded in the binary and served at the mount, alongside the
JSON the mount already served. Structure only — see *Web UI*.

**Still deferred** (and *why*):

- **The full rank `weight`** — the weight is `m_total + prio_w(priority)`; the
  cross-rig-ref description scan (`min(xrefs,5)`) is dropped.
- **The takeaway-driven NEEDS sentence** — NEEDS uses the deterministic phrase.
  `gc.takeaway` is now readable; spending it is `tk-x55wt`.
- **`stranded`/`empty`/`complete`/`progress_mismatch`** booleans. (STRANDED
  itself is already in the severity derivation: open work with none in
  progress.)
- **The `held` visit fact** — the bash board's glyph (an open visit bead with
  `task_kind=visit` whose `gc.continuation_group` names the anchor). Metadata is
  now readable, so this is derivable; deriving it belongs to the consumer bead.
- **owned-convoy filter** — floating + non-`sling-` title still approximates
  ownership. `BeadsSource` could resolve the real edge, but changing *which*
  convoys reach the board is a gather change and was kept out of tk-x89rn.
- **event-invalidation** — the cache is TTL-only; the supervisor SSE
  `/v0/events/stream` can later replace polling.

The three beads that spend the widened seam: `tk-x55wt` (dead columns + constant
NEEDS), `tk-b3rga` (decision tiles), `tk-2v08m` (human-routed beads invisible).

## Handoff

The `[[service]]` stanza above lives in the **town repo** (`city.toml`), which is
outside this rig PR. Per the spike bead, the city-scoped placement is the
operator/keeper's to apply. Everything in this rig PR (the Go module, launcher,
and tests) is self-contained and proven runnable standalone; adding the stanza
turns on auto-start + the tailscale-reachable mount.
