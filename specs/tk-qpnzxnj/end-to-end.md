---
name: End-to-end run of the mail-notify orders
description: What one run in a throwaway city showed of the mail-notify orders and gctk mail notify, from a send, an API send, a reply, mail to oneself and a sleeping session. Read it when judging whether mail wakes a sitting, or before changing the orders, the verb or the nudge they send.
---

# End-to-end run of the mail-notify orders, 2026-11-23

## The city

A throwaway city, `gc init --template minimal`, run by its own supervisor
under its own `GC_HOME`, so no live session was mailed or nudged. It ran the
installed gc 1.4.3, the city's build 6589a7df45. Its `pack.toml` imported this
branch's tree by path, at b9d0baeba, and gctk was built from the same tree
into `.gc/services/gctk/bin/gctk`, where the orders' exec line finds it. Every
order but the two mail orders was skipped, and the always-on mechanik and
deacon were suspended.

The woken session was a probe agent, `mailprobe`, on Claude Haiku 5.5, whose
prompt told it to list its inbox when told it has mail. Both orders named it
through the override a city uses to change the list:

```toml
[[orders.overrides]]
name = "mail-notify-on-send"
env = { GCTK_MAIL_NOTIFY_AGENTS = "mailprobe" }
```

and the same entry for `mail-notify-on-reply`. The session was opened as a
sitting is, `gc session new mailprobe --alias mp-1 --no-attach`.

## What it showed

| Mail | Event | Order run | The probe |
|---|---|---|---|
| `gc mail send mp-1` with no `--notify`, 02:12:03Z | `mail.sent`, the message in its payload | mail-notify-on-send, 02:12:27Z | "You have mail from human" in its pane 32 s after the send, and its turn read the mail by 38 s |
| `POST /v0/city/mnprobe/mail` from `human`, as the dashboard sends, 02:13:12Z | `mail.sent` | mail-notify-on-send, 02:13:26Z | its turn read the mail 25 s after the send |
| `gc mail reply` with no `--notify`, to a message the probe sent, 02:13:53Z | `mail.replied` | mail-notify-on-reply, 02:13:56Z | its turn read the mail 12 s after the reply |
| mail from the probe to itself, as a handoff is | `mail.sent` | mail-notify-on-send, 02:15:56Z | no nudge, and the ledger held only the three messages from human |
| `gc mail send mp-1` while the probe slept, 02:18:13Z | `mail.sent` | mail-notify-on-send, 02:18:26Z | Gas City queued the nudge with a wake, and the probe was starting 19 s after the mail |

Every run of either order ended with the outcome label `exec`, an exit of 0.
At 02:13:56Z both orders ran at once, since the probe's own message to human
recorded a `mail.sent` as the reply recorded its `mail.replied`. The probe was
nudged once. A pass run by hand afterwards, as the order runs it, printed
`{"read":"2026-11-23T02:16:28Z","woken":[]}` and exited 0 in 0.86 s.

The city first ran Gas City's default nudge dispatcher, `legacy`. After the
sleeping probe woke, its queued nudge was still pending and never attempted
at 02:21:15Z, three minutes after the pass queued it. With
`[daemon] nudge_dispatcher = "supervisor"`, which the live city sets, the
restarted supervisor delivered it and the probe read its mail 12 s after the
supervisor was ready. By Gas City's code a session's
start begins its poller under `legacy` too (`maybeStartNudgePoller` from
`gc prime --hook`, in `cmd/gc/cmd_prime.go` at gastownhall/gascity
c377651cb318), so why that one nudge waited was not traced.
