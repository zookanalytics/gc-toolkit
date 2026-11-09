---
name: Gas City search for the terminal conversation form
description: The search the arch check asks for before the pack adds the terminal conversation form (helm-svc form), the gc-helm verbs conversations and attach, and open --new-subject. What Gas City and bd ship for composing a question into work, titling it, saving it again without filing it twice, listing sessions to return to and telling when one is ready, read at named upstream commits, and the gap each leaves that the form fills by composing them. Read it when checking whether the form, or one of its verbs, can move onto a Gas City or bd primitive.
---

# Gas City search for the terminal conversation form

`gc-helm.sh engage` on a terminal now opens a form. The subject, a multiline
question, a new topic's rig, the model and whether to attach are fields of one
screen, in that order, and the subject's details, its open conversations and
the city's rigs load while the operator types. Submitting saves the question as
a conversation, says so, then starts its sitting, and once the sitting has
started attaches to it, or with attaching off leaves it to prepare and says how
to return to it.
`gc-helm.sh attach` opens the same form on the conversations to return to, by
topic and readiness. The change adds this surface:

- `helm-svc form`, the Go program, a third entry point of the helm binary beside
  `board` and `probe`.
- `helm-svc form --no-attach`, which opens the form with attaching off, and
  which engage passes on from its own `--no-attach`.
- `gc-helm.sh conversations [<ref>] [--json]`, a read: every open conversation
  in the city with its sitting's readiness, or the subject a reference names
  with where a conversation about it would be held.
- `gc-helm.sh attach [<conversation>]`, the return verb.
- `gc-helm.sh open --new-subject --rig <rig>`, which files a new topic's
  subject and its conversation without a sitting, so a save is acknowledged
  before a start.
- `gc-helm.sh open <ref> --if-subject <id>`, which files only while the
  reference still names the subject the form showed.
- `gc-helm.sh open <ref> --conversation <id>`, which completes the conversation
  an earlier open filed for the concern, by its id, rather than file another.

Gas City read at upstream main `2264fa8108` (gastownhall/gascity, fetched
2026-11-08). bd read as installed, 1.3.4, and its source at v1.3.2 in the Go
module cache.

## What was searched, and what each leaves

**A form that composes a question into work.** bd ships `bd create-form`, a
huh form (`cmd/bd/create_form.go` at beads v1.3.2) with Title, Description,
Type, Priority, Assignee, Labels and External Reference fields. It files one
plain issue in the store the command runs against. It does not cover the need:
its Title field is required, and the operator ruled out entering a title; it
resolves no subject, so it cannot say which rig a bead or PR belongs to; and it
files no conversation (a task that tracks one subject and waits assigned to
`human`), starts no sitting and loads nothing while the operator types. Gas City
ships no terminal form of its own: upstream's `go.mod` at `2264fa8108` carries
no terminal UI library. The form is built on the same libraries bd's form is
(charm.land bubbletea, bubbles and lipgloss v2, which `bd` 1.3.2's `go.mod`
already requires), and it files through gc-helm.sh's open and engage, so a
conversation is written once, by the code the command line uses.

**A short title for a long question.** `gc session new --title-hint <text>`
(`cmd/gc/cmd_session.go` at `2264fa8108`, the `title-hint` flag) titles a
*session* from text, a short version at once and one refined by a title model
afterwards. It does not cover the need: the title the operator sees on the board
and in the queue is the conversation bead's and the subject bead's, not the
session's, and a bead's title is written at `bd create`, before any session
exists. The bead titles come from the pack's `conversation_title` in
gc-helm.sh, the convention every conversation title already uses, which is
deterministic and needs no model call.

