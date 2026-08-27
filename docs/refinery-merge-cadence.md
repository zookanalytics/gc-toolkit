---
name: Refinery merge cadence
description: The exec order that drives the merge queue — the driver and its five arms, the rc=3 interlock, the single-flight guarantee, and how to read what a pass did. Read it to know what drives merges, and why nothing else may.
---

# Refinery merge cadence

The merge side of the anchor lifecycle is driven entirely by one order:
`merge.sh` fires only from this cadence, so the cadence *is* the merge queue's
clock. When it stops, gated-green CLEAN pull requests sit unlanded and nothing
else about the city looks wrong — which is why its liveness has its own doctor
check (`check-cadence-live`).

## Scope

**Mandate.** What drives the merge-side writers, what each arm owns, and the
runtime guarantees the arrangement depends on.

**Boundaries.** The states the arms move an anchor through are
[state-machine.md](state-machine.md). The refinery *agent*'s judgment calls
(rejection, blocked, refused) live in `formulas/mol-refinery-patrol.toml` and
are not driven by this order.

## Mechanism

Every 60s, per rig: `orders/refinery-reconcile.toml` (`trigger = "cooldown"`,
`scope = "rig"`) execs `assets/scripts/refinery-reconcile.sh`, the ~100-line
driver, which runs the five arms in order and exits.

| | |
|---|---|
| Cadence | `interval = "60s"`, tunable from city.toml `[[orders.overrides]]` |
| Scope | `scope = "rig"` — one registration per importing rig |
| Working directory | the rig's own root, so `git remote get-url origin` resolves |
| Environment | controller-built: `GC_RIG`, `GC_RIG_ROOT`, `BEADS_DIR`, `GC_BEADS_PREFIX`, `PACK_DIR`, `GC_PACK_STATE_DIR`, the Dolt projection, the `gh` token |
| Timeout | `300s`, deliberately under core `order-tracking-sweep`'s 10m stale window |

Anything per-rig is derived inside the driver from `GC_RIG` / `GC_RIG_ROOT`;
one `[order.env]` serves every registration. The refinery agent does not drive
the cadence — the arms run whether or not any refinery session is awake.

## The five arms

1. **gate-ensure.sh** — gate satisfiability. Every gating anchor declares a
   non-empty `check_set` (the default is stamped when absent; the `none`
   sentinel is respected), and every declared gate is *raisable*: marker green
   at the live head, or a live routed review bead in flight, else dispatch one
   (stamp first, then attach `mol-review` via `gc sling --on`; read the pour
   back). An `exception@` marker bound to the live head also ends the arm's
   interest with no dispatch, because it reads as settled. It holds the merge,
   and it says so on the anchor: `signoff.sh` set `gc.routed_to=human` and a
   `blocked_reason` naming the cap in the same act that wrote the marker. No
   visit is filed for it, so the anchor is parked rather than queued. A head
   move past a recorded `exception@` undoes that. The gate is no longer
   settled and one dispatch is re-armed.
   A review whose only reach is the pour stamp is qualified before it counts
   as in flight: if its workflow is spent — every step closed but
   `workflow-finalize`, which belongs to the control-dispatcher — no verdict
   can still be coming, and the arm escalates through `escalate.sh` under the
   `review-wedge` key rather than holding the anchor in silence. It escalates
   on the second consecutive sighting, because `mol-review`'s failure arm
   closes its chain before it restores the bead's route. One dispatch is
   refused outright: a head that a closed request-changes verdict already
   judged, whose rework child is still open, can only be answered the same
   way, so the gate stays armed and the merge held until that rework moves the
   head. Behind that sits a ceiling on DISPATCHES —
   `GC_MAX_REVIEW_DISPATCHES`, default 5, and not `signoff.sh`'s round cap —
   for the reviews neither refusal can see: one that ends writing no marker
   and leaving no open rework child returns the anchor to the state that
   triggered the dispatch, so the next pass repeats it at the same head. At
   the ceiling the gate holds, the anchor carries `dispatch_backstop.<gate>`
   and a note saying why, and one visit is filed under the `dispatch-runaway`
   key. **rc=3 is the designed interlock**: it holds `merge.sh` for this
   pass — an anchor whose gates are not yet satisfiable must not be mergeable
   on the same tick — and is reported without failing the order.
