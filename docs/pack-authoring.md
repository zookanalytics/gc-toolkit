---
name: Pack authoring — gc-toolkit's own conventions
description: The conventions gc-toolkit's own formulas, scripts, skills and agents follow where Gas City leaves the choice to the pack — how a step closes and how a run declines, how step text and skills reach a pack script, why each shell block in step text makes one call, how a landed pack change is confirmed live, where a rig-scoped agent runs, the patrol-wisp cycle, and how a scan resolves an owner or an address. A pack convention; the Gas City facts beneath it are gascity/packs.md and gascity/agent-types.md.
---

# Pack authoring

This page states gc-toolkit's own authoring conventions, not Gas City
behavior. The platform facts each convention answers to are
[gascity/packs.md](gascity/packs.md), for formulas and packs, and
[gascity/agent-types.md](gascity/agent-types.md), for agents and sessions. Where a
convention rests on one of them, it links there.

## Scope

**Mandate.** The conventions gc-toolkit's own formulas, scripts, skills and
agents follow where Gas City leaves the choice to the pack: how a step closes
and how a run declines, how step text and skills reach a pack script, why each
shell block in step text makes one call, how a landed pack change is confirmed
live, the names the pack's artifacts carry, where a rig-scoped agent runs, the
patrol-wisp cycle, and how a scan resolves an owner or an address.

**Boundaries.** What Gas City itself does when a formula runs or a pack loads
is [gascity/packs.md](gascity/packs.md); agent variants, identity and session
lifecycle are [gascity/agent-types.md](gascity/agent-types.md). Each component's own job
is its row in [component-model.md](component-model.md) §4, and how work moves
end to end is [architecture.md](architecture.md).

## A step closes through `step-close.sh`

