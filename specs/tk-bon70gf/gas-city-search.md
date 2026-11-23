---
name: Gas City search for a key's motion (tk-bon70gf)
description: The primitive searched in Gas City for marking a bead whose work is in motion, or one its declaring domain carries out itself, and why the key registry's declaration covers what it leaves. Read it when reviewing the motion options in services/gctk/internal/ledger/keys.go, as AGENTS.md asks of a change that grows a registry's output and adds a refusal.
---

# Gas City search for a key's motion

This change adds two options to a key's declaration in gctk's ledger,
`InMotion` and `CarriedOut`, a `motion` field to each entry of
`services/gctk/key-registry.json`, and one refusal to the first reaction's
check, for a bead its domain carries out itself. It adds no bead key, no bead
kind and no order. The first reaction's sweep reads the declarations in place
of its own list of keys, so a domain that files a bead of a new kind marks the
key it files it with where it declares that key, and the sweep and the check
both hear of it.

## Who moves a bead next

Searched at `gastownhall/gascity` main 21ad051d002e (2026-11-23).

Gas City says whose move a bead is in two ways. A route, `gc.routed_to`, makes
an open bead no session holds a pool's demand:
`collectOpenUnassignedRoutedWork` (`cmd/gc/build_desired_state.go`) collects
the open, unassigned, routed beads each pool is demanded for. An assignee says
a session holds the bead. The first reaction's check already refuses both
(`rowRefusal` and `dispatchPaths` in `services/gctk/reaction/refusal.go`), and
its sweep drops a routed bead.

Neither covers a withdrawal of a PR's approvals. The landing order, an exec
order with no session, carries it out and closes it. A route would make it a
pool's demand, which a pool session would claim and could not carry out, and an
assignee names a session, which an exec order is not. The demand read holds no
other mark of whose move a bead is, so none covers a bead an exec order owns,
or a bead whose work is in motion under keys the pack writes, such as a PR's
branch and merge result.

So the mark sits on the key, in the declaration the ledger already requires of
every key a gctk domain writes, and the registry, which lists every
declaration, answers the sweep and the check.
