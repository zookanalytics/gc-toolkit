#!/usr/bin/env bash
# gctk-resolve.sh — hand a ported script's call to the gctk binary. Sourced,
# never executed.
#
# A script whose subcommand gctk implements sources this file beside itself and
# hands its arguments over ahead of its own shell body:
#   # shellcheck source=gctk-resolve.sh
#   . "$SCRIPTS_DIR/gctk-resolve.sh" || { echo "$PROG: cannot source gctk-resolve.sh" >&2; exit 1; }
#   gctk_resolve <subcommand> "$@"
#
# gctk_resolve execs `gctk <subcommand> "$@"` when a usable binary resolves, so
# it returns only when none does, and the script's own shell answers instead.
# GCTK_BIN=none forces that shell.
#
# Resolution is EXPLICIT: $GCTK_BIN, else the city named by GC_CITY_PATH,
# GC_CITY or GC_CITY_ROOT — the same precedence boot-health.sh, doctor-sweep.sh
# and the tmux pickers read, and GC_CITY_PATH is the one the supervisor puts in
# an agent session — else the city `gc service list --json` reports. The
# listing is what the merge cadence itself needs: the order runner that execs
# refinery-reconcile.sh carries no city variable at all (docs/
# refinery-merge-cadence.md), so an env-only chain would leave every cadence
# call on the shell while the board reported the binary current. Never a walk
# up from this file's own path — the hermetic suites run from a tree inside a
# live city, and a filesystem hunt would find that city's binary and stop
# testing the shell.
#
# A binary the city resolved is also held to THIS checkout: `gctk version`
# carries the tree hash of services/gctk it was built from, and a checkout
# whose services/gctk is at another one — a rig ahead of the build order's ~5m
# lag, or a branch that changed the port — takes the script's shell, which is
# the writer that matches its callers. A hand build stamps the toolchain's
# commit (with -dirty for a modified tree) instead, and the subtree that commit
# holds is the comparable identity. A binary that cannot be compared (no stamp,
# no git) is trusted; an explicit $GCTK_BIN is never second-guessed.
#
# The exec exports GCTK_SCRIPTS_DIR as this file's directory, which is the
# sibling scripts' directory: a subcommand that shells out to them (merge runs
# lane-state.sh, finalize-gate.sh, escalate.sh, record-failure-cap.sh and
# render-seed-audit.sh) finds them there.

_gctk_resolve_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

gctk_resolve() { # <subcommand> [args...]
    local sub="$1" bin="${GCTK_BIN:-}" city mod want have mapped
    shift
    if [ -z "$bin" ]; then
        city="${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-}}}"
        if [ -z "$city" ]; then
            city="$(gc service list --json 2>/dev/null | jq -r '.city_path // empty' 2>/dev/null || true)"
        fi
        [ -n "$city" ] && bin="$city/.gc/services/gctk/bin/gctk"
        if [ -n "$bin" ] && [ -x "$bin" ]; then
            mod="$_gctk_resolve_dir/../../services/gctk"
            want="$(git -C "$mod" rev-parse 'HEAD:./' 2>/dev/null || true)"
            have="$("$bin" version 2>/dev/null | head -n 1 || true)"
            if [ -n "$want" ] && [ -n "$have" ] && [ "$have" != unknown ] && [ "$have" != "$want" ]; then
                mapped="$(git -C "$mod" rev-parse "${have%-dirty}:./" 2>/dev/null || true)"
                if [ "$mapped" != "$want" ]; then
                    echo "$0: deployed gctk is built from $have, this checkout's services/gctk is at $want; using the shell fallback" >&2
                    return 0
                fi
            fi
        fi
    fi
    if [ "$bin" != "none" ] && [ -n "$bin" ] && [ -x "$bin" ]; then
        GCTK_SCRIPTS_DIR="$_gctk_resolve_dir" exec "$bin" "$sub" "$@"
    fi
    return 0
}
