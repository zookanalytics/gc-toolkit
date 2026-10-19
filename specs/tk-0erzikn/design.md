---
name: A PR is one reviewable bead — the design
description: The design for the operator's PR model, settled in mechanik chat on 2026-10-18. Every PR is the operator's, a PR is one bead, and a convoy's members land on its branch with no PRs of their own unless told otherwise. It settles how that becomes the default, how a member takes its convoy's branch and when that branch is cut, where each review runs, when the PR opens and how rework returns to it, which living docs and doctrine change, and the implementation cut that reaches the operator as one PR. Read it to review the model before it is codified, or to build one of its units. Its inputs are brief.md and findings.md beside it.
---

# A PR is one reviewable bead

## The decisions, in one screen

Today every bead the city builds opens its own PR, and a convoy's members are no
exception. A convoy of seven changes reaches the operator as seven PRs into its
integration branch and then an eighth into main, and each one waits for an
approval. Under this design the convoy's PR is the only one. Each member lands
on the convoy's branch once its own molecule has reviewed it, and the operator
reviews the whole body of work once.

1. **The convoy decides how its members land.** A member with no landing mode of
   its own lands the way its convoy says, in Gas City's own convoy field. A
   convoy that says nothing lands its members on its integration branch with no
   PR. A member that is a stage the operator should review on its own is slung
   with `--merge mr`. The refinery reads this where it already decides how a
   bead lands, and a member whose gate fails there keeps its branch for the
   rework. Cost: six convoys open today, two in gc-toolkit and four in
   signal-loom, have ten members not yet landed, and those land with no PR
   instead of opening one each.
2. **A member takes its convoy's branch with no stamp of its own.** Gas City
   finds a member's branch through the one parent bd reports, so a member that
   also sits under an epic can be poured from main. The check at the start of
   the polecat's run already stops such a run before any work is done. It now
   stamps the convoy's branch on the member and pours the work again, instead
   of asking a person which branch it belongs on. Cost: one discarded pour for
   each such member.
3. **A convoy's branch is cut when its first member can start.** The branch is
   cut from main when the convoy is seeded, so a convoy is seeded once its
   first member's prerequisites are on main. A member that builds on work
   reaching main later waits on a hand-off bead, which brings the branch
   current once that work lands. Nothing new is built.
4. **A member is reviewed inside its own molecule, and the PR gets every
   check.** A member passes the work molecule's self-review loop and the
   refinery's gate before it lands. The city's checks run once, on the PR bead,
   before its PR is ready for review. Cost: a defect in an early member is
   caught only when the whole branch is reviewed, after later members may have
   built on it.
5. **The PR opens when the members are done, and rework comes back to it.**
   Graduation, the city's review of the branch and rework on the PR's own branch
   already work this way. Nothing new is built.
6. **The words follow the model.** The mechanik's dispatch doctrine, the
   polecat's doctrine, the component model, the design-convoy page, the PR
   banner and the `base: integration` label stop saying that each child opens a
   PR, that an owned convoy is the PR unit, or that a member poured from the
   wrong branch waits on a person.
7. **The implementation reaches the operator as one PR.** One owned convoy
   holds one member for each unit of the cut, each slung `--merge direct` by
   hand, and its graduation is the one PR. A bead assigned to the mechanik
   (tk-zkft1ym) stands the convoy up once this design merges.

Two things do not change. Every PR still needs the operator's approval, and
every PR still has exactly one owning bead (invariant I4).

## The model

The operator's words, from [brief.md](brief.md):

> "It's not about my approval being required on every PR. It's that a convoy can
> include multiple pieces of work, and that should all land as a single PR."

> "I feel like this is a pretty solid example of presenting all seven changes as
> one pull request, even though it might be seven individual changes that are
> done by individual pull cats (plus each review itself), and then it gets the
> overall review, etc."

> "Definitely not B. I don't want any PRs that are not mine. I'm still confused
> because molcat Do Work has reviews in it. It checks its work, and it can even,
> I think, have an external check from another bead, which represents another
> unit of work."

The model, as the brief states it:

1. Every PR is the operator's. The city opens a PR, into main or into an
   integration branch, only to ask for the operator's review.
