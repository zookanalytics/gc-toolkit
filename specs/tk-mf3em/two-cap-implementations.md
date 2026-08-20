---
name: The convergence cap's two writers, and why one of them stopped writing
description: Why the signoff round cap's gate-marker clear was removed rather than made to agree, what the oscillation actually cost in production, and why R11 now defers to a stale exception. Read when changing the cap, R11, or anything that writes check.<gate>.
---

# The convergence cap's two writers (tk-mf3em)

Two independent implementations of one rule — "the remediation rounds are
spent" — wrote **opposite** terminal states to the same field, and which one
survived was decided by pass ordering rather than by design.

| Arm | Where | On cap |
|---|---|---|
| A | `formulas/mol-refinery-patrol.toml` (`merge-push`) and `template-fragments/polecat-non-impl-done.template.md` (`signoff-round-cap`) | `gc.routed_to=human`, `blocked_reason`, **`--unset-metadata check.<gate>`** |
| B | `assets/scripts/reconcile-gate-verdicts.sh` R11 | **`check.<gate>=exception@<head>`** + `.reason` + `.attempts` |

Both orderings were observed in production: su-uzy9.5 (2026-08-13) ended with
B's stamp 43s after A's clear; sl-ew4w / PR#533 (2026-08-19) ended with A's
clear over B's stamp, on a different rig.

## It was not a coin-flip — it oscillated once per wake

The framing on the filed bead ("whichever ran last") understates it. Within a
single patrol wake the order is fixed and both arms run:

```
find-work    →  check-set-heal.sh          (dispatches on an ABSENT marker)
             →  reconcile-gate-verdicts.sh (arm B: stamps exception@<head>)
merge-push   →  the cap arm                (arm A: cleared check.<gate>)
```

So every wake ended with the marker **absent**, and the next wake's
`check-set-heal.sh` read that as Unevaluated and dispatched another codex
review. The cap's whole purpose is to stop that dispatch; the clear re-armed
it. On sl-ew4w the loop ran at roughly the patrol cadence — a no-op review
about every 14 minutes (`sl-88w0u`, `sl-o8akz`, `sl-pv0md`, `sl-3bi4n`, each
`gc.work_outcome=no-op`) — while an APPROVED + CLEAN + MERGEABLE PR sat unable
to land for ~14h.

It also presented as a dead refinery. It was not: the idle driver was alive
and `merge-skill.sh` was holding correctly on a genuinely absent gate. That is
a diagnosis trap worth remembering, and it is why the fix is in code rather
than in an operator note.

## Why arm A stopped writing, rather than being taught to agree

Making A stamp `exception@<head>` too would have looked like agreement and
re-created the defect one level down: two writers of one field, each resolving
the live head its own way (pre-open off the branch, post-open off the PR), each
free to drift. `reconcile-gate-verdicts.sh` is already the documented verdict
arm — `check-set-heal.sh` defers to it by name for the unmappable case — so the
correction is to leave it as the single writer.

Three things had to be true for that to be safe, and all three are:

1. **The clear bought no safety.** `merge-skill.sh` holds on anything that is
   not `green@<live head>`, so an absent marker holds exactly as hard as a
   stale or non-green one.
2. **The condition is still recorded.** R11 stamps
   `exception@<head>` + `attempts-exhausted` reason on the next wake. The
   anchor's own state still says *why* it is held, which was the stated point
   of R11 in the first place.
3. **The clear could destroy a valid verdict.** `CODEX_GATE` is decided by
   `check_set` membership alone, so the cap arm is reached whenever the merge
   is held for *any* reason — including `check.codex=green@<live head>` with a
   different gate (`approval`) doing the holding. Unsetting there discards a
   green nobody asked to retract.

The sidecars are the tell that the clear was never coherent: it removed
`check.<gate>` but not `check.<gate>.reason` / `.exception_escalated`, leaving
sl-ew4w asserting that an exception had been escalated for a gate that was
never evaluated.

### What was deliberately *not* changed

The **under-cap** path in the polecat fragment (`signoff-rework-dispatch`)
still clears the marker, and must. There a rework child is in flight: the fix
will move the head, a fresh review has to run against it, and re-arming
`check-set-heal.sh` is exactly the intent. Past the cap nothing is coming,
which is what makes the same write a terminal verdict instead of a retraction.
`assets/scripts/signoff-round-cap.test.sh` pins both halves of that
distinction so an over-broad reading of this fix cannot delete the wrong one.

## The second-order finding, now reproduced

The filed bead flagged this as unverified. It is real, it is in both phases,
and the existing test suite had encoded the buggy behaviour as an expectation
(`(MOVED)`).

`check.<gate>.attempts` is deliberately **not** head-bound — a rework round
that does any work moves the head by construction, so a head-bound counter
would reset every round and the bound could never fire. The consequence nobody
had followed through: a count that never resets is past the cap at *every*
later head, so R11 sets `reason` on the wake that was supposed to re-arm the
gate. That `reason` skips the whole `[ -z "$reason" ]` block — which is where
**both** re-arms live:

- pre-open, the clear of a stale `green@`/`exception@` marker;
- post-open, simply leaving the marker stale so
  `reconcile-merged-prs.sh`'s stale-gate arm can read it as stale and dispatch
  a re-review.

Either way the head move is consumed and `exception` becomes terminal *full
stop* rather than terminal-until-operator — the escape
`specs/tk-zgse0.2/merge-gate-exception-lifecycle.md` promises in AE-WS4-2.

The fix is the guard R12b already carries for the identical shape, with the
identical argument: **R11 is suppressed while the marker is an exception bound
to an older head.** Suppressing only defers. The count is not reset, so a head
move buys one honest evaluation rather than a clean slate; when that round
closes the marker is `fixable@<new head>` or absent rather than a stale
exception, nothing suppresses R11, and the gate goes terminal at the new head.
Nothing loops, because past the cap no rework child is filed — only an
operator moves the head.

`(CAPBITE)` in `assets/scripts/reconcile-gate-verdicts.test.sh` is the control
that keeps the deferral from silently becoming a deletion of R11, the same way
`(CAPOPEN)`/`(CAPCLOSE)` do for the in-flight deferral.

## Verification

- `assets/scripts/reconcile-gate-verdicts.test.sh` — 110 assertions. Against
  the pre-change script the new `(MOVED)` / `(CAPREARM)` / `(CAPBITE)` arms
  fail 8, so they are not vacuous.
- `assets/scripts/signoff-round-cap.test.sh` — 26 assertions, extracting and
  **executing** both cap halves against a logging `gc` stub and asserting on
  the argv. Two controls were run: the pre-change files (extraction empty →
  the positive-control arms fail loudly rather than passing vacuously) and a
  mutant with the clear re-introduced into both halves (the `check.` arms
  fail, one per half).
- The other 17 suites that read the three changed files were run unchanged.
