#!/bin/bash
# Judge for the `iterate` check loop in mol-goal-keeper (docs/goal-keeper.md).
#
# Runs when a goal iteration closes. Re-reads the goal contract, re-runs the
# oracle against reality, renders exactly one verdict, and writes the verdict
# trail. Exit code drives the loop:
#
#   exit 0  the loop is terminally resolved — the goal is `met` (closed) or
#           parked (`impossible` / `stalled` / `exhausted`, reassigned to the
#           escalation target). The orchestrator closes the control bead.
#   exit 1  `not-yet` — the oracle still fails, the reason is actionable, and a
#           bound remains. The loop appends the next iteration with the reason
#           threaded forward.
#
# Every internal error also exits 1 (fail-closed): a false `met` would close a
# goal reality never met, so the judge never declares met on a measurement it
# could not make. A broken oracle therefore loops until a bound trips and the
# goal parks with the error in its trail — visible, never silently met.
#
# ## Why the judge runs the oracle instead of trusting the worker
#
# A model cannot judge its own homework. The iteration worker that did the work
# never renders the verdict; this judge runs the oracle itself and reads the
# store and the tree directly, because an agent that summarizes its own success
# is not evidence. v1 oracles are deterministic — a command's exit code or a
# metric compared to a threshold — so the judge reaches a binary verdict without
# model judgment, and a number cannot be talked out of its result.
#
# ## Why the oracle must be cheap
#
# This runs inline in the control dispatcher on the sandboxed condition PATH
# (bd, gc, dolt, jq plus /usr/local/bin:/usr/bin:/bin), HOME redirected to the
# city root, bounded by the step's check.timeout, and it blocks the dispatcher
# for its whole duration. So the oracle it runs must be a fast deterministic
# measurement — a bead-store query, a quick metric — never a long build or
# benchmark. A goal whose oracle is heavy needs the engine telemetry interface
# (gc-vz6v0), out of v1 scope.
#
# ## Why resolution is bd-only
#
# Every bead read here goes through `bd`, never `gc bd`: `gc` first loads the
# full city config including the pack import closure, which can be cold in the
# condition env and then dies before doing anything. Raw `bd` talks to the store
# directly. Each call site carries a `# raw-bd:` marker for the lint. Same
# contract as rebase-check.sh / self-review-check.sh.
#
# ## Why the judge parks the goal itself
#
# A terminal park (impossible / stalled / exhausted) and the ceiling's last
# attempt are both moments after which nothing else runs — the orchestrator
# closes the control bead and stops. So the judge does the handback itself, the
# same shape the other check loops use: reassign the goal to its escalation
# target, set goal.status=parked with the reason and closest-approach evidence,
# and nudge. Every write is best-effort and cannot change the verdict.
#
# exit: 0 goal met or parked (loop done) · 1 not-yet, or any internal error
#         (fail-closed, loop continues until a bound parks it)

set -uo pipefail

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

# Resolved as we go; the park handback needs them and runs from paths that can
# fire before they are set.
ROOT=""
GOAL=""
SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd 2>/dev/null || echo)"

note() { printf 'goal-judge: %s\n' "$1" >&2; }

# A truthful "keep going": the loop should run another iteration unless a bound
# has tripped, which the callers check before reaching here.
not_yet() {
	note "not-yet: $1"
	record_trail not-yet "$1" "${2:-}" "${3:-}"
	# Thread the verdict forward: mol-goal-keeper's iterate step reads
	# goal.not_yet_reason as its assignment, and goal-arm.sh seeds only the
	# baseline, so without this write every iteration after the first re-reads
	# that stale baseline instead of the judge's current reason.
	if [ -n "$GOAL" ]; then
		# raw-bd: gc bd loads the city config, which can be cold in the condition env
		bd update "$GOAL" --set-metadata "goal.not_yet_reason=$1" >/dev/null 2>&1 ||
			note "WARN: could not thread not_yet_reason forward on $GOAL"
	fi
	exit 1
}

# A fail-closed error: never met, so the loop continues and a bound eventually
# parks the goal with this reason in the trail.
fail() {
	note "FAIL: $1"
	record_trail error "$1" ""
	# On the ceiling's last attempt an error would otherwise strand the goal:
	# the orchestrator closes the control bead and nothing runs. Park it.
	park_if_ceiling_reached "error: $1"
	exit 1
}

