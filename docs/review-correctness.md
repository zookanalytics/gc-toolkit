---
name: The correctness check on gc-toolkit
description: The method extension the correctness check appends on gc-toolkit reviews. It names the shell, jq and formula-prose defects this repository's lint and tests leave to the reviewer, and the guard that catches the rest of each.
---

# The correctness check on gc-toolkit

gc-toolkit's scripts are bash and jq, and its formulas and skills carry shell
blocks that agents run. Each entry below names a defect class a review here
hunts and the guard that catches part of it, so the review looks hardest where
no guard reaches.

## Scope

**Mandate.** The defect classes particular to gc-toolkit that a correctness
review hunts for, and how much of each the repository's lint and tests catch.

**Boundaries.** The method, its grades and the verdict are pack content, in
`skills/review-correctness/SKILL.md`. The rule a lint detector enforces is
stated in its header under `tools/lint-learned.d/`. The Go services under
`services/` get the method alone.

## What the gates leave to the review

- `tools/lint.sh` shellchecks the `.sh` and shell-shebang files a change names,
  at warning severity (`assets/scripts/shellcheck-run.sh`). An unquoted
  expansion (SC2086) and a variable set in a pipeline's subshell (SC2030,
  SC2031) are info findings, so the gate never reports them. A
  `# shellcheck disable=` directive a change adds hides its finding from the
  gate, so read the reason it gives. A shell block in a formula, skill, prompt
  or doc is never shellchecked.
- Each detector `tools/lint-learned.sh` runs enforces one rule, inside the
  scope its header states, and any other shape is the review's.
- CI runs the suites on Linux and on macOS (`.github/workflows/tests.yml`), so
  a portability defect fails a job only on a line some test executes.

## Shell and jq

- **Unquoted expansions.** bash splits and globs an unquoted `$VAR`, so check
  each one whose value can be empty or hold a space or a glob character.
- **Errexit and pipelines.** Most scripts set `-u` or `-uo pipefail` without
  `-e`, so check that each command whose failure matters is tested where it
  runs, with `|| rc=$?`, `if !` or `|| exit`. Without pipefail,
  `gc bd list … | jq …` returns jq's status, and a failed read passes as an
  empty one. With pipefail, `… | grep -q` can fail on a match, because grep
  exits at the first one and a writer with more to write dies of SIGPIPE
  (`pipefail-grep-q.sh`). Under `set -e`, a `[ … ] && x=1` that ends a function
  or a sourced block kills the caller on the false path, which
  `crash-loop-window.test.sh` pins by sourcing its block under `bash -eu`.
- **Masked exit codes.** shellcheck reports `local x=$(cmd)` and its `export`,
  `declare` and `readonly` forms (SC2155). It does not report
  `if ! x=$(cmd); then rc=$?`, where `$?` is the negation's 0, or an `rc=$?`
  after `x=$(cmd) || true`. The repository's form is `x=$(cmd) || rc=$?`.
- **Variables lost in subshells.** An assignment, an array append or an `exit`
  inside a command substitution, a pipeline stage or a `( … )` group never
  reaches the caller, and the caller's EXIT trap does not fire there. The
  repository keeps such state in the caller's shell: `mktemp_tracked` in
  `assets/scripts/deferred-dispatch.sh` answers in `REPLY` instead of on
  stdout, and `assets/scripts/converse-reap.sh` loops over a checked temp file
  with `done < "$FILE"` instead of a pipe. A `<<<` here-string is not that file:
  bash writes a large one to a temp file of its own, and when that cannot be
  written the loop runs zero times and reports an empty queue.
- **Unreadable read as empty.** `jq -r '.x'` prints the string `null` for a
  missing key, which passes `[ -n "$X" ]`, and `.x // empty` prints nothing.
  Nothing is also what comes back from a store that did not answer, from input
  jq could not parse, and from a `2>/dev/null` that hid either. Unreadable is
  not empty here (`assets/scripts/deferred-dispatch.sh`,
  `assets/scripts/gate-visit-sweep.sh`): a read whose emptiness decides
  anything checks its exit status, and an unreadable answer holds or fails
  closed. A raw control byte in a JSON string makes jq refuse the whole
  payload, so store text goes through the shared `scrub` helper first, and
  `inline-ctrl-scrub.sh` flags a scrub written inline.
- **jq's `//`.** It replaces `false` as well as null, so `.enabled // true` is
  true for an explicit false, and it does not catch an error raised on its
  left. `id-read-unguarded.sh` flags `.id // .[0].id` on a bd answer, and any
  other `a // b` over a value of uncertain shape needs a type guard.
