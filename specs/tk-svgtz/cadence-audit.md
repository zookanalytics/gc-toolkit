---
name: City Cadence Audit (tk-svgtz)
description: Full inventory of every recurring clock in the loomington city — what triggers it, whether the trigger mechanism is right, and whether the interval is justified — with measured evidence for the merge cadence in particular. Findings and recommendations only; deletes nothing.
---

# City Cadence Audit

## Scope

**Mandate.** Answer, for the whole city, how many independent clocks are
running, what starts each one, whether the trigger mechanism is the right
one, and whether the interval is justified. Merge cadence first.

**Boundaries.** This is an audit. It produces findings and a
recommendation and changes no behaviour. Ring 1 teardown of the
out-of-band merge driver is tk-d83wm and is not performed here.
Where this report contradicts the commissioning bead's premises, the
correction is stated with its evidence — the premises were the reason to
look, not the finding.

## Method and evidence window

Everything below is measured on the live city, not inferred from
documentation.

| Source | Window | Volume |
|---|---|---|
| `gc order list --json`, order TOML, `gc order history` | live, 2026-08-20T04:2xZ | 36 live registrations |
| `internal/orders`, `cmd/gc/order_dispatch.go`, `cmd/gc/order_store.go`, `cmd/gc/dispatch_runtime.go` in `rigs/gascity` | HEAD | scope/exec/gate semantics |
| `/tmp/gc-refinery-idle-gc-toolkit/reconcile.log` | 2026-08-12T09:44Z → 2026-08-20T04:17Z (186.6 h) | 5,032 driver ticks |
| `.gc/usage.jsonl` | last 24 h and 7 d | 32,429 / 54,849 model calls |
| `systemctl --user`, `/proc`, `ps` | live | unit CPU, cgroups, orphans |
| `git merge-base upstream/main origin/main` in `rigs/gascity` | HEAD | fork-vs-upstream attribution |

