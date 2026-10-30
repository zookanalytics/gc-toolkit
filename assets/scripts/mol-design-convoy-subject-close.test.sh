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
# An earlier pour's input convoy, left tracking the subject by a sling that
# failed or a run that was cancelled, is released too, before this run's own
# edge, unless an open workflow root still names it.
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
#                 when a run starts. `gc bd dep remove <convoy> sub-1` drops that
#                 convoy's rows from it, unless DEP_REMOVE_HOLDS is set, and with
#                 TRACKS_BREAK_ON_REMOVE set every read after a remove fails
#   LIST_ROOTS    JSON `gc bd list --metadata-field gc.input_convoy_id=<id>` prints
#   SHOW_SUBJECT  JSON `gc bd show sub-1` prints
#   SHOW_INPUT    JSON `gc bd show ic-1` prints
#   MEMBERS       JSON `gc convoy status ic-1 --json` prints
#   EARLIER_STATUS JSON `gc convoy status <any other convoy> --json` prints
# The writes and the reads answer independently, so a non-zero write over a
# store that reads back as wanted is bd refusing a repeat, and a zero write over
# a store that does not is a write that reported success and changed nothing.
mkdir -p "$TMP/bin"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'STUB'
printf '%s\n' "$*" >> "$GC_LOG"
case "${1:-} ${2:-} ${3:-}" in
  "bd dep add")    exit "${DEP_ADD_RC:-0}" ;;
  "bd dep remove")
    if [ -n "${TRACKS_BREAK_ON_REMOVE:-}" ]; then
      printf '{"error":"simulated"}\n' > "$TRACKS_FILE"
    elif [ -z "${DEP_REMOVE_HOLDS:-}" ] && jq -e 'type == "array"' "$TRACKS_FILE" >/dev/null 2>&1; then
      jq -c --arg c "${4:-}" 'map(select(.id != $c))' "$TRACKS_FILE" > "$TRACKS_FILE.new" && mv "$TRACKS_FILE.new" "$TRACKS_FILE"
    fi
    exit "${DEP_REMOVE_RC:-0}" ;;
  "bd dep list")
    case " $* " in
      *" -t until "*)  printf '%s\n' "${LIST_UNTIL:-[]}" ;;
      *" -t tracks "*) cat "$TRACKS_FILE" ;;
      *)               printf '[]\n' ;;
    esac
    exit 0 ;;
