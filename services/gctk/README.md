# gctk — gc-toolkit's CLI

`gctk` is gc-toolkit's command-line interface, built as one Go binary: the
documented, structured surface through which agents act on a city. Agents are
its users. A person can run any command and it should make sense, but no
command is shaped for ad-hoc human use. The command tree is cobra's, and a
command's generated help (`gctk <noun> <verb> --help`) and its code's doc
comments state what it does and how; this README is the map to them.

gctk links no beads library: its store adapter (`internal/gcbd`) reaches beads
through `gc bd` and the supervisor's API.

## Commands

| Command | What it does | Documented in |
|---|---|---|
| `bead holds` | what holds each bead named, from one read of the store: one status (blocked, held, unjudged or clear) with the waits behind it and whether each is the bead's own or an ancestor's, its own pending waits and when the last landed, why it is in flight, its arm, and its wait edges into another store, one JSON object per line, read from the store `--db` names or the one gc routes the first bead to | `gctk bead holds --help`, `internal/cli/bead.go`, `waits` |
| `bead stands` | where each bead named stands and whose move it is, from one listing of the store: its group in the helm board's words, the rule that placed it, what a person owes when the bead is itself the ask, the beads that rule names, how far the city carries it without a person and the bead that stops it, and where it stands by what it waits on, one JSON object per line, read from the store `--db` names or the one gc routes the first bead to | `gctk bead stands --help`, `internal/cli/beadstands.go`, `standing`, [docs/bead-standing.md](../../docs/bead-standing.md) |
| `bead arm`, `bead disarm` | arm a bead to start by itself once nothing holds it, on a formula through a pool, or remove its arm, each in one write under the bead's dispatch lock | `gctk bead arm --help`, `gctk bead disarm --help`, `arm` |
| `bead start-armed` | the deferred-dispatch order's pass: retire each arm that is no longer owed, and start each armed bead the pool's own serve rule would serve and nothing bd cannot judge holds, exactly once, printing one JSON line per arm; `--dry-run` writes nothing | `gctk bead start-armed --help`, `arm`, [docs/deferred-dispatch.md](../../docs/deferred-dispatch.md) |
| `bead park`, `bead place` | the operator's steering moves on a bead: a park, which holds everything under it that has not started behind a gate it files, born with its `blocks` edge, or behind a bead that exists, and refuses a bead in flight; and a placement, which gives a bead `hold:mayor` holds its parent or none, settles its priority, slings it or arms it while a wait holds it, and lifts the hold, each write taking its exit | `gctk bead park --help`, `gctk bead place --help`, `internal/cli/bead_steer.go`, `park`, `place`, [docs/steering.md](../../docs/steering.md) |
| `bead takeaway` | a bead's headline, the one line its handling concluded, with who wrote it, when, and whether anything still waits on it, in one update: each wait a `blocks` edge, or `--no-wait`'s settled mark. With `--release` its arm is removed first, then the same update reopens the bead, guarded on the status and the assignee it read, and assigns it to nobody or to the agent `--assign` names, each run beneath it ends, and `--route` slings it to a pool. The store is the one `--db` names or the one gc routes the bead to | `gctk bead takeaway --help`, `internal/cli/beadtakeaway.go`, `takeaway` |
| `deployment report` | the production-deploy-report order's pass over one rig: the newest deployments of an environment, Production unless `--environment` names another, read from GitHub in one call for the repository the rig's checkout names as its origin, and one patrol finding in the rig's store for a run of failed ones, filed and noted through `patrol-finding.sh` while they fail and its situation cleared once one succeeds; `--dry-run` writes nothing | `gctk deployment report --help`, `internal/cli/deployment.go`, `deployment` |
| `doctor run` | the doctor order's run: `gc doctor --json` under a deadline, never with `--fix`, recorded as one `gc-toolkit.doctor.ran` event whose payload names each failing check with the time it first failed and its streak, each check the run did not measure, each the accepted file accepts, and each monitor order's last good run; a run that did not complete carries the previous run's lists and exits 1 | `gctk doctor run --help`, `internal/cli/doctor.go`, `doctor` |
| `epic create` | filing an epic with its contract, each field in its own key, refused when the epic has no hypothesis and its parent is not an epic | `gctk epic create --help`, `internal/cli/epic.go` |
| `epic unweighed` | the time it read a rig's epics, which a portfolio sync marks each epic it weighs with, then each close and each latest shift of those epics that no sync has weighed, oldest first, one line each, from one read of the rig's epics, and a read that stops and says so when the store does not answer | `gctk epic unweighed --help`, `internal/cli/epic_unweighed.go`, `epic` |
| `lifecycle` | the plain write of a bead's `merge_result` outside the pending record, with the work record a landing writes, in one atomic update whose exit decides. It parses its own verbs and flags | `gctk lifecycle`, `internal/cli/lifecycle.go` |
| `mail notify` | the mail-notify orders' pass: for each session of an agent `--agents` names that can wake, its unread mail from another sender that no notice still queued will tell it of, answered with one wait-idle nudge naming each new message's sender, once for each message, which the pass's ledger keeps while the message stays unread | `gctk mail notify --help`, `internal/cli/mail.go`, `mail` |
| `memory due`, `memory apply`, `memory settle` | the learning loop's memory intake, which the feedback distiller's steps call: the agent memory notes due for its judge as JSON, oldest first, read from each memory directory Claude Code names for a session in each rig's checkout and the city's root; the judge's decision on each note recorded on its directory's list, a dropped note's text kept before it goes; and each note's wait ended once its fix has landed on the default branch, or with the note due again when it ended with none, with one finding for a place Claude Code names no directory for | `gctk memory --help`, `internal/cli/memory.go`, `memory`, `internal/claudecode` |
| `distiller start` | the feedback-distiller order's start: the pack's home rig, the one rig whose checkout holds a `pack.toml` naming the gc-toolkit pack, and the polecat pool `gc agent list` places there, and one run of `mol-feedback-distiller` slung to that pool unless a run is open in the rig's store, under a lock that keeps overlapping starts apart; a city with no home rig, a suspended one, or another start holding the lock starts nothing, and a read that fails, a second home rig, a pool that is not one or a lock that cannot be taken starts nothing and exits 1 | `gctk distiller start --help`, `internal/cli/distiller.go`, `distiller` |
| `pr compose` | a PR's title and body as the bead that owns it says they should be: its title with the conventional-commit type a repository's title check requires, and its body's managed summary region and branch-beads section, each read by its markers and kept current while the text people add stays as it is; with `--edit`, the open PR's title and body brought to that composition, each edited only where it differs | `gctk pr compose --help`, `internal/cli/prcompose.go`, `pr` |
| `pr summary` | the account of what a change does, for its PR: the bead's PR summary and the change's subject line as its title, recorded in one write whose exit decides, or the summary recorded, printed for a reader of the PR's text | `gctk pr summary --help`, `internal/cli/prsummary.go`, `pr` |
| `pr status` | a PR's status (working, merging, needs-review or needs-attention), the one derivation the `status:` label and the helm board share, and the open human gates that hold it, which `gc-helm engage` offers; for a PR on Gas Town's pending record, the pr domain's evaluator decides it over the store and the GitHub read the one-PR update saved on the PR's bead, so the verb reads no GitHub, and each condition not met follows it | `gctk pr status --help`, `internal/cli/prstatus.go`, `prstatus`, `pr` |
| `pr record` | the refinery's record of the PR a bead owns as pending until its merge is verified, in Gas Town's two writes under the store's record lock, each guarded on the status and assignee it read, so a bead that a close or a release reached first gets no record | `gctk pr record --help`, `internal/cli/prland.go`, `pr`, `pr/record` |
| `pr poll` | one pass of the PR watch: the PRs the store's live beads own asked about in one request for each 50 in a repository, reading their cheap signs and no detail, and the one-PR update run for each PR whose signs moved or whose saved merge state GitHub had not computed, taken from every repository in a shuffled order, none started past 90 seconds, so a pass in which nothing moved writes no bead but that of such a PR | `gctk pr poll --help`, `internal/cli/prwatch.go`, `pr` |
| `pr compare` | one pass of the net, every hour: the PRs the store's live beads own read in full in one request for each 10 in a repository, their signs, merge state, review decision, merge-queue flags, review threads' resolutions, posts' times, the city's reactions on inline comments and required check runs, with each list read on to its end and no post's text, and the one-PR update run over each part of each PR that differs from its saved read, taken in a shuffled order, none started past 3 minutes, so a thread resolved, a thread the city's reaction answered or a post edited with no sign moved reaches the saved read within one pass; then the rig's own repository searched for the city's labels, a page at a time until 20 PRs no live bead owns are found or the results end, and each cleared through the labels' writer in a shuffled order | `gctk pr compare --help`, `internal/cli/prwatch.go`, `pr` |
| `pr refresh` | the one-PR update, the one writer of GitHub's side on a bead: the parts of the PR its signs say moved, or the net finds differ, or every part for the re-read the landing order has made before a merge, read and saved on the live bead that owns it, in four parts that each keep the instant their read was sent, in one write under the store's record lock guarded on what it read, with pr_state and pr_last_checked_at on a bead on the pending record | `gctk pr refresh --help`, `internal/cli/prwatch.go`, `pr` |
| `pr reconcile` | one run of the landing order over the store's pending records, the second of the PR's two loops: every record decided through one read of the store, on the read the PR watch saved on its bead and the store alone, with no read of GitHub for a record that owes no act, and each that owes one decided again under the store's record lock, taken in a shuffled order, none started past 45 seconds and each stopped at 30: the withdrawals filed on a bead carried out on the act's own reads of what they dismiss, a draft whose review result passed at its validated head marked ready, a PR ready on the saved read re-read in full by the one-PR update and merged with its head pinned only on what that read saved, a bead closed once its merge commit is on the target, the bead of a PR a ruling retired closed through `bead-rehome.sh` once the saved read shows the PR closed, a changed head sent back to the refinery, and each exception kept blocked behind a human gate, and each owned PR's `status:` and `held:` labels written through their one writer, reading nothing of the PR first, where the ones the bead's read saved differ from what the store derives, with nothing of GitHub's written but by the one-PR update and nothing recorded of an act that did not complete | `gctk pr reconcile --help`, `internal/cli/prland.go`, `pr`, `pr/record`, `listing`, `prstatus` |
| `pr draft` | the PR a bead owns returned to draft before a writer of the city pushes onto it, read from its draft flag first and converted only when it is ready, so a round's later pushes change nothing | `gctk pr draft --help`, `internal/cli/prcycle.go`, `pr` |
| `pr withdraw` | the withdrawal of the approvals a material change leaves behind: a bead that blocks the bead that owns the PR and names the head, which the landing order carries out by dismissing each approval given on a commit that does not contain it | `gctk pr withdraw --help`, `internal/cli/prcycle.go`, `pr` |
| `pr push` | a converse sitting's push of its checkout's commits onto the branch of the PR a bead owns, once it proves that its conversation holds the PR and that the checkout's origin is the PR's repository: the PR returned to draft first, then the checkout's HEAD pushed under the lease through the pack's `branch-push.sh`, beside any review run that works the branch; `--check` proves the holding and changes nothing | `gctk pr push --help`, `internal/cli/prpush.go`, `pr` |
| `reaction check`, `reaction sling` | whether a bead may take a first reaction: the refusals of a bead whose next move is someone's (its kind, its status, an assignee, a route or an arm, a dispatch hold, an open conversation, a live run, an open human gate), each with its exit code; the check is the reaction's own first act and writes nothing, and the sling then slings a run of `mol-first-reaction` through the rig's proactive pool | `gctk reaction check --help`, `gctk reaction sling --help`, `internal/cli/reaction.go`, `reaction` |
| `reaction sweep` | the proactive order's pass: one ready read of the rig's store by priority, the raw input among it, less each bead a live run works, slung a first reaction each until the sweep's deadline, one JSON line per candidate; `--dry-run` slings nothing | `gctk reaction sweep --help`, `internal/cli/reaction.go`, `reaction` |
| `reaction dispose` | one exit of a first reaction on its subject, its writes in their order: a release to a pool or a hand-off to the named agent whose work it is, a hold on what it waits for, a validating closer now or once the beads that end its job land, or a human gate for the operator, with or without an action Accept runs; intake holds what it does not admit for placement | `gctk reaction dispose --help`, `internal/cli/reaction.go`, `reaction` |
| `reaction accept` | the acceptance of a recommendation a recommend exit left: under the bead's acceptance lock, its first write the arm's removal, the dispatch input recorded on the recommendation's gate, the gate answered and read for which answer it took, the formula slung at the bead once under the acceptance's token, the hold lifted and the dispatch recorded; a run finishes an acceptance an earlier one left | `gctk reaction accept --help`, `internal/cli/reaction.go`, `reaction` |
| `refinery stuck` | the refinery-queue-detect order's look: each open handoff assigned to a rig's refinery that carries a branch and no merge_result, has gone four hours without a write, and that nothing holds by `bead holds`, recorded as one `gc-toolkit.refinery-queue.stuck` event when it finds one; a rig whose queue does not read is left out and the run exits 1 | `gctk refinery stuck --help`, `internal/cli/refinery.go`, `refinery` |
| `review checks`, `review guidance` | the check index at a commit, with the rig's index laid over the pack's: every row, one check's row, or the checks of a check_set that gate a transition; and the rig's guidance for a check at the reviewed commit, or the guidance a change edits | `gctk review checks --help`, `gctk review guidance --help`, `internal/cli/review.go`, `review` |
| `review passed`, `review ask` | a review run's loop check, which passes an iteration on what the run's steps wrote and the asks open on the bead, and with `--record`, at the iteration that ends the loop, writes the run's result for the head and target it judged, in review_results under the store's record lock, with the asks it answered closed; and an ask on the bead that owns a PR, filed once per source and reason | `gctk review passed --help`, `gctk review ask --help`, `internal/cli/review.go`, `review` |
| `review step`, `review output`, `review comment` | for a review run's steps: what a step judges (its run, the PR, the iteration, the head that iteration judges and the change triage reads there), with `--stands`, triage's refusal of a run whose vars do not name the record or whose PR moved; the check of the output a step wrote, printed as the store keeps it, with the guidance-edit guard on a correctness approve; and the head's one comment, each lane's verdict with its findings and rulings | `gctk review step --help`, `gctk review output --help`, `gctk review comment --help`, `internal/cli/reviewrun.go`, `review` |
| `rig` | actions taken on the rig: running its checks and recording each result against the commit, and running a copy of its UI from a checkout for a demo capture or a person | `gctk rig --help`, `internal/cli/rig.go`, `internal/cli/rig_serve.go`, `internal/rig` |
| `session title` | giving a session a title its Gas City record and its terminal both show, made of the bead it is about (`--subject`), the pull request it is about (`--pr`) and its topic (`--topic`). A Claude Code or Codex terminal takes the title at the session's next boundary, a few seconds after the turn ends | `gctk session title --help`, `internal/cli/session.go` |
| `session progress` | the seat-progress-detect order's look: each busy pool seat whose claim it holds under the identity its writes carry, and that has written nothing to the claim's store or the city's for three hours since it last woke, recorded as one `gc-toolkit.seat-progress.stalled` event when it finds one | `gctk session progress --help`, `internal/cli/session_progress.go`, `session` |
| `version` | the revision the binary was built from | `cmd/gctk` |

