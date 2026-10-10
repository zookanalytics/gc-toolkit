#!/usr/bin/env bash
# Hermetic test for assets/scripts/gctk-resolve.sh — the one place a ported
# script decides whether `gctk <subcommand>` or its own shell answers. Covers:
# the explicit GCTK_BIN (named, none, not executable); the city chain
# (GC_CITY_PATH, GC_CITY, GC_CITY_ROOT in that precedence, then
# `gc service list --json`); a named city with no binary; the skew guard that
# holds a city-resolved binary to this checkout's services/gctk tree (matched,
# skewed, unstamped, a hand build's commit stamp, -dirty); GCTK_FALLBACK, which
# forces only the subcommands it names onto their shell; arguments passed
# through verbatim; GCTK_SCRIPTS_DIR exported as the helper's directory; and
# gctk_require, which runs the same chain with no skew guard and no fallback:
# it execs the binary, or refuses with exit 1 and never returns to its script.
#
# The guard compares tree hashes, so this suite builds a scratch checkout with
# real git rather than sourcing test-harness.sh, whose stub git answers nothing.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-resolve-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"   # the assertion helpers only; no stubs are installed
PASS=0; FAIL=0

# --- a scratch checkout: the helper, a port that sources it, a services/gctk ---
REPO="$TMP/repo"
mkdir -p "$REPO/assets/scripts" "$REPO/services/gctk"
cp "$HERE/gctk-resolve.sh" "$REPO/assets/scripts/"
PORT="$REPO/assets/scripts/fake-port.sh"
cat > "$PORT" <<'PORT_SH'
#!/usr/bin/env bash
set -u
SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
. "$SCRIPTS_DIR/gctk-resolve.sh" || exit 1
gctk_resolve fakesub "$@"
printf 'SHELL-FALLBACK %s\n' "$*"
PORT_SH
chmod +x "$PORT"
# A port with no shell body: anything printed after gctk_require is a return.
REQ="$REPO/assets/scripts/fake-required.sh"
cat > "$REQ" <<'REQ_SH'
#!/usr/bin/env bash
set -u
SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
. "$SCRIPTS_DIR/gctk-resolve.sh" || exit 1
gctk_require fakereq "$@"
printf 'RETURNED %s\n' "$*"
REQ_SH
chmod +x "$REQ"
git -C "$REPO" init -q
git -C "$REPO" config user.name test
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config commit.gpgsign false
echo one > "$REPO/services/gctk/src.go"
git -C "$REPO" add -A && git -C "$REPO" commit -qm one
OLD_COMMIT=$(git -C "$REPO" rev-parse --verify -q HEAD)
echo two > "$REPO/services/gctk/src.go"
git -C "$REPO" add -A && git -C "$REPO" commit -qm two
NEW_COMMIT=$(git -C "$REPO" rev-parse --verify -q HEAD)
TREE=$(git -C "$REPO/services/gctk" rev-parse 'HEAD:./')
if [ -n "$OLD_COMMIT" ] && [ -n "$NEW_COMMIT" ] && [ -n "$TREE" ]; then
    ok "setup: a two-commit checkout whose services/gctk tree moved"
else
    bad "setup: the scratch checkout did not commit (old='$OLD_COMMIT' new='$NEW_COMMIT' tree='$TREE')"
fi

# A gctk stand-in: `version` answers FAKE_GCTK_VERSION (unknown by default, the
# stamp of a build with no recorded revision); anything else names itself.
mkgctk() { # <path> <label>
    mkdir -p "$(dirname "$1")"
    printf '#!/usr/bin/env bash\nif [ "${1:-}" = version ]; then printf "%%s\\n" "${FAKE_GCTK_VERSION:-unknown}"; exit 0; fi\nprintf "%s %%s dir=%%s\\n" "$*" "${GCTK_SCRIPTS_DIR:-}"\n' "$2" > "$1"
    chmod +x "$1"
}
CITY="$TMP/city"; OTHER="$TMP/other-city"; EMPTY_CITY="$TMP/empty-city"
mkgctk "$CITY/.gc/services/gctk/bin/gctk" GCTK
mkgctk "$OTHER/.gc/services/gctk/bin/gctk" OTHER-GCTK
mkdir -p "$EMPTY_CITY"
mkgctk "$TMP/named-gctk" NAMED-GCTK

