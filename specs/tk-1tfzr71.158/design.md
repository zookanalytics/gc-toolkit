---
name: Design — the patrols move onto Gas City's orders and Gas Town's witness
description: The design record for tk-1tfzr71.158, the design child of initiative tk-1tfzr71.19, on moving orphan release, Dolt health and gc doctor onto native and pack orders, retiring the deacon with boot health, the incident ledger and the liveness census, and keeping the witness as the pack's copy of Gas Town's. Use it to approve the design at its gate, or to build one of the units it defines.
---

# Design: the patrols move onto Gas City's orders and Gas Town's witness

This is the design record for tk-1tfzr71.158, the design child of the
initiative tk-1tfzr71.19. The pack was read at e01b53e94, the commit
`integration/tk-1tfzr71.19` was cut from, and every pack line number is at that
commit. Main has since moved to 6dd9d13ee. Of the files this design retires,
PR #1531 edits only seven lines of `liveness-sweep.sh`, and PR #1535 edits
none. Gas City is cited by symbol at upstream main 918f45f71, and section 12
names where the city's gc build differs. Gas Town is cited at two gascity-packs
commits: 66897e7132c9, which Gas City's `go.mod` pins and which is gastown
0.1.13, and 7f86098c04ea, which the pack's refinery copy follows. Gas Town's
witness and deacon formulas are byte-identical at 7f86098c04ea and at packs
main 0f07496d2fa4. `W:` cites `gastown/formulas/mol-witness-patrol.toml` at
7f86098c04ea. The stores, the `human` mailbox and the doctor sweep's last run
were read on 2026-11-16 between 04:00Z and 04:50Z, except where a section names
a later read. This repository is public, so the ids of beads in other stores
are in this bead's notes, not here.

## What the operator approves

Today the patrols are two always-on agent roles, a witness in each rig and the
city's deacon, and three orders. The witness recovers work whose owner died
and watches the refinery's queue. The deacon runs `gc doctor`, judges Dolt and
its backups, and kills stray processes. Boot health watches the deacon, and the liveness census files
questions about work nothing names. Gas City already runs orders for most of
this: its controller and core's orphan sweep release a dead session's claims,
its controller ends the processes a closed session left behind, and the dolt
pack's orders watch the Dolt server and its backups. Approving this design keeps
the witness as the pack's copy of Gas Town's, retires the deacon with boot
health and the incident ledger, runs `gc doctor` from an hourly order, and
retires the census. The implementation child files the seven units of section
10. A change to the town's `city.toml` comes just before the landing, and a
second one and a cutover after it.

These calls carry a cost either way:

1. **The witness stays our copy of Gas Town's witness, taken at the commit our
   refinery copy follows.** The copy follows gascity-packs 7f86098c04ea, and
   each step calls one tested script. The cost: nothing tracks Gas Town for us,
   so when its witness changes, someone diffs the two formulas against the
   difference table in section 1. The other way is to import Gas Town's pack
   and exclude every role but the witness, which needs a Gas City build newer
   than the city's. That runs Gas Town's text unchanged. At that commit the
   text returns a conversation's task to the pool, moves a polecat's worktree
   pointer to a key our polecats do not read,
   mails a mayor this city does not have, and files warrants for the dog pool
   the city retired. Following the release Gas City pins instead is worse for
   salvage: that witness reads a worktree key no polecat writes, so a dead
   polecat's unpushed work is never pushed.
2. **Orphan recovery returns nothing to the pool, and Gas City does.** The
   witness keeps salvage: it pushes a dead owner's unpushed work, closes a bead
   whose branch already landed, and removes the worktree once its work is on
   origin and no live session holds the bead. Gas City's controller and core's
   orphan sweep release the claim, as they already do within minutes of a
   session's close: no store holds a recovery stamp later than 2026-10-24. The
   cost: a dead claim those two leave stays claimed until someone acts on it.
   A doctor check reports it, so it reaches your board through call 4's
   record, when it sits in the city's own store, which Gas City's
   `session-model` check reads, or is a step left in progress in a rig's
   store, which the pack's `check-claim-advancing` reads. On a rig's other
   beads nothing reports it, because `session-model` reads only the city's
   store. No rig's store held such a claim when each was read at
   2026-11-16T06:57Z, and section 12 asks Gas City to read every store.
   Nothing notices a bead that keeps killing the sessions that take it, because
   Gas City's spawn-storm check counts only a bead stamped by a recovery or a
   rejection, and its releases stamp neither. The witness's own count has seen
   nothing since 2026-10-24 for the same reason. The other way keeps the
   witness's release beside Gas City's, which can release a live session's step
   under its alias (tk-8a6akou).
3. **The deacon retires, with no loop in its place.** Its duties move or end:
   `gc doctor` to call 4's order, Dolt health to the dolt pack's orders and a
   backup check, stray processes to the controller's sweep. Boot health, the
   incident ledger and the deacon's continue hook go with it. The cost: no
   session kills a stray process the controller's sweep does not reach, kills
   a zombie Dolt server, or runs a doctor check's fix on its own judgment. The
   deacon's ledger records none of those since 2026-10-09, and it took 3
   entries in the last 23 days. The other way is Gas Town's deacon, whose steps
   mail the mayor and file warrants for the dog, or a deacon prompt with no
   steps, which still spends a session on duties that have moved.
4. **`gc doctor` runs from an hourly order, and each failing check is one
   record in the po's queue that closes itself once the check passes.** The
   order runs with no agent, so no session's restart cuts it short
   (tk-1vdtaza), and a check that reports per rig keeps a record per rig. A
   record skips the first reaction. A warning that clears on its own, such as
   the compactor's retry marker, opens and closes with no session spent. A
   known one, such as `hold-label-routed-to`, is ruled once by closing its
   record, and the order leaves it closed until the check passes. Only a pass
   doctor measured closes a record. A check a run timed out, skipped or left
   out keeps its record open, and a run leaves out every store check while the
   store is unreachable. Two pack doctor checks are added for what the deacon
   judged, beside Gas City's own checks of backups and sessions: whether each
   backup holds its store's writes, and whether each witness's patrol is
   advancing.
   The cost: a doctor problem waits for the po's next sitting instead of a
   reaction within minutes. The other way keeps a first reaction on each new
   record. Since 2026-10-22 the compactor's retry marker alone was filed 26
   times, and all 25 that have closed were closed as needing no work.
5. **The liveness census retires, and the board takes the one read it
   leaves.** The triage bucket kind goes with it, as you ruled (conversation
   tk-2pvj50q). The board member (tk-1tfzr71.24) lists on each render every
   ready bead that no hold, route, assignee, arm or live run sends anywhere,
   by title, for the po to queue or close. It also renders the mail that Gas
   City's orders send the `human` mailbox, which nothing shows today. The cost:
   between this member's landing and the board member's, nothing lists such
   beads. The census's last gate in this rig, filed 2026-11-01, counted 60 new
   and 168 carried. The other way keeps the census until the board's read
   lands, as a retirement bead armed behind the board member, so the sweep and
   its buckets run a lane longer.

Approving the design as it stands ships the first option of each. Section 9
maps every item the initiative's notes owe, and section 11 the problems held on
this member.

## 1. Which Gas Town, and the witness as a copy

**The versions.** Gas City upstream main pins gascity-packs 66897e7132c9
(`go.mod`), the head of `release/gastown-0.1.11`, which packs main's
`registry.toml` lists as gastown 0.1.13. Packs main carries no later gastown
release. The merge member modeled the refinery on Gas Town at 7f86098c04ea,
because no release carries the pending record it needed
(`specs/tk-1tfzr71.66/design.md`, What the pack keeps of its own).

