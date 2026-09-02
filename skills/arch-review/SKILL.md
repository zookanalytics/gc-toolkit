---
name: arch-review
description: The method for the arch gate — an architectural review that holds a diff against the repo's charter rather than against the whole codebase, asking whether the change fits the declared layer map and passes the admission test. Use when you hold a review bead whose check_name is arch, or when asked whether a change belongs where it was put. Covers the charter-first reading order, the five layer questions, and the rule that a design objection goes to a person as a visit instead of looping as rework.
compatibility: Requires Gas City (gc CLI, $GC_* env, beads).
---

# Architectural review

You read exactly three things: the charter, the review bead, and the diff.
Not the whole repo. The charter carries the contract; if you find yourself
opening files the diff does not touch to reconstruct that contract, the
charter is what is failing, and saying so is a finding.

Correctness is not your gate. Bugs, edge cases, and test coverage belong to
`codex`, which is already dispatched on this same commit. Yours is placement:
does this change fit the structure the repo declares?

## Reading order

1. **`docs/review-charter.md`** — the layer map, the admission test, and the
   gate menu. It names the single writers and the states they own.
2. **The review bead and its anchor** — what the change was asked to do.
   A change that does what it was asked in the wrong place is still a finding;
   a change that deviated and is better for it is worth saying so.
3. **The diff at the pinned commit** — `git diff "origin/$BASE...$REVIEWED_OID"`.
   Three dots: you judge what the branch changed, not what the base moved
   underneath it.

Follow the charter's own pointers only when a question needs them —
`component-model.md` for the primitive list and the invariant bindings,
`architecture.md` for the boundary, `state-machine.md` for the gate and
transition tables. Following one pointer is reading the contract; opening the
tenth file is reconstructing it.

## The five questions

**1. Is it healer-shaped?** Does the change add a pass that repairs state
some other writer should have written completely? The healer category is on
the discard list: every transition is one atomic write by the component that
caused the change, with a read-back. A new reconciler, sweep, or repair arm
is a finding against the writer that leaves the state half-written.

**2. Is mechanical work living in formula prose?** A formula step tells an
agent what to do; deterministic logic belongs in a script the step calls. A
step that asks an agent to compute, compare, or decide something a script
could is a step that fails differently every time it runs.

**3. Is design being carried in prose?** A rule a reader must extract from a
paragraph is not enforced. If the change states a constraint, ask what fails
when it stops holding. An invariant names its doctor check in the same
change, or it is not an invariant.

**4. Has a document grown past its mandate?** Every doc declares a `## Scope`
with a mandate and boundaries. Content that belongs to a neighbour creates
two places to keep one fact true, and one of them will rot. Point at the doc
whose mandate covers it.

**5. Does it pass the admission test?** A new component answers "cost of not
having it". A new state is declared in `lifecycle/lifecycle.toml` and names
its writer. A new metadata key is registered. A new invariant names its
check. The charter carries all four; a change that adds one of these without
its answer is a finding whatever its merits.

## A decision is not a defect

`request-changes` is for a defect: a specific change, on a named line, that
the author can make. It files one rework child, and the loop converges when
that child lands.

A disagreement about where something belongs, or whether it should exist, is
not that. Two defensible placements, a primitive that would have to move, a
boundary that would have to be redrawn — none of these can be resolved by
handing them back to the author, and trying is the reviewer-fatigue loop the
foundation forbids. Put the choice in front of a person instead:

```bash
SCRIPTS=""
for c in "${GC_RIG_ROOT:-}" "$(git rev-parse --show-toplevel 2>/dev/null)" "${GC_CITY_PATH:-}/rigs/gc-toolkit"; do
  [ -x "$c/assets/scripts/escalate.sh" ] && { SCRIPTS="$c/assets/scripts"; break; }
done
"$SCRIPTS/escalate.sh" --subject "$ANCHOR" --key arch-decision \
  --message "<the choice, the options, what each costs, what you would do>"
```

The key names the situation and the subject narrows it, so one open visit
stands per anchor; a second, different decision on the same anchor needs its
own key.

Frame it as a decision, not as an objection: what the change does, which
contract it strains, what the alternatives cost, and what you would do. A
visit that only says "this feels wrong" spends the operator's attention and
returns nothing.

Then give the verdict the change itself earns, and name the visit in the
body. `request-changes` when the diff needs work whichever way the decision
goes; `approve` when the change stands on its own and the decision is about
what comes after it. What you may not do is stamp the gate green while
pretending the question was answered, or file a rework child whose only
content is a question its holder cannot answer.

## Approving

Approve when the change fits: the layer questions come back clean and the
admission test is answered. Say what you checked and what you did not — an
honest coverage line is worth more than an implied "I read everything".
Remaining P2 observations ride along in the verdict body as non-blocking
notes; they do not hold the gate.
