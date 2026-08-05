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
- **D2 — Helm rewire depth.** Spec §6 says the rewire is implemented in
  the staged tree. The helm *script family* is a port row (PORTS.md) rather
  than a shipped copy, so the rewire is implemented **as the port's
  specified diff** (pick-a-row → file-or-attach a turn; release →
  stop-routing-and-drain) rather than as executable bash in this tree.
  Reason: shipping a diverged copy of a 45-script family the live pack
  still runs would duplicate the exact machinery stage-5 renames, and the
  overlap window forbids same-name copies (§1). The O2 proxy is met at the
  spec level and the port bead realizes it at intake; if review reads §6
  more strictly, the port lands before stage 2 runs its gate either way.
- **D3 — recycle directive mechanics.** The spec said the hook's action
  "changes to record-then-drain." A Stop hook cannot write a subject-bead
  outcome itself (only the role knows what to record), so the shipped hook
  sets a marker directive the converse prompt honors at the next turn
  boundary — deterministic trigger, role-executed recording. Invariants
  (never prompt, exit 0, defer-while-attached) carried verbatim.
- **D4 — `mol-nx-work` shape.** Two steps (build → drain) rather than a
  wider graph: the hand-off/gating half lives with the lander (the state
  machine's division of movers), so extra steps would re-encode lander
  work as worker steps. The v2 contract is still earned: the steps are
  independently routable, the finalize path closes the root, and fan-out
  shapes extend by adding steps, not by re-plumbing.

## Known gaps for the reviewers

- Formula/step TOML follows the live formulas' observed schema (steps,
  needs, condition, metadata, vars); no compiler exists in this
  environment, so syntax conformance is review-by-similarity plus stage-1
  `gc doctor`.
- The two new doctor `run.sh` scripts and `nx-patrol-anchor.sh` shell out
  to `gc`/`jq` shapes verified only against this repo's documented CLI
  usage; stage 1 exercises them for real.
- `services/helm` is not copied (port row; the Go sidecar is
  roster-agnostic and unchanged).
