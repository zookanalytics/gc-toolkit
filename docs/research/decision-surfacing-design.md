---
name: Decision-Surfacing Design
description: Proposal to close the gap between "decision bead becomes ready for operator review" and any operator-facing channel learning about it.
---

# Decision-surfacing design proposal

> **Status:** proposal. Not yet adopted. Adoption is mechanik + operator
> ratifying the chosen mechanism on parent bead `tk-f2wpu`, after which
> the two follow-up impl beads listed at the end of this doc are filed.
>
> **Bead:** `tk-c7ukh` (this research+propose). **Parent:** `tk-f2wpu`
> (P1, open since 2026-05-06). **Triggering incident:** `tk-yiwfz`
> review-readiness went unnoticed for ~3 days until the operator asked.

## Provenance

| Artifact | Producer | Source location | Surveyed at |
|---|---|---|---|
| Cockpit script (current state) | gc-toolkit pack | `assets/scripts/cockpit.sh` @ `1056bc4` | 2026-05-13 |
| `gc order` CLI | gascity binary | `gc order --help` (binary in `$PATH`) — sources in `cmd/gc/cmd_order.go`, `internal/orders/{order,triggers}.go` (upstream `~/temp/gascity`) | 2026-05-13 |
| `gc bd ready` flag surface | gascity binary | `gc bd ready --help` — semantics in `internal/beads/beads.go` (`Ready()`, `readyExcludeTypes`) | 2026-05-13 |
| `gc bd list --type=decision` shape | gascity binary | `gc bd list -t decision --status=open --json` | 2026-05-13 |
| Existing pack orders | gc-toolkit pack | `orders/digest-generate.toml` @ `1056bc4` | 2026-05-13 |
| Upstream order trigger types | gascity | `internal/orders/triggers.go` — `cooldown`, `cron`, `condition`, `event`, `manual` | 2026-05-13 |
| Event types emitted today | gascity | `internal/events/events.go` — `bead.created`, `bead.closed`, `bead.updated`, et al. | 2026-05-13 |
| Existing nudge/mail prior art | gc-toolkit formulas | `formulas/mol-witness-patrol.toml`, `formulas/mol-refinery-patrol.toml` @ `1056bc4` | 2026-05-13 |
| `assets/scripts/decision-ready-nudge.sh` (proposed) | — | **not found** — to be created by impl bead B | n/a |
| `orders/decision-ready-nudge.toml` (proposed) | — | **not found** — to be created by impl bead B | n/a |

