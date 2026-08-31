# helm — Attention Canvas backend spine (spike: tk-sy3vj)

A long-lived Go sidecar that serves a ranked **Helm board** as JSON, sourced live
from the city's bead state. It is the backend data + serving plane for the
Attention Canvas operator dashboard (epic `tk-eemvf`) and the Go port of the
board MODEL in `assets/scripts/gc-helm.sh` (the bash PoC, which this replaces —
the bash dies).

> **The bash board is gone; the bash WRITE VERBS are what is left.**
> `tmux-pick-helm.sh:60` invokes `"$HELM_SVC" board --json --limit=36`, this
> binary. `gc-helm.sh` no longer renders a board at all: it carries `open`,
> `react` and `takeaway`, and `gc-helm.sh --json` exits 2 with `unknown verb`.
> Its own usage text points at `helm-svc board`. Retiring the remaining verbs is
> a separate decision recorded under "Two helm boards, and they diverge" in
> `docs/gascity-human-engagement.md`.
>
> There is therefore no bash field set left to drift against, and
> `cmd/helm-svc/contract_parity_test.go` — which parsed the jq object literal
> out of `gc-helm.sh` and compared key sets — was deleted with the board it
> guarded (9a6b86a). The mirror that still needs guarding is the TypeScript one,
> and `web/contract_parity_test.go` guards it.

The spine came from the `tk-sy3vj` spike; `tk-x89rn` then widened the source seam
so the board can read `updated_at` and bead metadata, which is what makes
`stale_days` real; `tk-134d7` completed the model port and added the CLI view.
See *What's proven vs. deferred*, below.

## What it does

Two entry points over ONE board. They share `internal/source` (the gather) and
`internal/board` (the ranking); neither reimplements the other.

```
helm-svc                 serve  — the sidecar (below). Bare invocation, which is
                                  how the supervisor spawns it.
helm-svc board [--json]  render — what is owed by you (tk-134d7). See *CLI view*.
helm-svc board --all     render — the city overview instead.
helm-svc probe           check  — can THIS binary read the city's bead stores?
                                  See *Readability check*.
```

As the sidecar:

```
GET /helm   -> { generated_at, total, tiles:[ Tile, ... ], sittings:[ Sitting, ... ],
                 partial?, partial_errors? }
GET /healthz     -> { "status":"ok" }   (liveness probe; no gather)
GET /            -> the board JSON, or the embedded web app for a browser
                    (Accept: text/html) — see *Web UI*
GET /assets/...  -> the web app's bundle

POST /helm/open  -> { bead, outcome, visit?, message }   file a visit on a bead
                    — the ONE write route; see *Starting a conversation*
```

A `Tile` carries 40 fields, declared in `internal/board/model.go` and mirrored
in `web/src/contract.ts`. The order started as the bash board's object literal
so the two `--json` outputs could be diffed line for line; that literal is gone
and the order is now simply the wire's:

```
id rig kind title severity owed weight held
n_closed m_total open in_progress assigned
in_progress_live in_progress_dead dead_owner in_flight in_flight_heads owned
stranded empty complete progress_mismatch
stale_days priority cross_rig_refs open_heads dead_owner_heads parked_heads
waiting_on waiting_on_open disposition_due
takeaway takeaway_at takeaway_by updated_at closed_at frontier needs rank_score
```

`updated_at` and `closed_at` are `omitzero`, and they are the only two fields a
tile may omit. A source that cannot read `updated_at` (the supervisor backend)
omits it on every row; `closed_at` is present on a `DONE` row and absent from
every live one.

Tiles are deduplicated by id and **partitioned**: every `owed` row first,
longest-waiting first, then everything else by `rank_score` descending.

### The two questions, and why they are two surfaces

`owed` marks a row whose next move is a PERSON'S — an unanswered human gate, or
a parked conversation whose recorded waits have all landed. That partition is
the board's default answer; the city overview is one flag or one keystroke away.

Ranking cannot express the split. `rank_score` is severity, then subtree size,
then staleness; severity is coarse and shared between stranded, unowned and
human-gated rows, so the term that actually orders a board is SIZE — and a
demand owed by a person has a subtree near 1 where an epic has up to 999. On one
globally ranked list the operator's own queue therefore sorts under the city's
containers by construction, whatever the bands say. Inside the queue, size is
not the question either: it is a list of decisions, so it is ordered by how long
each has been owed (`gc.takeaway_at`, falling back to `updated_at`; a row
neither can date sorts last).

| surface | default | the overview |
|---|---|---|
| `helm-svc board` | the queue, oldest first | `--all` |
| tmux | `prefix+b` | `prefix+B` |
| dashboard | the *owed by you* section, at the top of the page | the ranked table under it |

The wire arrives partitioned, so the overview sorts itself back to `rank_score`
before it is capped (`board.CityOverview`). Reading the partitioned slice as if
it were ranked costs twice: the overview leads with the queue it is meant to
sit behind, and the cap then drops whatever the hoisted rows pushed past the
limit.

In the queue the row's HEADLINE is the demand — the `needs` sentence — and the
bead title is secondary; `prefix+b` and the *owed by you* table both read it
that way. The overview asks what the city's shape is, so it leads with the
object and its frontier.

**The empty queue is a CLAIM, and it is the most consequential sentence any of
these print.** So it never renders blank: the CLI prints its coverage
(`N rigs checked, all reachable`), and an empty queue out of a PARTIAL gather is
not an answer at all — it exits `3`, because the rows that would have
contradicted it are exactly the ones the unread store was holding. The picker
reads that exit code rather than substituting an empty menu. `--all` keeps its
own contract: an empty overview is an empty overview.

### CLI view (`helm-svc board`)

```
helm-svc board                     # what is owed by you, oldest first
helm-svc board --all               # the city overview: every anchor, ranked
helm-svc board --json              # the same rows as a JSON ARRAY (the gc-helm.sh contract)
helm-svc board --all --json --limit=0   # uncapped, for tooling
```

`--json` emits a bare **array**, not the service's envelope, because that array
is what `assets/scripts/tmux-pick-helm.sh` consumes — it runs `jq 'length'` and
`.[]` over this output, and the `{generated_at,total,tiles}` envelope would make
every row invisible while still parsing cleanly. Overview rows are capped at 50
by default with separate budgets of 15 for `parked` rows and 10 for `DONE` rows
(`--limit=0` opts out of all three); the queue takes the same 50 with neither
sub-budget, because there a parked row is a conversation waiting on the operator
rather than a straggler, and no closed row reaches it at all. Exit codes: `0`
rendered, `2` usage, `3` gather failed or an empty queue could not be stood
behind — a failed gather is never rendered as an empty "nothing needs you".

`tmux-pick-helm.sh` asks for no `DONE` band at all (`GC_HELM_DONE_WINDOW=0`).
Neither menu it renders is a view an operator leaves open, and the one action
either of them offers is `open`; a closed row there would spend a hotkey on
filing a conversation about something that is finished.

It runs the gather **in-process and uncached**: no daemon, no dependency on the
sidecar being up, which is most of the point of having a CLI. Measured on the
loomington city (5 stores, 55 anchors):

| | cold | warm |
|---|---|---|
| `gc-helm.sh --json --limit=0` | 19.9 / 22.2 / 26.6 s | 1.75 / 1.82 / 1.77 s (45s file cache) |
| `helm-svc board --json --limit=0` | 3.27 / 2.76 / 2.73 s | *(no cache — every run is cold)* |

Same binary as the sidecar on purpose: a separately-built CLI would be a second
artifact that can go stale on its own, which is the failure that motivated the
epic (`tk-5nm0p`). Full rationale in `cmd/helm-svc/board.go`.

### Readability check (`helm-svc probe`)

```
helm-svc probe                     # 0 readable · 3 no store could be opened · 2 usage
helm-svc probe --timeout=30        # bound the open (default GC_HELM_PROBE_TIMEOUT, else 10s)
```

One question, cheaply: can the binary running it open a bead store? It opens
one and gathers nothing — ~0.2s against the loomington city, against 2.7s for
the board — and one readable store is enough, matching what `Gather` needs to
return a board at all.

