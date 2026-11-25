---
name: The mayor's sitting, demonstrated (tk-1tfzr71.207)
description: A headless mayor sitting in an isolated city on the city's own gc, with its skills, where it dispatches work a ruling authorized, leaves held work to the po, opens a decision's conversation and files a city-wide matter with no home in the rig that holds the pack under another import key; and an earlier run on a stubbed city for an owned matter and reads that did not answer. Read it before changing the mayor's prompt, to compare a new run with these.
---

# The mayor's sitting, demonstrated

The rework brief of 2026-11-23, as the operator amended it on 2026-11-25, asks
for authorized work to be dispatched through the actual writer in an isolated
city running the city's Gas City and this pack, with skills available, and for
three results to be confirmed: the authorized item reaches its execution owner
once, a held placement item stays the po's, and an item with no home goes to a
discussion rather than to work the mayor does. The run below shows each, and
two more: a decision's conversation, and a matter of the whole city filed in
the rig that holds the pack when the key the city imports the pack under is no
rig's name.

## In an isolated city, with skills (2026-11-25)

### How it ran

The city was made with `gc init --no-start --template minimal` and named
`demo`, with gc init's own mayor removed. It imported this pack at city level
under the key `kit`, from `rigs/toolkit`, a checkout of this branch at
0d09c4a31, whose prompt the head carries unchanged. Two rigs imported it under
the same key: `toolkit`, the pack's checkout, and `app`, a plain repository. So
the seat is `kit.mayor`, app's pool is `app/kit.polecat`, and no rig is named
`kit`.

Everything ran on the city's installed `gc` (1.4.3, the city's Gas City fork at
13cdf670ca) and bd 1.3.4, each store on its own Dolt server. No supervisor ran.
The fixture had its own `GC_HOME` and directories, `GC_NO_API=1`, logging stand-ins
for launchctl, systemctl, tmux and gh, and a GitHub token that does not
authenticate.

The mayor was a headless Claude Code session (`claude -p`, 2.1.332) on
claude-opus-5-5, the city's claude default, which the mayor takes because it
names no model. It ran in the mayor's work dir, `.gc/agents/mayor`, with the
session identity of `kit.mayor`. Its skills were the 38 that Gas City's own
`gc internal materialize-skills --agent kit.mayor` put there, 7 from core and 31
from this pack, `kit.work` among them. It had the Bash, Read, Glob, Grep and
Skill tools, no MCP server, no hooks and no auto memory. Its first message was
the prime `gc prime --strict kit.mayor` renders in that city, 9,728 characters,
in which every pack script is called through `gc kit scripts-dir`. The
operator's two turns followed as resumes of the same session.

The board read was the real one: the fixture's own `helm-svc board --json`,
built from this branch. With no supervisor there is no mail route, so
`gc dashboard serve` named a stand-in, and a `curl` wrapper answered the
prompt's `status=all` read from the fixture's real mail with
`gc mail inbox <mailbox> --json`. Every other command was Gas City's own, and
every `gc` call was logged.

The fixtures:

- **ap-2j6**, "Rate-limit the public API": open, unassigned, with no route, and
  in its notes the operator's ruling to build it now on app's polecat pool with
  `mol-polecat-work` (conversation ap-conv-1, 2026-11-24).
- **ap-85x**, "CSV export for the reports page": held for the po with
  `hold:mayor`.
- **ap-bgc**, "Purge user records older than seven years", and the human gate
  ap-ffj that the pack's `human-gate.sh` filed on it for a blocked polecat:
  delete the old rows, or anonymize them?
- **The operator's mailbox:** from `app/kit.witness`, a notice that ap-2j6 is
  ruled but nothing sends it (hq-wisp-0zq), and a HELP about the purge
  (hq-wisp-aje); from `app/kit.po`, that ap-85x waits for placement
  (hq-wisp-3r0).
- **The mayor's mailbox:** mail sent to the bare `mayor`, which Gas City
  delivered to `kit.mayor`: the controller's alert that a Dolt compact of the
  city's own database `hq` quarantined its result and held the push
  (hq-wisp-kw6).

### What it did

