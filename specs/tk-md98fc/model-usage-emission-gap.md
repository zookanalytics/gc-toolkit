---
name: model-usage-emission-gap
description: Why a long-lived claude session records zero model-usage facts for a whole awake interval while working, and why the agent-token-telemetry check cannot tell that gap from benign idleness — with the two gascity fixes it needs.
---

# Model-usage emission gap: a stale session_key binds both sweeps to a dead transcript

The `agent-token-telemetry` doctor check (gascity
`cmd/gc/doctor_agent_token_telemetry.go`) is the reader, and it is correct: it
reports an awake, model-invoking session that has recorded no model-usage fact
for over an hour. The gap is upstream, in the emission path that writes
`.gc/usage.jsonl`.

The finding this bead was filed on — two persistent sessions (mechanik
`lx-0kl2y`, gascity refinery `lx-ekpvw`) silent for 135m and 121m while
working, sink healthy for every other session — is one instance of a single
defect: **a claude session's `session_key` selects the transcript that every
usage recorder reads, no writer points a non-empty `session_key` at the
conversation the process is currently writing, and it is cleared only by a
fresh-wake conversation reset. When a session begins a
new conversation (a new transcript file) without a preceding fresh-wake reset —
a resume that the provider forks to a new file, a `/clear`, a compaction that
rotates the file — `session_key` stays pinned to the previous conversation's
file. Every recorder then reads that now-dead transcript, finds nothing after
its cursor, and records nothing for the entire new interval.**

