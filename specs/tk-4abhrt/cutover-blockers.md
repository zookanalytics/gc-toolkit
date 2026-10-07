# converse cutover (tk-4abhrt): three premises fail against source and live state

The 3/3 cutover asks for one orchestration that, "on a converse visit being
filed (routed_to=human gate), open `gc session new converse-<model>` + `gc
session pin` it," retires the converse routed-pool atomically, and preserves
live converse (Principle 5). Three load-bearing premises of that design fail
when checked against gascity CORE source and the live ledger. The binding
primitive works; the spawn *model* does not. A design decision is owed before
implementation.

## What holds

The session-to-visit binding is sound. A session from `gc session new
converse-opus --alias <visit> --no-attach` is `session_origin=manual`, is not
`pool_managed`, and is therefore exempt from all three pool backstops
(`execution_backstop.go:195`, `idle_nudge.go:169`, `idle_nudge.go:384` all gate
on `pool_managed=="true"`, set only on the reconciler spawn path,
`session_name_lookup.go:322`). A manual session also skips tier-3 pool-demand
claiming (`workquery.go:788`). A visit assigned to that session's runtime
identity is then claimable with no pool routing at all: `gc hook --claim`
returns `existing_assignment` (in_progress) or `ready_assignment` (open, with a
CAS) purely on an assignee match (`cmd_hook_claim.go:752`, `:524`); route
matching gates only the unassigned pool tier (`:734`). So the existing converse
prompt and `converse-claim.sh` need no change to *work* a pre-assigned visit —
the orchestration assigns the visit to the spawned session's captured identity
and the machinery adopts it.

Two mechanics to carry into any implementation: the assignee must equal the
session's real runtime identity (`GC_SESSION_ID`/`GC_SESSION_NAME`/`GC_ALIAS`),
and for a multi-session template the stored alias is a *qualified* form, not the
bare visit id (`cmd_session.go:206`, `session_capacity.go:52`) — so capture the
identity from `gc session new --json`, do not assume it equals the visit id. An
`open` visit must also be `bd ready`; its `tracks` edge to the subject is
non-blocking, so it is ready unless something else blocks it.

## Premise 1 — the named carrier does not carry human gates

The bead states the visit "parks as the durable human-gate carried by the CORE
mail+renudge sweep (cmdOrderSweepNudgeMail, cmd_order.go:2137)."
`cmdOrderSweepNudgeMail` (`cmd_order.go:2137`, `nudge_mail_sweep.go:54`) is a
retention sweep: it closes stale *delivered nudge beads* and *read mail beads*
past a TTL. It does not select on `gc.routed_to=human`, sends no mail, nudges no
session, and reminds no human. No CORE mechanism periodically reminds a human
about a `routed_to=human` bead; `routed_to=human` parks purely by omission — no
pool route target equals `"human"`, so nothing serves it (subagent trace of
`cmd_mail.go`, `handler_mail.go`, `main.go:1426`). Human *gates* (`issue_type=
gate`) do get renudged by separate notify/renudge orders
(docs/gascity-human-engagement.md §200-207), but a visit is `task_kind=visit`,
not a gate, so those orders do not reach it either.

Consequence: a visit routed to `human` under this design has no attention
channel except the spawned session's own pane. That is only an adequate channel
if a pane is actually spawned and the operator is looking — which Premise 2
shows cannot hold at scale.

## Premise 2 — spawn-per-visit breaks the live engine (Principle 5)

Live ledger at 2026-09-06T10:05Z: **87 open/in_progress visits** (85 routed to
`gc-toolkit/gc-toolkit.converse`, 2 to `human`), against **17 active sessions**.
The pool bounds concurrent sittings today at `max_active_sessions = 2`; that cap
is the only thing keeping 85 parked conversations from becoming 85 live panes.

"Open `gc session new` + `gc session pin` per filed visit" removes that bound and
adds no other:

- A sweep over open visits would attempt ~85 spawns at once — past
  converse-opus's own `max_active_sessions = 8` and the city session cap, on top
  of the 17 already live.
- Even a hook that fires only on *newly* filed visits accumulates without
  bound: visits are filed several times an hour (six in the three hours before
  this survey), and a **pinned** sitting never idles out — it ends only on
  `gc-helm dismiss`. Sittings therefore accrue one-per-visit until the operator
  dismisses each by hand, and the session cap is reached long before that
  happens.

The pool's throttle is load-bearing, and the cutover as written deletes it. This
is the opposite of the bead's Principle 5 ("live converse is never broken").

## Premise 3 — pin-keepalive will not re-pin these sittings

pin-keepalive re-asserts the awake-pin only on sessions with
`configured_named_session=true` (its predicate, and its own header comment
anticipating "a converse sitting once reshaped"). That field is set only for a
`[[named_session]]` singleton materialized with **no** alias (`cmd_session.go:294`,
`:412` — the block is short-circuited when `requestedAlias != ""`). An
`--alias`-spawned converse sitting never carries it, so pin-keepalive's config-
drift re-pin never covers it. The design's reliance on pin-keepalive for
durability does not hold for the alias-spawn path.

(Whether a `pin` is even needed depends on whether a `session_origin=manual`
session is subject to the config-drift restart at all — not determined here, and
worth settling before wiring a pin the keepalive will not maintain.)

## The decision owed

The binding works, but the spawn model does not, and the fix is a design choice
that contradicts the bead's literal instruction and belongs to the tk-d3k4qm
design owner:

1. **Bound concurrency.** Cap live sittings (as the pool did) and leave the
   overflow parked — but then define what reminds the operator of a parked
   visit, since Premise 1 shows nothing does, and define how a slot frees when
   pinned sittings never idle out.
2. **Spawn on engagement, not on filing** (tk-d3k4qm direction A: "a fresh
   session spawns ON ENGAGEMENT ... exits when they leave"). There is no CORE
   "operator engaged a visit" trigger today (the board's open action files a
   visit; it does not spawn a session), so this needs a new primitive — itself
   operator-gated.
3. **Migrate the 87-visit backlog** as an explicit step of the cutover (drain,
   dismiss, or re-file), rather than letting the orchestration inherit it.

Recommendation: option 2 (on-engagement) matches direction A and the "holds only
while the operator is live" intent, but it is blocked on a spawn trigger that
does not exist; option 1 is implementable now but re-derives the pool's
throttle and still owes the parked-visit attention channel. Either way the bead
premise "spawn + pin per filed visit" cannot ship as written without breaking
the live city.
