---
name: Pack authoring — gc-toolkit's own conventions
description: The conventions gc-toolkit's own formulas, scripts, skills and agents follow where Gas City leaves the choice to the pack — how a step closes and how a run declines, how step text and skills reach a pack script, how a landed pack change is confirmed live, where a rig-scoped agent runs, the patrol-wisp cycle, and how a scan resolves an owner or an address. A pack convention; the Gas City facts beneath it are gascity-packs.md and gascity-agents.md.
---

# Pack authoring

This page states gc-toolkit's own authoring conventions, not Gas City
behavior. The platform facts each convention answers to are
[gascity-packs.md](gascity-packs.md), for formulas and packs, and
[gascity-agents.md](gascity-agents.md), for agents and sessions. Where a
convention rests on one of them, it links there.

## Scope

**Mandate.** The conventions gc-toolkit's own formulas, scripts, skills and
agents follow where Gas City leaves the choice to the pack: how a step closes
and how a run declines, how step text and skills reach a pack script, how a
landed pack change is confirmed live, the names the pack's artifacts carry,
where a rig-scoped agent runs, the patrol-wisp cycle, and how a scan resolves
an owner or an address.

**Boundaries.** What Gas City itself does when a formula runs or a pack loads
is [gascity-packs.md](gascity-packs.md); agent variants, identity and session
lifecycle are [gascity-agents.md](gascity-agents.md). Each component's own job
is its row in [component-model.md](component-model.md) §4, and how work moves
end to end is [architecture.md](architecture.md).

## A step closes through `step-close.sh`

