---
name: Gate calibration — which checks an anchor carries
description: The rule for setting an anchor's check_set, and the default. Which gates a change gets, who may change them, when a non-code change is calibrated differently from a code change, and why the round cap is not the lever for either. Read it before hand-setting check_set or proposing a different cap.
---

# Gate calibration

Every anchor starts with `codex`. That is the default for a code diff and for
a document alike, it is stamped by machinery that never reads the diff, and
departing from it is a human act on a named anchor. This document is the rule
for that departure.

## Scope

**Mandate.** Which gates an anchor's `check_set` declares, what the default
is, who may widen or narrow it, and how that decision differs for a change
whose deliverable is prose.

**Boundaries.** The gate vocabulary, the marker grammar, and the merge
condition are [state-machine.md](state-machine.md) §Gates. The cadence that
dispatches and evaluates gates is
[refinery-merge-cadence.md](refinery-merge-cadence.md). How a reviewer grades
what they find is the review method in `formulas/mol-review.toml`, which this
document does not calibrate; see [The remaining lever](#the-remaining-lever).

## The default is `codex`, for prose as well as code

Three writers put the default on an anchor, and none of them reads the diff:

- `mol-refinery-patrol` stamps `check_set` on every transition into a gating
  state, from its `[vars.check_set]` value (default `codex`).
- `gate-ensure.sh` stamps its `--default` on any anchor whose `check_set` is
  absent or empty.
- `refinery-reconcile.sh` supplies that `--default` from
  `REFINERY_RECONCILE_CHECK_SET`, an environment tunable defaulting to
  `codex`.

Class-blindness here is deliberate, not an oversight. The checks-needed
decision has one holder (operator ruling 2026-08-24,
`specs/2026-08-review-gates/scope.md`). A dispatcher that derived `check_set`
from path shapes would put the decision to skip review in the least
reviewable place in the pack, and every dispatcher would then have to agree
on the same classifier or anchors would gate differently depending on which
one reached them first.

So a spec bead and a code bead start identical. Calibration is what a human
does afterward, and only afterward.

## `codex` is mandatory before the PR exists

`pr-open.sh` requires `check.codex=green@<live head>` to create the PR. It
does not read `check_set`. An anchor sitting at `pre_open_gate` whose set
omits `codex` deadlocks: `gate-ensure.sh` dispatches nothing for a set of
`approval` or `none`, and `pr-open.sh` waits for a marker that nothing in the
cadence will go on to produce.

Two consequences:

1. Every branch gets one codex review, whatever it contains. There is no
   pre-open opt-out and this document does not create one.
2. **Calibration is a post-open act.** Narrowing a set before the PR is open
   strands the anchor. Widening is safe at any point.

## Widen to `codex,approval` when the document binds work not yet done

A design, a spec, a plan, or a change to operative doctrine is not checkable
against the tree, because the thing it describes does not exist yet. Its
correctness is a judgment about work that has not happened, and the person
who owns that judgment is the only party who can settle it.

Declare `approval` on those anchors. `merge.sh` then requires an external
APPROVED review at the live head, which names that person as a gate from the
start instead of leaving the round cap to reach them once the rounds are
spent. Codex stays in the set and keeps doing what it is good at on a prose
diff: a claim about the tree that is false, a command line that does not run,
an internal contradiction.

Widening is a set union and is the sanctioned direction of change. It never
strands an anchor and it never reduces what has to be true before a merge.

## Narrow to `approval` to release a capped prose anchor

For an anchor already at `pull_request` whose codex gate has spent its rounds
and whose open findings are judgment rather than fact, a human sets
`check_set=approval`.

`merge.sh`'s gate check inspects only the gates the set declares, so a
stranded `check.codex=exception@<oid>` becomes inert rather than needing to
be cleared. `signoff.sh` remains the sole writer of `check.*`; nothing about
this narrowing writes a verdict, and no marker is edited by hand.

The merge condition after the narrowing is an external APPROVED review at
the live head. That is the same human the cap was going to route to, reached
without spending further rounds to get there.

Record the reason on the anchor's notes in the same act. A narrowed set with
no recorded reason is indistinguishable from a mistake.

## `none`

`none` is the explicit gateless opt-out, human-only, and post-open for the
same reason narrowing is. Use it for a change that nothing downstream acts
on. It is rare: a record filed alongside the work it describes rides that
work's gate and needs no opt-out of its own.

An empty `check_set` is never `none`. Empty means never normalized, and every
reader holds the merge on it.

## The round cap is not the lever

`GC_MAX_REVIEW_ROUNDS` (default 3) is enforced at two points, and a capped
anchor therefore has two shapes. `signoff.sh` enforces it at verdict time: it
stamps `check.<g>=exception@<head>`, sets `blocked_reason`, and routes the
anchor to a human. `gate-ensure.sh` enforces it before dispatch: a spent
`dispatch_count` declines the next round, the merge stays held, and no marker
is written and nobody is routed. So an anchor can be capped with no
`exception@` on it at all, visible only as a held merge. Both shapes release
the same way.

A lower cap for prose work therefore buys nothing. The cap's terminal action
*is* the operator ticket, so lowering it makes the ticket arrive sooner
rather than less often, and it arrives with fewer findings attached. It does
not reliably end the loop either: signal-loom `sl-kg9z6.1.1` ran to seven
review rounds on a zero-code branch under a cap of 3, the rounds past it
proceeding on hand-authorized re-gates (tk-10521).

Calibrate the gate, not the cap.

## A capped anchor is not terminal, but nothing automatic moves it

Two facts that look contradictory and are both true:

- A fresh approving round still releases the gate, at the same head.
  `signoff.sh` stamps `green@<reviewed-oid>` and exits on the approve path
  before it computes rounds against the cap.
- No cadence pass will ever dispatch that round, and two independent guards
  see to it. `gate-ensure.sh` treats `exception@` as settled and skips it at
  any head, so moving the branch does not re-arm the gate; and a
  `dispatch_count` at the cap declines the round even with no marker present.

A human closes that gap, either by dispatching one more review at the unmoved
head or by narrowing the set as above. On 2026-08-26 signal-loom `sl-bgmuy`
went from `exception@3ecc2def` to `green@3ecc2def` at an unmoved head, an
instance of the first path.

Weigh the two knowing what the capped head is. `signoff.sh` enforces the cap
at verdict time and files no rework child on that path, so `exception@<oid>`
always names the head a reviewer just read and rejected, and the findings that
stopped it are stated on the review beads under the anchor. Read them before
choosing. Another round is a second opinion on code that has already been
judged, so it is the right move when the findings turn on a fact the reviewer
could have checked and did not. When the findings turn on judgment about work
that has not happened, no further reviewer will settle them and the narrowing
is the honest disposition.

## Who applies it

A human, on a named anchor, with the reason in that anchor's notes. No
dispatcher, formula, or reviewer may pre-set or shrink a `check_set`
(operator ruling 2026-08-24).

When triage lands (`specs/2026-08-review-gates/scope.md`), triage becomes the
sole authority over `check_set` and this document becomes its rule set for
non-code diffs: the widening above is a triage add, and the narrowings are
charter-bounded waivers. `none` stays human-only under that design too.

## The remaining lever

Calibrating `check_set` decides *who* gates a change. It does not change how
a reviewer grades one.

The review method (`formulas/mol-review.toml` §3 and §4) is written for code:
it asks the reviewer to run the tests the diff touches and grades a P1 as
wrong behavior on a reachable input. On a design document every further
reachable interleaving satisfies that definition, which is a review surface
with no terminus. That is what produced seven rounds on a zero-code branch
(tk-10521), and it is untouched by anything in this document.

Changing it means giving the method a second mode, which is a change to the
review contract and belongs to its own bead.
