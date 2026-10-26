---
name: Gas City search for a visit's topic
description: The search the arch check asks for before the pack adds the visit_topic key and visit-topic.sh. What Gas City, the packs it publishes and bd ship for telling apart two conversations with a person on one subject, and for keeping each one's waits its own, read at named upstream commits, and why the pack keeps a visit's topic as metadata of its own. Read it when checking whether a visit's topic, or the definition that derives it, can move onto a Gas City primitive.
---

# Gas City search for a visit's topic

This change gives a visit filed for a distinct concern a topic of its own.
`gc-helm.sh open --allow-duplicate` stamps `visit_topic=own` on the visit it
files, and `visit-topic.sh` turns a visit's stamps into the topic that
converse's fold, hold and sign-off compare. So the arch check asks what Gas
City already ships for that need
([review-arch.md](../../docs/review-arch.md#the-checks), check 1). Nothing Gas
City ships records, when a bead is filed, that it is a separate conversation
from another bead on the same subject, and its gates and waits carry no topic.
Each of its exclusivity primitives keeps one live holder per key and takes
that key from its caller. A visit's topic is that key. The pack keeps it as
metadata, which bd names as the extension point for an orchestrator's
workflow data.

## The surface and the need

- `visit_topic` is a metadata key on a visit, registered in `lifecycle.toml`.
  `gc-helm.sh open` writes `visit_topic=own` in the create payload of every
  visit it files with `--allow-duplicate`. `engage` passes that flag when the
  operator asks for a new visit with a reason, a template or a skill, or picks
  a new visit at the prompt.
- `assets/scripts/visit-topic.sh` is the one definition of a visit's topic.
  `converse-fold.sh`, `converse-hold.sh` and `converse-signoff.sh` source it.
  It decides the kind of topic once: the visit's `escalation_key`, the visit
  itself, or its subject. It then gives each reader its encoding. The fold
  compares `key:<key>`, `visit:<visit-id>` or the subject, and a sitting's
  demands carry the key, `visit:<visit-id>`, or no topic.

The need has two parts. When a sitting claims a visit, the fold must tell a
visit filed for a distinct concern apart from a live sitting on the same
subject, so that neither folds into the other. When two sittings on one subject
each hold, the human gate each files on a shared bead must stay its own, so one
sitting's hold does not refresh the other's question and one ruling does not
resolve the other's wait. Both parts lack the same thing: a key the filer sets
when a second visit on a subject is filed on purpose.

## Where the search looked

Each was read on 2026-10-26:

- Gas City at main `3fb225b904e0`: its documentation, its engineering docs,
  the `core` pack it bundles, and its source.
- Every pack Gas City publishes, at `dac12a4a802c`, including `pr-review` and
  `profiler`, which the packs' registry does not list.
- bd at `596531419be9`.

The search covered continuation groups and session affinity, gates, waits and
the questions a session asks, any topic or scope on those, dedup and
idempotency keys, duplicate and thread links, conversation identity, and
escalation keys. Each pack's hits were tallied, and the hits about sessions,
gates and waits were read. In the chat packs, whose thread and conversation
hits run to thousands, the code that routes a conversation to a session was
read.

## What Gas City ships near the need

### Continuation groups and session affinity

The [Formula Spec v2](https://docs.gascity.com/reference/specs/formula-spec-v2)
makes `continuation_group` a key of a shared drain, valid only with
`context = "shared"` (section 3.3), and makes `gc.continuation_group` reserved
step metadata that needs the v2 declaration (sections 2 and 5). The
engineering design *Agent Pools & Autoscaling*, in "Graph workflow
continuity", says continuation is always formula-declared. Claiming one
executable step pre-assigns its workflow siblings to the same persistent
session, to keep its worktree and conversation context. In the `gc` command,
`preassignHookContinuationGroup` does nothing for a bead without a
`gc.root_bead_id` or a group, and otherwise pins only open, unassigned
siblings that share both. Graph routing pins `gc.session_affinity=require`
beside a formula-declared group. The controller's continuation backstop
qualifies a step only when both keys are set (`continuationRowCouldBeCandidate`),
checks the step's workflow root again before it acts, and re-delivers the claim
nudge to the pool session the step was pre-assigned to
(`nudgeStalledPoolContinuations`). Package `beadmeta` lists both keys in
`SessionAffinityMetadataKeys`, which must be cleared together whenever work is
rerouted off its original session without a preserved assignee.

A continuation group gathers one workflow's steps onto one session. The pack
files a visit with no `gc.root_bead_id`, so continuation never acts on one.
The need also runs the other way: it keeps a second sitting apart from a live
one on the same subject. And a key that Gas City clears when work is rerouted
off its session cannot hold a topic that has to outlive a sitting. The pack
does stamp a visit's subject in `gc.continuation_group`, beside the visit's
`tracks` edge, and `visit-identity.sh` reads the stamp only when that edge is
missing. The packs that use groups (`gascity`, `superpowers`, `bmad`,
`compound-engineering` and `gstack`) declare them on formula steps. Most group
the steps that apply a review's findings, and `superpowers` keeps the steps of
one development item under a group named for its issue.

### Gates, waits and questions

- bd's [gate](https://beads.gascity.com/cli-reference/gate) is a bead that
  blocks one issue. `bd gate create` takes a type (`human`, `timer`, `gh:run`
  or `gh:pr`), the issue it blocks, a reason, a title, a timeout and an
  `--await-id`, which bd calls the condition identifier, such as a run ID or a
  PR number. A human gate waits for a manual `bd gate resolve`. bd gives a gate
  no field for the conversation it belongs to, so two gates on one bead are
  told apart only by what their caller writes on them.
- A formula's `[steps.gate]` table (`type`, `id`, `timeout`) compiles to a
  sibling gate bead that blocks its step. The formula spec lists the gate's
  `type` vocabulary as accepted but inert: no bundled watcher acts on it, and
  no bundled formula uses `gate` (sections 2 and 4).
- A session wait is a wait bead registered against one session (package
  `session`, `WaitSpec`). It records the beads it watches, whether it needs all
  or any of them closed, and a note delivered when they do
  ([`gc session wait`](https://docs.gascity.com/reference/cli#gc-session-wait),
  [`gc wait`](https://docs.gascity.com/reference/cli#gc-wait)). It adds no
  dependency edge, so it blocks nothing.
- A pending interaction is a question a live session stops to ask, such as a
  tool approval prompt. The
  [API reference](https://docs.gascity.com/reference/api#pending-interactions)
  lists them per session and city-wide, and clears one when it is answered,
  withdrawn or replaced, or when its session is gone.
- The `core` pack's `notify-on-human-gate-creation` and
  `renudge-stale-human-gates` orders mail and nudge the addressee of an open
  human gate, once per gate and again past a staleness threshold. They take the
  addressee from the gate's assignee, then its `gc.deferred_assignee`, then the
  city's escalation recipient.
- A `gc converge` loop is a root bead whose gate, manual, a condition script or
  both, decides whether it runs again. A person answers a manual gate with
  `gc converge approve` or `gc converge iterate` on the loop's bead.

None of these carries a topic, and a session wait and a pending interaction
each belong to one session. A sitting's demand is the other direction: an
answer a person owes, which blocks the bead it gates and outlives the sitting
that asked for it. No published pack creates a bd gate or reads `await_type`.
The `gascity` pack's human checkpoints, in its `github-pr-review`,
`github-issue-triage-base` and `github-issue-fix-base` workflows, and
`superpowers`' approval steps park the session with
`gc session wait --sleep --on-beads` on the step bead itself, record the
checkpoint on their own run's root, and mail a person once. Each question there
has a step bead of its own, so no two questions share a bead.

### One live holder per key

Gas City keeps one live holder per key in several places. Each takes the key
from its caller.

- A session alias is exclusive among open sessions (package `session`,
  `AliasConflictInfo`), and
  [`gc session new --alias`](https://docs.gascity.com/reference/cli#gc-session-new)
  sets it.
- An external-messaging binding links one external conversation to one session
  or agent, and binding a conversation that is already bound conflicts
  ([`gc extmsg bind`](https://docs.gascity.com/reference/cli#gc-extmsg-bind);
  package `extmsg`, `Bind`). The client names its conversations: it picks a
  stable `conversation_id` for each call, chat thread or channel, and a
  `scope_id` that namespaces them
  ([Connect an external client](https://docs.gascity.com/guides/connected-clients)).
- [`gc mail send --dedup`](https://docs.gascity.com/reference/cli#gc-mail-send)
  suppresses a send while a live message with the same key sits in the
  recipient's mailbox.
- `gc sling` refuses to launch a formula on a bead while a run of that formula
  on it is still live (package `sling`, `checkLegacySourceWorkflowConflict`).
- Attaching a sub-DAG to a workflow under an idempotency key reuses the one
  already attached under that key (package `molecule`, `findExistingAttach`).

Each makes a key exclusive and leaves the choice of key to its caller. None
decides which visits on one subject are one conversation. The pack makes that
choice. A visit `escalate.sh` files carries its situation's key, a visit filed
for a distinct concern is its own topic, as the operator ruled, and any other
visit's topic is its subject.

External messaging needs a closer look, because a binding is a conversation
held by one session. Its engineering design, *External Messaging Fabric*, says
Gas City's mail, nudges and session input are "enough for internal
agent-to-agent and human-to-agent work", and it adds the external conversation
as a first-class object beside them. A sitting is human-to-agent work: the
operator attaches to its session. A binding could at most stand in for the
fold's rule of one live sitting per topic, which predates this change. Using
one would route the operator's turns through a connected client, and the
binding's `conversation_id` would still need the key this change records.

### Telling two items apart

bd's [graph links](https://beads.gascity.com/core-concepts/graph-links) record
a relation once a caller has decided it. `bd duplicate <id> --of <canonical>`
marks a duplicate and closes it, `replies-to` threads messages, and
`relates-to` links two issues both ways. bd's two finders judge sameness by
content. [`bd duplicates`](https://beads.gascity.com/cli-reference/duplicates)
groups issues whose title, description, design and acceptance criteria hash
alike, and
[`bd find-duplicates`](https://beads.gascity.com/cli-reference/find-duplicates)
uses text similarity, or a model, to find issues "that discuss the same topic
with different wording". A visit filed for a distinct concern is distinct
because the operator said so when filing it, whatever its text says, so a
judgment by content cannot honor it. A session's `--title` is a human-readable
label ([`gc session new`](https://docs.gascity.com/reference/cli#gc-session-new)).

### The packs Gas City publishes

No published pack decides whether two beads are one conversation, or scopes a
person's question on a bead that several sessions share.

- The chat packs separate concurrent conversations by the platform's own
  identity. `slack-full`'s adapter keeps a thread-to-session registry
  (`threadSessionRegistry`) for its launcher mode, to converge later posts in a
  thread on one agent session. `discord` gives each managed launcher thread a
  session of its own. A new concern starts a new thread, and the platform's
  thread id is the key.
- `oversight-rig` delivers a rig's escalations to the channel its project-lead
  session is bound to, so a rig's escalations share one conversation.
- `gastown` dedups a repeating notification with `gc mail send --dedup`, and
  files at most one open warrant per target.
- `bmad`'s brainstorming skill names each session's output folder for its
  topic, so several brainstorms on one project do not collide.

## What the change does with it

The change composes what Gas City ships for each part, and keeps only the key.

- Engage spawns each sitting with its visit's id (or a `v-` form of it) as the
  session alias, so Gas City's alias reservation already allows one sitting per
  visit. A visit with a topic of its own takes that same identity, the visit,
  as its topic. The fold then never merges it with a sibling, and its demands
  carry the visit's id.
- A demand is bd's human gate, filed with
  `gc bd gate create --type=human --blocks`. The pack already writes a demand's
  topic on the gate, in `gc.demand_topic` and in the `--await-id` handle it
  recovers an uncertain create by. The change adds one value of that topic,
  `visit:<visit-id>`.
- The stamp is metadata, which bd's
  [Issue Metadata](https://beads.gascity.com/core-concepts/metadata) page names
  as the preferred extension point for data specific to an orchestrator or a
  team workflow. It uses neither of bd's reserved prefixes. It rides the
  create, so no sitting can claim the visit without it.
- `visit-topic.sh` turns a visit's stamps into its topic in one place, so the
  fold and the demands derive the same key from one decision. It is a jq
  definition its readers source, and it makes no call and keeps no state.

The change adds a metadata key and a sourced definition, and no bead kind or
lifecycle state, so it adds no pack noun and needs no warrant
([review-arch.md](../../docs/review-arch.md#the-checks), check 2). This answer
changes if Gas City ships a conversation identity that a filer can give a bead,
or a topic on a gate that its lookup and resolution key on. Either would be the
primitive to move the topic onto.
