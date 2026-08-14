---
name: Detecting a workflow that stopped advancing
description: Why no existing consumer can fire on a stalled graph.v2 workflow, what "stalled" is defined as mechanically, why the anchor is consulted for only two of its states, and why one of the two live instances turned out to be caused by another pass rather than merely missed by it.
---

# Detecting a workflow that stopped advancing

Design record for `assets/scripts/detect-stalled-workflows.sh` and the witness patrol
step that runs it (bead tk-xesf6).

## 1. The gap is real: no existing consumer can fire on either instance

The bead asked for this to be verified rather than assumed. It was, against the two
live instances, and the result is stronger than the bead's initial read — the misses
are structural, not incidental.

| Pass | Keyed on | Why it cannot fire |
|---|---|---|
| mol-liveness-sweep | `gc bd ready` → per-candidate edge check | see below — it misses roots and steps for two *different* reasons |
| witness `recover-orphaned-beads` | assignee + dead session | scoped to ASSIGNED beads by construction; a stalled frontier is unassigned |
| `recover-stranded-branches.sh` | `metadata.branch` | requires a pushed branch; `sl-xhfl` never created a worktree |
| `quiesce-completed-workflows.sh` | the anchor's terminal state | de-routes husks; it never asks whether a live workflow is moving |
| deacon queue-starvation | a session's queue + `bead.updated_at` | keyed on ASSIGNED work; a stalled workflow has no assignee |
| refinery patrols | the merge queue | a stalled workflow has no merge handoff |

The liveness sweep is the near miss and deserves its own line, because it fails twice
over:

- **Its roots are never candidates.** The candidate set is `gc bd ready`, and a
  graph.v2 root is blocked by its own `workflow-finalize` step. Verified: neither
  `sl-xhfl` nor `sl-jnjd` appears in signal-loom's 25-row ready set, while their
  finalize steps `sl-cutz` / `sl-vms6` are open blockers on them.
- **Its steps are candidates and are then dropped.** `sl-um8j` *is* in the ready set
  and survives every jq filter — and is then dropped by the class-2(i)(c) edge check,
  because it `tracks` its still-open root. That edge is true of **every step of every
  workflow**, moving or stalled, so the check that names a legitimate wait is exactly
  what hides this one.

None of these is wrong about its own question. The unasked one is whether the
workflow is still MOVING, which is visible only in the time derivative.

## 2. A correction to the bead's reading of instance 1

The bead recorded that `sl-xhfl`'s frontier steps "ARE in `gc bd ready`, so this is
NOT the invisible-to-demand deadlock — something claims and abandons."

Both halves are wrong, and the second one matters for anyone else who reads that
signature. **Ready is not offered.** The pool's offer predicate is open + unassigned
+ ready + `gc.routed_to` non-empty; `gc bd ready` is demand-agnostic and answers only
the first three. `sl-um8j` was ready and *unrouted*, so no polecat could ever be
offered it — which is exactly the invisible-to-demand deadlock, and exactly why "no
worktree created, no commit" was observed.

## 3. Instance 1 was not merely missed — it was caused

`sl-um8j`'s Dolt history settles what happened, in four rows:

| commit | assignee | `gc.routed_to` |
|---|---|---|
| 19:16:43 | — | present (routed to the pool) |
| 19:17:42 | `gc-toolkit__polecat-lx-vge0` | present — a polecat CLAIMED it |
| 19:19:09 | `gc-toolkit__polecat-lx-vge0` | **cleared** |
| 19:19:10 | — | cleared |

Route cleared first, assignee cleared one second later, in two separate writes: the
exact, documented signature of `quiesce-completed-workflows.sh`. It stripped a live
rework molecule's frontier step out from under the polecat that had claimed it 87
seconds earlier — the precise harm that script's own header warns about.

It did so because `sl-xhfl` is the **rework** for `sl-ew4w` / PR #533, and it anchors
on `sl-ew4w`, which carries `merge_result=pull_request` from the very PR the rework
exists to fix. `is_terminal_anchor()` reads that as "the molecule is dead".

