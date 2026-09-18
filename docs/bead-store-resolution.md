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

## Reading a bead's whole context

`assets/scripts/bead-context.sh <id>` answers "what is this bead, and is it
actionable?" in one call, so an agent stops re-running the show/jq/cross-store
dance to tell whether a blocked bead's blockers have landed. It prints the
bead's status, title, type, assignee and routing; the metadata that decides an
anchor's fate (branch, target, PR, merge_result, gate lanes, successor); every
dependency with its own status, read from the store that dependency lives in
through the prefix binding above; the store the bead itself lives in; and a
verdict on whether an open `blocks`-blocker, or one whose store cannot be
placed, holds it. `--store rig:<name>` and `--db <path>/.beads` pin the owning
store when a prefix is ambiguous or names the city's own store. It reads only,
and it runs on demand (a triage read, an unblock check, a hand-off) rather than
driving the dispatch loop; the loop's readiness question is `bd`'s own.

### What it returns, and what it leaves out

The fields it prints are the ones that decide a bead's fate. It leaves out the
free-text body, notes, description and comments, on purpose: that text is
unbounded, and returning it proactively is the cost this tool exists to avoid.
So it complements `gc bd show <id>`, which the reader still runs for the one
bead whose full body a decision turns on, and does not replace it.

### Dependencies, and what they cost

Every dependency is returned, closed ones included, because the actionable
verdict is computed over them: a closed `blocks`-dep is the evidence a blocker
has landed, so dropping closed edges would leave "all blockers cleared"
unprovable. Only `blocks`-edges gate the verdict; `related`, `tracks` and
`parent-child` edges are shown as context and never hold a bead.

`.dependencies` is a bead's own outbound edges, not its descendants. A
`parent-child` edge is stored on the child pointing up to its parent, so an
epic carries no edge per story: running this on an epic shows the epic's own
few edges, not its subtree. Dependency lists run to a handful of edges in
practice.

The cost is one `gc bd show` for the subject plus one more for each dependency
whose status the subject's store could not embed, which is each cross-store
dependency. Same-store dependencies carry their status inline and cost nothing
extra, and the subject read passes `--brief-deps`, so a dependency's body is
never fetched just to read its status. A bead with many same-store
dependencies is still a single read.

### What it looks like

```
$ bead-context.sh tk-4p2c1a
bead-context: tk-4p2c1a

  Status      open
  Title       Wire the demand gate into the board renderer
  Type        task
  Assignee    (unassigned)
  Store       gc-toolkit

  Metadata
    branch        polecat/tk-4p2c1a
    target        main
    merge_result  (unanchored)
    check_set     (default)

  Dependencies (2)
    STATUS       TYPE          STORE        ID
    closed       blocks        gc-toolkit   tk-9aa1b2
    open         blocks        gc-toolkit   tk-77c3d4

  Actionable  NO — open blocks-blocker(s): tk-77c3d4
```

`--json` returns the same context as one object, keyed the same way, for a
machine to read.
