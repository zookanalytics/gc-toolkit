# Upstream audit: gc handoff vs. on-demand named-session restart

**Audit bead:** tk-fxs87
**Feeds verdict on:** tk-wv6m6 (decision: should `gc handoff` be the universal 'restart the agent' path, including for on-demand named sessions?)
**Surveyed at:** 2026-05-11
**Upstream commit surveyed:** `d11ee0e12da211d622ffe919adef69c4ce493eff` (`zookanalytics/gascity` fork, tracking `gastownhall/gascity`)

## TL;DR

The named-session restart skip in `gc handoff` is **deliberate refusal**, codified in upstream PR #927 (#744 regression). The stated rationale — "the controller cannot restart the user-attended process" — is **technically misleading by today's code**: `gc session reset` exercises exactly the same `RequestFreshRestart` machinery against on-demand named sessions and works. The reconciler's restart-request handler at `cmd/gc/session_reconciler.go:1042-1086` is mode-agnostic. The standing intent of the refusal is best read as a *policy* against auto-restart of operator-attached processes during hook contexts (PreCompact especially), not a missing capability. There is **no open upstream advocacy** for "extend `gc handoff` to also restart on-demand named sessions." Issue #1087 (open) actively advocates the *opposite* — interactive agents should never be restarted without operator approval. Evidence currently favors verdict **B** or **C** in tk-wv6m6; verdict A would need a fresh upstream design conversation including an attached-detection guard.

## Provenance

| Doc-type or artifact | Producer | Source location (path + commit SHA, or URL) | Surveyed at |
|---|---|---|---|
| Source: self-handoff command | gascity | `cmd/gc/cmd_handoff.go` @ d11ee0e1 | 2026-05-11 |
| Source: session reset command | gascity | `cmd/gc/cmd_session_reset.go` @ d11ee0e1 | 2026-05-11 |
| Source: runtime request-restart | gascity | `cmd/gc/cmd_runtime_drain.go` @ d11ee0e1 | 2026-05-11 |
| Source: session reconciler | gascity | `cmd/gc/session_reconciler.go` @ d11ee0e1 | 2026-05-11 |
| Source: named-session helpers | gascity | `cmd/gc/named_sessions.go` @ d11ee0e1 | 2026-05-11 |
| Source: awake-set computation | gascity | `cmd/gc/compute_awake_set.go` @ d11ee0e1 | 2026-05-11 |
| Source: session lifecycle parallel | gascity | `cmd/gc/session_lifecycle_parallel.go` @ d11ee0e1 | 2026-05-11 |
| Source: NamedSession config schema | gascity | `internal/config/config.go` @ d11ee0e1 | 2026-05-11 |
| Source: session manager (RequestFreshRestart) | gascity | `internal/session/manager.go` @ d11ee0e1 | 2026-05-11 |
| Source: worker handle Reset | gascity | `internal/worker/handle_lifecycle.go` @ d11ee0e1 | 2026-05-11 |
| Source: tmux Respawn/Kill primitives | gascity | `internal/runtime/tmux/tmux.go` @ d11ee0e1 | 2026-05-11 |
| Test: handoff regression #744 | gascity | `cmd/gc/cmd_handoff_test.go:329-404` @ d11ee0e1 | 2026-05-11 |
| Docs: CLI reference (handoff/reset) | gascity | `docs/reference/cli.md:1170-2411` @ d11ee0e1 | 2026-05-11 |
| Docs: config reference (circuit breaker) | gascity | `docs/reference/config.md:266-268` @ d11ee0e1 | 2026-05-11 |
| Design doc: session-model-unification | gascity | `engdocs/design/session-model-unification.md` @ d11ee0e1 | 2026-05-11 |
| Commit: original skip-restart fix | gascity | 53f0c926ed00 (2026-04-19) | 2026-05-11 |
| Commit: preserve named-session guards | gascity | 4c24172dd45e (2026-05-01) | 2026-05-11 |
| Commit: complete named-session handling | gascity | 84c0e19d4f35 (2026-04-19) | 2026-05-11 |
| Commit: respawn circuit breaker for named | gascity | b31fd6c5a27b (2026-05-03) | 2026-05-11 |
| Commit: initial gc session reset | gascity | 0c85813fcdd1 (2026-04-08) | 2026-05-11 |
| Issue #744 (closed) | gastownhall/gascity | https://github.com/gastownhall/gascity/issues/744 | 2026-05-11 |
| PR #745 (closed superseded) | gastownhall/gascity | https://github.com/gastownhall/gascity/pull/745 | 2026-05-11 |
| PR #927 (merged) | gastownhall/gascity | https://github.com/gastownhall/gascity/pull/927 | 2026-05-11 |
| Issue #1102 (closed) | gastownhall/gascity | https://github.com/gastownhall/gascity/issues/1102 | 2026-05-11 |
| PR #1552 / PR #1568 (merged) | gastownhall/gascity | https://github.com/gastownhall/gascity/pull/1568 | 2026-05-11 |
| Issue #1087 (open) | gastownhall/gascity | https://github.com/gastownhall/gascity/issues/1087 | 2026-05-11 |
| Issue #1276 (open) | gastownhall/gascity | https://github.com/gastownhall/gascity/issues/1276 | 2026-05-11 |
| Issue #1893 (open) | gastownhall/gascity | https://github.com/gastownhall/gascity/issues/1893 | 2026-05-11 |
| Issue #119 (referenced) | gastownhall/gascity | https://github.com/gastownhall/gascity/issues/119 | 2026-05-11 |
| gascity decision beads | local Dolt | `bd list --type=decision` in gascity rig | 2026-05-11 |

