---
name: Design note — standing a human-gated row down once it has been answered
description: Why an answered decision/human row bands LOW rather than staying ELEVATED forever, why the rule reads the gc.routed_to marker rather than the kind alone, why disposition-due yields to it, and the before/after census taken on the live board.
---

# A ruling has to be able to end the row

Work record for `tk-b3rga`. What is authoritative about the resulting
behaviour lives in `services/helm/README.md` (*Until it is answered — the
stand-down*) and `docs/lifecycle-composition.md`; this note records the
reasoning, the one conflict the operator's ruling did not anticipate, and
the measurements.

## What was funded

The bead was filed 2026-08-10 against the *uninformative constants* half:
every `decision` tile renders byte-identical severity, frontier and needs,
so a board with a dozen decisions shows a dozen identical rows. The
operator re-scoped it on 2026-08-23 (visit `tk-oymjd`, subject `tk-jr8rw`,
ruling "yes as recommended") to the **stand-down**:

> a `decision` or `human` row whose `gc.takeaway` is PRESENT and whose
> recorded waits have all closed must band DOWN and read
> "ruled — close or extend", instead of staying ELEVATED forever.
>
> This mirrors machinery that ALREADY EXISTS for the `parked` kind […]
> Copy that shape; do not invent a new one.

Acceptance: the seven rows named in the 2026-08-23 census leave ELEVATED
on the next render, with `tk-z130v` — ruled 2026-07-24, still ELEVATED
thirty days later — as the regression case.

## The rule as shipped

An anchor is **ruled** when it is human-gated, carries a takeaway, and has
no outstanding `blocks` wait. Ruled *and childless* → LOW, frontier
"ruled — takeaway recorded", NEEDS "ruled — close or extend". Ruled *with
children* → banded by the roll-up like any other anchor.

Two implementations, because there are two boards: `assets/scripts/gc-helm.sh`
(the jq render) and `services/helm/internal/board/derive.go`. A fix landing
on one does not reach the other (`tk-9tbbk`).

## The three decisions worth recording

### LOW, not NORMAL

