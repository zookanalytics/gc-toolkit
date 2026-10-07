---
name: helm-board operator-ownership signal — spike report
description: Rules how the helm board identifies operator-owned work without tripping core's stale-routed-config doctor check. Decides the per-class handling of gc.routed_to=human, the config-partition verdict, and the implementation breakdown.
---

# Spike report: helm-board operator-ownership signal (tk-z0k17q)

**Bead:** `tk-z0k17q` — *Spike: helm-board operator-ownership signal — replace/repartition `gc.routed_to=human` without breaking dispatch*
**Origin:** `tk-99sxtg` — *doctor session-model: stale-routed-config false-positive on `gc.routed_to=human`* (operator ruling in sitting `tk-n52t31`)
**Branch:** `polecat/tk-z0k17q`
**Surveyed:** 2026-09-15
**Status:** Decision recommended. The one durable code change in this bead is this report. The live steps that confirm the recommendation — apply the config, `gc reload`, re-run `gc doctor` — side-effect the running city and are deferred to the operator (§C), per the spike-bead rule that a polecat does not spawn, reset, or reconfigure agents in a live town.

---

## TL;DR — recommendation

Declare `human` as a **non-spawned route target** in the city config:

```toml
# city.toml (town config), top level — NOT under a [rigs.imports] block
[[agent]]
name = "human"
max_active_sessions = 0
```

This stops the `stale-routed-config` doctor finding at its source, for every
`gc.routed_to=human` bead in every store, with **no core Go change, no fork
patch, and no upstream ask**. `max_active_sessions = 0` is load-bearing: a plain
entry would make the supervisor spawn a "human" pool. Confirm live with §C.

`gc.routed_to=human` is not merely a board sentinel that a native signal can
replace — it is the pack's **one non-queue route** (`lifecycle.toml` `park_route`).
For two of its three classes it is the *only* thing keeping the bead out of pool
queues, so deleting it means re-architecting dispatch, not swapping a display
key. Making the route a legitimate config target is the minimal fix that
actually clears the finding; the board-redesign alternative (§5, Alternative B)
is larger, touches a live operator surface, and does not clear the finding
unless it deletes the route everywhere.

This diverges from the sitting's phrasing ("redesign the board to use native
signals") and is reconciled against the ruling's intent in §5.

---

## Provenance

Two repositories. Core is our fork `zookanalytics/gascity` (upstream
`gastownhall/gascity`); the board and scripts are this rig, `gc-toolkit`.

| Claim | Source | Repo |
|---|---|---|
| The doctor check that fires | `cmd/gc/doctor_session_model.go:100-107` | gascity (fork) |
| `human` resolves via `FindAgent` | `internal/config/named_sessions.go:46-81` | gascity |
| A config agent spawns unless gated | `cmd/gc/build_desired_state.go:506-540` | gascity |
| `max_active_sessions=0` gates the spawn | `internal/config/session_capacity.go:35-45` | gascity |
| Sibling check already exempts `human` | `cmd/gc/doctor_routed_to_checks_test.go:91-114` | gascity |
| `human` is a reserved mail recipient, by literal | `internal/mail/resolve.go:32,45` | gascity |
| Board gathers the three classes on metadata | `services/helm/internal/source/beads.go:457-524` | gc-toolkit |
| `humanGated` reads the marker | `services/helm/internal/board/derive.go:310-323` | gc-toolkit |
| `human` is the one non-queue route | `lifecycle/lifecycle.toml:37-44` | gc-toolkit |
| A normal pool offers by its own address | `agents/proactive/agent.toml:38-39` | gc-toolkit |
| The (retired) converse offer predicate | `assets/scripts/converse-claim.sh:229-234`, `agents/converse/agent.toml:9` | gc-toolkit |
| The stampers (per class) | §3, table | gc-toolkit |
| Live census | `gc bd list` over the rig store and `/home/zook/loomington/.beads` | live |

---

