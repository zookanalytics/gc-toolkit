---
name: Runaway-polecat detection
description: How the deacon patrol catches a polecat that is still running with no work left, before token burn makes it expensive. Read it when the patrol reports a runaway-precondition line, or when tuning what counts as a clean drain.
---

# Runaway-polecat detection

A runaway polecat is a session that keeps taking turns after its work is
done. Every health scan in the city looks for the opposite failure — an agent
that has stopped moving, seen as a stale wisp or a bead whose `updated_at` no
longer advances. A runaway trips none of them: it moves vigorously, its
session is `state=active`, and token burn is invisible to both scans. The
cost is measured in the hundreds of thousands of tokens per detection hour,
so the useful question is not "has it stopped?" but "does it still have
anything to run?"

One state answers that, and it is cheap to read:

    session ACTIVE + its last claim CLOSED + no queued demand for its pool

Every polecat pool runs `min=0`. A seat exists only because demand spawned
it, and it is supposed to drain when the work it was spawned for is finished.
So a seat still moving with a closed claim and an empty queue has nothing
left to do, and catching it there costs one nudge instead of an hour of burn.

## Scope

**Mandate.** The precondition the deacon patrol watches for on pool worker
sessions, the guards that keep it off healthy ones, and the ladder from
detection to disposal.

**Boundaries.** It does not cover the shutdown dance itself — how a warrant
is served, interrogated and pardoned or executed is
`formulas/mol-dog-shutdown-dance.toml` and `docs/authority-map.md`. The
adjacent detector for a session parked at a provider quota banner is
`docs/quota-park-recovery.md`; a parked session is idle, not running, and the
two never fire on the same evidence.

## What runs it

`assets/scripts/runaway-precondition.sh`, once per cycle, from the deacon
patrol's `system-health` step. The step is the rule's only durable home: a
deacon's context resets every cycle, so a rule kept anywhere else is gone by
the next one.

The script classifies every active session whose template names a polecat
role, in every rig, and prints one `key=value` line per session plus a
summary. It nudges its own first findings and reports the rest; it never
kills a session and never files a bead.

## What holds a session back

Four guards stand between the precondition and a finding. Each one exists
because a healthy session looks exactly like a runaway without it.

- **The drain window.** A polecat that has just closed its last claim is
  normally exiting. Measured from anchor close to session exit, a clean drain
  finishes in about one to six minutes, so a claim that closed inside
  `RUNAWAY_GRACE_S` is reported `verdict=grace` and nothing acts on it.
- **Work still held.** `mol-polecat-work` runs its steps inline and keeps one
  claim for the whole run, but a formula that claims per step leaves its last
  claim closed in between. So a session holding any open or in-progress bead
  is not idle whatever its last claim says. The three assignee shapes are
  tested together — a pool seat is stamped with its session id, a named
  polecat with its alias, and `gc bd update --claim` writes the session name.
  A filter written for one shape reads FALSE CLEAN against the other two. A
  scan that failed or timed out cannot prove the session holds nothing, so it
  reads `verdict=unknown`, never clean.
- **Queued demand.** Work waiting in the pool is work the session will claim
  next. `gc hook <template>`, with no `--claim`, is the read-only probe: exit
  0 means an offer is waiting, exit 1 means the queue is empty.
- **Movement.** A session whose `last_active` has gone stale past
  `RUNAWAY_IDLE_S` is burning nothing. That is the not-moving axis, and the
  stale-wisp and stale-bead scans own it.

A session the probe cannot classify — an unreadable anchor, an undateable
stamp, a held-work scan that failed, a demand probe that failed — is reported
`verdict=unknown`. Unproven is never clean, and it is never warrantable either.

## The ladder

A first finding is nudged: the session is told its claim is closed, its pool
is empty, and that it should close its step chain and run
`gc runtime drain-ack`. A nudge is harmless to a session that is already
draining, which is what makes it the right first move.

Only a later pass that finds that same claim still idle reports
`verdict=warrant`. The deacon files one warrant for the dog pool against that
session — never a direct kill, and never a second warrant while one is open.
A nudge that fails to send is not recorded as a nudge, so the next pass
retries it rather than counting down to a warrant nobody was warned about.

The ladder is keyed to the claim, not just the session: the record names the
anchor the nudge was about. When a session finishes the nudged claim and idles
on a different one, the record resets, so the new claim earns its own nudge
before it can be warranted — a warrant never rests on a nudge that named a
claim the session has already left behind.

The nudge record is per session under `RUNAWAY_STATE_DIR`, pruned when the
session is gone. Without a writable state dir the script cannot remember its
own nudges: it still reports findings, the summary says
`state_dir=unavailable`, and the ladder stalls at the nudge.

## The surface

    session=<id> verdict=<v> template=<t> rig=<r> anchor=<bead>
      anchor_status=<s> closed_age_s=<n> idle_s=<n> demand=<yes|no|unknown>
      nudges=<n> reason=<slug>

    runaway-precondition: sessions=<n> flag=<n> warrant=<n> unknown=<n>
      state_dir=<ok|unavailable>

`verdict` is one of `clean`, `grace`, `flag`, `warrant`, `unknown`, and
`reason` names which guard decided it. `-1` in an age field means the value
was not computed on that path, not that it is zero.

## Tuning

| Variable | Default | What it sets |
|---|---|---|
| `RUNAWAY_GRACE_S` | 600 | how long after a claim closes the state starts to count |
| `RUNAWAY_NUDGE_WAIT_S` | 600 | how long after the nudge a still-flagged session becomes warrantable |
| `RUNAWAY_IDLE_S` | 600 | `last_active` age past which a session counts as not moving |
| `RUNAWAY_ROLE_MATCH` | `polecat` | ERE matched against the template's agent segment |
| `RUNAWAY_CALL_TIMEOUT` | 20 | per-`gc`-call bound; 0 disables |
| `RUNAWAY_STATE_DIR` | `<city>/.gc/runtime/runaway-precondition` | where the nudge record lives |

The defaults are sized against the patrol's own cadence: at a ten-minute
cycle a shorter grace buys no earlier nudge, and it costs the margin that
keeps a slow but clean drain from being nudged.

`--dry-run` classifies and reports without nudging or writing state, which is
how to read the city's current standing without touching it.

## What it does not do

It does not warrant a session that has merely stopped moving, does not act on
a seat that has never claimed anything (there is no finished work to prove it
is done, and a seat still coming up looks the same), and does not kill
anything. Disposal is the dog pool's, through a warrant the deacon files.
