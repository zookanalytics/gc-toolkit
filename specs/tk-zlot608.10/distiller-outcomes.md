---
name: What the feedback distiller filed in its 30 runs to 2026-11-17
description: Read it to check what tk-zlot608.10's summary says about how the distiller's recent outcomes split between guidance entries and fixes in code, or to re-take the count for a later window.
---

# What the feedback distiller filed in its 30 runs to 2026-11-17

The operator's view in conversation tk-qhk9uq6 was that "the feedback distiller
is overly focused on those general lesson guidance items". This counts what the
distiller filed, to test that view against the record.

## How it was counted

A distiller run is a root bead whose `gc.formula_name` is
`mol-feedback-distiller`. The rig store holds 59, the first on 2026-08-11. The
window is the 30 runs from 2026-10-19 to 2026-11-17, one a day. A run's beads
are the ones whose `created_by` is the session its root records in
`gc.session_name`, less the `gc-toolkit__polecat-` prefix, because a pool
session with no alias writes as its session id. The count reads the rig store's
`issues` table in one query:

```sql
SELECT id, title, created_by, created_at, status,
       JSON_UNQUOTE(JSON_EXTRACT(metadata, '$.task_kind')) AS kind
FROM issues WHERE created_by IN (<the 30 sessions>) ORDER BY created_at
```

It ran through `gc bd --db <rig>/.beads sql --json` on 2026-11-18.

## What they filed

| What the runs' sessions created | Beads |
|---|---:|
| feedback patterns | 83 |
| observations | 1 |
| prompt-update proposals | 14 |
| engineering beads | 26 |

The 14 proposals name their carrier in their body. Eleven are work-quality
entries, one a conventions bullet and one an operator-profile entry, and one
amends the learning-distill rubric itself.

The 26 engineering beads are every other bead the sessions created, all in this
rig's store. 25 are tasks that name the pattern they follow up, and one is a bug
a run found in the distiller's own load step (tk-3njf5ac.1). Their titles name
fixes in skills such as the converse and engagement skills and the
architecture-document standard, in review methods such as the correctness, arch
and pm checks, in formulas, in `AGENTS.md`, in `docs/skills.md`, in a fragment,
in the capture of the city's wake nudge, in a lint and in the self-review's
warrant listing. Most of them change prose that agents read, and a few add a
check. None went to another rig's store or to a project outside the city.

## What it shows

The record does not bear out the view as a count. In these runs the distiller
filed more fixes in code than guidance entries, 25 against 13, with the rubric's
own amendment and the bug counted apart. The view holds for the rules instead.
They gave guidance entries a carrier table and three gates, and described a fix
only as "the mechanical fix (lint / doctor check / gate / code change)", with
nothing on where it goes, what its bead says, or how code another rig owns is
filed. So the distiller already sent lessons to code, and chose each place and
each bead's words with no rule to go by. tk-imdyf0d is one such bead. Its words
copied a skill's rule into a formula and put the skill out of scope.