---
name: First-reaction actionable route loss — root cause and fix
description: Why an actionable first-reaction's gc.routed_to is emptied after the disposition (a re-sling of the notes-only reaction workflow retires a legitimate bare pool route), why the fix is an idempotency guard in gc-proactive.sh rather than a change to the disposition or a runtime patch, and what was ruled out (quiesce, orphan-dispose).
---

# First-reaction actionable route loss — root cause and fix

## Symptom (tk-wd5xaw)

A first reaction that exits `actionable` releases its subject to a pool on a
bare `gc.routed_to=<rig>/<rig>.polecat`. On five aged beads reacted in one
pilot pass, four later showed `gc.routed_to` **present but empty** — written
by the disposition, then cleared. The one that kept its route
(`tk-atebx`) was the one a polecat had CLAIMED (`in_progress`) before the
clearing happened. The emptied beads are bd-ready but offered to no pool, and
because they still carry `gc.first_reaction=actionable` the next scan reads
them as disposed and does not look again: a disposition that schedules nothing.

## The bare route is a legitimate dispatch, not a placeholder

The pool claims a bare-routed bead directly. The Tier-3 work query
(`bd ready --metadata-field gc.routed_to=$target --unassigned`) surfaces it,
dispatch computes pool demand from it, and `gc hook --claim` claims it and runs
it under the pool-worker prompt. No workflow is auto-instantiated at claim
time; `mol-polecat-work` lands only through an explicit `gc sling`. So the
actionable exit's bare route is a first-class dispatch surface — it just has to
survive until a worker claims it.

## What empties it (the write)

The only code in the gascity runtime that writes an empty-string `gc.routed_to`
is `retireClaimRoute` (`internal/sling/sling_core.go:855`), reached from
`doStartGraphWorkflow` (:910) via `restampWorkBeadRouting` on the source bead
(:939→:840) and `retireInputConvoyClaimRoutes` on every input-convoy member
(:945→:904). It exists to prevent double-dispatch: once a graph.v2 workflow
starts on a bead, the workflow — not a stale pool route — must be the single
live dispatch surface for the work it drives. `doStartGraphWorkflow` is reached
only through `gc sling`.

The discriminator follows from the idempotency guard at :862: a claim consumes
`gc.routed_to` into `gc.run_target` (the ga-sa0 rule), so a CLAIMED bead already
has an empty route that :862 skips. An unclaimed bead still carries the
disposition's route, and :865 empties it.

## Why it fires on an actionable bead

`mol-first-reaction` is slung with `--on`, so the reaction SUBJECT is the single
tracked member of the workflow's input convoy. `retireInputConvoyClaimRoutes`
retires that member's route on the premise the started workflow will drive it as
work. That premise is false for `mol-first-reaction`: it is notes-only, it does
not push the subject onto a branch, and on an already-reacted subject
`first-reaction-dispose.sh` refuses the second dispose. So re-slinging
`mol-first-reaction` on a subject that a prior reaction already routed clears the
actionable route at workflow-start and puts nothing in its place. The
dispose-level "a first reaction happens once" guard cannot save the route: it
runs after the sling, and the retirement already happened.

## The fix: idempotent first-reaction dispatch

Every in-repo path that slings a first reaction funnels through
`gc-proactive.sh` `cmd_sling`: the proactive scan calls it per candidate,
`gc-helm.sh react` shells out to `gc-proactive.sh sling`, and
`gc-visit-open.sh` goes through `gc-helm react`. `cmd_sling` is the single
chokepoint, and it is where the invariant belongs.

`sling_first_reaction_guard` refuses to sling `mol-first-reaction` at a bead that
already carries a completed reaction — `gc.first_reaction` (stamped by the
dispose) or `gc.proactive_reaction=1` (stamped by the release). The skip is an
idempotent no-op (exit 0), not an error: the reaction already happened, so the
caller has what it asked for, and callers like `gc-visit-open` do not fall back
to double-filing a visit. The proactive scan already excluded reacted beads in
`scan_precision_filter`; this closes the direct-sling, `react`, and
`gc-visit-open` paths the scan filter never covered.

This is the right layer because the bare route is a legitimate dispatch that
must survive, and the only thing that destroys it is a second workflow start on
the subject. A first reaction is defined to happen once; enforcing that at the
dispatch moment removes the trigger.

### Alternatives considered

- **Sling `mol-polecat-work` from the actionable exit instead of a bare route.**
  Rejected: the bare-route pool claim is the intended lightweight dispatch for a
  reaction, and swapping it for a full workflow changes the model and races the
  in-flight `mol-first-reaction` molecule still finalizing on the same subject.
- **Make the bare route non-retireable.** Not possible in the pack: the pool
  claims `gc.routed_to`, and that is exactly the key the runtime retires. The
  only non-retireable dispatch is a workflow's `gc.execution_routed_to`.
- **Preserve a reacted member's route in `retireClaimRoute`.** Wrong: when a
  work formula (`mol-polecat-work`) is legitimately slung at an actionable bead
  to do the work, its route SHOULD be retired so the workflow is the sole
  surface. The discriminator is the started formula (does it drive its members),
  not the member's reacted state.

## The runtime residual (split to gascity gc-vo9vq)

The pack guard covers every dispatch path that funnels through `gc-proactive.sh`.
A raw `gc sling --on mol-first-reaction <reacted-bead>` typed outside the tool
still trips the same retirement. That is the runtime's to close: filed as gascity
**gc-vo9vq**, proposing that `retireInputConvoyClaimRoutes` /
`restampWorkBeadRouting` gate route-retirement on the started formula actually
claiming/driving its members, so a notes-only reaction workflow does not retire
its subject's independent route while work formulas still do.

## Ruled out

- **`quiesce_release_molecule_steps`** (`gc-helm.sh`, the inline quiesce on
  `takeaway --release`). It de-routes the molecule's STEP beads and its
  `gc.kind=workflow` ROOT, resolves each root's anchor via the input convoy, and
  explicitly never touches the anchor (the subject). It does not empty the
  subject's route.
- **`orphan-dispose.sh`** source-class disposal delegates to
  `gc workflow reopen-source`, which re-routes rather than empties, and clears
  session pins, not the route.
- The witness-patrol `quiesce-completed-workflows.sh` named in older notes was
  deleted in the pack rewrite; its surviving worktree copy acted only on step
  beads and used `--unset-metadata` (absent), not the empty-string symptom.