**Finding a sitting to return to.** `gc session list --json`
(`newSessionListCmd`, and the `attached` field of its session rows, in
`cmd/gc/cmd_session.go` at `2264fa8108`) lists sessions with their alias,
state, creation time and whether a terminal is attached, and `gc session
attach` attaches to one. Together they cover attaching to a live session, and
the form uses both: `conversations` reads the session list for each sitting's
state and attachment, and the attach runs engage's, which runs `gc session
attach`. They do not cover the rest of the need. A session row does not say
which conversation its sitting holds, what that conversation is about, or
whether the sitting has finished preparing; and a conversation whose sitting's
session has closed has no session to list or attach to, while engage holds it in
a new sitting. The pack's conversation shape (`conversation.sh`) and engage's
states (live, queue, left) answer those, so the listing is a gc-helm verb that
joins the session list to the conversations.

**Telling when a sitting is ready.** `gc session wait` registers a dependency
wait that wakes a session when beads close (`--on-beads`), which is a wait for
the session, not a readiness signal for the operator. A session row's state
says when the runtime has started (`start-pending`, `creating`, `active`), and
the form reads it for "starting". Nothing in Gas City says when a converse
sitting has finished its prep and holds for the operator. The pack's own record
does: a sitting records each framing with `gc-helm.sh handback`, which stamps
`gc.handback_at` on the conversation ([the hand-back's search](../tk-6sn8yea/gas-city-search.md)).
A hand-back recorded after the sitting's session was created reads as ready.

**Saving before starting.** `gc-helm.sh engage --new-subject` creates a new
topic's subject, files its conversation and spawns its sitting in one call, so
an acknowledgement could come only once the spawn returned, and a spawn that
failed would leave the operator guessing whether the question was saved.
`gc-helm.sh open` already files a conversation without a sitting and answers
`--json`. `open --new-subject --rig` extends it to a topic with no bead yet,
through the subject creator engage uses, so the form saves with open, says
"saved", and starts with `engage <conversation> --no-attach`. bd's
`bd create` is the write under both. It exits 0 once the write is durable, which
is the point the form says "saved".

**Filing only where the screen said.** `open` resolves its reference before it
files: a closed bead along its supersedes or duplicates edge to its successor,
which can sit in another rig, a PR to its anchor, and a gate to the one bead
waiting on it. The form shows the subject that resolution gave when it read
the reference, and by the time the operator saves, the reference can lead to
another bead. bd's guarded writes, `--if-assignee` and `--if-status` on
`bd update` (`cmd/bd/update.go` at beads v1.3.2, the flags at lines 997–998),
apply a write only while a field of the bead written still holds the value the
caller read, and write nothing otherwise. They do not cover the need: the
conversation is a new bead, and `bd create` takes no precondition (its flags at
v1.3.2 are `cmd/bd/create.go` lines 918–964 and `registerCommonIssueFlags` in
`cmd/bd/flags.go`). `--deps tracks:<id>` resolves only the id it names
(`resolveDepSpecTargets`, which refuses an unknown one) and writes the edge
whatever that bead's state, and nothing in `create.go` follows a supersedes
edge. Gas City at `2264fa8108` has no verb that resolves a bead
reference to its live successor or guards a create on one; the only flags of
that kind in `cmd/gc` guard a purge (`expect-count` and `expect-digest`,
`cmd/gc/infra_class_purge.go`). So the guard is open's own, named after bd's
guards: `--if-subject <id>` files only while the reference resolves to that
subject, and otherwise files nothing and exits 4, open's refusal code. The
subject's id fixes its rig, since a rig is derived from the id's prefix.

**Saving again without filing twice.** `open` files the conversation in one
`bd create`, then makes its reply onto the gate it answers with `bd dep add`, a
second write. When that reply did not read back, `open` exited 4 with nothing on
`--json`, so the form could not tell that a conversation held the question, and
its next save, which passes `--allow-duplicate`, filed a second one. Three
primitives were read for a create that a retry repeats at most once:

- bd's `bd create` takes no idempotency key. Its `--deps` collapses only a
  repeated edge within one create (`dedupeDepSpecs`, `cmd/bd/create_deps.go`
  line 65 at beads v1.3.4), and `external_ref` carries a plain index, not a
  unique one (`idx_issues_external_ref`,
  `internal/storage/schema/migrations/0001_create_issues.up.sql` line 59), so a
  create run again is a second bead.
- The reply cannot ride the create. `--deps replies-to:<gate>` is written in the
  create's own transaction (`CreateIssuesInTxWithResult`,
  `internal/storage/issueops/execution.go` lines 88–101), but on bd's direct
  route `resolveDepSpecTargets` refuses a target the written store does not hold
  (`cmd/bd/create_deps.go` lines 106–128) and nothing is created. A gate can sit
  in another rig's store, and `bd dep add` records an edge onto it in
  `depends_on_external` without looking the gate up (`ClassifyDepTarget`,
  `internal/storage/issueops/dependencies.go` lines 92–100, and the existence
  check it skips at lines 222–236).
- Gas City at `2264fa8108` runs `POST /v0/city/{cityName}/beads` at most once
  per `Idempotency-Key` (`withIndexedIdempotency` in `humaHandleBeadCreate`,
  `internal/api/huma_handlers_beads.go` line 795). Its body takes no
  dependencies (`BeadCreateInput`, `internal/api/huma_types_beads.go` lines
  53–67), so a conversation filed there is born without the tracks edge that
  makes it one, which `open` writes in the same create so that no reader sees
  the task without its subject. Its keys live in a 30-minute in-memory cache
  (`newIdempotencyCache(30 * time.Minute)`, `internal/api/server.go` line 312),
  which a supervisor restart forgets.

None covers the need, so `open` uses what the store already records.
Once the conversation is filed, `--json` names it on every exit, the failed
reply's included, and the form keeps it as saved and starts nothing. Its save
again names that conversation, as the next section says. A save whose answer
was lost names none, and for it, with `--allow-duplicate`, a concern that a
conversation waiting in the queue holds as its whole ask lands on that
conversation. `open` already reads the subject's conversations before it files,
so that save completes the conversation the first one filed, adding the reply
that did not land, rather than file a second.

**Completing the conversation a save filed, by its id.** A save that files the
conversation and then fails on its reply onto the gate leaves the form holding
the conversation's id, from `open`'s `--json` answer. Its save again must
complete that conversation and never file a second, even once a sitting another
terminal started has taken the conversation out of the queue, which the match on
a queued ask passes over. Three primitives were read for naming what a retry
completes:

- bd writes the missing piece by id already. `bd dep add <conversation> <gate>
  --type replies-to` (`depAddCmd`, `cmd/bd/dep.go` line 253 at beads v1.3.4) is
  the reply's write, and `conversation_reply` makes it and returns its exit. bd
  answers a second add of an edge of the same type without an error and
  refreshes only the edge's metadata (`addDependencyInTx`,
  `internal/storage/issueops/dependencies.go` lines 258–277 at beads v1.3.4), so
  running it again adds no second edge. The edge holds nothing, whatever state
  the conversation is in. bd gives the form no way
  to reach it, because the form writes nothing itself, and its every write is a
  gc-helm verb.
- bd's guarded writes, `--if-assignee` and `--if-status` on `bd update`, apply a
  write only while the bead is in the state the caller read. The completion has
  to apply in every state but closed, queued or held by a sitting, so a guard on
  one state is the wrong tool, and an edge add takes none.
- Gas City at `2264fa8108` serves a bead's dependencies read-only.
  `GET /v0/city/{cityName}/bead/{id}/deps` (`cityGet` in
  `internal/api/supervisor_city_routes.go` line 225) is its one dependency
  route, and `gc bd dep add` passes through to bd
  (`cmd/gc/bd_split_allowlist.go` line 131). Its `Idempotency-Key` keys a
  create, and this conversation is created already.

None of them names the conversation a retry completes, except through the id
the create answered, which the caller holds. So `open --conversation <id>` takes
that id back. `open` lands on the conversation by its id, checks that it is an
open conversation about the subject and holds the concern as its ask, completes
its reply onto the gate with `conversation_reply`, and files nothing. A
conversation closed since, or one that holds another ask, is refused with exit 4,
and nothing is written.

**Keeping the subject a killed save filed.** The form runs each verb under a
deadline, and `verbs.Exec` ends a run past it by killing the run's process
group, so no trap of `open`'s runs. `open --new-subject` printed the subject's
id only from its exit trap until the conversation was filed, so a save killed in
between lost the subject, and the next save filed a second one. One primitive was
read for a retry that lands on the subject the killed run filed:

- Gas City at `2264fa8108` runs `POST /v0/city/{cityName}/beads` at most once
  per `Idempotency-Key`, as the section on saving again says, and its body
  carries what a subject is filed with: the rig, title, description and the
  metadata set at create time (`BeadCreateInput`,
  `internal/api/huma_types_beads.go` lines 54–69). A save again under the killed
  save's key would get the same subject back while the key stays in the
  30-minute in-memory cache, which a supervisor restart forgets. Using it takes a
  key the form makes, a new `open` flag to carry it, and a subject filed through
  the API instead of `gc bd create`, which gc forwards to bd once it has judged
  the bead's class (`cmd/gc/bd_split_allowlist.go` line 160).

A kill does not need it, because `open` holds the subject's id as soon as
`bd create` answers. So with `--json` it answers
`{subject, conversation: "", filed: false}` right then, before any read that can
stall, and the answer it ends with comes after. The form decodes the last answer
`open` printed, so a killed save comes back with the subject and the save again
files onto it. A create that landed and lost its reply leaves the id unknown.
That is a case the key would cover, the form does not, and a retry after it files
a second subject.

**Attaching once the sitting starts.** `gc session new` attaches the terminal to
the session it creates unless `--no-attach` is given (the `no-attach` flag of
`newSessionNewCmd`, and `shouldAttachNewSession`, which attaches unless that
flag is set or the transport is ACP, in `cmd/gc/cmd_session.go` at
`2264fa8108`). `gc session attach` (`newSessionAttachCmd`, same file) attaches
to a session that already exists. engage composes both with the same default:
it attaches the sitting it starts, once the reconciler has started it, unless
its own `--no-attach` is given. The form composes them through engage. It
starts the sitting with `engage <conversation> --no-attach`, so the start ends
with the save's acknowledgement still on screen, and then attaches through
engage's attach, `engage <conversation>`. They do not cover the field itself.
Gas City ships no terminal form, so nothing in it presets a form's field, and
engage's `--no-attach` reaches the form only as an argument. So `helm-svc form`
takes `--no-attach`, named for the flag it carries, and with it the attach field
opens off and the form leaves once the sitting has started.
