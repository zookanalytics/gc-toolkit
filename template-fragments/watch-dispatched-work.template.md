{{ define "watch-dispatched-work" }}
## Watching dispatched work

When you sling work and intend to report progress back to the operator,
spawn a watcher in the same turn. It wakes you on each bead transition,
so you surface status without polling.

**Do not watch a blocker in order to sling something after it.** That is
a dispatch held in your context: invisible to everyone else, and gone
when this session ends. Record it on the bead instead and drain —

```
{{ .ConfigDir }}/assets/scripts/deferred-dispatch.sh arm <bead> \
    --target <rig>/<agent> --reason "waits for <blocker>"
```

The rig's `deferred-dispatch` order slings it once `bd` reports the bead
ready. Watch for *reporting*; arm for *sequencing*. See
`docs/deferred-dispatch.md`.

### The ritual

Pick the form your pack supports. `{{ .ConfigDir }}` resolves to the
**consuming agent's own pack directory**, so the wrapper below exists
only for agents whose pack ships it — gc-toolkit-native agents such as
`mechanik`. Agents defined in a sub-pack (the gascity-keeper `keeper`,
for one) use the portable stream instead. Both go under a
per-line-notifying tool; `gc` is always on `PATH`.

```
gc sling <pool> <bead>
Monitor(
  command: "{{ .ConfigDir }}/assets/scripts/gc-bd-watch.sh <bead>",   # gc-toolkit-native
  description: "watching <bead>",
  persistent: true,
)
Monitor(
  command: "gc events --follow --payload-match 'bead.id=<bead>'",     # portable
  description: "watching <bead>",
  persistent: true,
)
```

Two knobs are load-bearing either way:

- `persistent: true` — beads take hours-to-days (operator interruption,
  rework loops, refinery queue). `Monitor`'s default 300s timeout is
  calibrated for builds/CI and would kill the watch mid-bead.
- Do NOT also spawn the stream via `Bash(run_in_background: true)`. It
  notifies only on process exit, not per stdout line; pairing it with
  `Monitor` against the same bash id is not a supported wiring, and the
  second subscription risks the operator wiring the wrong one.

Every meaningful transition fires an event — including `blocked`, which
needs intervention, not just `closed`.

**Portable stream.** Each stdout line is one API event DTO:

```json
{"seq":<n>,"type":"bead.updated","payload":{"bead":{"id":"<id>","status":"<new>"}}}
```

Match `.type` of `bead.updated`/`bead.closed` and compare
`.payload.bead.status` against the last status you observed —
`bead.updated` also fires on metadata and label writes, so only a
changed status is a real transition. `--follow` starts at the current
stream head, so a transition racing the dispatch can be missed; when
that window matters, snapshot the cursor with `gc events --seq` first
and resume via `--after <seq>`. `.seq` is that resume cursor.

**Wrapper.** `gc-bd-watch.sh` wraps the same stream and does that work
for you: it snapshots the cursor before reading the bead, emits a line
only on a real status change, reconnects with backoff across drops, and
exits at a terminal status. Act on `"type":"status_change"`, read `.to`:

```json
{"ts":"<rfc3339>","bead":"<id>","type":"watch_start","status":"<initial>"}
{"ts":"<rfc3339>","bead":"<id>","type":"status_change","from":"<prior>","to":"<new>"}
{"ts":"<rfc3339>","bead":"<id>","type":"watch_reconnect","attempt":<n>,"reason":"stream_error_<n>|stream_ended_before_terminal"}
{"ts":"<rfc3339>","bead":"<id>","type":"watch_end","reason":"closed|already_closed|timeout|killed|stream_error_<n>|stream_ended_before_terminal"}
```

`watch_reconnect` is informational; the next real transition still fires
a `status_change` once the stream recovers. If reconnects exhaust
`GC_BD_WATCH_MAX_RECONNECT` (default 5), the final `watch_end` carries
the underlying failure reason.

### When the pattern fits a different shape

- **Parallel dispatches** — one watcher per bead; the ritual scales by
  multiplication.
- **Cross-session durable notification** — `gc order` event-trigger
  carries the signal across session boundaries; reach for it when the
  recipient won't be in this session anymore.
- **Synchronous done-signal** — a foreground call (e.g. a foreground
  `git push`) returns when the work is done. Treat the return as the
  signal; the watcher is redundant.
{{ end }}
