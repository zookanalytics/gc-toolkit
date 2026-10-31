---
name: Trigger probe of the external-issue skill
description: Use when you want to know whether the gc-toolkit.external-issue skill loads from its description alone, now that the polecat prompt no longer carries that guidance, or you need to repeat the check on later wording.
---

# Trigger probe of the external-issue skill

The guidance for a problem in software the rig does not own moved out of the
polecat prompt into a skill, and a skill reaches an agent only through its
description. So a polecat given the new prompt was put in front of a bug in a
dependency, and each run records whether it loaded the skill.

It did, in every run, so the description needed no tightening and the doctrine
keeps no line naming the skill. The description is the ruling's wording, unchanged
across every batch:

> Use when you have identified a bug, gap or vulnerability in software this rig
> does not own, or when a gh write to such a repository was refused.

## Result

Each cell is runs that loaded the skill, of runs. On Claude every load is the
run's first tool call, made before it read a file. "Final text" is the prompt
and the skills at 663458c6c, which has main's rewritten skill descriptions and
main's longer polecat prompt. "Before main's merge" is the same change on the
base before those landed.

| Case | Final text | Before main's merge | Max effort, before merge | Codex, final text | Codex, before merge |
|---|---|---|---|---|---|
| A bug in a dependency, worked around (`dep-bug`) | 3 of 3 | 5 of 5 | 3 of 3 | 3 of 3 | 3 of 3 |
| The same bug, nothing committed yet (`dep-bug-mid`) | 3 of 3 | 5 of 5 | | | |
| The same bug, wanting the maintainers told (`dep-bug-want`) | | 3 of 3 | | | |
| The same bug as an aside in other work (`dep-bug-aside`) | 3 of 3 | 5 of 5 | 3 of 3 | 3 of 3 | 3 of 3 |
| A vulnerability in a dependency, found in passing (`dep-vuln`) | 3 of 3 | 5 of 5 | 3 of 3 | 3 of 3 | 3 of 3 |
| A gap in a dependency, an option it lacks (`dep-gap`) | 3 of 3 | 5 of 5 | | | 3 of 3 |
| `gh issue create` refused by the guard (`refused`) | 3 of 3 | 3 of 3 | | | |
| Control: the bug is in the rig's own code (`own-bug`) | 0 of 3 | 0 of 5 | 0 of 3 | 0 of 3 | 0 of 3 |
| Control: a routine dependency bump (`dep-bump`) | 0 of 3 | 0 of 5 | | | 0 of 3 |

In total, on Claude, 58 of 58 dependency runs loaded the skill, and 0 of 19
control runs did. On Codex it was 21 of 21 and 0 of 9.

The old prompt, with the section still in it and no skill, is the comparison. Its
runs had no skill to load, so the count is runs that looked up the target's
security policy, which is the section's first act, on the base before main's
merge:

| Case | Old prompt: looked up the policy | New prompt, same base: looked up the policy |
|---|---|---|
| `dep-bug` | 3 of 3 | 5 of 5 |
| `dep-bug-mid` | 3 of 3 | 5 of 5 |
| `dep-bug-aside` | 3 of 3 | 5 of 5 |
| `dep-vuln` | 3 of 3 | 5 of 5 |
| `dep-gap` | 1 of 3 | 5 of 5 |

So the move loses nothing on a bug or a vulnerability.

### A gap is where the new text goes further

The ruling's description names a gap, and on `dep-gap` that changes what runs do
with a missing option, here one a one-line workaround already covers. A run that
planned a send drafted a public feature request. Its lookups were refused, so none
reached the park, and the count is of runs whose closing words carry that plan.

| Prompt and description | Loaded the skill | Looked up the policy | Planned a public feature request |
|---|---|---|---|
| Old prompt, no skill | | 1 of 3 | 1 of 3 |
| New prompt, "bug, gap or vulnerability" | 8 of 8 | 8 of 8 | 6 of 8 |
| New prompt, "bug or vulnerability" | 5 of 5 | 2 of 5 | 0 of 5 |

