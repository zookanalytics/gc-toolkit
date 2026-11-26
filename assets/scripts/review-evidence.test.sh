#!/usr/bin/env bash
# review-evidence.test.sh — what gctk rig recorded at the commit a review reads,
# as review-evidence.sh prints it for the review's gather.
#
#   - It reads each check's record with `gctk rig <check> --check`, in the
#     worktree --worktree names, from a caller in another checkout at another
#     commit, and prints a line per check: a pass or a fail with its scope,
#     exit code and command, nothing recorded, or a record gctk could not read.
#     The first line names the gctk binary.
#   - A fail's line adds what `gctk rig pre-existing <check> --bead <anchor>`,
#     asked in the worktree, prints of the anchor's mark, and a clause naming
#     the exit when it prints nothing and exits neither 0 nor 1. It asks only
#     when the record fails, once per failing check.
#   - No gctk binary prints that there is none and reads nothing.
#   - A worktree that is not at the commit, though the caller's checkout is, a
#     worktree that cannot be entered, and a call missing a value, an empty
#     --worktree included, print nothing and read nothing.
#   - A call that names no worktree reads the checkout it is made in.
#   - Its temp file is gone once it exits.
#
# Hermetic: a scratch git repository and a stub gctk; no city, no network.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/review-evidence.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-review-evidence-test.XXXXXX")" || exit 1
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "missing '$2' in: $1" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3" "unexpected '$2' in: $1" ;; *) ok "$3" ;; esac; }

command -v jq  >/dev/null 2>&1 || { echo "jq is required"  >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "git is required" >&2; exit 1; }

unset GC_PACK_DIR GC_RIG_ROOT GC_RIG GC_CITY GC_CITY_PATH GCTK_BIN GC_BD_LIB 2>/dev/null || true
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR 2>/dev/null || true
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# --- the scratch checkout ---------------------------------------------------------
# The reviewed commit, and a later one the checkout can be moved to.
REPO="$TMP/repo"; git init -q -b main "$REPO"
printf 'one\n' > "$REPO/f"; git -C "$REPO" add f; git -C "$REPO" commit -q -m reviewed
OID=$(git -C "$REPO" rev-parse HEAD)
printf 'two\n' > "$REPO/f"; git -C "$REPO" commit -q -am later
LATER=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" checkout -q --detach "$OID"
REPO_REAL=$(cd "$REPO" && pwd -P)
# The caller's directory: another worktree of the repository, at the later
# commit, so a read of the caller's checkout refuses the reviewed commit.
ELSEWHERE="$TMP/elsewhere"; git -C "$REPO" worktree add -q --detach "$ELSEWHERE" "$LATER"

# --- the stubs --------------------------------------------------------------------
# gctk answers `rig <check> --check` with STUB_REC_<check>, STUB_ERR_<check> on
# stderr and exit STUB_RC_<check> (default 3, nothing recorded), and
# `rig pre-existing <check>` with STUB_PRE_<check> on stdout, STUB_PRE_ERR on
# stderr and exit STUB_PRE_RC_<check> (default 1, no mark), logging each call
# and the directory it ran in.
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$TMP/gctk" <<'GCTK'
#!/usr/bin/env bash
printf 'gctk %s|%s\n' "$*" "$(pwd -P)" >> "$STUB_LOG"
if [ "$1 $2" = "rig pre-existing" ]; then
  out="STUB_PRE_$3"; rc="STUB_PRE_RC_$3"
  [ -z "${STUB_PRE_ERR:-}" ] || printf '%s\n' "$STUB_PRE_ERR" >&2
  [ -z "${!out:-}" ] || printf '%s\n' "${!out}"
  exit "${!rc:-1}"
fi
rec="STUB_REC_$2"; err="STUB_ERR_$2"; rc="STUB_RC_$2"
[ -z "${!err:-}" ] || printf '%s\n' "${!err}" >&2
[ -z "${!rec:-}" ] || printf '%s\n' "${!rec}"
exit "${!rc:-3}"
GCTK
chmod +x "$TMP/gctk"
export STUB_LOG="$TMP/stub.log"

