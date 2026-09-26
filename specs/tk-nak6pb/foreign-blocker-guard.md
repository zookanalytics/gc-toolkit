---
name: foreign-blocker guard for pr-facts.sh's stale-base dispatch arm
description: Why the stale-base arm gates on a foreign-blocker predicate rather than bd-ready, and how it tells its own rework children from a real hold.
---

# The stale-base arm dispatched blind to blockers other than a demand

pr-facts.sh's CONFLICTING/stale-base arm mints a rebase/rework child when a
PR's branch no longer merges into its target. tk-rj8foi (#571) gave it a demand
guard: `takeaway_is_holding` skips the dispatch when an open `gc.demand_for`
gate holds the anchor, because "rebase onto the base" is routinely one horn of
the decision a demand asks.

That guard reads only the demand channel. An anchor can be held by other things.
The live occurrence this bead fixes: anchor tk-iguy2a (PR#787) was blocked by a
plain depends-on edge on tk-o0rkot (a restructure that will fold #787's class of
work). Its demand tk-nua2k6 had already been closed with the operator's "go"
ruling, so `takeaway_is_holding` read nothing, and the arm minted rebase child
tk-8lu4qc anyway — a rebase of a branch the operator's plan was about to
restructure.

# Why not "gate on bd-ready"

The obvious generalization — skip when the anchor is not `bd ready` (has any
open blocker) — is wrong here. The arm's OWN rework children block their anchor:
that blocks edge is how the merge waits for the fix. So an anchor with a live,
stranded, or orphaned rework child is never `bd ready`, and a bd-ready gate
would bury the dedup, stranded-re-route, and orphan-adoption the arm must still
perform. The distinction the guard needs is not "blocked / not blocked" but
"held by something that is not this arm's own work."

# The predicate: a foreign blocker

`anchor_foreign_blocker <anchor> <own-branch> <own-title>` walks the anchor's
live down-blocks edges (the same edges merge.sh holds the merge on) and skips
the dispatch when any blocker is *foreign* — not one of the arm's own children.

A blocker is the arm's own child if the dispatch below would recognize it, by
the same three signals the dispatch uses to find its children:

- it is on the anchor's branch (`metadata.branch` — the dedup key), OR
- it carries the anchor's rework marker (`task_kind=rework`,
  `anchor_bead=<anchor>`), OR
- its title contains the deterministic dispatch title the orphan adoption
  matches (`--title-contains "$FIX_TITLE"`).

Three signals rather than one because a child's stamp can half-land: a dropped
route keeps all three, a dropped role marker keeps branch and title, a fully
dropped stamp keeps only the title from `gc bd create`. Any one surviving means
the guard never reads a child whose stamp partly failed as a foreign freeze.

The cap's own demand (`gc.takeaway_by=signoff`) is excluded, for the same reason
`takeaway_is_holding` excludes it: reading the park's own record as a hold would
wedge the park. The guard fails closed — an unreadable edge list holds the
dispatch, the safe side for a rewrite. It is placed after `FIX_TITLE` is
resolved (the orphan-title signal needs it) and before the dedup.

# Disposition of the live instance

tk-8lu4qc (the wrongly-minted child) is neutralized: it is blocked on tk-o0rkot,
so it is out of `bd ready` and the pool will not serve it. Once this guard is on
main, close it as superseded — closing it earlier only lets the still-blind main
mint a fresh one, since the anchor stays blocked on tk-o0rkot.

# Related, filed separately

The comment-rework and red-check arms guard the demand channel and operator
holds but not general foreign blockers — the same class, one arm over. Filed as
tk-l7dka5, not folded in here: those arms push commits rather than rewrite a
branch, so the severity differs and the fix is a separate judgement.
