#!/usr/bin/env bash
# Hermetic test for how mol-design-convoy gives its subject a close.
#
# The subject's work moves into the owned convoy the run creates, and work
# queued behind the subject waits for that work to land. seed-convoy-until
# writes an `until` edge from the subject onto the convoy, so the
# deferred-dispatch reconcile pass closes the subject once the convoy closes.
# That pass leaves alone a bead carrying live work (live-work.sh), and the sling
# leaves two marks of a pour on the subject: the gc.execution_routed_to stamp
# and the input convoy's `tracks` edge. drain-hand-off, the run's last step,
# releases both and closes the input convoy, and refuses while the `until` edge
# does not read back, so a subject is never released with nothing to close it.
#
# As in the arm steps, the read-back decides whether an edge landed or went, not
# the add's or the remove's exit status. A resume re-runs every write over what
# the failed pass may already have done, so the resume cases give a write a
# non-zero exit over a store that reads back as wanted and check that the step
# completes. Each failure case breaks one read or write and checks that nothing
# after it ran.
#
# The keys the run records on the subject must not read as live work either, or
# the pass would leave the subject open for good, so the static pins put every
# key the formula writes on the subject through live-work.sh itself.
#
# EXECUTES the real snippets extracted verbatim between the formula markers, so
# the test cannot drift from the shipped instruction. No live city or network.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-design-convoy.toml"
LIVE_WORK="$HERE/live-work.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-design-convoy-subject-close-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

[ -f "$TOML" ] || { echo "formula not found: $TOML" >&2; exit 1; }
[ -f "$LIVE_WORK" ] || { echo "live-work.sh not found: $LIVE_WORK" >&2; exit 1; }

# extract <marker>: the lines between the marker pair (exclusive).
extract() {
  awk -v m="$1" '
    $0 ~ ("# >>> " m "$") {f=1; next}
    $0 ~ ("# <<< " m "$") {f=0}
    f' "$TOML"
}
copies() { grep -c -- "# >>> $1\$" "$TOML" || true; }

# --- static pins ---------------------------------------------------------------

for m in seed-convoy-until drain-hand-off; do
  eq "$(copies "$m")" "1" "$m has one copy"
  BLOCK="$(extract "$m")"
  [ -n "$BLOCK" ] && ok "$m extracted between markers" \
    || bad "$m extraction EMPTY — markers missing from $TOML"
  # A TOML triple-quoted string eats a trailing backslash (line-ending escape)
  # and silently joins lines, so a shipped snippet must be backslash-free.
  case "$BLOCK" in
    *\\*) bad "$m contains a backslash — TOML escapes will mangle it" ;;
    *)    ok  "$m is backslash-free" ;;
  esac
done

# The input convoy reaches the hand-off once, as the formula engine renders it,
# so the test below substitutes one placeholder.
eq "$(extract drain-hand-off | grep -c '{{convoy_id}}')" "1" "drain-hand-off names {{convoy_id}} once"

# shellcheck source=live-work.sh
. "$LIVE_WORK"
[ -n "${LIVE_WORK_JQ:-}" ] || { echo "live-work.sh defined no LIVE_WORK_JQ" >&2; exit 1; }

# Every key the formula writes on the subject, each set non-blank on a row of
# plain open work, as the subject stands once the run has handed it off.
KEYS="$(grep -o -- '--set-metadata "gc\.[a-z_]*=' "$TOML" | sed 's/^--set-metadata "//; s/=$//' | sort -u)"
grep -qx 'gc.design_convoy_id' <<<"$KEYS" \
  && ok "the keys the formula writes on the subject are found" \
  || bad "no key the formula writes on the subject was found, so the check below would pass on nothing"
ROW="$(printf '%s\n' "$KEYS" | jq -R . | jq -sc '{id: "sub-1", status: "open", assignee: "", issue_type: "task", metadata: (map({key: ., value: "x"}) | from_entries)}')"
eq "$(printf '%s' "$ROW" | jq -r "$LIVE_WORK_JQ"' live_work_reasons | join("; ")')" "" \
  "no key the run records on the subject is live work"
