# Installing gc-toolkit

> Reference for wiring `gc-toolkit` into a Gas City. Assumes a working Gas
> City install (`gc version` returns a version) and a city created with
> `gc init`.

gc-toolkit ships a **native agent roster** — polecat, refinery, witness,
deacon, mechanik, polecat-codex, proactive, and the converse-opus,
converse-fable and converse-codex sittings — declared in its own `pack.toml`.
It imports nothing: there are no gastown prerequisites, no transitive imports,
and no agent patches to wire.

Covered here:

1. [Importing gc-toolkit](#1-importing-gc-toolkit)
2. [The mechanik named session](#2-the-mechanik-named-session)
3. [Sub-pack opt-in: gascity-keeper](#3-sub-pack-opt-in-gascity-keeper)
4. [The helm board service](#4-the-helm-board-service)
5. [Verification](#5-verification)

For Gas City background, see [`gascity-reference.md`](gascity-reference.md).

---

## 1. Importing gc-toolkit

### Per-rig import (most common)

Drop gc-toolkit somewhere reachable from the city root (the convention is
`rigs/gc-toolkit/`), then add the import to your `city.toml`:

```toml
[[rigs]]
name = "my-rig"
prefix = "mr"

[rigs.imports.gc-toolkit]
source = "rigs/gc-toolkit"
```

`source` resolves relative to the city root.

### Remote git import

```toml
[rigs.imports.gc-toolkit]
source = "github.com/<owner>/gc-toolkit"
version = "v0.1.0"
```

`version` is required for git-backed imports; run `gc import install` to
materialize the pack under `.gc/cache/`.

### Default import across every rig

```toml
# pack.toml (city root)
[defaults.rig]
[defaults.rig.imports.gc-toolkit]
source = "rigs/gc-toolkit"
```

Any per-rig `[rigs.imports.gc-toolkit]` overrides the default for that rig.

### What the import brings in

- **The roster** — worker pools (`polecat`, and `polecat-codex` on the
  codex provider), patrols (`refinery`, `witness`, `deacon`), conversation
  sittings (`converse-opus`, `converse-fable`, `converse-codex`, which
  `gc-helm engage` opens per visit), and `proactive` (always-on, 2-slot).
- **The lifecycle** — `lifecycle/lifecycle.toml` (states, transitions,
  metadata registry) and the single transition writer
  `assets/scripts/lifecycle.sh`.
- **Orders** — the merge cadence (`refinery-reconcile`, 60s, rig-scoped),
  `deferred-dispatch`, `liveness-sweep`, `reconcile-rig-checkouts`,
  `boot-health`, `quota-park-nudge`, `helm-build`, and the feedback
  miner/distiller.
- **Skills** — surfaced via `gc skill list` (`gc-toolkit.handoff`,
  `gc-toolkit.session-title`, …).
- **Doctor checks** — the structural checks verified below.

---

## 2. The mechanik named session

gc-toolkit provides a `mechanik` named-session template (the city-scoped
structural engineer). Declare it once at the city level:

```toml
[[named_session]]
template = "mechanik"
```

Then:

```bash
gc start
gc session attach mechanik
```

---

## 3. Sub-pack opt-in: gascity-keeper

`packs/gascity-keeper/` is a separate pack for the one rig that maintains a
`gascity` fork. Import it **in addition to** gc-toolkit, on that rig only:

```toml
[rigs.imports.gascity-keeper]
source = "rigs/gc-toolkit/packs/gascity-keeper"
```

The complete wiring snippet — including the `[[rigs.patches]]`
fragment-injection blocks for refinery and polecat — lives in the sub-pack
itself: [`packs/gascity-keeper/pack.toml`](../packs/gascity-keeper/pack.toml).
The sub-pack ships its own `[[named_session]]` (`scope = "rig"`), so the
keeper is spawnable without an extra block; it resolves to
`<rig>/gascity-keeper.keeper` (confirm with `gc config show`).

Sub-pack imports are rig-scoped: declare them inside a `[[rigs]]` block, never
at the city level, or every rig picks them up.

---

## 4. The helm board service

The board is a Go sidecar (`services/helm`), render-only, and optional —
everything works without it. `[[service]]` is forbidden in rig-imported
packs, so the stanza is **city-level**: add it to the city's `city.toml` (or
city-root `pack.toml`), with the command path relative to the city root:

```toml
[[service]]
name = "helm"
kind = "proxy_process"

  [service.process]
  command = ["bash", "rigs/gc-toolkit/assets/scripts/gc-helm-svc.sh"]
  health_path = "/healthz"
```

The launcher `exec`s a prebuilt binary; the `helm-build` order keeps it built.
Write verbs (takeaway / open / react) stay in `assets/scripts/gc-helm.sh`;
rendering is `helm-svc board --json`. See
[`services/helm/README.md`](../services/helm/README.md).

---

## 5. Verification

### `gc doctor`

```bash
gc doctor
```

The pack's checks, and what a failure means:

| Check | Asserts (invariant) | First-failure cause |
|---|---|---|
| `check-wait-is-an-edge` | every live bead carrying a declared hold marker also carries a `blocks` edge to a live bead in the same store — a wait is an edge, not prose or a bare marker (I1) | a hold left as a marker or note with no `blocks` edge filed, or one whose blockers all closed or name another store |
| `check-state-space` | every `merge_result`/status combo is declared in `lifecycle.toml`, and a detached state rests unheld and offered to no pool (I2) | a writer minted an undeclared state, or something routed a parked anchor back into pool demand |
| `check-routed-work-claimable` | every route and assignee names a live target; routed work is in `bd ready` or in `bd blocked`; rig-scoped orders bound (I3) | a pool renamed, an order missing its rig registration, or routed work stranded outside both queues |
| `check-one-anchor-per-pr` | one open owning anchor per PR (I4) | duplicate anchors filed for one branch |
| `check-closed-implies-landed` | closed anchor ⇒ `merged` + `merged_sha`, or explicit terminal (I5) | something closed a bead out-of-band |
| `check-gate-integrity` | gating anchors declare `check_set`; markers are a bare lane-state word (I6+I7) | a hand-written or unmigrated marker |
| `check-gate-marker-provenance` | every green lane on an open gating anchor rests on a verdict `signoff.sh` recorded — a closed approve review bead marked `gc.outcome=recorded`, or an APPROVED GitHub review (I7 depth) | a `check.<lane>=green` that resolves to no backing verdict, or an approve verdict whose outcome was never recorded |
| `check-step-terminal` | no offerable step under a closed root; no stalled frontier (I8) | a workflow died mid-molecule |
| `check-pour-text-current` | a running molecule executes the formula text that is current when it runs (I9) | a rig checkout lagging past the reconciler's self-heal window, an unfetched remote-tracking ref, or a formula edited after a live molecule was poured |
| `check-cadence-live` | every pack order fired within its interval (I10) | order not registered for a rig, or the controller is down |
| `check-claim-advancing` | every step a pool should run is advancing: a claimed step is held by a running session still producing output, and an offered step has been claimed (I11) | a claimed step whose holder is gone or stalled past the bound, or a routed open step a live pool session leaves unclaimed |
| `check-root-advancing` | a started workflow root is still advancing or reachable: no in_progress `gc.kind=workflow` root sits with a dead session, unlanded work, and an unclaimable — unrouted AND unowned — executable frontier (I13) | a molecule drained mid-flight, and its inline steps have no owner and no route, so orphan recovery and the pool both pass over them |
| `check-config-bound` | prompts/overlays/fragments resolve in the composed config | a rename that missed a reference |
| `check-seed-audit-current` | `generated/seed-audit/` matches its inputs (warn-only if absent) | a prompt input moved without a re-render |
| `check-recycle-capable` | cycle-recycle can fire: a Stop event reaches the hook with its stdin intact, the hook's own `--measure` reads a transcript's context size, and no refinery defer guard is latched | the Stop wiring stopped passing the hook its stdin, the transcript shape moved under the measurement, or an uncommitted tracked file has latched the refinery's git-op guard |
| `check-wisp-cascade-intact` | every bead store carries the four `ON DELETE CASCADE` foreign keys from the wisp auxiliary tables into `wisps(id)` | a store whose schema migration recorded the constraints as applied without adding them, leaving it to accumulate auxiliary rows no wisp reaches |
| `check-session-store-scope` | a live agent's store environment names only its own rig's scope, in both the running pane and the warm-respawn environment | a global store key the tmux server holds reaching the next respawned session, so one agent reads another rig's store |
| `check-blocked-work-armed` | every blocked, unassigned plain-work bead carries a dispatch path — `gc.routed_to` or a `gc.dispatch_when_ready` arm (warn-only) | a blocked work bead with no route and no arm, so it strands when its blocker closes and no pool is offered it |
| `check-visit-outcome-recorded` | every CLOSED visit records the `gc.outcome` it closed on, so the board can report the finished sitting (warn-only) | a visit closed with no outcome, so a dropped need reads identically to a correct dedup close |
| `check-armed-dispatch-owed` | every bead armed with `gc.dispatch_when_ready` whose `blocks` edges have all closed was slung within the deferred-dispatch cadence (warn-only) | the deferred-dispatch order not firing, or an arm set at a non-open status that `bd ready` never surfaces |
| `check-feedback-routing-owed` | an open anchor whose PR posture is `commented`/`changes_requested` has that feedback routed within the owed window (warn-only) | the merge cadence's feedback arm not routing, so operator feedback reads as consumed while nothing acts on it |
| `check-hq-marooned-work` | no rig-workable bead sits unclaimed in the HQ (city/lx) store, which no pool reads | a city-scoped role with `GC_RIG` unset filing a bare `bd create` into the HQ store, marooning the work by construction |
| `check-demo-toolchain` | the demo:capture toolchain — Node, Chromium, ffmpeg, and `OPENAI_API_KEY` — is resolvable (readiness, warn-only) | a missing demo dependency, so a capture degrades to a silent, captioned clip |

`gc doctor --verbose` explains any failure; `gc doctor --fix` applies the
canonical remediation where one exists.

Each check holds one deadline for its whole run and gives every probe only
the time left before it, so a slow or wedged data plane costs findings
rather than the whole check: a probe that no longer fits is refused, the
store behind it is reported as NOT checked, and the check says the budget
ended the run. Read that as partial — an arm skipped for time is not an arm
that passed.

That deadline is 60s, matching `--check-timeout`'s default. The flag sizes
the doctor's own abandon timer and is not passed to the checks, so raising
it on a loaded host means exporting the same number of whole seconds as
`GC_DOCTOR_CHECK_TIMEOUT` too:

```bash
GC_DOCTOR_CHECK_TIMEOUT=120 gc doctor --check-timeout 120s
```

### `gc config show`

```bash
gc config show | grep -E '^\[\[agent\]\]|^name ='
```

Confirm the native roster is present — `polecat`, `polecat-codex`,
`refinery`, `witness`, `deacon`, `dog`, `converse-opus`, `converse-fable`,
`converse-codex`, `mechanik` — with no gastown entries.

### First render of the seed audit

`generated/seed-audit/` ships empty; render it once per clone, which also
wires the pre-commit hook that keeps it current:

```bash
assets/scripts/render-seed-audit.sh --install-hook
```

Until then `check-seed-audit-current` warns rather than errors.

The hook keeps a branch current against its own base, which is not the same as
keeping the landing branch current: the artifact is rendered from the whole
source tree, so a PR whose render predates a prompt input the base has since
gained lands over that input. `merge.sh` refuses such a merge, using
`render-seed-audit.sh --check-merge` over the tree `git merge-tree` writes, so
merges on this rig need git 2.38 or newer.

### Smoke test

```bash
gc start
gc session new mechanik
gc session attach mechanik
```

If the mechanik session comes up with the gc-toolkit prompt header, the
import composed correctly.

---

## Gotchas

- **`source` paths are city-root-relative**, not rig-root-relative.
- **Rig names must differ in their first two letters** — the bead prefix is
  auto-derived, so set explicit `prefix` values for similar names.
- **`pack.toml` vs `city.toml`.** Pack-level config (defaults, `[global]`
  hooks) goes in the city root `pack.toml`; per-rig wiring (`[[rigs]]`,
  `[rigs.imports.*]`, `[[rigs.patches]]`, `[[rigs.overrides]]`) goes in
  `city.toml`.
- **Merged is not live until the checkout syncs.** `reconcile-rig-checkouts`
  fast-forwards each rig checkout every 15 minutes; a just-merged pack change
  is not what the runtime executes until then (see
  [refinery-merge-cadence.md](refinery-merge-cadence.md), *Adjacent order*).
