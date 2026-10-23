{{ define "watch-dispatched-work" }}
## Addressing: pools versus named agents

`gc sling` stamps `gc.routed_to` and nothing else, whatever the target.
For a **pool** that is the whole address — polecat, polecat-codex, dog,
proactive — because pool members run the routed tier of the work query,
and the bead has to stay unassigned for their claim filter to offer it.
A converse sitting is neither a pool nor a named agent: a visit parks on
the helm board (`gc.routed_to=human`), and `gc-helm engage` spawns the
sitting when the operator draws it off the board.

A **named agent** is addressed by `assignee` instead: mechanik, deacon,
witness, refinery, keeper. Its hook would also claim a bead routed to
its own name, but the assignee is what the controller and the pack's
notice read to give the agent a turn (docs/deferred-dispatch.md, "Work
assigned to a named agent owes a notice"). Give them the assignee write,
in place of the sling or straight after it, using the agent's exact
QualifiedName — city-scoped for a city singleton (`gc-toolkit.mechanik`),
rig-scoped otherwise (`gc-toolkit/gc-toolkit.witness`), the form
`gc agent list` prints:

```
gc bd update <bead> --assignee <qualified-name>
```

Then tell the agent, because the write gives an idle named session on
`wake_mode = "resume"` no turn:
`"$(gc <binding> scripts-dir)/deferred-dispatch.sh" notify <bead> --agent <qualified-name>`
mails it the bead once `bd` reports the bead ready. `gc <binding> scripts-dir`
prints the directory of the gc-toolkit pack's scripts, so a script called
through it is the pack's own copy, whichever pack the calling agent comes from.
`<binding>` is the name the city imports that pack under, which gc puts in
front of its skills: `gc-toolkit` in `gc-toolkit.work`.

## Dispatched work is file-and-forget

The default after `gc sling` is file-and-forget: the bead is the
contract, and nothing here reads it again. A follow-up that is BLOCKED on
another bead is the one case that needs more than a sling, and the answer is
still an edge and a drain, never a watcher: record the blocker as a `blocks`
edge, then ARM the follow-up so it routes itself when the blocker lands.

```
"$(gc <binding> scripts-dir)/deferred-dispatch.sh" arm <bead> \
    --target <rig>/<agent> --reason "waits for <blocker>"
```

The rig's `deferred-dispatch` order slings the armed bead once `bd`
reports it ready (docs/deferred-dispatch.md). Arm it rather than leave it
unrouted for someone to route later: a blocked work bead with no route and
no arm is the debt `doctor/check-blocked-work-armed` flags, and a watch held
in your context is a dispatch invisible to everyone else and gone when the
session ends.

The one sanctioned watch: a human is in THIS conversation right now,
waiting on the outcome. Then spawn exactly one bounded terminal-status
watch — it reports closed or not-closed, and you do not read the work
product:

```
Monitor(
  command: '"$(gc <binding> scripts-dir)/gc-bd-watch.sh" <bead>',
  description: "watching <bead>",
  persistent: true,
)
```

`persistent: true` is load-bearing (beads outlive Monitor's default
300s timeout), and one watcher per bead — never a second subscription
via `Bash(run_in_background: true)`. `gc-bd-watch.sh` wraps `gc events`
and exits at a terminal status; act on `"type":"status_change"`, read
`.to` (`blocked` needs intervention, not just `closed`). No human
waiting means no watcher — not even "to report back later"; the record
carries the outcome.
{{ end }}
