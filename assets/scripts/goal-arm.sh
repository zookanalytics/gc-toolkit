#!/usr/bin/env bash
# Arm a goal: record its contract snapshot and pour the keeper loop
# (docs/goal-keeper.md). This is the keeper's arming action — it runs before the
# first iteration and is where the tamper-evident snapshot is taken.
#
# Usage:
#   goal-arm.sh <goal-bead> [contract flags] [--iteration-target <pool>] [--dry-run]
#
# Contract flags (any provided are written to the goal bead before arming; omit
# them to arm a goal whose goal.* metadata is already set):
#   --statement <text>           the measurable end state
#   --oracle-kind metric|command
#   --oracle-command <cmd>       the command the judge runs; may reference pack
#                                scripts via "$GOAL_SCRIPTS_DIR/<name>.sh"
#   --compare lt|le|gt|ge        (metric) met when value <op> threshold
#   --threshold <number>         (metric) the threshold
#   --max-iterations <n>         iteration budget (required)
#   --wall-clock <dur|iso>       e.g. 72h, 30d, or an absolute 2026-10-01T00:00:00Z
#   --token-budget <n>           recorded; enforcement waits on engine telemetry
#   --invariant <cmd>            repeatable; each must exit 0 every iteration
#   --escalation-target <addr>   who receives a park (default: human)
#   --owner <text> / --provenance <text>
#   --iteration-target <pool>    pool the loop routes iterations to
#                                (default: gc-toolkit/gc-toolkit.polecat)
#   --dry-run                    validate and snapshot, do not write or sling
#
# exit: 0 armed (or, with --dry-run, valid and snapshotted) · 1 a write or the
#         sling failed · 2 usage error or an incomplete/invalid contract
set -uo pipefail

PROG=goal-arm
warn() { echo "$PROG: $*" >&2; }
die()  { warn "$*"; exit "${2:-1}"; }

usage() { cat >&2 <<'USAGE'
usage: goal-arm.sh <goal-bead> [contract flags] [--iteration-target <pool>] [--dry-run]
  see the script header for the full flag list. --max-iterations, a statement,
  and an oracle are required to arm.
USAGE
}

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub
bd_json() { gc bd "$@" --json 2>/dev/null | scrub; }

HERE="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"

GOAL=""
ITERATION_TARGET="gc-toolkit/gc-toolkit.polecat"
DRY_RUN=0
declare -a INVARIANTS=()
# Contract fields to apply, as key<TAB>value, in one pass below.
declare -a SETS=()
set_meta() { SETS+=("$1"$'\t'"$2"); }

require_value() { [ $# -ge 2 ] || { usage; exit 2; }; case "$2" in --*) usage; exit 2;; esac; }

while [ $# -gt 0 ]; do
	case "$1" in
	--statement)         require_value "$@"; set_meta goal.statement "$2"; shift 2 ;;
	--oracle-kind)       require_value "$@"; set_meta goal.oracle.kind "$2"; shift 2 ;;
	--oracle-command)    require_value "$@"; set_meta goal.oracle.command "$2"; shift 2 ;;
	--compare)           require_value "$@"; set_meta goal.oracle.compare "$2"; shift 2 ;;
	--threshold)         require_value "$@"; set_meta goal.oracle.threshold "$2"; shift 2 ;;
	--max-iterations)    require_value "$@"; set_meta goal.budget.max_iterations "$2"; shift 2 ;;
	--token-budget)      require_value "$@"; set_meta goal.budget.token_budget "$2"; shift 2 ;;
	--wall-clock)        require_value "$@"; set_meta goal.budget.wall_clock "$2"; shift 2 ;;
	--invariant)         require_value "$@"; INVARIANTS+=("$2"); shift 2 ;;
	--escalation-target) require_value "$@"; set_meta goal.escalation_target "$2"; shift 2 ;;
	--owner)             require_value "$@"; set_meta goal.owner "$2"; shift 2 ;;
	--provenance)        require_value "$@"; set_meta goal.provenance "$2"; shift 2 ;;
	--iteration-target)  require_value "$@"; ITERATION_TARGET="$2"; shift 2 ;;
	--dry-run)           DRY_RUN=1; shift ;;
	-h | --help)         usage; exit 0 ;;
	--*)                 warn "unknown flag '$1'"; usage; exit 2 ;;
	*)
		[ -z "$GOAL" ] || { warn "unexpected argument '$1'"; usage; exit 2; }
		GOAL="$1"; shift ;;
	esac
done

[ -n "$GOAL" ] || { usage; exit 2; }

# The goal bead must exist.
GJSON=$(bd_json show "$GOAL")
case "$(printf '%s' "$GJSON" | jq -r 'type' 2>/dev/null)" in
array) ;;
*) die "goal bead $GOAL not found (or the store is unreadable)" 2 ;;
esac

# Invariants collapse into one JSON-array field.
if [ "${#INVARIANTS[@]}" -gt 0 ]; then
	INV_JSON=$(printf '%s\n' "${INVARIANTS[@]}" | jq -Rsc 'split("\n") | map(select(length>0))')
	set_meta goal.invariants "$INV_JSON"
fi

