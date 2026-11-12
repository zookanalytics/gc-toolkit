#!/usr/bin/env bash
# converse-entry.test.sh — a converse sitting's way in
# (assets/scripts/converse-entry.sh). Each case gives the hook's answer and the
# conversation's record, and pins the entry the script prints, the skill it
# names next and the values it hands on: a fresh conversation, a restart while
# the hold stands or before it, a stay woken early while its work is out, a
# stay that stopped short in each window its writes leave, with its work open
# and with it closed, the return of the work, no conversation at all, and each
# way the state can fail to read, which is never an answer to drain on.
#
# Hermetic: stubs gc and gctk, reads the repo only; no city, no network.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/../.."
SUT="$REPO/assets/scripts/converse-entry.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "${2:-}"; }
is()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "got '$2', want '$3'"; fi; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "no '$3' in: $2" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1" "'$3' found in: $2" ;; *) ok "$1" ;; esac; }

[ -r "$SUT" ] || { printf 'converse-entry: cannot read %s\n' "$SUT" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { printf 'converse-entry: jq is required\n' >&2; exit 1; }

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/gctk-converse-entry-test.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT
BIN="$TMPD/bin"; FIXDIR="$TMPD/fix"
mkdir -p "$BIN" "$FIXDIR"

# The gc stub answers the three reads the entry makes from fixtures, logs every
# call, and refuses anything else, so a write the entry should never make fails
# the case that reaches it.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/gc" <<'STUB'
printf '%s\n' "$*" >>"$FIXDIR/calls"
case "$*" in
  "hook --claim --json")
    [ -r "$FIXDIR/hook" ] && cat "$FIXDIR/hook"
    exit "$(cat "$FIXDIR/hook.rc" 2>/dev/null || echo 0)" ;;
  "bd list --id "*" --all --json")
    id=$4
    [ -r "$FIXDIR/row-$id.json" ] || { echo "Error: no issue found matching $id" >&2; exit 1; }
    [ ! -r "$FIXDIR/notice" ] || cat "$FIXDIR/notice"
    jq -c '[.]' "$FIXDIR/row-$id.json" ;;
  "bd list --assignee "*" --status open,in_progress --json")
    [ -r "$FIXDIR/assigned" ] || { echo "Error: list failed" >&2; exit 1; }
    cat "$FIXDIR/assigned" ;;
  *) echo "stub gc: refused: $*" >&2; exit 9 ;;
esac
STUB
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/gctk" <<'STUB'
printf 'gctk %s\n' "$*" >>"$FIXDIR/calls"
[ "${1:-} ${2:-}" = "bead holds" ] || { echo "stub gctk: refused: $*" >&2; exit 9; }
[ -r "$FIXDIR/holds-$3.json" ] || { echo "gctk: store did not answer" >&2; exit 1; }
cat "$FIXDIR/holds-$3.json"
STUB
chmod +x "$BIN/gc" "$BIN/gctk"

echo "── the script is shipped executable and syntactically valid ──"
[ -x "$SUT" ] && ok "converse-entry.sh is executable" || bad "converse-entry.sh is executable" "chmod +x it"
bash -n "$SUT" && ok "converse-entry.sh: valid bash" || bad "converse-entry.sh: valid bash" "bash -n failed"

ALIAS="gc-toolkit/gc-toolkit.tk-c"