# `gc service list --json` names FAKE_SERVICE_CITY, or no city at all.
mkdir -p "$TMP/bin"
printf '#!/usr/bin/env bash\nif [ "${1:-} ${2:-}" = "service list" ]; then\n  if [ -n "${FAKE_SERVICE_CITY:-}" ]; then printf "{\\"city_path\\":\\"%%s\\"}\\n" "$FAKE_SERVICE_CITY"; else echo "{}"; fi\n  exit 0\nfi\nexit 2\n' > "$TMP/bin/gc"
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH"

# Every case starts from no resolution input at all, whatever the ambient
# session exports, and passes an argument with a space in it.
run() { env -u GCTK_BIN -u GC_CITY_PATH -u GC_CITY -u GC_CITY_ROOT -u GCTK_SCRIPTS_DIR \
            -u GCTK_FALLBACK -u FAKE_SERVICE_CITY -u FAKE_GCTK_VERSION "$@" "$PORT" a "b c" 2>&1; }
runreq() { env -u GCTK_BIN -u GC_CITY_PATH -u GC_CITY -u GC_CITY_ROOT -u GCTK_SCRIPTS_DIR \
            -u GCTK_FALLBACK -u FAKE_SERVICE_CITY -u FAKE_GCTK_VERSION "$@" "$REQ" a "b c" 2>&1; }
SDIR="$REPO/assets/scripts"

echo "# an explicit GCTK_BIN"
out=$(run GCTK_BIN="$TMP/named-gctk")
eq "$out" "NAMED-GCTK fakesub a b c dir=$SDIR" "GCTK_BIN is exec'd with the subcommand, the arguments and GCTK_SCRIPTS_DIR"
out=$(env -u GCTK_BIN GCTK_BIN="$TMP/named-gctk" "$PORT" "b c" 2>/dev/null | wc -l | tr -d ' ')
eq "$out" "1" "…and the exec replaces the script, so its shell never runs after it"
out=$(run GCTK_BIN=none GC_CITY_PATH="$CITY")
eq "$out" "SHELL-FALLBACK a b c" "GCTK_BIN=none forces the shell even with a city named"
out=$(run GCTK_BIN="$TMP/does-not-exist" GC_CITY_PATH="$CITY")
eq "$out" "SHELL-FALLBACK a b c" "a GCTK_BIN that is not executable takes the shell, never the city's"
out=$(run GCTK_BIN="$TMP/named-gctk" FAKE_GCTK_VERSION="$OLD_COMMIT")
has "$out" "NAMED-GCTK fakesub" "an explicit GCTK_BIN is never held to the checkout"

echo "# the city chain"
for VAR in GC_CITY_PATH GC_CITY GC_CITY_ROOT; do
    out=$(run "$VAR=$CITY")
    eq "$out" "GCTK fakesub a b c dir=$SDIR" "$VAR alone resolves the city's binary"
done
out=$(run GC_CITY_PATH="$CITY" GC_CITY="$OTHER" GC_CITY_ROOT="$OTHER")
eq "$out" "GCTK fakesub a b c dir=$SDIR" "GC_CITY_PATH leads the chain, over GC_CITY and GC_CITY_ROOT"
out=$(run GC_CITY="$CITY" GC_CITY_ROOT="$OTHER")
eq "$out" "GCTK fakesub a b c dir=$SDIR" "GC_CITY outranks GC_CITY_ROOT"
out=$(run FAKE_SERVICE_CITY="$CITY")
eq "$out" "GCTK fakesub a b c dir=$SDIR" "with no city variable, the city gc service list names resolves"
out=$(run GC_CITY_PATH="$OTHER" FAKE_SERVICE_CITY="$CITY")
eq "$out" "OTHER-GCTK fakesub a b c dir=$SDIR" "a city variable outranks the service listing"
out=$(run)
eq "$out" "SHELL-FALLBACK a b c" "no city named anywhere: the shell answers"
out=$(run GC_CITY_PATH="$EMPTY_CITY")
eq "$out" "SHELL-FALLBACK a b c" "a named city with no binary built: the shell answers"

