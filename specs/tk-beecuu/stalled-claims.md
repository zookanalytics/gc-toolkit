---
name: Stalled claims — continuation and detection
description: Why tk-beecuu's continuation fix was placed in the claim response rather than the wake path or the prompt, why that lands in the gascity rig, and how doctor/check-claim-advancing was scoped to detect the failure from the pack side.
---

# Stalled claims — continuation and detection

tk-beecuu asked for two things: a fresh-woken pool session holding an existing
assignment must continue its step rather than end its turn, and a detector for a
claimed step nothing is advancing. It named three candidate sites for the first
and asked for one to be picked with a reason.

## What the wake path actually does

The bead's mechanism section reads as though the woken session never sees the
step. That is not quite the state of the code, and the difference decides where
the fix belongs.

`gc prime --hook` injects the held step bead as a `<system-reminder>` block:
`primeHookContextSuffix` calls `wispStepInjectionContent`, which resolves the
agent's active step and renders it through `formatWispStepReminder`
(gascity `cmd/gc/wisp_step_inject.go`). The codex per-provider overlay stages a
`SessionStart` hook that runs exactly that command, and both failing sessions
had it: `.gc/worktrees/gc-toolkit/polecat-codex/gc-toolkit.hicks/.codex/hooks.json`
and ripley's carry `gc prime --hook --hook-format codex` under `SessionStart`.

The resolution path also reaches the shape that failed. Both sessions held step
one of a `mol-review` molecule whose root is unassigned, so
`resolveActiveWispStep` falls past its molecule tiers to the legacy tier — any
in-progress bead with a description assigned to the agent — which their step
satisfied.

What is not established is delivery. The transcripts quoted in the bead begin at
the claim, so whether the SessionStart block reached the model's context cannot
be read off them. Both readings point the same way:

- If the injection fired, a one-shot block at SessionStart was not enough. It is
  a different event from the action the session takes, and the turn still ended.
- If it did not fire, the wake-time injection is the wrong carrier for a
  guarantee, because it depends on a provider hook having run.

Either way the continuation has to arrive in the reply to the action the session
actually performs.

## The three candidates

**The wake path** (`wake_mode = resume`) changes what the session *remembers*,
not what it is *told*. A resumed pool session also carries the previous bead's
context into the next claim, which is why pools run fresh. city.toml:151-156
records that this exact patch was applied and reverted, and asks for isolated
evidence before it returns; tk-beecuu supplies evidence that the failure is
real, which is not the same as evidence that resume is its remedy. It also does
nothing for a session that legitimately starts fresh after dying mid-step.

**The prompt** is instruction-dependent. It fails silently when competing
guidance wins, and the failure only surfaces a round later. It also cannot
satisfy the bead's own acceptance criterion, which asks for a fixture in which a
fresh-woken session continues the step — there is no fixture for "the model read
the paragraph". The doctrine fragment already says "when the hook returns work,
you run it" and both sessions had it.

**The claim response** is mechanical. The continuation arrives in the same
stdout the session is already reading, on the turn that was ending, on every
provider regardless of which hooks fired. It is also what empirically resolved
the outage: the nudge that unwedged both sessions works by appending
`wispStepInjectionContent` (`cmd/gc/cmd_nudge.go:498`), so the content that
fixes this is already written and already proven — it is reaching the wrong
event.

Picked: the claim response.

## Where that lands, and what ships here

`gc hook --claim` is the gascity binary, not this pack. The fix is filed as
**gc-ycww6** (P1) with the patch site named by symbol
(`hookClaimExistingAssignment` and `writeHookClaimWorkResultForBead` in
`cmd/gc/cmd_hook_claim.go`, reusing `wispStepInjectionContent`), the tier scope,
and its tests. tk-beecuu's first acceptance criterion is satisfied there, not on
this branch.

This branch ships the detector, which is the half that belongs to the pack and
the half that survives the fix: it reports the failure whatever its cause, and
it keeps reporting the three other ways a claim stops advancing.

## The detector

`doctor/check-claim-advancing`, invariant I11. Per store, every `in_progress`
bead carrying `gc.step_ref` and untouched for longer than the stall bound is
joined to the session holding it, matched on session id, session_name or alias.

