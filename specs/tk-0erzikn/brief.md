---
name: Brief — a PR is one reviewable unit, and a convoy's work aggregates into it
description: An input to this bead's design (design.md beside it). The operator's words from mechanik chat on 2026-10-18, verbatim, and the operator's ruling of 2026-10-19 on the first design, which rebuilt it on Gas City's own convoy model. It states the model in Gas City's terms, what already works, what holds the default back, the rules the design is measured by, and the questions the design settles.
---

# Brief: a PR is one reviewable unit, and a convoy's work aggregates into it

Design brief from the operator's words in mechanik chat on 2026-10-18, and from
the operator's ruling of 2026-10-19 on the first design, which the operator
reviewed on PR #1298 and ruled on in visit tk-ilmnzqh. The history and evidence
behind it are in `findings.md` beside this file.

## The operator's words (2026-10-18, verbatim)

- "The whole reason we have convoys is that I can do all 7 of them as one chunk
  of work, Or at least that's one of the reasons I thought they existed."
- "You should not have to always do one discrete unit of work at a time."
- "It's not about my approval being required on every PR. It's that a convoy can
  include multiple pieces of work, and that should all land as a single PR."
- "Broadly speaking, all PRs to main need a review. The city has the ability to
  do PRs that don't go to main and get my review, and the city is more than
  capable of doing as many phases of work as necessary before showing me a PR
  (whether that is a PR to main or a PR to an integration branch) by creating a
  pull request. Let's make sure that makes sense so we don't codify anything
  wrong again."
- "We definitely want the ability to break things into smaller chunks of work
  that should be aggregated for a single PR. I feel like this is a pretty solid
  example of presenting all seven changes as one pull request, even though it
  might be seven individual changes that are done by individual pull cats (plus
  each review itself), and then it gets the overall review, etc."
- "As for multi-stage PRs, the request is simply that every reviewable unit is a
  pull request. I think I even explicitly, at one point, said, 'Convoy is an
  implementation detail. It's the means by which things move forward and is not
  tied to a PR.' Although I think there's an overall bead for a PR, in which case
  every PR has a bead, but that bead can have a subchildren in the sense that
  it's not one bead per PR. Instead, a PR is represented by a single bead."
- "Definitely not B. I don't want any PRs that are not mine. I'm still confused
  because molcat Do Work has reviews in it. It checks its work, and it can even,
  I think, have an external check from another bead, which represents another
  unit of work. In the structure of 1 through 5, yes, those are largely true, but
  Convoy is an implementation detail only insofar as Convoy is a well-defined
  concept in Gas City with a specific purpose. Nothing we do should have held
  that back."

## The operator's ruling (2026-10-19, verbatim)

The first design was rebuilt on Gas City's own convoy model. These words bind
the design.

1. The four tests are the acceptance bar:

   > "1. Prose and config are free. Prompts, skills, checklists, formulas,
   > orders, work queries — build freely.
   > 2. A pack noun needs a dated warrant and a retirement trigger. Name the
   > missing platform primitive; when upstream ships it, migrating onto it is
   > scheduled work. A converter between a pack noun and a platform noun is the
   > alarm that the trigger was missed.
   > 3. Glue composes native calls; it may not add semantics. A script that
   > checks-then-creates is glue; a script with its own claim protocol, state
   > keys or recovery forensics is a layer.
   > 4. Surfaces render platform objects; they never mint their own."

   In the sitting the operator accepted how the tests apply: they cut by
   content, not by file type, so a semantics layer inside a formula step's
   inline bash is still a layer, not config.

2. On the refinery's `mr` default:

   > "This should be about 1-2 lines, to change the default. Not a bunch of
   > plumbing. The only thing that tries to change is that even if main is
   > unprotected, changes to main must go through a PR. It's a safety for if we
   > haven't enabled the github rule on a given repo yet."