2. A PR is one bead. It can have child beads, each done by its own polecat.
   Children open no PRs. Their work lands on the PR bead's branch, and the PR
   opens for the overall review once they are done.
3. Each child is reviewed inside its own work molecule before its work lands.
   The PR gets the overall review.
4. The city works in as many internal phases as it needs before it opens a PR.
5. Multi-stage work is more than one PR. Every reviewable unit is a PR.
6. A convoy is Gas City's concept, with its defined purpose: work that moves
   together onto a target branch, its children inheriting the target and the
   merge strategy. A convoy is not a PR, and nothing in gc-toolkit may keep it
   from working that way.

The words this design uses:

- **PR bead.** The one bead that owns a PR, which the component model calls the
  anchor. A lone bead is its own PR bead. A convoy's bead becomes the PR bead
  when the convoy graduates.
- **Member.** A bead linked to an owned convoy as its parent-child child. Its
  own polecat builds it, and it lands on the convoy's branch.
- **Stage.** A PR bead whose PR targets a convoy's branch instead of main, so
  the operator reviews that stage before the rest of the work moves on.
- **Landing mode.** How the refinery lands a branch. `direct` pushes it onto its
  target with no PR, and `mr` opens a PR. The bead key is `merge_strategy`.

## What the code does today

These were read at gc-toolkit `35cf7c70f` and gascity `2e9a6f0a6`. The installed
`gc`, built at `b7da5db00`, carries the same text in every gascity file cited.

- **One block decides the landing mode.** The refinery's
  `merge-strategy-resolve` block appears at both of its call sites in
  `formulas/mol-refinery-patrol.toml`, byte-identical. It takes the bead's own
  `merge_strategy`, and with none it takes the formula's
  `default_merge_strategy`, which is `mr`. It turns `mr` into `direct` for a
  `polecat/*` target that records no PR of its own, the fold-in
  ([specs/tk-sw5bu](../tk-sw5bu/merge-strategy-fold-in.md)). An `integration/*`
  target stays `mr`, and case (20) of
  `assets/scripts/mr-aware-rejection-failclosed.test.sh` pins that.
- **Gas City stamps a mode only from a flag or a rig default.** `gc sling
  --merge` stamps `merge_strategy`. With no flag, `SlingMergeStrategy`
  (`internal/sling/sling.go`) takes the rig's `default_merge_strategy` from
  `city.toml`. No rig in this city sets one, so a bare sling stamps nothing. A
  convoy's `convoy.merge` is written by `gc convoy create --merge` and printed
  by `gc convoy status`, and nothing in gascity reads it to decide anything. Gas
  City's own tutorial lists it as the convoy's merge strategy, beside the
  `target` its child beads inherit (`docs/tutorials/06-beads.md`).
- **The no-PR landing is reachable by hand.** The seven members of convoy
  tk-23q3ytl carry `target=integration/tk-23q3ytl` and a deferred dispatch whose
  sling arguments are `--merge direct`. `direct-merge-push.sh` lands such a
  member by fast-forward and closes it with `merge_result=merged` and
  `merged_target`.
  GitHub allows the push. The "Signed Commits" ruleset covers every branch and
  requires only signatures. The "Default Branch" ruleset, which requires a PR,
  covers `main` alone.
- **No direct landing onto an integration branch is on record.** The gc-toolkit
  store records 31 landings onto `integration/*` branches, each through a PR.
  Nine of its landed beads record no PR number or URL of their own, and none of
  those landed on an integration branch. The direct path was hardened on
  2026-10-18, in PR #1294.
- **A failed gate deletes a direct bead's branch.** When the refinery's gate
  fails because of the branch, the handle-failures step repools the bead with
  its `metadata.branch` kept. Its `rejection-branch-keep` block then deletes the
  branch on origin when the bead resolves `direct` and records no PR, and case
  (9) of `mr-aware-rejection-failclosed.test.sh` pins the delete. The rebuild
  resumes `metadata.branch`, so its workspace-setup finds no branch and files
  the missing-branch visit. A bead in `mr` mode keeps its branch, and its
  rebuild resumes it.
