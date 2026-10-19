---
name: Converse on native human gates — the gate is the conversation
description: The design for tk-0ur8r9p, the design child of convoy tk-iirrmiw under initiative tk-1tfzr71.4. A question for the operator becomes one native human gate on the bead it is about, filed by escalate.sh, claimed by a sitting through its work query, answered by resolving the gate with the outcome at the head of its reason, and read directly by the helm board. The visit bead kind, the sweep that turned gates into visits, and the scripts that kept the two in step retire. It settles what a gate blocks and carries, the one writer, every caller and reader, how a question reaches the operator, the sitting's claim and ending, the board's read path, the skills and prompts, the retire list and keys, the migration of open visits, the cutover, the build breakdown and the sequencing with the epic's other members. It also records the platform facts it was verified against and the two premises of the ruling that did not hold. Read it to approve the design at its checkpoint or to build one of its units.
---

# Converse on native human gates: the gate is the conversation

## What the operator approves here

Today a question the city needs you to answer is a visit, a task bead the pack
invented before Gas City shipped human gates. Since then the pack files a native
human gate, a sweep turns it into a visit, and the rest of the pack reads the
visit. After this change the gate is the question. Nothing converts it, and the
board reads it directly. Your sitting with converse, the record it leaves, the
board's ranking and the keys you press stay as they are.

1. **A question is one native human gate on the bead it is about.** Its title is
   the question as the board shows it. Its description is the framing, its await
   id names the situation, its assignee is the sitting that holds it, and its
   close reason is the answer. It carries no pack metadata, and the visit bead
   kind goes. Cost: the gate blocks that bead, and a visit never did. Routed work
   waits for your answer. A question about a PR holds its merge, which an open
   visit already does today through the finalize gate. A question about an epic
   pauses the parts of it that have not started.
2. **escalate.sh is the one writer of questions.** It reads the bead's gates
   before it files, so each situation is asked once. It keeps the one-day quiet
   period after you call a situation moot or benign, and a filer can still
   withdraw its own unanswered question. gc-helm.sh demand, mol-visit and the
   five copies of the visit-filing block go. Cost: two situations on one bead are
   two gates. They fold into one board row and one sitting.
3. **Every caller keeps its call.** The escalate.sh call sites keep their flags,
   and the polecat decline stays escalate.sh, then await-ruling.sh, then
   run-cancel.sh. await-ruling.sh still releases the claim and arms the re-sling,
   but it no longer adds an edge, because the gate is the edge. Cost: none at the
   call sites. Every reader that looked for a visit now reads the bead's gates.
4. **The board is how a question reaches you.** The town's city.toml also turns
   off core's notify-on-human-gate-creation, next to the re-ask order it already
   turns off, because both mail a mailbox you do not read. Cost: a town-repo
   commit. No mail or nudge announces a question, which is today's behavior.
5. **A sitting is one session for one bead.** Engage starts it, assigns it every
   open question on that bead, and attaches you. The sitting claims its questions
   with a plain gc hook --claim through a work query that serves gates, so
   converse-claim, the put-back, the fold and the restart forensics go. Cost:
   engage keeps its reclaim from a dead sitting, and converse-reap stays, keyed on
   gates. Gas City releases neither a dead sitting's gate nor a finished manual
   session (section 6).
6. **A sitting ends by answering or by leaving the question open.** An answer is
   one bd call that resolves the gate with `ruled:`, `moot:` or `benign:` at the
   head of its reason, and the record goes on the bead's notes. A hold keeps the
   gate claimed, with what you owe as its title. Dismiss ends a sitting and never
   answers its question. Cost: dismissing a sitting no longer clears an
   escalation from the board. It stays until a sitting answers it or its filer
   withdraws it.
7. **The board reads open human gates directly and ranks them as today.** A gate
   folds onto the bead it blocks, and held, owed, engaged, Accept and the PR's
   needs-attention status read the gate where they read the visit. Cost: the
   board's default store reader gains a gate read that no test covers today.
8. **Cutover is one migration run per store, right after the pack update.** Each
   open visit becomes a gate on its subject, or joins the gate already asking the
   same thing, with its notes carried over. Cost: for the minutes between the
   pack update and the run, open visits are not on the board, and a sitting live
   at cutover is ended and has to be engaged again.
9. **The build is four beads onto this branch, in order:** the writer and its
   callers, the readers, converse and the board, then the cutover. Cost: four PRs
   to review here instead of one.

## The platform this rides

Every fact below was read on 2026-10-19 against the installed gc 1.4.3 and bd
1.3.1, and against Gas City's upstream source. The installed gc is built from a
local commit that upstream does not contain. Where a fact matters, it was read
at upstream, and the core orders it names are byte-identical in both. Gas City
paths are relative to the Gas City source tree, and bd paths to bd's.

| Mechanism | What this design uses it for | Where it was read |
|---|---|---|
| `bd gate create --type=human --blocks <bead> --title --reason --await-id` | Files a question. It adds one `blocks` dependency, so the target is blocked by the gate. The reason is appended to the description. No assignee, metadata or label can be set at create, and nothing dedups. | bd `cmd/bd/gate.go` (flags 1282-1288, edge 352-368, description 411-437); `bd gate create --help` |
| `bd gate list <bead> --json` | Lists a bead's gates for the writer's dedup and for every reader. It returns the bead's outgoing dependencies of any type that are gates, open ones only unless `--all`, 50 unless `--limit 0`, with `await_type` and `await_id`. | bd `cmd/bd/gate.go` 79-98 and `filterIssueGates` 129-144; `cmd/bd/gate_proxied_server.go` 450-488 |
| `bd gate resolve <id> --reason` | The answer. It closes the gate with that close reason and recomputes `is_blocked` for the beads it blocked. | bd `internal/storage/issueops/close.go` 339-384; `bd gate resolve --help` |
| `bd close` refuses a blocked bead without `--force` | A question holds its bead's close. | bd `internal/storage/issueops/close.go` 150-160 |
| A blocked parent's state cascades to its `parent-child` descendants | Why a question on an epic pauses its parts. | `docs/component-model.md`, I1's shape law |
| `bd ready` excludes gates, and a plain `bd list` hides them (`--include-gates` or `--type gate` shows them) | Why a sitting needs its own work query. | bd `internal/storage/sqlbuild/ready.go` 16-22; a live listing, 2026-10-19 |
| `bd update --claim` works on a gate | The sitting's claim. | bd `internal/storage/issueops/claim.go` 61-136 |
| Agent `work_query`, and its three-tier default | Converse claims its gates. With no session, the controller's probe runs only the routed tier, and the current runtime takes no wake demand from a work query. | Gas City `internal/config/config.go` 3626-3643; `cmd/gc/session_reconcile.go`, `computeWorkSet`; `cmd/gc/city_runtime.go` 4625 |
| A manual session stays awake until it is closed or drained. An attached session is woken even when drained. | Why converse-reap stays (section 6). | Gas City `cmd/gc/compute_awake_set.go` 432-440, 590-594 |
| The pool execution backstop nudges, then drains, a pool session that holds in-progress work and is quiet for 90 seconds, with no attachment exemption | Why a sitting is not a pool session. | Gas City `cmd/gc/execution_backstop.go` 321-322, 405-421 |
| Core notify-on-human-gate-creation and renudge-stale-human-gates | Turned off in this city (section 5). Both act only on an open human gate, and mail its assignee, then `gc.deferred_assignee`, then `$GC_ESCALATION_RECIPIENT` (default `human`). | Gas City `internal/bootstrap/packs/core/assets/scripts/notify-on-human-gate-creation.sh` 1-80, 173-181; the town's city.toml 304-311 |
| Core escalate.sh hook and its incident reminder | Prior art for the writer's quiet period. It is a mail hook for maintenance scripts, and it is not this pack's writer. | Gas City `internal/bootstrap/packs/core/assets/scripts/escalate.sh` 1-22; `docs/getting-started/troubleshooting.md` 877-905 |