esac
case "${1:-} ${2:-}" in
  "bd update")    exit "${UPDATE_RC:-0}" ;;
  "bd list")      printf '%s\n' "${LIST_ROOTS:-[]}"; exit 0 ;;
  "bd show")
    case "${3:-}" in
      sub-1) printf '%s\n' "${SHOW_SUBJECT:-[]}" ;;
      ic-1)  printf '%s\n' "${SHOW_INPUT:-[]}" ;;
      *)     printf '{"error":"no issue found"}\n' ;;
    esac
    exit 0 ;;
  "convoy status")
    [ "${STATUS_RC:-0}" = 0 ] || exit "$STATUS_RC"
    if [ "${3:-}" = ic-1 ]; then printf '%s\n' "${MEMBERS:-}"; else printf '%s\n' "${EARLIER_STATUS:-}"; fi
    exit 0 ;;
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
  printf '%s\n' "${LIST_TRACKS:-[]}" > "$TMP/tracks.json"
  RC=0
  PATH="$TMP/bin:$PATH" GC_LOG="$TMP/gc.log" TRACKS_FILE="$TMP/tracks.json" SUBJECT="sub-1" CONVOY_ID="cv-1" \
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
# Earlier pours' input convoys, as Gas City leaves them on the subject: a sling
# that failed closes its convoy and leaves the edge, and a cancelled run leaves
# both. ic-1, this run's own, tracks the subject beside them.
OWN_ROW='{"id":"ic-1","dependency_type":"tracks","issue_type":"convoy","status":"open","metadata":{"gc.synthetic":"true"}}'
FAILED_SLING='[{"id":"ic-0","dependency_type":"tracks","issue_type":"convoy","status":"closed","metadata":{"gc.synthetic":"true"}},'"$OWN_ROW"']'
CANCELLED_RUN='[{"id":"ic-0","dependency_type":"tracks","issue_type":"convoy","status":"open","metadata":{"gc.synthetic":"true"}},'"$OWN_ROW"']'
TRACKED_BY_VISIT='[{"id":"v-1","dependency_type":"tracks","issue_type":"task","status":"open","metadata":{"task_kind":"visit"}},'"$OWN_ROW"']'
EARLIER_CLOSED='{"convoy":{"id":"ic-0","status":"closed"},"children":[{"id":"sub-1","status":"open"}]}'
EARLIER_OPEN='{"convoy":{"id":"ic-0","status":"open"},"children":[{"id":"sub-1","status":"open"}]}'
EARLIER_SHARED='{"convoy":{"id":"ic-0","status":"open"},"children":[{"id":"sub-1","status":"open"},{"id":"sub-2","status":"open"}]}'
ROOT_CLOSED='[{"id":"r-0","status":"closed"}]'
ROOT_OPEN='[{"id":"r-0","status":"in_progress"}]'

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
    UPDATE_RC=0 DEP_REMOVE_RC=0 LIST_TRACKS='[]' SHOW_INPUT="$INPUT_OPEN" CLOSE_RC=0 \
    LIST_ROOTS='[]' EARLIER_STATUS="$EARLIER_CLOSED"
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

  export DEP_REMOVE_RC=0 DEP_REMOVE_HOLDS=1 LIST_TRACKS="$TRACKED_BY_INPUT"
  run_block drain-hand-off "$sh"
  stopped && not_logged "convoy close" \
    && ok "[$sh] hand-off: a remove that exits 0 but still reads back stops before the convoy closes" \
    || bad "[$sh] hand-off: closed an input convoy that still tracks the subject (rc=$RC)"
  unset DEP_REMOVE_HOLDS

  export LIST_TRACKS='{"error":"simulated"}'
  run_block drain-hand-off "$sh"
  stopped && not_logged "bd dep remove" && not_logged "convoy close" \
    && ok "[$sh] hand-off: an unreadable tracks read stops it before any edge goes" \
    || bad "[$sh] hand-off: an unreadable tracks read was taken for no earlier convoy (rc=$RC)"

  export LIST_TRACKS='[]' TRACKS_BREAK_ON_REMOVE=1
  run_block drain-hand-off "$sh"
  stopped && not_logged "convoy close" \
    && ok "[$sh] hand-off: an unreadable read-back stops before the convoy closes" \
    || bad "[$sh] hand-off: an unreadable read-back was taken for a removed edge (rc=$RC)"
  unset TRACKS_BREAK_ON_REMOVE

  # A convoy tracking the subject that is no synthetic input convoy, a planned
  # batch say, is not this run's to release, and neither is a tracks edge from a
  # bead that is no convoy, such as a visit's.
  export LIST_TRACKS="$TRACKED_BY_OTHER"
  run_block drain-hand-off "$sh"
  eq "$RC" "0" "[$sh] hand-off: another convoy's edge does not stop this run's release"
  not_logged "bd dep remove ic-0" && not_logged "convoy status ic-0" \
    && ok "[$sh] hand-off: a convoy that is no input convoy is left alone" \
    || bad "[$sh] hand-off: released a convoy that is no input convoy"

  export LIST_TRACKS="$TRACKED_BY_VISIT"
  run_block drain-hand-off "$sh"
  eq "$RC" "0" "[$sh] hand-off: a visit's tracks edge does not stop this run's release"
  not_logged "bd dep remove v-1" && ok "[$sh] hand-off: a visit's tracks edge is left alone" \
    || bad "[$sh] hand-off: removed a visit's tracks edge"

  # Earlier pours' input convoys. Each one no open workflow root names is
  # released before this run's own edge goes, so a step that stops on one still
  # finds the subject when it re-runs. A failed sling's convoy is already closed
  # and only loses its edge. A cancelled run's convoy is still open, and it is
  # closed first while the subject is all it tracks.
  export LIST_TRACKS="$FAILED_SLING" LIST_ROOTS='[]' EARLIER_STATUS="$EARLIER_CLOSED"
  run_block drain-hand-off "$sh"
  eq "$RC" "0" "[$sh] earlier: a failed sling's input convoy does not stop the hand-off"
  logged "bd dep remove ic-0 sub-1" && ok "[$sh] earlier: a failed sling's edge is removed" \
    || bad "[$sh] earlier: a failed sling's edge is left on the subject"
  not_logged "convoy close ic-0" && ok "[$sh] earlier: a convoy already closed is not closed again" \
    || bad "[$sh] earlier: closed a convoy that was already closed"
  logged "$EDGE_REMOVE" && [ "$(line_of "bd dep remove ic-0 sub-1")" -lt "$(line_of "$EDGE_REMOVE")" ] \
    && ok "[$sh] earlier: an earlier edge goes before this run's own" \
    || bad "[$sh] earlier: this run's own edge went first, or not at all"
  logged "$INPUT_CLOSE" && ok "[$sh] earlier: this run's input convoy is closed" \
    || bad "[$sh] earlier: this run's input convoy is left open"

  export LIST_TRACKS="$CANCELLED_RUN" LIST_ROOTS="$ROOT_CLOSED" EARLIER_STATUS="$EARLIER_OPEN"
  run_block drain-hand-off "$sh"
  eq "$RC" "0" "[$sh] earlier: a cancelled run's input convoy does not stop the hand-off"
  logged "convoy close ic-0" && logged "bd dep remove ic-0 sub-1" \
    && [ "$(line_of "convoy close ic-0")" -lt "$(line_of "bd dep remove ic-0 sub-1")" ] \
    && ok "[$sh] earlier: a cancelled run's convoy is closed, then its edge removed" \
    || bad "[$sh] earlier: a cancelled run's convoy was not closed before its edge went"

  export EARLIER_STATUS="$EARLIER_SHARED"
  run_block drain-hand-off "$sh"
  eq "$RC" "0" "[$sh] earlier: a convoy that tracks another bead does not stop the hand-off"
  not_logged "convoy close ic-0" && logged "bd dep remove ic-0 sub-1" \
    && ok "[$sh] earlier: a convoy that tracks another bead loses the subject's edge and stays open" \
    || bad "[$sh] earlier: closed a convoy that tracks another bead, or kept the subject's edge"

  export EARLIER_STATUS="$EARLIER_OPEN" LIST_ROOTS="$ROOT_OPEN"
  run_block drain-hand-off "$sh"
  eq "$RC" "0" "[$sh] earlier: a convoy an open root names does not stop this run's release"
  not_logged "bd dep remove ic-0" && not_logged "convoy close ic-0" \
    && ok "[$sh] earlier: a convoy an open root names is left alone" \
    || bad "[$sh] earlier: released a convoy a live run may still use"
  logged "$EDGE_REMOVE" && ok "[$sh] earlier: this run's own edge still goes" \
    || bad "[$sh] earlier: this run's own edge was left"
  grep -q 'open workflow root' "$TMP/block.err" \
    && ok "[$sh] earlier: leaving it is reported" || bad "[$sh] earlier: the convoy was left silently"

  # A read or write about an earlier convoy that fails stops the step before
  # this run's own edge goes, so a re-run finds the subject and tries again.
  for c in 'an unreadable root read:LIST_ROOTS={"error":"simulated"}' 'an unreadable earlier convoy:EARLIER_STATUS=' \
           'a close that fails:CLOSE_RC=1' 'an edge that will not go:DEP_REMOVE_HOLDS=1'; do
    what="${c%%:*}"; set_env="${c#*:}"
    export LIST_TRACKS="$CANCELLED_RUN" LIST_ROOTS='[]' EARLIER_STATUS="$EARLIER_OPEN" CLOSE_RC=0
    export "${set_env?}"
    run_block drain-hand-off "$sh"
    stopped && not_logged "$EDGE_REMOVE" && not_logged "$INPUT_CLOSE" \
      && ok "[$sh] earlier: $what stops it before this run's own edge goes" \
      || bad "[$sh] earlier: $what still released this run's own edge (rc=$RC)"
  done
  unset DEP_REMOVE_HOLDS
  export LIST_TRACKS='[]' LIST_ROOTS='[]' EARLIER_STATUS="$EARLIER_CLOSED" CLOSE_RC=0

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
