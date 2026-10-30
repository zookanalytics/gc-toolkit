#!/usr/bin/env bash
# store-only-exit — mol-polecat-work's store-only exit, before the step records
# the exit and hands the work bead back: the check that the run has nothing to
# land, and, when the record the run wrote finishes the bead, the hand-off to
# the bead's validating closer.
#
#   store-only-exit.sh --bead <work-bead> --base <branch>
#                      [--convoy <input-convoy> --done "<close brief>"]
#
# A run whose whole product is store work, such as a bead filed in another
# rig's store or a record written into this one, has no branch for the refinery
# to merge. The submit step records the exit and releases the work bead through
# hand-back.sh once this script exits 0.
#
# It refuses when the run has work to land: a commit ahead of origin/<base>, an
# uncommitted change, or polecat/<bead> on origin. A run that only forgot to
# commit then lands the normal way, not as store work. It reads the tree the
# bead's work_dir names, or the current directory when that names no directory.
# A probe git cannot answer counts as nothing to land.
#
# --done is for a record that finishes the bead, such as a live check whose
# every check passed. Nothing else would close such a bead: its polecat never
# closes its own work bead, and no closer reads halt_reason, so left open and
# unrouted it reads as work not yet done. --done hands the bead to its
# validating closer, mol-validate-close, which re-checks the record against
# live state, then closes the bead as done, or asks the operator when the
# record does not hold:
#   * the brief is appended to the bead's notes as a
#     `## Close brief (store-only exit, <time>)` section, the claim the closer
#     tests, before the closer is armed;
#   * a `blocks` edge holds the bead on the root of the live run working it,
#     the run run-lib.sh finds poured over --convoy, so the closer pours once
#     this run ends and never beside it as a second live run on the bead;
#   * deferred-dispatch.sh arms mol-validate-close on the pool this run
#     executes on (gc.execution_routed_to, else gc.routed_to), and its
#     reconcile pass slings it once nothing holds the bead.
# The arm refuses a claimed or routed bead, and reconcile never slings over an
# assignee, so --done needs the bead open, unassigned and unrouted, the shape
# Gas City leaves the bead a graph.v2 run works.
#
# Everything is read and checked before anything is written, and each write is
# read back. The first one that does not land exits 1, and the step drains
# without recording the exit or handing the bead back, so the step stays
# claimed and the worker that takes it next re-takes the exit. A re-run
# converges: an edge and an arm already in place count as landed, and the notes
# gain a second copy of the brief.
#
# Callers: mol-polecat-work's submit-and-exit, step 0.
# exit: 0 nothing to land, and with --done the closer is held and armed ·
#       1 refused, or a write did not land · 2 usage
set -uo pipefail

PROG="store-only-exit"
CLOSER="mol-validate-close"

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

usage() {
  cat >&2 <<'USAGE'
usage: store-only-exit.sh --bead <work-bead> --base <branch>
                          [--convoy <input-convoy> --done "<close brief>"]

  --bead     the work bead the run was poured for
  --base     the branch the run's worktree was cut from
  --convoy   the run's input convoy, which names the run whose root holds the
             validating closer until the run ends; required with --done
  --done     the close brief, when the record the run wrote finishes the bead:
             what the record shows, why that meets what the bead asks for, and
             anything that argues for keeping it open. Empty means the record
             does not finish the bead, and nothing is handed off.

exit: 0 nothing to land, and with --done the closer is held and armed ·
      1 refused, or a write did not land · 2 usage
USAGE
}

require_value() {
  if [ "$#" -lt 2 ]; then
    echo "$PROG: $1 requires a value" >&2; usage; exit 2
  fi
  case "$2" in
    --bead|--base|--convoy|--done|-h|--help)
      echo "$PROG: $1 requires a value, but the next argument is the option '$2'" >&2; usage; exit 2 ;;
  esac
}

