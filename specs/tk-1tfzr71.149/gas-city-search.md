---
name: Gas City search for the landing order's one read a pass and its labels by comparison
description: The Gas City, Gas Town, bd and GitHub primitives searched for the surface tk-1tfzr71.149's design adds, namely the one GitHub request per repository that reads every PR the city owns, the order that runs the pass and its acts, the saved read's new fields, and the label writes made by comparison with nothing recording a failed one. It says what each search found at a named upstream commit and why none covers the need. Read it when building or reviewing one of the design's units, or when the arch check asks for the search.
---

# Gas City search for the landing order's one read a pass and its labels by comparison

Read on 2026-11-15 in a checkout of `gastownhall/gascity` at main 294079d53f
(2026-11-15T17:30:54Z), at `gastownhall/gascity-packs` main 0f07496d2f, and at
`gastownhall/beads` tag v1.3.4, the build the city runs beside gc 1.4.3. The
initiative's leads were read at Gas City main e9a628c500. The commits since then
change none of the cited behavior. The newest, #9155, refactors the order store's
query builders and adds leg reads with no production caller. Each section names
the unit of [the design](design.md) that adds the surface.

## The read of GitHub (unit 1)

The need: one GitHub request per repository, each pass, that reads every PR the
city owns there. It must return the facts the saved read holds about a PR's
state, which checks are required at its head, what tells that its feedback
moved, and its labels. It must also find the other PRs that carry a `status:` or
`held:` label.

- **Gas City's PR monitor.** `pullRequestsQuery` in
  `internal/githubmonitor/client.go` lists `pullRequests(first: 50, states:
  OPEN, orderBy: {field: UPDATED_AT, direction: DESC})`. For each PR it reads
  `number title url author isDraft mergeStateStatus baseRefName headRefName
  headRefOid`, and the last commit's `statusCheckRollup.contexts(first: 100)`
  with each check's name, status and conclusion. It reads no labels, no review
  decision, no review or comment, and no check's `isRequired`. It lists only open
  PRs, so a merged PR is not in it. Its one caller is `gc github pr backfill`
  (`cmd/gc/cmd_github.go`), which no bundled order runs. `poll_interval`,
  `webhook_secret_env` and `merge_queue` are read only by validation, though
  `docs/reference/config.md` says `poll_interval` enables a polling cadence. Not
  covered: it lacks the labels, the required checks and the feedback signs, and
  it cannot report a PR that left the open list.
