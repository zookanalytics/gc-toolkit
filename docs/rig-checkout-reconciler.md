# Rig-checkout reconciler

The live `rigs/*` checkouts are what the runtime executes (pack
`source = "rigs/<rig>"`). The refinery merges PRs via its own clone, so a
merged PR is **not live** until `reconcile-rig-checkouts` syncs the checkout.

## Mechanism

Every 15m (`orders/reconcile-rig-checkouts.toml`, `scope = "city"`), for each
non-HQ rig (`gc rig list`): `git -C <rig> fetch origin` then
`merge --ff-only origin/<default-branch>`. `--ff-only` is safe by
construction — it advances only on a clean fast-forward, preserves a
non-conflicting dirty file for free, and **refuses (mutates nothing) on any
divergence or conflicting dirty file** — so it ships enabled, no dry-run gate.

## Exceptions

On a refusal the script does **not** touch the checkout. It files one
idempotent bead per blocked rig (`metadata.reconcile_rig=<rig>`, at most one
open per rig — re-runs never duplicate), assigned to the mayor
(`RECONCILE_MAYOR_ADDR`, default `gc-toolkit.mayor`), carrying `git status` +
`git log <remote>..HEAD`. The mayor judges in ~2 lines (already-upstream →
reset; machine-local config → leave; real work → handle) and closes it; the
script also auto-closes it once the rig ff-s cleanly. Why ff-only replaces the
classifier: bead `tk-yjtf`.