- **The city's checks need the PR bead's lifecycle, and only demo needs the PR
  itself.** This corrects the brief, which says the specialist checks need a PR
  and that `mol-review` refuses to run without one. `review-checks.toml` puts
  correctness, triage, arch and pm in the `pre-open` phase and demo in
  `open-as-draft`. `gate-ensure.sh` dispatches reviews for every anchor at
  `pre_open_gate` or `pull_request`. A pre-open review bead
  carries `review_branch` and `review_base` and no PR, a shape
  `formulas/mol-review.toml` reviews. What a member that lands direct lacks is a
  gating state. Only the PR path gives a bead one, when it moves from
  `handed_off` into `pre_open_gate` or `pull_request`, so no check runs on a
  direct member.
- **Graduation already makes the convoy bead the PR bead.**
  `convoy-graduate.sh` takes an open owned convoy that targets `integration/*`
  once every member is closed and at least one landing onto its branch is
  recorded. It rewrites the convoy into an `mr` work bead with
  `branch=integration/<id>` and `target` the rig's default branch, and seeds
  its `pr_summary` from the landed members' summaries. `pr-stack.sh` lists
  those members in the PR body, because it reads every bead whose
  `merged_target` is the PR's branch.
- **Rework already returns to the PR bead.** `rework-child.sh` files a child
  that resumes the anchor's own branch. The refinery's one-anchor-per-PR arm
  closes that child landed-on-branch rather than letting it open a second PR.
- **One polecat builds one bead.** `mol-polecat-work` refuses an input convoy
  with more than one member. That is the model's "each done by its own polecat",
  and it stays.
- **Sling finds a member's branch through one parent.** `gc sling` pours a
  feature-branch formula from the bead's own `target`, else from the first
  convoy target on the chain of parents bd reports (`BeadMetadataTarget`,
  `internal/sling/sling.go`), else from the rig's default branch. bd reports one
  parent, the bead's first parent-child edge. So a member that also sits under
  an epic can report the epic: sl-kg9z6.3.8, a member of convoy sl-oudm5,
  reports its epic sl-kg9z6.3 and names no target. `mol-polecat-work`'s
  workspace-setup guard cancels such a run before any branch is cut and files a
  visit that asks for the target. The mechanik's seed-and-link recipe stamps the
  convoy's target on each member it links, so sling never needs the parent. The
  operator's hold-queue ruling of 2026-10-08 (gc-afhveq) closed the gascity fix
  for the lookup (gc-gp4a2l). The finding is not disputed, and it does not meet
  the fork's "absolutely-critical / upstream-bound" bar.
- **A convoy's branch is cut once, at seed.** `convoy-seed.sh` cuts
  `integration/<id>` from the default branch's tip when it seeds the convoy.
  No step brings the branch current with the default branch until graduation,
  when the refinery merges the default branch in, as it does for every branch it
  prepares. Convoy tk-23q3ytl was seeded on 2026-10-18 equal to main, and its
  first member builds on the review-path redesign, which reaches main only when
  convoy tk-gaklsnk graduates. So hand-off bead tk-fsws0k6, assigned to the
  mechanik with a ready notice, waits on tk-gaklsnk and then fast-forwards the
  branch to main. The first member waits on the hand-off by a `blocks` edge.

## 1. Making a no-PR landing the default

### Decision

A bead's landing mode resolves in this order:

1. The bead's own `merge_strategy`, which a sling's `--merge` or a writer's
   stamp sets.
2. Otherwise, the mode of the convoy it lands through. That applies when the
   bead is a member of an open convoy whose `target` is an `integration/`
   branch, its own `target` is that same branch, and it records no PR of its
   own. The mode is the convoy's `convoy.merge`, and a convoy that names none
   lands its members `direct`.
3. Otherwise the refinery's default, `mr`.

The fold-in for `polecat/*` targets stays as it is, and so does the rule that an
`existing_pr` forces `mr`.

So a convoy's members land on its branch with no PR unless told otherwise, and
"told otherwise" takes one of two forms. A member slung with `--merge mr` is a
stage the operator reviews on its own. A convoy carrying `convoy.merge=mr` makes
every member such a stage.

A member whose gate fails at the refinery keeps its branch. The refinery's
rejection arms repool the bead with its `metadata.branch` kept, and the rebuild
resumes that branch, so no rejection deletes a branch in any mode. A branch is
deleted when its work lands: by `delete_merged_branches` after a direct landing,
and by the repository's delete-on-merge after a PR.

