---
name: Roadmap — where gc-toolkit is going
description: The living planning document — the position gc-toolkit holds toward Gas City and GasTown, a verified snapshot of what the pack is today, the primitives every addition is measured against, the directions currently in flight, and what is settled versus open. Read it to find where we are and what the next concrete step is.
---

# gc-toolkit roadmap

A living planning document. Primary purpose: **a new conversation about
gc-toolkit can open this file and quickly find where we are and what the next
concrete step is.** Secondary purpose: describe the pack's direction to
external adopters.

This document carries what is currently true and what is coming. The reasoning
behind an approach we tried and dropped is *work record*, not current truth: it
belongs in `specs/<bead-id>/` alongside the bead that retired it, per
[file-structure.md](file-structure.md). This doc links to those records rather
than carrying them, and keeps no obituaries.

## Scope

**Mandate.** Where gc-toolkit is going — the position it takes toward its
substrate and its neighbours, the primitives every addition is measured
against, the directions currently in flight, and enough of a verified snapshot
of what exists today to make "next" legible.

**Boundaries.** Direction, not construction. *How* the pack is built and how
its pieces cohere is [architecture.md](architecture.md); *why* it exists and
what it believes is [foundation.md](foundation.md); where documents are filed
is [file-structure.md](file-structure.md); the pitch and the wiring are
[`../README.md`](../README.md) and [install.md](install.md). It is also not a
bead tracker — the bead graph is the live queue, and this doc names only
direction durable enough to outlive the beads that carry it.

## Thesis

gc-toolkit takes an idea to implementation with the fewest human steps, and
makes the human steps that do exist high-bandwidth — the human sees what
matters, engages where judgment is needed, and skims the rest.

Every addition to the pack — formula, agent, skill, convention, channel —
should either reduce human steps or make a remaining human step more efficient
for the human. If it does neither, it doesn't belong.

### Gas City is the substrate

gc-toolkit is built *on* Gas City and leans on its primitives heavily. The
corollary is a hard one: **the pack must not depend on modifications carried in
a fork of Gas City.** Where a fork dependency exists today, removing it is
live work rather than an accepted fixture, and where a primitive is genuinely
missing the answer is an upstream contribution — the process for a city that
must carry local source patches, and for driving them back upstream, is
[gascity-local-patching.md](gascity-local-patching.md).

### GasTown is an example pack, not an upstream to augment

GasTown is one worked example of operating a Gas City. gc-toolkit takes from it
what is genuinely useful and is otherwise independent; **copying is actively
avoided**.

The reasoning: the core Gas City concepts are good, but GasTown's operating
model — specifically its attention and helm model — diverges from ours
materially enough that gc-toolkit is realistically **an independent
implementation of its own approach on top of Gas City**, not an augmentation
layer over GasTown.

Today the pack still imports the gastown pack wholesale at a pinned sha and
expresses its divergences as additive fragment-append patches (see
[architecture.md](architecture.md), *Composition substrate*). That import is an
inherited starting position, not a commitment: it survives exactly as long as
it is cheaper than the alternative. Proving the pack can actually leave it is
an explicit thread of the bead-universe arc below.

## What the pack is today

Verified against the tree, by listing each directory. Members are named rather
than counted, so that a claim here goes stale *visibly* — a name that no longer
resolves is a diff, a count that no longer holds is silent.

**Agents** (`agents/`) — the native roster. `mechanik`, the city-scoped
structural engineer that owns formulas, agent configs, dispatch patterns and
conventions; `bead-host`, the resident one-bead conversation, operator-spawned
and resumed rather than destroyed; `proactive`, the rig pool that runs the
cheap first reaction ahead of the operator; `polecat-codex`, the codex-provider
worker pool that executes the review signoff; and `mechanik-thread` /
`mayor-thread`, operator-spawned focus threads over the canonical roles.
`_polecat-gemini` is staged-inert — the underscore prefix disables discovery,
pending a gemini CLI command-substitution workaround (`PROVENANCE.md`). `dog`
is deliberately not vendored (`DOG-NOTE.md`); the imported gastown pack owns
that pool, along with `boot`, `deacon`, `mayor`, `polecat`, `refinery` and
`witness`. Of those, `deacon`, `mayor`, `polecat`, `refinery` and `witness` are
patched in place where our opinions differ.

**Formulas** (`formulas/`) — six. Three resident patrol loops
(`mol-deacon-patrol`, `mol-refinery-patrol`, `mol-witness-patrol`); two
doc-cohesion audits (`mol-doc-keeper-drift-audit`,
`mol-doc-keeper-memory-audit`) that run as formula-roles on the polecat pool
rather than behind a standing doc-keeper agent; and `mol-first-reaction`, the
pre-read that warms a bead before the human arrives. Scheduled entry points for
the audits and for checkout reconciliation live in `orders/`.

**Prompt composition** — `template-fragments/` holds the additive doctrine
fragments named by `pack.toml`'s `[[patches.agent]]` entries; `overlays/`
ships the `cycle-recycle` Claude `Stop` hook staged into the patrol agents.
No whole-file prompt mirrors.

