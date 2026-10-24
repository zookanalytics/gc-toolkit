---
name: Brief — a PR is one reviewable unit, and an integration effort's work aggregates into it
description: An input to this bead's design (design.md beside it). The operator's words from mechanik chat on 2026-10-18, verbatim; the operator's ruling of 2026-10-19 on the first design, which rebuilt it on Gas City's own convoy model; the operator's ruling of 2026-10-23, which recast the design as a plan to delete gc-toolkit's own convoy code and defend every survivor with a warrant; and the operator's ruling of 2026-10-24, which stops using a convoy to carry a branch, gives each bead its own branch and has one landing bead per integration branch carry it to main. It states the model in Gas City's terms, what already works, what holds the default back, the rules the design is measured by, and the questions the design settles.
---

# Brief: a PR is one reviewable unit, and an integration effort's work aggregates into it

Design brief from the operator's words in mechanik chat on 2026-10-18, and from
three rulings on PR #1298. The operator ruled on the first design on
2026-10-19, in visit tk-ilmnzqh, on the rebuilt design on 2026-10-23, in visit
tk-mnryf1w, and on the deletion plan's warrants on 2026-10-24, in visit
tk-c2txixo. The history and evidence behind it are in `findings.md` beside this
file.

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

## The operator's ruling (2026-10-23)

The rebuilt design was recast as a deletion plan. These are the operator's
words in the sitting, verbatim:

- > "If an external party, familiar only with Gas City, and standard packs like
  > Gas Town, were to look at the graph and operation behind a convoy run by our
  > pack, would they look identical to a normal convoy? Do we do anything special
  > or different with convoys? In short, this statement needs to not just be
  > "**A convoy tracks its members the way Gas City does.**" but more gc-toolkit
  > uses Gas City convoys the way they are intended to be used."
- > ""This is the design's one platform gap, recorded in section 1 with its date
  > and the trigger that retires the write." let's talk about why we need a
  > platform gap."
- > "When we are done implementing, do we expect this code to be able to delete
  > nearly all convoy logic wtihin gc-toolkit, since the pack isn't the source of
  > that context."
- > "I believe the only thing I ever wanted to change in convoys was the default
  > when landing on main of doing direct. PRs are the means for me to see what
  > commits are being done. In theory, our ruleset enforces that and Gas City wil
  > lpick that up, so we could have what I think is 0 convoy code if we just let
  > that happen. Yet somehow, gc-toolkit has more than a handful of lines of
  > convoy code and this spec and follow-up work is to try and remove all that
  > code."
- > "And what I think is some false understanding around waht mr is/was supposed
  > to do. All it protects is main, not a named or long-lived branch. Arguably
  > this is a reason we might want to just say use GitHub rulesets, because then
  > I can define if other branches should have protection, since we don't have a
  > means to list whatn requires a PR"
- > "I feel like convoy-seed.sh shouldn't exist or needs a really strong warrant
  > justiciation."
- > "And 99% sure Gas City with a ruleset triggers a PR just fine, no errors. I
  > used that originally and only had gc-toolkit change the default when there
  > was a moment the ruleset was turned off and the city went ahead and committed
  > while it was off, which was unintended. So I asked ot have it default to
  > always act like a ruleset is on main. But I realistically haven't removed the
  > ruleset in a month or more."
- > ""graph.v2 root names its subject only through gc.input_convoy_id" Why is
  > this needed at all by us? What are we doing differently that justifies
  > something like this."
- > "I basically want to see ap roposal that effectively says, delete these
  > thousands of lines because we're using Gas City convoys as the noun / verb.
  > And we'll need to tweak these few things. And we'll have to manage XYZ
  > feature(s) we have today to work or otherwise evaluate removing the features.
  > Alternative: defend every last piece that we do not remove on why it exists,
  > what feature(s) it enables, and what would need to happen in Gas City to lose
  > it. In short, the warrants ask."

What the sitting settled, which binds the design:

1. **The end state is about zero pack convoy code.** The acceptance bar is the
   external-observer test: someone who knows only Gas City and its standard
   packs sees a normal convoy in this pack's graph and operations. The design
   claims that gc-toolkit uses Gas City's convoys as they are intended to be
   used, and proves it.
