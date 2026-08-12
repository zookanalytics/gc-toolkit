---
name: Design — The converse thread's ending is an event, not an absence
description: Fixes a converse thread vanishing mid-attention with no operator-facing completion signal (tk-bzm86). Corrects the filed diagnosis — wisp_ttl GCs closed wisp beads and never reaps a live sitting; the real clock is the pack's own idle_timeout, measured from terminal OUTPUT, capped by core's assigned-work defer backstop, and its kill clears the scrollback under wake_mode=fresh. Resolves the bead's three scope items into a sign-off block, a takeaway stamped when the hold begins, and a recorded decision not to buy longevity — plus the one fix that belongs upstream.
---

# Design: the converse thread's ending is an event, not an absence

Design record for `tk-bzm86` (P1 bug, two operator-reported instances:
2026-08-10 gc-toolkit, 2026-08-11 signal-loom). Companion to
`specs/tk-h9pq5/design-doc.md`, which built the visit/converse spine; this
records what that spine does when a sitting *ends*, which it did not say.

## The complaint

An operator was reading a converse thread — reading, not typing. It was
simply gone. No completion message, no summary, no pointer to what it had
produced. Their words: *"I don't think it said I'm done."* The second
instance, a day later in another rig: *"I thought I was having a
conversation with it and it was going to move forward work on addressing
the comments, but it is nowhere to be found."*

Both times the machinery was **correct**. The agent finished, stamped
`gc.outcome`, closed its visit, wrote its conclusions to the subject, and
in the second case dispatched follow-on work before ending. Nothing was
lost from the record. The failure is entirely at the seam where the
system meets the person watching it: **the system has a rich notion of
"done" and none of it reaches the human who was there.**

That is the whole bug, and it is worth stating in its sharp form: *the
work being recorded correctly is not a mitigation, it is the reason
nobody noticed.* Every automated check downstream sees a clean close.

## What actually ends a sitting (the filed diagnosis was wrong)

The bead named `[daemon] wisp_ttl = "8h"` as the second, timer-driven
path to the same disappearance, and reasoned about mitigations from
there. That premise does not hold, and building on it would have produced
a fix aimed at a mechanism that never fires. Verified against the gascity
source (rig checkout `7cff88fdc`, 2026-08-11):

| Claim as filed | What the source says |
|---|---|
| An 8h `wisp_ttl` reaps the visit wisp | `WispTTL` is how long a **closed** wisp (an ephemeral v1 formula-run bead) survives before deletion (`internal/config/config.go`). It GCs *records*, and never touches a live held sitting. The two 8h values are a coincidence. |
| Core owns the timer | The clock is `idle_timeout` on `agents/converse/agent.toml` — **pack-owned config**, not core policy. |
| Idle means the operator went away | Idle is the provider's last activity, which for tmux is per-window `#{window_activity}` (`Tmux.rawSessionActivity`) — pane **output** and `send-keys`. Reading produces neither. |
| A held visit is protected | It defers the stop, briefly. `DecideIdleTimeout` (`internal/session/lifecycle_timers.go`) defers on assigned work; the reconciler caps the streak at `assigned_work_defer_limit` (default 3, `cmd/gc/assigned_work_defer_tracker.go`) and then forces `assigned_work_exhausted`. At `patrol_interval = "30s"` that is ~90 seconds of grace. |
| The thread is hidden | It is **destroyed**. The stop calls `ClearScrollback` (`cmd/gc/session_reconciler.go`) and the template's `wake_mode = "fresh"` makes the respawn a clean provider session. Contrast `wake_mode = "resume"`, measured replaying a transcript across a ~15h gap (`specs/tk-oml75/spike-report.md` §1). |

So there is one real reap path, it is ours, and it has a cruel property
the filed version understated: **sustained attention is
indistinguishable from abandonment.** Leaving a thread open because you
intend to come back is exactly the behaviour that gets it collected — the
clock cannot see a reader, only a writer.

