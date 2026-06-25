---
name: Work-bead state machine
description: The lifecycle a unit of work moves through as one bead — whether it produces code, a committed artifact, or a recorded decision — and the evidence (merge, commit, signoff, CI, approval) that drives each transition between dispatch and closure. Read it to know what a bead's status is allowed to mean.
---

# Work-bead state machine: a bead closes when its work lands

## Scope

This doc owns one question: **what a work bead's `closed` status is allowed to
mean.** It describes the lifecycle a single unit of work moves through from
dispatch to closure — the states it occupies, the transitions between them, and
the evidence (a merge, a commit, a signoff, CI, an approval) that drives each
transition — for every kind of unit, whether it produces code, a keepable
artifact, or a recorded decision. It does not cover the routing that delivers
work to an agent (the field-level contract lives in
[gascity-routing-model.md](gascity-routing-model.md)) or the refinery's full
patrol loop (the `mol-refinery-patrol` formula); it is not a command tutorial.

## The invariant: `closed` means the output has landed

A bead is `closed` only when its **output has landed** — wherever that output
comes to rest. This is **locality of truth**: the bead you query tells the
truth about its own doneness without a tree-walk — a still-open bead is
unlanded work, a closed bead is landed work, nothing in between reads as done.
Closing is **completion, not handoff**: a bead closes because its own output is
done, never because responsibility moved to someone else, and unblocking a
dependent when it lands is what the dependency graph is for, not a form of
handoff. The state this forbids is a bead closed while its output is still
unlanded — the classic case being a code bead closed at PR-creation, before the
PR merges.

## What "landed" means: landing-target and check-set are per-unit

Two properties are declared per unit, and the rest of the machine is identical
for all of them:

- a **landing-target** — where this unit's output comes to rest, and
- a **check-set** — what must hold before it may come to rest there (below).

There is no code/non-code fork in the machine — one machine, parameterized per
unit. The dividing question is simply whether the output is committed:

| Unit produces… | landing-target | check-set | `closed` means |
|---|---|---|---|
| **a committed output** — code, or a keepable artifact (a spec, a design, a set of options) | the repo, through a PR: `main` (or a convoy branch) for code; `specs/<bead-id>/` or `docs/` for an artifact | signoff · CI (where it applies) · approval · title/description current · merged | the commits merged to the target |
| **an ephemeral finding or decision** — a result consumed at once, a recorded choice | the **bead's own notes** | the finding/decision is recorded | the note is written |

A keepable artifact lands through the **same PR machine and full check-set as
code** — it pays the main-approval gate, with CI simply having nothing to run
where there is no code. An ephemeral unit lands without a commit: the worker
writes the note and closes the bead. `merged_sha` is therefore the
committed-output signal, not a universal one — an ephemeral unit closes with no
merge at all, by design, because the invariant is *landed* and "landed" is
whatever the unit's landing-target makes it.

## Work is a graph, not a line

A unit rarely stands alone, and the work around it is not a sequence. Units
chain through the **dependency graph**, and a single piece of work can mix both
landing modes. A worked example — *propose options → choose → implement*:

```
  explore A --\
  explore B ---\
  explore C ----+--> choose ------> implement ----> (lands to main)
  explore D ---/     (decision)     (code)
  explore E --/      (fan-in)
  (fan-out)
```

- each **explore** unit produces a keepable artifact — it lands in
  `specs/<bead-id>/` through a PR and closes when committed;
- **choose** produces an ephemeral decision — it depends on the explorations,
  lands in its own notes, and closes when recorded;
- **implement** produces code — it depends on the decision and lands to `main`
  through the full check-set.

The dependency edges, not a linear status, carry the shape of the work.
`closed` means the same thing at every node — *that node's* output has landed —
but *where* it lands differs by node, which is exactly what the per-unit
landing-target buys.

## Everything is a convoy

Every PR-bearing dispatch is wrapped in a **convoy** — a bead whose members are
work beads joined by parent-child tracks. A **sling makes a convoy**; there is
no separate model for "one bead" versus "a set of beads": a lone bead-to-`main`
is the degenerate **one-child convoy**, a multi-bead initiative is a
**many-child convoy**, and the same machine runs either way.

