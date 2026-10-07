---
name: WIP viewing and review — the WIP/ready state model
description: Proposal for tk-6bji7k.1. How a bead-driven workflow lets a person view and review work in progress on GitHub. Two things carry the model: one workflow-owned status label says who must act next, and the pull request's base says where an approved change lands. An approval means the same thing everywhere — merge what is presented into this pull request's base — so the only variable is the base: `main`, a convoy's integration branch, or a direct commit with no pull request. The operator must be able to read that base. A pull request opens at the checkpoint where a person is needed and there is something tangible to review. Rules out building review into Helm and switching off GitHub.
---

# WIP viewing and review

The question is how a bead-driven workflow lets a person view and review work
while it is still in progress — before it is a finished change asking for a
merge approval — and how the workflow's own state says who must act on it next.
That is a state-model question, not a tooling-shortcut question. A branch link
on a board row would help someone find the work; it would not say whether the
work is theirs to weigh in on or the city's to keep building.

## The workflow this serves

The design has to fit the shape a design or coding change actually takes:

1. The city designs a change and writes it up — a spec, sometimes with
   mock-ups — on a branch.
2. A person views the spec and mock-ups on GitHub, reading files in the browser
   and commenting on the lines that need it. Inline, file-anchored commentary is
   the reason a pull request beats a bare branch at this step.
3. The person leaves feedback so the work can continue.
4. The city carries the change forward — to a final review, or through another
   feedback cycle.
5. The person approves, and the city merges.

The arc lands on `main` as one change, but its reviewed phases do not each land
there. A phase that needs a checkpoint lands on the owning convoy's integration
branch, and `main` moves only when the whole unit graduates — the section "Where
a checkpoint lands" gives the mechanism. At step 2 the person reviews the
checkpoint; approving it merges that phase into the convoy's integration branch,
not into `main`. Two things have to hold for that: the operator must be able to
read which base a pull request targets, so a checkpoint into integration is never
taken for a merge to `main`, and a person must not be asked to look before the
work is ready for them.

## One status dimension: who must act next

The workflow already computes, every cadence pass, the one thing a person
scanning for their work needs — who must act on each anchor next — and projects
it onto GitHub's pull request list as a single workflow-owned label from a
mutually-exclusive `status:` group (`docs/state-machine.md`, "The status label";
`assets/scripts/pr-status-label.sh`):

- **`status: working`** — the city holds the ball: a rework child stands on the
  reviewed commit, or an approved PR is merging. No one should look.
- **`status: needs-review`** — settled at the current head with no open rework:
  a person should review or re-review this commit now.
- **`status: needs-attention`** — the city stopped without settling: a hold
  stands, or an approved PR is wedged with no work in flight. The ask is
  "unstick us", not "review the diff".

Precedence when inputs overlap is `needs-attention` > `working` >
`needs-review`. That single dimension is the WIP/ready state model. It answers
the operator's question directly — is this mine to act on right now — and it
answers it the same way whether the change is a spec at step 2 or a finished
implementation at step 5. `working` means don't look; `needs-review` means look;
`needs-attention` means look, where the ask is to unblock rather than to review.
What the label does not carry is where an approved change then lands. That is set
by the pull request's base, not by which checkpoint the approval is given at — an
approval means the same thing at a spec checkpoint and at the finished change.
The subsection "An approval authorizes a merge into the base" below covers it.

The label stays honest across a review round because it reads the city's own
computed state — the posture and merge state the refinery stamps on the anchor,
its holds, and its rework children — and not GitHub's review posture directly or
a lane's `green` marker. The `working` → `needs-review` flip rests on the rework
child, which is filed against the reviewed commit and closes when the fix lands,
so GitHub's sticky `CHANGES_REQUESTED` never traps the label in `working` after a
hand-back, and a `green` lane that outlives a rewritten commit
(`docs/state-machine.md`, "Green survives new commits") cannot read the label
settled (`specs/tk-6bji7k.3/decision.md`).

This is the whole WIP/ready signal a person reads on GitHub. There is not a
second one. The internal machine axis `pr.machine` (`docs/state-machine.md`,
"The machine axis") is the city's own bookkeeping that feeds the label; it is not
separately projected onto GitHub, and the draft flag carries no state of its own.

### An approval authorizes a merge into the base

An approval means one thing wherever it is given: what is presented here is
approved, so merge it into this pull request's base. A GitHub **Approve** on a
checkpoint and one on the graduation carry the identical verdict. The only thing
that differs is the base the approved change lands on, and that is a fact about
the pull request, not a second meaning the person has to hold.

A checkpoint's base is `integration/<convoy-id>`, so approving it merges that
phase into integration and `main` does not move; the graduation's base is `main`,
so approving it ships the unit. Same verdict, different base. That is what makes
this model simpler than one where the same click has to mean different things at
different points.

