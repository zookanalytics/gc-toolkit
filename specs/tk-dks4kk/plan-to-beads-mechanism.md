---
name: The plan-to-beads mechanism — decision record
description: Decision for tk-dks4kk on what makes a landed plan's target list a filing checklist. Records why the enumeration has to live in the document rather than the ledger, the declaration-plus-reader mechanism that was built, and which of tk-twp697's rejected options the operator's trade reopened. Read before proposing a different plan-tracking mechanism.
---

# What makes a landed plan's target list a filing checklist

## The decision

A scheduling document declares its target set as a marked table, and a doctor
check reads that declaration back against the ledger.

The document marks the table with `<!-- plan-targets -->`. The table's last
column binds each row to one of three things: a backticked bead ID, `none —
<reason>` for a member that deliberately gets none, or `landed: <what>` once it
is done. `doctor/check-plan-targets-filed` errors on a row that binds to
nothing and on a bead ID that resolves in no reachable store, and reports which
bound beads are still open.

The rule is in `docs/file-structure.md`, applied at write time by
`skills/filing-documentation`, and retrofitted onto
`specs/tk-z9nln/consolidation-plan.md` — the plan that dropped the target.

## Provenance

Filed from `tk-dks4kk`, 2026-08-26, carried from PR #455 through
`specs/2026-08-rewrite/cutover-runbook.md` step 9 item 12. The predecessor
`tk-twp697` measured the failure and stopped one step short of this, recording
why: *"If the operator wants a guarantee rather than visibility, that requires
the gate — and that trade should be made deliberately by them, not smuggled in
here under a documentation change."* This bead is that trade being made. Its
wording — *"the mechanism, not the doc convention"* — settles the question
`tk-twp697` left open, so the options that bead rejected on the grounds that
they were more than a documentation change are reopened here and re-judged.

The measurements are not repeated here.
[`specs/tk-twp697/plan-targets-never-filed.md`](../tk-twp697/plan-targets-never-filed.md)
holds them: the 21-hour window, the controlled comparison across three
set-shaped documents, and the second dropped target that applying the rule by
hand uncovered.

## 1. What had to become answerable

The bead states the requirement as a question that must have an answer: *this
plan landed, and these are the beads it produced.*

For that question to have an answer, four things must hold. The plans must be
findable. Each plan's targets must be enumerable. Each target must name its
bead, or record that it deliberately has none. Something must check the second
against the third.

`tk-twp697` delivered the third alone. That is why it could only offer
visibility: a convention that a human might apply produces no artifact anyone
can query afterwards.

## 2. Why the ledger alone cannot answer it

The attractive design is to put the binding in the ledger, where dispatchers
already look. Each target bead carries a pointer to the plan that scheduled it,
and the question becomes a metadata query.

It cannot work, and the reason is worth stating because the idea recurs. A bead
that was never filed carries no metadata. The missing target is the entire
failure, and the ledger has nothing to say about it — a ledger-side query
returns the beads that exist and is silent, by construction, about the row that
produced none. Only the plan's own target list knows how many members there
were.

So the enumeration has to live in the document. The ledger's job is to answer
whether each named bead is real, which is the half it can do well.

## 3. The mechanism

Two parts, and neither works alone.

**The declaration.** A marker plus a table, in the document, in the same PR.
The marker makes identification exact and opt-in, which matters because
guessing which documents schedule work is a heuristic with no good answer — a
plan, an audit and a ranked shortlist are the same shape as any other table.
The last column carries the binding, so the rule does not depend on a column
name; the live precedents in this repo call that column `Bead` in one document
and `Check` in another.

**The reader.** `doctor/check-plan-targets-filed`, ledger-only and read-only,
in the same idiom as the pack's other ten checks. It runs after the fact, on
the checkout, which is what the bead asked for: the failure it catches happened
in the window *after* a plan merged, and a pre-merge gate would not have been
looking then.

