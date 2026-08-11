---
name: Helm source backend — why the in-process beads library
description: Records which of the two sanctioned data-access paths tk-x89rn chose to carry updated_at and metadata, the live evidence that forced the choice, and the behavioural differences the new backend introduces.
---

# Helm source backend — why the in-process beads library

`tk-x89rn` widened the Helm source seam so the board can read `updated_at`
and bead `metadata`, and restored `stale_days` on top of them. The bead
named two sanctioned paths and required the choice be written down. This
is that record.

## Scope

**Mandate.** Why this bead picked the in-process beads library over an
extended supervisor endpoint, what was measured to justify it, and what
changes observably as a result.

**Boundaries.** It does not describe how to operate the service (see
`services/helm/README.md`), and it does not cover the three consumer beads
that spend the capability (`tk-x55wt`, `tk-b3rga`, `tk-2v08m`).

## The constraint

`services/helm/README.md` states the data-access contract as hard: all
bead/Dolt access goes through a Gas City API — never raw Dolt, no
`sql.Open("mysql")`, no `JSON_EXTRACT` against bead DBs. Two paths are
sanctioned:

1. the in-process beads library, or
2. a new/extended supervisor endpoint carrying `updated_at` + metadata.

## What was measured

Probing the live supervisor (loomington, 2026-08-10) established what the
HTTP API can and cannot supply. The `Bead` schema *declares* `updated_at`,
`metadata` and `assignee`, so the gap is not visible from the OpenAPI
document alone — it only shows in the payloads:

| Endpoint | `metadata` | `updated_at` |
|---|---|---|
| `/beads?type=epic` | absent | absent |
| `/beads/graph/{id}` | absent | absent |
| `/beads/ready` | absent | absent |
| `/bead/{id}` | **present** | absent |
| `/convoy/{id}` (+ children) | **present** | absent |

So metadata *is* reachable over HTTP, but only through per-anchor
single-bead reads. `updated_at` is reachable through **no endpoint at
all**: the field serializes `omitzero` and arrives zero everywhere, and
there is no `fields` or `full` parameter to widen the projection.

The store itself has the value — `bd show` and `bd list --json` both
return `updated_at`, and gascity's own `bdIssue`/`toBead` decode carries it
— so the zero is introduced somewhere in the supervisor's read path, not
missing from the data. Diagnosing that is gascity's, not this bead's.

## The decision

**Path 1, the in-process beads library** (`github.com/steveyegge/beads`),
opening each rig's own `.beads` store through `beads.OpenFromConfig`.

Path 2 was not available to this bead. The supervisor is the `gc` binary,
which lives in the **`gascity` rig**, not in `gc-toolkit`. Extending an
endpoint cannot be shipped from this repository, so choosing it would have
meant closing this bead with the capability undelivered and three
consumers still blocked.

Path 1 is also the shape already proven: the bash PoC this service ports
(`assets/scripts/gc-helm.sh`) reads `bd list --db <rig>/.beads` per rig —
the same library, through its CLI. The Go source is the same access
pattern in-process.

The contract holds. The library owns the connection exactly as it does for
every `bd` invocation; there is no hand-written SQL and no `JSON_EXTRACT`
anywhere in the new code.

## What it costs

Honest accounting, because these are real and a reviewer should not have
to discover them:

- **Dependency weight.** The helm module went from *zero* requirements to
  ~170 (the Dolt / go-mysql-server stack). `go.sum` grows to ~1400 lines.
- **Binary size.** `helm-svc` is ~158 MB, up from a few MB.
- **First build is slow** — minutes, not seconds. The launcher builds on
  demand, so a *cold* cache now costs a real wait; Go's build cache keeps
  subsequent restarts instant, as before.
- **Go floor.** The module's `go` directive moved from 1.23 to 1.26.5,
  pulled up by the beads module chain.

None of these are visible to a board consumer, and none change the
service's request path. They are paid at build and startup.

## What changes observably

Verified by running the same binary against the live city under both
backends:

| | beads library | supervisor HTTP |
|---|---|---|
| `stale_days` | real (0–87 across 22 tiles; 17 non-zero) | `0` on every tile |
| `updated_at` | carried | `null` |
| NORMAL→ELEVATED stale bump | can fire | unreachable |
| child `assignee` | carried | absent |
| anchors | 22 | 23 |

### The anchor-count difference is the supervisor's status flattening

The one extra anchor over HTTP was `su-av11`, an epic whose real status is
**`deferred`**. gascity's `mapBdStatus` collapses every status that is not
`closed`/`in_progress` into `open`, so a deferred (or blocked, or pinned)
anchor arrives over HTTP indistinguishable from an open one, and the HTTP
source admits it.

The library source sees the true status and filters to `open`, which is
what `gc-helm.sh` does (`bd list --status open`). So this is the HTTP
backend over-reporting, not the new backend dropping work — a deliberately
parked epic is not an attention item. The new behaviour matches the model
of record.

Child counts are unaffected: the board already treats every non-closed,
non-in-progress child as open, so flattening `deferred`→`open` never moved
a count.

## Backend selection

The choice is made once, at startup, and logged — never silently per
request. A per-request fallback could let a board lose its staleness lane
and still look healthy, which is the failure this bead exists to end.

- default: the beads library, when a city root with rig stores is readable;
- fallback: the supervisor HTTP API, with a log line naming the
  consequence (`stale_days will be 0`);
- `GC_HELM_SOURCE=beads|supervisor` forces either. Forcing `beads` when
  the stores are unreadable is fatal rather than a quiet downgrade.

## What this bead deliberately did not do

The capability is shipped; spending it is three separate beads. `Metadata`
is populated on every anchor and child, and **no derivation reads it yet**.
`needs()`, `frontier()` and the gather set are untouched, and the
owned-vs-unowned convoy partition stays deferred even though this backend
could now resolve it — changing which convoys reach the board is a gather
change. `tk-x55wt`, `tk-b3rga` and `tk-2v08m` consume it separately so each
stays reviewable.
