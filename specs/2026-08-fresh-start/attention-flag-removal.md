---
name: Decision record — remove gc.attention (the flag-for-attention concept)
description: Operator decision (2026-08-08) to remove the gc.attention flag and the flag-this-for-attention concept from the pack, with the defensibility check that preceded it, what replaces the hand-raise (a filed conversation turn), and the full sweep inventory.
---

# Decision record: remove `gc.attention`

**OPERATOR DECISION (2026-08-08, their words):** "Unless it's defensible,
can we just get rid of `gc.attention` … stripping out the flag-this-thing
-for-attention concept plus the flag label itself. It won't mean anything
in core GC, and I wasn't a fan of that approach to solve the use-case of
what's most pressing."

**Defensibility check (the "unless"): not defensible — removal proceeds.**
The one legitimate need the flag served — *an agent believes a human
should look at this* — has a strictly better form in the current model:
**file a conversation turn on the subject.** A turn is durable, owned,
conversation-carrying, blockable, and board-legible through real
lifecycle state; the flag is a bare metadata bit with no lifecycle (set,
often never cleared), no upstream meaning (verified — `gc.attention`
appears nowhere in core), and it is the backdoor form of agents asserting
urgency, which the operator has separately rejected. The board's job is
to *derive* what is pressing from real state — open turns, human gates,
stranded convoys, blocked work — not to trust self-assertions.

## What replaces the hand-raise

Nothing new: `mol-turn`'s four-line convention. The first concrete
conversion is `mol-first-reaction`, whose final step now files a
proactive turn instead of flagging — which is tk-h9pq5's own Open
Question 4 ("first-reaction proactivity as turns") landing on the side
the design predicted.

## Sweep inventory

- `assets/scripts/gc-helm.sh` — `flag`/`clear` verbs, the flagged anchor
  kind, and the FLAGGED severity band removed; board keeps its remaining
  anchor kinds.
- `services/helm/` — FLAGGED kind/severity and `gc.attention` handling
  removed from the Go board model, source, tests, README.
- `tools/helm-surface-fixture.sh` — flag scenarios removed.
- `formulas/mol-first-reaction.toml` — flag step → proactive turn.
- `tools/gc-proactive.sh` — the scan's `gc.attention` skip clause
  removed (the `gc.proactive_reaction` marker already carries the
  dedup).
- `agents/proactive/PROVENANCE.md`, `docs/gascity-conversations.md`,
  `specs/2026-08-fresh-start/gas-city-native.md` — prose updated.

**Deliberately untouched:** `specs/` history (records stay as written,
including tk-h9pq5's "keep the flag" clause, which this decision
supersedes — noted here rather than edited there), and `gc.takeaway`
(a different concept: the board headline for re-entry, not a hand-raise;
no ruling exists on it and it keeps earning its place).

## Consequence for tk-h9pq5

Two of its clauses are now superseded by recorded decisions: the Phase-2
reaper-skip (spine-port.md D4) and the `gc.attention`-flag retention
(this record). A future revision of the design doc should fold both in;
until then, these records are the deltas.
