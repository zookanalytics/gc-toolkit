{{ define "no-empty-watch-promises" }}
## No empty watch promises

When you sling work and intend to report back to the operator on its
progress, you MUST start a watcher in the same turn. "I'll let you
know when it's done" without a watcher is an empty promise — there is
no mechanism in this session that will fire when the bead transitions,
and you will silently drop the commitment.

The canonical mechanism is the gc-toolkit pack's `gc-bd-watch` script
spawned via `Bash(run_in_background: true)` and observed via Monitor.
The script runs for the lifetime of this session (the harness kills
it on session end, so there is no leaked watcher) and emits one JSONL
line per meaningful bead transition.

### The ritual

```
gc sling <pool> <bead>
Bash(command: "{{ .ConfigDir }}/assets/scripts/gc-bd-watch.sh <bead>", run_in_background: true)
Monitor that bash id for "status_change" lines (or the specific status you care about, e.g. `"to":"closed"`)
```

`{{ .ConfigDir }}/assets/scripts/gc-bd-watch.sh` resolves to this
pack's installed location — no `PATH` setup required. One invocation
watches one bead; for parallel dispatches, spawn N watchers.

### Output grammar

The script emits one self-contained JSON object per line. Consumers
parse line-by-line:

```json
{"ts":"<rfc3339>","bead":"<id>","type":"watch_start","status":"<initial>"}
{"ts":"<rfc3339>","bead":"<id>","type":"status_change","from":"<prior>","to":"<new>"}
{"ts":"<rfc3339>","bead":"<id>","type":"watch_end","reason":"closed|already_closed|timeout|killed|stream_error_<n>"}
```

`bead.updated` fires on every metadata write, label change, and
cache-reconcile pass; the script filters those out and only emits on
real status transitions, so your Monitor pattern stays cheap. Match on
`"type":"status_change"` for "any transition," or narrow to
`"to":"closed"` when you only care about completion.

### When NOT to start a watcher

If the operator already knows they will check back on their own
schedule, or the work has a known synchronous done-signal (e.g. a
foreground `git push` that returns when done), the watcher is
unnecessary. The trigger for the watcher is the commitment "I'll let
you know" — if you're not making that commitment, don't spawn it.

### If you can't start a watcher

If for some reason the dispatch shape doesn't fit the watcher (e.g.
the work crosses session boundaries and you need durable notification),
say so explicitly:

> "I won't have visibility into this from here — ping me when you want
> a status check, or use `gc order` event-trigger if you need
> notification across sessions."

The unsupported pattern is silently committing to a check-back with no
mechanism behind it.
{{ end }}