Two premises of the ruling (tk-xexv7bo, turn 3) did not hold when they were
re-verified, and the design is reshaped around both. Each is recorded under
[Gap records](#gap-records).

- **`gc.continuation_group` does not reach a gate.** The hook claim preassigns
  open beads that share both `gc.root_bead_id` and `gc.continuation_group`
  (Gas City `cmd/gc/cmd_hook_claim.go` 3362-3372). The reconciler's backstop
  covers only task beads under a graph.v2 root
  (`cmd/gc/build_desired_state.go` 6453-6466). A gate has no workflow root, so
  same-subject continuity comes from one session serving one subject (section 6).
- **Nothing native releases a gate a dead sitting claimed.** Core's orphan-sweep
  lists in-progress beads with a plain `gc bd list`, which hides gates
  (`internal/bootstrap/packs/core/assets/scripts/orphan-sweep.sh` 89, 106).
  Gas City's dead-assignee release covers pool-routed work. bd's lease reclaim
  runs only for agents that set `auto_reclaim_stale_claims`, and a lease lasts
  five minutes, which no config or flag changes (bd
  `internal/storage/issueops/lease.go` 19-42). A held sitting is quiet for hours,
  so lease reclaim would take a live sitting's question. Engage keeps its
  reclaim (section 6).

One more upstream fact frames the design. No upstream pack asks a human through
`bd gate create`. The build pack parks its session with `gc session wait --sleep`
and mails the human once, and Gas Town asks in the live conversation or escalates
by mail. So nothing upstream competes with this use of human gates, and nothing
upstream fills the board's role.

## 1. What a conversation is

A conversation is one native human gate:

```
gc bd gate create --type=human --blocks <subject> --await-id <situation> \
  --title "<the question, at most 140 characters>" --reason "<the framing>"
```

**It blocks its subject**, the bead whose next step waits on the answer. bd
records the gate as a `blocks` dependency of the subject. The subject leaves
`bd ready` and the pool's offer until the gate closes, and `bd close` refuses it
while the gate is open. Three consequences follow, and the first decision above
asks the operator to accept them.

- **Routed work waits.** A visit never held its subject's readiness. Its
  `tracks` edge is non-blocking on purpose (`assets/scripts/finalize-gate.sh`, header), and the
  doctrine "a conversation does not freeze its subject"
  (`docs/gascity-human-engagement.md`) rests on that. The doctrine retires: a
  question the operator owes holds the bead it is about until it is answered.
- **A question about a PR anchor holds the merge.** gctk merge holds on any live
  `blocks` blocker of the anchor (`services/gctk/internal/cli/merge.go` 552-567).
  An open visit already holds the merge today through finalize-gate's
  no-open-visit clause, which gctk merge runs before approval and again before
  the merge (merge.go 571-578, 766-774). So the merge hold does not change. What
  retires is the machinery that kept the conversation's own wait off the
  anchor: converse-hold's demand filed on the visit, its opt-in `--hold-merge`,
  and the cut-short sign-off that moved the demand onto the anchor.
- **A question about a container pauses its unstarted parts.** A blocked epic,
  or an owned convoy whose members are `parent-child` children, cascades its
  blocked state to every descendant (I1's shape law, `docs/component-model.md`).
  That is the shape law's wait of the whole. A question about one part is filed
  on that part. Work already in flight is not stopped, because a blocker gates
  claims, not running sessions.

**Its title** is the question as the board's NEEDS cell shows it, at most 140
characters, the cap gc-helm.sh takeaway already enforces. bd's default title is
`Gate: human`, so the writer always passes one.

**Its description** carries the framing: the filer's message, and the original
id when the writer redirected an ephemeral subject (section 2). A question the
liveness sweep raises names, in its message, the command that re-reads the
current state. That replaces the `visit.recheck` hook.

**Its await id** names the situation: the filer's `--key`, or `conversation` for
a question the operator opens. bd stores it and returns it from `bd gate list`.
bd's gate check skips human gates (bd `cmd/bd/gate.go` 712-731), and core's two
human-gate orders read a gate's type, status, age and addressee, never its await
id. So the pack's meaning for a human gate's await id collides with nothing in
the platform.

**Its assignee** changes across a question's life:

- **Waiting:** unassigned. The board shows the question owed and unengaged.
- **A task only a named person can perform:** assigned to that person, as
  `gc-helm.sh demand --assignee` does today. Engage leaves such a gate with its
  person.
- **In a sitting:** claimed by the sitting's session. `bd update --claim` sets
  `in_progress`, the assignee and a lease.
- **Held:** still claimed by the sitting (section 7).
- **Dismissed or cut short:** released, open and unassigned.

**It carries no pack metadata.** Every fact the visit kept in a pack key is a
native field of the gate:

| The visit carried | The gate carries it as |
|---|---|
| `task_kind=visit` | `issue_type=gate`, `await_type=human` |
| `gc.routed_to=human`, the board's human partition | `await_type=human` |
| a `tracks` edge to the subject and `gc.continuation_group=<subject>` | its `blocks` edge, read with `bd gate list <subject>` |
| `escalation_key` | its await id |
| the title `visit: <subject> — <headline>`, and `gc.takeaway` on a demand gate | its title |
| `gc.demand_for`, `gc.demand_topic`, `gc.gate_visit`, `gc.hold_demand` | the gate itself |
| `gc.outcome`, `gc.outcome_reason`, `gc.ruling` | its close reason (section 7) |
| `pr_number`, `pr_url` and `anchor_bead`, stamped on PR-comment visits so the merge held | its `blocks` edge on the anchor |
| `visit.recheck` | its description |
| `gc.pr_visit_summary`, `gc.pr_visit_actions` | arguments to the sign-off (section 7) |

Molecule steps stamp `gc.continuation_group` for Gas City's own preassignment
(`formulas/mol-polecat-work.toml` 55, `formulas/mol-review.toml` 145). That use
is not the visit's, and it stays.

## 2. The one filing writer

**escalate.sh files every question.** It already has the most callers, and it
already resolves the subject's store. Its flags stay as they are: `--subject`,
`--key`, `--message` and `--retract`. `--key` becomes optional and defaults to
`conversation`. `--pool` retires, because a gate is not routed.

It files in five steps:

1. **It resolves the subject's store** with escalation-rig.sh, unchanged. A gate
   must sit in its subject's store, because a `blocks` edge across stores holds
   nothing (I1, `docs/component-model.md`).
2. **It redirects an ephemeral subject** (a wisp, or a subject proven to name no
   placeable bead) to the rig's standing triage subject, as today. The original
   id goes in the framing, so `escalation_raised_by` retires.
3. **It reads the subject's gates** with `bd gate list <subject> --all --limit 0
   --json`. An open human gate with the same await id means the situation is
   already asked, so the writer prints that gate's id and exits 0. This is the
   idempotency the ruling asks for. bd has none at create, so two writers racing
   in the same instant can both file. The board folds both, and the sitting
   answers both with one reason.
4. **It keeps the quiet period.** If the newest closed human gate with the same
   await id closed with a reason headed `moot:` or `benign:` less than
   `GC_ESCALATE_VERDICT_WINDOW` seconds ago (default 86400), it files nothing and
   says so. A caller whose question carries a wait passes 0, as today, because a
   wait needs an open gate to sit on.
5. **It files the gate** (section 1) and reads its id back.

`--retract` withdraws the filer's own question. It resolves every open,
unassigned human gate on the subject with that await id, with the reason
`moot: <message>`. A gate a sitting holds is left alone, as today.

**One open question per subject and situation.** The ruling says one open ask
per subject, and the operator still sees exactly that: every question on a bead
folds into the bead's one board row, and one sitting answers all of them. In the
store, two situations on one bead stay two gates, such as two PR comments, or a
review question beside a merge failure. Keeping them apart lets each filer
withdraw its own question when its situation clears, and keeps the quiet period
per situation.

What becomes of escalate.sh's other behavior:

| Today | After |
|---|---|
| Dedup on `escalation_key` and `gc.continuation_group` (escalate.sh 393-461) | Step 3: the await id, scoped by the subject's `blocks` edge |
| The verdict window over closed visits' `gc.outcome` (463-531) | Step 4: the closed gate's reason |
| The `escalation.recurrences` tally on the closed visit | Retires. `escalation.recurrence_last` has no reader, and only the tally reads `recurrences`. |
| `--retract` closes through visit-close.sh (257-337) | Resolves the gate |
| The ephemeral-subject triage bucket (536-605) | Kept. The bucket is a standing subject the gate blocks, and it is not visit machinery. |
| The route check and repoint through pool-route.sh | Retires |
| Its copy of the gate-visit block (383-650) | Replaced by steps 3 to 5 |

The quiet period is the one behavior the writer adds to native calls, and it has
upstream prior art. Core's own escalate.sh does not re-send an unchanged incident
for a day (`GC_ESCALATE_REMINDER_SECONDS`, default 86400). The pack's period
answers the same need, a detector that re-fires a condition a person already
looked at, and keys it on the person's verdict.

**The other minters fold into it:**

- **`gc-helm.sh demand`**, the pack's only native gate minter (gc-helm.sh
  1460-1669), retires. first-reaction-dispose.sh files its ruling and recommend
  question through escalate.sh with the key `first-reaction`, and the waits, prs
  and converse-settle skills call escalate.sh. converse-hold.sh and
  converse-signoff.sh, its other callers, retire or shrink (section 7).
- **`gc-helm.sh open`** files the operator's conversation through escalate.sh
  with the key `conversation`. Engage, the operator's intake and helm-svc's
  POST /helm/open all reach it that way.
- **The gate-visit block** in mol-validate-close and mol-feedback-distiller
  becomes an escalate.sh call with the keys `validate-close` and
  `distiller-contention`. Today both reuse an open keyless visit on the subject.
  With their own keys, their questions show beside the operator's conversation
  instead of disappearing into it.
- **mol-visit** retires. Nothing pours it.
- **gate-visit-sweep** retires. There is no visit left to make.

**converse-hold's PR-anchor case.** converse-hold.sh files its demand on the
visit when the subject is in `pre_open_gate`, `pull_request` or `merged`
(converse-hold.sh 210-213, 234-244). That kept the conversation's own wait off
the anchor. With no visit, the hold is the conversation gate itself, which is
already on the subject. On a PR anchor it holds the merge, as the open visit
already did, and nothing more is filed.

## 3. Every caller outside converse

The list was re-derived from main at 35cf7c70f. Every call keeps escalate.sh's
flags. The column on the right is what changes around the call.

| Caller | Its move |
|---|---|
| mol-polecat-work's decline arms: load-context's unreadable, parked and duplicate refusals; the blocked-work fallback; the malformed convoy; workspace-setup's target guard, branch divergence and missing branch; the bring-current question through bring-current-audit.sh; submit's branch-shape, landing-target and hand-off refusals | The call is unchanged, and the gate blocks the work bead. await-ruling.sh (section 4) releases the claim and arms the re-sling, and run-cancel.sh ends the run. The verdict window stays off where a wait follows. |
| `template-fragments/polecat-doctrine.template.md` (Escalation and the decline protocol) and `template-fragments/pool-worker-no-consent-ui.template.md` | The same three calls in the same order. The text says "the human gate escalate.sh files" where it said "the visit escalate.sh opens". Every polecat does what it does today. |
| mol-validate, mol-rig-demo, mol-refinery-patrol, mol-witness-patrol, mol-dog-shutdown-dance | Unchanged calls. mol-witness-patrol's check-refinery finds its open `witness-refinery-queue` questions with `bd gate list` and retracts them as today. |
| The deacon, refinery and witness prompts | Unchanged calls. The deacon prompt's stale "converse pool" default goes. |
| pr-facts.sh, the merge-path families | Unchanged calls. It stops stamping `pr_url`, `pr_number` and `anchor_bead` on the comment and unengaged-thread questions, because the gate blocks the anchor. `visit_for`, the dispose retract and refresh, the merge-blocked-approval retire, the retire on a disposed anchor and the write-back's awaiting and resolved replies read the anchor's gates by await id. |
| gctk merge (one-anchor-per-pr, seed-audit-merge-gate) and record-failure-cap.sh | Unchanged calls. gctk merge reads a human gate on the anchor as a person's hold (section 4). |
| gate-ensure.sh, branch-supersession.sh, reconcile-rig-checkouts.sh, rejection-repool.sh | Unchanged calls. branch-supersession.sh's lookup reads gates. |
| deferred-dispatch.sh, liveness-sweep.sh, finding.sh, upstream-finding.sh | Unchanged calls. liveness-sweep.sh puts its recheck command in the message instead of stamping `visit.recheck`. finding.sh records the gate's id (section 4). |
| The gascity-keeper sub-pack's refinery fragment | Its call passes flags escalate.sh rejects, behind `|| true`. tk-vfgmu8k fixes it to escalate.sh's flags, and this design keeps those flags. |
| first-reaction-dispose.sh | escalate.sh with the key `first-reaction`. Its `--visit` option, which blocked the subject on a visit, retires. |
| mol-validate-close, mol-feedback-distiller | escalate.sh with their own keys (section 2). |
| gc-helm.sh engage and open, the operator's intake, helm-svc POST /helm/open | escalate.sh with the key `conversation` (sections 6 and 8). |
| The waits, prs and converse-settle skills | escalate.sh where they called `gc-helm.sh demand` (section 9). |

## 4. What an open or answered question means to other machinery

| Meaning today | Read by | After |
|---|---|---|
| **An open visit refuses its subject's finalization** | finalize-gate.sh `clause_no_open_visit`, run by gctk merge before approval and before the merge, and by bead-rehome.sh | The gate holds natively: gctk merge holds on a live blocker, and `bd close` refuses a blocked bead. The clause stays as an explicit precondition, re-expressed as "no open human gate blocks this bead", because a close path that passes `--force` skips bd's refusal. `--except-key` keeps its meaning: the caller's own unassigned gate with that await id does not hold the act it asks to retry. |
| **Any live bead carrying the PR's `pr_number` holds the merge**, which is how a PR-comment visit held its PR | gctk merge `inflightHolder` (merge.go 1509-1554) | No longer stamped on questions. The gate blocks the anchor. The probe stays for its other holders. |
| **The merge's machine state** | gctk merge `stuckHolder` (merge.go 1580-1590) | A gate with no route would read as "an unrouted blocker no automated actor will clear". gctk merge reads a human gate as a person's hold and records no machine state, as it does for a visit today. |
| **An open visit sets the PR's needs-attention status** | gctk pr-status `anchorOpenVisit` (`services/gctk/internal/cli/prstatus.go` 107-192) and `services/gctk/prstatus/prstatus.go` 121-123 | An open human gate on the anchor. |
| **The proceed ruling:** await-ruling.sh blocks the work bead on the visit and arms its re-sling | `assets/scripts/await-ruling.sh` | The gate is the edge. await-ruling.sh keeps the claim release, the route clear and the deferred-dispatch arm, and it checks that an open human gate with the key blocks the work bead instead of adding one. It survives because a formula-slung bead needs the arm. Closing the gate makes the bead ready, and only the arm re-slings it on its formula. |
| **Review release:** a needs-you finding is released only by a closed visit carrying `gc.ruling`, following `gc.folded_into` and `gc.superseded_by` | finding.sh close-answered, run by gate-ensure.sh; review-answer.sh; pr-facts.sh's review dismissal | finding.sh stamps the gate's id as `finding.gate` and releases on a gate whose close reason is headed `ruled:`. It still follows `gc.superseded_by`. Gates do not fold (section 7), so the `gc.folded_into` hop retires. `finding.ruling_visit` becomes `finding.ruling_gate`, and its readers move with it. |
| **Liveness:** a subject covered by a live visit is conversing, and one named by `gc.demand_for` is held by design | liveness-classify.sh 113-149, liveness-sweep.sh, liveness-sweep-precheck.sh, liveness-recheck.sh | A bead blocked by an open human gate is held by design while no live sitting holds the gate, and conversing while one does. The sweep's live-visit guards read the subject's gates. |
| **Orphan disposal** | orphan-dispose.sh's visit arm; the witness patrol's recovery steps | The visit arm retires. Routed-human beads never reached it anyway (mol-witness-patrol.toml 245-250). salvage-scope-gate keeps treating a gate as not work. |
| **A ruling's rework child** | `source_ruling_bead` (rework-child.sh, gate-ensure.sh, duplicate-sweep.sh, liveness-sweep.sh, live-work.sh) | Readers unchanged. The value is the gate's id from now on. |
| **A PR comment's disposition** | `pr_comment_disposition=visit:<id>` (pr-facts.sh; doctor check-feedback-routing-owed) | `gate:<id>`. |
| **Others** | bd-lib.sh's anchor children; bead-rehome.sh's outcome stamp on a visit it rehomes; pr-post.sh's `gc:visit` marker | The anchor children lose the visit. The stamp retires, because a gate is never rehomed, only its subject. The marker becomes the reminder's gate marker (section 7). |

The doctor checks:

- **check-visit-outcome-recorded retires.** A gate's answer is its close reason,
  written by the close itself. A gate a person closes by hand with no headed
  reason fails safe both ways: its finding stays held, and the quiet period does
  not start.
- **check-hq-marooned-work** drops its visit exemption. Gates are already exempt
  as infrastructure.
- **check-wait-is-an-edge** keeps its terminal-wait exemption and keys it on the
  gate type. `terminal_wait_key = "gc.demand_for"` in `lifecycle/lifecycle.toml`
  `[holds]` becomes a type rule.
- **check-blocked-work-armed** keeps its rule. A visit's route no longer counts
  as a dispatch path, and a work bead blocked by a human gate needs its arm,
  which await-ruling.sh writes.
- **check-state-space** adds every retired key to `RETIRED_KEYS`, so a leftover
  on a live bead is reported.
- **check-until-resolved-owed** changes only its finding text.
- **check-feedback-routing-owed** reads `gate:<id>` dispositions.
- **check-armed-dispatch-owed** takes hold-lib.sh's demand-gate rule from the
  gate type.
- **check-routed-work-claimable** does not change.

## 5. How a question reaches the operator

The operator reads the board, not mail. That is why the town's city.toml already
disables renudge-stale-human-gates (304-311). Core's notify order mails a human
gate's addressee only while the gate is open, and the addressee is its assignee,
then `gc.deferred_assignee`, then `$GC_ESCALATION_RECIPIENT`, which defaults to
the `human` mailbox. A question is filed open and unassigned, so every question
mails that mailbox. notification-wisp-reap exists to close those notices.

**The board alone is the reach.** The town's city.toml adds an override that
disables notify-on-human-gate-creation beside the renudge override, and the
comment over both names the board as this city's reach for a human gate. The
override is a commit to the town repo, not to gc-toolkit. It lands before the
cutover, so the gates the migration files mail nobody.

**Re-asking is the board's ordering.** An open question stays on the board,
owed and ordered by how long it has been owed, until a sitting answers it, its
filer withdraws it, or Accept resolves it. Nothing re-mails. A question held by
a sitting is in progress, and both core orders skip it anyway.

**notification-wisp-reap keeps one pass.** Its gate-notice pass retires with the
notify order. Its second pass collapses repeated `ESCALATION:` mails that core's
maintenance escalations send. Those are not human gates, so that pass stays.

`docs/gascity-human-engagement.md` contradicts itself on this point. Lines
224-229 and 493-495 say to ride the notify and renudge orders, and lines 531-533
say the visit is the reach. Both statements are rewritten to say that the board
is the reach and that core's two orders are off in this city.

The alternative was to keep the orders and give them an addressee someone reads.
`GC_ESCALATION_RECIPIENT` is one orchestrator-wide recipient for every gate and
every core escalation, set only from the environment (Gas City
`docs/getting-started/troubleshooting.md` 877-889). The operator has no session
to nudge. Pointing it at an agent would wake that agent on every question. The
alternative was rejected.

## 6. The sitting and its claim

**A sitting is a manual session of the converse agent the operator chose.**
Engage starts it as today: `gc session new converse-<model> --alias <subject>
--no-attach`. The alias becomes the subject's id instead of the visit's, so a
subject has at most one sitting, and engaging a subject that already has a live
sitting attaches to it. For an id the runtime refuses as an alias, the existing
`v-` prefix fallback stays.

**Engage assigns the sitting the subject's questions.** It assigns every open
human gate on the subject that is unassigned, or held by a session no longer in
`gc session list`, to the new session. Each assignment is a conditional update,
`--if-assignee ""` or `--if-assignee <the gone holder>`, so a race with another
engage loses cleanly. A gate assigned to a named person stays with that person.
Then engage attaches the operator. If the subject has no open question, engage
first files the conversation through escalate.sh.

**The sitting claims through its work query.** Each converse agent gains a
`work_query` (config, the epic's first test) that serves the open human gates
assigned to the session, for example
`gc bd list --type=gate --assignee="$GC_ALIAS" --status=open,in_progress --json`
filtered to `await_type` human. Gas City's default query cannot serve a gate.
Its second and third tiers run `bd ready`, which excludes gates, and its first
tier's plain `bd list` hides them. The new query spawns nothing. Without a
session the controller's probe runs only the routed tier, the current runtime
takes no wake demand from a work query, and a gate carries no route. The
sitting's first step is a plain `gc hook --claim --json`, which claims an
assigned gate: it sets `in_progress`, a lease and the session stamps.
converse-claim.sh retires. pool-demand-wiring.test.sh's rule for converse agents
flips from "no work_query" to "a work_query that serves the gates engage
assigned". Its `min_active_sessions = 0` and no-`scale_check` rules stay.

**Same-subject continuity comes from the alias, not from the continuation
group.** Gas City's continuation preassignment does not reach a gate (see the
platform section). It is not needed: one session serves one subject, and engage
assigns it all of that subject's questions. When a question is filed on the
subject while the sitting runs, converse-continue assigns it to itself with a
conditional update and claims it.

**The put-back retires, and so does a shared session serving many subjects.** A
sitting's work query serves only gates assigned to it, so it can never claim
another subject's question. The put-back released exactly those claims
(converse-claim.sh 305-344), so it has nothing left to do.

**A sitting whose session dies keeps its gate until engage reclaims it.**
Nothing native releases it (see the platform section). The board shows a gate
whose holder is not a live session as unengaged, reading the holder's liveness
from the session list as the liveness classifier does today. The next engage
reassigns the gate with a conditional update naming the gone holder. That is the
reclaim engage does for a visit today (gc-helm.sh 4057-4108), applied to the
gate.

**converse-reap stays, keyed on gates.** Gas City keeps a manual session awake
until it is closed or drained. A sitting cannot drain itself at its sign-off: an
attached operator's pane would be destroyed, and the attached override would
wake the session straight back up. A pool session would end on its own once its
work closed and nobody was attached. But the pool execution backstop drains a
pool session that holds in-progress work and is quiet for 90 seconds, with no
attachment exemption, and a sitting is quiet whenever the operator is reading or
thinking. So sittings stay manual sessions, and converse-reap closes an
unattached converse session that holds no open human gate.
Its retirement trigger: Gas City ends a manual session once its claimed work has
closed and nobody is attached, or exempts a session that waits on a person from
the execution backstop.

## 7. Hold, record and close

**The record** is unchanged doctrine: the sitting appends to the subject's
notes, and it writes the subject's headline with gc-helm.sh takeaway.

**A hold** is the operator owing an answer later. The sitting keeps its claim on
the gate, and it sets the gate's title to what the operator owes, at most 140
characters. It appends the hold to the subject's notes. The board shows the
question owed and engaged. The session stays, because the converse agents keep
`idle_timeout = "0"`. converse-hold.sh retires, and so do its demand, its
`gc.hold_demand` stamp and its `gc.gate_visit` stamp. An unanchored subject still
moves to `held` and back through lifecycle.sh, now called from the hold and
settle skills.

A hold does not use `gc session wait --sleep`. That command sets a wait hold and
drains the session (Gas City `cmd/gc/cmd_wait.go` 406-416), which would destroy
an attached operator's pane. While the hold is set, attaching does not wake the
session either (`cmd/gc/compute_awake_set.go` 590-594). Upstream uses it for an
agent waiting on a bead, and a sitting is a person and an agent in one pane.

**A restarted sitting** reads the gate it holds. Its `gc hook --claim` returns
the gate as an existing assignment. The gate's title says what is owed, and the
subject's notes say what was said. With `wake_mode = "resume"` it also has its
transcript. The BEGAN restart forensics retire: converse-claim.sh's diagnosis
(258-284) and the prompt's yes, unknown, recheck and no rules inferred from
`gc.hold_demand` whether a hold had begun, and the claimed gate now states it.

**The answer** is one call:

```
gc bd gate resolve <gate> --reason "<outcome>: <one line>"
```

The outcome is one of three words:

- `ruled`: the operator decided. It releases a needs-you finding.
- `moot`: the premise no longer holds. A filer's retract writes this. It starts
  the quiet period.
- `benign`: the premise holds, but it needs nobody. It starts the quiet period.

One bd call writes the close and its reason together, so there is nothing to read
back. visit-close.sh stamped `gc.outcome` and `gc.outcome_reason` before it
closed, and read them back, because those were two writes. That guard retires
with the stamps. The premise re-check's moot or benign close is this same call,
so converse-close-out.sh retires. The board already shows a closed sitting's
reason as its headline (`services/helm/internal/source/facts.go` 123), and it
reads the gate's close reason instead.

**Leaving the question open** is a release: `bd update <gate> --status open
--assignee ""`. A sitting cut short releases its gate. The ruled-no sign-off's
second demand on the anchor retires, because the gate already holds the anchor.

**Dismiss** ends a sitting. It releases the gates the session holds, and it
answers nothing. converse-reap then closes the session once nobody is attached,
as it closes a dismissed sitting's session today, so the pane is never taken from
under the operator who pressed the key. Today dismiss closes the visit, which for
an escalation removes the question until its detector re-files it. After this,
the question stays on the board. That is the cost the sixth decision names.

**There is no fold.** One open gate per subject and situation means two sittings
never hold the same question, so the holder lookup has nothing to find. A
duplicate from a race is answered with the same reason as its twin. Today a fold
also moved `pr_number`, `pr_url` and `anchor_bead` to the holder so the merge
stayed held. The gate holds the merge through its own edge. converse-fold.sh,
`visit-close.sh --into` and `gc.folded_into` retire.

**converse-signoff.sh stays as one call**, rewritten. It is glue the epic's third
test allows, because the settle skill needs its steps in one order every time:

1. route a ruling's rework through converse-rework.sh, unchanged;
2. write the subject's headline;
3. resolve each gate the ruling answers, or release it;
4. release a `held` subject;
5. update the PR reminder.

`gc.ruling`, `gc.pr_visit_summary` and `gc.pr_visit_actions` retire. The ruling
is the resolve reason, and the summary and actions are passed to the reminder
directly.

**The PR reminder stays** (tk-wxrh1z): a comment on the subject's PR when a
sitting engages, edited in place when it ends. It is keyed by the gate's id, and
pr-visit-comment.sh is renamed pr-sitting-comment.sh.

## 8. The board's read path

**What it reads.** The board reads, per store, the human gates that are open or
in progress, and the human gates closed inside the sittings window (default
24 hours). The library backend reads them with a gate-typed search. The
supervisor backend already unions a `type=gate` page into its scan
(`services/helm/internal/source/supervisor.go` 554-585). A gate's subject is the
bead it blocks. `visitFilter`, `resolveVisitSubjects` and the visit-identity
spelling retire.

**How a gate folds.** `wrapperTarget` (`services/helm/internal/board/derive.go`
2571-2595) treats a human gate as the wrapper and the bead it blocks as the
subject. `applyFold` keeps its meanings:

- **Held:** a subject with an open human gate is held. The stranded arm of
  `severity` (derive.go 696) reads it as before.
- **Owed:** an open human gate makes its subject owed even while work on the
  subject is in flight. That is the visit's rule today. A demand alone yields to
  live work (derive.go 2666), but gate-visit-sweep gives every unassigned demand
  a visit, so a demand already follows the visit's rule in effect. One rule keeps
  that behavior.
- **Owed since:** the earliest open gate's `updated_at`, which is what the
  visit's clock was.
- **Needs:** the gate's title, or `N× — a · b` over several.

**Engaged:** a subject is engaged when one of its open gates is held by a live
session. `classifyVisits` becomes the same classification over gates.

**Accept** is offered when the subject carries `gc.recommended_formula`, has an
open, unassigned human gate, and has none engaged. gc-helm.sh accept resolves the
subject's unassigned gates with `ruled: accepted <formula>` before it slings, and
reopens them if the sling fails. That is today's order (gc-helm.sh 2839-2918),
which keeps load-context from cancelling the run it starts.

**Ranking is unchanged.** `rankScore` (derive.go 734-741) and its inputs are
untouched. Every input a visit supplied, held and the owed clock among them, now
comes from the gate. A board test pins that a subject ranks the same with a gate
as it did with a visit.

**The wire model.** In `services/helm/internal/board/model.go` and
`services/helm/web/src/contract.ts`, `held`, `acceptable`, `accept_formula` and
`recommendation` keep their meaning. `visit_state` is renamed `sitting_state`.
The web marker reads "in session" or "waiting" without the word visit. The
sittings card reads gates. gctk pr-status's `OpenVisit` phase input reads an open
human gate.

**The verbs** (gc-helm.sh, and helm-svc's POST routes that run it):

| Verb | After |
|---|---|
| engage, `--new-subject` | Section 6. `--new-subject` still creates the subject first (gc.origin=operator), then engages it. `--allow-duplicate` retires: a second concern on a bead is a second question in the same sitting. |
| open (POST /helm/open) | Files the conversation through escalate.sh without engaging. `parseOpenStdout` keeps its sentences. |
| accept (POST /helm/accept) | As above. |
| dismiss (POST /helm/dismiss) | Ends the sitting (section 7). On a subject with no live sitting it does nothing and says so. |
| park, takeaway | Unchanged. park's plain gate has no await type and is not a question, and takeaway writes the subject's headline. |
| demand | Retires into escalate.sh (section 2). |

**The operator's hands do not change.** The tmux bindings keep their keys and
what they show:

- **prefix+b and prefix+B** (tmux-pick-helm.sh) engage a picked row.
- **prefix+a** (tmux-visit-prompt.sh) runs the operator's intake. gc-visit-open.sh
  is renamed operator-intake.sh, because it never filed a visit itself. Its
  fallback, which ran `gc-helm.sh open`, files through escalate.sh. The prompt's
  match for "first reaction slung", which the intake no longer prints, is
  corrected with it.
- **prefix+A** (tmux-new-subject.sh) runs `engage --new-subject`.
- **prefix+X** (tmux-dismiss-sitting.sh) runs dismiss under the pane's session.

## 9. Skills, prompts and fragments

The sitting doctrine stays: premise re-check, prep, the hand-back's shape and the
record discipline. Only text that depends on the visit bead changes.

| File | What changes |
|---|---|
| `skills/converse-recheck-premise` | The premise is read from the gate's title and framing. A moot or benign verdict is `gc bd gate resolve` with that headword, in place of converse-close-out.sh. |
| `skills/converse-prep` | It reads the gate and the subject's notes. A recheck command named in the framing is run, in place of the `visit.recheck` hook. |
| `skills/converse-hold` | The hold of section 7, in place of converse-hold.sh, the visit demand and `--hold-merge`. The dismiss line at the foot of every framing stays. |
| `skills/converse-settle` | converse-signoff.sh's new shape. The resolve replaces visit-close.sh and the guarded stamps, and the reminder update passes its text directly. A cross-store follow-up waits through escalate.sh. |
| `skills/converse-continue` | It re-runs `gc hook --claim` and adopts any new question on its subject. |
| `skills/waits` | One section on asking a person: escalate.sh files a human gate, and await-ruling.sh arms the re-sling. The demand-gate, visit and gate-visit-sweep sections go. |
| `skills/prs` | A merge hold is a question on the anchor through escalate.sh. The not-needed successor names the gate. |
| `skills/work` | Accept and the intake are described on gates. "Ask for a visit" becomes "ask the operator". |
| `skills/handoff` | A converse session resolves or releases its gates before it drains. |
| `skills/learning-distill` | The contention question goes through escalate.sh. |
| `agents/_converse/prompt.template.md` | Its definitions of visit, subject, topic and demand become one definition of a question. The claim block becomes `gc hook --claim`. The BEGAN rules, the fold and the finish arm go. The ending says the thread ends when its questions are answered or dismissed. |
| `agents/converse-{opus,fable,codex}/agent.toml` | They gain the work query. Their header comments say the alias is the subject. |
| `template-fragments/visit-close.template.md` | Renamed `ask-close.template.md`. A role never resolves another role's question, and withdraws its own with `--retract`. The deacon, mechanik, proactive, refinery and witness prompts include it. |
| `template-fragments/polecat-doctrine.template.md`, `template-fragments/pool-worker-no-consent-ui.template.md` | The decline wording of section 3. The calls are unchanged. |

Every prompt change re-renders `generated/seed-audit/agents/*.md` in the same
commit, because gctk merge holds a merge whose renders are stale.

## 10. What retires, and the keys

**The retire list.** The initiative's list was confirmed on main, and the rest of
main's visit machinery was added to it:

| Piece | Fate |
|---|---|
| The visit bead kind, `task_kind=visit` | Retires. |
| gate-visit-sweep, its order and script | Retires. |
| converse-claim.sh, converse-fold.sh, converse-close-out.sh, converse-hold.sh | Retire. |
| visit-close.sh, the guarded close | Retires. |
| The BEGAN and `gc.hold_demand` restart forensics | Retire. |
| mol-visit.toml, and the five gate-visit block copies with gate-visit.test.sh | Retire. |
| visit-identity.sh | Retires. Its Go spelling, which gcbd_test.go pins, goes with it. |
| converse-recheck-hook.sh | Retires with `visit.recheck`. |
| orphan-dispose.sh's visit arm | Retires. |
| gc-helm.sh demand | Retires into escalate.sh. |
| notification-wisp-reap | Its gate-notice pass retires, and its escalation pass stays. |
| converse-reap, its order and script | Stays, keyed on gates (section 6). |
| gc-visit-open.sh | Renamed operator-intake.sh, and it files through escalate.sh. |
| pr-visit-comment.sh | Renamed pr-sitting-comment.sh, and keyed by the gate. |
| `template-fragments/visit-close.template.md` | Renamed ask-close.template.md. |
| finalize-gate.sh's `clause_no_open_visit` | Re-expressed on gates (section 4). |

**The keys.** A key goes only when its last reader moves. Each retired key joins
`RETIRED_KEYS` in `doctor/check-state-space/run.sh`.

| Key | Fate | The readers that move first |
|---|---|---|
| `gc.gate_visit` | Goes. | gate-visit-sweep.sh |
| `gc.hold_demand` | Goes. | converse-claim.sh, converse-signoff.sh |
| `gc.ruling` | Goes. | finding.sh close-answered, which reads the close reason |
| `gc.folded_into` | Goes. | finding.sh, visit-close.sh |
| `gc.pr_visit_summary`, `gc.pr_visit_actions` | Go. | pr-visit-comment.sh |
| `visit.recheck` | Goes. | converse-recheck-hook.sh. Its writer, liveness-sweep.sh, puts the command in the message. |
| `escalation_key` | Goes. The await id carries it. | await-ruling.sh, branch-supersession.sh, pr-facts.sh, finding.sh, finalize-gate.sh `--except-key`, mol-witness-patrol's check-refinery, converse-hold.sh, converse-signoff.sh, converse-fold.sh, the formula copies |
| `escalation_raised_by` | Goes. | None. It is never read. |
| `escalation.recurrences`, `escalation.recurrence_last` | Go. | escalate.sh's tally |
| `triage.scope` | Stays. | The triage subject is not a visit. |
| `triage.last_seen` | Stays. Its registry text is corrected: it holds the in-scope ids, not a time. | |
| `triage.hold` | Stays. It has readers outside visits and no writer, and its retirement belongs to the liveness subsystem. | |
| `gc.outcome` and `gc.outcome_reason` on visits | Go. `gc.outcome` on molecule steps stays. | The board's sittings headline, bead-rehome.sh |
| `finding.visit` | Renamed `finding.gate`. | finding.sh, review-answer.sh |
| `finding.ruling_visit` | Renamed `finding.ruling_gate`. | pr-facts.sh's review dismissal, review-answer.sh |
| `source_ruling_bead` | Stays. Its value is the gate's id from now on. | |
| `pr_number`, `pr_url`, `anchor_bead` as stamped on visits | No longer stamped on questions. The keys stay on anchors and their children. | gctk merge's `pr_number` probe, gctk pr-status's in-flight count |
| `gc.demand_for` | Goes. | liveness-classify.sh, liveness-sweep.sh, liveness-sweep-precheck.sh, liveness-recheck.sh, hold-lib.sh, deferred-dispatch.sh, bead-context.sh, pr-facts.sh, pre-open-rebase.sh, the board, check-wait-is-an-edge's `terminal_wait_key` |
| `gc.demand_topic` (written and read, never registered) | Goes. | gc-helm.sh demand, converse-signoff.sh |
| `gc.routed_to=human` and `gc.takeaway` on gates | No longer stamped on gates. Both stay the subject-level markers they are. | |
| `pr_comment_disposition=visit:<id>` | Becomes `gate:<id>`. | pr-facts.sh, check-feedback-routing-owed |

**The tests that retire, with what they cover:**

- gate-visit.test.sh: the five copies' filing invariants.
- gate-visit-sweep.test.sh: one visit per human gate, and the `gc.gate_visit` stamp.
- converse-claim.test.sh: the claim's verdicts, BEGAN, and the finish close.
- converse-hold.test.sh: the demand, `gc.hold_demand` and `--hold-merge`.
- converse-fold-scope.test.sh: the topic, the holder and the hold's premise gate.
- converse-close-out.test.sh: the moot and benign close through visit-close.sh.
- visit-close.test.sh: the outcome pair, the fold and its merge-hold key transfer.
- visit-identity.test.sh: coverage by the `tracks` edge with the stamp fallback.
- doctor/check-visit-outcome-recorded and its run.test.sh: a closed visit carries `gc.outcome`.
- liveness-recheck.test.sh's `visit.recheck` cases.
- notification-wisp-reap.test.sh's gate-notice cases.
- gc-helm.test.sh's demand and topic cases.

These tests are rewritten on gates rather than retired: escalate.test.sh,
await-ruling.test.sh, decline-wiring.test.sh, visit-close-wiring.test.sh (as the
ask-close wiring), finding.test.sh, finalize-gate.test.sh, merge.test.sh, the
prstatus tests, pr-facts.test.sh, gc-helm-engage.test.sh, gc-helm-accept.test.sh,
gc-helm-open.test.sh, gc-helm.test.sh's dismiss cases, converse-signoff.test.sh,
converse-reap.test.sh, pr-visit-comment.test.sh and its wiring test,
liveness-classify.test.sh, liveness-sweep.test.sh, the
`*-escalation-wiring.test.sh` set, pool-demand-wiring.test.sh, and the board's
Go and web tests. formula-marker-coverage.test.sh loses the gate-visit markers.

## 11. Migrating the open visits

The cutover runs a one-shot script once per store: the city store, and every rig
store the pack runs on, suspended rigs included. It has a dry-run mode, and the
test suite runs it against a fixture store. It is not a standing sweep. The
cutover deletes it once every store reports no open visit (section 12).

Before the first visit, it runs finding.sh close-answered on every anchor that
has a needs-you finding. Every finding a closed visit already released is then
released under the old rule, which the new finding.sh no longer reads.

For each open or in-progress visit, it does six things:

1. **It reads the subject and the key.** The subject is the visit's `tracks`
   target, else its `gc.continuation_group`. The key is its `escalation_key`,
   else `conversation`.
2. **A visit whose subject has closed still becomes a gate on it**, because the
   question it asks can outlive its subject. A subject that no longer exists is
   replaced by the rig's standing triage subject, as escalate.sh does for an
   ephemeral subject, and the framing names the missing id.
3. **A demand gate already asking the same thing becomes the question.** That is
   a gate with `gc.demand_for` naming the subject, one whose `gc.gate_visit`
   names this visit, or converse-hold's demand filed on the visit itself. Its
   await id becomes its `gc.demand_topic`, else `conversation`, and its title
   becomes its takeaway. A demand filed on the visit gains a `blocks` edge onto
   the subject, and the visit's own edge goes with the visit's close. Its pack
   keys are removed.
4. **Otherwise it files the gate through escalate.sh**, with the quiet period
   off. The title is the visit's headline, the framing is the visit's
   description, and the await id is the key. escalate.sh's dedup merges a visit
   into a gate already asking the same situation, so nothing is asked twice.
5. **It carries the visit's notes** onto the gate under a line naming the visit.
   It re-points `finding.visit` on needs-you findings to `finding.gate`, and
   `pr_comment_disposition=visit:<id>` to `gate:<id>`.
6. **It closes the visit** with the reason `migrated: gate <id>`.

A visit held by a live sitting is migrated like any other, and the gate is filed
unassigned. Then the script closes that sitting's session, so the operator
re-engages the subject on the new path. Last, it closes the "Human gate awaiting
you" notices still open in the city store, which nothing else will close once
the notify order is off.

**Nothing lost, nothing doubled.** Every open visit ends as an open gate, on its
subject or on the triage subject that stands in for a missing one. A rerun finds
each gate by its await id and only closes the visits left over. It reports, per
store, the visits it migrated and the ones it merged into a gate already there.

## 12. Cutover and the build

**The cutover order:**

1. **The town's city.toml turns off notify-on-human-gate-creation** (section 5),
   any time before step 3.
2. **The operator approves and merges this integration branch to main.** That is
   the one reviewed unit the initiative asks for.
3. **The rig checkout sync moves the pack to that main.** One pack serves every
   rig, so every rig switches at once. gate-visit-sweep's order disappears,
   escalate.sh files gates, converse claims gates, and the board reads gates.
   gate-visit-sweep stops at the same moment the board starts reading gates.
   Demand gates already on the board stay there, and the migration merges the
   visits the sweep made for them.
4. **The migration runs on every store, city first.** Until it finishes, open
   visits are not on the board, and a sitting that was live at step 3 is running
   an old prompt against new scripts. The migration ends that sitting after
   carrying its visit over.
5. **The operator checks** that no store has an open visit and that the board
   shows every question. A follow-up commit on main then deletes the migration
   script and its test. Unit D files that follow-up as a bead blocked on the
   cutover, so it is tracked from the start.

**How each rig cuts over.** Every rig's code switches together at step 3. Every
rig's store is migrated by its own run at step 4. A suspended rig's store is
migrated too, and its questions surface when the rig is resumed.

**The build is four beads onto integration/tk-iirrmiw, in this order.** Each is
its own PR on the branch, and each keeps the suite green. The convoy's
implementation child, tk-xgj6mg7, builds unit A. When it starts, it files units
B, C and D as members of this convoy, each blocked on the unit before it, as its
brief allows when the design calls for a split:

| Unit | What it carries |
|---|---|
| A. The writer and its callers | escalate.sh on gates. await-ruling.sh. first-reaction-dispose, mol-validate-close and mol-feedback-distiller on escalate.sh. gc-helm.sh demand retired. mol-visit and the formula copies of the gate-visit block retired. The polecat doctrine and pool-worker fragments, the ask-close fragment, and the deacon, refinery and witness prompts. The registry entries of the keys the writer stops writing. |
| B. The readers | finalize-gate. gctk merge and pr-status. finding.sh and review-answer.sh. pr-facts.sh. branch-supersession.sh. The liveness scripts, hold-lib.sh, deferred-dispatch.sh, bead-context.sh and pre-open-rebase.sh. orphan-dispose.sh and the witness patrol. bead-rehome.sh. The doctor checks, `RETIRED_KEYS`, and the docs that teach these components (section 13). |
| C. Converse and the board | The converse work query and prompt. The five converse skills and the shared skills. gc-helm.sh engage, open, accept and dismiss, with the copy of the gate-visit block in open. converse-signoff.sh rewritten, converse-reap re-keyed, and the converse scripts that retire. pr-sitting-comment.sh and operator-intake.sh. The tmux scripts. The board's source, derive, model, wire contract, web and text board. gate-visit-sweep's order and script. The human-engagement doc's converse sections and the board's README. |
| D. The cutover | The migration script and its test. notification-wisp-reap's gate pass retired. The cutover runbook in its own spec. The remaining docs. |

The order follows the dependency. B's readers read what A's writer files, and C's
sittings answer what A files and B reads. A, B and C each leave the integration
branch consistent for the suite, though not deployable before D. The branch is
never deployed until it graduates as a whole. Each of the four PRs is about one
subsystem. The single build is the alternative, at the cost of one PR across
every file this design names.

## 13. Sequencing with the siblings

**tk-1tfzr71.1 (the foundation rule) lands first,** as the epic says. Its branch
touches `docs/foundation.md`, `docs/gascity-local-patching.md` and
`agents/mechanik/prompt.template.md`. This build edits none of them. Both
re-render `generated/seed-audit/agents/mechanik.md`, because the mechanik prompt
includes the visit-close fragment. That is a generated-only conflict, settled by
re-rendering.

**tk-1tfzr71.3 (the docs split) and this design touch four files:**

- `docs/gascity-human-engagement.md`
- `docs/gascity-agents.md` (its conversations section)
- `docs/gascity-packs.md` (its visit mentions)
- `docs/gascity-reference.md` (its visit mentions)

The split decides where each fact lives, and this design decides what the visit
facts say. The split was slung before this design was written, so it is expected
to land first. Units B, C and D then edit the pages it leaves. If a unit
starts before the split lands, it edits the current page, and whichever lands
second takes the other's text in a bring-current merge.

**The other docs that teach visits are this design's to update,** in the unit
whose behavior they describe:

- Unit B: `docs/finalize-gate.md`, `docs/refinery-merge-cadence.md`,
  `docs/state-machine.md`, `docs/authority-map.md`, and
  `docs/component-model.md` (its primitives, invariants and placement rows).
- Unit C: `docs/gascity-human-engagement.md`, `docs/architecture.md` (how
  humans engage), and `services/helm/README.md`.
- Unit D: `docs/gascity-agents.md`, `README.md`, and every other doc that
  mentions visits: `docs/quota-park-recovery.md`,
  `docs/lifecycle-composition.md`, `docs/gascity-packs.md`,
  `docs/outbound-sends.md`, `docs/steering.md`, `docs/install.md`,
  `docs/bead-store-resolution.md`, `docs/deferred-dispatch.md`,
  `docs/review-correctness.md`, `docs/gascity-reference.md`,
  `docs/epic-stewardship.md`, `docs/review-demo.md`, `docs/product-goals.md`
  and `docs/feedback-learning.md`.

**The specs that record the visit design stay as written.** Among them are the
conversation-as-continuation-group design, the spine port, the converse claim
scoping, the hold model, the reap, the cutover and engage ordering, the gate
snippet, the guarded close, the finalize gate and the board's wrapper fold. They
are historical record by definition (`docs/file-structure.md`). The central docs
stop citing them as authority once they are rewritten, and this spec's
description names what it supersedes.

## Gap records

Each claim that Gas City cannot express something is dated and was re-verified
against upstream before it justified anything here. Each is answered by reshaping
the feature, not by a wrapper.

| Date | Claim | How it is answered |
|---|---|---|
| 2026-10-19 | `bd gate create` has no idempotency. | The writer reads `bd gate list` before it creates (section 2). |
| 2026-10-19 | Continuation preassignment applies only within one workflow root, so it never reaches a gate. | One session per subject. Engage assigns, and continue adopts new questions (section 6). |
| 2026-10-19 | Nothing native releases a gate claimed by a session that died. Orphan-sweep's listing hides gates, the dead-assignee release covers pool-routed work, and lease reclaim would rob a live held sitting. | Engage's conditional reassign naming the gone holder (section 6). |
| 2026-10-19 | A manual session is not ended when its work closes, and a pool sitting would be drained by the execution backstop while the operator reads. | converse-reap, keyed on gates. Its trigger is in section 6. |
| 2026-10-19 | `GC_ESCALATION_RECIPIENT` is one environment-wide mail recipient, and this city's operator reads the board. | The board is the reach, and core's two orders are off (section 5). |

This design adds no pack noun. It keeps one convention in a native field, the
outcome word at the head of a gate's close reason, because two readers need it:
finding release and the quiet period. It keeps one behavior in glue, the quiet
period, which mirrors core escalate's incident reminder.
