---
name: End-to-end runs of the mail-notify orders
description: What two runs in throwaway cities showed of the mail-notify orders and gctk mail notify, from a send, an API send, a reply, mail to oneself and a sleeping session, the second on Gas City's default nudge dispatcher throughout. Read it when judging whether mail wakes a sitting, or before changing the orders, the verb or the nudge they send.
---

# End-to-end runs of the mail-notify orders, 2026-11-23

## The first run

### The city

A throwaway city, `gc init --template minimal`, run by its own supervisor
under its own `GC_HOME`, so no live session was mailed or nudged. It ran the
installed gc 1.4.3, the city's build 6589a7df45. Its `pack.toml` imported this
branch's tree by path, at b9d0baeba, and gctk was built from the same tree
into `.gc/services/gctk/bin/gctk`, where the orders' exec line finds it. Every
order but the two mail orders was skipped, and the always-on mechanik and
deacon were suspended.

The woken session was a probe agent, `mailprobe`, on Claude Haiku 5.5, whose
prompt told it to list its inbox when told it has mail. It was a city-scoped
agent with no work directory of its own, so its session ran in the city's
root. Both orders named it through the override a city uses to change the
list:

```toml
[[orders.overrides]]
name = "mail-notify-on-send"
env = { GCTK_MAIL_NOTIFY_AGENTS = "mailprobe" }
```

and the same entry for `mail-notify-on-reply`. The session was opened as a
sitting is, `gc session new mailprobe --alias mp-1 --no-attach`.

### What it showed

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

The city first ran Gas City's default nudge dispatcher, `legacy`. The woken
probe's first turn answered its prompt, but its queued nudge was still pending
and never attempted at 02:21:15Z, three minutes after the pass queued it. With
`[daemon] nudge_dispatcher = "supervisor"`, which the live city sets, the
restarted supervisor delivered it and the probe read its mail 12 s after the
supervisor was ready. The second run found why the nudge waited: the probe
ran in the city's root.

## The second run: a sleeping session on the default dispatcher

### The city

A second throwaway city, set up as the first and run on Gas City's default
nudge dispatcher throughout, with no `nudge_dispatcher` set. It imported this
branch's tree at cd00fa6c3, and its gctk was built from that tree. Three probe
agents on Claude Haiku 5.5 were listed for both orders:

- `probe`, which set only `sleep_after_idle = "1m"`. Its session ran in a
  worktree of its own, `.gc/worktrees/p-1`.
- `mailprobe`, the first run's agent file and prompt word for word, but for a
  one-minute `sleep_after_idle`. Its session ran in the city's root, as the
  first run's did.
- `mailprobe2`, the same file with `work_dir = ".gc/agents/{{.AgentBase}}"`
  added.

Each mail went out with `gc mail send` and no `--notify` while its probe
slept.

### What it showed

| Probe | Mail | The wake | The probe's first turn |
|---|---|---|---|
| `probe`, asleep about two minutes | 04:02:30Z | the pass queued the nudge with a wake, and the probe was starting at 04:02:45Z | its prompt hooks added the mail and the nudge, and it answered with the mail's subject at 04:03:10Z, 40 s after the send |
| `probe`, asleep 2 s | 04:04:39Z | starting at 04:05:04Z | it answered with the subject at 04:05:18Z, 39 s after the send |
| `mailprobe`, in the city's root | 04:12:45Z | starting at 04:13:08Z | it answered its prompt, and the nudge stayed queued with no attempt while the probe slept again at 04:14:49Z, and still at 04:18:15Z |
| `mailprobe2`, in a directory of its own | 04:21:50Z | starting at 04:22:38Z | its prompt hooks added the mail and the nudge, and it answered with the subject at 04:22:55Z, 65 s after the send |

A woken session's prompt starts its first turn, and that turn's prompt hooks,
`gc mail check --inject` and `gc nudge drain --inject`, add the unread mail and
the queued nudge to it. Neither hook reads the nudge dispatcher. After a fresh
start a `gc nudge poll` process ran for the session, and after each wake
looked at none did, so on the default dispatcher those hooks are what deliver
a woken session's queued nudge.

The `mailprobe` session in the city's root recorded no startup hook and no
prompt hook in its transcript, and no poller ran for it, so nothing added the
nudge or the mail to its turn. The first run's nudge waited for the same
reason. The supervisor's dispatcher types a queued nudge into the session's
pane and needs no hook, so switching to it delivered that nudge. Why no hook
ran in the city's root was not traced. A converse sitting runs in its rig
worktree, the `work_dir` its template sets in `agents/converse-*/agent.toml`.
