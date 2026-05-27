{{ define "cycle-recycle" }}
### Cycle-recycle policy

Long-running patrol agents (refinery, witness, deacon) need to recycle
their context periodically so it doesn't accumulate from idle polling
and event metadata. This template adds a single **proactive** check on
top of standard GasTown — Claude's PreCompact hook in
`internal/hooks/config/claude.json` runs the auto-handoff sequence
when Claude is about to compact, and remains the reactive safety net
at the model's own compaction edge.

**Trigger.** At end-of-wisp, query `input_tokens` from the supervisor
API. If the value is at or above 200K, run the pour-next-before-handoff
sequence below.

```bash
# Supervisor API: $GC_API_URL when exported, else gc-toolkit's
# canonical default (port 8372 from ~/.gc/supervisor.toml via the
# gc_api_base helper pattern). City name resolves from $GC_CITY path
# via the gc cities registry; agent name from $GC_AGENT.
API_URL="${GC_API_URL:-http://127.0.0.1:8372}"
CITY=$(gc cities --json 2>/dev/null | jq -r --arg p "$GC_CITY" '.cities[] | select(.path == $p) | .name')
TOKENS=$(curl -sf --max-time 3 "$API_URL/v0/city/$CITY/agent/$GC_AGENT" 2>/dev/null | jq '.input_tokens // 0' 2>/dev/null || echo 0)
TOKENS=${TOKENS:-0}  # empty stdin → jq emits nothing → default to 0 for the test below
if [ "$TOKENS" -ge 200000 ]; then
  # pour-next-before-handoff ritual (below)
fi
```

If the curl fails or `input_tokens` is null (API unreachable, provider
with no transcript adapter), the check skips silently — PreCompact
still fires at the model's compaction edge. No fallback heuristic.

200K is an absolute work-product threshold, not a percentage. A
200K-window agent fires at its natural compaction edge; a 1M-window
agent at 20%. Equally correct in both cases, no model-window table
involved.

**Action when the trigger fires (pour-next-before-handoff):**

> **NEVER ask the operator whether to recycle.** Do not invoke
> `AskUserQuestion`, `/handoff`, or any other interactive consent UI
> at the threshold boundary — heartbeat agents (witness, deacon,
> refinery) blocking on consent stall patrols and gate checks for as
> long as the prompt sits unanswered. The threshold IS the directive.

The formula's universal invariant is **"pour next before burn current"** —
every exit path obeys it. Cycle-recycle must obey it too, so the
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
gc handoff "context cycle: input_tokens reached $TOKENS (next wisp: $NEXT)"

# 3. Trigger the actual restart. For controller-restartable sessions
#    gc handoff already stopped the runtime so this typically never runs.
#    For on-demand named sessions (refinery, witness, named-deacon) this
#    is what respawns the user-attended process. Also clears any tripped
#    named-session respawn circuit breaker.
gc session reset "$GC_ALIAS"
```

**Caveats.**

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
  attachment**. If the operator is attached to the named coord's tmux
  pane to watch or debug at the moment cycle-recycle fires, the
  session will be killed under the operator without warning.
- `gc handoff` (state capture) chained with `gc session reset`
  (restart trigger) covers both controller-restartable and on-demand
  named sessions from one recycle path. `gc handoff` always writes
  the HANDOFF bead and stops the runtime for controller-restartable
  classes; `gc session reset` is a no-op for those and the actual
  restart trigger for on-demand named. Including `$NEXT` in the
  handoff body makes the inherited wisp ID discoverable even if the
  new session's tier-1 startup query misses it.

**Why 200K.** Operator decision 2026-05-24. Replaces the earlier
wisp-count (N=6) and idle-poll-count (M=8) proxies, which over-fired
in event-noisy rigs — live 2026-05-24 evidence showed witness/deacon
recycling every ~10 min while sitting at 25% context. Reading
`input_tokens` directly removes the proxy counters and the
model-window table from the equation, leaving one simple rule: cycle
when the work product has actually grown to ~200K tokens.
{{ end }}
