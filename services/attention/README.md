# attention — Attention Canvas backend spine (spike: tk-sy3vj)

A long-lived Go sidecar that serves a ranked **attention board** as JSON, sourced
live from the Gas City supervisor's loopback HTTP API. It is the backend data +
serving plane for the Attention Canvas operator dashboard (epic `tk-eemvf`) and
the Go port of the board MODEL in `assets/scripts/gc-attention.sh` (the bash PoC,
which this replaces — the bash dies).

This is a **spike**: it proves the data+serving spine end-to-end with a minimal
real payload. The full model port is a follow-up bead (see *Deferred*, below).

## What it does

```
GET /attention   -> { generated_at, total, tiles:[ {id,rig,kind,title,severity,
                      live,n_closed,m_total,open,in_progress,frontier,needs,
                      rank_score}, ... ], partial?, partial_errors? }
GET /healthz     -> { "status":"ok" }   (liveness probe; no gather)
```

Tiles are ranked `rank_score` descending and deduplicated by id. Four anchor
kinds are gathered: **epic**, **decision**, **flagged** (`gc.attention=1`), and
**convoy** (owned, floating).

## Architecture

Three packages, a clean dependency line `board <- source <- server <- cmd`:

| Package | Responsibility |
|---|---|
| `internal/board` | The MODEL. Pure, I/O-free: severity, liveness, counts, frontier/needs, `rank_score`, sort+dedup. Ported field-for-field from `gc-attention.sh`. |
| `internal/source` | The data-access **seam**. `Source` interface + `SupervisorSource` (HTTP client against the supervisor API). |
| `internal/server` | HTTP routes + a server-side TTL cache of the computed board. |
| `cmd/attention-svc` | Entrypoint: listen on the `GC_SERVICE_SOCKET` unix socket, wire source→server, graceful SIGTERM. |

### Data-access contract (hard constraint)

All bead/Dolt access goes through a Gas City API — **never raw Dolt**. v1 uses the
supervisor HTTP API (itself a Gas City API). There is no `sql.Open("mysql")`, no
`JSON_EXTRACT` against bead DBs. The `source.Source` interface is the seam: a
future contract-compliant backend (the in-process beads library, or a sanctioned
new endpoint) can swap in without touching the model or serving code.

Endpoints consumed (all under `/v0/city/<city>/`): `/rigs`, `/beads?type=epic`,
`/beads/graph/{id}` (all-status child roll-up), `/beads?type=decision`, `/beads`
(paged scan, filtered to `gc.attention=1` in process), `/convoys` +
`/convoy/{id}`, `/sessions?view=full` (liveness). Cross-rig `partial` /
`partial_errors` are propagated to the board envelope; a 503 (total outage)
surfaces as a 502 from `/attention`.

## Wiring it as a workspace-service

The service is a `proxy_process`: the supervisor spawns the launcher, hands it a
unix socket in `GC_SERVICE_SOCKET`, and reverse-proxies
`/v0/city/<city>/svc/attention/attention` → `GET /attention` (path-stripped).

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
name = "attention"
kind = "proxy_process"

  [service.process]
  command = ["bash", "rigs/gc-toolkit/assets/scripts/gc-attention-svc.sh"]
  health_path = "/healthz"
```

`publish_mode` defaults to `private` (a pack must not set `direct`), and
`state_root` defaults to `.gc/services/attention`. The launcher
(`assets/scripts/gc-attention-svc.sh`) builds the binary on demand (Go's build
cache makes restarts instant) and `exec`s it so SIGTERM reaches the Go process.

Once declared, the board is reachable:

```bash
curl http://127.0.0.1:8372/v0/city/<city>/svc/attention/attention   # ranked board
# and through the same tailscale origin the gc dashboard uses (:8372).
```

## Build / run / test

```bash
cd services/attention
go test ./...                 # unit tests (model golden cases + mock-supervisor source + server/cache)
go build ./cmd/attention-svc  # or let the launcher build it

# Run standalone against the live supervisor (no [[service]] needed):
GC_SERVICE_SOCKET=/tmp/att.sock \
GC_SERVICE_URL_PREFIX=/v0/city/<city>/svc/attention \
GC_CITY_PATH=$GC_CITY_PATH \
  ./attention-svc &
curl --unix-socket /tmp/att.sock http://x/attention | jq .
```

Discovery env: `GC_ATTENTION_SUPERVISOR_URL` (else supervisor.toml port, default
`127.0.0.1:8372`); `GC_ATTENTION_CITY` (else parsed from `GC_SERVICE_URL_PREFIX`,
else `GC_CITY_PATH` basename); `GC_ATTENTION_CACHE_TTL` (seconds or a Go
duration; default 45s).

## Spike findings — what's proven vs. deferred

**Proven** (this spike): the spine works end-to-end against the live city —
auto-buildable launcher, unix-socket serving, `/healthz`, a real cross-rig ranked
board, instant crash-restart, TTL cache, contract-compliant HTTP-only data
access, unit tests over the model and a mock supervisor.

**Deferred to the follow-up model-port bead** (and *why*):

- **`stale_days`** and the NORMAL→ELEVATED stale bump — the supervisor bead API
  omits `updated_at` (serialized `omitzero`), so staleness is not derivable over
  HTTP. The rank formula keeps the staleness lane (currently 0) so the follow-up
  only has to supply a richer source.
- **The full rank `weight`** — the spike weight is `m_total + prio_w(priority)`;
  the cross-rig-ref description scan (`min(xrefs,5)`) is dropped.
- **`assigned` / `open_heads`** — the bead API omits `assignee`.
- **The takeaway-driven NEEDS sentence** — NEEDS uses the deterministic phrase;
  `gc.takeaway` plumbing is deferred.
- **`stranded`/`empty`/`complete`/`progress_mismatch`** booleans.
- **owned-convoy filter** — `/convoys` omits the `owned` flag, so floating +
  non-`sling-` title approximates ownership; true `owned==true` filtering needs a
  richer convoy source.
- **flagged scan cost** — no server-side metadata filter exists, so flagged
  anchors require a paged full-bead scan (bounded; logged if truncated). A
  sanctioned `?metadata=` filter or the beads library would remove this.
- **event-invalidation** — the cache is TTL-only; the supervisor SSE
  `/v0/events/stream` can later replace polling.

## Handoff

The `[[service]]` stanza above lives in the **town repo** (`city.toml`), which is
outside this rig PR. Per the spike bead, the city-scoped placement is the
operator/keeper's to apply. Everything in this rig PR (the Go module, launcher,
and tests) is self-contained and proven runnable standalone; adding the stanza
turns on auto-start + the tailscale-reachable mount.