### Why the convoy, read at the refinery

- Model statement 6 says a convoy's members inherit its target and its merge
  strategy. `convoy.merge` is the field Gas City gives a convoy for the second.
  Reading it means gc-toolkit never overrides a convoy that says `mr`, and one
  open convoy, the review-engagement convoy (tk-x4oc74), says exactly that.
- The brief's other option, resolving every `integration/*` target to `direct`,
  keys on a branch-name convention instead of on the convoy. It would land that
  convoy's members against the mode the convoy declares.
- The rule reaches only a convoy whose target is an `integration/` branch,
  because that is the convoy `convoy-graduate.sh` graduates into a PR. A member
  landed with no PR onto any other branch would reach no PR at all.
- The fold-in's design kept `integration/*` targets on `mr` so that convoy work
  would not fast-forward past its review gate. Under the model the gate for a
  convoy's work is its PR bead, and every member's work passes through it before
  it reaches main.
- The refinery is where the mode is decided today, once, at landing time. A
  stamp written by gascity's sling would be fixed when the bead was dispatched,
  and changing sling would be a gascity PR, a second PR in another repository.
- The read costs no new store call. The `gc bd show --json` the block already
  holds lists each parent-child parent with its metadata, the convoy's `target`
  and `convoy.merge` among them.
- The default lives in one reader, so it holds however the convoy was made. A
  rule that every convoy's creator must set a field is the discipline that
  failed when every sling had to pass `--merge direct`. So `convoy-seed.sh` does
  not change, and a convoy it seeds lands its members `direct` by the default.

### Why a rejected branch is kept

Members land `direct` under this design, so the delete would reach every member
whose gate fails. Today such a member is in `mr` mode, so its branch is kept and
the rework resumes it with no one asked. With the delete, the same failure ends
in the missing-branch visit. The delete reads a direct bead with no PR as work
that will not be resumed, and the repool the same arm has just made resumes it.
Dropping the delete also fixes the rebuild of a direct bead outside any convoy.

### The bash bridge

- `merge-strategy-resolve`, at both call sites and byte-identical: when the bead
  carries no `merge_strategy` key and no PR of its own, find its open
  parent-child convoy whose trimmed `target` starts with `integration/` and
  equals the bead's `target`. Take that convoy's `convoy.merge`, normalized the
  way the block already normalizes `pr` to `mr`, or `direct` when it names none.
  Gas City also accepts `local` for a convoy, which the refinery has no landing
  for, so any value other than `direct`, `mr` or `pr` resolves to `mr` and the
  work still reaches a review. This is about a dozen lines.
- `rejection-branch-keep`, in the handle-failures step: the arm that deletes a
  direct bead's branch goes, and the block keeps a rejected branch in every
  mode.
- `assets/scripts/mr-aware-rejection-failclosed.test.sh`: case (20) keeps its
  answer, since its bead belongs to no convoy, and its comment says so. New
  cases pin a member that lands `direct`, a convoy that says `mr`, a convoy
  that says `local`, a member with its own stamp, a member with its own PR, a
  member whose target is not its convoy's, and a closed convoy. Cases (9),
  (13d) and (14) change from a deleted branch to a kept one, and case (18),
  which tests a refused delete, goes with the delete.
- `lifecycle/lifecycle.toml`: the `merge_strategy` entry states the order.

### What the gctk port carries

The landing mode is one question with one answer, owned by the domain that owns
convoys: a bead's own mode, else the mode of the convoy it lands through, else
the default. The port reads membership both ways the store records it, as a
parent-child child and as a `tracks` target, the two forms `convoy-graduate.sh`
already counts. The bash bridge reads only the parent-child form, because every
gc-toolkit recipe links members that way. Until the port, a member linked only
by `tracks` lands by its own stamp or by the refinery's default.

### What changes for convoys open today

A member that already has a PR, or sits at `pre_open_gate` or `pull_request`, is
past the refinery's queue and keeps its PR. The change reaches only members the
refinery has not yet taken.

