---
name: Research — context-aware recycling for gascity (idle-detection parallel)
description: Read-only research on what's already built, what's missing, and what the path forward is for replacing gascity's heuristic cycle-recycle counters (N=6 wisps, M=8 idle polls) with a deterministic context-fill signal. Inventories existing transcript/context infrastructure, documents idle-detection layering, surveys Claude Code's introspection surface, and frames three options (ignore / local patch / engage upstream) with concrete next-bead handoffs.
---

# Research — context-aware recycling for gascity (idle-detection parallel) (tk-m8z78)

Read-only diagnostic for the bead `tk-m8z78`. Follow-up to the
2026-05-09 N=3/M=4 → N=6/M=8 retune, which the cycle-recycle template
itself names as a stop-gap until `gc context --usage` lands. The
deliverable is this document; implementation is out of scope and lives
in a follow-up bead.

## Provenance

| Doc-type or artifact | Producer | Source location (path + commit SHA) | Surveyed at |
|---|---|---|---|
| Bead description (operator stance, problem framing) | gc-toolkit__mechanik | `bd show tk-m8z78` (created 2026-05-10T01:32:02Z, comment 2026-05-10T07:32:12Z) | 2026-05-10 |
| Cycle-recycle template (current heuristic, structural-fix call-out) | gc-toolkit pack | `rigs/gc-toolkit/template-fragments/cycle-recycle.template.md` @ working tree (`3581f336` last committed; N=6/M=8 raise uncommitted on `main` at survey time) | 2026-05-10 |
| Cycle-recycle parent diagnostic — premise validation | gc-toolkit pack | `rigs/gc-toolkit/specs/tk-6hm32/analysis.md` @ `f9208e43` | 2026-05-10 |
| Cycle-recycle root-cause diagnostic | gc-toolkit pack | `rigs/gc-toolkit/specs/tk-fyzvk/analysis.md` @ `c9decbb2` | 2026-05-10 |
| Cycle-recycle implementation (startup-adopt + pour-before-burn) | gc-toolkit pack | commit `3581f336` (2026-05-08) "feat(refinery+deacon): startup-adopt + cycle-recycle pour-before-burn (tk-yvtiv)" | 2026-05-10 |
| Original cycle-recycle observation (idle polling dominates context) | gc-toolkit beads | `bd show tk-rm4dp` (closed) "Refinery cycle policy: cap context-bloat from idle polling" | 2026-05-10 |
| Cycle-recycle fragment extraction | gc-toolkit beads | `bd show tk-ovdqo` (closed) "Patrol cycle-recycle fragment: extract, apply to refinery/witness/deacon" | 2026-05-10 |
| `gc context --usage` design entry (NEEDS IMPL, tier 3) | gascity examples/gastown pack | `rigs/gascity/examples/gastown/FUTURE.md:50` @ `30986544` (last touched 2026-04-19) | 2026-05-10 |
| `gc context --usage` SDK-roadmap entry (tier 1, ~50 LOC) | gascity examples/gastown pack | `rigs/gascity/examples/gastown/SDK-ROADMAP.md:47-55` @ `733f2f52` (last touched 2026-03-27) | 2026-05-10 |
| Existing transcript-tail parser (model + ContextUsage extraction) | gascity gc binary | `rigs/gascity/internal/sessionlog/tail.go` @ `5ee3b885` (last touched 2026-04-19) | 2026-05-10 |
| Existing model-context-window lookup table | gascity gc binary | `rigs/gascity/internal/sessionlog/context.go` @ `ee0506ff` | 2026-05-10 |
| API session response with `context_pct` / `context_window` / `activity` | gascity gc binary | `rigs/gascity/internal/api/handler_sessions.go:46-51,559-589` @ `30eb4a03` | 2026-05-10 |
| API agent response with same fields + `enrichSessionMeta` | gascity gc binary | `rigs/gascity/internal/api/handler_agents.go:62-68,436-461` @ `a173472c` | 2026-05-10 |
| API enrichment design (the doc that produced the above) | gascity engdocs | `rigs/gascity/engdocs/archive/analysis/api-enrichment-audit.md` "Gap 9: Session log viewer (model, context usage, conversation)" | 2026-05-10 |
| First-class context plumbing into the API | gascity gc binary | commit `fb4b0a7a` (2026-03-06) "feat: enrich API with first-class agent state, status counts, rig metadata, and session context" | 2026-05-10 |
| Dashboard-ready session enrichment | gascity gc binary | commit `6a449fb4` (2026-03-08) "feat: enrich session API with dashboard-ready fields" | 2026-05-10 |
| Default Claude hook config (PreCompact already wired) | gascity gc binary | `rigs/gascity/internal/hooks/config/claude.json:16-26` @ `25232add` | 2026-05-10 |
| PreCompact-hook origin commit (replace `gc prime` with `gc handoff`) | gastownhall/gascity | PR #313 (merged 2026-04-05) — `https://github.com/gastownhall/gascity/pull/313` | 2026-05-10 |
| Churn circuit breaker for context-exhaustion death spirals | gastownhall/gascity | PR #246 (merged 2026-04-06) — `https://github.com/gastownhall/gascity/pull/246` | 2026-05-10 |
| Runtime `GetLastActivity` interface (last-I/O signal) | gascity gc binary | `rigs/gascity/internal/runtime/runtime.go:164-166` @ `b43a6b78` | 2026-05-10 |
| Runtime sleep-capability probe | gascity gc binary | `rigs/gascity/internal/runtime/probe.go` @ `f6da4cc0` | 2026-05-10 |
| Cockpit external context observer (peek tmux pane, grep `ctx:N%`) | gc-toolkit pack | `rigs/gc-toolkit/assets/scripts/cockpit.sh:141-150,226-310` @ `c9f548bd` | 2026-05-10 |
| Claude Code statusLine input schema (`context_window.used_percentage`) | local Claude install | `~/.claude/cache/changelog.md:2234` (changelog entry: "Added `context_window.used_percentage` and `context_window.remaining_percentage` fields to status line input") | 2026-05-10 |
| Claude Code PreCompact hook support | local Claude install | `~/.claude/cache/changelog.md:630` (entry: "Added PreCompact hook support: hooks can now block compaction by exiting with code 2 or returning `{\"decision\":\"block\"}`") | 2026-05-10 |
| User's local statusLine reads `.context_window.used_percentage` | overseer (zook) settings | `~/.claude/statusline-command.sh` (lines 4–10) | 2026-05-10 |
| Claude Code session JSONL transcripts (the read-source) | local Claude install | `~/.claude/projects/<slug>/<session-uuid>.jsonl` (e.g. this session under `-home-zook-loomington--gc-worktrees-gc-toolkit-polecats-gc-toolkit-nux/`) | 2026-05-10 |

