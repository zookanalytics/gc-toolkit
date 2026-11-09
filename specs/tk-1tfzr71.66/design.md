---
name: Design — land through Gas Town's refinery flow, with GitHub's branch rules deciding approval and required checks
description: The design for tk-1tfzr71.66, the design child of initiative tk-1tfzr71.20, read at main 7ed46e378 against Gas City upstream main 862ee37e4570, gascity-packs main 3339ad104a88, bd v1.3.4 and gc-toolkit's GitHub rules as they stood on 2026-11-09. It sets the PR pipeline's target model for the merge, review-lanes and GitHub-intake members, says how the pack's refinery takes Gas Town's flow and where it still differs, answers the brief's questions and each problem held on this retirement, and defines the units the implementation child files and the cutover after them. Read it to approve the design at its gate, or to build one of its units.
---

# Design: land through Gas Town's refinery flow under GitHub's branch rules

This is the design record for tk-1tfzr71.66, the design child of the
initiative tk-1tfzr71.20. The pack was read at main 7ed46e378, the commit
`integration/tk-1tfzr71.20` was cut from. Gas City is cited by symbol at
`gastownhall/gascity` main 862ee37e4570. Gas Town is cited by path at
`gastownhall/gascity-packs` main 3339ad104a88, and at 66897e7132c9, the gastown
release that the city's gc 1.4.3 bundles (`PublicGastownPackVersion`). bd is
cited at `gastownhall/beads` v1.3.4 (7ef2fd05eb0c), the build the city runs.
GitHub's behavior is cited by its documentation page, and gc-toolkit's rules and
settings were read live on 2026-11-09 at about 19:10Z. The search behind the
surface the units add is [gas-city-search.md](gas-city-search.md).

## What the operator approves

Today the pack merges every PR itself, under its own approval rule, once a merge
pass finds the review lanes green. Approving this design moves the merge onto
GitHub. The refinery takes Gas Town's flow and opens each PR as a draft as soon
as the work reaches it. The city posts its verdict on every head commit as a
status that GitHub requires on the default branch and on every integration
branch, so a PR the city opens waits for that verdict whoever presses Merge.
That status passes last, once the city holds nothing on the PR, everything else
GitHub requires is in place and the city has read every review and comment, and
GitHub's auto-merge then lands the PR. A status belongs to the commit, so before
the city pushes a PR onto a commit whose status already passes, it marks that
commit pending, and the PR waits for a verdict that counts it. Where the branch
requires an approval, a review that requests changes holds the merge from the
moment you submit it. A comment or an approval's message that lands in the
moments between the city's last read and the merge is read only once the PR has
merged. A push made outside the city's own steps, such as yours, onto a commit
whose status already passes can let the PR merge on a verdict that did not count
it. Your approval carries across reworks, and only the city's reading of a
change withdraws it. The new flow reaches every rig when the effort lands, and
the merge moves onto GitHub one rig at a time, after you set that rig's rules
and a sandbox PR shows they hold.

Three calls carry a cost either way:

1. **Who decides that a PR has its approval.**
   - (a) GitHub, wherever the target branch's rules require an approving review,
     as gc-toolkit's default branch does. A PR into a branch with no such rule
     waits for you to merge it, as in Gas Town's flow, and the city's status
     holds your Merge until it passes. That includes every stage PR into an
     integration branch, this design's own among them, so a design gate becomes
     your Merge instead of your Approve. The pack's approval rule is deleted.
   - (b) As (a), plus an approval that the integration branches' rules
     require, so a stage PR merges on your Approve. The city's account turns
     auto-merge on and also holds the bypass its landings need on those
     branches, so a sandbox PR has to show that auto-merge still waits for your
     approval and for the city's status, which GitHub's documentation does not
     say.
   - (c) The pack, as the ruling of 2026-10-02 has it. The city lets GitHub
     merge only once it reads a standing approval from another account, on
     every branch, with no approval rule to set up. The pack keeps its reading
     of the reviews under a warrant. The city turns auto-merge on for a stage
     PR too, so (c) needs the same sandbox proof as (b).
2. **The seed audit.**
   - (a) Re-render after landing, and hold no PR for it. Until the re-render
     lands, the next PR's diff can show render lines it did not change.
   - (b) A CI check your ruleset requires. A PR that changes prompt inputs then
     needs bringing current whenever the default branch moved its renders, and
     a render can still go stale after the check passed, because a branch need
     not be current to merge.
3. **A merge hold for a deleted script that open runs still call.**
   - (a) No hold. Each deletion bead keeps its drain check, and a run that
     reaches a deleted script declines with a gate. A missed check costs what it
     did the one time it happened, on 2026-10-27: one run poured again.
   - (b) A hold before any PR into the default branch merges. It needs a reader
     of every store's open steps, which is what the retired PR (tk-57wjk4l)
     built.

Approving as it stands ships the first option of each. Either way, each rig's
cutover asks you, through a gate, to allow auto-merge, to require
`gc-toolkit/status` on the default branch, beside the CI checks, and on every
integration branch, to let the city's account alone bypass the integration
branches' rules, and to let the city's account dismiss reviews. The bypass is
there because the city lands work on an integration branch by pushing, and
GitHub refuses a push to a branch whose required status has not passed at the
pushed commit (section 10). Until the GitHub-intake member lands, a PR lands
within one pass of the last thing it waits for, most often your approval or its
CI checks, as it does today. Until then, as today, the city routes nothing an
approval's own message asks for. Some of the deletion plan's rows move to the
members whose code still calls their files (section 8). Section 11 lists the
five units the implementation child files, and section 10 the cutover beads and
the retirement bead that land after the effort does.

## 1. The target flow, and how the pack takes Gas Town's

### The flow

1. A polecat hands its bead to the rig's refinery, as it does today. When its
   branch heads an open PR, as a rework's does, its push publishes that PR's
   new head (section 4).
2. The refinery takes one bead assigned to it that nothing holds, by the
   answer of `gctk bead holds`, and brings its branch current by merging the
   target in.
3. It runs the rig's gate.
4. A failure the branch caused sends the work back to the polecat pool. A
   failure that is already on the target is tracked, and the landing goes
   ahead.
5. A `direct` bead lands by a fast-forward push, and the refinery closes it. On
   an integration branch, whose rules require the city's status, the push goes
   through a bypass that only the city's account holds (section 10). When the
   branch heads an open PR, the push publishes that PR's new head (section 4).
6. For an `mr` bead, the refinery composes the PR's title and body with
   `gctk pr compose`. When the bead already owns a PR, the refinery edits that
   PR's title and body first and then publishes the new head (section 4), so a
   review that the push starts reads the current body. When the bead has no PR
   yet, the
   refinery pushes the branch and then opens the PR as a draft with that title
   and body. It files a `gh:pr` gate on the bead, so the bead waits on its own
   PR's merge, and it runs the PR's projection. It opens or updates a PR only
   into a target whose rules require the city's status, and files a human gate
   on the bead for any other target (section 10).
7. The review lanes run on the draft, and the PR turns ready when the lanes
   before that phase pass.
8. The projection posts the city's verdict at the PR's head as the
   `gc-toolkit/status` commit status, one verdict for every open PR at that
   commit. The status passes last. It reads success only once the city holds
   nothing on the PR, every other requirement of the target is met there and
   the city has routed every review and comment (section 4). While the city
   reads the PR approved, the
   projection also keeps GitHub's auto-merge on, where the target's rules
   require an approving review.
9. GitHub merges when its rules allow: the approval, the CI checks, the city's
   status and, where the repository requires it, resolved threads.
