---
name: Gas City search for the memory intake (tk-zlot608.2)
description: The primitives searched in Gas City, bd and Claude Code for each need of the memory intake, the distiller's reading of agent memory notes, with what each covers and why the gaps need the distiller's new step and the pack's own script. Read it when building or reviewing the intake's surface, as AGENTS.md asks of a change that adds a cluster of formula steps or a script.
---

# Gas City search for the memory intake

The intake this bead designs ([design.md](design.md)) adds a step to the
distiller's formula, a script and the files the script keeps in the pack's state
directory. It adds no order. Each need below names the primitive searched, at
Gas City upstream main 6bd609f5bf (2026-11-11) and bd upstream main d76ade282
(2026-11-11) with bd 1.3.4 installed, and Claude Code's documentation read on
2026-11-11.

## Run the judging on a schedule

**Covered: the distiller's Gas City order.** The distiller already runs on a
Gas City order with a `cooldown` trigger, which fires once `interval` has
elapsed since the last run (the orders tutorial, `docs/tutorials/07-orders.md`).
The memory step is a step of that formula, so it runs on that order and adds
none. The tutorial's "Duplicate prevention" has the orchestrator skip an order
that already has open work. The script still locks each memory directory while
it writes, as the distiller's formula already allows for a concurrent peer pour
when it files.

## Read, judge and empty an agent's memory

**Not covered.** This is the gap the step and its script fill.

