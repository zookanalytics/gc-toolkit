{{ define "watch-dispatched-work" }}
## Watching dispatched work

When you sling work and intend to report progress back to the operator,
spawn a watcher in the same turn — it wakes you on each bead transition, so
you surface status without polling.

**Do not watch a blocker in order to sling something after it.** That is a
dispatch held in your context: invisible to everyone else and gone when the
session ends. Record it on the bead and drain —

```
{{ .ConfigDir }}/assets/scripts/deferred-dispatch.sh arm <bead> \
    --target <rig>/<agent> --reason "waits for <blocker>"
```

The rig's `deferred-dispatch` order slings it once `bd` reports the bead
ready. Watch for *reporting*; arm for *sequencing*
(docs/deferred-dispatch.md).

### The ritual

```
gc sling <pool> <bead>

# Then spawn exactly ONE watcher:
Monitor(
  command: "{{ .ConfigDir }}/assets/scripts/gc-bd-watch.sh <bead>",
  description: "watching <bead>",
  persistent: true,
)
```

Two knobs are load-bearing: `persistent: true` (beads take hours-to-days;
Monitor's default 300s timeout would kill the watch mid-bead), and never
also spawn the stream via `Bash(run_in_background: true)` — a second
subscription on one bead risks acting on the wrong one. Every meaningful
transition fires — including `blocked`, which needs intervention, not just
`closed`.

`gc-bd-watch.sh` wraps `gc events`: it snapshots the cursor before reading
the bead, emits a line only on a real status change, reconnects with
backoff, and exits at a terminal status. Act on `"type":"status_change"`,
read `.to`. For parallel dispatches, one watcher per bead; for a recipient
who will not be in this session anymore, use a `gc order` event trigger;
for a synchronous done-signal (a foreground push), the return IS the
signal and a watcher is redundant.
{{ end }}
