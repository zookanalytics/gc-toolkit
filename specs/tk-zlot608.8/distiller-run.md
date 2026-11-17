---
name: A distiller run of gctk memory against a scratch memory directory (tk-zlot608.8)
description: The record of one run of the memory intake's verbs as mol-feedback-distiller's steps call them, built from this branch, with Claude Code asked where each of the city's places keeps memory under a scratch config directory and the live bead store read only. Read it to see what gctk memory prints, what it does to a directory, its index and a collection note, what it hands the judge, and how a wait ends.
---

# A distiller run of gctk memory against a scratch memory directory

The run took this branch's `gctk`, built from the tree of the commit that adds
this record, and called its verbs as the distiller's steps do: read-memory's
`gctk memory settle`, load-and-gate's `gctk memory due --limit 200`, decision
lines as judge-and-cluster writes them, and file-and-dispatch's `gctk memory
apply`. It ran in the home rig's checkout, against the live city: `gc rig list`
named the city's seven places, and the bead store was read only.

Claude Code 2.1.326 was asked in each place, with `CLAUDE_CONFIG_DIR` set to a
scratch directory, so each answer named a directory under it (`<cfg>`), and no
real memory directory was read. The scratch config holds no sign-in, so each
ask's turn failed after its init record, which the ask reads, and no model call
was made. Each ask made its place's directory, and the adapter removed it again,
which is why the second settle still finds six places with none. The home rig's
directory was then made and seeded with six notes in Claude Code's front matter,
an index and a collection note. `GCTK_SCRIPTS_DIR` named a stub
`patrol-finding.sh` that only logged its calls. The state directory was the
city's own, `<state>`, which held nothing before the run and was removed after
it.

The waits are on live beads: tk-7p37ddd, an open feedback pattern; tk-0rhvews,
a closed pattern whose proposal, tk-r307gbq, merged on main; and tk-g7cn1bd, a
prompt-update that closed with no merge.

```text
=== settle, before the home rig has a memory directory
loomington: no memory directory at <cfg>/projects/-Users-gc-Code-loomington/memory/
gc-toolkit: no memory directory at <cfg>/projects/-Users-gc-Code-loomington-rigs-gc-toolkit/memory/
signal-loom: no memory directory at <cfg>/projects/-Users-gc-Code-loomington-rigs-signal-loom/memory/
gascity: no memory directory at <cfg>/projects/-Users-gc-Code-loomington-rigs-gascity/memory/
shutupandlisten: no memory directory at <cfg>/projects/-Users-gc-Code-loomington-rigs-shutupandlisten/memory/
sprintshow: no memory directory at <cfg>/projects/-Users-gc-Code-loomington-rigs-sprintshow/memory/
growth-factor: no memory directory at <cfg>/projects/-Users-gc-Code-loomington-rigs-growth-factor/memory/
waits ended: 0 units removed with a fix landed, each one's text kept; 0 units due again with no fix landed
exit 0

=== settle, with the home rig's directory seeded
loomington: no memory directory at <cfg>/projects/-Users-gc-Code-loomington/memory/
signal-loom: no memory directory at <cfg>/projects/-Users-gc-Code-loomington-rigs-signal-loom/memory/
gascity: no memory directory at <cfg>/projects/-Users-gc-Code-loomington-rigs-gascity/memory/
shutupandlisten: no memory directory at <cfg>/projects/-Users-gc-Code-loomington-rigs-shutupandlisten/memory/
sprintshow: no memory directory at <cfg>/projects/-Users-gc-Code-loomington-rigs-sprintshow/memory/
growth-factor: no memory directory at <cfg>/projects/-Users-gc-Code-loomington-rigs-growth-factor/memory/
gc-toolkit: <cfg>/projects/-Users-gc-Code-loomington-rigs-gc-toolkit/memory, 6 notes and 1 entries
waits ended: 0 units removed with a fix landed, each one's text kept; 0 units due again with no fix landed
exit 0

=== load-and-gate's seed: gctk memory due --limit 200
exit 0
  66eef4ddd3174a4e/stale.md@402c9fc31cf1cbc6  note  new  2026-11-17
  66eef4ddd3174a4e/lesson.md@8a0350642813fc84  note  new  2026-11-17
  66eef4ddd3174a4e/moment.md@7d914642e0ea3563  note  new  2026-11-17
  66eef4ddd3174a4e/unsure.md@24fcff3f95158dc1  note  new  2026-11-17
  66eef4ddd3174a4e/landed.md@5bc9a1c0b16a84b7  note  new  2026-11-17
  66eef4ddd3174a4e/ended.md@2c1e0985f40e919e  note  new  2026-11-17
  66eef4ddd3174a4e/hub-topics.md@3489795453a0215e  entry  new  2026-11-17

=== judge-and-cluster's decision lines
66eef4ddd3174a4e/stale.md@402c9fc31cf1cbc6 drop
66eef4ddd3174a4e/lesson.md@8a0350642813fc84 waits tk-7p37ddd
66eef4ddd3174a4e/moment.md@7d914642e0ea3563 next 2026-11-24
66eef4ddd3174a4e/unsure.md@24fcff3f95158dc1 next 2026-12-15 ask-use
66eef4ddd3174a4e/landed.md@5bc9a1c0b16a84b7 waits tk-0rhvews
66eef4ddd3174a4e/ended.md@2c1e0985f40e919e waits tk-g7cn1bd
66eef4ddd3174a4e/hub-topics.md@3489795453a0215e waits tk-7p37ddd