- **Gas City** has no primitive that reads an agent's memory. Its audit of Gas
  Town's commits defers agent memory
  (`engdocs/archive/analysis/gastown-upstream-audit.md`, "22g. Agent memory":
  it "requires `gc remember`/`gc forget` CLI commands and agent bead metadata
  fields"). No file upstream names `MEMORY.md`, auto memory or
  `CLAUDE_CODE_DISABLE_AUTO_MEMORY`.
- **Claude Code** keeps memory files out of its retention sweep: "`MEMORY.md`
  and topic files stay until you or Claude edits or deletes them"
  ([memory](https://code.claude.com/docs/en/memory), "Storage location"). It
  offers switching memory off (`autoMemoryEnabled`,
  `CLAUDE_CODE_DISABLE_AUTO_MEMORY`) and moving it (`autoMemoryDirectory`). It
  warns an agent when `MEMORY.md` nears its 200-line or 25 KB load limit ("How
  it works"). It sorts, expires or empties nothing.

So the judging, the removal and the record are the pack's. The judging is the
distiller's, by its rubric. The script carries the mechanics a step must not
hold as a procedure (docs/pack-authoring.md): placing each memory directory,
listing the due notes, removing a note only while its hash matches the hash the
judge read, and editing the index or a collection note only when it has not
changed since the script read it.

## Find a memory directory

**Partly covered: Claude Code's storage-location rules and Gas City's settings
file.** The memory page ("Storage location") gives the directory as
`~/.claude/projects/<project>/memory/`, where `<project>` "is derived from the
git repository, so all worktrees and subdirectories within the same repo share
one auto memory directory". The sessions page gives the conversion for a
transcript's `<project>`, the working directory's path "with non-alphanumeric
characters replaced by `-`", cut to 200 characters with a hash of the path
appended when it is longer
([sessions](https://code.claude.com/docs/en/sessions), "Where transcripts are
stored"). The memory directories on this host carry that conversion of the path
of the rig's checkout, for the sessions in its worktrees too.

The memory page's section also moves the directory. `CLAUDE_CONFIG_DIR` takes
the place of `~/.claude`. `CLAUDE_CODE_PROJECT_DIR_NAME`, set beside it, names
`<project>` for every repository launched with that config directory, and
Claude Code ignores a value that is not 1 to 64 letters, digits, hyphens or
underscores (sessions, "Name the project directory yourself").
`autoMemoryDirectory` names the directory itself: "It is read from any settings
scope: user, project, local, policy, or `--settings`", and its value "must be
an absolute path or start with `~/`". Claude Code honors a project's or a local
value under workspace trust, and while
`permissions.blockReadsOutsideWorkingDirectories` is on it neither loads nor
writes memory in a directory a repository-supplied settings file chooses. That
is the shared project settings, or local settings that git tracks or that sit
under a linked `.claude`
([permissions](https://code.claude.com/docs/en/permissions), "When your local
settings file needs trust"). Memory is off under `autoMemoryEnabled` false or
`CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` (the memory page, "Enable or disable auto
memory"), and that variable set to `0` turns it on "even when `--bare` mode or
`autoMemoryEnabled: false` would otherwise disable it"
([environment variables](https://code.claude.com/docs/en/env-vars)). When
several levels set a key, Claude Code uses the value of the highest: managed
settings, then `--settings`, then local, shared project and user settings
([settings](https://code.claude.com/docs/en/settings), "Settings precedence").

Gas City gives each Claude session one of those levels.
`config.appendProviderSettings` adds `--settings` with the file
`config.ProviderSettingsSource` names, `<city>/.gc/settings.json`, and
`hooks.installClaude` writes that file from the city's own Claude settings,
`<city>/.claude/settings.json` first (`internal/config/launch_command.go` and
`internal/hooks/hooks.go` at 6bd609f5bf).

No `claude` command prints the directory a session uses (`claude --help` at
2.1.322), and inside a session `/memory` opens it. So the script applies the
rules itself to the inputs it can read. [design.md](design.md), section 7,
gives those inputs, the directories the run reads, and how it tells an absent
directory from a place it cannot resolve, so a miss under the derived name is
never by itself an empty directory. A place the run cannot resolve is reported
through the pack's `patrol-finding.sh`, the route the feedback miner takes, so
the intake adds no reporting of its own.

## Hold a note until what it waits on is done

**Covered for the patterns, not for the note.** A note waits on its feedback
pattern, a bead whose lifecycle composes bd's `blocks` edges, `bd defer` and
`bd ready` (the pattern change, tk-ltcv43q, records its own search). A note is
a file, not a bead, so no bd edge can make it wait. The list the script keeps
records the bead each note waits on, and each run reads that bead's status.

**Searched: bd's dated defer,** for a note about a moment that has not passed,
which the judge reads again on a date (design.md, section 2). `bd defer --until`
hides an issue from `bd ready` until the date passes and then returns it to open
(`cmd/bd/defer.go` at d76ade282). It holds only an issue, and the note is a
file, so the note's row on the list holds the date, and each run compares it.

**Searched: bd's cross-project dependency,** for a note's wait on a fix filed in
another rig's store. A dependency names a local issue or an external reference,
`external:<project>:<capability>` (`cmd/bd/dep.go` at d76ade282). An external
reference resolves once the other project holds a closed issue labeled
`provides:<capability>`, which `bd ship` adds to a closed issue labeled
`export:<capability>` (`cmd/bd/ship.go`). It does not cover the need: the waiter
here is a note, which no edge can hold, and the wait would end only once someone
ran `bd ship` after each fix closed. So the note's row on the list names that
bead, and the run reads it from its store.

## Stop a vetoed rule from steering agents

When the operator vetoes a proposal a note's pattern spawned, the build keeps
the note for the judge and stops its rule steering agents in the run that ends
the wait (design.md, section 3). This need was searched on 2026-11-14, at Gas
City upstream main 13bb101b8f, with Claude Code's memory page read that day.

**Not covered: switching off one memory file.**

- **Claude Code** turns auto memory off for a whole session or project
  (`autoMemoryEnabled`, `CLAUDE_CODE_DISABLE_AUTO_MEMORY`) and moves the whole
  directory (`autoMemoryDirectory`)
  ([memory](https://code.claude.com/docs/en/memory), "Enable or disable auto
  memory" and "Storage location"). Its `claudeMdExcludes` setting skips
  CLAUDE.md and rules files by path ("Exclude specific CLAUDE.md files"), and
  the page names no exclusion for a memory topic file. What loads at the start
  of a session is the index, `MEMORY.md`, and Claude reads a topic file "on
  demand using its standard file tools when it needs the information" ("How it
  works"). Claude treats memory "as context, not enforced configuration"
  ("CLAUDE.md vs auto memory"). So the words an agent reads are the lever: the
  index and collection-note lines that point at the note, and the note's own
  text.
- **Gas City** has no primitive that reads or edits an agent's memory. No file
  at upstream main 13bb101b8f names `MEMORY.md`, auto memory, `autoMemory` or
  `CLAUDE_CODE_DISABLE_AUTO_MEMORY`, and its audit still defers agent memory
  (`engdocs/archive/analysis/gastown-upstream-audit.md`, "22g. Agent memory").
- **bd** can mark a bead, but a note is a file, so no bd state reaches it.

**Covered: reading the veto.** The distiller's vetoed-PR sweep defines a veto as
a prompt-update bead, closed when its PR opened with `merge_result` set to
`pull_request`, whose PR GitHub reports closed unmerged (mol-feedback-distiller,
load-and-gate section 4). The run already reads each follow-up's merge state and
its PR's through `gh pr view` to tell whether a fix landed, so it tells a veto
apart from the same read and adds no reader.

So read-memory writes the marks itself, in the words `memory-guidance.md` holds,
through the guarded edit it already makes to an index: each mark is written only
while the file holds the text it was made from. The marks need no state of their
own. The note's row clears its wait and is due from the day the pattern closed,
as after a dismissal, and a mark already in a file is not written again.

## Keep the list and the removed notes' text

**Covered: Gas City's pack state directory.** Gas City names one runtime
directory for each pack in a city, `citylayout.PackStateDir`, which is
`<city>/.gc/runtime/packs/<pack>` (`internal/citylayout/runtime.go`). The pack
spec gives it to a pack's commands as `GC_PACK_STATE_DIR`
(`docs/reference/specs/pack-spec.md`, the command environment table). A
polecat's session does not get that variable, so the script names the directory
from the city root, as the pack's shared locks do.

## A memory agents could write instead

**Searched: bd's memory plane.** bd stores memories in the bead store with
`bd remember`, lists them with `bd memories`, and removes one with `bd forget`
(`docs/cli-reference/remember.md`, `memories.md` and `forget.md`). Writes are
transactional, every provider can make them, and `bd prime` injects every stored
memory at the start of a session (`docs/cli-reference/prime.md`). It does not
cover this need:

- The operator ruled that the intake is the memory agents write today: "yes use
  it as an intake" (conversation tk-1amy8sd, 2026-11-11). Claude Code's own
  instructions have its agents write Claude Code's memory directory.
- `bd prime` loads every memory into every session, and its caps cut by count or
  size, not by relevance (`--max-memories`, `--max-memory-chars`). Claude Code
  loads only the index and reads a note when a session needs it. The city's
  memory directories hold about 2,070 notes, which would land in every session.
- A memory is a key and a value (`memoryops/memories.go`), with no time it was
  written and no writer, so the intake would still keep its own list.

The gc-toolkit rig's store holds no bd memories (`gc bd memories`, 2026-11-11).
bd's plane is the natural intake for Codex agents, which have none, if the
operator wants them to have one (design.md, section 7).

`bd prime`'s default text tells an agent to use `bd remember` and not
`MEMORY.md` files. The city's Claude agents follow Claude Code's own memory
instructions, and the guidance block (design.md, section 6) names the memory
directory the distiller reads. Removing bd's line would mean replacing
`bd prime`'s whole default text in every rig with a `.beads/PRIME.md`
(`docs/cli-reference/prime.md`, "Workflow customization"), so this design leaves
it.
