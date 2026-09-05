---
name: Review gates — triage scan + dedicated small-context reviewers
description: Scope for adding an architectural review (and future dedicated reviews) as named gates, dispatched by a small-context triage agent that widens each anchor's check_set from a charter-declared menu. Design settled 2026-08-24; implementation is a follow-up to the rewrite PR, not part of it.
---

# Review gates: triage scan + dedicated reviewers

Status: **implemented, minus the convergence half.** The charter, the two
methods, the triage widening verbs and the widened default all landed; the
per-gate round accounting and the escalate verdict were carved out and are
retired by the review-cycle design that supersedes them. What landed and what
did not is under the inventory. The work-feeder half is designed, not
implemented — [work-feeder.md](work-feeder.md).

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
named gate, signoff.sh records the reviewed commit on the review bead and
stamps a bare `check.<gate>=green` that binds to no commit, and merge.sh
requires every declared gate's marker to read `green`. A marker is a state of
the lane, so an appended commit leaves it green and only a rewrite that drops
the reviewed commit off the branch supersedes the review; the live head is
guarded separately, by merge.sh's own PR merge guard.

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
        → check_set now codex,triage,arch…; check.triage=green
next cadence pass: gate-ensure dispatches the added gates
arch session: charter + bead + diff
        → approve            → check.arch=green
        → request-changes    → rework child, marker cleared
          (a design question → escalate.sh visit, then one of the two above)
merge.sh: unchanged — merges when every declared gate reads green
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
- **A lane-state marker, a commit-bound menu.** A gate marker is the bare value
  `check.<gate>=green`, a state of the lane rather than a value pinned to a
  commit. `reviewed_oid` on the review bead records the commit the reviewer read
  and binds no marker, so a push that only adds commits on top leaves the gate
  green. Only a rewrite that takes the reviewed commit off the branch supersedes
  the review: `signoff.sh` refuses a verdict whose `reviewed_oid` is no longer an
  ancestor of the head, closes the review bead, and lets gate-ensure pour a fresh
  review at the live head. The menu is bound to the commit instead: triage and
  `signoff.sh` both read `docs/review-charter.md` out of the reviewed commit
  rather than off a working tree, so a branch is classified and warranted against
  the menu it ships and a reviewer's own checkout supplies no menu at all.
- **Closed menu, justified adds.** The charter declares the gate menu (name →
  when it applies → method skill). Triage is a classifier over that table and
  appends a one-line justification per added gate to the anchor's notes. The
  feedback distiller watches the add-rate for gate inflation.
- **A mandatory row is a rule, not a backstop.** The charter may declare
  mandatory paths ("diff touches `services/helm/**` ⇒ `arch`"), and triage
  adds the gate whatever the applies-when column would have argued. Nothing
  re-derives the branch diff behind triage, so a miss is a gate the anchor
  never gets. That is why the declared list is short and holds only the paths
  where a wrong change is expensive.
- **Design questions go to a person, defects loop.** An architectural
  objection is usually a decision, not a defect. The reviewer files a visit
  with `escalate.sh --key arch-decision` framing the choice, then gives the
  verdict the diff itself earns and names the visit in the body:
  `request-changes` when the diff needs work whichever way the decision goes,
  `approve` when the change stands on its own. That keeps the question off
  the rework loop (the reviewer-fatigue anti-pattern foundation.md forbids)
  without a verdict that parks the gate. Parking the gate belongs to the
  round cap alone: `signoff.sh` parks the anchor under `merge_hold=signoff_cap`
  when a gate exhausts `GC_MAX_REVIEW_ROUNDS`, and routes it to a human in the
  same act.
  `skills/arch-review/SKILL.md` carries the shape.
- **`codex` is never waivable.** The charter's menu marks it so, and the
  waiver verb could not reach it in any case: `--waive-gates` records a
  non-add, and `signoff.sh` refuses it outright for a gate `check_set`
  already declares. Both transitions judge an anchor by that set alone.
  `pr-open.sh` publishes once every marker-bearing gate the set declares reads
  `green`, and `merge.sh` applies the same predicate, so a set that could drop
  `codex` would publish and merge with the correctness review never run. The
  flow above runs triage at `pre_open_gate`, which is exactly where that would
  happen, so codex staying always-on is what makes the publishing gate mean
  anything.

## Hand calibration

Before triage, `check_set` was calibrated by hand on the anchors that needed
it. [docs/authority-map.md](../../docs/authority-map.md) now carries the power
as two rows, widen and narrow, and triage holds the machine half of each: it
is the sole narrower, its waiver reaches only the gates the charter marks
waivable, and `none` stays the human-only opt-out, still on a named anchor,
still with the reason in that anchor's notes, still only once the PR is open.

