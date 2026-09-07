#!/usr/bin/env bash
# converse-parent.test.sh — reading a subject's OWN parent off its bead
# (assets/scripts/converse-parent.sh), so a sitting files siblings, not children.
# A parent-child edge is stored on the child, so it is read from the subject's
# dependencies; the reader tolerates both edge shapes (type / dependency_type,
# id / depends_on_id) and prints an empty line for a rootless subject.
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

cat >"$BIN/gc" <<'STUB'
#!/usr/bin/env bash
[ "${1:-}" = "bd" ] && [ "${2:-}" = "show" ] || exit 2
cat "$FIXDIR/subject.json"
STUB
chmod +x "$BIN/gc"

echo "── the script is shipped executable and syntactically valid ──"
[ -x "$SUT" ] && ok "converse-parent.sh is executable" || bad "converse-parent.sh is executable" "chmod +x it"
bash -n "$SUT" && ok "converse-parent.sh: valid bash" || bad "converse-parent.sh: valid bash" "bash -n failed"

# parent_of <subject-json> — write the fixture, run the script, print its output.
parent_of() {
    printf '%s' "$1" >"$FIXDIR/subject.json"
    ( PATH="$BIN:$PATH" FIXDIR="$FIXDIR" SUBJECT=tk-sub bash "$SUT" )
}

echo "── a parent-child edge yields the parent id ──"
is "the parent is read off the parent-child dependency" \
   "$(parent_of '[{"id":"tk-sub","dependencies":[{"id":"tk-parent","dependency_type":"parent-child"}]}]')" \
   "tk-parent"
is "the alternate edge shape (type / depends_on_id) resolves too" \
   "$(parent_of '[{"id":"tk-sub","dependencies":[{"depends_on_id":"tk-parent2","type":"parent-child"}]}]')" \
   "tk-parent2"

echo "── a rootless or non-parent edge yields an empty line ──"
is "a subject with no dependencies has no parent" \
   "$(parent_of '[{"id":"tk-sub","dependencies":[]}]')" ""
is "a tracks edge is not a parent" \
   "$(parent_of '[{"id":"tk-sub","dependencies":[{"id":"tk-x","dependency_type":"tracks"}]}]')" ""
is "the parent-child edge is picked out from among others" \
   "$(parent_of '[{"id":"tk-sub","dependencies":[{"id":"tk-x","dependency_type":"tracks"},{"id":"tk-p","dependency_type":"parent-child"}]}]')" \
   "tk-p"

echo "── a subject id is required ──"
( PATH="$BIN:$PATH" FIXDIR="$FIXDIR" bash "$SUT" >/dev/null 2>&1 )
is "no subject exits non-zero" "$?" "2"

echo
echo "converse-parent: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
