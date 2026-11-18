---
name: Design — the patrols move onto orders, with a witness woken only for mail
description: The design record for tk-1tfzr71.158, the design child of initiative tk-1tfzr71.19, on the witness's scripted jobs becoming orders that look and orders that act, a witness that runs only for its mail, doctor's results and Gas City's alerts on the board, and the retirement of the deacon, boot health, the incident ledger and the liveness census. Use it to approve the design at its gate, or to build one of the units it defines.
---

# Design: the patrols move onto orders, with a witness woken only for mail

This is the design record for tk-1tfzr71.158, the design child of the
initiative tk-1tfzr71.19. The operator sent its first version back for four
changes in conversation tk-9l9pg0x on 2026-11-16, and this version makes them.
The pack was read at e01b53e94, the commit `integration/tk-1tfzr71.19` was cut
from, and every pack line number is at that commit. Main has since moved to
8b9c4caf3, and of the files this design retires it has changed only
`liveness-sweep.sh` and its test, by twelve lines (#1531). Gas City is cited
by symbol at upstream main c7eb6d2f43, and section 14 names where the city's
gc build differs. Gas Town is cited at two gascity-packs commits: 66897e7132c9,
which Gas City's `go.mod` pins and which is gastown 0.1.13, and 7f86098c04ea,
which the pack's refinery copy follows. `W:` cites
`gastown/formulas/mol-witness-patrol.toml` at 7f86098c04ea. The stores, the
`human` mailbox and the event log were read on 2026-11-16, at the times each
section names. This repository is public, so the ids of beads in other stores
are in this bead's notes, not here.

## What the operator approves

Today a witness session in each rig runs a patrol loop every hour, and the
city's deacon session runs one that drives `gc doctor`, judges Dolt and its
backups, and kills stray processes. Boot health watches the deacon, and the
liveness census files questions about work nothing names. Gas City's own orders
already release a dead session's claims, end the processes a closed session
left behind and watch the Dolt server and its backups, and they mail their
alerts to the `human` mailbox, which nothing shows. The PR as first written
kept the witness's loop, put each failing doctor check in the Product Owner's
queue as a record, and added two pack doctor checks. Approving this version
makes the changes below, and it adds no mayor.

1. **The witness's three scripted jobs become orders.** Today the witness runs
   them in its loop: saving a dead polecat's work, checking a pool seat that
   prints but makes no progress, and checking the refinery's queue. Each
   becomes an order that only reads and records an event when it finds
   something, and a second order that acts on that event after reading each
   item again: it pushes, closes, removes a worktree, or files the finding or
   human gate (section 2). Cost: seven orders join the city's dispatch ring,
   and an order that cannot read shows on the board only once it has failed
   three runs in a row and two doctor runs have found that, where the loop
   filed a finding at once.
2. **The witness runs only to read its mail.** Today its session is always on.
   It becomes an on-demand session, as the refinery and the Product Owner are,
   and every mail to it carries `--notify`, which asks Gas City to wake it. Its
   patrol formula, the hourly next-iteration and the witness-nudge order go
   (section 1). Cost: a mail whose wake does not land waits until the next mail
   sent with `--notify`, whose turn reads every unread mail.
3. **The deacon retires, with boot health, the incident ledger and its
   continue hook.** `gc doctor` moves to an order, Dolt and its backups to Gas
   City's orders, and stray processes to the controller (section 4). Cost: no
   session kills a stray process the controller does not reach, or a zombie
   Dolt server. The ledger records neither since 2026-10-09.
4. **Doctor's results show on the board, and nothing enters the Product
   Owner's queue.** An order runs `gc doctor` each hour and records the run as
   one Gas City event. The board shows each check that two runs in a row found
   failing, since when, when doctor last ran, and each monitor order's last good
   run. A warning you accept is listed in a reviewed file in this repository,
   and approving this design accepts two entries: `hold-label-routed-to`, which
   warns on a Gas City bug, and `dolt-compact-state` for its first three hours,
   the time the compactor takes to clear its own retry marker (section 5).
   Cost: a doctor failure waits until you look at the board, where the deacon
   filed it for a first reaction within minutes.
5. **Gas City's alerts show on the board once the false ones are fixed at
   their cause.** All 24 spawn-storm alerts since 2026-11-11 were false, because
   each rework the pack files carries `rejection_reason`, the key Gas City's
   detector reads as a bead sent back to the pool. A rework carries a key of
   the pack's own instead. Three of the four scripts that file a rework retire
   with the old review path (tk-1tfzr71.122), the GitHub intake
   (tk-1tfzr71.21) and the old merge path (tk-1tfzr71.70), so the key change
   waits for all three, and the board's inbox lands after it. The dolt pack's
   backup advisory is false on an idle store as well, and only Gas City can
   change its rule, so the inbox also waits on a human gate that you clear once
   that fix reaches the city, or once you rule that the inbox shows the
   advisory. Its cutover archives the old mail whose matter has ended
   (section 6). Cost: until then the board shows no inbox, as today.
6. **The backup check and the patrol-advancing check are dropped.** Gas City's
   `bd-backup-freshness` check and `mol-dog-backup` order judge backups, and no
   patrol loop is left to watch (section 7). Cost: nothing notices a sync that
   returns without carrying the store's writes.
7. **The liveness census retires** with its triage bucket kind, as you ruled
   (conversation tk-2pvj50q), and the board member (tk-1tfzr71.24) takes its
   one read (section 8). Cost: between the census's retirement and that row,
   nothing lists ready work that no queue holds.
8. **The work lands twice, a week apart.** The first landing adds what only
   reads or shows: the doctor order, the three orders that look and the
   board's page. They run beside the witness's loop and the deacon for a week,
   and a report compares what each found. The second landing adds the orders
   that act and retires the loop, the deacon and the census, and its summary
   carries that comparison (section 12). Cost: the old patrols run a week
   longer than one landing would keep them.

Approving the design as it stands ships each of these. Section 11 maps every
item the initiative's notes owe, and section 13 the problems held on this
member.

## 1. The witness, woken for its mail

**What it was.** The witness is the pack's copy of Gas Town's witness, taken at
7f86098c04ea, the commit the refinery's copy follows (visit tk-dbpz6t2,
2026-10-31). At the pin, Gas Town's salvage reads `metadata.worktree`
(gastown 0.1.13, `mol-witness-patrol.toml:270-272`), a key no polecat writes,
and at 7f86098c04ea it reads `artifact_dir` and accepts our `work_dir` layout
(W:324-407). Its loop runs check-inbox, recover-orphaned-beads, check-refinery
and next-iteration (`formulas/mol-witness-patrol.toml`), and the copy's own
recover-orphaned-beads checks a live owner's seat in its branch 2b (:483-499).
Gas Town's witness and deacon formulas are byte-identical at 7f86098c04ea and
at packs main 0f07496d2fa4.

**What it becomes.** Of those steps only check-inbox judges anything. The
others run a script and decide nothing a script cannot, and the operator ruled
that they run as orders (conversation tk-9l9pg0x, section 2), on the view they
gave there: "Have deterministic code do deterministic work, although decisions
still go to LLMs". So the
witness keeps mail triage alone, which is what the initiative's contract keeps
as prompt doctrine, and it needs no loop:

- **Its mode.** The witness's named session moves from `mode = "always"` to
  `mode = "on_demand"` (`pack.toml`), as the refinery's and the Product
  Owner's already are. Its idle timeout puts it to sleep, as theirs does.
