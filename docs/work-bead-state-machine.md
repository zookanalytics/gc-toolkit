---
name: Work-bead state machine
description: The lifecycle a unit of work moves through as one bead — whether it produces code, a committed artifact, or a recorded decision — and the evidence (merge, commit, signoff, CI, approval) that drives each transition between dispatch and closure. Read it to know what a bead's status is allowed to mean.
---

# Work-bead state machine: a bead closes when its work lands

## Scope

**Mandate.** The lifecycle of a single unit of work as it moves through
gc-toolkit: the states a work bead occupies from dispatch to closure, the
transitions between them, and the evidence — pull request, commit, signoff,
CI, approval — that drives each transition. It owns one invariant above all:
**what `closed` is allowed to mean** — and it owns that meaning for *every*
kind of unit, whether the unit produces code, a keepable artifact, or a
recorded decision.

**Boundaries.** This doc covers the *states a bead moves through*, not the
*routing* that delivers it to an agent — the field-level contract (sling vs
direct assignee vs `gc.routed_to`) lives in
[gascity-routing-model.md](gascity-routing-model.md). It describes the
refinery's role *in* the machine, not the refinery's full patrol loop, which
lives in the `mol-refinery-patrol` formula. It is not a command tutorial.

## The invariant: `closed` means the output has landed

Everything is a bead. A unit of work is a single bead that holds its own
state; the PR, branch, signoff, CI, and commit are **evidence** that drive its
transitions — not separate truth. A bead is `closed` only when its **output
has landed** — wherever that output lands. "Done" means landed; it never means
"the work is now someone else's problem."

This is **locality of truth**: the bead you query tells the truth about its own
doneness without a tree-walk. A still-open bead is still-unlanded work; a
closed bead is landed work. Nothing in between reads as done.

Closing is **completion, not handoff** — a distinction the word "handoff" must
not blur. Closing a research bead the moment its synthesis is recorded is
*completion*, not handing the work to someone else to finish. A bead may
*unblock* downstream beads when it lands (that is what dependencies are for),
but it closes because **its own** output is done, not because responsibility
moved. The anti-pattern `closed` exists to forbid is closing a bead while its
output is still unlanded — the classic case being a code bead closed at
PR-creation, before the PR merges.

## What "landed" means: landing-target and check-set are per-unit

> **Adopted, with one piece tabled.** This section and *"Work is a graph, not a
> line"* below generalize the model beyond code-to-`main`: a unit's
> landing-target and check-set are declared per unit, and work is a graph of
> such units rather than a line. That generalization is **adopted**. **One**
> sub-option is explicitly **tabled for now** — a *lighter-weight* landing for
> keepable artifacts (a reduced check-set: a review or none, no CI). Today
> every **committed** output, code or artifact, pays the **full PR gate** (the
> main-approval gate is the control we want); the lighter artifact path is a
> future option we may add later, not current. Nothing here changes how a code
> bead lands.

Not every unit produces code, and not every output belongs in `main`. The
generalization is that **two properties are declared per unit** and the rest of
the machine is identical:

- a **landing-target** — *where* this unit's output comes to rest, and
- a **check-set** — *what must hold* before it may come to rest there
  (next section).

There is **no code/non-code fork** in the machine. There is one machine,
parameterized per unit. A **committed output** — whether code or a keepable
artifact — lands in the repo through a **normal PR** and pays the same full
check-set; an **ephemeral** finding or decision lands in its own bead and is
simply recorded. (Code is the richest instantiation because it has CI to run;
an artifact PR is the *same* gate, with checks that simply have nothing to do
where there is no code.) The two live landing modes are two settings of those
per-unit properties:

| Unit produces… | landing-target | check-set | `closed` means | `merged_sha`? |
|---|---|---|---|---|
| **a committed output** — code, *or* a keepable artifact (a spec, a design doc, the "5 UX options") | the repo via a **normal PR**: `main` or a convoy branch for code; `specs/<bead-id>/` or `docs/` for an artifact | signoff · CI (where it applies) · approval · title/description current · merged | the commits merged to the target | yes |
| **an ephemeral finding or decision** (a research result consumed at once, a recorded choice) | the **bead itself** — its notes | the finding/decision is **recorded** | the note is written | no |