**Skills** (`skills/`) — `filing-documentation`, `handoff`, `session-title`,
and the demo pair `gc-demo-script` / `demo-capture`.

**Machinery** — `assets/scripts/` carries the delivery path (`merge-skill.sh`,
`pre-open-resolve.sh`, the `reconcile-*.sh` family) and the Helm attention
board (`gc-helm.sh`), each with tests alongside; `services/helm/` is the Go
service growing up as that board's successor; `tools/` holds command entry
points and test fixtures; `doctor/` holds the anti-regression check suite, each
check a hard-won fix locked into the pack files.

**Sub-packs** (`packs/`) — `gascity-keeper` is the one, opt-in and imported
only by rigs that carry a Gas City fork: the `keeper` agent, the
`mol-upstream-gc-*` formula family, and the rebase-handling fragments.

**Docs** (`docs/`) — the central, authoritative tier, in two groups. The pack's
own record: [foundation.md](foundation.md),
[architecture.md](architecture.md), this roadmap,
[file-structure.md](file-structure.md), [install.md](install.md),
[work-bead-state-machine.md](work-bead-state-machine.md),
[rig-checkout-reconciler.md](rig-checkout-reconciler.md). And the **agent
brief** — the `gascity-*` docs an agent working in or on Gas City loads as
context: [gascity-reference.md](gascity-reference.md) indexes upstream
documentation and holds the bar for adding a new one;
[gascity-agents.md](gascity-agents.md),
[gascity-packs.md](gascity-packs.md),
[gascity-routing-model.md](gascity-routing-model.md) and
[gascity-local-patching.md](gascity-local-patching.md) carry what upstream does
not.

## Guiding primitives

The operating model the pack *runs on* — one substrate, two laws — is
[architecture.md](architecture.md)'s subject. What follows is the planning
filter: what an addition is checked against before it earns a place.

### Branded context channels

Every user-facing surface — agent name, document path, bead type, subject
prefix — must carry a recognizable brand. When the operator sees a branded
agent name or opens a file like `architecture.md`, the brand pre-loads the
mental model: they know the scope, the shape of the conversation, and what
context to bring.

Branded surfaces are what make engagement high-bandwidth. The operator skips to
the actual question fast because the surface itself told them the rest. General
text has no such association and forces re-orientation every time.

**Rule of thumb**: before adding a new surface, state its brand in one
sentence. If you can't, don't add it.

### Three hats, but earn the agent

A specialist domain still decomposes into three responsibilities: **partner**
(reactive — answers when asked, records what lands), **active** (seeks out —
patrols for drift between what is described and what is true, and promotes
decisions found in passing into durable records), and **library** (keeps the
data — knows what artifacts exist and retrieves the relevant ones fast).

What has changed is the realization. The hats do not imply a standing agent.
The default is a **skill or a formula-role**, loaded transiently; a standing
agent is earned only by a job that genuinely cannot be done between
invocations. Shipped practice settled this: the doc-cohesion audits wear the
active and library hats as scheduled formula-roles on the polecat pool with no
standing owner, and the personas work takes the same shape by design.

### Merge-strategy agnosticism, with a known asymmetry

gc-toolkit does not force a merge strategy. `direct`, `mr` and `pr` are all
supported, the default is a formula variable rather than a constant, and a
`direct` push rejected by a protected branch auto-promotes to a pull request.
A consuming rig picks its strategy; the pack adapts.

The honest qualification: the **merge gate is PR-shaped**. The check-set — and
therefore the codex signoff — is defined for `mr`-mode pull requests, while
`direct` mode fast-forwards to the target and closes. A rig on `direct` is
consequently ungated. That asymmetry is recorded as open below, not papered
over.

*(The consult-bead engagement model, and the `concierge` / `consult-host`
cluster built to surface it, are retired from core and removed. The record of
what was tried and why it was dropped is `specs/tk-fi68i/consult-retirement.md`.)*

## What we're building

The live directions, each rooted in an open epic. The epic is the queue; the
entry here is the direction, and it stays only while the direction does.

### Bead-Universe, post-v1 — `tk-6d0vb`

v1 built the operating model and proved it by dogfooding: the resident
one-bead host, the fed-and-fetched bead universe, the attention board, and
proactive-as-a-formula. The successor arc proves it at depth and resolves what
v1 deferred — mayor and mechanik re-engagement under resident hosts, selective
proactivity and its budget, cross-host visibility, and the self-improvement
audit loop. It also carries the leaveability thread of the thesis above:
replacing fixed-crew and pool machinery with host topology wherever that
actually earns itself.

### Personas — `tk-ae96t`

Give every LLM role a portable, reusable definition and bind it to work through
Gas City. A persona **is a skill**: a tight always-on identity plus advisory
owns and processes, loaded transiently by default. This is the concrete form of
*earn the agent* above, and it is where the architect returns — not as the
standing conversational agent that was explored and removed, but as an identity
skill plus method-skills invocable from a formula step. The model doc and the
first definitions are in flight, not landed.

