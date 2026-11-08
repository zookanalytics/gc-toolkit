---
name: Gas City search for the terminal conversation form
description: The search the arch check asks for before the pack adds the terminal conversation form (helm-svc form), the gc-helm verbs conversations and attach, and open --new-subject. What Gas City and bd ship for composing a question into work, titling it, listing sessions to return to and telling when one is ready, read at named upstream commits, and the gap each leaves that the form fills by composing them. Read it when checking whether the form, or one of its verbs, can move onto a Gas City or bd primitive.
---

# Gas City search for the terminal conversation form

`gc-helm.sh engage` on a terminal now opens a form. The subject, a new topic's
rig, a multiline question and the model are fields of one screen, and the
subject's details, its open conversations and the city's rigs load while the
operator types. Submitting saves the question as a conversation, says so, then
starts its sitting without attaching and says where it stands.
`gc-helm.sh attach` opens the same form on the conversations to return to, by
topic and readiness. The change adds this surface:

- `helm-svc form`, the Go program, a third entry point of the helm binary beside
  `board` and `probe`.
- `gc-helm.sh conversations [<ref>] [--json]`, a read: every open conversation
  in the city with its sitting's readiness, or the subject a reference names
  with where a conversation about it would be held.
- `gc-helm.sh attach [<conversation>]`, the return verb.
- `gc-helm.sh open --new-subject --rig <rig>`, which files a new topic's
  subject and its conversation without a sitting, so a save is acknowledged
  before a start.

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