eq "$(printf '%s' "$ROW" | jq -r "$LIVE_WORK_JQ"' live_work_edge_reasons([]) | join("; ")')" "" \
  "a handed-off subject, which nothing tracks, carries no live edge"
# The two marks the hand-off releases are live work, which is why it releases
# them: the stamp on the row, and the input convoy's tracks edge among the
# subject's dependents.
STAMPED="$(printf '%s' "$ROW" | jq -c '.metadata["gc.execution_routed_to"] = "rig/gc-toolkit.polecat"')"
eq "$(printf '%s' "$STAMPED" | jq -r "$LIVE_WORK_JQ"' live_work_reasons | join("; ")')" \
  "gc.execution_routed_to=rig/gc-toolkit.polecat" "the pour's stamp is live work"
eq "$(printf '%s' "$ROW" | jq -r "$LIVE_WORK_JQ"' live_work_edge_reasons([{id: "ic-1", dependency_type: "tracks", issue_type: "convoy", status: "closed"}]) | join("; ")')" \
  "tracked by convoy ic-1 (closed)" "the input convoy's tracks edge is live work, whatever the convoy's status"
grep -q -- '--unset-metadata gc.execution_routed_to' <<<"$(extract drain-hand-off)" \
  && ok "drain-hand-off clears the pour's stamp" || bad "drain-hand-off does not clear the pour's stamp"

SHELLS=(bash)
if command -v zsh >/dev/null 2>&1; then
  SHELLS+=(zsh)
else
  echo "note - zsh not present; executing under bash only"
fi

# --- the gc stub -----------------------------------------------------------------
# Logs every call, one line each, and answers by env:
#   DEP_ADD_RC, DEP_REMOVE_RC, UPDATE_RC, CLOSE_RC, STATUS_RC   exit of that call
#   LIST_UNTIL    JSON `gc bd dep list <subject> --direction=down -t until` prints
#   LIST_TRACKS   JSON `gc bd dep list <subject> --direction=up -t tracks` prints
#   SHOW_SUBJECT  JSON `gc bd show sub-1` prints
#   SHOW_INPUT    JSON `gc bd show ic-1` prints
#   MEMBERS       JSON `gc convoy status ic-1 --json` prints
# The writes and the reads answer independently, so a non-zero write over a
# store that reads back as wanted is bd refusing a repeat, and a zero write over
# a store that does not is a write that reported success and changed nothing.
mkdir -p "$TMP/bin"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'STUB'
printf '%s\n' "$*" >> "$GC_LOG"
case "${1:-} ${2:-} ${3:-}" in
  "bd dep add")    exit "${DEP_ADD_RC:-0}" ;;
  "bd dep remove") exit "${DEP_REMOVE_RC:-0}" ;;
  "bd dep list")
    case " $* " in
      *" -t until "*)  printf '%s\n' "${LIST_UNTIL:-[]}" ;;
      *" -t tracks "*) printf '%s\n' "${LIST_TRACKS:-[]}" ;;
      *)               printf '[]\n' ;;
    esac
    exit 0 ;;
esac
case "${1:-} ${2:-}" in
  "bd update")    exit "${UPDATE_RC:-0}" ;;
  "bd show")
    case "${3:-}" in
      sub-1) printf '%s\n' "${SHOW_SUBJECT:-[]}" ;;
      ic-1)  printf '%s\n' "${SHOW_INPUT:-[]}" ;;
      *)     printf '{"error":"no issue found"}\n' ;;
    esac
    exit 0 ;;
  "convoy status") [ "${STATUS_RC:-0}" = 0 ] || exit "$STATUS_RC"; printf '%s\n' "${MEMBERS:-}"; exit 0 ;;
  "convoy close")  exit "${CLOSE_RC:-0}" ;;
esac
exit 0
STUB
chmod +x "$TMP/bin/gc"

