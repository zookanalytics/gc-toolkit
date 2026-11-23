---
name: A/B probe of the fixture entry in rule tk-xxb1jh
description: Read it to check the numbers in tk-je73drv's summary, to see which cases the fixture entry moves, or to re-run the probe on a later wording.
---

# A/B probe of the fixture entry

The proposal asks the build to measure one thing. On PR #1507's case, with and
without the entry, does an author record the producer's output instead of
building the note by hand? If the entry does not move the author, pattern
tk-xxb1jh comes back to the distiller with that evidence.

The entry does not move the author on #1507's case. It does move the author on
#1045's case, the stub for `gc bd list` that the operator's account reviewed.
Every run with the entry says it would copy the recorded rows into the fixture,
and no run without it does.

| Case | What is counted | Without the entry | With it |
|---|---|---|---|
| M, PR #1507: a note kept to record its uses | Runs that take the note, or the change a use makes, from Claude Code's real output, recorded or sampled | 0 of 3 | 0 of 3 |
| M | Runs whose note fixture carries front matter | 2 of 3 | 3 of 3 |
| M | Runs whose simulated use changes the note's text beyond the appended line | 0 of 3 | 0 of 3 |
| B, PR #1045: the scan drops a bead a live workflow drives | Runs that would run the real `gc bd list` reads before writing the fixture | 3 of 3 | 3 of 3 |
| B | Runs that build the fixture from that recorded or sampled output | 0 of 3 | 3 of 3 |
| B | Runs that propose a stub `gc` answering the live path's exact command lines, the ask of #1045's review comment | 3 of 3 | 1 of 3 |

## Method

Each arm's system prompt is the whole rendered page
`generated/seed-audit/agents/polecat.md`, followed by the auto-memory section of
this build session's Claude Code system prompt, which shows the front matter an
agent writes on a note. The page without the entry is the effort's base,
8d778ffee, and the page with it is the entry's commit, 92c907ba7. The two
system prompts differ only in the entry and its anchor. The model is
`claude-opus-5-5`, the one this build's polecat session runs.

Each call ran `claude -p --model claude-opus-5-5 --tools "" --max-turns 1
--no-session-persistence --output-format json --setting-sources ""
--strict-mcp-config --disable-slash-commands` from an empty directory, with
every `GC_*` and `BEADS_*` variable unset and auto memory off. Each cell has
three runs. The twelve calls took about 351,000 input tokens and 50,000 output
tokens, and ran 7.5 minutes in all.

Each case closes with "You have no tools in this turn. Reply with the lines,
and with any step you would take before adding them." So a run can say that it
would record or sample real output, but it cannot do it.

## Cases

- **M** is the case `── a note kept to record its uses ──` at #1507's reviewed
  head, 68355c2, which passed with a `printf` append to a note that had no front
  matter. The run gets the task: the note gains the line that asks for its
  uses, an agent records a use as the guidance asks, the use does not make the
  note due, its date still does, and any other change does. It also gets the
  script's header and its `scan` and ask-use code, `memory-guidance.md`, and the
  suite's harness up to its first case. The suite's own cases are left out, so
  the note's shape is the run's choice.
- **B** is the case under review comment 4212283570 on #1045, posted from the
  operator's account: `tools/gc-proactive.test.sh` at 4e6e9fee5, where
  `roots.json` and `convoys.json` stand in for the two `gc bd list` reads that
  `scan_drop_inflight` takes. The run gets the script's header,
  `rig_beads_db`, the sling guard, the scan's filters and `scan_candidates`,
  and the whole test file with the case cut out and its place marked.

## The sentences each count rests on

M, recorded or sampled. No run in either arm names Claude Code's output as a
source. Each run's steps before writing are checks on the script, such as what
`USE_LINE` holds and whether `due` needs a `read` first, and a run of the
suite. Each run writes the note with `printf` and records the use with an
appending `printf`.

M, front matter. Without the entry, runs 1 and 2 write `name` and
`description`, run 2 also writes `metadata.type`, and run 3 writes a bare line.
With it, all three write `name` and `description`, and run 1 also writes
`metadata.type`. No run writes `node_type`, `originSessionId` or `modified`,
the keys Claude Code adds when it saves a note
(`specs/tk-riu2z5n/claude-code-saves.md` at 36ed696db, in PR #1507's commits).

B, building from the recorded output. With the entry:

- Run 1: "Copy a convoy row and a root row from that output into the fixtures
  below, then rename their ids."
- Run 2: "Record that command's real output against a convoy that tracks a
  bead. Copy the row shape into the fixture below."
- Run 3: "Then rebuild both fixture files from rows you sampled."

Without it, each run checks the output and keeps rows of its own:

- Run 1: "The fixture can only copy the row shape I assume."
- Run 2: "I would run that command against the rig's store and confirm the
  shape."
- Run 3: "The fixture below copies that shape, but the fixture cannot prove the
  shape is real."

B, a stub for the exact command lines. Without the entry, run 1 proposes it if
`board_rank` calls no `gc`, run 2 proposes it if the shape holds, and run 3
files a bead for it. With it, only run 3 proposes it, "built from the output
recorded in step 3".

## What it can and cannot show

It shows what an author says it would do first, in one turn with no tools, on a
page that holds every other standard. It cannot show what an author with tools
does. On #1507's case no run could have found the stamp without opening a real
note or recording a real save. Three runs a cell can show a change from none to
all, but not a small change, so the stub count's fall from 3 to 1 can be noise.

The two cases suggest where the entry fires. It fires when the producer is
plainly another program, a command whose output the test replaces. It does not
fire when the producer is the agent's own tool. In #1507's case the agent writes
the use line through Claude Code's file tools, and every run treated that write
as a plain append of its own, not as data that Claude Code writes.
