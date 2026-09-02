---
name: The unheld half of the detached-state property
description: Work record for tk-vcrnw6. Why the assignee clear on entry to a detached state belongs in lifecycle.sh rather than at individual call sites or in the doctor alone, and why it stops at status=open. Read it before adding a repair pass for a stale assignee on a gating anchor, and before widening the clear past that status.
---

# The unheld half of the detached-state property

Work record for bead tk-vcrnw6. `specs/tk-eh64m/parked-anchors-and-pool-demand.md`
is the record for the route half of the same property and should be read first;
this one settles the assignee half, which that work left to each caller.

## What was half-enforced

`lifecycle/lifecycle.toml` declares `detached_states = ["pre_open_gate",
"pull_request"]`, and `doctor/check-state-space` states the property as: an open
bead in one of them rests unheld and offered to no pool. Two fields carry that,
and the doctor errors on both (`detachedroute` and `detachedassignee`).

`lifecycle.sh` maintained only the route. `mol-refinery-patrol` merge-push
passed `--assignee ""` at its two gating transitions, so the routine path was
correct, but every other transition into or within a detached state left the
field as found: `pr-open.sh`'s flip, `merge.sh`'s `record_machine`,
`pr-facts.sh`'s three posture re-stamps, `gate-ensure.sh`'s machine-axis
record.

The cost is not a stalled merge. It is a bead in two queues at once. The
refinery's find-work step is assignee-keyed
(`gc bd list --assignee=$GC_AGENT --status=open --has-metadata-key=branch`),
and its own comment states the contract the writer was not keeping: "Every path
that legitimately returns a bead here clears the field first." Finding a
`merge_result`-bearing bead in that queue, it flags and moves on, which is
correct — find-work is not a writer. So a survivor sits in the refinery's queue
for the life of the anchor with nothing converging it. tk-z7h9a8 (PR #544) held
one for a day until visit tk-x7mfvh repaired it by hand; blast radius at repair
time was 1 of 17 open gating anchors.

The baseline this ships onto is clean. Across the five rigs in the city there
are 25 open anchors in a detached state and none carries an assignee, so
nothing is cleared on the first cadence pass after it lands. What ships is the
converger for the next occurrence, and a regression gate beside the doctor arm
that has to keep finding nothing.

## Why the writer, not the call sites

The bead offered three homes. The call-site option (`pr-open.sh` only) was
rejected on coverage: it addresses transitions *into* a detached state and
leaves the self-edges, and the self-edges are both the larger population and
the ones that ran against the observed anchor. The detector-only option is the
status quo, and the status quo is what left tk-z7h9a8 needing a hand.

`lifecycle.sh` is the declared single writer of transitions, and a state's
declared entry actions are already its job — that is what the route arm is. The
assignee arm is the same shape, in the same atomic update, under the same
post-write read-back.

This is not the repair pass `specs/tk-eh64m` rejected. That rejection is about
a reconcile cadence re-clearing a field it cannot see the reason for. Here the
transition writes the postcondition of the state it is itself writing.

## Why the clear stops at status=open

The route half needed `park_route` because `gc.routed_to=human` is a real value
a person owns, and clearing it would retract a bead they still hold. The bead
asked whether the assignee needs an equivalent sentinel. It does not, and the
survey is the reason: nothing in the pack holds an anchor by assignee. The one
writer that sets one is the polecat done sequence's handoff pointer
(`mol-polecat-work.toml`, `--assignee="$REFINERY_TARGET"`), and that pointer is
spent the moment the anchor is gated. `gc-helm.sh takeaway --release` and
`converse-claim.sh` both clear it. `docs/gascity-routing-model.md` names
`assignee="" + gc.routed_to="" + status=open` as the gating idiom itself.

The hazard is real one field over, though, and `status` is where it lives. bd's
`validation.AssigneeNotStolen` refuses an assignee edit on a bead another actor
holds `in_progress`, and the refusal drops the whole atomic update
(`docs/gascity-routing-model.md` row 46). An unconditional clear would therefore
turn every posture re-stamp and machine-axis record on such an anchor into a
hard failure — and it would be attempting exactly the retraction the route half
was careful to avoid.

So the arm reads the status off the bead it already has in hand and clears only
at `open`. Three things agree on that line:

- `open` is the status every detached state declares, so it is the whole
  population the property covers.
- It is the term of bd's guard that decides whether the edit lands at all, so
  the guard is never armed and no transition gains a new way to fail.
- A live claim on a gating anchor is a second driver racing the cadence. That
  is a finding to escalate, not one to overwrite silently.

Nothing is lost by stopping there. Every anchor enumeration in the pack —
`pr-open.sh`, `merge.sh`, `pr-facts.sh`, `gate-ensure.sh` — is `--status=open`,
so no cadence pass reaches an `in_progress` anchor to begin with, and
`check-state-space` scans the same set. The decision is made on `lifecycle.sh`'s
own re-read rather than the caller's enumeration, so a bead claimed between the
two is seen as claimed.

An assignee that is already empty emits no flag at all, which keeps the healthy
transition's `bd update` byte-identical to what it was.

## Convergence without a repair pass

`merge.sh` and `gate-ensure.sh` record the machine axis on every open anchor
every pass, and `pr-facts.sh` re-stamps posture the same way. All three are
self-edges into a detached state, so the arm fires on them. The existing
population converges on the next cadence pass with no sweep and no new writer.

## Not established

Which write moved tk-z7h9a8 into `pull_request` without clearing the assignee
was not identified, and this change makes the question moot rather than
answering it. `bd history` snapshots omit metadata, so `merge_result` is not
reconstructable from the ledger. The two gating transitions in
`mol-refinery-patrol` write both fields together, so neither performed it.