**The target is Gas Town at 7f86098c04ea, for the witness as for the
refinery.** At the pin, the witness's salvage reads `metadata.worktree`
(gastown 0.1.13, `mol-witness-patrol.toml:270-272`), a key no polecat writes,
Gas Town's own included. At 7f86098c04ea it reads `artifact_dir` and accepts a
`work_dir` at `.gc/worktrees/<rig>/polecats/<slot>/worktrees/<bead>` whose
repository shares the rig root's git common directory (W:324-407). Our layout
passes both tests: the slot name fits the accepted characters, and a per-bead
worktree's common directory is the rig checkout's. Two copies that follow one
commit read against one base. The copies move to a gastown release once one
contains 7f86098c04ea.

**A copy, not an import.** An import of Gas Town's pack on each rig brings its
witness, refinery and polecat (`gastown/pack.toml:13-15`). Gas City's
`agents_exclude` removes named templates from an import edge, and nothing
selects one (`Import.AgentsExclude`, `internal/config/config.go`), so an import
excluding the other two would leave the witness. The import cannot change step
text, and Gas Town's text at 7f86098c04ea does four things this city must not:

- It keeps only assigned beads and maps liveness from sessions (W:157-232), so
  a conversation's task, assigned to `human` or to a closed sitting's alias,
  reads as orphaned and goes back to the pool (W:1019).
- It adopts a legacy `work_dir` as `artifact_dir` and unsets `work_dir`
  (W:462, W:1012). Our polecats resume from `work_dir`.
- It mails `mayor/` for every escalation (W:115, W:290, W:773, W:1041,
  W:1123), which reaches no seat here.
- Its check-polecat-health files a warrant routed to the dog (W:1183), which
  the session-liveness member retired.

**The copy's steps** are Gas Town's five: check-inbox, recover-orphaned-beads,
check-refinery, check-polecat-health and next-iteration. Each step calls one
tested script (section 8). Its differences, each with its reason and what ends
it:

| Difference | Reason | Ends when |
|---|---|---|
| `next-iteration` defers the next wisp an hour. Gas Town's asks for the hour through `idle_timeout`. | Gas City applies no idle timeout to an always-on session, so its passes would run back to back. | Gas City gives an always-on patrol an idle interval. |
| It reads our anchors, PR states and conversations, and treats both pending-record values as an in-flight PR. | Our pipeline writes them. | The retirements of the old merge path (tk-1tfzr71.70) and the old review path (tk-1tfzr71.122) land. |
| It files findings and human gates where Gas Town mails the mayor. | The po owns little and takes none of that load, and the operator ruled at tk-rl8gz4b.29's design that this stays. | An operator ruling gives the po escalation handling. |
| Recovery returns nothing to the pool. Gas Town's reopens the bead with `gc workflow delete-source` and `reopen-source` (W:1019). | Gas City's controller and core's orphan sweep release a dead claim within minutes, and a second writer raced them (tk-8a6akou). | Gas Town's witness leaves the release to them, as the orphan sweep's header assumes. |
| Salvage keeps `work_dir`, and clears it only with the worktree it names. | Our polecats resume from `work_dir`. | The work formula records Gas Town's `artifact_dir`. |
| check-polecat-health files a finding on a pool seat whose pane prints but which has written nothing for three hours, judged by the seat's own writes. Gas Town's files a warrant on a bead's update time. | The controller's work ladder recovers a quiet seat, and no dog serves a warrant here. | Gas City paces a busy pool seat by its progress. |
| A pack doctor check reports a witness whose patrol stops advancing. Gas Town's deacon runs `witness-heartbeat-check` and nudges. | This city runs no deacon (section 3). | Gas City reports a named session whose work stops advancing. |
| The `witness-nudge` order prompts a witness that stopped short of `next-iteration`. | Gas City gives an always-on session no further turn (issue #4090). | Gas City closes #4090 with a fix that reaches a session stopped short. |
| check-refinery does not wake the refinery for a stale `pr_reconcile_pending` check (W:1080-1108). | The landing order runs the pending record with no refinery turn. | No end is planned. |

**The stuck-polecat difference ends.** `seat-progress.sh`, branch 2b of
recover-orphaned-beads, is our check-polecat-health. With the controller's work
ladder it covers what Gas Town's step covers: the ladder takes a seat whose pane
goes quiet, and the finding names a seat whose pane prints while its work stands
still. The rewrite moves it into Gas Town's step of that name.

## 2. Orphan recovery

**What Gas City releases.** Core's orphan-sweep order runs every five minutes.
It resets an in-progress claim whose holder no live session, configured agent
or pool instance answers to, through `gc bd release-if-current`, which writes
only while the assignee and status are the ones it read. It never resets a
claim held by `human` or one `gc agent is-foreign` cannot vouch for
(`internal/bootstrap/packs/core/assets/scripts/orphan-sweep.sh`). Its header
leaves salvage to a work-health role such as Gas Town's witness
(`orders/orphan-sweep.toml:5-6`). The controller releases an open or
in-progress bead routed to a pool whose assignee has no open session bead,
skips a bead labeled `human`, and clears the session-affinity keys in the same
write (`releaseOrphanedPoolAssignments`, `cmd/gc/pool_session_name.go`;
`releaseListed`, `cmd/gc/work_release.go`). A claim held under an alias that a
live session now carries stays with that session, which adopts it on its next
claim (`hookClaimExistingAssignment`, `cmd/gc/cmd_hook_claim.go`).

Each part of recover-orphaned-beads and each class of `orphan-dispose.sh`, and
where it goes:

| Today (`formulas/mol-witness-patrol.toml`, `assets/scripts/orphan-dispose.sh`) | After |
|---|---|
| Part 1, the candidates: beads naming an owner (`gc.session_id`, then the assignee, then `gc.session_name`), less an in-flight PR, a human route, a conversation and a topology root (:185-278) | Kept, in the salvage script. A person's hold is read from the open human gate that blocks the bead, not from `gc.routed_to=human`, which the dispatch member cleared from every store. Both pending-record values stay an in-flight PR. |
| Part 2, the liveness map and its fail safe (:354-481) | Kept, in the salvage script, from `gc session list --json`, which lists every session that has not closed. A map that does not load files `witness-empty-liveness-map`, as today. |
| Part 2b, a live owner's seat (:483-499) | Moves to check-polecat-health. |
| Part 3, salvage through `branch-context.sh` (:501-627) | Kept, in the salvage script. `branch-context.sh` retires: the witness runs in its rig's worktree, so the script checks that the bead's `work_dir` shares the rig root's git common directory, as Gas Town's does, and refuses a salvage that does not. The push keeps the refinery's lease (`branch-push.sh`). |
| Part 4, verify before reset (:629-657) | Kept, behind the fresh read below. A landed branch closes the bead and files `witness-orphan-work-landed`. An unknown verdict files the human gate `witness-branch-recovery-unknown`. An unmerged branch is left to Gas City's release. |
| Part 5, the owning-store guard and the worktree's removal (:659-713) | Kept, behind the fresh read below, with Gas Town's checks before a removal: the tree is clean, its head is its branch's head on origin, and the removal takes no `--force` (W:956-1003). `work_dir` is cleared first, so the next claimer cuts a tree on the recorded branch, as Gas Town's cleanup does (W:1012). |
| `orphan-dispose.sh` class `review` | Gas City's controller releases it to its review pool, or core's sweep resets it. |
| class `workflow-root` | No write, as today. |
| class `workflow-step` | The controller's release, which keeps the step's route, or core's sweep. A step claimed under a live alias stays with that alias. |
| class `workflow-step-dead` (a step under a closed root) | Gas City's claim path retires a workflow whose input work is terminal (`retireDoneWorkflowCandidates`, `cmd/gc/cmd_hook_claim.go`). A step left offerable under a root closed by hand is what `check-step-terminal` (I8) reports, and its result reaches the doctor record. |
| class `workflow-step-unresolved` | No write, as today. |
| class `source`: delete-source, reopen-source, the pins and `restore_route` | Gas City's release. No route is restored from `gc.execution_routed_to`. |
| The claim check, the guarded write, `witness-partial-release` | Gone, with the writes they guarded. |
| Part 6, the crash-loop rate and `witness-crash-loop` | Retires, and nothing native takes its place. Core's `spawn-storm-detect` counts a bead that comes back to the pool only while it carries `recovered` or `rejection_reason` (`internal/bootstrap/packs/core/assets/scripts/spawn-storm-detect.sh`, step 3), and neither Gas City release writes either. The witness has stamped no recovery since 2026-10-24, so the rate has had nothing to count since then. Section 12 asks Gas City to count its own releases. `recovered`, `recovered_at` and `recovered_count` register as retired. |

**What this answers.** The witness releases no claim, so it no longer reopens a
dead session's step (tk-wcdwhxm), and none of its writes can release a fresh
owner under an unchanged alias (tk-8a6akou). The evidence that the native
release already covers the generic arms: no store holds a recovery stamp later
than 2026-10-24T02:54:46Z.

**What reports a claim both releases leave.** Two doctor checks report one, and
their results reach the doctor record (section 4), but neither reads every bead
in a rig's store. Gas City's `session-model` check reports a bead assigned to a
closed, retired or missing session bead, in the city's own store only. Its
`Run` lists work from `newStore(c.cityPath)` (`cmd/gc/doctor_session_model.go`),
and `cmd/gc/cmd_doctor.go` registers it once, as a city check, with no twin
among the per-rig checks. Every rig here keeps its own store. The pack's
`check-claim-advancing` (I11) reads every rig's store from `gc rig list --json`
and reports an in-progress step whose holder is not running or names no
session, once its claim is older than 30 minutes. Nothing reports a dead claim
on a rig's other beads. One is an open bead assigned to a dead session and
routed to no pool, which the controller does not release and the sweep, reading
in-progress claims, does not reach. Another is an in-progress claim the sweep
keeps because it could not verify its holder dead, which it names in an
`order.skipped` outcome and retries. That is the loss call 2 presents. When
each rig's store was read at 2026-11-16T06:57Z, 39 of their 1,154 open and
in-progress beads named an assignee. One named `human`, a person's assignment
that core's sweep never resets, and each of the others named a live session,
by its id or its alias (`gc session list --json`). Section 12 asks Gas City for
a `session-model` that reads every store, as core's orphan sweep walks every
rig.

**What salvage still reaches.** A graph.v2 run claims its steps, not its work
bead, so a run's work bead names no owner, and a released step's next claimer
enters the recorded worktree and carries on. Salvage reaches a work bead a dead
session claimed directly, such as a rework child. Neither Gas City release
clears the bead's `gc.session_id` or `gc.session_name`. The orphan sweep's
`gc bd release-if-current` writes only the status and the assignee
(`ReleaseIfCurrent`, `internal/beads/bdstore_conditional_release.go`), and the
controller clears only the keys `SessionAffinityMetadataKeys` lists
(`internal/beadmeta/keys.go`). So a released bead still names its dead owner
until its next claim stamps a new one, and salvage reaches it while it waits in
the pool. Gas Town's witness keeps only assigned beads, and its text leaves that
case to a separate salvage scan (W:165-170).

**The fresh read.** A claim can land while the script works, so parts 4 and 5
act on what the script reads just before it acts, as Gas Town's safety gate
does (W:930-992). The script closes the bead or removes its worktree only while
no live session answers to the bead's owner and the bead's assignee is that
owner or empty. It clears `work_dir` in one write guarded by the assignee and
status it read (bd's `--if-assignee` and `--if-status`), and removes the
worktree only once that write lands. A claim that lands first fails the write,
and the worktree stays for its claimer.

## 3. The deacon

Its steps (`formulas/mol-deacon-patrol.toml`), and where each goes:

| Step | Today | After |
|---|---|---|
| check-inbox (:46-66) | Handles mail. The only pack mail that reaches it is cycle-recycle's handoff. | Retires. |
| orphan-process-cleanup (:68-85) | Finds `claude` and `node` processes with no terminal (`ps aux`) and kills those its judgment marks orphaned. | Gas City's controller ends, every tick, a process that left its agent's process group and outlived its session while carrying that session's `GC_SESSION_ID` (`sweepProcessTableOrphans`, `cmd/gc/session_beads.go`; `docs/reference/exec-session-provider.md`). It does not reach a process that carries no session id, or a leak of a live session. |
| dolt-health (:87-284) | Section 5. | Section 5. |
| system-health (:286-425) | Drives `doctor-sweep.sh` and files each non-ok result. | Section 4. |
| next-iteration (:427-486) | Waits `event_timeout`, pours the next wisp and starts it. | Retires. |

**No deacon loop remains.** Gas Town's deacon at 7f86098c04ea mails the mayor
from check-inbox, dolt-health and system-health, files warrants for the dog from
its health and queue scans, and watches the dog pool
(`gastown/formulas/mol-deacon-patrol.toml`). Every duty either addresses a seat
this city does not run or moves to an order here, so taking it would spend a
session each cycle on outcomes no one receives. A prompt with no steps would
have nothing left to judge.

**Its continuation goes with it.** The `patrol-continue.sh` Stop hook in
`overlays/cycle-recycle/` acts only for the deacon, and its reset is the restart
that killed the doctor sweep started in a handed-back turn (tk-1vdtaza). The
hook, its test, its settings entry and the deacon's sections of
`docs/patrol-continue.md` go, and so does the open gap in its failed reset
(tk-hpy4lgk). The page keeps the witness's continuation.

## 4. `gc doctor` from an exec order

No core, dolt-pack or Gas Town order runs `gc doctor`. Gas Town's deacon runs it
in a step and mails the mayor. An exec order runs its script on the
orchestrator with no agent, no LLM and no work beads (`docs/tutorials/07-orders.md`,
Formula orders vs. exec orders), under its own `timeout` (`internal/orders/order.go`).
Gas City starts each dispatched order in a goroutine of its own
(`launchDispatchOne`, `cmd/gc/order_dispatch.go`), so a long run holds up no
other order and no session. Doctor runs here took 120 seconds at
2026-11-16T03:24:53Z and 130 seconds at 04:32:04Z, and the runs the deacon
started since 2026-10-07 took 131 to 267 seconds (the initiative's note on
tk-1vdtaza).

**The order.** `orders/doctor-record.toml` runs `gctk doctor record` on the
city scope every hour, with a 30-minute timeout. The interval stays longer than
the timeout, as core's own orders keep theirs, because a cooldown counts from a
run's start (`internal/bootstrap/packs/core/orders/orphan-sweep.toml:23-27`). On the
landing order the operator said "Regular orders should be fast, with targeted
work done more asyncronously or in paths that don't impact experience when
generally slow" (sitting tk-y9h5lbd, 2026-11-15). Here the slow part is Gas
City's own run, off every agent's path, and the pack's pass writes only where a
record differs from the run.

**The record.** A failing check becomes a doctor result, a bead in gc-toolkit's
store that `gctk doctor record` alone writes. It carries `task_kind=doctor-result`,
the result's name, the rigs it names, and the latest result's message, fix hint
and details. It is held for placement at its create (`hold:mayor`), so it waits
in the po's queue, where the po places a fix, closes it as ruled, or parks it.
It takes no first reaction.

- **One record per result, per rig.** Gas City reports a per-rig check as one
  result per rig, named `rig:<rig>:<check>` or `<check>:<scope>`
  (`cmd/gc/cmd_doctor.go`), so a record keyed by the result's whole name is
  per rig. `patrol-finding.sh --check` keys by the name's last segment, which
  merges every rig's instance into one finding (conversation tk-wsgylaw). A
  pack check is one result for the whole city (`PackDoctorEntry`,
  `internal/config/config.go`), so a record also holds the rigs its result
  names: each city rig named as `rig <name>` or `rig "<name>"` in its message
  or details, the form Gas City's own details use. The pack's checks that
  report per rig name each rig that way.
- **Each run compares and writes the difference.** A measured non-ok result
  with no open record opens one, and an open record takes the result's text
  when it changes. A record still waiting in the po's queue closes, with a
  reason headed `ok:`, once a run measures its check ok. A record someone has
  placed, routed or taken is left to its owner, with one note that the check
  measures ok.
- **A result the run did not measure changes no check's record.** A check
  doctor abandoned at its per-check timeout reports `timed_out`, its outcome
  unknown (`boundedRun`, `internal/doctor/doctor.go`). When the store gate
  skips a store-reading check's scope, because its proxied store is stopped or
  its rig or city is suspended, doctor reports a stand-in under the check's own
  name, whose message starts `not checked:` and whose status is ok, or a warning
  while the controller runs (`StoreNotRunningMessage` and
  `StoreSuspendedMessage`, `internal/doctor/store_liveness.go`;
  `doctorStoreGate.checkOr`, `cmd/gc/doctor_store_gate.go`). Neither changes its
  check's record. A run with a timed-out check or a stand-in that warns opens
  or updates the record of the run itself, below, which names each of them.
- **A check the run leaves out keeps its record.** Doctor registers its checks
  conditionally, run by run (`CheckNames`, `internal/doctor/select.go`). It
  leaves out every store-dependent check when `bead-store-preflight` finds the
  store unreachable, the session checks when the session provider cannot be
  built, every check of a suspended rig or of one with no path, and most checks
  when the city's config does not load (`cmd/gc/cmd_doctor.go`). When the cause
  is a fault, doctor reports it as a failing result of its own, such as
  `bead-store-preflight` or `session-provider`, which opens its own record. A
  record whose check a run leaves out stays open, and carries the time of the
  first run that left it out until a run reports the check again.
- **Only a fact closes a record whose check is gone.** A check that Gas City or
  the pack removed looks, in a run, like one left out, so the verb never closes
  a record because its check is missing. It closes a per-rig record whose rig
  `gc rig list --json` no longer lists, with a reason headed `retired:`. The
  pack unit that deletes one of the pack's checks closes that check's records
  as retired. The po closes as retired the record of a Gas City check an
  upgrade removed. `gc doctor --check <name> --json`, run while every store
  reads and the check's rig, if it has one, is not suspended, confirms the
  removal by answering `unknown_check` with the names the city registers
  (`doctorUnknownCheckFailure`, `cmd/gc/cmd_doctor.go`). A `retired:` close
  ends the episode as an `ok:` close does.
- **A person's close rules the episode.** A record closed with any reason but
  `ok:` or `retired:` stays closed while its check keeps failing, until a result
  names a rig the record did not, which opens a new record. The first run that
  measures the check ok marks the ruled episode ended, so a later failure opens
  a new record.
- **A run that does not read keeps every record.** `gctk doctor record` runs
  `gc doctor --json` under a deadline shorter than the order's timeout. When
  doctor exits other than 0 or 1, prints JSON that does not parse, or passes the
  deadline, the verb changes no check's record and opens or updates the record
  of the run itself. A later complete run closes it: one that reads, with no
  check timed out and no stand-in that warns. A run of the verb that
  dies records `order.failed` with the tail of its output (`dispatchExec`,
  `cmd/gc/order_dispatch.go`), and the next run reads those events
  (`gc events --type order.failed`) and opens the run's record. It reads
  events because `gc order history` lists order-tracking beads
  (`cmd/gc/cmd_order.go`), and this city deletes a closed tracking bead 30
  minutes after its close (`[beads.policies.order_tracking]` in the town's
  `city.toml`), before the next run starts.
- **It fixes nothing.** The order never runs `gc doctor --fix`. A bare `--fix`
  also runs `hold-label-routed-to`'s fix, which writes a route that names no
  agent here.

Every non-ok result of a run reaches a record, its check's or the run's own,
because one Go pass with no agent turn writes them all (tk-9h0w9y5's
validation note on this member).

**The two known warnings.** `dolt-compact-state` warns on any pending-GC
marker, including the one the compactor writes on purpose when a writer races
its flatten and clears at its next pass (`internal/doctor/checks_dolt_compact_state.go`).
Its record opens and closes within that retry, with no session spent. The age
gate asked of Gas City (tk-945d0wq) waits in the operator's set-aside upstream
findings, and the record needs none. `hold-label-routed-to` warns on every
bead held with `hold:mayor` and no route, which Gas City's issue 6069 reports as
a bug. Its record is ruled once and stays closed until the check passes.

**The deacon's findings at the cutover.** 48 of the deacon's and boot health's
findings were open in this store when read, and several name checks that no
longer report, because nothing ends a finding's episode. Some name checks that
are gone: when read at 2026-11-16T06:58Z, open findings named the pack's
`check-refinery-patrol-live`, `check-routed-work-claimable`,
`check-until-resolved-owed` and `check-visit-outcome-recorded`, which the pack
has deleted, and `binary-freshness`, which neither Gas City commit cited here
carries. The cutover closes each finding that no closer is armed on. One whose
check has a doctor result names that result as its place. One whose check is
gone closes as retired, on the facts section 4 accepts: the pack's deletion of
the check, or `gc doctor --check` answering `unknown_check` under the
conditions section 4 names. Any other says the doctor order now keeps its
check, so the check's next measured failure opens a record, and a check a run
left out at the cutover is not taken for one that retired. The held findings
are left to their closers (section 11).

## 5. Dolt health and backups

Each verdict of the deacon's dolt-health step, and what raises it after:

| Deacon verdict (`mol-deacon-patrol.toml:87-284`) | Native raise | After |
|---|---|---|
| Server unreachable, `dolt-server-unreachable` | `dolt-health` fails every 30 seconds (`order.failed`), `mol-dog-doctor` escalates every five minutes, and doctor's Dolt server checks fail | The doctor record of those checks. During an outage nothing writes to the store anyway. |
| Latency over 5000 ms, nothing filed | `mol-dog-doctor` warns at 1000 ms | No pack verdict. |
| Commits over 50,000, `dolt-commit-bloat-<db>` | `mol-dog-compactor` flattens every two hours and records `order.failed` when it cannot, and doctor's `dolt-noms-size` warns on size | No pack verdict. |
| Zombie servers, killed | `gc dolt health` reports them | No pack verdict and no kill (call 3). |
| Orphan databases, `dolt-orphan-dbs` | `mol-dog-doctor`'s advisory and `mol-dog-phantom-db` | No pack verdict. |
| Backup manifest older than 12 hours, or a newer file than the manifest, `dolt-backup-<db>` | `mol-dog-doctor` dates a backup by its manifest's age at 12 hours (`examples/bd/dolt/assets/scripts/mol-dog-doctor.sh:33,91`), `mol-dog-backup` escalates a failed sync, and doctor's `bd-backup-freshness` reads `last_sync` at 24 hours | The pack's backup check, below. |

**The backup check.** The manifest's age misreads an idle store: a sync with
nothing to copy writes no manifest, so a complete backup reads stale
(tk-cpfrmai, tk-veejeg2, tk-0m719df, tk-r358gzg, tk-qdunipz). Moving the check
onto `mol-dog-doctor` keeps that false read, and its advisory dedups on the
condition word `backup`, so a second store going stale sends nothing new
(`mol-dog-doctor.sh`'s advisory signature). So the pack keeps a judge of its
own, `doctor/check-backup-current`, whose `run.sh` calls `gctk dolt unbacked`,
and the doctor order records its result per rig.

A backup holds the whole store as a sync read it, including the writes bd has
not committed. A sync first commits what bd has pending (`bd: pre-backup
commit`), then calls `DOLT_BACKUP('sync')` (beads v1.3.4:
`cmd/bd/backup_dolt.go`, `versioncontrolops.BackupSync`). Dolt saves the
calling session's working set and copies the database's root, which names each
branch's commits and its working set (`syncRemote`,
`go/libraries/doltcore/sqle/dprocedures/dolt_backup.go`; `actions.SyncRoots`,
`go/libraries/doltcore/env/actions/remotes.go`). So a backup carries the writes
this city's bd leaves uncommitted, which wait in the working set because the
city's and the gc-toolkit rig's bd configs set `dolt.auto-commit: "batch"`
(`--dolt-auto-commit`, `cmd/bd/main.go`). It carries the rows of the tables
each store keeps in `dolt_ignore` too, among them wisps and bd's `events`. On
2026-11-16 a scratch database's backup, synced and restored with this host's
dolt 2.7.3, held a row another server session wrote and never committed, and a
row of an ignored table. bd's comment that a sync carries only committed
history (`commitWorkingSetBeforeBackup`, `cmd/bd/backup_proxied_server.go`) is
not what Dolt does. The pre-backup commit decides only whether those writes are
in a commit when the backup takes them.

No file time dates what a backup lacks. A store's own `manifest` lags its
writes, which go to Dolt's chunk journal: the gc-toolkit store's was last
written at 05:34Z on 2026-11-16, while its journal took writes past 06:20Z. And
bd stamps `last_sync` when a sync returns, whether it carried a write or not
(`updateDoltBackupState`), so no sync's report enters the age.

So for each store the backup covers, the check reads the backup's working set
from the backup's own files, through Dolt's storage packages, which open a
directory of table files with no chunk journal, as a backup is
(`nbs.NewLocalStore`, `go/store/nbs/store.go`). With the working set comes the
time Dolt stamps on it at each change, which every SQL transaction sets
(`WorkingSetMeta`, `go/store/datas/workingset.go`;
`DoltTransaction.WorkingSetMeta`,
`go/libraries/doltcore/sqle/dsess/transactions.go`). In a backup it is the time
of the last change the sync carried, so every write the store made after it is
one the backup lacks. These paths are in Dolt's repository, at the version of
`github.com/dolthub/dolt/go` that Gas City's `go.mod` requires at 918f45f71.
The check reads the rest from the store's server:

- The store's working set hashes as the backup's does (`dolt_hashof_db()`):
  the backup holds every write, whatever either file's age.
- They differ: the age counts from the oldest write time the store's rows carry
  that is more than a second later than the backup's working-set time (a
  bead's `updated_at`, a dependency's, a comment's or an event's
  `created_at`), and the store is flagged once that time is older than one
  backup cadence plus its grace. Such a write counts from its own time, however
  fresh `last_sync` is. A row's own time needs no shared history, so a history
  the dolt pack's compactor flattened
  (`examples/bd/dolt/commands/compact/help.md`) changes nothing here.
- A file in the backup newer than its manifest past the grace is a torn sync,
  flagged as today.
- A backup or a working set it cannot read flags the store as unreadable, never
  healthy.

The check dates only rows timed past the second after the working-set time,
because a row timed in that second or before it can be a write the backup holds
or one it lacks. Dolt stamps the working set as a transaction commits and cuts
the time to its whole second (`time.Now().Unix()` in
`DoltTransaction.WorkingSetMeta`). bd stamps a row when its statement runs,
which is before its transaction commits. An event's `created_at` is the
statement's whole second (`NowAuxTime`,
`internal/storage/issueops/derivedid.go`). A time bd binds to a bead, such as
its `updated_at`, is rounded to the nearest second when Dolt's SQL engine
stores it in a `DATETIME` column (`ConvertToTime`, go-mysql-server
`sql/types/datetime.go`, at the version Gas City's `go.mod` requires at
918f45f71). So the last write a backup holds can read one second past its
working-set time. A write the sync missed can read any of those seconds too. A
label bd adds in the working-set time's own second, after the sync took the
root, reads that second. A write whose statement ran before the working-set
time, in a transaction that committed after the sync took the root, reads an
earlier one. Counting the rows of those seconds would date the gap from a write
the backup holds, such as an idle store's last write, and flag an idle store at
its first write after a backup.

