---
name: Converse on native human gates — the gate is the conversation
description: The design for tk-0ur8r9p, the design child of convoy tk-iirrmiw under initiative tk-1tfzr71.4. A question for the operator becomes one native human gate on the bead it is about, filed by escalate.sh, claimed by a sitting through its work query, answered by resolving the gate with the outcome at the head of its reason, and read directly by the helm board. The visit bead kind, the sweep that turned gates into visits, and the scripts that kept the two in step retire. It settles what a gate blocks and carries, the one writer, every caller and reader, how a question reaches the operator, the sitting's claim and ending, the board's read path, the skills and prompts, the retire list and keys, the migration of open visits, the cutover, the build breakdown and the sequencing with the epic's other members. It also records the platform facts it was verified against and the two premises of the ruling that did not hold, and it supersedes the specs that record the visit design. Read it to approve the design at its checkpoint or to build one of its units.
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
   id names the bead and the situation, its assignee is the sitting that holds
   it, and its close reason is the answer. It carries no pack metadata, and the
   visit bead kind goes. Cost: the gate blocks that bead, and a visit never did.
   Routed work waits for your answer. A question about a PR holds its merge,
   which an open visit already does today through the finalize gate. A question
   about an epic pauses the parts of it that have not started.
2. **escalate.sh is the one writer of questions.** It reads the bead's gates
   before it files, so each situation is asked once. It keeps the one-day quiet
   period after you call a situation moot or benign, and a filer can still
   withdraw its own unanswered question. gc-helm.sh demand, mol-visit and the
   five copies of the visit-filing block go. Cost: two situations on one bead are
   two gates. They fold into one board row and one sitting.
3. **Every caller keeps its call.** The escalate.sh call sites keep their flags,
   and the polecat decline stays escalate.sh, then await-ruling.sh, then
   run-cancel.sh. await-ruling.sh still makes the work bead wait on the
   question, releases the claim and arms the re-sling. When the question is
   about the work bead itself, the gate's own edge is the wait. When it is about
   another bead, as a rework child's bring-current question is about its anchor,
   await-ruling.sh adds the work bead's edge onto the gate. Only `--pool`
   retires. upstream-finding.sh forwards an option of its own to it, and
   reconcile-rig-checkouts.sh passes it when its pool knob is set, but no caller
   passes the option and nothing sets the knob. Cost: none at the call sites.
   Every reader that looked for a visit now reads the bead's gates.
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
   folds onto the bead it is about, and held, owed, engaged and the PR's
   needs-attention status read the gate where they read the visit. Accept
   answers only the question that put a recommendation to you. While another
   question still blocks the bead, the row offers Discuss and names that
   question. Cost: the board's default store reader gains a gate read that no
   test covers today. A recommendation beside another open question waits until
   that question is answered, where today's Accept closed every waiting question
   on the bead with one click.
8. **Cutover is one migration run per store, right after the pack update.** Each
   open visit becomes a gate on its subject, or joins the gate already asking the
   same thing, with its notes carried over. Work that waited on the visit waits
   on the gate, and every finding and routed PR comment that names a visit is
   pointed at what answers it now. Cost: for the few minutes until the migration
   has run and the board has been rebuilt, the board can miss an open visit or a
   new question, a ruled finding is not yet released, and a sitting live at
   cutover is ended and has to be engaged again.
9. **The build is four beads onto this branch, in order:** the writer and its
   callers, the readers, converse and the board, then the cutover. Cost: four PRs
   to review here instead of one.

## The platform this rides

Every fact below was read on 2026-10-19 against the installed gc 1.4.3 and bd
1.3.1, against Gas City's upstream source at 1e05ae624, and against its packs at
520e95cb2. The installed gc is built from a local commit that upstream does not
contain. Where a fact matters, it was read at upstream, and the core orders it
names are byte-identical in both. Gas City paths are relative to the Gas City
source tree at that commit, and bd paths to bd's v1.3.1 source.

| Mechanism | What this design uses it for | Where it was read |
|---|---|---|
| `bd gate create --type=human --blocks <bead> --title --reason --await-id` | Files a question. It adds one `blocks` dependency, so the target is blocked by the gate. The reason is appended to the description, after a line naming the target. No assignee, metadata or label can be set at create, and nothing dedups. No field names the target, so a `blocks` edge another bead adds onto the gate looks like the first. | bd `cmd/bd/gate.go` (flags 1282-1288, edge 352-368, description 411-437); `bd gate create --help` |
| `bd gate list <bead> --json` | Lists a bead's gates for the writer's dedup and for every reader. It returns the bead's outgoing dependencies of any type that are gates, with `await_type` and `await_id`. It lists every gate that is not closed, a claimed one included, unless `--all`, and at most 50 unless `--limit 0`. With no gates it prints `null`. | bd `cmd/bd/gate.go` 79-98 and `filterIssueGates` 129-144; `cmd/bd/gate_proxied_server.go` 450-488; `cmd/bd/output.go` 68-87 |
| `bd gate resolve <id> --reason` | The answer. It closes the gate with that close reason and recomputes `is_blocked` for the beads it blocked. | bd `internal/storage/issueops/close.go` 339-384; `bd gate resolve --help` |
| `bd close` refuses a blocked bead without `--force`, and a close removes none of the bead's dependency rows | A question holds its bead's close. A bead a gate blocks closes only once the gate closes or the edge is removed with `bd dep remove` (section 11). | bd `internal/storage/issueops/close.go` 150-160, and 339-384, where the close writes the row, drops the lease and recomputes its dependents' blocked state, and deletes no edge |
| A blocked parent's state cascades to its `parent-child` descendants | Why a question on an epic pauses its parts. | `docs/component-model.md`, I1's shape law |
| `bd ready` excludes gates, and a plain `bd list` hides them (`--include-gates` or `--type gate` shows them) | Why a sitting needs its own work query. | bd `internal/storage/sqlbuild/ready.go` 16-22; a live listing, 2026-10-19 |
| `bd update --claim` works on a gate, and is a compare-and-swap | The sitting's claim, and a filer's withdrawal of its own question, by `--retract` and by the finalize retry (sections 2 and 4). It sets `in_progress`, the assignee and a lease. It refuses a bead another actor holds, and it is idempotent for the actor that holds it. | bd `internal/storage/issueops/claim.go` 61-136, the lease at 197-205 |
| Agent `work_query`, and its three-tier default | Converse claims its gates. The default's first tier is a plain `bd list`, and its other two run `bd ready`. The current runtime takes no wake demand from a work query. | Gas City `internal/config/config.go` 3626-3643; `internal/config/workquery.go` 443-461, 605-612, 780-785; `cmd/gc/city_runtime.go` 3349-3352, 4625 |
| `gc hook --claim` claims an open bead already assigned to the session, of any type but `message`. It runs a custom `work_query` with `GC_ALIAS` and the session's other identities in its environment. | The sitting's first step (section 6). | Gas City `cmd/gc/cmd_hook_claim.go` 792-910, 1290-1300; `cmd/gc/cmd_hook.go` 428-481 |
| A manual session does not end when its work closes. It stays until it is closed or drained, and a wait hold or an idle-sleep setting only puts it to sleep. An attached session is woken even when drained, unless a wait hold is set. | Why converse-reap stays (section 6). | Gas City `cmd/gc/compute_awake_set.go` 432-440, 583-594, 668-693 |
| The pool execution backstop nudges, then drains, a pool session that holds in-progress work and is quiet for 90 seconds, with no attachment exemption | Why a sitting is not a pool session. | Gas City `cmd/gc/execution_backstop.go` 321-322, 405-421 |
| Core notify-on-human-gate-creation and renudge-stale-human-gates | Turned off in this city (section 5). Both act only on an open human gate, and mail its assignee, then `gc.deferred_assignee`, then `$GC_ESCALATION_RECIPIENT` (default `human`). | Gas City `internal/bootstrap/packs/core/assets/scripts/notify-on-human-gate-creation.sh` 1-80, 173-181; the town's city.toml 304-311 |
| Core escalate.sh hook and its incident reminder | Prior art for the writer's quiet period. It is a mail hook for maintenance scripts, and it is not this pack's writer. | Gas City `internal/bootstrap/packs/core/assets/scripts/escalate.sh` 1-22; `docs/getting-started/troubleshooting.md` 877-905 |
| A city's order override can set an exec order's environment | The alternative section 5 rejects. | Gas City `internal/config/config.go` 2383-2385; `internal/orders/override.go` 162-166; `cmd/gc/order_store.go` 229-235 |