BEAD=""; BASE=""; CONVOY=""; DONE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --bead)   require_value "$@"; BEAD="$2";   shift 2 ;;
    --base)   require_value "$@"; BASE="$2";   shift 2 ;;
    --convoy) require_value "$@"; CONVOY="$2"; shift 2 ;;
    --done)
      # An empty brief is a value: the step passes its brief whether or not it
      # wrote one.
      [ "$#" -ge 2 ] || { echo "$PROG: --done requires a value" >&2; usage; exit 2; }
      DONE="$2"; shift 2 ;;
    -h|--help) usage; exit 2 ;;
    *) echo "$PROG: unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done
if [ -z "$BEAD" ] || [ -z "$BASE" ]; then
  echo "$PROG: --bead and --base are required" >&2; usage; exit 2
fi
if [ -n "$DONE" ] && [ -z "$CONVOY" ]; then
  echo "$PROG: --done needs --convoy, the input convoy that names the run whose root holds the closer" >&2; usage; exit 2
fi
case "$BEAD$BASE$CONVOY" in
  *'{{'*|*'}}'*)
    echo "$PROG: an argument was passed unsubstituted ('$BEAD' '$BASE' '$CONVOY'); the pour did not render it" >&2; exit 2 ;;
esac
case "$BEAD$CONVOY" in
  *[!A-Za-z0-9._-]*)
    echo "$PROG: --bead and --convoy must contain only [A-Za-z0-9._-]" >&2; exit 2 ;;
esac
case "$BASE" in
  *[!A-Za-z0-9._/-]*)
    echo "$PROG: --base must contain only [A-Za-z0-9._/-]" >&2; exit 2 ;;
esac

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$SCRIPT_DIR/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 1; }
# shellcheck source=run-lib.sh
. "${GC_RUN_LIB:-$SCRIPT_DIR/run-lib.sh}" || { echo "$PROG: cannot source run-lib.sh beside this script" >&2; exit 1; }
DEFERRED="${GC_DEFERRED_DISPATCH_TOOL:-$SCRIPT_DIR/deferred-dispatch.sh}"

# run-lib.sh's reader: bd's own arguments, against the store gc bd answers from.
store_read() { gc bd "$@"; }

ROW=$(bd_json show "$BEAD")
if ! printf '%s' "$ROW" | jq -e 'type == "array" and length > 0 and (.[0] | type) == "object"' >/dev/null 2>&1; then
  echo "$PROG: could not read $BEAD; nothing was written" >&2
  exit 1
fi
row_field() { printf '%s' "$ROW" | jq -r "$1" 2>/dev/null; }
STATUS=$(row_field '.[0].status // ""')
ASSIGNEE=$(row_field '.[0].assignee // ""')
ROUTED=$(row_field '.[0].metadata["gc.routed_to"] // ""')
POOL=$(row_field '.[0].metadata as $m | [ $m["gc.execution_routed_to"], $m["gc.routed_to"] ] | map(select(. != null and . != "")) | .[0] // ""')
WORK_DIR=$(row_field '.[0].metadata.work_dir // ""')

# ── Nothing to land ──────────────────────────────────────────────────────────
TREE="."
[ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ] && TREE="$WORK_DIR"
AHEAD=$(git -C "$TREE" rev-list --count "origin/$BASE..HEAD" 2>/dev/null) || AHEAD=0
DIRTY=$(git -C "$TREE" status --porcelain 2>/dev/null) || DIRTY=""
PUSHED=$(git -C "$TREE" ls-remote origin "refs/heads/polecat/$BEAD" 2>/dev/null) || PUSHED=""
if [ "${AHEAD:-0}" != "0" ] || [ -n "$DIRTY" ] || [ -n "$PUSHED" ]; then
  echo "STORE-ONLY EXIT REFUSED: this run has work to land"
  echo "  tree read: $TREE"
  echo "  commits ahead of origin/$BASE: ${AHEAD:-0}"
  echo "  uncommitted changes: ${DIRTY:+yes}"
  echo "  branch already on origin: ${PUSHED:+polecat/$BEAD}"
  echo "Land it the normal way: branch gate, target resolve, refinery handoff."
  echo "If none of it is yours, that tree is not this run's own worktree: mail the witness that fact instead of releasing the bead."
  exit 1
fi

