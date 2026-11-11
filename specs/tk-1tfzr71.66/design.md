---
name: Design — one approval contract for the city's PRs, with the work pending until its merge is verified
description: The design for tk-1tfzr71.66, the design child of initiative tk-1tfzr71.20, read at main 7ed46e378 against Gas City upstream main 6bd609f5bfb4, gascity-packs main 7f86098c04ea, bd v1.3.4 and gc-toolkit's GitHub rules as they stood on 2026-11-11. It sets one approval contract for every PR the city opens, on the default branch and on integration branches alike, keeps the work's bead open on Gas Town's pending-through-merge record until the merge is verified on the target, decides each PR's readiness in one evaluator that the board and the merge both read, says how the pack's refinery takes Gas Town's flow and where it still differs, answers the brief's questions and each problem held on this retirement, and defines the units the implementation child files and the cutover after them. Read it to approve the design at its gate, or to build one of its units.
---

# Design: one approval contract for the city's PRs, with the work pending until its merge is verified

This is the design record for tk-1tfzr71.66, the design child of the
initiative tk-1tfzr71.20. The pack was read at main 7ed46e378, the commit
`integration/tk-1tfzr71.20` was cut from. Gas City is cited by symbol at
`gastownhall/gascity` main 6bd609f5bfb4, and the code cited reads the same at
862ee37e4570, where an earlier draft read it, except a formula check's attempt
count (section 13). Gas Town is cited by path at `gastownhall/gascity-packs`
main 7f86098c04ea, and at 66897e7132c9, gastown 0.1.13, the last release the
packs registry lists and the one that Gas City main and the city's gc 1.4.3
bundle (`PublicGastownPackVersion`). bd is cited at `gastownhall/beads` v1.3.4
(7ef2fd05eb0c), the build the city runs. GitHub's behavior is cited by its
documentation page, by its GraphQL schema as read on 2026-11-11, or by the
manual of gh 2.103.3, and gc-toolkit's rules and settings were read live on
2026-11-11. The contract this design builds is the operator's ruling of
2026-11-11 in conversation tk-tj17s9i, which tk-1tfzr71.66's notes record. The
search behind the surface the units add is
[gas-city-search.md](gas-city-search.md).

## What the operator approves

Today the pack merges every PR itself, under its own approval rule, once a
merge pass finds the review lanes green, and a transition machine checks each
landing write. On the default branch GitHub's rules also require your approval,
and on an integration branch only the pack's rule does.

Approving this design sets one contract for every PR the city opens, into the
default branch or an integration branch alike, and for every push onto such a
PR, yours included. A PR the city did not open, such as Dependabot's, a person's
or one from a fork, stays outside it. The city knows its PRs by the account that
opened them. When another account has already opened a PR from a work's branch
into its target, the city takes neither that PR nor a second one, and asks you,
through a gate, to close that PR or stand the work down. You approve the PR. The
city finishes the fixes and checks still owed, then merges it, and you press no
Merge. GitHub's rules still apply wherever a branch has them, and a branch
without an approval rule still needs your approval. The city bars no account
from approving, its own (zook-bot) included, but GitHub refuses an approval from
a PR's own author, and the city's account opens every PR in this contract, so
your approval comes from another account. Your approval carries across ordinary
rework. When triage reads a new head as a material change, the city dismisses
the earlier approval, and the PR waits until GitHub shows it dismissed and you
approve again.

The work's bead stays open from the moment its PR is published until the merge
is verified on the target, on the record Gas Town's refinery keeps for the same
purpose, so the work that waits on it starts only on code that has landed. One
evaluator decides whether a PR is ready, and the board and the merge both read
it. When the evaluator finds the PR ready on a fresh read, the city asks GitHub
to merge exactly the head it judged, and it closes the bead only once it finds
the merge commit on the target. No auto-merge and no commit status of the
city's stand as a permission to merge.

**What it leaves open.** A review, a comment, a hold or a change of base that
arrives between the city's last read and GitHub's merge is not part of that
decision, because the merge request binds only the head. A merge request that
GitHub leaves unanswered can still take effect later, over a hold the city has
read since. Anyone who can press Merge on GitHub merges past every city hold,
wherever the branch's rules let them. A merge into another base than the record
names, a merge of a head the city did not validate, or a PR closed without
merging keeps the bead open behind a gate for a person, and is never closed as
landed. Until the GitHub-intake member lands, as today, the city routes nothing
an approval's own message asks for.

**When it reaches a rig.** The new path reaches a rig only after the
review-lanes member lands, because the evaluator counts a review result only for
the head and the target it names, and that member's loop is what records them.
Until a rig moves, it keeps today's flow. Each rig's cutover asks you, through a
gate, only where the city's account cannot dismiss a review in that rig's
repository.

These calls carry a cost either way. The sitting that ruled the contract did
not rule on them:

1. **The seed audit.**
   - (a) Re-render after landing, and hold no PR for it. Until the re-render
     lands, the next PR's diff can show render lines it did not change.
   - (b) A CI check your ruleset requires. A PR that changes prompt inputs then
     needs bringing current whenever the default branch moved its renders, and
     a render can still go stale after the check passed, because a branch need
     not be current to merge.
2. **A merge hold for a deleted script that open runs still call.**
   - (a) No hold. Each deletion bead keeps its drain check, and a run that
     reaches a deleted script declines with a gate. A missed check costs what it
     did the one time it happened, on 2026-10-27: one run poured again.
   - (b) A hold before any PR into the default branch merges. It needs a reader
     of every store's open steps, which is what the retired PR (tk-57wjk4l)
     built.

Approving as it stands ships the first option of each. Some of the deletion
plan's rows move to the members whose code still calls their files (section 8).
Section 11 lists the units the implementation child files, and section 10 the
cutover beads and the retirement bead that land after the effort does.

## 1. The target flow, and how the pack takes Gas Town's

### The flow

1. A polecat hands its bead to the rig's refinery, as it does today. A rework
   child's polecat pushes its anchor's branch, which moves the PR's head, and
   hands the child to the refinery.
2. The refinery takes one bead assigned to it, open or in progress, that
   carries a branch, as Gas Town's find-work does. Before it prepares the
   branch, it checks that nothing holds the bead (`gctk bead holds`) and that no
   other open bead is working on that branch. It takes a rework child handed
   back to it before the child's anchor.
3. It brings the branch current by merging the target in, and runs the rig's
   gate.
4. A failure the branch caused sends the work back to the polecat pool. A
   failure that is already on the target is tracked, and the landing goes
   ahead.
5. A `direct` bead lands by a fast-forward push, and the refinery records
   `merged` and closes it.
6. For an `mr` bead, the refinery composes the PR's title and body with
   `gctk pr compose`. When the bead owns an open PR, the refinery edits that
   PR's title and body, then pushes the new head under git's lease on the commit
   it read on the branch (section 4). When the bead records no PR, the refinery
   first looks on GitHub for a PR open from the bead's branch in the rig's
   repository into its target. It adopts one it finds and handles it as a PR the
   bead owns, as Gas Town's merge-push takes the PR open for its branch when
   `gh pr create` fails, so one branch never gets a second PR. When none is
   open, it pushes the branch and opens the PR as a draft. Either way it then
   writes the pending record with `gctk pr record`. The bead goes to `blocked`,
   stays assigned to the refinery, and records
   `merge_result=pull_request_pending` with the PR's identity, its intended
   target and the head the refinery validated (section 6). For a rework child,
   the record it writes is its anchor's, and it then closes the child as landed
   on its anchor's branch.

   The step takes a PR, one the bead records or one it finds open on the
   branch, only when the city's account opened it: the PR's author is the login
   the city's `gh` acts as (`pr-post.sh acting-login`), matched exactly, the
   test `pr-open.sh` already uses to tell its own drafts. A PR that another
   account opened stays outside the contract. The step edits nothing on it,
   pushes nothing, opens no second PR, and parks the bead behind a human gate
   that names the PR (section 6). The person closes that PR, and the refinery
   opens the city's own once the gate clears, or the person stands the work
   down. A step that cannot read the PR's author or the city's login takes no
   PR and tries again on its next pass. GitHub changes no PR's author once the
   PR is open (`updatePullRequest` takes none), so a record, which names only a
   PR the city's account opened, needs no later check of it.
7. The review lanes run on the draft, and the PR turns ready for review once
   the lanes before that phase pass.
8. The landing order runs `gctk pr reconcile` on a cooldown. Each run takes the
   pending records it checked least recently and reads each one's PR from GitHub
   by its number:
   - When the PR is open at the head the refinery validated, the evaluator
     decides whether it is ready (section 4). When it is, the order asks GitHub
     to merge exactly that head. When it is not, the order records when it
     checked.
   - When the PR is open at another head, the record moves to
     `pull_request_head_changed`, and the bead goes back to the refinery, open,
     which validates the new head from step 2.
   - When the PR has merged the validated head, and the merge commit is on a
     freshly fetched target, the order records `mr_merged` and closes the bead.
   - Anything else is an exception that keeps the bead open behind a gate for
     a person (section 6).
9. The close releases the work that waits on the bead.

### What the pack keeps of its own