The dividing question is simply: **does the output get committed?**

- **Keepable → commit it through a normal PR.** If the output is worth keeping
  — a spec, a design, a set of options, an investigation report others will
  re-read — it lands in the repo under `specs/<bead-id>/` (or `docs/` for
  durable reference material), through the **same PR machine and full
  check-set as code**: it pays the main-approval gate (and CI wherever it
  applies). It is a real landing; the commit is the `merged_sha`. The only
  thing that differs from code is *where* it comes to rest, not *how* it gets
  there.
- **Ephemeral → record it.** If the output is consumed immediately — a decision
  that only needs to be *known*, a finding that exists only to unblock the next
  unit — it lands in the **bead's own notes**. There is no merge, no
  `merged_sha`; the worker closes the bead when the note is in place. This is
  the one mode that is wholly outside the PR machine below.

So `merged_sha` is the code-and-committed-artifact signal, not a universal one:
an ephemeral unit lands without a commit and closes anyway. That is by design —
the invariant is *landed*, and "landed" is whatever the unit's landing-target
makes it.

This is the **same shape as `owned = f(target)`** in the routing model: a
unit's behavior falls out of *what it is and where it lands*, declared once,
not out of a special case bolted onto the machine. The check-set is a per-unit
property in exactly the way the landing-target is.

**Live example — the failure this prevents.** This very initiative produced a
keepable spec, `specs/tk-6d0vb.1/composable-check-options.md`. It was authored
at the right path — but it sits on an unmerged polecat branch and is **not on
`main`**. Under this model that spec **has not landed**: its bead must not read
`closed`, and the way it lands is by *committing it to its target* (a normal
PR to `main`), not by loitering on a branch where its consumers cannot find it.
An orphaned artifact on a dead branch is precisely the "unlanded but treated as
done" state the invariant forbids.

## Work is a graph, not a line

A unit rarely stands alone, and the work that surrounds it is **not a
sequence**. Units chain through the **dependency graph**, and the convoy that
holds them (next sections) is a **graph of units**, not a line. The graph is
where exploration, fan-out, and fan-in live — and each node is a unit with its
own landing-target and check-set, so a single piece of work can mix both
landing modes.

A worked, non-linear example — *propose options → choose → implement*:

```
  explore option A --\
  explore option B ---\
  explore option C ----+--> choose ----> implement ----> (lands to main)
  explore option D ---/    (decision)    (code)
  explore option E --/     (fan-in)
  (fan-out: 5 units)
```

- the **explore** units each produce a *keepable artifact* — they land in
  `specs/<bead-id>/` through a normal PR and close when committed;
- **choose** produces an *ephemeral decision* — it depends on the explore
  units, lands in its own notes (the choice, and why), and closes when
  recorded;
- **implement** produces *code* — it depends on the decision and lands to
  `main` through the full check-set.

Five explorations are five units that fan out; the decision fans them back in;
implementation consumes the decision. The dependency edges, not a linear
status, carry the shape of the work. "Closed" still means the same thing at
every node — *that node's* output has landed — but *where* it lands differs by
node, which is exactly what the per-unit landing-target buys.

## The machine (one unit)

The states below are drawn for the **code** path — the richest instantiation.
A keepable-artifact unit runs the *same* states through the *same* check-set
(an ordinary PR; CI simply has nothing to run where there is no code); an
ephemeral unit skips the PR machine entirely and closes straight from
`in_progress` when its note is recorded.

```
dispatch
  -> open . gc.routed_to=<pool>                              -- pool demand
       -> worker claims -> in_progress . assignee=worker        (builds on its branch, sets target)
            -> hands off -> open . assignee=refinery . branch,target set
                 -> refinery direct-mode: FF-merge to target, push
                 |     -> closed . "Landed on $TARGET at <sha>"
                 |
                 -> refinery mr-mode: push branch, open PR to target
                       -> GATING . open . assignee="" . gc.routed_to="" . pr_url,pr_number set
                       |    -- the check-set hangs off this anchor as gate conditions:
                       |    -- a signoff gate BLOCKS it; CI + approval + a current
                       |    -- title/description are the other checks (see below)
                       |
                       |- check-set clears, PR merges -> closed . "Landed on $TARGET at <sha>"
                       |- a check needs work         -> rework: a NEW child is filed against
                       |                                the anchor (open . gc.routed_to=<fix-pool>)
                       \- PR abandoned               -> refinery closes the PR; anchor closed
                                                        (or, if closed out-of-band, escalated)
```

