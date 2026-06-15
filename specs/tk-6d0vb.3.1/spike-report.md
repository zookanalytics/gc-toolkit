# Spike report: context-recycle mechanism for the bead-HOST case (`tk-6d0vb.3.1`)

**Bead:** `tk-6d0vb.3.1` — *research: validate context-recycle mechanism for
the bead-HOST case (handoff-restart + context-size source) + recommend tuning*
(child of `tk-6d0vb.3`, *Context-aware bead-host: suggest an
operator-gated flush-then-handoff recycle — Gas City's `/compact` for
conversations*; host epic `tk-6d0vb`, *Bead-Universe Operating Model*)
**Branch:** `polecat/tk-6d0vb.3.1`
**Polecat:** `gc-toolkit/gc-toolkit.slit`
**Surveyed at:** 2026-06-15
**Status:** Findings + recommendations. **Research only — no implementation.**
Per the brief, this does **not** touch `agents/bead-host/prompt.template.md`.
The two live-city probes that would side-effect running agents (restart a host;
hit the supervisor API under auth) are **deferred to the operator** (§Operator
verification), per the `tk-oml75` / `tk-k9s0k` precedent that a polecat must not
restart agents in the live city. Everything that could be settled read-only
(code trace) or non-destructively (read my own transcript) **is** settled below.

---

## TL;DR — the four questions, answered

**Q1 (load-bearing) — Is a bead-host controller-restartable; does a restart give
a FRESH transcript on the same alias? → YES. The premise FIRES.**
The brief's worry was that a bead-host is an *"on-demand configured named
session"* for which `gc handoff` only writes mail and cannot restart. **It is
not.** Empirically, a live bead-host's session bead carries
`configured_named_session = null` (not `"true"`), so `isNamedSessionBead` is
**false**, so `sessionRestartableByController` returns **true**
(`cmd/gc/cmd_handoff.go:347-350`). The handoff caveat applies only to *configured*
named sessions (those declared in `pack.toml [[named_session]]` with
`mode != "always"`, e.g. refinery) — a bead-host has no such declaration. All
three restart paths — `gc handoff` (self), `gc runtime request-restart`,
`gc session reset` — therefore produce a **fresh, empty transcript on the same
alias/bead** for a `wake_mode=resume` host, via `Manager.RequestFreshRestart`
→ `continuation_reset_pending=true` → session-key rotation + a
`continuation_epoch` bump (`internal/session/manager.go:869`;
`cmd/gc/session_reconciler.go:1697-1701`; `cmd/gc/session_wake.go:48-50`).
**Recommended primitive: `gc handoff` self-handoff for the flush+restart in one
call; `gc session reset "$GC_ALIAS"` as the gate-free fallback.** One genuine
semantic fork to ratify (§Q1.4): *fresh-restart* (scope reset) vs Claude-native
*`/compact`* (continuity-preserving) — the operator's own "/compact for
conversations" framing points at the latter; the dispatch directive's
"flush-then-handoff" points at the former. They are different recycles.

**Q2 — How does a bead-host read its own context size? → Read its own
transcript tail. Do NOT depend on the supervisor API.**
The API endpoint the cycle-recycle template uses
(`GET /v0/city/{cityName}/agent/{base}` → `.input_tokens`) is **real**
(`internal/api/handler_agents.go:62-66`) but unreachable from a host's
environment without work: `GC_API_URL` is **never exported** to agents,
`GC_CITY` is **not guaranteed** for a host, and the 404 in recon was the empty
`{cityName}` path-segment collapsing the route. `gc context --usage` **still does
not exist**. The robust path needs only `pwd` + the Claude session id, both
always present:

