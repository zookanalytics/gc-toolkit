#!/usr/bin/env bash
# converse-entry.test.sh — a converse sitting's way in
# (assets/scripts/converse-entry.sh). Each case gives the hook's answer and the
# conversation's record, and pins the entry the script prints, the skill it
# names next and the values it hands on: a fresh conversation, a restart while
# the hold stands or before it, a stay woken early while its work is out, a
# stay that stopped short in each window its writes leave, with its work open
# and with it closed, a second stay with an earlier stay's text, a hold claimed
# back over a second stay that stopped short, while the earlier work is out and
# once it closes, the return of the work, a stay on its gate before and after
# the gate closes, with the gate's work handed on, a stay whose line names its
# work rather than a gate, a gate the sitting filed before it stayed, open or
# closed, no conversation at all, Gas City stopping the session whatever its
# conversation's state, and each way the state can fail to read, which is never
# an answer to drain on.
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

# The gc stub answers the reads the entry makes from fixtures, logs every call,
# and refuses anything else, so a write the entry should never make fails the
# case that reaches it. A dep list joins each bead the conversation's row waits
# on through a blocks edge to that bead's row, as bd does, and a bead with no
# row of its own answers as open work. deps.down fails it.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/gc" <<'STUB'
printf '%s\n' "$*" >>"$FIXDIR/calls"
case "$*" in
  "hook --claim --json")
    [ -r "$FIXDIR/hook" ] && cat "$FIXDIR/hook"
    [ ! -r "$FIXDIR/hook.err" ] || cat "$FIXDIR/hook.err" >&2
    exit "$(cat "$FIXDIR/hook.rc" 2>/dev/null || echo 0)" ;;
  "bd list --id "*" --all --json")
    id=$4
    [ -r "$FIXDIR/row-$id.json" ] || { echo "Error: no issue found matching $id" >&2; exit 1; }
    [ ! -r "$FIXDIR/notice" ] || cat "$FIXDIR/notice"
    jq -c '[.]' "$FIXDIR/row-$id.json" ;;
  "bd list --assignee "*" --status open,in_progress --json")
    [ -r "$FIXDIR/assigned" ] || { echo "Error: list failed" >&2; exit 1; }
    cat "$FIXDIR/assigned" ;;
  "bd dep list "*" --type blocks --json")
    id=$4
    [ ! -e "$FIXDIR/deps.down" ] || { echo "Error: store unavailable" >&2; exit 1; }
    [ -r "$FIXDIR/row-$id.json" ] || { echo "Error: no issue found matching $id" >&2; exit 1; }
    out=""
    for d in $(jq -r '.dependencies[]? | select(.type == "blocks") | .depends_on_id' "$FIXDIR/row-$id.json"); do
      if [ -r "$FIXDIR/row-$d.json" ]; then r=$(jq -c '. + {dependency_type: "blocks"}' "$FIXDIR/row-$d.json")
      else r=$(jq -nc --arg d "$d" '{id: $d, issue_type: "task", status: "open", dependency_type: "blocks"}'); fi
      out="$out${out:+,}$r"
    done
    printf '[%s]\n' "$out" ;;
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
# hook work <reason> <bead> | hook drain [<reason> [<stderr>]] | hook raw <text> [<rc>]
# A drain's reason defaults to no_work; <stderr> is what the hook writes there.
hook() {
  case "$1" in
    work)  jq -nc --arg r "$2" --arg b "$3" '{schema_version: "1", ok: true, command: "hook", action: "work", reason: $r, bead_id: $b}' >"$FIXDIR/hook" ;;
    drain) jq -nc --arg r "${2:-no_work}" '{schema_version: "1", ok: true, command: "hook", action: "drain", reason: $r}' >"$FIXDIR/hook"; echo 1 >"$FIXDIR/hook.rc"
           [ -z "${3:-}" ] || printf '%s\n' "$3" >"$FIXDIR/hook.err" ;;
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
# holds <id> [<open work>|gate:<open gate>...] — gctk bead holds' answer for
# the conversation; a gate: one is a stay's gate.
holds() {
  local id=$1 p="" w
  shift
  for w in "$@"; do
    case "$w" in
      gate:*) p="$p${p:+,}$(jq -nc --arg w "${w#gate:}" '{id: $w, type: "blocks", status: "open", issue_type: "gate", await_type: "gctk:needs-review"}')" ;;
      *) p="$p${p:+,}$(jq -nc --arg w "$w" '{id: $w, type: "blocks", status: "open", issue_type: "task"}')" ;;
    esac
  done
  jq -nc --arg id "$id" --argjson p "[$p]" \
    '{id: $id, status: (if ($p | length) > 0 then "blocked" else "clear" end), waits: $p, pending: $p, last_landed: "", in_flight: "", arm: null, foreign: []}' \
    >"$FIXDIR/holds-$id.json"
}
assigned() { jq -sc '.' "$@" >"$FIXDIR/assigned"; }
# item <id> <status> — the list row of a bead of work, as the entry reads the
# status of one a stay names with no edge onto it.
item() { jq -nc --arg id "$1" --arg s "$2" '{id: $id, issue_type: "task", status: $s}' >"$FIXDIR/row-$1.json"; }
# stay_gate <id> <work> <status> [<closed at> [<reason>]] — the row of a stay's
# gate on <work>, as a dep list joins it.
stay_gate() {
  jq -nc --arg id "$1" --arg w "$2" --arg s "$3" --arg at "${4:-}" --arg why "${5:-}" \
    '{id: $id, issue_type: "gate", status: $s, await_type: "gctk:needs-review", await_id: $w}
     + (if $at == "" then {} else {closed_at: $at, close_reason: $why} end)' >"$FIXDIR/row-$1.json"
}
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
# A second stay with an earlier stay's text writes its own first line too, so
# a stop there reads as that stay, whether the earlier stay's work has closed
# or is still out.
fresh; hook work existing_assignment tk-c; conv tk-c in_progress "staying: keep the API (waits on tk-w1)
staying: keep the API" tracks:tk-s blocks:tk-w1; holds tk-c
enter >/dev/null
is "a second stay with the same text, stopped there after the first stay's work closed, is interrupted" "$(line ENTRY | cut -d: -f1)" "ENTRY interrupted"
hasnt "…and is no return of that work" "$(line ENTRY)" "returned"
fresh; hook drain; conv tk-c open "staying: keep the API (waits on tk-w1)
staying: keep the API" tracks:tk-s blocks:tk-w1; holds tk-c tk-w1
assigned "$FIXDIR/row-tk-c.json"
enter >/dev/null
is "…and with that work still out, it is interrupted, not waiting" "$(line ENTRY | cut -d: -f1)" "ENTRY interrupted"
is "…which the stay's skill runs again" "$(line NEXT=)" "NEXT=converse-stay"
# When the record cannot rebuild the stopped call, the stay's skill holds, and
# first claims back the conversation a second stay left open over the first
# stay's work. That hold stands while the work is out and once it closes.
STOPPED="staying: keep the API (waits on tk-w1)
staying: add the flag
holding: say what the stopped stay should wait on"
fresh; hook drain; conv tk-c in_progress "$STOPPED" tracks:tk-s blocks:tk-w1; holds tk-c tk-w1
assigned "$FIXDIR/row-tk-c.json"
enter >/dev/null
is "a hold claimed back over a second stay that stopped short, the first stay's work still out, stands" "$(line ENTRY | cut -d: -f1)" "ENTRY interrupted"
is "…and goes on with the hold" "$(line NEXT=)" "NEXT=converse-continue"
fresh; hook work existing_assignment tk-c; conv tk-c in_progress "$STOPPED" tracks:tk-s blocks:tk-w1; holds tk-c
enter >/dev/null
is "…and once that work closes, the claim returns the held conversation and the hold stands" "$(line ENTRY | cut -d: -f1)" "ENTRY interrupted"
is "…going on with the hold" "$(line NEXT=)" "NEXT=converse-continue"
fresh; hook work ready_assignment tk-c; conv tk-c in_progress "$STOPPED" tracks:tk-s blocks:tk-w1; holds tk-c
enter >/dev/null
is "a hold left on the open conversation reads as a fresh sitting once that work closes, so the skill claims it back first" "$(line NEXT=)" "NEXT=converse-recheck-premise"
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

