/**
 * The TypeScript half of the board-contract parity check: a real sample of the
 * wire bytes, asserted against the hand-written contract at COMPILE TIME.
 *
 * `board.fixture.json` is generated from the Go structs and committed
 * (`go test ./web -run TestBoardFixture -update`). The assignment below is the
 * whole test — `tsc` fails when the fixture no longer satisfies `Board`, which
 * is exactly what a renamed or removed Go field produces once the fixture is
 * regenerated. `npm run build` runs `tsc` first, so this is enforced on the
 * frontend build, not only in `go test`.
 *
 * Nothing imports this module. It is type-level only, so Vite never pulls it
 * into the bundle; it exists to be type-checked.
 *
 * WHAT THIS CATCHES that the Go-side parity test does not: it validates the
 * contract against bytes the Go encoder actually produced, rather than against
 * reflection over the same structs. If the two ever disagree — a custom
 * MarshalJSON, an encoder setting — the fixture is the one telling the truth.
 * What it does NOT catch: a renamed OPTIONAL field, which simply goes missing
 * and stays assignable. That is the Go-side test's job, and why both exist.
 */
import fixture from './board.fixture.json';
import type { Board } from './contract';

/**
 * TypeScript infers WIDENED types for a JSON import: `"HIGH"` comes in as
 * `string`, not as the literal, so a fixture cannot be assigned directly to a
 * type whose fields are string-literal unions (`Severity`). This widens the
 * contract the same way for the comparison, leaving every field NAME and its
 * required/optional-ness — the parity that matters here — fully checked. The
 * literal members of `Severity` are checked against the Go constants by
 * TestSeverityParity instead.
 *
 * The mapped type is homomorphic, so `?` modifiers survive it.
 */
type JsonWidened<T> = T extends string
  ? string
  : T extends number
    ? number
    : T extends boolean
      ? boolean
      : T extends readonly (infer E)[]
        ? JsonWidened<E>[]
        : T extends object
          ? { [K in keyof T]: JsonWidened<T[K]> }
          : T;

export const boardFixture: JsonWidened<Board> = fixture;