`sl-jnjd` wears the same shape for a different reason: mol-scoped-work stamps
`pull_request` at its own submit step, so the anchor goes terminal while the
molecule's cleanup and finalize steps are still to run, and those get de-routed too.

That defect is filed as **tk-8m8d4** (it is a repair, not a detector, and this bead
explicitly excludes unsticking these instances). It is recorded here because it
**constrains the detector**: a stall detector that defers to `is_terminal_anchor`
would exempt both instances and find nothing.

## 4. What "stalled" means, mechanically

A graph.v2 workflow root — open or in_progress, carrying `gc.input_convoy_id` — is
STALLED when all four hold for at least `--stall-minutes` (default 120):

1. **SILENT** — no bead of the workflow has been written. Last-touch is the max
   `updated_at` over the root and every bead carrying `gc.root_bead_id=<root>`, **in
   any status**.
2. **UNHELD** — no live session behind it: neither the root's `gc.session_name` nor
   any member's assignee is in the live roster.
3. **STARTED** — the graph has closed at least one step, so it demonstrably moved and
   then stopped, AND the anchor has not landed (see §5).
4. **UNCLAIMABLE** — its frontier (the members `gc bd ready` returns) is non-empty and
   every frontier bead is unassigned AND unrouted. No pool can be offered it and no
   session holds it.

> **(4) was NARROWED after this record — tk-6mccf.** As written above the frontier is
> every ready member, and graph.v2 pours inert DESCRIPTOR beads alongside its steps
> (`gc.kind=spec` "Step spec for <step>", `gc.kind=scope`) which are ready and
> unroutable by construction — so they satisfy (4) forever without meaning it. On the
> first live report against a `mol-scoped-work` graph, 7 of the 8 beads named as the
> frontier were spec beads. The shipped predicate is now the ready **executable**
> members: an allow-list of `gc.kind`, so the next inert kind poured is excluded on
> the day it appears. This is load-bearing twice over, because §6's dedup marker is
> keyed on that same set — descriptor ids never close, so including them pinned most
> of the key to constants and suppressed re-reports after the real frontier moved. A
> descriptor-only frontier now exempts as the *empty frontier* row in the table below —
> every executable member is still blocked — and is counted under its own name in the
> pass's summary line. See `assets/scripts/detect-stalled-workflows.sh`
> (`is_executable_kind`), its regression cases INERT/MIXED/CONTROL/NEWKIND, and its
> doctor check.
>
> **The allow-list comes from the producer contract, not from a ledger listing.** The
> first cut named the six kinds a `gc bd list` over this rig actually returned (absent,
> `task`, `retry`, `cleanup`, `scope-check`, `workflow-finalize`) — a sample, not a
> vocabulary. The executable control set is `beadmeta.ControlKinds`, exactly eight
> (`rigs/gascity/internal/beadmeta/kindsets.go`; behavior owner is the
> one-case-per-member `ProcessControl` switch in `internal/dispatch/runtime.go`), and
> five of them — `ralph`, `check`, `retry-eval`, `fanout`, `drain` — had never been
> poured in gc-toolkit, so the sample dropped them. A kind missing from an allow-list
> does not fail loudly: it reads as *inert*. An unrouted `check` on the frontier would
> have been filtered out, the frontier gone empty, the workflow counted as a
> descriptor-only wait, and the stall never reported — i.e. the sampled list hid exactly
> the missing-route class this pass exists to surface. The shipped set is now
> `ControlKinds` in full plus the worker-executed kinds (absent, `task`, `cleanup`);
> the excluded set is `beadmeta.WorkflowTopologyKinds` (`workflow`, `scope`, `spec`),
> whose own docstring — "Routing never lands on these; agents must never claim them" —
> is the contract-level statement of the inertness the filter keys on.

