---
name: Work-bead state machine
description: Every artifact — a PR, a branch, a unit of work — is owned by one bead that is the single locus of its truth: open means unlanded, closed means landed. This doc is the lifecycle that one bead moves through from dispatch to closure, the evidence (merge, commit, signoff, CI, approval) that drives each transition, and the honesty boundary between what a bead self-reports and what only an outside observer can catch. Read it to know what a bead's status is allowed to mean.
---

# Work-bead state machine: everything is owned

## Scope

This doc owns one question: **what a work bead's `closed` status is allowed to
mean.** It describes the lifecycle a single unit of work moves through from
dispatch to closure — the states it occupies, the transitions between them, and
the evidence (a merge, a commit, a signoff, CI, an approval) that drives each
transition — for every kind of unit, whether it produces code, a keepable
artifact, or a recorded decision.

The machine's contract is **accurate self-representation**: a bead reports what
it is (open = unlanded, closed = landed) and may raise its hand for any
condition it knows needs attention — a blocker, a pending decision, a recognized
error. What it cannot report is what it does not know: **stuck** is the case
where an unknown exception has occurred, so there is no hand to raise, and it is
detectable only from outside — by an observer reading state, liveness, and time.
Known needs are pushed in-band; the unknown residual is caught out-of-band.

Out of scope: the routing that delivers work to an agent (the field-level
contract lives in [gascity-routing-model.md](gascity-routing-model.md)); the
refinery's full patrol loop (the `mol-refinery-patrol` formula); how an observer
handles an artifact it finds with no owning bead; and command tutorials.

## The law: everything is owned

Every artifact — a PR, a branch, a unit of work — is **owned by one bead**, the
single locus of its truth. The artifact carries no truth of its own; its owning
bead does. A still-open bead is unlanded work; a closed bead is landed work;
nothing in between reads as done. This is **locality of truth**: the bead you
query tells the truth about its own doneness without a tree-walk.

Everything below is an instance of this one law. Closing is **completion, not
handoff** — a bead closes because its own output has landed, never because
responsibility moved to someone else; unblocking a dependent when it lands is
what the dependency graph is for, not a form of handoff. The state the law
forbids is a bead closed while its output is still unlanded — the classic case
being a code bead closed at PR-creation, before the PR merges.

**Unlanded work lives on an open bead, wherever its bytes rest.** Work that is
started-but-incomplete, tabled, or delayed is held by an **open owning bead**;
the bead is the truth and the index, and the branch (or any other store) is just
where the bytes sit. Incomplete, tabled, and delayed are first-class honest
**open** states — a known position the bead represents, never "stuck." The law
rules out exactly two shapes: **unlanded work with no owning bead** (orphaned),
and a **closed bead over unlanded work** (a lie). An artifact with no owning bead
is an exception, caught by an observer; how the observer handles it is out of
scope here.

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

**Every committed output lands through a PR** — code and keepable artifact
alike, on the same machine and the same full check-set, with CI simply having
nothing to run where there is no code. A keepable artifact pays the same
main-approval gate as code. An ephemeral unit lands without a commit: the worker
writes the note and closes the bead. `merged_sha` is therefore the
committed-output signal, not a universal one — an ephemeral unit closes with no
merge at all, by design, because the law is *landed* and "landed" is whatever
the unit's landing-target makes it.

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

## Every PR is owned by a convoy bead

A PR is an artifact, so the law applies: **every PR is owned by a bead** — a
**convoy**, whose members are work beads joined by parent-child tracks. A
**sling makes a convoy**; there is no separate model for "one bead" versus "a
set of beads": a lone bead-to-`main` is the degenerate **one-child convoy**, a
multi-bead initiative is a **many-child convoy**, and the same machine runs
either way.