The city imports no gastown pack. The gastown release that Gas City main and
the city's gc bundle closes an `mr` bead as soon as its PR is published
(`gastown/formulas/mol-refinery-patrol.toml` at 66897e7132c9, merge-push), and
its `gastown/commands` holds only `status`. Gas Town main keeps the bead pending
until the merge is verified (`gastown/commands/pr-merge-reconcile/run.sh` at
7f86098c04ea), and no release carries that yet. So the pack keeps its own
refinery formula, modeled step for step on Gas Town's at 7f86098c04ea, as its
witness is modeled on Gas Town's witness
([built-once-target.md](../../docs/built-once-target.md#patrol)), and it writes
Gas Town's pending-through-merge record itself, with Gas Town's values and their
meanings. The steps are validate-identity, check-inbox, find-work, rebase,
run-tests, handle-failures, merge-push, patrol-summary and next-iteration. Gas
Town's ancestry check, which skips the prep when the target is already in the
branch, and its park when the target branch is missing, come with them. Each
step calls one tested script
([rule 2](../../docs/built-once-target.md#the-rules)).

Each remaining difference names its reason and what ends it:

| Difference | Reason | Ends when |
|---|---|---|
| The branch is brought current by merging the target in, and every push is a fast-forward. A push onto a PR's branch goes under git's lease on the commit the writer read on the branch, and that lease never forces, because the writer checks first that the new head descends from that commit (section 4). Gas Town rebases, and in `mr` it force-pushes with a lease that names no commit. | A PR under review keeps the commits its approval and its threads were given on. A fast-forward cannot overwrite a commit the branch gained after its prep, which the lease against a shared remote-tracking ref did (tk-ni0i48p), and a push someone else made is refused, never overwritten. | No end is planned. This is a measured reason to differ. |
| A bead with no PR yet goes back to the pool through `gc sling` on `mol-polecat-work`, with its branch kept. Work on a branch whose PR is open comes back as the PR's rework child, so the bead keeps its PR and its record. Gas Town writes the pool route by hand, and after a failure the branch caused it deletes the branch. | Dispatch goes only through `gc sling` (the dispatch design, `specs/tk-1tfzr71.54/design.md` on `integration/tk-1tfzr71.15`). Deleting a PR's branch closes the PR. | Gas Town requeues through `gc sling` and keeps the PR of a bead it sends back. |
| A failure already on the target is tracked by `preexisting-failure.sh`, keyed by its symptom. Gas Town searches open bugs by title. | Two agents title one failure two ways. The key finds the tracker after a retitle, and the work formula's pre-flight files through the same script. | Gas Town keys its tracker. |
| Where a person must act, the pack files a human gate on the bead, keyed by the case: the refinery's park, and each exception the landing order finds (section 6). Gas Town routes the bead to `human` and mails the mayor, and its reconcile blocks the bead and mails the mayor. | A person's wait is a human gate on the bead it blocks (the dispatch design). The seat that tk-rl8gz4b.28 adds in the mayor's place, the po, owns only what a ruling gives it, and that effort's design keeps the same difference for the witness. | An operator ruling gives the po escalation handling. |
| The PR opens as a draft. Gas Town opens it ready. | The city's checks run on the PR before it asks you. | No end is planned. |
| The city merges the PR: the landing order asks GitHub to merge the head the refinery validated, once the evaluator finds the PR ready. Gas Town never merges, and a person does. | You approve, and the city lands the PR, on every target (the ruling of 2026-11-11). | No end is planned. |
| The `mr` step takes a PR only when the city's account opened it, and parks the bead behind a gate when another account opened the PR on its branch. Gas Town's merge-push takes the PR that `gh pr view <branch>` returns when `gh pr create` fails, and checks the PR's state, branch, head, base and repository, never its author. | The city merges every PR it takes, and its contract covers only the PRs it opens (the ruling of 2026-11-11). Gas Town merges none, so a PR it takes still waits for a person's Merge. | No end is planned. |
| The pack writes Gas Town's pending-through-merge record itself (`gctk pr record`, `gctk pr reconcile`), from a landing order rather than from the refinery's find-work, and its reconcile also decides readiness and requests the merge. The record then has two writers, the refinery and the order, so both verbs take the store's record lock, and the record's writes carry bd's guards on the bead's status and assignee, so a bead that closed or left the refinery first gets no record, and a run leaves a bead that a release took from the refinery as the release left it (section 4). Gas Town main runs `gc gastown pr-merge-reconcile` once per find-work, and its witness wakes the refinery when a pending check is due, so its one refinery session makes every write, `record_handoff` writes unconditionally, and its reconcile assigns a bead to the refinery in each write that records a check or a transition. | No gastown release carries the command, and the city imports none. An order needs no agent, so a PR that waits on your approval or on its checks occupies no session. A stand-down can release or close a bead the refinery holds. | The city takes a gastown release that carries `pr-merge-reconcile`, its record refuses a bead that a close or a release reached first, and its reconcile leaves a bead that a release took. The record and the close then become that command, and the pack keeps the readiness check and the merge request. |
| find-work skips a bead that something holds, or whose branch another open bead is working on, and takes a rework child before its anchor. Gas Town lists the beads assigned to the refinery, open or in progress, and reads no wait. | A bead assigned to the refinery can still wait on work that edits its branch, such as a rework child, and two writers on one branch would overwrite each other's work. | Gas Town's find-work reads waits. |
| An already-merged branch records `merged`, at the target commit that holds it. Gas Town records `already_merged`. | Every reader that asks whether a `direct` landing happened asks one value (section 6). | No end is planned. |
| The gate runs through `detached-job.sh`. Gas Town runs each command inline. | A tool call is cut off at ten minutes, and a rig's gate can run longer. | The gate runs where no tool call bounds it, as a formula check script or an order. |
| The refinery takes the hand-off that brings an integration effort's branch current, with plain git (tk-gmjtb2e, which landed on main in #1455 after this branch's base). Gas Town has no integration efforts. | An effort's branch reaches the default branch through one PR. | The convoys member (tk-1tfzr71.23) moves efforts onto `gc convoy land`. |
| One worker per branch. A conflict on a branch whose rework child is open goes to that child. Gas Town has no rework children. | Review feedback is fixed by rework children until the review-lanes member moves that work into its loop. | tk-1tfzr71.22 lands. |

## 2. Where the approval rule lives

**Today.** The operator's ruling of 2026-10-02, recorded on tk-7h5l3m from
sitting tk-kwmyg3, makes approval a universal merge rule in the city's merge
logic. Every PR needs an APPROVED review from an account other than the city's,
and "GitHub branch protection remains an extra enforcement layer only, not the
mechanism". `gctk merge` applies the rule (`reviewVerdict` in
`services/gctk/internal/cli/merge.go`). Each account's latest review that
approves or requests changes counts, and a review that only comments changes
nothing. A standing CHANGES_REQUESTED vetoes, and no approval given at or before
`bring_current_lifted_at` counts. It skips the city's own account, and it counts
a review from any other account, whatever that account's access to the
repository. `review-verdict.sh` holds a second copy, which `pr-facts.sh`,
`approval-withdraw.sh`, `bring-current-guard.sh` and `converse-signoff.sh`
source, and the verdict cases in `merge.test.sh` hold the two equal.

**GitHub, as read on 2026-11-11.** The Default Branch ruleset covers the default
branch alone. It requires one approving review, resolved review threads and the
`test` and `test-macos` checks from GitHub Actions, allows squash merges only,
and requires neither a current branch nor a merge queue. It neither dismisses
stale reviews nor requires the last push to be approved. Every branch carries
the Signed Commits ruleset, and an integration branch carries nothing else.
Auto-merge is not allowed in the repository's settings, and the city's account
can push to the repository but is neither an admin nor a maintainer. GitHub
counts toward a required review only the approvals of accounts with write
access, and a PR's author cannot approve it ([Approving a pull request with
required reviews](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/approving-a-pull-request-with-required-reviews)).
A review records whether its author can push to the repository
(`authorCanPushToRepository` on `PullRequestReview`).

**The design.** The pack keeps an approval rule of its own, because no rule of
GitHub's covers an integration branch, and the operator's ruling of 2026-11-11
asks for your approval on every target: "So even without required approvals on
main, the city in MR, which is our default, should still require an approval",
and "It applies on main or an integration branch." The evaluator applies the
rule at each decision (section 4). It reads the reviews fresh from GitHub, and
takes GitHub's own eligibility:

- An approval counts when it is the latest review that approves or requests
  changes from an account that can push to the repository, the approval GitHub
  counts toward a required review. A later review that only comments leaves it
  standing. No account is excluded for being a bot, an app or the city's own.
  GitHub refuses an approval from a PR's author, though, and the city's account
  opens every PR in the contract (section 1), so an approval through that
  account never stands on one. No step tells an agent to approve.
- A request for changes that is such an account's latest review of those two
  kinds holds the PR until its author approves or it is dismissed.
- A dismissed review counts for nothing. Nothing else ends an approval: no time
  of the city's own, such as `bring_current_lifted_at`, counts against an
  approval that GitHub still shows.

Where the target's rules require an approving review, GitHub enforces its own
count as well, and the evaluator reads GitHub's merge state too, so the
stricter of the two holds.

This departs from the ruling of 2026-10-02 in two ways. The city's account is
no longer excluded, as the ruling of 2026-11-11 asks: "I am not really
concerned about that nor the risk that zook-bot could go rogue and approve in
GitHub itself" (typo fixed). And a review from an account that cannot push to
the repository counts for nothing. Today's rule counts it, and on a public
repository anyone can review, so today an approval from any other GitHub account
satisfies the rule on a stage PR, whose branch carries no approval rule of
GitHub's.

`reviewVerdict` and the approval gate go with `gctk merge`. `review-verdict.sh`
and the lift line go once their last readers move: the sign-off in unit 5,
`bring-current-guard.sh` and `approval-withdraw.sh` with tk-1tfzr71.22, and
`pr-facts.sh`'s posture with tk-1tfzr71.21. The approval behavior stays, in the
evaluator, the one place the pack reads an approval.

## 3. How an approval behaves when the PR changes

**GitHub's settings stay as they are.** `dismiss_stale_reviews_on_push` and
`require_last_push_approval` stay off. GitHub dismisses an approval as stale
whenever the PR's diff changes, "because a contributor pushes new changes to the
pull request branch or clicks Update branch, or because a related pull request is
merged into the target branch", and the second setting needs a fresh approval
after each push ([Available rules for rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets)).
Either one would withdraw your approval at the first rework. In tk-o9i6kp0
(2026-11-05), which conversation tk-qimlnbz answered, you asked for the
opposite: an approval that carries across a rework, so the PR merges once the
rework completes, "unless something major comes up, just like in a merge
conflict, that required material decision making" (typos fixed).

**One decision, with one owner.** In conversation tk-k3g9xbi (2026-11-09) you
said: "If the steps believe enough has changed, they are supposed to dismiss my
review so it is no longer there and otherwise, that review holds." In the target
the owner is triage's decision at each new head, which tk-1tfzr71.22 builds into
its loop. Triage reads the change itself. When it rules the change material,
such as a conflict that was resolved with decisions of substance, the
withdrawal is work the loop owns, and it blocks the PR's bead until it finishes.
It dismisses every approval given before that head, with the city's mark in the
dismissal's message, the mark `gctk pr post` owns, and asks for your review
again. It finishes only once GitHub shows each of those approvals dismissed. A
dismissal GitHub refuses leaves it unfinished, behind a human gate, so the PR
stays held rather than merging on an approval the city meant to withdraw. Before
it dismisses, it lets the intake route the review's own comments, since a
dismissal retires them (the lesson of tk-uos4onx). Nothing else withdraws an
approval, and nothing reads an approval's age: no gate asks for a fresh review
because an approval predates the head, which is the parallel gate the finding of
2026-11-09 records.

**Until tk-1tfzr71.22 lands,** no rig is on the new path (section 10), and the
two writers that withdraw an approval today stay as they are, with their lift
line, on the old path. One is the ruling on a conflicted bring-current round,
which `bring-current-guard.sh` carries out. The other is the validator's ruling
that a fresh whole-diff review is due, which `approval-withdraw.sh` carries out.

**The cases of 2026-11-05.** You ruled them low priority, to follow the rewrite
("Yes, this is low priority and should follow the rewrite",
2026-11-05T22:38Z). The model settles each, and the validating closer armed on
tk-o9i6kp0 checks it against that note once the initiative lands.

1. **A fix asked for in an APPROVED review's own message.** No GitHub rule reads
   a review's message. The intake (tk-1tfzr71.21) reads an approving review's
   message as feedback, like any other review's, so a fix it asks for becomes
   fix work that blocks the PR's bead, and the evaluator reads the PR not ready
   until the fix lands. The approval stands across the fix's push unless triage
   withdraws it. Until tk-1tfzr71.21 lands, the intake's rule leaves that
   message out, as it does today, so a fix asked for there merges unread. This
   is a residual the design leaves open (section 8).
2. **An approval submitted between the comment read and the merge.** The city
   asks GitHub to merge only on the evaluator's fresh answer, and that answer
   reads every review and comment the intake counts, the approving review among
   them. So what can go in unread is only what arrives after that read and
   before GitHub's merge: the moments between the read and the merge request,
   and as long as GitHub takes to merge once asked. Today's merge leaves a
   window of the same kind, between its read of the reviews and its
   `gh pr merge` (`services/gctk/internal/cli/merge.go`). A merge request that
   GitHub leaves unanswered stretches the window to whenever GitHub acts on it
   (section 4). On a branch whose rules require a review, a review that requests
   changes from an account with write access holds the merge from the moment it
   is submitted, until its author approves or someone with write access
   dismisses it ([Approving a pull request with required
   reviews](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/approving-a-pull-request-with-required-reviews)).
   So what stays open is the message of an approving or commenting review, a
   request for changes on a branch with no approval rule of GitHub's, and a
   plain comment, each arriving in that window. Section 8 names it.
