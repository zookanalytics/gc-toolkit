#!/usr/bin/env bash
# Hermetic test for assets/scripts/hand-back.sh, the one write that gives a bead
# back from this session's claim.
#
# What it holds:
#   - a bead this session holds in_progress, under any of its identities, or one
#     open with no assignee or this session's, is reopened, unassigned and
#     stripped of both session pins in ONE write, guarded on the status and
#     assignee it showed, and the caller's further flags ride that same write;
#   - a bead that shows anything else gets nothing but a note: open or
#     in_progress under someone else, in_progress with no assignee, closed or
#     parked, unreadable, or held by an identity the environment does not name;
#   - a write the store refuses, and one made stale by a claim that lands after
#     the read, leave the claim whole, pins and route included, with a note
#     naming what the bead shows after it;
#   - a call with no bead exits 2 and writes nothing.
#
# The harness's gc stub keeps the beads in a JSON store. A wrapper in front of
# it enforces bd's --if-status and --if-assignee the way bd does, where a
# mismatch writes nothing and exits 13. WRAP_REFUSE makes it refuse every
# guarded write, the way a failing store looks to the script, and
# WRAP_RACE="<status>|<assignee>" moves the bead there between the script's
# read and its write.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-hand-back-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/hand-back.sh"
SUT="$SD/hand-back.sh"

mkdir -p "$TMP/guard"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/guard/gc" <<WRAP
if [ "\${1:-} \${2:-}" = "bd update" ]; then
  id="\${3:-}"; has_s=0; want_s=""; has_a=0; want_a=""
  for a in "\$@"; do
    case "\$a" in
      --if-status=*)   has_s=1; want_s="\${a#--if-status=}" ;;
      --if-assignee=*) has_a=1; want_a="\${a#--if-assignee=}" ;;
    esac
  done
  if [ "\$has_s" = 1 ] || [ "\$has_a" = 1 ]; then
    if [ -n "\${WRAP_RACE:-}" ]; then
      "$BIN/gc" bd update "\$id" --status="\${WRAP_RACE%%|*}" --assignee="\${WRAP_RACE#*|}" >/dev/null
    fi
    [ -z "\${WRAP_REFUSE:-}" ] || { printf 'Error updating %s: the store refused the write\n' "\$id" >&2; exit 1; }
    row=\$("$BIN/gc" bd show "\$id" --json)
    cur_s=\$(printf '%s' "\$row" | jq -r '.[0].status // ""')
    cur_a=\$(printf '%s' "\$row" | jq -r '.[0].assignee // ""')
    if { [ "\$has_s" = 1 ] && [ "\$want_s" != "\$cur_s" ]; } || { [ "\$has_a" = 1 ] && [ "\$want_a" != "\$cur_a" ]; }; then
      printf 'Error updating %s: precondition failed: it shows status "%s" and assignee "%s"\n' "\$id" "\$cur_s" "\$cur_a" >&2
      exit 13
    fi
  fi
fi
exec "$BIN/gc" "\$@"
WRAP
chmod +x "$TMP/guard/gc"

