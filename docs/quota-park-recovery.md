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
| 2026-08-02 | Codex usage limit | two review polecats | ~7h30m holding the gc-toolkit merge queue; cleared only by a hand nudge |

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
  history, not a park. The banner is recognised by its SUBJECT and its NOUN,
  never by the word "limit": a provider blocks you on *your session/usage/weekly
  (etc.) limit*, or names itself in front of one (*Claude usage limit reached*).
  An ordinary tool error blocks you on a **rate** limit, and says so just as
  possessively — `You have exceeded your API rate limit`, `Your API rate limit
  will reset at 18:00 UTC`. Both of those are idle panes on working sessions,
  and both matched an earlier, looser form of this pattern;
- no busy marker in that same tail window (`esc to interrupt`, which both CLIs
  print while working). The window is shared with the banner test on purpose:
  both CLIs print the working indicator in the live status line at the bottom of
  the screen, so a copy further up is a turn that has already ended. Matched over
  the whole capture instead, a stale marker in the scrollback vetoes a live
  banner below it and a genuinely parked session is vouched for as clean;
- the matching line is not a **citation** — under a `>`/`▎` blockquote marker,
  double-quoted anywhere, or opening with a single quote, a smart quote or a
  backtick. Providers print their banner bare; an agent writing *about* a quota
  block does not. This is not hypothetical: the script's first live run flagged a
  resident conversation session that had reported the Codex outage to the
  operator and gone idle with the banner quoted in its own report. The single quote counts only as an
  *opening delimiter*, at the start of the line — the apostrophe in the
  provider's own "You've" is the same character, so rejecting it anywhere on the
  line would drop every real banner and switch this order off.

A parked session is nudged (`--delivery immediate`, falling back to the plain
form for an older `gc` that rejects the flag), then re-nudged on a doubling
backoff from 2m to a 15m cap, for as long as it stays parked. A pane that goes
busy or clean ends the episode; the next block starts again from the first
attempt.

The fallback fires only for that flag-rejection case — a fast usage error —
never for a call that hit its bound. A timeout means the runtime may have taken
the nudge and simply not answered in time; retrying there puts two resume
messages into one pane and leaves the attempt counter below what the agent
actually received.

Refusing that immediate retry is only half of it, because the same ambiguity
outlives the cycle. A nudge whose bound expired is recorded as **unconfirmed**:
it advances the retry pacing (`last_try`, and the doubling exponent) without
being counted as a delivery in `attempts`, the figure the escalation reports to
a human. Left out of both, as an earlier version did, the next 3m pass reads
`attempts=0`, treats a session it may well have just nudged as never nudged,
skips the backoff and sends the second resume message anyway — the duplicate
simply arrives one cycle later. Paced, not muted: once the window elapses the
retry does go out, since an unconfirmed nudge may equally well never have
landed. A fast rejection is different and is *not* paced — nothing was
delivered, so the next cycle retries in 3m and cannot duplicate.

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
silently. Same `run_bounded` idiom as `assets/scripts/merge.sh`.

**And the bound is a hard one where the host allows it.** `timeout N` sends
SIGTERM and then *waits*: a child free to ignore the signal runs as long as it
likes, which `timeout 1 bash -c 'trap "" TERM; sleep 4'` demonstrates in four
seconds. A `gc` call wedged in the runtime or in Dolt is precisely the process
least likely to service a signal promptly, so the bound most relied on to keep
one hung call from stranding the sweep is the one likeliest to be ignored — by
the very call that provoked it. `timeout -k` adds the SIGKILL nothing can
ignore, `QUOTA_PARK_KILL_AFTER` (5s) is the grace between them, and expiry stays
a non-zero rc either way — 124 for the timeout, 128+n where the kill lands first
— which the nudge and escalation paths already treat as the ambiguous case it
is. A host whose `timeout(1)` predates `-k` keeps the soft bound and **says so
once per pass**: recovery still runs, but a call that ignores SIGTERM can hold
the sweep past its budget, and a short pass must not be mistaken for a full one.
A host with no `timeout` at all degrades to unbounded calls rather than lose
recovery — dropping every probe would disable the order outright.

