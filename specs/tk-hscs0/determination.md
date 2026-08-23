---
name: Determination for tk-hscs0 — why the proactive first reaction never fired
description: What was actually broken behind "proactive first reaction never fires", which of the bead's three defects held up under measurement, and the evidence that falsified the third. Read this before treating tk-hscs0's body as the diagnosis.
---

# Determination for tk-hscs0

The bead was filed 2026-08-22 19:54 and re-diagnosed 2026-08-23 in a converse
sitting (visit tk-ru7zo), where the operator ruled "fix it". It named three
independent defects and a three-item scope. This records what survived
contact with the live system.

**Summary.** Defects 1 and 2 are real and are the whole of the symptom; they
are one defect, not two, and the fix needed a piece the re-diagnosis did not
identify. Defect 3 is **falsified** — the v1 formula slung at a pool target
worked, and all six reactions the bead cites as evidence of the failure
actually ran to completion. The v2 migration still ships, for a different and
narrower reason.

## Defect 1 + 2 — the tunables sit on the consumer; the gate runs on the producer

Confirmed, and this is the entire operator-visible symptom.

`GC_PROACTIVE_ENABLED` and `GC_PROACTIVE_CITY_CAP` are declared in city.toml
under `[[rigs.overrides]] agent = "proactive"`. The reconciler injects them
into the proactive pool's own sessions and into its `work_query` /
`scale_check` — every *consumer* of the decision sees them. The decision
itself is made on the *producer* side, by `assets/scripts/gc-visit-open.sh` →
`tools/gc-proactive.sh deliverable`, running in the filer's process. The
primary filer is helm-svc (`services/helm/internal/server/open.go`), and a
`[[service]]` block has no env field at all, so helm-svc structurally cannot
carry them.

