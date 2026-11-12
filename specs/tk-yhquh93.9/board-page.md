---
name: The rig board's page, and where it departs from the Claude Design export
description: The record of unit 2 of the board's build (tk-yhquh93.9) - the page on the rig read, its actions and the old page's removal - with each place the page departs from the operator's Claude Design export and why, and the bead that carries each part this build leaves out. Read it before changing how the page draws a row, or when the page and the export disagree.
---

# The rig board's page

The operator drew the board in their own Claude Design session and ruled, in
conversation tk-w2hvygn, on where that design meets the store. The brief is the
newest block headed "## Current state" in tk-yhquh93.2's notes. Unit 1
(tk-yhquh93.2, recorded in [board-read.md](../tk-yhquh93.2/board-read.md))
built the read: one document per rig, which decides every group, signal, count,
ask, section and order. This unit builds the page that lays that document out,
wires its actions, and removes the old page.

## What was built

- **The page** (`services/helm/web/src/rigboard/`). One rig a page, with the rig
  in the address (`?rig=<name>`); with no rig there, the city's rigs from
  `GET /helm/rigs` as links. Four pages, Epics, Needs you, Work queue and
  Unprioritized, each a layout of the document's own lists. Every object is
  drawn with one row structure (`Line.tsx`): chevron, priority, a marker or tag,
  the title, then the signal, Details and the bead id; line 2 clipped to two
  lines; line 3 for short facts and actions. Titles wrap and are never cut.
  Search runs over the loaded document. A bead id copies on a click, and a
  referenced id's "show" fills search with it.
- **Its reads.** The rig's document, on load, every half minute, whenever the tab
  is shown again, and after a write the page sends. A read that fails keeps the
  last good document on screen with the time it was read and the failure beside
  it, and a failed first read shows the failure alone, with no list. A bead's
  whole description, read from the supervisor when its Details opens and
  formatted as markdown, through a typed client generated from the supervisor's
  OpenAPI document and pruned to that one operation (`src/supervisor/`).
- **Its actions.** Start the conversation, on a question no conversation
  answers, and Rejoin the conversation, on a question a conversation answers and
  on a conversation, call the engage route. The side panel, where the export
  draws its terminal, shows the route's answer and the command that attaches to
  the sitting, with a control that copies it. Discuss, in every row's Details,
  opens the open route's form (`src/open/`) in the side panel.
- **Its fonts.** IBM Plex Sans (400, 500, 600) and IBM Plex Mono (400, 500), the
  latin woff2 files of the `@fontsource` packages, bundled and served from the
  page's own origin. The build writes each package's licence beside the page
  (`dist/fonts/`).
- **The old page removed.** `App.tsx`, `styles.css`, `drill/`, `terminal/` and
  `actuate/ActuateButton.tsx`, with their tests, and the two xterm packages.
  The supervisor client the page keeps moved from `drill/` to `supervisor/`.
- **The page on fixture data.** `helm-fixture` answers `GET /helm/rigs` and
  `GET /helm/rigs/{rig}` from a rig document, by default the document the rig
  read builds from the committed gc-toolkit fixture, so tests and a demo capture
  run the page on real gc-toolkit beads. The search for both reads is
  [gas-city-search.md](gas-city-search.md).

## Where the page departs from the export