Because the base carries the whole distinction, the operator has to be able to
read it. An integration-targeted pull request is marked as a checkpoint on the
pull request list and states its base in a standing body banner — that it merges
into `integration/<convoy-id>`, and that the broader review runs at graduation
(the section "Where a checkpoint lands" below; tk-6bji7k.9). The status label is
orthogonal to this and unchanged: it still says only who must act next.

Both bases are gated the same way. A merge into either needs its declared lanes
green, every open review comment addressed, and — where its `check_set` calls for
one — an approval; nothing merges ungated (`assets/scripts/merge.sh`). The
branch-protection rules a base carries can differ, so the gates themselves may
differ, but integration is not the loose base to `main`'s strict one. The base
names which line of work the approved change joins; it does not lower the bar.

## Draft is not part of this model

GitHub's draft boolean carries no state in this design. The status label is the
only WIP signal a person reads, and it covers a draft pull request exactly as it
covers an open one (`assets/scripts/pr-facts.sh`, the label projection above the
draft gate); the code otherwise reads draft only to skip a draft in the merge arm
and the posture read (`assets/scripts/merge.sh`, `assets/scripts/pr-facts.sh`).

One later use is worth naming but not pursued here. Because GitHub Actions fire on
a draft's pushes unless a workflow opts out, gating CI jobs on `draft == false`
could save Actions minutes on a pull request still taking follow-up commits. That
is speculative and general — a candidate optimization, not doctrine this proposal
rests on — and it is tk-6bji7k.5's, which would also verify draft-CI gating per
rig before anything relied on it.

## When the pull request opens

A pull request opens at the checkpoint where a person is needed and there is
something tangible for them to engage with. The trigger is need, not phase. The
tangible unit varies — a spec on its own, a spec with an implementation, a spec
with several designs or mock-ups — and it is the need for a person's eyes on
something concrete that opens the PR, not arrival at any particular workflow
stage. Until that checkpoint the board holds the work and the pushed branch is
the artifact surface; no pull request exists.

Not every engagement opens a pull request. An engagement with nothing tangible
to mark up — a direction to settle, a question with no diff behind it — routes as
a converse visit instead. Where the line falls between a converse visit and a PR
checkpoint is left to experience rather than drawn here; the principle is that a
PR is for engaging on something a person can read and comment on line by line.

Opening at the checkpoint, rather than at the first commit, is the ruling for
now, and the conservatism is operational rather than doctrinal. Opening a pull
request per branch as soon as it exists would put many PRs in flight at once, and
it is not verified that every rig disables full CI on draft PRs, so opening early
across rigs could spend Actions minutes on runs that should not happen. Moving
the checkpoint earlier is a reasonable later change; it carries one precondition —
verify draft-CI gating in each rig it would apply to first.

## Where a checkpoint lands: an integration branch

The checkpoint-open rule above decides when a pull request opens; the convoy that
owns the work decides where it lands, and it is not `main`. The convoy carries an
integration branch, `integration/<convoy-id>`, cut from `main` and empty at
first. Each phase that needs a reviewed checkpoint — a design, a spec, an
implementation — opens a child pull request into that integration branch and
carries its own review. Approving a child pull request merges its phase into
integration and mints it, and `main` does not move. When the unit is ready, a
graduation pull request carries the integration branch to `main` under the
broader final review, and the phase-approval trail rides with it.

A child pull request authorizes exactly one merge, into `integration/<convoy-id>`,
so approving a spec at a checkpoint mints that phase and `main` does not move. The
distinction the operator reads is the base, so an integration-targeted pull
request has to be unmistakable. Two surfaces carry that, both set at pr-open
time where the base branch is known: a workflow-owned label so the pull request
list marks the PR as a checkpoint into integration, and a standing body banner
stating that it merges into `integration/<convoy-id>`, that its approval mints a
phase, and that the broader review runs at graduation (tk-6bji7k.9). The board
already records the merge target.

Phase branches are disposable once merged. The next phase pours from the updated
integration branch, never from a prior phase branch, so squashing a phase and
letting its branch be deleted costs nothing. A child pull request replaces a bare
seed commit only where a phase needs a reviewed mint; a bare commit with no pull
request is still the right surface for scaffolding no one has to approve.

The mechanism is the existing owned convoy, not a new pipeline: `gc sling`'s
convoy-ancestor walk already resolves an owned member's target to
`integration/<convoy-id>` and the refinery lands work there. GitHub's native
stacked pull requests remain a watch item, to revisit at general availability or
if convoy practice shows friction; this design does not build a stack pipeline.

## The surface is GitHub

A person reviews on GitHub, and the two alternatives are ruled out on evidence.

**Build a review UI into Helm.** Rendering a diff is cheap; several maintained
libraries do it. The comment model is not: no diff-viewer library ships comment
persistence or the hard part, re-anchoring a comment as the branch under it
changes, and every serious code-review tool built that as a dedicated subsystem.
A credible first version is six to ten engineer-weeks, and GitHub-grade
re-anchoring is open-ended beyond that. This spends the effort on review plumbing
rather than on the state model, and it is ruled out.