The corrected mechanism is recorded centrally in
`docs/gascity-human-engagement.md` → "How a held sitting ends", because
it is an upstream-fact question and that file is where upstream facts
live. This spec records the *design*; that file records the *mechanism*.

## The constraint that shapes every remedy

**Nothing pack-owned runs at kill time.** The reap is a reconciler
decision followed by a process kill; there is no pre-reap hook, no
shutdown formula, no last-words channel. Combined with `wake_mode =
fresh`, this eliminates two whole families of fix:

- *"Warn before the reap"* — nothing of ours is running to warn.
- *"Let the operator resume it"* — there is nothing to resume.

What is left is the only thing that survives a kill: **state written
before it.** The remedy has to be durability-in-advance plus a legible
ending on the path where we *are* still running.

## Resolution of the three scope items

### 1. On deliberate close, emit an operator-facing takeaway — **built**

Two halves, because the operator and the record need different things.

**In-thread (the human):** the sitting ends with a **sign-off block**,
posted as the thread's last word — two lines, nothing below them:

```
Ended (<one-word-outcome>): <what this sitting settled, in one line>
Look at: <subject-id> — <the one thing to read or do next>
```

This is not decoration. The converse contract already requires that
every message posted *while holding* end with `Next (yours): …` — so
before this change, the last line of a thread that ended was always an
unanswered **question**. A question, then silence, reads as a crash. The
sign-off and the hold line are mutually exclusive and both terminal:
every message ends with one or the other, so "which state is this thread
in?" is answerable from the last line alone.

**Durable (the record):** the same content is stamped on the subject via
`assets/scripts/gc-helm.sh takeaway "$SUBJECT" … --by converse` before
the close. That reuses the existing thin writer rather than inventing a
second one, and it puts the ending where the board already looks for a
NEEDS headline. `--release` is deliberately **not** passed: it clears
assignee and route and marks a proactive reaction, which would park a
subject the operator is mid-conversation about.

**Finding the writer is a search, not a path.** converse is
`scope = "rig"`, so it is imported into every rig and
`rigNameForQualifiedAgent` resolves the rig from the qualified name: a
`signal-loom/gc-toolkit.converse` session runs with `GC_RIG_ROOT` at
*signal-loom*, which ships no `assets/` at all. Both stamps therefore
walk the pack's standard candidate list — `$GC_RIG_ROOT`, the git
toplevel, `$GC_CITY_PATH/rigs/gc-toolkit` — taking the first root with
an **executable** copy, and say so loudly when none has one.

A single default (`${GC_RIG_ROOT:-<pack>}`) cannot do this: `GC_RIG_ROOT`
is *non-empty* in the broken case, so the fallback never fires and the
stamp fails before writing. That is not a hypothetical rig — this bug's
second instance was a signal-loom sitting (session `lx-qk9v`), so the
first form would have left exactly the case that motivated the fix
untraced. A missing writer is now announced in-thread rather than
swallowed, because a stamp that silently does not happen is the original
bug one level down.

Order matters and is fixed: **durable stamp → close the visit → post the
sign-off.** The writes go first so a session that dies mid-sequence has
still left the trace; the human-visible line goes last so it is what
remains on screen.

### 2. Make a reap recoverable — **built, via the "persist" arm**

The bead offered two arms: warn before the reap, or persist the takeaway
so the reap is recoverable. The warn arm is unavailable (above), so:
**the takeaway is stamped when the hold BEGINS**, not only at close —
`"holding — <the one decision or input needed>"`, the same line as
`Next (yours):`.

That single extra write per sitting converts the failure from *reaped =
nothing* into *reaped = the subject says what it was waiting for, and
when*. It is the difference between a thread that vanished and a thread
whose last known state is on the record with a timestamp.

It is deliberately cheap: one Dolt write at human pace, on a bead that
was going to be written anyway at close.

### 3. Should read-activity stay the reap clock — **decided: no change to the clock**

