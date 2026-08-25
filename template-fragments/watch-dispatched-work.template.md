{{ define "watch-dispatched-work" }}
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
