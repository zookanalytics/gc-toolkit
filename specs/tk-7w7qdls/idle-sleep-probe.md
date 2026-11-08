---
name: Probe of v2's idle sleep and stop for a converse sitting
description: Use when you need the evidence that v2's per-agent sleep_after_idle keeps a converse sitting running while it holds its conversation or a client is attached, stops it otherwise, and resumes it with its thread on attach; how a drain-ack's stop and the tab's done mark behave at the sign-off and the dismiss; and why the done mark is a tmux title format and not a typed /rename.
---

# v2's idle sleep and stop for a sitting: the probe

The design of tk-7w7qdls rests on four behaviours of the v2 reconciler's
per-agent idle sleep, which had only been read in code. A converse sitting
must keep running while it holds a claimed conversation, attached or not. It
must keep running while a client is attached. It must stop once it holds
neither. And attaching to a stopped one must resume its thread. This records
what ran on 2026-11-08 and what each result decided. It also records how the
two endings, the sign-off and the dismiss, stop a session under an attached
tab, and what the tab's title reads after each.

## Setup

All of it ran in a scratch city with its own supervisor, tmux server and
`GC_HOME`, on the macOS host: `gc` 1.4.3 at fork `cb80c5354`, whose merge-base
with upstream is `9f807760c`, the build the live city runs. Claude Code was
2.1.319 and tmux 3.8. The city set `session_reconciler = "v2"`, and its
supervisor log read `session reconciler: v2`. Every order was skipped.

A city that `gc init` makes has a proxied-server store, which v2 refuses to
boot on, so its infrastructure classes ran on `sqlite-beads`, moved there with
`gc storage migrate --from-work --fleet-stopped`. The live city runs on native
Dolt.

Two templates stood in for the converse ones. Each ran Claude on Haiku through
`claude-pick`, with `attach = true`, `wake_mode = "resume"`,
`idle_timeout = "0"`, `nudge = ""`, and the converse templates'
`session_live` entries, which set `detach-on-destroy` and
`set-titles on` with `set-titles-string "#T"`. The idle-sleep checks used
`sleep_after_idle = "1m"`, so a check fits in minutes. The ending checks used
`sleep_after_idle = "10m"`, the value this change ships. Every session was a
manual one, from `gc session new <template> --alias <alias> --no-attach`.

A tab was a real tmux client running `gc session attach <id>` inside a pane of
a second tmux server. That pane's own title is what the client's terminal is
sent, so `#{pane_title}` on the second server is the title a tab shows.

## The idle sleep

| Check | What ran | Result |
|---|---|---|
| Claimed work holds a sitting running, attached or not | Session A held an `in_progress` bead assigned to its alias. A client attached to it for a minute, then detached at 20:52:53Z. | Running throughout, attached and then detached for more than twelve minutes, past the ten-minute grace and the one-minute policy. |
| With nothing claimed and no client, it sleeps | Session B held nothing and was never attached. | Asleep with sleep reason `idle` at 20:52:43Z, about two minutes after it started and 101 seconds after its idle clock began. It stayed asleep, with no wake, until a client attached. |
| A client holds it running | A client attached to B for six minutes, six times its policy, while B held nothing. | Running throughout. |
| Attaching to a slept sitting resumes its thread | Before B slept, it was told the code word MARIGOLD-7. A client then attached to it while it slept. | B woke under the client with `claude … --resume 251e8afe-…`, the session key it slept with. Gas City handed it its prompt again, as a new message, and asked for the word it answered MARIGOLD-7. |
| Closing a sitting's conversation by hand lets it sleep | A's bead was closed while A was detached. | Asleep with sleep reason `idle` 11 seconds after the controller read the close. |

Three findings came with them:

- **No manual grace under a sleep policy.** B slept two minutes after it
  started, where the reading in code expected the ten-minute grace for a
  manual session first. The awake set's own idle sleep does spare a manual
  session younger than the grace (`inManualGracePeriod`). The v2 allocator's
  sleep-policy pass (`configSleepSuppressed` in `cmd/gc/allocator_decide.go`)
  runs after it and has no such rung: it sleeps a session once the policy's
  time has passed since the later of its last detach and its last terminal
  output, unless an attached client, assigned work or an explicit wake
  overrides it (`wakeDemandOverridesSleepSuppression`).
- **A detach can sleep a quiet session at once.** B slept 17 seconds after its
  client detached. Its last output had been six minutes earlier, and the pass
  after a detach reads the last output, because `detached_at` is not stamped
  until that pass.
