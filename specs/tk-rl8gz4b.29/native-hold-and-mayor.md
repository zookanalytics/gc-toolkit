---
name: Holding new work on Gas City's hold, with a mayor working the queue
description: Use when building or reviewing the effort that retires the placement marker (tk-rl8gz4b.28), before giving the mayor or mechanik a job, or when a change would write, read or lift a hold on new work.
---

# Holding new work on Gas City's hold, with a mayor working the queue

New work that no epic holds carries Gas City's `hold:mayor` label. The queue is
one native read, `gc beads list --label hold:mayor`. The mayor is a session the
operator opens to work that queue, and each sitting starts fresh. Placing a bead
is one verb, `gc-helm.sh place`, which sets the parent, slings the bead and lifts
the hold. `placement=pending`, `assets/scripts/placement.sh` and
`gc-helm.sh unplaced` all go.

Every answer below is proposed until the operator approves this design's PR. The
rulings it rests on are quoted with where they were said, and text from the
initiative's description (tk-rl8gz4b.28) is named as that. What Gas City ships is
cited in [the search record](gas-city-search.md), read at the commits named there.

## What the operator is asked to rule

**1. Who places routine work?** (`docs/authority-map.md` says no agent does today.)

- *The mayor proposes and the operator rules* (recommended). The mayor brings the
  queue in pieces that each fit one screen, with a recommendation, and applies
  each ruling. Nothing starts without the operator's word. The queue waits between
  sittings, for as long as the operator chooses.
- *The mayor also places by a rule the operator writes*, such as "a member of an
  unparked epic when its first reaction says actionable". Work starts with nobody
  looking. It adds an order to wake the mayor and a stored rule, and a wrong
  placement costs polecat time and a PR review.

The first keeps capacity in the operator's hands, which is what the epic was
filed for, and it can grow into the second later with nothing rebuilt.

**2. Does the pile with no first reaction join the queue at cut-over?**
gc-toolkit's intake is off, so many open beads there have had no first reaction
and carry no marker. Their count is on tk-hok6w.

- *One write per bead puts them in the queue* (recommended). It spends no tokens
  and starts no work. The mayor's batch sort then reads one list, and turning
  intake back on later reacts only to new beads. Intake stays off, as ruled on
  2026-10-26. Some stale beads will take a sitting's minute to close.
- *They stay where they are* until first reactions or a census sitting reach them.
  The working list stays two lists, and turning intake on then spends a first
  reaction on each.

**3. Does the witness mail the mayor?** Gas Town's witness escalates by mailing
`mayor/`, and the witness's target is Gas Town's (visit tk-dbpz6t2).

- *Our witness keeps filing findings and human gates* (recommended). The mayor receives
  no patrol traffic, and this stays a named difference from Gas Town until the
  operator rules otherwise.
- *The witness mails the mayor, as Gas Town's does.* The mayor owns escalation
  handling as well as the queue, and its mailbox takes the patrol traffic the
  initiative's description names as a symptom: "a mailbox that absorbed escalation
  storms".

## The seats at landing

| Seat | Owns | Runs |
|---|---|---|
| mayor | the placement queue, and nothing else it was not ruled to own | when the operator opens it, fresh each sitting |
| mechanik | how the city works, and every town-repo edit | always, with the operator's standing conversation |
| a converse sitting | one bead's conversation | per conversation |
| patrols, pools, refinery | what they own today | unchanged |

The operator's words for the first two: "mayor (overseer of all, owner of little)",
"mechanik (gc-toolkit / Gas City expert)", and "I'd also rather the mayor take
something over the mechanik who is designed to focus more on gc-toolkit
effectiveness" (visit tk-2hdsjmg).

The operator tabled a per-rig seat in the same visit. Nothing here builds one or
closes it off: the verb names no seat, and one store's queue is one
`gc bd --rig <rig> list --label hold:mayor`. Gas City's published `oversight-rig`
pack is the nearest model, a rig-scoped `project-lead` it describes as taking
project-level scoping out of the mayor.

## What a held bead is

A held bead is open and unassigned, with no route and no arm, and it carries
`hold:mayor`. Gas City keeps such a bead out of the default work query, the hook,
pool demand and the route-restore sweeps.

Three things about it are choices:

- **It carries no route.** Gas City's two texts disagree here. The conventions page
  says a pack that parks on a hold usually clears the route, and the session-model
  page says `gc.routed_to` only ever names a backing config identity. The
  `hold-label-routed-to` doctor check wants the route to equal the label's value,
  and its `--fix` writes it. Upstream issue 6069 reports that check as a bug and an
  open PR removes it. This design follows the documented contract, which costs one
  standing doctor warning until the fix reaches the fork. The deacon's patrol step
  today files a warning or runs its `--fix`, so it names this check as known and does
  neither. A route a `--fix` writes anyway does nothing while the hold stands, and
  `place` clears it.
- **A create carries the label in its own write** (`--labels hold:mayor`), and a
  bead that already exists takes `gc bd set-state <id> hold=mayor --reason "..."`.
  The conventions page asks for `set-state` every time, so that an audit event
  exists. On a create the bead's own record is that audit, and a `set-state` after
  the create would leave a window with an open bead in no queue, which is the
  reason the witness's block rides the marker on its create today. `set-state` also
  files a closed `event` bead as a child of the subject. The pack's findings already
  live with that.
- **The queue reads the label alone.** `placement.sh` inferred "placed" from six
  facts because no writer cleared the marker. A hold is lifted by a write, so
  nothing is inferred.

## 1. What keeps the mayor from becoming the dumping ground

The operator's account: "lots of items naturally did go to the mayor to handle...
As a mayor, it works well. As the dumping ground of everything, it became a
problem" (visit tk-2hdsjmg). This design's reading of why: a resident agent with an
inbox is the easiest thing to send work to. So it removes the properties that made it
easy, rather than asking the prompt to decline.

- **Nothing is waiting to receive.** The seat is on demand and fresh, so no
  conversation accumulates what it was told. Plain mail wakes nothing. A nudge or a
  `--notify` mail does wake it, because Gas City materializes a named session on a
  direct reference. That wake gets one turn, whose only job is to say whose request
  it is.
- **It has no route to fill.** It declares `default_sling_formula = ""` and a
  `sling_query` that refuses with a message saying where the work goes, so a plain
  `gc sling` to the mayor fails at the caller. It needs both, because the city's
  `[agent_defaults]` gives every agent `mol-polecat-work` and a graph.v2 pour never
  runs the query. `gc sling --on <formula>` pours past the query for the same reason,
  and nothing refuses it.
- **Its queue has named writers.** `hold:mayor` is written only by the writers
  `docs/authority-map.md` lists.
- **One check covers every path that leaves a record.** Assignment, mail and
  `gc sling --on` cannot be refused by config, and any writer can set a label. So one
  doctor check holds one invariant, that the mayor receives nothing but its queue, and
  a new path shows up as a finding within one sweep of its first use. That is why
  there is one check, not a guard per path. A delivered nudge leaves nothing to read,
  so the check cannot see one.
- **A new ownership is a ruling.** `docs/authority-map.md` gains a row saying so,
  and `docs/architecture.md` lists what the seat owns.

### Every path that would reach it

