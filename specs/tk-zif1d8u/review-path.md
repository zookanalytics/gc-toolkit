---
name: The review path as one lifecycle formula and one skill per check
description: The design for tk-zif1d8u, the design child of convoy tk-gaklsnk under initiative tk-febol6c. A review bead becomes data. gate-ensure.sh writes the review's values once, at dispatch, on the bead's metadata and as the formula vars its pour fills into the step text, so the reviewer reads its commit, its base and its check's skill by name and reads the change with plain git. A check's method is the skill named from the check, and a check with no skill is a paragraph of the formula. The specialist stance is one skill. Every rig gets every check the pack ships, every reader takes a rig's review guidance at the commit it judges, and a change that edits that guidance is named to its approver on the correctness verdict. It settles the values a review is told, the frame contract, the review bead's data, method loading, the skill shape, where a rig's guidance is read and the backstop for a change to it, the tests, the sequencing with the review-coverage epic, and the implementation breakdown. Read it to approve the design at its checkpoint or to build one of its units.
---

# The review path as one lifecycle formula and one skill per check

## What the operator approves here

Today three layers of bash assemble a review. A script writes the reviewer's
instructions into the review bead's description. Each formula step re-derives
the same values into shell variables. The check skills then use those variables
without saying where they come from. Separately, a rig that keeps no
`review-checks.toml` can never get the demo, arch or pm check.

1. **The dispatch writes the review's values once, and the step text carries
   them.** A review needs the commit it reads, the base its diff starts from
   and the check whose method it applies. "What a review is told", below,
   lists every value with one meaning each. gate-ensure.sh writes them on the
   review bead's metadata, as it writes most of them today, and passes the same
   values as formula vars when it pours the review. The pour fills them into
   the step text, so the reviewer reads its commit, its base and its check's
   skill by name, and a pour that lacks a required value fails. No step
   re-derives a value, and no script stands between the reviewer and its
   values: the reviewer runs plain git in a worktree at the reviewed commit.
   gate-ensure pours a review only once it has read the branch's head, and
   nothing moves or clears a value afterwards, signoff.sh included. So a review
   reads only the commit its dispatch recorded, and main's fallback of
   reviewing the branch's latest commit when none was recorded ends. A review
   held with no workflow reads the same values from its metadata. Cost: a
   review whose head neither GitHub nor `git ls-remote` can read waits a pass,
   a person who slings a review by hand passes its values too, and when a
   rewrite takes a review's commit off the branch and the store drops
   signoff.sh's superseded close, the retry reviews that commit once more
   (section 1). This refines the card's "the formula records its pins once".
   The card's pin is `reviewed_oid`, the branch's head at the moment the review
   was dispatched, frozen so the verdict certifies the commit the reviewer read
   and cannot slide onto a later push. The dispatch writes it once, because the
   quorum's two lanes start in parallel and a recovered review has no workflow
   to record it.
2. **A check's method is the skill named from the check.** The step text names
   `gc-toolkit.review-<check>` with the check filled in at pour. A check a
   rig's index declares with no pack skill is judged against its row's
   purpose. A check declared nowhere is approved with `--needs-you`. Both cases
   are a paragraph of the formula. `review-dispatch-body.sh` and its test are
   deleted, and the bead's description becomes one fixed paragraph on how to
   recover a review with no workflow. Cost: none for today's five checks.
3. **The specialist stance is one skill, `gc-toolkit.specialist-stance`.** The
   demo, arch and pm skills load it, and so does the formula's no-skill case.
   Cost: one more entry in every agent's skill list.
4. **Every rig gets every check the pack ships, and a rig steers triage in
   words.** The pack's `review-checks.toml` declares the five checks. A rig's
   own index is optional: its rows add a check of the rig's own or change a
   pack check's phase or purpose for that rig. The `method` column goes. A
   rig's `docs/review-triage.md` reaches triage like any check's guidance, so a
   rig can tell triage never to add a check, or to add one only for one kind of
   change. That is advice triage weighs, not a refusal signoff.sh enforces, and
   how reliably it holds is the operator's open question. Cost: triage can now
   add demo, arch or pm in the three rigs here that keep no index (gascity,
   shutupandlisten, signal-loom) and in sprintshow, whose index lists only
   correctness and triage and says it leaves the other three out on purpose.
   No row withdraws a pack check outright. Triage's judgment does not change,
   and adding nothing stays its common case.
