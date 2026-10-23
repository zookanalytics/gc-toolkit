---
name: A PR is one reviewable unit, on Gas City's convoy as it is intended to be used — the design
description: The design for the operator's PR model, recast by the operator's ruling of 2026-10-23 as a plan that deletes gc-toolkit's own convoy code. gc-toolkit uses Gas City's convoy as the noun and the verb. A convoy tracks its members, each member carries the convoy's branch as its target and lands there with no PR, a finished owned convoy lands the way Gas Town lands one, and work reaches main only through a PR. The design measures the convoy code the pack carries, deletes graduation, the seed script, a duplicate order, the integration banner and label, and the refinery's fold-in and branch delete, keeps four pieces under warrants, shows that someone who knows only Gas City and Gas Town sees a normal convoy, and cuts the work into five units. Read it to review the model and the deletions before they are built, or to build one of its units. Its inputs are brief.md and findings.md beside it.
---

# A PR is one reviewable unit, on Gas City's convoy as it is intended to be used

## The proposal, in one screen

Today a bead that names no merge strategy opens its own PR, convoy members
included, because gc-toolkit's refinery delivers such a bead through a PR. A
convoy of seven changes reaches the operator as seven PRs into its branch and an
eighth into main. Beside that, gc-toolkit carries about 6,800 lines that touch
convoys, and some of them do what Gas City and Gas Town already do.

Under this design the convoy's PR into main is the only one, unless the operator
asks to review a stage on its own. gc-toolkit uses Gas City's convoy as it is
intended to be used: someone who knows only Gas City and Gas Town sees a normal
convoy in the pack's graph and in its operations (section 7).

**Deleted.** Section 9 measures each deletion.

- Graduation: `convoy-graduate.sh`, its test, and its cadence arm. Gas Town's
  auto-land takes its place. Once an owned convoy's members are closed, the
  refinery takes the convoy's bead as a work bead and carries its branch to main
  (section 4).
- `convoy-seed.sh`, its test, and the test of its call from `mol-design-convoy`.
  The recipes call Gas City's verbs and push one branch (section 3).
- The hourly `convoy-check` order. An order in Gas City's core pack runs the same
  command (section 4).
- The `base: integration` label and the integration banner in a PR's body. GitHub
  shows every PR's base (section 5).
- The refinery's fold-in flip, and its rejection arm's delete of a `direct`
  bead's branch. Under the `direct` default neither has work left (section 1).

**Changed.**

- The refinery's default becomes `direct`, as Gas Town's is. One line keeps main
  behind a PR: a bead that would land `direct` on main resolves to `mr`
  (section 1).
- A member is added with `gc convoy add`, Gas City's `tracks` edge, and the step
  that adds it writes the convoy's `target` on it (section 2).
- workspace-setup's convoy target guard reads the convoys that track a bead, as
  well as its parents (section 2).
- The refinery's patrol takes a finished owned convoy's bead, as Gas Town's does
  (section 4).

**Kept, each under a warrant** (section 8):

1. The one line for main. It keeps main behind a PR in a window when main's
   ruleset is off, which is when the city once pushed to main unintended, and
   Gas City has no merge strategy per target branch to say it in config.
2. A member's `target`, and the guard that catches a member without one. Gas
   City's sling reads a convoy's target only down a parent chain.
3. The cut of a convoy's branch. No Gas City verb creates a branch.
4. The code that reads a workflow's input convoy. A graph.v2 root records the
   input convoy it was launched on and not the bead, so a reader reaches the bead
   through the convoy, as Gas City's own code does.

The cut deletes about 1,700 lines and adds about 220, in five units that reach
main as one PR (sections 9 and 11). The largest block that stays, about 2,600
lines that read a workflow's input convoy, retires only when Gas City records a
root's work bead.

What it costs:

- A finished convoy is taken at the refinery's next patrol iteration on its rig,
  which comes with the next work bead the rig hands the refinery.
- A member added without its `target` is declined at workspace-setup before any
  branch is cut, and waits on a visit that asks for the target.
- A member that builds on work reaching main after its convoy was seeded waits
  for the mechanik to bring the convoy's branch current.
- Ranking or parking a convoy no longer ranks or parks its members, because Gas
  City's tracking changes no parent and blocks nothing.
- A PR into a convoy's branch is marked only by GitHub's own display of its base.

Unchanged: every PR needs the operator's approval, and every PR has exactly one
owning bead (invariant I4), the issue or the convoy it came from.

## The model

The operator's words, from [brief.md](brief.md):

> "It's not about my approval being required on every PR. It's that a convoy can
> include multiple pieces of work, and that should all land as a single PR."

> "A PR has an issue or a convoy that it came from."

> "polecats self-review, so a defect in an early member is caught during the
> self-review. Big picture items aren't caught until later, but that's what the
> PR is looking for, not each individual step"

> "I believe the only thing I ever wanted to change in convoys was the default
> when landing on main of doing direct. PRs are the means for me to see what
> commits are being done."

> "I basically want to see ap roposal that effectively says, delete these
> thousands of lines because we're using Gas City convoys as the noun / verb."

The model, as the brief states it:

1. Every PR is the operator's. The city opens a PR, into main or into a convoy's
   branch, only to ask for the operator's review.
2. A PR comes from one issue or one convoy. Work that reaches the operator as one
   PR is a convoy, whose members land on its branch with no PRs of their own. A PR
   into main is a complete unit of work.
3. Each member is reviewed inside its own work molecule before its work lands. The
   PR gets the overall review.
4. The city works in as many internal phases as it needs before it opens a PR.
5. Multi-stage work is more than one PR. Every reviewable unit is a PR.
6. A convoy is Gas City's concept, used as Gas City defines it. Nothing in
   gc-toolkit may keep a convoy from working that way.
7. Work reaches main only through a PR. Whether any other branch needs a PR is set
   by the GitHub ruleset the operator defines for it.

The design's words are Gas City's. A **member** is a bead its convoy tracks. A
**stage** is a member the operator reviews on its own, through a PR into the
convoy's branch. A PR's **owning bead** is the issue or the convoy it came from,
which gc-toolkit's component model calls the anchor.

## What Gas City and Gas Town provide

Read on 2026-10-23 in Gas City's code and documentation as deployed (`gc` 1.4.3),
and in the Gas Town and build packs it bundles.

- **A convoy groups work and tracks it.** "A convoy is a container bead that
  groups related work so you track a batch as a unit" (Gas City's "How Gas City
  Works" page). Its membership is `tracks` edges from it to each member, and
  "Tracking is pure grouping: it changes no parent and blocks nothing" (its beads
  tutorial). `gc convoy add` adds "a tracks dependency from the convoy to the
  issue ... without changing the issue parent".
- **A convoy's target reaches only its children.** `gc convoy create --target` and
  `gc convoy target` record the "target branch inherited by child work beads".
  Sling branches a bead from its own `target`, else from the `target` of a convoy
  on its parent chain, else from the rig's default branch
  (`SlingFormulaTargetBranch` and `BeadMetadataTarget`, in Gas City's `sling`
  package). The key is unprefixed "so work beads can read their own value
  directly". A sling's `--var base_branch=` outranks that lookup for the one pour
  it starts, and sling has no flag that writes a target.
