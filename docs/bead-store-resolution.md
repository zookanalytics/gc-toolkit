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

Every bead id begins with a prefix its store owns: `tk-` for gc-toolkit, and
another rig's prefix or the city store's for each of theirs. The prefix is the
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
name the city's own store at all: `gc --rig <hq-rig> bd list` exits 1 with
`rig not found` where `gc bd --db <city>/.beads list` answers. `GC_RIG` set to
the city's rig name does no better. `gc bd` warns that it names no bound rig,
ignores it, and answers from the caller's working directory, so a caller in a
rig checkout reads and writes that rig's store. Only a `--db` path reaches
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
from inside a `tk-` rig that reads the ambient-store miss on another rig's
bead as its absence takes a whole live rig's worktrees for unowned.

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

- `converse-signoff.sh` runs a ruling's rework or retirement in the rig that
  holds the PR's anchor, which can be another rig than the conversation's, so
  it resolves that rig and its checkout from the anchor's id and writes nothing
  when either cannot be resolved.
- `bead-rehome.sh` places both ends of a disposition, so the edge it writes
  in the origin's store names a successor that the store its prefix names
  actually holds.
- `mol-witness-patrol`'s cleanup step holds `git worktree remove` behind
  `--present`: a worktree whose owner cannot be placed is not an unowned one.

A gate that concludes absence without going through it is reporting on
whichever store it happened to be standing in.

## Reading the rig map

Every derivation above starts from the rig map: each rig's name, path, prefix
and suspension, and a row for the city itself. The pack reads it through one
helper, `assets/scripts/rig-map.sh`, so the reasons a listing fails and the
time it may take are decided in one place. The helper runs `gc rig list --json`
and prints the listing. When the listing does not read, it prints nothing on
stdout, names the reason on stderr and exits 3. A caller then reports that the
map did not read, and why, rather than reading the failure as a city with no
rigs or a prefix no rig carries. The helper writes to stderr only then, so a
caller may capture both streams in one.

The helper puts one bound on the call, `GC_RIG_LIST_TIMEOUT`, 120 seconds by
default. The bound exists to cut off a `gc` that never answers, so it sits far
above what the listing takes on a loaded host, and no caller tunes it as a
latency budget. A caller under a deadline it does not set bounds the call by the
time it has left, as it bounds any other call. A doctor check does so within
`gc doctor`'s per-check timeout, and a board verb within the board's deadline
for the verb.

`gc rig list --json` is slow on a loaded host because of the `running` flag on
each rig row. Gas City's `doRigList` fills it with `rigHasRunningAgent`. For
each unlimited pool agent the rig configures, until it finds one running, that
asks `discoverPoolInstances` for the pool's instances, and each such call lists
the city's running sessions again. With tmux sessions every list starts its own
`tmux list-sessions`, so one listing starts a few dozen processes, and on a
loaded host each of them waits to be scheduled. The text listing computes no
`running` and starts two. No pack caller reads a rig row's `running`. The flag
on the city's own row is the controller probe that `city-liveness.sh` reads.

No cheaper source carries the whole map:

- `gc rig list` without `--json` prints a table for people, not a contract.
- `gc config show --json` carries each configured rig's name, path and prefix.
  Its suspension is only what `city.toml` says, so a rig suspended with
  `gc rig suspend` reads as not suspended, and the city's own row is not among
  its rigs.
- `gc status --json` carries no prefixes.
- `.beads/routes.jsonl` maps each prefix to a relative path, with no names and
  no suspension.

gctk's store adapter needs no rig map. To find a bead's store by its id's
prefix and a rig's store by its name (`gcbd.Client.StoreOf`,
`gcbd.Client.RigStore`), it needs each store's name, prefix and folder, and it
reads them from `gc config show --json`, which Gas City prints from the city's
config files, so the read waits on no supervisor, bead store or tmux. The
city's own store is the folder that read names as `city_path`, under the name
and prefix the city's `.gc/site.toml` binds, where it binds them, and
otherwise the ones the config's `[workspace]` sets, as Gas City takes them. A
rig folder the config gives as a relative path is under the city's folder, as
Gas City reads it. A prefix the config leaves unset is the one Gas City
derives from the name.

