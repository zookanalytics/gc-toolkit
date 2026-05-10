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
post-`/clear` session has an in-progress wisp waiting on its hook
regardless of whether the startup discovery query catches it.

```bash
# 1. Pour the next wisp BEFORE handoff so the inheriting session
#    finds a fresh in-progress wisp on its hook.
NEXT=$(gc bd mol wisp <mol-{role}-patrol> --root-only <vars...> --json | jq -r '.new_epic_id')
gc bd update "$NEXT" --assignee=$GC_AGENT

# 2. Hand off, mentioning the next-wisp ID so the next session knows
#    what to inherit even if discovery somehow misses it.
gc handoff "context cycle: <reason> (next wisp: $NEXT)"
```

Examples:
- `gc handoff "context cycle: 6 patrol wisps closed this session (next wisp: $NEXT)"`
- `gc handoff "context cycle: 45+ min idle, find-work events accumulated (next wisp: $NEXT)"`

`gc handoff` writes a durable HANDOFF bead and, for
controller-restartable sessions, also requests a restart. For
on-demand named sessions (refinery, witness, and deacon when configured
that way), the handoff mail is sent but the controller cannot restart
the user-attended process — **the operator must `/clear`** to recycle.
Either way, the next session reads the HANDOFF bead and resumes from
clean state. Including `$NEXT` in the message body makes the inherited
wisp ID discoverable to the new session even if its tier-1 in-progress
query somehow misses it (race, status flip, etc.).

**After running `gc handoff`:**

- Sit idle. Do not start the next cycle yourself — the new wisp is
  poured but unstarted, waiting for the post-`/clear` session.
- Surface the handoff message (with the next-wisp ID) in your output so
  the operator sees it.
- Wait for `/clear` (or controller restart). The next session reads
  the HANDOFF bead, finds the in-progress wisp via its tier-1 startup
  query, and resumes from clean state.

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
- `gc handoff` over `gc runtime request-restart`: `request-restart`
  silently no-ops for on-demand named sessions because the controller
  cannot restart user-attended processes. `gc handoff` always writes a
  HANDOFF bead, so the next session has clean resume state regardless
  of whether a controller restart, an operator `/clear`, or a
  PreCompact hook restarted it.
{{ end }}
