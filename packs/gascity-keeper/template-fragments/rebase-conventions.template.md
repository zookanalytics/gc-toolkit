{{ define "rebase-conventions" }}
## Gascity rebase conventions

When `zookanalytics/gascity:main` rebases onto `upstream/main`, local
commits meet upstream's evolution. The four rules below define how
gc-toolkit handles that meeting. They are gc-toolkit-specific because
upstream `gascity` doesn't carry a fork; this is fork-side framing.

This fragment ships with the `gascity-keeper` sub-pack and is injected
only into agents in rigs that import that sub-pack (the gascity rig
today). The core gc-toolkit refinery and polecat prompts do not carry
these rules.

### Default: rework intent on new upstream, don't auto-drop

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

### Dropped-absorbed: drop the WHOLE commit

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

### Force-push ownership: rig-scoped refinery, not core refinery

Rebase outcomes against `upstream/main` produce divergent history
(post-rebase `origin/main` shows N ahead, M behind in *both*
directions until the push lands). Landing that history **requires**
`git push --force-with-lease HEAD:main`. There is no fast-forward
path — that is intrinsic to rebase, not a workflow choice.

Two correct rules collide on this point. The reconciliation is *who*
does the force-push:

- **Core gc-toolkit refinery's "NEVER force-push to main/master" is
  absolute.** It handles routine feature/bugfix landings and must
  never destroy main history. Do not carve out exceptions like
  `requires_force_push=true` metadata flags. The rule stays absolute
  in the core prompt.
- **The gascity-flavored refinery owns the rebase tail.** The
  `gascity-keeper` sub-pack's refinery overlay (see the
  `refinery-rebase-handling` fragment) detects rebase-shaped beads
  via `metadata.molecule_id` (matching `mol-upstream-gc-rebase*`,
  with `metadata.backup_ref` as fallback) and OWNS the
  `git push --force-with-lease HEAD:main` step for them. The
  exception lives in this rig-scoped overlay, not in the polecat
  formula's terminal `push` step.
- **Polecat hands the bead to refinery like every other polecat.**
  The rebase polecat (running `mol-upstream-gc-rebase`) no longer
  carries its own terminal force-push: it pushes the working
  branch, sets `metadata.target = main` and the rebase-bead
  metadata, and reassigns to refinery. Refinery performs the
  force-push under the overlay's authorisation.

If a rebase-shaped bead lands at a refinery that does NOT carry the
gascity overlay (i.e., a refinery in a rig that doesn't import the
`gascity-keeper` sub-pack), refinery escalates to mayor instead of
force-pushing. That preserves PR #17's defensive intent for the
mis-routed case while keeping the legitimate path automated for the
intended case.

### Conflict policy: must not dead-end

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

This stance applies to **other abort paths too** (check failure,
install failure, push race): once cooperative handback is
structural, those surface as questions to the operator, not
terminal aborts.

### Re-pour over a paused rebase is resume, not duplicate dispatch

When you claim `load-context` for a fresh `mol-upstream-gc-rebase`
root and the issue already has a rebase in progress, treat that as
the formula's designed resume path. **Proceed; do not park it as a
duplicate dispatch** when all of these are true:

- The issue has `metadata.rebase_in_progress=true`,
  `metadata.work_dir` set, and `metadata.commit_verdicts` set.
- The fresh root's `gc.var.issue` points at that same issue.
- `metadata.pending_rework` is unset or points to a closed rework bead.

This resume is safe because the formula is guarded for exactly this
case. `workspace-setup` checks `metadata.work_dir` first, changes into
that worktree, and skips creating a from-scratch worktree. `survey`
checks `metadata.commit_verdicts` first and skips re-surveying. The
rebase step reads the closed `metadata.pending_rework` and, for
mechanical rework, runs `git -c core.editor=true rebase --continue`.
There is no from-scratch survey, no restart that destroys the rework
fix, and no second force-push track from the original polecat: the
original polecat drained when it handed `pending_rework` to the keeper.

Still park a true duplicate: a second fresh root for an issue with no
paused rebase or no `metadata.rebase_in_progress`, or two fresh roots
racing before any `metadata.work_dir` exists. A concurrent live polecat
on the same worktree is the separate `polecat-patterns`
worktree-reclaim/liveness concern, not this rule.
{{ end }}
