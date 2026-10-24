---
name: Gas City search for the review path's resolver modes and record keys
description: The search the arch check asks for before the pack adds surface of its own. What Gas City, the packs it publishes and bd ship for a rig's list of review checks, a rig's guidance for one check read at the reviewed commit, the guidance a change edits, and the record a review's dispatch leaves on the review bead, read at named upstream commits, and why none of it covers what review-checks.sh's --show, --check, --extension and --edits and the review_context and review_formula keys do. Read it when checking whether the review path still needs that surface.
---

# Gas City search for the review path's resolver modes and record keys

This design adds pack surface. `review-checks.sh`, the pack's one reader of the
check index, gains modes that print a rig's checks and its review guidance at
the commit a review judges. The dispatch writes `review_context` and
`review_formula` on the review bead. So the arch check asks what Gas City
already ships for each need
([review-arch.md](../../docs/review-arch.md#the-checks), check 1).

Gas City ships the mechanism the design passes a review's values through:
formula vars, which the sling fills into the step text. The design composes
them. For the rest of the surface the search found nothing that covers the
need. Gas City reads its configuration from the city and its packs, and its one
read at a git ref takes a single ref for every repository, while a review needs
a rig's own files at the commit it judges. Gas City records a run's formula and vars on the
run's root, while a review needs them on a review bead that may have no run.
Every pack that names reviewers or lanes declares them itself. None of the
surface is a pack noun, so it takes no warrant
([review-arch.md](../../docs/review-arch.md#the-checks), check 2), and the
change touches no path or key that a warrant in
[warrants.md](../../docs/warrants.md) covers.

## The surface and the need

- `review-checks.sh --show --at <oid>` prints the checks a rig gets: the pack's
  index, with the rows of the `review-checks.toml` that commit carries laid over
  it key by key. `--check <name> --at <oid>` prints one row of it. Triage reads
  its menu with `--show`, and signoff.sh and the review formulas ask `--check`
  whether a check is declared. `review-outcome.sh supersede-anchor --oid` names
  the commit an operator's ruling judged, which that verb resolves the anchor's
  checks at.
- `review-checks.sh --extension <check> --at <oid>` prints the rig's guidance
  for one check, the `docs/review-<check>.md` that commit carries. A review
  prints it while it gathers what it reads, and carries it into the step that
  applies the check's method, so the rig's words add to the pack's method, and
  a branch's edit to them governs its own review.
- `review-checks.sh --edits --base <branch> --at <oid>` prints the review
  guidance a change edits: `review-checks.toml` and each `docs/review-*.md`
  among the paths it touches from where it left `<branch>`, with a renamed file
  counted at both of its paths. signoff.sh reads it to name such an edit to the
  person who approves the merge.
- `review_context` is why the dispatch sent a review: the lane it found short of
  green, or the bring-current round a triage review rules on. gate-ensure.sh
  writes it on the review bead, passes it as a formula var on the sling, and
  rewrites it when its stranded arm slings the review again.
- `review_formula` is the formula gate-ensure.sh pours onto a review, mol-review
  or the quorum, as the refinery's reconcile chooses for the pass. A review held
  with no poured workflow follows that formula's steps, as the review's fixed
  description says.

What the modes need is a read of a rig's own files at the commit a review
judges, over the pack's own rows. What the keys need is a value that stays on
the review bead whether or not a run holds it, so that a review held with no
workflow still names why it went out and which formula runs it.

## Where the search looked

Each was read on 2026-10-24:

- Gas City at main `c05f1d782c30`: its documentation, its engineering docs, the
  `core` pack it bundles, and the source of its formula parser, of sling, of its
  git helpers and of its bead metadata vocabulary.
- Every pack Gas City publishes, at `c1848011ae23`. Gas City bundles `gastown`
  and the build pack, `gascity`, from among them
  ([Builtin Packs](https://docs.gascity.com/reference/system-packs)).
- bd at main `d26da8dadd50`: its documentation of issue metadata and of
  `bd config`.

The search covered review checks, lanes, reviewers and personas; a repository's
review guidance and instruction files; configuration a rig lays over a pack's;
reading a file at a git ref; listing the paths a change touches
(`--name-only`, `--name-status`, a pull request's file list); and what a
dispatch or a run leaves on a bead (`formula`, `workflow_id`, `molecule_id`,
`gc.var.`, a reason or a context). Each part the search found was read.

## What Gas City ships near each need

### A rig's list of checks

Gas City keeps no list of review checks. A review's lanes are formula
structure. `core`'s `mol-review-quorum` takes its lanes, their providers and
their targets as formula vars.
[Multi-Lane Review Loops](https://docs.gascity.com/guides/understanding-formulas#multi-lane-review-loops)
describes lanes as the children of a review formula's loop, and the build pack,
`gascity`, declares its acceptance, test-evidence and simplicity lanes that way
in `build-basic-review`. Where Gas City says "check" it means other things.
`[steps.check]` runs a script that decides whether a step passed
([Check](https://docs.gascity.com/reference/specs/formula-spec-v2#3-1-check)),
and `[[doctor.check]]` declares a health check for `gc doctor`
([LocalDoctorCheck](https://docs.gascity.com/reference/config#localdoctorcheck)).

Gas City lays a rig's configuration over a pack's in the city's own
configuration. A rig's entry there sets `formula_vars`, a `formulas_dir` that is
the highest formula layer, and patches to the agents its packs bring
([Rig](https://docs.gascity.com/reference/config#rig)). Formula layers run from
the city's packs, through the city's own `formulas/` and the rig's packs, to the
rig's `formulas_dir`, and the highest layer that holds a name wins
([File Naming And Layers](https://docs.gascity.com/reference/specs/formula-spec-v2#1-1-file-naming-and-layers)).
All of it is read from the city's configuration and from files on disk. A rig's
`review-checks.toml` lives in the rig's own repository, and the design reads it
at the commit being judged, so that a branch's edit to it governs its own
review (decision 5 of [review-path.md](review-path.md)).

One reader in Gas City reads files at a git ref. When `GC_FORMULA_REF` names a
ref, the formula parser reads each formula file and description file that sits
in a git repository at that ref, and takes a file the ref lacks as absent
(package `formula`, `SourceFromEnv` and `GitRefSource`). It exists to keep
formula resolution off in-flight branches. It serves the formula parser, which
reads formulas and the files they name, not a data file such as the index. It
also applies one ref to every repository a layer lives in, so it cannot read
the pack's files as installed and a rig's files at the commit under review in
one resolution.

bd keeps configuration per project in the beads database, under namespaces such
as `custom.*` ([bd config](https://beads.gascity.com/cli-reference/config)). A
value there belongs to the store, not to a commit, so a branch cannot carry its
own.

Among the packs Gas City publishes, each list of reviewers is the pack's own.
`compound-engineering`'s `compound-code-review` turns its persona catalog into
review lanes, picks its conditional reviewers with a selector that judges the
diff, and records the pick in `gc.build.selected_reviewers`. `gstack`,
`superpowers` and `bmad` declare their review lanes in their own formulas.
`pr-pipeline`'s `mol-pr-review` scores a fixed set of categories, and
`pr-review`'s `review-pr` skill runs a fixed set of providers. No pack reads a
list of checks from the repository under review. The nearest shape is in the
BMAD Method skills that `bmad` vendors. A skill's `customize.toml` holds its
defaults, and a project's team and personal override files are merged over it
key by key. That merge runs through a resolver a BMAD install puts in the
project, reads the project's working tree, and customizes BMAD's own workflows,
so it holds nothing for this pack to call.

So the pack keeps `--show` and `--check`. The rig's rows come from
`git show <oid>:review-checks.toml` in the rig's repository, fetched by id when
no repository here holds the commit, and the pack's rows from the index at the
root of the pack the script ships in.

### A rig's guidance for one check

Gas City lets a formula step take its text from a file. A `description_file`
under `../assets/` resolves through the formula layers, so a city or a
higher-priority pack can replace a step's prose by shipping the same asset path
([Description Files](https://docs.gascity.com/reference/specs/formula-spec-v2#1-8-description-files)).
The parser reads that file when it loads the formula, from the literal path the
step names, and the winning layer's text becomes the step's description
(package `formula`, `resolveDescriptionFiles` and `winningAssetPath`). That does
not carry a rig's guidance for a check. The path belongs to the step, so a step
that serves every check cannot choose a file by the check it reviews. The
winning text replaces the pack's prose rather than following it, while a rig's
guidance extends the pack's method. And the layers are the city's, read from
disk or at the one `GC_FORMULA_REF` ref, not from the rig's repository at the
reviewed commit.

Gas City's skills are authored at a pack's level or at an agent role's level,
and are linked into each agent's provider skill directory when the city starts
([Skills](https://docs.gascity.com/guides/capabilities-for-coding-agent-users#skills),
[gc skill list](https://docs.gascity.com/reference/cli#gc-skill-list)). A
check's method is such a skill in this design. A rig's repository is not a
skill scope, and a skill is read as linked, not at a commit.

The packs read a repository's own guidance only through its general instruction
files, in the checkout where the agent works. `compound-engineering`'s
project-standards reviewer reads each `CLAUDE.md` and `AGENTS.md` in a
directory above a changed path. `pr-pipeline`'s `mol-pr-start` reads
`CONTRIBUTING.md`, `AGENTS.md`, `CONVENTIONS.md` and `CLAUDE.md` before it
plans. `gastown`'s `mol-refinery-patrol` falls back to the project's
instruction file for its quality gates when no gate command is configured. A
BMAD skill's `persistent_facts` can load project files as context. None of
these is chosen by the check a review applies, and none is read at a recorded
commit. The build pack's `code-review-base` reads no repository file for its
settings: it treats the values rendered into its step text as authoritative,
and requires them neither in bead metadata nor in a `review-config.yaml`.

So the pack keeps `--extension`. It is `git show <oid>:docs/review-<check>.md`
behind the resolver, which finds or fetches the commit.

### The guidance a change edits

Gas City has no command that lists the paths a change touches, and its `git`
package has no helper that does. The GitHub PR monitor records a pull request's
readiness and routes its repair, and keeps no file list
([GitHubPRMonitor](https://docs.gascity.com/reference/config#githubprmonitor)).
The packs that need the list run git in their own steps.
`contributing-to-gascity`'s `fine-tune` skill lists the design docs and release
gates a branch touches with `git diff --name-only main...HEAD -- <paths>`.
`gstack`'s `land-and-deploy` skill lists the project documents a branch touched
the same way. `pr-pipeline`'s `mol-pr-from-issue` matches the touched paths
against protected patterns, and `gastown`'s `mol-polecat-work` has its
affected-tests command read `git diff --name-only $BASE_REF...HEAD`.

So the pack keeps `--edits`, which is the same git call. It sits in the
resolver because the resolver is the one place that says which paths are review
guidance. It turns rename detection off, so a guidance file renamed away counts
as an edit to it.

### A review's dispatch record

Gas City records a run's formula and vars on the run's root. The compiler
stamps the formula's name, `gc.formula_name`, on every root (package `formula`,
`toRecipeWithGraph`). Sling stamps a graph.v2 root with its input convoy and a
snapshot of the runtime vars, `gc.graphv2_vars.v1`
([Compilation](https://docs.gascity.com/reference/specs/formula-spec-v2#2-compilation),
under root stamping; package `sling`, `stampGraphV2RootMetadata`). The bead a
convoy-first `--on` launch pours over gets its route, `gc.execution_routed_to`,
and its merge strategy, and no key that names the formula or the root (package
`sling`, `attachFormulaToBead`). The launch's input convoy is its one link to
the root, and the root is neither a child of the bead nor its `workflow_id` or
`molecule_id` (package `sling`, the comment on
`liveConvoyTrackedWorkflowRoots`). While a run lives, its formula and vars are
on its root. A review with no run has no root, and nothing on the review bead
names either.

An agent's `default_sling_formula` names the formula applied to every bead
slung to that agent ([Agent](https://docs.gascity.com/reference/config#agent)).
The review pool sets none, and one default could not choose between the review
formulas: the refinery's reconcile chooses one for each pass, and the pool also
claims work that is not a review. `gc sling` takes a formula and its vars and
has no flag for why it dispatched
([gc sling](https://docs.gascity.com/reference/cli#gc-sling)). The `github`
pack's intake hands an order the event that triggered it, as environment for
that one run.

Gas City and bd both leave keys like these to the pack. Gas City's bead
metadata vocabulary declares only the keys its engine reads, and pack-private
keys stay open-world by design (package `beadmeta`, and the engineering doc
*Bead Store*). bd calls metadata "the preferred extension point for data that is
specific to an integration, orchestrator, team workflow, or experimental
automation", and reserves only the `bd:` and `_` prefixes
([Issue Metadata](https://beads.gascity.com/core-concepts/metadata#reserved-key-prefixes)).
The bundled `gastown` pack keeps its review legs' record the same way.
`mol-idea-to-plan` writes `coordinator`, `review_id`, `review_phase` and
`review_leg` on each leg's bead and slings it with its own `review_formula`
var, and `mol-review-leg` reads those keys back from the bead.

So the pack keeps `review_context` and `review_formula` as keys of the review's
record, beside the values that record already carried.

### The values the step text names

Gas City ships this, and the design composes it. A formula declares vars, with
`required` for a value the pour must have, and the pour fills each `{{name}}`
in the step text from the sling's `--var` values, the rig's `formula_vars` and
the declared defaults
([Variables](https://docs.gascity.com/reference/specs/formula-spec-v2#1-4-variables),
[Rig](https://docs.gascity.com/reference/config#rig)). The review formulas
declare each value of "What a review is told" in [review-path.md](review-path.md)
as a var, and gate-ensure.sh passes them on every sling. The build pack's
`code-review-base` takes its review's subject, its report path and an optional
context the same way.

## What the pack keeps

The pack keeps the resolver's `--show`, `--check`, `--extension` and `--edits`
modes, and the `review_context` and `review_formula` keys. Each mode is a git
read at the commit its caller names, and each key is a value of the review's
record that Gas City keeps only on a run's root. This record goes stale, and
the surface moves onto Gas City, when Gas City ships a way for a review to read
a rig's own files at the commit it judges, or keeps on a bead the formula and
vars it is to be poured with.
