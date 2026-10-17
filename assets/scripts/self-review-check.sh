#!/usr/bin/env bash
# Exit condition for the `self-review` check loop in mol-polecat-work.
#
# Exit 0 ("pass" — closes the control bead and releases submit-and-exit) ONLY
# when the tree checked out right now is clean and `gctk rig` holds a passing
# record of each of the rig's recorded checks (test, lint and typecheck) at its
# HEAD. Every other state, including any internal error in this script, exits
# non-zero so the loop spawns the next iteration. Fail-closed is deliberate: a
# false pass hands an unverified diff to the refinery, which is the red handoff
# this loop exists to stop.
#
# ## Why this READS the records instead of running the checks
#
# The runtime executes this script inline in the control dispatcher
# (internal/dispatch/ralph.go -> internal/convergence/condition.go), which
# constrains it three ways:
#
#   1. The gate exec is bounded by check.timeout (default 5m). A rig's declared
#      test/build gate can run far longer, so running it here would time out.
#   2. The exec blocks the control dispatcher for its whole duration — a
#      long-running gate here stalls control-bead processing city-wide.
#   3. PATH is the sandboxed condition PATH (bd, gc, dolt, jq plus
#      /usr/local/bin:/usr/bin:/bin) and HOME is redirected to the city root.
#      A language toolchain such as `go` is not guaranteed to be on it, and the
#      build/module caches under the redirected HOME start cold.
#
# So the iteration agent runs the declared checks in its own session — real
# HOME, real toolchain, no dispatcher held open — through `gctk rig`, which runs
# each command itself and records its result against the commit it ran at,
# under the rig clone's git common directory that every worktree of the clone
# shares. This script reads those records at the live HEAD with `gctk rig
# <check> --check`, which runs nothing and calls nothing but git, so it answers
# here, where gc can fail. A record names one commit, so any later commit has
# none until the checks run again, and a record cannot certify a tree the
# command did not run on.
#
# ## Why cwd is not trusted
#
# The runtime sets cwd from inherited work_dir metadata, which need not resolve
# to this molecule's worktree. The worktree is resolved explicitly below from
# the work bead's metadata.work_dir (stamped by workspace-setup), and every git
# call is pinned to it with `git -C`.
#
# ## Why resolution is bd-only
#
# Every bead lookup here goes through `bd`, never `gc` (and `gc bd` is `gc` for
# this purpose). `bd` talks to the bead store directly; `gc` subcommands first
# load the full city config including the pack import closure, which in the
# condition env can be cold — then the `gc` call dies before doing anything
# ("... locked but not cached ...; run 'gc import install'"). A resolution that
# dies goes blind to an already-green gate AND suppresses the exhaustion
# handback below (which is gated on a resolved $ISSUE), so the loop burns its
# whole budget and strands with nothing on anyone's hook. Keeping resolution on
# `bd` keeps both working in a minimal env. Each `bd` call carries a `# raw-bd:`
# marker, which the raw-bd-invocation lint reads.
#
# ## Why this script writes to the work bead on the LAST failing attempt
#
# When gc.attempt reaches gc.max_attempts the orchestrator closes the control
# bead gc.outcome=fail and stops; nothing touches the work bead, and
# submit-and-exit stays blocked forever. This script is the only thing that runs
# at that moment, so it performs the handback itself: stamp aborted_at, clear
# the pool route and the drained session's pins, reassign the work bead to the
# witness with the failure tail in notes, and nudge. It fires only on the
# budget's last attempt (GC_ITERATION >= gc.max_attempts) and only once (a work
# bead already carrying aborted_at is left alone). Every write is best-effort: a
# handback that fails must not change the verdict, which is a FAIL either way.

set -uo pipefail

# Resolved as we go; the handback needs $ISSUE and runs from failure paths that
# can fire before it is set.
ROOT=""
ISSUE=""

note() { printf 'self-review-check: %s\n' "$1" >&2; }

fail() {
	printf 'self-review-check: FAIL: %s\n' "$1" >&2
	handback_if_budget_exhausted "$1"
	exit 1
}

# A truthful "not done yet": run another iteration, unless this was the last —
# in which case the handback is the durable signal.
incomplete() {
	note "$1"
	handback_if_budget_exhausted "$1"
	exit 1
}

# The iteration bead this attempt ran on, read at most once (memoized). Empty
# when GC_BEAD_ID is unset or the read fails; callers treat empty as "nothing to
# say" rather than an error.
ITERATION_JSON=""
ITERATION_JSON_READ=0
iteration_json() {
	if [ "$ITERATION_JSON_READ" = "0" ]; then
		ITERATION_JSON_READ=1
		if [ -n "${GC_BEAD_ID:-}" ]; then
			# raw-bd: gc bd loads the city config, which can be cold here — see "Why resolution is bd-only"
			ITERATION_JSON=$(bd show "$GC_BEAD_ID" --json 2>/dev/null) || ITERATION_JSON=""
		fi
	fi
	printf '%s' "$ITERATION_JSON"
}

