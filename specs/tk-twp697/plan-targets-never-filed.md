---
name: Why a merged plan's targets never became beads — and the one-column fix
description: Recommendation for tk-twp697. Measures every set-shaped document in this repo and finds the conversion failure is mechanical, not a lapse of diligence: a document that writes its follow-up bead IDs into its own rows converts every member, one that promises in prose loses them. Read before writing a plan, an audit, or any document whose output is work.
---

# A plan's targets never became beads: what actually failed, and the cheapest thing that fixes it

## Recommendation, up front

**When a document's output is a *set* of follow-up work, file each member as a
bead in the same PR as the document, and write the bead ID into the row that
proposes it.** A member that deliberately gets no bead says so in the same
place. As members land, edit their rows to name what landed instead of the bead.

Nothing new gets built. No gate, no detector, no sweep, no patrol step. The rule
is codified in `docs/file-structure.md` (§ *A document whose output is a set of
follow-up work names the beads in its rows*), applied at write time by the
`filing-documentation` skill, and retrofitted onto the one live plan that lacked
it (`specs/tk-z9nln/consolidation-plan.md`).

This is a *visibility* remedy, not an enforcement one, and that distinction is
argued in §6 rather than glossed.

## Provenance

Filed from `tk-twp697`, 2026-08-24, after the operator's judgement on being told
Target 2 of the consolidation plan had no bead: *"The 'and Target 2 has no bead.
Nobody filed it.' IS A FAILURE OF THE CITY"*. Ledger measurements are against
the gc-toolkit store at 2026-08-24T05:30Z (977 open beads, 5,388 closed); source
measurements against `origin/main` at `5c1499c`.

## 1. The record is worse than the bead's own scoreboard

The bead credits the plan with filing two of its four targets. It filed **one**.

| Target | Bead | Created | Relative to the plan merging at 2026-08-23T07:33:31Z |
|---|---|---|---|
| 1 — close the graph.v2 step chain | `tk-zab6q` | 2026-08-22T06:03:49Z | **25 h before.** The plan did not file it; it already existed |
| 2 — finish the helm consolidation | `tk-clvkf6` | 2026-08-24T04:28:08Z | **+20 h 55 m**, and only because a sitting tripped over it |
| 3 — retire `reconcile-refinery-handoffs.sh` | `tk-qf2l0j` | 2026-08-23T13:10:45Z | +5 h 37 m — the only target the plan actually converted |
| 4 — one control-char scrubber | none, **by design** | — | The plan folds it into whichever target touches a scrubber first |

Of the two targets that needed filing after the plan merged, one took 5½ hours
and one took 21 and needed a human. The plan's own sequence said of Target 1
*"file it now"* — for a bead that had been open for a day. The document could not
tell what had already been done, because nothing in it recorded that.

### The window was real, not hypothetical

