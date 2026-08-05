# Ports in progress — carried doctor checks

Per the census (spec §7), the live pack's doctor suite carries into gc-next
under `check-nx-*` names; sources remain in this repo's `doctor/` until
cutover stage 5. Port beads are filed at intake. The two checks already
shipped here (`check-nx-patrol-chain-liveness`,
`check-nx-lander-single-writer`) are new to gc-next.

| Source (live pack) | Ports to | Change in port |
|---|---|---|
| `check-base-artifact-collision` | `check-nx-base-artifact-collision` | Snapshots re-point at gc-next's own formulas + `nx-worktree-setup.sh`; same job (silent shadowing of base artifacts), more important during staging. |
| `check-merge-gate-drop` (tk-4na1b) | `check-nx-merge-gate-drop` | Formula/pool names re-pointed (`mol-nx-work`/`mol-nx-patrol-land`, `gc-next.*`). Doctrine unchanged. |
| `check-cycle-recycle-hook` | `check-nx-cycle-recycle-hook` | Re-scoped: asserts the hook is staged onto `converse` (not witness/deacon/refinery) and gated to it. |
| `check-startup-discovery` | `check-nx-startup-discovery` | Re-scoped: asserts the reconcile doctrine is present in the patrol formulas' orient steps (the fragment-based tiers retire with the residents). |
| `check-pr-prep-single-commit-unchanged` (tk-ur4o2) | moves with the keeper sub-pack | Keeper material, not core. |
| `check-keeper-repour-reassign`, `check-keeper-resume-handoff-token`, `check-rebase-exceptions-through-keeper`, `check-rebase-worktree-branch-reuse` | move with the keeper sub-pack | Keeper material, not core. |