Two premises of the ruling (tk-xexv7bo, turn 3) did not hold when they were
re-verified, and the design is reshaped around both. Each is recorded under
[Gap records](#gap-records).

- **`gc.continuation_group` does not reach a gate.** The hook claim preassigns
  open beads that share both `gc.root_bead_id` and `gc.continuation_group`
  (Gas City `cmd/gc/cmd_hook_claim.go` 3362-3372). The reconciler's backstop
  covers only task beads under a graph.v2 root
  (`cmd/gc/build_desired_state.go` 6453-6466, its checks at 6598-6612 and
  6659-6664). A gate has no workflow root, so same-subject continuity comes from
  one session serving one subject (section 6).
- **Nothing native releases a gate a dead sitting claimed.** Core's orphan-sweep
  lists in-progress beads with a plain `gc bd list`, which hides gates
  (`internal/bootstrap/packs/core/assets/scripts/orphan-sweep.sh` 89, 106), and
  an agent's default on_death release lists the same way
  (`internal/config/workquery.go` 1351-1378). Gas City's dead-assignee release
  covers pool-routed work (`cmd/gc/pool_session_name.go` 196-404). bd frees an
  expired lease only when something runs `bd reclaim`, and nothing in Gas City
  does: the hook claim's `auto_reclaim_stale_claims` setting would, but it is not
  wired at this commit (`cmd/gc/cmd_hook.go` 550-560). A lease lasts five
  minutes, which no config or flag changes (bd
  `internal/storage/issueops/lease.go` 19-42). A held sitting is quiet for hours,
  so lease reclaim would take a live sitting's question. Engage keeps its
  reclaim (section 6).

One more upstream fact frames the design. No upstream pack asks a human through
`bd gate create`. The build pack's human-gate steps park the session with
`gc session wait --sleep` and mail the human once
(`gascity/assets/workflows/github-pr-review/human-gate-comment.md` in the packs),
and Gas Town asks in the live conversation or escalates by mail
(`gastown/agents/witness/prompt.template.md` 332-341). So nothing upstream
competes with this use of human gates, and nothing upstream fills the board's
role.

## 1. What a conversation is

A conversation is one native human gate:

```
gc bd gate create --type=human --blocks <subject> --await-id <subject>:<key> \
  --title "<the question, at most 140 characters>" --reason "<the framing>"
```

**It blocks its subject**, the bead whose next step waits on the answer. bd
records the gate as a `blocks` dependency of the subject. The subject leaves
`bd ready` and the pool's offer until the gate closes, and `bd close` refuses it
while the gate is open. Three consequences follow, and the first decision above
asks the operator to accept them.

- **Routed work waits.** A visit never held its subject's readiness. Its
  `tracks` edge is non-blocking on purpose (`assets/scripts/escalate.sh`
  629-631, and the header of `assets/scripts/finalize-gate.sh`), and the
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

**Its await id** names the subject and the situation, as `<subject>:<key>`. The
key is the filer's `--key`, or `conversation` for a question the operator opens.
escalate.sh refuses a subject or a key outside `[A-Za-z0-9._-]`
(`assets/scripts/escalate.sh` 124, 133), so the colon splits the two. bd stores
the await id and returns it from `bd gate list`. bd's gate check skips human
gates (bd `cmd/bd/gate.go` 712-731), and core's two human-gate orders read a
gate's type, status, age and addressee, never its await id. So the pack's
meaning for a human gate's await id collides with nothing in the platform.
gc-helm.sh demand already names its gated bead in its await id
(`gc-demand:<gated>[:<topic>]`, gc-helm.sh 1442).

**Its subject is the bead its await id names**, and the gate blocks it. Other
beads can wait on the same question through `blocks` edges of their own, as a
rework child waits on the question its bring-current conflict filed on its
anchor (section 4). bd records what a gate blocks only as those edges, so the
await id is what tells the subject from a waiter. A reader that asks what a
bead's questions are keeps the human gates whose await id names that bead, as
the writer's dedup, engage, the board's fold and the migration do. A reader
that asks whether a bead waits on a person counts every open human gate the
bead depends on, as finalize-gate, gctk merge, the liveness classifier and
Accept do (section 8).

**Its assignee** changes across a question's life:

- **Waiting:** unassigned. The board shows the question owed and unengaged.
- **A task only a named person can perform:** assigned to that person through
  escalate.sh's `--assignee` (section 2), as `gc-helm.sh demand --assignee` does
  today. Engage leaves such a gate with its person.
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
| a `tracks` edge to the subject and `gc.continuation_group=<subject>` | its await id and its `blocks` edge, read with `bd gate list <subject>` |
| `escalation_key` | the key in its await id |
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
`conversation`. `--pool` retires, because a gate is not routed, and so do the
routes that forward it: upstream-finding.sh's own `--pool` (upstream-finding.sh
57, 411), and reconcile-rig-checkouts.sh's `RECONCILE_ESCALATION_POOL` knob,
which tries a pool before the board (reconcile-rig-checkouts.sh 166-169,
184-195). `--assignee` joins them for a task only a named person can perform,
which `gc-helm.sh demand --assignee` covers today and the waits skill teaches.
`bd gate create` sets no assignee, so the writer sets it with an update after
the create.

It files in five steps:

1. **It resolves the subject's store** with escalation-rig.sh, unchanged. A gate
   must sit in its subject's store, because a `blocks` edge across stores holds
   nothing (I1, `docs/component-model.md`).
2. **It redirects an ephemeral subject** (a wisp, or a subject proven to name no
   placeable bead) to the rig's standing triage subject, as today. The original
   id goes in the framing, so `escalation_raised_by` retires.
