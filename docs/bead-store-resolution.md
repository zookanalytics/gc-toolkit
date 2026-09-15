---
name: bead-store-resolution
description: How a bead id names the store that owns it, and why a gate that destroys on bead-absence has to resolve that store before concluding anything.
---

# Bead store resolution

## Scope

**Mandate.** Deriving the store that owns a bead from its id, and the standard
of proof a gate owes before it acts on that bead's absence.

**Boundaries.** Which store a bead should have been created in is
[the component model](component-model.md)'s, and what a disposition writes when
a bead moves is [the state machine](state-machine.md)'s. This doc speaks only
to reading: given an id, which store answers for it, and what its silence means.

## A lookup resolves a live id but not its absence

Every bead id begins with a prefix its store owns — `tk-` for gc-toolkit,
`su-` for shutupandlisten, `lx-` for the city's own store. The prefix is the
whole of that binding, and nothing else in a lookup carries it. An unpinned
`gc bd show` resolves a live id from whichever store holds it, wherever the
caller stands. What it cannot carry is an absence: a miss is answered by the
store the caller happens to be standing in, not the one the prefix names, so a
bead absent from another store returns exactly what a bead that exists nowhere
returns —

```
{"error":"no issues found matching the provided IDs","schema_version":1}
```

— on the same exit code, with the same text. The caller cannot tell "wrong
store, ask elsewhere" from "no such bead anywhere".

`--rig` narrows that to one rig's store rather than fixing it, and it cannot
name the city's own store at all: `gc --rig <hq-rig> bd list` answers empty
where `gc bd --db <city>/.beads list` answers. Only a `--db` path reaches
every store, the city's included.

## A flag's value can select the store

Resolution reads the id out of the command's arguments. It walks them left to
right, skips every argument that begins with `-`, and retargets the whole
command to the store owning the first remaining argument that resolves as a
bead. A positional id is found this way, which is how `gc bd show
<foreign-id>` reaches another rig at all.

A flag's value is its own argument, so the same walk reads it, and the store
moves on the shape of the value rather than the flag it belongs to. A value
that is itself id-shaped is taken as the id to resolve and moves the command
to that id's store; a value that is not, and the `--flag=value` spelling whose
whole token begins with `-`, are both passed over.

The two spellings fail in opposite directions, and each fails the way this
document is about — a silent empty result on exit 0, shaped exactly like a
real miss:

- A value flag carrying an id-shaped value in the **spaced** form reads from
  the wrong store. `gc bd list --assignee <session-id>` is the one that bites:
  a session id is a bead in the city's own store, so the query retargets there
  and reports no matches for a session that holds beads in its rig.
  `-a` and `-l` take a value the same way. `--assignee=<session-id>` stays in
  the rig and answers correctly.
- `--id`, whose job is to name a bead that may live elsewhere, reaches that
  store only in the **spaced** form. `gc bd list --id=<foreign-id>` is skipped
  by the walk, never leaves the local store, and answers empty; `gc bd list
  --id <foreign-id>` resolves the prefix and answers.

So there is no single safe habit. Give `--id` its value spaced, pass every
other value flag as `--flag=value`, and read a positional id as the
store-selecting argument it is. `--metadata-field key=value` is unaffected:
its `key=value` argument never parses as a bare id.

## Absence has to be earned

The failure is not the empty answer. It is a gate that reads one as
permission: no owning bead, so nothing is protected, so delete. A prune run
from inside a `tk-` rig that reads a `su-` bead's ambient-store miss as its
absence takes a whole live rig's worktrees for unowned.

So any gate whose next act is destructive — worktree prune or reclaim,
witness salvage, source disposal — resolves the owning store from the id
prefix BEFORE it concludes absence, and refuses when the prefix resolves to
nothing.

`assets/scripts/bead-store.sh` is that resolver, and the one place the
derivation lives. It maps a prefix to a rig through `gc rig list --json`, asks
that rig's store by path, and separates three answers a single exit code
cannot:

| | meaning | exit |
|---|---|---|
| yes | the store its prefix names answered, and the verdict holds | 0 |
| no | that store answered, and the opposite is true | 1 |
| unproven | no store could be asked, or it answered about a different or an ambiguous id | 3 |

`--absent` exits 0 only in the first column, so a gate written as

```bash
bead-store.sh --absent "$id" && rm -rf "$dir"
```

refuses an unknown prefix, a prefix two rigs carry, an unreadable rig list and
an unreadable store, because every one of them is a 3. `--present` is the same
guard at the opposite polarity rather than the negation of `--absent`: both
refuse an unproven store, which is what keeps "I could not tell" out of both
branches.

A reference that is not a full `<prefix>-<id>` is refused before any store is
asked: a string with no prefix dash, and a bare `<prefix>-` with no id after
the prefix. The bare marker is the subtle one. Its prefix resolves to a real
store, so probing it would read that store's not-found as this id's own
absence, the same way a foreign prefix's ambient miss does. It names a store
but no bead, so it earns no verdict.

Reading the payload is what makes that distinction available. A store that
cannot be opened exits 1 and prints nothing; a genuine miss exits 1 and prints
the error object above. The exit code is the same on both, so the verdict
comes from what was printed.

## An exact id, or no verdict

Even the store the prefix names answers a bare id as an exact-or-prefix match,
so its answer is a verdict only about the id actually asked for.

A hit proves presence only when it carries that exact id. `bd show tk-abc` when
no `tk-abc` exists but `tk-abcdef` does returns `tk-abcdef` on exit 0 — a real
bead, but a different one. Reading it as "tk-abc is present" is a claim about a
bead the store never confirmed, so a hit whose id is longer than the id asked
for is unproven.

A miss object is worse: it is byte-identical whether the id matched nothing or
matched several. `bd show tk-ab` when a dozen `tk-ab*` beads exist prints the
same `{"error":"no issues found matching the provided IDs"}` a true not-found
prints, on the same exit 1, and says "ambiguous issue ID … matches N issues"
only on stderr. So absence is the exact not-found alone: the store states it on
stderr, and ambiguity or any other lookup error is unproven, never absent. A
destructive gate that read an ambiguous reference as absence would delete on a
reference to a dozen live beads.

## Who asks it

- `escalation-rig.sh` binds `GC_RIG` for `escalate.sh`, so a visit lands in
  the store its subject lives in.
- `bead-rehome.sh` places both ends of a successor pointer, so
  `gc.superseded_by_store` names the store that actually holds the successor.
- `mol-witness-patrol`'s cleanup step holds `git worktree remove` behind
  `--present`: a worktree whose owner cannot be placed is not an unowned one.

A gate that concludes absence without going through it is reporting on
whichever store it happened to be standing in.
