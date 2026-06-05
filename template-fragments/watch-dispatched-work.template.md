{{ define "watch-dispatched-work" }}
## Watching dispatched work

When you sling work to a polecat or convoy and intend to report
progress back to the operator, spawn a watcher in the same turn. The
watcher wakes you when the bead transitions, so you can surface
status changes without polling.

The portable mechanism is `gc events --follow` filtered to one bead.
`gc` is always on `PATH`, so this works from any agent in any pack. It
runs as a long-lived process whose stdout is a JSON Lines stream — one
API event DTO per line. Spawn it under a per-line-notifying tool
(Claude Code's `Monitor`); each emitted line wakes the agent, and the
harness tears the process down at session end so the watcher never
leaks past the session.

### The ritual

After `gc sling <pool> <bead>` to dispatch, spawn

```
gc events --follow --payload-match "bead.id=<bead>"
```

under a per-line-notifying tool and observe each emitted JSON line as a
notification. Each line is one event DTO; match on `.type` of
`bead.updated` or `bead.closed` and read `.payload.bead.status`. Every
meaningful transition fires an event — that includes states like
`blocked` that need intervention, not just `closed`.

`bead.updated` also fires on metadata writes and label changes, not
just status changes, so compare `.payload.bead.status` against the last
status you observed and act only on a real transition.

**Claude Code example:**

```
gc sling <pool> <bead>
Monitor(
  command: "gc events --follow --payload-match 'bead.id=<bead>'",
  description: "watching <bead>",
  persistent: true,
)
```

Notes:

- Each stdout line becomes one notification to the agent. Match
  `.type` of `bead.updated`/`bead.closed` and key off
  `.payload.bead.status`; ignore other event types.
- `persistent: true` is the right knob for bead watches because
  beads can take hours-to-days (operator interruption, polecat
  rework loops, refinery queue). The default 300s `Monitor` timeout
  is calibrated for builds/CI and would kill the watch mid-bead.
- `--follow` starts at the current stream head, so a transition that
  races between the `gc sling` dispatch and the watcher starting can
  be missed. When that startup window matters, snapshot the cursor
  first with `gc events --seq` and resume from it via
  `gc events --follow --after <seq> --payload-match "bead.id=<bead>"`.
- Do NOT also spawn the stream via `Bash(run_in_background: true)`.
  `Bash` with `run_in_background` notifies only on process exit, not
  per stdout line — pairing it with `Monitor` against the same bash
  id is not a supported wiring, and spawning a second invocation
  costs an extra `gc events --follow` subscription and risks the
  operator wiring the wrong one.

### Event grammar

Each line from `gc events --follow` is one API event DTO. The fields
this watch keys on:

```json
{"seq":<n>,"type":"bead.updated","payload":{"bead":{"id":"<id>","status":"<new>"}}}
{"seq":<n>,"type":"bead.closed","payload":{"bead":{"id":"<id>","status":"closed"}}}
```

Consumers parse line-by-line, filter `.type`, and compare
`.payload.bead.status` to the previously observed status to detect a
real transition. `.seq` is the resume cursor for `--after`.

### Richer wrapper (gc-toolkit-native agents)

gc-toolkit ships a convenience wrapper, `gc-bd-watch.sh`, around the
same `gc events --follow` stream. It adds what the raw form leaves to
the consumer: it snapshots the cursor before reading the bead (closing
the startup race above), emits a `status_change` line only on a real
transition (so metadata-only `bead.updated` events don't wake you),
reconnects with exponential backoff across transient stream drops, and
exits when the bead reaches a terminal status.

It lives at `{{ .ConfigDir }}/assets/scripts/gc-bd-watch.sh`.
**`{{ .ConfigDir }}` resolves to the consuming agent's own pack
directory**, so this path is valid only for agents whose pack ships the
script — gc-toolkit-native agents such as `mechanik`. An agent defined
in or imported from a different pack will not find the script under its
`{{ .ConfigDir }}`; those agents use the portable `gc events --follow`
form above. The script is invoked by this pack-relative path, not by a
bare name on `PATH`.

For agents that can reach it:

```
Monitor(
  command: "{{ .ConfigDir }}/assets/scripts/gc-bd-watch.sh <bead>",
  description: "watching <bead>",
  persistent: true,
)
```

The wrapper emits one self-contained JSON object per line; match on
`"type":"status_change"`:

```json
{"ts":"<rfc3339>","bead":"<id>","type":"watch_start","status":"<initial>"}
{"ts":"<rfc3339>","bead":"<id>","type":"status_change","from":"<prior>","to":"<new>"}
{"ts":"<rfc3339>","bead":"<id>","type":"watch_reconnect","attempt":<n>,"reason":"stream_error_<n>|stream_ended_before_terminal"}
{"ts":"<rfc3339>","bead":"<id>","type":"watch_end","reason":"closed|already_closed|timeout|killed|stream_error_<n>|stream_ended_before_terminal"}
```

The `watch_start` / `watch_end` boundary events are useful for
confirming the watcher started and for reading the exit `reason` when
it stops. `watch_reconnect` is informational — the watcher hit a
transient stream failure and is reconnecting at the most recently
observed `seq`. Consumers keying on `"type":"status_change"` ignore it;
the next real transition still fires a `status_change` event once the
stream recovers. If reconnects exhaust the budget
(`GC_BD_WATCH_MAX_RECONNECT`, default 5), the final `watch_end` carries
the underlying failure reason.

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
