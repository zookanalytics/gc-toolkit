---
name: Gas City search for the work formula's rewrite
description: The record of what tk-1tfzr71.12 looked for in Gas City and bd before it added claim-close.sh, decline.sh, the work step scripts and await-ruling.sh --blocked-by. Read it when judging whether that surface should be a native call instead.
---

# Gas City search for the work formula's rewrite

Read on 2026-11-01 at `gastownhall/gascity` main ce6b62131,
`gastownhall/gascity-packs` main 0b0d96250, and bd 1.3.2. The city's deployed `gc`
is the fork's 1.4.3 at e03752646, whose embedded core pack is what `gc core
scripts-dir` names here. A fork is not evidence for what upstream ships, so it is
named only where it is what runs.

## Composed

- **`gc hook current --id-only`** (`cmd/gc/cmd_hook_current.go`,
  `docs/reference/cli.md#gc-hook-current`) names the bead a step closes. Its help
  names the environment problem `step-close.sh` was written against. It reads the
  stamp `gc hook --claim` writes on the session's own bead
  (`stampHookSessionCurrentClaim`, `cmd/gc/cmd_hook_claim.go`), on every result
  that hands a bead over. Verified live in this run: the stamp moved with each of
  four claims, and `status=in_progress` on each.
- **Core's `work-holder.sh --claim`**, reached by `gc core scripts-dir`, replaces
  `work-tree-holder.sh` and takes the work with one compare-and-set. It is in the
  fork's core pack and not upstream's, which the warrant records.
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
  with nothing added but the sibling yield, `work_holder`, and the outage stop. `gc
  worktree` covers part of `work-setup.sh`, and tk-1tfzr71.10 moves that part.
- **`await-ruling.sh --blocked-by`.** Searched: `gc sling --after`, order triggers on
  `bead.closed`. Gas City has no sling on unblock (`docs/warrants.md`, deferred
  dispatch), so a bead that waits on another needs the edge and the arm this script
  already makes for a gate.

## Rejected

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
