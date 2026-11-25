---
name: Gas City search for the placement queue's move to hold:po (tk-1tfzr71.233)
description: The Gas City and bd primitives searched for each need of moving the placement queue from hold:mayor to hold:po, what each covers, the reason upstream gives for holding only two values and the census that tests it here, and why gctk bead move-placement-hold composes bd's update, not its set-state, over each store. Read it when reviewing the label, the pack's hold rule or the verb, as AGENTS.md asks of a change that adds surface or accommodates Gas City.
---

# Gas City search for the placement queue's move to hold:po

This change moves the label that holds new work for its rig's po from
`hold:mayor` to `hold:po`, reads any `hold:<value>` as a hold in the pack's hold
rule, and adds one gctk verb, `gctk bead move-placement-hold`. It adds no order,
no metadata key and no bead kind. Each need names the primitive searched at
`gastownhall/gascity` main 0998eac14bfe (2026-11-25) and at bd v1.3.4, the
version the city runs, whose source is the module `github.com/steveyegge/beads`
v1.3.4. The city's `gc` is built from the keeper's fork, `zookanalytics/gascity`
main 13cdf670ca, which carries gc-uyshxy. The fork is named below only as the
runtime this change accommodates, never as a primitive Gas City ships.

## Hold new work for its rig's po under a value no agent answers to

**Covered upstream for two values only.** `beadmeta.DispatchHoldLabels` is
`hold:mayor` and `hold:external` (`internal/beadmeta/hold_labels.go`), and
`HasDispatchHold` compares a bead's labels against that list, so upstream serves
a bead held on any other value as ordinary work. The values are data, "not role
names", and the conventions page gives the reason for two:
`engdocs/contributors/hold-label-conventions.md` says "Only two values are
canonical. Don't introduce a third without a new architecture decision", and
that `hold:mayor` means "the required next actor is the mayor". The page sets
the taxonomy for Gas City's own bd tracker, where the mayor is the seat that
places work.