10. Core's gate sweep resolves the `gh:pr` gate once the PR has merged, and the
    bead is ready again. The refinery checks that the merge commit is on the
    target, records the landing and closes the bead.

### What the pack keeps of its own

The city imports no gastown pack, and the gastown that gc 1.4.3 bundles closes
an `mr` bead as soon as its PR is published (`gastown/formulas/mol-refinery-patrol.toml`
at 66897e7132c9, merge-push). So the pack keeps its own refinery formula and
models it step for step on Gas Town's at 3339ad104a88, as its witness is modeled
on Gas Town's witness ([built-once-target.md](../../docs/built-once-target.md#patrol)).
The steps are validate-identity, check-inbox, find-work, rebase, run-tests,
handle-failures, merge-push, patrol-summary and next-iteration. Gas Town's
ancestry check, which skips the prep when the target is already in the branch,
and its park when the target branch is missing, come with them. Each step calls
one tested script ([rule 2](../../docs/built-once-target.md#the-rules)).

Each remaining difference names its reason and what ends it:

| Difference | Reason | Ends when |
|---|---|---|
| The branch is brought current by merging the target in, and every push is a fast-forward. Gas Town rebases, and in `mr` it force-pushes with a lease. | A PR under review keeps the commits its approval and its threads were given on. A fast-forward cannot overwrite a commit the branch gained after its prep, which the lease against a shared remote-tracking ref did (tk-ni0i48p). | No end is planned. This is a measured reason to differ. |
| A bead with no PR yet goes back to the pool through `gc sling` on `mol-polecat-work`, with its branch kept. Work on a branch whose PR is open comes back as the PR's rework child, so the bead keeps its PR and its merge gate. Gas Town writes the pool route by hand, and after a failure the branch caused it deletes the branch. | Dispatch goes only through `gc sling` (the dispatch design, `specs/tk-1tfzr71.54/design.md` on `integration/tk-1tfzr71.15`). Deleting a PR's branch closes the PR, and a bead waiting on its merge gate is not workable. | Gas Town requeues through `gc sling` and keeps the PR of a bead it sends back. |
| A failure already on the target is tracked by `preexisting-failure.sh`, keyed by its symptom. Gas Town searches open bugs by title. | Two agents title one failure two ways. The key finds the tracker after a retitle, and the work formula's pre-flight files through the same script. | Gas Town keys its tracker. |
| Where a person must act, the refinery files a human gate on the bead. Gas Town parks the bead on the `human` route and mails the mayor. | A person's wait is a human gate on the bead it blocks (the dispatch design). The seat that tk-rl8gz4b.28 adds in the mayor's place, the po, owns only what a ruling gives it, and that effort's design keeps the same difference for the witness. | An operator ruling gives the po escalation handling. |
| The PR opens as a draft, and the city posts its status on every head. Gas Town opens it ready and posts nothing. | The city's checks run on the PR before it asks you, and the merge waits for the city's verdict at each head (section 4). | No end is planned. |
| The projection turns GitHub's auto-merge on where the target requires an approval. Gas Town never merges. | You approve rather than merge, and an approved PR merges on its own, as it does today. | No end is planned. |
| The bead waits for its merge on a `gh:pr` gate, and the refinery's close step makes the merged checks of `pr-merge-reconcile`. Gas Town main runs `gc gastown pr-merge-reconcile` at each find-work. | That command is not in the gastown that gc bundles, and the city imports none. | The city takes a gastown release that carries it, or Gas City ships a close on a PR's merge. |
| An already-merged branch records `merged`, at the target commit that holds it. Gas Town records `already_merged`. | Every reader that asks whether the work landed asks one value (section 6). | No end is planned. |
| The gate runs through `detached-job.sh`. Gas Town runs each command inline. | A tool call is cut off at ten minutes, and a rig's gate can run longer. | The gate runs where no tool call bounds it, as a formula check script or an order. |
| The refinery takes the hand-off that brings an integration effort's branch current, with plain git (tk-gmjtb2e). Gas Town has no integration efforts. | An effort's branch reaches the default branch through one PR. | The convoys member (tk-1tfzr71.23) moves efforts onto `gc convoy land`. |
| One worker per branch. A conflict on a branch whose rework child is open goes to that child. Gas Town has no rework children. | Review feedback is fixed by rework children until the review-lanes member moves that work into its loop. | tk-1tfzr71.22 lands. |

## 2. Where the approval rule lives

**Today.** The operator's ruling of 2026-10-02, recorded on tk-7h5l3m from
sitting tk-kwmyg3, makes approval a universal merge rule in the city's merge
logic. Every PR needs an APPROVED review from an account other than the city's,
and "GitHub branch protection remains an extra enforcement layer only, not the
mechanism". `gctk merge` applies the rule (`reviewVerdict` in
`services/gctk/internal/cli/merge.go`): each account's latest review counts, a
standing CHANGES_REQUESTED vetoes, and no approval given at or before
`bring_current_lifted_at` counts. `review-verdict.sh` holds a second copy, which
`pr-facts.sh`, `approval-withdraw.sh`, `bring-current-guard.sh` and
`converse-signoff.sh` source, and the verdict cases in `merge.test.sh` hold the
two equal.

**GitHub, as read on 2026-11-09.** The Default Branch ruleset covers the default
branch alone. It requires one approving review, resolved review threads and the
`test` and `test-macos` checks from GitHub Actions, allows squash merges only,
and does not require a branch to be current. It neither dismisses stale reviews
nor requires the last push to be approved. Every branch carries the Signed
Commits ruleset, and an integration branch carries nothing else. Auto-merge is
not allowed in the repository's settings, and the city's account has write
access, not admin. A PR's author cannot approve their own PR, and only
approvals from accounts with write access count ([Approving a pull request with
required reviews](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/approving-a-pull-request-with-required-reviews)).
The city's account opens every PR, so on a branch that requires an approval,
GitHub already requires one from another account.

**The design.** The projection turns auto-merge on only for a bead on the new
path, which carries its merge gate (section 10), and only while the city reads
the PR approved and the target branch's rules require an approving review. It
reads those rules from GitHub (`GET /repos/{owner}/{repo}/rules/branches/{branch}`),
and never edits them. Under every option of call 1, the city's status holds a
stage PR, because each rig's cutover makes the integration branches' rules
require it, as the default branch's do (section 10). Call 1 sets what else holds
a stage PR once the pack's rule retires:

- Under (a), only a person merges a PR into a branch with no approval rule, and
  the city's status holds that Merge until it passes. `prstatus` reads such a
  PR `needs-review`, with the reason "waiting for your merge" once the lanes
  pass, so the label, the board and the sign-off ask for the merge, not an
  approval. A rig whose default branch requires no approval has its PRs wait
  for a merge in the same way, until its cutover sets the rule.
- Under (b), the integration ruleset also holds a stage PR for the approval,
  and the projection turns auto-merge on for it as it does on the default
  branch.
- Under (c), the projection reads the pack's own verdict on the reviews instead
  of GitHub's rule, on every branch, so it turns auto-merge on for a stage PR
  once that verdict reads approved. `review-verdict.sh` stays as that reading
  under a warrant, and its gctk copy and the parity cases go.

Under (b) and (c), the account that turns auto-merge on for a stage PR is the
city's, which also holds the bypass of the integration branches' rules. GitHub's
documentation does not say whether auto-merge still waits for a ruleset's rules
when the account that turned it on may bypass them, so the cutover's sandbox
shows it (section 10). Under (a), the city never turns auto-merge on for a
stage PR, and the person who merges one holds no bypass.

Under (a) and (b), `reviewVerdict` and the approval gate go with `gctk merge`.
`review-verdict.sh` and the lift line go once their last readers move: the
sign-off in unit 4, `bring-current-guard.sh` and `approval-withdraw.sh` with
tk-1tfzr71.22, and `pr-facts.sh`'s posture with tk-1tfzr71.21.

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
such as a conflict that was resolved with decisions of substance, the one
withdrawal writer does three things. It dismisses every approval given before
that head, with the city's mark in the dismissal's message, the mark
`gctk pr post` owns. It asks for your review again. And it runs the projection,
which turns auto-merge off, because the city no longer reads the PR approved.
Before
it dismisses, the writer lets the intake route the review's own comments, since
a dismissal retires them (the lesson of tk-uos4onx). Nothing else withdraws an
approval, and nothing reads an approval's age: no gate asks for a fresh review
because an approval predates the head, which is the parallel gate the finding of
2026-11-09 records.

**Until tk-1tfzr71.22 lands,** the two writers that withdraw an approval today
stay as they are. One is the ruling on a conflicted bring-current round, which
`bring-current-guard.sh` carries out. The other is the validator's ruling that a
fresh whole-diff review is due, which `approval-withdraw.sh` carries out. Their
lift line still counts through the posture `pr-facts.sh` records. So a dismissal
GitHub refuses still keeps the city from reading the PR approved, and auto-merge
stays off.

**The three cases of 2026-11-05.** You ruled them low priority, to follow the
rewrite ("Yes, this is low priority and should follow the rewrite",
2026-11-05T22:38Z). The model settles each, and the validating closer armed on
tk-o9i6kp0 checks it against that note once the initiative lands.

1. **A fix asked for in an APPROVED review's own message.** No GitHub rule reads
   a review's message. The intake (tk-1tfzr71.21) reads an approving review's
   message as feedback, like any other review's, so a fix it asks for becomes
   fix work on the PR's bead. That work is in flight, so the city's status reads
   pending and the merge waits for it. The approval stands across the fix's
   push unless triage withdraws it. This is a residual under the warrant this
   design adds (section 8).
2. **An approval submitted between the comment read and the merge.** An
   approval that turns auto-merge on is read first. Auto-merge is on only while
   the city reads the PR approved, and the city reads it approved only after it
   has read the reviews, the approving one included. A review that arrives once
   auto-merge is on is a different case. GitHub turns auto-merge off only when
   someone without write access pushes or the base branch changes, and a review
   moves neither the head nor the status the city posted there ([Automatically
   merging a pull request](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/automatically-merging-a-pull-request)).
   So the city's status passes last (section 4). It reads success only once
   every other requirement is met at the head and the city has routed every
   review and comment the PR carries. A review that arrives while a required
   check still runs, or while a thread the base requires resolved is still
   open, is read before that success, and a fix it asks for keeps the status
   pending. An approving review's message is among them once the intake reads
   it as feedback (case 1). Until tk-1tfzr71.21 lands, the intake's rule leaves
   that message out, as it does today, so a fix asked for there merges unread.

   This narrows the case and does not close it. GitHub merges once the city's
   success posts, so a review or comment submitted between the city's last read
   and that merge goes in unread. Today's merge leaves a window of the same
   kind, between its read of the reviews and its `gh pr merge`
   (`services/gctk/internal/cli/merge.go`). On a branch whose rules require a
   review, a review that requests changes from an account with write access
   holds the merge from the moment it is submitted, until its author approves
   or someone with write access dismisses it ([Approving a pull request with
   required reviews](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/approving-a-pull-request-with-required-reviews)).
   So what stays open is the message of an approving or commenting review, a
   request for changes from an account without write access, and a plain
   comment. The warrant this design adds names that window as a residual it
   leaves open (section 8), and the validating closer on tk-o9i6kp0 reads it
   against the note.
3. **The threads the city leaves open.** Wherever the repository requires
   resolved threads, each open thread holds its PR. The rule for the city's
   write-back (tk-1tfzr71.21): the city resolves the thread of its own post once
   it has answered it, a declined or deferred machine finding included, with
   the answer in the thread. A person's thread stays open until the person
   resolves it, or until the city lands the fix it asked for and resolves it
   naming the commit. So a person's open thread holds the merge, which is the
   setting you chose. On a base that does not require resolved threads, a
   thread that still waits on the city's answer reads `held: review` in
   `prstatus`, and the city's status reads pending on it. There the merge waits
   for the city's answer rather than for the thread's resolution, and the merge
   and the label agree, which today they do not.

## 4. Where triage sits for each change

**The placement is the city's status on each head commit, which the rules of
every branch the city opens a PR into require: the default branch and each
integration branch (section 10).** GitHub requires a check to pass on the PR's
latest commit, and a check from an earlier commit does not count
([Troubleshooting required status
checks](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks)).
A status belongs to the commit, though, not to the PR. A push onto a commit that
carries no status of the city's leaves the PR without the city's verdict until
the city posts one there, but a PR that moves onto a commit the city has already
judged arrives with that verdict. So every push the pack makes onto a PR's
branch publishes the head behind a pending status (below). Nothing merges a head
before the city posts there a verdict that counts the PR, whoever presses Merge,
unless a push that does not go through the publication, such as a person's,
moves the PR onto a commit that already reads success. A review that gates only
the PR's opening would leave a later push unjudged, as the 2026-10-23
requirement says.

**What the status reads.** It reads success at a head only when all of these
hold for each open PR at that commit that a bead owns:
- The city has nothing in flight on the PR and nothing holding it.
- No feedback on the PR is newer than what the city has routed. The record of
  what it has routed is the anchor's watermarks, `pr_review_watermark`,
  `pr_comment_watermark` and `pr_issue_comment_watermark`, each the highest id
  routed in its own id space (the `[posture]` table of
  `lifecycle/lifecycle.toml`). The projection is the reader that compares it.
  At each post it reads the PR's feedback fresh and asks the intake's own
  question of it: whether feedback in any id space sits above that space's
  watermark. Today that question is `pr-facts.sh`'s watermark compare, which
  counts a review's message only for a commenting review or one that requests
  changes, and leaves out what the anchor's answered marks show the threads
  have answered. A wider count would find feedback the intake never routes,
  and the status would stay pending with nothing left to route. tk-1tfzr71.21
  adds an approving review's message to the intake's count (section 3, case 1).
- Every other requirement of the PR's target that can still change at that head
  is met: the approving review the target requires, which the city has read
  (under call 1(c), the pack's own verdict on the reviews, on every branch),
  the other required checks, and resolved threads where the target requires
  them.

Otherwise it reads pending, with what it waits on in the status description. It
never reads failure, because every reader that acts on a red check would take
the city's own hold for one: `pr-facts.sh`'s red-check arm today, and Gas City's
PR monitor, which classes a PR with a failing check as `checks_failed`
(`classifyPullRequest` in `internal/githubmonitor/monitor.go`). A commit status
from the city's own token satisfies a required check whose `integration_id` is
left unset ([Repository rules](https://docs.github.com/en/rest/repos/rules)).

**Why it passes last.** GitHub merges once every requirement passes, and a
review that arrives after auto-merge is on leaves auto-merge on (section 3). A
status that read success while a required check still ran would let such a
review merge unread when the check finished. Posted last, the status makes
GitHub's merge follow the city's read of the PR. The projection turns auto-merge
on while its own status still reads pending, because GitHub shows auto-merge
only on a PR that cannot merge at once ([Automatically merging a pull
request](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/automatically-merging-a-pull-request)),
and then posts success. What changes between that read and GitHub's merge is not
in the verdict, which is the window section 3 names.

**One verdict for every PR at a commit.** A commit status belongs to the
repository and the commit, not to a PR. GitHub reflects it in every pull
request involving that commit, and the latest status in each context is the one
that counts ([Commit statuses](https://docs.github.com/en/rest/commits/statuses)).
Two open PRs can share a head, such as one branch with PRs into two bases, or two
branches at one commit. The refinery's prep can make such a pair. Merging the
target into a branch whose commits the target already holds fast-forwards the
branch to the target's head. When the target has an open PR of its own, such as
an integration branch's landing PR, the two PRs then share that head, and the
branch's own PR has nothing left to merge. In this repository one pair of PRs
has ever shared a final head, a stacked pair in May, and no open PR shares one
(a census of all 1,454 PRs on 2026-11-09). A status written per PR would let the
clear PR's success replace the held PR's pending, and the held PR would merge
over its hold.

So the projection posts the verdict of the commit. Before each post it reads,
fresh from GitHub, the repository's open pull requests
(`GET /repos/{owner}/{repo}/pulls?state=open`, every page) and its branch refs,
and keeps the PRs at that commit. A PR whose head branch is in the repository is
at the commit its branch's ref reads, because the push itself moves the ref, and
the projection that follows a push does not depend on when GitHub moves the PR's
recorded head (`head.sha`). A PR from a fork is at its `head.sha`. That list
includes a PR into another base, a PR from a fork and a PR that no bead owns.
GitHub's list of the pull requests associated with a commit
(`GET /repos/{owner}/{repo}/commits/{commit_sha}/pulls`) cannot stand in for it.
For a commit on the default branch it returns only the merged pull request that
introduced the commit
([Commits](https://docs.github.com/en/rest/commits/commits)), and it returned
none for the heads of two open PRs from forks (section 13). The projection posts
success only when each PR a bead owns reads success by the rule above, against
its own target's rules. Otherwise it posts pending, and the description names
the PR that holds the commit. A PR that no bead owns holds nothing of the
city's, so a PR that someone else opens at the city's head cannot hold the
city's merge. A clear PR waits while another PR at its head is held, and the
description says which one.

GitHub's status API has no compare-and-set. The latest post in a context wins,
so a post computed from an older read could replace one computed from a newer
read. The refinery's `mr` step, the label writer, the withdrawal writer and each
publication of a head (below) run the projection, so the projection serializes
each repository's posts. It holds one `flock` file per repository, under the
city's `.gc/runtime/packs/gc-toolkit`, where Accept's lock is kept. It takes the
lock before it reads anything the verdict rests on, the open PRs at the commit
and each one's holds, feedback and requirements, and keeps it until its post. A
publication holds the same lock from its first read through the projection after
its push, and the posts it makes run under that hold rather than waiting for the
lock again. A writer that finds the lock held waits for it and does not skip its
post, because the post it would skip can be the one that carries a new hold. The
last post at a commit then comes from the latest read, and what remains is the
window section 3 names. The projection posts only when the state or the
description changes, because GitHub keeps at most 1000 statuses per commit and
context.

The intake routes outside that lock. It moves a watermark past a batch only
once the batch's routing reads back (the `[posture]` table), so the hold the
routing makes exists first. The projection therefore reads the watermarks
before the holds, and a watermark it reads as moved comes with the hold it
routed to.

**A head is published behind a pending status.** A PR that moves onto a commit
where the city's status already reads success, posted there for another PR or
for an earlier state of this one, arrives with that success. An approved PR
keeps its approval and its auto-merge across a push from an account with write
access (section 3), so GitHub could merge it on a verdict that did not count it,
before any projection runs. The case needs a commit that carries work the PR's
target lacks, such as another PR's head that a stacked branch moves onto,
because a fast-forward onto the target's own head leaves the PR nothing to
merge. So every writer the pack runs that pushes a branch first reads, under the
projection's lock for the repository, the open PRs whose head is that branch.
When there are any, it publishes the new head in this order, holding the lock
throughout:

1. It reads the city's status at the commit the push will make their head.
   When this read or the read of the open PRs fails, it pushes nothing, and
   retries as it does after a refused push.
2. When that status reads success, the projection posts pending there, naming
   the PRs the push moves.
3. It pushes.
4. It runs the projection at that commit, whether the push landed or not, so a
   pending posted for a push that failed holds no other PR.

No other post of the city's lands between the read and the push, because every
projection waits for the lock. For a commit the repository does not hold, GitHub
answers the status read with no statuses, as it does for a held commit with none
(section 13). So a new commit reads as carrying no verdict, and GitHub merges no
PR at it until the city posts there. A PR's first head needs no publication. The
`mr` step opens the PR as a draft, which GitHub does not merge, and runs the
projection before anything can mark it ready.

The writers are the polecat's push at submit (`work-submit.sh`), which is how a
rework moves its PR's head, the refinery's pushes (the `mr` step's push of a
PR's new head, a `direct` landing onto a branch that heads an open PR, and an
effort's bring-current), and the witness's salvage push. None of GitHub's rules
for a branch refuses a push onto a commit whose status passes
([Available rules for rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets)),
and a status belongs to the commit, so none can be scoped to a PR. GitHub's
setting that would hold the merge after any push, `require_last_push_approval`,
asks for a fresh approval after every push, which section 3 keeps off. So a push
that does not go through the publication, such as a person's, can still move a
PR onto a commit that reads success, and the warrant names it as a residual
(section 8).

**The review input is the review verdict at the head.** The loop tk-1tfzr71.22
builds runs triage on each new head. Triage reads the change itself (the ruling
of 2026-10-23) and either adds no checks, so the status turns success once
nothing else holds the PR, or reopens the checks the change needs. Until that
member lands, today's lanes feed the status, and a lane's green survives a push
([state-machine.md](../../docs/state-machine.md#checks)). So until then, a push
after the lanes are green can merge with no triage. That is the gap tk-2w1w33v
holds on tk-1tfzr71.22.

**The draft.** The PR leaves draft when the lanes before the ready-for-review
phase pass. `pr-open.sh`'s flip does that today, and the loop does it once
tk-1tfzr71.22 lands.

## 5. What holds a merge

The merge asks one definition of what holds a PR and one of a bead's waits, and
computes no wait of its own. The projection posts what `prstatus` derives. For
the anchor's waits, `prstatus` takes the answer of the `waits` package, which
`gctk bead holds` gives from shell
([its contract](../../docs/gctk-architecture.md#the-bead-holds-contract)). A
bead with an open PR is in flight, so only its own waits hold it, and an edge
into another store holds nothing. Any wait that holds the anchor, other than its
own merge gate, keeps the city's status pending. `prstatus`'s walk of `blocks`
edges keeps the job it has today, which is to name the gate or the bead a person
owes the next move on, for the label's reasons and the board. `gctk merge`'s own
readers of holds retire with it: `inflightHolder`, the blocker walk in
`recordBlockerVerdict`, `finalize-gate.sh`'s no-open-gate clause at merge, and
`landsFirst`'s `isHeld`. Moving `prstatus` under the pr domain, onto the
ledger, is gctk's recorded debt, and it goes with tk-1tfzr71.21, which rewrites
`prstatus`'s facts off the posture
([gctk-architecture.md](../../docs/gctk-architecture.md#debt)).

| Hold | Kept | Expressed as |
|---|---|---|
| The anchor's open children that work on its branch: a rework, a fix unit, a merge-in | yes | the child carries `anchor_bead`, and `prstatus` counts it in flight |
| A bead that names the PR | no | a bead that must hold a PR blocks its anchor by a `blocks` edge, and naming the PR holds nothing |
| A wait of the anchor's own, such as a `blocks` edge from work that must land first | yes | the `waits` answer, which `prstatus` takes |
| An open human gate on the anchor | yes | the gate blocks the anchor |
| An open conversation on the PR | yes | its `conversation.<id>` gate on the anchor (tk-icol3l8) |
| A review thread | yes | GitHub's thread rule where the repository requires resolved threads, and `held: review` for a thread still waiting on the city's answer, on every base |
| `merge_hold` and `rebase_hold`, set by hand | yes | read by `prstatus`, unchanged |
| A removed script that open runs still call | no (call 3) | each deletion bead's drain check |
| The seed render | no (call 2) | the re-render after landing |
| The approval and the CI checks | GitHub's | the target branch's ruleset |
| The bead's own `gh:pr` merge gate | not a hold | it is the merge itself, so `prstatus` excludes it, and `blocker-holder.sh` reads a gate that core's gate sweep resolves as held by an automated actor |

The last row matters while the old merge runs on rigs not yet moved.
`gctk merge` holds a merge on any live blocker of the anchor. It records a blocked
verdict for a blocker that no automated actor holds, and `prstatus` reads that
verdict as `needs-attention`. Without those two clauses, every bead on the new
path would read held on its own merge gate.

## 6. Which anchor states survive, and what reads them

**The end state.** `merge_result` keeps the values Gas Town's refinery records
for the same facts, each with one meaning:

- **No record** (the key absent): the bead has not landed and owns no open PR. A
  bead sent back keeps the record it had, so absence never means "rejected".
- **`pull_request`**: the bead owns an open PR (`pr_number`, `pr_url`) and waits
  on its merge gate.
- **`merged`**: the bead is closed and its work is on the target at `merged_sha`.
  For `direct` that is the fast-forward push. For `mr` it is GitHub's merge
  commit, found on `origin/<target>` after a fetch.

`rejection_reason` is the record that the work was sent back, and why. A person's
wait is a human gate on the bead, keyed by its case. `pre_open_gate` retires,
because no PR waits to be opened. `abandoned`, `retargeted`, `blocked` and
`refused_false_completion` retire into human gates whose keys name the case.
`unanchored` retires into the absent key.

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
| owns an open PR (`pull_request`) | the refinery's `mr` step; on the old path `pr-open.sh`'s create and `pr-facts.sh`'s PR records | nothing, once the machine goes | `check-one-anchor-per-pr`, and I2 (`check-state-space`) re-read against the kept values | the board's merge rows (`isMergeAnchor`), `waits` (`in_flight`), `work-gate.sh`, `work-submit.sh` (`resolve_anchor`), `deferred-dispatch.sh`'s arm retirement, `priority-lib.sh`, tk-icol3l8's subject test |
| landed (`merged`, `merged_sha`, closed) | the refinery's direct landing (`direct-merge-push.sh`) and close step; on the old path `gctk merge` and `pr-facts.sh`'s record of a merge made outside the city | nothing | I5 (`check-closed-implies-landed`), widened below | `work-submit.sh` through `gc.work_outcome`, `pr-stack.sh`'s in-flight filter (retiring) |
| sent back (`rejection_reason`) | the refinery's requeue; `rework-child.sh` (tk-1tfzr71.22) and `pr-facts.sh` (tk-1tfzr71.21) until they retire | nothing | nothing | `gc-helm.sh`'s takeaway refusal and `waits` (`in_flight`), each reading it as work in flight |
| held for a person | `human-gate.sh` | its one-open-gate-per-key rule | `check-wait-is-an-edge` | none |
| closed | the refinery, the duplicate and stand-down writers, a person | bd's close of a bead with open waits | I5, for every bead that carries a PR | none |

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
| The board and the status label | Both still read `prstatus`. The label writer also posts the city's status and keeps auto-merge, and the board's clauses for retired values match nothing once no bead carries them. | unit 2; the board member (tk-1tfzr71.24) drops the dead clauses |
| The PR-finishing rank (`prio_pr_approved` in `priority-lib.sh`) | Carried, not dropped. It reads the approval from the posture at `pr_head_oid`, which stay until tk-1tfzr71.21. When the posture goes, the rank reads the approval from `prstatus`, the reading the projection uses. Whichever change removes the machine's exit sets keeps clearing `pr_finishing_settled` and `pr_head_oid` when a bead leaves `pull_request`, until tk-1tfzr71.21 removes the keys. | tk-1tfzr71.21, and the retirement bead |
| The sign-off's headline (`converse-signoff.sh`) | It reads `prstatus` instead of sourcing `review-verdict.sh`. `needs-review` means the PR still needs your Approve, or your merge on a branch with no approval rule. | unit 4 |
| A rework child parked for a person | It still owns the anchor's branch. The refinery's conflict path, and later the intake's conflict repair, add the conflict to that child's notes, running or parked, and file and sling nothing else. | unit 3; tk-1tfzr71.21 for the intake |
| The doctor | I5 reads every closed bead with a PR. I2 reads the kept values. `check-refinery-patrol-live` retires with the old patrol. | units 3 and 4, and the retirement bead |
| Readers that take `pull_request` as "an anchor" | Unchanged: the value keeps its meaning. | none |

## 7. Rework and branch currency

**The refinery brings a branch current.** Its prep merges the target in. When
the merge is clean, the refinery publishes it itself (section 4), with no
polecat and no audit. When it conflicts, the work goes back to the pool with
`rejection_reason` "Conflicts with `<target>` at `<sha>`". It goes back as the
bead itself when the bead has no PR yet, and as the PR's rework child when it
has one (section 1). The polecat merges and resolves the conflict, and writes in
the merge commit's message what collided and what it decided.
`git show --remerge-diff <merge>` then shows a reviewer exactly the hunks
resolved by hand, and that commit is what triage reads at the new head. A rework
or rebuild child is dispatched by `gc sling`, as the dispatch design has it.

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
Until tk-1tfzr71.21, `pr-facts.sh`'s conflict arm finds the conflict, and it
files the merge-in only for an approved PR. After that, the PR monitor's
`merge_conflict` class finds it (`classifyPullRequest`), and the intake routes it
to the refinery's prep.

**Landing time with 50 or more PRs open.** No pass visits every PR to land one,
because GitHub merges an approved PR when its last requirement, the city's
status, passes. Until tk-1tfzr71.21 the city still reads your approval on the
posture arm, and the label writer posts the city's status in the same pass. That
arm reads only the PRs that moved, but it runs once per pass, and at 87 anchors
a pass took about 30 minutes (the city config's override note). So a PR lands
within one pass of the last of its other requirements to pass, which is most
often your approval or its CI checks, as today. Once tk-1tfzr71.21 lands, the
city reads the approval on its webhook event, and posts its status when a
required check at the head completes.

The closed epic's two checks, recorded in the initiative's notes of 2026-11-08,
are a proposal, and this design proposes reading them once lane A has landed:
- Nine in ten approved PRs land within 3 hours over a fortnight with 50 or more
  open. The baseline, measured from GitHub as first approval to merge: from 1 to
  14 October, with about 90 to 104 open, the median was 34 minutes and nine in
  ten landed within 16.7 hours. From 25 October to 7 November, with about 6
  open, the median was 5 minutes and nine in ten landed within 2.4 hours.
- A landing brings current only the PRs it directly conflicts with. That holds
  by construction while the rules do not require a current branch.

**The integration-effort hand-off** stays the refinery's (tk-gmjtb2e, unlanded).
It is a difference from Gas Town until the convoys member lands (section 1).
Unit 3 carries whichever of the two lands second.

## 8. What the pack keeps, and in what form

- **The PR's title and managed summary** become `gctk pr compose <bead>` and
  `gctk pr summary <bead>` ([gctk-architecture.md](../../docs/gctk-architecture.md#the-surface)).
  Compose reads the managed region by its markers, never up to the first
  `<details>` line (tk-tefrxph). `pr-summary-region.sh` goes in the same change.
- **`pr-stack.sh`'s re-render** moves into the step that opens or updates the
  PR. The refinery composes the title and body and edits the PR before it
  pushes a new head, so a review started at that head reads the current body
  (tk-pdc0ovc). `pr-stack.sh` and its arm go.
- **The seed audit:** call 2.
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
- **The approval nuances GitHub cannot express** stay as named residuals under
  one warrant, *The city's merge status*, which unit 2 adds to
  [warrants.md](../../docs/warrants.md):
  - the merge waits for the city's verdict at each head;
  - auto-merge waits for the city's reading of the approval, so the approval's
    own message is read first;
  - the city's verdict passes last, once every other requirement is met and
    the intake has routed the feedback it counts, so feedback that arrives
    after auto-merge is on is read before the merge;
  - a thread still waiting on the city's answer holds the merge where the base
    does not require resolved threads;
  - each push the pack makes onto a PR's branch publishes the head behind a
    pending status, under the projection's lock, so none of them brings a PR
    onto a verdict that did not count it (section 4).

  The warrant also names the residuals they leave open. A review or comment
  submitted between the city's last read and GitHub's merge goes in unread
  (section 3). A push that does not go through the publication, such as a
  person's, can move a PR onto a commit whose status already reads success
  (section 4).
- **The pre-existing-failure scripts** stay, off the deletion plan. The work
  formula's pre-flight files a base failure's tracker through
  `preexisting-failure.sh`, and its self-review marks one through
  `rig-check-pre-existing.sh`. Those are the tested scripts the work member
  (tk-1tfzr71.12, closed) moved them onto. Retiring the scripts would put core's
  search-and-file procedure back into step text, against rule 2. Only the
  refinery's own use changes: a failure already on the target is tracked, and
  the landing goes ahead, as Gas Town's handle-failures does.

**The deletion plan's rows.** Unit 5 moves the rows whose files have callers this
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
| tk-c8hl47c: a pre-open rework becomes a second anchor of its PR | removes it | No pre-open round exists, and the refinery opens or updates only the PR of the branch's owner. A rework child's hand-back updates its anchor's PR and never gives the child a landing record of its own. |
| tk-cvffk5x: the architecture references omit the direct landing writer | removes it | This design's change to `architecture.md` states both landing paths and their writer, and unit 5 rewrites `component-model.md`'s. |
| tk-gwmqd0x: gctk's signal relay test races its trap | removes it | The test goes with `gctk lifecycle`. |
| tk-ni0i48p: the refinery's push forces over commits gained after the prep | removes it | Every push is a fast-forward, and a push refused as non-fast-forward is retried from a fresh prep, never forced. |
| tk-o9i6kp0: how an approval behaves across a rework | settles it in section 3 | Its validating closer checks the model against the note of 2026-11-05. |
| tk-pdc0ovc: a lane reads the PR body before the summary refresh | removes it | The refinery edits the body before it pushes the head that starts the lane. |
| tk-r82qrrv: the state-machine guide misnames the guard as a resolver caller | removes it | Unit 5 rewrites the Checks vocabulary in that page. |
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
- The dismissal that drops unrouted comments (tk-uos4onx): the withdrawal writer
  lets the intake route them first.
- The login read from gh's stdout whatever its exit (2026-11-03 note): the
  withdrawal writer reads it through `pr-post.sh acting-login`.
- The stale rig HEAD in the dropped-tail finding (2026-11-06 note) goes with that
  report.

tk-1tfzr71.50, the deletion of `bd-lib.sh`'s checked create, waits on the last
callers of those helpers. After this member, they are in files that
tk-1tfzr71.21 and .22 retire, so its edge onto this initiative is joined by edges
onto those two.

## 10. The cutover

The effort lands for every rig at once. After it lands, the merge moves one rig at
a time, gc-toolkit first.

**What lands with the effort.** The new refinery formula runs on every rig. It
brings branches current by merge, requeues through `gc sling`, lands `direct`
work, updates an open PR and closes a bead once its PR has merged. The city's
status is posted on every PR, and it holds nothing on a rig until that rig's
cutover makes its default branch and its integration branches require it.

On a rig still on the old path, the `mr` step parks the bead at `pre_open_gate`
as it does today. `pr-open.sh` opens its PR, and `gctk merge` merges it under
the pack's rule.

A rig formula variable, `github_merge_rules`, says the rig's rules are in place.
Only the refinery's `mr` step reads it. When it is set, the step opens the PR as
a draft at once and files the bead's merge gate. From then on, the merge gate
tells every other reader that the bead is on the new path: the projection keeps
auto-merge only for a bead with one, and `gctk merge` holds such a bead on that
gate and never merges it.

On such a rig the `mr` step opens or updates a PR only into a target whose
rules, as GitHub returns them for that branch, require `gc-toolkit/status`. The
projection it runs reads those rules already, for the auto-merge toggle. For any
other target it opens nothing, and files a human gate on the bead that names the
target, so every PR the city opens waits for the city's verdict, whoever presses
Merge. On 2026-11-09 no open bead in any rig's store targeted a branch other
than its default branch or an integration branch.

**The integration branches' rules and the city's pushes.** A ruleset that
requires a status check refuses an update of the branch until the check has
passed at the new commit: "commits must first be pushed to another ref where the
checks pass" (`required_status_checks` in
[Repository rules](https://docs.github.com/en/rest/repos/rules)). The rule's
entry in
[Available rules for rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets)
has the checks pass "before collaborators can make changes to a branch or tag
targeted by your ruleset", not only before a merge. The refinery lands a
`direct` bead on an integration branch by such an update, and an effort's
stand-up, its bring-current and a rework of its landing PR push there too.
Posting success at the commit before the push would not serve once the effort's
landing PR is open, because the push moves that PR's head. A success posted
before the push did not count the PR, so the PR would arrive at a verdict given
without it. A verdict that counts the PR reads pending while anything holds it,
so GitHub would refuse the push. So the city's account pushes there through the
ruleset's bypass, which it alone holds, in mode `always`. Mode `pull_request`
covers pull requests only, and a landing is a push. Mode `exempt` runs no rules
for the account and leaves no entry in the ruleset's audit. The city posts
nothing for a landing itself. When the branch heads an open PR, as it does once
the effort's landing PR is open, the push publishes that PR's new head (section
4). Without the bypass, GitHub refuses the landing, and `direct-merge-push.sh`
reads the refusal as a protected branch and promotes the bead to `mr`, so the
work waits for a stage PR.

**Each rig's cutover** is a bead the implementation child files on the default
branch, blocked by this initiative's landing:
1. You change the rig's GitHub settings, which a human gate on the bead asks
   for:
   - allow auto-merge;
   - make the default branch's ruleset require an approving review, the rig's CI
     checks and `gc-toolkit/status` with no integration ID;
   - add a ruleset on `integration/**` that requires `gc-toolkit/status` with
     no integration ID, and under call 1(b) an approving review, with one
     bypass actor in mode `always`: the city's account alone. The settings page
     grants a bypass to roles, teams and apps, so that actor is a team whose
     only member is the city's account, or the account itself as a `User` actor
     set through the rules API ([Creating rulesets for a
     repository](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository),
     [Repository rules](https://docs.github.com/en/rest/repos/rules));
   - let the city's account dismiss reviews;
   - set thread resolution as you want it.
2. Sandbox PRs show each behavior, against a ruleset copy on a `sandbox/**`
   branch:
   - an unapproved PR does not merge;
   - an approved PR whose city status is pending does not merge;
   - an approved PR whose CI checks still run keeps the city's status pending,
     and a review submitted meanwhile is read before the status turns success;
   - in one projection run, auto-merge turns on while the city's status still
     reads pending, the success posts after it, and the PR merges by
     auto-merge. The sandbox also shows whether GitHub refuses to turn
     auto-merge on for a PR it can already merge;
   - two approved PRs at one head stay unmerged while one of them is held, and
     the city's status names the held one. A PR with nothing left to merge
     beside a held one is among the cases;
   - the city's dismissal lands and turns auto-merge off;
   - a push to an approved PR keeps the approval, and the merge waits until the
     city posts at the new head;
   - an approved PR with auto-merge on, which the city holds, pushed onto
     another PR's head where the city's status reads success, stays unmerged
     until the city posts there a verdict that counts it, once for a polecat's
     push and once for the refinery's;
   - the merge gate resolves on the merge, and the refinery closes the bead;
   - a stage PR, against a copy of the integration ruleset on another
     `sandbox/**` branch: a person who holds no bypass cannot merge it while the
     city's status reads pending, and the city's fast-forward push of a
     `direct` landing onto that branch lands through the bypass.

   Under call 1(b) or (c), it also shows whether auto-merge on a stage PR waits
   for the rules when the account that turned it on holds the bypass. If it does
   not, the bypass moves to a deploy key that only the city's pushes use
   (`DeployKey` in the rules API), so the account that turns auto-merge on holds
   none.
3. The mechanik sets `github_merge_rules` in the rig's config, and watches the
   rig's first PRs through to their close.

**The old path finishes.** `merge_result` stays readable throughout. A bead that
opened its PR on the old path carries no merge gate, so `gctk merge` keeps
merging it under the pack's rule until it lands.

A retirement bead on the default branch waits on every rig's cutover bead, and is
armed to dispatch when they close. Its drain check is that no open bead is on the
old path: no `pre_open_gate`, and no `pull_request` without a merge gate. It then
deletes:
- `gctk merge`, `merge.sh`, their tests and the merge arm;
- `merge-tail-report.sh`;
- `pre-open-rebase.sh` and its arm;
- `pr-open.sh`'s create path;
- `gctk lifecycle` and the machine in `lifecycle.toml`. `lifecycle.sh` stays a
  plain write of the value, keeping the two side effects its callers rely on:
  the work record a landing writes, and the clear of the PR-finishing keys when
  a bead leaves `pull_request`. Its row goes under tk-1tfzr71.21, whose
  `pr-facts.sh` is its last caller;
- `review-verdict.sh`'s gctk copy and the parity cases;
- the old `mr` branch of the refinery's step;
- `github_merge_rules` itself;
- the old path's entry under Debt in `architecture.md`.

**Rule 2.** Every step of the rewritten formula calls one tested script and holds
no shell procedure. The suites that extract the old formula's blocks go in
unit 3, with the steps they extract, as the operator ruled for this rewrite
(2026-10-26).

## 11. The units

Each unit lands on `integration/tk-1tfzr71.20`, keeps the suite green and
leaves the city working.

| Unit | What it does | Waits on | Answers |
|---|---|---|---|
| 1. `gctk pr compose` and `gctk pr summary` | The PR's title, managed summary region and branch-beads section are composed in gctk from the bead that owns the PR, with the region read by its markers. `pr-summary-region.sh` is deleted, and `pr-open.sh` and `pr-stack.sh` call the verb. Go tests pin the output against today's renders. | nothing | tk-tefrxph; the gctk domain move note |
| 2. The city's status on GitHub | `prstatus` answers whether the city holds the merge: nothing in flight, nothing held, and, by the `waits` package's answer, no wait of the anchor's own but its merge gate. It reads "waiting for your merge" on a base with no approval rule. It reads a PR's unanswered threads when it gathers the PR's facts, so the count's one writer can retire with `gctk merge`. The label writer also posts `gc-toolkit/status` at the head, success or pending and never failure. It posts success last, once every other requirement of the target is met there and no feedback on the PR is newer than the anchor's watermarks, counted by the intake's own rule. One status covers every open PR at that commit, read fresh from the repository's open PRs and branch refs before each post: a PR from a branch in the repository is at its branch's ref, and a PR from a fork at its `head.sha`. Among them are a PR from a fork, a PR into another base and a PR with no anchor. Whichever writer runs the projection, it waits for a lock for the repository, reads under it everything the verdict rests on, the watermarks before the holds, and posts only when the state or description changes (section 4). The unit also builds the publication of a head (section 4). Under that lock, a writer that pushes a branch heading an open PR reads the city's status at the commit the push will make the head, has the projection post pending there when it reads success, pushes, and runs the projection there before it lets the lock go. The polecat's push at submit (`work-submit.sh`) and the witness's salvage push move onto it. For a bead that carries its merge gate, it keeps auto-merge on exactly while the city reads the PR approved on a base that requires an approving review, and turns it on before it posts success. No bead carries one before unit 3, so the toggle is inert until then. `blocker-holder.sh` reads a gate that core's gate sweep resolves as held by an automated actor. The warrant *The city's merge status* is added, covering the status, its lock, the publication and the auto-merge toggle. Tests for each, among them a review that arrives while a required check still runs, feedback the intake's rule leaves out, which holds nothing, the auto-merge toggle turning on before the success post, two open PRs at one head with one of them held, where the status reads pending for both, a PR with nothing left to merge beside a held one, a shared head on the default branch and one from a fork, a writer that waits for the lock, two writers posting at one commit, a publication onto a commit whose status reads success, which posts pending before its push, a publication whose push fails, which still projects there, a projection during a publication, which waits for it, and a PR whose `head.sha` still names its old commit, which is counted at its branch's ref. | nothing | sections 3, 4 and 5 |
| 3. The refinery on Gas Town's flow | `mol-refinery-patrol` is rewritten on Gas Town's steps at 3339ad104a88, with the differences in section 1, and each step calls one tested script. The scripts cover: the prep by merge in the refinery's own worktree (`refinery-workspace.sh` and its warrant go); the gate through `detached-job.sh`; the failures, through the requeue by `gc sling` or a rework child, and the pre-existing path; the direct landing, published through unit 2's publication when the target heads an open PR; the `mr` step (compose the title and body, edit them onto a PR the bead already owns before it publishes the new head through unit 2's publication, or push and then open a new PR as a draft with them, record the PR with `opened_as_draft` so the review lanes and `pr-open.sh`'s ready flip handle it unchanged, file the merge gate with a notice to the refinery, run the projection, file a human gate in place of a PR into a target whose rules do not require `gc-toolkit/status`, and the old-path park while `github_merge_rules` is unset); the close once the merge gate resolves, with the seed re-render under call 2; the rework hand-back; and the integration-effort hand-off, whose push is published the same way. `rejection-repool.sh`, `pr-stack.sh` with its arm, `check-refinery-patrol-live` and the old formula's block-extraction suites go. The polecat doctrine gains the drift rule. | units 1 and 2; tk-gmjtb2e, whichever lands second carrying the other | tk-c8hl47c, tk-ni0i48p, tk-pdc0ovc, tk-w0hkwos; section 7 |
| 4. The readers move | The sign-off's headline reads `prstatus`. I5 reads every closed bead with a PR. I2 reads the kept values. | unit 3 | section 6 |
| 5. Docs, warrants and the plan | The pages that hold the merge's depth are rewritten to the flow as it stands once units 1 to 4 land: `refinery-merge-cadence.md`, `state-machine.md` (the kept values and their sentences, and the Checks vocabulary), `component-model.md` with both landing writers, `authority-map.md`, `design-convoy.md`'s gates under call 1, `gctk-architecture.md`'s rows and the merge section of `built-once-target.md`, which takes section 1's differences as that page holds the witness's. `architecture.md` states the target from this design's own change, with the old path under Debt. Unit 5 drops the Debt entry units 1 to 4 retire, the refinery push that can force, and corrects any line a unit departed from. The warrants' Covers lines move off retired paths. The plan's rows move as section 8 says. | units 1 to 4 | tk-cvffk5x, with this design's change to `architecture.md`; tk-r82qrrv |

**What each waiting member needs.**

| Member | Needs | Because |
|---|---|---|
| tk-1tfzr71.22, review lanes | the status placement, the approval decision's ownership, and units 2 and 4 | Its loop's verdict at each head is `prstatus`'s review input. Triage at each head owns the approval decision, through one withdrawal writer. It takes over the bring-current guard and audit (section 8). A conflict on a branch with an open PR comes to it as a rework child until its loop has a repair step for it. |
| tk-1tfzr71.21, GitHub intake | sections 3, 5 and 7, and unit 2 | It reads an approving review's message as feedback. It resolves the city's own threads once answered. It routes the monitor's `merge_conflict` to the refinery's prep, and takes nothing from its `blocked` class, which the monitor marks actionable for every PR GitHub reads BLOCKED, one waiting on your approval or on the city's status included (`classifyPullRequest`). It runs the projection when a required check at a PR's head completes, because the city's status passes last (section 4). It moves the PR-finishing rank and `prstatus`'s facts off the posture. It deletes the cadence driver and the files whose rows move to it. |
| tk-1tfzr71.23, convoys | the integration-effort hand-off's place in unit 3 | Moving efforts onto `gc convoy land` ends that difference. |
| tk-1tfzr71.25, META | the retirement bead's row list | The registry entries and parity tests of the retired machine go there. |

## 12. Edges and notes the implementation child adds

- The five units are filed under the epic (tk-1tfzr71) with
  `target=integration/tk-1tfzr71.20` in each create. The landing bead
  (tk-1tfzr71.20) and the summary task (tk-1tfzr71.68) each wait on every unit
  through a `blocks` edge. Each unit waits on the units its row names and is
  armed to dispatch when they close.
- The cutover beads, one per rig, and the retirement bead are filed with
  `target` the default branch, outside the effort. Each is blocked by
  tk-1tfzr71.20 and armed. The retirement bead is also blocked by every cutover
  bead. Neither the landing bead nor the summary task waits on any of them.
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
  again, since they move. At this design's reading, these overlap:
  - tk-gmjtb2e (PR #1455), which edits the refinery's prompt and the
    integration-effort recipe, for unit 3.
  - tk-icol3l8 (PR #1453), in review, which files a conversation's gate on the
    anchor and rewrites `converse-signoff.sh`, for unit 2's holds and unit 4's
    sign-off.
  - tk-rl8gz4b.28 (PR #1445), the po effort, which edits
    `lifecycle/lifecycle.toml` and pages unit 5 rewrites (`architecture.md`,
    `authority-map.md`, `built-once-target.md`, `component-model.md` and
    `warrants.md`), for unit 5 and the retirement bead. Its edits to
    `architecture.md` and `built-once-target.md` sit beside this design's own
    and share no line with them.

## 13. Facts this design rests on

- **Gas Town's refinery** (`gastown/formulas/mol-refinery-patrol.toml` at
  3339ad104a88), in `mr` mode:
  - It pushes with `--force-with-lease` and runs `gh pr create` itself.
  - It runs `pr-merge-reconcile record`, which leaves the bead blocked until
    GitHub reports the PR merged and its merge commit is on the target
    (`gastown/commands/pr-merge-reconcile/run.sh`).
  - It runs no `gh pr merge`, so a person merges.
  - Its conflict and branch-failure paths write `gc.routed_to` to the polecat
    pool by hand, and the branch-failure path deletes the branch.
  - It files a pre-existing failure as a P1 bug found by its title, and merges
    anyway.
  - Its refinery agent sets `max_active_sessions = 1`.
- **The gastown that gc 1.4.3 bundles** (66897e7132c9) closes an `mr` bead at
  publication with `merge_result=pull_request`, and its `gastown/commands` holds
  only `status`.
- **bd's `gh:pr` gate** (`checkGHPRWithRunner` in `cmd/bd/gate.go` at v1.3.4)
  resolves when `gh pr view` reports MERGED. On CLOSED it escalates through
  `gt escalate`, which the city does not have, and stays open, so the intake or
  a person answers a PR closed without merging.
- **Core's gate sweep** runs every 30s (`internal/bootstrap/packs/core/orders/gate-sweep.toml`).
  It checks the gates of the city store and of every rig store that is not
  suspended (`gate-sweep.sh`).
- **Gas City's PR monitor** lists open PRs only and classes them as
  `checks_failed`, `merge_conflict`, `behind_base` or `blocked`
  (`classifyPullRequest`). `gc github pr backfill --create-repair-beads` files
  one repair bead per PR head, and nothing schedules it.
- **No Gas City or Gas Town primitive gates a merge on approval or on required
  checks.** Only gstack's land-and-deploy skill runs `gh pr merge --auto`, and
  pr-review's `mol-pr-merge-only` waits on checks and merges.
- **GitHub** counts a commit status as a required check, and requires a check on
  the latest commit only. A commit status belongs to the repository and the
  commit, so every PR at that commit shows it. The latest status in a context
  counts, GitHub keeps at most 1000 per commit and context, and the status API
  has no compare-and-set. Auto-merge merges once every required review and check
  passes. It turns off only when someone without write access pushes or the base
  branch changes, so a review leaves it on. A review that requests changes from
  an account with write access holds the merge until its author approves or
  someone with write access dismisses it. The list of pull requests associated
  with a commit returns only the merged one for a commit on the default branch,
  and on 2026-11-09 it returned none for the heads of two open PRs from forks
  (cli/cli #14783 and #14689), which the repository's list of open PRs returns
  with their head commits. A merge queue is
  available to this organization-owned public repository, but every required
  check would have to run on the queue's merge group. The city's per-head status
  cannot, so this design does not use one.
- **GitHub's rulesets.** A ruleset that requires a status check refuses an
  update of a branch it covers until the check has passed at the new commit
  (`required_status_checks` in [Repository
  rules](https://docs.github.com/en/rest/repos/rules)). The rules API takes as a
  bypass actor an integration, an organization admin, a repository role, a
  team, a deploy key or a user. Mode `always` is the default, `pull_request`
  lets the actor bypass the rules on pull requests only and never applies to a
  deploy key, and `exempt` runs no rules for the actor and creates no bypass
  audit entry. The settings page grants a bypass to repository admins and
  organization owners, the maintain or write role, teams other than secret
  ones, GitHub Apps and Dependabot ([Creating rulesets for a
  repository](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository)).
  Neither that page nor the page on auto-merge says whether auto-merge waits
  for a ruleset's rules when the account that turned it on may bypass them.
- **GitHub's status read** (`GET /repos/{owner}/{repo}/commits/{ref}/status`,
  and `.../statuses`) answers 200 with no statuses for a commit the repository
  does not hold, the same as for a held commit with none (read on gc-toolkit on
  2026-11-09).
