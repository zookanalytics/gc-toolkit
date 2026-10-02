---
name: Per-polecat metrics report — data sources and token attribution
description: Why tools/gc-polecat-metrics.sh reads the usage sink rather than the API, and how it recovers a build session the handoff clears from the anchor. Read before changing the report's token join or its session-resolution trace.
---

# tk-6lvz29 — per-polecat metrics: sources and attribution

`tools/gc-polecat-metrics.sh` reports one row per closed work bead: completion
time, PR facts, review and rework rounds, and token usage with an estimated
cost. Every column is a read over data Gas City already records. This file is
the evidence behind two design choices the code cannot show on its own — which
usage interface the token column reads, and how a row gets a session id when
the bead no longer carries one.

## Token usage reads the sink, because nothing else serves it per session

The report needs, for a session that ran at any time in the past, its summed
model-call tokens and cost. Three interfaces were measured against that need:

- `gc costs` reads the sink but declares no JSON (`--json` returns
  `json_unsupported`) and groups by run id across the whole city. There is no
  per-session, machine-readable output to consume.
- The API route `GET /v0/city/{city}/usage` returns a dashboard summary:
  city-wide `today` and `last_24h` totals, and a `recent_by_session` array
  bounded to `recent_window_secs` (300s). It ignores `session_id`, `by`, and
  `since` query parameters and self-reports `partial: true` with the reason
  "usage history exceeded the dashboard read limit". It cannot answer usage for
  a session that ran outside the last five minutes.
- The sink itself, `<city>/.gc/usage.jsonl`, is the append-only history. One
  pass filtered to the report's session ids yields exact per-session sums.

So the sink is the only interface that answers the question, and the report
reads it directly, grep-prefiltered to the sessions it needs. A durable
structured affordance — JSON on `gc costs`, or an API route that accepts a
session and a window over full history — would replace the raw read; both are
Gas City changes, out of scope here, and tracked as a follow-up.

### The join key

A model record carries `session_id` on all but a handful of rows and `run_id`
on every row, and the two are equal wherever both are present. The join key is
therefore `session_id`, falling back to `run_id`. Records with
`kind != "model"` (compute wall-seconds) carry no tokens and are excluded.

## A session id must be recovered, because the handoff clears it

The sink is keyed by session, and the operator's scoping proved the join on one
bead that still carried `gc.session_id`. Across the store that stamp is the
exception: the refinery handoff clears `gc.session_id` and `gc.session_name`
from the anchor (to keep a finished bead from reading as a live orphan), so a
minority of merged anchors carry one, spread across every month rather than
cut off at a date. Reviews, reworks, and the workflow root are bare the same
way. A join on the anchor's own stamp alone would leave most rows blank.

The build session survives in one place: the workflow's `load-context` step
bead retains `gc.session_id` after the chain finalizes. The report recovers the
session by tracing from the anchor back to that step:

```
anchor  <--tracks--  input convoy  (title: "input convoy for <anchor>")
                           ^
        mol-polecat-work root  (gc.input_convoy_id = convoy)
                           |
        load-context step  (gc.root_bead_id = root, gc.session_id = the session)
```

The trace is built from three bulk reads — all `load-context` steps, all
`mol-polecat-work` roots, all convoys — composed on the root id, with no
per-anchor query. A bead reworked across several dispatches has one root and
one load-context step per dispatch, so it resolves to every session that worked
it, and its token figure sums them.

Resolution order per anchor: the load-context trace, then the anchor's own
`gc.session_id` if present, unioned. A bead whose session resolves to neither
shows tokens as `n/a` and is counted in the coverage line rather than dropped.

## Attribution is per session, and the report says so

A session is the unit the sink measures, and a session may build more than one
bead. For those beads the token figure is the session total, shared — not
apportioned. Each row names its session(s) and `session_beads`, the number of
beads that session built, and sets `tokens_shared` when that count exceeds one,
so a reader never reads a shared total as this bead's alone. Summing the token
column across rows therefore double-counts a shared session; sum per session
instead.

## Completion time falls back, and flags the fallback

Completion time is `closed_at` minus the bead's start. `started_at` is absent on
many beads, so start falls back to `gc.claimed_at`, then `created_at`, and the
row records which under `start_source`. A `created_at` start includes time the
bead waited in the pool before a polecat took it, so a row flagged `created_at`
overstates the polecat's own working time.

## The durable fix this report defers

Per-bead token attribution should not need a three-hop trace. The anchor is the
natural carrier of its own build session, and the handoff is where that link is
severed. Preserving the build session on the anchor under a stable key at
handoff — or stamping the cumulative usage at close — would make the join a
direct read and raise coverage to every bead. That work, and the Gas City
alternatives (JSON on `gc costs`, a historical per-session usage route), is
tracked in tk-27vatk; until it lands, the load-context trace is the join, at
the coverage the report prints.
