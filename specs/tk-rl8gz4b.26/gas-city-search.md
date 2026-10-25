---
name: Gas City search for a rejected graduation's rebuild
description: The search the arch check asks for before the pack changes how a rejected graduation is rebuilt. What Gas City, the packs it publishes and bd ship for running a worker on a convoy as one work item, for keeping that run's pours apart, and for landing its work back on the convoy, read at named upstream commits, and why the pack pours the rebuild onto an ordinary child bead instead of wrapping gc sling. Read it when checking whether the pack still needs the rebuild child, or the merge-push rule that anchors the bead a rework child names.
---

# Gas City search for a rejected graduation's rebuild

A graduation's anchor is a convoy. `convoy-graduate.sh` gives the owned convoy
its integration branch and hands it to the refinery as the work bead of the
graduation PR. When the refinery rejects it, for a conflict with its target or a
failure the branch caused, a polecat rebuilds the branch. This change pours that
rebuild onto an ordinary child bead with plain `gc sling`, and lets the
refinery's landing of the child anchor the convoy. The arch check asks what Gas
City already ships for each part of that
([review-arch.md](../../docs/review-arch.md#the-checks), check 1). Nothing Gas
City ships runs a worker on a convoy as one work item, or refuses a second run
poured onto a convoy target. Everything it ships for one work item applies to an
ordinary bead, so the rebuild runs on one.

## The surface and the need

- `rejection-repool.sh` files, or adopts, the rebuild child of a rejected work
  bead that is a convoy. The child is an ordinary task that carries
  `task_kind=rework`, names the convoy as its `anchor_bead`, carries the
  convoy's branch, target and the `rejection_reason`, and blocks the convoy.
  The script pours `mol-polecat-work` onto the child with `gc sling`, and arms a
  deferred dispatch on the child when the sling fails.
- `mol-refinery-patrol`'s merge-push gives the gating transition to the bead a
  rework child names as its `anchor_bead` when no bead on the branch carries a
  `merge_result` yet, and then closes the child landed-on-branch.
  `mol-polecat-work`'s submit step reads the anchor the same way for the PR's
  summary and title.

The need has three parts. The run works on one bead whose branch is the
convoy's. Every pour of that run, whether the repool's, a replayed arm's or a
person's, is serialized with the others and refused while one is live. The
convoy stays the anchor of the graduation PR, and that PR's merge closes it.

## Where the search looked

Each was read on 2026-10-24:

- Gas City at main `6e35bd5ea549`: its documentation, its engineering docs, the
  `core` pack it bundles, and its source. The commits since `58d13ccee7a3`,
  which the arch review read, change only its CI and its tests.
- Every pack Gas City publishes, at `c1848011ae23`. Each was searched for
  `rejection_reason`, `Conflicts with`, `integration_branch`, `reopen-source`
  and a `gc sling` of a convoy, and each hit was read.
- bd at `0c562176ccee`.

`gc sling`'s `--dry-run` preview was read again on 2026-10-25 at main
`149ae8df7c95`, where it is unchanged. Its answers for a bead with a live run
and for one whose run had ended were checked by running it.

## What Gas City ships

**A run poured onto a convoy works on its members.** The engineering design
*Convoy-First Formulas And Drain V0* sets the graph.v2 invocation contract. A
target that is already a convoy is passed through whole, and a normal bead gets
a visible one-item convoy that contains it. Package `graphv2` implements it.
`NormalizeInputConvoy` returns a convoy target as the run's input convoy, and
for every other target it calls `CreateSingleItemInputConvoy`, which mints the
convoy marked `gc.synthetic` and closes it again when its track fails. The
[Formula Spec v2](https://docs.gascity.com/reference/specs/formula-spec-v2)
page names that convoy `{{convoy_id}}`. A formula that works one bead takes the
one bead it tracks, and the Gas Town pack's `mol-polecat-work` derives its work
bead that way, as this pack's does. The one fan-out the spec offers is the
`drain` step, which scatters the input convoy into one-member unit convoys and
runs an item formula on each
([Understanding Formulas](https://docs.gascity.com/guides/understanding-formulas)).
No sling flag, formula option or step runs a worker on a convoy as one work
item.

**A convoy routed to a pool is never offered.** Package `beads` leaves the
`convoy` type out of `Ready()`: `IsReadyExcludedType` marks it a container that
groups child beads and is never actionable work. `IsContainerType` marks the
same type as one whose children a dispatch expands. Only the Gas Town pack
handles a rejection. Its `mol-refinery-patrol` sends a conflicted bead back by
routing it to the polecat pool (`gc.routed_to`), and its integration auto-land
hands the refinery the convoy bead itself, so a convoy that pack rejects is
routed and never claimed. The build pack's mayor skill slings a convoy with
`--on` only for a convoy-first formula such as `implement`, which drains the
convoy's members.

**Launch ownership is keyed by the bead gc sling is handed.** In package
`sling`, `attachFormulaToBead` holds `withGraphV2SourceWorkflowLock`, keyed by
that bead, across `checkLegacySourceWorkflowConflict`, the pour and
`restampWorkBeadRouting`, which stamps the bead's routing. The duplicate check,
`liveConvoyTrackedWorkflowRoots`, finds a live root of the same formula through
a synthetic convoy that tracks the bead. Its comment says a convoy target was
never covered, because nothing tracks a convoy target. So an ordinary bead gets
the one-bead input convoy, the lock, the refusal of a second live run and the
stamp. A convoy target gets the lock, keyed by the convoy, and no refusal.

**The duplicate check can be asked without a pour.** At main `6e35bd5ea549`
and at `149ae8df7c95` alike, `gc sling --dry-run` previews a pour and makes
none. For `--on <formula>` its pre-check, `dryRunReportBlockingMolecule` in the
`gc` command, reads the bead's attached molecules and workflows
(`FindBlockingMolecule`). It then runs the launch's duplicate check in
`dryRunReportBlockingWorkflow`, through `LiveConvoyTrackedWorkflowRoots`, the
exported form of `liveConvoyTrackedWorkflowRoots`. A live workflow exits 1
with `gc sling: bead <id> already has attached workflow <root>` on stderr. No
live workflow or attachment exits 0 with the passing line `Pre-check: <id> has
no existing molecule/wisp children or live formulas-v2 workflow for <formula>
✓`. A lookup that fails prints `gc sling: pre-check inconclusive: <error>` and
exits 0 with no passing line. An open molecule or wisp exits 1 naming a
molecule, and any other exit 1 is a usage, route or store failure. Under
`--force` the preview skips the workflow half and prints a shorter passing
line.

**The landing is the pack's.** Gas City ships no landing for this pack's
anchors. The anchor lifecycle, its rework children and the refinery's one anchor
per PR are the pack's own formulas and scripts. bd records the two edges the
child needs: its `blocks` edge onto the convoy, and the `related` edge that joins
a child to its anchor.

## What the change does with it

The rebuild of a rejected convoy runs on an ordinary bead, so every launch
mechanic is Gas City's. A convoy has one rebuild child: a later repool adopts
it, every retry slings that same bead, and `gc sling` takes its lock and refuses
a second live run under the child's id. Whether a run is live on an adopted
child is `gc sling`'s answer too. The repool runs the preview of the pour it is
about to make, before it releases the child, because the release clears the
assignee, route and stamp a live run still uses. It reads only the two answers
that prove something: a live workflow named on the child, which it reports and
leaves alone, and the passing pre-check for the child and `mol-polecat-work`,
which lets it release and pour the child. Any other answer, an inconclusive
lookup among them, stops the repool at a visit that carries `gc`'s exit and
stderr. The arm a failed sling leaves is the deferred dispatch every other bead
uses, and its replay is a plain `gc sling` of the child. The pack adds no lock,
no duplicate check and no input convoy of its own.

What the pack adds is glue and formula text. The filing of the child runs `bd`
and `gc sling` the way `pre-open-rebase.sh` and `rework-child.sh` file and pour
theirs. The landing rule in merge-push is a formula's. Neither adds a pack noun,
since a rebuild child is an ordinary `task_kind=rework` child of its anchor.

A hand `gc sling <pool> <convoy> --on mol-polecat-work` still pours a run over
the convoy's members, because that is Gas City's contract for a convoy target,
and the run refuses it at load-context. The visits `rejection-repool.sh` files
name the command that finishes a repool: a re-run of the script, or a
`gc sling` of the rebuild child.