if [ -z "$DONE" ]; then
  echo "$PROG: $BEAD has nothing to land"
  exit 0
fi

# ── The validating closer: checked before anything is written ──────────────
if [ "$STATUS" != open ] || [ -n "$ASSIGNEE" ] || [ -n "$ROUTED" ]; then
  echo "$PROG: $BEAD is status '$STATUS', assignee '$ASSIGNEE', gc.routed_to '$ROUTED'. Its validating closer is armed only on an open, unassigned and unrouted bead, the shape a graph.v2 run leaves its work bead in, so nothing was written" >&2
  exit 1
fi
case "$POOL" in
  */*) ;;
  *)
    echo "$PROG: $BEAD names no rig-qualified pool its run executes on (gc.execution_routed_to and gc.routed_to gave '$POOL'), so there is no pool to arm its validating closer on; nothing was written" >&2
    exit 1 ;;
esac
[ -x "$DEFERRED" ] || { echo "$PROG: deferred-dispatch.sh not found at $DEFERRED; nothing was written" >&2; exit 1; }
if ! RUNS=$(run_lib subject store_read "$CONVOY"); then
  echo "$PROG: could not read the runs poured over $CONVOY; nothing was written" >&2
  exit 1
fi
ROOT=$(printf '%s' "$RUNS" | jq -r --arg b "$BEAD" '
  [ .[] | select(.live and .bead == $b) | .root ] | unique
  | if length == 1 then .[0] else empty end' 2>/dev/null)
if [ -z "$ROOT" ]; then
  echo "$PROG: no single live run over $CONVOY works $BEAD, so no run root can hold its validating closer until the run ends; nothing was written" >&2
  exit 1
fi

# ── The brief, the hold, the arm ─────────────────────────────────────────────
if ! gc bd update "$BEAD" --append-notes "## Close brief (store-only exit, $(date -u +%Y-%m-%dT%H:%M:%SZ))
$DONE" </dev/null >/dev/null 2>&1; then
  echo "$PROG: the close brief did not land on $BEAD, so its validating closer was not armed" >&2
  exit 1
fi

# `dep add <bead> <blocker>` reads "<bead> is blocked by <blocker>".
holds_on_root() {
  bd_json dep list "$BEAD" | jq -e --arg r "$ROOT" '
    type == "array" and any(.[]; (.id // .depends_on_id // "") == $r
                               and ((.dependency_type // .type // "") == "blocks"))' >/dev/null 2>&1
}
if ! holds_on_root; then
  gc bd dep add "$BEAD" "$ROOT" --type=blocks </dev/null >/dev/null 2>&1 || true
  if ! holds_on_root; then
    echo "$PROG: the blocks edge from $BEAD onto its run's root $ROOT did not land, so its validating closer was not armed" >&2
    exit 1
  fi
fi

if ! ARM_OUT=$("$DEFERRED" arm "$BEAD" --target "$POOL" --sling-arg --on --sling-arg "$CLOSER" \
    --reason "store-only exit: its record finishes it, which $CLOSER re-checks" 2>&1 </dev/null); then
  echo "$PROG: the validating closer was not armed on $BEAD: $ARM_OUT" >&2
  exit 1
fi
BACK=$(bd_json show "$BEAD")
ARMED=$(printf '%s' "$BACK" | jq -r '.[0].metadata["gc.dispatch_when_ready"] // empty' 2>/dev/null)
ARMED_ON=$(printf '%s' "$BACK" | jq -r '(.[0].metadata["gc.dispatch_when_ready_args"] // "") | tostring' 2>/dev/null)
case "$ARMED_ON" in
  *"\"$CLOSER\""*) ;;
  *) ARMED_ON="" ;;
esac
if [ "$ARMED" != "$POOL" ] || [ -z "$ARMED_ON" ]; then
  echo "$PROG: $BEAD reads back armed to '$ARMED' with sling arguments that do not pour $CLOSER; its validating closer is not armed" >&2
  exit 1
fi
echo "$PROG: $BEAD has nothing to land, and $CLOSER is armed on $POOL, held on run $ROOT, so it re-checks the record once this run ends"
exit 0
