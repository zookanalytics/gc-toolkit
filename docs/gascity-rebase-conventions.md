---
name: gascity rebase conventions
description: gc-toolkit's framework for rebasing local gascity commits onto upstream — default rework, dropped-absorbed semantics, force-push ownership, conflict policy.
---

# Gascity rebase conventions

When `zookanalytics/gascity:main` rebases onto `upstream/main`, local
commits meet upstream's evolution. The four rules below define how
gc-toolkit handles that meeting. They are gc-toolkit-specific because
upstream `gascity` doesn't carry a fork; this is fork-side framing.

## Default: rework intent on new upstream, don't auto-drop

When a local commit conflicts with upstream's evolution, the default
is **rework the intent on top of new upstream**, not auto-drop. Local
commits represent goals/intents, not literal implementations.

Operator stance composes from two settled positions:

- **Upstream wins on behavior choice.** Don't fight upstream's design.
  Anything truly unique and necessary lives in `gc-toolkit`, not in
  a gascity fork.
- **Local intent survives.** A perf fix, a bug fix, a feature gets
  ported onto the new upstream code — not silently dropped. The
  commit may not apply cleanly mechanically, but the *intention*
  should apply cleanly with some cleanup.

Polecats classify each conflict into one of four cases:

1. **Mechanical** — intent preserved, surrounding code shifted; relocate
   the change.
2. **Dropped-absorbed** — upstream provides the behavior or supersedes
   it; skip the commit with an audit log entry.
3. **Judgment-required** — different API or behavior choice; rework
   with operator-routed review.
4. **Infeasible** — pause-with-questions via the keeper, do not abort
   into a terminal state.

Default action is rework. Drop is only correct when upstream-side
absorption is clearly identifiable.

## Dropped-absorbed: drop the WHOLE commit

When the classification is `dropped-absorbed`, the **entire commit
goes**. Do not:

- Cherry-pick adjacent changes onto a synthetic commit.
- Back-port tests written against the now-fixed-upstream bug.
- Preserve "interesting" refactors that rode along on that commit.

The spirit of every local commit is fixing an underlying problem.
If upstream has fixed that problem, the commit's reason-for-existing
is gone, and so is everything that shipped with it. The strategic
goal is to **shrink** the surface of custom commits gc-toolkit
maintains as gascity improves — preserving bits-because-they're-nice
works against that.

If a piece of the absorbed commit genuinely has independent value
(an unrelated bug fix that got bundled), file a new bead with that
scope and let it land as a fresh commit on its own merits — don't
smuggle it through the rebase as commit-preservation.

## Force-push ownership: rebase polecat, never refinery

Rebase outcomes against `upstream/main` produce divergent history
(post-rebase `origin/main` shows N ahead, M behind in *both*
directions until the push lands). Landing that history **requires**
`git push --force-with-lease HEAD:main`. There is no fast-forward
path — that is intrinsic to rebase, not a workflow choice.

Two correct rules collide on this point. The reconciliation is *who*
does the force-push:

- **Refinery's "NEVER force-push to main/master" is absolute.** It
  handles routine feature/bugfix landings and must never destroy
  main history. Do not carve out exceptions like
  `requires_force_push=true` metadata flags. The rule stays absolute.
- **The rebase polecat owns its own `push` step.** The rebase
  formula's terminal step uses `--force-with-lease`, runs under
  `notify_recipient=overseer`, and has its own race-loss escalation
  path. That is the sanctioned channel for the force-push.

If a rebase-shaped bead ends up at `assignee=<rig>/gc-toolkit.refinery`
(or routed there), **it is a routing bug, not a refinery problem**.
The rebase polecat should own the bead through its terminal `push`
step. The fallback while the routing bug exists is escalation to
mayor and operator-gated manual force-push; the structural fix is
upstream of refinery.

## Conflict policy: must not dead-end

`abort + mail + drain` is **not an acceptable terminal outcome** for
a rebase conflict. The polecat must either:

1. **Rework the commit's intent on top of new upstream** (default,
   per the rework framing above).
2. **Pause with concrete questions** for the operator, routed
   through the gascity-keeper. Stamp metadata on the bead
   (`conflict_questions` or `rebase_in_progress`), reassign/notify
   the keeper, the keeper drives the operator conversation, and the
   polecat resumes when answers land.

The abort-and-mail shape is unacceptable because it leaves the
operator with manual git work the polecat is supposed to handle —
even when the conflict is mechanically resolvable (an anchor shift
on preserved intent). Saying "the polecat hit a conflict, here's
the backup ref, you take it from here" violates the keeper-polecat
contract and silently risks losing real work.

This stance applies to **other abort paths too** (test failure,
install failure, push race): once cooperative handback is
structural, those surface as questions to the operator, not
terminal aborts.

## Cross-references

- [`gascity-local-patching.md`](./gascity-local-patching.md) — the
  fork-setup, branch model, and sync workflow. This doc layers
  rebase-specific conventions on top.
- [`gascity-upstream-engagement.md`](./gascity-upstream-engagement.md)
  — when to engage upstream at all. Drop decisions in this doc
  presume the local patch existed for a real reason; engagement
  decisions cover whether that reason is still worth surfacing
  upstream.