# run_block <marker> <shell>: runs the block with the step's variables in the
# environment, {{convoy_id}} rendered as ic-1, and the stub first on PATH. Sets
# RC; the call log is $GC_LOG. A sentinel after the block records whether
# execution ran past it: the step's contract is that a failed read or write
# stops it, not merely that the block's last command happened to fail.
run_block() {
  local m="$1" sh="$2" block
  block="$(extract "$m")"
  { printf '%s\n' "${block//\{\{convoy_id\}\}/ic-1}"; printf 'printf "past\\n" > "%s"\n' "$TMP/past.flag"; } > "$TMP/block.sh"
  : > "$TMP/gc.log"; rm -f "$TMP/past.flag"
  RC=0
  PATH="$TMP/bin:$PATH" GC_LOG="$TMP/gc.log" SUBJECT="sub-1" CONVOY_ID="cv-1" \
    "$sh" "$TMP/block.sh" >/dev/null 2>"$TMP/block.err" || RC=$?
}
logged()     { grep -qxF -- "$1" "$TMP/gc.log"; }
not_logged() { ! grep -qF -- "$1" "$TMP/gc.log"; }
stopped()    { [ "$RC" -ne 0 ] && [ ! -e "$TMP/past.flag" ]; }
line_of()    { grep -nxF -- "$1" "$TMP/gc.log" | head -1 | cut -d: -f1; }

UNTIL_OK='[{"id":"cv-1","dependency_type":"until","status":"open"}]'
UNTIL_OTHER='[{"id":"cv-9","dependency_type":"until","status":"open"}]'
SUBJECT_OK='[{"id":"sub-1","status":"open","metadata":{"gc.design_convoy_id":"cv-1","gc.execution_routed_to":"rig/gc-toolkit.polecat"}}]'
SUBJECT_UNSEEDED='[{"id":"sub-1","status":"open","metadata":{"gc.execution_routed_to":"rig/gc-toolkit.polecat"}}]'
ONE_MEMBER='{"children":[{"id":"sub-1","status":"open"}]}'
NO_MEMBER='{"children":[]}'
TWO_MEMBERS='{"children":[{"id":"sub-1","status":"open"},{"id":"sub-2","status":"open"}]}'
INPUT_OPEN='[{"id":"ic-1","status":"open","issue_type":"convoy"}]'
INPUT_CLOSED='[{"id":"ic-1","status":"closed","issue_type":"convoy"}]'
TRACKED_BY_INPUT='[{"id":"ic-1","dependency_type":"tracks","issue_type":"convoy","status":"open"}]'
TRACKED_BY_OTHER='[{"id":"ic-0","dependency_type":"tracks","issue_type":"convoy","status":"open"}]'

STAMP_CLEAR="bd update sub-1 --unset-metadata gc.execution_routed_to"
EDGE_REMOVE="bd dep remove ic-1 sub-1"
INPUT_CLOSE="convoy close ic-1"