| time (UTC, 2026-08) | event |
|---|---|
| 23T07:33:31 | plan merges (PR #435). Target 2 scheduled. No bead |
| 23T07:37 | `tk-sfg2e` filed: *add a closed-dispositions view to `gc-helm.sh`* — **+4 min** |
| 23T08:37 | first commit, **+283 lines into `gc-helm.sh`** (plus +304 of test for them) — +64 min |
| 23T09:14 | second commit |
| 24T04:28:08 | `tk-clvkf6` filed. Target 2 becomes a bead, +21 h |
| 24T04:28:49 | PR #439 closed unmerged — **41 seconds later** |

`gc-helm.sh` is 2,056 lines and Target 2 exists to cut ~2,370 from the helm
surface; PR #439 proposed growing it by 14%, and its test file by 22%. The
counterfactual is
therefore not speculative: a bead filed in the plan's own PR would have existed
**four minutes** before the conflicting work was filed and **64 minutes** before
its first commit.

The 41-second gap between Target 2 becoming a bead and PR #439 being closed is
the whole diagnosis in one line. The bead and the cancellation were the same act
of human attention. Nothing systemic produced either one.

## 2. Sets lose members; single promises do not

Eleven documents in `docs/` and `specs/` promise follow-up beads. Most of those
promises were kept, and checking which ones is what locates the defect.

The promises that were kept are all **single items**, and each was honoured
within a day, usually by the same molecule:

| Document | Promise | Outcome |
|---|---|---|
| `specs/tk-fyzvk/analysis.md` | *"implementation … lives in a follow-up bead"* | `tk-yvtiv`, next day, closed |
| `specs/tk-6hm32/analysis.md` | *"A follow-up implementation bead should be filed"* | `tk-yvtiv` (same bead, both docs), closed |
| `specs/tk-5ib0r/investigation.md` | *"It should be filed separately"* | `tk-5ttye`, `tk-xesf6`, same day |

A single promise is either kept or **obviously** absent — one item, one question,
asked once. A *set* is different: it can be three-quarters converted and still
read as finished, because nothing anywhere records which rows were converted.
That is the whole mechanism. The plan did not fail because someone was careless;
it failed because a four-row table has no memory of which rows have been dealt
with, and a partly-converted set looks exactly like a finished one.

## 3. The controlled comparison

Three documents in this repo are set-shaped — their deliverable is an enumerated
list of follow-up work. Same rig, same month, comparable authorship. They differ
in one thing.

| Document | Members | Bead IDs in the rows? | Converted |
|---|---|---|---|
| `docs/component-model.md` §3 | 6 UNCHECKED invariants | **Yes**, written at authoring time | **6 of 6**, all filed 2026-08-23, the day the document was written |
| `specs/tk-23wdf/context-budget-ledger.md` §7 | 6 ranked candidates (+8 findings) | **Yes**, and maintained in place | **All.** `tk-0981e`, `tk-dy7sb`, `tk-4dvem`, `tk-yhwfv.1` |
| `specs/tk-z9nln/consolidation-plan.md` | 4 targets | **No** | 1 of 3 filed from the plan; the largest waited 21 h |

Two details make this more than a correlation.

**The plan is fluent in bead IDs.** It cites twelve of them in its body as
provenance — `tk-y389z`, `tk-i48ca`, `tk-jww3y`, `tk-3yj8g` and more. Not one
appears in a target row. The convention was not unknown to its author; it was
simply never applied to the document's own output.

**A within-document control.** `tk-23wdf`'s candidate 6 was the one row whose
text promised a bead without naming one — *"worth a follow-up bead, not the
one-line hygiene delete an earlier draft assumed"*. It survived anyway, because
the row itself was maintained: it now reads **BANKED (tk-yhwfv.1)**. The same
document's F2 and F4 rows carry `tk-dy7sb` and `tk-4dvem` inline. Keeping the
rows current is what kept the set whole.

`docs/component-model.md` states the maintenance half explicitly, and it is
worth quoting because it is the part people drop: *"when one lands, edit the row
to name the check instead of the bead."*

## 4. Applying the rule once, by hand, found a second dropped target

The recommendation was tested before being written down: walk the live plan's
target rows and ask, per row, *which bead is this?* Target 2 was already known.
Target 1 was not.

The plan states Target 1 as **"close the graph.v2 step chain … *and retire the
quiesce sweeper*"** and puts its entire 2,099-line figure on it. Those 2,099
lines *are* the sweeper — `quiesce-completed-workflows.sh` (877) plus its test
(1,222). `tk-zab6q` / PR #443 landed only the close path. **The deletion, which
is where every one of Target 1's lines lives, had no bead.**

Its precondition — the plan's *"watch one full cycle finalize, then delete the
sweeper"* — turns out to be met. Open step beads by pour hour:

| pour hour (UTC) | still-open step beads |
|---|---|
| 2026-08-23T13Z | 14 |
| 2026-08-23T14Z – 2026-08-24T03Z | **0** |
| 2026-08-24T04–05Z | 91 (13 chains poured 04:28–05:06, in flight) |

The last chain to strand was poured **four hours before #443 went live** at
2026-08-23T17:18:47Z. Fourteen hours of pours have closed cleanly since, and
store-wide there are **zero** open step beads carrying `gc.outcome` — the free
detector for a closed step reopened by session teardown. The husk stock is still
624 beads (63% of the open ledger), but a chain is only re-offerable through its
one unblocked head, and exactly **one** pre-#443 `load-context` bead is still
pool-routed (`tk-f5bz4`).

Filed as **`tk-eh0r3m`**, with the caller inventory the delete needs: the single
live invocation is one step in `formulas/mol-witness-patrol.toml`, whose removal
must rewire `detect-stalled-workflows`'s `needs` edge, and five further files
cite the script as *owner of a concern* — several defining themselves by
contrast with it — so the delete has to relocate that knowledge rather than
grep the name away.

**This is the argument for the rule.** One pass over one plan's rows, costing
minutes, surfaced the highest-ranked target in the document sitting unfiled for
a day, hiding behind a sibling bead that had landed. A row that had to carry an
ID could not have hidden it.

## 5. What was considered and rejected

**A gate, detector, sweep or patrol step that checks a merged plan's targets
against the ledger.** Ruled out twice over: the plan forbids it in its own words
(*"add a gate/budget/review step … the fourth is the process this document was
asked not to create"*), and the operator's standing position is less code and
fewer things to break. The plan itself measures 13,116 lines — 37% of
implementation shell — as compensating machinery already. Another detector is
the disease.

**Generating the target table from the ledger.** Genuinely mechanical, and
rejected on cost: it means a new generator, and `generated/` is explicitly *not
a tier* in `docs/file-structure.md`. New code to enforce a convention that two
documents already follow by hand is the wrong trade.

**`parent-child` edges from the plan bead to each target bead,** so the set is
answerable from the ledger with `bd show`. Attractive — the ledger is where
dispatchers actually look — and it needs no new code, `gc bd dep` exists. Not
recommended *yet*: `parent-child` has live readiness semantics (a blocked
ancestor cascades to hide children from `bd ready`), so hanging targets off a
closed plan bead is a change to dispatch behaviour, not a documentation change.
It would need its own validation, which costs more than the disease. Recorded
here rather than filed, deliberately: filing a speculative bead to investigate
adding graph edges is exactly the process inflation this document is meant to
avoid.

**Accepting the gap and relying on the operator to catch it.** This is the
status quo, and its measured cost is 587 lines of work (283 of them in the file
scheduled for reduction) walking the wrong way for 21 hours, caught by a human
on review. Also the reason the option cannot simply
be dismissed: it *did* work. It is rejected because the row-ID convention costs
approximately nothing and does not consume the operator's attention.

## 6. The honest limit

This is an instruction-dependent remedy, and this repo's own doctrine is that
instruction-dependent fixes fail silently. Two things make it the right call
anyway, and neither is that instructions are reliable.

**The failure stops being silent.** Today a missing target bead is recorded
nowhere: the plan's prose promise is satisfied or not with no trace either way.
Under the rule the omission is a blank cell in a table, in the diff of the PR
that adds the document — read by the codex gate and the operator who already
review it. No new check is created; an existing one is given something to see.

**The only mechanical alternative is the forbidden gate.** Between a convention
with two working precedents in this repo and a detector the plan explicitly
rules out, the convention wins.

What it does **not** do is guarantee filing. A determined author can ship a
table with an empty column, and nothing will stop them. If the operator wants a
guarantee rather than visibility, that requires the gate — and that trade should
be made deliberately by them, not smuggled in here under a documentation change.

## 7. What this document schedules

Applying its own rule, the output set is one row:

| # | Follow-up | Bead |
|---|---|---|
| 1 | Retire `quiesce-completed-workflows.sh` — consolidation plan Target 1's unfiled second half, 2,099 lines | **`tk-eh0r3m`** |

Everything else the recommendation calls for is in the same PR as this document
and needs no bead: the rule in `docs/file-structure.md`, the write-time step in
`skills/filing-documentation/SKILL.md`, and the bead column retrofitted onto
`specs/tk-z9nln/consolidation-plan.md` (Targets 1–4, including Target 4's
deliberate *none*). A bead whose complaint is that scheduled work never becomes
beads should not hand back a fresh list of promises.
