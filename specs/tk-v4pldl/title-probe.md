---
name: Probe of the subject-line wording
description: What the Subject lines section, submit step 4c and gc-toolkit's scope rule make an author write, and what the correctness check's title bullet makes a reviewer do, measured on merged PRs. Read it to check the numbers in PR #1375's summary.
---

# Probe of the subject-line wording

The operator's ruling on PR #1375 sent it back before review, to add a scope
decision, a what-not-how clause and a reviewer's check on titles, and asked for a
probe with an arm whose author carries a rig's own rules. This records that probe.
It is a cut-down prompt with no tools and no session history, so it shows a
direction, not what a live polecat will write.

Every run in [Authors](#authors) and [Reviewers](#reviewers) had the rules in front
of it. The operator's review then moved them out of the prompt, and
[The rules read from a skill](#the-rules-read-from-a-skill) measures them where they
now are.

## Authors

### Method

`claude -p` on `claude-opus-5-5`, with no tools, three runs per cell, from an empty
directory with no settings or memory. Each run was asked for exactly one
`ANCHOR_TITLE="..."` line, and each answer went through the real `cc_title`. An
arm's text was cut from the tree by `tomllib`, and the run checked it against
`HEAD` first. Authors' text was last changed at 166f61d4d, and the final run was
on that commit.

The sixteen cases are real merged PRs. Each gave the anchor's stored title, its
kind, the branch's commit subjects and its `pr_summary`, cut to 2,500 characters.
Eight came from this PR's first round: #1361, #1358, #1344, #1336, #1322, #1362,
#1333 and #1298. Only two of those have a size table led by a named subsystem, so
the other eight were picked by rule: for each named subsystem that leads a size
table with at least half of its net lines, the most recent such PR on main. Those
are #1371, #1377, #1378, #1370, #1351, #1320, #1343 and #1288. No case was dropped
or re-rolled after a run.

The arms:

- **Main's step 4c.** Main's step text alone.
- **This wording, no rig rules.** The doctrine's Subject lines section and this
  branch's step 4c.
- **This repository's AGENTS.md and size table.** The same, plus this repository's
  whole `AGENTS.md`, and the case's `tools/measure.sh --pr` output handed to the
  author as if it had run it. This is the arm a gc-toolkit author is closest to.
- **A rig's own rules.** The same as the second arm, plus the rules below, which
  were written for this probe and conflict with the doctrine in three ways. They
  allow fewer types, require a scope on every title, and start the words with a
  capital letter.

```markdown
# Commit rules for this repository

Every commit subject and PR title follows these rules.

Types: use only `feat`, `fix`, `docs` and `chore`.

Scopes: every title carries exactly one of these.

- `agents`: prompts, formula steps and skills
- `scripts`: shell scripts and their tests
- `board`: the web board and its services
- `ci`: CI workflows and developer tooling
- `records`: docs and design records

Start the words after the colon with a capital letter.
```

### Results

| Arm | Titles | Carrying a scope | Median length | Longest | Over 72 | Scoped titles: median, longest |
|---|---:|---:|---:|---:|---:|---|
| Main's step 4c, no rig rules | 48 | 0 | 132 | 169 | 45 | none |
| This wording, no rig rules | 48 | 0 | 65 | 72 | 0 | none |
| This wording, this repository's AGENTS.md and size table | 48 | 30 | 66 | 73 | 3 | 67.5, 73, 3 over 72 |
| This wording, a rig's own rules | 48 | 48 | 68 | 75 | 1 | 68, 75, 1 over 72 |

The types:

- Main's step 4c: `chore` 27, `fix` 21.
- No rig rules: `fix` 18, `docs` 6, `feat` 6, `refactor` 6, `security` 6, `build` 3, `test` 3.
- This repository: `fix` 18, `build` 6, `docs` 6, `refactor` 6, `security` 6, `feat` 3, `test` 3.
- A rig's own rules: `fix` 27, `chore` 9, `docs` 6, `feat` 6.

**A rig's own rules come first.** On every conflict the rig's rules won. All
48 titles used one of the rig's four types, where the second arm used seven.
All 48 carried a scope from the rig's list, and all 48 started the words
with a capital letter.

**This repository's scope rule.** The 30 scoped titles are all three runs of the
ten cases whose table is led by a named subsystem holding at least half of its net
lines, and each took that first row. The other 18 are the six cases with no table
or led by `shared`, and none of them wrote a scope. A title the author cannot read
a scope for keeps its type: `refactor:` for #1361 and `docs:` for #1298.

**The limit.** Scoped titles do not always fit 72. In this repository's arm 3 of
30 ran one character over, at 73, and in the rig's arm 1 of 48 reached 75. The
author counts by eye and nothing checks it. With the ` (tk-xxxxxxx)` and ` (#1375)`
the composer adds, 21 characters, a title of 72 reaches 93, which passes a
100-character check, and 75 reaches 96. A child bead's longer id adds up to three.

**A rule the sixteen cases never reached.** The scope rule says to write none when
no one row holds most of the change. Three more PRs whose first row holds under
half of the table's net lines ran on this repository's arm. 4 of 9 titles
carried no scope: all three of #1379, whose first row holds 31 percent, one of
three of #1347, at 36 percent, and none of #1353, at 44 percent. So that branch of
the rule is a judgment an author can make either way. These titles are not in the
table above.

**What it did to a real name.** #1362's diff doubles every `#` so that text in a
tmux menu cannot run as a shell command. With "name what changes rather than how"
as a clause and no example, 6 of 9 titles named the escaping on the first wording
and 8 of 9 on the second. With one contrasting example added to the section, 9 of 9
named what changes, as in `security(visit):
stop tmux pickers running commands from menu text`. Reading the other cases side by
side, their titles stayed as good. The second arm's and the rig's types did not
move, and in this repository's arm #1344 went from `feat` to `build` in all three
runs. That is one case, and it is why the section carries the contrast.

**What the first run found.** With the first wording, 14 of 48 titles in the
second arm carried a scope of the author's own, under six names (`ci`,
`architecture`, `helm`, `gc-helm`, `gctk`, `demo`), though the section said to write
none. After the section said never to coin a name and step 4c tied the scope to a
rig's rules naming scopes, 0 of 48 did.

**Controls.** A title that already fits was kept in 12 of 12 runs: two titles in
the second arm and two in this repository's arm, one of those scoped. An earlier
control's scoped title was 74 characters, so it did not fit, and the runs set it
again or shortened it. A title of 65 replaced it.

**How the scope lands across recent work.** Of the last 70 PRs merged on main
when this ran, 44 have a first row that names a subsystem and holds at least
half of the table's net lines, 6 have a named first row under
half, 13 are led by `shared` or `unplaced`, and 7 have no
table. A subsystem is where the tool files a path, so a name can read oddly: a tmux
picker fix is `visit`.

The whole final run cost $2.17 for 204 calls and took about two and a half
minutes at a load near 60.

### Every title from the final run


**#1361**, merged as: chore: run_lib map takes no scope, since no caller asks it for every run

Size table: shared | -7 | -6

```
new  refactor: remove the all option from run-lib.sh's map verb
new  refactor: remove the unused all option from run-lib's map verb
new  refactor: remove the unused all option from run-lib's map verb
repo refactor: remove the unused all option from run-lib.sh's map verb
repo refactor: remove the unused all option from run-lib's map verb
repo refactor: remove the all option from run-lib's map verb
rig  chore(scripts): Remove the all option from run-lib.sh's map verb
rig  chore(scripts): Remove the unused all option from the run-lib map verb
rig  chore(scripts): Remove the unused all option from run-lib.sh's map verb
```

**#1358**, merged as: chore: CI's actions are pinned to commit SHAs and run on Node 24, and the suite passes on the Ubuntu 26 image ubuntu-latest moves to

Size table: no table

```
new  build: pin CI's actions to commit SHAs and run them on Node 24
new  build: pin CI actions to commit SHAs on Node 24 and enforce the pins
new  build: pin CI's actions to commit SHAs and run them on Node 24
repo build: pin CI's actions to commit SHAs on their Node 24 releases
repo build: pin CI actions to commit SHAs on their Node 24 releases
repo build: pin CI actions to commit SHAs on their Node 24 majors
rig  chore(ci): Pin CI actions to commit SHAs on their Node 24 releases
rig  chore(ci): Pin CI's actions to commit SHAs on their Node 24 releases
rig  chore(ci): Pin CI's actions to Node 24 commit SHAs and check the pins
```

**#1344**, merged as: chore: Every gc-toolkit PR shows its size change, computed from git, naming lines it adds to code the deletion plan retires

Size table: no table

```
new  feat: show each PR's size change in a comment from gc-toolkit's CI
new  feat: show each PR's size change in a comment CI keeps current
new  feat: post each gc-toolkit PR's size change as a CI comment
repo build: post a size comment on each PR from CI
repo build: post each PR's size change as a comment computed from git
repo build: post each PR's size change as a comment from CI
rig  feat(ci): Post each PR's size change as a comment computed from git
rig  feat(ci): Post each PR's size change in a comment CI keeps current
rig  feat(ci): Post each PR's size change as a comment computed from git
```

**#1336**, merged as: chore: gc-helm engage waits for its sitting to start and then attaches, instead of giving up at 120 seconds

Size table: visit | +66 | +138

```
new  fix: make gc-helm engage wait for its sitting to start, then attach
new  fix: make gc-helm engage wait for its sitting to start, then attach
new  fix: make gc-helm engage wait for its sitting to start, then attach
repo fix(visit): make engage wait for its sitting to start, then attach
repo fix(visit): make gc-helm engage wait for its sitting and then attach
repo fix(visit): make gc-helm engage wait for its sitting and then attach
rig  fix(scripts): Make gc-helm engage wait for its sitting, then attach
rig  fix(scripts): Make gc-helm engage wait for its sitting, then attach
rig  fix(scripts): Make gc-helm engage wait for its sitting and then attach
```

**#1322**, merged as: chore: docs/architecture.md says what a review reads from the installed pack and what from the rig under review, and at which commit

Size table: no table

```
new  docs: record what a review reads from the pack, the rig and dispatch
new  docs: record what a review reads from the pack, rig and dispatch
new  docs: record what a review reads from the pack, the rig and dispatch
repo docs: record what a review reads from the pack, the rig and its dispatch
repo docs: record what a review reads from the pack, the rig and dispatch
repo docs: record what a review reads from the pack, the rig and its dispatch
rig  docs(records): Record where a review's pieces come from in the architecture
rig  docs(records): Record where a review's pieces come from
rig  docs(records): Record where a review's pieces come from
```

**#1362**, merged as: fix: The tmux pickers double every # in the bead, session and pane text they put in a menu, so #(...) in that text shows as written instead of running as a shell command

Size table: visit | +25 | +186

```
new  security: stop tmux pickers running shell commands from menu text
new  security: keep tmux pickers from running commands in menu text
new  security: stop the tmux pickers expanding # formats in menu text
repo security(visit): stop tmux pickers running commands from menu text
repo security(visit): stop tmux pickers running #(...) in their menu text
repo security(visit): stop tmux pickers running menu text as shell commands
rig  fix(scripts): Stop tmux pickers expanding formats in menu text
rig  fix(scripts): Stop tmux pickers expanding formats in menu text
rig  fix(scripts): Stop tmux pickers expanding formats in menu text
```

**#1333**, merged as: chore: Delete four tools nothing runs: the surface census, the per-polecat metrics report, the reachability fixture and the one-shot approval migration

Size table: shared | -323 | -108; review | -144 | -132

```
new  refactor: delete four tools nothing runs
new  refactor: delete four tools nothing runs
new  refactor: delete four tools nothing runs
repo refactor: delete four tools that nothing runs
repo refactor: delete four tools that nothing runs
repo refactor: delete four tools nothing runs
rig  chore(scripts): Delete four tools that nothing runs
rig  chore(scripts): Delete four tools nothing runs
rig  chore(scripts): Delete four tools that nothing runs
```

**#1298**, merged as: chore: Design: a PR is one reviewable unit, carried to main by one landing bead per integration branch, deleting gc-toolkit's convoy landing code

Size table: no table

```
new  docs: design a PR model with one landing bead per integration branch
new  docs: design a PR model where one landing bead carries a branch to main
new  docs: design the PR model of one landing bead per integration branch
repo docs: design the one-bead PR model and its convoy code deletions
repo docs: design the one-bead PR model and its convoy code deletions
repo docs: design the one-bead PR model and the convoy code it deletes
rig  docs(records): Design the PR model of one landing bead per branch
rig  docs(records): Design one landing bead per integration branch as its PR
rig  docs(records): Design the one-bead PR model and the code it deletes
```

**#1371**, merged as: chore: A demo capture cannot reach the live city, so a screenshot or video on a pull request shows fixture data only

Size table: review | +450 | +559; doctor | +7 | +9

```
new  security: sandbox demo captures away from the live city
new  security: keep demo captures from reaching the live city
new  security: run demo captures in a sandbox cut off from the live city
repo security(review): keep live city data out of demo captures
repo security(review): keep live city data out of demo captures
repo security(review): keep live city data out of demo captures
rig  fix(scripts): Keep live city data out of demo captures
rig  fix(scripts): Run every demo capture in a sandbox cut off from the city
rig  fix(scripts): Keep live city data out of demo captures
```

**#1377**, merged as: fix: Self-review counts a setup or build note naming the repo's own command when the step declares none

Size table: work | +3 | +51; config | +2 | 0

```
new  fix: count a self-review's setup and build note with no command declared
new  fix: count a setup or build note when the step declares no command
new  fix: count a setup or build note when the step declares no command
repo fix(work): accept a setup or build note when the step declares no command
repo fix(work): count a setup or build note when the step declares no command
repo fix(work): accept a setup or build note when the step declares no command
rig  fix(scripts): Count a setup or build note when no command is declared
rig  fix(scripts): Count a setup or build note naming undeclared commands
rig  fix(scripts): Count a setup or build note when the step declares none
```

**#1378**, merged as: fix: check-session-store-scope reads the running process from the kernel's record where there is no /proc, and warns once when it can read no pane at all

Size table: doctor | +86 | +392

```
new  fix: read running agents' environments on macOS in the store scope check
new  fix: make check-session-store-scope read running processes on macOS
new  fix: make check-session-store-scope read running agents on macOS
repo fix(doctor): read what a running agent holds on hosts with no /proc
repo fix(doctor): read running agents' store scope on hosts with no /proc
repo fix(doctor): read what a running agent holds on hosts with no /proc
rig  fix(scripts): Make the session store check read running agents on macOS
rig  fix(scripts): Make the session store check read running agents on macOS
rig  fix(scripts): Make the session store check read running agents on macOS
```

**#1370**, merged as: fix: A SIGTERM that misses a long sleep no longer holds gctk rig's relay tests open to the grace deadline, so TestRunStopWaitsForAChildThatIsStillStopping stops failing under load

Size table: gctk | 0 | +13

```
new  test: remove the SIGTERM races from gctk's stop tests
new  test: remove the SIGTERM races from gctk's stop tests
new  test: keep gctk's stop tests from racing SIGTERM against their commands
repo test(gctk): close the races that fail stop tests under load
repo test(gctk): remove two SIGTERM races from the stop tests
repo test(gctk): close the races that fail stop tests under load
rig  fix(ci): Keep gctk's stop tests from failing at random under load
rig  fix(ci): Keep gctk's stop tests from failing at random under load
rig  fix(ci): Keep gctk's stop tests from failing at random under load
```

**#1351**, merged as: fix: The helm board counts an epic's children by what holds each one, so a child waiting its turn reads queued and a pull request in review owes no disposition

Size table: board | +691 | +690

```
new  fix: count helm board beads by what holds them, not their markers
new  fix: read what holds each helm board bead from its graph and work
new  fix: read what holds each helm board bead from its graph and work
repo fix(board): read what holds each open bead from its graph and live work
repo fix(board): count held beads by what holds them, not their markers
repo fix(board): read what holds each open bead from its graph and live work
rig  fix(board): Count each open bead by what holds it, not by its markers
rig  fix(board): Count open beads by what holds them, not by their markers
rig  fix(board): Show what holds each open bead, not the markers it carries
```

**#1320**, merged as: fix: A rejected graduation is rebuilt on an ordinary child bead that gc sling pours, and its landing anchors the convoy

Size table: merge | +268 | +716; work | +26 | +29; shared | +3 | 0; review | +2 | 0; doctrine | +1 | 0

```
new  fix: rebuild a rejected graduation on a child bead instead of its convoy
new  fix: rebuild a rejected graduation on a child bead, not the convoy
new  fix: rebuild a rejected graduation on a child bead instead of its convoy
repo fix(merge): run a rejected graduation's rebuild on a convoy's child bead
repo fix(merge): rebuild a rejected graduation on a child of its convoy
repo fix(merge): rebuild a rejected graduation on a child, not its convoy
rig  fix(scripts): Run a rejected graduation's rebuild on a child bead
rig  fix(scripts): Rebuild a rejected graduation on a child of its convoy
rig  fix(scripts): Rebuild a rejected graduation on a child, not its convoy
```

**#1343**, merged as: fix: The refinery, witness and deacon restart at a turn's end or before their next prompt once their prompt or patrol formula changes on disk

Size table: patrol | 0 | +249; config | +154 | 0; doctor | +38 | +23

```
new  fix: restart a patrol session once its prompt or formula changes
new  fix: restart a patrol session once its prompt or formula changes
new  fix: restart patrol sessions when their prompt or formula changes
repo fix(patrol): restart a session whose prompt or formula changed on disk
repo fix(patrol): restart a session whose prompt or formula changed on disk
repo fix(patrol): restart a session once its prompt or formula changes
rig  fix(scripts): Restart a patrol session whose prompt or formula changed
rig  fix(scripts): Restart a patrol session whose prompt or formula changes
rig  fix(scripts): Restart a patrol session whose prompt or formula changed
```

**#1288**, merged as: chore: outside feedback capture: review feedback from outside the city becomes condensed observations the distiller reads as a set

Size table: feedback | +835 | +1111; merge | +8 | +23; doctrine | +1 | 0; shared | +1 | 0

```
new  feat: capture outside review feedback as condensed observations
new  feat: capture outside review feedback as condensed observations
new  feat: capture outside review feedback as condensed observations
repo feat(feedback): condense outside review feedback into observations
repo feat(feedback): capture outside review feedback as condensed observations
repo feat(feedback): capture outside review feedback as observations
rig  feat(scripts): Turn outside review feedback into condensed observations
rig  feat(scripts): Capture outside review feedback as condensed observations
rig  feat(scripts): Capture outside review feedback as condensed observations
```

## Reviewers

### Method

This PR's own reviews ran on the codex pool, so this ran on `codex exec` at
`gpt-6.1-sol`, medium effort, in an empty read-only directory, three runs per cell.
Each run got the whole correctness method. The new arm also got the Subject lines
section, because the review pool's prompt carried it when this ran. The message held
the bead's description, the PR's title and summary, and the whole diff, with the
title varied over the same two real PRs, #1336 (a fix) and #1361 (removing an unused
option).

