---
name: Gas City search — waking a converse sitting for its mail
description: The search behind the mail-notify orders and their verb, gctk mail notify: the primitive looked for in Gas City and its published packs, why none covers the wake, and the cooldown trigger the pack composes for the orders' cadence. Read it when changing the orders or the verb, or when a review asks why the wake is the pack's.
---

# Gas City search for tk-qpnzxnj

Gas City is read at upstream main c377651cb318 (2026-11-23), and its published
packs at gascity-packs 44b9db7168f6 (2026-11-20). A path without a repository
is Gas City's. The city's fork of Gas City is not evidence here, and the one
place it is named below is the course the operator ruled out.

## The two orders, on mail.sent and mail.replied

**Searched.** A setting, command or order that requests a recipient's turn
when mail arrives for it, whoever sent the mail.

- `gc mail send --notify` and `gc mail reply --notify` "request a recipient
  turn (including a managed wake if not running)" (`newMailSendCmd` and
  `newMailReplyCmd` in `cmd/gc/cmd_mail.go`). The sender decides, one message
  at a time, and a send without the flag requests nothing.
- The API's send and reply, which the dashboard uses, record `mail.sent` and
  `mail.replied` with the message and take no notify option
  (`humaHandleMailSend` and `humaHandleMailReply` in
  `internal/api/huma_handlers_mail.go`). So mail from the dashboard can never
  request a turn.
- `gc mail check --inject`, which Gas City installs as a prompt hook
  (`internal/hooks/config/claude.json`, and Codex's in
  `internal/bootstrap/packs/core/overlay/per-provider/codex/.codex/hooks.json`),
  shows unread mail to a session once something else starts its turn
  (`cmdMailCheckWithFormat` in `cmd/gc/cmd_mail.go`). It starts no turn of its
  own.
- Core's orders: `nudge-mail-sweep` closes stale delivered nudges and read mail,
  and `nudge-on-route` wakes a session when a bead is routed to it
  (`internal/bootstrap/packs/core/orders/`). Neither reads unread mail.
- The published packs hold no order on `mail.sent` or `mail.replied` and no
  other mention of either event. The one sender that passes `--notify` is an
  example in Gas Town's crew prompt (`gastown/assets/prompts/crew.template.md`),
  and the only `gc session nudge` in the messaging packs is the Slack bridge's
  own (`slack-full/scripts/slack_chat_bind_room.py`).
- An open proposal: gastownhall/gascity#1966, a design issue on waking a
  coordinator session on its mail. Its maintainer ruling (2026-06-28) is that
  such sessions "wake on mail with a debounce", with implementation still to
  follow, and no Gas City release carries it.
- An open draft, gastownhall/gascity#6387, wakes a pool that has no session
  for unread mail to its alias whose sender passed `--notify`. Mail sent
  without the flag, the API's included, still requests nothing there.

**Gap.** A turn for mail whose sender did not ask for one. Gas City records
every send and reply as an event, and an exec order on an event is its shape
for reacting to one: `trigger = "event"` with `on` naming the type
(`Order.On` in `internal/orders/order.go`). The trigger names one type and
filters on no payload, so the pack runs two orders, one per type, and each
reads what it needs again ("Orders", the `event` trigger in
`docs/tutorials/07-orders.md`, which also states that delivery is at least
once and that event orders share the per-pass dispatch budget). The course the
operator ruled out was a Gas City setting built on the city's fork, which only
the CLI's send and reply applied. Once a Gas City release wakes a session on
its mail as #1966 rules, the mail-notify orders and their verb retire.

## The cadence order, mail-notify-reconcile

**Searched.** A Gas City primitive that runs the pass again when a mail
event's run fails, or when no run comes for the mail at all.

- An exec order on an event moves its event cursor before its command runs,
  "otherwise a crash after the side effect can replay the event"
  (`memoryOrderDispatcher.dispatchExec` in `cmd/gc/order_dispatch.go`). So a
  run that fails does not see its event again.
- An order that has never run fires only on events recorded after the
  orchestrator started, or after the reload that added it (the `event` trigger
  in `docs/tutorials/07-orders.md`). So mail sent before the orders load starts
  no run.
- The `cooldown` trigger runs an order once its `interval` has passed since its
  last run, whatever the bus carried (`Order.Interval` in
  `internal/orders/order.go`, and the trigger table in
  `docs/tutorials/07-orders.md`).

**Gap.** None. The cooldown trigger is the primitive, and the pack composes
it: mail-notify-reconcile runs the event orders' pass every 15 minutes, under
the same lock and ledger, so mail whose event's run failed, whose event the bus
lost, or which came before the orders loaded still requests its sitting's turn
with no new mail.

## The verb, `gctk mail notify`, and what it reads

