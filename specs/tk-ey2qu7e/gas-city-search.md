---
name: Gas City search for weighing a skill's shell blocks
description: The search AGENTS.md asks of a change that grows a script's surface, made for the mode tools/lint-step-text.sh gains, which weighs the shell blocks a change adds to a skill as it weighs formula step text. What Gas City and bd ship that reads a skill, at named upstream commits, and why none of it covers the need. Read it when checking whether the pack still needs the skill mode, or whether Gas City or bd now judges a skill's shell.
---

# Gas City search for weighing a skill's shell blocks

## The surface and the need

`tools/lint-step-text.sh` gains a mode. Besides a formula's step text, it now
reads the Markdown files of a skill that a change names, and fails a change that
adds a procedure to a skill's shell blocks, by the rule
[pack-authoring.md](../../docs/pack-authoring.md#step-text-calls-a-tested-script)
states. The change adds no script, order, bead kind, metadata key or lifecycle
state. `tools/lint.sh`, the rig's lint command, already hands the lint every
file a change names, so the self-review and the merge gate reach the new mode
through results they already read.

Holding the rule for skills takes three things:

1. Each skill file a change names, at the merge base and in the working tree,
   read line by line, with each line tied to its file and its line.
2. A count of the commands and the control flow in each shell block.
3. A judgment of only what the change adds, which pairs a block with its old
   self wherever it moved, across a skill's files and between skills.

The lint already holds the second and the third for formulas. The search asks
whether Gas City or bd holds any of them for skills.

## Where the search looked

Each was read on 2026-11-23 (UTC):

- Gas City at upstream main `dfd5200c3ee3` (gastownhall/gascity): the CLI
  reference's `gc lint` and `gc skill` sections (`docs/reference/cli.md`); the
  source of `gc lint` (`cmd/gc/cmd_lint.go`, `cmd/gc/prompt.go`), of the skill
  commands and the skill catalog (`cmd/gc/cmd_skill.go`,
  `cmd/gc/skill_integration.go`, `internal/materialize/skills.go`), of the
  doctor's skill checks (`internal/doctor/skill_checks.go`,
  `internal/doctor/skill_dangling_sink_check.go`) and of their validation
  (`internal/validation/skill_collision.go`); and the core pack's skills
  (`internal/bootstrap/packs/core/skills`) and every test that names one. The
  source was searched for every file outside the tests that names `SKILL.md`,
  and for every Go file outside the tests that holds a Markdown code fence.
- bd at v1.3.4, the version Gas City's `go.mod` requires at that commit:
  `bd lint` (`cmd/bd/lint.go`) and the setup command's skill install and check
  (`cmd/bd/setup/agent_skill.go`).

## What Gas City ships

**`gc lint` reads no skill.** The CLI reference says `gc lint <pack>`
"validates the pack.toml file, reports non-fatal loader warnings, and parses
prompt templates". In the source, `lintPack` runs the pack loader,
`lintNamedSessionPoolConflicts`, `lintFormulaFiles`, `lintPrompt` over the
targets `collectLintPromptTargets` gathers, and `lintClaudeOverlayHookShape`.
A prompt target is an agent's prompt template, or a file whose name
`isPromptTemplatePath` accepts, one that ends in `.template.md` or `.md.tmpl`,
so a skill's `SKILL.md` is never one. `cmd/gc/cmd_lint.go` never names a skill.

**What reads a skill reads its frontmatter.** `gc skill list` lists the skills
a city or an agent sees (`discoverSkillDirEntries`). The catalog that
materializes skills into an agent's sinks takes each `SKILL.md`'s `name` and
`description` from its frontmatter, and reads only the file's first 64 lines
(`readSkillFrontmatter`). The doctor has two skill checks. `skill-collision`
reports two agent-local skills of one name in one sink (`SkillCollisionCheck`,
over `validation.ValidateSkillCollisions`), and `skill-dangling-sink` reports a
dangling symlink in a skill sink (`SkillDanglingSinkCheck`). Neither reads a
skill's body.

**The code that reads a Markdown code fence reads Gas City's own tutorials.**
Outside the `_test.go` files, three Go files hold a run of three backticks. Two
write a fence: the CLI reference's generator (`internal/docgen/cli.go`), and
the formula parser's note for a step whose `description_file` is too large to
inline, which lists the formula's variables in a fenced block
(`descriptionFileReferenceDescription`). One reads fences: the acceptance
goldens' snapshot (`test/acceptance/tutorial_goldens/snapshot.go`, built only
with the `acceptance_c` tag), which collects each fenced snippet of Gas City's
tutorial pages. None reads a pack's skill.

**The core pack's skills hold single commands, and no rule says they must.**
None of the shell blocks in its seven skills holds a pipe, `&&` or `;`. Two
tests read a core skill, both `skills/gc-work/SKILL.md`, and each looks for
words. `pack_formulas_test.go` pins its prose about `--claim`, and
`cmd/gc/prompt_test.go` fails on a `bd ready --include-ephemeral` written in
it. Neither weighs its shell.

## What bd ships

`bd lint` checks beads, not files: its help says "Check issues for missing
template sections", by issue type. bd's setup command writes bd's own
`SKILL.md` and checks it (`installAgentSkill`, `checkAgentSkill`), and the
check compares the installed file with bd's template. Nothing in bd reads
another skill.

## Why the pack's lint covers it

Nothing Gas City or bd ships reads a skill's shell, so none of the three things
the rule needs exists upstream. The step-text lint already holds the count and
the judgment. Its skill mode gives the same parser a skill's lines in place of
a formula's decoded strings, and gives the same judge each skill as a step, so
the rule for skills reuses the code that holds it for formulas.

The mode has no need left once Gas City or bd ships a check that weighs the
shell blocks in a pack's text, or once the pack's skills hold no shell blocks
to weigh.
