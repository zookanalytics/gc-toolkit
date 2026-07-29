---
name: Architecture — how gc-toolkit is built and coheres
description: The 30,000-ft guide to gc-toolkit, leading with the operating model — one substrate (the bead) and two localities, truth and attention, with intake named as the open gap — then the model in motion, then the map of what the pack delivers, the architectural pattern behind each capability, and where each is defined. Read it to know what the system is, to place a new capability, or to check an existing one for consistency.
---

# Architecture

gc-toolkit has **one substrate and two laws**. The substrate is the **bead**;
the laws say where an artifact's *truth* lives and where its *dialogue* lives.
Nearly everything the pack builds is a consequence of those two laws — so this
document states the model first, shows it in motion, and only then maps the
pieces that implement it. That map doubles as the pack's consistency check: the
reference both *what's built* and *what's built next* are measured against.

For the *why* behind the pack, see [foundation.md](foundation.md); for the
*direction* it's heading, [roadmap.md](roadmap.md); for the pitch and install,
[`../README.md`](../README.md).

## Scope

**Mandate.** The operating model gc-toolkit runs on — its substrate and the two
laws over it — and how the pack's delivered capabilities implement that model:
the architectural pattern behind each capability, the way the capabilities fit
together, and the single site where each is defined.

**Boundaries.** It names the model and the patterns and definition-sites at
altitude; it is not a contributor how-to, a config reference, or a decision tree
for where to put a change. It does not restate the work-bead state machine
([work-bead-state-machine.md](work-bead-state-machine.md) is canonical for that),
and it does not cover *why* the pack exists or what it believes
([foundation.md](foundation.md)), *where* it is headed
([roadmap.md](roadmap.md)), how documentation is *filed*
([file-structure.md](file-structure.md)), or how the pack is *installed and
wired* ([`../README.md`](../README.md), [install.md](install.md)).

## The model

**The bead is the substrate.** One kind of object carries everything: a unit of
work, a PR, a branch, a multi-step initiative, a conversation. Two laws govern
it, and both say the same thing — *the bead is the locus*.

### Law 1 — locality of truth

**The bead owns the artifact.** This law is canonical and already written; it is
stated, with its full state machine, in
[work-bead-state-machine.md](work-bead-state-machine.md) ("everything is owned").
One doc per subject: that one owns the machine, this one only names the law and
its consequences.

- every PR, branch, and unit of work has **one owning bead** — the single locus
  of its truth, queryable without a tree-walk;
- **open = unlanded, closed = landed** — nothing in between reads as done;
- **one bead or many is the same machine** — a lone bead-to-`main` is the
  *degenerate one-child convoy*, a multi-bead initiative a *many-child convoy*;
- the merge-gate is **one class of gate** — a composable check-set whose members
  (signoff · CI · approval · title/description-current · merged) are the same
  kind of thing, none privileged;
- an artifact with **no owning bead is an exception the board catches** —
  surfaced high, never a silent drop.

### Law 2 — locality of attention

**The bead owns the conversation about it.** The dual of Law 1, and stated here
for the first time: it names as a *law* what the pack has so far shipped only as
an agent. Its consequences:

- **one bead, one conversation** — discussion lives on the bead as a resident,
  durable, resumable session whose alias *is* the bead id, suspended rather than
  destroyed when the operator leaves (`agents/bead-host`);
- **the bead raises its own hand** — a bead's LLM flags itself onto the
  attention board instead of the operator scanning a queue; escalation
  inversion, the dual of mailing the mayor (`assets/scripts/gc-helm.sh`);
- **the operator arrives warmed and framed** — a cheap first reaction reads the
  bead's universe and leaves a fixed-shape card (*understanding · found ·
  proposal · decision needed*) before the human ever looks, so picking a row
  lands in an advanced conversation, not a cold one
  (`agents/proactive` running `formulas/mol-first-reaction.toml`).

The symmetry is deliberate and is the whole simplification: **Law 1 is where an
artifact's truth lives; Law 2 is where its dialogue lives.** Both answer "where
does this belong?" with *the bead*.

### The hole — intake

Both laws presume a bead already exists. **Intake — the moment a new thing
becomes one — is the single step that sits outside both**, because there is
nothing yet to own the truth or to host the conversation. The model predicts the
gap, and the pack shows it: `agents/` ships no native intake agent, and every
native role is a *post-bead* role — a host is spawned only at an existing bead
and explicitly refuses to be a sling target; a first reaction is slung *at* a
bead. The one roster member that might plausibly front intake, `mayor`, is
imported from gastown and fragment-patched, not designed here.

This is a named gap, not a plan. Which agent owns the front door is an open
design decision, deliberately unmade.

## How it runs

Three walkthroughs — the laws in motion.

