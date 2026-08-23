---
name: Design note — standing an idle decomposed row down to the dispatcher
description: Why a stranded row with no dead owner and no takeaway bands LOW rather than HIGH, why the takeaway clause is the one that carries the rule, why no gather had to be widened to make it safe, and the before/after census taken on the live board.
---

# The row was shouting a dispatch request at a human

Work record for `tk-9tbbk.3`. What is authoritative about the resulting
behaviour lives in `services/helm/README.md` (*Until somebody picks it up —
the dispatch stand-down*) and in the ranking-heuristic header of
`assets/scripts/gc-helm.sh`; this note records the reasoning, the two
clauses that were considered and rejected, and the measurements.

## What was funded

Cause 2 of the four mechanical causes measured under subject `tk-jr8rw`
(operator-origin, 2026-08-23: "~100 beads on the helm board, all requiring
me"), left as the next sitting's material once `tk-b3rga` landed.

A decomposed anchor with open children and nothing live in them bands HIGH
— the operator's loudest band — and renders `decomposed, idle — assign or
visit`. On the census taken for the bead, **twelve of the fourteen HIGH
rows carried that one byte-identical string**, so 86% of the loudest band
was a single derived sentence. The sentence names its own actor and it is
not the operator: assigning open work to a pool is a **dispatch**, which
`gc sling` and the dispatching agents perform and which no human performs
by hand.

The bead is explicit that this is `tk-b3rga` one band up — *band a row by
WHO it needs, not by what it IS* — and that the shipped shape is to be
copied rather than reinvented.

## The rule as shipped

A row is **awaiting dispatch** when it has the `stranded` shape (open
children, nothing live, no open visit), no child claimed by a dead session,
and **no `gc.takeaway`**. Such a row bands LOW, its frontier reads
`N open · awaiting dispatch`, and its NEEDS reads
`awaiting dispatch — no operator action`.

Two implementations, because there are two boards:
`assets/scripts/gc-helm.sh` (the jq render) and
`services/helm/internal/board/derive.go`. A fix landing on one does not
reach the other (`tk-9tbbk`).

## The four decisions worth recording

### The takeaway clause is the rule, not a qualifier on it

The bead's census names two HIGH rows that are NOT the defect — `sl-kg9z6`
and `tk-6v7nm`, which "carry real, distinct text". Both are idle by exactly
the counts that would otherwise stand them down. Reading what that text
says settles what the clause has to be: `sl-kg9z6` reports "PRs 557/559
held on operator" and `tk-6v7nm` ends "the enable-vs-backfill token trade
is the operator's call". Both are genuinely operator-facing, and the only
thing distinguishing them from the twelve is that somebody wrote a NEEDS
sentence for them.

So the clause is not "these two happen to be exceptions". It is the
principle the board already runs on, stated one level up: the authored
takeaway WINS the NEEDS cell everywhere else in both renderers, because
someone looked at the row and said what it wants. A derived rule that
quiets such a row overrules a judgement with a guess. Only a row rendering
the mechanical constant is rendering the thing this bead is about.

It also preserves every earlier ruling for free, which is how you can tell
it is the right cut rather than a convenient one. A decomposed `parked`
subject carries a takeaway **by definition** — the takeaway is how the kind
is selected — so `tk-a9k0l` ("open work under a parked row falsifies its
claim to want nothing") is untouched, and so is the same lesson for a ruled
decision (`tk-b3rga`). Neither needed a clause of its own.

### A dead owner is not a missing dispatch — and a husk is

These look identical on the board (nothing is moving) and are two different
actors. The `in_progress` status separates them:

| | child state | who owes it |
|---|---|---|
| dead owner | `in_progress`, assignee dead | a recovery — the pool will never re-offer a claimed bead |
| husk | `open`, unassigned, dead workflow over it | a dispatch — the pool re-offers it |

So the dead-owner clause keeps that row HIGH with its existing phrase
("dead owner — recover or reassign"), and the husk stands down. This
retired one assertion in `gc-helm.test.sh`'s `(HUSK)` case, which read the
band. What that case actually guards is that a husk is never counted as
**moving** — `stranded` true, `in_flight` 0, `in_progress_dead` 0 — and
those three assertions are untouched. The band assertion was how "no false
all-clear" was expressed back when the only quiet band available meant
"work is in flight"; LOW does not make that claim. The case now asserts the
new band with the husk/dead-owner distinction written next to it.

### LOW, not NORMAL

Same reasoning as the stand-down above, with its own numbers. NORMAL is
stale-bumped past fourteen days. Of the nine live rows this was measured
against, one was already 20 days old and four more were at 12 or 13 — so a
NORMAL stand-down would have passed its own acceptance criterion on the day
it landed and put five of nine rows back in ELEVATED inside a week.

LOW is also not a hiding place. Only kind `parked` is lifted out of the
ranked table into the web app's quiet section; a LOW epic stays in the
table, ranked last, with a phrase saying what it is waiting for.

### Rejected: reading `gc.routed_to` off the children

The one thing that would falsify "a dispatcher can take this" is an idle
child that no agent will take — a child carrying `gc.routed_to=human`. The
obvious guard is to read it, and it would have cost a widening of both
gathers: the bash epic roll-up projects children as `{id, status, assignee}`
and carries no metadata at all.

It is unnecessary, and for a structural reason rather than a lucky one.
**Every open bead carrying `gc.routed_to=human` is gathered as a `human`
anchor in its own right**, at ELEVATED, so it holds a row on the board
whatever its parent's band. A quiet parent cannot hide it. What a quiet
parent stops advertising is exactly the set of children a dispatcher can
take — which is the claim the rule is making.

Measured, not assumed: all 34 idle heads under the nine target rows were
plain open beads — no assignee, no route, not blocked. Zero human-routed.
`TestAwaitingDispatchCannotHideWorkNoAgentWillTake` pins the structural
argument rather than leaving it to be re-derived.

### Rejected: an age escape hatch

"Undispatched for N days means the dispatcher is broken, so tell the
operator" is attractive and is exactly the stale bump the LOW decision just
rejected. It would rebuild the noise on a timer. A dispatcher that has
stopped dispatching is a supervision fact about the *city*, not a property
of each of nine rows, and it belongs in a signal that says so once.

## What the guards are worth

All three clauses were mutated out and the suites re-run:

| clause dropped | what fails |
|---|---|
| `takeaway == ""` | `TestAuthoredTakeawayKeepsAnIdleRowLoud`, plus `TestParkedWithChildren`, `TestRuledWithChildrenIsBandedByItsRollUp`, `TestDedupKeepsHigherBand`, `TestStaleDoesNotBumpOtherBands` |
| `len(deadOwnerHeads) == 0` | `TestAwaitingDispatchDoesNotSwallowADeadOwner`, `TestDeadOwnerIsNotMoving`, `TestParkedNeverOutranksAttention` |
| `!held` | `TestHeldAnchorIsNotStranded` |

The collateral in the first row is the point: dropping the takeaway clause
does not just fail its own test, it reopens `tk-a9k0l` and `tk-b3rga`.

## Measurements

Paired control on the live loomington board, `board --json --limit=0` run
back to back from the HEAD binary and from the patched one, both returning
the same 64 anchors:

| band | HEAD | patched |
|---|---|---|
| HIGH | 12 | 2 |
| ELEVATED | 17 | 17 |
| NORMAL | 1 | 1 |
| LOW | 34 | 44 |

**Exactly ten rows changed band, and they are exactly the ten that carried
the retired phrase** — `sl-kg9z6.1`, `sl-kg9z6.2`, `sl-kg9z6.3`,
`sl-kg9z6.4`, `sl-kg9z6.5`, `su-xkmq`, `tk-190fp`, `tk-eemvf`, `tk-yhwfv`,
`tk-zhklc` — all HIGH → LOW. **No row moved UP**, and no row changed
frontier or needs without also changing band. The two HIGH rows that remain
are `sl-kg9z6` and `tk-6v7nm`, the two the bead named as not the defect.

Ten rather than the twelve the bead counted: `tk-4it3h` and `tk-9tbbk` had
left HIGH on their own between the census and the fix — `tk-9tbbk` because
the work on this bead was in flight under it. An earlier pair, taken twenty
minutes before, showed nine: `sl-kg9z6.1` was momentarily out of the band
and came back. The set is the phrase, not a fixed list of ids.

Cross-board parity was checked on the live city by rendering both boards
and comparing every row whose derivation INPUTS matched (`m_total`, `open`,
`in_progress_live`, `in_progress_dead`, `held`, `takeaway`, both waiting
lists) — 58 of 64 rows, zero mismatches on `severity`, `frontier` and
`needs`. The six excluded rows had drifted between the two runs, which the
comparison reports rather than averages over. Both boards independently
render zero instances of the retired phrase.

## What was deliberately not done

- **Changing the `stranded` wire field.** It is a shape claim — open work
  with nothing live in it — and that is still exactly true of a stood-down
  row. Nothing in the tree branches on it (the web app mentions it only in
  a comment), and repurposing it as an urgency flag would be a contract
  change this bead did not ask for. `model.go` and the `gc-helm.sh` header
  now say it is shape and not band.
- **The `held` inversion.** Opening a visit on an idle row now RAISES its
  band, LOW → NORMAL, where before it lowered it, HIGH → NORMAL. It reads
  correctly — a live conversation is something happening, an undispatched
  backlog is not — but it is the reverse of what the `held` clause was
  written for, and it is recorded in the README rather than quietly left
  for the next reader to trip over.
- **`tk-3a176`**, the sibling: epics not GROUPING their children, and an
  EMPTY epic sinking to rank 44. That is the too-quiet direction of the
  same board; this bead is the too-loud direction. Related, disjoint, still
  open.
- **`tools/helm-surface-fixture.sh`'s phantom-`gc helm` guard**, which is
  red at HEAD and stays red here — reproduced against a clean
  `git archive origin/main` tree (151 passed, 1 failed, the same one).
  Filed as `tk-paunpk`. Every other assertion in that fixture passes; the
  five it had pinning the retired behaviour were updated in place.
