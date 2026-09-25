---
name: WIP viewing and review — the WIP/ready state model
description: Proposal for tk-6bji7k.1. How a bead-driven workflow views and reviews work in progress before it is a finished, approval-gated change. One status dimension — the workflow-owned status label — carries who must act next; the draft flag is a CI-cost lever rather than a second signal; a pull request opens at the checkpoint where a person is needed and there is something tangible to review; and a checkpoint's pull request lands on the owning convoy's integration branch rather than on main, so its approval mints a phase and main moves only at graduation. Rules out building review into Helm and switching off GitHub.
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
a checkpoint lands" gives the mechanism. At step 2 the person is asked to look
and steer, not to approve a merge to `main`. Two things have to hold for that:
the machine must not read an early look as a merge approval, and a person must
not be asked to look before the work is ready for them.

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
What the label does not carry is what a review verdict then authorizes, and that
does differ between a spec at step 2 and a finished change at step 5. The
subsection "A checkpoint approval is not a merge to main" below draws that line.

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

### A checkpoint approval is not a merge to main

The label says who must look; it does not say what their verdict authorizes, and
that differs between a checkpoint and the graduation. `needs-review` shows at
both: on a child pull request presenting a spec for feedback, and on the
graduation pull request presenting the finished unit for merge to `main`. The
label reads the same; the verdicts do not.

What keeps them apart is the pull request's base, not a rule against approving
mid-journey. A child pull request's base is `integration/<convoy-id>`, so
approving it mints that phase into integration and moves nothing on `main`; the
graduation pull request's base is `main`, so approving it authorizes the merge
that ships the unit. A GitHub **Approve** keeps one meaning throughout —
authorize the merge into this pull request's base — and the base is the thing the
operator must be able to read, which is why an integration-targeted pull request
is labelled and bannered as a checkpoint (the section "Where a checkpoint lands"
below). The label is unchanged by any of this: it still says only who must look.

The merge preconditions stay a last-line backstop, not the mechanism. A merge to
`main` needs more than an approval — the city must have reached its terminal step
with gates green and no hold, and `assets/scripts/merge.sh` skips a draft — so a
stray approval on the wrong base cannot ship work by itself. The design does not
lean on that: the base carries the meaning. And a merge-authorizing approval
still has to survive the commits that follow it, which is the commit-scoping the
section "Sign-off scoped to a commit, reset by materiality" leaves open.

## The draft flag is a CI-cost lever, not a signal

GitHub's draft boolean carries no WIP meaning here. The code reads it only to
skip a draft PR in the merge arm and the posture read (`assets/scripts/merge.sh`,
`assets/scripts/pr-facts.sh`), and the status-label projection sits above that
skip on purpose, so it covers a draft PR as much as an open one
(`assets/scripts/pr-facts.sh`, the label projection above the draft gate).

What draft is good for is cost. GitHub Actions fire on a draft's pushes unless a
workflow opts out, and `.github/workflows/tests.yml` triggers on every
`pull_request` to `main` with no draft filter, so a PR opened early and still
taking follow-up commits would run the full suite on each push. Gating the jobs
on `github.event.pull_request.draft == false` and adding `ready_for_review` to
the trigger types makes a draft cost no Actions minutes until it is marked ready.
That is the entire role of draft in this design: a CI-cost optimization for a PR
opened early and still churning, orthogonal to the status label that says who
must act.

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

This is what makes an early approval safe rather than something to forbid. A
child pull request authorizes exactly one merge, into `integration/<convoy-id>`,
so an operator steering a spec at a checkpoint mints that phase with no risk to
`main`. The distinction the operator reads is the base, so an integration-targeted
pull request has to be unmistakable. Two surfaces carry that, both set at pr-open
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
(`assets/scripts/pr-open.sh`). The WIP model opens a PR earlier than the current
flow does, before the work is ready to merge, so the requirement is that this
early checkpoint route through that same pre-open gate rather than around it. The
boundary is internal; the operator sees only that what is waiting on them has
already cleared it. The work here is to hold the early checkpoint to the checks
every current flow already runs, not to invent a new precondition.

**Sign-off scoped to a commit, reset by materiality.** This is the real open
decision. Both review axes carry a verdict across the commits appended after it,
and a routine push drops neither; they differ only in how each reacts to a
rewrite that replaces the reviewed commit:

- A **human** approval is recorded against the commit it was given on, and it
  stands across the commits that follow. GitHub drops a standing approval only
  when the repository turns on "dismiss stale approvals when new commits are
  pushed." That setting is off here and stays off: it keys on the SHA, not on
  whether the diff changed, so it would drop an approval on a content-neutral
  rebase and make even a routine post-approval rebase far harder than it earns. A
  changes-requested review is never auto-dismissed by a push either; the city
  reworks that veto but never dismisses it (`services/helm/README.md`), and the
  one dismissal the city does make is of its own superseded machine review, with
  a human approval always left external (`assets/scripts/signoff.sh`,
  `dismiss_superseded`). So a human verdict, once given, persists across new
  commits on its own.
- A **city gate** lane is commit-agnostic. `green` names no commit, a push does
  not stale it (`docs/state-machine.md`, "Green survives new commits"), and the
  `reviewed_oid` pin guards only against a rewrite that removes the reviewed
  commit — an amend, rebase, or force-push answers `gone` and refuses a fresh
  verdict, while commits appended on top keep the pin and the lane green
  (`docs/state-machine.md`, "Gates"). The reason is cost: the cadence re-derives
  every few minutes, and re-gating on every appended commit would never converge.

A WIP review loop, where a reviewer comments and the author pushes fixups in
reply, has to say when a standing approval no longer covers the live head.
Because the approval persists on its own, the risk to guard is the opposite of an
over-eager reset: a material rewrite shipping under a sign-off that was given for
an earlier diff. Treating every new commit as stale guards against that but is
too blunt, since it re-reviews a pure rebase and every trivial fixup. The rule to
run is materiality: a human sign-off stands across commits that do not change the
reviewed diff in substance, and a re-review is owed only when the change since
sign-off is material. Judging that materiality is the piece to build. An agent
evaluates the diff since the approved commit and decides whether it warrants
another human pass, while machine lanes keep the commit-agnostic rule so the
cadence still converges.

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