| Class | Condition |
|---|---|
| UNHELD | no assignee at all |
| ORPHANED | the assignee names no session |
| DEAD | the holder is not running |
| STALLED | the holder runs, but its `last_active` is past the bound too |

UNHELD is read off the bead. The other three are read out of the session
roster, and `_cache_age_s` sits beside `sessions` rather than inside each one,
so it ages the whole roster and not just `last_active`. Against a roster older
than the bound, an absent session may be a holder that started after the
snapshot, and `running: false` may be a state its holder has since left. So all
three degrade from error to warning there, and only UNHELD still reports as an
error. `gc session list` exposes no uncached mode to fall back on.

### Why holder-clocked

`last_active` is the discriminator the bead says does not exist today. It is
derived from tmux pane changes and hardened upstream against self-inflation, so
gc's own nudge keystrokes do not ratchet it (`internal/runtime/tmux/tmux.go`
carries the comments and the guard). A working agent refreshes it; a session
parked at a prompt does not.

Clocking on the holder rather than the bead is what keeps the check quiet in the
case that matters. A polecat can legitimately hold one implementation step for
six hours, and a bead-clocked stall test either cries wolf on that or has to be
set so loose it sleeps through a real outage. `check-step-terminal`'s stall arm
takes the loose end: 48h, holder-blind. The four-hour outage would not have
tripped it.

### Bound

30 minutes, `GC_DOCTOR_CLAIM_STALL_MINUTES`. The longest legitimate single tool
call in this repo freezes a pane for roughly 15 minutes (the pack suite, the
check-set-heal visibility test), so 30 clears real work with margin while
catching a stall eight times faster than the outage was noticed.

Both clocks must be past the bound, never just one. A step claimed seconds ago
by a session that happens to be momentarily quiet is starting, not stalled. The
same gate is what keeps a pool recycle silent: the holder's incarnation changes
under a live claim, and only a claim older than the bound is judged at all.

### Why a separate check, not an arm on check-routed-work-claimable

tk-beecuu asked whether one check should cover both this and tk-7jvj5u. It
should not.

The two ask different questions of different data. tk-7jvj5u is reachability —
whether an **open, unassigned** bead can be offered, answered from `bd ready`
and `bd blocked` membership. I11 is liveness — whether a bead already in a
claimed state has anything advancing it, answered from session activity. A
stalled claim is perfectly reachable; it is held. Folding liveness into I3 would
also make the check's description false in the other direction, and tk-7jvj5u is
open and owns an edit to that same `run.sh`.

### UNHELD

The class was not in the original design. It was added after the first live run:
the check listed 26 in-progress step beads in gc-toolkit and 23 of them carried
no assignee at all, dating to a single 11-second window on 2026-08-24. A step in
that state is reachable by neither path — nothing holds it, and `bd ready` skips
it because its status is not open — and both `check-step-terminal` and
`check-routed-work-claimable` scan `--status open`, so nothing had seen it for
three days.

Clearing an assignee and setting a status are separate writes, so this state
exists briefly during a legitimate release. The claim-age bound covers that
window.

The 23 live strands are filed for repair as **tk-d0j3r7**; this check detects
them and does not fix them.

## Verification

`doctor/check-claim-advancing/run.test.sh` is hermetic, stubs `gc` and `bd`
only, and passes 54 assertions. The `bd` stub applies the same `--status` and
`--has-metadata-key` filters the real tool applies server-side, so a fixture row
the real tool would never return cannot reach the check.

It covers both directions the acceptance asks for: a holder that has worked
within the bound is silent even after holding a step for six hours, and each of
the four classes fires and names the bead, the holder, and how long it has been
quiet. It also covers identity matching on all three keys, the claim-age gate,
the configurable bound including a non-numeric value falling back to the default
rather than to zero, the suspended-rig skip, the stale-cache degrade of each
roster-derived class with UNHELD surviving it, and every probe failing closed to
a warning rather than a pass.

Against the live city the check is silent on both working polecat sessions and
reports the 23 real strands.