## 1. The named-session restart gate

The block is implemented in two places that share the same gate function.

### 1.1 Gate function

`cmd/gc/cmd_handoff.go:279-298` — `sessionRestartableByController`:

```go
func sessionRestartableByController(store beads.Store, sessionName string) (bool, error) {
    ...
    if !isNamedSessionBead(b) {
        return true, nil
    }
    return namedSessionMode(b) == "always", nil
}
```

A session is "restartable by the controller" iff it is **not** a configured named session **or** its mode is `"always"`. By construction this excludes `on_demand` named sessions (the default mode per `internal/config/config.go:367-370`, 426-432).

### 1.2 Self-handoff skip

`cmd/gc/cmd_handoff.go:190-202`:

```go
restartable, err := sessionRestartableByController(store, sessionName)
if err != nil { ... }
if !restartable {
    if err := clearRestartRequest(store, dops, sessionName); err != nil { ... }
    fmt.Fprintf(stdout, "Handoff: sent mail %s (named session; restart skipped).\n", b.ID)
    return handoffOutcome{code: 0}
}
```

Help text (lines 30-33) commits to this behavior:

> For on-demand configured named sessions, sends mail and returns without requesting restart because **the controller cannot restart the user-attended process**.

### 1.3 Remote-handoff skip

`cmd/gc/cmd_handoff.go:340-352`:

```go
if !restartable {
    ...
    fmt.Fprintf(stdout, "Handoff: sent mail %s to %s (named session; kill skipped because the controller cannot restart it)\n", b.ID, targetAddress)
    return 0
}
```

### 1.4 Same gate for `gc runtime request-restart`

`cmd/gc/cmd_runtime_drain.go:421-433`:

```go
restartable, err := sessionRestartableByController(store, current.sessionName)
if err != nil { ... }
if !restartable {
    if err := clearRestartRequest(store, dops, current.sessionName); err != nil { ... }
    fmt.Fprintln(stdout, "Restart skipped for named session; controller cannot restart on-demand named sessions.")
    return 0
}
```

Help text (lines 390-393):

> For on-demand configured named sessions, the controller cannot restart the user-attended process. In that case this command reports that restart was skipped and returns immediately. No session.draining event is emitted when restart is skipped.

### 1.5 Test pinning the behavior

`cmd/gc/cmd_handoff_test.go:329-336` — comment block on the regression:

> Regression for gastownhall/gascity#744:
> gc handoff on a named (human-attended) session used to call setRestartRequested unconditionally. The controller cannot respawn a user-started session, so the PreCompact hook crashed the user to their shell on every context compaction. doHandoff must recognize the named-session case, still send the handoff mail, and skip both the tmux and bead restart flags.