```bash
# Empirically validated in THIS session: returned input_tokens=167926.
SLUG=$(pwd | sed 's:[/.]:-:g')
JSONL="$HOME/.claude/projects/$SLUG/${CLAUDE_CODE_SESSION_ID}.jsonl"
[ -f "$JSONL" ] || JSONL=$(ls -t "$HOME/.claude/projects/$SLUG/"*.jsonl 2>/dev/null | head -1)
TOKENS=$(grep '"usage"' "$JSONL" | tail -1 \
  | jq '[.message.usage.input_tokens,
         .message.usage.cache_read_input_tokens,
         .message.usage.cache_creation_input_tokens] | add // 0')
# Window from the transcript's OWN model field (not an env var — no GC_MODEL exists,
# and AI_AGENT carries no model id / [1m] suffix). Mirrors ModelContextWindow.
MODEL=$(grep '"model"' "$JSONL" | tail -1 | jq -r '.message.model // .model // empty')
case "$MODEL" in *'[1m]'*|*gemini*) WINDOW=1000000;; *) WINDOW=200000;; esac
```

**Correction to the prior recipe:** the transcript filename is
`$CLAUDE_CODE_SESSION_ID` (the Claude provider UUID, e.g. `7abe773f-…`), **not**
`$GC_SESSION_ID` (the gc id, e.g. `lo-6fcgw`). Verified directly (§Q2.2).

**Q3 — Soft-band default? → A fraction of the model window (~55–60%), floored at
a host-meaningful absolute (~120K), per-host overridable.** The patrols' flat
200K is a work-product accumulation threshold for throwaway heartbeat context;
a host's context is denser and continuity-bearing, so band on the *window* (so
it travels correctly across a 200K vs 1M model) and leave headroom for the
`/compact` net. Rationale in §Q3.

**Q4 — Command word + escalating salience? → Surveyed, not decided (operator's
call).** Vocabulary already in play: `/compact`, `/handoff`, "cycle/recycle",
`gc session reset`. The heartbeat *"never ask the operator"* rule does **not**
bind a host — a host is conversational, so *suggesting* a recycle is exactly
right (the opposite of patrol discipline). Options + tradeoffs in §Q4.

---

## Provenance

| Artifact / fact | Source | How verified | At |
|---|---|---|---|
| `.3` dispatch directive ("suggest, never auto-fire; no hard cap; PreCompact kept as net") | `gc bd show tk-6d0vb.3` notes | read | 2026-06-15 |
| This bead's research brief (the 4 questions) | `gc bd show tk-6d0vb.3.1` notes | read | 2026-06-15 |
| Bead-host role doc (the impl surface — **not edited**) | `agents/bead-host/prompt.template.md` @ `c23a2e1` | read | 2026-06-15 |
| Bead-host agent config (`scope=city`, `wake_mode=resume`, `idle_timeout=8h`, `min_active_sessions=0`) | `agents/bead-host/agent.toml` | read | 2026-06-15 |
| Host spawn tool + binding contract ("`continuation_epoch` stays constant across resume wakes; a change = lineage reset") | `tools/gc-bead-host.sh` header | read | 2026-06-15 |
| Cycle-recycle policy (200K patrol threshold; handoff+reset chain; "never ask") | `template-fragments/cycle-recycle.template.md` | read | 2026-06-15 |
| Heartbeat no-consent rule (why patrols never ask; `/handoff` is operator-initiated) | `template-fragments/heartbeat-no-consent-ui.template.md` | read | 2026-06-15 |
| reset-vs-handoff semantics (reset = whole-session kill; handoff = pane respawn) | `specs/tk-my4za/reset-vs-handoff-audit.md` | read | 2026-06-15 |
| Handoff skill (session-shape classification; `/compact` vs handoff; carry-forward) | `skills/handoff/SKILL.md` | read | 2026-06-15 |
| Prior context-recycling research (API surface, `gc context` budgeted-not-built, transcript parser) | `specs/tk-m8z78/research-context-aware-recycling.md` | read | 2026-06-15 |
| **Restart→fresh-transcript mechanism** (`RequestFreshRestart`, key rotation, epoch bump, restartability gate) | gascity `internal/session/`, `cmd/gc/` (see §Q1.3 citations) | code trace (delegated deep-read) | 2026-06-15 |
| **Context-size API surface** (endpoint shape, `input_tokens` field, why 404, no `gc context`, transcript fallback) | gascity `internal/api/`, `internal/sessionlog/`, `cmd/gc/main.go` (see §Q2 citations) | code trace (delegated deep-read) | 2026-06-15 |
| **Empirical: bead-host `configured_named_session=null`** | live session bead `lo-wisp-k410` (hosts `tk-6d0vb`) | `gc bd show lo-wisp-k410 --json` | 2026-06-15 |
| **Empirical: transcript-tail self-read = 167926 tok** | this polecat's own `…/7abe773f-….jsonl` | ran the recipe | 2026-06-15 |
| **Empirical: PreCompact net = `gc handoff --auto "context cycle"`** | gascity `internal/hooks/config/claude.json:17-26` | read | 2026-06-15 |
| **Empirical: `gc context --usage` absent** | `gc context --usage` → "unknown flag" | ran | 2026-06-15 |

