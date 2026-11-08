---
name: Gas City search for the first-draft mark on an epic's board row
description: The search the arch check asks for before the helm board adds `hypothesis_first_draft` to each tile. What bd and Gas City ship for a draft state, for a ruling on an epic, and for a board that shows a bead's state, read at named upstream commits, and why the board derives the mark from two keys the epic already carries. Read it when you check the board's first-draft mark against what Gas City ships.
---

# Gas City search for the first-draft mark on an epic's board row

A hypothesis is a first draft until the operator's first ruling on its epic, so
an epic that carries `epic_hypothesis` and no `epic_ruling` has one
([docs/epics.md](../../docs/epics.md#the-contract-an-epic-carries)). Until this
change the board's epic row said nothing about the hypothesis, so the operator
could not tell from the board which hypotheses they had judged.

This change adds the key `hypothesis_first_draft` to each tile of the helm
board's output, which is `helm-svc board --json` and the web service's board
payload. The web board draws `hypothesis: first draft` beside the title of a row
where it is true. The change adds no metadata key, bead kind, state or script.
A new key in a service's output is operational surface, so the arch check asks
what bd and Gas City already ship for the need
([review-arch.md](../../docs/review-arch.md#the-checks), check 1).

## The need

- An epic's row says that its hypothesis is a first draft while the epic
  carries `epic_hypothesis` and no `epic_ruling`, and stops saying so once any
  ruling is recorded.
- The mark reads state the epic already carries, so nothing has to be written
  or cleared when a ruling lands.
- The operator sees it where they scan, on the board's web page, and owes
  nothing for it. The row keeps its band, its owed state and its needs.

## Where the search looked

Each was read on 2026-11-08:

- Gas City at upstream main `fdfec4c19` (gastownhall/gascity): its docs, its
  engineering docs, the packs it bundles, the API schema
  (`docs/reference/schema/openapi.json`), and the source of the dashboard the
  supervisor serves (`internal/api/dashboardspa/web/frontend/src`).
- bd at upstream main `2edea9ced` (gastownhall/beads): its docs, its status
  types (`internal/types/types.go`), its custom statuses (`status.custom`) and
  its epic commands (`cmd/bd/epic.go`).

The search looked for a draft or proposed state that bd or Gas City keeps for a
bead or for one of its fields, an epic model that records a ruling on a
hypothesis, and a board or dashboard that shows a state derived from a bead's
metadata or takes a pack's rule for a mark on a row.

## What each one does, and why none covers the need

**bd's statuses.** A bead is open, in progress, blocked, deferred, closed,
pinned or hooked (`internal/types/types.go`, the `Status` constants), and a
store can add its own statuses through `status.custom`. A status is the bead's
lifecycle. A first draft is not a stage of the epic's lifecycle. The epic stays
open and takes work while its sentence waits for a ruling
([docs/epics.md](../../docs/epics.md#elaboration-is-progressive)), so a status
for the draft would take the epic out of every read of open work. A label would
be a second record of what `epic_ruling` already says, and a writer would have
to keep the two in step, which is a converter
([review-arch.md](../../docs/review-arch.md#the-checks), check 3).

**bd's epic commands.** `bd epic status` shows "epic completion status", and
`bd epic close-eligible` closes "epics where all children are complete"
(`cmd/bd/epic.go`, `epicStatusCmd` and `closeEligibleEpicsCmd`). Both read an
epic's progress from its children. Gas City's formula spec treats an epic the
same way: a step with children compiles to an epic, and "epic closure in the
bead store follows the epic's children" (`docs/reference/specs/formula-spec-v1.md`).
Neither has a hypothesis or a ruling, and the pack's epic closes on a ruling and
never because its children closed
([docs/epics.md](../../docs/epics.md#how-an-epic-closes)).

**Gas City's dashboard.** It shows "agents and their sessions, beads, mail,
formula runs, and a health view" (`docs/getting-started/dashboard.md`, "What it
shows"). Which beads need the operator is decided by fixed rules over Gas City's
own markers: ready work nobody claimed, an escalated or help-requested block,
stalled work and a wait on a named human
(`attention/beadsNeedingAttention.ts`), and the mayor's decision question
(`attention/registry.ts`). It takes no rule from a pack and reads no key of the
epic's contract, so it has nowhere to show a first draft. Gas City's docs and
engineering docs name no draft or proposed state for a bead, and nothing in
them records a ruling on an epic.

**Gas City's API.** Each bead carries its metadata as a map of strings
(`docs/reference/schema/openapi.json`, `components.schemas.Bead`, property
`metadata`) on `/v0/city/{cityName}/beads`. This is the primitive the change
composes. The board's supervisor source reads an epic's metadata off that list,
and its beads source reads the same keys from the store, so both hand the
derivation `epic_hypothesis` and `epic_ruling` today.

## What the change builds, given that

The contract an epic carries is the pack's: its keys are registered in
`lifecycle/lifecycle.toml` under `[metadata.epic_stewardship]`, and neither bd
nor Gas City has a hypothesis or a ruling. The mark is therefore the board's
reading of those two keys, made at each render (`board.hypothesisFirstDraft`),
the way the board already reads a landed Delivery off an epic's metadata and
children. It stores nothing and defines no state of its own, so no writer keeps
it in step and no warrant is owed for a pack noun.
