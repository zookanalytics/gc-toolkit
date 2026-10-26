---
name: A PR is one reviewable unit, delivered by one landing bead per integration branch — the design
description: The design for the operator's PR model, rebuilt on the operator's ruling of 2026-10-24. Each bead carries its own branch in its own target. One ordinary landing bead per integration branch waits on the effort's beads and carries that branch to main through the one PR, and a summary task writes that PR's summary from the finished branch. A convoy is optional status and carries no branch. Work reaches main only through a PR. The design measures the convoy code the pack carries; deletes graduation, the seed script, a duplicate order, the workspace-setup target guard, the integration banner and label, the refinery's fold-in and branch delete, and mol-design-convoy's drain; puts 21 copies of one lookup behind one shared reader; keeps one warrant, the rule for main; moves the open convoys that carry a branch today; and cuts the work into six units. Read it to review the model and the deletions before they are built, or to build one of its units. Its inputs are brief.md and findings.md beside it.
---

# A PR is one reviewable unit: each bead carries its branch, and a landing bead carries the branch to main

## The proposal, in one screen

Today a bead that names no merge strategy opens its own PR, because
gc-toolkit's refinery delivers such a bead through a PR. An effort of seven
changes reaches the operator as seven PRs into its branch and an eighth into
main. The branch those seven land on lives on an owned convoy, and Gas City
builds a convoy as a status grouping that many convoys share per bead. So
gc-toolkit carries code that makes a convoy do what Gas City does not build it
to do: hand its branch to its work, notice when that work is done, and land.

Under this design:

- Each bead carries its own branch in its own `target`, written in the create
  that files it for an integration effort. Nothing inherits a branch.
- One ordinary landing bead per integration branch names the branch, waits on
  the effort's beads through `blocks` edges, reaches the refinery when they
  close, and opens the one PR into main.
- The effort's summary task, an ordinary bead on Gas City's report formula,
  runs once the effort's beads have landed. It writes the PR's summary on the
  landing bead from the finished branch, and its close releases the landing
  bead to the refinery.
- The effort's beads land on its branch with no PR of their own, unless the
  operator asks to review one on its own.
- A convoy may still track an effort for status. It carries no branch.

**Deleted, about 2,700 lines net** (section 9 measures each unit): graduation
and its cadence arm; the hourly `convoy-check` order, which duplicates one in
Gas City's core pack; `convoy-seed.sh`; workspace-setup's convoy target guard;
`mol-design-convoy`'s drain and the `until` edge it serves; the
`base: integration` banner and label; the refinery's fold-in flip and its
rejection arm's branch delete; and 21 copies of one lookup, which become calls
to one shared reader.

**Changed.** The refinery's default becomes `direct`, as Gas Town's is, and one
line keeps main behind a PR. The refinery takes, and the witness and the doctor
watch, only work that nothing holds, so a landing bead waits with the refinery
until its effort is done. The recipes stand an effort up with one push, a
landing bead, three writes per bead and a summary task.

**Kept under a warrant:** only the line for main (section 8).

**One departure from the ruling's letter, for the operator to confirm.** The
ruling named four pieces as duplicates to delete. Read against the code, three
of them do more than their Gas City counterpart: `step-close.sh`'s `--convoy`
route names a molecule that no formula can name another way, the review
cadence's double-pour check also routes a stranded review to its liveness judge,
and `work-tree-holder.sh` has no counterpart in Gas City as released. The design
keeps the three and moves their lookups onto the shared reader. The fourth,
`mol-design-convoy`'s drain, goes (section 6).

What it costs:

- A bead filed for an effort without its `target` lands on main through a PR of
  its own, outside the effort's PR. The operator sees it as a separate PR.
  Nothing declines it before it is built.
- A bead filed without the landing bead's wait can land on the branch after the
  landing bead has gone to the refinery. While the PR is open its work rides the
  PR. After the PR merges, it lands on a branch nothing carries to main.
- Each effort carries one more bead, its summary task, and a polecat's report
  run to write the PR's summary, where graduation composed one from the landed
  beads' own summaries. A bead filed without the summary task's wait can land
  after the summary is written. The pre-open correctness check, which reads the
  summary against the whole branch, then sends it back for a rework.
- A finished effort reaches the refinery after its summary task has run. The
  deferred-dispatch order on its rig, on a 5-minute cooldown, slings the task
  after the last bead lands and sends the landing bead's notice after the task
  closes. Gas City starts a stopped refinery as soon as the bead is ready.
  Graduation ran at most once every 15 minutes.
- A handoff slung past an open blocker of its own now waits at the refinery
  until that blocker closes, which is what its edge says.
- Ranking or parking an effort reaches its beads and its summary task through
  their epic, not through a convoy. A park that stands when the effort's last
  bead lands holds the summary task, so the effort reaches the refinery once the
  park lifts. Graduation took a finished convoy even under a park.
- No recipe makes a convoy, so an effort has no convoy row on the helm board.
- Each open convoy that carries a branch today is moved to a landing bead once
  (section 10). An operator's `merge_hold` or `rebase_hold` on one becomes a
  gate the landing bead waits on, which the operator closes to release the
  effort.

Unchanged: every PR needs the operator's approval, and every PR has exactly one
owning bead (invariant I4), the bead it came from. For an effort that is its
landing bead.

## The model

The operator's words, from [brief.md](brief.md):

> "It's not about my approval being required on every PR. It's that a convoy can
> include multiple pieces of work, and that should all land as a single PR."

> "polecats self-review, so a defect in an early member is caught during the
> self-review. Big picture items aren't caught until later, but that's what the
> PR is looking for, not each individual step"

> "I believe the only thing I ever wanted to change in convoys was the default
> when landing on main of doing direct. PRs are the means for me to see what
> commits are being done."

> "bail, each bead carrys its branch, landing bead per integration, and could
> still be tracked under a convoy for our own purposes. But the convoy does not
> enforce the branch."

The model, as the brief states it:

1. Every PR is the operator's. The city opens a PR, into main or into an
   integration branch, only to ask for the operator's review.
2. A PR comes from one bead. Work that reaches the operator as one PR is an
   integration effort: its beads land on its branch with no PRs of their own,
   and one landing bead carries the branch to main through the PR. A PR into
   main is a complete unit of work.
3. Each bead is reviewed inside its own work molecule before its work lands.
   The PR gets the overall review.
4. The city works in as many internal phases as it needs before it opens a PR.
5. Multi-stage work is more than one PR. Every reviewable unit is a PR.
6. A bead carries its own branch. A bead filed for an integration effort
   carries the effort's branch from the moment it is filed.
7. A convoy is Gas City's status grouping. It may track an effort's beads, and
   it carries nothing a bead needs to do its work.
8. Work reaches main only through a PR. Whether any other branch needs a PR is
   set by the GitHub ruleset the operator defines for it.

The design's words: an **integration effort** is the beads that land on one
integration branch. Its **landing bead** is the ordinary bead that carries that
branch to main, and its **summary task** is the ordinary bead that writes the
landing bead's PR summary once the effort's work has landed. A **stage** is a
bead of an effort that the operator reviews on its own, through a PR into the
branch. A PR's **owning bead** is the bead it came from, which gc-toolkit's
component model calls the anchor.

## What Gas City and Gas Town provide

Read on 2026-10-24 in Gas City as deployed (`gc` 1.4.3), and in the Gas Town
and build packs it bundles.

- **A convoy is a status grouping.** "A convoy is a container bead that groups
  related work so you track a batch as a unit" (Gas City's "How Gas City Works"
  page). Its membership is `tracks` edges, and "Tracking is pure grouping: it
  changes no parent and blocks nothing" (its beads tutorial). Its readiness
  leaves convoys out of ready work, as "never actionable Ready work"
  (`readyExcludeTypes`, in its `beads` package). Many convoys track one bead:
  `gc sling` wraps the bead it starts in a convoy, each graph.v2 run takes an
  input convoy that tracks its bead, and any person can group beads.
- **A convoy's target reaches only its children, and members are not
  children.** `gc convoy target` says "Child work beads can inherit this target
  branch". Sling branches a feature-branch formula's bead from its own `target`,
  else from the `target` of a convoy on its parent chain, else from the rig's
  default branch (`BeadMetadataTarget`, in its `sling` package). Since
  2026-05-21, `gc convoy add` and sling's wrapper convoy link by `tracks` edges
  and leave a bead's parent alone, so a tracked member inherits nothing. The
  beads tutorial now says both that members "are not children of the convoy"
  and that `target` is "inherited by child beads".
- **A bead's own `target` is read first.** Sling reads it before any parent,
  Gas Town's `mol-polecat-work` writes it on its work bead at submit, and a
  refinery lands a bead on it.