Code-trace citations come from two focused read-only deep-reads of the gascity
tree (`rigs/gascity` @ working tree, `c23a2e1`-era). They are reproducible: every
claim below carries a `file:line` an operator can re-open.

---

## Q1 — Is a bead-host controller-restartable, and does a restart flush context?

### Q1.1 The worry, stated precisely

`.3` wants the host to do a *flush-then-handoff recycle*: capture state, then
restart into a **fresh, empty transcript under the same alias** so the bloated
context window is dropped. The recon that filed this bead flagged a load-bearing
risk, grounded in `gc handoff`'s own help text:

> *"For on-demand configured named sessions, sends mail and returns WITHOUT
> requesting restart because the controller cannot restart the user-attended
> process."*

If a bead-host is such a session, `gc handoff` writes mail and **does not
restart** — the flush never happens, and `.3`'s whole premise collapses.

### Q1.2 The resolution: a bead-host is NOT a *configured* named session

The restartability decision is a single function:

```go
// cmd/gc/cmd_handoff.go:332-350
func sessionRestartableByController(store beads.Store, sessionName string) (bool, error) {
    ...
    if !isNamedSessionBead(b) {
        return true, nil          // ← bead-host lands HERE
    }
    return namedSessionMode(b) == "always", nil
}
```

and `isNamedSessionBead` is a pure metadata read:

```go
// internal/session/named_config.go:162-164,172-174
func IsNamedSessionBead(b) bool { return b.Metadata["configured_named_session"] == "true" }
func NamedSessionMode(b)  string { return b.Metadata["configured_named_mode"] }
```

`configured_named_session` is stamped only for sessions **declared in
`pack.toml [[named_session]]`**. In this city the only such declaration is
`mechanik` (`mode = "always"`); a bead-host is spawned ad hoc by
`tools/gc-bead-host.sh` via `gc session new --alias <bead>` and is **not**
declared. So its session bead never gets the flag.

**Empirical confirmation (live host, read-only):**

```
$ gc bd show lo-wisp-k410 --json | jq '.[0].metadata | {configured_named_session, configured_named_mode, wake_mode, state}'
{ "configured_named_session": null, "configured_named_mode": null, "wake_mode": "resume", "state": "awake" }
```