The convoy is the unit that carries a PR — and its rework — through to landed,
and it owns a **stable branch** that is the head of that PR. The branch name is
cosmetic (`integration/<convoy-id>` by convention when several children share
it, or the lone child's branch when there is one); what matters is that a
convoy has **one stable PR head**, so rework lands on the *same* PR instead of
forking a new one each round.

**The boundary invariant: a convoy is the only thing that targets the protected
boundary.** No bead lands on `main` except a convoy. A **child** targets its
**convoy branch**; the **convoy** targets `main`. The levels chain through
`target`:

| | lands when… | target |
|---|---|---|
| child work bead | its commits merge to the convoy branch | the convoy branch |
| convoy | **all children closed** and **its PR merges** | `main` |

That second row is the **completion gate, stated once**: a convoy completes
when all its children are closed *and* its own PR has merged. Because a child
closes only on merge to the convoy branch (not at PR-creation), "all children
closed" means "every child's work is actually on the branch" — so the convoy's
PR can never assemble a half-built branch, and an abandoned child stays open and
blocks the convoy until a human resolves it. A child contributes to the branch
however it needs: one commit, a dozen, a rebase, or none (a child can exist only
to group or to mark a sub-unit). There is no one-bead-one-commit rule.

The convoy graduates **through this same machine, one level up**: once all
children are closed, a reconcile pass assigns the convoy to the refinery with
its branch and `target=main`, and it walks `open → PR → check-set → merge →
closed` like any bead. No coordinator drives graduation; `gc convoy land`
remains a manual primitive but is not the driver.

## The states

The states below are drawn for the code path — the richest instantiation. A
keepable-artifact unit runs the same states through the same check-set (CI
simply has nothing to run); an ephemeral unit skips the PR machine and closes
straight from `in_progress` when its note is recorded.

```
dispatch
  -> open . gc.routed_to=<pool>                       -- pool demand
       -> the worker claims -> in_progress            (builds on its branch, sets target)
            -> hands off -> open . assignee=refinery . branch,target set
                 -> direct-mode: FF-merge to target, push -> closed "Merged to <target> at <sha>"
                 -> mr-mode: push branch, open PR to target
                       -> GATING . open . assignee="" . gc.routed_to="" . pr_url,pr_number set
                       |    (the check-set hangs off it as gate conditions)
                       |- check-set clears, PR merges -> closed "Merged to <target> at <sha>"
                       |- a check needs work          -> rework: a NEW child filed against it
                       \- PR abandoned                -> the PR is closed and the convoy closed
                                                         (or escalated, if closed out-of-band)
```

| State | Status | assignee | gc.routed_to | Marker |
|---|---|---|---|---|
| pool demand | open | — | `<pool>` | `branch` unset until claimed |
| building | in_progress | the worker | — | `work_dir`, `branch` |
| handed off | open | refinery | — | `branch`, `target` |
| **gating** | **open** | **—** | **—** | `pr_url`, `pr_number`, `merge_result=pull_request` |
| closed (landed) | closed | — | — | `merged_sha` (committed output) / close reason (ephemeral) |
| abandoned | closed / open | — | — / `human` | PR closed unmerged: refinery-closed, or escalated if out-of-band |

The **gating** state is the one close-on-land adds. The bead stays open — its
work has not landed — but it is **detached from both work queues** on purpose:

- `assignee=""` so the refinery's find-work query (which looks for
  `assignee=<refinery>`, open, with a `branch`) does not re-grab it and re-open
  the PR in a loop; and
- `gc.routed_to=""` so an open, unassigned bead is not read as pool demand
  (open + unassigned + `gc.routed_to` set = demand; see
  [gascity-routing-model.md](gascity-routing-model.md)).

A gating convoy is therefore invisible to find-work and to the pool reconciler;
the only thing that watches it is the refinery's reconcile pass.

**The movers.** The **worker** builds (`open → in_progress → hands off`) and
reworks; the machine names a role, not a specific agent. The worker never
closes a unit that merges — though it does close its own ephemeral unit (there
is nothing to merge) and hands a keepable artifact to the refinery like any
other PR. The **refinery** is the only mover that reaches `closed` for anything
that merges: it opens the PR, transitions the bead to gating, and on a later
idle pass detects that the check-set has cleared and the PR has merged, and
closes. Its *active* endpoint is still PR-created — it hands the bead to gating
and moves on; it does not babysit a PR to merge. Keeping closure in one mover is
deliberate: one authority over "did it land" means no second place for that
state to drift. No coordinator (mayor / mechanik / deacon / witness) sits in
this loop.

## The check-set: one class of gate

A gating convoy does not wait on a single "is it reviewed?" flag. It waits on a
**check-set** — a set of conditions that must all hold before the work may land.
For a bead landing to `main`:

| Check | Satisfied by | Evidence |
|---|---|---|
| **signoff** | the signoff gate (a review step) | the gate's bead is closed/approved |
| **CI** | the rig's CI on the PR | required checks green |
| **approval** | a human (or delegated) approver | an approving PR review |
| **title/description current** | a validation step | title + body match the latest diff |
| **merged** | the merge itself | `merged_sha` exists |

These are the **same class of thing**: a PR triggers CI, which runs
asynchronously against GitHub, exactly as approval is asynchronous — from the
machine's point of view all are gates to track and follow up on, none
privileged. The set is **composable**: the signoff gate is one pluggable
member, not a hardcoded step, and a rig may add or drop members (a second
reviewer, a license check, a changelog check) without changing the machine,
which only ever asks "are all members of this convoy's check-set satisfied?" A
keepable-artifact PR uses this same set; an ephemeral unit's set is the single
member "recorded."

