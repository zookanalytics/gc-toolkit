---
name: Gas City search for the work formula's rewrite
description: The record of what tk-1tfzr71.12 looked for in Gas City and bd before it added claim-close.sh, decline.sh, the work step scripts and await-ruling.sh --blocked-by. Read it when judging whether that surface should be a native call instead.
---

# Gas City search for the work formula's rewrite

Read on 2026-11-01 at `gastownhall/gascity` main ce6b62131,
`gastownhall/gascity-packs` main 0b0d96250, and bd 1.3.2. The second-run check and
everything about `work-holder.sh` were read again that day at `gastownhall/gascity`
main 879a71fa0. The city's deployed `gc` is the fork's 1.4.3 at e03752646. A fork is
not evidence for what upstream ships, so it is named only where it is what runs.

## Composed

- **`gc hook current --id-only`** (`cmd/gc/cmd_hook_current.go`,
  `docs/reference/cli.md#gc-hook-current`) names the bead a step closes. Its help
  names the environment problem `step-close.sh` was written against. It reads the
  stamp `gc hook --claim` writes on the session's own bead
  (`stampHookSessionCurrentClaim`, `cmd/gc/cmd_hook_claim.go`), on every result
  that hands a bead over. Verified live in this run: the stamp moved with each of
  four claims, and `status=in_progress` on each.
- **`gc sling`'s refusal of a second live run** replaces `work-tree-holder.sh`'s
  hold on a run in flight. `checkLegacySourceWorkflowConflict`
  (`internal/sling/sling_core.go`) and `liveConvoyTrackedWorkflowRoots`
  (`internal/sling/sling_attachment.go`) refuse a second live root of one formula on
  one bead, under the lock `withGraphV2SourceWorkflowLock` takes. That lookup is
  scoped to one formula because distinct formulas on one bead are legitimate, and
  `--force` skips it. Verified live: `gc sling --dry-run` on a bead with a live run
  answered that the bead already has an attached workflow.
- **The record `gc sling` judges**, a root's `gc.input_convoy_id` and its convoy's
  `tracks` edge, read through `run-lib.sh`, which is `work-gate.sh`'s whole check for
  what gets past that refusal. A forced relaunch does: `--force` replaces only a
  root with the same `graphv2.RootKey`, which names the input convoy, and a bare bead
  gets a new convoy at each launch (`CreateSingleItemInputConvoy`,
  `internal/graphv2/invocation.go`), so the new root stands beside the old one. A
  claimant with no poured workflow never calls sling. Since each launch of a bare
  bead has its own convoy, a run knows itself by its `--convoy`: of the 5,951 roots
  in this rig's store on 2026-11-01, no two name one convoy. The older root builds,
  which both dispatches read alike from the same rows, so the check writes nothing.
- **A claim on the work bead** decides a claimant with no poured workflow, as the
  gate's owner check always has. **`git checkout`'s refusal of a branch another
  worktree holds** decides a sibling on the branch, at `work-setup.sh`.
- **`bd update --unset-metadata`, `gc bd dep add`, `gc sling`,
  `deferred-dispatch.sh`** carry the waits and writes. The scripts add no store of
  their own.
- **`[daemon]`'s `auto_reclaim_stale_claims`**
  (`docs/reference/config.md`, an agent field, off by default) is the one reader of
  a claim's lease, by `bd reclaim --id` from `gc hook --claim`. No agent in this
  pack or city sets it, and no order runs `bd reclaim`. So the formulas stop
  wrapping long commands in `lease-heartbeat.sh`, as the bead's Retires line allows.

## Not covered, and why the surface exists