**Move review off GitHub to a self-hostable platform.** Only two open platforms
solve comment re-anchoring: Phorge/Differential carries inline comments forward
as "ghosts," and Gerrit carries them across patchsets under one Change. Both mean
running a second, heavier git-hosting stack — Phorge a PHP, MySQL, and daemon
deployment maintained by a volunteer fork of an abandoned product; Gerrit a
Change-Id workflow that fights how agents commit. GitLab CE, Gitea, and Forgejo
share GitHub's weakness of marking a comment outdated on force-push, and Gitea
and Forgejo are worse: their git garbage collection can prune the
force-pushed-away commits entirely, 404-ing the compare link. Switching hosting
to gain one feature costs the whole operational surface, and it is ruled out.

Coding-agent systems converge on the same answer: the terminal review artifact is
a git branch and a GitHub pull request, and the product work is around the PR — a
triage inbox, a live process log — not a replacement for it.

## The parts still to design

Three pieces of the model still need work.

**The early checkpoint runs the pre-open checks every flow already runs.** A
person is never the first eyes on unchecked work today, and that is enforced now,
not a thing to build. A polecat runs its own `self-review` and pre-flight before
the handoff, and the refinery holds the anchor at `pre_open_gate` until every
lane its `check_set` declares is green before any PR opens
(`assets/scripts/pr-open.sh`). A checkpoint pull request is ready for its base
when it opens — it is not a merge-ready change opened early — so the requirement
is only that it route through that same pre-open gate rather than around it. The
boundary is internal; the operator sees only that what is waiting on them has
already cleared it. The work here is to hold the checkpoint to the checks every
current flow already runs, not to invent a new precondition.

**A standing approval and the live head.** A review loop where a person comments
and the author pushes fixups in reply has to say when an approval given on an
earlier commit no longer covers the head that follows it. This is a property of
the generic review loop, not something the integration-branch model changes: an
approval on a checkpoint and one on the graduation age against later commits the
same way, so the rule here is the rule everywhere.

Treating every new commit as stale is too blunt — it re-reviews a pure rebase and
every trivial fixup — so the rule is materiality: a human sign-off stands across
commits that do not change the reviewed diff in substance, and a re-review is
owed only when the change since sign-off is material. Judging that materiality,
with a fixup-then-squash discipline that keeps comments anchored within a round,
is tk-6bji7k.6's to build. The related hand-back hygiene — clearing a stale
`CHANGES_REQUESTED` once every thread is confidently addressed, so the label is
not trapped by GitHub's sticky verdict — is tk-6bji7k.4's.

**A visible process artifact and two-way links.** The artifact should tell a
person one thing: whether the change is theirs to act on right now. The status
label already carries exactly that on the PR list, so an operator-facing phase
indicator beside the diff should read the same three-value taxonomy rather than
invent a second vocabulary. The links should run both ways. The board renders a
pre-PR branch as bare text today, holding no repo slug and linking nothing
(`services/helm/internal/board/derive.go`, `services/helm/web/src/App.tsx`), so
the branch a person wants to browse is undiscoverable without opening the
dashboard. Turning that branch string into a GitHub link, and carrying a link the
other way from the PR back to the board — with action links that take the
operator straight to a board move, such as opening a visit to discuss the PR —
closes the gap. Which URLs those are is the open detail, since they have to
resolve to real board actions and not just to the board.

## Relation to the epic's other beads

The status-label spine this model rests on is landed
(`specs/tk-6bji7k.3/decision.md`), from research on the now-closed tk-6ttx19, and
the stale-PR-body problem a PR iterating in place would otherwise hit (tk-t1130i)
is closed too. The open siblings are where this model still touches:

- **tk-jvhkjy** — whether agents read annotated bead-and-PR state from a script
  or the bead carries every gate directly. That is the read model behind the
  label and the machine axis.
- **tk-7h5l3m** — the `codex` gate is opaque and coupled to `pr-open.sh`. The
  self-checked precondition and the phase indicator build on the gate model, so
  they should agree on how a gate is named and read.
- **tk-j5wrs** — an anchor's in-flight set has no canonical definition. A WIP
  state added here respects one membership test rather than adding another.

## The builds that follow

Each is filed as a sibling under the epic:

- **tk-6bji7k.5** — the draft flag as a CI-cost optimization: the `tests.yml`
  gate on `draft == false` plus `ready_for_review`.
- **tk-6bji7k.6** — the materiality reset in the review path, plus a
  fixup-then-squash convention for review rounds so comments stay anchored within
  a round and history is rewritten only between rounds.
- **tk-6bji7k.7** — bidirectional board-and-PR links and the operator-facing
  phase indicator, the discoverability slice.
- **tk-6bji7k.4** — review-dismissal hygiene at hand-back, so a stale
  `CHANGES_REQUESTED` is cleared once every thread is confidently addressed.
- **tk-6bji7k.9** — the integration-targeted pull request identification surfaces:
  a workflow-owned label on the pull request list and a standing body banner, both
  set at pr-open time, so a checkpoint into integration is never mistaken for a
  merge to `main`.
