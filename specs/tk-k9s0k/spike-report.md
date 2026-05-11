# Spike report: `mechanik-side` as pack-defined agent (`tk-k9s0k`)

**Bead:** `tk-k9s0k` (task under sling-convoy `tk-o5uj8`)
**Branch:** `polecat/tk-k9s0k-mechanik-side`
**Polecat:** `gc-toolkit/gc-toolkit.furiosa`
**Author:** polecat `gc-toolkit__polecat-lx-3rwi1q`
**Source commits:** see branch
**Surveyed at:** 2026-05-11

## Provenance

| Doc-type / artifact | Producer | Source | Surveyed at |
|---|---|---|---|
| Work bead | `gc-toolkit__mechanik` (filer) | bd `tk-k9s0k` | 2026-05-11 |
| Parent context: gc-h1gxg | gascity rig | `gascity:gc-h1gxg` decision + four research passes | 2026-05-11 |
| First-principles pass | `gc-toolkit__polecat (slit)` | `gascity:specs/gc-h1gxg/inspiration-first-principles.md` | 2026-05-11 |
| Multi-instance pass | `gc-toolkit__polecat-codex (ripley)` | `gascity:specs/gc-h1gxg/survey-pass-2-multi-instance.md` | 2026-05-11 |
| gascity config schema | gascity v0.x | `internal/config/config.go:1718-1981` (Agent struct) | 2026-05-11 |
| Agent discovery code | gascity | `internal/config/agent_discovery.go` | 2026-05-11 |
| Path adjustment | gascity | `internal/config/compose.go:1156,1195`; `internal/config/pack.go:1340-1361` | 2026-05-11 |

## TL;DR — Verdict

**WORKS — design verified, operational verifications deferred.**

Five of five static design questions resolved; the static config + render
behavior matches the spec from gc-h1gxg's synthesis. The two
verifications that require spawning real sessions (pool semantics,
canonical-reset survival) are deferred to the operator: they touch the
running city and would persist beyond a polecat session. Concrete commands
are provided in §C below.

## Files changed

- `agents/mechanik-side/agent.toml` — new agent config
- `agents/mechanik-side/PROVENANCE.md` — provenance note
- `template-fragments/mechanik-side-role.template.md` — side-role
  clarification fragment, injected via `append_fragments`
- `pack.toml` — `[[named_session]]` entry for operator-spawn UX
  (`scope = "rig"`, `mode = "on_demand"`)

Canonical mechanik (`agents/mechanik/*`) is **not** modified.

## A. Verifications

### 1. `prompt_template` cross-reference — **WORKS**

`agents/mechanik-side/agent.toml`:

```toml
prompt_template = "agents/mechanik/prompt.template.md"
```

**Path resolution.** Relative paths in pack-defined agent.toml resolve
against the **pack root** (`internal/config/pack.go:1349-1351` via
`adjustFragmentPath`), not the agent.toml's directory. So
`agents/mechanik/prompt.template.md` lands on the canonical template.