**1. Idea → bead → board → host.** An idea becomes a bead; a first reaction
reads its universe and writes a card; the bead flags *itself* onto the Helm; the
operator picks the row and lands in that bead's resident host, already primed.
Everything from "bead" rightward is machinery — the *first* arrow is the hole
above, and it is still a human typing.

**2. Bead → convoy → merge-gate → landed.** The single-bead path, which is the
degenerate one-child convoy. A sling makes the convoy; a worker builds on its
branch and hands off to the refinery; the codex signoff runs *pre-open*, so the
PR is green at birth; the rest of the check-set — CI, human approval — clears at
the live head, where any new commit re-gates. The merge skill lands it and the
bead closes: closed = landed.

**3. Multi-step initiative.** The same machine with many children. The convoy
holds an integration branch, each child targets *that* branch instead of `main`,
and when the last child closes the convoy graduates through the identical
open → PR → check-set → merge path one level up. Only a convoy ever targets the
protected boundary.

## The map

What the pack actually ships, and where each piece lives. The two flows are the
two laws in running code; three support layers keep them healthy, and one
composition substrate wires it all onto Gas City without forking it.

```
                     ┌──────────────── Attention ─────────────────┐
   new / filed bead ─▶  proactive  →  Helm board  →  bead-host     │
                     └────────────────────┬───────────────────────┘
                                          │ files & slings a work bead
                     ┌────────────────────▼──────────── Delivery ──┐
                     │  sling  →  owned convoy  →  merge-gate       │
                     │  (codex pre-open + CI + human approval)      │
                     │  →  merge-skill lands  →  rig-checkout sync  │
                     └─────────────────────────────────────────────┘

   Support layers (keep both flows healthy, unbabysat):
       engine-health · fork & upstream · doc & knowledge cohesion
   Composition substrate (how it's wired):
       gastown imported wholesale + additive bare-name fragment-append patches
```

### Flow 1 — Attention

*Law 2 in running code (the Bead-Universe Operating Model, epic `tk-q4xaj`).*

- **Delivers.** The warmed, framed, single-bead conversation instead of a cold
  queue.
- **Pattern.** *Ephemeral first-reaction worker → board hand-raise → resident
  single-bead host.* The worker is the first thing shed under session pressure,
  and any code it produces takes the codex-gated `mr` path, never a direct merge.
- **Plays with.** The on-ramp to Delivery: the host (or the worker, in the rare
  code case) files a sub-bead and slings it to a worker pool — it never merges
  or closes an implementation bead itself.
- **Defined in.** `agents/proactive` running `formulas/mol-first-reaction.toml`;
  the Helm attention board (`assets/scripts/gc-helm.sh` today, with the
  `services/helm/` Go service as its emerging successor); `agents/bead-host`.

### Flow 2 — Delivery

*Law 1 in running code: filed bead → landed, live change, with the fewest human
steps.*

- **Delivers.** A filed bead becomes a merged, live change; the human step is an
  approval, and the machine does the rest.
- **Pattern.** *Owned-convoy close-on-land state machine* — a bead stays open
  until its PR merges (a pack-only delta over stock GasTown, which closes at
  PR-creation) — plus *integration-branch graduation* for multi-bead
  initiatives, and a *composable, head-bound check-set* in which every gate is a
  marker pinned to the live head (`green@<head>`), so a new commit re-gates and
  a stale approval can't carry a drifted PR. Codex runs pre-open; a single-writer
  *merge skill* auto-lands once every gate is green, then live rig checkouts
  *fast-forward sync* to the merged tip.
- **Plays with.** It consumes Attention-flow dispatch (a sling turns a filed bead
  into a convoy plus pool demand); the engine-health layer keeps its agents alive
  and the doctor suite fences it against regression.
- **Defined in.** [work-bead-state-machine.md](work-bead-state-machine.md)
  (canonical); `template-fragments/convoy-integration-branch` (+ the polecat-side
  `polecat-convoys`); `formulas/mol-refinery-patrol.toml` with
  `assets/scripts/merge-skill.sh`, `pre-open-resolve.sh`, and
  `reconcile-graduated-convoys.sh`; `orders/reconcile-rig-checkouts.toml` +
  [rig-checkout-reconciler.md](rig-checkout-reconciler.md);
  `doctor/check-merge-gate-drop`.

### Support — Engine health

*Keep both flows running across restarts and context exhaustion, unbabysat.*

- **Delivers.** The long-running agents stay live, resume in-flight work after a
  restart instead of orphaning it, and recycle themselves before context degrades.
- **Pattern.** *Resident self-recycling patrol loops* (each pours its next
  iteration before burning the current one) + *layered, idempotent
  startup-discovery* (ordered fallback tiers that resume or adopt in-flight work
  and converge to exactly one patrol wisp) + a *deterministic cycle-recycle hook*
  (a Claude `Stop` hook fired at every turn boundary, so recycling happens
  regardless of how full context is) + an *anti-regression check-suite* (each
  doctor check locks a hard-won fix into the pack files).
