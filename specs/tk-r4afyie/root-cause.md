---
name: Deacon idles after a patrol cycle — root cause and fix
description: Why the deacon stopped patrolling between cycles from 2026-10-12. Nothing gave an ended turn another turn, and the restart that had followed every cycle was Gas City's reassignment restart, which its own guards held off. Covers the evidence for each link, the leads the bead named and what each showed, and why the fix is a Stop hook that hands the next cycle back plus a city-store pin on the deacon's wisp commands. Read when revisiting how the deacon's patrol continues.
---

# Deacon idles after a patrol cycle

## Symptom

From 2026-10-12 the deacon ran one or two patrol cycles per session, wrote a
summary, ended its turn and sat idle for hours or days. Sessions per day fell
from 60-140 to 0-5, apart from 49 on 2026-10-24. Session `d78acd75` ended its
last turn at 2026-10-24T20:05Z and did nothing for about 47 hours.

## What gives the deacon its next cycle

**Each session gets at most two prompts.** Every deacon transcript since
2026-10-12 opens with the startup prompt (`[<city>] gc-toolkit.deacon • …`
plus the role prompt). Most then receive the agent's configured nudge ("Run gc
prime, then the startup wisp reconcile; patrol the city.") within 50ms of the
first turn ending. After that, the only prompts are the completion
notifications of the session's own background commands, plus one deferred
reminder that reached session `72eaee3d` thirteen hours on. So a session that
completes its turns runs one or two cycles and idles. The listing comes from
reading each transcript's string user messages and its `turn_duration`
records.

**The model ends its turn after a cycle.** The prompt says "Do NOT enter a
standing by idle state between cycles; after next-iteration, run `gc hook`",
and the formula ends with "run `gc hook` and start the next cycle". The
deacon's turns still end on a cycle summary, in every session read.

**The per-cycle restart was Gas City's reassignment restart.** Gas City
restarts an alive `wake_mode = "fresh"` session whose assigned work bead
differs from the bead it last recorded (`cycleAliveSessionForFreshReassign`,
`cmd/gc/session_bead_cycle.go`, decided in `cmd/gc/session_reconciler.go`).
The deacon's next-iteration assigns the freshly poured wisp to itself, which
is such a change. Between 2026-10-24T03:25Z and 19:38Z the event log holds 52
`worker.operation kill`s of the deacon, each followed by `start_resolved`.
Each one's write moved the session bead's `currently_processing_bead_id` to a
new wisp and set `continuation_reset_pending`. The kills read in detail came
about 70 seconds after the session's pour. On 2026-10-26 the same restart
fired 28 seconds after session `ff6adfd9` ended its turn with the next wisp open
(kill at 21:00:22Z).

**That restart serves a reassignment, and its guards hold it off.** At the
installed build `e03752646` (the same code as upstream main `1036b2cb2`) the
restart is skipped when:

- the session holds any in-progress claim (`sessionHasFreshInProgressClaim`,
  upstream since 2026-10-17);
- the bead it last recorded is still open and assigned to it;
- that bead closed before the session's current incarnation woke;
- it already claimed the new bead itself, or the new bead is already closed.

From 2026-10-01 until 2026-10-12T22:48Z, 715 of 935 deacon sessions ended
inside a tool call, killed mid-turn. On 2026-10-12 that was during or just
after the pour, with 30 to 190 seconds before the next session. From session
`324fdd6e` (born 2026-10-12T22:48Z) on, sessions complete their prompted turns
and idle.

## The stalls

**2026-10-12T22:48Z to 2026-10-24T03:25Z.** Sessions ran their prompted turns
and idled, mostly for hours, before something else restarted them. From the
earliest session-bead event the archive holds (2026-10-21T03:58Z) until
2026-10-24T03:25Z, the deacon's `currently_processing_bead_id` never moved,
which every reassignment restart does. It named `tk-wisp-1jp`, an open
`mol-deacon-patrol` wisp in the gc-toolkit rig store, assigned to
`gc-toolkit.deacon`. Polecat reads on 2026-10-15 and 2026-10-20 list it
there. A reconcile run from the deacon's own directory reads the city store
and never saw it. At 2026-10-24T05:16Z the deacon wrote, of its own startup: "I
first ran the reconcile from `rigs/gc-toolkit`, so it ran against the rig
store. It claimed a stale patrol wisp from 10-12, `tk-wisp-1jp`." Its first
command had been `cd "${GC_RIG_ROOT:-…/rigs/gc-toolkit}"`, and its shell kept
that directory. The restart resumed at 03:25Z, when the pointer moved to a
city-store wisp, before `tk-wisp-1jp` was burned at 05:03Z. The data do not show
which guard held each restart off in this period. Events start on
2026-10-19 and the supervisor log on 2026-10-16. Neither the installed gc
build of 2026-10-12 nor the moment the pointer was first set can be recovered.