3. **It reads the subject's gates** with `bd gate list <subject> --all --limit 0
   --json`. A human gate with the same await id that is not closed, whether it
   waits or a sitting holds it, means the situation is already asked, so the
   writer prints that gate's id and exits 0. A gate the subject only waits on
   names another bead in its await id, so it never matches. This is the
   idempotency the ruling asks for. bd has none at create, so two writers racing
   in the same instant can both file. The board folds both, and the sitting
   answers both with one reason.
4. **It keeps the quiet period.** If the newest closed human gate with the same
   await id closed with a reason headed `moot:` or `benign:` less than
   `GC_ESCALATE_VERDICT_WINDOW` seconds ago (default 86400), it files nothing and
   says so. A caller whose question carries a wait passes 0, as today, because a
   wait needs an open gate to sit on.
5. **It files the gate** (section 1) and reads its id back.

`--retract` withdraws the filer's own question. It claims each human gate on the
subject with that await id that is not closed and is either unassigned or held
under the one actor name every retract claims with, then resolves it with the
reason `moot: <message>`. A gate a sitting holds is left alone, as today. The claim is
bd's compare-and-swap, so a gate a sitting engages after the read is left alone
too. The name is fixed because bd claims as its caller's actor, and Gas City
gives each order and each session its own `BEADS_ACTOR` (`cmd/gc/order_store.go`
197, `internal/session/lifecycle.go` 78). Under the caller's actor, a retract
from another caller could not claim a gate an earlier one holds. A retract
interrupted between its claim and its resolve leaves the gate held under the
fixed name, and the next retract for the situation completes it, because bd's
claim is idempotent for its holder.

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
| Dedup on `escalation_key` and `gc.continuation_group` (escalate.sh 393-461) | Step 3: the await id `<subject>:<key>`, among the gates `bd gate list <subject>` returns |
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
flags, except the `--pool` that upstream-finding.sh and
reconcile-rig-checkouts.sh forward. The column on the right is what changes
around the call.

| Caller | Its move |
|---|---|
| mol-polecat-work's decline arms: load-context's unreadable, parked and duplicate refusals; the blocked-work fallback; the unclear-requirements instruction; workspace-setup's malformed convoy, target guard, branch divergence and missing branch; the bring-current question through bring-current-audit.sh; submit's branch-shape, landing-target and hand-off refusals | The call is unchanged. The gate blocks the work bead, except for the bring-current question, which bring-current-audit.sh files on the anchor (bring-current-audit.sh 339) and whose wait await-ruling.sh adds as the work bead's own edge onto the gate (`formulas/mol-polecat-work.toml` 726, section 4). await-ruling.sh then releases the claim and arms the re-sling, and run-cancel.sh ends the run. The verdict window stays off where a wait follows. |
| `template-fragments/polecat-doctrine.template.md` (Escalation and the decline protocol) and `template-fragments/pool-worker-no-consent-ui.template.md` | The same three calls in the same order. The text says "the human gate escalate.sh files" where it said "the visit escalate.sh opens". Every polecat does what it does today. |
| mol-validate, mol-rig-demo, mol-refinery-patrol, mol-witness-patrol, mol-dog-shutdown-dance | Unchanged calls. mol-witness-patrol's check-refinery finds its open `witness-refinery-queue` questions with `bd gate list` and retracts them as today. |
| mol-deacon-patrol | It names escalate.sh in prose only. Its "becomes a visit" wording says the call files a question. |
| The deacon, refinery and witness prompts | Unchanged calls. The deacon prompt's stale "converse pool" default goes. |
| `template-fragments/visit-close.template.md`, which the deacon, mechanik, proactive, refinery and witness prompts include | Its `--retract` call is unchanged. The fragment is renamed (section 9). |
| pr-facts.sh, the merge-path families | Unchanged calls. It stops stamping `pr_url`, `pr_number` and `anchor_bead` on the comment and unengaged-thread questions, because the gate blocks the anchor. `visit_for`, the dispose refresh, the merge-blocked-approval retire, the retire on a disposed anchor and the write-back's awaiting and resolved replies read the anchor's gates by await id. The dispose retract after a landed close (`retract_dispose_visits`) goes, both its call at pr-facts.sh 1779 and the full-pass sweep that retries it (1298-1335). bead-rehome.sh withdraws the retry's own question before the close (section 4), so a landed close leaves none open. |
| gctk merge (one-anchor-per-pr, seed-audit-merge-gate) and record-failure-cap.sh | Unchanged calls. gctk merge reads a human gate on the anchor as a person's hold (section 4). |
| gate-ensure.sh, branch-supersession.sh, reconcile-rig-checkouts.sh, rejection-repool.sh | Unchanged calls. branch-supersession.sh's lookup reads gates. reconcile-rig-checkouts.sh's pool knob, `RECONCILE_ESCALATION_POOL` or its prior name `RECONCILE_MAYOR_ADDR`, retires with `--pool`, and so does its pool attempt that falls back to the board call (reconcile-rig-checkouts.sh 166-169, 184-195). Nothing sets the knob, so its call stays the board call it makes today. |
| deferred-dispatch.sh, liveness-sweep.sh, finding.sh | Unchanged calls. liveness-sweep.sh puts its recheck command in the message instead of stamping `visit.recheck`, and its disposition text names escalate.sh where it named `gc-helm.sh demand`. finding.sh records the gate's id (section 4). |
| upstream-finding.sh | Its own `--pool` option and the forwarding of it (upstream-finding.sh 57, 411) retire with escalate.sh's, and so do the cases in upstream-finding.test.sh that pin the forwarding. No caller passes the option, so every call is unchanged. |
| The gascity-keeper sub-pack's refinery fragment | Its call passes flags escalate.sh rejects, behind `|| true`. tk-vfgmu8k fixes it to escalate.sh's flags, and this design keeps those flags. |
| first-reaction-dispose.sh | escalate.sh with the key `first-reaction`. Its `--visit` option, which blocked the subject on a visit, retires. |
| mol-validate-close, mol-feedback-distiller | escalate.sh with their own keys (section 2). |
| gc-helm.sh engage and open, the operator's intake, helm-svc POST /helm/open | escalate.sh with the key `conversation` (sections 6 and 8). |
| The waits, prs and converse-settle skills | escalate.sh where they called `gc-helm.sh demand` (section 9). The waits skill's own escalate.sh call is unchanged. |

## 4. What an open or answered question means to other machinery

| Meaning today | Read by | After |
|---|---|---|
| **An open visit refuses its subject's finalization** | finalize-gate.sh `clause_no_open_visit`, run by gctk merge before approval and before the merge, and by bead-rehome.sh | The gate holds natively: gctk merge holds on a live blocker, and `bd close` refuses a blocked bead. The clause stays as an explicit precondition, re-expressed as "no open human gate blocks this bead", because a close path that passes `--force` skips bd's refusal. `--except-key` keeps its meaning: the caller's own questions under that key, held by nobody but the retry, do not hold the act they ask to retry. bd still refuses the close while they block the bead, so the retry withdraws them first (below). |
| **Any live bead carrying the PR's `pr_number` holds the merge**, which is how a PR-comment visit held its PR | gctk merge `inflightHolder` (merge.go 1509-1554) | No longer stamped on questions. The gate blocks the anchor. The probe stays for its other holders. |
| **The merge's machine state** | gctk merge's blocker classification (merge.go 553-567, `stuckHolder` 1582-1592) | It records a pool-routed blocker as progressing, an unrouted one as "an unrouted blocker no automated actor will clear", and nothing for a blocker routed to `human`, which is how a demand gate reads today (merge.test.sh 1307-1309). A gate carries no route, so gctk merge reads a gate whose await type is `human` as that person's hold and records no machine state. |
| **An open visit sets the PR's needs-attention status** | gctk pr-status `anchorOpenVisit` (`services/gctk/internal/cli/prstatus.go` 107-192) and `services/gctk/prstatus/prstatus.go` 121-123 | An open human gate on the anchor. |
| **The proceed ruling:** await-ruling.sh blocks the work bead on the visit and arms its re-sling | `assets/scripts/await-ruling.sh` | The wait is a `blocks` edge from the work bead onto the gate. await-ruling.sh finds the gate by its await id on the subject, which is `--subject` as today, else the work bead. When the work bead is the subject, the gate's own edge is the wait. When it is not, as for the bring-current question a rework child files on its anchor, await-ruling.sh adds the work bead's edge, because the child's `related` edge to its anchor holds nothing (`assets/scripts/bd-lib.sh` 195). Either way it reads the edge back before it releases the claim, clears the route and arms the re-sling, in today's order, so the re-sling cannot fire before the answer. It survives because a formula-slung bead needs the arm. Closing the gate makes the work bead ready, and only the arm re-slings it on its formula. |
| **Review release:** a needs-you finding is released only by a closed visit carrying `gc.ruling`, following `gc.folded_into` and `gc.superseded_by` | finding.sh close-answered, run by gate-ensure.sh; review-answer.sh; pr-facts.sh's review dismissal | finding.sh stamps the gate's id as `finding.gate`. A needs-you finding is ruled once that gate has closed with a reason headed `ruled:`, or once the finding records its ruling as `finding.ruling_bead`, which the migration writes for a finding whose visit was ruled before the cutover (section 11). Its release then waits, as today, until no fix unit on its lane and no ruling's rework child is live, and the close records the ruling's bead as `finding.ruling_bead`. It still follows `gc.superseded_by`. Gates do not fold (section 7), so the `gc.folded_into` hop retires. `finding.ruling_visit` becomes `finding.ruling_bead`, named like `source_ruling_bead` because it names a gate for a ruling given after the cutover and a visit for one given before. pr-facts.sh's review dismissal and review-answer.sh read it there. |
| **Liveness:** a subject covered by a live visit is conversing, and one named by `gc.demand_for` is held by design | liveness-classify.sh 113-149, liveness-sweep.sh, liveness-sweep-precheck.sh, liveness-recheck.sh | A bead blocked by an open human gate is held by design while no live sitting holds the gate, and conversing while one does. The sweep's live-visit guards read the subject's gates. |
| **Orphan disposal** | orphan-dispose.sh's visit arm; the witness patrol's recovery steps | The visit arm retires. Routed-human beads never reached it anyway (mol-witness-patrol.toml 245-250). salvage-scope-gate keeps treating a gate as not work. |
| **A ruling's rework child** | `source_ruling_bead` (rework-child.sh, gate-ensure.sh, duplicate-sweep.sh, liveness-sweep.sh, live-work.sh) | Readers unchanged. The value is the gate's id from now on. |
| **A PR comment's disposition** | `pr_comment_disposition=visit:<id>` (pr-facts.sh; doctor check-feedback-routing-owed) | `question:<id>`. pr-facts.sh reads the kind and the named bead's status (`conversation_fix_landed`, pr-facts.sh 186, and the write-back at 4332-4333). The migration rewrites every `visit:<id>` (section 11), naming the gate for a visit it migrated and the visit itself for one closed before the cutover, so the prefix names a question rather than a gate. |
| **Others** | bd-lib.sh's anchor children; bead-rehome.sh's outcome stamp on a visit it rehomes; pr-post.sh's recognition of the reminder's `gc:visit` marker, which pr-visit-comment.sh writes | The anchor children lose the visit. The stamp retires, because a gate is never rehomed, only its subject. pr-post.sh recognizes the reminder's new marker (section 7). |

**A retry withdraws its own question before it closes.** pr-facts.sh is the one
caller of `--except-key`, through bead-rehome.sh. It closes an anchor whose PR
was closed with a pre-recorded disposition, and on every attempt it names the
key under which it reports a refused close (pr-facts.sh 1758-1768). Today that
report is a visit, whose `tracks` edge blocks nothing, so the close goes through
once finalize-gate excepts it.
A gate blocks its subject, and bd refuses an unforced close while it is open
(bead-rehome.sh 553-563 closes unforced). So bead-rehome.sh closes in these
steps:

1. **It reads what would hold the close.** finalize-gate runs with
   `--except-key` as today. bead-rehome.sh also reads the bead's live blockers
   and open children, which are what an unforced `bd close` refuses on. Anything
   other than the bead's own questions under that key holds the close, and so
   does any of those questions held by anyone but this retry. Then it claims,
   resolves and closes nothing, and the bead stays open with its successor
   pointer recorded, as a held close leaves it today.
2. **It claims each excepted question** with `bd update --claim`, under one
   actor name that the retry always uses. The claim is bd's compare-and-swap, so
   a question someone engaged after the read refuses it. The retry then releases
   whatever it claimed and holds the close. A question an interrupted pass left
   claimed is claimed again, because bd's claim is idempotent for its holder.
3. **It resolves each claimed question** with a reason that names the retry and
   carries no outcome word. The retry has not shown the premise gone yet, so the
   quiet period does not start.
4. **It closes the bead**, unforced, as today.

Only a blocker or an open child that appeared after step 1 can refuse step 4.
The bead then stays open with its question withdrawn, and pr-facts.sh files its
report again under the same key, which nothing mutes. A pass that stops between
two steps leaves a state the next pass completes. A question someone else holds
and every unrelated blocker still hold the close, because step 1 reads them and
step 2 cannot claim a question another actor holds.

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
- **check-feedback-routing-owed** reads only whether a disposition is present,
  so only its comments change.
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
filer withdraws it, or, for the question that put a recommendation to the
operator, Accept answers it (section 8). Nothing re-mails. A question held by a
sitting is in progress, and both core orders skip it anyway.

**notification-wisp-reap keeps one pass.** Its gate-notice pass retires with the
notify order. Its second pass collapses repeated `ESCALATION:` mails that core's
maintenance escalations send. Those are not human gates, so that pass stays.

`docs/gascity-human-engagement.md` contradicts itself on this point. Lines
224-229 say to ride core's notify and renudge orders, and lines 493-495 stamp
the gate identity so that those orders fire. Lines 531-533 say the visit is the
reach. Both statements are rewritten to say that the board is the reach and that
core's two orders are off in this city.

The alternative was to keep the orders and give them an addressee someone reads.
The town can point the two orders at another recipient by setting
`GC_ESCALATION_RECIPIENT` in an order override's environment (see the platform
section). Any recipient is still a mailbox or a session, and the operator reads
neither. They have no session to nudge, and pointing the orders at an agent would
wake that agent on every question. The alternative was rejected.

## 6. The sitting and its claim

**A sitting is a manual session of the converse agent the operator chose.**
Engage starts it as today: `gc session new converse-<model> --alias <subject>
--no-attach`. The alias becomes the subject's id instead of the visit's, so a
subject has at most one sitting, and engaging a subject that already has a live
sitting attaches to it. For an id the runtime refuses as an alias, the existing
`v-` prefix fallback stays.

**Engage assigns the sitting the subject's questions.** It assigns every open
human gate whose await id names the subject, and that is unassigned or held by a
session no longer in `gc session list`, to the new session. Each assignment is a
conditional update, `--if-assignee ""` or `--if-assignee <the gone holder>`, so
a race with another engage loses cleanly. A gate assigned to a named person
stays with that person. A gate the subject only waits on is another bead's
question, and engage leaves it to that bead's sitting.
Then engage attaches the operator. If the subject has no open question, engage
first files the conversation through escalate.sh.

**The sitting claims through its work query.** Each converse agent gains a
`work_query` (config, the epic's first test) that serves the open human gates
assigned to the session, for example
`gc bd list --type=gate --assignee="$GC_ALIAS" --status=open,in_progress --json`
filtered to `await_type` human. Gas City's default query cannot serve a gate.
Its second and third tiers run `bd ready`, which excludes gates, and its first
tier's plain `bd list` hides them. The new query spawns nothing, because the
current runtime takes no wake demand from a work query and a gate carries no
route. The sitting's first step is a plain `gc hook --claim --json`, which claims
an assigned gate: it sets `in_progress`, a lease and the session stamps.
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

**converse-reap stays, keyed on gates.** Gas City does not end a manual session
when its work closes. It stays until it is closed or drained. A sitting cannot
drain itself at its sign-off: an attached operator's pane would be destroyed,
and the attached override would wake the session straight back up. A pool
session would end on its own once its work closed and nobody was attached. But
the pool execution backstop drains a pool session that holds in-progress work
and is quiet for 90 seconds, with no attachment exemption, and a sitting is
quiet whenever the operator is reading or thinking. So sittings stay manual
sessions, and converse-reap closes an unattached converse session that holds no
open human gate.
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

A hold does not use `gc session wait --sleep`. That command sets a wait hold, and
the controller then drains the session (Gas City `cmd/gc/cmd_wait.go` 406-416),
which would destroy an attached operator's pane. While the hold is set, the
controller does not count an attachment as a reason to wake the session
(`cmd/gc/compute_awake_set.go` 591). Upstream uses it for an
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
so converse-close-out.sh retires. The board's sittings card already falls back to
a closed sitting's reason for its headline when the sitting left no takeaway
(`services/helm/internal/board/model.go` 658-669), and it reads the gate's close
reason there instead.

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
never hold the same question, so the holder lookup has nothing to find. Engage
takes only the gates whose await id names its subject, so the sitting of a bead
that waits on another bead's question never takes that question. A
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
bead its await id names (section 1). Any other bead it blocks is a waiter, whose
row lists the gate among what it waits on, as a bead blocked by a visit lists
the visit today (`waitingSplit`, `services/helm/internal/board/derive.go` 317).
`visitFilter`, `resolveVisitSubjects` and the visit-identity spelling retire.

**How a gate folds.** `wrapperTarget` (derive.go 2571-2595) treats a human gate
as the wrapper and the bead its await id names as the subject, so a gate with
waiters still folds onto one row. `applyFold` keeps its meanings:

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

**Accept answers the recommendation's question and nothing else.** A
recommendation is `gc.recommended_formula` on the subject. Only
first-reaction-dispose.sh's recommend exit sets it (first-reaction-dispose.sh
822-841), and that exit files the question that puts it to the operator through
escalate.sh with the key `first-reaction` (section 2). So the recommendation's
gate is the subject's open human gate with the await id
`<subject>:first-reaction`, or both of them when a race filed two. The `--visit`
option, which held a recommendation on a question the caller filed, retires
(section 3), so no recommendation rides on another question. A subject whose
recommendation has no open gate under that await id offers Discuss only, because
nothing asks the operator to accept it.

Accept is offered while all three hold:

1. The subject carries `gc.recommended_formula`.
2. The recommendation's gate is open and unassigned. A gate a sitting holds is
   that sitting's to answer, even when the sitting has died, because only
   engage's conditional reassign takes a gate from its holder (section 6).
3. No other open human gate blocks the subject. That counts the subject's own
   questions under any other key, the questions it waits on that name another
   bead, a gate a sitting holds and a gate assigned to a person.

**Why Accept answers one gate.** Separate situations on one bead stay separate
gates (section 2), and each gate's close does something of its own. A `ruled:`
close releases a needs-you finding (section 4). Any close releases what waits on
the gate, so a rework child waiting on its anchor's bring-current question would
be re-slung without the decision it waits for. An Accept that resolved every gate
on the subject would spend one click as several answers the operator never gave.
Today's Accept already closes every waiting question on the subject. It resolves
every open, unassigned demand there (gc-helm.sh 2830-2849) and dismisses every
visit (3151-3156). A dismissed visit carries no `gc.ruling`, so a needs-you
finding whose visit Accept dismissed stays held with its question gone from the
board. Carried over to gates, the same sweep would close the finding's gate with
`ruled:` and release the finding on a ruling nobody gave.

**Why it waits for the others.** Every gate blocks its subject, so the subject's
next step waits for each answer (section 1). A formula sling reads no `blocks`
edge (`docs/gascity-routing-model.md`, "A `blocks` dep between work beads does
not hold a graph.v2 dispatch"). An Accept that resolved only its own gate while
another stayed open would start the work before that question was answered.
mol-polecat-work's load-context would cancel such a run, and a formula with no
such check would run past the question. So Accept is offered only once the
recommendation's question is the last question blocking the subject.

While another question blocks the subject, the row offers Discuss, and the wire
field `accept_withheld` names each open question that holds Accept back. Discuss
engages the subject, and its sitting answers each of the subject's questions on
its own terms. A question the subject only waits on is answered in its own
bead's sitting. Once the others are answered or withdrawn, the row offers Accept
again if the recommendation's gate is still open and unassigned.

gc-helm.sh accept re-reads the three conditions live before it writes anything,
because a board row can be stale and a command can be copied. When one fails, it
refuses and writes nothing. When the third fails, the refusal names each open
question by id and title, with Discuss as the way forward. Otherwise it resolves
the recommendation's gate with `ruled: accepted <formula>`, reads back that no
open human gate blocks the subject, and slings. A question filed between the
read and the resolve shows in that read-back, and a sling can fail. Either way
Accept reopens the recommendation's gate, and nothing is dispatched. The resolve
comes before the sling, today's order (gc-helm.sh 3110-3138), so the run never
finds the recommendation's own gate open. The dispatch is recorded as today:
`gc.recommended_formula_dispatched` lands in the write that strips
`gc.recommended_formula`. A re-run that finds the marker skips the three
conditions, since the run that wrote it already answered the gate. It finishes
that record and never slings again. Accept no longer runs dismiss. The one gate
it answers is one no sitting holds, so it has no sitting to end.

**Ranking is unchanged.** `rankScore` (derive.go 734-741) and its inputs are
untouched. Every input a visit supplied, held and the owed clock among them, now
comes from the gate. A board test pins that a subject ranks the same with a gate
as it did with a visit.

**The wire model.** In `services/helm/internal/board/model.go` and
`services/helm/web/src/contract.ts`, `held`, `accept_formula` and
`recommendation` keep their meaning, and `acceptable` reads Accept's three
conditions. `accept_withheld` is new. It is set on a row that meets Accept's
first two conditions and fails the third, and it names the questions that fail
it the way Needs names gates: the gate's title, or `N× — a · b` over several. It
is null on every other row. The web and text boards print it beside Discuss as
the reason Accept is not offered. `visit_state` is renamed `sitting_state`. The
web marker reads "in session" or "waiting" without the word visit. The sittings
card reads gates. gctk pr-status's `OpenVisit` phase input reads an open human
gate.

**The verbs** (gc-helm.sh, and helm-svc's POST routes that run it):

| Verb | After |
|---|---|
| engage, `--new-subject` | Section 6. `--new-subject` still creates the subject first (gc.origin=operator), then engages it. A concern passed to engage with `--reason`, `--template` or `--skill` is filed the way open files it. |
| open (POST /helm/open) | Files the conversation through escalate.sh without engaging. `parseOpenStdout` keeps its sentences. `--allow-duplicate`, which engage passes today to file a second visit, retires. A bead has one conversation question, so a second concern on a bead whose conversation question is open joins it: escalate.sh returns that gate, and open appends the new reason and body to the gate's notes. |
| accept (POST /helm/accept) | Resolves only the recommendation's gate, then slings, as above. While another question blocks the subject, it refuses, writes nothing and names each open question. It runs no dismiss. |
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
| `skills/converse-prep` | It reads the gate with its notes, and the subject's notes. A recheck command named in the framing is run, in place of the `visit.recheck` hook. |
| `skills/converse-hold` | The hold of section 7, in place of converse-hold.sh, the visit demand and `--hold-merge`. The dismiss line at the foot of every framing stays. |
| `skills/converse-settle` | converse-signoff.sh's new shape. The resolve replaces visit-close.sh and the guarded stamps, and the reminder update passes its text directly. A cross-store follow-up waits through escalate.sh. |
| `skills/converse-continue` | It re-runs `gc hook --claim` and adopts any new question on its subject. |
| `skills/waits` | One section on asking a person: escalate.sh files a human gate, and await-ruling.sh arms the re-sling. The demand-gate, visit and gate-visit-sweep sections go. |
| `skills/prs` | A merge hold is a question on the anchor through escalate.sh. The not-needed successor names the gate. |
| `skills/work` | Accept and the intake are described on gates. Taking a recommendation in a sitting answers the recommendation's gate alone, as Accept does, and its sling waits until no other question blocks the bead (section 8). "Ask for a visit" becomes "ask the operator". |
| `skills/handoff` | A converse session resolves or releases its gates before it drains. |
| `skills/learning-distill` | The contention question goes through escalate.sh. |
| `agents/_converse/prompt.template.md` | Its definitions of visit, subject, topic and demand become one definition of a question. The claim block becomes `gc hook --claim`. The BEGAN rules, the fold and the finish arm go. The ending says the thread ends when its questions are answered or dismissed. |
| `agents/converse-{opus,fable,codex}/agent.toml` | They gain the work query. Their header comments say the alias is the subject. |
| `template-fragments/visit-close.template.md` | Renamed `ask-close.template.md`, and its `define` with it, so the include line in each prompt that includes it changes: the deacon, mechanik, proactive, refinery and witness prompts. A role never resolves another role's question, and withdraws its own with `--retract`. |
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
| visit-identity.sh | Retires, with its Go readings: gctk pr-status's `visitCovers` and the board's `resolveVisitSubjects`. gcbd's `DependsOn`, which only `visitCovers` calls, goes with the `gcbd_test.go` case that pins its edge spellings. |
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
`RETIRED_KEYS` in `doctor/check-state-space/run.sh`. The migration script reads
some of these keys on the beads it converts: `escalation_key`,
`gc.demand_for`, `gc.demand_topic`, `gc.gate_visit`, `gc.ruling`,
`gc.folded_into`, `finding.visit` and `finding.ruling_visit` (section 11). It
also sets `gc.gate_visit` on a demand until the demand's visit has closed. It
is the last script to use them, so they stay registered until the follow-up
that deletes the script retires them (section 12).

| Key | Fate | The readers that move first |
|---|---|---|
| `gc.gate_visit` | Goes. The migration sets it on a demand while the demand's visit is open, so a rerun finds the demand, and then removes it (section 11). | gate-visit-sweep.sh |
| `gc.hold_demand` | Goes. | converse-claim.sh, converse-signoff.sh |
| `gc.ruling` | Goes. The migration reads it once, on closed visits, to carry a ruling given before the cutover onto its finding (section 11). | finding.sh close-answered, which reads the close reason or `finding.ruling_bead` |
| `gc.folded_into` | Goes. The migration's walk reads it once, on closed visits (section 11). | finding.sh, visit-close.sh |
| `gc.pr_visit_summary`, `gc.pr_visit_actions` | Go. | pr-visit-comment.sh |
| `visit.recheck` | Goes. | converse-recheck-hook.sh. Its writer, liveness-sweep.sh, puts the command in the message. |
| `escalation_key` | Goes. The key in the await id carries it. | await-ruling.sh, branch-supersession.sh, pr-facts.sh, finding.sh, finalize-gate.sh `--except-key`, mol-witness-patrol's check-refinery, converse-hold.sh, converse-signoff.sh, converse-fold.sh, the formula copies |
| `escalation_raised_by` | Goes. | None. It is never read. |
| `escalation.recurrences`, `escalation.recurrence_last` | Go. | escalate.sh's tally |
| `triage.scope` | Stays. | The triage subject is not a visit. |
| `triage.last_seen` | Stays. Its registry text is corrected: it holds the in-scope ids, not a time. | |
| `triage.hold` | Stays. It has readers outside visits and no writer, and its retirement belongs to the liveness subsystem. | |
| `gc.outcome` and `gc.outcome_reason` on visits | Go. `gc.outcome` on molecule steps stays. | The board's sittings headline. Their writers stop with it: visit-close.sh, gc-helm.sh dismiss, and bead-rehome.sh on a visit it rehomes. |
| `finding.visit` | Renamed `finding.gate`. The migration converts it on every live finding (section 11). | finding.sh, review-answer.sh |
| `finding.ruling_visit` | Renamed `finding.ruling_bead`. The migration renames it on every finding that carries it (section 11). | pr-facts.sh's review dismissal, review-answer.sh |
| `source_ruling_bead` | Stays. Its value is the gate's id from now on. | |
| `epic_ruling_evidence` | Stays. Its value is the gate's id from now on. | |
| `pr_number`, `pr_url`, `anchor_bead` as stamped on visits | No longer stamped on questions. The keys stay on anchors and their children. | gctk merge's `pr_number` probe, gctk pr-status's in-flight count |
| `gc.demand_for` | Goes. | gc-helm.sh, its writer; converse-claim.sh, converse-signoff.sh and gate-visit-sweep.sh; liveness-classify.sh, with liveness-sweep.sh and liveness-sweep-precheck.sh, which source it; liveness-recheck.sh; hold-lib.sh, with deferred-dispatch.sh through it; live-work.sh; pr-facts.sh; pre-open-rebase.sh; the board; check-blocked-work-armed; check-wait-is-an-edge's `terminal_wait_key` |
| `gc.demand_topic` (written and read, never registered) | Goes. | gc-helm.sh demand, converse-signoff.sh |
| `gc.routed_to=human` and `gc.takeaway` on gates | No longer stamped on gates. Both stay the subject-level markers they are. | A reader that told a visit or a demand by its route, such as bead-context.sh, reads the gate's await type instead. |
| `gc.continuation_group` | Stays, for molecule steps. Its registry text, which describes the visit's fence, is rewritten. | |
| `pr_comment_disposition=visit:<id>` | Becomes `question:<id>`. The migration rewrites every one (section 11). | pr-facts.sh |

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
await-ruling.test.sh, which adds the waiter's edge for a subject that is not the
work bead, decline-wiring.test.sh, visit-close-wiring.test.sh (as the
ask-close wiring), finding.test.sh, finalize-gate.test.sh, bead-rehome.test.sh,
which adds the retry's withdrawal before the close, upstream-finding.test.sh,
whose `--pool` cases go, reconcile-rig-checkouts.test.sh, whose unroutable-pool
run goes, review-answer.test.sh, merge.test.sh, the
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

For each open or in-progress visit, it does the following, in this order. Each
write is read back before the next, and the visit closes last, so a run that
stops part way leaves the visit open for the rerun to finish:

1. **It reads the subject and the key.** The subject is the visit's `tracks`
   target, else its `gc.continuation_group`. The key is its `escalation_key`,
   else `conversation`.
2. **A visit whose subject has closed still becomes a gate on it**, because the
   question it asks can outlive its subject. A subject that no longer exists is
   replaced by the rig's standing triage subject, as escalate.sh does for an
   ephemeral subject, and the framing names the missing id.
3. **A demand gate already asking the same thing becomes the question.** That is
   a gate with `gc.demand_for` naming the subject, one whose `gc.gate_visit`
   names this visit, or converse-hold's demand filed on the visit itself. The
   script first sets the demand's `gc.gate_visit` to this visit, so a rerun
   that finds the visit still open finds the demand by it. The demand's await
   id becomes `<subject>:<topic>`, where the topic is its `gc.demand_topic`,
   else `conversation`. `bd update --await-id` writes it, and the gate's title
   becomes its takeaway. Its other pack keys are removed, and `gc.gate_visit`
   stays until the visit has closed.
   converse-hold's demand carries the visit's own key as its topic
   (converse-hold.sh 187-189), so a held visit and its demand become one
   question. converse-hold files that demand on the visit itself when the
   subject is a PR anchor (converse-hold.sh 210-213, 234-244), so it blocks the
   visit, not the subject. bd refuses to close a blocked bead and keeps a closed
   bead's edges, so the demand's edge moves before the visit can close. The
   subject's `blocks` edge onto the demand is added and read back. Then the
   visit's edge onto it is removed with `bd dep remove`, and read back as gone.
4. **Otherwise it files the gate through escalate.sh**, with the quiet period
   off. The title is the visit's headline, the framing is the visit's
   description, and the await id is `<subject>:<key>`. escalate.sh's dedup
   merges a visit into a gate already asking the same situation, so nothing is
   asked twice.
5. **It moves the waits.** Every bead that waits on the visit through a `blocks`
   edge gets the same edge onto the gate, and so does every bead whose `until`
   edge names the visit. Each is read back. That covers await-ruling.sh's work
   beads, first-reaction-dispose.sh's `--visit` holds,
   `gc-helm.sh takeaway --waiting-on` and edges placed by hand. Left on the
   visit alone, a `blocks` wait would release its work when step 7 closes the
   visit, before anyone has answered, and an `until` edge would dispose its bead
   as resolved. The old edges stay, and hold nothing once the visit is closed.
6. **It carries the visit's notes** onto the gate under a line naming the visit,
   unless the gate's notes already carry that line.
7. **It closes the visit** with the reason `migrated: gate <id>`, unforced. A
   visit bd still refuses, because something other than the moved demand blocks
   it, stays open and is reported. Nothing is forced.

**A human gate no visit stands for is re-pointed too.** gate-visit-sweep files
no visit for a gate assigned to a person, a gate whose gated bead has closed, or
a gate stamped `gc.gate_visit=skip` (gate-visit-sweep.sh 17-28). After the
visits, the script gives each open human gate whose await id does not yet name
its subject the shape step 3 gives a demand. Its subject is its
`gc.demand_for`, else the one bead it blocks, its await id becomes
`<subject>:<topic>`, and its pack keys are removed. A gate that blocks several
beads and names none of them is reported and left for a person. The same pass
removes the `gc.gate_visit` that step 3 left on a demand whose visit has closed.

**Every live reference to a visit is re-pointed, after the visits.** The records
in the table below name a visit and are read after the cutover. A finding can
name a visit that a fold or a re-home closed, so for a finding the script walks
from the named visit to the one that holds the question now, as finding.sh's
`ruled_visit` does today (finding.sh 1262-1281). The walk follows
`gc.folded_into`, `gc.superseded_by` and the `migrated: gate <id>` close reason
the script writes, so it runs after the visit pass, and a rerun converts what an
earlier pass left. The walk is a copy inside the script, because when the script
runs the pack's finding.sh no longer reads visits. It is deleted with the
script. A disposition's reader reads only the status of the bead it names, so a
disposition follows only the `migrated: gate <id>` reason.

| Reference | Read after the cutover by | The script writes |
|---|---|---|
| `finding.visit` on an open needs-you finding | finding.sh close-answered, which gate-ensure.sh runs every pass | Where the walk ends at a gate, through a visit the script migrated, `finding.gate`, naming that gate. Where it ends at a visit closed with `gc.ruling`, `finding.ruling_bead`, naming that visit, and the finding stays open. close-answered then releases it once no fix unit on its lane and no ruling's rework child is live, as it does today (finding.sh 1372-1396), so a ruled finding whose rework is still in flight stays held until the rework lands. Where it ends at a visit closed with no ruling, nothing has answered the finding, as today, and its notes name the visit. `finding.visit` is removed in every case. Where the walk ends at a gate, a `finding.reply` not yet posted that names the visit is rewritten to name the gate. |
| `finding.ruling_visit` on a closed finding | pr-facts.sh's review dismissal, which counts a needs-you finding as answered only when it records its ruling (pr-facts.sh 4745, 4794), and review-answer.sh | Renamed `finding.ruling_bead`, with its value kept, on every finding that carries it, so a review whose findings were released before the cutover is still dismissed. |
| `pr_comment_disposition=visit:<id>` on an anchor | pr-facts.sh, which reads the kind and the named bead's status (section 4) | `question:<id>`, naming the gate for a visit the script migrated, and the visit itself for one closed before the cutover. |

Until the script has run on a store, the new readers find none of them, so they
release nothing early. For those minutes a needs-you finding stays held and a
routed comment reads as unanswered.

A visit held by a live sitting is migrated like any other, and the gate is filed
unassigned. Then the script closes that sitting's session, so the operator
re-engages the subject on the new path. Last, it closes the "Human gate awaiting
you" notices still open in the city store, which nothing else will close once
the notify order is off.

**Nothing lost, nothing doubled.** Every open visit ends as an open gate, on its
subject or on the triage subject that stands in for a missing one, and every
bead that waited on the visit waits on that gate. A rerun finds each gate again.
escalate.sh's dedup finds a gate step 4 filed by its await id on the subject,
and step 3 finds a demand by the `gc.gate_visit` it set first, which names the
visit until the visit has closed. The rerun adds only the edges, notes and
references still missing, removes a visit's edge onto a moved demand if it is
still there, and closes only the visits left over. It reports, per store, the
visits it migrated, the ones it merged into a gate already there, and any it
could not close. Its test stops a run after each write and reruns it. After
every rerun, each open visit has become one gate with its waits and references
moved, and every visit but the ones the report names is closed.

## 12. Cutover and the build

**The cutover order:**

1. **The town's city.toml turns off notify-on-human-gate-creation** (section 5),
   any time before step 3.
2. **The operator approves and merges this integration branch to main.** That is
   the one reviewed unit the initiative asks for.
3. **The rig checkout sync moves the pack to that main.** One pack serves every
   rig, so every rig switches at once. gate-visit-sweep's order disappears,
   escalate.sh files gates, and converse claims gates. The board and gctk are
   built binaries, so they switch when the helm-build and gctk-build orders next
   rebuild them, inside their five-minute cooldown. The cutover runs both orders
   by hand with `gc order run` as soon as the pack moves, so the old board's
   window is one build long. Until the new board is up, the old one reads visits
   and does not read the new gates as questions. Demand gates already on the
   board stay there, and the migration merges the visits the sweep made for
   them.
4. **The migration runs on every store, city first, once the new board is up.**
   Until it finishes, open visits are not on the board, a ruled finding and a
   routed comment that name a visit wait for it, and a sitting that was live at
   step 3 is running an old prompt against new scripts. The migration ends that
   sitting after carrying its visit over.
5. **The operator checks** that no store has an open visit and that the board
   shows every question. A follow-up commit on main then deletes the migration
   script and its test, and retires the keys only the script still read
   (section 10). Unit D files that follow-up as a bead blocked on the cutover,
   so it is tracked from the start.

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
| A. The writer and its callers | escalate.sh on gates, with the subject in the await id and the claimed retract. await-ruling.sh, with the waiter's edge. upstream-finding.sh's `--pool` and reconcile-rig-checkouts.sh's pool knob retired. first-reaction-dispose, mol-validate-close and mol-feedback-distiller on escalate.sh. gc-helm.sh demand retired. mol-visit and the formula copies of the gate-visit block retired. The polecat doctrine and pool-worker fragments, the ask-close fragment, and the deacon, refinery and witness prompts. The registry entries of the keys the writer stops writing. |
| B. The readers | finalize-gate. gctk merge and pr-status. finding.sh and review-answer.sh. pr-facts.sh. branch-supersession.sh. The liveness scripts, hold-lib.sh, deferred-dispatch.sh, bead-context.sh and pre-open-rebase.sh. orphan-dispose.sh and the witness patrol. bead-rehome.sh, with the retry's withdrawal before the close. The doctor checks, `RETIRED_KEYS`, and the docs that teach these components (section 13). |
| C. Converse and the board | The converse work query and prompt. The five converse skills and the shared skills. gc-helm.sh engage, open, accept and dismiss, with the copy of the gate-visit block in open. Accept on the recommendation's gate alone, pinned by the acceptance case below. converse-signoff.sh rewritten, converse-reap re-keyed, and the converse scripts that retire. pr-sitting-comment.sh and operator-intake.sh. The tmux scripts. The board's source, derive, model, wire contract with `accept_withheld`, web and text board. gate-visit-sweep's order and script. The human-engagement doc's converse sections and the board's README. |
| D. The cutover | The migration script, with its copy of the visit walk, and its test, which stops a run after each write. notification-wisp-reap's gate pass retired. The cutover runbook in its own spec. The remaining docs. |

The order follows the dependency. B's readers read what A's writer files, and C's
sittings answer what A files and B reads. A, B and C each leave the integration
branch consistent for the suite, though not deployable before D. The branch is
never deployed until it graduates as a whole. Each of the four PRs is about one
subsystem. The single build is the alternative, at the cost of one PR across
every file this design names.

**Unit C's acceptance case: a recommendation beside a review question.** The
fixture is one anchor with two open questions. A first reaction's recommend exit
filed `<anchor>:first-reaction` and stamped `gc.recommended_formula`, and
finding.sh filed a needs-you finding's question as
`<anchor>:review-needs-you.<finding>` (finding.sh 918-924).
gc-helm-accept.test.sh and the board's derive tests pin each step:

1. **The board withholds Accept.** Both gates fold onto the anchor's row, and
   Needs prints both titles. `acceptable` is false, and `accept_withheld` names
   the review question.
2. **A stale Accept refuses.** `gc-helm.sh accept <anchor>` exits non-zero and
   names the review question. Both gates stay open, the finding stays held,
   `gc.recommended_formula` stays, and nothing is slung.
3. **Discuss answers the review question.** Engage assigns the sitting both
   gates. The sitting rules the review question, and that `ruled:` close is what
   releases the finding (section 4). The operator leaves the recommendation, so
   the sign-off releases its gate unanswered.
4. **Accept answers the recommendation alone.** With the recommendation's gate
   the last one open and nobody holding it, the row offers Accept, and
   `accept_withheld` is null. Accept resolves that gate with
   `ruled: accepted <formula>`, slings the formula and records the dispatch. The
   review question's close reason is still the sitting's ruling.
5. **A late question stops the dispatch.** A question filed after Accept's live
   read and before its resolve shows in the read-back. Accept reopens the
   recommendation's gate, and nothing is slung.

A second fixture makes the other question one the anchor only waits on. Its
await id names another bead, and the anchor waits on it through a `blocks` edge
of its own. That question folds onto its own bead's row, and the anchor's row
lists it among what it waits on. Accept is withheld the same way, with
`acceptable` false and `accept_withheld` naming that question. A stale
`gc-helm.sh accept <anchor>` refuses, names that question and slings nothing.

## 13. Sequencing with the siblings

**tk-1tfzr71.1 (the foundation rule) lands first,** as the epic says. Its branch
touches `docs/foundation.md`, `docs/gascity-local-patching.md` and
`agents/mechanik/prompt.template.md`. This build edits only the last of them, at
its visit-close include (line 181), which the foundation branch's hunks at lines
185 and 189 do not touch. Both re-render
`generated/seed-audit/agents/mechanik.md`, because the mechanik prompt includes
the fragment. That is a generated-only conflict, settled by re-rendering.

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
| 2026-10-19 | A gate records what it blocks only as `blocks` edges. No field names the bead it was filed for, and a bead that waits on the question adds an edge just like the first. | The await id names the subject, as `<subject>:<key>` (section 1). |
| 2026-10-19 | Continuation preassignment applies only within one workflow root, so it never reaches a gate. | One session per subject. Engage assigns, and continue adopts new questions (section 6). |
| 2026-10-19 | Nothing native releases a gate claimed by a session that died. The listings of orphan-sweep and the on_death release hide gates, the dead-assignee release covers pool-routed work, and lease reclaim, which nothing in Gas City runs at this commit, would rob a live held sitting. | Engage's conditional reassign naming the gone holder (section 6). |
| 2026-10-19 | A manual session is not ended when its work closes, and a pool sitting would be drained by the execution backstop while the operator reads. | converse-reap, keyed on gates. Its trigger is in section 6. |
| 2026-10-19 | Core's human-gate orders reach a person only by mail and nudge, and an override can only point them at another mailbox or session. This city's operator has no session and reads the board, not a mailbox. | The board is the reach, and core's two orders are off (section 5). |

This design adds no pack noun. Its conventions live in native fields: the
outcome word at the head of a gate's close reason, which finding release and the
quiet period read, and the subject at the head of its await id, which tells a
question's subject from the beads that wait on it. The glue it keeps is the
quiet period, which mirrors core escalate's incident reminder.
