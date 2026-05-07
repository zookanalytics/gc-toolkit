{{ define "cycle-recycle" }}
### Cycle-recycle policy

Long-running patrol agents (refinery, witness, deacon) need to recycle
their context periodically so it doesn't accumulate from idle polling and
event metadata. The structural fix is `gc context --usage` (gascity
FUTURE.md tier 3, NEEDS IMPL); until that lands, apply the heuristic
policy below.

Recycle when **either** trigger fires:

1. **Completed-wisp count.** You have closed **3 or more** patrol wisps
   in this session. Each patrol cycle pours and burns one wisp; three
   full cycles is roughly the point at which find-work polling and
   event-metadata accumulation start to dominate context.

2. **Idle-poll count.** You have done **4 or more** consecutive
   `gc events --watch` waits that returned with no events and no work
   found (~30 minutes of idle polling at the default 30s→300s
   exponential backoff). Reset the counter as soon as an event arrives
   or work is found — the next idle stretch is what counts, not the
   cumulative.

**Action when a trigger fires:**

```bash
gc handoff "context cycle: <reason>"
```

Examples:
- `gc handoff "context cycle: 3 patrol wisps closed this session"`
- `gc handoff "context cycle: 30+ min idle, find-work events accumulated"`

`gc handoff` writes a durable HANDOFF bead and, for
controller-restartable sessions, also requests a restart. For
on-demand named sessions (refinery, witness, and deacon when configured
that way), the handoff mail is sent but the controller cannot restart
the user-attended process — **the operator must `/clear`** to recycle.
Either way, the next session reads the HANDOFF bead and resumes from
clean state.

**After running `gc handoff`:**

- Sit idle. Do not start the next cycle.
- Surface the handoff message in your output so the operator sees it.
- Wait for `/clear` (or controller restart). The next session resumes
  from the HANDOFF bead.

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

- N=3 wisps: observed point where the find-work polling loop begins to
  dominate context (gc-toolkit refinery, 2026-05-06: 63% context after
  one completed wisp + one in-progress over 5h49m — most of the bloat
  was idle-poll history, not merge work).
- M=4 idle waits: with the default 30s timeout doubling to a 300s cap,
  four consecutive empties is roughly 30 min of accumulated event
  metadata.
- `gc handoff` over `gc runtime request-restart`: `request-restart`
  silently no-ops for on-demand named sessions because the controller
  cannot restart user-attended processes. `gc handoff` always writes a
  HANDOFF bead, so the next session has clean resume state regardless
  of whether a controller restart, an operator `/clear`, or a
  PreCompact hook restarted it.
{{ end }}
