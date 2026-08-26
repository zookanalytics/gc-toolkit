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
- **TODO-4 — Dog coverage (investigated 2026-08-24; item 1 resolved
  2026-08-26).**
  Finding: the rewrite kept every *detector* and dropped every *actuator*.
  Duty-by-duty: hang diagnostics, zombie PIDs, and orphan processes are
  covered (deacon); jsonl-backup/reaper were gastown-internal (N/A). Four
  gaps, with dispositions:
  1. **Dolt backups — RESOLVED (2026-08-26). No replacement actor is
     needed, and the gap this item feared never existed.** Two premises
     behind the original wording were wrong. The rewrite did not drop the
     dog pool: `agents/dog/` ships in the new pack. And the dolt builtin
     pack does not route backups to a pool at all, so no actor was ever at
     risk.
     Checked live against `~/.gc/system/packs/dolt`. Every Dolt order but
     one is `exec`, which runs inline in the controller with no pool and no
     actor: `mol-dog-backup` (6h), `mol-dog-compactor` (24h),
     `mol-dog-doctor` (5m), `mol-dog-phantom-db` (1h), `dolt-health` (30s),
     `dolt-remotes-patrol` (15m). `mol-dog-backup.toml` carries the header
     "Converted from formula+pool to exec", so the ~6h cadence the deacon's
     STALE_H=12 verifier assumes is intact.
     Observed, not just inferred from the order shapes: every manifest
     under `$GC_CITY_PATH/.dolt-backup` was written at 2026-08-26 06:00,
     well inside the 12h threshold, and the five directories carrying them
     (`gc`, `lx`, `sl`, `su`, `tk`) are exactly the five databases
     `gc dolt health` reports live. A sixth directory, `sp`, is frozen at
     2026-07-21 and has no live database behind it, so the deacon's
     verifier passes it to the extra-directory branch and emits
     `INFO sp: backup dir with no live database (advisory)` rather than
     counting it as a stale backup.
     The one pool-shaped Dolt order is `mol-dog-stale-db` (cron 4h,
     `pool = "dog"`), which `city.toml` suppresses via
     `[orders] skip = ["mol-dog-jsonl", "mol-dog-stale-db"]`. **It stays
     skipped**, because the dog pool that now exists is not the pool that
     order was written for. `agents/dog/` is a warrant executor: its prompt
     admits one formula (`mol-dog-shutdown-dance`), and that formula's
     `receive-warrant` step closes any bead lacking `warrant.target` /
     `warrant.reason` as `gc.outcome=refused` with a MALFORMED_WARRANT
     note. A poured `mol-dog-stale-db` bead carries no `warrant.*` fields,
     so un-skipping the order would refuse and escalate every four hours
     while no cleanup ran. `docs/authority-map.md` scopes the pool the same
     way, to killing a wedged session under a warrant. The precedent is
     already in-pack: `orders/boot-health.toml` notes that the dog pool
     existing again does not license reusing it.
     Staying skipped costs almost nothing, which is the other half of the
     argument. A dry-run `gc dolt-cleanup --json --probe` on 2026-08-26,
     after months with the order suppressed, found 0 stale databases to
     drop, 0 orphan processes to reap, 0 errors, 0 force blockers, and
     75324 reclaimable bytes. There is no backlog to justify pointing
     destructive `DROP DATABASE` work at a pool that holds kill authority.
     If the duty is ever wanted back, the fix is the conversion every
     sibling order already got. `mol-dog-stale-db`'s formula body is
     already a single deterministic shell step whose only parameters are
     two numeric thresholds, so it needs an agent no more than
     `mol-dog-backup` did. That file is builtin pack source under
     `rigs/gascity/examples/bd/dolt/`, so it would land as a gascity bead,
     not here. Filed as gascity bead gc-t7g1h at low priority; it is an
     operator call, not a repair.
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
  Residue (cosmetic, clean opportunistically): `docs/gascity-agents.md`
  and `gascity-packs.md` still list dog in the gastown roster tables (they
  document the runtime/gastown, so arguably correct as-is).
  `tmux-pick-session.sh` filtering `dog` was listed here as residue too;
  it is not. The pool exists, and the script's own comment now gives the
  filter its reason — the warrant executor is short-lived and rarely worth
  attaching to.
- **TODO-5 — Post-cutover cleanup.** Delete `cutover-2026-08.sh`, its test,
  and the runbook once the cutover completes cleanly; move ruling residue
  from this file into the docs it belongs in.
- **TODO-6 — RESOLVED (2026-08-26). The stale `bd` embedded-store backup is
  off by policy, not unattended.** Surfaced while closing TODO-4 item 1:
  `gc doctor` warns that two scopes have not synced their embedded-store
  backup in a very long time — `rigs/gascity` at 1625h25m and
  `rigs/shutupandlisten` at 1902h25m, against a 24h threshold. This is a
  different pipeline from `mol-dog-backup`, which writes
  `$GC_CITY_PATH/.dolt-backup`; the warning reads `.beads/backup/` inside
  each rig.
  Nothing is broken and nothing needs repair. `backup.enabled: false` is
  set in the city's own `.beads/config.yaml` and in all four rigs, so the
  embedded-store backup is disabled uniformly and deliberately. The two
  flagged scopes are simply the two that had synced before it was turned
  off, and their frozen `backup_state.json` is what the check reads. The
  other two rigs never wrote that file, so `BdBackupFreshnessCheck` skips
  them and the warning names two scopes rather than four. Recovery for all
  of these stores rests on the Dolt backup, which is current.
  What the finding does expose is a defect in the check itself:
  `BdBackupFreshnessCheck` reads only `backup_state.json` and never
  consults `backup.enabled`, so a deliberately-disabled backup warns
  forever on its own leftovers. Its `FixHint` tells the operator to
  "verify backup.enabled", which already, correctly, reads `false`, and
  `CanFix()` returns false, so the warning has no path to clearing. The
  check is Go under `rigs/gascity/internal/doctor/`, so the fix lands as a
  gascity bead: gc-nyy49.
