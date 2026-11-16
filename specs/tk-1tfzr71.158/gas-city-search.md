---
name: Gas City search — the patrols' move onto orders and Gas Town's witness
description: The search behind each surface design tk-1tfzr71.158 adds: the primitive looked for in Gas City, bd and Gas Town, and why it does not cover the need. Read it when building one of the design's units, or when a review asks why a surface is the pack's.
---

# Gas City search for design tk-1tfzr71.158

Gas City is read at upstream main 918f45f71 (2026-11-16) and Gas Town at
gascity-packs 7f86098c04ea, whose witness and deacon formulas are byte-identical
at packs main 0f07496d2fa4. A path without a repository is Gas City's. Each
entry names the surface the design adds, what was searched for, and the gap.

## The doctor order and `gctk doctor record`

**Searched.** An order that runs `gc doctor`: none of core's orders
(`internal/bootstrap/packs/core/orders/`), none of the dolt pack's
(`examples/bd/dolt/orders/`), and none of Gas Town's, whose `orders/` holds only
`digest-generate.toml` (gascity-packs `gastown/orders/`). Gas Town's deacon runs
`gc doctor` inside its system-health step and mails `mayor/` a finding
(`gastown/formulas/mol-deacon-patrol.toml`, system-health). `gc doctor --json`
prints its report and stores nothing (`doctorJSONResult` and its report,
`cmd/gc/cmd_doctor.go`). An exec order is Gas City's shape for mechanical work:
"An exec order runs the script on the orchestrator — no agent, no LLM, no work
beads" (`docs/tutorials/07-orders.md`, Formula orders vs. exec orders).

**Gap.** Turning a run's results into records a surface renders, and keeping
those records current run to run. The order is native, and the verb is the
part no primitive does.

## The doctor result record

**Searched.** A keyed problem record with a lifecycle:

- `gc mail send --dedup <key>` suppresses a send while a live, unarchived
  message with that key sits in the same mailbox (`cmd/gc/cmd_mail.go`). It is
  a mailbox entry, and this city's operator reads the board, which excludes
  mail.
- Core's `escalate.sh --incident-key` keeps a fingerprint under
  `<city>/.gc/incidents` and re-sends after a reminder interval
  (`internal/bootstrap/packs/core/assets/scripts/escalate.sh`). It throttles
  mail.
- `gc event emit <type>` records a custom event (`cmd/gc/cmd_event_emit.go`)
  and keeps no current state for a key.
- `[doctor]` config has size thresholds, the nested-worktree toggle and local
  checks, and no way to mute or acknowledge a check (`DoctorConfig`,
  `internal/config/config.go`).
- No `gc` command creates an incident, alert or problem object (no such `Use:`
  in `cmd/gc`).

**Why not the pack's patrol finding.** The record has to be held for placement
in the same write that creates it, keyed by the result's whole name, and ended
when its check passes. `patrol-finding.sh` keys `--check` by the name's last
segment, files `--no-react` with no hold, and ends nothing, so the record would
grow the script past a fix, which AGENTS.md sends into gctk. The record is
gctk's, beside the patrol finding, and one warrant covers both.

**What closes a record.** Doctor's report marks two results it did not
measure: a check it abandoned carries `timed_out` (`doctorJSONResult`,
`cmd/gc/cmd_doctor.go`), and a check the store gate skipped is a stand-in whose
message starts `not checked:` (`internal/doctor/store_liveness.go`). It marks
nothing for a check it left out, because it registers checks conditionally, run
by run (`CheckNames`, `internal/doctor/select.go`), and `gc doctor --check
<name>` answers `unknown_check` with that run's registered names
(`doctorUnknownCheckFailure`). So no Gas City surface tells a check that
retired from one a run left out. The verb closes a record as retired only when
`gc rig list --json` no longer lists its rig, and leaves every other retirement
to the change or the person that knows it.

## `gctk dolt unbacked` and `doctor/check-backup-current`

**Searched.** A judge of whether a store's backup holds its writes:

- `mol-dog-doctor` dates a backup by "the mtime of the remote's manifest and
  never the mtime of the newest file of any kind", stale at 12 hours
  (`examples/bd/dolt/assets/scripts/mol-dog-doctor.sh:33,91`), and dedups its
  advisory on the set of condition words.
- `bd-backup-freshness` reads `last_sync` and warns at 24 hours, in one joined
  message with no Details or Payload
  (`internal/doctor/checks_bd_backup_freshness.go`).
- `mol-dog-backup` escalates a failed sync under the incident key
  `dolt-backup:required-sync` (`examples/bd/dolt/assets/scripts/mol-dog-backup.sh`).