It exists because a binary's ability to read a store is fixed by the beads
library it embedded at build time, while the store's schema moves under it
whenever `bd` is upgraded. That drift is invisible to every other signal: the
sources are older than the binary, `/healthz` answers without gathering, and
the sidecar itself keeps serving because `selectSource` falls back to the
supervisor HTTP API. In August 2026 all three read green for three days while
`helm-svc board` exited 3 on every rig (`tk-00o34c`). `probe` is the one
question whose answer moves with the store, and the build gate below spends it
on every tick.

### Anchor kinds

Five kinds are gathered. The first three are selected by the bead's issue
**type**; the last two by its **metadata** (`tk-2v08m`).

| kind | selected by | band | why |
|---|---|---|---|
| `epic` | `issue_type=epic` | derived from the roll-up | durable per-rig anchor |
| `decision` | `issue_type=decision` | ELEVATED, LOW once *ruled* | human-gated |
| `convoy` | `issue_type=convoy`, machine convoys dropped | derived from the roll-up | floating epic-improviser |
| `human` | `gc.routed_to=human` | ELEVATED, LOW once *ruled* | the operator owns it; no agent will take it |
| `parked` | `gc.takeaway` present | LOW while childless, else derived from the roll-up; ELEVATED once every `blocks` blocker has closed | a conversation that reached a takeaway |

All five are gathered by **both** backends. The library backend filters the two
metadata kinds in the store query; the HTTP backend filters them client-side
over one paged `/beads?status=open` scan (`tk-lb3u4m`). The two selectors live
in `source.metadataAnchor` — one field set, read two ways — because a bead that
is an anchor on one backend and absent from the other is the shape of bug that
cost the board its human-routed rows.

**The library backend gathers every kind twice**: once at status open, and once
at status closed over `GC_HELM_DONE_WINDOW` (default 7d, `0` disables). The open
queries stop returning an anchor the moment it is answered, so the second pass
is the only thing that gives a closed one a row. It bands `DONE`, which sorts
below every live band, and stays there until `gc-helm dismiss <id>` stamps
`gc.dismissed_at`. The two bounds are different in kind: the window bounds what
ENTERS the band, and the dismiss is the only thing that removes a row the
operator can already see. Design and the tradeoff the window accepts:
`specs/tk-ghlg1e/layout-stability.md`.

The HTTP backend scans `status=open` only, so its board carries no `DONE` band
— narrower, not wrong, and the same shape of gap the source seam already
records for `updated_at`.

**Why metadata is an anchor key at all.** The type question cannot see an
operator-owned item. `gc.routed_to=human` and `gc.takeaway` are stamped on
ordinary task/bug/chore beads, so a board keyed on type excluded them by
construction — including the one bead in the city that was provably blocked on
the operator and explicitly stamped as such. `gc.routed_to=human` is already the
city's durable marker for "a human must act"; the board just was not reading it.

Both metadata gathers **exclude** the three typed kinds, so a bead that is
already an anchor (an epic carrying a takeaway, say) is not gathered twice. A
bead carrying both markers is, and `BuildBoard`'s dedup keeps the higher band —
`human` over `parked`.

That dedup is why every human-gate rule keys on *human-gatedness*
(`board.humanGated`, which reads `gc.routed_to` off the anchor) rather than on
the kind alone. Two rows for one bead, each banded on its own, means the LOUDER
derivation always wins — in both directions. A rule that quiets the `human` row
is undone by its `parked` twin on every row it was written for; and a `parked`
twin banded by its roll-up hands the bead a HIGH *stranded* row, which is what
the board said about `gc-sc8a8`, a bead held for a named operator ruling
(`tk-lb3u4m`). The band, the frontier and the `stranded` flag all read the
marker, so the two rows describe the bead the same way and the dedup has nothing
left to arbitrate.

Both gathers read the anchor's `parent-child` children, exactly as the `epic`
gather does. The relation belongs to the bead, not to the kind, and it is
load-bearing for `parked` in particular — see *Until its work is done* below.

**`parked` is deliberately not an attention item.** It is LOW so it can never
compete for rank with a stranded epic, and the web app lists it in a section of
its own below the ranked table rather than as a row inside it. What the operator
needs from these is not triage but recall: an open bead whose visit ended with a
takeaway is already resumable — typing a bare bead id into the `prefix+a` popup
reopens the conversation on that bead (`assets/scripts/tmux-visit-prompt.sh`) —
it was only unfindable.

**Until its work is done.** The floor is a claim about the bead — it wants
nothing — and open work hanging under it falsifies the claim. So a `parked`
anchor with children is banded by that roll-up like any other anchor: HIGH when
its frontier is stranded, NORMAL when something is moving, and LOW again once
every child has closed.

That relation is the ONLY one that can see the canonical converse shape. A
sitting files the work it routes as a CHILD of the subject, and beads refuses a
`blocks` edge from a parent to its own descendant —

    $ bd dep add tk-z9nln tk-wvrga -t blocks
    Error: tk-z9nln cannot be blocked by its descendant tk-wvrga

— so those subjects have no `waiting_on` edge at all and the disposition rule
below can never fire for them. Worse, before `tk-a9k0l` both gathers hardcoded
an empty child slice, and a plain (non-epic/convoy/decision) bead reaches the
board ONLY through its parent's roll-up: the row reported zero children AND its
open children were on no board anywhere. Measured on `tk-z9nln`, 2026-08-22 —
the row read `m_total=0 · conversation parked`, while the deliverable it was
waiting for sat open, unassigned and unrouted, invisible.

A roll-up whose children have ALL closed stays LOW. The row can now *say* the
work landed (`m_total>0`, `complete`, "all N closed · 0 open"), which is what a
sweep needs to act on it; pushing the operator at that moment is `tk-2cyxo`'s
bead, not the board's.

**Until its named wait is over.** A takeaway is one frozen string, so a sitting that
ROUTES work out of a subject leaves it saying "routed — nothing further needed
here" for as long as the bead stays open, including long after the work merged.
Nothing re-read that sentence, so a finished topic and a live hold were the same
LOW row: tk-yps55 sat parked for 29 hours after its fix landed and cost a whole
sitting to discover it was done. Roughly 40% of the reserved parked budget was
going to already-terminal rows.

So the wait is recorded as a **`blocks` edge** —
`gc-helm takeaway <subject> "…" --waiting-on <work-bead>` writes it beside the
prose — and the board re-derives, per render, whether it has been discharged:

| `waiting_on` | `waiting_on_open` | row |
|---|---|---|
| empty | — | LOW, "conversation parked — takeaway recorded", or "— no takeaway recorded" when the sitting left none (a childless row; with children the roll-up answers instead) |
| non-empty | non-empty | LOW, "parked · waiting on N" — a live hold, still quiet |
| non-empty | empty | `disposition_due`: ELEVATED, "parked · blocker landed", and NEEDS becomes "blocker landed — dispose or resume" |

Two properties are load-bearing:

- **Derived, never stored.** The board re-gathers every run, so this needs no
  new field on the bead and nothing has to clear it when a blocker lands. It is
  also why it does not depend on tk-puh9d (stored `blocked` status never
  auto-clearing) being fixed first — it never consults stored status.
- **Fail-closed.** A blocker counts as landed only on a positive `closed`. One
  that cannot be resolved — a store in another rig, an `external:` reference, a
  read that failed — counts as still open, so the row keeps its pre-fix LOW
  band. A missed promotion costs a glance; a false "everything landed" invites
  the operator to dispose of a subject whose work is still in flight.

The blocker statuses are read **outside the gather cache**, in the same class as
session liveness: a cached "still waiting" is exactly the answer this exists to
stop serving. The read is skipped entirely when no anchor carries an edge, so a
city whose sittings have not written any yet pays nothing.

The disposition-due row is one of two `parked` shapes the web app lifts OUT of
the quiet section and into the ranked table — the other is a row with open
children. Leaving either below would re-hide the row the distinction exists to
surface.

### Until it is answered — the stand-down (`tk-b3rga`)

The same question, asked of the two human-gated kinds, has the opposite answer.

