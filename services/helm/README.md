# helm — Attention Canvas backend spine (spike: tk-sy3vj)

A long-lived Go sidecar that serves the **Helm board**: the operator's web page,
and the JSON documents it draws, read live from each rig's bead store. It is
the backend data + serving plane for the Attention Canvas operator dashboard
(epic `tk-eemvf`).

> **The bash board is gone; the bash verbs are what is left.**
> The board's one view for people is the web page this binary serves, which
> reads one document per rig (see *The rig board*), and
> `helm-svc board --json` prints those documents for agents. `gc-helm.sh` renders
> no board at all: it carries the write and read-only verbs that
> `gc-helm --help` lists, and `gc-helm.sh --json` exits 2 with `unknown verb`.
> Its own usage text points at `helm-svc board`. Retiring the remaining verbs
> is a separate decision recorded under "One board, and its verbs in
> gc-helm.sh" in `docs/human-engagement.md`, under Watch items.

## What it does

Two entry points over ONE rig board. They share its reader,
`internal/rigboard`, so for each rig `helm-svc board --json` prints the
document the sidecar serves the page.

```
helm-svc                    serve — the sidecar (below), whose web page is the
                                    board's one view for people. Bare
                                    invocation, which is how the supervisor
                                    spawns it.
helm-svc board --json       print — each rig's board document as JSON, for
                                    agents and tooling. See *The JSON read*.
helm-svc form --helm <gc-helm.sh>
                            run — the terminal conversation form that
                                    gc-helm.sh engage and attach open, which
                                    a bare gc-helm.sh opens as engage. See
                                    *The conversation form*.
```

As the sidecar:

```
GET /healthz            -> { "status":"ok" }   (liveness probe)
GET /                   -> the embedded web app — see *Web UI*
GET /assets/...         -> the web app's bundle
GET /helm/rigs          -> { read_at, rigs:[ <name>, ... ] }   see *The rig board*
GET /helm/rigs/{rig}    -> { read_at, board }   one rig's document
GET /helm/city          -> { read_at, city }    see *The city page*

POST /helm/open     -> { bead, outcome, conversation?, message }   file a conversation
                       about a bead in the operator's queue
POST /helm/engage   -> { bead, verb, message }   spawn a Discuss sitting on the bead's
                       conversation
                    — the write routes; see *Actuating from the board*
```

### The JSON read (`helm-svc board --json`)

```
helm-svc board --json                    # every rig's document
helm-svc board --json --rig=gc-toolkit   # one rig's
helm-svc board --json --timeout=300      # bound the whole read (default 120 s)
```

It prints the rig board for agents and tooling: for each rig the city lists,
the document the web page draws for it, from the reader behind
`GET <mount>/helm/rigs/{rig}` (`rigboard.Read`, see *The rig board*), so an
agent and the page read one answer. It has no terminal view: a call without
`--json` exits `2` and names the web page.

The answer is one object, `{read_at, rigs: [...]}`. `read_at` is when the read
ended, and `rigs` holds one entry per rig, in the order `gc rig list` names
them: `{rig, board}`, the rig's document, or `{rig, error}`, the reason its
read failed, so a rig that could not be read is never printed as a board with
nothing on it. Exit codes: `0` when every rig was read, `2` for a usage error,
including a call without `--json` and a `--rig` the city does not list, and `3`
when a read failed. A failed rig list prints nothing, and a failed rig's read
still prints the answer, which names that rig with its error.

It reads each rig's store **itself and uncached**, through gctk's listing, one
rig after another under the one `--timeout`: it does not depend on the sidecar
being up, so a build from a working tree reads the live city through that
tree's reader. Measured on the operator's city (7 rigs, 1,693 rows) at a load
of 20 to 37, it read every rig in 13 s.

Same binary as the sidecar on purpose: a separately built one would be a second
artifact that can go stale on its own. Full rationale in
`cmd/helm-svc/board.go`.

### The conversation form (`helm-svc form`)

```
helm-svc form --helm <gc-helm.sh> --models claude-opus,claude-fable,codex-astra,codex-sol [--subject <ref> [--from <bead>] | --new-subject [--rig <name>] [--question <text>]] [--model <variant>] [--no-attach]
helm-svc form --helm <gc-helm.sh> --return     # the conversations to return to
```

