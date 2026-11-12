---
name: Gas City search for the standing memory triage (tk-zlot608.2)
description: The primitives searched in Gas City, bd and Claude Code for each need of the standing memory triage, with what each covers and why the gaps need the pack's own order, formula and script. Read it when building or reviewing the triage's surface, as AGENTS.md asks of a change that adds an order, a cluster of formula steps or a script.
---

# Gas City search for the standing memory triage

The triage this bead designs ([design.md](design.md)) adds an order, a formula
and a script. Each need below names the primitive searched, at Gas City
upstream main 6bd609f5bf (2026-11-11), bd upstream main d76ade282 (2026-11-11)
with bd 1.3.4 installed, and Claude Code's documentation read on 2026-11-11.

## Run an LLM pass on a schedule, in each rig

**Covered: Gas City's order.** Gas City's orders tutorial
(`docs/tutorials/07-orders.md`) gives a `cooldown` trigger that fires once
`interval` has elapsed since the last run. Under "Rig-scoped orders", a pack's
orders come along to every rig the pack is applied to and run scoped to that
rig. Under "Duplicate prevention", the orchestrator skips an order that already
has open work, so one run goes at a time. The triage composes these: its order
is `trigger = "cooldown"`, `interval = "168h"`, scoped to the rig, on the
`gc-toolkit.polecat` pool. The pack adds only the formula the order pours, as
the feedback miner does.

## Read, sort and empty an agent's memory

**Not covered.** This is the gap the formula and its script fill.

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

So the analysis, the removal and the copy are the pack's. The script carries the
mechanics a step must not hold as a procedure (docs/pack-authoring.md): finding
a store, copying it, listing the due notes, counting reads, removing a note only
while its hash matches the copy, and editing the index only when it has not
changed since the script read it.

## Find a store

**Partly covered: Claude Code's naming.** The memory page gives the store as
`~/.claude/projects/<project>/memory/`, where `<project>` "is derived from the
git repository, so all worktrees and subdirectories within the same repo share
one auto memory directory". It does not publish how a path becomes
`<project>`, so the script derives the name from the rig's checkout as the
stores on the host show it, with every `/` and `.` becoming `-`. A store that
does not exist under that name makes the run a no-op that says so.

## Count the sessions that read a note

**Not covered.** Claude Code says when a session recalls memories in its own
interface, and keeps no count anyone can query. Gas City's event types
(`internal/events/events.go`) cover beads, sessions, orders, mail and worker
operations, and none records a file an agent reads. The session transcripts
Claude Code keeps on the host record each tool call and the files it read, so
the script counts readers from them.
Claude Code deletes transcripts after `cleanupPeriodDays` (the memory page), and
the triage reads only the week since its previous run.

## Keep the copy and the record

**Covered: Gas City's pack state directory.** Gas City names one runtime
directory for each pack in a city, `citylayout.PackStateDir`, which is
`<city>/.gc/runtime/packs/<pack>` (`internal/citylayout/runtime.go`). The pack
spec gives it to a pack's commands as `GC_PACK_STATE_DIR`
(`docs/reference/specs/pack-spec.md`, the command environment table). A
polecat's session does not get that variable, so the script names the directory
from the city root, as the pack's shared locks do.

## A store agents could write instead

**Searched: bd's memory plane.** bd stores memories in the bead store with
`bd remember`, lists them with `bd memories`, and removes one with `bd forget`
(`docs/cli-reference/remember.md`, `memories.md` and `forget.md`). Writes are
transactional, every provider can make them, and `bd prime` injects every stored
memory at the start of a session (`docs/cli-reference/prime.md`). It does not
cover this need:

- The operator ruled that the intake is the memory agents write today: "yes use
  it as an intake" (conversation tk-1amy8sd, 2026-11-11). Claude Code's own
  instructions have its agents write Claude Code's store.
- `bd prime` loads every memory into every session, and its caps cut by count or
  size, not by relevance (`--max-memories`, `--max-memory-chars`). Claude Code
  loads only the index and reads a note when a session needs it. Two weeks of
  intake, some 450 notes, would land in every session.
- A memory is a key and a value (`memoryops/memories.go`), with no time it was
  written and no writer, so the triage would still keep its own record of age.

The gc-toolkit rig's store holds no bd memories (`gc bd memories`, 2026-11-11).
bd's plane is the natural intake for Codex agents, which have none, if the
operator wants them to have one (design.md, section 6).

`bd prime`'s default text tells an agent to use `bd remember` and not
`MEMORY.md` files. The city's Claude agents follow Claude Code's own memory
instructions, and the guidance block (design.md, section 5) names the store the
triage reads. Removing bd's line would mean replacing `bd prime`'s whole default
text in every rig with a `.beads/PRIME.md` (`docs/cli-reference/prime.md`,
"Workflow customization"), so this design leaves it.