5. **Every file a review reads is read at the reviewed commit, the rig's
   review guidance included.** That guidance is `review-checks.toml` and
   `docs/review-<check>.md`. Every reader of it passes `review-checks.sh --at`
   the commit it judges: a review its reviewed commit, and a gating reader the
   anchor's head, as gate-ensure and pr-open do today. A branch's own edit to
   its guidance governs that branch's review, so what a person reads in the
   branch is what applies to it, and signoff.sh holds the correctness approve
   on such a branch until it names the edit to the person who approves the
   merge (section 6). Nothing is fetched to keep a copy current. Cost: a
   process fix merged on a rig's default branch reaches an open PR when that
   PR next merges its base in, and a PR that never does is reviewed under the
   rules it was written against. That lag is the cost this design chooses,
   not an oversight: closing it means reading the default branch live, which
   the operator ruled out (comment 6237592575). This reverses part 4 of the
   initiative's Target and its fifth Done-when line, which had every reader take
   the default branch's copy so that a process change reaches work in flight
   (PR #1262 comment 4290610037).
6. **Tests hold behavior where the pieces meet, iterating the index.** Each
   declared check resolves to its skill or its purpose, the dispatch writes the
   record and passes the same values as vars, every value a review formula
   names is one the dispatch passes, every skill block runs given only the
   values the step text names, and signoff.sh keeps the recorded commit, a
   departed one included, and refuses each flag a check does not own. Cost: no
   test holds a formula's wording, so a step that loses an instruction is
   caught in review, not by the suite.
7. **This lands before the review-coverage epic's method units.** It changes
   the review path's structure and no check's judgment. Those units then edit
   inside the new skill shape, build their prep script on the values the step
   text carries, and relax the subagent rule in the one place it is left. Cost:
   they wait for this convoy's build. The epic's contract sitting rules on this
   (section 9).
8. **The build is two beads onto this integration branch, in order.** First the
   layered index, which every reader takes at the commit it judges, with the
   backstop for a change to the guidance and the `git ls-remote` read of a
   head GitHub does not answer. Then the values, the formulas and the skills.
   Cost: one more PR to approve on the integration branch, for two diffs that
   are each reviewable in one sitting.
   The single build the card intended is the alternative, at the cost of one PR
   across about forty files.

## What a review is told

A review needs two things to start: the commit it reads and the base its diff
starts from. The commit is the branch's latest commit when gate-ensure
dispatches the review. It is written down then, and nothing moves or clears it,
so the diff the reviewer reads, every command its method runs and the commit
its verdict names are the same code, even if someone pushes while it reads.
The quorum's two lanes read the same commit for the same reason. The base is
the branch the change lands on. The diff runs from where the branch left the base, so it shows
what the branch changed and not what the base did since.

Every value a step or a skill uses is in this table. gate-ensure.sh writes each
one at dispatch, on the review bead's metadata, and passes it as the formula
var of the same name, so the step text names it wherever the formula writes
`{{<key>}}`. A skill has no template pass, so it names a value as `<key>`, and
the agent fills it in from the step text it holds.

| Key | Required | What it is | Example |
|---|---|---|---|
| `review_bead` | always | this review bead | `tk-hyt71ck` |
| `check` | always | the check this review applies, in lowercase | `arch` |
| `anchor_bead` | always | the work bead the verdict lands on, whose description says what the change is for | `tk-zif1d8u` |
| `review_branch` | always | the branch under review | `polecat/tk-zif1d8u` |
| `review_base` | always | the branch it lands on, where the diff starts | `integration/tk-gaklsnk` |
| `reviewed_oid` | always | the commit under review, which is the card's pin: the branch's head when the review was dispatched, written once and never moved or cleared | `11810d325ac7…` |
| `review_pr_url` | once a PR is open | the anchor's PR, else empty | `https://github.com/zookanalytics/gc-toolkit/pull/1277` |
| `review_pr_number` | with `review_pr_url` | that PR's number, else empty | `1277` |
| `review_context` | no | why this review went out, such as a bring-current round for triage to rule, else empty | |

`review_bead` is the bead itself, and `check` is its `check_name` folded to
lowercase. Every other key is the metadata key of the same name.

One more value exists only once the review runs: `<worktree>`, the review's
worktree at the reviewed commit, whose path load-dispatch prints. In it the
diff is `git diff origin/<review_base>...HEAD`, with three dots so the diff
starts where the branch left its base, and every other git command works as
usual.

The record also carries `task_kind`, `check_name`, `review_formula`,
`review_pool` and `fix_target_pool`, all five on every review. The machinery
reads them and no step does: `review_formula` names the formula a review held
with no workflow follows, and the two pools say where a returned review and a
rework go, as today. A record is whole when it carries those five, every key
the table marks always, and both PR keys once a PR is open. It is short when it
lacks any of them. A sling that leaves out a required var pours nothing. The
review formulas refuse a review that lacks a value the table marks always, and
read any other value a review lacks as empty (section 1).

## What this design rests on

The pack is read at `9db3fea95`, which is main with PR #1262 landed and the
commit integration/tk-gaklsnk was cut from. Line numbers in this document are at
that commit. gascity is read at `11a09362a`.

What Gas City, the packs it publishes and bd ship for the surface this design
adds, the resolver's new modes and the record's new keys, and why none of it
covers that surface, is in [gas-city-search.md](gas-city-search.md), read at
the upstream commits it names.

The sources are the operator's three reviews of PR #1262 (5536090671,
5538944776, 5542707712), the review comments 4286312773 ("A repo does not need
to include anything to get a great review") and 4290610037 ("the new process
inside of that rig should absolutely be applied"), the operator's review of
this design's first draft (5558827752) and the operator's rulings on it (PR
comments 6237592575 and 6237655823), the ruling in visit tk-0smmk03, and the
Target, Done-when and Boundaries of tk-febol6c. Where the review of the draft
and an earlier source disagree, the review governs, and decision 5 names the
one place that happens.

Facts read from the running city:

- The review pool is the rig's `polecat-codex` pool
  (`assets/scripts/refinery-reconcile.sh:89`). That pool claims any bead that
  carries a formula, not only reviews (`agents/polecat-codex/agent.toml:1-4`).
- Pack skills reach a session as catalog links named `gc-toolkit.<dir>`, which
  point at the installed pack. `gc skill list` prints them with their binding.
- `gc <binding> scripts-dir` (PR #1269) prints the installed pack's script
  directory. The ask-for-work skills call every pack script through it
  (`docs/gascity-packs.md:566-580`).
- A pour fills each `{{name}}` in a step's text once. The value comes from the
  sling's `--var`, else the rig's formula_vars, else the vars sling adds,
  `binding_prefix` among them, else the formula's declared default
  (gascity `internal/sling/sling.go:1166-1206`,
  `internal/formula/parser.go:615-624`). A var the formula declares `required`
  fails the pour when nothing gives it (`parser.go:728-731`). graph.v2 reserves
  `issue`, `bead_id` and `convoy_id` (`internal/formula/graphv2_validation.go:18-22`).
  gate-ensure already forwards `--var` values to every review it pours
  (`gate-ensure.sh:106-109`, `:964`, `:1072`), today one list for every review
  in a pass, which is how the quorum gets its lane config.
- A skill has no template pass, and no variable set in one tool call survives
  into the next (`docs/gascity-packs.md:566-567`).
- Each rig's `review-checks.toml` on its default branch today:

  | Rig | `review-checks.toml` | `docs/review-<check>.md` |
  |---|---|---|
  | gc-toolkit | correctness, triage, demo, arch, pm | none |
  | gascity | none | none |
  | shutupandlisten | none | none |
  | signal-loom | none | none |
  | sprintshow | correctness and triage, no phase. Correctness's `method` is `formulas/mol-review.toml`. The header says sprintshow leaves demo, arch and pm out on purpose. | none |

Settling the design turned up four defects on main. Each is the frame contract
or the index read showing through, so the build fixes each and none is filed
on its own:

- **No writer stamps a PR on a review bead.** gate-ensure.sh's work order has no
  PR key (`gate-ensure.sh:189-196`), so `mol-review`'s post-open branch never
  runs (`formulas/mol-review.toml:79-88`). The correctness skill's read of the
  published page then runs with an empty `$PR` and `$PR_REPO_Q`
  (`skills/review-correctness/SKILL.md:104`).
- **The triage skill cannot find its parser outside gc-toolkit.** It predates
  `gc <binding> scripts-dir` and still looks for `review-checks.sh` with a loop
  of its own: under `GC_PACK_DIR`, which agent sessions never have, and under
  `GC_RIG_ROOT`, which holds the pack only when the rig is gc-toolkit
  (`skills/review-triage/SKILL.md:38-41`). In every other rig the parse prints
  nothing, and triage reads that as no menu. The fix is the `scripts-dir` call
  the ask-for-work skills make.
- **The triage skill uses `$ANCHOR`, which no frame block sets.** It feeds the
  bring-current round read and the observation's provenance
  (`skills/review-triage/SKILL.md:122-123`, `:187`, `:191`, `:196`). The anchor
  is `anchor_bead` in "What a review is told".
- **liveness-sweep.sh classifies every rig's anchors against gc-toolkit's own
  index**, the file two directories above the script
  (`assets/scripts/liveness-sweep.sh:303`).

## 1. The frame contract

### Today

Each step of `mol-review` and of the quorum re-derives the review bead from the
input convoy, and the values it needs from the bead's metadata, in its own
shell block. That happens in `load-dispatch` (`formulas/mol-review.toml:73-116`),
in `review` (`:148-156`, then the keepalive and workspace blocks at `:174-192`),
and in `verdict-and-drain` (`:336-345`), where the agent retypes the reviewed
commit by hand. It happens again in each quorum lane
(`formulas/mol-review-quorum-signoff.toml:91-95`, `:157-160`) and in the
synthesis (`:219-231`, then the keepalive block at `:260-267` and the chain
close at `:318-319`).

The skills use those variables by name. The correctness skill uses `$M`,
`$BASE`, `$REVIEWED_OID`, `$PR`, `$PR_REPO_Q` and `hb`. Triage uses
`$REVIEW_BEAD`, `$REVIEWED_OID` and `$ANCHOR`. Demo uses `$REVIEW_BEAD`,
`$REVIEWED_OID`, `$BASE`, `$REVIEW_WT`, `$SCRIPTS` and `hb`, and pm uses
`$REVIEWED_OID`. No variable survives from one tool call to the next. So a
skill's block works only when the agent pastes the formula's blocks in front of
it in one shell, which is what `mol-review.toml:197-201` asks.

### The values reach the reviewer in the step text

gate-ensure.sh writes the record on the review bead and passes the same values
on the sling (section 2). The record is what readers other than the reviewer
read: signoff.sh, gate-ensure's own arms, the board, and a claimant of a review
held with no workflow. The vars are what the reviewer reads. Both come from the
one work order gate-ensure builds, and a test holds the two lists together
(section 8).

`mol-review` and the quorum declare a var for each value of "What a review is
told". The six every review has, `review_bead`, `check`, `anchor_bead`,
`review_branch`, `review_base` and `reviewed_oid`, are declared `required`, so
a sling that leaves one out pours nothing. The three that can be empty default
to empty. gate-ensure slings a review only once its record reads back
(`gate-ensure.sh:1050-1067`), and its stranded arm re-slings one with the
values its record holds (`:954`, `:964`), so a review it dispatches is never
poured short.

Each step names a value where it uses it. The method paragraph names the skill
as `{{binding_prefix}}review-{{check}}`, which a pour in this city fills in as
`gc-toolkit.review-arch`. load-dispatch makes the worktree at
`{{reviewed_oid}}`, and the verdict call passes `--review-bead
{{review_bead}}` and `--reviewed-oid {{reviewed_oid}}`, so the agent retypes
nothing. No value has to survive from one shell to the next, because each is
in the text.

One step gathers what the dispatch cannot know, because it exists only once
the review starts. load-dispatch prints the anchor's description, the PR's page
when one is open, the rig's guidance for the check, which
`review-checks.sh --extension {{check}} --at {{reviewed_oid}}` reads from the
reviewed commit's `docs/review-{{check}}.md`, and the path of the review's
worktree at the reviewed commit. Each quorum lane gathers the same in its first
block. The agent carries that output into the steps that follow, as it carries
the step text.

No reader script is built. A script that printed one value, wrapped `git diff`
or `git show`, or built the worktree would only stand in front of what the
reviewer already has: the step text names each value, the reviewer runs git in
the worktree with whatever options it needs, and load-dispatch calls
`review-workspace.sh add` as the review step does today.

The template pass stops in three places:

- A skill is a file in the catalog, with no template pass. It names a value as
  `<key>`, and the agent fills it in from the step text.
- A review held with no workflow has no poured text. Its claimant reads the
  steps with `gc formula show` and the values from the bead's metadata, as the
  fixed description says (section 2).
- The worktree's path and the step bead a keepalive refreshes exist only once
  the review runs. load-dispatch prints the first, and the agent has the second
  from its own claim.

### What a step and a skill may assume

1. The values of "What a review is told", in the step text.
2. The review's worktree at the reviewed commit, whose path load-dispatch
   prints. The reviewer reads the change there with git: the diff, the log, and
   any file at that commit.
3. What load-dispatch gathered: the anchor's description, the PR's page and
   the rig's guidance for the check.
4. A keepalive for a long command:
   `lease-heartbeat.sh <the step bead your claim returned> -- <command>`. The
   lease belongs to the claimed step, which differs per step and per lane, so
   the dispatch cannot pass it. The agent has it from its own claim.
5. The verdict envelope, `findings.md` and `findings.json`, and the one
   `signoff.sh` call the formula makes with the flags the method names.

Nothing else. A skill's block that calls a pack script reaches it as
`"$(gc <binding> scripts-dir)/<script>"`, the form the ask-for-work skills use.
A formula step reaches one through the candidate loop that tk-60i7nl6 replaces
when it lands.

### A short record

A review the dispatch pours is never short of its record. gate-ensure slings a
review only once its whole record reads back (`gate-ensure.sh:1050-1067`). A
create that reads back short is not slung. bd_create closes one the in-flight
probe could not find, and the stranded arm completes any other before it slings
it (`:1045-1049`, section 2). A pour that lacks a required var fails, and
nothing moves or removes a value afterwards.

signoff.sh is the one writer that removes a value today. When it refuses a
verdict whose commit a rewrite took off the branch, it clears `reviewed_oid`
and reads the clear back (`signoff.sh:483-502`). The clear exists so that
main's load-dispatch, which reviews the branch's latest commit when a review
records none (`mol-review.toml:113-114`), does not review the departed commit
again on the next claim. This design ends that fallback, so the clear no
longer sends the next claim to the live head. It would only leave the record
short, and it goes. signoff.sh's departed-commit path becomes: refuse the
verdict, append the note, close the review superseded, read the close back,
and exit 2 if the close did not land. The verdict step's failure arm restores
the route as it does today (`mol-review.toml:368-376`), and the next claimant
retries the same close. It reviews the departed commit again first, because
only signoff.sh tests whether that commit is still on the branch. So each
close that does not read back costs one more review of a commit that cannot
merge, and a close fails to read back only when the store refuses
signoff.sh's write or its read. Once a close lands, the next pass dispatches a
fresh review at the live head.

signoff.sh is also the one writer that can move the pin. Today a
`--reviewed-oid` that names another commit replaces it (`signoff.sh:414-421`,
`:589`), as `signoff.test.sh:538-542` asserts. Under this design signoff.sh
refuses that call and writes nothing, so a verdict either names the commit its
review was dispatched for or is not recorded. Every review formula's verdict
call passes `{{reviewed_oid}}`, so no dispatched review meets the refusal. A
record with no pin, a review made by hand or before this design, still takes
the commit the call names.

So a claimant meets a short record only on a review made by hand or before this
design. load-dispatch says what a missing value means, and the quorum's lanes
and its synthesis say the same. A value the review lacks is empty, as the PR
keys are before a PR opens. When a value the table marks always is empty, the
step reviews nothing. It appends to the review's notes which key is missing and
ends as the verdict step's failure arm does, except that it leaves the route
empty, because the next claim would meet the same gap. A quorum lane writes
nothing outside its own step bead (`mol-review-quorum-signoff.toml:80-82`), so
a lane that meets the gap names the key in its lane output with the `blocked`
verdict and closes its step, and the synthesis makes the refusal. A claimant
holding the review with no workflow releases its claim. A dispatched review
never meets that refusal. A review meets it when a person slung it with a
required var given empty, which a pour accepts (`parser.go:728-731` refuses
only a var not given), or when its claimant holds it with no workflow and its
record lacks the key.

The refused review is left open with nothing driving it. One that was never
poured is the stranded arm's, which completes its record before it slings the
review again, writing the pin only where the record has none
(`gate-ensure.sh:954`, section 2). One whose workflow is spent is the wedge
gate-ensure's spent-workflow arm escalates today (`gate-ensure.sh:479-520`).
That visit offers two repairs, a return to the pool and a close. For a short
record only the close helps, because the next pass then dispatches a fresh
review, and the refusal's note says so. Reviewing a commit the dispatch did not
record is never the fallback.

### The quorum reads the same values

The two lanes and the synthesis are poured by one sling, so they are filled in
with the same values. No lane derives a value, so the two lanes cannot read
different commits, and the quorum needs no step of its own to fix the commit.
The quorum's `base_ref` var retires: it stood in for `review_base`, which the
vars now carry, and refinery-reconcile.sh never passes it
(`refinery-reconcile.sh:118-133`).

## 2. The review bead's data

### What gate-ensure writes

`review_work_order` (`gate-ensure.sh:189-196`) writes `task_kind`,
`check_name`, `anchor_bead`, `review_branch`, `review_base`, `review_pool`,
`fix_target_pool`, and `reviewed_oid` when it read the head. It gains four
things:

- **`review_pr_url` and `review_pr_number`**, copied from the anchor's `pr_url`
  and `pr_number` when its `merge_result` is `pull_request`. When the anchor
  carries only the URL, the number is parsed from it, as signoff.sh parses it.
  They take keys of their own because `gc-helm.sh` resolves a bare PR number to
  every live bead whose `pr_number` matches (`gc-helm.sh:629-633`), and an
  anchor's PR must keep resolving to the anchor alone. signoff.sh reads the PR
  from the anchor (`signoff.sh:392-410`), so the record and the verdict name the
  same PR.
- **`review_context`**, the reason gate-ensure composes today for the note's last
  section (`gate-ensure.sh:867-879`). It says either that the lane does not
  derive green or that a bring-current round asks triage to rule.
- **`review_formula`**, the formula the dispatch pours, `REVIEW_FORMULA`.
- **`reviewed_oid` on every review.** `live_head_for` reads the head through the
  GitHub API and returns nothing when `gh` or a parseable GitHub origin is
  missing, and the review then goes out with no commit (`gate-ensure.sh:137-139`,
  `:152-166`). Under this design it falls back to
  `git ls-remote origin refs/heads/<branch>`, which needs only the origin the
  review fetches from anyway. An anchor whose head neither read answers is held
  for the pass. gate-ensure then passes the resolver an empty commit, the
  resolver refuses it, and gate-ensure's resolve arm keeps the merge held and
  retries on the next pass (`gate-ensure.sh:813-820`, section 6). The stranded
  arm writes `reviewed_oid` only where the record has none. For a record that
  carries one, its order leaves the key out, as it does today
  (`gate-ensure.sh:950-954`, `:194`). That is what keeps the pin in
  place: `bd_meta_ensure` rewrites every key of an order once any key reads
  short (`bd-lib.sh:567-590`), so an order carrying the live head would move a
  pin the dispatch wrote. A record with no pin gets the anchor's head, which
  the pass reads once per anchor (`:762`), and an unreadable head holds the
  pass, as it holds a fresh dispatch. Such a record is a create that read back
  short (`:1045-1049`), or a review made by hand or before this design. Main
  heals it today through mol-review's fallback to the live head
  (`mol-review.toml:113-114`). This design ends that fallback, so the repair
  moves into the arm, which owns the record.

### What gate-ensure passes on the sling

Every sling of a review, the fresh dispatch's (`:1072`) and the stranded arm's
(`:964`), passes each value of "What a review is told" as `--var <key>=<value>`,
read from the record it has just written or read back, beside the
`--sling-var` values it forwards today. `check` is `check_name` folded to
lowercase, the form a skill name and the index use, and `review_bead` is the
bead being slung. `review_context` is the one free-text value, so the formulas
name it in prose and never inside a shell block, where a quote in it would
split the command.

### The description

The bead's description becomes one fixed paragraph, with nothing substituted
into it:

> This is a signoff review. Its metadata is the review's record: the check, the
> anchor, the reviewed branch, base and commit, the PR once one is open, and the
> formula that runs it. If you hold this bead with no poured workflow, run
> `gc formula show` on the formula its `review_formula` names and follow its
> steps in order. In recovery there is no input convoy and there are no step
> beads to close. Read each `{{<key>}}` in the steps as this bead's value under
> that key, `{{check}}` as its `check_name` in lowercase, `{{review_bead}}` as
> this bead, and `{{binding_prefix}}` as the binding your skill catalog shows on
> the pack's skills. The steps say what a key the bead does not carry means,
> and when it means you review nothing.

gate-ensure passes it on the create, where it passes the composed body today
(`gate-ensure.sh:1053-1058`). The formula carries the rule for a missing value,
not this paragraph, because the reviews that can lack one were made by hand or
before this design, and neither carries this paragraph. One dispatched before
it carries the old note, which sends its claimant to the same steps (section
1).

### Every reader of today's description

No script acts on a review bead's description. The scripts that read a
description read another bead's: an anchor's (`pr-open.sh`, `pr-stack.sh`,
`demo-repo-artifact.sh`), a finding's or a visit's (`review-answer.sh`,
`scaffolding-sweep.sh`, `pr-facts.sh`), a park gate's (`gc-helm.sh`) or a
ledger entry's (`gc-deacon-ledger.sh`). The work-context hook and
`tools/gc-bd-universe.sh` pass a description through to an agent, and
`tools/gc-proactive.sh` skips review beads. The readers are the agents and two
tests.

| Reader | Reads today | Reads instead |
|---|---|---|
| `mol-review` load-dispatch, step 5 (`mol-review.toml:118-122`) | the note's check section, which names the method | the check, which the step text names. The review step names the skill (section 3). |
| The quorum lanes, step 2 (`mol-review-quorum-signoff.toml:97-99`, `:163-165`) | the skill the check section names | the same |
| The demo, arch and pm skills (`review-demo/SKILL.md:15`, `review-arch/SKILL.md:10`, `review-pm/SKILL.md:13`) | "the dispatch note's shared specialist stance" | `gc-toolkit.specialist-stance` (section 4) |
| The demo skill on `docs/review-demo.md` (`review-demo/SKILL.md:138-140`) | the extension the note appended from the reviewed commit | the guidance load-dispatch prints from the reviewed commit (sections 3 and 6) |
| A claimant of a review the failure arm returned to its pool (`mol-review.toml:372-384`) | the note's recovery paragraph | the fixed paragraph and `review_formula` |
| The reviewer reading why it was dispatched | the note's "Context from the dispatch" | `review_context`, in the step text |
| A Claude lane of the quorum, through the work-context hook (`overlays/work-context`) | the whole description, at claim | the fixed paragraph. The values arrive in the step text. |
| `gate-ensure.test.sh` (`:61-62`, `:232`) | a stub body script and its marker | assertions on the record and the fixed paragraph |
| `pr-facts.test.sh` (`:191`, named again at `:195` and `:880`) | a stub body script that pr-facts.sh never calls | nothing. The stub goes, and the `validate-dispatch-body.sh` stub beside it stays. |

`review-dispatch-body.sh`, its test and its row in `docs/component-model.md`
(`:394`) are deleted. The rules its frame section shares with the formula
stay in the formula: one verdict, never `gh pr review --approve`, and what to
do when a rewrite takes the reviewed commit off the branch. Its "One agent,
single pass. No fan-out" line goes with the script. That leaves `mol-review`'s
own rule as the one place the subagent policy lives (section 9).

## 3. Loading the method

Every step that applies a method carries this paragraph: `mol-review`'s review
step, and the quorum's two lanes and its synthesis, which judges and runs under
the same method. The pour fills in the check, and load-dispatch has already
printed the rig's guidance for it (section 1):

> The check's method is the skill `{{binding_prefix}}review-{{check}}`. Load it
> from your skill catalog and apply it, and no other review skill. A copy of a
> skill in the review's worktree is the change under review, not your method.
> When your catalog has no such skill:
>
> - If the rig's check index declares `{{check}}`
>   (`review-checks.sh --check {{check}} --at {{reviewed_oid}}` prints its row),
>   judge the diff against the purpose the row states. Load
>   `{{binding_prefix}}specialist-stance` and hold it. Say in your coverage line
>   that the pack ships no method for this check.
> - If no index declares it, approve, and pass `--needs-you` saying the check
>   is declared nowhere, so the operator decides whether it stays in the
>   anchor's `check_set`.
>
> The rig's guidance for this check is the reviewed commit's
> `docs/review-{{check}}.md`, which load-dispatch printed when the commit
> carries one. It adds to the method and never replaces it. Most rigs keep
> none.

- **The name.** `gc-toolkit.<name>` is the name `docs/skills.md` gives every
  pack skill, and the one the operator ruled for pack text (review
  5538944776). `{{binding_prefix}}` is the var sling adds to every pour
  (`internal/sling/sling.go:1196`), so a city that imports the pack under
  another binding fills in `<binding>.review-<check>`. The ask-for-work skills
  make the same substitution by hand for `gc <binding> scripts-dir`.
- **Where the template pass stops.** The check is known at dispatch, so the
  skill's name is filled in before the agent reads it. Whether the catalog
  holds that skill is the session's to answer, and a template has no
  conditional, so the two no-skill cases stay sentences the agent reads. Both
  are rare: no rig here declares a check of its own, and an undeclared token is
  a legacy one.
- **No list.** Which checks have a skill is the catalog's answer. The formula
  names the skill from the check, and the pack's index declares a check only
  where `skills/review-<check>/` exists, which a test holds (section 8). The
  case arm `correctness|triage|demo|arch|pm`
  (`review-dispatch-body.sh:154-155`) goes.
- **The same treatment as today.** A declared check with no skill got the stance
  and its purpose (`review-dispatch-body.sh:127-143`, `:169-179`), and an
  undeclared one got the `--needs-you` approve (`:180-186`). Both keep it. A
  live anchor's legacy `codex` token is the second case.
- **One wording in four steps.** A formula has no include mechanism, so the
  paragraph is a marked region, `review-method-load`, in each of the four
  steps, and a test holds every copy to one text. The correctness method asks
  the same of any rule a change repeats across copies of a code path.

## 4. One skill per check

### The shape

Each check's skill carries these parts, under these headings:

- **Frontmatter.** `name: review-<check>`. A `description` saying what the check
  judges, with the trigger "Use when you hold a review bead whose check is
  `<check>`". `compatibility`.
- **The opening.** The concern, in a paragraph. A specialist check's opening
  loads the stance: "This check holds the specialist stance: load
  `gc-toolkit.specialist-stance` before you judge."
- **`## What it reads`.** The values it uses, by key, as `<reviewed_oid>`. The
  subject documents it holds the change to, read in the review's worktree at
  the reviewed commit. The rig's guidance load-dispatch printed.
- **`## What it judges`.** The method, as it stands.
- **`## What blocks`.** Which findings make the verdict `request-changes`, and
  which ride along.
- **`## The verdict`.** The lines it adds to the envelope, what `findings.json`
  carries, and each `signoff.sh` flag it passes beyond the formula's call, or
  "none".

A block names each value it uses by its key, and the agent fills it in from the
step text (section 1). It reads the change with git in `<worktree>`.

The reshaping moves sentences between headings and rewrites how a block names
its values. It changes no sentence of judgment. That is the initiative's first
boundary, and the build's review holds it.

### The specialist stance, written once

Today `review-dispatch-body.sh` prints the stance ahead of every check except
correctness and triage (`review-dispatch-body.sh:124-145`). It becomes
`skills/specialist-stance/SKILL.md`, which loads as
`gc-toolkit.specialist-stance`. The demo, arch and pm skills load it from their
opening, and so does the formula's purpose case. Its text is today's stance
without the sentences the formula already states for every check: the one
`signoff.sh` call, never `gh pr review`, and the anchor touched only through
`signoff.sh`.

A reference file inside each specialist skill's directory is the other shape,
and it costs no catalog entry. The correctness skill sets the precedent, with
its `references/` links to the work-quality fragments. The purpose case rules it
out: a check with no skill has no directory to read the file from without a
path. A prompt fragment is ruled out as well, because reviews run on
`polecat-codex`, which claims any bead, so a fragment composed into its prompt
would reach implementation turns too. A skill is reached by name from both
places.

The name stays outside the `review-` prefix, so a rig check named `specialist`
or `stance` can never load the stance as its method.

Each check's own skill says whether the check holds the stance, so no script
lists the specialist checks. Correctness and triage do not load it. Demo, arch
and pm do.

### How each skill moves

| Skill | Frame values it uses today | Moves |
|---|---|---|
| correctness | `$M`, `$BASE`, `$REVIEWED_OID`, `$PR`, `$PR_REPO_Q`, `hb`, and `$ANCHOR` set from `$M` | Its preamble about the formula's blocks goes (`:12-17`). The test-evidence block names `<anchor_bead>` and `<reviewed_oid>`. The page read becomes `gh pr view <review_pr_url>`, which `gh` resolves to that repository's PR. Suites run under the keepalive. Flags: none. |
| triage | `$REVIEW_BEAD`, `$REVIEWED_OID`, and `$ANCHOR`, which nothing sets | The index parse becomes `review-checks.sh --show --at <reviewed_oid>`, reached through `scripts-dir` (sections 5 and 6). Its no-index fallback and the missing-index observation go, because every rig has the pack's menu. That observation is the one every gascity triage files today, and tk-ymhd3o4 plans to file it once per repository instead (section 9). The observation stays for a rig row the resolver rejects. The anchor is `<anchor_bead>`. It never blocks. Flags: `--add-gates`, `--reopen`, `--round-reason`, `--dismiss-approval`. |
| demo | `$REVIEW_BEAD`, `$REVIEWED_OID`, `$BASE`, `$REVIEW_WT`, `$SCRIPTS`, `hb` | Loads the stance. The capture runs beside `<worktree>`, under the keepalive. `demo-repo-artifact.sh` and `demo-deliver.sh` are reached through `scripts-dir`. `docs/review-demo.md` is the guidance load-dispatch prints. Flags: `--visual`, `--visual-fallback-from`. |
| pm | `$REVIEWED_OID` | Loads the stance. Reads `docs/product-goals.md` in `<worktree>`. Flags: none. |
| arch | none | Loads the stance. Reads `docs/architecture.md` and `docs/architecture/` in `<worktree>`. Flags: none. |

## 5. A rig needs nothing

### Today

The index's header says correctness and triage are the forced baseline, that
triage may add only a check the index declares, and that a repo with no index
gets the baseline alone (`review-checks.toml:14-18`). signoff.sh enforces it
(`signoff.sh:907-913`), and so does the triage skill (`:77-79`). The triage
skill also states why it never reads the pack's copy: it "would classify this
rig against gc-toolkit's checks" (`:31-33`). The operator's comment 4286312773
reverses that intent: a rig with nothing should still get a great review.

### The pack declares, a rig adds

A rig's effective index is the pack's index with the rig's rows laid over it.

- **The pack's index** is `review-checks.toml` at the root of the pack as gc
  loaded it. It declares each check the pack ships a skill for, with its phase
  and purpose. `review-checks.sh` reads it beside itself, the way it reaches
  every sibling file. So it is always the installed pack's copy, wherever the
  city imports the pack from, and never a checkout the caller stands in.
- **The rig's index** is the `review-checks.toml` that the commit being judged
  carries (section 6), and it is optional. A row for a check the pack declares
  changes that check's phase or purpose for the rig, key by key, and a key the
  row leaves out keeps the pack's value. A row for any other check adds a
  check of the rig's own, judged against its purpose (section 3) with whatever
  guidance its extension adds.
- **In gc-toolkit both layers read one path, and they are two copies.** The
  pack's layer is the installed copy of gc-toolkit's `review-checks.toml`, and
  the rig's layer is the copy at the commit being judged. They differ whenever
  a branch edits the index, and the branch's edit then governs its own review,
  as any rig's branch does. Once installed, every row gc-toolkit keeps is a
  pack row, which every rig gets. So gc-toolkit cannot declare a check for its
  own reviews alone: the resolver reads one path per layer, and gc-toolkit's
  path feeds both. It needs no such check today. Test 4 iterates the pack's
  index in the tree under test, so a gc-toolkit commit that adds a row with no
  skill fails the suite before it can merge.

The initiative's constraint holds with one refinement: a check is declared in an
index and nowhere else. The pack's index declares the checks the pack ships,
and a rig's index declares its own. No script, formula or skill lists checks.

### A rig steers triage in words

Triage's guidance is the rig's `docs/review-triage.md`, which load-dispatch
prints for triage as it prints any check's guidance (sections 1 and 3). A rig that
writes "never add demo here" or "add arch only for changes under `internal/`"
puts that sentence in front of triage on every review. A rig row that restates
a pack check's purpose for the rig changes the line triage's menu shows for
that check, which is a second place a rig can say what the check is for there.

Both are advice. Triage weighs them with its own reading of the diff, and
signoff.sh validates an add only against the index, so nothing refuses an add
the guidance argued against. How reliably the guidance holds against a diff
that seems to warrant the check is the operator's open question, and no test
of this build answers it. No row withdraws a pack check outright. Triage judges
whether a diff warrants each check, and adding nothing is its common case, so a
rig with no screens does not get demo added for want of a visual surface. A row
that withdraws a check can come later, if advice proves too weak.

### The method column

A check's skill is named from the check (section 3), so the `method` key has no
reader. The parser ignores it, the emitted TSV drops the column to
`<name>\t<purpose>\t<phase>`, and the pack's rows lose the key. sprintshow's
`method = "formulas/mol-review.toml"` stops meaning anything, as it already
does in practice.

### The default check_set stays configuration

Four places name the baseline `correctness,triage`:

- `mol-refinery-patrol`'s `check_set` var (`formulas/mol-refinery-patrol.toml:94-96`,
  `:939`);
- refinery-reconcile.sh's `REFINERY_RECONCILE_CHECK_SET` default (`:95`);
- gate-ensure.sh's `--default` (`:81`, `:95`, `:114`);
- the registry's `check_set_default` (`lifecycle/lifecycle.toml:196`).

They configure which lanes an anchor starts with, which `docs/state-machine.md`
calls configuration, not doctrine. None of them declares a check, because a
token no index declares still takes pre-open and gates every transition
(`review-checks.sh:206-216`). Moving the baseline into the index would put the
merge cadence's default and the patrol formula under this build. So it stays
where it is, and the index header points at it instead of restating it.

Scripts that carry one check's own verdict mechanics name that check. signoff.sh
names triage as the owner of `--add-gates` and demo as the owner of `--visual`
(`signoff.sh:214-216`), and bring-current-guard.sh gives triage its round. They
bind a flag or a round to the check that owns it, and list no checks.

### Held to the operator's sixth point

"Would this work with gc-toolkit installed and some other rig under review?"
Walk a gascity PR through the design:

1. gate-ensure runs for gascity with `GC_RIG_ROOT=rigs/gascity`. It resolves
   the lanes from the pack's index, since gascity keeps none, writes the record
   from gascity's branch, base, head and PR, and passes the same values on the
   sling.
2. The review runs on gascity's `polecat-codex` pool. Its catalog links the
   installed pack's skills, so `gc-toolkit.review-arch` loads from the pack gc
   loaded, wherever the city imports it from.
3. The step text names gascity's branch, base, commit and PR. load-dispatch
   builds the worktree in gascity's repository, where the reviewer runs git.
4. The reviewed commit carries no `docs/review-arch.md`, so load-dispatch
   prints no guidance for arch. Arch reads `docs/architecture.md` at the reviewed commit,
   which gascity does not keep, and says so in its coverage line, as its method
   already provides. gascity's architecture lives under `engdocs/architecture/`,
   and gascity carries no review files of its own: the operator closed its
   index bead, gc-7dr9l, as below the fork's change bar. Pointing a pack check at
   a rig's own docs from outside the rig is a limit this design leaves in place.
5. Triage can add arch, pm or demo, and signoff.sh validates the add against the
   same effective index.
6. liveness-sweep classifies gascity's anchors against that index, not
   gc-toolkit's.

Each step names the rig by `GC_RIG_ROOT` and the pack by the pack gc loaded.
None of them reads gc-toolkit as the rig under review.

## 6. Where a rig's guidance is read

### The commit being judged

Each reader takes a rig's guidance at the commit it is judging. A review reads
the index and `docs/review-<check>.md` at its reviewed commit. A gating reader
reads the index at the anchor's head, the commit whose transition it decides.
That is the rule the index header states today (`review-checks.toml:12-13`),
and gate-ensure and pr-open already follow it (`gate-ensure.sh:817`,
`pr-open.sh:456`). Every other reader passes the commit it acts on, as the
table below says, the three that read the working tree today included. A
branch's edit to either file governs that branch's review and no other. A
guidance change merged on a rig's default branch reaches an open branch when
that branch next merges its base in, which is the lag decision 5 chooses.

No reader reads a default branch, so nothing is fetched to keep a copy current.
A reader that lacks the commit it judges fetches that commit by id, as
`review-checks.sh --at` does today (`review-checks.sh:157-164`).

### The one resolver

`review-checks.sh` keeps its job as the one parser and resolver of the check
index, and takes on the layered index of section 5. `--at <oid>` is its one
source for a rig's rows:

- `--resolve --check-set <cs> --through <phase> --at <oid> [--with-phase]`
  resolves against the effective index: the pack's rows from beside the
  script, with the rows of the index `<oid>` carries laid over them. A commit
  that carries no index adds no rows.
- `--check <name> --at <oid>` prints one check's effective row, which the
  purpose case reads. `--show --at <oid>` prints the whole effective index,
  which is triage's menu.
- `--extension <check> --at <oid>` prints the rig's `docs/review-<check>.md` at
  that commit. When the commit carries none, it prints nothing and exits 0.
  That is the common case, so load-dispatch runs it for every review and
  prints whatever it returns.
- `--file <index>` stays for a test that parses one file.
  `GC_REVIEW_CHECKS_INDEX` keeps naming the whole effective index, so a hermetic
  test fixes what every reader sees.

The working-tree read goes. Today a resolve with no `--at`, or at a commit
that carries no index, reads the working tree's `review-checks.toml`
(`review-checks.sh:33-43`, `:169-173`). Under this design the rig's layer
comes from the commit `--at` names and from nowhere else, so no reader falls
back to the checkout it happens to run in. A call that names no commit, with
`--at` missing or empty, is refused as a usage error and emits no rows.
`--file` and `GC_REVIEW_CHECKS_INDEX` are the two exceptions. Each names an
index outright, which is how a test fixes the index a reader sees.
`--extension` reads a file that only a commit carries, so it is refused
without a commit even then. A reader that loses its commit fails at once,
where an answer from the pack's rows alone would judge the change by the
pack's defaults and skip the rig's own rows without a word.

Every reader in the table below names its commit. Each reader that gates a
transition already holds when its resolve fails, so a refusal holds what that
reader gates and never decides on a guess. gate-ensure and pr-open hold the
anchor for the pass, gctk merge holds the merge, review-outcome refuses the
supersede, pr-facts proves nothing green, and liveness-sweep keeps the anchor
a candidate (`liveness-sweep.sh:295-296`). pr-open resolves only once it has
read the head (`pr-open.sh:452-455`, `:544-547`, `:758-759`). liveness-sweep
reads the head as pr-open does, so an anchor whose head it cannot read stays a
candidate as well. The readers at review time always hold a commit. signoff.sh
refuses a verdict that names none before it reads the index
(`signoff.sh:442-445`). The triage skill reads at its review's commit, which
mol-review always names: the recorded one, or on main the live head when none
is recorded (`mol-review.toml:113-114`). gate-ensure writes a review's
dispatch body only after its own resolve succeeds.

The one reader that can still pass an empty commit is gate-ensure, when its
read of the head fails (section 2). The resolver refuses that call, and
gate-ensure's fail-closed arm holds the anchor for the pass: it dispatches
nothing, settles nothing and retries on the next pass
(`gate-ensure.sh:813-820`). That is the hold section 2 gives an anchor whose
head no read answers, so the refusal needs no interim behavior. Unit A also
brings section 2's `git ls-remote` fallback, so the head that goes unread is
one neither GitHub nor `git ls-remote` answers.

A rig row whose phase is outside the ordered set is refused, as today
(`review-checks.sh:227-235`). Read at a commit, that refusal holds only the
branches whose commit carries the row.

### Every reader and its move

| Reader | Reads today | Under this design |
|---|---|---|
| `gate-ensure.sh` (`:817`) | `--resolve --at` the PR head | the same, against the effective index |
| `pr-open.sh` (`:456`, `:553`, `:789`) | `--resolve --at` the head the PR opens at, directly and through `prs_resolve_phased` | the same, against the effective index |
| `pr-summary-region.sh` `prs_resolve_phased` (`:37-42`), and `pr-stack.sh`, which calls it (`:263`) | `--at <head>` | the same, against the effective index |
| `liveness-sweep.sh` (`:298-313`) | gc-toolkit's own index, two directories above the script, through `--file` | `--at` the head of the anchor's branch, the commit pr-open would open it at, with no `--file` |
| `signoff.sh --add-gates` (`:859-883`, `:907-913`) | `git show <reviewed_oid>:review-checks.toml`, through a scratch file | `review-checks.sh --check <name> --at <reviewed_oid>`. The no-index arm goes. |
| the triage skill (`:37-48`) | `git show ${REVIEWED_OID}:review-checks.toml`, with a parser it finds only in gc-toolkit | `review-checks.sh --show --at <reviewed_oid>`, through `scripts-dir` |
| `review-dispatch-body.sh` (`:161-168`, `:199-215`) | the purpose and the extension at the reviewed commit | the purpose through `--check --at` and the extension through `--extension --at`, until unit B deletes it and the formula makes both reads (section 3) |
| the demo skill (`:138-140`) | the extension the note appended | the guidance load-dispatch prints |
| `pr-facts.sh` `lanes_green` (`:662-670`), called at `:1184` and `:3166` | the working tree | `--at` the PR head its caller already holds: the head the unengaged-threads probe is given, and the head the dismissal arm read |
| `review-outcome.sh supersede-anchor` (`:339`) | the working tree | `--at` the commit a new, required `--oid` names, as back-lane already takes one. mol-validate passes the pass's `reviewed_oid` (`mol-validate.toml:418`, `:495`). converse-rework.sh (`:127`) passes the head of the anchor's branch, which it reads as signoff.sh reads one (`signoff.sh:430`). |
| `gctk merge` `firstNotgreenLane` (`services/gctk/internal/cli/merge.go:988`), called at `:532` and `:760` | the working tree | `--at` the head it merges, `headOid` (`:400`), which its `gh pr merge --match-head-commit` already pins (`:782`). This is a Go change. |

pr-facts.sh, review-outcome.sh and gctk merge resolve `--through merge`, which
names every check_set token but the three non-lanes, whatever the index
declares. So the commit each passes changes its answer only when that commit
carries a phase outside the ordered set, and then each refuses and holds, as
gate-ensure and pr-open do. Read at the head it merges, gctk merge holds a PR
whose head adds such a row. Today it reads the working tree, which carries the
row only once the PR has landed, so nothing at the merge stops it.

The pm skill reads neither file. Its one read of the rig is
`docs/product-goals.md` (section 4), and it names the index only in prose.

In practice the layered index changes what a gating reader sees only in a rig
whose commit declares no row for a check the pack declares. There that check
now has the pack's phase and purpose, where today it is undeclared and takes
pre-open.

The index header keeps its rule, and the statements the layered index makes
untrue are rewritten:

- the index header's baseline paragraph, which says a repo with no index gets
  correctness and triage alone (`review-checks.toml:14-18`), and its extension
  paragraph, which says the dispatch body appends an extension (`:21-27`);
- `review-checks.sh`'s header, where a commit with no index falls through to
  the working tree (`:33-43`);
- `signoff.sh`'s usage and comment (`:119-123`, `:859`), which validate an add
  against the reviewed commit's own index alone;
- the triage skill's index contract (`:28-35`, `:55-59`), which refuses the
  pack's copy;
- the demo skill (`:138-140`), on where its extension comes from;
- sprintshow's own index header, which says sprintshow leaves demo, arch and pm
  out on purpose. It is sprintshow's file, so unit A's builder files a bead for
  its rewrite in sprintshow's store. The bead points that intent at a
  `docs/review-triage.md` that tells triage so (section 5).

### A change to its own guidance is named to the approver

Read at the reviewed commit, a branch's edit to `review-checks.toml` or a
`docs/review-<check>.md` governs that branch's own review. The backstop makes
the review say so to the person who approves the merge.

signoff.sh refuses a correctness approve that passes no `--needs-you` when the
change touches `review-checks.toml` or a `docs/review-*.md`. It lists the paths
the change touches, from where the branch left `review_base` to
`reviewed_oid`, names the guidance files among them in the refusal, and writes
nothing. Both review formulas already have the reviewer re-run a call
signoff.sh refuses for a missing flag (`mol-review.toml:353-355`,
`mol-review-quorum-signoff.toml:301-303`). So the reviewer runs it again with
`--needs-you` saying what the edit changes about the review, and the verdict's
opening line carries that sentence (`signoff.sh:550`).

- **What it adds.** It holds no merge. Every merge already waits for an
  approving review from an account other than the city's
  (`review-checks.toml:18-19`), and `--needs-you` only names a decision on the
  verdict's opening line (`signoff.sh:98-103`). What the backstop adds is that
  the approver is told the change edits its own review guidance and that its
  review ran under that edit.
- **Why signoff.sh.** The ruling named two places for the rule: the
  correctness skill, or a path check in signoff.sh. A rule in the skill is an
  instruction the reviewer weighs beside the rig's guidance for the check, and
  that guidance is the file the branch may have edited. signoff.sh is pack code
  the branch under review does not supply, so it refuses whatever the guidance
  says, and `signoff.test.sh` holds it.
- **Why correctness.** It is in the default check_set (section 5), so every
  anchor that does not opt out of review runs it. It takes no round ruling, so
  the `--needs-you` it must pass never meets signoff.sh's refusal of one beside
  `--dismiss-approval` (`signoff.sh:380-382`). Only its approve is held,
  because the approve is what readies the merge. A request-changes verdict
  sends the change back, and the approve that follows the rework carries the
  sentence.
- **What it leaves out.** A method needs no backstop: the methods load from the
  installed pack (section 3), so a branch that edits a skill is reviewed under
  the installed one. The pattern `docs/review-*.md` also matches gc-toolkit's
  `docs/review-workspace.md`, which no index reads as guidance, so a change to
  that file costs one needless sentence on its correctness verdict.
- **Cost.** signoff.sh reads a change's paths, which it does not do today. The
  operator's stance is to let a branch strengthen its own review and keep a
  backstop for when that goes wrong, rather than block the change's own path to
  improving the process (comment 6237592575).

## 7. Process versus subject

A change may edit its own review guidance, and that edit governs its own
review.

## 8. Tests where the pieces meet

### New behavior tests

1. **The record and the vars** (`gate-ensure.test.sh`). A fresh dispatch writes
   every required key and the fixed paragraph, and its sling passes every value
   of "What a review is told" as a `--var`. A `pull_request` anchor's dispatch
   carries its PR as `review_pr_url` and `review_pr_number`. `review_context`
   carries the reason, the bring-current ruling line included. The stranded
   arm writes `reviewed_oid` only where it is absent: a stranded review whose
   pin differs from the live head keeps its pin through the arm's write, one
   with no pin is pinned at the live head, and each re-sling passes the pin its
   record then holds.
2. **The commit stays recorded** (`signoff.test.sh`). signoff.sh's refusal of
   a departed commit leaves `reviewed_oid` in place and closes the review
   superseded, and a close that does not read back exits 2 with the commit
   still recorded and no verdict. A `--reviewed-oid` that names a commit other
   than the record's is refused with nothing written, and one given for a
   record with no pin is recorded. The suite's cases that assert today's clear
   (`:667`) and the flag replacing the pin (`:463-467`, `:538-542`,
   `:698-705`) are rewritten to these.
3. **The vars meet the formulas** (new, structural). Every `{{name}}` in
   `mol-review` and the quorum is a var the formula declares, `convoy_id`
   aside, and every declared var is one gate-ensure passes or sling adds. The
   six values every review has are declared `required`, and the three that can
   be empty default to empty. No `{{review_context}}` sits inside a shell
   block.
4. **Method resolution, iterating the pack's index** (new). Every row has a
   `skills/review-<check>/SKILL.md` whose frontmatter `name` is
   `review-<check>` and which has a verdict section. Every `skills/review-*`
   directory has a row. Every flag a skill's verdict section names is one
   `signoff.sh` accepts, and every skill a check skill says to load is one the
   pack ships. The correctness skill's `references/` links resolve to the
   work-quality fragments and the exemplar corpus. A fixture rig index that adds
   a check with no skill resolves to its purpose through `--check`, and a token
   no index declares resolves to nothing. The `review-method-load` region is the
   same text in every step that carries it.
5. **The skill blocks run on the values alone, iterating the pack's index.**
   Every shell block in each check's skill runs under `set -u` in a fresh
   shell. Its `<key>` placeholders are filled from a fixture record, with a
   scratch rig repository holding the fixture's commit, `<worktree>` a checkout
   of that commit, and `scripts-dir` answering the pack's script directory. The
   commands with effects outside the scratch repository (`gh`, `bd create`, the
   capture engine) are stubbed. Every placeholder a block uses is a key of
   "What a review is told" or `<worktree>`. The correctness test-evidence
   block's bash and zsh cases, now `review-method.test.sh` (EVIDENCE), become
   two of these runs.
6. **The layered index** (`review-checks.test.sh`). A commit with no index
   resolves to the pack's rows. A rig row changes a pack check's phase and
   keeps its purpose. A rig row adds a check. A `method` key is ignored. The
   rig's rows come from the commit `--at` names, not from the working tree,
   which the test proves by resolving at a commit whose index differs from the
   working tree's, and a commit with no index adds no rows even when the
   working tree has one. A call that names no commit is refused, with `--at`
   missing and with `--at ""`, even when the working tree has an index.
   `--file` and `GC_REVIEW_CHECKS_INDEX` each resolve without `--at`, and
   `--extension` is refused without a commit even when one of them is given.
   `--extension` prints a commit's extension, and prints nothing and exits 0
   at a commit that carries none. A rig row with a phase outside the ordered
   set is refused.
7. **What signoff.sh refuses** (`signoff.test.sh`), iterating the effective
   index. It refuses `--add-gates` from every declared check but triage,
   `--visual` from every check but demo, a demo verdict without `--visual`, and
   an add of a check the effective index at the reviewed commit does not
   declare. An add of a pack check that the reviewed commit's own index leaves
   out is now accepted. It refuses a correctness approve with no `--needs-you`
   when the change touches `review-checks.toml` or a `docs/review-*.md`, and
   the refusal names the files. The same approve with `--needs-you` records, as
   do a change that touches neither and a correctness request-changes.
8. **One reader, one list** (new, structural). No script, formula or skill
   outside `review-checks.sh` reads `review-checks.toml` or a
   `docs/review-<check>.md`, by path or at a commit. signoff.sh's backstop
   names both only to match the paths a change touches, and reads neither, so
   the test looks for reads, not names. No script or formula
   carries a list of two or more of the pack's checks, as a `case` alternation
   or a comma list, except the four configuration sites of section 5. The test
   takes the names from the pack's index.

### What becomes of each test that holds prose

- `review-dispatch-body.test.sh` goes with its script.
- `review-method.test.sh` goes. Its (NEUTRAL), (METHOD), (QUORUM), (SPECIALIST)
  and (KEEPALIVE) cases hold formula and skill wording. (STANDARDS) becomes part
  of test 4, as a property of the correctness skill's files. (RUBRIC), the
  learning loop's anchors in `rubric-ledger.md`, moves beside
  `learning-recurrence.test.sh`, which already inventories that ledger.
  (EVIDENCE) becomes part of test 5.
- `tools/lint-learned.d.test.sh`'s zsh-colon-modifier case rebuilds two lines of
  the live triage skill (`:1225-1250`), and this design rewrites both. It gets a
  fixture of its own, so a lint rule's regression case stops depending on a
  live skill's wording.

### Tests that run a formula's blocks

`formula-worktree-rig.test.sh` (`:183-188`) and `review-workspace.test.sh`
(`:176-178`) extract a review formula's marked blocks and run them.
`step-close.test.sh` (`:1400-1413`) rewrites a copy of `mol-review`'s
review-step close without `--convoy` and checks that its scan catches the
mutant. They test where a formula meets a script, so they stay. The first two
are re-pointed at load-dispatch's blocks, which build the worktree at
`{{reviewed_oid}}` and print the reviewed commit's `docs/review-{{check}}.md`.
A fixture commit carrying `docs/review-triage.md` shows triage's guidance
reaching a triage review, and load-dispatch's refusal is run with
`reviewed_oid` empty to show it reviews nothing, names the key and leaves the
route empty. The chain closes as before, so the third needs only the review
step's close to keep its one `--convoy` call. The review formulas keep no
keepalive block, because no formula block runs a long command any more, so
`lease-heartbeat.test.sh` drops its two lines for them (`:190-191`).

### Suites that reach the resolver

Every reader now passes `--at`, the working-tree read is gone, and the pack's
rows come from beside the resolver. Each suite that runs a reader of the index
is re-derived against that shape. The harness these suites share clears every
`GC_*` variable and stubs git to report no toplevel (`test-harness.sh:55`,
`:1264`), so a resolver run under it finds no repository and reads no rig
layer, today or after this change. A call there that names no commit is
refused as it is anywhere, so the refusal changes only a suite that resolves
with neither a commit nor an index override.

- `review-outcome.test.sh` runs the resolver beside the real
  `review-outcome.sh` and sets no `GC_REVIEW_CHECKS_INDEX`. Today that resolver
  reads no index. Under this design it reads the pack's index from the tree
  under test. The suite sets `GC_REVIEW_CHECKS_INDEX` so its lanes do not follow
  that file, its `supersede-anchor` calls (`:195-242`) pass `--oid`, and a new
  case shows the verb refuses without one.
- `signoff.test.sh` stubs `git show <oid>:review-checks.toml` for signoff.sh's
  own read (`:299-313`). That read moves into the resolver, where the same stub
  serves the rig's layer, and the pack's layer is the index of the tree under
  test, which test 7's accepted pack check reads. The suite also takes test 2
  and the backstop's cases, for which its stub answers the paths a change
  touches.
- `pr-facts.test.sh` (`:109`, `:879`) and `merge.test.sh` (`:58`) copy the
  resolver into a scratch directory, where it finds no pack index, and the
  harness serves it no rig index. It reads no index before this change or
  after it.
  Each suite gains a case in which a stub resolver logs its arguments, showing
  `lanes_green` passing the PR head and gctk merge passing the head it merges.
- `approval-withdraw.test.sh` runs mol-validate's `validate-not-converged`
  block and pins its `supersede-anchor` call (`:337-346`). The call now carries
  `--oid` with the pass's `reviewed_oid`, which the block's runner sets.
- `converse-rework.test.sh` fixes the index with `GC_REVIEW_CHECKS_INDEX`
  (`:172`) and runs the real `review-outcome.sh`. converse-rework.sh now reads
  the anchor's branch head for `--oid`, so the suite stubs `git ls-remote` and
  adds the case where no head reads and the supersede fails closed.
- `liveness-sweep.test.sh` sets `GC_REVIEW_CHECKS_INDEX` (`:21`), which the
  sweep forwards as `--file` today (`liveness-sweep.sh:303-306`). The sweep now
  passes `--at` each anchor's head and no `--file`, so the variable keeps fixing
  the index through the resolver, and the suite stubs the sweep's new read of
  each head. The variable would let a call with no commit resolve, so a case
  in which a head does not read shows the sweep keeps that anchor a candidate
  without resolving it.
- `review-checks.test.sh` takes test 6. Its case of a commit with no index
  (`:268-274`) asserts today's fall-through to the working tree, and asserts
  the pack's rows instead.
- `pr-open.test.sh` and `pr-stack.test.sh` already reach the resolver through
  `--at` with a head, under the harness or with `GC_REVIEW_CHECKS_INDEX` set,
  so the resolver's new shape leaves them as they are. pr-open reads the head
  before it resolves, and every PR in pr-stack's fixtures carries one.
- `gate-ensure.test.sh` reaches the resolver through `--at` as well, at the
  head its `gh` stub answers. Its case of an unread head (`:523-536`) asserts
  that a backed lane still settles and an unbacked one still dispatches, with
  no pin. The refusal holds both anchors for the pass instead, so the case
  asserts the hold, with nothing settled and nothing dispatched. A case shows a
  head that `gh` does not answer read through `git ls-remote` and pinned on the
  review. Its other anchors with no head fixture stop before the resolve, or
  assert nothing the hold changes.

## 9. Sequencing with the review-coverage epic

The epic tk-qjdt90g plans method work on the same surface. Its contract sitting,
visit tk-laelooy, sequences the two. Until it rules, this design proceeds as
ruled.

### Files both touch

| File | This design | The epic |
|---|---|---|
| `formulas/mol-review.toml` | Every step names the values the pour filled in. load-dispatch gathers the anchor, the PR, the worktree and the rig's guidance, and the review step loads the skill named from the check. | U1.6 moves the review step's mechanics into a prep script. U1.5 relaxes the "single honest pass, no subagents" rule (`:31-36`). |
| `formulas/mol-review-quorum-signoff.toml` | The lanes and the synthesis name the values the pour filled in, and `base_ref` retires. | U1.5 lets a lane fan out. |
| `skills/review-correctness/SKILL.md` | The uniform headings. The test-evidence block and the page read name the values by key. | U1.1 to U1.4 change the method: the finding contract, hunting angles, verify-or-demote and the sweep. The cutover tk-b0ww25t edits the test-evidence block. |
| `skills/review-correctness/rubric-ledger.md` | Nothing. Its anchors name What to check dimensions, which keep their names. | U1.1 to U1.4 amend the dimensions it anchors. |
| `assets/scripts/review-dispatch-body.sh` | Deleted. | The epic's Belongs names its correctness arm, gone since #1262. U1.5 names its No fan-out line. |
| `assets/scripts/review-method.test.sh` | Retired. | Closure check 3 leans on its (NEUTRAL) cases. |
| `docs/review-<check>.md` | Read at the reviewed commit by `review-checks.sh --extension`, which load-dispatch calls. | U1.7 writes gc-toolkit's `docs/review-correctness.md`. |
| `assets/scripts/signoff.sh` | Its index read moves to the resolver. It keeps the recorded commit, and it holds a correctness approve on a change to the review guidance until the verdict names the edit. | U1.1 may change what `findings.json` carries, which signoff.sh files as finding beads. |
| PR #1217 (tk-gfb2hbq), open and conflicting with main | Rewrites the same review step. | Carries `review-context.sh` and `review-file-bug.sh`, a first prep script, and the 9,000-character step bound. |

### Rules both touch

- **The subagent policy.** This design deletes the dispatch body's "No fan-out"
  line with its script and writes no subagent text of its own. U1.5 then
  rewrites one place, `mol-review`'s hard rule, and adds what the quorum lanes
  lack.
- **The review's mechanics.** This design puts the review's values in the step
  text and has load-dispatch gather the rest. U1.6's prep script is that
  gathering, packaged as a script: it starts from the values the pour filled
  in rather than deriving them again.
- **Generic in the pack, specific in the rig.** `review-checks.sh --extension`
  at the reviewed commit is the delivery half of U1.7.
- **The step-size bound.** This design shortens every review step, because the
  re-derivation blocks go. The review step is 8,915 characters today, against
  #1217's bound of 9,000.

### Another open bead on this surface

tk-ymhd3o4 (routed to the polecat pool, no branch yet) changes the triage
skill's index-gap observation so a repository's missing index is recorded once
rather than on every review. Unit A (section 10) removes the missing-index case
altogether, because a rig with no index gets the pack's checks. What is left for
tk-ymhd3o4 is the stale case, a rig row the resolver rejects. Built before unit
A, it changes a block unit A then deletes. Built after, it is that one case.

### Recommendation for the sitting

This convoy's build lands first. It changes structure and no judgment, so the
method units then edit content under headings that will not move again. U1.6
builds on the values the pour fills in instead of re-deriving them, and U1.5
has one rule to relax. The other order costs this build a reshaping of a skill
those units have just rewritten, and leaves a prep script deriving the values
the step text now carries. #1217 targets main, so whichever of it and this
convoy's graduation lands second merges the other in.

## 10. The breakdown

The build is two beads onto integration/tk-gaklsnk, in order. The
implementation child, tk-nuctjl8, builds unit A. When it starts, it files unit
B as its sibling in the convoy, with `target` stamped to the integration
branch, blocked on itself and armed with a deferred dispatch, so unit B starts
when unit A lands.

### Unit A: every rig gets every pack check, read at the commit being judged

- `review-checks.sh` takes on the layered index: the pack's rows beside the
  script, the rig's from the commit `--at` names. It gains `--check`, `--show`
  and `--extension`, its working-tree read goes, a call that names no commit
  is refused unless `--file` or `GC_REVIEW_CHECKS_INDEX` names the index, and
  the `method` key is ignored.
- gate-ensure.sh's `live_head_for` reads a head that GitHub does not answer
  through `git ls-remote` (section 2). An anchor whose head neither read
  answers is then held for the pass by the refusal (section 6), so the comment
  that says an unread head sends a review out with no pin
  (`gate-ensure.sh:137-139`) is rewritten with the function.
- liveness-sweep.sh resolves at the head of each anchor's branch, and
  `review-dispatch-body.sh` reads a check's purpose through `--check --at` and
  its extension through `--extension --at` until unit B deletes it (section 6).
- pr-facts.sh, review-outcome.sh and gctk merge pass `--at` the commit each
  acts on (section 6). review-outcome.sh's supersede-anchor gains `--oid`,
  which mol-validate and converse-rework.sh pass, and gctk merge's
  `firstNotgreenLane` takes the head it merges, a Go change.
- signoff.sh validates `--add-gates` against the effective index at the
  reviewed commit. Its scratch-file read and its no-index arm go. It refuses a
  correctness approve with no `--needs-you` on a change that touches the
  review guidance (section 6).
- The triage skill reads its menu with `review-checks.sh --show --at` through
  `scripts-dir`, and its no-index fallback goes.
- `review-checks.toml` loses its `method` keys. Its header states the layered
  index and points at the configuration that holds the baseline.
- A bead in sprintshow's store for its index header, which points its intent to
  leave demo, arch and pm out at a `docs/review-triage.md` (sections 5 and 6).
- Tests 6 and 7 of section 8, the reader half of test 8, and
  `gate-ensure.test.sh`'s cases of an unread head (section 8).

It changes which checks every gating reader sees in a rig whose commit declares
none, and it carries the build's Go change, so it lands alone, reviewable as
one change.

### Unit B: the review bead is data, the step text carries it, and each check is one skill

- gate-ensure.sh writes the record (section 2), passes it as vars on every
  sling, requires a head, pins a stranded review only where it has no pin,
  writes the fixed description, and stops calling `review-dispatch-body.sh`.
  Unit A's refusal already holds an anchor whose head no read answers.
  gate-ensure's own check for a head before it pours holds it where an index
  override lets the resolve pass with no commit.
- `mol-review` and the quorum declare the vars, name each value where they use
  it, refuse a short record, gather in load-dispatch, and load the skill named
  from the check (sections 1 and 3). Their failure arm restores the route as
  today.
- signoff.sh's departed-commit path stops clearing `reviewed_oid`, and
  signoff.sh refuses a `--reviewed-oid` that names a commit other than the
  record's (section 1). The `reviewed_oid` entry in `lifecycle/lifecycle.toml`
  (`:728-733`), which says only that path clears it, says the dispatch writes
  it once and nothing moves or clears it. The other living accounts of the
  clear drop it: `docs/state-machine.md` (`:342-365`), the verdict row of
  `docs/authority-map.md` (`:35`), and gate-ensure.sh's comment on a superseded
  review (`:238-241`).
- The five check skills take the uniform shape and name values by key, and
  `skills/specialist-stance/SKILL.md` is new.
- `review-dispatch-body.sh`, its test, its component-model row,
  `pr-facts.test.sh`'s stub and `review-method.test.sh` go. Tests 1 to 5 of
  section 8 land, with the list half of test 8, which can hold only once the
  dispatch body's case arm is gone. The formula-block tests are re-pointed, and
  the lint case gets its fixture.

It depends on unit A for `--check`.

### The change at graduation

Nothing on the integration branch runs. The design takes effect when the convoy
graduates to main and the rig checkout fast-forwards, which moves gate-ensure,
the formulas and the skills in one step.

A review poured before then keeps the step text it was poured with. That text
reads the description and the metadata the bead was dispatched with, so the
review finishes under the old frame. The skills it loads from the catalog are
the new ones, which name values by key. The old steps print the same values
under shell names, `REVIEWED_OID` for `reviewed_oid` and `BASE` for
`review_base`, so the agent fills a new skill's placeholders from them. A
review stranded across the change is slung again by the new gate-ensure, whose
stranded arm completes the record, writing the pin only where there is none,
and passes the record as vars (section 2).

The one exception to reading only the dispatch's commit is an old review that
today's gate-ensure dispatched with no commit, because its read of the head
failed (`gate-ensure.sh:137-139`). If its old workflow is still running, it
takes the live head through its old load-dispatch (`mol-review.toml:113-114`)
and the review step's re-derivation (`:156`). Nothing new refuses a value the
old steps supply: signoff.sh compares the call's commit only with a pin the
record holds. If it is held with no workflow, because an old failure arm
returned it to the pool, its claimant follows its old description to the new
steps, and they refuse it for the commit it lacks (section 1). Once the
claimant releases it, its old workflow reads as spent with no verdict, and
gate-ensure's spent-workflow arm escalates it as a wedge.

An old review bead carries none of the keys this design adds:
`review_formula`, `review_pr_url`, `review_pr_number` and `review_context`.
Lacking them stops nothing. `review_formula` is read only by the fixed
description, which an old bead does not carry, and its own description names
its formula outright (`review-dispatch-body.sh:72-75`, `:105-106`). A review
without the PR keys skips the PR's page and reads the change with git, which
is what every review on main does today, because no writer stamps a PR on a
review bead. `review_context` may be empty on any review. So an old review
poured before graduation finishes as above, and an old one held with no
workflow that carries its commit follows its old description to the new steps,
where the four keys it lacks read as empty.

## What this design does not change

- No check's judgment. Sentences move between headings, and how a block names a
  value changes.
- The formula names `mol-review` and `mol-review-quorum-signoff`, which the
  board, the witness, orphan disposal, gate-ensure and the learning loop key on.
- How a formula reaches the pack's scripts (`lease-heartbeat.sh`,
  `review-workspace.sh`, `signoff.sh`, `step-close.sh` and `review-checks.sh`):
  through the candidate loop, until tk-60i7nl6 lands.
- The default `check_set`, and who stamps it (section 5).
- `findings.md`, `findings.json`, the verdicts signoff.sh records and what it
  writes for each, and the validator.
