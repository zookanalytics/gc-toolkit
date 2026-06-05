# Rig-checkout reconciler

> Keeps the live `rigs/*` checkouts synced to their `origin/main`, escalating to
> the mayor **only** when novel local work collides with upstream. Design:
> `tk-yjtf`. Implementation: `tk-nu5u`.

## Why this exists

The checkouts under `rigs/*` are what the runtime executes (pack
`source = "rigs/<rig>"`; there is no separately-deployed copy). The refinery
merges PRs via its **own** clone, so a merged PR is **not live** until the
checkout is synced. They also accumulate `.beads/` churn (bd rewrites it
continuously) and the occasional machine-local tuning. Observed 2026-06-05: the
gc-toolkit checkout was 7 merged PRs behind and carried three local changes that
were all already on origin — a naive `reset --hard` would have been lossless
that day but in general risks eating real work, and a naive "dirty → notify"
spams because of the `.beads/` writes.

So this is a *reconciler*, not a dumb syncer: it classifies before it acts.

## The three buckets

Per run, per rig: `git fetch origin`, then classify every local deviation (a
commit in `origin/main..HEAD` **or** a tracked dirty/staged hunk) into one of:

1. **KNOWN DIVERGENCE** — matches the declared allowlist
   (`assets/config/reconcile-rig-checkouts.allowlist`, seeded `.beads/**`).
   Machine-local / bd-owned. Kept across an advance, never blocks.
2. **ALREADY UPSTREAM** — content already on `origin/main` (patch-equivalent
   commit via `git cherry`; blob-identical dirty file). Obsolete residue,
   dropped on advance.
3. **NOVEL REAL WORK** — not on origin, not allowlisted:
   - **conflicts** (upstream also changed those paths since the merge-base) →
     **BLOCK** the rig, escalate to the mayor, do **not** mutate the checkout.
   - **no conflict** → advance to `origin/main` but **preserve the novel work on
     top**, and flag it in the ledger as a PR-promotion candidate.

A rig blocks iff it has ≥1 novel-conflicting deviation. Otherwise it advances
(live) / would-advance (dry-run). Advancing preserves allowlisted paths
(`.beads/`) and non-conflicting novel work; already-upstream commits are dropped
(the pre-advance sha is logged + recorded; `git reflog` is the backstop).

Untracked files are ignored by default (`-uno`): they survive any advance
untouched and in practice are machine-local cruft (`backup/*`, `LOCK`,
`.local_version`). Set `RECONCILE_INCLUDE_UNTRACKED=1` to classify them too.

## Rollout: observe first, then grant write authority

The order **ships in dry-run / observe mode** (`[order.env] RECONCILE_DRY_RUN =
"1"` in `orders/reconcile-rig-checkouts.toml`). In observe mode it classifies,
writes the ledger, and refreshes mayor escalations, but makes **zero** checkout
mutations. The script also defaults to dry-run when the var is unset, so the
safe behavior holds even if the env block is removed.

1. **Watch.** Let it run on its 15m cadence (or `RECONCILE_DRY_RUN=1 RECONCILE_ESCALATE=0
   bash assets/scripts/reconcile-rig-checkouts.sh` by hand) and read the per-rig
   ledgers. Confirm it classifies real drift the way you expect.
2. **Grant write authority.** When satisfied, set `RECONCILE_DRY_RUN = "0"` in
   the order TOML and land it. Now non-blocked rigs are advanced for real.
3. **Handle escalations.** A blocked rig opens (or refreshes) one idempotent
   bead owned by the mayor. Reconcile the listed paths by hand or promote the
   local work into a PR; the bead auto-closes when the rig stops conflicting.

## Trigger: periodic for v1

Periodic backstop only (`trigger = "cooldown"`, `interval = "15m"`). A
post-merge event trigger is deferred: the work bead closes at PR-*creation*, not
at merge, so `bead.closed` on the work bead is not the merge signal. Whether a
clean "origin advanced / merge landed" event exists is a follow-up.

## The divergence ledger

Per-rig JSON under `$GC_PACK_STATE_DIR/reconcile-rig-checkouts/ledger/<rig>.json`:
the rig's behind/ahead, every classified deviation, and the pre-advance sha. This
is the **candidate set** for later PR-promotion — the same doctrine as
[`gascity-local-patching.md`](gascity-local-patching.md), one level down
(rig-checkout-local changes that should graduate into committed PRs). Promotion
is operator-initiated and deferred (not v1). Each mayor escalation bead links its
rig's ledger via `metadata.ledger_path`.

## The allowlist

`assets/config/reconcile-rig-checkouts.allowlist` — repo-relative globs, one per
line, seeded `.beads/**`. **Static by design**: operator-extended only (edit +
PR), no auto-learning, so real work can never be silently absorbed into the
tolerated class. Runtime-only additions are possible via `RECONCILE_ALLOWLIST_EXTRA`
(newline- or `:`-separated).

## Tunables (order.env or shell)

| Var | Default | Meaning |
|-----|---------|---------|
| `RECONCILE_DRY_RUN` | `1` | observe mode; `0` grants write authority |
| `RECONCILE_MAYOR_ADDR` | `mayor` | owner/route of the blocked-rig escalation bead |
| `RECONCILE_ESCALATE` | `1` | create/refresh/close mayor beads + nudge |
| `RECONCILE_INCLUDE_UNTRACKED` | `0` | also classify untracked files |
| `RECONCILE_ALLOWLIST_FILE` | pack config | allowlist path |
| `RECONCILE_ALLOWLIST_EXTRA` | — | extra patterns, runtime-only |
| `RECONCILE_RIGS_OVERRIDE` | — | test seam: `name=path` lines, bypass `gc rig list` |

## Tests

`assets/scripts/reconcile-rig-checkouts.test.sh` — hermetic (no `gc` binary, no
live city). Builds throwaway git fixtures exercising all three buckets, the
dry-run non-mutation invariant, the advance/preserve path, and the canonical
2026-06-05 gc-toolkit incident. Run it directly.
