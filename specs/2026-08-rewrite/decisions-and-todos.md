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
5. **Learned-rule lint wiring** — DECIDED (2026-08-24): wire into the
   gc-toolkit rig's own `lint_command` at cutover (runbook step 4b); no
   other rig, no pre-commit wiring.
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
- **TODO-2 — RESOLVED (2026-08-24).** Wire `tools/lint-learned.sh` into the
  gc-toolkit rig's `lint_command` at cutover (runbook step 4b); this rig
  only, no pre-commit wiring. Rationale stands: per-rig because the rig owns
  its gates; "lint" because these are source-shape rules with no runtime
  state, and `gc doctor` now asserts live properties only.
- **TODO-3 — Liveness sweep bias wording.** "Re-report, never mute" stands
  as the fail-safe direction, but the framing (and tuning: batch cadence,
  what lands in the operator's triage visit vs. converse) gets a pass after
  the first live week.
- **TODO-4 — Dog coverage (investigated 2026-08-24; two decisions remain).**
  Finding: the rewrite kept every *detector* and dropped every *actuator*.
  Duty-by-duty: hang diagnostics, zombie PIDs, and orphan processes are
  covered (deacon); jsonl-backup/reaper were gastown-internal (N/A). Four
  gaps, with dispositions:
  1. **Dolt backups** — the backup dog performed them (~6h cadence; the
     deacon's STALE_H=12 verifier assumes it). UNCOVERED unless the dolt
     builtin pack still has an actor. Runbook step 0 now verifies against
     the live city. If unclaimed: cheapest fix is an exec order
     (`orders/dolt-backup.toml` + ~30-line wrapper, no LLM). **OPERATOR
     DECISION after the live check.**
  2. **Orphan-database removal** — detection stays advisory in the deacon
     (never --force from a patrol step); a new `dolt-orphan-dbs` escalate
     key routes the finding to a visit. Actual removal stays manual, or
     folds into the same exec order as (1) below the old threshold of 20.
  3. **Compaction** — detection (>50k commits) now escalates via the new
     `dolt-commit-bloat-<db>` key; compaction itself stays manual until a
     FLAG actually fires.
  4. **Wedged-agent recovery (shutdown dance)** — deliberately traded for
     human triage visits (liveness sweep) plus the widened no-consent-UI
     fragment and the cycle-recycle hook that remove the top causes.
     **Cost analysis (2026-08-24):** this is the one true regression — a
     ≤7-minute cheap-model dance became an operator interrupt with up to
     ~6h wedge latency (the sweep's precheck interval), and the mechanical
     alternative (`gc runtime request-restart`) silently no-ops for
     refinery/named on-demand sessions. Everything else the dog did moved
     DOWN in cost (exec orders beat dog sessions; a dog pool is
     0-when-idle so it cannot recreate the boot failure mode).
     **Recommendation:** reintroduce the dog as a warrant-executor-ONLY
     pool (name is collision-free without the gastown import): demand-
     scaled 0→2, cheap model, work arrives only as routed warrant beads
     from the deacon/witness detectors, one formula
     (mol-dog-shutdown-dance) + one probe script, a declared
     [metadata.warrant] registry group, escalate.sh on every stop path;
     the dead session's beads flow into existing witness orphan recovery
     (no healer reappears). ~15-40 cheap calls per episode vs. one
     operator interrupt + stalled WIP. **DECIDED (2026-08-24): (a)
     reintroduce at cutover — implemented in this change** (`agents/dog/`,
     `formulas/mol-dog-shutdown-dance.toml`,
     `assets/scripts/dance-probe.sh`, `[metadata.warrant]` in
     `lifecycle/lifecycle.toml`, warrant filing wired into the
     deacon/witness patrols; boot-health stays report-only).
  Residue (cosmetic, clean opportunistically): `tmux-pick-session.sh` still
  filters `dog`; `docs/gascity-agents.md`/`gascity-packs.md` still list dog
  in the gastown roster tables (they document the runtime/gastown, so
  arguably correct as-is).
- **TODO-5 — Post-cutover cleanup.** Delete `cutover-2026-08.sh`, its test,
  and the runbook once the cutover completes cleanly; move ruling residue
  from this file into the docs it belongs in.
