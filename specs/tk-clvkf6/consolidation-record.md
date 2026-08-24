---
name: Target 2 record — the helm consolidation, and what the plan's table got wrong (2026-08-24)
description: What was actually done for consolidation-plan Target 2 plus the closed-dispositions rebuild, the four places the plan's measurements were wrong or incomplete, and the live divergence found while deleting the duplicate. Read it before trusting any figure in specs/tk-z9nln/consolidation-plan.md's Target 2 table.
---

# Target 2 record: finishing the helm consolidation

Work on `tk-clvkf6`, 2026-08-24, against `origin/main` at `b8a4a6a`. This is a
record of what was done and what the plan did not know — not a statement of
what is true now. For that, read `services/helm/README.md`.

## What shipped

Two things the bead asked for, in one change because the second is what makes
the first safe to delete.

**The closed-dispositions view, built in the service.** `internal/closed` is
the model; `BeadsSource.GatherClosed` reads it through the sanctioned beads
library; `GET /helm/closed`, `helm-svc closed` and the dashboard's *what was
decided* panel are three renderers over that one gather. Semantics were ported
from PR #439 (branch `polecat/tk-sfg2e` at `43993d6`, codex-green) rather than
re-derived: the operator's ruling was about *location*, and the shell
implementation's decisions — tracks-edge-first, fail-loudly, validate the
`--since` spelling, do not cache — were all correct.

**`gc-helm.sh`'s board half retired.** `cmd_board` plus every `gather_*` — 973
lines — became a 211-line renderer that locates the `helm-svc` binary, forwards
the caller's flags, and passes its bytes and exit code back.

| artifact | before | after | delta |
|---|---|---|---|
| `assets/scripts/gc-helm.sh` | 2,056 | 1,347 | −709 |
| `assets/scripts/gc-helm.test.sh` | 1,396 | 625 | −771 |
| `tools/helm-surface-fixture.sh` | 603 | 308 | −295 |
| `cmd/helm-svc/contract_parity_test.go` → `board_cli_test.go` | 668 | 516 | −152 |
| | | | **−1,927** |

Against the plan's predicted ~2,365. The gap is not a shortfall so much as a
correction, and it is made of the four items below: the parity file was
over-counted by ~490 lines (only 175 of it was duplication tax), the fixture
harness was not counted at all (−295), and `gc-helm.sh` gained back some of what
it lost in prose — the header, the usage block and the renderer's own rationale
are longer than what they replaced, because a thin renderer has to say why it is
thin.

The board half itself — `cmd_board` plus every `gather_*` — was **973 lines
replaced by 211.**

## Four things the plan's Target 2 table got wrong

The plan says to re-measure before acting. Doing so changed the work in four
ways, three of which would have caused damage if the table had been followed
literally.

### 1. `contract_parity_test.go` is not 668 lines of duplication tax

The table lists the whole file as existing "only to police the duplication."
Reading it, **175 of 668 lines do.** The rest states requirements of
`helm-svc`'s own renderer: the array-not-envelope shape, the split row cap, the
flag surface, the rune-counted columns, the content-sized id widths
(`tk-mtuej`), the bounded NEEDS cell.

One of them was written *for this change*, and says so:

> `TestPickerFieldsPresent` names the SIX fields
> `assets/scripts/tmux-pick-helm.sh` actually dereferences. The parity test
> above would catch their removal too, but only while the bash board still has
> them — **this one states the consumer's requirement directly, so retiring
> `gc-helm.sh` later cannot quietly retire the contract with it.**

Deleting the file as the table instructs would have deleted exactly the guard
its author left for whoever did the deleting. Only the four bash-board readers
were excised; the file was renamed to what it always was underneath.

A fifth reader stays: `TestBashBoardEnforcesTakeawayCap`. The `takeaway` WRITE
verb never moved and has no Go counterpart, so the script is still the only
place the ≤140 cap can be checked.

### 2. The blast radius includes a file the table does not mention

`tools/helm-surface-fixture.sh` drove another ~330 lines of board
render/rank/glyph assertions through the same `GC_HELM_FIXTURE` hook. Removing
the shell gather broke **73 of its 152 assertions**. The plan's table does not
list it.

This is not an argument against the target — it is the same duplication tax,
counted twice because the assertions were duplicated too. But a change sized
from the table alone would have discovered it at test time.

### 3. Two documented env knobs would have been dropped silently

`gc-helm.sh` honoured `GC_HELM_MAX_ROWS` and `GC_HELM_MAX_PARKED`; `helm-svc`
did not read either. A thin renderer that simply forwarded flags would have
dropped both without a word — the row cap would have gone back to 50/15 for
anyone who had set them. `helm-svc board` now reads them from the environment
it inherits.

### 4. The performance claim needed re-measuring, and it moved the design

The plan's risk note says a thin renderer "must keep a degraded-but-useful mode
rather than printing an error." Measured on the live five-rig city,
`--json --limit=0`:

| | cold | warm |
|---|---|---|
| `gc-helm.sh` (old, own gather) | 51.9 s | ~1.8 s (45 s gather cache) |
| `helm-svc board` | 6.0 / 6.6 / 7.1 s | *(no cache — every run is cold)* |
| `gc-helm.sh` (new, thin) | ~7 s | **0.11 s** |

The Go board is ~8× faster cold, but `helm-svc board` is deliberately
daemonless and uncached so `prefix+b` works when the sidecar is down. Six
seconds per glance is a different tool from 0.05 seconds per glance, and the
tmux picker re-opens the board constantly — so the cheap layer went into the
thin renderer, which is the only place that can tell a repeat glance from a
first one. It caches **rendered output**, not a gather it no longer performs.

## The divergence found while deleting the duplicate

This is the finding worth carrying forward, because it is an argument about
method rather than about helm.

`internal/source.visitSubjects` read a visit's subject from the
`gc.continuation_group` stamp alone. `gc-helm.sh`'s `gather_visits` read the
`tracks` edge **as well**. Measured over gc-toolkit's last seven days on
2026-08-24: **49 closed visits, 49 carrying the edge, 44 carrying the stamp.**

So five conversations could read *held* on the terminal board and *unheld* on
the web one. That is not a cosmetic glyph: a held anchor is never stranded, so
a missed visit promotes the row to HIGH and tells the operator to go and attend
to a conversation that is already being had.

`contract_parity_test.go` did not catch it and could not: it compared field
SETS, not values, so a derivation that changes meaning without changing shape
passes. **A field-set parity test is not a substitute for having one model — it
passes precisely the divergences that matter.** The fix landed in
`internal/source/facts.go` in the same change, because deleting a renderer
cannot fix a divergence; only deleting the duplicate can.

The shell suite's `(VISITEDGE)` case, which proved this behaviour, was given a
Go home (`TestSubjectOfPrefersTracksEdge`) rather than being dropped with the
code it tested.

## Two bugs found in this change's own work

Recorded because both were found by self-review rather than by a reviewer, and
both are the kind that survive a green suite.

**The cache slot ignored the flags.** The first draft keyed the rendered-output
cache by `(verb, --json)`. `tmux-pick-helm.sh` runs `--json --limit=36`, so a
`--limit=2` typed at a prompt within the TTL would have handed the picker two
rows — silently, because the answer is well-formed JSON either way. The slot is
now keyed by the whole forwarded argv. Mutation-checked: reverting it fails four
assertions.

**A flaky assertion in the new suite.** The degraded-replay test aged a cache
stamp by exactly 600 s and asserted the banner said `600s ago`; a second ticking
over between write and read makes it 601. It now asserts an age is *stated*, not
which one. A test that fails on the clock teaches everyone to re-run it.

## What was deliberately not done

- **No cadence, order, nudge or mail for `closed`.** The operator refused push
  explicitly: *"pull, I won't read a random digest nor can we easily have a
  cadence when my schedule varies."* The dashboard panel therefore fetches
  nothing until opened and does not poll.
- **No `partial` mode on the closed view.** A board missing a rig is still a
  true statement about the rigs it read; a disposition list quietly missing a
  wedged rig's sittings is indistinguishable from a genuinely quiet window. Any
  read failure is an error — HTTP 502, CLI exit 3.
- **No cache in `helm-svc closed`.** It answers an explicit window, and a
  cached answer would be the previous `--since` returned without saying so.
- **`gc-helm.sh` not retired entirely.** Its `open`, `react` and `takeaway`
  WRITE verbs have no Go equivalent — and `helm-svc`'s own `POST /helm/open`
  shells out to `gc-helm.sh open`. Retiring what is left means porting those
  writes, which is different work.
- **Target 4 (the control-char scrubber) not folded in.** The plan suggests
  folding it into whichever target touches a scrubber first. This change removes
  scrubber call sites rather than adding or editing one, so there was nothing to
  fold into.

## One pre-existing failure fixed in passing

`tools/helm-surface-fixture.sh`'s phantom-CLI guard greps for the literal
`gc helm`, and a comment in `gc-helm.sh` wrapped `` `gc helm\nopen` `` across a
line — so main's own script tripped main's own guard. Verified against
`origin/main` in a scratch tree before touching it. The comment meant the real
hyphenated `gc-helm`, which the guard deliberately does not match.

## Verification

| suite | result |
|---|---|
| `assets/scripts/gc-helm.test.sh` | 85 passed, 0 failed (stable over 4 runs) |
| `tools/helm-surface-fixture.sh` | 34 passed, 0 failed (was 79/73 mid-change) |
| `go build ./... && go vet ./... && go test ./...` | all 7 packages pass |
| `npm run typecheck` / `npm test` | clean / 143 passed |
| live `GET /helm/closed` over a unix socket | 15 rows across 4 rigs, titles and takeaways joined |
| live `GET /helm` | 62 anchors, 37 fields — unchanged |

Guards were mutation-checked rather than assumed: the cache key, the
never-cache-a-failure rule, the refresh-not-forwarded rule, `subjectOf`'s
tracks-edge preference, the `IncludeDependencies` hydration, the SPA's
quiet-vs-error distinction, and the SPA's pull-only rule each fail their tests
when reverted.
