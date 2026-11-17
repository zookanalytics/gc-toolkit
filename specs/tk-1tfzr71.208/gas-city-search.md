---
name: Gas City search for pouring a PR's review run the claim does not retire
description: The Gas City primitives searched for pouring the landing order's review run for a PR's bead that the refinery holds, what each does at a named upstream commit, and why the pour cooks the formula with no target and writes the bead's edge onto the run itself. Read it when changing or reviewing that pour, or when the arch check asks for the search.
---

# Gas City search for pouring a PR's review run

Read on 2026-11-17 at `gastownhall/gascity` main 08fa618049.

## The need

The landing order pours one review run, `mol-pr-review`, for a PR's bead on
the pending record. The run must work while the refinery holds that bead: on
the record the bead stays open or blocked and assigned to the refinery, and the
refinery runs no step of the run. The bead waits on the run, because the order
reads a bead's runs from its `blocks` edges onto their roots (`runsIn` in
`services/gctk/pr/withdraw.go`). The run's beads take the bead's priority, and
the bead has one live run at a time, a pour that stops partway included.

## What was searched

- **`gc formula cook --attach <bead>`**, the pour the order made. For a
  graph.v2 formula it makes the bead the one member of a synthetic input convoy
  and stamps the convoy on the root as `gc.input_convoy_id` (`PrepareInvocation`
  and `NormalizeInputConvoy` in `internal/graphv2/invocation.go`). It runs under
  a per-source workflow lock that reuses a live workflow of the same source, and
  gives every bead it creates the bead's priority (the `--attach` arm of
  `newFormulaCookCmd` in `cmd/gc/cmd_formula.go`). Before `gc hook --claim`
  hands out a step, it retires a workflow whose input members are all settled,
  and it reads an open member assigned to an agent that is neither the claimer
  nor a seat on one of the workflow's steps as settled
  (`retireDoneWorkflowCandidates`, `hookRetireIfInputSettled` and
  `workflowInputMembersSettled` in `cmd/gc/cmd_hook_claim.go`). The refinery is
  such an agent, so the first claim of any step retires the run as skipped, and
  no config turns the check off.
- **`gc sling <target> <bead> --on <formula>`.** Its graph.v2 path passes the
  bead to `PrepareInvocation` as the target
  (`prepareGraphV2FormulaInvocation` in `internal/sling/sling_core.go`), which
  makes the same convoy, so the claim retires its runs the same way.
- **`gc formula cook` with no target.** A graph.v2 formula that names no
  `{{convoy_id}}` pours with no input convoy (the untargeted arm of
  `PrepareInvocation`), and `mol-pr-review` names none. Its root carries no
  `gc.input_convoy_id`, so the claim reads its input as pending and never
  retires it (`workflowRootIDForInputCheck` and `workflowInputDoneAcross` in
  `cmd/gc/cmd_hook_claim.go`). The cook still stamps every var on the root as
  `gc.var.<name>` (`stampFormulaVars` in `internal/molecule/molecule.go`),
  routes each step by its `gc.run_target` (`decorateFormulaCookGraphV2Recipe`,
  which both arms of the cook call), and prints every bead it created in its
  `--json` line's `id_mapping` (`formulaCookJSONResult`). It writes no edge onto
  a bead, takes no lock and copies no priority. It keys no root either, since
  `stampFormulaCookGraphV2Root` keys one only by its input convoy, so each cook
  pours a new run.

## What the pour composes

The order cooks with no target, under the store's record lock that each of its
runs holds for a record, so two pours for one bead run one after the other, as
under the per-source lock. It gives each bead the cook created the bead's
priority in one `bd update`, then writes the bead's `blocks` edge onto the root
with `bd dep add`. A pour that stops after the cook leaves a root that no edge
of the bead names, which can end before the next run reads it. The next run
finds it by its `gc.var.pr_bead`, live or closed, and writes the edge before it
decides anything of the record, so the run holds the bead as an attached run
does. A root the bead's store does not hold gets no edge, since bd adds an edge
onto an id outside its own prefix that holds
nothing, and the order files a human gate on the bead, which keeps it from
pouring another. That root is what a city that serves graph beads from a store
of its own makes, where `gc formula cook --attach` of a graph.v2 formula
refuses instead (the help of `gc formula cook`).