A graph.v2 step advances only by closing its own step bead, and neither
environment spelling the upstream bodies use names that bead reliably
([gascity-packs.md](gascity-packs.md#a-v2-step-advances-by-closing-its-own-step-bead-not-by-drain-ack)).
So every pack formula step closes through
`assets/scripts/step-close.sh --step <formula>.<step-id> --convoy {{convoy_id}}`
instead. It resolves the target from the store by (`metadata."gc.root_bead_id"`,
`metadata."gc.step_ref"`) — the molecule and the step. A pool agent wears one
assignee across every run it makes, so only that pair names exactly one bead;
the assignee corroborates the match and never identifies it alone. `--convoy`
names the molecule as the live workflow root poured over the formula's input
convoy. A formula with no input convoy leaves it off, and the script derives
the molecule, first from the `gc.session_id` stamp a claim leaves on the step.
It refuses to write at all when it cannot prove which bead is yours. The pack's
hardened detector `tools/lint-learned.d/step-close-env-id.sh` holds the
line, flagging any step that closes a bead on an id read from the
environment.

Mirror the canonical bodies' outcome set — pass, plus `gc.outcome=fail`
with `gc.failure_class=transient|hard` and a `gc.failure_reason` — and their
terminal ordering: a terminal step closes, then drain-acks.

## A run that must not advance is cancelled, after its wait is recorded

Some refusal arms cannot close their step, because closing advances the graph
and the next step is destructive — `mol-polecat-work`'s duplicate-dispatch gate
is the case, where `workspace-setup` would recreate the branch over a live
worker's commits. Leaving the step `open` is the respawn loop by another door:
`open` is claimable, so the pool re-offers the same step every cycle and each
fresh worker re-derives the same refusal. Clearing `gc.routed_to` alone does
not fix it either, because the runtime routes a step a drained session left
assigned back to its pool
([gascity-packs.md](gascity-packs.md#a-v2-step-advances-by-closing-its-own-step-bead-not-by-drain-ack)).

A molecule's lifecycle is gascity's, so the refusal ends the run through
gascity's run cancel
([gascity-packs.md](gascity-packs.md#a-run-is-cancelled-through-the-supervisor-api)).
`assets/scripts/run-cancel.sh` sends it, after resolving the run from the step
this session holds, and the pack writes no member of the molecule. Nothing
resumes a cancelled run, so a wait for a person sits on the work bead:
`assets/scripts/await-ruling.sh` makes the work bead wait on the visit with a
`blocks` edge and arms its re-sling, and closing the visit pours a fresh run.
The re-sling fires only for an open, unassigned bead, so the script first
releases a claim on the work bead that no live worker holds. The visit is
filed with `escalate.sh`'s verdict window off, because a wait needs an open
visit and the window files none for a situation a person already closed
`moot` or `benign`.

The refusal drains only after the cancel lands. A cancel that does not land
leaves the step claimed by this session, and the step goes back to the pool
only once the session ends, so the next worker retries it.

A molecule keeps the step text it was poured with, while the scripts that text
calls are read from the rig checkout when the step runs. So a pack script that
open step text names stays callable under that name until no open step bead
names it. Step text from an earlier version of these formulas requires
`assets/scripts/molecule-hold.sh` to exist before it resolves the pack's
scripts, and calls it to decline. That script hands the call to
`run-cancel.sh --step` unchanged, so such a run ends through gascity's run
cancel like any other.

## Step text and skills reach pack scripts at runtime

A formula step body gets no template pass, and the variables that name the
pack's own directory are not exported to agent sessions
([gascity-packs.md](gascity-packs.md#a-formula-body-gets-no-template-pass)).
So step text resolves a pack script at shell runtime through the variables a
session does carry:

```bash
"$GC_RIG_ROOT/assets/scripts/foo.sh"               # owning rig only (repo == pack)
"$GC_CITY_PATH/rigs/<pack>/assets/scripts/foo.sh"  # also resolves for importer rigs
```

`$GC_RIG_ROOT` points at the agent's own rig checkout, so it finds the script
only for the **owning** rig; the `$GC_CITY_PATH/rigs/<pack>/…` form is the
portable one, because every agent shares `$GC_CITY_PATH` (the city root) and the
script lives in the owning pack's tree under it.

An agent's own shell, where a skill's examples run, has no template pass
either, and no variable set in one tool call survives into the next. It asks
gc for the pack instead: `commands/scripts-dir/run.sh` is the pack command
`scripts-dir`, which prints the scripts directory of the pack gc loaded. gc
registers a pack command under its import binding and under no other name
([pack spec](https://docs.gascity.com/reference/specs/pack-spec), §1.2.12),
so a city that imports the pack as `[imports.gc-toolkit]` runs
`gc gc-toolkit scripts-dir`, and one that imports it as `[imports.kit]` runs
`gc kit scripts-dir`. A skill is not rendered, so its text cannot carry the
binding. Its examples write `"$(gc <binding> scripts-dir)/foo.sh"`, and the
agent fills in the binding gc puts in front of the skill's own name
(`gc-toolkit.work`), which `gc skill list` prints as the skill's FROM. The
call then runs the pack's own copy wherever the city imports the pack from,
and never a checkout the agent is standing in. The ask-for-work skills
(`work`, `waits`, `records`, `prs`) call every writer this way.

## A landed pack change is confirmed on the deployed checkout

This city imports the pack by directory, so what is live is the rig
checkout's working tree, not the merge
([gascity-packs.md](gascity-packs.md#a-directory-imported-pack-is-live-from-the-working-tree-not-from-a-merge)).
Two silent failure modes follow, and a landing pack-content PR usually trips
both at once:

- **The rig root is behind `origin/main`** — the merged content simply is not
  there. Every git-side check reports success while the live pack is older:
  `git ls-tree origin/main`, the anchor's `merge_result` / `merged_sha`, the PR
  state. `reconcile-rig-checkouts` ff-s each checkout forward on a 15m cooldown
  ([refinery-merge-cadence.md](refinery-merge-cadence.md), *Adjacent order*), so the window is
  usually minutes — but it is open exactly when you go to confirm the landing.
- **An untracked draft shadows the committed artifact** — a file authored in
  place at the destination path and never committed is still sitting there
  after the merge, and it is what the pack reads. It also blocks its own
  repair: `git merge --ff-only` refuses to clobber untracked files, so the
  reconciler cannot advance the checkout and files an escalation visit instead,
  leaving the rig behind *and* holding the stale draft. Because the working
  tree is the deployment, an untracked file **is** a deployed artifact,
  committed or not.

**So verify the DEPLOYED artifact, not the merged one.** In the rig root:

```bash
git rev-list --count origin/main..HEAD   # 0 = nothing local at risk
git status --short                       # ?? at a landed path = a shadowing draft
# remove superseded drafts (back them up first), then:
git merge --ff-only origin/main
diff <(git show origin/main:<path>) <path>   # deployed copy == merged copy
```

Then confirm the executable bit survived and that the artifact registered.
`gc order list` and `gc config show` re-parse **disk**, so they prove the file
is on disk and parses — not that the live supervisor picked it up. A file
event in a watched directory reloads the live set mid-sync, so sequence the
change so **one** reload observes the final state — deleting a draft before
the ff-merge logs `removed <name>` and leaves the order absent while HEAD is
already correct — and confirm re-registration in the supervisor log
(`added <name>`) rather than on disk.

## The pack's artifacts carry their own names

gc-toolkit imports no base pack: every agent, formula, and script here is
authored in this pack under its own name, mostly as pack-distinct `mol-*`
formulas, so none shadows a same-named artifact of another layer
([gascity-packs.md](gascity-packs.md#what-upstreams-docs-already-say), "Layering and names").
Keep it that way: check a new artifact's basename against any pack the
importing city composes with before adding it, and never reuse a template
`define` name you did not coin.

## A check loop's iterations are routed to a pool

A check loop gets a fresh context per iteration only when its iterations are
pool-routed, and nothing warns when they are not
([gascity-packs.md](gascity-packs.md#stepscheck-is-fresh-context-per-iteration-only-if-pool-routed)).
So pool routing is an **acceptance criterion** of any check-loop formula
here, not a preference: sling the formula at a pool target, or set the
step's `gc.run_target` to one, and verify it on the first failed iteration:

```bash
# Iteration beads carry ref <step>.iteration.N. Compare consecutive ones:
# iteration N+1 must NOT come back with iteration N's assignee.
gc bd show <iteration-N-bead> --json   | jq -r '.[0].assignee'
gc bd show <iteration-N+1-bead> --json | jq -r '.[0].assignee'
```

`mol-upstream-gc-rebase` is the pack's first check-loop adoption: it replaced
its file-a-rework-bead-and-re-pour loop with a native one, for the crash-safe
loop state the runtime keeps.

## Refresh procedure

This page states the pack's own conventions, so it changes with the pack's
code: update it in the same PR as a change to the convention it states. The
Gas City facts it links are re-verified by the refresh procedures of
[gascity-packs.md](gascity-packs.md#refresh-procedure) and
[gascity-agents.md](gascity-agents.md#refresh-procedure); when one of them
moves, re-derive the convention here that rests on it.