3. On nouns that have diverged from Gas City's:

   > "if a noun has diverged, our goal is to still build on the Gas City version
   > of the noun and not add more to the diverging noun. And then we can have a
   > conversation if that noun needs to be prioritized in the epic doing that
   > retirement work."

4. > "The brief needs to be updated to reflect these items before it has a
   > chance of approval"

The operator's review of the first design (PR #1298, review 5567080244) adds
these, which the ruling keeps:

- > "We USE Gas City, not fight it or simply ignore it."
- > "If you're needing to change Gas City, most likely you're using Gas City
  > wrong."
- > "Why would we build a system that has a discarded pour as part of its
  > operation?"
- > "The relentless focus on parent / child here is concerning to me. I didn'
  > tthink convoys required parent/child relationships."
- > "A PR has an issue or a convoy that it came from."
- > "it might be reasonably for those children to land as PRs to an integration
  > bead. I think the block might only need to apply to a main PR, since that's a
  > complete unit of work."
- > "polecats self-review, so a defect in an early member is caught during the
  > self-review. Big picture items aren't caught until later, but that's what the
  > PR is looking for, not each individual step"
- > "Never reference other repos in gc-toolkit commits" and "do not include
  > random dumps of bead data into a public repo."

## The model

1. **Every PR is the operator's.** The city opens a PR, into main or into a
   convoy's branch, only to ask for the operator's review. It opens no PR that
   is not for the operator.
2. **A PR comes from one issue or one convoy.** A lone bead's PR comes from that
   bead. Work that reaches the operator as one PR is a convoy. Its members are
   each built by their own polecat and land on the convoy's branch with no PRs
   of their own, and the convoy's PR opens for the overall review once they are
   done. A PR into main is a complete unit of work. A member still opens its
   own PR into the convoy's branch when the operator should review it on its
   own.
3. **Each member is reviewed inside its own work molecule before its work
   lands.** mol-polecat-work's self-review loop checks the member's work. The
   PR gets the overall review, which is where big-picture items are caught.
4. **The city works in as many internal phases as it needs** before it opens a
   PR.
5. **Multi-stage work is more than one PR.** Every reviewable unit is a PR. An
   early stage can be a PR into a convoy's branch, and the last one goes to
   main.
6. **A convoy is Gas City's concept, used as Gas City defines it.** A convoy is
   a container bead that groups related work so a batch is tracked as a unit.
   It tracks its members with `tracks` edges and is not their parent. An owned
   convoy has a manual lifecycle that `gc convoy land` ends. A merge strategy
   means what Gas City defines: `direct` merges the work branch into its target,
   `mr` delivers it through a merge or pull request, and `local` leaves it on its
   branch with no merge and no request. Nothing in gc-toolkit may keep a convoy
   from working that way.

## What already works, by hand

- **A member can land on its convoy's branch with no PR.** Sling it with
  `--merge direct` and stamp `target=integration/<convoy-id>`. The refinery
  reads the bead's own `merge_strategy` (formulas/mol-refinery-patrol.toml,
  merge-strategy-resolve). It does not force `integration/*` targets to `mr`.