# record <check> <pass|fail> [scope] : a record as gctk prints it at the
# reviewed commit.
record() {
  jq -nc --arg k "$1" --arg r "$2" --arg s "${3:-}" --arg c "$OID" \
    '{check: $k, result: $r, commit: $c, exit_code: (if $r == "pass" then 0 else 1 end), command: "run-the-\($k)s"} + (if $s == "" then {} else {scope: $s} end)'
}
# evidence [VAR=value...] : the script run from the caller's directory, reading
# the worktree WORKTREE names, by default the checkout at the reviewed commit,
# against the anchor tk-anchor1; stdout in OUT, stderr in ERR, status in RC, the
# run's temp dir in RUNTMP.
evidence() {
  : > "$STUB_LOG"; RC=0
  RUNTMP="$TMP/run.$RANDOM"; mkdir -p "$RUNTMP"
  OUT=$(cd "$ELSEWHERE" && env PATH="$BIN:$PATH" TMPDIR="$RUNTMP" GCTK_BIN="$TMP/gctk" "$@" \
    bash "$SUT" --anchor tk-anchor1 --commit "${COMMIT:-$OID}" --worktree "${WORKTREE:-$REPO}" 2>"$TMP/err") || RC=$?
  ERR=$(cat "$TMP/err")
}
line() { printf '%s\n' "$OUT" | grep "^$1: " | head -n 1; }
calls() { grep -c "^$1" "$STUB_LOG" 2>/dev/null || true; }

echo "# each check's record, read in the worktree at the reviewed commit, from another checkout"
evidence STUB_RC_test=0 STUB_REC_test="$(record test pass full)" STUB_RC_lint=0 STUB_REC_lint="$(record lint pass)"
eq "$RC" 0 "a read of the records exits 0"
eq "$(printf '%s\n' "$OUT" | head -n 1)" "gctk: $TMP/gctk" "the first line names the gctk binary the records were read with"
eq "$(line test)" "test: pass, scope full, exit 0, command: run-the-tests" "a full-suite pass prints its scope, exit code and command"
eq "$(line lint)" "lint: pass, exit 0, command: run-the-lints" "a record with no scope prints none"
eq "$(line typecheck)" "typecheck: nothing recorded" "a check with nothing recorded says so"
eq "$(printf '%s\n' "$OUT" | sed -n 's/^\([a-z]*\): .*/\1/p' | paste -sd' ' -)" "gctk test lint typecheck" "one line per check gctk rig records, in that order"
for c in test lint typecheck; do
  grep -qxF "gctk rig $c --check|$REPO_REAL" "$STUB_LOG" && ok "the $c record is read with --check, in the worktree --worktree names" \
    || bad "the $c record is read with --check, in the worktree --worktree names" "log: $(tr '\n' ';' < "$STUB_LOG")"
done
eq "$(calls 'gctk rig pre-existing')" 0 "with no fail, the anchor's mark is not asked about"
eq "$(find "$RUNTMP" -mindepth 1 | wc -l | tr -d ' ')" 0 "the run leaves no temp file behind"

evidence STUB_RC_test=0 STUB_REC_test="$(record test pass affected)"
eq "$(line test)" "test: pass, scope affected, exit 0, command: run-the-tests" "a pass of the affected subset prints scope affected"
evidence STUB_RC_test=0 STUB_REC_test="$(record test pass none)"
eq "$(line test)" "test: pass, scope none, exit 0, command: run-the-tests" "a pass that ran nothing prints scope none"

echo "# a fail, and the anchor's pre-existing mark"
FAILREC=$(record test fail affected)
FAILLINE="test: fail, scope affected, exit 1, command: run-the-tests"
evidence STUB_RC_test=1 STUB_REC_test="$FAILREC" STUB_PRE_RC_test=0 STUB_PRE_test="pre-existing, tracked by tk-t1"
eq "$(line test)" "$FAILLINE; pre-existing, tracked by tk-t1" "a fail whose mark holds is pre-existing, with its tracker"
grep -qxF "gctk rig pre-existing test --bead tk-anchor1|$REPO_REAL" "$STUB_LOG" && ok "…asked of the anchor, in the worktree" \
  || bad "…asked of the anchor, in the worktree" "log: $(tr '\n' ';' < "$STUB_LOG")"
