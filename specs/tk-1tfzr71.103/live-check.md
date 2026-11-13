---
name: Live check of how each named agent hears about its work
description: Use when you need the evidence behind the form each named agent takes its work in (route, assignee or mail), whether a nudge reaches it at the hand-off or when a blocker closes, whether a default nudge wakes a stopped session, or why a ready hand-off nudges the agent itself rather than relying on core's nudge-on-route order.
---

# Live check of how each named agent hears about its work

The record unit 2 of the deferred-dispatch effort (tk-1tfzr71.103) owes: each
receiving agent finds the work in the form the design's section 6 gives it
(`specs/tk-1tfzr71.98/design.md`), hears the nudge, and the deacon's, the
witness's and the keeper's paths are settled before the work skill names
their form. Run on 2026-11-13 between 20:55Z and 21:17Z.

## Where it ran

- **The city's build**: gc `1.4.3`, build `6589a7df45-dirty`, with core and bd
  imported at `e38ce9cc55`, the commit the live city pins. The core order
  scripts the check ran were byte-identical to the live city's copies.
- **A scratch city** on that build, with its own supervisor on its own port and
  its own tmux server, the session reconciler `v2` and the supervisor's nudge
  dispatcher, as the live city runs them. gc-toolkit came in by a path import of
  this branch's worktree, and the keeper's pack into a rig `r1`. Every order but
  `nudge-on-route` and `cascade-nudge-on-blocker-close` was skipped.
- Every provider was a sink: a script that appends each line typed into the
  session to a log with the time it arrived, and runs nothing. So a nudge shows
  as a line in the agent's log, and no model ran.
- The `v2` reconciler needs conditional writes, which this host's bd 1.3.4
  lacks, so the infrastructure classes were bound to SQLite
  (`gc storage migrate --from-work --fleet-stopped`). That split city refuses
  `gc bd` for the host's patched bd, so a `gc` shim first on the supervisor's
  PATH served `gc bd` with the real bd. Raw bd writes emit no event, so each
  blocker was closed through the city's API, which emits `bead.closed` as a
  `gc bd close` does in the live city.
- Read-only probes of the live city's hooks, with `gc hook <agent>` under each
  agent's alias and no claim.

## Results

| What was checked | What happened |
|---|---|
| A ready bead handed to the mechanik with `gc sling gc-toolkit.mechanik <bead> --no-formula --no-convoy` | The bead read open, unassigned, `gc.routed_to=gc-toolkit.mechanik`, and the mechanik's hook (`GC_ALIAS=gc-toolkit.mechanik`) offered it. |
| core's `nudge-on-route` after that route | No nudge reached the mechanik, after five routes. The order ran every one to two minutes. Its script selects `bead.updated` events by `.payload.metadata."gc.routed_to"` and `.payload.id`, and every event the build emitted carried the bead under `.payload.bead`. Its own filter over those events printed nothing, and the same filter on `.payload.bead` printed the bead and its target. |
| The same on the live city | `gc events --type bead.updated --since 3h` held no flat-shaped event and 2104 nested ones. `nudge-on-route-state.json` was last written at 19:36Z, a minute after the supervisor restarted onto this build at 19:35Z. Filed in the gascity rig as gc-wzfk0f. |
| `gc sling … --no-formula --no-convoy --nudge` to the running mechanik | It printed "No running sessions for gc-toolkit.mechanik — poked controller for wake", and nothing reached the mechanik. |
| `gc session nudge gc-toolkit.mechanik "<bead> is routed to you and ready"`, default delivery | It reached the mechanik's session within a second. |
| A waiting bead routed to the mechanik, its `blocks` blocker then closed | The hook did not offer the bead while it waited, and offered it once the blocker closed. `cascade-nudge-on-blocker-close` nudged the route with the default delivery 27 s after the close: "blocker r1-wc6 closed — routed dependent r1-9rw may be ready to claim". |
| A landing-shaped bead (a `branch`, waiting on a blocker) assigned to the on-demand refinery, which was not running | The refinery's find-work listing (`--assignee --status=open --has-metadata-key=branch`) returned it. When its blocker closed, the controller started the refinery one second later, and the cascade's queued nudge reached it 26 s after the close: "- [operator] blocker r1-uhr closed — your dependent r1-t4u may be unblocked". |
| A bring-current hand-off (no `branch`, waiting on the outside work) assigned to the running refinery | find-work's listing left it out. When its blocker closed, the queued nudge naming it reached the refinery 27 s later. |
| A default `gc session nudge` to the on-demand keeper, which had never run | The nudge queued ("the session cannot take input now: starting"), the controller started the keeper one second later, and the nudge reached it 17 s after that. |
| The deacon holding its patrol wisp, with an outside bead routed to it and another assigned to it | Its hook answered the wisp alone, in progress and again once the wisp was open, ahead of both outside beads. |
| The live city's hooks, read-only | The deacon's and the refinery's answered their in-progress patrol wisps. The witness's answered nothing, its next wisp deferred between passes. The keeper's answered a bead both assigned and routed to it. The mechanik's answered nothing. |

## What the check settles

- **The mechanik** claims through its hook, so it takes the route. A route
  alone gives it no turn on this build, so a writer whose bead is ready nudges
  it at the write. A waiting bead takes the route alone, and the cascade
  nudges the route when the blocker closes.
- **The refinery** finds its work by the beads assigned to it, so it takes the
  assignee. It is woken when an assigned bead becomes ready, and the cascade's
  nudge names the bead, which is how it takes a bring-current hand-off.
- **The keeper** takes the assignee too: its wake sweep lists the open beads
  assigned to it, and a nudge to it when it is not running starts it. Its own
  pr-prep hand-back already assigns the bead and mails it with `--notify`.
- **The deacon and the witness** take no bead. Each one's hook answers its own
  patrol wisp, which its patrol pours and assigns before it burns the last one,
  and neither patrol lists assigned beads. Each reads its mail every cycle, so
  the work skill sends them mail.
- **Section 6's reading that a default nudge wakes a stopped session holds**:
  the nudge queues and the controller starts the session, which then gets it.
- **Section 6's reading that `nudge-on-route` nudges a routed agent does not
  hold on the city's build**, and a ready hand-off nudges the agent itself.

## How to run it again

The scratch city's config, the sink, the shim and the agents' logs are under
`~/.cache/tk-1tfzr71.103/live/evidence/` on the host that ran it. The recipe:
`gc init --template minimal --no-start` into a short path such as
`/private/tmp/claude-502/<name>` (a long one overflows the supervisor's socket
path), a `supervisor.toml` with its own port, `cities.toml` by hand, every gc
call under `env -i HOME=/Users/gc … GC_HOME=<its home>`, the storage
migration above, the shim, then `gc supervisor run`. Never give its agents a
real shell as their provider: gc types each agent's prompt into the session at
start.