2. **pr-open.sh** — `pre_open_gate → pull_request`. For each anchor with
   `check.codex == green@<live head>`: adopt an existing PR for the branch or
   `gh pr create` non-draft, re-read the created PR by number, refuse a moved
   head, replay the verdict as a comment (never an approval), then one
   `lifecycle.sh` transition carrying `pr_url`/`pr_number`/`merged_target`.
3. **merge.sh** — `pull_request → merged`. Pinned `gh pr view`, identity gates
   (same repo, not a fork, head branch matches), re-read the anchor, validate
   holds/gates/children/approval/base/CLEAN, re-read the full authorization
   set immediately before merging, `gh pr merge --squash --match-head-commit
   <validated oid>`, then close + record via one `lifecycle.sh` call.
4. **pr-facts.sh** — external facts only, no merge authority: PR merged
   out-of-band (record), closed-unmerged (→ `abandoned` + visit), base changed
   (→ `retargeted` + visit), CONFLICTING (one rework child per head), a gate
   `green@` or `exception@` at a stale head (one re-review child per head,
   carrying `mol-review`), hold-resolved retraction.
5. **convoy-graduate.sh** — all convoy members closed AND ≥1 recorded merge
   onto the integration branch AND no hold/branch veto → assignee=refinery,
   `branch=integration/<id>`, `merge_strategy=mr`.

## Single-flight: why there is no lock

Two `merge.sh` writers against the same anchors is the failure this
arrangement exists to prevent, and the controller prevents it:

- The tracking bead for a run is created **synchronously before** the run
  launches and closed in a `defer` **after** it returns.
- The dispatcher's first gate skips any order with an open tracking bead.
- That gate keys on `ScopedName()` — `refinery-reconcile:rig:<rig>` — so each
  rig has its own single-flight and co-tenant rigs never serialise against
  each other.

Two settings must never change, because each would undo the guarantee:

- **Never set `no_work_gate` on this order.** It opts the order out of both
  open-work gates, and the first of them is the single-flight above.
- **`timeout` must stay below `order-tracking-sweep --stale-after`** (10m in
  core). The sweep closes a tracking bead it judges stale, and an un-gated
  tracking bead is a second dispatch — keeping the kill earlier than the sweep
  is what makes single-flight hold for a *wedged* pass, not merely a slow one.

For the same reason, never run a cadence driver out-of-band (by hand, cron,
or a daemon): it is a second merge writer the controller's gate cannot see.

## Reading what a pass did

The controller keeps an exec order's output only on non-zero exit, folding a
bounded tail into the `order.failed` event. So: an unexpected arm failure makes
the driver exit 1 (the failing arm names reach `order.failed`); gate-ensure's
rc=3 hold is reported but does not fail the order. A healthy pass logs to
`<GC_PACK_STATE_DIR>/refinery-reconcile/<rig>/pass.log`, trimmed to
`REFINERY_RECONCILE_LOG_KEEP` lines (2000 default) — each
`=== <timestamp> rig=<rig>` line is one completed pass, and the log is not
subject to bead retention.

**`gc order history` is store-complete only when the read is unbounded.** Any
positive `--limit` — including the default 50, and a limit larger than the row
count — returns runs from the city store alone, printed under a `RIG` column,
so a single-rig answer looks city-wide. Always:

```bash
gc order history refinery-reconcile --since 30m --limit 0
```

Prefer `gc doctor` (`check-cadence-live`) over hand-rolled queries: it asserts
per rig that the order is registered and firing within its interval.

## Adjacent order: rig-checkout sync

The live `rigs/*` checkouts are what the runtime executes, and `merge.sh`
lands PRs via GitHub — so a merged PR is **not live** until
`orders/reconcile-rig-checkouts.toml` (every 15m, city-scoped) fast-forwards
each rig checkout: `git fetch origin && git merge --ff-only origin/<default>`.
`--ff-only` mutates nothing on divergence or a conflicting dirty file; on a
refusal the script files one idempotent visit per blocked rig (via
`escalate.sh`, carrying `git status` + `git log <remote>..HEAD`) and
auto-closes it once the rig fast-forwards cleanly. The 15-minute window is
also the exposure behind component-model I9, watched by
`doctor/check-pour-text-current`.