The screen `gc-helm.sh engage`, which a bare `gc-helm.sh` on a terminal runs,
and `gc-helm.sh attach` hand a terminal to, which they run with their own path
as `--helm` and the converse variants as `--models`. Its pages are tabs at its
top: starting a conversation (Ctrl+N), returning to one (Ctrl+R), and People
(Ctrl+P). Each tab shows its key, which goes to that page from any page and
field, and the key of the page on screen does nothing. ↑ from the subject
reaches the tabs, ←/→ move along them, and on a list page ←/→ move along them
at once. The page for starting a conversation holds the subject, a multiline
question, the model, shown with each word of its name capitalized (claude-opus
reads Claude-Opus) and passed on as named, and whether to attach, in that
order. The subject is a bead, a PR, or
a rig's whole name or prefix typed there, which starts a new topic in that rig,
and a line under it shows the rig it names or the bead's own rig. `--rig` fills
in the subject with the name of the rig it names exactly, and `--subject` with
a reference the form looks up and never matches to a rig. ↑ and ↓ move between
the fields at a field's first and last row. It reads `gc-helm.sh conversations`
in the background while the operator types, the city's rigs with their
prefixes included, saves with `gc-helm.sh open`, starts with
`gc-helm.sh engage <conversation> --no-attach`, and once the sitting has
started attaches with `gc-helm.sh engage <conversation>`, passing `--model` with
the model its start ran on. `--no-attach`, which engage passes on from its own
command line, opens the form with attaching off, and the form then leaves once
the sitting has started. In a suspended rig attaching is off whatever the
operator chose, and the form saves the question, starts no sitting and leaves.
`--from`, which engage passes on too, names the bead a `--subject` gate was
reached from. The People page lists the `seats` that `gc-helm.sh conversations
--json` gives, mechanik and each rig's po, each with its session's state as
Gas City's session list gives it, and reads them again every ten seconds while
it is on screen. Enter leaves the terminal to `gc-helm.sh mechanik` or
`gc-helm.sh po --rig <rig>`, each of which hands it to the seat's session, and
a seat takes no question. It writes nothing itself, so what it files is what the
command line files. [human-engagement.md](../../docs/human-engagement.md#engage)
says what it shows and when it saves. `internal/form/testdata/helm-fixture.sh`
answers those verbs from fixture data, so the form can be run with no city
behind it.

## Architecture

The packages, with clean dependency lines `rigboard <- server <- cmd` and
`cityboard <- source`:

| Package | Responsibility |
|---|---|
| `internal/source` | Gas City's own interfaces as the pages read them: the `gc` command, through which the rig board reads each rig's store and the service finds its city, and the supervisor's event log, which the city page reads. |
| `internal/server` | HTTP routes + a server-side TTL cache of each rig's board document and of the city's. |
| `internal/rigboard` | The rig board's read: one gctk listing of a rig's store, the pack's shared readers asked of its rows, and the one table that names each row's group and signal. See *The rig board*, below. |
| `internal/cityboard` | The city page's read: doctor's newest run from the city's event log, and which of its checks the page shows and counts. See *The city page*, below. |
| `internal/verbs` | Runs a `gc-helm.sh` write verb for the server's POST routes, under a deadline that kills the run's whole process group. It owns no verb logic. |
| `internal/form` | The terminal conversation form, `helm-svc form`. See *The conversation form*, above. |
| `internal/fixture` | The board on fixture data, for `cmd/helm-fixture`. See *The board on fixture data*, below. |
| `web` | The operator's web app (Vite + React + TS) and the `go:embed` that compiles its built bundle into the binary. |
| `cmd/helm-svc` | Entrypoint: listen on the `GC_SERVICE_SOCKET` unix socket, wire the reads and the write routes into the server, graceful SIGTERM. |

## Wiring it as a workspace-service

The service is a `proxy_process`: the supervisor spawns the launcher, hands it a
unix socket in `GC_SERVICE_SOCKET`, and reverse-proxies
`/v0/city/<city>/svc/helm/helm/rigs` → `GET /helm/rigs` (path-stripped).

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
curl http://127.0.0.1:8372/v0/city/<city>/svc/helm/helm/rigs   # the city's rigs
open http://127.0.0.1:8372/v0/city/<city>/svc/helm/            # the web app
# and through the same tailscale origin the gc dashboard uses (:8372).
```

### Building

The build does **not** run in the service start path, and this is load-bearing.

The supervisor gives a `proxy_process` **5 seconds** to answer its health probe
(`proxyProcessReadyTimeout`, gascity `internal/workspacesvc/proxy_process.go`).
A cold build of helm-svc takes longer: 5 to 6s at loads of 14 to 20, and a
warm one under a second. A cold build started by the launcher loses that race,
and `waitReady` then calls `stopProcessGroup()`, killing the build along with
the start.

Killed starts are visible on disk: on 2026-08-22 this service's `bin/` held
**2,677** zero-byte `.helm-svc.build.XXXXXX` staging files laid down over three
days, one per killed start, each a `mktemp` that never reached its `mv`.

So the two jobs are separate:

| | script | when |
|---|---|---|
| build | `assets/scripts/gc-build.sh helm` | the `helm-build` order, while a build or a restart is owed |
| start | `assets/scripts/gc-helm-svc.sh` | the supervisor, on demand |

`gc-build.sh` is the pack's one out-of-band builder. The `gctk-build` order runs
it as `gc-build.sh gctk`, which builds the merge cadence's binary the same way,
without the restart described below.

Both orders are condition orders. On each pass the order dispatcher runs
`gc-build.sh <component> --due`, which reads the checkout and the record. For
helm it reads them under the state root the city's service listing reports,
the root the deploy publishes to and the service is served from. The order runs
only when the check answers that a run is owed and due. A run is owed while the binary is missing or was built from a revision
other than the checkout's, and for helm while a publish waits for its restart.
It is due on the first pass after the checkout moves, and otherwise five
minutes after the last run, so a build or a restart that failed is tried again
every five minutes until it succeeds. The script's check states the rule.

`gc-build.sh helm` rebuilds when a source is newer than the binary, an
ordinary `find -newer` dependency, the same question `make` asks. It also
rebuilds when the build-status record names a revision other than the one the
run sees, since deleting a file makes nothing newer. It publishes by atomic
rename so a failed link can never truncate a serving binary, and in `--deploy`
mode restarts the service onto what it published. Build and restart are one
step on purpose: a new binary that nothing restarts onto is the other half of
the defect. On 2026-08-22 the helm process had been up 14h55m on a
binary built at 02:40 while three commits touching `services/helm` had landed
after it, all three inert in the served board.

**A publish that was never restarted onto is remembered.** Publishing marks
`<state_root>/restart-pending`, and only a restart that returns success clears
it; the next `--deploy` run restarts even though the binary is by then current.
Without that record the same inert state returns by a different road: a restart
that fails once leaves a binary built from the checkout's revision, so nothing
is ever stale again, the order's check owes no run, and the old process serves
the old inode until a commit moves its sources. The same record is what carries
a hand-run build (below) to the service.

To build by hand — after editing Go sources or rebuilding `web/dist` — run:

```bash
assets/scripts/gc-build.sh helm            # build iff stale
gc service restart helm                    # serve it now, rather than waiting
```

The `gc service restart` there is only to see it immediately — the build records
the publish either way, so the `helm-build` order restarts onto it five minutes
after the build. A restart run by hand does not clear that record (only the
build's own restart does), so it costs that one redundant restart;
`rm <state_root>/restart-pending` skips it. Recognising a hand restart
would mean probing whether the running process is on the new inode, which is
exactly the bespoke liveness machinery this split exists to avoid.

If the binary is missing entirely the launcher exits non-zero with a message
naming the builder, and the service sits `degraded` until the order builds one.
It deliberately does not build its way out: it has 5 seconds.

## Web UI

`web/` is a Vite + React + TypeScript app, the operator's board, embedded in the
binary and served at the service mount. It is one page per rig, with the rig in
the address (`?rig=<name>`); with no rig there, it lists the city's rigs from
`GET <mount>/helm/rigs` as links. Nothing rolls up across rigs. Beside the rig
pages, `?city` is the city's page (see *The city page*), and the bar of the rig
list and of each rig page links to it.

**What it reads.** One rig's document, `GET <mount>/helm/rigs/{rig}` (see *The
rig board*), which it lays out as four pages: Epics, Needs you, Work queue and
Unprioritized. The document decides every group, signal, count, need and
order; the page lays it out, folds it and filters it, and derives no state of
its own. Its types are `src/rigboard/document.gen.ts`, generated from the Go
types. It reads the document again every half minute, whenever the tab is shown
again, and after a write it sends. A read that fails keeps the last good
document on screen, with the time it was read and the failure beside it, and a
failed read with no document before it shows the failure alone, never an empty
list.

**How it draws.** Two views make up the pages. Needs you is one entry per need
(a question, a decision, a conversation, a pull request waiting on the
operator's review, work assigned to them, a ruling), with every bead the need
holds beneath it in the Work queue's order. Each Needs you view leads with how
many of its needs count, and beneath that how many of each kind count: pull
requests, questions, conversations waiting for you, in conversation and
rulings, a zero among them, then assigned to you when one counts. A kind's count
shows that kind alone, and a second click shows every kind again. The needs
that do not count, those about parked work or work held for the Product Owner,
fold beneath the rest under Parked or unprioritized, closed until opened. The
Work queue is the work in the
order it is expected to land, with the ready work nothing sends anywhere
after it, folded under Not scheduled. Work that waits on other work stays in
the queue, and its row names what it waits on. Work that carries hold:mayor
waits for the Product Owner: the Unprioritized page lists it, and neither view
lists it or counts it.
The Epics page shows both for each epic and each
Delivery, over the work each holds nearest, with its closed work folded beneath,
and each line leads with how many needs hold it. The Needs you and Work queue
pages show the same views across the rig. Every object, from an epic to a gate,
is drawn with one row structure (`src/rigboard/Line.tsx`), whose look follows
the operator's Claude Design export, and an object looks the same wherever it
appears: on every page a need is tinted and tagged with its kind, and its line 3
says how many beads it holds up and, for a pull request, what holds it. A page
decides only what nests under a row: a need on a Needs you view nests the beads
it holds there, and nothing else nests. Details opens in place under a row: the
bead's whole description, formatted, which the page reads from the supervisor
when Details opens (see *The page's supervisor read*), an epic's contract and
last ruling, the pull request's facts with its link, what the bead waits on and
what waits on it. Search runs over the loaded document. A bead id copies on a
click, and a referenced id's "show" fills search with it.

**What it writes.** Start the conversation and Rejoin the conversation call the
engage route, and the side panel, where the export draws its terminal, shows the
route's answer and the command that attaches to the sitting, with a control
that copies it. Discuss, in every row's Details, opens the open route's form
(`src/open/`). See *Actuating from the board*.

**Its fonts are bundled.** IBM Plex Sans and IBM Plex Mono come from the
`@fontsource` packages (`src/fonts.css`) and are served from the page's own
origin, the only origin `web/handler.go`'s content policy admits for a font.
The build writes each package's licence beside the page, as
`dist/fonts/IBM-Plex-Sans-LICENSE.txt` and `dist/fonts/IBM-Plex-Mono-LICENSE.txt`.

Each of the following is load-bearing.

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

**The bare mount is the app's.** A workspace-service gets exactly one mount, so
the app answers at it, whatever the request asks for, and the JSON routes answer
beneath it under `/helm/`.

To run the page against a live city while editing it:

```bash
npm run dev        # http://127.0.0.1:5175/?rig=<rig>, proxying its reads to the city GC_CITY names
HELM_DEV_MOUNT=http://127.0.0.1:8372/v0/city/<city>/svc/helm npm run dev
```

`HELM_DEV_MOUNT` must resolve to loopback — the supervisor binds loopback only
and the dev proxy refuses to send traffic off-host.

## Terminal

The page mounts no terminal. Start the conversation and Rejoin the conversation
spawn the sitting through the engage route, which runs `gc-helm.sh engage` with
`--no-attach`, and the side panel shows the command the answer names to attach
to it, with a control that copies it. The operator runs that command in a
terminal of their own.

## The rig board (`GET <mount>/helm/rigs/{rig}`)

`GET <mount>/helm/rigs` lists the city's rigs, and `GET <mount>/helm/rigs/{rig}`
answers one rig's board: a document holding every row the four pages draw, once
each, and the Epics, Needs you, Work queue and Unprioritized pages as lists of
those rows' ids. Each epic and Delivery on the Epics page carries its own Needs
you, its own Work queue and its closed work, over the rows it holds nearest, and
the Needs you and Work queue pages carry the same two views across the rig. Its
read time sits beside it (`read_at`), not in it.

**What it reads.** One read of the rig's store through gctk's listing
(`services/gctk/listing`), a ledger pass, never the beads library: one
`gc bd list` of every live bead, gates, wisps, infrastructure beads and
templates among them, one `gc bd list --parent <epic> --all` per open epic and
Delivery for its closed members, and each bead the readers need beyond those,
such as a closed bead a wait names, read once. A closed epic among those
members, such as a Delivery that landed while its epic stays open, gets the
same read for its own closed members. A member is kept only when its own
parent-child edge names the parent. Closed work beneath a bead that is not an
epic is not read, since that would take one call per parent. While the rig has
an open decision, one `gc bd list --has-metadata-key gc.handback --all` reads
every bead that records a hand-back, the closed conversations of sittings that
ended at their hand-off among them, for the newest a decision's Details opens
with. It reads every hand-back the store holds, so its cost grows with the
sittings the rig has had. Every reader is asked of the listing's rows, so one
document never mixes two reads of a bead:

| Reader | What the read takes from it |
|---|---|
| `services/gctk/listing` | each bead's fields and the keys the page shows, decoded through the listing's declarations; whether a bead is a run's root or a step poured under one (`waits.IsRootOrStep`), a person's to clear (`prstatus.IsPersonBlocker`), or a row of the store's ephemeral plane; every bead that records a hand-back (`Listing.HandedBack`) |
| `services/gctk/waits` (`Listing.Holds`) | what holds each bead, the waits behind it, whether it is in flight, its arm |
| `services/gctk/prstatus` (`Holding` over `Listing.Blockers`, and `Stays`) | what a person owes on a bead through its `blocks` edges, and whether a conversation or a decision waits on work of its own first, which is no person's move until that work closes |
| `services/gctk/prstatus` (`Read` over the listing, `Derive`, `Held`, `Reasons`) | each open pull request's facts, and where one on the old record stands and what holds it |
| `services/gctk/pr` (`FromStore` through `Listing.PRAnswers`), rendered by `prstatus` (`Render`, `RenderHeld`, `RenderReasons`) | where a pull request on Gas Town's pending record stands and what holds it: the evaluator's answer over the listing's rows and the GitHub read the landing order saved on the PR's bead, as `gctk pr status` gives it, so the board reads no GitHub. A pull request whose answer did not read, because a read of the store failed, reads unread |
| `services/gctk/conversation` | what a conversation is, what it tracks and replies to, so a decision it tracks and a gate it replies to read its state |
| `services/gctk/queue` (`Order` over the listing) | the order the rig's open work is expected to land in, which `queue` reads from the listing's rows, waits' answers, the store's ready set and the live runs, and which of it is the ready work nothing sends anywhere |

The listing reads the store's ephemeral plane and its templates because waits
reads every run, and a row is a bead bd's own listing shows: the board leaves
out a wisp, a row stored with no history, such as an order run's tracking bead,
and a template molecule. `internal/rigboard/table.go` is the one table that
turns the readers' answers into a row's group and signal, first match wins,
and the only place those words are chosen. The read adds no rule about what
holds a bead, whose move it is or whether work is moving. The blocked status
Gas Town's pending record writes on a bead whose pull request it holds is the
record's own and holds nothing, so such a pull request reads "Pull request
#n" with where it stands, in the Work queue.
`specs/tk-yhquh93.2/gas-city-search.md` says why it reads through `gc bd list`
rather than the supervisor's bead routes.

**How it orders work.** The read asks `services/gctk/queue` once for the
order of the rig's open work, naming the work and handing over the listing, and
every Work queue view lists its rows in that one order. Nothing sits above what
it waits on: bd graph's execution layers put what can go now first, and each
layer goes in the order the pool claims ready work,
priority, then oldest, then id. The ready work nothing sends anywhere comes
after the queue, under Not scheduled: each piece the store's ready set serves
that no hold, route, assignee, arm or live run sends, among them a placed piece
whose run ended with it open. A piece counts as worked only while a live run
works it, by waits' run link, so no stamp a pour or a run left on its row
stands for one. Work that waits on other work stays in the queue behind what
it waits on. Work held hold:external reads "Waits outside the city". Work held
for the Product Owner reads "Waits for the Product Owner": it is placed with
the rest, and then no view lists it. A need sorts by the first bead it holds in
that order, or by its own place when it is work itself, so the top need holds
up the front of the queue. `specs/tk-yhquh93.13/gas-city-search.md` cites the rules the
order composes, and `specs/tk-yhquh93.13/board-views.md` records the board's
two views.

**What it counts.** Every Needs you view, the rig's and each epic's and
Delivery's, lists each need it covers once, counts the needs that count, and
counts them by kind (`NeedsYou` in `internal/rigboard/document.go`), so a count
reaches zero only when nothing that counts needs the operator. A need does not
count when what it is about is parked or waits for the Product Owner. It is
parked itself when it, or an epic or Delivery above it, waits on a park, which
the read tells as a wait on a gate that is no human gate, the wait the table
reads as "Held by a gate" (`gateHold`). A gate, a decision or a conversation
does not count when every bead it holds or is about is parked, is a need that
does not count, or carries hold:mayor. A pull request or other work that is
itself a need counts unless it is parked itself, and a need about nothing else
counts. A question a sitting
is talking over counts as in conversation. An epic's or a Delivery's needs
count on its line counts the needs that count too.
`specs/tk-yhquh93.14/needs-you-count.md` records the rule and the calls it
settled, and `specs/tk-yhquh93.14/gas-city-search.md` the search behind it.

**How it is cached.** The document depends on the store's answers alone, so it
is cached whole per rig, the work's order with it, since the order is a function
of the rig's one read. The cache keeps the board's rule: a minute's time to
live (`server.RigBoardTTL`, from a measured 2.9 s read of gc-toolkit), one
gather of a rig at a time however many requests wait on it, and every rig
dropped when a write route succeeds. The drop also lets the next request gather
at once, beside a gather that began before the write, and that gather's answer
stays out of the cache. A gather has thirty seconds. When they run out, the read
stops every store call it made, with the processes each call started, `bd`
among them, and only then does the request answer its failure, so polls that
come while the store hangs do not pile up reads on it. A failed read answers
502 with the failure, never a document, so the page keeps its last good
document and says the read failed.

**The page's types are generated.** `web/src/rigboard/document.gen.ts` comes
from `internal/rigboard/document.go` and `table.go`, through tygo, and nobody
writes it by hand. `TestPageTypesAreCurrent` fails when it is stale:

```bash
cd services/helm
go test ./internal/rigboard -run TestPageTypesAreCurrent -update   # writes it again
```

**Real data for tests and demos.** `internal/rigboard/testdata/gc-toolkit.fixture.json`
is real gc-toolkit beads, the epics `fixtureEpics` names and their graph, cut
from the store by the read's own gather and scanned for other rigs, host paths,
emails and accounts; its `about` block says what was cut and replaced.
`TestFixtureBoard` builds the document from it through the read itself, gctk's
listing over the pack's stub store (`assets/scripts/holds-store.stub.sh`), and
holds it to `internal/rigboard/testdata/gc-toolkit.board.json`. Cut it again
from a city with
`RIGBOARD_CUT_CITY=<city root> go test ./internal/rigboard -run TestCutFixture`,
then write the golden with `go test ./internal/rigboard -run TestFixtureBoard -update`.

## The city page (`GET <mount>/helm/city`)

The city's page shows what doctor found in its newest recorded run
(`specs/tk-1tfzr71.158/design.md`, section 5). `web/src/cityboard/` draws it at
the address `?city`, with the board's one row structure (`Line`).

**What it reads.** The newest `gc-toolkit.doctor.ran` event in the city's event
log, which the doctor order records each hour (`gctk doctor run`), read from the
supervisor's `GET /v0/city/{city}/events?type=gc-toolkit.doctor.ran&limit=1`
(`source.EventLog`). The route answers the newest match first, and the read names
no window, so a doctor that has stopped still shows its last run. Its payload is
gctk's `doctor.Record`, which `internal/cityboard` decodes.
`specs/tk-1tfzr71.178/gas-city-search.md` says why the page reads the event log
and what Gas City's own dashboard shows of it.

**What it shows.** `internal/cityboard` decides it, and the page lays it out:

- when doctor last ran, and whether that run completed. A run that started more
  than two hours before the read is late, twice the order's cadence. It is the
  one lateness rule the board holds, because doctor cannot report that it
  stopped;
- each failing check that two runs in a row measured failing and the operator
  has not accepted, with the time it first failed and its runs in a row. A
  rig's instance of a per-rig check, `rig:<rig>:<check>`, is a row of its own.
  The streak counts only the runs that measured the check, so a run that did not
  complete or did not measure it adds nothing. A check that showed failing and
  that the run could not measure stays, counted, with why, until a run measures
  it ok or the operator accepts it;
- each other check the run did not measure, as not measured;
- the checks `doctor/accepted.toml` accepts, folded under their count, each with
  its reason and ruling;
- each monitor order's last good run, as the run recorded it. Whether a monitor
  is late or failing is Gas City's verdict, in its order checks, which reach the
  page as checks, so the page holds no rule for it.

The page leads with the count of the failing checks it shows, which reaches zero
when no check has failed two runs in a row. The words beside the count say so,
and name how many accepted checks and checks not measured it leaves out. With no
run in the log, or none that measured the checks, it shows no count and says why.

**How it is cached.** The document is cached whole for five minutes
(`server.CityPageTTL`), with one read at a time, since the newest run changes
once an hour. The board's write routes change no doctor run, so a write leaves
it cached. A failed read, or a newest event that holds no run's record, answers
502 with the failure, and the page keeps the last good document and says the
read failed. The page reads it every two and a half minutes, and whenever the
tab is shown again.

**Its types are generated.** `web/src/cityboard/document.gen.ts` comes from
`internal/cityboard/document.go`, through tygo, and `TestPageTypesAreCurrent`
fails when it is stale. `internal/cityboard/testdata/doctor.ran.json` is a live
city's newest doctor event, with its store and a rig renamed, and
`TestTheLiveRunsPage` holds the document built from it to
`internal/cityboard/testdata/city.json`, which the page's tests read and
helm-fixture serves:

```bash
cd services/helm
go test ./internal/cityboard -run 'TestPageTypesAreCurrent|TestTheLiveRunsPage' -update   # writes both again
```

## Actuating from the board (`POST <mount>/helm/{open,engage}`)

The board's write routes — the only writes this service serves; everything else
is a read. Each shells out to the matching `gc-helm.sh` verb:

- **open** files a conversation about a bead in the operator's queue, where it
  waits on the board until the operator engages it (tk-yc00g).
- **engage** spawns a Discuss sitting bound to the bead's conversation
  (`--no-input --no-attach`). Its message also names each open human gate that
  holds the bead and how to engage it, since that sitting answers none of them.

Where they surface: **Start the conversation** and **Rejoin the conversation**
call engage, on a question and on a conversation, and **Discuss**, in every
row's Details, opens open's form for the bead. Each verb is also a
`gc-helm.sh <verb>` a person or an agent can run by hand.

**They own no verb logic.** Each verb lives once, in `gc-helm.sh`, and these
routes *shell out to it* exactly as `assets/scripts/operator-intake.sh` does —
so subject resolution, open's join of a conversation already in the queue and
rig resolution are inherited, not reimplemented. `gc-helm-open.test.sh` and
`gc-helm-engage.test.sh` guard those single copies; a Go reimplementation would
be an unguarded second one. A successful write drops the rig board's cached
answers, so the next read shows what it changed.

```bash
curl -X POST http://127.0.0.1:8372/v0/city/<city>/svc/helm/helm/open \
  -H 'Content-Type: application/json' -H 'X-GC-Request: true' -d '{"bead":"tk-abc12"}'
```

**What open and engage do not do: attach.** In tmux, `open` reattaches the
caller and `engage` attaches the spawned sitting. The page mounts no terminal,
so the web `open` *files* the conversation and the web `engage` *spawns* the
sitting with `--no-attach`. The page says that neither attached you, and shows
the attach command engage's answer names.

### What the operator is told

`gc-helm.sh`'s exit codes are its contract, and the handler maps each to its own
status and a stable `reason` slug. The tool's own stderr sentence is passed
through **verbatim** as `error` — each verb already writes a different, specific
sentence per failure (wrong id prefix vs. no ledger answers vs. data plane down
vs. a usage error), and re-deriving that here would be a second copy of the
script's knowledge.

| exit | HTTP | `reason` | meaning |
|---|---|---|---|
| 0 | 200 | — | open: `outcome` is `filed`/`existing`; engage carries the tool's sentence in `message` |
| 1 | 422 | `verb_failed` | the verb ran and could not act on the request's bead |
| 2 | 500 (open) / 422 (engage) | `usage` / `verb_failed` | open: a wiring bug (the id is pre-validated). engage: a usage refusal, with the script's sentence |
| 3 | 503 | `environment` | missing dependency, rigs unenumerable or no city root |
| 4 | 422 | `verb_failed` | bead not found / unverifiable / filing failed |
| — | 504 | `timeout` | the tool did not finish; the action may or may not have gone through — check the bead |
| — | 503 | `unavailable` | no write tool resolved, or it could not be run |

Refused before the subprocess runs: `invalid_bead` (400), `forbidden` (403),
`busy` (409 — one in-flight run per bead).

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
board's reads. **This route does not widen it**, and adds no login or token: the
service has no session concept, and inventing one here would be a second,
weaker authentication story beside tailscale's.

What POST adds over GET is not reachability but **CSRF** — the operator's
browser is *on* the tailnet, so any page they visit could otherwise write here
with their network position. So the handler requires a same-origin write
(`Sec-Fetch-Site`, with `Origin` as the fallback tell for a browser-shaped
request), and validates the bead id against the id syntax **before** it becomes
an argv element — an id beginning with `-` would otherwise be read by a verb's
flag loop as a flag. Whether the bead *exists* stays the script's gate; a second
copy in front of it would only drift.

Concurrent writes on one bead are collapsed in-process (409 `busy`), whichever
verb holds it: the scripts' state checks are read-then-act, so a double-click
could otherwise race one (open filing a second conversation), and so could an
open and an engage on one row. Two different beads never contend.

### Configuration

| env | default | meaning |
|---|---|---|
| `GC_HELM_OPEN_TOOL` | set by `gc-helm-svc.sh` to its sibling `gc-helm.sh` | path to the write tool (name is historical; it serves every verb) |
| `GC_HELM_OPEN_TIMEOUT` | `120s` | bounds one write-verb run (Go duration or bare seconds) |

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

## The page's supervisor read (`web/src/supervisor/`)

The rig's document carries no piece of work's description, so a row's Details
reads that one bead from the **supervisor's** typed API when it opens:
`GET /v0/city/{city}/bead/{id}`, which answers a bead of any rig in the city.

**It addresses the supervisor same-origin.** Not `127.0.0.1:8372`. helm-svc is
reverse-proxied *by* the supervisor, so the app and the API already share an
origin, and two things make that the only workable target: the board is read
over tailscale from machines where `127.0.0.1` is the *reader's* host, and the
app is served under `connect-src 'self'` (`web/handler.go`), which refuses
cross-origin requests before they leave the page. The one value discovered at
runtime is the city name, parsed from the mount path by `src/supervisor/origin.ts`.
`npm run dev` proxies `/v0` to the loopback supervisor so the same code path
works there, taking its city from `HELM_DEV_MOUNT`. Served anywhere else, as
`helm-fixture` serves it, the page says it cannot read the description.

**Its types are generated, not hand-written.** The supervisor API is in the
OpenAPI spec, so `src/supervisor/gen/supervisor.d.ts` is generated from it,
pruned to the one operation the page calls, because the full spec generates
~23k lines for a spec owned by another repo (the gascity rig). Regenerate after
any supervisor API change, and commit the result:

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
silently. Do not hand-write supervisor shapes.

## Build / run / test

```bash
cd services/helm
go test ./...                 # unit tests: the rig board and city page reads, the routes and caches, the form, the fixture and the embedded app
go build ./cmd/helm-svc  # or: assets/scripts/gc-build.sh helm

cd web && npm test            # the page's own tests, on the rig read's fixture document

# Run standalone against the live supervisor (no [[service]] needed):
GC_SERVICE_SOCKET=/tmp/helm.sock \
GC_SERVICE_URL_PREFIX=/v0/city/<city>/svc/helm \
GC_CITY_PATH=$GC_CITY_PATH \
  ./helm-svc &
curl --unix-socket /tmp/helm.sock http://x/helm/rigs | jq .

# The JSON read needs only gc and the city root — no socket, no running sidecar:
GC_CITY_PATH=$GC_CITY_PATH ./helm-svc board --json | jq '.rigs[] | {rig, rows: (.board.rows | length)}'
```

Discovery env:

- `GC_HELM_CITY_PATH` (else `GC_CITY_PATH`, else `GC_CITY`) — the city root the
  rig board's reads run gc from. With none of them set, helm-svc asks gc which
  city it resolves (`gc config show --json` → `city_path`) rather than
  reimplementing discovery, so a plain shell that injects none of these reads
  the same city gc would.
- `GC_HELM_GC_BIN` — override the `gc` binary the rig board's reads and city
  discovery shell out to (otherwise `gc` on `PATH`).
- `GC_HELM_SUPERVISOR_URL` (else supervisor.toml port, default `127.0.0.1:8372`)
  and `GC_HELM_CITY` (else parsed from `GC_SERVICE_URL_PREFIX`, else the
  `GC_CITY_PATH` basename) — where the city page reads the supervisor's event
  log.

## The board on fixture data (`helm-fixture`)

`cmd/helm-fixture` serves the app this commit embeds with no city behind it.
`GET /helm/rigs` and `GET /helm/rigs/{rig}` answer one rig's document,
`GET /helm/city` answers the city's document, and `POST /helm/<verb>` answers a
canned answer, so nothing it serves reads or writes a city. It is gc-toolkit's
declared `ui_serve_command`, so a demo capture of the board serves it as its
`--serve` command (`docs/review-demo.md`), and a sitting's live copy of the
board runs it too, each as a copy that `gctk rig serve` runs.

```bash
cd services/helm
PORT=5199 go run ./cmd/helm-fixture        # the gc-toolkit fixture, on 127.0.0.1:5199/?rig=gc-toolkit
go run ./cmd/helm-fixture --addr 127.0.0.1:5199 --rig-board <file> --city <file> --answers <dir>
```

- `--rig-board` is one rig's document, in the shape
  `web/src/rigboard/document.gen.ts` names, which the page reads. The default is
  `internal/rigboard/testdata/gc-toolkit.board.json`, the document the rig read
  builds from the committed gc-toolkit fixture. The rig list names the one rig
  the document names, and both routes give the time the fixture started as the
  read time.
- `--city` is the city's document, in the shape
  `web/src/cityboard/document.gen.ts` names, which the city page reads. The
  default is `internal/cityboard/testdata/city.json`, the document the city's
  read builds from a live city's newest doctor run. Its route gives the time the
  fixture started as the read time.
- `--answers` is a directory of canned write answers. `engage.json` is the 200
  answer to `POST /helm/engage`, in the shape `web/src/actuate/client.ts` reads
  (`web/src/open/client.ts` for `open`). `engage.409.json` answers with status
  409 instead, which the app reads as a refusal. A verb with no answer is refused
  with 503 and reason `unavailable`, as helm-svc refuses a write when it has no
  write tool.
- It listens on loopback only: `--addr`, else `127.0.0.1:$PORT`.

It is a command of its own, not a helm-svc subcommand: helm-svc reads the city
through gc and writes through `gc-helm.sh`, while this command links nothing
that could read or write a city, and `go run` starts it in seconds. Its tests
hold its import graph to the standard library, the app's package and
`internal/fixture`.

## Deferred

- **Retiring `gc-helm.sh`.** Its `open`, `engage` and `dismiss` verbs have no
  Go equivalent, so the script stays. Retiring them is the decision recorded
  under "One board, and its verbs in gc-helm.sh" in `docs/human-engagement.md`.
- **A cache for the JSON read.** `helm-svc board --json` reads each rig it
  prints on every run. A cache would re-introduce a staleness surface, which
  is the thing this epic exists to reduce, so it is deliberately not done.
- **event-invalidation** — the sidecar's cache is TTL-only; the supervisor SSE
  `/v0/events/stream` can later replace polling.

## Handoff

The `[[service]]` stanza above lives in the **town repo** (`city.toml`), which is
outside this rig PR. Per the spike bead, the city-scoped placement is the
operator/keeper's to apply. Everything in this rig PR (the Go module, launcher,
and tests) is self-contained and proven runnable standalone; adding the stanza
turns on auto-start + the tailscale-reachable mount.
