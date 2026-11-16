---
name: Design — the first reaction moves into gctk as the reaction domain
description: The design for tk-ssm8qns.18, the design child of initiative tk-ssm8qns.17, taken at main 6dd9d13ee. Read it to approve the move of tools/gc-proactive.sh and assets/scripts/first-reaction-dispose.sh into gctk at its gate, to build one of its two units, or to learn how an open report against either script was settled.
---

# Design: the first reaction moves into gctk

This is the design record for tk-ssm8qns.18, the design child of initiative
tk-ssm8qns.17. The pack was read at main 6dd9d13ee, the commit
`integration/tk-ssm8qns.17` was cut from, and every line number is at that
commit. Each Gas City fact is cited by symbol at upstream main e60ed864f3
(2026-11-16), and the city's gc build, 6589a7df45, carries each symbol this
design relies on. bd is 1.3.4. The store figures were read on 2026-11-16
between 06:34Z and 07:20Z.

## What the operator approves

Every new bead gets a first reaction: a run of `mol-first-reaction` that reads
the bead once, writes a card on it and takes one of five exits. Two shell
scripts carry it today. `tools/gc-proactive.sh` holds the check a reaction runs
first, the sling and the scan, and `assets/scripts/first-reaction-dispose.sh`
holds the exits: 2,322 lines, with 3,236 lines of tests. On 2026-11-16 one of
their reads passed 3.4 MB of bead rows to jq as an argument, past macOS's 1 MiB
limit, and every reaction in the gc-toolkit store stopped at its first act until
PR #1535 fixed that read in place. Approving this design moves both scripts into
gctk as one domain, `reaction`, with five commands, and deletes the scripts and
their tests in the same change. What a reaction decides does not change, and
neither do the exits, their exit codes or the card. No store read passes rows
through a command line.

Three calls carry a cost either way:

1. **The recommendation key moves with the one exit that sets it, and three
   scripts keep spelling it until Accept moves.** `gc.recommended_formula` is
   the action a `recommend` exit leaves for your Accept, and that exit is its
   only setter, so the `reaction` domain takes over its declaration (section 2).
   Accept (`gc-helm.sh accept`) and a sitting's invalidation
   (`converse-invalidate-recommendation.sh`) still clear it, and the sign-off
   (`converse-signoff.sh`) still reads it. That departs from rules 1 and 6 of
   "The rules a domain move follows" in docs/gctk-architecture.md, as the arm's
   readers do under your ruling in conversation tk-au9jrqt. One Debt entry
   names it, with the follow-up bead that moves those reads and clears
   (section 9). The board's own read of the key is already under its Debt
   entry, which tk-1tfzr71.24 retires. The cost: one key declared in Go while
   three scripts spell it. The other way moves those reads and clears onto the
   domain now, which grows this Feature into Accept and the sign-off, outside
   its boundaries.
2. **The effort's PR to main waits for the pilot check.** The landing merges
   only once tk-1tfzr71.116 closes, after its pilot check holds and it lifts
   the pause, so the pilot rig's first ten reactions on the new path all run
   one implementation (section 7). The cost: the check wakes on 2026-11-20 and
   reads the pilot rig's first ten reactions on the new path, counted from
   #1520's landing, and while there are fewer it is deferred again. Ten took
   4.6 days on the old path, and the pilot had none at 2026-11-16T04:18Z, so
   the port reaches main on 2026-11-20 at the earliest, and later if filing
   stays slow. Nothing waits on the port meanwhile, because PR #1535 fixed the
   failure in place. The other way lands the port once its PR is approved and
   mixes the two implementations in the pilot's sample, so a failed check would
   not say which one failed.
3. **What no caller uses is not ported.** That is the sling's `--nudge` and
   `--dry-run`, the dispose's `--dry-run`, the scan's text output, four tunables
   nothing sets, the test fixture seam, and the prompt's clause for a leftover
   reaction bead, of which no store holds one (section 5). The cost: a person
   who ran one of those by hand loses it, and the sweep's dry run is the one
   listing left. The other way ports each one with no caller to hold it to
   gctk's bar.

Approving the design as it stands ships the first option of each. Section 5
names each behavior change, section 6 settles each open report, and section 9
lists the units.

## 1. The commands, from their callers

Each caller asks one question or takes one act, and each becomes one command:

| Caller | Asks today | Calls after |
|---|---|---|
| `formulas/mol-first-reaction.toml`, the react step | `gc-proactive.sh sling <S> --check --run <root>`: may this run react to its subject? | `gctk reaction check <S> --run <root>` |
| `orders/proactive-scan-sling.toml` | `gc-proactive.sh scan --sling`: react to every candidate in this rig | `gctk reaction sweep --db "$GC_RIG_ROOT/.beads"`, named in the order's exec line |
| `agents/proactive/prompt.template.md`, the exit blocks | `first-reaction-dispose.sh <S> --disposition <exit> ...` | `gctk reaction dispose <S> --disposition <exit> ...` |
| the prompt's clause for a leftover reaction bead | `gc-proactive.sh sling <subject>` | nothing: the clause goes (section 5) |
| `assets/scripts/gc-helm.sh react`, which `operator-intake.sh` calls | `gc-proactive.sh sling <bead> [--nudge] [--dry-run]` | `gctk reaction sling <bead>` |
| `assets/scripts/patrol-finding.sh`, at a finding's filing | `deliverable`, then `sling <bead>` | `gctk reaction deliverable`, then `gctk reaction sling <bead>` |
| `assets/scripts/operator-intake.sh`, choosing its path | `deliverable`, under the subject's rig | `gctk reaction deliverable` |
| `first-reaction-dispose.sh`, before a route or a hand-off | `deliverable <target> <S>` and `assignable <agent> <S>` | nothing: both become rules inside `dispose` |

