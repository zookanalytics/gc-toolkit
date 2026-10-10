---
name: Design-convoy pattern
description: The executable owned-convoy pattern converse reaches by recommendation. mol-design-convoy stands up an owned integration convoy, cuts its branch, files a design child, and arms implementation behind the design's approval, so design and implementation graduate to the default branch as one reviewed unit. Covers the molecule, the seed script, the two operator gates under the universal approval rule, and the design-gated default. The when-to-recommend rubric ships in the converse and mechanik prompts.
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
(`agents/mechanik/prompt.template.md`). Children branch from
`integration/<convoy-id>`: `gc sling` reads it from a child's own
`metadata.target`, which the mechanik recipe stamps, and otherwise from the
first convoy target on the one parent chain bd reports. The refinery lands them
on that branch, and the cadence then graduates the convoy to the default branch
as one human-approved PR (`convoy-graduate.sh`).

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
| `arm-design` | File the design child, link it parent-child to the convoy, read the link back, and sling `mol-polecat-work`. |
| `arm-implementation` | File one implementation child that builds the initiative per the design. `design_gated=true`: a `blocks` edge from the design child plus a `deferred-dispatch.sh arm`, so the design's closure dispatches it. `design_gated=false`: sling it now, in parallel. Each edge is read back before anything dispatches. |
| `drain` | Close the step chain and drain. |

Every step re-derives the subject from the input convoy in its own shell and
records its result on the subject (`gc.design_convoy_id`, `gc.design_child`,
`gc.impl_child`, and the `*_armed` markers), so a crashed run resumes without
creating a second convoy, child, or workflow. An arm stamps its `*_armed` marker
only after every setup write it made has landed and read back. A link or
`blocks` edge that does not read back fails the step with the marker unstamped,
so the resume re-runs that arm rather than skipping it. The read-back decides,
not the add's exit status, because a resumed add can meet an edge the failed
pass already wrote.

The implementation is one child, not a fan-out: the design defines the
breakdown, so the child carries "split into multiple beads if the design
calls for it" and splits itself when it runs. Enumerating pieces here
would guess at a breakdown the design has not settled yet.

### convoy-seed.sh — the branch cut

`assets/scripts/convoy-seed.sh` encapsulates the owned-convoy hand-recipe:
create the convoy, set its target, and cut+push `integration/<convoy-id>`. The
cut runs in a disposable `mktemp` worktree, never the rig root. Reconcile keeps
the rig root fast-forwarded to the default branch and directory-imported packs
build from its working tree, so a branch checkout or commit there would park the
deploy off the default branch. The script cuts from the resolved default branch
(`origin/HEAD`), and is idempotent: a supplied `--convoy` id skips creation and
an existing origin branch skips the cut. Its git operations bind to the rig
root named by `--rig-root`, else `GC_RIG_ROOT`, else the checkout it runs in,
so a caller outside the rig checkout, such as city-scoped mechanik, passes
`--rig-root`.

A shared input artifact (a decisions doc several polecats need) is seeded with
`--artifact`, which starts the branch ahead of the default. A design-convoy
seeds nothing; its branch starts equal to the default and the design child lands
the first commit.

## The two operator gates

Every PR a design-convoy produces merges only with a standing APPROVED review
from an account other than the city's. The approval counts at whatever commit
it was given and stands across later pushes until someone dismisses it, so a
push to an approved PR does not wait for a second approval. A standing
CHANGES_REQUESTED from any other account vetoes the merge. `merge.sh` enforces
this as a universal merge rule: it is armed for every PR and named by no
`check_set` token (`assets/scripts/merge.sh`), and GitHub branch protection is
an extra layer, not the authority. The design child's checkpoint PR, each
child's PR onto the integration branch, and the graduation PR all pass through
it. The pattern's two gates are the two approvals that decide what moves next.

The rule is the default branch's `merge.sh`, the copy the refinery runs from
its deployed pack, and it gates PRs onto an integration branch as well. An
integration branch's own copy of `merge.sh` can predate the rule. The refinery
never runs that copy, and a convoy that changes no `merge.sh` leaves the default
branch's version in place when it graduates.

**Gate 1, the design checkpoint** (design-gated only). The design child's doc
lands on the integration branch through a checkpoint PR onto that branch, and
the universal rule holds that PR until the operator approves it. The
implementation child is held behind the design child by a `blocks` edge, and a
deferred dispatch sends it to the pool when the design child closes. The design
child closes only when its checkpoint PR merges, so the operator's approval of
the design is what releases implementation.

**Gate 2, graduation.** Once every convoy member is closed and the ledger
records at least one landing on the integration branch, `convoy-graduate.sh`
rewrites the convoy into an mr work bead (`branch = integration/<id>`,
`target = default`), and the refinery opens the graduation PR from the
integration branch to the default branch. The same universal rule holds that PR
until an operator's approval stands on it, so the operator reviews the whole
unit, design and implementation together, before the default branch moves.

## Design-gated versus all-in-one

`design_gated` is a var, default `true`, settled per initiative at the
recommend-to-Accept point or overridden with `--var design_gated=false`. It is
read case-insensitively: `false`, `0`, `no`, or `off` selects all-in-one, and
`true`, `1`, `yes`, or `on` selects design-gated. An empty or unrecognized value
also selects design-gated, with a warning, so a typo never drops the design gate.

- **Design-gated** (`true`): implementation waits behind gate 1, so it starts
  only after the operator approves the design. Use it when the design decision
  genuinely gates the implementation shape, the blast radius is high, or the
  design is uncertain. The cost is the design round-trip before implementation
  starts.
- **All-in-one** (`false`): design and implementation dispatch together and land
  on the integration branch in parallel. Each child's PR still needs the
  operator's approval to land, but implementation does not wait for the
  design's. Use it when the shape is already agreed and the design doc is mostly
  a record, or the implementation is small enough to redo cheaply. The cost is
  implementation built on a design the operator may later change.

The default is design-gated because a design doc is cheaper to change than built
implementation.

## How converse reaches it

The recommend-to-Accept-to-sling path carries the pattern with no special
handling. Converse stamps `gc.recommended_formula = mol-design-convoy` on the
subject visit; the board offers Accept while that key is non-empty; and
`gc-helm.sh accept` slings `gc sling <pool> <subject> --on mol-design-convoy
--var issue=<subject>`, the same single-formula, single-subject shape
`mol-first-reaction` rides.

Two convoys share the word. Accept's sling creates an **input convoy** whose
one tracked member is the subject, which the formula reads as `{{convoy_id}}`.
`seed-convoy` creates the durable **owned convoy** for the PR unit. The input
convoy is only this pour's handle on the subject. The owned convoy lives on and
graduates.

## When to reach for it

The rubric that chooses a design-convoy over a plain work bead or a bare visit is
routing guidance for the roles that route work, so it ships in their prompts.
`template-fragments/design-convoy-routing.template.md` holds it, and the
converse and mechanik prompts include it, each beside its own verb: converse
recommends the formula, and mechanik slings it.
