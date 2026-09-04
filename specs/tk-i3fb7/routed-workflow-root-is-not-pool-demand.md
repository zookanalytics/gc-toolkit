---
name: A routed workflow root is not pool demand
description: The measurement that settles whether a spent molecule's routed ROOT bead drives polecat spawn or re-offers its steps, why the answer is no at three independent layers, and what was actually wrong in this pack.
---

# A routed workflow root is not pool demand

## The question

`tk-i3fb7` was filed on the premise that a completed molecule's ROOT keeps
`gc.routed_to` after its steps are de-routed, and that `scale_check` counts
that route as pool demand. A later pass added a second premise: that the
offer resolves through `gc.root_bead_id`, so a root's route alone hands
unrouted steps to fresh polecats.

The bead carried its own falsification condition from the first entry:
"confirm scale_check actually counts a routed workflow-root as demand before
choosing the fix — if it does not, this is log hygiene, not churn." Five
witness patrols and one polecat pass observed the step/root split, applied
containment by hand, and each recorded the condition as still unverified.

## The answer

Neither premise holds. A bead carrying `gc.kind=workflow` is excluded from
both the offer and the demand count, by kind, at every reader.

**The offer does not resolve through the root.** `hookClaimMatchesRoute`
(`cmd/gc/cmd_hook_claim.go`) compares one candidate's own
`gc.routed_to` against the session's route targets. Its only other arm reads
`gc.run_target`, and only when the candidate is itself `gc.kind=workflow`.
There is no `gc.root_bead_id` lookup on the claim path. Upstream of it, the
generated pool-demand query (`internal/config/workquery.go`,
`bdReadyPoolDemandShell`) filters `--metadata-field "gc.routed_to=$target"`,
so an unrouted step is never returned to be filtered in the first place.

**A topology bead is never served.** `hookCandidateClaimable` refuses any
candidate whose `gc.kind` is in `beadmeta.WorkflowTopologyKinds`
(`workflow`, `scope`, `spec`), and `isWorkflowTopologyHookCandidate` applies
the same test over the raw query output.

**A topology bead is never counted.** `demandRowServable`
(`cmd/gc/demand_serve_predicate.go`) excludes the same kind set. That file
exists to make the controller's demand loop agree with the worker's query,
and it names a routed topology bead as one of four classes of "permanent
capacity demand that no worker could ever claim" it was written to end. The
controller's scan (`build_desired_state.go`) counts only rows
`demandServableForTemplates` accepts. `demand_serve_agreement_test.go` pins
the case.

The exclusions are present at `3561360de9f8`, the revision the installed
`gc` was built from, so this describes the running binary and not only the
source tree.

### The live measurement

Root `tk-9wjdjq` is the current instance of the shape: open, unassigned,
`gc.kind=workflow`, `gc.routed_to=gc-toolkit/gc-toolkit.polecat`, its convoy
`tk-1v3298` holding one closed member, and six of its seven steps unrouted
(`workflow-finalize` correctly stays routed to the control-dispatcher).

Running the pool's own offer query with the 20-item cap lifted returned 64
rows. None of the six unrouted steps appeared, and every one of the 64 rows
carried its own `gc.routed_to` to the pool. The earlier probe that suggested
otherwise was reading a capped result.

## What was actually wrong

The premise was false about the engine and true about this pack.
`liveness-sweep.sh` classifies a bead as `routed-and-claimable` on the
presence of `gc.routed_to` alone. A routed workflow root reaches that arm and
takes the label: it is not a convoy or an order wisp, so the `machine` arm
misses it, and it carries no `gc.root_bead_id` of its own, so the `husk` arm
misses it too — `HUSK_STEPS` is built by matching steps against their root's
id, which the root itself does not carry.

`routed-and-claimable` is a drop class, so the misclassification files no
false visit. What it does is publish a count of beads described as claimable
pool demand when nothing can ever claim them, which is the reading six
passes acted on.

The fix keys the arm on the same thing the engine keys on. A bead whose
`gc.kind` is a workflow-topology kind classifies as `topology`, ahead of the
route test, so the route arm only sees beads a worker would genuinely be
served.

## The other two readers of the same key

`liveness-sweep-precheck.sh` builds a cheaper survivor set whose exclusions
must stay a subset of the sweep's, or it would drop a bead the sweep would
report. It already excludes every routed bead outright, so it drops both live
roots without knowing why, and adding a topology arm there would only affect
an unrouted topology bead. That population is zero in this rig, and a second
copy of the kind list is drift surface, so the precheck is left alone. The
subset invariant holds: this change adds a sweep exclusion, it removes none.

`doctor/check-routed-work-claimable` reads `gc.routed_to` for a different
question — whether a route is byte-identical to a live agent identity, and
whether the bead is reachable in `bd ready` or `bd blocked`. Both live roots
carry a valid pool address and both are in `bd ready`, so the check is quiet
on them and needs no arm.

## Mirrored set

The pack names `workflow`, `scope` and `spec` directly;
`beadmeta.WorkflowTopologyKinds` is the source of truth and there is no
command that reads it out. Drift is one-directional and safe: a kind added
upstream and not mirrored here falls through to the route arm, which is the
behavior that preceded this change.

## Rejected

Both fixes the bead suggested clear `gc.routed_to` on the root, one by
widening the sweep's selection and one by adding a write after the steps
quiesce. Neither is worth doing. The route on a root is not a leak — it names
the run, which is why the engine excludes topology beads by kind rather than
by absence of a route — and clearing it would remove a stamp that
`hookClaimMatchesRoute` reads for the `gc.run_target` migration arm.

The script both fixes targeted, `assets/scripts/quiesce-completed-workflows.sh`,
was deleted at PR #465 and no longer exists to edit.

The backlog the bead named as its remaining scope, roughly 490 husk chains,
is not in the store. Every non-closed `gc.kind=workflow` root was created
within the preceding 27 hours.