| The export | The page | Why |
|---|---|---|
| A rig switch in the header, with a count for each rig | The rig the address names, and a link to the list of the city's rigs | The brief: one rig a page, and nothing rolls up across rigs |
| An epic's row reads its handle, or its title less "Epic:", and a Delivery's its title less "Delivery:" | An epic's row reads its handle where it records one, else its title as stored, and a Delivery's row its title as stored. Details holds an epic's title | Titles are never cut, and nothing rewrites a bead's text. A handle is a stored word |
| Needs you leads with every open human gate and conversation, "things are waiting on you" | It leads with the document's count, the asks that hold or concern work under an epic: "things in an epic are waiting on you" | The count must be able to reach zero, and the read counts no ask under no epic |
| An ask's signal is its conversation's state: "No conversation", "Conversation waits for you" or "In session" | The row's signal, as the document gives it: the ask's words, which read "Question" while no conversation answers a question | Go chooses every signal, and the page derives none |
| Line 3 says what a chain ends on in words of its own ("stuck until you answer:", "held by this gate:") | Line 3 names each bead the document's line 3 lists, by id, title and a show link, in no words of the page's own | The document gives the beads, not a kind of end. The export's words came from its own walk |
| "held with its epic by", and "N more beads wait on this", on line 3 | Neither is drawn | Both came from the export's own walk. An ancestor's gate reaches the row as its own "Held by a gate", and Details lists what waits on a bead |
| "In flight · <assignee>" and "Closed · merged" as one signal | The signal, with the table's note beneath it | The document carries the two apart |
| A pull request's facts are its machine, conversation and merge state, red when the merge state is dirty or blocked | Its number, where it stands and what holds it, in the pack's words, never red | The document gives `prstatus`' words and no merge state |
| Details leads with the data file's trimmed description | Details leads with the whole description, formatted, read from the supervisor when it opens | The brief |
| An epic's Details reads Measures and Done when | Hypothesis, Boundaries, Closure condition, Leading indicators and Last ruling | The words docs/epic-stewardship.md gives the contract's fields |
| A terminal panel with a session's lines and an input | A side panel with the engage route's answer and the attach command, or Discuss's form, and no input | The brief: no terminal is mounted |
| Discuss opens a new conversation in the terminal panel | Discuss opens the open route's form, which files a conversation in the operator's queue | The brief |
| Unprioritized lists "No epic yet" beside the Product Owner's session | It lists the beads by priority, and no session | The brief |
| A Work queue section's dot is drawn for its kind of section | A section's heading takes the colours of the group its rows share, and none when they share none | Go decides each row's group, and the page gives no section a group of its own |
| Details can open in a side panel | Details opens in place only | The brief |
| Fonts from Google Fonts | Fonts bundled and served from the page's origin | The page's content policy (`web/handler.go`) admits a font from its own origin only |

The export has no Accept or Dismiss, and neither has the page. The routes and
`gc-helm.sh`'s verbs stay.

## Calls this build made

- The brief has every file under `web/src` the page does not import deleted,
  naming "the fixtures" among them, and keeps `web/src/contract.ts` and
  `web/contract_parity_test.go` untouched. That test reads
  `web/src/board.fixture.json`, and `web/src/contract.fixture.ts` asserts the
  same sample against `contract.ts` at compile time, so the two fixtures stay
  with the parity check they belong to, which tk-1tfzr71.25 retires.
- The address carries the rig as a query, `?rig=<name>`, which the page's
  handler serves at the mount's root with no route of its own, and which the
  shell's mount normalizer keeps.
- A description is formatted with `react-markdown` and `remark-gfm`, which
  show raw HTML in a description as text and drop a `javascript:` link's
  address.
- The page reads its document every half minute, half the service's minute of
  cache, and a read open for a minute is dropped as failed.
- A section's count on a heading is the number of rows its list holds, and the
  "holds up N beads" on an ask drawn under work is the length of its list of
  holds. Neither decides anything.
- In a board column under 800px wide, a phone's or one the side panel
  narrows, line 1 wraps: the title takes the whole line, the signal flows
  beneath it, and Details and the bead id sit at the right. Details' fields
  stack under their names. Beside the three columns, the narrowest titles on
  the committed fixture have under about 160px at that width, and no width at
  all on a phone.
- The side panel sits beside the board where the two fit, and after the board
  below about 1080px. When it opens or turns to another bead or kind, it
  scrolls into view and focus moves into it, and an engage's answer that
  arrives later moves nothing.

## What this build leaves out

| Left out | The bead that carries it |
|---|---|
| A conversation's terminal on the page | tk-yhquh93.5 |
| Needs you rolled up across every rig | tk-yhquh93.6 |
| Work behind other work split by whether what is ahead is moving | tk-yhquh93.7 |
| A mark for work that started and has no live worker | tk-yhquh93.8 |
| The Product Owner's session on the Unprioritized page | tk-c9dcsbn |
| The command line's rows moving onto this read, and the `/helm` answer `helm-fixture` still serves | tk-1tfzr71.24 |
| The contract's parity check: `contract.ts`, its two fixtures and `contract_parity_test.go` | tk-1tfzr71.25 |
| The learning loop's standing records out of the Work queue | tk-yhquh93.10 |
