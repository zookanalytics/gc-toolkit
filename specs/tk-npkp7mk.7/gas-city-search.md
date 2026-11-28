---
name: Gas City search — mailing a person about a stuck prompt
description: The search behind the prompt-alert orders and their verb, gctk session prompt-alert, which mail the escalation recipient and the mechanik once about each prompt a pool seat waits at that Gas City escalated, and once when it clears. It covers the work ladder's nudge_refused escalation, the pending-interaction events, event-triggered orders, core's escalate.sh with its incident keys and GC_ESCALATION_RECIPIENT, the notify-on-claims-stalled orders, gc mail send --dedup, why none delivers this alert as it stands, the measurements its reads rest on, and the gaps it leaves. Read it when changing the orders or the verb, or when a review asks why the alert is the pack's.
---

# Gas City search for tk-npkp7mk.7

Gas City is read at gastownhall/gascity main 6dce31bbb6 (2026-11-27), and its
published packs at gastownhall/gascity-packs main 44b9db7168f6 (2026-11-20). A
path without a repository is Gas City's. The city runs the fork's gc 1.4.3
(210638e33c), which is not evidence here. The measurements are this city's
event log, read on 2026-11-28 between 01:35Z and 01:45Z.

## The trigger: work.escalated with reason nudge_refused

**Searched.** A Gas City signal that a session waits at a prompt nobody
answers, repeated while it waits.

- The work ladder records `work.escalated` with reason `nudge_refused` when a
  pool seat cannot take a counted nudge because it waits at a pending
  interaction or its runtime is unavailable (`(*ladderPass).nudge` in
  `cmd/gc/work_ladder_lane.go`, on `runtime.ErrPendingInteraction` or
  `runtime.ErrRuntimeUnavailable`, and the notice path in
  `cmd/gc/work_ladder_notice.go`). It raises the alert at the third refusal in
  a row and every sixth after, with refused nudges paced at
  `DefaultPausedCap` (10 minutes) or slower, so the repeat comes about every
  `DefaultCap`, hourly, "never silenced after one alert" (`refusalAlerts`,
  `refusedAlertAt` and `refusedRealertEvery` in
  `internal/workladder/decide.go`, and `internal/workladder/policy.go`).
- Its payload is `WorkLadderPayload` (`internal/events/work_payloads.go`):
  `session_id`, `session_name`, `template`, `provider`, `bead_id`,
  `store_ref`, `generation` and `reason`. It carries no request id, so the
  prompt it refused at has to be read from the pending events.
- The ladder paces pool seats alone: open pool-managed session rows with a
  runtime name, or a canonical-singleton pool seat a named session took over,
  less one-shot agents (`ladderGoverns` and `ladderSeat` in
  `cmd/gc/work_ladder_lane.go`).
- The one reader of `work.escalated` in Gas City is the claims-stall guard,
  which reads it only with reason `trigger_unanswered`
  (`(*claimStallGuard).observe` in `cmd/gc/claim_stall_guard.go`).

**Why it does not deliver the alert as it stands.** The escalation reaches the
event log and no one: no order, script or service of Gas City or its published
packs mails on it.

**Measured.** In the seven days to 2026-11-28T01:37Z the log held 21
`nudge_refused` escalations, every one of them from the three long waits of
2026-11-23 and 2026-11-24 (`gc events --type work.escalated --since 168h
--payload-match reason=nudge_refused`, 12.6 s). Each prompt's first came 22,
47 and 22 minutes after the prompt appeared, then about every 62 minutes: 7,
6 and 8 escalations over waits of 7h15m, 6h24m and 14h7m. In the 48 hours to
the same time the log held 3 `work.escalated` events, none of them
`nudge_refused`.

## The prompt: session.pending and session.pending_cleared

**Searched.** A record of the prompt a session waits at, and of its end.