- **No verb creates a branch.** The two verbs above record a branch's name. Gas
  Town's `mol-idea-to-plan` formula stands an initiative up with
  `gc convoy create --owned`, names its branch `integration/<convoy-id>` with
  `gc convoy target`, and adds each task with `gc convoy add`. It creates no
  branch and writes no target on a task. Gas Town's `mol-polecat-work` branches
  each bead from `origin/<base_branch>`, which has to exist.
- **A merge strategy is the bead's own `merge_strategy`.** `direct` merges the
  work branch into its target, `mr` delivers it through a merge or pull request,
  and `local` leaves it on its branch with no merge and no request (Gas City's
  `beadmeta` package). An absent key is unset, and each consumer reads unset as
  its own default. Sling stamps the `--merge` it is given, or else the rig's
  `default_merge_strategy`, which applies to every bead the rig slings whatever
  its target. A convoy's `convoy.merge` and `convoy.notify` are recorded and
  printed, and nothing acts on either.
- **An owned convoy has a manual lifecycle.** `--owned` marks a "manual
  lifecycle, no auto-close". `gc convoy land` "verifies all children are closed
  ..., closes the convoy bead, and records a ConvoyClosed event", and moves no
  branch. A convoy that is not owned closes itself when its last member closes,
  through the bead store's `on_close` hook. Gas City's core pack runs
  `gc convoy check` hourly, in its `convoy-autoclose-backstop` order, for a close
  the hook missed.
- **Gas Town's refinery lands `direct` unless told otherwise.** It reads
  `merge_strategy` with `direct` as the default, turns `direct` into `mr` for a
  bead that carries an existing PR, and escalates `local`. It has no
  protected-branch detection and no PR fallback. A push the target refuses stops
  the merge step before any bead write, and the bead stays with the refinery for
  the next patrol to retry. With `integration_branch_auto_land` on, which it is
  not by default, its next-iteration step takes a finished owned convoy. After a
  landing on an integration branch, it lists the open convoys, and for each owned
  one with an integration branch whose children are all closed it assigns the
  convoy's bead to itself, with that branch as the bead's `branch` and the default
  branch as its `target`. The next iteration lands the bead like any work bead
  (Gas Town's `mol-refinery-patrol` formula).
- **A graph.v2 workflow takes a convoy as its input.** Slung on a bead, a graph.v2
  formula is poured over an input convoy that tracks the bead, and its root
  records the convoy as `gc.input_convoy_id`. Gas City deprecates the formula
  variable `issue` in favour of deriving the work bead from the input convoy
  (`LegacyIssueVar`, in its `graphv2` package), and Gas Town's `mol-polecat-work`
  and `mol-review-leg` derive it with `gc convoy status {{convoy_id}}`. The root
  carries no `gc.source_bead_id`, the key a legacy launch records, so Gas City's
  own walk from a bead to the workflow driving it goes through the convoys that
  track the bead, "the only durable link from a work bead back to a convoy-first
  workflow driving it" (`ListLiveInputConvoyRootsForConvoys`, in its
  `sourceworkflow` package).
- **The build pack drains a convoy and publishes once.** `build-from-convoy` runs
  each member in its own worker session and worktree, reviews the whole result,
  and can push and open one PR, with push and PR off by default. Its members
  commit in detached worktrees and push nothing (the build pack's README and its
  formulas).

## What gc-toolkit carries today

The census covers every tracked file outside `specs/` and `generated/` that
mentions a convoy, an `integration/` branch or graduation, at this branch's merge
of main 974f87e03. A file that exists only for convoys counts whole. Elsewhere a
line counts when it is within one line of a mention. By that method gc-toolkit
carries about 6,800 such lines in 158 files, 3,038 of them in the 11 files that
exist only for convoys. The sitting's census, which measured spans by hand,
counted about 7,800.

| What it is | Lines | Files | Under this design |
|---|---|---|---|
| Readers of a workflow's input convoy: the formulas' subject derivation, `step-close.sh --convoy`, the cadence's review dispatch, the liveness sweeps, priority following, the doctor checks, the helm board's facts | about 2,600 | 90 | kept under warrant 4, apart from two native calls (section 8) |
| `mol-design-convoy` and its tests, `docs/design-convoy.md`, and the convoy doctrine in the mechanik's prompt, the polecat doctrine and the `prs` skill | about 1,560 | 7 | rewritten onto Gas City's verbs (unit C). The drain step stays under warrant 4 |
| Graduation, its cadence wiring, and the `convoy-check` order | about 730 | 6 | deleted (unit B) |
| The helm board's convoy surfaces | about 630 | 19 | kept: a surface that renders Gas City's convoys (section 8) |
| `convoy-seed.sh`, its test, and the test of its call from `mol-design-convoy` | 480 | 3 | deleted (unit C) |
| The test of workspace-setup's convoy target guard | 425 | 1 | kept under warrant 2, and extended (unit D) |
| Mentions in docs and prompts | about 225 | 23 | corrected where a deletion makes them false |
| The integration banner and label | about 70 | 5 | deleted (unit E) |
| The refinery's merge strategy, the lifecycle registry, the proactive pool | about 60 | 4 | changed (unit A) |

The guard itself sits in `formulas/mol-polecat-work.toml`, which the census
counts with the readers. The window understates a block whose lines seldom name a
convoy, such as the label code, so section 9 measures each deletion by its
blocks.

## 1. The default, and the one line for main (unit A)

### Decision

Two changes to `formulas/mol-refinery-patrol.toml`:

1. `vars.default_merge_strategy` becomes `direct`.
2. The `merge-strategy-resolve` block gains one rule: a bead that would land
   `direct` on the rig's default branch resolves to `mr`. A bead with no `target`
   lands on the default branch, so it resolves to `mr` too. The default branch is
   the patrol's `target_branch`, which is main.

So:

- A member, whose target is its convoy's branch, lands there with no PR.
- A lone bead's work, a convoy's own landing, a rework of a PR into main, and a
  supplement to one all land on main, so each goes through a PR, as each does
  today.
- A member slung `--merge mr` is a stage, and opens a PR into its convoy's branch.
- A bead aimed at another PR's head that names no strategy lands on that head, so
  its work folds into that PR, as it does today.
- A bead aimed at any other branch lands as its strategy says. Whether that branch
  needs a PR is the GitHub ruleset the operator defines for it.
- A `local` bead stays `local` whatever its target, and the refinery refuses it
  as unsupported, as it does today.
- The rule that `existing_pr` forces `mr` stays as it is.

The refinery reads only the bead's own `merge_strategy`, and nothing reads a
convoy's `convoy.merge`. The one line is the only rule this design adds to Gas
City's meaning of a strategy.

### What else unit A changes

- **The fold-in flip goes.** Today the resolve block turns an `mr` bead aimed at
  another PR's head, with no PR of its own, into `direct`, so its work folds onto
  that head instead of opening a nested PR
  ([specs/tk-sw5bu](../tk-sw5bu/merge-strategy-fold-in.md)). The beads it exists
  for come from dispatches that name no strategy, and under the `direct` default
  they land on the head with no flip. The pack's scripts that stamp `mr` aim at
  main (`convoy-graduate.sh`, which unit B deletes, and the feedback distiller)
  or give a rework child its anchor's target (`rework-child.sh`, `pr-facts.sh`,
  `pre-open-rebase.sh`), and a bead that folds onto a head anchors no PR, so no
  child inherits that aim. An `mr` bead aimed at another PR's head then means a
  PR into it, as Gas City defines `mr`. The flip's variables, `MS_FOLD_IN`,
  `MS_BRANCH` and `MS_HAS_OWN_PR`, go with it.
