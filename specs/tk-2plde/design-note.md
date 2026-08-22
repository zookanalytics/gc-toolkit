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

## NOT DONE: the backfill

The bead's `## Backfill` section is **not** executed here, deliberately.

Disposing of a parked subject is an operator ruling. This repo's own converse
contract says so in as many words — *"You do not close subjects on your own
judgment"* — and the correct instrument (`bead-rehome.sh --origin … --successor
…`) needs a successor pointer that only the ruling can supply. Writing the
missing edges is not mechanical either: a takeaway names bead ids for several
reasons, and `tk-gy1ws` names `tk-x2tw7` as its *successor*, not as something it
waits on. A wrong `blocks` edge on a live subject is worse than no edge, because
`bd` then refuses to close it.

So the census is recorded here and filed as its own bead — **`tk-jj2ad`**,
linked `discovered-from` this one — rather than acted on.

Census taken 2026-08-22 ~06:33Z from `gc-helm.sh board --json --limit=0 --refresh`
against the live city — 58 rows, 18 parked, of which exactly **one**
(`tk-gnrhr`) already carried a `blocks` edge, and it renders correctly as
`parked · waiting on 1` with its blocker still open.

| bead | rig | age | takeaway (first 96 chars) |
|---|---|---|---|
| `tk-zmrui` | gc-toolkit | 8d | dispatched holistically — no content discriminator adopted; census showed only 1 of 3 terminal b |
| `tk-gnrhr` | gc-toolkit | 0d | split — membership half PARKED on design bead tk-j5wrs (blocks edge, load-bearing); mechanical g |
| `tk-3a176` | gc-toolkit | 0d | holding — the parked-band fix did NOT self-resolve; decide: enforce ≤140 at write, clamp at rend |
| `sl-6u5z` | signal-loom | 8d | disposed — sl-jnjd complete-and-closed (operator-approved 2026-08-13). It was a COMPLETION HUSK, |
| `su-vehr` | shutupandlisten | 8d | resolved — su-vc8n needed no operator decision: it closed itself 2026-08-13T19:59:37Z with gc.ou |
| `tk-mxrq9` | gc-toolkit | 0d | verified, unruled — real + reachable (signal-loom requires 3 checks; comment at :1808 denying th |
| `tk-z9nln` | gc-toolkit | 0d | dispatched — audit-as-diff ruled; tk-z9nln.1 slung (workflow tk-z1ror) to produce the divergence |
| `tk-x2tw7` | gc-toolkit | 0d | routed — website-eval breakdown built as sl-kg9z6 (44 beads, 5 tracks); 6 dispatched, naming + i |
| `tk-gy1ws` | gc-toolkit | 0d | superseded — the question is answered and owned elsewhere. The operator filed tk-x2tw7 at 06:47Z |
| `su-6013` | shutupandlisten | 8d | TABLED — su-uzy9 STAYS PARKED (standing home open-through-MVP; MVP not reached: Mac xcodebuild b |
| `su-zia4` | shutupandlisten | 4d | executed (operator CONFIRM, 2026-08-17) — su-5dee + su-ykcs STILL TABLED, unchanged, both mechan |
| `tk-n3we6` | gc-toolkit | 2d | cleared — 17 husk workflow roots closed with successor pointers (tk-lxthp + 16 siblings), verifi |
| `tk-hok6w` | gc-toolkit | 0d | folded-1-routed-2-gated-2 — helm outage over (hand-recovered, tk-5nm0p folded into in-flight tk- |
| `sl-djvs` | signal-loom | 0d | routed — sitting 11: operator ruled 'route the six'; all 6 slung to mol-polecat-work, verified a |
| `gc-b0pmq` | gascity | 0d | holding (visit gc-qcvca, resumed 2026-08-22 by converse-2 -- this sitting has now been REAPED TW |
| `su-7sjl` | shutupandlisten | 0d | settled — sitting 9 routed the single candidate su-g1n9s (workflow su-jtqo1, mol-polecat-work) a |
| `tk-mw9qz` | gc-toolkit | 8d | SPLIT + HELD (operator, 2026-08-13). Funded half is tk-rbf9r: make the terminal attach target DY |
| `su-g48h` | shutupandlisten | 8d | dispatched — appetite GRANTED for the automation route, not more manual gating. Item 3 RETIRED:  |

Read by their own takeaway text, roughly eleven of the eighteen are
self-declared terminal ("disposed", "resolved", "superseded", "cleared",
"settled", "executed", "dispatched", "routed", "nothing further needed") — on a
budget of 15 reserved rows, which is the cost the bead quantifies.

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