| Path | What it does at landing |
|---|---|
| `quota-park-nudge.sh`'s default `mayor/`, which resolves to the seat by bare name once one exists | The default becomes `human`. That reaches nobody who reads it, as today's default does. It is the smallest stopgap for a retiring file, noted on tk-1tfzr71.18. |
| `gc-terminal-attach.sh`'s default session | The pack sets no default. A terminal opened with no name refuses and says how to name one. `GC_TERMINAL_DEFAULT_SESSION` stays, so the operator can choose a default in the town's config. |
| Gas City's warmup mail, hard-coded to `mayor` with no config field | Unchanged, because it cannot be re-pointed. It fires only at `gc start` on a failed check, and the same failure prints on stderr and stays in `gc doctor`. The check ignores this sender, and if it shows in the seat's inbox the mayor archives it. |
| Core's `orphan-sweep` and `spawn-storm-detect`, which go to `GC_ESCALATION_TARGET`, default `human` | Unchanged. The city does not set the variable, and the authority map's new row makes pointing it at the mayor a ruling. |
| Gas Town's witness, deacon, refinery and polecat, which all mail `mayor/` | The city does not import them. tk-1tfzr71.18 and .19 owe this if they take those roles, and a note on each says so. See ruling 3. |
| `gc sling mayor "..."`, which Gas City's docs teach | The seat has no formula of its own, so this reaches `sling_query`, which refuses. |
| `gc sling` to the mayor with a graph.v2 formula, by `--on` or `--formula` | Nothing refuses it. The run's steps route to the seat, which wakes and takes none of them, because its prompt takes no work from the hook. The check names the steps. |
| Assignment: `gc bd update --assignee`, `first-reaction-dispose.sh --assign` or `--then-assign`, or `gc-helm.sh takeaway --release --assign` | `first-reaction-dispose.sh` refuses the mayor's address. The others wake the seat and the check names them. |
| `gc mail send` | Delivered, and it wakes nothing. The mayor's prompt treats unread mail as a sign of a path and says whose it is. The check names the sender. |
| `gc session nudge`, `gc mail send --notify` | These materialize the seat and wake it, which costs one first turn. With nobody attached, its prompt says whose request it is and runs `gc runtime drain-ack`. The check names a `--notify` mail's sender and sees no nudge. |
| `hold:mayor` set on something that is not new work | The check names it: a bead with an anchor or a landing state. A branch alone does not count, because a run that ended can leave one on a bead the mayor holds again (section 6). |
| `reconcile-rig-checkouts.sh`'s `RECONCILE_MAYOR_ADDR`, `dolt` maintenance's `alert_to`, `gc convoy --owner mayor` | Unset in this city, or display only. They stay as they are. |
| The operator typing a request at the mayor | Its prompt answers questions from what it can read. For anything to be done, it files a bead or a human gate, or says whose job it is. |

`deacon-`, `refinery-` and `witness-human-gate-wiring.test.sh` keep their assertions.
Their reason changes: "there is no mayor mailbox to absorb it" becomes that the mayor's mailbox
is not an escalation channel. "Mail dedups nothing" goes, because `gc mail send`
has `--dedup` now.

### The witness

The later ruling asks which this is: a difference this effort ends, or one that
stays. It stays, if ruling 3 goes as recommended. The initiative's description says
"Escalations stay visits and gates", and `docs/built-once-target.md` gains it among
the witness's differences from Gas Town:

- **Reason:** Gas Town's witness mails the mayor for emergencies, failures,
  recovered and handed-off orphans and queue health. "Owner of little" rules that
  load out. The missing dedup cited in the old comments is not the reason, since mail
  has it now.
- **What ends it:** an operator ruling that gives the mayor escalation handling.
- **Owed by tk-1tfzr71.19:** Gas Town's formula addresses `mayor/` literally, and a
  bare name now resolves to this seat. So taking the role by import would start
  this mail on its own. A copy must keep findings and human gates, or the import must be
  ruled.

### Where the mayor differs from Gas Town's

A role's default is Gas Town's, and each difference names its reason and what ends
it (visit tk-dbpz6t2, said of the witness and applied here as this design's own
reading). The agent shape is the same as Gas Town's: `scope = "city"`,
`wake_mode = "fresh"`, `work_dir = ".gc/agents/mayor"`, `idle_timeout = "1h"`,
`max_active_sessions = 1`. Each difference below ends with an operator ruling that
gives the seat the job.

| Gas Town's mayor | This city's | Reason |
|---|---|---|
| `mode = "always"` | `mode = "on_demand"` | It has no unattended work, and an always-up session invites sends |
| Dispatch liberally | Places queue beads only, on a ruling | Owner of little |
| Fix directly when fast | Changes no repo | The pools do the work, and mechanik edits the town repo |
| Handles escalations | Files or points | Findings and human gates carry them |
| Rig wake and sleep | Reads only | The operator's and mechanik's today |
| `gc handoff` when context fills | No handoff, no carried memory | A resident context is one symptom the record names |

## 2. What "overseer of all" means at landing

The mayor may read anything and writes only queue acts. It reads inside a sitting,
when the work or the operator's question calls for it. No schedule makes it read,
and it reports nothing nobody asked for.

- **For the queue:** `gc beads list --label hold:mayor --format=json`, each bead's
  card with `gc bd show`, the open epics and what holds them, and the `AGENTS.md` of
  the bead's rig, since a rig can say where a kind of problem goes, as gc-toolkit's
  does for code its deletion plan retires.
- **For the operator's questions:** `gc status`, `gc session list`, `gc rig list`,
  the board, open PRs, any bead.