- **The rejection arm's branch decision goes.** On a branch-caused rejection,
  `rejection-branch-keep` deletes the bead's branch when the bead resolves
  `direct` and records no PR. Under the `direct` default every member is such a
  bead, and the rebuild the same arm's repool starts resumes that branch, so the
  delete would stop every member whose gate fails at workspace-setup's
  missing-branch visit. Without the delete, every path through the decision keeps
  the branch, so the decision goes whole, with its copy of the resolve block.
  merge-push's copy is then the one reading of the strategy. A branch is still
  deleted when its work lands, by `delete_merged_branches` after a direct landing
  and by the repository's delete-on-merge after a PR.
- **The proactive pool's rule.** Its doctrine says code a reaction produces takes
  the gated `mr` path, never `direct`, and names two things that enforce it, the
  city's default and the pool's `GC_DEFAULT_MERGE_STRATEGY`. No rig sets the
  default, and nothing reads the variable, so the rule rests on the refinery's
  `mr` default, which this design changes. It holds in this form. Code a reaction
  writes carries `merge_strategy=mr` itself, as the pool's prompt already tells
  it to, so it opens a PR wherever it lands. Work a reaction routes is its
  subject's own, and lands by the subject's target like any bead's. Aimed at
  main, it goes through a PR by the one line. Aimed at a convoy's branch, it
  reaches main in the convoy's PR. So a reaction's code reaches main only through
  a PR. Unit A corrects the doctrine and removes the variable, its sentence in
  the prompt, and the fixture's check of it.
- **Words, tests and the warrant.** The `merge_strategy` entry in
  `lifecycle/lifecycle.toml`, the resolve block's comment, the `pr-stack.sh`
  comment, a line of `docs/refinery-merge-cadence.md`, and the tests in
  `mr-aware-rejection-failclosed.test.sh` change to match (section 11). Unit A
  adds warrant 1 to `docs/warrants.md`.

So the formula gains a default's value and one line, and loses the fold-in flip
and the rejection arm's branch decision.

### Why

- **The default is Gas Town's.** Gas City leaves an unset strategy to its
  consumer, and Gas Town's refinery reads it as `direct`. gc-toolkit's `mr`
  default is why a member opens a PR at all.
- **`mr` was only ever about main.** The default came from a moment when main's
  ruleset was off and the city pushed straight to main, which nobody intended,
  and the operator asked the pack to act as if main's ruleset were always on. PRs
  are how the operator sees what commits reach main, and nothing asked for any
  other branch to be held behind one. The last design read the default as
  protecting every branch work would reach with no review, and kept a PR for
  every branch but a convoy's and another PR's head. That reading was wrong, and
  its two exceptions go with it.
- **The ruleset enforces while it is on, and the line holds when it is off.**
  gc-toolkit's main carries a GitHub ruleset that requires a PR with one
  approval, squash merges only, and the checks `test` and `test-macos`, and it
  refuses a direct push from any writer. When it refuses one, gc-toolkit's
  `direct-merge-push.sh` promotes the bead to `merge_strategy=pr` and the
  refinery opens a PR instead, as it has since 2026-05-10. That is gc-toolkit's
  own fallback: Gas Town's refinery has none, and retries the refused push on
  every patrol. With the ruleset off, nothing refuses the push, which is how the
  city once pushed to main unintended. The line makes main behave as if its
  ruleset were always on.
- **Gas City cannot express it as config.** A rig's `default_merge_strategy` is
  stamped on every bead the rig slings, whatever its target, so `mr` there would
  open a PR for every member again. Gas City has no merge strategy per target
  branch.
- **It applies to `direct` alone.** `direct` is the only strategy that changes a
  branch without a PR. `mr` changes it through one, and `local` lands nothing.

### `local`

`local` leaves the work on its branch with no merge and no request, so it lands
nothing and the line does not apply to it. The resolver passes it through
unchanged, whatever its target. gc-toolkit's refinery has no landing for `local`,
so its merge-push step refuses it as unsupported, as it does today: it transitions
nothing and escalates the bead for a person to choose a strategy. Gas Town's
refinery stops on `local` and escalates it the same way. This design neither
slings `local` nor maps it onto another strategy.

## 2. Members are tracked, and carry their convoy's branch (units C and D)

### Decision

A convoy's members are added with `gc convoy add <convoy> <member>`, the way Gas
Town's planning formula adds them. The same step writes the convoy's `target` on
the member, reads the edge and the target back, and slings the member, or arms it
when it waits on other work. A member keeps whatever parent it has. The
mechanik's recipe and `mol-design-convoy` change to this, and neither writes a
parent-child edge to a convoy (unit C). workspace-setup's convoy target guard
reads the convoys that track a bead as well as its parents, so a member poured
without its target is declined before any branch is cut (unit D).

### Why

- **It is Gas City's membership.** A convoy groups its members without being their
  parent, so a member that belongs to an epic and to a convoy records two plain
  facts: one parent edge and one `tracks` edge. The parent-child link asks the one
  parent edge to carry both, which is why a member under an epic could be poured
  from main.
- **The target is Gas City's own key, in its own slot.** Sling and the refinery
  read a bead's own `target` first, and Gas Town's `mol-polecat-work` writes
  `target` on its work bead at submit. The write adds no key, no state and no
  reader.
- **It is written when the member is added, not when it is slung.** Sling has no
  flag that writes a target, and `--var base_branch=` sets only the variable of
  the pour it starts. A later pour, such as the re-sling a visit's close arms or a
  rework, reads the bead again, and would pour from main.
- **The readers that count a convoy's members already read `tracks`.** Gas City's
  `gc convoy status`, `gc convoy land` and auto-close read both forms, and so does
  the refinery's auto-land step, which reads members through `gc convoy status`
  (section 4).

The write stands in for sling resolving a target through `tracks`. That is the
first platform gap, warrant 2 in section 8. Gas Town carries the same gap: its
planning formula adds members with `gc convoy add` and writes no target on them,
so its members pour from the default branch.

### When the write is missed

A member added without its target would branch from main and land there. Its work
would reach the operator as a PR into main of its own, and the convoy's PR would
leave it out. workspace-setup's convoy target guard catches it before any branch
is cut. Today the guard reads only a bead's parent-child convoy parents. Under
this design it also reads the convoys that track the bead, with one read of the
bead's incoming `tracks` edges, whose rows carry each convoy's metadata. A member
poured from a branch that is not its convoy's target takes the guard's existing
decline: its run is cancelled before any worktree exists, and the member waits on
a visit that names the convoy and asks for the target. Stamping the target and
closing the visit re-slings the member, which then pours from the convoy's branch.