A count below is the runs with a finding whose locus names the title, at that
grade. Verdicts are not counted, because other findings on the diff decided some of
them. Each output was also read by eye.

### Results

| The title | Main's bullet | First wording | Final wording |
|---|---|---|---|
| `chore:` and the filed words, on the fix (its real merged title) | none | 3 blocking | 3 blocking |
| `fix: make gc-helm engage attach at once instead of waiting for its sitting` | 2 blocking, 1 P2 | 3 blocking | 3 blocking |
| `fix(visit): make gc-helm engage wait for its sitting to start, then attach` | none | none | none |
| `fix: improve gc-helm engage` | none | 3 P2 | 3 P2 |
| `feat: make gc-helm engage wait for its sitting to start, then attach` | none | 3 blocking | none |
| `chore:` and the filed words, on removing an unused option (its real merged title) | none | 3 blocking | 3 blocking |
| `refactor: remove the unused all option from run-lib.sh's map verb` | none | 2 blocking | 1 blocking |

The first wording caught what it was for and also over-fired, asking for `feat` on
a fair `refactor` and for `fix` on an arguable `feat`. The final wording adds that
`chore` is false on a diff another type describes, and that a type the diff could
fairly take is the author's call. That took the arguable `feat` to none. One run in
three still blocks the fair `refactor`, reading its row's "changes no behavior"
against an option a caller could once pass, so a rework round can still go on a
fair name. Under main's bullet all three runs of the false words named the title,
two of them inside a finding about the help text.