## Reading a bead's whole context

`assets/scripts/bead-context.sh <id>` rebuilds a subject's working context in
one call, so an agent orienting on a bead — the converse opening claims, folds,
then primes a subject before any work — stops re-running the show/jq/cross-store
dance by hand. It returns, and nothing outside this:

- **Subject core** — status, priority, type, task_kind, assignee; the live and
  provenance routes; the anchor state (merge_result, pr_number, branch,
  merged_target) when the bead carries a merge_result; the first_reaction fields;
  gc.origin; and the distilled gc.takeaway headline with its settled flag.
- **Context edges**, shown but never gating — the parent, the relates-to edges,
  the beads that track it, its conversations among them, the beads that wait
  on it by a `blocks` or an `until` edge, and a count per class.
- **Store** — the store that answered, and the db it read.

and, each behind an opt-in flag so a caller pays only for what it needs:

- **`--frontier`** — what holds it. A verdict over `ready | advancing | stuck`:
  ready when nothing holds it, else advancing when every wait behind what holds
  it advances, and stuck when one does not. Each wait is named
  `{id, title, status, advance}`, plus `stuck_on {id, why}` when it is stuck,
  `ancestor` when it is an ancestor's wait, and `unjudged` when it is a
  `waits-for` wait the store cannot judge yet. `holds` names what holds it in
  one word, an edge into another store, which holds nothing, is listed under
  `foreign`, and its own closed blockers are a count.
- **`--horizon`** — the direct children. The epic-health snapshot
  `{total, open, closed, advancing, stuck}`, with open children named the same
  way and done children counted only, so a hundred-story epic stays bounded.

