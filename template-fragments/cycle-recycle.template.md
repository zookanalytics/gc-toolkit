{{ define "cycle-recycle" }}
### Cycle-recycle policy

Long-running patrol agents (refinery, witness, deacon) need to recycle
their context periodically so it doesn't accumulate from idle polling and
event metadata. The structural fix is `gc context --usage` (gascity
FUTURE.md tier 3, NEEDS IMPL); until that lands, apply the heuristic
policy below.

Recycle when **either** trigger fires:

1. **Completed-wisp count.** You have closed **6 or more** patrol wisps
   in this session. Each patrol cycle pours and burns one wisp.

2. **Idle-poll count.** You have done **8 or more** consecutive
   `gc events --watch` waits that returned with no events and no work
   found (~45+ minutes of idle polling at the default 30s→300s
   exponential backoff). Reset the counter as soon as an event arrives
   or work is found — the next idle stretch is what counts, not the
   cumulative.

**Action when a trigger fires (pour-next-before-handoff):**

The formula's universal invariant is **"pour next before burn current"** —
every other exit path obeys it. Cycle-recycle must obey it too, so the
inheriting session finds an in-progress wisp on its hook regardless of
whether the startup discovery query catches it.

```bash
# 1. Pour the next wisp BEFORE handoff so the inheriting session
#    finds a fresh in-progress wisp on its hook.
NEXT=$(gc bd mol wisp <mol-{role}-patrol> --root-only <vars...> --json | jq -r '.new_epic_id')
gc bd update "$NEXT" --assignee=$GC_AGENT

# 2. Write the durable HANDOFF mail. For controller-restartable sessions
#    this also stops the runtime so the controller respawns; for on-demand
#    named sessions it only writes mail and returns.
gc handoff "context cycle: <reason> (next wisp: $NEXT)"

# 3. Trigger the actual restart. For controller-restartable sessions
#    gc handoff already stopped the runtime so this typically never runs.
#    For on-demand named sessions (refinery, witness, named-deacon) this
#    is what respawns the user-attended process. Also clears any tripped
#    named-session respawn circuit breaker.
gc session reset "$GC_ALIAS"
```

Examples:
- `gc handoff "context cycle: 6 patrol wisps closed this session (next wisp: $NEXT)"`
- `gc handoff "context cycle: 45+ min idle, find-work events accumulated (next wisp: $NEXT)"`

**Layered model.** `gc handoff` is the state-capture command: it always
writes the durable HANDOFF bead, and for controller-restartable
sessions it also stops the runtime so the controller respawns the
process. `gc session reset` is the explicit-restart-trigger: it does
not write mail of its own — the durable record is the HANDOFF bead
from step 2 — but it forces a fresh respawn for on-demand named
sessions where `gc handoff` cannot. Chaining the two covers both
classes from a single recycle path: step 2 captures state; step 3 is a
no-op for controller-restartable (the runtime is already stopped) and
the actual restart trigger for on-demand named.

Including `$NEXT` in the message body makes the inherited wisp ID
discoverable to the new session even if its tier-1 in-progress query
somehow misses it (race, status flip, etc.).

**After running the recycle sequence:**

- The new session boots from the controller-driven respawn (step 2 for
  controller-restartable, step 3 for on-demand named) and reads the
  HANDOFF bead on its first action.
- It finds the in-progress next wisp via its tier-1 startup query
  (assignee = `$GC_ALIAS`, status = `in_progress`) and resumes from
  clean state. **No operator `/clear` is required** — the chain handles
  the restart end-to-end.
- Surface the handoff message (with the next-wisp ID) in your output
  before the reset fires so any attached operator sees what happened.

**Cost / caveats.**

- `gc session reset` invokes `tmux kill-session`. The host tmux session
  for the agent is destroyed and respawned. Anything not written to
  durable state before recycle is lost: pane scrollback, mid-edit
  `Edit`/`Write` content that didn't complete, co-located helper
  panes / `tail -f` windows / debugger panes the operator has open in
  the session.
- The HANDOFF mail bead written in step 2 is durable in the bead store
  and survives the restart. It is the canonical carry-forward; the new
  session reads it on first action.
- The platform's restart-request path **does not check operator
  attachment**. The config-drift path does (session reconciler), but
  restart-request bypasses it. If the operator is attached to the
  named coord's tmux pane to watch or debug at the moment cycle-recycle
  fires, the session will be killed under the operator without
  warning.
- Implication for trigger design: cycle-recycle thresholds must be
  tight. Don't fire on weak signals. The canonical thresholds (6
  patrol wisps closed OR 8 idle waits since last work) exist for this
  reason — they're set high enough that recycle reflects a genuine
  need for fresh context, not noise.

**Pathological-loop note.** If the cycle-recycle trigger somehow fires
repeatedly (e.g. event-watch loop bug, runaway counter), each cycle
adds a new wisp with no opportunity to burn the prior one. Accumulated
wisps are detectable as multiple open patrol wisps assigned to
`$GC_ALIAS`; the startup discovery's tier-3 step adopts the newest and
closes older ones with `'orphaned cross-rotation'` reason.

**Verifying the wisp count (optional):**

```bash
gc bd list \
  --type=molecule --mol-type=patrol \
  --assignee="$GC_ALIAS" \
  --status=closed \
  --closed-after="$SESSION_START_ISO" \
  --json | jq length
```

`$SESSION_START_ISO` is the ISO timestamp captured when this session
began (e.g. `date -Iseconds` written to a session-scoped temp file the
first time the recycle check runs). The check is for verification —
your own count of completed cycles in this session is the authoritative
signal.

**RSS as a fallback only.** Process RSS does not track Claude's context
window directly, so it is not a primary trigger. If RSS exceeds 1500 MB
*and* neither trigger above has fired, treat it as a soft warning to
re-check the counters more strictly — but do not recycle on RSS alone.

**Why these specific thresholds:**

- N=6 wisps and M=8 idle waits: raised 2026-05-09 from N=3/M=4 because
  the original numbers (calibrated on a single 2026-05-06 observation
  of 63% context after 1+1 wisps in 5h49m) caused agents to recycle
  before they accomplished much real work. Idle-poll history was the
  dominant context bloat in that observation, not merge work, so for
  active patrols the original ceiling was much lower than necessary.
  These new thresholds are still proxies — the structural fix is
  context-fill measurement (`gc context --usage` per FUTURE.md).
- `gc handoff` chained with `gc session reset` over `gc runtime
  request-restart` alone: `request-restart` silently no-ops for
  on-demand named sessions because the controller cannot restart
  user-attended processes from inside the session. `gc handoff` always
  writes the durable HANDOFF bead (the canonical carry-forward), and
  the chained `gc session reset` is what actually respawns named
  sessions without requiring operator `/clear`.
{{ end }}