## 1. What `gc.routed_to=human` is, and how much of it there is

Core never writes `gc.routed_to=human`. Core routes beads only to pool or agent
identities; it reserves the *word* `human` in two unrelated places — a mail
recipient (`internal/mail/resolve.go:45`) and a gate await-type. `gc.routed_to=human`
is this pack's signal, doing two jobs at once:

- **A route.** `lifecycle/lifecycle.toml:44` declares `park_route = "human"`:
  "the one route value that is not a queue. No pool claims it, so it parks the
  bead for a person ... every other route is a pool offer." A normal pool's
  demand query matches `gc.routed_to` against the pool's *own* address
  (`agents/proactive/agent.toml:39`: `gc.routed_to=$target`), and `human` is no
  live pool's address, so the value excludes a bead from every pool by
  construction.
- **A board signal.** `services/helm` gathers operator-owned work by metadata,
  not issue type, because the marker sits on ordinary `task`/`bug` beads
  (`source/beads.go:457-467`). The `human` gather is
  `{kind:"human", key:"gc.routed_to", value:"human"}` (`beads.go:501`), and
  `board/derive.go:320` classes a bead operator-owned when
  `Metadata["gc.routed_to"]=="human"`.

**Live census (2026-09-15).** Rig store `gc-toolkit`: 97 open beads carry
`gc.routed_to=human`. City store `/home/zook/loomington/.beads`: 4 more (the
mayor advisories the origin bead first reported). By class:

| Class | Count (rig) | Selector | Native non-route signal it also carries |
|---|---|---|---|
| Visits | 57 | `task_kind=visit` | none that excludes from a pool |
| Demand / decision | 21 | `type` in {decision, task, bug, convoy}, no `merge_result` | a demand *gate* for the gate subset only |
| Parked / wedged anchors | 19 | `merge_result` present (`pre_open_gate`, `held`, …) | `merge_result`, `merge_hold`, lifecycle state |

**Zero** of the 101 beads (97 rig + 4 city) carry `assignee=human`; all are
unassigned or assigned to a session bead. This matters for §4.

---

## 2. The doctor finding, exactly

`cmd/gc/doctor_session_model.go:100-107`:

```go
if routedTo := strings.TrimSpace(b.Metadata[beadmeta.RoutedToMetadataKey]); routedTo != "" {
    cityName := config.EffectiveCityName(c.cfg, "")
    if config.FindAgent(c.cfg, routedTo) == nil {
        if _, ok, _ := resolveNamedSessionSpecForConfigTarget(c.cfg, cityName, routedTo, currentRigContext(c.cfg)); !ok {
            findings = append(findings, fmt.Sprintf("stale-routed-config: %s routes to missing config target %q", b.ID, routedTo))
        }
    }
}
```

The finding fires only when `FindAgent` returns nil **and** the named-session
resolver also misses. `FindAgent` is checked first and short-circuits, so making
`FindAgent(cfg,"human")` non-nil is sufficient. The check is upstream core,
unchanged on `upstream/main`, so a sync does not fix it. Core's *newer* sibling
check already treats a config agent named `human` as canonical —
`cmd/gc/doctor_routed_to_checks_test.go:91-114` builds `config.Agent{Name:"human"}`
and asserts `StatusOK` for a `gc.routed_to=human` bead. The two checks disagree
only because `stale-routed-config` predates that convention.

---

## 3. Per-class ruling: can a native signal carry the route?

Every writer of the marker, by class (verified in the tree):

