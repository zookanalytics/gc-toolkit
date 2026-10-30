---
name: Design-convoy pattern
description: The executable integration-effort pattern converse reaches by recommendation. mol-design-convoy makes its subject the effort's landing bead, cuts the subject's integration branch, files a design child, arms implementation behind the design's approval, and files the summary task that writes the subject's PR summary, so design and implementation reach the default branch as one reviewed PR. Covers the molecule, the branch cut, the two operator gates under the universal approval rule, and the design-gated default.
---

# Design-convoy pattern

A design-convoy is an integration effort whose first bead settles a design on the
effort's branch and whose implementation is armed behind that design's approval,
so the whole unit reaches the default branch as one reviewed PR. A molecule
converse recommends and the operator Accepts stands it up: it cuts the
integration branch, files the design child, the implementation child and the
summary task, and only once every wait among them reads back hands the subject
to the refinery and dispatches the work, with no human running git. No convoy
carries a design-convoy's branch: the branch is its subject's own.

## Scope

**Mandate.** How a design-convoy runs: the molecule that stands one up, the
branch cut it performs, the operator gates the unit passes through on its way to
the default branch, and the choice between design-gated and all-in-one.

**Boundaries.** Which work a design-convoy fits is stated in its formula's own
description (`formulas/mol-design-convoy.toml`), which the `work` skill's
formula choice reads. How any integration effort is stood up, and how its beads
branch and land, is the mechanik's dispatch doctrine
(`agents/mechanik/prompt.template.md`). How a summary task writes its PR summary
is the polecat doctrine's (`template-fragments/polecat-doctrine.template.md`).
The merge rule the gates apply is `gctk merge`'s, which `assets/scripts/merge.sh`
runs; this page says how the pattern meets that rule and does not define it.

## Why a molecule stands it up

An integration effort's beads land on its integration branch, and its landing
bead carries the branch to the default branch through one PR. Each bead names
the branch as its own `metadata.target`, written in the create that filed it, so
`gc sling` branches it from there and the refinery lands its work there. A bead
of the effort lands with no PR of its own unless it is a stage, slung
`--merge mr`, whose PR goes into the branch.

Cutting the branch is the one step a converse sitting cannot perform, because a
sitting never pushes. Everything downstream expects the integration branch to
already exist: a polecat branches from `origin/<target>`, the refinery brings a
branch current by merging `origin/<target>` into it, and pre-open review diffs
against the anchor's target. None of them creates it. So the branch cut is the
piece the pattern supplies, performed by a pool worker that has push rights.

## mol-design-convoy — the molecule

`formulas/mol-design-convoy.toml` is a dispatch molecule: slung `--on` a single
subject (the initiative), it reads the input convoy's one tracked member,
orchestrates, and drains. It writes no code and needs no worktree of its own.
The subject is the effort's landing bead. Its steps:

| Step | What it does |
|---|---|
| `load-context` | Read the subject and its recommendation card for the design topic and intended implementation. Resolve `design_gated` (var, default `true`). |
| `seed-branch` | Cut `integration/<subject-id>` from the default branch with one create-only push from the rig's checkout, and record it on the subject: `branch` names the integration branch and `target` the default branch, read back. |
| `file-design` | File the design child with the integration branch as its `target` in its create, under the subject's epic when it has one, make the subject wait on it by a `blocks` edge, and read both back. |
| `file-implementation` | File one implementation child the same way, which builds the initiative per the design and lands with no PR of its own. `design_gated=true`: also hold it behind the design child by a `blocks` edge, read back. |
| `file-summary` | File the summary task beside the subject, under the subject's epic when it has one, with no `target`. It waits on each child by a `blocks` edge, and the subject waits on it. The three edges are read back. |
| `dispatch` | Read every target and edge of the setup back. Then hand the subject to the refinery, assigned with the notice that assignment owes, and dispatch the work: sling the design child, `--merge mr` when design-gated; arm the implementation child behind the design (`design_gated=true`) or sling it now, in parallel (`design_gated=false`); and arm the summary task to the polecat pool on `mol-polecat-report`. Then close the step chain and drain. |

Nothing is handed over or dispatched until the whole setup reads back. The
filing steps dispatch nothing, so a run that stops between them leaves no child
in flight and the subject with nobody, and no child can land while the subject
waits on fewer than all of them. That includes the all-in-one implementation,
which starts only once the summary task it must give its split beads to is
filed and waited on.

Every step re-derives the subject from the input convoy in its own shell and
records its result on the subject (`branch` and `target`, `gc.design_child`,
`gc.impl_child`, `gc.summary_task`, and the `*_armed` markers), so a crashed run
resumes without cutting a second branch or filing a second child, task or
workflow. The dispatch step stamps each `*_armed` marker right after its own
dispatch, so a resume dispatches nothing twice. A target or an edge that does
not read back fails its step, so the resume re-runs that step. The read-back
decides, not the add's exit status, because a resumed add can meet an edge the
failed pass already wrote.

The implementation is one child, not a fan-out: the design defines the
breakdown, so the child carries "split into multiple beads if the design
calls for it" and splits itself when it runs. Enumerating pieces here
would guess at a breakdown the design has not settled yet. Its brief says that
each bead it splits into is filed the way it was, and waited on by the summary
task as well, so the subject and the summary task wait for every piece.

### The branch cut

