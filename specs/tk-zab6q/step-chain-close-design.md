---
name: Closing the mol-polecat-work step chain — the deliberate calls
description: Design record for tk-zab6q. Why the close lands in the gc-toolkit mirror rather than upstream, why the six steps close in forward dependency order (bd refuses to close a blocked issue — dependent-first was tried and closes exactly one bead), why workflow-finalize is never closed by the polecat, and what evidence settled each. Also why the auto_push=false halt arm carries a verbatim copy of the block rather than calling one. Read it before changing the order of the submit-chain-close block or moving either copy.
---

# Closing the mol-polecat-work step chain

Design record for bead tk-zab6q, which implements Target 1 of
`specs/tk-z9nln/consolidation-plan.md`. The plan established *that* the fix
is reachable in this repo and named three things as "the real design work,
not the mechanics". This document answers those three, with the evidence
each answer rests on. Call 4 was not on the plan's list — the pre-open
signoff found it (tk-qkfwp7), and it is here because the answer is a
trade-off rather than a mechanic. It does not restate the diagnosis — that is
`specs/tk-y389z/step-close-root-cause.md` and the plan.

## What shipped

`formulas/mol-polecat-work.toml`, `submit-and-exit`: a marker-delimited
block that closes six step beads through `assets/scripts/step-close.sh`, in
forward dependency order, immediately before `gc runtime drain-ack`. It ships
at **both** of the step's terminal exits — step 8, after the refinery handoff,
and the step-3 `auto_push=false` arm, after the bead is parked branch-ready.
Asserted by `assets/scripts/submit-branch-gate.test.sh` §5 and §6, which
execute the block and the whole halt arm extracted verbatim from the formula.

**And the prompt copy, which is the one a polecat is told is mandatory.**
The done sequence exists three times — the base prompt's
`### The Done Sequence`, its `## FINAL REMINDER: RUN THE DONE SEQUENCE`, and
the formula's `submit-and-exit` — and all three ended at
`gc runtime drain-ack`. Fixing only the formula leaves the two prompt copies
telling a polecat that its work "is not complete until you run these
commands", none of which close a step. So the change also ships
`template-fragments/polecat-close-step-chain.template.md`, elected in
`pack.toml` and hand-synced into `agents/polecat-codex/agent.toml` and
`agents/_polecat-gemini/prompt.template.md`.

This is the same shape as `polecat-append-notes`, which exists because the
identical triplication defeated the `--notes` → `--append-notes` correction
(tk-t41dq, tk-q9e9y). `doctor/check-polecat-fragment-sync` enforces the
hand-sync; there is no automatic propagation.

## Call 1 — the order is forward, because `bd` allows no other

The chain is linear; each step is blocked by the one before it:

    load-context <- workspace-setup <- preflight-tests <- implement
                 <- self-review <- submit-and-exit <- workflow-finalize

**`bd` refuses to close a blocked issue.** So the chain can only unwind from
the unblocked end: `load-context` first, because nothing blocks it, and
closing it is what unblocks `workspace-setup`, and so on to
`submit-and-exit`.

### This was got wrong first, and a live run caught it

The first draft of this change reasoned as follows, and shipped
dependent-first: closing a step is what makes its *dependent* ready, so
walking forwards briefly publishes a ready, open, pool-routed
`workspace-setup` — the step that rebuilds a branch that may be green-gated
under a live review. Closing dependent-first would never expose a ready open
step. The argument is sound as far as it goes, and it is irrelevant, because
`bd` will not perform it:

    tk-3kabdu: updating issue: cannot close blocked issue: tk-3kabdu is blocked by [tk-8yvm91]
    tk-8yvm91: updating issue: cannot close blocked issue: tk-8yvm91 is blocked by [tk-43f5x7]
    tk-43f5x7: updating issue: cannot close blocked issue: tk-43f5x7 is blocked by [tk-lmugzw]
    tk-lmugzw: updating issue: cannot close blocked issue: tk-lmugzw is blocked by [tk-ys5i8x]
    tk-ys5i8x: updating issue: cannot close blocked issue: tk-ys5i8x is blocked by [tk-49gx3p]
    step-close: closed tk-49gx3p (mol-polecat-work.load-context) outcome=pass