**`title/description current` is load-bearing for automated merge.** Auto-merge
fires the instant CI and approval clear — which can be **stale**: an approval
given on an earlier diff, with a title and body that no longer describe what
will land. Approval alone is therefore not a sufficient gate for auto-merge;
the title/description-current check confirms the PR's title and body still
describe the latest commits before the merged check may fire. Without it,
auto-merge can land prematurely.

## Rework is a new child

When a check needs work — a signoff requests changes, CI fails, the description
has drifted — the fix is a **new child filed against the convoy**, never the
same bead cycling open→closed→open and never a flag toggled back on the convoy.

- **The PR is changed, never closed and reopened.** Rework adds commits to the
  same PR branch; the PR is a long-lived object across however many rework
  rounds it takes.
- **The completion gate stays honest for free.** A convoy completes only when
  all its children are closed. The moment a rework child is filed it is open, so
  "all children closed" is false and the convoy cannot land — automatically, no
  extra flag. Five rework rounds are five children, each closed when its own fix
  landed; none is the same bead reopened, so no bead's history lies about how
  many times it "finished."

The signoff gate **attaches as a dependency of the open convoy** — the gate's
bead BLOCKS the convoy (`gc bd dep <gate> --blocks <convoy>`). The dependency
graph then shows directly which bead is on which PR and what it waits on.

## Closure flavors: what "landed" was

`closed` means landed, but *what* landed differs by unit, so "merged" is not the
universal close reason:

- a **convoy** that holds a PR closes when **its PR merges** (`merged_sha`);
- a **child** closes when **its own output lands** — merge to the convoy branch
  for code, or the note recorded for an ephemeral unit.

Reading "merged" as the close reason for everything would be wrong: an ephemeral
child closes with a written note and no merge at all.

## Merge: one reconcile point

No worker performs the merge by hand. The merge is the terminal check,
satisfied by GitHub auto-merge once the rest of the check-set clears — gated by
the title/description-current member so a stale approval cannot land early
(above) — and reconciled by **exactly one authority**, so "did it land" lives in
one place.

Today that authority is the refinery's reconcile pass: it queues `gh pr merge
--auto` only while the head is signoff-validated, and later observes the merge
and closes the bead. That is the **reconciler-of-record**.

**Open fork (not resolved here): who marks the bead merged.** Three shapes are
possible — the worker marks it at merge time, the refinery poll observes and
closes it (current), or naked auto-merge closes nothing and the bead is
reconciled separately. The binding **constraint** is that the bead's closure and
the PR's merge must be reconciled at **one** point: if two points both decide
"merged" (say a worker stamp *and* a refinery poll), they can **desync** — one
fires, the other does not, and the bead's state disagrees with the PR. The pick
is open; the constraint — a single reconcile point — is not.

## Abandonment: we close our own PRs

A PR can end without merging — the approach was wrong, the work was superseded,
the bead was cancelled. When **we** abandon, the refinery **closes the PR and
the convoy together** with an abandoned reason; there is no escalation, because
abandoning our own work is a normal outcome.

Escalation is reserved for the case the machine has no context for: a PR closed
**out-of-band** — by a human or a process outside Gas City — that the refinery
did not initiate. There the bead is left open, flagged, and routed to a human
(`gc.routed_to=human`), because only they know why. The rule: **we close what we
abandoned; we escalate only what someone else closed.**

## Where artifacts rest

Where does a produced artifact rest? The landing-target answers it:

- **ephemeral** output rests in the **bead's own notes**;
- **keepable** output rests in the **repo, through the convoy's PR**.

A **parked branch awaiting a later PR is not a sanctioned resting state.** Work
sitting on a branch that no PR is carrying is *unlanded treated as done* —
precisely what the invariant forbids. If such work must persist, it belongs
**under an open child on the convoy branch**, where its open status tells the
truth (still unlanded) and the convoy's completion gate keeps it visible — not
on a detached branch where its consumers cannot find it and nothing tracks it to
landed. The convergent position is **no parked branches**; if a case genuinely
needs one, that is an **open policy question** to raise, not a default to assume.

## Divergence from stock GasTown

Stock GasTown mr-mode closes the work bead at **PR-creation**. gc-toolkit keeps
the bead **open through gating and closes it on land**, so `closed` always means
landed and the dependency graph always shows who is on which PR. This is a
**pack-only delta** — it lives entirely in the `mol-refinery-patrol` formula and
its reconcile scripts (`reconcile-merged-prs.sh`,
`reconcile-graduated-convoys.sh`); gascity core is untouched and gains no new
status (`gating` is a metadata marker on an ordinary `open` bead).
**Direct-mode beads are unchanged.**