**Path correction:** parent bead references `rigs/gc-toolkit/assets/scripts/cockpit.sh`. The actual path (in this worktree's view) is `assets/scripts/cockpit.sh`; the `rigs/gc-toolkit/` prefix is the city-level view of the same file. Both refer to the same artifact.

## Chosen mechanism

Adopt the parent bead's proposed combination: **cockpit panel (mechanism 1) + `gc order` event-driven nudge (mechanism 3)**.

The cockpit panel is the passive surface — operator looking at the cockpit sees a list of decisions ready for review, distinct from "all open decisions". The `gc order` event-driven nudge is the active surface — when a `bead.closed` event arrives, an order runs a script that re-evaluates ready-decision state and nudges mechanik when a new decision-ready transition has occurred.

Both surfaces share the same underlying query (`gc bd ready -t decision`), so they agree by construction. The cockpit can never disagree with the nudge about whether a decision is ready.

### Why both, not just one

- **Cockpit alone** assumes the operator looks at the cockpit. They mostly do, but the triggering incident (`tk-yiwfz`, 3-day silent gap) happened with the cockpit running. The "OPEN DECISION BEADS" panel was visible the whole time and didn't differentiate review-ready from in-flight. A passive panel is necessary but not sufficient.
- **Nudge alone** wakes mechanik on every decision-ready transition but leaves the operator-facing cockpit no better. The operator still has to ask mechanik. A nudge is an active push to one agent; the cockpit is a passive pull for the human.
- **Both** gives the operator a self-serve view *and* an active push so mechanik can route urgent decisions without polling.

Mechanism 2 (auto-mail on synthesis close) was rejected because it requires every synthesis formula to remember to fire mail — the bead description explicitly flags this as the brittle option ("inferior to a structural fix").

Mechanism 4 (scheduled doctor sweep) was rejected as redundant with the cockpit panel — they both ask the same query, just at different cadences. The cockpit's 60s refresh is faster than a doctor sweep would be.

## Mechanism 1: Cockpit panel

**Surface:** `assets/scripts/cockpit.sh`, line ~350.

**Change:** replace the current `OPEN DECISION BEADS` panel with `DECISIONS READY FOR REVIEW`, switching the query from `bd list -t decision --status open` to `bd ready -t decision`.

```sh
# Current
draw_section 'OPEN DECISION BEADS' 'decision' -t decision --status open

# Proposed
draw_section 'DECISIONS READY FOR REVIEW' 'decision_ready' --ready -t decision
```

`draw_section` calls `bead_block`, which today shells out to `gc bd list`. The `--ready` flag would route to `gc bd ready` instead. The cockpit's `bead_block` already supports `--rig <name>` for per-rig fan-out; that survives unchanged.

**Query semantics:** `bd ready` uses the `GetReadyWork` API — it returns open beads of the given type whose blocking dependencies are all closed, excluding infrastructure types (`molecule`, `gate`, `message`, etc.). For `type=decision`, this is exactly "open decision bead with zero open blockers" — the definition of decision-ready.

**Recipient:** the human operator reading the cockpit.

**Trade-off accepted:** an unblocked decision bead that has zero blockers from the start (e.g., a research-free decision bead) will also appear in this panel. That's intended — those are also waiting on operator review.

## Mechanism 2 (chosen as #3 in parent bead): `gc order` event-driven nudge

**Surface:** new `orders/decision-ready-nudge.toml` + new `assets/scripts/decision-ready-nudge.sh`.

**Order TOML:**

```toml
# orders/decision-ready-nudge.toml
[order]
description = "Nudge mechanik when a decision bead becomes ready for review"
trigger     = "event"
on          = "bead.closed"
exec        = "$PACK_DIR/assets/scripts/decision-ready-nudge.sh"
```

`trigger = "event"` is supported by `internal/orders/triggers.go::checkEvent` — the controller advances an event cursor per order, and the order fires when matching events accumulate past the cursor. There are no event-triggered orders in the live city today, so this introduces the pattern; the trigger type is implemented but unexercised in production.

**Exec script logic** (`assets/scripts/decision-ready-nudge.sh`):

```sh
#!/bin/sh
# For city + each rig:
#   - query: gc bd ready -t decision --rig <rig> --json
#   - for each returned bead:
#       - if metadata.gc.decision_notified != "true": send nudge to
#         mechanik, then set metadata.gc.decision_notified=true on the
#         bead so the next firing doesn't re-notify
```

Two notes on idempotency:

1. The script is called once per `bead.closed` event accumulation, not once per closure. If three closures fire in the same tick, the script still queries the current `bd ready` state once and processes each newly-ready decision exactly once.
2. The `gc.decision_notified` metadata flag on the decision bead is the durable record of notification. If the bead is reopened (e.g., operator wants to add more research before deciding), the impl bead should also clear the flag — proposed semantics: clear on `bead.updated` where `status` transitions back to `open`.

**Recipient: mechanik (single primary recipient).** Single-recipient is simpler than fanout — mechanik is the coordination agent that owns surfacing decisions to the operator. Mayor as a future fanout target is a follow-up if mechanik isn't responsive (out of scope for this bead).

**Communication: `gc session nudge`, not mail.** The durable record is the bead's metadata flag plus its `status=open` + zero open blockers. Nudge is ephemeral but mechanik is a long-lived agent; the next time it checks its inbox or hook, it sees the decision. If mechanik happens to be dead, the next cockpit refresh shows the decision in the panel, and a fresh mechanik session re-queries `bd ready -t decision` anyway. So mail is not load-bearing here.

## Worked example: `tk-yiwfz`

Replay of the historical incident under the proposed mechanisms. (`tk-yiwfz` is now closed, but its timeline is the canonical example.)

| Step | Time (historical) | What happens |
|---|---|---|
| 1. Operator scopes `tk-yiwfz` (decision bead, P2, "default file-recording locations"). | 2026-05-02 | Bead status=open. Six research children filed (tk-yiwfz.1..7, with .4 the synthesis). |
| 2. Research children complete. | 2026-05-04 → 2026-05-06 | One by one, blocking children close. `tk-yiwfz` dependency_count drops. |
| 3. Synthesis child `tk-yiwfz.4` merges (commit `69fa5d2`). | 2026-05-06 ~10:00 | `bead.closed` event recorded, type=`bead.closed`, subject=`tk-yiwfz.4`. |
| **Today (gap):** | | Nothing happens. `bd ready -t decision` would now include `tk-yiwfz` but no surface asks. Cockpit shows it under "OPEN DECISION BEADS" but indistinguishable from the dozen other open decisions. |
| **Proposed (mechanism 1, cockpit):** | 2026-05-06 ~10:01 | Next cockpit tick (≤60s after merge): "DECISIONS READY FOR REVIEW" panel includes `tk-yiwfz` (`gc-toolkit  (1)` → `○ tk-yiwfz  P2  Establish default file-recording locations …`). Operator looking at cockpit sees it immediately. |
| **Proposed (mechanism 2, order):** | 2026-05-06 ~10:00 + controller tick | Controller next-tick evaluates `decision-ready-nudge` order: event cursor < latest `bead.closed` seq → trigger fires. Exec script queries `bd ready -t decision`, finds `tk-yiwfz` without `gc.decision_notified=true`, sets the flag, and `gc session nudge gc-toolkit/gc-toolkit__mechanik "Decision ready for review: tk-yiwfz — Establish default file-recording locations …"`. Mechanik sees the nudge on its next hook fire and surfaces to operator. |
| 4. Operator reviews and closes. | 2026-05-09 (historical) | `tk-yiwfz` closes with "Adopted: synthesis landed as docs/file-structure.md". |

The gap that took 3 days in the historical timeline collapses to ≤60s (cockpit) and one controller tick (nudge) under the proposed design.

## Follow-up impl beads

To be filed after this proposal is ratified on `tk-f2wpu`.

### Bead A: `impl(cockpit): replace OPEN DECISION BEADS panel with DECISIONS READY FOR REVIEW`

**Scope:** Modify `assets/scripts/cockpit.sh` line ~350 to swap the query from `bd list -t decision --status open` to `bd ready -t decision`. Update the panel header. Verify against a probe decision bead (file a throwaway decision bead with one open child, close the child, watch the next cockpit tick surface it). Update the cockpit-sketch reference doc if it cites the old panel name. ~10 LoC + a probe-bead manual test.

### Bead B: `impl(orders): add decision-ready-nudge order with idempotency flag`

**Scope:** File `orders/decision-ready-nudge.toml` with `trigger=event, on=bead.closed` and `assets/scripts/decision-ready-nudge.sh`. Script fans out across city + each rig via `gc bd ready -t decision --rig <rig> --json`, filters by missing `metadata.gc.decision_notified`, sends `gc session nudge` to mechanik for each new ready decision, and sets the flag. Add a probe-bead integration test (file decision + blocker, close blocker, verify mechanik received exactly one nudge). Clear `gc.decision_notified` when a decision bead is reopened — handled either by extending this script to also watch `bead.updated` events with a status-transition filter, or by a separate small order; decision deferred to the impl bead. ~50 LoC script + TOML.

## Out of scope (deferred)

- Mayor as a secondary fanout recipient — file as follow-up if mechanik proves unreliable.
- Slack/concierge fanout — tracked separately (parent bead references `tk-ag9y6`).
- Other "review-needed" bead patterns beyond `type=decision` (e.g., a `task` bead waiting on review). The mechanism generalizes by changing the type filter, but the parent bead's scope is decisions specifically.
- Behavioral fix to mechanik's prompt ("don't make commitments you can't deliver") — flagged in parent bead as a separate concern, not addressed by the structural surface this bead designs.

## Open questions

1. **Reopen handling.** Should `gc.decision_notified` clear when a decision is reopened? Proposed: yes (re-notify on next ready transition). Concrete mechanism deferred to impl bead B.
2. **Doc location convention.** `docs/file-structure.md` (the adopted spec from `tk-yiwfz`) tiers work-tied design proposals under `specs/<bead-id>/`, not `docs/research/`. The parent bead `tk-c7ukh` explicitly directed this doc to `docs/research/decision-surfacing-design.md`. Recording the tension here — relocating after adoption (e.g., to `docs/decision-surfacing.md` once the impl beads land and this doc graduates to "what's true now") is a low-cost follow-up.