fresh() { rm -f "$FIXDIR"/*; }
# hook work <reason> <bead> | hook drain | hook raw <text> [<rc>]
hook() {
  case "$1" in
    work)  jq -nc --arg r "$2" --arg b "$3" '{schema_version: "1", ok: true, command: "hook", action: "work", reason: $r, bead_id: $b}' >"$FIXDIR/hook" ;;
    drain) jq -nc '{schema_version: "1", ok: true, command: "hook", action: "drain", reason: "no_work"}' >"$FIXDIR/hook"; echo 1 >"$FIXDIR/hook.rc" ;;
    raw)   printf '%s' "$2" >"$FIXDIR/hook"; echo "${3:-0}" >"$FIXDIR/hook.rc" ;;
  esac
}
# conv <id> <status> <notes> [tracks:<id>|replies-to:<id>|blocks:<id>]... — the
# list row of a conversation assigned to this session's alias.
conv() {
  local id=$1 status=$2 notes=$3 deps="" d
  shift 3
  for d in "$@"; do
    deps="$deps${deps:+,}$(jq -nc --arg i "$id" --arg t "${d%%:*}" --arg o "${d#*:}" '{issue_id: $i, depends_on_id: $o, type: $t}')"
  done
  jq -nc --arg id "$id" --arg s "$status" --arg n "$notes" --arg a "$ALIAS" --argjson d "[$deps]" \
    '{id: $id, issue_type: "task", status: $s, assignee: $a, notes: $n, metadata: {}, dependencies: $d}' >"$FIXDIR/row-$id.json"
}
# handback <id> <text> — record a hand-back on the conversation's row.
handback() {
  jq -c --arg t "$2" '.metadata["gc.handback"] = $t | .metadata["gc.handback_at"] = "2026-11-12T10:00:00Z"' \
    "$FIXDIR/row-$1.json" >"$FIXDIR/tmp" && mv "$FIXDIR/tmp" "$FIXDIR/row-$1.json"
}
# holds <id> [<open work>...] — gctk bead holds' answer for the conversation.
holds() {
  local id=$1 p=""
  shift
  for w in "$@"; do p="$p${p:+,}$(jq -nc --arg w "$w" '{id: $w, type: "blocks", status: "open", issue_type: "task"}')"; done
  jq -nc --arg id "$id" --argjson p "[$p]" \
    '{id: $id, status: (if ($p | length) > 0 then "blocked" else "clear" end), waits: $p, pending: $p, last_landed: "", in_flight: "", arm: null, foreign: []}' \
    >"$FIXDIR/holds-$id.json"
}
assigned() { jq -sc '.' "$@" >"$FIXDIR/assigned"; }
# item <id> <status> — the list row of a bead of work, as the entry reads the
# status of one a stay names with no edge onto it.
item() { jq -nc --arg id "$1" --arg s "$2" '{id: $id, issue_type: "task", status: $s}' >"$FIXDIR/row-$1.json"; }
# enter — run the script as a sitting would; prints stdout, leaves the status
# in $FIXDIR/rc and the calls it made in $FIXDIR/calls.
enter() {
  : >"$FIXDIR/calls"
  ( PATH="$BIN:$PATH" FIXDIR="$FIXDIR" GCTK_BIN="$BIN/gctk" GC_ALIAS="${ENTRY_ALIAS-$ALIAS}" bash "$SUT" >"$FIXDIR/out" 2>"$FIXDIR/err" )
  echo $? >"$FIXDIR/rc"
  cat "$FIXDIR/out"
}
line() { grep -m1 "^$1" "$FIXDIR/out"; }
rc() { cat "$FIXDIR/rc"; }

echo "── fresh: a conversation this sitting has just taken up ──"
fresh; hook work ready_assignment tk-c; conv tk-c in_progress "" tracks:tk-s replies-to:tk-g1 replies-to:tk-g2; holds tk-c
OUT=$(enter)
is "a new claim with no record is fresh" "$(line ENTRY | cut -d: -f1)" "ENTRY fresh"
is "…and starts from the premise" "$(line NEXT=)" "NEXT=converse-recheck-premise"
is "…naming the conversation" "$(line CONVERSATION=)" "CONVERSATION=tk-c"
is "…its subject" "$(line SUBJECT=)" "SUBJECT=tk-s"
is "…the gates it replies to" "$(line GATES=)" "GATES=tk-g1 tk-g2"
is "…and the scripts directory, the script's own" "$(line CONV=)" "CONV=$(cd "$REPO/assets/scripts" && pwd)"
is "…exiting 0" "$(rc)" 0
hasnt "…with no stay values" "$OUT" "WORK="
fresh; hook work ready_assignment tk-c; conv tk-c in_progress "" tracks:tk-s; holds tk-c
enter >/dev/null
is "a conversation that replies to no gate says so" "$(line GATES=)" "GATES=none"
fresh; hook work ready_assignment tk-c; conv tk-c in_progress "holding: decide the route" tracks:tk-s; holds tk-c
enter >/dev/null
is "a conversation handed back to the queue mid-hold is fresh for its next sitting" "$(line NEXT=)" "NEXT=converse-recheck-premise"
fresh; hook work ready_assignment tk-c; conv tk-c in_progress "staying: keep the API (waits on tk-w)
holding: rule on the follow-up" tracks:tk-s blocks:tk-w; holds tk-c
enter >/dev/null
is "a return that went on to hold, then went back to the queue, is fresh for its next sitting" "$(line ENTRY | cut -d: -f1)" "ENTRY fresh"
fresh; hook work ready_assignment tk-c; conv tk-c in_progress "" tracks:tk-s; holds tk-c
printf 'gc bd: answering from the cache\n' >"$FIXDIR/notice"
enter >/dev/null
is "a gc bd notice line before the row does not stop the read" "$(line ENTRY | cut -d: -f1)" "ENTRY fresh"

echo "── interrupted: a restart while the sitting held its conversation ──"
fresh; hook work existing_assignment tk-c; conv tk-c in_progress "holding: decide the route" tracks:tk-s; holds tk-c
handback tk-c "tk-s — the route

Two routes are open. I recommend the first."
OUT=$(enter)
is "a restart over a standing hold is interrupted" "$(line ENTRY | cut -d: -f1)" "ENTRY interrupted"
is "…and goes on with the conversation" "$(line NEXT=)" "NEXT=converse-continue"
has "…printing the last hand-back recorded on it" "$OUT" "Two routes are open. I recommend the first."
has "…with when it was recorded" "$OUT" "(2026-11-12T10:00:00Z):"
fresh; hook work existing_assignment tk-c; conv tk-c in_progress "holding: decide the route" tracks:tk-s; holds tk-c
OUT=$(enter)
has "a standing hold with no hand-back recorded says so" "$OUT" "No hand-back is recorded on the conversation."
fresh; hook work existing_assignment tk-c; conv tk-c in_progress "" tracks:tk-s; holds tk-c
enter >/dev/null
is "a restart before any hold is interrupted" "$(line ENTRY | cut -d: -f1)" "ENTRY interrupted"
is "…and starts from the premise" "$(line NEXT=)" "NEXT=converse-recheck-premise"
fresh; hook work existing_assignment tk-c; conv tk-c in_progress "staying: keep the API (waits on tk-w)
holding: rule on the follow-up" tracks:tk-s blocks:tk-w; holds tk-c
enter >/dev/null
is "a restart after a return went on to hold goes on with the hold" "$(line NEXT=)" "NEXT=converse-continue"
# The hook serves no in-progress bead that waits on open work: it answers
# drain, and the claimed conversation is found by its alias.
fresh; hook drain; conv tk-c in_progress "staying: keep the API (waits on tk-w)" tracks:tk-s blocks:tk-w; holds tk-c tk-w
assigned "$FIXDIR/row-tk-c.json"
OUT=$(enter)
is "a claimed conversation whose work is still open is a stay that stopped short" "$(line ENTRY | cut -d: -f1)" "ENTRY interrupted"
is "…which the stay's skill finishes" "$(line NEXT=)" "NEXT=converse-stay"
has "…naming the open work" "$(line ENTRY)" "(tk-w)"
is "…and the work it waits on" "$(line WORK=)" "WORK=tk-w"
is "…exiting 0" "$(rc)" 0

echo "── returned: the work the sitting stayed for has closed ──"
fresh; hook work ready_assignment tk-c; conv tk-c in_progress "holding: decide the route
staying: keep the API as agreed (waits on tk-w)" tracks:tk-s replies-to:tk-g1 blocks:tk-w; holds tk-c
OUT=$(enter)
is "a stay whose work has closed is a return" "$(line ENTRY | cut -d: -f1)" "ENTRY returned"
is "…loading the stay's skill" "$(line NEXT=)" "NEXT=converse-stay"
is "…naming the work it waited on" "$(line WORK=)" "WORK=tk-w"
is "…and what the operator agreed, without the work its line names" "$(line AGREED=)" "AGREED=keep the API as agreed"
is "…with the conversation's values" "$(line SUBJECT=)" "SUBJECT=tk-s"
fresh; hook work existing_assignment tk-c; conv tk-c in_progress "staying: keep the API (waits on tk-w)" tracks:tk-s blocks:tk-w; holds tk-c
enter >/dev/null
is "a restart during the return is still the return" "$(line ENTRY | cut -d: -f1)" "ENTRY returned"
fresh; hook work ready_assignment tk-c; conv tk-c in_progress "staying: keep the API (waits on tk-w1)
holding: rule on the follow-up
staying: keep the API and add the flag (waits on tk-w1, tk-w2)" tracks:tk-s blocks:tk-w1 blocks:tk-w2; holds tk-c
enter >/dev/null
is "a second stay's return names all its work" "$(line WORK=)" "WORK=tk-w1 tk-w2"
is "…and the newest agreement" "$(line AGREED=)" "AGREED=keep the API and add the flag"

echo "── waiting: a stay woken early, while its work is out ──"
fresh; hook drain; conv tk-c open "staying: keep the API (waits on tk-w)" tracks:tk-s blocks:tk-w; holds tk-c tk-w
assigned "$FIXDIR/row-tk-c.json"
OUT=$(enter)
is "a drain over an open conversation whose work is out is waiting" "$(line ENTRY | cut -d: -f1)" "ENTRY waiting"
is "…loading the stay's skill" "$(line NEXT=)" "NEXT=converse-stay"
is "…naming the conversation" "$(line CONVERSATION=)" "CONVERSATION=tk-c"
is "…the work" "$(line WORK=)" "WORK=tk-w"
is "…and what was agreed" "$(line AGREED=)" "AGREED=keep the API"
is "…exiting 0" "$(rc)" 0
has "…after listing this session's open and claimed beads by its alias" "$(cat "$FIXDIR/calls")" "bd list --assignee $ALIAS --status open,in_progress --json"

echo "── a stay that stopped short: each window its writes leave, with the work open and closed ──"
# converse-signoff.sh --stay writes `staying: <agreed>` before anything else,
# then the sign-off's own writes, then `staying: <agreed> (waits on <the
# work>)`, then an edge onto each bead that line names, then the status that
# leaves the conversation open. A stop in any window, and a restart after it,
# reads as a stay, never as a hold that stands or a sitting that held nothing,
# and reads as a return only once each bead the newest line names has closed.
#
# After the first line, before the line that names the work. Nothing names the
# work yet, so whether it is open or has closed, the record is the same, and so
# is the entry: the sign-off has not finished.
for st in open closed; do
  fresh; hook work existing_assignment tk-c; conv tk-c in_progress "holding: decide the route
staying: keep the API" tracks:tk-s replies-to:tk-g1; holds tk-c; item tk-w "$st"
  OUT=$(enter)
  is "a stay stopped before its sign-off finished, its work $st, is interrupted" "$(line ENTRY | cut -d: -f1)" "ENTRY interrupted"
  has "…saying the sign-off did not finish" "$(line ENTRY)" "stopped before its sign-off finished"
  is "…which the stay's skill runs again, not the hold's" "$(line NEXT=)" "NEXT=converse-stay"
  is "…naming no work, which no line names yet" "$(line WORK=)" "WORK="
  is "…and what was agreed" "$(line AGREED=)" "AGREED=keep the API"
  hasnt "…reading nothing of the work" "$(cat "$FIXDIR/calls")" "tk-w"
  is "…exiting 0" "$(rc)" 0
done
fresh; hook work existing_assignment tk-c; conv tk-c in_progress "staying: keep the API" tracks:tk-s replies-to:tk-g1; holds tk-c
enter >/dev/null
is "a stay with no hold before it, stopped there, is interrupted" "$(line ENTRY | cut -d: -f1)" "ENTRY interrupted"
is "…and never sent to the premise re-check" "$(line NEXT=)" "NEXT=converse-stay"
fresh; hook work existing_assignment tk-c; conv tk-c in_progress "staying: keep the API (waits on tk-w1)
holding: rule on the follow-up
staying: add the flag" tracks:tk-s blocks:tk-w1; holds tk-c
enter >/dev/null
is "a second stay stopped there, after a return that held, is interrupted, whatever the first stay's closed edge says" "$(line ENTRY | cut -d: -f1)" "ENTRY interrupted"
hasnt "…and is no return" "$(line ENTRY)" "returned"
fresh; hook drain; conv tk-c open "staying: keep the API (waits on tk-w1)
staying: keep the API and add the flag" tracks:tk-s blocks:tk-w1; holds tk-c tk-w1
assigned "$FIXDIR/row-tk-c.json"
enter >/dev/null
is "a second stay from a sitting woken early, stopped there, is interrupted, not waiting" "$(line ENTRY | cut -d: -f1)" "ENTRY interrupted"
is "…which the stay's skill runs again" "$(line NEXT=)" "NEXT=converse-stay"
#
# After the line that names the work, before its edge. The claim serves the
# conversation, since no edge holds it, so the work's own status decides.
fresh; hook work existing_assignment tk-c; conv tk-c in_progress "holding: decide the route
staying: keep the API (waits on tk-w)" tracks:tk-s replies-to:tk-g1; holds tk-c; item tk-w open
OUT=$(enter)
is "a stay stopped before its edge, its work open, is interrupted" "$(line ENTRY | cut -d: -f1)" "ENTRY interrupted"
has "…naming the work it does not wait on yet" "$(line ENTRY)" "wait on tk-w, which is still out"
is "…which the stay's skill runs again" "$(line NEXT=)" "NEXT=converse-stay"
is "…with the work its line names" "$(line WORK=)" "WORK=tk-w"
has "…after reading that work's status" "$(cat "$FIXDIR/calls")" "bd list --id tk-w --all --json"
fresh; hook work existing_assignment tk-c; conv tk-c in_progress "holding: decide the route
staying: keep the API (waits on tk-w)" tracks:tk-s replies-to:tk-g1; holds tk-c; item tk-w closed
enter >/dev/null
is "a stay stopped before its edge, its work closed, is the return" "$(line ENTRY | cut -d: -f1)" "ENTRY returned"
is "…naming the work" "$(line WORK=)" "WORK=tk-w"
is "…and what was agreed" "$(line AGREED=)" "AGREED=keep the API"
fresh; hook work existing_assignment tk-c; conv tk-c in_progress "staying: keep the API (waits on tk-w1)
holding: rule on the follow-up
staying: add the flag (waits on tk-w2)" tracks:tk-s blocks:tk-w1; holds tk-c; item tk-w2 open
enter >/dev/null
is "a second stay stopped before its edge is interrupted, though the first stay's edge onto closed work stands" "$(line ENTRY | cut -d: -f1)" "ENTRY interrupted"
has "…naming the second stay's work" "$(line ENTRY)" "wait on tk-w2"
fresh; hook drain; conv tk-c in_progress "staying: keep the API (waits on tk-w1, tk-w2)" tracks:tk-s blocks:tk-w1; holds tk-c tk-w1; item tk-w2 open
assigned "$FIXDIR/row-tk-c.json"
enter >/dev/null
is "a stay stopped between its edges, the unedged work open, is interrupted" "$(line ENTRY | cut -d: -f1)" "ENTRY interrupted"
has "…naming the work it has no edge onto" "$(line ENTRY)" "wait on tk-w2, which is still out"
fresh; hook drain; conv tk-c in_progress "staying: keep the API (waits on tk-w1, tk-w2)" tracks:tk-s blocks:tk-w1; holds tk-c tk-w1; item tk-w2 closed
assigned "$FIXDIR/row-tk-c.json"
enter >/dev/null
is "…and with the unedged work closed, it stopped before it left the conversation to wait" "$(line ENTRY | cut -d: -f1)" "ENTRY interrupted"
has "…waiting on the work still open" "$(line ENTRY)" "still open (tk-w1) but is still claimed"
#
# After the edges, before the status write. The claim serves no conversation
# that waits on open work, so with the work open the drain finds it still
# claimed, and with the work closed the claim serves it as an existing
# assignment, as a restart during the return does.
fresh; hook drain; conv tk-c in_progress "staying: keep the API (waits on tk-w)" tracks:tk-s blocks:tk-w; holds tk-c tk-w
assigned "$FIXDIR/row-tk-c.json"
enter >/dev/null
is "a stay stopped before its status write, its work open, is interrupted" "$(line ENTRY | cut -d: -f1)" "ENTRY interrupted"
fresh; hook work existing_assignment tk-c; conv tk-c in_progress "staying: keep the API (waits on tk-w)" tracks:tk-s blocks:tk-w; holds tk-c
enter >/dev/null
is "a stay stopped before its status write, its work closed, is the return" "$(line ENTRY | cut -d: -f1)" "ENTRY returned"
#
# The finished stay: open, waiting while its work is out, and the return once
# it closes, are the waiting and returned sections above.
#
# A hold after a stay whose work is still out stands, and a conversation that
# waits on open work no stay recorded is a record that does not agree with
# itself.
fresh; hook drain; conv tk-c in_progress "staying: keep the API (waits on tk-w)
holding: rule on the follow-up" tracks:tk-s blocks:tk-w; holds tk-c tk-w
handback tk-c "tk-s — the follow-up"
assigned "$FIXDIR/row-tk-c.json"
OUT=$(enter)
is "a hold after a stay whose work is still out stands" "$(line ENTRY | cut -d: -f1)" "ENTRY interrupted"
is "…and goes on with the hold" "$(line NEXT=)" "NEXT=converse-continue"
has "…printing the last hand-back" "$OUT" "tk-s — the follow-up"

echo "── none: no conversation is this session's ──"
fresh; hook drain; printf '[]' >"$FIXDIR/assigned"
enter >/dev/null
is "a drain with nothing open under the alias drains" "$(line NEXT=)" "NEXT=drain"
is "…saying so" "$(line ENTRY | cut -d: -f1)" "ENTRY none"
is "…exiting 0" "$(rc)" 0
fresh; hook drain
jq -nc '{id: "tk-x", issue_type: "task", status: "open", assignee: "gc-toolkit/gc-toolkit.tk-c", notes: "", dependencies: []}' >"$FIXDIR/x.json"
assigned "$FIXDIR/x.json"
enter >/dev/null
is "an open bead under the alias that is no conversation leaves nothing to hold" "$(line NEXT=)" "NEXT=drain"

echo "── unreadable: never an answer to drain or close on ──"
unread() {
  enter >/dev/null
  is "$1: unreadable" "$(line ENTRY | cut -d: -f1)" "ENTRY unreadable"
  is "$1: exits 1" "$(rc)" 1
  hasnt "$1: names no drain" "$(cat "$FIXDIR/out")" "NEXT=drain"
  hasnt "$1: prints no jq error of its own" "$(cat "$FIXDIR/err")" "jq: error"
}
fresh; hook raw "" 1; unread "the hook answers nothing"
fresh; hook raw "Error: store unavailable" 1; unread "the hook answers no JSON"
fresh; hook raw '{"action":"wait"}'; unread "the hook answers an action it does not know"
fresh; hook raw '{"action":"work","reason":"ready_assignment"}'; unread "the claim names no bead"
fresh; hook work ready_assignment tk-c; unread "the claimed conversation does not read"
fresh; hook work ready_assignment tk-c; conv tk-c in_progress "" replies-to:tk-g1; holds tk-c
unread "the claimed bead is no conversation"
fresh; hook work ready_assignment tk-c; conv tk-c in_progress "" tracks:tk-s; unread "holds does not answer"
fresh; hook work ready_assignment tk-c; conv tk-c in_progress "" tracks:tk-s
printf '{"id":"tk-c","error":"store timeout"}' >"$FIXDIR/holds-tk-c.json"; unread "holds answers an error"
fresh; hook drain; ENTRY_ALIAS="" unread "a drain with no alias to list under"
fresh; hook drain; unread "the open beads under the alias do not list"
fresh; hook drain; printf '{"error":"no store"}' >"$FIXDIR/assigned"; unread "the listing answers no list"
fresh; hook drain; conv tk-c open "" tracks:tk-s; holds tk-c; assigned "$FIXDIR/row-tk-c.json"
unread "an open conversation with no work holding it, though the claim found nothing"
fresh; hook drain; conv tk-c in_progress "holding: x" tracks:tk-s; holds tk-c; assigned "$FIXDIR/row-tk-c.json"
unread "a claimed conversation with no work holding it, though the claim found nothing"
fresh; hook work ready_assignment tk-c; conv tk-c in_progress "staying: x (waits on tk-w)" tracks:tk-s blocks:tk-w; holds tk-c tk-w
unread "a claim served while holds still reads its work open"
fresh; hook drain; conv tk-c open "staying: x (waits on tk-w)" tracks:tk-s blocks:tk-w; assigned "$FIXDIR/row-tk-c.json"
unread "the waiting conversation's holds does not answer"

fresh; hook drain; conv tk-c in_progress "" tracks:tk-s blocks:tk-w; holds tk-c tk-w; assigned "$FIXDIR/row-tk-c.json"
unread "a conversation that waits on open work with no staying: line"
fresh; hook work existing_assignment tk-c; conv tk-c in_progress "staying: x (waits on tk-w)" tracks:tk-s; holds tk-c
unread "a bead the stay names with no edge onto it does not read"

echo "── it writes nothing beyond the hook's claim, and takes no arguments ──"
fresh; hook work ready_assignment tk-c; conv tk-c in_progress "staying: x (waits on tk-w)" tracks:tk-s blocks:tk-w; holds tk-c
enter >/dev/null
is "a return makes three calls: the claim, the row and holds" "$(tr '\n' '|' <"$FIXDIR/calls")" "hook --claim --json|bd list --id tk-c --all --json|gctk bead holds tk-c|"
( PATH="$BIN:$PATH" bash "$SUT" --conversation tk-c >/dev/null 2>&1 ); is "an argument is a usage error" "$?" 2

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