# The loop's budget, from the ralph control bead's gc.max_attempts. The ralph
# condition env sets GC_ITERATION but leaves GC_MAX_ITERATIONS at its zero value,
# so the budget comes from the beads. Echoes nothing when it cannot be resolved —
# an unknown budget means no handback, never a guessed one.
resolve_budget() {
	local subject_json step
	subject_json=$(iteration_json)
	[ -n "$subject_json" ] || return 0

	# GC_BEAD_ID is normally the iteration bead, but the runtime falls back to
	# the control bead when there is no subject — then the budget is already here.
	local direct
	direct=$(printf '%s' "$subject_json" | jq -r '.[0].metadata."gc.max_attempts" // empty')
	if [ -n "$direct" ]; then
		printf '%s' "$direct"
		return 0
	fi

	[ -n "$ROOT" ] || return 0
	# gc.control_for on the iteration is the step id the control carries as
	# gc.step_id — the join key when a molecule has more than one check loop.
	step=$(printf '%s' "$subject_json" | jq -r '.[0].metadata."gc.control_for" // empty')
	# raw-bd: gc bd loads the city config, which can be cold here — see "Why resolution is bd-only"
	bd list --all --include-infra --limit 0 --json \
		--metadata-field "gc.root_bead_id=$ROOT" \
		--metadata-field "gc.kind=ralph" 2>/dev/null |
		jq -r --arg step "$step" '
			[ .[] | select($step == "" or (.metadata."gc.step_id" // "") == $step) ]
			| .[0].metadata."gc.max_attempts" // empty'
}

# The witness address, derived from the molecule's pool route (…/<prefix>polecat
# -> …/<prefix>witness). The witness is the escalation first responder; it
# triages the handed-back bead and promotes it to a human visit if needed.
resolve_witness() {
	local route="$1"
	case "$route" in
	*.polecat) printf '%s.witness' "${route%.polecat}" ;;
	*.polecat-*) printf '%s.witness' "${route%.polecat-*}" ;;
	*) : ;;
	esac
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

	# Re-read rather than trusting a snapshot: a retried exec of this same
	# attempt must not append a second handback.
	local issue_json
	# raw-bd: gc bd loads the city config, which can be cold here — see "Why resolution is bd-only"
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

	local worktree branch route witness
	worktree=$(printf '%s' "$issue_json" | jq -r '.[0].metadata.work_dir // "(not recorded)"')
	branch=$(printf '%s' "$issue_json" | jq -r '.[0].metadata.branch // "(not recorded)"')
	route=$(printf '%s' "$issue_json" | jq -r '.[0].metadata."gc.execution_routed_to" // .[0].metadata."gc.routed_to" // empty')
	witness=$(resolve_witness "$route")

	# Clear the pool route so no fresh polecat is offered the same failing work,
	# and clear the drained session's pins so the bead does not read as owned by
	# a session that has ceased to exist. Reassign to the witness with the
	# failure recorded. aborted_at is what a sweep keys on; the assignee + notes
	# are what a reader acts on.
	local -a args=(
		--status=open
		--set-metadata "aborted_at=self-review-exhausted"
		--set-metadata "self_review_loop_attempts=$attempt"
		--set-metadata "gc.routed_to="
		--unset-metadata gc.session_id
		--unset-metadata gc.session_name
	)
	[ -n "$witness" ] && args+=(--assignee "$witness")

	if ! bd update "$ISSUE" "${args[@]}" --append-notes "$(
		cat <<EOF
Self-review check loop exhausted its budget (attempt $attempt of $budget) without
a verified-green gate (aborted_at=self-review-exhausted). The control bead closes
gc.outcome=fail and submit-and-exit stays blocked; no further iteration will run.

Last exit-condition verdict: $reason
Worktree: $worktree
Branch: $branch

The branch and worktree are intact. Resume by checking out the branch in the
worktree, driving the declared checks to green by hand, then re-slinging
mol-polecat-work on this bead; or judge the change unshippable and dispose of it.
EOF
	)" >/dev/null 2>&1; then
		note "WARN: exhaustion handback write failed for $ISSUE (loop still reports FAIL)"
		return 0
	fi
	note "budget exhausted at attempt $attempt/$budget; handed $ISSUE back to ${witness:-(no witness resolved)} with aborted_at=self-review-exhausted"

	# Timely signal only; the bead above is the durable one.
	if [ -n "$witness" ]; then
		gc session nudge "$witness" \
			"$ISSUE: self-review check loop exhausted ($attempt/$budget) — the change could not reach a green gate; branch intact, details in bead notes (aborted_at=self-review-exhausted)" \
			>/dev/null 2>&1 || true
	fi
}