Main's "understates the scope" is gone, and these runs do not test it: a title that
understates a diff is now one whose words misname it.

## The rules read from a skill

The operator's review on PR #1375 objected to where the rules load, so they left
the polecat prompt and `AGENTS.md`. The Subject lines section became the skill
`gc-toolkit.subject-lines`, and this repository's scope rule became
`docs/subject-lines.md`, which the skill sends an author to. The sections above
all had the rules in front of the author and the reviewer, so none of them shows
that the rules still arrive. An author now gets them only by loading them. This
section measures that, on commit b17c75dc6.

### Method

- **The prompt.** Each run's first message is the whole rendered prompt from
  `generated/seed-audit/agents/polecat.md`, as a pool session receives it, with
  the Subject lines section gone, followed by the real step text and the case.
  Codex runs get `polecat-codex.md`.
- **The skills.** Each fixture holds a polecat's whole catalog by catalog name, the
  core pack's links and every gc-toolkit skill, so a run has to find this one among
  them.
- **Claude.** `claude -p --model claude-opus-5-5 --tools "Skill,Read,Grep,Glob,Bash"
  --setting-sources project --strict-mcp-config --max-turns 6
  --no-session-persistence --output-format stream-json --verbose`, with the first
  message on stdin, every `GC_*`, `BEADS_*` and `CLAUDE*` variable unset, and
  `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`. Claude Code 2.1.316.