### States

| State | Status | assignee | gc.routed_to | Marker |
|---|---|---|---|---|
| pool demand | open | — | `<pool>` | `branch` unset until claimed |
| building | in_progress | worker | — | `work_dir`, `branch` |
| handed off | open | refinery | — | `branch`, `target` |
| **gating** | **open** | **—** | **—** | `pr_url`, `pr_number`, `merge_result=pull_request` |
| closed (landed) | closed | — | — | `merged_sha` (code / committed artifact) / close reason (ephemeral) |
| abandoned | closed / open | — | — / `human` | PR closed unmerged: refinery-closed, or escalated if out-of-band |

The **gating** state is the one close-on-land adds. The anchor stays open —
its work has not landed — but it is detached from both work queues on purpose:

- `assignee=""` so the refinery's find-work query (`assignee=$GC_AGENT`,
  `status=open`, has `branch`) does **not** re-grab it and re-open the PR in a
  loop; and
- `gc.routed_to=""` so an open + unassigned anchor is **not** read as pool
  demand (the pool-demand coupling: open + unassigned + `gc.routed_to` set =
  demand). See [gascity-routing-model.md](gascity-routing-model.md).

A gating anchor is therefore invisible to find-work and to the pool
reconciler. The thing that watches it is the refinery's reconcile pass.

### Movers

- The **worker** (a polecat) builds (`open -> in_progress -> hands off`) and
  reworks. It never closes a code bead. (It *does* close its own ephemeral unit
  — there is nothing to merge — and hands a keepable artifact to the refinery
  like any other PR.)
- The **refinery** is the only mover that reaches `closed` for anything that
  merges. It opens the PR, transitions the anchor to gating, and — on a later
  idle pass — detects that the check-set has cleared and the PR has merged, and
  closes. The refinery's *active* endpoint is still PR-created: it hands the
  anchor to gating and moves on; it does **not** babysit a PR to merge. Closure
  is reconciled, not awaited. Keeping closure in this one mover is deliberate:
  one authority over "did it land" means there is no second place for that
  state to drift out of sync.
- **The check-set** is a set of conditions (next section). They are pluggable;
  the machine is blind to who or what staffs each one.
- No coordinator (mayor / mechanik / deacon / witness) sits in this loop.

## The check-set: gates are conditions of one class

A gating anchor does not wait on a single "is it reviewed?" flag. It waits on
a **check-set** — a set of conditions that must all hold before the work may
land. For a bead landing to `main` the check-set is:

| Check | Satisfied by | Evidence |
|---|---|---|
| **signoff** | a signoff gate (a review step) | the gate's bead is closed/approved |
| **CI** | the rig's CI on the PR | required checks green |
| **approval** | a human (or delegated) approver | an approving PR review |
| **title/description current** | a validation step | title + body match the *latest* diff |
| **merged** | the merge itself | `merged_sha` exists |

These are the **same class of thing** — a PR triggers CI, which runs against
GitHub asynchronously, exactly as approval is asynchronous. From the machine's
point of view they are all just gates to track and follow up on; none is
privileged. The set is **composable**: the signoff gate is one *pluggable*
member, not a hardcoded step. A rig may add or drop members (a second
reviewer, a license check, a changelog check) without changing the machine —
the machine only asks "are all members of this anchor's check-set satisfied?"
A keepable-artifact PR uses this **same** set — approval and a current
title/description still gate it; CI simply has nothing to run where there is no
code. An ephemeral unit's set is a single member, "recorded."

Two consequences worth stating, because they are easy to get wrong:

- **`title/description current` is load-bearing for automated merge.** When
  merge is left to GitHub auto-merge, the merge fires the instant CI and
  approval clear — which can be **stale**: an approval given on an earlier
  diff, with a title and body that no longer describe what will land. Human
  approval *alone* is therefore not a sufficient gate for auto-merge. The
  title/description-current check closes that gap: a validation step confirms
  the PR's title and body still describe the latest commits before the merged
  check is allowed to fire. Without it, auto-merge can land prematurely.
- **No worker performs the merge by hand.** The merge is the terminal check,
  satisfied by GitHub (auto-merge once the rest of the set clears) under the
  refinery's single authority — not by a worker clicking merge in a second
  place. This keeps "did it land" reconciled in exactly one mover.

## Rework is a new child, not the same bead reopened

When a check needs work — a signoff requests changes, CI fails, the
description has drifted — the fix is a **new child filed against the anchor**,
not the same bead cycling open→closed→open and not a flag toggled back on the
anchor.

This matters for two reasons the alternatives get wrong:

- **The PR is changed, never closed and reopened.** Rework adds commits to the
  same PR branch. The PR is a long-lived object across however many rework
  rounds it takes; we never close a PR and open a fresh one from the same
  branch just to represent "needs rework." (An earlier design cleared a
  `merge_result` marker on the anchor to mean "rework in flight." That made
  the anchor's state disagree with reality — the PR still existed — so it is
  retired.)
- **The completion gate stays honest for free.** An anchor (a convoy, below)
  completes only when **all its children are closed**. The moment a rework
  child is filed it is open, so "all children closed" is false and the anchor
  cannot land — automatically, with no extra flag. When the rework child lands
  its commits and closes, the gate re-evaluates. Five rework rounds are five
  children, each closed when its own fix landed; none of them is the same bead
  reopened, so no bead's history lies about how many times it "finished."

The signoff gate **attaches as a dependency of the open anchor** — the gate's
bead BLOCKS the anchor (`gc bd dep <gate> --blocks <anchor>`). The dependency
graph then shows, directly, which bead is on which PR and what it waits on.
This retires the old **backward `work_bead` pointer** — a gate bead that
pointed at an *already-closed* work bead as its primary reference, which was
counterproductive precisely because the thing it pointed at was already done.
The edge now points the right way: the gate blocks something still open.

## Everything is a convoy: one machine, applied at every level

The anchor that carries a PR through its check-set is a **convoy** — a bead
whose members are work beads (joined by parent-child tracks). This is not a
second machine bolted on for aggregates; it is the **same machine** run at a
different level, and the levels chain through `target`:

| | lands when… | target | `closed` means |
|---|---|---|---|
| child work bead | its commits merge to the convoy branch | the convoy branch | merged to the convoy branch |
| convoy | all children closed **and** its check-set clears | `main` | merged to `main` |

A convoy owns a **stable branch** that is the head of its PR. The name of that
branch is cosmetic — `integration/<convoy-id>` by convention when several
children share it, or simply the lone child's branch when there is only one.
What matters is the **mechanism**: a single stable PR head per convoy, so that
rework lands on the *same* PR and the convoy's identity does not fork into a
new PR each round.

**Dispatch creates the convoy.** Every PR-bearing dispatch is wrapped in an
**owned** convoy at sling time (`gc convoy create --owned`), targeting `main`
(or the next level up). A lone bead-to-main is dispatched as an owned convoy
with one child; a multi-bead initiative is an owned convoy with several. In
both cases the convoy is the unit that tracks the work — *through its PR and
through every rework round* — to landed. There is no separate model for "a
single bead" versus "a set of beads": one bead is the degenerate convoy, the
same machine with a member count of one.

