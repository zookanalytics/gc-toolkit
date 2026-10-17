#!/usr/bin/env bash
# rig-check-pre-existing.sh — record on a bead that one recorded fail of a
# check is pre-existing: the same failure is red on the base branch, and a
# tracker carries it.
#   rig-check-pre-existing.sh --bead <id> --check test|lint|typecheck
#                             --commit <sha> --trackers "<id> [<id>...]"
#                             [--worktree <dir>]
# Callers: the self-review of formulas/mol-polecat-work.toml, on the work bead
# at the commit it reviews, and the refinery's handle-failures step
# (formulas/mol-refinery-patrol.toml), on the anchor at the merged head.
#
# `gctk rig` records each check's result against a commit, and a fail stays a
# fail: a record says what the command did at that commit, never whose failure
# it is. Judging that is the caller's. A caller that finds a red check failing
# the same way on the base, with a tracker for it (preexisting-failure.sh),
# writes its judgment here, as rig_check_pre_existing.<check> =
# {"commit":"<sha>","record":{...},"trackers":["<id>",...]}. The record is the
# fail `gctk rig <check> --check` reads at the worktree's HEAD (default the
# current directory), which must be <sha>. A later run at that commit with
# another command or scope replaces the record, and its fail is not the one
# judged, so each reader honors the judgment only while --check still reads
# that record: self-review-check.sh lets the loop converge past it on the work
# bead at HEAD, and the correctness review runs no suite for it on the anchor
# at the reviewed commit.
#
# A second write for the same record adds its trackers to the ones already
# there, because a gate files one tracker per failing test or linted file. A
# write for another record, at that commit or another, replaces the value, so
# a judgment never carries over to a run it did not see.
#
# Exit: 0 written and read back · 1 no recorded fail of <sha> to mark, the bead
# did not read, or the write did not read back as written · 2 usage
set -uo pipefail

PROG="rig-check-pre-existing"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$HERE/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 1; }

usage() {
  [ -z "${1:-}" ] || echo "$PROG: $1" >&2
  echo "usage: $PROG --bead <id> --check test|lint|typecheck --commit <sha> --trackers \"<id> [<id>...]\" [--worktree <dir>]" >&2
  exit 2
}

BEAD=""; CHECK=""; COMMIT=""; TRACKERS=""; WORKTREE="."
while [ "$#" -gt 0 ]; do
  case "$1" in
    --bead|--check|--commit|--trackers|--worktree)
      [ "$#" -ge 2 ] || usage "$1 needs a value"
      case "$1" in
        --bead) BEAD="$2" ;;
        --check) CHECK="$2" ;;
        --commit) COMMIT="$2" ;;
        --trackers) TRACKERS="$2" ;;
        --worktree) WORKTREE="$2" ;;
      esac
      shift 2 ;;
    *) usage "unknown argument '$1'" ;;
  esac
done
[ -n "$BEAD" ] || usage "--bead is required"
case "$CHECK" in
  test|lint|typecheck) ;;
  *) usage "--check must be test, lint or typecheck, not '$CHECK'" ;;
esac
# The full object name: an abbreviation is no commit a reader can compare.
case "$COMMIT" in
  "" | *[!0-9a-f]*) usage "--commit must be a full commit sha, not '$COMMIT'" ;;
esac
[ "${#COMMIT}" -eq 40 ] || [ "${#COMMIT}" -eq 64 ] || usage "--commit must be a full commit sha, not '$COMMIT'"
# Trackers are bead ids, separated by spaces or commas.
LIST=$(printf '%s' "$TRACKERS" | jq -Rsc '[splits("[[:space:],]+") | select(length > 0)]' 2>/dev/null) || LIST=""
case "$LIST" in "" | "[]") usage "--trackers must name at least one tracker bead" ;; esac
printf '%s' "$LIST" | jq -e 'all(.[]; test("^[A-Za-z0-9][A-Za-z0-9._-]*$"))' >/dev/null 2>&1 \
  || usage "--trackers must be bead ids, not '$TRACKERS'"
[ -d "$WORKTREE" ] || usage "--worktree must be a directory, not '$WORKTREE'"

# >>> gctk-bin
GCTK="${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"
# <<< gctk-bin
[ -x "$GCTK" ] || { echo "$PROG: no gctk binary at $GCTK to read the recorded fail, so nothing was written" >&2; exit 1; }
# rig's own line goes to stderr, where it says what is recorded, and the record
# it found is the one JSON line on stdout.
RECORD=$(cd "$WORKTREE" && "$GCTK" rig "$CHECK" --check)
RC=$?
RECORD=$(printf '%s' "$RECORD" | jq -c --arg c "$COMMIT" 'select(type == "object" and .result == "fail" and .commit == $c)' 2>/dev/null)
if [ "$RC" != 1 ] || [ -z "$RECORD" ]; then
  echo "$PROG: $WORKTREE holds no recorded $CHECK fail at $COMMIT (gctk rig $CHECK --check exit $RC), so there is nothing to mark and nothing was written" >&2
  exit 1
fi

ROW=$(bd_json show "$BEAD")
if ! printf '%s' "$ROW" | jq -e --arg id "$BEAD" 'type == "array" and length > 0 and (.[0].id // "") == $id' >/dev/null 2>&1; then
  echo "$PROG: could not read $BEAD, so nothing was written" >&2
  exit 1
fi
KEY="rig_check_pre_existing.$CHECK"
# bd keeps a JSON value as a string, so the earlier value is parsed before its
# trackers are kept.
VALUE=$(printf '%s' "$ROW" | jq -c --arg k "$KEY" --arg c "$COMMIT" --argjson r "$RECORD" --argjson t "$LIST" '
  ((.[0].metadata // {})[$k] // null | if type == "string" then (fromjson? // null) else . end) as $p
  | {commit: $c, record: $r,
     trackers: ((if ($p | type) == "object" and $p.commit == $c and $p.record == $r then ($p.trackers // []) else [] end) + $t | unique)}')
[ -n "$VALUE" ] || { echo "$PROG: could not compose the value for $KEY, so nothing was written" >&2; exit 1; }

gc bd update "$BEAD" --set-metadata "$KEY=$VALUE" </dev/null >/dev/null 2>&1 || true
GOT=$(bd_meta_readback "$BEAD" "$(jq -nc --arg k "$KEY" --arg v "$VALUE" '{($k): $v}')")
if [ "${GOT%%$'\t'*}" != landed ]; then
  echo "$PROG: $KEY on $BEAD did not read back as written ($GOT)" >&2
  exit 1
fi
RUN=$(printf '%s' "$RECORD" | jq -r '"the run of \(.command | @sh)" + (if .scope then " (scope \(.scope))" else "" end)')
echo "$PROG: $BEAD records $CHECK's fail at $COMMIT as pre-existing, for $RUN: $(printf '%s' "$VALUE" | jq -r '.trackers | join(", ")')"
