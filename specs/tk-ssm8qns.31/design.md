---
name: Design — the first reaction's deficiencies, now that it runs in gctk
description: The design for tk-ssm8qns.31, the design child of tk-ssm8qns.21, read at main 508a9324c. Read it to rule on what the sitting on the first reaction's move found, one item at a time, to build what you ruled as tk-ssm8qns.32's units, or to learn which of the reaction's store reads a narrower read can replace and where its answer would differ.
---

# Design: the first reaction's deficiencies, now that it runs in gctk

This is the design record for tk-ssm8qns.31, the design child of tk-ssm8qns.21.
While the first reaction's move into gctk was being designed, a converse sitting
found what the items below name (conversation tk-8nri3k3, 2026-11-16). You ruled
that the move carries what exists and that these are investigated once it lands,
and it landed as PR #1573. The pack was read at main 508a9324c, and a line
number in one of its files is at that commit. Gas City is cited by symbol, with
line numbers at upstream main 1feaf7eeb7, and the city's build 6589a7df45
carries every symbol cited. bd is 1.3.4, cited in its v1.3.4 source. A path in
Gas City's or bd's source says whose it is. The figures were measured on
2026-11-19 between 09:00Z and 09:20Z, in the gc-toolkit store unless a figure
names another. Its issues table held 86,611 beads, 85,811 of them closed. The
reaction's commands ran from a build of 508a9324c, through a stand-in for `gc`
that logged each call and refused every write.

## What you rule on

The first reaction now runs in gctk, and this design says, for each thing the
sitting found, whether to change it. 1a makes a check faster and 1b makes an
idle sweep read far less, both with the same answers. 3a fixes a rule that
refuses routes to pools Gas City runs without a cap. 3b and 6a hand two
questions back to Gas City's own answers. The other rows keep what exists, or
leave it to work that already owns it.

Each row is one ruling, and you can take or refuse each one alone. Approving the
design as it stands takes every recommendation, and refusing a row takes the
other way it names.

| # | The finding | Recommended | What approving it ships | The other way |
|---|---|---|---|---|
| 1a | To find the runs on its subject, a check scans every bead the store holds, closed ones included, and it reads two other things twice | Read live runs alone, and each thing once | A check about 1.5 s faster than its 3.9 s today, with the same answer | Keep the scans, whose cost grows with every bead the store closes |
| 1b | Each sweep reads the city's roster, 2.5 MB, before it knows whether it has anything to sling | Ask about the pool only once a candidate exists | About 0.9 GB a day less read across the four rigs that sweep while passes find nothing, with the same slings | Keep reading the roster on every pass |
| 1c | Each check reads the store's whole blocked set, 2.8 MB, to learn what holds one bead | Ask bd for a blocked read of named beads, and change no code now | One ask, which you send or drop | Copy bd's blocked rule into gctk, which must then follow every change bd makes to it |
| 2 | The recommend exit, the only setter of the key your Accept takes, unused since 2026-10-13 | Keep it, and leave its future to the board's easy-approvals epic | Nothing changes | Retire the exit with the key, Accept, a sitting's invalidation and the sign-off's accept |
| 3a | The pool rule reads Gas City's "no cap", -1, as a pool that runs no sessions | Read only a cap of 0 that way | A route to an uncapped pool is no longer refused | Keep refusing routes to 49 of the city's 135 agents |
| 3b | `gctk reaction deliverable` works out from the roster what `gc sling`'s dry run reports | Ask the dry run wherever a bead is in hand | Gas City's own preview of the sling, in place of gctk's copy of its rule | Keep gctk's copy of the rule, with 3a's fix |
| 4 | How work reaches an interactive agent such as the mechanik | Design it as a bead under Steer work by epic, the epic that owns placement | A design bead there, and none of its design here | An epic of its own, or another home you name |
| 5a | One exit code per kind of refusal, though no caller acts differently on them | Leave it to the parked reaction redesign, whose target 2 removes the codes | A note on that bead | Collapse the codes now, in the five places that read them |
| 5b | "May this bead take a reaction" is asked at four points under two rules, and in one case the check and the sling disagree | Leave it to the same redesign, whose target 1 moves the question to the offer path | A note on that bead | Make the check apply the sling's rule exactly now |
| 5c | The emergency lane, which routes a fix for a red main at P0 past placement, used once in the month counted | Keep it | Nothing changes | Retire it, so such a fix waits for placement |
| 5d | The blocked exit files the bead its subject waits on, and arms the subject's dispatch | Keep both | Nothing changes | Retire either act |
| 6a | The arm's start keeps its own guard for a pour Gas City left unfinished, the guard you ruled Gas City's for the reaction | Remove it, as the reaction's was removed | A dispatch whose pour a killed client left fenced reads as sent, and nobody is asked | Keep it until Gas City finishes or clears such pours |
| 6b | Accept cannot see a pour Gas City left unfinished | Hold the report on the board member that rewrites Accept | A note there, and a wait | Fix Accept's search now, in code that member rewrites |
| 6c | The ask that Gas City finish or clear such pours, whose first part an open upstream issue already asks | Send its second part as an issue, and its first as a comment on that issue | Your send | Leave it held |