| Convoy | Members not yet landed | Today | After the change |
|---|---|---|---|
| tk-23q3ytl, review coverage Feature 1 (gc-toolkit) | the seven method units | `direct`, by their dispatch arguments | `direct` |
| tk-gaklsnk, the review-path redesign (gc-toolkit) | tk-2aluzc9, unit B | a PR into `integration/tk-gaklsnk` | lands with no PR |
| tk-alyaztk, the refinery pool of one (gc-toolkit) | tk-fhkllrb, the implementation | a PR into `integration/tk-alyaztk` | lands with no PR |
| tk-x4oc74, review engagement (gc-toolkit) | tk-icggxv | a PR, since the convoy says `mr` | a PR |
| sl-oudm5, sl-kkn25, sl-63wpu, sl-ffjfk (signal-loom) | eight members, none dispatched | a PR each into the convoy's branch | land with no PR |

In both design convoys the design stage already merged through its own PR. The
review-path redesign's unit A (tk-nuctjl8) keeps its open PR, #1292. After
that, each convoy's next PR is its graduation. A convoy that should keep a PR
per member is told so before the change reaches main:
`gc bd update <convoy> --set-metadata convoy.merge=mr`.

## 2. A member takes its convoy's branch

### Decision

A member that names no target, and whose open convoys name one branch, takes
that branch whichever parent bd reports for it. When workspace-setup finds such
a member poured from another branch, its guard stamps the convoy's branch as the
member's `target`, cancels the run before any worktree exists, and arms the
work's re-sling. The next deferred-dispatch pass pours the work again, and sling
takes the stamped target first. No visit is filed. A stamp that does not read
back files the visit instead, so the repair never repeats itself.

The guard's two other convoy holds stay visits, because only a person knows the
branch.
One is a member whose own `target` differs from the branch it was poured from.
The other is a member whose convoys name more than one branch.

The mechanik's recipe keeps stamping the convoy's target when it links a member,
so a member it links is poured from the convoy's branch the first time.

### Why

- Model statement 6 says a convoy's children inherit its target. A member that
  names no target and belongs to one convoy branch has one right answer, and a
  visit would ask a person a question with one answer.
- The cause is Gas City's lookup, which reads one parent. Fixing it there is the
  fix where the cause arises, and the operator's ruling closed it for the fork
  (gc-gp4a2l). Inside gc-toolkit the guard is the one reader that sees every
  member before any work is built, whichever recipe linked it. That is the
  reason section 1 reads the convoy at the refinery.
- A stamp that every linker must write is the discipline section 1 sets aside
  for the landing mode. The recipe's stamp stays because it saves the discarded
  pour, and nothing depends on it.

### Cost

A member poured from the wrong branch costs one discarded pour, which ends in
workspace-setup before a worktree exists. Today it costs a visit and a person's
answer. In the open convoys of section 1, sl-kg9z6.3.8 would take this path if
it were slung as it stands.

### The bash bridge

- `workspace-setup-convoy-target-guard`, in `formulas/mol-polecat-work.toml`:
  its `mismatch` case stamps the convoy's target on the bead and reads it back.
  It then makes the writes `await-ruling.sh` makes before its arm, releasing the
  claim and clearing the route keys, arms the re-sling through
  `deferred-dispatch.sh arm` with no `blocks` edge, and cancels the run. Its
  `stale` and `conflict` cases keep their visits. The repair pours the work
  again rather than declining it, so the record the cancelled run leaves is the
  armed re-sling on the work bead, which `deferred-dispatch.sh list` returns.
- `assets/scripts/workspace-setup-convoy-target-guard.test.sh` pins the stamp,
  the armed re-sling and the absence of a visit, beside the cases that still
  file one. `assets/scripts/decline-wiring.test.sh`, which pins how the
  formulas cancel a run, keeps passing: the repair calls no `await-ruling.sh`,
  and its cancel names its own step.

### What the gctk port carries

A member's branch is its convoy's target, read from membership in both forms the
store records, as a parent-child child and as a `tracks` target. The guard reads
only the parent-child form, as it does today.

## 3. When a convoy's branch is cut

### Decision

A convoy's branch is cut once, when `convoy-seed.sh` seeds the convoy, from the
default branch as it stands then. So a convoy is seeded when its first member
can start. When that member builds on work that has not yet reached the default
branch, the bead that seeds the convoy waits on that work by a `blocks` edge,
and the members are linked and slung when it runs. tk-zkft1ym stands this
design's own convoy up that way, once this design merges.

