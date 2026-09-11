---
name: Auto-open a converse for live operator intake, with an idle-recycle guard — tk-9ntg93
description: Why a live prefix+a topic now opens a converse automatically and how a never-attended auto-open is reclaimed without a gascity core change. The design record for converse-auto-open and converse-idle-recycle.
---

# Auto-open for live operator intake, with an idle-recycle guard

Bead: `tk-9ntg93`. Deliverables: `assets/scripts/converse-auto-open.sh`,
`assets/scripts/converse-idle-recycle.sh` + `orders/converse-idle-recycle.toml`,
the `gc-visit-open.sh` and `formulas/mol-first-reaction.toml` hook points (+ their
co-located tests). Doctrine home: `docs/gascity-human-engagement.md`.

## The gap

After the converse routed-pool was retired (d407b8c3, spawn-on-engagement), an
operator prefix+a topic filed a visit that parked on the helm board and advanced
only by a manual `gc-helm engage`. Nothing opened it and nothing announced it, so
operator-commissioned topics sat invisibly — the "black hole" (tk-jr8rw).

## Auto-open, and why the discriminator is a one-shot marker

The force-to-visit invariant (`first-reaction-dispose.sh`, tk-diqxx9) is correct
and stays: every operator-origin subject reaches a visit. This completes that
visit by spawning its sitting (`gc-helm engage <visit> --no-attach`, the board
picker's own spawn); it does not bypass it.

The hard constraint is scope: auto-open must fire for a LIVE keystroke and never
for a scan re-reacting a stale operator subject (that would spawn a converse with
no human present — the volume that retired the pool). `gc.origin=operator` cannot
discriminate: it is permanent and rides every operator subject, stale ones
included. So `gc-visit-open` arms a separate marker, `gc.interactive_intake`, only
at the keystroke, and `converse-auto-open` **consumes it on read** — one shot.
A replayed or scan-driven reaction finds nothing to arm and parks the visit
exactly as before. The marker is read/consumed before any branch, so the arming
is spent at the live moment regardless of what the cap or engage then decide;
every uncertain path ends with the visit parked, never with a headless auto-open.

Both intake paths call the one action: the react path from mol-first-reaction's
ruling step (after the visit is filed), the fallback from `gc-visit-open` directly.

## The idle-recycle guard, and why no core change

A never-attended auto-open is speculative and must not hold a session slot
forever. converse carries `idle_timeout="0"` and `origin=manual`, so the runtime
recycles nothing; `converse-reap` ends a sitting whose visit has CLOSED. This is
the half that spec named out of scope and deferred to **tk-20rfkt**
(`specs/tk-2i4bde/converse-reap.md`): a visit still OPEN that was never attended.
That spec flagged the blocker — *idle time cannot tell a never-attended sitting
from a live hold, which is why `idle_timeout="0"`* — and the resolution here is to
use a different discriminator: **attachment, not idle time.**

The pack has only the live `.attached` boolean from `gc session list`; there is
no was-ever-attached history anywhere, and no `gc-helm attach` verb to hook (attach
is plain `gc session attach`). Rather than add that history to gascity core — the
Principle-1 fallback the bead said to flag, not build — **the sweep is the
history**: `converse-idle-recycle` runs on a cadence, and the first pass that sees
an auto-opened sitting `.attached` stamps `gc.auto_open_attended_at` on its visit,
promoting it to a normal held sitting for good; a later detach never re-arms the
reclaim. A sitting that ages past the budget without that stamp is reclaimed. No
core change was required.

Reclaim **re-parks** rather than dismisses: it closes the session (frees the slot)
and returns the visit to open/unassigned with `gc.routed_to=human` kept (the board
predicate) and the auto-open marks cleared — mirroring converse-claim's proven
release ordering. The conversation was never had, so the topic stays on the board
for a later engage; it is not closed.

Two hard rules inherited from converse-reap: never touch an attached sitting (the
pack cannot see typed text, and draining a pane that has some is the operator's one
hard no), and an unreadable probe reclaims nothing.

## Config

Env var + safe default + numeric validation (the `liveness-sweep.sh` pattern),
per-rig variation (Principle 2):

- `CONVERSE_AUTO_OPEN_CAP` (default 2) — bounds concurrent speculative (not-yet-
  attended) auto-opens in the subject's rig, counted as a single open-only bead
  query on `gc.auto_opened`. Past it, the visit parks instead of auto-opening.
- `CONVERSE_AUTO_OPEN_RECYCLE_SECS` (default 900) — the idle budget before reclaim,
  read by the sweep; city-wide default in the order's `[order.env]`.

Per-rig override of a custom exec-order threshold beyond env/defaults is not wired
in this pack today (`[order.env]` serves every registration identically; only
interval/timeout/enabled are shown overridable in `city.toml`). The safe defaults
stand regardless; richer per-rig override is a gascity concern, out of scope here.

## Marker lifecycle

| Key | Bead | Set by | Cleared by |
|---|---|---|---|
| `gc.interactive_intake` | subject | gc-visit-open (keystroke) | converse-auto-open (consumed one-shot) |
| `gc.auto_opened` / `gc.auto_opened_at` | visit | converse-auto-open (after a successful engage) | converse-idle-recycle (on reclaim) |
| `gc.auto_open_attended_at` | visit | converse-idle-recycle (first observed attach) | — (promotion is permanent) |