# Wall-clock: stamp an absolute deadline at arming so the judge enforces it on
# every close. Accept a duration (Ns/Nm/Nh/Nd) or an absolute ISO string.
deadline_from() {
	local spec="$1" secs=""
	case "$spec" in
	*[0-9]s) secs=$(( ${spec%s} )) ;;
	*[0-9]m) secs=$(( ${spec%m} * 60 )) ;;
	*[0-9]h) secs=$(( ${spec%h} * 3600 )) ;;
	*[0-9]d) secs=$(( ${spec%d} * 86400 )) ;;
	*) printf '%s' "$spec"; return 0 ;;   # assume absolute ISO; the judge parses it
	esac
	date -u -d "+${secs} seconds" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
		|| date -u -v+"${secs}"S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null
}

# The effective wall_clock is the flag if given, else what is already on the bead.
WALL=""
for pair in ${SETS[@]+"${SETS[@]}"}; do
	[ "${pair%%$'\t'*}" = "goal.budget.wall_clock" ] && WALL=${pair#*$'\t'}
done
[ -n "$WALL" ] || WALL=$(printf '%s' "$GJSON" | jq -r '.[0].metadata["goal.budget.wall_clock"] // empty' 2>/dev/null)
if [ -n "$WALL" ]; then
	DEADLINE=$(deadline_from "$WALL")
	[ -n "$DEADLINE" ] || die "could not compute a deadline from wall_clock='$WALL'" 2
	set_meta goal.wall_clock_deadline "$DEADLINE"
fi

# The effective contract = the bead's metadata overlaid with the flag values.
# Validate and snapshot from this, so a --dry-run of a flag-provided contract
# validates the same thing a real arm would write.
EFF_META=$(printf '%s' "$GJSON" | jq -c '.[0].metadata // {}')
for pair in ${SETS[@]+"${SETS[@]}"}; do
	key=${pair%%$'\t'*}; val=${pair#*$'\t'}
	EFF_META=$(printf '%s' "$EFF_META" | jq -c --arg k "$key" --arg v "$val" '.[$k]=$v')
done
EFF_JSON="[{\"metadata\": $EFF_META}]"
m() { printf '%s' "$EFF_JSON" | jq -r --arg k "$1" '.[0].metadata[$k] // empty' 2>/dev/null; }

# Validate the effective contract.
MISSING=()
[ -n "$(m goal.statement)" ] || MISSING+=("goal.statement (--statement)")
KIND=$(m goal.oracle.kind); [ -z "$KIND" ] && KIND=command
[ -n "$(m goal.oracle.command)" ] || MISSING+=("goal.oracle.command (--oracle-command)")
MAXIT=$(m goal.budget.max_iterations)
case "$MAXIT" in '' ) MISSING+=("goal.budget.max_iterations (--max-iterations)") ;; *[!0-9]*) die "goal.budget.max_iterations must be a positive integer (got '$MAXIT')" 2 ;; esac
if [ "$KIND" = "metric" ]; then
	case "$(m goal.oracle.compare)" in lt|le|gt|ge) ;; *) MISSING+=("goal.oracle.compare must be lt|le|gt|ge (--compare)") ;; esac
	case "$(m goal.oracle.threshold)" in '' ) MISSING+=("goal.oracle.threshold (--threshold)") ;; *[!0-9.+-]*) die "goal.oracle.threshold must be numeric" 2 ;; esac
fi
if [ "${#MISSING[@]}" -gt 0 ]; then
	warn "incomplete contract; cannot arm. Missing/invalid:"
	for x in "${MISSING[@]}"; do warn "  - $x"; done
	exit 2
fi

# The tamper-evident snapshot, via the shared canonical serializer.
SNAP=$(printf '%s' "$EFF_JSON" | "$HERE/goal-canonical.sh") || die "could not serialize the contract"
[ -n "$SNAP" ] || die "empty contract snapshot"

BASELINE="Baseline iteration: establish the current measurement and make the first bounded improvement toward: $(m goal.statement)"

if [ "$DRY_RUN" -eq 1 ]; then
	echo "contract valid. effective snapshot:"
	echo "  $SNAP"
	for pair in ${SETS[@]+"${SETS[@]}"}; do echo "would set ${pair%%$'\t'*}=${pair#*$'\t'}"; done
	echo "would set goal.snapshot, goal.status=armed, goal.armed_at, goal.not_yet_reason"
	echo "would sling: gc sling $ITERATION_TARGET $GOAL --on mol-goal-keeper --var issue=$GOAL"
	exit 0
fi

# Write the contract fields, one update each so a failure names the field.
for pair in ${SETS[@]+"${SETS[@]}"}; do
	gc bd update "$GOAL" --set-metadata "${pair%%$'\t'*}=${pair#*$'\t'}" >/dev/null 2>&1 \
		|| die "could not write ${pair%%$'\t'*} on $GOAL"
done

gc bd update "$GOAL" \
	--set-metadata "goal.snapshot=$SNAP" \
	--set-metadata "goal.status=armed" \
	--set-metadata "goal.armed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
	--set-metadata "goal.not_yet_reason=$BASELINE" \
	>/dev/null 2>&1 || die "could not record the arming snapshot on $GOAL"

# Pour the keeper loop, routed to the pool so each iteration is a fresh session.
if gc sling ${GC_RIG:+--rig "$GC_RIG"} "$ITERATION_TARGET" "$GOAL" --on mol-goal-keeper --var "issue=$GOAL" >/dev/null 2>&1; then
	echo "$PROG: armed $GOAL and poured mol-goal-keeper at $ITERATION_TARGET"
	echo "$PROG: snapshot $SNAP"
else
	die "snapshot recorded but the sling failed; re-pour with: gc sling $ITERATION_TARGET $GOAL --on mol-goal-keeper --var issue=$GOAL"
fi