NORMAL is stale-bumped past fourteen days. `tk-z130v` is thirty days old,
so banding a ruled row NORMAL would return the named regression case to
ELEVATED on the next render — the rule would pass its own acceptance test
for about two weeks and then silently stop working. LOW is also what
`parked` uses for the same claim ("this wants nothing; it has to stay
findable"), which is the shape the ruling said to copy.

### The rule reads `gc.routed_to`, not just the kind

This is the conflict the ruling did not anticipate, and it costs two of
the seven acceptance rows if left alone.

A bead carrying **both** `gc.routed_to=human` and a `gc.takeaway` is
gathered **twice** on purpose — once per marker — and `BuildBoard`'s dedup
keeps the **higher band**. So the louder derivation of a bead always wins,
and any rule that *quiets* the `human` row is undone by its `parked` twin.
Concretely: the twin of an answered human bead whose waits have landed is
exactly the `disposition_due` shape, which bands ELEVATED. `tk-j5wrs` and
`sl-kg9z6.1.2` are both this shape.

So "human-gated" is defined as kind `decision`, kind `human`, **or** the
`gc.routed_to=human` marker on the anchor — the third clause is what lets
the twin be recognised as the same bead. This required widening both
gathers to carry the marker (`routed_to` in the bash meta-gather;
`Anchor.Metadata` already carried it in Go).

### `disposition_due` yields to the stand-down

`dispositionDue` gains `&& !humanGated(a)`. Two operator-ruled rules
otherwise disagree about the same bead in the same state:

| | trigger | direction |
|---|---|---|
| `disposition_due` (`tk-2plde`) | parked + waits all landed | UP, out of the LOW floor |
| `ruled` (`tk-b3rga`) | human-gated + answered + waits all landed | DOWN, out of the ELEVATED band |

They are reconcilable because they *ask for the same thing* — "dispose of
this" — and differ only in volume, and because the promotion exists
specifically to lift a row out of the parked **floor**, where nobody would
ever look at it again. A human-gated bead was never in that floor; it has
been shouting since the day it was filed. Once the stand-down answers for
the same state, the promotion adds nothing except an ELEVATED duplicate
that wins the dedup.

A `parked` row that is **not** human-gated is untouched — `tk-2plde` is
intact, and pinned by a test that says so.

### Rejected: letting a ruling quiet a stranded child

An earlier shape stood every ruled row down regardless of its roll-up.
That reintroduces `tk-a9k0l` one kind over: "answered" is a claim about
the BEAD, and open work hanging under it falsifies the claim. A ruled row
with children is therefore banded by the roll-up, exactly as a decomposed
`parked` subject is. The `parked` LOW floor already stops at a decomposed
subject for this reason; the stand-down stops in the same place.

## The wait clause was vacuous until the gathers were widened

Both gathers read `waiting_on` for `parked` **alone** — the Go comment
said so explicitly ("WHY ONLY PARKED"). Left that way, `waiting_on_open`
is empty for every `decision` and `human` row, the "and the work landed"
clause is trivially satisfied, and an answered decision whose routed work
is still open stands down anyway.

That failure mode is silent: nothing errors, no field goes missing, and
the only symptom is a row that quietly stopped asking too early. So the
gathers now read the edges for all three kinds that spend them, and
`TestWaitingEdgesAreGatheredForEveryKindThatSpendsThem` /
`(RULEHOLD)` pin which kinds those are. `epic` and `convoy` deliberately
still do not pay the read: they are banded by a child roll-up that already
reports whether their work is moving.

The clause is not hypothetical. The edges are real — `tk-lpf9g` →
`tk-vvnkj` (closed), `sl-kg9z6.1.2` → seven closed blockers — and a live
negative control turned up during implementation: `tk-hs2e8`, a decision
answered "NO" at 16:28Z on 2026-08-23 with `tk-jsyci7` routed and still
open. It stays ELEVATED, which is correct.

## Measurements

Paired control on the live loomington board, `board --json --limit=0
--refresh` from the HEAD script and from the patched script, both
returning the same 63 anchors:

| band | HEAD | patched |
|---|---|---|
| HIGH | 13 | 13 |
| ELEVATED | 26 | 19 |
| NORMAL | 1 | 1 |
| LOW | 23 | 30 |

**Exactly seven rows changed band, and they are the seven the acceptance
criterion names** — `sl-kg9z6.4.1`, `tk-lpf9g`, `tk-63qgj`, `tk-0tln5`,
`tk-z130v`, `tk-j5wrs`, `sl-kg9z6.1.2` — all ELEVATED → LOW. No row moved
UP. No `parked` row changed at all.

An earlier pair, taken minutes before, showed `tk-hs2e8` standing down as
an eighth row. That was a real race, not a defect: a converse sitting
stamped its takeaway at 16:28:33Z and wrote the `--waiting-on` edge one
second later, so the gather in between saw an answered decision with no
recorded wait. With the edge present it holds at ELEVATED, which is the
live negative control quoted above.

## What was deliberately not done

- **Closing any of those beads.** Out of scope by the ruling: converse
  does not close subjects by contract, and the point is that the BAND
  stands down without requiring a close.
- **The uninformative-constants half, in general.** A ruled row now reads
  differently from an unruled one, and a ruled row with children reports
  its roll-up — which is real information where there was none. But an
  *unruled* decision still renders the same two constants as every other
  unruled decision. That half of the 2026-08-10 framing is untouched and
  still open.
- **The FRONTIER/NEEDS column collision** noted in the same census
  ("routed to the operator — no agent wirouted — fix went inert…"): the
  CLI pads FRONTIER to 36 columns with `rpad`, which truncates without a
  gutter, so a longer phrase butts straight into NEEDS. Real, cited on
  this bead as a corroborating board fact, and a separate defect in the
  render rather than in the derivation. The phrases added here are 25 and
  23 characters so they cannot make it worse.
- **`tools/helm-surface-fixture.sh`’s phantom-`gc helm` guard**, which is
  red at HEAD and stays red here. Reproduced against a clean `git archive
  HEAD` tree, so it is not branch-local: the guard forbids the space form
  `gc helm`, and the only hit is a comment in `gc-helm.sh:952` that means
  `gc-helm open` and got line-wrapped across the hyphen. Filed as
  `tk-paunpk`. The one assertion in that fixture this change DID break —
  the whitespace-collapse case, which read `.needs` of a decision that is
  now ruled — is fixed here, and the fixture gained the stand-down
  assertions alongside it.