**And the next pass starts where the last one stopped.** Bounding the pass is
only half the problem; the other half is *which* sessions the budget gets spent
on. `gc session list` returns a stable order and every hung peek costs a whole
`CALL_TIMEOUT`, so a sweep that always starts at the top pays for the same
unreadable prefix first on every cycle and defers the same tail on every cycle —
eight slow sessions at the defaults (8 × 15s = the 120s budget) and the rest of
the city is never inspected at all, while the summary line reports a healthy 3m
sweep over it. The starving prefix and the parked agent behind it are exactly
the sessions this order exists for, so this is the bug eating itself.

The fix is a cursor: the last session a pass attempted (recorded *before* its
peek, since the peek is the call that hangs) is written to `.sweep-cursor`, and
the next pass rotates the list to start after it. An unreadable prefix ends up at
the back of the following pass and cannot consume it twice. A pass that gets
through the whole list leaves the cursor on the final record, and rotating past
the last record is the identity — so on a healthy city the order is simply the
list order, unchanged. The regression asserts both halves: with the cursor
removed between passes the park behind the prefix is never reached, with it kept
the rotation walks past and reaches it.

**This order deletes only files it wrote.** Ending an episode removes a file in
a directory this order does not own: `QUOTA_PARK_STATE_DIR` defaults inside the
shared city runtime dir and is an override besides, and a session id is not a
rare shape for a filename. A bare `rm -f "$STATE_DIR/<id>"` is therefore not
"end the episode" but "delete whatever is at that name" — reproduced during
review with an unrelated regular file at `$STATE_DIR/lx-clean`, destroyed by one
clean sweep. The week-old prune below already had a narrow ownership test;
what it did not have was the every-three-minutes paths using it. Now all three
share one: directly in `STATE_DIR`, a regular file and not a symlink, named like
the ids we write (`safe_id`), carrying this order's own marker as its first line.
Anything failing one of them is somebody else's and is left alone.

**Ownership is claimed, not guessed.** That test used to end at a `first_seen=`
header, which is a *shape* — and a shape is something a foreign file can happen
to have. Both directions of the guess were reproduced. Reading: a file at a
session-id path carrying plausible `first_seen`/`last_seen`/`detector_class`
fields made `--status` answer `quota_park=yes` for an episode this order never
created — a warrant deferred on evidence it did not produce. Deleting: the same
weak test gated the removal paths, so a file merely shaped like state was
unlinked by a routine sweep, against the very contract above. So every file this
order writes now opens with `#quota-park-nudge-state-v1`, and every path that
reads one requires it: no marker, not ours, in every direction — read, report,
enumerate, delete, prune. The version suffix is what will let a future format
change be told apart from a foreign file rather than parsed as an older one of
ours.

It is an ownership *label*, not an authenticator, and the boundary is worth
stating plainly: it closes the collision class — another component's state, a
stray name, a hand-edited leftover, a shared or mis-set `QUOTA_PARK_STATE_DIR`
— which is the class that has actually been hit here. It cannot stop something
that can write to `STATE_DIR` from writing the marker too, and nothing at this
layer can, since such a writer runs as the same user this order does. An accident
cannot forge ownership; a forgery has to be deliberate.

That refusal has a price, and it is the right one to pay: a foreign file at a
live session's path keeps `--status` answering `unknown` for that session rather
than `no`, because there is a file there this order cannot read as an episode.
It answers with `reason=foreign-state`, which says exactly that, and the patrols
then apply their own judgment — the safe direction and the honest one.

**A timestamp from the future is corrupt, not a record.** Every timestamp
persisted here is stamped from the running pass's own clock, so one *ahead* of
that clock cannot be a record of anything this order did — a bad clock, a
truncated write, a hand edit. "Is an integer" was never the whole contract,
because each such field defeats a different guard by arithmetic alone and always
in the direction that stops recovery: a future `last_try` keeps `NOW - last_try`
negative so the backoff window never elapses and the parked session is never
nudged again; a future `first_seen` keeps `age` negative so `ESCALATE_AFTER` is
never reached and no human is told; a future `last_run` makes every later
`--status` read a stopped order as a freshly-swept one. Each is treated as
invalid and falls back to the default a *missing* field gets — start of episode,
never nudged, no heartbeat — which is the direction that recovers.

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

