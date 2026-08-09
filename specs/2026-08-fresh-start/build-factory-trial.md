---
name: Runbook — build-factory trial (increment 1)
description: Operator runbook for trialing the upstream gascity pack's build factory in the existing city, on the gc-toolkit rig, with the conversation spine (tk-h9pq5 Phases 0–1) as the brief — exact setup commands, the brief text, the stop-and-judge point, an evaluation checklist, and the follow-up loop. Invocation details verified from gascity-packs source 2026-08-08.
---

# Runbook: build-factory trial (increment 1)

**What this is.** Step 1 of the fresh-start increment path
([gas-city-native.md](gas-city-native.md)): run one real brief through the
upstream `gascity` pack's build factory and judge what it produces —
before deciding anything about adopting it. The brief is deliberately
recursive: it asks the factory to plan **increment 2, the conversation
spine** (tk-h9pq5 Phases 0–1). The factory produces reviewable artifacts
and stops at approval points, so a bad tree costs one judgment and
nothing runs; a good tree, once ratified, *is* increment 2's work filed.

**Where.** The existing city, gc-toolkit rig. Not a fresh city: the value
of the trial is judging the factory's output against work we understand,
in the environment it would actually serve.

## Setup (once, ~10 min)

City-level import (from the town root):

```sh
gc import add --name gc https://github.com/gastownhall/gascity-packs.git//gascity
gc import install
```

Rig-scoped roles for the gc-toolkit rig, in `city.toml`:

```toml
[rigs.imports.gc]
source = "https://github.com/gastownhall/gascity-packs.git//gascity/roles"
```

Two house-rule notes, flagged rather than silently violated:
- Upstream's README shows the import **unpinned**; our own rule
  ([gascity-packs.md](../../docs/gascity-packs.md)) is durable imports are
  `source`+`version`. For a trial, unpinned-at-tip is acceptable; pin
  before anything durable depends on it.
- The roles arrive under qualified names (`gc.requirements-planner`,
  `gc.task-decomposer`, …), all `fallback = true`, so they should not
  collide with the existing roster. If `gc doctor` or pack loading
  complains after import, stop and report — that's a finding, not a
  detour to fix silently.

## The brief (one bead)

```sh
gc bd create "Build the gc-toolkit conversation spine (tk-h9pq5 Phases 0-1)"
```

Then set its body (or paste as description at create time):

> Realize specs/tk-h9pq5/design-doc.md Phases 0–1 in the gc-toolkit pack.
> Phase 0: verify a pool-spawned session can self-title on claim
> (`gc session rename "$GC_SESSION_ID" …`); if it cannot, choose a
> fallback (reconciler-set alias, or board-only legibility) and record
> the choice. Phase 1: (a) a converse role authored as a delta on the
> upstream `gc-role-worker` contract, with the execute/close clause
> replaced by hold-for-operator — rebuild the subject bead's slice from
> its record, hold in_progress, write the visit's outcome to the subject
> bead's notes, close only the turn bead; (b) a turn-filing convention —
> a child bead of the subject carrying gc.run_target=<converse-role>,
> gc.continuation_group=<subject-bead-id>, task_kind=conversation;
> (c) a small dedicated conversation pool so held turns never starve
> implementation work. Acceptance is the tk-h9pq5 Phase 1 gate, on one
> real subject bead: (1) filing a turn spawns a session with no operator
> keystroke; (2) the role rebuilds the subject's slice, not the turn's,
> and holds; (3) on operator input the outcome lands on the subject and
> only the turn closes; (4) a second turn filed while the session is
> warm vacuums onto it; (5) after the session drains, a third turn
> cold-spawns and correctly answers a pre-seeded question about the
> subject from the record alone.

## Launch

```sh
gc sling gc.run-operator <bead-id> --on build-basic \
  --var artifact_root=plans/conversation-spine/build
```

Defaults that matter (leave them): `interaction_mode=interactive`,
`review_mode=agent`, `push=false`, `open_pr=false`.

**Corrected by the run (see
[build-factory-trial-reactions.md](build-factory-trial-reactions.md) §3):**
`interaction_mode=interactive` is *model discretion*, not a mechanism —
`build-basic` ships **no approval gate of any kind**, no graph edge can
wait on a human, and the run filed 8 beads with nothing asked. Expect
autonomy, not menus; the judge point below is *your* gate, imposed from
outside the formula.

**Known trap (F4, from the live run):** a launch warning may claim the
factory lacks context it actually receives — the input convoy delivers
the brief's referenced material even though the rendered context doesn't
show it. Do **not** "fix" this with `--var requirements_path=<doc>`:
that reuses the doc as the requirements artifact and silently skips the
requirements stage. If you genuinely need to hand it more context, the
safe var is `--var context_path=<dir>`. See
[build-factory-trial-findings.md](build-factory-trial-findings.md). The step chain is
prepare → requirements (`gc.requirements-planner`) → plan
(`gc.design-author`) → plan-review (`gc.review-synthesizer`) → decompose
(`gc.task-decomposer`) → implement → review → finalize. Artifacts are
*supposed* to be schema-checked (`gc.build.*.v1`, 3 attempts) — **but in
a split city/rig layout the check never runs** (relative
`.gc/scripts/…` path resolves against the rig root; every stage
control-quarantines and proceeds ungated — reactions doc, environment
finding 1). Assume artifacts are unvalidated unless the scripts were
installed into the rig root first.

## The stop-and-judge point

**The trial's deliverable is the tree, not the implementation.** Judge at
the end of *decompose*, before implement runs. `interaction_mode=
interactive` should hold for approval; if the graph barrels past
decompose without asking, interrupt it — that itself is a first-class
finding. Interrupting loses nothing: the factory ships continuation
formulas (`build-from-requirements/-plan/-review/-decompose/-convoy`)
that resume from any stage's artifacts, e.g.:

```sh
gc sling gc.run-operator build-from-decompose --formula \
  --var artifact_root=plans/conversation-spine/build \
  --var requirements_path=… --var plan_path=… --var plan_review_path=…
```

If the tree is ratified and implementation proceeds: the default
`implementation_target` is `gc.implementation-worker` (from the roles
import). Routing to the rig's existing polecat pool instead
(`--var implementation_target=…`) is possible but adds a variable to the
experiment — default first.

## What to react to (the judgment, ~15 min of your attention)

Artifacts land under `plans/conversation-spine/build/`
(`requirements.md`, `implementation-plan.md`, `tasks.md`, …). React to:

1. **Requirements fidelity** — did `requirements.md` capture the brief's
   intent, or drift? Did it ask you anything worth being asked?
2. **The tree** — `tasks.md`'s `convoys[]`/`beads[]` nesting and dep
   edges vs. how you would have cut it. Too fine, too coarse, wrong
   seams?
3. **The interaction** — where it blocked for you, whether those were
   the *right* moments (foundation: agents earn every interaction), and
   whether surfaces spoke titles or leaked handles.
4. **Cost** — wall-clock and tokens, order-of-magnitude.
5. **The gap question** — what did mol-nx-plan promise that you actually
   missed here (desired-tree re-planning? ratification as a turn?), if
   anything?

## Follow-up loop

Send reactions in whatever form is cheapest (bullet notes are enough; or
push the `plans/` dir somewhere readable). I fold the verdict into
[gas-city-native.md](gas-city-native.md) as ADOPT / ADAPT / SHELVE with
reasons; a ratified tree proceeds as increment 2's filed work, an
unratified one gets increment 2 hand-filed per tk-h9pq5 directly —
either way the spine work starts, and the factory question is settled by
evidence instead of argument.