Section 7 lists the units tk-ssm8qns.32 builds from what you approve.

## 1. The reads

Three kinds of read grow with the store rather than with the question: a read of
a whole set to answer for one bead, a read of whole rows where ids or a few keys
would do, and a filter that scans closed beads to find live work. You named the
second in your comment on PR #1538, which opened conversation tk-8nri3k3: "it's
still somewhat crazy that the city is moving 3.4MB of bead rows in order to
evaluate what actions to take. Worth something looking into a better long-term
fix for this". You named the third in that conversation, on 2026-11-16 at
17:01Z: "Seems weird to read close beads we dont' care about, that's pure waste
that onyl grows." On narrowing a read you said, in the same turn: "if that's a
clear optimization that has no negative consequences, sure, but I'm not
confident tit's been analyzed." So each narrower read below names every case
where its answer differs from today's.

What each command reads, measured through the logging stand-in:

| Command | Calls | Bytes | Time in gc | Wall time |
|---|---|---|---|---|
| `check` on a subject nothing holds | 11 | 2,823,844 | 2.6 s | 3.0 s |
| `check` on a subject a person's gate holds, which a convoy tracks as a reaction's subject is tracked | 15 | 2,833,673 | 3.9 s | 4.3 s |
| `sweep --dry-run` in gc-toolkit, nine candidates | 5 | 5,197,788 | 1.7 s | 1.8 s |
| `sweep --dry-run` in one rig where the sweep runs, no candidate | 2 | 2,705,488 | 0.5 s | 0.6 s |
| `sweep --dry-run` in another such rig, no candidate | 2 | 2,560,920 | 0.35 s | 0.4 s |

A sling applies the check's refusals before it calls `gc sling`, so a sweep pays
the check's reads again for each candidate it slings. The sweep runs every 15
minutes in four of the city's rigs, and the town's `city.toml` turns it off in
gascity and gc-toolkit.

Each read, what the command uses of it, and its narrower form:

| Read | Made by | Size and time | Used | Narrower read | Where its answer differs | Ruling |
|---|---|---|---|---|---|---|
| The runs on the subject: `gc bd list --all --metadata-field gc.input_convoy_id=<convoy>` for each convoy that tracks it, then `--all --metadata-field gc.var.issue=<subject>` (`waits.RunsOf`, `services/gctk/waits/run.go:75`) | check, sling | 0.65 to 0.76 s each, a scan of every bead, returning 0 to 5.6 KB | live runs alone (`services/gctk/reaction/refusal.go:208-221`) | the same filters without `--all`, 0.11 to 0.12 s | a run whose root bd's listing hides without `--all`: one pinned, by its status or by bd's pinned flag, or one with a status a store adds as done or frozen (bd's `internal/workapi/list.go:242-250` and `351-357`). No bead in the city's seven stores is pinned either way, and no store adds a status | 1a |
| The subject's row and the beads that track it, each read twice (`refusal.go:184` and `waits.go:144`; `refusal.go:294` and `run.go:76`) | check, sling | 0.15 s and 0.24 s a read | one read of each | one read of each | none: the second read follows the first within a second | 1a |
| The blocked set, `gc bd blocked --json`, and the store's marks (`services/gctk/internal/gcbd/blocked.go:308`) | check, sling, the blocked exit, a close exit that waits | 2,756,456 bytes for 280 beads in 0.34 s, 84% of it descriptions and notes, then 9,223 bytes of marks in 0.31 s | what holds the subject and its ancestors | bd 1.3.4 has none: `bd blocked` takes no id filter and has no brief form. bd's rule could be copied into gctk over the marks of the named beads | the copy agrees today, and differs wherever bd later changes its rule | 1c |
| The roster, `gc agent list --json` (`services/gctk/internal/gascity/roster.go:72`) | each sweep pass, `deliverable`, the dispose before a route or a hand-off | 2,479,524 bytes for 135 agents in 0.15 s, 98% of it each agent's `work_query` | a pool's or an agent's name, suspension and cap | no read on a pass with no candidate; `gc sling --dry-run` (item 3) | none in what a sweep slings | 1b, 3b |
| The sweep's ready set (`services/gctk/reaction/sweep.go:158`) | each sweep pass | 2,699,180 bytes for 346 beads in 1.1 s in gc-toolkit, 85% descriptions and notes; 81,395 to 225,963 bytes where the sweep runs | the candidate rule's keys, labels and edges, and whether a description is empty | brief rows with held beads left out, 133 rows and 128,272 bytes in 1.1 s, then the whole rows of the few that pass | none: the rule still reads every row | none: where the sweep runs, the read is already small, and its time does not change |
| The brief ready set, `gc bd ready --brief --json --limit 0` (`gcbd/state.go:39`) | a hand-off to the mechanik or the refinery, to decide its nudge | 312,545 bytes for 360 beads in 1.1 s | whether the subject is among them | bd's ready read of the agent's own beads: by assignee for the refinery, 0.37 s; by the route's key for the mechanik, 1,328 bytes in 1.26 s | a subject someone re-routes between the hand-off and the read: today its first agent is nudged, and the narrow read nudges nobody | none: six hand-offs in the month counted, and item 4 decides the hand-off's future |
| The live runs (`waits.LiveRuns`, `run.go:58`) | check, sling, sweep | three reads of live beads, about 18 KB in 0.45 s | the runs that work the beads asked about | none needed | none | none: it reads live beads alone, and little |
| The checks at the default branch's head (`services/gctk/reaction/emergency.go:46-53`) | an exit that claims an emergency | every page of check runs and statuses | the named check, and any other failing one, which the message names | check runs filtered by name | the message no longer names other failing checks | none: once in the month counted |

### 1a. Read live runs alone, and each thing once

The check asks for every run that works its subject, closed ones included,
because `waits.RunsOf` copies `run-lib.sh`'s `runs` verb, whose shell callers
read closed runs too (`blocker-holder.sh`, `gate-ensure.sh`, `queue-priority.sh`,
`work-lib.sh` and `gc-helm.sh`). The refusal then reads only the live ones. The
port carried the reads as the scripts made them (specs/tk-ssm8qns.18/design.md,
section 4), which is where the repeats come from too.

What changes: `waits` gains a live-only form of the runs on a bead beside
`RunsOf`, and the refusal reads it. The check and the sling read the subject's
row and the beads that track it once each. The measured check on a subject a
convoy tracks goes from 15 calls to 13, and from 3.9 s inside gc to about
2.4 s: 1.17 s comes off the two scans and 0.39 s off the repeated reads. Its
bytes barely change, because the scans returned little. What each command
decides does not change, except for a run whose root bd's listing hides
without `--all`, as the table says. The other way keeps both scans, which read
every closed bead on every check and grow as the store closes more.

### 1b. The sweep asks about its pool only once it has a candidate

The sweep asks whether its rig's proactive pool can take a reaction before its
ready read (`sweep.go:155`), and the answer reads the whole roster. In the two
rigs measured where the sweep runs, the dry run found no candidate, and the
roster was 92 to 97% of what the pass read. Asking
only once a candidate passes the candidate rule slings the same reactions. A
pass with no candidate then reads its ready set alone, 81 to 226 KB. At a pass
every 15 minutes in each of the four rigs, that comes to about 0.9 GB a day less
read while passes find nothing, as the measured ones did. A pass whose pool
cannot take a reaction now reads its ready set before it says so, and when it
finds no candidate its summary says it slung none, where today it says the rig
has no sweep. The other way keeps the roster read on every pass.

### 1c. The blocked set

The check learns whether a person's answer decides its subject from the store's
own answer about what holds it, which `waits` takes from bd and never works out
itself (`services/gctk/waits/waits.go:1-15`). bd has no read of that answer for
named beads: `bd blocked` lists every bead the store marks blocked, as whole
rows, and takes neither an id filter nor a brief form (bd's
`GetBlockedIssuesInTx`, `internal/storage/issueops/blocked.go:241-384`, and the
command's flags, `cmd/bd/ready.go:741-744`, which are `--parent`, `--label`,
`--label-any` and `--exclude-label`). gctk could instead copy bd's rule, which
names a bead's live `blocks`, `conditional-blocks` and `waits-for` targets and
otherwise its parent (bd's `blocked.go:286-367`), and apply it to the marks of
the named beads. The marks and the listing agree today, 280 beads in each with
the same ids. The copy would cut what is read from 2.77 MB to under 10 KB, but
its time only from 0.65 s for the two reads to about 0.3 s for one, since one bd
call costs about that whatever it returns. And it would put a second statement
of bd's rule in gctk, which has to follow every change bd makes to it.

Recommended: an ask to bd's maintainers for `bd blocked --id`, or a brief form,
which you send or drop. gctk changes nothing until bd carries one, and then
`waits` reads it with no change to what it answers. The other way builds the
copy now.

### The longer-term fix

Each kind of read above has its fix:

- A whole set read for one bead: ask the store about the beads in question,
  which 1c's ask is for.
- Whole rows where a few fields are used: read brief rows. bd offers them for
  `list` and `ready`, and Gas City offers none for its roster, but after 1b and
  3b the reaction reads the roster only for a hand-off to a named agent.
- A scan of closed beads for live work: read live beads alone, which 1a does.

1a and 1b need nothing from anyone else.

## 2. The recommend exit

When a reaction knows the action and judges that it needs your trigger, the
recommend exit files a human gate under `first-reaction` and records the formula
in `gc.recommended_formula`. The board then offers Accept, which slings that
formula on the bead (`gc-helm.sh accept`). A sitting takes it with
`converse-signoff.sh --accept`, or withdraws it with
`converse-invalidate-recommendation.sh`, and docs/design-convoy.md names it as
one way a design convoy starts. It came from PR #843 (2026-09-28), by the
sitting's tagging of the scripts' lines.

None of the 191 first reactions of 2026-10-15 to 11-15 took it, across six rigs.
It was last taken on 2026-10-12 and 10-13, for new work outside an epic while
intake was off, which intake's placement hold now covers (the sitting's count,
in tk-8nri3k3's notes). Seven open beads keep a recommendation, six in
gc-toolkit and one in gascity, the newest from 2026-10-02. None carries a gate
of any status, so the board offers Accept on none of them (`readAcceptance`,
`services/helm/internal/board/human.go:169`).

What else rests on it: the board's easy-approvals epic (tk-3d1d6p0) is about
accepting an agent's one recommendation on the board, which is what Accept does
for a reaction. tk-ssm8qns.23, which the port filed and did not arm, moves the
key's reads and clears onto the reaction domain. Accept's own code lies in the
path of the board member tk-1tfzr71.24 (section 6b), so the part of that move
that changes Accept's clear is work in code that member rewrites.

Recommended: keep it, and leave its future to that epic, which decides how any
agent's recommendation reaches you. You have not said you do not want it. The
other way retires the exit, the key, Accept, the invalidation script, the
sign-off's `--accept`, and the board's Accept button with its three conditions.
That cuts against the epic's aim, and a reaction that knows the action is left
the ruling exit alone, a question you answer in a conversation.

## 3. `deliverable`, and the pool rule it shares with the dispose

`gctk reaction deliverable` answers whether a pool can take work now, from the
roster: the pool is registered, not suspended, has at least one slot, and, when
a bead is named, sits in a rig that reads the bead's store
(`services/gctk/reaction/pool.go:26-65`). Four places act on its no:

- the sweep skips its rig (`sweep.go:155`);
- operator-intake files your topic as a conversation at once, so you do not wait
  on a reaction a stopped pool would not run (`assets/scripts/operator-intake.sh:395`);
- a patrol finding is left for the next sweep (`assets/scripts/patrol-finding.sh:605-608`);
- the dispose refuses, before it writes anything, a route nobody serves, so the
  subject is not left open and routed to no one (`dispose.go:316-338`).

It came from the scripts' pick-up probes, PRs #361 and #1000 (the sitting's
tagging read). Gas City's sling refuses a target the city does not configure and
a route into another rig's store. It warns, and never refuses, on a suspended
agent, rig or city and on a pool whose cap is exactly 0 (Gas City's
`newTargetResult`, `internal/sling/sling_core.go:246-260`, with the warning
codes `agent_suspended`, `rig_suspended`, `city_suspended` and `pool_empty` from
`slingJSONWarnings` in `cmd/gc/cmd_sling.go`). Its dry run writes nothing and
gives the same warnings. A route into another rig's store meets two refusals,
and the dry run skips one, the guard by bead prefix (`shouldGuardCrossRig`). It
keeps the other, the store check (`validateBuiltInRouteStoreReachable`, both in
`internal/sling/sling_core.go`), which refuses the same routes to a rig's pool on
Gas City's default sling query, as every pool of the pack's is, and checks
nothing for an agent with a sling query of its own. So `deliverable` turns Gas
City's warnings into a refusal, which its callers need, and it works out the
facts again from the roster.

### 3a. A cap of -1 is no cap

The roster prints -1 for every agent whose config sets no
`max_active_sessions`, and Gas City reads that as unlimited (Gas City's
`scaleParamsForTopology`, `cmd/gc/pool.go:243-247`, and
`EffectiveMaxActiveSessions`, `internal/config/session_capacity.go:23-24`). Its
own `pool_empty` warning is for a cap of exactly 0 (`sling_core.go:258`). The
pool rule answers no for a cap below 1 (`pool.go:61`), so the dispose refuses a
route to any of the 49 agents that read -1 on 2026-11-19: the claude,
claude-watch, codex and gemini agents (seven each), the witness (six), and
single agents such as design-author and implementation-worker. The pools a
reaction routes to by default carry a cap of 2 or 5, so no route is known to
have met it. A hand-off to a named agent is checked by `Assignable`, which reads
no cap.

Recommended: read only a cap of 0 as no slots. It is one comparison and its
test, and it is the whole fix when 3b is refused.

### 3b. Ask Gas City's dry run instead of the roster

The rule over the roster states again what `gc sling --dry-run --json` reports,
and 3a is where the two came apart. Recommended: wherever a bead is in hand, ask
the dry run of the sling about to be made, and read a refusal or any of the four
warnings as no.

- `gctk reaction deliverable` takes the bead. Both callers already hold it,
  since operator-intake stamps its subject first and patrol-finding files its
  finding first, so each passes it, a fix in place in each script.
- The dispose dry-runs its route, its closer's route and a `--then-route`, with
  the subject.
- The sweep dry-runs its first candidate. It reads as its pool's no only the
  four warnings and a target the city does not resolve, since a refusal about
  the candidate's own state says nothing of the pool, and that candidate's own
  sling meets it.
- The roster stays for a hand-off to a named agent, which `Assignable` checks
  (`pool.go:76`): the refinery's writes an assignee that no sling previews, and
  item 4 decides the mechanik's.

What changes: a cap of -1 passes, as in 3a. Suspension reads the same, because
the roster's `suspended` is already Gas City's effective suspension of the city,
the rig and the agent (Gas City's `agentSuspensionCauseWith`,
`cmd/gc/cmd_suspend.go`). A route into another rig's store is still refused
before anything is written, by the store check the dry run keeps, except a route
to an agent with a sling query of its own, which no pool of the pack's has and
which today's rule refuses by prefix. A roster that does not read answers yes
today, as no evidence that the pool is gone. A dry run that does not answer
keeps that rule, while a dry run's refusal is a no, and the unit tells the two
apart by the reply. Each answer costs one `gc sling --dry-run` call, which loads
the city's config as the roster read does. Its time is not measured here, since
this design's measurements ran nothing that slings. The other way keeps gctk's
rule, with 3a's fix.

## 4. How work reaches an interactive agent

The question reaches past the first reaction. Between 2026-10-17 and 11-14, 45
notices were armed for the mechanik across the six rig stores, and first
reactions sent 6 of them. Polecat runs sent 16, the mechanik itself 14, sittings
7, a validate run 1 and a reaction by hand 1, and the keeper got one, from a
sitting (tk-8nri3k3's notes, "Hand-off cases"). What decides the answer is where
work waits when only an interactive agent can do it. No pool works the town repo
or an agent home. The mechanik edits the town repo (docs/authority-map.md:119),
and `gc-helm.sh place`, the placement sitting's act, routes only to a pool.

That makes it a placement question. Recommended: its design is a bead under the
epic named Steer work by epic (tk-rl8gz4b), which owns the placement sitting and
the intake hold. The other way is an epic of its own for the seats that take
work by name, the mechanik, the keeper and the refinery, if you see the question
as wider than placement. Nothing of its design is decided here.

The facts the bead starts from:

- Your words, in conversation tk-8nri3k3 on 2026-11-16 at 17:01Z: "Beads
  shoudln't be ahnded straigth to the mechanik, that gets to the issue where an
  interactive agent suddenly gets random context that distracts it. Same with
  keeper. These agents shoudl get notified if it's directly related tot heir
  active work. At least that's my desire, but if we need a place for certain
  items to go, we can discuss if this is a hard line or a broad try if able."
- Your ruling for the port, "Yes, as recommended." at about 17:54Z, as the
  sitting's notes record under "Ruled and carried out": the mechanik's hand-off
  is carried as it works, the keeper is no longer a target, and this question
  goes to the follow-up.
- The month's six hand-offs by a first reaction went to the mechanik, and each
  was done within minutes: one town-repo edit, four cleanups on the host and one
  store rewire. The sitting's reader judged none of them related to work the
  mechanik had under way.
- On 2026-11-16 one such hand-off left the mechanik's session on a pending
  question for over ten hours, with later notices queued behind it.
- The hand-off exists because a town-repo fix sat routed to a person, unengaged,
  for about 58 hours (PR #1129, 2026-10-11).
- An ask open in the gascity store (gc-pn2gms) would have Gas City nudge a named
  session for work assigned to it that it has not claimed.

## 5. The smaller findings

### 5a. One exit code per kind of refusal

The check and the sling refuse with one of four codes: 3 when a reaction already
runs or a conversation tracks the subject, 4 when another live run works it, 5
when its next move is decided, and 6 when its kind takes no reaction
(`refusal.go:25-38`). No caller acts differently on them. The react step and the
proactive prompt end the run with no gate on any of the four
(`formulas/mol-first-reaction.toml:55`, `agents/proactive/prompt.template.md:68`).
`gc-helm.sh react` maps them to its own 5 to 8 (`assets/scripts/gc-helm.sh:3433-3448`),
and operator-intake, which calls react, files the conversation directly on every
one of them, changing only its message (`operator-intake.sh:422-436`). The sweep
counts its skips by them for its summary (`sweep.go:208-222`). The codes arrived
one fix at a time: 3 on 2026-09-06, 4 on 2026-10-07, 5 with PR #1207 on
2026-10-15, and 6 with PR #1520 on 2026-11-15.

The parked reaction redesign (tk-itv781b.1) has this as its target 2: "The prompt
makes one call per mechanical phase with a binary contract — go, or already
handled." It waits on a park gate (tk-u5t8h6x) that you release. Recommended:
leave it there, with a note on that bead naming these readers. The other way
collapses the codes into one now, with the reason in the message. That changes
the formula's step, the prompt, react, intake and the sweep's summary, puts this
effort into a redesign you parked, and changes react, which lies in the board
member's path (tk-1tfzr71.24).

### 5b. Four points, two rules

"May this bead take a reaction" is asked four times: by the sweep's candidate
rule (`sweep.go:60-85`, with `dropInFlight` at `:242`), by the sling's refusals
(`refusal.go:183-237`), by the check, which applies the same refusals and passes
over its own run and gate, and by each exit, which takes only an open subject
(`dispose.go:253`). The two rules are the candidate rule, which picks raw input
nobody has looked at (among its clauses: a description, a type of task, bug,
feature or spike, no headline, no parent, no work markers, and readiness), and
the refusals, which decide whether a bead may take a reaction at all. Each point
asks again because the bead can change in between: a sweep runs for up to five
minutes, and a claim can come minutes after its sling. The check at the claim
came with PR #1520 (2026-11-15), which made a reaction a run slung on its
subject, and the refusals with the codes of 5a.

In one case the check and the sling decide differently. The check counts its own
run as work in flight, because the run's one step is no load-context step, so
`pastLoadContext` reads it as started (`run.go:177-188`), and work in flight is
not held by an ancestor's wait (`waits.go:358-359`). So the check passes a
subject held through an ancestor's open human gate, where the sling refuses the
same subject with code 5. It can arise only when the subject comes to wait on an
ancestor's open gate between the sling and the claim. The sweep takes no subject
with a parent, and operator-intake and patrol-finding file theirs with none. This
was found by reading the code, and no case of it is known.

The redesign's target 1 moves the question to the offer path: "whatever hands R
to a worker refuses or closes it when S already carries the write-back proof or
an owner." Recommended: leave both the four points and the disagreement to it,
with a note. The other way makes the check apply the sling's rule exactly now, by
passing over its own run when it asks whether the subject is in flight, which
changes `waits`' read for that one caller and adds its test.

### 5c. The emergency lane

An actionable or blocked exit that names a failing check (`--emergency <check>`)
is admitted to a pool at P0, past placement, once the named check is confirmed
failing at the head of the repository's default branch (`checkMain`,
`emergency.go:25`; `dispose.go:269-305` and `456-467`). It is the reaction's
only GitHub read. It came from PR #1243 (2026-10-13), and it was used once in the
month counted (the sitting's count). Recommended: keep it. You have not said you
do not want it, and what it costs is its code, `emergency.go`'s 153 lines and the
dispose's branch for it. The other way retires it, and a fix for a red main waits
for your placement sitting like any other new work unless a person routes it.

### 5d. The blocked exit's blocker and arm

A blocked exit can file the bead its subject waits on when none exists
(`--blocker "<title>"`, one create that carries the subject's wait,
`dispose.go:375-400`), so the wait is an edge and not prose. It can also arm the
subject's dispatch for when the wait lifts (`--then-route`, `dispose.go:497-506`),
so nobody has to remember to send it. Since 2026-10-15, first reactions have
filed four blockers, all in gc-toolkit, and no arm a blocked exit wrote carries a
later date in its note. Intake explains the second: a held bead is armed by
nothing, and 63 of the month's 191 reactions held their subject for placement.
Both acts came with PR #554 (2026-09-01), which gave the reaction its actionable
and blocked exits, and they take 42 and 47 of the dispose's 158 lines for a wait
on another bead (the sitting's tagging read of the scripts). tk-v209ua2 holds
what is open about the exit: whether it converts an edge of another type that
the subject already has onto the bead it waits on, since bd refuses the wait's
edge beside it, and whether a hand-off writes its edges before its assignee.

Recommended: keep both. The other way retires either act. Without the blocker, a
reaction whose wait has no bead files one itself before the exit, in two writes
instead of one. Without the arm, a blocked bead that intake admits needs a person
to send it when its wait lifts.

## 6. The unfinished pour outside the reaction

When Gas City pours a run bead by bead, its fallback when the one-batch pour is
off or fails twice, it fences each bead with `gc.instantiating` until the pour
finishes, and a pour that stops part way can stay fenced. Gas City then counts
the root as live, so `gc sling` refuses another run of the formula on that bead
with exit 3 until a person runs `gc convoy delete <root> --force` (gc-3znzo8's
description, read at 6589a7df45). No such pour exists today. No bead in any of
the seven stores carries `gc.instantiating=true` or an open
`molecule_failed=true`, and the 321 beads that keep the key, empty, are
gc-toolkit's, from 35 pours of 2026-09-22 to 10-10.

Of the reaction's guard you asked: "why does this code need it when we don't
otherwise have this logic protecting the pack. This is city's responsibility,
right? And arguably somethign the architecture should just handle."
(conversation tk-8nri3k3, 2026-11-16 at 17:01Z). You then ruled that the port
leave it out, with an ask for Gas City written up (that conversation's notes,
"Ruled and carried out"). Two other places carry the same state.

### 6a. The arm's start

The deferred-dispatch start reads its earlier pours on a retry, by the token in
their titles, and the roots that an exit 3 of `gc sling` names. It treats a root
as unfinished when it carries `molecule_failed=true` or a fence on itself or on a
bead under it (`pours`, `services/gctk/arm/start.go:451-485`), and an open
unfinished root makes it ask a person, naming the root and the command that
closes it (`askUnfinished`, `start.go:520`). It came with the move of deferred
dispatch into gctk (PR #1503, 2026-11-14), whose design states it under "Exactly
once" (specs/tk-1tfzr71.98/design.md, section 4). It has never asked: no store
holds a gate under the key it asks under, which its cap on attempts shares, or
the conversation it opens instead on a bead that has an open child (`ask`,
`start.go:557`).

Recommended, as my reading of how far your ruling reaches: remove the fence
reads and the ask. A root that carries `molecule_failed=true` stays an attempt
that failed, which the start tries again under its existing cap on attempts,
and the cap asks a person once they run out (`askCap`, `start.go:539`). Any other
root it finds counts as the pour that landed. The cost: a pour that a killed
client left fenced, with no failure stamp, then reads as landed, so its dispatch
retires and its work does not run until someone notices. The start also stops
reading every bead under a root, a scan of the whole store for each root on each
retry. Your words in conversation tk-gy4953q (2026-11-17 at 23:40Z) bear on the
trade: "Building code that can't fail is different from building lots of code to
try and manage every failure." The other way keeps the guard until Gas City
finishes or clears such pours, which 6c asks for.

### 6b. Accept

Accept finds its own pour by searching for its token with `--all
--include-ephemeral` and without `--include-gates` (`accept_token_root`,
`gc-helm.sh:3900`), and a fenced bead is typed a gate, which bd's listing hides
(tk-fm9js29). So after such a pour Accept reports that the formula already runs,
and nothing runs. Accept's code lies in the path of the board member
tk-1tfzr71.24, whose contract reduces each `gc-helm.sh` verb to native writes,
and AGENTS.md gives such code no new work. Accept also runs only on a
recommendation, and none has been made since 2026-10-13 (item 2).

Recommended: append the problem to tk-1tfzr71.24's notes and hold tk-fm9js29 on
it, so that it is checked and closed once that member lands. The other way fixes
the search now by adding `--include-gates`, which AGENTS.md allows only as a
stopgap for harm to you now, and no such harm is current.

### 6c. The ask for Gas City

gc-3znzo8 asks Gas City to finish, fail or remove a root its fallback left
fenced, or to stop counting such a root as live, and to unset the key when it
lifts the fence. It is held for your placement in the gascity store, written for
you to decide and send. Its first part is already asked upstream:
gastownhall/gascity#6179, open, says "a client killed mid-instantiation leaves a
fenced workflow that nothing activates, voids or reports", and #6177 asks the
same of a pour that failed (tk-fm9js29). No upstream issue asks the second part,
searched on 2026-11-19. Recommended: send the second part as an issue and the
first as the city's case on #6179, since #6179's fix is what removes 6a's cost.
The other way leaves it held.

## 7. The units

tk-ssm8qns.32 builds what you approve on `integration/tk-ssm8qns.21`, one commit
for each unit, after a first act it makes whatever you rule. A unit whose rulings
you all refuse is not built, and a refused ruling's part of a unit drops out of
it. The effort's summary names the belief the units serve: the pack borrows
before it invents (docs/foundation.md), since they take what Gas City and bd
answer instead of working it out again, and they leave Gas City's states to Gas
City.

**The first act**, notes and filings with no code:

- tk-itv781b.1 gets a note with 5a's readers, 5b's four points and the case in
  which the check and the sling disagree.
- tk-3d1d6p0 gets a note with item 2's facts: the exit, the key's readers, its
  use and the seven beads that keep a recommendation. tk-ssm8qns.23 gets a note
  with item 2's ruling, and that its change to Accept's clear lies in
  tk-1tfzr71.24's path.
- Item 4's design bead is filed under the home you rule, with section 4's facts
  as its description, and that epic's own rules decide when it runs.
- tk-1tfzr71.24 gets 6b's problem appended to its notes, and tk-fm9js29 is held
  on it, as the `gc-toolkit.waits` skill's "Have a bead checked and closed once
  other work lands" says.
- gc-3znzo8 gets a note with 6a's ruling.
- 1c's ask to bd's maintainers is filed in the gc-toolkit store with section 1's
  figures, held for your placement and written for you to send, as gc-3znzo8 is.

**Unit 1: the reads and the cap (1a, 1b, 3a).**

- `waits` gains the live-only form of the runs on a bead, and a test holds it to
  the live runs in `RunsOf`'s answer over the run link's fixture. The refusal
  reads it.
- The check and the sling read the subject's row and the beads that track it
  once each.
- The sweep reads its ready set and applies the candidate rule before it asks
  about its pool, and asks only once a candidate passes.
- The pool rule reads only a cap of 0 as no slots, unless unit 2 replaces the
  rule.
- Each change has its test on the fakes, and a mutant that restores the old read
  or comparison, which the tests must fail.

**Unit 2: the dry run (3b).**

- The runtime adapter gains `gc sling --dry-run --json`, decoded to a refusal,
  the four warnings, or a call that did not answer.
- `deliverable` takes a bead, and operator-intake and patrol-finding pass theirs.
  The dispose asks the dry run before a route, a closer's route and a
  `--then-route`. The sweep asks it about its first candidate, and reads only
  the warnings and a target the city does not resolve as its pool's no.
  `Assignable` keeps the roster, for the hand-offs to a named agent.
- The pool rule over the roster goes, with 3a's comparison.
- Tests for each answer of the dry run, and the callers' suites updated.

**Unit 3: the arm's start (6a).** `pours` drops its fence reads, and with them
its read of the beads under each root. `askUnfinished` goes, and the cap's ask
keeps the key the two shared. A root carrying `molecule_failed=true` is a failed
attempt, and any other root found is the pour that landed, on a retry and on an
exit 3 alike. The start's tests for the unfinished pour go with it, and a test
pins each case that stays.

**Against the bead's Done when.** You rule on each row above at this design's
gate. What you rule to change lands through the units and the first act, and
what you rule to keep, or to leave with other work, is recorded on the bead
that owns it.

## 8. The Gas City search

Unit 2 adds one mode: `gctk reaction deliverable` takes a bead. The primitive
it composes is `gc sling --dry-run --json` (`newTargetResult` in
`internal/sling/sling_core.go` and `slingJSONWarnings` in `cmd/gc/cmd_sling.go`,
at upstream 1feaf7eeb7). It leaves out only the hand-offs to a named agent,
which keep `Assignable` (section 3b). Searched for one agent's facts as well:
`gc agent list` takes no selector, since its command drops its arguments
(`cmd/gc/cmd_agent.go`),
Gas City has no `gc agent show`, and the supervisor's read of one agent
(`agentByName`, `internal/api/huma_handlers_agents.go`) takes suspension from the
agent's config and its session alone, so it would read a pool in a suspended rig
or city as live. For 1c, bd 1.3.4's `blocked` has no id filter and no brief form
(section 1c), which is why 1c is an ask. Units 1 and 3 add no surface: unit 1
narrows reads and reorders one, and unit 3 removes the arm's ask.

## 9. The deletion plan

`tools/deletion-plan.tsv` at 508a9324c names none of the files the units change:
`services/gctk/reaction`, `services/gctk/waits`, `services/gctk/arm/start.go`,
the runtime adapter `services/gctk/internal/gascity`, the command's
`services/gctk/internal/cli/reaction.go`, `assets/scripts/operator-intake.sh`
and `assets/scripts/patrol-finding.sh`.
Accept's code and `react` in `gc-helm.sh` lie in the path of tk-1tfzr71.24, whose
row in the schedule retires the verbs that only call Gas City as partial files,
so no unit changes them (6b, and 5a's other way). No integration branch's
deletion plan names any of these files either.

Open work the units meet, read on 2026-11-19: unit 2 adds the dry run to the
runtime adapter, `services/gctk/internal/gascity/gascity.go` and its fake, which
PRs #1580, #1559, #1557 and #1550 also change, #1580 and #1559 in its `Sling`.
#1557 also changes `patrol-finding.sh`, and #1550 and #1597 change the adapter's
`roster.go`. #1596 changes `refusal.go` and #1584 `start.go`, each away from the
code units 1 and 3 change. Whichever lands second merges the other.