- **What wakes it.** `gc mail send --notify` requests a recipient turn and, in
  a managed city, a wake for a recipient that is not running. Mail without it
  requests no wake: "Unread mail alone does not request a wake"
  (`newMailSendCmd`'s help, `cmd/gc/cmd_mail.go`). The notice is recorded with
  the policy `WakeIfNeeded` (`mailNotifyOpPolicy`, `cmd/gc/cmd_nudge.go`). The
  city's gc 1.4.3 prints the same help, and its managed wake needs the
  recipient to resolve to a session bead, which a named on-demand session keeps
  while it sleeps: the city's on-demand refinery sessions kept theirs for 4 to
  77 days when read on 2026-11-16.
- **Who sends it mail.** Every instruction that mails the witness adds
  `--notify`: the HELP block in `template-fragments/polecat-doctrine.template.md`
  and in `agents/proactive/prompt.template.md`, the work formula's NOTICE line
  and its load-context text (`formulas/mol-polecat-work.toml`), the text
  `assets/scripts/converse-entry.sh` and `assets/scripts/store-only-exit.sh`
  print, the converse prompt's lines for an unreadable claim and a refused
  acknowledgement (`agents/_converse/prompt.template.md`), and the work
  skill's block that mails a patrol (`skills/work/SKILL.md`), which also stops
  saying that a patrol reads its mail every cycle. The unit greps for every
  other sender again. `--notify` asks for a turn "even with earlier unread
  mail", so a wake that did not land is made up by the next one, and that turn
  reads every unread mail.
- **Its prompt.** check-inbox's doctrine moves into the witness's prompt: HELP
  triage, a NOTICE filed as a finding through one call (`gctk mail finding`),
  and a defect filed as a bead held for placement. The prompt says nothing of
  a patrol, salvage or the refinery, and its nudge reads "Run gc prime, then
  read your mail" (`agents/witness/agent.toml`).
- **What goes.** `formulas/mol-witness-patrol.toml` whole, so next-iteration,
  the startup wisp reconcile and the `patrol-wisp-pour` block go with it, and
  so do `orders/witness-nudge.toml` and `assets/scripts/witness-nudge.sh`,
  which prompt a loop that no longer exists. `gctk patrol next`, which the first
  version proposed for next-iteration, is not built.

**Whether a rig needs a witness session at all.** It does, and only while it
has mail. A HELP mail asks a question about a bead the asker holds, and the
answer needs an agent that can read the rig's tree and its branches, which the
witness's rig worktree gives it. A city-wide reader would need every rig's tree
and would change every polecat's address. A session that runs only when mail
wakes it costs nothing between mails: the store held 19 mails to the city's
witnesses, all sent from 2026-11-10 to 11-16, 2 of them HELP and 9 of them to
this rig's.

**Its differences from Gas Town's witness.** Each names its reason and what
ends it, under visit tk-dbpz6t2's rule:

| Difference | Reason | Ends when |
|---|---|---|
| It runs no patrol loop: mail wakes it, and its scripted steps run as orders that look and orders that act (section 2). | The operator's ruling in conversation tk-9l9pg0x: code does the work that needs no judgment. | Gas Town's witness runs its scripted steps outside its session. |
| It files findings and human gates where Gas Town mails the mayor. | The ruling at tk-rl8gz4b.29's design, and this city runs no mayor. | An operator ruling gives escalation to a seat. |
| Recovery returns nothing to the pool. Gas Town's reopens the bead with `gc workflow delete-source` and `reopen-source` (W:1019). | Gas City's controller and core's orphan sweep release a dead claim within minutes, and a second writer raced them (tk-8a6akou). | Gas Town's witness leaves the release to them, as the orphan sweep's header assumes. |
| Salvage keeps `work_dir`, and clears it only with the worktree it names. | Our polecats resume from `work_dir`. | The work formula records Gas Town's `artifact_dir`. |
| A finding, not a warrant, names a pool seat that prints while its work stands still, judged by the seat's own writes. | The controller's work ladder recovers a quiet seat, and no dog serves a warrant here. | Gas City paces a busy pool seat by its progress. |
| Salvage reads our anchors, PR states and conversations, and takes both pending-record values as an in-flight PR. | Our pipeline writes them. | The retirements of the old merge path (tk-1tfzr71.70) and the old review path (tk-1tfzr71.122) land. |
| The refinery's queue check does not wake the refinery for a stale `pr_reconcile_pending` check (W:1080-1108). | The landing order runs the pending record with no refinery turn. | No end is planned. |

The first version's rows for next-iteration's spacing, the nudge order and the
deacon's heartbeat check end here, with the loop they served.

**Why a copy, not an import.** An import of Gas Town's pack on each rig brings
its witness, refinery and polecat (`gastown/pack.toml:13-15`), Gas City's
`agents_exclude` removes named templates from an import edge
(`Import.AgentsExclude`, `internal/config/config.go`), and the import cannot
change step text. Gas Town's text at 7f86098c04ea loops, keeps only assigned
beads and maps liveness from sessions (W:157-232), so a conversation's task
reads as orphaned and goes back to the pool (W:1019). It moves a legacy
`work_dir` to `artifact_dir` (W:462, W:1012), mails `mayor/` for every
escalation (W:115, W:290, W:773, W:1041, W:1123) and files warrants for the dog
(W:1183), which the session-liveness member retired.

## 2. The patrol orders: one looks, another acts

Each of the witness's three scripted jobs becomes two exec orders. An order
that looks runs on a cooldown, reads, and writes nothing to any store. When it
finds something, it records one event naming what it found, with
`gc event emit` ("Record a custom event to the city event log",
`cmd/gc/cmd_event_emit.go`). An order that acts has `trigger = "event"` on that
type, so it runs only after a look found something. Gas City tells an exec
order nothing of the event that fired it: its environment carries the pack,
rig and store variables and the outcome file only (`orderExecEnvWithError`,
`cmd/gc/order_store.go`). So the act reads its items again, through the same
reader as the look, and acts on what it reads then. One gctk verb holds both
halves of each job: run plain, it looks, and with `--act` it acts, so one rule
decides both and a run without the flag writes nothing.

| Order | Trigger | Runs | Budget | Reads | Writes |
|---|---|---|---|---|---|
| `orphan-work-detect` | every 15 minutes | `gctk worktree salvage` | 2 minutes | each rig's beads that name an owner, and `gc session list --json` | the event `gc-toolkit.orphan-work.found`, listing each bead whose owner no live session answers to |
| `orphan-work-salvage` | that event | `gctk worktree salvage --act` | 15 minutes | the same beads, then each bead, its tree and its branch on origin just before acting | a push, a close of a bead whose branch landed, a tree's removal, a `work_dir` cleared, and the findings and gate of section 10 |
| `seat-progress-detect` | every 30 minutes | `gctk session progress` | 2 minutes | each live pool seat's claim, whether its pane prints, and its writes to the stores | the event `gc-toolkit.seat-progress.stalled` |
| `seat-progress-report` | that event | `gctk session progress --act` | 2 minutes | the same seats again | the finding `no-progress.<session>` |
| `refinery-queue-detect` | every 30 minutes | `gctk refinery stuck` | 2 minutes | each rig's refinery address and the handoffs assigned to it | the event `gc-toolkit.refinery-queue.stuck` |
| `refinery-queue-report` | that event | `gctk refinery stuck --act` | 2 minutes | the same handoffs again | the human gate `witness-refinery-queue` |

The doctor order of section 5 is the seventh. The names follow gctk's rule for
naming a verb (`docs/gctk-architecture.md`), and each unit may derive a better
word from the verbs and orders beside it and say so.

**Scope and the dispatch ring.** Each order is city-scoped and walks every rig
that `gc rig list --json` lists, as core's orphan sweep does. Gas City starts
at most four cooldown, cron and event orders per 30-second pass
(`docs/tutorials/07-orders.md`), and its `order-dispatch-floor` check flags an
order whose interval is shorter than that ring's worst case. When run on
2026-11-16 at 18:21Z it reported "31 order(s) set to fire more often than the
9m30s dispatch floor (73 orders in the ring, 4 dispatched per 30s pass)". The
seven orders join the ring and `boot-health` and `witness-nudge` leave it,
which puts the floor at 10 minutes, under each new cadence. An order per rig
would add 37 to the ring, six for each of the six rigs and the doctor order.

**The cadences and budgets.** A cooldown counts from a run's start, so each
interval stays longer than its order's timeout, as core's own orders keep
theirs. Salvage looks every 15 minutes because Gas City's orphan sweep releases
a dead claim within five, and the seat and queue checks look every 30 minutes
because they judge three hours of silence and a handoff's age. A look reads one
list per rig and the session list once. The salvage act's 15 minutes cover a
push per bead it saves. The witness's loop ran each of them once an hour.

**An event fires the act at least once.** Gas City's event orders keep a
cursor, and one event can still fire twice, so "make an event order's action
safe to repeat for the same bead" (`docs/tutorials/07-orders.md`, event).
Every act here is: a push of a branch already on origin moves nothing, a
closed bead refuses a second close, a removed tree is not found, and a finding
or gate is filed once per open key. An event lost to the recorder's
best-effort write is made up by the next look, which finds the same thing
while it holds. A look that finds a bead the act refused, such as a tree git
will not remove, records it again each run, and the act's refusal finding,
open under one key, is its one record.

**A look that cannot read fails its run.** Where the loop filed
`witness-candidates-unreadable`, `witness-empty-liveness-map`,
`witness-refinery-queue-unreadable` or `witness-refinery-queue-unroutable`,
the look exits non-zero. Gas City records `order.failed` with the tail of its
output (`tailForOrderFailureEvent`, `cmd/gc/order_dispatch.go`), and its
`order-outcome-healthy` check warns once an order fails three runs in a row
(`orderOutcomeFailureThreshold`, `internal/doctor/checks_order_outcome.go`),
which reaches the board through section 5.

**What runs the act, and what guards it.** Gas City's order dispatcher runs
it. Before it dispatches an order it skips one whose previous run's tracking
bead is still open (`docs/tutorials/07-orders.md`, Duplicate prevention), but
its watchdog closes an open tracking bead two minutes old
(`orderTrackingSweepWatchdogStaleAfter`, `cmd/gc/order_dispatch.go`), so a run
longer than that can overlap the next one. Each act is therefore safe to run
twice at once: every write it makes is guarded or changes nothing the second
time, except that two runs in the same instant can each file a finding (below).
This area's incidents came from a script that judged liveness from
state that moved under it. The witness released a step that a fresh session had
taken under the dead one's alias (tk-8a6akou), and the scratch reaper deleted
temp directories a live build still used (#1528). The salvage act's guards
answer that:

- It releases no claim, so no write of its can free a fresh owner's step.
- It judges an owner dead by the session id and the alias together, from a
  `gc session list --json` it reads just before each bead, and acts only while
  no live session answers to either and the bead's assignee is that owner or
  empty (section 3, the fresh read).
- Its writes to a bead are bd's conditional updates (`--if-assignee`,
  `--if-status`), which write nothing once a claim has moved the bead.
- It removes a tree only through git with no `--force`, and only when the
  tree is clean and its head is its branch's head on origin, so git refuses a
  tree holding any change. It deletes no branch.
- Its push takes the refinery's lease (`branch-push.sh`), so a push never
  replaces a commit it did not read.

The seat and queue acts only file a finding or a gate, under the key the
look's reader derives. `patrol-finding.sh` and `human-gate.sh` file nothing
while one is open under that key, though two runs in the same instant can each
file one, because bd keeps no idempotency at create.

## 3. Orphan recovery

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
| Part 1, the candidates: beads naming an owner (`gc.session_id`, then the assignee, then `gc.session_name`), less an in-flight PR, a human route, a conversation and a topology root (:185-278) | The salvage reader, which the look and the act share. A person's hold is read from the open human gate that blocks the bead, not from `gc.routed_to=human`, which the dispatch member cleared from every store. Both pending-record values stay an in-flight PR. |
| Part 2, the liveness map and its fail safe (:354-481) | The salvage reader, from `gc session list --json`, which lists every session that has not closed. A map that does not load fails the run (section 2). |
| Part 2b, a live owner's seat (:483-499) | The seat-progress orders. |
| Part 3, salvage through `branch-context.sh` (:501-627) | The salvage act. `branch-context.sh` retires: the act checks that the bead's `work_dir` shares the rig root's git common directory, as Gas Town's does, and refuses a salvage that does not. The push keeps the refinery's lease (`branch-push.sh`). |
| Part 4, verify before reset (:629-657) | The salvage act, behind the fresh read below. A landed branch closes the bead and files `witness-orphan-work-landed`. An unknown verdict files the human gate `witness-branch-recovery-unknown`. An unmerged branch is left to Gas City's release. |
| Part 5, the owning-store guard and the worktree's removal (:659-713) | The salvage act, behind the fresh read below, with Gas Town's checks before a removal: the tree is clean, its head is its branch's head on origin, and the removal takes no `--force` (W:956-1007). `work_dir` is cleared once the tree is gone, so the next claimer cuts a tree on the recorded branch. Gas Town's cleanup takes the same order: it removes the tree, keeps the bead as it is when git refuses (W:1001-1007), and unsets `work_dir` only after the removal (W:1009-1016). |
| `orphan-dispose.sh` class `review` | Gas City's controller releases it to its review pool, or core's sweep resets it. |
| class `workflow-root` | No write, as today. |
| class `workflow-step` | The controller's release, which keeps the step's route, or core's sweep. A step claimed under a live alias stays with that alias. |
| class `workflow-step-dead` (a step under a closed root) | Gas City's claim path retires a workflow whose input work is terminal (`retireDoneWorkflowCandidates`, `cmd/gc/cmd_hook_claim.go`). A step left offerable under a root closed by hand is what `check-step-terminal` (I8) reports, and its result reaches the board through section 5. |
| class `workflow-step-unresolved` | No write, as today. |
| class `source`: delete-source, reopen-source, the pins and `restore_route` | Gas City's release. No route is restored from `gc.execution_routed_to`. |
| The claim check, the guarded write, `witness-partial-release` | Gone, with the writes they guarded. |
| Part 6, the crash-loop rate and `witness-crash-loop` | Retires, and nothing native takes its place. Core's `spawn-storm-detect` counts a bead in the pool only while it carries `recovered` or `rejection_reason` (`internal/bootstrap/packs/core/assets/scripts/spawn-storm-detect.sh`, step 3), and neither Gas City release writes either. The witness has stamped no recovery since 2026-10-24, so the rate has had nothing to count since then. Section 14 asks Gas City to count its own releases. `recovered`, `recovered_at` and `recovered_count` register as retired. |

**What this answers.** No pack order releases a claim, so nothing reopens a
dead session's step (tk-wcdwhxm), and no pack write can release a fresh owner
under an unchanged alias (tk-8a6akou). The evidence that the native release
already covers the generic arms: no store holds a recovery stamp later than
2026-10-24T02:54:46Z.

**What reports a claim both releases leave.** Two doctor checks report one,
and their results reach the board (section 5), but neither reads every bead
in a rig's store. Gas City's `session-model` check reports a bead assigned to a
closed, retired or missing session bead, in the city's own store only: its
`Run` lists work from `c.newStore(c.cityPath)`
(`cmd/gc/doctor_session_model.go`), and `cmd/gc/cmd_doctor.go` registers it
once, as a city check. Every rig here keeps its own store. The pack's
`check-claim-advancing` (I11) reads every rig's store from `gc rig list --json`
and reports an in-progress step whose holder is not running or names no
session, once its claim is older than 30 minutes. Nothing reports a dead claim
on a rig's other beads, such as an open bead assigned to a dead session and
routed to no pool, which the controller does not release and the sweep, reading
in-progress claims, does not reach. When each rig's store was read at
2026-11-16T06:57Z, 39 of their 1,154 open and in-progress beads named an
assignee: one named `human`, and each of the others named a live session.
Section 14 asks Gas City for a `session-model` that reads every store.

**What salvage still reaches.** A graph.v2 run claims its steps, not its work
bead, so a run's work bead names no owner, and a released step's next claimer
enters the recorded worktree and carries on. Salvage reaches a work bead a dead
session claimed directly, such as a rework child. Neither Gas City release
clears the bead's `gc.session_id` or `gc.session_name`: the orphan sweep's
`gc bd release-if-current` writes only the status and the assignee
(`ReleaseIfCurrent`, `internal/beads/bdstore_conditional_release.go`), and the
controller clears only the keys `SessionAffinityMetadataKeys` lists
(`internal/beadmeta/keys.go`). So a released bead still names its dead owner
until its next claim stamps a new one, and salvage reaches it while it waits in
the pool. Gas Town's witness keeps only assigned beads, and its text leaves
that case to a separate salvage scan (W:165-170).

**The fresh read.** A claim can land between the look and the act, and while
the act works, so the act closes a bead or removes its worktree only on what it
reads just before it acts, as Gas Town's safety gate does (W:930-992): no live
session answers to the bead's owner, and the bead's assignee is that owner or
empty. It removes the worktree first, in the order Gas Town's cleanup and
`work-submit.sh` take, and then clears `work_dir` in one write guarded by the
assignee and status it read. When git refuses the removal, the tree and
`work_dir` both stay, so the next claimer enters the recorded tree and the next
look finds the bead again.

Two cases leave `work_dir` naming a tree that is gone. In one, the act stops
between the removal and the write. In the other, a claim lands between the
fresh read and the removal, git removes the tree, and the guarded write then
fails. That claimer loses no work: git removes only a clean tree, so a tracked
or untracked change makes it refuse, and the act deletes no branch, so a commit
the claimer made stays on the local branch. What a gone tree costs a claimer
depends on the script its next step runs. `work-setup.sh` cuts a fresh tree in
its place, and `work-enter.sh` stops on the missing path, so that run goes no
further until the bead has a tree again. A later act that reaches the bead
finds no tree at that path and clears `work_dir` in the same guarded write.

## 4. The deacon

Its steps (`formulas/mol-deacon-patrol.toml`), and where each goes:

| Step | Today | After |
|---|---|---|
| check-inbox (:46-66) | Handles mail. The only pack mail that reaches it is cycle-recycle's handoff. | Retires. |
| orphan-process-cleanup (:68-85) | Finds `claude` and `node` processes with no terminal (`ps aux`) and kills those its judgment marks orphaned. | Gas City's controller ends, every tick, a process that left its agent's process group and outlived its session while carrying that session's `GC_SESSION_ID` (`sweepProcessTableOrphans`, `cmd/gc/session_beads.go`). It does not reach a process that carries no session id, or a leak of a live session. |
| dolt-health (:87-284) | Section 7. | Section 7. |
| system-health (:286-425) | Drives `doctor-sweep.sh` and files each non-ok result. | Section 5. |
| next-iteration (:427-486) | Waits `event_timeout`, pours the next wisp and starts it. | Retires. |

**No deacon loop remains.** Gas Town's deacon at 7f86098c04ea mails the mayor
from check-inbox, dolt-health and system-health, files warrants for the dog
from its health and queue scans, and watches the dog pool
(`gastown/formulas/mol-deacon-patrol.toml`). Every duty either addresses a seat
this city does not run or moves to an order here, so taking it would spend a
session each cycle on outcomes no one receives.

**Its continuation goes with it.** The `patrol-continue.sh` Stop hook in
`overlays/cycle-recycle/` acts only for the deacon, and its reset is the restart
that killed the doctor sweep started in a handed-back turn (tk-1vdtaza). The
hook, its test, its settings entry and the deacon's sections of
`docs/patrol-continue.md` go, and so does the open gap in its failed reset
(tk-hpy4lgk). The witness keeps the overlay's context recycle.

## 5. Doctor on the board

No core, dolt-pack or Gas Town order runs `gc doctor`, and Gas City keeps no
doctor result: `gc doctor --json` prints its report and stores nothing, and the
supervisor's API serves no doctor route. Gas Town's deacon runs it in a step
and mails the mayor. An exec order runs its script on the orchestrator with no
agent, no LLM and no work beads (`docs/tutorials/07-orders.md`, Formula orders
vs. exec orders), under its own `timeout`. Doctor runs here took 120 seconds
at 2026-11-16T03:24:53Z and 130 seconds at 04:32:04Z, and the deacon's runs
since 2026-10-07 took 131 to 267 seconds (the initiative's note on tk-1vdtaza).

**The order.** `orders/doctor-run.toml` runs `gctk doctor run` on the city
scope every hour, with a 30-minute timeout. The verb runs `gc doctor --json`
under a deadline shorter than that, never with `--fix`, because a bare `--fix`
also runs `hold-label-routed-to`'s fix, which writes a route that names no agent
here. It writes no bead.

**The record of a run is one event.** The verb records each run with
`gc event emit gc-toolkit.doctor.ran --payload <json>`, and the event log is
the platform object the board reads. Its payload carries:

- when the run started and finished, and whether it completed: doctor exited 0
  or 1 and printed JSON that parses, within the deadline;
- each result that is not ok, by its name, status, message and the time it
  first failed, carried from the previous run's event when that run listed it
  as failing, and this run's start otherwise;
- each result the run did not measure, by name and why: a check doctor
  abandoned at its per-check timeout reports `timed_out`, and a check the store
  gate skipped reports a stand-in whose message starts `not checked:`
  (`internal/doctor/store_liveness.go`). One that was failing keeps the time it
  first failed;
- each accepted result, with its entry from the accepted file below;
- the last good run of each monitor order below.

A run that did not complete records why and carries its previous event's
results unchanged, so the board still shows the last results doctor measured,
and the verb then exits non-zero, so Gas City records `order.failed` as well.
A run's payload is a few kilobytes, and Gas City's event readers take lines of
up to a megabyte (`internal/events/reader.go`).

**What the board shows.** A city page, beside the rig pages, reads the newest
`gc-toolkit.doctor.ran` event from the supervisor's
`GET /v0/city/{city}/events?type=gc-toolkit.doctor.ran&limit=1`
(`EventListInput`, `internal/api/huma_types_events.go`), which returns the
newest match first. It shows:

- when doctor last ran, and whether that run completed. The page marks the run
  late once it is more than two hours old, twice the order's cadence, the one
  lateness rule the board holds, because doctor cannot report that it stopped;
- each failing check that is not accepted and that two runs in a row found
  failing, which the event shows as a first failure older than its own run,
  with the time it first failed. A rig's instance of a per-rig check is its own
  row, because Gas City names it `rig:<rig>:<check>` (`cmd/gc/cmd_doctor.go`);
- each check the run did not measure, as not measured;
- the accepted checks, folded under their count;
- each monitor order's last good run.

The page leads with the count of failing checks it shows, which reaches zero
when no check has failed two runs in a row.

**A check that clears on its own stays off the board.** A failure the next run
no longer finds was in one run only, and the page never shows it. A check that
takes longer to clear is listed in the accepted file with how long it may fail
before it shows. `dolt-compact-state` warns on any pending-GC marker, including
the one the compactor writes on purpose when a writer races its flatten and
clears at its next pass (`internal/doctor/checks_dolt_compact_state.go`), and
the compactor runs every two hours (`examples/bd/dolt/orders/mol-dog-compactor.toml`).
Its entry lets it fail for three hours before it shows. Since 2026-10-22 the
compactor's retry marker alone was filed 26 times, and all 25 that have closed
were closed as needing no work. The age gate asked of Gas City (tk-945d0wq) is
the fix at its cause.

**An accepted warning lives in a reviewed file.** `doctor/accepted.toml` lists
each accepted check by name, with the reason and the ruling that accepted it,
and for a check accepted only for a while, how long it may fail. A change to it
is a PR the operator reviews, and the operator's approval is the ruling. Gas
City's pack discovery reads only the directories under `doctor/`
(`DiscoverPackDoctors`, `internal/config/doctor_discovery.go`), so the file is
no check. The verb marks a result accepted when the file names it, and the
page folds it. Approving this design accepts two entries:

- `hold-label-routed-to`, with no bound. It warns on every bead held with
  `hold:mayor` and no route, which Gas City's issue 6069 reports as a bug.
- `dolt-compact-state`, for three hours, as above.

**A failure that is new and stays reaches the operator** on the city page from
the second run that finds it, with the time it first failed, and it counts in
the page's lead until a run measures it ok or the operator accepts it. Nothing
mails or nudges anyone about it, and nothing enters the Product Owner's queue,
because the operator holds that interrupts do not belong where a person talks
with an LLM (conversation tk-9l9pg0x).

**Each monitor order's last good run.** The monitors are the orders whose job
is to notice a problem: the four orders of sections 2 and 5 that look, Gas
City's that mail the `human` mailbox, `spawn-storm-detect`, `orphan-sweep`,
`reaper`, `mol-dog-doctor` and `mol-dog-backup`, and the dolt pack's
`dolt-health`, which reports only by failing its run. For each, the
verb reads the newest `order.completed` event, which Gas City records when an
exec run exits 0 (`dispatchExec`, `cmd/gc/order_dispatch.go`). It reads events
because `gc order history` lists order-tracking beads, and this city deletes a
closed one 30 minutes after its close (`[beads.policies.order_tracking]` in the
town's `city.toml`). Whether a monitor is late or failing is Gas City's verdict
in its `order-firing-current` and `order-outcome-healthy` checks
(`internal/doctor/checks_order_firing.go`,
`internal/doctor/checks_order_outcome.go`), which reach the page as failing
checks, so the page holds no second rule for them. Both read ok when run on
2026-11-16 at 18:21Z.

**How the page's reads cache.** One cached unit is the newest doctor event,
which changes once an hour, so the page reads it at most every five minutes.
The read takes no time bound, so a doctor that has stopped still shows when it
last ran and what that run found, beside the late mark. While doctor runs, the
server's backward read of the log ends within its last two hours
(`fetchEventPageAscending`, `internal/api/huma_handlers_events.go`).

**The deacon's findings at the cutover.** When the sitting on this PR read
them on 2026-11-16, 18 of the deacon's doctor findings were open in this store,
among 47 it filed across 22 keys since 2026-10-16, and 27 of the 29 that closed
were closed as needing no work. Four of the open ones name checks the pack has
deleted. The second
landing's cutover closes each one that no closer is armed on. One whose check
still fails says the city page shows it. One whose check is gone closes as
retired, on the pack's deletion of the check, or on `gc doctor --check <name>`
answering `unknown_check` while every store reads and the check's rig is not
suspended (`doctorUnknownCheckFailure`, `cmd/gc/cmd_doctor.go`). The held
findings are left to their closers (section 13).

## 6. Gas City's alerts on the board, and spawn-storm

Core's alerts go to `GC_ESCALATION_RECIPIENT` or `GC_ESCALATION_TARGET`,
`human` by default (`spawn-storm-detect.sh`, `orphan-sweep.sh`, `escalate.sh`,
and the dolt pack's `mol-dog-doctor.sh`), and core's `notify-claims-stall.sh`
calls that recipient "the operator inbox the dashboard shows". Nothing in this
city shows it to the operator: when read on 2026-11-16 at 18:15Z it held 122
unread messages.

| Kind | Messages | Sent | What they are |
|---|---|---|---|
| Boot health, and one reply to it | 69 | 2026-08-12 to 10-27 | The pack's alert that the deacon is cold. It retires with the deacon. |
| `SPAWN_STORM` | 24 | 2026-11-11 to 11-16 | False, below. Every bead named had closed as shipped. |
| A polecat's notice that main's pre-flights fail | 9 | 2026-10-18 to 11-07 | Each pre-flight step that sent one also files or confirms a tracker bead (`formulas/mol-polecat-work.toml`, preflight-tests). |
| `mol-dog-backup`'s failed sync | 9 | 2026-09-18 to 10-05 | True when sent. October's problem was fixed (tk-hqf2nl7, folded into tk-lebkcwy, both closed). |
| Claims-stall | 6 | 2026-11-06 and 11-13 | Three stalls, each followed by its resume mail 3 to 38 minutes later. |
| `reaper` and `orphan-sweep` notices | 2 | 2026-10-24 and 10-25 | One-time reports, from a Dolt outage and one reset. |
| An agent's note that an upstream PR is ready to send | 3 | 2026-08-14 to 11-12 | Asks for the operator's send. |

**Spawn-storm is false here, and its cause is the pack's.** Each sweep, core's
`spawn-storm-detect` reads the ready, unassigned beads of every store and counts
a bead that carries `rejection_reason` or `recovered` each time its
`updated_at` differs from the one it had when a sweep last found it there. It
alerts when one bead's count reaches `SPAWN_STORM_THRESHOLD`, 2 by default
(`spawn-storm-detect.sh`, step 3). The 23 alerts in this store each named a
rework the pack filed with `rejection_reason`, which the pack writes on every
rework as the reason the resumed worker starts from, and the 24th named a bead
filed for a PR's review comments in another store. Two of the 23 traced in the
event log took no claim and no release
before their alert: each sat open and unassigned, carrying the key, while
writes to it moved its update time. The detector reads Gas Town's meaning into
the key, a bead the refinery sent back, and a rework is a new bead that was
never sent back.

The ways to fix it, weighed:

- **A key of the pack's own on a rework (this design's).** A rework records its
  reason under `rework_reason`, and `rejection_reason` stays on a bead the
  refinery sends back itself (`refinery-requeue.sh`), which is what the
  detector is for. The reworks' writers and the readers of a rework's reason
  move: `work-setup.sh`'s resume by merge, the work formula's load-context and
  the polecat doctrine's resume, and gctk's waits, PR record and lifecycle,
  where they read it. Four scripts file a rework: `rework-child.sh`, which
  files a review's and a ruling's, `pr-facts.sh`, which files one for a PR's
  review comments, a conflict with its base or a red required check,
  `pre-open-rebase.sh`, which files one to bring a branch current before its
  PR opens, and `refinery-requeue.sh`, which files one when the refinery will
  not land a bead whose PR is open. The first retires with the old review path
  (tk-1tfzr71.122) on main's deletion plan, the second with the GitHub intake
  (tk-1tfzr71.21) and the third with the old merge path (tk-1tfzr71.70), and
  AGENTS.md's rule gives code the plan retires no new work. So the change
  waits for the three retirements, then moves the writers that remain, the
  readers and the open reworks' key in one change, and no reader ever takes
  both keys.
- **The detector's threshold.** The town could raise `SPAWN_STORM_THRESHOLD`
  through an order override's `env` (`OrderOverride.Env`,
  `internal/config/config.go`). A rework would still be counted each time a
  sweep found it written while it waits, so it would take more writes to raise
  the same false alert, and a bead the refinery really keeps sending back would
  take as many sweeps longer to raise a true one. It hides the cause, so this
  design does not take it.
- **Gas City counting a return only.** A detector that counted a bead's
  return to the pool, by a release or a reopen, rather than any write while it
  waits, would fix this for every city. A change asked of Gas City is the
  operator's send (section 14, ask 4).

**The dolt pack's backup advisory is false on an idle store too.**
`mol-dog-doctor` dates each backup by its manifest's age at 12 hours (section
7), the rule the deacon's judge applied when it raised the idle-store findings
section 13 holds, and a sync with nothing to copy writes no manifest, so an idle
store's complete backup reads stale. It mailed the `human` mailbox one store's
12-hour-old backup on 2026-11-11, and that message was archived within six
minutes. Its healthy pass archives its advisories once the condition clears
(`advisory_archive_superseded`, `examples/bd/dolt/assets/scripts/advisory_state.sh`),
so a census of unread mail, such as the one above, can miss one. Its rule is
Gas City's, so its fix at the cause is a change asked of Gas City, which is the
operator's send (section 14, ask 2).

**The inbox's own unit lands after the rework key,** and after the second
landing, so neither the false spawn-storm alerts nor boot health's reach it. It
also waits on a human gate about the backup advisory, which the operator clears
once Gas City's fix reaches the city's gc, or sooner by ruling that the inbox
shows the advisory while a store sits idle. It adds a list to the city page:
the `human` mailbox's unarchived messages, read or unread, newest first, read
from `GET /v0/city/{city}/mail?agent=human&status=all`, which lists every
open message where `status=unread` leaves out one already read
(`MailListInput`, `internal/api/huma_types_mail.go`; `mailAllForQuery`,
`internal/api/handler_mail.go`), with an archive on each
row that calls `POST /v0/city/{city}/mail/{id}/archive`, one native write. The
page's lead counts its messages beside its failing checks. One cached unit is
the inbox's answer, read at most once a minute and dropped when the operator
archives a message from the page.

**The 122 messages.** `gc mail send --dedup` suppresses a send while an
unarchived message with the same key sits in the mailbox (`newMailSendCmd`'s
help), so a stale alert can hold back a fresh one. The inbox unit's cutover
archives each message whose matter has ended, by the kinds above: boot
health's, spawn-storm's, the pre-flight notices, the backup-sync failures up to
the last successful sync, each claims-stall pair, and the two one-time
notices. It records each archived message's kind and count on the cutover
bead, and it leaves the agents' notes about upstream PRs, which ask for the
operator's send, for the page's first render.

## 7. Dolt health and backups

Each verdict of the deacon's dolt-health step, and what raises it after:

| Deacon verdict (`mol-deacon-patrol.toml:87-284`) | Native raise | After |
|---|---|---|
| Server unreachable, `dolt-server-unreachable` | `dolt-health` fails every 30 seconds (`order.failed`), `mol-dog-doctor` escalates to the `human` mailbox every five minutes, and doctor's Dolt server checks fail | The city page shows doctor's checks and, once section 6's unit lands, the mail. |
| Latency over 5000 ms, nothing filed | `mol-dog-doctor` warns at 1000 ms | No pack verdict. |
| Commits over 50,000, `dolt-commit-bloat-<db>` | `mol-dog-compactor` flattens every two hours, and doctor's `dolt-noms-size` warns on size | No pack verdict. |
| Zombie servers, killed | `gc dolt health` reports them | No pack verdict and no kill (section 4). |
| Orphan databases, `dolt-orphan-dbs` | `mol-dog-doctor`'s advisory and `mol-dog-phantom-db` | No pack verdict. |
| Backup manifest older than 12 hours, or a newer file than the manifest, `dolt-backup-<db>` | `mol-dog-doctor` dates a backup by its manifest's age at 12 hours (`mol-dog-doctor.sh`, `BACKUP_STALE_S`), `mol-dog-backup` mails a failed sync, and doctor's `bd-backup-freshness` warns when `last_sync` is 24 hours old (`internal/doctor/checks_bd_backup_freshness.go`) | Gas City's checks and mail alone, below. |

**The backup check is dropped.** The first version added
`doctor/check-backup-current`, which read each backup's working set through
Dolt's storage packages and compared it with its store's. It goes, with
`gctk dolt unbacked`, Dolt's Go module in gctk's build and the backup warrant
it needed. Gas City's monitors judge backups: `bd-backup-freshness` reads a
backup current while its syncs return, idle stores included, and reaches the
city page as a doctor check, and `mol-dog-backup`'s mail about a failed sync
reaches the inbox. The five backup findings held on this member (section 13)
were one false alarm, which the deacon's own manifest-age check raised on idle
stores, and `bd-backup-freshness` read those stores ok and reported October's
real problem (tk-hqf2nl7). `mol-dog-doctor` dates a backup by the same manifest
age, so it misreads an idle store as well, and its advisory reaches the `human`
mailbox (section 6). What nothing judges now: bd stamps `last_sync` when a sync
returns, whether it carried the store's writes or not
(`updateDoltBackupState`, beads v1.3.4 `cmd/bd/backup_dolt.go`), so a sync
that returns without them reads fresh. Section 14 keeps the ask for a judge of
what a backup holds, and it is the operator's send.

The suspended-store backup and Dolt reclaim keep their warrants and their
orders.

## 8. The liveness census

The census retires whole: `liveness-sweep.sh`, its precheck, its recheck and
its classifier, with their tests and `orders/liveness-sweep.toml`. The triage
bucket kind (`task_kind=triage-subject`) retires with it and gets no warrant.
In the operator's words, it "is largely replaced by the Product Owner role and
the broader here is where work goes to get triaged process" (conversation
tk-2pvj50q, 2026-11-12). `standing-kinds.sh` lists only that kind, so it
retires with its readers' exclusions in `tools/gc-proactive.sh`,
`doctor/check-blocked-work-armed` and `doctor/check-hq-marooned-work`.

