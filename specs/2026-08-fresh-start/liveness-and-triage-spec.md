---
name: Spec — the gate snippet, the liveness sweep, and triage recurrence
description: Implementation spec for the three pieces that realize P3 and the batched-triage design on common patterns — the canonical gate-turn snippet (marker-delimited, test-extracted), the unnamed-wait sweep (order + v1 formula that normalizes idle beads into turns), and triage-subject recurrence (order + formula filing a turn only when warranted) — plus the city-side adoption list and what stays out of scope.
---

# Spec: gate snippet · liveness sweep · triage recurrence

> **Vocabulary addendum (2026-08-08, post-green-light):** implemented as
> written, then renamed in the same PR by operator decision — "turn" is
> now **visit** throughout the live surfaces: `mol-turn.toml` →
> `mol-visit.toml`, `gate-turn` markers/test → `gate-visit`,
> `task_kind=conversation` → `task_kind=visit`. This spec is kept as the
> green-lit record; read its "turn"/"gate-turn" as "visit"/"gate-visit".

> **Sweep addendum (2026-08-08, operator review):** §2's per-bead
> normalization and epic exclusion are superseded in the implementation:
> normalization is **batched** (one standing "unnamed waits" triage
> subject per rig; one visit per pass listing all candidates — N idle
> beads cost one conversation, not N, per the P3 batching resolution),
> and the epic special-case is replaced by the type-agnostic
> **waiting-on-structure** class (open children or blockers = named
> wait; an epic with all children closed is a first-class unnamed wait
> needing a "what comes next?" exploration). The per-pass filing cap is
> superseded by a per-visit listing cap.

> **Recurrence addendum (2026-08-10, operator decision — visit su-aib6):**
> §3's ripeness pre-check is superseded in the implementation. The machine
> hint alone is not ripeness: the check is the hint **and** a set-delta
> against the candidate set the last filed visit was built from
> (`triage.last_seen` on the subject bead). Motivating case: a
> **park-shaped** subject — one whose scope matches exactly the beads
> parking puts into it, e.g. `label:parked-debt` — never drains, so a
> non-empty-scope test re-asks the same already-answered question every
> cooldown forever; three fired at once on 2026-08-10, each on a set
> unchanged from the day before. The gap §3 left is that ripeness was
> written for a subject triage moves beads OUT of; parks invert it (beads
> move in and stay), and they always carry a hint, so the "else" staleness
> arm never applied to them. The visit body now names which ids entered
> and which left. The delta is symmetric, so §3's "no candidates → no
> turn" holds only for a scope that was ALREADY empty: a subject whose
> recorded set was non-empty and now matches nothing files one final
> visit naming what left, then goes quiet. Deliberately still uncovered:
> a purely strategic change that moves no ids — the operator files that
> visit by hand.

Realizes P1–P4 ([operating-principles.md](operating-principles.md)) on
existing patterns only. Three repo pieces, one city-side list, one
explicitly deferred design. Vehicle per operator discussion: repo pieces
implement in this PR with their tests; city-side runs live, city idle.

## 1. The canonical gate-turn snippet

**What:** the four turn-filing lines plus the blocking edge — the gate
pattern's whole mechanical content:

```bash
# file a turn on <subject> and gate <blocked-bead> on it
POOL="${GC_RIG:+$GC_RIG/}gc-toolkit.converse"
TURN=$(gc bd create -t task --title "turn: <subject> — <visit>" -d "<visit>" --json | jq -r '.id // .[0].id')
gc bd update "$TURN" --set-metadata "gc.routed_to=$POOL" \
  --set-metadata "gc.continuation_group=<subject>" \
  --set-metadata "task_kind=conversation"
gc bd dep add "$TURN" "<subject>" --type=parent-child
gc bd dep add "$TURN" --blocks "<blocked-bead>"   # omit when nothing waits
```