`decision` and `human` are banded by what they ARE, and what they are never
changes while the bead is open. So a row asked for the operator on the day it
was filed and went on asking after they answered it. Measured on the 2026-08-23
board: seven of 24 ELEVATED rows carried a `gc.takeaway` recording their own
ruling — `tk-z130v` had been ELEVATED for thirty days after being ruled — and
since converse never closes a subject by contract, nothing in the city could
ever have retired them. Two constants that never stand down are not
*unmissable*; uniform is the same thing as invisible.

A row is **ruled** when all three hold:

1. it is human-gated — kind `decision` or `human`, or a bead carrying
   `gc.routed_to=human` (which is how the `parked` twin of one is recognised);
2. it carries a `gc.takeaway`; and
3. its `blocks` waits were READ, and none of them is still open.

| shape | row |
|---|---|
| no takeaway | unchanged: ELEVATED, frontier "human-gated decision"; NEEDS names the silence (below) |
| takeaway, waits unreadable | unchanged — an unread graph proves nothing |
| takeaway, a wait still open | unchanged — answering is not finishing |
| takeaway, every wait landed, no children | LOW, "ruled — takeaway recorded", NEEDS "ruled — close or extend" |
| takeaway, every wait landed, *with* children | banded by the roll-up, like a decomposed `parked` subject |

The last row is the `tk-a9k0l` lesson one kind over: "answered" is a claim about
the BEAD, and open work hanging under it falsifies the claim. A ruling must not
become a new way to hide a stranded child.

Three properties carry over from the disposition rule, and one is new:

- **Derived, never stored** — so a re-opened question stands back up by itself.
- **The wait clause is not decoration.** It is why `waitingEdges` is read for
  `decision` and `human` and not for `parked` alone: with no edges gathered,
  "every wait landed" is vacuously true and an answered decision whose routed
  work is still open would stand down anyway. Nothing errors and no field goes
  missing — the only symptom is a row that quietly stopped asking too early.
- **An empty wait set only counts when it was READ.** The clause fires on the
  absence of open waits, and a failed per-anchor dependency query produces that
  same absence — so a Dolt timeout would stand an answered row down and invite
  the operator to close or extend a question whose routed work the board never
  checked. `waitingEdges` therefore reports a read failure as
  `Anchor.WaitingUnknown` rather than as an empty set, and `ruled` refuses it
  (tk-fhd705). `gc-helm.sh` needs no counterpart: there `waiting_on` rides on
  the same payload that produced the anchor, so a failed read drops the row
  rather than leaving it standing with its edges missing.
- **LOW, not NORMAL.** NORMAL is stale-bumped past fourteen days, which would
  put `tk-z130v` — thirty days old — straight back in the band it was standing
  down from.
- **`dispositionDue` yields to it.** That promotion exists to lift a row out of
  the parked LOW *floor*; a human-gated bead was never in that floor, and the
  stand-down answers for the same state at the volume the operator asked for.
  Both firing would put an ELEVATED duplicate of every stood-down row back on
  the board, and the dedup would keep it. A `parked` row that is not
  human-gated is untouched.

NEEDS spends itself on the disposition rather than on the takeaway, the same
trade the disposition rule makes. The takeaway here is not stale — it IS the
ruling — but NEEDS answers "what does this row want from me", and what a ruled
row wants is a close or a re-open, not a re-read. The ruling stays on the wire
in `takeaway`, where nothing truncates it; in the terminal table it was the
longest cell in that column and the least actionable.

### A parent stops counting its parked children as idle (`tk-lb3u4m`)

An anchor's roll-up reports how many children are open and how many are moving.
The gap between those two numbers is what makes a row HIGH — *stranded*, with
`decomposed, idle — assign or visit` next to it. That reading is wrong for one
class of child: a bead routed to the operator, or holding a takeaway, is not
work nobody has picked up. It has a row of its own, with its own ask on it, and
nobody is going to assign it because it is already assigned to the operator.

So `open_heads` splits. `parked_heads` names the open children that carry their
own row — `board.hasOwnRow`, the same two markers the gather selects the `human`
and `parked` kinds by — and the band, the `stranded` flag and the frontier's
count phrases all read the IDLE remainder. `open` on the wire is unchanged: it
is still every non-closed child, because the total was never the thing that was
wrong.

Three shapes come out of it:

| the anchor's open children | band | frontier |
|---|---|---|
| some idle, some parked | unchanged — the idle ones still strand it | `5 open · 0 in flight (stranded) · 2 parked for the operator` |
| all parked | NORMAL — no ask of its own | `2 parked for the operator · nothing idle` |
| none parked | unchanged, byte for byte | `2 open · 0 in flight (stranded)` |

Measured on the live board the day this landed: `sl-kg9z6.1` had been reporting
`7 open, 0 in flight (stranded)` while three of those seven were waiting on a
named operator ruling, and `tk-eemvf` and `tk-9tbbk` were reading `decomposed,
idle — assign or visit` with nothing under them but a parked child.

## Converse sittings (`tk-ghlg1e.1`)

Beside the ranked list the envelope carries the **conversation record**: every
converse sitting that is running, plus those that closed inside a recent window.
A sitting is a `task_kind=visit` bead — the bead a converse session claims and
holds a conversation inside — and it is the same read that produces `held`.

Sittings are **not tiles and are not ranked against them**. A tile is an anchor
that wants something; a sitting is an event. The web app gives them a section of
their own below the parked one, and `helm-svc board` prints them under the
table, for the same reason parked conversations get a section: putting an event
in a queue of demands answers a question nobody asked.

| | gathered | shown |
|---|---|---|
| running | `status` open or in_progress | always — a live conversation is never elided |
| closed | `closed_at` inside `GC_HELM_SITTINGS_WINDOW` (default `24h`) | most recent first, capped at 12 in a rendered view |

`GC_HELM_SITTINGS_WINDOW` takes a Go duration (`6h`, `90m`). `0` gathers no
closed sittings and leaves the running ones untouched; anything unparseable
falls back to the default, because a malformed knob must not cost the board a
section. The bound lives on the QUERY (`ClosedAfter`), not in the renderer:
closed visits accumulate forever, and reading them all to throw most away would
grow without limit against a store the whole city shares.

The two passes fail independently. Losing the closed pass costs the recent
history and nothing else — `held` is derived from the running half of the same
record, so the glyph and the section can never disagree about what is held.

### The justification a sitting closed on

`gc.outcome` is stamped on the VISIT before it closes (`folded`, `moot`,
`benign`, `diagnosed`, `cut-short`, or the word a held sitting signs off with).
It is per-sitting and never rewritten, so it is attributable with no inference
at all. A running sitting has none, and renders as `—` rather than as blank.