echo "── a stay in a rig's store waits on its gate, which names the work it is for ──"
# The second staying: line names the stay's gate. The entry reads the stay as
# waiting while the gate is open and as returned once it has closed, and hands
# on the gate's await id as the work.
fresh; hook drain; conv tk-c open "staying: keep the API (waits on tk-gate)" tracks:tk-s blocks:tk-gate; holds tk-c gate:tk-gate; stay_gate tk-gate tk-w open
assigned "$FIXDIR/row-tk-c.json"
OUT=$(enter)
is "a stay on its open gate is waiting" "$(line ENTRY | cut -d: -f1)" "ENTRY waiting"
has "…naming the work and its gate" "$(line ENTRY)" "stays for tk-w, on its gate tk-gate"
is "…loading the stay's skill" "$(line NEXT=)" "NEXT=converse-stay"
is "…handing on the gate's work as the work" "$(line WORK=)" "WORK=tk-w"
is "…and what was agreed" "$(line AGREED=)" "AGREED=keep the API"
is "…exiting 0" "$(rc)" 0
has "…after reading what the conversation waits on" "$(cat "$FIXDIR/calls")" "bd dep list tk-c --type blocks --json"
fresh; hook work ready_assignment tk-c; conv tk-c open "staying: keep the API (waits on tk-gate)" tracks:tk-s blocks:tk-gate; holds tk-c
stay_gate tk-gate tk-w closed 2026-11-20T10:00:00Z "tk-w's PR reads needs-review in its own right at abc1234"
enter >/dev/null
is "once its gate has closed, the stay is back" "$(line ENTRY | cut -d: -f1)" "ENTRY returned"
has "…saying why the gate closed" "$(line ENTRY)" "(tk-w's PR reads needs-review in its own right at abc1234)"
has "…and which work is back" "$(line ENTRY)" "so tk-w is back with conversation tk-c"
is "…loading the stay's skill" "$(line NEXT=)" "NEXT=converse-stay"
is "…handing on the gate's work" "$(line WORK=)" "WORK=tk-w"
is "…and what was agreed" "$(line AGREED=)" "AGREED=keep the API"
fresh; hook work existing_assignment tk-c; conv tk-c in_progress "staying: keep the API (waits on tk-gate)" tracks:tk-s blocks:tk-gate; holds tk-c
stay_gate tk-gate tk-w closed 2026-11-20T10:00:00Z "tk-w closed"
enter >/dev/null
is "a restart during that return is still the return" "$(line ENTRY | cut -d: -f1)" "ENTRY returned"
is "…for the gate's work" "$(line WORK=)" "WORK=tk-w"
# The stay's call stopped after its line named the gate and before its status
# write: the conversation is still claimed, and its gate is open.
fresh; hook drain; conv tk-c in_progress "staying: keep the API (waits on tk-gate)" tracks:tk-s blocks:tk-gate; holds tk-c gate:tk-gate; stay_gate tk-gate tk-w open
assigned "$FIXDIR/row-tk-c.json"
enter >/dev/null
is "a stay stopped before its status write, its gate open, is interrupted" "$(line ENTRY | cut -d: -f1)" "ENTRY interrupted"
has "…naming its gate and the gate's work" "$(line ENTRY)" "waits on its gate tk-gate for tk-w, which is still open, but is still claimed"
is "…which the stay's skill runs again" "$(line NEXT=)" "NEXT=converse-stay"
is "…with the gate's work" "$(line WORK=)" "WORK=tk-w"
# Work that had closed by the stay needs no gate: the line names the work
# itself, with no edge onto it, and the entry reads it as back.
fresh; hook work existing_assignment tk-c; conv tk-c in_progress "staying: keep the API (waits on tk-w)" tracks:tk-s; holds tk-c; item tk-w closed
enter >/dev/null
is "a stay that named its closed work, with no gate, is the return" "$(line ENTRY | cut -d: -f1)" "ENTRY returned"
is "…for that work" "$(line WORK=)" "WORK=tk-w"
# A stay made before stays waited on a gate names its work, and its
# conversation waits on that work through an edge, as a stay in the city's own
# store does. That record reads as it always has: waiting while the work is
# out, and returned once it has closed.
fresh; hook drain; conv tk-c open "staying: keep the API (waits on tk-old)" tracks:tk-s blocks:tk-old; holds tk-c tk-old; item tk-old open
assigned "$FIXDIR/row-tk-c.json"
enter >/dev/null
is "a stay whose line names its work, not a gate, is waiting while that work is out" "$(line ENTRY | cut -d: -f1)" "ENTRY waiting"
is "…handing on that work" "$(line WORK=)" "WORK=tk-old"
fresh; hook work ready_assignment tk-c; conv tk-c open "staying: keep the API (waits on tk-old)" tracks:tk-s blocks:tk-old; holds tk-c; item tk-old closed
enter >/dev/null
is "…and returned once it has closed" "$(line ENTRY | cut -d: -f1)" "ENTRY returned"
is "…handing on that work" "$(line WORK=)" "WORK=tk-old"

