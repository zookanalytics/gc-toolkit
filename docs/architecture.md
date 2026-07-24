---
name: Architecture — how gc-toolkit is built and coheres
description: The 30,000-ft map of gc-toolkit — the capabilities the pack delivers, the architectural pattern behind each, how they compose, and where each is defined. Read it to place a new capability, or to check an existing one for consistency.
---

# Architecture

gc-toolkit exists to run **two flows** — pre-advancing work before it claims
human attention, and carrying a filed bead through to a landed, live change —
with everything else in service of them. Three **support layers** keep the flows
healthy, and one **composition substrate** wires it all onto Gas City without
forking it. This document is the map of those pieces: what each delivers, the
architectural pattern behind it, how it plays with the rest, and where it is
defined. It is the pack's consistency check — the reference both *what's built*
and *what's built next* are measured against.

For the *why* behind the pack, see [foundation.md](foundation.md); for the
*direction* it's heading, [roadmap.md](roadmap.md); for the pitch and install,
[`../README.md`](../README.md).

## Scope

**Mandate.** How gc-toolkit's delivered capabilities are implemented and how
they compose — the architectural pattern behind each capability, the way the
capabilities fit together, and the single site where each is defined.

**Boundaries.** It names patterns and definition-sites at altitude; it is not a
contributor how-to, a config reference, or a decision tree for where to put a
change. It does not cover *why* the pack exists or what it believes
([foundation.md](foundation.md)), *where* it is headed
([roadmap.md](roadmap.md)), how documentation is *filed*
([file-structure.md](file-structure.md)), or how the pack is *installed and
wired* ([`../README.md`](../README.md), [install.md](install.md)).

## The two flows at a glance

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

## Flow 1 — Attention

*The Bead-Universe Operating Model (epic `tk-q4xaj`): pre-advance work before it
claims human attention.*

- **Delivers.** The operator engages a warmed, framed, single-bead conversation
  instead of triaging a cold queue.
- **Pattern.** *Ephemeral first-reaction worker → board hand-raise → resident
  single-bead host.* An ephemeral one-shot worker does the cheap reading and
  frames a decision, then flags the bead onto an attention board
  (escalation-inversion — the bead raises its own hand); the operator picks the
  row into a resident host that owns that one bead's conversation durably. The
  first-reaction worker is the first thing shed under session pressure, and any
  code it produces takes the codex-gated `mr` path, never a direct merge.
- **Plays with.** It is the on-ramp to Delivery: the host (or the worker, in the
  rare code case) files a sub-bead and slings it to a worker pool — it never
  merges or closes an implementation bead itself.
- **Defined in.** `agents/proactive` running `formulas/mol-first-reaction.toml`;
  the Helm attention board (`assets/scripts/gc-helm.sh` today, with the
  `services/helm/` Go service as its emerging successor); `agents/bead-host`.

## Flow 2 — Delivery

*Filed bead → landed, live change, with the fewest human steps.*

- **Delivers.** A filed bead becomes a merged, live change; the human step is an
  approval, and the machine does the rest.
- **Pattern.** *Owned-convoy close-on-land state machine* — a bead stays open
  until its PR merges, so `closed` means *landed* (a pack-only delta over stock
  GasTown, which closes at PR-creation). Multi-bead initiatives use
  *integration-branch graduation*: children target the convoy branch, only the
  convoy targets `main`, and graduation is automatic when the last child lands.
  The merge-gate is a *composable, head-bound check-set* — codex signoff, CI,
  human approval, and title/description-current are each a marker pinned to the
  live head (`green@<head>`), so any new commit re-gates and a stale approval
  can't carry a drifted PR; codex runs *pre-open* so the PR is green at birth.
  A single-writer *merge skill* auto-lands once every gate is green, then live
  rig checkouts *fast-forward sync* to the merged tip.
- **Plays with.** It consumes Attention-flow dispatch (a sling turns a filed
  bead into a convoy plus pool demand); the engine-health layer keeps its
  agents alive and the doctor suite fences it against regression.
- **Defined in.** [work-bead-state-machine.md](work-bead-state-machine.md)
  (canonical); `template-fragments/convoy-integration-branch` (+ the polecat-side
  `polecat-convoys`); `formulas/mol-refinery-patrol.toml` with
  `assets/scripts/merge-skill.sh`, `pre-open-resolve.sh`, and
  `reconcile-graduated-convoys.sh`; `orders/reconcile-rig-checkouts.toml` +
  [rig-checkout-reconciler.md](rig-checkout-reconciler.md);
  `doctor/check-merge-gate-drop`.

## Support — Engine health

*Keep both flows running across restarts and context exhaustion, unbabysat.*

- **Delivers.** The long-running agents stay live, resume in-flight work after a
  restart instead of orphaning it, and recycle themselves before context
  degrades.
- **Pattern.** *Resident self-recycling patrol loops* (each pours its next
  iteration before burning the current one) + *layered, idempotent
  startup-discovery* (ordered fallback tiers that resume or adopt in-flight work
  and converge to exactly one patrol wisp) + a *deterministic cycle-recycle
  hook* (a Claude `Stop` hook the harness fires at every turn boundary, so the
  recycle happens regardless of how full context is) + an *anti-regression
  check-suite* (each doctor check locks a hard-won fix into the pack files so it
  cannot silently regress).
- **Plays with.** The patrols keep the witness and deacon (Attention side) and
  the refinery (Delivery side) alive and resumable; the doctor suite fences the
  Delivery machinery as well as the patrol loops themselves.
- **Defined in.** `formulas/mol-{deacon,refinery,witness}-patrol.toml`;
  `template-fragments/layered-startup-discovery`; `overlays/cycle-recycle`;
  `doctor/check-*`.

## Support — Fork & upstream

*For a city that must carry local `gascity` source patches: keep the divergence
minimal and drive it back upstream.*

- **Delivers.** Local patches to the Gas City source live on a fork without a
  hand-managed patch queue, and flow back upstream as reviewable PRs.
- **Pattern.** *Git-native candidate-set model* — every commit on `origin/main`
  that diverges from `upstream/main` *is* an upstream candidate, so the git log
  is the queue (no held branches, no labels) — plus *commit-body-as-review-packet*
  (the commit message is the upstream PR), executed by a *keeper-fronted,
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

## Support — Doc & knowledge cohesion

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
  briefs; this map itself is kept consistent by the forward-lever discipline
  below, not by the audits.
- **Defined in.** [file-structure.md](file-structure.md);
  `formulas/mol-doc-keeper-{drift,memory}-audit.toml`;
  `orders/doc-keeper-{drift,memory}-audit.toml`.

## Composition substrate

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

This document is the lever that keeps growth coherent. A new capability should
slot into one of the two flows or a support layer and reuse that layer's
pattern; if it fits none of them cleanly, that is the signal — either the
capability is miscast, or the map itself needs a deliberate extension. Keeping
new work consistent with this map is how *what gets built next* stays coherent
with *what's built*.
