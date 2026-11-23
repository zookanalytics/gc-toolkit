#!/usr/bin/env bash
# test-floor.test.sh — tests for tools/test-floor.sh, the file every suite
# sources so the test floor sits beneath its stubs when it runs by itself.
#
# Hermetic: fixture suites, a canary and a scratch HOME in a temp dir. The
# canary stands in for the real gc, bd and gh: it sits behind the floor on PATH
# and logs each call it answers, so a call that reached the real tool there
# shows in its log. No live city, no store, no network.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/test-floor.sh" || exit 2
SUT="$HERE/test-floor.sh"
FLOOR="$HERE/test-floor"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-test-floor-test.XXXXXX")" || { echo "cannot allocate a tempdir"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

CANARY="$TMP/canary"; CANARY_LOG="$TMP/canary.log"
mkdir -p "$CANARY"
cat > "$CANARY/gc" <<EOF
#!/bin/sh
printf '%s %s\n' "\${0##*/}" "\$*" >> "$CANARY_LOG"
EOF
chmod +x "$CANARY/gc"
ln -s gc "$CANARY/bd"; ln -s gc "$CANARY/gh"
: > "$CANARY_LOG"

echo "# sourced, it puts the floor in front of the gc, bd and gh on PATH"
OUT="$(PATH="$CANARY:/usr/bin:/bin" "$BASH" -c '. "$1" || exit 2
for t in gc bd gh; do "$t" call one; echo "$t rc=$?"; done' _ "$SUT" 2>&1)"
for t in gc bd gh; do
  has "$OUT" "test-floor: refused '$t call one'" "$t is refused by the floor"
  has "$OUT" "$t rc=127" "…with the exit of a command that is not installed"
done
eq "$(cat "$CANARY_LOG")" "" "no call reaches the gc, bd or gh behind the floor"

echo "# a stub directory that goes mid-run hands the call to the floor"
# A suite run by itself writes a stub gc into its temp dir and puts that in
# front of PATH, as most suites do. The temp dir goes while a script it started
# still runs, and that script calls gc.
cat > "$TMP/fixture.test.sh" <<'EOF'
#!/usr/bin/env bash
set -u
[ -z "${ENTER_FLOOR:-}" ] || { . "$ENTER_FLOOR" || exit 2; }
STUBS="$FIXTURE_TMP/bin"; mkdir -p "$STUBS"
printf '#!/bin/sh\necho "stub answered $*"\n' > "$STUBS/gc"; chmod +x "$STUBS/gc"
export PATH="$STUBS:$PATH"
"$BASH" -c 'gc first'
rm -rf "$STUBS"
"$BASH" -c 'gc second; echo "second rc=$?"'
EOF
: > "$CANARY_LOG"
OUT="$(ENTER_FLOOR="$SUT" FIXTURE_TMP="$TMP/run-floor" PATH="$CANARY:$PATH" "$BASH" "$TMP/fixture.test.sh" 2>&1)"
has "$OUT" "stub answered first" "the stub answers while its directory stands"
has "$OUT" "test-floor: refused 'gc second'" "once it goes, the floor refuses the call"
has "$OUT" "second rc=127" "…and the script sees a command that is not installed"
eq "$(cat "$CANARY_LOG")" "" "the gc behind the floor is never reached"
: > "$CANARY_LOG"
OUT="$(env -u ENTER_FLOOR FIXTURE_TMP="$TMP/run-bare" PATH="$CANARY:$PATH" "$BASH" "$TMP/fixture.test.sh" 2>&1)"
eq "$(cat "$CANARY_LOG")" "gc second" "(premise) without the floor the same call reaches the gc behind the stubs"

echo "# a zsh the suite starts reads no startup file of the host user's"
eq "$(env -u ZDOTDIR "$BASH" -c '. "$1" || exit 2; printf %s "$ZDOTDIR"' _ "$SUT")" "$FLOOR" "ZDOTDIR names the floor"
eq "$(cd "$FLOOR" && printf '%s\n' .z* | grep -v -x -F '.z*')" "" "the floor holds no zsh startup file"
if ZSH_BIN="$(command -v zsh)"; then
  mkdir -p "$TMP/home"
  printf 'exit 7\n' > "$TMP/home/.zshenv"
  rc=0; env -u ZDOTDIR HOME="$TMP/home" "$ZSH_BIN" -c 'exit 0' || rc=$?
  eq "$rc" 7 "(premise) a plain zsh runs the .zshenv in its HOME"
  rc=0; env -u ZDOTDIR HOME="$TMP/home" "$BASH" -c '. "$1" || exit 2; "$2" -c "exit 0"' _ "$SUT" "$ZSH_BIN" || rc=$?
  eq "$rc" 0 "a plain zsh started after the floor does not run it"
else
  echo "skip - zsh not installed; the zsh runs are skipped"
fi

echo "# a tree without the floor does not run"
mkdir -p "$TMP/bare/tools"
cp "$SUT" "$TMP/bare/tools/test-floor.sh"
rc=0; OUT="$("$BASH" -c '. "$1"; echo "ran on"' _ "$TMP/bare/tools/test-floor.sh" 2>&1)" || rc=$?
eq "$rc" 2 "sourcing it there exits 2"
has "$OUT" "no test floor beside $TMP/bare/tools/test-floor.sh" "…and says which tree lacks the floor"
hasnt "$OUT" "ran on" "…and nothing after it runs"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
