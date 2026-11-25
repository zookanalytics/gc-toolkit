---
name: Placement hold exercise on the installed runtime (tk-1tfzr71.233)
description: What an isolated city driven by the city's installed gc, fork main 13cdf670ca, showed for this branch on 2026-11-25 - the hold:po and hold:mayor beads the hook withholds, the po's queue read and gctk bead stands, gctk bead move-placement-hold's dry run, runs and refusals, gctk bead place sending hold:po and hold:mayor work to a pool through gc sling, and the hook serving it. Read it when reviewing whether old and new placement labels stay held and visible until placement, or when repeating the exercise.
---

# Placement hold exercise on the installed runtime

Run on 2026-11-25 between 02:25Z and 02:45Z, from a scratch directory, with the
`gc` the city runs (`gc version` 1.4.3, commit 13cdf670ca, fork main with
gc-uyshxy), bd 1.3.4, and `gctk` built from this
branch. The recipe is the one tk-1tfzr71.234 used: every command ran through `env -i`
with its own `HOME` and `GC_HOME`, `GC_ISOLATED=1` and `GC_NO_API=1`, a
`supervisor.toml` naming an API port nothing listens on, and `launchctl`,
`systemctl` and `tmux` replaced by logging shims. `gc init --no-start
--template minimal` made the city `hpfx` (prefix `hq`), with its mayor
removed, and `gc rig add` made the rig `r1`, bound to a local pack `fx` whose
one agent is a pool, `r1/fx.polecat`, on `mol-do-work`. No supervisor ran for
it, and nothing started a session. The live supervisor reported the same build
and one city before and after, and the live Dolt servers kept their pids.

## The beads

| Bead | Labels | Route | Stands for |
|---|---|---|---|
| r1-ecw | `hold:po`, by `bd set-state` | none | new work intake holds |
| r1-7pd | `hold:mayor` | none | work held before the move |
| r1-7gl | `hold:mayor`, `hold:po` | none | a bead on both spellings |
| r1-ukj | `hold:external`, `hold:mayor` | none | a second hold beside the placement hold |
| r1-4bg | `hold:release-train` | none | a hold of the pack's own |
| r1-bun | `hold:mayor` | `r1/fx.mayor` | a route to an agent named mayor |
| r1-2cp | `hold:mayor`, closed | none | a closed record |
| r1-tvd | none | `r1/fx.polecat` | unheld routed work, the control |
| r1-bj3 | `hold:po` | `r1/fx.polecat` | a route does not beat `hold:po` |
| r1-p5o | `hold:mayor` | `r1/fx.polecat` | a route does not beat `hold:mayor` |
| hq-fd6 | `hold:mayor` | none | the HQ store's queue |

## What each step showed

1. **The runtime withholds both spellings.** `gc hook r1/fx.polecat` served
   r1-tvd alone. r1-bj3 and r1-p5o, routed to the same pool, were withheld by
   `hold:po` and by `hold:mayor`.
2. **The queue shows both spellings, and no other hold.** The po's queue read
   (the jq in `agents/po/prompt.template.md`, over `gc beads list
   --format=json`) listed r1-7gl, r1-7pd, r1-bj3, r1-bun, r1-ecw, r1-p5o and
   r1-ukj, and not r1-4bg, r1-2cp or r1-tvd. `gctk bead stands` answered
   `for-product-owner` for r1-ecw, r1-7pd and r1-7gl, the rule the board's
   Unprioritized page reads, `not-ready` for r1-4bg and `scheduled` for r1-tvd.
3. **The move's dry run writes nothing and names what it would do.**
   `gctk bead move-placement-hold --dry-run` exited 1. It would move hq-fd6,
   r1-7gl and r1-7pd, counted r1-ecw and r1-bj3 on `hold:po` already, and left
   three beads, each with the write a person makes: r1-bun as the doctor
   repair's route ("Clear the route"), r1-p5o as a route a writer chose ("Place
   it with gctk bead place, or clear the route"), and r1-ukj for its
   `hold:external` ("Move its placement hold by hand", naming
   `gc bd update r1-ukj --add-label hold:po --remove-label hold:mayor`).
   Review changed how a route is named after this run. The doctor repair wrote
   only `mayor` or a binding's `mayor` with no rig, so a rig-qualified route
   such as r1-bun's is now named as one a writer chose, the same as r1-p5o's.
   A route of the repair's shape is named as one it may have written, since a
   writer can choose it too, with `gc bd history <bead> --events` to read who
   set it before it is cleared (`TestAMoveTakesTheQueueOntoHoldPO`, tk-repair
   and tk-chosen).
4. **The move writes through set-state, and a second run writes nothing.** The
   first run moved the same three and left the same three, exit 1. The second
   moved none, counted four r1 beads and hq-fd6 on `hold:po`, and left the same
   three. Each moved bead carries one closed event bead, "State change: hold →
   po", whose description reads "Changed hold from mayor to po" and the move's
   reason. r1-7gl ended on `hold:po` alone, and r1-2cp, closed, kept
   `hold:mayor`. Review changed the move's write after this run. It is now one
   `gc bd update <bead> --add-label hold:po --remove-label hold:mayor`, which
   keeps a hold another writer adds before the write lands, and bd's history
   records its two label changes in place of an event bead. The move's store
   acceptance case pins it against bd 1.3.4
   (`TestStoreAcceptanceAMoveTakesTheQueueOntoHoldPO`).
5. **The named writes finish the move.** Clearing r1-bun's route and making
   r1-ukj's named update left a third run to move r1-bun and leave r1-p5o, the
   person's call.
6. **Placement sends both spellings on, and refuses what it must not lift.**
   With `GCTK_SCRIPTS_DIR` naming this branch's scripts and `GC_CITY_PATH` the
   fixture city, as a session has them, `gctk bead place --standalone`:
   - placed r1-ecw: `queue-priority.sh settle`, then `gc sling` to
     `r1/fx.polecat`, which poured `mol-do-work` as r1-cly, then the lift,
     printing "hold:po lifted";
   - placed r1-p5o: it cleared the route the bead carried while held, slung it
     (r1-heg) and printed "hold:mayor lifted";
   - refused r1-ukj, exit 2, because `hold:external` would keep it held;
   - refused r1-4bg, exit 2, because it carries no `hold:po`. The refusal
     then named `gc bd set-state r1-4bg hold=po`, which would have swapped its
     `hold:release-train` out, since set-state swaps a bead's first `hold:`
     label. Self-review changed it after this run: a bead another hold holds
     and no placement hold is refused naming that hold, with no set-state
     (`TestPlaceRefusesWhatItDoesNotPlace`, "another hold and no placement
     hold").
7. **The pool is served what was placed.** `gc hook r1/fx.polecat` then served
   r1-tvd and the do-work steps of r1-cly and r1-heg, and nothing still held.
   `gc hook r1/fx.polecat --claim` claimed r1-tvd.
8. **The move then finishes.** With r1-p5o placed, a last
   `gctk bead move-placement-hold` read both stores, moved nothing, left
   nothing and exited 0.

Not exercised here: a live controller's wake, keep-awake and route-restore
lanes, which tk-1tfzr71.234 left out for the same reason, and the board's own
render, whose Go read the branch's tests cover with both spellings and a hold
of the pack's own (`services/helm/internal/rigboard`).