A member that builds on work reaching the default branch after the seed waits on
a hand-off bead by a `blocks` edge. The hand-off waits on that work and, once it
lands, brings the convoy's branch current. While nothing has landed on the
convoy's branch, that is a fast-forward to the default branch, which is what
tk-fsws0k6 does for tk-23q3ytl. Once a member has landed, it is a merge of the
default branch into the convoy's branch. The mechanik owns the hand-off, with a
ready notice, as it owns the seeding.

Nothing new is built. The mechanik's dispatch doctrine states both (unit C).

### Why

- A member is poured from its convoy's branch, so the branch has to hold what
  the member builds on before the member starts. Seeding when the first member
  can start makes that true with no further step.
- Each wait is a `blocks` edge, so a member stays out of `bd ready` until the
  branch holds what it builds on, and the mechanik hears when to act.
- The refinery brings a convoy's branch current with the default branch once
  more at graduation, when it prepares that branch like any other. Merging the
  default branch in each time it moves would add a merge commit to every
  convoy's branch for each move of main. A hand-off brings a branch current only
  when a member needs it.

### Cost

When a convoy is seeded before its first member can start, or a later member
builds on work from outside the convoy, the hand-off costs the mechanik one
fast-forward or merge, pushed once it is notified.

## 4. Where each review runs

### Decision

| Where | What runs | What it reads |
|---|---|---|
| Inside each member's molecule | the self-review loop of `mol-polecat-work`: a polecat in a fresh session reviews and fixes the diff, and `self-review-check.sh` lets the loop end only when test, lint, typecheck, setup and build pass at HEAD | the member's own diff |
| At the refinery, before the member lands | the rig's full gate at the prepared head (the `run-tests` step) | the member merged onto the branch as it stands |
| On the PR bead, before its PR opens | every `pre-open` check: correctness and triage, and arch and pm when triage adds them | the whole branch against its target |
| On the PR bead, while its PR is a draft | the demo check, when triage adds it | the PR |
| On the PR | the operator's approval, `merge.sh`'s universal rule | everything |

### Why

- It is the operator's account of the member's review: the work molecule "checks
  its work", and each self-review iteration runs as its own bead in a fresh
  session under an exec check.
- The city's checks judge what the operator judges. Triage picks the specialist
  checks from the whole diff, and pm asks whether the PR lets the operator
  decide. The operator asked to review "a complete body of work" (2026-09-30,
  [findings.md](findings.md)), and the checks see the same one.
- A city review of each member needs a gating state for a bead that never opens
  a PR. That takes a new transition in `lifecycle/lifecycle.toml`, from
  `pre_open_gate` to `merged` with no PR, a cadence arm that lands a green
  member directly, and a `pr-open.sh` that leaves such a member alone. It is far
  more than the smallest bridge.

### Cost

A member's defect is found when the PR bead's correctness review reads the whole
branch, after later members may have built on it, and the fix comes back as
rework on the branch. That review reads the union of the members' diffs, a
larger diff than any one member's. Making one review of a body of work
trustworthy is the review-coverage epic's job (tk-qjdt90g), and its missed-issue
indicator is where a gap here would show.

Not in this cut: a second agent's correctness review of each member inside its
molecule, the way Gas City's `code-review` expansion runs review lanes in a
formula. It is the next step if reviews of convoy PRs miss defects that a review
of each member would have caught.

## 5. When the PR opens, and how rework returns

1. Each member lands on the convoy's branch and closes.
2. Once every member is closed and a landing is recorded, the merge cadence
   graduates the convoy within about fifteen minutes. The convoy bead becomes
   the PR bead, an `mr` work bead from `integration/<id>` to main.
3. The refinery prepares that branch, runs the rig's gate on it and moves the PR
   bead to `pre_open_gate`.
4. The city's pre-open checks review the whole branch. A request-changes verdict
   files a rework child of the PR bead, which resumes `integration/<id>`, and
   the refinery closes it landed-on-branch.
5. The PR opens once every pre-open check is green. When triage added the demo
   check, it opens as a draft and turns ready once demo is green.