- **jq versions.** jq 1.7 does not compile a bare `if … end` or `reduce …`
  followed by `as`, `[i]` or `.key`, and jq 1.8 does. The host runs 1.8, and
  its `/usr/bin/jq` is 1.7. The Linux CI job runs the jq of its Ubuntu image,
  1.7 on 24.04 and 1.8 on 26.04, so such a program can pass on the host and
  fail on Linux. Parenthesize the term, and probe with `/usr/bin/jq`.
- **BSD and GNU userland.** The host is macOS: `sed`, `grep`, `awk`, `date`,
  `stat` and `find` are BSD, `/bin/bash` is 3.2, and `#!/usr/bin/env bash`
  finds bash 5. Where the userlands disagree, the repository tries both
  spellings, as `epoch_of` in `assets/scripts/gc-deacon-ledger.sh` does for
  `date` and `mtime_of` in `formulas/mol-deacon-patrol.toml` does for `stat`,
  or writes the one form both accept, such as `sed -i.bak … && rm -f ….bak`
  for an in-place edit.

## Shell blocks in formula prose

An agent pastes a formula step's shell blocks into its own tool shell. Review a
block as that shell runs it.

- **Write for zsh as well as bash.** A block runs in whatever shell the agent
  has, and a Claude Code agent's is zsh. zsh leaves an unquoted `$VAR`
  unsplit, so `for x in $LIST` and `cmd $FILES` each get one word, while an
  unquoted `$(…)` is split. `formula-unquoted-for.sh` flags only the `for`
  form. An unbraced name before a colon can take a zsh modifier that rewrites
  what follows, so `"$REV:review-checks.toml"` reaches git as
  `<rev>eview-checks.toml`. The name is braced, `"${REV}:…"`, and
  `zsh-colon-modifier.sh` flags the unbraced form. zsh's `echo` expands the
  backslash escapes in JSON, so JSON reaches jq through `printf '%s'`, never
  `echo "$X"`. `candidate-pipeline.test.sh` runs its block under
  `bash -O xpg_echo` and `zsh -f` to catch it.
- **Each block starts in a fresh shell.** Nothing an earlier block or step set
  survives, so a block sets every variable it reads, the claimed step's id
  included, and resolves each script path itself.
- **`set -e` stops nothing.** In the Claude Code tool shell a block runs on
  past a failed command even after `set -e`, so a block gates each write with
  `if` or `|| exit`. Suites source some blocks under `bash -eu`, so a block
  also has to complete under errexit.
- **TOML decodes the block first.** Formula descriptions are TOML basic
  strings. `\\` in the file is one backslash, a backslash before a character
  TOML does not escape, such as `\$`, stops the formula from parsing, and a
  backslash at the end of a line joins the next line to it. A suite that
  extracts a region with awk reads the raw file instead, so a backslash in the
  region makes it test text the agent never runs, and `lease-heartbeat.test.sh`
  asserts its regions hold none.
- **A rendered var is raw text.** A pour writes each `{{var}}` into the step as
  it stands, so a var that holds a command, quotes and all, reaches the block
  through a quoted heredoc, never inside quotes. The test command in
  `formulas/mol-polecat-work.toml` arrives that way, and
  `lease-heartbeat.test.sh` runs it rendered.

## Marker-fenced blocks

A `# >>> <name>` line and a `# <<< <name>` line fence a block that a test runs.
In a formula or a skill the fence marks step shell that a suite extracts and
executes. In scripts it marks a shared helper that each file needing it carries
as a copy, because neither formulas nor pack scripts have an include mechanism.

- **Read the suite that names the block.** `formula-marker-coverage.test.sh`
  fails when no suite names a formula's marker, but not when the naming suite
  stops asserting what the block does. When a block's behavior changes, find
  its suite with `git grep -l -F -e '<name>' -- '*.test.sh'` and check that a
  case pins the change.
- **The markers are the contract.** An extracting suite matches the exact
  marker line and fails on an empty extraction, so renaming or duplicating a
  marker changes its suite in the same diff.
- **Only the region is tested.** Lines in the same code fence outside the
  markers run untested, unless the suite reads past the closing marker as
  `lease-heartbeat.test.sh` does.
- **Copies change together.** A helper's suite, such as
  `control-char-scrub.test.sh` or `doctor-budget.test.sh`, finds its copies by
  sweeping named directories and executes each one. An edit to one copy is
  owed to every copy, and a copy outside the swept directories is held by no
  suite.