`seed-branch` fetches origin and pushes `refs/remotes/origin/<default>` to
`refs/heads/integration/<subject-id>` with an empty lease
(`--force-with-lease=refs/heads/integration/<subject-id>:`). The default branch
is the one `origin/HEAD` names, or `main` when it names none. The mechanik's
recipe for standing an effort up by hand cuts with the same marked blocks, so
an effort cut either way starts from, and lands on, the same branch. The push
sends a ref and checks nothing out, so the rig's checkout never moves.
Reconcile keeps that checkout fast-forwarded to the default branch and
directory-imported packs build from its working tree, so a branch checkout or
commit there would park the deploy off the default branch.
The empty lease refuses a branch that already exists, so a refused push after
which origin carries the branch is a cut an earlier pass already made. A subject
that records the branch already is not cut again. One that records another
branch, or lands on a branch other than the default, is not cut, because an
effort that lands inside another effort's branch is not built.

The branch starts equal to the default branch, and the design child lands the
first commit.

## The two operator gates

Every PR a design-convoy produces merges only with a standing APPROVED review
from an account other than the city's. The approval counts at whatever commit
it was given and stands across later pushes until someone dismisses it, so a
push to an approved PR does not wait for a second approval. A standing
CHANGES_REQUESTED from any other account vetoes the merge. `merge.sh` enforces
this as a universal merge rule: it is armed for every PR and named by no
`check_set` token (`gctk merge`, which `assets/scripts/merge.sh` execs), and
GitHub branch protection is an extra layer, not the authority. The design
child's PR into the integration branch, when the design is gated, and the
subject's PR into the default branch both pass through it. The pattern's two
gates are the two approvals that decide what moves next.

The rule is the default branch's `gctk merge`, the binary the `gctk-build`
order builds from the deployed pack the refinery runs, and it gates PRs onto an
integration branch as well. An integration branch's own copy of `services/gctk`
can predate the rule. The refinery never runs a build of that copy, and an
effort that changes nothing under `services/gctk` leaves the default branch's
version in place when its PR merges.

**Gate 1, the design checkpoint** (design-gated only). The design child is a
stage: its doc lands on the integration branch through its own PR into that
branch, and the universal rule holds that PR until the operator approves it. The
implementation child is held behind the design child by a `blocks` edge, and a
deferred dispatch sends it to the pool when the design child closes. The design
child closes only when its PR merges, so the operator's approval of the design
is what releases implementation, which then lands on the branch with no PR of
its own.

**Gate 2, the subject's PR.** The subject waits on each child and on the summary
task by `blocks` edges, and the `dispatch` step assigned it to the refinery. The
summary task is dispatched once both children have landed, and writes the
subject's `pr_summary` from the finished branch: what the whole branch does,
and where the finished work departs from the subject's description. Once it
closes, nothing the subject waits on is open. The refinery takes the subject and
brings its branch current with the default branch, and the merge cadence opens
the PR from the integration branch into the default branch, with the summary
task's account as its `## Summary`. The same universal rule holds that PR until
an operator's approval stands on it, so the operator reviews the whole unit,
design and implementation together, before the default branch moves.

## When the subject closes

The subject is the owning bead of the effort's PR, so it closes when that PR
merges, as any PR's owning bead does. Work that waits on the subject through a
`blocks` edge starts once the subject closes.

## Design-gated versus all-in-one

`design_gated` is a var, default `true`. The operator settles it per initiative
when acting on the recommendation. The board's Accept passes no var, so an
Accept from the board takes the design-gated default, except when it finishes
an acceptance a sitting's sign-off left unfinished: that sling carries the var
the acceptance recorded on the recommendation's gate. For all-in-one, the
operator takes the recommendation to a sitting (Discuss) instead, and the
sitting's sign-off takes it with `--accept --var design_gated=false`. The
sign-off hands the var to Accept's writer, which answers the gate that put the
recommendation to the operator, slings the formula with the var under the
bead's acceptance lock, and records the dispatch (the `work` skill). The var is
read case-insensitively: `false`, `0`, `no`, or `off` selects all-in-one, and
`true`, `1`, `yes`, or `on` selects design-gated. An empty or unrecognized
value also selects design-gated, with a warning, so a typo never drops the
design gate.

- **Design-gated** (`true`): implementation waits behind gate 1, so it starts
  only after the operator approves the design. Use it when the design decision
  genuinely gates the implementation shape, the blast radius is high, or the
  design is uncertain. The cost is the design round-trip before implementation
  starts.
- **All-in-one** (`false`): design and implementation dispatch together and land
  on the integration branch in parallel, with no PR of their own. The subject's
  PR is the one PR, where the operator first sees both. Use it when the shape is
  already agreed and the design doc is mostly a record, or the implementation is
  small enough to redo cheaply. The cost is implementation built on a design the
  operator may later change.

The default is design-gated because a design doc is cheaper to change than built
implementation.

## How converse reaches it

The recommend-to-Accept-to-sling path carries the pattern with no special
handling. The recommendation is `gc.recommended_formula = mol-design-convoy` on
the subject, and the board offers Accept while that key is non-empty. Accept
(`gc-helm.sh accept`) runs
`gc sling --rig <the subject's rig> <subject> --on mol-design-convoy`. The
`--rig` pin resolves the subject in its own rig's store, whatever directory the
sling runs from. The sling carries no `issue` var, because graph.v2 reserves
`issue`, `convoy_id` and `bead_id`.

Accept's sling creates an input convoy whose one tracked member is the subject,
which the formula reads as `{{convoy_id}}`. That convoy is only this pour's
handle on the subject, and it carries nothing the effort's beads read.