`gc.takeaway` is the harder half, and it is why `Sitting.takeaway` is not a
copy. **The takeaway lives on the SUBJECT, and each sitting overwrites the last
one's.** A subject visited three times has one takeaway and two sittings that
did not write it, so hanging it on all three rows would credit two of them with
a conclusion they never reached. The service carries it only for the sitting
whose own span — `gc.claimed_at` (falling back to the bead's creation) to
`closed_at`, or to now while it runs — contains `gc.takeaway_at`.

Measured on the live city, 2026-08-26: `tk-7linih` was visited twice, by
`tk-5063jn` (closed 20:52, `diagnosed`) and `tk-eb5cot` (20:58–21:21,
`unblocked`). Its single takeaway is stamped 21:20:48, inside the second span
and after the first had ended. The span test is what stops the earlier sitting
from displaying a headline written half an hour after it closed.

Two sittings that genuinely overlap on one subject could both contain the stamp.
The visit claim serializes them in practice, and the failure there is a
duplicated headline rather than a misattributed one. A subject that cannot be
read at all leaves its sittings showing an outcome and no headline — narrower,
not wrong — and marks the gather partial.

### Where it shows up

Both terminal views print the section under their rows, the queue and `--all`
alike: the record belongs to the board rather than to one of its views, and a
conversation nobody ended is owed in the same sense the queue's rows are. `●`
marks a running sitting; AGE is measured from the start of a running one and
from the end of a closed one. `--json` is **untouched**: it emits the bare
ranked array that `gc-helm.sh --json` emits and `tmux-pick-helm.sh` consumes,
and growing a second shape there would break that contract.

The web app renders the same order — running first, longest-running first, then
most recently closed — and drills in on a sitting's SUBJECT, since that is the
anchor the drill plane knows how to open. Because `POST /helm/open` already
invalidates the cached board, a visit filed from the drill panel appears in this
section on the next read rather than after the TTL.

**`gc-helm.sh` needs no counterpart.** This adds no field to `Tile` and no
anchor kind, so the bash board's `--json` contract and the parity test are
untouched; the bash board simply has no sittings section. Adding one there is a
separate decision, in the same class as the other bash-only verbs.

## Architecture

Three packages, a clean dependency line `board <- source <- server <- cmd`:

| Package | Responsibility |
|---|---|
| `internal/board` | The MODEL. Pure, I/O-free: severity, counts, frontier/needs, `rank_score`, sort+dedup. Ported field-for-field from `gc-helm.sh`. |
| `internal/source` | The data-access **seam**. `Source` interface + two backends: `BeadsSource` (in-process beads library, the default) and `SupervisorSource` (HTTP client against the supervisor API). |
| `internal/server` | HTTP routes + a server-side TTL cache of the computed board. |
| `web` | The operator's web app (Vite + React + TS) and the `go:embed` that compiles its built bundle into the binary. |
| `cmd/helm-svc` | Entrypoint: listen on the `GC_SERVICE_SOCKET` unix socket, wire source→server, graceful SIGTERM. |

### Data-access contract (hard constraint)

All bead/Dolt access goes through a Gas City API — **never raw Dolt**. There is
no `sql.Open("mysql")`, no `JSON_EXTRACT` against bead DBs. The `source.Source`
interface is the seam, and the shipped backends sit behind it without the model
or serving code knowing which one is live.

**`BeadsSource` — the in-process beads library (default).** Opens each rig's own
`.beads` store through `beads.OpenFromConfig`, the same library the `bd` CLI uses
and the same access pattern the bash PoC always had (`bd list --db
<rig>/.beads`). Rigs are enumerated on disk — the HQ store at `<city>/.beads`,
then `<city>/rigs/*/.beads` — so it needs the city root and no HTTP at all.
Store handles are opened lazily and reused for the process lifetime; the rig
*set* is re-read each gather, so a rig added later is picked up without a
restart.

**`SupervisorSource` — the loopback HTTP API (fallback).** Endpoints consumed
(all under `/v0/city/<city>/`): `/rigs`, `/beads?type=epic`, `/beads/graph/{id}`
(all-status child roll-up), `/beads?type=decision`, `/convoys` + `/convoy/{id}`,
and `/beads?status=open` paged to the end — one scan the `human` and `parked`
kinds are filtered out of client-side, and whose parent-child edges are inverted
into those anchors' child roll-ups so they cost no request of their own.

**The `gc` CLI (`internal/source/gccli.go`) — for two facts no bead carries.**
`gc session list --state all --json` for session liveness, and `gc convoy list`
/ `gc convoy status` for convoy ownership and the in-flight join. This is the
same source `gc-helm.sh` reads, so the two boards agree by construction rather
than by two derivations. It honours the contract for the same reason the other
two do — a Gas City interface, not raw Dolt — and every call is best-effort: a
missing or failing `gc` records a partial error and narrows the board (nothing
reads as held or in flight) instead of aborting the gather. The lost session map
is named explicitly in `partial_errors`, because without it every claim reads as
a dead owner and a healthy board would otherwise turn red with no explanation.

Either way, cross-rig `partial` / `partial_errors` are propagated to the board
envelope, and a total outage (no rig or no endpoint readable) surfaces as a 502
from `/helm` rather than an empty board that reads as "nothing needs attention".

### Why there are two backends

`SupervisorSource` cannot see one fact the model needs, and this is a property
of the API, not of the client:

- **`updated_at` reaches no endpoint at all** — not `/beads`, `/beads/graph/{id}`,
  `/beads/ready`, `/bead/{id}` or `/convoy/{id}`. The `Bead` schema declares the
  field, but it serializes `omitzero`, arrives zero everywhere, and there is no
  `fields`/`full` parameter to widen the projection. Without it `stale_days` is
  pinned to 0 and **no tile can ever age**.

`BeadsSource` reads it directly. Choosing it over a new supervisor endpoint —
the other sanctioned path — is recorded, with the measurements, in
`specs/tk-x89rn/source-backend-decision.md`; the short version is that the
supervisor is the `gc` binary in the **gascity** rig and cannot be changed from
this repository.

**Two further reasons stood here until tk-lb3u4m measured them and found them
false:** that metadata reaches only the single-bead reads, and that the
metadata-keyed kinds are therefore unreachable over HTTP. `GET /beads` really
does take no metadata predicate, but its payloads carry `metadata`,
`description`, `priority`, `assignee` and `dependencies`, so the filter runs
client-side over one paged scan — nine requests and ~750 ms for the whole city's
900 open beads, against a gather already dominated by the per-epic
`/beads/graph/{id}` calls. What that belief cost was not a narrower board: it was
a board on which the four beads provably waiting on the operator had no row at
all, and the epic above one of them read `decomposed, idle — assign or visit`.
Measured on the live city, the same gather went from 28 tiles to 81.

The **sittings** record is absent on this backend, and not for either of those
reasons: it is derived from the visit read, which `SupervisorSource` does not do
at all. Under `GC_HELM_SOURCE=supervisor` the envelope's `sittings` is `null`
and neither view renders the section.

**Costs of the library backend, paid at build time, not per request:** the
module went from zero dependencies to ~170 (the Dolt / go-mysql-server stack),
`helm-svc` is ~161 MB, and the Go floor moved to 1.26.5. A cold build measured
**2m29s** on 2026-08-22 (1.3 GB of build cache); a warm one ~12.5s. Those
numbers are why the build does not run in the service start path — see
*Building* below. Startup itself is an `exec` and costs nothing.

**One behavioural difference.** The HTTP backend reports one extra anchor,
because gascity's `mapBdStatus` flattens every status that is not
`closed`/`in_progress` into `open` — so a **deferred** epic arrives over HTTP
looking open and is admitted. The library backend sees the real status and
filters to `open`, matching `gc-helm.sh` (`bd list --status open`). A
deliberately-deferred epic is not an attention item, so the library behaviour is
the faithful one. Child counts are unaffected: the board already treats every
non-closed, non-in-progress child as open.

### Picking a backend

Selected once at startup and logged — never silently per request, because a
per-request fallback could drop the staleness lane while the board still looked
healthy.

| `GC_HELM_SOURCE` | Behaviour |
|---|---|
| unset (default) | beads library if this binary can actually OPEN a rig store; otherwise the HTTP API, with a log line naming the consequence |
| `beads` | force the library; **fatal** if no store can be opened, rather than a quiet downgrade |
| `supervisor` | force the HTTP API (accepting `stale_days = 0`, no visits or sittings, no in-flight join, and unresolved waiting edges) |

**The test is an OPEN, not a path check** (tk-4cqtv). Resolving
`<city>/rigs/*/.beads` is not enough to know this backend can serve: a binary
whose embedded beads library is older than the live stores finds every directory
present and fails only later, per rig, inside each gather with a schema-version
mismatch. Selecting on the cheap check therefore made the one failure the
fallback exists for invisible to the code choosing the fallback — a helm-svc
reported itself healthy while every gather across all four rigs died. The
startup probe opens a store, which is where that error is raised.

Paying for that open at startup costs nothing extra: the handle is cached, so
the first gather reuses the connection the probe made. It moves the first
connection earlier rather than adding one, and only a *candidate* beads backend
is probed — a forced `supervisor` never pays. A probe that fails or times out
selects the HTTP API rather than refusing to start, because a degraded board
beats no board.

## Wiring it as a workspace-service

The service is a `proxy_process`: the supervisor spawns the launcher, hands it a
unix socket in `GC_SERVICE_SOCKET`, and reverse-proxies
`/v0/city/<city>/svc/helm/helm` → `GET /helm` (path-stripped).

**Placement (important).** `[[service]]` is **forbidden in rig-imported packs**
(`internal/config/pack.go` — gc-toolkit is rig-imported by four rigs), so the
declaration must live in a **city-scoped** location: `city.toml` itself or the
city-root `pack.toml`. The Go binary stays in the rig; the `command` resolves
relative to the declaring pack's `SourceDir`, which for a city-scoped service is
the **city root** — hence the relative `rigs/gc-toolkit/...` path below.

Add this to the city's `city.toml` (town repo — **operator/keeper action**, see
*Handoff*):

