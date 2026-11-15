---
name: Design — session liveness retires onto the controller's work ladder
description: The design record for tk-1tfzr71.137, the design child of initiative tk-1tfzr71.18, on retiring the pack's session-liveness compensations onto Gas City's controller. Use it to approve the design at its gate, or to build one of the units it defines.
---

# Design: session liveness retires onto the controller's work ladder

This is the design record for tk-1tfzr71.137, the design child of the
initiative tk-1tfzr71.18. The pack was read at a80f4e1ef, the commit
`integration/tk-1tfzr71.18` was cut from, and every line number is at that
commit. Each Gas City fact is cited by symbol at upstream main 8e7d91b583
(2026-11-15), and every symbol cited sits at the same path in the city's gc
build, 6589a7df45. Section 11 names the cited files that differ between the
two. The stores, the controller's event journal and the orders' own records
were read on 2026-11-15 between 07:30Z and 08:10Z, and the journal reaches back
to 2026-11-08. This repository is public, so the ids of the cases section 3
draws from other stores are in this bead's notes.

## What the operator approves

Today the pack keeps sessions alive with 5,838 lines in 18 files: a dog pool
that kills a stuck session after three rounds of probing, the warrant bead the
witness and the deacon file to start it, an order that nudges sessions parked on
a provider's usage limit, an order that keeps the mechanik pinned, and an order
that reports a cold deacon. Gas City's controller now runs its work ladder in
this city. It nudges a pool seat whose pane has gone quiet, releases a claim the
seat never starts, restarts the seat once when its started work goes unanswered,
and restarts a seat its provider refuses for a rate limit. Approving this design
retires the dog, its dance, the warrant bead, the quota-park nudge and the pin
keepalive, and hands boot health to the patrol member (tk-1tfzr71.19).
Afterwards nothing in the pack kills a stuck session. The implementation child
files the three units of section 8 on the integration branch. No cut-over bead
is needed, because each retired order stops when its file leaves the pack.

These calls carry a cost either way:

1. **The dog's due process retires, and a session that keeps printing while its
   work stands still becomes a finding for you.** In the 15 warrants filed since
   2026-09-20 the dog killed nothing. Thirteen targets were healthy sessions
   whose watched record had gone stale, five warrants were pardoned on pane
   movement in the first round, and six never reached a dog. The controller's
   ladder now handles a pool seat whose pane goes quiet. Neither the ladder nor
   the dance acts on a session whose pane keeps printing, so the witness files a
   finding when such a pool seat, holding a claim, has written nothing for three
   hours. The cost: a seat stuck in a hung model turn holds its slot and its work
   until you act on the finding. The other way is for the witness to restart the
   seat itself with `gc session kill`, after which the controller restarts it in
   place with its claims. That acts sooner, and a wrong judgment restarts a
   healthy turn.
2. **Quota-park nudging retires.** On 2026-11-11 the controller itself restarted
   the three polecats parked on Claude's weekly limit, and each then closed the
   bead it held. In the order's own records no nudge resumed a session: each nudge
   sent while a limit held was refused, and the one deacon that stayed parked to
   its reset resumed by itself a minute after the reset. The cost: when Claude
   does not resume a parked named session by itself, it waits. A witness in the
   middle of a pass still gets the witness-nudge order's nudge, a parked deacon
   reaches your board through boot health's cold-deacon finding, as both of the
   deacon's parks on 2026-10-30 did, and an on-demand seat wakes on its next
   demand. The mechanik waits for you. Keeping the nudge means building it in Go
   as gctk's quota-park noun, with a warning that reaches you, since its warning
   today goes to a seat this city does not have.
3. **Pin keepalive retires, and the mechanik pins itself when it starts.**
   `mode = "always"` keeps the mechanik up and restarts it when it dies, with no
   pin. For the mechanik a pin does one thing more: config drift never restarts
   the pinned session under your conversation. The mechanik's session bead has
   carried its pin since 2026-09-07, and the order has had nothing to
   re-assert since, because a pin drops only when the bead is replaced. One
   line in the
   mechanik's prompt keeps the exemption across a replacement with no order. The
   cost: one more startup step for the mechanik. The other way, with no line, a
   replaced mechanik can be restarted by a config change, which keeps its
   conversation, until someone runs `gc session pin`.
