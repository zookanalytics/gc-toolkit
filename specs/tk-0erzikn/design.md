---
name: A PR is one reviewable unit, built on Gas City's convoy — the design
description: The design for the operator's PR model, rebuilt on Gas City's own convoy model by the operator's ruling of 2026-10-19 and measured by its four tests. A convoy tracks its members the way Gas City does, each member carries its convoy's branch as its own target and lands there with no PR, work landing on main or on any branch the pack does not cut for its own work goes through a PR, and a convoy's work reaches main as one PR. It settles the default, membership and a member's branch, when the convoy's branch is cut and how it is brought current, where each review runs, how the convoy lands and rework returns, the nouns that have diverged from Gas City's, which living files change, and the implementation cut. Read it to review the model before it is codified, or to build one of its units. Its inputs are brief.md and findings.md beside it.
---

# A PR is one reviewable unit, built on Gas City's convoy

## The decisions, in one screen

Today a bead that names no merge strategy opens its own PR, and a convoy's
members are no exception, because gc-toolkit's refinery delivers such a bead
through a PR. A convoy of seven changes reaches the operator as seven PRs into
its branch and an eighth into main, and each waits for an approval. Under this
design the convoy's PR into main is the only one, unless the operator asks to
review a stage on its own.

1. **A convoy tracks its members the way Gas City does.** A member is added
   with `gc convoy add`, which links it by a `tracks` edge and leaves its parent
   alone, so a member can also sit under an epic. Today's recipes make each
   member the convoy's parent-child child instead.
2. **A member carries its convoy's branch as its own `target`.** Gas City's
   sling passes a convoy's target only down a bead's parent chain. So the step
   that adds a member also writes the convoy's `target` onto it, a key
   that sling and the refinery already read first, and workspace-setup's guard
   declines a member poured without it. This is the design's one platform gap,
   recorded in section 1 with its date and the trigger that retires the write.
3. **The refinery's default becomes Gas Town's, and every branch but a
   convoy's keeps its PR.** A bead that names no merge strategy lands `direct`,
   as Gas Town's refinery lands it. A `direct` landing goes through a PR
   instead unless it lands on a convoy's branch or on another PR's head, even
   where the branch it lands on is unprotected. So a member lands on its
   convoy's branch with no PR, while a lone bead's work, a convoy's own landing
   and work aimed at any other branch go through a PR. The decision is the
   default's value and one rule in the refinery's resolve block, the PR rule.
   The rule takes the place of the block's fold-in flip, and the rejection
   arm's branch decision goes, since without its delete it has nothing left to
   decide, so the refinery formula ends up shorter. Section 2 lists all that
   unit A changes and measures it against the operator's "about 1-2 lines"
   bar.
4. **A stage is a member slung `--merge mr`.** It opens its own PR into the
   convoy's branch, for the operator to review on its own.
5. **Merge strategies mean what Gas City says they mean.** The refinery reads
   only the bead's own `merge_strategy`, and nothing reads a convoy's
   `convoy.merge`. The PR rule in decision 3 is the one exception this design
   adds, and the fold-in flip, which turns an `mr` aimed at another PR's head
   into `direct`, goes. `local` stays work left on its branch for its consumer,
   whatever its target. Nothing turns it into another strategy, nothing turns
   another strategy into it, and the refinery refuses it as unsupported, as it
   does today.
6. **A member is reviewed in its own molecule, and the convoy's PR gets the
   overall review.** A member passes its self-review loop and the refinery's
   gate before it lands. The city's checks and the operator's review run once,
   on the convoy's PR.
7. **An owned convoy lands as Gas Town lands one.** When every member is
   closed, the convoy's bead becomes the work bead that carries its branch to
   main, the way Gas Town's refinery takes an owned convoy. gc-toolkit already
   does this, and nothing is built.

What it costs:

- A member added without its `target` is declined at workspace-setup before
  any branch is cut, and waits on a visit that asks for the target. The recipes
  write the target in the same step that adds the member, so only a skipped
  step costs that.
- A member that builds on work reaching main after its convoy was seeded waits
  for the mechanik to bring the convoy's branch current, one fast-forward or
  merge (section 3).
- Ranking or parking a convoy no longer ranks or parks its members, because
  Gas City's tracking changes no parent and blocks nothing. The members, or the
  epic they sit under, are ranked and parked instead (section 1).

What it rules out: reading `convoy.merge` at the refinery and mapping `local`
onto `mr`, a converter the four tests ban; a workspace-setup step that discards
a run and pours it again as its normal path, which is a recovery layer; reading
the convoy that tracks a bead at the refinery, to tell a convoy's branch from
any other, which is plumbing; and any change to Gas City.

Unchanged: every PR still needs the operator's approval, and every PR still has
exactly one owning bead (invariant I4), the issue or the convoy it came from.

## The model

The operator's words, from [brief.md](brief.md):

> "It's not about my approval being required on every PR. It's that a convoy can
> include multiple pieces of work, and that should all land as a single PR."

> "A PR has an issue or a convoy that it came from."

> "polecats self-review, so a defect in an early member is caught during the
> self-review. Big picture items aren't caught until later, but that's what the
> PR is looking for, not each individual step"

> "We USE Gas City, not fight it or simply ignore it."

The model, as the brief states it:

1. Every PR is the operator's. The city opens a PR, into main or into a convoy's
   branch, only to ask for the operator's review.