Test `TestDoHandoff_Regression744_NamedSessionSkipsRestart` (lines 336-404) explicitly seeds `configured_named_mode = "on_demand"` and asserts that all restart flags remain cleared after `doHandoffWithOutcome`.

## 2. Intent signal

| Finding | Classification | Evidence |
|---|---|---|
| Self-handoff skip for on-demand named | **Deliberate refusal** | Commit message 53f0c926 (#927): *"every PreCompact 'gc handoff context cycle' tick killed Claude Code to the user's shell and lost any in-flight context-recovery work"*; test comment at cmd_handoff_test.go:329-336 names the failure mode; help text at cmd_handoff.go:32 commits to the policy in docs. |
| `gc runtime request-restart` skip for on-demand named | **Deliberate refusal** (consistent with handoff) | cmd_runtime_drain.go:431 explicit log line; help text at lines 390-393. |
| Remote-handoff skip for on-demand named | **Deliberate refusal** | cmd_handoff.go:350 explicit log line, same gate function. |
| Reconciler restart-request handling is mode-agnostic | **Capability present** (gap is policy, not technical) | session_reconciler.go:1042-1086 kills the session for **any** type when `restart_requested` is set; no mode check. |
| `gc session reset` *does* restart on-demand named sessions | **Deliberate inversion of handoff policy** | cmd_session_reset.go:11-34 — long doc: *"For named sessions, reset also clears any tripped named-session respawn circuit breaker before requesting the fresh restart"*; cmd_session_reset.go:88 calls the same `handle.Reset()` machinery handoff would have used. |
| Why named sessions are protected from *config-drift* restarts when attached | **Deliberate refusal** (separate concern) | session_reconciler.go:1118-1124 — *"a single transient IsAttached false negative would destroy conversation context irreversibly"*; b20a8d5a *"attached sessions never restart on config drift"*. |
| Why named sessions are protected from *config-drift* restarts when actively in use | **Deliberate refusal**, refs gastownhall/gascity#119 | session_reconciler.go:1151-1156: *"prevents draining a working agent mid-task without graceful handoff"*. |

**Bottom line on intent.** The gate is deliberate and intentionally redundant across `gc handoff`, `gc handoff --target`, and `gc runtime request-restart`. The verbatim rationale in upstream artifacts is "the controller cannot restart the user-attended process" (cmd_handoff.go:32; cmd_runtime_drain.go:391; PR #745 description; issue #744 description). However:

- `gc session reset` is a counter-example shipped by the same maintainers (initial commit 0c85813f, 2026-04-08 — predating PR #745). Reset uses `handle.Reset(ctx) → manager.RequestFreshRestart(id)` (worker/handle_lifecycle.go:102-113 → session/manager.go:785-797), which only sets `restart_requested=true` and `continuation_reset_pending=true` metadata. The reconciler then kills the session on its next tick, and the next awake-set computation re-wakes the on-demand named session because the session bead still has demand (compute_awake_set.go:130-147).
- The respawn circuit breaker (commit b31fd6c5, PR #563) was added *because* "the supervisor reconciler will respawn a named session indefinitely with zero awareness of loop conditions" — proving that the controller *does* respawn named sessions in steady state.

So the surface-level claim "controller cannot restart" reflects the **as-of-#744 PreCompact failure mode**, not a present-day capability limit. The policy that has accreted on top of it is best summarized as: **handoff/request-restart are auto-invoked from hook contexts, and auto-restart of operator-attached processes is destructive; reset is operator-explicit, so it's allowed.** This policy is implicit in the code, not stated in any single doc.

## 3. Safety / correctness concerns

The audit found multiple concrete failure modes documented upstream:

1. **PreCompact race** — `gc handoff` from the PreCompact hook used to set `restart_requested=true` while Claude was producing the compaction summary. The reconciler killed the pane mid-summary; the new session booted with only the empty "context cycle" mail subject. Original symptom in issue #744 (on-demand mode), generalized to `always` mode in issue #1102 ("fix: mayor session crashing during pre-compact step"). Solution: PR #1568 added `gc handoff --auto` and a stdin-based PreCompact detection that takes the skip-restart path regardless of bead classification (cmd_handoff.go:46-48, 226-238). **Status as of d11ee0e1:** PreCompact hooks should use `--auto`; the named-session skip is no longer load-bearing for the PreCompact race.

2. **Mid-task drain of an attached agent** — config-drift handling at session_reconciler.go:1118-1124 has an explicit guard: *"Attached sessions never get config-drift restarts. The human will restart when ready... a single transient IsAttached false negative would destroy conversation context irreversibly."* The guard is config-drift-only; the **restart-request** path (line 1042-1086) has no equivalent attached check.

3. **Mid-task drain of an actively-in-use named session** — config-drift defers when the named session is "pending interaction, tmux-attached, or recent activity" (session_reconciler.go:1151-1156), referencing gastownhall/gascity#119. Again, this is config-drift-specific; restart-request bypasses it.

4. **User preference for non-disruption** — issue #1087 (open) is operator-authored: *"As a user, I don't want an agent that I'm interacting directly with to ever be killed without my direct approval, regardless of whether their config has changed."* Proposes splitting "autonomous" vs "interactive" agents at the config layer. This is the cleanest articulation of the underlying safety concern.

5. **Co-located tmux state** — orthogonal to the handoff question but worth flagging for tk-wv6m6: `gc session reset`'s implementation goes through `RequestFreshRestart → reconciler kills via workerKillSessionTargetWithConfig`, which on tmux maps to `KillSessionWithProcesses` (tmux.go:435-509). That kills the host tmux session, destroying any operator-attached helper panes. Tk-2ezog already weighed this trade-off and chose to keep kill-session semantics; nothing about that decision has shifted in upstream since.

The audit found **no upstream signal that named-session pane state — scroll back, mid-edit, partial commits — is explicitly considered in restart-skip rationale.** The closest is the attached-session guard in config drift (concern #2 above), but it does not extend to restart-request.

## 4. Existing capability check

**Can `respawn-pane` technically restart an on-demand named session today?** Yes.

- `gc session reset` already does it. cmd_session_reset.go:88 calls `handle.Reset(ctx)`, which sets the same metadata flags the reconciler checks for any session (session_reconciler.go:1047: `beadRequested := session.Metadata["restart_requested"] == "true"`).
- The reconciler's stop path uses `workerKillSessionTargetWithConfig` (session_reconciler.go:1050), which on tmux runs through `KillSessionWithProcesses`. The next awake-set tick computes the desired set; if the session has demand (assigned work, mail, or named-default-demand), it goes back into the desired set and the reconciler starts it.
- For on-demand sessions, demand comes from `compute_awake_set.go:130-147`: presence of a non-drained, non-closed canonical bead. The handoff mail bead itself does not directly create demand, but any pre-existing assigned work bead on the named identity does (PR #1704 added the assigned-work scan). In cycle-recycle's path the pre-poured next wisp provides this demand.
- `internal/runtime/tmux/tmux.go:2835-2867` — `RespawnPane`/`RespawnPaneWithWorkDir` are used by tmux re-start paths. The comment at line 2865-2867 confirms they are intended for the controller-managed restart flow: *"This is essential for handoff: set on before killing processes, so respawn-pane works."*

The only **technical** caveat: the named-session respawn circuit breaker (commit b31fd6c5) can trip after 5 restarts in 30 minutes without progress. `gc session reset` clears the breaker explicitly (cmd_session_reset.go:80-86); if `gc handoff` were extended to restart on-demand named, it would need the same breaker-clear (or the breaker would suppress repeat handoffs).

**Conclusion: the gap is policy, not capability.** Extending handoff is a refactor on top of existing primitives, not a new platform capability.

## 5. Open upstream signal

Searched gastownhall/gascity issues and PRs for "handoff", "named session", "restart", "respawn-pane", "on_demand". Notable open items as of 2026-05-11:

| # | State | Title | Relevance |
|---|---|---|---|
| 1087 | OPEN | feat: Introduce "automatic" vs "interactive" agents | **Directly relevant.** Operator advocates *more* protection for interactive sessions, not less. Argues against any auto-restart of human-attended agents. Active since 2026-04-21, no maintainer pushback in body. |
| 1893 | OPEN | bug: alive on_demand sessions ignore bd update --assignee | Recent (2026-05-09) confirmation that **`gc session reset` is the de facto workaround** for restart needs on on-demand named sessions. Operator workaround: *"`gc session reset <session-id>` for each stale named session before slinging new work."* No comment from operator that handoff should pick this up. |
| 1276 | OPEN | gc runtime request-restart panics with empty select{} deadlock | Tangential. Documents the same gate (`TestRuntimeRequestRestartNamedOnDemandReturnsWithoutBlocking`) without challenging it. |
| 1493 | OPEN | bug: named-always session post-churn stays asleep indefinitely | Concerns `always` named sessions, not on-demand. |

Closed/merged precedent for the current shape:

- Issue #744 (closed 2026-04-15) — origin of the skip.
- PR #745 (closed 2026-04-15) — original implementation, superseded.
- PR #927 (merged 2026-04-19) — final form of the skip; cited in test comment.
- Issue #1102 (closed 2026-04-22) — generalized failure to `always` mode during PreCompact.
- PR #1552/#1568 (merged 2026-05-01) — `gc handoff --auto` for PreCompact; the *"right discriminator isn't the bead — it's the call site"*. This is the most recent statement of intent and it **moves further away** from "controller can/can't restart" toward "auto vs explicit invocation context."

**No open issue or PR advocates "extend `gc handoff` to also restart on-demand named sessions."** No issue references gastownhall/gascity#744 in the direction of reversing it. The upstream conversation is moving toward *more* operator-attachment protection, not less.

The gascity decision beads in the local Dolt store contain no decisions related to handoff or named-session restart; tk-2ezog and tk-wv6m6 are the only decisions on this surface and both live in the gc-toolkit rig.

## 6. Recommendation feedstock

The evidence currently favors verdict **B** or **C** in tk-wv6m6 over verdict **A**.

- **Verdict A (push gascity upstream to extend `gc handoff` to also pane-restart on-demand named sessions)** is *technically buildable* — the reconciler already restarts these sessions when `restart_requested` is set, `gc session reset` proves the end-to-end path, and the only mechanical gap is the gate function and the respawn-circuit-breaker clear. **But the upstream signal is against it.** Issue #1087 (open, no pushback) explicitly wants interactive agents protected. The most recent merged change (PR #1568) refines the skip by call-site (PreCompact), reinforcing the policy that auto-restart of operator-adjacent processes needs a context check. An upstream PR would need to introduce an attached-detection guard (the config-drift `sessionAttachedForConfigDrift` exists but is not on the restart-request path) and convince maintainers that cycle-recycle from an unattended coord pane is a distinct case worth supporting. Without that prior design conversation, an A-style PR would likely be rejected or rebased away.
- **Verdict B (accept the asymmetry, reverse tk-2ezog, land PR #5 as-is)** is most consistent with upstream's de facto position. `gc session reset` is the documented and tested restart path for on-demand named sessions (issue #1893's workaround confirms operators are already chaining it). PR #5 codifies the same pattern in cycle-recycle. The cost is the co-located tmux state the original tk-2ezog flagged — that risk is unchanged but tk-2ezog's mitigation (prefer-handoff policy) is the exact thing PR #5 reverses in a hot path. The verdict requires documenting the risk in cycle-recycle prose and accepting it.
- **Verdict C (status quo)** keeps tk-2ezog's prefer-handoff policy intact and closes PR #5. Cost: named coord recycle continues to need operator `/clear`, which is what tk-wzcvj was filed to eliminate. The cycle-recycle pipeline stalls observed in tk-wzcvj's "Observed 2026-05-11" section would persist.

The audit found **no upstream evidence** that the current asymmetry is regarded as a bug. The pattern of recent commits and the open issue #1087 read as upstream consciously leaning into "handoff = mail + maybe-restart-if-safe; reset = explicit-restart" rather than collapsing them. Verdict B aligns gc-toolkit with that direction without requiring an upstream change.
