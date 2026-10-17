---
name: The review path as one lifecycle formula and one skill per check
description: The design for tk-zif1d8u, the design child of convoy tk-gaklsnk under initiative tk-febol6c. A review bead becomes data. gate-ensure.sh writes the review's whole record once, at dispatch, and every formula step and check skill reads it by name through one script. A check's method is the skill named from the check, and a check with no skill is a paragraph of the formula. The specialist stance is one skill. Every rig gets every check the pack ships, and every reader takes a rig's review guidance from the rig's default branch. It settles the frame contract, the review bead's data, method loading, the skill shape, the live read, process versus subject, the tests, the sequencing with the review-coverage epic, and the implementation breakdown. Read it to approve the design at its checkpoint or to build one of its units.
---

# The review path as one lifecycle formula and one skill per check

## What the operator approves here

Today three layers of bash assemble a review. A script writes the reviewer's
instructions into the review bead's description. Each formula step re-derives
the same values into shell variables. The check skills then use those variables
without saying where they come from. Separately, a rig that keeps no
`review-checks.toml` can never get the demo, arch or pm check. And the rig
files that steer a review are read at the commit under review, so a process fix
merged on a rig's main does not reach work already in flight.

1. **The review bead's metadata is the review's whole record, written once at
   dispatch.** gate-ensure.sh already writes the check, the anchor, the branch,
   the base and usually the reviewed commit. It adds the PR once one is open,
   the reason for the dispatch, and the formula that runs the review. It
   dispatches a review only once it has read the branch's head, so every review
   is pinned. Every formula step and every check skill reads a value by name
   through one script, `review-frame.sh`, given the review bead's id. Cost: a
   review whose head neither GitHub nor `git ls-remote` can read waits a pass
   instead of starting unpinned. This refines the card's "the formula records
   its pins once": the dispatch records them, because the quorum's two lanes
   start in parallel and a recovered review has no workflow to record them.
2. **A check's method is the skill named from the check.** The formula loads
   `gc-toolkit.review-<check>`. A check a rig's index declares with no pack
   skill is judged against its row's purpose. A check declared nowhere is
   approved with `--needs-you`. Both cases are a paragraph of the formula.
   `review-dispatch-body.sh` and its test are deleted, and the bead's
   description becomes one fixed paragraph on how to recover a review with no
   workflow. Cost: none for today's five checks.
3. **The specialist stance is one skill, `gc-toolkit.specialist-stance`.** The
   demo, arch and pm skills load it, and so does the formula's no-skill case.
   Cost: one more entry in every agent's skill list.
4. **Every rig gets every check the pack ships.** The pack's
   `review-checks.toml` declares the five checks. A rig's own index is optional:
   its rows add a check of the rig's own or change a pack check's phase or
   purpose for that rig. The `method` column goes. Cost: triage can now add
   demo, arch or pm in the three rigs here that keep no index (gascity,
   shutupandlisten, signal-loom) and in sprintshow, whose index lists only
   correctness and triage. Triage's judgment does not change, and adding
   nothing stays its common case.
5. **Every reader takes a rig's review guidance from its default branch, at
   most a minute old.** That guidance is `review-checks.toml` and
   `docs/review-<check>.md`, read through `review-checks.sh` by the cadence,
   signoff.sh, the formula and triage. A process change merged on a rig's main
   applies to work in flight. A branch's own edit to those two files governs
   nothing until it lands. Everything else a check reads, the diff and the docs
   it holds the change to, is read at the reviewed commit. Cost: one fetch of
   the default branch per rig per minute, and pr-open's gates follow main's
   phases rather than the PR head's.
6. **Tests pin behavior where the pieces meet, iterating the index.** Each
   declared check resolves to its skill or its purpose, the dispatch writes the
   record and the reader refuses a short one, every skill block runs given only
   a record, and signoff.sh refuses each flag a check does not own. Cost: no
   test holds a formula's wording, so a step that loses an instruction is
   caught in review, not by the suite.
7. **This lands before the review-coverage epic's method units.** It changes
   the review path's structure and no check's judgment. Those units then edit
   inside the new skill shape, build their prep script on `review-frame.sh`, and
   relax the subagent rule in the one place it is left. Cost: they wait for this
   convoy's build. The epic's contract sitting rules on this (section 9).
8. **The build is two beads onto this integration branch, in order.** First the
   live read and the layered index, which every gating reader takes. Then the
   record, the frame and the skills. Cost: one more PR to approve on the
   integration branch, for two diffs that are each reviewable in one sitting.
   The single build the card intended is the alternative, at the cost of one PR
   across about forty files.

## What this design rests on

The pack is read at `9db3fea95`, which is main with PR #1262 landed and the
commit integration/tk-gaklsnk was cut from. Line numbers in this document are at
that commit.

