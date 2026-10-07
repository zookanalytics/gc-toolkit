---
name: gc bd unclaim/update mis-route when --if-assignee names a live session
description: Why a spaced session-id guard value retargets gc bd to the city store and reports "no issue found matching <bead>", why the fix is in gascity (gc-rwa68), and the pack-side backstop shipped for orphan-dispose.sh.
---

# gc bd unclaim/update mis-route when --if-assignee names a live session

tk-hjxuck reported that `gc bd unclaim <bead> --if-assignee <value>` and
`gc bd update <bead> --if-assignee <value>` fail to resolve their target bead
whenever `<value>` resolves to a live session, reporting
`Error resolving <bead>: no issue found matching "<bead>"` for a bead every
other verb reads. A non-session value, or the same command with no `--if-assignee`
guard, works; bare `bd -C <rig>` is unaffected. The report asked for two fixes:
route the guarded verbs the way the unguarded ones route, and stop reporting a
routing failure as a missing bead.

## Root cause — the gc wrapper, not bd

The fault is in the `gc` binary, whose source is the gascity rig
(`github.com/gastownhall/gascity`), not in gc-toolkit and not in the `bd`
binary.

`resolveBdScopeTarget` (`cmd/gc/cmd_bd.go`) picks the store a `gc bd` command
targets by walking every argv element that does not begin with `-` and
retargeting the whole command to the store owning that element's bead-id
prefix. A flag's value is its own argv element, so a *space-separated*
`--if-assignee lx-yevik` exposes `lx-yevik` to the scan while the attached
`--if-assignee=lx-yevik` hides it behind the leading `-`.

The loop guards itself with `bdBeadExists` (a bare `store.Get`), intending to
reject non-id flag values. It cannot, because a live session identity *is* a
real bead: sessions are `issue_type: session` beads in the city store, one per
live session, with the id `gc hook --claim` stamps as a bead's assignee. So the
guard resolves the session, the command retargets to the city store, and `bd`
runs there and cannot find the rig bead — hence "no issue found matching
<bead>". A value that resolves to no session fails the guard, the command stays
in the rig store, and `bd` reports the true CAS result (`assignee mismatch`).

The two asks collapse into one fix: once the scanner no longer sniffs flag
values, `bd` runs in the right store, finds the bead, and reports the real CAS
outcome, so the misleading "no issue found matching" disappears on its own.

For `unclaim` there is a second contributor. `unclaim` is absent from the
`internal/bdflags` subcommand manifest, so `bdArgsNameClassOwnedBead`
(`cmd/gc/cmd_bd_by_id.go`) falls into its "undecidable — judge every token"
branch and also inspects the `--if-assignee` value; this path matters for a
class-reserved (`gcs-`) session id, while the `lx-`-shaped ids seen in practice
misroute through `resolveBdScopeTarget` above.

### Reproduction (loomington, gascity HEAD cf63b7da1, 2026-09-15)

Non-mutating: the CAS guard writes nothing on a mismatch, so tk-hjxuck
(assignee empty) is untouched by either probe.

    $ gc bd unclaim tk-hjxuck --if-assignee lx-4e3nan     # spaced, live session
    Error resolving tk-hjxuck: no issue found matching "tk-hjxuck"

    $ gc bd unclaim tk-hjxuck --if-assignee=lx-4e3nan     # attached, same value
    Error unclaiming tk-hjxuck: assignee mismatch: tk-hjxuck is held by "", expected "lx-4e3nan"

`lx-4e3nan` resolves as `type=session` in the city store, which is what lets it
pass `bdBeadExists`.

## Where the fix lives: gascity gc-rwa68

The durable fix is a gascity binary change, which a gc-toolkit polecat cannot
push. gascity already carries **gc-rwa68** (open), which reports the identical
root cause for the read verb (`gc bd list -a <session-id>` returns zero rows
from the city store for a session that holds beads). gc-rwa68 records the
mechanism, the `=` mitigation, and three candidate fixes: parse argv and skip
known value-flag values before the prefix scan; reject a scope candidate whose
`issue_type` is `session`; and carry the resolved scope in the `--json`
payload.

tk-hjxuck is the write-side sibling of gc-rwa68: same scanner, same guard, same
mitigation, additionally covering `unclaim`/`update --if-assignee` and the
misnamed error. Rather than file a duplicate, the write-side symptom and the
error-message observation were added to gc-rwa68, and tk-hjxuck carries
`gc.filed_as=gc-rwa68`. A fix in gc-rwa68 closes both.

## Pack-side backstop shipped here

One gc-toolkit caller used the mis-scoping spaced form:
`orphan-dispose.sh` `release_assignee` guarded its assignee clear with
`gc bd update "$BEAD" --assignee "" --if-assignee "$GUARD"`, where `$GUARD` is
the orphaned session's assignee. Whenever that assignee is a session-id-shaped
value, the guarded release mis-scoped and failed, always falling through to the
more-privileged forced bare-`bd` retry instead of the sanctioned non-force CAS.

The fix attaches the value (`--if-assignee="$GUARD"`), which routes correctly
regardless of the wrapper bug and is harmless for a non-id guard. The bare-`bd`
fallback stays space-separated: `bd` parses flags directly and does no
argv-scanning store inference.

`orphan-dispose.test.sh` asserts the emitted guard is the attached form and not
the spaced form, so a regression to the mis-scoping spelling fails the suite.

The other guarded-release call sites are unaffected: `gc-helm.sh` guards on an
empty assignee (`--if-assignee ""`) or on a session *name* (`--assignee
"$sname"`), and session names carry no bead-id prefix, so the scanner never
treats them as scope candidates.

## Mitigation for any caller

Until gc-rwa68 lands, pass an id-shaped value-flag argument attached
(`--if-assignee=<v>`, `--assignee=<v>`, `-l=<v>`), or use bare `bd -C <rig>`,
which is not subject to the wrapper's scan. The one exception is `--id <v>`,
whose spaced form is the spelling that resolves a foreign prefix across stores.
