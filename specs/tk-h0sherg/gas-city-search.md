---
name: Gas City search for an ask that waits (tk-h0sherg)
description: The primitives searched in bd and Gas City for filing a review ask that waits on another bead from its first write, with what each covers and why gctk still checks the waited bead's id prefix and store itself. Read it when building or reviewing `gctk review ask --waiting-on` or the sign-off's `--rework-waiting-on`, as AGENTS.md asks of a change that adds a flag.
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

## Refuse a wait whose edge would hold nothing

**Not covered on every transport, and a store holding the bead does not cover
it.** bd decides whether an edge is local by the id prefixes of its two beads,
not by whether the store holds the far bead. gctk refuses, with nothing filed,
an ask on a PR's bead of another prefix than the one its store gives the ask, a
wait on a bead of another prefix than the PR's bead, and then a wait on a bead
of that prefix that the PR's store does not hold.

- bd classifies an edge by prefix. `IsExternalDepTarget` in
  `internal/storage/issueops/dependencies.go` reads an edge whose two ids carry
  different prefixes (`ExtractPrefix` in `internal/types/id_generator.go`) as
  an edge onto another repository's bead, and it reads no row to decide. The
  create's insert (`PersistDependenciesWithOptionsResult` in
  `internal/storage/issueops/create.go`, through `ClassifyDepTarget`) stores
  such an edge in `depends_on_external`, the one target column with no foreign
  key into the store's issues. bd's blocked rule joins the waited bead through
  `depends_on_issue_id` (`directly_blocked` in
  `internal/storage/schema/migrations/0046_add_is_blocked.up.sql`), and bd
  marks a bead blocked only by an edge onto an issue or a wisp
  (`markDirectBlockingDependencySourceInTx` in
  `internal/storage/issueops/dependencies.go`), so such an edge never holds the
  bead.
- A store can hold a bead of another prefix. A create at an explicit id outside
  the store's prefix lands under bd's `--force` (`ForceIDPrefix`), or when the
  store's `allowed_prefixes` names that prefix (`ValidateIssueIDPrefix` in
  `internal/storage/issueops/create.go`), and the conformance case
  `RunLifecycleCreateRefusesAForeignIDPrefix` in
  `backend/conformance/lifecycle_create_contract.go` creates one and reads it
  back. An edge from the ask onto such a bead is still an edge between two
  prefixes, so finding the bead in the store does not make the wait hold.
- The ask takes the prefix bd's create mints an id from: the `issue_prefix`
  row of the store's config table, less a trailing dash. The direct path reads
  it with `ReadConfigPrefix` (`internal/storage/issueops/helpers.go`), through
  `NewBatchContext`, for `assignCreateIssueIDInTx`
  (`internal/storage/issueops/create.go`). The proxied-server path reads the
  same row in `resolveTopLevelPrefix` (`internal/storage/domain/issue.go`).
  Neither takes the prefix from config.yaml, and `ReadConfigPrefix` fails on a
  store without the row, saying an `issue-prefix` in config.yaml does not
  satisfy it. The
  ask's own edge onto the PR's bead holds only when the two share a prefix,
  and the store can hold a PR's bead of another prefix, as above. A wait holds
  the ask only when it carries the PR bead's prefix too, which is the rule the
  `waits` skill gives every wait edge.
- `bd config get issue_prefix --json` reads that row on both paths
  (`configGetCmd` and `openWorkspaceConfig` in `cmd/bd/config.go`, then
  `GetSetting` in `internal/workapi/storeworkspaceconfig/workspaceconfig.go` or
  `internal/storage/uow/workspace_config.go`). `issue_prefix` is not a key bd
  reads from config.yaml alone (`IsYamlOnlyKey` in
  `internal/config/yaml_config.go`). `bd where --json` is not that read.
  `cmd/bd/where.go` names config.yaml's `issue-prefix` or `issue_prefix` ahead
  of the row, and on a server or proxied-server store it never reads the row
  (`shouldReadWherePrefixFromStore`). A probe on the city's bd over a proxied
  scratch store of prefix `pb` showed both. `bd where` named no prefix until
  config.yaml named `rb`, and then named `rb`, while `bd config get
  issue_prefix` named `pb` and `bd create` minted `pb-83k`. The store
  acceptance case `TestStoreAcceptanceTheCreatesPrefix`
  (`services/gctk/internal/gcbd/acceptance_test.go`) builds the same store and
  holds gctk's read to `pb`.
- For a bead of the PR bead's prefix, bd's create paths differ. The direct path
  resolves each `--deps` target in its store (`resolveDepSpecTargets` in
  `cmd/bd/create_deps.go`), and an unknown target fails the create. The
  proxied-server path (`runCreateProxiedServer` in
  `cmd/bd/create_proxied_server.go`) parses the specs and resolves none.
- A probe on the city's bd over a proxied scratch store showed an edge between
  two prefixes filing: `bd create --deps blocks:<pr>,blocked-by:zz-nope` filed
  the bead with an edge onto `zz-nope`, and `bd blocked` left the bead out. A
  missing target with the store's own prefix was refused.

So a wait on a bead of another prefix files with an edge that holds nothing on
either path, whether or not the store holds that bead, and the ask reads clear
and the race stays with no sign. Gas City's `gc bd` adds no check, as above.
gctk's check reads the prefix the PR's store gives the ask with `gc bd config
get issue_prefix`, pinned to that store, and files nothing when the read fails
or names no prefix. It compares that prefix and each wait's with the PR bead's,
then reads each waited bead in the PR's store before the create, and it is the
same on every transport.

## Report an ask a re-run finds that does not wait

**Not covered.** gctk finds an ask of the same source and reason before it
files, and nothing in bd or Gas City compares that ask's edges with the waits a
later call names. gctk reads the found ask's own `blocks` edges and refuses the
call when one named wait is missing, naming the ask, so a sitting never takes
an ask that a run can work early as one that waits.