- The controller's pending-interaction lane records `session.pending` when a
  session gains a pending interaction and `session.pending_cleared` when it is
  gone, "once per transition, not once per detection pass", checking every
  active session every 5 seconds, and on a restart it rebuilds what it
  announced from the log (`internal/pendingwatch/pendingwatch.go`,
  `cmd/gc/pending_interaction_lane.go`, and docs/reference/api.md, "Pending
  Interactions").
- `SessionPendingPayload` carries `session_id`, `template`, `alias`,
  `request_id`, `kind`, `prompt`, `options` and `metadata`, and
  `SessionPendingClearedPayload` repeats `session_id`, `request_id` and `kind`
  with a `reason`: `resolved`, `replaced` or `session_gone`
  (`internal/api/event_payloads.go`). A pane's approval has the request id
  `tmux-` and a hash of the approval (`internal/runtime/tmux/interaction.go`),
  so the same prompt coming back carries the same id. The verb keys a prompt by
  its session, its request id and the seq of its `session.pending`.
- `GET /v0/city/{cityName}/pending` lists the pending interactions and
  `POST .../session/{id}/respond` answers one (docs/reference/api.md), and the
  dashboard shows them (docs/gascity/human-engagement.md, "Where a question
  surfaces"). Both reach only someone already looking.

**Why it does not deliver the alert as it stands.** Nothing reads these events
to tell anyone. They are also no alert on their own: most prompts clear inside
Claude Code's two-minute block, and only Gas City's escalation says a prompt
has outlasted the ladder's nudges.

**Measured.** In the 48 hours to 2026-11-28T01:40Z the log held 33
`session.pending` and 34 `session.pending_cleared` events, and no escalation of
any of their sessions. The pass reads both types with no window, which gc
answers with the newest page of each, 500 events (`fetchCityEvents` in
`cmd/gc/cmd_events.go` at 6dce31bbb6). At 2026-11-28T08:25Z each such read
took about 10 seconds and answered 76 events reaching back to 2026-11-23, from
the log and its archives, where a day of `session.pending` took about 3
seconds. The census on tk-p4by7cv found that the lane recorded 6 of the 18
two-minute prompts in one 72-hour window, and all three long waits.

## Event-triggered orders

**Searched.** An order trigger that runs a pass on an escalation of one reason,
or on a prompt's clear.

- An event trigger names one event type and matches every event of it after
  the order's cursor, with no payload filter (`checkEvent` in
  `internal/orders/triggers.go`).
- An exec order receives no event, only its environment, and its cursor moves
  to the log's head before its command runs (`dispatchExec` in
  `cmd/gc/order_dispatch.go`), so a run that fails never sees its event again.
  A script re-reads with `gc events --type <t> --since <d>`, as core's do.

**What the pack composes.** Two event orders, one on `work.escalated` and one on
`session.pending_cleared`, run one pass that reads the escalations of the last
two hours and, when one is `nudge_refused` or a prompt is still owed mail, the
prompts and clears of the last day. There is no cadence order: Gas City's
hourly escalation is the cadence, so a failed run or a dropped escalation is
made good by the seat's next escalation or any pass before it, as the
operator's ruling in conversation tk-0alsb23 asked, with no timer of ours.

## Delivery: core's escalate.sh, its incident keys, and GC_ESCALATION_RECIPIENT

**Searched.** A Gas City hook that mails a city's escalation recipient once per
incident.

- Core's `internal/bootstrap/packs/core/assets/scripts/escalate.sh` mails
  `${GC_ESCALATION_RECIPIENT:-human}`, adds `--notify` for every recipient but
  `human`, and with `--incident-key` keeps an unchanged incident quiet for
  `GC_ESCALATE_REMINDER_SECONDS` (a day by default) after its last delivered
  notice, its state best-effort under `<city>/.gc/incidents`.
  `--resolve-incident` forgets an incident and sends nothing. The variables are
  documented in docs/getting-started/troubleshooting.md, "Maintenance
  escalation and completion routing", where an agent recipient "is woken with
  `--notify`".
