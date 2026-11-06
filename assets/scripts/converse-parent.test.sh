#!/usr/bin/env bash
# converse-parent.test.sh — the parent a sitting gives work that serves the
# subject's epic (assets/scripts/converse-parent.sh): the subject's nearest
# parent-child ancestor that is not closed. A parent-child edge is stored on the
# child, and bd's show prints each parent's status beside its edge, so the walk
# reads the subject and then each closed parent it climbs past. The cases pin
# the walk's answer, the beads it reads, and that an unreadable bead is an error
# rather than an empty answer.
#
# Hermetic: stubs gc, reads the repo only; no city, no network.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/../.."
SUT="$REPO/assets/scripts/converse-parent.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "${2:-}"; }
is()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "got '$2', want '$3'"; fi; }

[ -r "$SUT" ] || { printf 'converse-parent: cannot read %s\n' "$SUT" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { printf 'converse-parent: jq is required\n' >&2; exit 1; }

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/gctk-converse-parent-test.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT
BIN="$TMPD/bin"; FIXDIR="$TMPD/fix"
mkdir -p "$BIN" "$FIXDIR"

# The stub answers `gc bd show <id> --json` from $FIXDIR/<id>.json, logs each
# id it is asked for, and fails as gc does for a bead it cannot show.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/gc" <<'STUB'
[ "${1:-}" = "bd" ] && [ "${2:-}" = "show" ] || exit 2
printf '%s\n' "${3:-}" >>"$FIXDIR/reads"
[ -r "$FIXDIR/${3:-}.json" ] || { echo "Error: no issue found matching ${3:-}" >&2; exit 1; }
cat "$FIXDIR/${3:-}.json"
STUB
chmod +x "$BIN/gc"

echo "── the script is shipped executable and syntactically valid ──"
[ -x "$SUT" ] && ok "converse-parent.sh is executable" || bad "converse-parent.sh is executable" "chmod +x it"
bash -n "$SUT" && ok "converse-parent.sh: valid bash" || bad "converse-parent.sh: valid bash" "bash -n failed"

# bead <id> [<parent>:<status>|tracks:<id>]... — the show fixture of <id>, with
# one dependency row per argument, in order: a parent-child edge onto <parent>
# at <status>, or a tracks edge onto <id>.
bead() {
    local id=$1 rows="" row
    shift
    for row in "$@"; do
        case "$row" in
            tracks:*) row=$(jq -nc --arg p "${row#tracks:}" '{id: $p, dependency_type: "tracks", status: "open"}') ;;
            *) row=$(jq -nc --arg p "${row%%:*}" --arg s "${row#*:}" '{id: $p, dependency_type: "parent-child", status: $s}') ;;
        esac
        rows="$rows${rows:+,}$row"
    done
    printf '[{"id":"%s","status":"open","dependencies":[%s]}]' "$id" "$rows" >"$FIXDIR/$id.json"
}
# walk — run the script on tk-sub; prints its stdout, and leaves that stdout's
# byte count in $FIXDIR/bytes, its status in $FIXDIR/rc and the ids it read,
# space-separated, in $FIXDIR/read.
walk() {
    : >"$FIXDIR/reads"
    ( PATH="$BIN:$PATH" FIXDIR="$FIXDIR" SUBJECT=tk-sub bash "$SUT" >"$FIXDIR/out" 2>"$FIXDIR/stderr" )
    echo $? >"$FIXDIR/rc"
    wc -c <"$FIXDIR/out" | tr -d ' ' >"$FIXDIR/bytes"
    tr '\n' ' ' <"$FIXDIR/reads" | sed 's/ $//' >"$FIXDIR/read"
    cat "$FIXDIR/out"
}
fresh() { rm -f "$FIXDIR"/*.json; }

echo "── an open parent is the answer, read off the subject alone ──"
fresh; bead tk-sub tk-parent:open
is "an open parent is printed" "$(walk)" "tk-parent"
is "…from one read, the subject's" "$(cat "$FIXDIR/read")" "tk-sub"
fresh; bead tk-sub tk-parent:in_progress
is "a parent in progress is open" "$(walk)" "tk-parent"
fresh; bead tk-sub tracks:tk-x tk-p:open
is "the parent-child edge is picked out from among others" "$(walk)" "tk-p"

echo "── a closed parent is climbed past to the nearest open ancestor ──"
fresh; bead tk-sub tk-delivery:closed; bead tk-delivery tk-epic:open
is "a Story under a closed Delivery of an open epic gets the epic" "$(walk)" "tk-epic"
is "…reading the Story and the closed Delivery, never the epic" "$(cat "$FIXDIR/read")" "tk-sub tk-delivery"
fresh; bead tk-sub tk-a:closed; bead tk-a tk-b:closed; bead tk-b tk-c:open
is "the climb goes on through each closed level" "$(walk)" "tk-c"
fresh; bead tk-sub tk-convoy:closed tk-epic:open; bead tk-convoy tk-above:open
is "an open parent on the subject's own level wins over a bead above a closed one" "$(walk)" "tk-epic"
fresh; bead tk-sub tk-a:closed tk-b:closed; bead tk-a tk-a2:closed; bead tk-b tk-b2:open; bead tk-a2 tk-far:open
is "a level is read whole before the one above it" "$(walk)" "tk-b2"

echo "── no open ancestor is an empty line ──"
fresh; bead tk-sub
is "a subject with no parent gets an empty line" "$(walk)" ""
is "…one newline, not nothing" "$(cat "$FIXDIR/bytes")" "1"
is "…and exits 0" "$(cat "$FIXDIR/rc")" "0"
fresh; bead tk-sub tracks:tk-x
is "a tracks edge is not a parent" "$(walk)" ""
fresh; bead tk-sub tk-epic:closed; bead tk-epic
is "a Story under a closed epic with no open ancestor gets an empty line" "$(walk)" ""
is "…one newline, not nothing" "$(cat "$FIXDIR/bytes")" "1"
is "…and exits 0" "$(cat "$FIXDIR/rc")" "0"
fresh; bead tk-sub tk-a:closed; bead tk-a tk-b:closed; bead tk-b tk-a:closed
is "a loop of closed parents ends in an empty line" "$(walk)" ""
fresh; bead tk-sub tk-a:closed; bead tk-a tk-sub:open
is "a loop back to the subject never prints the subject" "$(walk)" ""

echo "── a bead that cannot be read is an error, not an empty answer ──"
fresh
is "an unreadable subject prints nothing" "$(walk)" ""
is "…not even an empty line" "$(cat "$FIXDIR/bytes")" "0"
is "…and exits 1" "$(cat "$FIXDIR/rc")" "1"
fresh; bead tk-sub tk-delivery:closed
is "an unreadable closed parent prints nothing" "$(walk)" ""
is "…not even an empty line" "$(cat "$FIXDIR/bytes")" "0"
is "…and exits 1" "$(cat "$FIXDIR/rc")" "1"
grep -q 'cannot read the parents of tk-delivery' "$FIXDIR/stderr" && ok "…naming the bead it could not read" \
    || bad "…naming the bead it could not read" "stderr: $(cat "$FIXDIR/stderr")"
fresh; printf '[{"id":"tk-other","dependencies":[{"id":"tk-p","dependency_type":"parent-child","status":"open"}]}]' >"$FIXDIR/tk-sub.json"
is "a show that answers for another bead prints nothing" "$(walk)" ""
is "…and exits 1" "$(cat "$FIXDIR/rc")" "1"
fresh; printf '[{"id":"tk-sub","dependencies":[{"id":"tk-p","dependency_type":"parent-child"}]}]' >"$FIXDIR/tk-sub.json"
is "a parent row with no status prints nothing" "$(walk)" ""
is "…and exits 1" "$(cat "$FIXDIR/rc")" "1"
fresh; printf 'not json' >"$FIXDIR/tk-sub.json"
is "a show that is not JSON prints nothing" "$(walk)" ""
is "…and exits 1" "$(cat "$FIXDIR/rc")" "1"

echo "── a subject id is required ──"
( PATH="$BIN:$PATH" FIXDIR="$FIXDIR" bash "$SUT" >/dev/null 2>&1 )
is "no subject exits 2" "$?" "2"

echo
echo "converse-parent: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
