---
name: Non-code gate calibration — what the two PR#477 objections settled
description: The record of tk-rbeq4f. Why PR#477's gate-calibration doctrine was rejected at the premise, what check_set actually is and where its default lives, the four gate-machinery facts the tree had wrong, and why the round cap was not lowered for prose. Read it before proposing a check_set default, a prose-specific cap, or a new gate document.
---

# Non-code gate calibration: what the objections settled

PR#477 proposed `docs/gate-calibration.md`, a 180-line doctrine for which
gates a spec or design bead should carry. The operator closed it unmerged on
2026-08-26 with two inline comments, both on the premise rather than the
wording:

- at line 8, on "Every anchor starts with `codex`. That is the default for a
  code diff and for a document alike" — *"Ummm, no. Codex is just an agent, it
  is definitely not some default anchor"*
- at line 64, on the narrowing procedure — *"What is all this doing in a
  random document?"*

A converse sitting on tk-9heqfh checked both against the tree and agreed with
both. This bead started from the objections. Nothing from the deleted document
was carried forward as a starting position.

## Objection 1: what the policy object actually is

`codex` is a gate name. Review-gate names are opaque to the machinery that
acts on them: `gate-ensure.sh` dispatches a review for whatever names it finds
in an anchor's `check_set`, `signoff.sh` writes `check.<name>`, and `merge.sh`
requires every name in the set to read `green@<live head>`. None of the three
knows what any name means. Three names are not review gates, and every reader
of the set knows them by name: the `none` and `off` sentinels, and `approval`,
which `merge.sh` satisfies from GitHub's review state rather than from a
marker.

The policy object is `check_set` itself, and it lives on the anchor. Its
starting value is configuration, set at two writer sites that never read the
diff:

- `formulas/mol-refinery-patrol.toml` `[vars.check_set]` (default `codex`),
  stamped on every transition into a gating state.
- `assets/scripts/gate-ensure.sh` `DEFAULT_CHECK_SET`, applied only to an
  anchor whose set is absent or empty, and supplied by
  `refinery-reconcile.sh` from `REFINERY_RECONCILE_CHECK_SET`.

`lifecycle/lifecycle.toml` `[gates] check_set_default` records the same value
in the metadata registry. Nothing reads that entry, and no drift check pins it
against the two writers; that gap is filed as tk-dgsi8a.

So no default belongs in a document. A document that states the value becomes
a third copy of a tunable, and it goes stale the first time a rig tunes it.
Stating that value as doctrine is what turned an agent's name into a policy.
What a document owes the reader is the name of the object, the sites that set
it, and who may depart from it.

`codex` is load-bearing in exactly one place beyond configuration:
`assets/scripts/pr-open.sh:202` reads `metadata["check.codex"]` by literal name
and never consults `check_set`. That is a coupling, not a policy, and it has
one consequence worth stating: an anchor whose set drops `codex` while still
at `pre_open_gate` strands, because gate-ensure raises only the names the set
declares and nothing then produces the marker pr-open waits on. This is why
narrowing is a post-open act.

## Objection 2: nothing here needed a new home

Every subject the rejected document covered already had an owner:

| Subject | Owner |
|---|---|
| gate vocabulary, marker grammar, merge condition, the round cap | `docs/state-machine.md` §Gates |
| who may change `check_set`, under what evidence | `docs/authority-map.md` |
| the actor that will own `check_set` once triage exists | `specs/2026-08-review-gates/scope.md` |

This bead amended those three and created no fourth. `docs/authority-map.md`
gained the row its own rule already required: "A component that needs a power
not granted here is a design change, not an implementation detail — amend this
table in the same PR." Changing an anchor's `check_set` was such a power and
had no row.

The one thing the rejected document held that is neither vocabulary nor
authority is operational judgment about a capped prose anchor. It is recorded
below, in this bead's own record, which is where a judgment held by no
component belongs.

## The four machinery facts the tree had wrong

Each was established by tk-9heqfh, re-verified against the tree at `24e1bc7`,
and re-verified at every rebase since: `81b2734`, then `eb68ab3`, then
`0fb31c7`, whose line numbers the citations below carry. Facts 1 and 2 were
overtaken by those rebases and are recorded below as they resolved.

1. **`exception@` did not stale on a head move; tk-at7fur settled that it
   should.** At `24e1bc7`, `docs/state-machine.md` said the marker "holds
   until the head moves" while `gate-ensure.sh:259` matched `exception@*` and
   continued at every head, so no commit re-armed the gate. This bead did not
   own which side of that divergence was the error, and said so. tk-at7fur
   did, and it landed as #486 on 2026-08-27, before this branch reached main:
   `gate-ensure.sh:391` now compares the recorded oid to the live head and
   re-arms a stale exception, and `pr-facts.sh` files its stale-gate
   re-review child for `exception@` alongside `green@`. The doc text that was
   wrong at `24e1bc7` is true at `0fb31c7`, so this branch carries main's
   wording rather than the correction it was written with.
