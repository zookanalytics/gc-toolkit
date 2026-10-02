---
name: Design-convoy pattern
description: The executable owned-convoy pattern converse reaches by recommendation. mol-design-convoy stands up an owned integration convoy, cuts its branch, files a design child, and arms implementation behind the design's approval, so design and implementation graduate to the default branch as one reviewed unit. Covers the molecule, the seed script, the two operator gates, the design-gated default, and the when-to-recommend rubric.
---

# Design-convoy pattern

A design-convoy is an owned convoy whose first child settles a design on an
integration branch and whose implementation is armed behind that design's
approval, so the whole unit graduates to the default branch as one reviewed PR.
A molecule converse recommends and the operator Accepts stands the convoy up:
it creates the convoy, cuts the integration branch, files the design child, and
arms implementation, with no human running git.

## Why a molecule stands it up

The default PR unit is an owned convoy on an integration branch
(`agents/mechanik/prompt.template.md`). Children inherit
`metadata.target = integration/<convoy-id>` through `gc sling`'s convoy-ancestor
walk; the refinery lands them on that branch; the cadence then graduates the
convoy to the default branch as one human-approved PR (`convoy-graduate.sh`).

Creating the convoy is the one step a converse sitting cannot perform. `gc convoy
create --owned` records metadata but never touches git, and a sitting never
pushes. Everything downstream expects the integration branch to already exist:
the submit gate resolves `metadata.target` and fails closed with no branch, the
refinery brings a branch current by merging `origin/<target>`, and pre-open
review diffs against the integration branch. None of them creates it. So the
branch cut is the piece the pattern supplies, performed by a pool worker that
has push rights.

## mol-design-convoy — the molecule

`formulas/mol-design-convoy.toml` is a dispatch molecule shaped like
`mol-first-reaction`: slung `--on` a single subject (the initiative), it reads
the input convoy's one tracked member, orchestrates, and drains. It writes no
code and needs no worktree of its own. Its steps:

| Step | What it does |
|---|---|
| `load-context` | Read the subject and its recommendation card for the design topic and intended implementation. Resolve `design_gated` (var, default `true`). |
| `seed-convoy` | Run `convoy-seed.sh`: create the owned convoy, set `target = integration/<convoy-id>`, cut and push the branch. Record the convoy id on the subject. |
| `arm-design` | File the design child, link it parent-child to the convoy, and sling `mol-polecat-work`. For `design_gated=true`, stamp the child's `check_set` with the approval lane (`codex,approval`) to arm the checkpoint gate. |
| `arm-implementation` | File one implementation child that builds the initiative per the approved design. `design_gated=true`: a `blocks` edge from the design child plus a `deferred-dispatch.sh arm`, so the design's closure dispatches it. `design_gated=false`: sling it now, in parallel. |
| `drain` | Close the step chain and drain. |

Every step re-derives the subject from the input convoy in its own shell and
records its result on the subject (`gc.design_convoy_id`, `gc.design_child`,
`gc.impl_child`, and the `*_armed` markers), so a crashed run resumes without
creating a second convoy, child, or workflow.

The implementation is one child, not a fan-out: the design defines the
breakdown, so the child carries "split into multiple beads if the approved
design calls for it" and splits itself when it runs. Enumerating pieces here
would guess at a breakdown the design has not settled yet.

### convoy-seed.sh — the branch cut

`assets/scripts/convoy-seed.sh` encapsulates the owned-convoy hand-recipe:
create the convoy, set its target, and cut+push `integration/<convoy-id>`. The
cut runs in a disposable `mktemp` worktree, never the rig root. Reconcile keeps
the rig root fast-forwarded to the default branch and directory-imported packs
build from its working tree, so a branch checkout or commit there would park the
deploy off the default branch. The script cuts from the resolved default branch
(`origin/HEAD`), and is idempotent: a supplied `--convoy` id skips creation and
an existing origin branch skips the cut.