# bead <id> <status> <assignee> [<extra metadata JSON object>] — a work bead a
# hook claim stamped with the session pins, routed to the polecat pool. An empty
# assignee is written as bd prints one, null.
bead() {
  local extra="${4:-}"
  [ -n "$extra" ] || extra='{}'
  jq -nc --arg id "$1" --arg st "$2" --arg as "$3" --argjson extra "$extra" '
    {id: $id, status: $st, assignee: (if $as == "" then null else $as end),
     notes: "", title: "work",
     metadata: ({"gc.session_id": "lx-me", "gc.session_name": "gc-toolkit__polecat-lx-me",
                 "gc.routed_to": "gc-toolkit/gc-toolkit.polecat", "branch": "polecat/x"} + $extra)}'
}
POOL="gc-toolkit/gc-toolkit.polecat"
# hb [VAR=val ...] -- <args...> — the script, with this session's identity and the
# wrapper's knobs set by the assignments and every identity variable the
# assignments leave out unset. Sets RC, OUT and ERR; the gc log holds this run's
# calls alone.
RC=0; OUT=""; ERR=""
hb() {
  local envs=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  [ $# -gt 0 ] && shift
  : > "$STUB_GC_LOG"
  RC=0
  env -u GC_ALIAS -u GC_SESSION_ID -u GC_SESSION_NAME -u GC_AGENT PATH="$TMP/guard:$PATH" \
    ${envs[@]+"${envs[@]}"} bash "$SUT" ${@+"$@"} > "$TMP/out" 2> "$TMP/err" || RC=$?
  OUT=$(cat "$TMP/out"); ERR=$(cat "$TMP/err")
}
# writes <id> — the updates this run sent for <id>, the wrapper's own race write
# included, one per line.
writes() { grep -F "bd update $1 " "$STUB_GC_LOG" || true; }
claim() { printf '%s|%s|%s|%s|%s' "$(bstatus "$1")" "$(bassignee "$1")" "$(meta "$1" gc.session_id)" "$(meta "$1" gc.session_name)" "$(meta "$1" gc.routed_to)"; }
HELD_CLAIM="in_progress|lx-me|lx-me|gc-toolkit__polecat-lx-me|$POOL"

echo "# a claim this session holds is handed back in one guarded write"
store "[$(bead B1 in_progress lx-me)]"
hb GC_SESSION_ID=lx-me -- B1
eq "$RC" "0" "a bead held in_progress under \$GC_SESSION_ID: exit 0"
eq "$(bstatus B1)|$(bassignee B1)" "open|" "…reopened and unassigned"
eq "$(meta B1 gc.session_id)|$(meta B1 gc.session_name)" "<absent>|<absent>" "…both session pins removed"
eq "$(meta B1 gc.routed_to)" "$POOL" "…its route left as it was, so its pool can offer it again"
eq "$(writes B1 | wc -l | tr -d ' ')" "1" "…all of it in one write"
eq "$(writes B1)" "bd update B1 --if-status=in_progress --if-assignee=lx-me --status=open --assignee= --unset-metadata gc.session_id --unset-metadata gc.session_name" \
   "…guarded on the status and the holder it showed"
has "$OUT" "B1 is open and unassigned" "…and it says so"

for form in GC_ALIAS GC_SESSION_NAME GC_AGENT; do
  store "[$(bead B2 in_progress gc-toolkit/gc-toolkit.tk-x)]"
  hb "$form=gc-toolkit/gc-toolkit.tk-x" GC_SESSION_ID=lx-me -- B2
  eq "$RC|$(bstatus B2)|$(bassignee B2)" "0|open|" "a bead held under \$$form is this session's, and is handed back"
done

store "[$(bead B3 in_progress lx-me)]"
hb GC_SESSION_ID=lx-me -- B3 --set-metadata gc.routed_to=human --set-metadata "gc.takeaway=Needs a decision"
eq "$RC|$(meta B3 gc.routed_to)|$(meta B3 gc.takeaway)" "0|human|Needs a decision" "further flags land with the hand-back"
eq "$(writes B3 | wc -l | tr -d ' ')" "1" "…in the same write as the reopen"

store "[$(bead B4 open "")]"
hb GC_SESSION_ID=lx-me -- B4
eq "$RC|$(bstatus B4)|$(bassignee B4)" "0|open|" "an open bead with no assignee takes the write"
has "$(writes B4)" "--if-status=open --if-assignee= --status=open" "…guarded on the open status and the empty assignee it showed"
eq "$(meta B4 gc.session_id)|$(meta B4 gc.session_name)" "<absent>|<absent>" "…and loses the pins a released bead must not carry"

store "[$(bead B5 open lx-me)]"
hb GC_SESSION_ID=lx-me -- B5
eq "$RC|$(bstatus B5)|$(bassignee B5)" "0|open|" "an open bead assigned to this session is handed back"

echo "# a bead that is not this session's claim gets nothing but a note"
store "[$(bead B6 open gc-toolkit/gc-toolkit.refinery)]"
hb GC_SESSION_ID=lx-me -- B6 --set-metadata gc.routed_to=""
eq "$RC" "1" "an open bead assigned to someone else: exit 1"
eq "$(claim B6)" "open|gc-toolkit/gc-toolkit.refinery|lx-me|gc-toolkit__polecat-lx-me|$POOL" "…its assignee, pins and route untouched"
eq "$(writes B6 | grep -c -- '--if-status' || true)" "0" "…no release is attempted"
has "$(notes B6)" "Hand-back refused: B6 shows status open and assignee gc-toolkit/gc-toolkit.refinery, which is not a claim this session can hand back, so nothing was released." \
    "…and the note says what it showed"
has "$ERR" "not a claim this session can hand back" "…as does stderr"

store "[$(bead B7 in_progress lx-other '{"gc.session_id":"lx-other","gc.session_name":"gc-toolkit__polecat-lx-other"}')]"
hb GC_SESSION_ID=lx-me -- B7
eq "$RC" "1" "a bead another session holds in_progress: exit 1"
eq "$(claim B7)" "in_progress|lx-other|lx-other|gc-toolkit__polecat-lx-other|$POOL" "…its claim left whole"
eq "$(writes B7 | grep -c -- '--if-status' || true)" "0" "…no release is attempted"

store "[$(bead B8 in_progress "")]"
hb GC_SESSION_ID=lx-me -- B8
eq "$RC|$(bstatus B8)|$(writes B8 | grep -c -- '--if-status' || true)" "1|in_progress|0" "a bead in_progress with no assignee is no claim of this session's, and is not written"
has "$(notes B8)" "B8 shows status in_progress and assignee none" "…and the note says what it showed"

for st in closed blocked deferred hooked; do
  store "[$(bead B9 "$st" lx-me)]"
  hb GC_SESSION_ID=lx-me -- B9
  eq "$RC|$(bstatus B9)|$(bassignee B9)|$(writes B9 | grep -c -- '--if-status' || true)" "1|$st|lx-me|0" "a bead that shows $st is not reopened, though this session's id is its assignee"
done
has "$(notes B9)" "B9 shows status hooked and assignee lx-me" "…and the note says what it showed"

store "[$(bead B10 in_progress lx-me)]"
hb -- B10
eq "$RC|$(claim B10)" "1|$HELD_CLAIM" "an environment that names no identity matches no holder, so nothing is released"

store "[]"
hb GC_SESSION_ID=lx-me -- B11
eq "$RC|$(grep -c -- '--if-status' "$STUB_GC_LOG" || true)" "1|0" "a bead that cannot be read: exit 1, and no release is attempted"
has "$ERR" "B11 could not be read, so nothing was released." "…and stderr says why"

echo "# a refused write leaves the claim whole and says what the bead shows"
store "[$(bead B12 in_progress lx-me)]"
hb GC_SESSION_ID=lx-me WRAP_REFUSE=1 -- B12 --set-metadata gc.routed_to=human --set-metadata "gc.takeaway=Needs a decision"
eq "$RC" "1" "a write the store refuses: exit 1"
eq "$(claim B12)" "$HELD_CLAIM" "…the claim stands: status, assignee, both pins and the route"
eq "$(meta B12 gc.takeaway)" "<absent>" "…and no further flag landed either"
has "$(notes B12)" "Hand-back refused: the write that reopens B12 and releases this session's claim exited 1 (the store refused it). It shows status in_progress and assignee lx-me." \
    "…and the note names the exit and what the bead shows"

store "[$(bead B13 open "")]"
hb GC_SESSION_ID=lx-me "WRAP_RACE=in_progress|lx-other" -- B13
eq "$RC" "1" "a claim that lands between the read and the write: exit 1"
eq "$(bstatus B13)|$(bassignee B13)" "in_progress|lx-other" "…and the new holder's claim stands"
has "$(notes B13)" "exited 13 (the bead changed after it was read). It shows status in_progress and assignee lx-other." \
    "…and the note says the bead changed, and what it shows now"

echo "# usage"
store "[$(bead B14 in_progress lx-me)]"
hb GC_SESSION_ID=lx-me --
eq "$RC|$(grep -c '^bd ' "$STUB_GC_LOG" || true)" "2|0" "no bead: exit 2, and nothing read or written"
hb GC_SESSION_ID=lx-me -- --status=open
eq "$RC|$(grep -c '^bd ' "$STUB_GC_LOG" || true)" "2|0" "a flag where the bead goes: exit 2, and nothing read or written"
hb GC_SESSION_ID=lx-me -- --help
eq "$RC" "0" "--help exits 0"
eq "$(claim B14)" "$HELD_CLAIM" "…and none of them touched the bead"

echo
echo "hand-back.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