- **A slept session stays asleep only while its policy is unchanged.**
  Changing the template's value from one minute to two woke both slept
  sessions within 10 seconds, and both slept again two minutes later
  (`configWakeSuppressedAt` holds a slept session asleep only while its
  recorded `sleep_policy_fingerprint` matches).

One method note: the probe first closed A's bead with `bd` directly, which the
controller's cache did not see for four minutes. The close through the city's
API took at once. In the live city every pack write goes through `gc bd`.

## The two endings

Sessions C and D ran the ten-minute template, each with a tab attached. Each
was titled with a typed `/rename`, as `gctk session title` has Gas City do, so
before the ending their tabs read `✳ tk-probe #1 — sign-off probe` and
`✳ tk-probe #2 — dismiss probe`.

| Ending | What ran | Tab title after it | Stop |
|---|---|---|---|
| Sign-off | C's own agent ran the drain block this change gives the prompt, from its Bash tool: `[ -z "${TMUX_PANE:-}" ] \|\| tmux set-option -t "$TMUX_PANE" set-titles-string 'done · #T'; gc runtime drain-ack` | `done · ✳ tk-probe #1 — sign-off probe` at once | Held while the tab stayed attached, 76 seconds, the session up and `draining`. Stopped 73 seconds after the tab detached. |
| Dismiss | From a shell outside every tmux server, as the board runs it: the server named the way `gc-helm dismiss` names it (`[session] socket` from `gc config show --json`, empty, so `city_name` from `gc status --json`), then `tmux -L pp7w set-option -t "=s-gcg-3073:" set-titles-string 'done · #T'` and `gc runtime drain-ack --operator gcg-3073` | `done · ✳ tk-probe #2 — dismiss probe` at once | Held while the tab stayed attached, 55 seconds. Stopped 18 seconds after the tab detached. |

After each stop the record's state read `drained`, which `gc session list`
shows as `asleep`, and the stop event read "drain acknowledged by agent", as
the idle sleeps' did. `gc session prune --state drained --before 1s` then
closed C and D and left A and B, the idle-slept ones, asleep: the core
reaper's daily prune is that command with `--before 24h`.

## Why the done mark is not a typed /rename

`gctk session title` titles a session through `gc session submit --intent
follow_up "/rename <title>"`. Session E, titled and with a tab attached, tried
it both ways after a drain-ack:

- Sent from outside while E was idle, the submit answered `submitted` and typed
  at once, and the tab's title changed.
- Run by E's own agent in one tool call with its drain-ack, as a sign-off would
  run it, the submit answered `queued`, for the session's next boundary. Two
  minutes later, with the stop held under the tab, the title had not changed.

So a `/rename` cannot mark the tab at the sign-off, and at a dismiss it marks
it only when the agent is idle. A dismiss of a sitting that is not running
would also wake it, because a submit to such a session resumes it. The tmux
title format reaches the client at once in every case above.

## What it decided

- **The design stands.** Claimed work and an attached client each hold a
  sitting running, a sitting with neither sleeps, and attaching resumes its
  thread. The grace the reading expected is not there, and nothing rests on
  it: engage binds a sitting's conversation as it starts it, so the only
  sitting the idle sleep reaches is one that holds nothing.
- **The sign-off and the dismiss keep their drain-ack.** v2 holds its stop
  while a tab is attached and lets it go within minutes of the detach, and the
  drained record is the one the core reaper's prune closes. An idle-slept
  record is never pruned, so it stays asleep, holding no process, until
  something closes it.
- **The tab is marked done by the session's `set-titles-string`.** The agent's
  drain block sets it on its own pane's session, and `gc-helm dismiss` sets it
  on the holder's session on the server Gas City names.

## Reproducing it

Write a `supervisor.toml` with its own port and a `cities.toml` under a scratch
`GC_HOME` with a short path, and run every gc call under `env -i` with `HOME`,
`PATH`, `TERM`, `TMPDIR` and `GC_HOME` set, so this session's identity cannot
reach the live city. Run `gc init --template minimal --no-start`, drop its
mayor, skip every order, set the reconciler and the store as above, and run
`gc supervisor run`. Read session state with `gc session list --state all
--json`, and the session metadata from the sqlite store's `metadata` table.
Attach with `gc session attach` inside a second tmux server, type with
`send-keys -t "=<session>:"`, and read the tab's title as that server's
`#{pane_title}`. Write a bead the controller must see through `gc bd` or the
city API.