Four decisions inside the check that are load-bearing:

- **Every bead in a cell is verified, not just the first.** Target 1 of the
  consolidation plan was two deletions filed as two beads, and that split is
  what let one half go unfiled for a day. A binding that could name only one
  bead would have reproduced the original defect.
- **A bead ID must resolve.** Without this the check degenerates into "the cell
  is not blank", and a row could be satisfied by a plausible-looking string.
- **Code fences are skipped.** `docs/file-structure.md` shows the convention in
  a fenced example. Scanning it would make the document that teaches the rule a
  subject of it.
- **A vacuous pass says so.** The summary always reports how many documents and
  rows were examined, and an unreadable or wholly suspended ledger warns rather
  than passing. A check that watches nothing and prints OK is the failure it
  was built to prevent, wearing a green light.

## 4. What was rejected

**Parent-child edges from the plan bead to each target bead.** `tk-twp697`
found this attractive and deferred it. Re-judged under the operator's trade, it
is still wrong, and for a reason that is not about cost: `parent-child` carries
live readiness semantics, because `bd ready` excludes descendants of a blocked
ancestor. Hanging targets off a plan bead changes what the pool serves. A
tracking mechanism that alters dispatch behaviour is a worse trade than one
that does not, however clean the graph looks. It also does not solve §2 — an
edge to a bead that was never filed does not exist either.

**Generating the target table from the ledger.** Same defect as §2, plus
`generated/` is explicitly not a tier in `docs/file-structure.md`.

**A pre-merge gate on the PR that adds the plan.** This is the shape
`tk-twp697` assumed "the gate" meant, and it is the wrong point in time. The
consolidation plan's targets were droppable for 21 hours *after* it merged; a
gate at merge time asks the author to promise, which is what prose already did.
Reading the claim back afterwards is both cheaper and better matched to when
the failure happens.

**Leaving it at the convention.** This is what `tk-twp697` shipped and the bead
explicitly declines.

## 5. What this does not guarantee

The check is opt-in by the marker, so a document that declares no target set is
not watched. That hole is real and is not closable by this mechanism: deciding
that an arbitrary document *should* have declared a checklist requires guessing
what its output is.

What changes is where the omission sits. Before, a dropped target left no trace
anywhere. Now the standard names a concrete artifact — the marker — that a
reviewer can look for, and every declaration that does exist is machine-checked
from then on. The failure moves from invisible to opt-out, which is not the
same as prevented and should not be described as such.

The parser is also a markdown parser, with the limits that implies. A pipe
inside a table cell will confuse it. This is worth knowing and not worth
defending against.

## 6. Adoption

`specs/tk-z9nln/consolidation-plan.md` is bound: 6 rows, 5 beads, 1 still
outstanding. It is retrofitted rather than left alone so that the check watches
something real from the first commit.

The live case is worse than the retrofit suggests. The follow-up list in
`specs/2026-08-rewrite/cutover-runbook.md` — the document this bead was filed
from — has thirteen items, no target-list marker and no bead column, so
nothing can read it back. Three items name a bead in passing prose
(`tk-508bx9` at item 4, `tk-wz4igt` at item 9, `tk-43chr6` at item 13), and
item 12 is this bead, which the list never names. The diagnosed failure is
running in the document that reported it. Binding that list is not folded in
here: it needs a bead-by-bead walk of thirteen items, several of which are
large, and the runbook is a one-shot document with its own retirement path.

<!-- plan-targets -->

| # | Follow-up | Bead |
|---|---|---|
| 1 | Bind the 2026-08 rewrite runbook's 13 carried follow-ups | `tk-yshft8` |

Everything else this decision calls for is in the same PR and needs no bead:
the check, the rule in `docs/file-structure.md`, the write-time step in
`skills/filing-documentation`, the consolidation-plan retrofit, and the check's
registration in `docs/component-model.md` and `docs/install.md`.
