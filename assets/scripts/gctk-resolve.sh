#!/usr/bin/env bash
# gctk-resolve.sh — hand a ported script's call to the gctk binary. Sourced,
# never executed.
#
# A script whose subcommand gctk implements sources this file beside itself and
# hands its arguments over ahead of anything else it does, by one of two calls:
#   # shellcheck source=gctk-resolve.sh
#   . "$SCRIPTS_DIR/gctk-resolve.sh" || { echo "$PROG: cannot source gctk-resolve.sh" >&2; exit 1; }
#   gctk_resolve <subcommand> "$@"   # the script still carries a shell body
#   gctk_require <subcommand> "$@"   # the binary is the only implementation
#
# gctk_resolve execs `gctk <subcommand> "$@"` when a usable binary resolves, so
# it returns only when none does, and the script's own shell answers instead.
# GCTK_BIN=none forces that shell. GCTK_FALLBACK forces it for the subcommands
# it names (space- or comma-separated) and leaves the binary serving every
# other call. A suite drives merge.sh's shell that way, because that shell
# records every landing through lifecycle.sh, which needs the binary.
#
# gctk_require is for a script that is only the exec (lifecycle.sh). It execs
# the binary the same chain resolves. When there is none, it names what is
# missing and exits 1, so it never returns. GCTK_BIN=none names no binary and is
# refused like a missing one. GCTK_FALLBACK is not read, because there is no
# shell to fall back to.
#
# Resolution is EXPLICIT: $GCTK_BIN, else the city named by GC_CITY_PATH,
# GC_CITY or GC_CITY_ROOT — the same precedence boot-health.sh, doctor-sweep.sh
# and the tmux pickers read, and GC_CITY_PATH is the one the supervisor puts in
# an agent session — else the city `gc service list --json` reports. The
# listing is what the merge cadence itself needs: the order runner that execs
# refinery-reconcile.sh carries no city variable at all (docs/
# refinery-merge-cadence.md), so an env-only chain would miss the binary on
# every order-driven call. Never a walk up from this file's own path — the
# hermetic suites run from a tree inside a live city, and a filesystem hunt
# would find that city's binary instead of the shell or the build a suite
# means to test.
#
# gctk_resolve also holds a binary the city resolved to THIS checkout: `gctk
# version` carries the tree hash of services/gctk it was built from, and a
# checkout whose services/gctk is at another one — a rig ahead of the build
# order's ~5m lag, or a branch that changed the port — takes the script's
# shell, which is the writer that matches its callers. A hand build stamps the
# toolchain's commit (with -dirty for a modified tree) instead, and the subtree
# that commit holds is the comparable identity. A binary that cannot be
# compared (no stamp, no git) is trusted; an explicit $GCTK_BIN is never
# second-guessed. gctk_require makes no such comparison. There is no other
# implementation to prefer, so refusing a binary the build order has not yet
# replaced would turn the order's lag into a refusal of every call.
# doctor/check-cadence-live and the board's PACK row report that lag instead.
#
# The exec exports GCTK_SCRIPTS_DIR as this file's directory, which is the
# sibling scripts' directory: a subcommand that shells out to them (merge runs
# lane-state.sh, finalize-gate.sh, review-checks.sh, escalate.sh,
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

gctk_resolve() { # <subcommand> [args...]
    local sub="$1" forced="${GCTK_FALLBACK:-}" mod want have mapped
    shift
    case " ${forced//,/ } " in *" $sub "*) return 0 ;; esac
    _gctk_locate
    if [ -n "$_gctk_city" ] && [ -x "$_gctk_bin" ]; then
        mod="$_gctk_resolve_dir/../../services/gctk"
        want="$(git -C "$mod" rev-parse 'HEAD:./' 2>/dev/null || true)"
        have="$("$_gctk_bin" version 2>/dev/null | head -n 1 || true)"
        if [ -n "$want" ] && [ -n "$have" ] && [ "$have" != unknown ] && [ "$have" != "$want" ]; then
            mapped="$(git -C "$mod" rev-parse "${have%-dirty}:./" 2>/dev/null || true)"
            if [ "$mapped" != "$want" ]; then
                echo "$0: deployed gctk is built from $have, this checkout's services/gctk is at $want; using the shell fallback" >&2
                return 0
            fi
        fi
    fi
    if [ "$_gctk_bin" != "none" ] && [ -n "$_gctk_bin" ] && [ -x "$_gctk_bin" ]; then
        GCTK_SCRIPTS_DIR="$_gctk_resolve_dir" exec "$_gctk_bin" "$sub" "$@"
    fi
    return 0
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
        echo "$sub: no gctk binary at $_gctk_bin, so nothing was written. The gctk-build order (orders/gctk-build.toml) publishes it: a fresh city has one after the order's first build, $_gctk_city/.gc/services/gctk/build-status.json records why the last build failed, and assets/scripts/gc-gctk-build.sh builds it now" >&2
    fi
    exit 1
}