=== file-and-dispatch: gctk memory apply <the decisions file>
removed 66eef4ddd3174a4e/stale.md@402c9fc31cf1cbc6, its text kept at <state>/66eef4ddd3174a4eedeb3f2f729f8e1f9b58edcc1872ade3bca820cc753ddd5d/removed/stale.md@402c9fc31cf1cbc6012a2360ab7aee11b49004b5fc60df9358484bdefaf1eb2e
recorded 66eef4ddd3174a4e/lesson.md@8a0350642813fc84: waits on tk-7p37ddd
recorded 66eef4ddd3174a4e/moment.md@7d914642e0ea3563: due again on 2026-11-24
recorded 66eef4ddd3174a4e/unsure.md@24fcff3f95158dc1: due again on 2026-12-15, with a request to record the days it is used, one line a day
recorded 66eef4ddd3174a4e/landed.md@5bc9a1c0b16a84b7: waits on tk-0rhvews
recorded 66eef4ddd3174a4e/ended.md@2c1e0985f40e919e: waits on tk-g7cn1bd
recorded 66eef4ddd3174a4e/hub-topics.md@3489795453a0215e: waits on tk-7p37ddd
exit 0

=== the directory, the index and the collection note after apply
ended.md
hub-topics.md
landed.md
lesson.md
MEMORY.md
moment.md
unsure.md

# Memory Index

- [Lesson](lesson.md) — formula copies
- [Moment](moment.md) — #1486
- [Unsure](unsure.md) — loaded host
- [Landed](landed.md) — fix filed
- [Ended](ended.md) — declined
- [Topics](hub-topics.md) — bd calls

# Topics

- (no file) Prefer one gc bd show with many ids to one call per id.

=== unsure.md now asks for its uses
Run the slow suites last when the host is loaded.
<!-- memory-intake: use --> When this note steers your work and holds no used line for today, add one at its end: used <YYYY-MM-DD>: <what it changed>

=== the list
#memory-intake list 1	kind	name	hash	judged	wait	next	why
note	ended.md	3ad2417f6b70adc9da0d4c2853c5fc9578bcd57b413ba0ab1c25466be3387774	2026-11-17T02:44:51Z	tk-g7cn1bd		
entry	hub-topics.md	3489795453a0215e3ebc6c85b404585dce44e53eb174bab63dc479f168959397	2026-11-17T02:44:51Z	tk-7p37ddd		
note	landed.md	958bb934f496f051a37a6528da4cea6fe34668b3a9cd63fa0647ba050a6c546d	2026-11-17T02:44:51Z	tk-0rhvews		
note	lesson.md	4b47fbc3d054db22553757008d69f6d875ff3e468663d9101230bd33037926e7	2026-11-17T02:44:51Z	tk-7p37ddd		
note	moment.md	4bc61834893881a5292aa42df473119a5a3da41504355d17a11dead086359695	2026-11-17T02:44:51Z		2026-11-24	
note	unsure.md	0ada3a688b058e79bf93eb276134667635266e02cf9dc40cb1648d938b86c8ec	2026-11-17T02:44:51Z		2026-12-15	

=== settle: tk-0rhvews closed with its proposal merged on main, tk-g7cn1bd closed with no merge, tk-7p37ddd open
loomington: no memory directory at <cfg>/projects/-Users-gc-Code-loomington/memory/
signal-loom: no memory directory at <cfg>/projects/-Users-gc-Code-loomington-rigs-signal-loom/memory/
gascity: no memory directory at <cfg>/projects/-Users-gc-Code-loomington-rigs-gascity/memory/
shutupandlisten: no memory directory at <cfg>/projects/-Users-gc-Code-loomington-rigs-shutupandlisten/memory/
sprintshow: no memory directory at <cfg>/projects/-Users-gc-Code-loomington-rigs-sprintshow/memory/
growth-factor: no memory directory at <cfg>/projects/-Users-gc-Code-loomington-rigs-growth-factor/memory/
gc-toolkit: <cfg>/projects/-Users-gc-Code-loomington-rigs-gc-toolkit/memory, 5 notes and 1 entries
waits ended: 1 unit removed with a fix landed, each one's text kept; 1 unit due again with no fix landed
exit 0

=== due after the settle
  ended.md  date  2026-10-31T00:00:00Z  prior: waited on tk-g7cn1bd, which closed with no merge: not needed, per tk-vhk169l in rig:gc-toolkit — PR#1360 closed not-needed (disposition pre-recorded before the close)

=== the index after the settle, and the texts kept
# Memory Index

- [Lesson](lesson.md) — formula copies
- [Moment](moment.md) — #1486
- [Unsure](unsure.md) — loaded host
- [Ended](ended.md) — declined
- [Topics](hub-topics.md) — bd calls

landed.md@5bc9a1c0b16a84b7…
stale.md@402c9fc31cf1cbc6…

=== the finding writer was called with
   4 patrol-finding.sh --scope memory-intake --key memory-intake.places --cleared --message The memory intake learns every place's memory directory again.
```
