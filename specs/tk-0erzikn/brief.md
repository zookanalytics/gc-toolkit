---
name: Brief — a PR is one reviewable unit, and a convoy's work aggregates into it
description: An input to this bead's design (design.md beside it). The operator's words from mechanik chat on 2026-10-18, the model they state, what already works by hand, what holds the default back, the constraints and the questions the design settles, as mechanik wrote them. Copied verbatim below this header.
---

# Brief: a PR is one reviewable unit, and a convoy's work aggregates into it

Design brief from the operator's words in mechanik chat on 2026-10-18. The
history and evidence behind it are in `findings.md` beside this file.

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

## The model

1. **Every PR is the operator's.** The city opens a PR, into main or into an
   integration branch, only to ask for the operator's review. It opens no PR
   that is not for the operator.
2. **A PR is one bead.** That bead can have child beads, each a unit of work done
   by its own polecat. Children open no PRs. Their work lands on the PR bead's
   branch, and the PR opens for the overall review once they are done.
3. **Each child is reviewed inside its own work molecule before its work lands.**
   mol-polecat-work already reviews the diff and runs the declared checks in a
   bounded check loop. Gas City formulas also run review lanes by other agents
   inside a molecule (docs/guides/understanding-formulas.md in gascity, the
   `code-review` expansion). The PR gets the overall review.
4. **The city works in as many internal phases as it needs** before it opens a
   PR.
5. **Multi-stage work is more than one PR.** Every reviewable unit is a PR. An
   early stage can be a PR into an integration branch, and the last one goes to
   main.
6. **A convoy is Gas City's concept, with its defined purpose:** grouping work
   that moves together onto a target branch, its children inheriting the target
   and the merge strategy. A convoy is not a PR, and nothing in gc-toolkit may
   keep it from working that way.

## What already works, by hand

- **A child can land on its convoy's branch with no PR.** Sling it with
  `--merge direct` and stamp `target=integration/<convoy-id>`. The refinery
  reads the bead's own `merge_strategy` (formulas/mol-refinery-patrol.toml,
  merge-strategy-resolve). It does not force `integration/*` targets to `mr`.
- **The landing is recorded.** direct-merge-push.sh fast-forwards the target,
  records `merge_result=merged` with `merged_target`, and closes the child.
  GitHub requires only signed commits off the default branch (the "Signed
  Commits" ruleset). The "Default Branch" ruleset covers main alone.
- **The convoy bead becomes the PR's bead.** When every member is closed and at
  least one merge is recorded on the branch, convoy-graduate.sh hands it to the
  refinery as a PR-mode work bead targeting main.

So the model is reachable today by hand. The fix makes it the default.

## What holds it back today

- **Every bead opens its own PR, convoy children included.** The refinery reads
  a bead's own `merge_strategy` and falls back to its formula default, which is
  `mr` (formulas/mol-refinery-patrol.toml, `vars.default_merge_strategy`, since
  #197 on 2026-07-21). A town-wide `default_merge_strategy = "mr"` in city.toml
  came first (e997f65, 2026-06-05), set to stop direct pushes to gascity main.
  It left city.toml in eb4bd94 (2026-07-23).
- **The convoy's own merge setting is never read.** gascity's sling stamps
  `merge_strategy` on a routed bead from the `--merge` flag, else from a rig
  default (internal/sling/sling.go, SlingMergeStrategy). No rig default is set
  today, so a bare sling stamps nothing. A convoy's `convoy.merge` field
  (internal/convoy/convoy_fields.go) plays no part.
- **Each work bead owns its own PR.** The anchor model (#465): docs/component-model.md
  I4, "Every PR has exactly one owning anchor", with the anchor being the work bead.
- **Convoy children open their own PR on purpose.** #994 (tk-sw5bu) keeps
  `integration/*` children on `mr`, and the refinery's merge-strategy block does
  the same (formulas/mol-refinery-patrol.toml:625-655).
- **A polecat takes one bead at a time.** mol-polecat-work refuses an input convoy
  with more than one member (formulas/mol-polecat-work.toml:424-432).
- **The specialist review checks need a PR.** gate-ensure.sh dispatches the review
  beads for a PR anchor, and formulas/mol-review.toml refuses to run without a PR
  number and URL. The checks are correctness, arch, pm, demo and triage.
- **Every child PR is labelled a phase.** The `base: integration` "phase" label and
  banner go on every PR into an integration branch (#851). docs/design-convoy.md
  says each child PR needs approval.

## Constraints

- **I4 stays, re-read.** Every PR has exactly one owning bead: the PR bead. Its
  children own no PR.
- **The approval rule stays.** Every PR needs the operator's approval (merge.sh).
- **Bash is a bridge.** The scripts are moving to Go (gctk). Any bash change is the
  smallest bridge, and the design states the model so the gctk port carries it.
- **This fix cannot use itself.** Until it lands, the machinery still opens one PR
  per bead, so the fix's own implementation goes out in as few PRs as possible.

## What the design settles

- **Making it the default.** A convoy's children should land on its branch with
  no PR unless told otherwise, rather than each one needing `--merge direct` at
  sling time. Options are honoring `convoy.merge`, or resolving a convoy child's
  `integration/*` target to direct.
- **Children taking the convoy's branch without a hand stamp.** Sling reads a
  child's own `target` first, then the first convoy target on the one parent
  chain bd reports. A child that also belongs to an epic can report the epic
  and resolve to main instead. So today each child's target is stamped by hand,
  as on the seven children of convoy tk-23q3ytl.
- **When the convoy's branch is cut.** convoy-seed.sh cuts the branch at seed
  time. A convoy whose children build on work that lands later needs its branch
  brought up to that point first. Convoy tk-23q3ytl needed a hand-off bead
  (tk-fsws0k6) to fast-forward it once the redesign reaches main.
- **Where each review runs.** Which reviews run inside the child's molecule, and
  which once on the PR? This covers the specialist checks that need a PR today.
- **When the PR opens.** It opens when the children are done. Rework from the
  operator's review comes back as children of the same PR bead.
- **What to correct:**
  - docs/component-model.md
  - docs/design-convoy.md
  - the `base: integration` label text in docs/state-machine.md
  - the "phase" wording in pr-summary-region.sh and pr-status-label.sh
  - the mechanik dispatch doctrine ("an owned convoy is the PR unit")
- **The implementation cut,** within the constraint above.

## First case

The review epic's seven correctness-method changes (tk-qjdt90g.9, .4, .5, .8,
.6, .7 and tk-wigtu9) become one PR bead with seven children. They keep their
build order, and each is built and reviewed by its own polecat. The operator
reviews one PR.