A graph.v2 step advances only by closing its own step bead, and neither
environment spelling the upstream bodies use names that bead reliably
([gascity/packs.md](gascity/packs.md#a-v2-step-advances-by-closing-its-own-step-bead-not-by-drain-ack)).
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
([gascity/packs.md](gascity/packs.md#a-v2-step-advances-by-closing-its-own-step-bead-not-by-drain-ack)).

A molecule's lifecycle is gascity's, so the refusal ends the run through
gascity's run cancel
([gascity/packs.md](gascity/packs.md#a-run-is-cancelled-through-the-supervisor-api)).
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
([gascity/packs.md](gascity/packs.md#a-formula-body-gets-no-template-pass)).
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

## Step text calls a tested script

Step text holds no procedure. Each shell block in a formula step makes one
call, to a tested pack script reached as the section above shows or to one
command such as `gc`, and anything two steps need is one script. No shell block
in step text is shellchecked, and a block runs in a test only where a suite
extracts it, while a script carries a test of its own. So the procedure lives
in the script, and the step passes the call its own facts as arguments.
Existing step text changes at its own rewrite.

A block does more than make one call when it holds control flow (`if`, `elif`,
`else`, `case`, `for`, `select`, `while`, `until`, a function definition, `&&`
or `||`) or more than one command. A sequence and a pipeline are more than one
command, and so is a command substitution that holds more than one. A
substitution that holds a single command is an argument of the command around
it. A here-document's body is data, not commands.

`tools/lint-step-text.sh` holds the rule, and `tools/lint.sh` runs it on the
files a change names. It reads every TOML string in a formula as Python's
`tomllib` decodes it, so it needs a Python 3.11 or newer on PATH. It judges
only what a change adds. It weighs each step by
the commands and the control flow of the procedures its blocks hold, and fails
a step the change makes heavier in either count. A new step fails when it holds
a procedure at all. A block the change leaves alone, or moves without editing
it, weighs nothing, so a step that only gains single calls passes, and so does
one that trades a procedure for a call. `tools/lint-step-text.in-flight` names
the branches whose formula changes were built before the rule, and a step made
heavier only by lines one of them adds draws a warning instead of a failure.

## A landed pack change is confirmed on the deployed checkout

This city imports the pack by directory, so what is live is the rig
checkout's working tree, not the merge
([gascity/packs.md](gascity/packs.md#a-directory-imported-pack-is-live-from-the-working-tree-not-from-a-merge)).
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
([gascity/packs.md](gascity/packs.md#what-upstreams-docs-already-say), "Layering and names").
Keep it that way: check a new artifact's basename against any pack the
importing city composes with before adding it, and never reuse a template
`define` name you did not coin.

## A check loop's iterations are routed to a pool

A check loop gets a fresh context per iteration only when its iterations are
pool-routed, and nothing warns when they are not
([gascity/packs.md](gascity/packs.md#stepscheck-is-fresh-context-per-iteration-only-if-pool-routed)).
So pool routing is an **acceptance criterion** of any check-loop formula
here, not a preference: sling the formula at a pool target, or set the
step's `gc.run_target` to one, and verify it on the first failed iteration:

```bash
# Iteration beads carry ref <step>.iteration.N. Compare consecutive ones:
# iteration N+1 must NOT come back with iteration N's assignee.
gc bd show <iteration-N-bead> --json   | jq -r '.[0].assignee'
gc bd show <iteration-N+1-bead> --json | jq -r '.[0].assignee'
```

`mol-polecat-work`'s `self-review` and `mol-upstream-gc-rebase`'s `rebase`
are check loops, and both are slung at a pool.

## A rig-scoped agent runs in a worktree of its rig

An agent's `work_dir` is its session's working directory, and cwd is where
`gh` and `git` resolve the repo. A directory under the city `.gc` tree
resolves to the **city** repo, so an agent that inspects a rig's PRs or
branches from such a cwd gets answers about the wrong repo.

A **rig-scoped** agent therefore runs in a git worktree of the rig it serves:
`work_dir = ".gc/worktrees/{{.Rig}}/<role>/{{.AgentBase}}"`, with a `pre_start`
hook running `assets/scripts/worktree-setup.sh` to cut that worktree from the
rig root before the session starts. This holds for the worker pools (polecat,
proactive, refinery) and for the coordination roles that shell `gh`/`git`
(the `converse-<model>` sitting templates, witness). The worktree is not the
rig's main checkout (`rigs/<rig>`), so it does not collide with the refinery's
home; `worktree-reap.sh` protects it as an agent home. The template variables
`work_dir` and `pre_start` accept are upstream's
([config reference](https://docs.gascity.com/reference/config), `Agent`).

A **city-scoped** agent (mechanik, deacon, dog) spans rigs and has no single
`{{.Rig}}`, so it stays under `.gc/agents/` and passes the repo explicitly on
each call (`gh --repo <owner>/<rig>`, `git -C <rig-root>`). A rig-scoped agent
that legitimately targets a fixed repo the same way (the gascity-keeper
`keeper`, which drives the upstream repo) declares a `# worktree-exempt:`
marker instead of taking a worktree. `assets/scripts/agent-worktree-wiring.test.sh`
holds this wiring.

## Patrol agents run a patrol-wisp cycle

A patrol agent is not a distinct Gas City variant. It is a named singleton
([gascity/agent-types.md](gascity/agent-types.md#variant-a--named-singletons-named_session))
whose prompt adds a patrol-wisp cycle on top of the standard lifecycle. The
deacon, witness and refinery are this pack's patrol agents, as they are in
upstream's gastown pack: each `[[named_session]]` declares them like any other
singleton, and their prompts implement the patrol contract below.

It is called out on its own because the contract has substantial mechanics
that pool workers and ad-hoc sessions do not have, and because regressions in
it show up as missed-MERGE_READY and stale-patrol incidents (`tk-fyzvk`,
`tk-6hm32`, `tk-yvtiv`).

### Patrol wisps

Each patrol cycle is a single bead — a **patrol wisp** — owned by
the agent. The wisp is created at cycle start, status flips through
`in_progress` while the agent works, and it is closed when the
cycle completes. The next cycle pours a fresh wisp before burning
the old one (**pour-before-burn**), so the agent always has a
discoverable hook.

Patrol wisps are **root-level**: they are not sub-beads of a
parent workflow molecule. Each cycle is its own root.

### Startup discovery (4-tier)

When a patrol agent starts (boot, restart, or recovery), it walks
four tiers before pouring a fresh wisp. The first tier that returns
work wins:

1. **In-progress wisp** — `bd list --status=in_progress
   --assignee=$GC_AGENT`. Crash recovery: pick up where you left
   off mid-cycle.
2. **Routed work bead** — `bd ready --has-metadata-key=branch
   --assignee=...`. Catches work that arrived during a
   cycle-recycle window (e.g., operator `/clear`).
3. **Open patrol wisp** — adopt the newest OPEN patrol wisp owned
   by this agent; close older duplicates as
   `orphaned cross-rotation`. Covers wisps that survived a
   rotation without being claimed.
4. **Fresh pour** — only when 1-3 are empty. Create a new patrol
   wisp and claim it `in_progress`.

In this pack the shape lives in each patrol prompt's own
startup-adopt section (wisp queries with `--include-infra`,
title-keyed adopt-before-pour) — the native agent prompts under
`agents/` carry it directly; there is no shared
startup-discovery fragment. If an agent's startup-discovery block is
missing tier 2 or 3, expect missed-MERGE_READY-style stalls.

Only refinery and deacon are held to the full walk. The other two
consumers share the fragment for its ephemeral-awareness rules
rather than for tier coverage:

- **witness** — reconcile-only by design. It monitors other agents'
  work rather than receiving branch-bearing work beads of its own,
  so tiers 2 and 3 are deliberately not asserted against it. What
  is asserted instead: every `--type=molecule` query carries
  `--include-infra`, and every one is scoped to `mol-witness-patrol`
  roots — its reconcile *burns* surplus wisps, so an unscoped query
  could adopt or destroy an unrelated molecule root.
- **boot** — reads the *deacon's* wisp as a freshness signal rather
  than reconciling one of its own, so the tiers do not apply. Its
  block is held to a positive assertion that the patrol-wisp read
  still exists at both call sites the fragment supersedes, carrying
  `--include-infra`, `--limit=0`, `--json`, the deacon `--assignee`
  and the `mol-deacon-patrol` title — and to the *absence* of any
  `--status` filter, since a just-poured wisp sits at `open` through
  the deacon's burn-then-claim window and any status filter
  false-empties the read against a healthy deacon.

### Lifecycle

Beyond what the underlying named singleton provides:

- **Restart-friendly.** A patrol agent can be killed mid-cycle
  without losing work — tier-1 recovers via the `in_progress`
  wisp. Use `gc runtime request-restart` (preferred) or
  `gc session reset` when a refresh is needed; `gc session kill`
  also works for patrols because the reconciler will respawn and
  the new instance will adopt the in-flight wisp via tier 1.
- **Handoff.** Patrols do not need explicit operator-driven
  handoff — the next cycle is the handoff. Closing the current
  wisp and the cycle-recycle behavior in the prompt template
  together carry the cadence.
- **Health.** Patrol freshness is checked by deacon's own patrol
  (`mol-deacon-patrol.toml`): a stale patrol wisp on witness or
  refinery surfaces as a deacon warning. The reconciler also
  surfaces patrol agents that are alive-but-stuck via
  `gc doctor` checks.

### Addressing

Same as the underlying named singleton — patrols use the same
QualifiedName (`<rig>/<binding>.<template>` for the rig-scoped
witness/refinery, `<binding>.<template>` for the city-scoped
deacon). See [gascity/agent-types.md, Variant A](gascity/agent-types.md#variant-a--named-singletons-named_session).

### Work routing visibility

Patrol wisps are *produced* by the patrol cycle itself and recovered through
the assignee tiers, not consumed from a routed pool. Outside work that needs a
specific patrol agent to act is assigned to it — `bd update <bead> --assignee
<patrol-qualified-name>` — with the notice every named-agent assignment owes
([deferred-dispatch.md](deferred-dispatch.md#work-assigned-to-a-named-agent-owes-a-notice)),
the same convention the pack follows for any named agent.

### Examples in the wild

- **Deacon** (`gc-toolkit.deacon`, city-scoped, `mode = "always"`):
  cross-rig gate checks, convoy dispatch, stuck-agent escalation.
  Patrol cycle: `mol-deacon-patrol.toml`.
- **Witness** (`<rig>/gc-toolkit.witness`, rig-scoped,
  `mode = "always"`): per-rig orphan worktree salvage, stuck polecat
  detection, missing-bead-owner surfacing.
- **Refinery** (`<rig>/gc-toolkit.refinery`, rig-scoped,
  `mode = "on_demand"`): merge queue processor; patrol cycle pours
  per merge-queue iteration.

## A scan resolves an owner before it calls one absent

Gas City writes a city-scoped identity bare and a rig-bound one
rig-qualified ([session model, "Canonical persisted identity
forms"](https://github.com/gastownhall/gascity/blob/main/engdocs/design/session-model-unification.md)),
so a city-scoped session's alias is bare (`gc-toolkit.gc-z0vi2`) even when
the bead it works belongs to a rig, while a pool instance or rig-scoped
singleton is rig-qualified (`gc-toolkit/gc-toolkit.nux`). Both directions
are live in one city, and which fields name a bead's holder is
[gascity/agent-types.md](gascity/agent-types.md#which-fields-name-a-beads-holder).

It costs any scan that resolves a bead's owner by exact lookup into a
session map keyed on `id, name, session_name, alias, agent_name`. When
the bead's `assignee` was written rig-qualified, no key in that map
matches and a live owner resolves to **absent**:

```
assignee "gascity/gc-toolkit.gc-z0vi2" -> absent
alias    "gc-toolkit.gc-z0vi2"         -> active  (session s-hq-wisp-q5qbl)
```

Nothing downstream catches it: "absent after exact lookup" classifies as
orphaned for pool/ephemeral identities, and the skip rule exempts only
*configured infra* identities (refinery, witness). An ephemeral work
identity falls through to source-delete + reopen —
yanking a bead out from under a live owner mid-work.

The scan resolves `gc.session_id` first, then `assignee`, then
`gc.session_name`, because only the id always names one session; the other
two can name an identity that a later session carries too
([gascity/agent-types.md](gascity/agent-types.md#which-fields-name-a-beads-holder)).
Resolve a bead against an identity its successor shares and you read the
successor's life as the dead owner's, leaving the bead `in_progress` under an
owner that never returns.

**Rule: an `absent` owner is a lead, not a verdict.** Before
classifying one as orphaned, resolve it the way the shipped witness
recipe does — *exact first, then last segment, live wins*:

1. **The exact lookup stays authoritative.** A literal map-key hit
   stands even when a normalized retry would answer differently. That
   is how a genuinely dead session still gets recovered.
2. **On a miss, retry once on the last `/`-separated segment of *both*
   sides** — `${OWNER##*/}` as shell shorthand (`##`, not `#`: the
   part to drop runs to the **last** slash, not the first), compared as
   a whole segment and never as a suffix, so `toolkit.furiosa` does not
   alias onto `gc-toolkit.furiosa`. Both sides, because both directions
   are live in one city at once: a city-scoped session's bare alias
   against a rig-qualified assignee, and a pool worker's rig-qualified
   alias against a bare assignee.
3. **A collision resolves toward life.** Baring the prefixes can collapse
   two cities' sessions onto one identity, so any candidate outside the
   dead states (`archived`, `closed`, `failed-create`) wins; only when
   *every* candidate is dead does the retry report a dead state. The retry
   can therefore turn `absent` into a live state but can never manufacture
   an orphan.

The map the lookup reads holds to the same rule. Two listed sessions can
carry one key, and `gc session list` lists the newest session first
([gascity/agent-types.md](gascity/agent-types.md#which-fields-name-a-beads-holder)), so
a map that let the later entry win would give such a key to its dead
predecessor. In the map a dead state never replaces a live one, so a shared
key reads as its live holder's state.

A step-2 hit means a live session, not an orphan. The lookup ships in
`formulas/mol-witness-patrol.toml` between the `liveness-lookup` markers,
and `assets/scripts/liveness-lookup.test.sh` executes that snippet
extracted verbatim from the formula rather than a transcription of it —
so the rule above and the running code cannot drift apart silently.

One thing narrows the exposure without closing it: **bare does not imply
a mismatch.** City-scoped singletons
(`gc-toolkit.mechanik`, `gc-toolkit.deacon`) carry bare aliases too — but
*their* assignees are written bare as well, so the exact lookup hits.
The hazard is the mismatch between the two sides, not bareness.

## A route or assignee is resolved, never spelled

The owner lookup above is the read side, where a normalizing retry recovers a
mismatch after the fact. The write side has no retry. A pool offer and an
assignment poll both compare raw strings
([gascity/routing-model.md](gascity/routing-model.md)), so a `gc.routed_to`
or an `assignee` that is merely well-formed is claimed by nobody, reports
success, and reads back clean.

Which form is correct is a property of the target's `scope`, not of its name,
and both scopes ship in one pack:

| Agents | `scope` | Identity to stamp |
| --- | --- | --- |
| dog, deacon, mechanik | `city` | `gc-toolkit.<role>` — no rig segment, so the deacon is `gc-toolkit.deacon` |
| converse-opus, converse-fable, converse-codex, polecat, polecat-codex, proactive, refinery, witness | `rig` | `gc-toolkit/gc-toolkit.<role>`, so the refinery is `gc-toolkit/gc-toolkit.refinery` |

Each agent declares its own `scope` in `agents/<role>/agent.toml`, and the
`[[named_session]]` stanzas in `pack.toml` restate it for the singletons. Read
that field for an agent the table does not name.

An author who copies a qualifier from the recipe beside the one being written
is right only when the two agents happen to share a scope. Over-qualifying a
city-scoped agent and under-qualifying a rig-scoped one produce the same
outcome: an address that matches nothing.

**Rule: resolve the identity, do not spell it.**
`assets/scripts/resolve-route.sh <name>` takes any form of a name and prints
the identity that is live. It reads `gc agent list`, keeps only the
candidates a bead in this store can be offered to (the city-scoped ones plus
`$GC_RIG`'s), and refuses an ambiguous name rather than picking one. An
unreadable roster is the absence of proof rather than proof of an empty city,
so there the name comes back unchanged on exit 3 and the caller files
unverified rather than not at all.

The witness addresses both scopes and resolves at both sites: it files a
warrant to the city-scoped dog and reads the rig-scoped refinery's queue. Its
recipes are the `warrant-file` and `refinery-stuck-escalate` blocks in
`formulas/mol-witness-patrol.toml`, which `assets/scripts/witness-route.test.sh`
and `assets/scripts/refinery-stuck-escalate.test.sh` execute as extracted from
the formula.

## Refresh procedure

This page states the pack's own conventions, so it changes with the pack's
code: update it in the same PR as a change to the convention it states. The
Gas City facts it links are re-verified by the refresh procedures of
[gascity/packs.md](gascity/packs.md#refresh-procedure) and
[gascity/agent-types.md](gascity/agent-types.md#refresh-procedure); when one of them
moves, re-derive the convention here that rests on it.
