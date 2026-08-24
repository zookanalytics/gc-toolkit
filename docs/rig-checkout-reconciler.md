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

## Verification

`doctor/check-pour-text-current` asserts this order's own contract over exactly
the set it promises to keep current (`gc rig list`, non-HQ), and reports what
that contract does not cover.

It measures the lag but deliberately does **not** fetch — a doctor check is a
read, and fetching would repair the very condition it is trying to observe.
That constraint is what makes its second finding load-bearing: `git rev-list
HEAD..origin/<default>` compares against the **local** remote-tracking ref, and
only this order's own `git fetch` advances it. When the order stops, both sides
freeze together and the behind-count reads `0` at precisely the moment the lag
becomes unbounded. So the check dates the last fetch from `.git/FETCH_HEAD` and
treats the behind-count as a **floor** whenever that is stale.

A lag *inside* the 15m cooldown is this order's duty cycle and is reported as a
note, not a finding — with slack, because a cooldown order fires slower than it
declares and a threshold at 1× the interval would flag a healthy queue.

The HQ rig is excluded here for the same reason it is excluded above
(`select(.hq != true)`), and the check says so rather than silently skipping it.