| Stamper | Class | Is the route redundant, or the only signal? |
|---|---|---|
| `assets/scripts/gc-helm.sh:965` (`demand`) | demand-gate | **Partly redundant.** The demand is also a native gate (`issue_type=gate`), which is what keeps it out of Ready. The route is additive: it is the board's gather predicate. |
| `assets/scripts/gc-helm.sh:1158` (gate-visit, `POOL=human`) | visit | **Only park signal.** The bead also gets `task_kind=visit`, but that is a claim discriminator, not a pool exclusion. |
| `assets/scripts/escalate.sh:406` (default `human`) | visit | **Only park signal.** Same shape as gate-visit. |
| `assets/scripts/signoff.sh:869` (round cap) | parked-anchor | **Complementary.** Anchor also carries `merge_hold`, `merge_result`, `gc.takeaway`; the route elevates it to the `human` row. |
| `assets/scripts/lifecycle.sh:446` (`:249` default) | parked-anchor / held | **Only park signal.** `lifecycle.toml:37-40`: the route is the only thing keeping a detached-state anchor off pool queues. |
| `assets/scripts/converse-hold.sh:106` (`--route human`) | visit / demand-gate | **Partly redundant** with the demand gate the work blocks on. |
| `formulas/mol-refinery-patrol.toml:505,605` (`--route human`) | parked-anchor | **Only park signal.** |

**3a. Demand-gates.** The route is partly redundant: `gc-helm.sh` demand also
files a native `await_type=human` gate, and gates are not pool-claimed. The
board *could* gather this subset via the gate instead. But that only covers the
gate subset — the 21 demand/decision beads are a mix, and 6 are `decision` beads
with no gate. So "read the gate instead" is a partial answer even for this class.

**3b. Visits (57, the largest class).** The route is irreducible. A visit is
deliberately not a gate (it tracks an edge and stays claimable), so it has no
native pool-exclusion. `task_kind=visit` is the *claim scope*
(`converse-claim.sh` scopes the claim on it), not the *offer predicate*: what gc
offers is route-based, and `converse-claim.sh:232` records that clearing
`gc.routed_to` "would park the turn" because "it is the pool's offer predicate."
The converse routed-pool is retired, so today the value parks a visit purely by
omission. Either way, deleting it from a visit removes its only pool-exclusion
and its only board row. It cannot be replaced by `task_kind=visit` without
re-plumbing how gc offers converse work.

