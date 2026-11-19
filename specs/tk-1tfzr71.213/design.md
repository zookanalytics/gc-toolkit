---
name: Design — the board reads only the shared readers, and gc-helm's verbs move into gctk
description: The design record for tk-1tfzr71.213, the design child of initiative tk-1tfzr71.24, read at main 790e32ee5 and Gas City upstream main bfe7a19cc2. It retires the tile board with its own store reader, which ends the ICU helper; has `helm-svc board --json` print the page's document; turns the work queue's "Not scheduled" list into the row of ready work no queue holds; moves gc-helm.sh's steering and record verbs into gctk and leaves its conversation verbs to tk-ssm8qns.15; keeps the takeaway fields until a bead of their own decides them; and runs the build orders only when their source moves. Read it to approve the design at its gate, or to build one of the units it defines.
---

# Design: the board reads only the shared readers, and gc-helm's verbs move into gctk

This is the design record for tk-1tfzr71.213, the design child of the
initiative tk-1tfzr71.24. The pack was read at 790e32ee5, the commit
`integration/tk-1tfzr71.24` was cut from, and every pack line number is at that
commit. Gas City is cited by symbol at upstream main bfe7a19cc2, and at the
city's build 6589a7df45 where the two differ. The initiative's description is
the contract, and its notes, read oldest first, say what changed after it was
filed; section 11 names where each note is answered.

## What the operator approves

Today your web page reads each rig's board from gctk's shared readers (`GET
/helm/rigs/{rig}`), and the city page reads doctor's runs from Gas City's event
log. An older board still runs beside them. `helm-svc board --json` and the
`/helm` route serve its rows, which it derives from each store through an
embedded copy of the beads library: about 9,000 lines of Go and 13,000 lines of
tests, whose rows no agent, script or skill reads. That library is why a fresh
clone needs the ICU helper before it builds. `gc-helm.sh`, 6,357 lines of
shell, carries fifteen verbs, and gctk itself shells out to two of them. The
helm build order runs every five minutes and opens a bead store each time to
probe the library. Approving this design makes these changes.