The code fix is in gascity. This bead is filed in gc-toolkit with the
diagnosis; see [Follow-up](#follow-up-work) for the gascity beads.

## The emission path has three recorders, all keyed on session_key

A claude session's model usage reaches `.gc/usage.jsonl` through three paths.
All three resolve the transcript the same way, so all three fail together when
the resolution is wrong.

1. **Prompt-op seam** — `internal/worker/invocation_telemetry.go:101`
   `recordInvocationTelemetry`, called on a successful turn from
   `internal/worker/handle_lifecycle.go:261,305` (the Message/Nudge callers). It
   fires only for turns driven through the worker handle. A `claude-watch`
   session whose turns happen in its own tmux pane (operator-typed, or
   self-driving after a nudge) does not reach this seam.

2. **Live in-interval sweep** — `cmd/gc/usage_compute.go:532`
   `sweepLiveSessionModelUsage`, run every reconcile tick (floored to 30s by
   `liveModelSweepMinInterval`, `usage_compute.go:45`) for each awake session.
   For a session whose interval never ends, this is the only recorder.

3. **Terminal sweep** — `cmd/gc/usage_compute.go` `emitDueComputeFacts` →
   `SweepSessionModelUsage`, run once when the awake interval ends.

For claude, all three resolve the transcript through
`internal/session/chat.go:1214` `TranscriptPathClassified`, whose first rung is
`workertranscript.DiscoverKeyedPath(searchPaths, provider, workDir,
b.Metadata["session_key"])` (`chat.go:1230`). For the claude family that call
lands on `sessionlog.FindSessionFileByID(searchPaths, workDir, session_key)`
(`internal/worker/transcript/discovery.go:76`), which returns
`<project-dir>/<session_key>.jsonl` when that file exists.

## Root cause: no writer reconciles a non-empty session_key to the live conversation

`session_key` holds the claude conversation UUID, which is the transcript
filename stem. Several writers set it, and they split by whether the stored key
is already populated.

**Write-when-empty.** These set a key only when none is stored, so they never
touch a live one:

- Bead creation mints one for a provider that takes a `--session-id` flag
  (`cmd/gc/session_beads.go:1896-1899`), and the same reconcile backfills a
  legacy bead whose key is empty (`session_beads.go:2190-2194`).
- A fresh start mints one when the candidate carries none
  (`cmd/gc/session_lifecycle_parallel.go:1085-1097`).
- `gc prime --hook`, wired to the session's SessionStart hook, reads the
  provider session id from the hook stdin and writes it, but returns early when
  a key is already stored: `if existing := strings.TrimSpace(info.SessionKey);
  existing != "" { return }` (`cmd/gc/cmd_prime.go:775-778`). `PersistSessionKey`
  carries the identical guard (`internal/session/manager.go:2020`), and
  `maybePersistDerivedSessionKey` is dead — `derivedResumeSessionKey` is a stub
  returning `""` (`internal/worker/provider_resume.go:3`).

**Mint-fresh-on-transition.** These replace a non-empty key, but with a newly
generated UUID for a NEW conversation — never the id of the conversation already
on disk:

- A fresh restart mints a new key (`freshRestartSessionKey`,
  `cmd/gc/session_reconciler.go:833-863`).
- A config-drift repair rotates a non-empty key to a fresh one unless the
  resume-preserving gate holds (`resetConfiguredNamedSessionForConfigDriftInfo`,
  `session_reconciler.go:5668-5678`; the tk-z130v.5 mechanism below).

Between transitions the key is preserved: an ordinary sleep keeps it
(`SleepPatch`, `internal/session/lifecycle_transition.go:422-434`), and only two
resets clear it — the fresh-wake reset, where `session_key` is a member of
`freshWakeConversationResetKeys` (`lifecycle_transition.go:84`) applied when a
drain acknowledges with `freshWake` set (`AcknowledgeDrainPatch`,
`CompleteDrainPatch`, `lifecycle_transition.go:439-465`), and the recovery reset
`ConversationResetPatch` (`internal/session/lifecycle_exits.go:184`), applied by
wake-failure and churn recovery (`cmd/gc/session_reconcile.go:709,805`).

The only source that carries the live conversation's real provider session id is
the SessionStart hook stdin, and its writer refuses a non-empty key. So no path
reconciles a stored non-empty `session_key` to the conversation the process is
actually writing: the write-when-empty writers never touch it, and the
transition writers replace it with a freshly minted id, not the live one. When
the live transcript diverges from the stored key mid-interval, nothing corrects
it until the next fresh wake.

## Why the divergence records nothing, for the whole interval

With `session_key` pinned to the previous conversation's UUID and that file
still on disk:

- `FindSessionFileByID(session_key)` resolves the OLD file (it exists), so
  discovery returns `TranscriptFound` with the dead path — not absent, not
  ambiguous.
- The live sweep memoizes that path (`usage_compute.go:554-573`) and, because
  discovery returned a found path (settled, non-empty), never re-discovers for
  the epoch. The memo is keyed by `(session_id, awake_started_at, session_key)`
  (`usage_compute.go:585`); with `session_key` frozen it is never invalidated.
- Each sweep reads the dead transcript, whose cursor
  (`invocation_usage_cursor`) already sits at its last entry, so
  `usagesSinceCursor` returns nothing (`invocation_telemetry.go:422`).
- The new conversation's turns are never read by any recorder.

The cursor is not the culprit: `usagesSinceCursor` returns ALL window entries
when the cursor has scrolled out of the tail (`invocation_telemetry.go:432`), so
a stale cursor against the RIGHT transcript would still emit. The failure is
discovery pointing at the wrong file.

The gap self-heals only at the next fresh wake, which clears `session_key` and
lets `gc prime --hook` capture the current UUID. That is why the incident is
intermittent and why every currently-awake session shows a correct key.

## The discriminator: deacon works because it wakes fresh often

The report named deacon (`lx-54vlh`) as the control: same provider
(`claude-watch`), same named-session shape, also rotates transcripts, records
fine. The difference is interval length, not shape.

- deacon runs a patrol cadence: each cycle is a fresh wake that clears
  `session_key`, so the next SessionStart hook re-captures the current UUID.
  Measured: deacon's project dir holds a new transcript every ~15 minutes
  (13:15, 13:30, 13:39, …), each captured correctly.
- mechanik and the refinery hold a single conversation across a long interval.
  A rotation inside that interval leaves `session_key` stale, and nothing
  re-captures until the interval finally ends.

Short intervals are also covered by the terminal sweep at interval end; a
long-awake session depends entirely on the live sweep, which is exactly the
lane the report pointed at.

## Forensic corroboration (mechanik, 2026-09-02 → 09-03)

From the surviving transcripts in
`~/.claude/projects/-home-zook-loomington--gc-agents-mechanik/`:

- Pre-wake transcript `fd110900-…`: usage-bearing turns 2026-09-02T19:40 →
  **23:11:48**. The report's newest recorded fact for mechanik was
  **23:12:01Z** — the fact stream stops exactly at this transcript's last turn.
- Post-wake transcript `41348736-…` (mechanik woke 23:22:09): usage-bearing
  turns from **23:22:29** onward, **154** of them. The report measured mechanik
  silent for 135 minutes across this same span.

The last recorded fact came from the transcript the session left at 23:22; the
154 turns of the conversation it moved to were never recorded. That is the
stale-key binding, observed end to end.

## Relationship to existing beads

- **tk-z130v.5** (gc-toolkit tracking bead, closed will-not-fix) recorded the
  mirror defect in the same subsystem: an asleep named session that
  config-drifts takes the asleep-drift repair path where the `preserveResume`
  gate is false and a fresh `session_key` is minted, losing the resume the
  operator expected. There `session_key` rotates when it should be preserved;
  here it is preserved when it should rotate — both are `session_key` failing to
  track the live transcript. The operator ruled it will-not-fix (converse visit
  tk-2vaa9r, 2026-09-04), so it stands as historical context here, not an active
  dependency.
- **tk-jnrm6i** (gc-toolkit, open) owns the reader's noise problem: the check's
  partial-silence arm re-escalates forever because benign idleness is this
  city's designed steady state, and it argues (correctly) that cheap
  suppressions would also mask the fleet-wide outage arm. The self-announcing
  discriminator below is the real fix it asks for, and it resolves this bead's
  "confirm by hand every time" cost at the same time.

## Fix

Both changes are in gascity.

### R1 — reconcile session_key to the live conversation (the root cause)

The SessionStart hook's stdin carries the provider session id of the
conversation the process is actually writing to. The event fires with a
separate source for each start — `startup`, `resume`, `clear`, `compact`,
`fork` — but the managed hook that runs `gc prime --hook` is wired only for
`startup` (`internal/hooks/config/claude.json:7-16`; the live
`.gc/settings.json` carries the same single matcher). So the writer never runs
on the mid-session rotations that reproduce the bug: resume, `/clear`, and
compaction. R1 is two changes that must land together.

**R1a — a reconciling writer.** When the hook supplies a concrete provider
session id for a family that is trusted on hook stdin
(`providerAcceptsHookStdinSessionID`, codex/claude) and it differs from the
stored `session_key`, UPDATE it instead of returning early at
`cmd/gc/cmd_prime.go:775-777`. This needs a reconciling writer distinct from
`PersistSessionKey`'s set-when-empty contract (e.g. a
`Manager.ReconcileSessionKey` that overwrites, called only from the trusted
hook-stdin path so the non-empty guard still protects every other writer). On
overwrite, reset `invocation_usage_cursor` so the new transcript is swept from
its start.

