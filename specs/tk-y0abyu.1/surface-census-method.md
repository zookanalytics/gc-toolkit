---
name: Operating-surface census — method and baseline reconciliation
description: The definitions assets/scripts/surface-census.sh measures the gc-toolkit operating surface by, and why the oracle's numbers differ from the manual baseline the surface-shrink epic (tk-y0abyu) recorded.
---

# Operating-surface census

`assets/scripts/surface-census.sh` is the epic's oracle: run it for the current
surface numbers (`--json` for a machine object). This record fixes the
definitions it counts by, and reconciles its reading with the manual baseline in
the epic body, so checkpoint 1 can re-aim the provisional targets against a
known method rather than re-deriving one.

## What each measure counts

- **source scripts** — `assets/scripts/*.sh` that are not `*.test.sh`, with
  their total line count. This is the shell operating surface; the oracle is one
  of them (it counts itself). Each source script falls into exactly one
  entry-point class, assigned by the widest surface that references it:
  - **outside-startable** — referenced by filename from the execution surface
    outside `assets/scripts`: `formulas`, `doctor`, `services`, `tools`,
    `orders`, `agents`, `skills`, `template-fragments`, `packs`, `lifecycle`,
    `overlays`, `.github`. Something outside the layer can start it, including a
    skill whose instructions name a script by filename.
  - **called-by-other-scripts** — not outside-startable, but named by another
    source script. Live internal call surface.
  - **docs-only** — not startable and not called by a script, but named in
    `docs`/`specs`. A documentation mention.
  - **unreferenced** — named nowhere outside its own file. A dead-surface
    candidate.

  The four classes partition the source scripts exactly, so a checkpoint can
  tell live internal surface from dead surface. `internal_only` is the roll-up
  of called-by-other-scripts and unreferenced — the scripts no external surface
  starts.
- **metadata keys** — distinct bead-metadata keys the executable operating
  surface (`assets/scripts` + `tools` + `formulas` + `doctor`) reads or writes,
  via `--set-metadata` / `--unset-metadata` / `--metadata-field` flags and the
  jq accessors `.metadata.KEY`, `.metadata["KEY"]`, `.metadata."KEY"`,
  `metadata["KEY"]`. **bare** keys carry no dotted namespace; the **namespace
  breakdown** counts keys per leading dotted segment (`bare` for the
  un-namespaced); **single-use** keys appear in exactly one file, and their
  sorted list is emitted alongside the count. Three surfaces are held out on
  purpose: `*.test.sh` (fixture keys, not the contract), full-line comments (a
  key named in prose is documented, not used), and `services` (its Go/TS
  `.metadata` is a different, non-bead structure). A key assembled at runtime
  from a variable — `--unset-metadata "check.$CHECK_NAME"` — is captured as its
  static prefix (`check.`), since the dynamic tail is not in the source.
- **duplicated helpers** — shell function names defined in three or more source
  scripts. **drifted helpers** are the subset whose definitions are not all
  identical: each definition's body is read by brace depth from its opening
  brace to the matching close and whitespace-normalized to a token signature, so
  indentation and line breaks are not differences, and a name with two or more
  distinct signatures has drifted. A name whose copies share one signature is a
  deliberately kept-in-sync duplicate — some are proven byte-identical by a test
  — and is exempt from drift.

## Reconciliation with the manual baseline

The epic body (visit tk-fw8w1w, 2026-09-29) recorded the surface manually. The
oracle at this checkout reads:

| measure | manual baseline | oracle (this checkout) |
|---|---|---|
| source scripts | 88 (~32.4k lines) | 89 / 33000 — the +1 is the oracle itself |
| outside-startable | 72 of 88 | 75 |
| — called-by-other-scripts | — | 9 |
| — docs-only | — | 5 |
| — unreferenced | — | 0 |
| metadata keys | ~176 | 151 |
| — un-namespaced (bare) | 74 | 65 |
| — single-use | 45 | 76 |
| duplicated helpers | 25 | 24 |
| — drifted (bodies differ) | — | 16 |

Source scripts, bare keys, and duplicated helpers agree within a script or two
— the manual eyeball was close. The remaining rows are method, not error:

- **outside-startable (75 vs 72)** — the oracle counts a script named by
  filename in a `skills/` instruction as outside-startable, because a skill
  starts it the same way a formula does. That is execution surface, not a docs
  mention, so those scripts count as startable rather than internal-only.
- **metadata total (151 vs ~176)** — the manual `~176` counted test fixtures and
  prose mentions; the oracle holds both out, counting only the live contract the
  operating surface reads or writes.
- **single-use (76 vs 45)** — the precise per-file count finds more one-file keys
  than the manual estimate. This widens, not narrows, the consolidation target
  the epic is after.
- **drifted vs duplicated (16 of 24)** — the manual count stopped at duplicate
  names; the oracle separates the copies that have actually diverged from the
  ones kept in sync, so the consolidation work aims at the 16 that differ.
- **called-by-other-scripts, docs-only, unreferenced (9 / 5 / 0)** — the manual
  baseline did not split the non-startable scripts. The oracle does, so a
  checkpoint reads internal call surface apart from dead surface; here nothing is
  wholly unreferenced.

The epic states the numeric targets are provisional until checkpoint 1 re-aims
them; the oracle is the method they re-aim against.