Two cases could look like a standing human narrowing path, and neither is
one. A missing charter leaves a widening unvalidated rather than blocked:
`signoff.sh` warns and accepts `--add-gates`, because adding a gate is always
safe, and a human may widen by hand for the same reason. A narrowing the
charter does not mark waivable is available to nobody, and no charter at all
refuses every waiver outright. The one move left to a human there is `none`,
which the narrowing row grants.

## Implementation inventory (follow-up work)

| # | Artifact | Change |
|---|---|---|
| 1 | `docs/review-charter.md` | The charter: layer map pointer, admission-test pointer, the gate menu table (name / applies-when / method skill / mandatory paths). Declared format so tooling can parse the mandatory rows. |
| 2 | `skills/review-triage/SKILL.md` | Triage method: inputs, menu contract, monotonic-widen rule, justification requirement, when to add nothing (the expected common case). |
| 3 | `skills/arch-review/SKILL.md` | Arch method: charter-first reading order, the layer questions (healer-shaped? mechanical-in-formula? prose-carried design? past-mandate growth? admission test met?), escalate-vs-rework rule. |
| 4 | `assets/scripts/review-dispatch-body.sh` | METHOD bodies for `triage` and `arch` keyed on `check_name` (~30 lines). |
| 5 | `assets/scripts/signoff.sh` | `--add-gates g1,g2` (union write + read-back; triage method only), `--waive-gates`, `--justification`. The escalate verdict was designed here and dropped — see below. |
| 6 | `assets/scripts/gate-ensure.sh` | Default check_set `codex` → `codex,triage`, env-tunable per rig. No other change — it already dispatches any named gate and pins `reviewed_oid`. |
| 7 | `doctor/check-gate-integrity` | One clause: anchors whose branch diff touches a charter-mandatory path carry the mandated gate (charter table + ledger + git; warn-only at first). |
| 8 | `docs/state-machine.md` | Gate table rows for `triage` and `arch`; the widening rule. |
| 9 | Tests | signoff monotonicity and the waiver refusals; the charter parser; the gate-named dispatch body; one declared default agreed by the three files that name it, proved through the merge-push path that mints anchors. |

No new lifecycle states, no new metadata keys (check_set and check.<g> are
existing registry entries), no new pools (polecat-codex serves both methods;
split later only if load or model choice demands it).

### What landed, and what did not

Rows 1-6, 8 and 9 landed. Two pieces did not, and one row was answered
differently than written.

- **Row 7, the doctor clause, was dropped.** Its waiver keyed on a
  commit-pinned marker (`check.triage=green@<oid>`), and this design records
  markers as bare lane states with no oid binding for it to key on. A mandatory
  row is therefore a rule triage follows, with nothing re-deriving the branch
  diff behind it. The charter and the triage method both say so.
- **`--verdict escalate` was dropped**, and with it the per-gate round
  accounting (`dispatch_count.<gate>`, rework children counted per gate) that
  the widened `check_set` would otherwise have needed. Both belong to the
  convergence half: the dispatch ceiling exists to proxy convergence, and the
  design that supersedes this one judges convergence instead of counting it.
  Shipping a second, differently-shaped convergence mechanism first would have
  cost the carve twice. An architectural objection that is a decision rather
  than a defect goes to a person as a visit; `skills/arch-review/SKILL.md`
  carries the shape.
- **Row 6 was already half-answered.** The `check_set` split that fuses
  `codex,triage` into one gate name was fixed ahead of this work, at every
  site in `gate-ensure.sh`, `pr-facts.sh` and `pr-open.sh`. What this work
  added is the single splitter in `pr-facts.sh`, so its three arms cannot
  drift back apart one at a time.

One artifact was added beyond the inventory: `assets/scripts/review-charter.sh`,
the single parser of the menu grammar. `signoff.sh` and the menu-agreement
tests read the table, and a predicate implemented twice is the defect class
this pack files most often.

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
- Resolved: proactive/first-reaction does NOT become this gate's front half.
  The two share a shape and nothing else — triage's subject is a diff and its
  output is machine-consumed by `gate-ensure.sh` and `merge.sh`, while a first
  reaction's subject is a bead and its output is a disposition, and the two
  fail in opposite directions. First-reaction is the city's first-level
  triage on the filing axis: its terminal step routes the bead to a pool,
  holds it on an edge, or files a visit. The evidence, and what each mechanism
  owes the other, is in
  [specs/tk-diqxx9/first-reaction-triage.md](../tk-diqxx9/first-reaction-triage.md).
