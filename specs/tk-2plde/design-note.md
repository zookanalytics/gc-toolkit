---
name: Design note — a routed wait as a graph edge, and the disposition-due row
description: Why the parked board's wait became a `blocks` edge re-asked at render time rather than a stored state, what was deliberately left out, and the backfill census taken on 2026-08-22.
---

# A routed wait is an edge, not a sentence

Work record for `tk-2plde`. What is authoritative about the resulting
behaviour lives in `services/helm/README.md` ("Anchor kinds") and
`docs/gascity-human-engagement.md`; this note records the reasoning, the
rejected alternatives, and the part of the bead that was deliberately not
executed.

## The defect, restated

`gc.takeaway` is **one string, frozen when written**. A sitting that routes
work out of a subject stamps something like:

    routed — fix+guard ruled; tk-hgmob P1 slung via mol-polecat-work.
    Nothing further needed here.

and the subject goes on saying exactly that after tk-hgmob merges, because
nothing in the city re-reads prose. The board's parked predicate was a
non-empty test on that string, so `holding — awaiting X` and `nothing further
needed here` were mechanically the same row, both floored at LOW, forever.
tk-yps55 sat parked for 29 hours after its fix landed and cost a whole sitting
to discover it was finished.

The operator's framing: *"waiting, holding, those are graph states, not
comments."*

## What was built

Two halves, as the bead proposed, plus the parity work the scope warning
required.

**Write the edge.** `gc-helm takeaway <subject> "<text>" --waiting-on <bead>`
(repeatable) adds `subject depends-on <bead>` as a `blocks` edge in the same
call that stamps the takeaway. The converse prompt passes it at sign-off for
each bead a sitting slung.

**Derive, do not store.** Both boards re-ask, per render, whether those
blockers have closed:

| `waiting_on` | `waiting_on_open` | row |
|---|---|---|
| empty | — | unchanged — LOW, "conversation parked — takeaway recorded" |
| non-empty | non-empty | LOW, "parked · waiting on N" |
| non-empty | empty | ELEVATED, "parked · blocker landed", NEEDS = "blocker landed — dispose or resume" |

Landed in both implementations, per the bead's scope warning:
`assets/scripts/gc-helm.sh` and `services/helm` (`internal/source/beads.go`,
`internal/board/{model,derive}.go`), plus the two contract surfaces the Go
tests pin — `web/src/contract.ts` and the regenerated `web/src/board.fixture.json`.

## Decisions worth recording

**The `blocks` edge type, not a new one.** `bd dep add -t` also offers
`related`, `until`, `caused-by`, `supersedes` and others — the bead's note that
it offers "only depends-on/blocked-by" is inaccurate. `blocks` was chosen
anyway: it is the type whose semantics are already understood everywhere, and
an exotic type risks a silent no-op. Verified on live beads that adding a
`blocks` edge does **not** flip the subject to `status=blocked` (tk-1h9e9 is
`open` with an open blocker), so this does not manufacture the stuck state
tk-puh9d is about.

**Derived at render, so tk-puh9d is not a prerequisite.** Nothing is stored,
so nothing has to be cleared when a blocker lands, and the derivation never
consults stored `blocked` status. The two beads are independent.

**Blocker status is read OUTSIDE the gather cache.** The edge is structural and
rides the cached anchor set; whether it has been *discharged* is the fact this
whole change exists to re-ask, and a cached "still waiting" is precisely the
answer that must not be served. It is in the same class as session liveness,
which the board already holds outside the cache for the same reason.

**Fail-closed, in the quiet direction.** A blocker counts as landed only on a
positive `closed`. One that cannot be resolved — a store in another rig, an
`external:` reference, a read that timed out — counts as still open, so the row
keeps its pre-fix LOW band. A missed promotion costs a glance; a false
"everything landed" invites the operator to dispose of a subject whose work is
still in flight. Pinned by `(FAILCLOSE)` in the bash suite and
`TestUnresolvedBlockerStaysQuiet` in Go.

**Zero cost until the edges exist.** `resolve_waiting_status` reads the gathered
anchors first and returns before touching a rig when nothing carries an edge, so
a city whose sittings have not written any pays nothing. The Go side pays one
`GetDependenciesWithMetadata` per parked row.

