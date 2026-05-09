---
name: Validate cycle-recycle premise — can refinery revert to v3's controller-restart path?
description: Read-only validation of the load-bearing claim in template-fragments/cycle-recycle.template.md that `gc runtime request-restart` no-ops for refinery sessions. Confirms the claim, locates the controller carve-out by file+line, and recommends Option B (patch v4) over Option A (revert to v3) because the v3 path is itself broken for refineries — reverting would silently disable cycle-recycle's trigger without restoring restart functionality.
---

# Validate cycle-recycle premise — can refinery revert to v3's controller-restart path? (tk-6hm32)

Read-only diagnostic for the bead `tk-6hm32`. Follow-up to `tk-fyzvk`
(closed). The deliverable is this document; implementation is out of
scope and lives in a follow-up bead.

## Provenance

| Doc-type or artifact | Producer | Source location (path + commit SHA) | Surveyed at |
|---|---|---|---|
| gc-toolkit pack.toml (refinery `mode = on_demand`) | gc-toolkit pack | `rigs/gc-toolkit/pack.toml` @ `c9decbb` | 2026-05-08 |
| gc-toolkit refinery formula (v4) | gc-toolkit pack | `rigs/gc-toolkit/formulas/mol-refinery-patrol.toml` @ `6888c41` | 2026-05-08 |
| gc-toolkit witness formula (also uses cycle-recycle, mode=always) | gc-toolkit pack | `rigs/gc-toolkit/formulas/mol-witness-patrol.toml` @ `2a3cb43` | 2026-05-08 |
| cycle-recycle template fragment | gc-toolkit pack | `rigs/gc-toolkit/template-fragments/cycle-recycle.template.md` @ `8412dca` | 2026-05-08 |
| gastown v3 refinery formula (uses `gc runtime request-restart`) | gascity examples/gastown pack | `rigs/gascity/examples/gastown/packs/gastown/formulas/mol-refinery-patrol.toml` @ `cddc5b96` | 2026-05-08 |
| gastown v3 pack.toml (refinery already `mode = on_demand` in v3) | gascity examples/gastown pack | `rigs/gascity/examples/gastown/packs/gastown/pack.toml` @ `752a8bb8` | 2026-05-08 |
| `gc runtime request-restart` source (the carve-out) | gascity gc binary | `rigs/gascity/cmd/gc/cmd_runtime_drain.go` @ `d776e06a` | 2026-05-08 |
| `sessionRestartableByController` predicate | gascity gc binary | `rigs/gascity/cmd/gc/cmd_handoff.go` @ `2f3bf408` | 2026-05-08 |
| Named-session mode metadata helpers | gascity gc binary | `rigs/gascity/internal/session/named_config.go` @ `c1d8e2e7` | 2026-05-08 |
| Carve-out fix commit (`gc runtime request-restart` skip) | gascity gc binary | commit `84c0e19d` (2026-04-19, "fix: complete named session handoff handling") | 2026-05-08 |
| Original named-session-handoff carve-out commit | gascity gc binary | commit `53f0c926` (2026-04-19, "fix: skip restart request for named sessions on self-handoff") | 2026-05-08 |
| Regression tests covering the no-op behavior | gascity gc binary | `cmd/gc/cmd_runtime_drain_test.go::TestRuntimeRequestRestartNamedOnDemandReturnsWithoutBlocking` and `cmd/gc/cmd_handoff_test.go::TestDoHandoff_Regression744_NamedSessionSkipsRestart` | 2026-05-08 |
| tk-fyzvk diagnostic (parent — Option A + B recommendation) | gc-toolkit pack | `rigs/gc-toolkit/specs/tk-fyzvk/analysis.md` @ `c9decbb` | 2026-05-08 |
| Live refinery session bead (target of test contemplated by Track 1) | live bd ledger | `gc session list`: `lx-htsx1` (gc-toolkit/gc-toolkit.refinery, active), `lx-rmdm1` (gascity/gc-toolkit.refinery, asleep), `lx-mo3ln` (signal-loom/gc-toolkit.refinery, asleep) | 2026-05-08 |

