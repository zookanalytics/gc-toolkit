#!/usr/bin/env bash
# Hermetic test for review-file-bug.sh: an out-of-scope review finding is filed
# once, keyed on its token, and an unreadable store files nothing.
#
# What it holds:
#   1. FILE — no open bug carries the token: one bug is created, its title
#      carrying the token and its body the reviewed branch and commit.
#   2. DEDUP — an open bug carries the token: its id is printed and nothing is
#      created, so a re-review of the same page files no second bug.
#   3. FAIL CLOSED — an unreadable probe, and a create that returns no id, each
#      print "unfiled" with the reason and exit 1, creating nothing blind.
#   4. USAGE — a missing option refuses with exit 2 and touches nothing.
#
# Fakes gc; no city, Dolt, or network.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/review-file-bug.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-review-file-bug-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3" "got '$1' want '$2'"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "'$2' not in '$1'" ;; esac; }

[ -x "$SUT" ] || { echo "not executable: $SUT" >&2; exit 1; }

# gc : `bd list` prints $FAKE_LIST (the probe's answer) and records its argv;
#      `bd create` prints $FAKE_CREATE and records its argv.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "bd list")   shift 2; printf 'LIST %s\n' "$*" >> "$FAKE_LOG"; printf '%s' "${FAKE_LIST-[]}"; exit 0 ;;
  "bd create") shift 2; printf 'CREATE %s\n' "$*" >> "$FAKE_LOG"; printf '%s' "${FAKE_CREATE-}"; exit 0 ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH" FAKE_LOG="$TMP/log"

ARGS=(--token "PR #7 body / ## Summary: placeholder" --title "The summary is a placeholder" --body "It says nothing about the diff." --branch polecat/tk-x --oid abc123)

# run [args...] -> "<rc>|<stdout>"; the gc calls are left in $FAKE_LOG.
run() {
  : > "$FAKE_LOG"
  local rc=0 out
  out="$("$SUT" "$@" 2>/dev/null)" || rc=$?
  printf '%s|%s' "$rc" "$out"
}

# --- 1. File. -----------------------------------------------------------------
eq "$(FAKE_LIST='[]' FAKE_CREATE='{"id":"tk-new"}' run "${ARGS[@]}")" "0|tk-new" \
   "no open bug carries the token: files one and prints its id"
has "$(grep '^LIST ' "$FAKE_LOG")" "--type=bug --title-contains PR #7 body / ## Summary: placeholder --json" \
   "the probe asks for open bugs whose title carries the token"
has "$(grep '^CREATE ' "$FAKE_LOG")" "--title=The summary is a placeholder (PR #7 body / ## Summary: placeholder)" \
   "the filed title carries the token in parentheses, where the next probe looks"
has "$(cat "$FAKE_LOG")" "Found reviewing polecat/tk-x at abc123; out of scope for that diff." \
   "the body names the reviewed branch and commit"
eq "$(FAKE_LIST='[]' FAKE_CREATE='[{"id":"tk-arr"}]' run "${ARGS[@]}")" "0|tk-arr" \
   "an array-shaped create answer still yields the id"

# --- 2. Dedup. ----------------------------------------------------------------
eq "$(FAKE_LIST='[{"id":"tk-open"}]' run "${ARGS[@]}")" "0|tk-open" \
   "an open bug carries the token: prints its id"
eq "$(grep -c '^CREATE ' "$FAKE_LOG")" "0" "and creates nothing"

# --- 3. Fail closed. ----------------------------------------------------------
eq "$(FAKE_LIST='' run "${ARGS[@]}")" "1|unfiled — duplicate probe unreadable" \
   "an empty probe answer is unreadable, not 'no match': files nothing"
eq "$(grep -c '^CREATE ' "$FAKE_LOG")" "0" "and creates nothing blind"
eq "$(FAKE_LIST='{"error":"db locked"}' run "${ARGS[@]}")" "1|unfiled — duplicate probe unreadable" \
   "an object-shaped probe answer is unreadable too"
eq "$(FAKE_LIST='[]' FAKE_CREATE='{"error":"refused"}' run "${ARGS[@]}")" "1|unfiled — bd create returned no id: refused" \
   "a create that returns no id says so, with bd's error"
eq "$(FAKE_LIST='[]' FAKE_CREATE='' run "${ARGS[@]}")" "1|unfiled — bd create returned no id" \
   "a create that returns nothing says so"

# --- 4. Usage. ----------------------------------------------------------------
eq "$(run --token t --title x --body y --branch b)" "2|" "a missing --oid refuses as usage"
eq "$(cat "$FAKE_LOG")" "" "and runs no gc call"
eq "$(run "${ARGS[@]}" --bogus x)" "2|" "an unknown option refuses as usage"

echo
echo "review-file-bug: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
