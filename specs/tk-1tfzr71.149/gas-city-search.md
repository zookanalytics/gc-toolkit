---
name: Gas City search for the PR watch, the one-PR update and the landing order that acts from the beads
description: The Gas City, Gas Town, github pack, bd and GitHub primitives searched for the surface tk-1tfzr71.149's design adds, namely the cheap question and the net that read GitHub, the one-PR update that saves what it read on a PR's bead, the landing order that acts from the beads, the label writes made by comparison, and the board's line saying when GitHub was last asked. It says what each search found at a named upstream commit and why none covers the need. Read it when building or reviewing one of the design's units, or when the arch check asks for the search.
---

# Gas City search for the PR watch, the one-PR update and the landing order that acts from the beads

Read on 2026-11-16 at `gastownhall/gascity` main 9a4b1e718
(2026-11-16T13:40:28Z), in a clone fetched that day, at
`gastownhall/gascity-packs` main 0f07496d2f, and at `gastownhall/beads` tag
v1.3.4, the build the city runs. None of the commits on Gas City's main since
294079d53f touches the order engine, the webhook receiver, the PR monitor or the
API's order routes. Each section names the unit of [the design](design.md) that
adds the surface.

## The cheap question and the net read GitHub (units 1 and 3)

The need: a request that asks GitHub, for every PR the city owns in a
repository, whether anything moved, in a few signs and no details, and a slower
read of the facts no sign covers. Both must read PRs that merged or closed while
a bead still owns them.