4. **Boot health and the cold-witness report go to the patrol member.** What a
   cold patrol means depends on what that member makes the witness and the
   deacon: Gas Town's roles, core's orders or the pack's own loops. So the
   report of a cold deacon and a cold witness is built there, and boot health's
   rows in the deletion plan move to it. The deacon's warrants against a stale
   witness patrol stop with no stand-in, since all seven named a patrol record
   the witness had left behind while it kept working. The cost: until the patrol
   member lands, a witness whose patrol stands still while its pane prints, or
   which holds no patrol record, is reported to nobody. That is already so in
   effect, because none of the deacon's warrants reached you or changed a
   session. The other way is to build a doctor check here that reports both,
   which the patrol member would then rewrite.

Approving the design as it stands ships the first option of each. Section 2
answers the two constraints the subject's notes fold in, and section 9 the
problems held on this bead.

## 1. What the controller does now

The city runs Gas City's v2 session reconciler, and the v2 reconciler runs the
work ladder. The town's `city.toml` sets `session_reconciler = "v2"` under
`[daemon]` and does not set `work_ladder`, and an unset switch is on:
`DaemonConfig.WorkLadderEnabled` (`internal/config/config.go`) returns true for
any value but `"off"`. The ladder governs pool seats only (`ladderGoverns`,
`cmd/gc/work_ladder_lane.go`). A configured named session, such as a witness,
the deacon or the mechanik, gets no ladder entries, whatever it holds.

The ladder judges a seat by its pane, and reads its transcript only for a
provider's refusals. A seat is quiet once its pane has
printed nothing for 90 seconds (`idleClaimNudgeGrace`, `cmd/gc/idle_nudge.go`)
and shows no busy marker. It reads no bead's `updated_at`, no step and no
molecule's progress. For a pool seat:

