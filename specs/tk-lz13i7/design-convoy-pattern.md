---
name: Design-Convoy Pattern
description: The executable owned-convoy pattern converse reaches by recommendation. A mol-design-convoy molecule stands up an owned integration convoy, cuts its branch from a disposable worktree, files a design child, and arms implementation behind the design's approval. Covers the recommend-to-Accept wiring, the when-to-recommend rubric, and the design-gated default. Design input for the converse design-convoy epic (tk-2gt6r2).
---

# Design-Convoy Pattern

A design-convoy is an owned convoy whose first child settles a design on an
integration branch and whose implementation children are armed behind that
design's approval, so the whole unit graduates to the default branch as one
reviewed PR. This design makes the pattern executable. A molecule that converse
recommends and the operator Accepts stands the convoy up — it creates the
convoy, cuts the integration branch, files the design child, and arms
implementation — with no human running git by hand.

## Scope

**Mandate.** The executable design-convoy pattern: the `mol-design-convoy`
molecule and its lifecycle, how converse reaches it through the
recommend-to-Accept-to-sling path, the rubric that chooses it over a plain work
bead or a bare visit, and the design-gated-versus-all-in-one default. It defines
the implementation the epic (tk-2gt6r2) owns.

**Boundaries.** It does not change the recommend-to-Accept-to-sling machinery
(landed as PR #843) or the convoy graduation cadence (`convoy-graduate.sh`); it
consumes both. It does not own the attention derivation for a checkpoint PR
awaiting review — that is review-engagement (tk-x4oc74), which this pattern
composes with. It does not build the implementation; Section 8 hands that to a
tracked owner.

## 1. The gap: a sitting cannot cut the branch

The default PR unit is an owned convoy on an integration branch
(`agents/mechanik/prompt.template.md:80-129`). Children inherit
`metadata.target = integration/<convoy-id>` through `gc sling`'s convoy-ancestor
walk; the refinery lands them on that branch; the cadence then graduates the
convoy to the default branch as one human-approved PR
(`assets/scripts/convoy-graduate.sh`).

Standing the convoy up is hand-run. `gc convoy create --owned` records convoy
metadata and never touches git. The integration branch is cut and pushed by a
human following the mechanik recipe: create the convoy, add a disposable
worktree, commit the shared artifact, push the branch, remove the worktree.
tk-2pe0fm made that recipe safe — a disposable worktree instead of a rig-root
checkout, which had parked a deploy mirror off its default branch — but left it
a human step.

Converse recommends and slings; a sitting never pushes. A converse that
assembled this shape by hand got as far as it could and stopped at the one step
it cannot perform: cutting the integration branch. Everything downstream expects
the branch to already exist. The submit gate resolves `metadata.target` and
fails closed with no branch (`formulas/mol-polecat-work.toml:1013-1034`); the
refinery brings a branch current by merging `origin/$TARGET`
(`formulas/mol-refinery-patrol.toml:195-235`); pre-open review refuses to guess
a base and diffs against the integration branch
(`formulas/mol-review.toml:93-102`). None of them creates it.

So the missing piece is an automated integration-branch cut reachable from the
recommend-to-Accept path, performed by something that has push rights.

## 2. The pattern end to end

The molecule converse recommends does the stand-up and then drains; the convoy
runs itself from there.

```
converse           stamps gc.recommended_formula = mol-design-convoy on the subject visit
   |
operator Accept -> gc-helm.sh accept: gc sling <pool> <subject> --on mol-design-convoy --var issue=<subject>
   |
mol-design-convoy  (one pool session, has push rights)
   |- seed-convoy         gc convoy create --owned; cut+push integration/<convoy-id> from a disposable worktree
   |- arm-design          file design child, sling mol-polecat-work (target = integration/<convoy-id>)
   |- arm-implementation  design_gated=true  -> file impl child(ren), blocks-edge on design, deferred-dispatch arm
   |                       design_gated=false -> sling impl child(ren) now, in parallel
   \- drain
   |
design child  -> design doc on the integration branch -> checkpoint PR (base = integration) -> operator approves, merges   [gate 1]
   |
   | design_gated: design child closes -> arm fires -> impl child dispatches
   v
impl child(ren) -> code on the integration branch -> PR (base = integration) -> merges
   |
   | all children closed AND >=1 landing on the branch
   v
convoy-graduate.sh -> rewrites the convoy bead into an mr work bead (branch = integration, target = default)
   v
refinery -> integration/<id> -> default-branch graduation PR -> operator approves -> the default branch moves   [gate 2]
```

Every PR the pattern produces, onto the integration branch or into the default
branch, merges only with a standing APPROVED review from an account other than
the city's, which counts until it is dismissed. `merge.sh` enforces that as a
universal merge rule (Section 3.1). Design-gated
work has two operator gates, the two approvals that decide what moves next.
Gate 1 is the checkpoint PR into the integration branch: the operator reviews
the design on-branch before any implementation starts. The design child cannot
close, and the deferred implementation cannot dispatch, until an operator's
APPROVED review stands on the checkpoint PR and the PR merges. Gate 2
is the graduation PR from the integration branch to the default branch: the
operator reviews the whole unit, design and implementation together, before it
lands. All-in-one work has only gate 2. Its implementation starts beside the
design, and although each child's PR still needs the operator's approval to land
on the integration branch, no approval holds implementation back.

## 3. mol-design-convoy — the molecule

It is a dispatch molecule shaped like `mol-first-reaction`: slung `--on` a single
subject, it reads the input convoy's one tracked member, orchestrates, and
drains (`formulas/mol-first-reaction.toml:48-51`). It writes no code and needs
no worktree of its own. Its steps:

| Step | What it does |
|---|---|
| `load-context` | Read the subject (the initiative) via `{{convoy_id}}` / `gc.var.issue`; read its recommendation card for the design topic and the intended implementation breakdown; resolve `design_gated` (a var, default `true`). |
| `seed-convoy` | Run `convoy-seed.sh` (below): create the owned convoy, set `target = integration/<convoy-id>`, cut and push the branch from a disposable worktree. Idempotent on resume. |
| `arm-design` | File the design child, link it parent-child to the convoy, read the link back, sling `mol-polecat-work` to the pool. The child lands its design doc on the integration branch and the refinery opens the checkpoint PR, which the universal approval rule holds for the operator (Section 3.1). |
| `arm-implementation` | File the implementation child(ren), link parent-child to the convoy. `design_gated=true`: a `blocks` edge from the design child plus a `deferred-dispatch.sh arm`. `design_gated=false`: sling them now. Each edge is read back before anything dispatches. |
| `drain` | Close the step chain and drain. |

`convoy-seed.sh` is the centerpiece — the automated branch cut, encapsulating the
mechanik hand-recipe so a worker runs it instead of a person:

```
convoy-seed.sh --name "<initiative>" [--artifact <path> --artifact-message "<msg>"]
  -> prints convoy_id and branch
  # 1. gc convoy create "<initiative>" --owned --json      -> convoy_id
  # 2. gc convoy target <convoy_id> "integration/<convoy_id>"
  # 3. git fetch --prune origin
  #    SEED=$(mktemp -d)/wt
  #    git -C <rig-root> worktree add "$SEED" -b integration/<convoy_id> origin/<default>
  #    [ --artifact: add + commit it in "$SEED" ]      # design-convoys seed nothing; the branch starts == default
  #    git -C "$SEED" push -u origin integration/<convoy_id>
  #    git -C <rig-root> worktree remove "$SEED"
  # idempotent: if origin already has the branch, skip the cut (resume-safe)
```

The disposable worktree is load-bearing: the rig root is a deploy mirror that
reconcile keeps fast-forwarded to the default branch, so the seed must never
check out or commit there. That is the tk-2pe0fm lesson, now enforced in code
rather than in a human's care.

One constraint the seed step respects. `self-review-check.sh` must resolve its
beads bd-only so it stays correct under a cold import cache that kills `gc
convoy`, and its test asserts it never shells out to `gc convoy`
(`assets/scripts/self-review-check.test.sh:103-109`). That is a rule about a
resolution predicate, not about orchestration. The seed step's `gc convoy
create` runs in a live session as an action, and the children resolve their
`base_branch` from the inherited `metadata.target`, not from `gc convoy`. The
two do not collide.

### 3.1 The gates under the universal approval rule

Gate 1 has to be a hold the merge machinery enforces, not a convention. The city
lands every anchor's PR through `merge.sh`, and `merge.sh` requires a standing
APPROVED review on every PR from an account other than the city's. The approval
counts at whatever commit it was given and stands across later pushes until
someone dismisses it, and a standing CHANGES_REQUESTED from any other account is
a veto (`assets/scripts/merge.sh`, its approval check). The rule is universal: no
`check_set` token arms it and none opts out, and GitHub branch protection is an
extra layer, not the authority. So the design child's checkpoint PR waits for
the operator with no stamp on the child, which carries whatever `check_set` the
refinery stamps on every anchor at merge-push.

What makes that approval a gate on implementation is the sequencing. For
`design_gated=true`, `arm-implementation` holds the implementation child behind
the design child with a `blocks` edge and arms a deferred dispatch on it. The
design child closes when its checkpoint PR merges, which the universal rule
allows only after the operator approves. Once the design child is closed, the
`blocks` edge no longer holds the implementation child, and the deferred
dispatch slings it, so the operator's approval of the design is what releases
implementation.

Gate 2 is enforced the same way. `convoy-graduate.sh` turns the finished convoy
into an mr work bead whose PR runs from the integration branch to the default
branch, and `merge.sh` holds that graduation PR until an operator's APPROVED
review stands on it, as it holds every other PR.

All-in-one (`design_gated=false`) slings the implementation child beside the
design child, with no `blocks` edge. Each child's PR still waits for the
operator's approval to land on the integration branch, but no approval holds
implementation back, and gate 2 is the first review of the unit as a whole.

## 4. Reaching it from converse

The recommend-to-Accept-to-sling path already carries this with no change.

Converse stamps `gc.recommended_formula = mol-design-convoy` on the subject
visit; `first-reaction-dispose.sh` is the one writer of that key. The board
offers Accept when the key is non-empty (`services/helm/internal/board/derive.go`
tests `rf != ""`). The operator Accepts, and `gc-helm.sh accept` slings it:

```
gc sling ${GC_RIG:+--rig "$GC_RIG"} "$bead" --on "$formula" --var "issue=$bead"
```

(`assets/scripts/gc-helm.sh:2404`), then withdraws the recommendation and
dismisses the visit on success. This is the same single-formula, single-subject
shape `mol-first-reaction` already rides, so the Accept path needs no change. The
new capability lives entirely inside `mol-design-convoy`.

Two convoys share one word, and keeping them distinct is the whole trick.
Accept's sling creates an **input convoy** — the ephemeral molecule wisp whose
one tracked member is the subject, which the formula reads as `{{convoy_id}}`.
`mol-design-convoy`'s `seed-convoy` step creates a separate **owned convoy** for
the durable PR unit. The input convoy drains with the molecule; the owned convoy
lives on and graduates. Accept dispatches one subject formula, and that formula
stands the durable convoy up itself.

## 5. When to recommend

| Follow-up | Route | Why |
|---|---|---|
| Executable work that needs a design settled before or beside the build, large or high-blast-radius enough that one holistic review beats scattered PRs | Design-convoy: recommend `mol-design-convoy` | Design and implementation land as one reviewed unit; the design gate catches a wrong shape before it is built |
| A single, well-understood change that is its own review unit | Plain work bead: a work formula on the default one-child convoy | No design phase; one PR to the default branch |
| A human judgment, decision, or question with nothing to build | Bare visit: `mol-visit` | The operator decides; nothing to dispatch |

The distinguishing questions, in order:

1. Is there executable work at all? No: bare visit.
2. Does it need a design settled before or beside the implementation, and is it
   large or high-blast-radius enough that one holistic review beats scattered
   PRs? Yes: design-convoy. No: plain work bead.

The minimal converse change adds the design-convoy row to converse's routing
rubric — near the "route through a formula" rule
(`agents/converse/prompt.template.md:392`) and the recommendation block (`:369-379`)
— and names `mol-design-convoy` as the recommended formula when the rubric points
there. No skill-code change. converse-settle's sibling-and-arm path stays for the
plain-work-bead case. The rubric ships as one shared prompt fragment,
`template-fragments/design-convoy-routing.template.md`, which the converse and
mechanik prompts both include, each beside its own verb: converse recommends the
formula, and mechanik slings it.

## 6. Design-gated versus all-in-one

Design-gated is the default; all-in-one is an operator-selectable override
through the `design_gated` var.

- **Design-gated** (`design_gated=true`): the universal approval rule holds the
  checkpoint PR until an operator's APPROVED review stands on it (Section 3.1).
  The design child closes only when that PR merges, and
  implementation is armed behind that closure, so implementation dispatches only
  after the operator approves. Two gates. Use it when the design decision
  genuinely gates the implementation shape, the blast radius is high, or the
  design is uncertain. Cost: implementation waits for the design round-trip.
- **All-in-one** (`design_gated=false`): design and implementation dispatch
  together and land on the integration branch in parallel. Each PR still needs
  the operator's approval, but implementation does not wait for the design's.
  Use it when the shape is already agreed and the design doc is mostly a record,
  or the implementation is small enough to redo cheaply. Cost: implementation may
  be built on a design the operator later changes.

The default is design-gated because a design doc is cheaper to change than built
implementation, and the checkpoint gate is the pattern's reason to exist. The
operator confirmed that default (sitting tk-kwmyg3, 2026-10-02) and settles the
shape per initiative at the recommend-to-Accept point, or overrides it with
`--var design_gated=false`. The formula reads the var case-insensitively, and an
empty or unrecognized value falls back to design-gated, so a typo never drops
the design gate.

## 7. Coordination with in-flight work

- **accept-discuss-flow** (tk-pyzug2, PR #843, landed): the
  recommend-to-Accept-to-sling machinery this pattern rides. Build on it; it is
  done.
- **review-engagement** (tk-x4oc74, in flight on `integration/review-engagement`):
  its Defect B makes a blocked-on-human frontier derive `needs-attention`
  instead of `working`, from one derivation shared by the GitHub label
  (`services/gctk/prstatus/prstatus.go`) and the board phase chip
  (`services/helm/internal/board/derive.go`), and surfaces an attention-reason
  that distinguishes "a visit awaits engagement" from "a stalled or blocked
  frontier". The design-convoy's gate 1 — a checkpoint PR awaiting operator
  approval — is exactly that blocked-on-human frontier. This pattern consumes
  B's shared derivation; if the checkpoint-awaiting-approval case wants its own
  attention-reason, it is added to B's reason taxonomy, never a competing board
  affordance. Its Defects A and C — acknowledgment decoupled from merge-state,
  and comment-to-visit linkage — carry the checkpoint review's comment handling
  unchanged. Sequencing: land B before the pattern surfaces gate 1 on the board,
  or gate 1 rides the generic `needs-attention` until B lands.

## 8. Handed to implementation

The owner is the converse design-convoy epic (tk-2gt6r2), which carries
`target = integration/design-convoy` and parents this design. Armed behind this
design's approval, the implementation is two slices:

- **Mechanism.** `formulas/mol-design-convoy.toml` (the five-step molecule of
  Section 3) and `assets/scripts/convoy-seed.sh` (create, cut, push from a
  disposable worktree, idempotent), each with a hermetic test. Gate 1 needs no
  change to the merge machinery, because the universal approval rule already
  holds every PR (Section 3.1). Plus the
  authoritative doc that states the pattern as what is true once it lands —
  folded into `docs/state-machine.md` and `docs/refinery-merge-cadence.md`, or a
  new `docs/design-convoy.md` — reconciling the cadence-arm numbering, which
  drifts between the scripts and the docs (`convoy-graduate.sh` and
  `refinery-reconcile.sh` call it arm 5; `docs/state-machine.md:155` calls it
  arm 6).
- **Wiring.** The converse routing-rubric change of Section 5, and the mechanik
  doctrine change that points the owned-convoy recipe at `mol-design-convoy`
  instead of the hand-run git block (`agents/mechanik/prompt.template.md:80-129`),
  so the doctrine's intent stays while its manual steps become the molecule.
  This slice blocks on the mechanism.

This design fixes the molecule's shape and steps, the seed script's contract and
its safety constraint, the recommend-to-Accept path (confirmed unchanged), the
rubric, and the design-gated default. It leaves to implementation the formula's
exact step text and var wiring, the seed script's flag surface and idempotency
test, and the final doc placement.

The cost of waiting, which makes this a tracked deferral and not a dump: until
the mechanism lands, every owned-convoy dispatch stays a hand-run seed — the
error-prone step that produced tk-2pe0fm — and converse cannot offer a
design-convoy at all, so design-first work either lands a spec straight to the
default branch (the anti-pattern the doctrine names) or waits on a human to run
the mechanik recipe.

## Provenance

Design bead tk-lz13i7, child of the converse design-convoy epic tk-2gt6r2, on the
epic's integration branch `integration/design-convoy`. Inputs: the mechanik
owned-convoy doctrine (`agents/mechanik/prompt.template.md:80-129`) and its
tk-2pe0fm safety fix; the recommend-to-Accept-to-sling machinery landed as PR
#843 (tk-pyzug2); two pack sweeps of the convoy, branch, and graduation
machinery and of the converse recommend-to-Accept path, recorded against the
file and line references cited above; the review-engagement design
(`specs/tk-x4oc74/design.md`, `integration/review-engagement`); and the hand-run
converse attempt that assembled this shape and stopped at the branch cut.
Implementation is owned by tk-2gt6r2.

The gate mechanism in Sections 2, 3.1, and 6 follows the operator's rulings in
sitting tk-kwmyg3 (2026-10-02). Approval is a universal merge rule enforced in
city merge logic, landed with tk-yx2oqr.2, so gate 1 carries no approval token
in the design child's `check_set`, and the design-gated default stands as
settled. Rework tk-wuo3gc brought this design and the branch to that model.