It starts fresh for each sitting, through `wake_mode = "fresh"` and `on_demand`. A
detach does not end a sitting, because Gas City keeps a running on-demand session up
until it idles past `idle_timeout`. So a sitting ends when the operator says it is
done and the mayor runs `gc runtime drain-ack`, or after an hour idle. An attach
inside that hour continues the sitting, and the first wake after it is a new
conversation. Each ruling lands on its bead before the next piece, so nothing is
lost. The prompt forbids `gc handoff`, and the seat's `env` sets
`CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`, because a handoff note or a memory file would
rebuild the resident context by another route. Unit 3 proves all of this live, since
it was read from the source and not run.

## 3. Which coordination jobs leave mechanik

Only placement, and it matches the operator's sentence quoted above:

- **The placement sitting** moves to the mayor. So does the batch sort in
  `.gc/agents/mechanik/placement-2026-10-31/`, the method on tk-hok6w's newest
  Current state block. The sorter's brief becomes a skill written with no rig's
  details in it.
- **tk-rl8gz4b.17 stays mechanik's, smaller.** Its move 1 edits the town repo, which
  only mechanik does, and its timing stays the operator's. Its move 2 ran on
  2026-10-14 and the cut-over below replaces the marker it wrote, so a note says so.

Parks and priority moves are the next candidates, since they are not about
gc-toolkit's effectiveness. They stay where they are, because the initiative's
description makes a new ownership an operator ruling and nobody has ruled it.

## 4. Placing as one act, and how a hold lifts

`gc sling` reads no hold, so a sling leaves the label on. The hook then serves the
bead to nobody and the controller wakes nobody for it, the refinery after a hand-off
included. Nothing native places and lifts in one write, because a sling is a separate
command. So placing is one verb that runs the native writes in a set order and can be
run again.

```
gc-helm.sh place <bead> --under <epic> [--shift <±n>] [--route <rig>/<pool>] [--on <formula>]
gc-helm.sh place <bead> --standalone [--route <rig>/<pool>] [--on <formula>]
```

`--under`, `--shift` and `--standalone` come from tk-rl8gz4b.13, the verb this
replaces. `--route` takes the form `gc-helm.sh takeaway` gives it, and `--on` is
`gc sling`'s. With no `--route` it uses the polecat pool of the bead's rig, and with no
`--on` that pool's default formula. It writes in this order:

1. It refuses a closed bead and a bead carrying `anchor_bead`. A bead with no
   `hold:mayor` is refused, or reported as already placed when a live run works it.
2. It clears any route, because a `--fix` may have written one and
   `deferred-dispatch.sh arm` refuses a routed bead. With `--under`, it removes any
   relates-to edge between the two, sets the parent and reads it back. `--shift`
   writes the shift.
3. It runs `queue-priority.sh settle`, as `rework-child.sh` and `gate-ensure.sh` do
   before they sling, because a pour copies the priority once.
4. It dispatches, unless an assignee or a landing state shows that an earlier run of
   the verb already did and stopped before its lift. When `hold-lib.sh` says a blocker
   holds the bead or an ancestor, it arms the re-dispatch, so a park keeps holding.
   Otherwise it runs `gc sling`, whose exit 3 means a live run of that formula already
   works the bead, and it goes on.
5. It lifts, in one write: `gc bd update <bead> --remove-label hold:mayor
   --append-notes "Placed ..."`, and reads it back. This write leaves the route alone,
   because a sling that falls back to a plain route needs the one it wrote.

**Dispatch comes before the lift.** A sling that fails leaves the bead held, in the
queue, where someone is looking. Lifting first would leave an open, unrouted bead in
no queue, which is the shape this effort removes. If a crash lands between the two,
the run goes on with the hold still on it. The queue still lists the bead, the check
names it, and running `place` again finishes the lift without a second run.

**A hold lifts in one of these ways:**

- `place` lifts it.
- `gc-helm.sh takeaway --release --route` and `gc-helm.sh accept` lift it, because a
  route the operator writes through either is a placement.
- A close leaves the label on a closed bead, which nothing reads.
- `gc bd update <bead> --remove-label hold:mayor` lifts it by hand. An `until` edge
  onto a retiring bead takes this write too. A bead lifted this way with nothing else
  written is raw input again, so the scan reacts to it when intake is on and the
  sweep names it until then.
