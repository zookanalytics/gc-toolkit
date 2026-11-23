---
name: Gas City search for keeping the waits a re-homed or folded close would release
description: What tk-qx5xr3w looked for in bd and Gas City before bead-rehome.sh moved the waits on a re-homed, folded or ruled fixed-upstream bead onto its successor, why the carry is one bulk dep add, why a successor in another store refuses the close while a bead waits, and what the 2026-11-23 census and repair found. Read it when judging how bead-rehome.sh treats what waits on a bead it closes, or a proposal to hand that to bd or Gas City.
---

# Gas City search for keeping the waits a re-homed or folded close would release

bd was read at `github.com/steveyegge/beads` tag v1.3.4 (7ef2fd05eb0c), the
commit the city's `bd` reports as `1.3.4 (7ef2fd05e+patched)`. Gas City was read
at `gastownhall/gascity` main 97c0c9b3b1. The live stores were read on
2026-11-23.

## The need

A close under `re-homed`, `folded` or `duplicate` moves the bead's work to its
successor, and so does a `fixed-upstream` close a ruling made before its fix
landed. A bead that waited on the closed bead needs that work, so it must go on
waiting until the successor has closed or shipped. Under `not-needed` nothing
carries the work and the wait may end with the close. `bead-rehome.sh` already
kept the waits of a duplicate (specs/tk-1tfzr71.13/gas-city-search.md, "Why the
sweep goes with no replacement"). The other kinds released them.

## What bd provides, and where it stops

- **The ready rule never follows a `supersedes` edge.**
  `DependencyType.AffectsReadyWork` (`internal/types/types.go`) is true for
  `blocks`, `parent-child`, `conditional-blocks` and `waits-for` only. So a bead
  blocked by the closed bead goes ready at its close.
- **A blocks edge holds only within its store.** The blocked state a ready read
  uses joins a blocks edge to a bead of the same store
  (`markBlockedTemplateForIssues`, `internal/storage/issueops/blocked_state.go`:
  `JOIN issues t ON t.id = d.depends_on_issue_id`). An edge whose far bead has
  another prefix is stored as an external target (`ClassifyDepTarget`,
  `internal/storage/issueops/dependencies.go`), which that join never reaches. So
  a blocks edge onto a successor in another rig's store holds nothing.
- **`bd supersede` moves no wait.** `runSupersede` (`cmd/bd/duplicate.go`) adds
  the `supersedes` edge and closes the bead through `CloseIssue`, and leaves
  what depends on the bead as it was.
- **bd's cross-project wait needs a ship step.** An external reference,
  `external:<project>:<capability>`, blocks until the project the store's
  `external_projects` config names has a closed bead labeled
  `provides:<capability>`, a label `bd ship` adds (`bd dep add --help`,
  `cmd/bd/ship.go`). Nothing in the city runs `bd ship` when a bead closes, and
  the gc-toolkit store sets no `external_projects` ("external_projects (not
  set)", read 2026-11-23). Composing it would make the pack own a ship step
  after every successor's close, so it is not composed.
- **The bulk add is the write that fits.** `bd dep add --file -` lands every
  edge of the request in one transaction and runs one cycle check of the whole
  graph in memory before the commit (`ExecuteAddDependencies` and
  `checkAddedEdgesForCycles`, `internal/storage/issueops/dependency_editor.go`).
  With `--no-cycle-check` it skips the per-edge probe, which a single-edge add
  always runs whatever its flags (the positional branch of `cmd/bd/dep.go` calls
  `addDependencyEdgesDirect` with `false`). That probe walks the store's graph
  from the blocker, and in this city's stores it has failed its read timeout on
  adds onto members of the large simplification epic, while the bulk write
  landed the same edges. This change's own repair landed an edge onto that epic,
  tk-1tfzr71, through the bulk write on 2026-11-23. A bulk request bd refuses,
  for a cycle, a parent chain or an edge of another type on the pair, commits no
  edge of it.

## What Gas City provides, and where it stops

- **Nothing reads a disposition edge or moves a waiter.** At main 97c0c9b3b1
  the only Go use of `supersedes` or `duplicates` as an edge type is the
  `duplicates` verb in the split-city allowlist (`cmd/gc/bd_split_allowlist.go`).
- **A convoy cannot hold a bead on another store's bead.** `gc convoy create`
  says "Every issue's ID prefix must route to that same store"
  (`cmd/gc/cmd_convoy.go`), and `gc convoy check` closes a convoy once its
  children close. So a convoy would hold a waiter only on a successor in its own
  store, where a blocks edge already does.

## What the pack does, then

`bead-rehome.sh` is the one writer of a close with a successor, and it moves the
waits itself, with no new verb, mode or key:

- Under every kind but `not-needed`, while the successor has neither closed nor
  shipped, each open bead the origin blocks gains a `blocks` edge onto the
  successor before the close, in one bulk `dep add --file - --no-cycle-check`,
  and a bead that comes to wait during the close gains it just after.
- A waiter a ruling has recorded a PR-close disposition on (`pr-dispose.sh`,
  `gc.pr_close_disposition_kind`) gains no edge. It closes under that ruling and
  waits for nothing more. That is the anchor `scaffolding-sweep.sh` finds when
  it carries one of the anchor's findings forward to a new bug just before the
  anchor's own close, through `pr-facts.sh`'s close arm or the refinery's arm 9.
  An edge onto the bug would hold that close, which is the stranded anchor the
  sweep's order exists to prevent. Both scripts are retired by the deletion
  plan, and neither changes here.
- A successor in another store refuses the close while a bead waits on the
  origin, as a duplicate's close already did, because no edge from the origin's
  store holds there. The refusal names the human gate that holds a waiter that
  needs the work and the `dep remove` that ends a wait, and the same call run
  again closes the bead once no waiter is left. The landing order (`gctk pr
  reconcile`) reads that refusal as a close held for now and reads the bead
  again on its next run. The bead stays open, so its waiters stay held.

## The census and the repair, 2026-11-23

One read-only SQL query per store listed each open bead blocked by a closed bead
whose `supersedes` edge names a successor, with the kind its close note names.
Leaving out `not-needed`, a successor that has closed or shipped, and a waiter
that is its own successor or waits on it already, four beads had lost a wait on
work still open, and each now waits on its successor:

| Waiter | Closed bead | Kind | Successor |
|---|---|---|---|
| tk-3twm8f | tk-d3k4qm | re-homed | tk-20rfkt |
| tk-nt5uda | tk-y0abyu | folded | tk-1tfzr71 |

The other two are in another rig's store, both waiting on one re-homed bead
whose successor is open, and tk-qx5xr3w's notes name them. Neither had another
open blocker, so both had sat in `bd ready` since that close on 2026-11-13. Of
the six beads tk-qx5xr3w named on 2026-11-07, tk-ssm8qns.3, tk-g587e9f and
tk-ssm8qns.12 have closed, and tk-slnm11l's successor, tk-1tfzr71.22, has
shipped. No store held an open waiter of a bead closed under any kind but
`not-needed` onto a successor in another store.