> **Owned vs. un-owned is a per-unit property, not a fork.** Gas City also has
> *un-owned auto-convoys*: lightweight per-sling tracking bundles that
> auto-close when their members close. It is tempting to read "owned convoy
> that gates on a check-set" vs. "un-owned convoy that just auto-closes" as two
> different machines — it is not. The only thing "owned" changes is the
> convoy's **close-condition**: an owned convoy's close-condition is *its
> check-set clears*; an un-owned convoy's close-condition is the trivial *all
> members closed*. That is the **same kind of per-unit property** as the
> landing-target and the check-set above — `owned = f(intent)`, just as
> `target` and check-set are declared per unit. An un-owned auto-convoy is
> simply a convoy whose check-set is empty; it carries no branch and never
> gates a landing because there is nothing in its set to wait on. One machine,
> two settings — not a second mechanism that happens to share the word
> "convoy." Branch and merge-strategy stay orthogonal to ownership: "owned"
> changes only the close-condition, not how a child contributes commits.

A child contributes to the convoy branch **however it needs** — one commit, a
dozen, a rebase that owns none of them, or none at all (a child can exist to
group or to mark a sub-unit). There is no "one bead = one commit" rule.

The convoy graduates **through the work-bead machine itself**: once all
children are closed, a reconcile pass assigns the convoy bead to the refinery
with `branch=<convoy branch>`, `target=main`, and it walks `in_progress -> PR
-> check-set -> merge -> closed` exactly like any bead. So it is **recursion**
— one machine, defined once, applied to an aggregate — with the target chain
(child → convoy branch → `main`) threading the levels. No coordinator drives
it; `gc convoy land` remains available as a manual primitive but is not the
graduation driver.

Because a child closes on **merge to the convoy branch** (not at PR-creation),
"all children closed" means "all children's work is actually on the convoy
branch." That is the **interlock**: graduation can never assemble a half-built
branch, and an abandoned child stays incomplete and blocks graduation until a
human resolves it. The completion gate the operator's intuition names —
*all children closed, then the convoy's own PR merges* — falls straight out of
the recursion, and rework-as-a-new-child plugs into it: a new open child makes
the gate false until it lands.

## Abandonment: we close our own PRs

A PR can end without merging — the approach was wrong, the work was
superseded, the bead was cancelled. When **we** decide to abandon, the
refinery **proactively closes the PR** and closes the anchor with an
abandoned reason. There is no escalation: abandoning our own work is a normal
outcome, not an incident.

Escalation is reserved for the case the machine has **no context for**: a PR
closed **out-of-band** — by a human or a process outside Gas City — that the
refinery did not initiate. There, the anchor is flagged and routed to a human
(`gc.routed_to=human`) because only they know why it happened. The rule is:
*we close what we abandoned; we escalate only what someone else closed.*

## Draft PRs are scaffolding, slated for removal

The model's intended end state is **no draft PRs**. A signoff is a check in the
set like any other, and the cleaner shape is for the validating work to happen
*before* the PR is opened (or as an ordinary check on a normal PR), so that
**every PR that exists is a real candidate** and carries, in its own record,
the evidence of what validated it. That is where this is going.

Today the signoff gate still runs against a **draft** PR: the refinery opens
the PR as draft, the signoff concludes, and a reconcile pass un-drafts it. This
is **scaffolding**, retained only because, historically, "is this PR actually
ready?" had no better signal than draft state — and it is explicitly *not* the
target model. The check-set model above is written so that dropping draft later
changes **one member's implementation** (where the signoff runs), not the
machine: the signoff stays a check, it just stops needing a draft to hold the
PR back. Removing the draft mechanism is left to a later, separate change; the
core model here already assumes its absence.

## Deliberate divergence from stock GasTown

Stock GasTown mr-mode closes the work bead at **PR-creation**. gc-toolkit
keeps the anchor **open through gating and closes it on land**, so `closed`
always means landed and the dependency graph always shows who is on which PR.
This is a pack-only delta — it lives entirely in the `mol-refinery-patrol`
formula and its reconcile scripts; gascity core is untouched and gains no new
status (`gating` is a metadata marker on an ordinary `open` bead, not a core
state). The convoy-close authority is the refinery's reconcile pass, not a
core `on_close` hook — chosen so the machine stays bead-native and the core
hook is removable later. The generalization of `closed`-means-landed across
code, committed artifacts, and ephemeral decisions (above) is likewise a
gc-toolkit framing layered on bead-native primitives, not a core change.
Direct-mode beads are unchanged.