echo "# the skew guard: a city-resolved binary is held to this checkout"
out=$(run GC_CITY_PATH="$CITY" FAKE_GCTK_VERSION="$TREE")
eq "$out" "GCTK fakesub a b c dir=$SDIR" "a binary stamped with this checkout's services/gctk tree answers"
out=$(run GC_CITY_PATH="$CITY" FAKE_GCTK_VERSION=unknown)
eq "$out" "GCTK fakesub a b c dir=$SDIR" "an unstamped binary cannot be compared and is trusted"
out=$(run GC_CITY_PATH="$CITY" FAKE_GCTK_VERSION="$NEW_COMMIT")
eq "$out" "GCTK fakesub a b c dir=$SDIR" "a hand build stamped with a commit whose services/gctk is this tree answers"
out=$(run GC_CITY_PATH="$CITY" FAKE_GCTK_VERSION="$NEW_COMMIT-dirty")
eq "$out" "GCTK fakesub a b c dir=$SDIR" "…and so does that commit's -dirty stamp"
out=$(run GC_CITY_PATH="$CITY" FAKE_GCTK_VERSION="$OLD_COMMIT")
has "$out" "SHELL-FALLBACK a b c" "a build from a commit whose services/gctk differs takes the shell"
has "$out" "deployed gctk is built from $OLD_COMMIT, this checkout's services/gctk is at $TREE; using the shell fallback" "…and says which revisions disagree"
hasnt "$out" "GCTK fakesub" "…and the skewed binary does not run"
out=$(run GC_CITY_PATH="$CITY" FAKE_GCTK_VERSION=0000000000000000000000000000000000000000)
has "$out" "SHELL-FALLBACK a b c" "a stamp naming no object in this checkout takes the shell"

echo "# GCTK_FALLBACK: one port's shell, forced by name"
out=$(run GCTK_BIN="$TMP/named-gctk" GCTK_FALLBACK=fakesub)
eq "$out" "SHELL-FALLBACK a b c" "GCTK_FALLBACK naming the subcommand forces its shell over a named binary"
out=$(run GC_CITY_PATH="$CITY" FAKE_GCTK_VERSION="$TREE" GCTK_FALLBACK="other,fakesub")
eq "$out" "SHELL-FALLBACK a b c" "…and over a current city binary, named anywhere in a comma-separated list"
out=$(run GCTK_BIN="$TMP/named-gctk" GCTK_FALLBACK="other fakesubx fake")
eq "$out" "NAMED-GCTK fakesub a b c dir=$SDIR" "a list naming only other subcommands leaves this one on the binary"

echo "# gctk_require: the binary, or a refusal that never returns"
out=$(runreq GCTK_BIN="$TMP/named-gctk"); rc=$?
eq "$rc|$out" "0|NAMED-GCTK fakereq a b c dir=$SDIR" "GCTK_BIN is exec'd with the subcommand, the arguments and GCTK_SCRIPTS_DIR"
out=$(runreq FAKE_SERVICE_CITY="$CITY")
eq "$out" "GCTK fakereq a b c dir=$SDIR" "the same city chain resolves, down to gc service list"
out=$(runreq GC_CITY_PATH="$CITY" FAKE_GCTK_VERSION="$OLD_COMMIT")
eq "$out" "GCTK fakereq a b c dir=$SDIR" "a city binary built from another services/gctk revision still answers, with no warning"
out=$(runreq GCTK_BIN="$TMP/named-gctk" GCTK_FALLBACK=fakereq)
eq "$out" "NAMED-GCTK fakereq a b c dir=$SDIR" "GCTK_FALLBACK is not read: there is no shell to force"

out=$(runreq GCTK_BIN=none GC_CITY_PATH="$CITY"); rc=$?
eq "$rc" "1" "GCTK_BIN=none is refused with exit 1, even with a city named"
has "$out" "fakereq: GCTK_BIN=none names no binary, and gctk fakereq is the only implementation" "…naming why"
hasnt "$out" "RETURNED" "…and the script never runs past the call"
out=$(runreq GCTK_BIN="$TMP/does-not-exist" GC_CITY_PATH="$CITY"); rc=$?
eq "$rc" "1" "a GCTK_BIN that is not executable is refused, never replaced by the city's"
has "$out" "GCTK_BIN=$TMP/does-not-exist is not an executable gctk binary" "…naming the path it was given"
hasnt "$out" "GCTK fakereq" "…and the city's binary does not run"
out=$(runreq); rc=$?
eq "$rc" "1" "no city named anywhere is refused"
has "$out" "no city to find the gctk binary in" "…naming what is missing"
out=$(runreq GC_CITY_PATH="$EMPTY_CITY"); rc=$?
eq "$rc" "1" "a named city with no binary built is refused"
has "$out" "no gctk binary at $EMPTY_CITY/.gc/services/gctk/bin/gctk" "…naming where the binary belongs"
has "$out" "gctk-build order" "…and the order that publishes it"
has "$out" "$EMPTY_CITY/.gc/services/gctk/build-status.json" "…and the record of that order's last build"
hasnt "$out" "RETURNED" "…and the script never runs past the call"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
