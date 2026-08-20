---
bead: tk-2qa85
title: Re-aiming tooling-spend controls at the always-on patrol roles
date: 2026-08-20
status: decided
supersedes_assumption: "apply the gc-toolkit.boot mode=on_demand precedent to the five patrol sessions"
---

# Re-aiming tooling-spend controls at the patrol roles

## Summary

The four witnesses and the deacon really are ~75% of city model calls. But the
remedy the bead proposed — the `mode = "on_demand"` patch that retired
`gc-toolkit.boot` — **cannot** reduce it, and neither can anything else in
`city.toml`. The cost is not session *creation*; it is five immortal sessions
each spinning a patrol loop. The only lever is patrol *frequency*, which lives
in a formula default, so this landed as a pack change (explicitly authorised by
the bead: *"unless a pack change is genuinely required"*).

## Baseline

24h window ending 2026-08-20T07:20Z, `kind=model`, from `.gc/usage.jsonl`.
Reproduces the bead's own figures to within rounding.

| role | calls | share |
|---|---:|---:|
| witnesses (4) | 19,905 | 56.9% |
| deacon | 6,273 | 17.9% |
| **combined** | **26,178** | **74.8%** |
| polecats | 6,423 | 18.4% |
| refinery | 1,936 | 5.5% |
| everything else | 446 | 1.3% |
| **TOTAL** | **34,983** | |

Measurement script: `assets/scripts/patrol-spend-split.sh` (committed with this
change so the follow-up window is taken the same way).

## Why `mode = "on_demand"` cannot work here

Each of the five is **one** session, not a respawn loop:

```
gc-toolkit/gc-toolkit.witness      lx-5cv9v   started 2026-08-19T03:48:43Z
gascity/gc-toolkit.witness         lx-vlvay   started 2026-08-19T03:48:41Z
signal-loom/gc-toolkit.witness     lx-n5xi6   started 2026-08-19T03:48:41Z
shutupandlisten/gc-toolkit.witness lx-rf7rk   started 2026-08-19T03:48:44Z
gc-toolkit.deacon                  lx-b14ge   started 2026-08-19T03:48:40Z
```

Over the whole 24h window each worker shows **exactly one** distinct
`session_id` in `usage.jsonl`. `NamedSession.Mode` governs when the controller
*materialises* a session (`internal/config/config.go:467-473`); these were
materialised once, ~28h ago, and have never drained. Setting `on_demand` would
change nothing about the spend and would add a real risk — a patrol that only
starts "when work or an explicit reference requires it" is a patrol that may
not start, and nothing else pours these wisps.

`boot` is not the precedent it looks like. In its own pre-retirement 24h window
boot was **1 session / 23 model calls**. Retiring it removed a respawn-and-idle
watchdog, a different problem with a different shape.

**Disposition for all five: keep `mode = "always"`.** This is a decision, not an
omission — see the block at the end of this file, which is meant for `city.toml`
so the next reader does not re-derive it.

## What is actually load-bearing per cycle