**What reads unnamed waits afterwards.** New work waits for placement in the
Product Owner's queue, and each exit of the work formula names where its bead
went (`specs/tk-rl8gz4b.29/native-hold-and-po.md`, section 6). What no queue
holds is one shape, a ready bead that no hold, route, assignee, arm or live run
sends anywhere, and it includes a placed bead whose run ended with the bead
open. The board lists it as a row group on each render, built by the board
member (tk-1tfzr71.24). On a doctor check proposed for another tendency the
operator said "I feel like using doctor is an abuse of the doctor concept, but
I am also just not a fan of the doctor leverage. We use it more than I would
expect already" (sitting tk-t5f0r7, 2026-09-30), so this read is a row of the
board's, not a check. The Product Owner queues each one with
`gc bd set-state <id> hold=mayor --reason "<why>"` or closes it. The census's
reader owes this list, and the row meets each item:

- Every waiting bead is listed by title on every render, with no carried set
  and no baseline (tk-ppqwgmo).
- One reader decides both the row and any later look, so nothing re-checks it
  with rules of its own (tk-8gradm4.12).
- A bead counts as worked only while a live run works it, never by a pour's
  leftover stamp (tk-v6d9rka's note).
- A bead held with `hold:external` waits on something outside its store and is
  named as that wait, not as placement.
- Where the row points at the queue it names the Product Owner's queue read,
  which keeps every spelling of the label, not the exact listing (tk-f4f2hr1's
  note).
- Whether a bead waits comes from Gas City's store through `gctk bead holds` or
  its package, and the row computes no wait of its own (design tk-ssm8qns.2).

**The buckets at the cutover.** When read there were 15 open triage buckets
across the city's seven stores: one unnamed-waits bucket in each of six rig
stores, four ephemeral-subject buckets, three label-scoped buckets in one rig,
and two hand-made conversation homes in another. Seven open human gates and two
plain parking gates block them, and five open beads in one rig are parked on
the label-scoped buckets. The second landing's cutover settles each one:

- A human gate whose situation still holds is filed again on the bead it
  concerns. The rest resolve as moot, since the kind they asked about retired.
- A plain parking gate also holds beads that are not buckets, so it stays. The
  bucket's edge onto it goes.
- Each parked bead takes `hold:mayor` with its bucket's reason before its
  bucket closes, so it goes into the Product Owner's queue rather than back to
  the pool.
- A hand-made conversation home loses its `task_kind` and stays open as an
  ordinary bead.
- Every other bucket closes.

The ids are in this bead's notes.

## 9. Boot health and the ledger

**Boot health retires with the deacon it watches.** Its three files leave
`tools/deletion-plan.tsv` with this member's other rows. The reason its header
gives for filing no warrant, the dog's shutdown dance, names nothing that
exists, and the file goes rather than the reason being rewritten.

**The incident ledger retires with nothing in its place.** Its writers are the
deacon's steps and prompt, `human-gate.sh` when the deacon files a gate, and
the continue hook (`assets/scripts/gc-deacon-ledger.sh`, and its callers).
Every act it logged retires with the deacon or already has a record of its own,
such as the gate. The current ledger took 3 entries in 23 days.

**No check watches the witness.** The first version added
`doctor/check-patrol-advancing` and `gctk patrol cold` to report a witness
whose patrol stopped advancing. With no loop there is no patrol to advance, so
both are dropped with the patrol-liveness warrant. A look order that stops is
what Gas City's `order-firing-current` reports, on the city page.

**I12 after the ledger.** The ledger found its own bead by label alone. Three
readers still decide a bead by a label afterwards. `skills/external-issue` finds
an upstream finding by its `upstream-finding` label, a label-only record by
design (`lifecycle/lifecycle.toml`, the upstream-send group).
`doctor/check-hq-marooned-work` exempts a bead labeled `debt`. The board reads a
convoy's ownership from its `owned` label (`applyConvoyOwnership`,
`services/helm/internal/source/beads.go`), the label Gas City's own
`gc convoy` commands key ownership on (`cmd/gc/cmd_convoy.go`). So I12 keeps its
scoped wording (`docs/component-model.md`).

