---
name: Gas City search for naming a rig's repository and counting failed zero-diff checks
description: The search the arch check asks for before the pack adds surface of its own. What Gas City, the packs it publishes and bd ship for naming a rig's checkout by path in a formula step, and for counting one check's failures on a work bead across the refinery's turns, read at named upstream commits. It shows why rig-root.sh is glue over two native reads, and why the pack keeps its own failure count in bead metadata. Read it when checking whether the pack still needs either.
---

# Gas City search for naming a rig's repository and counting failed zero-diff checks

This change adds two pieces of pack surface. `assets/scripts/rig-root.sh`
resolves the path by which a formula step's git calls name the rig's
repository. The `zero_diff_check_failures` metadata key counts the refinery's
zero-diff checks that could not run on a work bead. So the arch check asks what
Gas City already ships for each need
([review-arch.md](../../docs/review-arch.md#the-checks), checks 1 and 2).

A formula step can learn its rig's path from the `GC_RIG_ROOT` that Gas City
sets on every rig-scoped session, or from the roster that `gc rig list --json`
prints with every path made absolute. Formula text gets no variable that
carries the path, so a step makes one of those reads itself. `rig-root.sh`
makes them for every step that names a rig by path, and keeps no state. Gas
City's retry budgets live on the step beads of a molecule it materializes. The
refinery's patrol has no step beads, so nothing upstream counts a check's
failures across the refinery's turns. bd's charter leaves retry plans to the
orchestration layer and puts the per-issue data it needs in issue metadata,
and the pack keeps its count there. Neither addition is a pack noun, so
neither needs a warrant.

## Where the search looked

All three were read on 2026-10-25, UTC:

- Gas City at main `7cff3a26556a`: its documentation, its engineering docs,
  the `core` pack it bundles, and the source of session environments, rig
  listing, command context, sling's formula variables and the controller's
  assigned-work backstop. None of what the search read there has changed since
  `698a594923c5`, the commit the review read.
- Every pack Gas City publishes, at `55e77ca43b01`, including `pr-review` and
  `profiler`, which the packs registry does not list.
- bd at main `73f64fdfce97`.

For the rig's path, the search covered `GC_RIG_ROOT`, `{{.RigRoot}}`, formula
variables, `gc rig list`, `gc rig status`, and how a `gc` command chooses its
rig. For the count, it covered every retry and attempt budget
(`[steps.retry]`, `[steps.check]`, `max_attempts`, `gc.attempt`), restart and
defer limits, and any counter a pack keeps, in a bead or in records of its
own. Each part the search found was read.

## Naming a rig's repository by path

### The surface and the need

With no argument, `rig-root.sh` prints `GC_RIG_ROOT`, and when that is unset,
the roster entry for `GC_RIG`. With `--rig <name>` it prints the roster entry
for that rig, whatever `GC_RIG_ROOT` says, for a formula that works one fixed
rig. It prints nothing and exits 1 when no single path resolves. Every formula
block whose git calls name the rig by path calls it, and so do
`direct-merge-push.sh` and `refinery-workspace.sh`.

The need is a path for `git -C`, in a formula step and in the scripts a step
runs. The path must not come from the current directory, because nothing pins
a session's cwd between steps. It must never be empty, because `git -C ""`
runs in the current directory.

### What Gas City ships near the need

**The session environment.** Gas City starts each rig-scoped agent's session
with `GC_RIG` and `GC_RIG_ROOT`, the rig's name and its root path. A
city-scoped agent gets both empty, so that a value the tmux server inherited
does not leak into its session (package main, `resolveTemplate`). The
[Understanding Formulas](https://docs.gascity.com/guides/understanding-formulas)
guide names "the `GC_RIG` the controller sets on every rig agent". The
[exec beads provider](https://docs.gascity.com/reference/exec-beads-provider#environment-variables)
reference lists both variables for a store script in rig scope. `GC_RIG_ROOT`
is the read `rig-root.sh` makes first.

**Agent configuration and prompts.** `{{.RigRoot}}` is one of the path fields
that agent configuration templates expand, in `work_dir`, `pre_start`,
`session_setup`, `work_query`, `sling_query` and others
([configuration reference](https://docs.gascity.com/reference/config#agent)).
Prompt templates expand `{{ .RigRoot }}` too. `gc prime` fills it from
`GC_RIG_ROOT`, and when that is unset, from the configured path of the rig
`GC_RIG` names (package main, `buildPrimeContextFor`; package workdir,
`RigRootForName`). That is the rule `rig-root.sh` applies with no argument,
but it reaches prompt text only. Formula step text is neither a configuration
template nor a prompt. `work_dir` sets the directory a session starts in, and
an agent's commands can leave it.

**Formula variables.** Formula v2 reserves one variable that the runtime
supplies, `{{convoy_id}}`
([Formula Spec v2, variables](https://docs.gascity.com/reference/specs/formula-spec-v2#1-4-variables)).
`gc sling` also passes routing variables: `rig_name`, `binding_name` and
`binding_prefix`, and `base_branch` and `target_branch` to a formula that uses
them (package sling, `buildSlingFormulaVars`). So a formula learns its rig by
name, never by path. A rig's `formula_vars` sets defaults for the variables a
formula declares
([configuration reference](https://docs.gascity.com/reference/config#rig)). A
path there would be a second copy, written into each rig's configuration by
hand, beside the one the roster holds.

**The roster.** [`gc rig list`](https://docs.gascity.com/reference/cli#gc-rig-list)
with `--json` prints every rig with its path, and the city itself as an entry
marked `hq`. The command makes each path absolute before printing it (package
main, `resolveRigPaths`), and its JSON type documents the path as "Always
absolute in output". When it cannot read the city, it prints a JSON error
object in place of the roster and exits 1.
[`gc rig status`](https://docs.gascity.com/reference/cli#gc-rig-status) prints
one rig, its path included. Given no name, it takes the rig from the command's
context. That context comes from the command's flags, then the city
environment and `GC_RIG`, then `GC_DIR`, and last the current directory
(package main, `resolveContext`), which is the read this change keeps out of
git calls. Given a name, it reads the rig straight from the configuration,
without the `resolveRigPaths` step that `gc rig list` runs. `gc rig list`,
keyed on a name, is the second read `rig-root.sh` makes.

**The core pack.** Its `prune-branches` order takes every rig's path from
`gc rig list --json` and runs each git call as `git -C "$rig_path"`. Its other
scripts read the same roster for rig names, prefixes and scopes.

**The packs Gas City publishes.**

- `gastown`'s `mol-polecat-work`, at its worktree step, and its
  `mol-witness-patrol`, for orphan recovery, require `GC_CITY_PATH`, `GC_RIG`
  and `GC_RIG_ROOT`. Each stops when any of the three is empty, and runs its
  git calls in the rig through `-C`. Its `task-artifact-cleanup` command
  requires the same three. Its `pr-merge-reconcile` command runs git with
  `-C "$GC_RIG_ROOT"` when that is set, and in the current directory when it
  is not. Its polecat and refinery agents pass `{{.RigRoot}}` to the worktree
  script their `pre_start` runs. Its `mol-digest-generate` lists the rigs with
  `gc rig list` and reads each one's merges with `git -C <rig-path>`. Its crew
  prompt, to make a worktree in another rig, takes that rig's root from
  `gc rig status <name>` and runs `git -C` on it.
- The build pack `gascity` takes its artifact root from `GC_RIG_ROOT`, falling
  back to `GC_DIR` and `GC_BEADS_SCOPE_ROOT`, in its artifact helper and its
  `build-artifact-valid.sh` check. Its review workflow's `write-report` step
  says "Read the rig root from `$GC_RIG_ROOT`", and not to write under the
  current directory. Workflows in `bmad`, `compound-engineering`, `gstack` and
  `superpowers` run their artifact validators "from `$GC_RIG_ROOT`".
- `oversight-rig` sets its project lead's `work_dir` to `{{.RigRoot}}`.
- No other pack names a rig's root, and only `gastown`'s crew prompt looks
  one up by name.

### What the pack keeps

With no argument, `rig-root.sh` reads `GC_RIG_ROOT` first, as `gastown` and the
build pack do, and reads the roster only when it is unset, keyed on `GC_RIG`.
That is the rule `gc prime` applies to a prompt's `{{ .RigRoot }}`. With
`--rig` it reads the roster, keyed on the name given. It reads the roster the
way the core pack's `prune-branches` does. `gastown`'s crew prompt asks
`gc rig status <name>` instead, which skips the step that makes a configured
path absolute. Gas City's session environment sets the two variables
together, so the roster answers two callers: one that carries a rig's name
without its path, and a formula that works one fixed rig, whatever rig its
session serves.

The script writes nothing and keeps no state. It is glue over two native reads,
so it adds no pack noun and needs no warrant
([review-arch.md](../../docs/review-arch.md#the-checks), check 2). It is one
script rather than three lines in each block because the copies had drifted,
and a fix to the lookup had to land at every site.

A formula variable that carried the rig's path, the way `gc sling` passes
`rig_name`, would let a step name its repository without the script.

## Counting failed zero-diff checks

### The surface and the need

The refinery's zero-diff check asks whether a handed-off branch carries any
change against its target. It runs first in the refinery's merge-push step,
before a direct landing or a pull request. When the check cannot run, the step
adds one to `zero_diff_check_failures` on the work bead and leaves the work
with the refinery. At the third failure in a row it parks the bead `blocked`,
routed to a person, with a visit under the `refinery-zero-diff-check-failed`
key. A check that runs clears the count, and so does the park.

The need is a count of consecutive failures that outlives the refinery's turns.
A check that fails ends the turn (`gc runtime drain-ack`) and leaves the bead
assigned to the refinery, and a later turn's find-work selects it again, in a
later session. The work bead is the one object every attempt shares.

### What Gas City ships near the need

**Retry and check loops.** `[steps.retry]` re-runs the attempts of a step that
the orchestrator classifies as transient, up to `max_attempts`, and closes the
step by `on_exhausted` when the budget runs out
([Formula Spec v2, retry](https://docs.gascity.com/reference/specs/formula-spec-v2#3-2-retry)).
`[steps.check]` re-runs a step until a check script passes. Exit 75 marks an
infrastructure outcome, which re-runs the script without spending an attempt,
under a budget of its own
([Formula Spec v2, check](https://docs.gascity.com/reference/specs/formula-spec-v2#3-1-check)).
That is the distinction this change draws: a check that could not run is not a
verdict. Both loops count attempts with beads the compiler materializes for the
step: a control bead that keeps the step's id, which the orchestrator runs, and
one bead per attempt or iteration.

The refinery's patrol has no step beads. It is poured with
`gc bd mol wisp mol-refinery-patrol --root-only`, and the `--root-only` flag of
[`bd mol wisp`](https://beads.gascity.com/cli-reference/mol#bd-mol-wisp)
creates "only the root issue (no child step issues)". So no step of the patrol
is a bead that a loop could wrap. A loop around merge-push would also re-run
the whole step, and the
[Understanding Formulas](https://docs.gascity.com/guides/understanding-formulas#self-checking-work-and-transient-hardening)
guide warns that a retry attempt "re-runs the whole step with no record of
irreversible side effects the failed attempt already landed". Merge-push lands
merges and opens pull requests. When its budget ran out, the loop would close
the step, where the refinery needs the work bead parked for a person while its
patrol moves on.

**Restart and defer limits.** `[daemon] max_restarts` quarantines an agent that
restarts more often than that within `restart_window`
([configuration reference](https://docs.gascity.com/reference/config#daemonconfig)),
and [`gc session wake`](https://docs.gascity.com/reference/cli#gc-session-wake)
releases the quarantine. It counts a session's restarts, not a check's failures
on a bead. The controller's assigned-work backstop is the nearest in shape. An
agent's `assigned_work_defer_limit`, 3 by default, bounds how many consecutive
reconciler ticks may defer an idle stop on the same assigned bead. The count
resets when the anchor bead changes or the session is no longer eligible for
that stop
([configuration reference](https://docs.gascity.com/reference/config#agent)).
The controller keeps the count in its own memory, per session (package main,
`memoryAssignedWorkDeferTracker`), and no formula can read or write it.

**The packs Gas City publishes.**

- `gastown`'s refinery runs the same check, `branch_has_real_change`, in its
  merge-push step. When the check cannot compute, the step stops with "Do not
  mutate bead state", and the bead waits, unchanged, for a later patrol, with
  no count and no limit. A branch with no change is parked `blocked` for a
  person: "NEVER silent retry".
- The build pack `gascity`, and the packs whose workflows extend it, bound
  their loops with `max_attempts` on the steps they materialize. Their steps
  read the attempt number from `gc.attempt`, and earlier failures from
  `gc.attempt_log` on the loop's control bead. The build pack's `claim`
  command, like `gastown`'s polecat prompt, retries a claim a few times within
  one run.
- `pr-review`'s `mol-pr-iterate` keeps an iteration count in the notes of its
  run's root bead, which its intake step sets to 0, and halts to the mayor
  once the count reaches 2 with the feedback still present. The count starts
  over with each run.
- `slack-full`'s adapter keeps a count of failed message deliveries in its own
  process, for its health endpoint. An ingress receipt parked for correlation
  recovery counts its attempts across passes and restarts, and fails at the
  sixth. Receipts are JSON files in the adapter's state directory, not beads.
- No pack keeps a count across runs on the bead those runs act on.

**bd.** An issue has no attempt or retry field (package types, `Issue`). bd's
project charter, under Orchestration Boundary, gives the orchestration layer
"retry plans", and says "When orchestration needs extra per-issue data, prefer
issue metadata before adding first-class fields or commands". bd's
[Issue Metadata](https://beads.gascity.com/core-concepts/metadata) page calls
metadata "the preferred extension point for data that is specific to an
integration, orchestrator, team workflow, or experimental automation".

### What the pack keeps

The count is one metadata key on the work bead, the object every attempt
shares, which is where bd's charter puts per-issue orchestration data.
`lifecycle/lifecycle.toml` registers it. The park writes the `blocked` state
the pack already has, through its existing lifecycle writer, and files its
visit through the existing escalation. So the change adds no bead kind and no
lifecycle state, and needs no warrant. Until the third failure, the refinery
does what `gastown`'s does when the check cannot compute: it leaves the work
assigned to the refinery for a later turn, and writes nothing on the bead but
the count. The count adds only the bound.

A failure budget that Gas City kept across runs, on the bead those runs act
on, would replace the key.