- `set-state` cannot do it, because it refuses an empty value and no state command
  removes a dimension.

A bare hand sling of a held bead is not caught when it runs. The check names it on
its next pass, and `place` finishes it. The work skill tells an agent to use `place`
for a held bead.

## 5. Whether the mayor may place routine work itself

This is ruling 1 above. At the recommended answer the authority map's rows read as
follows:

- **Hold new work:** the same writers, with `hold:mayor` in place of the marker.
- **Place a held bead:** the operator directly, or the mayor on the operator's ruling
  in a sitting. The mayor may never place without one.
- **Close-with-successor:** the mayor joins its callers, on a ruling in a sitting, as
  converse is today.

## 6. Who notices a placed bead whose run ended with the bead open

**At landing, the liveness sweep still does.** A placed bead carries no hold, so its
classifier reads it as an unnamed wait, which is what the sweep does with that shape
today. PR #1369 chased a pour's stale stamp hiding a marked bead from the queue. With
no marker and no inference, that shape no longer exists.

**After tk-1tfzr71.19 retires the sweep, its replacement owes this, as a doctor check
or a board view.** The shape is: open, no hold, no wait, no landing state, no live run
by `run-lib.sh`, and a pour's stamp left behind. The mayor reads that list in a
sitting and holds each bead with
`gc bd set-state <id> hold=mayor --reason "its run ended"`. That puts it in the one
queue, where `place` can send it again, since `place` refuses a bead with no hold. The
mayor is overseeing here and owns nothing new. The note tk-rl8gz4b.30 writes on
tk-1tfzr71.19 carries this.

**The cause stays where it is.** A graph.v2 run does not claim the bead it works, so
an ended run leaves nothing on the bead that says so. Gas City's nearest reads do not
tell this case apart: `gc convoy stranded` lists every unassigned tracked bead,
including those under a live run, and the orphan sweeps act on assigned beads or on a
branch with a session back-reference. tk-1tfzr71.12, which rebuilds the work formula
on core's base, is where this cause can be fixed.

**It is rare.** On 2026-11-01, of the beads `bd ready` offers in this rig's store, 6
of 525 carry a pour's stamp with no live run, and one of those has a PR. Each exit of
`mol-polecat-work` that can leave its bead open already writes where it went: a decline
files its gate and its wait, and a store-only run writes its record, with a closer when
the record finishes the bead. What remains is a hand cancel, a finding whose reaction
has ended, a store-only record nobody has closed, and old residue. That rate does not
justify a new detector before the sweep retires, so this design adds none.

## 7. How this squares with `docs/built-once-target.md`

The page says "What a person owes is a native human gate on the bead it blocks". This
design leaves that sentence true and adds placement beside it, because a held bead
owes nobody an answer:

- **A gate is one bead waiting on one person's judgment,** and something is overdue
  while it stands. Gas City's `await_type=human` means that, its orders can notify and
  renudge on it, and here a sitting can answer it.
- **A hold says the next actor is a seat.** It carries no debt. A bead can sit in the
  queue for weeks with nothing overdue, and the queue is worked in pieces when the
  operator chooses.
- **The operator steered this way on 2026-10-31:** "some conversation / visit or
  active agent that I engage to discuss open items... Not a fan of the fix cadence or
  fixed set to accept", and "I feel like 187 being done one at a time is going to
  consume quite a bit of tokens". A gate per bead is that one-at-a-time ask (quoted on
  tk-1tfzr71.17 and tk-hok6w). So tk-1tfzr71.17's "a native human gate for ... a
  placement" goes, and a note there says so.
- **They combine.** A held bead whose first reaction owes the operator a real question
  still files a gate through the ruling exit.

The page gains this under Human engagement:

> New work no epic holds is owed to nobody. It carries Gas City's `hold:mayor`, and the
> mayor, a fresh on-demand session, works that queue with the operator. A hold is the
> next actor's queue, and a gate is an answer someone owes.

It also lists the mayor's differences from Gas Town's above, and states the witness's
difference in its Patrol section. That section's list arrives with tk-r4c0g67's
branch, whose line says the difference ends when this design rules. So the unit
rewrites that line if the branch has landed and writes the paragraph if it has not.

## 8. Moving each writer and reader