for sh in "${SHELLS[@]}"; do
  # --- seed-convoy-until ---
  export DEP_ADD_RC=0 LIST_UNTIL="$UNTIL_OK"
  run_block seed-convoy-until "$sh"
  eq "$RC" "0" "[$sh] until: an edge that reads back passes the step"
  logged "bd dep add sub-1 cv-1 --type=until" \
    && ok "[$sh] until: the subject waits on the convoy (operand order)" \
    || bad "[$sh] until: no until edge from the subject onto the convoy"
  [ -e "$TMP/past.flag" ] && ok "[$sh] until: the step runs on past the edge" \
    || bad "[$sh] until: the step stopped on a verified edge"

  export DEP_ADD_RC=0 LIST_UNTIL='[]'
  run_block seed-convoy-until "$sh"
  stopped && ok "[$sh] until: an add that exits 0 but does not read back stops the step" \
    || bad "[$sh] until: an unread edge was trusted (rc=$RC)"
  grep -q 'nothing would close it' "$TMP/block.err" \
    && ok "[$sh] until: the stop says what is at stake" \
    || bad "[$sh] until: the stop does not say what is at stake"

  export LIST_UNTIL="$UNTIL_OTHER"
  run_block seed-convoy-until "$sh"
  stopped && ok "[$sh] until: an edge onto another convoy does not count" \
    || bad "[$sh] until: an edge onto another convoy was accepted (rc=$RC)"

  # resume: the edge is present from the failed first pass, bd refuses the duplicate
  export DEP_ADD_RC=1 LIST_UNTIL="$UNTIL_OK"
  run_block seed-convoy-until "$sh"
  eq "$RC" "0" "[$sh] until resume: an existing edge that reads back passes the step"
  grep -q 'reading the edge back' "$TMP/block.err" \
    && ok "[$sh] until resume: the refused add is reported" \
    || bad "[$sh] until resume: the refused add passed silently"

  # --- drain-hand-off ---
  export MEMBERS="$ONE_MEMBER" STATUS_RC=0 SHOW_SUBJECT="$SUBJECT_OK" LIST_UNTIL="$UNTIL_OK" \
    UPDATE_RC=0 DEP_REMOVE_RC=0 LIST_TRACKS='[]' SHOW_INPUT="$INPUT_OPEN" CLOSE_RC=0
  run_block drain-hand-off "$sh"
  eq "$RC" "0" "[$sh] hand-off: a subject with a verified until edge is handed off"
  logged "$STAMP_CLEAR" && ok "[$sh] hand-off: the pour's stamp is cleared" \
    || bad "[$sh] hand-off: the stamp is not cleared"
  logged "$EDGE_REMOVE" && ok "[$sh] hand-off: the input convoy's tracks edge is removed (operand order)" \
    || bad "[$sh] hand-off: the tracks edge is not removed, or removed the wrong way round"
  logged "$INPUT_CLOSE" && ok "[$sh] hand-off: the input convoy is closed" \
    || bad "[$sh] hand-off: the input convoy is left open"
  [ "$(line_of "$STAMP_CLEAR")" -lt "$(line_of "$EDGE_REMOVE")" ] && [ "$(line_of "$EDGE_REMOVE")" -lt "$(line_of "$INPUT_CLOSE")" ] \
    && ok "[$sh] hand-off: the stamp goes first, then the edge, then the convoy" \
    || bad "[$sh] hand-off: the writes ran out of order"
  not_logged "bd close" && not_logged "convoy close cv-1" \
    && ok "[$sh] hand-off: neither the subject nor the owned convoy is closed" \
    || bad "[$sh] hand-off: closed the subject or the owned convoy"

  # The precondition: no release without a close to hand the subject to.
  for c in "no until edge:LIST_UNTIL=[]" "an until edge onto another convoy:LIST_UNTIL=$UNTIL_OTHER" \
           "no recorded convoy:SHOW_SUBJECT=$SUBJECT_UNSEEDED"; do
    what="${c%%:*}"; set_env="${c#*:}"
    export MEMBERS="$ONE_MEMBER" SHOW_SUBJECT="$SUBJECT_OK" LIST_UNTIL="$UNTIL_OK"
    export "${set_env?}"
    run_block drain-hand-off "$sh"
    stopped && not_logged "bd update" && not_logged "bd dep remove" && not_logged "convoy close" \
      && ok "[$sh] hand-off: $what stops it before any write" \
      || bad "[$sh] hand-off: $what still released the subject (rc=$RC)"
  done
  export SHOW_SUBJECT="$SUBJECT_OK" LIST_UNTIL="$UNTIL_OK"

  export UPDATE_RC=1
  run_block drain-hand-off "$sh"
  stopped && not_logged "bd dep remove" && not_logged "convoy close" \
    && ok "[$sh] hand-off: a stamp that will not clear stops it before the edge goes" \
    || bad "[$sh] hand-off: went on past a failed stamp clear (rc=$RC)"
  export UPDATE_RC=0

  export DEP_REMOVE_RC=0 LIST_TRACKS="$TRACKED_BY_INPUT"
  run_block drain-hand-off "$sh"
  stopped && not_logged "convoy close" \
    && ok "[$sh] hand-off: a remove that exits 0 but still reads back stops before the convoy closes" \
    || bad "[$sh] hand-off: closed an input convoy that still tracks the subject (rc=$RC)"

  export LIST_TRACKS='{"error":"simulated"}'
  run_block drain-hand-off "$sh"
  stopped && not_logged "convoy close" \
    && ok "[$sh] hand-off: an unreadable tracks read stops before the convoy closes" \
    || bad "[$sh] hand-off: an unreadable tracks read was taken for a removed edge (rc=$RC)"

  # A convoy other than this run's own tracking the subject is not this run's to
  # release; its own edge is all the hand-off reads back.
  export LIST_TRACKS="$TRACKED_BY_OTHER"
  run_block drain-hand-off "$sh"
  eq "$RC" "0" "[$sh] hand-off: another convoy's edge does not stop this run's release"
  not_logged "bd dep remove ic-0" && ok "[$sh] hand-off: another convoy's edge is left alone" \
    || bad "[$sh] hand-off: removed another convoy's edge"

  # resume: the edge went in the failed first pass, bd refuses the repeat
  export DEP_REMOVE_RC=1 LIST_TRACKS='[]'
  run_block drain-hand-off "$sh"
  eq "$RC" "0" "[$sh] hand-off resume: an edge already gone completes the hand-off"
  logged "$INPUT_CLOSE" && ok "[$sh] hand-off resume: the input convoy is closed" \
    || bad "[$sh] hand-off resume: the input convoy is left open"
  grep -q 'reading the edge back' "$TMP/block.err" \
    && ok "[$sh] hand-off resume: the refused remove is reported" \
    || bad "[$sh] hand-off resume: the refused remove passed silently"
  export DEP_REMOVE_RC=0

  # A re-run after the edge went finds the input convoy tracking nothing, so the
  # subject cannot be found again, and only the convoy is left to close.
  export MEMBERS="$NO_MEMBER" SHOW_INPUT="$INPUT_OPEN"
  run_block drain-hand-off "$sh"
  eq "$RC" "0" "[$sh] hand-off re-run: an input convoy that tracks nothing is closed"
  logged "$INPUT_CLOSE" && not_logged "bd update" && not_logged "bd dep remove" \
    && ok "[$sh] hand-off re-run: only the convoy close runs" \
    || bad "[$sh] hand-off re-run: wrote more than the convoy close"

  export SHOW_INPUT="$INPUT_CLOSED"
  run_block drain-hand-off "$sh"
  eq "$RC" "0" "[$sh] hand-off re-run: a finished hand-off passes again"
  not_logged "bd update" && not_logged "bd dep remove" && not_logged "convoy close" \
    && ok "[$sh] hand-off re-run: a finished hand-off writes nothing" \
    || bad "[$sh] hand-off re-run: a finished hand-off still wrote"

  export SHOW_INPUT="$INPUT_OPEN" CLOSE_RC=1
  run_block drain-hand-off "$sh"
  stopped && ok "[$sh] hand-off: an input convoy that will not close fails the step" \
    || bad "[$sh] hand-off: a failed convoy close passed (rc=$RC)"
  export CLOSE_RC=0

  export MEMBERS="$TWO_MEMBERS"
  run_block drain-hand-off "$sh"
  stopped && not_logged "bd update" && not_logged "bd dep remove" && not_logged "convoy close" \
    && ok "[$sh] hand-off: an input convoy with two members stops it before any write" \
    || bad "[$sh] hand-off: handed off from a convoy with two members (rc=$RC)"

  export MEMBERS="$ONE_MEMBER" STATUS_RC=1
  run_block drain-hand-off "$sh"
  stopped && not_logged "bd update" && not_logged "bd dep remove" && not_logged "convoy close" \
    && ok "[$sh] hand-off: an unreadable input convoy stops it before any write" \
    || bad "[$sh] hand-off: handed off on an unreadable input convoy (rc=$RC)"
  export STATUS_RC=0
done

echo
echo "mol-design-convoy-subject-close: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
