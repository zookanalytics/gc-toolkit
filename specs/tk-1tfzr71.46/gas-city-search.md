---
name: Gas City search for the names that replace the retired word visit
description: The search the arch check asks for before the pack adds a name of its own. What Gas City and bd ship for a pack's workflow label, for the settings of a script a tmux key binding starts, and for that script's drafts folder, read at named upstream commits, and why the pack keeps its own names for them. Read it when checking the engagement label, the GC_INTAKE_* settings or the intake-drafts folder.
---

# Gas City search for the names that replace the retired word visit

The native-gates cutover retired the visit, and its design asks each surface
that kept the word in its name to be renamed or to carry a dated debt
(specs/tk-0ur8r9p/design.md, section 10). This change renames three surfaces.
Each new name replaces a retired one with the same meaning, and the change adds
no key, verb or mode. A new name is still surface in AGENTS.md's sense, so the
arch check asks what Gas City ships for each need
([review-arch.md](../../docs/review-arch.md#the-checks), check 1).

## The surface and the need

- **The workflow label `engagement`.** `tools/measure.sh` labels the files of
  the human-engagement workflow, and `docs/component-model.md` section 4 places
  that workflow's components under the label. CI prints the label in every PR's
  size comment, and a commit or PR title takes its scope from it
  (`docs/commit-conventions.md`). It was `visit`.
- **The intake prompt's settings `GC_INTAKE_*`.** `tmux-intake-prompt.sh`, which
  `prefix + a` runs, reads eight settings: the intake tool, its timeout, the
  rig-list cache's lifetime, the drafts folder, the drafts' keep days and the
  popup's width, height and input height. `operator-intake.sh` reads one, the
  default rig. They were `GC_VISIT_*`, and the intake tool's was
  `GC_VISIT_OPEN_TOOL`, after the script that became `operator-intake.sh`.
- **The drafts folder `intake-drafts`.** The prompt writes each message to a
  draft file before it hands it to the intake, so a failed intake keeps the
  text. The folder was `visit-drafts`, and `gc-visit-drafts` under the temp
  root.

## Where the search looked

- `gastownhall/gascity` at upstream `main` 9f807760c (2026-11-05): `docs/`,
  `engdocs/`, `cmd/gc` and `internal/`, read in a local clone with
  `git grep <term> upstream/main -- docs engdocs internal cmd`.
- `gastownhall/beads` at upstream `main` 6d713a748 (2026-11-04).

## What Gas City ships near each need

### A workflow label

Gas City has no taxonomy of a pack's files by workflow or subsystem. The pack
spec (`docs/reference/specs/pack-spec.md`) defines a pack's directories by
their kind, such as agents, formulas, orders, commands and doctor checks, and
never by their purpose. The label belongs to the pack's own placement index, so
the word is the pack's choice.

The word chosen is the one the pack already uses for this workflow: its page is
`docs/human-engagement.md`, and `docs/built-once-target.md`'s subsystem table
names the row "human engagement". Gas City gives the word no meaning of its
own: `git grep -i -w engagement upstream/main -- docs engdocs` finds nothing,
and the three hits in Go source are comments that use it in its ordinary sense
(`internal/runtime/tmux/tmux.go`, its test, and
`internal/sling/sling_merge_strategy_test.go`). Two other words were weighed.
`converse` names the agent that hosts a sitting, while the workflow also holds
the board, the tmux surfaces, intake and the first reaction's disposition.
`human` is Gas City's park route and the await type of its human gate.

### Settings for a script a tmux key binding starts

Gas City hands configuration to two kinds of process. An agent's process gets
the `env` map of its `Agent`, `AgentOverride` or `AgentPatch` entry
(`docs/reference/config.md`). A pack command gets the invoking environment plus
`GC_BIN`, `GC_CITY`, `GC_CITY_PATH`, `GC_CITY_NAME`, `GC_PACK_DIR`,
`GC_PACK_NAME`, `GC_PACK_STATE_DIR` and the others pack-spec section 1.2.12
("Command Directory") lists, because gc runs it. The intake prompt is neither:
`tmux-bindings.sh` binds `prefix + a` to a tmux `run-shell` of the script, so
tmux starts it with the tmux server's environment. Its settings therefore stay
environment variables, set where that server reads them.

The names keep the `GC_` prefix. Upstream's config reference calls `GC_*` a
prefix of "keys gc sets itself" when it rejects them from a capture's forced
`env` (`docs/reference/config.md`, the `env` row of `ProgramStatusBinding`),
so a pack name there reads as one of gc's. The pack's script settings already
sit under that prefix, among them `GC_CONVERSE_CAPABILITY_LIB` and
`GC_CITY_LIVENESS_LIB`, which `operator-intake.sh` reads beside the default rig.
This change follows the names beside it and changes only the retired word.
Moving every pack setting out of the prefix would change that convention for
the whole pack, and it is not made here.

No caller sets an old name. On 2026-11-05 no `GC_VISIT_*` variable was set in
the town repository, `~/.zshenv`, `~/.zshrc`, `~/.zprofile`, `~/.tmux.conf`,
`~/Library/LaunchAgents` or the default tmux server's global environment, and
only these two scripts, their tests and `docs/human-engagement.md` named one.
So the change reads the new names alone, with no fallback to the old ones.

### The drafts folder

Gas City's state directory for a pack is `GC_PACK_STATE_DIR`, which pack-spec
section 1.2.12 sets for a command gc runs, from `citylayout.PackStateDir`
(`internal/citylayout/runtime.go`). The prompt already prefers it, and falls
back to `$XDG_STATE_HOME/gc`, then `~/.local/state/gc`, then a folder under the
temp root, because tmux does not set it. The change renames only the leaf. The
fallback chain, and the choice to start the prompt from tmux rather than as a
pack command, stay as they are.

Nothing moves the old folder. The prompt never reads a kept draft back: a press
that keeps one names its path, and the operator opens it there. So a draft kept
under the old name stays where it was announced, and the reaper, which deletes
`draft-*` files older than the keep days in the current folder, no longer
reaches it. On 2026-11-05 the city host's one such folder,
`/Users/gc/.local/state/gc/visit-drafts`, held no draft, only a `rig-list.cache`
from 2026-10-13. A person can remove it.

## The bd fact the change relies on

bead-rehome.sh's work-outcome arm, keyed on the retired kind, is deleted rather
than keyed on a conversation's shape. bd refuses an unforced close of a bead
assigned to anyone but the closing actor: `AssigneeMatches` in
`internal/validation/issue.go` of `gastownhall/beads` (at 6d713a748, and at
9b65b9e19, the commit the deployed bd 1.3.2 is built from) returns "cannot close
… assignee is …, actor is …" unless the assignee is empty or matches the actor.
A conversation is always assigned, to `human` in the operator's queue or to its
sitting's alias (`assets/scripts/conversation.sh`), and bead-rehome's close is
unforced, so it can close a conversation only when it runs as that assignee.
The sitting that holds a conversation names it only as the successor of the
subject it re-homes (`agents/_converse/prompt.template.md`), never as the
origin. On 2026-11-05 no bead with a conversation's shape carried
`gc.superseded_by` in any of the city's seven stores: 0 of 1,105 pointed beads.
