#!/usr/bin/env bash
# Hermetic test for rig-root.sh: which path it prints for the rig a session
# works, or for a rig named on the command line, and that it prints nothing and
# exits 1 whenever no single path resolves, since an empty root lets
# `git -C ""` run in the cwd. A stub gc answers `rig list` from a roster file.
# No live city, store, or network.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/rig-root.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-rig-root-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "missing '$2' in: $1" ;; esac; }

[ -x "$SCRIPT" ] || { echo "rig-root.sh is missing or not executable" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }
unset GC_RIG_ROOT GC_RIG 2>/dev/null || true

mkdir -p "$TMP/bin"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
[ "$1 $2" = "rig list" ] || exit 0
[ -z "${FAKE_GC_FAILS:-}" ] || exit 1
cat "$FAKE_ROSTER"
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH"

# run <roster-json> <GC_RIG_ROOT> <GC_RIG> [<arg>...]: sets RC, OUT and ERR.
run() {
  printf '%s' "$1" > "$TMP/roster.json"
  local root="$2" rig="$3"; shift 3
  OUT=$(GC_RIG_ROOT="$root" GC_RIG="$rig" FAKE_ROSTER="$TMP/roster.json" "$SCRIPT" "$@" 2>"$TMP/err"); RC=$?
  ERR=$(cat "$TMP/err")
}
ROSTER='{"rigs":[{"name":"myrig","path":"/rigs/my"},{"name":"gascity","path":"/rigs/gascity"}]}'

echo "── the rig this session works ──"
run "$ROSTER" /from/env myrig
eq "$RC|$OUT" "0|/from/env" "GC_RIG_ROOT wins over the roster"
run "$ROSTER" "" myrig
eq "$RC|$OUT" "0|/rigs/my" "with GC_RIG_ROOT unset, the roster entry for GC_RIG"
run "$ROSTER" "" no-such-rig
eq "$RC|$OUT" "1|" "a GC_RIG the roster lacks prints nothing and exits 1"
has "$ERR" "GC_RIG_ROOT unset, and GC_RIG='no-such-rig' matched no rig in the roster" "and says which name matched nothing"
run "$ROSTER" "" ""
eq "$RC|$OUT" "1|" "with GC_RIG_ROOT and GC_RIG both unset, nothing resolves"
has "$ERR" "GC_RIG_ROOT and GC_RIG are both unset" "and says both are unset"

echo "── a rig named on the command line ──"
run "$ROSTER" /from/env myrig --rig gascity
eq "$RC|$OUT" "0|/rigs/gascity" "--rig reads the roster, whatever GC_RIG_ROOT says"
run "$ROSTER" /from/env myrig --rig nope
eq "$RC|$OUT" "1|" "--rig with a name the roster lacks prints nothing and exits 1"
has "$ERR" "'nope' matched no rig in the roster" "and names the rig"

echo "── a roster that does not name one path ──"
run '{"rigs":[{"name":"myrig","path":"/a"},{"name":"myrig","path":"/b"}]}' "" myrig
eq "$RC|$OUT" "1|" "two paths under one name resolve nothing"
has "$ERR" "matched more than one rig path" "and says the name is ambiguous"
run '{"rigs":[{"name":"myrig","path":"/a"},{"name":"myrig","path":"/a"}]}' "" myrig
eq "$RC|$OUT" "0|/a" "the same path listed twice is one path"
run '{"rigs":[{"name":"myrig","path":null}]}' "" myrig
eq "$RC|$OUT" "1|" "a null path is no path, never the string null"
run '{"rigs":[{"name":"myrig","path":""}]}' "" myrig
eq "$RC|$OUT" "1|" "an empty path is no path"
run '{"rigs":[{"name":"myrig"}]}' "" myrig
eq "$RC|$OUT" "1|" "an entry with no path is no path"
run '{"rigs":["junk",{"name":"myrig","path":"/a"}]}' "" myrig
eq "$RC|$OUT" "0|/a" "an entry that is not an object is skipped"
run "$(printf '{"rigs":[{"name":"myrig","path":"/a","description":"tab\there"}]}')" "" myrig
eq "$RC|$OUT" "0|/a" "a raw control byte in the roster does not cost the lookup"
run '' "" myrig
eq "$RC|$OUT" "1|" "an empty roster resolves nothing"
run 'not json' "" myrig
eq "$RC|$OUT" "1|" "an unreadable roster resolves nothing"
OUT=$(GC_RIG_ROOT="" GC_RIG=myrig FAKE_GC_FAILS=1 FAKE_ROSTER="$TMP/roster.json" "$SCRIPT" 2>/dev/null); RC=$?
eq "$RC|$OUT" "1|" "a gc that fails resolves nothing"

echo "── usage ──"
run "$ROSTER" /from/env myrig --rig
eq "$RC|$OUT" "2|" "--rig with no name is a usage error"
run "$ROSTER" /from/env myrig --rig ""
eq "$RC|$OUT" "2|" "--rig with an empty name is a usage error"
run "$ROSTER" /from/env myrig extra
eq "$RC|$OUT" "2|" "an unknown argument is a usage error"

echo "-----"
echo "rig-root: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