echo "── a gate the sitting filed before it stayed ──"
# The sitting files the stay's gate for work it sent itself, then runs the
# stay's call. A restart between the two finds a claimed conversation that waits
# on the open gate, with neither a staying: nor a holding: line.
fresh; hook drain; conv tk-c in_progress "" tracks:tk-s blocks:tk-gate; holds tk-c gate:tk-gate; stay_gate tk-gate tk-w open
assigned "$FIXDIR/row-tk-c.json"
OUT=$(enter)
is "a claimed conversation on the open gate the sitting filed, with no stay recorded, is interrupted" "$(line ENTRY | cut -d: -f1)" "ENTRY interrupted"
has "…naming the gate" "$(line ENTRY)" "the gate tk-gate"
has "…and saying the stay's call has not run" "$(line ENTRY)" "the stay's call has not run"
is "…which the stay's skill runs" "$(line NEXT=)" "NEXT=converse-stay"
is "…for the gate's work" "$(line WORK=)" "WORK=tk-w"
is "…with nothing agreed on record" "$(line AGREED=)" "AGREED="
is "…and the conversation's values" "$(line SUBJECT=)" "SUBJECT=tk-s"
is "…exiting 0" "$(rc)" 0
# Left open rather than claimed, the same record is no stay the sign-off writes.
fresh; hook drain; conv tk-c open "" tracks:tk-s blocks:tk-gate; holds tk-c gate:tk-gate; stay_gate tk-gate tk-w open
assigned "$FIXDIR/row-tk-c.json"
enter >/dev/null
is "an open conversation on that gate, with no stay recorded, does not read" "$(line ENTRY | cut -d: -f1)" "ENTRY unreadable"
# The gate can close before the stay's call runs, when the work is finished
# first, and a restart then finds it closed with neither line. Its work is
# back, and its return is owed.
fresh; hook work existing_assignment tk-c; conv tk-c in_progress "" tracks:tk-s blocks:tk-gate; holds tk-c
stay_gate tk-gate tk-w closed 2026-11-20T10:00:00Z "tk-w's PR reads needs-review in its own right at abc1234"
enter >/dev/null
is "a restart after the gate the sitting filed has closed, with no stay recorded, is the return" "$(line ENTRY | cut -d: -f1)" "ENTRY returned"
has "…saying the gate closed before the stay" "$(line ENTRY)" "closed before it stayed"
has "…and why" "$(line ENTRY)" "(tk-w's PR reads needs-review in its own right at abc1234)"
is "…which the stay's skill carries out" "$(line NEXT=)" "NEXT=converse-stay"
is "…for the gate's work" "$(line WORK=)" "WORK=tk-w"
is "…with nothing agreed on record" "$(line AGREED=)" "AGREED="
# One that closed before the last hand-back was the work of a return already
# made, and a conversation that waits on work rather than a gate is no stay.
fresh; hook work existing_assignment tk-c; conv tk-c in_progress "" tracks:tk-s blocks:tk-gate; handback tk-c "tk-s — the return"; holds tk-c
stay_gate tk-gate tk-w closed 2026-11-11T10:00:00Z "tk-w closed"
enter >/dev/null
is "a restart after such a gate closed before the last hand-back starts from the premise" "$(line NEXT=)" "NEXT=converse-recheck-premise"
fresh; hook work existing_assignment tk-c; conv tk-c in_progress "" tracks:tk-s blocks:tk-w; holds tk-c; item tk-w closed
enter >/dev/null
is "a restart on a conversation whose edge is onto work, not a gate, starts from the premise" "$(line NEXT=)" "NEXT=converse-recheck-premise"

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