The bead treats the placement of the two vars as the open question ("the helm
service block in city.toml and/or a city-wide `[env]`"). That framing has no
good answer: a service block cannot hold env, and a city-wide `[env]` would
enable proactive for every rig, when only gc-toolkit's pool is meant to be on.

So the fix resolves the tunables **per target pool** instead of moving them:
env first (an operator override, and what an already-injected caller carries),
then the resolved city config for the pool this run targets, then the built-in
default. One `gc config show --json`, taken at most once per run and only for
a tunable the env left unanswered.

### The piece the re-diagnosis missed

Resolving from the pool's config is necessary but not sufficient, because the
lookup is *keyed by the pool*, the pool is rig-scoped, and `gc-proactive.sh`
qualifies its target from `GC_RIG` and fails closed when it is unset.
**helm-svc has no `GC_RIG` either** — it is a city-wide service. Read from the
live process (`/proc/<pid>/environ`, pid 3685568, 2026-08-23): no
`GC_PROACTIVE_*`, no `GC_RIG`.

Measured against that environment, reconstructed faithfully with `env -i`:

| script | rig context | answer | rc |
|---|---|---|---|
| origin/main | none | `no: … disabled` | 1 |
| config-aware | none | `no: … disabled` | 1 |
| config-aware | `GC_RIG=gc-toolkit` | `yes: … under the cap` | 0 |
| config-aware | `GC_RIG=signal-loom` | `no: … disabled` | 1 |

The last row is why this is resolved per-pool rather than city-wide: only
gc-toolkit's pool is enabled, and the gate must keep answering "no" for the
three rigs that are not.

`gc-visit-open.sh` therefore asks under the **subject's** rig. It already
resolves `RIG_NAME` on both subject paths well before the gate, and
`gc-helm.sh`'s `react` already makes the same move on the sling side.

**On the bead's acceptance criterion.** "`tools/gc-proactive.sh deliverable`
must exit 0 from helm-svc's env" is not satisfiable as literally written, and
should not be: with no rig named, the honest answer is "no" — the enable state
is per-rig and helm-svc is city-wide. What is satisfiable, and what the
symptom actually requires, is that the gate answers "yes" on the path helm-svc
takes, where the subject names the rig. That is what the table above shows.

## Defect 3 — FALSIFIED

The bead's claim: `mol-first-reaction` is a v1 formula slung at a pool target,
`gc sling` rejects such slings, "demand is structurally 0 and stays 0 with the
env fixed."

This does not hold. Three independent lines of evidence:

**1. The guard is on a different code path.** `RecipeHasReadySurface` gates
`slingFormula` — the standalone `gc sling <target> <formula> --formula` launch
(gascity `internal/sling/sling_core.go`) — and a pool ORDER
(`cmd/gc/order_dispatch.go`, as a warning). The path this formula uses,
`--on`, routes through `slingOnFormula` → `attachFormulaToBead`, which applies
no such check. `--on` routes the *target bead*, which is Ready-visible on its
own merits; the container root just rides along.

**2. The beads were routed and were picked up.** From
`tk.dolt_history_issues`, all six targets — tk-63qgj, tk-yrio, tk-lpf9g,
tk-0tln5, tk-lfgyw, tk-mv5xmu — carry
`gc.routed_to = "gc-toolkit/gc-toolkit.proactive"` with `status = in_progress`
in their history.

**3. All six reactions completed.** Every one of those beads carries a
`# First reaction` card in its notes, `gc.proactive_reaction = 1`, and a
stamped `gc.takeaway`.

**Where the bead's measurement went wrong.** "Store-wide count of beads
carrying `gc.routed_to=<rig>/gc-toolkit.proactive`: 0" was taken on a
*completed* state. The formula's own final step runs
`gc-helm.sh takeaway … --release`, which clears the route. The field is
therefore present-but-**empty**, not absent — the absent-vs-empty tri-state.
A `--metadata-field gc.routed_to=<pool>` query counts zero either way, so the
count cannot distinguish "never routed" from "routed, worked, released". Live
reads confirm the empty (not absent) form on all six.

The related observation — "all six hand-poured molecules: routed=<empty>
convoy=<empty> type=molecule" — is about the wisp **roots**, which are never
routed by design. The routed thing is the target bead.

**Why the reactions ran while the switch was off.** `cmd_sling` consults the
merge strategy and the cap clamp, but *not* `proactive_auto_enabled`. Only
`deliverable` and `demand` consult the enable gate. Manual slinging is
deliberately ungated, which is exactly why the operator's hand-poured items
worked throughout the window when auto-spawn was disabled.

## Why the v2 migration ships anyway

Not to revive a dead surface — the surface was not dead. It ships because of
what the v1 container root leaves behind:

- A v1 wisp materializes step beads but nothing closes them, and step 3 drains
  without closing anything, so the whole 4-bead chain stays open forever.
  Every completed v1 reaction minted one unclaimable husk. Those husks are
  scope item 3.
- `{{issue}}` is a deprecated v2 compat alias, removed next release.
- v1 gives no convoy, so nothing derives the target bead per step, and a
  session that dies mid-reaction has nothing to resume from.

The migrated formula closes each of its three steps through
`assets/scripts/step-close.sh` (resolving by assignee + `gc.step_ref`, never
from a `GC_*BEAD_ID` env var — tk-niu2f), so `workflow-finalize` can retire
the root rather than stranding it.

The one behaviour that genuinely was refused under v1, and now is not, is a
standalone `--formula` sling or a pool **order** for this formula. Neither is
in use today; if a scheduled producer is ever wanted for proactive reactions,
v2 is the precondition for it.

## Scope item 3 — the husk reap

Six roots named by the bead, each a 4-bead chain (root + `load-bead` +
`first-reaction` + `advance-and-drain`) — 24 beads. Before reaping, all 24
were verified `open`, unassigned, and unrouted, with no external dependents;
and each root's target bead was verified to carry a completed reaction. Reaped
with `gc bd mol burn --force`; all 24 confirmed gone and all six targets
confirmed intact afterwards.

| root | target | target state after reap |
|---|---|---|
| tk-b2t2h | tk-63qgj | open, reaction + takeaway present |
| tk-wyocx | tk-yrio | closed, reaction + takeaway present |
| tk-fp4qt | tk-lpf9g | open, reaction + takeaway present |
| tk-8z77p | tk-lfgyw | closed, reaction + takeaway present |
| tk-y5df6 | tk-mv5xmu | closed, reaction + takeaway present |
| tk-7yi5u | tk-0tln5 | open, reaction + takeaway present |

These are instances of tk-zab6q (workflow husks as ledger pollution). The
generator for `mol-polecat-work` husks is upstream and unfixed; the
`mol-first-reaction` generator is fixed here, by the step-closes above.

## Not done, deliberately

Option (c) from the bead's original body — render a hollow board tile as
visibly hollow, distinct from a real NEEDS — was left alone. The bead says
"fix in passing if it falls out naturally; do not expand scope to chase it",
and it does not fall out of any of the three changes here. It remains worth
doing and is untouched by this work.

## Board coverage

Unchanged by this work and worth restating, because it is the measure the fix
has to beat. Re-measured in the bead at 2026-08-23 04:35Z: 62 anchors, 34 with
a takeaway (55%), up from 41% the previous evening — the gain coming from hand
stamping by converse and mechanik, which tracks where sittings run and so
plateaus rather than converges. Whether the now-working automatic path closes
that gap is an observation to make after this lands, not a claim made here.