- **Codex.** `codex exec --ephemeral --skip-git-repo-check --ignore-rules -s
  read-only -m gpt-6.1-sol -c 'model_reasoning_effort="medium"' --json`, with
  `.agents/skills` in the fixture. A load is a command that reads the skill's
  `SKILL.md`, since Codex has no skill tool. codex-cli 0.164.0.
- **Nothing was sent.** On Claude, a Bash call with no allow rule is refused unless
  it only reads. Runs tried `gc` 32 times and `bd` 7 times, `gc hook --claim` among
  them, and each came back refused. On Codex the sandbox is read-only. Afterwards the
  worktree and the bead this work ran under were unchanged.

Three small git repositories stand in for three rigs:

- **This repository.** `AGENTS.md` at this commit, which no longer has the scope
  rule, and `docs/subject-lines.md`. The case hands over the `tools/measure.sh
  --pr` output, as the earlier arm did.
- **No rig rules.** A one-line README and nothing else.
- **A rig's own rules.** The rules above, at `docs/commit-rules.md`, a name the
  skill does not say, with one line in `CLAUDE.md` and `AGENTS.md` naming that page.
  So a run has to follow what the rig says rather than a path it was given.

The cases are the sixteen merged PRs above, with the same facts. Each run ends on
exactly the one line it set. One run per cell on Claude, because a miss is what this
looks for and the wording is the wording already measured three times a cell.

