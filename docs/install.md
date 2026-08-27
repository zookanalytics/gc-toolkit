# Installing gc-toolkit

> Reference for wiring `gc-toolkit` into a Gas City. Assumes a working Gas
> City install (`gc version` returns a version) and a city created with
> `gc init`.

gc-toolkit ships a **native agent roster** — polecat, refinery, witness,
deacon, converse, mechanik, polecat-codex, proactive — declared in its own
`pack.toml`. It imports nothing: there are no gastown prerequisites, no
transitive imports, and no agent patches to wire.

Covered here:

1. [Importing gc-toolkit](#1-importing-gc-toolkit)
2. [The mechanik named session](#2-the-mechanik-named-session)
3. [Sub-pack opt-in: gascity-keeper](#3-sub-pack-opt-in-gascity-keeper)
4. [The helm board service](#4-the-helm-board-service)
5. [Verification](#5-verification)

For Gas City background, see [`gascity-reference.md`](gascity-reference.md).

---

## 1. Importing gc-toolkit

gc-toolkit is a **rig-scope pack**, and its city-scope half ships as the
sibling sub-pack `packs/gc-toolkit-city`. A complete install imports both: the
core pack on each rig, the sub-pack once at the city. Importing gc-toolkit
itself at city scope meets its five rig-scope orders with a registration
nothing can claim, and `gc` drops each one with a warning on every invocation.

### Per-rig import

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

### The city-scope companion

```toml
# pack.toml (city root)
[imports.gc-toolkit-city]
source = "rigs/gc-toolkit/packs/gc-toolkit-city"
```

Two things need a city-scope registration, and this is where they live:

- **`dog`** — the warrant-executor pool, the only path to a kill
  ([`authority-map.md`](authority-map.md)). Its bare name collides with the
  city-scope `dog` the `bd` pack ships, and a collision drops one of the two
  silently, so only an import-qualified registration keeps both. It answers to
  `gc-toolkit-city.dog`; the patrols address it through the `warrant_route`
  formula var, which defaults to that. Bind the sub-pack under another name and
  you must pass the new address as `warrant_route` when pouring
  `mol-deacon-patrol`, `mol-witness-patrol` and `mol-dog-shutdown-dance`.
- **The `session_live` hooks** — the tmux `S` session-picker binding and the
  gc-toolkit status line. A city-scope pack's `[global]` reaches every agent in
  the city; declared on a rig-scope pack it would reach only that rig's agents,
  leaving the city-scope ones (`deacon`, `mechanik`, `dog`) without them.

`mol-dog-shutdown-dance` ships here too. Formula search paths are
scope-layered, so a city-scope agent searches city-pack formulas alone and the
dog cannot resolve a copy that lives in the rig-scope pack. Every rig still
reaches this one, because a rig's layers start with the city's.

Skip the sub-pack and everything else still composes — you lose the kill path
and the tmux chrome, and nothing reports an error.

### What the import brings in

- **The roster** — worker pools (`polecat`, and `polecat-codex` on the
  codex provider), patrols (`refinery`, `witness`, `deacon`), conversation
  role (`converse`), and `proactive` (always-on, 2-slot). `dog` comes from the
  city-scope sub-pack above.
- **The lifecycle** — `lifecycle/lifecycle.toml` (states, transitions,
  metadata registry) and the single transition writer
  `assets/scripts/lifecycle.sh`.
- **Orders** — the merge cadence (`refinery-reconcile`, 60s, rig-scoped),
  `deferred-dispatch`, `liveness-sweep`, `reconcile-rig-checkouts`,
  `boot-health`, `quota-park-nudge`, `helm-build`, and the feedback
  miner/distiller.
- **Skills** — surfaced via `gc skill list` (`gc-toolkit.handoff`,
  `gc-toolkit.session-title`, …).
- **Doctor checks** — the nine structural checks verified below.

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

Declare this one inside a `[[rigs]]` block, never at the city level, or every
rig picks it up. Import scope follows what a sub-pack contains, not the fact
that it is a sub-pack — `gc-toolkit-city` is city-scope for the reasons given
in section 1.

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

The pack's nine checks, and what a failure means:

| Check | Asserts (invariant) | First-failure cause |
|---|---|---|
| `check-state-space` | every `merge_result`/status combo is declared in `lifecycle.toml` (I2) | a writer minted an undeclared state |
| `check-routed-work-claimable` | every route and assignee names a live target; rig-scoped orders bound (I3) | a pool renamed, or an order missing its rig registration |
| `check-one-anchor-per-pr` | one open owning anchor per PR (I4) | duplicate anchors filed for one branch |
| `check-closed-implies-landed` | closed anchor ⇒ `merged` + `merged_sha`, or explicit terminal (I5) | something closed a bead out-of-band |
| `check-gate-integrity` | gating anchors declare `check_set`; markers are well-formed `verb@oid` (I6+I7) | a hand-written or truncated marker |
| `check-step-terminal` | no open step under a closed root; no stalled frontier (I8) | a workflow died mid-molecule |
| `check-cadence-live` | every pack order fired within its interval (I10) | order not registered for a rig, or the controller is down |
| `check-config-bound` | prompts/overlays/fragments resolve in the composed config | a rename that missed a reference |
| `check-seed-audit-current` | `generated/seed-audit/` matches its inputs (warn-only if absent) | a prompt input moved without a re-render |

`gc doctor --verbose` explains any failure; `gc doctor --fix` applies the
canonical remediation where one exists.

### `gc config show`

```bash
gc config show | grep -E '^\[\[agent\]\]|^name ='
```

Confirm the native roster is present — `polecat`, `polecat-codex`,
`refinery`, `witness`, `deacon`, `dog`, `converse`, `mechanik` — with no
gastown entries.

### First render of the seed audit

`generated/seed-audit/` ships empty; render it once per clone, which also
wires the pre-commit hook that keeps it current:

```bash
assets/scripts/render-seed-audit.sh --install-hook
```

Until then `check-seed-audit-current` warns rather than errors.

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
- **Moving an existing install off a city-scope `gc-toolkit` import is one
  edit, not two steps.** A directory-imported pack is live from the working
  tree and `reconcile-rig-checkouts` advances that checkout every 15 minutes,
  so a pack that has split its city-scope half will apply itself before anyone
  edits `pack.toml`. Between the two you have no `dog` and no `session_live`
  hooks on any agent, and nothing reports it. Swap the import in the same
  change that takes the pack.
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
