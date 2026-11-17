---
name: Gas City search for an ask that waits (tk-h0sherg)
description: The primitives searched in bd and Gas City for filing a review ask that waits on another bead from its first write, with what each covers and why gctk still checks the waited bead's store itself. Read it when building or reviewing `gctk review ask --waiting-on` or the sign-off's `--rework-waiting-on`, as AGENTS.md asks of a change that adds a flag.
---

# Gas City search for an ask that waits

This change adds `gctk review ask --waiting-on <bead>`, and the sign-off's
`--rework-waiting-on <bead>` that reaches it through `converse-rework.sh`. The
need is an ask, the task a PR's review run takes, that waits on another bead
from the write that files it, so that no landing pass reads the ask clear
before its wait stands. The sources read are `gastownhall/beads` v1.3.4
(7ef2fd05eb0c), the bd the city runs, and `gastownhall/gascity` main
6cf1cccd640d (2026-11-17). Each bd claim is read at v1.3.4, and one that also
holds at bd main 8cdfa796a8f5 (2026-11-13) says so.

## File the bead with its wait in one write

**Covered: bd create's `--deps blocked-by:<id>`.** `parseDepSpec` and
`canonicalDependencyType` in `cmd/bd/create_deps.go` read `blocked-by:<id>` as
the new bead's own `blocks` edge onto `<id>`, where a `blocks:<id>` entry gives
`<id>` the edge instead. Each `--deps` edge rides the one create request, so
the bead lands with its edges or not at all, and the dependency insert's
`HasCycle` check (`internal/storage/domain/db/dependency.go`) refuses a cycle
inside that create. gctk's ledger already sends a filing's edges as one
`--deps` list, so the ask's wait joins its `blocks:` edge onto the PR's bead
and its `discovered-from:` edge in that list. `create_deps.go` is unchanged at
bd main, and the cycle check still stands there.

**Gas City adds nothing between.** `newBdCmd` in `cmd/gc/cmd_bd.go` forwards
the arguments after `gc bd` to bd unchanged, except on a `list` of the wisps
tier and on a ready frontier, so a create's `--deps` reaches bd as written.

## Refuse a wait on another store's bead

**Not covered on every transport.** gctk reads each waited bead in the store
that holds the PR's bead, and refuses one that store does not hold, with
nothing filed.

- bd's direct create path resolves each `--deps` target in its store
  (`resolveDepSpecTargets` in `cmd/bd/create.go`), and an unknown target
  fails the create.
- Its proxied-server path (`runCreateProxiedServer` in
  `cmd/bd/create_proxied_server.go`) parses the specs and resolves none. The
  insert stores an edge onto an id whose prefix names another repository as an
  external target (`IsExternalDepTarget` in
  `internal/storage/issueops/dependencies.go`), in the one target column with
  no foreign key into the store's issues. bd's blocked rule joins the waited
  bead through `depends_on_issue_id` (`directly_blocked` in
  `internal/storage/schema/migrations/0046_add_is_blocked.up.sql`), so such an
  edge never holds the bead.
- A probe on the city's bd over a proxied scratch store showed both halves:
  `bd create --deps blocks:<pr>,blocked-by:zz-nope` filed the bead with an
  edge onto `zz-nope`, and `bd blocked` left the bead out. A missing target
  with the store's own prefix was refused.

So whether bd refuses such a wait depends on the store's transport, and where
it does not, the ask reads clear and the race stays with no sign. Gas City's
`gc bd` adds no check, as above. The ledger read gctk makes before the create
is the check, and it is the same on every transport.

## Report an ask a re-run finds that does not wait

**Not covered.** gctk finds an ask of the same source and reason before it
files, and nothing in bd or Gas City compares that ask's edges with the waits a
later call names. gctk reads the found ask's own `blocks` edges and refuses the
call when one named wait is missing, naming the ask, so a sitting never takes
an ask that a run can work early as one that waits.