# --- the goal contract, read once --------------------------------------------
GOAL_JSON=""
read_goal() {
	[ -n "$GOAL" ] || return 1
	# raw-bd: gc bd loads the city config, which can be cold here
	GOAL_JSON=$(bd show "$GOAL" --json 2>/dev/null | scrub) || return 1
	case "$(printf '%s' "$GOAL_JSON" | jq -r 'type' 2>/dev/null)" in
	array) return 0 ;;
	*) return 1 ;;
	esac
}

meta() { printf '%s' "$GOAL_JSON" | jq -r --arg k "$1" '.[0].metadata[$k] // empty' 2>/dev/null; }

# Canonical serialization of the contract, for the tamper-evident snapshot.
# Delegated to goal-canonical.sh so arm and judge compute it identically — see
# that script's header on why a second implementation would break re-arming.
canonical_contract() {
	printf '%s' "$GOAL_JSON" | "$SCRIPTS_DIR/goal-canonical.sh" 2>/dev/null
}

# --- the verdict trail, append-only, keyed on attempt ------------------------
# One entry per attempt on goal.trail. Refuses to append to something that does
# not read back as an array; a blind append is how an audit log grows without
# bound exactly when something is wrong.
record_trail() {
	local verdict="$1" reason="$2" value="${3:-}" sig="${4:-}"
	[ -n "$GOAL" ] || return 0
	[ -n "$sig" ] || sig="$reason"
	local attempt="${GC_ITERATION:-}"
	case "$attempt" in '' | *[!0-9]*) attempt=0 ;; esac

	local entry
	entry=$(jq -nc \
		--argjson attempt "$attempt" \
		--arg verdict "$verdict" \
		--arg reason "$reason" \
		--arg value "$value" \
		--arg sig "$sig" \
		--arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" \
		--arg iter "${GC_BEAD_ID:-}" \
		'{attempt:$attempt, verdict:$verdict, reason:$reason, value:$value,
		  sig:$sig, at:$at, iteration_bead:$iter}
		 | with_entries(select(.value != null and .value != ""))' 2>/dev/null) || return 0
	[ -n "$entry" ] || return 0

	local fresh log updated
	# raw-bd: paired reads/writes in the minimal condition env
	fresh=$(bd show "$GOAL" --json 2>/dev/null | scrub) || return 0
	log=$(printf '%s' "$fresh" | jq -c '
		(.[0].metadata["goal.trail"] // "[]")
		| (if type == "string" then (fromjson? // null) else . end)
		| if type == "array" then . else null end' 2>/dev/null)
	if [ -z "$log" ] || [ "$log" = "null" ]; then
		note "WARN: goal.trail on $GOAL is unreadable; not recording attempt $attempt"
		return 0
	fi
	updated=$(printf '%s' "$log" | jq -c --argjson e "$entry" '
		if any(.[]; .attempt == $e.attempt and .verdict == $e.verdict) then . else . + [$e] end' 2>/dev/null) || return 0
	[ -n "$updated" ] || return 0
	# raw-bd: gc bd loads the city config, which can be cold in the condition env
	bd update "$GOAL" --set-metadata "goal.trail=$updated" >/dev/null 2>&1 ||
		note "WARN: could not record trail for attempt $attempt on $GOAL"
}

# The prior trail, parsed, for stall and closest-approach checks.
trail_array() {
	printf '%s' "$GOAL_JSON" | jq -c '
		(.[0].metadata["goal.trail"] // "[]")
		| (if type == "string" then (fromjson? // []) else . end)
		| if type == "array" then . else [] end' 2>/dev/null
}

# --- park the goal (impossible / stalled / exhausted) ------------------------
park() {
	local verdict="$1" reason="$2" value="${3:-}"
	record_trail "$verdict" "$reason" "$value"
	[ -n "$GOAL" ] || { note "cannot park: goal unresolved"; return 0; }

	# Re-read: an earlier retried exec of this attempt may already have parked.
	local fresh already
	# raw-bd: gc bd loads the city config, which can be cold in the condition env
	fresh=$(bd show "$GOAL" --json 2>/dev/null | scrub) || fresh=""
	already=$(printf '%s' "$fresh" | jq -r '.[0].metadata["goal.status"] // empty' 2>/dev/null)
	if [ "$already" = "parked" ] || [ "$already" = "met" ]; then
		note "goal $GOAL already $already; leaving it"
		return 0
	fi

	local target
	target=$(printf '%s' "$fresh" | jq -r '.[0].metadata["goal.escalation_target"] // empty' 2>/dev/null)
	[ -n "$target" ] || target="human"

	# raw-bd: gc bd loads the city config, which can be cold in the condition env
	bd update "$GOAL" \
		--status=open \
		--assignee "$target" \
		--set-metadata "goal.status=parked" \
		--set-metadata "goal.parked_verdict=$verdict" \
		--append-notes "$(cat <<EOF
Goal parked: $verdict (goal-keeper).

Reason: $reason
Closest approach: ${value:-(not measured)}
Attempt: ${GC_ITERATION:-?}

The keeper loop has stopped; no further iteration will run. goal.trail carries
the per-attempt verdicts. Decide the disposition — re-state the goal and re-arm
with goal-arm.sh, or close it — then this hold releases.
EOF
	)" >/dev/null 2>&1 || { note "WARN: park write failed for $GOAL"; return 0; }

	note "parked $GOAL to $target ($verdict): $reason"
	gc session nudge "$target" \
		"goal $GOAL parked: $verdict — $reason (goal.trail has the detail)" \
		>/dev/null 2>&1 || true
}

# The loop ceiling from the control bead's gc.max_attempts (the formula's
# max_attempts). The condition env leaves GC_MAX_ITERATIONS at zero, so it comes
# from the beads. Echoes nothing when it cannot be resolved.
resolve_ceiling() {
	[ -n "$ROOT" ] || return 0
	local direct
	if [ -n "${GC_BEAD_ID:-}" ]; then
		# raw-bd: gc bd loads the city config, which can be cold in the condition env
		direct=$(bd show "$GC_BEAD_ID" --json 2>/dev/null | scrub |
			jq -r '.[0].metadata."gc.max_attempts" // empty' 2>/dev/null)
		[ -n "$direct" ] && { printf '%s' "$direct"; return 0; }
	fi
	# raw-bd: gc bd loads the city config, which can be cold in the condition env
	bd list --all --include-infra --limit 0 --json \
		--metadata-field "gc.root_bead_id=$ROOT" \
		--metadata-field "gc.kind=ralph" 2>/dev/null | scrub |
		jq -r '.[0].metadata."gc.max_attempts" // empty' 2>/dev/null
}

park_if_ceiling_reached() {
	local reason="$1"
	local attempt ceiling
	attempt="${GC_ITERATION:-}"
	case "$attempt" in '' | *[!0-9]*) return 0 ;; esac
	ceiling=$(resolve_ceiling)
	case "$ceiling" in '' | *[!0-9]*) return 0 ;; esac
	[ "$ceiling" -gt 0 ] || return 0
	[ "$attempt" -ge "$ceiling" ] || return 0
	park exhausted "loop ceiling reached ($attempt/$ceiling): $reason" ""
	# The ceiling is terminal: nothing runs after this attempt, so stop the loop
	# on the parked goal rather than falling through to another verdict.
	exit 0
}

# --- 1. Resolve the molecule root and the goal bead --------------------------
ROOT="${GC_WISP_ID:-}"
if [ -z "$ROOT" ]; then
	[ -n "${GC_BEAD_ID:-}" ] || fail "neither GC_WISP_ID nor GC_BEAD_ID is set"
	# raw-bd: gc bd loads the city config, which can be cold in the condition env
	ROOT=$(bd show "$GC_BEAD_ID" --json 2>/dev/null | scrub |
		jq -r '.[0].metadata."gc.root_bead_id" // empty' 2>/dev/null)
fi
[ -n "$ROOT" ] || fail "could not resolve the molecule root bead"

# raw-bd: gc bd loads the city config, which can be cold in the condition env
ROOT_JSON=$(bd show "$ROOT" --json 2>/dev/null | scrub) || fail "could not read root bead $ROOT"
GOAL=$(printf '%s' "$ROOT_JSON" | jq -r '.[0].metadata."gc.var.issue" // empty' 2>/dev/null)

# Cross-check against the input convoy's single tracked member when readable; the
# two disagreeing means the molecule is wired wrong and judging the wrong bead is
# the false verdict this exists to prevent.
CONVOY=$(printf '%s' "$ROOT_JSON" |
	jq -r '.[0].metadata."gc.input_convoy_id" // .[0].metadata."gc.var.convoy_id" // empty' 2>/dev/null)
if [ -n "$CONVOY" ]; then
	# raw-bd: gc bd loads the city config, which can be cold in the condition env
	MEMBERS=$(bd dep tree "$CONVOY" --json 2>/dev/null | scrub |
		jq -r --arg c "$CONVOY" '[.[] | select((.depth // 0) == 1 and (.parent_id // "") == $c) | .id]' 2>/dev/null)
	MEMBER=$(printf '%s' "$MEMBERS" | jq -r 'if type=="array" and length==1 then .[0] else empty end' 2>/dev/null)
	if [ -n "$MEMBER" ]; then
		if [ -z "$GOAL" ]; then
			GOAL="$MEMBER"
		elif [ "$GOAL" != "$MEMBER" ]; then
			fail "root $ROOT gc.var.issue=$GOAL disagrees with convoy $CONVOY member $MEMBER"
		fi
	fi
fi
[ -n "$GOAL" ] || fail "could not resolve the goal bead from root $ROOT"

read_goal || fail "could not read goal bead $GOAL"

# --- 2. Tamper-evidence: compare the contract to its arming snapshot ----------
SNAPSHOT=$(meta "goal.snapshot")
CURRENT=$(canonical_contract)
[ -n "$CURRENT" ] || fail "could not serialize the contract on $GOAL"
if [ -z "$SNAPSHOT" ]; then
	# Not armed through goal-arm.sh, or an older run. Adopt the current contract
	# as the snapshot so tamper-evidence starts from here, and say so.
	# raw-bd: gc bd loads the city config, which can be cold in the condition env
	bd update "$GOAL" --set-metadata "goal.snapshot=$CURRENT" >/dev/null 2>&1 || true
	record_trail re-armed "no arming snapshot found; adopted the current contract" ""
elif [ "$SNAPSHOT" != "$CURRENT" ]; then
	# The contract changed after arming. Re-arm against it and record the change,
	# rather than judging against goalposts that moved.
	# raw-bd: gc bd loads the city config, which can be cold in the condition env
	bd update "$GOAL" --set-metadata "goal.snapshot=$CURRENT" >/dev/null 2>&1 || true
	record_trail re-armed "contract changed after arming; re-armed against the current contract" ""
	read_goal || true
fi

# --- 3. Run the oracle -------------------------------------------------------
ORACLE_KIND=$(meta "goal.oracle.kind")
ORACLE_CMD=$(meta "goal.oracle.command")
[ -n "$ORACLE_CMD" ] || fail "goal $GOAL has no goal.oracle.command"

# The oracle may reference pack scripts through $GOAL_SCRIPTS_DIR.
export GOAL_SCRIPTS_DIR="$SCRIPTS_DIR"
export GOAL_BEAD="$GOAL"

ORACLE_OUT=""
ORACLE_RC=0
# Capture stdout for the result; let the oracle's stderr flow to this judge's
# stderr (the dispatcher log). An oracle prints its machine-readable result — a
# metric value, or a reason — as the last line of stdout, and diagnostics to
# stderr, so a chatty oracle cannot bury its value.
ORACLE_OUT=$(bash -c "$ORACLE_CMD")
ORACLE_RC=$?
ORACLE_LAST=$(printf '%s\n' "$ORACLE_OUT" | grep -v '^[[:space:]]*$' | tail -n 1)

MET=1          # 1 = not met, 0 = met
VALUE=""
REASON=""
# The stall signature: the stable part of a not-met verdict, without the
# measured value. Section 6c keys the stall check on this, not on REASON, so a
# metric whose value changes each attempt (and so changes REASON) is still
# recognized as the same wedged failure. Empty falls back to REASON there.
SIGNATURE=""

case "$ORACLE_KIND" in
metric)
	VALUE="$ORACLE_LAST"
	COMPARE=$(meta "goal.oracle.compare")
	THRESHOLD=$(meta "goal.oracle.threshold")
	# An oracle that cannot produce a comparable measurement — nonzero exit, or
	# empty/non-numeric output — is a not-met with an actionable reason, threaded
	# through section 6 like any other not-met so the shared bounds still park it.
	# Exiting early here (the old not_yet path) skipped the wall-clock, iteration
	# budget, stall, and ceiling checks, so a permanently broken metric oracle
	# looped until the formula ceiling stopped the control bead without ever
	# parking the goal for a human.
	METRIC_ERR=""
	if [ "$ORACLE_RC" -ne 0 ]; then
		METRIC_ERR="metric oracle exited $ORACLE_RC: ${ORACLE_LAST:-no output}"
	else
		case "$VALUE" in
		'' | *[!0-9.+-]*) METRIC_ERR="metric oracle printed a non-numeric value: '${VALUE}'" ;;
		esac
	fi
	if [ -n "$METRIC_ERR" ]; then
		MET=1; VALUE=""; REASON="$METRIC_ERR"
	else
		case "$THRESHOLD" in
		'' | *[!0-9.+-]*) fail "goal.oracle.threshold is not numeric: '${THRESHOLD}'" ;;
		esac
		# awk does the float compare; met per the operator.
		CMP=$(awk -v v="$VALUE" -v t="$THRESHOLD" -v op="$COMPARE" 'BEGIN{
			if (op=="lt") print (v<t)?1:0;
			else if (op=="le") print (v<=t)?1:0;
			else if (op=="gt") print (v>t)?1:0;
			else if (op=="ge") print (v>=t)?1:0;
			else print "err";
		}')
		case "$CMP" in
		1) MET=0; REASON="measured $VALUE ${COMPARE} threshold $THRESHOLD — met" ;;
		0) MET=1; REASON="measured $VALUE, need ${COMPARE} $THRESHOLD"; SIGNATURE="need ${COMPARE} $THRESHOLD" ;;
		*) fail "goal.oracle.compare must be one of lt le gt ge (got '${COMPARE}')" ;;
		esac
	fi
	;;