WHY="the pre-existing mark on tk-anchor1 at $OID names no open tracker, so it judges nothing: tk-t1 is not open and no open bead carries its failure, so merge the base in"
evidence STUB_RC_test=1 STUB_REC_test="$FAILREC" STUB_PRE_test="$WHY"
eq "$(line test)" "$FAILLINE; $WHY" "a mark that does not hold adds why, and the fail is not called pre-existing"
evidence STUB_RC_test=1 STUB_REC_test="$FAILREC"
eq "$(line test)" "$FAILLINE" "a fail on an anchor with no mark is the commit's"
evidence STUB_RC_test=1 STUB_REC_test="$FAILREC" STUB_PRE_RC_test=4 STUB_PRE_test="tk-anchor1 did not read, so no pre-existing mark is known: the store did not answer"
eq "$(line test)" "$FAILLINE; tk-anchor1 did not read, so no pre-existing mark is known: the store did not answer" \
  "a mark that could not be read says so"
evidence STUB_RC_test=1 STUB_REC_test="$FAILREC" STUB_PRE_RC_test=2 STUB_PRE_ERR="Error: unknown command \"pre-existing\" for \"gctk rig\""
eq "$(line test)" "$FAILLINE; no pre-existing mark on tk-anchor1 was judged, as gctk rig pre-existing exited 2: Error: unknown command \"pre-existing\" for \"gctk rig\"" \
  "a gctk that cannot answer, such as one built before the verb, leaves the fail the commit's and says why"
LINTREC=$(record lint fail)
evidence STUB_RC_test=1 STUB_REC_test="$FAILREC" STUB_RC_lint=1 STUB_REC_lint="$LINTREC" STUB_PRE_RC_lint=0 STUB_PRE_lint="pre-existing, tracked by tk-l1"
eq "$(line lint)" "lint: fail, exit 1, command: run-the-lints; pre-existing, tracked by tk-l1" "a lint fail is judged by the answer about lint"
eq "$(line test)" "$FAILLINE" "…and the test fail beside it by its own"
eq "$(calls 'gctk rig pre-existing')" 2 "each failing check is asked about once"
COMMIT=${OID:0:12} evidence STUB_RC_test=0 STUB_REC_test="$(record test pass full)"
eq "$RC" 0 "an abbreviated commit is the checkout's commit"

echo "# a record gctk could not read"
evidence STUB_RC_test=4 STUB_ERR_test="gctk rig test: the record store did not answer"
eq "$(line test)" "test: unread, gctk rig test --check exited 4: gctk rig test: the record store did not answer" \
  "a machine failure is no record, and names gctk's reason"
evidence STUB_RC_test=0 STUB_REC_test="not json"
eq "$(line test)" "test: unread, gctk rig test --check exited 0 with no record it could parse" "a pass with no record to parse is no record"
eq "$(calls 'gctk rig pre-existing')" 0 "…and asks nothing of the anchor"

echo "# no gctk binary"
evidence GCTK_BIN="$TMP/no-gctk" STUB_RC_test=0 STUB_REC_test="$(record test pass full)"
eq "$RC" 0 "no binary exits 0"
eq "$OUT" "gctk: no binary at '$TMP/no-gctk' (GCTK_BIN, else the city's build, which its gctk-build order publishes), so no record can be read" \
  "no binary is said in one line, naming the binary looked for"
eq "$(calls 'gctk ')" 0 "…and nothing is read"
: > "$STUB_LOG"
OUT=$(cd "$ELSEWHERE" && env -u GCTK_BIN -u GC_CITY_PATH PATH="$BIN:$PATH" bash "$SUT" --anchor tk-anchor1 --commit "$OID" --worktree "$REPO" 2>/dev/null)
has "$OUT" "gctk: no binary at '/.gc/services/gctk/bin/gctk'" "with no GCTK_BIN and no city, it names a path no city holds"