- **The landing is recorded.** direct-merge-push.sh fast-forwards the target,
  records `merge_result=merged` with `merged_target`, and closes the member.
  GitHub requires only signed commits off the default branch (the "Signed
  Commits" ruleset). The "Default Branch" ruleset covers main alone.
- **The convoy's bead carries its branch to main.** When every member is closed
  and at least one landing is recorded on the branch, convoy-graduate.sh hands
  the convoy's bead to the refinery as an `mr` work bead targeting main. Gas
  Town's refinery takes an owned convoy whose members are all closed the same
  way when its `integration_branch_auto_land` is on: it assigns the convoy's
  bead to itself, with the convoy's branch as the bead's branch and main as its
  target.

So the model is reachable today by hand. The fix makes it the default.

## What holds it back today

- **Every bead opens its own PR, convoy members included.** The refinery reads
  a bead's own `merge_strategy` and falls back to its formula default, which is
  `mr` (formulas/mol-refinery-patrol.toml, `vars.default_merge_strategy`, since
  #197 on 2026-07-21). Gas Town's refinery falls back to `direct`. The `mr`
  default came from a city-wide setting made to stop direct pushes to a main
  branch, and nothing shows convoy branches were considered.
- **Members are linked as the convoy's children.** The mechanik's recipe and
  mol-design-convoy link each member to the convoy with a parent-child edge,
  because Gas City's sling finds a convoy's target only through a bead's parent.
  Gas City's own membership is a `tracks` edge, and its tutorial says members
  "are not children of the convoy". A bead has one parent, so a member that also
  sits under an epic can lose its convoy's branch.
- **Each work bead owns its own PR.** The anchor model (#465):
  docs/component-model.md I4, "Every PR has exactly one owning anchor", with the
  anchor being the work bead.
- **Convoy members open their own PR on purpose.** #994 (tk-sw5bu) left
  `integration/*` members on `mr` on purpose. The refinery's merge-strategy
  block has no rule of its own for them: it flips only a bead aimed at a
  `polecat/*` head to `direct`, so a member that names no strategy takes the
  `mr` default.
- **A polecat takes one bead at a time.** mol-polecat-work refuses an input
  convoy with more than one member.
- **The city's checks run on a PR's owning bead.** gate-ensure.sh dispatches the
  review beads for an anchor. Correctness, triage, arch and pm run before its PR
  opens, and demo runs on the PR while it is a draft.
- **Every member's PR is labelled a phase.** The `base: integration` "phase"
  label and banner go on every PR into an integration branch (#851).
  docs/design-convoy.md says each member's PR needs approval.

## Constraints

- **I4 stays.** Every PR has exactly one owning bead: the issue or the convoy it
  came from. A convoy's members own no PR.
- **The approval rule stays.** Every PR needs the operator's approval (merge.sh).
- **The four tests decide what the design may build.** Any script change is
  glue that composes native calls.
- **This fix cannot use itself.** Until it lands, the machinery still opens one PR
  per bead, so the fix's own implementation goes out in as few PRs as possible.
- **The spec names no other repository, no other rig's beads and no live bead
  data.**

## What the design settles

- **Making it the default.** A convoy's members land on its branch with no PR
  unless told otherwise, rather than each one needing `--merge direct` at sling
  time. The refinery's default changes in about two lines and keeps one
  invariant: a change to main goes through a PR, even where main is unprotected.
- **Membership, and a member's branch.** Members are tracked the way Gas City
  tracks them. Sling passes a convoy's target only to a bead whose parent is the
  convoy, so a tracked member needs its branch some other way. That gap gets a
  dated warrant and a retirement trigger, and its bridge adds no semantics.
- **When the convoy's branch is cut.** convoy-seed.sh cuts the branch at seed
  time. A convoy whose members build on work that lands later needs its branch
  brought up to that point first.
- **Where each review runs.** Which reviews run inside the member's molecule,
  and which once on the PR.
- **When the PR opens, and how the convoy lands.** It opens when the members are
  done, and an owned convoy lands the way Gas City lands one. Rework from the
  operator's review comes back to the same PR.
- **Diverged nouns.** Where gc-toolkit's nouns differ from Gas City's, the design
  builds on Gas City's and adds nothing to the diverged one.
- **What to correct:**
  - docs/component-model.md
  - docs/design-convoy.md and mol-design-convoy
  - the `base: integration` label text in docs/state-machine.md
  - the "phase" wording in pr-summary-region.sh and pr-status-label.sh
  - the mechanik dispatch doctrine ("an owned convoy is the PR unit")
  - the polecat doctrine's paragraph on integration branches
- **The implementation cut,** within the constraints above.

## First case

The review epic's seven correctness-method changes (tk-qjdt90g.9, .4, .5, .8,
.6, .7 and tk-wigtu9) become one convoy with seven members. They keep their
build order, and each is built and reviewed by its own polecat. The operator
reviews one PR.