### Attention Canvas — `tk-eemvf`

A pack-local web dashboard that renders the attention board as a spatial,
in-canvas console: each anchor holds a durable place, so the operator carries
many topics and switches cheaply because the environment reinstates the context
and only the delta needs reading. Settled: web rather than native, one
persistent canvas rather than OS windows, pack-local rather than a fork of the
core dashboard, and a surface that is *pulled* rather than one that interrupts.
This is also where the older "visual design candidates" idea landed a real
home: exploration runs as interactive prototypes whose oracle is the operator's
perceptual reaction, and implementation enters through a handoff bundle.

### Self-improvement loop — `tk-190fp`

Skills are hand-authored and static today, so agents re-derive the same
procedures instead of crystallizing them; memory captures facts, not reusable
procedure. The direction is a loop that distils recurring procedure into a
skill. The hard part is not authoring — it is governance, since an
auto-created skill becomes an auto-loaded instruction, and every change here
must still ride bead → PR → review like any other.

### Further review passes

The merge gate's codex signoff is the first review pass and it ships. The
original idea was broader: specialist passes that produce structured output and
bubble only the cases needing a human. GasTown ships `mol-review-leg` as a
reusable primitive to compose on. What is undrawn is the configuration shape —
which passes are pack defaults and which are per-rig opt-in — so no second
pass has been built.

## Decisions

### Settled

- **Gas City is the substrate, and the pack does not depend on a fork of it.**
  Fork dependencies are debt to remove, not a supported configuration.
- **GasTown is an example pack, not an upstream to augment.** Take what is
  useful; avoid copying; stay independent. This supersedes the earlier
  "gc-toolkit augments gastown" thesis.
- **Specialist work is a skill or formula-role by default.** A standing agent
  must earn itself with a job that cannot be done between invocations.
- **Two tiers of filing, and no third.** `docs/` is what is true now;
  `specs/<bead-id>/` is what was thought. There is no `docs/adr/` tier —
  retired reasoning lives with the bead that retired it.
- **The city never approves its own pull request.** Automated review is a gate
  that records evidence; approval is external and human.
- **The pack does not force a merge strategy**, with the PR-shaped-gate
  asymmetry noted above.
- **The pack is publishable and public.** All artifacts reference only public
  projects; no private rig names appear in pack artifacts.
- **"Gate" is the settled word for the merge check-set.** An earlier decision
  preferred "legs, not gates" on the grounds that passes are partners rather
  than walls. The merge check-set is genuinely a gate — it holds a merge on
  recorded evidence — and the shipped vocabulary says so. The partner framing
  survives where it is accurate: for the specialist passes above, which advise
  rather than hold.

### Open

- **Who owns intake.** Both laws of the operating model presume a bead already
  exists; the moment a new thing *becomes* one sits outside them, and no native
  agent owns it. Named as a deliberate gap in
  [architecture.md](architecture.md), not yet a plan.
- **Gating for non-PR strategies.** Whether `direct`-mode rigs get a gate, or
  whether the gate stays a PR-only guarantee that `direct` rigs knowingly opt
  out of.
- **Governance for generated skills.** What may create a skill, what review it
  passes, and how an auto-loaded instruction is prevented from shadowing a base
  prompt (`tk-190fp`).
- **Re-engagement under resident hosts.** What the mayor and mechanik roles
  become once each bead can hold its own conversation (`tk-6d0vb`).
- **Selective proactivity and its budget.** Which beads earn proactive work and
  how much, driven by the attention ranking rather than by a flat rule
  (`tk-6d0vb`).
- **Review-pass configuration shape.** Which passes are pack defaults versus
  per-rig opt-in, and where that configuration lives.

## Near-term

The next durable artifacts, in rough order. Not a contract.

1. Land the personas model doc and the first persona definitions, so *earn the
   agent* has a worked example rather than a principle (`tk-ae96t`).
2. Close the gating asymmetry, or record `direct` as knowingly ungated — the
   check-set should not be silently absent for a whole class of rig.
3. Take the leaveability thread far enough to answer it: name what the pack
   still takes from the imported roster that it could not readily replace
   (`tk-6d0vb`).
4. Answer intake — decide which surface owns the moment a thing becomes a
   bead, since every other flow starts there.
5. Attention Canvas exploration through to a handoff bundle, so the
   implementation loop has something concrete to enter with (`tk-eemvf`).
6. Design the self-improvement loop's governance before any generation is
   built (`tk-190fp`).

## Keeping this document honest

This roadmap goes stale in one predictable way: a claim about what exists
outlives the tree. Two habits hold it:

- **Verify the snapshot by listing, not by memory.** Anything in *What the pack
  is today* is a directory listing away from being checked, and the section is
  refreshed in the change that moves the roster — not in a later cleanup pass.
- **Retire, don't accumulate.** A direction that ends leaves this document; the
  record of why it ended goes to `specs/<bead-id>/` with its bead, and the
  reader follows a link rather than reading past an obituary. Significant
  shifts are legible through git history on this file.
