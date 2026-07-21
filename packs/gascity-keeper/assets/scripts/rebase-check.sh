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
#
# ## Why this script writes to the work bead on the LAST failing attempt
#
# Exhaustion is otherwise invisible to the humans who own this workflow. When
# `gc.attempt` reaches `gc.max_attempts` the orchestrator closes the control
# bead with `gc.outcome=fail` and stops (internal/dispatch/ralph.go); nothing
# touches the work bead. It keeps its polecat assignee and no keeper-visible
# flag, so the keeper's prime sweep (`assignee=$GC_AGENT` AND one of
# `suggested_pr_title` / `aborted_at` / `conflict_questions` /
# `rebase_in_progress`) never surfaces it — the rebase strands mid-flight with
# `install` and `push` blocked and no pending item anywhere. That is exactly the
# class of stranded state this formula's v12 rewrite exists to remove.
#
# This script is the only thing that runs at that moment, so it performs the
# handback itself, in the same shape the install/push aborts use: set
# `aborted_at`, reassign the work bead to the requesting keeper, append the
# failure tail to the notes, and nudge. It fires only when this attempt is the
# budget's last (`GC_ITERATION >= gc.max_attempts`) and only once (a work bead
# that already carries `aborted_at` is left alone). Every write is best-effort:
# a handback that fails must not change this script's verdict, and the verdict
# is a FAIL either way.

set -uo pipefail

# Resolved as we go; the handback needs them and runs from failure paths that
# can fire before they are set.
ROOT=""
ISSUE=""

fail() {
	printf 'rebase-check: FAIL: %s\n' "$1" >&2
	handback_if_budget_exhausted "$1"
	exit 1
}

note() { printf 'rebase-check: %s\n' "$1" >&2; }

# A truthful "not done yet": the loop should run another iteration, unless this
# was the last one — in which case the handback below is the durable signal.
incomplete() {
	note "$1"
	handback_if_budget_exhausted "$1"
	exit 1
}