bd writes an event row, with its own `created_at`, for each label it adds or
removes (`AddLabelInTx` and `RemoveLabelInTx`,
`internal/storage/issueops/labels.go`), so a label is dated by its event. A
missing write adds no age when it leaves no time at all, such as a bead's
removal, which takes the bead's events with it, or when no row it wrote is
timed past the second after the working-set time. A store whose only missing
writes are such writes reads current until the next sync carries them. When a
later write is missing beside them, the age counts from that write, which can
be younger than they are. A store whose syncs stop is what
`bd-backup-freshness` reports, at 24 hours.

The suspended-store backup and Dolt reclaim keep their warrants and their
orders.

## 6. The liveness census

The census retires whole: `liveness-sweep.sh`, its precheck, its recheck and its
classifier, with their tests and `orders/liveness-sweep.toml`. The triage
bucket kind (`task_kind=triage-subject`) retires with it and gets no warrant.
In the operator's words, it "is largely replaced by the Product Owner role and
the broader here is where work goes to get triaged process" (conversation
tk-2pvj50q, 2026-11-12). `standing-kinds.sh` lists only that kind, so it
retires with its readers' exclusions in `tools/gc-proactive.sh`,
`doctor/check-blocked-work-armed` and `doctor/check-hq-marooned-work`.

