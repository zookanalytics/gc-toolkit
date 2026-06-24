{{ define "cycle-recycle" }}
### Cycle-recycle policy

Long-running patrol agents (refinery, witness, deacon) need to recycle
their context periodically so it doesn't accumulate from idle polling
and event metadata.

**This policy is enforced by a deterministic hook, not by you.** The
gc-toolkit pack ships a Claude Code `Stop` hook in
`overlays/cycle-recycle/` (`.claude/settings.json` +
`.claude/hooks/cycle-recycle.sh`), staged into each patrol agent's work
dir via the `overlay_dir` patch on witness/deacon/refinery. The harness
runs that hook at every turn boundary regardless of model state, so the
recycle fires even when context is full — which is exactly when an
in-prompt "run the check yourself" instruction degrades and gets skipped
(the failure this replaced: tk-g8pfg). Do **not** run a context check or
a recycle sequence by hand; the hook owns it. This document is the
reference for what the hook does and why.

Two layers protect a patrol agent's context:

- **Proactive (this policy).** The `Stop` hook reads `input_tokens` from
  the supervisor API every turn and recycles at a clean turn boundary
  *before* the model's auto-compact would fire mid-task.
- **Reactive (safety net).** Claude's PreCompact hook in
  `internal/hooks/config/claude.json` runs the auto-handoff sequence at
  the model's own compaction edge if the proactive layer ever misses
  (API unreachable, provider with no transcript adapter).

**Trigger.** When `input_tokens` is at or above 200K, the hook runs the
recycle sequence below. The hook self-gates on `$GC_AGENT`: it acts only
for the witness/deacon/refinery roles and is a no-op for every other
agent (ephemeral polecats, bead-hosts, mayor, mechanik), so a focused
worker is never recycled mid-task.

```bash
# What the hook measures (see overlays/cycle-recycle/.claude/hooks/cycle-recycle.sh):
API_URL="${GC_API_URL:-http://127.0.0.1:8372}"
CITY=$(gc cities --json | jq -r --arg p "$GC_CITY" '.cities[] | select(.path == $p) | .name')
TOKENS=$(curl -sf --max-time 3 "$API_URL/v0/city/$CITY/agent/$GC_AGENT" | jq '.input_tokens // 0')
# if TOKENS >= 200000 -> recycle
```

If the curl fails or `input_tokens` is null, the hook skips silently and
PreCompact remains the net. No fallback heuristic.

200K is an absolute work-product threshold, not a percentage. A
200K-window agent fires at its natural compaction edge; a 1M-window
agent at 20%. Equally correct in both cases, no model-window table
involved.

**Recycle sequence (what the hook runs when the trigger fires):**

> **NEVER ask the operator whether to recycle.** No `AskUserQuestion`,
> `/handoff`, or any interactive consent UI at the threshold boundary —
> heartbeat agents (witness, deacon, refinery) blocking on consent stall
> patrols and gate checks for as long as the prompt sits unanswered. The
> threshold IS the directive (heartbeat-no-consent-ui).

```bash
# 1. Write the durable HANDOFF mail (carries the trigger token count
#    forward). For controller-restartable sessions this also stops the
#    runtime; for on-demand named patrol sessions it only writes mail.
gc handoff "context cycle: input_tokens reached $TOKENS"

# 2. Trigger the restart. For on-demand named sessions (refinery,
#    witness, named-deacon) this respawns the user-attended process and
#    clears any tripped named-session respawn circuit breaker. A no-op
#    for controller-restartable sessions, which step 1 already stopped.
gc session reset "$GC_ALIAS"
```

**pour-next-before-burn.** The formula's universal invariant is "pour
next before burn current." On the hook path that guarantee is delegated
to the **inheriting session's startup-adopt** (Tier-2/3 layered startup
discovery): a generic `Stop` hook fires at a turn boundary that may be
mid-wisp and cannot reliably reconstruct the patrol formula's pour vars
(`binding_prefix`, `target_branch`, `rig_name`,
`default_merge_strategy`) — those live in the agent's own prompt, not in
its environment. The fresh session re-pours/adopts its patrol wisp on
startup with the correct vars, so the next wisp is established without
the hook guessing them. The trigger token count travels in the HANDOFF
body so the new session has context before it re-derives its wisp.

**Caveats.**

- `gc session reset` invokes `tmux kill-session`. The host tmux session
  for the agent is destroyed and respawned. Anything not written to
  durable state before recycle is lost: pane scrollback, mid-edit
  `Edit`/`Write` content that didn't complete, co-located helper
  panes / `tail -f` windows / debugger panes the operator has open in
  the session.
- The HANDOFF mail bead is durable in the bead store and survives the
  restart. It is the canonical carry-forward; the new session reads it
  on first action.
- The platform's restart path **does not check operator attachment**. If
  the operator is attached to the named coord's tmux pane to watch or
  debug at the moment the recycle fires, the session will be killed
  under the operator without warning.

**Why 200K.** Operator decision 2026-05-24. Replaces the earlier
wisp-count (N=6) and idle-poll-count (M=8) proxies, which over-fired
in event-noisy rigs — live 2026-05-24 evidence showed witness/deacon
recycling every ~10 min while sitting at 25% context. Reading
`input_tokens` directly removes the proxy counters and the
model-window table from the equation, leaving one simple rule: cycle
when the work product has actually grown to ~200K tokens.

**Why a hook.** Operator decision 2026-06-24 (tk-g8pfg). The earlier
mechanism was soft prose ("apply the cycle-recycle policy at end of
wisp") inside the patrol formula steps. Formulas can run no deterministic
command step, so the check depended on the model executing it — and the
fuller the context, the less reliably it did, so context climbed and the
check was skipped harder (self-reinforcing). A session-level hook is
harness-enforced and auto-covers all three patrol roles (including the
refinery, which referenced cycle-recycle nowhere) with no per-formula
wiring.
{{ end }}