`advance` answers whether the city carries a bead to its end without a person,
by the rule the helm board reads
([the `bead stands` contract](gctk-architecture.md#the-bead-stands-contract)),
and `gctk bead stands` answers it for the subject and each bead the sections
name. A bead advances when the city takes it as things stand, queued in the
board's words, and every bead it waits on advances, and an epic or a Delivery
advances while every open member does. Anything else is `stuck`, and `stuck_on`
names the bead that stops it, with the word that says why: the ask, when that
bead is itself what a person owes, and otherwise the rule that names it.
`services/gctk/standing` declares each of these words with its meaning: the
asks and the rules in `rules.go`, and the verdicts `ready`, `advancing` and
`stuck` in `advance.go`.

| `why` | The bead that stops it |
|---|---|
| `question` | is an open human gate, or an open decision that does not wait on work of its own first |
| `conversation` | is an open conversation its sitting does not stay in, which answers no open human gate and tracks no decision that asks |
| `pull-request` | carries a pull request that waits on the operator's review, or needs the operator's attention for a reason of its own. One that needs it only for a question or another ask that holds it is stuck on the gate or the bead a person owes instead, by `own-wait` or `further-along` |
| `assigned-to-you` | is any other open bead only a person clears, such as a task in the operator's queue |
| `ruling` | is an epic with members and none of them open, or a landed Delivery |
| `own-wait` | is a human gate, or a bead only a person clears, that the stuck bead waits on through a wait of its own |
| `further-along` | is such a gate or bead further along its waits, an ancestor's included |
| `parked` | is a gate that is no human gate, which holds the stuck bead, its own or an ancestor's |
| `status` | has a status no pool offers, such as deferred, pinned or a status its store adds |
| `answers` | is the question a conversation answers, which the question's own reading carries |
| `members` | is an epic or a Delivery with no members at all |
| `gate` | is a gate that is no human gate |
| `not-scheduled` | is ready work that nothing sends anywhere: the store serves it as ready, no dispatch hold holds it, and no arm, route, assignee or live run moves it |
| `outside` | is work that waits outside the city: `hold:external` holds it and no live run works it |
| `for-product-owner` | is work nothing sends that is held for the Product Owner's placement, `hold:po` or its earlier spelling `hold:mayor` |
| `not-ready` | is any other work nothing sends, which the store does not serve as ready |
| `unread` | could not be read, has no standing of its own and no bead that speaks for it, waits on itself through the beads it waits on, or is a `waits-for` wait the store cannot judge yet |

So a queued bead is stuck on what stops the first of its waits that does not
advance, and an epic or a Delivery on what stops the first of its open members:
a routed bead behind work nobody routes is stuck on that work, and a bead
behind a human gate further along is stuck on the gate. A decision a ruling
left waiting on the work it sent, and a conversation its sitting stays in,
advance while that work does. A wait on a bead with no standing of its own,
such as a merge anchor's rework or the root of a run, reads as the bead that
speaks for it: the anchor the rework names, or the bead the run works. Where
that is the waiting bead itself, the wait is its own work and stops nothing, so
a pull request whose review run or rework is under way is not stuck on it.

A pour leaves the bead its run works open, unassigned and unrouted, so its row
alone cannot say a run holds it. The answer reads that bead in flight from the
run's start, by the runs of the subject's store. Whether a claim's, a route's
or a run's session is still up is out of reach of these reads: one whose
session has died still reads advancing, and `doctor/check-root-advancing`
reports a stranded root.

The converse opening opts into both, so its subject slice, the readiness verdict
and the epic-health snapshot arrive from one call. A caller that only needs
claimability opts into `--frontier` alone. `--store rig:<name>` and `--db
<path>/.beads` pin the owning store when a prefix is ambiguous or names the
city's own store, which no `--rig` value reaches. `--json` emits the whole
context as one object; the default is a human-readable block. It reads only.

### What it returns, and what it leaves out

The free-text body — descriptions, notes and comments, of the subject or of any
listed bead — is never returned. No blocker or child is carried beyond
`{id, title, status, advance}` and, when it is stuck, the `stuck_on {id, why}`
that names its cause, and no bead that waits on the subject beyond
`{id, title, status, edge}`. That text is unbounded, and returning it
proactively is the context bloat this tool exists to cut. So it complements `gc
bd show <id>`, which the reader still runs for the one bead whose full body a
decision turns on, and does not replace it.

### The edges, the frontier, and what they cost

A bead's own read carries its outbound edges — the parent link, the relates-to
edges (either the `relates-to` or the older `related` spelling), and the
`blocks`-deps. The beads that track it are an inbound `tracks` edge and the direct
children an inbound `parent-child` edge, each stored on the other bead, so each
is read with one reverse query the subject's own row cannot answer.

Each bead that waits on the subject carries a `blocks` or an `until` edge to
it, another inbound edge. That is how a closed design's read names the build it
released. The subject's read asks bd for its dependents too
(`--include-dependents`), and bd returns each one cut to its identity fields and
the edge's type, never its body. The dependents also hold every child and every
inbound `related` edge, the review, validation and rework beads that gather on a
design, so the list keeps only the `blocks` and `until` ones. It names the open
ones first, each with its edge, and at most ten of them. Its counts give how
many wait in all and how many of those are open, since a gate can hold a hundred
parked beads. bd reads only the subject's store, so a bead in another store that
waits on the subject is not listed.

The counts are over a bead's own edges and its direct children, never its whole
subtree. A `parent-child` edge is stored on the child pointing up, so an epic
carries no edge per story; `--horizon` lists the direct children by the
`--parent` query, asked for with `--all`. bd's default scope leaves out closed
and pinned children, and a `--status` list leaves out any status it does not
name, so with `--all` a child in any status is counted, a done one included.
The listing also returns the closed event bead `bd set-state` files under a
bead each time its state changes. An event records the change, not work, so it
is not counted as a child.

The subject read passes `--brief-deps`, so a listed bead's body is never fetched
to read its status, and a same-store closed blocker's status rides the edge at no
extra cost — the common bulk on an epic. What holds the subject and where the
named beads stand are one `gctk` call each, pinned to the subject's store:
`gctk bead holds` reads the subject's waits, and `gctk bead stands` lists the
store once and reads beyond that list only what the beads it answers need, such
as the closed members of an epic none of whose members is open. A read that does
not answer fails the verdict closed, and a bead with no answer reads stuck on
itself, `unread`.

A `blocks` edge into another store holds nothing for bd: the bead stays in `bd
ready`, and a deferred dispatch does not wait on it (`docs/component-model.md`,
I1). The frontier lists it under `foreign` and judges nothing in the other
store. A reader who finds one should mirror the wait into the waiting bead's
own store, where it holds.
