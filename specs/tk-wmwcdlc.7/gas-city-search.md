---
name: Gas City search for an epic's hypothesis at its create
description: The search the arch check asks for before gctk adds `gctk epic create` and its bridge `assets/scripts/epic.sh`. What bd and Gas City ship for refusing or reporting a bead created without a metadata key, read at named upstream commits, and why the pack checks the key in the epic's own create rather than in bd's create validation, a bd hook or a Gas City event order. Read it when checking whether the command's check can move onto a bd or Gas City primitive.
---

# Gas City search for an epic's hypothesis at its create

An epic is a hypothesis that can be answered, and `docs/epics.md` makes a
hypothesis the one hard gate on filing one. Until this change nothing checked
`epic_hypothesis` before an epic closed. The close gate
(`finalize-gate.sh` `clause_epic_ruling_recorded`) and the doctor's I15 read the
key only at close, and nothing a filer reads when it files an epic named the
key. Of this rig's live top-level epics with no hypothesis, seventeen were filed
after the contract landed, every one by a converse sitting or the mechanik,
each with its own `gc bd create -t epic` (tk-wmwcdlc.5's census, recorded on
tk-wmwcdlc.7).

This change adds `gctk epic create <title> --hypothesis <sentence> [--handle]
[--boundaries] [--closure-condition] [--indicators] [--parent] [-d] [--rig]`
and the bridge `assets/scripts/epic.sh`, which execs it, because the work
skill's examples call every writer through the pack command. The command files
the epic with each contract field in its own key, in the create itself. It
refuses an epic whose parent is not an epic when it has no hypothesis, and files
nothing. An epic whose parent is an epic and that has no hypothesis is a
Delivery, and the command files it with no metadata. A gctk command and a
script are operational surface, so the arch check asks what bd and Gas City
already ship for the need ([review-arch.md](../../docs/review-arch.md#the-checks),
check 1).

## The need

- A top-level epic created with no `epic_hypothesis` is refused at its create,
  or reported at once.
- A Delivery, an epic whose parent is an epic, is exempt.
- The refusal or report reaches the filer while the operator's statement is in
  its context. A converse sitting files an epic as one of its last writes, then
  signs off and drains.
- Nothing polls. The operator, in converse sitting tk-vu6faf2 on 2026-11-05,
  about how a session's title reaches its terminal: "Any query to gas city is
  expensive if done often, so it needs to be a push change vs a pull to check
  if anything changed" (observation tk-dbsf5cu). Holding this need to those
  words is this change's reading.

## Where the search looked

Each was read on 2026-11-06 or 2026-11-07:

- bd at the build the city runs, 1.3.4 (`7ef2fd05e`, gastownhall/beads, the
  v1.3.4 release merge), and at upstream main `8c3eb30f3`: `bd lint --help`,
  `bd create --help`, its configuration reference, and its source.
- Gas City at upstream main `24c9f5f1f` (gastownhall/gascity): its docs, its
  engineering docs, the `core` pack it bundles, and its source.
- This city's event stream, for how often `bead.created` fires.

The search looked for a create-time validation that can require a metadata key,
a type-scoped validation of any kind, a hook that runs on a create, and an
order or event that reacts to a created bead.

## What each one does, and why none covers the need

**bd's `validation.on-create`.** `cmd/bd/create.go` reads it at create
(line 279 at `7ef2fd05e`) and runs `validation.LintIssue`, which checks the
description for the sections `bd lint --help` lists by type: a bug needs Steps
to Reproduce and Acceptance Criteria, a task Acceptance Criteria, an epic
Success Criteria. `lint.sections.<type>` adds sections, and "built-in
requirements are never relaxed" (`bd lint --help`). It reads the description,
not a metadata key. Set to `error`, it would refuse every task this city files
without an Acceptance Criteria section, and every Delivery, whose description
opens with `Aim:` and `Done when:` lines.

**bd's `validation.metadata`.** A metadata schema in config:
`validation.metadata.mode` is `none`, `warn` or `error`, and
`validation.metadata.fields.<key>` can be `required`
(`docs/reference/configuration.md`, `internal/config/config.go`
`MetadataSchemaFields`). `storage.ValidateMetadataSchema`
(`internal/storage/metadata.go`, the same at `7ef2fd05e` and `8c3eb30f3`)
checks every field it is given against every issue, and a field's schema has a
type, values, `required`, and a minimum and maximum, but no issue type. So
`epic_hypothesis` required would refuse every task, and no key can be required
of an epic alone or waived for a Delivery.

**bd's hooks.** An executable `.beads/hooks/on_create` runs after each create
(`internal/hooks/hooks.go`). It runs once the write has committed, "fire-and-forget",
and its stdout and stderr go into buffers kept for tracing
(`internal/hooks/hooks_unix.go` `runHook`), so it can neither refuse the create
nor print to the filer. Gas City removes the hooks it once installed
(`cmd/gc/hooks.go` `installBeadHooks`), and its troubleshooting page says
"Native `bd` store selection intentionally falls back to the subprocess-backed
store when executable `.beads/hooks/on_create`, `.beads/hooks/on_update`, or
`.beads/hooks/on_close` scripts are present", because "the native in-process
store does not run shell hooks" (`docs/getting-started/troubleshooting.md`,
"Native Store Falls Back Because Hooks Are Installed"). A hook would move each
rig's store off the native store, and would not run on it.

