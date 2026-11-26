---
name: Gas City search for sending a check that fails on a rig's main to be fixed
description: The search the arch check asks for before the pack adds `gctk actions track` and the actions-track order, which file the tracker of each GitHub Actions workflow whose newest finished push run on a rig's default branch failed. It covers what Gas City, bd and the packs Gas City publishes ship near that need, read at named upstream commits, why the pass files through the pack's tracker of a failure on a base branch, and why it reads the branch's newest push runs in one call. Read it when checking whether the pass can move onto a Gas City primitive.
---

# Gas City search for sending a check that fails on a rig's main to be fixed

A failure on a rig's default branch is work to fix, and the pack already sends
one to be fixed: `preexisting-failure.sh` files the failure's tracker and slings
it to the rig's polecat pool ([steering.md](../../docs/steering.md#the-intake-rule)).
Its callers are agents that ran the failing test themselves. Nothing reads
GitHub's result for a rig's default branch, except an agent that asks about one
named check (`checkMain` in `services/gctk/reaction/emergency.go`). So a check
that fails only in GitHub's CI, or in a rig where no agent has run the tests
since, is seen by nobody. This change adds `gctk actions track`, the order
`actions-track` that runs it, and a read of a branch's runs and of a run's jobs
in gctk's GitHub adapter. The arch check asks what Gas City already ships for
that need ([review-arch.md](../../docs/review-arch.md#the-checks), check 1). Gas
City ships no reader of a branch's workflow runs. The record the need asks for
is one the pack already keeps, its tracker.

## The surface and the need

- `gctk actions track --rig <rig> [--dry-run]` reads the newest 100 runs that
  pushes to the rig's default branch started, finished or not, of every
  workflow, in one GitHub read. For each workflow file, the newest run that
  failed or succeeded decides. For each workflow whose deciding run failed, it
  files the tracker through `preexisting-failure.sh`. It files nothing while a
  bead already tracks the failure, and nothing for a run that the failure's
  tracking covered before it last ended. It reads the failed run's jobs only
  for a tracker it files.
- `orders/actions-track.toml` runs it every five minutes in each rig, and is on
  as it ships.
- The GitHub adapter's `BranchRuns` and `RunJobs` read the runs and the jobs.

The need, in the operator's words on 2026-11-25 in conversation tk-w8e75e0:
"Main has CI. Main checks fail. Main checks fail and nothing fixes them That's
bad, main should be green. Can the city keep main green. And can we do that
simply?" The record they asked for, in the same conversation: "For each failure,
file a bead, with a key unique to that issue", "If it's a known CI failure we
aren't fixing, that bead gets held. All future failures dedup to the same key,
all is fine", "Others get worked and ideally fixed."

## Where the search looked

Each was read on 2026-11-25:

- Gas City at `gastownhall/gascity` main `0997336456`: its source, its
  documentation and its engineering docs.
- bd at `gastownhall/beads` main `786241099046`.
- Every pack in `gastownhall/gascity-packs` at main `44b9db7168f6`.

The search covered GitHub Actions runs and jobs, check runs and statuses on a
default branch, the pull-request monitor, gates, webhooks, keyed problem records
and per-rig order configuration. It repeats, at these commits, a search made for
the same need on 2026-11-23.

## What Gas City ships near the need

### No reader of a branch's runs

Gas City's `internal/` and `cmd/` read no GitHub Actions run: no call names
`actions/runs`, `actions/workflows` or `gh run list`, and its `docs/` and
`engdocs/` name those only in links to Gas City's own CI runs. Its one GitHub
monitor, `[[github.pr_monitor]]`, reads open pull requests
(`pullRequests(... states: OPEN ...)` in `internal/githubmonitor/client.go`),
and the check rollup it reads is each open pull request's head's. A push run on
the default branch belongs to no pull request, so the monitor never reads it.

### A gate waits on one run

bd's `gh:run` gate waits on one run: `checkGHRun` in `cmd/bd/gate.go` runs
`gh run view <id>`, and core's `gate-sweep` order checks open gates. A gate is a
wait on a run someone named, and each new run on a branch is a run no gate
names.

### The packs

The `pr-pipeline` pack's `mol-pr-from-issue` stops its own push at a `base-ci`
step when `gh run list --branch main` shows a failure from the last six hours
(`pr-pipeline/formulas/mol-pr-from-issue.formula.toml`). It is a check inside
one formula run, which files nothing and tells no one.

### bd's own repository

bd's repository watches its own main from a workflow of its own
(`.github/workflows/main-ci-alert.yml`): when a tracked workflow's push run on
main ends red, it keeps one `ci/main-red` GitHub issue and closes it once no
workflow is red. It is that repository's own tooling, not a primitive a city
composes. Its record is a GitHub issue, which nothing in the city reads, and
each repository would carry its own copy. The pass takes its rule for which
runs count from it: a push run of the branch in the repository itself, never a
fork's pull request from the fork's own branch of the same name, which GitHub
also reports on the branch.

### Webhooks

Gas City's `[[webhook]]` receiver routes a delivery its rule matches to an
order that declares `trigger = "webhook"`, and a public webhook may fire only a
formula order (`routeOrder` in `internal/webhooksink/sink.go`). GitHub sends a
delivery only to a URL it can reach, and an event cuts latency without deciding
anything
([gctk-architecture.md](../../docs/gctk-architecture.md#the-rule-that-admits-an-order)).
So the cooldown order is the pass, and a city that GitHub can reach can run the
same verb for the rig a `workflow_run` delivery names.

### Which rigs

An `[[orders.overrides]]` entry turns a rig's instance of an order on or off
(`ApplyOverrides` in `internal/orders/override.go`), and no order field names
rigs. The pass needs no list. Every rig's default branch has the checks a push
to it starts, so the order runs in every rig as it ships, and the city's config
names no rig and no workflow. A scheduled workflow counts once its own file adds
a push trigger.

### Keyed problem records

The PR monitor keeps one open repair bead per pull request's head
(`ensureGitHubPRRepairBead` in `cmd/gc/cmd_github.go`). Its key is the pull
request's repository, number and head (`githubPRRepairDedupeMetadata`), so no
other reader can file under it. Gas City ships no record of a failure on a base
branch that each reader of the failure finds by one key.

## Why the pass files through the pack's tracker

The pack already keeps the record the operator asked for.
`preexisting-failure.sh` files one tracker per failure key, with the key
stamped in the create. Before it files, it looks for a bead that holds the key
in every live status, held, worked or waiting. A closed tracker's duplicate or
successor edge leads it to the live bead that carries the failure now. It slings
each tracker it files to its rig's polecat pool, which the intake rule admits.
Every gate that meets a failure on a base branch files through it. A failure
nobody will fix is held on its bead, and the writer files nothing for it
again, so the pass builds nothing for holding. A patrol finding, the record the
deployment report keeps, would be a second record of the same failure under
another key, with a first reaction in front of the fix. The operator asked of
that shape, in the same conversation: "how do we have two things that are
intended to do the same thing?"

The writer's lookup and its create are two calls, so two filers that meet one
red at once could each read no tracker and each file one. The order is a filer
that runs on its own, and the rule that admits an order asks that its writes
take one lock shared with every pack writer of what they write
([gctk-architecture.md](../../docs/gctk-architecture.md#the-rule-that-admits-an-order)).
Every filer of a tracker files through the writer, so the writer holds that lock
from its lookup until its create has answered: a flock on
`preexisting-failure.lock` in the store's own `.beads` directory, as
`queue-priority.sh` holds the store's priority lock there. bd offers no create
that refuses a second bead by a key the bead carries. It refuses a create whose
explicit `--id` already exists (`cmd/bd/create.go` at beads v1.3.4, the version
`gastownhall/gascity`'s `go.mod` pins at 944ef25f3b), but a key files again once
its tracker has closed, so an id made from the key would also need the closed
tracker the same lookup read, and every tracker's id would change form. Neither
`gc` nor `bd` exposes a lock to a script. The race has not been seen. On
2026-11-25, each of the city's seven stores answered
`gc bd list --all --type=bug --title-contains "Pre-existing failure"`, with 66
trackers stamped with a key since 2026-10-13 among them, and no key had been
filed a second time while a tracker of it was live.

A run names its jobs and its steps, not its failing test, so the pass keys a
workflow's failure by the workflow's file, `key --target .github/workflows/<file>`.
The tracker's text sends its worker to find the failing test and look up that
test's tracker. When one exists, the worker closes the workflow's tracker as its
duplicate, and later failures of the workflow reach that tracker through the
writer's lookup.

The pass reads the key's closed trackers from the rig's store for one guard of
its own: a failed run files nothing when the failure's tracking covered it
before it last ended. Without it, the pass would file a second tracker in the
minutes after each fix lands, from a run older than the fix's own. A run that
started before the tracking ended is covered when the tracker was filed after
the run was made, or when a newer run of the workflow, made before the tracking
ended, has not decided. What that leaves is the newest run made between the
filing and the end, the run of the commit that landed the fix, because a landing
starts that run before it closes the tracker. Of this repository's twelve newest
merges, read on 2026-11-25, GitHub made each merge's first run 2 to 4 seconds
after the merge, and the refinery closed the merged bead 51 seconds to 3 minutes
after it, so a fast workflow's run can finish before the close: the newest
merge's `govulncheck.yml` run finished 9 seconds before its bead closed. So when
the fix's own run fails, the pass files the failure, whether that run finished
before the close or after it. That is why the read takes the runs that have not
finished, which decide nothing: a run from before the fix is held back only
while the fix's run is still to decide.

The tracking ends at the latest close along the tracker's chain of duplicates
and supersedes edges in the rig's store, the edges the writer's lookup follows
(`tracked_by` in the writer): a workflow's tracker closed as the duplicate of a
test's tracker ends only when that tracker's fix closes it.

## Why one read of the branch's newest push runs

Read on 2026-11-25:

- **The newest commit usually has no result.** Each job of this repository's
  `tests.yml` holds a concurrency group with cancel-in-progress on the ref, so a
  push cancels the test run of the push before it. Of the 33 test runs among the
  newest 100 finished push runs on main, 28 were cancelled. The newest run of a
  workflow that failed or succeeded is the newest result there is.
- **One call reads every workflow.** `GET repos/<repo>/actions/runs` with
  `branch`, `event=push`, `exclude_pull_requests=true` and `per_page=100`, and
  no `status`, so that it holds the runs not yet finished, answered in 1.4 to
  3.5 seconds in each of the city's six rig repositories at 09:59 UTC, 0.4 to
  2.7 MB, about 2 MB on this repository's main. Its runs reached back from about
  two days on this repository's main to over three months on the quietest. A
  pass that finds nothing failing makes no other call.
- **The allowance.** Every five minutes in six rigs is 72 calls an hour, against
  the 5,000 REST calls an hour of the city's login, which used about 3,400 in the
  hour measured.

## What the first passes file

The same read in each rig on 2026-11-25 found three workflows whose deciding
run failed, all in one rig, and none in the other five. Each gets a tracker in
its rig's store on that rig's first pass, sent to its rig's polecat pool to be
fixed like any other failure on a base branch.
