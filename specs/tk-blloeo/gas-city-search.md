---
name: Gas City search for the status label's merging value and the merge pass's blocked causes
description: The search the arch check asks for before the pack adds the status label's merging value and clear verb, the merge pass's classification of an approved PR it cannot merge, the pr.machine_cause key, blocker-holder.sh and status_label_clear_owed. What Gas City, bd, and the packs Gas City bundles and publishes ship near those needs, read at named upstream commits, and why the pack keeps its own label and machine axis. Read it when checking whether the machine axis or the status label can move onto a Gas City primitive.
---

# Gas City search for the status label's merging value and the merge pass's blocked causes

The `status:` label on the rig's pull requests gains the value `merging`, and
comes off a PR once it merges or closes. Behind the label, the merge pass
reads an approved PR's required checks before it names what holds the PR,
records `blocked` only for a cause no automated actor will clear, and records
that cause as a value, `pr.machine_cause`. A new script answers whether an
automated actor holds an anchor's blockers, and a new key records a label clear
that did not land. So the arch check asks what Gas City already ships for each
piece, and whether the causes are a pack noun that needs a warrant
([review-arch.md](../../docs/review-arch.md#the-checks), checks 1 and 2).

Gas City has one classifier of a pull request's readiness, the `gc` binary's
PR monitor. It reads only a PR's draft flag, its merge state and its check
rollup, so it calls every `BLOCKED` PR blocked, a required check still running
included, and it records its class on a repair bead it files, not on the bead
whose PR it is. bd keeps operational state as a label through `bd set-state`,
which cannot clear a value or tie it to the verdict and the head it qualifies,
and Gas City reads bead labels as state only for its dispatch holds. bd's
custom statuses would take the place of the bead's own status. No pack that Gas
City bundles or publishes reads a branch's rules to tell a block from a wait,
keeps a label on a pull request that says whose move it is, or judges whether
an automated actor holds a blocker. Gas City ships no retry for a failed write
to an outside service. So the pack keeps its machine axis and its owed-clear
record, and the warrants *Machine axis* and *Owed status label clear* in
[warrants.md](../../docs/warrants.md) say why.

## The surface and the need

The change adds or widens these pieces of surface:

- **`merging`, a new `status:` value.** `assets/scripts/pr-status-label.sh`
  is the one writer of the workflow-owned `status:` label on the rig's pull
  requests. An open PR carries exactly one value, and the change adds `merging`
  for an approved PR that the city is landing and that nothing known blocks.
  Package `services/gctk/prstatus` decides the value, through `gctk pr-status
  derive`, and the helm board derives its phase from the same package.
  `ensure` now also corrects a label whose description no longer says what its
  value means.
- **The `clear` verb.** `pr-status-label.sh clear` takes every `status:` label
  off a PR that merged or closed, where GitHub's own Merged or Closed state
  takes over. `gctk merge` runs it for a merge it made or recovered, and
  `pr-facts.sh` for a merge or a close it records, each before the write that
  takes the anchor out of every enumeration of open PRs.
- **The merge pass's classification of an approved PR it cannot merge.**
  `gctk merge` (package `services/gctk/internal/cli`, `handleBlocked` and the
  `BEHIND` and `DIRTY` arms in `merge.go`) already read the base branch's
  effective rules (`GET /repos/{owner}/{repo}/rules/branches/{branch}`) and,
  where they require it, the PR's review threads. It recorded `blocked` for
  every `BLOCKED` PR except one still owed an approval, a required check still
  running included, and for every `DIRTY` and `BEHIND` one with nothing in
  flight. It now reads the required checks as well. A required thread left
  unresolved, a required check that failed, a conflict whose merge-in rework
  something defers, a base the branch is behind, and a rule the pass cannot
  name each record `blocked`. A required check still running, or one GitHub
  shows as Expected, records `progressing`, and so does a conflict that
  `pr-facts.sh`'s conflict arm will file a merge-in rework for. A read that
  does not answer records nothing, where it used to record `blocked`.
- **`pr.machine_cause`.** The value the merge pass records beside a `blocked`
  verdict, one of `review-threads`, `check-failed`, `conflict`, `behind`,
  `blocker` and `rule`, declared as `causes` under `[machine_axis]` in
  `lifecycle/lifecycle.toml`. `gctk merge` writes it in the one lifecycle write
  that records `pr.machine=blocked@<head>` and the `pr.machine_reason`
  sentence, and unsets both whenever it records any other verdict.
  `prstatus.Derive` reads it for the label and the board, and `gate-ensure.sh`
  reads it before it replaces a blocked verdict.
- **`assets/scripts/blocker-holder.sh`.** It answers whether an automated actor
  holds the live blockers an anchor's merge waits on. A route to anything but
  `human`, a claim by anything but `human`, or a live run working the blocker
  counts as an actor. The merge pass and `gate-ensure.sh` both ask it, so the
  two writers of `pr.machine` reach one answer.
- **`status_label_clear_owed`.** A clear that did not land, valued with the PR
  number. `gctk merge` carries it in its record, and `pr-facts.sh` writes it
  before its own. Every full pass of `pr-facts.sh` lists the anchors carrying
  it, in any status, retries each clear, and unsets the key once it lands.

The needs behind them:

- One label on each open PR that says whose move it is, derived from what the
  city records rather than from GitHub's merge state alone, and removed when
  the PR is resolved.
- A verdict that tells a blocker no automated actor will clear from a wait the
  city is already acting on. GitHub reports `BLOCKED` for a required check
  still running as it does for a wedge, which was the false needs-attention on
  an approved PR waiting for its checks.
- The reason for a blocked verdict as a value a reader keys on, recorded and
  cleared with the verdict, so no reader parses the sentence.
- A terminal label write that survives a failed GitHub call after the anchor
  has left every enumeration of open PRs.

## Where the search looked

Each was read on 2026-10-27:

- Gas City at main `e73ebbfb48fd`: its documentation, its engineering docs,
  the `core` pack and the example packs in its repository, and its source. The
  search covered pull request monitoring and readiness, `mergeStateStatus`,
  `mergeable`, review decisions and review threads, branch protection and
  rulesets, required checks and check rollups, GitHub labels, bead labels used
  as state, `bd set-state`, what decides who holds or owns a bead, retries and
  outboxes for a failed write, and what the documentation says about a pack's
  own metadata keys and states.
- Every pack in `gastownhall/gascity-packs` at main `dac12a4a802c`, and the
  packs Gas City bundles, at the packs commit its `go.mod` pins,
  `66c672b5ed00`. Each pack was searched for a GitHub label write or read, a
  read of a PR's mergeability or blockers, a PR's state recorded on a bead, a
  failed write recorded and retried, and a blocker judged to be held by an
  automated actor or by a person. Each pack's hits were tallied by distinct
  line before they were read, and code was told apart from prose an agent
  follows.
- bd at main `43f41374a34d`: labels as state, `bd set-state` and `bd state`,
  gates, its GitHub sync, claims and their leases, and metadata.

Each passage quoted below from docs.gascity.com or beads.gascity.com was also
found on the live site.

## What Gas City ships near the need

### The gc binary's pull request readiness monitor

Gas City has one classifier of a pull request's readiness, in the `gc`
binary. A city declares a monitor as a `[[github.pr_monitor]]` entry
([GitHubPRMonitor](https://docs.gascity.com/reference/config#githubprmonitor)
in the configuration reference), which names a repository, its base branches,
the rig that owns repair work and the route that work goes to.
[`gc github pr backfill`](https://docs.gascity.com/reference/cli#gc-github-pr-backfill)
"reports PRs that need repair: failed checks, merge conflicts, blocked
mergeability, or branches behind their base", and with
`--create-repair-beads` it creates "deduped repair beads for actionable PRs".

The classifier is `classifyPullRequest` in package `githubmonitor`. Its query
(`pullRequestsQuery`) reads each open PR's draft flag, its
`mergeStateStatus` and its head commit's check rollup, and nothing else that
bears on the merge. A draft is `draft`. Any failed check, required or not, is
`failed`. Otherwise `DIRTY` is `conflicted`, `BEHIND` is `behind`, `UNSTABLE`
is `failed` and `BLOCKED` is `blocked`, each of them actionable. Pending
checks make a PR `pending` only when its merge state is none of those, so a
`BLOCKED` PR whose required check is still running is `blocked` and
actionable. It reads no branch rule, review thread or approval.

What it records goes on a repair bead it files, not on the bead whose PR it
is. `ensureGitHubPRRepairBead`, in the `gc` command's source, finds an open
repair bead by owner, repository, PR number and head commit, or creates one.
It stamps `github.state`, `github.failure_kind`, `github.merge_state_status`,
`github.failed_checks` and `github.pending_checks` on it, with a
`gc.routed_to` of the monitor's repair route and the labels `github`, `ci`,
`repair` and `pr-monitor`, and attaches the monitor's repair workflow so a
pool works the repair.

Only that command runs the monitor. No order in the bundled `core` pack calls
it, and no code outside package `config` reads a monitor's `poll_interval`,
webhook secret or `merge_queue` policy, though the reference documents them.

It does not cover the need. It cannot tell a required check still running
from a wedge, because it reads no branch rule, and that is the false
needs-attention this change removes. It reads a failed advisory check as a
failed PR, where the merge pass judges only the required ones. Its classes
say what a pool should repair, while the pack's `blocked` names what no
automated actor will clear. And its record sits on a repair bead keyed by the
PR and its head, where neither the label nor the board looks.

### A pull request's end: bd's `gh:pr` gate

bd's [`gh:pr` gate](https://beads.gascity.com/cli-reference/gate) waits for
a pull request to merge. `bd gate check` reads the PR with
`gh pr view <id> --json state,title`, resolves the gate on `MERGED` and
escalates it on `CLOSED`. The bundled `core` pack's `gate-sweep` order runs
`gc bd gate check --type=gh --escalate` on a 30-second cooldown. The gate
reads only whether the PR has ended, nothing of what blocks it, and closing a
gate releases the step it blocks. It would tell the pack when to take the
`status:` label off. The writers that clear the label are the ones that
record the merge or the close, so they already know the moment.

### GitHub labels

No Go code in Gas City writes or reads a GitHub label, and neither does the
`core` pack. Its query for the PR monitor fetches no labels.

The nearest vocabulary is a convention of Gas City's own repository. Its
contributor guide, `CONTRIBUTING.md`, lists "Pull Request Pipeline Labels" for
the project's own review-and-merge pipeline, among them `status/needs-review`,
`status/reviewing`, `status/merge-ready`, `status/merge-queued` and
`status/merge-failed`, "applied by maintainers and by that automation". No
code in the repository writes those pipeline labels, and neither `gc` nor a
pack carries the automation that does, so a city gets none of it.

Among the published packs, one writes a label on a pull request. The
`pr-review` pack's `mol-adopt-pr` and `mol-pr-merge-only` formulas tell the
agent to run `gh pr edit <number> --add-label "status/needs-info"` when a PR
conflicts and its author must rebase it. No pack removes that label or any
other, and no pack keeps one status label per PR. The `github` pack reads
labels: its README's example rule starts an order, `pr-review-request`, when
`status/needs-review` is added to an open PR, and no pack ships that order.
The `gascity` pack stores an issue's labels on the bead it files for the
issue. Gas City bundles neither `pr-review` nor any other pack that writes a
PR label.

So nothing Gas City ships or publishes writes a label that says whose move a
PR is, or takes one off when the PR ends. The pack writes its `status:` labels
through `gh label` and `gh pr edit`, GitHub's own commands.

### Merge readiness in the published packs

No pack, at either commit, decides anything from the values of
`mergeStateStatus`, a review decision, the required flag of a check, or a
branch's rules or rulesets. The nearest:

- The `gstack` pack's `land-and-deploy` skill fetches `mergeStateStatus` and
  never reads it. It stops on a `CONFLICTING` PR, waits while the checks it
  calls required are pending and stops on failing ones, but the fields it
  fetches carry no required flag. It records nothing on a bead.
- The `pr-review` pack's `mol-adopt-pr` and `mol-pr-merge-only` read
  `mergeable` and rebase a `CONFLICTING` PR or ask its author to, and wait on
  `gh pr checks` without telling a required check from an advisory one. A PR
  ready to merge gets `merge_ready: true` in the notes of the run's root, and
  a maintainer merges it, through the mayor. Its `mol-pr-ci-diagnose` sorts a
  PR's checks into `green`, `pending`, `failing_infra`, `failing_code` or
  `no_checks`, in the run's notes.
- The `gastown` pack's `pr-merge-reconcile` command, at the packs' main and
  not at the bundled pin, keeps a `merge_strategy=mr` bead blocked until its
  PR merges. It reads the PR's state, head and merge commit, records
  `pr_state` (`open`, `merged`, `closed_unmerged` and others) on the work
  bead, and reads nothing of what blocks a merge.

Each is the pack's own judgment or record, in its own keys or notes. None reads
a branch's rules, so none can tell a required check from an advisory one, or a
block nobody will clear from a check still running.

### Labels as state in Gas City

Gas City reads bead labels as state for one purpose, its dispatch holds. The
engineering doc *Hold and Blocked Label Conventions* sets them for the
project's own bd tracker: a `hold:<value>` label, set with
`bd set-state <id> hold=<value>`, means "I am paused pending a specific actor
or condition", and "Only two values are canonical", `hold:mayor` and
`hold:external`. Package `beadmeta` declares both in `DispatchHoldLabels`, and
the dispatcher reads them so a held bead is not handed out as work. The doc
retires a plain `blocked` label in favor of bd's `blocked` status. It also
names a `maintainer-pr-review` pack, with its own labels and metadata, that
Gas City neither bundles nor publishes, so the search could not read it.

A hold says what an agent should not do with a bead. The machine axis says
what the merge cadence can do with a pull request, and its `blocked` verdict
holds nothing back: the refinery still owns the anchor, and the pass reads it
again next time. No Go code in Gas City runs `bd set-state` or `bd state`.

### State on a bead in bd

bd keeps operational state on a bead as a label. The
[Labels](https://beads.gascity.com/core-concepts/labels#labels-as-state-cache)
page's section "Labels as State Cache" gives the convention:
`<dimension>:<value>`, one value per dimension, with an event bead recording
each change. "Events are the source of truth. Labels are a cache for fast
queries." Its best practices say to "Keep value sets small - 2-4 values per
dimension". [`bd set-state`](https://beads.gascity.com/cli-reference/set-state)
applies the convention in one command. In bd's source (`runSetState` in
`cmd/bd/state.go`) it files a closed event bead as a child of the subject,
then swaps the dimension's label in one guarded label patch, and writes
nothing when the value is unchanged. `bd state` reads one dimension and
`bd state list` reads them all.

It does not fit the cause, or the verdict the cause qualifies:

- A cause is true only beside a `blocked` verdict at the head that verdict
  was recorded at. A state label is read on its own, as in
  `bd list --label <dimension>:<value>`, so a cause left behind after its
  verdict moved on would answer that query wrongly. `bd set-state` refuses an
  empty value, and no state command removes a dimension, so the cause could
  not be cleared when the verdict changes. Only a plain `bd label remove`
  could, with no event behind it.
- The verdict itself is dated: `pr.machine` holds the verdict, the head
  commit it was reached at, and the pass's instant. A reader takes a verdict
  only at the head the PR is on now. A label value that carried the head would
  be a new value at every head, far past the two to four the page advises.
- The merge pass writes the verdict, its cause and its sentence in one write,
  and clears the cause and the sentence in the write that records any other
  verdict. `bd set-state` writes one dimension per call, as an event and a
  label patch, apart from the metadata write that carries the verdict.

bd's metadata is where data of this kind goes. The
[Issue Metadata](https://beads.gascity.com/core-concepts/metadata) page calls
metadata "the preferred extension point for data that is specific to an
integration, orchestrator, team workflow, or experimental automation", and
reserves only the `bd:` and `_` prefixes. Gas City's engineering doc on beads
leaves pack-private keys open-world, and Gas City keeps no registry of states
that a pack extends.

bd does let a store add statuses of its own. Its
[Configuration](https://beads.gascity.com/reference/configuration#custom-statuses-and-types)
page's section "Custom Statuses and Types" sets them with `status.custom`, and
each one's category decides whether `bd ready` and `bd list` show it. A bead
has one status, and an anchor's already says where the bead stands in its own
lifecycle, which the readers of live work key on. The merge verdict and its
cause sit beside that status, and a custom status could carry them only in its
place.

bd's other GitHub surface mirrors issues. Its
[`bd github`](https://beads.gascity.com/cli-reference/github) commands sync
issues between beads and GitHub. A push writes the bead's status onto the
issue as a `status::in_progress`, `status::blocked` or `status::deferred`
label, and leaves open and closed to the issue's own state
(`BeadsIssueToGitHubFields` in `internal/github/mapping.go`). That is the
nearest shape to the `status:` label anywhere in the search, a status label
that GitHub's own state replaces once the item closes. It mirrors a bead onto
a GitHub issue. A fetch skips pull requests, a reference resolves only to an
issue URL or bd's `github:<n>` shorthand, and a push writes the issue's
title, body, state and whole label set from the bead. So it cannot keep one
label on a pull request whose title, body and other labels belong to someone
else.

### Who holds a bead

A bead's holder, in bd, is its claim. A claim sets the assignee and
`in_progress`, and carries a lease that
[`bd heartbeat`](https://beads.gascity.com/cli-reference/heartbeat) keeps
fresh and [`bd reclaim`](https://beads.gascity.com/cli-reference/reclaim)
reverts once it goes stale. The lease lives in a node-local table, and other
replicas see the claim through the status and assignee.

Gas City adds routing. Its engineering doc *Session Model Unification* sets
the "Workflow Ownership Contract": an unclaimed bead whose `gc.routed_to`
names a config is generic demand for it, and a claimed bead belongs to its
`assignee`, with the route kept as provenance. Gas City reads those marks
inside the controller, each reader for one decision. `sessionOwnsLiveClaim`
keeps a drain from stopping a session that holds live work,
`liveOpenSessionAssignmentExists` finds a pool assignment whose session is gone
so the controller can release it, and `CheckBeadState` in package `sling`
warns when a bead about to be slung is already routed. The run API's cancel
interrupts a run's holders, the assignees of its `in_progress` steps
(`interruptRunHolders` in package `api`). No command or endpoint takes a bead
and answers whether anything is working it, and the file that holds
`sessionOwnsLiveClaim` leaves a single ownership resolver to future work in
its opening comment.

No published pack judges whether an automated actor holds a blocker. The
`gastown` pack's witness patrol judges whether a bead's own assignee session
is alive, and the `oversight-rig` pack's project-lead prompt counts a bead
ready only when its dependencies are closed and no human decision gates it.

### A write retried on a later pass

Gas City ships no outbox and no retry queue for a write to an outside service.
Its engineering doc on orders lists "No retry on dispatch failure" among their
known limitations. `[steps.retry]` retries a formula step's attempt within its
run (section 3.2 of the formula spec), and a label clear runs inside a
script's pass, not as a step. Webhook intake leaves the retry to the sender,
which redelivers on a non-2xx answer.

Packs that retry such a write keep a marker of their own. The `gastown` pack's
`pr-merge-reconcile` keeps `pr_reconcile_pending` on a work bead until its
lookup, close and cleanup land, and lists the beads carrying it in any status,
closed ones included, least recently checked first. The `oversight-rig` pack
delivers its escalation rollups from a condition order and adds a `delivered`
label once one lands, so an undelivered one is tried again on the next tick.

## What the change does with it

**The machine axis stays the pack's.** Nothing in Gas City, bd or the packs it
bundles and publishes records why a pull request cannot merge as a value a
reader keys on, or tells a block no automated actor will clear from a wait the
city is already acting on. The PR monitor and bd's labels as state come nearest,
and neither fits, for the reasons above. So `pr.machine`, `pr.machine_cause`
and `pr.machine_reason` stay pack keys in bd's metadata. The causes are states
the pack defines for itself, which makes them a pack noun
([foundation.md](../../docs/foundation.md#boundaries), test 2), and the
verdict they qualify is one too. The warrant *Machine axis* in
[warrants.md](../../docs/warrants.md#machine-axis) records them, with this
search as its evidence. The build scope recorded from the operator's ruling
in sitting tk-pzhnn9 put the cause beside `pr.machine_reason` as a structured
value, registered in `lifecycle.toml`. The search found no primitive that
covers it, so the key stays where the ruling put it.

**The merge pass composes GitHub's own facts.** It reads the base branch's
effective rules, the PR's review threads and its check rollup through `gh`,
which the PR monitor reads only in part, and the anchor's holds and blockers in
the store, which no Gas City classifier reads. Its verdict is recorded on the
anchor under the warrant above.

**`blocker-holder.sh` composes Gas City's marks of a holder.** It reads a
blocker's route and its claim from one listing of the anchor's blockers, and
the runs that work it through `run-lib.sh`, which follows Gas City's own link
from a run's root to its input convoy and the bead the convoy tracks. It
records nothing, so it adds no pack noun. Its rule that any one mark is an
actor reads each mark as the ownership contract defines it, a route as demand
and a claim as a holder, and does not reconcile the two.

**The `status:` label is a rendering.** `prstatus.Derive` computes its value
on each write from the anchor's records and does no I/O, and nothing keeps the
value in the store. The label itself is GitHub's, written through `gh`.

**`status_label_clear_owed` is the pack's retry marker.** Gas City ships no
retry for a failed write to GitHub, and the packs that retry one keep a marker
of their own, as this key does. The key records a state the pack defines, so
it carries the warrant *Owed status label clear* in
[warrants.md](../../docs/warrants.md#owed-status-label-clear).

This answer changes if Gas City's PR monitor reads a base branch's rules and
its required checks, so that a required check still running is not a block,
and records its class where a reader of the PR's own bead finds it. It changes
too if bd can clear a state dimension, or write one in the same write as the
metadata it qualifies, or if Gas City ships a retry for a failed write to an
outside service. At `e73ebbfb48fd` and `43f41374a34d` none of these ships.
