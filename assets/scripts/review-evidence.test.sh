#!/usr/bin/env bash
# review-evidence.test.sh — what gctk rig recorded at the commit a review reads,
# as review-evidence.sh prints it for the review's gather.
#
#   - It reads each check's record with `gctk rig <check> --check`, in the
#     worktree --worktree names, from a caller in another checkout at another
#     commit, and prints a line per check: a pass or a fail with its scope,
#     exit code and command, nothing recorded, or a record gctk could not read.
#     The first line names the gctk binary.
#   - A fail's line says it is pre-existing, with its trackers, only when the
#     anchor's rig_check_pre_existing.<check> holds that very record at the
#     commit. A mark for another run's record, a mark at another commit, an
#     anchor with no mark and an anchor that does not read leave the fail the
#     commit's. The anchor is read once, and only when some record fails.
#   - No gctk binary prints that there is none and reads nothing.
#   - A worktree that is not at the commit, though the caller's checkout is, a
#     worktree that cannot be entered, and a call missing a value, an empty
#     --worktree included, print nothing and read nothing.
#   - A call that names no worktree reads the checkout it is made in.
#   - Its temp file is gone once it exits.
#
# Hermetic: a scratch git repository, and stubs for gctk and gc's store; no
# city, no network.
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
# stderr and exit STUB_RC_<check> (default 3, nothing recorded), logging its
# call and the directory it ran in. gc answers `bd show` with STUB_ANCHOR, or
# fails when STUB_BD_FAIL is 1, logging every call.
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$TMP/gctk" <<'GCTK'
#!/usr/bin/env bash
printf 'gctk %s|%s\n' "$*" "$(pwd -P)" >> "$STUB_LOG"
rec="STUB_REC_$2"; err="STUB_ERR_$2"; rc="STUB_RC_$2"
[ -z "${!err:-}" ] || printf '%s\n' "${!err}" >&2
[ -z "${!rec:-}" ] || printf '%s\n' "${!rec}"
exit "${!rc:-3}"
GCTK
cat > "$BIN/gc" <<'GC'
#!/usr/bin/env bash
printf 'gc %s\n' "$*" >> "$STUB_LOG"
case "$1 ${2:-}" in
  "bd show") [ "${STUB_BD_FAIL:-0}" = 1 ] && exit 1; printf '%s\n' "$STUB_ANCHOR" ;;
  *) exit 1 ;;
esac
GC
chmod +x "$TMP/gctk" "$BIN/gc"
export STUB_LOG="$TMP/stub.log"
NO_MARK='[{"id":"tk-anchor1","metadata":{}}]'