- **No verb creates a branch.** `gc convoy create --target` and
  `gc convoy target` record a name. Gas City's notes for its Gas Town example
  leave integration branches to packs ("git workflow + bead metadata —
  gastown-gc helper territory, not SDK primitive"), and no pack Gas City
  bundles creates one. The original Gas Town's `gt mq integration create` cut
  the branch from the rig's default branch, and its guide said "Create the
  integration branch *first*, before slinging any child work". A polecat
  branches from `origin/<base_branch>`, which has to exist.
- **A merge strategy is the bead's own `merge_strategy`.** `direct` merges the
  work branch into its target, `mr` delivers it through a merge or pull request,
  and `local` leaves it on its branch with no merge and no request (its
  `beadmeta` package). An absent key is unset, and each consumer reads unset as
  its own default. Sling stamps the `--merge` it is given, or else the rig's
  `default_merge_strategy`, which applies to every bead the rig slings whatever
  its target.
- **An owned convoy has a manual lifecycle.** `gc convoy land` ends one: it
  checks that the tracked beads are closed, closes the convoy and records an
  event, and moves no branch. A convoy that is not owned closes itself when its
  last tracked bead's close reaches the controller, and the core pack's hourly
  `convoy-autoclose-backstop` order runs `gc convoy check` for a close the
  controller missed. `gc convoy close` closes a convoy whatever its beads'
  status.
- **Gas Town's refinery lands `direct` unless told otherwise.** It has no
  protected-branch detection and no PR fallback. With
  `integration_branch_auto_land` on, which it is not by default, it assigns a
  finished owned convoy's bead to itself after a landing on the integration
  branch, and lands that bead like a work bead. That makes the convoy the unit
  of work Gas City's readiness says it is not.
- **A pour slung at a convoy works on the convoy's beads.** A graph.v2 formula
  slung at a bead runs over a one-item input convoy that tracks it. Slung at a
  convoy, it takes that convoy as its input (`NormalizeInputConvoy`, in its
  `graphv2` package). So a rebuild poured at a convoy's bead works on the
  convoy's members, and a rebuild poured at an ordinary bead works on that bead.
- **A named session takes assigned work once it is ready.** Direct delivery to a
  named session is an assignee with no route (Gas City's dispatch architecture).
  Its claim offers assigned work through `bd ready --assignee`, and the
  controller counts an open assigned bead as that session's demand only once
  the bead is ready (`workBeadHasAwakeDemand`, in the controller's awake set),
  which starts a stopped on-demand session. Demand alone does not always give a
  running session a turn, which is why gc-toolkit sends a named agent a notice
  once an assigned bead is ready
  ([deferred-dispatch.md](../../docs/deferred-dispatch.md)).
- **The build pack drains a convoy and publishes once.** Its
  `build-from-convoy` runs each member in its own worker, reviews the whole
  result, and can push and open one PR. Each member starts from the default
  branch, so nothing collects several beads' work on an integration branch.

## What gc-toolkit carries today

The census covers every tracked file outside `specs/` and `generated/` that
mentions a convoy, an `integration/` branch or graduation, at this branch's merge
of main a5e5c2cd2. A file that exists only for convoys counts whole. Elsewhere a
line counts when it is within one line of a mention. By that method gc-toolkit
carries 6,803 such lines in 158 files, 3,038 of them in the 11 files that exist
only for convoys.

| What it is | Lines | Files | Under this design |
|---|---|---|---|
| Readers of a workflow's input convoy: the formulas' derivation of their bead, and 21 copies of one lookup in the pack's tooling | about 2,600 | 90 | the formulas' derivation stays as Gas City's contract; the copies become calls to one shared reader (unit F) |
| `mol-design-convoy` and its tests, `docs/design-convoy.md`, and the convoy doctrine in the mechanik's prompt, the polecat doctrine and the `prs` skill | about 1,560 | 7 | rewritten to the landing bead; the drain, the `until` edge and their test go (unit C) |
| Graduation, its cadence wiring, and the `convoy-check` order | about 730 | 6 | deleted (unit B) |
| The helm board's convoy surfaces | about 630 | 19 | kept: they render Gas City's convoys (section 8) |
| `convoy-seed.sh`, its test, and the test of its call from `mol-design-convoy` | 480 | 3 | deleted (unit C) |
| The test of workspace-setup's convoy target guard | 425 | 1 | deleted with the guard (unit D) |
| Mentions in docs and prompts | about 225 | 23 | corrected where the model makes them false (section 11) |
| The integration banner and label | about 70 | 5 | deleted (unit E) |
| The refinery's merge strategy, the lifecycle registry, the proactive pool | about 60 | 4 | changed (unit A) |

The guard itself sits in `formulas/mol-polecat-work.toml`, which the census
counts with the readers. The window understates a block whose lines seldom name
a convoy, such as the label code, so section 9 measures each unit by its blocks.

## 1. The default, and the one line for main (unit A)

### Decision

Two changes to `formulas/mol-refinery-patrol.toml`:

1. `vars.default_merge_strategy` becomes `direct`.
2. The `merge-strategy-resolve` block gains one rule: a bead that would land
   `direct` on the rig's default branch resolves to `mr`. A bead with no `target`
   lands on the default branch, so it resolves to `mr` too. The default branch is
   the patrol's `target_branch`, which is main.

So:

- A bead of an integration effort, whose target is the effort's branch, lands
  there with no PR.
- A lone bead's work, a landing bead, a rework of a PR into main, and a
  supplement to one all land on main, so each goes through a PR, as each does
  today.
- A bead slung `--merge mr` is a stage, and opens a PR into its effort's branch.
- A bead aimed at another PR's head that names no strategy lands on that head, so
  its work folds into that PR, as it does today.
- A bead aimed at any other branch lands as its strategy says. Whether that branch
  needs a PR is the GitHub ruleset the operator defines for it.
- A `local` bead stays `local` whatever its target, and the refinery refuses it
  as unsupported, as it does today.
- The rule that `existing_pr` forces `mr` stays as it is.

The refinery reads only the bead's own `merge_strategy`. The one line is the only
rule this design adds to Gas City's meaning of a strategy.

### What else unit A changes

- **The fold-in flip goes.** Today the resolve block turns an `mr` bead aimed at
  another PR's head, with no PR of its own, into `direct`, so its work folds onto
  that head instead of opening a nested PR
  ([specs/tk-sw5bu](../tk-sw5bu/merge-strategy-fold-in.md)). The beads it exists
  for come from dispatches that name no strategy, and under the `direct` default
  they land on the head with no flip. The pack's writers of `mr` aim at main
  (`convoy-graduate.sh`, which unit B deletes, the feedback distiller, and the
  proactive prompt for a reaction's own code) or give a rework child its
  anchor's target (`rework-child.sh`, `pr-facts.sh`, `pre-open-rebase.sh`), and a
  bead that folds onto a head anchors no PR, so no child inherits that aim. An
  `mr` bead aimed at another PR's head then means a PR into it, as Gas City
  defines `mr`. The flip's variables, `MS_FOLD_IN`, `MS_BRANCH` and
  `MS_HAS_OWN_PR`, go with it.
- **The rejection arm's branch decision goes.** On a branch-caused rejection,
  `rejection-branch-keep` deletes the bead's branch when the bead resolves
  `direct`, records no PR and is not a fold-in. Under the `direct` default every
  bead of an effort is such a bead, and the rebuild the same arm's repool starts
  resumes that branch, so the delete would stop every such bead whose gate fails
  at workspace-setup's missing-branch visit. Without the delete, every path
  through the decision keeps the branch, so the decision goes whole, with its
  copy of the resolve block. merge-push's copy is then the one reading of the
  strategy. A branch is still deleted when its work lands, by
  `delete_merged_branches` after a direct landing and by the repository's
  delete-on-merge after a PR.
- **The proactive pool's rule.** Its doctrine says code a reaction produces takes
  the gated `mr` path, never `direct`, and names two things that enforce it, the
  city's default and the pool's `GC_DEFAULT_MERGE_STRATEGY`. No rig sets the
  default, and nothing reads the variable, so the rule rests on the refinery's
  `mr` default, which this design changes. It holds in this form. Code a reaction
  writes carries `merge_strategy=mr` itself, as the pool's prompt already tells
  it to, so it opens a PR wherever it lands. Work a reaction routes is its
  subject's own, and lands by the subject's target like any bead's. Aimed at
  main, it goes through a PR by the one line. Aimed at an integration branch, it
  reaches main in its landing bead's PR. So a reaction's code reaches main only
  through a PR. Unit A corrects the doctrine and removes the variable, its
  sentence in the prompt, and the fixture's check of it.
- **Words, tests and the warrant.** The `merge_strategy` entry in
  `lifecycle/lifecycle.toml`, the resolve block's comment, the `pr-stack.sh`
  comment, a line of `docs/refinery-merge-cadence.md`, and the tests in
  `mr-aware-rejection-failclosed.test.sh` change to match (section 12). Unit A
  adds warrant 1 to `docs/warrants.md`.

### Why

- **The default is Gas Town's.** Gas City leaves an unset strategy to its
  consumer, and Gas Town's refinery reads it as `direct`. gc-toolkit's `mr`
  default is why each bead of an effort opens a PR at all.
- **`mr` was only ever about main.** The default came from a moment when main's
  ruleset was off and the city pushed straight to main, which nobody intended,
  and the operator asked the pack to act as if main's ruleset were always on. PRs
  are how the operator sees what commits reach main, and nothing asked for any
  other branch to be held behind one.
- **The ruleset enforces while it is on, and the line holds when it is off.**
  gc-toolkit's main carries a GitHub ruleset that requires a PR with one
  approval, squash merges only, and the checks `test` and `test-macos`, and the
  city's account cannot bypass it. When it refuses a direct push, gc-toolkit's
  refinery promotes the bead to `merge_strategy=pr` and opens a PR instead, as it
  has since 2026-05-10, today in `direct-merge-push.sh`. Gas Town's refinery has
  no such fallback: a refused push stops its merge step with the bead still
  assigned to it, and the next patrol takes the bead again. With the ruleset off,
  nothing refuses the push, which is how the city once pushed to main
  unintended. The line makes main behave as if its ruleset were always on.
- **Gas City cannot express it as config.** A rig's `default_merge_strategy` is
  stamped on every bead the rig slings, whatever its target, so `mr` there would
  open a PR for every bead of an effort again. Gas City has no merge strategy
  per target branch.
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

## 2. Each bead carries its own branch (units C and D)

### Decision

A bead filed for an integration effort carries the effort's branch as its own
`target`, written in the `gc bd create` that files it. Sling branches it from that
target, the refinery lands it there, and every later pour of the bead reads the
same key: the re-sling a visit's close arms, a rejection's rebuild, a rework. No
bead inherits a branch from anything, so no two sources can disagree about one.
workspace-setup's convoy target guard and its test go (unit D).

### Why

- **What the operator loses without it:** an effort's work, landed together and
  reviewed as one PR. A bead with no branch of its own lands on main through its
  own PR.
- **What gc-toolkit does differently:** Gas Town never lands planned work off
  main. Its planning formula names an integration branch on an owned convoy and
  adds tasks to it with `gc convoy add`, and each task branches from main, lands
  on main, and nothing compares it with the convoy's branch. gc-toolkit lands an
  effort's beads on the effort's branch so the operator reviews one PR, so its
  beads must know the branch.
- **The bead has the one slot that can hold it.** A branch is singular. A bead
  can sit in many convoys but has one `target`, which Gas City reads first, Gas
  Town's polecat writes, and a refinery lands on.
- **Written in the create, not at sling.** Sling has no flag that writes a
  target, and `--var base_branch=` sets only the pour it starts. A key written in
  the create is there for every pour, and the bead never exists without it.

### The guard goes (unit D)

The guard declines a convoy's member whose pour lost the convoy's branch: the
branch lived on the convoy, the member reached it only through its parent, and
bd reported another parent, such as the member's epic. Under the model the branch
is the bead's own, so that loss cannot happen. What remains is a bead filed for
an effort without its target. It branches from main and lands on main through a
PR of its own, by the line for main, and the operator sees that PR beside the
effort's. The guard compares a bead's base with its convoy's target, and under
the model no convoy carries a target, so it would have nothing to compare.

Its block also declines a bead it cannot read, under load-context's situation
key. That read exists only for the guard, and load-context declines an unreadable
bead before workspace-setup runs.

### What tracking changes

The readers that find a bead's convoy through its parent edge treat a convoy
parent like any other parent: `priority-lib.sh`, `hold-lib.sh`,
`converse-parent.sh`, `placement.sh`, `bead-context.sh` and the top-level test of
`tools/gc-proactive.sh`. None of them carries code of its own for a convoy
parent, so none changes. Under the model no bead of an effort has a convoy for a
parent, so a convoy's priority no longer ranks its beads, and parking a convoy
no longer holds them. An effort is ranked and parked through its epic, or on its
beads.

## 3. Standing an integration effort up (unit C)

### Decision

The mechanik's recipe and `mol-design-convoy` stand an effort up in this order:

1. **Name the landing bead.** `mol-design-convoy` uses its subject, the
   initiative, which is already the bead the effort delivers. The mechanik files
   one in the rig's store: an ordinary task, titled for what the effort delivers,
   whose description says what the effort is to deliver, under the effort's epic
   when it has one.
2. **Cut its branch** with one create-only push from the rig's checkout, after a
   fetch of origin:
   `git push origin refs/remotes/origin/<base>:refs/heads/integration/<landing-id> --force-with-lease=refs/heads/integration/<landing-id>:`.
   `<base>` is the default branch the checkout's `origin/HEAD` names, or `main`
   when it names none. The two recipes cut with the same marked blocks, so an
   effort starts from, and lands on, the same branch whichever stood it up. The
   push sends a ref and checks nothing out, so the rig's checkout never
   moves. The empty lease refuses a branch that already exists, so a resumed
   recipe that finds the branch on origin goes on without pushing.
3. **Record the branch on the landing bead:** `branch=integration/<landing-id>`
   and `target=<base>`, read back.
4. **File each bead of the effort** with `target=integration/<landing-id>` in its
   create, add the landing bead's `blocks` edge on it, and read both back.
   Nothing is slung yet.
5. **File the summary task** once the effort's beads are filed: an ordinary task
   in the rig's store, titled for the landing bead's PR summary, whose
   description names the landing bead, under the effort's epic when it has one.
   That puts it beside the landing bead, which waits on it. As a member of the
   epic it may be armed to a pool, and the epic ranks and parks it as it does
   the effort's beads ([steering.md](../../docs/steering.md)). It lands
   nothing, so it carries no `target`. Add its `blocks` edge on each bead of the
   effort and the landing bead's `blocks` edge onto it, and read them back.
6. **Hand the landing bead to the refinery** once every wait reads back: assign
   it to the rig's refinery, by the address the polecat handoff checks against
   the roster, and record the notice the assignment owes
   (`deferred-dispatch.sh notify`). Handed over while it waits on only some of
   the effort, it would reach the refinery once those had closed, and the
   refinery would open the effort's PR on a partial branch. Assigned before it
   waits on anything, it would reach the refinery at once, and the refinery
   would refuse its empty branch as a change with nothing in it.
7. **Dispatch the work:** sling each bead of the effort, or arm it when it waits
   on other work, and arm the summary task to dispatch to the rig's polecat pool
   on Gas City's `mol-polecat-report` (section 4). A stage is slung
   `--merge mr`. Nothing is in flight before this step, so no bead can land while
   the landing bead waits on fewer than all of them. The summary task is armed
   only once it waits on every bead: armed with nothing to wait on, it would be
   dispatched at once.

The branch is named for the bead that lands it, so an integration branch has one
landing bead. None of these steps is a warrant: the push is the act the original
Gas Town performed first, and the rest are Gas City's own writes, composed in a
recipe.

### Adding work later

A bead joins an effort with the same writes, before it is slung: its `target`,
the landing bead's `blocks` edge on it, and the summary task's. While any wait
of the landing bead is open, the landing bead stays with the refinery
unprepared, so a bead added then is in the PR. A summary task that has already
been dispatched may already have read the branch, so a fresh summary task, filed
and armed as the first one was, waits on the bead instead, and the landing bead
waits on that one too. A bead of the effort that splits its work files each new
bead the same way. Once the refinery has taken the landing bead, work for its
branch rides that branch as a rework, or as a supplement once the PR is open
(the `prs` skill), and a rework restamps the summary from the whole branch, as
it does for any PR.

### A shared input artifact

A spec or decisions doc that several beads need is the effort's first bead. It
lands on the branch like any bead, and the beads that need it wait on it with a
`blocks` edge.

### When the branch is brought current

An effort's branch is cut from the default branch when the effort is stood up. A
bead that builds on work reaching main after that needs the branch brought
current first. That is a hand-off to the mechanik, not a bead of the effort. The
hand-off is a task assigned to the mechanik, which waits on the outside work by a
`blocks` edge, and deferred dispatch's ready notice tells the mechanik when that
work has landed. The bead that needs the branch current waits on the hand-off by
a `blocks` edge, and is armed to dispatch when the hand-off closes.

Once notified, the mechanik brings the branch current from a disposable worktree:
a fast-forward to main when the branch holds nothing main lacks, and a merge of
main into it when it does. It pushes the result and closes the hand-off, which
releases the bead. No polecat builds the hand-off, so no self-review and no
refinery gate reads main's commits as its change. A merge that conflicts is not
mechanical: the mechanik pushes nothing and puts it to the operator with a visit.

When the landing bead is prepared, the refinery brings the branch current by
merging main into it, as it does every branch it prepares.

### `mol-design-convoy`

- **Its subject is the landing bead.** Its seed step cuts
  `integration/<subject-id>` and records the branch and a `target` of main on
  the subject, so a resumed step finds the branch recorded and cuts nothing. The
  subject then closes when its PR merges, as any PR's owning bead does, so the
  work queued behind it starts then. The `until` edge that closed the subject
  when its convoy closed goes, and so does the drain step, which released the
  subject from its pours' input convoys and cleared its pour's stamp so that the
  until pass could close it.
- **Its filing steps** file the design child and the implementation child with
  their target in the create and the subject's `blocks` edge on each, hold the
  implementation child behind a gated design, and file the summary task beside
  the subject, with its `blocks` edge on each child and the subject's onto it,
  reading each write back. A last step reads the whole setup back, hands the
  subject to the refinery, and then dispatches: the design child is slung
  `--merge mr`, a stage whose PR is the design gate, the implementation child is
  armed behind it, or slung with it for all-in-one, and the summary task is
  armed. The implementation child's brief tells it that a bead it splits into
  takes the same writes, the summary task's edge among them.
- **Its name stays.** A pattern's name is a word nothing in Gas City reads, and
  renaming it moves every caller for no behavior.

### What `convoy-seed.sh` carries, and where each part goes

| convoy-seed.sh | Under this design |
|---|---|
| Creates the owned convoy and sets its target | the landing bead records the branch; no convoy is made |
| Writes the convoy's id to a file before the steps that can fail, so a resumed run reuses the convoy | `mol-design-convoy` records the branch on its subject, and a resumed step reads it there. The mechanik reads the landing bead's id from the create that filed it |
| Cuts the branch in a throwaway worktree, so the rig's checkout never moves | a ref push needs no worktree |
| Skips the cut when origin already has the branch | the empty lease refuses an existing branch, and the recipe reads that as done |
| Seeds a shared input artifact on the branch (`--artifact`) | the artifact is the effort's first bead |

### A convoy for status

A convoy that tracks an effort's beads and its landing bead gives the effort one
progress row, closes itself when the landing bead closes, and carries nothing
the work reads. Neither recipe makes one. The helm board reads a convoy without
Gas City's `owned` label as an orphan with no owning bead and bands it high
(tk-vlg4ihb), and whether gc-toolkit should use convoys as trackable units at all
is its own question (tk-fv1pkm6).

## 4. The landing bead reaches the refinery (unit B)

### Decision

The landing bead is assigned to the refinery when its effort is stood up, and
carries the notice that assignment owes (section 3, step 5). Three readers of the
refinery's queue change, so that an assigned bead waits while something holds
it:

- the refinery's find-work leaves a bead that something holds, by `hold-lib.sh`'s
  definition;
- the witness's `check-refinery` leaves the same bead out of its count of stuck
  handoffs;
- the doctor's `check-refinery-patrol-live` leaves the same bead out of the
  queue it ages, so a refinery whose queue holds only a waiting landing bead
  reads as idle, not as a stalled patrol.

The landing bead carries a `branch`, so `hold-lib.sh` reads it as work in flight,
which only its own blockers hold: the effort's beads and its summary task. The
summary task is dispatched only once the effort's beads have closed, so it
closes last, and bd then reports the landing bead ready. Gas City counts it as
the refinery's demand, which starts a stopped refinery. The deferred-dispatch pass
sends the notice, which requests a running refinery's turn. Either way
find-work takes the bead on the refinery's next turn.

From there it takes the path every bead aimed at main takes. The refinery merges
main into the branch, runs the rig's gate, refuses a branch with no change and
parks it for a person, and resolves the bead to `mr` by the line for main. The
merge cadence's checks review the whole branch before the PR opens, and
`merge.sh` lands the PR with the operator's approval and closes the bead.

A park on the effort's epic holds what under it has not started: the effort's
beads, and the summary task until it is dispatched, since deferred dispatch
slings no armed bead that has not started while a park on one of its ancestors
stands (`hold-lib.sh`). So an effort parked before its summary task is
dispatched reaches the refinery once the park lifts. Once the summary task has
run, bd still keeps the landing bead out of ready work while the park stands, so
its notice waits for the park to lift. find-work reads `hold-lib.sh`, which
leaves work in flight running under a parked ancestor, so it takes the landing
bead on any earlier turn the refinery has, as graduation takes a finished convoy
today.

### Why

- **What the operator loses without it:** the effort's one PR opening by itself
  once its work is done. Without the hold, find-work would take a landing bead
  while its effort is still being built, and open the effort's PR on a partial
  branch.
- **What gc-toolkit does differently:** nothing in Gas Town hands its refinery
  work before the work is done, so its refinery never meets a bead that waits.
  gc-toolkit hands the landing bead over when the effort is stood up, so that
  no hand-over has to run when the effort finishes: the graph says what the
  landing bead waits for, and Gas City's readiness says when.
- **It is how gc-toolkit hands any work to a named agent:** an assignee, and the
  notice a wait owes ([deferred-dispatch.md](../../docs/deferred-dispatch.md),
  "Work assigned to a named agent owes a notice"). It is the form Gas City
  documents for direct delivery to a named session, and Gas City's own claim
  offers assigned work only once it is ready. find-work takes the refinery's
  work without asking whether it waits, and the witness's check and the
  doctor's patrol check read that queue the same way, so those three are what
  change.
- **A handoff waits only on a blocker of its own.** `hold-lib.sh` holds work in
  flight only by its own blockers, so a handoff under a parked epic still lands.
  A bead an arm dispatched had no open blocker when it was slung, so its handoff
  lands as today. A bead slung by hand past an open blocker now waits at the
  refinery until that blocker closes, which is what its `blocks` edge says.
- **A landing bead is an ordinary bead.** It is ready work once its waits clear,
  which a convoy's bead never is, and a rejection's rebuild poured at it works on
  it, where a rebuild poured at a convoy's bead works on the convoy's members.

### Rejected

- **The deferred-dispatch arm.** An arm slings, and sling's router writes
  `gc.routed_to` and never an assignee, for a named agent as for a pool. The
  refinery reads its queue by assignee, so an armed sling would put the landing
  bead in a queue nothing reads, and gc-toolkit hands work to a named agent by
  assignee, never by route.
- **Graduation, and Gas Town's auto-land step.** Each makes the convoy's bead the
  unit of work at the end, and each needs a step to run once the effort finishes:
  graduation on a cadence interval, and Gas Town's after a landing on the branch.
  The ruling keeps a convoy a status grouping, and no step has to find a
  finished effort: the edges on the landing bead and on its summary task say
  when each is ready.

### The PR's summary (unit C)

The effort's summary task writes the landing bead's `pr_summary`, which
`pr-open.sh` publishes as the PR's `## Summary`. It waits on every bead of the
effort, and the landing bead waits on it, so it runs once the effort's last
bead has landed, and the refinery takes the landing bead only after it has
closed. Its arm slings it to the rig's polecat pool on `mol-polecat-report`, the
core pack's formula for work that changes no file, whose write-report step
closes the bead.

Its polecat reads the finished branch against main, and the summary each landed
bead's own polecat wrote at its handoff. It sets the landing bead's
`pr_summary` to what the whole branch does, for the operator's merge decision,
and names where the finished work departs from the landing bead's description:
work the description promised that did not land, work that landed beyond it,
and an approach that changed. It reads the write back and closes the task. The
pre-open correctness check then reads that summary against the whole branch, as
it reads every anchor's pending summary, and `pr-open.sh` publishes it, with the
landing bead's description demoted to a collapsed dispatch section. The polecat
doctrine states the method once, and the summary task's description names the
landing bead it writes for.

From there the summary changes as any PR's does: a rework of the PR restamps it
from the whole branch at its submit, and `pr-stack.sh` carries the restamp to the
open PR.

- **What the operator loses without it:** an effort's PR that opens with the
  plan the effort started from as its summary. `pr-open.sh` publishes an
  anchor's description, the dispatch text, when no summary was written, and the
  PR body's bead list (`pr-stack.sh`) names each bead only by its id and title,
  so the operator would rebuild what the change does from its beads.
- **What gc-toolkit does differently:** Gas Town's refinery opens a PR whose
  summary is the bead's description, with the bead's notes below it. gc-toolkit
  publishes the account of the diff written at handoff by the polecat that built
  the work, and demotes the description, because the summary is where the
  operator decides. No polecat builds a landing bead's work, so that account
  needs a run of its own once the work has landed.
- **It is an ordinary bead on Gas City's own formula.** `mol-polecat-report`
  writes to the store, changes no file, and closes its bead, and that close is
  what the landing bead's edge waits for. No pack script composes the summary, so
  the observer test gains no addition (section 7).

Three other authors are rejected:

- **The landing bead's description.** It is written when the effort is stood up,
  before any work exists. `pr-open.sh` treats it as dispatch text, and the
  pre-open correctness check sends back a summary that restates the dispatch.
- **A summary composed from the landed beads' own summaries, as graduation
  composes one.** The composition would stay as pack code in the merge path that
  every PR shares, for the landing bead alone, and a list of each bead's account
  says what each bead did, not what the branch does.
- **A polecat run on the landing bead itself.** `mol-polecat-work`'s submit
  writes the summary of every anchor a polecat builds, but its self-review loop
  would review the whole effort again, and could change it, before the PR's own
  checks read it. The landing bead would also reach the refinery from that run
  instead of waiting there from setup. A report run writes the summary and
  changes nothing else.

### What graduation carries, and where each part goes

| Graduation | Under this design |
|---|---|
| Takes an open owned convoy whose target is an integration branch | the landing bead names its branch, so nothing is selected |
| Counts members in both forms, and a `tracks` edge to a bead it cannot read holds the convoy | the landing bead's `blocks` edges, which the recipe reads back before it hands the bead over. bd holds nothing on an edge to a bead in another store, so each bead of an effort is filed in the rig's store |
| Requires a landing recorded on the branch, so a convoy whose members landed nothing does not graduate | the refinery refuses a branch with no change: it closes nothing, opens no PR, and parks the bead for a person |
| Skips a convoy, or a bead on its branch, that carries `merge_hold` or `rebase_hold` | a `blocks` edge of its own, such as one onto a gate, holds the landing bead before the refinery takes it. No refinery step reads either marker until the bead is an anchor, by which point the refinery has brought its branch current. `gc-helm.sh park` refuses a bead that carries a branch, so the edge is written with `gc bd dep add`, and section 10 carries an open convoy's hold over as one. Once the landing bead is an anchor, either marker keeps its PR from opening, and `merge_hold` also holds its review dispatch and its merge, as for every PR |
| Skips a convoy whose branch a live bead already owns | one landing bead per branch, which the recipe names once |
| Stamps `merge_strategy=mr` | the line for main resolves the landing bead to `mr` |
| Stamps `graduation=true` | nothing reads it. The key stays registered, as retired |
| Seeds the PR's summary from the landed members' summaries | the effort's summary task writes the landing bead's `pr_summary` from the finished branch, and the landing bead waits on it, so the summary is written before the refinery takes the bead (above) |
| Runs at most once per 15 minutes | the deferred-dispatch pass after the effort's last bead lands slings the summary task, and the pass after the task closes sends the landing bead's notice, on that order's 5-minute cooldown. Gas City starts a stopped refinery as soon as the bead is ready |
| `REFINERY_RECONCILE_INTEGRATION_AUTO_LAND=false` turns it off | nothing to turn off. A `blocks` edge onto a gate holds one landing bead |

### Gas City's lifecycle verbs

The model uses no owned convoy and no `gc convoy land`. A convoy that only groups
work closes itself, and Gas City's core pack sweeps hourly for a close the
controller missed, so gc-toolkit's `convoy-check` order, which runs the same
command on the same interval, goes.

## 5. Reviews, the PR, stages and rework

| Where | What runs | What it reads |
|---|---|---|
| Inside each bead's molecule | the self-review loop of `mol-polecat-work`: a polecat in a fresh session reviews and fixes the diff, and the loop ends only when the rig's checks pass at its head | the bead's own diff |
| At the refinery, before the bead lands | the rig's gate on the prepared head | the bead merged onto the effort's branch |
| Once the effort's beads have landed | the summary task's report run, which writes the PR's summary | the whole branch against main, and each landed bead's summary |
| On the effort's PR, before it opens | correctness and triage, and arch and pm when triage adds them | the whole branch against main |
| On the effort's PR, while it is a draft | demo, when triage adds it | the PR |
| On the effort's PR | the operator's approval, `merge.sh`'s universal rule | everything |

A bead's defect is its own self-review's to catch. The effort's PR is where the
big-picture items are caught, which is what the operator reviews it for. A bead
closes when it lands, like any bead whose work is done.

The operator's review returns as a rework child that resumes the PR's branch,
and scope found while the PR is open rides a supplement on the same branch. A
rework child joins its anchor by a `related` edge and blocks it by a `blocks`
edge.

**Stages.** A stage is a bead slung `--merge mr`. It opens its own PR into the
effort's branch, the operator approves it, and it lands before the beads that
wait on it. The design child of a design-gated `mol-design-convoy` is one,
because its PR is the design gate. A stage built from several beads would be an
effort that lands into another effort's branch, which this design does not
build.

**The integration banner and label go** (unit E). Every PR into an integration
branch carries a `base: integration` label and a banner in its body that says
approving it "mints this phase into the convoy integration branch". Both render
the PR's base, which GitHub shows at the head of every PR, under a word the pack
coined. Under this design a PR into an integration branch is a stage the operator
asked for, so the label's writer in `pr-status-label.sh`, the banner in
`pr-summary-region.sh`, the calls to them in `pr-open.sh`, their tests, and the
section of `docs/state-machine.md` that describes them go. The label stays on the
PRs it already marks, and nothing adds it again.

## 6. The input convoy's readers: one shared reader (unit F)

### Decision

A graph.v2 run records the input convoy it was poured over
(`gc.input_convoy_id`), and that convoy tracks the bead the run works. Seven
formulas derive their bead in each step with `gc convoy status {{convoy_id}}`,
as Gas Town's formulas do, and that derivation is Gas City's contract and stays.
Beside it, the pack's tooling carries one lookup in 21 copies across 18 files,
801 lines, 115 of them Go in the helm board's facts. Some go from a run to its
bead, some from a bead to the runs that work it, and one from an input convoy to
its run. The copies already disagree in method: some read `gc convoy status`,
two read `bd dep tree` and fall back to the legacy `issue` variable, and one
parses the input convoy's title.

Unit F replaces them with one shared reader, sourced the way `hold-lib.sh` is,
with three verbs:

- `runs <bead>`: the runs that work a bead, each with its root, its formula and
  whether it is live;
- `subject <root-or-input-convoy>`: the bead a run works, and the run's root;
- `map`: every run in the store with its root, input convoy, bead, formula and
  liveness, for a caller that judges many beads in one pass.

Each copy becomes a call to the reader, and the reader's fixture is the case set
the Go copy in `services/helm/internal/source/facts.go` must agree with, as
`hold-lib.fixture.json` is for a copy of the hold.

`live-work.sh` stops counting every convoy that tracks a bead, closed ones
included, and asks the reader whether a live run works the bead. A status
grouping holds nothing, and a closed convoy groups nothing.

### Why

- **What the operator loses without the lookup:** the stranded report and the
  doctor checks would list every bead a run is building, because Gas City leaves
  the worked bead open, unassigned and unrouted; the helm board could not show
  which session works a bead; a review whose run died would hold its PR
  silently; a first reaction could be filed on a bead a run is building; a
  workflow would not follow its bead's priority; a park could not tell a poured
  bead from one waiting; disposal could close a bead a run is working; and a step
  could not find its worktree.
- **What gc-toolkit does differently:** a standard city reads the input convoy
  only in each step's own derivation. Gas City's standard surfaces that judge
  open work, `gc convoy stranded` and the dashboard's ready-unclaimed row, flag
  any open bead with no assignee, so they misread a bead a run is working.
  gc-toolkit's liveness sweeps, doctor checks, helm board, priority following and
  disposal exist to read that state correctly, and each needs the lookup.
- **One definition, no copies.** The lookup is a read of Gas City's state, not a
  pack noun, so it needs no warrant. Copied 21 times it has already drifted three
  ways. One reader puts its method, its failure handling and its test in one
  place, as `hold-lib.sh` and `dispatch-path.sh` do for theirs.

### What the ruling named as duplicates

The ruling named four pieces as duplicates of something Gas City already does.
Read against the code at this branch's merge of main and the deployed `gc`:

| Piece | What the ruling took it to duplicate | What deleting it would lose | Under this design |
|---|---|---|---|
| `step-close.sh`'s `--convoy` route | `--root`, since a claim carries `root_bead_id` | A formula cannot name its run's root: the root is created after the pour's variables, and the variables Gas City reserves name only the input convoy and the bead. So a step's `--root` would have to be copied by hand from the agent's claim into each of 23 calls in 7 formulas, including the chain-close loops for steps no claim returned. The route also refuses a convoy's root unless this session holds or held a bead in it, which is what keeps a re-poured run from closing another molecule's step | stays. Its convoy-to-run lookup becomes the reader's `subject` |
| The double-pour check in `gate-ensure.sh` | sling's refusal of a second live root of the same formula on a bead | The same check routes a stranded review whose stamp dropped to the liveness judge. Relying on sling, a spent chain, whose finalizer is still open, would be refused on every pass, and gate-ensure discards sling's output, so the review would never escalate. It also counts a root of any formula, which matters when the review formula changes | stays. Its lookup becomes the reader's `runs` |
| `work-tree-holder.sh` | the core pack's `work-holder.sh` | That script is in the core pack of the Gas City build this city runs, but not in Gas City's released core pack. It decides from a `work_holder` record that gc-toolkit's `mol-polecat-work`, which replaces the core steps that write it, never writes, so swapped in it would read every bead as unheld, and a duplicate dispatch would pass | stays. Its lookup becomes the reader's `runs` |
| `mol-design-convoy`'s drain, with `live-work.sh`'s count of closed tracking convoys | a test that a live run works the bead | The drain also clears the pour's stamp, which `live-work.sh` reads as live work too, so a live-run test alone would not retire it | goes, because the subject is the landing bead and nothing closes it by disposal (section 3). `live-work.sh` asks the reader instead |

So unit F deletes the copies and the closed-convoy count, and the three pieces
that are not duplicates keep their behavior on the reader. Adopting the core
pack's `work-holder.sh` would mean writing its `work_holder` record from
gc-toolkit's polecat formula and depending on a script Gas City has not
released, which this design does not take on.

## 7. What a Gas City and Gas Town reader sees

Someone who knows only Gas City and Gas Town watches an integration effort that
gc-toolkit runs.

| What they see | What Gas City or Gas Town does | Same? |
|---|---|---|
| A branch `integration/<id>` on origin, cut from main before any work starts | no verb or bundled pack cuts one; the original Gas Town's `gt mq integration create` cut it first | a recipe step, the one the original Gas Town took |
| Beads whose own `target` names that branch | Gas City's own key, which sling reads first | yes |
| Each bead slung to a pool, wrapped by sling in a one-item input convoy | sling's own launch | yes |
| A bead's work landed on the branch by the refinery, with no PR | Gas Town's refinery lands `direct` by default | yes |
| A stage, slung `--merge mr`, opening a PR into the branch | `mr` as Gas City defines it | yes |
| An ordinary bead with `branch=integration/<id>` and `target=main`, waiting on the effort's beads by `blocks` edges, assigned to the refinery | ordinary beads, edges and an assignment; Gas City offers assigned work once it is ready | yes |
| A bead with no `target` that waits on the effort's beads, slung on `mol-polecat-report` once they close, which writes the landing bead's summary and closes, and which the landing bead waits on | Gas City's report formula, whose close ends the wait on it | yes |
| The bead with `branch=integration/<id>` reaching main through a PR | Gas Town would land it `direct`. Main's ruleset would refuse the push, and Gas Town's refinery would retry it on every patrol | added, warrant 1 |
| The PR reviewed by the city's checks and the operator, merged, and its bead closed at the merge | not a convoy behavior: gc-toolkit's merge path does this for every PR | outside the model (below) |
| A workflow's steps deriving their bead with `gc convoy status {{convoy_id}}` | Gas Town's formulas do the same | yes |
| A convoy that only groups work, closing itself when its last bead closes | Gas City's auto-close and its core pack's sweep | yes, when someone makes one |
| No owned convoy and no convoy target | Gas Town's planning formula names a branch on an owned convoy, and nothing lands on it | gc-toolkit uses neither |

So the reader sees ordinary beads, edges and assignments, Gas City's convoys used
as groupings, and one addition under a warrant, the line for main. What they see
beyond the effort (the PR's owning bead, the summary `pr-open.sh` publishes from
it, the city's checks, the operator's approval, a bead closing when its PR
merges) is gc-toolkit's merge
path, the same for every PR. Moving that path onto Gas Town's refinery is the
merge member of the migration epic (tk-1tfzr71.20), and this design adds nothing
to it.

## 8. What stays, and why

### Warrant 1: the one line for main

- **What the operator loses without it:** a change reaching main with no PR
  whenever main's ruleset is off, which is how the city once pushed to main
  unintended. PRs are how the operator sees what commits reach main.
- **What gc-toolkit does differently:** it delivers work to main through a PR the
  operator approves, where Gas Town lands it `direct`. Gas City has no merge
  strategy per target branch, so the rule cannot be a line of config, and Gas
  Town's refinery has no PR fallback at all.
- **Covers:** the rule in `merge-strategy-resolve`, in
  `formulas/mol-refinery-patrol.toml`, that resolves a bead landing `direct` on
  the default branch to `mr`.
- **Stands in for:** a merge strategy set per target branch.
- **Retires when:** Gas City can set a merge strategy for a target branch, so the
  rule becomes a line of the rig's config.
- **Recorded:** 2026-10-23, kept by the operator on 2026-10-24.

Unit A adds it to `docs/warrants.md` in that page's own format.

### Kept with no warrant

Each of these is prose, config, glue over native calls, a read of Gas City's
state, or a surface that renders it, which the four tests leave free. Each still
answers what the operator would lose without it.

- **The shared reader of a workflow's input convoy** (unit F): the stranded
  report, the doctor checks, the helm board's session column, priority
  following, park and disposal, as section 6 sets out.
- **The read of a hold in find-work, `check-refinery` and
  `check-refinery-patrol-live`** (unit B): without it the refinery would open an
  effort's PR on a partial branch, the witness would escalate a waiting landing
  bead as a stuck handoff, and the doctor would report an idle refinery's patrol
  as stalled. They read `hold-lib.sh`, the pack's one definition of a hold.
- **The recipes' push** (unit C): without it an effort's beads have no branch to
  land on, and every polecat stops at a missing base.
- **The summary task** (unit C): without it the effort's PR opens with the plan
  the effort started from as its summary, and the operator rebuilds the change
  from a list of bead titles. It is a recipe step that files an ordinary bead on
  Gas City's report formula, and its method is a paragraph of the polecat
  doctrine.
- **`mol-design-convoy` and the mechanik's recipe**: a formula and a prompt.
- **The helm board's convoy surfaces**: they render Gas City's convoys and their
  tracked beads. The board misreads two things, each filed apart: it reads Gas
  City's `owned` label as "has an owning bead" (tk-vlg4ihb), and it tells a
  machine convoy by its title (tk-y4820m2).
- **The parent readers** of section 2, which carry no convoy code.
- **Two calls around Gas City's launch.** `deferred-dispatch.sh` caps the retries
  of a sling that keeps failing, because each launch mints an input convoy.
  `run-cancel.sh` ends a run through Gas City's run cancel, and closes what a
  root closed by hand left open with `gc convoy delete <root> --force`.
- **Prose and fixtures.** Docs and prompts that describe Gas City's convoys, and
  tests that name an `integration/` branch to show a behavior holds for any
  branch shape.

## 9. The deletion map

Measured at this branch's merge of main a5e5c2cd2. A file deleted whole counts
exactly, a block counts its lines as they stand, and an addition is estimated.

| Unit | Deletes | Adds | Net |
|---|---|---|---|
| A. The default and the one line | `rejection-branch-keep` (52), the fold-in flip (19), `GC_DEFAULT_MERGE_STRATEGY` with its prompt sentence and fixture check (7), the test's branch-decision section (about 145) | the one line (about 4), the resolve block's test cases (about 35), warrant 1 (about 12) | about -170 |
| B. The landing bead reaches the refinery | `convoy-graduate.sh` (321), its test (305), `orders/convoy-check.toml` (31), arm 8 with its switch and target lookup (20), its cases (12), graduation's paragraphs and rows in the docs (about 20) | find-work's read of a hold (about 20) and its cases (about 60), `check-refinery`'s (about 15) and its cases (about 35), `check-refinery-patrol-live`'s (about 30) and its cases (about 35), the architecture page's sentence (about 5) | about -510 |
| C. Recipes on the landing bead | `convoy-seed.sh` (158), its test (180), `mol-design-convoy-seed-invoke.test.sh` (142), `mol-design-convoy-subject-close.test.sh` (427), the seed-convoy step (88), the drain step (84), the arm steps' parent-child links (about 6), the mechanik's seed recipe and graduation prose (about 45), `docs/design-convoy.md`'s seed, graduation and subject-close text (about 60), the polecat doctrine's paragraph (about 15) | the seed step (about 40), each bead's two writes and the hand-off (about 18), the summary step (about 45) and its cases in the arm test (about 60), the arm test's other cases (about 30), the mechanik's recipe (about 40), `docs/design-convoy.md` (about 25), the doctrine's paragraph and the summary task's method (about 25), the summary's writer in `lifecycle/lifecycle.toml` and `docs/refinery-merge-cadence.md` (about 5) | about -920 |
| D. The guard | step 1b of workspace-setup (116), its test (425) | nothing | -541 |
| E. The banner and label | `pr-status-label.sh`'s `base:` group (about 55) and its test section (about 45), the banner (about 17), `pr-open.sh`'s calls (8) and its banner cases (about 52), `docs/state-machine.md`'s base label section (47) | nothing | about -225 |
| F. One shared reader | the 19 copies in shell and formulas that stay in use (672), the lookup fixtures in their tests (about 150) | the reader (about 150), its suite and shared fixture (about 260), 19 calls (about 95), the Go copy's fixture test (about 20) | about -300 |
| **All** | **about 3,720** | **about 1,060** | **about -2,660** |

What stays, and why, is section 8. Section 11 lists every living file the units
change.

## 10. Moving the open convoys that carry a branch

An open convoy that carries a target today is an owned convoy on an
integration branch, waiting for graduation. When the implementation reaches
main, graduation is gone, so each such convoy needs a landing bead. The mechanik
moves them once, on a hand-off task filed with the units, which waits on the
implementation convoy's bead, the anchor of its PR, by a `blocks` edge and
carries the ready notice. The
spec names no live bead: the hand-off lists each rig's open convoys
(`gc bd list --rig <rig> --type=convoy --status=open --json`) and takes each one
whose `target` names an integration branch and that carries no `branch` of its
own.

The landing bead must be held wherever the convoy was held. Graduation takes no
convoy that carries `merge_hold` or `rebase_hold`, or whose branch a live bead
holds with either. Once graduation makes a convoy an anchor, its merge waits on
every open blocker of its own, and the beads that wait on it are released when
it closes, at its PR's merge. A landing bead handed over without those holds is
taken by the refinery as soon as its effort's beads have closed. The refinery
brings its branch current, and the cadence reviews it and opens its PR, because
`gate-ensure.sh` and `pr-open.sh` read holds off the PR's anchor alone. So the
move carries each hold onto the landing bead as a `blocks` edge before it hands
the bead over, and moves each wait off the convoy before it closes the convoy.
A marker would not keep the refinery from taking the landing bead. No step of
the refinery's patrol from find-work through merge-push reads either marker, and
bd decides from edges, not markers, when the bead is ready. That is when Gas
City counts it as the refinery's demand and the deferred-dispatch pass sends its
notice.

For each such convoy, in this order:

1. **Name its landing bead, and file its summary task.** A `mol-design-convoy`
   subject that records the convoy (`gc.design_convoy_id`) is its landing bead.
   Otherwise the mechanik files one, as the recipe does. Either way it files the
   summary task as the recipe does, adds the landing bead's `blocks` edge onto
   it, and reads it back.
2. **Record the branch on it:** the convoy's `target` as its `branch`, and main
   as its `target`. The branch exists already, so nothing is cut.
3. **Move each open bead the convoy tracks or parents.** Write the convoy's
   target as the bead's own `target` when it names none, add the landing bead's
   and the summary task's `blocks` edges on it, and read all three back.
4. **Carry the convoy's holds.**
   - **An operator's hold.** When the convoy carries `merge_hold` or
     `rebase_hold`, or a live bead besides the landing bead carries either and
     names the convoy's target as its `branch`, file a gate in the rig's store
     with no await type and no `gc.demand_for`, the shape of a park's gate, so
     no sweep closes or visits it. Its title says what was held and that closing
     it releases the effort to the refinery. Its description names the bead that
     carried the hold and the markers it stands for, with any `hold_reason`
     beside them. Add the landing bead's `blocks` edge onto the gate and read it
     back. `gc-helm.sh park` refuses a bead that carries a branch, so the edge
     is written with `gc bd dep add`, as every wait of the landing bead is. The
     markers stay where they are and are not copied to the landing bead. Closing
     the gate is the release for the effort, and a marker on the landing bead
     would keep its PR from opening after the operator had released it.
   - **A prerequisite.** For each open bead the convoy waits on by a `blocks`
     edge, such as a park's gate, add the same edge from the landing bead and
     read it back.
5. **Move what waits on the convoy.** A subject that is the landing bead loses
   its `until` edge onto the convoy, which would close it when the convoy
   closes. Each other open bead that waits on the convoy, by a `blocks` or an
   `until` edge, gets the same edge onto the landing bead, read back, and then
   loses its edge onto the convoy. The landing bead closes when its PR merges,
   as a graduated convoy does, so each of those waits still ends when the effort
   reaches main.
6. **Hand the landing bead to the refinery,** with its notice, **and arm the
   summary task.** When the convoy's beads have all closed, the next pass
   dispatches the summary task, unless a park on its epic holds it, and a
   landing bead that nothing else holds is ready once that task closes. A held
   one stays out of bd's ready work until its gate and every blocker step 4
   carried have closed, so until then the refinery neither prepares its branch
   nor opens its PR.
7. **Close the convoy.** Append a note to it naming its landing bead and any
   gate step 4 filed, then close it with `gc convoy close`, Gas City's verb for
   closing a convoy whatever its beads' status. Nothing reads its target after
   step 3, and nothing waits on it after step 5.

A write that does not read back stops the move before step 6: the landing bead
is not handed over, the summary task is not armed, the convoy stays open, and
the hand-off records which write failed. A bead in another store is the usual
cause, since bd holds nothing on an edge across two stores.

A convoy that graduation already handed to the refinery carries a branch and a
target of main, so the hand-off passes over it: it finishes as any anchor does.
Between the implementation's merge and the hand-off, a finished convoy waits for
its landing bead, and its open beads still reach its branch through their own
target or their parent link, so nothing lands on main by mistake.

### What the hand-off checks

The hand-off closes once each convoy it moved reads back this way:

- **A held convoy whose beads have all closed**, the case the move exists to
  keep held: its landing bead is assigned to the refinery and waits on the gate
  filed for the hold, bd's ready work leaves it out, and its notice
  (`gc.notify_when_ready`) is still recorded on it, since bd has not reported it
  ready.
- **A convoy that waited on an open bead:** its landing bead waits on the same
  bead.
- **A bead that waited on the convoy:** it waits on the landing bead by the same
  kind of edge, and its edge onto the convoy is gone.
- **A convoy with open beads:** its landing bead and its summary task wait on
  each of them.
- **A finished convoy that nothing held:** its summary task is armed with no
  open blocker of its own, so the next pass dispatches it once no park on its
  epic holds it, and its landing bead waits on that task alone.
- **Every convoy it moved** is closed, with the note that names its landing
  bead.

Unit B's tests pin the refinery's side of the first case: a landing bead held
only by such a gate is not taken until the gate closes (section 12).

## 11. What to correct

Each row says what a living file asserts today and what it says under the design.
Each unit that edits a prompt or a formula regenerates its pages under
`generated/seed-audit/`. Specs are records and are not edited.

| File | Says today | Says under the design | Unit |
|---|---|---|---|
| `formulas/mol-refinery-patrol.toml`, `default_merge_strategy` and merge-push's `merge-strategy-resolve` | the default is `mr`; an `mr` bead aimed at another PR's head with no PR of its own flips to `direct`, recorded in `MS_FOLD_IN`; the comment calls the block the one reading that the step keeping a branch and the step opening a PR share | the default is `direct`; a bead that would land `direct` on the default branch resolves to `mr`; `local` passes through; the flip and its variables go; the comment names merge-push as the block's one reader | A |
| `formulas/mol-refinery-patrol.toml`, handle-failures' `rejection-branch-keep` | decides from its own copy of the resolve block whether a rejected bead's branch survives, and deletes it for a `direct` bead that records no PR and is not a fold-in | goes whole: a rejected branch is kept in every mode, because the repooled rebuild resumes it | A |
| `lifecycle/lifecycle.toml`, `merge_strategy` | an absent key resolves to `mr`; a `polecat/` target with no PR of its own resolves from `mr` down to `direct` | an absent key resolves to `direct`; a bead that would land `direct` on the default branch resolves to `mr`; the fold-in sentence goes | A |
| `assets/scripts/pr-stack.sh` header, and `docs/refinery-merge-cadence.md` | a `merged_target` row "landed its own PR into it" | it landed on the branch, with or without a PR of its own | A |
| `agents/proactive/PROVENANCE.md` item 3, `prompt.template.md` "mr-only for Code", `agent.toml` `[env]`, the header of `tools/gc-proactive.sh`, `tools/proactive-first-reaction-fixture.sh` | the invariant rests on the city's `mr` default and on `GC_DEFAULT_MERGE_STRATEGY`, which nothing reads | code a reaction writes carries `merge_strategy=mr`, and work it routes lands by its target and reaches main only through a PR; the variable, its sentence and the fixture's check go | A |
| `docs/warrants.md` | no entry for the line | warrant 1 | A |
| `assets/scripts/convoy-graduate.sh`, its test, `orders/convoy-check.toml` | graduation; a second hourly `gc convoy check` | deleted | B |
| `assets/scripts/refinery-reconcile.sh` and its test, `orders/refinery-reconcile.toml` | arm 8 runs `convoy-graduate.sh` with an interval stamp, a target lookup and the `REFINERY_RECONCILE_INTEGRATION_AUTO_LAND` switch; the order's description says the cadence graduates convoys | arm 8 goes, with its stamp, lookup and switch; the arm lists and the order's description drop it | B |
| `formulas/mol-refinery-patrol.toml`, header, find-work and prepare step | convoy graduation is the reconcile order's; find-work selects any open, assigned, branch-bearing bead; an idle turn ends with "The session_sleep policy restarts you on the idle interval"; "a graduation bead" is a branch shape | the header drops graduation; find-work leaves a bead `hold-lib.sh` says is held, and says why; an idle turn ends, and the next work handed over or a notice brings the next turn; the prepare step names a landing bead | B |
| `formulas/mol-witness-patrol.toml`, `check-refinery` | every assigned, unprepared bead past the bound is a stuck handoff | a held bead is waiting, not stuck, and is left out of the count | B |
| `doctor/check-refinery-patrol-live` and its test, and `docs/component-model.md`'s I14 row | the queue the check ages is every open, assigned, branch-bearing bead with no `merge_result`, the set find-work selects from | the check leaves a bead `hold-lib.sh` says is held, as find-work does, so a refinery whose queue holds only a waiting landing bead reads as idle, not stalled; the row's definition of the queue says the same | B |
| `lifecycle/lifecycle.toml`, `graduation`, `target`, `merge_strategy` and `rebase_hold` | `convoy-graduate.sh` writes `graduation`, `target` and `mr`, and honors `rebase_hold` | `graduation` stays registered, as retired; the other mentions of graduation go | B |
| `agents/refinery/prompt.template.md` | "a graduated convoy arrives as an ordinary mr-mode work bead"; the cadence runs convoy graduation | a landing bead arrives assigned when its effort is stood up, and is taken once nothing holds it; the cadence's list drops graduation | B |
| `docs/architecture.md`, "How work moves" | one bead per PR, from file to merge | adds that an integration effort's beads land on its branch, and its landing bead carries the branch to main through the one PR | B |
| `docs/refinery-merge-cadence.md`, `docs/state-machine.md`'s convoy graduation, `docs/component-model.md`'s Convoy primitive and its rows for `convoy-graduate.sh` and `convoy-check.toml`, `docs/review-correctness.md`'s example | graduation is cadence arm 8 and a transition on the convoy bead; a convoy is a "tracked set with one landing target" without which "integration branches cannot graduate"; a pack order beside core's; the loop-input example cites `convoy-graduate.sh` | arm 8 and the transition go; a convoy is Gas City's status grouping and a run's input, and a landing bead carries an effort to main; the two rows go; the example cites another script | B |
| `services/helm/internal/board/derive.go` and its test, and the web board's sample row in `services/helm/web/src/board.fixture.json` and `services/helm/web/contract_parity_test.go` | a finished convoy's row reads "all N closed — graduate" | it reads that every tracked bead is closed | B |
| the comment in `services/gctk/cmd/gctk/main.go`, and `services/gctk/README.md` | each lists convoy-graduate among the cadence's scripts | the lists drop it | B |
| graduation fixtures in `pr-facts.test.sh` and `pre-open-rebase.test.sh`, a comment in `deferred-dispatch.test.sh` | a graduation bead | a landing bead | B |
| `assets/scripts/convoy-seed.sh`, its test, `mol-design-convoy-seed-invoke.test.sh`, `mol-design-convoy-subject-close.test.sh` | the seed script, its tests, and the subject's close through an `until` edge and the drain | deleted | C |
| `formulas/mol-design-convoy.toml` | seed-convoy runs `convoy-seed.sh` and writes the subject's `until` edge onto the convoy; the arm steps link each child parent-child and rely on the link for the target; the design child is slung with no merge flag; the drain hands the subject to the convoy; graduation carries the convoy to main | the seed step cuts `integration/<subject-id>` and records the branch on the subject; each child is filed with its target and the subject's `blocks` edge, both read back; a summary step files the summary task beside the subject, with its `blocks` edge on each child and the subject's onto it, and reads them back; a last step reads the whole setup back, hands the subject to the refinery, slings the design child, `--merge mr` when design-gated, and arms the summary task on `mol-polecat-report`; the drain step goes; the subject's PR carries the effort to main, with the summary its summary task wrote | C |
| `assets/scripts/mol-design-convoy-arm.test.sh` | pins the parent-child link and its read-back | pins the target in each create, the subject's `blocks` edges and their read-back, the design child's `--merge mr`, the subject's hand-off only once the whole setup reads back and before anything is dispatched, and the summary step's writes and their arm (section 12) | C |
| `agents/mechanik/prompt.template.md`, the dispatch doctrine and its recipe | "an owned convoy is the PR unit"; a lone bead is the one-child convoy; `convoy-seed.sh` with `--artifact`; each child linked parent-child; graduation | a PR comes from one bead, and a lone bead needs nothing else; an effort is a landing bead, one push, three writes per bead and a summary task (section 3); a bead that joins once the summary task has been dispatched waits on a fresh one; a shared input artifact is the first bead; a bead that builds on work reaching main after the cut waits on the mechanik's hand-off; an effort is ranked and parked through its epic | C |
| `template-fragments/polecat-doctrine.template.md`, integration branches | a child carries the target "which the owned-convoy recipe stamps when it links the child"; workspace-setup cancels a child poured from the wrong base; graduation | a bead filed for an integration effort carries the effort's branch as its own target from its create; its work lands there with no PR unless it is a stage; the landing bead carries the branch to main; a summary task writes its landing bead's `pr_summary` from the finished branch, and this paragraph is the one statement of how (section 4); the metadata table's `pr_summary` row names a summary task as that key's other writer | C |
| `skills/prs/SKILL.md`, supplements | a supplement's target under an owned convoy is `integration/<convoy-id>` | a supplement's target is its PR's base: the integration branch for a stage's PR, main for a landing bead's | C |
| `formulas/mol-polecat-work.toml`, submit step 1b, and `formulas/mol-review.toml`, step 3 | a caller-set target includes "an owned convoy its integration branch"; "A convoy child lands on `integration/<convoy-id>`" | a bead filed for an integration effort carries the effort's branch; a bead of an effort lands on its integration branch | C |
| `docs/design-convoy.md` | the seed script; the subject closes when its owned convoy closes; each child's PR needs the operator's approval; graduation | the push and the subject as landing bead; the design child is a stage, the implementation lands with no PR, and the subject's PR is the second gate; all-in-one has one PR, the subject's; the summary task writes the subject's PR summary once the children have landed | C |
| `lifecycle/lifecycle.toml`, `pr_summary`, and the sentence of `docs/refinery-merge-cadence.md` that names its writer | the polecat writes it on the anchor at submit, its handoff | so does a landing bead's summary task, once the effort's work has landed | C |
| `docs/epics.md`, "A checkpoint is always qualified" | a PR Checkpoint "lands a phase of work on a convoy's integration branch" | it lands a stage on an integration branch | C |
| `formulas/mol-polecat-work.toml`, workspace-setup's convoy target guard, and its test | declines a convoy child poured from a base that is not its convoy's target | deleted | D |
| `assets/scripts/pr-status-label.sh` and its test | the `base:` group and its `mark-base` verb | they go, and the `status:` group stays | E |
| `assets/scripts/pr-summary-region.sh` | a banner on a PR into `integration/*` | it goes | E |
| `assets/scripts/pr-open.sh` and its test | calls `mark-base` at create and at adoption; pins the banner and the label | the calls and the cases go | E |
| `docs/state-machine.md`, the base label section | the `base:` label and the banner | it goes | E |
| the 19 shell and formula copies of the lookup (section 6) and their tests | each reads the input convoy its own way | each calls the shared reader, and its test stubs the reader | F |
| `services/helm/internal/source/facts.go` | a Go copy of the lookup | the same, tested against the reader's fixture | F |
| `assets/scripts/live-work.sh`, `assets/scripts/until-resolved.sh`, `docs/deferred-dispatch.md`'s list of live-work marks, `docs/component-model.md`'s `live-work.sh` row | any convoy that tracks a bead, closed ones included, marks it live | a live run working the bead marks it live, from the reader's map | F |
| `docs/authority-map.md`, the drain row | the drain hands a design-convoy subject to its owned convoy, which `merge.sh` closes as the graduation PR's anchor | the row goes, with the drain | C |
| `docs/warrants.md`, the priority-following entry | covers `queue-priority.sh` and `priority-lib.sh` | re-verified, since unit F changes both | F |

What stays as it is: the anchor and I4 in `docs/component-model.md`, with
`doctor/check-one-anchor-per-pr`, since an effort's beads own no PR; `merge.sh`'s
approval rule; the rule that `existing_pr` forces `mr`; the parent readers of
section 2; the one-bead input convoy of `mol-polecat-work`; and the formulas'
own derivation of their bead.

## 12. The implementation cut

The fix cannot use itself. Until it reaches main, main's refinery still defaults
to `mr`, and its find-work takes a bead that waits, so a landing bead cannot be
handed over at setup. The implementation therefore runs on main's machinery as
it stands, one last time: one owned convoy on `integration/<convoy-id>`, one
member per unit below, each added with `gc convoy add`, carrying the convoy's
target, and slung `--merge direct` or armed behind the unit it waits on. Main's
graduation counts `tracks` members, and main's guard passes a member that
carries its own target, so the convoy reaches main as the one PR the operator
reviews. When that PR merges, graduation leaves main in the same commit that
makes the landing bead the way an effort lands.

| Unit | What it changes | Its tests | Waits on |
|---|---|---|---|
| A. The default and the one line | `default_merge_strategy` and merge-push's `merge-strategy-resolve` in `formulas/mol-refinery-patrol.toml`, whose `rejection-branch-keep` goes; the `merge_strategy` entry of `lifecycle/lifecycle.toml`; the `pr-stack.sh` comment and the `docs/refinery-merge-cadence.md` line; the proactive pool's `PROVENANCE.md`, prompt, `agent.toml`, `tools/gc-proactive.sh` header and fixture; warrant 1 | `mr-aware-rejection-failclosed.test.sh`, as listed below; `tools/proactive-first-reaction-fixture.sh`; `render-seed-audit.sh --check` | nothing |
| B. The landing bead reaches the refinery | deletes `convoy-graduate.sh`, its test, `orders/convoy-check.toml`, and arm 8 of `refinery-reconcile.sh` with its stamp, lookup and switch; find-work, `check-refinery` and `doctor/check-refinery-patrol-live` read a hold through `hold-lib.sh`; the header, find-work and prepare step of `mol-refinery-patrol.toml`; `graduation` registered as retired; the refinery's prompt; the docs, helm and gctk rows of section 11 | `find-work-gating-guard.test.sh`, `refinery-stuck-escalate.test.sh` and `doctor/check-refinery-patrol-live/run.test.sh`, as listed below; `refinery-reconcile.test.sh` without arm 8; the helm board's tests; `render-seed-audit.sh --check` | A |
| C. Recipes on the landing bead | deletes `convoy-seed.sh` and its test, `mol-design-convoy-seed-invoke.test.sh` and `mol-design-convoy-subject-close.test.sh`; `mol-design-convoy`'s seed step, arm steps and drain, and its new summary step; the mechanik's doctrine and recipe; the polecat doctrine's paragraph, with the summary task's method; the `prs` skill; the two formula sentences; the `pr_summary` entry of `lifecycle/lifecycle.toml` and the sentence of `docs/refinery-merge-cadence.md` that names its writer; `docs/design-convoy.md` and the checkpoint sentence of `docs/epics.md` | `mol-design-convoy-arm.test.sh`, as listed below; `skill-needs.test.sh`; `render-seed-audit.sh --check` | nothing |
| D. The guard | deletes workspace-setup's step 1b in `mol-polecat-work.toml` and `workspace-setup-convoy-target-guard.test.sh` | `decline-wiring.test.sh`, which scans every decline in the formula; `workspace-setup-worktree-rig.test.sh` and `workspace-setup-record-worktree-gate.test.sh` | nothing |
| E. The banner and label | `pr-status-label.sh`, `pr-summary-region.sh`, `pr-open.sh`; the base label section of `docs/state-machine.md` | `pr-status-label.test.sh`; `pr-open.test.sh` | nothing |
| F. One shared reader | adds the reader and its fixture; moves the 19 copies onto it; `live-work.sh` and `until-resolved.sh` read a live run; the helm board's Go copy is tested against the fixture; the docs rows of section 11 | the reader's suite; each caller's suite, stubbing the reader; `live-work.test.sh`; `go test ./...` in `services/helm`; `render-seed-audit.sh --check` | C |

Each unit is one concern a reviewer can hold. A, C, D and E start together. B
waits on A, because both edit the refinery formula, its generated page and the
lifecycle registry's `merge_strategy` entry. C's edits to that registry and to
`docs/refinery-merge-cadence.md` are an entry and a sentence that neither A nor B
edits, so C waits on nothing. F waits on C, because C deletes
`mol-design-convoy-subject-close.test.sh`, which pins how `live-work.sh` reads the
keys the drain leaves, and F changes that reading. Each wait is a `blocks` edge
with an armed dispatch. The default, the hand-off and the recipes reach main
together, in the one PR, so no effort is stood up between a default that would
land a design child with no PR and the `--merge mr` that keeps the design gate.

Until unit A reaches main, the refinery still deletes a direct member's branch
when its gate fails because of the branch, and the rebuild stops at the
missing-branch visit. The release is to restore the branch from the member's
worktree, or to clear `metadata.branch` so the rebuild starts again from the
convoy's branch.

The units, and the hand-off of section 10, are filed from this section as it
reads on main once this design merges (tk-zkft1ym), so a change made in this
design's review leaves no filed bead describing an older cut. They take over the
graduation and integration-branch scope of the migration epic's convoy member
(tk-1tfzr71.23), whose remaining scope, the parent readers, carries no convoy
code.

### Unit A's tests

`assets/scripts/mr-aware-rejection-failclosed.test.sh` pins the merge strategy and
the rejection arm. Its one fill of the formula's default, `${2:-mr}`, sits in the
`arm` helper, which goes with the arm, so the resolve block's own cases below
fill the default as `direct`, the formula's new value.

- **The rejection arm goes, and so does the section that runs it:** the arm's
  extraction, its `git` stub and its `arm` helper, and that section's cases (6)
  to (21). One check replaces them: the handle-failures step deletes no branch.
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
  check that counts call sites expects one, and the check that the two resolve
  blocks are byte-identical goes. The check that no step reads `merge_strategy`
  outside the block stays.

### Unit B's tests

Unit B is accepted on its first case, the one the change exists for.

- **A landing bead waits, then is taken.** In `find-work-gating-guard.test.sh`,
  the formula's find-work selection block runs over a store that holds a landing
  bead assigned to the refinery, carrying `branch=integration/cv-1` and
  `target=main`, with a `blocks` edge on each of two effort beads and on its
  summary task. While either effort bead is open, the block selects nothing.
  Once the second closes, the block still selects nothing while the summary task
  is open, and once that closes, the block selects the landing bead, so the
  refinery never prepares a landing bead before its summary task has closed.
  Unit A's case for a bead aimed at main resolves
  it to `mr`, and from there it takes the path to its PR that every bead bound
  for main takes.
- **A carried hold waits.** A landing bead whose effort beads have all closed,
  and whose one open blocker is a gate with no await type, the gate section 10
  files for an open convoy's hold, is not selected. Once the gate closes, the
  block selects it.
- **A handoff waits only on a blocker of its own.** A polecat's handoff with no
  blocker is selected, and so is a handoff whose epic is parked, since a hold on
  an ancestor leaves work in flight running. A handoff with an open blocker of its
  own waits.
- **A hold that cannot be read takes nothing.** A blocker the store does not
  return holds the bead, and a listing that fails ends the turn as an unreadable
  queue does today.
- **The witness waits too.** In `refinery-stuck-escalate.test.sh`, a held landing
  bead past the stuck bound files no visit, and an unheld handoff past the bound
  still does.
- **The doctor waits too.** In `doctor/check-refinery-patrol-live/run.test.sh`, a
  refinery whose queue holds only a held landing bead past the bound, beside a
  patrol wisp that has rested past it, reads as idle, and an unheld handoff in the
  same state still reads as stalled.

The deferred-dispatch suite already pins the notice: sent once `bd` reports an
assigned bead ready, kept while it waits.

### Unit C's tests

Unit C is accepted on the case the summary task exists for: an effort whose
finished scope differs from its setup description opens its PR with a summary of
the finished work.

- **The summary task waits for the finished scope.** In
  `mol-design-convoy-arm.test.sh`, the summary step runs over a subject under an
  epic, whose description names the planned work. It files the summary task
  under that epic, with no `target` and a description that names the subject,
  writes the task's `blocks` edge on the design child and on the implementation
  child and the subject's edge onto the task, and reads all three back. The
  dispatch step arms the task on `mol-polecat-report` only once every edge of
  the setup reads back. Each write that fails to read back, in a case of its
  own, fails its step with nothing armed. A resume over edges that already read
  back completes the step, and the dispatch step arms the task once.
- **The rest of the path is pinned where it runs.** The deferred-dispatch suite
  pins that an armed bead is not slung while a blocker of its own, or a park on
  its epic, holds it, and that its arm fires once that hold releases. So the
  summary task runs after the effort's last bead lands, including a bead that
  joined after setup with the summary task's edge. Unit B's first case pins
  that the refinery takes the landing bead only after the summary task closes.
  `pr-open.test.sh` pins that an anchor's `pr_summary` is the PR's
  `## Summary` and its description is demoted to the dispatch section. So the
  PR opens with what the summary task wrote from the finished branch, not with
  the description written at setup.
- **The words are checked where every summary's are.** What the summary says is
  the summary task polecat's account. The pre-open correctness check reads it
  against the whole branch, as it reads every anchor's pending summary, and
  sends back one that restates the dispatch or leaves out work the branch
  carries.

### Unit F's tests

The reader's suite runs each verb over a fixture store: a live run and a finished
run over one bead, a run whose input convoy names no bead, a legacy run that
records `issue`, and a store read that fails, which fails the verb rather than
reading as no runs. The same fixture drives the Go copy's test. Each caller's
suite keeps its cases and stubs the reader in place of the convoy reads, and
`live-work.test.sh` gains the case the change exists for: a bead a closed convoy
tracks, with no live run, is not live work.
