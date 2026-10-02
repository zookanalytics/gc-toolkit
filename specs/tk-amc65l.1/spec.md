---
name: engage --new-subject — create-and-engage a fresh conversation subject
description: Design record for gc-helm engage --new-subject (rig-aware create-and-engage in one gesture) and the gc.reaction_owned stand-down that keeps the async first-reaction worker from filing a second visit. Read when touching engage's new-subject path, the proactive scan/sling guard, or mol-first-reaction's advance-and-drain.
---

# engage --new-subject

## Problem

Starting a converse conversation required a bead to exist first: `gc-helm engage`
resolves a subject, files its visit, spawns a `converse-<model>` sitting, binds
it, and attaches — but it refuses a subject that does not resolve. So "the city
has an issue, we need to talk about something with no bead yet" had nothing to
name. The operator had to file a bead, then hunt for it to engage.

## Deliverable

`gc-helm engage --new-subject` files a fresh subject bead and engages it in one
gesture.

- **The positional argument is the subject TEXT** (the new bead's title), not an
  id. Absent `--reason`/`--template`, that text doubles as the visit's opener.
- **`--rig <name>` picks the rig** the subject is created in. This is the net-new
  capability: every other engage path derives the rig from the subject's id
  prefix, but a brand-new subject has no id yet, so the rig must be chosen. The
  subject is created in that rig's store (`gc bd create --db <rig>/.beads`) and
  the sitting spawns in that rig's converse pool (unchanged — engage already
  points `GC_DIR` at the subject's rig).
- **Interactive** (a TTY, or `GC_HELM_ASSUME_TTY`): prompts for rig, subject, and
  model. A lone converse-capable rig auto-selects. `--no-input` requires `--rig`.
- **`--subject` and `--new-subject` conflict** (one names an existing bead, the
  other creates one); `--rig` without `--new-subject` is refused (an existing
  subject's rig comes from its id).

After the pre-step (`engage_create_subject`) resolves the rig, obtains the title,
and creates the bead, it sets `$bead` to the new id and primes the opener; the
rest of `cmd_engage` runs unchanged, filing the ONE visit and engaging it.

## Correctness constraint: the live-intake stand-down

The created subject is operator-origin (`gc.origin=operator`), so the
force-to-visit invariant would route it to a visit — but engage files that one
visit itself. The async first-reaction / proactive worker must NOT file a second.

The subject is created MARKED `gc.reaction_owned=1`, set in the same
`gc bd create --metadata` write, so the proactive scan can never observe the
subject unmarked (the marker is born with the bead — no create-then-mark race).
Three gates read it, defense in depth:

1. **`tools/gc-proactive.sh` `scan_precision_filter`** drops a bead carrying
   `gc.reaction_owned`, the same way it drops one already reacted
   (`gc.proactive_reaction` / `gc.first_reaction`). This is the race-free primary
   gate: the scan never slings a first reaction at a live intake.
2. **`tools/gc-proactive.sh` `sling_first_reaction_guard`** refuses a marked bead
   as a no-op (read-only, like the existing already-reacted skip), so an explicit
   `gc-proactive sling` — or `gc-helm react`, which re-raises the skip as exit 5
   and files nothing — does not file a visit either.
3. **`formulas/mol-first-reaction.toml` advance-and-drain** carries an early
   stand-down, ahead of the exit blocks and the gate-visit create, mirroring the
   ALREADY-REACTED guard: if the subject is marked, it stamps
   `gc.proactive_reaction=1`, consumes the marker fail-closed, files no visit,
   closes the step, and drains. This is the backstop for a direct pour
   (`gc sling … --on mol-first-reaction`) that bypasses the scan and the guard.

The force-to-visit invariant is preserved, not relaxed: the subject still gets
exactly one operator-filed visit.

## The marker lifecycle and the salvage

The key names the bead's state — a live owner already owns reacting to it —
rather than the path that set it, so a reader meets the marker without first
learning the engage intake behind it. Any future setter that takes a bead's
reaction off the autonomous worker writes the same key.

The marker and its fail-closed consume are salvaged from the dropped branch
`polecat/tk-9ntg93 @ d82af132` (`gc-visit-open.sh` set the marker,
`converse-auto-open.sh` consumed it). There it meant "auto-open the visit after
first-reaction files it," and the fail-closed consume (unset, then read back,
proceed only once provably gone) stopped a headless replay from auto-opening
twice.

Here the marker's role changed: first-reaction must not run at all, because
engage handles the subject end-to-end. The fail-closed READ (positive-finding
only; an unreadable marker is not treated as present) and the fail-closed CONSUME
(unset, read back) are preserved. The consume fires only in gate 3 — the direct-
pour backstop; the primary gate (1) is a read-only drop, so in the common path
the marker simply lingers as a permanent exclusion, which is correct for an
operator-engaged subject.

### Why the consume stamps `gc.proactive_reaction=1`

Clearing `gc.reaction_owned` without a replacement would re-expose the
subject to the scan (gate 1 drops on that marker), and a later sweep would
re-react. So the stand-down stamps `gc.proactive_reaction=1` FIRST — the
permanent "a reaction completed" proof the scan and the sling guard already read
— then consumes the one-shot marker. The operator's interactive engage IS the
reaction, so marking it reacted is honest. The subject is not `routed_to=human`,
so a standalone `gc.proactive_reaction=1` is not a board row and creates no husk.
If the stamp fails, the consume is skipped and the marker is left in place, so
either marker keeps a sweep off the bead — no path files a second visit.

### The abort backstop: a created subject always gets its visit

`engage --new-subject` creates the subject before the gates that can still refuse
the live engage — an unknown `--model` or `--template`, a suspended or not-running
rig, a store read that will not confirm the bead. A created operator-origin
subject owes exactly one visit, and nothing downstream supplies it on an abort:
the scan drops a marked bead, and even unmarked a first reaction does not force a
visit for `gc.origin=operator` (its actionable/blocked/close exits file none). So
`engage_create_subject` arms an EXIT backstop the instant the subject exists, and
on any abort before the visit is filed the backstop files that one parked visit
itself — through the same `cmd_open` the happy path uses, so it parks on the board
and dedups. The marker is left set, exactly as a successful engage leaves it, so
the async worker still stands down. The live engage is best-effort over a durable
subject-plus-visit: when the spawn cannot proceed, the visit is on the board for
the operator to engage once the blocker is cleared. Revoking the marker to hand
the subject to first-reaction recovery is not enough, because that recovery does
not file the owed visit.

## Deliberate choices

- **Atomic marker-at-create** (`gc bd create --metadata`) rather than
  create-then-update: it removes the window in which the scan could see the
  subject unmarked.
- **No dispose-side guard.** The Explore of the invariant noted
  `first-reaction-dispose.sh` as a possible belt-and-suspenders site, but the
  formula early-check `exit 0`s before any exit block, so dispose never runs for
  a marked subject. A guard there would be dead code.
- **prefix+A uses `--no-attach`.** The keybinding opens engage's real interactive
  prompt in a new window (tmux's one-line command-prompt cannot carry a subject
  plus a menu); it spawns with `--no-attach`, matching the operator's habit of
  cycling to the sitting from prefix+S, consistent with prefix+b. The keybinding
  is additive over the CLI.

## Out of scope (dropped with tk-9ntg93)

The operator ruled the auto-open-on-first-reaction trigger and the idle-recycle
subsystem dropped. This bead reintroduces none of it: no `converse-auto-open.sh`,
no `converse-idle-recycle.sh`, no `orders/converse-idle-recycle.toml`, no
`mol-first-reaction.toml` auto-open block, and no gascity `last_attached`
surfacing (tk-8cozf7). An operator-gated, one-per-gesture engage removes the
automation volume that forced the fragile never-attended recycle guard, so the
never-attended failure cannot occur by construction. A future dormant-engage
cleanup, if ever needed, keys on inactivity (`last_active`), never on
attach-detection — file it separately.