**The web app had to move the row, not just band it.** The dashboard splits
`parked` into a quiet section below the ranked table whose sub-heading promises
nothing there is waiting on work. Leaving a disposition-due row in that section
would have re-hidden the exact row the distinction exists to surface, so
`disposition_due` lifts it into the attention table.

**The stamp is written before any edge, and a failed edge only warns.** A
sitting that could not wire its graph must still leave the conclusion it
reached; losing the takeaway would be the same data loss arriving by another
door. The order and the exit status are both pinned by tests, because a
reordering is invisible at runtime.

## Rejected

- **Widening the shared open-bead snapshot** to `open,in_progress,blocked,deferred`
  so "absent from the snapshot" would mean closed. Cheaper, but the snapshot has
  three consumers (visits, meta anchors, the in-flight join) and widening it
  changes what the board *shows*, not just what it can compute.
- **Inferring "landed" from absence in the open snapshot.** Same cost saving, but
  a blocker sitting at `blocked` or `deferred` would read as landed, and the Go
  board — which reads real statuses — would have disagreed. That is the drift the
  bead's scope warning names.
- **Gathering `waiting_on` for the `human` kind too.** Only `parked` spends it,
  and in Go each anchor costs a query. Both sides gather it for `parked` alone so
  the wire shapes stay identical.

## The backfill: a method, not a checklist

The code half above makes a routed wait an edge *going forward*. The parked
rows that already existed were left for **`tk-jj2ad`** (linked
`discovered-from` this one), which executed the safe part of it on
2026-08-23.

This section used to carry an 18-row census taken at one instant and read like
a checklist. It is not one, and presenting it as one caused real error: by the
time anyone worked it, the set had decayed **18 -> 8 -> 4 -> 2**, and two of
the rows an earlier note told a worker to *wire* had to be re-classified
because the work they named had since closed. **Re-derive the set. Never
replay a table.**

### The carve-out: ten of those rows are standing scopes, not conversations

`gc-helm.sh` kind `parked` is "any non-typed open bead carrying a
`gc.takeaway`", and it has no notion of `task_kind=triage-subject`. A standing
triage scope — a permanent bucket the detectors file visits *into* — therefore
renders forever as a concluded conversation, headlined by whatever its last
sitting happened to be about. `sl-6u5z` is the worked example: its 08-13
headline read "NOW SELF-DRIVING ... only a pool cycle remains", true for about
seven hours and false for the eight days after.

**Closing one does not dispose of it.** Two code paths say so:

- `assets/scripts/detect-stalled-workflows.sh:378-396` (`resolve_subject`)
  looks the scope up in LIVE (`bd list --status=open,in_progress`) and
  **creates a new one** when it finds none. Closing a stalled-workflows scope
  mints a replacement under a fresh id on the next patrol pass and orphans the
  old bead's visit history — verified on `sl-6u5z`, which holds 6 visits and
  two full diagnoses in its notes.
- `assets/scripts/liveness-sweep-precheck.sh:42-46` states it outright for the
  unnamed-waits scopes: the standing subject is "a permanent open, unassigned,
  unblocked bead in every rig, so without this the survivor set could never be
  empty and the whole precheck would be dead code." That path is read-only, so
  a close there does not respawn — it breaks the precheck instead.

Identify them by metadata, not by reading the headline:
`task_kind=triage-subject`, carrying a `triage.scope` value.

### The re-derive rule

Re-run `gc-helm.sh board --json --limit=0 --refresh`, take `kind == "parked"`,
and exclude in this order. What survives is the work set.

1. `metadata.task_kind == "triage-subject"` -> standing scope. Never dispose.
2. An open or `in_progress` visit naming it
   (`gc.continuation_group == <bead>`) -> a sitting holds it. Leave it alone.
3. An existing dependency edge to something still open -> already wired.
4. The takeaway self-describes as awaiting an operator ruling -> not yours.

Only category (1) of the three dispositions below is safe unsupervised.

### The three dispositions

1. **Still waiting on work genuinely in flight** -> wire the edge:
   `gc-helm takeaway <subject> "<unchanged text>" --waiting-on <work-bead>`.
   The board then promotes the row by itself when the work lands. Safe for an
   agent **only where the takeaway names the routed bead unambiguously.**