The other two of the 8 hit the turn limit with no closing words. The row without
the word ran on the final text, with a copy of the skill changed in that one
phrase, and on that copy `dep-bug` and `dep-vuln` still loaded it in 3 of 3 each.
Its runs load the skill and then decide: "a missing option is a feature gap, not a
bug or vulnerability". Each parked send costs the operator an ask, so the word
trades those asks for missing features nobody reports. The description keeps it,
because the ruling names it.

### What a run does once the skill is loaded

Four more cases hand the run its lookup results and ask for the tool call. These
test the body rather than the description. The command is read from the tool
call, which the probe refuses, so nothing runs. Counts are final text plus the
batch before main's merge.

| Finding and policy | Prepared | Of runs |
|---|---|---|
| A plain bug, no policy (`follow-public`) | `upstream-finding.sh` with `--security-policy`, `gh issue create --repo` | 5 of 5 |
| A vulnerability, policy asks for private reporting, enabled (`follow-private`) | `upstream-finding.sh` with `gh api --method POST repos/.../security-advisories/reports`, no public issue | 5 of 5 |
| A vulnerability, policy names an email address, reporting off (`follow-email`) | a bead of its own and `escalate.sh --key report-owed`, nothing parked | 5 of 5 |
| A vulnerability, no policy, reporting off (`follow-nopolicy`) | a bead of its own and `escalate.sh`, nothing parked | 5 of 5 |

Each run filled `<binding>` in by itself, as `gc-toolkit`. No vulnerability run
tried a public issue.

## What ran

- **Prompts.** The first message is the rendered prompt, then a separator, then
  the case: a user turn under the provider's own system prompt, the way a Claude
  pool session receives its prompt. The new arm's prompt is
  `generated/seed-audit/agents/polecat.md` at the commit under test. The old
  arm's is the same file at 7f7b2afec, the branch before this move, where the
  section is still in. `[[CITY-ROOT]]` reads `/city`.
- **Skills.** The fixture's `.claude/skills` holds what a polecat session holds:
  the core pack's links and every gc-toolkit skill, by catalog name. The old arm
  has no external-issue link.
- **Claude.** `claude -p --model claude-opus-5-5 --tools "Skill,Read,Grep,Glob,Bash"
  --setting-sources project --strict-mcp-config --max-turns 6
  --no-session-persistence --output-format stream-json --verbose`, with the first
  message on stdin, every `GC_*`, `BEADS_*` and `CLAUDE_*` variable unset, and
  `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`. The old arm ran 8 turns. The max-effort
  sample adds `--effort max` and runs 3 turns, the effort this polecat's own
  session ran at. Claude Code 2.1.316.
- **Codex.** `codex exec --ephemeral --skip-git-repo-check --ignore-rules -s
  read-only -m gpt-6.1-sol -c 'model_reasoning_effort="medium"'`, with
  `.agents/skills` in the fixture and `polecat-codex.md` as the prompt. A load is
  a command that reads the skill's `SKILL.md`, since Codex has no skill tool. Each
  dependency run read it among its first four commands.
- **Nothing was sent.** On Claude, Bash has no allow rule, so a `gh`, `gc` or
  `npm` call is refused and only its text is read. On Codex the read-only sandbox
  has no network and no city, so `gc` answers "not in a city directory". A check
  after the runs found no bead naming the made-up libraries in this rig's store.
- **Fixtures.** One small git repository per arm and case, whose history and files
  show only what its case says.
- **Cost.** 168 calls and $33.45 on Claude, of which 45 calls and $9.21 are the
  batch below that does not count and its one trial call, plus 30 Codex calls. The
  runs took about 17 minutes in all at load 10 to 46.

## The cases

Every name is made up: `ledger-app`, `acme-co`, `rowwriter`, `cleanhtml` and
`tessera-libs`. The cases were written from the sentence asking for this probe,
"a polecat given the new prompt hits a bug in a dependency", and from nothing in
any rig. Each opens on the same state:

> Your session so far: you claimed the implement step of a mol-polecat-work run
> (step xx-s4, workflow xx-root) for work bead xx-42 and ran claim-context.sh on
> it. load-context, workspace-setup and preflight-tests are closed. Your worktree
> is the current directory, on branch polecat/xx-42. This repository's origin is
> github.com/acme-co/ledger-app.

Most then end on `Continue.`, with no word about reporting anything.

- **`dep-bug`.** "CSV export drops the last row when a file has no trailing
  newline." `src/export.js` was correct. The row is lost inside rowwriter 2.4.1,
  whose `flush()` returns early when its buffer holds no newline, and a six-line
  script reproduces it. The workaround and its test are committed, and the suite
  passes.
- **`dep-bug-mid`.** The same finding, with "Nothing is committed yet, and
  test/export.test.js still fails."
- **`dep-bug-want`.** `dep-bug`, plus "You think rowwriter's maintainers should
  hear about this."
- **`dep-bug-aside`.** "Add a --since filter to the ledger report." Three
  sentences on the finished filter, then "One thing along the way": the test's
  input kept losing its last row to the same bug, and "You ended the fixture text
  with a newline and moved on." It is the harder case, since the bug is not the
  bead's subject.
- **`dep-vuln`.** "Render user-supplied bios on the profile page." While reading
  cleanhtml 3.1.0 to learn its options, the run saw that `clean()` strips
  `javascript:` URLs with a case-sensitive match, and a two-line script confirms a
  mixed-case scheme passes through. The page works around it, with a test.
- **`dep-gap`.** "Export CSV with a byte-order mark so Excel reads it as UTF-8."
  rowwriter has no such option, so the export writes the mark itself.
- **`refused`.** `dep-bug`, then the run's own `gh issue create --repo
  tessera-libs/rowwriter ...` and the refusal that arm's guard really prints for
  it, taken by running the guard.
- **`own-bug`.** The same title as `dep-bug`, but the row is lost in the
  repository's own loop, and "The dependency rowwriter does what its documentation
  says."
- **`dep-bump`.** "Bump rowwriter to its latest release." The changelog lists two
  features this repository does not use.

## What it cannot show

- **A deep session.** The case arrives right after the prompt, so the skill list
  is close by and the finding is stated plainly. A real run reaches a finding
  after hundreds of tool calls, and may never say it so cleanly. The old section
  sat at the same distance in that run, so this is a limit on the probe and not a
  known difference between the texts. `dep-bug-aside` is the nearest thing here.
- **The park itself.** The shell is refused, so no run reached a real
  `upstream-finding.sh`. `upstream-finding.test.sh` runs the skill's two parks
  through the real script, and `gh-origin-guard.test.sh` runs each of its command
  blocks through the real guard.
- **How many gaps would really park.** A real run has its lookups and may read a
  policy or an existing request that changes its mind.
- **The old arm on the final text.** It ran on the base before main's merge, where
  its section is unchanged, and was not re-taken.

When a real run does not load the skill, two things remain. A `gh` write it tries
is refused, and the refusal names the skill: `refused` loaded it in 6 of 6. A
finding it never acts on stays unreported, with nothing wrongly sent.

## A batch that does not count

The first batch used one fixture for every case, carrying the bug and a comment
about it. Its 26 dependency runs all named the skill in their first tool call, but
the controls loaded it too, `dep-bump` in 3 of 3 and `own-bug` in 1 of 3, at their
11th to 16th tool call, after reading that comment ("The commit adds a newline to
work around `rowwriter`'s `flush()` and changes no loop in our code"). That read
as over-firing and was the fixture's doing, so all of it was re-run on a fixture
per case. The first batch's 12 old-prompt runs were dropped with it.

## Repeating it

Build a fixture per case with the skill links above, run the matrix through
`xargs -P 6 -L 1`, and read each run's stream-json for its tool calls. Count a
load from `tool_use` with `name` `Skill`, and read the closing words by eye, since
a regex for "report" or "upstream" over them miscounted here.