## TL;DR

The cycle-recycle template's claim — that `gc context --usage` is the
structural fix and the heuristic counters are a workaround — is **correct
in intent but understates how much of the structural fix is already
built**. gascity already parses Claude Code session transcripts, computes
context % per model, and surfaces it via the API server (since 2026-03-06,
PR-equivalent commits `fb4b0a7a` + `6a449fb4`). The dashboard consumes
it. The cockpit consumes a tmux-statusline grep variant. **What is
missing is a CLI surface an in-session agent can call** — `gc context
--usage` from FUTURE.md / SDK-ROADMAP — and a clean way to resolve "this
session" from inside an agent's shell.

Separately, **Claude Code itself already provides the structural exit
path**: the `PreCompact` hook fires when Claude Code is about to
auto-compact the context window. The default `internal/hooks/config/claude.json`
already wires `PreCompact` to `gc handoff --auto "context cycle"` (PR
#313, merged 2026-04-05). So the **reactive** "context is full, hand
off now" path is solved at the framework level.

The cycle-recycle heuristic counters are doing a different job: they
recycle **proactively at clean wisp boundaries** before Claude Code's
auto-compact trigger fires mid-task. The proxy (wisp count + idle-poll
count) is a stand-in for "how full is context right now," which is
exactly what the existing gascity infrastructure can answer for an
*external* observer but not yet for a *self*-observer.

**Recommendation: Option B (local patch).** Implement `gc context
--usage` as a thin CLI over the existing `internal/sessionlog` +
worker `SessionLogAdapter` — the heavy lifting is done. Estimated
~100-200 LOC including session-key resolution from agent env. Then
update the cycle-recycle template to consult it as the primary trigger
with the heuristic counters as a fallback. Detailed in §6.

## 1. Inventory — gascity context-tracking work that already exists

The bead frames `gc context --usage` as not-yet-built. That's true at
the **CLI layer**, but the implementation pipeline is largely in place.

### 1.1 Transcript-tail parser (`internal/sessionlog`)

**Source:** `rigs/gascity/internal/sessionlog/tail.go` @ `5ee3b885`,
`rigs/gascity/internal/sessionlog/context.go` @ `ee0506ff`.

The package reads the last `tailChunkSize = 64 KiB` of a Claude Code
JSONL session file, walks JSONL entries backwards, and extracts:

- `Model` (from the most recent `assistant` entry's `model` field)
- `ContextUsage{InputTokens, Percentage, ContextWindow}` — computed as
  `(input_tokens + cache_read_input_tokens + cache_creation_input_tokens) * 100 / contextWindow`,
  capped at 100
- `Activity` ∈ `{"idle", "in-turn", ""}` derived from `stop_reason` /
  `system.turn_duration` / interrupt detection (`InferActivity`)
- `MalformedTail` heuristic for transcript corruption

Model → context-window mapping is a hard-coded family table
(`modelFamilyWindows` in `context.go`):

```go
"opus":   200_000,
"sonnet": 200_000,
"haiku":  200_000,
"gemini": 1_000_000,
"gpt-5":  258_000,
"codex":  258_000,
"gpt-4":  128_000,
"gpt-4o": 128_000,
```

**Discoverable bug (out of scope for this research bead):** Opus 4.7
runs in a 1M-token window when invoked as `claude-opus-4-7[1m]`, but
this table maps any "opus"-family substring to 200K. A correct
percentage requires honoring the explicit window suffix (or reading
the actual window size from the model card). Worth filing as a P2 bug
on its own — the rest of this research applies regardless.

### 1.2 API surface (`internal/api/handler_sessions.go`, `handler_agents.go`)

**Source:** `rigs/gascity/internal/api/handler_sessions.go:46-51,559-589` @ `30eb4a03`
and `rigs/gascity/internal/api/handler_agents.go:62-68,436-461` @ `a173472c`.

Both `sessionResponse` and `agentResponse` carry:

```go
Model         string `json:"model,omitempty"`
ContextPct    *int   `json:"context_pct,omitempty"`
ContextWindow *int   `json:"context_window,omitempty"`
Activity      string `json:"activity,omitempty"`
```

The `enrichSessionMeta` / inline session-list enrichment helpers
discover the agent's transcript via
`worker.SessionLogAdapter.DiscoverTranscript(provider, workDir, sessionKey)`
and call `TailMeta` on the result. The discovery prefers session-key
lookup when available (Codex/Gemini sessions guard against cross-reading)
and falls back to workdir-scoped lookup for Claude. Routes are
registered at `internal/api/supervisor_city_routes.go:54-58, 257-260`:

- `GET /agents` and `GET /agent/{base|dir/base}`
- `GET /sessions` and `GET /session/{id}`

The dashboard is the primary consumer (typed via
`cmd/gc/dashboard/web/src/generated/types.gen.ts:143-144,2433-2434`).

### 1.3 The implementation history

| Commit | Date | What it added |
|---|---|---|
| `fb4b0a7a` | 2026-03-06 | "feat: enrich API with first-class agent state, status counts, rig metadata, and session context" — initial wiring |
| `6a449fb4` | 2026-03-08 | "feat: enrich session API with dashboard-ready fields" — extended to per-session enrichment |
| `5ee3b885` | 2026-04-19 | "fix: restore worker branch ci regressions" — last touch on `tail.go` |

The design rationale lives in
`rigs/gascity/engdocs/archive/analysis/api-enrichment-audit.md` "Gap 9:
Session log viewer (model, context usage, conversation)", which
explicitly outlines the two layers (Layer A: agent-summary fields,
Layer B: full transcript endpoint) and the model-window lookup table.

### 1.4 The CLI gap

There is **no `cmd_context.go` and no `gc context` subcommand**. An
in-session agent cannot call `gc context --usage` and get a number
back; the only consumers today are the API server (over HTTP) and the
cockpit (which peeks the tmux pane). FUTURE.md and SDK-ROADMAP both
list the CLI as NEEDS IMPL and budget it at ~50 LOC.

### 1.5 What the cockpit shows about real context fill

`rigs/gc-toolkit/assets/scripts/cockpit.sh:141-150` defines
`peek_ctx <session-id>`:

```sh
gc session peek "$1" 2>/dev/null \
  | grep -oE 'ctx:[0-9]+%|Context [0-9]+% used' \
  | tail -1 \
  | grep -oE '[0-9]+'
```

This greps the tmux scrollback for whatever the in-pane status line
last rendered. `draw_ctx_watch` (lines 226–310) tiers the result:

| Tier | Range | Action |
|---|---|---|
| hidden | `<12%` | Don't surface |
| watch | `12–25%` | Yellow column |
| care | `26–49%` | Orange column |
| red | `≥50%` | Red column |

The cockpit is therefore an **external** consumer of the same signal
gascity already computes internally — it just reads it through the
display surface (tmux pane) instead of calling the API. The 50% "red"
threshold is meaningfully below the cycle-recycle heuristic's implied
fire-point (which the recycle-cause comment cites at "63% context
after 1+1 wisps"), confirming that context-fill measurement at the
proactive-recycle horizon is well within range of what the parser
already produces.

## 2. Idle-detection mechanism — the parallel the bead asks about

The bead asks if idle detection is the closest architectural parallel
to context-fill detection, and whether the same shape is reusable.
**Three different "idle" signals exist at three different layers**;
they all carry "agent is not doing work" but answer different
questions. Context fill would slot in alongside them, not replace any.

### 2.1 Layer A — Runtime I/O activity (`runtime.GetLastActivity`)

**Source:** `rigs/gascity/internal/runtime/runtime.go:164-166` @ `b43a6b78`,
`internal/runtime/probe.go` @ `f6da4cc0`.

The session-provider interface (tmux/ACP/etc.) reports the last time
*any* I/O was observed on the session's pty. This is the lowest-level
signal: it tells the controller-side reconciler whether a session is
"alive but quiet" or "alive and chatty," and it gates automatic idle
sleep (`SessionSleepCapability`). The reconciler/wake logic uses it
heavily (`internal/api/runtime_observation.go:31`,
`huma_handlers_agents.go:100-101,214-215`).

**Properties:** Cheap, provider-agnostic, no transcript parsing.
Doesn't know anything about turn boundaries — a Claude that's
streaming output and a Claude that's printing a long bash result both
look "active."

### 2.2 Layer B — Transcript activity (`sessionlog.InferActivity`)

**Source:** `rigs/gascity/internal/sessionlog/tail.go:147-235` @ `5ee3b885`.

Reads the JSONL tail and classifies the most recent meaningful entry:

| Entry | Maps to |
|---|---|
| `system.turn_duration` | `idle` |
| `assistant.stop_reason ∈ {end_turn, stop_sequence, max_tokens, …}` | `idle` |
| `assistant.stop_reason = tool_use` | `in-turn` |
| `user` (non-interrupt) | `in-turn` |
| `user` containing `[Request interrupted by user]` | `idle` |

This is the same machinery that already produces `ContextUsage`. Both
fields ship together on `agentResponse`.

**Properties:** Semantically meaningful (turn-aware), Claude-specific
(Codex/Gemini transcript shapes differ — see `canUseCheapTranscriptLookup`
guard). Requires the session-log file path and the Claude Code session
key for clean disambiguation.

### 2.3 Layer C — Prompt-level event-watch idle counter

**Source:** `template-fragments/cycle-recycle.template.md` lines 13–21
+ `rigs/gascity/examples/gastown/SDK-ROADMAP.md:62-74` (Tier 2,
`gc events --watch`, IMPLEMENTED).

Each patrol agent counts consecutive `gc events --watch` returns with
no events and no work. After M=8 (raised from M=4 on 2026-05-09),
the agent recycles. The counter is in-prompt — gascity has no
durable "idle counter" bead; the agent maintains it in working memory.

**Properties:** Crude proxy for "this session has been polling without
finding anything to do for ~45+ minutes." Doesn't observe context
fill at all — it observes a *correlate* of context fill (every `gc
events --watch` round-trip leaves event-payload metadata in the
context window).

### 2.4 What this means for the bead's premise

The "idle parallel" the bead asks about is real but partial:

- **Idle is a signal the framework can surface** — gascity already
  exposes Layer A (runtime I/O) and Layer B (transcript turn state)
  for *external* consumers (controller, dashboard, cockpit).
- **Context fill is symmetric** — gascity already computes it. Same
  data path (transcript), same surfacing (API).
- **Prompt-level proxy counters are a different category** — they are
  what an in-session agent does *because* it can't call back to the
  framework. Both the cycle-recycle counters and the M=8 idle-poll
  counter live here. They will go away when the agent can self-query.

So idle and context-fill are siblings at the framework layer. The
extensibility question — "is the architecture extensible to a context-
fill signal?" — answers itself: it already is, the wiring just stops
short of a CLI surface for in-session use.

## 3. Claude Code introspection surface

What does Claude Code expose to an agent running inside it?

### 3.1 Environment variables (none useful for context fill)

Surveyed via `env | grep -iE 'claude|context|ctx|token'` in this
session:

```
AI_AGENT=claude-code/2.1.126/agent
CLAUDECODE=1
CLAUDE_CODE_ENTRYPOINT=cli
CLAUDE_CODE_EXECPATH=/home/linuxbrew/.linuxbrew/Caskroom/claude-code/2.1.126/claude
```

Per `~/.claude/cache/changelog.md:88`: `CLAUDE_CODE_SESSION_ID` is
exposed to Bash subprocess env (matches the `session_id` passed to
hooks). **No env var for current context %, current usage, current
window size, model, or compaction state.**

### 3.2 The `statusLine` command — the only documented Claude-side
emitter of `context_window.used_percentage`

Per `~/.claude/cache/changelog.md:2234`:

> Added `context_window.used_percentage` and
> `context_window.remaining_percentage` fields to status line input
> for easier context window display

Per `~/.claude/cache/changelog.md:107`:

> Fixed statusline `context_window` token counts reflecting
> cumulative session totals instead of current context usage

The status-line command is invoked by Claude Code on every turn (and
on screen redraws). It receives a JSON object on stdin including:

```jsonc
{
  "cwd": "...",
  "context_window": {
    "used_percentage": <number>,
    "remaining_percentage": <number>
  },
  "rate_limits": {
    "seven_day": { "used_percentage": <number>, "resets_at": "..." }
  },
  // …
}
```

**The user's installed status-line script
(`~/.claude/statusline-command.sh:4-10`) already reads this field**,
which is why the cockpit's `peek_ctx` regex matches `ctx:N%` — that
string is the script's own rendering of `context_window.used_percentage`.

**Implication:** Claude Code does emit the metric, just not to a
surface an agent can read directly. The status-line command runs as a
shell subprocess Claude Code spawns; the agent's tool calls cannot
invoke it the way they invoke arbitrary Bash. But because it's a
shell script, it can write the value to a known file each invocation,
and an agent can read that file. This is the cheapest hybrid surface.

### 3.3 `PreCompact` hook — the existing reactive structural answer

Per `~/.claude/cache/changelog.md:630`:

> Added PreCompact hook support: hooks can now block compaction by
> exiting with code 2 or returning `{"decision":"block"}`

`rigs/gascity/internal/hooks/config/claude.json:16-26` already wires
this:

```json
"PreCompact": [
  {
    "matcher": "",
    "hooks": [
      {
        "type": "command",
        "command": "… gc handoff --auto \"context cycle\""
      }
    ]
  }
]
```

PR #313 (merged 2026-04-05) replaced an earlier `gc prime --hook`
configuration that double-injected the agent-context block on every
compaction cycle. The current behavior: when Claude Code decides to
auto-compact, the hook fires and `gc handoff --auto` writes a HANDOFF
bead before compaction proceeds.

**Implication:** the **reactive** "context is too full, hand off now"
behavior is *already structural* — it doesn't depend on heuristics. The
gap the cycle-recycle counters address is the **proactive** version:
hand off at a clean wisp boundary *before* PreCompact would fire mid-
turn. That requires the agent to know its own context % during normal
execution, not just at the compaction trigger.

### 3.4 Other Claude Code hook events (changelog inventory)

From `~/.claude/cache/changelog.md` references:

- `SessionStart` (subtypes: `startup`, `resume`)
- `SessionEnd`
- `PreToolUse`, `PostToolUse`, `PostToolUseFailure`
- `Stop`, `StopFailure`, `SubagentStop`
- `UserPromptSubmit`
- `PreCompact`
- `TaskCreated`, `CwdChanged`, `FileChanged`
- `WorktreeCreate`

None except the status-line command are documented to receive
`context_window.*`. PostToolUse hook input was extended with
`duration_ms` (changelog line 328) but not context fields. Stop /
SubagentStop were extended with `last_assistant_message` (line ~170)
but not context fields.

### 3.5 Self-readable transcript

Each Claude Code session writes a JSONL transcript under
`~/.claude/projects/<path-slug>/<session-uuid>.jsonl`. An agent with
file-read access (which polecats have, by definition) can read that
file. This is exactly what `internal/sessionlog/tail.go` does today —
the agent could run the same parsing logic.

Two practical complications for an in-session agent:

1. **Knowing which file is theirs.** The slug is derived from the
   project path Claude Code was launched in, which may not match the
   agent's current `pwd` if the agent started in a parent dir and
   then `cd`'d into a worktree. (Verified empirically in this session:
   transcript lives under
   `~/.claude/projects/-home-zook-loomington--gc-worktrees-gc-toolkit-polecats-gc-toolkit-nux/`
   even though `pwd` is the bead-scoped sub-worktree.)
2. **Multiple sessions per project dir.** Claude Code stores all
   sessions for a given project together; an agent must know its own
   session UUID to pick the right file. The `CLAUDE_CODE_SESSION_ID`
   env var (when present) resolves this; otherwise newest-mtime is a
   reasonable heuristic.

Both complications are already solved inside the worker package
(`workertranscript.DiscoverKeyedPath` + `DiscoverFallbackPath`), so a
CLI that reuses that logic gets the disambiguation for free.

## 4. Architectural home — where context awareness should live

| Option | Producer | Consumer | What's missing |
|---|---|---|---|
| Framework-level (Claude Code) | Anthropic | All agents (any provider, no extra integration) | Anthropic adds env var / CLI / hook input field; out of our control, long lead time |
| Gascity-level (gc binary) | gascity | gascity agents only (Claude / Codex / Gemini via existing adapters) | CLI surface (`gc context --usage`); session-key resolution from agent env; ~100–200 LOC over existing infra |
| Hybrid (status-line side-channel) | Operator-managed `~/.claude/statusline-command.sh` | gascity agents only, only when Claude Code redraws status line | Status-line script writes to a known file per turn; agents read it; tmux-only, fragile to redraw timing |

### 4.1 Framework-level — pros and cons

**Pros:** Clean separation. Every provider that supports it gets the
signal uniformly. Agents don't need gascity to reason about context.
Anthropic owns the model-window table and gets it right (including
the Opus-4.7-in-1M case the gascity table currently misses).

**Cons:** Lead time is bounded by Anthropic's roadmap, not ours. The
existing `statusLine` JSON proves Claude Code can emit the value; what
doesn't exist yet is a stable surface for an in-session shell to read
it. Filing this as a feature request is reasonable but doesn't
unblock the proactive-recycle problem this quarter.

### 4.2 Gascity-level — pros and cons

**Pros:** Almost entirely already built. `gc context --usage` is
budgeted in SDK-ROADMAP at ~50 LOC; in practice it's closer to 100–200
LOC because the CLI must resolve "this session" from the agent's env.
Reuses `internal/sessionlog` directly. Provider-aware (the existing
adapters already disambiguate Claude vs. Codex vs. Gemini transcripts).

**Cons:** The transcript is tail-only (last 64 KiB) and may
occasionally miss the most recent assistant `usage` block during
turns where the tail boundary lands mid-message. The sessionlog
package handles this gracefully (returns nil; caller treats as
unknown). The Opus-1M model-window bug must be fixed before any
recycle-decision can trust the percentage. **The sessionlog tail also
reflects the most recent assistant message's `input_tokens` total —
which during a multi-tool-use turn lags the live in-flight request by
at most one tool call.** That precision is sufficient for proactive
recycle decisions at clean-wisp boundaries; it is *not* sufficient
for fine-grained mid-turn throttling, but the bead is not asking for
that.

### 4.3 Hybrid — pros and cons

**Pros:** Zero new gascity code if the operator owns the status-line
script. The script can write `{"context_pct": N, "ts": ISO}` to
`~/.claude/runtime/context-state.json` (or any per-session path) every
time Claude Code redraws.

**Cons:** Tmux-pane-shaped — depends on Claude Code's redraw cadence,
which is not a stable contract. Already partially in production via
the cockpit's `peek_ctx`, which is acceptable for an *external*
operator but fragile for an *agent's* core decision logic. Couples
gascity's recycle decision to a piece of code outside gascity's repo
(the user's status-line script). Doesn't help non-Claude providers.

## 5. Path forward — three options the operator can pick from

Framed as the standard ignore / local patch / engage upstream model.

### Option A — Ignore (status quo)

Keep the N=6/M=8 heuristic counters as the cycle-recycle trigger.
Continue tuning the constants if reality drifts.

**Cost:** Zero engineering. **Risk:** The cycle-recycle template
itself (lines 100–102 in working tree) acknowledges these are proxies;
they over-fired before, may under-fire next, and require empirical
retuning every time the patrol shape changes.

**Concrete next bead:** *None.* This is the do-nothing path.

### Option B — Local patch (recommended)

Implement `gc context --usage` per FUTURE.md / SDK-ROADMAP, then
update the cycle-recycle template to consult it as the primary
trigger with the heuristic counters as a fallback.

**Build:**

1. New `cmd_context.go` exposing `gc context --usage` (and likely
   `gc context --activity` for symmetry, since it's free from the
   same TailMeta call).
2. Resolves "this session" from agent env (`GC_SESSION_ID`,
   `CLAUDE_CODE_SESSION_ID`, `GC_AGENT`, `GC_RIG`) by calling the
   already-running supervisor API server — `GET /agents/{name}` —
   rather than re-implementing transcript discovery in the CLI. The
   API already does the work; the CLI just renders it.
3. Update the model-window table in `internal/sessionlog/context.go`
   to honor explicit `[1m]` / `[200k]` suffixes (and add Opus-4.7-1M).
4. Update `template-fragments/cycle-recycle.template.md` so the
   trigger reads:

   > Recycle when **any** trigger fires:
   >
   > 1. **Context-fill signal.** `gc context --usage` returns ≥ N% (e.g. 60).
   > 2. **Completed-wisp count.** N closed patrol wisps. (Fallback.)
   > 3. **Idle-poll count.** M consecutive empty `gc events --watch` waits. (Fallback.)

   The structural trigger fires first when available; fallbacks
   remain in case the API is unreachable, the transcript is stale, or
   `--usage` returns unknown. Explicitly mark fallbacks as such.

**Estimated scope:** ~100–200 LOC (binary CLI + fix), ~30 lines of
template prose. Bounded. Reuses everything in §1.1–§1.3.

**Concrete next bead:** *File a P2 task on gc-toolkit (or gascity if
the operator routes this upstream) titled "Implement `gc context
--usage` CLI; rewire cycle-recycle trigger". Description points at
this research doc, the SDK-ROADMAP entry, the existing `internal/
sessionlog` + handler code, and the model-window-table bug. Use
mol-polecat-work; deliverable is one PR adding the command, the
table fix, and the template change.*

### Option C — Engage upstream (Anthropic / Claude Code)

File a feature request asking Claude Code to expose
`context_window.used_percentage` to in-session agents, ideally via:

- An env var refreshed each turn (e.g. `CLAUDE_CONTEXT_USED_PCT`), or
- A documented hook event with that field in input (e.g. `PreToolUse`
  or a new `TurnStart` hook), or
- A native slash command that returns the value.

**Concrete next bead:** *File an issue at
`https://github.com/anthropics/claude-code/issues` titled "Expose
context_window.used_percentage to in-session agents (env or hook)".
Include the use case (multi-agent orchestration framework wanting to
make proactive recycling decisions before PreCompact fires), reference
the existing `statusLine` input field as proof Claude Code already
computes the value, and link this research doc.*

**Lead time:** Out of our control. **Right thing regardless** —
Anthropic-side resolution would benefit other agent frameworks (Cline,
Aider, etc.) and lets us drop the gascity-specific patch when it lands.

### Recommendation

**Take Option B, file Option C in parallel.** The Option B work is
small, reuses existing infrastructure, and unblocks proactive
context-aware recycling this quarter. The Option C ticket is the
right long-term shape and incurs no cost beyond filing it.

Do not pursue Option A; the cycle-recycle template's own footnote
points at the structural fix and the proxies have already been retuned
once in three days, suggesting they will keep needing retuning.

## 6. Open questions for the operator

1. **Trigger threshold.** §5 Option B suggests "≥ 60%" by analogy to
   the cockpit's "red" tier (≥50%) and the original 63% observation.
   The cycle-recycle constants document explains *why* the proxies
   fire where they do; the operator may want a different threshold
   depending on patrol shape and how disruptive a mid-task PreCompact
   would be. Suggest leaving it as a per-formula variable.

2. **Fallback ordering.** §5 Option B keeps wisp-count and idle-poll
   as fallbacks. Open question: do we want them as **fallbacks**
   (only fire when context-fill is unknown) or as **belt-and-
   suspenders** triggers (fire when *any* of the three conditions is
   met)? Belt-and-suspenders is more conservative; fallbacks are
   cleaner once the structural signal is reliable.

3. **Provider scope.** `internal/sessionlog` parses Claude transcripts
   well. Codex/Gemini transcripts have different shapes — the API
   `canUseCheapTranscriptLookup` guard already excludes them. The CLI
   should likely return "unknown" rather than a wrong number for
   those providers, with a follow-up bead to extend transcript
   support.

4. **Model-window-table fix.** The Opus-4.7-1M miscount is a real bug
   that affects any consumer (dashboard, cockpit, future CLI).
   Probably worth its own P2 fix bead independently of this work.
