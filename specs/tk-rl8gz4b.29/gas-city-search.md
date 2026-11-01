---
name: Gas City search for holding new work and seating a mayor
description: Use when a review or a later change asks what Gas City ships for holding work, listing a queue, lifting a hold, placing a bead or seating a mayor, or when one of the triggers at the end may have fired.
---

# Gas City search for holding new work and seating a mayor

The placement marker's own design records no search of Gas City. This is the
search for its replacement ([the design](native-hold-and-mayor.md)), one section
per need, each ending in what the design does about it.

Read on 2026-11-01 at Gas City main `cb0cc685d4e4`, Gas City's published packs at
main `0b0d96250f66`, the `gastown` pack Gas City pins for a new city at
`cb6a612882b8` (`PublicGastownPackVersion` in package config), and bd main
`6ebaacba8f5f`. Pages are cited by title, and code by package and symbol. The city
runs a fork of Gas City, which is not evidence of what Gas City ships. So the
symbols the design leans on were also found in the installed build at `e03752646`
and `gc beads list` was run against it, to know the design works here.

## Holding a bead

**Gas City ships this, and the design composes it.**

- *Hold and Blocked Label Conventions* (engdoc) defines `hold:mayor` as "the required
  next actor is the mayor" and sets it with `bd set-state <id> hold=mayor --reason`.
  It says the check is "for the *presence of a label value*, not a branch on a role".