- **Gas City's PR monitor.** `pullRequestsQuery` in
  `internal/githubmonitor/client.go` lists `pullRequests(first: 50, after:
  $cursor, states: OPEN, orderBy: {field: UPDATED_AT, direction: DESC})`. For
  each PR it reads `number title url author isDraft mergeStateStatus baseRefName
  headRefName headRefOid` and the last commit's `statusCheckRollup.contexts(first:
  100)` with each context's name, status and conclusion or state. It reads no
  labels, no counts of comments or reviews, no review decision, no base tip and
  no check's `isRequired`, and it lists only open PRs, so a PR that merged is not
  in it. Its one caller is `gc github pr backfill` (`newGitHubPRBackfillCmd` and
  `doGitHubPRBackfill` in `cmd/gc/cmd_github.go`), which no bundled order runs.
  Not covered: it lacks the signs and the required checks, and it cannot see a
  merge.
- **Gas Town's reconcile.** `gastown/commands/pr-merge-reconcile/run.sh` reads
  one record's PR a call, by URL, with `gh pr view --json
  url,number,state,headRefName,headRefOid,baseRefName,mergedAt,mergeCommit`. It
  reads no check, review, comment or label. Not covered: its cost follows the
  number of records.
- **bd.** `internal/github/client.go` at v1.3.4 syncs beads with GitHub issues
  (`FetchIssues`, `FetchIssuesSince`, `FetchIssueByNumber`, `CreateIssue`,
  `UpdateIssue`, `AddLabels`, `RemoveLabel`). It reads no PR state, check or
  review. Not covered.
- **GitHub's own API.** This is what the reads compose. GraphQL aliases let one
  request carry one `pullRequest(number: N)` field per PR, so it reads merged
  PRs as well as open ones, and each field can pass its own number to
  `isRequired(pullRequestNumber:)` for the net, which a list of PRs cannot. A
  rollup's `checkRunCountsByState` and `statusContextCountsByState` count a
  head's checks without reading them. Each conversation comment, review and
  inline comment carries its own `updatedAt`, which an edit moves, so the net
  reads those times and no text, since a PR's `updatedAt` misses some edits
  (design, sections 1 and 2). The REST API answers a conditional request that
  finds nothing changed with a 304, free of the allowance, but a PR's ETag moves
  at any push to its repository and the check runs' ETag misses a commit status
  (design, section 1).

Conclusion: none covers it. Both reads are queries in gctk's GitHub adapter
(services/gctk/internal/gh), beside the reads that adapter makes today.

## The one-PR update saves GitHub's side on the bead (unit 1)

The need: one operation that reads one PR and saves on the bead that owns it
what GitHub shows, with the signs it read, writing only what differs and never
an older read over a newer one. It must be callable from the cheap question,
the net and a webhook alike.

- **Gas Town's record.** The reconcile writes its record on the work bead:
  `pr_url`, `pr_number`, `pr_repo`, `pr_head_sha`, `pr_state`,
  `pr_last_checked_at`, `pr_merged_at`, `merged_sha`, `merged_target`,
  `merge_result`, `pr_reconcile_error` and the marker `pr_reconcile_pending`.
  `record_retryable_error` writes `pr_state`, `pr_last_checked_at` and
  `pr_reconcile_error` on a check that could not decide. It holds nothing about
  checks, reviews, threads or labels. Not covered: the record names the PR and
  its landing, and the update keeps its keys' meaning
  ([design, section 11](design.md#11-what-pr_last_checked_at-means)).
- **Gas City's PR monitor.** With `--create-repair-beads`, `gc github pr
  backfill` files a separate repair bead for a PR with failed checks, a conflict
  or a blocked merge, and refreshes it at each run. It keys the bead on `source`
  (`github-pr-monitor`), `github.owner`, `github.repo`, `github.pr` and
  `github.head_sha`, and writes `github.failure_kind`, `github.monitor`,
  `github.url`, `github.base`, `github.head`, `github.merge_state_status`,
  `github.state`, `github.failed_checks` and `github.pending_checks`
  (`cmd/gc/cmd_github.go`). Not covered: it writes nothing onto the bead that
  owns the PR, and it holds no required checks, reviews, threads or labels.
- **The github pack's webhook service.** `github/scripts/github_intake_service.py`
  writes no PR state onto a bead. The beads it writes are for comments addressed
  to the city. Not covered.
- **Gas City's webhook receiver.** It maps an event to an order (`WebhookRule`
  in `internal/config/webhook.go`) and writes no bead. Not covered.
- **bd.** A bead's `external_ref` holds a reference, not state. Not covered.

Conclusion: none covers it. The parts, their read instants and their signs join
the one key the PR-status effort added, `pr_github_read`, under that key's
warrant, and its one writer becomes `gctk pr refresh`, which also writes Gas
Town's `pr_state` and `pr_last_checked_at`. No key is added, and
`pr_reconcile_error` is no longer written.

## What runs each order, and how the landing order starts (units 1, 2 and 3)

The need: the cheap question every few minutes, the net more slowly, and the
landing order soon after an update and soon after a change on the store's side,
with nothing queued that a failure could strand.

- **Triggers.** `Order` in `internal/orders/order.go` takes `trigger` as
  cooldown (`interval`), cron (`schedule`, `tz`), condition (`check`,
  `check_timeout`), event (`on`), manual or webhook, one to an order.
  `CheckTriggerWithOptions` in `internal/orders/triggers.go` answers each.
- **Cooldown.** `checkCooldown` makes an order due once the time since its last
  run's start reaches `interval`. The run record is made before the run starts,
  so the interval counts from the start.
- **Event.** `gc event emit <type>` records an event of any type the pack names,
  best-effort (`cmd/gc/cmd_event_emit.go`). `checkEvent` makes an event order due
  when an event of its `on` type follows its cursor, with no filter on the
  payload, and it skips the dispatcher's own run records. `dispatchExec` in
  `cmd/gc/order_dispatch.go` sets the cursor to the event log's head
  (`SetCursor`) before the command runs, so events recorded during a run start
  one more run. Not chosen for the landing order: every writer of a store change
  it acts on would have to emit, and a change no writer announced would wait
  (design, section 5).
- **On demand.** `gc order run <name> [--rig]` (`cmdOrderRun` and
  `doOrderRunExecTracked` in `cmd/gc/cmd_order.go`) runs an exec order's command
  in the caller and writes a run record first, from which the cooldown counts. It
  does not check for a run that is open. The design's webhook rule uses it.
- **Condition.** `checkCondition` runs the check under `sh -c` with its output
  discarded (`cmd.Stdout = io.Discard`), so nothing it finds reaches the run, and
  its timeout defaults to `defaultConditionCheckTimeout = 10 * time.Second`
  (`internal/orders/order.go`). The lane runs every condition check at every pass,
  outside the dispatch budget, and waits for them all. Not chosen: a check every
  30 seconds, and an act that keeps failing would run again at every pass.
- **The lane.** `startOrdersLane` in `cmd/gc/orders_lane.go` runs a pass about
  every `[daemon] patrol_interval` after the last one ended, 30 seconds by
  default, and a pass starts at most `DefaultMaxOrderDispatchesPerTick = 4`
  cooldown, cron or event orders (`internal/config/config.go`).
- **One run at a time, for two minutes.** A run still open is skipped, not
  queued (`hasOpenTracking`). `runOrderTrackingSweepWatchdog` in
  `cmd/gc/city_runtime.go` closes a run record older than
  `orderTrackingSweepWatchdogStaleAfter = 2 * time.Minute` without checking its
  run, so a run past two minutes can overlap the next. The record lock and the
  update's read instants make that safe (design, section 7).
- **Timeout.** An exec order's timeout defaults to 300 seconds
  (`TimeoutOrDefault` in `internal/orders/order.go`), and `[orders] max_timeout`
  can only lower it (`effectiveTimeout`). On timeout the run's process group is
  signalled and then killed after `shellExecSignalGrace = 2 * time.Second`.
- **A queue for mechanical work.** `cmd/` and `internal/` hold no outbox, job
  queue or retry queue a pack can use, and no order hands another its findings.
  A failed exec run is recorded as `order.failed` and retried only by the
  order's next firing. Not covered: what a pass leaves undone stays a difference
  the next pass finds, so nothing is queued.
- **What a run leaves.** Each run writes a run record, which Gas City deletes
  after `[beads.policies.order_tracking] delete_after_close`, 7 days by default
  (`cmd/gc/cmd_order.go`) and 30 minutes in this city. The cooldown index reads
  the newest `orderTrackingHistoryIndexLimit = 256` runs per store
  (`cmd/gc/order_dispatch.go`). A rig's copy of a pack order is named
  `<name>:rig:<rig>` (`ScopedName`) and has its own runs and cooldown.
- **Tuning.** `[[orders.overrides]]` changes an order's `interval` and `timeout`
  from city.toml.

Conclusion: three cooldown exec orders, each naming gctk in its exec line: a new
`pr-poll` every 2 minutes, a new `pr-compare` every 10 minutes, and the
existing landing order, `orders/pr-reconcile.toml`, every minute. A webhook rule
starts the landing order on demand after its update.

## The webhook a later effort adopts (no unit)

The need: the route a webhook takes into the city later, so that the one-PR
update is the call it makes, and nothing here has to change for it.

- **The github pack's webhook service.** `github/scripts/github_intake_service.py`
  serves GitHub App deliveries. It accepts a delivery and runs the matching
  rules on a thread of its own (`enqueue_event_rules`). A rule names one event,
  a `match` table of payload paths and an ordered list of actions, in the city's
  `config/github-intake/rules.toml` (`load_rules`, `normalize_rule` and
  `rule_matches` in `github/scripts/github_intake_common.py`). The service runs
  a rule's actions in order and stops at the first that fails
  (`process_event_rules`). An `order` action runs `gc order run <name> [--rig
  <rig>]`, and a `command` action runs its argument list with each `{{path}}`
  filled from that path in the delivery's payload, and with `GC_GITHUB_REPO`,
  `GC_GITHUB_PR_NUMBER`, `GC_GITHUB_PR_URL` and the payload's file in its
  environment (`execute_rule_action`, `render_template`, `github_event_env`).
  Covered: a rule whose command is `gctk pr refresh` and whose next action runs
  the landing order (design, section 8).
- **Gas City's own receiver.** `[[webhook]]` mounts a hook whose rules map an
  event onto an order, with args projected from the payload (`WebhookRule` in
  `internal/config/webhook.go`). A public hook may fire only a formula order,
  never an exec order (`routeOrder` in `internal/webhooksink/sink.go`), and a
  tenant or private hook answers only a request from the loopback or one
  carrying `X-GC-Request` (`webhookRequestAllowed` in
  `internal/api/handler_webhook.go`). Not covered: GitHub can reach neither form
  with an exec order behind it.
- **GitHub.** Its documentation says "GitHub does not automatically redeliver
  failed deliveries", so a delivery is a hint to read, and the cheap question is
  the backstop.

## Gas Town merges no PR and reads no check

Gas Town's refinery formula, `gastown/formulas/mol-refinery-patrol.toml`, opens a
PR with `gh pr create` and records it with `gc gastown pr-merge-reconcile
record`. Neither that formula nor the reconcile command calls `gh pr merge` or
turns on auto-merge, and neither reads a check, so Gas Town waits for someone
else to merge the PR and then lands the bead. The pack's landing order asks
GitHub to merge itself (`mergePullRequest` with `expectedHeadOid`, or
`enqueuePullRequest`, in services/gctk/internal/gh/gh.go), which is why its
saved read holds required checks, approvals and threads that Gas Town's record
does not.

## The label writes, and no record of one that failed (unit 4)

The need: a PR's `status:` and `held:` labels equal what the store derives, on
every PR the city owns and on any other PR that carries one. A write that does
not land is made again by a later run, with nothing recording that it was owed.

- **Gas City.** No code in `cmd/` or `internal/` lists PRs with their labels or
  writes a GitHub label. A search for `addLabels`, `removeLabels`,
  `labels(first`, `LabelsOnLabelable` and `--add-label` finds only bead labels.
- **Gas Town.** No label code.
- **The github pack.** Its service writes no `status:` or `held:` label and
  derives none.
- **bd.** `AddLabels` and `RemoveLabel` in `internal/github/client.go` add
  labels to an issue number and take one off over REST, in a package internal to
  bd that gctk cannot import, with no rule that derives them. Not covered.
- **Retrying a failed write.** No queue exists (above). The comparison is the
  retry: the saved labels still differ, so a later run writes again.

Conclusion: none covers it. The landing order calls the pack's one writer of the
labels, `assets/scripts/pr-status-label.sh`, through the `reconcile` and `clear`
verbs it has, and the net calls `clear` for a PR no bead owns. They add no verb
and no key, and retire none of the old path's callers, which their own beads
retire (design, section 9).

## The board's line saying when GitHub was last asked (unit 5)

The need: one value, for each rig, saying when the cheap question last read
GitHub, which the board can show and mark stale.

- **Gas City's run history.** `GET /v0/city/{city}/orders/history` with
  `scoped_name` (`humaHandleOrderHistory` in
  `internal/api/huma_handlers_orders.go`) lists an order's runs, newest first,
  each with its `created_at`, `duration_ms` and `exit_code`. `gc order history
  <name> --rig <rig>` prints the same. Covered: the board reads the newest run
  of the rig's `pr-poll` that exited 0.
- **Gas City's events.** Each run is recorded as `order.fired`, then
  `order.completed` or `order.failed` (`internal/events/events.go`). Not chosen:
  the run history already answers per order and per rig.
- **A key the poll writes.** It would write a bead at every pass, which the
  design rules out. Not chosen.

Conclusion: the run history covers it. The board's unit reads it through the
supervisor's API, as the board reads the city today
(services/helm/internal/source/supervisor.go).

Read again when unit 5 was built, on 2026-11-17 at `gastownhall/gascity` main
09518c191, where none of the files cited here changed after 294079d53f:

- **What says a run exited 0.** An exec order's run records no exit code.
  `humaHandleOrderHistory` fills `exit_code` from `convergence.gate_exit_code`
  (`GateOutputFromMetadata`), which only the convergence handler writes
  (`internal/convergence/handler.go`). `dispatchExec` in
  `cmd/gc/order_dispatch.go` records how the run ended as a label on its record
  instead, through `SetOutcome`: `exec` when the command exited 0,
  `exec-failed` when it did not, and `exec-env-failed` when its environment
  could not be built (`RunOutcome.Labels` in `internal/orders/store.go`). The
  history lists each run's `labels`, and `gc order history` prints neither
  (`cmd/gc/cmd_order.go`). The board reads a run that exited 0 by its `exec`
  label.
- **The order's interval.** `GET /v0/city/{city}/order/{name}`
  (`humaHandleOrderGet`, and `toOrderResponse` in
  `internal/api/handler_orders.go`) answers the order's `interval` and
  `enabled` after the city's `[[orders.overrides]]` (`OrdersAll` in
  `cmd/gc/api_state.go`), and 404 for an order the city does not hold.
  Covered: the board takes three of that interval, and reads a rig with no
  enabled `pr-poll` as unwatched.
- **How far the history reaches.** The run retention,
  `[beads.policies.order_tracking] delete_after_close`, is in no answer of the
  supervisor's API: the config read (`humaHandleConfigGet` in
  `internal/api/huma_handlers_config.go`) carries the workspace, agents, rigs,
  providers and patches. Not covered: with no run that exited 0, the board
  gives the start of the oldest run the history holds, where the design gave
  the retention's 30 minutes.
