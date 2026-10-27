---
name: Gas City search for the other-rig mention check
description: The search the arch check asks for before the pack adds rig-mentions.sh, the advisory check that lists each place a change names another rig of its city. What Gas City, bd, the packs Gas City bundles and publishes, and the redaction scanner one of those packs runs ship near that need, read at named upstream commits, and why the check composes the city's rig list instead. Read it when checking whether the check can move onto a Gas City primitive.
---

# Gas City search for the other-rig mention check

gc-toolkit's repository is public, and the pack names no other rig of the city
it runs in. This change adds `assets/scripts/rig-mentions.sh`, which lists each
place a change names another rig: the rig's name, a bead id with the rig's
prefix, or a path into the rig's checkout. So the arch check asks what Gas City
already ships for that need
([review-arch.md](../../docs/review-arch.md#the-checks), check 1). Gas City
lists a city's rigs with the three things the check matches, and the check
reads them from there. Nothing in Gas City, bd or the packs Gas City publishes
reads the text a change adds for the city's own rigs. The nearest is a
redaction scanner that the gstack pack runs before it sends a spec out. Its
patterns are a fixed set, and it takes no list of names to look for.

## The surface and the need

- `rig-mentions.sh` reads the lines a branch adds and the messages of its
  commits that no remote has yet (`--branch <base>`), the title, summary and
  dispatch text a bead's pull request publishes (`--bead <id>`), a file
  (`--file <path>`), or every tracked file (`--tree`). It prints each mention
  it finds, one per line, and then its advice. It exits 0 when it finds none, 1
  when it prints some, and 2 when it could not check.
- mol-polecat-work runs it twice. Self-review step 2 runs it on the branch and
  the work bead, and submit step 4 runs it on the summary that step composes.
  Each reads the list and fixes what it finds, and neither stops on it.
- [component-model.md](../../docs/component-model.md) places it in the work
  workflow.

The need is narrow. Before a change's text is published, list each mention of
another rig of the city the change runs in. The rigs are the city's own, read
when the check runs, so the repository never commits the names it looks for.
The list is advice, because the operator asked for a catch rather than a merge
refusal, and because a word can be a rig's name without being a use of that
rig.

## Where the search looked

Each was read on 2026-10-26:

- Gas City at main `37bd09351ac8`: its documentation, its engineering docs,
  the `core` pack it bundles from its own repository, and its source.
- Every pack in `gastownhall/gascity-packs` at main `dac12a4a802c`, and the
  `gastown` and `gascity` packs Gas City bundles, at the packs commit its
  `go.mod` pins, `66c672b5ed00`.
- bd at main `2ef4df339a44`.
- gstack at `1626d4857bfe`, the upstream commit the gstack pack records in its
  `vendor/gstack/upstream.toml`, for the scanner that pack's `spec` skill runs.

The search covered redaction, scrubbing and sanitizing, disclosure,
confidential and private text, leaks, public and private repositories,
visibility, cross-rig work and other rigs, the rig list, pull request bodies
and commit messages, pre-commit and pre-push hooks, and secret scanning. In
every pack it looked for a check that reads outbound text, and for any rule
that keeps a city's own names out of it. Each pack's hits were tallied, and the
hits about outbound text were read.

## What Gas City ships near the need

### The rig roster

[`gc rig list`](https://docs.gascity.com/reference/cli#gc-rig-list) lists "all
registered rigs with their paths, prefixes, default branches, and beads
status", and `--json` prints them as data. A rig's name, path and prefix are
fields of its [`Rig`](https://docs.gascity.com/reference/config#rig) entry.
They are the three things the check matches, so the check reads them from
`gc rig list --json` each time it runs.

Nothing in a rig's entry says what another rig's content may name. A `Rig`
carries no visibility, no repository owner and no remote. Gas City's cross-rig
features route work and resolve its dependencies: `gc rig add` generates the
cross-rig routes for a new rig, and the bundled `core` pack's `cross-rig-deps`
order converts a satisfied cross-rig `blocks` dependency to `related`.

### Redaction in Gas City

The trust model
([Command Execution Trust Boundaries](https://docs.gascity.com/reference/trust-boundaries))
treats pull request text as untrusted data that must not be concatenated into a
shell command. Before its orchestrator runs a `work_query`, a `scale_check`, a
pool hook, an order or a sling helper, it strips inherited secret-looking
environment keys. Its failure logs "redact known secret values before writing
order exec errors or events". In source, package execenv's
`RedactText` replaces known secret values and secret assignment patterns in
text meant for logs or events, and package gitcred's `ScrubSecrets` masks a
credential that git echoes in an error. `gc metrics status` shows "redacted
local command-usage metrics status". Each of these protects a secret value or a
user's usage data, and none of them reads text for a rig's name.

The `core` pack's `jsonl-export` order exports every bead scope to a git
archive, and its scrub rules decide which records the archive keeps: test
pollution, system issue types, `gc:` and `order:` titles, and sling
auto-convoys are dropped. The rules select records. They read no text for a
name.

### bd

bd keeps its own records out of a repository in three ways.
[`bd init`](https://beads.gascity.com/cli-reference/init) `--contributor` runs
the OSS contributor setup, which routes planning issues to a separate planning
repository, and `--stealth` keeps bd's files out of the repository.
[`bd preflight`](https://beads.gascity.com/cli-reference/preflight) lists
pre-PR checks, and one of them is `.beads/issues.jsonl` pollution. Each one
keeps bd's data out of a pull request. None of them reads the text a change
adds.

### The packs Gas City bundles and publishes

- The gstack pack's `spec` skill reviews a spec's text before the text leaves.
  A semantic pass by the model reads the final draft once, looking for named
  people, customers and vendors tied to negative judgments, unannounced
  strategy, NDA material and "Confidential context bleed — a codename only in
  this spec, not in the repo README / `package.json`". Then upstream gstack's
  `gstack-redact` scans the exact bytes before each place they go: before the
  skill sends the draft to Codex, before it files the spec as an issue, and
  before it archives it. Its taxonomy is gstack's `lib/redact-patterns.ts`:
  credentials at the HIGH tier; lower-confidence credential shapes such as JWTs
  and Google API keys, PII, legal markers, hostnames under `.internal`,
  `.corp`, `.local` and similar, and localhost URLs at MEDIUM; absolute paths
  under a home directory and TODO markers at LOW. Its options set the input,
  the repository's visibility, the spans and emails to suppress, the findings
  to auto-redact and a size cap. None of them adds a term to look for.
  gstack's `gstack-redact-prepush` hook scans the lines a push adds with the
  same taxonomy, blocks the push on a HIGH finding and warns on a MEDIUM one.
  So the scanner cannot list a rig's name or a bead id by the rig's prefix.
  Its home-path pattern lists every path under a home directory, the change's
  own rig's included, at the tier it only surfaces.
  The semantic pass is a model's judgment over one spec, with nothing to tell
  it which names are the city's.
- The `gascity` pack, bundled and at packs main, renders a GitHub issue triage
  comment with `render_triage_comment` in `assets/scripts/github_reports.py`.
  It withholds the analysis of a security-sensitive or P0 report until a person
  approves it. The rule reads the report's verdict and priority, not its names.
  The same pack's `publish` formula creates a pull request only after the push
  succeeds and a "sanitized title/body" from the final report passes policy
  (`assets/workflows/publish/open-pr.md`), and its preflight step validates
  "sanitized metadata". Neither step says what sanitizing removes, and the
  pack's GitHub helper, `assets/scripts/github_api.py`, posts a pull request's
  body as it reads it from the file.
- The `github` pack's `redact_config` hides its GitHub App's secret material in
  the configuration it prints.
- The `oversight-rig` pack tells its project lead to keep to "THIS rig only —
  never another rig, never the whole city", and asks for status updates in
  "plain language: omit internal IDs, session names, branches". These are
  instructions to a model, and no check reads what comes back. Two of the
  pack's unit tests read the files of its packaged `city-executive-status`
  skill. One fails on a path under `/home/`, an email address or an
  eleven-character id that starts with `C`, and the other on any `/home/`
  path. Their patterns are fixed, and they read only that skill's files.

## What the change does with it

The check composes the roster and adds the matching that no primitive offers.

- It reads names, prefixes and paths from `gc rig list --json` when it runs, so
  the names stay in the city and out of the repository. The rig the change is
  for is not another rig, and neither are Gas City, the pack and the engine its
  demo capture drives, which the pack names as dependencies.
- It runs inside the existing mol-polecat-work self-review and submit steps and
  prints advice. It adds no order, no bead kind, no lifecycle state and no
  metadata key, so it adds no pack noun and needs no warrant
  ([review-arch.md](../../docs/review-arch.md#the-checks), check 2).
- The sweep that came with it touches paths that one warrant covers. Its
  rewording of `assets/scripts/gh-origin-guard.sh` and
  [gh-origin-guard.md](../../docs/gh-origin-guard.md) falls under
  [*gh write containment*](../../docs/warrants.md#gh-write-containment), which
  is re-verified in the same change
  ([review-arch.md](../../docs/review-arch.md#the-checks), check 4). Its
  edits to `assets/scripts/gc-helm.sh` leave the `priority` verb, which
  *Priority following* covers, as it was. No other Covers line names a path the
  branch changes.

This answer changes if Gas City, bd or a pack Gas City bundles ships a check
that reads outbound text against the city's own rigs, or a rig setting that
says what a rig's repository may name. Either would be the primitive to move
the check onto. A redaction scanner that took a caller's list of terms, such as
`gstack-redact` with such an option, would be a scanner to compose, with
`gc rig list` still supplying the terms.
