---
name: A/B probe of the guidance rule, tk-9t1wmrd
description: Read it to check the numbers in tk-u5ss4qv's summary, to see which parts of the rule reach a reviewer and which reach an author, or to re-run the probe on a later wording.
---

# A/B probe of the guidance rule

The proposal says a written standard is needed because the city's review passed
the diffs the operator corrected. This measures that claim with the old text and
the filed text, on those diffs. It also measures a conflict the proposal did not
weigh: `AGENTS.md` sends a rule that binds only gc-toolkit's own work to "the doc
or the check that owns it", and the entry says "never in a docs page".

The filed text catches a docs-page rubric, a command replaced by a pointer, and a
choice with no listing command. No run flagged any of those under the old text.
It does not catch either case the operator objected to as a favored option or a
number. It moves authors only when nothing pushes against the command.

On codex, which runs the reviews, the filed text also blocks rules only this
repository binds, in every run, until `AGENTS.md` says a docs page is a right
place for them. That paragraph leaves the rubric and the pointer blocked.

## What reviewers did

Each cell counts the runs with a blocking finding on what the new entry covers.
The old text has no such entry, so its column shows whether any other entry caught
the problem, and none did. It approved R1, R2, R3 and R9 outright in every run.

| Case | Source | Old text | Filed text |
|---|---|---|---|
| R1, a routing rubric moved into a docs page | #1269, comment 4290656675 | 0 of 3 | 3 of 3 |
| R2, an exact command replaced by a pointer to a skill | #1269, comment 4286682920 | 0 of 3 | 8 of 9 |
| R8, "through the right mol" with no listing command | #259, comment 3742486901 | 0 of 3 | 3 of 3 |
| R3, prompt bullets that single out one formula | #1269, comment 4286636653 | 0 of 3 | 0 of 3 |
| R4, a line count standing in for scope | #944, comment 4167767108 | 0 of 3 | 0 of 3 on the number; 3 of 3 call the page guidance in a docs page |
| R9, a bullet that names one formula among the routes | the bullet #936 added | 0 of 3 | 0 of 3 on the favored option; 3 of 3 on the missing command for its stamp |
| R5, a rig's guidance page, which a review formula prints | `docs/review-demo.md` as #1266 added it | 0 of 3 | 0 of 6 on its location; 6 of 6 on a missing command |
| R6, a convention for authoring skills | `docs/skills.md` lines this effort adds, at 2a3bd983b | 0 of 3 | 2 of 3 on its location |
| R7, control: a table of facts | `docs/state-machine.md` as b3034bf9e changed it | 0 of 3 | 0 of 3 |

Other entries block R4, R5, R7 and R8 on both texts, for counted sets, em dashes
and a documentation-only diff, the last because R7 shows one file of a larger
commit. One old and one filed R6 run also block on the entry about load-bearing
claims. The cells count only what the new entry covers.

R5 first looked like the conflict: the pack's own review formula prints that page
to the reviewer. No run called its location a violation, with or without a line
quoting `review-checks.toml` on what the page is (three runs each, R5 and R5b).

R3's three runs say the entry lets a skill carry the guidance. R2's approving run
says the same, which reads a pointer to a skill as meeting "give the exact command
to run there". The operator's comment on that hunk says it does not: "This should
have an example or exact command to run."

## What authors did

| Case | Task | What was counted | Old text | Filed text |
|---|---|---|---|---|
| A2 | Rewrite a step so it does not duplicate the `records` skill, the real failure on #1269 | the step gives the command | 0 of 3 | 0 of 3 |
| A3 | Shorten two prompt bullets now the `work` skill exists, the real failure on #1269 | the bullets give `gc formula list` | 0 of 3 | 0 of 3 |
| A3 | | the bullets still name `mol-design-convoy` | 3 of 3 | 3 of 3 |
| A4 | Write a step, with the command in the task and nothing against keeping it | the step gives the command | 3 of 3 | 3 of 3 |
| A5 | Write a paragraph on routing, with `gc formula list` in the task | it gives `gc formula list` | 3 of 3 | 3 of 3 |
| A5 | | it gives a command to send the bead, `gc sling` | 0 of 3 | 3 of 3 |
| A1 | Move a rubric out of the prompts, with a skill, a formula description and a docs page on offer | the rubric lands in the `work` skill | 3 of 3 | 3 of 3 |

