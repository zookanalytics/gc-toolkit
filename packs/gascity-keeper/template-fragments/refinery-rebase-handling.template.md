{{ define "refinery-rebase-handling" }}
## Rebase-bead handling (gascity overlay)

This section is injected by the `gascity-keeper` sub-pack — present only
in rigs that import that pack. The core refinery prompt's "NEVER
force-push to `main`/`master`" rule still applies as the default; the
exception below carves out a *narrow* legitimate path for the
`mol-upstream-gc-rebase` family and that family only.

### Detection: is this a rebase bead?

A rebase bead is one whose source molecule belongs to the
`mol-upstream-gc-rebase*` family. Walk metadata in this order; first
match wins:

1. **`metadata.molecule_id`** — read the molecule wisp's title
   and check whether it starts with `mol-upstream-gc-rebase`:

   ```bash
   MOL_ID=$(gc bd show "$WORK" --json | jq -r '.[0].metadata.molecule_id // empty')
   if [ -n "$MOL_ID" ]; then
     MOL_NAME=$(gc bd show "$MOL_ID" --json 2>/dev/null | jq -r '.[0].title // empty')
     case "$MOL_NAME" in
       mol-upstream-gc-rebase|mol-upstream-gc-rebase-rework) IS_REBASE=1 ;;
       *) IS_REBASE=0 ;;
     esac
   fi
   ```

   `mol-upstream-gc-pr-prep` and `mol-upstream-gc-sync` are NOT rebase
   beads — they do not produce divergent history against `main` and
   must follow the standard refinery flow (no force-push).

2. **`metadata.backup_ref`** — fallback signal. The rebase formula's
   workspace-setup step stamps `metadata.backup_ref` with the
   pre-rebase tip so the operator can range-diff after landing. If
   step 1 didn't match (e.g., the molecule bead was burned before
   refinery picked the work up), the presence of `backup_ref`
   together with `metadata.target = main` is treated as evidence
   that the bead came from a rebase formula:

   ```bash
   BACKUP=$(gc bd show "$WORK" --json | jq -r '.[0].metadata.backup_ref // empty')
   TARGET=$(gc bd show "$WORK" --json | jq -r '.[0].metadata.target // empty')
   if [ "$IS_REBASE" != "1" ] && [ -n "$BACKUP" ] && [ "$TARGET" = "main" ]; then
     IS_REBASE=1
   fi
   ```

Anything else is NOT a rebase bead. Continue with the standard merge
flow (no force-push, ever).

### Procedure: landing a rebase bead

When `IS_REBASE=1`:

1. **Fetch and verify `origin/main` is still at the pre-rebase tip.**
   Refuse to land a stale working branch — the rebase polecat may have
   completed against an older `upstream/main` than what's now on
   origin. The rebase formula stamps `metadata.pre_rebase_tip` (and
   `metadata.backup_ref`) at workspace-setup with the SHA of
   `origin/main` it observed before rewriting history. Compare the
   current `origin/main` tip against that recorded SHA:

   ```bash
   git fetch --prune origin
   BRANCH=$(gc bd show "$WORK" --json | jq -r '.[0].metadata.branch')
   git checkout "$BRANCH"

   PRE_REBASE_TIP=$(gc bd show "$WORK" --json \
     | jq -r '.[0].metadata.pre_rebase_tip // .[0].metadata.backup_ref // empty')
   if [ -z "$PRE_REBASE_TIP" ]; then
     echo "ERROR: rebase bead $WORK missing metadata.pre_rebase_tip/backup_ref — cannot verify race-loss safely" >&2
     # Refuse to push; escalate via the same race-loss path below.
     exit 1
   fi

   # PRE_REBASE_TIP may be a SHA or a refname (e.g. refs/backup/main-pre-rebase).
   PRE_REBASE_SHA=$(git rev-parse "$PRE_REBASE_TIP^{commit}")
   CURRENT_MAIN_SHA=$(git rev-parse origin/main)
   ```

   Why not `git rev-list --left-right --count "$BRANCH...origin/main"`
   with an expected `main-ahead = 0`? A history-rewriting rebase
   replaces the OLD `origin/main` commits with new SHAs. The old
   commits stay reachable from `origin/main` but are not reachable
   from the rebased branch, so they show up as right-only in the
   symmetric difference even when nothing raced — `main-ahead > 0`
   is the steady state for a clean rebase, not a race indicator.
   Comparing `origin/main` to the recorded `pre_rebase_tip` is the
   correct test: equal means no race, unequal means another change
   landed.

   If `PRE_REBASE_SHA != CURRENT_MAIN_SHA`, **another change landed on
   `main` after the polecat finished its rebase** — see Race loss
   below.