command | "")
	# Exit 0 = met; 3 = impossible (reserved); anything else = not met.
	if [ "$ORACLE_RC" -eq 0 ]; then
		MET=0; REASON="${ORACLE_LAST:-oracle exited 0 — met}"
	elif [ "$ORACLE_RC" -eq 3 ]; then
		park impossible "oracle reports the goal unsatisfiable as stated: ${ORACLE_LAST:-exit 3}" ""
		exit 0
	else
		MET=1; VALUE=""; REASON="oracle exited $ORACLE_RC: ${ORACLE_LAST:-not met}"
	fi
	;;
*)
	fail "goal.oracle.kind must be metric or command (got '${ORACLE_KIND}')"
	;;
esac

# --- 4. Invariants: a violated invariant fails the iteration even if met ------
INV=$(meta "goal.invariants")
if [ -n "$INV" ] && [ "$INV" != "[]" ]; then
	INV_LIST=$(printf '%s' "$INV" | jq -r '(if type=="string" then (fromjson? // []) else . end)[]?' 2>/dev/null)
	while IFS= read -r inv_cmd; do
		[ -n "$inv_cmd" ] || continue
		if ! bash -c "$inv_cmd" >/dev/null 2>&1; then
			# Broken invariant is a not-yet regardless of the oracle: the reason
			# is to restore the invariant. The invariant, not any metric measured
			# above, is the failure signature now, so clear a metric SIGNATURE and
			# let section 6c fall back to this reason.
			MET=1
			REASON="invariant violated: $inv_cmd"
			SIGNATURE=""
			break
		fi
	done <<-INVEOF
	$INV_LIST
	INVEOF