A2 and A3 carry the pressure the proposal names: avoiding duplication and saving
prompt weight. The old text reproduces the real failure there, so those nulls are
real. A1's old text does not reproduce the failure, so A1 shows nothing. The task
named the skill as a surface, which the real author had to find. A5's filed runs
also write `bd create`, which the task did not give and which the pack's prompts
spell `gc bd create`. An author with tools can check that, and these calls have
none.

## Where the carve-out goes

Each cell counts the runs with a blocking finding under the new entry, except R4,
which counts findings that call the page guidance in a docs page.

| Wording | R6, skills convention | R1, rubric | R2, pointer | R8, list | R4, epics page |
|---|---|---|---|---|---|
| Filed | 2 of 3 | 3 of 3 | 8 of 9 | 3 of 3 | 3 of 3 |
| A sentence in `AGENTS.md` | 0 of 3 | 3 of 3 | 6 of 9 | 3 of 3 | 3 of 3 |
| A sentence in the entry | 0 of 3 | 3 of 3 | 3 of 9 | 3 of 3 | 3 of 3 |
| A clause for a page a formula prints | 1 of 3 | 3 of 3 | not run | not run | not run |

The wordings:

- In `AGENTS.md`, after "the doc or the check that owns it": ", and a docs page is
  a right place for such a rule even though the polecats' standard keeps other
  guidance for an agent out of docs pages". The branch carries these words as a
  paragraph of their own after the file's opening paragraph, which keeps its
  merge with #1365's rewrite of that paragraph clean.
- In the entry, at its end: "A repository's own conventions for changing it are
  not this guidance, and stay in the doc or check that owns them." It is not on
  the branch.
- In the entry, for "never in a docs page": "or in a page a formula prints to it
  at that moment, never in a docs page it is left to open". It is not on the
  branch. It solves a problem R5 shows reviewers do not have, so it is not
  offered.

The `AGENTS.md` sentence holds R6 without touching any prompt. One R6 run under the
filed text cleared the lines by citing `AGENTS.md` as it stands, so that file is
already what a reviewer weighs. Under the new sentence, all three R1 runs say the
allowance does not apply, because that rubric is routing guidance for every rig.
R2 reads 6 of 9 under that sentence and 3 of 9 under the sentence in the entry,
which passes R6 too. Every approving R2 run under either sentence says the step's
pointer to a skill meets the entry, the reason R2's one approving filed run gives,
and none cites the sentence. So nothing here says why the counts differ, and nine
runs a side is a caution rather than a measurement.

## On codex

Every routed review runs on codex, and the tables above ran on Claude. These cells
run the reviewer arm on codex. Each counts the runs with a blocking finding on
where the guidance lives, except R2's, which count the missing command.

| Case | Old text | Filed text | With the `AGENTS.md` paragraph |
|---|---|---|---|
| R1, a routing rubric moved into a docs page | 0 of 3 | 3 of 3 | 3 of 3 |
| R2, an exact command replaced by a pointer to a skill | 0 of 3 | 3 of 3 | 3 of 3 |
| R6, a convention for authoring skills | 0 of 3 | 3 of 3 | 0 of 3 |
| R10, this effort's lines in `docs/review-arch.md` and `docs/review-triage.md` | 0 of 3 | 3 of 3 | 0 of 3 |
| R10b, those lines, with a purpose line saying the review formula prints the page | not run | 0 of 3 | 0 of 3 |
| R5, a rig's guidance page, with that purpose line | not run | 0 of 3 | 0 of 3 |