The guard counts only an open convoy that names a target, so the input convoy each
pour makes, which names none, is not read as membership. It reads Gas City's own
edge and key and files the visit it already files, so it adds no key, no state and
no claim of its own. The decline ends a run only for a member whose add skipped
the write, so a discarded run is the signal of a failure and never a step of
normal operation. A bead that has started records a branch, which the guard
resumes without checking, so a convoy adds only beads that have not started, as
both recipes do.

### What tracking changes in gc-toolkit

The readers that find a bead's convoy through its parent edge treat a convoy
parent like any other parent: `priority-lib.sh`, `hold-lib.sh`,
`converse-parent.sh`, `placement.sh`, `bead-context.sh` and the top-level test of
`tools/gc-proactive.sh`. None of them carries code of its own for a convoy
parent, so none changes. A tracked member has no convoy for a parent, so:

- A convoy's priority no longer ranks its members, and parking a convoy no longer
  holds its members' armed dispatches. A convoy's work is ranked and parked on its
  members, or on the epic they sit under.
- A sitting's follow-up from a member joins the member's epic, and joins the
  convoy only when the sitting adds it.
- `bead-context.sh` shows the convoy as tracking the member, not as its parent.
- The proactive scan reacts only to beads with no parent. It skips routed, armed
  and in-flight beads, and the recipes sling or arm a member in the step that adds
  it, so the scan does not reach one.

Making these readers treat a `tracks` edge as a parent would add semantics to a
native relation: tracking "changes no parent and blocks nothing".

## 3. Standing a convoy up: Gas City's verbs and one push (unit C)

### Decision

`convoy-seed.sh` goes. The mechanik's recipe and `mol-design-convoy`'s
seed-convoy step stand a convoy up with Gas City's verbs and one git act:

1. `gc convoy create <name> --owned` creates the convoy.
2. `gc convoy target <id> integration/<id>` names its branch. Gas Town's planning
   formula names it the same way.
3. One `git push` creates the branch on origin from the default branch's fetched
   tip, unless origin already has it. The push sends a ref and checks nothing out.

The third step is warrant 3: the cut is the one act no Gas City verb performs.

### What convoy-seed.sh carries, and where each part goes

| convoy-seed.sh | Under this design |
|---|---|
| Creates the owned convoy and sets its target | the recipe calls the same two verbs |
| Writes the convoy's id to a file before the steps that can fail, so a resumed run reuses the convoy | `mol-design-convoy` records the id on its subject as soon as the create returns, as it does today, and a resumed step reads it there. The mechanik reads the id the create printed |
| Cuts the branch in a throwaway worktree, so the rig root's checkout never moves | a ref push needs no worktree: it sends the fetched default-branch tip to the new branch's name |
| Skips the cut when origin already has the branch | the recipe asks origin for the branch first |
| Seeds a shared input artifact on the branch (`--artifact`), so the mechanik, which commits nothing else, can start the branch ahead of the default | goes. The artifact is the convoy's first member, which lands it on the branch like any member, and the members that need it wait on it with a `blocks` edge |

The script keeps no state of its own beyond the id file, so nothing else needs a
home.

### When a convoy's branch is brought current

A convoy's branch is cut from the default branch when the convoy is stood up. A
member that builds on work reaching main after that needs the branch brought
current first. That is a hand-off to the mechanik, not a member. The hand-off is a
task assigned to the mechanik, which waits on the outside work by a `blocks` edge,
and deferred dispatch's ready notice tells the mechanik when that work has landed.
The member that needs the branch current waits on the hand-off by a `blocks` edge,
and is armed to dispatch when the hand-off closes.

Once notified, the mechanik brings the branch current from a disposable worktree:
a fast-forward to main when the branch holds nothing main lacks, and a merge of
main into it when it does. It pushes the result and closes the hand-off, which
releases the member. No polecat builds the hand-off, so no self-review and no
refinery gate reads main's commits as its change. A merge that conflicts is not
mechanical: the mechanik pushes nothing and puts it to the operator with a visit.
The hand-off is a plain task, each wait is a `blocks` edge, and the act is the
mechanik's recipe, which is prose, so nothing is built for it.

When the convoy's bead lands, the refinery brings the branch current by merging
main into it, as it does every branch it prepares.

## 4. A finished convoy lands as Gas Town lands one (unit B)

### Decision

Graduation goes. gc-toolkit's refinery formula carries Gas Town's
`integration_branch_auto_land` variable, on by default here, and Gas Town's step
for it, in the next-iteration step:

- On every patrol iteration, the step reads the rig's open convoys labelled
  `owned` whose `target` is an integration branch.
- For each one whose members are all closed, as `gc convoy status` counts them,
  and whose bead carries no `branch` yet, it assigns the convoy's bead to the
  refinery, sets the bead's `branch` to the convoy's target and its `target` to
  the rig's default branch, and writes the bead's `pr_summary` from the summaries
  of the members that landed on the branch.
- Landing an integration branch any other way stays forbidden, as Gas Town's step
  forbids it.

The next iteration takes the convoy's bead like any work bead. It merges main into
the branch, runs the rig's gate, and resolves the bead to `mr` by the one line for
main. The cadence's checks review the whole branch, the PR opens, and `merge.sh`
lands it with the operator's approval, which closes the convoy's bead.

The step is prose the patrol agent runs, as Gas Town's is. Gas Town runs it after
a landing on an integration branch. gc-toolkit's refinery also lands PRs, in its
merge cadence, which no patrol step sees, so the step runs on every iteration. A
convoy whose last member lands through its own PR is then taken at the refinery's
next iteration, not left for an unrelated landing.

### What graduation carries, and where each part goes

| Graduation | Under this design |
|---|---|
| Takes an open owned convoy whose target is an integration branch | the same, as Gas Town's step takes one |
| Counts members in both forms, and a `tracks` edge to a bead it cannot read holds the convoy | `gc convoy status` counts a convoy's members as Gas City defines them |
| Requires a landing recorded on the branch, so a convoy whose members landed nothing does not graduate | the refinery's refusal of a branch that carries no change: it closes nothing, opens no PR, and asks a person, who ends the convoy with `gc convoy land` |
| Skips a convoy, or a bead on its branch, that carries `merge_hold` or `rebase_hold` | the hold is honored where it is for every PR's owning bead: no review dispatch, no PR, no merge. The patrol only merges main into the branch, which rewrites nothing |
| Skips a convoy whose branch a live bead already owns | the step takes only a bead that carries no `branch`, so it takes each convoy once |
| Stamps `merge_strategy=mr` | the one line for main resolves the bead to `mr` |
| Stamps `graduation=true` | nothing reads it. The key stays registered, as retired |
| Seeds the PR's summary from the landed members' summaries | the step writes `pr_summary` |
| Runs at most once per 15 minutes, with guards against a short read | the step runs once per patrol iteration, and a read that fails takes nothing, for the next iteration to retry |
| `REFINERY_RECONCILE_INTEGRATION_AUTO_LAND=false` turns it off | Gas Town's `integration_branch_auto_land` variable |

### Gas City's lifecycle verbs, where they fit

- An owned convoy that lands through its PR closes when the PR merges, as any PR's
  owning bead does. Gas Town's auto-land also closes the convoy's bead through its
  refinery's close of a work bead, not through `gc convoy land`.
