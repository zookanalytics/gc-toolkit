---
name: Gas City search for the failed-deployment report
description: The search the arch check asks for before the pack adds `gctk deployment report` and the production-deploy-report order, which turn a rig's failed production deployment, as GitHub records it, into one patrol finding in the rig's store. What Gas City, bd and the packs Gas City publishes ship near that need, read at named upstream commits, why the change composes Gas City's per-rig order overrides and the pack's patrol finding, and where the failing step's error line cannot come from. Read it when checking whether the report can move onto a Gas City primitive.
---

# Gas City search for the failed-deployment report

A rig whose repository a host such as Vercel deploys can fail its production
deployment on every merge while the previous build keeps serving, and nothing
in the city reads the failure. This change adds `gctk deployment report`, the
order `production-deploy-report` that runs it, and a read of a repository's
deployments in gctk's GitHub adapter. So the arch check asks what Gas City
already ships for that need
([review-arch.md](../../docs/review-arch.md#the-checks), check 1). Gas City
ships the per-rig switch the list of watched rigs needs, and the change uses
it. It ships no reader of deployments, and its one GitHub monitor reads open
pull requests, which a deployment's failure comes after.

## The surface and the need

- `gctk deployment report --rig <rig> [--environment <name>] [--dry-run]`
  reads the newest 100 deployments of one environment, Production by default,
  in the repository the rig's checkout names as its origin, in one GraphQL
  read. The newest finished one decides. While the deployments fail, it reports
  one patrol finding in the rig's store through `patrol-finding.sh`, which
  files the finding once, counts each later report, notes a report whose text
  changed, and slings the finding's first reaction. Once one succeeds, it
  clears the finding's situation.
- `orders/production-deploy-report.toml` runs it hourly in each rig, and ships
  disabled.
- The GitHub adapter's `Deployments` reads the deployments, and the git
  adapter's `RemoteRepository` names the repository a remote's URL points to,
  which the pr domain's origin checks read as well.

The need: a failed production deployment of a rig's default branch becomes a
task in that rig's store the same day, naming the commit and linking the
deployment, with one task for a run of failures, and a later success recorded
on it. The city reads what the deploy host already posts to GitHub, so it
needs no credential for the host. The rigs watched are listed in config.

## Where the search looked

Each was read on 2026-11-21:

- Gas City at `gastownhall/gascity` main `2e2bc8b75a`: its documentation, its
  engineering docs, the `core` pack it bundles, and its source.
- bd at `gastownhall/beads` main `786241099046`.
- Every pack in `gastownhall/gascity-packs` at main `44b9db7168f6`.

The search covered deployments and deployment statuses, commit statuses and
checks on a default branch, Vercel and other deploy hosts, GitHub monitors,
webhooks and polling, repair work filed from GitHub, and per-rig order
configuration.

## What Gas City ships near the need

### The list of rigs: a per-rig order override

An order a pack ships with `enabled = false` does not run, and a city turns it
on with an `[[orders.overrides]]` entry, whose `rig` names the one rig-scoped
instance it changes
([Orders, Overrides](https://docs.gascity.com/tutorials/07-orders), source
`docs/tutorials/07-orders.md`). Discovery applies the overrides before the
dispatcher filters out disabled orders (`ApplyOverrides` in
`internal/orders/override.go`, called from `internal/orderdiscovery/discovery.go`,
and `FilterEnabled` in `cmd/gc/order_dispatch.go`). An override's `env` sets an
order's `[order.env]` for that instance, which Gas City lays over the order's
environment last (`orderExecEnvWithError` in `cmd/gc/order_store.go`). So the
order ships disabled, and the city's config lists each rig it watches as one
override, with the environment's name when the host names it otherwise. A rig
the config leaves off has no enabled instance, so it takes no place in the
orders lane.

The same function gives a rig-scoped exec order `GC_RIG`, its rig's name, and
carries the controller's GitHub CLI token into the order
(`projectGitHubTokenExecEnv`), so the verb's `gh` call reads as the city's
login.

### GitHub: the pull-request readiness monitor

`[[github.pr_monitor]]` declares a repository, its base branches and the rig
that owns repair work, and `gc github pr backfill --create-repair-beads` files
deduped repair beads for pull requests that need repair
([gc github pr backfill](https://docs.gascity.com/reference/cli#gc-github-pr-backfill),
[GitHubPRMonitor](https://docs.gascity.com/reference/config#githubprmonitor)).
It reads open pull requests only (`ListOpenPullRequests`, whose query asks for
`pullRequests(states: OPEN)`, in `internal/githubmonitor/client.go`), and its
states are a pull request's readiness: failed checks, a conflict, a block,
behind its base, or draft (`internal/githubmonitor/monitor.go`). A production
deployment of the default branch runs after its pull request has merged and
closed, so the monitor never reads it. Its dedup is keyed on the pull
request's repository, number and head (`githubPRRepairDedupeMetadata` in
`cmd/gc/cmd_github.go`), so it is no keyed record another reader can file
under.

### Deployments

Gas City's documentation uses the word deployment for a city's own
configuration, where `city.toml` is "this city's deployment"
(`docs/getting-started/coming-from-gastown.md`). None of its documentation,
engineering docs or source reads a repository's deployments or their
statuses, or names a deploy host: a search of its Go source for GitHub's
deployment routes and types finds one Kubernetes test. The `core` pack's
orders are beads-health, binding-snapshot, cascade-nudge-on-blocker-close,
convoy-autoclose-backstop, cross-rig-deps, gate-sweep, jsonl-export,
notify-on-claims-resumed, notify-on-claims-stalled,
notify-on-human-gate-creation, nudge-mail-sweep, nudge-on-route,
order-tracking-sweep, orphan-sweep, prune-branches, reaper,
renudge-stale-human-gates and spawn-storm-detect. The one that reads GitHub,
gate-sweep, evaluates bd's GitHub gates.

### Gates

bd's `gh:run` gate waits for a GitHub workflow run and its `gh:pr` gate for a
pull request's merge (`bd gate`, `docs/CLI_REFERENCE.md` in bd), and core's
gate-sweep order closes each once its run or pull request finishes
(`internal/bootstrap/packs/core/orders/gate-sweep.toml`). A gate is a wait on
one named run or pull request, which a bead holds until it closes, and it has
no type for a deployment.

### Webhooks

Gas City's API carries a webhook receiver, `/v0/city/{cityName}/hook/{name}`,
which passes a provider's webhook through to the city
(`engdocs/architecture/api-control-plane.md`), and a webhook can target an
order (`docs/tutorials/07-orders.md`). GitHub sends a `deployment_status`
event only to a URL it can reach, and an event cuts latency without deciding
anything, since an order converges from durable state
([gctk-architecture.md](../../docs/gctk-architecture.md#the-rule-that-admits-an-order)).
So the hourly poll is the order, and a city GitHub can reach can fire the same
verb from that event as well.

### bd

`bd github sync` syncs issues between bd and GitHub (`cmd/bd/github.go`), and
its client fetches issues and filters out pull requests (`FetchIssues` in
`internal/github/client.go`). It reads no deployment. `bd create` has no flag that
finds a record already filed under a key instead of filing a second one.

### The packs Gas City publishes

The gstack pack's `land-and-deploy` skill merges a pull request and then waits
for its deploy (`gstack/skills/land-and-deploy/SKILL.md`, Step 6). It runs in a
session a person attends, asks that person what to do when a deploy fails, and
for an auto-deploying host such as Vercel waits a minute and probes the site
rather than reading the deployment's status. It covers a landing someone
watches, and the city's merges are made by its landing order with nobody
watching.

## What the change composes

- Gas City's per-rig override, for the list of rigs.
- The pack's patrol finding (`assets/scripts/patrol-finding.sh`), for the one
  task a run of failures keeps. Its warrant
  ([warrants.md](../../docs/warrants.md#patrol-findings)) stands: the searches
  above found no keyed problem record in Gas City or bd. The change adds no key
  to the finding and does not touch its writer.
- GitHub's deployments, read as the host posted them.

## The error line

The task names the commit, its pull request and the deployment, and quotes the
deployment's status and any commit status failing on its commit. It cannot
quote the failing step's error line. A Vercel deployment's status gives the
deployment's URL, which Vercel's sign-in guards, and a description that names
the deployment and the CLI command that prints its logs. The build log is read
through Vercel's CLI (`vercel inspect --logs`) or its REST API, each of which
takes a Vercel account's token
([vercel inspect](https://vercel.com/docs/cli/inspect)), and the report is
built to need none, as its task asked. So the finding points its reader at the
log, and the person or agent who acts on it reads the line there.