### At step 4c

| Provider and rig | Runs | Skill loaded before the title | Read the rig's page | Titles with a scope | Median length | Longest | Over 72 |
|---|---:|---:|---:|---:|---:|---:|---:|
| Claude, this repository | 16 | 16 | 16 | 10 | 67 | 72 | 0 |
| Claude, no rig rules | 16 | 16 | none to read | 0 | 66.5 | 72 | 0 |
| Claude, a rig's own rules | 16 | 16 | 16 | 16 | 68 | 72 | 0 |
| Codex, this repository | 6 | 6 | 6 | 4 | 60.5 | 67 | 0 |
| Codex, no rig rules | 3 | 3 | none to read | 0 | 58 | 60 | 0 |
| Codex, a rig's own rules | 3 | 3 | 3 | 3 | 58 | 61 | 0 |

On Claude the skill was the first tool call in all 48 runs, and on Codex reading it
was the first command in all 12. So the load held on both providers, and it
came before the title in every run.

The titles did not move from having the rules inline:

- **This repository.** All 10 scoped titles are the ten cases whose size table is led
  by a named subsystem holding at least half its net lines, each taking that first
  row, as with the rules inline, where it was 30 of 48 over three runs each. None of
  the other six wrote a scope. The scope rule reached them only through the page.