**The reason does not hold here.** In this city the po places new work, and the
mayor is a separate seat for city-wide triage (PR #1606, tk-1tfzr71.207), so
`hold:mayor` would name the wrong next actor. Upstream's
`hold-label-routed-to` doctor check acts on the value as a route
(`cmd/gc/doctor_hold_label_routed_to.go`: `holdLabelValue` takes any value but
`external` and `cleared`, and its fix writes that value, or its one
binding-qualified alias, into `gc.routed_to`). With a seat named mayor, that
fix would route every held bead to it. Issue 6069 reports the fix as a bug and
is open. A value of the pack's own, `hold:po`, holds nothing upstream, because
upstream reads only the two.

**Measured here.** A census of every live bead's labels in each store the rig
list names, `gc bd --db <store> list --json --limit 0` with ephemeral, gate,
infra and template beads included, filtered to labels that begin `hold:` in any
case, read at 2026-11-25T02:11:48Z: `hold:mayor` is the only hold value on a
live bead, 202 beads in all, across six rig stores (54, 54, 47, 19, 17 and 11)
and none in the HQ's. Closed records carry `hold:mayor` too: 287 of them, 282
in this rig's store. The verb's dry run at
02:11:40Z read all seven stores and found each of the 202 a bead it moves:
none assigned, none routed, none carrying a second hold label.

**The fix at the source.** gc-uyshxy, merged to the fork as d62873fce6
(fork PR #259), makes `beadmeta.ActiveHoldValue` hold a bead on any
`hold:<value>` whose trimmed value is not `cleared`, and removes the
`hold-label-routed-to` check. tk-1tfzr71.234 verified it deployed: the city's
`gc` binaries and its supervisor run fork main 13cdf670ca, and an isolated city
driven by that binary withheld `hold:po`, `hold:release-train` and `Hold:PO`
from `gc hook` and served a bead once `bd set-state <id> hold=cleared` lifted
it. The operator authorized the fork change and this migration in conversation
tk-5e70s01 on 2026-11-23, and this work asks nothing upstream. The fork's
downstream gaps are filed: gc-dvnast (the dashboard names an actor only for the
two old values) and gc-gf1hzn (doctor's hint names `hold=mayor|external`).

## The pack's hold rule

**Covered by the runtime, in Go and in jq.** The fork's
`beadmeta.ActiveHoldValue` is the rule, and `activeHoldLabelJQ` in
`internal/config/workquery.go` renders it in jq for the generated work
queries. Neither is reachable from pack code: gctk's runtime adapter
(`services/gctk/internal/gascity/hold.go`) and `dispatch-path.sh` mirror it, as
they mirrored the two-value list before. A `--exclude-label` flag matches one
label exactly and cannot name every value, so the fork's
`PoolDemandServeRulesForQuery` drops held rows with jq, and the deferred-dispatch
start's ready read keeps only the human label in its flags and holds a held bead
by the adapter's rule before it reads readiness.

## Move a held bead's label with no moment unheld, and keep every other hold

**Covered: bd's update, adding one label and removing another.**
`bd update <id> --add-label hold:po --remove-label hold:mayor` carries both in
one `LabelPatch` (`cmd/bd/update.go`). `issueops.ExecuteUpdate` reads the bead
in the update's own transaction (`internal/storage/issueops/execution.go`), and
`issueops.ApplyLabelPatch` (`internal/storage/issueops/aggregate.go`) writes the
labels the bead carries there, plus `hold:po` and less `hold:mayor`. So the bead
is held before and after the commit, each other label it carries as the write
lands stays on, and a bead already on `hold:po` alone takes no change. bd
records each label it adds or removes as a `label_added` or `label_removed`
event with its actor (`AddLabelInTx` and `RemoveLabelInTx` in
`internal/storage/issueops/labels.go`), which `bd history <id> --events` reads.
The verb's write is this command.

**Covered for setting a hold, not for this move: bd's set-state.**
`bd set-state <id> hold=po --reason <text>` (`cmd/bd/state.go`, `runSetState`)
adds `hold:po` and removes the bead's old hold label in one `LabelPatch`, and
files a closed `event` bead that records the change and its reason. The
conventions page names it the sanctioned way to set a hold, "never with a plain
`bd label add`", because it treats `hold:` as one dimension with one value:
set-state "removes any existing label in the `hold:` dimension, adds the new
one, and files an audit event bead". It chooses the label it removes from its
own read of the bead, before its update: `findStateLabel` takes the first label
that begins with the exact text `hold:`, and bd reads a bead's labels
`ORDER BY label` (`internal/storage/issueops/labels.go`). The move sets no hold.
It changes the spelling of the placement hold on a bead that already carries
it, and must leave any other hold on, which this city's `gc` reads as a hold of
its own. A hold another writer adds after the move reads a bead and before
set-state reads it, such as `hold:external`, sorts before `hold:mayor`, so
set-state would swap that hold out and leave `hold:mayor`.

**Measured here.** The move's store acceptance case
(`services/gctk/place/move_acceptance_test.go`) runs it against bd 1.3.4 on a
scratch store, with a writer that adds `hold:external` to one bead just before
the move's write. With the move writing through set-state, on 2026-11-25, that
bead ended on `hold:mayor` and `hold:po`, its history recorded `hold:external`
removed, and the move reported the bead moved. Through the update it ends on
`hold:external` and `hold:po`. No live bead carries a second hold label (the
census above), so the case needs a writer to act during the move. Intake and
the po's Hold lever set the placement hold with set-state, as the page asks, and
a hold added before such a write lands would be swapped out the same way.
tk-uki5019 takes that up once this change lands.

**What the write leaves to a person.** The verb writes a bead only when its
`hold:` labels are `hold:mayor`, or `hold:mayor` beside `hold:po`. Another hold
or `hold:cleared` on the bead is a label another writer put there, so whether
the bead still waits for placement is a person's call. bd removes a label by its
exact text, so the update would leave `Hold:Mayor` beside `hold:po`. The verb
names each such bead with the
`gc bd update --add-label hold:po --remove-label ...` write a person makes,
which leaves the bead held too.

## Read every store, and name the one that does not answer

**Not covered.** `gc beads list --label hold:mayor` reads the city's stores in
one call (`cmd/gc/cmd_beads.go`, `routeBeadsList`), but its label filter is
exact (`internal/beads/query.go`, `beadHasLabel`), and when a store fails it
prints no list at all (`beadsListPartialErrorDetail`), so it cannot move the
stores that answer and name the one that did not. Nothing in Gas City or bd
writes across a city's stores. `gc bd --db <store> list` reads one store, and
the verb runs it for the HQ and for each rig `gc rig list --json` names,
suspended or not.

## What the verb adds, and when it goes

`gctk bead move-placement-hold` reads each store on its own, swaps `hold:mayor`
for `hold:po` in one update on each bead whose `hold:` labels are `hold:mayor`,
or `hold:mayor` beside `hold:po`, reads each bead again just before its write so
a bead a placement lifted meanwhile takes no `hold:po`, and exits 0 only when
every store read and no live bead is left on `hold:mayor`. It
is debt: it exists for the `hold:mayor` labels written before the pack moved,
and it goes with the pack's reading of `hold:mayor` as the placement hold, once
the cutover has run and no writer is left that writes it.