echo "── stop: Gas City stops the session, whatever its conversation's state ──"
DRAIN_SAID="gc hook --claim: drain pending for this session; run: gc runtime drain-ack tk-s1 — then exit"
# stopped <what> — the case's entry is a stop that drains on the hook's word,
# reads nothing past the claim, and passes on what the hook said.
stopped() {
  is "$1: stop" "$(line ENTRY | cut -d: -f1)" "ENTRY stop"
  is "$1: …drains" "$(line NEXT=)" "NEXT=drain"
  is "$1: …exiting 0" "$(rc)" 0
  is "$1: …reading nothing past the claim" "$(tr '\n' '|' <"$FIXDIR/calls")" "hook --claim --json|"
}
fresh; hook drain drain_pending "$DRAIN_SAID"; conv tk-c in_progress "holding: decide the route" tracks:tk-s; holds tk-c; assigned "$FIXDIR/row-tk-c.json"
OUT=$(enter)
stopped "a drain under way over a hold that stands"
has "…naming the reason" "$(line ENTRY)" "(drain_pending)"
has "…and passing on the acknowledgement the hook names" "$OUT" "$DRAIN_SAID"
hasnt "…never as a hold to continue" "$OUT" "NEXT=converse-continue"
# Gas City refuses the session's own drain-ack while it holds the conversation
# it claimed and has not finished, and tells it to continue.
has "…and, when the ack is refused over the conversation the session holds, going on with it" "$(line ENTRY)" \
  "When the ack is refused because this session holds its conversation, which it started and has not finished, the sitting goes on with that conversation"