- **No rig rules.** No title coined a scope, as with the rules inline, 0 of 48.
- **A rig's own rules.** All 16 used one of the rig's four types, a scope from its
  list and a capital first letter, as with the rules inline, 48 of 48. On Codex 3 of
  3 did too.

Looking for a rig's rules costs little where they exist, and the search is what a
rig with none pays. On this repository every Claude run needed one further call,
which read the page. With no rules to find, 6 of 16 runs stopped after that one
call, and the others made up to 5 more looking, several of them for this repository's
page by the path in the prompt's text, which a fixture cannot answer. On a real rig
`AGENTS.md` and `CLAUDE.md` are already in the session, so there is less to search.

### While committing

The implement step names the skill on this branch. `polecat/tk-1tfzr71.12`, in review
when this ran, makes `mol-polecat-work` inherit core's implement step, whose text does
not name it and lists seven commit types. So these runs took a change at the point of
committing, under each text, on three of the cases and with no rig rules.

| The step's text | Skill loaded | First tool call |
|---|---:|---:|
| This branch's implement step, which names the skill | 6 of 6 | 5 of 6 |
| Core's implement step, which does not | 6 of 6 | 6 of 6 |
| Control: `preflight-tests`, which writes no subject line | 0 of 3 | |
| Control: `load-context`, which writes no subject line | 0 of 3 | |

So on core's text the description alone loaded the skill. All 11 subject lines that
were written carried a type from the table and no coined scope. One run of core's
text used its six turns looking for the change, which the fixture does not hold,
and wrote none. Each of these runs was told it was about to commit, so a run deep in
other work may be less prompt, and nothing here measures that. A miss costs little:
the squash merge lands the PR title, not a commit subject.

### The reviewer, with the section out of its prompt

