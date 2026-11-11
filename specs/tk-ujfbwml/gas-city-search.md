---
name: Gas City search for renaming the converse templates under open sittings
description: Use when you need the evidence for why converse-opus, converse-fable and converse-codex stay configured after their provider-led successors land, what Gas City does to a session whose template is gone, or which primitive the withdrawal and the removal's wait compose.
---

# Gas City search: renaming the converse templates under open sittings

The change gives each converse template a provider-led name
(`converse-claude-opus`, `converse-claude-fable`, `converse-codex-sol`), adds
`converse-codex-astra`, and keeps `converse-opus`, `converse-fable` and
`converse-codex` configured but withdrawn from engage's menu and its `--model`.
It adds operational surface: four agent templates, and engage's withdrawn list
(`ENGAGE_WITHDRAWN_MODELS` in `assets/scripts/gc-helm.sh`). Each primitive
searched is below, with what it covers.

Read at `gastownhall/gascity` main 9f807760c (2026-11-05), the upstream commit
the city's gc build is synced to. Paths are in `cmd/gc/`.

## What Gas City does with a session whose template is gone

This is the reason the old templates stay, so it is read in full.

- **The reconciler never wakes one.** `classifyOverlaySession`
  (`build_desired_state.go`) resolves the session's stored template through
  `findAgentByTemplate` and returns no verdict when no agent matches, so
  `(p *decidePass) overlay` (`allocator_plan.go`) leaves the session out of
  the desired set. `(p *decidePass) classify` (`allocator_decide.go`) makes a
  row outside the desired set a Drain with `DrainReason` `orphaned`, and
  `keepReason` keeps such a row in a running city only on a partial pass, an
  uncertain observation or a pending create.
- **A running one that holds work keeps running.** `armDrainBegin`
  (`reconcile_arms_drain.go`) returns `workKept` for a Drain row with open
  work, and `drainBeginChecks` (`reconcile_effect_drain.go`) refuses an
  orphaned begin with `causeHasWork`. A sitting holding its conversation is
  therefore left running, but the reconciler never starts it again, after a
  crash or a reboot. The close effect's own residual notes that a
  `gc session attach` in another process can re-create a runtime it has just
  read as gone; that is a race with the close, not a way back.
- **Once its work is gone it stops at once, attached or not.** `drainKind`
  (`reconcile_session_decide.go`) makes the orphaned begin a plain
  `intentDrainBegin`, and `drainBeginNeeds` reads only the work leg for it, so
  no attach fence holds it. A configured sitting's stop waits for its client
  to detach.
- **Once its process is gone it closes and releases its work.** `armClose`
  (`reconcile_arms_close.go`) proposes the orphan close for a Drain row whose
  runtime is gone (`freshClosable`) and which no deliberate hold keeps
  (`deliberatelyHeldRow`). The close effect (`reconcile_effect_close.go`,
  `closeWorkStep`, `case c.Kind == closeOrphan && c.Orphaned`) releases the
  row's claims before the close, so a sitting whose process died while it held
  its conversation loses its thread and hands the conversation back.

## A rename that carries the sessions: none

`findAgentByTemplate` (`session_reconcile.go`) matches an agent by its exact
identity, and its fallback `findAgentByLegacyTemplate` resolves only the
legacy binding forms, a bound `dir/binding.name` to the unbound `dir/name` and
the reverse. No agent field names a former name, so an open session on a
renamed template matches nothing and takes the orphan path above. The old
templates therefore stay configured, with their fields unchanged, until no
open sitting runs on them.

## Taking a configured template out of engage: the menu is the pack's own

engage builds its menu and checks `--model` against the `agents/converse-*`
directories (`engage_list_models`). Gas City keeps no list of the templates a
launcher offers, so there is no Gas City switch to filter: the need is in
engage's menu, not in the sessions, whose templates must stay exactly as they
are. The withdrawal is therefore a list in engage, and `gc session new` still
takes a withdrawn template by name.

## The removal's wait: bd's blocks edge

The old templates go once no sitting holds an open conversation on them. A
sitting's conversation is a bead, so the removal bead waits on each such
conversation in its own store with a `blocks` edge, and on this change's work
bead, as the `waits` skill sets out. An open session whose conversation has
closed holds no work, so the orphan path above closes it harmlessly once its
template goes.