`safe_id` also rejects a **leading hyphen**, which is the argument half of the
same problem: the id is not only a filename, it is passed to `gc session peek`
and `gc session nudge`, and a shell-quoted argument is still parsed as an
*option* by the command that receives it. An id of `-n` or `--help` arrives there
as a flag rather than as a session. What that would run is the receiving CLI's
business; refusing to hand it over is ours.
The alias is allowlisted and truncated (`sanitize_display`) before it is logged
or mailed, for the same reason the pane is excluded from the escalation below:
keeping the pane out while pasting the alias in raw just moves the hole into a
shorter field.

**Nudging is the only action.** The session is alive and correct — killing it
discards live context and a fresh agent hits the same block. This order never
files a warrant, and the patrols hold theirs back while it is working: the rule
is stated ahead of *every* path that can warrant a session, not once per
formula. That is `check-polecat-health` in `mol-witness-patrol`, and
`health-scan`, `queue-starvation-check` and `utility-agent-health` in
`mol-deacon-patrol` — each step is read immediately before it is acted on, so a
rule stated only in the first one does not reach the other two. Queue starvation
is the easiest of them to get wrong: a quota-parked agent holds open beads with
`bead.updated_at` frozen for hours, which is the starvation signature exactly.
Seven warrants were filed against two quota-parked agents on 2026-08-02. If a
park outlasts `QUOTA_PARK_ESCALATE_AFTER` (2h), one escalation visit is filed
via `escalate.sh` — once per episode, not once per cycle.

"Hold back" is the whole of it, though, and not "never warrant": each of those
steps asks this order for a verdict rather than reading the pane, and defers only
for as long as the order says it is actively recovering that session. The next
section is what they read and why it is not the screen.

## The status surface: what the patrols are allowed to read

The first version of that patrol rule said *peek the pane, and if you see a
limit banner do not file a warrant*. That is a hole, and a bad one. The pane is
agent-controlled output: a wedged — or prompt-injected — agent can print a
provider-shaped line, sit at an idle prompt, and have the patrols stand down.
It is an off switch any agent can reach for itself, wired to the one path that
would otherwise have recovered its work, and the agents most likely to pull it
are precisely the wedged and the compromised ones. Warrant suppression cannot
key on pane text.

So the classification stays in this script — no LLM, no pane text out — and the
patrols read it through a closed-field surface:

```
$ quota-park-nudge.sh --status lx-gsnfk
heartbeat_age=48
heartbeat_fresh=1
stale_after=600
session=lx-gsnfk quota_park=yes detector_class=possessive-limit age_s=8400 parked_for=2h20m attempts=5 unconfirmed=0 escalated=1 last_seen_age=48 reason=-
```

Every value is an integer this script computed, a label from `detector_class`'s
fixed set, a `reason` from a fixed set, or one of `yes`/`no`/`unknown` — nothing
that originates on a screen. Omit the session id to list every episode currently
tracked. It is read-only: no peek, no nudge, no prune.

The verdict a patrol acts on:

| `quota_park` | Meaning | Patrol action |
|---|---|---|
| `yes` | Confirmed parked within `STALE_AFTER`, and being nudged | **Defer** the warrant this cycle, logged. A bounded defer, not a standing suppression |
| `no` | This order **classified that session** within `STALE_AFTER` and found no park (or it is excluded from recovery) | Normal warrant path |
| `unknown` | No verdict to give; `reason` says which kind of nothing | Normal warrant path — see below |

`unknown` is the field that keeps this honest, and it is deliberately not folded
into `no`. Everything reported here is evidence *this order produced*; if the
order is disabled, wedged before it could list sessions, or absent from the host,
there is no evidence at all. Read as "not parked" that silence is right by
accident; read as "parked" it would suppress warrants city-wide on the strength
of a stopped clock.

So every answer is conditional on evidence about **that session**, never merely
on a pass having run, and `reason` names the gap:

| `reason` | Meaning | Is recovery down? |
|---|---|---|
| `-` | A verdict was given (`yes` or `no`) | — |
| `no-recent-sweep` | `.heartbeat` is stale: no pass lately at all | **Yes** — say so in the patrol log |
| `not-swept` | A pass ran but has no usable record of this session: deferred by `SWEEP_BUDGET`, an unreadable pane, an id it refused, attached, not in the active list, or a verdict it could not persist | No — ordinary partial coverage |
| `stale-episode` | An episode exists but nothing has confirmed it since `last_seen` | No |
| `unsafe-session-id` | An id this order will not name a file with, so it holds no state for it | No |
| `foreign-state` | Something is at that session's state path that this order did not write, so there is no episode to read — and no clean verdict to give either, since it will not remove a file it does not own | No |
| `state-dir-unavailable` | `QUOTA_PARK_STATE_DIR` could not be created, or cannot be written: no heartbeat, no coverage record, no episodes — this order holds no evidence about **any** session and can record none | **Yes** — say so in the patrol log |

