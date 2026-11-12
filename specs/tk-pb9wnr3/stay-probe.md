---
name: Probe of a converse sitting that stays asleep until its work returns
description: Use when you need the evidence that a converse sitting can stay for the return of the work it sent, sleeping with its conversation open and woken with its thread when that work closes; how the two native paths (a session wait with a sleep hold, and an open conversation that waits on the work through a blocks edge) behaved under an attached tab, an early attach, a lapsed claim lease, the work's close and a dismiss; and why the pack composes the edge.
---

# A sitting that stays until its work returns: the probe

The operator ruled that a converse sitting ends at its hand-off unless they ask
it to stay, and that one which stays keeps its conversation open while its
agent sleeps and is woken, with that conversation, when the work it sent
closes. Two Gas City paths could carry the sleep and the wake, and neither had
been run on a sitting. This records what ran on 2026-11-12 and what each result
decided.

## Setup

A scratch city with its own supervisor, `GC_HOME`, port and tmux server, on the
macOS host: `gc` 1.4.3 at fork `36ad5186a2`, the build the live city runs, whose
session-wait, awake-set and wake code matches upstream `6bd609f5bf`. Claude Code
was 2.1.322 and tmux 3.8. The city set `session_reconciler = "v2"`, and its
supervisor log read `session reconciler: v2`. A city that `gc init` makes has a
proxied store, which v2 refuses, so the infrastructure classes ran on
`sqlite-beads`, moved there with `gc storage migrate --from-work --fleet-stopped`.
Every order was skipped but `cascade-nudge-on-blocker-close`, which the live city
runs and which nudges a dependent's assignee when its blocker closes.

One template stood in for the converse ones: Claude on Haiku through
`claude-pick`, `wake_mode = "resume"`, `attach = true`, `idle_timeout = "0"`,
`nudge = ""`, the converse templates' `session_live` entries, and
`sleep_after_idle = "1m"`, so a check fits in minutes. Its prompt had the
session run `gc hook --claim --json` on every delivery and report the result, as
a sitting's step 1 does. Two manual sessions ran it, each created as engage
creates a sitting, with `gc session new <template> --alias <conversation>
--no-attach`, and each conversation was a task assigned to that alias. Writes
the controller must see went through the city's API.

- **Sitting A, the wait path.** Session `gcg-1`, conversation `pb9-m96`, work
  `pb9-522`. It stayed by `gc session wait gcg-1 --on-beads pb9-522 --note
  "<text>" --sleep`, with its conversation still claimed.
- **Sitting B, the edge path.** Session `gcg-1025`, conversation `pb9-hfv`, work
  `pb9-hhl`. It stayed by a `blocks` edge from the conversation onto the work,
  then a write that put the conversation back to `open` under the alias.

A tab was a real tmux client running `gc session attach <id>` inside a pane of a
second tmux server, so `#{pane_title}` there is the title a tab shows.

## Results

Each sitting first claimed its conversation, at 06:45:48Z, and the claim read
`ready_assignment` for both: a fresh sitting's first claim. Each was told a code
word (HERON-41 for A, QUINCE-83 for B), and a tab attached to each at 06:47:01Z.

| Check | Sitting A (wait) | Sitting B (edge) |
|---|---|---|
| The stay, written at 06:47:13Z with the tab attached | `Registered wait gcg-2049 … draining to sleep`. The session read `draining`, with `wait_hold=true` and `sleep_intent=wait-hold`. | `bd ready` listed the work and not the conversation. The session read `active`. |
| What the tab showed while it stayed attached, 4 min 24 s | The live sitting. The process and the tmux session stayed up, the client stayed attached, the title did not change, and no `GC_DRAIN_ACK` was set. | The live sitting, awake past its one-minute policy. |
| The stop, once the tab detached at 06:51:51Z | Asleep at 06:52:58Z, 67 s later. | Asleep at 06:53:33Z, 102 s later. |
| The record while asleep | `asleep`, sleep reason `idle`, `wait_hold=true`, the same `session_key` | `asleep`, sleep reason `idle`, the same `session_key` |
| The claim's lease | Expired at 06:50:50Z, five minutes after the claim. The conversation still read `in_progress` under the alias at every later read: nothing reclaimed it. | None: the open conversation carried no lease fields. |
| An attach while asleep, at 06:54:00Z | Woke on its session key, its thread intact, and the prompt arrived again. The claim read `existing_assignment`. The wait read `canceled`, and `wait_hold` and `sleep_intent` were cleared. | Woke on its session key, its thread intact, and the prompt arrived again. The claim read `action: drain`, reason `no_work`. |
| After that tab detached, at 06:55:40Z | Still running at 06:58:49Z: its wait was gone, and the claimed conversation keeps it awake. Asleep at 06:59:35Z, 38 s after the wait was registered again. | Asleep again on its own at 06:58:40Z, 3 min after the detach. |
| The work's close, through the API at 06:59:44Z | Awake at 06:59:51Z on the same `session_key`. The prompt it was sent again arrived cut short, as only the tail of the skills list, so the session did not run its claim. The reminder `Wait satisfied (gcg-4097): <note>` arrived as a deferred system reminder at the end of that turn. | Awake at 06:59:56Z on the same `session_key`. The prompt arrived whole, and the claim read `ready_assignment` for the conversation, claimed again with a fresh lease. |
| The thread, asked for the code word at 07:03Z | HERON-41 | QUINCE-83 |