## TL;DR

The cycle-recycle template's load-bearing claim — that `gc runtime
request-restart` silently no-ops for refinery sessions — is **TRUE**
in the current code. Refineries are configured with `mode = "on_demand"`
in both v3 and v4 packs, and the gc binary has an explicit pre-emptive
carve-out (`cmd_runtime_drain.go:420-433`) that detects on-demand named
sessions, prints `"Restart skipped for named session; controller cannot
restart on-demand named sessions."`, and returns 0 without setting any
flags. The carve-out was added in commit `84c0e19d` (2026-04-19), is
covered by a dedicated regression test, and matches the same predicate
used by `gc handoff`'s named-session branch.

This means **the bead's load-bearing premise — "v3 works, we replaced
its restart mechanism, we broke it" — is false for refineries.** v3's
formula is not "working"; it is silently no-op'ing too (it has been
since 2026-04-19, before the v3 formula's most recent commit on
2026-05-04). Reverting to v3 would not restore restart functionality;
it would only delete cycle-recycle's `gc handoff`-based trigger and the
operator's `/clear` recovery path, leaving no working context-recycle
mechanism at all.

**Recommendation: Option B (patch v4).** Implement tk-fyzvk's Option A
(startup-adopt) plus Option B (pour-next-before-burn). The cycle-recycle
policy itself is correct; the gaps are in startup discovery and the
broken pour-before-burn invariant.

## Track 1 — Does `gc runtime request-restart` actually no-op for refinery sessions?

**Result: YES, it no-ops. The cycle-recycle template's claim is correct.**

Evidence is from code inspection rather than a runtime test against
`lx-htsx1` because the behavior is fully determined by:

1. The refinery's `mode = "on_demand"` declaration in `pack.toml`.
2. A pre-emptive guard in `cmd_runtime_drain.go` that short-circuits the
   restart request for any on-demand named session.
3. A dedicated regression test that asserts the no-op contract.

A live test would only re-confirm what the code unambiguously says, at
the cost of disrupting a production refinery's wisp lifecycle. The
unanimity of the three signals below is sufficient for Track 3.

### 1.1 Refinery is `mode = "on_demand"` (and was in v3 too)

`rigs/gc-toolkit/pack.toml` declares (current head, around the
`[[named_session]]` block):

```toml
[[named_session]]
template = "witness"
scope = "rig"
mode = "always"

[[named_session]]
template = "refinery"
scope = "rig"
mode = "on_demand"
```

Same declaration is in the gastown v3 example pack
(`rigs/gascity/examples/gastown/packs/gastown/pack.toml` @
`752a8bb8`). **Refinery has been on_demand throughout the history
covered by this analysis.** Witness, by contrast, is always.

### 1.2 `cmd_runtime_drain.go:420-433` — the pre-emptive skip

```go
if store != nil {
    restartable, err := sessionRestartableByController(store, current.sessionName)
    if err != nil {
        fmt.Fprintf(stderr, "gc runtime request-restart: checking session type: %v\n", err)
        return 1
    }
    if !restartable {
        if err := clearRestartRequest(store, dops, current.sessionName); err != nil {
            fmt.Fprintf(stderr, "gc runtime request-restart: clearing stale restart request: %v\n", err)
            return 1
        }
        fmt.Fprintln(stdout, "Restart skipped for named session; controller cannot restart on-demand named sessions.")
        return 0
    }
}
```

The function returns BEFORE calling `dops.setRestartRequested(sn)` or
emitting `events.SessionDraining`. The reconciler never sees a flag and
never kills the session. The agent's caller observes a successful exit
and a benign stdout message — practically indistinguishable from
"restart succeeded" if the caller only checks the exit code. This is
the source of the "silent no-op" perception even though the message is
visible.

