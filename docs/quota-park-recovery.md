# Quota-park recovery

A provider quota block is self-healing in principle — the window reopens on a
clock. An agent whose **turn ended inside the block** is not: it has no pending
work to drive it and no timer of its own, so it sits at an idle prompt under
the limit banner until something nudges it. The controller cannot see this
(`state=active` — the session really is alive and correct), and patrol wisps
only go stale, which reads the same as "busy".

Twice observed, two different providers:

| Date | Provider | Parked | Cost |
|---|---|---|---|
| 2026-07-22 | Claude session limit | both rig witnesses | 1h26m still parked *after* the window reopened; no orphan recovery in either rig meanwhile |
| 2026-08-02 | Codex usage limit | two review polecats | ~7h30m holding the gc-toolkit merge queue; cleared only when the mayor nudged by hand |

Both times every agent resumed within 20s of a single `gc session nudge`.
Bug: `tk-al95k`.

## Mechanism

`orders/quota-park-nudge.toml` runs `assets/scripts/quota-park-nudge.sh` every
3m, `scope = "city"` — no LLM, no agent, no wisp. For each session the
controller believes is alive (`state=active`, not `attached` — a human at the
pane can act for themselves), it captures the pane tail and calls it **parked**
when all of these hold:

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
form for an older `gc` that rejects the flag), then re-nudged on a doubling
backoff from 2m to a 15m cap, for as long as it stays parked. A pane that goes
busy or clean ends the episode; the next block starts again from the first
attempt.

The fallback fires only for that flag-rejection case — a fast usage error —
never for a call that hit its bound. A timeout means the runtime may have taken
the nudge and simply not answered in time; retrying there puts two resume
messages into one pane and leaves the attempt counter below what the agent
actually received. A timed-out nudge is recorded as failed and the next cycle
retries it under the backoff, which is the right pacing for a session that is
still blocked anyway.

Two selection rules are load-bearing enough to state on their own:

**Liveness is `.state`, never `.running`.** `running` is null for an active
session during controller churn, so a `running == true` filter drops exactly
the live sessions it means to select — and a quota-parked one in that state
would never be peeked at all. The helm's owner-liveness join keys off `.state`
for the same reason (`assets/scripts/gc-helm.sh`, with a `running: null` case
pinned in `tools/helm-surface-fixture.sh`); this order follows it.

**Every `gc` call is bounded.** The order runner applies no timeout of its own,
and these calls go through the runtime and Dolt — the layers most likely to be
wedged during the very incidents this order recovers from. Unbounded, one hung
`gc session peek` strands every session *behind* it in the sweep. Each call is
capped at `QUOTA_PARK_CALL_TIMEOUT` (a wedged one is skipped, not fatal) and the
pass as a whole at `QUOTA_PARK_SWEEP_BUDGET`, after which the remainder defers
to the next cycle rather than overlapping it — reported in the summary line, not
silently. Same `run_bounded` idiom as `assets/scripts/merge-skill.sh`; hosts
without coreutils `timeout` degrade to unbounded calls rather than lose recovery.

**Only a successful peek may end an episode.** Ending one deletes the state
file, which is what resets the backoff and the once-per-episode escalation flag.
A peek that errored or hit its bound proves nothing about the pane, so reading
it as "clean" would let a transient runtime failure — during precisely the kind
of incident this order runs in — make a six-hour park look freshly detected and
start nudging again from attempt 1. An unreadable pane leaves the episode intact
and is counted in the summary line.

**The session list is untrusted input.** An alias is mutable and an agent can
set its own, so both fields get handled as data rather than as structure. The
list is read as `@tsv`, which escapes tab, newline, carriage return and
backslash inside a field — interpolated instead, a newline in an alias forges a
*second record*, and the "id" of that record went straight into
`$STATE_DIR/$id`. The id is then validated as a bare token (`safe_id`): no
separator, no dot-segment, nothing that resolves out of the state directory. The
two are complementary — the encoding stops a field from becoming a record, the
validation stops a record from becoming a path — and a session whose id fails
validation is skipped entirely and counted, never peeked or nudged on a guess.
The alias is allowlisted and truncated (`sanitize_display`) before it is logged
or mailed, for the same reason the pane is excluded from the escalation below:
keeping the pane out while pasting the alias in raw just moves the hole into a
shorter field.

**Nudging is the only action.** The session is alive and correct — killing it
discards live context and a fresh agent hits the same block. This never files a
warrant, and neither do the patrols: the exception is stated ahead of *every*
path that can warrant a session, not once per formula. That is
`check-polecat-health` in `mol-witness-patrol`, and `health-scan`,
`queue-starvation-check` and `utility-agent-health` in `mol-deacon-patrol` —
each step is read immediately before it is acted on, so a rule stated only in
the first one does not reach the other two. Queue starvation is the easiest of
them to get wrong: a quota-parked agent holds open beads with `bead.updated_at`
frozen for hours, which is the starvation signature exactly. Seven warrants were
filed against two quota-parked agents on 2026-08-02. If a park outlasts
`QUOTA_PARK_ESCALATE_AFTER` (2h), one mail goes to the mayor — once per
episode, not once per cycle.