```toml
[[service]]
name = "helm"
kind = "proxy_process"

  [service.process]
  command = ["bash", "rigs/gc-toolkit/assets/scripts/gc-helm-svc.sh"]
  health_path = "/healthz"
```

`publish_mode` defaults to `private` (a pack must not set `direct`), and
`state_root` defaults to `.gc/services/helm`. The launcher
(`assets/scripts/gc-helm-svc.sh`) `exec`s the prebuilt binary — so SIGTERM
reaches the Go process — and builds nothing. See *Building* for what does.

Once declared, the board is reachable:

```bash
curl http://127.0.0.1:8372/v0/city/<city>/svc/helm/helm   # ranked board
open http://127.0.0.1:8372/v0/city/<city>/svc/helm/       # the web app
# and through the same tailscale origin the gc dashboard uses (:8372).
```

### Building

The build does **not** run in the service start path, and this is load-bearing.

The supervisor gives a `proxy_process` **5 seconds** to answer its health probe
(`proxyProcessReadyTimeout`, gascity `internal/workspacesvc/proxy_process.go`).
A warm build of this module takes ~12.5s and a cold one 2m29s. A build started
by the launcher therefore never finished inside the window — not on a slow day,
ever — and `waitReady` then called `stopProcessGroup()`, killing the build along
with the start. The next start began again and was killed at 5s again.

That loop was visible on disk: on 2026-08-22 this service's `bin/` held **2,677**
zero-byte `.helm-svc.build.XXXXXX` staging files laid down over three days, one
per killed start, each a `mktemp` that never reached its `mv`.

So the two jobs are separate:

| | script | when |
|---|---|---|
| build | `assets/scripts/gc-helm-build.sh` | the `helm-build` order, every 5m |
| start | `assets/scripts/gc-helm-svc.sh` | the supervisor, on demand |

`gc-helm-build.sh` rebuilds when a source is newer than the binary — an
ordinary `find -newer` dependency, the same question `make` asks — publishes by
atomic rename so a failed link can never truncate a serving binary, and in
`--deploy` mode restarts the service onto what it published. Build and restart
are one step on purpose: a new binary that nothing restarts onto is the other
half of the defect. On 2026-08-22 the helm process had been up 14h55m on a
binary built at 02:40 while three commits touching `services/helm` had landed
after it, all three inert in the served board.

**Source mtime is not the only way to go stale.** A binary can be newer than
every source file and still fail every gather, because what it can read is
fixed by the beads library it embedded and the store's schema moves
independently. `find -newer` is structurally blind to that: deleting a file
makes nothing newer, and a dependency that drifts under an unchanged `go.mod`
never touches a source at all. So the gate also asks `helm-svc probe`, and
`build-status` records the answer rather than the build:

| `build-status` | meaning |
|---|---|
| `ok <ts>` | built or current, **and** the binary can read the stores |
| `unreadable <ts> <why>` | it cannot; the board will not render |
| `unprobed <ts>` | no city in the environment to probe against (a hand run) |
| `failed <ts>` | the build itself failed; the previous binary is untouched |

`ok` is written only behind a passing probe, so nothing downstream can read
this file as a healthy board while the gather it reports on cannot run. An
unreadable binary exits the gate non-zero, which is what turns the order red.

Nothing is ever restarted onto a binary the probe has condemned. In `--deploy`
mode the readability answer comes before the restart, on both paths: a build
whose artifact fails the probe reports and stops without marking
`restart-pending`, and an up-to-date binary that fails it is not restarted onto
even when a previous run left that marker behind. The service keeps running the
binary it already has.

**A rebuild is the remedy only while it can produce a different binary.** When
the stale thing is the `go.mod` pin rather than the sources, rebuilding embeds
the same library and changes nothing, so repeating it every five minutes buys
a rebuild loop and buries the real fix. The gate records the beads version of
the binary whose probe failed in `<state_root>/probe-failed`; a later tick that
would embed that same version reports and stops instead of rebuilding, naming
the dependency to bump. Moving the pin re-arms it, and a passing probe clears
the record.

**A publish that was never restarted onto is remembered.** Publishing marks
`<state_root>/restart-pending`, and only a restart that returns success clears
it; the next `--deploy` run restarts even though the binary is by then current.
Without that record the same inert state returns by a different road: a restart
that fails once leaves a binary newer than every source, so nothing is ever
stale again, every later tick exits on "is up to date" without reaching the
restart, and the old process serves the old inode until someone edits a source
file. The same record is what carries a hand-run build (below) to the service.

To build by hand — after editing Go sources or rebuilding `web/dist` — run:

```bash
assets/scripts/gc-helm-build.sh            # build iff stale
gc service restart helm                    # serve it now, rather than waiting
```

