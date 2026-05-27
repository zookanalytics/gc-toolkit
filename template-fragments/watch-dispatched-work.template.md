{{ define "watch-dispatched-work" }}
## Watching dispatched work

When you sling work to a polecat or convoy and intend to report
progress back to the operator, spawn a watcher in the same turn. The
watcher wakes you when the bead transitions, so you can surface
status changes without polling.

The canonical mechanism is the gc-toolkit pack's `gc-bd-watch`
script. It runs as a long-lived process whose stdout is a JSONL
stream — one line per meaningful bead transition. Spawn it under a
per-line-notifying tool (Claude Code's `Monitor`); each emitted line
wakes the agent, and the harness tears the process down at session
end so the watcher never leaks past the session.

### The ritual

After `gc sling <pool> <bead>` to dispatch, spawn
`{{ .ConfigDir }}/assets/scripts/gc-bd-watch.sh <bead>` under a
per-line-notifying tool and observe each emitted JSONL line as a
notification. Match on `"type":"status_change"`. Every meaningful
transition fires one event — that includes states like `blocked`
that need intervention, not just `closed`.

**Claude Code example:**

```
gc sling <pool> <bead>
Monitor(
  command: "{{ .ConfigDir }}/assets/scripts/gc-bd-watch.sh <bead>",
  description: "watching <bead>",
  persistent: true,
)
```

Notes:

- Each stdout line from `gc-bd-watch.sh` becomes one notification
  to the agent. Match `"type":"status_change"` for real transitions;
  the `watch_start` / `watch_end` boundary events arrive too and are
  useful for confirming the watcher actually started / for reading
  the exit `reason` when it stops.
- `persistent: true` is the right knob for bead watches because
  beads can take hours-to-days (operator interruption, polecat
  rework loops, refinery queue). The default 300s `Monitor` timeout
  is calibrated for builds/CI and would kill the watch mid-bead.
- Do NOT also spawn the script via `Bash(run_in_background: true)`.
  `Bash` with `run_in_background` notifies only on process exit, not
  per stdout line — pairing it with `Monitor` against the same bash
  id is not a supported wiring, and spawning a second invocation
  costs an extra `gc events --follow` subscription and risks the
  operator wiring the wrong one.

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