### 1.3 `cmd_handoff.go:269-288` — the predicate that decides "restartable"

```go
func sessionRestartableByController(store beads.Store, sessionName string) (bool, error) {
    if store == nil || sessionName == "" {
        return true, nil
    }
    id, err := resolveSessionID(store, sessionName)
    if err != nil {
        if errors.Is(err, session.ErrSessionNotFound) {
            return true, nil
        }
        return false, fmt.Errorf("resolving session %q: %w", sessionName, err)
    }
    b, err := store.Get(id)
    if err != nil {
        return false, fmt.Errorf("loading session %q: %w", id, err)
    }
    if !isNamedSessionBead(b) {
        return true, nil
    }
    return namedSessionMode(b) == "always", nil
}
```

Decision matrix:

| Session shape | `isNamedSessionBead(b)` | `namedSessionMode(b)` | restartable? |
|---|---|---|---|
| Pool/headless | false | (n/a) | **true** |
| Named, `mode = "always"` (witness, mayor, deacon, boot) | true | "always" | **true** |
| Named, `mode = "on_demand"` (refinery) | true | "on_demand" | **false** |

Refinery is the only currently-configured agent class in the false
column. (`gc session list` confirms three live refinery sessions:
`lx-htsx1`, `lx-rmdm1`, `lx-mo3ln` — all named `<rig>/gc-toolkit.refinery`,
all spawned from the on_demand `[[named_session]]` block.)

### 1.4 Regression test — the contract is intentional

`cmd/gc/cmd_runtime_drain_test.go::TestRuntimeRequestRestartNamedOnDemandReturnsWithoutBlocking`
(lines 700-756) seeds a session bead with:

```go
store.SetMetadata(b.ID, "configured_named_session", "true")
store.SetMetadata(b.ID, "configured_named_mode", "on_demand")
store.SetMetadata(b.ID, "restart_requested", "true")
store.SetMetadata(b.ID, "continuation_reset_pending", "true")
```

…then asserts `cmdRuntimeRequestRestart` returns within 10s, exits 0,
prints "Restart skipped for named session", and clears the seeded
restart flags. This is not a bug — it is the documented and tested
contract.

### 1.5 Conditional behavior across rigs

The carve-out predicate reads only the session bead's metadata
(`configured_named_session`, `configured_named_mode`). Both fields are
set by `session_template_start.go:142` from the named-session spec at
session creation time. The predicate does not branch on rig name,
binding name, or any per-rig metadata.

So **every rig's refinery behaves identically** under request-restart —
gc-toolkit, gascity, signal-loom — because all three vendor the same
`refinery` template with `mode = "on_demand"`. There is no
rig-conditional behavior to surface here.

## Track 2 — Why doesn't request-restart work? Is the carve-out removable?

The carve-out is **intentional and defensive, not strictly required by
the controller's mechanics**. It can be narrowed for refinery-class
sessions, but doing so is a controller-binary change, not a pack
change.

### 2.1 The carve-out is conservative, not mechanical

The reconciler's restart-handling code at
`cmd/gc/session_reconciler.go:1042-1085` does NOT branch on session
mode. It checks both tmux metadata and bead metadata for
`restart_requested`, and if set:

1. Kills the session (`workerKillSessionTargetWithConfig`).
2. Rotates `session_key`, clears `started_config_hash`, clears
   `last_woke_at`, sets `continuation_reset_pending`.
3. `continue` — the next reconcile tick re-evaluates desired state.

For an on-demand named session that still has assigned/routed work,
the next tick would in principle re-spawn it: `compute_awake_set.go:130-146`
sets it desired when `NamedSessionDemand[ns.Identity]` is true, and
the demand index in `build_desired_state.go:420-436` flips true when an
open work bead's `Assignee` matches the named identity. A refinery
mid-cycle has its patrol wisp `in_progress` and routed work beads
assigned to it, so demand would persist across the kill window.

