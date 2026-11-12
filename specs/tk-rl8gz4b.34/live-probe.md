---
name: Live probe of the po's seat
description: Use when checking what the po's seat does when it runs (an attach, a detach, a drain, mail, a nudge, the idle limit, a sling), or why its prime is kept under 10,000 characters and how a sitting recovers a missing prime.
---

# Live probe of the po's seat

Unit 3 of the native-hold effort (tk-rl8gz4b.34) seats the po. Its done-when asks
for a live probe, run where this branch's pack is loaded, and a record of any
result that differs. This is that record.

## Where it ran

A scratch city, `poprobe`, made with `gc init --template minimal --no-start` and
run by its own supervisor (`gc supervisor run` with its own `GC_HOME` and API
port), so its sessions sat on their own tmux server and its beads in their own
store. Its `pack.toml` imported this branch's worktree as `gc-toolkit` at city
level, and its `city.toml` copied the live city's claude provider, its
`[agent_defaults] default_sling_formula = "mol-polecat-work"` and
`formula_v2 = true`. Mechanik, the deacon and the dog were suspended, and every
pack order but `pin-keepalive` was skipped, along with core's dolt and dog orders.
The installed gc was 1.4.3 (`e03752646`), and Claude Code was 2.1.319. It ran on
2026-11-06 from 06:35Z to 07:03Z, and the operator's attach was
`gc session attach gc-toolkit.po` from a separate tmux client.

## Results

| Done-when | Result |
|---|---|
| An attach materializes the seat and starts a new conversation with no memory index | Holds. The attach created the session (`po-wisp-jb5`) and started Claude in `.gc/agents/po` with a new session key. Its process carried `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`, its project directory held no `memory/`, and asked, it reported no memory section. Its prime did not arrive whole: see below. |
| A detach leaves it up | Holds. Detached past a controller tick, it stayed active with the same key. |
| `gc runtime drain-ack` ends it | Holds. Told the sitting was done, it ran `gc runtime drain-ack`, its state went to `drained`, and its conversation key was replaced. |
| The idle limit ends it | Holds, with the limit patched to 2 minutes in the scratch city: detached at 06:58:30Z, drained at 07:01:23Z, its key cleared. |
| The next attach starts another conversation | Holds: each attach started a new conversation, which remembered nothing. Its prime was missing: see below. |
| Plain mail wakes nothing | Holds. It stayed asleep after plain mail, past a controller tick, and the message stayed unread. |
| A nudge wakes it for one turn | Holds. The nudge woke it at 06:52:25Z. It read `attached` as `false` and ran `gc runtime drain-ack`, and it was draining by 06:52:59Z. It did not first say whose request it was. |
| `gc sling` without `--on` exits non-zero | Holds: exit 1, and the error carries the refusal, which says to send the bead to a work pool or hold it for the po. |
| With `--on` the run pours | Holds. `--on mol-polecat-work` poured run `po-gwt`. Its root and the steps load-context, workspace-setup, preflight-tests, implement, `self-review.iteration.1` and submit-and-exit carry `gc.routed_to=gc-toolkit.po`, and the self-review and workflow-finalize control steps go to `core.control-dispatcher`. The work bead took `gc.execution_routed_to=gc-toolkit.po`. The routed steps woke the po, which took none of them and drained. Cancelling the run closed its 10 members as `canceled`. Whether routed steps left in place wake it again after each drain was not observed. |

## The results that differ

**A prime over 10,000 characters arrives as a 2 KB preview.** A session an attach
starts takes its prime as session-start hook context, not as its first message.
Claude Code 2.1.319 saves hook context over 10,000 characters to a file and gives
the session a 2 KB preview (`oFe=1e4`, the default threshold of its hook-output
persist, read in the 2.1.319 binary). The po's first prime was 22.7 KB, and the po
said its prompt was cut to a preview. A session the controller starts takes its
prime as its first message instead, which has no such cap: the deacon's 23K and a
converse sitting's 42K arrive whole. So the po's prime is kept under the cap: its
prompt composes only the `ask-for-work` and `operator-profile` fragments, and
renders at 6,780 characters. `assets/scripts/po-prime-cap.test.sh` fails a render
past 9,800 characters, so a profile promotion that grows the prime fails at its
own PR.

**A re-attach after a drain starts the po with no prime at all.** A second and a
third attach each started a conversation whose context held no po prompt. The
session-start hook ran and `gc prime --hook` printed nothing, so Claude Code kept
no record of it. `primeHookLiveManagedSession` (`cmd/gc/cmd_prime.go`, the same at
Gas City main `005135c33`) primes only a session whose stored state is active,
awake, creating or start_pending, and an attach starts a drained session's runtime
while its bead still reads `drained`. The first attach worked because a new bead
reads `creating`, and a controller start, such as a nudge's, delivers the prime as
the first message. Telling a re-attached po to run `gc prime` gives it the whole
prompt. tk-nu6eztz tracks the fix.

**pin-keepalive would have pinned the po awake.** Its order pins every configured
named session on the interactive provider, and a pin holds off the idle drain that
ends a sitting. The script now leaves a named session whose mode is not `always`
alone. The probe's run of that order never fired, so its suite carries the proof.