The `gc service restart` there is only to see it immediately — the build records
the publish either way, so the next `helm-build` tick would restart onto it
within 5 minutes. A restart run by hand does not clear that record (only the
build's own restart does), so it costs one redundant restart on the following
tick; `rm <state_root>/restart-pending` skips it. Recognising a hand restart
would mean probing whether the running process is on the new inode, which is
exactly the bespoke liveness machinery this split exists to avoid.

If the binary is missing entirely the launcher exits non-zero with a message
naming the builder, and the service sits `degraded` until the order builds one.
It deliberately does not build its way out: it has 5 seconds.

## Web UI

`web/` is a Vite + React + TypeScript app — the operator's board surface —
embedded in the binary and served at the service mount. This is the U5 scaffold
(`tk-eemvf.1`): **structure only**. It renders the board contract as a plain
readable table. The spatial canvas, and the visual direction it implements, are
U6 and land on top of this.

It renders the board as **two** tables. The ranked one is the board proper;
below it, when the gather found any, a *parked conversations* section lists the
QUIET `parked` tiles — id, rig, title, staleness, and how to resume. They are
split because they answer different questions, and mixing them would put a
thread that wants nothing in the same ranking as work that is stuck
(`tk-2v08m`). A `parked` tile that is owed a disposition (`tk-2plde`) or has
open children (`tk-a9k0l`) is not quiet and stays in the ranked table. The
parked table drops the progress columns: every row that reaches it has an empty
open frontier, so `open/wip` reads the same answerless `0` on all of them.

Four things about it are load-bearing.

**`base: './'` (KTD5).** The app is served under a runtime-city-named prefix
(`/v0/city/<city>/svc/helm/`), never at an origin root, and the supervisor's
service proxy strips that prefix before the request arrives — so the server
cannot know it and cannot rewrite absolute URLs. Every asset reference must be
document-relative. `base: '/'` is the known failure for this service: it works
on a dev server and 404s everything under the mount. `TestAssetsResolveUnderMountPrefix`
resolves the shell's references the way a browser does and fetches them back
through a simulated mount, so a regression fails the build rather than the
board.

The same proxy maps both `.../svc/helm` and `.../svc/helm/` to `/`, so the
server cannot redirect the slash-less form either. An inline script in
`index.html` normalizes it client-side, before the deferred module scripts run.

**`dist/` is committed.** The builder rebuilds the Go binary on demand but
never runs npm, so the built bundle is tracked — same contract as the stock
dashboard SPA. After changing anything under `web/`, rebuild and commit the
output:

```bash
cd services/helm/web
npm install        # first time (or npm ci)
npm run build      # tsc + vite build -> dist/
git add dist       # the bundle ships in the repo
```

The builder treats `web/dist/**` as build input alongside `*.go`, so a
bundle-only change still triggers a rebuild of the binary that embeds it.

**The bare mount answers two audiences.** It has always returned the board
JSON, and the app has to live at that same path because a workspace-service
gets exactly one mount. So the representation follows the request: a browser
navigation (`Accept: text/html`) gets the app, everything else — curl, `fetch`,
any script — gets the JSON it always got. `/helm` is JSON unconditionally; that
is the contract U7 mirrors and U8/U9 consume, and no Accept header changes it.

```bash
npm run dev        # http://127.0.0.1:5175, proxying the board fetch to a live mount
HELM_DEV_MOUNT=http://127.0.0.1:8372/v0/city/<city>/svc/helm npm run dev
```

`HELM_DEV_MOUNT` must resolve to loopback — the supervisor binds loopback only
and the dev proxy refuses to send traffic off-host.

## Terminal

`web/src/terminal/` embeds a live terminal in the board (U9, `tk-eemvf.4`): a
peek at rest, a live terminal on focus. It attaches to the city's **existing**
ttyd — this service owns no PTY and spawns no process.

```
ttyd -i 127.0.0.1 -p 7681 -b /terminal -W -a <guard script>   # -> gc session attach <session>
```

Four things about it are load-bearing.

**It works because a tailscale mapping makes it same-origin.** ttyd is
published by its own `tailscale serve` mapping, separate from the supervisor's:

```
https://<host>/terminal  ->  http://127.0.0.1:7681/terminal    (ttyd)
https://<host>/v0        ->  http://127.0.0.1:8372/v0          (supervisor, and the board under it)
```

So on the published origin the board and ttyd share an origin, and the socket is
admitted by this app's own strict `connect-src 'self'` CSP with **no widening**
and no CORS. That is a property of the tailscale mapping, not of the supervisor:
reach the board directly on `127.0.0.1:8372` instead and ttyd is a different
port, a different origin, and the terminal cannot connect there. The app says so
rather than hanging — see the reachability check below.

**The reachability check is a content-type check, not a status check.** The
supervisor serves a SPA at its root with a catch-all that answers *every*
unmatched path with `200 text/html`. On an origin that does not route ttyd,
`GET /terminal/token` therefore looks perfectly healthy:

```bash
curl -si http://127.0.0.1:8372/terminal/token | head -2   # 200, text/html  <- NOT ttyd
curl -si http://127.0.0.1:7681/terminal/token | head -2   # 200, application/json
```

A status-only probe reports a working terminal and the operator finds out when
the socket dies. The tile requires `application/json` before opening a socket,
so a misrouted origin produces a sentence instead of a silent failure.

**Closing a tile detaches; it never kills the session.** ttyd runs one
`gc session attach` per connected client, and that process is a *tmux client* of
a session that outlives it. Teardown therefore closes the socket and writes
**nothing** — an `exit`, a `^C` or a `^D` written on the way out is
indistinguishable from the operator typing it and would end a live agent's
session. `session.ts` holds the invariant, `session.test.ts` asserts it, and it
was verified end-to-end against a real ttyd wrapping a throwaway tmux session:
after a clean close the session, its shell, and its ability to run commands all
survived. See `specs/tk-eemvf.4/decisions.md`.

**One terminal, any session.** The attach target is chosen per connection, not
baked into the systemd unit (`tk-rbf9r`). ttyd runs with `-a/--url-arg`, which
appends each `arg` in the socket's query string to the argv of the command it
spawns, so `…/terminal/ws?arg=<session>` selects what gets attached:

```
ttyd -i 127.0.0.1 -p 7681 -b /terminal -W -a \
  <rig>/assets/scripts/gc-terminal-attach.sh
```

`?session=<name>` on the board's own URL is what puts it there — an operator
knob in the same family as `?terminal=`, accepting anything `gc session attach`
names: an id (`lx-k7r38`), an alias (`gc-toolkit/gc-toolkit.witness`), or a
session name. Naming nothing sends no `arg` and lands on the city default,
`gc-toolkit.mayor`, which is exactly what this terminal did before.

**`-a` means the URL chooses argv, so a guard is load-bearing.**
`assets/scripts/gc-terminal-attach.sh` is the only thing between the query
string and `gc`. It takes at most one argument (ttyd appends *every* `arg=`, so
a second one is an injection attempt, not a typo), refuses a leading `-`, `..`,
whitespace and shell metacharacters, and then — the part that actually decides
— requires an exact match in the live `gc session list`. A name that is
well-formed but not live is refused. A name that fails anything is refused
outright rather than quietly falling back to the mayor: `gc session attach`
runs tmux, tmux clears the screen on attach, so a "that was rejected" notice
would be wiped and the operator would be typing into the mayor believing it was
something else. `assets/scripts/gc-terminal-attach.test.sh` covers this
hermetically, driving the real script against a stub `gc` with the hostile
inputs that ttyd 1.7.7 was measured to deliver.

The guard `exec`s the attach rather than forking it, so ttyd's close-time
SIGHUP lands on the tmux client itself — that is the deployment half of the
detach invariant above.

**What this widens.** Any client that can reach the terminal could already open
a writable mayor terminal, so this does not change *whether* write is possible;
it changes *which* sessions are reachable, from one to every live session. That
is real. It is bounded by the tailnet (there is no new port and no new
`tailscale serve` mapping), and by the allowlist, which can only ever name
sessions that already exist.

**Still one terminal — that part is now layout, not wiring.** How many
terminals a board should show at once, and how a tile maps to a session, are
the open questions; the board contract carries no session for a tile, so
drill-target → session is deliberately not guessed here. Deferred to the design
handoff, tracked as `tk-mw9qz`.

The tile reports at least 80x24 to ttyd however small it is rendered, because
tmux sizes a window to fit its clients and a tile reporting its own size would
reflow a terminal the operator is also attached to.

For dev, the vite server proxies `/terminal` (with `ws: true`) to ttyd's
loopback port, reproducing the same-origin shape the tailscale mapping provides
in deployment; override with `HELM_DEV_TTYD`, which is loopback-checked exactly
like `HELM_DEV_MOUNT`.

## The board contract

`web/src/contract.ts` is the TypeScript mirror of the Go structs in
`internal/board/model.go` — the body of `GET <mount>/helm`, and the one shape
the frontend is allowed to assume. It is **hand-written**: the `/svc/` surface
is not in the supervisor's OpenAPI document, so there is no generated client to
hang a type off.

What makes that safe is the rule in model.go's package doc — the tags are an
**additive** contract, so fields may be added but never renamed or removed. What
makes it *stay* true is `web/contract_parity_test.go`, which fails `go test ./...`
when the two sides disagree about a field's name, its type, or whether it is
optional. It mirrors the wire only: `board.Anchor` and `board.Child` carry tags
too, but they feed `BuildBoard` and never cross the wire, so the parity test
rejects an interface for them just as it rejects a missing one for `Tile`.

**Adding a field to the board.** Add it to the Go struct, mirror it in
`contract.ts`, populate it in `fixtureBoard()`, and regenerate the fixture:

```bash
cd services/helm
go test ./web -run TestBoardFixture -update   # rewrites web/src/board.fixture.json
go test ./web                                 # parity + coverage
(cd web && npm run build)                     # tsc asserts the fixture against contract.ts
```

Skip any of those and a test tells you which one — that is the point of them.

**Why two checks.** The Go test compares by reflection, and is the only layer
that catches a renamed *optional* field (the key just goes missing, which an
optional property tolerates). The fixture is a committed sample of the bytes the
Go encoder actually produced, asserted against the contract at compile time by
`web/src/contract.fixture.ts`; it validates the encoder rather than a second
reading of the structs, and it fails `npm run build`, so a frontend author who
never runs `go test` is still caught. `TestFixtureCoversEveryField` keeps the
fixture from decaying into a check that passes because it exercises nothing.

Two shapes deserve care when mirroring, and the mapping derives both from the
struct tag rather than leaving them to judgement: `omitempty`/`omitzero` becomes
a TypeScript `?`, and a slice *without* `omitempty` becomes `T[] | null` because
`encoding/json` writes `null` for a nil slice. `tiles` and `sittings` really are
nullable — narrow them (`board.tiles ?? []`) before iterating.

Reasoning and rejected alternatives (codegen, a TS test runner, a `.ts`
fixture): `specs/tk-eemvf.2/decisions.md`.

## Starting a conversation (`POST <mount>/helm/open`, tk-yc00g)

The board's **one write route**, and the drill panel's one write action: file a
visit on a bead so a converse session picks it up. Everything else this service
serves is a read.

The affordance already existed in tmux (`tmux-pick-helm.sh` → `gc-helm.sh open`),
but the operator's main surface is the web board, so it needed to exist there.

**It owns no visit logic.** Visit filing lives once, in `gc-helm.sh open`'s
marked `gate-visit` block, and this route *shells out to that verb* exactly as
`assets/scripts/gc-visit-open.sh` does — so the subject-existence gate
(tk-ujwvt), the one-open-visit-per-subject gate, rig resolution by id prefix and
the board cache bust are inherited, not reimplemented.
`assets/scripts/gate-visit.test.sh` guards that single copy; a Go
reimplementation would be an unguarded second one.

```bash
curl -X POST http://127.0.0.1:8372/v0/city/<city>/svc/helm/helm/open \
  -H 'Content-Type: application/json' -d '{"bead":"tk-abc12"}'
```

**What it does not do: attach.** In tmux, `open` reattaches the caller. In a
browser there is no pane to attach to until the embedded ttyd can be retargeted
at the new session (tk-rbf9r, whose city-repo half tk-xlup8 is written but
unapplied). So the button *files* the visit and says a conversation is opening;
the panel copy is explicit that it did not attach you. That is a follow-on, not
a reason to hold this.

### What the operator is told

`gc-helm.sh`'s exit codes are its contract, and the handler maps each to its own
status and a stable `reason` slug. The tool's own stderr sentence is passed
through **verbatim** as `error` — `cmd_open` already writes a different, specific
sentence per failure (wrong id prefix vs. no ledger answers vs. data plane
down), and re-deriving that here would be a second copy of the script's
knowledge.

| exit | HTTP | `reason` | meaning |
|---|---|---|---|
| 0 | 200 | — | `outcome` is `filed`, or `existing` when one was already open |
| 2 | 500 | `usage` | the handler and the script disagree about the request — a wiring bug |
| 3 | 503 | `environment` | missing dependency, rigs unenumerable, gather failed |
| 4 | 422 | `verb_failed` | bead not found / unverifiable / filing failed |
| — | 504 | `timeout` | the tool did not finish; a visit may or may not have been filed — check the bead |
| — | 503 | `unavailable` | no visit tool resolved, or it could not be run |

Refused before the subprocess runs: `invalid_bead` (400), `forbidden` (403),
`busy` (409).

**Exit 3 is knowingly coarse, and deliberately not papered over here.** In the
script it still collapses a rig-enumeration timeout, a jq parse failure and a
genuinely rigless city into one sentence (tk-lzdty half 2). Guessing between
them in Go would hard-code that ambiguity in a second place; passing the
sentence through means the day tk-lzdty lands and the script's sentences
separate, the browser separates with it and **nothing here changes**.
`internal/server/open_parity_test.go` reads `gc-helm.sh` and feeds the parser the
sentences it really contains, so a reworded echo fails a test instead of quietly
degrading every open to an unclassified outcome.

### Exposure

helm-svc is published to the tailnet by tailscale-serve, so reaching this route
already requires being on the tailnet — the same boundary that admits the
board's reads and the ttyd terminal. **This route does not widen it**, and adds
no login or token: the service has no session concept, and inventing one here
would be a second, weaker authentication story beside tailscale's (the same
reasoning `web/src/terminal/endpoint.ts` gives for not re-checking the ttyd
session name in the browser).

