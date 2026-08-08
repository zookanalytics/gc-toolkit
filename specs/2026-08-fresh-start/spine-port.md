---
name: Decision record — conversation-spine port (increment 2)
description: The decisions made porting the quarry's reviewed converse+turn realization onto the fresh-start branch as native pack assets — names, claim/drain idiom, the recycle-guard deferral, and one flagged deviation from the ratified tk-h9pq5 design (no reaper-skip clause) — plus what remains runtime-unproven and the optional single-command check that would prove it.
---

# Decision record: conversation-spine port

Ported: `agents/converse/` (agent.toml, prompt.template.md, PROVENANCE.md)
and `formulas/mol-turn.toml`, from the quarry branch's reviewed
realization, per the ratified design `specs/tk-h9pq5/design-doc.md`.
Statuses per the working contract: **D-entries are the porting agent's
decisions**, open to operator reaction; none is an operator ruling.

## D1 — Names: `converse`, `mol-turn`

New things get names once, deliberately (operator rule: same *thing*
keeps its name; these never shipped on main, so they are new things).
`converse` is kept from the quarry because it is descriptive and the
thing is the same thing the quarry reviewed; every provisional
`nx-`/`gc-next` string is stripped (`mol-nx-turn` → `mol-turn`, binding
`gc-next.` → `gc-toolkit.`, work_dir `nx-converse` → `converse`). The
quarry's role names were flagged as baked-in provisional debt; this port
is where they revert to plain pack-native names.

## D2 — Claim/drain idiom: `gc hook --claim --json` + `gc runtime drain-ack`

The prompt keeps claim-only discovery via `gc hook --claim --json` (a
live core flag, documented in docs/gascity-agents.md) and makes the drain
verb explicit with main's idiom `gc runtime drain-ack` (the quarry prompt
said "drain" without a command). The role *tracks the semantics* of
upstream's `gc-role-worker` contract — empty continuation group after
close is a hard session boundary; a successful claim is authoritative
even across groups — without importing the roles pack, per tk-h9pq5 Q5
(revisit the import when role variants multiply).

## D3 — Recycle guard replaced by a marker-free stewardship clause

The quarry version checked a `.nx-recycle-now` marker set by a staged
Stop hook that main does not stage for this role. Rather than port that
infrastructure, the prompt carries the behavior contract directly: on low
context mid-hold, record the outcome-so-far to the subject, close the
turn honestly, drain. Turn boundaries — not recycling — are the release
valve by design; if lived holds prove long enough to exhaust context
mid-turn, extending `overlays/cycle-recycle/` to converse is the
follow-up, not a prerequisite.

## D4 — **Deviation from tk-h9pq5 Phase 2: no reaper-skip clause** ⚠

The ratified design says the witness orphan-recovery must structurally
skip `task_kind=conversation` beads so a parked turn is not reaped. The
port deliberately does **not** add that clause, on two pieces of
evidence:

1. **Main's recovery is liveness-keyed, with no time threshold**
   (verified in `formulas/mol-witness-patrol.toml`, recover-orphaned-beads:
   the filter keeps only *assigned* beads, and the per-bead loop recovers
   only beads whose assignee resolves *dead*). A held turn — assigned to
   a live converse session — is already structurally unreachable by
   recovery. The design's Q1 assumed a threshold reaper that does not
   exist here; trial finding B2 independently showed the skip clause is
   never reached during a live hold.
2. **For a turn whose session died mid-hold, recovery is the cold
   path, not a hazard.** Recovery returns the turn to
   open/unassigned/still-routed; pool demand respawns converse; the
   fresh session reconstitutes from the subject's record. Skipping
   conversations would *strand* died-mid-hold turns as permanently
   assigned to dead sessions — breaking exactly the continuity the
   design wants. (v1's bead-host needed the skip because hosts had
   resume semantics owned by other tooling; v2 turns are ordinary pool
   work and want ordinary recovery.)

`task_kind=conversation` is still stamped — as legibility for the board
and any future patrol — but nothing skips on it. If tk-h9pq5 is next
revised, Q1's resolution should be rewritten to this ground truth.

## D5 — No `work_query` override

Converse relies on the default routed-pool demand predicate (the
polecat-codex shape), unlike proactive's gated/clamped query: converse
has no enable-gate and no shed-clamp; a filed turn *is* the demand, and
`max_active_sessions = 2` bounds concurrent holds.

## Runtime-unproven (the honest remainder)

Everything above is contract-and-config; two things only a running city
can prove, per tk-h9pq5's own plan:

- **Phase 0:** a pool-spawned session self-renaming on claim.
- **Phase 1 gate:** the five assertions (spawn-on-file, subject-slice
  hold, record-then-close-turn-only, warm vacuum, cold reconstitution).

The optional single-command check, for whenever the operator cares to
run it in either city with this branch checked out on the rig (paste the
output back; that is the entire ask):

```sh
gc sling <rig>/gc-toolkit.converse mol-turn --formula \
  --var subject=<any-real-bead-id> --var visit="spine smoke test: say hi and hold"
```

A session should spawn with no further keystroke, title itself to the
subject, and hold. Anything else is a finding.