fi

# --- 5. Met is terminal ------------------------------------------------------
if [ "$MET" -eq 0 ]; then
	record_trail met "$REASON" "$VALUE"
	# raw-bd: gc bd loads the city config, which can be cold in the condition env
	bd update "$GOAL" \
		--status=closed \
		--set-metadata "goal.status=met" \
		--append-notes "$(cat <<EOF
Goal met (goal-keeper): $REASON

goal.trail carries the per-attempt convergence record. Closing on met.
EOF
	)" >/dev/null 2>&1 || note "WARN: could not close met goal $GOAL"
	note "PASS: goal $GOAL met — $REASON"
	exit 0
fi

# --- 6. Not met: park on a tripped bound, else keep iterating -----------------
ATTEMPT="${GC_ITERATION:-0}"
case "$ATTEMPT" in '' | *[!0-9]*) ATTEMPT=0 ;; esac

# 6a. wall-clock deadline (absolute ISO, stamped at arming).
DEADLINE=$(meta "goal.wall_clock_deadline")
if [ -n "$DEADLINE" ]; then
	NOW_EPOCH=$(date -u +%s 2>/dev/null)
	DL_EPOCH=$(date -u -d "$DEADLINE" +%s 2>/dev/null || date -u -j -f %Y-%m-%dT%H:%M:%SZ "$DEADLINE" +%s 2>/dev/null || echo)
	if [ -n "$DL_EPOCH" ] && [ -n "$NOW_EPOCH" ] && [ "$NOW_EPOCH" -gt "$DL_EPOCH" ]; then
		park exhausted "wall-clock budget exhausted (deadline $DEADLINE): $REASON" "$VALUE"
		exit 0
	fi
