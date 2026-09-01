---
name: Layout stability — nothing leaves the operator's view without an explicit act
description: What was built for tk-ghlg1e on both surfaces (the helm board's DONE band and the converse pane's idle reap), the bound each half accepts and why, and the evaluation of decoupling pane lifetime from session lifetime, which is upstream work and is filed there rather than patched here.
---

# Layout stability: board and tmux

Work record for `tk-ghlg1e`, filed from the 2026-08 cutover runbook
(`specs/2026-08-rewrite/cutover-runbook.md`, step 9 item 6).

The rule the operator stated is one sentence: an item they are looking at
must not disappear on its own. Sinking is acceptable, vanishing is not.
Two surfaces broke it in the same shape and for unrelated reasons, which
is why one bead carries both.

## The two instances

**The board.** Anchors are gathered as open beads. When an anchor closed,
the next gather did not return it and its row was not rendered. From the
operator's side that is indistinguishable from a row that was never
there, on the one surface whose job is to say what still wants a human.
The row disappeared at exactly the moment it was answered.

**The pane.** A held converse sitting was collected by `idle_timeout`,
which is measured from terminal output. Reading produces no output, so
eight hours of sustained attention and eight hours of abandonment were
the same measurement. The kill clears the scrollback and `wake_mode =
"fresh"` respawns clean, so the thread was destroyed rather than hidden.
That mechanism is recorded in `docs/gascity-human-engagement.md` and was
the subject of `tk-bzm86`, which fixed the *trace* and deliberately left
the clock alone.

## What was built

### Board: the DONE band

A closed anchor now keeps a row. It bands `DONE`, which sorts below every
live band, and `gc-helm dismiss <id>` takes it off the board on the
operator's word. What bounds the band itself is a separate question,
answered below.

- `board.SevDone` ranks `-1`, so the whole band lands at or below `-1`
  while the quietest live row floors at `0`. The four existing band ranks
  are unchanged, so no live row's `rank_score` moved.
- Inside the band the order is recency, not weight. Blast radius and
  staleness rank rows by how badly they want a human, and a closed row
  wants nothing. The row the operator just watched close is the one they
  are looking for, so it sits at the top.
- `CapRows` gained a third budget. The band sorts last, so a shared
  budget would drop all of it first, and these are the rows that were
  about to disappear on their own.
- The gather runs a second pass at status closed, bounded by
  `ClosedAfter`.
- The band belongs to the surfaces that answer *what is the city doing*:
  the dashboard, and `helm-svc board --all`. The CLI's default view is
  the operator's queue, which lists what a person owes, and a closed
  anchor is never `owed`. That queue is ordered by how long each row has
  waited, so admitting one would put a finished row above every live
  demand — the opposite of the floor the band is built on. The row
  sinks; it does not lead. The tmux picker reads the same queue and
  switches the band off outright.

### Board: what bounds the band

Two bounds, and they are not the same kind of thing.

`gc.dismissed_at` is the explicit one. It is written by `gc-helm
dismiss`, and it is the only thing that removes a row the operator can
see. The gather reads it on the closed pass alone, and that gate is
load-bearing rather than an optimisation: a dismissed anchor that is
later reopened is live work again, and applying the marker to the open
pass would hide that row from the live board.

`GC_HELM_DONE_WINDOW` (default 7 days) is the other, and it is an
honest compromise rather than a clean application of the rule. Some
bound is unavoidable: this city's ledger holds several hundred closed
anchors, the operator's own picker asks for 36 rows, and an unbounded
pass would bury the live board under years of finished work, which is a
different way of losing their view. So the guarantee the window buys is
the one that was actually broken. **A row does not vanish because it
closed.** It does age out of the band a week later, on a clock, and that
much is a knowing exception to the rule. `0` turns the band off
entirely.

If the exception turns out to matter, the fix is not a longer window. It
is to record on the bead that a row was rendered while closed, and to
retire it on the dismiss alone. That is state the gather does not have
today and would have to start writing.