A shared input artifact (a decisions doc several polecats need) is seeded with
`--artifact`, which starts the branch ahead of the default. A design-convoy
seeds nothing; its branch starts equal to the default and the design child lands
the first commit.

## The two operator gates

Design-gated work has two gates; all-in-one has one.

**Gate 1, the checkpoint PR** (design-gated only). The design child's doc lands
on the integration branch and the refinery opens a PR onto that branch. The
approval lane in the child's `check_set` makes `merge.sh` hold that PR until an
operator's APPROVED review stands at its live head (`assets/scripts/merge.sh`).
The design child cannot close, and the deferred implementation cannot dispatch,
until the operator approves. Two mechanics carry the arm to the merge:

- The refinery preserves an `approval`-bearing `check_set` already on the anchor
  at merge-push, rather than overwriting it with its bare var default
  (`formulas/mol-refinery-patrol.toml`, the `check-set-prefer-approval-arm`
  block). Without this the arm is erased before the checkpoint PR opens.
- `pr-open.sh` drops `approval` from the pre-open lane checks, because an
  external review cannot exist before the PR does. The stamp binds only at
  merge, so the checkpoint PR still opens for the operator to read.

**Gate 2, graduation.** Once every convoy member is closed and the ledger
records at least one landing on the integration branch, `convoy-graduate.sh`
rewrites the convoy into an mr work bead (`branch = integration/<id>`,
`target = default`), and the refinery opens the graduation PR from the
integration branch to the default branch. The operator reviews the whole unit,
design and implementation together, before the default branch moves.

## Design-gated versus all-in-one

`design_gated` is a var, default `true`, settled per initiative at the
recommend-to-Accept point or overridden with `--var design_gated=false`.

- **Design-gated** (`true`): the design child carries the approval lane, so the
  checkpoint holds implementation behind the operator's approval. Use it when
  the design decision genuinely gates the implementation shape, the blast radius
  is high, or the design is uncertain. The cost is the design round-trip before
  implementation starts.
- **All-in-one** (`false`): design and implementation dispatch together and land
  on the integration branch in parallel, reviewed once at graduation. Use it
  when the shape is already agreed and the design doc is mostly a record, or the
  implementation is small enough to redo cheaply. The cost is implementation
  built on a design the operator may later change.

The default is design-gated because a design doc is cheaper to change than built
implementation.

## How converse reaches it

The recommend-to-Accept-to-sling path carries the pattern with no special
handling. Converse stamps `gc.recommended_formula = mol-design-convoy` on the
subject visit; the board offers Accept while that key is non-empty; and
`gc-helm.sh accept` slings `gc sling <pool> <subject> --on mol-design-convoy
--var issue=<subject>`, the same single-formula, single-subject shape
`mol-first-reaction` rides.

Two convoys share the word. Accept's sling creates an ephemeral **input
convoy** whose one tracked member is the subject, which the formula reads as
`{{convoy_id}}`. `seed-convoy` creates the durable **owned convoy** for the PR
unit. The input convoy drains with the molecule; the owned convoy lives on and
graduates.

## When to recommend

| Follow-up | Route | Why |
|---|---|---|
| Executable work that needs a design settled before or beside the build, large or high-blast-radius enough that one holistic review beats scattered PRs | Recommend `mol-design-convoy` | Design and implementation land as one reviewed unit; the design gate catches a wrong shape before it is built |
| A single, well-understood change that is its own review unit | A work formula on the default one-child convoy | No design phase; one PR to the default branch |
| A human judgment, decision, or question with nothing to build | `mol-visit` | The operator decides; nothing to dispatch |

The distinguishing questions, in order:

1. Is there executable work at all? No: bare visit.
2. Does it need a design settled before or beside the implementation, and is it
   large or high-blast-radius enough that one holistic review beats scattered
   PRs? Yes: design-convoy. No: plain work bead.