2. **The round cap was enforced at two points; tk-gr420e settled that it
   should be one.** At `eb68ab3`, `signoff.sh` enforced it at verdict time and
   `gate-ensure.sh` refused a dispatch once `dispatch_count` reached the same
   ceiling, writing no marker and routing nobody, so a capped anchor could
   carry no `exception@` at all and appear only as a merge that never lands.
   This bead recorded that as a documentation gap. tk-gr420e read the second
   enforcement point as the defect instead: a review dispatch is not a rework
   round, and refusing one withholds the very verdict that settles the gate.
   It landed as #493 on 2026-08-27, before this branch reached main. The cap
   now has one enforcer. `signoff.sh:226-232` counts attempted rework children
   under `GC_MAX_REVIEW_ROUNDS`, and `signoff.sh:248` spends the cap.
   `gate-ensure.sh:529` bounds DISPATCHES under `GC_MAX_REVIEW_DISPATCHES`
   (default 5), a separate number with a terminal act of its own: it stamps
   `dispatch_backstop.<gate>`, appends a note, and files one
   `dispatch-runaway` visit. The silent hold this fact described went with the
   arm that produced it. This branch carries main's wording for both.
   `docs/refinery-merge-cadence.md` arm 1 still gains the one no-dispatch
   state main does not name: an `exception@` bound to the live head.
3. **`docs/authority-map.md` had no `check_set` row.** Added.
4. **A spent cap does not gate a green verdict.** `signoff.sh:234-241` stamps
   `green@<reviewed oid>` and exits on the approve path before it counts
   rounds, so one further approving review releases the gate at the very head
   the exception names. At that head nothing in the cadence will dispatch that
   review, because gate-ensure and `pr-facts.sh` both read an exception bound
   to the live head as settled. Only a head move changes that, and it re-gates
   the new head rather than the one the exception names.

Fact 4 is live, not theoretical. signal-loom `sl-bgmuy` (PR#552) carried
`check.codex=exception@3ecc2def` and now carries `green@3ecc2def` at the same
head, released by a hand-dispatched review bead titled "first review of head
3ecc2def (post-cap re-gate)". The anchor's `blocked_reason` cleared with the
release; `gc.routed_to=human` stayed, which is correct, because the human the
cap reached is still the one who decides to land it.

## Why the cap was not lowered for prose

The cap's terminal action *is* the handoff to a human. Lowering it for prose
work moves that handoff earlier and attaches fewer findings to it; it does not
remove it. It does not reliably end the loop either: tk-10521 recorded signal-loom
`sl-kg9z6.1.1` running to seven review rounds on a zero-code branch under a
cap of 3, the rounds past the cap proceeding on hand-authorized re-gates.

One live docs-only case grounds this: `sl-bgmuy` (PR#552, changing
`docs/material-layers.md` and `specs/sl-bgmuy/coach-flow.md`), capped at 3,
still open and routed to human, and since released as described above. The
bead cites a second case that is not a docs branch. `sl-kg9z6.1.2` (PR#559,
`check.codex=exception@9af8238a`) changes `convex/materialNode.ts` and two
test files, so its cap says nothing about prose. tk-at7fur read its exception
as a stranding defect rather than a calibration one, and #486 fixed it as one.

## What a human does with a capped prose anchor

Held as this bead's judgment, not as pack doctrine. The authority-map row
bounds the act; this is how to choose within it.

Read the findings first. `signoff.sh` files no rework child on the cap path,
so `exception@<oid>` always names a head a reviewer read and rejected, and the
findings that stopped it are on the review beads under the anchor.

Another round is a second opinion on a head that has already been judged. It
is the right move when the findings turn on a fact the reviewer could have
checked and did not, which is what `sl-bgmuy` turned out to be.

When the findings turn on judgment about work that has not happened yet, no
further reviewer settles them, because the document's correctness is not
checkable against the tree. Declaring `approval` on the anchor names the
person who owns that judgment as a gate, and `merge.sh` then requires an
external APPROVED review at the live head. That reaches the same human the cap
was going to reach, without spending rounds to get there. Record the reason in
the anchor's notes in the same act: a changed set with no recorded reason is
indistinguishable from a mistake.

Since #486 there is a third move: pushing a commit stales the exception, so
the next cadence pass re-arms the gate and dispatches one review. It is the
right one only when the push answers the findings. With the cap already spent,
a request-changes verdict on the new head writes another `exception@` and
files no rework child, so nothing inside the cadence moves the anchor again
until someone pushes again. `gate-ensure.sh`'s dispatch ceiling bounds how
many times that can repeat.

## Carved out

- **tk-wigtu9** — `mol-review`'s rubric is code-shaped. Its step 2 sends the
  reviewer to run the tests the diff touches, and its step 4 grades P1 as
  wrong behavior on a reachable input. On a document describing work that has
  not happened, every further interleaving a reader imagines meets that
  definition, so the review surface has no terminus. That is what produced the
  round counts above, and changing it is a change to the review contract that
  every rig's reviews run.
- **tk-dgsi8a** — `lifecycle/lifecycle.toml` `[gates] check_set_default` has no
  reader and no drift check, while the states and transitions in the same file
  are pinned by `assets/scripts/lifecycle.test.sh`.

Neither is available to a dispatcher as an escape hatch: no dispatcher may
derive `check_set` from the diff, a standing operator ruling from 2026-08-24
recorded in `specs/2026-08-review-gates/scope.md`.