- `DispatchHoldLabels` and `HasDispatchHold` in package beadmeta are the definition.
  The readers: `isHeldHookCandidate` in the hook, `demandServableForTemplates` for
  pool demand, the default work query (`gc ready`'s help text), wake readiness, and
  `isDetachedHandoffOrphanCandidate` in the route-restore sweep.
- The same page states the contract the marker misses: "A pack that parks with a
  label of its own should also set a bd status (`blocked` or `deferred`) or a
  canonical hold, or the controller will treat the bead as detached and restore its
  route."
- No published pack writes or reads a hold, at either packs commit. `set-state`
  appears only in one packs test. So this city is the first pack user of the label,
  and there is no pack precedent to follow.
- bd's `runSetState` (package main of bd) files a closed `event` bead as a child of
  the subject and swaps the label in one update. It files nothing when the value is
  already set, so a `set-state` after a create carrying the label records nothing.

## Listing the queue across stores

**Gas City ships this. It retires `gc-helm.sh unplaced`.**

- [`gc beads list`](https://docs.gascity.com/reference/cli#gc-beads-list) lists "beads
  across all rigs" with `--label` and `--format=json`. Run on the installed build, it
  answered in about 3 seconds and matched a per-store read for labels in this rig's
  store and in a suspended rig's store.
- What it lacks beside the verb it replaces: its rows carry no priority, and
  `renderBeadsListFromAPI` prints the API's rows without its `partial_errors`, so a
  store that fails drops out with no notice. The design accepts both and says why.
- `--format=json` has two shapes. `writeBeadsJSONWithCache` wraps the API's rows as
  `{"beads": [...], "_cache_age_s": n}`, and `doBeadsListFallback`'s `writeBeadsJSON`
  prints a bare array, so a reader takes both. The installed build answered with the
  array here.
- [`gc ready`](https://docs.gascity.com/reference/cli#gc-ready) federates too, but it
  answers ready work only and has no label selector, and a held bead with a blocker
  must still be listed. `gc bd list` reads one store.
- `needs-mayor` and `needs-mayor-decision` are routing labels in Gas City's own tracker,
  which the conventions page says may sit beside the hold. One queue needs no second
  label.

## The route on a held bead

**Gas City's texts disagree. The design follows the documented contract.**

- *Hold and Blocked Label Conventions*: "A pack that parks finished work on a hold
  usually clears its `gc.routed_to` at the same time, because the next actor is not
  the pool that worked it."
- *Session Model Unification* (engdoc): `gc.routed_to` "stores the resolved qualified
  config identity" and is never "a session identity" or an alias.
- `holdLabelRoutedToCheck` in package main warns on any `hold:<value>` whose route is
  not `<value>`, and its `--fix` writes that value. `v2RoutedToNamespaceCheck` rewrites
  a short route for a bound agent to the qualified form, so under a binding the two
  would disagree with each other.
- Issue 6069 in Gas City's tracker (open, P1) reports the first check as a bug, on the
  grounds that hold and route are orthogonal, and an open PR, 6071, retires its rewrite.
- The installed build carries the check. So the design takes one known warning, tells
  the deacon's step so, and lets `place` clear any route a `--fix` wrote. It clears it
  before it dispatches, since the pack's arm refuses a routed bead and a plain route's
  sling writes its own. It ends when that fix reaches the fork.

## Lifting a hold

**bd ships the write. Nothing names it as the lift.**

- `bd update --remove-label` and `bd label remove` remove a label.
- `set-state` refuses an empty value, and no state command removes a dimension
  (`setStateCmd` and `runSetState`), so the sanctioned command cannot lift.
- The conventions page names no lift. Gas City's release-gate records say "lifted
  `hold:mayor`" with no command, and no pack lifts one.
- The lift uses `--remove-label` in one `bd update` with its note.

## Placing as one act

**Nothing covers it. The design adds a verb, as glue.**

- [`gc sling`](https://docs.gascity.com/reference/cli#gc-sling): neither package sling
  nor `cmd_sling.go` reads a hold, so a sling pours and leaves the label on.
- Nothing lifts a hold and pours in one write, and a sling is its own command, so one
  write is not available. Gas Town's mayor prompt and the `gc.mayor` skill in the
  `gascity` pack sling beads and read no hold.
- `gc-helm.sh place` runs parent, settle, sling or arm, and lift in a set order. The
  arch check's rule covers it: "Glue that runs a series of native calls as one call adds
  no noun". It adds no state, and each step is a native write. Its worth over three
  commands in a prompt is the order and the re-run, which a queue worked in batches needs.
- `hold-lib.sh` and `queue-priority.sh` carry pack semantics Gas City lacks. Priority
  following has its own warrant, and neither gains anything here.

## Seating a mayor

**Gas City ships the role as configuration. The design configures it.**

- `DefaultCity` in package config writes one agent, `mayor`, as an always-mode named
  session, with the embedded `prompts/mayor.md`. The
  [FAQ](https://docs.gascity.com/getting-started/faq) says the platform "hardcodes zero
  roles". [Coming from Gas Town](https://docs.gascity.com/getting-started/coming-from-gastown)
  calls it the human's point of contact, reached with `gc session attach mayor`.
- Gas Town's `mayor` agent has `scope = "city"`, `wake_mode = "fresh"`,
  `idle_timeout = "1h"` and `max_active_sessions = 1`, with a `mode = "always"` named
  session. Its prompt says to dispatch liberally and fix when fast, and lists escalation
  handling and rig lifecycle among its responsibilities.
- An import does not fit. The city imports `bd`, `core` and `gc-toolkit`, and
  [Configure the Gastown Pack](https://docs.gascity.com/guides/gastown-config-recipes)
  shows an import bringing in the pack's city-scoped agents as a set. Its prompt also
  carries the jobs this seat declines. So the pack ships its own agent, modeled on Gas
  Town's, and the design lists each difference.
- `oversight-rig` opens with the failure this design guards against: "In a single-mayor
  city, the mayor ends up in the minutiae of every project's work scoping". Its answer is
  a rig-scoped role, which is the idea the operator tabled.
- [`NamedSession`](https://docs.gascity.com/reference/config#namedsession)'s `mode`:
  `on_demand` reserves the identity and materializes it "when work or an explicit
  reference requires it". *Session Model Unification* lists direct session targeting
  among the causes. `wake_mode = "fresh"` starts a new provider session on each wake.
- A detach does not stop such a session. `computeAwakeSetKeyed` in package main keeps a
  running on-demand session awake under the reason `on-demand:running`.
- What ends it decides whether the next attach is fresh. `AcknowledgeDrainPatch` and
  `CompleteDrainPatch` clear `session_key` on a fresh session, so `gc runtime drain-ack`
  and an idle drain each leave nothing to resume. The idle drain comes from
  [`sleep_after_idle`](https://docs.gascity.com/reference/config#agent):
  `reconcileDetachedAtInfo` stamps `detached_at` under a sleep policy, and past the limit
  the awake computation decides `idle-sleep`, which the reconciler drains. `idle_timeout`
  takes another path: `buildIdleTracker` registers it for a named session that is not
  `always`, and its kill writes `SleepPatch`, which keeps the key. `SessionHandle.Attach`
  starts a stopped session from `startCommand` with no look at `wake_mode`, and only the
  controller's `PreWakePatch` clears a key at a wake. So the seat sets `sleep_after_idle`
  in place of Gas Town's `idle_timeout`, or an attach after an idle kill would resume.

## Paths that would reach the seat

- `ResolveNamedSessionSpecForConfigTarget` and `namedSessionBareName` in package session
  let a bare `mayor` or `mayor/` resolve to a bound session, so Gas Town's text and the
  pack's stale default would both reach this seat.
- `defaultWarmupMailTo` in package warmup is `mayor`, and `runStartWarmup` passes no
  override.
- Core's `orphan-sweep` and `spawn-storm-detect` read `GC_ESCALATION_TARGET`, default
  `human`, and name a coordinator only as what a city can choose. `DoltMaintenance`'s
  `alert_to` is empty unless set.
- Gas Town's witness, deacon, refinery and polecat all address `mayor/`. Its deacon uses
  [`gc mail send --dedup`](https://docs.gascity.com/reference/cli#gc-mail-send), so mail
  does dedup now, and the wiring suites' comment that it does not is stale.
- A nudge wakes the seat. `resolveNudgeTargetInStore` materializes a named session, and
  `shouldQueueManagedNudgeWake` queues the text and asks for a wake when it is not
  running. `gc mail send --notify` takes the same path through `newMailNudgeFunc`. Mail
  without `--notify` requests no turn, as that command's help says.

## Refusing a sling

**Gas City ships the seam, and it covers a plain route only.**
[`sling_query`](https://docs.gascity.com/reference/config#agent) is "the command template to
route a bead to this session config".

- `cliBeadRouter.Route` in package main runs a custom one and returns its error. Package
  sling's `finalizeInStore` is what calls it for one bead.
- `doStartGraphWorkflow`'s comment says "Graph launches never pass through finalize()", so a
  graph.v2 formula never reaches the query, by `--on` or by a default formula.
- `ApplyAgentDefaults` gives `[agent_defaults] default_sling_formula` to any agent whose own
  field is nil, and this city sets `mol-polecat-work` there. `EffectiveDefaultSlingFormula`
  returns an agent's explicit empty string, so `default_sling_formula = ""` sends a plain
  `gc sling` to the query.
- Nothing refuses `gc sling --on` with a graph.v2 formula, so the check's first arm covers it.

## Noticing a run that ended with its bead open

**Nothing covers it.**

- [`gc convoy stranded`](https://docs.gascity.com/reference/cli#gc-convoy-stranded) lists
  open tracked issues with no assignee. A graph.v2 run does not claim the bead it works, so
  this lists beads under live runs too. Run while writing this record, it listed this
  design's own bead.
- `sweepDetachedHandoffOrphans` wants a work branch and a session back-reference. Core's
  `orphan-sweep` reads in-progress beads assigned to dead agents.
- Gas Town's `check-polecat-health` judges in-progress beads under live polecats.
- The design adds nothing now, and hands the need to tk-1tfzr71.19.

## The check that the mayor receives only its queue

**Gas City ships the seam, and no check for this.**

- *Encode known mistakes as doctor checks*, in
  [Set Up a Multi-Agent Engineering Environment](https://docs.gascity.com/guides/multi-agent-engineering-environment#encode-known-mistakes-as-doctor-checks),
  is the pattern, and a pack's `doctor/<name>/` is the seam.
- `hold-label-conventions` reads retired labels, and `hold-label-routed-to` is above.
  Neither reads who a seat receives from.
- Mail and assignment have no refusal: `gc mail send` delivers to any resolved identity,
  and `bd update --assignee` writes any value. So this has to be observed after the fact.
  A delivered nudge leaves no record to observe.
- `gc mail send` gives a caller with no session identity the sender `human`, as an exec order
  has, so the check cannot read that sender as the operator.
- A doctor check reports only once the pack has landed. The design takes that, since the
  new paths it looks for are mostly hand-made and live.

## A reader's test for a hold

`has_dispatch_hold` in `dispatch-path.sh` copies `HasDispatchHold`'s rule into jq. Gas City
exposes the rule as flags on a query (`--exclude-label`) and in Go, and these readers hold
JSON rows they have already read: `bd ready`, `bd blocked` and `bd list` all print `labels`,
which was checked on live rows.

## Triggers

The answer changes if one of these ships. None had fired at the commits above.

- `gc sling` lifts or refuses a hold: `place` shrinks or goes.
- Issue 6069 lands: the known warning and the deacon's sentence go.
- `gc beads list` prints priority and partial errors: the two gaps above close.
- `gc mail` or a config field can scope who may mail a session: one arm of the check goes.
- A graph.v2 pour runs `sling_query`, or an agent can refuse a pour: `--on` is refused at the
  caller, and the seat's empty default formula may go.
- `gc session attach` honors `wake_mode`: the seat can take Gas Town's `idle_timeout`.
- `gc convoy stranded` tells a live run from an ended one: tk-1tfzr71.19's need is covered.
