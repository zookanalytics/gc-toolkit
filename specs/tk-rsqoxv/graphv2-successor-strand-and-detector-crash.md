---
name: graph.v2 successor steps strand unrouted, and the detector that should catch them crashed (tk-rsqoxv)
description: Why a graph.v2 molecule's later step comes up open+unrouted after its predecessor closes (a post-pour route strip when the continuation chain breaks mid-molecule, not a pour-time gap and not caused by #928), and why the I13 detector built to catch exactly this class (doctor/check-root-advancing) silently crashed on every stranded root that carried no gc.session_name. Read before touching check-root-advancing, graph.v2 step routing/continuation, or the mol-first-reaction/mol-validate strand class (gascity gc-im8lv / gc-ouvfx / gc-rfxju).
---

# graph.v2 successor steps strand unrouted — and the detector was blind

Two distinct, compounding faults produce the reported symptom. One is a
gascity-core routing gap this rig cannot fix from a gc-toolkit branch; the
other is a gc-toolkit shell bug in the very check meant to surface the first,
fixed here.

## Symptom

A graph.v2 molecule (`mol-validate`, `mol-first-reaction`) runs its steps as a
chain. A step closes normally; its successor comes up `open`, `assignee` empty,
with `gc.routed_to` / `gc.execution_routed_to` / `gc.run_target` all empty. The
pool hook only offers routed work, so the successor reaches no worker and the
molecule stalls at `workflow-finalize` forever. Reported on `tk-a1qoql`
(mol-validate, anchor tk-t6gd5x): `triage-findings` closed, `rule-convergence`
(tk-ca5371) came up unrouted; the witness unblocked it by stamping
`gc.routed_to=gc-toolkit/gc-toolkit.polecat` by hand.

## Not a one-off, not #928, not a pour-time gap

- **Recurring and pre-existing.** The same signature sits live on `tk-4lc2h0`
  (mol-validate): `triage-findings` closed 2026-09-26, `rule-convergence`
  (tk-ire9v1) open+unrouted since — stranded ~5 days. It predates the suspected
  #928 (tk-p17xc2, landed 2026-10-01) by five days, so #928 did not cause it.
  #928 is a refinery-reconcile `bd_list` memo, unrelated to graph.v2 step
  routing. (The reporter cited "tk-2w0pc9 / #928"; tk-2w0pc9 is a separate
  reconcile merge-tail bug and #928 is tk-p17xc2 — neither touches routing.)
- **The route is stripped after pour, not withheld at pour.** A freshly poured,
  never-claimed mol-validate molecule (tk-fy3gqy, pour 2026-10-01T07:47) carries
  `gc.routed_to`, `gc.session_affinity=require`, and `gc.continuation_group=main`
  on **every** step, including `rule-convergence` and `finalize-and-drain`.
  graphroute stamps all steps at pour (internal/graphroute/graphroute.go
  `ApplyGraphRouteBinding` line ~224 sets routed_to; ~242-244 sets the
  continuation pair; `DecorateGraphWorkflowRecipeWithDefaultBinding` loops over
  every step). So an unrouted successor on a live molecule had its route
  **removed** post-pour. This falsifies the "born unrouted at pour / weak sling
  guard" theory and confirms the "distinct code path" gc-im8lv hypothesized
  (gc-rfxju fixed the pour-time nameless-binding cause and is not regressed).

## Fault 1 — gascity core: the successor's route is stripped and nothing re-arms it

The trigger is a continuation break mid-molecule. `preassignHookContinuationGroup`
(cmd/gc/cmd_hook_claim.go:1500) pins the open sibling steps to the first
claiming session (sets their `assignee`). When that session drains after an
early step instead of continuing, the orphaned preassignments are released: the
ready one is re-offered to the pool, but the blocked downstream steps lose
`gc.routed_to` and `gc.session_affinity` (the `gc.continuation_group` survives).
A fresh worker then pool-claims the released ready step — but
`preassignHookContinuationGroup` bails when the claimed step's own
`gc.continuation_group` is empty (line 1503: `if rootID == "" || group == ""`),
so it never re-pins the next sibling. When that step closes, its successor is
left deliverable by nothing:

| mechanism | gate it fails on | site |
|---|---|---|
| pool offer | needs `gc.routed_to` (stripped) | hook claim |
| continuation nudge | needs `assignee` + `session_affinity==require` (both gone) | build_desired_state.go:5828 `continuationRowCouldBeCandidate` |
| route-recovery backstop | recovers only from `gc.run_target` / a carried route (steps carry neither) | route_recovery.go:32 `carriedPoolRoute` |
| detached-orphan restore | resolves the route from the bead's own `gc.session_id`/`gc.session_name` (a never-claimed step has none) | detached_orphan_lane.go:417 `restoreDetachedOrphanRoute` |

Evidence shape, verified on the live steps: a step that advanced normally
(same-session continuation) keeps `cg=main`/`aff=require`; a step that fell back
to the pool ends `cg`/`aff` cleared; a stranded successor ends `routed_to` and
`session_affinity` gone with `continuation_group` kept. Candidate strip sites
for the gascity implementer to bisect against tk-4lc2h0 /
internal/dispatch/control.go:1332-1404 and ralph.go:1373.

The durable fix belongs in gascity: re-arm a ready, unassigned, unrouted
graph.v2 step from its live root's own route (`gc.root_bead_id` → root
`gc.routed_to`) — exactly the value the witness stamps by hand. Tracked by
**gc-im8lv** (the bug / instances, operator-ruling), **gc-ouvfx** (the detector,
filed 2026-08-13, unbuilt), with **gc-rfxju** the prior pour-time cause fix
(closed; does not cover this path). This rig cannot push to gascity.

## Fault 2 — gc-toolkit: the detector crashed on exactly the roots it exists to catch (fixed here)

`doctor/check-root-advancing` (I13) was purpose-built (#847, tk-d12vam) to
report a started molecule root whose frontier is unreachable — the precise
class above. It never worked: line 263 read `${LIVE[$sname]:-}` where `$sname`
is the root's `gc.session_name`. `LIVE` is an associative array, and an empty
subscript is a fatal error in bash (`LIVE: bad array subscript`). A **stranded**
root commonly carries no `gc.session_name` — the slot that drove it is gone and
nothing restamped the root — so the check aborted on every strand it was meant
to find and `gc doctor` reported it failed with zero findings. The adjacent
member-liveness read guards its lookup (`[ -n "$who" ]`, line 267); the root
read did not.

Fix: guard `$sname` the same way before the lookup, so an empty session_name
falls through to member liveness instead of aborting. With the fix, the check
run live against the city surfaces three real strands silent 15+ days —
tk-fym3u0 (gc-toolkit) and gc-88oib / gc-0cjmf (gascity, two of gc-im8lv's own
instances) — where before it surfaced nothing. The hermetic test gains a case
whose root carries no session_name; it fails against the pre-fix script and
passes after.

This is the regression gate for Fault 1: once the gascity re-arm lands, this
detector stays green because strands stop being minted; until then, it surfaces
them for the witness to route or dispose rather than letting them sit silent.
