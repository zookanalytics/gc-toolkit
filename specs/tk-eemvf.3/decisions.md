---
name: U8 drill-in plane — decisions and rejected alternatives
description: Why the drill plane talks to the supervisor same-origin rather than to 127.0.0.1:8372, why its types are generated from a pruned copy of the supervisor's OpenAPI spec, why every list read carries its partial-data envelope, and why the SSE reconnect supplies its own after_seq cursor. Read before changing how the web app reaches the supervisor (U6/U9/U10).
---

# U8 drill-in plane — decisions

Work record for `tk-eemvf.3` (U8 of the Attention Canvas plan,
`specs/tk-eemvf/2026-06-30-001-feat-attention-canvas-plan.md`). What is true
*now* — the module layout, how to regenerate the types — is in the code and in
`services/helm/web/scripts/gen-supervisor-types.mjs`. This file records what was
decided against, for whoever lands U9's terminal embed and U10's deploy.

The leg is the "dive in and read the latest" half of the epic's claim: from a
tile, open live bead / session / activity detail. The live terminal is U9. Like
U5 this is structure, not visual design — the direction gates U6.

## 1. The plane addresses the supervisor SAME-ORIGIN, not `127.0.0.1:8372`

**Decision.** Every request resolves against the document's own origin. The only
thing discovered at runtime is the city name, parsed out of the mount path
(`/v0/city/<city>/svc/helm/`) by `src/drill/origin.ts`.

**The bead and the plan both say otherwise** — "against the supervisor at
127.0.0.1:8372", "cross-origin is fine here; the stock dashboard already does
exactly this" (plan U8, *Approach*). That is correct *for the stock dashboard*
and wrong for this app, for two independent reasons:

1. **The tailscale origin.** The stock `gc dashboard` is served by its own server
   on `:8080`, so it must reach across to `:8372`. helm-svc is reverse-proxied
   *by* the supervisor, so the SPA and the typed API are already the same origin.
   And the board is read from a phone or a laptop that is not the city host,
   where `127.0.0.1` is *the reader's own machine* — the supervisor is
   unreachable at that address by construction. The bead's own third test
   scenario ("reachable through the tailscale origin") is the one a hardcoded
   loopback address fails.
2. **The app's own CSP.** U5 ships `connect-src 'self'` (`web/handler.go`,
   `buildCSP`). A `fetch` or `EventSource` to any other origin is refused by the
   browser before it leaves the page. Verified live on the running service:
   `connect-src 'self'` is present on the served shell.

So the cross-origin design does not merely have a caveat — it does not run.
Same-origin needs no CORS, no CSP exception, no port, and inherits whatever
origin the operator actually opened.

**Rejected: inject the supervisor base URL via a `<base href>` or a meta tag**
(the mechanism KTD5 floats for asset paths). Unnecessary here — the mount path
already carries the city, and the client can read it even though the server
cannot (the proxy strips the prefix before helm-svc sees the request; see U5
decision 2). One less injected value to keep in sync.

**Consequence for U9/U10.** ttyd is a *separate* tailscale-serve mapping on a
different origin, so the terminal embed will hit `connect-src 'self'` head-on.
It needs either a CSP entry for the ttyd origin or a proxied path under this
one. Decide it there; do not widen the policy speculatively.

## 2. Types are generated from a PRUNED copy of the supervisor's OpenAPI spec

**Decision.** `scripts/gen-supervisor-types.mjs` reads the supervisor's spec,
keeps the eight operations this plane calls plus the transitive `$ref` closure,
and runs `openapi-typescript` over that subset. The single generated artifact,
`src/drill/gen/supervisor.d.ts`, is committed.

**Why not generate from the whole spec.** The supervisor describes ~200
operations; the full generation is ~23k lines / ~865KB of `.d.ts`. That is a
large committed artifact in a *different repository* from the one that owns the
spec, for eight endpoints. Pruning first gives 3.1k lines and keeps the
dependency surface legible.