2. A PR comes from one issue or one convoy. Work that reaches the operator as
   one PR is a convoy, whose members land on its branch with no PRs of their
   own. A PR into main is a complete unit of work.
3. Each member is reviewed inside its own work molecule before its work lands.
   The PR gets the overall review.
4. The city works in as many internal phases as it needs before it opens a PR.
5. Multi-stage work is more than one PR. Every reviewable unit is a PR.
6. A convoy is Gas City's concept, used as Gas City defines it.

The design's words are Gas City's. A **member** is a bead its convoy tracks. A
**stage** is a member the operator reviews on its own, through a PR into the
convoy's branch. A PR's **owning bead** is the issue or the convoy it came
from, which gc-toolkit's component model calls the anchor.

## What Gas City provides

Read on 2026-10-19 in Gas City's documentation and code, as installed (`gc`
1.4.3), and in the Gas Town and build packs it bundles.

- **A convoy groups work and tracks it.** "A convoy is a container bead that
  groups related work so you track a batch as a unit" (its "How Gas City Works"
  page). Its membership is `tracks` edges from it to each member. "Tracking is
  pure grouping: it changes no parent and blocks nothing", and members "are not
  children of the convoy" (its beads tutorial). `gc convoy add` adds "a tracks
  dependency from the convoy to the issue ... without changing the issue
  parent". Gas City still reads parent-child membership, which it calls legacy
  (its `convoy` package).
- **A convoy's target reaches only its children.** `gc convoy create --target`
  names the "target branch inherited by child work beads". Sling branches a bead
  from its own `target`, else from the `target` of a convoy it finds by walking
  the bead's parent chain, else from the rig's default branch
  (`SlingFormulaTargetBranch` and `BeadMetadataTarget`, in its `sling` package).
  A member that its convoy only tracks inherits nothing.
- **A merge strategy is the bead's own `merge_strategy`.** `direct` merges the
  work branch into its target, `mr` delivers it through a merge or pull request,
  and `local` leaves it on its branch with no merge and no request, so that the
  consumer decides (its `beadmeta` package). An absent key is unset, and each
  consumer reads unset as its own default. `gc sling --merge` stamps the key,
  and so does a rig's `default_merge_strategy` in `city.toml`, which no rig in
  this city sets. A convoy's `convoy.merge` is written by
  `gc convoy create --merge` and printed by `gc convoy status`, and nothing in
  Gas City or its bundled packs reads it.
- **An owned convoy ends when it is landed.** `--owned` marks a "manual
  lifecycle, no auto-close". `gc convoy land` "verifies all children are closed
  ..., closes the convoy bead, and records a ConvoyClosed event". It moves no
  branch. A convoy without the `owned` label closes itself once all its members
  are closed.
- **Gas Town's refinery lands `direct` unless told otherwise.** It reads
  `merge_strategy` with `direct` as the default, turns `direct` into `mr` for a
  bead that carries an existing PR, and escalates `local` as unsupported. With
  `integration_branch_auto_land` on, which is off by default, it takes an owned
  convoy whose children are all closed by assigning the convoy's bead to itself
  with the integration branch as its `branch` and the default branch as its
  `target`, and lands it like any work bead (Gas Town's `mol-refinery-patrol`
  formula).