The first review run gave the new arm the section, because the review pool's prompt
carried it then. It no longer does. This run gave the correctness method alone at this
commit, on `codex exec` at `gpt-6.1-sol`, medium effort, three runs a cell, on the
same seven titles and the same two diffs. The directory held the pack's skills, as
a review session's does, and the method names the skill, so a reviewer could load it.

| The title | Rules in the prompt, final wording | Rules out of the prompt |
|---|---|---|
| `chore:` and the filed words, on the fix (its real merged title) | 3 blocking | 3 blocking |
| `fix: make gc-helm engage attach at once instead of waiting for its sitting` | 3 blocking | 5 blocking, 1 P2 of 6 |
| `fix(visit): make gc-helm engage wait for its sitting to start, then attach` | none | none of 6 |
| `fix: improve gc-helm engage` | 3 P2 | 3 P2 |
| `feat: make gc-helm engage wait for its sitting to start, then attach` | none | none |
| `chore:` and the filed words, on removing an unused option (its real merged title) | 3 blocking | 3 blocking |
| `refactor: remove the unused all option from run-lib.sh's map verb` | 1 blocking | none of 6 |

A count is the runs with a finding whose locus names the title, at that grade, as
above. Verdicts are not counted, because other findings on the diff decided some of
them, and every title finding and verdict line was read by eye. The false words and
the fair `refactor:` ran three times more, because three runs left each of them
thin, and a loose filter of mine ran the good title three times more as well.

The method holds with the section out. A reviewer read the skill in 22 of 30 runs,
including every run of the fair `refactor:` but one. The one P2 on the false words
was a run that did not read it, though another that did not read it still blocked,
so a reviewer that skips the skill can grade a false title lower, and one run does
not show how often. The fair `refactor:` blocking in none of 6, against 1 of 3 before,
is too few runs to credit to the move.

### Cost

69 Claude calls for $14.42, including three trial calls, and 42 Codex calls, in about
20 minutes at load 25 to 50.

### Every title from these runs

"repo" is this repository, "none" no rig rules, and "rig" a rig's own rules. A row
is absent where that provider did not run that case.

**#1361**, merged as: chore: run_lib map takes no scope, since no caller asks it for every run

```
repo       refactor: remove the unused all option from run-lib's map verb
none       refactor: remove the unused all option from run-lib.sh's map verb
rig        chore(scripts): Remove the all option from run-lib.sh's map verb
codex repo feat: remove the unused all option from run-lib map
codex none feat: remove the unused all option from run-lib map
codex rig  feat(scripts): Remove the run-lib map all option
```

**#1358**, merged as: chore: CI's actions are pinned to commit SHAs and run on Node 24, and the suite passes on the Ubuntu 26 image ubuntu-latest moves to

```
repo       build: pin CI's actions to commit SHAs and run them on Node 24
none       build: pin CI's actions to commit SHAs and run them on Node 24
rig        chore(ci): Pin CI's actions to Node 24 commit SHAs and enforce the pins
```

**#1344**, merged as: chore: Every gc-toolkit PR shows its size change, computed from git, naming lines it adds to code the deletion plan retires

```
repo       feat: show each PR's size and lines added to retiring code in a comment
none       feat: post each PR's size change as a comment from gc-toolkit's CI
rig        feat(ci): Post each PR's size change as a comment CI keeps current
```

**#1336**, merged as: chore: gc-helm engage waits for its sitting to start and then attaches, instead of giving up at 120 seconds

```
repo       fix(visit): make gc-helm engage wait for its sitting and then attach
none       fix: make gc-helm engage wait for its sitting to start, then attach
rig        fix(scripts): Make gc-helm engage wait for its sitting, then attach
codex repo fix(visit): keep engage waiting for its sitting to start and attach
codex none fix: keep gc-helm engage waiting through slow sitting starts
codex rig  fix(scripts): Keep engage waiting until its sitting starts
```

**#1322**, merged as: chore: docs/architecture.md says what a review reads from the installed pack and what from the rig under review, and at which commit

```
repo       docs: map what a review reads from the pack, the rig and its dispatch
none       docs: state what a review reads from the pack, the rig and its dispatch
rig        docs(records): State what a review reads from the pack and from the rig
```

**#1362**, merged as: fix: The tmux pickers double every # in the bead, session and pane text they put in a menu, so #(...) in that text shows as written instead of running as a shell command

```
repo       security(visit): stop tmux pickers running shell commands from menu text
none       security: stop tmux pickers running menu text as shell commands
rig        fix(scripts): Show tmux picker menu text as written, never expanded
codex repo security(visit): prevent shell execution from tmux picker text
```

