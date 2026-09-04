{{ define "watch-dispatched-work" }}
## Addressing: pools versus named agents

`gc sling` stamps `gc.routed_to` and nothing else, whatever the target.
For a **pool** that is the whole address — polecat, polecat-codex, dog,
proactive, converse — because pool members run the routed tier of the
work query, and the bead has to stay unassigned for their claim filter
to offer it.

A **named agent** is addressed by `assignee` instead: mechanik, deacon,
witness, refinery, keeper. Their sessions skip the routed tier, so a
bead carrying only `gc.routed_to=<name>` is never offered to the
identity it names. Give them the assignee write, in place of the sling
or straight after it, using the agent's exact QualifiedName — city-scoped
for a city singleton (`gc-toolkit.mechanik`), rig-scoped otherwise
(`gc-toolkit/gc-toolkit.witness`), the form `gc agent list` prints:

```
gc bd update <bead> --assignee <qualified-name>
```

Nothing reports the mistake. The controller counts routed demand and
can wake the target on it, and the woken session's own `gc hook` then
shows nothing, so the work sits. To check a dispatch you already sent,
read both views: `gc hook <qualified-name>` with the name as an argument
is the controller's, a bare `gc hook` inside the target's session is
the agent's, and a bead only the first can see is stranded.

## Dispatched work is file-and-forget

The default after `gc sling` is file-and-forget: the bead is the
contract, and nothing here reads it again. Sequencing between beads is
edges, never a watcher — record the dependency and drain:

```
{{ .ConfigDir }}/assets/scripts/deferred-dispatch.sh arm <bead> \
    --target <rig>/<agent> --reason "waits for <blocker>"
```

The rig's `deferred-dispatch` order slings the armed bead once `bd`
reports it ready (docs/deferred-dispatch.md). A watch held in your
context is a dispatch invisible to everyone else and gone when the
session ends.

The one sanctioned watch: a human is in THIS conversation right now,
waiting on the outcome. Then spawn exactly one bounded terminal-status
watch — it reports closed or not-closed, and you do not read the work
product:

```
Monitor(
  command: "{{ .ConfigDir }}/assets/scripts/gc-bd-watch.sh <bead>",
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