## 10. Findings, warrants and step text

**Where each patrol finding goes.** The table in section 7 covers the deacon's
Dolt keys. Of the others:

| Finding today | After |
|---|---|
| `doctor-<check>` and `doctor-sweep-failed` (deacon) | The city page (section 5). No record. |
| `deacon-cold.<deacon>` (boot health) | Retires with the deacon. |
| `witness-crash-loop` | Retires with no native raise (section 3). |
| `witness-partial-release` | Retires with the write it reported. |
| `witness-candidates-unreadable`, `witness-empty-liveness-map`, `witness-refinery-queue-unreadable`, `witness-refinery-queue-unroutable` | The look's run fails, and Gas City's `order-outcome-healthy` reports three failures in a row on the city page (section 2). |
| `witness-salvage-refused`, `witness-orphan-work-landed`, `witness-unplaceable-owner.<bead>`, and the gate `witness-branch-recovery-unknown` | Kept, filed by the salvage act. No native order reads a worktree. |
| `no-progress.<session>` | Kept, filed by the seat-progress act. |
| The gate `witness-refinery-queue` | Kept, filed by the refinery-queue act. |
| HELP and NOTICE mail findings | Kept, filed by the witness. Mail triage is the witness's judgment. |

**The keyed problem record keeps its warrant, for the patrol finding alone.**
The doctor result is no record now, but the patrol finding stays a pack noun:
the acts and the witness file it, keyed and deduplicated. For a keyed problem
record Gas City has only `gc mail send --dedup`, which suppresses a resend
while a live message carries the key, and the incident keys of core's
`escalate.sh`, which throttle mail. `gc event emit` records an event and keeps
no current state per key. One entry in `docs/warrants.md` covers the patrol
finding and retires when Gas City ships a keyed problem record.
`patrol-finding.sh` stays the one writer of patrol findings, as shared glue
whose callers reach past the patrols.