2. **The PR rule is one line: a bead landing on main lands through a PR.** Its
   warrant is the incident above. The rule for integration branches and other
   PRs' heads goes, and the protection of any other branch is the GitHub
   ruleset the operator defines. gc-toolkit's main carries one today: a pull
   request with one approval, squash merges only, and the required checks
   `test` and `test-macos`. Gas Town's refinery has no protected-branch
   detection and no PR fallback, so a direct push the ruleset refuses is retried
   forever. The ruleset enforces, and the one line keeps main-bound work on the
   PR path.
3. **convoy-seed.sh shrinks to Gas City's verbs** (`gc convoy create --owned`,
   `gc convoy target`) plus the one git act no verb performs, cutting
   `integration/<id>`, or it dies into the formula that seeds. A named wrapper
   needs a warrant it is unlikely to earn.
4. **Graduation is weighed against Gas Town's `integration_branch_auto_land`
   in this design,** not left to the migration epic. Gas Town's auto-land makes
   the convoy's bead the work bead that carries its branch to main once its
   members close. Gas City's auto-close and `gc convoy land`, which moves no
   branch, are adopted where they fit.
5. **The deletions enter the cut.** The convoy code the last design left to the
   migration epic (graduation, and the integration-branch flow: convoy-seed.sh,
   mol-design-convoy's seed and drain steps, the `base: integration` banner and
   label) becomes units. Each deletion is made, or its survivor is warranted.
   The workspace-setup guard that bridges a member's target keeps its warrant.
6. **The readers of the input convoy are the second platform gap.** Gas Town's
   own formulas derive their subject from the input convoy the same way, so
   these readers are native shape. The design records the gap with an upstream
   ask, for a graph.v2 root that names its subject directly, and defends the
   readers by that warrant rather than deleting them.
7. **The design inverts the count.** The rebuilt design deleted almost no
   convoy code and added a little. This one deletes far more than it adds.

## The operator's ruling (2026-10-24)

The deletion plan went to a sitting on its warrants. The operator asked what
each warrant defends, and the sitting ended with a ruling that stops using a
convoy to carry a branch. These are the operator's words in the sitting,
verbatim:

- > "Why doesn't Gas City need this today? What are we doing differently that
  > forces this to be something we need but no one else does."
- > "In short, we are explaining the warrants, not defending them with what user
  > facing feature/functionality we are doing that requires this warrant to
  > exist."
- On the rule for main:

  > "That's my rule, clearly change behavior, it holds easily"
- On the readers of a workflow's input convoy:

  > "Reading overall sounds sane, but that's just us looking at data vs
  > changing behavior. Unsure if I'd even call a read of state as a warrant, if
  > that's really waht that is"
- > "We are definitely cleaning up, this is our material opportunity to make
  > sure we have the right design, anything we carry is a huge long-term cost
  > for our maintainence burden"
- > "So in that explanation, it sounds like it could find more than one convoy
  > that disagree on the branch. That's not good. Shouldn't the branch be on the
  > bead or something? I get the issue better now, but the how it's handled
  > feels forced or just not architecturally sound. Because a branch is
  > singular, but it sounds like it cna have more than one bead, that leads to a
  > conflict, right?"
- > "Let's say I have three integration branches I'm working on. All have
  > multiple beads targeting those branches.
  > I then create a convoy intending to track (taking the view convoy is a group
  > for tracking) the completion of all security beads on those three
  > integration brnaches.
  > That convoy would show me status of all security work as a group.
  > That convoy isn't involved in where the work goes, nor is it in charge of
  > moving the work forward. It's just a status grouping."
- > "So I'm of two minds:
  > - Bail on convoys completely for the branch purpose. Agents chain beads when
  >   working on a branch and know to set the proper branch
  > - FIgure out how to update convoys to do what they at one point they dreamed
  >   of being. But I'm worried what they are and what they aspire to be are at
  >   odds iwth eachother."
- The ruling:

  > "bail, each bead carrys its branch, landing bead per integration, and could
  > still be tracked under a convoy for our own purposes. But the convoy does not
  > enforce the branch."