1. **`helm-svc board --json` prints the page's own document.** For each rig it
   prints what `GET /helm/rigs/{rig}` answers, from the same reader, so an agent
   and the page read one answer, as you asked on 2026-11-11 in conversation
   tk-w2hvygn ("one read, no way to allow it to be inconsistent with other
   logic"). Your ruling of 2026-11-06 in conversation tk-4346ghp kept the
   command as the agents' read, and no agent, script or skill runs it today
   (section 1). Cost: its output changes from tile rows to one document per rig,
   and `--all` and `--limit` go. The alternative retires the command with the
   old board, which departs from that ruling.
2. **The old board retires whole, and the repository builds with no cgo.** Its
   reader, its rows, the `/helm` route, the Accept and Dismiss routes your page
   no longer calls, `helm-svc probe`, the fixture server's old answer and the
   old contract all go. The beads library leaves `go.mod`, so `go build ./...`
   and `go test ./...` pass on a fresh clone with no flags, and the ICU helper,
   its uses and CI's ICU installs go, as you gave the go for on 2026-11-19 in
   conversation tk-ivsp7gg (section 4). Cost: what only the old rows showed is
   shown nowhere: a sitting's session state, the build status of helm and gctk,
   an Accept offer and how long an ask has waited. Your page has shown none of
   them since it moved to the rig board on 2026-11-11. On the page, one label
   changes: "Routed to you" reads "Assigned to you", since a task assigned to
   you is all that still reaches it (section 7).
3. **The work queue's "Not scheduled" list becomes the list of ready work that
   nothing sends anywhere,** the row the liveness census's retirement left to
   this member: every ready bead that no hold, route, assignee, arm or live run
   sends anywhere, by title, on every render (section 2). Cost: work that waits
   on other work leaves that list, since its row already says what it waits on,
   and work held `hold:external` reads as waiting outside the city instead of
   not scheduled.
4. **gc-helm.sh's steering and record verbs become gctk commands, and the script
   goes once tk-ssm8qns.15 moves the conversation verbs.** takeaway, park, place
   and accept move into gctk. react's and priority's callers call what those
   verbs only forward to, `gctk reaction sling` and `queue-priority.sh move`.
   resolve, dismiss and handback join open, engage, conversations, attach and
   the seat verbs, which tk-ssm8qns.15 already moves, because they share those
   verbs' subject and sitting helpers (section 5). Each guard a verb keeps today
   moves with it, among them takeaway's compare-and-swap. Cost: the skills,
   prompts and scripts that call a moved verb change their call, and the
   conversation verbs stay shell until tk-ssm8qns.15, which nothing has sent to
   a pool yet, runs. Your keys, your page's buttons and the terminal form work
   as before.
5. **The takeaway stops being shown, and its fields stay until a bead of their
   own decides them.** No page shows a takeaway once the old board goes. The
   fields keep two jobs: the first reaction's scan reads one as the record that
   a bead had its reaction, and three doctor checks read them. Approving keeps
   them, moves the verb that writes them into gctk unchanged, and leaves their
   retirement or their warrant to tk-1tfzr71.216, filed for your placement
   (section 6). The alternative retires them here: every writer writes notes
   instead, the scan reads the bead's first-reaction run, and the three checks
   change, which about doubles this member's reach into code it otherwise leaves
   alone.
6. **The build orders run only when their source has moved.** helm's and gctk's
   build orders become condition orders: each pass asks `gc-build.sh` whether
   the checkout's source differs from what the binary was built from, and runs
   the build only then (section 8). Gain: no run and no run record on the passes
   where nothing changed, today one every five minutes or so for each, and two
   orders leave the four-per-pass dispatch budget the city's other clock-driven
   orders share. Cost: a cheap check every pass, and a build that fails is tried
   again when the source moves or a person runs the order, where today it is
   tried every five minutes. No Gas City primitive rebuilds a service when its
   source changes. gctk's order is this design's addition to the contract, which
   names only helm's.

The work lands in five units on the integration branch (section 10), and the
old and new answers are compared on the live city before the old board's unit
lands (section 9).

## 1. The agents' read

`helm-svc board` (`services/helm/cmd/helm-svc/board.go`, `runBoard`) gathers
through `source.NewBeadsSource`, the embedded library, and prints a bare JSON
array of `board.Tile`: the operator's owed rows, or with `--all` the city
overview. The `/helm` route (`internal/server/server.go:132`, `handleBoard`)
serves the same rows in an envelope with sittings and pack health, from the
library or from the supervisor API. The page reads neither. It fetches only
`helm/rigs`, `helm/rigs/{rig}` and `helm/city`, and posts only to `helm/open`
and `helm/engage` (`web/src/rigboard/read.ts`, `web/src/open/client.ts`,
`web/src/actuate/client.ts`).

No skill, formula, prompt, order, script or workflow runs `helm-svc board` or
fetches `/helm`. Outside `services/helm`, specs and docs, its name appears only
in `gc-helm.sh`'s header, usage and two refusals, in `gc-helm.test.sh`'s NOBOARD
case and in a comment of `tools/helm-surface-fixture.sh`.

`helm-svc board --json` becomes a thin command over `rigboard.Read`, the reader
behind `GET /helm/rigs/{rig}`. It prints `{read_at, rigs: [...]}` with each
rig's `board` document, or one rig's with `--rig <name>`, and keeps
`--timeout`. A rig whose read fails is named in the answer with its error. The
GitHub-intake effort tk-1tfzr71.149 (PR #1559, open at this reading) adds to
each rig's answer when GitHub was last asked (`rigboard.ReadAsked`, through the
supervisor's API). If it lands first, the command prints that beside each
document, as the page's answer carries it.

What retires with the tile board:

- In `services/helm/internal/source`, everything the page's reads do not use.
  They use the `gc` command runner the rig list uses (`NewGC` in `gccli.go`),
  the city the server resolves at start (`DiscoverCityPath`, which lives in
  `beads.go` and moves beside the runner) and the event-log read the city page
  uses (`events.go`). After tk-1tfzr71.149 they also use its supervisor API
  client (`supervisorapi.go`), which finds the API as the supervisor backend
  does (`discoverBaseURL` and `discoverCity` in `supervisor.go`), so those stay
  too. The rest goes: the library reader (`beads.go`, `facts.go`,
  `startfail.go`), the supervisor backend's bead reads (`supervisor.go`), the
  build-status read (`packhealth.go`), the session read in `gccli.go` and the
  `Source` seam (`source.go`).
- `services/helm/internal/board`, whole.
- In `internal/server`, the `/helm` route with its cache and gather, the bare
  `/` JSON answer, and the `POST /helm/accept` and `POST /helm/dismiss` routes,
  which served the tile page's buttons. `POST /helm/open` and `/helm/engage`
  stay for the page.
- `helm-svc probe` and the backend choice at start (`GC_HELM_SOURCE`).
- `cmd/helm-fixture`'s `--board` answer, and the page's old contract:
  `web/src/contract.ts`, `contract.fixture.ts`, `board.fixture.json` and
  `web/contract_parity_test.go`. The deletion plan gives the parity test to
  tk-1tfzr71.25, but it reflects over `board.Board`, so it cannot outlive that
  type. Unit 2 deletes it and removes its row, which names tk-1tfzr71.25, from
  `tools/deletion-plan.tsv`.
- Outside the service, `assets/scripts/lifecycle.test.sh` reads the machine
  axis's values from `internal/board/derive.go` and holds them to
  `lifecycle.toml`. The values `prstatus` reads (`prstatus.go`) are the copy
  left, so unit 2 points that check at them.

## 2. What the replacement owes

The notes list what "the reader that replaces the embedded store" owes. The rig
board is that reader.

| Need | At main | This design |
|---|---|---|
| Each live merge anchor's PR answer by the one rule over the saved GitHub read | `rigboard.Read` asks `Listing.PRAnswers` for every anchor on the pending record and renders it with `prstatus.Render`, `RenderHeld` and `RenderReasons` (`internal/rigboard/gather.go:206-266`) | Answered. An anchor on the old record reads `prstatus.Derive` until the old merge path's retirement (tk-1tfzr71.70), and one with no open PR is the old review path's (tk-1tfzr71.122). |
| Each blocker's await type | `waits` reads it (`services/gctk/waits/waits.go:60`), and only a human gate or a person's blocker reads "Waiting on you" (`holdingVerdict` and `gateHold` in `internal/rigboard/table.go`) | Answered: no timer or GitHub gate reads as yours. It reads "Held by a gate" under "Not moving", and whether such a gate reads as moving is the page's to decide (tk-yhquh93.7). |
| A sitting for each open conversation | A conversation row carries its status and assignee and reads "In conversation" or "Conversation waits for you" (`table.go:136-146`). No session is read. | Goes. Nothing reads a sitting's session once the old board retires, and a conversation whose sitting died reads "In conversation". The implementation child notes that on tk-yhquh93. |
| An epic's waits with each blocker's status, and a landed Delivery's close time | The rig board reads every wait from the store through `waits`, where the supervisor backend marked an epic's waits unread. No row carries a date. | The waits are answered. The close time goes: nothing on the page dates an ask. |
| The row of ready beads no queue holds | Nothing builds it. The work queue's "Not scheduled" list is close but includes work with open waits and counts `hold:external` as unscheduled (`services/gctk/queue/queue.go:210-216, 323-344`). | Built in unit 3, below. |

Unit 3 gives `queue` one answer for the set the patrols design's section 8
defines (`specs/tk-1tfzr71.158/design.md`): a ready bead, by the store's ready
set, that no dispatch hold, route, assignee, arm or live run sends anywhere,
with a placed bead whose run ended with the bead open among them. A bead held
`hold:external` is named as waiting outside the city. A bead counts as worked
only while a live run works it, read through `waits`' run link, never from a
pour's stamp. `hold:mayor` work stays on the Unprioritized page, the Product
Owner's queue, and the unit checks that the page reads every spelling of the
label there, as the queue's own read does. The page's "Not scheduled" list
reads that answer, and nothing else computes it.

The two Debt entries that name this member retire with unit 2: "The `/helm`
board reads the store itself" in `docs/gctk-architecture.md`, and "The agents'
board still reads the store itself" in `docs/architecture.md`, which this
design widens from the PR rule to the whole reader. The architecture page's
"`gc-helm.sh` still carries the write verbs" goes with whichever of unit 4 and
tk-ssm8qns.15 lands second.

## 3. The supervisor API and the store

The reason the library reader was kept, that the supervisor API returns no
`updated_at`, no longer holds: `beads.Bead` carries `UpdatedAt` (Gas City
`internal/beads/beads.go`, added by 81df5a3ccf, which the city's build
contains). The API's bead still carries no `await_type` and no `closed_at`, and
no route serves gates.

The board needs neither from the API. The rig page reads each store through
`gc bd`, by gctk's store adapter, and gets every field it shows from that
read, await types among them, and the city page reads the supervisor's event
log. Once unit 2 lands, no read the board keeps opens a store directly, so no
warrant is owed.

## 4. A build with no cgo

Only `services/helm/internal/source` imports `github.com/steveyegge/beads`, in
`beads.go`, `facts.go` and `startfail.go`. Its embedded Dolt store brings in
`github.com/dolthub/go-icu-regex` and with it the need for ICU's headers.
Unit 2 deletes those files and tidies `go.mod`, so the beads requirement and
the indirect requirements only it brings leave.

What existed only for that goes in the same unit:

- `assets/scripts/icu4c-cgo.sh`, and its uses: `gc-build.sh`'s `ICU=1` for
  helm, `tools/lint.sh`'s vet, and the `go-macos` job's vet and test step in
  `.github/workflows/tests.yml`.
- CI's installs of ICU: `libicu-dev` in the `go` job and `icu4c` in the
  `go-macos` job's brew line, which keeps `flock`.
- The ICU cases of `assets/scripts/gc-helm-svc.test.sh` and
  `tools/lint.test.sh`, and the build recipes that name the helper in
  `docs/component-model.md`, `docs/review-correctness.md`,
  `docs/review-demo.md` and `services/helm/README.md`.
- `gc-build.sh`'s probe of helm, with its `probe-failed` latch and its
  `unreadable` status, since nothing is left to probe.
- What open branches add or move, if they land first. tk-a5mwcic.3 (PR #1595)
  moves the `go-macos` job's use of the helper into `tools/test.sh`.
  tk-1fsgv13 (PR #1600) adds `govulncheck.yml`, which installs icu4c and uses
  the helper. tk-2astzmg (PR #1601) adds `lint.yml`, which installs
  `libicu-dev`, and the exclusion for `services/helm/internal/source/beads.go`
  in `.golangci.yml`. `git grep -n -i -E 'icu4c|libicu|go-icu-regex'` at the
  unit's head lists every use left.

The unit proves the end state on a fresh clone of its head, with cgo on and
no CGO flags set, as a fresh clone has them: `go build ./...`, `go vet ./...`
and `go test ./...` pass, and `go.mod` names neither
`github.com/steveyegge/beads` nor `github.com/dolthub/go-icu-regex`.

## 5. The verbs

| Verb | Callers at main | Fate | Why |
|---|---|---|---|
| takeaway | gctk's `reaction dispose`, `converse-signoff.sh`, `stand-down.sh`, five skills | gctk command | One guarded update, wait edges, a disarm, run cancels, a nudge and a sling: a composition. gctk stops shelling out to it. |
| park | the Product Owner's prompt, `converse-epic-review` | gctk command | It refuses work in flight, whose merge and close an open park gate would hold, and reuses an open park gate with the same title. |
| place | the Product Owner's prompt, `backlog-refinement`, `work` | gctk command | Six writes in order, from unsetting the route to the sling or the arm. |
| accept | `converse-signoff.sh`, `work` | gctk command, in the reaction domain | The lock, the disarm, the gate's answer with its read-back, the sling, the hold's lift and the recommendation's clear. |
| priority | the Product Owner's prompt, `converse-epic-review` | the callers run `queue-priority.sh move` | The verb finds the bead's store and runs that script, which finds the store itself (`resolve_db`). |
| react | `operator-intake.sh` | the caller runs `gctk reaction sling` | The verb is that one call, with its exit codes renumbered. |
| resolve, dismiss, handback | `operator-intake.sh`; `tmux-dismiss-sitting.sh` (your prefix+X) and `converse-hold`; the converse prompt | tk-ssm8qns.15 | resolve is the subject resolver open and engage use, and dismiss and handback share their sitting and comment helpers, so one port keeps one copy of each. |
| open, engage, conversations, attach, po, mechanik | the page, the form, your keys, skills, and for open gctk's `arm start`, which asks a person through it | tk-ssm8qns.15 | That bead already moves them, with the form's seam. |
| board | none | tk-1tfzr71.25 | The deletion plan gives the stub to that member. |

gctk places each new command by the rules a domain move follows
(`docs/gctk-architecture.md`), and the unit records the Gas City search for
each (section 8 names where to start). A verb's callers move to its
replacement in the same unit that removes the verb. The carried constraints:

- takeaway's release stays one update guarded by `--if-status` and
  `--if-assignee` set to what it read, so a close or a claim that lands after
  the read still stands. `gc-helm.test.sh`'s CAS, RACECLOSE, RACECLAIM, GONE,
  MINE and TOAGENT cases become Go tests that fail when a guard is removed.
- Each moved verb's shell tests become Go tests in the unit that moves it, and
  the shell goes in the same change: `gc-helm-park.test.sh`,
  `gc-helm-place.test.sh`, `gc-helm-accept.test.sh`, the cases of
  `gc-helm.test.sh` for the verbs that leave, and the takeaway and react checks
  of the hand-run `tools/helm-surface-fixture.sh`. `lifecycle.test.sh` holds
  two of `gc-helm.sh`'s copies to `lifecycle.toml`: the headline cap, which
  takeaway and park share, and the detached states, which takeaway reads. In
  gctk the verbs read both from the `lifecycle` package (`TakeawayMax` and
  `DetachedStates`), as `gctk lifecycle` does, so those two checks go.
- Each gctk command pins a store by `--db` or the store gctk's adapter routes
  the bead to, never by `BEADS_DIR`.
- The first reaction's scan keeps reading `gc.takeaway` (decision 5).
- Accept finds its own pour with a listing that includes gate-typed beads. If
  the city's `gc` does not yet carry the end of the bead-by-bead pour
  (gc-3znzo8), the search treats a fenced root, and a root left open with
  `molecule_failed`, as unfinished, as deferred dispatch's start does.
- The warrants whose Covers lines name a moved verb change with it: Priority
  following names the priority verb, and Accept's lock names accept's lock.
- The `BEADS_DIR` pins in the verbs tk-ssm8qns.15 moves travel with them:
  open's, engage's, `conversations_pin`'s, `current_sitting`'s and dismiss's
  explicit-id path. The note tk-ssm8qns.15 gets says to pin by `GC_RIG` or
  `--db` and to read a subject in another rig from that rig's store. accept's
  pin moves with accept in unit 4, under the rule above.

Each unit changes every line its change makes false, in docs, skills, prompts,
refusals and comments, and a `git grep` for the names it retires finds them.
The stale text the notes list is among them. `gccli.go`'s liveness comment and
`services/helm/README.md`'s liveness paragraph go with the old board (unit 2).
The README's opening note, `skills/work`'s line about the board's Accept
button, and `gc-helm.sh`'s header, usage and refusals, which then point at the
web page, go with the verbs (unit 4). The watch item in
`docs/human-engagement.md` changes with each unit that makes part of it false:
its sentence on what `helm-svc board --json` prints in unit 1, its other board
sentences in unit 2, and its verb sentence in unit 4. The largest of the rest
are these. In unit 1, the README's section on the JSON read. In unit 2, its
sections on the readability check, the data-access contract, the two backends,
the build-status record and its PACK rows, the board contract and the Accept
and Dismiss routes, and `docs/component-model.md`'s `helm-fixture` row. In unit
4, `docs/steering.md`, `docs/authority-map.md`, `docs/install.md`'s line on the
write verbs, and the refusals of `queue-priority.sh` and
`doctor/check-po-queue-only` that tell a person to run a moved verb.

## 6. What the pack mints

| Item | At main | Platform object in its place |
|---|---|---|
| Visit beads | Retired by tk-1tfzr71.4 and tk-1tfzr71.46 | The native human gate, which a conversation answers |
| Demand stamps | Retired by tk-1tfzr71.33 | The gate's `blocks` edge |
| Reaction beads | Retired by tk-1tfzr71.17 | The first reaction's run on the bead |
| Park gates | Live, and already platform objects: a plain gate with a `blocks` edge | Themselves. The park verb moves into gctk (section 5). |
| Takeaway fields | Live. Writers: the takeaway verb, and `gctk lifecycle --takeaway` through `pr-facts.sh`, which tk-1tfzr71.21 retires. Readers: the old board, the first reaction's scan, three doctor checks, `bead-context.sh`, one skill, and the liveness recheck, which the patrols' second landing retires. | Kept (decision 5). Once the old board retires, no surface reads them. |
| `build-status.json` | Live. `gc-build.sh` writes it, and the old board's PACK rows read it. | Its only surface reader retires. It stays `gc-build.sh`'s own record of what it built, which the check in section 8 reads. |

The takeaway's own bead, tk-1tfzr71.216, asks whether the fields retire onto
the bead's notes, with another record of a first reaction, or stay with a
warrant.

## 7. The `human` route and the gate rows

Every board read of the route is in the old board, and goes with it:
`humanGated` and `poolRouted` in `internal/board/derive.go`, `deriveState`'s
routed check and `poolRoute` in `state.go`, and the source's routed-to-you query
in `internal/source/beads.go`. So do the three reads that derive a person's hold
from a gate's row: `humanIndex.holds` and `holdsWork`, `humanIndex.parksWork`,
and `beadFacts`' count through `openHumanGate`. The rig board never reads the
route.

The rig board's "Routed to you" ask (`askOf` in `internal/rigboard/table.go`)
fires on the listing's person-blocker flag. Since the dispatch effort cleared
the route, what reaches it is a task whose edges do not read as a conversation
and whose assignee is `human`, or a sitting named for the task
(`conversation.IsCandidate`). Unit 2 names the ask for the task assigned to
you: "Assigned to you", with its test case renamed from "work routed to a
person".

## 8. The build orders

`orders/helm-build.toml` runs `gc-build.sh helm --deploy` on a five-minute
cooldown, and `orders/gctk-build.toml` runs `gc-build.sh gctk --deploy` the same
way. `gc-build.sh` already builds only when the binary is missing or its
source has changed, so most runs build nothing.

Unit 5 gives `gc-build.sh` a mode that only answers whether a build is owed, and
makes each order a condition order whose check is that mode. A build is owed
when the binary is missing, or when the checkout's source revision differs from
the one the binary was built from and from the last revision a build was tried
for, so a failed build is not tried again on every pass. A person runs the order
to try it again sooner. The script stays a script because it builds gctk's own
binary, which gctk cannot hold.

The Gas City search, at upstream bfe7a19cc2:

- An order fires on six triggers: cooldown, cron, condition, event, manual and
  webhook (`internal/orders/triggers.go`, `CheckTriggerWithOptions`). A due
  condition order runs outside the per-pass budget of clock-driven orders,
  `DefaultMaxOrderDispatchesPerTick`, 4 (`internal/config/config.go`;
  `dueConditionCandidate` in `cmd/gc/order_dispatch.go`), and its check runs
  concurrently with the others, at most eight at once, each within its
  `check_timeout`. The city's build does the same.
- No event fires when a ref or a rig's default branch moves: none of the event
  types in `internal/events/events.go` is a git event, and
  `reconcile-rig-checkouts.sh`, which moves this checkout, emits none.
- A service (`internal/config/service.go`, `Service`) has a command and a
  health path but no build step, no source watch and no version. Gas City
  starts it again when its declaration or its published address changes, or
  when it failed to start, and never because its source changed
  (`internal/workspacesvc/manager.go`).
- Upstream's open issue gastownhall/gascity#6141 asks for a longer readiness
  window for a service whose command builds itself first, the pattern a pack
  uses to rebuild a binary its install wiped. That builds a service when it
  starts. Nothing starts a running service again when its source moves, so it
  does not cover the need.

So no primitive rebuilds a service when its source changes. A condition order
whose check reads the source revision is the closest composition. A webhook on
GitHub's push would track the remote ref, not the checkout the build reads. An
event order would need whatever moves the checkout to emit an event of its own
(`gc event emit`), and a checkout moved any other way, such as by hand, would
build nothing.

For the verbs, each unit's search starts here: bd's `deferred` status with its
`defer_until`, and its gates, for park, bd's guarded update for takeaway's
release, `gc sling` and the deferred dispatch arm for place, and `gc sling`'s
launch lock for accept, whose warrant records why its own lock stands.

## 9. The switch

The page's contract tests and fixture captures stay: the rig board's
`testdata`, `document.gen.ts` generated from `document.go`, and
`Board.test.tsx`. The old contract's tests go with it (section 1).

Before unit 2 lands, its implementer reads both answers back to back on the
live city. The old rows come from the deployed binary, which is built from main
until the integration branch lands:
`"$GC_CITY_PATH/.gc/services/helm/bin/helm-svc" board --json --limit=0`, which
prints every row owed to you with no cap. The new document comes from a build
of the unit's head, running `helm-svc board --json`. The implementer lists every
bead the old rows say is owed to you that the new document's "needs you" rows
do not name, or the reverse, and says why for each in the unit's PR summary. A
difference that the new reader gets wrong is fixed in the shared reader before
the unit lands.

What you see change: on the page, one label (decision 2) and the "Not
scheduled" list's members (decision 3). In your terminal, `gc-helm` names the
web page as the board. Everything else you use, your keys, the page's buttons
and the terminal form, works as before.

## 10. Units

Each unit lands on `integration/tk-1tfzr71.24` and leaves the suite green and
the city working.

| Unit | What it does | Waits on |
|---|---|---|
| 1. The agents' read | `helm-svc board --json` over `rigboard.Read`, with `--rig` and `--timeout`; its tests; the text section 5 gives it | nothing |
| 2. The old board retires | Everything section 1 lists; the beads requirement and the ICU helper with every use (section 4); "Assigned to you"; the two Debt entries; the warrants that name the old board's reads (Machine axis, Unanswered review threads); the deletion plan's row for the parity test; `lifecycle.test.sh`'s machine-axis check; the text section 5 gives it; the comparison of section 9 | unit 1 |
| 3. Ready work no queue holds | `queue`'s answer and the "Not scheduled" list over it (section 2), with tests for each item of the patrols design's section 8 list | unit 1 |
| 4. The verbs | takeaway, park, place and accept as gctk commands; react's and priority's callers; the callers, tests, warrants and text of section 5 | nothing |
| 5. The build orders | `gc-build.sh`'s owed-build mode and the two condition orders (section 8) | unit 2: until the library goes, its probe needs a run when the source has not moved |

Unit 4 is the largest, and its implementer may split it into a bead for
takeaway and one for the rest, each removing its verbs and moving their
callers together.

## 11. Edges and notes the implementation child adds

- The units are filed under the epic (tk-1tfzr71) with
  `target=integration/tk-1tfzr71.24` in each create, and tk-1tfzr71.24 and the
  summary task tk-1tfzr71.215 wait on each through a `blocks` edge. A unit
  waits on the units its row names through a `blocks` edge, armed to dispatch
  on `mol-polecat-work` when they close. The child builds no unit.
- tk-ssm8qns.15 gets a note: resolve, dismiss and handback move with its
  verbs, and each `BEADS_DIR` pin in the verbs it moves, dismiss's two among
  them, becomes `GC_RIG` or `--db`, with a subject in another rig read from that
  rig's store (section 5). Whichever of it and unit 4 lands second removes the
  architecture page's Debt entry on `gc-helm.sh`'s verbs. The bead stays
  unarmed, as its epic decides.
- tk-ssm8qns.23 gets a note: accept's clear of `gc.recommended_formula` moves
  with unit 4, and the bead keeps the reads in `converse-signoff.sh` and
  `converse-invalidate-recommendation.sh`.
- tk-1tfzr71.25 gets a note: the contract parity test goes with unit 2, and the
  `board` stub verb stays its.
- tk-yhquh93 gets a note with the two page readings of section 2: a timer or
  GitHub gate reads "Not moving", and a conversation whose sitting died reads
  "In conversation".
- The open bugs whose code unit 2 deletes are held on tk-1tfzr71.24 by the
  waits skill's "Have a bead checked and closed once other work lands", and
  each is checked when unit 2 lands: one whose cause lived only in the deleted
  code closes as moot, and one whose cause survives is pointed at the code that
  carries it. Candidates at this reading: tk-ikpyzn.13, tk-ikpyzn.16,
  tk-68ardj9, tk-8wg5eg9, tk-fu2zlgq, tk-vlg4ihb, tk-72u5bsc, tk-2ylndr6,
  tk-7rquf68 and tk-vbn1adn in the old board alone, and tk-fgek12q, tk-35ob5gq,
  tk-y4820m2 and tk-ilobdri, which also name code that survives. tk-j8dzqmm
  already waits on this member.
- Open branches at this reading that change the units' files: the GitHub-intake
  effort (tk-1tfzr71.149, PR #1559) in the rig board, its server route and
  `main.go`, with a new file in `internal/source` (section 1), for units 1 and
  2; the lint (tk-2astzmg, PR #1601) in `board.go`, `internal/board/state.go`
  and `supervisor.go`, and with the Go release pin (tk-1fsgv13, PR #1600) and
  the make targets (tk-a5mwcic.3, PR #1595) in the ICU helper's uses (section
  4), for unit 2; and the sitting's send-back (tk-h0sherg, PR #1563) in
  `converse-signoff.sh`, which calls accept and takeaway, for unit 4. The child
  surveys the open branches again before filing, since they move.

How each note of the initiative is answered: the PR answer, the await types,
the sittings, the epic waits and the Delivery dates in section 2; the ready
row in sections 2 and 10; `readPendingWaits`, which goes with `beads.go` in
section 1; the supervisor API in section 3; the cgo end in
section 4; the verbs, the takeaway release, the pinning, react, the first
reaction's record, Accept's search and the stale text in section 5; the minted
state in section 6; the route and the gate rows, `demand()`'s comment and the
"Routed to you" ask in sections 1 and 7; `selfStart` and the board's read of
`gc.recommended_formula`, which go with the old board, in section 1; the
rebuild order in section 8; and the postmaster seat, which tk-1tfzr71.207 adds
beside the seat verbs that tk-ssm8qns.15 moves, in section 5.