`lo-wisp-k410` is the live host for `tk-6d0vb` (this arc's own epic). With
`configured_named_session = null`, `isNamedSessionBead → false`,
`sessionRestartableByController → true`. **`gc handoff` and
`gc runtime request-restart` DO restart a bead-host.** The caveat the brief
quoted targets the *configured* on-demand class (refinery and friends), which a
bead-host is not.

### Q1.3 The fresh-transcript mechanism (and that `wake_mode=resume` does not block it)

All three restart verbs converge on one worker call:

- `gc handoff` (no `--target`): `cmd/gc/cmd_handoff.go:212` `handle.Reset(...)`
- `gc runtime request-restart`: `cmd/gc/cmd_runtime_drain.go:534` `handle.Reset(...)`
- `gc session reset`: `cmd/gc/cmd_session_reset.go:94` `handle.Reset(...)`

`SessionHandle.Reset` → `Manager.RequestFreshRestart`, the load-bearing write:

```go
// internal/session/manager.go:869-879
return m.store.SetMetadataBatch(id, map[string]string{
    "restart_requested":          "true",
    "continuation_reset_pending": "true",   // the fresh-transcript trigger
})
```

The reconciler then, for a Claude-style provider (`--session-id`/`--resume`),
**rotates the resume key to a brand-new UUID and clears `started_config_hash`**:

```go
// cmd/gc/session_reconciler.go:1697-1701
newSessionKey, hasCapability := freshRestartSessionKey(tp, session.Metadata) // new UUID
batch := sessionpkg.RestartRequestPatch(newSessionKey, clk.Now())            // clears started_config_hash
```

so the next wake takes the **fresh** branch (`--session-id <new-uuid>` = empty
conversation), not `--resume <old-key>` (replay):

```go
// cmd/gc/session_reconciler.go:4006-4010  (resolveSessionCommand)
if (firstStart || forceFresh) && rp.SessionIDFlag != "" {
    return command + " " + rp.SessionIDFlag + " " + sessionKey   // FRESH
}
return resolveResumeCommand(...)                                  // replay
```

A second, independent layer agrees: `preWakeCommit` reacts to
`continuation_reset_pending` by clearing `session_key` **and bumping the
continuation epoch** (`cmd/gc/session_wake.go:48-50,113-123`). **Key point:**
`wake_mode` is read **only** as `== "fresh"` anywhere in the controller; there is
**no `wake_mode == "resume"` branch**. `resume` is merely the default
("not-fresh"), and it governs the *natural sleep→wake* cycle only. An **explicit
restart always goes fresh**, resume-mode or not. The command's own doc strings
say so: `cmd_session_reset.go:21` "fresh provider conversation state";
`RequestFreshRestart` is literally the method name.

This also lines up with the host-binding contract, which already anticipated the
distinction: *"`continuation_epoch` stays constant across resume-mode wakes …; a
change in epoch means the conversation lineage was reset"*
(`tools/gc-bead-host.sh` header). A recycle is exactly "a change in epoch." The
host can **observe its own recycle**: `$GC_CONTINUATION_EPOCH` (exported to every
session — `internal/session/lifecycle.go:36`) increments in the post-recycle
incarnation.

**Per-path summary:**

| Path | Restarts a bead-host? | Transcript after |
|---|---|---|
| `gc handoff` (self) | **Yes** (restartable=true) — also writes the durable carry-forward in one call | **Fresh** |
| `gc runtime request-restart` | **Yes** | **Fresh** |
| `gc session reset "$GC_ALIAS"` | **Yes — and gate-free** (`handle.Reset` called unconditionally, no restartability check; also clears any tripped circuit breaker) | **Fresh** |

### Q1.4 The semantic fork the operator should ratify: fresh-restart vs `/compact`

A fresh restart **works**, but it is a *scope reset*: the new incarnation has
**no transcript**. It re-primes cold from the bead universe (`gc bd show
"$BEAD"`) plus whatever durable carry-forward exists. That is the right recycle
when the conversation has *turned over* (a phase closed, resolved sub-threads
bloating context). It is the **wrong** recycle when the value is *continuity* —
and continuity is a host's entire reason to exist.

Claude-native **`/compact`** is the other shape: it summarizes in place and
**continues the same session** (no epoch bump, transcript preserved-as-summary).
The handoff skill already draws this line — recommend `/compact` for *"routine
context trimming where continuity matters more than scope reset"*
(`skills/handoff/SKILL.md:104-106`). And the **reactive net already is
`/compact`-shaped**: PreCompact fires `gc handoff --auto "context cycle"`
(`internal/hooks/config/claude.json:23`); for a restartable host that is a
fresh-restart at the model's hard edge.

The two source texts pull different ways, and `.3` should resolve it explicitly:

- The operator's **title** — *"Gas City's `/compact` for conversations"* —
  points at **continuity-preserving** compaction.
- The dispatch **directive** — *"flush-then-**handoff** recycle"* — points at
  **fresh-restart**.

**Recommendation for `.3`:** implement the **fresh-restart** path (it is what
"handoff" means and what the mechanism delivers), but **name the continuity cost
in the suggestion** and offer `/compact` as the lighter alternative the operator
can pick instead. Concretely, two load-bearing implementation notes:

1. **The "flush" must land in the BEAD, not in handoff mail.** A fresh restart
   drops the transcript; the next incarnation re-primes by re-reading the bead
   (`agents/bead-host/prompt.template.md` "On Resume — reflect current reality"),
   **not** by checking mail. So the carry-forward (what the operator and host
   were mid-weighing, un-noted ideas) must be written to the work bead's
   **notes/takeaway** before the restart — that is what survives and what the
   next incarnation reads. `gc handoff`'s HANDOFF *mail* bead is the wrong
   vehicle for a host; the takeaway-per-turn discipline the host already follows
   is the right one, extended with a richer pre-recycle note.
2. **The post-recycle incarnation is a COLD prime, not a resume.** The role doc's
   "On Resume" path assumes transcript replay; after a recycle there is none.
   `.3` should make the first-reaction card after a recycle reconstruct from
   `gc bd show "$BEAD"` + the carry-forward note (this is the *intentional*
   instance of the same "degraded fresh re-prime from the bead body" that
   `tk-oml75` designed for the transcript-eviction case — here it is on purpose).

### Q1.5 One residual to confirm live (operator)

`RequestFreshRestart` marks the existing session for restart; the reconciler
restarts **that** session (it is not pool-demand reconciliation, so
`min_active_sessions = 0` does not by itself suppress it). I could not *prove*
read-only that a `min_active_sessions=0` host respawns (vs. dies) after the kill
— that needs a live restart, which is operator-deferred. **`gc session reset` is
the lowest-risk way to confirm** (its doc string promises "starts the same
session again"). The §Operator-verification probe settles it in ~30s and also
demonstrates the `$GC_CONTINUATION_EPOCH` bump.

---

## Q2 — How should a bead-host read its own live context size?

### Q2.1 The API path is real but fragile from a host's environment

The cycle-recycle template reads
`curl "$GC_API_URL/v0/city/$CITY/agent/$GC_AGENT" | jq '.input_tokens'`. Every
piece of that is real:

- The route exists: `GET /v0/city/{cityName}/agent/{base}` (and a rig-qualified
  `/agent/{dir}/{base}`) — `internal/api/supervisor_city_routes.go:55-59`. The
  `{cityName}` segment is a structural constant (`internal/api/city_scope.go:43`);
  **there is no cityless `/agent` variant**.
- The field exists: `agentResponse.InputTokens *int json:"input_tokens"` plus
  `context_pct`, `context_window` (`internal/api/handler_agents.go:62-66`),
  populated unconditionally for a live Claude agent
  (`internal/api/huma_handlers_agents.go:230`). `input_tokens` =
  `input + cache_read + cache_creation` from the last assistant usage block
  (`internal/sessionlog/tail.go:328-331`).

But from a **host's** environment the call breaks for environmental reasons, not
field reasons:

- **`GC_API_URL` is never exported to agents** (it's on the runtime-fingerprint
  *exclude* list — `internal/runtime/fingerprint.go:159`). It must be defaulted.
  The default `:8372` is correct (`~/.gc/supervisor.toml [supervisor] port`,
  default 8372 — `internal/supervisor/config.go:67-72`).
- **`GC_CITY` is not guaranteed for a host.** Nothing in
  `internal/session/lifecycle.go` sets it; it comes from a separate city-identity
  layer a host isn't guaranteed to carry. When `CITY` is empty the URL collapses
  to `/v0/city//agent/…` and Huma matches no route → **the 404 from recon.** The
  city must be resolved (path→name via `gc cities --json`, which reads
  `~/.gc/cities.toml` with no env or API dependency — `cmd/gc/cmd_register.go`).
- **`gc context --usage` still does not exist** (no `context` command in
  `cmd/gc/main.go:238-298`; `gc context --usage` → "unknown flag", confirmed by
  running it). The `tk-m8z78` "Option B" CLI was never built. So there is no
  turnkey self-query.

I attempted the live API read-only end-to-end and got **no response** even from
the cityless `/v0/cities` on the default port — i.e. the API server may be
unauthenticated-unreachable from an agent shell (or bound/keyed differently).
That is itself the point: **the API path has too many ways to fail from inside a
host.** Do not hang a recycle trigger on it.

### Q2.2 Recommended: read your own transcript tail (empirically validated)

It needs only `pwd` and the Claude session id — both always present — and is
byte-for-byte what the server computes (`internal/sessionlog/tail.go:327-331`,
window from `internal/sessionlog/context.go:32-44`).

```bash
SLUG=$(pwd | sed 's:[/.]:-:g')                         # ProjectSlug: / and . → -
JSONL="$HOME/.claude/projects/$SLUG/${CLAUDE_CODE_SESSION_ID}.jsonl"
[ -f "$JSONL" ] || JSONL=$(ls -t "$HOME/.claude/projects/$SLUG/"*.jsonl 2>/dev/null | head -1)
TOKENS=$(grep '"usage"' "$JSONL" | tail -1 \
  | jq '[.message.usage.input_tokens,
         .message.usage.cache_read_input_tokens,
         .message.usage.cache_creation_input_tokens] | add // 0')
MODEL=$(grep '"model"' "$JSONL" | tail -1 | jq -r '.message.model // .model // empty')
case "$MODEL" in *'[1m]'*|*gemini*) WINDOW=1000000;; *) WINDOW=200000;; esac
PCT=$(( TOKENS * 100 / WINDOW ))
```

**Empirical:** run in this polecat session it returned **`input_tokens=167926`**
— a live, correct fill, zero API dependency.

**Two corrections to the naïve recipe, both verified here:**

1. **Filename is `$CLAUDE_CODE_SESSION_ID`, not `$GC_SESSION_ID`.** In this
   session `GC_SESSION_ID=lo-6fcgw` but the transcript is
   `…/7abe773f-…-….jsonl` = `$CLAUDE_CODE_SESSION_ID`. Using `GC_SESSION_ID`
   finds nothing. (Keep the newest-mtime `*.jsonl` fallback for the rare case
   the var is unset.)
2. **Slug = replace both `/` and `.` with `-`** (`ProjectSlug`,
   gascity `reader.go` — confirmed: my cwd
   `/home/zook/loomington/.gc/worktrees/…` slugged the `.gc` dot to `-gc`).

### Q2.3 Caveats to encode in `.3`

- **Window detection.** Default 200K; switch to 1M only when the model id carries
  `[1m]` (e.g. `claude-opus-4-8[1m]`). The gascity model-window table has a known
  Opus-1M-miscount bug (`tk-m8z78` §1.1) — reading the `[1m]` suffix directly
  sidesteps it. Today's session ran Opus 4.8 1M; at 167926 that is ~17%, not
  ~84% — getting the window right is load-bearing for the band.
- **Tail lag.** The tail reflects the *last completed* assistant turn's usage; it
  lags an in-flight turn by at most one tool call. Fine for a clean-pause recycle
  suggestion; not for mid-turn throttling (which `.3` does not need).
- **Provider scope.** This is Claude-shaped. A bead-host is Claude (this rig); if
  a host ever runs Codex/Gemini, return "unknown" rather than a wrong number.

---

## Q3 — Soft-band default (recommendation + rationale)

**The patrols' 200K does not transplant.** It is a flat *work-product
accumulation* threshold tuned for heartbeat agents whose context is
**disposable** event-poll metadata, with a hard rule to recycle the instant it
trips (`template-fragments/cycle-recycle.template.md`). A host is the opposite on
every axis that sets a threshold:

- **Denser, dearer context.** A host's window is a *continuity-bearing
  conversation about one bead*, not idle-poll noise. Recycling sooner is cheaper
  for a patrol (nothing lost) and costlier for a host (continuity lost) — so the
  host band should sit **higher in absolute terms** but trigger a **suggestion,
  not an action**.
- **Window-relative, not absolute.** 200K is the *whole* window of a 200K model
  and 20% of a 1M one (the template even says so). A host that may run Opus-1M
  should band on a **fraction of its window** so the policy is correct on both,
  with no model table.
- **Leave headroom for the net.** PreCompact (`gc handoff --auto`) is the
  hard-edge safety net. The soft band must fire **comfortably before** it, so the
  operator-gated suggestion has room to be seen and accepted before the model
  compacts on its own.

**Recommendation:** `soft_band = max(0.55 × context_window, 120_000)`, **per-host
overridable**.

- `0.55–0.60 × window` → ~110–120K on a 200K model, ~550–600K on a 1M model:
  past the cockpit's "red ≥50%" worry tier (`tk-m8z78` §1.5) but well short of
  the compaction edge.
- `120K` floor → on a 200K model the fraction alone is fine, but the floor keeps
  a hypothetical small-window host from nagging at trivial fills.
- **Per-host override** because bands are workload-shaped (a heavy
  reading/PR-diff host fills faster than a quiet watch host) — mirror
  `tk-m8z78` §6's "leave it a per-formula variable" call.

This is a *suggestion* threshold; the only hard cap remains PreCompact, per the
directive ("NO hard cap").

---

## Q4 — UX vocabulary survey (flagged for the operator; NOT decided here)

The brief says: survey, present options, do not decide. First, the framing fact:

**The heartbeat "never ask" rule does NOT bind a host.** The no-consent doctrine
is explicit that it is for **heartbeat agents** (witness, deacon, refinery)
because *"blocking the heartbeat on consent stalls patrol activity"*
(`template-fragments/heartbeat-no-consent-ui.template.md`). A bead-host is a
**conversational** agent whose entire job is to talk to the operator about one
bead. For a host, **suggesting a recycle and waiting for a yes/no is correct
behavior, not a stall** — the precise inverse of patrol discipline. `.3`'s
"suggest, operator-gated, never auto-fire" is therefore consistent with the
codebase, *as long as it is scoped to the host* and does not leak the consent UI
back into the patrol fragments.

### Q4a — The command word

| Option | Existing meaning | Fit for a host recycle | Note |
|---|---|---|---|
| **`/compact`** | Claude-native in-place compaction; the handoff skill's pick when *continuity > scope reset* | **Highest continuity.** Matches the operator's own title verbatim ("/compact for conversations"). | Does **not** flush to a fresh transcript — it summarizes in place. If `.3` truly wants *fresh*, this word mis-sells it. |
| **`/handoff`** | Operator-initiated carry-forward + **fresh transcript** (`skills/handoff/SKILL.md`) | **Highest fidelity to "flush-then-handoff."** Already means "carry the live thread forward, restart clean." | The skill is "operator-initiated only" — a host *suggesting* it is a new posture; keep the suggestion in the host prompt, do not auto-invoke the skill. |
| **"cycle" / "recycle"** | The patrols' `cycle-recycle` policy (automatic, never-ask) | Neutral, already in the vocabulary; the dispatch directive floats it | Carries patrol "automatic" connotation — may imply auto-fire, which `.3` explicitly is **not**. Needs the "suggested, gated" qualifier to avoid that read. |
| `gc session reset` | Hard whole-session kill (wedged-agent tool) | Mechanically works, gate-free | Wrong *register* for an operator-facing word — it reads as "something's broken," not "let's refresh." Keep it as the under-the-hood primitive, not the spoken verb. |

**My read (for the operator to ratify, not a decision):** the cleanest pairing
is to **say `/compact`** (it is the operator's own mental model and the
continuity-preserving truth) **for the light path**, and reserve **`/handoff`**
(or "recycle") for the **heavier fresh-restart** when the conversation has turned
over. One word over-promises if the two semantics are collapsed — §Q1.4 is the
same fork surfacing in the vocabulary. If a single word is required, **"recycle"**
is the least-wrong umbrella because it is already in-house and semantically
empty enough to define precisely in the host prompt.

### Q4b — Escalating salience

The directive's default (gentle at the band → firmer near the edge) is sound and
has a natural two-stop structure already present in the system:

- **At the soft band (§Q3):** a one-line, low-salience mention folded into the
  first-reaction card's **Proposal/Decision-needed** slot — the host already
  emits that card every turn (`agents/bead-host/prompt.template.md`), so the
  nudge costs nothing and the operator can accept/decline in the same one move
  they already use. No new UI.
- **Approaching the compaction edge** (e.g. ≥ ~80% window, below PreCompact):
  promote it to the card's headline / **takeaway** so it is visible from the
  attention board without opening the host, and state the consequence ("will
  auto-compact at the edge if not recycled").
- **The edge itself:** unchanged — PreCompact `gc handoff --auto` is the net.

Keep all of it as *salience*, never *consent-blocking*: the host should keep
working/answering while the suggestion stands, and never `AskUserQuestion`-block
its own turn waiting for the recycle answer.

---

## Recommendation summary for `.3`'s implementation

1. **The mechanism is valid — build the fresh-restart recycle.** A bead-host is
   controller-restartable (`configured_named_session=null`); `gc handoff`
   (self) restarts it into a fresh transcript on the same alias. Use **`gc
   handoff -- "context recycle" "<carry-forward>"`** as the one-call flush+restart;
   keep **`gc session reset "$GC_ALIAS"`** as the gate-free fallback. Have the
   post-recycle incarnation **verify** via the `$GC_CONTINUATION_EPOCH` bump.
2. **Flush to the bead, not to mail.** Write the carry-forward (live-conversation
   nuance) to the work bead's **notes + takeaway** *before* the restart — that is
   what the cold-primed next incarnation re-reads. Mail is the wrong vehicle for
   a host.
3. **Trigger off the transcript tail, not the API** (§Q2.2 recipe, using
   `$CLAUDE_CODE_SESSION_ID`). No `gc context` exists; the API is unreachable/
   fragile from a host env.
4. **Band on the window:** `max(0.55×window, 120K)`, per-host overridable;
   suggestion-only; PreCompact stays the sole hard net.
5. **Suggest, don't block** (host ≠ heartbeat): fold the prompt into the existing
   first-reaction card; escalate salience near the edge; never consent-block.
6. **Name the continuity cost and offer `/compact`** as the lighter alternative
   (§Q1.4 / §Q4) — resolve the "fresh-restart vs continuity" fork explicitly in
   the host prompt rather than letting one verb hide it.

## Operator verification (live probes — deferred, ~1 min)

Settles the one read-only residual (Q1.5) and the API question (Q2.1) live.
Run against a **throwaway** bead-host, not a working one.

```bash
# A. Confirm fresh-restart works on a min_active_sessions=0 host + epoch bump.
gc-bead-host.sh up <throwaway-bead>            # spawn a host
gc session peek <throwaway-bead> --lines 3     # note GC_CONTINUATION_EPOCH (=1 on first life)
gc session nudge <throwaway-bead> "echo epoch=\$GC_CONTINUATION_EPOCH"
gc session reset <throwaway-bead>              # gate-free fresh restart
sleep 20
gc session nudge <throwaway-bead> "echo epoch=\$GC_CONTINUATION_EPOCH; do you remember our prior chat?"
sleep 15; gc session peek <throwaway-bead> --lines 20
#   PASS = epoch incremented (2) AND the host has NO memory of the prior turn (fresh transcript).
gc session close <throwaway-bead>

# B. (Optional) Confirm the API read shape if you want the secondary path wired.
CITY=$(gc cities --json | jq -r --arg p "$GC_CITY" '.cities[]|select(.path==$p)|.name')
PORT=$(grep -E '^\s*port' ~/.gc/supervisor.toml | grep -oE '[0-9]+' | head -1)
curl -sf "http://127.0.0.1:${PORT:-8372}/v0/city/$CITY/agent/<dir>/<base>" | jq '{input_tokens, context_pct, context_window}'
#   PASS = numbers come back ⇒ the API path is usable as a secondary once CITY is resolved.
```

## Out of scope / open follow-ups

- **Implementation** of `.3` (the host-prompt edit) — separate bead; this is
  findings only.
- **`gc context --usage` CLI** (`tk-m8z78` Option B, still unbuilt) — would make
  Q2 turnkey for *all* agents; worth filing independently, but `.3` does not need
  it (transcript tail suffices).
- **Opus-1M model-window-table bug** in `internal/sessionlog/context.go`
  (`tk-m8z78` §1.1) — affects the API path's `context_pct`; the transcript recipe
  here sidesteps it by reading the `[1m]` suffix directly.
- **`min_active_sessions=0` respawn-after-restart** — code says the restart-request
  path restarts the existing session regardless; probe A confirms it live.