**2026-10-24T03:25Z to 19:38Z.** One fresh session per cycle, 52 restarts.

**2026-10-24T19:38Z, session `d78acd75`.** It adopted the wisp the restart
recorded and ran a cycle. Then it claimed the next wisp itself
(`gc bd update <wisp> --status=in_progress`) about two minutes after
the pour, before any restart, and ran a second cycle in the same
conversation. At 20:04Z it poured the next wisp with
`gc bd update "$NEXT" --assignee="$GC_AGENT" --status=in_progress`, a change
to the formula's assign. The wisp was in progress from its first event. The
in-progress-claim guard retained the session, its turn ended at 20:05Z, and
nothing typed into it until the reset on 2026-10-26.

## The leads the bead named

- **The prompt's `gc hook` instruction.** The model ends its turn anyway (above).
- **Sleep policy (`effective_sleep_after_idle=off`, `legacy_off`).** All 997
  session-bead events the archive holds read `off`, `legacy_off` and wake
  mode `fresh`. The restarts that kept the patrol going were reassignment
  kills, not idle sleeps. This is not the cause.
- **`idle_timeout = "2h"`.** `buildIdleTracker` (`cmd/gc/cmd_start.go`)
  registers no timeout for a named session in mode `always` ("mode="always"
  must never be subject" to it), at `e03752646` and on upstream main. It
  never applies to the deacon.
- **The respawn circuit breaker.** `session_circuit_state` is empty in all 997
  events, so it never tripped. The reassignment restart resets it on each kill.
- **"No town or gc-toolkit commit around 2026-10-12 touches the deacon."**
  This holds for `agents/deacon/`, `formulas/mol-deacon-patrol.toml` and
  `overlays/cycle-recycle/`. The town's 2026-10-12 commits touch deferred
  dispatch, intake and test policy.

The cause is in gc-toolkit. The deacon's patrol had no way of its own to
continue after a turn ended, and it ran on a Gas City restart built for
reassignment, whose guards are correct for that purpose. Nothing is filed
against the gascity rig.

## The fix

**A Stop hook hands the next cycle back** (`overlays/cycle-recycle/.claude/hooks/patrol-continue.sh`,
policy in `docs/patrol-continue.md`). The bead asks for a patrol that does
not depend on a controller restart after each cycle. Upstream Gas Town's
deacon ends its turn and relies on a `session_sleep` policy to restart it.
That is still a restart after each cycle, so the continuation is taken at
the turn boundary instead. Claude Code behavior the hook rests on, verified
with Claude Code 2.1.310 in scratch sessions run with `claude -p`:

- A Stop hook that prints `{"decision":"block","reason":"…"}` keeps the turn
  going. The model receives the reason as "Stop hook feedback", and the
  transcript records it as an `isMeta` user message.
- The payload carries `session_id`, `stop_hook_active` (true on a stop that
  follows a block) and `background_tasks`. A turn that ends with a running
  background task lists it with `status: "running"`, and Claude Code resumes
  the session with its completion notification.
- Claude Code overrides a hook that blocks the turn from ending nine times in
  a row and ends the turn ("A hook blocked the turn from ending 9 consecutive
  times — overriding and ending turn"). With a tool call between blocks it
  honored all twelve that one run made.
- The shipped hook, run as the Stop hook of a session with no tools, `GC_AGENT`
  set to the deacon and the reset target emptied, handed back three times,
  then took its reset path and let the turn end, writing the state file back
  to a zero count.

**The deacon's wisp commands name the city store.** The startup reconcile's
queries and pour (`agents/deacon/prompt.template.md`), and next-iteration's
fallback query and pour (`formulas/mol-deacon-patrol.toml`), pass
`--city="$GC_CITY_PATH"`. `gc bd` takes `--city` anywhere in its arguments
(`extractBdScopeFlags`, `cmd/gc/cmd_bd.go`), and an explicit city overrides
`GC_RIG` and the working directory (`resolveBdScopeTarget`). Run from a rig
worktree with `GC_RIG=gc-toolkit`, the unpinned list answered from the rig
store with no deacon wisp. The pinned list answered from the city store with
the live one.

## Not addressed here

- boot-health's cold reports reach an unread mailbox. That is tk-wsvoyyh.
- The witness shares the overlay and runs as an always-mode session too. Its
  sessions restart dozens to hundreds of times a day, which shows no stall
  like this one, so the hook does not act for it.
