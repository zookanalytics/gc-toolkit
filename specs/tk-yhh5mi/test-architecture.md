# Phase 1 — Test architecture for `assets/scripts/*.sh`

Bead: `tk-yhh5mi` · Convoy: `tk-aezem4` · Branch: `integration/smoke-tests`

This doc is the decisions artifact for Phase 1 of the smoke-tests
mol. It inventories every structured-output consumer in
`assets/scripts/*.sh`, surveys testing approaches, recommends one
(or a hybrid), and outlines Phases 2–5. No executable code is
introduced in this phase.

## 0. Provenance

No external testing patterns were imported as text or code. Bats,
shellspec, and shunit2 are referenced by name in the survey
section below as comparable shell-test frameworks but their
sources, docs, and READMEs were not copied or paraphrased into
this document — the comparison is from prior knowledge of their
shape. If Phase 2 decides to vendor or adopt one, that polecat
will add the provenance row at that time.

Internal audit (this repo's scripts at HEAD of
`integration/smoke-tests`) is not a provenance row per mechanik's
rule.

## 1. Inventory

### 1.1 Method

`grep -nE '(--json|jq |gc bd|gc session|gc mail)' assets/scripts/*.sh`
plus a manual read of every file in `assets/scripts/` at HEAD of
`integration/smoke-tests`. Files with no structured-output
consumption (`consult-attach.sh`, `tmux-bindings.sh`,
`tmux-status-line-override.sh`, `worktree-setup.sh`,
`tmux-pick-session.sh`) are listed for the empty-row audit at the
bottom of this section.

