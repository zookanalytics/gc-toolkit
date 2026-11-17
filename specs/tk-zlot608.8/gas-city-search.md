---
name: Gas City search for gctk memory (tk-zlot608.8)
description: The primitives searched in Gas City, bd and Claude Code for each need of the memory intake's Go shape, gctk memory, with what each covers and why each gap is the noun's, its state directory and the distiller's read-memory step. Read it when reviewing the intake's surface, as AGENTS.md asks of a change that adds a gctk noun, a state directory or formula steps.
---

# Gas City search for gctk memory

This build adds a gctk noun, `memory`, with three verbs (`due`, `apply`,
`settle`), a state directory per memory directory, the distiller's
`read-memory` step, one patrol finding key (`memory-intake.places`) and a prompt
fragment. It adds no order and no bead key. Each need names the primitive
searched, at `gastownhall/gascity` main 5f7cd988a6be (2026-11-17),
`gastownhall/beads` main 8cdfa796a8f5 (2026-11-13), Claude Code 2.1.326, and
Claude Code's documentation read on 2026-11-17. The design's own search,
[specs/tk-zlot608.2/gas-city-search.md](../tk-zlot608.2/gas-city-search.md),
holds the needs this build did not change: the schedule, a memory agents could
write instead, and bd's dated defer and cross-project dependency.

## Run the judging on a schedule

**Covered: the distiller's Gas City order.** The distiller runs on an order
with a `cooldown` trigger (`docs/tutorials/07-orders.md`). read-memory is a step
of its formula, so the build adds no order.

## Read, judge and empty an agent's memory

**Not covered.** No file in Gas City outside its tests names `MEMORY.md`, auto
memory or `CLAUDE_CODE_DISABLE_AUTO_MEMORY`, and its audit of Gas Town's
commits defers agent memory
(`engdocs/archive/analysis/gastown-upstream-audit.md`, "22g. Agent memory").
Claude Code keeps memory files out of its retention sweep: "`MEMORY.md` and
topic files stay until you or Claude edits or deletes them"
([memory](https://code.claude.com/docs/en/memory), "Storage location"). So the
judging is the distiller's, by its rubric, and the bookkeeping is the noun's,
which stands on its warrant
([docs/warrants.md](../../docs/warrants.md#memory-note-waits)).

## Find a memory directory

**Covered by asking Claude Code.** Claude Code computes where a session keeps
auto memory, and the build asks it rather than copying the rules.

- The memory page documents no command that prints the directory: `/memory`
  "provides an option to open the auto memory folder", and the page gives the
  default location and the settings that move it
  ([memory](https://code.claude.com/docs/en/memory)).
- A print-mode session's stream starts with a system record of subtype `init`,
  which in 2.1.326 carries `memory_paths.auto`, the session's auto memory
  directory. The Agent SDK's reference does not list the field among the init
  message's fields ([TypeScript reference](https://code.claude.com/docs/en/agent-sdk/typescript),
  `SDKSystemMessage`), and the binary's schema marks it `@internal`. The binary
  sets it only when auto memory is on (`LFn`, which builds the init record).
  So an answer with no field is reported as a place the intake cannot learn,
  whichever of the two it is, and never read as memory being off.
- The ask runs with the settings a city session runs with. Gas City projects
  `<city>/.gc/settings.json` before each Claude start and passes it with
  `--settings` (`ensureClaudeSettingsArgs`, `settingsArgs` and
  `claudeSettingsSource` in `cmd/gc/cmd_start.go`). A second `--settings` flag
  replaces the first (probed with 2.1.326), so the ask passes that file's
  object with `disableAllHooks` set, which keeps the city's and the checkout's
  hooks from running with it. `--bare` would also skip hooks, but it turns auto
  memory off (`claude --help`, 2.1.326).
- A session's start makes its memory directory when nothing is there (probed:
  both `projects/<project>/` and `memory/` appear empty), so the adapter removes
  each empty directory the ask made on the way to the answer, by its real path.
- The ask is one turn on haiku with no transcript (`--no-session-persistence`)
  and no MCP server (`--strict-mcp-config`). The init record comes before the
  turn, so a turn refused for its account still answers.

## Hold a note until what it waits on is done

**Covered for the patterns, not for the note.** A note waits on its feedback
pattern, whose lifecycle composes bd's `blocks` edges, `bd defer` and `bd
ready`. A note is a file, which no bd edge can hold: `bd defer --until` holds
an issue (`cmd/bd/defer.go`), and a dependency joins an issue to a bd id or an
`external:<project>:<capability>` reference (`cmd/bd/dep.go`). So the list
records the bead each note waits on, or the date it is next due.

## Read the beads a note waits on

**Covered: the bd store, through gctk's ledger.** `gctk memory settle` reads
each bead a note waits on with one `gc bd list --id ... --all` per store, and a
pattern's follow-ups from the same listing: the beads its own `blocks` edges
name, with its `proposal_bead` and `eng_bead`, which the distiller writes and
the ledger declares read-only.

## Tell whether a fix has landed

**Searched: Gas City's work record.** A close records `gc.work_outcome`, and a
shipped one records `gc.work_commit` reachable on `gc.work_branch`
(`internal/workrecord/gate.go`, `EnforceEnvVar`). It records the branch a close
shipped on, which for a member of an integration effort is the effort's branch,
so it does not say whether the fix reached the default branch. In this rig's
store it also begins on 2026-10-14: 1,114 of the 1,486 beads closed on a merge
carry no `gc.work_commit`, and 124 of the rest name the work's source branch.

**Covered: Gas Town's merge record and git.** Every bead in this store closed on
a merge carries `merged_sha` and `merged_target`, the record the pr domain
declares (`services/gctk/pr/record`). The settle reads it through that domain's
reading face and asks `git merge-base --is-ancestor` whether the merge commit is
on origin's default branch in the rig's checkout, as origin/HEAD names it, the
check the lifecycle's landing makes (`services/gctk/internal/cli/lifecycle.go`).
A merge into `integration/<id>` lands once the bead `<id>` has, and a bead that
closed with no merge commit landed nothing. No bead in this store that closed
with `merge_result=pull_request` has an open or a merged PR, so the settle asks
GitHub nothing.

## Keep the list and the removed notes' text

**Covered: Gas City's pack state directory.** `citylayout.PackStateDir`
(`internal/citylayout/runtime.go`) names `<city>/.gc/runtime/packs/<pack>`, and
the noun keeps one directory there per memory directory, named for the SHA-256
of its real path.

## Report a place the intake cannot learn

**Covered: the pack's finding writer.** `patrol-finding.sh` keeps one bead per
situation key, updates it when the situation recurs and clears it through
`bd set-state`, as the feedback miner's findings do. The settle keeps one key,
`memory-intake.places`, through the runtime adapter's script call, and adds no
reporting of its own.

## Tell agents what goes in memory

**Covered: Gas City's prompt templates.** A role's prompt composes pack
fragments, and the template data carries `ProviderKey`, which "Templates can
branch on" (`PromptContext` in `cmd/gc/prompt.go`). The converse prompt, which
Claude and Codex sittings share, composes the memory fragment only when the key
is `claude`, so no Codex sitting carries it. The operator ruled that the
guidance lives in prompts (option A, conversation tk-f6pdi0y), in place of a
block the intake would rewrite in each index.