Every one of those is a *line*, not a silence, and the last one is where that
distinction was bought. The state directory is created at the top of the script,
and it used to be created with `mkdir -p "$STATE_DIR" || exit 0` — ahead of the
`--status` branch, so a state dir the order could not create or write made the
surface exit 0 having printed **nothing at all**. A patrol greps that output for
`quota_park=` and finds no field; a missing field is read as whatever default the
reader assumed, on the one path where this order knows nothing about anything.
The sweep genuinely cannot run without the directory — with nowhere to write an
episode, every park is re-detected as new, nudged on every cycle and escalated
past its backoff — so it still stops, but it stops *loudly*, in the order
runner's log, and the surface answers `unknown` / `state-dir-unavailable` in the
vocabulary its readers already have. `-w` is checked as well as the `mkdir`,
because `mkdir -p` succeeds on a directory that already exists and says nothing
about whether anything may be written in it.

**A patrol that gets no output at all is in the same position, and answers the
same way.** The helper may be absent from the host, non-executable, or return
nothing; the discovery snippet in both patrol formulas is `[ -n "$QPN" ] && "$QPN"
--status <id>`, which yields an empty string in every one of those cases. Empty
or unparseable output is `unknown` — never `no`, never `yes`. Take the normal
warrant path and log it as *recovery status unavailable*, the same as
`reason=no-recent-sweep`: quota-park recovery itself is what is missing, and that
is worth a line in the log rather than a silent fallthrough.

The `no` case is the one that has to be *earned*. A pass that runs out of
`SWEEP_BUDGET` defers its whole tail without peeking it and still writes a fresh
heartbeat at the end, so "a sweep ran recently and there is no episode" is not
the same statement as "that session is not parked" — answered off the heartbeat
alone, every deferred session reports `no`, which is a verdict about a pane
nobody read. That is the failure this order exists to prevent, arriving through
the surface built to prevent it. Hence a third file beside the heartbeat:
`.sweep-coverage`, one `<session-id> <timestamp>` line per session the sweep
actually classified, merged across passes and aged out at `STALE_AFTER`. `no`
requires a line there; anything else is `unknown` with `reason=not-swept`.

A coverage line means more than "the pane was read": it means the verdict is
still there to be read back. For a parked session the state file *is* the
verdict — `--status` answers `yes` out of it — so a line written at peek time
claims more than the pass can show. Reproduced during review with a directory at
`$STATE_DIR/<id>`: the sweep detected the park, nudged it, could not persist the
episode, and the surface then reported `quota_park=no reason=-` for a session it
had just nudged. So the vouch waits on the write: a clean or excluded session is
vouched for when its file is gone (that *is* the verdict), a parked one only
once its episode is written. A write that fails withholds the vouch, and the
session reports `unknown` / `not-swept` — a gap, named in the vocabulary the
patrols already have rather than a new value none of them define. It is counted
and logged in the summary line too; a sweep that could not record what it found
must not read as one that found nothing.

Making that failure *visible* was half the fix. `mv file dir` does not replace
the directory, it moves the file inside it, so a directory at a session's state
path swallowed the episode while the write reported success. The atomic writer
now refuses a directory destination (real or symlinked) — the one type `mv`
redirects into rather than replaces, which is why a planted symlink or FIFO is
still safely destroyed rather than followed.

`escalated` is a **0/1** field. The state file carries a third value —
`unconfirmed`, for an escalation whose bound expired mid-write — but that is
internal bookkeeping for the resend suppression, and from the moment it is
recorded this script behaves as though the human was notified, so the surface
reports `1`. The
patrols and this doc define only `0` and `1`; publishing a value no consumer
handles is how a park that outlasted `ESCALATE_AFTER` keeps getting deferred down
an undefined path. The regression suite asserts that agreement in both
directions — every value the surface emits is one the patrol formulas handle.

