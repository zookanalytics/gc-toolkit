---
name: Gas City search for the step-text lint
description: The search the arch check asks for before tools/lint-step-text.sh judges the procedures a change adds to formula step text. What Gas City, the packs it bundles and publishes, and bd ship for validating a formula, reading its step text and judging the shell in it, read at named upstream commits, and why the pack checks rule 2 with a lint of its own. Read it when checking whether the pack still needs the lint, or whether Gas City now checks step text itself.
---

# Gas City search for the step-text lint

`tools/lint-step-text.sh` fails a formula change that adds a procedure to step
text, meaning a shell block that holds control flow or more than one command.
It judges only the lines the change adds. The arch check asks what Gas City
already ships for that ([review-arch.md](../../docs/review-arch.md#the-checks),
check 1). Gas City validates a formula's structure and never reads what its
step text holds. Its own formulas, and the packs it publishes, keep procedures
in step text, and the checks they run over that text are tests that judge
whole files. No formula command in `gc` or `bd` returns a file's step text with
each line tied to its place in the file. So the pack checks rule 2 with a lint
of its own, run by the rig's existing lint command.

## The surface and the need

The change adds one script and the list it reads:

- `tools/lint-step-text.sh`, which `tools/lint.sh` runs on the files a change
  names. `tools/lint.sh` is the rig's lint command, so the self-review's check
  loop and the merge gate reach the new lint through results they already
  read.
- `tools/lint-step-text.in-flight`, the branches whose formula changes were
  built before the rule.

It adds no bead kind, lifecycle state or metadata key, so it adds no pack noun
and needs no warrant ([review-arch.md](../../docs/review-arch.md#the-checks),
check 2).

The rule it holds is rule 2 of the built-once target
([built-once-target.md](../../docs/built-once-target.md#the-rules)), stated in
[pack-authoring.md](../../docs/pack-authoring.md#step-text-calls-a-tested-script).
Holding it takes four things:

1. A rule about what a step's text holds.
2. Each formula file's step text decoded as the agent reads it, with each line
   tied to the file line it came from. The lint reads it at the change's merge
   base, in the working tree and at an in-flight branch's head.
3. A count of the commands and the control flow in each shell block.
4. A judgment of only the lines the change adds, so step text that predates
   the rule passes until its own rewrite.

## Where the search looked

Each was read on 2026-10-27 (UTC):

- Gas City at main `45563e2abf21`: the CLI reference, the formula
  specification, the pack specification's doctor directory, the `core` pack it
  bundles, its module requirements and its source. The source was searched for
  the lint and formula commands, the formula parser and its `Step` type, the
  compile pipeline, `GC_FORMULA_REF`, the doctor's formula and pack checks, and
  every test or tool that reads a fenced shell block or runs shellcheck. Each
  hit outside the tests was read, and so was each test that reads step text.
- Every pack Gas City publishes, at `dac12a4a802c`: `bmad`, `cass`,
  `compound-engineering`, `contributing-to-gascity`, `discord`, `gascity`,
  `gastown`, `github`, `gstack`, `oversight-rig`, `pr-pipeline`, `pr-review`,
  `profiler`, `runtime-cloudflare`, `slack-channel`, `slack-full`,
  `slack-mini` and `superpowers`, and the repository's own CI workflow and
  tests. Each was searched for code that decodes formula TOML, for `lint`, for
  tests that read a fenced block out of step text, and for prose that rules on
  shell in step text, and each hit was read. Gas City bundles `gastown` and
  `gascity` from the packs at `66c672b5ed00`, and the same search ran there.
- bd at `2ef4df339a44`: `bd lint`, `bd formula`, `bd cook` and the formula
  parser behind them.

Each passage cited below from Gas City's and bd's documentation was also found
on the live sites, docs.gascity.com and beads.gascity.com.

## What Gas City ships

**Formula validation is structural.** The
[formula specification](https://docs.gascity.com/reference/specs/formula-spec-v2#1-9-validation)
says "A formula must satisfy these structural rules". They cover the formula's
name, contract and type, its variables, step ids and titles, priorities,
dependencies, and the shape of `check`, `retry`, `drain`, timeouts and loops.
None reads what a step's description holds. Its
[Doctor and lint](https://docs.gascity.com/reference/specs/formula-spec-v2#doctor-and-lint)
section names the two checks Gas City runs over formulas. The `gc doctor` check
`formula-requirements` reports parse failures, the deprecated `contract`
opt-in, missing v2 requirements and host mismatches (package doctor,
`FormulaRequirementsCheck`). `gc lint` warns on the deprecated
`gc.output_json` fan-out, and "Warnings do not fail lint."

**`gc lint` runs a fixed set of checks, and none reads step text.** The
[CLI Reference](https://docs.gascity.com/reference/cli#gc-lint) says it
validates "the pack.toml file, reports non-fatal loader warnings, and parses
prompt templates". In the `gc` command's source, `lintPack` runs the pack
loader, a check for named-session pool conflicts, `lintFormulaFiles`, the
prompt templates and the Claude overlay hook shape. `lintFormulaFiles` parses
each file in the pack's `formulas/` directory and reports only
`formula.GraphV2OutputJSONWarnings`, and it skips a file that does not parse.
`lintPrompt` scans each agent's prompt template, and every `*.template.md` or
`*.md.tmpl` file in the pack, for `bd` flags that bd does not know (package
bdflags, `ScanUnknownFlags`). That scan splits each line on unquoted
separators and on whitespace, and it joins no continued lines. A formula is
neither, so the scan never reads step text. The checks are Go functions that
`lintPack` calls in turn, and nothing in a pack adds one.

**Gas City's own step text holds procedures.** Under the specification's
[data model](https://docs.gascity.com/reference/specs/formula-spec-v2#0-2-data-model),
"Agents execute only plain work beads", and the orchestrator runs the control
beads. A step's work is its `Description` or its `DescriptionFile` (package
formula, `Step`). Its other fields name, route and control the step, and none
makes the step's work a script that something other than an agent runs. A
[check](https://docs.gascity.com/reference/specs/formula-spec-v2#3-1-check)
does name a script, but "after each iteration closes, the orchestrator runs
the configured script" to judge the agent's work, not to do it. The `core`
pack's `mol-do-work` keeps shell blocks with control flow in its `do-work` and
`drain` steps, such as the block in `do-work` that opens
`if [ -z "$WORK_BEAD_ID" ]; then`. Gas City checks one property of that text
in its own test suite. `coreDrainAckBlocks` collects each block fenced as
`bash` in a rendered core step, and `coreDrainAckViolations` reports a
`gc runtime drain-ack` that no fail-closed close of the step precedes in its
own block (package main, `core_formula_drain_ack_test.go`). It tests core's
formulas, and no command runs it on a pack.

**No formula command returns step text with its lines.**

- `gc formula show <name> --json`
  ([CLI Reference](https://docs.gascity.com/reference/cli#gc-formula-show):
  "Compile and display a formula recipe") needs a city. It finds the formula by
  name in the city's formula search paths and compiles it
  (`newFormulaShowCmd`, `formula.CompileWithoutRuntimeVarValidation`), which
  resolves inheritance and applies control flow, advice, expansions, aspects,
  conditions and Ralph checks. Each step in its JSON (`formulaStepJSON`)
  carries an id, title, description, notes, type, priority, labels, assignee,
  root flag and metadata, and no file or line. The parser keeps a
  `Step.SourceLocation`, a place such as `steps[0]`, and does not serialize it.
  So the command returns the compiled steps of whichever formula wins a name
  in the city, not the text of a given file at a given commit.
- `GC_FORMULA_REF` reads formula files at a git ref (package formula,
  `SourceFromEnv` and `GitRefSource`). Inside a repository it reads committed
  content only, and "an uncommitted or untracked file is treated as absent"
  (`gitRepoAwareFallback`). The lint's new side is the working tree, before any
  commit.
- [`bd cook`](https://beads.gascity.com/cli-reference/cook) and
  [`bd formula`](https://beads.gascity.com/cli-reference/formula) read bd's
  own formula files. bd's parser decodes a path as TOML only when it ends in
  `.formula.toml`, and as JSON otherwise (package formula, `Parser.ParseFile`),
  so a Gas City formula named `<name>.toml` does not parse.
  [`bd lint`](https://beads.gascity.com/cli-reference/lint) checks issues for
  "missing recommended sections", not formulas.

**Nothing Gas City ships counts the commands in a shell block.** Its module
requires TOML decoders and no shell or Markdown parser. Its drain-ack test
finds a block by the fence's prefix and a close by a regular expression, and
`ScanUnknownFlags` splits lines as described above, each for a purpose of its
own.

**The published checks judge whole files.**

- The packs repository's CI runs `gc lint` on a list of its packs
  (`.github/workflows/ci.yml`, "Lint and exercise shared role prompt
  composition"). It checks `gastown`'s findings against a pinned set
  (`tests/gastown_lint_upstream_defects.txt`).
- Its `tests/test_v2_drain_ack_closes_own_step.py` holds the same drain-ack
  rule over named steps of `gastown` and `pr-pipeline` formulas, which it
  decodes with Python's `tomllib`. Its exceptions are fixed lists of deferred
  steps and exempt formulas. Its `tests/test_no_bare_bd_commands.py` checks
  that the packs' shipped files route `bd` commands through `gc`.
- Two packs test a procedure where it lives. `gastown`'s
  `tests/test_polecat_push_gate.sh` lifts the push gate's bash out of the
  `submit-and-exit` step of its `mol-polecat-work` and runs it against stubbed
  `gc` and `git`, so "what is tested is the text an agent reads at pour time".
  That test is at the packs' head and not at the bundled pin. `pr-pipeline`'s
  `tests/test_pr_review_size_guard.py` does the same for the budget refusal in
  `mol-pr-review`. The `gascity` pack's `tests/test_formula_assets.py` pins
  phrases in its own step descriptions and checks that each
  `description_file` resolves.
- A pack doctor check, `doctor/<name>/run.sh`
  ([pack specification](https://docs.gascity.com/reference/specs/pack-spec#1-2-11-doctor-directory)),
  is how Gas City lets a pack add a check of its own. Its contract hands the
  script the city's root and the pack's directory (package doctor,
  `PackScriptCheck`), so it judges the city as it is, not a change.

None of these checks takes a base revision. Each holds its rule over every file
it reads, and names its exceptions by file or step.

## What the change does with it

Nothing Gas City ships covers the four needs, so the lint is pack code. It
decodes the TOML strings in a formula, finds the fenced blocks in them and
counts their commands itself, with awk, and it reads the merge base, the
working tree and in-flight heads with git. Its unit is the one Gas City's
drain-ack test uses, a fenced shell block of decoded step text, which is what
an agent runs as one command. It parts from the published checks in judging
only what a change adds, because the rule exempts existing step text until its
own rewrite. So its exceptions are the branches built before the rule, not
fixed steps. It runs inside `tools/lint.sh`, the rig's lint command, and adds
no check of its own to a loop or a gate. Running `gc lint` as well would add
the checks it makes, not this rule. The lint adds no pack noun, so it needs no
warrant, and it keeps no pack state in step with Gas City's, so it is no
converter.

The search found one limit of the lint. A step's text can also live in a
Markdown file that `description_file` names
([formula specification](https://docs.gascity.com/reference/specs/formula-spec-v2#1-8-description-files)),
and the lint reads only the text written inline in the formula. No gc-toolkit
formula sets `description_file`. tk-o55szzi extends the lint to that file, and
it waits on this change.

This answer changes if `gc lint` takes a rule that a pack declares, if the
formula specification's validation reads what step text holds, or if a Gas
City command returns a formula file's step text with each line tied to its
place in the file, at a commit or in the working tree. At `45563e2abf21` none
does. The lint should then become that rule, or read its step text through
that command.
