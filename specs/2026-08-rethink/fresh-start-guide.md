# Guide for a fresh start — realizing foundation.md in gc-toolkit, incrementally

You are a fresh agent on the gc-toolkit repository. This guide is the
distillation of a prior agent's full attempt at this work — what the
operator actually wants, the working relationship that attempt got wrong,
the assets it produced that you may quarry, and the traps (mechanical and
procedural) it paid to discover. It was written by that prior agent as its
last artifact, at the operator's request, with its failure analyzed
honestly. Read it all before your first move.

## 0. The partnership contract — read this first, it outranks the rest

The prior attempt failed **as a partnership** before it failed as
engineering. The mechanism: the agent treated the operator's utterances as
decisions to execute rather than positions to test. "About a third" became
a recorded target. "Bold is great" became a load-bearing identity.
"Keep the names for now" became names baked into every string. A ledger of
numbered rulings amplified it, converting musings into gospel with an
audit trail.

Your contract:

- **Ideas are positions to test, not rules.** When the operator shares a
  thought, your job is to probe it, strengthen it, or argue against it —
  with reasons — before anything hardens. Agreement without examination is
  a failure mode, not politeness.
- **Distinguish rulings from musings explicitly, and ask when unsure.**
  "Is this a decision, or thinking out loud?" is always a welcome
  question. Record only actual decisions, and status everything you
  record: RULING / PREFERENCE / OPEN.
- **Keep provisional things cheap to change.** Anything deferred for
  later review must not become load-bearing in the meantime. If a name, a
  number, or a shape is provisional, isolate it.
- **Push back proportionally.** The operator wants a partner who says
  "I don't think that follows, here's why" — and who yields gracefully
  when the operator, having heard it, decides anyway.
- **Numbers offered casually are calibration, not quotas.** Do not build
  measurement or enforcement around an aspiration unless asked.

## 1. What the operator wants — in their words

> "I want to USE GAS CITY, and I want to have the foundation.md in
> particular come through in a smart, intelligent, scaleable way, with
> what I feel like are solid ideas in architecture.md."

Unpacked, with statuses:

- **RULING — the vehicle is gc-toolkit itself, evolved in place.** No
  parallel pack, no second roster. Changes are edits to the pack the
  operator already runs.
- **RULING — batch size is the discipline.** Foundation says the pack is
  self-hosting; honor that. The work is a *sequence of small,
  independently-landable changes*, each one a PR the operator can
  actually read, riding normal delivery. The prior attempt built a
  cathedral in one session — twice over, counting the giant branch. Do
  not run a big-bang process of any kind.
- **RULING — same concept keeps its name.** Where a role or artifact is
  the same concept as what it replaces, keep the name and defend the
  evolved concept in architecture.md. A rename must be justifiable in one
  sentence stating the *conceptual* difference; if the sentence can't be
  written, the rename doesn't survive. (Shape changes — residency, caps,
  contract tightenings — are not concept changes.)
- **PREFERENCE — a mayor with a purpose is fine.** Zero standing agents
  is *one option*, not a target. Notably, upstream's own conventions
  assume a mayor seat (the sanctioned hold taxonomy is `hold:mayor`;
  escalations mail the mayor), and the operator's separately-stated wish
  for one unified entry point ("don't make me choose the surface") fits a
  standing front-door seat naturally. Argue residency case by case.
- **PREFERENCE — use the ecosystem.** Track Gas City's latest (upstream
  main, not the fork, where possible), lean on published packs/roles/
  formulas/skills when they fit, and prefer borrowing with citation over
  reinventing. Multi-provider validation of work is valuable; lean toward
  more of it.
- **OPEN — most everything else**, including which foundation-delivering
  change lands first. Discuss before deciding.

## 2. Where to start (candidates, not a mandate)

These are the seams the prior work identified as independently landable,
roughly ordered by value-per-risk. Treat as a menu to discuss with the
operator, not a plan to execute:

1. **Conversations as continuation groups** — the genuinely new
   capability, no Gas Town ancestor: a `converse` role (hold-not-close
   variant of upstream's `gc-role-worker` contract), turns as routed
   child beads, the board's pick-a-row filing-or-attaching a turn. Design
   ratified in `specs/tk-h9pq5/design-doc.md`; a reviewed realization
   exists in the quarry.
2. **The worker contract tightened** — v2 step-bead discipline (close own
   step with `gc.outcome` before drain-ack), gated-by-default for
   agent-initiated code. Same polecat, sharper contract.
3. **One patrol converted to a chain** — move continuity from a resident
   session into anchored chains of routed cycle beads, for *one* patrol,
   and live with it before converting others. The chain protocol (anchor
   order, liveness check, file-next-before-work, plain-bead cycle links)
   is designed and reviewed in the quarry and is independent of any
   residency decision.
4. **De-gastowning, gradually** — replace imported roster pieces with
   native ones a role at a time, each with its own argument, using the
   census (quarry) so nothing earned is silently lost.
5. **The decomposition formula** (`mol-nx-plan` spec in the quarry) — a
   brief becomes a ratified tree; iteration first-class; operator
   surfaces speak titles, never handles.

## 3. The quarry — validated assets, license to disagree

Branch `claude/gas-city-pack-architecture-1uyfq2` (PR #257, unmerged,
kept as reference). Everything below is *input*, not foundation — you are
explicitly licensed to disagree with any of it:

| Asset | Where | Validation level |
|---|---|---|
| Doctrine census + gastown disposition table + injection matrix | `specs/2026-08-rethink/spec.md` §2, §7 | Reviewed twice; the single most expensive-to-redo artifact |
| Port ledger | `packs/gc-next/assets/scripts/PORTS.md`, `doctor/PORTS.md` | Accurate at writing |
| Patrol cycle logic (land + health) | `packs/gc-next/formulas/mol-nx-patrol-*.toml` | Reviewed; step design is the asset, names are not |
| Chain protocol (anchor order, liveness check) | `packs/gc-next/orders/`, `doctor/` | Reviewed; two live-city findings already banked against it |
| converse + turn wiring | `packs/gc-next/agents/converse/`, `formulas/mol-nx-turn.toml` | Reviewed; contract re-verified against upstream source |
| v2 worker formula + signoff-gate fragment | `packs/gc-next/formulas/mol-nx-work.toml`, `template-fragments/nx-signoff-gate.template.md` | Reviewed |
| mol-nx-plan spec (decomposition, desired-state reconcile) | `specs/2026-08-rethink/mol-nx-plan-spec.md` | Adversarially reviewed, design-only |
| Operator rulings + this failure's record | `specs/2026-08-rethink/decisions.md`, the operator's finding files | Primary sources — but re-read §0: several "rulings" were musings over-hardened; the 2026-08-07 finding and this guide supersede where they conflict |
| Staging-host runbook | `specs/2026-08-rethink/staging-host.md` | Install facts doc-verified; the bead re-route pass mostly dissolves once names revert |
| Ecosystem/upstream research | `specs/2026-08-rethink/ecosystem-fit.md` | Source-verified 2026-08-06 |

## 4. Upstream facts, verified from source (dated 2026-08-06, clone `3e629ad`)

Safe to rely on; re-verify anything load-bearing since upstream moves fast:

- The roles pack's worker contract lives in a shared `gc-role-worker`
  fragment (12 roles, including `requirements-planner` and
  `task-decomposer`); discovery is the `gc gc claim` wrapper; **empty
  continuation group after close = session boundary; a successful claim
  is authoritative even across groups**. Old per-role prompt citations
  are stale.
- `gc.continuation_group` vacuum is live core; `gc.session_affinity`
  still advisory (watch: drain has begun writing it).
- `gc.routed_to=human` parks (nothing drives it); upstream's live
  human-wait is the `type=human` **gate** with notify/renudge orders;
  hold taxonomy is `hold:mayor` / `hold:external` only.
- `bd dep <blocker> --blocks <blocked>` creates a blocking edge;
  `bd dep remove` exists; `bd ready` excludes actively-blocked beads —
  so human-question beads can gate dependents natively.
- Upstream's conversation investment is `extmsg` (external channels as
  session-bound transcripts) — a different plane from beads-as-turns;
  meet it at the subject bead, don't compete.
- Install/bootstrap truth (macOS, `make install` from main, launchd
  supervisor, `gc rig add --adopt` for bead-store moves, automatic
  control-dispatcher): `specs/2026-08-rethink/staging-host.md`.

## 5. Traps

**Mechanical** — `docs/gascity-packs.md` is the canonical trap list; read
it before authoring anything. The prior attempt additionally paid for
these (all caught in review, all real):

- The routing read side is **exact string match**: direct `gc.routed_to`
  stamps must be rig-qualified (`${GC_RIG:+$GC_RIG/}<binding>.<template>`);
  a bare name sits silently forever. And in a city with a
  `default_sling_formula`, a bare sling is a Lane-4 attach that stamps
  nothing — stamp-don't-sling, or `--no-formula`.
- `--set-metadata` takes **one key per flag**; comma-joined pairs become
  one garbage value.
- Template fragments need `{{ define "<name>" }}…{{ end }}` wrappers.
- **Closing a failed step releases its dependents** — nothing halts a v2
  graph on `gc.outcome=fail`, so every abort path must make downstream
  steps no-op by reading their predecessor's outcome (fail-closed).
- Convoy completion counts the **convoy's** `parent-child` children —
  wire membership to the convoy, or it graduates empty.
- Whether `[[patches.agent]]` resolves an agent declared in the *same*
  layer is **unverified** — check before depending on self-patches.
- The both-contexts scope expansion applies to **city-level** packs only.

**Procedural** — what actually went wrong, so you don't repeat it:

- Musings hardened into rulings (§0). The ledger made it worse.
- Provisional names were baked into every load-bearing string, making
  the scheduled review expensive. Isolate what's provisional.
- A constraint was withdrawn (staged coexistence → fresh-city migration)
  and the machinery serving it was **kept by inertia**. When a premise
  falls, re-derive everything that stood on it — run the consistency
  test against your own scaffolding, not just the runtime's.
- Batch size: one session built a parallel pack, a spec suite, and a
  cutover plan before the operator lived with any of it. The operator's
  reaction to *seeing it built* was the most valuable review — it came
  months of work too late. Ship small; let the operator live with each
  change; treat their reaction as the primary gate.

## 6. How to begin

1. Read `docs/foundation.md` and `docs/architecture.md` — the beliefs
   are the point; the operator considers them solid.
2. Read the operator's finding on the prior attempt (the
   parallel-vs-in-place vehicle finding) — it is the sharpest statement
   of what they want and how they judge.
3. Open a conversation, not a plan: bring your read of the first seam
   (§2), your doubts about it, and one genuine question. Do not produce
   an outcome document. Do not produce a phase structure. Propose the
   first *small* change, argue about it like a partner, and land it
   through the city's own delivery.

The prior attempt's last, honest summary: the ideas mostly survived
review; the process didn't. The census, the conversation model, and the
chain protocol are worth mining. The grand unified rewrite — in any
vehicle — is not worth repeating. Realize foundation.md the way
foundation.md itself says work should happen: bead-sized, reviewed,
landed, and compounding.