What POST adds over GET is not reachability but **CSRF** — the operator's
browser is *on* the tailnet, so any page they visit could otherwise write here
with their network position. So the handler requires a same-origin write
(`Sec-Fetch-Site`, with `Origin` as the fallback tell for a browser-shaped
request), and validates the bead id against the id syntax **before** it becomes
an argv element — an id beginning with `-` would otherwise be read by
`cmd_open`'s flag loop as a flag. Whether the bead *exists* stays the script's
gate; a second copy in front of it would only drift.

Concurrent opens of the same bead are collapsed in-process (409 `busy`):
`cmd_open`'s one-visit-per-subject gate is read-then-create, so a double-click
could otherwise race it and file the second visit it exists to prevent.

### Configuration

| env | default | meaning |
|---|---|---|
| `GC_HELM_OPEN_TOOL` | set by `gc-helm-svc.sh` to its sibling `gc-helm.sh` | path to the visit tool |
| `GC_HELM_OPEN_TIMEOUT` | `120s` | bounds one `open` run (Go duration or bare seconds) |

The launcher resolves the tool as its own sibling rather than the binary
guessing `rigs/<rig>/…`: gc-toolkit is rig-imported by four rigs, so there is no
single correct rig name to hardcode. If nothing resolves, the board serves
read-only and the route answers 503 saying so — rather than 404ing as though it
were a typo.

The run is placed in its own **process group** and cancelled by signalling the
group. `gc-helm.sh` spawns `gc`/`bd` children, and killing only the script
leaves a child holding the inherited stdout pipe — measured, that made a 50ms
deadline return after a full 5s, which is precisely the wedged-data-plane case
the bound exists for.

## Drill-in plane (`web/src/drill/`, U8)

Clicking a tile's id opens live detail for that anchor: the bead, the session
working it (with its `?peek` output snapshot), and an activity feed. It reads
the **supervisor's** typed API — not `/helm` — and keeps itself current off the
supervisor's SSE stream. A live terminal is U9.

**It addresses the supervisor same-origin.** Not `127.0.0.1:8372`. helm-svc is
reverse-proxied *by* the supervisor, so the app and the API already share an
origin, and two things make that the only workable target: the board is read
over tailscale from machines where `127.0.0.1` is the *reader's* host, and the
app is served under `connect-src 'self'` (`web/handler.go`), which refuses
cross-origin requests before they leave the page. The one value discovered at
runtime is the city name, parsed from the mount path by `src/drill/origin.ts`.
`npm run dev` proxies `/v0` to the loopback supervisor so the same code path
works there, taking its city from `HELM_DEV_MOUNT`.

**It never states an incomplete read as a complete one.** The board aggregates
across every rig, and a rig store that does not answer is normal: the supervisor
returns 200 with `partial: true` and a reason per store. Every list read here
therefore carries that envelope (`ListResult` in `src/drill/client.ts`), a read
that failed outright is expressed as the maximally partial one, and counts come
from the supervisor's `total` rather than the page it returned. Under a partial
read the panel says it could not tell whether an agent is working the anchor —
never "no agent is working this anchor" — and the signals strip states floors
("at least 3") with the stores' own reasons beside them.

**Its event stream resumes where it left off.** A dropped stream is reconnected
with capped backoff to a URL carrying `after_seq=<highest seq delivered>`. The
browser resends `Last-Event-ID` only for its own reconnect of the same
`EventSource` object, so a replacement built from the bare URL would start at the
current city head and silently lose the outage — and since the panel refetches
only on a delivered event, it would then show stale state under a "live"
indicator. Where no cursor exists yet (the drop preceded the first event), the
hooks refetch on the way back to `open` instead.

**Its types are generated, not hand-written.** The supervisor API is in the
OpenAPI spec, so `src/drill/gen/supervisor.d.ts` is generated from it — pruned
to the eight operations this plane calls, because the full spec generates ~23k
lines for a spec owned by another repo (the gascity rig). Regenerate after any
supervisor API change, and commit the result:

```bash
cd services/helm/web
npm run gen:supervisor-types                 # from the live supervisor's /openapi.json
npm run gen:supervisor-types -- --spec <file>  # or from a copy of the spec, offline
npm run gen:supervisor-types -- --check      # fails if the committed types are stale
npm test                                     # vitest; no city needed
```