# --- 1. Resolve the molecule root (wisp) -------------------------------------
# GC_WISP_ID is exported by the condition env; fall back to the iteration bead's
# gc.root_bead_id, which molecule instantiation stamps on every member.
ROOT="${GC_WISP_ID:-}"
if [ -z "$ROOT" ]; then
	[ -n "${GC_BEAD_ID:-}" ] || fail "neither GC_WISP_ID nor GC_BEAD_ID is set"
	# raw-bd: gc bd loads the city config, which can be cold here — see "Why resolution is bd-only"
	ROOT=$(bd show "$GC_BEAD_ID" --json 2>/dev/null |
		jq -r '.[0].metadata."gc.root_bead_id" // empty') ||
		fail "could not read root bead id from $GC_BEAD_ID"
fi
[ -n "$ROOT" ] || fail "could not resolve the molecule root bead"

# --- 2. Root -> the single tracked member (the work bead) --------------------
# Resolved with `bd` only. Two independent sources, cross-checked when both read:
#   the convoy's direct dependants — the tracked membership itself, which
#     carries the "exactly one member" invariant mol-polecat-work is built on;
#   gc.var.issue on the root — stamped by the self-review iteration as the
#     resilient fallback for when the membership read is degraded.
# raw-bd: gc bd loads the city config, which can be cold here — see "Why resolution is bd-only"
ROOT_JSON=$(bd show "$ROOT" --json 2>/dev/null)
[ -n "$ROOT_JSON" ] || fail "could not read root bead $ROOT"

CONVOY=$(printf '%s' "$ROOT_JSON" |
	jq -r '.[0].metadata."gc.input_convoy_id" // .[0].metadata."gc.var.convoy_id" // empty')
[ -n "$CONVOY" ] || fail "root $ROOT carries no input convoy id"

ROOT_ISSUE=$(printf '%s' "$ROOT_JSON" | jq -r '.[0].metadata."gc.var.issue" // empty')

