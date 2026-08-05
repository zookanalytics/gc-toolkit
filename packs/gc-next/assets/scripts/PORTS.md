# Ports in progress — carried executables

The O5 census (specs/2026-08-rethink/spec.md §7) carries the live pack's
script machinery into gc-next. The sources live **in this same repository**
(`assets/scripts/`, `tools/`, `services/`) until cutover stage 5, so
nothing here is lost — this manifest is the authoritative list of what
ports, to what name, and what changes in the port. Each port is intake-era
work (stage 0+) that rides Delivery; port beads are filed at intake.

| Source (live pack) | Ports to (gc-next) | Change in port |
|---|---|---|
| `assets/scripts/merge-skill.sh` | `assets/scripts/nx-merge-skill.sh` | Identity/doctrine unchanged (single writer of merged-truth); pool names re-pointed to `gc-next.*`. |
| `assets/scripts/pre-open-resolve.sh` | `assets/scripts/nx-pre-open-resolve.sh` | Unchanged mechanics; invoked from `mol-nx-patrol-land`. |
| `assets/scripts/check-set-heal.sh` | `assets/scripts/nx-check-set-heal.sh` | Unchanged (anchor repair; backfills before visibility). |
| `assets/scripts/reconcile-graduated-convoys.sh` | `assets/scripts/nx-graduate-convoys.sh` | Unchanged. |
| `assets/scripts/quiesce-completed-workflows.sh` | `assets/scripts/nx-quiesce-workflows.sh` | Unchanged (tk-p9ji9). |
| `assets/scripts/gc-helm.sh` (+ `services/helm/`) | `assets/scripts/nx-helm.sh` (+ `services/helm/`) | **Pick-a-row rewired**: files-or-attaches a turn (tk-h9pq5 §6 of the spec) instead of resume-or-create a host; `takeaway --release` maps to stop-routing-and-drain. The Go sidecar carries with its board sourcing unchanged. |
| `assets/scripts/gc-bd-watch.sh` | `assets/scripts/nx-bd-watch.sh` | Unchanged. |
| `tools/gc-bd-universe.sh` | `assets/scripts/nx-bd-universe.sh` | Unchanged (the fed slice + untrusted-data fencing); moves under `assets/scripts/` per pack-spec layout. |
| `tools/gc-proactive.sh` | `assets/scripts/nx-outride.sh` | Pool/env names re-pointed (`GC_NX_OUTRIDER_*`); mirrors the agent.toml gate + clamp + board-rank logic (keep in lockstep — gate-asserted by the carried fixture). |
| `assets/scripts/host-bead-skip.test.sh` | `doctor`-adjacent regression fixture | Re-keyed: the skip clause under test becomes `task_kind=conversation` (tk-h9pq5 Q1). |
| Fixtures: helm-open, helm-surface, proactive-first-reaction, bead-universe-reachability | carried beside their ported tools | Re-pointed at nx names. |
| `assets/scripts/worktree-setup.sh` | `assets/scripts/nx-worktree-setup.sh` | **Shipped now** (minimal provisioning; the live script's extra hardening folds in at port). |
| tmux status-line chain (`tmux-status-line-override.sh`, `gc-toolkit-status-line.sh`, `tmux-bindings.sh`) | `assets/scripts/nx-status-line.sh` | **Shipped now**, single-layer + staging-gated (spec §2); bindings fold in at port. |

**Not ported** (retired, with rationale — spec §7): `tools/gc-bead-host.sh`
and the two bead-host fixtures (superseded by continuation-group
conversations, tk-h9pq5 Q4; zero live instances);
`tools/upstream-gc-sync.sh` (moves to the keeper sub-pack, not here).
