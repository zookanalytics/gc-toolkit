# Implementation notes — Phase 3 of the rethink

The staged tree is `packs/gc-next/`, implementing [spec.md](spec.md).
This file records what review checks against: the outcome-proxy ledger,
port status, and deviations from the spec discovered during
implementation (per the spec's own rule: deviations are recorded back).

## Proxy ledger (spec §10 → files)

| Outcome | Realized by |
|---|---|
| O1 | `packs/gc-next/pack.toml` (no imports; header trace); spec §2's dispositions realized across the tree; `assets/scripts/nx-collision-audit.sh` — **runs clean** against the live pack + pinned base-layer names (staging validation re-runs it inside a real city, stage 1). |
| O2 | `agents/converse/` (role, hold-not-close, self-title, recycle guard); `formulas/mol-nx-turn.toml` (turn convention + `task_kind=conversation`); the reaper-skip step in `formulas/mol-nx-patrol-health.toml` (`work-health`); the Helm pick-a-row rewire specified as the `nx-helm.sh` port row (`assets/scripts/PORTS.md`) — see deviation D2. |
| O3 | `formulas/mol-nx-work.toml` + `formulas/mol-nx-patrol-land.toml` + `agents/lander/` (close-on-land, check-set, single-writer); mr default + non-empty `check_set` default for agent-initiated work (`mol-nx-work` vars; wright/outrider `[env]`). |
| O4 | The interlock line in every formula header (implemented for `mol-nx-work`; realized-in-part note for `mol-nx-patrol-land`; recorded notes elsewhere). |
| O5 | Census §7 rows → files or PORTS manifests: fragments (2 shipped shared + inlined per-role, see D1), overlay (`assets/overlays/nx-cycle-recycle/`, gate re-keyed + record-then-drain), doctor (`doctor/check-nx-*` + `doctor/PORTS.md`), orders (`orders/nx-*.toml`), formula doctrines (in the four formula bodies), scripts/tools (`assets/scripts/PORTS.md`). Sources remain in-repo until stage 5, so every port row resolves. |
| O6 | No central doc touched on this branch; the stage-5 rewrite list is spec §9. |
| O7 | `pack.toml`: zero `[[named_session]]`; the residency decision + chain mechanics in spec §4 realized as `nx-patrol-anchor` (order + script) and `check-nx-patrol-chain-liveness`; sentry deliberately unscoped with the comment §4 requires; keeper unchanged this phase (its O7 argument is cutover-adjacent, spec §8). |
| O8 | Brand sentence at the top of every `agent.toml`, every formula description, `pack.toml`, `README.md`; turn-subject brand in the converse prompt and `mol-nx-turn`; the `task_kind`/`chain` metadata constants branded where defined (anchor order, patrol formulas). |
| O9 | Doctor + orders rows above; keeper sub-pack untouched and loading (its recompositions are stage-4 work, spec §8); doc audits shipped (`mol-nx-doc-drift`/`-memory` + their orders). |

## Deviations from the spec (recorded, with rationale)

- **D1 — fragment realization.** The spec's injection matrix maps ten
  doctrines to roles. Implementation ships two as shared fragment files
  (`nx-thread-role` — multi-consumer by design; `nx-signoff-gate` —
  dispatched into review runs) and **inlines the rest into the consuming
  role prompts**, each citing its source fragment and lesson beads. Reason:
  a single-consumer fragment adds a resolution layer without reuse; the
  doctrine-reaches-role obligation is what the matrix binds. The census
  stands: nothing is dropped.
- **D2 — Helm rewire depth** (amended into the spec after phase-3 review
  judged the first rationale unsound). The rewire ships as the `nx-helm.sh`
  port row's specified diff, not as executable bash; the honest reason is
  **divergence cost** — a diverged copy of a script family the live pack
  still runs, maintained through the whole overlap window — not the
  collision rule (the `nx-` rename satisfies that). Spec §6 and the §10 O2
  proxy now say exactly this, and the port bead is sequenced **before**
  stage 2's gate.
- **D3 — recycle directive mechanics.** The spec said the hook's action
  "changes to record-then-drain." A Stop hook cannot write a subject-bead
  outcome itself (only the role knows what to record), so the shipped hook
  sets a marker directive the converse prompt honors at the next turn
  boundary — deterministic trigger, role-executed recording. Invariants
  (never prompt, exit 0, defer-while-attached — with uncertain-attachment
  deferring, per the source) carried. **Recorded cost:** for a held
  conversation the next turn boundary is often the operator's return, so a
  recycle triggered mid-hold spends part of the interaction it protects;
  the honest close-out (outcome written, turn closed short) is what keeps
  that spend bounded.
- **D4 — `mol-nx-work` shape.** Two steps (build → drain) rather than a
  wider graph: the hand-off/gating half lives with the lander (the state
  machine's division of movers), so extra steps would re-encode lander
  work as worker steps. The v2 contract is still earned: the steps are
  independently routable, the finalize path closes the root, and fan-out
  shapes extend by adding steps, not by re-plumbing.
- **D5 — `services/helm` not copied.** Spec §1's layout and §7 name the Go
  sidecar as shipping in gc-next; it is instead a PORTS.md row (the same
  divergence-cost argument as D2 — the sidecar is roster-agnostic and
  unchanged, and the live pack keeps running it through the overlap). The
  §1 layout's `services/helm/` line is therefore a stage-5 arrival, not a
  staging one.
- **D6 — the health-city chain is a stage-4 activation, not a staging
  deliverable.** The spec's "deliberately unscoped sentry" rested on the
  both-contexts scope expansion, which applies to city-level packs only
  (docs/gascity-agents.md) — under the README's rig-level import no city
  sentry ever materializes, so a staged city chain would be unclaimable.
  Amended: sentry is explicit `scope="rig"`; the town half of health stays
  owned by the live pack's patrols through the overlap window; activating
  the city chain (city-level import wiring + a city anchor order + the
  liveness assertion) is a named stage-4 step. The formula's city steps
  ship gated, so activation is wiring, not authoring. Spec §4 amended in
  place.
- **D7 — the chain anchor is a formula order, not an exec-order script.**
  Review B4 showed order-exec env (`GC_RIG`, store resolution for `gc bd`
  writes) is undocumented, while the order→pool wisp path is the proven
  mechanism the live doc-keeper orders pin down. `mol-nx-patrol-anchor`
  (v2, Ready-visible root) fired at the sentry pool replaces the script;
  spec §4 amended in place.

## Stage-1 verification list (mechanics review-by-similarity only)

Recorded here so the staging rig's first import tests them explicitly:

1. `gc.run_target = "gc-next.wright"` in `mol-nx-work` resolves at pour to
   the rig-qualified `gc.routed_to` (a materialized build step is actually
   claimed by a wright) — the header carries the same warning.
2. A `[[patches.agent]]` in a pack's own pack.toml resolves an agent
   declared in the same layer (the converse recycle overlay stages) — the
   pack.toml comment carries the fallback.
3. v1 step `condition = "{{chain_scope}} == rig"` gates as expected (no
   live formula uses `condition`).
4. `gc bd create --json` id parse (`.id // .[0].id`) against the real CLI.
5. The supervisor endpoint shape in the recycle hook against the running
   supervisor.

## Known gaps for the reviewers

- Formula/step TOML follows the live formulas' observed schema (steps,
  needs, condition, metadata, vars); no compiler exists in this
  environment, so syntax conformance is review-by-similarity plus stage-1
  `gc doctor` — the specific unproven mechanics are enumerated in the
  stage-1 verification list above.
- The two new doctor `run.sh` scripts shell out to `gc`/`jq` shapes
  verified only against this repo's documented CLI usage; stage 1
  exercises them for real.

## Phase-3 review disposition

Both phase-3 reviews (spec conformance; mechanics audit) are applied in
the final revision: routed stamps rig-qualified with `binding_prefix`
vars, one key per `--set-metadata` flag, fragment `{{ define }}` wrappers,
`nx-signoff-gate` wired via wright's `append_fragments`, sentry re-scoped
and the city chain deferred (D6), the anchor converted to a formula order
(D7), the liveness and single-writer doctor checks corrected (store
scoping, errexit tail, GNU date, template bucketing), the recycle hook's
probe and defer bias aligned with the source, worktree sync advancing the
worktree, the first-reaction close-your-bead error removed, the lander
manual-spawn ban and convoy doctrine added to its prompt, and D2/D5
recorded honestly with spec §6/§10 amended in place.