The blocker-close nudge ran 78 s after the work closed and nudged nothing,
because it nudges open dependents and B had already claimed its conversation. A
woken sitting cannot count on it.

A third check ran on B. At 07:11:56Z it stayed again on new work, and it slept
at 07:12:28Z. Then the two acts of `gc-helm dismiss` ran from outside: the
conversation closed through the API, and `gc runtime drain-ack --operator
gcg-1025` answered `Drain acknowledged`. The record stayed `asleep` with sleep
reason `idle`, its `drain_ack_at` stamped and cleared within four seconds, and
the session did not wake.

## What the pack's readers make of it

Read in the pack at `3a6bf50f5` for an open conversation assigned to an alias
whose session is asleep, the edge path's state, and for one in progress under
such an alias, the wait path's:

- **The board.** `/helm` reads a conversation as in session while any listed
  session carries its alias, asleep included, so neither state is owed there.
  The per-rig board counted every open conversation that answers no open gate
  as an ask on Needs you. This change makes one that a wait of its own holds no
  ask: it reads "Waits on" its work, in the Queued group.
- **`gc-helm engage`.** It treats an asleep sitting as live and attaches to it
  rather than starting a second. It waited for the session list to read
  `active` first, which an asleep sitting never reads, so it would have waited
  fifteen minutes and exited 4. This change attaches an asleep sitting at once,
  since the attach wakes it with its thread and its prompt, as the table shows.
  Once the tab detaches, engage reads the conversation and prints that the
  sitting is still open, with the attach that takes it up again.
- **The sweeps.** No sweep, order or doctor check closes either state. The
  liveness sweep classifies only unassigned ready beads, the witness and
  `orphan-dispose.sh` skip conversations, and Gas City's core reaper prunes only
  `drained` sessions, never an idle-slept one.
- **The claim.** On the edge path, the claim answers `drain` while the work is
  out and `ready_assignment` once it lands, which is what a fresh sitting reads
  too. So the converse prompt's step 1 reads the conversation's `staying:` line
  for both.

## What it decided

- **The pack composes the edge.** Both paths slept the sitting with its
  conversation open and woke it with its thread when the work closed. The edge
  path is the one that holds without the sitting's help: an early attach
  cancels a session wait, and the sitting then never sleeps again until it
  registers the wait anew, while the edge survives every attach and the sitting
  sleeps again on its own. The edge is also a graph state that the board and
  `doctor/check-wait-is-an-edge` already read. Its one limit is the store: an
  edge onto a bead in another rig's store holds nothing, so a sitting stays only
  for work in its conversation's own store.
- **No tab loses its pane at the stay.** Neither path stopped a session under
  an attached tab. The design that set the session wait aside for the hold
  (`specs/tk-0ur8r9p/design.md`) read the wait as draining the session under an
  attached pane. The v2 reconciler held that stop until the tab detached.
- **A lapsed lease costs nothing.** bd's claim lease lasts five minutes
  (`DefaultLeaseTTL` in bd's `internal/storage/issueops/lease.go`), and only
  `bd reclaim` acts on one that lapsed, which nothing in this city runs.
  The edge path drops the claim at the stay in any case.
- **The record is the return's fallback.** A resume keeps the thread, but a
  session that is closed, or a transcript past its retention, does not. So the
  stay writes everything a sign-off writes, and the `staying:` line names what
  the return compares, so that a new sitting can take up the return from the
  record.

## Reproducing it

Start from the scratch-city recipe in
[`specs/tk-7w7qdls/idle-sleep-probe.md`](../tk-7w7qdls/idle-sleep-probe.md#reproducing-it).
Skip every order but the one under test, set the reconciler and the store as
above, and run `gc supervisor run` under its own `GC_HOME`. Create each
conversation through `POST /v0/city/<n>/beads`, start its session with `gc
session new <template> --alias <conversation> --no-attach`, then assign the
conversation to the alias through `POST /v0/city/<n>/bead/<id>/update`, which
refuses an alias no open session holds. Write the edge with `bd dep add
<conversation> <work> --type blocks` against the work store, and put the
conversation back to `open` and close the work through the API, which the
controller sees at once. Read the session's state, sleep reason, wait hold and
session key from the `metadata` table of `<city>/.gc/store/graph/beads.sqlite`,
and a wait's state with `gc wait inspect <id> --json`.