Each file was checked against `tools/deletion-plan.tsv` at d983f9f50, main once PR #1359
landed.

| File | On the plan | What it does after this |
|---|---|---|
| `assets/scripts/first-reaction-dispose.sh` | no (tk-1tfzr71.17 rewrites parts) | Intake writes `set-state hold=mayor` with the reason it already builds and reads the label back. Its note names the queue read. `--assign` and `--then-assign` refuse the mayor's address. |
| `formulas/mol-witness-patrol.toml`, `bug-file` | no | `--labels hold:mayor` on the create, with its prose and the suite that pins it, `witness-route.test.sh`. |
| `formulas/mol-feedback-distiller.toml`, file-and-dispatch and 1b | no | The same, on each `prompt-update` and engineering bead, with `distiller-file-for-placement.test.sh`. |
| `skills/work/SKILL.md`, `agents/proactive/prompt.template.md`, its `agent.toml` and `PROVENANCE.md`, `formulas/mol-deacon-patrol.toml`'s prose, `skills/learning-distill/SKILL.md` | no | Wording, with the exact commands. The deacon's step gains the known check. |
| `assets/scripts/placement.sh` and its test | no | Deleted. |
| `assets/scripts/dispatch-path.sh` | no | Gains `has_dispatch_hold`, read the way Gas City's `HasDispatchHold` reads: either canonical value, trimmed, any case. The queue's readers already source this file. |
| `assets/scripts/gc-helm.sh` | no (tk-1tfzr71.24 rewrites parts) | `unplaced` goes with its suite, `gc-helm-unplaced.test.sh`. So do `stamp_hides_placement` and the failure it raises, and a surviving stamp only warns. `place` arrives, and the two routing verbs lift the hold. |
| `tools/gc-proactive.sh` | no | `(has_dispatch_hold \| not)` in the filter. |
| `doctor/check-blocked-work-armed` | no | Reads the label on the row it already has, so its second `bd list` and its "could not be read" warning go. |
| `assets/scripts/liveness-classify.sh`, `-recheck.sh`, `-sweep.sh`, `-sweep-precheck.sh` and their suites | **yes, tk-1tfzr71.19** | The smallest edit that lets `placement.sh` go: the source line drops, the predicate's name swaps, and the line of text a census gate carries names the new read. They gain no behavior, the PR's size line shows these lines against the retiring bead, and a note on it says why. |
| `assets/scripts/quota-park-nudge.sh` | **yes, tk-1tfzr71.18** | The one-word default above, with its note, and the two places `docs/quota-park-recovery.md` states it. |
| `assets/scripts/deferred-dispatch.sh` | no (tk-1tfzr71.16 rewrites parts) | Sources `dispatch-path.sh`, and its reconcile leaves a held bead alone, because a sling reads no hold, so a held bead with an arm would pour. `arm` still accepts one, because `place` arms and then lifts. |
| `assets/scripts/gc-terminal-attach.sh`, its test, `services/helm/README.md`, `services/helm/web/src/terminal/endpoint.ts`'s comment | no | The default path above. |
| `lifecycle/lifecycle.toml`, `[metadata.placement]` | no | Marked retired by unit 1. The follow-up removes it and adds `placement` to `check-state-space`'s `RETIRED_KEYS`. |
| `docs/steering.md`, `docs/authority-map.md`, `docs/architecture.md`, `docs/component-model.md`, `docs/feedback-learning.md`, `docs/built-once-target.md`, `docs/human-engagement.md` | no | State what is true after landing. `architecture.md` loses "There is no mayor" and gains the seats. The authority map's human gate row loses "there is no mayor", and says a gate, not the mayor's mailbox, carries what a person owes. |
| `docs/review-demo.md` | no | Its example of a report command names `gc-helm.sh unplaced` and that verb's suite, so it takes another verb's. |
| `services/helm/internal/board/derive_test.go` | no | The fixture drops its marker. The board has no reader of it. |
| `deacon-`, `refinery-` and `witness-human-gate-wiring.test.sh` | no | The comment above. |

Left alone on purpose: `doctor/check-hq-marooned-work/doctor.toml` already names a
mayor as a city-scoped role, and that stays true. `docs/warrants.md` and
`docs/gascity/routing-model.md` state Gas City's hold, which does not change.
`formulas/mol-review.toml`'s "the mayor's" is an example of a claim. `lifecycle.toml`'s
"the mayor's beads" and `RECONCILE_MAYOR_ADDR` go with tk-1tfzr71.14.

