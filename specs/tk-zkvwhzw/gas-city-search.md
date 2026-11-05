---
name: Gas City search for the set-aside upstream finding
description: Use when you need the evidence that bd and Gas City primitives carry an upstream finding set aside for the operator, which upstream symbol each part composes, or why the change adds no script, pack kind, metadata key or reader code for it.
---

# Gas City search: an upstream finding set aside for the operator

The change records a problem an agent finds in software the rig does not own as
an upstream finding, set aside with nothing drafted and nothing asked, gathers
the findings in one list, and lets the operator take one up in a conversation.
It alters operational surface: it retires `upstream-finding.sh`, the keys it
wrote and the task kind it wrote, `upstream-send`, gives bd's `deferred` status
a use in the pack, and gathers the findings by a label, `upstream-finding`,
with no pack kind in the retired one's place. Each primitive searched is below,
with what it covers.

Read at `gastownhall/beads` main 6d713a748 and `gastownhall/gascity` main
a91df0b85 on 2026-11-05, and at `gastownhall/gascity-packs` main 796d7ecd7 the
same day. The city runs bd 1.3.2 and gc 1.4.3, and where a line says
"observed", the behaviour was also run on those.

## What composes the finding

**Set aside, out of every ready queue: bd's `deferred` status.** Covers it.
`deferCmd` in `cmd/bd/defer.go` defines it: deferred issues "are deliberately
set aside - not blocked by anything specific, just postponed for future
consideration", "don't show in 'bd ready' but remain visible in 'bd list'", and
a defer without a date "is the indefinite icebox: it stays deferred until
someone runs 'bd undefer'". `StatusDeferred` in `internal/types/types.go` is
"Deliberately put on ice for later". Gas City keeps the deferral when it
collapses bd's statuses: `normalizedBdReadState` in `internal/beads/bdstore.go`
says bd's ready query "filters on the raw status, so a row the store still
records deferred is never served, whatever its date", so `gc ready` and the
pools' work queries never offer one.

**Filed set aside in one write: `bd create --status`.** Covers it.
`cmd/bd/create.go` validates `--status` against the built-in statuses, deferred
among them, and creates the issue in that status, so the label, the status and
the edge ride one create. Observed in a scratch store on bd 1.3.2: `bd create
... --status deferred -l upstream-finding --deps discovered-from:<work>` read
back deferred, labelled and linked, with no `task_kind`; `bd ready` left it out
and `bd list --label upstream-finding` listed it; the work bead it hung from
still closed.

**Where it was hit: bd's `discovered-from` dependency.** Covers it.
`DepDiscoveredFrom` in `internal/types/types.go` is an association type, apart
from the workflow types that "affect ready work calculation", so the edge
records provenance and holds nothing.

**One list across the rig stores: `gc beads list --label`.** Covers it.
`newBeadsListCmd` in `cmd/gc/cmd_beads.go` lists "beads across all rigs, routed
through the supervisor API when the controller is alive and falling back to a
direct multi-store read otherwise", with `--label`, `--status` and `--all`
filters, and `collectBeadsAcrossStores` reads every rig store and the city
store. Observed on gc 1.4.3: one call returned beads from every rig store, the
suspended rigs' included, and the city store.

**Gathering by status instead of a label: `gc beads list --status deferred`.**
Does not cover it. `mapBdStatus` in `internal/beads/bdstore.go` maps bd's
statuses onto Gas City's three, so every status but `in_progress` and `closed`
reads `open`. Observed: `gc beads list --status deferred` returned nothing,
through the API and with `GC_NO_API=1`, while a rig store held two deferred
beads that a plain `gc beads list` printed as `open`. So the label gathers the
list. Every finding is filed deferred and leaves the list only by closing, so
`--label` alone lists the findings that wait, and `--all` adds what became of
the rest.

**A deferral Gas City's storage split refuses.** Not in the way.
`docs/runbooks/split-storage-classes.md` ("Holds") refuses "an undated
deferral" only among the beads it relocates, and it relocates the five
infrastructure classes. Tasks stay on the work ledger, so a finding never meets
that refusal.

