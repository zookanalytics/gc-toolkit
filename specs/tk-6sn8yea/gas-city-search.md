---
name: Gas City search for a sitting's last hand-back
description: The search the arch check asks for before the pack adds the gc-helm handback verb and the gc.handback and gc.handback_at keys. What Gas City, the packs it publishes and bd ship for reading what a session said after it ends, read at named upstream commits, three sittings' transcripts read against them, and why the pack records each hand-back on the visit instead. Read it when checking whether a sitting's last words can move onto a Gas City primitive.
---

# Gas City search for a sitting's last hand-back

When a converse sitting ends, the gc-helm tab that showed it exits, and nothing
of its pane survives. This change has the tab print the sitting's last
hand-back. The sitting records each hand-back it posts on its visit with
`gc-helm.sh handback`, which writes the text to the visit's `gc.handback` key
and the time to `gc.handback_at`. `gc-helm.sh engage` prints the text once
`gc session attach` returns. So the arch check asks what Gas City already ships
for that need ([review-arch.md](../../docs/review-arch.md#the-checks), check 1).
Gas City reads the transcript a session's provider writes, after the session
ends as well as before, through `gc session logs` and the API's transcript
endpoints, for both providers that converse sittings run. A transcript does
not mark which text is a hand-back, though. In three recent sittings, neither
the last text nor the last text in a hand-back's shape picked out the
hand-back every time. So the sitting says which text is its hand-back by
recording it. The record goes on the visit as metadata, which bd names as its
extension point for an orchestrator's data.

## The surface and the need

- `gc-helm.sh handback <visit-id>` reads a hand-back on stdin and writes it to
  the visit as `gc.handback`, with `gc.handback_at`, in one update that replaces
  the hand-back recorded before. It refuses an empty stdin and a bead that is
  not a visit, and it reads the text back. The converse prompt's rule "Record
  each hand-back on the visit, then post it" runs it before each framing and
  the sign-off, and the hold and settle skills carry the command.
- `gc.handback` and `gc.handback_at` are metadata keys, registered in
  `lifecycle.toml`.
- `gc-helm.sh engage` runs `gc session attach` as a child process. When the
  attach returns on a closed visit, engage prints how the visit closed and the
  recorded hand-back. On an open visit it prints the command that re-attaches.

The need is narrow. Once a sitting's session has ended, the operator's tab
prints the hand-back the sitting last posted, a framing or its sign-off. It
prints the header, the body and the decision, without the detail above them or
the close-out line below. It works for each provider a converse template runs:
Claude, for `converse-opus` and `converse-fable`, and Codex, for
`converse-codex`. It does not copy the pane, which the operator ruled out.

## Where the search looked

Each was read on 2026-10-26:

- Gas City at main `f78779e41522`: its documentation, its engineering docs, the
  `core`, `bd` and `dolt` packs it bundles from its own repository, and its
  source.
- Every pack in `gastownhall/gascity-packs` at main `dac12a4a802c`, and the
  `gastown` and `gascity` packs Gas City bundles, at the packs commit its
  `go.mod` pins, `66c672b5ed00`.
- bd at main `249d7cde74db`.

The search covered session transcripts and logs, the API's transcript, stream
and session responses, a live session's pane, the event log, mail and external
messaging, and the places bd keeps text on a bead. In every pack it looked for
reads of a transcript or of a session's output, and for any record of what a
worker last said to a person. Each pack's hits were tallied, and the hits about
sessions were read.

## What Gas City ships near the need

### A session's transcript

[`gc session logs`](https://docs.gascity.com/reference/cli#gc-session-logs)
shows "structured session log messages from a session's JSONL file". `--tail`
keeps the last N entries, and `--json` prints them as one result. It resolves a
closed session as well as a live one (package main, `resolveSessionLogContext`,
which looks the identifier up with `resolveSessionIDAllowClosedWithConfig`). It
finds the file by the session's key wherever the provider's family has a keyed
lookup (package transcript, `keyedFinders` and `DiscoverKeyedPath`). Claude
takes the generic lookup by id, Codex has its own
(`FindCodexSessionFileByIDNoWindow`), and both are exact. Gemini's is the one
keyed lookup that can return another conversation's file
(`inexactKeyedLookupFamilies`). It searches under the home directory of the
process that reads (package sessionlog, `DefaultSearchPaths`, with
`DefaultCodexSearchPaths` for Codex), and in the paths `[daemon] observe_paths`
adds. Each JSON entry carries its uuid, type and subtype, role, timestamp, and
text or content blocks, beside the provider's raw message (package main,
`sessionLogEntryJSON`).

The API serves the same transcript.
`GET /v0/city/{cityName}/session/{id}/transcript` takes one of three
formats. `conversation`, the default, returns turns. `raw` forwards the
provider's own frames, which a consumer parses by the provider the envelope
names (engineering doc *API Control Plane*, section 3.6). `structured` returns
a "provider-neutral structured transcript snapshot". Its assistant messages
carry an id, role, model, provider, status, stop reason, timestamp, usage and
content blocks (`SessionTranscriptStructuredResponse` and
`SessionStructuredMessageAssistant` in the OpenAPI document the
[Supervisor REST API](https://docs.gascity.com/reference/api) page links). The
endpoint resolves a closed session as well as a live one, and the session
stream answers a closed session with one snapshot of its transcript (package
api, `humaHandleSessionTranscript` and `streamSession`).

So Gas City can return a sitting's transcript after its session ends, for both
providers, and in a shape that does not depend on the provider. No read can say
which text is the hand-back. Nothing on a text entry or a text block says what
it is for, and a structured message is a user, assistant, system, tool or
unknown message. The structured format marks only the provider's own asks: an
interaction block, for a prompt the provider raises such as an approval, and a
tool call whose input kind is `question`, when the agent calls its provider's
question tool (`SessionStructuredInteraction` and
`SessionStructuredToolInput` in the OpenAPI document). A question tool carries
a question and its options, not a hand-back's header, body and decision, and a
sign-off asks nothing. A sitting posts other text too, such as progress notes,
step remarks and memory notes. The hand-back is the one it means the operator
to act on.

Three sittings' transcripts show what a read would get. They are the three the
arch validation pass sampled, read again on 2026-10-26 with
`gc session logs --tail 0 --json`. The `gc` that read them is the city's
deployed build of a fork, so they show what the transcripts hold, and the
claims above cite upstream.

| Visit | Its last assistant text | Its last hand-back |
|---|---|---|
| tk-wzp9ok3 | A step remark: it was loading step 8 before posting its sign-off. | Its step-5 framing, 43 minutes before. It posted no sign-off. |
| tk-4jv1oyh | A memory note, just before it drained. | Its step-5 framing, 95 minutes before. It posted no sign-off. |
| tk-u1wf6au | Its sign-off, posted after it acknowledged the drain. | That sign-off, which has no header line. |

Taking the last assistant text finds the hand-back in one of the three. Taking
the last text that carries the hand-back's header line
(`<subject-id> — <short human label>`) finds it in the other two and nothing
in the third. These sittings ran the prompt before this change, which had no
rule to record a hand-back. They show the transcript a read would get, and they
show that a sitting does not always give a hand-back its defined shape. A
transcript read could rely only on a marker the sitting writes into the text
the operator reads. It would then have to cut the hand-back out of the
sitting's own prose, from the header down to the close-out line.

### A live session's pane

[`gc session peek`](https://docs.gascity.com/reference/cli#gc-session-peek)
shows a session's output "without attaching". It reads the API's session
response when the controller is up, and the session handle's `Peek` otherwise
(package main, `routeSessionPeek` and `doSessionPeekFallback`). The API's
session response carries that preview as `last_output`, filled only while the
session runs (package api, `enrichSessionResponseWithKeyedPaths`). Either way
it reads the pane, which goes with the session, and the operator ruled out
copying it.

### Events, mail and external messaging

- Gas City's session events record what happened to a session, such as
  `session.woke`, `session.draining` and `session.stopped` (package events).
  `session.pending` carries a prompt the provider raises, such as an approval,
  which the controller reads off the session's screen so that a client can
  answer it (`SessionPendingPayload` in the OpenAPI document). None of them is
  a reply the agent posted. The `extmsg.inbound` and `extmsg.outbound` events
  belong to external messaging's conversations, below.
- [`gc mail send`](https://docs.gascity.com/reference/cli#gc-mail-send) sends
  "a message to a session alias or human". A sitting could mail the operator
  each hand-back. That delivers each one a second time, as unread mail in the
  operator's inbox, after the pane has already shown it, and the tab would
  still have to work out which message is the latest hand-back for its visit.
  `gc handoff` sends the same kind of mail to the session itself, for its next
  run.
- External messaging gives an agent an explicit reply.
  `POST /v0/city/{cityName}/extmsg/outbound` "publishes an agent's reply to the
  client's callback", and `GET /v0/city/{cityName}/extmsg/transcript` "lists a
  conversation's history"
  ([Supervisor REST API](https://docs.gascity.com/reference/api), "Endpoint
  families"). Both work on a conversation with a connected client, which
  registers a callback URL for a provider and an account. The engineering
  design *External Messaging Fabric* adds the external conversation because
  Gas City's mail, nudges and session input are "enough for internal
  agent-to-agent and human-to-agent work". A sitting is human-to-agent work,
  and the operator's tab is a terminal attached to the session, not a
  connected client.

### Text on a bead

bd keeps text on a bead in several places, so the record could go in any of
them.

- A [comment](https://beads.gascity.com/cli-reference/comments) carries an
  author, a time and its text, and bd's commands only add and list comments.
  A comment per hand-back would keep all of them, and the tab would print the
  newest. Nothing on a comment says it is a hand-back. A comment that a person
  or another agent adds to the visit would print as the sitting's last words,
  unless the reader also matched each comment's author to the session that held
  the visit.
- A visit's title and description are written when it is filed, and carry the
  ask it was filed with, so a hand-back written there would replace the ask.
  bd's design and acceptance criteria fields hold design notes and acceptance
  criteria (`bd update --design` and `--acceptance`).
- A bead's notes are one free-text field that all its writers share. A visit's
  notes carry what others write about it, such as a diagnosis appended for its
  sitting, so the latest hand-back cannot be cut out of them without a marker.
- A close reason is one line, written when the visit closes, and engage already
  prints how a visit closed. A framing is posted while the visit is open, and
  the operator's `gc-helm dismiss` closes the visit with a reason of its own.
- [Issue Metadata](https://beads.gascity.com/core-concepts/metadata) "is the
  preferred extension point for data that is specific to an integration,
  orchestrator, team workflow, or experimental automation". A key names what
  its value is, and a write replaces the value.

### The packs Gas City publishes

When a published pack hands a worker's words to a person, the worker writes
them out itself. No pack reads them back from the worker's transcript. Each
finding is at packs main unless it names the bundled pin.

- `pr-pipeline` and `pr-review` write a run's summary for a person as
  `summary_for_human` on the run's root bead, "so downstream loop-close
  handlers can surface the outcome" (`pr-review`'s `mol-pr-iterate`).
  `mol-pr-iterate`, `pr-review`'s `mol-pr-revert` and `pr-pipeline`'s
  `mol-pr-from-issue` set it when the run halts or finishes, and `pr-review`'s
  `mol-adopt-pr` sets it when the run halts.
- `gastown`'s `mol-polecat-work` stamps `halt_reason` on the work bead at
  several of its halts. Its base-branch STOP arms do so because otherwise "an
  unrecorded exit just loops through witness recovery until someone reads
  session logs". At the bundled pin it stamps `halt_reason` at one halt, when
  `auto_push` is off.
- The chat packs send an agent's words to a chat only when the agent runs one
  of their commands with the text: `reply-current` in `slack-full`,
  `slack-channel` and `discord`, and `post-message` in `slack-mini`. In
  `slack-full`, plain assistant output "stays private to the session and does
  NOT go to Slack". In `discord`, plain assistant output "does not go back to
  Discord" when an event asks for an explicit publish. `slack-full` publishes
  through Gas City's external-messaging outbound by default, which records the
  reply in the conversation's transcript. A session with an active company
  turn posts with the acting agent's own Slack token instead.
- To address a reply, `slack-full` takes the newest `extmsg.inbound` event for
  the session from Gas City's event log (`find_latest_inbound_for_session`).
  `discord` reads the session's transcript through the API for the newest
  `<discord-event>` block in a user message, and falls back to ingress records
  it keeps itself (`find_latest_discord_reply_context`). Neither reads the
  agent's reply from its transcript. `discord` keeps each reply it publishes,
  with its body, in a publish record of its own, and can quote it from there
  when a person replies to that message.
- `oversight-rig` delivers its escalation rollups through Gas City's
  external-messaging outbound, and its project lead does not read "raw agent
  transcripts".
- `gastown`'s agents read a live session's pane with `gc session peek`. Before
  its shutdown dance kills a stuck session, it reads the last 100 lines: "Save
  this output — it's the last evidence of what the agent was doing". None of
  its commands stores that output.
- `profiler` copies a run's transcripts into a profile for analysis. It lists a
  session whose transcript file is gone as a gap, because it reads transcripts
  "from the provider's own storage at collect time" (its README, "Known v0
  limits"). `cass` points an agent at an external tool that searches past
  coding-agent sessions for earlier work. Both read transcripts as material to
  analyze, not as a record of what an agent said to a person.
- The `gascity` pack names session logs only to tell an agent not to read them:
  in its `build-base` and `implement` workflows, and at the bundled pin in its
  role prompts, which forbid "session-log inspection" when looking for work.

## What the change does with it

The change records the hand-back that Gas City's reads cannot pick out, and
keeps the record in bd as metadata.

- The sitting names its hand-back by writing it, the one step no transcript
  read can take for it. The published packs hand a worker's words to a person
  the same way.
- The record is metadata on the visit, as bd documents for orchestrator data,
  under keys that use neither of bd's reserved prefixes (`bd:` and `_`). The
  board's one-line headline is kept the same way, as `gc.takeaway`, which each
  write replaces. A hold writes it on the visit when the subject is a pull
  request's anchor, and on the subject otherwise. `gc.handback` always goes on
  the visit, and holds the whole hand-back.
- engage reads the record from the same visit row it reads for the visit's
  status and outcome. The tab's last words then depend on the bead store alone,
  not on where a provider writes its transcript or on the reader's search
  paths.

The change adds a script verb and two metadata keys, and no bead kind or
lifecycle state, so it adds no pack noun and needs no warrant
([review-arch.md](../../docs/review-arch.md#the-checks), check 2). No warrant
in [warrants.md](../../docs/warrants.md) covers a path or key it touches. Its
edits to `gc-helm.sh` leave the `priority` verb, which *Priority following*
covers, as it was (check 4).

This answer changes if Gas City lets a session mark a reply it posts to the
person attached to it, in a record a reader can fetch after the session ends,
with no connected client. A structured transcript message kind for such a
reply would do it, and so would a record of a session's last reply. Either
would be the primitive to move the hand-back onto, and `gc.handback` would go.
External messaging's outbound already records a reply, but only in a
conversation with a connected client.