- **The build pack drains a convoy and publishes once.** `build-from-convoy`
  runs each member in its own worker session and worktree, in parallel, then
  reviews the whole result, repairs it, and can push and open one PR. Push and
  PR are off by default. It reads no merge strategy and uses no integration
  branch (the build pack's README and its formulas).

## What gc-toolkit does today

- **The refinery defaults to `mr`.** Its `merge-strategy-resolve` block, at both
  call sites in `formulas/mol-refinery-patrol.toml`, takes the bead's own
  `merge_strategy`, else `vars.default_merge_strategy`, which is `mr`. It turns
  `mr` into `direct` for a `polecat/*` target that records no PR of its own, the
  fold-in ([specs/tk-sw5bu](../tk-sw5bu/merge-strategy-fold-in.md)), and an
  `existing_pr` forces `mr`. The formula lands `direct` and `mr`, and it has no
  step for `local`.
- **Recipes make each member the convoy's child.** The mechanik's seed-and-link
  recipe (`agents/mechanik/prompt.template.md`) links each member to the convoy
  with a parent-child edge and also stamps the convoy's target on it.
  `formulas/mol-design-convoy.toml` links its design and implementation children
  with a parent-child edge and relies on that edge alone for their target.
- **Graduation carries a finished convoy to main.** `convoy-graduate.sh` takes
  an open owned convoy that targets `integration/*` once every member is closed
  and a landing on its branch is recorded. It counts members in both forms, as
  parent-child children and as `tracks` targets. It assigns the convoy's bead to
  the refinery as an `mr` work bead with `branch=integration/<id>` and
  `target=main`, which is the shape of Gas Town's auto-land. The bead closes
  when its PR merges, like any PR's owning bead, rather than through
  `gc convoy land`.
- **A rejected direct bead loses its branch.** When the refinery's gate fails
  because of the branch, it repools the bead with `metadata.branch` kept, and its
  `rejection-branch-keep` block then deletes that branch on origin when the bead
  resolves `direct` and records no PR. The rebuild resumes `metadata.branch`,
  finds no branch, and stops at workspace-setup's missing-branch visit. Case (9)
  of `assets/scripts/mr-aware-rejection-failclosed.test.sh` pins the delete.
- **workspace-setup guards parent-child members only.** The convoy target guard
  in `formulas/mol-polecat-work.toml` reads the bead's parent-child convoy
  parents, and files a visit when the run was poured from a branch that is not
  theirs.
- **Reviews.** A member's work molecule runs the self-review loop, and the
  refinery runs the rig's gate on the prepared head before it lands anything.
  The city's checks run on a PR's owning bead: correctness, triage, arch and pm
  before the PR opens, and demo while it is a draft (`review-checks.toml`).

## 1. Members are tracked, and carry their convoy's branch

### Decision

A convoy's members are added with `gc convoy add <convoy> <member>`. The same
step writes the convoy's `target` onto the member, reads the edge and the
target back, and slings the member, or arms it when it waits on other work. A
member keeps whatever parent it has. The mechanik's recipe and
`mol-design-convoy` change to this, and neither writes a parent-child edge to a
convoy. workspace-setup's convoy target guard reads the convoys that track a
bead as well as its parents, so a member poured without its target is declined
before any branch is cut (below).

### Why

- It is Gas City's membership. A convoy groups its members without being their
  parent, so a member that belongs to an epic and to a convoy records two plain
  facts: one parent edge and one `tracks` edge. The parent-child link asks the
  one parent edge to carry both, which is why a member under an epic could be
  poured from main.
- Sling and the refinery already take a bead's own `target` first, so the write
  uses a key both read, and nothing new reads it.
- The readers that count a convoy's members already read `tracks`.
  `convoy-graduate.sh` counts both forms, and Gas City's `gc convoy status`,
  `gc convoy land` and autoclose read both.

### The gap, with its warrant

- **Recorded:** 2026-10-19, against Gas City as installed (`gc` 1.4.3): the help
  of `gc convoy add` and `gc convoy target`, Gas City's beads tutorial, and
  sling's target lookup.
- **What Gas City cannot express:** a convoy's `target` for a bead the convoy
  tracks. Sling finds a convoy's target only through a bead's parent chain, and
  Gas City documents it as the target "inherited by child work beads".
- **The bridge:** the convoy's `target` written onto the member when it is added.
  It is one write of Gas City's own key, which sling reads first as the bead's
  own target. It adds no key, no state and no reader.
- **What else rests on it:** workspace-setup's convoy target guard reads the
  convoys that track a bead, to decline a member poured without its target. It
  reads Gas City's own edge and key and files the guard's existing visit.
- **Retirement trigger:** Gas City's sling resolving a target through `tracks`
  membership. Then the recipes stop writing the member's target, and the member
  takes its branch from its convoy. Sling then pours a tracked member from its
  convoy's branch, so the guard's read of `tracks` has nothing left to catch.
- **Where it is recorded:** unit C adds the entry to `docs/warrants.md`,
  covering the recipes' write and the guard's read.

### When the write is missed

A member added without its target would branch from main and land with main as
its target. Its work would reach the operator as a PR into main of its own, the
convoy's PR would leave that work out, and graduation would count the member as
closed wherever it landed. Nothing would say the model broke, so the miss is
caught where it still costs nothing, before any branch is cut.

workspace-setup's convoy target guard catches it. Today the guard reads only a
bead's parent-child convoy parents. Under this design it reads the convoys that
track the bead as well, through Gas City's `tracks` edge, as Gas City's own
convoy code reads membership in both forms. A member poured from a branch that
is not its convoy's target then takes the guard's existing decline: its run is
cancelled before any worktree exists, and the member waits on a visit that
names the convoy and asks for the target. Stamping the target and closing the
visit re-slings the member, which then pours from the convoy's branch. The
guard counts only a convoy that names a target, so the input convoy each pour
makes is not read as membership. The guard asks which convoys a bead belongs
to, which is what a `tracks` edge records, so it reads the edge for its own
meaning. The readers below ask about a bead's parent, and stay as they are.

The decline ends a run only for a member whose add skipped the write. The
recipes write the target in the same step that adds the member, and the guard
passes it, so a discarded run is the signal of a failure and never a step of
normal operation. The guard reads native edges and Gas City's own `target` and
files the visit it already files, so it adds no key, no state and no claim of
its own. Graduation is not where the miss is caught: it is one of the nouns
that have diverged from Gas City's (section 7), and by the time it counts
members the stray PR has already been opened. A bead that has started records a
branch, which the guard resumes without checking, so a convoy adds only beads
that have not started, as both recipes do.

### What tracking changes in gc-toolkit

Some gc-toolkit readers find a bead's convoy through its parent edge. A tracked
member has no convoy for a parent, so each of these reads it as it reads any
bead whose parent is not a convoy:

- `priority-lib.sh` makes a bead follow its most urgent parent. A member follows
  its epic, or keeps its own priority, and a convoy's priority no longer ranks
  its members.
- `hold-lib.sh`, which `deferred-dispatch.sh` and `gc-helm.sh park` use, holds a
  parent's children with it. Parking a convoy no longer holds its members' armed
  dispatches, and the park survey lists nothing under a convoy. A convoy's work
  is held by parking its members, or the epic they sit under.
- `converse-parent.sh` files a sitting's follow-up beside its subject, under the
  subject's parent. Follow-up from a member joins the member's epic, and joins
  the convoy only when the sitting adds it.
- `placement.sh` counts a bead marked for placement as placed once it has a
  parent. A marked bead that is only added to a convoy stays unplaced until it
  is routed. The recipes do not mark members.
- `bead-context.sh` shows a member's convoy as tracking it, not as its parent.
- `tools/gc-proactive.sh` reacts only to beads with no parent, and a member
  with no epic now has none. The scan skips routed, armed and in-flight beads,
  and the recipes sling or arm a member in the step that adds it, so the scan
  does not reach one.

None of these readers changes. Each reads parents, and a Gas City convoy is not
its members' parent: tracking "changes no parent and blocks nothing". Making
these readers treat a `tracks` edge as a parent would add semantics to a native
relation, which the four tests rule out.

## 2. The default: `direct`, and a PR for every branch but a convoy's

### Decision

The decision is two changes to `formulas/mol-refinery-patrol.toml`:

1. `vars.default_merge_strategy` becomes `direct`.
2. The `merge-strategy-resolve` block gains the PR rule: a bead that would land
   `direct` resolves to `mr` unless its target is a convoy's branch,
   `integration/*`, or another PR's head, `polecat/*`. It applies whether the
   bead names `direct` or names no strategy. A bead with no `target` lands on
   the default branch, so it resolves to `mr`.

So:

- A member, whose target is its convoy's branch, lands there with no PR.
- A lone bead's work, a graduated convoy, a rework of a PR into main and a
  supplement to such a PR all go to main, so each goes through a PR, as each
  does today.
- A bead aimed at any other branch, such as a named or long-lived one, goes
  through a PR, as it does today when it names no strategy. One that names
  `direct` goes through a PR too, as one aimed at main does.
- A member slung `--merge mr` is a stage and opens a PR into its convoy's
  branch.
- A bead aimed at another PR's head that names no strategy lands on that head
  and folds into its PR, as it does today.
- A `local` bead stays `local` whatever its target, and the refinery refuses it
  as unsupported (below).
- The rule that `existing_pr` forces `mr` stays as it is.

### What unit A changes, measured against the operator's bar

The operator asked for "about 1-2 lines, to change the default. Not a bunch of
plumbing." The decision is the default's value and the PR rule. Everything else
unit A changes follows from them, and none of it adds plumbing:

- **The PR rule takes the place of the fold-in flip.** Today the resolve block
  turns an `mr` bead aimed at another PR's head, with no PR of its own, into
  `direct`, so its work folds onto that head instead of opening a nested PR
  ([specs/tk-sw5bu](../tk-sw5bu/merge-strategy-fold-in.md)). The beads it
  exists for come from a dispatch that names no strategy, and under the
  `direct` default they land on the head with no flip. The pack's scripts that
  stamp `mr` are `convoy-graduate.sh` and the feedback distiller, which aim at
  main, and `rework-child.sh`, `pr-facts.sh` and `pre-open-rebase.sh`, which
  give a child its anchor's target. A bead aimed at a PR's head lands there as
  a fold and anchors no PR, so no child inherits that aim. So the flip goes,
  and an `mr` aimed at a PR's head means a PR into it, as Gas City defines
  `mr`. The flip's variables, `MS_FOLD_IN`, `MS_BRANCH` and `MS_HAS_OWN_PR`,
  go with it, and the block reads only the strategy and the target.
- **The rejection arm's branch decision goes.** On a branch-caused rejection,
  `rejection-branch-keep` decides whether the bead's branch survives, and it
  deletes the branch only for a `direct` bead that records no PR. Under the
  `direct` default every member is such a bead, and the rebuild that the same
  arm's repool starts resumes that branch, so a delete would stop every member
  whose gate fails at workspace-setup's missing-branch visit. Without the
  delete, every path through the decision keeps the branch, so the decision
  goes whole: its copy of the resolve block, and `MS_FOLD_IN`, whose only
  reader it is. merge-push's copy of the block is then the one reading of the
  strategy. A branch is still deleted when its work lands, by
  `delete_merged_branches` after a direct landing and by the repository's
  delete-on-merge after a PR.
- **Words and tests.** The `merge_strategy` entry in `lifecycle/lifecycle.toml`,
  the resolve block's own comment, the `pr-stack.sh` comment, a line of
  `docs/refinery-merge-cadence.md`, the proactive pool's doctrine (section 8),
  and the tests in `mr-aware-rejection-failclosed.test.sh` (section 9) change to
  match.

So the formula gains a default's value and one rule, and loses the fold-in
flip and the rejection arm's branch decision.

### Why

- Gas City leaves an unset strategy to its consumer, and Gas Town's refinery
  reads it as `direct`. gc-toolkit's `mr` default is the reason a convoy's
  member opens a PR at all.
- What the `mr` default protects is a branch that work would otherwise reach
  with no review. The operator's invariant names main: a change to main goes
  through a PR even where main is unprotected. A named or long-lived branch is
  protected the same way today, by the same default. The PR rule keeps both, as
  a rule about where work lands rather than a default for every branch. It
  applies to `direct` alone, because `direct` is the only strategy that changes
  a branch without a PR: `mr` changes it through one, and `local` lands
  nothing. Turning `local` into `mr` would open a PR for work that asked for no
  merge and no request.
- The rule keys on the names of two branches. A convoy's branch and another
  PR's head are the two places where work lands with no PR of its own and
  reaches main later through one, the convoy's or the PR whose head it is. The
  bead alone does not say whether its target is a convoy's branch, and reading
  the convoy that tracks it would add a lookup to the resolve block, the
  plumbing the operator's bar rules out. The pack names both branches itself:
  `convoy-seed.sh` cuts every convoy's branch as `integration/<convoy-id>`, and
  workspace-setup cuts every bead's branch as `polecat/<bead-id>`. Graduation,
  the PR banner and the `base:` label already key on `integration/*`. A branch
  of any other shape gets a PR, so a branch the pack did not name errs toward a
  review, never away from one.
- Reading the convoy instead, the first design's predicate over `convoy.merge`,
  reads a field Gas City writes for display and needed a converter for `local`.
  The PR rule needs neither.
- Gas City's own flags keep working where work lands with no PR of its own:
  `--merge mr` makes a stage, and `--merge direct` lands directly on a convoy's
  branch or another PR's head.

### `local`

`local` leaves the work on its branch with no merge and no request, so it lands
nothing and the PR rule does not apply to it. The resolver passes it through
unchanged, whatever its target. gc-toolkit's refinery has no landing for
`local`, so its `merge-push` step refuses it as unsupported, as it does today:
it transitions nothing and escalates the bead for a person to choose a
strategy. Gas Town's refinery stops on `local` and escalates it the same way.
This design neither slings `local` nor maps it onto another strategy.

### The proactive pool's rule

The proactive pool's doctrine says that code a reaction produces takes the
correctness-gated `mr` path, never `direct`. It names two things that enforce
it, the city's default and the pool's own `GC_DEFAULT_MERGE_STRATEGY`, and says
that work a reaction routes goes to the polecat pool, "whose default is `mr`".
Neither enforces it today. No rig's config sets `default_merge_strategy`, the
key Gas City's sling reads, and nothing reads the variable, so the rule rests
on the refinery's `mr` default, which this design changes.

Under the design the rule holds in this form:

- Code a reaction writes itself carries `merge_strategy=mr`, as the pool's
  prompt already tells it to. It opens a PR wherever it lands, so it never
  takes the `direct` path.
- Work a reaction routes to the polecat pool is its subject's own work, and it
  lands by the subject's target like any bead's. Aimed at main, or at any
  branch but a convoy's or another PR's head, it goes through its own PR by the
  PR rule. Aimed at a convoy's branch, it lands there as a member and reaches
  main in the convoy's PR, which the city's checks review before it opens.
  Aimed at another PR's head, it folds into that PR, as it does today. The
  proactive scan skips routed, armed and in-flight beads, and the recipes sling
  or arm a member in the step that adds it (section 1), so a subject the scan
  reaches is not a member.

So a reaction's code reaches main only through a PR. Unit A corrects the
doctrine to say how, and removes the variable and the fixture check that
asserts it, which is the change tk-aqytltn asks for.

## 3. When a convoy's branch is cut, and how it is brought current

A convoy's branch is cut once, when `convoy-seed.sh` seeds the convoy, from the
default branch as it stands then. So a convoy is seeded when its first member
can start.

A member that builds on work reaching main after the seed needs the convoy's
branch brought current first. That is a hand-off to the mechanik, not a member.
The hand-off is a task assigned to the mechanik. It waits on the outside work by
a `blocks` edge, and deferred dispatch's ready notice tells the mechanik when
that work has landed. The member that needs the branch current waits on the
hand-off by a `blocks` edge, and is armed to dispatch when the hand-off closes.

Once notified, the mechanik brings the branch current from a disposable
worktree, as `convoy-seed.sh` cuts it. When the branch holds nothing that main
lacks, that is a fast-forward to main. When it does, such as a member's landing
or a seeded artifact, it is a merge of main into the branch. The mechanik
pushes the result and closes the hand-off, which releases the member.

- **No review reads main's commits as new work.** No polecat builds the
  hand-off, so no self-review and no refinery gate treats main's commits as its
  change. They were reviewed on their way to main, and the convoy's PR into
  main shows only the convoy's own work.
- **The waiting member is held until the push**, not through a polecat's build
  of a mechanical merge.
- **A merge that conflicts is not mechanical.** The mechanik pushes nothing and
  puts it to the operator with a visit, as a polecat does when bringing a
  branch current needs a decision.
- **It passes the four tests.** The hand-off is a plain task, each wait is a
  `blocks` edge, the notice is the one deferred dispatch already sends a named
  agent, and the act is the mechanik's recipe, which is prose. Nothing new is
  built, and unit C's dispatch doctrine states it.

## 4. Where each review runs

| Where | What runs | What it reads |
|---|---|---|
| Inside each member's molecule | the self-review loop of `mol-polecat-work`: a polecat in a fresh session reviews and fixes the diff, and the loop ends only when the rig's checks pass at its head | the member's own diff |
| At the refinery, before the member lands | the rig's gate on the prepared head | the member merged onto the convoy's branch |
| On the convoy's PR, before it opens | correctness and triage, and arch and pm when triage adds them | the whole branch against main |
| On the convoy's PR, while it is a draft | demo, when triage adds it | the PR |
| On the convoy's PR | the operator's approval, `merge.sh`'s universal rule | everything |

A member's defect is its own self-review's to catch. The convoy's PR is where
the big-picture items are caught, which is what the operator reviews it for. A
member closes when it lands, like any bead whose work is done, and no state or
transition is built for it.

## 5. How the convoy's PR opens and lands, and how rework returns

1. Each member lands on the convoy's branch and closes.
2. Once every member is closed and a landing is recorded, the merge cadence
   graduates the convoy. Its bead becomes the work bead that carries
   `integration/<id>` to main, as Gas Town's auto-land takes an owned convoy's
   bead.
3. The refinery prepares the branch and runs the rig's gate, and the city's
   pre-open checks review the whole branch. A request-changes verdict files a
   rework child of the convoy's bead, which resumes `integration/<id>`.
4. The PR opens once those checks are green, as a draft first when triage added
   demo.
5. The operator reviews it. Their feedback returns as a rework child that
   resumes the PR's branch, and scope found while the PR is open rides a
   supplement on the same branch.
6. `merge.sh` lands the PR once the operator's approval stands, and the convoy's
   bead closes.

Every step is today's machinery. It is the build pack's shape: the members are
built in parallel, the whole is reviewed once, and one PR is published. The
build pack runs its members in their own worktrees and publishes the result in
one step, and gc-toolkit lands each member on the convoy's branch through the
refinery.

## 6. Stages

A stage is a member slung `--merge mr`. It opens its own PR into the convoy's
branch, the operator approves it, and it lands before the members that wait on
it. The design child of a design-gated `mol-design-convoy` is one, because its
PR is the design gate, so the formula slings it `--merge mr`.

A stage built from several beads would be a convoy that lands its own PR into
another convoy's branch. Graduation carries every convoy to the default branch,
so that shape is not built, and this design does not build it.

## 7. Nouns that have diverged from Gas City's

Under the operator's ruling, this design builds on Gas City's version of each
noun and adds nothing to gc-toolkit's, beyond the PR rule the operator asked
for on the merge strategy. Whether a diverged noun is retired, and when, is a
conversation for the epic that moves gc-toolkit onto Gas City as shipped
(tk-1tfzr71).

| Noun | Gas City's | gc-toolkit's | This design |
|---|---|---|---|
| Convoy membership | `tracks` edges | a parent-child edge, in the mechanik's recipe and `mol-design-convoy` | moves to `tracks` |
| Merge strategy | `direct`, `mr` and `local`, with unset left to the consumer | the lifecycle registry lists `mr`, `pr` and `direct`, and the refinery's default is `mr` | reads Gas City's key and values, moves the default to Gas Town's, keeps the operator's PR rule, and drops the fold-in flip |
| A finished owned convoy's landing | Gas Town's auto-land takes the convoy's bead as a work bead, and `gc convoy land` ends the convoy | graduation, `convoy-graduate.sh`, with conditions of its own, and the bead closes through the PR's merge | unchanged |
| A PR's owning bead | Gas City core does not open PRs; the build pack publishes one PR for the convoy or issue its workflow ran on | the anchor (`docs/component-model.md`) | unchanged: the anchor is that issue or convoy |
| A convoy's work as one PR | the build pack's drain, review and publish | members land on an integration branch, then graduation | unchanged |

## 8. What to correct

Each row says what a living file asserts today and what it says under the model.
The unit that changes it is in the last column (section 9).

| File | Says today | Says under the model | Unit |
|---|---|---|---|
| `formulas/mol-refinery-patrol.toml`, `default_merge_strategy` and `merge-strategy-resolve` | the default is `mr`; an `mr` bead aimed at another PR's head with no PR of its own flips to `direct`, recorded in `MS_FOLD_IN`; and the block's comment calls it the one reading that the step keeping a branch and the step opening a PR share | the default is `direct`; the PR rule resolves a bead that would land `direct` to `mr` unless its target is `integration/*` or `polecat/*`; a `local` bead passes through unchanged; the flip and its variables go; and the comment names merge-push as the block's one reader | A |
| `formulas/mol-refinery-patrol.toml`, `rejection-branch-keep` | decides from its own copy of the resolve block whether a bead's branch survives a branch-caused rejection: deletes it for a `direct` bead that records no PR, since nothing PR-shaped means no PR will want the branch "only in direct mode", and keeps it otherwise | goes whole, with its copy of the resolve block: a rejected branch is kept in every mode, because the repooled rebuild resumes it | A |
| `lifecycle/lifecycle.toml`, `merge_strategy` | an absent key resolves to the formula default, `mr`, and a `polecat/` target with no PR of its own resolves from `mr` down to `direct` | an absent key resolves to `direct`, the PR rule resolves a bead that would land `direct` to `mr` unless its target is a convoy's branch or another PR's head, and the fold-in sentence goes | A |
| `assets/scripts/pr-stack.sh` header comment, and `docs/refinery-merge-cadence.md` | a `merged_target` row "landed its own PR into it" | it landed on the branch, with or without a PR of its own | A |
| `agents/proactive/PROVENANCE.md`, item 3 | the invariant "is enforced by the city default (`default_merge_strategy = "mr"`) and this agent's `GC_DEFAULT_MERGE_STRATEGY = "mr"`", and work a reaction routes "goes to the polecat pool, whose default is `mr`" | code a reaction writes carries `merge_strategy=mr`, so it never lands `direct`, and work a reaction routes lands by its target like any bead's; either way it reaches main only through a PR | A |
| `agents/proactive/prompt.template.md`, "mr-only for Code" | "The pool already defaults `GC_DEFAULT_MERGE_STRATEGY=mr`; do not override it." | the sentence goes, and the hand-off with `merge_strategy=mr` stays | A |
| `agents/proactive/agent.toml`, `[env]` | `GC_DEFAULT_MERGE_STRATEGY = "mr"`, under a comment that calls it the invariant's belt-and-suspenders | the line and its comment go, since nothing reads the variable | A |
| `tools/gc-proactive.sh`, header comment | code a reaction routes "still takes the correctness-gated mr path", on the polecat pool "(its GC_DEFAULT_MERGE_STRATEGY=mr)" | code a reaction routes lands by its target and reaches main only through a PR | A |
| `tools/proactive-first-reaction-fixture.sh` | its header says the pool "defaults to mr", its sling section that the invariant "now lives downstream, on the polecat pool", and a check asserts `agent.toml`'s `GC_DEFAULT_MERGE_STRATEGY = "mr"` | the comments say what `PROVENANCE.md` says, and the check goes | A |
| `docs/design-convoy.md` | "The default PR unit is an owned convoy"; the design child is linked "parent-child to the convoy"; "each child's PR onto the integration branch"; in all-in-one, "Each child's PR still needs the operator's approval" | Each child is added to the convoy and carries its target. Design-gated: the design child is a stage, a PR into the convoy's branch, the implementation lands with no PR, and the convoy's PR is the second. All-in-one: one PR, the convoy's. | B |
| `formulas/mol-design-convoy.toml`, arm-design and arm-implementation | links each child with a parent-child edge, reads that edge back, relies on it for the child's target, and slings with no merge flag | adds each child with `gc convoy add`, reads the convoy's `tracks` edge back, writes the convoy's target on the child, and slings the design child `--merge mr` when design-gated | B |
| `assets/scripts/pr-summary-region.sh`, the integration banner | "Approving it mints this phase into the convoy integration branch" | "stage" for "phase". This file and `docs/state-machine.md` already use "phase" for a check's phase, so one word keeps one meaning. | B |
| `assets/scripts/pr-status-label.sh`, the `base:` label | "checkpoint into integration; approval mints a phase, not a merge to main" | the same, for a stage. `ensure_group` creates a missing label and never edits one, so the label already on GitHub changes by one `gh label edit`. | B |
| `docs/state-machine.md`, the base label section | "approving the PR mints a phase into the integration branch", and the banner example | the same words as the banner and label | B |
| `docs/epics.md`, "A checkpoint is always qualified" | a PR Checkpoint "lands a phase of work on a convoy's integration branch" | it lands a stage | B |
| `agents/mechanik/prompt.template.md`, the dispatch doctrine | "an owned convoy is the PR unit", a lone bead is the one-child convoy, the recipe links each child with a parent-child edge and reads it back, and a child slung without the stamp "is held at workspace-setup" | A PR comes from one bead or one convoy, and a lone bead needs no convoy. Work that reaches the operator as one PR is an owned convoy. The recipe adds each member with `gc convoy add`, reads the convoy's `tracks` edge back, writes the convoy's target on the member, and slings it with no merge flag. A stage is slung `--merge mr`. A member added without its target is held at workspace-setup before any branch is cut, as a child slung without the stamp is today. A member that builds on work reaching main after the seed waits on a hand-off to the mechanik, which brings the convoy's branch current with a fast-forward, or a merge once the branch holds work main lacks, and asks the operator when the merge conflicts. Ranking or parking a convoy's work is done on its members or their epic. | C |
| `template-fragments/polecat-doctrine.template.md`, integration branches | a child of an owned convoy carries the target "which the owned-convoy recipe stamps when it links the child", and without it workspace-setup "cancels that run ... and the work waits on a visit" | A member of an owned convoy carries the convoy's branch as its target, written when it is added. The convoy tracks the member and is not its parent, so sling finds the branch only through that target. Without it, workspace-setup cancels the run before it cuts a branch, and the work waits on a visit that asks for the target. The member's work lands on the branch with no PR unless it is a stage. | C |
| `skills/prs/SKILL.md`, supplements | a supplement's target "for a PR under an owned convoy is `integration/<convoy-id>`" | that holds for a stage's PR, and a convoy's own PR targets main | C |
| `formulas/mol-polecat-work.toml`, workspace-setup's convoy target guard | reads a bead's parent-child convoy parents only, and declines a convoy child poured from a branch that is not where its work lands | reads the convoys that track the bead as well, so a member poured without its target is declined before any branch is cut, with a visit that asks for the target | C |
| `docs/warrants.md` | no entry covers a convoy's target on a tracked member | an entry for the recipes' target write and the guard's read of `tracks`, standing in for sling resolving a target through `tracks` and retired when it does | C |

Each unit that edits a prompt or a formula regenerates its pages under
`generated/seed-audit/`. Specs are records and are not edited.

What stays as it is: `docs/component-model.md`, whose Convoy row already reads
"tracked set with one landing target" and whose anchor is the bead that owns a
PR; the approval rule in `merge.sh`; I4 and its check,
`doctor/check-one-anchor-per-pr`, since a member never owns a PR; the one-bead
input convoy of `mol-polecat-work`; the parent readers that section 1 lists;
the rule that `existing_pr` forces `mr`; `convoy-seed.sh`; and graduation.

## 9. The implementation cut

The fix cannot use itself. Until it reaches main, the refinery's default is
still `mr`, so the implementation runs the by-hand path. One owned convoy, on
`integration/<convoy-id>`, holds one member for each unit below. Each member is
added with `gc convoy add`, carries the convoy's target, and is slung
`--merge direct`. The members are built in parallel, and the convoy reaches
main as the one PR the operator reviews.

| Unit | What it changes | Its tests |
|---|---|---|
| A. The default | `default_merge_strategy` and `merge-strategy-resolve` in `formulas/mol-refinery-patrol.toml`, whose `rejection-branch-keep` arm goes; the `merge_strategy` entry in `lifecycle/lifecycle.toml`; the `pr-stack.sh` comment; the line in `docs/refinery-merge-cadence.md`; the proactive pool's `PROVENANCE.md`, prompt, `agent.toml` and the header of `tools/gc-proactive.sh`; and the seed-audit pages of the formula and the proactive prompt | `assets/scripts/mr-aware-rejection-failclosed.test.sh`, changed as [unit A's tests](#unit-as-tests) list; `tools/proactive-first-reaction-fixture.sh`; `assets/scripts/render-seed-audit.sh --check` |
| B. Stages | arm-design and arm-implementation in `formulas/mol-design-convoy.toml`, `docs/design-convoy.md`, the banner in `assets/scripts/pr-summary-region.sh`, the label text in `assets/scripts/pr-status-label.sh` and the live label, the base label section of `docs/state-machine.md`, the PR Checkpoint sentence of `docs/epics.md`, and the formula's seed-audit page | `assets/scripts/mol-design-convoy-arm.test.sh`, `assets/scripts/pr-open.test.sh` |
| C. Membership and doctrine | the dispatch doctrine in `agents/mechanik/prompt.template.md`, the integration-branch paragraph of `template-fragments/polecat-doctrine.template.md`, the supplement section of `skills/prs/SKILL.md`, workspace-setup's convoy target guard in `formulas/mol-polecat-work.toml`, the warrant's entry in `docs/warrants.md`, and the seed-audit pages of the mechanik, polecat and polecat-codex prompts and of `mol-polecat-work` | `assets/scripts/workspace-setup-convoy-target-guard.test.sh`, `assets/scripts/skill-needs.test.sh`, `assets/scripts/render-seed-audit.sh --check` |

Each unit is one concern a reviewer can hold. The units touch disjoint files, so
the refinery's merge of the convoy's branch into a member's branch before it
lands meets no conflict from the others, whichever lands first. None builds on
another, so none waits for the others.

The default and the words reach main together, in the convoy's one PR. So no
design-convoy is poured between a default that would land its design child with
no PR and the `--merge mr` that keeps the design gate.

Until unit A reaches main, the refinery still deletes a direct member's branch
when its gate fails because of the branch, and the rebuild stops at the
missing-branch visit. The release is to restore the branch from the member's
worktree, or to clear `metadata.branch` so the rebuild starts again from the
convoy's branch.

The units are filed from this table as it reads on main, once this design
merges, so a change made in this design's review leaves no filed bead
describing an older cut.

### Unit A's tests

`assets/scripts/mr-aware-rejection-failclosed.test.sh` pins the merge strategy
and the rejection arm. Its harness fills in the formula's default as
`${2:-mr}`, so that default moves to `direct` with the formula's. Each case
below pins the path it names under the new default.

- **A rejected `direct` bead keeps its branch.** In the branch-decision
  section, (6), (9), (13d) and (14) move onto `target: integration/cv-1`, so
  each is a bead that resolves `direct`: one that names no strategy, one that
  names `direct`, one behind a repool that stopped short, and one under the
  formula's default. Each keeps its branch. With no target, each would resolve
  to `mr` by the PR rule and keep its branch for that reason, which pins
  nothing about a `direct` bead. (19) keeps the branch of a bead aimed at
  `polecat/tk-anchor` that names no strategy, now `direct` by the default rather
  than by the flip. (20) and (21) keep theirs, as they do today. A check that
  the handle-failures step deletes no branch pins the decision's removal.
- **What goes with the arm's decision.** The cases that pin its reasons for
  keeping or deleting a branch go with it: (7), (8), (10) to (13c), (13e), (15)
  to (17b), the refused delete (18) to (18c), and (19b)'s check that a branch
  was kept "for the fold reason", which the resolve case below replaces.
- **The resolve block.** Run on its own, the block resolves a bead aimed at
  `integration/cv-1` to `direct` when it names no strategy (20b), and to `mr`
  when it names `mr`, a stage. It resolves a bead aimed at `polecat/tk-anchor`
  to `direct` when it names no strategy (19), and to `mr` when it names `mr` and
  records no PR of its own, since the flip is gone, which (19b) now pins. `pr`
  resolves to `mr` (8b). A bead aimed at `main`, at no target, or at `release/x`
  resolves to `mr` whether it names `direct` or no strategy. A `local` bead
  stays `local` aimed at `main`, at no target, and at `integration/cv-1`. A bead
  aimed at `polecat/tk-anchor` with its own `existing_pr` still resolves to `mr`
  (21b), through merge-push's `existing_pr` rule, which that case runs after the
  block.
- **One reading.** The resolve block has one call site left, merge-push's, so
  the check that counts call sites expects one, and the check that two copies
  are byte-identical goes. The check that no step reads `merge_strategy` outside
  the block stays.
