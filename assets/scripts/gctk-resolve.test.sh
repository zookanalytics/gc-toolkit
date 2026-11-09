#!/usr/bin/env bash
# Hermetic test for assets/scripts/gctk-resolve.sh — how a bridge script hands
# its call to `gctk <subcommand>`. Covers: the explicit GCTK_BIN (named, none,
# not executable); the city chain (GC_CITY_PATH, GC_CITY, GC_CITY_ROOT in that
# precedence, then `gc service list --json`); a named city with no binary;
# arguments passed through verbatim; GCTK_SCRIPTS_DIR exported as the helper's
# directory; the refusal with exit 1 that never returns to its script; and a
# binary built from this checkout, which answers `gctk_require rig` with its own
# subcommand, since the helper hands any subcommand over unread.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-resolve-test.XXXXXX")"
# gctk-resolve.sh exports its own directory, named through cd and pwd, as
# GCTK_SCRIPTS_DIR. cd and pwd drop the doubled slash that a TMPDIR ending in /
# leaves in mktemp's path, so TMP is resolved before any expected path is built.
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"   # the assertion helpers only; no stubs are installed
PASS=0; FAIL=0

# --- a scratch checkout: the helper and a bridge that sources it ---
REPO="$TMP/repo"
mkdir -p "$REPO/assets/scripts"
cp "$HERE/gctk-resolve.sh" "$REPO/assets/scripts/"
# A bridge: anything printed after gctk_require is a return.
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

# A gctk stand-in, which names itself, its arguments and GCTK_SCRIPTS_DIR.
mkgctk() { # <path> <label>
    mkdir -p "$(dirname "$1")"
    printf '#!/usr/bin/env bash\nprintf "%s %%s dir=%%s\\n" "$*" "${GCTK_SCRIPTS_DIR:-}"\n' "$2" > "$1"
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
runreq() { env -u GCTK_BIN -u GC_CITY_PATH -u GC_CITY -u GC_CITY_ROOT -u GCTK_SCRIPTS_DIR \
            -u FAKE_SERVICE_CITY "$@" "$REQ" a "b c" 2>&1; }
SDIR="$REPO/assets/scripts"

echo "# an explicit GCTK_BIN"
out=$(runreq GCTK_BIN="$TMP/named-gctk"); rc=$?
eq "$rc|$out" "0|NAMED-GCTK fakereq a b c dir=$SDIR" "GCTK_BIN is exec'd with the subcommand, the arguments and GCTK_SCRIPTS_DIR"
out=$(env -u GCTK_BIN GCTK_BIN="$TMP/named-gctk" "$REQ" "b c" 2>/dev/null | wc -l | tr -d ' ')
eq "$out" "1" "…and the exec replaces the script, so nothing after the call runs"

echo "# the city chain"
for VAR in GC_CITY_PATH GC_CITY GC_CITY_ROOT; do
    out=$(runreq "$VAR=$CITY")
    eq "$out" "GCTK fakereq a b c dir=$SDIR" "$VAR alone resolves the city's binary"
done
out=$(runreq GC_CITY_PATH="$CITY" GC_CITY="$OTHER" GC_CITY_ROOT="$OTHER")
eq "$out" "GCTK fakereq a b c dir=$SDIR" "GC_CITY_PATH leads the chain, over GC_CITY and GC_CITY_ROOT"
out=$(runreq GC_CITY="$CITY" GC_CITY_ROOT="$OTHER")
eq "$out" "GCTK fakereq a b c dir=$SDIR" "GC_CITY outranks GC_CITY_ROOT"
out=$(runreq FAKE_SERVICE_CITY="$CITY")
eq "$out" "GCTK fakereq a b c dir=$SDIR" "with no city variable, the city gc service list names resolves"
out=$(runreq GC_CITY_PATH="$OTHER" FAKE_SERVICE_CITY="$CITY")
eq "$out" "OTHER-GCTK fakereq a b c dir=$SDIR" "a city variable outranks the service listing"

echo "# a refusal that never returns"
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

echo "# gctk_require rig: the real binary's subcommand, reached unchanged"
harness_build_gctk
if [ -n "$GCTK_BUILT" ]; then
    RIGREQ="$REPO/assets/scripts/fake-rig.sh"
    cat > "$RIGREQ" <<'RIG_SH'
#!/usr/bin/env bash
set -u
SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
. "$SCRIPTS_DIR/gctk-resolve.sh" || exit 1
gctk_require rig "$@"
printf 'RETURNED %s\n' "$*"
RIG_SH
    chmod +x "$RIGREQ"
    # --check needs no command and reads only git and the record store, so a
    # clean clone with no record answers it.
    CLONE="$TMP/clean-clone"
    git init -q "$CLONE"
    git -C "$CLONE" -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false \
        commit -q --allow-empty -m one
    out=$(cd "$CLONE" && GCTK_BIN="$GCTK_BUILT" "$RIGREQ" test --check 2>&1); rc=$?
    eq "$rc" "3" "gctk_require rig test --check reaches the built binary's rig: nothing is recorded, exit 3"
    has "$out" "gctk rig test: nothing is recorded at $(git -C "$CLONE" rev-parse HEAD)" "…which names the commit it read"
    hasnt "$out" "RETURNED" "…and the script never runs past the call"
    out=$(cd "$CLONE" && GCTK_BIN="$GCTK_BUILT" "$RIGREQ" deploy 2>&1); rc=$?
    eq "$rc" "2" "a verb rig does not know is the binary's usage error, exit 2"
else
    bad "${GCTK_BUILD_ERR:-gctk was not built}"
fi

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
