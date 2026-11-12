---
name: Gas City search for holding an incomplete Epic at its close
description: The search the arch check asks for before the close gate and I15 hold an epic that carries no hypothesis unless it is a Delivery. What bd and Gas City ship for refusing or reporting a close by issue type, metadata key or parent, read at named upstream commits, and why the change grows the pack's own gate clause and doctor check instead. Read it when checking whether either can move onto a bd or Gas City primitive.
---

# Gas City search for holding an incomplete Epic at its close

An epic with no hypothesis is a Delivery when its parent is an epic, and an
incomplete Epic otherwise (`docs/epics.md`). Until this change the close gate
(`finalize-gate.sh` `clause_epic_ruling_recorded`) and the doctor's I15 passed
both. This change holds the incomplete Epic in both, unless it is ruled close
with its outcome or disposed. The clause gains a refusal, and I15 gains a
diagnostic and lists a store's open epics as well as its closed ones. A new
diagnostic in a doctor check is operational surface, so the arch check asks what
bd and Gas City already ship for the need
([review-arch.md](../../docs/review-arch.md#the-checks), check 1).

## The need

- A close of an epic that carries no hypothesis and whose parent is not an epic
  is refused, unless it carries the close ruling with its outcome or a
  disposition.
- A close that ran no such check is reported after the fact.
- A Delivery passes both, so the rule reads the parent's type.

## Where the search looked

Each was read on 2026-11-12:

- bd at the build the city runs, 1.3.4 (`7ef2fd05e`, gastownhall/beads), and at
  upstream main `d76ade282`.
- Gas City at upstream main `6bd609f5b` (gastownhall/gascity).

The search looked for a close-time check that can refuse by issue type,
metadata key or parent, a hook that runs at a close, an order that reacts to a
close, and a doctor primitive. It also looked at what bd's rows already carry
about an epic's parent.

## What each one does, and why none covers the need

**bd's `validation.on-close`.** `validateCloseReasons` in `cmd/bd/close.go`
reads it (line 618 at `7ef2fd05e`, 666 at `d76ade282`) and runs
`validation.ValidateCloseReason` (`internal/validation/template.go`, the same at
both). That checks the close reason's text alone: empty, the default "closed",
or shorter than 20 characters. It reads no issue type, no metadata key and no
parent.

**bd's `validation.metadata`.** A field's schema, `MetadataFieldSchema`
(`internal/storage/metadata.go`, the same at both commits), has a type, values,
`required`, and a minimum and maximum, and no issue type or parent. So
`epic_hypothesis` cannot be required of an epic with no epic parent alone.

**bd's `on_close` hook.** `HookFiringStore` (`internal/storage/hook_decorator.go`
at `7ef2fd05e`) fires `on_create`, `on_update` and `on_close` "after successful
mutations", and inside a transaction "only after the transaction commits
successfully", so a hook cannot refuse the close it reports. Gas City's
troubleshooting page also says the native in-process store "does not run shell
hooks", and an executable hook moves a store off it
(`docs/getting-started/troubleshooting.md` at `6bd609f5b`, "Native Store Falls
Back Because Hooks Are Installed").

**bd's `epic close-eligible`.** Its help reads "Close epics where all children
are complete" (`cmd/bd/epic.go` at `7ef2fd05e`). That is the last-unit close the
epic contract forbids, not a hold on one.

**Gas City's `gc bd` admission.** Before bd runs, `doBd` (`cmd/gc/cmd_bd.go` at
`6bd609f5b`) refuses a mistyped metadata pair, a rig-qualified metadata value
the city does not configure, a SQL read blind to a relocated class, and a create
a split city would strand (`mistypedMetadataPairRefusal`,
`bdRigQualifiedMetadataRefusal`, `bdSQLRelocatedClassRefusal`,
`bdRelocatedClassCreateRefusal`). Each is built in for its own shape, none
refuses a close for what the bead is, and none takes a rule from config or a
pack.

**Gas City's event orders.** An order with `trigger = "event"` matches on the
event type alone: `On` "is the event type to match (for event triggers)", and
the `Order` struct has no field that filters an event's bead
(`internal/orders/order.go` at `6bd609f5b`). An order on `bead.closed` would
fire on every close in the city, after the close has landed, so it can only
report, which I15 already does without a firing per close.

## What the change composes

- **bd's show row.** `IssueDetails.Dependencies` is a list of
  `IssueWithDependencyMetadata` (`internal/types/types.go` at `7ef2fd05e`), each
  the far bead's whole `Issue`, its `issue_type` included, plus its
  `dependency_type`. The gate already reads the epic with one `gc bd show`, so
  it reads the parent's type off that row, with no second read.
- **bd's list row.** `IssueWithCounts` carries `parent`, "Computed parent from
  parent-child dep", and the row's edges carry `type` and `depends_on_id`, but
  not the far bead's type. So I15 reads a parent-child edge against the store's
  own epics. It lists them with the one `gc bd list --type=epic` per store it
  made before, with `--all` in place of `--status closed`, because a closed
  Delivery's parent may still be open.
- **Gas City's pack doctor check.** A check is a `doctor/<name>/` directory with
  a `doctor.toml` and a `run.sh`, and `gc doctor` runs every check the city's
  packs supply (`docs/guides/multi-agent-engineering-environment.md` at
  `6bd609f5b`, "Encode known mistakes as doctor checks"). I15 is one, and the
  report stays in it.

## What it leaves in place

A bare `gc bd close` still closes an incomplete Epic, because neither bd nor Gas
City holds a close on an issue type, a key and a parent's type. I15 reports one
afterwards, as it reports any epic closed without its ruling. The clause can
move onto bd once its close validation can scope a rule to an issue type, a
metadata key and the parent's type.