has "…until the conversation no longer holds the session, when it acknowledges the drain" "$(line ENTRY)" \
  "acknowledges the drain once the conversation is closed, back in the operator's queue or left to wait."
fresh; hook drain drain_pending "$DRAIN_SAID"; conv tk-c open "staying: keep the API (waits on tk-w)" tracks:tk-s blocks:tk-w; holds tk-c tk-w; assigned "$FIXDIR/row-tk-c.json"
OUT=$(enter)
stopped "a drain under way over a stay whose work is out"
hasnt "…never as a stay that waits on" "$OUT" "NEXT=converse-stay"
fresh; hook drain drain_pending "$DRAIN_SAID"; conv tk-c open "" tracks:tk-s; holds tk-c; assigned "$FIXDIR/row-tk-c.json"
enter >/dev/null
stopped "a drain under way over a conversation nothing holds"
fresh; hook drain stale_session; conv tk-c in_progress "holding: decide the route" tracks:tk-s; holds tk-c; assigned "$FIXDIR/row-tk-c.json"
OUT=$(enter)
stopped "a stale session over a hold that stands"
hasnt "…with no hook line when the hook wrote none" "$OUT" "The hook said:"
fresh; hook drain stale_session; printf '[]' >"$FIXDIR/assigned"
enter >/dev/null
stopped "a stale session holding no conversation"
fresh; hook drain rig_suspended; conv tk-c open "staying: keep the API (waits on tk-w)" tracks:tk-s blocks:tk-w; holds tk-c tk-w; assigned "$FIXDIR/row-tk-c.json"
enter >/dev/null
stopped "a suspended rig over a stay whose work is out"

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
fresh; hook raw '{"action":"drain"}' 1; unread "the hook drains with no reason"
fresh; hook drain claims_errored "gc hook --claim: claiming tk-c: database is locked"; conv tk-c open "" tracks:tk-s; holds tk-c; assigned "$FIXDIR/row-tk-c.json"
unread "the claim of a ready conversation did not land"
has "…passing on what the hook said" "$(cat "$FIXDIR/out")" "claiming tk-c: database is locked"
is "…reading nothing past the claim" "$(tr '\n' '|' <"$FIXDIR/calls")" "hook --claim --json|"
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
fresh; hook drain; conv tk-c open "staying: x (waits on tk-gate)" tracks:tk-s blocks:tk-gate; holds tk-c gate:tk-gate; stay_gate tk-gate tk-w open
assigned "$FIXDIR/row-tk-c.json"; : >"$FIXDIR/deps.down"
unread "what a staying conversation waits on does not list"
fresh; hook drain; conv tk-c in_progress "" tracks:tk-s blocks:tk-gate; holds tk-c gate:tk-gate; stay_gate tk-gate tk-w open
assigned "$FIXDIR/row-tk-c.json"; : >"$FIXDIR/deps.down"
unread "what a claimed conversation on a gate with no stay recorded waits on does not list"
fresh; hook work existing_assignment tk-c; conv tk-c in_progress "" tracks:tk-s blocks:tk-gate; holds tk-c
stay_gate tk-gate tk-w closed 2026-11-20T10:00:00Z x; : >"$FIXDIR/deps.down"
unread "what a restarted conversation with no stay recorded waits on does not list"

echo "── it writes nothing beyond the hook's claim, and takes no arguments ──"
fresh; hook work ready_assignment tk-c; conv tk-c in_progress "staying: x (waits on tk-w)" tracks:tk-s blocks:tk-w; holds tk-c
enter >/dev/null
is "a return makes four calls: the claim, the row, holds and what the conversation waits on" "$(tr '\n' '|' <"$FIXDIR/calls")" "hook --claim --json|bd list --id tk-c --all --json|gctk bead holds tk-c|bd dep list tk-c --type blocks --json|"
fresh; hook work ready_assignment tk-c; conv tk-c in_progress "" tracks:tk-s replies-to:tk-g1; holds tk-c
enter >/dev/null
is "a fresh conversation that waits on nothing makes three: the claim, the row and holds" "$(tr '\n' '|' <"$FIXDIR/calls")" "hook --claim --json|bd list --id tk-c --all --json|gctk bead holds tk-c|"
( PATH="$BIN:$PATH" bash "$SUT" --conversation tk-c >/dev/null 2>&1 ); is "an argument is a usage error" "$?" 2

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