The sources are the operator's three reviews of PR #1262 (5536090671,
5538944776, 5542707712), the review comments 4286312773 ("A repo does not need
to include anything to get a great review") and 4290610037 ("the new process
inside of that rig should absolutely be applied"), the ruling in visit
tk-0smmk03, and the Target, Done-when and Boundaries of tk-febol6c.

Facts read from the running city:

- The review pool is the rig's `polecat-codex` pool
  (`assets/scripts/refinery-reconcile.sh:89`). That pool claims any bead that
  carries a formula, not only reviews (`agents/polecat-codex/agent.toml:1-4`).
- Pack skills reach a session as catalog links named `gc-toolkit.<dir>`, which
  point at the installed pack. `gc skill list` prints them with their binding.
- `gc <binding> scripts-dir` (PR #1269) prints the installed pack's script
  directory. The ask-for-work skills call every pack script through it
  (`docs/gascity-packs.md:566-580`).
- Each rig's `review-checks.toml` on its default branch today:

  | Rig | `review-checks.toml` | `docs/review-<check>.md` |
  |---|---|---|
  | gc-toolkit | correctness, triage, demo, arch, pm | none |
  | gascity | none | none |
  | shutupandlisten | none | none |
  | signal-loom | none | none |
  | sprintshow | correctness and triage, no phase, `method = "formulas/mol-review.toml"` | none |

Settling the design turned up four defects on main. Each is the frame contract
or the index read showing through, so the build fixes each and none is filed
on its own:

- **No writer stamps a PR on a review bead.** gate-ensure.sh's work order has no
  PR key (`gate-ensure.sh:189-196`), so `mol-review`'s post-open branch never
  runs (`formulas/mol-review.toml:79-88`). The correctness skill's read of the
  published page then runs with an empty `$PR` and `$PR_REPO_Q`
  (`skills/review-correctness/SKILL.md:104`).
- **The triage skill cannot find its parser outside gc-toolkit.** It looks for
  `review-checks.sh` under `GC_PACK_DIR`, which agent sessions never have, and
  under `GC_RIG_ROOT`, which holds the pack only when the rig is gc-toolkit
  (`skills/review-triage/SKILL.md:38-41`). In every other rig the parse prints
  nothing, and triage reads that as no menu.
- **The triage skill uses `$ANCHOR`, which no frame block sets.** It feeds the
  bring-current round read and the observation's provenance
  (`skills/review-triage/SKILL.md:122-123`, `:187`, `:196`).
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
(`formulas/mol-review-quorum-signoff.toml:91-95`) and in the synthesis
(`:219-231`, `:260-267`).

The skills use those variables by name. The correctness skill uses `$M`,
`$BASE`, `$REVIEWED_OID`, `$PR`, `$PR_REPO_Q` and `hb`. Triage uses
`$REVIEW_BEAD`, `$REVIEWED_OID` and `$ANCHOR`. Demo uses `$REVIEW_BEAD`,
`$REVIEWED_OID`, `$BASE`, `$REVIEW_WT`, `$SCRIPTS` and `hb`, and pm uses
`$REVIEWED_OID`. No variable survives from one tool call to the next. So a
skill's block works only when the agent pastes the formula's blocks in front of
it in one shell, which is what `mol-review.toml:197-201` asks.

### The record

The review's record is the review bead's metadata. gate-ensure.sh writes all of
it when it dispatches the review (section 2), and no formula step writes to it.

| Key | Required | What it names |
|---|---|---|
| `task_kind` | yes | `review` |
| `check_name` | yes | the check, as the anchor's `check_set` wrote it |
| `anchor_bead` | yes | the anchor the verdict lands on |
| `review_branch` | yes | the branch under review |
| `review_base` | yes | the branch it lands on, which is the diff's base |
| `reviewed_oid` | yes | the commit the review reads, the head at dispatch |
| `review_formula` | yes | the formula that runs the review |
| `review_pr_url`, `review_pr_number` | both once a PR is open, neither before | the anchor's PR at dispatch |
| `review_context` | no | why this dispatch went out |
| `review_pool`, `fix_target_pool` | routing | where the failure arm and a rework go, as today |

The reader computes five more values and stores none of them:

| Value | What it is |
|---|---|
| `review_bead` | the review bead, resolved from the input convoy |
| `check` | `check_name` folded to lowercase, the form a skill name and the index use |
| `pr_repo` | `host/owner/repo` parsed from `review_pr_url`, the pin every `gh` call takes |
| `repo` | the rig's repository: `GC_RIG_ROOT`, else the rig `GC_RIG` names in `gc rig list` |
| `worktree` | the path of the review's worktree at the reviewed commit |

### The reader: review-frame.sh

`assets/scripts/review-frame.sh` is the contract written once: what a step or a
method may ask of the review. Every verb takes the review bead as `--bead <id>`,
or as `--convoy <id>` from a step. `--convoy` resolves the convoy's one tracked
member and refuses any other count, the check each step writes inline today.

- `record` prints the record and the derived values, one `name=value` per line,
  with `review_bead` first. It exits 3 when the record is short of any required
  key.
- `pin <name>` prints one value. It exits 3 only when that value is required
  and missing. An optional key the record does not carry prints nothing and
  exits 0.
- `diff [--stat]` prints the diff under review,
  `origin/<review_base>...<reviewed_oid>`, in the rig's repository. Three dots
  compare against the merge-base, as `mol-review` does today. It fetches the
  base and the commit when the repository lacks them.
- `show <path>` prints a file as the reviewed commit carries it, from the rig's
  repository. It exits 3 when the commit has no such file. This is the subject
  read of section 7.
- `worktree` makes the review's worktree at the reviewed commit through
  `review-workspace.sh add`, or finds the one already there, and prints its
  path. It fetches the commit when the repository lacks it.

Every verb exits 0 when it printed, 1 when the bead or the convoy cannot be
read, and 2 on a usage error. A verb that needs the PR exits 3 on a
`review_pr_url` it cannot parse, or on one PR key without the other. Every exit
3 names the key on stderr. A test hands the script a fixture row instead of a
store, which is what lets a method's blocks run outside a city (section 8).

### What a step and a skill may assume

1. The review bead's id. `load-dispatch` prints it at the head of the record.
   In recovery, it is the bead you hold.
2. Any value of the record, read by name:
   `review-frame.sh pin <name> --bead <id>`.
3. The diff under review, and any file at the reviewed commit, through
   `review-frame.sh diff` and `review-frame.sh show`.
4. The review's worktree at the reviewed commit, through
   `review-frame.sh worktree`.
5. A keepalive for a long command:
   `lease-heartbeat.sh <the step bead your claim returned> -- <command>`. The
   lease belongs to the claimed step, which differs per step and per lane, so
   the record cannot carry it. The agent has it from its own claim.
6. The rig's guidance for the check, which the review step prints (section 3).
7. The verdict envelope, `findings.md` and `findings.json`, and the one
   `signoff.sh` call the frame makes with the flags the method names.

Nothing else. A block that needs a value reads it inside that block. A skill
names a value in its prose by its key, as `<reviewed_oid>`.

A formula step reaches a pack script the way every formula reaches one today,
through the candidate loop that tk-60i7nl6 replaces when it lands. A skill
reaches one as `"$(gc <binding> scripts-dir)/<script>"`, the form the
ask-for-work skills use.

### A short record

A review dispatched under this design cannot reach a reviewer short of its
record. gate-ensure.sh slings a review only once its whole work order reads
back (`gate-ensure.sh:1050-1067`). Its stranded arm writes the whole order
before it slings a review again (`:954`). So a short record means a bead made
by hand or before this design.

`load-dispatch` reads the record with `record`, which refuses a short one with
exit 3 and names the key. The step then appends that message to the review
bead's notes, closes the chain forward and drains. It does not restore the
bead's route, because the next claim would meet the same short record.
gate-ensure's spent-workflow arm then reads the review as wedged and asks a
person for one of its two repairs (`gate-ensure.sh:479-520`). Reviewing an
unpinned commit is never the fallback.

### The quorum reads one record

The two lanes and the synthesis each read the same record through
`review-frame.sh --convoy`. A lane's whole input is `record` and `diff`. No lane
derives a value, so the two lanes cannot read different commits, and the
quorum needs no pin step of its own. The quorum's `base_ref` var retires: it
stood in for a `review_base` the record now always carries, and
refinery-reconcile.sh never passes it (`refinery-reconcile.sh:120-133`).

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
  missing, and the review then goes out unpinned (`gate-ensure.sh:137-139`,
  `:152-166`). Under this design it falls back to
  `git ls-remote origin refs/heads/<branch>`, which needs only the origin the
  review fetches from anyway. An anchor whose head neither read answers is held
  for the pass, which is the arm's ordinary "merge stays held, retry next
  pass". The stranded arm writes `reviewed_oid` only when the review has none.
  It pins the live head, and it never moves a pin a dispatch wrote.

### The description

The bead's description becomes one fixed paragraph, with nothing substituted
into it:

> This is a signoff review. Its metadata is the review's record: the check, the
> anchor, the reviewed branch, base and commit, the PR once one is open, and the
> formula that runs it. If you hold this bead with no poured workflow, run
> `gc formula show` on the formula its `review_formula` names and follow its
> steps in order, with this bead as the review bead they read.

gate-ensure passes it on the create, where it passes the composed body today
(`gate-ensure.sh:1053-1058`).

### Every reader of today's description

No script reads a review bead's description. The scripts that read a
description read an anchor's or a finding's: `pr-open.sh`, `pr-stack.sh`,
`review-answer.sh` and `scaffolding-sweep.sh`. The readers are the agents and
two tests.

| Reader | Reads today | Reads instead |
|---|---|---|
| `mol-review` load-dispatch, step 5 (`mol-review.toml:118-122`) | the note's check section, which names the method | the record's `check`. The review step names the skill (section 3). |
| The quorum lanes, step 2 (`mol-review-quorum-signoff.toml:97-99`, `:163-165`) | the skill the check section names | the same |
| The demo, arch and pm skills (`review-demo/SKILL.md:15`, `review-arch/SKILL.md:10`, `review-pm/SKILL.md:13`) | "the dispatch note's shared specialist stance" | `gc-toolkit.specialist-stance` (section 4) |
| The demo skill on `docs/review-demo.md` (`review-demo/SKILL.md:138-140`) | the extension the note appended from the reviewed commit | the guidance the review step prints, read live (sections 3 and 6) |
| A claimant of a review the failure arm returned to its pool (`mol-review.toml:372-384`) | the note's recovery paragraph | the fixed paragraph and `review_formula` |
| The reviewer reading why it was dispatched | the note's "Context from the dispatch" | `review_context`, which load-dispatch prints with the record |
| A Claude lane of the quorum, through the work-context hook (`overlays/work-context`) | the whole description, at claim | the fixed paragraph. The record arrives through the frame. |
| `gate-ensure.test.sh` (`:61-62`, `:232`) | a stub body script and its marker | assertions on the record and the fixed paragraph |
| `pr-facts.test.sh` (`:191-195`, `:880`) | a stub body script that pr-facts.sh never calls | nothing. The stub goes. |

`review-dispatch-body.sh`, its test and its row in `docs/component-model.md`
(`:394`) are deleted. The rules its frame section shares with the formula
stay in the formula: one verdict, never `gh pr review --approve`, and what to
do when a rewrite takes the pinned commit off the branch. Its "One agent,
single pass. No fan-out" line goes with the script. That leaves `mol-review`'s
own rule as the one place the subagent policy lives (section 9).

## 3. Loading the method

Every step that applies a method carries this paragraph: `mol-review`'s review
step, and the quorum's two lanes and its synthesis, which judges and runs under
the same method. It names no check:

> The check's method is the skill `gc-toolkit.review-<check>`, where `<check>`
> is the record's `check`. Load it from your skill catalog and apply it, and no
> other review skill. A copy of a skill in the review's worktree is the change
> under review, not your method. When your catalog has no such skill:
>
> - If the rig's check index declares the check
>   (`review-checks.sh --check <check>` prints its row), judge the diff against
>   the purpose the row states. Load `gc-toolkit.specialist-stance` and hold it.
>   Say in your coverage line that the pack ships no method for this check.
> - If no index declares it, approve, and pass `--needs-you` saying the check
>   is declared nowhere, so the operator decides whether it stays in the
>   anchor's `check_set`.
>
> Then print the rig's guidance for the check,
> `review-checks.sh --extension <check>`. It adds to the method and never
> replaces it. Most rigs keep none.

- **The name.** `gc-toolkit.<name>` is the name `docs/skills.md` gives every
  pack skill, and the one the operator ruled for pack text (review
  5538944776). A city that imports the pack under another binding sees
  `<binding>.review-<check>`. The ask-for-work skills make the same
  substitution for `gc <binding> scripts-dir`.
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
- **`## What it reads`.** The record's values it uses, by key. The subject
  documents it holds the change to, read at the reviewed commit with
  `review-frame.sh show`. The rig's guidance the frame prints.
- **`## What it judges`.** The method, as it stands.
- **`## What blocks`.** Which findings make the verdict `request-changes`, and
  which ride along.
- **`## The verdict`.** The lines it adds to the envelope, what `findings.json`
  carries, and each `signoff.sh` flag it passes beyond the frame's call, or
  "none".

The mechanics a method needs are calls given the review bead (section 1). A
block reads every value it uses through `review-frame.sh`, in that block.

The reshaping moves sentences between headings and rewrites how a block reads
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
| correctness | `$M`, `$BASE`, `$REVIEWED_OID`, `$PR`, `$PR_REPO_Q`, `hb`, and `$ANCHOR` set from `$M` | Its preamble about the formula's blocks goes (`:12-17`). The test-evidence block reads `anchor_bead` and `reviewed_oid` through `review-frame.sh`. The page read becomes `gh pr view <review_pr_number> --repo <pr_repo>`. Suites run under the keepalive. Flags: none. |
| triage | `$REVIEW_BEAD`, `$REVIEWED_OID`, and `$ANCHOR`, which nothing sets | The index parse becomes `review-checks.sh --show` (sections 5 and 6). Its no-index fallback and the missing-index observation go, because every rig has the pack's menu. The observation stays for a rig row the resolver rejects. The anchor comes from the record. It never blocks. Flags: `--add-gates`, `--reopen`, `--round-reason`, `--dismiss-approval`. |
| demo | `$REVIEW_BEAD`, `$REVIEWED_OID`, `$BASE`, `$REVIEW_WT`, `$SCRIPTS`, `hb` | Loads the stance. The capture runs beside the worktree `review-frame.sh` returns, under the keepalive. `demo-repo-artifact.sh` and `demo-deliver.sh` are reached through `scripts-dir`. `docs/review-demo.md` is the guidance the frame prints. Flags: `--visual`, `--visual-fallback-from`. |
| pm | `$REVIEWED_OID` | Loads the stance. Reads `docs/product-goals.md` with `review-frame.sh show`. Flags: none. |
| arch | none | Loads the stance. Reads `docs/architecture.md` and `docs/architecture/` with `review-frame.sh show`. Flags: none. |

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
- **The rig's index** is the rig's own `review-checks.toml` on its default
  branch (section 6), and it is optional. A row for a check the pack declares
  changes that check's phase or purpose for the rig, key by key, and a key the
  row leaves out keeps the pack's value. A row for any other check adds a
  check of the rig's own, judged against its purpose (section 3) with whatever
  guidance its extension adds.
- **In gc-toolkit the two are one file**, so its effective index is that file as
  its default branch carries it. It follows that a check gc-toolkit declares is
  a pack check, which every rig gets. The test that every pack row has a skill
  keeps a skill-less check out of that file. gc-toolkit has no rig-only check
  today, and one would need a second file.

The initiative's constraint holds with one refinement: a check is declared in an
index and nowhere else. The pack's index declares the checks the pack ships,
and a rig's index declares its own. No script, formula or skill lists checks.

A rig cannot withdraw a pack check. Triage judges whether a diff warrants each
check, and adding nothing is its common case, so a rig with no screens never
gets demo added for want of a visual surface. A row that withdraws a check can
come later, if a rig needs one.

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
   the lanes from the pack's index, since gascity keeps none, and writes the
   record from gascity's branch, base, head and PR.
2. The review runs on gascity's `polecat-codex` pool. Its catalog links the
   installed pack's skills, so `gc-toolkit.review-arch` loads from the pack gc
   loaded, wherever the city imports it from.
3. `review-frame.sh` reads the record from gascity's store, and diffs and builds
   the worktree in gascity's repository.
4. `review-checks.sh --extension arch` reads gascity's default branch and finds
   no extension.
5. Triage can add arch, pm or demo, and signoff.sh validates the add against the
   same effective index.
6. liveness-sweep classifies gascity's anchors against that index, not
   gc-toolkit's.

Each step names the rig by `GC_RIG_ROOT` and the pack by the pack gc loaded.
None of them reads gc-toolkit as the rig under review.

## 6. The live read

### What current means

A rig's current copy of a file is the file at the tip of the rig's default
branch as origin has it: `refs/remotes/origin/<default>` in the rig's
repository, where `<default>` is the branch `refs/remotes/origin/HEAD` names,
else `main`. refinery-reconcile.sh resolves the graduation target the same way
(`:136-141`). Every worktree of the rig's repository shares that ref.

The resolver refreshes the ref with one `git fetch origin <default>` when its
own last refresh is more than a minute old. A merge on the rig's main therefore
reaches every reader within a cadence pass, and a pass that resolves fifty
anchors fetches once. A fetch that fails leaves the ref as it stands, and the
resolver reads it with a warning, because a slightly stale copy of the rig's
process is better than none.

Current is not:

- **the rig root's working tree**, which trails origin until
  reconcile-rig-checkouts fast-forwards it on its cooldown, and stalls whenever
  that fast-forward is refused;
- **the checkout the caller stands in**, which for a worker is its own branch and
  for a reviewer is the worktree of the change under review. That is what
  `review-checks.sh:148-152` and `:171-173` read today;
- **the reviewed commit.**

The rig's repository is `GC_RIG_ROOT`, else the rig `GC_RIG` names in
`gc rig list`. A caller that has neither gets a refusal, never a guess. A
repository with no such ref has no rig layer, which reads as a rig that keeps
no index, with a warning.

### The one resolver

`review-checks.sh` keeps its job as the one parser and resolver of the check
index, and it takes on the rig's extensions:

- `--resolve --check-set <cs> --through <phase> [--with-phase]` resolves against
  the effective index, read live. `--at` and the working-tree read retire.
- `--check <name>` prints one check's effective row, which the purpose case
  reads. `--show` prints the whole effective index, which is triage's menu.
- `--extension <check>` prints the rig's `docs/review-<check>.md` from the same
  ref, and exits 3 when the rig keeps none.
- `--file <index>` stays for a test that parses one file.
  `GC_REVIEW_CHECKS_INDEX` keeps naming the whole effective index, so a hermetic
  test fixes what every reader sees.

### A bad rig index degrades, it does not stall

Read at the reviewed commit, an index with a phase outside the ordered set held
only the PRs that carried it (`review-checks.sh:227-235`). Read live, the same
refusal would hold every transition of every PR in the rig until someone fixed
main. So the resolver ignores a rig row it cannot use, with a warning. A pack
check keeps the pack's row. A rig-only check takes pre-open, the phase that
gates every transition. Nothing opens or leaves draft ungated, and nothing
stalls.

### Every reader and its move

| Reader | Reads today | Moves to |
|---|---|---|
| `gate-ensure.sh` (`:817`) | `--resolve --at` the PR head | `--resolve`, live |
| `pr-open.sh` (`:456`, `:553`, `:789`) | `--resolve --at` the head the PR opens at, directly and through `prs_resolve_phased` | live. The pass's one fetch of branch heads stays, for the heads themselves. |
| `pr-summary-region.sh` `prs_resolve_phased` (`:37-42`), and `pr-stack.sh`, which calls it (`:263`) | `--at <head>` | live. The head stays the region's, not the index's. |
| `pr-facts.sh` (`:664`) | the working tree | live |
| `review-outcome.sh` (`:339`) | the working tree | live |
| `gctk merge` (`services/gctk/internal/cli/merge.go:989`) | the working tree, through the script | live, with no Go change, because it calls the resolver with no source flag |
| `liveness-sweep.sh` (`:298-313`) | gc-toolkit's own index, two directories above the script | the effective index of the rig it sweeps |
| `signoff.sh --add-gates` (`:859-883`, `:907-913`) | `git show <reviewed_oid>:review-checks.toml`, through a scratch file | `review-checks.sh --check`, live. The no-index arm goes. |
| the triage skill (`:37-48`) | `git show ${REVIEWED_OID}:review-checks.toml`, with a parser it finds only in gc-toolkit | `review-checks.sh --show`, through `scripts-dir` |
| `review-dispatch-body.sh` (`:161-168`, `:199-215`) | the purpose and the extension at the reviewed commit | `--check` and `--extension`, live, until unit B deletes it and the formula makes both reads (section 3) |
| the demo skill (`:138-140`) | the extension the note appended | the guidance the review step prints |

The pm skill reads neither file. Its one read of the rig is
`docs/product-goals.md`, which is subject (section 7), and it names the index
only in prose.

On merge the move changes nothing in practice: `--through merge` gates every
declared token whatever its phase. The live read matters for which checks gate
a PR's opening and its leaving draft.

#1262 deleted `docs/review-config.md`, so the pinning rule and its in-flight
rationale now sit in the index header (`review-checks.toml:12-13`, `:21-27`).
Both paragraphs are rewritten to the live rule, and to who reads an extension.
The rule is rewritten wherever else it is stated:

- `review-checks.sh`'s header (`:33-43`);
- `signoff.sh`'s usage and comment (`:119-123`, `:859`);
- the comments on resolving at the head in `gate-ensure.sh` (`:804`) and
  `pr-open.sh` (`:254-260`);
- the triage skill's index contract (`:28-35`, `:55-59`);
- the demo skill (`:138-140`);
- `mol-refinery-patrol`'s `check_set` var description (`:95`), which says
  triage reads the index at the reviewed commit.

## 7. Process versus subject

Two rig files are process: `review-checks.toml` and `docs/review-<check>.md`.
They say how the rig wants its changes reviewed. Every reader takes them live,
through `review-checks.sh`. A branch that edits either is reviewed like any
other change, and its edit governs nothing until it lands.

Everything else a review reads in the rig is subject. That is the diff, and
every document a check holds the change to, read at the reviewed commit through
`review-frame.sh show` or in the review's worktree, which is that commit. Arch
reads `docs/architecture.md` and `docs/architecture/`, pm reads
`docs/product-goals.md`, and demo reads the visuals `demo-repo-artifact.sh`
lists. A change may edit those documents itself, and the check judges it
against the version it carries. Arch's question, whether an architecture change
is reflected in the docs in the same PR, depends on that.

A document an extension points to is subject, though the pointer is process. A
rig's `docs/review-arch.md` that says its architecture lives in
`ARCHITECTURE.md` is read live, and `ARCHITECTURE.md` is read at the reviewed
commit.

The pack's content is neither. The methods and the stance load from the
installed pack's catalog, and the correctness skill's work-quality fragments
come with it through its `references/` links. In gc-toolkit, where pack and rig
share one repository, a branch that edits a method is reviewed under the
installed method, not under its own edit.

An extension is named for its check, and the frame reads one only for the
review's check. gc-toolkit's `docs/review-workspace.md` shares the prefix, and
it is never read as an extension, because no index declares a check named
`workspace`.

The specialist stance's instruction to read the reference docs a check
stewards at the reviewed commit is this rule, and it stays.

## 8. Tests where the pieces meet

### New behavior tests

1. **The record** (`gate-ensure.test.sh`). A fresh dispatch writes every
   required key and the fixed paragraph. A `pull_request` anchor's dispatch
   carries its PR as `review_pr_url` and `review_pr_number`. `review_context`
   carries the reason, the bring-current ruling line included. A head that
   neither `gh` nor `ls-remote` reads holds the dispatch, and the `ls-remote`
   fallback pins. The stranded arm writes `reviewed_oid` only where it is
   absent.
2. **The reader** (`review-frame.test.sh`, new). `record` prints each key and
   each derived value. Removing any required key makes it exit 3 and name that
   key. An unparseable PR URL, or one PR key without the other, exits 3.
   `--convoy` refuses a convoy with no member or with two. `diff` and `show`
   read the reviewed commit, not the working tree, from a cwd in another
   repository. `worktree` builds the worktree in the repository `GC_RIG_ROOT`
   names, from a wrong cwd, and returns the same one when run twice.
3. **Method resolution, iterating the pack's index** (new). Every row has a
   `skills/review-<check>/SKILL.md` whose frontmatter `name` is
   `review-<check>` and which has a verdict section. Every `skills/review-*`
   directory has a row. Every flag a skill's verdict section names is one
   `signoff.sh` accepts, and every skill a check skill says to load is one the
   pack ships. The correctness skill's `references/` links resolve to the
   work-quality fragments and the exemplar corpus. A fixture rig index that adds
   a check with no skill resolves to its purpose through `--check`, and a token
   no index declares resolves to nothing. The `review-method-load` region is the
   same text in every step that carries it.
4. **The frame contract, iterating the pack's index.** Every shell block in each
   check's skill runs under `set -u` in a fresh shell, given only a review bead
   id, a stub store serving a fixture record, and a scratch rig repository. The
   block's placeholders are filled from the fixture, and the commands with
   effects outside the scratch repository (`gh`, `bd create`, the capture
   engine) are stubbed. No block uses a value it did not read itself. The
   correctness test-evidence block's bash and zsh cases, now
   `review-method.test.sh` (EVIDENCE), become two of these runs.
5. **The live read** (`review-checks.test.sh`). A rig with no index resolves to
   the pack's rows. A rig row changes a pack check's phase and keeps its
   purpose. A rig row adds a check. A `method` key is ignored. A rig row with a
   bad phase is ignored with a warning, a pack check keeps its row, and a
   rig-only check takes pre-open. The rig layer comes from origin's default
   branch, not from the rig root's working tree and not from the caller's
   checkout, which the test proves by running from a worktree whose branch
   carries a different index. The ref is fetched at most once a minute and read
   as it stands when the fetch fails. `--extension` prints the default branch's
   copy, ignores the reviewed commit's, and exits 3 when the rig keeps none.
6. **What signoff.sh refuses** (`signoff.test.sh`), iterating the effective
   index. It refuses `--add-gates` from every declared check but triage,
   `--visual` from every check but demo, a demo verdict without `--visual`, and
   an add of a check the effective index does not declare. An add that the live
   index declares and the reviewed commit's does not is now accepted.
7. **One reader, one list** (new, structural). No script, formula or skill
   outside `review-checks.sh` reads `review-checks.toml` or a
   `docs/review-<check>.md`, by path or at a commit. No script or formula
   carries a list of two or more of the pack's checks, as a `case` alternation
   or a comma list, except the four configuration sites of section 5. The test
   takes the names from the pack's index.

### What becomes of each test that pins prose

- `review-dispatch-body.test.sh` goes with its script.
- `review-method.test.sh` goes. Its (NEUTRAL), (METHOD), (QUORUM), (SPECIALIST)
  and (KEEPALIVE) cases pin formula and skill wording. (STANDARDS) becomes part
  of test 3, as a property of the correctness skill's files. (RUBRIC), the
  learning loop's anchors in `rubric-ledger.md`, moves beside
  `learning-recurrence.test.sh`, which already inventories that ledger.
  (EVIDENCE) becomes part of test 4.
- `tools/lint-learned.d.test.sh`'s zsh-colon-modifier case rebuilds two lines of
  the live triage skill (`:1225-1250`), and this design rewrites both. It gets a
  fixture of its own, so a lint rule's regression case stops depending on a
  live skill's wording.

### Tests that run a formula's blocks

`formula-worktree-rig.test.sh` (`:183-188`), `review-workspace.test.sh`
(`:176-178`) and `step-close.test.sh` (`:1404-1413`) extract a review formula's
marked blocks and run them. They test where a formula meets a script, so they
stay, re-pointed at the new blocks: the worktree is built through
`review-frame.sh`, and the chain closes as before. The review formulas keep no
keepalive block, because no formula block runs a long command any more, so
`lease-heartbeat.test.sh` drops its two lines for them (`:190-191`).

## 9. Sequencing with the review-coverage epic

The epic tk-qjdt90g plans method work on the same surface. Its contract sitting,
visit tk-laelooy, sequences the two. Until it rules, this design proceeds as
ruled.

### Files both touch

| File | This design | The epic |
|---|---|---|
| `formulas/mol-review.toml` | Every step reads the record. The review step loads the skill named from the check and prints the rig's guidance. The verdict call stops passing `--reviewed-oid`. | U1.6 moves the review step's mechanics into a prep script. U1.5 relaxes the "single honest pass, no subagents" rule (`:31-36`). |
| `formulas/mol-review-quorum-signoff.toml` | The lanes and the synthesis read the record, and `base_ref` retires. | U1.5 lets a lane fan out. |
| `skills/review-correctness/SKILL.md` | The uniform headings. The test-evidence block and the page read go through `review-frame.sh`. | U1.1 to U1.4 change the method: the finding contract, hunting angles, verify-or-demote and the sweep. The cutover tk-b0ww25t edits the test-evidence block. |
| `skills/review-correctness/rubric-ledger.md` | Nothing. Its anchors name What to check dimensions, which keep their names. | U1.1 to U1.4 amend the dimensions it anchors. |
| `assets/scripts/review-dispatch-body.sh` | Deleted. | The epic's Belongs names its correctness arm, gone since #1262. U1.5 names its No fan-out line. |
| `assets/scripts/review-method.test.sh` | Retired. | Closure check 3 leans on its (NEUTRAL) cases. |
| `docs/review-<check>.md` | Read live by `review-checks.sh --extension`. | U1.7 writes gc-toolkit's `docs/review-correctness.md`. |
| `assets/scripts/signoff.sh` | Its index read moves to the resolver. | U1.1 may change what `findings.json` carries, which signoff.sh files as finding beads. |
| PR #1217 (tk-gfb2hbq), open and conflicting with main | Rewrites the same review step. | Carries `review-context.sh` and `review-file-bug.sh`, a first prep script, and the 9,000-character step bound. |

### Rules both touch

- **The subagent policy.** This design deletes the dispatch body's "No fan-out"
  line with its script and writes no subagent text of its own. U1.5 then
  rewrites one place, `mol-review`'s hard rule, and adds what the quorum lanes
  lack.
- **The review's mechanics.** This design turns the pins, the diff, the
  worktree and the rig's guidance into script calls. U1.6's prep script
  packages what is left of the review step. Built on `review-frame.sh`, as verbs
  of it or calls to it, it reads the record rather than deriving the values
  again.
- **Generic in the pack, specific in the rig.** The live `--extension` read is
  the delivery half of U1.7.
- **The step-size bound.** This design shortens every review step, because the
  re-derivation blocks become script calls. The review step is 8,915
  characters today, against #1217's bound of 9,000.

### Recommendation for the sitting

This convoy's build lands first. It changes structure and no judgment, so the
method units then edit content under headings that will not move again. U1.6
builds on the record instead of re-deriving it, and U1.5 has one rule to relax.
The other order costs this build a reshaping of a skill those units have just
rewritten, and leaves a prep script deriving the values the record replaces.
#1217 targets main, so whichever of it and this convoy's graduation lands
second merges the other in.

## 10. The breakdown

The build is two beads onto integration/tk-gaklsnk, in order. The
implementation child, tk-nuctjl8, builds unit A. When it starts, it files unit
B as its sibling in the convoy, with `target` stamped to the integration
branch, blocked on itself and armed with a deferred dispatch, so unit B starts
when unit A lands.

### Unit A: every reader takes the rig's review guidance live, and every rig gets every pack check

- `review-checks.sh` takes on the layered index: the pack's rows beside the
  script, the rig's on origin's default branch. It gains the refresh, `--check`,
  `--show`, `--extension` and the degraded bad row. `--at` and the working-tree
  read retire, and the `method` key is ignored.
- Every reader in section 6 moves, `review-dispatch-body.sh`'s two reads
  included, so the dispatch body reads live until unit B deletes it.
- signoff.sh validates `--add-gates` against the effective index. Its
  scratch-file read and its no-index arm go.
- The triage skill reads its menu with `review-checks.sh --show` through
  `scripts-dir`, and its no-index fallback goes.
- `review-checks.toml` loses its `method` keys. Its header states the layered
  index and the live rule, and points at the configuration that holds the
  baseline.
- Tests 5 and 6 of section 8, and the reader half of test 7.

It touches every gating reader, so it lands alone, reviewable as one change to
what every transition reads.

### Unit B: the review bead is data, the frame reads it, and each check is one skill

- gate-ensure.sh writes the record (section 2), requires a head, writes the fixed
  description, and stops calling `review-dispatch-body.sh`.
- `review-frame.sh` and its test.
- `mol-review` and the quorum read the record and load the skill named from the
  check (sections 1 and 3).
- The five check skills take the uniform shape and read values through the
  frame, and `skills/specialist-stance/SKILL.md` is new.
- `review-dispatch-body.sh`, its test, its component-model row,
  `pr-facts.test.sh`'s stub and `review-method.test.sh` go. Tests 1 to 4 of
  section 8 land, with the list half of test 7, which can hold only once the
  dispatch body's case arm is gone. The formula-block tests are re-pointed, and
  the lint case gets its fixture.

It depends on unit A for `--check` and `--extension`.

### The change at graduation

Nothing on the integration branch runs. The design takes effect when the convoy
graduates to main and the rig checkout fast-forwards, which moves gate-ensure,
the formulas and the skills in one step.

A review poured before then keeps the step text it was poured with. That text
reads the description and the metadata the bead was dispatched with, so the
review finishes under the old frame. The skills it loads from the catalog are
the new ones. They read the keys an old bead already carries through
`review-frame.sh pin`, which refuses only a missing value it was asked for, so
an old bead's lack of `review_formula` stops nothing. A review stranded across
the change is slung again by the new gate-ensure, whose stranded arm writes the
whole record first.

## What this design does not change

- No check's judgment. Sentences move between headings, and how a block reads a
  value changes.
- The formula names `mol-review` and `mol-review-quorum-signoff`, which the
  board, the witness, orphan disposal, gate-ensure and the learning loop key on.
- How a formula reaches the pack's scripts (`lease-heartbeat.sh`,
  `review-workspace.sh`, `signoff.sh`, `step-close.sh`, `review-checks.sh`, and
  the new `review-frame.sh` alike): through the candidate loop, until
  tk-60i7nl6 lands.
- The default `check_set`, and who stamps it (section 5).
- `findings.md`, `findings.json`, signoff.sh's verdicts and what it writes, and
  the validator.