- Its callers find it by their own search: `GC_ESCALATE_SCRIPT`, then
  `assets/scripts/escalate.sh` in each pack `GC_ESCALATE_SEARCH_PACKS` names
  under `${GC_SYSTEM_PACKS_DIR:-<city>/.gc/system/packs}`, then the caller's own
  directory (core's `notify-claims-stall.sh`, `reaper.sh` and
  `jsonl-export.sh`) or a path relative to the gascity checkout (bd's
  `examples/bd/dolt/assets/scripts/_notify.sh`). The hook's header gives the
  search's reason: "Packs can override escalation by shipping
  assets/scripts/escalate.sh and placing that pack earlier in
  GC_ESCALATE_SEARCH_PACKS." Gas City retired the per-city `.gc/system/packs`
  tree in d71b469e54 (#3344, 2026-06-14), "compose builtins via pinned
  imports", and now prunes it and resolves builtin packs from the user-global
  cache (`pruneRetiredSystemPacks` in `cmd/gc/embed_builtin_packs.go`). Nothing
  sets `GC_SYSTEM_PACKS_DIR`, so that reason no longer holds: no override pack
  is found.

**Why it does not deliver the alert as it stands.** A gc-toolkit exec order
cannot run it. The order's env names only its own pack's directory
(`orderExecEnvWithError` in `cmd/gc/order_store.go`), core ships no command
that prints its directory, and `gc import list` prints no local path. In this
city `<city>/.gc/system/packs` does not exist, and neither `city.toml` nor the
environment of the supervisor, which orders inherit, sets `GC_ESCALATE_SCRIPT`,
`GC_ESCALATION_RECIPIENT` or `GC_SYSTEM_PACKS_DIR`, so every core escalation
runs core's own copy and goes to `human`.
Even reached, its `--notify` would request the mechanik's turn, which the
operator's ask rules out: a mail notice to a running session is typed into it
as a turn of its own at its next idle boundary (`deliverMailNotifyLegacy` in
`cmd/gc/cmd_nudge.go`, `NudgeDeliveryWaitIdle`).

**What the pack composes.** `gc mail send --json` to each recipient. The
escalation recipient's mail requests its turn when it is not `human`, as the
hook's does, and the mechanik's copy requests none, since the prompt hook the
city installs, `gc mail check --inject`, shows a session its unread mail at its
next turn. That copy of the hook's recipient and wake rule is an entry in
docs/gctk-architecture.md's re-implementation register. The fault at the
source, a hook no pack outside the gascity repository can run and an override
search that walks a pruned tree, is the upstream finding tk-6521737, whose fix
is about ten lines: resolve the hook once from the composed packs, export it as
`GC_ESCALATE_SCRIPT` into each exec order's env beside `PACK_DIR`, and have the
scripts read it.

## The sister alert: notify-on-claims-stalled

**Searched.** An order that already mails a stuck agent and its recovery.

- Core's `notify-on-claims-stalled` and `notify-on-claims-resumed` run
  `notify-claims-stall.sh` on `agent.claims_stalled` and
  `agent.claims_resumed`. It reads both types over a 15-minute lookback, mails
  a stall once through `escalate.sh` under the incident key
  `claims-stalled:<episode>`, and on resumption resolves that incident and
  mails a note as its own incident, `claims-resumed:<episode>`. A send that
  fails exits non-zero (`internal/bootstrap/packs/core/orders/` and
  `assets/scripts/notify-claims-stall.sh`).

**Why it does not deliver the alert as it stands.** It reads the claims-stall
guard's two events alone, and the guard reads `work.escalated` only for
`trigger_unanswered`. The verb follows its shape: two event orders over one
pass that re-reads its events, one alert per incident, a short note when it
ends, and a send that fails failing the run.

## Keeping one mail per prompt: gc mail send --dedup

**Searched.** A send that goes once per key.

- `gc mail send --dedup <key>` suppresses the send while a live, unarchived
  message with the key is in the same mailbox, and "once the recipient
  archives the message the stream may alert again; senders that want a longer
  re-alert cadence keep their own last-sent state" (`newMailSendCmd` and
  `doMailSendJSON` in `cmd/gc/cmd_mail.go`, and `SendDeduped` in
  `internal/mail/beadmail/beadmail.go`). With `--json` a suppressed send
  answers `already_done`.

**Why it does not hold the alert to one mail as it stands.** The mayor archives
the `human` mail whose matter is handled (`agents/mayor/prompt.template.md`),
and a pass re-reads the events on every escalation and clear, so after an
archive the next escalation would mail the prompt again, and a clear it reads
again would mail its note again. So the verb keeps its own last-sent
state, as the help advises: a ledger of whom each prompt's alert and note have
reached, under a lock its passes share, in the city's
`.gc/runtime/packs/gc-toolkit` beside the mail-notify ledger. It still sends
with `--dedup`, so a send whose ledger write was lost is not sent twice while
its message is live. The pack's own keyed record, the patrol finding
(`assets/scripts/patrol-finding.sh`), keeps a situation as a bead and slings a
first reaction on it, which makes the prompt work for an agent. The operator
asked to be told, so the alert is mail.

## What the published packs hold

gascity-packs at 44b9db7168f6 holds no mention of `work.escalated`,
`nudge_refused` or `session.pending` (GitHub code search of the repository,
2026-11-28).

## What the alert leaves uncovered

- **Named sessions.** The ladder escalates pool seats alone, so a named
  session at a prompt, such as a sitting's or a patrol role's, is never
  alerted. No timer of the pack's covers it, as the operator's ruling asks.
- **A prompt the lane never records.** A seat escalated at a prompt Gas City
  did not record is not alerted. The lane recorded every long wait in the
  census window.
- **A prompt older than the log.** Gas City records a prompt once, when it
  appears (`Watcher.apply` in `internal/pendingwatch/pendingwatch.go` at
  6dce31bbb6). A seat whose escalations no pass takes until the prompt has
  left the newest 500 prompts in the log and its archives is not alerted.
  This city keeps its archives 168 hours and records about 15 prompts a day,
  so that takes a week with no pass, such as orders first started beside a
  prompt a week old.
- **A clear that never comes.** A prompt up when its session closed or slept
  while no watcher ran gets no `session.pending_cleared`, so its incident stays
  in the ledger and no note goes.
- **A clear whose run failed.** Its note waits for the next escalation or
  clear in the city. The pass reads the clears with no window, which gc
  answers with the newest 500 from the log and its archives
  (`fetchCityEvents` in `cmd/gc/cmd_events.go` at 6dce31bbb6), so the note is
  lost only if no pass runs before the clear leaves them. This city keeps its
  archives 168 hours (`archive_retain_age` in its `[events.rotation]`) and
  records about 15 clears a day, so that takes a week with no pass.
- **A city's own escalation hook.** A city that overrides `escalate.sh` or
  sets `GC_ESCALATE_SCRIPT` does not have this alert routed through it until
  tk-6521737 is fixed.
