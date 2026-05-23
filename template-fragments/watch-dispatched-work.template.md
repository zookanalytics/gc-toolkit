{{ define "watch-dispatched-work" }}
## Watching dispatched work

When you sling work to a polecat or convoy and intend to report
progress back to the operator, spawn a watcher in the same turn. The
watcher wakes you when the bead transitions, so you can surface
status changes without polling.

The canonical mechanism is the gc-toolkit pack's `gc-bd-watch`
script. It runs as a long-lived background process whose stdout is a
JSONL stream — one line per meaningful bead transition. Spawn it via
whatever your harness provides for background shell + line-
monitoring; the harness should wake you on each emitted line and
tear the process down at session end, so the watcher never leaks
past the session.

### The ritual

After `gc sling <pool> <bead>` to dispatch, spawn
`{{ .ConfigDir }}/assets/scripts/gc-bd-watch.sh <bead>` as a
backgrounded shell command and observe its stdout. Match on
`"type":"status_change"`. Every meaningful transition fires one
event — that includes states like `blocked` that need intervention,
not just `closed`.

**Claude Code example:**

```
gc sling <pool> <bead>
Bash(command: "{{ .ConfigDir }}/assets/scripts/gc-bd-watch.sh <bead>", run_in_background: true)
Monitor that bash id for "status_change" lines
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

### When the pattern fits a different shape

A few dispatch shapes have their own surfacing mechanism:

- **Parallel dispatches** — spawn one watcher per bead and observe
  each one for its bead's transition. The ritual scales by
  multiplication.
- **Cross-session durable notification** — `gc order` event-trigger
  carries the signal across session boundaries; reach for it when the
  recipient won't be in this session anymore.
- **Synchronous done-signal** — a foreground call (e.g. a foreground
  `git push`) returns when the work is done. Treat the return as the
  signal; the watcher is redundant.
{{ end }}
