---
name: Reap a converse sitting once its visit has closed — tk-2i4bde
description: Why a settled converse sitting leaks its session slot after the cutover to manual sessions, and the unattached-only reap cadence that ends it. The design record for the converse-reap order.
---

# Reap a converse sitting once its visit has closed

Bead: `tk-2i4bde`. Deliverable: `orders/converse-reap.toml` +
`assets/scripts/converse-reap.sh` (+ its co-located test).

## The gap

Converse is spawn-on-engagement (`tk-4abhrt`): `gc-helm engage` runs
`gc session new converse-<model> --alias <visit> --no-attach`, which makes an
`origin=manual` session bound to a visit — the session's alias IS the visit id.
A manual session is exempt from every pool backstop, so nothing in the runtime
cycles it.

Both endings the converse config names close the VISIT, on the stated belief
that closing the visit ends the sitting:

- the agent's sign-off (`agents/converse/prompt.template.md`), and
- the operator's `gc-helm dismiss` (`assets/scripts/gc-helm.sh` `cmd_dismiss`,
  whose own comment reads "closing it here is the only act that ends a sitting
  the operator no longer wants").

Closing the visit does not close the session. Under the retired routed-pool a
session with no live visit had no wake reason and the runtime's `no-wake-reason`
drain collected the pane in about a minute; a manual session is outside that
path. So the session outlives its closed visit:

- It holds one of `max_active_sessions` slots (default 2). Two settled sittings
  starve converse city-wide.
- When the operator has walked away, a closed visit coexists with a live pane.
  Observed 2026-09-07 as session holding visit `tk-8nt4tt`: the visit closed at
  05:25Z, the operator kept engaging ~17h, and the sitting was still live when
  this bead was worked.

The operator's model is "I don't close conversations; they get reaped." The
config did not provide that reap. This bead is it.

## The fix: an unattached-only reap cadence

`orders/converse-reap.toml` (cooldown, 5m, city scope) runs
`assets/scripts/converse-reap.sh`: for every converse session that is not
already closed and is NOT attached, it resolves the bound visit from the
session's alias and closes the session (`gc session close`) when that visit
reads `closed` or no longer resolves. A visit still `open`/`in_progress` is a
live hold and is left alone.

"No longer resolves" is bd's not-found answer: `gc bd show` on a deleted or
purged id exits non-zero yet still prints an object whose `error` names no
matching issue, and the script reads stdout and exit status separately so that
signature survives to be classified as gone.

Fully mechanical — `gc session list`, one `gc bd show` per converse session,
`gc session close` for the settled ones. No agent, formula, or pool. Bias
throughout: only a readable `closed` visit or bd's not-found signature reaps;
every other outcome — a read that yields no JSON, an error that is not the
not-found one, an alias that is not a bead id, or a bound bead that is not a
visit — is left alone, so the pass only ends a sitting it can prove is settled.

### Why unattached-only

The bead calls a closed-visit session "unambiguously reapable." One standing
operator ruling narrows that in practice: *"draining a session with typed text
should be a hard no"* (`specs/tk-tufrw/teardown-input-loss.md`). The pack cannot
see a half-typed reply in the composer — that needs the runtime's
`InputAreaState` (`gc-ze774`), which is not shipped. Attachment is the only
signal the pack has for "someone is at this pane," so an attached sitting is left
for its own sign-off or a dismiss even when its visit already reads closed.

This is not a hole in the fix; it is the correct boundary. The observed
attached-with-closed-visit case is the agent closing the visit *prematurely*
while the operator is still engaged — a distinct agent-side problem captured as
operator feedback, not this reap's to correct. Reaping an attached pane there
would cut off a live conversation and risk unsent words. Once the operator
detaches, the next pass reaps it, which is exactly "reaped outside of me."

On this city one tmux client is switched between panes, so at most one session
reads attached at a time; every other settled sitting reads unattached and is
reaped. The reap of the currently-attached pane simply waits for it to be left.

## Boundaries

- **`tk-20rfkt`** (open, deferred) — the harder half: ending a sitting whose
  visit is still OPEN and the operator walked away before any sign-off. Idle
  time cannot tell that from a live hold, which is why `idle_timeout="0"`. This
  pass never touches an open visit.
- **`tk-qgrnq8`** — an OPEN held visit outliving its ~5-minute bead lease and
  being re-offered in a loop. Also an open-visit case; unrelated to this reap.

## Where it lives, and why the pack owns it

Manual converse sessions are *deliberately* exempt from runtime cycling
(`tk-4abhrt`), so "a converse session whose visit closed should be reaped" is a
converse-policy decision, and converse is a pack role. The pack already owns the
lifecycle verbs this completes — `engage` spawns, `dismiss`/sign-off close the
visit — so the reap belongs beside them. No `gc`-binary change is required:
`gc session list`, `gc bd show`, and `gc session close` are all existing verbs
(`gc session close` is already the engage-abort cleanup path in `gc-helm.sh`).

## Verification

- `assets/scripts/converse-reap.test.sh` — hermetic, stubbed `gc`. Asserts a
  closed visit and a gone visit are reaped — the closed visit recognised whether
  bd answers with an array or a single object, the gone visit against bd's real
  not-found answer (the not-found object returned with a non-zero exit) — a live
  hold is kept, an attached session is never closed even with a closed visit
  (the `tk-8nt4tt` shape), non-visit/no-alias/bad-alias/non-converse/
  already-closed sessions are left alone, the summary counts, the `--dry-run`
  plan, an unreadable listing aborting with exit 1, an unreadable visit and a
  non not-found visit failure both being skipped not reaped, and a close failure
  being reported without stopping the pass. Co-located per the `scratch-reap` /
  `worktree-reap` convention, so the review gate runs it adjacent to the diff.
- Live `--dry-run` at build time flagged the four unattached closed-visit
  sittings then leaking slots in the city, kept the two live holds, and excluded
  the one attached closed-visit session.
