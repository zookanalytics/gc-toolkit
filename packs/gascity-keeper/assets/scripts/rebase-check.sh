#!/bin/bash
# Exit condition for the `rebase` check loop in mol-upstream-gc-rebase.
#
# Exit 0 ("pass" — closes the control bead and releases install/push) ONLY when
# the rebase is finished AND the post-rebase quality gate is green on exactly
# the tree that is checked out right now. Every other state, including any
# internal error in this script, exits non-zero so the loop spawns the next
# iteration. Fail-closed is deliberate: a false pass force-pushes an unverified
# history onto the fork's main branch.
#
# ## Why this VERIFIES the gate instead of running it
#
# The runtime executes this script inline in the control dispatcher
# (internal/dispatch/ralph.go -> internal/convergence/condition.go), which
# constrains it in three ways:
#
#   1. The default gate timeout is 5 minutes and `check.timeout` bounds the
#      whole exec. The gascity gate (`make check` = fmt-check + lint + vet +
#      test) runs ~15 minutes, so running it here would time out.
#   2. The exec blocks the control dispatcher for its full duration — a
#      long-running gate here stalls control-bead processing city-wide.
#   3. PATH is the sandboxed condition PATH (bd, gc, dolt, jq plus
#      /usr/local/bin:/usr/bin:/bin) and HOME is redirected to the city root.
#      `go` is not guaranteed to be on it, and the Go build/module caches under
#      the redirected HOME would be cold.
#
# So the iteration agent runs the gate in its own session — real HOME, real
# toolchain, no dispatcher held open — and stamps the result on the work bead.
# This script confirms that stamp still describes the live HEAD. The stamp is
# bound to a commit sha, so any later commit invalidates it and re-gates the
# loop; it can go stale, but it cannot silently certify a different tree.
#
# ## Why cwd is not trusted
#
# The runtime sets cwd from the inherited `work_dir` metadata, which resolves to
# the POLECAT's step worktree — not the gascity rebase worktree. The rebase
# worktree is resolved explicitly below, from the work bead's metadata.work_dir
# (stamped by the workspace-setup step), and every git call is pinned to it
# with `git -C`.

set -uo pipefail

fail() {
	printf 'rebase-check: FAIL: %s\n' "$1" >&2
	exit 1
}

note() { printf 'rebase-check: %s\n' "$1" >&2; }

# --- 1. Resolve the molecule root (wisp) -------------------------------------
# GC_WISP_ID is exported by the condition env; fall back to the iteration
# bead's gc.root_bead_id, which molecule instantiation stamps on every member.
ROOT="${GC_WISP_ID:-}"
if [ -z "$ROOT" ]; then
	[ -n "${GC_BEAD_ID:-}" ] || fail "neither GC_WISP_ID nor GC_BEAD_ID is set"
	ROOT=$(bd show "$GC_BEAD_ID" --json 2>/dev/null |
		jq -r '.[0].metadata."gc.root_bead_id" // empty') ||
		fail "could not read root bead id from $GC_BEAD_ID"
fi
[ -n "$ROOT" ] || fail "could not resolve the molecule root bead"

# --- 2. Root -> input convoy -> the single tracked member (the work bead) -----
CONVOY=$(bd show "$ROOT" --json 2>/dev/null |
	jq -r '.[0].metadata."gc.input_convoy_id" // .[0].metadata."gc.var.convoy_id" // empty')
[ -n "$CONVOY" ] || fail "root $ROOT carries no input convoy id"

ISSUE=$(gc convoy status "$CONVOY" --json 2>/dev/null |
	jq -r 'if (.children | length) == 1 then .children[0].id else empty end')
[ -n "$ISSUE" ] || fail "convoy $CONVOY does not have exactly one tracked member"

# --- 3. The rebase worktree, as recorded by workspace-setup ------------------
ISSUE_JSON=$(bd show "$ISSUE" --json 2>/dev/null) || fail "could not read work bead $ISSUE"
WORKTREE=$(printf '%s' "$ISSUE_JSON" | jq -r '.[0].metadata.work_dir // empty')
[ -n "$WORKTREE" ] || fail "work bead $ISSUE has no metadata.work_dir yet"
[ -d "$WORKTREE" ] || fail "recorded work_dir does not exist: $WORKTREE"
git -C "$WORKTREE" rev-parse --git-dir >/dev/null 2>&1 ||
	fail "work_dir is not a git worktree: $WORKTREE"

# --- 4. The rebase must be finished ------------------------------------------
# A halted rebase means the iteration stopped on a conflict it did not resolve.
# That is the normal "keep looping" signal, not an error.
for state in rebase-merge rebase-apply; do
	state_dir=$(git -C "$WORKTREE" rev-parse --git-path "$state" 2>/dev/null) || continue
	case "$state_dir" in
	/*) ;;
	*) state_dir="$WORKTREE/$state_dir" ;;
	esac
	if [ -d "$state_dir" ]; then
		note "rebase still in progress ($state); another iteration is needed"
		exit 1
	fi
done

# --- 5. The tree must be clean ----------------------------------------------
# Unmerged paths or stray edits mean the iteration left work behind; install and
# push would then operate on something no gate ever saw.
DIRTY=$(git -C "$WORKTREE" status --porcelain 2>/dev/null) ||
	fail "could not read git status in $WORKTREE"
if [ -n "$DIRTY" ]; then
	note "worktree is dirty; another iteration is needed:"
	printf '%s\n' "$DIRTY" >&2
	exit 1
fi

HEAD_SHA=$(git -C "$WORKTREE" rev-parse HEAD 2>/dev/null) ||
	fail "could not resolve HEAD in $WORKTREE"

# --- 6. HEAD must actually sit on top of the upstream tip we rebased onto -----
# Without this, a `git rebase --abort` that returns HEAD to the pre-rebase tip
# could be certified by a check_passed_sha stamped on that same pre-rebase tip
# in an earlier run.
ONTO=$(printf '%s' "$ISSUE_JSON" | jq -r '.[0].metadata.rebase_onto_sha // empty')
[ -n "$ONTO" ] || fail "work bead $ISSUE has no metadata.rebase_onto_sha; the iteration must stamp the upstream tip it rebased onto"
git -C "$WORKTREE" cat-file -e "${ONTO}^{commit}" 2>/dev/null ||
	fail "rebase_onto_sha $ONTO is not a commit in $WORKTREE"
if ! git -C "$WORKTREE" merge-base --is-ancestor "$ONTO" "$HEAD_SHA" 2>/dev/null; then
	note "HEAD ($HEAD_SHA) is not on top of the upstream tip ($ONTO); another iteration is needed"
	exit 1
fi

# --- 7. The quality gate must be green at THIS HEAD --------------------------
GATE_SHA=$(printf '%s' "$ISSUE_JSON" | jq -r '.[0].metadata.check_passed_sha // empty')
if [ -z "$GATE_SHA" ]; then
	note "no metadata.check_passed_sha recorded; the gate has not passed yet"
	exit 1
fi
if [ "$GATE_SHA" != "$HEAD_SHA" ]; then
	note "gate stamp is stale (passed at $GATE_SHA, HEAD is $HEAD_SHA); another iteration is needed"
	exit 1
fi

note "PASS: rebase complete and gate green at $HEAD_SHA"
exit 0
