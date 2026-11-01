---
name: The correctness check on gc-toolkit
description: Use when you run the correctness check on a gc-toolkit change, when you want to know what that check will look for in your own change, or when you have a defect class particular to gc-toolkit to add to it.
---

# The correctness check on gc-toolkit

gc-toolkit ships bash and jq scripts, shell blocks that agents run from its
formulas and skills, the Go services `services/gctk` and `services/helm`, and
the helm web app in `services/helm/web`. Each surface's section opens with what
the gates run on it, then names the defects that have bitten there and the
guard for each, so the review looks hardest where no guard reaches.

## Scope

**Mandate.** The defect classes particular to gc-toolkit that a correctness
review hunts on each surface the repository ships, and how much of each the
repository's gates catch.

**Boundaries.** The method, its grades and the verdict are pack content, in
`skills/review-correctness/SKILL.md`. The rule a lint detector enforces is
stated in its header under `tools/lint-learned.d/`. `AGENTS.md` and
[architecture.md](architecture.md#what-the-pack-supplies-and-what-a-rig-supplies)
state where a rule that binds only gc-toolkit's own repository lives.

## Where the gates run

`gc formula show mol-polecat-work --rig gc-toolkit` shows the commands the rig
declares.

- The polecat's self-review runs `lint_command`, which is
  `tools/lint-learned.sh` and then `tools/lint.sh` over the files the branch
  changes. It runs the suites `tools/run-tests.sh --affected origin/main`
  selects, by the rules in that script's header, and stamps the head that
  passed on its work bead as `self_review_passed_sha`. When the anchor's stamp
  names the reviewed commit, the method runs no suite.
- The refinery runs the same `lint_command` at merge, and no tests.
- CI runs the whole `*.test.sh` suite on Linux and on macOS
  (`.github/workflows/tests.yml`), and no lint, Go test or web check. Every
  merge waits on the checks main's ruleset requires.

## Pack content every rig runs

gc-toolkit is the pack every rig in the city runs, and also a rig of its own.
Pack content is what the installed pack runs or loads, which every rig shares,
such as its skills, formulas, agent prompts and template fragments, its
scripts, orders, doctor checks and hooks, its services,
`lifecycle/lifecycle.toml` and the rows of `review-checks.toml`. Its
directories include `skills/`, `formulas/`, `agents/`, `template-fragments/`,
`assets/scripts/`, `orders/`, `doctor/`, `overlays/` and `services/`, and a
file outside them is pack content when pack content runs it, as pack scripts
run `tools/gc-proactive.sh`. A skill's description and a formula's step prose
are pack content as much as a script is. `review-checks.toml` is both the
pack's check index and gc-toolkit's own, so a row changed there changes that
check for every rig.

A rule that binds only work on gc-toolkit's own repository stays out of pack
content
([architecture.md](architecture.md#what-the-pack-supplies-and-what-a-rig-supplies)).
No gate looks for one. A lint for the repository's name cannot be the guard,
because such a rule can be worded for any repository and name none.

- **A rule only gc-toolkit holds is a finding.** The test is whether a rig
  other than gc-toolkit would hold its own changes to the rule. A rule fails it
  when it rests on a doc, a plan or a convention only gc-toolkit keeps, such as
  its component model, its deletion plan or the size line on its pull
  requests. It fails just as surely when its wording fits any repository while
  the discipline it states is one only gc-toolkit keeps. Text that names the
  pack only to reach the pack's own scripts or skills states no such rule.
- **The finding names every line that carries the rule.** A change can write
  one rule into several pack files at once, such as a skill's body and its
  description, or a check's method and its purpose in `review-checks.toml`. A
  clause the change adds to a description or a purpose to announce the rule
  carries the rule, even when the clause read alone states a general
  principle. Each of those lines is a locus of the same finding.
- **The failure is in another rig.** An agent at work for another rig follows
  the rule as written. It holds that rig's change to gc-toolkit's rule, looks
  for a gc-toolkit doc the rig does not keep, or adds gc-toolkit's output to the
  rig's pull request. That is an instruction that does the wrong thing when it
  is followed as written, so the finding blocks. It also makes false
  architecture.md's statement that such a rule is never written into the pack
  content every rig runs.
- **The fix moves the rule.** It goes where `AGENTS.md` sends a rule for
  gc-toolkit's own repository. Guidance to one review check goes into
  gc-toolkit's `docs/review-<check>.md`, and a check only gc-toolkit runs goes
  under `tools/lint-learned.d/` or `.github/workflows/`. Making the rule apply
  only where a rig's own extension opts in still leaves its text in every
  rig's copy, so that is no fix. The pack file keeps text that holds for every
  rig, and the finding names where the rule goes.

## Bash and jq scripts

`tools/lint.sh` shellchecks the `.sh` and shell-shebang files a change names,
at warning severity (`assets/scripts/shellcheck-run.sh`). An unquoted expansion
(SC2086) and a variable set in a pipeline's subshell (SC2030, SC2031) are info
findings, so the gate never reports them. A `# shellcheck disable=` directive a
change adds hides its finding from the gate, so read the reason it gives. Each
detector `tools/lint-learned.sh` runs enforces one rule, inside the scope its
header states, and any other shape is the review's. CI fails a portability
defect only on a line some test executes.

- **Errexit.** Most scripts set `-u` or `-uo pipefail` without `-e`, so a
  command whose failure matters is tested where it runs, with `|| rc=$?`,
  `if !` or `|| exit`. The repository keeps a status with `x=$(cmd) || rc=$?`.
  shellcheck reports `local x=$(cmd)` (SC2155), and not
  `if ! x=$(cmd); then rc=$?` or an `rc=$?` after `x=$(cmd) || true`, which
  lose the status the same way. Suites source some blocks under `bash -eu`, as
  `crash-loop-window.test.sh` does, so a block or function that ends on a false
  `[ … ] && x=1` fails there.
- **Unreadable is not empty.** A read whose emptiness decides anything checks
  its exit status, and an unreadable answer holds or fails closed
  (`assets/scripts/deferred-dispatch.sh`, `bd_list` in `assets/scripts/bd-lib.sh`).
  A `gc bd list … | jq …` without pipefail reads a store that did not answer as
  an empty list. `gc bd … --json` can carry a raw control byte inside a note,
  which makes jq refuse the whole payload, so store text goes through the
  shared `scrub` helper first, and `inline-ctrl-scrub.sh` flags a scrub written
  inline.
- **Loop input.** A loop that can report an all-clear reads an explicit,
  checked temp file, as `assets/scripts/converse-reap.sh` does, never a `<<<`
  here-string. Under disk
  pressure bash cannot write the temp file behind a large here-string, so the
  loop runs zero times and the caller reports nothing found, and no detector
  flags the shape. A helper whose side effects the caller needs answers in a
  variable instead of on stdout, as `mktemp_tracked` in
  `assets/scripts/deferred-dispatch.sh` answers in `REPLY`.
- **bd metadata in jq.** bd infers a scalar's type at `--set-metadata`, so
  `k=1` stores a number and `k=true` a boolean, and a comparison with a string
  takes `tostring` first. `id-read-unguarded.sh` flags `.id // .[0].id` on a bd
  answer.
- **BSD and GNU userland.** The host is macOS: `sed`, `grep`, `awk`, `date`,
  `stat` and `find` are BSD, `/bin/bash` is 3.2, and `#!/usr/bin/env bash`
  finds bash 5. Where the userlands disagree, the repository tries both
  spellings, as `epoch_of` in `assets/scripts/gc-deacon-ledger.sh` does for
  `date` and `mtime_of` in `formulas/mol-deacon-patrol.toml` does for `stat`,
  or writes the one form both accept, such as `sed -i.bak … && rm -f ….bak` for
  an in-place edit. CI's macOS job fails by name when one of those tools
  resolves outside `/usr/bin` and `/bin`.

## Shell blocks in formulas and skills

No shell block in a formula, skill, prompt or doc is shellchecked. The learned
detectors that read formula and skill text each catch one shape, and a block
runs in a test only where a suite extracts it, usually by its markers.
`tools/lint.sh` fails a formula change that adds a procedure to step text, by
the rule in
[pack-authoring.md](pack-authoring.md#step-text-calls-a-tested-script).

- **The agent's shell.** An agent pastes a step's blocks into its own tool
  shell. A codex agent's is zsh, and a Claude agent's is the shell its
  provider's `CLAUDE_CODE_SHELL` names, or else its login shell, zsh on macOS.
  So a block is written for zsh as well as bash. Of zsh's unsplit unquoted
  expansions, `formula-unquoted-for.sh` flags only `for x in $LIST`, so a
  `cmd $FILES` is the review's. An unbraced name before a colon can take a zsh
  modifier, so `"$REV:review-checks.toml"` reaches git as
  `<rev>eview-checks.toml`, and `zsh-colon-modifier.sh` flags it. JSON reaches
  jq through `printf '%s'`, since zsh's `echo` expands its escapes, and
  `candidate-pipeline.test.sh` runs its block under `bash -O xpg_echo` and
  `zsh -f` to catch an `echo`.
- **No variable survives a tool call.** Each call runs in a fresh shell, so a
  block sets every variable it reads, the claimed step's id included, and
  resolves each script path itself, as the formulas' candidate loop does.
- **`set -e` stops nothing.** In the Claude Code tool shell a block runs on past
  a failed command even after `set -e`, so a block gates each write with `if`
  or `|| exit`. Suites source some blocks under `bash -eu`, so a block also has
  to complete under errexit.
- **TOML decodes the block first.** A formula step's description is a TOML
  basic string, so the agent runs the block as TOML decodes it: `\\` in the
  file is one backslash, `\$` stops the formula from parsing, and a backslash
  at the end of a line joins the next line to it. A suite that extracts a
  region with awk reads the raw file, so a backslash in the region tests text
  the agent never runs.
- **A rendered var is raw text.** A pour writes each `{{var}}` into the step as
  it stands, so a var that holds a command, quotes and all, reaches the block
  through a quoted heredoc, never inside quotes. The check commands in
  `formulas/mol-polecat-work.toml` arrive that way, and `rig-checks.test.sh`
  runs them with both quote kinds.

## Marker-fenced blocks

A `# >>> <name>` line and a `# <<< <name>` line fence a block for a test to run.
In a formula or a skill the fence marks step shell that a suite extracts and
executes. In a script it marks a block for a suite to extract, or a helper that
each file needing it carries as a copy.

- **Read the suite that names the block.** `formula-marker-coverage.test.sh`
  fails when no suite names a formula's marker, but not when the naming suite
  stops asserting what the block does, and nothing checks that a suite names a
  marker in a script, a skill or a prompt. When a block's behavior changes,
  find its suite with `git grep -l -F -e '<name>' -- '*.test.sh'` and check
  that a case pins the change.
- **The markers are the contract.** A suite finds its block by the marker's
  name, and most fail on an empty extraction, so renaming or duplicating a
  marker changes its suite in the same diff.
- **Only the region is tested.** Lines in the same code fence outside the
  markers run untested.
- **Copies change together.** A helper's suite, such as
  `control-char-scrub.test.sh` or `doctor-budget.test.sh`, finds its copies by
  sweeping named directories, executes one, and fails when another differs
  from it. An edit to one copy is owed to every copy, and a copy outside the
  swept directories is held by no suite.

## The Go services

`tools/lint.sh` runs `go vet ./...` in each module and `gofmt -l` over every
tracked Go file, at the self-review and at merge. Vet type-checks test files
and runs none of them, and no gate runs `go test`. CI's whole suite drives gctk
end to end, because each suite whose scripts reach `lifecycle.sh` or
`merge.sh` builds gctk from the checkout (`harness_build_gctk` in
`assets/scripts/test-harness.sh`). `merge.test.sh` and `lifecycle.test.sh`
name none of gctk's `.go` files, so the affected subset leaves them out of a
gctk change, and no suite it selects for a Go change builds the code that
changed. No suite builds or runs helm-svc. So on a Go diff the review runs
`go test ./...` in each module the diff touches, and for gctk the suites of the
commands it changes. On the host helm compiles only with ICU's cgo flags, so
its tests run with `CGO_CPPFLAGS` and `CGO_LDFLAGS` set from `icu4c_cgo_flags`
in `assets/scripts/icu4c-cgo.sh`, as `tools/lint.sh` sets them for vet.

- **Live at the next build, with no fallback.** The `gctk-build` and
  `helm-build` orders run `assets/scripts/gc-build.sh` every five minutes, so
  each binary is rebuilt from the rig checkout soon after a change reaches it.
  `gctk merge` lands the pull requests the merge cadence merges, and every
  merged record is a `gctk lifecycle` transition. The bridges `merge.sh` and
  `lifecycle.sh` have no shell fallback, so a gctk defect reaches every landing
  in the city.
- **One meaning, several lists.** `lifecycle/lifecycle.toml` declares the
  anchor states and the machine axis. gctk carries the states as a typed table
  and helm carries the machine values as Go constants in
  `internal/board/derive.go`, and `lifecycle.test.sh` holds both to the TOML.
  No test holds the machine values the writers record to it (`recordMachine`
  in gctk's `internal/cli/merge.go`, `assets/scripts/gate-ensure.sh`), and a
  recorded value helm does not know renders as `unknown` on the board.
- **A port reads what its script read.** gctk reads bead fields the way jq
  does. `Bead.Meta` in `internal/gcbd/gcbd.go` stringifies a scalar as
  `(v // "") | tostring` would, so a metadata number reads as its digits, and
  `Scrub` strips the control bytes the shell `scrub` strips. A Go type
  assertion where jq would raise an error fails open, so the unreadable case is
  fixtured: `merge.test.sh` feeds `gctk merge` a required check with a numeric
  `conclusion` and expects a hold. `Scrub`'s match with the shell helper is
  pinned only by `gcbd_test.go`.
- **Reads through the supervisor API.** `gcbd.Show` reads through the
  supervisor API, whose bead payload carries no notes and whose cached answer
  can lag a write just made, so a read that verifies a write, or one that needs
  notes, uses `ShowDirect`. A bead that cannot be read comes back nil, and the
  caller refuses to act rather than read it as empty.
- **Child process groups.** `gitIn` in `internal/cli/lifecycle.go` runs git,
  and `Run` in `internal/rig/run.go` runs the rig's check commands, each in a
  process group of its own, out of reach of the order runner's group stop. A
  SIGTERM or SIGINT that reaches gctk during the call stops the child's group
  with SIGTERM, and gctk exits 128 plus the signal. A git fetch killed outright
  leaves a ref lock in the rig checkout that fails every later fetch there, so
  a stop sends the group SIGTERM before anything harder. gctk's other
  subprocesses, `gctk merge`'s git calls among them, stay in its own group.
- **The board's gather loads the shared store.** helm-svc's gather reads every
  rig's store on a cache miss. A full-row read pulls the heavy text columns out
  of the Dolt store the city's agents share, and a round trip per epic or
  convoy made under the board's lock serializes every board request behind one
  slow gather. `internal/source/beads_test.go` pins which reads take the lite
  projection and that edges, conversations and pull requests cost no read per row,
  and `internal/server/server_test.go` pins that concurrent misses share one
  gather, run outside the board's lock. So a gather change is read for a new
  per-row call or a heavy column.
- **A derivation key follows the sling's shapes.** `Facts.Inflight` is keyed by
  an input convoy's tracked member, which in the common sling shape is the
  anchor's own bead, so a roll-up over children alone shows live work as
  stranded (`TestAnchorOwnWorkflowCounts` in `internal/board`). A derivation
  change is checked against each shape a key takes: the anchor itself, a
  child, and a review or rework bead.

## The helm web app

No gate runs the web checks or lints TypeScript. `npm run typecheck`,
`npm test` and `npm run build` run in no CI job, suite or gate command, and no
suite the affected subset selects for a path under `services/helm/web` runs
the app's code. The review runs them in `services/helm/web` after `npm ci`,
then checks that `git status --porcelain -- dist` prints nothing.

- **The bundle is committed.** helm-svc embeds `dist/` (`web/embed.go`) and
  its builder never runs npm, so a change to the app's runtime code ships only
  with the rebuilt `dist/` in the same diff. A runtime change that ships
  renames `dist/assets/index-*.js`, and no gate compares `dist/` with `src/`.
- **The contract is a hand-written mirror.** `src/contract.ts` mirrors the Go
  wire structs by hand, because the board's `/svc/` surface is not in the
  supervisor's OpenAPI document, and a Go field renamed without its mirror
  reads `undefined` in the browser with nothing failing.
  `web/contract_parity_test.go` compares the two in both directions, and
  `src/contract.fixture.ts` fails `npm run build` when the committed wire
  sample stops matching the type. `go test ./web -run TestBoardFixture -update`
  regenerates the sample. Neither check runs in a gate.
- **Writes carry `X-GC-Request`.** The supervisor proxies helm-svc and refuses
  a mutation without that header, with a 403 that never reaches helm-svc.
  Every write client takes `SVC_WRITE_HEADERS` from `src/svcWrite.ts`, and
  `ActuateButton.test.tsx` and `OpenConversation.test.tsx` assert the header on
  each write.
- **URLs are document-relative.** The app is served under
  `/v0/city/<city>/svc/helm/`, a prefix the proxy strips, so `vite.config.ts`
  keeps `base: './'` and `App.tsx` fetches `helm`, not `/helm`. A root-absolute
  URL works on the dev server and misses helm-svc under the mount.
  `web/handler_test.go` resolves every asset `dist/index.html` names through
  the mount.
- **Supervisor types are a pruned snapshot.** `src/drill/gen/supervisor.d.ts`
  is generated from a live supervisor's OpenAPI document for the operations
  `scripts/gen-supervisor-types.mjs` lists, and committed. A new supervisor
  call adds its operation there and regenerates with
  `npm run gen:supervisor-types`, and when the supervisor's API moves, the
  snapshot goes stale with nothing failing.