Six calls, one bead closed. That is this molecule's own chain, run live at
submit time. Closing `load-context` then unblocked `workspace-setup`, which
closed on the next call — the inverse control.

**Why the hermetic test did not catch it.** The fake `step-close.sh` closed
whatever it was asked to close, so it accepted an order the real tool rejects
— a stub that does not refuse what the tool refuses hides a dead branch behind
a green suite. The fake now models the blocked-issue rule, and
`submit-branch-gate.test.sh` §5 keeps the reversed loop as a **control**,
asserting it closes exactly one bead. That control is what stops the order
being "simplified" back.

### What the forward order costs

The exposure the first draft was trying to avoid is real and cannot be
designed away — it can only be bounded:

- The steps stay **assigned to this session** for the whole loop. Pool
  fallback offers only *unassigned* beads, so a ready step is not claimable
  by another polecat while the session lives, and the loop is six consecutive
  local calls.
- The loop runs **after** the refinery handoff, so there is no unsubmitted
  work a mistaken claim could destroy.
- `submit-and-exit` closes **last** and is `workflow-finalize`'s only blocker,
  so completing the loop arms the control-dispatcher finalizer as a backstop
  (see Call 3).

If the session dies mid-loop, the remainder is re-pooled — which is exactly
the pre-fix behaviour, for a strictly smaller set of steps. The loop must
never run before the handoff.

**A note on `gc.session_affinity`.** The step beads carry
`gc.session_affinity=require`, which reads like a guarantee that only the
owning session can be offered them. It is not one:
`gascity/cmd/gc/pool_session_name.go:448` says outright that it *"is an
advisory marker no routing path reads."* It is the assignee, not the affinity
marker, that keeps a ready step out of the pool.

## Call 2 — the mirror closes steps it does not declare

Three of the six (`load-context`, `preflight-tests`, `implement`) are
`mol-polecat-base`'s, upstream in `gastownhall/gascity`. The mirror closes
them anyway.

- `step-close.sh` resolves each bead from the `(assignee, gc.step_ref)`
  pair, so it can only ever close a bead **this session already owns**.
  Closing a base step is not reaching into another formula's territory; it
  is this run cleaning up after itself.
- The alternative — close only the three the mirror declares — leaves
  `load-context` open, assigned to a drained session, pool-routed and
  unblocked. That is exactly the re-offer condition that generates the
  husks, so the narrower choice does not fix the bug.
- A refusal is safe by construction: `step-close.sh` exits non-zero and
  writes nothing when the bead is not this session's. The loop reports it
  and continues.

## Call 3 — `workflow-finalize` is never ours

It carries `gc.kind=workflow-finalize` and `gc.routed_to=<rig>/core.control-dispatcher`.
The dispatcher's handler (`gascity/internal/dispatch/runtime.go`) closes the
workflow **root** first, then calls
`molecule.CloseSubtreeWithMetadata(root, {gc.outcome: skipped, close_reason: …})`,
which resolves members via `ListSubtree` → `ListByMetadata(gc.root_bead_id)`
— the exact key our step beads carry — and force-closes every one still
open. Its own comment: *"This also repairs partially materialized workflows
whose unused steps were never reached by ordinary dependency progression."*

Two consequences:

1. Closing `workflow-finalize` ourselves would take the finalizer's job and
   skip the root close. We must not.
2. `submit-and-exit` closes **last** in the forward order, and it is that
   step's only blocker. So completing the loop is exactly what arms the
   finalizer, and the finalizer then force-closes anything the loop could not
   — a step it refused, or one left by an interrupted run that still reached
   the end. It is a backstop for the tail of the loop, not for a loop that
   died before it.