- **`claim-close.sh`.** Searched: `gc bd close`, `gc bd update --if-status
  --if-assignee`, `gc hook`. Core's `mol-scoped-work` closes with `gc bd update
  "$(gc hook current --id-only)" --status=closed`, which does not check that the
  claim is the step being finished. A close re-run after the claim moved on would
  close the next step unrun, and a `--if-status` guard does not stop that, because
  the next step is in progress too. bd has no guard on metadata. Upstream's own
  `mol-do-work` and `mol-polecat-commit` therefore write the `gc.step_ref` check
  into their step text, as jq. Rule 2 forbids a procedure in step text here, so
  the same check is one script of a page. It resolves nothing: `gc hook current`
  names the bead.
- **`decline.sh`.** Searched: `gc workflow`, `gc convoy`, `gc hook --drain-ack`, the
  supervisor's `POST /runs/{id}/cancel`. Each is one part of a decline. None records
  the gate and the wait first, and the order is the point, because a cancelled run
  with no record behind it leaves work nothing re-offers. tk-qitjxcm carries the rest
  of the copies onto this script.
- **`work-gate.sh`.** Searched: core's `load-context`. Upstream's has no gate. The
  fork's parks the step and mails, where the operator's ruling on visit tk-r69f9cv
  has every decline cancel its run. Neither refuses a finished, parked or blocked
  bead, and `gc sling --on` pours without reading a blocks edge, which is why the
  guard exists: tk-1tfzr71.12's notes record reworks this gate refused only because
  their edge had landed.
- **`work-setup.sh`, `work-enter.sh`, `work-submit.sh`, `rig-checks.sh`.** These are
  the bodies of overrides the warrant names, moved out of step text under rule 2,
  with nothing added but the sibling yield, the outage stop, and
  `work-submit.sh`'s refusal of a `--bead` caller that holds neither that bead nor
  this step. `gc worktree` covers part of `work-setup.sh`, and tk-1tfzr71.10 moves
  that part.
- **`rig-checks.sh`'s command arguments.** Searched: `formula.Substitute`
  (`internal/formula/parser.go`), which writes a var into step text as it stands
  and has no shell-quoting form, and `stampFormulaVars`
  (`internal/molecule/molecule.go`), which records each non-empty var on the root
  as `gc.var.<name>`. A script could read a poured run's commands from those
  stamps, but a claimant with no poured workflow has no root, and a step's fallback
  to the repo's own quality gate runs a command no pour stamped, so the commands
  need an input either way, and a second source is a second way to differ. `gctk
  rig --command` takes one string, so each is one argument: a quoted heredoc inside
  it hands over a shell string of any shape, as the old blocks' heredocs did, and
  the call stays one call under rule 2.
- **`await-ruling.sh --blocked-by`.** Searched: `gc sling --after`, order triggers on
  `bead.closed`. Gas City has no sling on unblock (`docs/warrants.md`, deferred
  dispatch), so a bead that waits on another needs the edge and the arm this script
  already makes for a gate.

## Rejected

- **Core's `work-holder.sh --claim` and a `work_holder` key.** Only the fork's core
  pack carries that script: `internal/bootstrap/packs/core/assets/scripts` has none
  at main 879a71fa0, so on Gas City as shipped every run would fall through to a
  person. foundation.md rules out answering a gap with a fork, and there is no gap:
  the key would be a second record of what the run's root records already, and one
  that runs poured before it never wrote. `gc beads metadata-cas`
  (`docs/reference/cli.md`) is upstream's, but it compares a key, and the older-root
  rule leaves it nothing to compare.
- **`bd update --claim` on the work bead.** Upstream's `mol-polecat-base` leaves the
  bead a run works unclaimed, and this formula's steps run across sessions, so one
  session's claim would not name the run.
- **`gc convoy delete-source`'s preview** as the reader of a bead's live runs. It
  reads `sourceworkflow.ListLiveRoots`, which lists by `gc.source_bead_id`, and a
  convoy-first `--on` launch never stamps that, as the comment on
  `checkLegacySourceWorkflowConflict` records.
- **A continuation group on inherited steps.** `mergeSteps` replaces a child step
  whole and the formula has no step default, so an inherited step cannot gain the
  markers without a core change. Gas Town runs these steps unmarked on `wake_mode =
  "fresh"`, so `implement` takes that shape here. A session that claims it in the same
  turn carries on, since the reconciler's fresh cycle skips a session whose current
  claim is the assigned bead (`cmd/gc/session_reconciler.go`, read at the fork, which
  is what runs). A session cycled instead hands `implement` to a fresh one, which
  loses only the mechanical steps' conversation. Running `mol-polecat-report` on this
  pool has shown both.
- **`extends = ["mol-scoped-work"]`.** It declares the markers, but its `submit` is a
  stub and its scope aborts on a step's failure, so every pack step would still be an
  override, under a different step name that nine scripts read.