Reproduction commands are in the [appendix](#appendix-reproduction).

---

## 1. The inventory: every clock in the city

There are **five distinct cadence mechanisms**, not one. Only the first
is what "cadence in this city" usually means, and it is not where the
cost is.

### 1.1 Controller-dispatched orders — 36 live registrations

The controller evaluates every order's trigger on its own tick
(`[daemon] patrol_interval = "30s"` in `city.toml`). A cooldown interval
is therefore a *minimum*, not a period (see [F7](#f7)).

| Pack | Order | Trigger | Interval | Kind | Scope |
|---|---|---|---|---|---|
| dolt | dolt-health | cooldown | 30s | exec | city¹ |
| dolt | dolt-remotes-patrol | cooldown | 15m | exec | city¹ |
| dolt | mol-dog-backup | cooldown | 6h | exec | city¹ |
| dolt | mol-dog-compactor | cooldown | 2h | exec | city¹ |
| dolt | mol-dog-doctor | cooldown | 5m | exec | city¹ |
| dolt | mol-dog-phantom-db | cooldown | 1h | exec | city¹ |
| core | beads-health | cooldown | 30s | exec | city¹ |
| core | gate-sweep | cooldown | 30s | exec | city¹ |
| core | order-tracking-sweep | cooldown | 1m | exec | city¹ |
| core | cross-rig-deps | cooldown | 5m | exec | city¹ |
| core | nudge-mail-sweep | cooldown | 5m | exec | city¹ |
| core | orphan-sweep | cooldown | 5m | exec | city¹ |
| core | renudge-stale-human-gates | cooldown | 5m | exec | city¹ |
| core | spawn-storm-detect | cooldown | 5m | exec | city¹ |
| core | reaper | cooldown | 30m | exec | city¹ |
| core | wisp-compact | cooldown | 1h | exec | city¹ |
| core | prune-branches | cooldown | 6h | exec | city¹ |
| core | cascade-nudge-on-blocker-close | event `bead.closed` | — | exec | city¹ |
| core | notify-on-human-gate-creation | event `bead.created` | — | exec | city¹ |
| core | nudge-on-route | event `bead.updated` | — | exec | city¹ |
| gastown | digest-generate | cooldown | 24h | formula → dog | city¹ |
| gc-toolkit | boot-health | cooldown | 2m | exec | `city` |
| gc-toolkit | quota-park-nudge | cooldown | 3m | exec | `city` |
| gc-toolkit | reconcile-rig-checkouts | cooldown | 15m | exec | `city` |
| gc-toolkit | feedback-miner ×4 rigs | cooldown | 48h | formula → pool | `rig` |
| gc-toolkit | liveness-sweep ×4 rigs | condition | — | formula → pool | `rig` |
| gc-toolkit | triage-recurrence ×4 rigs | cooldown | 24h | formula → pool | `rig` |

¹ Registered city-wide with **no `scope` key at all** — see [F1](#f1).
This is not the same thing as `scope = "city"`.

**Registered but disabled** by `[[orders.overrides]]` in `city.toml`:
`doc-keeper-drift-audit`, `doc-keeper-memory-audit`, `feedback-distiller`
(4 rigs each = 12 registrations). **Skipped** by `[orders] skip`:
core's `jsonl-export` (via `skip_aliases = ["mol-dog-jsonl"]`) and the
dolt pack's `mol-dog-stale-db`.

**Cost:** near zero. Every one of these but four is an exec script.

### 1.2 Controller-owned in-process loops

| Loop | Cadence | Cost (measured) |
|---|---|---|
| `gc supervisor run` — order tick | 30s (`patrol_interval`) | 26.5% CPU sustained |
| `gc convoy control --serve --follow <rig>/core.control-dispatcher` ×4 | event-driven; **1s → 5s idle re-poll**; 100 ms ×3 drain retry | ~6.3% CPU each, ~25% total |

The control dispatchers are the **fastest clock in the city**. They are
nominally event-driven, but `cmd/gc/dispatch_runtime.go:62` documents why
they cannot be: *"a worker that closes a step bead with a raw bd write
does not publish a city BeadClosed event, so the control-dispatcher only
notices the next ready step on its idle re-poll."* The idle cap was
lowered 30s → 5s to hide that, at the cost of a permanent per-rig store
scan every 1–5 s.

### 1.3 Agent session loops — where the model spend actually is

Seven named sessions run `mode = "always"` + `wake_mode = "fresh"`, which
means they restart with fresh context after every drain. Their period is
one full agent turn plus the patrol formula's own sleep var:

| Session | Sleep var | Default | Model calls, last 24 h |
|---|---|---|---|
| `gc-toolkit/gc-toolkit.witness` | `mol-witness-patrol` `event_timeout` | 180 s | 5,992 |
| `gascity/gc-toolkit.witness` | ″ | 180 s | 4,555 |
| `signal-loom/gc-toolkit.witness` | ″ | 180 s | 4,381 |
| `shutupandlisten/gc-toolkit.witness` | ″ | 180 s | 2,952 |
| `gc-toolkit.deacon` | `mol-deacon-patrol` `event_timeout` | 60 s | 5,589 |
| `gc-toolkit.mayor` | — | — | 170 |
| `gc-toolkit.mechanik` | — | — | 8 |

Against a 24 h total of **32,429 model calls**: witnesses **55%**, deacon
**17%**, **72% together**. Polecats — the agents doing the work — are
6,923 calls, **21%**.

### 1.4 Cadences running outside the controller

| Thing | What starts it | Cadence | Status |
|---|---|---|---|
| `gc-refinery-idle-{gascity,gc-toolkit,shutupandlisten,signal-loom}.service` | hand-armed via `assets/scripts/refinery-idle-arm.sh` into a transient systemd `--user` unit | `sleep 60` (observed median **114 s**) | live, 4 units |
| `/var/tmp/gc-int-env-*/bin/gc-drift supervisor run` ×3 | leaked from `gc` integration tests | supervisor tick | **orphaned 18 h+, cwd deleted** |
| `dolt sql-server` | auto-started by whichever process calls `gc bd` first | n/a (long-lived) | **inside `gc-refinery-idle-signal-loom.service`'s cgroup** |

The four merge drivers are transient units: they exist only in
`/run/user/1000/systemd/transient/`, execute a script in `/tmp`, and a
city shutdown does not stop them. `gc status` does not list them.

### 1.5 Config-level clocks

`city.toml`: `[daemon] patrol_interval = 30s`, `wisp_gc_interval = 30m`,
`wisp_ttl = 8h`, `restart_window = 1h`, `shutdown_timeout = 60s`;
`[session] setup_timeout = 60s`, `startup_timeout = 30m` (a documented
tourniquet); `[beads.policies.order_tracking] delete_after_close = 30m`;
`[events.rotation] archive_retain_age = 168h`;
`[maintenance.dolt] interval = 24h`; `[[service]] helm` (`proxy_process`,
health-polled). Plus the `liveness-sweep` window carried as
`LIVENESS_SWEEP_INTERVAL=86400` in an `[[orders.overrides]] check` prefix
because a `condition` trigger ignores `interval`.

---

## 2. Corrections to the commissioning premises

Three of tk-svgtz's stated premises do not survive checking. Each was a
good reason to look; none is a finding.

### 2.1 "Every one of core's 13 orders is `exec` + `scope = "city"`"

Core ships **15** orders (not 13 — `notify-on-human-gate-creation` and
`renudge-stale-human-gates` are newer), of which 14 are live. All are
indeed `exec`. **None of them declares `scope` at all.**

The distinction is load-bearing, because the default is not what the
Go doc comment says. `internal/orders/order.go:31-35` claims *"'rig' (the
default when empty) registers it once per importing rig"*, but
`internal/orderdiscovery/discovery.go:80-127` only drops the unbound
city-pass registration for orders where `DeclaresRigScope()` is literally
true. An empty-scope order **keeps its city-pass registration** — which is
why every core order shows `RIG = -` in `gc order list`.

The consequence is invisible for core (a bootstrap pack, city layer only)
and real for any pack a rig imports: an empty-scope order there registers
*both* unbound *and* once per importing rig. Declaring `scope` is not
decoration; leaving it off is what the guard at
`discovery.go:196` exists to clean up after.

### 2.2 "Upstream's mol-refinery-patrol does not sleep at all"

The fork's `mol-refinery-patrol.toml` **does** sleep:
`[vars.event_timeout] default = "60"`, described as *"Seconds to sleep
before re-checking for work. Replaces former event-watch loop which
hot-spun on cache-reconcile firehose."* The 60 s idle cadence the
out-of-band driver implements is the formula's own contract, not a
deviation from it — `mol-refinery-patrol.toml:391` names
`sleep {{event_timeout}}` a *"cadence contract, not an implementation"*
and explicitly sanctions an out-of-band driver for harnesses that block
foreground `sleep`.

There is no upstream `mol-refinery-patrol` to compare against at all
(next point), so "upstream does not sleep" has no referent.

### 2.3 "The merge machinery has no upstream counterpart"

True, and verified: zero hits for all seven pass names across
`upstream/main` (gastownhall/gascity at `af85466e7`). But the reason
matters. **Upstream ships no production refinery.** Its only refinery
artifacts are under `examples/` and `test/`. There is no upstream merge
queue that 24.6k lines is 24.6k lines *more than*.

Separately, the fork has added **no order and no order-schema change** to
core: `merge-base..origin/main` touches only 5 core scripts and 2 core
formulas under `internal/bootstrap/packs/core/`. The core order set is
upstream's, unmodified.

So the correct framing of the 24.6k figure is not "the fork
re-implemented something upstream does in less". It is "the fork built a
gated merge queue that upstream does not have, and nobody has since asked
which parts of the gate still pay for themselves". That question is
answerable, and [§4](#4-merge-cadence-what-is-load-bearing) answers it
with measurements.

---

## 3. Answers to the five questions

### Q1. Full inventory — done, [§1](#1-the-inventory-every-clock-in-the-city).

Five mechanisms: controller orders (36), controller in-process loops (5),
always-on agent session loops (7), out-of-band systemd drivers (4, plus 3
orphans), and config-level timers. The commissioning bead counted the
first category only, which is the one that costs nothing.

### Q2. Is each trigger mechanism right? Should any pool order be exec?

The six pool orders split cleanly.

| Order | Needs LLM judgment? | Verdict |
|---|---|---|
| `liveness-sweep` | narration, yes; detection, no | **already correct.** `trigger = "condition"` with an exec precheck; the empty board costs no session. This is the model the other five should follow. |
| `triage-recurrence` | no for the gate, yes for the visit | **should gain a precheck.** "Does this triage subject have candidates in scope and no open visit?" is two bead queries. Fires 4×/day city-wide to answer it with a model. |
| `feedback-miner` | yes | **keep as pool.** Judging whether a PR comment is corrective feedback about standing behaviour is the judgment. Note `city.toml` already documents that it has no precheck and every fire spawns a session. |
| `feedback-distiller` | yes | **keep as pool** (currently disabled). Its own first step is a mechanical gate, per its header; that gate is a precheck living inside the session that the precheck should have avoided. |
| `doc-keeper-drift-audit` | yes | keep as pool (disabled since 2026-06-19). |
| `doc-keeper-memory-audit` | yes | keep as pool (disabled since 2026-06-19). |

So: **one order (`triage-recurrence`) should move behind an exec
precheck**, and one (`feedback-distiller`) would benefit from lifting its
internal gate out into one. That is the whole of the "convert pool back to
exec" opportunity — the fork has not, in fact, been broadly converting
orders into agent dispatch. Three of its nine orders are exec + city, and
of the six pool orders, four genuinely need a model and one is already
gated.

The far larger conversion opportunity is not an order at all: it is the
four witness sessions and the deacon ([F5](#f5)).

### Q3. Is `exec` + `scope = "rig"` supported?

**Yes, fully.** No example exists in core or this pack, but the code path
is complete and unambiguous:

- **Validation permits it.** `internal/orders/order.go:284-289` accepts
  `scope` ∈ {`""`, `"city"`, `"rig"`} independent of exec/formula. The
  only exec-related refusal is `exec` + `pool`
  (`order.go` `Validate`: *"exec orders cannot have a pool"*), because
  exec bypasses the agent pipeline.
- **Registration binds it per rig.**
  `orderdiscovery.discovery.go` drops the unbound city-pass copy and
  stamps `aa[i].Rig = rigName` for each importing rig.
- **The store target resolves to the rig.**
  `cmd/gc/order_store.go:resolveOrderStoreTarget` — with `a.Rig` set and
  `a.Pool` empty (which exec guarantees), it returns
  `ScopeRoot = rig.Path`, `ScopeKind = "rig"`, `RigName = rig.Name`.
- **The environment is rig-scoped.**
  `orderExecEnvWithError` then sets `BEADS_DIR` from
  `bdRuntimeEnvForRigWithError`, plus `GC_RIG`, `GC_RIG_ROOT`,
  `GC_STORE_ROOT`, `GC_STORE_SCOPE=rig`, `GC_BEADS_PREFIX`, and
  `BEADS_ACTOR=order:<name>`.
- **The working directory is the rig root.**
  `order_dispatch.go:1407` — `m.execRun(ctx, a.Exec, target.ScopeRoot, env)`.

There is already a live proof-of-concept in this pack, one field over:
`liveness-sweep` is `scope = "rig"` and its `check` command is an exec
script that the controller runs **once per importing rig**, which is
precisely why the script keys its state by `GC_RIG` (its order header
spells out the coupling). A rig-scoped `exec` is the same runner with the
same env.

**Two cautions for tk-d83wm:**

1. `GC_PACK_STATE_DIR` is scoped to **CITY + PACK**, not city + pack +
   rig. A rig-scoped exec order that writes state there must key its own
   files by `GC_RIG` or the first rig silences the rest.
2. Derive per-rig values *inside* the script from `GC_RIG`. There is no
   `vars` channel on a rig-scoped order — `orders.Override` has no vars
   field, as `city.toml`'s feedback-miner block already documents.

### Q4. Does the controller serialise cooldown orders?

**Yes, per `(order, rig)` — and it is a real single-writer guarantee, with
one flag that voids it.**

The mechanism is a tracking bead, not a lock file:

- The scoped key is `Order.ScopedName()` — `name` for a city
  registration, `name + ":rig:" + rig` for a rig-scoped one
  (`order.go:120-125`). Per-rig registrations therefore serialise
  independently of each other, which is what a per-rig merge driver wants.
- Before dispatch, `order_dispatch.go:676` runs the open-work gate
  (`trackingIndex.hasOpenWork`). An **open** tracking bead for that scoped
  name means in-flight; the tick skips (`order_dispatch.go:689`).
- The tracking bead is created **before** the exec launches
  (`launchResolvedDispatch`), so the window between "decided to run" and
  "is running" is already covered.
- `TimeoutOrDefault()` is **300 s for exec**, so a wedged run cannot hold
  the gate open forever.
- Orphaned tracking beads from a dead controller are swept at startup
  (`sweepOrphanedOrderTracking`).

**The flag that voids it:** `idempotent = true`. On an open-work gate
*timeout*, `gateFailClosed` returns `false` for an idempotent order and
logs *"open-work gate failed but order is idempotent; dispatching anyway
(#2893)"* (`order_dispatch.go:2342-2345`). That is a deliberate trade of
single-flight for liveness. `no_work_gate = true` disables the gate
outright; its own doc says *"Single-flight is the author's
responsibility."* **A replacement merge order must set neither.** Note
that this pack's `boot-health` does set `idempotent = true` — correctly,
since it is a read-only report.

Given that, the driver's `flock` has no counterpart to preserve: the
tracking-bead gate is strictly stronger, because it survives the
controller restart that would drop an flock, and it is visible in the
ledger.

### Q5. Merge cadence — how much of the 24.6k lines is load-bearing?

Answered with measurements in [§4](#4-merge-cadence-what-is-load-bearing).
Short version: the *cadence* is not load-bearing at 60 s — 92.5% of ticks
do nothing. Of the *code*, two passes carry essentially all of the
observed value, one has never fired at all, and one has 13 of 18
capabilities that did not fire once in eight days.

---

## 4. Merge cadence: what is load-bearing

### 4.1 The 24,654 lines, reproduced

| Pass | Code | Test | Total |
|---|---:|---:|---:|
| check-set-heal | 3,140 | 4,997 | 8,137 |
| reconcile-merged-prs | 2,409 | 3,667 | 6,076 |
| merge-skill | 2,079 | 3,171 | 5,250 |
| pre-open-resolve | 814 | 948 | 1,762 |
| reconcile-gate-verdicts | 954 | 636 | 1,590 |
| reconcile-graduated-convoys | 441 | 637 | 1,078 |
| reconcile-refinery-handoffs | 420 | 341 | 761 |
| **Total** | **10,257** | **14,397** | **24,654** |

The bead's figure is exact. Test lines are 1.40× code. The seven passes
are **44% of the pack's entire 56,300-line `assets/scripts` layer**.

### 4.2 What each pass actually did, over 5,032 ticks / 186.6 hours

Counters below are true summary-line event counters, not gauges.

| Pass | Ticks it ran | Ticks it acted | Act rate | What it did |
|---|---:|---:|---:|---|
| reconcile-merged-prs | 5,028 | 256 | 5.09% | 3 stale-base rebases routed, 3 resolved holds cleared, **1 bead closed** |
| pre-open-resolve | 1,178 | 39 | 3.31% | **38 PRs opened**, 2 flipped |
| merge-skill | 4,360 | 33 | 0.76% | **41 merges** (40 distinct squash SHAs) |
| reconcile-gate-verdicts | 5,007 | 32 | 0.64% | 30 fixable verdicts, 1 exception, 1 escalation, 1 gate re-armed |
| check-set-heal | 5,008 | 17 | 0.34% | 16 signoffs dispatched, **1 heal** |
| reconcile-graduated-convoys | 5,031 | 25 | 0.50% | 1 convoy graduated |
| reconcile-refinery-handoffs | 4,693 | **0** | **0.00%** | **nothing, ever** |

**Any pass acting at all: 380 of 5,032 ticks — 7.55%.** The other 92.45%
of the cadence is pure polling.

### 4.3 Which capabilities have never fired

`reconcile-merged-prs` (6,076 lines) reports 18 summary counters. **Thirteen
were zero for the entire window**: abandoned/escalated, retargeted, rebases
held, stale-gate re-reviews routed, stale-gate re-reviews held, superseded
reviews retracted, retractions held, foreign-PR identity holds,
identity-encoding forced closes, wedged-close escalations, partial closes,
doctor-gate indeterminate, unowned open PRs.

Its headline job — closing a bead whose PR merged out-of-band — fired
**once**. That is not evidence it is useless; merge-skill closes beads on
its own landing path, so this pass is the *reconciler for the exceptional
case*, and the exceptional case happened once. It is evidence that a
6,076-line reconciler is sized for a failure surface that is not being
exercised.

`reconcile-refinery-handoffs` (761 lines) produced 4,693 identical
all-zero lines and repaired nothing. On top of that it **could not read
its own inputs on 338 ticks (6.7%)** and fail-safed.

`check-set-heal` — the largest pass at 8,137 lines — healed **once**. Its
live contribution is dispatching signoffs (16), which is a small,
well-defined slice of it.

### 4.4 The cadence is not what it says

- Declared `INTERVAL=60`. **Observed median tick period 114 s**, mean
  116 s, p90 168 s. The passes take ~54 s median; the sleep is the smaller
  half of the period. The interval is not the cadence — the pass duration
  is.
- The driver was **dead for 25.4 h of the 186.6 h window (13.6%)**,
  including a **13.4-hour** and a **9.5-hour** outage. Over the same
  window 59 PRs merged but merge-skill accounts for 41; the gap is work
  that landed while the driver was down.
- Reading the store or GitHub fails routinely at this rate: session roster
  unreadable on **337 ticks (6.7%)**, open-handoff enumeration unreadable
  on **338 (6.7%)**, PR review history unreadable on **421 (8.4%)**, `gh
  pr view` failed on 264, GitHub 503 on 11. Every one is fail-safe — the
  arm silently disables for that pass and nothing escalates. So on roughly
  **1 tick in 15, merge-safety arms are off and no one is told.**

### 4.5 Cost

Unit CPU since arming (2026-08-19 07:52 → 2026-08-20 04:19, ~20.5 h):

| Unit | CPU | % of one core |
|---|---:|---:|
| gc-refinery-idle-gascity | 3.53 h | 17.2% |
| gc-refinery-idle-gc-toolkit | 4.50 h | 21.9% |
| gc-refinery-idle-shutupandlisten | 3.68 h | 17.9% |
| gc-refinery-idle-signal-loom | 25.81 h | 125.7%¹ |

¹ Inflated because `dolt sql-server` lives in this unit's cgroup. The
three clean drivers alone are **~57% of one core, permanently, to do
something on 7.55% of ticks.**

---

## 5. Findings

<a id="f1"></a>
### F1 — `scope` unset ≠ `scope = "city"`, and the doc comment says the wrong thing

`internal/orders/order.go:31-35` documents the empty default as
rig-scoped; registration treats it as city-scoped by keeping the
city-pass copy (`orderdiscovery/discovery.go`). For a pack on the city
layer only (core) the two readings coincide. For a pack rigs import, an
empty-scope order registers **both** unbound and per-rig. Every order in
this pack that is meant to be per-rig therefore *must* say
`scope = "rig"` — and does. The Go comment is the defect.

<a id="f2"></a>
### F2 — The merge cadence polls 13× more often than it acts, at ~57% of a core

7.55% of 5,032 ticks did anything. Median period 114 s against a declared
60 s. Three drivers cost 57% of a core continuously; the fourth's cost is
unmeasurable because it is hosting the database.

<a id="f3"></a>
### F3 — The out-of-band driver was dead 13.6% of the last eight days

Two outages (13.4 h, 9.5 h) plus six shorter gaps. The pack carries a
460-line arming script and a 393-line doctor check whose sole purpose is
to notice this, and it still happened twice in one window. That is the
strongest available argument for tk-d83wm: the durability problem is not
fixed by better arming, it is fixed by not owning the lifetime.

<a id="f4"></a>
### F4 — Dolt has no durable owner, and cgroup membership is why

Live now: `dolt sql-server` PID 1732746 in
`/user.slice/…/gc-refinery-idle-signal-loom.service`. Its parent chain is
`dolt → gc __gc-managed-dolt-scope-watchdog (1732734) → systemd (1273)`.
Reparenting to systemd did **not** move it out of the unit's cgroup —
cgroup membership is inherited at fork and survives reparenting. So
`systemctl --user restart gc-refinery-idle-signal-loom.service`, the
documented way to re-arm a driver, kills the city store. Which unit is
fatal changes every time dolt restarts (three different owners recorded
on this bead so far). `gascity-supervisor.service` is now active and
still does not own dolt.

<a id="f5"></a>
### F5 — The dominant cadence in the city is agent patrol sessions, and the precedent for fixing it already landed

72% of the last 24 h of model calls came from four witnesses and one
deacon. Polecats — the agents doing work — were 21%.

This is exactly the problem `boot-health` was written to solve, and the
fix worked: `gc-toolkit__boot` ran 18,278 lifetime model calls (2,000–5,900
per day at the end), last called **2026-08-09**, and is now **zero**. The
detection half became a 2-minute exec order at no model cost. Four
witnesses and a deacon are the same shape — `mode = "always"` +
`wake_mode = "fresh"` + a patrol formula whose steps are mostly mechanical
reads — and have not had the same treatment.

The boot-health header is worth re-reading here: it also documents
*why the escalation half was deliberately left out* (a nudge costs more
context than the cycle it interrupts; 4 of 5 nudges never landed against a
`wake_mode = "fresh"` target). Any witness conversion inherits that
constraint.

<a id="f6"></a>
### F6 — The fastest clock in the city exists because agents bypass the event bus

Four `gc convoy control --serve` loops poll every 1–5 s per rig (~25% of a
core total) because, per `dispatch_runtime.go:62`, *a step bead closed
with a raw `bd` write publishes no city event*. The idle cap was cut 30 s
→ 5 s to hide the resulting per-hop latency. The event-driven design is
correct; the polling fallback is compensation for writers that do not
emit. Fixing the emit side would let the cap go back up.

<a id="f7"></a>
### F7 — Declared interval systematically understates real cadence

Cooldown is a floor evaluated on a 30 s controller tick, so observed
periods run 20–100% long: `boot-health` 2m → ~3.5m observed;
`quota-park-nudge` 3m → 3.8–6.3m; `mol-dog-doctor` 5m → 5.5–6.6m;
`reconcile-rig-checkouts` 15m → 15.2–17.9m. Nothing is wrong — but
"interval" in an order file is not a period, and tuning spend by editing
it is less precise than it looks.

<a id="f8"></a>
### F8 — Three orphaned test supervisors have been running for 18+ hours

`/var/tmp/gc-int-env-{333725245,392238169,1716150665}/bin/gc-drift
supervisor run`, PPID 1273, cwd deleted. 25 leaked `gc-int-env-*` trees,
116 MB. They are idle (0.0% CPU) but they are supervisors — processes
whose job is to dispatch orders — surviving the tests that made them, in
the same user scope that captured dolt. In scope for "anything running
outside the controller."

<a id="f9"></a>
### F9 — Read failures at this poll rate are silently converted into disabled safety arms

337 ticks could not read the session roster; 338 could not enumerate open
handoffs; 421 could not read PR review history. Each fail-safes correctly
— and logs to a file nobody reads. The design is right; the *reporting* is
missing. At 6.7–8.4% these are not rare events.

<a id="f10"></a>
### F10 — Half the merge machinery's capability surface is untested by production

13 of 18 `reconcile-merged-prs` counters, and all 3 of
`reconcile-refinery-handoffs`, were zero across 186.6 hours. Code that
never runs is code whose correctness rests entirely on its unit tests —
which, at 1.40× code, is where 14,397 of the 24,654 lines already are.

---

## 6. Recommendations

Ranked by (value ÷ risk). Nothing here deletes anything; each is a
separately-filable change.

1. **Replace the four out-of-band drivers with one rig-scoped exec
   order** (tk-d83wm's job — this audit clears its blocker). `exec` +
   `scope = "rig"` is supported, sets `GC_RIG`/`BEADS_DIR`/cwd correctly,
   and its tracking-bead gate is a stronger single-writer guarantee than
   the flock. Set neither `idempotent` nor `no_work_gate`. Key any
   `GC_PACK_STATE_DIR` state by `GC_RIG`. This also resolves [F3](#f3) and
   removes the cgroup that currently captures dolt ([F4](#f4)).
2. **Raise the merge cadence from 60 s to 120–180 s.** Observed period is
   already 114 s, so this mostly makes the real cadence honest; at 7.55%
   action rate the latency cost is small and the CPU saving is direct.
   Cheap, reversible, and independent of recommendation 1.
3. **Give dolt a durable owner** ([F4](#f4)). `gascity-supervisor.service`
   exists and is running. Until dolt starts inside it, any unit restart is
   a coin flip on the city store.
4. **Apply the boot-health pattern to the witness patrol** ([F5](#f5)).
   The detection half of a witness cycle is mechanical; 55% of the city's
   model calls are witnesses. Honour the boot-health header's finding that
   the *escalation* half cannot simply be nudged.
5. **Put `triage-recurrence` behind an exec precheck**, exactly as
   `liveness-sweep` is. Its gate is two bead queries.
6. **Surface the read-failure rate** ([F9](#f9)). A counter and one
   escalation threshold; the fail-safe behaviour itself is correct.
7. **Reap the orphaned test supervisors and `gc-int-env-*` trees**
   ([F8](#f8)), and find out why integration tests leak supervisors.
8. **Fix the Go doc comment on `Order.Scope`** ([F1](#f1)) — one comment,
   prevents the next reader from shipping an unbound registration.
9. **Before trimming the merge machinery, instrument rather than delete.**
   [F10](#f10) says 13 counters never fired; it does not say they are
   dead. The cheap next step is to keep the counters and revisit in a
   window that includes a rebase storm and a rejected merge.

## What this audit did not do

No file outside `specs/tk-svgtz/` was changed. No order, formula, unit,
or script was edited, disabled, or removed. The orphaned test supervisors
in [F8](#f8) were left running.

---

## Appendix: reproduction

```bash
# Order inventory (note: --json omits `scope`; read the TOML for that)
gc order list
gc order list --json | jq -r '.orders[] | [.name,(.rig//"-"),.trigger,(.interval//"-")] | @tsv'
gc order history <name> --limit 5

# Scope / exec / gate semantics (in rigs/gascity)
sed -n '190,215p;280,295p' internal/orders/order.go        # scope docs + Validate
sed -n '80,215p'          internal/orderdiscovery/discovery.go
sed -n '126,175p'         cmd/gc/order_store.go            # resolveOrderStoreTarget
sed -n '660,700p;1400,1410p' cmd/gc/order_dispatch.go      # open-work gate; execRun cwd
sed -n '2337,2347p'       cmd/gc/order_dispatch.go         # gateFailClosed / idempotent
sed -n '42,75p'           cmd/gc/dispatch_runtime.go       # serve poll + idle cap

# Fork-vs-upstream attribution
MB=$(git merge-base upstream/main origin/main)
git diff --stat "$MB"..origin/main -- internal/bootstrap/packs/core/
git ls-tree -r upstream/main --name-only | grep -c merge-skill   # 0

# Merge-cadence measurements (5,032 ticks)
L=/tmp/gc-refinery-idle-gc-toolkit/reconcile.log
grep -c '^---- tick' "$L"
grep -o 'merge-skill: [0-9]* merged' "$L" | awk '{s+=$2} END{print s}'
grep -c 'FAIL-SAFE the live session roster could not be READ' "$L"
python3 specs/tk-svgtz/passrate.py "$L"   # per-pass action rates
python3 specs/tk-svgtz/counters.py "$L"   # per-counter totals (summary lines only)

# Cost and ownership
systemctl --user show gc-refinery-idle-<rig>.service -p CPUUsageNSec -p ActiveEnterTimestamp
cat /proc/$(pgrep -f 'dolt sql-server' | head -1)/cgroup
ps -eo pid,ppid,etimes,args | grep gc-drift

# Model-call spend
NOW=$(date +%s000); jq -r --argjson d1 $((NOW-86400000)) \
  'select(.at >= $d1) | .worker' "$GC_CITY_PATH/.gc/usage.jsonl" \
  | sed 's/-lx-[a-z0-9]*$//' | sort | uniq -c | sort -rn
```
