---
name: Gas City search for the step-text lint and the until exit
description: The searches the arch check asks for before the change adds its operational surface. tools/lint-step-text.sh judges the procedures a change adds to formula step text, and first-reaction-dispose.sh's until exit leaves a subject to close once the beads it names close. For each, what Gas City, the packs it bundles and publishes, and bd ship for the need, read at named upstream commits, and why the pack's own code covers what they do not. Read it when checking whether the pack still needs the lint or the until exit's reader, or whether Gas City or bd now supplies either.
---

# Gas City search for the step-text lint and the until exit

The change adds operational surface in `tools/lint-step-text.sh` and in the
`until` exit of `assets/scripts/first-reaction-dispose.sh`. Each part below
records what Gas City ships for one of them.

## The step-text lint

`tools/lint-step-text.sh` fails a formula change that adds a procedure to step
text, meaning a shell block that holds control flow or more than one command.
It judges only the lines the change adds. The arch check asks what Gas City
already ships for that ([review-arch.md](../../docs/review-arch.md#the-checks),
check 1). Gas City validates a formula's structure and handles step text only
as a template: it fills in variables when it pours a formula, and its compiler
rejects a reserved variable used wrongly. No command it ships judges the shell
a step holds. Its own formulas, and the packs it publishes, keep procedures in
step text, and the checks they run over that text are tests that judge whole
files. No formula command in `gc` or `bd` returns a file's step text with each
line tied to its place in the file. So the pack checks rule 2 with a lint of
its own, run by the rig's existing lint command.

### The surface and the need

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

### Where the search looked

Each was read on 2026-10-27 (UTC):

- Gas City at main `45563e2abf21`: the CLI reference, the formula
  specification, the pack specification's doctor directory, the `core` pack it
  bundles, its module requirements and its source. The source was searched for
  the lint and formula commands, the formula parser and its `Step` type, the
  compile pipeline, `GC_FORMULA_REF`, the doctor's formula and pack checks, and
  every test or tool that reads a fenced shell block or runs shellcheck. Each
  hit outside the tests was read, and so was each test that reads step text.
- Every pack in Gas City's packs repository, at `dac12a4a802c`: `bmad`, `cass`,
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

### What Gas City ships

**Formula validation is structural.** The
[formula specification](https://docs.gascity.com/reference/specs/formula-spec-v2#1-9-validation)
says "A formula must satisfy these structural rules". They cover the formula's
name, contract and type, its variables, step ids and titles, priorities,
dependencies, and the shape of `check`, `retry`, `drain`, timeouts and loops.
None reads what a step's description holds. One rule outside that list reads
step text, for template variables only. The compiler's reserved-symbol
validation
([Compilation](https://docs.gascity.com/reference/specs/formula-spec-v2#2-compilation))
finds each reference to a variable a v2 formula reserves, `{{convoy_id}}`,
`{{bead_id}}` or `{{issue}}`, in a step's title, description and notes with a
regular expression. It fails the references the
[variables section](https://docs.gascity.com/reference/specs/formula-spec-v2#1-4-variables)
forbids (package formula, `ValidateGraphV2ReservedSymbols`). The
specification's
[Doctor and lint](https://docs.gascity.com/reference/specs/formula-spec-v2#doctor-and-lint)
section names what `gc doctor` and `gc lint` check in formulas. The
`gc doctor` check `formula-requirements` reports parse and inheritance
failures, the deprecated `contract` opt-in, missing v2 requirements and host
mismatches (package doctor, `FormulaRequirementsCheck`). `gc lint` warns on
the deprecated `gc.output_json` fan-out, and "Warnings do not fail lint."

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
`if [ -z "$WORK_BEAD_ID" ]; then`. Gas City's own tests check that text, each
over files Gas City ships. `coreDrainAckBlocks` collects each block fenced as
`bash` in a rendered core step, and `coreDrainAckViolations` reports a
`gc runtime drain-ack` that no fail-closed close of the step precedes in its
own block (package main, `core_formula_drain_ack_test.go`).
`TestQualityGateFallbackInFormulas` pins phrases in the steps of core's
`mol-polecat-base`. The acceptance test `TestDrainAckBeforeExit` wants
`gc runtime drain-ack` on the line before each `exit` in a code block of the
formulas and prompt templates under `examples/`. The dolt pack's tests lift the
shell out of its `mol-dog-stale-db` step, check it with `bash -n` and run it
against stubbed commands (`examples/bd/dolt`). The gastown example's tests run
helper functions they cut out of the `merge-push` step of the bundled
`gastown` pack's `mol-refinery-patrol` (`examples/gastown`). No command runs
any of them on a pack.

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
- `GC_FORMULA_REF` chooses what the formula reader reads (package formula,
  `SourceFromEnv`). Unset, or set to `working-tree` or `HEAD`, it reads the
  files on disk. Set to another git ref, it reads that ref's committed content
  for a path inside a repository (`GitRefSource`), and "an uncommitted or
  untracked file is treated as absent" (`gitRepoAwareFallback`). So
  `gc formula show` could read a formula at the merge base or on disk, but
  either way it answers with the compiled steps of the name that wins in the
  city's layers, with no line.
- [`bd cook`](https://beads.gascity.com/cli-reference/cook) and
  [`bd formula`](https://beads.gascity.com/cli-reference/formula) read bd's
  own formula files. bd's parser decodes a path as TOML only when it ends in
  `.formula.toml`, and as JSON otherwise (package formula, `Parser.ParseFile`).
  So it reads a Gas City formula `<name>.toml` only through the
  `<name>.formula.toml` alias that Gas City links into a scope's
  `.beads/formulas/` to the file that wins the name
  ([formula specification](https://docs.gascity.com/reference/specs/formula-spec-v2#1-1-file-naming-and-layers)),
  and like Gas City's parser it keeps a step's `SourceLocation` out of its
  JSON. [`bd lint`](https://beads.gascity.com/cli-reference/lint) checks
  issues for "missing recommended sections", not formulas.

**Nothing Gas City ships counts the commands in a shell block.** Its module
requires TOML decoders and no Markdown parser. It requires `google/shlex`,
which splits a string into words by the shell's quoting rules and has no
notion of an operator, and uses it to read an agent's shell command as a file
read or a search (packages worker and sessionlog). The core drain-ack test
finds a block by the fence's prefix and a close by a regular expression, the
reserved-symbol validation finds a variable by a regular expression, and
`ScanUnknownFlags` splits lines as described above, each for a purpose of its
own. The dolt pack's test hands a block to `bash -n`, which checks its syntax
and counts nothing.

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
- Tests run procedures where they live. `gastown`'s tests lift bash out of
  its formulas' steps through `tomllib` and run it against stubbed commands.
  At the bundled pin, `tests/test_deacon_dolt_health_guard.sh` does it for the
  `dolt-health` step of `mol-deacon-patrol`. At the head,
  `tests/test_polecat_push_gate.sh` does it for the push gate in the
  `submit-and-exit` step of `mol-polecat-work`, so "what is tested is the text
  an agent reads at pour time". `pr-pipeline`'s
  `tests/test_pr_review_size_guard.py` does the same for the budget refusal in
  `mol-pr-review`. The repository's own
  `tests/test_default_branch_resolution.py` pulls the default-branch
  resolution out of the `gascity` pack's `prepare-worktree` step and out of
  guards in `contributing-to-gascity` and `pr-pipeline` formulas, and runs it
  against git repositories it builds. The `gascity` pack's
  `tests/test_formula_assets.py` pins phrases in its own step descriptions and
  checks that each `description_file` resolves.
- A pack doctor check, `doctor/<name>/run.sh`
  ([pack specification](https://docs.gascity.com/reference/specs/pack-spec#1-2-11-doctor-directory)),
  is how Gas City lets a pack add a check of its own. Its contract hands the
  script the city's root and the pack's directory (package doctor,
  `PackScriptCheck`), so it judges the city as it is, not a change.

None of these checks takes a base revision. Each holds its rule over every file
it reads, and names its exceptions by file or step.

### What the change does with it

Nothing Gas City ships covers the four needs, so the lint is pack code. It
decodes the TOML strings in a formula with Python's `tomllib`, the decoder the
packs' tests use, and ties each decoded line to its file line itself, since
`tomllib` keeps no positions. It finds the fenced blocks in that text and
counts their commands itself, with awk, and it reads the merge base, the
working tree and in-flight heads with git. Its unit is the one Gas City's core
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
formula specification's validation judges the shell in step text, or if a Gas
City command returns a formula file's step text with each line tied to its
place in the file, at a commit or in the working tree. At `45563e2abf21` none
does. The lint should then become that rule, or read its step text through
that command.

## The until exit

`first-reaction-dispose.sh --disposition until --until <bead>` ends a first
reaction on a subject whose whole job is over once another bead lands, such as
the bead that retires the code the subject is about. The edge it writes,
`until`, is bd's own type, a reference that keeps a bead "active until target
closes", and nothing that Gas City, the packs it bundles and publishes, or bd
ships acts on it. Gas City and bd close a bead when other beads close only if
it contains them, as a convoy, an epic or a workflow root does, or if it is a
gate, which closes itself and unblocks the work that waits on it. None of them
closes a bead whose job another bead's landing ends. So the exit composes what
bd ships, the `until` type and an edge write made in one transaction, with the
release the script's other exits use, and the pack's existing reader of
`until` edges closes the subject.

### The surface and the need

The change adds a mode and an option to a script the pack already ships:

- `--disposition until`, an exit of `assets/scripts/first-reaction-dispose.sh`,
  the script that performs a first reaction's disposition. The proactive
  agent's prompt names it with the other exits.
- `--until <bead>`, given once for each bead whose landing ends the subject's
  job.

It adds no bead kind, lifecycle state or metadata key. The edge it writes is
bd's own type, and the release and the landed proof it writes are the ones the
script's other exits write. So it adds no pack noun and needs no warrant
([review-arch.md](../../docs/review-arch.md#the-checks), check 2).

The rule it serves is in
[AGENTS.md](../../AGENTS.md#code-the-deletion-plan-retires-gets-no-new-work).
A problem in code the deletion plan retires that already has a bead of its own
waits on that retirement, closes once the retirement lands, and is sent
nowhere meanwhile. Holding it takes four things:

1. A record on the subject that names each bead whose close ends its job, kept
   where every reader of the store can see it.
2. A subject that nothing offers as work or holds: no route, arm, placement,
   assignee or `blocks` edge.
3. A close of the subject once every bead it names has closed, and not before.
   So the names are recorded whole or not at all.
4. Something that makes that close without a person.

### Where the search looked

Each was read on 2026-10-27 (UTC):

- Gas City at main `a86d05bd73e0`: the CLI reference, the orders tutorial, the
  `core` pack's orders and the scripts they run, and its source. The source was
  searched for each dependency type Gas City names and what reads it, the
  controller's close-event auto-close, `gc convoy check`, `gc session wait`,
  the gate sweep, and `until` written as a dependency type anywhere in its Go,
  docs, TOML and shell. Each hit outside the tests was read.
- The packs the first part lists, in Gas City's packs repository at
  `dac12a4a802c`, and `gastown` and `gascity` at `66c672b5ed00`, the packs
  commit Gas City bundles. Each was searched for an `until` edge in each way of
  writing the type, a gate that awaits a bead, a gate check, an order an event
  triggers, `bd supersede`, `bd duplicate`, `bd epic`, `gc convoy check` and
  `gc convoy land`, `gc session wait`, and prose about closing one bead when
  another closes or lands. Each hit was read.
- bd at main `5011528b3ad5`: its dependency types and every reader of
  `until`, `bd dep add --file`, `bd dep list`, `bd gate` and its bead gate,
  `bd epic close-eligible`, `bd close`, `bd supersede`, `bd duplicate` and
  `bd defer`. The bd the city runs, at `9b65b9e198ac`, was read for the same
  `until` type, readiness rule, bead gate and edge write.

Each passage cited below from Gas City's and bd's documentation was also found
on the live sites, docs.gascity.com and beads.gascity.com.

### What Gas City and bd ship

**bd defines `until`, and nothing acts on it.** bd's dependency types (package
types, `DepUntil`) define `until` as "Active until target closes (e.g., muted
until issue resolved)", among the "Reference types (cross-referencing without
blocking)". `AffectsReadyWork` holds only `blocks`, `parent-child`,
`conditional-blocks` and `waits-for`, so an `until` edge never keeps a bead out
of `bd ready`. bd reads the type only to show it: the `bd` command heads the
edge "ACTIVE UNTIL" in `bd show`, words it "is active until" when `bd dep add`
reports it (`depRelations`), and marks it with an hourglass
(`getRefTypeEmoji`). The
[`bd dep`](https://beads.gascity.com/cli-reference/dep) reference lists `until`
among the types `bd dep add --type` takes, while the
[Dependencies and Gates](https://beads.gascity.com/core-concepts/dependencies)
page leaves it out of both its tables, of blocking and of non-blocking types.
Gas City names no `until` edge. Its readiness reads `blocks`, `waits-for` and
`conditional-blocks` (package beads, `IsReadyBlockingDependencyType`), and its
convoy membership reads `tracks` (package convoy, `TrackingDepType`). No pack,
published or bundled, writes or reads an `until` edge. bd's `delegated-from`
type says "completion cascades up", and like `until` it is read only to show
it.

**What closes a bead when others close contains them, or is a gate.**

- The controller closes a convoy once every member is terminal. On a member's
  `bead.closed` it checks each convoy that parents or tracks the bead, and
  closes one that is still open, not labeled `owned`, and of type `convoy`
  (package main, `doConvoyAutocloseWith` and `convoyStillAutocloses`).
  [`gc convoy check`](https://docs.gascity.com/reference/cli#gc-convoy-check),
  "Auto-close convoys where all issues are closed", and the `core` pack's
  `convoy-autoclose-backstop` order run the same check for a close whose event
  was missed. The same close event closes a molecule root once all its steps
  are terminal, and the workflow roots attached to a closed work bead
  (`doMoleculeAutocloseWith`, `doWispAutocloseWith`).
- [`bd epic close-eligible`](https://beads.gascity.com/cli-reference/epic)
  closes "epics where all children are complete". Nothing in Gas City or its
  packs runs it.
- A gate is a bead that blocks "dependent work until an external condition is
  met"
  ([Dependencies and Gates](https://beads.gascity.com/core-concepts/dependencies#gates)).
  A `bead` gate awaits a bead, and a plain `await_id` names one in the gate's
  own rig (the `bd` command's `beadGateTargetID`). `bd gate check` closes the
  gate once that bead closes, and the work that waits on the gate through a
  `blocks` edge becomes ready. The `core` pack's `gate-sweep` order runs
  `bd gate check` for timer and GitHub gates and skips bead gates, to be
  restored "when beads adds it back". `gastown`'s deacon checks the same kinds.
  So nothing in Gas City as shipped checks a bead gate.
- The `core` pack's other orders that close beads close them by their own age
  or state, not on another bead's close: stale delivered nudges and read mail
  (`nudge-mail-sweep`), stale order-tracking beads (`order-tracking-sweep`),
  and stale or expired wisps (`reaper`, `wisp-compact`).

**What acts on a close closes nothing itself.**

- An order with `trigger = "event"` and `on = "bead.closed"` "fires whenever
  the named event appears on the bus"
  ([Tutorial 07 - Orders](https://docs.gascity.com/tutorials/07-orders)), and
  the order supplies what it runs. The `core` pack's
  `cascade-nudge-on-blocker-close` is one. It reads the closed bead's `blocks`
  dependents and nudges each one's assignee or routed target.
- [`gc session wait --on-beads`](https://docs.gascity.com/reference/cli#gc-session-wait)
  registers "a dependency wait for a session", which wakes the session with a
  note once the beads it names close. The `gascity` and `superpowers` packs
  park a session on its own step that way while a person decides.
- The `core` pack's `cross-rig-deps` order turns a satisfied cross-rig
  `blocks` edge into `related`.
- [`bd supersede --with`](https://beads.gascity.com/cli-reference/supersede)
  and [`bd duplicate --of`](https://beads.gascity.com/cli-reference/duplicate)
  close a bead at once, "with a reference to" another bead, whether or not
  that bead has closed. `bd defer --until` takes a time, not a bead.

**bd writes a set of edges in one transaction.** `bd dep add --file -` reads
edges as JSONL, each with its own type
([`bd dep`](https://beads.gascity.com/cli-reference/dep)), and adds them as
"One request, one transaction, one history entry", all or nothing (the `bd`
command's `addBulkDependencies`). The edges' sources must all resolve to one
store. `bd dep list --direction=down -t until` reads a bead's `until` edges
back. The bd the city runs defines `until`, decides readiness and checks a
bead gate the same way, and writes a `--file` set in the same one transaction.

### What the change does with it

Nothing Gas City or bd ships closes a bead that neither contains the beads it
waits on nor is a gate, so the close stays with the pack's existing reader of
`until` edges. The deferred-dispatch pass closes an open, unassigned bead that
carries no live work once every one of its `until` targets has closed and no
`blocks` blocker of its own is open
([deferred-dispatch.md](../../docs/deferred-dispatch.md#the-resolved-by-consumer-until)).
That reader predates this change, and the built-once target keeps closing on
an `until` edge as a residual of deferred dispatch under a warrant
([built-once-target.md](../../docs/built-once-target.md#work)), which
tk-1tfzr71.16 owes.

The exit adds a writer for what that reader already reads, and each part of it
is bd's or the script's own. The record is bd's `until` type, which bd defines
with this meaning. The write is bd's bulk add in one transaction, so the pass
never reads part of a set and closes the subject while a bead it names is still
open. The read-back is bd's `dep list` by type. The release is
`gc-helm.sh takeaway --release`, which the script's other exits use too, and it
leaves the subject open, unassigned and unrouted. The exit's own glue is the
order of these steps. The edges come after the release, because the edges are
what makes the pass select the subject, and the release writes the subject's
status with no condition, so it would reopen a subject the pass closed while
the release ran. Each edge is then read back by its type, because bd keeps one
edge type per pair of beads
([deferred-dispatch.md](../../docs/deferred-dispatch.md#the-resolved-by-consumer-until)),
so a `blocks` edge the subject already has onto a named bead refuses the whole
write.

Each nearer primitive fails a need above:

- A bead gate on the named bead, with the subject waiting on it, fails needs 2
  to 4. A `blocks` edge would hold the subject, nothing in Gas City checks the
  gate, and a gate that closed would make the subject ready work, which is what
  the blocked exit does, not a close.
- Making the subject a gate, a convoy or an epic over the bead it names would
  change what the subject is to every reader of the store. A report of a
  problem would read as a wait that work blocks on, a group of work, or the
  parent of the work it waits for.
- Superseding the subject now closes it before the retirement lands, while its
  problem is still in the code, so it fails need 3.
- An order triggered by `bead.closed` would still run pack code to find the
  subject and close it. It is a trigger the reader could take in place of its
  five-minute cadence, and the reader's trigger is outside this change.

This answer changes if bd or Gas City acts on an `until` edge, if Gas City's
gate sweep checks bead gates and a gate can close the bead that waits on it,
or if Gas City closes a bead once the beads it names close. At Gas City's
`a86d05bd73e0` and bd's `5011528b3ad5` none does. The exit should then write
what that reader reads, and the pack's reader should retire.