- bd's backup state file holds only `last_sync` and `duration`
  (`.beads/dolt-backup-state.json` in each store, read on 2026-11-16), and bd
  stamps `last_sync` when a sync returns (`updateDoltBackupState`, beads v1.3.4
  `cmd/bd/backup_dolt.go`). `bd backup status` reports the destination,
  `last_sync` and the sync's duration (`showDoltBackupStatusJSON`).
- `dolt backup` adds, removes, restores and syncs a backup (`add`, `remove`,
  `restore`, `sync`, `sync-url`, dolt 2.7.3), and no dolt pack command reads one
  (`examples/bd/dolt/commands/`).

**Gap.** None reports the newest commit a backup holds, and commits are what a
backup carries, since `DOLT_BACKUP` "syncs COMMITTED history"
(`commitWorkingSetBeforeBackup`, beads v1.3.4 `cmd/bd/backup_proxied_server.go`).
So an idle store reads stale, and a sync that returns without carrying a write
reads fresh. A restore copies the whole store to read it, and the backups here
reached 9.2 GB on 2026-11-16. The check reads that commit from the backup's own
files through Dolt's storage packages (`nbs.NewLocalStore`,
`go/store/nbs/store.go` in `github.com/dolthub/dolt/go`), and it dates what the
store holds beyond that commit from the store's own commits and from the write
times its rows carry (`dolt_diff`). It is a pack doctor check, so `gc doctor`
runs it and the doctor order records it, and its `run.sh` only calls gctk.

## `gctk patrol cold` and `doctor/check-patrol-advancing`

**Searched.** A report of a named, always-on session whose patrol stops
advancing:

- The work ladder paces only pool-managed seats and a pool seat a named
  session took over (`ladderGoverns`, `cmd/gc/work_ladder_lane.go`).
- Doctor's `agent-sessions`, `orphan-sessions` and `session-model` checks judge
  whether sessions and their beads exist, not whether a patrol advances
  (`cmd/gc/doctor_session_model.go`).
- Gas Town's `witness-heartbeat-check` is a command its deacon runs, read-only,
  on the session's last activity (`gastown/commands/witness-heartbeat-check/run.sh`
  at 7f86098c04ea), in no gastown release.
- An always-on session gets no further turn after its turn ends (Gas City issue
  #4090), which the pack's `witness-nudge` order meets with a nudge and no
  record.

**Gap.** A record that a witness's current patrol has not advanced within a
bound, judged on the patrol its live session runs.

## `gctk worktree salvage`

**Searched.** A native salvage of a dead owner's worktree:

- Core's orphan sweep releases the claim and does "No worktree salvage — cities
  that staff a work-health patrol role (e.g. the gastown pack's witness) handle
  that separately" (`internal/bootstrap/packs/core/orders/orphan-sweep.toml:5-6`).
- `gc worktree cleanup` removes only a worktree `gc worktree ensure` made, with
  its attempt id and generation, and refuses a dirty one or unpushed commits
  (`gc worktree cleanup --help`). The polecats' worktrees are cut with git.
- The controller's closed-bead worktree reaper reaches closed beads only
  (`reapClosedBeadWorktrees`, `cmd/gc/bead_worktree_reaper.go`).
- Gas Town's witness salvages in its step text, through keys that differ from
  ours (gascity-packs `gastown/formulas/mol-witness-patrol.toml:324-462`).

**Gap.** Gas Town's salvage, on the keys our polecats write, pushed under the
refinery's lease. The verb moves the step's blocks into one tested call (rule
2), and it releases nothing. The `work_dir` clear that comes before a removal is
bd's conditional update, which writes nothing once the assignee or status it
names has moved (`--if-assignee`, `--if-status`, beads v1.3.4
`cmd/bd/update.go`).

## `gctk session progress`

**Searched.** The session-liveness design's search for a seat that prints while
its work stands still (`specs/tk-1tfzr71.137/design.md`, section 11) found no
Gas City reader of a session's own writes. This design adds no rule to it. It
moves `seat-progress.sh` into gctk with a pass over the rig's claims, which is
growth AGENTS.md sends into gctk.

## `gctk mail finding`, `gctk refinery stuck` and `gctk patrol next`

**Searched.** `gc mail` reads, peeks, archives and marks mail, and turns none
into a record. Gas Town's check-inbox mails `mayor/` (W:115). Gas Town's
check-refinery nudges the refinery and mails `QUEUE_HEALTH` (W:1123), and
doctor's `pool-idle-routed-work` reports routed work a pool leaves while an
instance idles, which is not the refinery's assigned inbound queue. Gas Town's
next-iteration is step text over `gc bd mol wisp`, `gc bd update` and
`gc bd mol burn`, which the verb composes, with the defer the pack's copy adds.

**Gap.** Each verb is one tested call for a block of step text (rule 2), over
the native calls named, and adds no rule the block does not already hold.