fi

# 6b. iteration budget: the smaller of goal.budget.max_iterations and the ceiling.
MAXIT=$(meta "goal.budget.max_iterations")
case "$MAXIT" in '' | *[!0-9]*) MAXIT="" ;; esac
if [ -n "$MAXIT" ] && [ "$ATTEMPT" -ge "$MAXIT" ]; then
	park exhausted "iteration budget exhausted ($ATTEMPT/$MAXIT): $REASON" "$VALUE"
	exit 0
fi

# 6c. stalled: the same failure signature as the previous attempt, with no
# closest-approach improvement. Detecting the wedge early parks before the rest
# of the budget burns. The signature is value-free on purpose: a metric reason
# embeds the measured value, so keying the stall on the reason would never fire
# when the value moves — even when it moves away from the threshold. Keying on
# the signature and comparing the measured value separately catches a wedged or
# worsening metric, while progressing-but-slow (the value moved toward the
# threshold) stays not-yet.
if [ -z "$REASON" ]; then
	# A not-yet with no actionable reason is a stall by definition.
	park stalled "oracle failed with no actionable reason" "$VALUE"
	exit 0
fi
[ -n "$SIGNATURE" ] || SIGNATURE="$REASON"
PRIOR=$(trail_array)
PREV=$(printf '%s' "$PRIOR" | jq -c '[.[] | select(.verdict=="not-yet")] | last // {}' 2>/dev/null)
PREV_SIG=$(printf '%s' "$PREV" | jq -r '.sig // .reason // empty' 2>/dev/null)
PREV_VALUE=$(printf '%s' "$PREV" | jq -r '.value // empty' 2>/dev/null)
if [ -n "$PREV_SIG" ] && [ "$PREV_SIG" = "$SIGNATURE" ]; then
	IMPROVED=1
	if [ -n "$VALUE" ] && [ -n "$PREV_VALUE" ]; then
		COMPARE=$(meta "goal.oracle.compare")
		IMPROVED=$(awk -v v="$VALUE" -v p="$PREV_VALUE" -v op="$COMPARE" 'BEGIN{
			if (op=="lt"||op=="le") print (v<p)?1:0;
			else if (op=="gt"||op=="ge") print (v>p)?1:0;
			else print 0;
		}')
	elif [ -z "$VALUE" ] && [ -z "$PREV_VALUE" ]; then
		IMPROVED=0
	fi
	if [ "$IMPROVED" = "0" ]; then
		park stalled "repeating failure with no closest-approach improvement: $REASON" "$VALUE"
		exit 0
	fi
fi

# 6d. ceiling backstop, then keep iterating.
park_if_ceiling_reached "$REASON"   # parks and exits 0 only if the ceiling is hit
not_yet "$REASON" "$VALUE" "$SIGNATURE"