The suites that stub or drive either script are callers too, and section 3
lists them. A person reads the scan by hand, as the mechanik did for the pilot
(tk-1tfzr71.116's notes, 2026-11-16T04:18Z), and the sweep's dry run serves that
read.

The commands:

| Command | Caller class | What it does | Exit |
|---|---|---|---|
| `gctk reaction check <bead> --run <root> [--db <path>]` | hook | the sling's refusals, read as the reaction's first act and writing nothing, with the asking run and a first-reaction gate whose message names that run passed over | 0 react; 3 to 6 a refusal; 1 decided nothing; 2 usage |
| `gctk reaction sling <bead> [--db <path>]` | agent, hook | the refusals, then `gc sling --rig <rig> <rig>/gc-toolkit.proactive <bead> --on mol-first-reaction`, and a human gate when Gas City left a pour of the formula unfinished on the bead | 0 slung; 3 to 6; 1; 2 |
| `gctk reaction sweep [--db <path>] [--dry-run]` | order; agent for `--dry-run` | one ready read, the candidate rule, then a sling of each candidate, highest priority first, until the sweep's deadline, with one JSON line per candidate saying what the sweep did or would do | 0; 1 when the ready read or the candidate rule fails, and nothing is slung |
| `gctk reaction deliverable` | hook | whether this rig's proactive pool can take a reaction now | 0 yes; 1 no |
| `gctk reaction dispose <bead> --disposition <exit> --reason <text> --takeaway <text> [--run <root>] [--by <who>] [--db <path>] [the exit's flags]` | agent | one exit, its writes in their order | 0 disposed; 2 usage, nothing written; 3 the subject is not open, nothing written; 4 stopped part way, and a re-run resumes |

The refusal codes keep their meaning, because three callers branch on them: 3
says a reaction already runs on the subject or an open conversation tracks it, 4
that a live run of another formula works it, 5 that its next move is decided
already, and 6 that its kind takes no reaction. `gc-helm.sh react` maps them to
its own 5 to 8, the prompt's check text names them, and the sweep counts its
skips by them.

Each exit's flags are declared in one table in the domain. A flag set for an
exit whose row does not name it is refused before anything is read, so a flag
added to one exit leaves the others unchanged:

| Exit | Its flags |
|---|---|
| `actionable` | `--route <rig>/<agent>`, with `--emergency <check>`; or `--assign <agent>` |
| `recommend` | `--recommended-formula <mol>` |
| `blocked` | `--waiting-on <bead>`, repeatable, and `--blocker <title>`, at least one of the two; then `--then-route <rig>/<agent>`, with `--emergency <check>`, or `--then-assign <agent>` |
| `close` | `--route <rig>/<agent>`; `--waiting-on <bead>`, repeatable |
| `ruling` | none |

**The names**, by "The rule that names a verb" in docs/gctk-architecture.md. No
Gas City or bd command is named `reaction`, `check`, `sweep`, `deliverable` or
`dispose` (`gc --help` and `bd help`, read at the city's builds). `sling` keeps
`gc sling`'s word: the verb does the whole act over that primitive, its
refusals, the pour and the gate on an unfinished pour, and its callers are
documented onto it alone, so no caller chooses between the two. The noun names
a first reaction, which the pack's one formula for it already calls
`mol-first-reaction`. It is a reaction to a bead, never the retired reaction
bead (`task_kind=reaction`), of which no store holds one.

## 2. The domain and what it owns

The domain is one package, `services/gctk/reaction`, under the five commands.
It is a domain in `services/gctk/layers_test.go`, it asks the domains below it,
and no domain asks it.

**What it owns.**

- The rule of which bead may take a first reaction, which the check, the sling
  and the sweep apply the same way.
- The sweep's candidate rule and its deadline.
- Each exit's writes and their order, with the rules that decide them: intake's
  (docs/steering.md), an emergency's confirmation on the default branch, the
  form each named agent takes its work in, and the checks that a route or a
  hand-off reaches someone.
- The key `gc.recommended_formula`, which the `recommend` exit alone sets
  (call 1). Its entry in `lifecycle/lifecycle.toml` stays, because shell still
  clears it, under the ledger's rule that a key shell still writes stays in that
  file until its writer moves, and the entry names the domain as its owner.
- The situation keys of its two gates, `first-reaction` and
  `first-reaction-unfinished-pour`, stated once in the package.

**What it asks.**

| Question | Asked of |
|---|---|
| what holds a bead: its status, its own pending waits, its wait edges into another store | `waits` |
| the runs that work a bead, live or not, each with its formula; every live run in the store | `waits`, the run link, which gains the first answer and reads the second today |
| whether Gas City left a run's pour unfinished | `waits`, which takes the rule over from `arm` (below) |
| whether a bead is armed | `arm/record` |
| whether a bead carries a PR record's markers, `branch`, `merge_result`, `pr_url` and `pr_number` | `pr/record` |
| whether a task is an open conversation about the bead | `conversation` |
| whether a bead is a human gate | `prstatus` (`IsHumanGate`) |
| arm a bead | `arm`, the function `gctk bead arm` runs, in the same process |

**The adapters it reaches**, and what each gains:

- **Store.** The ledger's reads and writes. It gains a ready read that names no
  key, the sweep's whole ready set by priority, and a `set-state` write for the
  hold. A bead's readiness after a hand-off is read through
  `gc bd list --ready --id <bead>`, bd's own ready rule for one bead.
- **Runtime.** `gc sling`, and `human-gate.sh` and `gc-helm.sh takeaway` through
  its runner of the pack's scripts, as today. It gains `gc session nudge`, the
  roster (`gc agent list --json`), the named sessions (`gc config show --json`),
  the rig list (`gc rig list --json`, read once per process), `gc formula show`
  for a recommended formula, and the one Go statement of Gas City's dispatch
  holds (below).
- **GitHub.** It gains a repository's default branch and the checks at its
  head, check runs and commit statuses, every page of each.

**The keys it reads.** It spells no key another package owns. The arm's keys
are `arm/record`'s, the PR record's are `pr/record`'s, and the run link's are
`waits`'. Each key no domain owns yet it declares read-only, naming its writer:
`gc.routed_to`, `gc.kind`, `gc.root_bead_id`, `gc.step_ref` and `gc.step_id`
(Gas City's), `gc.takeaway` and `gc.takeaway_by` (`gc-helm.sh takeaway`'s),
`task_kind` (each filer's), `anchor_bead` (the writers of PR-finishing work),
`work_dir` (`work-setup.sh`'s) and `check_name` (the old review path's lanes).

**The shared rules**, each with one definition in Go:

| Rule | Its definition today | In the port |
|---|---|---|
| a conversation's shape | `conversation.sh`, with its Go definition in `conversation` | asks `conversation` |
| the run link | `run-lib.sh`, with its Go copy in `waits` held to the file's fixture | asks `waits` |
| an unfinished pour | `arm`'s start (`pours`, `services/gctk/arm/start.go`), which `gc-proactive.sh`'s `unfinished_pours` copies | one exported question in `waits`, which `arm` and `reaction` ask, and the shell copy goes with the script |
| a human gate | `bd-lib.sh`'s `HUMAN_GATE_JQ`, with `prstatus.IsHumanGate` in Go | asks `prstatus` |
| a dispatch hold | Gas City's `beadmeta.HasDispatchHold`, copied by `dispatch-path.sh` for the scripts and twice in Go, in `arm` and `queue` | one Go copy in the runtime adapter, which `arm`, `queue` and `reaction` ask |
| a dispatch path | `dispatch-path.sh`: a route or an arm | `gc.routed_to`, read-only, and `arm/record` |
| the standing kinds | `standing-kinds.sh`, whose one kind is `triage-subject` | the same one kind in the package, while it lasts (section 8) |

## 3. The move, whole

The rules a domain move follows, from docs/gctk-architecture.md, applied:

1. **The intent moves whole.** The key, its writer, the questions and every
   caller move in the same PR, the effort's one PR to main. It deletes
   `tools/gc-proactive.sh`, `tools/gc-proactive.test.sh`,
   `assets/scripts/first-reaction-dispose.sh` and
   `assets/scripts/first-reaction-dispose.test.sh`, 5,558 lines, and keeps no
   test that holds the shell and the Go equal. The PR's size line shows the net.
2. **Dependencies point down.** `reaction` sits above `waits`, `arm`,
   `arm/record`, `pr/record`, `conversation` and `prstatus`, and above the
   adapters. Nothing below it imports it.
3. **An owner gathers its own inputs.** Each command takes bead ids and the
   asking run, never facts a caller assembled.
4. **Each power is one verb.** Four rows of docs/authority-map.md name
   `first-reaction-dispose.sh` as a holder: withdrawing a superseded
   first-reaction gate, arming a blocked follow-up, holding new work for
   placement, and handing a town-repo edit to the mechanik. Each names
   `gctk reaction dispose`.
5. **Each rule is tested in Go.** Section 5 says how.
6. **A key's name appears once.** `gc.recommended_formula` is declared in
   `reaction`, with call 1's exception.
7. **Retiring code gets no new work.** Section 8.

**Every caller**, by where it lives:

- **The formula.** `mol-first-reaction`'s description and its react step.
- **The order.** `proactive-scan-sling`'s exec line and its comments. It keeps
  its name, because the city's overrides name it, and its cadence, scope,
  timeout and `[order.env]`.
- **The prompts.** The proactive prompt's check text and exit blocks, the
  comment in its `agent.toml`, and its `PROVENANCE.md`, whose Gate paragraph
  names the Go tests.
- **The scripts.** `gc-helm.sh` (`react`, the two takeaway messages that name
  the blocked exit, and its comments), `patrol-finding.sh`,
  `operator-intake.sh`, and the comments of
  `converse-invalidate-recommendation.sh`, `dispatch-path.sh`,
  `standing-kinds.sh` and `run-lib.sh` that name either script.
- **The suites.** `gc-helm.test.sh`, `gc-helm-open.test.sh`,
  `operator-intake.test.sh`, `patrol-finding.test.sh` and
  `feedback-miner.test.sh` stub a script, and stub gctk through `GCTK_BIN`
  instead. `gc-helm-conversations.test.sh` drives the real check through the
  fixture seam, and drives the built binary over the harness's stub store
  instead, as the suites that reach `gctk merge` do. `bd-lib.test.sh`,
  `dispatch-path.test.sh`, `standing-kinds.test.sh` and `run-lib.test.sh` drop
  `tools/gc-proactive.sh` from their reader lists, and `gctk-bin.test.sh`
  updates its list of the files that carry the `gctk-bin` block.
- **The hand-run fixture.** The section of `tools/helm-surface-fixture.sh` on
  react's wiring drives the deleted script through its fixture seam, and it
  goes. The board's test data (`services/helm/internal/rigboard/testdata`)
  name the scripts only inside captured bead titles, which stay as they are.
- **The pages.** docs/human-engagement.md, docs/component-model.md,
  docs/authority-map.md, docs/deferred-dispatch.md, docs/steering.md,
  docs/review-correctness.md (whose example of a file under `tools/` that pack
  content runs becomes `tools/gc-bd-universe.sh`), services/gctk/README.md, and
  the comments of `lifecycle/lifecycle.toml`. The seed audit renders the changed
  prompt and formula again.

**The architecture page.** This PR states the target in
docs/gctk-architecture.md: the five commands' rows in the surface table,
`reaction` among the nouns and what each owns, and one Debt entry saying the
reaction still runs from shell, which the last unit removes. Unit 1 adds call
1's Debt entry once the key's declaration has moved. docs/architecture.md names
neither script, and no fact it states moves.

## 4. The store reads

Every read the five commands make goes through the store adapter, the runtime
adapter or the GitHub adapter. Each runs one command and decodes its standard
output in Go, or reads the supervisor's API. A command line carries ids and
flags alone, and the store adapter names at most 200 ids in one read
(`idBatch`, `services/gctk/internal/gcbd/find.go`), so no read grows an
argument with the store.

The reads that grow with a store today:

| Read | Size on 2026-11-16 | Today | In the port |
|---|---|---|---|
| every bead that carries `gc.instantiating`, for the unfinished pours | 321 rows, 3,401,825 bytes, in the gc-toolkit store | jq's input since PR #1535, and an argument before it | decoded from the read's output |
| the ready set the sweep reads | 495 beads, 3,280,261 bytes, in the same store | jq's input | decoded from the read's output |
| the check runs and commit statuses at the head of main, for an emergency | every page, merged | passed to jq as `--argjson` arguments (`first-reaction-dispose.sh:576-595`) | decoded from each page's output |

`getconf ARG_MAX` is 1,048,576 on the city's host. The emergency's read has the
fence read's shape: a repository with enough checks at its default branch's head
would stop it, and the port removes that read with the rest. This repository's
main carried three check runs at 07:21Z, 9,234 bytes, far below the limit.

**The test.** The store adapter's own tests drive it through a stub `gc` on
`PATH`, and so does this one. The stub answers the fence read with a JSON array
larger than `getconf ARG_MAX`, read when the test runs so that it holds on any
host, and answers every other read with the least that makes the subject one
that takes a reaction. `gctk reaction check <S> --run <root>` runs end to end
through the real adapter and exits 0. A second case runs
`gctk reaction sweep --dry-run` over the same stub and lists the subject. A
third counts the stub's `gc rig list` calls for one sling, one sweep and one
dispose, and each makes one (tk-nyctwpz).

## 5. Behavior kept, and the changes named

**Kept.** Every behavior of the two scripts is kept but the changes below.
These are the ones a port is most likely to lose:

- **The refusals and their codes.** From the row, in this order: 6 for a
  standing record or a feedback pattern, then 5 for a status other than open,
  an assignee, a route or an arm, and `hold:mayor` or `hold:external`. Then 3
  for an open conversation that tracks the subject, 3 for a live reaction and 4
  for a live run of another formula, with a reaction's unfinished pour read as
  no run, and 5 for an open human gate. A read that does not answer decides
  nothing and exits 1, and under `check` it is no refusal either, so the
  reaction asks again.
- **The check's pass-over.** The asking run is no second reaction, and a gate
  under `first-reaction` whose message names the run among its words is the
  run's own, so a reaction re-offered after it filed its gate finishes its exit.
- **The unfinished pour.** When `gc sling` exits 3 naming only roots whose pour
  Gas City left unfinished, the sling files one human gate on the bead under
  `first-reaction-unfinished-pour`, naming each root and
  `gc convoy delete <root> --force`, and refuses with 5.
- **The sweep.** One ready read, unassigned and not an epic, by priority. Its
  candidate rule drops a bead with no description, a type outside task, bug,
  feature and spike, a workflow, scope or spec root, a step, a standing kind, a
  feedback pattern, a review lane, a headline (`gc.takeaway` or
  `gc.takeaway_by`), a work marker, a parent, a dispatch path or a dispatch
  hold. It drops every bead a live run works, reading a reaction's unfinished
  pour as no run, and a run map that does not read drops nothing and says so. It
  starts no sling once less of its deadline is left than its slowest sling took,
  each figure taken in whole seconds as its upper bound, and it skips a rig whose
  pool cannot take a reaction, with exit 0. Its summary counts each skip by its
  cause.
- **The pool and the hand-off.** A pool answers no only on a positive finding:
  absent from the roster, suspended, capped at zero, or in a rig that does not
  own the bead's store. A named agent answers no when the roster names none, it
  is suspended, it is a pool, or its hook reads no store the bead lives in. A
  roster, config or rig list that does not read answers yes.
- **The exits.** Usage is refused before any read. The subject's status is read
  before the first write, and a subject that is not open takes none and exits 3.
  Each exit keeps the order of its writes, so the write that dispatches, holds
  or gates the subject comes last and a re-run resumes. The blocker a blocked
  exit filed is found among the subject's pending waits by its title, a gate
  under the same key and brief is reused, and a superseded first-reaction gate
  is withdrawn before the new one is filed. A recommendation is cleared before
  the act and set only once its gate is filed, an emergency's P0 lands before
  the route, the hold is the last write, and the close exit's brief and headline
  land before its closer. The po, the deacon and the witness are refused, the
  mechanik takes a route, and the refinery and the keeper take the assignee.

**How it is pinned.** Each of the 80 cases of `tools/gc-proactive.test.sh` and
the 92 of `assets/scripts/first-reaction-dispose.test.sh` becomes a Go test on
the adapters' fakes, with the case's store fixture as the fake's rows, as the
gctk ports before this one did. Each guard is proved by a mutant: a copy of the
package with the guard in its pre-fix shape, which the tests must fail. The
shell suites are deleted with the scripts, and nothing runs the two side by
side.

**The changes**, each for your approval:

| Change | Today | After | Why |
|---|---|---|---|
| The commands' names | `gc-proactive.sh sling <S> --check --run <root>`, `scan --sling`, `first-reaction-dispose.sh` | `gctk reaction check`, `sweep` and `dispose`, beside `sling` and `deliverable` | one domain's verbs (section 1) |
| Modes with no caller | the sling's `--nudge` and `--dry-run`, which `gc-helm.sh react` only passes through; the dispose's `--dry-run`; the scan's text output; `GC_PROACTIVE_POOL`, `GC_PROACTIVE_TYPES`, `GC_PROACTIVE_ROSTER_TIMEOUT` and `GC_FIRST_REACTION_GH_TIMEOUT`; the fixture seam `GC_PROACTIVE_FIXTURE` | not ported: the four tunables' defaults become the domain's constants, and `gc-helm.sh react` drops the two flags | nothing in the tree passes or sets them but the scripts' own suites, the react cases of `gc-helm-open.test.sh`, which pass `--dry-run` and drop it, and the two users of the fixture seam that section 3 moves off it, and the town's city.toml sets none (read 2026-11-16). `GC_PROACTIVE_SWEEP_TIMEOUT` stays, because the order sets it in `[order.env]`, where an override can change it |
| The prompt's clause for a leftover reaction bead | it slings the subject of a reaction bead the old path filed | removed, with its PROVENANCE line, the test that pins it and the three `lifecycle.toml` entries that name it | tk-1tfzr71.116's step 2 found no reaction bead open in any store (2026-11-15T07:14:43Z), and unit 2 reads every store again before it removes the clause |
| The rig list | read once by a sling and once by a scan, and up to three times by a dispose, once in each probe it runs | read once by each command | tk-nyctwpz |
| The store a command reads | the rig `GC_RIG` names for the sling and the scan, through `rig-map.sh`, and the subject's rig for the dispose | `--db`, or the store gc routes the bead to, as `gctk bead holds` reads it; the order passes `--db "$GC_RIG_ROOT/.beads"` | gctk's one rule for a store. The pool's rig stays `GC_RIG`'s, and a `GC_RIG` that names another rig than the bead's still exits 1, now at `gc sling`'s cross-rig refusal |
| Messages | the scripts' wording | the same facts in gctk's wording | callers branch on exit codes, the decline passes the check's message on as its reason, and no caller parses one |

## 6. The open reports

These are the list at filing and the three searches run again at design time
(`gc bd search` for proactive, "first reaction" and first-reaction, each with
`--status open`, 2026-11-16 at about 06:45Z). A report that no longer applies is
handed to the validating closer with a close brief, which checks the reason and
closes it or asks a person. A report the port fixes waits on the landing bead,
tk-ssm8qns.17, and its validating closer is armed for when that closes.

| Report | Settled | Why |
|---|---|---|
| tk-3lmcjrt, a direct reaction acts on work waiting for placement | no longer applies after #1520 | Placement is the `hold:mayor` label, and the row refusal refuses a held bead with 5 on every path, the direct sling's included, as the scan's filter drops it. The port keeps both. |
| tk-yqx8vzu, the scan reacts again to a bead whose work is poured but not started | no longer applies after #1520 | The sweep drops every bead a live run works, and the sling and the check refuse a live run of another formula with 4. The port keeps both. |
| tk-u61kn9, two sweeps dispose one subject | no longer applies after #1520 | Two slings that both pass the refusals meet `gc sling`'s per-bead launch lock and its live-workflow conflict, so the second exits 3 and pours nothing. The port passes that exit through. |
| tk-nyctwpz, the sling reads the rig list again on every call | the port fixes it | One rig-list read per command, counted by section 4's test. It is armed to the polecat pool today, so its arm moves to the validating closer, held on the landing. |
| tk-q3rr8q1, a blocked exit's `--then-route` to the proactive pool pours `mol-polecat-work` | no longer applies after #1520 | The proactive agent's `default_sling_formula` is `mol-first-reaction`, and `gctk bead arm` records the target's default when the arm names no formula, so the arm pours a reaction, whose check passes once the start clears the arm after its pour. |
| tk-0u5trz, the blocked exit's blocker churns as demand | no longer applies after #1520 | A blocker the exit files is new work nobody has decided on, and it takes one reaction like any other: `gc sling` refuses a second while one runs, and the headline its exit writes keeps it out of every later sweep. |
| tk-6121i3p, a duplicate's hold takes two writes | no longer applies after #1439 and #1520 | A duplicate is closed at once through `bead-rehome.sh`, which writes bd's own `duplicates` edge, and `duplicate_of` is retired with its sweep. A reaction that finds a duplicate takes the close exit, one call. |
| tk-rvj7wg0, no exit for a bead another bead resolves, and a hold check that accepts any edge | carries on, narrowed | The hold check is gone: `gc-helm.sh takeaway` exits 4 on a refused edge, and the exit stops before any arm. The `until` edge is retired, and the close exit's `--waiting-on` holds a bead whose job another bead's landing ends. What remains is a duplicate's close reaching you through the validating closer, which is that closer's policy and outside the port. The edge collision it also names is tk-v209ua2's. |
| tk-v209ua2, a related edge passes the blocked exit's hold check | carries on, narrowed, held on the landing | The early dispatch no longer happens, as for tk-rvj7wg0. What remains is its own open choice. When the subject already has an edge of another type onto the bead it waits on, bd refuses the `blocks` edge and the exit stops with the remedy named, and the port keeps that refusal. Whether the exit converts the edge instead is the follow-up, which builds on the Go exit, so it waits on the landing. |
| tk-kvcgj8, the close exit does not release the subject's claim | no longer applies after #1520 | A worker claims the react step, never the subject, so the subject reaches every exit open and unassigned. |
| tk-itv781b.1, the reaction redesign | carries on, narrowed | #1520 meets its target 4, since no key records a reaction, and most of target 1: `gc sling` refuses a second live reaction, the pour refuses a closed subject, and Gas City retires a run whose subject closed or took an assignee before a worker claims it. The port meets target 3, since each exit's flags are its own. Target 2, a prompt with no case on exit statuses, remains, because the check's and the dispose's exits each call for a different act, and so does the part of target 1 a refusal that arises after the sling reaches. This table settles its list of candidate absorptions. |
| tk-1wqr0qk, the fixture no runner runs | no longer applies after #1520 | #1520 deleted `tools/proactive-first-reaction-fixture.sh`, and the PROVENANCE Gate paragraph names suites the runner selects. After the port it names the Go tests, which CI runs on every PR. |
| tk-at5hqqy, no guard for a subject closed between the pour and the reaction | no longer applies after #1520 | The steps it names are gone. The check refuses a subject that is not open, every exit writes nothing to one, and Gas City retires a run whose input closed before its step is claimed. |
| tk-8gradm4.7, one shared check for anything live behind a bead | carries on | Its closer is armed for tk-1tfzr71.19. The port moves the sweep's and the sling's reads of runs onto `waits`' run link, so the proactive scan is no longer one of the readers it lists. |
| tk-1tfzr71.117, remove the prompt's clause for a leftover reaction bead | the port fixes it | Unit 2 removes the clause, its PROVENANCE line, its test and the three `lifecycle.toml` entries that name it, since the clause calls the deleted script and no store holds a reaction bead. It waits on the landing, and its arm moves to the validating closer. |
| tk-tuy36rf, operator-intake files a subject a reaction can take before its conversation exists | carries on as its own fix | Its remedy is operator-intake.sh's create, assigned to `human`, and the assignee refusal the port keeps is what makes that remedy hold. |
| tk-l4czecn, the formula cites authority-map rows by line number | no longer applies after #1520 | #1520 rewrote the formula, which cites no row (`git grep "rows 28"` finds none in formulas/ or agents/). |
| tk-ns24vi2, the witness's report of the failure itself | nothing to change | It was disposed `close` at 05:58Z, and its validating closer closed it at 07:19Z, having found PR #1535's fix live. Section 4's test keeps the failure from returning. |

The searches also found beads against neither script, which the port leaves
alone: tk-1ggf9cr (a pool session's startup nudge), tk-f8ifu1 and tk-m3oqyr (two
variables the town's city.toml no longer sets on 2026-11-16, which their owner
can close), tk-toahupq (your gate on linking beads at a first reaction, which is
the reaction model's), tk-tem3f2a (mol-validate-close's ask) and tk-2ntb1ux (the
converse prompt).

## 7. The landing order

**tk-1tfzr71.116.** The mechanik's cut-over pauses the scan in three rigs,
wakes on 2026-11-20 to read the pilot rig's first ten reactions on #1520's path,
and is deferred again while there are fewer. It checks each one, compares their
exits with the pilot's last ten on the old path, and lifts the pause. It changes
only the town's city.toml, so it shares no file with the port. Its steps 1 and 2
are done (2026-11-15 at 07:09Z and 07:15Z). The landing bead, tk-ssm8qns.17,
waits on it by a `blocks` edge (call 2), so the effort's PR merges only after
the pilot's ten reactions ran one implementation. The units build on the
integration branch meanwhile, which the city does not run.

**tk-1tfzr71.117.** It waits on tk-1tfzr71.116 to remove the clause that unit 2
removes. With its edge onto the landing (section 6), it closes through its
validating closer once the landing merges, and no second PR touches the clause.

**tk-1tfzr71.19 and its design, tk-1tfzr71.158.** Unit 7 of that design retires
`standing-kinds.sh` with its readers' exclusions, `tools/gc-proactive.sh`'s
among them, and edits the reader lists of `dispatch-path.test.sh` and
`run-lib.test.sh`. Whichever lands on main second resolves the overlap. If unit
7 lands first, the port carries no standing kind. If the port lands first, unit
7 removes the domain's standing kind with the rest. A note on both beads names
the Go constant and the three test files.

**tk-1tfzr71.122.** The old review path's retirement removes review beads. The
sweep's two clauses for them, `task_kind=review` and `check_name`, are kept
while such beads exist. The merge cadence still files them for each PR on the
old path, and four were open in the gc-toolkit store at 07:18Z on 2026-11-16,
all filed in the four minutes before. A note on tk-1tfzr71.122 names both
clauses, so its change removes them.

**tk-1tfzr71.24.** The board member retires the board's own reads,
`gc.recommended_formula` among them, under the board's Debt entry, and its
contract reduces `gc-helm.sh`'s verbs. `react` becomes one call of
`gctk reaction sling`, and a note on the bead says so.

## 8. The deletion plan

`tools/deletion-plan.tsv` at 6dd9d13ee names neither script nor its test, and
none of the files section 3 changes. The shared definitions the port reads,
`dispatch-path.sh`, `standing-kinds.sh`, `run-lib.sh`, `bd-lib.sh` and
`conversation.sh`, are not rows either. Their readers that are rows, the
liveness census's scripts (tk-1tfzr71.19), stay untouched, because the port
deletes no shared definition, so the one exception in rule 7 does not arise.
The port adds no line to a file the plan retires, which the PR's size line
shows.

Two of the domain's rules guard kinds a scheduled member retires: the standing
kind, which tk-1tfzr71.19 retires (15 open `triage-subject` beads across the
seven stores on 2026-11-16), and the review lane, which tk-1tfzr71.122 retires.
Each is kept while its beads exist, and the notes of section 7 hand its removal
to the member that retires the kind.

## 9. The units

tk-ssm8qns.19 builds unit 1 and files unit 2 under the epic, with
`target=integration/tk-ssm8qns.17`, blocked by unit 1, blocking the landing
bead tk-ssm8qns.17 and the summary task tk-ssm8qns.20, and armed on
`mol-polecat-work`. Both land on the integration branch with no PR of their own.
The effort's one PR carries them to main, and tk-ssm8qns.20 writes its summary,
which names the foundation belief the move serves: human attention is the
budget, and an intake that stops leaves every new bead waiting for a person.

Unit 1 goes first, because the dispose calls `gc-proactive.sh` and nothing in
`gc-proactive.sh` calls the dispose. Unit 2 waits on it, because both edit the
prompt and the same pages.

**The first act.** Before it builds, tk-ssm8qns.19 applies section 6. Each
report that no longer applies gets a close brief and the validating closer.
tk-nyctwpz and tk-1tfzr71.117 each get a close brief, a `blocks` edge onto
tk-ssm8qns.17 and the closer's arm, after a disarm of the arm each carries.
tk-v209ua2 gets a `blocks` edge onto tk-ssm8qns.17, and each report that carries
on gets a note. It then writes the edge and the notes of section 7.

**Unit 1: the exits.**

- `gctk reaction dispose`, with the exits' writes, intake's rule, the
  emergency's check, the named agents' forms, and the route and hand-off rules
  that `deliverable` and `assignable` answer today.
- The adapters' growth those need: the store's `set-state` and one-bead ready
  read; the runtime's nudge, roster, named sessions, rig list and formula read;
  GitHub's checks at the default branch's head.
- The declaration of `gc.recommended_formula`, its `lifecycle.toml` entry
  rewritten, and call 1's Debt entry. The follow-up bead it names moves Accept's
  and the sitting's reads and clears onto the domain, filed under the epic,
  blocked by the landing and not armed, so the epic's checkpoint decides when it
  starts.
- The callers: the prompt's exit blocks and their text, `gc-helm.sh`'s two
  messages, the four authority-map rows, and the pages and comments that name
  the script.
- It deletes `assets/scripts/first-reaction-dispose.sh` and its test, 3,139
  lines, and carries the test's 92 cases as Go tests with their mutants.

**Unit 2: the check, the sling, the sweep and the pool.**

- `gctk reaction check`, `sling`, `sweep` and `deliverable`, with the
  refusals, the candidate rule, the in-flight drop, the deadline, the unfinished
  pour's gate and the sweep's summary.
- In `waits`: the runs that work a bead, with each run's formula, and the
  unfinished-pour question, which `arm` swaps onto. The dispatch hold's one Go
  copy, which `arm` and `queue` swap onto. The store's ready read that names no
  key, by priority.
- The tests of section 4.
- The callers: the formula's step and description, the order's exec line,
  `gc-helm.sh react`, `patrol-finding.sh`, `operator-intake.sh` and the prompt's
  check text. The clause for a leftover reaction bead goes with what pins it,
  once every store reads with none. Then the suites, the reader lists, the
  hand-run fixture's section and the pages.
- It deletes `tools/gc-proactive.sh` and its test, 2,419 lines, carries the
  test's 80 cases as Go tests with their mutants, and removes the architecture
  page's Debt entry for the shell.

**Against the initiative's Done when.** The check, the sling, the sweep and the
dispose run as gctk commands, the formula's step and the order's exec line name
gctk, and so does every other caller (units 1 and 2). Both scripts and their
tests leave in the effort's one PR, whose size line shows the net. Section 4's
test feeds the check a store read larger than `getconf ARG_MAX` (unit 2). Each
report is settled as section 6 says (the first act, and the closers armed on
the landing). The PR's summary names the foundation belief (tk-ssm8qns.20).

## 10. The Gas City search

Each command the change adds, with the primitive searched at upstream main
e60ed864f3 and what it leaves. The change adds no key, since
`gc.recommended_formula` exists and only its declaration moves, and no order,
since `proactive-scan-sling` keeps its name and only its exec line changes.

| Command | The primitive | What it covers, composed | What it leaves, which the command adds |
|---|---|---|---|
| `check`, `sling` | `gc sling`'s refusals (`internal/sling`, `cmd/gc/cmd_sling.go`) | A bead no store holds (`MissingBeadError`), a route across rigs (`CrossRigRouteError`, in `preflight`) or stores (`CrossStoreRouteError`, `validateBuiltInRouteStoreReachable`), a target the city does not configure, a second live run of the formula (`checkLegacySourceWorkflowConflict` and `liveConvoyTrackedWorkflowRoots`, under `withGraphV2SourceWorkflowLock`), and a closed target at the pour (`CreateSingleItemInputConvoy`, `internal/graphv2/invocation.go`). The sling passes exit 3 through and reports the rest as errors. The check leans on Gas City's retirement of a run whose input closed or took an assignee before its step was claimed (`hookRetireIfInputSettled`, `cmd/gc/cmd_hook_claim.go`). | `internal/sling` reads no hold label (`beadmeta.HasDispatchHold`, `internal/beadmeta/hold_labels.go`, has no caller there), no readiness and no human gate. It clears an assignee only under `--reassign`, which is false by default, and it admits a run of another formula, which its conflict check calls legitimate concurrent work. A conversation, a standing record and a feedback pattern are the pack's. An unfinished pour is a live root to Gas City (`markFailed` and `fenceGraphWorkflowBead`, `internal/molecule/molecule.go`; `carriedPoolRoute` in `cmd/gc/route_recovery.go` counts any fence that is not blank), and nothing finishes it. |
| `sweep` | the default work query, bd's ready set, and order triggers | bd's ready set is the sweep's one read (`bd ready --unassigned --exclude-type=epic --sort priority`). | The work query offers only work routed to the claiming pool (`hookCandidateClaimable` and `hookClaimMatchesRoute`, `cmd/gc/cmd_hook_claim.go`), and a bead nobody has decided on has no route. bd's ready flags select a key's presence or one value and a label's exact text, and the candidate rule needs keys to be absent, so it runs in Go over the one read. An order on `bead.created` (`BeadCreated`, `internal/events/events.go`) is told no bead (`cmd/gc/order_dispatch.go`, "Auto-triggered orders carry no args channel"; the [orders tutorial](https://github.com/gastownhall/gascity/blob/e60ed864f346e9bf9151f8b30d2b83539e8b16cb/docs/tutorials/07-orders.md), "Formula orders vs. exec orders"), so the order sweeps on its cooldown. Gas City ends an exec order at its timeout by signalling its process group (`shellExecRunner`), so the sweep keeps its own deadline. |
| `deliverable` | the roster, `gc agent list --json`, and `gc sling`'s dry run | The roster's qualified name, suspension and pool maximum are the three facts the answer reads. | `gc sling`'s dry run computes the same warnings (`newTargetResult`, `internal/sling/sling_core.go`) but answers for one sling of one bead, and this command's callers ask about the pool with no bead in hand. One rule over the roster answers that form and the dispose's. |
| `dispose` | each exit's native writes | The human gate (bd's `gate create --type=human`, through `human-gate.sh`), the hold (`gc bd set-state <bead> hold=mayor`, Gas City's hold label), the hand-off (`gc sling <agent> <bead> --no-formula --no-convoy`), the closer (`gc sling <pool> <bead> --on mol-validate-close`), the nudge (`gc session nudge`), the ready read (bd's `list --ready`) and the arm (`gctk bead arm`). bd's own duplicate and supersede are composed by the closer the close exit hands to: `bead-rehome.sh` writes bd's `duplicates` and `supersedes` edges, and no exit records a successor. | The order of the writes, which lets a re-offered reaction resume; intake's rule; the rule that only an emergency's named check confirms it; and the form each named agent takes its work in (docs/authority-map.md, Route work). `default_sling_formula` in the [config reference](https://github.com/gastownhall/gascity/blob/e60ed864f346e9bf9151f8b30d2b83539e8b16cb/docs/reference/config.md) is what makes an arm on the proactive pool pour a reaction. |
