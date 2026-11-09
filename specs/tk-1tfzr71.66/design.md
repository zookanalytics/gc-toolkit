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
status GitHub requires, and GitHub's auto-merge lands the PR once its rules and
that status allow. Your approval carries across reworks, and only the city's
reading of a change withdraws it. The new flow reaches every rig when the effort
lands, and the merge moves onto GitHub one rig at a time, after you set that
rig's rules and a sandbox PR shows they hold.

Three calls carry a cost either way:

1. **Who decides that a PR has its approval.**
   - (a) GitHub, wherever the target branch's rules require an approving review,
     as gc-toolkit's default branch does. A PR into a branch with no such rule
     waits for you to merge it, as in Gas Town's flow. That includes every stage
     PR into an integration branch, this design's own among them, so a design
     gate becomes your Merge instead of your Approve. The pack's approval rule
     is deleted.
   - (b) As (a), plus a ruleset that requires an approval on integration
     branches, so a stage PR merges on your Approve. The city's direct landings
     onto those branches then need a bypass that only its account holds, and a
     sandbox PR has to show that auto-merge still waits for your approval,
     which GitHub's documentation does not say.
   - (c) The pack, as the ruling of 2026-10-02 has it. The city lets GitHub
     merge only once it reads a standing approval from another account, on
     every branch, with nothing to set up. The pack keeps its reading of the
     reviews under a warrant.
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
`gc-toolkit/status` beside the CI checks, and to let the city's account dismiss
reviews. Until the GitHub-intake member lands, a PR lands within one pass of
your approval, as it does today. Some of the deletion plan's rows move to the
members whose code still calls their files (section 8). Section 11 lists the
five units the implementation child files, and section 10 the cutover beads and
the retirement bead that land after the effort does.

## 1. The target flow, and how the pack takes Gas Town's

### The flow

1. A polecat hands its bead to the rig's refinery, as it does today.
2. The refinery takes one bead assigned to it that nothing holds, by the
   answer of `gctk bead holds`, and brings its branch current by merging the
   target in.
3. It runs the rig's gate.
4. A failure the branch caused sends the work back to the polecat pool. A
   failure that is already on the target is tracked, and the landing goes
   ahead.
5. A `direct` bead lands by a fast-forward push, and the refinery closes it.
6. For an `mr` bead, the refinery pushes the branch. It opens the PR as a
   draft, or updates the PR the bead already owns, with the title and body
   `gctk pr compose` makes. It files a `gh:pr` gate on the bead, so the bead
   waits on its own PR's merge, and it runs the PR's projection.
7. The review lanes run on the draft, and the PR turns ready when the lanes
   before that phase pass.
8. The projection posts the city's verdict on the PR's head as the
   `gc-toolkit/status` commit status. While the city reads the PR approved, it
   also keeps GitHub's auto-merge on, where the target's rules require an
   approving review.
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
and never edits them. Call 1 sets what holds a stage PR once the pack's rule
retires:

- Under (a), only a person merges a PR into a branch with no approval rule.
  `prstatus` reads such a PR `needs-review`, with the reason "waiting for your
  merge" once the lanes pass, so the label, the board and the sign-off
  ask for the merge, not an approval. A rig whose default branch requires no
  approval has its PRs wait for a merge in the same way, until its cutover sets
  the rule.
- Under (b), the integration ruleset holds a stage PR for the approval, and the
  projection turns auto-merge on for it as it does on the default branch.
- Under (c), the projection reads the pack's own verdict on the reviews instead
  of GitHub's rule, on every branch. `review-verdict.sh` stays as that reading
  under a warrant, and its gctk copy and the parity cases go.

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
2. **An approval submitted between the comment read and the merge.** The merge
   this design builds closes it. Auto-merge is on only while the city reads the
   PR approved, and the city reads it approved only after it has read the
   reviews, the approving one included. An approval that arrives with comments
   cannot merge ahead of their reading.
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