### The beads already carrying the marker

The census on 2026-11-01 read every store, the suspended rigs' included, since they
share the city's Dolt server. 53 open beads carry the marker, across five stores and
three of them suspended. In the running rigs, 29 read as waiting and 3 as already
placed. The list is in this bead's notes, and the count moves as beads are filed.

The cut-over is the same commands run twice. A bead that still reads as waiting takes
`set-state hold=mayor --reason "held for placement before the native hold"`. A bead
already placed takes nothing. After landing, every bead also loses the key.

- **Before the effort's PR merges,** the first pass adds holds in the stores whose scan
  is on, which the town's `proactive-scan-sling` overrides say. Those are the stores
  where a scan would otherwise spend first reactions on these beads after landing. The
  old and new readers both read a bead with both as waiting, so no reader needs a
  transition mode. Two things live in that window do not know the hold, and the narrow
  pass keeps what they reach small. A placement through the old verbs leaves the hold
  on. The deacon's live step can answer the new doctor warning with its `--fix`, whose
  route takes the bead off `gc-helm.sh unplaced` until landing.
- **After it merges,** a bead armed behind tk-rl8gz4b.28 runs the pass in every store,
  for anything filed since as well. It runs `place` on a held bead that a live run, a
  landing state or a route other than the mayor's shows was placed in the window. It
  unsets the key everywhere and lands the registry change above. If ruling 2 says so,
  the same bead also holds the pile.

These are commands in a bead's description, so the repo gains no migration script.

## 9. The session's cost

On demand. The token cost does not decide it:

- A wake's first turn loads about 40k to 50k tokens, going by recent mechanik and
  deacon transcripts, and mechanik started 11 conversations over the last week. A first
  reaction is about 3.2M tokens (tk-1tfzr71.17). An idle session spends nothing.
- What decides it is what each mode invites. An always-up session is a live address
  that shows as active in `gc session list`, which is the resident agent the
  initiative's description records as a symptom.
- On demand fits how the seat works, since nothing here runs unattended, and held work
  wakes nothing, because Gas City leaves held beads out of wake readiness.

The operator's door is `gc session attach gc-toolkit.mayor`, or bare `mayor`, which is
the command Gas City documents. An on-demand session materializes on that reference.
The helm terminal's `?session=` passes its guard once the session has been
materialized, or from any start if the operator sets `GC_TERMINAL_DEFAULT_SESSION`.

## What is ours, and what ends it

| Pack piece | Kind | What ends it |
|---|---|---|
| `gc-helm.sh place` | Glue: native writes in a set order, adding no state | `gc sling` lifting a hold, or tk-1tfzr71.24 folding it |
| `has_dispatch_hold` | Forced: shell readers need Gas City's predicate over JSON rows | A reader moving to Go or to a native filter |
| `doctor/check-mayor-queue-only` | A feature: the invariant "owner of little" needs in order to hold | An operator ruling that gives the seat more, which changes what it asserts |
| The mayor's agent, prompt and batch-sort skill | Configuration and prose on a role Gas City ships | Each difference above ends as it says |
| One known doctor warning | Contained debt from Gas City's check | Upstream's fix reaching the fork |

This design adds no pack noun, because `hold:mayor` and the mayor are Gas City's. It
removes the one pack noun the marker was, which never had a warrant.

## The units

`tk-rl8gz4b.30` files these under the epic, each with
`target=integration/tk-rl8gz4b.28`, and makes `tk-rl8gz4b.28` and the summary task wait
on each. They run in order, because they share files.

1. **The hold.** Writers and readers move to the label, `placement.sh` and `unplaced`
   go, and the registry entry is marked retired, per the table above. Steering's intake
   sections and the authority map's hold row are rewritten. Done when a first reaction,
   the witness and the distiller each leave a bead carrying the label with no marker,
   and the scan, the sweep and `check-blocked-work-armed` each leave it alone.
2. **Placing.** `gc-helm.sh place` and the two routing verbs. tk-rl8gz4b.13 closes,
   with this unit as its successor. Done when `place` on a held bead ends with a live
   run and no label; a failed sling leaves the label on; and a second run after a stop
   at any write finishes the job. Placing under a parked epic must arm instead of
   pouring. Steering's "Placing a bead" and the authority map's place row come with it.
