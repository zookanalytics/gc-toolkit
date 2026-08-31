---
name: Review gates — triage scan + dedicated small-context reviewers
description: Scope for adding an architectural review (and future dedicated reviews) as named gates, dispatched by a small-context triage agent that widens each anchor's check_set from a charter-declared menu. Design settled 2026-08-24; implementation is a follow-up to the rewrite PR, not part of it.
---

# Review gates: triage scan + dedicated reviewers

Status: **scoped, not implemented**. Implement after the rewrite PR lands.

## The idea

Two kinds of reviewer, both ordinary review-pool sessions, both small-context
and fully independent of the authoring session:

1. **Triage** (`check.triage`) — a broad, cheap scan that does not judge the
   change; it decides *which dedicated reviews apply* and records that
   decision by widening the anchor's `check_set` from a declared menu.
2. **Dedicated reviewers** (`check.arch` first; `security`, `perf`,
   `data-migration`, `demo`, … later) — each reads exactly three things: the
   repo's **charter**, the review bead, and the diff. Never the whole repo.
   The `demo` gate is triage-decided like any other: "does this change
   warrant a recorded demo (new or updated)?"; when added, a review session
   produces it via `skills/gc-demo-script` + `skills/demo-capture` and the
   verdict is the artifact recorded on the anchor — contained, reviewable,
   auditable (operator decision 2026-08-24, item 9).

Both ride the existing gate machinery unchanged: gate-ensure dispatches any
named gate, signoff.sh writes the verdict evidence-bound to the reviewed
commit, merge.sh requires every declared gate green at the live head.

## Why small context works

The enabling artifact is the **charter**: a few-KB per-repo distillation of
the architecture contract a reviewer holds the diff against. For gc-toolkit
it is mostly extant — component-model.md §5 (the admission test: a component
answers "cost of not having it"; a state names its handler; a metadata key is
declared; an invariant names its check) plus architecture.md's layer map.
A missing or stale charter is the reviewer's first finding, filed as a
`task_kind=observation` into the learning loop — the charter is forced into
existence by the review that needs it.

## Flow

```
handoff → gate-ensure stamps default check_set = codex,triage
        → dispatches triage review bead (reviewed_oid pinned)
triage session: charter + diffstat + skim
        → signoff.sh --verdict approve --add-gates arch[,security…]
        → check_set now codex,triage,arch…; check.triage=green@<oid>
next cadence pass: gate-ensure dispatches the added gates
arch session: charter + bead + diff
        → approve            → check.arch=green@<oid>
        → request-changes    → rework child, marker cleared
        → escalate           → check.arch=exception@<oid> + visit
merge.sh: unchanged — merges when every declared gate is green@live head
```

## Rules that make it safe

- **Monotonic widening — and triage is the sole narrower.** `--add-gates`
  performs a set-union write with read-back; no dispatcher, formula, or
  reviewer may pre-set or shrink `check_set` (operator ruling 2026-08-24:
  the checks-needed decision lives in one contained, reviewable, auditable
  place). The only sanctioned narrowing is a triage **waiver**: for gates the
  charter explicitly marks waivable (and only those), triage may record
  "not needed" with a one-line justification on the anchor. Waivers are
  expected to be rare and the distiller watches their rate alongside the
  add-rate. `none` stays a human-only opt-out.
- **Head-bound triage.** The triage verdict is `green@<oid>` like any gate; a
  push re-stales it, so a grown diff is re-classified.
- **Closed menu, justified adds.** The charter declares the gate menu (name →
  when it applies → method skill). Triage is a classifier over that table and
  appends a one-line justification per added gate to the anchor's notes. The
  feedback distiller watches the add-rate for gate inflation.
- **Mechanical backstop for misses.** The charter may declare mandatory rows
  ("diff touches `services/helm/**` ⇒ `arch`"). One clause in
  `doctor/check-gate-integrity` asserts open anchors honor them.
- **Design questions escalate, defects loop.** An architectural objection is
  usually a decision, not a defect: `--verdict escalate` writes
  `exception@<head>` and files a visit framing the choice (G2), instead of
  ping-ponging rework children (the reviewer-fatigue anti-pattern
  foundation.md forbids).