2. **Run preflight against the rebased branch** (not against `main`,
   since the rebased branch IS the new history we're about to land):

   ```bash
   # Tests, build, lint — whatever the rig's formula_vars specify.
   # Run as the merge polecat would; rebase polecat already ran them
   # at push time but a fresh run here closes the time-of-check /
   # time-of-use window.
   ```

   If preflight fails on a rebase bead, do NOT push. Reject the bead
   back to the polecat pool with `rejection_reason="rebase preflight
   failed: <summary>"` and leave the branch intact so the polecat can
   resume from it.

3. **Force-push with lease to main.** This is the authorised
   exception to the core "NEVER force-push to `main`" rule:

   ```bash
   git push --force-with-lease=main:"$PRE_REBASE_SHA" origin "$BRANCH:main"
   ```

   The expected-value form `--force-with-lease=main:"$PRE_REBASE_SHA"`
   uses the SHA the rebase polecat saw before rewriting history (the
   `metadata.pre_rebase_tip` resolved above), NOT the just-fetched
   `origin/main`. Using `origin/main` as the expected value defeats
   the protection: the preceding `git fetch --prune origin` already
   updated the local `origin/main` ref, so the lease form
   `--force-with-lease=main:origin/main` would compare the remote tip
   to itself and ALWAYS pass — a genuine race that landed between
   rebase-finish and refinery-push would not be detected.

   Pinning the lease to `$PRE_REBASE_SHA` ensures the push only lands
   if `origin/main` is still at the tip the rebase polecat observed.
   This is the safety net that converts a silent race into a refused
   push.

4. **Sync the rig's local main checkout to the new tip.** The
   force-push above advanced `origin/main`, but the rig's checkout
   at `<rig-root>` is still on the OLD divergent `main` and won't
   reflect the new history until something updates it. The operator
   builds from and references that checkout — leaving it stale after
   every rebase landing is the bug this step fixes.

   Safety is skip-and-report: only reset when the rig is on `main`,
   clean, AND its HEAD still matches the pre-rebase tip the polecat
   observed (`$PRE_REBASE_SHA` from step 1). If it's on a feature
   branch, has dirty state, has drifted to a different `main` tip
   (unpublished commits, divergent ancestor), or if `fetch`/`reset`
   itself fails, record the skip/error in `metadata.rig_update_result`
   so the close notification (step 5) tells the operator to sync
   manually. Never surprise WIP, never silently discard local commits,
   and never report a sync that didn't actually happen.

   ```bash
   # GC_RIG is set in rig-bound sessions. Fall back to gascity —
   # that's the only rig importing gascity-keeper today.
   RIG_NAME="${GC_RIG:-gascity}"
   RIG_ROOT=$(gc rig list --json \
       | jq -r '.rigs[] | select(.name=="'"$RIG_NAME"'") | .path')

   if [ -z "$RIG_ROOT" ] || [ ! -d "$RIG_ROOT" ]; then
       RIG_UPDATE_RESULT="skipped: rig $RIG_NAME not resolvable"
   elif ! git -C "$RIG_ROOT" fetch --prune origin >/dev/null 2>&1; then
       # Don't claim a sync when we never saw the new origin/main —
       # otherwise we could reset to a stale tip and record
       # `reset: old -> old` while the rig is still on the old history.
       RIG_UPDATE_RESULT="skipped: fetch origin failed in $RIG_ROOT (operator must sync)"
   else
       CURRENT_BRANCH=$(git -C "$RIG_ROOT" rev-parse --abbrev-ref HEAD)
       DIRTY_COUNT=$(git -C "$RIG_ROOT" status --porcelain | wc -l)
       CURRENT_HEAD_SHA=$(git -C "$RIG_ROOT" rev-parse HEAD)

       if [ "$CURRENT_BRANCH" != "main" ] || [ "$DIRTY_COUNT" -ne 0 ]; then
           RIG_UPDATE_RESULT="skipped: branch=$CURRENT_BRANCH dirty=$DIRTY_COUNT (operator must sync)"
       elif [ "$CURRENT_HEAD_SHA" != "$PRE_REBASE_SHA" ]; then
           # Clean local main, but HEAD is not at the pre-rebase tip
           # the polecat saw. Could be unpublished local commits or a
           # divergent ancestor — `reset --hard origin/main` would
           # silently discard them. Skip and report.
           OLD_SHORT=$(git -C "$RIG_ROOT" rev-parse --short HEAD)
           EXPECTED_SHORT=$(git -C "$RIG_ROOT" rev-parse --short "$PRE_REBASE_SHA" 2>/dev/null \
                            || printf '%.10s' "$PRE_REBASE_SHA")
           RIG_UPDATE_RESULT="skipped: HEAD=$OLD_SHORT does not match pre_rebase_tip=$EXPECTED_SHORT (operator must sync)"
       else
           OLD_SHA=$(git -C "$RIG_ROOT" rev-parse --short HEAD)
           if ! git -C "$RIG_ROOT" reset --hard origin/main >/dev/null 2>&1; then
               RIG_UPDATE_RESULT="error: reset --hard origin/main failed in $RIG_ROOT (operator must sync)"
           else
               NEW_SHA=$(git -C "$RIG_ROOT" rev-parse --short HEAD)
               # Sweep reaped worktree admin entries. In-flight polecat
               # worktrees still finish on their own bases by design;
               # prune only removes records for directories that already
               # vanished.
               git -C "$RIG_ROOT" worktree prune >/dev/null 2>&1
               RIG_UPDATE_RESULT="reset: $OLD_SHA -> $NEW_SHA (worktree prune ran)"
           fi
       fi
   fi

   gc bd update "$WORK" --set-metadata rig_update_result="$RIG_UPDATE_RESULT"
   ```

5. **Mark the bead landed and close it.** The standard
   merge_strategy=direct close path applies — set `merge_result=force_lease`
   and `pr_url=` (rebase bypasses PR creation by design), then close.
   The close notification (mail or nudge to the gascity-keeper) MUST
   surface `metadata.rig_update_result` so the operator can see at a
   glance whether the rig followed the rebase or still needs a manual
   sync.

### Race loss

If step 1 reports `main-ahead > 0`, OR step 3's push is rejected with
"stale info" / "tip is not the expected value", the rebase polecat's
work is no longer landable as-is. Do NOT attempt to retry the
force-push. Escalate to mayor with the bead-id and the lost-race
context so the operator (via the gascity-keeper) can decide whether
to:

- Re-pour the rebase formula to redo the work atop the new
  `origin/main`, or
- Drop the rebase entirely (whatever landed on `main` already
  superseded it), or
- Take it manually if the situation is unusual.

```bash
gc mail send mayor -s "ESCALATION: rebase race loss on $WORK" -m "$(cat <<EOF
Bead: $WORK
Branch: $BRANCH
Reason: origin/main advanced after the rebase polecat finished.

Either the rebase needs re-pouring atop the new main tip, or what
landed on main supersedes it. Routing this back to the gascity-keeper
for an operator decision.

Backup ref (pre-rebase tip): $(gc bd show "$WORK" --json | jq -r '.[0].metadata.backup_ref // "(none)"')
EOF
)"

gc bd update "$WORK" --status=open --assignee="$GC_RIG/gascity-keeper.keeper" \
  --set-metadata rejection_reason="rebase race loss: origin/main advanced"
```

### Refinery overlay scope

This rebase-handling overlay is opt-in per rig (only rigs that import
the `gascity-keeper` sub-pack). A refinery in a rig that does NOT
import the sub-pack will not carry these instructions; a rebase-shaped
bead that ends up at such a refinery is a routing leak. Escalate to
mayor instead of force-pushing. PR #17's "reject as routing leak"
intent survives in the unintended-target case; the legitimate path is
the overlay above.
{{ end }}