Adding an endpoint means adding it to `OPERATIONS` in
`scripts/gen-supervisor-types.mjs` and regenerating — `tsc` rejects a call to
any path missing from the generated types, so the two cannot drift apart
silently. The hand-written contract mirror in U7 is for the board JSON only,
which is absent from the supervisor spec; do not hand-write supervisor shapes.

## Build / run / test

```bash
cd services/helm
go test ./...                 # unit tests (model golden cases + mock-supervisor source + server/cache + the embedded app)
go build ./cmd/helm-svc  # or: assets/scripts/gc-helm-build.sh

cd web && npm test            # the app's own tests: ttyd protocol, endpoint check, detach invariant

# Run standalone against the live supervisor (no [[service]] needed):
GC_SERVICE_SOCKET=/tmp/helm.sock \
GC_SERVICE_URL_PREFIX=/v0/city/<city>/svc/helm \
GC_CITY_PATH=$GC_CITY_PATH \
  ./helm-svc &
curl --unix-socket /tmp/helm.sock http://x/helm | jq .

# The CLI view needs only the city root — no socket, no running sidecar:
GC_CITY_PATH=$GC_CITY_PATH ./helm-svc board
GC_CITY_PATH=$GC_CITY_PATH ./helm-svc board --json --limit=0 | jq length
```

Discovery env:

- `GC_HELM_SOURCE` — `beads` | `supervisor`; see *Picking a backend* above.
- `GC_HELM_CITY_PATH` (else `GC_CITY_PATH`, else `GC_CITY`) — the city root the
  beads backend enumerates `.beads` and `rigs/*/.beads` under. Required by
  `helm-svc board`, which has no HTTP fallback by design.
- `GC_HELM_GC_BIN` — override the `gc` binary the liveness/ownership reads shell
  out to (otherwise `gc` on `PATH`).
- `GC_HELM_SUPERVISOR_URL` (else supervisor.toml port, default `127.0.0.1:8372`)
  and `GC_HELM_CITY` (else parsed from `GC_SERVICE_URL_PREFIX`, else the
  `GC_CITY_PATH` basename) — the HTTP backend's target.
- `GC_HELM_CACHE_TTL` — seconds or a Go duration; default 45s.
- `GC_HELM_SITTINGS_WINDOW` — a Go duration; default 24h. How far back a CLOSED
  converse sitting stays on the board; `0` leaves only the running ones. See
  *Converse sittings* above.
- `GC_HELM_PROBE_TIMEOUT` — seconds or a Go duration; default 10s. Bounds the
  startup open described under *Picking a backend*. The socket is not created
  until the backend is chosen, so an unbounded probe would turn a wedged Dolt
  into a service that never starts. Zero and negative values fall back to the
  default: a zero deadline would fail every probe and pin the service to the
  HTTP backend for good.

The standalone invocation above reaches the supervisor over HTTP; to run it on
the library backend instead, pass `GC_CITY_PATH` (the supervisor already injects
it under a real service mount) and leave `GC_HELM_SOURCE` unset.

## What's proven vs. deferred

**Proven** (the `tk-sy3vj` spike): the spine works end-to-end against the live
city — auto-buildable launcher, unix-socket serving, `/healthz`, a real cross-rig
ranked board, instant crash-restart, TTL cache, contract-compliant data access,
unit tests over the model and a mock supervisor.

**Delivered since** (tk-x89rn, the source-seam widening):

- **`stale_days`** and the NORMAL→ELEVATED stale bump are real under
  `BeadsSource`. `updated_at` rides on the tile alongside it, because
  `stale_days: 0` alone cannot distinguish "touched today" from "the source
  could not read it".
- **`assignee`** is carried on children.
- **metadata** is carried on every anchor and child. tk-x89rn shipped it
  *carried, not spent*, so its consumers could stay separately reviewable.

**Delivered since** (tk-eemvf.1, the U5 scaffold): a mount-prefix-safe Vite +
React + TS app embedded in the binary and served at the mount, alongside the
JSON the mount already served. Structure only — see *Web UI*.

**Delivered since** (tk-2v08m, the metadata-keyed anchor kinds): the board
gathers `human` (`gc.routed_to=human`) and `parked` (`gc.takeaway` present)
beads, so an item the operator owns is no longer invisible for the sole reason
that its issue type is `task`. See *Anchor kinds*. This is the first consumer to
spend the metadata tk-x89rn widened the seam to carry. `internal/board` reads it
too: `humanGated` keys the human-gate rules off `gc.routed_to`, and `hasOwnRow`
keys the parked-child split off both markers.

**Delivered since** (tk-eemvf.4, the U9 terminal embed): an xterm.js terminal
attached to the city's existing ttyd, peek at rest and live on focus, with the
same-origin reachability confirmed and detach-not-kill verified — see
*Terminal*.

**Delivered since** (tk-134d7, the CLI view + the completed model port):

- **`helm-svc board`** — a second renderer over this gather and this
  derivation. See *CLI view*.
- **The full rank `weight`** — `m_total + prio_w(priority) + min(xrefs,5)`, with
  the cross-rig-ref description scan restored.
- **The takeaway-driven NEEDS sentence** — an anchor carrying `gc.takeaway`
  spends it as its NEEDS. This is the DATA half of `tk-x55wt`; that bead's
  remaining scope is the web tile's presentation. The sentence is bounded at
  **140 characters**, enforced by `gc-helm.sh takeaway` at write time (a longer
  text is refused, not trimmed — only the author knows which clause is the
  headline) and clipped with an ellipsis by both terminal tables for anything
  stored before that gate existed. `--json` always carries the whole string, in
  `needs` and in `takeaway`. It is a bound on PROSE only: NEEDS never holds an
  identifier, because the mechanical heads are `--json`-only (`tk-9tbbk.1`).
- **A demand with no takeaway says so.** A `human` row with no `gc.takeaway`
  reads "routed to you — no question recorded", and a childless `parked` row
  "parked for you — no question recorded". Both absent and blank count as
  silent: `collapseWS` flattens whitespace-only prose to empty. The phrase is
  the actionable one, because a silent demand means whoever routed or parked
  the row never finished the handoff; a generic "operator action" reads like a
  valid ask and leaves the operator nothing to act on.
- **`stranded`/`empty`/`complete`/`progress_mismatch`** booleans, and `held`.
- **The in-flight / dead-owner join.** A child counts as moving only when its
  owning session is demonstrably live, or a live graph.v2 workflow stands over
  it. This is the false-stranded defect `tk-fkeft` fixed in `gc-helm.sh`, fixed
  here too: a slung bead never leaves `status=open`, so a board reading only
  child status called a polecat mid-implementation "stranded — assign or visit".
- **owned-convoy partition** — `gc convoy list` supplies `owned` and `progress`,
  and an unowned non-machine convoy is banded HIGH as the orphan exception.
- **The HQ bead store.** `gc rig list` reports the city root itself as a rig
  (`hq: true`); the gather scanned only `rigs/*/.beads` and silently dropped it,
  hiding the city-scope `gc.routed_to=human` beads.

Session liveness and convoy ownership come from the `gc` CLI — see
*Data-access contract*, which that adds a third sanctioned backend to.

**Still deferred** (and *why*):

- **Retiring `gc-helm.sh`.** Its `open`, `react` and `takeaway` verbs have no Go
  equivalent, so the script stays. Retirement is a follow-up once the board view
  is proven at parity in daily use.
- **A CLI cache.** `helm-svc board` re-gathers every run (~2.7-3.3s). The bash
  board's 45s file cache makes a repeat glance ~1.8s. Caching here would buy
  about a second and re-introduce a staleness surface, which is the thing this
  epic exists to reduce — so it is deliberately not done, not merely undone.
- **`tk-b3rga`** (decision tiles) — still open, in the presentation.
- **event-invalidation** — the sidecar's cache is TTL-only; the supervisor SSE
  `/v0/events/stream` can later replace polling.

## Handoff

The `[[service]]` stanza above lives in the **town repo** (`city.toml`), which is
outside this rig PR. Per the spike bead, the city-scoped placement is the
operator/keeper's to apply. Everything in this rig PR (the Go module, launcher,
and tests) is self-contained and proven runnable standalone; adding the stanza
turns on auto-start + the tailscale-reachable mount.
