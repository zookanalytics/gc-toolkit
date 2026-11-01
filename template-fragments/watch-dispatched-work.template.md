{{ define "watch-dispatched-work" }}
## Addressing: pools versus named agents

A **pool** (polecat, polecat-codex, dog, proactive) takes a sling, which pours a
workflow its members claim:

```
gc sling <rig>/<pool> <bead> --on <formula>
```

A **named agent** (mechanik, deacon, witness, refinery, keeper) takes an
assignee instead, the name `gc agent list` prints. A route would reach its hook
too, but the assignee is what the controller and the pack's notice read to give
it a turn, and the write alone may give it none, so tell it as well:

```
gc bd update <bead> --assignee <qualified-name>
"$(gc <binding> scripts-dir)/deferred-dispatch.sh" notify <bead> --agent <qualified-name>
```

`<binding>` is the name the city imports the gc-toolkit pack under, which gc puts
in front of its skills: `gc-toolkit` in `gc-toolkit.work`. A script called through
`gc <binding> scripts-dir` is that pack's own copy, whichever pack the calling
agent comes from. A converse sitting is neither: a conversation waits in the
operator's queue, assigned to `human`, and `gc-helm engage` spawns the sitting
when the operator engages it from the board. The `work` skill has the rest of
sending work.

## Dispatched work is file-and-forget

The default after `gc sling` is file-and-forget: the bead is the contract, and
nothing here reads it again. A follow-up that is BLOCKED on another bead takes an
edge and an arm, never a watcher (the `waits` skill):

```
"$(gc <binding> scripts-dir)/deferred-dispatch.sh" arm <bead> \
    --target <rig>/<agent> --reason "waits for <blocker>"
```

A watch held in your context is a dispatch invisible to everyone else and gone
when the session ends.

The one sanctioned watch: a human is in THIS conversation right now, waiting on
the outcome. Then spawn exactly one bounded terminal-status watch — it reports
closed or not-closed, and you do not read the work product:

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