The paragraph holds R6 and R10 and leaves R1 and R2 blocked. All three R1 runs
under it say it does not reach a rubric that routes work in every rig. R2 stays at
3 of 3, where Claude's count went from 8 of 9 to 6 of 9. No codex run under the old
or the filed text cites `AGENTS.md`.

R10 and R10b show the same diff, and only the purpose line differs. R10b's says the
page is gc-toolkit's own guidance, which the review formula prints to the reviewer,
and that takes the filed text from 3 of 3 to 0 of 3. One of those three runs gives
that as its reason, and the other two give none. R5's purpose line says the same,
so R5 does not show what a page with no such line draws on codex.

On Claude, on these arms, R1 reads 3 of 3, R6 0 of 3 and R10 0 of 3 with the
paragraph. Under the filed text R10 reads 0 of 3 there, and all three runs cite
`AGENTS.md` as it stands. So the providers differ on these lines with no paragraph,
3 of 3 against 0 of 3, and agree once it is there.

Other entries also block, and the cells leave them out. R5 draws a counted set and
a missing command in every run of both arms. A claim the diff cannot show draws two
old R6 runs and one R6 run with the paragraph, on what its test suite checks, and
all three old R10 runs and one R10 run with the paragraph, on "the list its author
saw at self-review".

The arm and the purpose lines are rebuilt from the Method section, because the
first run's scratch is gone, so these cells and the tables above come from different
arms. The fragments are at c83311fa1. The old arm is that arm with this entry's
anchor and text taken out, and the paragraph arm adds the paragraph `AGENTS.md`
carries. R10 is `git diff origin/main...c83311fa1` on the two pages. Every codex call
was `codex exec --ephemeral --skip-git-repo-check --ignore-rules -s read-only -C
<empty directory> -m gpt-6.1-sol -c 'model_reasoning_effort="medium"' -c
developer_instructions=<arm> --json`, with the case on stdin and `OPENAI_API_KEY`,
`GH_TOKEN`, `GITHUB_TOKEN`, `GC_*` and `BEADS_*` unset. The 48 calls read 952k input
tokens, 622k of them cached. The 12 Claude calls use the Method section's command
and cost $0.68. I read the codex outputs whole, and each Claude output to the
sentence where it clears or blocks the lines.

## Method

Every call was `claude -p --model claude-opus-5-5 --tools "" --max-turns 1
--no-session-persistence --output-format json --system-prompt "<arm>"`, from an
empty directory, with the case on stdin and `GC_*` and `BEADS_*` unset. The 144
calls cost $5.03.

A reviewer arm held a role line, the whole of `AGENTS.md`, the Work-quality
standards dimension cut from `skills/review-correctness/SKILL.md`, the work-quality
fragments (base, human, polecats, system) and the exemplar corpus, then asked for
each violation with the entry's words and a closing verdict line. The old arm took
its fragment from the commit before the entry, and the filed arm from the commit
that adds it. An author arm held a role line, `AGENTS.md` and the same files, and
asked for the text to commit.

A reviewer case held the change's stated purpose and a real diff. R1, R2 and R3
are the hunk the comment sits on, from the PR's own commit. R4's commit is gone, so
it uses the comment's `diff_hunk`, which stops mid-sentence at the line the operator
commented on. R5, R6 and R7 come from the commit each row names. R8 and R9 show one
paragraph as added lines. I read the outputs behind every cell, the first 220 to
700 characters of each where the verdict and the finding sit, and the whole of the
author runs A2 to A5.

## Limits

- A real review has the worktree and can open the skill a pointer names. These
  calls see only the diff, so R2's and R3's reviewers could not check the skills.
- A real author has a far longer prompt, tools and the file's context, so the
  author half shows a direction only.
- Three runs a cell is thin. R2 went from 3 of 3 to 8 of 9 when widened.
- A purpose line moved R10 on codex, so a real review of such a page can read
  either way. No run here shows which.
- The correctness check reads the fragments from the installed pack, so it holds
  the effort's own PR to the entry only once the entry is installed.