**Searched.** A Gas City read of the unread mail a session has not been told
of, and a command that sends Gas City's own mail notice for a message already
stored.

- `gc mail inbox <session> --json` lists the session's unread messages and
  every address its mailbox answers to: its alias, its id and its earlier
  aliases (`doMailInboxTargetWithJSON` and `jsonRecipients` in
  `cmd/gc/cmd_mail.go`). A handoff is mail from one of those addresses.
- `gc nudge status <session> --json` lists the nudges still to be delivered to
  a session, each with its source. A mail notice from the nudge queue has
  source `mail` and names its message (`deliverMailNotifyLegacy` in
  `cmd/gc/cmd_nudge.go`), and one the session's conversation lane carries has
  the lane principal `gc:mail` and names none (`laneNudgeItem` in
  `cmd/gc/nudge_lane_status.go`, `mailNoticePrincipal` in
  `cmd/gc/cmd_nudge.go`).
- `gc session nudge --delivery wait-idle <session> <text>` delivers at the
  session's next idle boundary and never into a running turn. For a session
  that is not running it queues the nudge and requests a managed wake
  (`deliverSessionNudgeLegacy` in `cmd/gc/cmd_nudge.go`). Upstream's session
  nudge has no flag naming the bead a nudge is about.
- Gas City's mail notice, "You have mail from <sender>", is sent only from a
  send or a reply that passes `--notify` (`mailNotifyText` and
  `sendMailNotifyWithOp` in `cmd/gc/cmd_nudge.go`).

**Gap.** Nothing in Gas City compares a session's unread mail with the notices
already on their way to it, and no command sends its notice for a stored
message. So the verb reads the three lists and sends the same words through
`gc session nudge`. A session's state comes from `gc session list --json`, in
the words of `session.State` (`internal/session/manager.go`), and the verb wakes
only one that is active, awake, asleep, creating or start-pending.

## The notify ledger and its lock

**Searched.** A Gas City record of which messages a turn was already requested
for.

- The nudge queue keeps pending, in-flight and dead nudges, never delivered
  ones (`cmdNudgeStatus` in `cmd/gc/cmd_nudge.go`).
- A delivered nudge leaves `last_nudge_delivered_at` on the session's bead
  (`stampLastNudgeDeliveredAt` in `cmd/gc/cmd_nudge.go`), an advisory marker
  of the time, which names no message.
- Core's `nudge-on-route` keeps the pairs it has nudged in a file of its own,
  `$GC_PACK_STATE_DIR/nudge-on-route-state.json`
  (`internal/bootstrap/packs/core/assets/scripts/nudge-on-route.sh`).
- `gc session nudge --key` is Gas City's own record of a nudge already sent: a
  rerun under the same key reports the first run's outcome and sends nothing,
  after delivery too, but only "while the op journal records this command"
  (`newSessionNudgeCmd` and `sessionNudgeKeyUsage` in `cmd/gc/cmd_session.go`,
  and `deliverSessionNudgeKeyed` in `cmd/gc/cmd_nudge.go`). With no `[ops]`
  gate set, the journal records only over a SQLite sessions store. Set to
  `auto` or `require`, it records over a store that can record ops, which a
  store bd serves cannot until bd's writes take `--if-revision`, and no
  released bd's do (`OpsConfig` in `internal/config/ops.go`, and
  `CheckRecordsByDefault` in `internal/opjournal/default_recording.go`). A city
  `gc init` makes keeps its sessions in a SQLite store under `.gc/store` by
  default, and a city made before that keeps them in its work ledger, since an
  upgrade leaves its storage as it was (`--storage` in `cmd/gc/cmd_init.go`,
  and "Your city's storage stays as it was" in
  `docs/getting-started/upgrading.md`). There a keyed nudge runs unrecorded
  with a warning, and a rerun under the same key nudges again (`newCLIOp` in
  `cmd/gc/op_record.go`, and `cannotRecord` in
  `internal/opjournal/legacyop/legacyop.go`).

**Gap.** A record, per message, that outlives a pass in a city whose op journal
does not record its nudges, so a pass that runs again on the same mail requests
no second turn. The city this pack runs in is one: its `city.toml` has no
`[storage]`, so bd serves its sessions with its work, and its bd, 1.3.4, takes
no `--if-revision`, so no `[ops]` setting would record a keyed nudge there. The
verb keeps the record as core does, in the pack's state directory,
`.gc/runtime/packs/gc-toolkit`, holding only messages still unread, under a
lock every order's run takes. It passes no `--key` beside the ledger, because in
such a city the key records nothing and adds a warning to every nudge, and in a
city whose journal records nudges the ledger already holds what the key would.
Once the city keeps its sessions in a store the journal records, the ledger's
move onto a keyed nudge is due, as the "Mail wake" warrant in `docs/warrants.md`
says.
