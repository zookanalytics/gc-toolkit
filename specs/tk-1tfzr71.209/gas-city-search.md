---
name: Gas City search for who a waiting PR's bead is assigned to
description: The Gas City primitives read for the assignee of a PR's bead on the pending record, what each says at a named upstream commit, and why the bead is assigned to the refinery only while it validates a head and to nobody while the PR waits. Read it when changing who the record or the landing order assigns a PR's bead to, or when the arch check asks for the search.
---

# Gas City search for who a waiting PR's bead is assigned to

Read on 2026-11-18 at `gastownhall/gascity` main 5b7728de34.

## The need

A PR's bead on the pending record is read by three actors while its PR waits:
the landing order, which merges it, the refinery, which validates a head the
PR moved to, and a review run attached to the bead. Each needs to know whether
someone works the bead now, and Gas City itself reads the same answer when it
delivers work to a session and when it decides whether a workflow's input is
still its own. The field that answers must mean the same to all of them.

## What was searched

- **The assignee, Gas City's delivery of work to a session.**
  `engdocs/architecture/dispatch.md`: "Generic pool demand is ready work with
  `assignee=""` and `gc.routed_to=<target>`; assigning the pool template itself
  is not pool demand. Direct named-session delivery is ready work with
  `assignee=<named-session-identity>` and no generic route metadata". A bead
  whose PR waits for review and merge is neither: it is nobody's work, so it
  carries no assignee and no route. This covers the need. The refinery is
  assigned the bead in the write that hands it a head to validate, and the
  write that ends that work, the publication, assigns the bead to nobody.
- **The handed-off rule.** `workflowInputMembersSettled` in
  `cmd/gc/cmd_hook_claim.go` "reports whether every one of members is terminal,
  or non-terminal but handed off to an assignee outside identityCandidates that
  is not one of the workflow's own seats", and an open member assigned to
  nobody returns not settled, so `gc hook --claim` keeps the workflow. A review
  run attached with `gc formula cook --attach` to a bead assigned to nobody is
  therefore handed out at its first claim, and one attached to a bead the
  refinery is assigned is retired there. `TestCityAcceptance`
  (`services/gctk/internal/gascity/acceptance_test.go`) runs both with the
  city's gc. So the landing order never assigns the refinery while a run is
  attached: a changed head stays assigned to nobody until no run and no
  withdrawal holds it.
- **Demand for assigned work.** `workBeadHasAwakeDemand` in
  `cmd/gc/compute_awake_set.go` counts an open bead as its assignee's demand
  only while it reads ready, and a blocked bead never. The hand-over of a
  changed head assigns the refinery, so Gas City wakes the refinery for a head
  nothing holds, as after a polecat's hand-off, and the landing order still
  wakes it itself while only merge holds hold the bead
  ([the hand-over's search](../tk-1tfzr71.165/gas-city-search.md)).

## What the change composes

No key, value, state or bead kind is added. The record's status values,
`merge_result` values, marker and PR keys stay Gas Town's, and the bead's
assignee carries Gas City's meaning: who works it now. Three readers gain
words for that one field. The landing order's runs leave a bead someone other
than the refinery is assigned to that assignee: they do not take it, and they
report `assigned` for one assigned after a run took it. They no longer report
`released`. The evaluator names a bead's
assignee in a condition of kind `assigned`, so `gctk pr status` and the board
say who holds the bead. And a run reports `unassigned` when it assigns to
nobody a bead the record published while publications still left the refinery
assigned, a step the build that returns the review run's launch to
`gc formula cook --attach` deletes.