# record <check> <pass|fail> [scope] : a record as gctk prints it at the
# reviewed commit.
record() {
  jq -nc --arg k "$1" --arg r "$2" --arg s "${3:-}" --arg c "$OID" \
    '{check: $k, result: $r, commit: $c, exit_code: (if $r == "pass" then 0 else 1 end), command: "run-the-\($k)s"} + (if $s == "" then {} else {scope: $s} end)'
}
# marked <check> <commit> <tracker> <record> : an anchor whose pre-existing mark
# for <check> holds <record> at <commit>.
marked() {
  jq -nc --arg k "rig_check_pre_existing.$1" --arg c "$2" --arg t "$3" --argjson r "$4" \
    '[{id: "tk-anchor1", metadata: {($k): ({commit: $c, record: $r, trackers: [$t]} | tojson)}}]'
}
# evidence [VAR=value...] : the script run from the caller's directory, reading
# the worktree WORKTREE names, by default the checkout at the reviewed commit,
# against the anchor tk-anchor1; stdout in OUT, stderr in ERR, status in RC, the
# run's temp dir in RUNTMP.
evidence() {
  : > "$STUB_LOG"; RC=0
  RUNTMP="$TMP/run.$RANDOM"; mkdir -p "$RUNTMP"
  OUT=$(cd "$ELSEWHERE" && env PATH="$BIN:$PATH" TMPDIR="$RUNTMP" GCTK_BIN="$TMP/gctk" STUB_ANCHOR="$NO_MARK" "$@" \
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
eq "$(calls 'gc ')" 0 "with no fail, the anchor is not read"
eq "$(find "$RUNTMP" -mindepth 1 | wc -l | tr -d ' ')" 0 "the run leaves no temp file behind"

evidence STUB_RC_test=0 STUB_REC_test="$(record test pass affected)"
eq "$(line test)" "test: pass, scope affected, exit 0, command: run-the-tests" "a pass of the affected subset prints scope affected"
evidence STUB_RC_test=0 STUB_REC_test="$(record test pass none)"
eq "$(line test)" "test: pass, scope none, exit 0, command: run-the-tests" "a pass that ran nothing prints scope none"

echo "# a fail, and the anchor's pre-existing mark"
FAILREC=$(record test fail affected)
evidence STUB_RC_test=1 STUB_REC_test="$FAILREC" STUB_ANCHOR="$(marked test "$OID" tk-t1 "$FAILREC")"
eq "$(line test)" "test: fail, scope affected, exit 1, command: run-the-tests; pre-existing, tracked by tk-t1" \
  "a fail the anchor's mark holds at the reviewed commit is pre-existing, with its tracker"
eq "$(calls 'gc bd show tk-anchor1')" 1 "…the anchor is read once"
evidence STUB_RC_test=1 STUB_REC_test="$(record test fail full)" STUB_ANCHOR="$(marked test "$OID" tk-t1 "$FAILREC")"
eq "$(line test)" "test: fail, scope full, exit 1, command: run-the-tests; the anchor's pre-existing mark at this commit judged another run's fail" \
  "a mark holding the record another run replaced does not answer for the fail"
evidence STUB_RC_test=1 STUB_REC_test="$FAILREC" STUB_ANCHOR="$(marked test "$LATER" tk-t1 "$FAILREC")"
eq "$(line test)" "test: fail, scope affected, exit 1, command: run-the-tests" "a mark at another commit does not answer for the reviewed one"
evidence STUB_RC_test=1 STUB_REC_test="$FAILREC"
eq "$(line test)" "test: fail, scope affected, exit 1, command: run-the-tests" "a fail on an anchor with no mark is the commit's"
evidence STUB_RC_test=1 STUB_REC_test="$FAILREC" STUB_ANCHOR="$(marked lint "$OID" tk-t1 "$FAILREC")"
eq "$(line test)" "test: fail, scope affected, exit 1, command: run-the-tests" "a mark for another check does not answer for this one"
evidence STUB_RC_test=1 STUB_REC_test="$FAILREC" STUB_BD_FAIL=1
eq "$(line test)" "test: fail, scope affected, exit 1, command: run-the-tests; the anchor tk-anchor1 did not read, so no pre-existing mark is known" \
  "a fail on an anchor that does not read is the commit's, and says why"
evidence STUB_RC_test=1 STUB_REC_test="$FAILREC" STUB_ANCHOR="$(marked test "$OID" tk-t1 "$FAILREC" | jq -c '.[0].id = "tk-other"')"
has "$(line test)" "did not read" "an answer for another bead is no read of the anchor"
LINTREC=$(record lint fail)
evidence STUB_RC_test=1 STUB_REC_test="$FAILREC" STUB_RC_lint=1 STUB_REC_lint="$LINTREC" STUB_ANCHOR="$(marked lint "$OID" tk-l1 "$LINTREC")"
eq "$(line lint)" "lint: fail, exit 1, command: run-the-lints; pre-existing, tracked by tk-l1" "a lint fail is judged by the anchor's lint mark"
eq "$(line test)" "test: fail, scope affected, exit 1, command: run-the-tests" "…and the test fail beside it by its own"
eq "$(calls 'gc bd show tk-anchor1')" 1 "two fails read the anchor once"
COMMIT=${OID:0:12} evidence STUB_RC_test=1 STUB_REC_test="$FAILREC" STUB_ANCHOR="$(marked test "$OID" tk-t1 "$FAILREC")"
eq "$RC" 0 "an abbreviated commit is the checkout's commit"
has "$(line test)" "pre-existing, tracked by tk-t1" "…and a mark naming the full sha answers for it"

echo "# a record gctk could not read"
evidence STUB_RC_test=4 STUB_ERR_test="gctk rig test: the record store did not answer"
eq "$(line test)" "test: unread, gctk rig test --check exited 4: gctk rig test: the record store did not answer" \
  "a machine failure is no record, and names gctk's reason"
evidence STUB_RC_test=0 STUB_REC_test="not json"
eq "$(line test)" "test: unread, gctk rig test --check exited 0 with no record it could parse" "a pass with no record to parse is no record"
eq "$(calls 'gc ')" 0 "…and reads no anchor"

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
