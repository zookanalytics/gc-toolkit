---
name: The open-PR-with-an-absent-marker cell, and the pre-open gate that minted it
description: Disposition record for tk-qs1j6. The repair half the bead asked for shipped with the #465 rewrite; read this before re-reporting a held anchor with a missing marker. The prevention half did not ship, and this bead lands it — plus the comma-list split defect found while landing it.
---

# Pre-open gate reads check_set

tk-qs1j6 was filed by the shutupandlisten refinery against
`check-set-heal.sh`, `pre-open-resolve.sh` and `merge-skill.sh`. All three
were deleted by the #465 rewrite (`9a6b86ae`), which replaced them with
`gate-ensure.sh`, `pr-open.sh`, `merge.sh` and `pr-facts.sh`. The rewrite
implemented the bead's repair item. This record pins that evidence, and
records what the bead's remaining two items became.

## What the bead reported

A 2x2 over "where is the anchor" and "what shape is the marker". tk-t46nq
covered pre-open + absent, tk-w26b6 covered open-PR + stale, and this bead
covered the fourth cell: an OPEN, non-draft, approved PR whose anchor
declares `check_set=codex` and carries no `check.codex` at all. `merge.sh`
correctly refused to land it, and no pass could raise it, so the PR was
immortal.

## Item 1 shipped: every gating anchor is re-examined, marker or none

`gate-ensure.sh:285` enumerates both sub-states in one loop —
`pre_open_gate` and `pull_request` — and classifies each declared gate
against the live head with no reference to how the anchor got there. An
absent marker is one of the classified cases (`gate-ensure.sh:395`), and it
falls through to the same dispatch block a stale `green@` reaches. That is
the general form of the fix the bead asked for, and it closes all three
cells at once, which is what the bead predicted a general item 1 would do.

The old `check-set-heal.sh` behavior the bead diagnosed — a dispatch offered
only on the path where it HEALS an absent check_set, never on an already
normalized one — has no counterpart in `gate-ensure.sh`. Stamping the
default and raising the gates are sequential steps over the same row, not
alternative branches.

`assets/scripts/gate-ensure.test.sh` pins the absent-marker dispatch. The
suite passes 208/0 with `GC_RIG` unset.

## Item 2 did not ship: the publish gate read one gate by name

The bead's second item asked that the pre-open decision be made
"structurally unable to open a PR while a declared gate has no marker" —
the ordering the merge-push prose describes, enforced in code at PR-create
time. `pr-open.sh` read `.metadata["check.codex"]` by literal name and never
read `check_set`. Two failures followed, in opposite directions:

- **A declared gate could be published past.** With `check_set=codex,triage`
  and only `check.codex` green, `pr-open.sh` published a non-draft PR while
  `check.triage` was absent. That is this bead's own titled state, minted by
  the arm whose job is to prevent it.
- **An anchor could never publish.** With `check_set=none` (gateless by
  choice) or any set that does not name `codex`, `pr-open.sh` waited on a
  marker no arm writes: `gate-ensure.sh` raises only the gates the set
  declares. The anchor held at `pre_open_gate` for good.

`pr-open.sh` now derives the gates from the anchor's own `check_set` and
requires each `green@<live head>`, dropping `none`/`off` and `approval`
exactly as `merge.sh:89` `hold_gate` does. An empty set is held, never read
as ungated — the same rule `merge.sh` states, and gate-ensure stamps the
default earlier in the same pass. `approval` is dropped because it is
evidenced by an external GitHub review, which cannot exist before the PR
does; `merge.sh` enforces it at the merge.

`liveness-sweep.sh` already computed the correct predicate
(`pre_open_all_green`), so the pack held two disagreeing answers to "is this
anchor gated". They now agree.

## The comma-list split defect, found while landing item 2

`check_set` is a comma list. Four shell splitters wrote it as

    tr ',' '\n' | tr -d '[:space:]' | sed '/^$/d'

`[:space:]` includes the newline, so the second `tr` deleted the separators
the first one created and `codex, triage` became one gate named
`codextriage`. Verified against the pre-change scripts in a parallel tree:

| Arm | What it did with `codex, triage` |
|---|---|
| `gate-ensure.sh` | dispatched one review for gate `codextriage`; neither real gate was ever dispatched for |
| `pr-facts.sh` stale scan | filed 0 re-reviews for a genuinely stale `check.triage` |
| `pr-facts.sh` retarget | cleared `check.codextriage`, leaving the real markers standing |
| `pr-open.sh` | (the new gate) held on a gate that does not exist |

Every one of those is this bead's failure mode reached by another route: a
declared gate that no pass can raise. The split is now
`tr ',' '\n' | sed 's/[[:space:]]//g; /^$/d'`, which strips per line and
cannot rejoin. `merge.sh` and `liveness-sweep.sh` split in jq and were never
affected.

`tk-xhwits` found the same defect independently and fixed its `gate-ensure.sh`
copy as `tr -d '[:blank:]'`. Both forms are correct on the realistic input and
the two branches will collide on this line. This one was kept because it
matches what the merge predicate does: `merge.sh` strips with
`gsub("[[:space:]]"; "")`, which also removes CR, and the point of this bead's
change is that the publish gate and the merge gate answer the same question
the same way. `[:blank:]` is space and tab only.

## Item 3 answered by item 1, not by a new escalation

The bead asked that "gating anchor, non-`none` check_set, no marker, no
in-flight review" escalate rather than hold silently. In the rewrite that
condition is not a contradiction to report — it is the dispatch trigger. An
anchor in it gets a review, and the residues that a dispatch cannot fix
escalate on their own keys: `review-wedge` for a poured workflow that ended
with no verdict, and `dispatch-runaway` for an anchor that has spent its
dispatch ceiling. Adding a third visit for the state that already resolves
itself would file one per pass against work already in flight.

## Relationship to the open work on gate naming

`tk-7h5l3m` is an operator bead against the `docs/state-machine.md`
paragraph that documented this same coupling, and its sitting was open when
this landed. Its first-reaction proposed splitting the ask: land
"`pr-open.sh` reads `check_set`" on its own, and fold the broader gate
naming and structure question into `tk-xhwits`. This bead lands the first
half, so no separate bead needs filing for it. The second half is untouched
here.

`tk-xhwits` carries an unlanded branch with a declared gate menu
(`docs/review-charter.md`), `signoff.sh --add-gates/--waive-gates`, and
per-gate `dispatch_count.<gate>`. It overlaps this change in files but not in
decisions. At `9ebab091` it edits `pr-open.sh` in one place: the verdict
replay's `REVIEW_ID` lookup, which it narrows to the CLOSED codex review
pinned to the head the PR opened at, on the stated grounds that a `check_set`
can carry several gates. That is the block immediately above the gate this
bead rewrites, so the two are adjacent but independent; whichever lands
second rebases over a few lines of context.

Two notes for whoever lands the second one. Its narrowed lookup selects the
codex verdict by name while the comment label this bead made gate-generic
says "Pre-open signoff" — the label and the body should be reconciled in one
direction at that point, and its selection is the more careful of the two.
And it edits `gate-ensure.sh` and `pr-facts.sh` too, so the comma-split fix
below wants re-checking against its versions of those splitters rather than
assumed.

The stage-column shape that first-reaction proposed — each gate declaring
`pre-open` or `pre-merge` — would narrow the list `pr-open.sh` now iterates.
It does not need the predicate rewritten again.

## Residue

`docs/authority-map.md` conditions a `check_set` departure on "a narrowing
only once the PR is open". That row's stated reason was the strand this
change removes; whether the restriction should now be relaxed is a human
authority question and was left as it stands.