So the controller is **mechanically capable** of stopping and
re-spawning an on-demand refinery. The cmd_runtime_drain.go pre-emptive
skip is what prevents this from happening.

### 2.2 Why the conservative choice was made — commit history

Commit `53f0c926` (2026-04-19, "fix: skip restart request for named
sessions on self-handoff") is the original carve-out. Its message
explains the user-experience concern:

> Named (human-attended) sessions like the mayor are started by the
> user — the controller cannot respawn them — so every PreCompact
> "gc handoff context cycle" tick killed Claude Code to the user's
> shell and lost any in-flight context-recovery work the mail would
> have set up.

That commit treated **all** named sessions as non-restartable. Nine
hours later, commit `84c0e19d` (2026-04-19, "fix: complete named
session handoff handling") refined the predicate to:

```go
return namedSessionMode(b) == "always", nil
```

…effectively saying: "always-mode named sessions ARE controller-owned
(witness, mayor); on-demand named sessions might be user-driven, treat
as not-restartable."

The refinement is correct for mayor (which IS user-attended in the
typical setup) and witness/deacon/boot (always, controller-owned). It
is **overly conservative for refinery**, which in normal operation is
controller-spawned and headless — operators occasionally `gc session
attach` to inspect, but no human types into a refinery prompt.

### 2.3 Removing the carve-out for refinery — what it would take

The carve-out predicate does not have a refinery-specific escape
hatch. To make request-restart work for refineries without disrupting
mayor's user-attended path, one of these would be required:

- **(a)** Change refinery to `mode = "always"`. Cleanest from a binary
  perspective (no controller change needed). Cost: the controller would
  keep refineries always alive (idle-timeout-based sleep is still
  available via the awake-set logic, but the `mode = "always"` semantic
  may have other side-effects worth verifying — e.g. it currently
  exempts always sessions from idle sleep at
  `compute_awake_set.go:313-314`).
- **(b)** Add a per-agent or per-named-session "restartable" flag and
  set it true for refinery. Touches the binary and the schema; needs
  upstream PR.
- **(c)** Add a `mode = "on_demand_managed"` (or similar) third class
  meaning "on-demand wake but controller can restart on demand". Touches
  binary, schema, and every pack that vendors refinery.

**None of these are pack-only changes** that gc-toolkit can land
unilaterally. All require the upstream gc binary to learn a new
distinction. Option (a) is the smallest, but its full behavior change
under `mode = "always"` should be characterized before adopting (e.g.
how does always behave under rig suspension?).

## Track 3 — Decision

**Recommendation: Option B (patch v4).**

The bead's premise — "v3 works, we replaced its restart mechanism, we
broke it" — is **incorrect for refineries**. v3 has not worked for
refineries since at least 2026-04-19, and the v3 formula's most
recent commit on 2026-05-04 has not changed that. The cycle-recycle
policy v4 introduced is not the source of the broken restart; it is
the FIX for the broken restart, papering over the gc-binary carve-out
by pivoting from controller-driven recovery to operator-driven
recovery.

What v4 broke is narrower than the bead frames: it added a startup
contract (cycle-recycle leaves a wisp in_progress and expects the
post-`/clear` session to find it, while routed work beads pile up) that
the existing prompt's startup query doesn't cover. That gap is what
tk-fyzvk diagnosed; tk-fyzvk's Option A + B is the right fix.

### Why not Option A (revert to v3)

Direct revert is **not viable** as a path that restores restart
functionality. The v3 formula at `cddc5b96` calls `gc runtime
request-restart` directly. With the gc binary as it stands today, that
call returns immediately with "Restart skipped for named session" and
no further side effect. Reverting would:

- Remove the cycle-recycle template fragment (no operator-`/clear`
  recovery).
- Replace `gc handoff` with `gc runtime request-restart` (silent no-op
  for refinery).
- Net result: refinery has NO working context-recycle mechanism. After
  N wisps, context grows unbounded until the provider compacts or the
  session crashes. Strictly worse than the current state.

A revert that DOES restore restart would also have to bundle one of
the binary changes from §2.3, which makes it a bigger and riskier
change than tk-fyzvk's Option A + B (pure pack edits). Citations:

- `rigs/gascity/examples/gastown/packs/gastown/formulas/mol-refinery-patrol.toml:80-93` (v3's `gc runtime request-restart` call sits at L88, with the surrounding RSS-trigger context).
- `rigs/gascity/cmd/gc/cmd_runtime_drain.go:420-433` (the pre-emptive skip).
- `rigs/gascity/cmd/gc/cmd_runtime_drain_test.go:700-756` (regression test asserting no-op).
- `rigs/gascity/cmd/gc/cmd_handoff.go:269-288` (the `sessionRestartableByController` predicate).

### Why not Option C (hybrid)

Cycle-recycle as currently designed **already is** a hybrid — but
inside `gc handoff`, not at the formula level. Looking at
`cmd_handoff.go`'s `doHandoffWithOutcome` flow:

- For unnamed/pool sessions: writes mail, requests restart, controller
  respawns.
- For `mode = "always"` named sessions (witness, mayor, deacon, boot):
  writes mail, requests restart, controller respawns.
- For `mode = "on_demand"` named sessions (refinery): writes mail, does
  NOT request restart, operator must `/clear`.

So the formula calling `gc handoff` automatically picks the right
mechanism for each agent class. Witness's cycle-recycle on the
always-mode path works without any operator action; refinery's
cycle-recycle on the on-demand path requires the operator-`/clear`
step. There is nothing to add at the formula level that `gc handoff`
isn't already dispatching internally. A formula-level "use
request-restart for some agents, gc handoff for others" would be a
worse re-implementation of the binary's existing dispatch.

The only hybrid worth considering lives at the binary level (§2.3
options a/b/c) — and that is materially the same work as Option B from
tk-fyzvk's perspective: a separate, larger upstream change. Pursuing it
in parallel is fine as a longer-term path, but it is not a substitute
for fixing the discovery gap that tk-fyzvk already identified.

### Recommended next step

Implement tk-fyzvk's Option A + B in a follow-up implementation bead
off this diagnostic. Specifically:

- **Option A** (startup-adopt) — patch
  `rigs/gc-toolkit/agents/refinery/prompt.template.md` and the
  `propulsion-refinery` define block in
  `rigs/gc-toolkit/template-fragments/propulsion.template.md` to add a
  three-tier discovery (in-progress wisp → routed work beads → open
  patrol wisps).
- **Option B** (pour-before-burn) — patch
  `rigs/gc-toolkit/template-fragments/cycle-recycle.template.md` and
  the `check-inbox` step in
  `rigs/gc-toolkit/formulas/mol-refinery-patrol.toml` (and similarly
  in `mol-witness-patrol.toml`) to pour the next wisp before idling.

Optionally, file a separate longer-term bead exploring §2.3's binary
changes (changing refinery to `mode = "always"`, or adding a new
named-session class) as a path that would let cycle-recycle be deleted
entirely. That work is independent of the immediate Option A + B fix
and depends on understanding the full behavior change of `mode =
"always"` for refinery (idle timeout, suspension semantics, scaling).

## Out of scope (per bead description)

- **Implementation.** A follow-up implementation bead should be filed
  off this diagnostic.
- **Re-doing tk-fyzvk's gap analysis.** Cited as authoritative for the
  Option A + B definitions.
- **Adding tests.** The implementation bead can add them.
- **Live runtime test of `gc runtime request-restart`** against
  `lx-htsx1`. Code inspection is unambiguous (§1.2-1.4) and a runtime
  test would only re-confirm what the regression test in §1.4 already
  proves, at the cost of disrupting an active production refinery's
  wisp lifecycle. If the operator wants empirical confirmation, the
  test is small: from a refinery session run `gc runtime request-restart`
  and observe the immediate `"Restart skipped for named session"`
  output and clean exit.