**#1333**, merged as: chore: Delete four tools nothing runs: the surface census, the per-polecat metrics report, the reachability fixture and the one-shot approval migration

```
repo       refactor: delete the unused census, metrics, fixture and migration tools
none       refactor: delete the census, metrics, reachability and migration tools
rig        chore(scripts): Delete four tools that nothing runs
```

**#1298**, merged as: chore: Design: a PR is one reviewable unit, carried to main by one landing bead per integration branch, deleting gc-toolkit's convoy landing code

```
repo       docs: design a one-bead PR model that retires convoy landing code
none       docs: design a PR model with one landing bead per integration branch
rig        docs(records): Design one PR per effort, carried by a landing bead
codex repo docs: design one landing bead per integration branch
codex none docs: design the one-bead PR model and convoy code removal
codex rig  docs(records): Design one landing bead per integration branch
```

**#1371**, merged as: chore: A demo capture cannot reach the live city, so a screenshot or video on a pull request shows fixture data only

```
repo       security(review): keep demo captures from reaching the live city
none       security: keep demo captures from reaching the live city
rig        fix(scripts): Keep a demo capture from reaching the live city
codex repo security(review): isolate demo captures from live city data
```

**#1377**, merged as: fix: Self-review counts a setup or build note naming the repo's own command when the step declares none

```
repo       fix(work): count a self-review note of an undeclared setup or build
none       fix: count a setup or build note whose command the step does not declare
rig        fix(scripts): Count the repo's own setup or build note in self-review
```

**#1378**, merged as: fix: check-session-store-scope reads the running process from the kernel's record where there is no /proc, and warns once when it can read no pane at all

```
repo       fix(doctor): check running agents' session store scope on macOS
none       fix: make check-session-store-scope read running agents on macOS
rig        fix(scripts): Read running agents on macOS in check-session-store-scope
```

**#1370**, merged as: fix: A SIGTERM that misses a long sleep no longer holds gctk rig's relay tests open to the grace deadline, so TestRunStopWaitsForAChildThatIsStillStopping stops failing under load

```
repo       test(gctk): fix SIGTERM races in the stop tests' commands
none       test: keep gctk's stop tests from racing the SIGTERM they send
rig        fix(ci): Keep gctk's stop tests from failing at random under load
```

**#1351**, merged as: fix: The helm board counts an epic's children by what holds each one, so a child waiting its turn reads queued and a pull request in review owes no disposition

```
repo       fix(board): show what holds each open bead, not its markers
none       fix: stop the helm board reading held beads as stranded or owed
rig        fix(board): Count queued children and PRs in review by what holds them
```

**#1320**, merged as: fix: A rejected graduation is rebuilt on an ordinary child bead that gc sling pours, and its landing anchors the convoy

```
repo       fix(merge): rebuild a rejected graduation on a child gc sling pours
none       fix: rebuild a rejected graduation on a child bead, not on its convoy
rig        fix(scripts): Rebuild a rejected graduation on an ordinary child bead
codex repo fix(merge): rebuild rejected graduations on ordinary child beads
```

**#1343**, merged as: fix: The refinery, witness and deacon restart at a turn's end or before their next prompt once their prompt or patrol formula changes on disk

```
repo       fix(patrol): restart a session when its prompt or patrol formula changes
none       fix: restart a patrol session when its prompt or formula changes on disk
rig        fix(scripts): Restart patrol sessions whose prompt or formula changed
```

**#1288**, merged as: chore: outside feedback capture: review feedback from outside the city becomes condensed observations the distiller reads as a set

```
repo       feat(feedback): capture outside review posts as condensed observations
none       feat: capture outside review feedback as observations for the distiller
rig        feat(scripts): Capture outside review feedback as condensed observations
```

## What this cannot show

A run sees a cut-down prompt, a summary written by the PR's real author, and, in
this repository's arm, a size table it did not have to run. A real session has the
whole prompt in front of it and may read the section less closely. Three runs a
cell is few: a type or a word that moved between runs of one cell is not a finding.
The cases come from one repository, and the rig's rules were written by the same
session that wrote the wording, so that arm shows the rules winning where they
plainly conflict, not how a rig's rules read when they are vaguer.

The skill runs have the whole prompt and real tools, but each is told which step it
is at and that the line is what it owes, in one message, with nothing before it. A
live session reaches that step after hours of other work, possibly past a
compaction, and nothing refuses a title written without the load. So 60 of 60 shows
the step's wording and the description find the skill, not that a live session
always does.