6. The operator reviews it. Their review returns the same way: `pr-facts.sh`
   routes the feedback, the validator rules each point, and a rework child of
   the PR bead resumes the PR's branch. Scope found while the PR is open rides
   a supplement on the same branch.
7. `merge.sh` lands the PR once its checks are green and the operator's
   approval stands, and the PR bead closes.

Every step is today's machinery. A rework child or a supplement is a child of
the PR bead that opens no PR, which is model statement 2.

## 6. Stages: work that is more than one PR

A stage is a PR bead whose PR targets a convoy's branch. Work the operator does
not review on its own is a member instead, one of the internal phases of model
statement 4, and it lands with no PR. A one-bead stage is a member slung with
`--merge mr`. It opens its own PR into the convoy's branch,
the operator approves it, and it lands before the members that wait on it. The
design child of a design-gated design-convoy is one: its PR is the design gate.

A stage built from several beads would be a convoy nested in another, landing
its own PR into its parent's branch. `convoy-graduate.sh` graduates every convoy
to the rig's default branch, so that shape is not built, and this design's cut
does not build it. No open work needs it.

## 7. What to correct

Each row says what a living file asserts today and what it says under the model.
The unit that changes it is in the last column (section 8).

| File | Says today | Says under the model | Unit |
|---|---|---|---|
| `agents/mechanik/prompt.template.md`, the dispatch doctrine | "an owned convoy is the PR unit", a lone bead is the one-child convoy, and a child slung without the stamp "is held at workspace-setup before any branch is cut" | A PR bead is the unit. A lone bead is its own PR bead and needs no convoy. Several beads that reach the operator as one PR are an owned convoy, whose members land on its branch with no PR of their own. A member that is a stage is slung `--merge mr`. The seed-and-link recipe stays, and its sling passes no merge flag. A convoy is seeded when its first member can start, and a member that builds on work from outside the convoy waits on a hand-off that brings the branch current. A member slung without the stamp is poured again from the convoy's branch. | C |
| `docs/component-model.md`, §1 | the Anchor row, "the single open bead that owns a PR", and the Convoy row, "tracked set with one landing target" | The anchor is the PR bead, and the beads that build its branch own no PR. A convoy is a tracked set with one landing target and one landing mode its members inherit. I4 keeps its words. | C |
| `skills/prs/SKILL.md`, supplements | a supplement's `target` "for a PR under an owned convoy is `integration/<convoy-id>`" | That holds for a stage's PR. A convoy's graduation PR targets main. | C |
| `docs/design-convoy.md` | "The default PR unit is an owned convoy", "each child's PR onto the integration branch", and in all-in-one "Each child's PR still needs the operator's approval" | Design-gated: the design child is a stage PR into the branch, the implementation lands with no PR, and graduation is the second PR. All-in-one: one PR, at graduation. | B |
| `formulas/mol-design-convoy.toml`, arm-design | slings the design child with no merge flag | Slings it `--merge mr` when design-gated, because its PR is the design gate. All-in-one passes no flag, and neither does arm-implementation. `assets/scripts/mol-design-convoy-arm.test.sh` pins both. | B |
| `assets/scripts/pr-summary-region.sh`, the integration banner | "Approving it mints this phase into the convoy integration branch" | "stage" for "phase". These files already use "phase" for a check's phase, so one word keeps one meaning. `assets/scripts/pr-open.test.sh` pins the banner. | B |
| `assets/scripts/pr-status-label.sh`, the `base:` label | "checkpoint into integration; approval mints a phase, not a merge to main" | The same, for a stage. `ensure_group` creates a missing label and never edits one, so the label already on GitHub changes by one `gh label edit`. | B |
| `docs/state-machine.md`, the base label section | "approving the PR mints a phase into the integration branch", and the banner example | The same words as the banner and label. | B |
| `docs/epics.md`, "A checkpoint is always qualified" | a PR Checkpoint "lands a phase of work on a convoy's integration branch" | It lands a stage. | B |
| `lifecycle/lifecycle.toml`, `merge_strategy` | an absent key resolves to the formula default | The order in section 1. | A |
| `assets/scripts/pr-stack.sh`, header comment | a `merged_target` row "landed its own PR into it" | It landed into the branch, with or without a PR of its own. | A |
| `formulas/mol-refinery-patrol.toml`, the `rejection-branch-keep` comment | nothing PR-shaped on a bead means no PR will ever want its branch "only in direct mode" | A repooled bead's rebuild resumes its branch in every mode, so no rejection deletes it. | A |
| `template-fragments/polecat-doctrine.template.md`, integration branches | workspace-setup "cancels that run before it cuts a branch, and the work waits on a visit that asks for the target" | workspace-setup stamps the convoy's target on the bead and pours the work again from it. | D |