**The placement is the city's status on each head commit, which the rig's
ruleset requires.** GitHub requires a check to pass on the PR's latest commit,
and a check from an earlier commit does not count ([Troubleshooting required
status checks](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks)).
So every push leaves the PR without the city's verdict, and nothing can merge it
until the city posts one at that head, whoever presses Merge. A review that
gates only the PR's opening would leave a later push unjudged, as the 2026-10-23
requirement says.

**What the status reads.** It reads success when the city has nothing in flight
on the PR and nothing holding it, and pending otherwise, with what it waits on in
the status description. It never reads failure, because every reader that acts
on a red check would take the city's own hold for one: `pr-facts.sh`'s red-check
arm today, and Gas City's PR monitor, which classes a PR with a failing check as
`checks_failed` (`classifyPullRequest` in `internal/githubmonitor/monitor.go`). A
commit status from the city's own token satisfies a required check whose
`integration_id` is left unset ([Repository rules](https://docs.github.com/en/rest/repos/rules)).

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

**The refinery brings a branch current.** Its prep merges the target in. When the
merge is clean, the refinery pushes it itself, with no polecat and no audit.
When it conflicts, the work goes back to the pool with `rejection_reason`
"Conflicts with `<target>` at `<sha>`". It goes back as the bead itself when the
bead has no PR yet, and as the PR's rework child when it has one (section 1).
The polecat merges and resolves the conflict, and writes in the merge commit's
message what collided and what it decided. `git show --remerge-diff <merge>`
then shows a reviewer exactly the hunks resolved by hand, and that commit is
what triage reads at the new head. A rework or rebuild child is dispatched by
`gc sling`, as the dispatch design has it.

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
because GitHub merges an approved PR when its last requirement passes. Until
tk-1tfzr71.21 the city still reads your approval on the posture arm. That arm
reads only the PRs that moved, but it runs once per pass, and at 87 anchors a
pass took about 30 minutes (the city config's override note). So a PR lands
within one pass of its approval, as today. Once tk-1tfzr71.21 lands, the city
reads the approval on its webhook event.

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
  - a thread still waiting on the city's answer holds the merge where the base
    does not require resolved threads.
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
| tk-cvffk5x: the architecture references omit the direct landing writer | removes it | Unit 5 rewrites "How work moves" with both landing paths and their writers. |
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
status is posted on every PR, and it holds nothing until a rig's ruleset
requires it.

On a rig still on the old path, the `mr` step parks the bead at `pre_open_gate`
as it does today. `pr-open.sh` opens its PR, and `gctk merge` merges it under
the pack's rule.

A rig formula variable, `github_merge_rules`, says the rig's rules are in place.
Only the refinery's `mr` step reads it. When it is set, the step opens the PR as
a draft at once and files the bead's merge gate. From then on, the merge gate
tells every other reader that the bead is on the new path: the projection keeps
auto-merge only for a bead with one, and `gctk merge` holds such a bead on that
gate and never merges it.

**Each rig's cutover** is a bead the implementation child files on the default
branch, blocked by this initiative's landing:
1. You change the rig's GitHub settings, which a human gate on the bead asks
   for:
   - allow auto-merge;
   - make the default branch's ruleset require an approving review, the rig's CI
     checks and `gc-toolkit/status` with no integration ID;
   - let the city's account dismiss reviews;
   - set thread resolution as you want it.
2. A sandbox PR shows each behavior, against a ruleset copy on a `sandbox/**`
   branch:
   - an unapproved PR does not merge;
   - an approved PR whose city status is pending does not merge;
   - an approved PR whose city status reads success merges by auto-merge;
   - the city's dismissal lands and turns auto-merge off;
   - a push to an approved PR keeps the approval, and the merge waits until the
     city posts at the new head;
   - the merge gate resolves on the merge, and the refinery closes the bead.

   Under call 1(b), it also shows whether auto-merge waits for the approval when
   the account that turned it on may bypass the rule.
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
- `github_merge_rules` itself.

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
| 2. The city's status on GitHub | `prstatus` answers whether the city holds the merge: nothing in flight, nothing held, and, by the `waits` package's answer, no wait of the anchor's own but its merge gate. It reads "waiting for your merge" on a base with no approval rule. It reads a PR's unanswered threads when it gathers the PR's facts, so the count's one writer can retire with `gctk merge`. The label writer also posts `gc-toolkit/status` at the head, success or pending and never failure. For a bead that carries its merge gate, it keeps auto-merge on exactly while the city reads the PR approved on a base that requires an approving review. No bead carries one before unit 3, so the toggle is inert until then. `blocker-holder.sh` reads a gate that core's gate sweep resolves as held by an automated actor. The warrant *The city's merge status* is added. Tests for each. | nothing | sections 3, 4 and 5 |
| 3. The refinery on Gas Town's flow | `mol-refinery-patrol` is rewritten on Gas Town's steps at 3339ad104a88, with the differences in section 1, and each step calls one tested script. The scripts cover: the prep by merge in the refinery's own worktree (`refinery-workspace.sh` and its warrant go); the gate through `detached-job.sh`; the failures, through the requeue by `gc sling` or a rework child, and the pre-existing path; the direct landing; the `mr` step (fast-forward push, compose, open as a draft or update, record the PR with `opened_as_draft` so the review lanes and `pr-open.sh`'s ready flip handle it unchanged, file the merge gate with a notice to the refinery, run the projection, and the old-path park while `github_merge_rules` is unset); the close once the merge gate resolves, with the seed re-render under call 2; the rework hand-back; and the integration-effort hand-off. `rejection-repool.sh`, `pr-stack.sh` with its arm, `check-refinery-patrol-live` and the old formula's block-extraction suites go. The polecat doctrine gains the drift rule. | units 1 and 2; tk-gmjtb2e, whichever lands second carrying the other | tk-c8hl47c, tk-ni0i48p, tk-pdc0ovc, tk-w0hkwos; section 7 |
| 4. The readers move | The sign-off's headline reads `prstatus`. I5 reads every closed bead with a PR. I2 reads the kept values. | unit 3 | section 6 |
| 5. Docs, warrants and the plan | The pages that describe the merge are rewritten to the flow as it stands once units 1 to 4 land: `refinery-merge-cadence.md`, `state-machine.md` (the kept values and their sentences, and the Checks vocabulary), `architecture.md`'s "How work moves" with both landing paths, `component-model.md`, `authority-map.md`, `design-convoy.md`'s gates under call 1, `gctk-architecture.md`'s rows and the merge section of `built-once-target.md`. The warrants' Covers lines move off retired paths. The plan's rows move as section 8 says. | units 1 to 4 | tk-cvffk5x, tk-r82qrrv |

**What each waiting member needs.**

| Member | Needs | Because |
|---|---|---|
| tk-1tfzr71.22, review lanes | the status placement, the approval decision's ownership, and units 2 and 4 | Its loop's verdict at each head is `prstatus`'s review input. Triage at each head owns the approval decision, through one withdrawal writer. It takes over the bring-current guard and audit (section 8). A conflict on a branch with an open PR comes to it as a rework child until its loop has a repair step for it. |
| tk-1tfzr71.21, GitHub intake | sections 3, 5 and 7, and unit 2 | It reads an approving review's message as feedback. It resolves the city's own threads once answered. It routes the monitor's `merge_conflict` to the refinery's prep, and takes nothing from its `blocked` class, which the monitor marks actionable for every PR GitHub reads BLOCKED, one waiting on your approval or on the city's status included (`classifyPullRequest`). It moves the PR-finishing rank and `prstatus`'s facts off the posture. It deletes the cadence driver and the files whose rows move to it. |
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
    `warrants.md`), for unit 5 and the retirement bead.

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
  the latest commit only. Auto-merge merges once every required review and check
  passes, and survives pushes from accounts with write access. A merge queue is
  available to this organization-owned public repository, but every required
  check would have to run on the queue's merge group. The city's per-head status
  cannot, so this design does not use one.