**Step text.** Rule 2 applies to this rewrite (conversation tk-v7c6973,
2026-10-26), and each test that extracts a block goes with its block:

| Step today | After | Blocks and tests that go |
|---|---|---|
| check-inbox | The witness's prompt. A NOTICE becomes a finding through `gctk mail finding <mail> --key <key>`. | `notice-finding`, and `bug-file`, which becomes one `gc bd create ... --labels hold:mayor` in prose; `notice-finding.test.sh`, and the notice parts of `polecat-human-gate-wiring.test.sh` and `witness-human-gate-wiring.test.sh` |
| recover-orphaned-beads | `orphan-work-detect` and `orphan-work-salvage` (section 2) | every block of the step; the `candidate-pipeline`, `host-bead-skip`, `downstream-court-skip`, `topology-root-skip`, `liveness-lookup`, `husk-guard`, `salvage-scope-gate`, `owning-store-guard`, `worktree-cleanup`, `recovery-stamp-gate` and `crash-loop-window` tests, about 2,300 lines |
| its branch 2b | `seat-progress-detect` and `seat-progress-report`, with `seat-progress.sh` moved into gctk | `no-progress-finding`; `witness-route.test.sh` |
| check-refinery | `refinery-queue-detect` and `refinery-queue-report` | `refinery-stuck-handoff`; its test |
| next-iteration | Retires. | `patrol-wisp-pour`; the witness cases of `patrol-wisp-reconcile.test.sh`, `patrol-pour-vars.test.sh` and `witness-nudge.test.sh` |