echo "# a worktree at another commit, one that cannot be entered, and a call missing a value"
# The caller's checkout moves to the reviewed commit and the worktree away from
# it, so a read of the caller's checkout would pass where the worktree's refuses.
git -C "$REPO" checkout -q --detach "$LATER"
git -C "$ELSEWHERE" checkout -q --detach "$OID"
evidence STUB_RC_test=0 STUB_REC_test="$(record test pass full)"
eq "$RC" 1 "a worktree at another commit exits 1, though the caller's checkout is at the reviewed commit"
eq "$OUT" "" "…printing nothing"
has "$ERR" "the checkout at $REPO_REAL is at $LATER, not at $OID" "…and says which commit the worktree is at"
eq "$(calls 'gctk ')" 0 "…reading no record"
git -C "$REPO" checkout -q --detach "$OID"
git -C "$ELSEWHERE" checkout -q --detach "$LATER"
WORKTREE="$TMP/no-such-worktree" evidence STUB_RC_test=0 STUB_REC_test="$(record test pass full)"
eq "$RC" 1 "a worktree that does not exist exits 1"
eq "$OUT" "" "…printing nothing"
has "$ERR" "cannot enter the worktree $TMP/no-such-worktree" "…and says it could not enter it"
eq "$(calls 'gctk ')" 0 "…reading no record"
COMMIT=0000000000000000000000000000000000000000 evidence
eq "$RC" 1 "a commit the worktree cannot read exits 1"
for args in "--anchor tk-anchor1" "--commit $OID" "--anchor" "--anchor tk-anchor1 --commit $OID --worktree" "--anchor tk-anchor1 --commit $OID --other x"; do
  RC=0
  # shellcheck disable=SC2086  # each case is its own argument list
  OUT=$(cd "$REPO" && env PATH="$BIN:$PATH" GCTK_BIN="$TMP/gctk" bash "$SUT" $args 2>/dev/null) || RC=$?
  eq "$RC" 2 "usage: '$args' exits 2"
done
: > "$STUB_LOG"; RC=0
OUT=$(cd "$REPO" && env PATH="$BIN:$PATH" GCTK_BIN="$TMP/gctk" bash "$SUT" --anchor tk-anchor1 --commit "$OID" --worktree "" 2>"$TMP/err") || RC=$?
eq "$RC" 2 "an empty --worktree exits 2, though the caller's checkout is at the reviewed commit"
has "$(cat "$TMP/err")" "--worktree needs a path" "…and says the path is missing"
eq "$(calls 'gctk ')" 0 "…reading no record"

echo "# a call that names no worktree"
: > "$STUB_LOG"; RC=0
OUT=$(cd "$REPO" && env PATH="$BIN:$PATH" GCTK_BIN="$TMP/gctk" STUB_RC_test=0 STUB_REC_test="$(record test pass full)" \
  bash "$SUT" --anchor tk-anchor1 --commit "$OID" 2>/dev/null) || RC=$?
eq "$RC" 0 "a call with no --worktree, made in the checkout at the reviewed commit, exits 0"
eq "$(line test)" "test: pass, scope full, exit 0, command: run-the-tests" "…printing the records there"
grep -qxF "gctk rig test --check|$REPO_REAL" "$STUB_LOG" && ok "…read in the checkout the call is made in" \
  || bad "…read in the checkout the call is made in" "log: $(tr '\n' ';' < "$STUB_LOG")"
: > "$STUB_LOG"; RC=0
OUT=$(cd "$ELSEWHERE" && env PATH="$BIN:$PATH" GCTK_BIN="$TMP/gctk" bash "$SUT" --anchor tk-anchor1 --commit "$OID" 2>"$TMP/err") || RC=$?
eq "$RC" 1 "a call with no --worktree, made in a checkout at another commit, exits 1"
has "$(cat "$TMP/err")" "is at $LATER, not at $OID" "…and says which commit that checkout is at"
eq "$(calls 'gctk ')" 0 "…reading no record"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
