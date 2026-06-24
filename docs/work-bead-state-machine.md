---
name: Work-bead state machine
description: The lifecycle a unit of work moves through as one bead, and which evidence — pull request, signoff, CI, approval — drives each transition between dispatch and closure. Read it to know what a bead's status is allowed to mean.
---

# Work-bead state machine: a bead closes when its work lands

## Scope

**Mandate.** The lifecycle of a single unit of work as it moves through
gc-toolkit: the states a work bead occupies from dispatch to closure, the
transitions between them, and the evidence — pull request, signoff, CI,
approval — that drives each transition. It owns one invariant above all:
**what `closed` is allowed to mean.**

**Boundaries.** This doc covers the *states a bead moves through*, not the
*routing* that delivers it to an agent — the field-level contract (sling vs
direct assignee vs `gc.routed_to`) lives in
[gascity-routing-model.md](gascity-routing-model.md). It describes the
refinery's role *in* the machine, not the refinery's full patrol loop, which
lives in the `mol-refinery-patrol` formula. It is not a command tutorial.

## The invariant: `closed` means landed

Everything is a bead. A unit of work is a single bead that holds its own
state; the PR, branch, signoff, and CI are **evidence** that drive its
transitions — not separate truth. A bead is `closed` only when its work has
**landed on its `target`**: "done" means landed, never "the work is now
someone else's problem."

This is **locality of truth**: the bead you query tells the truth about its
own doneness without a tree-walk. A still-open bead is still-unlanded work; a
closed bead is landed work. Nothing in between reads as done.

What "landed" means depends on what the bead produces:

- **code** — landed = **merged to `target`**. The merge commit is the
  evidence (`merged_sha`).
- **a published artifact** (research synthesis, a decisions doc, an
  investigation finding) — landed = the artifact is **written to its durable
  home and made available** (posted to the bead, committed to a doc tree,
  recorded where its consumers look). There is no merge and no `merged_sha`;
  the worker closes the bead itself when the artifact is in place.

Both are "landed," and neither is a **handoff**. Closing a research bead the
moment its synthesis is published is *completion*, not handing the work to
someone else to finish — the distinction the word "handoff" must not blur. A
bead may *unblock* downstream beads when it lands (that is what dependencies
are for), but it closes because **its own** deliverable is done, not because
responsibility moved. The anti-pattern `closed` exists to forbid is closing a
bead while its deliverable is still unlanded — a code bead closed at
PR-creation, before the PR merges.

`target` is not always `main`:

- **a bead landing to `main`** — `target == main`; landed when merged to main.
- **a bead under a convoy** — `target ==` the convoy's branch; landed when
  merged there. `main` moves later, when the convoy itself lands (below).
- **a published-artifact bead** — no merge target; landed when posted. This
  path is out of the PR machine below and is unchanged by close-on-land.

## The machine (one bead)

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
| closed (landed) | closed | — | — | `merged_sha` (code) / close reason (artifact) |
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
  reworks. It never closes a code bead.
- The **refinery** is the only mover that reaches `closed` for code. It opens
  the PR, transitions the anchor to gating, and — on a later idle pass —
  detects that the check-set has cleared and the PR has merged, and closes.
  The refinery's *active* endpoint is still PR-created: it hands the anchor to
  gating and moves on; it does **not** babysit a PR to merge. Closure is
  reconciled, not awaited. Keeping closure in this one mover is deliberate:
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

## Everything is a convoy: one machine, applied at two levels

The anchor that carries a PR through its check-set is a **convoy** — a bead
whose members are work beads (joined by parent-child tracks). This is not a
second machine bolted on for aggregates; it is the **same machine** run at a
different level, and the levels chain through `target`:

| | lands when... | target | `closed` means |
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

> **A note on what "owned" selects.** An *owned* convoy is one whose lifecycle
> is driven deliberately — it holds open until its check-set clears and lands
> through the machine. Gas City also has *un-owned auto-convoys*: lightweight
> per-sling tracking bundles that auto-close when their members close. Those
> are a **tracking** device, not an **anchor** — they carry no branch, no
> check-set, and never gate a landing. The two are not a fork in the work
> machine: the anchor is *always* an owned convoy, created on purpose at
> dispatch; the auto-convoy is a separate bookkeeping concept that happens to
> share the word. Branch and merge-strategy stay orthogonal to ownership —
> "owned" changes only the **close-condition** (check-set vs. auto-close), not
> how a child contributes commits.

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

## Draft PRs are transitional

Today the signoff gate runs against a **draft** PR: the refinery opens the PR
as draft, the signoff concludes, and a reconcile pass un-drafts it. This
exists because, historically, "is this PR actually ready?" had no better
signal than draft state.

This is **not** where the model wants to end up. The intent is to **drop draft
PRs**: a signoff is a check in the set like any other, and the cleaner shape
is for the validating work to happen *before* the PR is opened (or as an
ordinary check on a normal PR), so that every PR that exists is a real
candidate and carries, in its own record, the evidence of what validated it.
Draft-gating is retained for now as a transitional mechanism; the check-set
model above is written so that removing it later changes one member's
implementation, not the machine.

## Deliberate divergence from stock GasTown

Stock GasTown mr-mode closes the work bead at **PR-creation**. gc-toolkit
keeps the anchor **open through gating and closes it on land**, so `closed`
always means landed and the dependency graph always shows who is on which PR.
This is a pack-only delta — it lives entirely in the `mol-refinery-patrol`
formula and its reconcile scripts; gascity core is untouched and gains no new
status (`gating` is a metadata marker on an ordinary `open` bead, not a core
state). The convoy-close authority is the refinery's reconcile pass, not a
core `on_close` hook — chosen so the machine stays bead-native and the core
hook is removable later. Direct-mode and published-artifact beads are
unchanged.