## What the change does not build

**A question to the operator: Gas City's human gate.** Searched as the way a
finding reaches a person, and left out on purpose. `bd gate create --type=human`
(`cmd/bd/gate.go`) blocks a bead until a person resolves the gate, so it puts
the finding on the operator's list of owed items, which is what the operator's
ruling removes. The gates already filed on parked sends are withdrawn through
`bd gate resolve`, by `human-gate.sh --retract`, when those beads move into the
list.

**A send.** The `github` pack in `gastownhall/gascity-packs` writes as a GitHub
App installation (`comment-issue`, `create-pr`), which is a send path, and
nothing here sends. No pack there records a problem found in third-party
software, uses bd's deferred status, or hangs a `discovered-from` edge: a grep
of the whole repository for `bd defer`, `status deferred`, `icebox`,
`discovered-from`, `upstream issue`, `security policy`, `SECURITY.md` and
`private vulnerability` found nothing that does.

**A writer script.** One `gc bd create` carries the whole finding, so the
external-issue skill gives that command and `upstream-finding.sh` goes with its
test. Its command quoting and round-trip check, its four refusals, its send key
and re-run handling, and the human gate it filed have nothing left to guard,
because nothing is drafted. tk-1hzqsmv's gap, a `-R` written attached or inside
a word of short flags, lived in that script's parse. No parse of a `gh` command
remains on the finding's path, and the origin guard, which stays, reads such a
`-R` as gh does.

**Reader code.** A deferred bead is already left alone by every pack reader
that offers work or asks the operator. The liveness sweep classifies only
`bd ready --unassigned` rows (`liveness_classify` in
`assets/scripts/liveness-classify.sh`), and the proactive scan reads only
`gc bd ready` (`tools/gc-proactive.sh`). The helm board's default backend
gathers beads at bd's `open` status, and its supervisor backend admits a bead
only on a gate, a conversation or a metadata anchor (`metadataAnchors` in
`services/helm/internal/source/beads.go`). The doctor checks that read deferred
beads look for a mark: a hold marker (`check-wait-is-an-edge`), a `blocks` edge
through `bd blocked` (`check-blocked-work-armed`), an arm
(`check-armed-dispatch-owed`), or a `merge_result` or a retired key
(`check-state-space`). A finding carries none of them.

**A kind for the finding: bd's issue type, or the pack's `task_kind`.**
Searched as a way to mark a bead as a finding, and not needed. bd ships kinds
of its own: `typesCmd` in `cmd/bd/types.go` lists the built-in issue types and
the custom ones a store registers under `types.custom`, the set `bd create
--type` accepts. The pack names its own kinds in `task_kind`
(`docs/component-model.md`, I12), and a kind the pack defines is a pack noun
that needs a warrant (`docs/foundation.md`, boundary 2). A finding needs
neither. Nothing counts findings or branches on one: the operator's list only
shows them, which the label already does through `gc beads list --label`
above, and the skill's read-back checks the status and the label. A custom
type would also have to be registered in every store a finding can land in,
for no reader. So a finding is a `task` with no `task_kind`, the label only
gathers the list, and the change adds no pack noun. The open parked sends that
move into the list lose their `upstream-send` kind in the move (tk-0sys1v6),
and the closed ones keep it as history.

**A metadata key.** The finding's content is its description and its edge, and
the skill's create sets no metadata. The four keys `upstream-finding.sh` wrote
stay registered as retired in `lifecycle/lifecycle.toml`, because parked sends
that move into the list keep their drafted command as a starting draft.

## Limits

- A finding left set aside after a conversation carries the headline the
  sign-off wrote. Settled by `--no-wait`, it is no hold marker, and the board's
  supervisor backend shows such a bead in its low band of items to find again,
  never as an attention item.
- `bd undefer` would put a finding in front of the ready readers as ordinary
  work. Nothing in the pack runs it, and the skill gives no step that does.
- `gc beads list` prints a waiting finding as `open`, for the reason above.