2. **Finished** -> operator ruling, then `bead-rehome.sh --origin <bead>
   --successor <bead> --kind re-homed|folded|fixed-upstream|duplicate`. The
   successor pointer is the whole point; a bare close is what
   `bead-rehome.sh`'s own header exists to prevent.
3. **Neither — the topic simply ended** -> ruling, then close with a reason.

### Re-derivation of 2026-08-23 ~01:45Z

63 rows, **25 parked** (up from 18). Applying the rules: 10 standing scopes
excluded by (1) — `sl-djvs`, `su-vehr`, `sl-6u5z`, `su-6013`, `su-zia4`,
`tk-n3we6`, `tk-hok6w`, `gc-b0pmq`, `su-7sjl`, `su-g48h`, each confirmed by its
own `task_kind`, not by the earlier note's say-so. `tk-82epi` excluded by (2),
held by live visit `tk-nd84o` on converse-1. `tk-gnrhr`, `tk-66rwg`,
`tk-fhlv4`, `tk-16f29` excluded by (3), already wired to open work.
`tk-6v7nm`, `tk-mxrq9`, `tk-mw9qz` excluded by (4). `tk-z9nln` also excluded:
its takeaway records that the wait *cannot* be an edge on its shape (a parent
cannot be blocked by its own child) and that the return trip is hand-executed
until `tk-2cyxo` ships a child-aware predicate.

**Executed:**

| bead | action | detail |
|---|---|---|
| `tk-x2tw7` | WIRED | `--waiting-on sl-kg9z6` (open, 44 beads). Takeaway text unchanged. |
| `tk-gy1ws` | DISPOSED | `bead-rehome.sh --kind folded --successor tk-x2tw7`; self-declared superseded, "No decision pending in this thread." |

**Left for a ruling** — each needs a decision this bead could not supply:

| bead | why it is not an agent's call |
|---|---|
| `tk-zmrui` | Says it "stays open to be subsumed", but both beads it named (`tk-cwsj1`, `tk-tbkkf`) have since **closed**. The subsuming work landed, so the remedy moved from *wire* to *dispose* — and disposal needs a ruling. An earlier note listed this as a wiring target; that was true when written. |
| `tk-3a176` | Its edge to `tk-9tbbk.1` is now discharged (that bead closed) and the takeaway says "No design work left on this subject" — terminal, so disposal, so a ruling. |
| `tk-fs2n4` | Names a real fix ("count only contendable sessions") but no successor bead exists to wire to. Needs a bead filed or a ruling. |
| `tk-u28iw` | Same shape: a recommendation ("publish check.codex as a commit status") with nothing filed. |

### Trap: a cross-store edge is invisible to `bd show`

`tk-x2tw7` is in the gc-toolkit store and `sl-kg9z6` in signal-loom. The edge
wrote fine, but afterwards `gc bd show tk-x2tw7 --json` reports
`dependencies: null` — while `bd list --id tk-x2tw7 --json` shows the row, and
the board reads it correctly. Verify a cross-store wire with `bd list`, not
`bd show`, or you will conclude a successful write failed and wire it twice.

## Verification

- `assets/scripts/gc-helm.test.sh` — 121 passed, 0 failed. New cases: `(DISPO)`,
  `(LIVEHOLD)`, `(BAREPARK)`, `(FAILCLOSE)` for the render; `(EDGE)`,
  `(EDGEMANY)`, `(EDGESTAMP)`, `(EDGESELF)`, `(EDGEFAIL)`, `(EDGENONE)` for the
  writer.
- `assets/scripts/converse-signoff.test.sh` — 90 passed, 0 failed, including the
  stamp-before-edge ordering and the no-abort-on-failed-edge guards.
- `services/helm`: `go test ./... -count=1` all green, including the
  CLI↔bash `--json` key-set parity test and the TypeScript wire fixture.
- `services/helm/web`: `npm test` 120 passed, `tsc --noEmit` clean.
- Every new guard was mutation-tested: the ELEVATED promotion, the
  `!= "closed"` fail-closed test, `resolve_waiting_status` running at all, the
  NEEDS override, the stamp/edge order, and the edge-failure exit status each
  fail their assertions when removed.
- Live smoke test against the loomington city, read-only: renders, and the one
  pre-existing edge row derives correctly.