**3c. Parked / wedged anchors (19).** The route is irreducible as the
pool-exclusion. `lifecycle.toml:37-44` is explicit that `park_route=human` is
the one non-queue route and that a detached-state anchor may rest on it; a
transition that finds it leaves it alone. The anchor also carries `merge_result`
(→ the board's `merge` kind) and often `gc.takeaway` (→ `parked`), and the
`human` gather is placed last so the dedup keeps the elevated `human` row
(`beads.go:519-522`, `derive.go:314-320`). Dropping the route would drop the
anchor into the merge band and, more seriously, remove the documented
keep-out-of-queue guarantee.

**Conclusion.** A native signal can carry only the demand-gate subset, and only
partially. For the two larger classes the route is the load-bearing
pool-exclusion. "Identify operator-owned work via native signals" is therefore
not sufficient on its own: any change that *deletes* `gc.routed_to=human` must
first give visits and parked anchors a new pool-exclusion, which is a dispatch
re-architecture, not a board change.

---

## 4. The config-partition verdict (the leading hypothesis)

**Hypothesis:** declare a route-only `human` partition in city config so core's
own resolver recognizes `gc.routed_to=human`, with no core Go change and without
the runtime trying to spawn a human session.

**Verdict: viable, with `max_active_sessions = 0`, declared bare in `city.toml`.**

1. **It resolves the finding.** `FindAgent` (`internal/config/named_sessions.go:46-81`)
   scans `cfg.Agents` for one whose `QualifiedName()` equals the routed value.
   An agent with `name="human"` and no binding and no dir has
   `QualifiedName()=="human"`, so `FindAgent(cfg,"human")` returns non-nil and
   §2's finding is never appended. This is the exact shape the sibling check's
   test already relies on.

2. **It must be bare, which means `city.toml`, not a rig agent.** The routed
   value in the wild is bare `human` (all 101 beads). `FindAgent`'s fallback
   path returns nil for an unqualified identity, so only a bare
   `QualifiedName()=="human"` matches. City-scoped agents imported from a rig are
   binding-prefixed — `gc-toolkit.dog`, `bd.dog`, one per binding — so an
   `agents/human/agent.toml` in this rig would resolve as `gc-toolkit.human`, not
   `human`, and would not match. The declaration must be a top-level `[[agent]]`
   in the town's `city.toml`, which carries no binding
   (`pack.go:946` appends the town's own agents after the binding-prefixed
   imports). `city.toml` is tracked in the **`loomington` town repo**
   (`zookanalytics/loomington`), not this rig — see §6.

3. **A plain entry would spawn; `max_active_sessions=0` stops it.**
   `build_desired_state.go:506-540` iterates `cfg.Agents`, and at :538 does
   `if !cfg.Agents[i].SupportsGenericEphemeralSessions() { continue }` before the
   default routed-demand probe. `session_capacity.go:41` returns false from that
   method when `max_active_sessions==0`. So a plain `[[agent]] name="human"`
   would let the probe count all 97 `gc.routed_to=human` beads as demand for a
   "human" pool and spawn sessions; `max_active_sessions=0` gates it out of that
   path and every other spawn path Explore mapped (`pool_desired_state.go`,
   `cmd_start.go`, `doctor_pool_idle_routed_work_check.go`). `FindAgent` ignores
   the field, so the finding still clears.

4. **It does not trade one finding for another.** The same check flags
   `legacy-token-matches-config-only` when a bead's **assignee** matches a config
   agent with no live session (`doctor_session_model.go:86-91`). If any bead were
   assigned to `human`, declaring the agent would move it from
   `stale-routed-config` to `legacy-token-matches-config-only`. The live census
   (§1) shows **zero** `assignee=human` beads in either store, so no trade
   occurs today. §C re-checks this before adoption and §D notes the standing
   risk.

5. **It does not disturb the reserved-word uses of `human`.** Mail resolution
   matches the literal string (`internal/mail/resolve.go:45: if to == "human"`),
   not a config lookup, so `gc mail send human` is unchanged. The gate
   await-type is unrelated. The orphan sweep preserves `assignee=human` by the
   literal alias, not by agent lookup.

6. **It fixes every store at once.** The doctor reads config, which is
   city-wide, so one declaration clears the finding for the rig-store beads and
   the city-store advisories together — which a per-stamper route removal cannot
   do, since it only touches beads the pack's own scripts write.

**What stays live-only.** Points 1–6 are static reads. That the running
supervisor does not spawn a `human` session after `gc reload`, that `gc doctor`
actually goes clean, and that config validation accepts a command-less
`max_active_sessions=0` agent are runtime facts. They are §C.

---

## 5. Recommendation and reconciliation with the ruling

**Recommended: the config-partition (§4).** It is the minimal change that
clears the finding, it honors the sitting's two hard constraints — no core
patch, no upstream ask — and it treats `human` as what the origin bead's own
takeaway called it: "a dispatch route, not a board sentinel." A route that core
routes to should be a config target core recognizes.

**Where this diverges from the sitting.** The sitting said "redesign the helm
board to identify operator-owned work via native signals." Read literally as
"delete `gc.routed_to=human` and gather via `await_type=human` gates +
`task_kind=visit`," the evidence says that path does not work as stated:

- It does not clear the finding unless the route is deleted from *every* bead in
  *every* store, including the mayor's city advisories, which the board does not
  write.
- Deleting the route strands the visit and parked-anchor classes, which have no
  other pool-exclusion (§3b, §3c). Restoring one is a dispatch re-architecture
  that removes the `park_route` invariant (`lifecycle.toml:44`) core-adjacent
  pack code depends on.

Read for intent — "stop the noise without a core patch or an upstream ask, and
don't route work away from the person who owns it" — the config-partition
satisfies the ruling better than the redesign does. The decision is the
operator's to confirm at this PR.

**Alternative B — native-signal board redesign (not recommended).** Kept here
so the operator can weigh it. To actually clear the finding it must *delete* the
route, so its scope is:

1. Give visits a native pool-exclusion (a `task_kind=visit` exclusion in every
   pool demand query, or a new hold), so a route-less visit is not claimed.
2. Give parked anchors a native pool-exclusion to replace `park_route`, and
   retire the `park_route` invariant in `lifecycle.sh`/`lifecycle.toml`.
3. Re-point the board gather from `gc.routed_to=human` to the per-class native
   signals (`source/beads.go`, `board/derive.go`).
4. Drop the stamp from every writer in §3's table.
5. Separately handle the city-store mayor advisories (still route-only).

That is roughly four to six polecat beads on a live operator surface, it deletes
a documented invariant, and it leaves the converse-offer semantics
(`converse-claim.sh:232`) to be re-derived. The config-partition obviates all of
it.

**Alternative C — accept as cosmetic.** `tk-99sxtg` is the dedup tracker
(`doctor_check=session-model`), so the deacon does not re-escalate while it is
open. The raw `gc doctor` warning stays. This is the do-nothing floor; the
config-partition is a small, clean improvement over it.

---

## 6. Implementation breakdown

The recommended path is a single operator config action, not a set of pool
beads, so nothing is pre-filed here — matching the rule that decision-dependent
work is filed once the operator accepts the model. On acceptance of §5:

| # | Work | Owner / rig | Wiring |
|---|---|---|---|
| 1 | Add the `[[agent]] name="human", max_active_sessions=0` stanza to `city.toml`; `gc reload`; run §C. | **The `loomington` town repo** (`zookanalytics/loomington`), where `city.toml` is tracked — not gc-toolkit. A PR there, then the operator's `gc reload` (a live town action). | Arms nothing; it *is* the fix. Closes `tk-99sxtg` once §C is clean. |
| 2 (optional) | A gc-toolkit regression that asserts a `gc.routed_to=human` bead does not trip `session-model` once `human` is configured, mirroring `doctor_routed_to_checks_test.go`'s human case, so a future config edit that drops the stanza is caught. | gc-toolkit (or gascity, wherever the doctor test suite lives) | `blocks`-armed on #1; only meaningful after the stanza exists. |
| 3 (only if Alternative B is chosen) | The four-to-six beads in §5, Alternative B. | gc-toolkit board + `lifecycle` + gascity dispatch | A convoy, each `blocks`-armed on the one before; #5-Alt-B(1) and (2) gate the rest. |

Everything above is armed on the operator merging this spec PR: `tk-99sxtg`
waits on `tk-z0k17q`, and no implementation should begin before the model in §5
is accepted.

---

## §C. Operator verification checklist (copy-paste)

A polecat must not reconfigure or reload a live town, so these run at the
operator's convenience after this PR merges. They confirm §4's static verdict.

```bash
cd /home/zook/loomington

# 0. Baseline: the finding exists, and count the population it covers.
#    gc doctor has no per-check flag, and the per-bead finding lines print only
#    under --verbose (default output shows just a count). The run is slow but
#    read-only. Before the fix this prints one or more human stale-routed-config
#    lines; an empty result here is itself a signal — investigate rather than
#    proceed.
gc doctor --verbose 2>&1 | grep 'stale-routed-config:.*human' || echo "NO human stale-routed-config finding — unexpected before the fix; is human already configured, or did the check not run?"
gc bd list --metadata-field gc.routed_to=human --limit 0 --json | jq length          # rig
gc bd list --db /home/zook/loomington/.beads --metadata-field gc.routed_to=human --limit 0 --json | jq length   # city
# Guard for the finding-trade (must stay 0 before adoption):
gc bd list --assignee human --status open,in_progress --limit 0 --json | jq length
gc bd list --db /home/zook/loomington/.beads --assignee human --status open,in_progress --limit 0 --json | jq length

# 1. Add the stanza to city.toml (top level, not under [rigs.imports]):
#      [[agent]]
#      name = "human"
#      max_active_sessions = 0
#    Then reload so the controller re-reads config.
$EDITOR city.toml
gc reload

# 2. PASS 1 — the human finding is gone. "cleared" is reported only when the
#    session-model check actually produced a verdict: a run that errored or
#    timed out prints no finding line either, and must not read as success.
#    `session-model —` (em-dash) is the check's own summary line; a bare
#    `session-model` also matches unrelated bead titles in --verbose output.
DOCTOR_OUT=$(gc doctor --verbose 2>&1)
SM=$(printf '%s\n' "$DOCTOR_OUT" | grep 'session-model —')
if printf '%s\n' "$DOCTOR_OUT" | grep 'stale-routed-config:.*human'; then
  echo "STILL PRESENT — investigate"
elif [ -z "$SM" ] || printf '%s\n' "$SM" | grep -qi -e 'timed out' -e abandoned; then
  echo "INCONCLUSIVE — session-model did not complete (timed out, errored, or absent); raise --check-timeout and re-run"
else
  echo "cleared"
fi

# 3. PASS 2 — nothing named human was spawned. All three must be empty.
gc session list --json | jq -r '.sessions[]? | select((.alias // "")=="human" or (.name // "")=="human" or ((.template // "") | test("(^|[./])human$"))) | .name'
gc agent list --json | jq -r '.agents[]? | select((.qualified_name // .name)=="human") | "\(.qualified_name // .name) active=\(.active_sessions // 0)"'
# expect: the agent is listed as a valid target with active=0, and NO session row.

# 4. PASS 3 — the reserved-word uses of human still work.
gc mail send human -s "config-partition smoke" -m "reserved recipient still resolves" && echo "mail ok"

# 5. PASS 4 — the board is unchanged: the human/visit/parked rows still render.
#    (open the helm board; the 57 visits and the parked anchors still appear.)

# 6. If all pass, close the tracker:
gc bd update tk-99sxtg --append-notes "Resolved by config-partition: [[agent]] name=human, max_active_sessions=0 in city.toml (spec tk-z0k17q). gc doctor session-model clean; no human session spawned; mail + board unchanged."
gc bd close tk-99sxtg   # operator disposition of the origin finding
```

**Fail handling.** If step 2 still shows the finding, `FindAgent` did not match:
confirm the stanza is top-level (bare name, no binding) and that `gc reload`
re-read it. If step 3 shows a spawned session, `max_active_sessions=0` did not
take: confirm the field name and value, and that config validation accepted the
stanza (a rejected stanza is silently not applied).

---

## §D. Residual risks and follow-ups

- **`assignee=human` in the future.** The finding-trade in §4.4 is zero-population
  today. If the operator ever assigns a bead to `human` (as the orphan-sweep
  test contemplates), the configured agent turns that into
  `legacy-token-matches-config-only`. Watch it with the §C guard; the durable
  answer, if it recurs, is the same one core's siblings took — teach that finding
  the `human` exemption — but that is out of scope here and needs no action while
  the population is zero.
- **Town-config ownership.** The declaration lives in `city.toml`, tracked in
  the `loomington` town repo (`zookanalytics/loomington`), not this rig. #6.1 is
  therefore a PR there plus the operator's `gc reload`, not a gc-toolkit bead.
  The live `gc reload` and `gc doctor` steps are §C either way.
- **Config validation of a command-less agent.** Whether `gc reload` accepts an
  `[[agent]]` stanza with only `name` and `max_active_sessions=0` is a runtime
  fact (§C step 1/2). If validation requires a provider or command, add a benign
  one that never runs (the agent never spawns).
- **Not measured live.** No agent was spawned, suspended, or reconfigured for
  this report. Every "does not spawn / does not trade findings / does not break
  mail" claim is derived from the code cited in §Provenance and confirmed only
  when §C is run.
