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
3. **Judgment-required** — different API or behavior choice; make the
   call and record the reasoning in the `metadata.conflict_resolutions`
   audit entry so it is reviewable after the fact.
4. **Infeasible** — pause-with-questions via the keeper, do not abort
   into a terminal state.

Default action is rework. Drop is only correct when upstream-side
absorption is clearly identifiable.

The classification is a judgment you make inside your own turn. It is no
longer routed structure: `mol-upstream-gc-rebase` v12 resolves conflicts
inline in its check loop (below) instead of dispatching a rework polecat
per conflict and a review polecat per judgment call.

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

### The rebase step is a check loop

`mol-upstream-gc-rebase` v12 runs its `rebase` step as a `[steps.check]`
loop. Each `iteration.N` is a separate bead with a separate session, so
every conflict is met with fresh context, and the loop appends the next
iteration automatically when its exit condition
(`assets/scripts/rebase-check.sh`) fails. That condition passes only when
the rebase is finished, the worktree is clean, HEAD sits on top of
`metadata.rebase_onto_sha`, and `metadata.check_passed_sha` equals the
live HEAD.

What this means for you as a polecat driving an iteration:

- **Resume, don't restart.** The worktree at `metadata.work_dir` may be
  mid-rebase from a previous iteration. Read the state, don't assume you
  are first.
- **Close your iteration bead when you stop.** Closing it is what runs
  the exit condition. Do not drain-and-park and do not hand the bead back
  to the keeper mid-loop — those were the v11 mechanisms.
- **You do not have to finish.** Leaving the rebase further along than
  you found it is a complete iteration.
- **Never fake progress to escape the loop.** Do not `git rebase --skip`
  a commit you did not judge absorbed, and never `git rebase --abort` —
  the abort discards every prior iteration's work, and the exit
  condition's ancestry check is specifically there to catch it.

Budget exhaustion (`max_attempts`) closes the control bead
`gc.outcome=fail` and leaves `install`/`push` blocked. That is the
escalation signal for a rebase the loop could not finish.

### Conflict policy: must not dead-end

`abort + mail + drain` is **not an acceptable terminal outcome** for
a rebase conflict. The polecat must either:

1. **Rework the commit's intent on top of new upstream** (default,
   per the rework framing above).
2. **Pause with concrete questions** for the operator, routed
   through the gascity-keeper. Stamp `metadata.conflict_questions` on
   the bead, leave the rebase where it stands, and let the loop
   exhaust — the keeper drives the operator conversation from the
   recorded questions and the control bead's `gc.outcome=fail`.

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

- The issue has `metadata.work_dir` and `metadata.commit_verdicts` set,
  and that worktree is genuinely mid-rebase or mid-gate (v11's
  `metadata.rebase_in_progress` flag is no longer written — check the
  worktree, not the flag).
- The fresh root's `gc.var.issue` points at that same issue.
- The issue carries the keeper's hand-off token and it matches your
  root: `metadata.resume_handoff` on the issue equals
  `gc.var.resume_handoff` on the fresh root, exact string match.

The token is what makes proceeding provably safe. The three state
conditions above are also true for a spurious re-dispatch that fires
while an earlier polecat is still driving the rebase — state alone
cannot tell a deliberate hand-off from a re-fire, and proceeding on a
re-fire risks a concurrent `git rebase --continue` and a double
force-push to main. The keeper mints `resume_handoff` only at its
deliberate re-pour — the moment it steps back from the rebase — and
threads the same value through the sling, so only the wisp it poured
right then can match. No token, or a token that doesn't match yours:
**park**, even with every state condition satisfied. A legitimate
resume never loses out — the keeper's next deliberate re-pour mints a
fresh token.

Once you commit to the resume — before entering the worktree or
driving the rebase — consume the token with
`gc bd update <issue> --unset-metadata resume_handoff`, so a
subsequent re-fire finds no token and parks.

This resume is safe because the formula is guarded for exactly this
case. `workspace-setup` checks `metadata.work_dir` first, changes into
that worktree, and skips creating a from-scratch worktree. `survey`
checks `metadata.commit_verdicts` first and skips re-surveying. The
rebase step's first act is to read the worktree and decide whether it is
starting fresh, resuming mid-rebase, or only owes the quality gate — the
same branch every iteration of the check loop takes. There is no
from-scratch survey and no restart that destroys prior conflict work.

Note that a *conflict* no longer needs a re-pour at all: the check loop
appends its own next iteration. This section covers the remaining case
where a whole rebase run was lost (session death, operator re-pour), not
the per-conflict path.

Still park a true duplicate: a second fresh root for an issue whose
worktree shows no paused rebase, or two fresh roots
racing before any `metadata.work_dir` exists, or any root whose
`gc.var.resume_handoff` is absent or doesn't match the issue's current
`metadata.resume_handoff`. A concurrent live polecat
on the same worktree is the separate `polecat-patterns`
worktree-reclaim/liveness concern, not this rule.
{{ end }}