A witness cycle runs: check-inbox, recover-orphaned-beads,
recover-stranded-branches, check-refinery, quiesce-completed-workflows,
detect-stalled-workflows, check-polecat-health, next-iteration. Observed live,
it spends most of that confirming a quiet board (*"Empty refinery queue, and
Step 0 ran clean, so this is genuinely healthy"*).

None of it is redundant, and none of it was removed. Two facts argue the
*frequency*, not the step list, is what was wrong:

1. `check-refinery` is explicitly a **backstop** — the formula says the
   refinery's own idle loop "is the primary owner" and this pass exists for
   "a refinery that is down, quarantined, or never woke". Running a backstop
   every three minutes is not proportionate to the failure it covers.
2. The witness formula already names the lever, and the direction:
   > *"This value sets patrol frequency, which is the dominant cost term once a
   > cycle is cheap — raise it rather than trimming steps if patrol cost needs
   > to come down."*

The liveness-sweep precheck (the model the bead suggested copying) does not
transfer. Its whole value is making an empty board cost **zero sessions**. The
session here already exists and never exits, so a precheck could only sit
*inside* the loop and would still pay for the cycle that evaluates it.

## Measured cycle structure

Cycles were timed from consecutive **live** patrol wisps (leaked wisps ignored —
the deacon carries 25 stale `mol-deacon-patrol` roots, and the witness leaks
occasionally too; neither set marks a cycle boundary). Cycle length varies a
lot with what the board contains, so these are observed ranges from spot samples
on 2026-08-20, not steady-state constants:

| role | wait | observed cycles | implied work |
|---|---:|---|---:|
| witness (gc-toolkit) | 180 s | 285 s, 521 s (n=2) | ~105-341 s |
| deacon | 60 s | 679 s, 839 s (n=2) | ~619-779 s |

Taking the sample means (witness ~403 s, deacon ~759 s) reconciles with the call
counts: 86,400/403 ≈ 214 witness cycles/day at ~31 calls each ≈ 6,540 measured;
86,400/759 ≈ 114 deacon cycles/day at ~55 calls each ≈ 6,273 measured.

The number that matters for this change is not the cycle length but the RATIO
old-cycle to new-cycle, since per-cycle cost is unchanged. That ratio is far
less sensitive to the sample noise than the absolute figures are.

## Why `city.toml` cannot reach the lever

`event_timeout` is a formula var, and `[rigs].formula_vars` is the config
surface for those. It does not apply here:

- The startup pour reads the value out of the **formula's own default** —
  `gc formula show <formula> --json | .vars[].default` — and forwards it as an
  explicit `--var` (`template-fragments/layered-startup-discovery.template.md`).
- `mergeRigFormulaVars` (`internal/sling/sling.go:1131-1155`) skips any key
  already present as an explicit `--var`.

So a `formula_vars` entry would be constructed and then discarded on every pour.
`[[patches.named_session]]` is no help either: its only field is `Mode`
(`internal/config/patch.go:167-177`). Hence the pack change.

One canonical file serves all four witnesses —
`rigs/gc-toolkit/formulas/mol-witness-patrol.toml`; every rig's
`.beads/formulas/` entry is a symlink to it — so one edit covers all four.

## The 600 s ceiling (why not larger)

The wait is one bounded tool call, and the harness caps a single call at 600 s.
Measured directly: `sleep 150` under the default cap returned **rc=143 (SIGTERM)
at exactly 2m00s**. A larger `event_timeout` would therefore not wait longer —
it would be killed mid-wait and silently deliver less pacing than configured,
leaving the number meaningless. Going past 600 s requires making the wait
resumable across calls (persist the deadline, re-enter until it passes), which
is a mechanism change and deliberately not bundled here. Both formulas now say
so at the wait site.

## Dispositions

| # | role | disposition | change |
|---|---|---|---|
| 1-4 | the four witnesses | keep `mode="always"`; slow the patrol | `mol-witness-patrol` `event_timeout` **180 → 600** |
| 5 | `gc-toolkit.deacon` | keep `mode="always"`; slow the patrol **and repair the backoff** | `mol-deacon-patrol` `event_timeout` **60 → 600**, plus the two fixes below |

### The deacon's backoff was partly dead letter

`mol-deacon-patrol`'s `next-iteration` step had two defects that made its
`event_timeout` weaker than it reads:

1. **The pour dropped the var.** It forwarded only `binding_prefix`. A
   `--root-only` pour materialises no defaults, so from cycle 2 onward
   `{{event_timeout}}` arrived unrendered. This is the exact hazard
   `mol-witness-patrol` documents verbatim ("a var that is not passed on this
   line reaches the next wisp unrendered … nothing at all for `event_timeout`")
   and enforces with a test; the deacon had neither.
2. **The wait was a bare `sleep {{event_timeout}}`.** The witness formula
   records the harness refusing exactly this form (*"Blocked: standalone
   sleep 60. To wait for a condition, use Monitor with an until-loop"*), and
   notes a blocked wait removes pacing rather than slowing it.

Both are now fixed by mirroring the witness: the pour forwards
`--var event_timeout`, and the wait is the bounded clock-poll.

### Coupled threshold: `boot-health.sh`

`boot-health` reports the deacon "cold" when its newest patrol wisp is older
than `WISP_FRESH`. The bound is the wisp's **maximum age** — `next-iteration`
pours before waiting, so a wisp lives a full cycle — which at a 600 s wait is
~1,220 s, well past the old 900 s bar. Left alone, this order would have called
a perfectly healthy deacon cold on every cycle. Raised to **3,600 s** (~3 cycles
of margin, the file's own rule). Its stale comment ("cycles every ~4.6 min in
practice") was replaced with the measured figures.

## Predicted effect

Frequency scales as `1 / (work + wait)` and per-cycle cost is unchanged, so the
saving is `1 - (old cycle / new cycle)`. Using the sample means above:

| role | old cycle | new cycle | saving | calls now | calls after |
|---|---:|---:|---:|---:|---:|
| witnesses (4) | ~403 s | ~823 s | ~-51% | 19,905 | ~9,800 |
| deacon | ~759 s | ~1,299 s | ~-42% | 6,273 | ~3,650 |
| **combined** | | | **~-49%** | **26,178** | **~13,450** |
| city total | | | **~-36%** | 34,983 | ~22,250 |

Combined patrol share would fall from 74.8% to ~60%. Treat these as an
order-of-magnitude expectation, not a forecast: cycle length varies with board
contents (n=2 per role), and the saving moves with it. The bead's done-criteria
require a measured follow-up window, which is what settles it.

## What coverage is given up

**No check is removed, and no escalation path changes.** The only thing that
grows is detection latency:

- Witness cycle ~8.7 min → ~15.7 min. Worst-case time to notice an orphaned
  bead, stranded branch, or stalled workflow roughly doubles.
- Deacon cycle ~11.3 min → ~20.3 min, covering inbox, orphaned-process cleanup,
  work-layer health, queue starvation, dog health, Dolt health, diagnostics.
- A genuinely dead deacon is now reported after ~60 min of coldness + the
  existing 30 min `REPORT_AFTER`, instead of ~15 + 30.

This sits inside tolerances the city already runs with: `session.startup_timeout`
is **30m**, and the witness's own `escalation_cooldown` is **24h** — at 600 s the
patrol still takes 144 observations per cooldown window. Dolt health is
additionally covered by `[maintenance.dolt]` and the `boot-health` order.

Nothing here touches the lx-c4hqp blocks, which address backlog growth, a
separate and still-real problem. This adds the missing target rather than
swapping one for the other.

## Activation (this does NOT self-apply)

The running loops forward their **current** `event_timeout` into each next wisp,
so a landed default reaches them only on a fresh startup pour. After this
merges and the rig checkout syncs:

```bash
gc session reset gc-toolkit.deacon
for r in gc-toolkit gascity signal-loom shutupandlisten; do
  gc session reset "$r/gc-toolkit.witness"
done
# then confirm the new value is what startup will read:
gc formula show mol-witness-patrol --json | jq -r '.vars[]|select(.name=="event_timeout").default'
gc formula show mol-deacon-patrol  --json | jq -r '.vars[]|select(.name=="event_timeout").default'
```

## Follow-up measurement (bead done-criterion)

Requires a full 24h window **after** activation — it cannot be taken in the same
session that lands the change. Take it identically:

```bash
assets/scripts/patrol-spend-split.sh            # defaults to the last 24h
```

and append the result to tk-2qa85. If the measured drop is short of the table
above, the next notch is a resumable wait (see the 600 s ceiling section), not a
bigger number.

## Optional: record the decision in city.toml

Behaviour-only-neutral, but it stops the next reader reaching for the boot
precedent. `city.toml` lives in the town repo, not this rig, so it is left for
the operator to paste:

```toml
# Patrol-role spend (tk-2qa85, operator decision 2026-08-20).
#
# The four witnesses + deacon are ~75% of city model calls. Do NOT reach for the
# gc-toolkit.boot `mode = "on_demand"` precedent below: these five are ONE
# long-lived session each (verified — a single session_id per worker across a
# full 24h of .gc/usage.jsonl), so `mode` governs a materialisation that already
# happened and cannot reduce their spend, while on_demand risks a patrol that
# never starts. They are deliberately left at mode = "always".
#
# The lever is patrol frequency: `event_timeout` in mol-witness-patrol /
# mol-deacon-patrol, raised 180->600 and 60->600 there. It is NOT reachable from
# here — the startup pour forwards the formula default as an explicit --var, and
# mergeRigFormulaVars skips keys already passed explicitly.
#
# See rigs/gc-toolkit/specs/tk-2qa85/patrol-cadence-reaim.md.
```
