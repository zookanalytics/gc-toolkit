---
name: Gas City search for a finding's cleared situation
description: The search the arch check asks for before patrol-finding.sh records that a finding's situation ended. What Gas City, the packs it publishes and bd ship for recording on a bead that the situation it tracks is over, read at named upstream commits, and why the change composes bd's operational state (`bd set-state`) rather than a metadata key of the pack's own. Read it when checking whether a finding's end-of-episode record still fits what bd and Gas City ship.
---

# Gas City search for a finding's cleared situation

boot-health files a cold deacon as one finding per deacon through
`patrol-finding.sh`. When a fresh patrol wisp shows the deacon patrolling
again, the operator's ruling on the anchor asks the finding to record that the
episode ended, or to close. `patrol-finding.sh --cleared` is that record. Its
first version kept it in a metadata key of the pack's own, `finding.cleared_at`,
with a note line, and named no Gas City or bd primitive it had looked for, so
the arch check asked for the search
([review-arch.md](../../docs/review-arch.md#the-checks), check 1).

bd ships the mechanism: a bead's operational state, set with `bd set-state`,
which keeps the current value as a `<dimension>:<value>` label and records each
change as a closed event bead under the bead. The change composes it and drops
the key. The rest of the search found nothing closer to the need.

## The surface and the need

- `patrol-finding.sh --key <key> --cleared --message <text>` finds the bead a
  recurrence of the key would land on, or else a bead held at `blocked` with
  nothing left to wait on, and records there that the situation ended. It files
  no finding and closes nothing. With no live bead it records nothing and exits
  0, and a failed lookup or a refused write exits 1, so the caller retries.
- A later report that lands on that bead records that the situation is back,
  and counts the occurrence as any recurrence does.
- boot-health is the caller. Its fresh-wisp pass runs `--cleared` for each
  cold episode that filed or refreshed the finding, and a record that does not
  land stays owed to a later fresh pass.

The need has three parts. A reader can tell a finding whose situation ended
from one still recurring without parsing its notes, and can see when and why it
ended. The bead stays open, because the work a finding asks for, which for a
cold deacon is whatever made it go cold, is not done when the situation ends.
The next episode lands on the same bead, so the first reaction that disposed of
it stands.

## Where the search looked

Each was read on 2026-10-27, UTC:

- Gas City at main `45563e2abf21`: its documentation, its engineering docs, the
  `core` pack it bundles from its own repository, and its source.
- Every pack in `gastownhall/gascity-packs` at main `dac12a4a802c`, and the
  packs Gas City bundles, at the packs commit its `go.mod` pins,
  `66c672b5ed00`.
- bd at main `2ef4df339a44`, and at `v1.3.2` (`9b65b9e198ac`), the version Gas
  City's `go.mod` pins.

The search covered a bead's status and the verbs that change it, deferral,
gates, labels and bd's operational state, bd's typed event beads, its events
journal, metadata, Gas City's event log and mail, and the detector orders core
ships. In every pack it looked for how a detector reports a situation and what
it records when the situation ends, with terms such as `set-state`, `bd state`,
`label add`, `recovered`, `episode` and `all clear`. Each pack's hits were
tallied, and the ones about detectors were read.

## What Gas City ships near the need

### A bead's status, deferral and gates

- bd's [Labels](https://beads.gascity.com/core-concepts/labels) page splits a
  bead's state in two. "Structured fields (status, priority, type)" are "Core
  workflow state", and status is "Where the issue is in the workflow". Closing
  a finding when its situation ends would say its work is done, and that work
  is still owed. The close would also cut off what the first reaction started:
  a fix routed to a pool, or a question put to the operator. The next episode
  would then find no live bead, so `patrol-finding.sh` would file a fresh one
  naming the closed one in `finding.recurrence_of`, and a fresh first reaction
  would run.
- [`bd defer`](https://beads.gascity.com/cli-reference/defer) hides a bead from
  ready work until a time. That pauses a bead's work, and records nothing about
  the situation it tracks.
- A [gate](https://beads.gascity.com/cli-reference/gate) is a wait that
  resolves when its condition does. A finding does not wait on its situation
  ending, so nothing would block on such a gate.

### Operational state: labels and events

- The Labels page's
  [Labels as State Cache](https://beads.gascity.com/core-concepts/labels#labels-as-state-cache)
  is the pattern for the rest: "Labels can cache operational state for fast
  queries, enabling patterns where beads track both immutable history (events)
  and current state (labels)." Its dimensions include `health:healthy` and
  `health:failing`, and it states that "Events are the source of truth. Labels
  are a cache for fast queries."
- [`bd set-state`](https://beads.gascity.com/cli-reference/set-state)
  `<issue> <dimension>=<value> --reason <text>` runs the pattern as one
  command: it "Creates an event bead recording the state change (source of
  truth)", "Removes any existing label for the dimension" and "Adds the new
  dimension:value label". bd's source agrees at main and at `v1.3.2`
  (`runSetState` in bd's `state` command). The event is a closed bead of type
  `event`, which bd's `TypeEvent` describes as "a system-internal type used by
  set-state for audit trail beads". It is filed at priority 4 as a parent-child
  child of the subject, and its description carries the reason. The label swap
  is one guarded update. A dimension already at the value writes nothing.
  [`bd state`](https://beads.gascity.com/cli-reference/state)
  `<issue> <dimension>` reads the value.
- Gas City uses the pattern for its own state. Its engineering doc "Hold and
  Blocked Label Conventions" sets a bead's `hold:<value>` with
  `bd set-state <id> hold=<value> --reason "..."`, which it calls "Structured,
  audited (files an event bead)", and it says to set either value "never with a
  plain `bd label add`". Gas City's dispatcher reads those two values, from
  `DispatchHoldLabels` in package `beadmeta`, and bd's `human` label, from
  `HumanLabel` there. No Gas City code reads a `situation:` label.
- That covers the need. The value says whether the situation is over, the event
  says when it changed and why, and each later change is one more event.
- A plain `bd label add` keeps the cache without the record, which both the
  Labels page and Gas City's conventions rule out. `bd create -t event`, with
  `--event-category` and `--event-target`, files a typed event bead without the
  label. That is the half of the pattern `bd set-state` writes for itself.

### Logs and journals

- bd's [events journal](https://beads.gascity.com/cli-reference/events)
  "records every committed issue mutation as an ordered, replayable row". It is
  off by default, kept for 7 days or 100,000 rows by default, and kept per
  branch and per replica. It is a replay feed for integrations. It would carry
  the write that records the end, and no reader of a finding looks there.
- Gas City's event log takes a custom event through
  [`gc event emit`](https://docs.gascity.com/reference/cli#gc-event-emit)
  `<type> --subject <bead>`. "Recording is best-effort", and "the event bus does
  not acknowledge durable persistence". The event is not on the bead, and
  nothing reads it as the bead's current state.
- `gc mail send` is the channel boot-health leaves, because the operator does
  not read the `human` mailbox. Core's `spawn-storm-detect` order mails once
  when a bead's reset count crosses its threshold, deduplicated per bead, and
  records nothing when the storm ends: it drops its own count once the bead
  closes.

### Metadata

bd's [Issue Metadata](https://beads.gascity.com/core-concepts/metadata) page
calls metadata "the preferred extension point for data that is specific to an
integration, orchestrator, team workflow, or experimental automation", and
reserves only the `bd:` and `_` prefixes. A pack key such as
`finding.cleared_at` is allowed there. It would stand in for the state bd's own
mechanism records, though, and only the pack would read it.

### Detectors in Gas City and its packs

- The detectors among core's orders at Gas City main mail a person or repair
  through a `gc` command: `spawn-storm-detect` as above, and `beads-health`,
  which runs `gc beads health`. Neither files a finding, and neither records
  that a situation ended.
- Gas Town's boot patrol (formula `mol-boot-patrol`) judges the deacon from its
  patrol wisp and its pane. It nudges the deacon or files a `warrant` bead for
  the dog pool, and records nothing when the deacon recovers.
- Gas Town keeps episode state in metadata of its own. Its `pr-merge-reconcile`
  command escalates "once per episode" by reading back the `pr_state` it
  recorded, and its witness patrol marks a recovered bead with
  `--set-metadata recovered=true`. Those are pack keys, the same choice as
  `finding.cleared_at`, and not a primitive.
- No pack calls `bd set-state` or `bd state`, at packs main or at the bundled
  commit. The other hits for the search terms recover other things: a dead
  worker's bead, branch or worktree in Gas Town and the build pack, a message
  or a delivery in the Discord and full Slack packs. One more is a review
  comment template's "All clear".

## What the change does with it

- `--cleared` runs `bd set-state <bead> situation=cleared --reason <message>` on
  the bead it finds. A clear of a bead already at `cleared` writes nothing.
- A report that lands on a bead whose `situation` reads `cleared` first runs
  `bd set-state <bead> situation=active --reason "reported again (occurrence N)"`,
  then counts the occurrence. A return that does not land counts nothing, so
  the caller's retry reads the bead as cleared again and records both.
- The finding's status and notes are left as they are. The events under the
  bead are its history, and `bd state <bead> situation` reads its state. A bead
  that no clear has reached carries no `situation` label.
- `finding.cleared_at`, the clear's note line and the forced note on a return
  are gone, and the change registers no metadata key.
- The board rolls up a parked or human-routed bead's parent-child children as
  the work it decomposed into. bd's event is such a child, so the board skips
  any child of bd's `event` type, which bd defines as an audit record. Without
  that, a finding that cleared would read as one whose children had all closed.
- `bead-context.sh --horizon` counts a bead's children, done ones included, in
  the snapshot a converse sitting reads at prime, and the converse-prep skill
  runs it on every subject, a finding included. It leaves an event out by the
  same rule, so the snapshot counts no state change as finished work.
- Elsewhere a closed event changes no decision. `live-work.sh` counts only open
  children as live work, `gc-helm.sh`'s park survey lists only beads that are
  not closed, and `queue-priority.sh` moves no closed bead's priority.
  `gc-bd-universe.sh` lists a bead's children by title for a sitting, through
  `bd children`, which includes closed ones, and an event's title names the
  state change.

The `situation` dimension and its two values are data in bd's state slot, as
Gas City's own `hold:` values are. The change adds no bead kind or lifecycle
state, so it adds no pack noun and needs no warrant
([review-arch.md](../../docs/review-arch.md#the-checks), check 2). No warrant
in [warrants.md](../../docs/warrants.md) covers a path or key it touches
(check 4).

This answer changes if Gas City or bd ships a kind of bead for a recurring
situation with a resolved state of its own, or if Gas City starts reading a
`situation:` value as it reads `hold:`. A finding would then move onto that.