- **`codex` is not waivable before the PR exists.** `pr-open.sh` requires
  `check.codex=green@<live head>` by literal name and never reads `check_set`,
  so a set that drops `codex` while the anchor is still at `pre_open_gate`
  strands it with nothing able to raise the marker pr-open waits on. The flow
  above runs triage at exactly that state, so codex staying always-on is what
  makes it safe there, not a preference about how much review is enough.

## Until triage lands

`check_set` is still calibrated by hand on the anchors that need it, and that
act is granted and bounded in
[docs/authority-map.md](../../docs/authority-map.md): a human, on a named
anchor, reason recorded in the anchor's notes, narrowing only once the PR is
open. That describes the interim only. Triage inherits the power when it
lands, and from that point the rules above are the contract: triage is the sole
narrower, its waiver reaches only the gates the charter marks waivable, and
`none` stays the human-only opt-out.

Two cases could look like a standing human narrowing path after that, and
neither is one. A missing charter leaves triage unable to widen the set, and a
human may still widen it by hand, because the rules reserve only narrowing to
triage. A narrowing the charter does not mark waivable is available to nobody.
The one move left to a human there is `none`, which the authority-map row
already grants.

## Implementation inventory (follow-up work)

| # | Artifact | Change |
|---|---|---|
| 1 | `docs/review-charter.md` | The charter: layer map pointer, admission-test pointer, the gate menu table (name / applies-when / method skill / mandatory paths). Declared format so tooling can parse the mandatory rows. |
| 2 | `skills/review-triage/SKILL.md` | Triage method: inputs, menu contract, monotonic-widen rule, justification requirement, when to add nothing (the expected common case). |
| 3 | `skills/arch-review/SKILL.md` | Arch method: charter-first reading order, the layer questions (healer-shaped? mechanical-in-formula? prose-carried design? past-mandate growth? admission test met?), escalate-vs-rework rule. |
| 4 | `assets/scripts/review-dispatch-body.sh` | METHOD bodies for `triage` and `arch` keyed on `check_name` (~30 lines). |
| 5 | `assets/scripts/signoff.sh` | `--add-gates g1,g2` (union write + read-back; triage method only) and `--verdict escalate` (exception@head + `escalate.sh` visit) (~40 lines, tests pinning monotonicity and the escalate path). |
| 6 | `assets/scripts/gate-ensure.sh` | Default check_set `codex` → `codex,triage`, env-tunable per rig. No other change — it already dispatches any named gate and pins `reviewed_oid`. |
| 7 | `doctor/check-gate-integrity` | One clause: anchors whose branch diff touches a charter-mandatory path carry the mandated gate (charter table + ledger + git; warn-only at first). |
| 8 | `docs/state-machine.md` | Gate table rows for `triage` and `arch`; the widening rule. |
| 9 | Tests | signoff monotonicity + escalate; gate-ensure triage round-trip (widened set dispatched next pass); charter-parse fixture for the doctor clause. |

No new lifecycle states, no new metadata keys (check_set and check.<g> are
existing registry entries), no new pools (polecat-codex serves both methods;
split later only if load or model choice demands it).

## Costs and open questions

- One extra cadence hop per anchor (triage → widened dispatch), ~60s + one
  small session. codex stays always-on; triage decides the rest — this is
  the proportionality answer: expensive reviews run only when indicated.
- Resolved (operator, 2026-08-24): dispatchers may NOT pre-set a narrower
  `check_set`; triage runs on everything and owns the waiver mechanism above.
  Mechanical formula-poured work gets its fast path from triage waiving
  quickly, not from routing around triage.
- Open: charter format for non-gc-toolkit rigs with no architecture docs —
  the triage skill's fallback is "add `arch` when the diff creates a file,
  crosses a top-level directory, or changes a public interface," plus the
  charter-gap observation.
- Open: where proactive/first-reaction sits in the workflow once triage
  exists — first-reaction is approximately triage-for-conversations, and may
  become the triage gate's front half. Decide during implementation.