- > "From this conversation, I'm wondering if we are using convoys appropriately
  > where we should as that trackable unit, but no need to really mix that into
  > this PR."
- > "I feel like net result is convoys don't do what we wanted, so we need some
  > supporting logic around how a convoy can track a branch overall, but how
  > that branch gets delivered, work gets added, etc. is 100% in gc-toolkit
  > logic."

What the sitting settled, which binds the design:

1. **Why a convoy cannot carry the branch.** Gas City builds a convoy as a
   status grouping, and many convoys track one bead: sling's wrapper convoy,
   each run's input convoy, and any grouping a person makes. A convoy could
   hand its branch to its work only while joining a convoy made the convoy the
   bead's parent, so that a bead had one convoy above it. That ended on
   2026-05-21, when Gas City moved membership to `tracks` edges so that joining
   a convoy no longer evicts a bead's epic. Carrying a branch on a convoy again
   would be a Gas City redesign of convoys. A bead already has the singular
   slot, its own `target`, and an ordinary bead can be the deliverable that
   carries a branch to main.
2. **The model.** Each bead carries its own landing branch in its own
   `target`, written when the bead is filed for an integration effort. One
   ordinary landing bead per integration branch is the deliverable: it names
   the branch (`branch=integration/<id>`, `target=main`), waits on the effort's
   beads through `blocks` edges, goes to the refinery when they close, and opens
   the one PR into main. A convoy may track the beads and the landing bead for
   status, and then closes itself when the landing bead closes. It carries no
   branch and enforces none. Nothing here uses owned convoys,
   `gc convoy land` or a convoy target. In answer to the last quote above, the
   landing bead, not a convoy, tracks the branch.
3. **Every survivor is defended** by what the operator would lose without it,
   and by what gc-toolkit does differently from a standard Gas City and Gas
   Town city. Explaining a piece's mechanism is not a defense.
4. **The rule for main stays, and it is the design's only warrant:** a direct
   landing on main resolves to `mr`.
5. **Setup is recipe, not warrant.** The mechanik's recipe and
   `mol-design-convoy` are rewritten to the model: cut `integration/<id>` once,
   with one create-only push
   (`git push origin refs/remotes/origin/<base>:refs/heads/integration/<id> --force-with-lease=refs/heads/integration/<id>:`);
   file the landing bead; and as each bead is filed, give it its branch and make
   the landing bead wait on it.
