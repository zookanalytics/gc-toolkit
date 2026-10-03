---
name: A triage path for stale branches that is not the operator's board
description: Why the three unanchored-branch chores sat 11-22 days on the helm board, why writing a better ask would not have moved them, and the sweep proposed instead — classify mechanically, auto-dispose what is decidable, archive the rest reversibly, and escalate only what is genuinely contested.
---

# Stale-branch triage: make the default disposition reversible

Work record for `tk-wfufb9`, scope item 4 — *"The three stale branch chores need
a triage path that is not the operator's board. Propose one; do not hand-rule
them here."* This is the proposal. It deliberately rules on none of the three
branches.

## Scope

**Mandate.** Where a stale-branch keep/abandon question should go instead of the
operator's attention band, and what has to be true of that destination for the
question to actually move. It is the record of what was proposed on this bead.

**Boundaries.** It does not decide the fate of any branch, does not specify the
sweep to the line, and is not the authority on branch conventions — that is
`docs/gascity-routing-model.md` for routes and the refinery docs for merge flow.
The implementation is tracked separately (see [Destination](#destination)).

## The three, as found

Census taken from the live board on 2026-08-23, all in the `shutupandlisten`
store, all carrying `gc.routed_to=human`:

| bead | branch | age when censused | state |
|---|---|---|---|
| `su-12qg` | `polecat/su-12qg` | ~22d | anchored; `rejection_reason` states the choice in full |
| `su-p78a` | `claude/apple-models-testing-y6qz5w` | ~22d | unanchored, ~2107 lines, `found_by=refinery-queue-scan-2026-08-01` |
| `su-ju41` | `claude/ios-voice-transcription-review-9ss6cj` | ~11d | unanchored, 10 commits / ~6.4k lines, `found_by=witness-patrol-2026-08-12` |

## The finding: a stated ask is not enough for this class

The rest of `tk-wfufb9` is about rows whose NEEDS said nothing. The obvious
extrapolation — *write the ask and these will move too* — is **falsified by
`su-12qg`**, and that is the most useful thing this census produced.

`su-12qg` has its ask written out at length, and it is a good one. Its
`rejection_reason` names the two options ("land it with an `npm run feeltest`
entry point, or declare it scratch and close"), corrects an earlier false claim
about the branch on the record, states that `metadata.target` points at a branch
that no longer exists, and identifies which of the two commits is genuinely new.
Everything a decider needs is on the bead.

It sat twenty-two days anyway.

So the blocker for a branch chore is not legibility. It is that **both offered
dispositions are terminal**: land work nobody has assessed, or delete work
nobody has assessed. Neither has a safe default, so neither can be taken by an
agent, and a question with no safe default and no owner is a question that waits
for someone who feels like deciding it. That is a permanent state.

The other two are the same shape with less written down. `su-ju41` is ~6.4k
lines of iOS transcript work; nobody deletes that on a board glance, and nobody
merges it on one either.

## What is actually mechanical here

Almost all of it. Given a branch and a target, an agent can determine without
any judgment at all:

- whether every commit is already reachable from the target
  (`git merge-base --is-ancestor`, or `git cherry -v` for patch-equivalence
  against a rewritten history);
- whether it still merges clean;
- how old the newest commit is, how many commits and lines it carries, and who
  authored them;
- whether any open PR references the head;
- whether an owning bead exists, and whether a live session stands behind it.

What is *not* mechanical is exactly one question, and only for one subset:
**should unmerged, unassessed work be thrown away?**

## The proposal

A per-rig sweep — script plus order, rig-scoped the way `patrol.toml` is — that
classifies every origin branch with no live owner and disposes of each class
where it can.

### 1. Superseded → close, no human

Every commit already reachable from the target. Nothing can be lost: the work is
on the target. Delete the branch, close the chore, record the merge commit.

### 2. Cold and unmerged → **archive**, no human

The key move, and the reason this proposal exists rather than a nicer board
cell.

Do not ask whether to delete the branch. **Tag it and delete it**: push
`archive/<branch>@<short-sha>` as an annotated tag carrying the classification
(age, commit count, author, mergeability at archive time), then delete the
branch ref. The objects survive under the tag indefinitely, so nothing is
destroyed and nothing becomes GC-eligible; restoring is one command
(`git branch <name> archive/<name>@<sha>`); and the branch list stops growing.

Because the act is **reversible, an agent may take it without consent.** That is
the whole mechanism. The three chores did not stall because nobody understood
them — they stalled because the only available act was irreversible, and an
irreversible act needs a human by rule (`docs/gascity-routing-model.md`,
"`gc.routed_to=human` means *unclaimable*, not *unclaimed*"). Replace the
irreversible default with a reversible one and the same rule now says an agent
can do it.

The chore closes with the tag recorded, so "what happened to that branch" stays
answerable from the ledger.

### 3. Genuinely contested → escalate, WITH the classification

Only three shapes reach a person:

- an open PR references the head — someone is mid-review, and archiving under a
  live PR would strand it;
- a live session owns the branch;
- the classifier could not read the branch or its target — fail-closed, never
  archive on an unread branch.

These arrive at the board with the classification already attached, so the row's
`blocked_reason` names the real question ("archive 6.4k lines of unmerged iOS
transcript work last touched 2026-08-12, or keep it for PR #NN?") rather than
the generic keep/abandon that nobody was ever going to answer from a table.

### 4. Where the sweep is triggered

The producers already exist and already find these branches —
`refinery-reconcile.sh` reports `FRESH HANDOFF (branch pushed, no anchor)`, and
the witness patrol filed `su-ju41` under `found_by=witness-patrol-2026-08-12`.
What is missing is not detection. It is a **disposition** for what detection
finds, which is why every one of them ends the same way: file a chore, route it
`human`, and stop.

The sweep is that disposition. `recover-stranded-branches.sh` is the nearest
sibling and the right shape to copy — it selects the complement of every other
scan, resolves liveness first and fail-closed, reads back every write, and
retracts its own markers when they stop being true.

## What this does not settle

- **The three branches.** Not ruled on here, by instruction. They stay as they
  are until the sweep exists; the sweep is what should decide them, and it
  should decide them without being asked.
- **The archive tag's own lifetime.** Tags accumulate too, just far more slowly
  and far more cheaply. Worth a threshold eventually; not worth blocking this on.
- **The cold threshold.** A number to pick with the operator, not to assert
  here. 14 days matches the board's own `STALE_DAYS`, which is a defensible
  starting point precisely because it is already the city's word for "nobody has
  touched this".

Until the sweep lands, all three will read as unexplained human routes on the
board and in `doctor/check-human-route-states-the-ask`. **That is the correct
reading, not a gap in this work.** Their route genuinely is unexplained: the
right destination for them is a triage sweep, and writing a prettier ask on the
operator's board would only make a misroute look decided — the exact failure
`tk-wfufb9` was filed about.

## Destination

Implementation is tracked as `tk-uqh5n7` (gc-toolkit), filed from this bead.