`pack-self-location.test.sh` pours `mol-witness-patrol` in a scratch city,
reads check-inbox's `SCRIPTS=$(b='kit.'; gc ...` line and sources `bd-lib.sh`
through it, so it tests that a poured step finds the pack's scripts through its
binding. A scratch city with no control-dispatcher pours only a root-only
formula, one with no `formula_compiler` requirement, and the witness's and the
deacon's are the pack's only such formulas. Both go, so the unit that retires
the witness's gives the test a root-only formula of its own, written into its
scratch pack with that line, and the binding's resolution stays tested.

## 11. What the initiative's notes owe, and where this design answers

| Owed item (where it was noted) | Answer |
|---|---|
| The replacement asks the store whether a bead waits, through `gctk bead holds`, and computes no wait (design tk-ssm8qns.2) | Sections 3 and 8 |
| One classifier for a census and its re-check (tk-8gradm4.12) | Section 8 |
| The ledger's label read and I12 (rework tk-9dmph8i) | Section 9 |
| No new continuation that waits on the model; the witness-nudge order goes with the loop it serves (tk-r4c0g67, tk-q4tvdyo, tk-afr00th) | The loop and the order both go (section 1). The deacon's hook goes (section 4). |
| Worked is judged by a live run (tk-v6d9rka) | Section 8 |
| No suspended-rig exception; a stale store's alarm is real except when the store is idle (tk-56m3hts, tk-cpfrmai, tk-veejeg2, tk-0m719df, tk-r358gzg, tk-qdunipz) | Section 7: the deacon's manifest-age judge that raised the idle stores' alarm retires, and `bd-backup-freshness` reads an idle store current. `mol-dog-doctor` keeps the manifest-age rule, so its advisory misreads an idle store until Gas City changes it (sections 6 and 14, ask 2). |
| Import or copy, the `work_dir` layout, check-polecat-health, the side-by-side week (visit tk-dbpz6t2) | Sections 1, 2 and 12 |
| Every waiting bead reachable by title (tk-ppqwgmo) | Section 8 |
| dolt-compact-state's designed retry (first reaction to tk-fijsqig, tk-945d0wq) | Section 5 |
| Read the default `gc session list --json`, not `--state all` (tk-1wfb7bd) | Section 3 |
| The census's test cost and its visit filters retire (tk-pgl0s8j, conversation tk-u4uo3wb) | Section 8 |
| A placed bead whose run ended; `mayor/` mail in a copy (tk-rl8gz4b.30) | Sections 8 and 1 |
| `dispatch-path.test.sh` drops the deleted readers (tk-rl8gz4b.32) | Section 12, unit 6 |
| `hold:external` is its own wait (tk-rl8gz4b.32's self-review) | Section 8 |
| One shared "is anything live behind this bead" (tk-8gradm4.7) | The census's copies retire, and the salvage reader is the one the look and the act share (sections 2 and 3). Its closer checks what remains. |
| A person's hold read from the open human gate (tk-1tfzr71.37) | Section 3 |
| Run `gc doctor` where no restart reaches it, and every non-ok result reaches the operator (tk-1vdtaza, tk-9h0w9y5) | Section 5: one Go pass with no agent turn records every non-ok result in the run's event. |
| No route restored from `gc.execution_routed_to`, and no route counted as an offer (dispatch design tk-1tfzr71.54) | Sections 3 and 8 |
| Name the Product Owner's queue read (tk-f4f2hr1) | Section 8 |
| Key a per-rig check per rig (conversation tk-wsgylaw) | Section 5: a rig's instance is its own row. |
| The precheck's lost jq fallback (review tk-mpvrcme) | It retires with the precheck. |
| `branch-context.sh` moved here; the salvage push takes the refinery's lease (merge design, section 8) | Section 3 |
| Both pending-record values are an in-flight PR (tk-1tfzr71.76) | Section 3 |
| The `label:` scope defect, the 15 buckets, the bucket kind's retirement, `standing-kinds.sh` (conversation tk-2pvj50q) | Section 8 |
| Feedback patterns no longer read as unnamed (tk-ltcv43q's self-review) | Section 8 |
| Branch 2b's rule carried as `seat-progress.sh`; boot health's owed report; no stand-in for the deacon's stale-patrol warrant (tk-1tfzr71.138, tk-1tfzr71.153) | Sections 2 and 9: the seat check becomes orders, and with no loop nothing stands in for a patrol's heartbeat. |
| Boot health's dance reason (the note of 2026-11-15T23:09Z) | Section 9 |
| `pack-self-location.test.sh` pours a patrol formula (tk-1tfzr71.155's self-review) | Section 10 |

The note on `GC_NO_API` (tk-rjmvj1y) was withdrawn by its correction
(tk-83dbts2), and the one on `backup-alarm-scope.sh` (tk-vqexoxe) by its own
(tk-56m3hts), so neither owes anything.

## 12. Units, landings and cutover

**Two landings, a week apart.** The initiative's risk note holds: run each
order beside the step it replaces for a week, compare what each finds, and
retire a step only when the order caught everything it did. A pack order cannot
run in the city before the pack's main carries it, so the work lands twice.
The first landing adds only what reads or shows, so it can run beside the old
patrols with no second writer: the doctor order, the three orders that look
and the city page. The second retires what they replace and adds the orders
that act, once a week's comparison says the looks caught what the steps did.
Gas City's own orders already run beside the patrols, so the comparison reads
them from the stores and the event log as well.

Each unit lands on its landing's integration branch, keeps the suite green and
leaves the pack whole. Each removes its files' rows from
`tools/deletion-plan.tsv`, registers the keys it retires as retired in
`lifecycle/lifecycle.toml`, re-renders the seed audit for what it changes, and
greps again for the names it removes, since this design listed their readers at
e01b53e94. Each unit is blocked by the one before it and armed to dispatch when
that closes, because they edit the same pages and the plan.

**The first landing**, on `integration/tk-1tfzr71.19`:

| Unit | What it does | Waits on |
|---|---|---|
| 1. The doctor order | `gctk doctor run`, `orders/doctor-run.toml`, the run's event and `doctor/accepted.toml` with its two entries (section 5); the keyed-problem-record warrant for the patrol finding (section 10). It adds the plan's rows for the whole files the second landing retires, beyond the twenty listed. Its PR shows a run's event against the live city beside the deacon's open doctor findings. | nothing |
| 2. The looks | `gctk worktree salvage`, `gctk session progress` and `gctk refinery stuck` with their reads, and the three detect orders (section 2), which record events and write nothing else. Its PR shows each look's run against the live city beside the witness's last week of findings and acts. | unit 1 |
| 3. The city page | The board's city page: when doctor last ran, the failing checks it shows, the checks not measured, the accepted checks and each monitor's last good run (section 5), under the board's design rules of rows, one rendering per object and a lead that can reach zero. | unit 2 |

A cutover bead armed on the first landing opens a seven-day timer gate, which
Gas City's gate sweep closes on its own.

**The comparison.** A report task waits on the first landing and the timer
gate. It reads the week from the stores and the event log: each look's events
beside what the witness's step acted on and filed, each doctor run's event
beside the deacon's doctor findings, and what Gas City's release and orphan
sweep did with the same beads. It records the comparison on the second
landing's bead. A case a look missed is filed as a bead that blocks the unit
retiring its step.

**The second landing**, on an integration branch of its own, which the
implementation child files with its landing bead and summary task:

| Unit | What it does | Waits on |
|---|---|---|
| 4. The acts and the witness | `--act` for each of the three verbs, with its guards (section 2), and the three act orders; the witness on demand, its prompt and the senders' `--notify` (section 1); `formulas/mol-witness-patrol.toml`, `orders/witness-nudge.toml`, `witness-nudge.sh`, `orphan-dispose.sh`, `branch-context.sh` and `seat-progress.sh` go, with their tests and the step extraction tests (section 10); `pack-self-location.test.sh` takes its own root-only formula; the pages and skills that describe the witness's loop or its recovery follow, among them `docs/authority-map.md` and `docs/component-model.md`. | the comparison |
| 5. The deacon retires | `agents/deacon/`, its named session and the pack's patch for it, `formulas/mol-deacon-patrol.toml`, `doctor-sweep.sh` and its test, boot health's three files, `gc-deacon-ledger.sh` and its test, the continue hook with its test and settings entry, `human-gate.sh`'s ledger append, `check-hq-marooned-work`'s ledger exemption, the deacon and boot health in `patrol-finding.sh`'s caller list and its reserved `doctor-*` keys, the deacon's tests and the pages that name them, among them `docs/pack-authoring.md`'s patrol startup section (tk-a89659h). The city page landed first, so the deacon's doctor step retires after the board shows doctor's results. | unit 4 |
| 6. The census retires | the census's eight files and its order, `standing-kinds.sh` with its test and its readers' exclusions, the reader lists of `dispatch-path.test.sh` and `run-lib.test.sh`, `skills/converse-prep`'s re-check, the witness prompt's line about the sweep, and the pages and registry entries that name the census or the bucket kind. It brings the branch current with main first, so #1531's edit of `liveness-sweep.sh` arrives before the deletion. | unit 5 |

**The town changes, one on each side of the second landing.** The mechanik
makes both. The town's `city.toml` patches the deacon's provider, and Gas City
refuses a config whose patch names an agent that does not exist
(`ApplyPatches`, `internal/config/patch.go`), so that patch must leave the town
before the landing reaches the city. Without it the deacon runs on the city's
default provider, the work tier, so the patch leaves once the landing PR is
approved and just before it merges, and the landing bead waits on that change.
The town's `[[orders.overrides]]` entries for `liveness-sweep` hold the census
to a 24-hour window, where its own is six hours. They leave after the landing,
because Gas City only logs an override whose order is gone (`OnOverrideError`,
`cmd/gc/order_dispatch.go`), and taking them out earlier would let the census
run up to four times as often until then.

**The second landing's cutover.** The landing reaches the city through the rig
checkout's reconcile. Then a cutover bead, armed on the landing:

1. Burns the deacon's and the witnesses' open patrol wisps. Gas City keeps an
   orphaned template's session running while it holds work, and closes it once
   the work is gone.
2. Settles the triage buckets as section 8 says.
3. Closes the deacon's and boot health's open findings that no closer is armed
   on, as section 5 says.

**The inbox comes after both landings.** Two beads of their own, each to main:

| Bead | What it does | Waits on |
|---|---|---|
| 7. The rework key | A rework records its reason under `rework_reason` in every writer that files one then, its readers move, and the open reworks' key is rewritten once (section 6). | the retirements of the old review path (tk-1tfzr71.122), the old merge path (tk-1tfzr71.70) and the GitHub intake (tk-1tfzr71.21) |
| 8. The inbox | The city page's list of the `human` mailbox with an archive on each row, and its cutover's archive of the old mail (section 6). | bead 7; the second landing, so boot health's mail has stopped; and the human gate on the backup advisory (section 6) |

## 13. Edges and notes the implementation child adds

The implementation child (tk-1tfzr71.159) files units 1 to 3 under the epic
tk-1tfzr71 with `target=integration/tk-1tfzr71.19` in each create, each blocked
by the unit before it and armed to dispatch when that closes, and the landing
bead (tk-1tfzr71.19) and its summary task (tk-1tfzr71.160) wait on all three.
It files the first landing's cutover bead, the comparison task, the second
landing with its integration branch, summary task and units 4 to 6, the two
town changes for the mechanik, the second landing's cutover bead, beads 7 and
8, and the human gate bead 8 waits on, with the edges section 12 names. The
second landing waits on the first town change, and the second town
change and the cutover wait on the second landing. It surveys the open
branches against each unit's files before it files, since they move.

The problems held on this member, and what each closer checks once the
landing that retires its code closes:

| Held bead | What the retirement removes | What its closer checks |
|---|---|---|
| tk-wcdwhxm, tk-8a6akou | `orphan-dispose.sh` and the witness's release of a dead session's claims | No pack order or script writes a step's status, route or assignee it does not hold. |
| tk-1vdtaza | the deacon's sweep and its restart | The doctor order's runs complete, and every non-ok result is in its run's event. |
| tk-2lor8sg, tk-ujz8d10 | the deacon's doctor findings | The check, if it still fails, shows on the city page. |
| tk-cpfrmai, tk-veejeg2, tk-0m719df, tk-r358gzg, tk-qdunipz | the deacon's manifest-age judge | No backup alarm is raised on an idle store. `mol-dog-doctor`'s advisory still raises one until Gas City changes its rule (section 14, ask 2), so the closer asks a person and names that rule. |
| tk-1erda9g, tk-ppqwgmo, tk-8gradm4.12 | the census | Nothing files a census gate. |
| tk-8gradm4.7 | the census's copies of the live-behind check | Which readers remain, and whether they share one rule. |
| tk-a89659h | the deacon and boot health | `docs/pack-authoring.md` names no boot agent and no shared startup fragment. |

It appends a note to each bead below:

- **tk-hpy4lgk.** A close brief, a `blocks` edge onto the second landing's bead
  and the validating closer's arm, under AGENTS.md's rule for code the plan
  retires: the deacon's failed reset retires with the deacon.
- **tk-1tfzr71.24.** The board's row of ready beads no queue holds, with the
  owed list of section 8. The city page and the inbox are this member's, and
  they read supervisor objects, events and mail, so the board member has
  nothing to migrate in them.
- **tk-1tfzr71.122, tk-1tfzr71.70 and tk-1tfzr71.21.** Bead 7 waits on each. A
  writer any of them builds to file a rework in place of `rework-child.sh`,
  `pre-open-rebase.sh` or `pr-facts.sh` is one that bead 7 moves to
  `rework_reason`.
- **tk-1tfzr71.25.** The keys this member registers as retired: `recovered`,
  `recovered_at`, `recovered_count`, the `triage.*` keys, the `triage-subject`
  kind and the ledger's label.
- **tk-945d0wq.** `doctor/accepted.toml` lets `dolt-compact-state` fail for
  three hours before the city page shows it, until Gas City's age gate lands.

## 14. Gas City facts, the upstream asks, and the search

The city runs gc 1.4.3, built on 2026-11-12 from the fork at 6589a7df45. Its
cached core and dolt packs match upstream main byte for byte in
`orphan-sweep.toml`, `orphan-sweep.sh` and `mol-dog-doctor.sh`. Its
`spawn-storm-detect.sh` is the fork's, which differs from upstream's in one
line that reads a missing bead and counts the same way, and has the same
threshold and recipient. Many of the Gas City files this record cites differ
between the fork build and upstream main, among them
`cmd/gc/pool_session_name.go`, `cmd/gc/cmd_hook_claim.go`,
`cmd/gc/order_dispatch.go`, `cmd/gc/cmd_nudge.go`, `internal/config/config.go`
and `cmd/gc/cmd_doctor.go`. One cited rule is not in the fork build:
`agents_exclude` entered upstream at 6e283f4820 (2026-11-12, #6268), after it.
Every other symbol and rule this record cites is present in both, among them
the release's human-label skip and pool test, the keys each release clears,
the workflow retire at claim, the session-model check and the one store it
reads, the override's `env`, the patch refusal, the store gate's stand-ins, a
timed-out check's `timed_out`, the `unknown_check` answer to `--check`, the
event trigger, the open-work gate, the `order.completed` and `order.failed`
events, `gc event emit`, the order checks' firing and outcome rules, the mail
send's `--notify` wake and `--dedup`, and pack doctor discovery's skip of
files.

These asks stay proposed. Posting them is the operator's decision, and none is
sent.

1. **A doctor result Gas City keeps.** A scheduled doctor run whose last result
   the supervisor's API serves would retire the pack's doctor order and its
   event.
2. **A backup judge of what the backup holds.** `mol-dog-doctor` and
   `bd-backup-freshness` judge a file's age or a sync's return, so an idle
   store's manifest reads stale and a sync that returns without carrying the
   store's writes reads fresh. The inbox's human gate waits on it (section 6).
3. **A keyed problem record.** It would retire the patrol finding.
4. **`spawn-storm-detect` counts a return to the pool.** It counts any write
   to a waiting bead that carries `rejection_reason` or `recovered`, so a bead
   written while it waits reads as sent back, and it misses Gas City's own
   releases, which write neither key, so a bead that keeps killing the
   sessions that take it raises nothing.
5. **`session-model` reads every store.** It lists work only from the city's
   store, so a dead claim both releases leave in a rig's store is reported only
   when it is a step in progress, which the pack's `check-claim-advancing`
   reads.
6. **`mol-dog-doctor`'s advisory keyed per database.** Its dedup on the
   condition word hides a second store going stale.

The search behind each surface this design adds is in
[gas-city-search.md](gas-city-search.md).
