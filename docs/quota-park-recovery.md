# Quota-park recovery

A provider quota block is self-healing in principle — the window reopens on a
clock. An agent whose **turn ended inside the block** is not: it has no pending
work to drive it and no timer of its own, so it sits at an idle prompt under
the limit banner until something nudges it. The controller cannot see this
(`state=active`, `running=true` — the session really is alive and correct), and
patrol wisps only go stale, which reads the same as "busy".

Twice observed, two different providers:

| Date | Provider | Parked | Dead time *after* the block expired |
|---|---|---|---|
| 2026-07-22 | Claude session limit | both rig witnesses | 1h26m (no orphan recovery in either rig) |
| 2026-08-02 | Codex usage limit | two review polecats | ~7h30m (holding the gc-toolkit merge queue) |

Both times every agent resumed within 20s of a single `gc session nudge`.
Bug: `tk-al95k`.

## Mechanism

`orders/quota-park-nudge.toml` runs `assets/scripts/quota-park-nudge.sh` every
3m, `scope = "city"` — no LLM, no agent, no wisp. For each session the
controller believes is alive (`running`, `state=active`, not `attached` — a
human at the pane can act for themselves), it captures the pane tail and calls
it **parked** when all of these hold:

- a provider limit banner matches in the last 12 lines (`QUOTA_PARK_TAIL_LINES`)
  — below a real banner there is only prompt chrome, so a match further up is
  history, not a park;
- no busy marker anywhere in the capture (`esc to interrupt`, which both CLIs
  print while working);
- the matching line is not a **citation** — quoted, or under a `>`/`▎`
  blockquote marker. Providers print their banner bare; an agent writing *about*
  a quota block does not. This is not hypothetical: the script's first live run
  flagged a bead-host that had reported the Codex outage to the operator and
  gone idle with the banner quoted in its own report.

A parked session is nudged (`--delivery immediate`, falling back to the plain
form), then re-nudged on a doubling backoff from 2m to a 15m cap, for as long
as it stays parked. A pane that goes busy or clean ends the episode; the next
block starts again from the first attempt.

**Nudging is the only action.** The session is alive and correct — killing it
discards live context and a fresh agent hits the same block. This never files a
warrant, and the deacon and witness patrols carry the same rule (seven warrants
were filed against two quota-parked agents on 2026-08-02). If a park outlasts
`QUOTA_PARK_ESCALATE_AFTER` (2h), one mail goes to the mayor — once per
episode, not once per cycle.

## Two rules the recurrences taught us

**Not provider-specific.** One defect, two providers, two wordings. The
signature set matches on the durable phrase (`hit|reached|exceeded your …
limit`, `usage limit reached`, `/usage-credits`) rather than on either CLI's
layout, and never on the apostrophe — both render `You've` with a typographic
`'` a C-locale `.` will not match. `QUOTA_PARK_MATCH` overrides it for a
provider we have not met.

**Never trust the stated reset time.** On 2026-08-02 the Codex banner said
`try again at Aug 8th, 2026 7:56 PM`. The limit reset on **Aug 2**. A fix that
slept until the parsed deadline would have kept those agents parked six extra
days — strictly worse than the bug. So the script never parses the reset clause:
it polls and retries, and recovery tracks the actual reset. The cost of being
early is one no-op nudge.

## Tuning

| Variable | Default | Meaning |
|---|---|---|
| `QUOTA_PARK_MATCH` | see script | ERE for provider limit banners |
| `QUOTA_PARK_BUSY` | `esc to interrupt…` | ERE proving the agent is mid-turn |
| `QUOTA_PARK_PEEK_LINES` | `20` | pane lines captured |
| `QUOTA_PARK_TAIL_LINES` | `12` | how far up the banner may sit |
| `QUOTA_PARK_BACKOFF_BASE` / `_CAP` | `120` / `900` | seconds between retries |
| `QUOTA_PARK_ESCALATE_AFTER` / `_TO` | `7200` / `mayor/` | one mail per long park; `0` disables |
| `QUOTA_PARK_EXCLUDE` | — | ERE of aliases never nudged |
| `QUOTA_PARK_STATE_DIR` | `$GC_CITY/.gc/runtime/quota-park` | per-session episode state |

Regression suite: `assets/scripts/quota-park-nudge.test.sh` (hermetic — fake
`gc`, canned panes, no city).

## Why an order and not the controller

The bug report preferred a controller-side fix, because it would cover every
agent class and not depend on patrol cadence. A city-scoped exec order has both
properties — it sweeps every session on its own 3m clock, independent of any
agent — and it lives in this pack, where the Go controller does not. If quota
handling later moves into the controller, this order is the thing to retire.