**Why not hand-write the types.** The bead is explicit — "do not invent a
client" — and it is right: the board contract needs a hand-written mirror only
because the `/svc/` surface is absent from the spec (that is U7's job). This
plane's endpoints *are* in the spec, so hand-writing them would create a second
contract to drift. The generated union even types SSE payloads per event type,
which the stock dashboard had to approximate with a loose hand-written envelope.

**Why the pruned spec itself is not committed.** Nothing reads it; the
`OPERATIONS` list in the generator documents the dependency surface far better
than 8k lines of JSON, and `--spec <file>` still regenerates offline from any
copy of the upstream spec. Committing a derived intermediate that nothing
consumes is cost without a reader.

**Drift detection.** `node scripts/gen-supervisor-types.mjs --check` regenerates
into a temp file and fails if the bytes differ from the committed copy. Two
things additionally keep the subset honest without ceremony: `tsc` rejects any
call to a path missing from the generated `paths`, so the type surface cannot
silently fall behind the code; and the generator throws rather than emitting a
partial spec if an operation it lists has disappeared upstream.

**Cross-repo caveat, stated plainly.** The spec is owned by the gascity rig
(`internal/api/openapi.json`, generated there from the Huma handlers). This
repo vendors types derived from it, so a supervisor API change lands here only
when someone re-runs the generator. `--check` is what makes that visible.

## 3. One event stream, ref-counted, not one per consumer

**Decision.** `createEventHub` multiplexes a single `EventSource` to every
subscriber; the first subscriber connects and the last one to leave disconnects.
The drill panel and the city-signals strip come and go independently, and
without the hub each would hold its own connection and its own copy of the
whole city firehose. An idle board now holds no connection at all.

## 4. Live state is applied two different ways, deliberately

**Decision.** The activity feed applies each matching event *directly* — the
event is the data, so refetching to learn what it already said would be silly.
Bead and session state is *refetched*, on a trailing 1.5s throttle, because an
event says "this changed", not what it changed to, and a busy anchor emits
bursts. Same reasoning as the stock dashboard's `useGcEventRefresh` coalescing.

Events are matched to an anchor structurally rather than by enumerating event
types — envelope `subject`, `payload.bead_id`, and `payload.work_bead_ids` are
all checked — so a new event family that follows the same convention is picked
up with no change here. A panel watching only `subject` would sit still through
exactly the session events the operator opened it for.

## 5. Activity history is a client-side scan, and is bounded

`/events` can be narrowed by type, actor, or time but **not by subject**, so
"events about this anchor" cannot be asked of the supervisor — the filter runs
client-side over the tail of a log shared by every rig. Events carry their
payloads (~1.3KB each, measured live), so the seed window is capped at 100
events (~130KB) per drill-open, once per open rather than per event. If this
ever needs to be cheaper, the fix is a server-side subject filter on the
supervisor, not a bigger client-side scan.

## 6. Every list read carries its completeness envelope

*Added in pre-open rework (`tk-tkh4f`), from signoff findings on `tk-sj4k6`.*

**Decision.** `DrillReads` returns `ListResult<T>` — `items` plus `partial`,
`partialErrors`, `total`, `nextCursor` — for `/sessions`, `/pending`, `/beads`
and `/events`, rather than unwrapping each to a bare array.

The first cut unwrapped to `data.items ?? []`, which threw away exactly the
metadata this plane exists to respect. The board aggregates cross-rig and
answers HTTP 200 with `partial: true` and a reason per store that did not
report; unwrapped, that is indistinguishable from a complete empty answer. The
concrete failure was the drill panel telling the operator **"No agent is working
this anchor right now"** when the session store had simply not answered — the
one sentence an operator reads as permission to look somewhere else. The
city-signals strip had the matching bug: it rendered exact counts while
honouring only `mail.partial`.

Three consequences follow, and each has a test:

- **A failed read is the maximally partial read**, not an empty one.
  `unreadList()` expresses a read that never landed in the same shape, so the
  degrade-don't-hide path (a broken session lookup must not hide the bead)
  cannot degrade into a confident zero.
- **Finding something still settles the question.** A matched session is
  authoritative whatever else went missing; only *finding none* depends on the
  list having been complete.
- **Counts come from `total`,** not `items.length`, which understates the moment
  a response is truncated. Under any partial read the strip states floors ("at
  least 3") rather than numbers.

**Rejected: a separate `partial` side-channel** (a second callback, or a
context-level "something was partial" flag). It loses which read was incomplete,
which is the only thing that tells the operator whether to keep waiting.

## 7. The SSE reconnect carries its own resume cursor

*Added in pre-open rework (`tk-tkh4f`), from signoff findings on `tk-sj4k6`.*

**Decision.** `subscribeCityEvents` tracks the highest `seq` it has delivered and
appends `after_seq=<seq>` to the URL of every replacement `EventSource`.

The first cut reconnected to the bare stream URL, on a comment claiming the
browser would resend `Last-Event-ID`. It does not: the browser resends that
header only on *its own* reconnect of the *same* `EventSource` object, and this
code closes the dead one and constructs a new one. The supervisor documents a
stream opened with neither `Last-Event-ID` nor `after_seq` as starting at the
current city event head (`huma_types_events.go`, `after_seq` on the city stream
— note the *supervisor*-scoped stream uses `after_cursor` instead). So every
event emitted during the outage was dropped. Because the panel refetches only in
response to a delivered event, it would then sit on stale state while the
indicator read "live" — indefinitely, and invisibly.

The cursor is the **highest** seq delivered, not the most recent: a supervisor
restart can replay frames already seen, and a cursor that walked backwards would
re-request that replay on every reconnect after it.

**The no-cursor case is covered separately.** A connection that dies before
delivering anything has nothing to resume from, and the head is the only honest
place to restart. Both `useDrill` and `useCitySignals` therefore refetch when the
stream returns to `open` after having dropped — the belt to the cursor's braces,
and the only thing that closes that particular gap.

**Rejected: letting `EventSource` do its own native reconnect** for transient
errors (the finding offered it as an alternative). It would resume correctly via
`Last-Event-ID`, but the module would then have two reconnect regimes — the
browser's for some failures and ours for the rest — with no way to tell which is
in play, and the capped backoff would apply to only one of them.

## What was deliberately not built

- **No visual design.** Same posture as U5: a readable panel, no canvas, no
  colour language. That is U6, gated on the Claude Design handoff.
- **No write verbs.** The plane is read-only, matching the plan's deferral of
  flag/clear/takeaway. No mutation means no `X-GC-Request` CSRF header is needed
  anywhere in this leg.
- **No terminal.** U9. The session panel shows the `?peek=true` snapshot, which
  is the resting-tile "read the latest output" the epic asks for.
- **No change to `/helm` or to helm-svc's Go code.** The drill plane talks to
  the supervisor directly; the board contract U7 mirrors is untouched.

## Verification performed

Gates: `tsc --noEmit` clean; `vitest run` 52 tests across 4 files; `npm run
build` clean; `go build ./...`, `go vet ./...`, `go test ./...` all clean
(including U5's `TestAssetsResolveUnderMountPrefix`).

The 15 tests added in the `tk-tkh4f` rework were checked against the code they
regress: with the resume cursor, the envelope flags and the `total`-based counts
each reverted in place, 8 of them fail and the pre-existing 37 keep passing. A
regression test that passes on the bug it names is not a regression test.

Bundle drift: rebuilt to a temp `outDir` and compared — `dist/` is byte-identical
to a clean build of `src/`, with matching file sets.

Live, against the running city (2026-08-11): the service was run on a unix
socket and probed — `/healthz` 200, `/helm` 19 real tiles (board JSON contract
unchanged), the shell serving the new bundle, assets 200. The CSP's pinned
inline-script hash was recomputed from the *shipped* shell and matched, so U5's
mount-prefix normalizer still runs. All eight supervisor URLs the client builds
were probed live and returned 200, including `?peek=true&peek_lines=40` and the
`gc:wait` label query; the SSE stream was confirmed to frame events as
`event: event` (the name the code binds to — a handler bound only to
`.onmessage` receives nothing).