The defer is bounded at the far end too. `escalated=1` means the park outlasted
`ESCALATE_AFTER` and an escalation visit is already open; a session still parked
after that has not been recovered by nudging, and the patrols refresh the
escalation via `escalate.sh` instead of deferring again in silence.

`QUOTA_PARK_EXCLUDE` suppresses the *action*, not the observation. An excluded
alias is still counted as parked in the summary line, but it is not nudged and
holds no episode state — so `--status` reports it as `no` and the patrols apply
their own judgment rather than deferring to a recovery that was switched off for
that session. "Holds no state" includes state from *before* the exclusion: an
alias can be added to the pattern while a park is already tracked, and a file
left behind would keep answering `yes` for a session this order has stopped
acting on, which is the deferral the exclusion was meant to end. So the episode
is cleared as the exclusion takes effect.

**The escalation quotes no pane text.** A pane holds whatever the agent printed,
and an agent can print text shaped like an operator directive; the visit is
durable and the operator reads it as an authenticated channel, so an excerpt in
the body launders untrusted content into that channel. The visit carries only
the alias, session id, park age, attempt count, and the same closed **detector
class** the status surface reports. All of that comes from the session list or
the script's own state file. A human who wants the screen reads it directly
with `gc session peek <id>`, which the visit body says.

It says one more thing, for the same reason the patrol rule changed: that this is
a **possible** park and not a proven one. The evidence behind the visit is a
pattern match on a pane, so the body asks the reader to check rather than telling
them the session is healthy and must not be warranted — an instruction that,
derived from agent-controlled text, is one an agent could have written for
itself.

**An escalation whose bound expired is not filed twice.** `escalate.sh` writes
through Dolt, the layer likeliest to be slow during the incident this order runs
in, so a bound can expire *after* the write commits: the visit exists and this
script never heard about it. `escalate.sh` itself keeps exactly one open visit
per situation key, so a retry refreshes rather than duplicates; the local flag
still carries three states, the same way an unconfirmed nudge does: `1` for a
write that completed, `unconfirmed` for one whose bound expired mid-flight
(suppresses the resend, and says in the log that it is doing so), and empty only
for a *fast* rejection, which delivered nothing and can safely be retried.

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
(Bead `tk-al95k`, operator correction 2026-08-02T16:35Z, which supersedes the
"the stated reset time is not trustworthy" framing in the note above it.)

## Tuning

| Variable | Default | Meaning |
|---|---|---|
| `QUOTA_PARK_MATCH` | see script | ERE for provider limit banners |
| `QUOTA_PARK_BUSY` | `esc to interrupt…` | ERE proving the agent is mid-turn |
| `QUOTA_PARK_PEEK_LINES` | `20` | pane lines captured; must be ≥ 1 |
| `QUOTA_PARK_TAIL_LINES` | `12` | how far up the banner may sit; must be ≥ 1 |
| `QUOTA_PARK_BACKOFF_BASE` / `_CAP` | `120` / `900` | seconds between retries; must be ≥ 1 |
| `QUOTA_PARK_ESCALATE_AFTER` | `7200` | one escalation visit (via `escalate.sh`) per long park; `0` disables |
| `QUOTA_PARK_EXCLUDE` | — | ERE of aliases never nudged |
| `QUOTA_PARK_CALL_TIMEOUT` | `15` | seconds per `gc` call; `0` disables the bound |
| `QUOTA_PARK_KILL_AFTER` | `5` | seconds after that before SIGKILL, for a call that ignores SIGTERM; must be ≥ 1 (`timeout -k 0` is accepted and would silently restore the soft bound) |
| `QUOTA_PARK_SWEEP_BUDGET` | `120` | seconds per pass before the rest defers; `0` disables |
| `QUOTA_PARK_STALE_AFTER` | `600` | how long `--status` treats a sweep and a sighting as evidence; must be ≥ 1 |
| `QUOTA_PARK_STATE_DIR` | `$GC_CITY/.gc/runtime/quota-park` | per-session episode state |

Every numeric knob above is validated once, up front, and falls back to its
default if it is not a bare integer **at or above its floor**. A garbage value
fails differently in each place it lands and announces itself in none of them: a
bad backoff bypasses backoff (`[: oops: integer expression expected` reads as
"window elapsed", so every cycle nudges), a bad `ESCALATE_AFTER` reads as
*disabled* and no human is ever told, and a bad `PEEK_LINES`/`TAIL_LINES` makes
`tail -n` error out so **no session is ever detected as parked at all**. A typo
in a tuning knob must not be able to switch off city-wide recovery quietly.