## Call 4 — the halt arm gets a copy, not a call

`submit-and-exit` ends the session for good in two places, not one. Step 8 is
the refinery handoff. The other is the `auto_push=false` arm in step 3, which
parks the branch as ready and `exit 0`s — deliberately without a handoff, but
just as terminally. The first cut of this change closed the chain only at step
8 and left the halt arm four comment lines telling the polecat to "run step 8's
block", above an `exit 0` that never reaches step 8. The opt-out halt therefore
stranded exactly the husk this change exists to stop, and no test ran the arm
(tk-qkfwp7).

The obvious repair — one definition, called from both — does not survive
contact with how the step is executed. Each fenced block is its own shell
invocation, so a function defined in step 8 is out of scope in step 3; and the
arm's `exit 0` means step 8's text is never read at all on that path. A shared
*script* would work, but the only part that shrinks is the loop: the four-line
candidate resolution that finds the pack has to be repeated at both sites
regardless, so a new script trades a seven-line duplicated block for a
six-line one — and adds a file, a second resolution target, and its own tests.

So the halt arm carries the block verbatim, indented one level to sit inside
the `if`. Duplication is the known hazard here — the `--notes` →
`--append-notes` correction was defeated by exactly this, a block written more
than once and fixed in one copy (tk-t41dq) — so the suite pins the copies
rather than trusting them: §6 asserts the halt copy is step 8's copy with two
spaces prepended to every line, and the pre-existing §5 check already pins the
prompt fragment's copy against that same source, byte for byte. Three copies,
two assertions, no drift that passes.

What §6 actually proves is the ordering, not the presence: it runs the arm
against a fake `gc` and a fake `step-close.sh` and requires the trace
`UPDATE, CLOSE ×6, DRAIN` — the bead parked first, the six steps closed next,
the drain last. Its control is the reviewed shape: the same arm with the block
stripped out. That control still exits 0 and still parks the bead correctly, so
nothing except looking for the closes distinguishes it — which is why the arm
went out with the defect in the first place.

The ordering within the arm follows step 8's rule that the loop never runs
before the work is out of reach. At step 8 that moment is the refinery handoff;
in the halt arm it is the `gc bd update` that sets `branch_ready=true` and
clears the assignee. Before that write, a step made ready by the loop could
still be claimed against work nobody has recorded.

One consequence is inherited deliberately. The block's `: "${SC:?…}"`
hard-fails when no `step-close.sh` can be found, which in the halt arm means
exiting *before* `gc runtime drain-ack` — an idle session rather than a silent
husk. That is step 8's existing trade (§5 asserts it), and the copy keeps it
rather than quietly softening one of the two sites.

## Known characteristic: resolution can reach another molecule's step

`step-close.sh` resolves by the `(assignee, gc.step_ref)` pair, which names
one bead only while a session owns one molecule. A polecat identity that still
carries husk chains from earlier sessions owns *several* beads for the same
`gc.step_ref`, and once this run's own bead for a step is closed, the
resolver's next call for that step can match an older molecule's.

Observed on this change's own submit, where the loop was re-run after a
partial first pass: `load-context` and `workspace-setup` resolved to
`tk-0mwux` (root `tk-ddn26`) and `tk-29n7h` (root `tk-o3cst`) — both already
closed, so the calls were no-ops and reported as such.

This is not new behaviour and not introduced here: `step-close.sh` has
resolved this way for the five sibling formulas since it shipped, and it emits
a `N beads match` note when the ambiguity is visible. What is new is that this
formula exercises it six times per run instead of once. It is bounded by the
fact that every candidate is, by construction, a bead **this same session
owns** — the resolver cannot reach another session's molecule — and the husk
population that creates the ambiguity is what this change removes. If it needs
tightening later, the mechanism already exists: `step-close.sh --bead <id>` takes
a hint and uses it only if it verifies against the same identity pair.

## Dedupe against tk-i3fb7