| The seat | What the controller does |
|---|---|
| holds a claim it never starts, pane quiet | nudges it at about 1.5, 4.5 and 10.5 minutes, then releases the claim at about 22.5 minutes (`DefaultClaimedThreshold`, `internal/workladder/policy.go`) |
| holds started work, pane quiet | nudges it six times, from 1.5 to about 95 minutes, then restarts it once, keeping its claim, at about 2 hours 35 minutes (`DefaultStartedThreshold`, `DefaultMaxRecycles`; `armExecutionStalled`, `cmd/gc/reconcile_arms_drift.go`). After that it raises a `started_unanswered` escalation and nudges hourly. Work that awaits a person is only nudged. |
| keeps printing while its work does not advance | nothing. A printing pane is never quiet, so the ladder takes no step. |
| holds work and its provider refuses it for a rate limit | after two refused turns in a row, read from the transcript (Claude's 429), nudges it every ten minutes without counting, and after ten minutes restarts it fresh once (`confirmed`, `internal/workladder/ratelimit.go`). A Codex usage limit counts as a spent quota, which raises `rate_limited_quota` instead of a restart (`internal/workladder/types.go`). |

The journal shows the ladder acting here. From 2026-11-08 to 2026-11-15 it
holds 89 `work.nudged`, 6 `work.rate_limited` and 1 `work.escalated` events, and
no `work.released` or `work.recycle_requested`. The six rate-limit events are
from 2026-11-11: three polecats refused with "You've hit your weekly limit" were
each restarted fresh between 11 and 52 minutes after their episode opened, and
each then closed its bead. The release and the restart of a quiet seat had no
case that week, so they stand on the code at both commits.

The rest of the controller's stall handling, for the shapes the subject names:

- **The legacy stall timeouts do not run.** `[session] progress_stall_timeout`
  and `claim_holder_stall_timeout` key on pane activity too, and v2 ignores
  them with a deprecation warning (`v2IgnoredSettings`,
  `cmd/gc/reconcile_latch.go`). The city sets neither. The execution backstop
  (`cmd/gc/execution_backstop.go`) runs only under the legacy reconciler or with
  `work_ladder = "off"`, so its hold on a started claim does not apply here.
- **A crash loop is a repeating five-minute quarantine that nobody is told
  about.** Five deaths each within 30 seconds of a wake, or three deaths between
  30 seconds and five minutes after one, quarantine the session for five minutes
  (`deadRuntimePatch`, `cmd/gc/reconcile_arms_heals.go`;
  `defaultMaxWakeAttempts`, `defaultMaxChurnCycles` and
  `defaultQuarantineDuration`, `cmd/gc/session_types.go`). It repeats while the
  loop lasts, and `session.quarantined` (`internal/events/events.go`) is
  declared and never emitted. The city's `max_restarts = 5` and
  `restart_window = "1h"` do not govern it. Under v2 they feed a crash tracker
  that nothing records a start into (`newCrashTracker`,
  `cmd/gc/crash_tracker.go`), the startup retry limit and the legacy circuit
  breaker.
- **A session that died on a limit screen sleeps 30 minutes**
  (`rateLimitQuarantine`, `cmd/gc/reconcile_effect_abandon.go`;
  `defaultRateLimitQuarantineDuration`, `cmd/gc/session_types.go`). The screen
  matcher (`ContainsProviderRateLimitScreen`, `internal/runtime/dialog.go`) runs
  only on a dead pane.
- **A live named session parked on a limit gets nothing.** The ladder's
  rate-limit step is a pool seat's. The provider-health file only holds back a
  start, and the city writes none.
- **An always-mode named session is kept up.** It is wanted on every pass
  ("named-always", `cmd/gc/compute_awake_set.go`), exempt from idle sleep, and
  restarted on the same bead when its runtime dies (`armDeadRuntimeHeal`,
  `cmd/gc/reconcile_arms_heals.go`).
- **A killed session restarts in place.** `gc session kill` sleeps it with
  `sleep_reason=killed`. An always-mode named session is still wanted, so it
  restarts on its bead. A pool seat holding started work keeps its claims and
  restarts in place, as specs/tk-1tfzr71.7/pool-slot-reap-rederived.md records.

## 2. The dog's due process

Today the witness and the deacon each judge a session stuck and file a warrant
through `file-warrant.sh`. The bead is a task labeled `warrant` with
`warrant.target`, `warrant.reason` and `warrant.requester`, sent to the dog by a
route written into its create (`file-warrant.sh:134-136`). A dog session, city
scoped, on Codex and at most two at a time, runs `mol-dog-shutdown-dance`.
`dance-probe.sh` answers `parked` for a quota-parked session and `alive` for a
busy marker or a changed pane hash (`dance-probe.sh:87-149`). One `alive`
pardons. Three `silent` rounds of 60, 120 and 240 seconds authorize
`gc session kill`.

The dance judges a session by its pane, as the ladder does. On a quiet pool
seat the ladder now nudges, then releases a claim the seat never started, or
restarts the seat with its started claim kept, which is what the dance's kill
came to. On a printing session
the dance always pardons, so it never acted where the ladder does not. The dog
adds nothing the controller lacks, and it retires with its dance,
`dance-probe.sh`, `file-warrant.sh` and the warrant bead. Gas Town's
`mol-shutdown-dance` does not take its place. It also pardons on the pane
alone, on "any sign of active work" (`gastown/formulas/mol-shutdown-dance.toml`
at gascity-packs 66897e7132c9, the commit upstream's `go.mod` pins), and the
city imports no gastown pack.

What the patrols do with a stuck session afterwards:

- **A pool seat whose pane has gone quiet is the controller's.** The witness
  files nothing for it.
- **A pool seat that keeps printing while it does not advance becomes a
  finding.** This is the one shape nothing else covers. The witness's branch 2b
  (`mol-witness-patrol.toml:489-519`) files it through `patrol-finding.sh`,
  which the plan keeps and which slings the finding's first reaction
  (specs/tk-1tfzr71.105/design.md, section 1). Its key names the session,
  `no-progress.<session-id>`. The rule meets the two constraints the subject's
  notes fold in from tk-smspkv:
  1. *It judges progress, not liveness.* Progress is any write the session made
     to a store. bd records each write's actor, and Gas City runs a session
     with the identity its claims are assigned to as that actor
     (`AssigneeIdentifier`, `internal/session/assignee_identities.go`, which
     `RuntimeEnvWithSessionContext` in `internal/session/lifecycle.go` exports
     as `BEADS_ACTOR`). For an unaliased pool seat that identity is its own
     session bead id. For an aliased seat, such as a converse sitting, it is the
     alias, which every session that held the alias shares. The witness reads
     the newest write whose actor is the claim's assignee, in the `events` and
     `wisp_events` tables of the rig's store and the city's through
     `gc bd sql`, never one record's `updated_at`. On 2026-11-15 the query took
     under a second over this rig's 626,000 events. A predecessor's write under
     a shared alias can only make the newest write newer, so it can spare a
     stuck seat and never files on a healthy one.
  2. *It never reads an abandoned record as the session being stuck.* It files
     only on the session's own writes, and it names the claim the session holds
     now: the in-progress bead assigned to it whose `gc.session_id` is that
     session. A record the session left behind is never the subject.

  It files only while the pane prints, meaning a `last_active` from
  `gc session list --json` within the last 90 seconds, so a session idle at its
  prompt is never filed, a held conversation included. The bound is three hours
  with no write. The longest gap between writes in a healthy session in section
  3's record is 1 hour 41 minutes, and the ladder restarts a quiet seat at about
  2 hours 35 minutes. Branch 2b reads no quota-park status any more: a parked
  session's pane is quiet, so the rule never files on it. It kills nothing.
- **A named owner is no longer warranted.** The ladder does not govern a named
  session (section 1), and branch 2b files only on a pool seat. Of the named
  owners in a rig's store, a refinery handoff that sits untouched stays
  check-refinery's human gate, a cold witness is the patrol member's report
  (section 6), and a conversation is never a candidate, since the witness's
  `downstream-court-skip` filter drops it. A quiet named owner holding any
  other claim gets no challenge nudge once the dance retires, and section 3's
  record holds no such case.
- **The deacon's "Stuck sessions" bullet goes** (`mol-deacon-patrol.toml:427-457`).
  It warrants on two signals. The first, `escalated=1` from
  `quota-park-nudge.sh --status`, always comes with `quota_park=yes` on the same
  line, so every such warrant met the dance's `parked` answer and closed
  refused. The second, a live witness or other infrastructure session whose
  patrol record is stale, produced all seven of the deacon's warrants in section
  3, and each named a record the witness had left behind. Reporting a cold
  patrol is boot health's successor's job (section 6).

The pack's word "warrant" for this bead retires with it. What takes the
warrant's place is a finding, the pack's existing kind of report to a person,
so no new name is needed and "warrant" keeps only the foundation's meaning. No
work reaches a pool through a route written into a create, because the
finding's reaction is slung and poured (specs/tk-1tfzr71.54/design.md, call 4).

**The patrol edits.** This member makes the edits the deletion forces, in
unit 1: branch 2b of the witness's `recover-orphaned-beads` step, the deacon's
"Stuck sessions" bullet in `system-health`, the `DOG_DONE:` handling in both
`check-inbox` steps (witness 69-71, deacon 54-64), the other lines of both
formulas that name the dog or a warrant (witness 17-22, 32, 42, 50, 263 and
481, deacon 34), the warrant lines of the two prompts
(`agents/witness/prompt.template.md:25-36`,
`agents/deacon/prompt.template.md:20-23`), and the paragraph of
`docs/pack-authoring.md:562-567` that gives the warrant as the witness's
city-scoped address. The patrol member (tk-1tfzr71.19)
takes every other step of both patrols and carries branch 2b's rule into its
rewrite. The deacon's incident ledger keeps its `warrant` category, with nothing
appending to it, until that member retires the ledger.

## 3. The warrant record against the controller

No warrant was filed after 2026-10-23, so the window is 2026-09-20 to
2026-10-23. It holds 15 warrants in three stores. The counts the subject gives
hold: the city store 30, this rig's 25, another rig's 14 and a third rig's 7,
four of them open. The label is broader than the dance. Only 41 beads carry
`warrant.*` metadata, and the city's 30 include 7 database and backup alerts.

The dog killed nothing. It pardoned five, each in the first round on pane
movement. It refused two for naming an agent where the probe needs a session
id, and two because the target was gone by the time a dog ran. Two more closed
with no dance, one by triage and one as a missing target. Four are open and
were never claimed, because each was filed in a rig store and the city-scoped
dog pool wakes only for the city's (tk-7yzkw3x).

Each case against the controller, and against branch 2b's rule:

| Cases | The target when filed | What the dog did | What the controller does | Branch 2b |
|---|---|---|---|---|
| 7 in the city store, 2026-09-29 to 10-01, the deacon against two witnesses | a patrol record left behind by the orphaning bug fixed on 10-01 (tk-sl05ll), while each witness kept working; one may have been idle on 09-29, its pane quiet for 45 hours | pardoned 5 in round 1, refused 2 for a malformed target | nothing, since both are named sessions | not its case: the witness's branch covers pool seats |
| tk-e66cgv, 2026-09-25, a polecat | its watched step lagged while it updated its task bead and filed a bead 16 minutes before; it closed the step the second the warrant landed | refused 5 days later, target gone | nothing, since it was printing | spared: it wrote 16 minutes before |
| tk-5artls, 2026-09-30, a polecat | heartbeat fresh; it updated a bead 40 minutes before and closed the step 13 minutes after | refused 21 hours later, target gone | nothing, since it was printing | spared |
| tk-5ode6s, 2026-10-02, a polecat | it wrote nothing for 1 hour 30 minutes, then closed four steps 11 minutes after the warrant | never claimed, then closed as a missing target | nothing, since it was printing | spared: its gap stayed under three hours |
| tk-0tqkhdw, 2026-10-23, a Codex polecat | idle at its prompt after store timeouts; it cleared its assignee while its session id stayed on the bead | never claimed | the ladder saw no work assigned to it; the controller reopened the bead about 3 hours 50 minutes later, and a new session closed it in two minutes | not its case: its pane was quiet |
| 4 in another rig's store, 2026-10-03 to 10-19, polecat and proactive seats | one healthy session that took two beads without a claim and closed both within hours; three long turns that kept writing, one a four-hour turn that updated two beads and filed two | triage closed 1, 3 never claimed | nothing, since each was printing | spared: each wrote within 1 hour 23 minutes before |

The controller would have done to every session what the dog did, which was
nothing. No case is a session that stayed busy without advancing. The thirteen
stale-record cases are the hard cases the notes name: the old rule read one
record's `updated_at` and filed on each, and branch 2b reads the session's own
writes and files on none. The four open warrants are moot, since each stuck
item closed within about 70 minutes of its filing, and section 9 closes them.

## 4. Quota-park

`quota-park-nudge.sh` (901 lines, an order every five minutes) nudges a live
session showing a provider's limit banner, backs off to 15 minutes, and warns a
person once after two hours. Its warrant entry (`docs/warrants.md`, Quota-park
nudging) stands in for "waking a live session that sits idle under a provider's
usage-limit banner once the limit resets". It retires when "Gas City wakes a
session parked on a provider's limit once the limit resets, or every provider
the city runs resumes such a session by itself".

What covers a live parked session now:

- **A pool seat holding work is the controller's.** The ladder's rate-limit
  step (section 1) found the 2026-11-11 weekly limit in three polecats'
  transcripts and restarted each. The city's launcher picks the account at each
  launch, so a restart is what moves a seat off a spent account. No named
  session runs Codex, so every Codex session is a pool seat, such as a dog, a
  `polecat-codex` slot or a `converse-codex` sitting.
- **A named session has no cover in Gas City.** Every named session in this
  city runs Claude Code, on the `claude` or `claude-watch` provider.
- **The order's own record shows no nudge resuming a session.** It keeps no log
  of its passes. Its episode files, the deacon's session audit trail and the
  finding notes hold four episodes since 2026-10-30. Every nudge sent while a
  limit held was refused. In the one episode that lasted to its reset, the
  deacon resumed by itself in the same conversation a minute after the reset,
  13 minutes after the order's last refused nudge. Two deacon episodes passed
  the two-hour mark, and no warning reached anyone, because its default
  recipient, `mayor/`, names no seat in this city.
- **tk-vtnyw8d** asks for your ruling on the order, and gives your view that
  "Claude now auto-resumes when quota has come back, or at least usually does".

So the order retires: its script and test, its order file,
`docs/quota-park-recovery.md`, its warrant entry, and the `quota-park` rows that
`docs/gctk-architecture.md` plans for gctk. For pool seats the warrant's trigger
has fired. For named sessions it rests on the one recorded resume and on your
view, which is why it is call 2. Afterwards a parked witness in the middle of a
pass is nudged by the witness-nudge order, whose 11-minute quiet rule also wakes
it once the limit lifts. A parked deacon goes cold and boot health reports it,
as boot health's finding (tk-uzrdj3a) did for both of the deacon's parks on
2026-10-30. An on-demand seat sleeps when idle and wakes on its next demand.

If you keep the nudge, it is built as gctk's quota-park noun
(`gctk quota-park nudge`, `gctk quota-park status <session>`) for named
sessions only, its warrant is re-verified at 8e7d91b583 with `ladderGoverns` as
the evidence, and its warning becomes a finding.

## 5. Pin keepalive

`pin-keepalive.sh` (344 lines, with a 10-line precheck, on a condition order)
runs `gc session pin` on each always-mode named session on the `claude` provider
that has lost its pin. Its header gives the purpose: a pinned session's
config-drift restart "keeps deferring".

- **The mechanik stays up with no pin.** It is always-mode, so the controller
  keeps it awake and restarts it when it dies (section 1).
- **For the mechanik a pin does one thing more.** `pin_awake` is written only
  by `gc session pin` (`SetPinAwake`, `internal/session/store.go`). On a
  configured named session it defers config drift indefinitely
  ("drift-deferred:pinned", `cmd/gc/reconcile_arms_drift.go`). It also
  overrides an idle-sleep policy (`decidePass.awake`,
  `cmd/gc/allocator_decide.go`), and the mechanik has none: it sets no
  `sleep_after_idle`, and the city sets no `[session_sleep]` default. Nothing
  carries the pin to a new session bead, because the controller creates a
  named session's bead without it (`planNamed`, `cmd/gc/allocator_plan.go`)
  and no config key sets it. Since 4668395f4, which both builds carry, a change
  to an agent's pool size, skills, prompt text or `wake_mode` no longer
  restarts its session, and a change to its command, its environment or its
  MCP servers still does.
- **The case has not come.** The mechanik's session bead has existed since
  2026-08-31 and has carried its pin in every audit snapshot since 2026-09-07.
  The order's pass log keeps its newest 400 lines. On 2026-11-15 they held 133
  checks back to 2026-11-14T20:27Z, each finding every target pinned, and the
  journal since 2026-11-08 holds no run of its exec. Its target set is the
  mechanik alone.

So the order and both scripts retire, and the mechanik's prompt gains one
startup step: pin its own session with `gc session pin`, which is idempotent. It
pins only its own always-mode seat and reads no session list. tk-9577vsc no
longer reproduces: 8c264e367 quoted both assignments, and
`shellcheck -S warning` exits 0 on the file. Its closer finds the file gone.

## 6. Boot health

`boot-health.sh` (333 lines, an order every five minutes) reads the deacon's
patrol record and, when the deacon stays cold past 30 minutes, files a finding
through `patrol-finding.sh`, refreshed hourly while the episode lasts and
cleared when it ends. Its one finding since 2026-10-30 (tk-uzrdj3a) holds two
episodes, each the deacon parked on the weekly limit.

It moves to the patrol member rather than becoming a doctor check here. That
member decides whether the witness and the deacon stay the pack's loops, become
Gas Town's roles or become core's orders, and each makes a cold patrol a
different thing to read. A check built here would be built against a patrol
about to change. Unit 3 moves boot health's three rows in
`tools/deletion-plan.tsv` (`boot-health.sh`, its test and
`orders/boot-health.toml`, 973 lines) to tk-1tfzr71.19, and the sizes in
`docs/built-once-target.md` move with them.

What that member's report owes, from the subject's notes, goes onto
tk-1tfzr71.19 (section 9):

- It reports on the board both a cold deacon and a cold witness, meaning a
  witness patrol that has not advanced within a bounded time.
- It covers a witness that holds no patrol record, and one whose deferred record
  never returns to open, the two shapes the witness-nudge order leaves
  (specs/tk-r4c0g67/gas-city-search.md, What the order costs).
- It judges the patrol the session is running now, never a record the session
  left behind, which is what all seven of the deacon's warrants misread.
- A filing that is not confirmed still owes the episode's end, because
  `patrol-finding.sh` writes the bead before steps that can still fail.
- The reason boot health gives for not nudging, that delivery to a fresh-wake
  singleton is unreliable, does not hold: three nudges on 2026-10-30 each reached
  an idle witness.
- Gas Town's `witness-heartbeat-check` is not in the gascity-packs commit
  upstream pins (66897e7132c9). It is described only at packs main
  0b0d96250f66, in specs/tk-r4c0g67/gas-city-search.md, so it is a model to
  re-read, not a fact.

## 7. What stays

Nothing in this member's scope stays, so no warrant entry is added. The
Quota-park nudging entry leaves `docs/warrants.md`, and so does its note that
the dog's warrant bead "shares only the word". If call 2 goes the other way, the
entry is re-verified and re-dated as section 4 says. Boot health has no warrant
entry, and the patrol member re-derives it. Branch 2b reads sessions through
`gc session list --json`, which lists the sessions that have not closed. The
dog's prompt retires, so `assets/scripts/where-to-search-wiring.test.sh` drops
`agents/dog` from its exemptions. The witness's and the deacon's prompts already
compose the fragment, and the mechanik's stays exempt, as tk-2f0pasy left it.

## 8. The units

Each unit lands on `integration/tk-1tfzr71.18`, keeps the suite green and leaves
the city working. They run in order, because they edit the same pages and the
plan. Each re-renders the seed audit for what it changes, and each unit's
polecat greps again for the names it removes, since this design listed their
readers at a80f4e1ef.

| Unit | What it does | Waits on | Releases |
|---|---|---|---|
| 1. The patrols stop filing warrants | the witness's branch 2b files the finding of section 2, with no quota-park read and no dog route; the deacon's "Stuck sessions" bullet goes, with its quota-park read; both `DOG_DONE:` handlers go; the other lines of both formulas that name the dog or a warrant; the warrant lines of the witness's and the deacon's prompts; the warrant example in `docs/pack-authoring.md`; `deacon-warrant.test.sh` is deleted and `witness-route.test.sh` rewritten to assert the finding and no dog | nothing | no warrant is filed after it lands, so the dog gets no work |
| 2. The dog, its dance and the warrant bead retire | deleted: `agents/dog/`, `formulas/mol-dog-shutdown-dance.toml`, `file-warrant.sh` and `dance-probe.sh` with their tests, and `dog-human-gate-wiring.test.sh`. Edited: `claim-close.test.sh:108-112,229` and `pack-self-location.test.sh:272-275`, which use the dance as a fixture; `where-to-search-wiring.test.sh:31`; `lifecycle/lifecycle.toml`, which registers `warrant.target`, `warrant.reason` and `warrant.requester` as retired; `doctor/check-hq-marooned-work/run.sh:226` and its fixture; `doctor/check-claim-advancing`'s description and its comment at `run.sh:37-43`; `resolve-route.sh`'s usage example; the caller list at `patrol-finding.sh:25-31`; `tools/measure.sh:70,85`; the dog's lines in `architecture.md`, `authority-map.md`, `component-model.md` and `warrants.md:24-25`; the dog's rows in `tools/deletion-plan.tsv` and its share of `docs/built-once-target.md` | unit 1 | the dog pool, and the warrant keys for tk-1tfzr71.25 |
| 3. Quota-park nudging and pin keepalive retire, and boot health's rows move | deleted: `quota-park-nudge.sh`, `pin-keepalive.sh` and `pin-keepalive-precheck.sh` with their tests, `orders/quota-park-nudge.toml`, `orders/pin-keepalive.toml` and `docs/quota-park-recovery.md`. Edited: the Quota-park nudging entry in `docs/warrants.md`; the quota-park rows and bullet in `docs/gctk-architecture.md`; the mechanik's prompt, which pins its own session at start; `lifecycle/lifecycle.toml:1889-1895`; `doctor/check-claim-advancing/run.sh:255-258`; the lines of the pages that name either; both orders' rows in `tools/deletion-plan.tsv`, and boot health's three rows moved to tk-1tfzr71.19, with the sizes in `docs/built-once-target.md` | unit 2 | two orders' passes every five minutes, and the closers of tk-vtnyw8d and tk-9577vsc |

Unit 2's PR states the counts of the ladder's events in the controller's
journal for the week before it: `work.nudged`, `work.released`,
`work.recycle_requested`, `work.rate_limited` and `work.escalated`. That is the
live check of the controller's handling, read again when the dog goes.

When the landing merges, the reconcile of the rig checkout delivers it, and
each order stops when its file is gone. The orders' runtime files under the
city's `.gc/runtime`, quota-park's episodes and pin keepalive's stamp and log,
are read by nothing afterwards.

## 9. Edges and notes the implementation child adds

The implementation child (tk-1tfzr71.138) files the units under the effort's
epic (tk-1tfzr71) with `target=integration/tk-1tfzr71.18` in each create. The
landing bead (tk-1tfzr71.18) and the summary task (tk-1tfzr71.139) each wait on
every unit through a `blocks` edge. Unit 2 waits on unit 1 and unit 3 on unit 2,
each armed to dispatch when its blocker closes. Before it files, the child
surveys the open branches against each unit's files again, since they move.

It closes the four open warrants as needing no work, each with the reason that
its stuck item closed on the day it was filed. One, tk-0tqkhdw, is in this
rig's store, and this bead's notes name the store of the other three.

It appends a note to each bead below:

- **tk-1tfzr71.19.** The patrol edits unit 1 makes, and branch 2b's rule to
  carry into its rewrite. Boot health's rows, now that member's, and what its
  report owes (section 6). The deacon's warrant on a stale infrastructure patrol
  is gone, so that report is the only one of a cold witness.
- **tk-1tfzr71.25.** Unit 2 registers the three `warrant.*` keys as retired,
  and the registry's retirement takes those entries with the others.
- **tk-vtnyw8d.** Call 2 answers it, and unit 3 carries it out. Its closer reads
  the landed design and the unit.
- **tk-9577vsc.** The finding no longer reproduces (section 5), and unit 3
  deletes the file.

## 10. The upstream asks

Two asks stay proposed. Posting them is your decision, and neither is sent.

1. **A progress signal for a busy pool seat.** The ladder reads pane output, so
   a seat that prints while its work stands still is never quiet and never
   paced. A signal from the seat's own store writes, or from its transcript's
   completed turns, would let the controller pace it, and branch 2b's finding
   would retire.
2. **A crash loop that tells someone.** `session.quarantined` is declared and
   never emitted, so a session quarantined again every five minutes reaches no
   one. Upstream added an alert for failed starts (`session.startup_health_alert`,
   297772b4c3). The city's build lacks it, and it does not cover a session that
   dies after it has started.

Named sessions get no ladder at all. Upstream removed its named-seat backstops
in #6551 (2026-09-25), and the city already tracks that gap, so this design asks
nothing new for it.

## 11. Gas City facts, and the search behind the surface

Of the Gas City files this record cites, these are byte-identical at upstream
8e7d91b583 and in the installed build 6589a7df45: `cmd/gc/work_ladder_lane.go`,
`internal/workladder/policy.go`, `internal/workladder/ratelimit.go`,
`internal/workladder/types.go`, `cmd/gc/idle_nudge.go`,
`cmd/gc/reconcile_latch.go`, `cmd/gc/crash_tracker.go`,
`cmd/gc/compute_awake_set.go`, `cmd/gc/allocator_plan.go`,
`internal/session/store.go`, `internal/session/assignee_identities.go`,
`internal/session/lifecycle.go`, `cmd/gc/allocator_decide.go`,
`internal/runtime/dialog.go` and `cmd/gc/claim_stall_guard.go`. These differ:
`internal/config/config.go`, `cmd/gc/execution_backstop.go`,
`cmd/gc/reconcile_arms_drift.go`,
`cmd/gc/reconcile_arms_heals.go`, `cmd/gc/reconcile_effect_abandon.go`,
`cmd/gc/session_types.go`, `internal/events/events.go` and
`cmd/gc/wisp_gc.go`. Each symbol and value cited from them is the same in both.
Two behaviors differ, and neither touches this design. Upstream's execution
backstop, which does not run here, also holds a seat on its heartbeat, and
upstream backs off and alerts on failed starts.

The surface this design adds is one finding key, `no-progress.<session-id>`, a
new diagnostic in the witness's patrol. The mechanik's startup pin is prose. The
search behind the finding, for a session whose pane prints while its work does
not advance:

- The work ladder reads pane output (`(*ladderPass).observeRuntime`,
  `cmd/gc/work_ladder_lane.go`) and governs pool seats only (`ladderGoverns`).
- The legacy stall timeouts (`SessionConfig.ProgressStallTimeout` and
  `ClaimHolderStallTimeout`, `internal/config/config.go`) read pane activity,
  and v2 ignores them (`v2IgnoredSettings`).
- The execution backstop reads a quiet pane and is off while the ladder runs
  (`cmd/gc/execution_backstop.go`).
- The claims-stall guard withholds spawns per template and touches no bead
  (`cmd/gc/claim_stall_guard.go`).
- Wisp GC closes abandoned workflow roots by `UpdatedAt` and acts on beads, not
  sessions (`cmd/gc/wisp_gc.go`).
- `gc.claimed_at` is written by the hook and read by no controller code.
- Gas Town's `mol-shutdown-dance` pardons on the pane, and its deacon's health
  scan judges a witness by its patrol record's freshness
  (`gastown/formulas/mol-deacon-patrol.toml` at gascity-packs 66897e7132c9).
- bd's `gc bd mol last-activity <id>` gives one molecule's last activity, the
  one-record read the notes rule out.

None judges a session by its own writes. bd's record of each write's actor
does, so branch 2b reads it and keeps no state of its own.

The search behind the pin: `gc session pin` is the only writer of `pin_awake`
(`SetPinAwake`), and neither config nor the creation of a session bead carries
it, so the mechanik runs the native verb itself.