3. **The seat.** `agents/mayor/` with its prompt, carrying the method and the exact
   commands; the batch-sort skill; the `pack.toml` stanza with `mode = "on_demand"`; the
   `agent.toml` with its empty `default_sling_formula`, refusing `sling_query` and `env`;
   the default paths in the table; a line in mechanik's prompt
   saying placement is the mayor's; and `architecture.md`, `built-once-target.md`, §4 of
   `component-model.md`, and the seed audit's render. The prompt and skill are pack
   content, so they name no rule that binds only gc-toolkit. The seat takes the
   `gh-origin-guard` overlay, as mechanik does, which touches that warrant, so the unit
   re-verifies it. Done when a live probe shows that
   an attach materializes the seat and starts a new conversation with no memory index,
   a detach leaves it up, `gc runtime drain-ack` or an hour idle ends it, and the next
   attach starts another conversation. Plain mail wakes nothing, and a nudge wakes it for
   one turn. The probe also tries `gc sling` to the seat. Without `--on` it should exit
   non-zero, and with `--on` the run pours and the check's first arm names its steps. The
   unit records any result that differs.
4. **The check.** `doctor/check-mayor-queue-only`, with its invariant in §3 of
   `component-model.md`. It reports an unheld bead or a run's step routed or assigned to
   the mayor, unread mail from anyone but `gc-start-warmup`, a held bead that is not new
   work, and a held bead carrying an arm, an assignee or a live run. It exempts no
   `human` sender, because an exec order's mail carries that sender too. Done when each
   arm fails on its fixture and the live city reads clean.
5. **The first pass.** A store-only bead running the first pass above. It waits on the
   four units and runs before the summary task.
6. **The follow-up.** Filed by unit 5, armed behind `tk-rl8gz4b.28`, and not waited on
   by it, since it runs after the merge. It runs the second pass and lands the registry
   change, in a PR of its own to main.

`tk-rl8gz4b.30` also writes the notes this design promises, on tk-1tfzr71.14, .17, .18
and .19 and on tk-rl8gz4b.17, when it files the units. They wait for the approval, since
until then every answer here is proposed.

**Branches that overlap.** PR #1359 landed on main at d983f9f50, after the integration
branch was cut at c41d2ea1d. It rewrote much of this ground: `gc-helm.sh`,
`first-reaction-dispose.sh`, `deferred-dispatch.sh`, the liveness scripts, `lifecycle.toml`,
the witness formula and the docs above. Building on the older copies would mean rebuilding
them, so unit 1 merges origin/main into the integration branch first, and each later unit
branches from that. The merge brings comments and gate text naming `awaiting_placement` and
`gc-helm.sh unplaced`, which unit 1 moves with the rest. #1217, #1373 and #1375 edit the
witness formula or the docs here and add no reader of the marker, so they take no edge, and
the effort's branch merges main again before its PR. `tk-ssm8qns.12` deletes `hold-lib.sh`
in favor of `gctk bead holds`, and `place` calls whichever is on main when it is built.

## What this leaves in place

- **The cost of waiting for this effort:** `placement=pending` keeps working as it does,
  and its known gap stays open, since PR #1369 was retired for this.
- **Intake:** gc-toolkit's stays off (operator, 2026-10-26), and whether first reactions
  return there stays the operator's call, on the numbers on tk-hok6w.
- **A short queue read:** a store that fails inside `gc beads list` drops its rows with
  no notice, because the command prints the API's rows and leaves out its
  `partial_errors`. `gc-helm.sh unplaced` reports this today, and that goes. Nothing acts
  on a bead's absence from the queue, so a short read costs one sitting a look at those
  beads, and the store's failure shows in `gc doctor`. Its rows also carry no priority,
  so the mayor groups by subject and reads a bead's priority when it discusses that bead.
  Its JSON is an array from the direct read and `{"beads": [...], "_cache_age_s": n}`
  through the API, so the prompt's command and the check accept both, and rows from the
  API can lag by that age.
- **Hand slings:** see section 4.
- **A nudge to the seat:** it costs one first turn and leaves nothing for the check to
  read. `gc sling --on` to the seat is refused by nothing, and the check names it.
