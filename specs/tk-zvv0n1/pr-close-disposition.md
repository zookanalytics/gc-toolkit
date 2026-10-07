---
name: Pre-recorded PR-close disposition
description: How a deliberate supersede/not-planned PR close records a machine-readable disposition on the open anchor, so pr-facts.sh auto-disposes it through bead-rehome.sh instead of filing a redundant rework-or-close visit. Records the design decided on tk-zvv0n1.
---

# Pre-recorded PR-close disposition

When a PR is closed unmerged out-of-band, `pr-facts.sh`'s close arm transitions
the anchor to `abandoned`, routes it to human, and files a
`pr-abandoned.<num>` visit — "rework it, or close it as not-planned". That arm
ran unconditionally, so a close whose disposition was already decided (the work
is superseded, or deliberately dropped) still produced a visit re-asking a
question the closer had already answered.

The fix gives a deliberate close a machine-readable disposition on the anchor,
and has `pr-facts.sh` honor it: consummate the disposition through the
sanctioned terminal-close path instead of filing the generic visit.

## The lifecycle question, answered

The bead asked whether "superseded / not-planned" is a terminal lifecycle state
that the I5 invariant (`doctor/check-closed-implies-landed`) accepts, or whether
such anchors must stay open with the disposition recorded.

It is already a terminal state I5 accepts. `check-closed-implies-landed`
exempts any closed bead carrying `gc.superseded_by`: bead-rehome.sh is the sole
writer of that pointer, and the check names it "the explicit terminal state this
check accepts." So the auto-dispose CLOSES the anchor — it does not leave it
open — and it does so through `bead-rehome.sh`, whose close both stamps
`gc.superseded_by` (satisfying I5) and records a populated close reason naming
the kind and successor.

No new terminal state, no change to the I5 check: the sanctioned disposition the
check already recognizes is the one the auto-dispose performs.

## The marker

A deliberate close records its intended disposition on the still-open anchor as
three metadata keys, named to mirror `bead-rehome.sh`'s interface:

| Key | Meaning |
|---|---|
| `gc.pr_close_disposition_kind` | one of `re-homed`, `folded`, `fixed-upstream`, `duplicate`, `not-needed` — the bead-rehome kind |
| `gc.pr_close_disposition_successor` | the successor bead: the carrier of the work, or (under `not-needed`) the evidence that concluded it was unnecessary |
| `gc.pr_close_disposition_successor_store` | optional `rig:<name>`, only when the successor's id prefix is ambiguous |

The marker is INTENT, not the disposition itself. It names the `bead-rehome.sh`
invocation that pr-facts will run; bead-rehome remains the sole writer of
`gc.superseded_by`, so the sole-writer invariant the I5 check and the Disposition
doctrine (docs/state-machine.md) rest on is preserved. `pr-dispose.sh` writes
these three keys, so they are registered in `lifecycle/lifecycle.toml`'s
metadata-key registry (`[metadata.pr_close_disposition]`); `pr-facts.sh` only
reads them.

The marker lives on an OPEN anchor carrying `merge_result=pull_request`, because
that is exactly the set `pr-facts.sh` enumerates. An anchor closed before its PR
(a caller who runs bead-rehome directly) is already invisible to pr-facts and
needs no marker; the marker exists for the close whose anchor is still open when
the PR closes.

## The two halves

### 1. The sanctioned path: `assets/scripts/pr-dispose.sh`

Records the marker on the open anchor and closes the PR, so whatever closes a PR
as superseded/not-planned goes through one verb rather than a bare GitHub close.

```
pr-dispose.sh --anchor <bead-id> --successor <bead-id> \
              --kind re-homed|folded|fixed-upstream|duplicate|not-needed \
              [--successor-store rig:<name>] [--note "<why>"] \
              [--pr <num>] [--no-close-pr] [--dry-run]
```

It validates the kind against bead-rehome's set, requires the anchor to be OPEN
and carrying `merge_result=pull_request` (idempotent no-op if already disposed),
stamps the three keys and reads them back, then closes the PR with an explaining
comment (unless `--no-close-pr`, for an operator who will close in the UI). It
does NOT close the anchor: that terminal close is pr-facts's, through the one
consummation point.

### 2. `pr-facts.sh` honors the marker

The close arm, before abandoning, reads the marker off the anchor:

- **Marker present and valid** → run `bead-rehome.sh --origin <anchor>
  --successor <succ> --kind <kind> [--successor-store <store>]`. On success the
  anchor is closed with the disposition recorded; any already-open
  `pr-abandoned.<num>` visit is retired (best-effort, closed `gc.outcome=moot` —
  the question it asked is answered). No new visit is filed.
- **Marker absent** → today's behavior: `abandoned` + the rework-or-close visit.
  This is the preserved default for a genuinely unknown out-of-band close.

Failure is not silent and does not strand the marker:

- bead-rehome exit 4 (the pointer would not stick — transient) → log and skip;
  the anchor stays `merge_result=pull_request` and the next pass retries.
- bead-rehome exit 5/6 or any other non-zero (close refused, a conflicting
  successor already recorded, a bad invocation — a human is needed) → escalate
  under a DISTINCT key `pr-dispose-failed.<num>` naming the marker and the
  error, and leave the anchor open for repair. The generic rework-or-close visit
  is still not filed: the closer's decision was recorded, and the visit that a
  human sees names the real obstruction instead of re-asking the decision.

## What is preserved

- The default: an out-of-band close with no recorded disposition still abandons
  and files the rework-or-close visit.
- I5 (`doctor/check-closed-implies-landed`): the anchor is closed through
  `bead-rehome.sh`, a sanctioned terminal close that stamps `gc.superseded_by`,
  which the check already exempts — never a bare close that leaves a
  closed-but-unlanded anchor unexplained.