The floor is why `0` is not simply "an integer, therefore fine". Zero is the
documented off switch for exactly three knobs — `CALL_TIMEOUT` (unbounded
calls), `SWEEP_BUDGET` (no per-pass budget) and `ESCALATE_AFTER` (never
escalate) — and those keep a floor of `0`. Everywhere else zero is a typo that
disables recovery while looking deliberate: `TAIL_LINES=0` makes `tail -n 0`
print nothing, so nothing is ever detected as parked; `PEEK_LINES=0` empties
every capture, which reads as an unreadable pane; `BACKOFF_BASE=0` or
`BACKOFF_CAP=0` collapses the retry window and nudges every parked pane on every
sweep, forever. Those knobs have a floor of `1` and fall back exactly as they do
for `oops`.

The three pattern knobs are validated the same way and for a sharper reason:
`grep` answers a malformed ERE with rc 2, and every test in the sweep reads a
non-zero rc as *did not match*. So `QUOTA_PARK_MATCH='('` does not switch the
detector off loudly — it reports every pane in the city as clean, deletes the
episode state of every session actually parked, and leaves `--status` answering
`no` for all of them, while the summary line reports a healthy sweep. Each
pattern is therefore checked once, ahead of the sweep, and falls back with a line
in the log: `MATCH` to the default detector (and it stops being labelled
`custom-match`), `BUSY` to the default busy markers, and `EXCLUDE` to *no
exclusions*. That last direction is deliberate — an unusable exclusion costs one
unwanted nudge per backoff window on one session, whereas treating it as matching
everything would leave the whole city unrecovered from a typo.

**State files are replaced, never written through.** A plain `>` follows an
existing symlink or FIFO. `QUOTA_PARK_STATE_DIR` is a shared runtime directory
whose location is an override, and every path under it is named by a session id,
so an entry planted beside our state would have this order writing wherever it
points — as the order's user, on every 3m sweep — and a FIFO would block the
open, hanging a sweep that is otherwise carefully bounded. Every write (episode
state, `.heartbeat`, `.sweep-cursor`, `.sweep-coverage`) goes to a `mktemp` file
created `O_EXCL` and is then `rename(2)`d into place, which replaces the
directory entry whatever type it is. Reads refuse to follow a symlink for the
same reason, so a planted link reads as *no state* and is destroyed by the next
write rather than being parsed as this order's own record.

The week-old cleanup of the state directory is deliberately narrow for the same
"this is a city-scoped order" reason: `QUOTA_PARK_STATE_DIR` is an override and
its default lives inside the shared city runtime tree, so a bare recursive
`find -delete` there is this order unlinking week-old files it has never heard
of. It prunes only files directly in the directory (never a nested tree), named
like the session ids it writes, and carrying its own marker line — anything else
is somebody else's file, whatever its age.

It walks a glob rather than `find`, and ages each file from the record inside it
(`last_seen`, falling back to `first_seen`) rather than from mtime, so the whole
path is POSIX shell: `find -maxdepth`/`-print0` are GNU/BSD extensions and `stat`
spells mtime differently on each, and this order degrades carefully everywhere
else — it *probes* for `timeout -k` rather than assuming it. A glob never
descends, so the depth guard comes free. Aging from the record is also the truer
measure: mtime says when the file was last written, `last_seen` says when a sweep
last confirmed the park.

The order's own non-episode files live there as well: `.sweep-cursor` (where the
next pass starts), `.heartbeat` (that a pass ran, and what it saw) and
`.sweep-coverage` (which sessions it classified). Every name begins with a dot,
which `safe_id` rejects — so no session can be given a state file that collides
with one, the prune never considers them as episodes, and `--status` never
reports one as a parked session. The same is true of the `.qpn-tmp.<pass>.*`
files the atomic writes go through; a pass killed between the `mktemp` and the
rename leaves one behind, and the week-old prune collects them by name. Each
carries the writing pass's timestamp in its name, which is how they are aged
without a `stat` — and the reason a temp file a *concurrent* pass is still
writing is never removed out from under its rename.

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