Every surface that describes the band says so: the terminal legend, the
web section's copy, and `services/helm/README.md`. The first two said
instead that nothing left the board on its own, which is the guarantee
the window does not keep — copy an operator would read as licence to
stop looking for a row that had aged out. Both now state the clock, and
both are asserted, so the promise cannot drift back without a test
failing. `docs/gascity-agents.md` is not on that list: it does not
describe the helm board at all, so there is no claim there to keep
honest.

### Tmux: the clock is off

`agents/converse/agent.toml` sets `idle_timeout = "0"`. A template whose
idle timeout is at or below zero is never registered with the idle
tracker (`buildIdleTracker`, `cmd/gc/cmd_start.go`), `checkIdle` answers
false without reading activity at all, and `DecideIdleTimeout` is never
reached. A held sitting now ends when its visit closes: the agent's own
sign-off, or the operator's dismiss.

Three things this does not do, all of them still live:

- A sitting that has **ended** is still collected about a minute later by
  the `no-wake-reason` drain. Different clock, different path, unaffected
  by any idle setting.
- `DecideMaxSessionAge` still fires regardless of who is holding.
- A crash or a city restart still takes the pane.

So the trace-before-you-wait discipline `tk-bzm86` built is unchanged,
and the prompt still says so. What changed is which endings it is
defending against.

### Tmux: the cost, and the release valve

A held visit nobody answers now holds its slot against
`max_active_sessions = 6` indefinitely. The 8h clock used to recycle it.

`gc-helm dismiss <bead-id>` is the release. It closes the subject's open
visit, which ends the sitting, and stamps `gc.dismissed_at`, which clears
the board row. One verb, because from the operator's side it is one act:
"I am done with this."

Both halves land or neither is recorded. The visit half runs first, and a
sitting it could not account for aborts the stamp: the row stays on the
board and the run exits 4. Two failures reach that arm — a close bd
refused even with `--force`, and a visit lookup that did not answer,
which is not the same as a subject with no visit. The row is the only
evidence the operator has that a sitting is still up, so retiring it over
a live one is precisely the disappearance this bead exists to prevent,
reached from the other direction.

The visit close escalates to `--force` after a plain close is refused.
bd's close-authority guard refuses a close by anyone but the assignee,
and the assignee is the converse session being dismissed. That guard is
what this verb exists to override. `gc bd close` accepts `--force`;
`gc bd update` does not.

The lookup is pinned at the subject's rig before it runs. `bd list`
reads whatever `BEADS_DIR` names, which in an agent session is that
agent's own rig, so an unpinned lookup on a cross-rig subject searches
the wrong ledger, finds no visit, and reports a sitting ended whose pane
is still up. The subject `show` is deliberately left unpinned, the way
`open` leaves it: it resolves across ledgers on its own.

The tmux picker asks for no `DONE` band (`GC_HELM_DONE_WINDOW=0`). It is
not a view the operator leaves open, its one action is `open`, and its
hotkey alphabet is 36 rows the title bar promises to things that need
them.

## Evaluation: decoupling pane lifetime from session lifetime

The runbook asks for this to be evaluated through the upstream ladder,
naming it a gascity local-patch candidate. Verified against the gascity
rig checkout at `6a013fc27` (2026-08-26).

**The coupling.** `Provider.Stop`
(`internal/runtime/tmux/adapter.go`) calls
`KillSessionWithProcessesExcluding`
(`internal/runtime/tmux/tmux.go:922`), which terminates the pane's
process tree and then calls `t.KillSession(name)` unconditionally. The
tmux session, its pane and its scrollback are destroyed as part of
stopping the agent. `ClearScrollback` is a red herring here: it has
exactly two callers, the max-session-age and idle-timeout stop arms of
the reconciler (`cmd/gc/session_reconciler.go:3319` and `:3467`), and
neither is on the `no-wake-reason` path. That path does not need to
clear anything, because the destruction is total.

