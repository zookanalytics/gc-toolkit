#!/usr/bin/env bash
# Pack doctor check: mol-upstream-gc-rebase's workspace-setup step
# handles the case where `rebase/<issue>` already exists in the rig's
# git repo (recovery after a worktree wipe).
#
# Symptom this guards against: a polecat session that drained while
# holding a rebase worktree leaves `refs/heads/rebase/<issue>` behind
# in the rig's shared repo even after the worktree dir was reaped. A
# fresh re-pour of the rebase mol then hits `git worktree add ... -b
# rebase/<issue>` -- which fails with "A branch named '...' already
# exists" and strands the bead. See tk-y883hr for the trip diagnostic.
#
# Fix shape: branch the worktree-create on
# `git rev-parse --verify refs/heads/rebase/<issue>` so that recovery
# re-attaches the existing branch without `-b`, while a fresh run still
# creates the branch from `<origin>/<upstream_branch>`.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

dir="${GC_PACK_DIR:-.}"
file="$dir/packs/gascity-keeper/formulas/mol-upstream-gc-rebase.toml"
violations=()

if [ ! -f "$file" ]; then
    echo "mol-upstream-gc-rebase.toml: missing file $file"
    exit 2
fi

# 1. Recovery branch must rev-parse refs/heads/rebase/{{issue}} to decide
#    whether to reuse vs. create. Anchor on the {{issue}} placeholder so
#    we match the formula form rather than an example elsewhere in the
#    file.
if ! grep -qE 'rev-parse --verify "refs/heads/rebase/\{\{issue\}\}"' "$file"; then
    violations+=("missing 'git rev-parse --verify refs/heads/rebase/{{issue}}' guard (recovery branch-reuse not gated)")
fi

# 2. Recovery path must call `worktree add` against the existing branch
#    name WITHOUT `-b` (i.e. re-attach, not create). Pattern: the
#    `worktree add` whose argument list ends with `"rebase/{{issue}}"`
#    and does NOT have `-b` in front of it.
if ! grep -qE 'worktree add "\$WORKTREE_PATH" "rebase/\{\{issue\}\}"' "$file"; then
    violations+=("missing branch-reuse 'worktree add \"\$WORKTREE_PATH\" \"rebase/{{issue}}\"' (recovery path absent)")
fi

# 3. Fresh-run path with `-b` must still exist (we didn't accidentally
#    remove the original create path while wiring the recovery branch).
if ! grep -qE 'worktree add "\$WORKTREE_PATH" -b "rebase/\{\{issue\}\}" "\{\{origin_remote\}\}/\{\{upstream_branch\}\}"' "$file"; then
    violations+=("missing fresh-run 'worktree add ... -b \"rebase/{{issue}}\" \"{{origin_remote}}/{{upstream_branch}}\"' (create path lost)")
fi

# 4. Stale-worktree prune must run before the rev-parse guard so that a
#    reaped-worktree run can re-attach the branch without tripping
#    `fatal: 'rebase/<issue>' is already used by worktree at <missing>`.
#    Pinned here because the workspace-setup recovery flow only works if
#    the prune call stays in place; removing it would reintroduce the
#    stale-claim symptom that codex reproduced on PR #53.
if ! grep -qE 'git -C "\$RIG_ROOT" worktree prune' "$file"; then
    violations+=("missing 'git -C \"\$RIG_ROOT\" worktree prune' before rev-parse guard (stale-worktree recovery absent)")
fi

if [ ${#violations[@]} -eq 0 ]; then
    echo "mol-upstream-gc-rebase workspace-setup handles existing rebase/<issue> branch (recovery after worktree wipe)"
    exit 0
fi

echo "${#violations[@]} branch-reuse gap(s) in mol-upstream-gc-rebase workspace-setup — see tk-y883hr"
for v in "${violations[@]}"; do
    echo "$v"
done
exit 2
