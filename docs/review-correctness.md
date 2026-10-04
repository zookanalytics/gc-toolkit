---
name: Correctness review — this rig's extension
description: The gc-toolkit extension to the generic correctness check. The pack is mostly shell, so shell static analysis (bash -n plus shellcheck, run fail-closed through assets/scripts/shellcheck-run.sh) is part of whether a change is correct and safe as merged, and an unrunnable linter is a finding rather than a pass. The dispatch body appends this to every correctness review from the reviewed commit.
---

# Correctness review — this rig's extension

The pack is mostly shell: `assets/scripts/*.sh` is the product. Shell static
analysis is therefore part of whether a change is correct and safe as merged,
and it is in the correctness bar, not optional.

## Lint every changed shell file, through the one runner

For each shell file the diff touches — `*.sh`, including `*.test.sh` — the
correctness bar is two static checks:

- `bash -n <file>` for syntax.
- shellcheck for lint, run through `assets/scripts/shellcheck-run.sh <files>`.

`shellcheck-run.sh` is the single way to run shellcheck here. It runs the host
`shellcheck` at `warning` severity. Run it rather than probing
`command -v shellcheck` yourself: a bare probe that finds nothing lets the lint
silently not happen while the review still reads clean.

## An unrunnable linter is a finding, not a pass

`shellcheck-run.sh` exits non-zero (3) when no `shellcheck` is on PATH. A review
that could not run shellcheck has not met the shell correctness bar. Raise it as
a finding and withhold the pass.
Clearing a shell change because the linter was unavailable is the failure this
extension exists to prevent.

## The suppression annotations are load-bearing

The scripts carry `# shellcheck disable=<code>` directives, each with an inline
justification, and they are verified only when shellcheck actually runs. A
change that adds a suppression states why the finding is a false positive on
that line; the review confirms the suppression is still warranted rather than
masking a real issue.
