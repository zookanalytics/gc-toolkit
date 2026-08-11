---
name: U7 TS board contract — decisions and rejected alternatives
description: Why the helm board's TypeScript type is hand-written, and how the two-layer parity check that keeps it honest is built. Read before adding a field to the board contract or changing where the mirror lives (U8/U9).
---

# U7 TS board contract — decisions

Work record for `tk-eemvf.2` (U7 of the Attention Canvas plan,
`specs/tk-eemvf/2026-06-30-001-feat-attention-canvas-plan.md`). What is true
*now* — where the contract lives, how to add a field, how to regenerate the
fixture — is in `services/helm/README.md` under *The board contract*. This file
records what was decided and what was rejected, for whoever lands U8/U9 on top.

The deliverable is not really the type. A hand-written type is fifteen minutes
of typing; the bead is explicit that "the parity check is the deliverable that
matters — without it the hand-written mirror silently drifts." Everything below
follows from that.

## 1. The mirror is the wire only — `Anchor` and `Child` are excluded

**Decision.** `src/contract.ts` mirrors exactly `board.Board` and `board.Tile`:
the types reachable from the `GET <mount>/helm` response body. `board.Anchor`
and `board.Child` carry JSON tags too, and the bead names model.go as the source
of truth, but they are the gather-side input to `BuildBoard` and never cross the
wire. The parity test enforces the boundary in *both* directions — a Go wire
struct with no interface fails, and an interface with no Go wire struct fails
too.

**Why.** Mirroring `Anchor` would publish a contract the service does not serve.
The frontend cannot obtain an `Anchor`; a type for one is an invitation to write
code against a payload that will never arrive. The reverse rule matters just as
much: it is what stops `contract.ts` from slowly accumulating UI-only types
until "the contract" and "the types the frontend happens to use" are the same
file and neither is checkable.

**Consequence for U8/U9.** The typed supervisor client and the terminal embed
get their own types. If a future endpoint serializes `Anchor`, mirror it *then*,
and the parity test will start requiring it automatically — `wireRoot` is
walked, not enumerated.

## 2. The parity check lives in Go, not in a TS test runner

**Decision.** `services/helm/web/contract_parity_test.go` — package `web`,
alongside the existing handler tests. It reflects over the Go structs and parses
`contract.ts`.

**Why.** The check must run in whatever gate actually runs. `go test ./...` is
that gate: it is what the refinery and the codex review run on this repo, and
what a Go author touching model.go runs. A Vitest suite would put the guard on
the far side of an `npm install` that the launcher deliberately never performs
(`assets/scripts/gc-helm-svc.sh` rebuilds the binary but never runs npm), so the
one person most likely to break the mirror — someone editing model.go, in Go —
would never see it fire.

**Rejected: a TS-side runtime test (Vitest/Jest).** It adds a test runner and a
dependency tree to a package that has none, and it can only check the mirror
against *another hand-written* fixture unless Go generates one — at which point
the Go test is already there and the runner earns nothing.

**Rejected: codegen from Go to TS.** It would eliminate drift outright, which is
tempting. But it needs a generator in the build path, and `dist/` is committed
precisely because the build path must survive with no Node. A generator that
only runs when someone remembers to run it is a hand-written file with extra
steps. The bead also scopes this leg as hand-written "on purpose".

## 3. Two layers, because each catches what the other cannot

**Decision.** The Go reflection test *and* a committed wire fixture
(`src/board.fixture.json`) asserted against the contract at compile time by
`src/contract.fixture.ts`.

**Why.** They fail on different things.

- The **Go test** compares names, TypeScript types, and optionality by
  reflection. It is the only layer that catches a renamed *optional* field — the
  fixture simply stops carrying the key, and an optional property is satisfied
  by absence.
- The **fixture** is validated against bytes the Go encoder actually produced,
  not against a second reading of the same structs. If reflection and the
  encoder ever disagree — a custom `MarshalJSON`, an encoder setting — the
  fixture is the one telling the truth. It also fails on the frontend side of
  the seam (`npm run build` runs `tsc` first), so a TS author who never runs
  `go test` still gets caught.

Verified by mutation, not by assertion: renaming a Go tag fails the parity test,
fails the fixture as stale, and — once regenerated — fails `tsc`. Adding a Go
field is accepted by `tsc` (the contract is additive-only) while the parity test
demands the mirror be updated, which is the intended asymmetry.

**`TestFixtureCoversEveryField`.** The fixture is only as good as its coverage:
an optional field never populated is invisible to TypeScript. So every wire key
must appear somewhere in the fixture, and a new Go field fails this test until
`fixtureBoard()` populates it. Without it the TS layer would decay silently into
a check that passes because it exercises nothing.

## 4. `tiles: Tile[] | null`, and optionality is derived from the tag

**Decision.** The Go→TS type mapping is mechanical in `tsTypeFor`, including the
nil-slice rule: a slice or pointer *without* `omitempty` is `T[] | null`,
because `encoding/json` writes `null`; *with* `omitempty` it is an optional
`T[]`, because the key is omitted instead. `omitempty` and `omitzero` both mean
"the key may be absent", which is precisely a TypeScript `?`.

**Why.** These are the two ways a hand-written mirror is wrong in a way that
type-checks: an optional marked required (so consumers skip a guard the wire
requires) and a nullable array typed as always-present (so `.map()` is called on
`null`). Deriving both from the struct tag removes the judgement call. `tiles`
really can be `null` — `BuildBoard` returns a nil slice for an empty board — and
`App.tsx` already narrows with `?? []`.

**Rejected: normalizing `null` to `[]` in a client wrapper and typing it
`Tile[]`.** That is a reasonable thing for U8's typed client to do, and it would
be a lie here. This file describes the wire; a wrapper that improves on the wire
belongs above it, not inside the mirror.

## 5. The fixture is JSON, and the assertion widens literal types

**Decision.** The fixture is a `.json` file — the wire bytes, indented — and
`contract.fixture.ts` asserts it through a `JsonWidened<T>` mapped type rather
than assigning it directly to `Board`.

**Why.** TypeScript infers *widened* types for a JSON import: `"HIGH"` arrives
as `string`, not as the literal, so a fixture can never satisfy a type whose
field is a string-literal union (`Severity`). Widening the contract the same way
for the comparison keeps every field name and every `?` fully checked, and gives
up only the literal membership of `Severity` — which `TestSeverityParity` checks
directly against the Go constants instead, by parsing model.go's const block
with `go/ast`.

**Rejected: emitting the fixture as a `.ts` literal.** It would preserve literal
types and check `Severity` for free. But it stops being a sample of the wire —
you can no longer diff it against `curl <mount>/helm` — and, being a fresh
object literal, excess-property checking would make every *additive* Go change
fail the frontend build, contradicting the contract's central rule.

## 6. `App.tsx` imports the contract; the local shapes are gone

U5 left a deliberately minimal local copy of the envelope with a note to replace
it here rather than let it grow into a second contract. Done: `App.tsx` now
imports `Board` from `./contract` and declares no wire shape of its own. Type
erasure means the emitted bundle is byte-identical, so `dist/` is unchanged by
this leg — verified against a fresh `vite build`, not assumed.