The convoy is the bead that owns a PR — and its rework — through to landed, and
it holds a **stable branch** that is the head of that PR. The branch name is
cosmetic (`integration/<convoy-id>` by convention when several children share
it, or the lone child's branch when there is one); what matters is that a convoy
has **one stable PR head**, so rework lands on the *same* PR instead of forking a
new one each round.

**The boundary invariant: a convoy is the only thing that targets the protected
boundary.** No bead lands on `main` except a convoy. A **child** targets its
**convoy branch**; the **convoy** targets `main`. The levels chain through
`target`:

| | lands when… | target |
|---|---|---|
| child work bead | its commits merge to the convoy branch | the convoy branch |
| convoy | **all children closed** and **its PR merges** | `main` |

That second row is the **completion gate, stated once**: a convoy completes when
all its children are closed *and* its own PR has merged. Because a child closes
only on merge to the convoy branch (not at PR-creation), "all children closed"
means "every child's work is actually on the branch" — so the convoy's PR can
never assemble a half-built branch. A child contributes to the branch however it
needs: one commit, a dozen, a rebase, or none (a child can exist only to group
or to mark a sub-unit). There is no one-bead-one-commit rule.

The convoy graduates **through this same machine, one level up**: once all
children are closed, a reconcile pass assigns the convoy to the refinery with
its branch and `target=main`, and it walks `open → PR → check-set → merge →
closed` like any bead. No coordinator drives graduation.

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
                 -> mr-mode, a pre-open check-set member (currently codex): push branch, dispatch codex on the BRANCH
                       -> PRE-OPEN GATING . open . assignee="" . gc.routed_to="" . merge_result=pre_open_gate
                       |    (no PR yet; the codex signoff gates whether the PR opens at all)
                       |- codex green@<head> -> pre-open-resolve.sh opens the non-draft PR -> GATING (below)
                       \- codex needs work   -> rework: a NEW child filed against the branch (no PR yet)
                 -> mr-mode, otherwise (no pre-open member, or existing PR): push branch, open PR to target
                       -> GATING . open . assignee="" . gc.routed_to="" . pr_url,pr_number . merge_result=pull_request
                       |    (the check-set hangs off it as gate conditions)
                       |- check-set clears -> merge skill merges + records -> closed "Merged to <target> at <sha>"
                       |- a check needs work          -> rework: a NEW child filed against it
                       |- base rewritten (CONFLICTING) -> rebase: a NEW child filed against it,
                       |                                  routed to the fix pool; stays gating
                       |- head moved off green@<oid>   -> stale gate: a codex RE-REVIEW child
                       |   (no rework bead filed)          filed at the live head, routed to the
                       |                                  review pool; stays gating
                       \- PR abandoned                -> the PR is closed and the convoy closed
                                                         (or escalated, if closed out-of-band)
```

| State | Status | assignee | gc.routed_to | Marker |
|---|---|---|---|---|
| pool demand | open | — | `<pool>` | `branch` unset until claimed |
| building | in_progress | the worker | — | `work_dir`, `branch` |
| handed off | open | refinery | — | `branch`, `target` |
| **pre-open gating** | **open** | **—** | **—** | `branch`, `merged_target`, `merge_result=pre_open_gate` (pre-open subset — currently `{codex}` — runs before the PR opens) |
| **gating** | **open** | **—** | **—** | `pr_url`, `pr_number`, `merge_result=pull_request` |
| **gating, stale base** | **open** | **—** | **—** | still `merge_result=pull_request`, plus `stale_base_head`, `blocked_reason`, and an open rebase child |
| **gating, stale gate** | **open** | **—** | **—** | still `merge_result=pull_request`, plus `stale_gate_head`, `blocked_reason`, and an open codex re-review child (the head moved off the reviewed `green@<oid>`) |
| closed (landed) | closed | — | — | `merged_sha` (committed output) / close reason (ephemeral) |
| abandoned | closed / open | — | — / `human` | PR closed unmerged: refinery-closed, or escalated if out-of-band |
| **anchorless** | **closed** | **—** | **—** | Not a state close-on-land creates: bead closed while its PR is still OPEN, so every bead-side scan is blind to it. Found by the PR → bead pass and marked `anchorless_flagged`; disposition is an operator call |

`open` is the **canonical status for unlanded work**; the machine adds no new
top-level status. **gating** is a *sub-state marker* — metadata that refines
*where in open* a bead sits, not a new status — and more such markers may be
added the same way without changing the canonical truth. The gating bead stays
open (its work has not landed) but is **detached from both work queues** on
purpose:

- `assignee=""` so the refinery's find-work query (which looks for
  `assignee=<refinery>`, open, with a `branch`) does not re-grab it and re-open
  the PR in a loop; and
- `gc.routed_to=""` so an open, unassigned bead is not read as pool demand
  (open + unassigned + `gc.routed_to` set = demand; see
  [gascity-routing-model.md](gascity-routing-model.md)).

A gating convoy is therefore invisible to find-work and to the pool reconciler;
the only thing that watches it is the refinery's reconcile pass.

**Pre-open gating** (`merge_result=pre_open_gate`) is another such sub-state
marker, added per the above without a new status. It is the phase in which a
**subset of the check-set runs early — against the branch, before the PR opens.**
That pre-open subset is **currently exactly `{codex}`**: the refinery dispatches
the codex signoff against the **branch** and parks the bead here — detached from
both queues exactly like gating — *before* opening the PR. An idle-loop pass
beside the merge skill (`pre-open-resolve.sh`) opens the non-draft PR only once
every pre-open member is green at the branch head — today just `check.codex` —
moving the bead to ordinary `pull_request` gating. A PR that becomes visible is
thus codex-green at birth, with no draft phase (drafts stay retired, #163). The
pre-open subset is the only part of the check-set that moves ahead of
PR-creation; the rest — CI, approval — stay post-open, gated at merge by the same
check-set the merge skill already enforces. Which members run pre-open is fixed in
code today; making that membership data-driven is a recorded, not-yet-built
extension (see [the check-set](#the-check-set-one-class-of-gate)).

**The movers.** The **worker** builds (`open → in_progress → hands off`) and
reworks; the machine names a role, not a specific agent. The worker closes its
own **ephemeral** unit (there is nothing to merge) and hands a keepable artifact
to the refinery like any other PR, but it never closes a unit that merges. The
**merge skill** is the **single writer of merged-truth**: once the check-set
clears it validates, performs the merge, and records that the bead landed —
synchronous, because the agent that merged is the one that knows it merged. The
**observer** is the backstop for what no one knows: it detects desync (a merge
skill that died mid-merge, an out-of-band merge, an unowned artifact) and
surfaces it, but it **never writes merged-truth**. The **refinery** is the agent
that runs the closing roles today; its *active* endpoint is still PR-created — it
hands the bead to gating and moves on, and a later idle pass runs the merge skill
— so it does not babysit a PR to merge. Keeping a single writer of merged-truth
is deliberate: one authority over "did it land" means no second place for that
state to drift. No coordinator (mayor / mechanik / deacon / witness) sits in this
loop.

## The check-set: one class of gate

A gating convoy does not wait on a single "is it reviewed?" flag. It waits on a
**check-set** — a set of conditions that must all hold before the work may land.
For a bead landing to `main`:

| Check | Satisfied by | Evidence |
|---|---|---|
| **signoff** | the signoff gate (a review step) | a `check.<name>=green@<head>` marker on the anchor |
| **CI** | the rig's CI on the PR | required checks green |
| **approval** | a human (or delegated) approver | an approving PR review |
| **title/description current** | the head-bound marker | every gate marker is `green@<live-head>` |
| **merged** | the merge itself | `merged_sha` exists |

These are the **same class of thing**: a PR triggers CI, which runs
asynchronously against GitHub, exactly as approval is asynchronous — from the
machine's point of view all are gates to track and follow up on, none
privileged. The set is **composable**: the signoff gate is one pluggable member,
not a hardcoded step, and a rig may add or drop members (a second reviewer, a
license check, a changelog check) without changing the machine, which only ever
asks "are all members of this convoy's check-set satisfied?" A keepable-artifact
PR uses this same set; an ephemeral unit's set is the single member "recorded."

**How the check-set is recorded (gc-toolkit).** Each gate is realized as a
per-gate marker on the gating anchor — `check.<name>=green@<sha>`, meaning "gate
`<name>` passed at commit `<sha>`." The anchor declares which gates apply in a
`check_set` metadata field (comma-separated gate names; empty declares no gates),
and the merge skill (`merge-skill.sh`) holds the merge until **every** gate named
in `check_set` is green **at the live head** — each `check.<name>` must equal
`green@<live-head-oid>`. Adding a gate is adding a name to `check_set` plus
whatever step stamps its marker; the merge skill is unchanged. This replaces the
retired `signoff_head` field (a single conflated marker) and the `review_gate`
string var: the per-gate marker model is the composable check-set made concrete.

**A dropped gate is silent, so a doctor check watches for it (tk-4na1b).**
"Empty declares no gates" is load-bearing at merge time and invisible everywhere
else: `merge-skill.sh` reads the stamped bead metadata and never consults the
formula, so an anchor stamped `check_set=""` lands ungated even though
`mol-refinery-patrol.toml` declares `default = "codex"` — which is how
shutupandlisten merged 11 PRs with no automated review before anyone noticed.
`doctor/check-merge-gate-drop/` turns that into a signal: it errors on a **live**
gating anchor stamped explicitly empty against a non-empty declared default, and
warns when a rig's *resolved* `check_set` is explicitly empty (a `--var` at a pour
site, or rig `formula_vars`). It is detect-only and never treats an **unset**
`check_set` as a drop — unset is the pre-#182 legacy state, and holding on it is
the stranding bug that "empty declares no gates" exists to fix.

**The pre-open subset: members that run before the PR opens (gc-toolkit,
tk-6d0vb.1.8).** Some check-set members can be produced *early* — against the
branch, before the PR exists — instead of post-open. These form the **pre-open
subset** of the check-set. A member in the subset is special only in *when* its
marker is produced, not in kind: the refinery stamps `check.<name>=green@<branch-head>`
on the branch during **pre-open gating** (above) so the PR opens already green on
that member, and the very same head-bound marker re-gates at merge if a later
commit moves the head. Every member outside the subset — CI, approval — is
produced post-open and gated at merge. The merge skill is unchanged either way: it
asks only "is every check-set member green at the live head?"

**The pre-open subset is currently exactly `{codex}`, and that membership is
hardcoded, not data-driven.** `pre-open-resolve.sh` reads only `check.codex` and
holds PR-open until it is green@head; `mol-refinery-patrol.toml` dispatches codex
specifically. What is *already* generic is the pre-open **phase** itself — the
`merge_result=pre_open_gate` state and `pre-open-resolve.sh` are phase-named, not
codex-named — so growing the subset needs no undoing of the shipped gate (PR #186).

> **Planned extension — data-driven pre-open membership** (recorded here as
> intent; **not built** — YAGNI until a real second pre-open check exists). To run
> more than codex before the PR opens, make the subset a declared property of the
> check-set rather than a constant in code:
> - **Declare membership as data** — a `pre_open_subset` field listing which
>   members run pre-open, or a per-check `phase=pre_open|merge` attribute carried
>   alongside `check_set`.
> - **Gate PR-open on all pre-open members** — `pre-open-resolve.sh` opens the PR
>   once *every* declared pre-open member is green@head, not only `check.codex`.
> - **Dispatch each pre-open member against the branch** — the refinery fans out
>   one branch-side dispatch per pre-open member, the way it dispatches codex today.
>
> **Build trigger:** a second check is wanted pre-open. Design tk-6d0vb.1.7 (Q7)
> already names **CI moving pre-open** as the likely candidate. When it fires, file
> a separate implementation bead; nothing in the shipped pre-open gate (PR #186)
> blocks the path.

**`title/description current` is load-bearing.** Approval and CI can be
**stale**: an approval given on an earlier diff, with a title and body that no
longer describe what will land, can still read as green. Approval alone is
therefore not a sufficient gate; each gate's marker is **bound to the head it
validated** (`green@<sha>`), so the merge skill merges only while every gate is
green at the *live* head — a later commit moves the head, the marker no longer
matches `green@<live-head>`, and the gate re-gates. A stale approval therefore
cannot carry an out-of-date PR onto the target.

## Rework is a new child

When a check needs work — a signoff requests changes, CI fails, the description
has drifted — the fix is a **new child filed against the convoy**, never the
same bead cycling open→closed→open and never a flag toggled back on the convoy.

- **The PR is changed, never closed and reopened.** Rework adds commits to the
  same PR branch; the PR is a long-lived object across however many rework rounds
  it takes.
- **The completion gate stays honest for free.** A convoy completes only when
  all its children are closed. The moment a rework child is filed it is open, so
  "all children closed" is false and the convoy cannot land — automatically, no
  extra flag. Five rework rounds are five children, each closed when its own fix
  landed; none is the same bead reopened, so no bead's history lies about how
  many times it "finished."

The signoff gate **attaches as a dependency of the open convoy** — the gate's
bead BLOCKS the convoy (`gc bd dep <gate> --blocks <convoy>`). The dependency
graph then shows directly which bead owns which PR and what it waits on.

**A rework child never becomes a second anchor — one gating anchor per PR
(tk-ynz4b).** When a rework child hands its fix back through the refinery, its
commits are already on the convoy branch, which *is* that child's landing
target — so the hand-back closes the child as landed-on-branch and gating
continues on the existing anchor alone. The child is never stamped
`merge_result`: while open it is exactly what the merge skill's
in-flight-rework hold counts (open, references the PR, no `merge_result`), and
stamping it would enroll it in the anchor enumeration as a second anchor with
no `check_set` — the PR's effective gate would become its *weakest* anchor,
landing the PR past a red codex gate. The re-review dispatched at hand-back
anchors to the existing anchor (its `check.<name>` markers are the ones the
merge skill and `pre-open-resolve.sh` read). Independently, the merge skill
refuses to merge any PR claimed by more than one open anchor: a legacy
double-anchor pair is held — never merged through either anchor — until the
duplicate is closed or demoted.

## When a child isn't landing

A convoy cannot complete while a child is open — that is the completion gate
doing its job, and it holds correctly however the child came to be stuck. Three
cases differ only in **how the condition becomes visible**, not in what the
machine does:

- **a decision** — someone chose to abandon or redirect the child. This is a
  known outcome, represented by **closing** the child: the work is no longer
  wanted, so there is nothing unlanded to lie about.
- **a known need** — the child knows it is blocked (a dependency, a missing
  input, a recognized error). It **raises its hand** in-band; the bead reports
  the blocker on itself.
- **an unknown failure** — nobody knows what broke. There is no hand to raise,
  so it is **caught from outside** by an observer reading state, liveness, and
  time (the *stuck* case from the honesty boundary above).

In all three the convoy blocks the same way — an open child means the branch is
not whole, so the PR cannot land — and no escalation machinery sits in the flow.
Known conditions are pushed in-band by the bead; the unknown residual is the
observer's to surface.

## Closure flavors: what "landed" was

`closed` means landed, but *what* landed differs by unit, so "merged" is not the
universal close reason:

- a **convoy** that holds a PR closes when **its PR merges** (`merged_sha`);
- a **child** closes when **its own output lands** — merge to the convoy branch
  for code, or the note recorded for an ephemeral unit.

Reading "merged" as the close reason for everything would be wrong: an ephemeral
child closes with a written note and no merge at all.

## Merge: one writer of merged-truth

No worker performs the merge by hand. The merge is the terminal check, and it is
run by a **merge skill** — an agent action that, once the rest of the check-set
clears, does three things in order: **validate** (title and description current,
every check satisfied), **merge**, and **record** that the bead landed. Because
the merge skill performed the merge, it is the one place that knows the merge
happened, and it is the **single writer of merged-truth**.

An **observer** is the backstop, not a second writer. It detects **desync** — a
merge skill that died between merging and recording, or a merge that happened
out-of-band — and surfaces the discrepancy for repair; it never writes
merged-truth itself. The reason for one writer is structural: if two places both
decided "merged" (say a merge skill *and* an independent poll), they could
**desync** — one fires, the other does not, and the bead's state disagrees with
the PR. One writer, one backstop that only observes, no place for "did it land"
to drift.

## Abandonment: we close our own PRs

A PR can end without merging — the approach was wrong, the work was superseded,
the bead was cancelled. When **we** abandon, the refinery **closes the PR and
the convoy together** with an abandoned reason; there is no escalation, because
abandoning our own work is a normal outcome.

Escalation is reserved for the case the machine has no context for: a PR closed
**out-of-band** — by a human or a process outside Gas City — that the refinery
did not initiate. There the bead is left open, flagged, and routed to a human
(`gc.routed_to=human`), because only they know why. This is an **observer
detecting a known external discrepancy** — the same out-of-band backstop as the
merge observer, consistent with the taxonomy above, not the in-flow escalation
it rules out. The rule: **we close what we abandoned; we escalate only what
someone else closed.**

## Stale base: the conflict we route, not escalate

A rewritten target branch — an upstream-rebase landing that force-pushes `main` —
rewrites every open PR's base commit out of existence, and **every** open gating
anchor goes CONFLICTING at once. The merge skill correctly refuses to merge a
conflicted PR, but unlike its other holds (BLOCKED, BEHIND, UNSTABLE, UNKNOWN)
this one never clears on retry: the anchor is detached from both work queues by
design, so without an arm for it nothing ever dispatches the rebase and the work
is stranded — invisibly, since a gating anchor is watched only by the observer.

The observer therefore files a **rebase child** of the anchor and routes it to the
fix pool, the same shape as a check that needs work: rework is always a new child,
never the anchor reopened. Two properties make it converge:

- **The anchor stays gating** (`merge_result=pull_request` intact). This is the
  one discrepancy the observer does *not* flip off the gating marker for, because
  it is the one that needs no human decision — the remedy is mechanical. Flipping
  it would also drop the anchor out of the *merge skill's* scan, so the rebased,
  green PR would sit ready with nothing left to land it. The open child holds the
  merge meanwhile (an anchor lands only when all its children are closed), and on
  hand-back the one-anchor-per-PR arm closes the child as landed-on-branch rather
  than minting a second anchor.
- **One rebase per head** (`stale_base_head=<head at detection>`). The arm re-arms
  only when the head moves, so a later rewrite that conflicts the *new* head is
  treated as the new stall it is, while an unchanged head is never re-filed.

This is still observation, not merge authority: the observer routes work and
records why, and the merge skill remains the single writer of merged-truth.

## Stale gate: the review we re-dispatch, not leave hanging

The symmetric twin of stale base. A gating anchor whose check-set went green —
`check.<name>=green@<oid>` — and whose PR head then advanced **past** `<oid>`
through a path that files **no rework bead** (a direct push to the PR branch, an
operator fixup) sits in a **silent indefinite hold**. The merge skill correctly
refuses (its stale-head guard: `green@<oid>` must equal the *live* head), but with
nothing re-dispatching the review the anchor is indistinguishable from a healthy
PR awaiting approval — it never merges, never rejects, never escalates. The
in-band re-gate paths do not reach it: `find-work` skips `assignee=""` anchors,
the auto-re-dispatch arm fires only on a polecat rework hand-back, and
`check-set-heal.sh` heals only an *empty* check-set and explicitly assumes a
green-at-a-stale-head marker "re-gates through the normal rework path" — the exact
assumption the no-rework-bead push disproves.

The observer therefore files a **codex re-review child** of the anchor at the LIVE
head and routes it to the review pool, the same shape as the stale-base rebase
arm. Two properties make it converge, mirroring stale base exactly:

- **The anchor stays gating** (`merge_result=pull_request` intact) and the gate is
  re-earned by a **real review**, never a hand-stamped `green` — stamping green
  here would certify an *unreviewed* commit. The open review child holds the merge
  meanwhile; its COMMENT signoff re-stamps `check.<name>=green@<live-head>` and the
  merge proceeds, and on hand-back the one-anchor-per-PR arm keeps it a single
  anchor. A `REQUEST_CHANGES` instead files a rework child, which clears the marker
  through the normal path.
- **One re-review per head** (`stale_gate_head=<head at detection>`). The arm
  re-arms only when the head moves again, so a later push off the *new* head is
  the new stall it is, while an unchanged head is never re-filed. Between dispatch
  and signoff the open review child also holds it, so the marker is the belt to
  that suspenders.
- **A poolless hold recovers** (`stale_gate_nopool_head`). When no review pool is
  configured the arm cannot dispatch; it holds on a *distinct* marker rather than
  `stale_gate_head`. Reusing `stale_gate_head` would read as "already dispatched at
  this head" and suppress the re-review forever — so once the pool is configured a
  later pass at the *same* head still dispatches, instead of the poolless pass
  silently stranding the anchor it was meant to heal.

Kept self-contained so the "detect stale gate → re-dispatch at head" logic can be
re-housed later inside a convergence loop without moving its guarantees.

## Anchorless PRs: reconciling from the other side

Every automated path in close-on-land starts from the **bead**: the merge skill,
the merge observer, and the refinery patrol all enumerate gating anchors and read
each one's `pr_number`. That is sound while the bead outlives the PR — which the
close-on-land model guarantees, since the anchor closes only on land.

It fails in the one state the model is designed to prevent but cannot retroact:
a PR whose bead is **closed** (or gone). Such a PR is not merely unhandled, it is
*unseen* — no scan starts anywhere that would reach it. It never appears in a
queue, never escalates, never times out. It does not read as broken; it reads as
absent. The pre-`#163` close-on-publish model created exactly this state by
design (bead closed at PR-creation), and the PRs it stranded sat untouched for
weeks — surfaced only when a human cross-checked `gh pr list` against the ledger
by hand.

So the observer also reconciles **PR → bead**: enumerate open PRs, subtract every
PR number any *live* bead references, and report the remainder. Two rules keep it
honest:

- **Detect and surface only.** It never merges, closes, or reopens an anchorless
  PR. Disposition — land it, close it as abandoned, or reopen the bead for
  rework — needs context the observer does not have, and stays an operator call.
  It emits the finding; a human decides.
- **Escalate once, or not at all.** A PR whose closed bead is resolvable is
  escalated once, bounded by an `anchorless_flagged` marker written to that bead
  *before* the mail goes out. A PR with no bead in any state is reported to the
  log but never mailed: there is nowhere durable to record that we already said
  it, so mailing would repeat every patrol wake forever. Likewise, a failed
  ledger read is empty rather than `[]`, and the scan fails **closed** on it —
  treating "I could not read the ledger" as "nothing is tracked" would flag every
  open PR at once.

Note the asymmetry with the rest of this document: the other dispositions fix a
bead whose PR misbehaved, while this one surfaces a PR whose bead is already
gone. Closing the loop from both directions is what makes "the bead is the index
of in-flight work" safe to rely on — any state where a PR outlives its anchor
falls out of that index silently, and only the PR-side scan catches it.

## Divergence from stock GasTown

Stock GasTown mr-mode closes the work bead at **PR-creation**. gc-toolkit keeps
the bead **open through gating and closes it on land**, so `closed` always means
landed and the dependency graph always shows which bead owns which PR. This is a
**pack-only delta** — it lives entirely in the `mol-refinery-patrol` formula and
its merge skill + reconcile scripts (`merge-skill.sh`, `reconcile-merged-prs.sh`,
`reconcile-graduated-convoys.sh`, `pre-open-resolve.sh`); gascity core is
untouched and gains no new status (`gating` and `pre_open_gate` are metadata
markers on an ordinary `open` bead). **Direct-mode beads are unchanged.**