Each unit that edits a prompt or a formula regenerates its pages under
`generated/seed-audit/`. Specs are records and are not edited.

What stays as it is: the approval rule in `merge.sh`; I4 and its check,
`doctor/check-one-anchor-per-pr`, since a member never enters a gating state;
the one-bead input convoy of `mol-polecat-work`; the workspace-setup guard's
visits for a stale target and for convoys that name more than one branch; the
fold-in; and the rule that `existing_pr` forces `mr`.

## 8. The implementation cut

The fix cannot use itself, because until it reaches main the machinery opens a
PR per bead. So the implementation runs the by-hand path. One owned convoy, on
`integration/<convoy-id>`, holds one member for each unit below, and the members
are built in parallel. Each is slung with `--merge direct`, and the convoy
graduates as the one PR the operator reviews.

| Unit | What it changes | Its tests |
|---|---|---|
| A. The landing mode | `merge-strategy-resolve` at both call sites in `formulas/mol-refinery-patrol.toml` and the branch delete in its `rejection-branch-keep` block, the `merge_strategy` entry in `lifecycle/lifecycle.toml`, the `pr-stack.sh` comment, and the formula's seed-audit page | `assets/scripts/mr-aware-rejection-failclosed.test.sh` |
| B. Stages | `formulas/mol-design-convoy.toml` arm-design, `docs/design-convoy.md`, the banner in `assets/scripts/pr-summary-region.sh`, the label text in `assets/scripts/pr-status-label.sh` and the live label, the base label section of `docs/state-machine.md`, the PR Checkpoint sentence of `docs/epics.md`, and the formula's seed-audit page | `assets/scripts/mol-design-convoy-arm.test.sh`, `assets/scripts/pr-open.test.sh` |
| C. Doctrine | the dispatch doctrine in `agents/mechanik/prompt.template.md`, §1 of `docs/component-model.md`, the supplement section of `skills/prs/SKILL.md`, and the mechanik's seed-audit page | `assets/scripts/skill-needs.test.sh`, `render-seed-audit.sh --check` |
| D. The member's branch | the `mismatch` case of `workspace-setup-convoy-target-guard` in `formulas/mol-polecat-work.toml`, the integration-branch paragraph of `template-fragments/polecat-doctrine.template.md`, and the seed-audit pages of the formula and of the polecat and polecat-codex prompts that compose the fragment | `assets/scripts/workspace-setup-convoy-target-guard.test.sh`, `assets/scripts/decline-wiring.test.sh`, `render-seed-audit.sh --check` |

Each unit is one concern a reviewer can hold. The units touch disjoint files,
so the refinery's merge of the convoy's branch into a member's branch before it
lands meets no conflict from the others, whichever lands first. Nothing in one
unit is built on another, so none waits for the others.

The default and the words reach main together. They land on the integration
branch first and move to main only in the graduation merge, so no design-convoy
is poured between a default that lands design children with no PR and the
`--merge mr` that keeps the design gate. The members themselves land through the
direct path by hand, so that path runs on an integration branch before any
convoy depends on it by default.

Until unit A reaches main, the refinery still deletes a direct member's branch
when its gate fails because of the branch. A member of this convoy, or of
tk-23q3ytl, that fails there waits on the missing-branch visit. Its release is
to restore the branch, or to clear `metadata.branch` so the rebuild starts again
from the convoy's branch.

**Who stands it up.** tk-zkft1ym is assigned to the mechanik and waits on this
design's bead (tk-0erzikn) by a `blocks` edge, with a ready notice armed. When
this design merges, the mechanik seeds the convoy, files one member per row of
the table above as it reads on main, links each to the convoy, stamps its
target, and slings each with `--merge direct`.
The units are filed then, from the cut the operator approved, so a change made
in this design's review cannot leave filed beads describing the old cut.
