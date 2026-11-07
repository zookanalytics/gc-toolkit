---
name: Probe of how a converse sitting's session ends under the v2 reconciler
description: Use when you need the evidence for why a sitting ends its own session with `gc session close "$GC_SESSION_ID"` rather than `gc runtime drain-ack`, why the pack does not detach that close from the agent, or where a close run inside its own pane fails.
---

# How a sitting's session ends under v2: the probe

The question was which Gas City primitive ends a converse sitting's session
under the v2 reconciler when the operator's tab is attached to it, and whether
an agent can run that primitive against its own session. This records what ran
on 2026-11-07 and what each result decided. The reading of Gas City's code that
led here is in the notes of bead tk-bhrmihv.

## Setup

All of it ran in a scratch city with its own supervisor and tmux server, on the
macOS host at load 15 to 25: `gc` 1.4.3 at fork main `cb80c5354`, whose
merge-base with upstream is `9f807760c`, Claude Code 2.1.319, Codex CLI 0.164.0
and tmux 3.8. The city set `session_reconciler = "v2"`.

Each session used the sittings' `session_live`, `idle_timeout = "0"` and an empty
`nudge`. Claude ran on Haiku and Codex on the live model. A tab was a real tmux
client running `gc session attach` inside a second tmux server's pane.

The city differs from the live one in its store. A city `gc init` makes has a
proxied-server store, which v2 refuses to boot on, so the infrastructure classes
ran on `sqlite-beads`, moved there with
`gc storage migrate --from-work --fleet-stopped`. The live city runs on native
Dolt. gc refuses `gc bd` on such a split city with this host's patched bd, so the
runs of the pack's own scripts reached the rig's store through a shim that sent
`gc bd` alone to bd. Every session call was the real gc.

## What ran

"Closed" below means all of these: the tmux session is gone, the session record
reads closed, the tab's client exited 0, and neither had changed 30 to 60 seconds
later.

| What ended it | Tab | Runs | Result |
|---|---|---|---|
| `gc runtime drain-ack`, at a shell | attached | 1 | Held. The record read `draining` and the session was still up at 56 s. Once the client detached, the stop went through at about 32 s, and the record read `asleep`. |
| `gc runtime drain-ack`, at a shell | none | 1 | Stopped at about 19 s. The record still read `asleep` 58 s later, so the session was not closed and its alias stayed held. |
| `gc session close "$GC_SESSION_ID"`, from Claude Code's Bash tool | attached | 12 | Closed, all 12. |
| The same | none | 1 | The tmux session gone and the record closed. |
| The same, from Codex's shell tool | attached | 4 | Closed, all 4. |
| The same, as a `!` line typed into Claude Code | attached | 1 | Closed within 3 s. |
| The same, as a `!` line typed into Codex | attached | 1 | Closed within 3 s. |
| The branch's `gc-helm.sh dismiss --json`, typed at a shell in a rig-scoped pane the real `gc-helm.sh engage` opened | attached | 1 | Closed in about 5 s. The conversation closed and the JSON printed first. The verb ended with 143, as the close signalled it. |
| The branch's `tmux-dismiss-sitting.sh`, as a `run-shell -b` job, on the same kind of pane | attached | 1 | Closed in about 2 s, and the conversation closed. |
| `gc session close "$GC_SESSION_ID"`, typed at an interactive shell that leads the pane, in a rig-scoped pane and a city-scoped one | attached | 2 | Failed, both. See below. |
| `nohup gc session close "$GC_SESSION_ID"`, at the same kind of shell | attached | 1 | Closed by about 10 s. |
| `gc session close <id>` from outside, on the two failed sessions | none | 2 | Cleared both: the tmux session gone and the record closed. |

A template with `max_session_age = "1m"` was still on its first tmux session at
667 s, so v2 runs no max-age restart. `shouldRestart`'s one caller is in the
legacy reconciler's tick, which returns at once under v2.

## Why the agents' closes hold and the shell's does not

A command either agent runs is the leader of a process session of its own, with
no controlling terminal. `ps` read the same in all six samples, from Claude Code's
Bash tool twice, Codex's shell tool twice and a `!` line in each: `TTY` `??`,
`STAT` `SNs`, and `PGID` equal to `PID`. Gas City's close leaves its own process
out of what it signals, so nothing Gas City sends reaches it, and no terminal
hangup can.

A close typed at an interactive shell is that shell's foreground child. Gas City
signals the shell, which ignores SIGTERM and takes the SIGKILL two seconds later.
The kernel then sends SIGHUP to the terminal's foreground process group, which
holds the close, and the close exits before it kills the tmux session or commits
the record. tmux shows `Pane is dead (signal kill)` under the attached client, and
the record stays open. The `nohup` run closes cleanly, which pins the hangup as
the cause. A sitting's pane holds the agent, not a shell, so no sitting takes this
path.

## What it decided

- **A sitting and `gc-helm dismiss` end a session with `gc session close`.** A
  drain-ack's stop waits while a client is attached, which leaves the live pane
  the operator declined under the tab, and it leaves the record open.
- **The pack does not detach the close from the agent.** The branch's first draft
  added a verb, `gctk session close`, which started the close of the caller's own
  session with `setsid`. It rested on a probe that sent SIGTERM to `claude -p`
  alone and saw its running command die within two seconds. That is not what Gas
  City does: it signals the pane's whole process tree, deepest first, and the
  agents already give a command what `setsid` would. The verb passed the same
  kinds of run (5 from Claude Code, 1 from Codex, 3 at a shell) and bought nothing
  on an agent's path, so it was dropped for the primitive.
- **`gc-helm dismiss --operator` is gone.** It chose an operator's ack over a
  self-ack, and `gc session close` has no such rule, so all it had left to change
  was one diagnostic.
- **A close that dies anyway is bounded.** Should a later agent version kill the
  close, the worst seen is a dead pane under the tab and an open record, and the
  outside close `converse-reap` runs clears that within two passes of its
  five-minute order.

## Follow-ups

The failure at an interactive shell is Gas City's, and no sitting reaches it. It
is filed in the gascity rig as gc-fj5drr.

## Reproducing it

Write a `supervisor.toml` with its own port and a `cities.toml` under a scratch
`GC_HOME` with a short path, and run every gc call under `env -i` with `HOME`,
`PATH`, `TERM`, `TMPDIR` and `GC_HOME` set, so this session's identity cannot
reach the live city. Run `gc init --template minimal --no-start`, drop its mayor,
set the reconciler and the store as above, and run `gc supervisor run`. A plain
shell session comes from a provider with `command = "/bin/sh"` and
`prompt_mode = "none"`. Attach with `gc session attach` inside a second tmux
server, type with `send-keys -t "=<session>:"`, and read `gc session list --state
all --json`, `has-session` and the client's exit status.
