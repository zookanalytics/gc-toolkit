---
name: The Gas City search for the postmaster (tk-1tfzr71.207)
description: What Gas City and Gas Town ship for working through the operator's alert mail, opening a seat, listing the mailbox and counting it, each with why it does or does not cover the postmaster's need. Read it before changing the postmaster's seat, its opener or the city page's mail count, or when Gas City gains a way to triage an operator's mail.
---

# The Gas City search for the postmaster

The postmaster adds a seat (`agents/postmaster`), an opener verb
(`gc-helm postmaster` and its row on Engage's People page) and a board element
(the waiting count on the city page). Upstream was read at
`gastownhall/gascity` main bfe7a19cc23a and `gastownhall/gascity-packs` main
23d007dac5d4, on 2026-11-19. The rulings it answers are on tk-1tfzr71.190 and
tk-1tfzr71.207 (conversations tk-9wz6v2b and tk-218zv3n).

## Someone who works through the operator's mail

**Gas City's dashboard Mail page.** `routes/Mail.tsx`
(`internal/api/dashboardspa/web/frontend/src/`) lists the operator's mailbox,
whose wire alias defaults to `human` (`contexts/OperatorConfigContext.tsx`,
line 29), with a "needs you" filter of unread mail less the pool-worker
firehose and a nav badge that counts it (`selectOperatorActionableUnread`).
It archives, reads and replies one message at a time. It covers looking at the
mail and archiving it by hand, and it does not judge a message, settle it with
the agent that owns its problem, or file a fix at a sender of junk. Reading the
raw mail is the work the operator's ruling takes off them, and the mailbox held
130 open messages, every one unread, on 2026-11-19. Composed: the postmaster
archives with Gas City's own `gc mail archive`, and the dashboard stays as it is.

**The mayor.** By the dashboard's convention the mayor "digests the worker
firehose and forwards only what needs the human"
(`web/shared/src/operator-mail.ts`, lines 44 to 46). `gc init` writes a city
whose one agent is a mayor, a named session in mode `always`
(`DefaultCity` in `internal/config/config.go`, lines 4998 to 5004), and its
prompt (`cmd/gc/prompts/mayor.md`) works its own inbox, not `human`. In
`gascity-packs/gastown/agents`, the witness's and the deacon's only mail is
escalation to the mayor (witness prompt, lines 22 and 311; deacon prompt, line
226), and the mayor's duties include "Work dispatch" and "Escalation handling:
Resolve issues Witnesses can't handle" (mayor prompt, lines 233 to 236). It does
not cover the need. The operator ruled a postmaster and not a mayor: it plans,
places and starts no new work, where a mayor dispatches. It runs only while the
operator holds a sitting, where `gc init`'s mayor is always on. And Gas City's
alerts go to `human`, not to a mayor. The seat takes the mayor's shape where it
fits: a named session of the city, waking fresh, one at a time (gastown's
`agents/mayor/agent.toml`).

**Pointing the alerts at an agent.** `docs/getting-started/troubleshooting.md`
(lines 1142 to 1148) says the `human` default of `GC_ESCALATION_RECIPIENT` "is a
mailbox with no session behind it" and advises pointing it at the agent that
surfaces alerts. Core's spawn-storm and orphan alerts read
`GC_ESCALATION_TARGET` instead (`spawn-storm-detect.sh`, line 33;
`orphan-sweep.sh`, line 39), with the same default. Not taken: the operator
ruled that Gas City's settings and its dashboard stay as they are, and an agent
that took the alerts would be woken for each one, the cost the operator
declined while the city sends this much junk mail. Both stay `human`, and no
default, escalation or fallback names the postmaster.

**A wake on each message.** Gas City records a `mail.sent` event
(`internal/api/openapi.json`) and runs orders on events (`trigger = "event"`,
as in core's `orders/notify-on-human-gate-creation.toml`), and a plain
`gc mail send` requests no wake. An order on `mail.sent` would wake the
postmaster for every message, which is the cost above, so none is added. Only
the operator's attach starts it.

## Opening the seat

**Gas City's named session and its attach.** A `[[named_session]]` in mode
`on_demand` (`NamedSession` in `internal/config/config.go`) runs only once
something asks for it, and `gc session attach` asks the controller to start a
session that is not running, waits for it, then attaches (`gc session attach
--help`). Composed: the postmaster is such a session of the city, as each rig's
po is of its rig, and its opener is that attach.

**The opener verb.** `gc-helm postmaster` is a third seat on gc-helm's seat
verb, beside `po` and `mechanik`, and a row of the People page's seat list,
which the board's form reads from `gc-helm.sh conversations --json`. It grows
gc-helm.sh rather than gctk as an exception the operator granted to AGENTS.md's
rule that new pack code is written in Go, in gctk. Their words, in conversation
tk-218zv3n on 2026-11-21: "Yes, this shoudl go where the current standing
agents sit. it'll get moved over when the other agents move over." The three
seats' commands move into gctk together, with the conversation commands, in
tk-ssm8qns.15. The board's move, tk-1tfzr71.24 (#1617), took takeaway, park,
place and accept into gctk and left the seat commands in shell.

## Listing the mailbox for the postmaster

`gc mail inbox` lists only unread mail, and `gc mail archive` selects read mail
(`--include-read`) only by a sender or a subject (`cmd/gc/cmd_mail.go`). The
mail route with `status=all` lists the open messages, read or unread
(`humaHandleMailList` in `internal/api/huma_handlers_mail.go`, whose `all`
reads `Provider.All`, "all open messages (read and unread)",
`internal/mail/mail.go`, line 178). The postmaster's prompt reads that route,
finding the supervisor with `gc dashboard serve` and the city's name with
`gc status --json`, and reads each message with `gc mail peek`, which leaves it
as it was. The route's answer says when it is not the whole mailbox: `partial`
and `partial_errors` when one of the city's mail stores fails while the others
answer, and `next_cursor` when more messages follow the page (`mailKeysetBody`
in `internal/api/huma_handlers_mail.go`, and `MailListBody` in
`internal/api/huma_types_mail.go`). The prompt prints both with the messages.

## The count on the board

`GET /v0/city/{city}/mail/count?agent=human` (`humaHandleMailCount`) answers
`total` and `unread`, where `total` counts the recipient's open messages, read
or unread, and an archive closes a message (`CountRecipients` in
`internal/mail/beadmail/beadmail.go`). Composed: the city page shows that total,
cached a minute, and lists no message. The list route's `total` with
`status=all` is the same number (130 against 130, and `gc mail count human` the
same, on 2026-11-19), but it returns the messages. The dashboard's badge counts
unread mail less the pool-worker firehose, a different number, and the ruling
asked for every message that waits.