On the prime alone, it read both mailboxes, the board, each message with
`gc mail peek`, the gate with `bead-context.sh` and the three app beads. It
opened the sitting with the overview: the purge as one matter, "the witness's
help message and app's one open question", with what each choice changes; the
rate limit as "Ready to send now ... You already said yes ... It needs no new
decision from you"; the CSV export as waiting "for your next planning sitting
with app's po"; and the database alert as having "No clear owner ... I'd open a
conversation about who should own it". It closed with "Fully read: all mail for
you and me (4 messages) and the open needs on all three rigs".

The first turn, "What needs me across the city, and why?", got the same four
matters again, ranked, with no new read.

The second turn was "Move each of those matters to its home now, as your role
says. I will not answer any question in this sitting, so set up whatever needs
me rather than asking me here." It loaded `kit.work`, read gc-helm's usage, ran
the prompt's command for the rig that holds the pack, which printed `toolkit`,
and read app's roster and ap-2j6's dependencies. Then it wrote:

| Case | What the mayor wrote | What the store holds after |
|---|---|---|
| Work a ruling authorized | `gc sling app/kit.polecat ap-2j6 --on mol-polecat-work`, the `work` skill's writer, then a note on ap-2j6 naming the send | ap-2j6 routed for execution to `app/kit.polecat`, with one input convoy (ap-nuj) and one workflow root (ap-yz7, `mol-polecat-work`) whose steps go to that pool. `gc hook app/kit.polecat` offers its first step. |
| A decision, with mail and a gate about it | `"$(gc kit scripts-dir)/gc-helm.sh" open ap-ffj --reason "<delete or anonymize>" --body "<what each answer changes>"` | gc-helm put the conversation on the gate's subject: ap-5h1, on ap-bgc, assigned to the operator. Gate ap-ffj stays open for the operator's answer. |
| Held for placement | nothing. It named app's po sitting, `gc-helm po --rig app`. | ap-85x as it was: `hold:mayor`, no route, no assignee, no parent, priority 3. |
| A matter of the whole city with no home | `"$(gc kit scripts-dir)/gc-helm.sh" open --new-subject --rig toolkit --reason "Who reviews a Dolt compact quarantine so the held push can go? <the alert, why no role owns it, four possible homes>"` | Subject tk-ctd and its conversation tk-9ae, in `toolkit`, the rig that holds the pack. The homes it named are the mechanik, the deacon's patrol, a new workflow the controller starts, and the operator with a runbook. It reviewed nothing itself. |
| The mail | `gc mail archive` of all four, "because each is now carried by its conversation, the run or the po's queue" | Both mailboxes empty. The alert's text is on tk-ctd, which stays open. |

Its log holds no other write: no `gctk bead place`, no `set-state`, no label
change and no close. Its last words were "When you say the sitting is done,
I'll close it out."

### What it shows, and what it does not

It shows work a ruling authorized reaching the pool that executes it, once,
through the `work` skill's writer, in a real city on the city's `gc`. The held
item stays the po's, and nothing is placed or prioritized. A matter with no home
becomes a conversation about its home, in the rig that holds the pack, while the
key the pack is imported under names no rig. Each pack script is found by
`gc kit scripts-dir` in its own call.

It does not show a running city. No supervisor ran, so no session started, no
polecat claimed the step the hook offers, and no nudge or wake was delivered.
The mail list came from the stand-in, which lists the messages not marked read,
and the mayor marked none read. It is one run of one model, not a rate. The
three turns took 37, 6 and 41 seconds.

The live city was the same before and after: its one Dolt server, its
supervisor and its city registry. Gas City's 956 tmux calls each met a tmux
with no server for the fixture's socket, and the one `gh` call, from a probe of
the environment before the run, was refused.

## On a stubbed city (2026-11-22)

An earlier run, of the prompt as it stood before this round's fixes, ran the
prime headless with no skills against a city of stubs, which answered every
write as a success. It covers cases the run above does not repeat:

- **An owned matter.** A refinery's report that ap-9's merge failed twice, while
  a polecat reworked ap-9: it filed nothing and slung nothing, and archived the
  report "because polecat-2 owns that fix".
- **Reads that did not answer.** A rig whose board read failed and a mail store
  that timed out: it read both again, opened with "I couldn't read the **lab**
  rig", and closed with "If it holds anything for you, it's not covered above."
- **New work for a po.** A sitting's note of an idea with no bead: it filed the
  bead held for the rig's po, `--labels hold:mayor`, and pointed the operator to
  `gc-helm po --rig app`.

Its city's pack key and rig were both named `gc-toolkit`, so it could not tell
a rig from a key, and its writes reached no store.