**Closed members are not optional to (1).** A step *closing* is the graph advancing,
and it is routinely the workflow's most recent event. Measured on `sl-xhfl`: its
closed steps were last written at 19:30:06Z while every live member sat at 19:19:10Z.
Dated by its live members alone, a workflow that had just advanced would read as
stalled. This costs one extra query per candidate
(`--metadata-field gc.root_bead_id=<root> --status=closed`), and only for candidates
that already failed the cheap half of the test.

**Every exempt case is a wait with a name**, which is what keeps this from being the
wall-clock rule the bead warned against:

| Exempt | Because |
|---|---|
| live session holds any member | somebody is working it; implementation routinely outlasts any threshold, so liveness is the guard and the timer is only the trigger |
| frontier bead is ROUTED | demand exists and a pool has not gotten to it. A quiet pool is a real wait with an owner (the deacon's queue-starvation pass). **This detector finds workflows nobody CAN work, never ones nobody HAS worked yet.** |
| frontier bead is ASSIGNED | a session holds it; if that session is dead the bead is an ORPHAN and the witness's own recovery pass owns it |
| empty frontier | `gc bd ready` returns nothing for the workflow, so a blocker is naming the wait in the graph |
| `triage.hold` / `gc.takeaway` on the root or the anchor | an operator decided it waits, and the value is the reason (mol-liveness-sweep class 4(c)/(d), same absent-vs-empty tri-state — an EMPTY stamp is a cleared hold) |
| suspended rig | needs no test: the pass runs from the rig's own witness patrol, so a stopped rig emits nothing |

## 5. The anchor is consulted for exactly two states

`closed` and `merge_result=merged` — the work landed, the workflow is finished.

Every other state `quiesce-completed-workflows.sh` treats as terminal is deliberately
NOT honoured: `pull_request`, `pre_open_gate`, a refinery handoff, a human park are
all states a live molecule wears mid-flight, and `pull_request` is what a rework
molecule's anchor already carries from the round being reworked (§3).

The husk guard is instead the workflow's **own** evidence — condition (3)'s first
half. mol-polecat-work runs its steps INLINE and closes none of them (tk-p9ji9), so
every husk of the city's most common formula has zero closed members and is exempt by
construction. That is what keeps this pass from reporting most of the rig.

Both halves are load-bearing, and each was found by a live false positive:

- Without the closed-step test, the pass reports every stranded husk in the rig.
- Without the landed-anchor test, it reports husks that *acquired* a closed step —
  somebody closes `load-context` by hand to stop the re-offer churn. Measured on
  gc-toolkit: three such molecules, all reported by the closed-step test alone, all
  with anchors closed and merged (`tk-5eikz`/PR#306, `tk-0981e`/PR#299).

Measured together on the two live rigs: **signal-loom, both true positives reported
and nothing else; gc-toolkit, zero reported** — 7 moving, 8 exempt as never-advanced,
3 exempt as landed.

## 6. Who owns the signal, and where it surfaces

**The witness patrol**, as a step between `quiesce-completed-workflows` and
`check-polecat-health`. It is the sibling of the two passes already there: quiesce
handles a workflow whose work is done and whose steps are dead; this handles one
whose work is *not* done and whose steps cannot be reached. Both walk the same
root → members → convoy → anchor resolution, and the witness patrol runs continuously
per rig, so a 2h stall surfaces within the hour rather than within the liveness
sweep's 6h cooldown.

The signal is **one visit per stalled workflow**, on a standing
`triage.scope=stalled-workflows` subject, routed to the rig's converse pool — the same
shape and vocabulary mol-liveness-sweep files its batch visit in, so a stall lands
where the board already looks. The visit body carries the diagnosis (how long silent,
which frontier beads, how many steps closed) and the disposition menu: route, unstick,
kill, or hold.

> **Superseded by tk-1g9yw.** The last-touch key described below was self-defeating:
> stamping the marker is a `bd update`, which bumps `updated_at` — the very field the
> key is read from — so the same workflow re-flagged every stall window forever, minting
> a fresh visit and converse session each time (a token amplifier). The marker is now
> keyed on the sorted **frontier bead-id set**, and a **visit-already-open guard**
> (skip a root that already has an open visit, matched by `stall_root`) is the primary
> one-visit bound. See `assets/scripts/detect-stalled-workflows.sh` and its doctor check.
> The paragraph below records the original design.

**Dedupe is per workflow, keyed to the observation.** The root is stamped
`stall_flagged=<last-touch>`, exactly as `recover-stranded-branches.sh` keys
`stranded_branch_flagged` to `<branch>@<tip>`. A workflow that stays stuck keeps the
same last-touch and is never re-reported; one that advances and stalls again earns
exactly one more signal. The patrol runs continuously, so a per-pass signal would be a
per-minute signal — the noise tk-jbv0r and tk-76jxq are about.

The visit is created BEFORE the marker is stamped, **and its routing is read back
before the marker is stamped.** In that order a failed create — or a `--set-metadata`
that exits 0 and persists nothing — leaves the stall un-retired and the next pass
re-signals; the reverse would retire it on a visit nobody ever saw.

The read-back covers the three stamps that make a visit a signal rather than a bead:
`gc.routed_to` (what offers it to the converse pool), `task_kind=visit` (what the board
and the converse role select on) and `gc.continuation_group` (what resolves it back to
the standing subject, an exact-string read). The `tracks` edge is lineage and is
deliberately outside the gate — losing it costs provenance, not the signal. Guarding
the write's exit status alone is not enough: the failure that matters here is the write
that succeeds and stores nothing, and from inside the pass the only way to tell those
apart is to read the bead back.

A failed read-back costs one unrouted visit bead, left behind and named on stderr, plus
one more filed next pass. That is the same cost the marker-write failure path already
carries, and it is the right side to err on — a duplicate visit is noise, while a stall
retired without a signal is precisely the silence this pass exists to end, now asserted
by a marker saying it was reported.

## 7. Fail-safe direction

Every unestablished fact reports nothing rather than guessing, because each input,
misread, turns a healthy workflow into an escalation: an unread session roster makes
every running molecule look unheld, an unreadable ready listing makes every frontier
look unclaimable, and an unreadable closed-member listing dates a workflow by a subset
of itself. The roster, the three bulk listings, the per-root closed read and the anchor
read each abort or skip with a named reason on stderr.

This inverts mol-liveness-sweep's bias ("a probe that cannot be read excludes
nothing"), and deliberately. That sweep's failure mode is re-listing a bead in a
sitting a human is already having; this pass's failure mode is manufacturing an
escalation about a workflow that is fine.

## 8. Known limits, stated rather than discovered later

- **A workflow that stalls before closing any step is invisible.** It is
  indistinguishable from an inline-execution husk, and reporting it would report every
  husk in the rig. That case is not silent in the same way: a polecat that died mid-run
  leaves an assigned bead for orphan recovery, and one that pushed leaves a branch for
  `recover-stranded-branches.sh`.
- **Claim churn masks silence.** A workflow being repeatedly claimed and abandoned
  keeps writing to its beads, so it never looks silent. That is a distinct signature
  (wisp burn) and belongs to tk-p9ji9, not here.
- **Pool starvation is out of scope by design** — a routed frontier is exempt. If
  nothing is draining a pool, the deacon's queue-starvation pass is the owner.
- **The window is per-rig-uniform.** `--stall-minutes` is one number for every workflow
  in the rig. A formula with legitimately long unattended gaps would need either a
  higher window or a per-formula override, which is not built.

## 9. Mechanical, per the bead's constraint

The remedy is a query plus a threshold that an existing patrol runs on a schedule:
`assets/scripts/detect-stalled-workflows.sh`, called from the witness patrol's
`detect-stalled-workflows` step, with `assets/scripts/detect-stalled-workflows.test.sh`
(hermetic, 50 assertions) and `doctor/check-stalled-workflow-detector` guarding that
the script, its test and its call site all stay shipped and wired — the patrol formula
is an allowlisted mirror of a base artifact, so a reconciliation that drops the step
would otherwise restore the blind spot in silence.
