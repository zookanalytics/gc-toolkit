#!/usr/bin/env bash
# gctk-resolve.sh — hand a bridge script's call to the gctk binary. Sourced,
# never executed.
#
# A script that only execs a gctk command sources this file beside itself and
# hands its arguments over ahead of anything else it does:
#   # shellcheck source=gctk-resolve.sh
#   . "$SCRIPTS_DIR/gctk-resolve.sh" || { echo "$PROG: cannot source gctk-resolve.sh" >&2; exit 1; }
#   gctk_require <subcommand> "$@"
#
# gctk_require execs `gctk <subcommand> "$@"` (lifecycle.sh, merge.sh, epic.sh).
# When there is no binary to run, it names what is missing and exits 1, so it
# never returns. GCTK_BIN=none names no binary and is refused like a missing
# one. A script that reads a command's answer and goes on (pr-open.sh,
# pr-stack.sh) asks gctk_path for the binary instead.
#
# Resolution is EXPLICIT: $GCTK_BIN, else the city named by GC_CITY_PATH,
# GC_CITY or GC_CITY_ROOT — the same precedence boot-health.sh, doctor-sweep.sh
# and the tmux session picker read, and GC_CITY_PATH is the one the supervisor puts in
# an agent session — else the city `gc service list --json` reports. The
# listing is what the merge cadence itself needs: the order runner that execs
# refinery-reconcile.sh carries no city variable at all (docs/
# refinery-merge-cadence.md), so an env-only chain would miss the binary on
# every order-driven call. Never a walk up from this file's own path — the
# hermetic suites run from a tree inside a live city, and a filesystem hunt
# would find that city's binary instead of the build a suite means to test.
#
# The binary is not compared against this checkout. There is no other
# implementation to prefer, so refusing a binary the build order has not yet
# replaced would turn the order's lag into a refusal of every call.
# doctor/check-cadence-live and the board's PACK row report that lag instead.
#
# The exec exports GCTK_SCRIPTS_DIR as this file's directory, which is the
# sibling scripts' directory: a subcommand that shells out to them (merge runs
# lane-state.sh, finalize-gate.sh, review-checks.sh, human-gate.sh,
# record-failure-cap.sh and render-seed-audit.sh) finds them there.

_gctk_resolve_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Sets _gctk_bin to the binary the chain names: $GCTK_BIN as given, none
# included, else the city's build path, else empty. Sets _gctk_city to the city
# that path came from, empty when $GCTK_BIN named the binary or no city was
# found. Whether the binary exists is the caller's question.
_gctk_locate() {
    _gctk_bin="${GCTK_BIN:-}"
    _gctk_city=""
    [ -z "$_gctk_bin" ] || return 0
    _gctk_city="${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-}}}"
    if [ -z "$_gctk_city" ]; then
        _gctk_city="$(gc service list --json 2>/dev/null | jq -r '.city_path // empty' 2>/dev/null || true)"
    fi
    [ -z "$_gctk_city" ] || _gctk_bin="$_gctk_city/.gc/services/gctk/bin/gctk"
    return 0
}

# gctk_path prints the binary the chain names, for a script that calls a gctk
# command and reads its answer rather than handing its process over. It prints
# nothing and returns 1 when the chain names no executable binary: GCTK_BIN=none,
# a path with no binary at it, or no city to look in.
gctk_path() {
    _gctk_locate
    if [ "$_gctk_bin" != "none" ] && [ -n "$_gctk_bin" ] && [ -x "$_gctk_bin" ]; then
        printf '%s\n' "$_gctk_bin"
        return 0
    fi
    return 1
}

gctk_require() { # <subcommand> [args...]
    local sub="$1"
    shift
    _gctk_locate
    if [ "$_gctk_bin" != "none" ] && [ -n "$_gctk_bin" ] && [ -x "$_gctk_bin" ]; then
        GCTK_SCRIPTS_DIR="$_gctk_resolve_dir" exec "$_gctk_bin" "$sub" "$@"
    fi
    # Nothing to exec. Each arm names what is missing, writes nothing, and exits
    # 1, the code every caller already reads as a refused call.
    if [ "${GCTK_BIN:-}" = "none" ]; then
        echo "$sub: GCTK_BIN=none names no binary, and gctk $sub is the only implementation; nothing was written" >&2
    elif [ -n "${GCTK_BIN:-}" ]; then
        echo "$sub: GCTK_BIN=$GCTK_BIN is not an executable gctk binary; nothing was written" >&2
    elif [ -z "$_gctk_city" ]; then
        echo "$sub: no city to find the gctk binary in — GC_CITY_PATH, GC_CITY and GC_CITY_ROOT are unset and \`gc service list --json\` named none. Set one of them, or GCTK_BIN; nothing was written" >&2
    else
        echo "$sub: no gctk binary at $_gctk_bin, so nothing was written. The gctk-build order (orders/gctk-build.toml) publishes it: a fresh city has one after the order's first build, $_gctk_city/.gc/services/gctk/build-status.json records why the last build failed, and assets/scripts/gc-build.sh gctk builds it now" >&2
    fi
    exit 1
}