**R1b — fire the hook on the rotations.** Wire the managed Claude hook so
`gc prime --hook` runs on `resume`, `clear`, `compact`, and `fork`, not only
`startup`: add those matchers, or use an empty matcher so the command matches
every source (the form the config already uses for `PreCompact` and
`UserPromptSubmit`). Without R1b the reconciling writer is never invoked on the
rotations and R1a alone leaves the bug live. If `gc prime --hook` is unsafe to
run on a given source, gate that inside the command rather than by narrowing
the matcher.

Test: a claude session bead with `session_key=OLD`, a SessionStart hook stdin
carrying `NEW`, and both `OLD.jsonl` and `NEW.jsonl` on disk — assert the bead's
`session_key` becomes `NEW` and a subsequent `SweepSessionModelUsage` records
`NEW`'s turns. Control: hook stdin carrying `OLD` (no change) and an untrusted
family (no overwrite). Add a config regression asserting the managed Claude
hook runs the persistence command for `resume`, `clear`, `compact`, and `fork`
(or through a source-agnostic matcher), so a later edit cannot silently narrow
it back to `startup`.

Defense in depth (optional, same bead): when the live sweep's keyed lookup
resolves a transcript whose tail has not advanced past the cursor while a newer
unambiguous transcript exists in the same workdir, prefer re-discovery. This
keeps ambiguity refusal for shared (pooled) workdirs.

### R2 — make the check self-announcing (serves tk-jnrm6i)

`agentTokenTelemetryCheck` reads only `.gc/usage.jsonl` and the session beads,
so it cannot separate "idle, nothing to record" from "working, not recorded,"
and hands a human that judgement every hour. Give it the discriminator it is
missing: for each session it would flag silent, resolve the session's live
transcript INDEPENDENTLY of the stored `session_key` — the newest transcript
actually being written under the session's `work_dir` — and compare its last
usage-bearing turn against the session's newest recorded fact.

- Live transcript has completed turns newer than the newest fact → a real
  emission gap. Announce it as such (the actionable finding), and it doubles as
  the live detector for R1's failure mode.
- Live transcript's last turn matches the newest fact → genuinely idle.
  Suppress or downgrade.
- Workdir has no unambiguous newest transcript (a shared pool workdir) → fall
  back to today's advisory wording rather than guess.

Resolving independently of `session_key` is the crux: reusing the sweep's keyed
lookup would read the same dead file and misreport the gap as idle. This is a
detection change and does not replace R1 — the check announcing the gap is not
the same as the gap not happening.

Test: three session fixtures against a pinned clock — (a) silent, live
transcript has a turn newer than the last fact → flagged real; (b) silent, live
transcript's last turn equals the last fact → classified idle; (c) shared
workdir with two live transcripts → advisory fallback.

## Follow-up work

- gascity `gc-zb3st` — R1, reconcile session_key on the SessionStart hook.
- gascity `gc-1fke8` — R2, self-announcing agent-token-telemetry discriminator
  (resolves tk-jnrm6i's escalation noise).