The inventory matrix below counts a row for every site where the
script reads structured output from a `gc` (or `bd`) subprocess —
JSON parsed by jq or Python (the PR #37 bug class) plus
plain-text parsed by awk (a related bug class flagged for the
recommendation). Each script's section also fields the
`gc <cmd> --json-schema` answer for the underlying command.

### 1.2 Matrix

| # | Script | Line | Producer command | Consumer | Parser | Schema paths referenced |
|---|---|---|---|---|---|---|
| 1 | `cockpit.sh` | 163 | `gc bd list "$@" --json` | inline `python3 -c` | Python `json.load` | `[].status`, `[].priority`, `[].id`, `[].title` |
| 2 | `cockpit.sh` | 216 | `gc bd list --rig <rig> --status in_progress --assignee <rig>/gc-toolkit.refinery --json` | written to a per-rig file, then read by `$RIGS_PY` | Python `json.load` | `[0].title` (via `rs[0].get("title", "")`) |
| 3 | `cockpit.sh` | 347 → 223 | `gc session list --json` | piped to `$RIGS_PY` (heredoc-defined Python script) | Python `json.load` | `[].Closed`, `[].Template`, `[].State` *(treats output as a top-level array of PascalCase records — see §1.3)* |
| 4 | `cockpit.sh` | 347 → 236 | `gc session list --json` (same as row 3, re-piped) | inline `python3 -c` | Python `json.load` | `[].Closed`, `[].State`, `[].ID`, `[].Template` *(same shape mismatch as row 3)* |
| 5 | `gc-toolkit-status-line.sh` | 88–91 | `gc session list --state active --json` | piped to `jq` | `jq -r --arg a` | `map(select(.AgentName == $a)) | .[0].Title` *(broken — see §1.3; PR #37 fix lives on a polecat branch not yet merged to integration)* |
| 6 | `tmux-spawn-thread.sh` | 207 | `gc session list` (no `--json`) | piped to `awk` | `awk` field split | column 1 = id, column 3 = state |
| 7 | `tmux-spawn-thread.sh` | 190 | `gc session new ... 2>&1` | `sed -n 's/^Session \([^ ]*\) created.*/\1/p'` | `sed` regex | producer must emit `Session <id> created` on first matching line |
| — | `consult-attach.sh` | — | (none) | — | — | — |
| — | `tmux-bindings.sh` | — | (none) | — | — | — |
| — | `tmux-pick-session.sh` | — | (none — consumes `tmux list-sessions`/`list-panes`, not `gc`) | — | — | — |
| — | `tmux-status-line-override.sh` | — | (none) | — | — | — |
| — | `worktree-setup.sh` | — | (none) | — | — | — |

Schema-path notation: `[]` = top-level array element; `[i]` = i-th
element; field path is dotted from there.

Total: 7 active rows across 3 scripts; 5 empty rows for files in
scope with no structured-output consumption (`consult-attach.sh`,
`tmux-bindings.sh`, `tmux-pick-session.sh`,
`tmux-status-line-override.sh`, `worktree-setup.sh`) — per the
bead's "empty file → empty row is fine" rule.

(`tmux-pick-session.sh` consumes only `tmux list-sessions` and
`tmux list-panes` output, not `gc`. It is flagged in the bead
description as a future row "after `tk-slncyq` lands" but
`tk-slncyq` has landed on `integration/smoke-tests` without
introducing a `gc session list --json` call yet — verified by
re-grepping the file at HEAD.)

### 1.3 Findings from the inventory

Two facts emerged during the audit that materially shape the
recommendation:

**Finding A — `gc bd list` publishes no schema.**
`gc bd list --json-schema` returns
`{"json_supported": false, "schemas": {}}`. The command emits
JSON when invoked with `--json` (top-level array of bead objects
with snake_case fields), but no `--json-schema` contract is
exposed. Captured shape from a live call lives at
`schemas/bd-list.json` for the record. **Three of the seven
inventory rows depend on this undocumented shape**; any approach
that requires `--json-schema` to be authoritative needs a
workaround for `bd list`.

**Finding B — `gc session list` publishes a schema; current
consumers do not match it.**
`gc session list --json-schema` declares the output is an object
`{schema_version, filters, sessions: [<session-objects>],
summary}` with snake_case fields on each session
(`agent_name`, `state`, `title`, `id`, `template`, ...). Live
output confirms this. But cockpit.sh's Python and the
status-line.sh jq query both consume `gc session list --json` as
a *top-level array of PascalCase records*. PR #37 (tk-foudmx) is
the fix for status-line.sh; that PR exists on a polecat branch
but has not merged to `main` or `integration/smoke-tests`.
**Rows 3, 4, and 5 are all silently miscompiling against the
real schema today** — exactly the bug class the mol is being set
up to prevent.

### 1.4 Schemas archived

| `gc <cmd>` | Schema artifact | Authoritative? |
|---|---|---|
| `gc session list` | `schemas/session-list.json` (output of `gc session list --json-schema`) | yes — published by the command |
| `gc bd list` | `schemas/bd-list.json` (hand-captured shape + the publisher's no-schema response) | no — see Finding A |
| `gc session list` (plain-text variant, row 6) | none | non-`--json` output has no machine-readable contract |
| `gc session new` (plain-text, row 7) | none | non-`--json` output has no machine-readable contract |

## 2. Approaches surveyed

### A. Schema-pinned static check

A test manifest enumerates `(script, gc-cmd, paths-referenced)`
tuples. The runner fetches `gc <cmd> --json-schema` for each
unique command, walks each path, and fails when the path doesn't
resolve in the schema. No fixtures, no script execution, no gc
daemon state — `--json-schema` is pure introspection.

- **Catches**: wrong field name (case, snake vs Pascal), missing
  array unwrap (`.sessions`), referenced field absent from
  schema entirely.
- **Misses**: jq/python logic bugs that produce a wrong value
  despite valid paths (e.g. `.[0]` when the array is empty),
  behavioral regressions in the surrounding shell code, any
  inventory row whose command publishes no schema (Finding A
  rules out all `gc bd list` rows).
- **Cost**: ~10–50 ms per check. Zero fixtures. Manifest is
  hand-maintained; drift between manifest and script is itself a
  bug class.

### B. Fixture-driven smoke

A captured `gc <cmd> --json` payload lives as a JSON file in the
repo. Each script grows a narrow input-override seam — environment
variable holding a path to the fixture, or `stdin` mode — and the
runner pipes the fixture in and asserts on the script's
user-visible output (status-line title, cockpit row, etc.).

- **Catches**: A's full coverage PLUS the logic regressions A
  misses — wrong jq filter, wrong Python field access, wrong
  truncation behavior, missing fallback. Catches the row-6/row-7
  cases (plain-text consumers) by capturing the producer's
  plain-text output as a fixture too.
- **Misses**: drift between fixture and the real producer when
  the producer's output schema changes silently. Mitigated by a
  fixture-refresh harness that diffs captured vs live and fails
  on drift — that harness has to run somewhere (CI step or
  developer-on-demand), and someone has to acknowledge the diff
  before promoting the new fixture.
- **Cost**: real bootstrapping. Every script under test grows
  an env-override or stdin-mode seam (small but non-zero).
  Fixtures need a refresh story. Runtime ~10–50 ms per test
  once the seam exists.

### C. Real-gc integration

The runner spins up isolated state (`bd --db /tmp/test-...`,
ephemeral session, etc.) and runs the actual `gc <cmd>` against
a sandboxed environment. The script under test runs against
that live state and the runner asserts on its real output.

- **Catches**: everything A and B catch, plus producer-side
  regressions (the script's view of reality stays correct even
  when gc itself drifts).
- **Misses**: nothing schema-related.
- **Cost**: highest. Needs a sandboxed Dolt server (Dolt is
  shared per the user's "gc dolt cleanup" warning about orphan
  databases; a real-gc test must not write to the production
  server). Needs ephemeral session lifecycle (`gc session
  new --no-attach` followed by teardown). Brittle to gc version
  skew — every version bump is a test-suite update. Slow:
  hundreds of ms to seconds per test.

### D. Sub-survey — shell-test frameworks (bats, shellspec, shunit2)

None of A/B/C prescribe a runner. The runner can be a hand-rolled
`tests/smoke/run.sh` or a vendored framework. bats is the most
common choice in Anthropic-adjacent repos that ship with
shell-script test suites. Trade-off in this repo:

- gc-toolkit currently has zero test infra and no test-related
  dev dependencies. A hand-rolled `tests/smoke/run.sh` is ~50
  lines and adds zero deps — appropriate for the size of the
  surface (3 scripts, 7 rows, ~250 LOC under test). bats adds a
  binary dep (or a vendored `bats-core/` tree) and a learning
  curve for whoever writes Phase 3 tests.
- The recommendation below is hand-rolled. Phase 2 can revisit
  if the harness skeleton turns out to want bats's
  setup/teardown features. Listed here for the record so future
  phases don't re-litigate this decision without a reason.

### 2.x Comparison table

| Approach | Schema drift (Finding A & B) | Logic regression | Plain-text rows (6, 7) | Bootstrapping cost | Per-test runtime | Maintenance |
|---|---|---|---|---|---|---|
| **A. Schema-pinned static** | ✓ for `session list`; ✗ for `bd list` (no published schema) | ✗ | ✗ (no schema for plain text) | low (manifest + walker) | ~10 ms | manifest drift |
| **B. Fixture-driven smoke** | ✓ via captured fixture | ✓ | ✓ via plain-text fixture | medium (override seam in each script) | ~10–50 ms | fixture refresh story |
| **C. Real-gc integration** | ✓ | ✓ | ✓ | high (sandboxed Dolt + session lifecycle) | 100s of ms – seconds | gc version skew |

## 3. Recommendation

**Hybrid: A as the primary gate, B as the fallback for rows A
cannot cover.** Phase 2 builds the harness around B (it
dominates A's coverage and covers the rows A cannot), and
extends the manifest format with an `assertion` field that the
runner can satisfy via either approach.

Concretely:

- For inventory rows whose producer publishes a schema (row 5 —
  `gc session list`), the harness fetches the schema via `gc
  <cmd> --json-schema`, walks the manifest's path list, and
  fails on the first unresolved path. This is the cheap, fast
  gate — runs on every `tests/smoke/run.sh` invocation, gives
  the PR #37 bug class a fast feedback signal, no fixture rot.
- For rows whose producer publishes no schema (rows 1, 2, 3, 4
  — all `gc bd list`) or whose output is non-JSON (rows 6, 7 —
  `gc session list` plain-text, `gc session new` plain-text
  message), the harness uses captured fixtures. Each fixture
  has a refresh script next to it (e.g.
  `tests/smoke/fixtures/bd-list/refresh.sh`) that re-captures
  from a live gc and exits non-zero on diff; promoting a diff
  is a deliberate operator step.
- Real-gc integration (C) is **explicitly out of scope** for
  this mol. It earns its own future epic if/when gc itself
  needs end-to-end coverage that polecat tests in gascity
  don't already provide.

### 3.1 Bug classes caught

- **CAUGHT — schema-drift in `--json` consumers** (the original
  PR #37 bug class): field-name case mismatch, missing array
  unwrap (e.g. `map(...)` on an object with `.sessions[]`),
  field referenced but not in the published schema, field
  removed from schema but still referenced.
- **CAUGHT — fixture-divergence in plain-text consumers** (rows
  6, 7): column-position drift in `gc session list`, format-
  string drift in `gc session new`'s "Session X created"
  message. Caught when the fixture-refresh diff fails to apply
  cleanly.
- **CAUGHT — logic regressions in fixture-based tests** (rows
  with B coverage): wrong truncation behavior, wrong fallback
  on missing field, wrong selector in jq/Python, etc.
- **NOT CAUGHT — divergence between fixture and live producer
  if the refresh script isn't run**. Mitigation: a Phase 4
  CI job runs `refresh.sh` against the workflow's gc and fails
  on diff. Developers running `tests/smoke/run.sh` locally
  without a fresh gc can still pass with stale fixtures — by
  design; the gate is the PR check, not local.
- **NOT CAUGHT — schema-drift on `gc bd list`** (Finding A) at
  the *publisher* level. If `gc bd list` ever silently changes
  its (undocumented) shape, schema-static checks against
  inventory rows 1–4 won't catch it because there is no schema
  to walk. The fixture for `bd list` will catch a value-shape
  change at refresh time; a corollary follow-up is to file a
  ticket asking `gc bd list` to publish `--json-schema`. Out
  of scope for this mol.
- **NOT CAUGHT — real producer-consumer integration**: gc
  emitting a payload that satisfies the schema but is
  semantically wrong (e.g. an empty `sessions` array when the
  caller expected non-empty). Tests in this mol are
  consumer-side; producer-side coverage lives in gc/gascity.

### 3.2 Why this and not pure-A or pure-B

Pure A loses three of seven inventory rows on `gc bd list`
alone, plus rows 6 and 7. Five of seven rows uncovered is not a
viable gate for the mol's stated goal.

Pure B catches everything but pays the bootstrap cost — an
input-override seam — on every script. For status-line.sh the
seam is trivial (the script already conditions on a cached
file). For cockpit.sh it's larger (the Python is heredoc-defined
inline; a clean seam means restructuring). The hybrid pays the
fixture cost only where A doesn't already cover, keeping the
per-script change as small as the row mix allows.

### 3.3 Future-proofing

The hybrid extends to `tools/`, `template-fragments/`, and
`formulas/` later without a rewrite. The manifest format is
producer-agnostic — a row is `(consumer-path, producer-command,
parser, paths, fixture-or-schema)`. New consumers (Python
scripts in `tools/`, Go in any future migration) plug in by
adding rows. The harness itself stays a small Bourne-shell
runner.

## 4. Phase 2–5 outline

### Phase 2 — Foundation

One polecat. Produces:

- `tests/smoke/run.sh` — Bourne-shell harness. Reads
  `tests/smoke/manifest.tsv` (one row per inventory entry) and
  runs each row's check (schema-walk or fixture-replay). Exits
  non-zero on any failure. Local-only; no CI wiring yet.
- `tests/smoke/lib/walk-schema.sh` — helper that resolves a
  dotted path against a JSON Schema (uses `jq` since the repo
  already depends on it for status-line.sh).
- `tests/smoke/lib/replay-fixture.sh` — helper that pipes a
  captured fixture into a script via the agreed override seam
  and asserts on its stdout.
- `tests/smoke/manifest.tsv` — initial rows covering
  `gc-toolkit-status-line.sh` (the PR #37 regression-pin) and
  one row from `cockpit.sh` (proving the fixture path works
  end-to-end). All rows for all scripts come in Phase 3.
- `tests/smoke/fixtures/session-list.json` — captured `gc
  session list --json` for the status-line.sh test.
- `assets/scripts/gc-toolkit-status-line.sh` — minimal override
  seam: `GC_SESSION_LIST_OVERRIDE` env var that, when set,
  reads from the named file instead of running `gc session
  list`. The diff is ~5 lines and lives behind an
  `if [ -n "$GC_SESSION_LIST_OVERRIDE" ]` guard so production
  behavior is unchanged when the env var is unset.

Failure-mode contract for Phase 2: the seed test must FAIL
against the current `integration/smoke-tests` HEAD (the broken
PascalCase jq query) and PASS against a checkout of PR #37's
fix. That is the explicit regression-pin demonstration the bead
calls for.

### Phase 3 — Backfill

The remaining 6 inventory rows. Dispatch is **two grouped
polecats**, not one-per-row, because:

- Rows 1–4 all share the same fixtures (`gc bd list` for rig
  beads, `gc session list` for cockpit's session enumeration).
  Splitting them across polecats forces each polecat to
  re-capture and bikeshed the same fixture files. Group =
  cockpit.sh, one polecat.
- Rows 6–7 share a fixture (plain-text `gc session list` /
  `gc session new` output) and live in the same script
  (tmux-spawn-thread.sh). Group = tmux-spawn-thread.sh, one
  polecat.

Each polecat:

- Adds the script's override seam (or extends the existing one).
- Captures fixtures into `tests/smoke/fixtures/`.
- Adds manifest rows.
- Adds at least one assertion per row.

Phase 3 polecats can run in parallel since the cockpit and
tmux-spawn-thread groups don't share files.

### Phase 4 — CI + docs

One polecat. Produces:

- `.github/workflows/smoke.yml` — runs `tests/smoke/run.sh` on
  every PR targeting `main` or `integration/smoke-tests`.
  Requires gc + bd in the runner image; if that's not available
  on the default runner, the workflow installs from the same
  source the repo's other tools use. **Failure mode if gc is
  not installable in CI**: the workflow runs only the
  fixture-replay subset (rows that don't need live `gc
  --json-schema`) and reports the limitation in the job
  summary. Phase 4 polecat decides at write time based on
  what's available.
- `docs/testing.md` (or similar — check naming convention with
  existing docs) — a CONTRIBUTING-style note explaining how to
  add a row when introducing a new `gc <cmd> --json` consumer,
  including the fixture-refresh story.
- A `pack.toml` or analogous registration so the smoke tests
  are discoverable from `gc rig status` (out of scope if no
  such hook exists — Phase 4 polecat verifies).

### Phase 5 — Graduation

`integration/smoke-tests` → `main` via a single squash-merge PR.
Refinery + operator path; no polecat dispatch required for the
merge itself.

Pre-graduation cleanup the Phase 4 polecat should leave for
Phase 5 to do (or do in a final commit on `integration/smoke-
tests` before opening the graduation PR):

- Remove any `tests/smoke/fixtures/*.tmp` or scratch files.
- Verify the testing doc is in its final location.
- Verify the CI workflow runs against `main` (not just
  `integration/smoke-tests`) after the squash.
- Verify no stray `--db /tmp/...` test artifacts in the repo.
- Confirm `bd list` schema follow-up is filed as its own bead
  (per Finding A) so it doesn't get lost on graduation.

## Acceptance criteria self-check

| Criterion (from bead) | Met by |
|---|---|
| Doc exists with four sections | §1, §2, §3, §4 |
| Inventory matrix covers every `gc <cmd> --json | jq` (or equivalent) call site in `assets/scripts/*.sh` | §1.2 + §1.1 (empty-row audit for the five files with no consumption) |
| Each unique `gc <cmd>` has its published schema cited | §1.4 + `schemas/session-list.json`, `schemas/bd-list.json` |
| Provenance table at top if external pattern surveyed | §0 (no external pattern imported as text; bats/shellspec/shunit2 referenced from prior knowledge only) |
| PR opened against `integration/smoke-tests`, not main | will be done at submit time |
| No code changes outside `specs/<this-bead>/` | self-verified at submit time |
| Recommendation states which bug classes the approach catches and does not | §3.1 |
| Phase 2–5 outline concrete enough to dispatch directly on Phase 2 | §4 — names `tests/smoke/run.sh`, the override seam, the regression-pin, and Phase 2's failure-mode contract |
