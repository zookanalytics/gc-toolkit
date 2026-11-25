---
name: Gas City search for the pour-text check's run listing (tk-zefuahv)
description: The record, for tk-zefuahv, of the Gas City behavior doctor/check-pour-text-current stops reporting, a run that finishes on the step text it poured with, read at gastownhall/gascity upstream main d6d5784f9c, with the reason Gas City gives for it, the city's measurement and why it is no fault to fix at the source. Read it when reviewing the check's removal of its run listing, or before the doctor reports runs on older step text again.
---

# Gas City search: a run finishes on the step text it poured with

`doctor/check-pour-text-current` reports no live run whose formula changed after
the run poured. That accommodates one behavior of Gas City: a run keeps the step
text it poured with. Gas City is read at gastownhall/gascity upstream main
`d6d5784f9c` (2026-11-24T07:45Z).

## The behavior

- **A step's text renders once, at pour.** `Instantiate` builds each step's bead
  with `stepToBead`, whose description is what `substituteStepDescription`
  returns: the step's text with the run's variables substituted
  (`internal/molecule/molecule.go`).
- **A retry rebuilds its attempt from the frozen step spec.** `spawnNextAttempt`
  deserializes the step spec that the control bead, or its spec bead, carries,
  and builds the attempt from it (`internal/dispatch/control.go`). The v2
  formula spec calls that spec a sidecar the compiler emits at materialization,
  carrying the serialized step definition
  (`docs/reference/specs/formula-spec-v2.md`, under `max_attempts`).

## The reason Gas City gives

Gas City's guide to formulas states it as the design: "Applying a formula
materializes its steps as beads, and from that moment the work is independent
of both the formula file and any agent session: sessions crash and recycle, but
the work persists, so whoever picks it up next finds the same state"
(`docs/guides/understanding-formulas.md`).

## Tested against this city

Commit 752d2c0ac9 records the measurement. The doctor run of 2026-11-23T15:44Z
named 25 `mol-polecat-work` runs at error. None had started: tk-8v6ly4b poured
at 05:47Z and closed its load-context step at 18:52Z. The change they were
flagged for, 539a62ca9, on main at 06:15Z, touched the preflight-tests and
self-review steps, which each run would reach on the text it poured with.

The reason holds in this city, because one run passes through several sessions.
The polecat's implement step ends its session, and the run's self-review
iterations are claimed fresh from the pool
([polecat-doctrine.template.md](../../template-fragments/polecat-doctrine.template.md),
"A step inherited from core, and the tree a claim finds"). So each session that
takes up a run finds the step text the run poured with.

## No fault to fix at the source

The behavior is the design Gas City states, and its reason holds here, so this
change files no fix at the source. A formula change leaves one question about a
run poured before it: whether to cancel the run and pour it again. The answer
turns on what the change did, which a file's git history cannot tell, so the
check reports no such run.

## What removing the run listing costs

Nothing lists the runs still on older step text. A warning in its place would
keep the doctor failing whenever a formula changes while runs poured from it
are going, because `gctk doctor run` records every check that is not ok as
failing ([services/gctk/doctor/doctor.go](../../services/gctk/doctor/doctor.go)).
A note on a passing result would print only under `gc doctor --verbose`,
because Gas City's `printResult` writes a check's detail lines only when verbose
(`internal/doctor/doctor.go`), and the doctor run records nothing of a passing
check. The PR's summary puts that choice to the operator.