- `gc convoy land` ends an owned convoy that will not reach main through a PR: one
  whose members closed with nothing landed, which the refinery refuses and puts to
  a person, or work the operator abandons. It is the native termination, and it
  moves no branch.
- A convoy that only groups work, with no branch of its own, is not owned, and
  closes itself when its last member closes. Gas City's core pack sweeps hourly
  for a close the hook missed, so gc-toolkit's `convoy-check` order, which runs
  the same command on the same interval, goes.

### Rejected: a cadence arm that makes Gas Town's assignment

A script in the merge cadence could make the same assignment on every pass,
deterministically. It would re-implement Gas Town's step as a pack script beside
the step that gc-toolkit's refinery can run as Gas Town wrote it, and it would
need a warrant for a primitive Gas Town already ships. The cost of the step is
the one stated above: a finished convoy waits for the next patrol iteration on its
rig.

## 5. Reviews, the convoy's PR, stages and rework

| Where | What runs | What it reads |
|---|---|---|
| Inside each member's molecule | the self-review loop of `mol-polecat-work`: a polecat in a fresh session reviews and fixes the diff, and the loop ends only when the rig's checks pass at its head | the member's own diff |
| At the refinery, before the member lands | the rig's gate on the prepared head | the member merged onto the convoy's branch |
| On the convoy's PR, before it opens | correctness and triage, and arch and pm when triage adds them | the whole branch against main |
| On the convoy's PR, while it is a draft | demo, when triage adds it | the PR |
| On the convoy's PR | the operator's approval, `merge.sh`'s universal rule | everything |

A member's defect is its own self-review's to catch. The convoy's PR is where the
big-picture items are caught, which is what the operator reviews it for. A member
closes when it lands, like any bead whose work is done.

The operator's review returns as a rework child that resumes the PR's branch, and
scope found while the PR is open rides a supplement on the same branch. A rework
child joins its anchor by a `related` edge and blocks it by a `blocks` edge, so it
never becomes a member of the convoy in Gas City's reading.

**Stages.** A stage is a member slung `--merge mr`. It opens its own PR into the
convoy's branch, the operator approves it, and it lands before the members that
wait on it. The design child of a design-gated `mol-design-convoy` is one, because
its PR is the design gate, so the formula slings it `--merge mr`. A stage built
from several beads would be a convoy that lands into another convoy's branch, and
auto-land carries every convoy to the default branch, so that shape is not built.

**The integration banner and label go** (unit E). Every PR into an integration
branch carries a `base: integration` label and a banner in its body that says
approving it "mints this phase into the convoy integration branch". Both render
the PR's base, which GitHub shows at the head of every PR, under a word the pack
coined. Under this design a PR into a convoy's branch is a stage the operator
asked for, so the label's writer in `pr-status-label.sh`, the banner in
`pr-summary-region.sh`, the calls to them in `pr-open.sh`, their tests, and the
section of `docs/state-machine.md` that describes them go. The label stays on the
PRs it already marks, and nothing adds it again.

## 6. The input convoy's readers

About 2,600 lines read a workflow's input convoy. They are the formulas' own
derivation of their subject, which `mol-polecat-work`, `mol-review`,
`mol-review-quorum-signoff`, `mol-validate`, `mol-validate-close`, `mol-rig-demo`
and `mol-design-convoy` run with `gc convoy status {{convoy_id}}`, and the pack's
tooling that walks from a root to its bead, or from a bead to the workflow driving
it:

- `step-close.sh --convoy`, which names a step's molecule;
- the cadence's review dispatch in `gate-ensure.sh`;
- `liveness-sweep.sh`, `liveness-sweep-precheck.sh` and `liveness-classify.sh`;
- `queue-priority.sh` and `priority-lib.sh`, where a workflow follows its subject's
  priority;
- `gc-helm.sh` and the helm board's facts;
- `tools/gc-proactive.sh`'s guard against a live workflow;
- `live-work.sh`, `until-resolved.sh`, `duplicate-sweep.sh`, `work-tree-holder.sh`,
  `self-review-check.sh` and `orphan-dispose.sh`;
- `doctor/check-root-advancing` and `doctor/check-blocked-work-armed`;
- `tools/gc-polecat-metrics.sh`, the work-context hook, and the gascity-keeper
  pack's `rebase-check.sh`;
- `mol-design-convoy`'s drain, which releases the input convoy from a subject that
  outlives its run, because `live-work.sh` counts a convoy that tracks a bead as
  live work;
- and their tests.

The derivation is Gas City's contract for a graph.v2 formula, which Gas Town's
formulas follow too, so it needs no warrant. The tooling reads the same link Gas
City's own code reads, because a graph.v2 root records its input convoy and not
its work bead. That is the second platform gap, warrant 4 in section 8. When a
root records its work bead, the tooling reads the root instead, and `live-work.sh`
asks whether an open root names the bead rather than whether a convoy tracks it,
so the drain's release goes too. This design deletes none of it.

## 7. The external-observer test

Someone who knows only Gas City and Gas Town watches a convoy that gc-toolkit runs.

| What they see | What Gas City or Gas Town does | Same? |
|---|---|---|
| A convoy bead created with `gc convoy create --owned`, its target set to `integration/<id>` with `gc convoy target` | Gas Town's `mol-idea-to-plan` stands an initiative up the same way | yes |
| A branch `integration/<id>` on origin, cut from main when the convoy is created | no verb creates a branch, and Gas Town's planning formula cuts none | added, warrant 3 |
| Members linked by `tracks` edges with `gc convoy add`, each keeping its own parent | the same verb and edge | yes |
| Each member's own `target` naming the convoy's branch | Gas City's own key, which sling reads first, and which Gas Town's polecat writes on its work bead | added, warrant 2 |
| Each member slung to a pool, wrapped by sling in a one-member input convoy | sling's own launch | yes |
| A member's work landed on `integration/<id>` by the refinery, with no PR | Gas Town's refinery lands `direct` by default | yes |
| A stage, slung `--merge mr`, opening a PR into the convoy's branch | `mr` as Gas City defines it | yes |
| Once every member is closed, the convoy's bead assigned to the refinery with `branch=integration/<id>` and `target=main` | Gas Town's `integration_branch_auto_land` | yes. gc-toolkit's step runs on every iteration, Gas Town's after a landing on an integration branch |
| The convoy's bead landing on main through a PR | Gas Town would land it `direct`. Main's ruleset would refuse the push, and Gas Town's refinery would retry it on every patrol | added, warrant 1 |
| The PR reviewed by the city's checks and the operator, merged, and the convoy's bead closed at the merge | not a convoy behavior: gc-toolkit's merge path does this for every PR | outside the convoy (below) |
| An owned convoy that ends without a PR, ended with `gc convoy land` | Gas City's lifecycle termination | yes |
| A convoy that only groups work closing itself when its last member closes, and core's hourly sweep for a missed close | Gas City's auto-close and its core pack's order | yes |
| A workflow's steps deriving their work bead with `gc convoy status {{convoy_id}}` | Gas Town's formulas do the same | yes |
| The helm board listing a convoy with its tracked members | a surface rendering Gas City's objects | yes, apart from two misreadings filed apart (section 8) |

