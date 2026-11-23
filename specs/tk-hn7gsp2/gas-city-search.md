---
name: Gas City search for the workflow failure report
description: The search the arch check asks for before the pack adds `gctk actions report` and the actions-failure-report order, which turn a failed run of a GitHub Actions workflow a rig marks, on the rig's default branch, into one patrol finding in the rig's store. What Gas City, bd and the packs Gas City publishes ship near that need, read at named upstream commits, why a mark in the workflow's own file chooses the workflows instead of Gas City's per-rig order overrides, and what a webhook would add later. Read it when checking whether the report can move onto a Gas City primitive.
---

# Gas City search for the workflow failure report

A scheduled workflow on a rig's default branch can fail every day while nobody
who can act is told. GitHub notifies one account of a scheduled run: the one
that last changed the workflow's schedule or turned it back on, which for the
workflows the city lands is the city's own login, and nothing in the city reads
that account's notifications. This change adds `gctk actions report`, the order
`actions-failure-report` that runs it, a read of a workflow's runs and of a
run's jobs in gctk's GitHub adapter, and a search of a commit's files in its git
adapter. So the arch check asks what Gas City already ships for that need
([review-arch.md](../../docs/review-arch.md#the-checks), check 1). Gas City
ships no reader of a branch's workflow runs, and the per-rig switch it does
ship cannot carry the choice of workflows as well as the workflow's own file
does.

## The surface and the need

- `gctk actions report --rig <rig> [--dry-run]` finds the workflows the rig
  marks: each file directly under `.github/workflows` that holds the line
  `# gc:report-failures`, at the default branch as the rig's checkout last
  fetched it. For each, it reads the newest 100 completed runs on that branch in
  one GitHub read, and the newest run that failed or succeeded decides. While
  the runs fail, it reports one patrol finding per workflow in the rig's store
  through `patrol-finding.sh`, after one more read for the failed run's jobs.
  Once a run succeeds, it clears the finding's situation.
- `orders/actions-failure-report.toml` runs it hourly in each rig, and is on
  by default.
- The GitHub adapter's `WorkflowRuns` and `RunJobs` read the runs and the jobs,
  the git adapter's `Grep` reads the marks, and the runtime adapter's
  `Result.Said` reads what the finding's writer said, which the deployment
  report now reads the same way.

The need, as the work bead states it: a failed run of a workflow a rig opts
in, on its default branch, files one bead in the rig's store with nobody reading
GitHub. The opt-in is per rig and per workflow. One open bead per workflow is
keyed so that a run that stays red refreshes it. A read that fails is not a
green, and a run that goes green says so on the open bead.

## Where the search looked

Each was read on 2026-11-23:

- Gas City at `gastownhall/gascity` main `572f981c6168`: its documentation, its
  engineering docs, the `core` pack it bundles, and its source.
- bd at `gastownhall/beads` main `786241099046`.
- Every pack in `gastownhall/gascity-packs` at main `44b9db7168f6`.

The search covered GitHub Actions runs and jobs, `workflow_run` events, check
runs and statuses on a default branch, GitHub's notifications, the pull-request
monitor, gates, webhooks, keyed problem records, and per-rig order
configuration.

## What Gas City ships near the need

### No reader of a branch's runs

Gas City's source reads no GitHub Actions run. A search of `internal/`, `cmd/`,
`docs/` and `engdocs/` for `actions/runs`, `actions/workflows` and `gh run list`
finds only links to Gas City's own CI runs, and the `workflowRun` names in
`cmd/gc` belong to Gas City's own formula runs. Nothing reads GitHub's
notifications.

Its one GitHub monitor, `[[github.pr_monitor]]` with `gc github pr backfill`,
reads open pull requests (`pullRequests(... states: OPEN ...)` in
`internal/githubmonitor/client.go`). A scheduled run on the default branch
belongs to no pull request, so the monitor never reads it.

### Gates wait on one run

bd's `gh:run` gate waits on one run: `checkGHRun` in `cmd/bd/gate.go` runs
`gh run view <id>`, resolves the gate on a success or a skip and escalates on
any other conclusion, and core's `gate-sweep` order checks open gates every 30
seconds (`internal/bootstrap/packs/core/orders/gate-sweep.toml`). A gate is a
wait on a run someone named, and each new scheduled run is a run no gate names.

### The packs

The `pr-pipeline` pack's `mol-pr-from-issue` stops its own push at a `base-ci`
step when `gh run list --branch main --status failure` shows a failure from the
last six hours (`pr-pipeline/formulas/mol-pr-from-issue.formula.toml`). It is a
check inside one formula run, which files nothing and tells no one. The github
pack's webhook intake runs `gc order run` or a command for a GitHub event a
rule matches (`execute_rule_action` in
`github/scripts/github_intake_service.py`), so it could start the verb, as the
webhooks below say.

### bd's own repository

bd's repository watches its own main this way, from a workflow of its own
(`.github/workflows/main-ci-alert.yml` with `.github/scripts/main-ci-alert.sh`):
when a tracked workflow's push run on main ends red, it keeps one `ci/main-red`
GitHub issue, comments on later reds, says when a workflow is green again and
closes the issue once none is red. It leaves out a fork's pull request from the
fork's own main, which GitHub also reports on the branch main. It is the
repository's own tooling, not a primitive a city composes: its record is a
GitHub issue, which nothing in the city reads, and each repository would carry
its own copy. The report takes its rule: the newest decided run of each
workflow decides, one record holds the situation, and a green is said on it.

### Webhooks

Gas City's `[[webhook]]` receiver matches a delivery by exact values at payload
paths, such as `workflow_run.conclusion`, and fires an order that declares
`trigger = "webhook"`, an exec order only from a hook that is not public
(`internal/webhooksink/sink.go`). GitHub sends a delivery only to a URL it can
reach, and an event cuts latency without deciding anything
([gctk-architecture.md](../../docs/gctk-architecture.md#the-rule-that-admits-an-order)).
So the hourly poll is the order, and a city GitHub can reach can run the same
verb for the rig a `workflow_run` delivery names.

### Which rigs and which workflows

An `[[orders.overrides]]` entry turns a rig's instance of an order on or off,
or sets its environment (`ApplyOverrides` in `internal/orders/override.go`, and
`FilterEnabled` in `cmd/gc/order_dispatch.go`), and since `3ee9c96585` ("let an
override enable an order its own file disables", #9115) it can turn on an order
its pack ships disabled. No order field names rigs, and none reads a rig's own
repository. The change does not use the overrides for its list:

- The choice is per workflow, and the workflow is a file in the rig's
  repository. An override would name the workflow from the city's config, where
  a renamed or deleted workflow leaves an entry naming a workflow GitHub no
  longer runs, and each read of it fails. The mark is a line of the workflow's
  own file, so it goes wherever the file goes and leaves with it.
- The operator ruled on 2026-11-22, of the city's per-rig override blocks in
  sitting tk-azsaa28: "ideally we remove the non-default city config". Reading
  that ruling as covering a new order's list is this change's reading.
- The city runs gc `6589a7df45`, which `3ee9c96585` is not in, so its override
  cannot turn on an order the pack ships disabled. The turn-on of the
  production-deploy-report order failed for that reason (tk-qfxdkoi).

So the order runs in every rig, and reads the marks in the rig's checkout, at
the remote-tracking ref of the default branch origin's HEAD names, which the
pack's `reconcile-rig-checkouts` order fetches every 15 minutes. A rig that
marks nothing costs a pass no GitHub read. The mark is the pack's own
convention, as the `<!-- gc:no-review -->` mark a comment opens with is
([not-for-review.md](../../docs/not-for-review.md)).

### Keyed problem records

The patrol finding's warrant
([warrants.md](../../docs/warrants.md#patrol-findings)) stands at `572f981c6168`.
`gc mail send --dedup` suppresses a send while a live message with the key is in
the mailbox (`newMailSendCmd` in `cmd/gc/cmd_mail.go`). Core's `escalate.sh`
keys an incident to throttle its mail, and keeps that state best-effort under
`.gc/incidents`
(`internal/bootstrap/packs/core/assets/scripts/escalate.sh`). `gc event emit`
records one event and keeps nothing per key (`cmd/gc/cmd_event_emit.go`). The
PR monitor's `ensureGitHubPRRepairBead` refreshes one open repair bead per
pull request, keyed on its repository, number and head
(`githubPRRepairDedupeMetadata` in `cmd/gc/cmd_github.go`), so no other reader
can file under it, and nothing clears it when the pull request goes green.

## What the change composes

- The pack's patrol finding (`assets/scripts/patrol-finding.sh`), for the one
  bead each workflow keeps: it files the bead once, counts each later report,
  notes a report whose text changed, records a green with `--cleared`, and
  slings the bead's first reaction. The change adds no key to the finding and
  leaves its writer as it is: the writer's list of its callers gains the
  report, and the warrant is re-dated in this change.
- GitHub's runs of a workflow and jobs of a run, read through its REST API as
  GitHub records them, one call an hour for each marked workflow and one more
  while it fails, against the 5,000 REST requests an hour the city's login has.
- The rig's checkout, for the marks, through one `git grep` of the
  remote-tracking ref.