The bead asked for this explicitly. `tk-i3fb7` — *"pass sweeps only
`gc.step_ref` beads — a completed molecule's ROOT keeps `gc.routed_to`, which
`scale_check` counts as pool demand"* — is a **different** bead and stays
open. It is about the containment sweeper's scope; this is about the
generator.

Its claim checks out: `quiesce-completed-workflows.sh:545` filters candidates
with `select((.metadata["gc.step_ref"] // "") != "")`, and a molecule root
carries `gc.step_id` but no `gc.step_ref` (verified on live root tk-gnetpn),
so the root is excluded from the sweep.

The two interact favourably rather than overlapping. When `submit-and-exit`
closes, the control-dispatcher's finalizer calls
`setOutcomeAndClose(store, rootID, outcome)` on the **root** — precisely the
bead the sweeper cannot reach. So a chain that finalizes cleanly never
exhibits tk-i3fb7's symptom. tk-i3fb7 remains live for the ~490 husk chains
already in the store and for any chain that still strands through a failure
arm.

## Why the fragment reaches molecules the formula cannot

A step bead's description is rendered once, at pour, and never re-renders. So
every molecule already in flight when this lands carries the OLD
`submit-and-exit` text, with no step 8 — the formula change cannot reach them,
and they will strand exactly as before.

The prompt fragment is not frozen: it is rendered fresh on every polecat
session. So it applies to in-flight molecules too, and it is the only half of
this change that does. That is a second, independent reason to correct the
prompt copies rather than the formula alone.

It also bounds the expected effect. This change stops NEW husks from the point
it lands; it does not clear the 490 already in the store, and the plan is
explicit that clearing without fixing the generator regrows (tk-y389z did
exactly that and the backlog came back larger). The existing backlog stays
`quiesce-completed-workflows.sh`'s job until a full cycle finalizes cleanly.

## What was *not* done, and why

- **`quiesce-completed-workflows.sh` (877 + 1,222 test lines) is kept.** The
  plan is explicit: keep the sweeper until one full cycle finalizes cleanly,
  *then* delete it. Removing it in the same change that first exercises the
  close path would leave no containment if the close path is wrong.
- **Target 4 (the seven control-character scrubbers) is not folded in.** The
  plan gates that on "if a scrubber is touched"; this change touches none.
- **The failure arms of `submit-and-exit` still leave the chain open.** The
  branch-shape gate, target-resolution and push-failure arms halt with the
  work unhanded-off and resumable. Their open steps *are* the recovery
  mechanism — a fresh polecat resumes the run. Only the two terminal exits
  (refinery handoff, and the `auto_push=false` branch-ready halt) close the
  chain; see Call 4 for why the halt arm carries its own copy of the block.

## Evidence that the `open`-tier fix is live

`tk-3o2ym` and `tk-wi0u1` both report `step-close.sh` refusing to close a
step left at `status=open` by the `ready_assignment` claim path. The script
now resolves an `open` tier explicitly (tk-jww3y): `in_progress` is tried
first, `open` only if that finds nothing.

The molecule that produced this change is the positive control. All six of
its step beads sat at `status=open, assignee=<this session>` — the precise
shape those two beads say is unclosable — and a `--dry-run` of the shipped
loop resolved every one:

    submit-and-exit    -> tk-3kabdu     preflight-tests   -> tk-lmugzw
    self-review        -> tk-8yvm91     workspace-setup   -> tk-ys5i8x
    implement          -> tk-43f5x7     load-context      -> tk-49gx3p

The same run demonstrates the hazard `step-close.sh` exists to prevent
(tk-niu2f). `GC_TRIGGER_BEAD_ID` held `tk-49gx3p` — the `load-context` bead —
for **all six** lookups, because the session was spawned on that step and a
hook-claim does not refresh the variable. A formula closing on the
environment value would have closed `load-context` six times and left the
other five open. The script reported the mismatch on five of the six and
resolved from the store instead.