**Gas City's `gc bd create`.** `gc bd` is the city's admission boundary for a
write. Before bd runs, `doBd` (`cmd/gc/cmd_bd.go`) refuses a dropped
`--set-metadata` pair (`mistypedMetadataPairRefusal`), a lease owner or a route
whose rig the city does not configure (`bdRigQualifiedMetadataRefusal`), and a
create that a split city would strand in the ledger a relocated class is not
read from (`bdRelocatedClassCreateRefusal`). Each refusal is built in for its
own keys or shapes, and none takes a rule from config or from a pack: the city
config reference (`docs/reference/config.md`) has no setting for one, so a pack
cannot add the rule that an epic carries a key.

**Gas City's event orders.** An order with `trigger = "event"` and
`on = "bead.created"` fires when a created bead's event reaches the bus
(`docs/tutorials/07-orders.md`, the trigger table and its notes). Core's
`notify-on-human-gate-creation` order reports a new human gate that way
(`internal/bootstrap/packs/core/orders/notify-on-human-gate-creation.toml`).
It is the primitive for reporting at once, and it does not fit this need:

- The trigger names only the event type (`internal/orders/order.go`, `On`), so
  the order fires for every created bead. The city recorded 208 `bead.created`
  events in the hour before 2026-11-07T01:22Z. An order the tick fires runs
  with no vars (`cmd/gc/order_dispatch.go`: `fireCandidate` calls
  `launchResolvedDispatch` with nil vars and env), so an exec order learns the
  event only by reading it back, and each firing runs a `gc events` query, as
  core's script does. This rig filed 24 epics in the six weeks from
  2026-09-26. The order would query Gas City about a hundred times an hour to
  catch about four epics a week, a frequent query of the kind the operator's
  words above call expensive.
- A report reaches the filer only once the event is on the bus and the next
  order tick has run. By then a sitting that filed its epic just before its
  sign-off can have drained, so the report would need another reader to act on
  it.

## What the change composes

- One `gc bd create --metadata`, which the command runs itself. bd writes the
  metadata into the issue it inserts (`cmd/bd/create.go` at `7ef2fd05e`), so
  the epic exists with its contract or not at all. The exit and the reply say
  whether it was filed: an exit 0 whose reply names the new bead. `gc bd` exits
  4, with bd's reply passed through, when bd fell back to a store whose writes
  do not persist (`cmd/gc/cmd_bd.go` `bdSilentFallbackExitCode` at
  `24c9f5f1f`), so the command takes no id from a non-zero exit. Nothing reads
  the epic back, because the command takes no act on it after the create.
  gctk's `gcbd.Create` reads each key back after its create, and the command
  does not use it.
- The same create with no metadata, for a Delivery.
- `gc bd show`, or the supervisor API's read of a bead, for the parent's
  `issue_type`, which tells a Delivery from an epic of its own.

The refusal comes from the create the work skill gives for an epic, where the
filer reads it while the operator's statement is in its context, and it costs
nothing when no epic is filed. It takes the intent-level shape the operator
described in the same sitting, about a session's title: "It's where I think
wrapper scripts in gc-toolkit are actually valuable, they consolidated complex
logic into having an agent express intent instead of knowing the execution
logic of that intent" (observation tk-rtr0xzk). Reading those words as
covering an epic's create is this change's own.

## What it leaves in place

A bare `gc bd create -t epic` still files an epic with no hypothesis, because
neither bd nor Gas City refuses a missing key on one issue type at create. The
work skill gives `epic.sh create` as the epic's create, and converse-settle's
filing step and the Epic Checkpoint send a sitting to that skill to file an
epic. The close gate and I15 still read the key only at close, and both pass
an epic that has none. tk-wmwcdlc.6, filed and waiting on tk-wmwcdlc.5, makes
both hold such an epic unless it is a Delivery.

The check moves onto bd once `validation.metadata` can scope a field to an
issue type and exempt a child of an epic, or onto Gas City once it ships a
create-time check of that kind. The command then keeps only the contract's
mapping of fields to keys.