3. **The threads the city leaves open.** Wherever the repository requires
   resolved threads, each open thread holds its PR, which GitHub reports in the
   merge state the evaluator reads. The rule for the city's write-back
   (tk-1tfzr71.21): the city resolves the thread of its own post once it has
   answered it, a declined or deferred machine finding included, with the
   answer in the thread. A person's thread stays open until the person resolves
   it, or until the city lands the fix it asked for and resolves it naming the
   commit. So a person's open thread holds the merge, which is the setting you
   chose. On a base that does not require resolved threads, a thread that still
   waits on the city's answer holds the PR through the evaluator's feedback
   receipts, and `prstatus` reads it `held: review`. There the merge waits for
   the city's answer rather than for the thread's resolution, and the merge and
   the label read one answer.

## 4. Where triage sits, and how the city decides to merge

**Triage at each head.** A review result counts only for the head and the
target it names. The loop tk-1tfzr71.22 builds runs triage on each new head, a
head the record requeued included (the ruling of 2026-10-23), and records each
result with the head and the target it judged. Triage reads the change itself
and either adds no checks, so the PR is ready once nothing else holds it, or
reopens the checks the change needs. The evaluator compares a result's head and
target with the PR's live ones at each decision, so a push or a change of base
whose event the city missed still finds no result to inherit. A branch taken
back to a head the loop judged finds that head's result again, which judged the
same commit. Today a lane records no head, and its green survives a push
([state-machine.md](../../docs/state-machine.md#checks)), so no rig moves to the
new path until tk-1tfzr71.22 lands (section 10).

**The draft.** The PR leaves draft when the lanes before the ready-for-review
phase pass. `pr-open.sh`'s flip does that today, and the loop does it once
tk-1tfzr71.22 lands.

**One evaluator.** Readiness is one function of gctk's pr domain, the one
definition that the label, the board and the merge read. It answers for the
PR's current revision: ready, with the head and the target it judged, or the
conditions not met. It reads:

- **The bead's own waits,** through the `waits` package that `gctk bead holds`
  answers from
  ([its contract](../../docs/gctk-architecture.md#the-bead-holds-contract)).
  The work on the PR's branch, such as a rework child, a fix unit, a merge-in
  or a withdrawal, blocks the bead it serves through a `blocks` edge, and never
  waits on it. So do a human gate, a conversation's gate (tk-icol3l8) and work
  that must land first. Until the review-lanes and intake members file their
  work with that edge, the evaluator also counts an open bead whose
  `anchor_bead` names the bead, as `prstatus` does today, and section 12 files
  the removal of that reading. `merge_hold` and `rebase_hold`, set by hand,
  hold it too. The `blocked` status that the record writes is not a wait.
- **The review results** at the PR's live head and target (above).
- **GitHub's live facts,** read fresh. The PR is open and not a draft. Its
  number, repository, head branch and base are the ones the record names. Its
  head is the head the refinery validated (`pr_head_sha`). GitHub reports its
  merge state `CLEAN`, which a conflict, a check that is not passing or any
  rule of the target holds back. Your approval stands, by section 2.
- **The receipts of the feedback the city has handled.** No review or comment
  is newer than the anchor's watermarks, `pr_review_watermark`,
  `pr_comment_watermark` and `pr_issue_comment_watermark`, each the highest id
  routed in its own id space, counted by the intake's own rule. Each thread
  that waits on the city's answer has it, by the anchor's answered marks. Today
  that count is `pr-facts.sh`'s watermark compare, which counts a review's
  message only for a commenting review or one that requests changes. A wider
  count would find feedback the intake never routes, and the PR would stay held
  with nothing left to route. tk-1tfzr71.21 adds an approving review's message
  to the intake's count (section 3, case 1).

The label and the board render the evaluator's answer through `prstatus`, and
the merge acts only on an answer it read in the same run. `prstatus`'s `merging`
is what the board shows, and it authorizes nothing. Readiness is computed per PR
at each read and stored nowhere, so it never stands as a permission on a commit
that another PR shares.

**The merge request.** The landing order asks GitHub to merge a PR only on an
answer the evaluator gave in the same run, and pins the request to the head that
answer judged: `gh pr merge --squash --match-head-commit <head>`, as `gctk merge`
does today (`services/gctk/internal/cli/merge.go`). GitHub merges only while the
PR's head is that commit (`expectedHeadOid` of the `mergePullRequest`
mutation), so a push that lands first makes it refuse, and the next run finds
the head moved. The request binds nothing but the head. A review, a comment, a
hold or a change of base made after the read is not part of it, and nothing in
it stops a person from merging the PR on GitHub, where the target's rules let
them (section 8). The order turns on no auto-merge, so no permission outlives
the decision.

**After the request.** The order reads the PR again by its number on its next
run, never from a list of open PRs, because a PR missing from that list can
have closed without merging. Whether GitHub answered the request with a merge
or left it unanswered, the next run reads where the PR stands: a merged PR goes
to the close (section 6), and an open one is decided again. A request
that GitHub left unanswered can take effect after a run has read the PR open
and found it held, and it then merges over that hold (section 8). GitHub
terminates a request that it takes more than ten seconds to process, and does
not say whether a terminated request took effect ([Troubleshooting the REST
API](https://docs.github.com/en/rest/using-the-rest-api/troubleshooting-the-rest-api)).

**A merge queue.** No rig's target requires one (gc-toolkit's rules, read
2026-11-11). On a target that does, `gh pr merge` adds the PR to the queue once
its required checks have passed, and turns on auto-merge when they have not (its
manual). The order turns on no auto-merge, so on such a target it adds the PR to
the queue itself, with the head it judged (`expectedHeadOid` of the
`enqueuePullRequest` mutation), and reads a PR in the queue (`isInMergeQueue`)
as a merge already requested. A PR the queue drops is decided again on the next
run.

**One writer per branch, and pushes that are never overwritten.** Work on a
PR's branch has one city writer at a time: the open bead whose work it is, such
as a rework child, or the refinery's prep. The refinery's find-work keeps a
second off the branch (section 1). A city push onto the branch goes under git's
lease on the commit the writer read there,
`git push --force-with-lease=refs/heads/<branch>:<commit>`. git's client reads
the branch on the server again when it pushes, and sends its update from the
commit it finds there ([gitprotocol-pack](https://git-scm.com/docs/gitprotocol-pack)).
The lease makes it send the update only when it finds the commit the writer
read, and refuse it as stale otherwise ([git-push](https://git-scm.com/docs/git-push)).
A lease that matches also lets git send an update that is not a fast-forward,
so the writer first checks that the new head descends from the commit it read,
and pushes nothing when it does not. With that check the lease never forces. It
names the commit the writer read, never the remote-tracking ref that every
worktree's fetch moves, which is how today's refinery push passes over a commit
the branch gained (tk-ni0i48p). The pack already pushes with such a lease where
`branch-end.sh` deletes a branch at the tip it checked.

So a push the city did not make, such as yours, is never overwritten. The
city's push is refused, and the next run of the landing order finds the PR at a
head the refinery has not validated (section 6). A push whose answer never
reached its writer needs no record of its own. The server applies it only while
the branch still holds the commit it read, the writer's retry reads the branch
afresh, so neither push overwrites the other, and the landing order compares
whatever head results with the head the refinery validated.

**What still needs ordering.** The commit status, its lock, its records and its
waits are gone, and these questions of order remain:

- **Two runs of the landing order on one record.** Gas City starts a cooldown
  order only when the tracking bead of its last run has closed and no work it
  started is open (the open-tracking and open-work gates in
  `cmd/gc/order_dispatch.go`), and an order fails closed when those gates time
  out unless it is marked `idempotent`. Upstream, those gates do not keep one
  run at a time. The controller's watchdog closes every tracking bead created
  two minutes earlier or more, whether or not its run is still going, an exec
  order may run for 300 seconds by default, and a cooldown counts from the last
  run's start, so the next tick can start a second run while the first still
  works (section 13). The gc this city runs carries a fork change that keeps a
  running run's tracking bead until two minutes past its time limit, and the
  design rests on neither build. A run handles each record under one lock per
  store, a `flock` on `pr-record.lock` in the store's `.beads` directory, on the
  model of the priority lock ([steering.md](../../docs/steering.md#the-lock)).
  The run takes the lock before it reads the record, waiting while another run
  or another writer of the record (below) holds it, and keeps it until its last
  write of that record, never for a whole run. Two runs that overlap therefore
  act on one record one after the other, the second from the record as the
  first left it. gctk opens the lock file close-on-exec, as Go opens every
  file, so no program a run starts, such as `gh` or a Dolt server that a store
  read brings up, inherits it. The kernel therefore releases the lock when the
  run's process ends, so a run that dies, or that its time limit stops, holds
  nothing. This form is taken because it holds on either build and asks no run
  to finish inside a window that Gas City sets in its code. A run limit under
  two minutes would hold too, but every run would have to fit its GitHub reads
  and its merge requests, each of which GitHub can take ten seconds to answer,
  inside that window, and the limit would have to follow the window wherever
  Gas City moves it. An order that a webhook fires skips both gates
  (`memoryOrderDispatcher.Dispatch` goes straight to `launchResolvedDispatch`),
  so each event would start a run of its own. No webhook fires the landing
  order, and its cooldown is how soon a change on GitHub is read.
- **Two writers of one record.** The refinery writes a pending record through
  `gctk pr record`, in the `mr` step and in a rework child's hand-back, and the
  landing order writes each later transition through `gctk pr reconcile`. Both
  verbs take the record lock above, which gctk's pr domain owns, so a run never
  writes a transition over a record that the refinery replaced after the run
  read it. `gctk pr record` holds the lock across both of Gas Town's writes, so
  no run reads the record between the two. It reads the bead under the lock
  first, and writes only on a bead that is not closed and is still assigned to
  the refinery. Each of its two writes carries bd's guards on the status and the
  assignee it read (`--if-status`, `--if-assignee`), which bd checks in the
  write's own transaction, and a guard that no longer holds writes nothing. So a
  publication writes nothing on a bead that left the refinery or closed before
  its record, such as one that a stand-down released before its close. That bead
  keeps its state and gets no record, and the refinery names the PR in a note on
  it. A refinery write waits while a run holds the lock, which the run releases
  after each record and, at the latest, when it ends. A run acts only on a bead
  that it reads under the lock as carrying `pr_reconcile_pending`, and only
  `gctk pr record` sets that marker. So a writer of the record's keys on a bead
  without the marker takes no lock. The direct landing, which closes a `direct`
  bead as `merged`, is one, and so are the cutover's moves. A disposition's
  close, a stand-down's among them, takes the lock too, whatever the bead
  carries, and reads the bead under it, because a publication can mark the bead
  after a read made without the lock. The close then lands before a publication
  takes the lock, or after both of its writes, and it clears any marker it
  finds. Otherwise a run that read the bead before the close could reopen it
  with a requeue, and a later run would reopen the closed bead as blocked, as
  Gas Town's reconcile does with a closed bead that still carries the marker but
  records no verified merge (`pull_request_legacy_closed_unverified`). A
  release, such as `gc-helm.sh takeaway --release`, which a stand-down runs
  before its close, reopens the bead and takes it from the refinery. It takes no
  lock, so it can land after the record, or while a run reads GitHub. A run
  therefore acts on a marked bead that is not closed only while the bead is
  still assigned to the refinery, and each of its writes carries bd's guards, as
  `gctk pr record`'s do, so none lands on a bead that a release reached during
  the run. A run that reads a marked bead that a release took from the refinery
  clears the marker, writes nothing else and names the PR in a note on it, so
  the bead stays where the release left it. Gas Town's reconcile assigns the
  bead to the refinery in each write that records a check or a transition, so a
  landing order that followed it there would take such a bead back and could
  merge its PR. A merge that a run requested before it could read the release
  still stands, and its bead stays open and released. A close that takes no
  lock, such as a person's own, can still land between the two writes. The bead
  then keeps the first write's marker with no record, and a later run reopens it
  as blocked, behind a gate. The order's run takes no lock of its own, and
  nothing that holds this lock takes another, so no two writers wait on each
  other in a cycle.
- **A head GitHub has not moved yet.** GitHub can name a PR's old head for a
  moment after a push. A run that reads the old head after the refinery has
  recorded the new one requeues the record, which costs one more validation.

**Bounded catch-up.** Each run of the landing order takes a bounded number of
records, the ones it checked least recently (`pr_last_checked_at`), and every
record it reads gets a new check time. So a record waits at most as many runs
as the open records take to cycle, and each run ends within an exec order's time
limit, 300 seconds by default (`TimeoutOrDefault`). Gas City stops a run's whole
process group at that limit, which releases the lock, and the records the run
did not reach wait for the next run. A PR that waits on your
approval or on its checks occupies no agent. A finite loop, such as a review
check that retries up to its `max_attempts`, finishes with a result and never
waits for an approval or for CI, because that wait is the landing order's next
read. Unit 3 measures a run's cost and
sets the count and the cooldown, so that a cycle over 50 open PRs stays within
the landing-time checks of section 7.

**The one path that admits work.** The landing order is the one path that
admits work on a pending record: it requeues a changed head to the refinery,
and it requests the merge. Until tk-1tfzr71.21 lands, the merge cadence's
feedback arm (`pr-facts.sh`) keeps routing feedback as rework children, and the
refinery's find-work keeps two writers off one branch. tk-1tfzr71.21 moves
feedback routing into the order's run, so that a webhook, the PR monitor or a
cadence arm never starts a writer on a branch the order does not know of. Gas
City's PR monitor is no record of the city's PRs. It reads no review or comment
(`classifyPullRequest`), and it lists open PRs only. Run with
`--create-repair-beads`, it files a repair bead per PR head only for a PR it
reads as needing action, every PR GitHub reports `BLOCKED` among them, such as
one that waits on your approval. It routes that bead to the monitor's
`repair_route` and pours the monitor's `repair_workflow` on it, which is
`mol-polecat-work` on the PR's branch unless the monitor names another
(`ensureGitHubPRRepairBead`), so the repair bead is a writer of its own from
the moment it is filed. No rig declares a monitor today. A rig that runs one
with repair beads names the intake's join as the monitor's `repair_workflow`,
so the monitor starts no writer. The join, which tk-1tfzr71.21 builds, ties
each repair bead for a city PR to the bead that owns the PR, once the PR's
repository and number, read on GitHub, match that bead's record, as work that
blocks that bead, and the order routes the repair. The join ties nothing of the
monitor's `blocked` class: a repair bead filed because a PR waits on your
approval would still hold that PR once you approved, since nothing in Gas City
closes a repair bead. The repair bead stays the monitor's, keyed by its head,
and the pack keeps no list of PRs beside the records.

## 5. What holds a merge

The merge asks one definition of readiness, the evaluator's (section 4), and
computes no wait of its own. `gctk merge`'s own readers of holds retire with it:
`inflightHolder`, the blocker walk in `recordBlockerVerdict`,
`finalize-gate.sh`'s no-open-gate clause at merge, and `landsFirst`'s `isHeld`.
`prstatus`'s walk of `blocks` edges keeps the job it has today, which is to name
the gate or the bead a person owes the next move on, for the label's reasons and
the board. Moving `prstatus` under the pr domain, onto the ledger, is gctk's
recorded debt, and it goes with tk-1tfzr71.21, which rewrites `prstatus`'s facts
off the posture ([gctk-architecture.md](../../docs/gctk-architecture.md#debt)).

| Hold | Kept | Expressed as |
|---|---|---|
| Work on the PR's branch: a rework, a fix unit, a merge-in, a withdrawal | yes | a `blocks` edge from that work onto the bead, and until tk-1tfzr71.21 and .22 file theirs with the edge, also an open bead whose `anchor_bead` names it |
| A bead that names the PR | no | a bead that must hold a PR blocks the bead that owns it by a `blocks` edge, and naming the PR holds nothing |
| A wait of the bead's own, such as a `blocks` edge from work that must land first | yes | the `waits` answer |
| An open human gate on the bead | yes | the gate blocks the bead |
| An open conversation on the PR | yes | its `conversation.<id>` gate on the bead (tk-icol3l8) |
| A review thread | yes | GitHub's thread rule where the repository requires resolved threads, read through the merge state, and the feedback receipts for a thread still waiting on the city's answer, on every base |
| `merge_hold` and `rebase_hold`, set by hand | yes | read by the evaluator, unchanged |
| The review result at the head | yes | the loop's result for the live head and target |
| Your approval | yes, on every target | GitHub's reviews, read by section 2, and GitHub's own count where the target's rules require one |
| The CI checks and the target's other rules | GitHub's | the merge state `CLEAN` at the head |
| A removed script that open runs still call | no (call 2) | each deletion bead's drain check |
| The seed render | no (call 1) | the re-render after landing |
| The record's own `blocked` status | not a hold | the record writes it, and the evaluator reads the record, never that status, as a wait |

## 6. Which anchor states survive, and what reads them

**The record.** The bead that owns a PR keeps Gas Town's pending-through-merge
record, with the values and meanings that
`gastown/commands/pr-merge-reconcile/run.sh` at 7f86098c04ea writes, and the
pack keeps no state of its own beside it:

- **No record** (the key absent): the bead has not landed and owns no open PR.
  A bead sent back keeps the record it had, so absence never means "rejected".
- **`pull_request_pending`**: the PR is open, and the bead waits on its merge.
  The bead is `blocked` and assigned to the refinery. The record names the PR
  (`pr_url`, `pr_number`, `pr_repo`), the head the refinery validated
  (`pr_head_sha`), `pr_state=open`, the intended target (`merged_target`),
  `blocked_reason` and `pr_last_checked_at`. The refinery writes it in two
  writes, as `record_handoff` does: first the marker `pr_reconcile_pending` and
  `existing_pr`, while the bead is still open, then the whole record with the
  `blocked` status in one write. A refinery that dies between them leaves an
  open bead that names its PR, never a blocked bead with half a record.
- **`pull_request_head_changed`**: the PR is open at a head the refinery has not
  validated, such as after your push. The bead is open and assigned to the
  refinery, keeps `pr_head_sha`, and records `existing_pr` and the head found
  (`observed_pr_head_sha`), with `rejection_reason` saying why. The refinery
  validates the new head and records it pending again, on the same PR.
- **`mr_merged`**: the PR merged the validated head, and the merge commit is on
  the target. The bead is closed. The record names `merged_sha`,
  `merged_target`, `pr_state=merged` and `pr_merged_at`, and keeps
  `pr_head_sha` and `branch`.
- **`merged`**: a `direct` landing, closed at `merged_sha`, the target commit
  that holds the work, a branch that had already landed included.
- **The exceptions.** Each keeps the bead `blocked` and files a human gate on it
  keyed by its value: `pull_request_closed_unmerged` (the PR closed without
  merging), `pull_request_merged_unvalidated_head` (the PR merged a head the
  refinery did not validate), `pull_request_reconcile_invalid` (the PR's URL,
  number, branch or base no longer match the record, such as after a change of
  base) and `pull_request_merge_evidence_contradiction` (GitHub's merge facts
  contradict a recorded merge). `pull_request_record_incomplete`, a record a
  dead writer left half written on a bead still assigned to the refinery, sends
  the bead back to the refinery for validation instead (section 4). None of them
  closes the bead, so none releases the work that waits on it.

`pr_reconcile_pending` keeps Gas Town's meaning: a reconciliation is still owed,
and the marker can outlive the bead's close while the close's own cleanup runs.
It is never a review or approval fact. The pack runs no artifact cleanup after
the close, because its worktree reaper does that job, so the reconcile clears
the marker once the close lands. A lookup that fails, or a merge commit not yet
on the fetched target, is recorded in `pr_reconcile_error` and retried on the
next run, and it never closes the bead.

`rejection_reason` is the record that the work was sent back, and why. A
person's wait is a human gate on the bead, keyed by its case. `pre_open_gate`
retires, because no PR waits to be opened. `pull_request`, today's value for a
bead that owns an open PR, retires. In Gas Town's record it proves only that a
PR was published, which is what the release the city bundles writes as it
closes the bead. `abandoned` and `retargeted` retire into the exceptions above,
and `unanchored` into the absent key. `blocked` and `refused_false_completion`
keep the meanings Gas Town's refinery gives them, a park for a missing target
branch or for a PR it cannot reuse, and a branch that carries no change, each
with a human gate. A PR it cannot reuse is an `existing_pr` that no longer
matches, as in Gas Town, or a PR that another account opened (section 1),
whose gate is keyed `refinery-pr-not-city-opened` and names the PR and the
account that opened it.

**No transition machine.** The lifecycle audit, folded into the initiative's
notes from tk-z014p6b, found that the writer checks its arguments, not the bead
it produces. `cmdTransition` carried 22 refusals on main at the audit, and #1132
took three rework rounds, each adding a guard against a way around the one
before. So `gctk lifecycle`, its validation and the machine in
`lifecycle/lifecycle.toml` retire. Each kept value stays one sentence in the key
registry, and the doctor checks the beads after the write.

**The audit's checklist, for each kept fact.**

| Fact | Written by | Refused by | Checked after the fact by | Inferred by proxy at |
|---|---|---|---|---|
| owns an open PR (`pull_request_pending`, `pull_request_head_changed`) | the refinery's `mr` step through `gctk pr record`, and the landing order's requeue; on the old path `pr-open.sh`'s create and `pr-facts.sh`'s PR records, as `pull_request` | nothing, once the machine goes | `check-one-anchor-per-pr`, and I2 (`check-state-space`) re-read against the kept values | the board's merge rows (`isMergeAnchor`), `waits` (`in_flight`), `work-gate.sh`, `work-submit.sh` (`resolve_anchor`), `deferred-dispatch.sh`'s arm retirement, `priority-lib.sh`, tk-icol3l8's subject test, `pr-facts.sh`'s anchor enumeration |
| landed (`mr_merged` or `merged`, `merged_sha`, closed) | the landing order's close; the refinery's direct landing (`direct-merge-push.sh`); on the old path `gctk merge` and `pr-facts.sh`'s record of a merge made outside the city | nothing | I5 (`check-closed-implies-landed`), widened below | `work-submit.sh` through `gc.work_outcome`, `pr-stack.sh`'s in-flight filter (retiring) |
| sent back (`rejection_reason`) | the refinery's requeue and the landing order's requeue of a changed head; `rework-child.sh` (tk-1tfzr71.22) and `pr-facts.sh` (tk-1tfzr71.21) until they retire | nothing | nothing | `gc-helm.sh`'s takeaway refusal and `waits` (`in_flight`), each reading it as work in flight |
| held for a person | `human-gate.sh`, for the refinery's park and each exception of the record | its one-open-gate-per-key rule | `check-wait-is-an-edge` | none |
| closed | the landing order, the refinery, the duplicate and stand-down writers, a person | bd's close of a bead with open waits | I5, for every bead that carries a PR | none |

**The audit's proposal, weighed.** It is a proposal, not a ruling.
- One meaning per state: adopted. `unanchored` had two meanings, which split
  into the absent key and `rejection_reason`.
- A state checked against the bead a write produces: adopted for the doctor,
  which checks the beads after the write. A writer makes one write and stands on
  its exit, with no read-back.
- A doctor that reads every closed bead: adopted for every closed bead that
  carries `pr_number`, not only one that carries `merge_result`. A bead sent
  back and closed with its PR still open is then checked. The cost is one
  listing per store, bounded by the PRs it has opened.

**Each reader.**

| Reader | Target | Built by |
|---|---|---|
| The board and the status label | Both read the evaluator's answer through `prstatus`, and the record's values. The board's clauses for retired values match nothing once no bead carries them. | unit 2 for the answer, unit 5 for the values; the board member (tk-1tfzr71.24) drops the dead clauses |
| The PR-finishing rank (`prio_pr_approved` in `priority-lib.sh`) | Carried, not dropped. It reads the approval from the posture at `pr_head_oid`, which stay until tk-1tfzr71.21. When the posture goes, the rank reads the approval from the evaluator's answer through `prstatus`. Whichever change removes the machine's exit sets keeps clearing `pr_finishing_settled` and `pr_head_oid` when a bead leaves the values of an open PR, until tk-1tfzr71.21 removes the keys. | tk-1tfzr71.21, and the retirement bead |
| The sign-off's headline (`converse-signoff.sh`) | It reads `prstatus` instead of sourcing `review-verdict.sh`. `needs-review` means the PR still needs your Approve. | unit 5 |
| A rework child parked for a person | It still owns the anchor's branch. The refinery's conflict path, and later the intake's conflict repair, add the conflict to that child's notes, running or parked, and file and sling nothing else. | unit 4; tk-1tfzr71.21 for the intake |
| The doctor | I5 reads every closed bead with a PR, and reads `mr_merged` and `merged` as landed. I2 reads the kept values. `check-one-anchor-per-pr` counts the values of an open PR. `check-refinery-patrol-live` retires with the old patrol. | units 4 and 5, and the retirement bead |
| Readers that take `pull_request` as "owns an open PR" | Each also reads `pull_request_pending` and `pull_request_head_changed`, until the retirement bead drops `pull_request`: `work-submit.sh` (`resolve_anchor`), `work-gate.sh`, `waits` (`in_flight`), the board's `isMergeAnchor`, `deferred-dispatch.sh`'s arm retirement, `priority-lib.sh`, tk-icol3l8's subject test, `stand-down.sh`'s refusal of a bead with an open PR, and `pr-facts.sh`'s feedback, conflict and posture arms, so they reach the new path until tk-1tfzr71.21 replaces them. Its arms that record a merge, a close without one or a moved base keep to `pull_request`, so the landing order stays the one writer of a new-path bead's end. | unit 5 |

**No workflow's end stands in for the merge.** Core's finalize closes the bead a
workflow names in `gc.source_bead_id`, and that bead's chain, only on a pass. It
leaves the bead open on a failure or a cancel (`processWorkflowFinalize` in
`internal/dispatch/runtime.go`). The work's own `mol-polecat-work` run names its
input convoy and no source bead, so its pass at the hand-off closes nothing of
the work bead's. No workflow the pack pours for a PR's review or repair names
the bead that owns the PR as its source, so no workflow's pass can close it.

## 7. Rework and branch currency

**The refinery brings a branch current.** Its prep merges the target in. When
the merge is clean, the refinery pushes it under the lease and records the new
head (section 4), with no polecat and no audit. When it conflicts, the work goes
back to the pool with `rejection_reason` "Conflicts with `<target>` at `<sha>`".
It goes back as the bead itself when the bead has no PR yet, and as the PR's
rework child when it has one (section 1). The polecat merges and resolves the
conflict, and writes in the merge commit's message what collided and what it
decided. `git show --remerge-diff <merge>` then shows a reviewer exactly the
hunks resolved by hand, and that commit is what triage reads at the new head. A
rework or rebuild child is dispatched by `gc sling`, as the dispatch design has
it.

**What this replaces.**
- `pre-open-rebase.sh` goes, because no PR waits to be opened once every rig
  has moved.
- `rejection-repool.sh` goes, replaced by the requeue through `gc sling`.
- The supersession detector has no replacement. The worker who resolves a
  conflict judges it. A branch whose purpose the target already removed is a
  falsified premise, which the worker declines with a gate.
- The polecat doctrine gains the rule from the note of 2026-10-30, as prose: a
  conflict is drift, not supersession, when the branch's edits inside the code
  the target removed are a small share of its change. That is the false
  positive the detector made on PR #1319.
- The bring-current audit and guard stay until tk-1tfzr71.22. They are what
  sends a conflicted round to triage, which rules whether your approval stands,
  until triage reads every head (section 3).

**A landing brings current only the PRs it conflicts with.** gc-toolkit's rules
do not require a branch to be current, so GitHub merges a PR that is behind its
target as long as it merges cleanly. A landing costs no other PR anything unless
GitHub reports it conflicting, and then only that PR is brought current, once.
The evaluator reads the conflict in the merge state and holds the PR. Until
tk-1tfzr71.21, `pr-facts.sh`'s conflict arm files the merge-in, and only for an
approved PR. After that, the intake routes it to the refinery's prep through
the landing order.

**Landing time with 50 or more PRs open.** No pass visits every PR to land one.
The landing order reaches each pending record in turn, the least recently
checked first, and asks for the merge of a ready PR in the run that reaches it.
So a PR lands within one cycle of the order over the open records once the last
of its conditions holds, which is most often your approval or its CI checks.
Today a PR lands within one pass of the merge cadence after its last condition,
and at 87 anchors a pass took about 30 minutes (the city config's override
note). A merge request that GitHub leaves unanswered is read again on the next
run.

The closed epic's two checks, recorded in the initiative's notes of 2026-11-08,
are a proposal, and this design proposes reading them once lane A has landed:
- Nine in ten approved PRs land within 3 hours over a fortnight with 50 or more
  open. The baseline, measured from GitHub as first approval to merge: from 1 to
  14 October, with about 90 to 104 open, the median was 34 minutes and nine in
  ten landed within 16.7 hours. From 25 October to 7 November, with about 6
  open, the median was 5 minutes and nine in ten landed within 2.4 hours.
- A landing brings current only the PRs it directly conflicts with. That holds
  by construction while the rules do not require a current branch.

**The integration-effort hand-off** stays the refinery's (tk-gmjtb2e). It
landed on main in #1455 after this branch's base, so the effort brings it in
when it brings its branch current, and unit 4 rewrites it onto the new formula.
It is a difference from Gas Town until the convoys member lands (section 1).

## 8. What the pack keeps, and in what form

- **The PR's title and managed summary** become `gctk pr compose <bead>` and
  `gctk pr summary <bead>` ([gctk-architecture.md](../../docs/gctk-architecture.md#the-surface)).
  Compose reads the managed region by its markers, never up to the first
  `<details>` line (tk-tefrxph). `pr-summary-region.sh` goes in the same change.
- **`pr-stack.sh`'s re-render** moves into the step that opens or updates the
  PR. The refinery composes the title and body and edits the PR before it
  pushes a new head, so a review started at that head reads the current body
  (tk-pdc0ovc). `pr-stack.sh` and its arm go.
- **The seed audit:** call 1.
- **The merge-strategy values** are Gas City's `direct` and `mr`
  (`merge_strategy` in `internal/beadmeta/keys.go`). `pr` retires.
  `direct-merge-push.sh`'s promotion on a protected branch writes `mr`. Gas
  City's `local` has no consumer here, so a bead slung `local` gets a human
  gate. The rule that a bead bound for the default branch lands through a PR
  stays under its warrant ([Main lands only through a PR](../../docs/warrants.md#main-lands-only-through-a-pr)).
- **`detached-job.sh`** stays (section 1). A formula check script would run the
  gate outside the harness ("after each iteration closes, the orchestrator runs
  the configured script", `[steps.check]` in
  `docs/reference/specs/formula-spec-v2.md`). The patrol is a root-only wisp
  whose steps are never materialized, though, so no step bead exists to carry
  the check.
- **The approval contract and readiness** stay the pack's, in one evaluator
  (sections 2 and 4), because no Gas City or Gas Town primitive decides a merge
  on an approval, on a bead's waits or on the city's reading of the feedback
  ([gas-city-search.md](gas-city-search.md)). The duplicated machinery goes:
  `reviewVerdict` and its shell copy, the lift line, the posture's reading of
  the approval and the transition machine.
- **The pending-through-merge record** is Gas Town's, which the pack writes
  until the city imports a gastown release that carries it (section 1).
- **The residuals the design leaves open:**
  - A review, a comment, a hold or a change of base that arrives after the
    evaluator's read and before GitHub's merge is not part of the decision,
    because the request binds only the head (sections 3 and 4). A change of base
    that merges ends in the `pull_request_reconcile_invalid` exception, never in
    a close.
  - A merge request that GitHub leaves unanswered can take effect after a later
    run found the PR held, so it merges over that hold, and what the hold waited
    for, such as a fix, comes after the merge (section 4).
  - Anyone who can merge on GitHub can merge a city PR past every city hold,
    where the target's rules let them: on gc-toolkit's default branch only with
    an approval and the CI checks, and on an integration branch with nothing.
    When the head they merge is the one the refinery validated, the landing
    order closes the bead as landed, because the work is on the target, and the
    work a hold waited for follows the merge. When it is not, the bead stays
    open behind the `pull_request_merged_unvalidated_head` gate.
  - A fix asked for in an approving review's own message merges unread until
    tk-1tfzr71.21 lands (section 3, case 1).
  - A run that reads a PR's old head from GitHub after the refinery has
    recorded the new one requeues the record once more, which costs one more
    validation (section 4).
  - The city knows a PR as its own by the account that opened it (section 1),
    so a PR that someone opens through the city's account from a work's branch
    is taken as the city's.
  - A PR whose bead closed or left the refinery before its record, or was
    released from it after the record, stays open with no record the landing
    order reads, named in a note on the bead, until someone retires it (section
    4). A merge that a run requested before it could read such a release still
    stands.
- **The pre-existing-failure scripts** stay, off the deletion plan. The work
  formula's pre-flight files a base failure's tracker through
  `preexisting-failure.sh`, and its self-review marks one through
  `rig-check-pre-existing.sh`. Those are the tested scripts the work member
  (tk-1tfzr71.12, closed) moved them onto. Retiring the scripts would put core's
  search-and-file procedure back into step text, against rule 2. Only the
  refinery's own use changes: a failure already on the target is tracked, and
  the landing goes ahead, as Gas Town's handle-failures does.

**The deletion plan's rows.** Unit 6 moves the rows whose files have callers this
member does not retire:

| Rows (lines with tests, at 7ed46e378) | Move to | Because |
|---|---|---|
| `refinery-reconcile.sh`, `orders/refinery-reconcile.toml`, `pace-lib.sh`, `record-failure-cap.sh`, `branch-supersession.sh` (2,734) | tk-1tfzr71.21 | The cadence drives `pr-facts.sh`'s arms and the review arms until those members retire them, and `pr-facts.sh` calls the cap and the supersession check. tk-1tfzr71.21 is last in lane A. |
| `bring-current-guard.sh`, `bring-current-audit.sh` (2,785) | tk-1tfzr71.22 | They carry the approval ruling on a conflicted round until triage reads every head, and `signoff.sh` and the work scripts call them. |
| `branch-context.sh` (462) | tk-1tfzr71.19 | Its only caller is the witness's salvage step. |
| `preexisting-failure.sh`, `rig-check-pre-existing.sh` (1,408) | off the plan | The work formula calls them. |

This member's retirement keeps the other 3,587 lines of its rows:
`merge-tail-report.sh`, `pre-open-rebase.sh`, `refinery-workspace.sh`,
`rejection-repool.sh` and `check-refinery-patrol-live`. It also retires old-path
code the plan does not list: `gctk merge` with `merge.sh` and their tests (6,085
lines), `gctk lifecycle` with its machine package and tests (1,593),
`pr-stack.sh` with its test (1,127), `pr-summary-region.sh` (288, ported), and the
suites that extract the old patrol formula's blocks. The retirement bead adds
their rows. Rule 3's size line computes the net.

## 9. The problems held on this retirement

These are the open beads that wait on the initiative (`gc bd dep list
tk-1tfzr71.20 --direction=up`), less the members that follow it.

| Bead | The target flow | Because |
|---|---|---|
| tk-6bovoni: guards replay merges over a rewritten main | still carries it until the supersession check and the guard retire, with tk-1tfzr71.21 and .22 | Both halves sit in files whose rows move (section 8). Its edge moves onto both members. |
| tk-c8hl47c: a pre-open rework becomes a second anchor of its PR | removes it | No pre-open round exists. A rework child's hand-back writes its anchor's record and never gives the child a landing record of its own. |
| tk-cvffk5x: the architecture references omit the direct landing writer | removes it | This design's change to `architecture.md` states both landing paths and their writers, and unit 6 rewrites `component-model.md`'s. |
| tk-gwmqd0x: gctk's signal relay test races its trap | removes it | The test goes with `gctk lifecycle`. |
| tk-ni0i48p: the refinery's push forces over commits gained after the prep | removes it | Every push is a fast-forward. A push onto a PR's branch goes under a lease on the commit the writer read, never the remote-tracking ref, once the writer has checked that the new head descends from it. A push refused as non-fast-forward or by its lease is retried from a fresh prep, never forced. |
| tk-o9i6kp0: how an approval behaves across a rework | settles it in section 3 | Its validating closer checks the model against the note of 2026-11-05. |
| tk-pdc0ovc: a lane reads the PR body before the summary refresh | removes it | The refinery edits the body before it pushes the head that starts the lane. |
| tk-r82qrrv: the state-machine guide misnames the guard as a resolver caller | removes it | Unit 6 rewrites the Checks vocabulary in that page. |
| tk-tefrxph: a summary with its own collapsed section re-edits on every pass | removes it | Compose reads the region by its markers, and `pr-stack.sh` goes. |
| tk-w0hkwos: the refinery's rejection writes trust `WORK` | removes it | Each step's script takes the bead it acts for and refuses a bead whose branch is not the one checked out in the refinery's worktree. |
| tk-w888tez: a rework closed with nothing pushed reads needs-attention by ruling | still carries it | The rule lives in `prstatus`, which survives, and the rework child's close already records what it pushed (`gc.work_outcome`, `gc.work_commit`). Its hold can be released, to build the rule in `prstatus` on that record rather than on the bring-current keys. |
| tk-y8bcuip: a pre-existing mark with a closed tracker still passes | still carries it | `rig-check-pre-existing.sh` survives (section 8). Its hold can be released, to fix the mark's tracker check in place. |

The replacement carries none of the problems the initiative's notes fold in
under rule 1:
- The reconcile's re-reads of every anchor's children (tk-a2j63cs) go with the
  merge arm.
- The copied URL parsing between the two dismissal writers (tk-mlhs2ac): the one
  withdrawal writer goes through `gctk pr post`.
- The dropped-tail report's false findings (tk-pmmnt07) go with
  `merge-tail-report.sh`.
- The dismissal that drops unrouted comments (tk-uos4onx): the withdrawal lets
  the intake route them first.
- The login read from gh's stdout whatever its exit (2026-11-03 note): the
  withdrawal reads it through `pr-post.sh acting-login`.
- The stale rig HEAD in the dropped-tail finding (2026-11-06 note) goes with that
  report.

tk-1tfzr71.50, the deletion of `bd-lib.sh`'s checked create, waits on the last
callers of those helpers. After this member, they are in files that
tk-1tfzr71.21 and .22 retire, so its edge onto this initiative is joined by edges
onto those two.

## 10. The cutover

The effort lands for every rig at once. After it lands, and once the
review-lanes member has landed too, the new path reaches one rig at a time,
gc-toolkit first.

**What lands with the effort.** The new refinery formula runs on every rig. It
brings branches current by merge, requeues through `gc sling` and lands `direct`
work. On a rig whose switch is set, it publishes an `mr` bead's PR and writes the
pending record. The landing order runs on every rig and acts only on pending
records, so it does nothing on a rig still on the old path. On such a rig, the
`mr` step parks the bead at `pre_open_gate` as it does today, `pr-open.sh` opens
its PR, and `gctk merge` merges it under the pack's rule. `gctk merge` acts only
on `merge_result=pull_request`, so it never merges a PR on the new path.

**The switch.** A rig formula variable, `pending_through_merge`, says that the
rig is on the new path. Only the refinery's `mr` step reads it, and each patrol
wisp renders it when the wisp is poured. Every other reader tells the two paths
apart by the record's value.

**Each rig's cutover** is a bead the implementation child files on the default
branch, blocked by this initiative's landing and by tk-1tfzr71.22:
1. A sandbox PR in the rig's repository shows that the city's account can
   dismiss a review there, since a material change's withdrawal depends on it
   (section 3). Where it cannot, a human gate on the bead asks you to let it.
2. The mechanik sets `pending_through_merge` in the rig's config.
3. Once the refinery has poured a patrol wisp since step 2, the rig's open
   beads that own an open PR, or that wait at `pre_open_gate` for one, move onto
   the new path. The wisp running at step 2 rendered the switch unset, so it can
   still park its bead at `pre_open_gate` or record it at `pull_request`, and
   the wait lets the moves take that bead too. Each bead's PR is read on GitHub
   first, and the bead's old record is appended to its notes, so no history is
   lost:
   - A bead whose open PR still matches its number, repository, branch and base
     goes to `pull_request_head_changed`, open and assigned to the refinery,
     with `existing_pr` and the live head as `observed_pr_head_sha`. The
     refinery validates that head and records it pending, and triage runs there
     before anything merges, because no review result of the old path names a
     head. `pr-open.sh` adopts a PR open on a bead's branch whoever opened it,
     so an old-path bead can own a PR that another account opened. The
     refinery's `mr` step parks such a bead behind a gate instead (section 1).
   - A bead whose PR closed without merging, or whose PR no longer matches its
     record, takes the matching exception, behind a human gate.
   - A bead whose PR has merged is left to the old path's record of a merge made
     outside the city (`pr-facts.sh`), which closes it as landed, as today.
   - A bead parked at `pre_open_gate` has no assignee and no route, so the new
     find-work, which takes only a bead assigned to the refinery, never reaches
     it, while `pr-open.sh`, which lists open beads by that value alone, would
     still open its PR on the old path. So the bead moves to the refinery,
     unless a PR on its branch has merged. Such a bead stays parked, where
     `pr-open.sh` adopts the merged PR untouched and `pr-facts.sh` closes the
     bead as landed, as today. The move is one write. It takes the transition
     machine's edge from `pre_open_gate` to no record, expecting the bead still
     to read `pre_open_gate`, assigns the bead to the refinery with no route,
     as a polecat's hand-off does, and appends its old record to its notes:
     `lifecycle.sh transition <bead> --to unanchored --expect pre_open_gate --assignee <refinery> --append-notes <old record>`.
     The refinery is then woken and nudged, as after a hand-off. Its find-work
     takes the bead, and its `mr` step adopts the PR open on the bead's branch
     when the city's account opened it, or opens one as a draft when none is
     open, then writes the pending record. A PR open there that another
     account opened parks the bead behind a gate (section 1).
   - A closed bead keeps the value it closed with. `merged` stays the record of
     a landing the old path verified, and every reader takes it as landed.

   Which opener owns a parked bead, at each point of the cutover:
   - Until the refinery pours its first patrol wisp after step 2, it can park
     beads at `pre_open_gate`, and `pr-open.sh` opens their PRs, as today.
   - From that wisp until a bead moves, the refinery parks no new bead there,
     and `pr-open.sh` still owns each bead parked before. A bead it opens in
     that time carries `pull_request`, so the move, which expects
     `pre_open_gate`, refuses it, and the bead moves by the first bullet
     instead.
   - The moves run under the lock that the merge cadence's driver holds for
     each pass on the rig while its arms run (`bd-lib.sh`'s `take_pass_lock` on
     the driver's `pass.lock`), and `pr-open.sh` runs only as one of those arms.
     So no run of `pr-open.sh` is opening or recording a PR while a bead moves.
   - From its move, the bead is the refinery's. `pr-open.sh` lists only
     `pre_open_gate`, and its record of an opened PR expects that value, so it
     never lists the bead or records a PR on it again. A PR that an earlier run
     of `pr-open.sh` opened without recording it, because the run failed after
     `gh pr create` and left the bead parked, is the PR the `mr` step adopts,
     because `pr-open.sh` opens a PR through the city's account.
4. The mechanik watches the rig's first PRs through to their close.

**The old path finishes** once every rig's cutover bead has closed, since each
cutover moves its rig's open PRs onto the record. A retirement bead on the
default branch waits on every rig's cutover bead, and is armed to dispatch when
they close. Its drain check is that no open bead is on the old path: none
carries `pull_request` or `pre_open_gate`. It then deletes:
- `gctk merge`, `merge.sh`, their tests and the merge arm;
- `merge-tail-report.sh`;
- `pre-open-rebase.sh` and its arm;
- `pr-open.sh`'s create path;
- `gctk lifecycle` and the machine in `lifecycle.toml`. `lifecycle.sh` stays a
  plain write of the value, keeping the two side effects its callers rely on:
  the work record a landing writes, and the clear of the PR-finishing keys when
  a bead leaves the values of an open PR. Its row goes under tk-1tfzr71.21,
  whose `pr-facts.sh` is its last caller;
- `review-verdict.sh`'s gctk copy and the parity cases;
- the old `mr` branch of the refinery's step, and `pending_through_merge`
  itself;
- every reader's clause for `pull_request`;
- the old path's entry under Debt in `architecture.md`.

**What the units and the first cutover show.** The units' tests show each of
these, and the first rig's cutover shows them on its first PRs:
- A publication leaves the bead open on the record, `blocked` and assigned to
  the refinery with the head it validated, and nothing closes it before its
  merge is verified.
- A push the city did not make moves the record to
  `pull_request_head_changed`, and the refinery validates the new head on the
  same PR. The city's own push onto a branch that moved is refused, never
  forced.
- A push between the evaluator's answer and the merge request makes GitHub
  refuse the merge, and the next run requeues the record.
- A merge request left unanswered is decided again from where the PR stands on
  the next run.
- A merged PR closes the bead only once its merge commit is on the fetched
  target, and one not yet there is retried.
- A PR closed without merging, merged at a head the refinery did not validate,
  or merged into another base keeps the bead open behind its exception's gate.
- The evaluator reads not ready for each condition that is not met, and a
  review result for another head or target counts for nothing.
- An approval from the city's account counts like any other account's, and an
  approval from an account that cannot push to the repository counts for
  nothing.
- A material change holds the PR until GitHub shows the earlier approvals
  dismissed.
- A rework child handed back is taken before its anchor, and the merge request
  never waits on the close of the bead that owns the PR.
- A bead parked at `pre_open_gate` when its rig cuts over moves to the
  refinery in one write, `pr-open.sh` opens nothing for it after, and the
  refinery publishes it on the new path, on the PR already open on its branch
  when the city's account opened one, never on a second.
- A PR that another account opened on a work's branch is never taken. The
  `mr` step parks the bead behind a gate, leaves the PR as it is and opens no
  second PR, whether the step found the PR or an old-path record named it.
- Under load, each run reaches the records it checked least recently, and two
  runs that overlap, or a run and the refinery's record write, act on one
  record one after the other.
- A close that reaches a bead before its publication's record keeps the bead
  closed through every later run, and the record writes nothing.
- A release that takes a bead from the refinery after its record keeps the
  bead released through every later run, and no run that reads the release
  requests its PR's merge.

**Rule 2.** Every step of the rewritten formula calls one tested script and holds
no shell procedure. The suites that extract the old formula's blocks go in
unit 4, with the steps they extract, as the operator ruled for this rewrite
(2026-10-26).

## 11. The units

Each unit lands on `integration/tk-1tfzr71.20`, keeps the suite green and
leaves the city working.

| Unit | What it does | Waits on | Answers |
|---|---|---|---|
| 1. `gctk pr compose` and `gctk pr summary` | The PR's title, managed summary region and branch-beads section are composed in gctk from the bead that owns the PR, with the region read by its markers. `pr-summary-region.sh` is deleted, and `pr-open.sh` and `pr-stack.sh` call the verb. Go tests pin the output against today's renders. | nothing | tk-tefrxph; the gctk domain move note |
| 2. The evaluator | One function of gctk's pr domain answers whether a PR is ready for its current revision, with the head and the target it judged or the conditions not met. It reads the bead's own waits through `waits`, the open beads whose `anchor_bead` names it until their writers add the edge, `merge_hold` and `rebase_hold`, the review results for the live head and target, GitHub's live facts (open, not a draft, the record's identity and base, the validated head, merge state `CLEAN`, and the approval by section 2's eligibility, read from each review's `authorCanPushToRepository`), and the feedback receipts (the watermarks, counted by the intake's own rule, and the answered marks). `prstatus` renders it, and `gctk pr status` prints the conditions not met. It reads a PR's unanswered threads when it gathers the PR's facts, so the count's one writer can retire with `gctk merge`. Tests for each condition, among them an approval from the city's account, which counts like any other account's, an approval and a request for changes from an account that cannot push, an approval followed by a review that only comments, which still counts, a dismissed approval, a review result for another head and one for another base, a head other than the validated one, each merge state, a wait of the bead's own, an `anchor_bead` child, and feedback newer than a watermark beside feedback the intake's rule leaves out, which holds nothing. | nothing | sections 2 to 5 |
| 3. The record and the landing order | The store's record lock is built in gctk's pr domain, and both verbs take it (section 4). `gctk pr record` writes the pending record in Gas Town's two writes, holding the lock across both, reads the bead under it first, and guards each write on the status and assignee it read, so it writes nothing on a bead that is closed or no longer the refinery's. `bead-rehome.sh` takes the lock too, whatever the bead carries, reads the bead under it, and its close clears any `pr_reconcile_pending` it finds. `gctk pr reconcile` takes a bounded number of pending records, the least recently checked first, and reads each PR from GitHub by its number. An identity that no longer matches is `pull_request_reconcile_invalid`. An open PR at another head is requeued as `pull_request_head_changed`. An open PR at the validated head goes to the evaluator, and a ready one is merged with its head pinned, or added to the merge queue with it where the target requires one. A merged PR at the validated head whose merge commit is on the fetched target records `mr_merged` and closes. The other ends are the exceptions, each with its human gate, and a failed lookup or fetch is retried. A rig-scoped cooldown exec order, `pr-reconcile`, runs it. Each run handles each record under the lock, from its read of the record to its last write of it, waits for the lock while another holder has it, and acts only on a bead it reads there as carrying `pr_reconcile_pending` and, unless the bead is closed, still assigned to the refinery, with each write guarded as `gctk pr record`'s are. Tests follow `pr-merge-reconcile`'s cases at 7f86098c04ea, and add the pack's: a ready PR merged with its head pinned; a push between the answer and the request, which GitHub refuses and the next run requeues; a request left unanswered and read again; a merge queue that takes the PR and one that drops it; a PR merged into another base; a record write that waits while a run holds the lock and lands after the run's last write; a run that waits while a record write holds the lock and then reads the whole record, so it requeues nothing the refinery has just validated; a disposition's close of a bead that carries the marker, which waits while a run holds the lock, clears the marker, and stays closed through every later run; a disposition's close that lands before a publication prepared earlier takes the lock, after which the publication writes nothing, so the bead stays closed through every later run, with no marker and no record; a close, or a stand-down's release of the bead, that takes no lock and lands between the publication's read and its first write, which the guard refuses the same way; a disposition that starts before a publication marks the bead, which waits for the lock while the publication holds it, then closes the bead and clears its marker; a release that takes the bead from the refinery after its record, or while a run reads GitHub, after which a run clears the marker, names the PR in a note and writes nothing else, so the bead stays released through every later run; a run still going when the watchdog closes its tracking bead and the next cooldown starts a second run, which acts on the record the first holds only once the first has written it, and from what it wrote; a run stopped at its time limit, which leaves the lock free and its unread records to the next run; and the order of records across runs under load. | unit 2 | sections 4 and 6 |
| 4. The refinery on Gas Town's flow | `mol-refinery-patrol` is rewritten on Gas Town's steps at 7f86098c04ea, with the differences in section 1, and each step calls one tested script. The scripts cover: find-work, which skips a held bead or a branch another open bead works on, and takes a rework child before its anchor; the prep by merge in the refinery's own worktree (`refinery-workspace.sh` and its warrant go); the gate through `detached-job.sh`; the failures, through the requeue by `gc sling` or a rework child, and the pre-existing path; the direct landing; the `mr` step (compose the title and body; edit them onto a PR the bead already owns, or onto the PR open from its branch into its target, which it adopts when the bead records none, before it pushes the new head under the lease, or, when no PR is open, push and then open a new PR as a draft with them; take a PR, recorded or found, only when the city's account opened it, and park the bead behind a gate, with no edit, no push and no second PR, when another account opened it; record the PR with `opened_as_draft`, so the review lanes and `pr-open.sh`'s ready flip handle it unchanged; write the pending record with `gctk pr record`, and name the PR in a note on a bead whose record it refuses because the bead closed or left the refinery; and the old-path park while `pending_through_merge` is unset); the rework hand-back, which writes the anchor's record with `gctk pr record` and closes the child; and the integration-effort hand-off (tk-gmjtb2e), whose push takes the same lease. The refinery writes a pending record only through `gctk pr record`, so each of its record writes takes the store's record lock (section 4). The polecat's push at submit (`work-submit.sh`) and the witness's salvage push take the lease too. `rejection-repool.sh`, `pr-stack.sh` with its arm, `check-refinery-patrol-live` and the old formula's block-extraction suites go. The polecat doctrine gains the drift rule. The `mr` step's tests include a PR open on the branch that the city's account opened and never recorded, which it adopts; one that another account opened, which parks the bead and opens no second PR; an old-path record of a PR that another account opened, which parks the bead the same way; and a bead closed or released before its record, which keeps that state and gets the PR in a note. | units 1 and 3 | tk-c8hl47c, tk-ni0i48p, tk-pdc0ovc, tk-w0hkwos; section 7 |
| 5. The readers move | Every reader that takes `pull_request` as "owns an open PR" also reads `pull_request_pending` and `pull_request_head_changed` (section 6), among them `stand-down.sh`'s refusal of a bead with an open PR and `pr-facts.sh`'s feedback, conflict and posture arms, while `pr-facts.sh`'s arms that record a merge, a close without one or a moved base keep to `pull_request`. The sign-off's headline reads `prstatus`. I5 reads every closed bead with a PR, with `mr_merged` and `merged` as landed. I2 reads the kept values. `check-one-anchor-per-pr` counts the values of an open PR. | unit 4 | section 6 |
| 6. Docs, warrants and the plan | The pages that hold the merge's depth are rewritten to the flow as it stands once units 1 to 5 land: `refinery-merge-cadence.md`, `state-machine.md` (the record's values and their sentences, and the Checks vocabulary), `component-model.md` with both landing writers, `authority-map.md`, `design-convoy.md`'s gates, `gctk-architecture.md`'s rows and the merge section of `built-once-target.md`, which takes section 1's differences as that page holds the witness's. `architecture.md` states the target from this design's own change, with the old path under Debt. Unit 6 drops the Debt entry that units 1 to 5 retire, the refinery push that can force, and corrects any line a unit departed from. The warrants' Covers lines move off retired paths. The plan's rows move as section 8 says. | units 1 to 5 | tk-cvffk5x, with this design's change to `architecture.md`; tk-r82qrrv |

**What each waiting member needs.**

| Member | Needs | Because |
|---|---|---|
| tk-1tfzr71.22, review lanes | the evaluator's review input, the approval decision's ownership, and units 2 and 5 | Its loop runs triage at every new head, a requeued one included, and records each result with the head and the target it judged, which the evaluator reads, so every rig's cutover waits on it. Triage at each head owns the approval decision. A material change's withdrawal is work the loop owns: it blocks the bead that owns the PR, dismisses the earlier approvals and finishes only once GitHub shows them dismissed, behind a human gate when GitHub refuses. The loop's review and repair work blocks that bead through a `blocks` edge, never waits on it, and never names it as a workflow's source. Its checks are finite loops that finish with a result, and none of them waits for an approval or for CI. It takes over the bring-current guard and audit (section 8). A conflict on a branch with an open PR comes to it as a rework child until its loop has a repair step for it. |
| tk-1tfzr71.21, GitHub intake | sections 3 to 7, and units 2 and 3 | It reads an approving review's message as feedback, and resolves the city's own threads once answered. It moves feedback routing into the landing order's run, so the order stays the one path that admits work on a pending record, and files each piece of work with a `blocks` edge onto the bead that owns the PR. Once no writer files work without that edge, the evaluator's `anchor_bead` reading goes. It builds the join that a rig running Gas City's PR monitor with repair beads names as the monitor's `repair_workflow`, because the monitor routes each repair bead and pours that workflow on it as it files the bead. The join starts no writer: it ties each repair bead for a city PR to the bead that owns the PR, by the PR's repository and number, as work that blocks that bead, routes the repair through the landing order, and ties nothing of the monitor's `blocked` class, which the monitor marks actionable for every PR that GitHub reads BLOCKED, one waiting on your approval included (`classifyPullRequest`). It moves the PR-finishing rank and `prstatus`'s facts off the posture, replaces `pr-facts.sh`, and deletes the cadence driver and the files whose rows move to it. |
| tk-1tfzr71.23, convoys | the integration-effort hand-off's place in unit 4 | Moving efforts onto `gc convoy land` ends that difference. |
| tk-1tfzr71.25, META | the retirement bead's row list | The registry entries and parity tests of the retired machine go there. |

## 12. Edges and notes the implementation child adds

- The units are filed under the epic (tk-1tfzr71) with
  `target=integration/tk-1tfzr71.20` in each create. The landing bead
  (tk-1tfzr71.20) and the summary task (tk-1tfzr71.68) each wait on every unit
  through a `blocks` edge. Each unit waits on the units its row names and is
  armed to dispatch when they close.
- The cutover beads, one per rig, and the retirement bead are filed with
  `target` the default branch, outside the effort. Each cutover bead is blocked
  by tk-1tfzr71.20 and by tk-1tfzr71.22, and armed. The retirement bead is
  blocked by every cutover bead, and armed. Neither the landing bead nor the
  summary task waits on any of them.
- A bead that removes the evaluator's `anchor_bead` reading is filed with
  unit 2, blocked by tk-1tfzr71.21 and .22, and armed to dispatch when both
  close, since those members retire the last writers that file work on a PR's
  branch without a `blocks` edge.
- The held problems' edges move where this design puts them:
  - tk-6bovoni gains `blocks` edges onto tk-1tfzr71.21 and .22.
  - tk-w888tez and tk-y8bcuip are released from the hold. Each loses its edge
    onto the initiative and its validating closer's arm, and gains a note naming
    the surviving file its fix goes into, so each is ordinary work again.
  - tk-1tfzr71.50 gains edges onto tk-1tfzr71.21 and .22.
  - The others keep their edge onto the initiative. Where the fix lives in
    old-path code that the retirement bead deletes, their edge moves onto that
    bead.
- Each moved row gets a note on the bead that now retires it, saying why.
- Before filing, the child surveys the open branches against each unit's files
  again, since they move. At this design's reading, on 2026-11-11, two open PRs
  overlap. PR #1464 (tk-c9dcsbn) edits `docs/architecture.md`,
  `docs/built-once-target.md`, `gc-helm.sh` and the board's form, beside this
  design's own edits and unit 5's board reader. PR #1465 (tk-rymdhac) edits
  `docs/architecture.md`. tk-gmjtb2e (#1455), tk-icol3l8 (#1453) and the po
  effort (tk-rl8gz4b.28, #1445) have landed on main since this branch's base, so
  the effort brings them in when it brings its branch current, and units 4 and
  5 build on them.

## 13. Facts this design rests on

- **Gas Town's refinery** (`gastown/formulas/mol-refinery-patrol.toml` at
  7f86098c04ea), in `mr` mode:
  - Its find-work runs `gc gastown pr-merge-reconcile` once, then lists the
    beads assigned to the refinery, open or in progress, that carry a branch
    (`gc bd list --assignee=$GC_AGENT --status=open,in_progress
    --has-metadata-key=branch`), which reads no wait.
  - It pushes an existing PR's branch with a lease that names no commit
    (`git push origin HEAD:$BRANCH --force-with-lease`), opens a new PR with
    `gh pr create`, and records the hand-off with
    `gc gastown pr-merge-reconcile record`.
  - It runs no `gh pr merge`, so a person merges.
  - Its conflict and branch-failure paths write `gc.routed_to` to the polecat
    pool by hand, and the branch-failure path deletes the branch.
  - It files a pre-existing failure as a bug found by its title, and merges
    anyway.
  - It parks a bead whose target branch is missing, or whose `existing_pr` it
    cannot reuse, with `merge_result=blocked`, routes it to `human` and mails
    the mayor. It halts a branch that carries no real change as
    `refused_false_completion`.
  - Its refinery agent sets `max_active_sessions = 1`
    (`gastown/agents/refinery/agent.toml`).
- **Gas Town's pending-through-merge record**
  (`gastown/commands/pr-merge-reconcile/run.sh` at 7f86098c04ea). `record`
  writes `pr_reconcile_pending` and `existing_pr` on the open bead, then, in one
  write, the `blocked` status, `merge_result=pull_request_pending`, `pr_url`,
  `pr_number`, `pr_head_sha`, `pr_repo`, `pr_state=open`,
  `pr_last_checked_at`, `merged_target` and `blocked_reason`, assigned to the
  refinery. Each reconcile takes the one marked bead it checked least recently,
  open, blocked or closed, and reads its PR by URL with `gh pr view`. A PR whose
  URL, number, branch or base is not the record's is
  `pull_request_reconcile_invalid`. An open PR at another head goes back to the
  refinery, open, as `pull_request_head_changed` with `observed_pr_head_sha`,
  keeping `pr_head_sha`. A closed PR is `pull_request_closed_unmerged`, and a
  merge of another head is `pull_request_merged_unvalidated_head`. A merge
  commit that a fresh fetch of the target does not reach is retried. Otherwise
  it records `mr_merged`, `merged_sha`, `merged_target`, `pr_state=merged` and
  `pr_merged_at`, closes the bead, and keeps the marker until its artifact
  cleanup converges. Its exceptions block the bead and mail the mayor.
  `gastown/README.md` says that a blocked bead is not session demand, so the witness wakes
  the refinery when a pending check is due, and that an upgrade does not reopen
  beads that an older release closed at publication with
  `merge_result=pull_request`.
- **The gastown that Gas City main and gc 1.4.3 bundle** (0.1.13,
  66897e7132c9) closes an `mr` bead at publication with
  `merge_result=pull_request` and the reason "Pull request ready", and its
  `gastown/commands` holds only `status`. The packs registry lists no later
  release, and 66897e7132c9 is not an ancestor of the packs' main.
- **bd's `gh:pr` gate** (`checkGHPRWithRunner` in `cmd/bd/gate.go` at v1.3.4)
  resolves when `gh pr view` reports MERGED. On CLOSED it escalates through
  `gt escalate`, which the city does not have, and stays open. The design uses
  no such gate, because the record and the landing order carry the merge, as in
  Gas Town.
- **Gas City's PR monitor** (`gc github pr backfill`,
  `internal/githubmonitor`) lists open PRs only, 50 to a page, under one
  45-second limit for the whole scan (`newGitHubPRBackfillCmd`). It reads each
  PR's draft flag, its merge state and the first 100 check contexts of its last
  commit, and no review, review decision or comment. `classifyPullRequest`
  classes a PR draft, failed, conflicted, behind, blocked, pending, unknown or
  clean, and marks failed, conflicted, behind and blocked actionable.
  `--create-repair-beads` files a repair bead only for an actionable PR, keyed
  by its repository, number and head commit, routes it to the monitor's
  `repair_route`, which a monitor must name, and pours the monitor's
  `repair_workflow` on it, `mol-polecat-work` with the PR's head branch as
  `branch` when the monitor names none (`ensureGitHubPRRepairBead`,
  `RepairWorkflowOrDefault`). An open repair bead for the same head is refreshed
  instead, and its assignee nudged. Nothing in Gas City closes a repair bead or
  runs the monitor on a schedule, and the city's resolved config declares no
  monitor (`gc config show`, 2026-11-11). A monitor names its base branches
  exactly and can filter by author, and `--all` lifts neither filter.
- **Gas City's orders** (`cmd/gc/order_dispatch.go`, `internal/orders`). A
  cooldown counts from a run's start (`checkCooldown`). A run writes its
  tracking bead before it starts and closes it at its end, and the dispatcher
  starts no run while an order's tracking bead or the work it started is open.
  Every 30 seconds the controller's watchdog closes each open or in-progress
  tracking bead created two minutes earlier or more, chosen by its creation
  time alone, whether or not its run is still going
  (`orderTrackingSweepWatchdogStaleAfter`, `staleRuns`). `no_work_gate` skips
  those gates, and `idempotent` makes a gate that times out fail open; both are
  off by default. An exec order runs a command with no agent, in a process
  group of its own that Gas City stops at the order's time limit, 300 seconds
  by default (`TimeoutOrDefault`, `shellExecRunner`). An order that a webhook
  fires skips both gates (`memoryOrderDispatcher.Dispatch`), and the webhook
  intake drops a repeated delivery from an in-memory set for 30 minutes. The gc
  this city runs, 1.4.3 built at 36ad5186a2, carries fork commit 8a8feef354,
  which keeps a run's tracking bead until two minutes past the time limit the
  run was launched with. Upstream main 6bd609f5bfb4 does not carry it.
- **Gas City's workflows, convoys and claims.** Finalize closes the
  `gc.source_bead_id` chain only on a pass (`processWorkflowFinalize`). A
  formula check (`[steps.check]`) retries up to its `max_attempts`, which main
  also lets a formula variable set and 862ee37e4570 does not. Convoy progress
  counts closed members and reads no PR (`ConvoyProgress`). No Gas City code
  merges a PR or reads a review decision. A claim changes only the bead, and
  nothing in Gas City locks a branch.
- **No Gas City or Gas Town primitive gates a merge on approval or on a bead's
  waits.** gstack's land-and-deploy skill tells an agent to run `gh pr merge`,
  with `--auto` or `--squash`, and after any failed exit to read the PR's state
  rather than run the merge again. pr-review's `mol-pr-merge-only` has a polecat
  squash-merge with no review step.
- **GitHub's reviews and merges.** A review records whether its author can push
  to the repository (`authorCanPushToRepository`). `mergePullRequest` takes
  `expectedHeadOid`, "OID that the pull request head ref must match to allow
  merge", and `enqueuePullRequest` takes an `expectedHeadOid` too. A PR reports
  `isInMergeQueue`, `autoMergeRequest` and `mergeStateStatus` (the GraphQL
  schema, read on 2026-11-11). gh's manual says that on a target that requires
  a merge queue, `gh pr merge` adds the PR once its required checks have passed
  and turns on auto-merge when they have not, and that `--match-head-commit`
  names the commit the head must match (gh 2.103.3). GitHub counts toward a
  required review only the approvals of accounts with write access, a PR's
  author cannot approve it, and a review that requests changes from an account
  with write access holds the merge until its author approves or someone with
  write access dismisses it. GitHub terminates a request that it takes more than
  ten seconds to process, reserves the right to change that window, and does not
  say whether a terminated request took effect
  ([Troubleshooting the REST
  API](https://docs.github.com/en/rest/using-the-rest-api/troubleshooting-the-rest-api)).
- **gc-toolkit on GitHub, read on 2026-11-11.** The default branch's rules
  require one approving review, resolved threads, the `test` and `test-macos`
  checks, squash merges, signed commits and a linear history, with no merge
  queue. An integration branch requires signed commits only. Auto-merge is not
  allowed, and the city's account can push but is neither an admin nor a
  maintainer. The city's account opened every PR among the 40 most recently
  merged, and the operator's account approved them.
- **git's push** ([gitprotocol-pack](https://git-scm.com/docs/gitprotocol-pack)):
  the client sends, for each ref, the commit it read there on the server and
  the commit it wants there. The server receives the pack, checks that each ref
  still holds the commit the client read, updates the refs, and then reports
  `ok` or `ng` for each. The client refuses an update that is not a
  fast-forward unless it is forced ([git-push](https://git-scm.com/docs/git-push)).
  The client reads the refs when it pushes, so the commit it sends as the one it
  read is the one it finds then. git's lease, `--force-with-lease=<ref>:<expect>`,
  the one form of it that git's documentation does not call experimental, makes
  the client send the update only when the ref's current value is `<expect>`,
  and fail otherwise, and a lease that matches overrides the rule that an update
  must be a fast-forward. On scratch repositories with git 2.56.0, on
  2026-11-10: with a branch moved from C to D, a plain push of N, which descends
  from both, sent D as the commit it read and landed, and a push of N under the
  lease on C was refused as stale and sent nothing. A lease that matched landed
  a new head that did not descend from it as a forced update, and one that did
  as a plain fast-forward.