# The loop's budget, from the ralph control bead's gc.max_attempts. The ralph
# condition env sets GC_ITERATION but leaves GC_MAX_ITERATIONS at its zero value
# (internal/dispatch/ralph.go builds ConditionEnv without MaxIterations), so the
# budget has to come from the beads. Echoes nothing when it cannot be resolved —
# an unknown budget means no handback, never a guessed one.
#
# Cost: one bead read per failing iteration, plus a root-scoped list when the
# subject bead does not carry the budget itself — a couple of seconds against a
# 2m gate timeout, on a path that already only runs once per iteration.
resolve_budget() {
	local subject_json step
	[ -n "${GC_BEAD_ID:-}" ] || return 0
	subject_json=$(bd show "$GC_BEAD_ID" --json 2>/dev/null) || return 0

	# GC_BEAD_ID is normally the iteration bead, but the runtime falls back to
	# the control bead itself when there is no subject — then the budget is
	# already here.
	local direct
	direct=$(printf '%s' "$subject_json" | jq -r '.[0].metadata."gc.max_attempts" // empty')
	if [ -n "$direct" ]; then
		printf '%s' "$direct"
		return 0
	fi

	[ -n "$ROOT" ] || return 0
	# gc.control_for on the iteration is the step id the control carries as
	# gc.step_id (internal/formula/ralph.go) — the join key when a molecule has
	# more than one check loop.
	step=$(printf '%s' "$subject_json" | jq -r '.[0].metadata."gc.control_for" // empty')
	bd list --all --include-infra --limit 0 --json \
		--metadata-field "gc.root_bead_id=$ROOT" \
		--metadata-field "gc.kind=ralph" 2>/dev/null |
		jq -r --arg step "$step" '
			[ .[] | select($step == "" or (.metadata."gc.step_id" // "") == $step) ]
			| .[0].metadata."gc.max_attempts" // empty'
}

handback_if_budget_exhausted() {
	local reason="$1"
	[ -n "$ISSUE" ] || return 0

	local attempt budget
	attempt="${GC_ITERATION:-}"
	case "$attempt" in
	'' | *[!0-9]*) return 0 ;;
	esac
	budget=$(resolve_budget)
	case "$budget" in
	'' | *[!0-9]*) return 0 ;;
	esac
	[ "$budget" -gt 0 ] || return 0
	[ "$attempt" -ge "$budget" ] || return 0

	# Re-read rather than trusting a snapshot: an iteration may have stamped
	# conflict_questions after this script started, and a retried exec of this
	# same attempt must not append a second handback.
	local issue_json
	issue_json=$(bd show "$ISSUE" --json 2>/dev/null) || {
		note "WARN: could not re-read $ISSUE for the exhaustion handback"
		return 0
	}
	local already
	already=$(printf '%s' "$issue_json" | jq -r '.[0].metadata.aborted_at // empty')
	if [ -n "$already" ]; then
		note "budget exhausted; $ISSUE already carries aborted_at=$already (leaving it)"
		return 0
	fi

	local keeper worktree backup questions
	keeper=$(printf '%s' "$issue_json" | jq -r '.[0].metadata.requesting_keeper // empty')
	[ -n "$keeper" ] || keeper=$(printf '%s' "$issue_json" | jq -r '.[0].metadata.notify_recipient // empty')
	worktree=$(printf '%s' "$issue_json" | jq -r '.[0].metadata.work_dir // "(not recorded)"')
	backup=$(printf '%s' "$issue_json" | jq -r '.[0].metadata.backup_ref // "(not recorded)"')
	# conflict_questions is stored as a JSON string; tolerate a store that hands
	# it back already parsed rather than reporting a misleading zero.
	questions=$(printf '%s' "$issue_json" |
		jq -r '(.[0].metadata.conflict_questions // "[]")
		       | (if type == "string" then (fromjson? // []) else . end)
		       | length' 2>/dev/null)
	[ -n "$questions" ] || questions=0

	local -a args=(
		--status=open
		--set-metadata "aborted_at=rebase-loop-exhausted"
		--set-metadata "rebase_loop_attempts=$attempt"
	)
	[ -n "$keeper" ] && args+=(--assignee "$keeper")

	if ! bd update "$ISSUE" "${args[@]}" --append-notes "$(
		cat <<EOF
The rebase check loop exhausted its budget (attempt $attempt of $budget) without
reaching a green gate (aborted_at=rebase-loop-exhausted). The control bead closes
gc.outcome=fail and install/push stay blocked; no further iteration will run.

Last exit-condition verdict: $reason
Worktree: $worktree
Backup ref: $backup
Recorded conflict questions: $questions

Next: read metadata.conflict_questions and metadata.conflict_resolutions, then
either drive the rebase to green by hand from the worktree, or unwind it:
  git -C $worktree reset --hard $backup
EOF
	)" >/dev/null 2>&1; then
		note "WARN: exhaustion handback write failed for $ISSUE (loop still reports FAIL)"
		return 0
	fi
	note "budget exhausted at attempt $attempt/$budget; handed $ISSUE back to ${keeper:-(no keeper recorded)} with aborted_at=rebase-loop-exhausted"

	# Timely signal only; the bead above is the durable one.
	if [ -n "$keeper" ]; then
		gc session nudge "$keeper" \
			"rebase $ISSUE: check loop exhausted ($attempt/$budget) — operator engagement needed (metadata.aborted_at=rebase-loop-exhausted; details in bead notes)" \
			>/dev/null 2>&1 || true
	fi
}

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
		incomplete "rebase still in progress ($state); another iteration is needed"
	fi
done

# --- 5. The tree must be clean ----------------------------------------------
# Unmerged paths or stray edits mean the iteration left work behind; install and
# push would then operate on something no gate ever saw.
DIRTY=$(git -C "$WORKTREE" status --porcelain 2>/dev/null) ||
	fail "could not read git status in $WORKTREE"
if [ -n "$DIRTY" ]; then
	printf '%s\n' "$DIRTY" >&2
	incomplete "worktree is dirty; another iteration is needed (see the status above)"
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
	incomplete "HEAD ($HEAD_SHA) is not on top of the upstream tip ($ONTO); another iteration is needed"
fi

# --- 7. The quality gate must be green at THIS HEAD --------------------------
GATE_SHA=$(printf '%s' "$ISSUE_JSON" | jq -r '.[0].metadata.check_passed_sha // empty')
if [ -z "$GATE_SHA" ]; then
	incomplete "no metadata.check_passed_sha recorded; the gate has not passed yet"
fi
if [ "$GATE_SHA" != "$HEAD_SHA" ]; then
	incomplete "gate stamp is stale (passed at $GATE_SHA, HEAD is $HEAD_SHA); another iteration is needed"
fi

note "PASS: rebase complete and gate green at $HEAD_SHA"
exit 0
