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
self-contained). Then:

```sh
gc doctor
```

**Expect:** the new `check-liveness-sweep-wired` passes; no new
failures. The two new orders (`liveness-sweep`, `triage-recurrence`)
register on the next `gc` start — they are inert until then.

## 1. Spine smoke (Phase 0/1 evidence — the one that matters most)

Pick any real open bead as `$SUBJECT`, then file a visit with the raw
canonical lines:

```sh
SUBJECT=<any-real-open-bead-id>
POOL="${GC_RIG:+$GC_RIG/}gc-toolkit.converse"
VISIT=$(gc bd create -t task --title "visit: $SUBJECT — spine smoke: say hi and hold" \
  -d "Spine smoke test: rebuild this subject's slice, say what you see, and hold." --json | jq -r '.id // .[0].id')
gc bd update "$VISIT" --set-metadata "gc.routed_to=$POOL" \
  --set-metadata "gc.continuation_group=$SUBJECT" \
  --set-metadata "task_kind=visit"
gc bd dep add "$VISIT" "$SUBJECT" --type=parent-child
```

**Expect, in order:** (1) a converse session spawns with no further
keystroke; (2) it renames itself to the subject (`gc session list` —
this is tk-h9pq5's one unproven integration, Phase 0); (3) it holds
`in_progress` with the subject's state summarized and a trailing "Next
(yours):" line. Say anything to it; **expect** your exchange's outcome
appended to the subject's notes, `gc.outcome` stamped on the visit, the
visit closed, and the session draining (empty group = session
boundary). File a second visit while the session is still alive:
**expect** it vacuumed onto the same session (warm). After the drain,
file a third: **expect** a fresh session that answers a question about
the subject from the record alone (cold).

## 2. Create one or two triage subjects

```sh
gc bd create -t task --title "triage: held ideas (gc-toolkit)" \
  -d "Triage scope: open, unassigned, unrouted idea/backlog beads in this rig that no formula owns. Each visit: enumerate the scope, rank ripeness, frame promote / park / kill per candidate."
gc bd update <id> --set-metadata "task_kind=triage-subject"
```

**Expect:** nothing happens — correct. Triage subjects are inert until
the recurrence order finds candidates (or you file a visit on one by
hand, which is also a fine first exercise of it).

## 3. Watch one liveness-sweep cycle

The order fires within 6h of `gc` start; to force it sooner, run the
formula's fire path once by hand (or just wait). **Expect:** at most 5
`visit: <id> — unnamed wait: route, gate, or park` beads on genuinely
idle beads, each parent-child to its subject, each spawning/queueing a
converse hold; the sweep's own notes list every filing plus how many
candidates the cap deferred. **The first pass against the real store is
a backlog census — expect real mess to surface; that is P3 working, not
a malfunction.** If the volume reads wrong, say so: the cap and cadence
are calibration defaults, not decisions.

## 4. Watch one triage-recurrence evaluation

Within 24h (or forced): **expect** per triage subject either a skip
(logged: open visit exists / not ripe) or one `visit: <id> — triage
visit: candidates look ripe` — and no visit at all if the scope is
empty. Pull-only: no board row unless there is something to say.

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
