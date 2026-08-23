---
name: Convergence record — the shared in-flight membership predicate and the anchor-owned round cap
description: What landed for tk-vie5k against the tk-j5wrs ruling, reader by reader, including the one place the ruling's wording could not be applied literally and why. Read before changing any membership guard or cap site.
---

# Convergence record — tk-vie5k

Implements the ruling on **tk-j5wrs** (operator, converse visit tk-9glgp,
2026-08-22). Branch `polecat/tk-vie5k`, cut at `2dcbcac`.

## What the ruling asked for, and where it landed

| Ruling | Landed as |
|---|---|
| 1. One shared membership predicate, with salvage as a CALLER (not a collapse of dispatch) | `# >>> inflight-membership`, canonical in `assets/scripts/check-set-heal.sh`, copied into three more readers |
| 2. `anchor_bead` is authoritative; the other three conventions documented in-file as non-canonical | `anchor_authority` in the block; in-file notes at `reconcile-gate-verdicts.sh` (blocks, parent-child) and `recover-stranded-branches.sh` (convoy) |
| 3. The round cap belongs to the ANCHOR | `# >>> signoff-round-cap` reworked to take `CAP_ANCHOR`, now in all four dispatchers |
| 4. The read-to-create race is DEFERRED | Recorded in the block's own comment, so the next reader does not re-litigate it. No locking added. |

Mechanism is the pack's existing one, not a new one: a marked block plus a
drift test, exactly as `formulas/mol-visit.toml` + `assets/scripts/gate-visit.test.sh`
do for `gate-visit`. `assets/scripts/inflight-membership.test.sh` extracts every
copy, diffs it against canonical, and EXECUTES it — the `signoff-round-cap.test.sh`
pattern, because a text grep passes on a block that says the right words and
computes the wrong answer.

## The five readers

1. **`check-set-heal.sh` `ACTING_JQ_DEF`** — became the canonical copy.
   `ACTING_JQ_DEF` survives as an alias so the sites naming it do not each pick
   up a second definition.
2. **`check-set-heal.sh` `inflight_for()`** — its inline `$ab == $a / $ab != ""`
   ladder now calls `anchor_authority`. Same truth table, one definition.
3. **`mol-refinery-patrol.toml` `EXISTING_REVIEW`** — the PRE-open arm already
   queried `anchor_bead`; the POST-open arm keyed on the PR number alone and
   trusted the first row. A PR number is shared by every anchor that ever gated
   the branch (that is why `one-anchor-per-pr-resolve` exists), so it now filters
   what the query returns through `anchor_authority`. Its `--limit=1` became
   `--limit=0`: filtering after a limit-1 query drops the right row.
4. **`reconcile-merged-prs.sh`** — both in-flight probes. `PROBE_ROW_JQ` carries
   `metadata.anchor_bead` in its original shape so `anchor_authority` reads a
   probe row exactly as it reads a whole bead; a projection is not a licence to
   write a second membership rule.
5. **`recover-stranded-branches.sh` `convoy_is_live()`** — see below.

## Where the ruling could not be applied literally

**Salvage needed `claimable`, not `acting`.** The bead names the defect as "a
molecule that is in_progress + routed + unclaimed reads as no landing path", and
the obvious fix — call `acting()` on the molecule root — is wrong in a way that
would have been catastrophic and silent: `acting()` also counts an owning STATUS,
and a graph.v2 root is `in_progress` from the pour until somebody closes it, which
nothing does. Every husk in the store would have read as live and salvage would
have gone permanently blind. Confirmed against the existing fixtures, which are
husks with `in_progress` roots — they all flipped to "live" on the first attempt.

So `acting()` was split into `claimable` (routed, or slung-and-unclaimed) and
`acting` (`claimable` OR a review OR an owning status), with no change to the
existing truth table. Salvage's clause is `claimable AND no assignee AND no
`gc.session_name``: a root stamps its session at claim time, so one that carries
a session HAS been claimed, and a husk keeps its route — clearing it is what
quiescing does. `(OFFER)` in `recover-stranded-branches.test.sh` pins both
directions, and `b-heldoffer` is the negative control: widen the clause to any
routed root and it stops being salvageable.

**A boundary deliberately not coded:** a husk the reconciler RE-OFFERS to the pool
still carries its dead session name and still reads as salvageable. That is the
pre-existing reading; tk-vie5k does not widen it.

## The cap

Sites 1 and 2 (`mol-refinery-patrol.toml`, `polecat-non-impl-done.template.md`)
already counted off the anchor and agreed. Site 3 (`reconcile-gate-verdicts.sh`
R11) counts **closed** children only, deliberately and with a long in-file
argument: an open child is a round IN FLIGHT, and counting it brings the cap
forward a whole round, converting a state a worker is actively fixing into a
TERMINAL exception. That divergence was left intact — converging it would regress
a documented safety property, and R11 is not a dispatcher.

What converged is the DISPATCHER-side count: one block, taking `CAP_ANCHOR`,
consumed by all four. Three of them had none before.

At the cap, a dispatcher **declines and says so**. It does not route the anchor to
a human and writes nothing under `check.<gate>` — R11 owns that verdict
(`signoff-cap-no-gate-write`), and a second writer of it is tk-mf3em returning
through a new door. With no new review the gate stays unsatisfied, so the merge
stays held: the safe side.

One ordering call worth naming: in `reconcile-merged-prs.sh` the cap sits AFTER
the stale-gate repair arm. A review that already exists and is merely unroutable
is repaired past the cap — the cap bounds new rounds, not the health of the round
already in flight, and refusing to repair would strand the one bead that could
still discharge the gate.

## Evidence

Every new assertion was checked against the unfixed code:

| Mutation | Effect |
|---|---|
| pending-offer clause removed from `convoy_is_live` | 3 fail (`OFFER` + both handoff censuses) |
| `anchor_authority` filter removed from the gate probe | 3 fail (`26b` + the run-8 census) |
| one character changed in one copy of the block | `DRIFT` fails for that file alone |

Suites after: inflight-membership 29, signoff-round-cap 30, check-set-heal 188,
recover-stranded-branches 116, reconcile-gate-verdicts 110, reconcile-merged-prs
411 — all green, from baselines of (n/a) 26 / 184 / 114 / 110 / 406.
`check-pipefail-grep-q` is unchanged at its three pre-existing findings.

## Out of scope, as the bead required

`tk-m5jfj`, `tk-plpm7`, `tk-rvspf`, `tk-hxd1e`, `tk-eh64m`, `tk-f8cxq`,
`tk-fkcol`. `tk-j5wrs` and `tk-gnrhr` are NOT closed by this work — the
`tk-gnrhr → tk-j5wrs` blocks edge is load-bearing and a later sitting disposes of
them in order.