6. **The deletions.** Graduation (`convoy-graduate.sh`, its test,
   `orders/convoy-check.toml` and arm 8's stamp), `convoy-seed.sh` and its
   tests, workspace-setup's convoy target guard and its test, the
   `base: integration` banner and label, and the wiring that makes a convoy
   the landing unit. Gas Town's `integration_branch_auto_land` is not adopted,
   and no script runs it.
7. **No Gas City fix is a prerequisite.** The beads tutorial's contradiction,
   which says both that members are not children and that a target is
   inherited by child beads, and the regression behind it, may be reported
   upstream as information.
8. **The readers of the input convoy are lookups, not warrants.** One unit
   replaces the copies of the lookup with one shared reader, and deletes the
   duplicates: `step-close.sh`'s `--convoy` route, the double-pour half of
   `gate-ensure.sh`, `work-tree-holder.sh`, and `mol-design-convoy`'s drain
   together with `live-work.sh`'s count of closed tracking convoys.
9. **Two things the design pins down:** how the landing bead reaches the
   refinery once its waits clear, and how the open convoys that carry a target
   today move to the model. The spec names no live bead.
10. **The deletion map's target is about 2,500 lines net removed**, which the
    design measures.
11. **Whether gc-toolkit uses convoys well** wherever it uses them as a
    trackable unit is a separate question (tk-fv1pkm6), outside this PR.

This replaces four things the 2026-10-23 sitting settled: the shrink of
`convoy-seed.sh` onto `gc convoy create --owned` and `gc convoy target`, the
weighing of graduation against Gas Town's auto-land, the warrant kept for the
workspace-setup guard, and the readers of the input convoy as a platform gap
with an upstream ask. The design's framing no longer rests on the convoy, so
its title drops "on Gas City's convoy as it is intended to be used". The
external-observer test stays, as a check of what a Gas City and Gas Town reader
sees.

## The model

1. **Every PR is the operator's.** The city opens a PR, into main or into an
   integration branch, only to ask for the operator's review. It opens no PR
   that is not for the operator.
2. **A PR comes from one bead.** A lone bead's PR comes from that bead. Work
   that reaches the operator as one PR is an integration effort. Its beads are
   each built by their own polecat and land on the effort's integration branch
   with no PRs of their own. One landing bead waits on them, and once they are
   done it carries the branch to main through the PR, which gets the overall
   review. A PR into main is a complete unit of work. A bead still opens its own
   PR into the integration branch when the operator should review it on its
   own.
3. **Each bead is reviewed inside its own work molecule before its work
   lands.** mol-polecat-work's self-review loop checks the bead's work. The PR
   gets the overall review, which is where big-picture items are caught.
4. **The city works in as many internal phases as it needs** before it opens a
   PR.
5. **Multi-stage work is more than one PR.** Every reviewable unit is a PR. An
   early stage can be a PR into an integration branch, and the last one goes to
   main.
6. **A bead carries its own branch.** Its `target` names where its work lands.
   A bead filed for an integration effort carries the effort's branch from the
   moment it is filed.
7. **A convoy is Gas City's concept, used as Gas City builds it: a status
   grouping.** It tracks beads with `tracks` edges and is not their parent. It
   may track an effort's beads for status, and it carries nothing a bead needs to
   do its work. A merge strategy means what Gas City defines: `direct` merges
   the work branch into its target, `mr` delivers it through a merge or pull
   request, and `local` leaves it on its branch with no merge and no request.
8. **Work reaches main only through a PR.** A PR is how the operator sees what
   commits reach main. Whether any other branch needs a PR is set by the GitHub
   ruleset the operator defines for it.

## What already works, by hand

- **A bead can land on an integration branch with no PR.** Give it
  `target=integration/<id>` and sling it with `--merge direct`. Sling branches a
  bead from its own `target`, and the refinery reads the bead's own
  `merge_strategy` (formulas/mol-refinery-patrol.toml, merge-strategy-resolve).
  It does not force `integration/*` targets to `mr`.
- **The landing is recorded.** direct-merge-push.sh fast-forwards the target,
  records `merge_result=merged` with `merged_target`, and closes the bead.
  GitHub requires only signed commits off the default branch (the "Signed
  Commits" ruleset). The "Default Branch" ruleset covers main alone.
- **One bead can carry a branch to main.** The refinery takes a bead assigned to
  it that names a `branch`, merges main into that branch, and hands a bead
  aimed at main to the merge cadence, which opens its PR. Graduation hands the
  convoy's bead to the refinery this way today. An ordinary bead with the same
  keys takes the same path.
- **A bead can wait on others.** A `blocks` edge keeps a bead out of `bd ready`
  until its blocker closes. A bead assigned to a named agent is offered to that
  agent once it is ready, and the deferred-dispatch pass sends the notice that
  wakes the agent for it.

So the model is reachable today by hand. The fix makes it the default, and
deletes what making the convoy the landing unit required.

## What holds it back today

- **Every bead opens its own PR, integration work included.** The refinery
  reads a bead's own `merge_strategy` and falls back to its formula default,
  which is `mr` (formulas/mol-refinery-patrol.toml, `vars.default_merge_strategy`,
  since #197 on 2026-07-21). Gas Town's refinery falls back to `direct`. The `mr`
  default came from a city-wide setting made to stop direct pushes to a main
  branch, and nothing shows integration branches were considered.
- **The branch lives on the convoy.** The mechanik's recipe and
  mol-design-convoy name the branch on an owned convoy and link each member to
  it with a parent-child edge, because Gas City's sling finds a convoy's target
  only through a bead's parent. A bead has one parent and can be tracked by many
  convoys, so a member that also sits under an epic can lose its branch, and a
  guard at workspace-setup exists to catch that.
- **The convoy is the landing unit.** Graduation hands the convoy's bead to the
  refinery once its members close, from a cadence arm with conditions of its
  own, and a mol-design-convoy subject closes when its convoy does.
- **Each work bead owns its own PR.** The anchor model (#465):
  docs/component-model.md I4, "Every PR has exactly one owning anchor", with the
  anchor being the work bead.
- **Integration work opens its own PR on purpose.** #994 (tk-sw5bu) left
  `integration/*` targets on `mr` on purpose. The refinery's merge-strategy
  block has no rule of its own for them: it flips only a bead aimed at a
  `polecat/*` head to `direct`, so a bead that names no strategy takes the `mr`
  default.
- **A polecat takes one bead at a time.** mol-polecat-work refuses an input
  convoy with more than one member.
- **The city's checks run on a PR's owning bead.** gate-ensure.sh dispatches the
  review beads for an anchor. Correctness, triage, arch and pm run before its PR
  opens, and demo runs on the PR while it is a draft.
- **Every PR into an integration branch is labelled a phase.** The
  `base: integration` "phase" label and banner go on every PR into an
  integration branch (#851). docs/design-convoy.md says each member's PR needs
  approval.
- **gc-toolkit carries convoy machinery of its own beside Gas City's.** A seed
  script wraps two Gas City verbs and a git push. A graduation arm does what Gas
  Town's auto-land does, with conditions of its own. An hourly order runs the
  same sweep as an order in Gas City's core pack. A guard catches a member
  poured without its convoy's branch. A banner and a label mark every PR into
  an integration branch. And one lookup of the input convoy that Gas City's
  sling makes for each pour is copied across the pack.

## Constraints

- **I4 stays.** Every PR has exactly one owning bead: the bead it came from. For
  an integration effort that is the landing bead, and the effort's other beads
  own no PR unless they are stages.
- **The approval rule stays.** Every PR needs the operator's approval (merge.sh).
- **The four tests decide what the design may build.** Any script change is
  glue that composes native calls.
- **Every survivor is defended.** Each piece the design keeps is defended by what
  the operator would lose without it, and by what gc-toolkit does differently
  from a standard Gas City and Gas Town city. A pack noun still needs a dated
  warrant and a retirement trigger.
- **The PR rule is one line, for main.**
- **This fix cannot use itself.** Until it lands, the machinery still opens one PR
  per bead, so the fix's own implementation goes out in as few PRs as possible.
- **The spec names no other repository, no other rig's beads and no live bead
  data.** It names each Gas City source for what it is: a page of its
  documentation, a symbol in its code, or one of the packs it bundles.

## What the design settles

- **The deletion map.** How much convoy code gc-toolkit carries, what each unit
  deletes, what the design adds, and the net, measured.
- **Making it the default.** An integration effort's beads land on its branch
  with no PR unless told otherwise, rather than each one needing
  `--merge direct` at sling time. The refinery's default changes, and the PR
  rule is the one line for main.
- **A bead's own branch.** How a bead filed for an integration effort carries
  its branch, and what becomes of the workspace-setup guard.
- **Standing an integration effort up.** The cut of its branch, its landing
  bead, how each bead joins the effort, how work joins it later, when the branch
  is brought current, and what becomes of convoy-seed.sh.
- **How the landing bead reaches the refinery** once its waits clear, and what
  becomes of each feature graduation carries.
- **Where each review runs, and when the PR opens.** Which reviews run inside
  each bead's molecule and which once on the PR. Rework from the operator's
  review comes back to the same PR.
- **The input convoy's readers.** One shared reader in place of the copies, and
  the duplicates it deletes.
- **What a Gas City and Gas Town reader sees,** row by row.
- **Moving the open convoys that carry a target today** onto the model.
- **What to correct,** in every living file the deletions and the model touch.
- **The implementation cut,** with the deletions as units, within the
  constraints above.

## First case

The review epic's seven correctness-method changes (tk-qjdt90g.9, .4, .5, .8,
.6, .7 and tk-wigtu9) become one integration effort: seven beads on one
integration branch and one landing bead. They keep their build order, and each
is built and reviewed by its own polecat. The operator reviews one PR.