It cannot, as configured: activity is pane output, and tmux cannot
observe reading. There is no `idle_timeout` value that distinguishes a
watched thread from an abandoned one — only values that make *both* live
longer.

So the decision is to **keep the 8h reap and fix the signal**, which is
the bead's own framing: *"An idle reap may well be correct policy;
reaping with no signal and no trace is not."* Raising the timeout would
buy nothing here and cost something real: it widens the window in which a
dead thread looks alive, and holds a provider session against a cap
(`max_active_sessions = 6`) that real sittings need. Longevity is not the
remedy; durability is.

The false comment that hid this — `agents/converse/agent.toml` asserting
"visit boundaries, not timeouts, end it" — is corrected in place, because
that comment is what stops the next reader from checking.

**The one fix that would make attention count belongs upstream.**
Attachment *is* observable: `runtime.LiveObservation.IsAttached` is
gathered on the same observation as `LastActivity`. The idle ladder never
consults it. An `IsAttached` arm in `DecideIdleTimeout` — defer while a
human is attached — would make read-attention a first-class signal and
close the "reaping collects attention itself" hole at its source. That is
a core change in `internal/session/lifecycle_timers.go`, filed cross-rig
against the gascity rig as **`gc-rjtk1`** rather than approximated here.

## What this deliberately does not do

- **It does not build a way back to an ended thread.** "A gone converse
  leaves no reachable trace, and `gc-helm open` can only start a fresh
  visit on a subject you already know to name" is `tk-j2kpp` (P2,
  blocked on this bead). This design makes the *ending* legible and the
  trace *exist*; making it *findable without knowing the subject id* is
  that bead's scope, and the sign-off's `Look at: <subject-id>` line is
  what it will have to work with.
- **It does not put non-anchor subjects on the board.** A plain task
  subject with a `gc.takeaway` is durable but still not a board row — the
  board collects epics, floating owned convoys, and decisions. That is
  the "no second surface" note in the bead, and it is a board-scope
  question, not a thread-ending one.
- **It does not touch `wisp_ttl`.** It was never involved.

## Regression

`assets/scripts/converse-signoff.test.sh` (hermetic; reads the repo
only) pins both halves of the contract: the hold-time stamp, the
sign-off block's two lines, the cut-short path signing off too, the
absence of `--release`, the corrected agent.toml comment, and the
central mechanism record. A prompt is prose, and the stamp is exactly
the kind of line a tidy-up edit drops with nothing downstream noticing.

Writer resolution is the one part that is **executed** rather than
grepped: the test lifts each takeaway block's resolver out of the prompt
and runs it against fixture roots — an importing rig with no `assets/`,
the owning rig, an empty `GC_RIG_ROOT`, a git-toplevel pack, and nothing
at all. Extraction is deliberately shape-agnostic (everything the block
runs before invoking the writer), so a prompt that reverts to assuming
one path is *run and fails on behaviour* rather than skipped for want of
a matching pattern. 41 assertions pass here; 7 fail against the
round-2 tree, where the imported-session case resolves the writer to
`…/rigs/signal-loom/assets/scripts/gc-helm.sh` — a file that does not
exist.

## Files

| File | Change |
|---|---|
| `agents/converse/prompt.template.md` | Hold stamps the takeaway before waiting; close becomes sign-off-then-close; cut-short routes through it; a "The reap" rule states what can end the thread without the agent; both takeaway blocks (and the `bead-rehome.sh` pointer) search the candidate roots for their writer instead of assuming one path. |
| `agents/converse/agent.toml` | Corrects the false "timeouts do not end a sitting" comment; records the real mechanism and why longevity is not the fix. |
| `assets/scripts/gc-helm.sh` | Usage only: documents `--by converse` and the two-stamps-per-sitting caller. |
| `docs/gascity-human-engagement.md` | New "How a held sitting ends" section — the verified mechanism, the seam, and the unbuilt core seam. |
| `assets/scripts/converse-signoff.test.sh` | New regression test. |