**Why the pack cannot do it.** The kill is core's. There is no pre-stop
hook, no shutdown formula, and nothing pack-owned runs at kill time.
Every lever the pack holds is config, and config can only choose which
clock fires, not what the kill does.

**The shape worth proposing.** Stopping an agent should retire its tmux
session rather than destroy it: rename it out of the addressable
namespace (`<name>.ended-<ts>`), leave the pane and its scrollback
intact with no live process, and exclude it from the awake set and from
`gc session` addressing. The operator's client stays attached to what
they were reading. The retired pane is reaped on an explicit act, or on
a TTL that is a memory bound rather than an attention policy.

**Why that shape and not simply "do not kill".** A surviving session
under its original name stays addressable, so `gc session nudge` would
type into a shell with no agent behind it, and the reconciler's
`wake_mode = "fresh"` respawn would either reuse a dirty pane or collide
on the name. Renaming is what makes the pane a corpse the operator can
read rather than an agent the city thinks is alive.

**Recommendation: file upstream, do not local-patch.** The fork's
discipline is upstream-first, and this is a runtime behavior change with
no pack-side approximation. The precedent is `gc-rjtk1`, the attachment
rung, which was filed cross-rig and merged upstream rather than
approximated in the pack.

Filed as `gc-f5cz9` against the gascity rig. It is adjacent to but
distinct from `gc-ze774`, which is a prohibition on tearing down a
session that holds unsubmitted operator input. `gc-ze774` protects what
the operator has typed and not sent; this protects what they have read
and not finished with. A retired pane would make `gc-ze774`'s loss
recoverable, and would not make its prohibition unnecessary.

## Regression

- `services/helm/internal/board/derive_test.go`: the band, its ordering,
  the lane bound, and the three cap budgets.
- `services/helm/internal/source/beads_test.go`: the closed pass, the
  window bound, the dismiss marker, a dismissed anchor that reopened,
  and the opt-out. The fake store was tightened to apply the status and
  close-time predicates and to refuse an unbounded closed query, because
  a fake that ignored them would let the done pass re-return every open
  anchor and test green.
- `services/helm/cmd/helm-svc/board_render_test.go`: the terminal
  table's half of the band — the split header count, the row, the legend
  line naming the verb that clears it, and the legend stating the window
  bound rather than promising an unbounded band.
- `services/helm/web/src/App.test.tsx`: the section, the same bound in
  its copy, and a closed `parked` subject staying out of the section
  that promises its rows are resumable.
- `assets/scripts/gc-helm.test.sh`: both halves of `dismiss`, the force
  escalation, the tracks-edge match, the cross-rig pin, idempotence, and
  the fail-closed arms — including the two that abort the row half, an
  unclosable visit and an unanswered lookup. The `gc` stub models bd's
  close-authority guard, a store that will not answer, and records which
  store each `bd list` read.
- `assets/scripts/converse-signoff.test.sh`: the `idle_timeout` value
  itself. It is a single config field with nothing else guarding it,
  which is the shape that gets tidied back to a plausible-looking `8h`.

Every guard above was mutated out and the matching assertion required to
fail before it was kept.

## What is not verified live

`helm-svc board` could not be smoked against this city. The beads
library pinned in `services/helm/go.mod` knows schema v65 and every rig
store is at v66, so the gather refuses before reading anything. That
skew is on `main` — this branch does not touch `go.mod` — and it is why
the terminal renderer is covered by a Go test over a hand-built board
rather than by a live run. The config half is source-verified instead:
`idle_timeout = "0"` parses (`durationOr`), passes the agent duration
validator, which checks parseability rather than positivity, and drops
the template from `buildIdleTracker`'s registration. Nine other agents
still set a timeout, so the tracker is still built and only converse is
exempt.