- **Plays with.** The patrols keep the witness and deacon (Attention side) and the
  refinery (Delivery side) alive and resumable; the doctor suite fences the
  Delivery machinery as well as the patrol loops themselves.
- **Defined in.** `formulas/mol-{deacon,refinery,witness}-patrol.toml`;
  `template-fragments/layered-startup-discovery`; `overlays/cycle-recycle`;
  `doctor/check-*`.

### Support — Fork & upstream

*For a city that must carry local `gascity` source patches: keep the divergence
minimal and drive it back upstream.*

- **Delivers.** Local patches to the Gas City source live on a fork without a
  hand-managed patch queue, and flow back upstream as reviewable PRs.
- **Pattern.** *Git-native candidate-set model* — every commit on `origin/main`
  that diverges from `upstream/main` *is* an upstream candidate, so the git log
  is the queue (no held branches, no labels) — plus
  *commit-body-as-review-packet*, executed by a *keeper-fronted,
  polecat-executed, refinery-landed* division of labor: the keeper only converses
  and dispatches, a polecat does the rebase, the refinery performs the one
  authorized force-push to land, and upstream-PR submission stays operator-gated.
- **Plays with.** An opt-in sub-pack layered over core that reuses the same
  polecat → refinery Delivery substrate; the *doctrine* half ships in core
  (injected into `mechanik`), the *machinery* half in the sub-pack.
- **Defined in.** `packs/gascity-keeper` (the `keeper` agent, the
  `mol-upstream-gc-*` formula family, the `refinery-rebase-handling` fragment);
  `template-fragments/upstream-engagement` (doctrine);
  [gascity-local-patching.md](gascity-local-patching.md).

### Support — Doc & knowledge cohesion

*Keep what's written true as the world moves.*

- **Delivers.** The pack's agent-brief docs stay both true and complete without
  hand edits.
- **Pattern.** *Two-tier filing* (`docs/` = what's true now, authoritative;
  `specs/<bead-id>/` = what was thought, historical) + a pair of *complementary
  automated audits*: a drift audit catches a brief claim made *false* by upstream
  movement, and a memory audit catches an in-scope learning *missing* from a
  brief. Each runs on a cooldown schedule and routes every correction through the
  normal bead → polecat → refinery-PR pipeline; there is no standing "doc-keeper"
  agent — it is a formula-role on the polecat pool.
- **Plays with.** Every fix rides Flow 2 (Delivery). The audits target the agent
  briefs; this map itself is kept consistent by the forward lever below, not by
  the audits.
- **Defined in.** [file-structure.md](file-structure.md);
  `formulas/mol-doc-keeper-{drift,memory}-audit.toml`;
  `orders/doc-keeper-{drift,memory}-audit.toml`.

### Composition substrate

*How everything above is wired, and where each piece lives.*

- **Delivers.** All of the above composes onto a running Gas City by
  configuration, not by forking — and every piece has exactly one definition-site.
- **Pattern.** *Import the gastown base pack wholesale at a pinned sha, then
  express every divergence as an additive, bare-name fragment-append patch* —
  never a whole-file prompt mirror, never a fork — plus *opt-in sub-packs* for
  rig-specific doctrine and *overlay dirs* for harness hooks. Native agents ship
  under `agents/`; the imported roster is patched in place.
- **Plays with.** This is the ground every flow and layer stands on; the seam
  between the native and imported roster is where gc-toolkit's opinions attach.
- **Defined in.** `pack.toml` (`[imports.gastown]`; the `[[patches.agent]]`
  fragment lists; `overlay_dir`); `template-fragments/*`; `packs/*`;
  [install.md](install.md). Native agents (`mechanik`, `bead-host`, `proactive`,
  `polecat-codex`, `_polecat-gemini`, the `*-thread` variants) vs the imported
  gastown roster (`boot`, `deacon`, `mayor`, `polecat`, `refinery`, `witness`),
  patched in place where gc-toolkit's opinions differ; `dog` is intentionally not
  vendored (`agents/DOG-NOTE.md`).

**Steward.** `mechanik` owns the pack's evolution; changes to versioned content
flow through beads to polecats (dispatch, don't hand-edit).

## The consistency map

This document is the lever that keeps growth coherent. The sharp test is the
model, not the map: a new capability should be a **consequence of Law 1 or
Law 2** — or an honest, named exception like intake — and it should slot into one
of the two flows or a support layer and reuse that layer's pattern. If it fits
none of them cleanly, that is the signal: either the capability is miscast, or
the model itself needs a deliberate extension. Keeping new work consistent with
this map is how *what gets built next* stays coherent with *what's built*.