- **Gas Town's reconcile.** `gastown/commands/pr-merge-reconcile/run.sh` reads
  each record's PR on its own, by URL, with `gh pr view --json
  url,number,state,headRefName,headRefOid,baseRefName,mergedAt,mergeCommit`. It
  writes `pr_last_checked_at` at every check. It reads no check, review or label.
  Not covered: its cost follows the number of records, which is what the design
  removes.
- **bd.** `internal/github/client.go` at v1.3.4 syncs beads with GitHub issues
  (`FetchIssues`, `FetchIssuesSince`, `FetchIssueByNumber`, `CreateIssue`,
  `UpdateIssue`, `AddLabels`). It reads no PR state, check or review. Not
  covered.
- **GitHub's own API.** This is the primitive the read composes. GraphQL
  aliases let one request carry one `pullRequest(number: N)` field per PR, each
  passing its own number to `CheckRun.isRequired(pullRequestNumber:)`, which a
  list of PRs cannot do, since a connection passes no argument per node. The
  same request carries a `search(type: ISSUE)` root field for the PRs that carry
  a label. Measured in the design's section 14: 11 PRs in one request at 3
  points, and the search at 1 point a page.

Conclusion: none covers it. The read is a query in gctk's GitHub adapter
(services/gctk/internal/gh), beside the reads that adapter makes today.

## What runs the pass (units 1 and 2)

The need: something that reads GitHub and the store every few minutes, cheaply
when nothing changed, and acts on what differs without the acts slowing the next
read. Nothing may be queued that a failure could strand.

- **Order triggers.** `Order` in `internal/orders/order.go` takes `trigger` as
  cooldown (`interval`), cron (`schedule`, `tz`), condition (`check`,
  `check_timeout`), event (`on`), manual or webhook (`[order.params]`), and
  `Validate` checks each. The trigger table in `docs/tutorials/07-orders.md`
  omits webhook.
- **Cooldown.** It counts from a run's start: `checkCooldown` measures from the
  tracking bead's `CreatedAt`, which `launchResolvedDispatch` creates before it
  launches the run (`cmd/gc/order_dispatch.go`). The alt text at
  `docs/tutorials/07-orders.md` line 218 and the cooldown-versus-cron diagram
  say it counts from the run's end, which the code does not do.
- **The lane.** Orders are evaluated on a lane that runs a pass about every
  `[daemon] patrol_interval` after the last one ended (`startOrdersLane` in
  `cmd/gc/orders_lane.go`; the default is 30 s in `internal/config/config.go`).
  A pass starts at most `DefaultMaxOrderDispatchesPerTick = 4` cooldown, cron or
  event orders, and a condition order whose check passes fires outside that
  budget (`dispatch`). No minimum interval and no jitter apply.
- **One run at a time, for two minutes.** A run still open is skipped, not
  queued (`hasOpenTracking`). But `runOrderTrackingSweepWatchdog`
  (`cmd/gc/city_runtime.go`) closes any tracking bead older than
  `orderTrackingSweepWatchdogStaleAfter = 2 * time.Minute` without checking its
  run, so a run past two minutes can overlap the next.
- **Timeout.** An exec order's timeout defaults to 300 s (`TimeoutOrDefault`)
  and `[orders] max_timeout` can only lower it (`effectiveTimeout`). On timeout
  the process group gets SIGTERM, then SIGKILL two seconds later
  (`processgroup.Terminate`, `shellExecSignalGrace`).
- **A condition order.** `CheckTriggerWithOptions` in
  `internal/orders/triggers.go` answers the condition case with
  `checkCondition(a, opts)` alone, so a condition order's `interval` is ignored.
  `checkCondition` runs the check under `sh -c` with its stdout discarded
  (`cmd.Stdout = io.Discard`), so nothing it finds reaches the run. Its timeout
  defaults to `defaultConditionCheckTimeout = 10 * time.Second`
  (`internal/orders/order.go`), which `max_timeout` does not cap. The lane runs
  every check on every pass and waits for all of them before it fires anything,
  and it skips the check while the order's run is open. Not covered: the
  comparison would run every 30 seconds, and the run would have to read GitHub
  again.
- **An event order.** `checkEvent` matches one exact event type with no filter
  on its payload, on the lane's next pass, and the run is told nothing about the
  event. Not covered: the acting run would have to find its work again.
- **A webhook.** `routeOrder` in `internal/webhooksink/sink.go` refuses an exec
  order behind a public hook, and an order a hook fires gets only the rule's
  args, never the body. A public route into the city is the operator's call, so
  it is out of this design.
- **On demand.** `gc order run` runs the exec in the caller, with no check of an
  open run (`doOrderRunExecResult` in `cmd/gc/cmd_order.go`). `POST
  /v0/city/{city}/order/{name}/run` fires only a webhook-trigger order, with no
  single-flight gate (`humaHandleOrderRun` in `internal/api/handler_webhook.go`).
  Not covered: neither runs on a schedule.
- **A queue for mechanical work.** `cmd/` and `internal/` hold no outbox, job
  queue or retry queue a pack can use. A failed exec run is labeled
  `exec-failed` and recorded as `order.failed`, with the last 2 KiB of its
  output, and is retried only by the order's next firing. `Order` has no field
  that starts another order. Not covered: a second order cannot be handed the
  first one's findings.
- **What a run leaves.** Each run writes a tracking bead. A closed one is kept 7
  days by default (`[beads.policies.order_tracking]`, `cmd/gc/city_runtime.go`).
  The cooldown index reads the newest `orderTrackingHistoryIndexLimit = 256`
  runs per store, and an order whose last run is older pays one more read, which
  the index then remembers (`cmd/gc/order_dispatch.go`). A rig's copy of a pack
  order is named `<name>:rig:<rig>` (`ScopedName`) and has its own tracking and
  cooldown, and it runs in the rig's directory.
- **Tuning.** `[[orders.overrides]]` changes an order's `interval` and `timeout`
  from city.toml without editing the pack.

Conclusion: the existing cooldown exec order, `orders/pr-reconcile.toml`, runs
the pass. Its interval goes to 2 minutes, and its acts start no later than 90
seconds into a run, so a run normally ends before the watchdog would let the next
start beside it. The record lock makes an overlap safe. What a pass leaves undone
stays a difference the next pass finds, so nothing is queued.

## The saved read's new fields (unit 1)

The need: the bead that owns a PR holds GitHub's side of it in a form the next
pass can compare. That form is the state the pass's read returns, and what told
that the feedback moved when the feedback was last read in full.

- **Gas City.** Its PR monitor writes nothing onto the bead that owns a PR, and
  its query lacks these facts (above).
- **Gas Town.** Its record holds the PR's state, head and merge facts, and
  nothing about checks, reviews or feedback.
- **bd.** A bead's `external_ref` holds a reference, not state.

Conclusion: none covers it. The fields join the one key the PR-status effort
adds, `pr_github_read`, under that key's warrant and with its one writer, the
landing order. No key is added.

## The label writes, and no record of one that failed (unit 2)

The need: a PR's `status:` and `held:` labels equal what the store derives, on
every PR the city owns and on any other PR that carries one. A write that does
not land is made again by a later pass, with nothing recording that it was owed.

- **Gas City.** No code in `cmd/` or `internal/` lists PRs with their labels or
  writes a GitHub label. A search for `addLabels`, `removeLabels`,
  `labels(first`, `LabelsOnLabelable` and `--add-label` finds only bead labels.
- **Gas Town.** No label code.
- **bd.** `AddLabels` adds labels to an issue number over REST, with no removal
  and no rule that derives them. Not covered: the families, the derivation and
  the clear are the pack's own.
- **Retrying a failed write.** No queue exists (above). The comparison is the
  retry: a later pass reads the labels again and writes what still differs.

Conclusion: none covers it. The comparison calls the pack's one writer of the
labels, `assets/scripts/pr-status-label.sh`, through the `reconcile` and `clear`
verbs it has. It adds no verb and no key, and it retires none of the old path's
callers, which their own beads retire (design, section 5).