**How it stays reusable without new machinery:** formula bodies are
plain string substitution (no include mechanism — a known trap), so the
pack's precedent applies: a **marker-delimited canonical copy**
(`# >>> gate-turn` / `# <<< gate-turn`) lives in `formulas/mol-turn.toml`
(the canonical spelling's home), consumers copy it, and a regression test
(`assets/scripts/gate-turn.test.sh`, the host-bead-skip pattern) extracts
the canonical copy, syntax-checks it, and asserts the known consumers'
copies match modulo their substitutions. Consumers at ship: `mol-turn`
itself, `mol-first-reaction` step 3, the sweep (§2), triage recurrence
(§3).

## 2. The liveness sweep (P3 enforcement)

**Home:** its own order + v1 formula (`orders/liveness-sweep.toml` →
`formulas/mol-liveness-sweep.toml`), not a witness-patrol step. Reasons:
the witness owns *session*-liveness (dead assignees); this sweep owns
*graph*-liveness (unnamed waits) — different failure classes, different
cadences (witness each cycle; sweep hourly-to-daily), and an 892-line
patrol should not grow a second mandate. Same fail-safe discipline
copied from witness: an unreadable listing aborts the cycle loudly —
never normalize on partial data.

**The classification (one jq pass over open beads, per rig):** every
open bead must be one of —

1. **worked** — assigned, or `gc.routed_to` non-empty (demand exists);
2. **gated** — an open blocking dependency, an open `type=human` gate,
   or gating-state markers (refinery sub-states count);
3. **conversing** — an open turn in its continuation group, or it *is*
   a turn;
4. **held-by-design** — `task_kind=triage-subject` beads and beads a
   triage scope covers (they wait on their triage conversation, §3);
5. **unnamed** — none of the above: the defect.

**The action:** for each unnamed bead, file **one** gate-turn on it
(canonical snippet; visit prompt: "unnamed wait: what is this waiting
on? Route it, gate it, or park it into a triage scope"), idempotent (no
second turn while one is open), capped per cycle (default 5, config
var) so a first run against a messy store produces a triage-able trickle
instead of a flood. Every filing logged to the sweep's own notes.
**Doctor check:** `check-liveness-sweep-wired` asserts the order exists,
enabled, and the formula parses — the sweep watches beads; the doctor
watches the sweep.

## 3. Triage recurrence

**The subject:** an ordinary bead, `task_kind=triage-subject`, body =
the scope in prose (authoritative, evaluated by the converse session at
turn time) plus one optional machine hint `triage.scope=<bd-ready
filter args>` for the cheap pre-check. Created in the city, not the
repo; near-disjoint scopes by operator convention.

**Recurrence:** `orders/triage-recurrence.toml` (daily cooldown,
per-rig) → `formulas/mol-triage-recurrence.toml` (v1, one step): for
each `task_kind=triage-subject` bead — skip if an open turn already
exists in its group; else run the cheap ripeness pre-check (the machine
hint if present, else "any held bead untouched since the last triage
turn closed"); if ripe, file the gate-turn ("triage visit: N candidates
look ripe — promote, park, or kill"). No candidates → no turn → no
board row: pull-only holds. *(Superseded — see the Recurrence addendum
above: the pre-check is the hint AND a set-delta against the last filed
visit, because a hint-only test nags park-shaped subjects forever.)* The
deep evaluation (which five, what
ranking) is the converse session's prep at turn time — the scope is the
lens, the chassis does the work.

## 4. City-side (live, city idle — the whole list)

1. Point the rig at this branch; `gc doctor` clean.
2. Spine smoke (spine-port.md's four raw lines): converse spawns,
   self-titles, holds → Phase 0/1 evidence.
3. Create 1–2 triage subjects (e.g. "triage: held ideas, gc-toolkit").
4. Enable both orders; watch one sweep cycle and one recurrence
   evaluation; react to what they file.
5. Optionally enable the P2 intake default (`GC_PROACTIVE_ENABLED=1`)
   now that first-reaction files turns.

Each step is one command plus observation; I write the exact runbook
when the repo pieces are merged-ready.

## Out of scope, deliberately

- **The build-factory ratification graft** — wrapping/patching another
  pack's v2 formula is its own design spike (wrap vs. fork vs. an
  upstream PR adding a gate hook to build-base; the third may be the
  right ecosystem move). Separate increment.
- **Board rendering of turns/gates as anchor kinds** — the board works
  without any of this (operator constraint); its turn-awareness is a
  later, additive change.
- **Retiring bead-host config** — orthogonal cleanup, its own small PR.
