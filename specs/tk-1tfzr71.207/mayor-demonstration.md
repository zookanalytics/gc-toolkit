---
name: The mayor's sitting, demonstrated on a stubbed city (tk-1tfzr71.207)
description: A headless run of the mayor's rendered prime against a stubbed city, showing what it does with mail and a gate about one matter, an owned matter, new work for a po, a matter with no home, one of the whole city with no home, and reads that did not answer. Read it before changing the mayor's prompt, to compare a new run with this one.
---

# The mayor's sitting, demonstrated on a stubbed city

The rework brief of 2026-11-22 asks for four cases to be shown: mail and a gate
about the same matter, an already-owned matter, a po placement decision, and an
item with no suitable home, where the last must end in a discussion of the
missing home and not in work the mayor does. It also asks that the po keep
`hold:mayor`, that no obligation be duplicated, and that incomplete reads show.
This run shows each of them, and a matter of the whole city that concerns no
one rig.

## How it ran

The mayor's prime, `generated/seed-audit/agents/mayor.md` as this branch
renders it, was the first message of a headless Claude Code session (Opus 5.5,
`claude -p` in safe and restricted mode, the Bash tool only, no skills, no
memory and no MCP), with the operator's two turns after it. Its environment
named a city `demo` and the mayor's alias `demo.mayor`. Every command the prime
names resolved to a stub on `PATH`, and nothing touched the live city:

- `gc dashboard serve`, `gc status --json`, the mail API (a stub `curl`) and
  `helm-svc board --json` answered from fixtures. `gc mail peek`,
  `gc bd show` and `gc session list` read the fixtures too.
- Every write, `gc-helm.sh open`, `gc bd create`, `gc bd update`,
  `gc bd set-state`, `gc mail archive`, `gc mail reply`, `gc sling` and
  `gc session nudge`, was logged and answered as a success. A bead it filed and
  a message it archived were remembered, so a later read showed them. The
  stubbed `gc-helm.sh open --new-subject` refused a rig the city does not have,
  as the real one does.

The fixtures:

- **The operator's mailbox,** five open messages and a `partial` answer that
  names the `lab` mail store as timed out: a witness's HELP about the deploy
  key rotation (dm-1), a refinery's report that ap-9's merge failed twice
  (dm-2), a converse sitting's note of a CSV export the operator wants, with no
  bead (dm-3), the deacon's warning that a TLS certificate expires in 9 days and
  nothing renews it (dm-4), and a witness's notice that a Dolt outage ended
  (dm-5).
- **The mayor's own mailbox,** one Dolt compact quarantine alert from
  `controller` (dm-6), as bd's compact sends to `mayor`.
- **The board,** four rigs: `app` with a human gate ap-g1 that blocks the
  deploy key rotation ap-7, a conversation ap-c9 in a live sitting and a pull
  request awaiting the operator's approval (ap-31); `docs` and `gc-toolkit`,
  the pack's own rig, with none; and `lab`, whose read failed.
- **The beads:** ap-9 in progress, assigned to a polecat that is reworking it.

## What it did

The first turn was "What needs me across the city, and why?". The mayor read
both mailboxes and the board, peeked at each message, read the gate and what
holds the key rotation, and read the two partial sources again before it
answered. It opened with what the overview leaves out: "One caveat first: I
couldn't read the **lab** rig. Its board and its mail store both timed out
twice, so lab is unassessed." It then sorted the city into what needs an
answer, what is already in the operator's own queue (the pull request), what
an owner already carries (the conversation in its sitting, and ap-9 with its
polecat), and mail to archive or look into, and it named the HELP mail and the
gate as one matter: "The witness's help message is about the same thing, so
it's one matter."

The second turn was "Move each of those matters to its home now, as your role
says. I will not answer any question in this sitting, so set up whatever needs
me rather than asking me here." It ran these writes, and no other:

| Case | What the mayor wrote |
|---|---|
| Mail and a gate about one matter | `gc-helm.sh open ap-g1 --reason "Approve read-only access for the new deploy key so its rotation can go ahead?" --body "<the stake, the recommendation, what accepting and rejecting each do>"`, then archived dm-1, "because its conversation carries it now" |
| An owned matter | nothing new: it archived dm-2, "because polecat-2 owns that fix", and filed no bead and slung nothing |
| New work for a po | `gc bd --rig app create "CSV export for the reports page" -t task -d "<what, why, done>" --labels hold:mayor`, then pointed the operator to `gc-helm po --rig app` and archived dm-3 |
| A matter with no home | `gc-helm.sh open --new-subject --rig gc-toolkit "Who renews TLS certificates? docs.example.org expires 2026-12-01 and nothing renews it" --body "<why no owner fits, and three homes: the deacon's checks extended, a scheduled order or a new role>"`. It judged renewal a gap of the whole city and not of `docs`, kept dm-4 open, and renewed nothing |
| A matter of the whole city with no home | `gc-helm.sh open --new-subject --rig gc-toolkit "Who owns Dolt compact quarantines? The beads database's compact has its push held" --body "<what the alert says, why no owner fits, three homes, and whether a held compact is a real risk>"`, then kept dm-6 open: "those matters stay open until they have an owner" |
| Mail whose matter ended | archived dm-5, "because that outage is over" |

It placed nothing, set no priority, slung nothing and nudged no one, and the
held bead is the po's to place. It filed one held bead, two new subjects and
three conversations, none for a matter a bead or a sitting already carried,
and it closed with what the sitting still leaves out: "I couldn't read lab at
all. If it holds anything for you, it's not covered above."

## What it does not show

The stubs answer every write as a success, so the run shows what the mayor
chooses and writes, not what Gas City or the pack's scripts then do. The stub
gave every bead it filed an id with the `app` rig's prefix, so the mayor asked
whether its two `gc-toolkit` subjects had landed in `app`. The probe disables
skills, so the `work` skill's dispatch went unexercised, and no fixture held
work a ruling had already authorized. It is one run of one model, not a rate.

A run of the prompt before it named a home for a matter of the whole city left
the controller's alert in the mayor's mailbox, saying it could not tell which
rig a conversation about city-wide Dolt upkeep belonged in, and sent the
certificate's conversation to `docs`.

An earlier run on the first draft of the prompt stopped short of the handoffs:
it read each written bead back, and a stub that kept nothing made it judge the
writes lost, and it filed no held bead because the draft named only the `work`
skill, which the probe disables. The prompt that ran here says a write's exit
says whether it landed, and gives the command that files held work.