Logic gctk does not hold runs as shell scripts. Among them are the rest of the
merge cadence (`gate-ensure`, `pr-open`, `pr-facts`, `signoff`) and
`refinery-reconcile.sh`, the driver that runs the cadence's arms.
[docs/gctk-architecture.md](../../docs/gctk-architecture.md) states which pack
logic moves into gctk and the shape it takes there.

## Bridges

A shell script that only execs a gctk command is a bridge for callers that do
not call gctk yet, and it goes away once they do. A bridge is not a contract
gctk keeps: matching a script's flags and output byte for byte is not a goal,
and neither are tests that pin usage text. `assets/scripts/lifecycle.sh` execs
`gctk lifecycle`, and `assets/scripts/epic.sh` execs `gctk epic` for the work
skill, whose examples call every writer through the pack command. Each finds
the binary through `assets/scripts/gctk-resolve.sh`, which states the
resolution chain, and none has a shell fallback. With no binary to run, a
bridge refuses the call with exit 1 and names the `gctk-build` order that
publishes the binary. A caller reads a refused write as a failed one: the merge
cadence's arms try it again on their next pass, and the refinery's direct
landing on its next patrol. A fresh city has no binary until that order's first
build, and a city whose build failed keeps serving the last good binary.

`assets/scripts/pr-status-label.sh` writes the `status:` and `held:` labels in
shell and takes their values from `gctk pr status`. It resolves the
binary the same way, and when there is none, or the binary is too old to carry
`pr status` or its `--json`, it leaves the labels unchanged. `gctk pr reconcile`
and `gctk pr compare` run it through the runtime adapter. The landing order
compares each owned PR's saved labels with the same derivation first
(`listing.PRLabels`, and `prstatus.Labels` for the labels' names), and runs
`reconcile` or `clear` only where they differ. The net derives nothing: it
searches for the labels `prstatus.LabelNames` lists and runs `clear` on each PR
it finds that no live bead owns. `gc-helm.sh` engage
lists what holds a bead from the reasons in the same verb's `--json` answer, and
the helm board imports the package behind it, `prstatus`, so the labels, engage
and the board read one definition of what holds a PR. For a PR on Gas Town's
pending record, the verb and the rig board ask the pr domain's evaluator over
the store and the GitHub read the one-PR update saved on the PR's bead, the
board through its listing (`listing.PRAnswers`), so none of them reads GitHub.

The refinery's merge-push step (`refinery-publish.sh`) takes a PR's title and
body from `gctk pr compose`, so an opened PR and a later refresh read one
composer, and a review run's push (`review-run.sh push`) edits the open PR to
the same composition with `--edit`.
Each finds the binary through `gctk-resolve.sh`'s `gctk_path`, and with no
binary, or one too old to carry the verb, it opens no PR and edits no body or
title that pass.

`assets/scripts/pr-reconcile.sh`, the landing order's script
(`orders/pr-reconcile.toml`), names the rig's refinery from the roster and execs
`gctk pr reconcile` through `gctk-resolve.sh`. With no binary to run, it refuses
the run with exit 1, and the order's next run tries again.

## rig

`gctk rig` holds the actions gctk takes on a rig, and checks are the first of
them. `test`, `lint` and `typecheck` run the command their caller passes and
record the result against the commit it ran at. `setup` and `build` run their
command and record nothing. In a checkout they find clean, they put back what
the command changes, other than files git ignores, so the recorded checks that
follow in the same checkout can run. The caller passes every input: the
command, which test run it is, and, when the rig declares no command for a
check, that there is nothing to run. gctk reads no formula var and works out no
diff.

Every place that runs a rig's declared checks calls it, passing the command
from the rig's formula vars: `mol-polecat-work`'s workspace-setup, its
preflight-tests at the base commit and its self-review, the refinery's
run-tests at the merged head, and the correctness review when the pinned
commit has no record to read. `assets/scripts/self-review-check.sh`, the
self-review's exit condition, and `assets/scripts/review-evidence.sh`, which
every review's gather runs, read the records with `--check`. Each caller finds
the binary by one line, the `gctk-bin` block, which takes `$GCTK_BIN` or else
the city's build and calls no `gc`, because `self-review-check.sh` runs where
`gc` can fail.

The records live under the rig clone's git common directory, which every
worktree of the clone shares and which outlives any one of them:

| Path under the git common directory | What it holds |
|---|---|
| `gc-rig-checks/<check>/commits/<commit>.json` | the check's record for that commit |
| `gc-rig-checks/test/trees/<tree>.json` | the full-suite test pass every commit with that tree reads |

`--publish-bead <bead>` copies a record onto the bead's `rig_check.<check>` key,
a key rig declares through the ledger, in one write that nothing reads back. A record says what a command did at
a commit and never whose failure it is: a caller that judges a recorded fail
pre-existing writes that judgment on a bead with
`assets/scripts/rig-check-pre-existing.sh`. `gctk rig <check> --help` states the
flags, which record answers a call, and the exit codes. `specs/tk-1hazlo2/rig-checks.md`
records the design and its measured cost.

`serve` runs a copy of the rig's UI from the checkout it is called in: the serve
command its caller passes, with bash at the checkout's top, on a free loopback
port it is given as `$PORT`, through `assets/scripts/demo-engine-lib.sh`, which
`GCTK_SCRIPTS_DIR` names, and which runs it inside the sandbox it defines for a
demo capture when the rig keeps that sandbox. The copy is up once it answers on that port, or once
the command prints the URL of the app it brought up, such as an iOS app on a
simulator, and the report's `app_url` says where its app is. A demo capture's
`--serve` starts one with no address and points the engine at its `app_url`. The
`converse-edit` skill starts one with the city's publish command and address
pattern for the operator. Each caller reads the rig's `ui_serve_command`, and
the city's `ui_publish_command` and `ui_address_pattern`, from the rig's formula
vars and passes them. A copy is a process group led by a detached gctk,
`rig serve --lead`, which ends the group when the serve command ends, and Gas
City's orphan sweep ends it once the session that started it has ended. Starts and
stops of one checkout take turns under a lock beside the copy's record, so two
starts that find a copy that died run one copy in its place, and two that ask to
publish a running copy run one publish command. The record and the lock live
beside the check records:

| Path under the git common directory | What it holds |
|---|---|
| `gc-rig-serve/<hash of the checkout's path>/` | a copy's port, its commands, its app's URL once its serve command prints one, its leader's pid and start, and its logs |
| `gc-rig-serve/<hash of the checkout's path>.lock` | the file a start or a stop of that checkout's copy holds an flock on while it runs, which the kernel releases if the call dies |

`gctk rig serve --help` states the flags, the states a call reports and the
exit codes. `specs/tk-rymdhac/gas-city-search.md` records what Gas City offers
for it.

## Build and deploy

`orders/gctk-build.toml` runs `assets/scripts/gc-build.sh gctk --deploy`
whenever its check, `gc-build.sh gctk --due`, answers that a run is owed and
due, and `gc-build.sh` states that rule, when it builds and what it writes. It
publishes the binary under `<city>/.gc/services/gctk`, and nothing builds in a
caller's path, so a gctk change goes live when the order next publishes it, on
the first pass after the change reaches the checkout, while a script edit is
live from the working tree at once. A build that fails is tried again every
five minutes. The bridges run whatever binary the order last published.
`doctor/check-cadence-live` reports a deployed binary built from sources other
than the checkout's.

## Layout

```
cmd/gctk/            the binary's entry point, and the revision `version` prints
internal/cli/        the command tree, each command with its help, flags and exit codes
internal/lifecycle/  a bead's headline and the cap gctk's writers hold it to
internal/ledger/     typed bead records: each key's declaration, one write per act
                     whose exit decides, snapshots, and a pass that reads each bead once
internal/host/       the host adapter: the processes gctk starts and signals, the process
                     table, and the loopback ports and their listeners
internal/host/fake/  the host adapter's in-memory fake, for the domains' tests
internal/gascity/    the runtime adapter: gc sling, an agent's default formula from the city's
                     config, the city's root, its rigs, the settings file its Claude sessions
                     start with, the pack's scripts that ask a person or file a finding, and
                     the one that ends a run
internal/gascity/fake/  the runtime adapter's fake, which records each call and answers as a test says
internal/gcbd/       the store adapter: bead reads and writes through `gc bd` and the
                     supervisor API, the store's listing, and its blocked set
internal/gcbd/fake/  the store adapter's in-memory fake, for the domains' tests
internal/gcbd/fakegc/  the compiled fake gc, which answers gc's command line from a store in
                     files for the shell suites, and its contract test against the city's bd
internal/daemon/     finding the supervisor API the store adapter's reads go through
internal/git/        the git subprocess seam: one git command per call, in a named directory
internal/gh/         the GitHub adapter: one `gh api` call per read, paged to its end, the
                     cheap question, the signs of up to 50 PRs in one call, and the net's
                     full read of up to 10
internal/gh/fake/    the GitHub adapter's in-memory fake, for the domains' tests
internal/feedback/   the pack's one definition of feedback, pr-post.sh's feedback-def, run
                     through jq
internal/claudecode/ the Claude Code adapter: where a session started in a directory keeps
                     its auto memory, asked of Claude Code itself
internal/claudecode/fake/  the Claude Code adapter's fake, which answers as a test says
internal/rig/        rig's runner, its commit-keyed record store, and a copy of the rig's UI
arm/                 the arm's verbs and its start: what arm refuses, the dispatch lock, and the
                     steps that send each armed bead once
arm/record/          the arm's keys, which it owns, the arm they decode to, and every write to them
pr/                  the pr domain: whether the PR a bead owns is ready to merge at its
                     current revision, from the store, GitHub and the definition of
                     feedback, or from the store and the GitHub read the one-PR update
                     saved there, which the PR watch reads when GitHub shows it moved,
                     or when the net's full read finds it differs; the account of the
                     change its author records, the PR summary; and what the PR's
                     title and body say: its title, and its body's managed summary
                     region and branch-beads section, with the renders they replaced
                     pinned under testdata
epic/                which closes and shifts of a rig's epics no portfolio sync has weighed,
                     from the ruling's keys and each sync's mark, read-only
memory/              the memory intake: each memory directory's list of the notes the
                     distiller's judge kept, the due notes, the judge's decisions, and the
                     waits that end once a fix lands
distiller/           where the city's one distiller run starts: the home rig, its polecat
                     pool, and whether a run is open there, read-only but for the sling
                     and the start's lock
prstatus/            the PR status derivation, exported for the helm board
listing/             one pass's read of a store for the helm board: every live bead, the
                     closed beads under a parent, the keys it decodes, and waits',
                     prstatus's and the pr evaluator's answers from the same rows
waits/               what holds a bead, from one snapshot: the rule by where the work is, the
                     in-flight test, the run link's copy and the keys it reads, read-only
standing/            where a bead stands and whose move it is: its group in the helm board's
                     words, the rule that placed it, its ask and the beads that rule names,
                     how far the city carries it and where it stands by what it waits on,
                     from waits', prstatus's and queue's answers, read through the Store a
                     listing implements
standing/person/     the rules about one bead: a human gate, a bead only a person clears, and
                     one that waits on work of its own first
review/              the review domain: the check index and a rig's guidance at a commit; the
                     shape a review run's steps write, the loop's pass rule over it, the run's
                     result in review_results, and the asks a run works, in review_checks
takeaway/            a bead's takeaway: its headline and the keys beside it, which it owns,
                     its wait edges, and the release that stops the bead or sends it on
reaction/            a bead's first reaction: each exit's writes in their order, intake's rule,
                     an emergency's check of the default branch, the form a named agent takes
                     a bead in, whether a pool or an agent would take one, and the
                     recommendation key, which it owns
queue/               the order work is expected to land in, for the helm board: bd graph's
                     execution layers over waits' answers, then the pool's claim order,
                     each bead's row and waits read through the Store a listing implements
key-registry.json    every declared key, generated from the declarations
```

## Running the tests

```bash
cd services/gctk && go test ./...          # every gctk package
cd services/gctk && go test ./cmd/gctk -run TestKeyRegistry -update   # write key-registry.json again
cd services/gctk && GCTK_STORE_ACCEPTANCE=1 go test ./internal/gcbd ./arm -run TestStoreAcceptance -v   # the city's bd on a scratch store
cd services/gctk && GCTK_STORE_ACCEPTANCE=1 go test ./internal/gcbd/fakegc -run TestContract -v   # the fake gc against the city's bd
cd services/gctk && GCTK_CITY_ACCEPTANCE=1 go test ./internal/gascity ./distiller -run TestCityAcceptance -v   # the city's gc on a scratch city
bash assets/scripts/lifecycle.test.sh      # lifecycle through its bridge
bash assets/scripts/epic.test.sh           # epic through its bridge
bash assets/scripts/gctk-resolve.test.sh   # which binary a bridge runs
```

A shell suite that reaches `lifecycle.sh` or `epic.sh` builds the
binary from the checkout itself, and fails if it cannot.