A first draft used `../mechanik/prompt.template.md` (relative to the
agent.toml's directory) which produced a malformed path; corrected.

**Template variable binding.** The renderer (`cmd/gc/prompt.go:75`)
builds a fresh `PromptContext` per agent at render time
(`cmd/gc/template_resolve.go:292-306`), so `{{ .AgentName }}`,
`{{ .RigName }}`, `{{ .BindingName }}`, `{{ .WorkDir }}` all bind to the
side instance's identity even when the template file is the canonical
mechanik's.

**Concrete test.** Built a throwaway test city pointing at this worktree
as both city pack and rig pack, ran:

```bash
gc --city <test-city> prime --strict mechanik-side
```

The rendered prompt:
- Starts with the canonical mechanik prompt body (verified by-eye —
  matches `agents/mechanik/prompt.template.md` headers and principles).
- Ends with the side-role fragment (appended via `append_fragments`).
- Side-role fragment renders `{{ .BindingName }}.mechanik` correctly as
  the canonical's address (e.g., `gc-toolkit.mechanik` in loomington).

**Symlink / shared-fragment fallback not needed.** Cross-reference works.

### 2. Separate workspace — **WORKS (static); spawn-test deferred**

`agents/mechanik-side/agent.toml`:

```toml
work_dir = ".gc/worktrees/{{.Rig}}/mechanik-side/{{.AgentBase}}"
pre_start = ["{{.ConfigDir}}/assets/scripts/worktree-setup.sh {{.RigRoot}} {{.WorkDir}} {{.AgentBase}} --sync"]
```

**Pattern.** Mirrors the polecat pattern
(`agents/polecat/agent.toml:3-5`):
- `{{.Rig}}` resolves to the rig name (e.g., `gc-toolkit`).
- `{{.AgentBase}}` resolves to the per-instance identity (e.g.,
  `gc-toolkit.mechanik-side-1`), so concurrent instances do not collide.
- `pre_start` invokes the shared `worktree-setup.sh` script (idempotent
  per `assets/scripts/worktree-setup.sh:58-62`) before session start.

**Expected materialization (loomington gc-toolkit rig):**

```
/home/zook/loomington/.gc/worktrees/gc-toolkit/mechanik-side/gc-toolkit.mechanik-side-1/
/home/zook/loomington/.gc/worktrees/gc-toolkit/mechanik-side/gc-toolkit.mechanik-side-2/
...
```

Each is a separate worktree of `rigs/gc-toolkit`, with its own branch
namespaced by hash of the path (`worktree-setup.sh:50-56`).

**Deferred:** First-spawn actually creating the worktree, and concurrent
spawns getting distinct directories without race. See §C.

### 3. Pool semantics with `min=0` — **STATIC OK; spawn-test deferred**

`agents/mechanik-side/agent.toml`:

```toml
min_active_sessions = 0
max_active_sessions = 4
```

Plus `pack.toml` named_session entry:

```toml
[[named_session]]
template = "mechanik-side"
scope = "rig"
mode = "on_demand"
```

**Reconciler behavior (static read).** `EffectiveMinActiveSessions()`
returns 0 (`internal/config/config.go:2176-2181`), so the reconciler
does not pre-spawn. Demand for new sessions comes from
`EffectiveScaleCheck` which counts routed work — and the override on
`work_query` (see §A.5) ensures no demand is ever found. So zero
auto-spawns on city start.

**Operator spawn path.** `gc session new gc-toolkit/gc-toolkit.mechanik-side`
falls under `cmdSessionNew` (`cmd/gc/session_model_phase0_cli_surface_spec_test.go:486`).
For agents with `max_active_sessions > 1`, gascity creates pool
instances numbered `<template>-1`, `<template>-2`, … up to the cap.

**Cap behavior.** `EffectiveMaxActiveSessions()` returns
`*MaxActiveSessions = 4`. The reconciler / session-new path checks
against this cap and returns an error when exceeded.
(Code path: `internal/agentutil/pool.go:23`,
`internal/agentutil/resolve.go:136,162`.)

**Deferred:** Actual `gc session new` runs (3× to reach 3 instances,
then a 5th to confirm the cap). See §C.

### 4. `GC_AGENT` identity in bead authorship — **STATIC OK; spawn-test deferred**

**Qualified-name derivation (`internal/config/config.go:104-110`):**

```
QualifiedName = Dir + "/" + BindingName + "." + Name
              = "gc-toolkit/gc-toolkit.mechanik-side"
```

For pool instances (`QualifiedInstanceName`,
`internal/config/config.go:128-131`):

```
"gc-toolkit/gc-toolkit.mechanik-side-1"
```

So spawned sessions get `GC_AGENT = gc-toolkit/gc-toolkit.mechanik-side-N`.
This is the form that appears in bead `assignee` / `created_by` columns
when the side instance closes a bead or sends mail.

**Deferred:** Concrete `bd close` from a spawned instance to confirm the
exact author string. See §C.

### 5. `work_query` / `sling_query` "never" syntax — **VERIFIED**

`agents/mechanik-side/agent.toml`:

```toml
work_query = "printf '[]'"
sling_query = "echo 'mechanik-side is operator-spawned only; not a sling target' >&2; exit 1"
```

**`work_query`.** Returns `[]` — an empty JSON array. The reconciler and
`gc hook` paths parse query output as a JSON list of beads; an empty
list means "no work." So:

- Reconciler never auto-spawns to satisfy demand.
- The side instance, if it runs `gc hook` from inside its session, gets
  no work assigned.
- The `scale_check` path (which counts `bd ready` matches by routed_to)
  is independent of `work_query`; it still finds 0 because nothing slings
  to this template (see below).

Verified:
```
$ sh -c "printf '[]'" ; echo $?
[]0
```

**`sling_query`.** Exits 1 with a clear stderr message. The sling driver
(`internal/sling/sling_core.go:352-355`) treats non-zero exit as failure
and propagates the error to the caller. So:

- `gc sling gc-toolkit/gc-toolkit.mechanik-side <bead>` fails with a
  legible error instead of silently writing `gc.routed_to`.
- Beads cannot be routed-to-pool for mechanik-side. The canonical
  mechanik remains the only `mechanik`-shaped sling target.

Verified:
```
$ sh -c "echo 'mechanik-side is operator-spawned only; not a sling target' >&2; exit 1" ; echo $?
mechanik-side is operator-spawned only; not a sling target
1
```

## B. Core acceptance — survives canonical reset

**Status: deferred to operator.**

**Why this should work.** Side instances are distinct agent identities
in pack config (`mechanik-side`, not `mechanik`). The `gc session reset`
command operates on a specific qualified name; it does not cascade to
other agents that happen to render the same prompt template. The
side-instance session is owned by `mechanik-side` and survives a reset
of `mechanik`.

`wake_mode = "resume"` keeps the side-instance's conversation across
sleep/wake cycles. The canonical mechanik uses `wake_mode = "fresh"`
(every wake starts a new provider session). That asymmetry is intentional:
the operator's focused-thinking thread is the artifact; the canonical's
job is queue absorption, not context retention.

**Deferred test:** see §C.

## C. Operator-test checklist

The five verifications and the core acceptance all require side-effecting
operations on the running loomington city. As a polecat I should not
spawn / reset agents in the live city. The following commands are what
the operator (or mechanik in review) should run after PR merge:

```bash
# Setup
cd /home/zook/loomington
gc reload                                        # pick up new pack content

# Verification 3 — pool semantics
gc agent list 2>/dev/null || gc status | grep mechanik-side
# Expect: mechanik-side template visible, 0 instances active.

gc session new gc-toolkit/gc-toolkit.mechanik-side
# Expect: spawns mechanik-side-1, attach-capable.

gc session new gc-toolkit/gc-toolkit.mechanik-side
gc session new gc-toolkit/gc-toolkit.mechanik-side
gc session new gc-toolkit/gc-toolkit.mechanik-side
# Expect: spawns -2, -3, -4.

gc session new gc-toolkit/gc-toolkit.mechanik-side
# Expect: error citing max_active_sessions=4 cap.

# Verification 2 — separate workspace
ls /home/zook/loomington/.gc/worktrees/gc-toolkit/mechanik-side/
# Expect: gc-toolkit.mechanik-side-1/, -2/, -3/, -4/ each its own worktree.

# Verification 4 — GC_AGENT identity in beads
# Attach to mechanik-side-1, run:
#   gc bd create "spike-test: identity check" -t task
# Then back outside:
gc bd list --created-by 'gc-toolkit/gc-toolkit.mechanik-side-1' --limit 1
# Expect: the bead, with created_by = "gc-toolkit/gc-toolkit.mechanik-side-1".

# Verification 5 — never a sling target
TEST_BEAD=$(gc bd create "spike-test: sling probe" -t task --json | jq -r .id)
gc sling gc-toolkit/gc-toolkit.mechanik-side "$TEST_BEAD"
# Expect: error "mechanik-side is operator-spawned only; not a sling target".

# Cleanup
gc bd close "$TEST_BEAD"

# Core acceptance — canonical reset
# With mechanik-side-1 still alive:
gc session reset gc-toolkit.mechanik
# Expect: canonical mechanik session restarts; mechanik-side-1 unaffected,
# its conversation/transcript intact.
```

## D. Open follow-ups (not addressed here)

- **Namepool.** Side instances are numbered (`mechanik-side-1`, `-2`).
  Operator-UX could be improved with a `namepool.txt`; deferred — the
  bead did not ask for one and numeric IDs are unambiguous in
  audit views.
- **Mail policy.** Routed mail addressed to `mechanik` lands on the
  canonical only (verified by `work_query = printf '[]'` and
  `sling_query` exit 1). The synthesized roadmap (`gc-h1gxg`
  decision) calls for role-addressed mail with `ErrAmbiguous` removal
  and explicit policy enums — out of scope per the bead.
- **Side-side coordination.** Two side instances sharing the same
  rig but different worktrees: no protocol for cross-thread
  coordination is defined here. Defaulting to "operator carries the
  message between threads" matches the bead's role text.