So gc-toolkit uses Gas City's convoys as they are intended to be used. The
observer sees three additions, each under a warrant: the cut of the convoy's
branch, the `target` on each member, and the one line that keeps main behind a
PR. What they see beyond the convoy (the PR's owning bead, the city's checks, the
operator's approval, a bead closing when its PR merges) is gc-toolkit's merge
path, the same for every PR. Moving that path onto Gas Town's refinery is the
merge member of the migration epic (tk-1tfzr71.20), and this design adds nothing
to it.

## 8. What stays, and the warrant for each

Each warrant says why the piece exists, the feature it carries, and what Gas City
would have to ship to retire it. Units A and D add them to `docs/warrants.md` in
that page's own format, which cites the upstream commits a verification read.

### Warrant 1: the one line for main

- **Covers:** the rule in `merge-strategy-resolve`, in
  `formulas/mol-refinery-patrol.toml`, that resolves a bead landing `direct` on
  the default branch to `mr`.
- **Why it exists:** main's ruleset refuses a direct push while it is on, and
  gc-toolkit's refinery then opens a PR. While it is off nothing refuses the
  push, and the city once pushed to main unintended in such a window. Gas City
  cannot say "main lands through a PR" in config: a rig's
  `default_merge_strategy` covers every bead the rig slings, and there is no
  strategy per target branch. Gas Town's refinery has no PR fallback at all.
- **Feature:** a change reaches main only through a PR, which is how the operator
  sees what commits reach main, whether or not main's ruleset is on.
- **Retires when:** Gas City can set a merge strategy for a target branch, so the
  rule becomes a line of the rig's config.
- **Recorded:** 2026-10-23.

### Warrant 2: a member's target, and the guard that catches a missing one

- **Covers:** the target write in the mechanik's recipe and in
  `mol-design-convoy`'s arm steps, workspace-setup's convoy target guard in
  `formulas/mol-polecat-work.toml`, and the guard's test.
- **Why it exists:** sling's target lookup walks a bead's parent chain only
  (`BeadMetadataTarget`), so a member a convoy only tracks inherits nothing and
  pours from the default branch. Gas Town's planning formula adds members the same
  way and writes no target on them.
- **Feature:** a member branches from its convoy's branch and lands there.
- **Retires when:** sling resolves a target through `tracks` membership. Then the
  recipes stop writing it, and the guard has nothing left to catch.
- **Upstream ask:** that sling resolve a bead's target through the convoys that
  track it. Unit D parks the request for the operator with `upstream-finding.sh`.
- **Recorded:** 2026-10-19, re-verified 2026-10-23.

### Warrant 3: the cut of a convoy's branch

- **Covers:** the one `git push` in the mechanik's recipe and in
  `mol-design-convoy`'s seed-convoy step.
- **Why it exists:** `gc convoy create --target` and `gc convoy target` record a
  branch's name, and nothing creates the branch. Gas Town's `mol-polecat-work`
  branches from `origin/<base_branch>`, which has to exist.
- **Feature:** a convoy's members have a branch to land on.
- **Retires when:** a convoy verb creates its target branch, or sling or the
  refinery creates a missing target branch from the default branch.
- **Recorded:** 2026-10-23.

### Warrant 4: the readers of a workflow's input convoy

- **Covers:** the tooling section 6 lists, and `mol-design-convoy`'s drain.
- **Why it exists:** Gas City launches a graph.v2 workflow on a bead through an
  input convoy that tracks the bead, and the root records the convoy and not the
  bead. Code that holds a root reaches the bead through the convoy, and code that
  holds a bead reaches the workflow driving it through the convoys that track it,
  as Gas City's own code does.
- **Feature:** a step finds the bead it works on and the molecule it closes; the
  cadence counts a review's workflows; the liveness sweeps, the doctor checks and
  the helm board tell a worked bead from a stranded one; a workflow follows its
  subject's priority; `mol-design-convoy`'s subject closes when its convoy lands.
- **Retires when:** a graph.v2 root records the work bead it was launched on. The
  formulas' own derivation is Gas City's contract and stays.
- **Upstream ask:** that a graph.v2 root launched on a bead record that bead. Unit
  D parks the request with `upstream-finding.sh`.
- **Recorded:** 2026-10-23.

### What stays without a warrant

- **`mol-design-convoy` and the mechanik's recipe.** A formula and a prompt, which
  the four tests leave free. Their convoy calls are Gas City's verbs, and their
  two acts beyond the verbs are warrants 2 and 3. The formula's markers on its
  subject record what each step created, so a step that runs again does not
  create twice.
- **The helm board's convoy surfaces.** A surface renders Gas City's convoys and
  their tracked members, which the fourth test permits. The board misreads two
  things, each filed apart: it reads Gas City's `owned` label as "has an owning
  bead" (tk-vlg4ihb), and it tells a machine convoy by its title (tk-y4820m2).
- **The parent readers** of section 2, which carry no convoy code.
- **Two calls around Gas City's launch.** `deferred-dispatch.sh` caps the retries
  of a sling that keeps failing, because each launch mints an input convoy, and
  `run-cancel.sh` ends a run with Gas City's `gc convoy delete` on its root. Both
  compose native calls.
- **Prose and fixtures.** Docs and prompts that describe Gas City's convoys are
  prose, which the four tests leave free, and the units correct each sentence
  their deletions make false (section 10). Tests that name an `integration/`
  branch to show a behavior holds for any branch shape test that behavior, not a
  convoy.

## 9. The deletion map

Measured at this branch's merge of main. A file deleted whole counts exactly; a
block counts its lines as they stand.

| Unit | Deletes | Adds | Net |
|---|---|---|---|
| A. The default and the one line | `rejection-branch-keep` (52), the fold-in flip (19), `GC_DEFAULT_MERGE_STRATEGY` with its prompt sentence and fixture check (7), the test's branch-decision section (about 145) | the one line (about 4), the resolve block's test cases (about 35), warrant 1 (about 12) | about -170 |
| B. Landing | `convoy-graduate.sh` (321), its test (305), `orders/convoy-check.toml` (31), arm 8 with its target lookup and switch (21), their test cases (about 15), graduation's paragraphs and rows in the docs (about 20) | Gas Town's variable and step (about 25) | about -690 |
| C. Recipes on Gas City's verbs | `convoy-seed.sh` (158), its test (180), `mol-design-convoy-seed-invoke.test.sh` (142), the seed call in `mol-design-convoy` (about 34), the mechanik's seed call and its artifact prose (about 20), `docs/design-convoy.md`'s seed-script section (about 19) | the two verbs and the push in both recipes (about 16), the add, read-back and target write in the arm steps (about 8), the arm test's cases (about 15) | about -515 |
| D. The guard, the warrants, the asks | nothing | the guard's read of tracking convoys (about 15), its test cases (about 40), warrants 2 to 4 (about 50) | about +105 |
| E. The banner and label | `pr-status-label.sh`'s `base:` group (about 55) and its test section (about 45), the banner (about 17), `pr-open.sh`'s calls (8) and its banner cases (about 52), `docs/state-machine.md`'s base label section (47) | nothing | about -225 |
| **All** | **about 1,700** | **about 220** | **about -1,490** |

What stays, and why, is section 8. The rewrites of `mol-design-convoy`, the
mechanik's doctrine and `docs/design-convoy.md` change words and calls in place,
and section 10 lists them.

The last design left graduation and the integration-branch flow to the migration
epic. Each piece now has a disposition here:

- Graduation, with its arm, its test and its wiring, is deleted (unit B).
- `convoy-seed.sh` and both of its tests are deleted, and `mol-design-convoy`'s
  seed-convoy step calls Gas City's verbs instead (unit C).
- The `base: integration` banner and label, their tests and their section of
  `docs/state-machine.md` are deleted (unit E).
- `mol-design-convoy`'s drain step and `mol-design-convoy-subject-close.test.sh`
  stay, under warrant 4: the drain releases the input convoy from a subject that
  outlives its run.
- `docs/design-convoy.md` is rewritten for the native recipe (unit C).
- workspace-setup's convoy target guard stays under warrant 2, and reads tracking
  convoys too (unit D).

## 10. What to correct

Each row says what a living file asserts today and what it says under the design.
Each unit that edits a prompt or a formula regenerates its pages under
`generated/seed-audit/`. Specs are records and are not edited.

| File | Says today | Says under the design | Unit |
|---|---|---|---|
| `formulas/mol-refinery-patrol.toml`, `default_merge_strategy` and merge-push's `merge-strategy-resolve` | the default is `mr`; an `mr` bead aimed at another PR's head with no PR of its own flips to `direct`, recorded in `MS_FOLD_IN`; the comment calls the block the one reading that the step keeping a branch and the step opening a PR share | the default is `direct`; a bead that would land `direct` on the default branch resolves to `mr`; `local` passes through; the flip and its variables go; the comment names merge-push as the block's one reader | A |
| `formulas/mol-refinery-patrol.toml`, handle-failures' `rejection-branch-keep` | decides from its own copy of the resolve block whether a rejected bead's branch survives, and deletes it for a `direct` bead that records no PR | goes whole: a rejected branch is kept in every mode, because the repooled rebuild resumes it | A |
| `lifecycle/lifecycle.toml`, `merge_strategy` | an absent key resolves to `mr`; a `polecat/` target with no PR of its own resolves from `mr` down to `direct` | an absent key resolves to `direct`; a bead that would land `direct` on the default branch resolves to `mr`; the fold-in sentence goes | A |
| `assets/scripts/pr-stack.sh` header, and `docs/refinery-merge-cadence.md` | a `merged_target` row "landed its own PR into it" | it landed on the branch, with or without a PR of its own | A |
| `agents/proactive/PROVENANCE.md` item 3, `prompt.template.md` "mr-only for Code", `agent.toml` `[env]`, the header of `tools/gc-proactive.sh`, `tools/proactive-first-reaction-fixture.sh` | the invariant rests on the city's `mr` default and on `GC_DEFAULT_MERGE_STRATEGY`, which nothing reads | code a reaction writes carries `merge_strategy=mr`, and work it routes lands by its target and reaches main only through a PR; the variable, its sentence and the fixture's check go | A |
| `docs/warrants.md` | no entry for the line | warrant 1 | A |
| `assets/scripts/convoy-graduate.sh`, its test, `orders/convoy-check.toml` | graduation; a second hourly `gc convoy check` | deleted | B |
| `assets/scripts/refinery-reconcile.sh` and its test, `orders/refinery-reconcile.toml` | arm 8 graduates convoys, with its target lookup and the `REFINERY_RECONCILE_INTEGRATION_AUTO_LAND` switch | the arm, its target lookup and the switch go, and the arm lists drop it | B |
| `formulas/mol-refinery-patrol.toml`, header, prepare step and next-iteration | convoy graduation is the reconcile order's; "a graduation bead" is a branch shape | Gas Town's `integration_branch_auto_land` variable and its step in next-iteration; the header and the prepare step name a convoy's bead | B |
| `lifecycle/lifecycle.toml`, `graduation`, `target`, `merge_strategy` and `rebase_hold` | `convoy-graduate.sh` writes `graduation`, `target` and `mr`, and honors `rebase_hold` | `graduation` stays registered, as retired; the refinery's step writes `target` on a convoy's bead; the other mentions go | B |
| `agents/refinery/prompt.template.md` | "a graduated convoy arrives as an ordinary mr-mode work bead"; the cadence runs convoy graduation | a finished convoy's bead is taken by the patrol's auto-land step; the cadence's list drops graduation | B |
| `docs/refinery-merge-cadence.md`, `docs/state-machine.md`'s convoy graduation, `docs/component-model.md`'s Convoy row and its rows for `convoy-graduate.sh` and `convoy-check.toml`, `docs/review-correctness.md`'s example | graduation is cadence arm 8 and a transition on the convoy bead; without convoys "integration branches cannot graduate"; a pack order beside core's; the loop-input example cites `convoy-graduate.sh` | the patrol's auto-land step; "an integration branch cannot reach main"; the two rows go; the example cites another script | B |
| `services/helm/internal/board/derive.go` and its test | a finished convoy's row reads "all N closed — graduate" | it reads that the refinery takes it at its next patrol | B |
| the comment in `services/gctk/cmd/gctk/main.go` | lists convoy-graduate among the cadence's scripts | the list drops it | B |
| graduation fixtures in `pr-facts.test.sh` and `pre-open-rebase.test.sh`, a comment in `deferred-dispatch.test.sh` | a graduation bead | a convoy's bead | B |
| `assets/scripts/convoy-seed.sh`, its test, `mol-design-convoy-seed-invoke.test.sh` | the seed script and its tests | deleted | C |
| `formulas/mol-design-convoy.toml` | seed-convoy runs `convoy-seed.sh`; arm-design and arm-implementation link each child with a parent-child edge, read it back and rely on it for the target; the design child is slung with no merge flag; graduation carries the convoy to main | seed-convoy calls the two verbs and pushes the branch; each child is added with `gc convoy add`, the `tracks` edge is read back, and the convoy's target is written on it; the design child is slung `--merge mr` when design-gated; the convoy's PR carries it to main | C |
| `assets/scripts/mol-design-convoy-arm.test.sh` | pins the parent-child link and its read-back | pins the add, the `tracks` read-back, the target write, and the design child's `--merge mr` | C |
| `agents/mechanik/prompt.template.md`, the dispatch doctrine and its recipe | "an owned convoy is the PR unit"; a lone bead is the one-child convoy; `convoy-seed.sh` with `--artifact`; each child linked parent-child; graduation | A PR comes from one bead or one convoy, and a lone bead needs no convoy. The recipe stands a convoy up with the two verbs and one push, adds each member with `gc convoy add`, writes the target, reads both back, and slings it with no merge flag. A stage is slung `--merge mr`. A shared input artifact is the first member. A member that builds on work reaching main after the cut waits on the mechanik's hand-off. A convoy's work is ranked and parked on its members. An owned convoy that ends without a PR is ended with `gc convoy land` | C |
| `template-fragments/polecat-doctrine.template.md`, integration branches | a child carries the target "which the owned-convoy recipe stamps when it links the child"; graduation | a member carries its convoy's branch as its target, written when it is added; the convoy tracks it and is not its parent; without the target, workspace-setup declines the run; the member's work lands on the branch with no PR unless it is a stage | C |
| `skills/prs/SKILL.md`, supplements | a supplement's target under an owned convoy is `integration/<convoy-id>` | that holds for a stage's PR, and a convoy's own PR targets main | C |
| `docs/design-convoy.md` | the seed script; each child's PR needs the operator's approval; graduation | the two verbs and one push; the design child is a stage, the implementation lands with no PR, and the convoy's PR is the second gate; all-in-one has one PR, the convoy's | C |
| `formulas/mol-polecat-work.toml`, workspace-setup's convoy target guard, and its test | reads a bead's parent-child convoy parents only | reads the convoys that track the bead as well, with cases for a tracked member | D |
| `docs/warrants.md` | no convoy entry | warrants 2, 3 and 4 | D |
| `assets/scripts/pr-status-label.sh` and its test | the `base:` group and its `mark-base` verb | they go, and the `status:` group stays | E |
| `assets/scripts/pr-summary-region.sh` | a banner on a PR into `integration/*` | it goes | E |
| `assets/scripts/pr-open.sh` and its test | calls `mark-base` at create and at adoption; pins the banner and the label | the calls and the cases go | E |
| `docs/state-machine.md`, the base label section | the `base:` label and the banner | it goes | E |
| `docs/epics.md`, "A checkpoint is always qualified" | a PR Checkpoint "lands a phase of work on a convoy's integration branch" | it lands a stage on a convoy's branch | E |

What stays as it is: the anchor and I4 in `docs/component-model.md`, with
`doctor/check-one-anchor-per-pr`, since a member never owns a PR; `merge.sh`'s
approval rule; the rule that `existing_pr` forces `mr`; the parent readers of
section 2; the one-bead input convoy of `mol-polecat-work`; and the readers of
section 6.

## 11. The implementation cut

The fix cannot use itself. Until it reaches main the refinery's default is still
`mr`, so the implementation runs by hand. One owned convoy, on
`integration/<convoy-id>`, holds one member for each unit below. Each member is
added with `gc convoy add`, carries the convoy's target, and is slung
`--merge direct`. Main's graduation counts `tracks` members, and main's guard
passes a member that carries its own target, so the convoy reaches main as the one
PR the operator reviews.

| Unit | What it changes | Its tests | Waits on |
|---|---|---|---|
| A. The default and the one line | `default_merge_strategy` and merge-push's `merge-strategy-resolve` in `formulas/mol-refinery-patrol.toml`, whose `rejection-branch-keep` goes; the `merge_strategy` entry of `lifecycle/lifecycle.toml`; the `pr-stack.sh` comment and the `docs/refinery-merge-cadence.md` line; the proactive pool's `PROVENANCE.md`, prompt, `agent.toml`, `tools/gc-proactive.sh` header and fixture; warrant 1 | `mr-aware-rejection-failclosed.test.sh`, as listed below; `tools/proactive-first-reaction-fixture.sh`; `render-seed-audit.sh --check` | nothing |
| B. Landing | deletes `convoy-graduate.sh`, its test and `orders/convoy-check.toml`; arm 8 out of `refinery-reconcile.sh`, its test and its order; Gas Town's variable and step in `mol-refinery-patrol.toml`; `graduation` registered as retired in `lifecycle/lifecycle.toml`; the refinery's prompt; the docs, helm and gctk rows of section 10 | `refinery-reconcile.test.sh` without arm 8; the helm board's tests; `render-seed-audit.sh --check` | A |
| C. Recipes on Gas City's verbs | deletes `convoy-seed.sh`, its test and `mol-design-convoy-seed-invoke.test.sh`; `mol-design-convoy`'s seed-convoy, arm-design and arm-implementation; the mechanik's doctrine and recipe; the polecat doctrine's paragraph; the `prs` skill; `docs/design-convoy.md` | `mol-design-convoy-arm.test.sh`; `mol-design-convoy-subject-close.test.sh`; `skill-needs.test.sh`; `render-seed-audit.sh --check` | nothing |
| D. The guard, the warrants, the asks | workspace-setup's convoy target guard in `mol-polecat-work.toml`; warrants 2 to 4 in `docs/warrants.md`; the two upstream requests, parked with `upstream-finding.sh` | `workspace-setup-convoy-target-guard.test.sh`; `render-seed-audit.sh --check` | A and C |
| E. The banner and label | `pr-status-label.sh`, `pr-summary-region.sh`, `pr-open.sh`; the base label section of `docs/state-machine.md`; the checkpoint sentence of `docs/epics.md` | `pr-status-label.test.sh`; `pr-open.test.sh` | nothing |

Each unit is one concern a reviewer can hold. A, C and E start together. B waits
on A, because both edit the refinery formula, its generated page and the
lifecycle registry's `merge_strategy` entry. D waits on A and C, because its
entries follow A's in the warrant register and cover C's recipes. Each wait is a
`blocks` edge with an armed dispatch. The default, the landing and the words reach
main together, in the convoy's one PR, so no design-convoy is poured between a
default that would land its design child with no PR and the `--merge mr` that
keeps the design gate.

Until unit A reaches main, the refinery still deletes a direct member's branch
when its gate fails because of the branch, and the rebuild stops at the
missing-branch visit. The release is to restore the branch from the member's
worktree, or to clear `metadata.branch` so the rebuild starts again from the
convoy's branch.

When the convoy's PR merges, graduation leaves main in the same commit that brings
the patrol's step. A convoy that graduation already took carries a `branch`, which
the step skips. One it has not taken is taken by the step, whose member count
reads both forms of membership, so a convoy in flight with parent-child members is
carried too.

The units are filed from this table as it reads on main, once this design merges
(tk-zkft1ym), so a change made in this design's review leaves no filed bead
describing an older cut. They take over the graduation and integration-branch
scope of the migration epic's convoy member (tk-1tfzr71.23), whose remaining
scope, the parent readers, carries no convoy code.

### Unit A's tests

`assets/scripts/mr-aware-rejection-failclosed.test.sh` pins the merge strategy and
the rejection arm. Its harness fills in the formula's default as `${2:-mr}`, so
that default moves to `direct` with the formula's.

- **The rejection arm goes, and so does the section that runs it:** the arm's
  extraction, its `git` stub and its `arm` helper, and cases (6) to (21). One
  check replaces them: the handle-failures step deletes no branch.
- **The resolve block, run on its own.** A bead aimed at `integration/cv-1`
  resolves to `direct` when it names no strategy or `direct`, and to `mr` when it
  names `mr`, a stage. A bead aimed at `polecat/tk-anchor` resolves to `direct`
  when it names no strategy, and to `mr` when it names `mr`, since the flip is
  gone. A bead aimed at `main`, or at no target, resolves to `mr` whether it names
  `direct` or no strategy. A bead aimed at `release/x` resolves to `direct` when it
  names no strategy or `direct`. `pr` resolves to `mr`. A `local` bead stays
  `local` aimed at `main`, at no target, and at `integration/cv-1`. A bead aimed at
  `polecat/tk-anchor` with its own `existing_pr` still resolves to `mr`, through
  merge-push's `existing_pr` rule, which that case runs after the block.
- **One reading.** The resolve block has one call site left, merge-push's, so the
  check that counts call sites expects one, and the check that two copies are
  byte-identical goes. The check that no step reads `merge_strategy` outside the
  block stays.
