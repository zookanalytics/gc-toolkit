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
extension (see [the check-set](#the-check-set-one-class-of-gate)). Because this is
the pass that *mints* the PR from a **branch name**, every read it makes and the
create itself are pinned to this checkout's origin repository and certified before
anything is stamped — see
[the invisible anchor](#the-invisible-anchor-repairing-the-field-every-pass-enumerates-on).

**The flip out of `pre_open_gate` is ordered, not atomic.** `merge_result` is not
one field among four here: it is the **visibility switch**. `pre_open_gate` is the
only sub-state that opens or re-adopts a PR, and `pull_request` is the one the merge
skill and the observer act on — so a single `gc bd update` carrying the switch
*and* `pr_url`/`pr_number`/`merged_target` can, if it persists partially, leave an
anchor that has left the only state that would ever open its PR and entered the
states that act on an identity it does not have. Both passes then skip it on an
empty number, and nothing routes it back: the invisible anchor again, reached from
the other side. The identity fields are therefore written **first**, **verified by
re-read** (a `gc bd update` that returns is not a ledger that holds it — the same
rule the `check_set` stamp follows), and only then is the switch thrown. Every
failure direction leaves the bead in `pre_open_gate`, which is the idempotent one:
the next pass finds the PR through the existing-PR arm, re-certifies it, and retries
the whole sequence. For the same reason the created PR is certified to be **at the
reviewed commit** — `--head` names a mutable ref, and a branch that moved between
the gate and the create would publish a non-draft PR at a commit codex never saw.

**The movers.** The **worker** builds (`open → in_progress → hands off`) and
reworks; the machine names a role, not a specific agent. The worker closes its
own **ephemeral** unit (there is nothing to merge) and hands a keepable artifact
to the refinery like any other PR, but it never closes a unit that merges. The
**merge skill** is the **single writer of merged-truth**: once the check-set
clears it validates, performs the merge, and records that the bead landed —
synchronous, because the agent that merged is the one that knows it merged. It
validates against a **fresh read of the anchor** (the enumeration snapshot
predates the PR read, and the signoff path writes the anchor concurrently), it
**re-reads the anchor once more immediately before merging** — the bead is the
authority for the merge, and the window between the last gate and `gh pr merge`
is made of round-trips another writer can act inside (park it with `merge_hold`,
clear or advance a `check.<gate>` on a re-gate, close it, retarget it) all
without moving the head — and it pins the merge to the **exact head it
validated** (`--match-head-commit`), so neither a mid-pass metadata write nor a
mid-pass push can land something no gate in that pass ever looked at. An
unreadable re-read holds: a merge is the one act the pass cannot retract, so "I
could not re-confirm" must never merge. The
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
| **approval** | a human (or delegated) approver | an approving PR review at the live head, by an account that is neither the city's nor untrusted (below) |
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

**`approval` is checked explicitly, because `CLEAN` only folds it sometimes
(tk-5niup).** `merge-skill.sh`'s terminal gate is GitHub's composite
`mergeStateStatus=CLEAN`, whose comment long read as "mergeable, required checks
green, **and approved**". That last clause holds only where the repo's ruleset
*requires* a review — there, no approval means `REVIEW_REQUIRED` and `BLOCKED`.
On a repo with **no** review requirement and no CI, `CLEAN` is true with **zero**
approving reviews, and the merge lands unreviewed work. So `approval` is a real,
separately-evaluated member: satisfied by an `APPROVED` review from an account
**other than the one the city acts as** — the city posts COMMENT signoffs and
never approves (#185), so a self-approval must never count — **and attached to
the PR's live head**. Head-binding is not optional here: it is the same
`green@<head>` rule the marker members follow, and without it the sequence
"human approves head A → work is pushed → the city dismisses its own block" ends
in a merge of a commit nobody approved, on any repo that keeps stale approvals
effective. That means the evidence is read from the paginated REST reviews
history, where each verdict carries its `commit_id`; `gh pr view --json
latestReviews` cannot serve it, because it reports the latest verdict per
reviewer with **no commit** — an approval of a dead head reads exactly like an
approval of the live one. Effective verdict is the **latest state-bearing review
per reviewer, computed before any verdict filtering**: `COMMENTED`/`PENDING` are
excluded outright — they carry no verdict and supersede nothing (the city's own
signoffs live there) — while `DISMISSED` *does* take part, because a retracted
review must **shadow** that reviewer's older rows. Filtering the terminal states
first is what lets a dismissal resurrect the `APPROVED` that preceded it, an
approval explicitly taken back satisfying the gate. Effectiveness is per
reviewer, but the *hold* is not: a standing `CHANGES_REQUESTED` from **any**
external reviewer vetoes the merge — one human's approval does not answer
another's unresolved objection, and on an unprotected repo `CLEAN` reads straight
through the objection. The veto is deliberately **not** head-bound (unlike the
approval): an objection stays live until its author supersedes it or it is
dismissed, and a new commit does not resolve it.

**The veto is not part of this member.** It is evaluated for *every* merge
candidate whose review history was read — whatever `check_set` names, marker or
not, and whether or not the anchor carries `signoff_dismissed`. `approval` asks
whether a human said **yes** where GitHub does not require one; the veto asks
whether a human said **no**, and nothing about a rig declining to declare
`approval` makes another reviewer's objection stop counting. Scoped inside the
approval gate (where it was first written), the ordinary anchor — `check_set`
`codex`, marker green at the live head, `CLEAN` because the repo is unprotected —
never consulted it at all and merged straight past an open changes-request
(tk-bdfww).

Unlike the other members `approval` is evidenced by
GitHub review state rather than a `check.<name>` marker, so the marker loop drops
the name the same way it drops the `none`/`off` sentinel; leaving it in would
hold the anchor forever on a `check.approval` no reviewer can stamp. It is
required when either:

- the anchor **names `approval` in `check_set`** — the explicit opt-in a rig on
  an unprotected repo should declare; or
- the anchor carries **`signoff_dismissed`** — the city retracted its own
  blocking review on that PR (below), so part of the PR's `CLEAN` is *our* doing
  and can no longer stand in for approval. Sticky on presence, not head-match: a
  dismissal is permanent, so a later head must not silently drop the requirement.
  Combined with head-binding this is deliberately strict — once the city has
  retracted a block on a PR, every subsequent head of that PR needs its own
  external approval. That is the intended shape: the thing we traded away was a
  standing GitHub-side block, and the replacement has to be at least as current
  as what it replaced.
- the PR's **review history shows a review authored by the city that is now
  `DISMISSED`** (tk-tmefn) — the same fact as `signoff_dismissed`, read from the
  side that cannot be bypassed. The marker records only the dismissals the city
  performed *in-band*; an operator who clears the stale city
  `CHANGES_REQUESTED` by hand on github.com leaves no marker at all, and on an
  unprotected repo that hand-clearing is precisely what turns the PR `CLEAN`. So
  the requirement follows the *retraction*, not the bookkeeping. GitHub only
  permits dismissing a state-bearing review and the city never approves, so a
  `DISMISSED` review under the city's login can only be a `CHANGES_REQUESTED` of
  ours that someone took back. Sticky, like the marker arm.

  Reading it costs one paginated reviews call per merge candidate, and makes an
  unreadable review history a hold where it previously was not: an unreadable
  history cannot show that no block of ours was retracted. Where the acting login
  itself cannot be resolved, no dismissal can be *attributed*, so the arm widens
  to "was anything dismissed on this PR at all" — over-broad, but scoped to PRs
  whose review state someone has already been editing, so a `gh api user` blip
  cannot stall a queue of PRs that carry no dismissals.

The default `check_set` is unchanged, so this adds no new hold to a rig whose
ruleset already requires review — there, approval was always the thing turning
`BLOCKED` into `CLEAN`. A rig on an unprotected repo that wants the guarantee
adds `approval` to its `check_set`.

**The approver must be TRUSTED, not merely external (tk-pkgym).** "An account
other than the city's" is a self-approval guard, not an approval *policy*: any
GitHub account can submit an `APPROVED` review, and this member matters precisely
where the repo enforces nothing server-side — so on an unprotected repo a
read-only collaborator, an unrelated bot, or a throwaway account would otherwise
land the PR. Every non-self `APPROVED` at the live head is therefore a
**candidate**, and the gate is satisfied by the first candidate that passes the
trusted-approver policy:

- `MERGE_TRUSTED_APPROVERS` (comma-separated logins), when set, **is** the
  policy — an explicit operator allowlist, evaluated with no API call. It
  *replaces* the probe rather than widening it: an unlisted account is untrusted
  even with write access.
- otherwise the approver must hold **write-level permission** on the repo
  (`admin`/`maintain`/`write`, read from
  `repos/{owner}/{repo}/collaborators/<login>/permission`). `author_association`
  is deliberately not used: `COLLABORATOR` covers a read-only collaborator.

Anything else — including a permission probe that cannot be **read** — is
untrusted and holds the merge, the same fail-closed reading every other gate
gets. The hold names both remedies, so a token that may not read collaborator
permissions is a configuration fix (set the allowlist), not a permanent stall.

**Residual race, by construction.** Every gate here is validated client-side and
then the merge is issued; review state can still change at the same head in that
window (an approval dismissed, a `CHANGES_REQUESTED` posted) and the merge would
still go through. `--match-head-commit` closes the *commit* half of this — a new
push cannot slip an unvalidated head into the squash — but there is no equivalent
binding for review state. Only server-side branch protection is atomic with the
merge. Where this local gate is the whole policy, that window is the accepted
residual risk; a rig that cannot accept it should require reviews in the repo's
ruleset, which makes GitHub itself refuse the merge.

**`title/description current` is load-bearing.** Approval and CI can be
**stale**: an approval given on an earlier diff, with a title and body that no
longer describe what will land, can still read as green. Approval alone is
therefore not a sufficient gate; each gate's marker is **bound to the head it
validated** (`green@<sha>`), so the merge skill merges only while every gate is
green at the *live* head — a later commit moves the head, the marker no longer
matches `green@<live-head>`, and the gate re-gates. A stale approval therefore
cannot carry an out-of-date PR onto the target.

## Review state: the GitHub side must not diverge from the bead side

A signoff writes its verdict in **two places** — the `check.<name>` marker on the
anchor and a review on the PR — and both are gates. Keeping them consistent is
not bookkeeping; when they disagree the PR becomes structurally unmergeable in a
way no amount of re-gating fixes (tk-5niup).

The loop that exposed it: codex reviews at head A, requests changes (a GitHub
`CHANGES_REQUESTED` review) and files a rework child; the rework lands and the
head advances to B; the re-gate at B finds everything resolved, posts a `COMMENT`
review and stamps `check.codex=green@B`. **A `COMMENT` review does not supersede
the same reviewer's earlier `CHANGES_REQUESTED`**, so GitHub keeps
`reviewDecision=CHANGES_REQUESTED` and `mergeStateStatus=BLOCKED` — pinned to a
commit that no longer exists — while the bead reads green. `merge-skill.sh`
requires `CLEAN`, so every PR that takes a changes round strands forever.

**The re-gate therefore retracts its own superseded review in the same step that
stamps green** (the `signoff-supersede-dismiss` snippet in
`template-fragments/polecat-non-impl-done.template.md`). Seven guards make the
retraction honest, and each one is the difference between reconciling and
erasing:

- **Our own reviews only.** A human's `CHANGES_REQUESTED` is a veto, never ours
  to clear.
- **Superseded commits only** — a review pinned to a commit other than the one
  just signed off. A `CHANGES_REQUESTED` at the *reviewed* commit means we both
  blocked and passed the same head; that contradiction holds, it does not resolve.
- **Only while the reviewed commit is still the live head** — re-read
  *immediately before each dismissal*, not once before listing the reviews. If
  the head moved after the signoff, removing the block would unblock an
  *unreviewed* commit — the same stale-head hazard `green@<oid>` exists to
  prevent. Checking only at listing time leaves a window in which a **fresh**
  block posted on the **new** head is indistinguishable, by commit, from a
  superseded one, and the retraction erases a live veto.
- **Record before retracting, and confirm the record.** Dismissal removes a
  GitHub-side merge block, so it is **merge-triggering** wherever `CLEAN` folds no
  approval; it is paired with `signoff_dismissed` on the anchor, which arms the
  explicit `approval` member above. The marker is written **first** and the
  dismissal runs only if it stuck: marker-then-dismiss can only over-hold, while
  dismiss-then-marker would drop both the block and the requirement if the write
  failed. "Stuck" means **read back off the anchor**, not "the write exited 0" — a
  `gc bd update` can report success and still not be durable, and an exit status
  cannot tell the two apart. Both markers on this path — the gate stamp and the
  pairing marker — are verified that way, for the same reason.

  The marker is the *pairing*, not the requirement itself. It cannot be: it is
  written only by this in-band path, so an operator dismissing the same review by
  hand produces the identical GitHub state with no marker anywhere. That is why
  the `approval` member's third arm reads the dismissal out of the review history
  directly (above) — the marker makes the in-band case cheap to see, the history
  makes *every* case impossible to miss.
- **Only on a confirmed-green gate.** The `check.<name>=green@<oid>` stamp that
  the retraction is trading for is itself best-effort — it is read back and the
  retraction is skipped unless the anchor really carries it. A dismissal against
  an unrecorded gate gives up the block for nothing. An unrecorded gate also
  **keeps the review bead open**: the review is flagged `signoff_retry` and
  re-routed to its own pool instead of being closed. Closing it would leave the
  anchor held with no marker *and* no open child — `check-set-heal.sh` repairs an
  empty `check_set`, not a missing marker under a normal one, so nothing would
  ever raise the gate again and the PR would strand silently.
- **Never while the anchor carries `merge_hold`.** Retraction is pipeline work on
  a PR an operator has deliberately parked, and merge-triggering work at that:
  dropping the last GitHub-side block is exactly what the hold forbids. The
  observer's retraction arm already skips a held anchor; the re-gate runs in the
  same anchor state and makes the same call. The gate marker is still stamped —
  recording a signoff is not merge-triggering — and the next re-gate retracts
  once the hold lifts.
- **Never while native auto-merge is armed — or unreadable.** With `gh pr merge
  --auto` set, clearing the last block does not *permit* the merge, it *performs*
  it — server-side, immediately, before `merge-skill.sh` reads `signoff_dismissed`
  at all. The approval requirement binds our own skill, never GitHub, so this case
  fails closed: the block stays up and an operator disarms auto-merge or lands it
  deliberately. The probe is therefore read **three-valued** — armed / disarmed /
  unknown — and only a definite *disarmed* clears the guard. Read through a
  `.autoMergeRequest // empty` filter, an API error, an auth failure, a rate limit
  and a malformed payload all produce the same empty string a genuinely disarmed
  PR does, so a probe that *failed* would clear the one guard whose entire job is
  to stop a server-side merge. Like the live-head check, it is re-probed
  *immediately before each dismissal*: auto-merge can be armed inside the window
  the up-front probe cannot see.

The reviews history is read **paginated** (`--paginate`, explicit `per_page`)
everywhere it is read. GitHub pages the endpoint at 30, and a PR that took a
changes round — the only kind either path acts on — is exactly the PR whose
reviews spill past page one. Unpaginated, the re-gate can `last` an *older*
review of its own and stamp the gate at the wrong commit, and the retraction can
miss the standing block entirely and leave the PR stranded in the state it exists
to heal.

Retracting *without* that pairing is the trap on the other side of this bug. The
stale review can be the **only** thing holding an unprotected repo's PR
non-`CLEAN`; clear it alone and the refinery squash-merges on its next idle pass.
Fail-closed in both directions is the rule: never strand a green PR, and never let
a cleanup action become an unreviewed merge.

**The observer converges what is already stranded.** Retracting at re-gate time
stops *new* strands, but an anchor stranded before it was in place has a marker
green at the live head — so the stale-gate arm above never fires, nothing
re-dispatches a review, and there is no in-band path out. The observer therefore
carries the **inverse** of the stale-gate arm: where that one sees a marker
lagging the head, this one sees the head's marker current and **GitHub** lagging
(`reviewDecision=CHANGES_REQUESTED` against a green gate). It performs the same
guarded retraction with the same pairing marker, honors `merge_hold` like every
other arm, and converges by construction — once dismissed the decision is no
longer `CHANGES_REQUESTED`, so the arm does not re-enter. The two arms are
symmetric halves of one rule: **whichever side is stale, re-earn it on that side —
never paper over the difference by stamping the other.**

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

**A child is recognized by that dependency, not only by `pr_number`.** The hold
resolves the child set two independent ways, because neither alone sees every
child: the PR number a bead stamps on *itself*, and the anchor's own dependency
edges — its `parent-child` **dependents** (the rework children) and the beads
that **block** it (the signoff gates). A rework child carries the *branch* while
the anchor carries PR *identity*, and the pre-open rework arm has no PR number to
stamp at all — it files before a PR exists — so a hold keyed on `pr_number` alone
looks straight past an open rework child and merges over it (tk-lgjvg, on PR#233).
Those two edges are also the *only* two that mean "holds this anchor," and the
directions matter: a `blocks` **dependent** is downstream work waiting *for* this
merge, and a `parent-child` **parent** is the epic above it — holding on either
would deadlock a healthy anchor forever. Any status but closed holds, since the
invariant is "all children **closed**"; a `blocked` child is the strongest case
of all, and an unreadable probe holds too, because "no children found" and "could
not look" are the same silence. A probe can also *succeed* and still be
unreadable: one malformed element inside an otherwise well-formed array aborts
the filter that reads the array, and an aborted filter returns byte-for-byte what
an empty one returns. So the check is not "did the query exit 0" but "could every
holder in the answer actually be read" — at the probe boundary and again at the
filter, since a payload valid enough to survive the first can still break the
second (tk-qoyly). One answer also has to be *one* answer: a probe that emits more
than one JSON document is unreadable even when every document is individually
well-formed, because the three probes are read out of a single stream by position
— an extra document shifts the later probes down a slot and the last one falls off
the end unread, silently deleting a whole class of holder (tk-wkrcy).

**Which source found a holder decides which filters may drop it.** Resolving by
`pr_number` sweeps up *every* bead naming the PR — including a duplicate gating
anchor, which is the one-anchor-per-PR guard's business below and not a child's,
so a `merge_result`-carrying bead from that source is discarded. A holder reached
by a **dependency edge** is never discarded that way: it was named as a holder
explicitly, and the shape you would delete is precisely the one that carries
`merge_result` by definition — an upstream PR or pre-open anchor filed as an
explicit merge-ordering `blocks`. Dropping it lets a green downstream PR merge
straight past the anchor it was ordered behind: the same fail-open as keying on
`pr_number` alone, reintroduced one layer down on the very edge added to close it
(tk-je0rk). A bead reachable both ways counts as a dependency holder — the
stronger claim wins, so no dep-linked bead is demoted into the discardable class
by also stamping a PR number.

The same rule governs the **repository** filter, and for the same reason
(tk-9m8q4). A PR *number* names a different pull request in every other
repository the ledger spans, so the `pr_number` sweep is the one — and the only
one — that can return a stranger: a foreign rework child carrying `#<n>` reads as
rework in flight on *our* `#<n>` and holds a ready PR indefinitely. That hold is
released by certifying the holder's own `pr_url` against the anchor's repository.
A holder reached by a **dependency edge** is never repository-filtered: it was
named by an explicit edge in *this* ledger, so it holds by virtue of the edge and
not by naming a number — and the shape you would delete is a legitimate
cross-repository merge-ordering block, which is exactly why an operator files one
by hand. So both exclusions are scoped to `_via == "pr_number"`, because both
exist only to undo that probe's over-broad sweep and neither says anything true
about a bead found by an edge. **A dependency edge is a claim; a PR number is a
coincidence until certified — only the coincidence is filtered.** Certification is
fail-closed either way: a holder whose `pr_url` cannot be parsed into a repository
stays the `?` wildcard and keeps its veto, so no legacy row loses its hold.

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

  "Closed" here means **`closed`, and nothing else**: a child in `blocked`,
  `deferred`, `hooked` or `pinned` owes exactly as much work as an `open` one, so
  the merge skill reads every non-closed status — and reads every key a bead names
  a PR with (`pr_number`, `fork_pr`, `fork_pr_url`), the same set the observer
  uses, so a child visible to one is visible to the other by construction. A
  ledger read the skill cannot complete HOLDS the merge rather than reading as "no
  child": an unreadable ledger and an empty one are indistinguishable through a
  projection, and only one of them is safe to merge on.
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

## The invisible anchor: repairing the field every pass enumerates on

Every disposition above is reached by enumerating gating anchors on
`merge_result`. That makes the field load-bearing in a way the others are not: an
anchor missing `merge_result` **entirely** is not merely un-gated or un-healed, it
is *unseeable* — by the merge skill, the pre-open resolver, the observer, and the
check-set heal that exists to repair bypassed anchors, all at once. There is no
pass left to notice. The failure is silent and unbounded: the machine reports a
clean queue while a PR rots. shutupandlisten's hand-recovered `su-uzy9.1` carried
`branch` and `pr_url` but no `merge_result`; the rig-wide gating set read empty and
PR#37 sat open for six days with zero escalations.

Note what did *not* catch it. The anchorless scan below walks PR → bead, and a live
bead did name PR#37 — carrying `branch`, so it read as *owned* rather than landing
on the unowned line. Both directions of the loop reported nothing, correctly, and
the PR was still stranded. Enumerating on the damaged field and enumerating on the
undamaged one are not the same coverage.

So the repair (`check-set-heal.sh` phase 0, ahead of the check-set normalization in
the same script) is keyed on a predicate that **survives the damage**: open beads
carrying `pr_url`/`pr_number` — which the refinery stamps only *after* it validates
a PR, so their presence is durable evidence the bead is past the polecat stage —
that carry no `merge_result`. It restores `merge_result=pull_request` and backfills
`pr_number` (the merge skill skips an anchor without one, so restoring visibility
without it yields an anchor that is seen and still never merges) from the certified
PR, and `merged_target` (what the retarget check compares against) from the anchor's
own recorded `target`/`merged_target`, falling back to the certified PR's live base
only when no recorded intent survived the damage. The recorded value wins on purpose:
adopting the live base would silently bless a retarget performed while the anchor was
invisible — precisely the window in which one could go unnoticed.

**The backfills land before the visibility, not with it.** `merge_result` is not
one field among several here — it is the *switch* that exposes the bead to every
pass above, and the other fields are what those passes then depend on. A partial
write that lands the switch and drops a dependent is not self-correcting: the bead
now *has* a `merge_result`, so it is no longer a candidate for this phase and
nothing will restore what went missing. The sharpest case is `merged_target`,
because the merge skill's retarget check is written as *"if a target is recorded
and it differs from the live base, hold"* — an empty `merged_target` does not fail
that check, it **skips** it, and the anchor merges onto whatever base the PR now
points at with no validation at all. So the dependents (`pr_number`,
`merged_target`, and the recovery markers `merge_result_healed` /
`merge_result_pr_state`) are written and verified **first**, and visibility is
flipped only once they are durable. A dependent that will not stick leaves the bead
invisible and retried on the next pass — the stall we already had, rather than a
new and permanent exposure.

Four rules keep it from inventing anchors:

- **Never enroll a child.** The merge skill's in-flight-rework hold counts exactly
  "open, references the PR, no `merge_result`" — the absence *is* the hold. Stamping
  a rework or review child would silently release it and land a PR mid-rework. So
  `anchor_bead`, `task_kind`, `source_review_bead`, `source_anchor_bead`, a
  non-empty `gc.routed_to`, a polecat assignee, or a PR already claimed by another
  open `merge_result`-carrying bead all disqualify a candidate. The last of these is
  one-anchor-per-PR read from the other end, and it must fail *closed*: an
  unreadable ledger returns the same empty answer as "no incumbent", so the lookup
  is only believed when it actually returned a result. It also has to ask the
  question on **both** identity surfaces — `pr_number` *and* a normalized `pr_url` —
  because `pr_number` is one of the fields this very phase backfills, so an
  incumbent that kept `merge_result` and `pr_url` but lost its number is a shape the
  recovery itself produces. A number-keyed lookup cannot see one, and the candidate
  would then be stamped *with* a number and become the only anchor the merge skill
  can see (it skips anchors without one) while the real anchor stays stranded.
  Both surfaces are keyed on **repository *and* number**, because a pull number is
  unique only within a repository and this city's ledger spans rigs with different
  ones — keyed on the bare number, another repository's `#745` reads as the owner of
  ours and refuses a real repair before the identity certification that would have
  caught the confusion ever runs. Qualifying one surface is not enough: the two are
  asked in sequence, so a foreign incumbent carrying *both* a `pr_url` and a
  `pr_number` was still refused by the number-keyed half. An incumbent whose
  repository cannot be named at all (no `pr_url`) is treated as matching, which keeps
  the guard fail-closed — the repository key narrows the guard, it must not become a
  way around it.
  Routing alone is not enough
  to exclude a child, because `gc.routed_to` is **cleared when a polecat claims
  it** — between the claim and the hand-back, a stale-base rebase child (which
  carries `branch`, `pr_url`, `pr_number` and no `merge_result`) wears the anchor
  shape exactly, and only `source_anchor_bead` still marks it.
- **Refuse ambiguity.** Two surviving candidates naming one PR means nothing here
  can tell which is the anchor; both are skipped and reported. A wrong anchor is
  worse than a visible stall. This one is a property of the *whole* candidate set,
  not of any single bead, which is why an unreadable candidate scan skips the entire
  phase for that pass: a scan that failed and a scan that found nothing return the
  same empty answer, and recovering from a half-built set can promote one side of a
  duplicate it never saw. Two rivals for one PR both lack `merge_result`, so neither
  reads as an incumbent — the one-anchor guard cannot catch what the scan dropped.
- **Certify the PR, not just its number.** `gh pr view <n>` resolves the number in
  the *current* repo, so a `pr_url` pointing at another repository's `#37` would
  silently bind this anchor to the local `#37` — and then gate and merge it. The
  metadata that named the PR is damaged by construction; that is why
  `merge_result` is missing at all. So the PR's own identity is checked against the
  bead before anything is stamped: the URL must be the same pull request, the PR and
  the branch it is opened *from* must both live in this checkout's own repository,
  and the head branch must be the bead's `branch`. The repository half is not
  implied by the rest — a branch name is owned by nobody, so a pull request opened
  from a **fork** that reuses the bead's branch name satisfies a `headRefName`
  comparison exactly, which is the same check the post-open validation in
  `mol-refinery-patrol` already makes against `headRepositoryOwner`/`headRepository`.
  A mismatch, an unreadable identity, or an origin repository this checkout cannot
  resolve at all (nothing to compare against means "matches" would only mean
  "unchecked") fails closed and waits for an operator to repair the metadata.
  That repository is named **host-qualified** — `<host>/<owner>/<repo>` — on both the
  read and the comparison. `<owner>/<repo>` does not name a repository; it names one
  *per host*, and `gh pr view --repo` accepts `[HOST/]OWNER/REPO` and supplies the
  host from `GH_HOST` when it is omitted. A hostless `--repo` therefore pins nothing:
  under a `GH_HOST` pointing at another GitHub host it reads that host's
  `<owner>/<repo>`, whose PR matches ours on owner, repo, head branch *and* head
  repository. Pinning the read and comparing the answer are two halves of one check —
  the comparison keeps the host so that a `gh` which ignored the flag (a transfer
  redirect, an older client) still shows up as a mismatch.
  A certification is only true in the process that performed it, so the certified
  URL is **persisted**: `pr_url` is backfilled from it alongside `pr_number`, as one
  more dependent of visibility. Without that, recovery hands the merge skill and the
  observer an anchor identified by *number alone* — the identifier this whole check
  exists to distrust — and they run later, in processes that never saw the
  certification and whose `gh` context is not this one's. Those passes pin their own
  reads to the origin remote's repository for the same reason and compare what comes
  back against the anchor's recorded URL; an origin they cannot resolve merges and
  records **nothing**, since a wrong merge cannot be retried away.
  The **pre-open resolver** asks the same question one step earlier in the lifecycle,
  where the anchor has no `pr_url` to compare against yet — it is the pass that
  *mints* one. There the identifier is a **branch name**, which names a repository
  even less than a number does: every fork of this repo can carry the same
  `polecat/<bead>`. So its existing-PR lookup, its branch-head read (`gh api`, pinned
  by explicit path plus `--hostname`, since there is no `--repo`), the create, and
  the verdict comment are all pinned to the origin-derived repository, and every
  answer is certified before it is stamped. Its stakes are the mirror of the merge
  skill's: `pre_open_gate` is the **only** state that retries PR-open, so an
  uncertified foreign same-branch PR does not merely mis-gate the anchor — it moves
  it out of that state onto a stranger's `pr_url`/`pr_number`, after which the
  hardened merge and reconcile passes correctly hold or skip and *nothing* ever opens
  the real PR. An unresolvable origin therefore opens nothing at all: a PR opened in
  the wrong repository is a published artifact no retry can take back.
  **And the repository a PR lives in is not the repository it comes from.** Pinning
  the read answers where the *answer* came from; a pull request opened **into** this
  repository **from a fork** is served by that pinned read and carries one of our own
  URLs, so the URL half certifies it while its head is a stranger's. `--head` filters
  on the branch **name** alone, so it is listed beside ours with nothing but arrival
  order between them — and taking the first row made that order decide which pull
  request an anchor binds to. So every candidate, whether found by the existing-PR
  lookup, discovered after a create race, or just created, is certified on all four
  halves of its identity — URL repository, head branch, **head repository**, and base
  — and the branch's pull request is *chosen* from the certified rows (a live `OPEN`
  ahead of a `MERGED` one, and both ahead of a dead `CLOSED` one) rather than taken
  off the top of the list. Certifying the *created* PR means reading it back **by
  number**, never by branch name: resolving a pull request by a name nobody owns is
  the gap itself, so the create-race discovery re-runs the same certified scan instead
  of `gh pr view <branch>`.
  Three answers, not two, because the dispositions differ. Nothing open from a branch
  of this name is the only one on which a PR is opened. A read that **failed**, a full
  page that may be **truncated**, an unreadable row, or a name collision in which
  *none* of the matches is this anchor's are all refusals: "I could not see it" and
  "it is not there" differ by exactly one twin pull request, and so do "nothing is
  open from this branch" and "the only things open from a branch of this name are
  somebody else's". A name collision is a state an operator looks at, not one to open
  a pull request into.
  **Every pass that acts on a pull request asks the head question, not just the one
  that mints it.** A fork's PR into this repository is served by the merge skill's
  and the observer's pinned reads too, and passes their URL comparison for the same
  reason — the URL is ours. So both certify the head as well: the head repository is
  this checkout's own, GitHub's own `isCrossRepository` agrees with that comparison
  (a row claiming both is self-contradicting, and an identity that contradicts itself
  is *unestablished* rather than a tie to break), and the head branch is the one the
  anchor records — checked only when the anchor has one, since a `pr_number`-only
  anchor, the shape recovery produces before backfill, has nothing to disagree with.
  An unreadable head holds rather than lands. The stakes differ by pass and both are
  terminal: the merge skill would squash a stranger's head onto the target under our
  anchor's gates, and the observer would close, escalate, retarget, or dispatch a
  **rebase** whose branch it takes from the PR's own `headRefName` and force-pushes —
  against a fork's head, a rebase onto a branch this rig does not own.
  In the observer that comparison covers **both** directions of its reconcile, not
  just the anchor reads: the anchorless scan enumerates open PRs with `gh pr list`
  and then stamps `anchorless_flagged` on a local closed bead and mails an escalation
  about it, so a list answered for another repository would bind strangers' pull
  requests to this rig's beads one colliding number at a time. Rows whose URL does not
  name this checkout's repository are dropped and *counted* — a wholly foreign list
  reports nothing rather than a storm of false findings, and says so on stderr, because
  "0 anchorless" would otherwise read as a clean scan.
- **Restore visibility, not verdicts.** The phase confirms the PR exists and reads
  its base; it never merges, closes, or reopens. A PR already merged or closed gets
  its `merge_result` back so the observer can record or escalate it, but no gate is
  armed — arming one would dispatch a signoff for a PR nobody can merge. That
  decision is *persisted* (`merge_result_pr_state`), because the observer may not
  dispose of the restored bead before the next wake and a pass-local skip would
  forget by then. It is also **re-checked live** before it is honoured: a closed PR
  can be reopened, and a record trusted blindly would suppress a legitimate gate
  forever. That re-check **re-certifies the PR's identity**, exactly as the recovery
  did — it does not merely ask a number for its state. The recovery certified the PR
  on the pass that restored the bead, while the re-check runs on every later pass,
  where the repository `gh` resolves a number in is not guaranteed to be the same
  one; an uncertifiable probe is therefore treated like an unreadable one, so another
  repository's same-numbered PR can neither refresh the record nor drop the anchor
  into gating.
  The re-check is owed to the **same** pass too, not only to later ones. Reading the
  PR closed and skipping on that basis is one claim; leaving the anchor ungated after
  the same pass has already restored its `merge_result` is a stronger one, because
  the merge skill runs afterwards *within that pass* and reads an empty `check_set`
  as "declares no gates". A PR reopened in that window is open, visible and
  un-reviewed. So both arms — the one that recovered the anchor here and the one
  reading a persisted verdict — ask the same certified question, and an answer of
  `OPEN` falls through to normal gating rather than the inert skip.
  What an *unreadable* answer costs turns on the **exposure**, never on which pass
  created it. A recovered non-OPEN anchor whose live state cannot be certified and
  whose canonical `check_set` is **empty** holds the merge skill (`UNSAFE_RC`)
  whether this pass restored it or an earlier one did: it is equally visible and
  equally ungated either way, the recorded non-OPEN state is a *memory of a past
  read* rather than a gate, and the merge skill runs later in this same patrol pass
  in its own `gh` context — able, quite possibly, to read the PR this pass could not,
  and to read the empty `check_set` as "declares no gates". Keying that hold on
  provenance was the earlier rule, and it left a PR recorded closed three passes ago
  and reopened since as an open, visible, ungated anchor that any pass could land.
  A **gated** anchor is the deferral: a non-empty `check_set` holds the merge on its
  own unmet marker no matter what this pass could not read, so it warns and retries —
  which is what keeps one anchor's silence from stalling the whole rig's queue.

Pre-open anchors are deliberately **out of scope**: a branch with no PR is
indistinguishable from ordinary in-flight polecat work, so there is no
damage-surviving evidence to key on and the phase does not guess.

Unlike a `check_set` stamp that fails to persist, a failed `merge_result` repair
does **not** hold the merge pass. An ungated anchor is one the merge skill can see
and land un-reviewed; an invisible one it cannot land at all. The first is a
correctness hazard worth stopping the rig for, the second is the stall we already
had — so this phase warns, flags once, and retries. A *successful* repair inverts
that reasoning, which is the subtlety worth stating plainly: restoring
`merge_result` **exposes** the anchor to the merge skill, so from that instant the
usual "delay is safe" argument no longer applies to it. If the recovery lands and
the gating that was supposed to follow does not, this pass has created the very
ungated-merge window it exists to close. So a recovered open-PR anchor that is
still ungated when the pass ends holds the merge (`UNSAFE_RC`) exactly as a failed
`check_set` stamp does — including the case where the phase-1 enumeration comes
back *empty*, which after a recovery is a contradiction rather than a quiet
"nothing to do".

An enumeration that could not be **read** holds the merge on the same grounds, and
without waiting for a recovery to turn it into a contradiction. Those two are
*known* exposures; this one is an *unverifiable* one. The merge skill runs
immediately afterwards on the standing guarantee that this pass normalized every
visible anchor's `check_set` — empty is ungated *there* by design, and this is the
boundary that repairs it — so a pass that could not read the gating set cannot make
that guarantee about **any** anchor, including one that arrived hand-recovered and
empty since the last pass. It is also the shape that hides best: a partial read (one
`merge_result` state enumerated, the other unreadable) looks exactly like a complete
one, and the empty-enumeration guard never fires on it. Reading a failed ledger
query as an answer at all is the general form of that mistake, and it is not
specific to this scan — `gc bd list --json` reports its own failures as a non-empty
error *object* on stdout, and a query that dies after emitting announces that only
in its exit status, so both survive the "is it an array?" test that every guard here
used to rely on. Each ledger read is therefore taken through one helper that
requires a zero exit *and* an array payload, and every caller treats a refusal as
"I cannot tell" rather than as "there is nothing there".

The same inversion is why that enumeration is **unbounded**, and why each recovered
anchor's *reach* is verified rather than inferred. A cap was defensible while every
anchor enumerated was already visible: one past it was merely deferred to a later
pass. A recovered anchor is not — it is visible to the merge skill *now*, and the
only enumeration that will ever dispatch its signoff is the one in this pass, so a
page boundary leaves a live anchor with an armed gate nothing was dispatched to
raise. A non-empty `check_set` does not close that gap either: it proves the anchor
is *gated*, not that phase 1 ever saw it, and the two come apart on exactly the
shape the damage most often produces — an anchor that came back still carrying
`codex`. Dropped from the enumeration, it passes a gatedness-only check in silence.
So reach and gatedness are two questions: unreached *and* ungated is the
ungated-merge condition and holds the whole pass; unreached but gated is held by its
own armed gate, so it is reported and left to the next pass, which the durable
`merge_result_healed` marker carries it into.

That handoff is also why a recovered anchor keeps flowing through the
satisfiability check even when its `check_set` already reads normal. The damage
that dropped `merge_result` need not have dropped `check_set` too: an anchor can
come back carrying `codex` and no `check.codex` marker, which looks "already
normalized" while having nothing that can ever raise its gate. Treating
`merge_result_healed` as a reason to keep checking — alongside `check_set_healed` —
is what stops the repair from trading an invisible PR for a permanently stuck one.

**A signoff already in flight is a claim about reachability, and the heal checks
it.** The dispatch is skipped when a review for the anchor already exists — that
dedup is what stops one gate collecting two claimable reviews. But "exists" is
not "can be claimed": the route (`gc.routed_to`, plus the durable `review_pool`
copy a signoff restores it from) is written best-effort, and the read-back that
verifies it can itself come back unreadable, in which case the dispatch
deliberately leaves the review **open** rather than close a bead a polecat may
already hold. Believed on the next pass, that open-but-unreachable review covers
the gate forever: the anchor is held, no replacement is minted, and nothing
escalates because the dispatch counter already recorded a signoff. So the heal
**validates the route of the review it is about to reuse**, and repairs only what
is absent — re-offering an inert one through the pool its own durable copy names
(an operator's re-route is preserved), restoring a missing durable copy on a
claimed one, and never touching the live route of a bead somebody holds. What it
cannot verify it does not count: an unreadable review is neither reused nor
replaced, which leaves the merge held and the question open for the next pass.

The same recovery shape hid a second way: `su-uzy9.1` was assigned to
`shutupandlisten/refinery` while the canonical identity was
`shutupandlisten/gc-toolkit.refinery`, which hid it from find-work's *assignee*
filter at the same time the missing `merge_result` hid it from every bead-keyed
pass. A gating anchor whose assignee is not the canonical refinery identity is
therefore **flagged** (`assignee_noncanonical`, bounded to the offending value) and
never rewritten — the identity is a routing decision an operator owns.

## The closed anchor: when `closed` is a lie

The repair above enumerates **open** beads, so it inherits the assumption every
other pass makes — that the anchor still exists. An anchor that was **closed at
PR-creation** breaks it, and does so in a way that is worse than invisibility.
Under close-on-land, `closed` *means landed*. So such a bead is not only
unreachable by the merge skill, the pre-open resolver, the observer and the
`merge_result` recovery — all of which enumerate open beads — it is also a **false
durable record**: the ledger asserts the work shipped while its PR sits open.

signal-loom `sl-jcr4` was closed on 2026-08-05 carrying
`pr_url=.../pull/518` and no `merge_result`. PR#518 then sat open for four days
while satisfying every non-codex gate — head matching the anchor's
`gc.work_commit`, base `main`, `mergeStateStatus` CLEAN, all 11 checks SUCCESS,
APPROVED by an admin at the live head — with zero escalations. The anchorless scan
below did report it, but that scan is *detect-and-surface only*; a report is not a
repair, and nothing consumed it.

The repair (`check-set-heal.sh` phase 0a, ahead of the `merge_result` recovery in
the same script) keys on a signature narrow enough to leave every legitimate close
alone:

> `closed` **+** a PR reference **+** `merge_result` **absent** **+** that PR still
> **open**

`merge_result` is what separates the two: a genuinely landed anchor is closed with
`merge_result=merged`, and the observer's other dispositions record `abandoned` or
`retargeted`. A closed bead carrying **any** `merge_result` has a disposition
written by a pass that knew what it was doing, and is left alone — resurrecting an
anchor something deliberately retired is worse than one more pass of a stall.

**The repair is only to reopen.** A reopened bead is, by construction, exactly the
shape the `merge_result` recovery above already handles, so it is re-stamped,
gated, and given a signoff on the *same pass*, by code that is already reviewed and
tested. That is also why the reopen is deliberately the **first** write rather than
the last. Stamping `merge_result` first and reopening second would, on a dropped
second write, leave a *closed* bead carrying a `merge_result` — no longer a
candidate for either phase, and still invisible to every open-bead pass: a
permanent strand minted by the repair itself. Reopening first cannot do that; if
everything after it fails, the bead is an ordinary recovery candidate and the next
pass finishes the job. The exposure that ordering costs is nil, because an open
bead with no `merge_result` is invisible to the merge skill regardless.

**The closed set is bounded before it is touched.** Hundreds of beads per rig are
legitimately closed while carrying a `pr_url` — every anchor closed before
`merge_result` existed — so certifying each against `gh` on every idle pass would
be unaffordable. The cheapest discriminator is also the narrowest, so it runs
first: one `gh pr list --state open` names every PR that could possibly qualify,
and a closed bead whose PR is not in that set costs nothing further. On gc-toolkit
that takes 413 closed candidates to 14, and the child exclusions take those to 0.
An unreadable list fails **closed** — an empty result from a failed call is
indistinguishable from "nothing is open" while meaning the opposite.

Beyond the exclusions the recovery phase already applies (children by
`anchor_bead` / `task_kind` / `source_review_bead` / `source_anchor_bead` / a live
`gc.routed_to`, a non-refinery assignee, ambiguity, and full PR certification), two
guards are specific to reopening:

- **One anchor per PR, asked of live beads only.** A live bead carrying a
  `merge_result` for this PR *is* the anchor, so the closed bead is a spent
  predecessor and reopening it would mint a second anchor. The guard keys on a live
  `merge_result`, **not** on "any live bead names the PR": review and rework
  children name the PR and carry no `merge_result` by construction, and a live child
  over a *closed* anchor is the strongest evidence the close was a mistake — it
  exists to gate a bead that is no longer there. Refusing on those would decline to
  repair exactly the case that most needs it, and the reopened anchor is what the
  child was waiting for.
- **Reopen once, then escalate.** The reopen stamps `reopened_not_landed`. A bead
  that carries it and is closed *again* was re-closed by a live writer, so reopening
  it a second time would flap the bead against that writer every idle pass. It is
  reported for an operator instead. The marker is written and read back *before* the
  status flip, because without a durable marker a later re-close cannot be told from
  a first repair.

**What closed it.** Worth separating the repair from its cause. The live mr path
does not close at PR-creation — all four rigs symlink gc-toolkit's
`mol-refinery-patrol.toml`, which is close-on-land — and the stock GasTown formula
that *does* (`gc bd close $WORK --reason "Pull request ready: $PR_URL"`, preserved
in `doctor/check-base-artifact-collision/base-snapshots/`) stamps
`merge_result=pull_request` in the same chained command, so it cannot produce this
shape either. `sl-jcr4`'s history shows the ordinary work-bead done-gate instead:
one update stamping `gc.work_outcome=shipped` + `gc.work_commit`, then a close 0.65s
later, with `merge_result` never written. That is an agent running the normal "I
shipped it" sequence on a bead that was an mr anchor with a live PR — a class of
writer rather than a single code path, which is why the heal arm is the durable
remedy rather than a fix at one call site.

## Anchorless PRs: reconciling from the other side

Every automated path in close-on-land starts from the **bead**: the merge skill,
the merge observer, and the refinery patrol all enumerate gating anchors and read
the PR each one names. That is sound while the bead outlives the PR — which the
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
PR number any *live* bead references, and report the remainder. Three rules keep
it honest:

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
- **Tracked is not owned.** A live bead naming a PR is enough to prove the PR is
  not *anchorless*, but not enough to prove anything will land it. A bead
  carrying none of `merge_result`, `merge_strategy`, `branch` or `target` tracks
  its PR without owning it, and is reported on a separate **unowned** line —
  never escalated (the bead is live, so this is a routing gap an operator can
  close, not a stranded PR) and never folded into the silence reserved for PRs an
  automated path is actually driving. Collapsing the two would make the scan
  quieter without making it truer.

**"PR number" means every key that names one.** `pr_number` is what the refinery
stamps, but it is not the only key in use: the fork-sync flow records `fork_pr` /
`fork_pr_url` and no `pr_number` at all. Every PR-keyed lookup — the tracked set,
the in-flight rework probes, the closed-bead resolution, **and the merge skill's
read of an anchor's own identity** — reads the same widened key set, so a bead
visible to one is visible to all of them. Widening a single lookup is worse than
widening none: it flips such a PR from *anchorless* to tracked-but-unprobeable,
which reads as resolved while the in-flight probes still cannot see the bead
holding the branch. The merge skill's half of that is the sharpest case — while
it read `pr_number` alone, a live `merge_result=pull_request` anchor keyed only
by `fork_pr` was skipped as "names no PR" every pass, and the observer counted it
*owned* and stayed silent: a PR nothing lands and nothing reports. An anchor
whose keys name *several different* numbers is held instead, never guessed:
picking one means picking a pull request, and a wrong pick lands the wrong work.

**And a number is not an identity.** Every key above holds a pull *number*, which
is unique only within a repository, while the PRs it is matched against come from a
`gh pr list` pinned to this checkout's origin — so matching on the number alone
compares this repository's pull requests against every repository's beads. Both
directions break, in opposite ways: a foreign *live* bead naming `#n` puts this
repo's open `#n` into the tracked set and its genuinely anchorless state is never
reported, while a foreign *closed* bead naming `#n` resolves as the dead anchor of
ours — receiving the `anchorless_flagged` stamp, being named in the escalation, and
bounding that escalation for a PR it never owned. So each reference carries the
repository its key names, host-qualified: `pr_number` is placed by the bead's own
`pr_url`, `fork_pr` by its `fork_pr_url`, and a `fork_pr_url` reference by itself.
A key that names no URL at all — the `pr_number`-only shape almost every legacy
bead and every freshly recovered anchor wears — is the `?` wildcard and matches any
repository, the same fail-closed convention the recovery phase's incumbent guards
use: qualification only ever rules out a *positive, parsed* disagreement, so it
never turns today's silence into a new finding and never widens what may be
written. The merge skill's own hold guards (duplicate-anchor, open-child) are keyed
the same way and for the same reason, though they fail toward *holding* rather than
merging: there, an unqualified number means a stranger's same-numbered bead can
hold a ready PR indefinitely, with nothing an operator can repair in this
repository to release it.

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
