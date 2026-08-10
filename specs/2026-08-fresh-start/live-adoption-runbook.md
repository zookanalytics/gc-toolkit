---
name: Runbook — live adoption of the fresh-start branch (city idle)
description: The five-step city-side list that gives the branch its runtime evidence — point the rig at the branch, spine smoke, create triage subjects, watch one sweep and one recurrence cycle, optionally enable the intake default. Each step is one command plus observation; paste outputs back and the findings ledger absorbs them.
---

# Runbook: live adoption (city idle)

Run in the active city with the rig quiesced. Each step is one command
plus a stated expectation; anything that deviates is a finding, not a
detour to fix silently. Paste outputs back in whatever form is cheapest.

## 0. Point the rig at the branch

Check out `claude/gc-toolkit-fresh-start-ehvljb` in the gc-toolkit rig
checkout (or merge the PR and pull main — either works; the branch is
self-contained). **If the city previously imported this pack under a
different binding key or subpath** (e.g. `[rigs.imports.gc-next]` →
`packs/gc-next/`): the pack now lives at the repo root and the binding
key must be renamed to `gc-toolkit` — repointing `source` alone loads
but silently mis-wires the orders' bare pool names (validator F-01).
Also drop any `default_sling_formula` naming a formula this branch
doesn't ship. Then:

```sh
gc import install   # refreshes packs.lock for remote imports (F-04)
gc doctor
```

**Expect:** the new `check-liveness-sweep-wired` passes; no new
failures beyond pre-existing ones. The two new orders register on the
next `gc` start — and because both formulas are graph.v2, their
compiled roots are Ready-visible, so a cold scale-from-zero polecat
pool wakes for them (F-20's fix).

## 1. Spine smoke (Phase 0/1 evidence — the one that matters most)

Pick any real open bead as `$SUBJECT`, then file a visit with the raw
canonical lines:

Pick an **unblocked, un-arrested** bead for the smoke (a blocked one
works too — that's F-06's fix with the tracks edge — but keep the first
smoke simple). Note the pool is hard-coded rig-qualified: an operator
shell has no `GC_RIG`, and the `${GC_RIG:+…}` form from the formulas
expands bare there, which routes nowhere (validator F-05).

```sh
SUBJECT=<any-real-open-bead-id>
RIG=gc-toolkit                         # your rig name
POOL="$RIG/gc-toolkit.converse"        # MUST be rig-qualified (F-05)
VISIT=$(gc bd create -t task --title "visit: $SUBJECT — spine smoke: say hi and hold" \
  -d "Spine smoke test: rebuild this subject's slice, say what you see, and hold." --json | jq -r '.id // .[0].id')
gc bd update "$VISIT" --set-metadata "gc.routed_to=$POOL" \
  --set-metadata "gc.continuation_group=$SUBJECT" \
  --set-metadata "task_kind=visit"
gc bd dep add "$VISIT" "$SUBJECT" --type=tracks   # tracks, not parent-child (F-06)
```

**Expect, in order:** (1) a converse session spawns with no further
keystroke; (2) it renames itself to the subject (`gc session list` —
this is tk-h9pq5's one unproven integration, Phase 0); (3) it holds
`in_progress` with the subject's state summarized and a trailing "Next
(yours):" line. Say anything to it; **expect** your exchange's outcome
appended to the subject's notes, `gc.outcome` stamped on the visit, the
visit closed. **Drain nuance (validated, F-10):** the session drains
only when NO visit is claimable anywhere in the rig — a successful
cross-group claim is authoritative, so with a visit backlog the session
re-claims other subjects instead of draining. So: warm continuity =
file a second visit while any converse session lives and **expect an
existing session to absorb it and re-title** (F-12, confirmed); cold
continuity = wait for the pool to empty (or quiesce the visit queue),
then file another and **expect a fresh session that answers a
pre-seeded question about the subject from the record alone**.

## 2. Create one or two triage subjects

```sh
gc bd create -t task --title "triage: held ideas (gc-toolkit)" \
  -d "Triage scope: open, unassigned, unrouted idea/backlog beads in this rig that no formula owns. Each visit: enumerate the scope, rank ripeness, frame promote / park / kill per candidate."
gc bd update <id> --set-metadata "task_kind=triage-subject" \
  --set-metadata "triage.scope=unrouted"
```

`triage.scope` is the machine-readable filter the recurrence formula
evaluates (defined token schema in `formulas/mol-triage-recurrence.toml`
step 2: `p<=N`, `label:X`, `kind:X`, `unrouted`); the body prose is for
the sitting. A subject without recognized tokens is never guessed at —
it just won't recur automatically.

**Expect:** nothing happens — correct. Triage subjects are inert until
the recurrence order finds candidates (or you file a visit on one by
hand, which is also a fine first exercise of it).

## 3. Watch one liveness-sweep cycle

The order fires within 6h of `gc` start; to force it sooner, run the
formula's fire path once by hand (or just wait). **Expect:** the sweep creates its standing "triage: unnamed waits" subject
(first run only) and files ONE batch visit listing every genuinely idle
bead (up to 20 lines), including any all-children-closed epics as
"what comes next?" candidates; a converse session holds it. **The first pass against the real store is a backlog census — expect a
long list; that is P3 working, and it costs exactly one conversation.**
Work the sitting (route / gate / park / kill, or open a visit on one);
the next pass lists only what remains.

## 4. Watch one triage-recurrence evaluation

Within 24h (or forced): **expect** per triage subject either a skip
(logged: open visit exists / not ripe) or one `visit: <id> — triage
visit: candidates look ripe` — and no visit at all if the scope is
empty and was empty last time, or if its candidate set has not moved
since the last visit (logged `skipped-unchanged`). A scope that just
emptied still files one final visit naming what left. Pull-only: no
board row unless there is something to say.

## 5. Optional: enable the intake default (P2)

```sh
export GC_PROACTIVE_ENABLED=1   # in the city's env, per your config convention
```

**Expect:** the proactive scan begins slinging first reactions at
movable-forward beads; each now surfaces as a filed visit (card in the
subject's notes, held hold) instead of the removed board flag. Skip
this step if you want to live with steps 1–4 first.

## Aftermath

Paste back whatever happened — especially step 1's five expectations
and step 3's first-census volume. Findings land in the
2026-08-fresh-start ledger; calibration adjustments (cap, cadences,
pool size) are one-line changes.