**What reads unnamed waits afterwards.** New work waits for placement in the
po's queue, and each exit of the work formula names where its bead went
(`specs/tk-rl8gz4b.29/native-hold-and-po.md`, section 6). What no queue holds
is one shape, a ready bead that no hold, route, assignee, arm or live run sends
anywhere, and it includes a placed bead whose run ended with the bead open. The
board lists it as a row group on each render, built by the board member
(tk-1tfzr71.24). The native-hold design allowed a doctor check here too. This
read is of work, where the two checks this design adds judge the health of
backups and sessions, as Gas City's own checks do. On a doctor check proposed
for another tendency the operator said "I feel like using doctor is an abuse of
the doctor concept, but I am also just not a fan of the doctor leverage. We use
it more than I would expect already" (sitting tk-t5f0r7, 2026-09-30). The po
queues each one with `gc bd set-state <id> hold=mayor --reason "<why>"` or
closes it. The census's reader owes this list, and the row meets each item:

- Every waiting bead is listed by title on every render, with no carried set
  and no baseline (tk-ppqwgmo).
- One reader decides both the row and any later look, so nothing re-checks it
  with rules of its own (tk-8gradm4.12).
- A bead counts as worked only while a live run works it, never by a pour's
  leftover stamp (tk-v6d9rka's note).
- A bead held with `hold:external` waits on something outside its store and is
  named as that wait, not as placement.
- Where the row points at the queue it names the po's queue read, which keeps
  every spelling of the label, not the exact listing (tk-f4f2hr1's note).
- Whether a bead waits comes from Gas City's store through `gctk bead holds` or
  its package, and the row computes no wait of its own (design tk-ssm8qns.2).

**The buckets at the cutover.** When read there were 15 open triage buckets
across the city's seven stores: one unnamed-waits bucket in each of six rig
stores, four ephemeral-subject buckets, three label-scoped buckets in one rig,
and two hand-made conversation homes in another. Seven open human gates and two
plain parking gates block them, and five open beads in one rig are parked on
the label-scoped buckets. The cutover settles each one:

- A human gate whose situation still holds is filed again on the bead it
  concerns. The rest resolve as moot, since the kind they asked about retired.
- A plain parking gate also holds beads that are not buckets, so it stays. The
  bucket's edge onto it goes.
- Each parked bead takes `hold:mayor` with its bucket's reason before its
  bucket closes, so it goes into the po's queue rather than back to the pool.
- A hand-made conversation home loses its `task_kind` and stays open as an
  ordinary bead.
- Every other bucket closes.

The ids are in this bead's notes.

## 7. Boot health, the ledger and a cold witness

**Boot health retires with the deacon it watches.** Its three files leave
`tools/deletion-plan.tsv` with this member's other rows. The reason its header
gives for filing no warrant, the dog's shutdown dance, names nothing that
exists, and the file goes rather than the reason being rewritten.

**The incident ledger retires with nothing in its place.** Its writers are the
deacon's steps and prompt, `human-gate.sh` when the deacon files a gate, and
the continue hook (`assets/scripts/gc-deacon-ledger.sh`, and its callers).
Every act it logged retires with the deacon or already has a record of its own,
such as the gate. The current ledger took 3 entries in 23 days.

**A cold witness is a doctor check.** `doctor/check-patrol-advancing`, whose
`run.sh` calls `gctk patrol cold`, reports each rig's witness whose patrol has
not advanced within a bound, and the doctor order records it per rig. It meets
what the session-liveness design owes (`specs/tk-1tfzr71.137/design.md`,
section 6):

- It judges the patrol the witness's live session runs now: the newest
  `mol-witness-patrol` wisp assigned to that session's identity, never a record
  a session left behind.
- It reports a witness that holds no patrol wisp, one whose deferred wisp never
  returns to open, and one whose session is not live.
- The record's episode ends when the check reads ok, which the next run sees
  whether or not an earlier write landed.
- It nudges nothing. The `witness-nudge` order does, so nothing leans on boot
  health's old reason for not nudging.

Gas Town's `witness-heartbeat-check` is a command its deacon runs at
7f86098c04ea and is in no release, so it is a model, read for its bound of 90
minutes on the session's last activity
(`gastown/assets/scripts/witness-heartbeat-check.sh` at packs main). The bound
here is the unit's to set from the witness's measured pass times.

**I12 after the ledger.** The ledger found its own bead by label alone. Three
readers still decide a bead by a label afterwards. `skills/external-issue` finds
an upstream finding by its `upstream-finding` label, a label-only record by
design (`lifecycle/lifecycle.toml`, the upstream-send group).
`doctor/check-hq-marooned-work` exempts a bead labeled `debt`. The board reads a
convoy's ownership from its `owned` label (`applyConvoyOwnership`,
`services/helm/internal/source/beads.go`), the label Gas City's own
`gc convoy` commands key ownership on (`cmd/gc/cmd_convoy.go`). So I12 keeps its
scoped wording (`docs/component-model.md`).

## 8. Findings, and the step text

**Which patrol findings a native order already raises.** The table in section
5 covers the deacon's Dolt keys. Of the others:

| Finding today | After |
|---|---|
| `doctor-<check>` and `doctor-sweep-failed` (deacon) | The doctor result of section 4. No Gas City order raises a doctor result. |
| `deacon-cold.<deacon>` (boot health) | Retires with the deacon. |
| `witness-crash-loop` | Retires with no native raise. `spawn-storm-detect` counts only a bead that comes back carrying `recovered` or `rejection_reason`, and neither Gas City release writes either (section 2). |
| `witness-partial-release` | Retires with the write it reported. |
| `witness-salvage-refused`, `witness-orphan-work-landed`, `witness-unplaceable-owner.<bead>`, `witness-empty-liveness-map`, `witness-candidates-unreadable` | Kept. Salvage is the witness's, and no native order reads a worktree. |
| `witness-refinery-queue-unroutable` and `-unreadable`, and the gate `witness-refinery-queue` | Kept. |
| `no-progress.<session>` | Kept, from check-polecat-health. |
| HELP and NOTICE mail findings | Kept. Mail triage is the witness's judgment. |

The native raises reach the `human` mailbox as mail, which this city's
operator does not read and the board does not show: 120 messages sat unread
there when read, among them 22 from `spawn-storm-detect` since 2026-11-11. The
board member renders them (call 5).

**The keyed problem record gets its warrant.** A patrol finding and a doctor
result are pack nouns, and neither has a warrant today. For a keyed problem
record Gas City has only `gc mail send --dedup`, which suppresses a resend
while a live message carries the key (`cmd/gc/cmd_mail.go`), and the incident
keys of core's `escalate.sh`, which throttle mail. `gc event emit` records an
event and keeps no current state per key. One entry in `docs/warrants.md`
covers both nouns and retires when Gas City ships a keyed problem record.
`patrol-finding.sh` stays the one writer of patrol findings, as shared glue
whose callers reach past the patrols.

**Step text.** Rule 2 applies to this rewrite (conversation tk-v7c6973,
2026-10-26). Each of the witness's steps calls one tested script, and each test
that extracts a block goes with its block:

| Step | Its one call | Blocks and tests that go |
|---|---|---|
| check-inbox | `gctk mail finding <mail> --key <key>`, for a NOTICE | `notice-finding`, and `bug-file`, which becomes one `gc bd create ... --labels hold:mayor` in prose; `notice-finding.test.sh`, and the notice parts of `polecat-human-gate-wiring.test.sh` and `witness-human-gate-wiring.test.sh` |
| recover-orphaned-beads | `gctk worktree salvage --rig <rig>` | every block of the step; `candidate-pipeline`, `host-bead-skip`, `downstream-court-skip`, `topology-root-skip`, `liveness-lookup`, `husk-guard`, `salvage-scope-gate`, `owning-store-guard`, `worktree-cleanup`, `recovery-stamp-gate` and `crash-loop-window` tests, about 2,300 lines |
| check-polecat-health | `gctk session progress --rig <rig>`, `seat-progress.sh` moved into gctk with a rig-wide pass | `no-progress-finding`; `witness-route.test.sh` |
| check-refinery | `gctk refinery stuck --rig <rig>` | `refinery-stuck-handoff`; its test |
| next-iteration | `gctk patrol next` | `patrol-wisp-pour`; the witness cases of `patrol-wisp-reconcile.test.sh`, `patrol-pour-vars.test.sh` and `witness-nudge.test.sh` |

The verb names follow gctk's rule for naming a verb
(`docs/gctk-architecture.md`), and each unit may derive a better word from the
verbs beside it and say so. Rule 2 asks only for one call per step, so a
step that runs a script and judges nothing could run as an order instead:
recover-orphaned-beads, check-polecat-health and check-refinery. They stay
steps, because the operator ruled the witness's target is Gas Town's witness,
whose steps they are (visit tk-dbpz6t2).

`pack-self-location.test.sh` pours `mol-witness-patrol` in a scratch city,
reads check-inbox's `SCRIPTS=$(b='kit.'; gc ...` line and sources `bd-lib.sh`
through it, so it tests that a poured step finds the pack's scripts through its
binding. A scratch city with no control-dispatcher pours only a root-only
formula, one with no `formula_compiler` requirement, and the witness's and the
deacon's are the pack's only such formulas. After the rewrite the deacon's is
gone and the witness's carries no such line, and the `gctk-bin` block names no
binding. So unit 6 gives the test a root-only formula of its own, written into
its scratch pack with that line, and the binding's resolution stays tested.

## 9. What the initiative's notes owe, and where this design answers

| Owed item (where it was noted) | Answer |
|---|---|
| The replacement asks the store whether a bead waits, through `gctk bead holds`, and computes no wait (design tk-ssm8qns.2) | Sections 2 and 6 |
| One classifier for a census and its re-check (tk-8gradm4.12) | Section 6 |
| The ledger's label read and I12 (rework tk-9dmph8i) | Section 7 |
| No new continuation that waits on the model; the witness-nudge order goes with the loop it serves (tk-r4c0g67, tk-q4tvdyo, tk-afr00th) | The witness keeps Gas Town's ending and the order (section 1). The deacon's hook goes (section 3). |
| Worked is judged by a live run (tk-v6d9rka) | Section 6 |
| No suspended-rig exception; a stale store's alarm is real except when the store is idle (tk-56m3hts, tk-cpfrmai, tk-veejeg2, tk-0m719df, tk-r358gzg, tk-qdunipz) | Section 5 |
| Import or copy, the `work_dir` layout, check-polecat-health, the side-by-side week (visit tk-dbpz6t2) | Sections 1 and 10 |
| Every waiting bead reachable by title (tk-ppqwgmo) | Section 6 |
| dolt-compact-state's designed retry (first reaction to tk-fijsqig, tk-945d0wq) | Section 4 |
| Read the default `gc session list --json`, not `--state all` (tk-1wfb7bd) | Section 2 |
| The census's test cost and its visit filters retire (tk-pgl0s8j, conversation tk-u4uo3wb) | Section 6 |
| A placed bead whose run ended; `mayor/` mail in a copy (tk-rl8gz4b.30) | Sections 6 and 1 |
| `dispatch-path.test.sh` drops the deleted readers (tk-rl8gz4b.32) | Section 10, unit 7 |
| `hold:external` is its own wait (tk-rl8gz4b.32's self-review) | Section 6 |
| One shared "is anything live behind this bead" (tk-8gradm4.7) | The census's copies retire, and the witness's live reads move into one script (section 2). Its closer checks what remains. |
| A person's hold read from the open human gate (tk-1tfzr71.37) | Section 2 |
| Run `gc doctor` where no restart reaches it, and every non-ok result reaches its record (tk-1vdtaza, tk-9h0w9y5) | Section 4 |
| No route restored from `gc.execution_routed_to`, and no route counted as an offer (dispatch design tk-1tfzr71.54) | Sections 2 and 6 |
| Name the po's queue read (tk-f4f2hr1) | Section 6 |
| Key a per-rig check per rig (conversation tk-wsgylaw) | Section 4 |
| The precheck's lost jq fallback (review tk-mpvrcme) | It retires with the precheck. |
| `branch-context.sh` moved here; the salvage push takes the refinery's lease (merge design, section 8) | Section 2 |
| Both pending-record values are an in-flight PR (tk-1tfzr71.76) | Section 2 |
| The `label:` scope defect, the 15 buckets, the bucket kind's retirement, `standing-kinds.sh` (conversation tk-2pvj50q) | Section 6 |
| Feedback patterns no longer read as unnamed (tk-ltcv43q's self-review) | Section 6 |
| Branch 2b's rule carried as `seat-progress.sh`; boot health's owed report; no stand-in for the deacon's stale-patrol warrant (tk-1tfzr71.138, tk-1tfzr71.153) | Sections 1 and 7 |
| Boot health's dance reason (the note of 2026-11-15T23:09Z) | Section 7 |
| `pack-self-location.test.sh` pours a patrol formula (tk-1tfzr71.155's self-review) | Section 8 |

The note on `GC_NO_API` (tk-rjmvj1y) was withdrawn by its correction
(tk-83dbts2), and the one on `backup-alarm-scope.sh` (tk-vqexoxe) by its own
(tk-56m3hts), so neither owes anything.

## 10. Units and cutover

**The comparison week.** Gas City's orders already run beside the patrols in
this city: core's orphan sweep, the controller's release and process sweep, and
the dolt pack's orders are all live. So the comparison needs no shadow mode.
Each unit's PR reads the week before it from the stores and the event log: what
the step it retires acted on, and what the native order did with the same
cases. A pack order or check the effort adds cannot run in the city before the
landing, so its unit's PR shows a dry run against the live city beside the
step it replaces. You rule each retirement when you approve the landing PR,
whose summary carries each unit's comparison.

Each unit lands on `integration/tk-1tfzr71.19`, keeps the suite green and leaves
the pack whole. They run in order, because they edit the same pages and the
plan. Each removes its files' rows from `tools/deletion-plan.tsv`, registers the
keys it retires as retired in `lifecycle/lifecycle.toml`, re-renders the seed
audit for what it changes, and greps again for the names it removes, since this
design listed their readers at e01b53e94. Unit 1 adds the plan's rows for the
whole files this design retires beyond the twenty already listed.

| Unit | What it does | Waits on | Releases |
|---|---|---|---|
| 1. The doctor order | `gctk doctor record`, `orders/doctor-record.toml` and the doctor result of section 4; the keyed-problem-record warrant; the pack checks that report per rig name each rig as `rig <name>`; the deacon's system-health step, `doctor-sweep.sh` and its test, and the doctor parts of `deacon-human-gate-wiring.test.sh` go, and so do `patrol-finding.sh`'s `--check`, its reserved `doctor-*` keys and their drift guard, whose one caller was that step. Its PR shows a dry run against the live city beside the deacon's open doctor findings. | nothing | the doctor's results through one pass with no session |
| 2. The backup check | `gctk dolt unbacked` and `doctor/check-backup-current`; the backup-currency warrant; gctk's build gains Dolt's Go module, which Gas City's own build carries; the deacon's dolt-health step and `dolt-backup-manifest-check.test.sh` go. Its PR shows the check's dry run beside the deacon's backup findings of the week, and the working-set hash and time it reads from the smallest backup's files beside `dolt_hashof_db()`, with that backup restored into a scratch directory (`dolt backup restore`) to show that no row it holds is timed more than a second past that working-set time. | unit 1 | the closers of the five backup beads, once the landing closes |
| 3. The cold-patrol check | `gctk patrol cold` and `doctor/check-patrol-advancing`; the patrol-liveness warrant. | unit 2 | a report of a cold witness |
| 4. The deacon retires | `agents/deacon/`, its named session and the pack's patch for it, `formulas/mol-deacon-patrol.toml`, boot health's three files, `gc-deacon-ledger.sh` and its test, the continue hook with its test and settings entry, `human-gate.sh`'s ledger append, `check-hq-marooned-work`'s ledger exemption, the deacon and boot health in `patrol-finding.sh`'s caller list, the deacon's tests and the pages that name them, among them `docs/pack-authoring.md`'s patrol startup section (tk-a89659h). | unit 3 | the deacon's session, and tk-hpy4lgk's closer |
| 5. The witness's recovery | recover-orphaned-beads calls `gctk worktree salvage`, which acts on section 2's fresh read, check-polecat-health calls `gctk session progress`, and `orphan-dispose.sh`, `branch-context.sh`, `seat-progress.sh` with their tests and the step's extraction tests go. | unit 4 | the closers of tk-wcdwhxm and tk-8a6akou |
| 6. The witness's other steps | check-inbox, check-refinery and next-iteration each call one script, as section 8 says, and the formula reads as Gas Town's at 7f86098c04ea with section 1's differences. `pack-self-location.test.sh` pours a root-only formula of its own (section 8). | unit 5 | step text with no procedure |
| 7. The census retires | the census's eight files and its order, `standing-kinds.sh` with its test and its readers' exclusions, the reader lists of `dispatch-path.test.sh` and `run-lib.test.sh`, `skills/converse-prep`'s re-check, the witness prompt's line about the sweep, and the pages and registry entries that name the census or the bucket kind. It brings the branch current with main first, so #1531's edit of `liveness-sweep.sh` arrives before the deletion. | unit 6 | the closers of tk-1erda9g, tk-ppqwgmo and tk-8gradm4.12, and the board's row (tk-1tfzr71.24) |

**The town changes, one on each side of the landing.** The mechanik makes
both. The town's `city.toml` patches the deacon's provider, and Gas City
refuses a config whose patch names an agent that does not exist
(`ApplyPatches`, `internal/config/patch.go`), so that patch must leave the town
before the landing reaches the city. Without it the deacon runs on the city's
default provider, the work tier, so the patch leaves once the landing PR is
approved and just before it merges, and the landing bead waits on that change.
The town's four `[[orders.overrides]]` entries for `liveness-sweep` hold the
census to a 24-hour window, where its own is six hours. They leave after the
landing, because Gas City only logs an override whose order is gone
(`OnOverrideError`, `cmd/gc/order_dispatch.go`), and taking them out earlier
would let the census run up to four times as often until the landing.

**The cutover, after the landing.** The landing reaches the city through the
rig checkout's reconcile. Then a cutover bead, armed on the landing:

1. Burns the deacon's open patrol wisps. Gas City keeps an orphaned template's
   session running while it holds work, and closes it once the work is gone.
2. Settles the triage buckets as section 6 says.
3. Closes the deacon's and boot health's open findings that no closer is armed
   on, as section 4 says.

## 11. Edges and notes the implementation child adds

The implementation child (tk-1tfzr71.159) files the seven units under the
epic tk-1tfzr71 with `target=integration/tk-1tfzr71.19` in each create, each
blocked by the unit before it and armed to dispatch when that closes. The
landing bead (tk-1tfzr71.19) and the summary task (tk-1tfzr71.160) wait on every
unit. It files the two town changes for the mechanik: the landing bead waits on
the first, and the second waits on the landing bead. It files the cutover bead,
which also waits on the landing bead. It surveys the open
branches against each unit's files before it files, since they move.

The problems held on this member, and what each closer checks once the
landing closes:

| Held bead | What the retirement removes | What its closer checks |
|---|---|---|
| tk-wcdwhxm, tk-8a6akou | `orphan-dispose.sh` and the witness's release of a dead session's claims | No pack script writes a step's status, route or assignee it does not hold. |
| tk-1vdtaza | the deacon's sweep and its restart | The doctor order's runs complete, and every non-ok result has its record. |
| tk-2lor8sg, tk-ujz8d10 | the deacon's doctor findings | The check's result, if it still fails, has a doctor result record. |
| tk-cpfrmai, tk-veejeg2, tk-0m719df, tk-r358gzg, tk-qdunipz | the manifest-age judge | An idle store's backup reads current in `check-backup-current`. |
| tk-1erda9g, tk-ppqwgmo, tk-8gradm4.12 | the census | Nothing files a census gate. |
| tk-8gradm4.7 | the census's copies of the live-behind check | Which readers remain, and whether they share one rule. |
| tk-a89659h | the deacon and boot health | `docs/pack-authoring.md` names no boot agent and no shared startup fragment. |

It appends a note to each bead below:

- **tk-hpy4lgk.** A close brief, a `blocks` edge onto tk-1tfzr71.19 and the
  validating closer's arm, under AGENTS.md's rule for code the plan retires:
  the deacon's failed reset retires with the deacon.
- **tk-1tfzr71.24.** The board's two reads from section 6 and call 5: the row of
  ready beads no queue holds, with the owed list, and the render of the
  `human` mailbox's mail from Gas City's orders.
- **tk-1tfzr71.25.** The keys this member registers as retired: `recovered`,
  `recovered_at`, `recovered_count`, the `triage.*` keys, the `triage-subject`
  kind and the ledger's label.
- **tk-945d0wq.** The doctor record lets the compactor's retry marker open and
  close with no session spent.

## 12. Gas City facts, the upstream asks, and the search

The city runs gc 1.4.3, built on 2026-11-12 from the fork at 6589a7df45. Its
cached core and dolt packs match upstream main byte for byte in
`orphan-sweep.toml`, `orphan-sweep.sh` and `mol-dog-doctor.sh`. Its
`spawn-storm-detect.sh` is the fork's, which differs from upstream's in one
line that reads a missing bead and counts the same way. Many of the Gas City
files this record cites
differ between the fork build and upstream main, among them
`cmd/gc/pool_session_name.go`, `cmd/gc/cmd_hook_claim.go`,
`cmd/gc/order_dispatch.go`, `internal/config/config.go` and
`cmd/gc/cmd_doctor.go`. One cited rule is not in the fork build:
`agents_exclude` entered upstream at 6e283f4820 (2026-11-12, #6268), after it.
Every other symbol and rule this record cites is present in both, among them
the release's human-label skip and pool test, the keys each release clears, the
workflow retire at claim, the session-model findings and the one store that
check reads, the override log, the patch refusal, the doctor result's fields,
the store gate's stand-ins, a timed-out check's `timed_out`, the
`unknown_check` answer to `--check`, the goroutine each dispatch runs in, the
`order.failed` event and the tracking beads `gc order history` reads.

These asks stay proposed. Posting them is your decision, and none is sent.

1. **A backup judge of what the backup holds.** `mol-dog-doctor` and
   `bd-backup-freshness` judge a file's age or a sync's return, so an idle
   store reads stale. A judge that compares a backup's working set with its
   store's would retire `check-backup-current`.
2. **`mol-dog-doctor`'s advisory keyed per database.** Its dedup on the
   condition word hides a second store going stale.
3. **A keyed problem record.** It would retire the patrol finding and the
   doctor result.
4. **A report of a named session whose work stops advancing.** The work ladder
   governs pool seats only. It would retire `check-patrol-advancing`.
5. **`spawn-storm-detect` counts Gas City's own releases.** It counts a bead
   that comes back to the pool only by `recovered` or `rejection_reason`, which
   neither the controller's release nor the orphan sweep writes, so a bead that
   keeps killing the sessions that take it raises nothing.
6. **`session-model` reads every store.** It lists work only from the city's
   store, so a dead claim both releases leave in a rig's store is reported only
   when it is a step in progress, which the pack's `check-claim-advancing`
   reads.

The search behind each surface this design adds is in
[gas-city-search.md](gas-city-search.md).