**The escalation quotes no pane text.** A pane holds whatever the agent printed,
and an agent can print text shaped like an operator directive; mail is durable
and the mayor reads it as an authenticated channel, so an excerpt in the body
launders untrusted content into that channel. The mail carries only the alias,
session id, park age, attempt count, and a **detector class** — one label from a
closed set (`possessive-limit`, `named-provider-limit`, `usage-credits`,
`provider-limit`, `custom-match`) saying which signature family matched. All of
that comes from the session list or the script's own state file. A human who
wants the screen reads it directly with `gc session peek <id>`, which the mail
body says.

## Two rules the recurrences taught us

**Not provider-specific.** One defect, two providers, two wordings. The
signature set matches on the durable phrase (`hit|reached|exceeded your …
limit`, `<provider> usage limit reached`, `/usage-credits`) rather than on
either CLI's layout, and never on the apostrophe — both render `You've` with a
typographic `'` a C-locale `.` will not match. `QUOTA_PARK_MATCH` overrides it
for a provider we have not met.

Every alternative stays anchored to something only a provider says — the
user-possessive `your … limit`, or a named provider/plan in front of it. A bare
`(session|usage|rate) limit (reached|exceeded)` looks harmless and is not: it
matches an ordinary idle tool error such as `Error: API rate limit exceeded`,
and that pane gets nudged on the recovery cadence for as long as it sits there.
A new provider belongs in the name list (or in `QUOTA_PARK_MATCH`), not in a
subject-less form.

That has now been paid for twice. A bare `limit will reset at` outlived the
round that tightened the alternative above, and matched `Error: API rate limit
will reset at 18:00 UTC.` on an idle pane — same false positive, same cost. It
carries the same possessive anchor now (`your … limit will reset`), so the
clause only counts as a banner when a provider is the one saying it. Nothing
reads the time in it either way; see the next rule.

**Never schedule against the stated reset time.** On 2026-08-02 the Codex banner
said `try again at Aug 8th, 2026 7:56 PM` and the block cleared on **Aug 2** —
not because the banner lied (it was probably right about the natural window) but
because the operator triggered a manual reset out of band. That is the general
case: quota returns by routes no banner predicts. A fix that slept until the
parsed deadline would have missed it by six days, which is worse than the bug it
fixes; a fix that dismissed banner times as garbage would be wrong in the other
direction. So the banner time is treated as a lower bound worth knowing and
never as an authority — the script does not read the reset clause at all, it
polls. Being early costs one no-op nudge; being late costs a day of throughput.
(Bead `tk-al95k`, mayor correction 2026-08-02T16:35Z, which supersedes the
"the stated reset time is not trustworthy" framing in the note above it.)

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
| `QUOTA_PARK_CALL_TIMEOUT` | `15` | seconds per `gc` call; `0` disables the bound |
| `QUOTA_PARK_SWEEP_BUDGET` | `120` | seconds per pass before the rest defers; `0` disables |
| `QUOTA_PARK_STATE_DIR` | `$GC_CITY/.gc/runtime/quota-park` | per-session episode state |

Every numeric knob above is validated once, up front, and falls back to its
default if it is not a bare integer. A garbage value fails differently in each
place it lands and announces itself in none of them: a bad backoff bypasses
backoff (`[: oops: integer expression expected` reads as "window elapsed", so
every cycle nudges), a bad `ESCALATE_AFTER` reads as *disabled* and no human is
ever told, and a bad `PEEK_LINES`/`TAIL_LINES` makes `tail -n` error out so **no
session is ever detected as parked at all**. A typo in a tuning knob must not be
able to switch off city-wide recovery quietly.

Regression suite: `assets/scripts/quota-park-nudge.test.sh` (hermetic — fake
`gc`, canned panes, no city). It also parses `orders/quota-park-nudge.toml` and
asserts the wiring the sweep depends on: `trigger`, `interval`, `scope = "city"`
and a live `exec` path. A rig-scoped order or a broken exec path fails just as
silently as a broken detector, and no other test in the pack reads that file.

## Why an order and not the controller

The bug report preferred a controller-side fix, because it would cover every
agent class and not depend on patrol cadence. A city-scoped exec order has both
properties — it sweeps every session on its own 3m clock, independent of any
agent — and it lives in this pack, where the Go controller does not. If quota
handling later moves into the controller, this order is the thing to retire.
