---
name: Cutover decisions and open discussion items (2026-08-24)
description: The operator's rulings on the nine attention items from the rewrite briefing, and the questions deliberately left open for discussion. Update rulings here as they land; delete items as they resolve.
---

# Decisions

1. **Cutover** — quiet the city, merge, run `assets/scripts/cutover-2026-08.sh`
   via an outside agent, bounce; runbook at `cutover-runbook.md`. The script
   includes the helm build/verify step (dashboard staleness has bitten
   before).
2. **Live-validation risk** — accepted; every PR requires operator approval,
   so commits are seen before merge. Residual runtime risk covered by the
   runbook's attended-first-merge step.
3. **Notification surface** — board-first accepted as the contract; the
   narrower surface beats the old mix of places. Operator may add mail
   mirrors later if a silent wait bites.
4. **Mayor** — removal stands as a net win *provided* the traffic it absorbed
   is genuinely gone. See TODO-1.
5. **Learned-rule lint wiring** — discuss first (TODO-2); do NOT auto-wire at
   cutover.
6. **Review gates** — triage is the sole authority over `check_set`,
   including a tightly-limited charter-bounded waiver mechanism; no
   dispatcher pre-sets. Recorded in `specs/2026-08-review-gates/scope.md`.
7. **gctk failure mode** — blessed, with the seam surfaced in the helm board
   via a build-status file. Recorded in
   `specs/2026-08-review-gates/gctk-promotion.md`.
8. **Liveness sweep** — clear-visit pass accepted; bias wording to revisit
   (TODO-3).
9. **Deletions** — demo skills RESTORED (`skills/demo-capture`,
   `skills/gc-demo-script`) and a triage-decided `demo` gate added to the
   review-gates menu. burn-watch/patrol-spend-split stay deleted. Dog:
   TODO-4.

# TODOs (discussion items)

- **TODO-1 — Mayor-shaped needs.** The mayor's real value was "a live agent
  to talk to when something breaks" — and it was usually too loaded with
  other work to serve that well; mechanik, being less loaded, worked better.
  Watch post-cutover: (a) volume of human-terminal states landing on the
  operator's queue; (b) whether mechanik stays unloaded enough to remain the
  break-glass conversation partner (guard its prompt against scope creep).
  Revisit only if either regresses.
- **TODO-2 — Lint: why per-rig, and why "lint".** To discuss. Standing
  answers to react to: per-rig because `lint_command` is rig-owned config —
  a pack that force-wires its detectors into every importing rig's refinery
  would gate other repos' merges without their consent (the pack ships the
  tool, the rig owns its gates); "lint" because these are source-shape rules
  with no runtime state, which belong at write/review time — `gc doctor` now
  asserts live system properties only. Open question: wire
  `tools/lint-learned.sh` into the gc-toolkit rig's own `lint_command`
  (one line of rig config), and/or into the pre-commit hook?
- **TODO-3 — Liveness sweep bias wording.** "Re-report, never mute" stands
  as the fail-safe direction, but the framing (and tuning: batch cadence,
  what lands in the operator's triage visit vs. converse) gets a pass after
  the first live week.
- **TODO-4 — Dog coverage.** The gastown dog pool (city-baked maintenance
  chores) is gone with the import and nothing native replaces it. Determine
  what the dog pool actually did in this city (session logs / gastown source)
  and either confirm the deacon patrol + orders cover it or add the missing
  duties explicitly.
- **TODO-5 — Post-cutover cleanup.** Delete `cutover-2026-08.sh`, its test,
  and the runbook once the cutover completes cleanly; move ruling residue
  from this file into the docs it belongs in.