# The convoy's tracked members are its direct children (depth 1 under the convoy
# itself). Empty output means the query failed outright, distinct from a convoy
# that genuinely has no members.
# raw-bd: gc bd loads the city config, which can be cold here — see "Why resolution is bd-only"
MEMBER_JSON=$(bd dep tree "$CONVOY" --json 2>/dev/null)
MEMBER=""
MEMBER_COUNT=""
if [ -n "$MEMBER_JSON" ]; then
	MEMBER_COUNT=$(printf '%s' "$MEMBER_JSON" | jq --arg convoy "$CONVOY" '
		[ .[] | select((.depth // 0) == 1 and (.parent_id // "") == $convoy) ]
		| length' 2>/dev/null)
	MEMBER=$(printf '%s' "$MEMBER_JSON" | jq -r --arg convoy "$CONVOY" '
		first(.[] | select((.depth // 0) == 1 and (.parent_id // "") == $convoy) | .id)
		// empty' 2>/dev/null)
fi

case "$MEMBER_COUNT" in
'' | *[!0-9]*)
	# Membership unreadable. gc.var.issue is the only source left; say so — the
	# "exactly one member" invariant went unverified this iteration.
	[ -n "$ROOT_ISSUE" ] ||
		fail "could not read convoy $CONVOY membership, and root $ROOT carries no gc.var.issue"
	ISSUE="$ROOT_ISSUE"
	note "WARN: could not read convoy $CONVOY membership; proceeding on root gc.var.issue=$ISSUE (membership unverified)"
	;;
1)
	ISSUE="$MEMBER"
	# Both sources readable and disagreeing means the molecule is wired wrong.
	# Certifying against the wrong bead is the false pass this exists to prevent.
	if [ -n "$ROOT_ISSUE" ] && [ "$ROOT_ISSUE" != "$ISSUE" ]; then
		fail "root $ROOT gc.var.issue=$ROOT_ISSUE disagrees with convoy $CONVOY member $ISSUE"
	fi
	;;
0)
	fail "convoy $CONVOY does not have exactly one tracked member (found 0)"
	;;
*)
	fail "convoy $CONVOY does not have exactly one tracked member (found $MEMBER_COUNT)"
	;;
esac
[ -n "$ISSUE" ] || fail "could not resolve the work bead from root $ROOT / convoy $CONVOY"

# --- 3. The worktree, as recorded by workspace-setup -------------------------
# raw-bd: gc bd loads the city config, which can be cold here — see "Why resolution is bd-only"
ISSUE_JSON=$(bd show "$ISSUE" --json 2>/dev/null) || fail "could not read work bead $ISSUE"
WORKTREE=$(printf '%s' "$ISSUE_JSON" | jq -r '.[0].metadata.work_dir // empty')
[ -n "$WORKTREE" ] || fail "work bead $ISSUE has no metadata.work_dir yet"
[ -d "$WORKTREE" ] || fail "recorded work_dir does not exist: $WORKTREE"
git -C "$WORKTREE" rev-parse --git-dir >/dev/null 2>&1 ||
	fail "work_dir is not a git worktree: $WORKTREE"

# --- 4. The tree must be clean ----------------------------------------------
# Uncommitted changes mean the iteration left work the declared checks never
# saw, and no record at HEAD describes them.
DIRTY=$(git -C "$WORKTREE" status --porcelain 2>/dev/null) ||
	fail "could not read git status in $WORKTREE"
if [ -n "$DIRTY" ]; then
	printf '%s\n' "$DIRTY" >&2
	incomplete "worktree is dirty; another iteration is needed (see the status above)"
fi

HEAD_SHA=$(git -C "$WORKTREE" rev-parse HEAD 2>/dev/null) ||
	fail "could not resolve HEAD in $WORKTREE"

# --- 5. Every recorded check must pass at THIS HEAD --------------------------
# The iteration ran each check through `gctk rig`. A check the rig declares no
# command for is recorded as a pass that ran nothing, so each of the three has a
# record to read. setup and build record nothing, so nothing here reads them.
# A recorded fail passes only when the work bead's rig_check_pre_existing.<check>
# carries that very record at this HEAD: the iteration found the same failure
# red on the base and carried by a tracker (rig-check-pre-existing.sh). A run
# with another command or scope replaces the record, and its fail needs a
# judgment of its own.
# >>> gctk-bin
GCTK="${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"
# <<< gctk-bin
[ -x "$GCTK" ] || fail "no gctk binary at $GCTK to read the recorded checks; the city's gctk-build order publishes it"
FAILED=""
UNRECORDED=""
for CHECK in test lint typecheck; do
	# rig's own line goes to stderr, where it says what is recorded, and the
	# record it found is the one JSON line on stdout.
	REC=$(cd "$WORKTREE" && "$GCTK" rig "$CHECK" --check)
	RC=$?
	case "$RC" in
	0) ;;
	1)
		PRE=$(printf '%s' "$ISSUE_JSON" | jq -r --arg k "rig_check_pre_existing.$CHECK" --arg c "$HEAD_SHA" --arg rec "$REC" '
			($rec | fromjson? // null) as $r
			| .[0].metadata[$k] // empty
			| (if type == "string" then (fromjson? // empty) else . end)
			| select(type == "object" and .commit == $c and ((.trackers // []) | length) > 0)
			| if $r != null and .record == $r then "tracked by " + (.trackers | join(", ")) else "another run" end' 2>/dev/null)
		case "$PRE" in
		"tracked by "*) note "$CHECK: the recorded fail at $HEAD_SHA is pre-existing, $PRE" ;;
		"another run")
			FAILED="$FAILED $CHECK"
			note "$CHECK: the pre-existing mark at $HEAD_SHA judged another run's fail, so this one needs a judgment of its own"
			;;
		*) FAILED="$FAILED $CHECK" ;;
		esac
		;;
	3) UNRECORDED="$UNRECORDED $CHECK" ;;
	4) FAILED="$FAILED $CHECK" ;;
	*) fail "gctk rig $CHECK --check exited $RC in $WORKTREE" ;;
	esac
done
[ -z "$FAILED" ] || incomplete "not green at $HEAD_SHA:$FAILED; another iteration is needed"

# A molecule poured before its self-review ran the checks through gctk rig
# keeps step text that records nothing and stamps self_review_passed_sha on the
# work bead. With no record at all, that stamp naming HEAD stands in for the
# records, so such a run still converges.
if [ -n "$UNRECORDED" ]; then
	LEGACY_SHA=$(printf '%s' "$ISSUE_JSON" | jq -r '.[0].metadata.self_review_passed_sha // empty')
	if [ "$UNRECORDED" = " test lint typecheck" ] && [ "$LEGACY_SHA" = "$HEAD_SHA" ]; then
		note "PASS: self-review green at $HEAD_SHA, by the stamp of a run poured before its checks were recorded"
		exit 0
	fi
	incomplete "nothing recorded at $HEAD_SHA for:$UNRECORDED; the checks have not run at this commit, so another iteration is needed"
fi

note "PASS: self-review green at $HEAD_SHA"
exit 0
