---
name: The Gas City search for the mayor (tk-1tfzr71.207)
description: What Gas City, bd and Gas Town ship for a city's mayor, for working through the operator's alert mail, for finding what needs the operator across rigs, for opening a seat, a conversation and a dispatch, and what the name mayor reaches in Gas City's defaults and routing, each with why it does or does not cover the mayor's need. Read it before changing the mayor's seat, its opener, its reads or the city page's mail count, or when Gas City gains a way to survey what needs an operator.
---

# The Gas City search for the mayor

The mayor adds a seat (`agents/mayor`), an opener verb (`gc-helm mayor` and
its row on Engage's People page) and a board element (the waiting count on the
city page). Upstream was read at `gastownhall/gascity` main 7b8d498424f4 and
`gastownhall/gascity-packs` main 44b9db7168f6, on 2026-11-22. Where the
city's own runtime matters, the installed `gc` was read too: 1.4.3, built from
the city's Gas City fork at 13cdf670ca, which the city's supervisor also runs.
The rulings it answers are on tk-1tfzr71.190 and tk-1tfzr71.207 (conversations
tk-9wz6v2b, tk-218zv3n and tk-5e70s01).

## The mayor Gas City and Gas Town ship

**Gas City's default mayor.** `gc init` writes a city whose one agent is
`mayor`, a named session in mode `always` (`DefaultCity` in
`internal/config/config.go`, line 5021), with the embedded prompt
`cmd/gc/prompts/mayor.md`: "plan work, manage rigs and agents, dispatch tasks,
and monitor progress" (lines 3 and 4), its dispatch `gc sling <agent>
<bead-id>`.

**Gas Town's mayor.** `gastown/agents/mayor/agent.toml` is `scope = "city"`,
`wake_mode = "fresh"`, `idle_timeout = "1h"` and one session, and
`gastown/pack.toml` runs it as a named session in mode `always` (lines 29 to
32). Its prompt says "Dispatch Liberally, Fix When Fast" (line 13), and its
responsibilities are work dispatch, rig lifecycle, cross-rig coordination,
escalation handling and strategic decisions such as priorities (lines 233 to
237). Gas Town's witness and deacon escalate to it by mail.

Composed: the seat is a named session of the city, one at a time and fresh at
each start, as both are, and it takes the name. It departs from both where the
operator ruled. It runs only once the operator opens it, so its mode is
`on_demand` with `sleep_after_idle`, as the po's is, and not `always`. It
implements nothing and fixes nothing, where Gas Town's mayor fixes when that is
fast. It sets no priority and places nothing, because each rig's po does that
with the operator, and it dispatches only work a ruling or placement already
authorized. It handles no escalation sent to it, because Gas City's alerts and
agents' escalations go to `human`, which it reads in a sitting. It runs no
rig's lifecycle, which is the operator's and mechanik's.

## Someone who works through the operator's mail

**Gas City's dashboard Mail page.** `routes/Mail.tsx`
(`internal/api/dashboardspa/web/frontend/src/`) lists the operator's mailbox,
whose wire alias defaults to `human` (`contexts/OperatorConfigContext.tsx`,
line 29), with a "needs you" filter of unread mail less the pool-worker
firehose and a nav badge that counts it (`selectOperatorActionableUnread` in
`web/shared/src/operator-mail.ts`). It archives, reads and replies one message
at a time. It covers looking at the mail and archiving it by hand, and it does
not judge a message, settle it with the agent that owns its problem, or file a
fix at a sender of junk. Reading the raw mail is the work the operator's ruling
takes off them, and the mailbox held 135 open messages, every one unread, on
2026-11-22. Composed: the mayor archives with Gas City's own `gc mail archive`,
and the dashboard stays as it is.

**The mayor's convention on the dashboard.** By the dashboard's convention the
mayor "digests the worker firehose and forwards only what needs the human"
(`web/shared/src/operator-mail.ts`, lines 44 to 46), and `operatorMail` keeps
mail whose sender is `mayor` as the operator's. The city's mayor does that
digesting in a sitting, with the operator, and sends them no mail.

**Pointing the alerts at an agent.** `docs/getting-started/troubleshooting.md`
(line 1144) says the `human` default of `GC_ESCALATION_RECIPIENT` "is a mailbox
with no session behind it" and advises pointing it at the agent that surfaces
alerts. Core's spawn-storm and orphan alerts read `GC_ESCALATION_TARGET` instead
(`spawn-storm-detect.sh`, line 33; `orphan-sweep.sh`, line 39), with the same
default. Not taken: the operator ruled that Gas City's settings and its
dashboard stay as they are, and an agent that took the alerts would be woken
for each one, the cost the operator declined while the city sends this much
junk mail. Both stay `human`.

**A wake on each message.** Gas City records a `mail.sent` event
(`internal/api/openapi.json`) and runs orders on events (`trigger = "event"`,
as in core's `orders/notify-on-human-gate-creation.toml`), and a plain
`gc mail send` requests no wake. An order on `mail.sent` would wake the mayor
for every message, which is the cost above, so none is added. Only the
operator's attach starts it.

## What needs the operator across the city

The mayor's overview is every rig's open questions and operator obligations:
human gates, conversations waiting for the operator or held in a sitting,
rulings owed, pull requests that wait on them and work assigned to them.

**Gas City's dashboard.** `attention/beadsNeedingAttention.ts`
(`internal/api/dashboardspa/web/frontend/src/`) is the selector behind the
Beads page's "Needs you": ready work that has sat unclaimed for a day, beads
escalated with `gc:escalation`, in-progress work whose assignee looks dead, and
work waiting on a named person. `web/shared/src/agents/needsYou.ts` adds the
agents awaiting input, errored, rate limited or stalled. Each is a projection a
browser page computes, with no command an agent can run, and none of them reads
this pack's human gates on their subjects, its conversations or the pull
requests the operator owes a move.

**`gc ready`.** It lists ready, claimable work across every store of the city
(`cmd/gc/cmd_ready.go`), and the flags its default work query passes leave out
`hold:mayor`, `hold:external` and work labeled `human` (line 42). It is the
work a pool can take, which by design leaves out what waits on a person.

**`gc beads list --label <label>`.** It reads one label across every store, and
a human gate is a gate bead, not a label, so it lists no gate and no
conversation by their kind.

Composed: the mayor reads the pack's board, `helm-svc board --json`, which
prints for each rig the document the board's rig page draws, from the same
reader (`services/helm/cmd/helm-svc/board.go`). Its Needs you view is every
need in the rig, the needs that count apart from those whose subject is parked
or held for the po, each with its kind and what it holds, and a rig whose read
failed carries its error in place of its document. In a rig that read, its Work
queue view lists apart, as unread, the work a reader could not answer, such as
a pull request whose facts no read gave (`WorkQueue` in
`services/helm/internal/rigboard/document.go`). So the overview counts what the
operator's board counts, adds no store and no second queue, and a rig or a bead
that did not read is named, never left out. The read took 12 seconds over the
city's seven rigs on 2026-11-22.

## Opening the seat

**Gas City's named session and its attach.** A `[[named_session]]` in mode
`on_demand` "reserve[s] identity and materialize[s] when work or an explicit
reference requires it" (`NamedSession` in `docs/reference/config.md`, line
603), and `gc session attach` asks the controller to start a session that is
not running, waits for it, then attaches (`gc session attach --help`).
Composed: the mayor is such a session of the city, as each rig's po is of its
rig, and its opener is that attach.

**The opener verb.** `gc-helm mayor` is a third seat on gc-helm's seat verb,
beside `po` and `mechanik`, and a row of the People page's seat list, which the
board's form reads from `gc-helm.sh conversations --json`. It grows gc-helm.sh
rather than gctk as an exception the operator granted to AGENTS.md's rule that
new pack code is written in Go, in gctk. Their words, in conversation
tk-218zv3n on 2026-11-21: "Yes, this shoudl go where the current standing
agents sit. it'll get moved over when the other agents move over." The three
seats' commands move into gctk together, with the conversation commands, in
tk-ssm8qns.15. The board's move, tk-1tfzr71.24 (#1617), took takeaway, park,
place and accept into gctk and left the seat commands in shell. The rename from
the postmaster changes the seat's name and adds no logic.

## A conversation, a placement and a dispatch

**A conversation.** Gas City has no command that opens a sitting on a subject:
`gc session new` starts a session from a template with a title, and
`gc session attach` joins one, and neither hands the session a subject or a
question. The pack's `gc-helm.sh open <bead> --reason <question>
--body <context>` files a conversation in the operator's queue, which the
`waits` skill names as the writer for asking the operator for a conversation,
and `gc-helm.sh open --new-subject --rig <rig>` files one for a matter with no
bead. Composed: the mayor arranges a decision's sitting with that writer.

**A placement.** Gas City's hold, `bd set-state <bead> hold=mayor --reason`,
puts a bead in its rig's po's queue (`HoldMayorLabel` in package beadmeta), and
`gctk bead place` is the po's placement. Composed: the mayor holds a matter
that needs a priority or a new commitment for the po, and places nothing.

**A dispatch.** `gc sling` routes a bead to a pool on its formula
(`cmd/gc/cmd_sling.go`). Composed: the mayor dispatches work a ruling or
placement already authorized through the `work` skill's writers, which call it.

## What the name mayor reaches

**Mail addressed to `mayor`.** Gas City's start warmup mails its failed checks
to `mayor` (`defaultWarmupMailTo` in `internal/warmup/warmup.go`, line 34), and
bd's Dolt compact mails its quarantine alerts to `GC_DOLT_COMPACT_ALERT_TO`,
`mayor` by default (`examples/bd/dolt/commands/compact/run.sh`, lines 402 and
2014), which the city's `mol-dog-compactor` order runs every two hours and this
city does not set. Both are plain `gc mail send`, so neither wakes a session. A
bare `mayor` names the bound `<binding>.mayor` named session
(`FindNamedSession` in `internal/config/named_sessions.go`, line 16), and the
mail list route reads a named session's mail under each of its addresses
(`resolveMailQueryWithContext` in `internal/api/handler_mail.go`, line 182).
So this mail, which no seat read before, reaches the mayor's mailbox, and the
mayor lists it with the operator's in a sitting. Gas Town's roles mail `mayor/`
too, and the city imports no Gas Town role.

**A route to the mayor.** Upstream Gas City's `hold-label-routed-to` doctor
check wants each bead a `hold:<value>` label holds routed to the agent `<value>`
names, and its fix writes that route, the bound `<binding>.mayor` once a bound
agent answers to `mayor` (`holdRouteTarget.route` and `Fix` in
`cmd/gc/doctor_hold_label_routed_to.go`, lines 84 and 176, through
`boundRoutedToAliases` in `cmd/gc/doctor_routed_to_checks.go`, line 197).
Routed metadata is not a named session's own demand
(`computeNamedSessionDemandOn` in `cmd/gc/build_desired_state.go`, line 1076),
but an on-demand named session's backing template counts ready routed work as
pool demand, which "wakes the sleeping singleton" (line 1398). So on upstream's
`gc`, a `gc doctor --fix` would route every bead in the po's queue to the
mayor, and a bead routed there would wake the seat once no hold held it.

The city's `gc` has no such check. Its Gas City fork's commit d62873fce6
(gc-uyshxy, the fork's pull request #259) makes every `hold:<value>` label a
hold, whatever its value names, and deletes the check and its fix: the check's
191 lines and its test's 727, in a change of 138 files, 2,018 lines added and
1,889 removed. The city's `gc` and its supervisor run the fork's main at
13cdf670ca, which carries that commit (verified on tk-1tfzr71.234 at
2026-11-25T01:45Z), and at 2026-11-25T08:31:15Z
`gc doctor --check hold-label-routed-to` answered that no registered check
matches. So the mayor needs a `gc` that carries d62873fce6, and the pack adds
nothing of its own for the route: no step skips a fix, and the seat keeps its
name. The pack holds new work for the po with `hold:mayor` and no route, by the
operator's ruling of 2026-11-25 in conversation tk-5e70s01, which keeps the
label and withdrew its move to `hold:po`.

**`gc sling mayor` and `gc session attach mayor`,** which Gas City's docs
teach, now reach the seat: the sling hits its `sling_query`, which refuses
plain slung work as the po's does, and the attach opens a sitting as
`gc-helm mayor` does. The pack's `gc-terminal-attach.sh`, the city web
terminal's attach target, defaults to the bare `mayor`, so a city that runs
that terminal opens a mayor sitting when the operator opens the terminal.

## Listing the mailbox for the mayor

`gc mail inbox` lists only unread mail, and `gc mail archive` selects read mail
(`--include-read`) only by a sender or a subject (`cmd/gc/cmd_mail.go`). The
mail route with `status=all` lists the open messages, read or unread
(`humaHandleMailList` in `internal/api/huma_handlers_mail.go`, line 194, whose
`all` reads `Provider.All`, "all open messages (read and unread)",
`internal/mail/mail.go`, line 178). The mayor's prompt reads that route for
`human` and for its own name, finding the supervisor with `gc dashboard serve`
and the city's name with `gc status --json`, and reads each message with
`gc mail peek`, which leaves it as it was. The route's answer says when it is
not the whole mailbox: `partial` and `partial_errors` when one of the city's
mail stores fails while the others answer, and `next_cursor` when more messages
follow the page (`mailKeysetBody`, line 182, and `MailListBody` in
`internal/api/huma_types_mail.go`, line 21). The prompt prints both with the
messages.

## The count on the board

`GET /v0/city/{city}/mail/count?agent=human` (`humaHandleMailCount`, line 432)
answers `total` and `unread`, where `total` counts the recipient's open
messages, read or unread, and an archive closes a message (`CountRecipients` in
`internal/mail/beadmail/beadmail.go`, line 1037). Composed: the city page shows
that total, cached a minute, and lists no message. It counts the operator's
mailbox and nothing else, so it is not a count of the city's open questions,
which the rig pages count. The list route's `total` with `status=all` is the
same number (130 against 130, and `gc mail count human` the same, on
2026-11-19), but it returns the messages. The dashboard's badge counts unread
mail less the pool-worker firehose, a different number, and the ruling asked
for every message that waits.
