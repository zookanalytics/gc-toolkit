#!/usr/bin/env bash
# gc-gctk-build.sh — build the gctk binary, OUT OF BAND from every caller.
# The merge-cadence scripts exec whatever this leaves behind and build nothing:
# a build inside the cadence would put a Go toolchain in the path of a merge,
# and a failed one would take the cadence down with it. Here, a failed build
# leaves the LAST GOOD binary serving and costs a log line.
# Usage:
#   gc-gctk-build.sh              build iff the binary is missing or stale
#   gc-gctk-build.sh --deploy     order mode; same work, and the exit status
#                                 is what the order records
# Staleness has two axes: sources newer than the artifact (find -newer), and
# a recorded binary_rev other than the revision this run sees. Both are needed
# — find -newer is blind to an input a commit deleted.
# Exit: 0 current (or built) · 1 build failed (the previous binary is left
# exactly as it was) · 2 usage.
# Env: GC_SERVICE_STATE_ROOT / GC_CITY_PATH / GC_CITY / GC_CITY_ROOT (state
# root), else `gc service list --json`'s city_path; GC_GO_BIN, GC_GCTK_GOTMP,
# GC_GCTK_GC_BIN. Caller: orders/gctk-build.
#
# There is no restart step and no service: gctk is a command the cadence
# invokes, so a published binary is serving the moment it lands. restart_pending
# is therefore always false in the status record, and stays in the shape because
# the board reads one record format for every component.
set -euo pipefail

DEPLOY=0
for arg in "$@"; do
    case "$arg" in
        --deploy) DEPLOY=1 ;;
        *) echo "gc-gctk-build: unknown argument: $arg" >&2; exit 2 ;;
    esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOD="$(cd "$HERE/../../services/gctk" && pwd)"
COMPONENT="gctk"

# State root: the override wins, else the city runtime dir. gctk is not a
# service, so there is no service entry to read a state_root from — the city
# path is the whole question, and a run that cannot answer it refuses rather
# than guessing.
#
# The env chain is tried first, so a hand run publishes into the city its
# operator meant. It is not enough on its own: `gc supervisor run`, which
# spawns this order, carries no GC_CITY, GC_CITY_PATH or GC_CITY_ROOT at all,
# so a scheduled tick reaches the listing and nothing else. Answering that tick
# with "cannot locate the city" would leave the binary unpublished forever
# while every order arm reported the cadence healthy.
CITY_PATH="${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-}}}"
if [ -z "$CITY_PATH" ]; then
    CITY_PATH="$("${GC_GCTK_GC_BIN:-gc}" service list --json 2>/dev/null \
        | jq -r '.city_path // empty' 2>/dev/null || true)"
fi
if [ -n "${GC_SERVICE_STATE_ROOT:-}" ]; then
    STATE_ROOT="$GC_SERVICE_STATE_ROOT"
elif [ -n "$CITY_PATH" ]; then
    STATE_ROOT="$CITY_PATH/.gc/services/$COMPONENT"
else
    echo "gc-gctk-build: cannot locate the city runtime dir; set GC_SERVICE_STATE_ROOT or GC_CITY_PATH, or run where \`gc service list --json\` reports a city_path" >&2
    exit 1
fi

BIN_DIR="$STATE_ROOT/bin"
BIN="$BIN_DIR/gctk"
mkdir -p "$BIN_DIR"

# Go toolchain: override, PATH, then the conventional system install.
GO="${GC_GO_BIN:-}"
if [ -z "$GO" ]; then
    if command -v go >/dev/null 2>&1; then GO="go"; else GO="/usr/local/go/bin/go"; fi
fi

# The build-status record, in the same shape and the same place as every other
# compiled component's, so services/helm reads them all with one rule. See the
# marked block in gc-helm-build.sh for what each field carries.
STATUS="$STATE_ROOT/build-status.json"
SOURCE_REV="$(git -C "$MOD" rev-parse HEAD 2>/dev/null || true)"

prev_field() { # <key>
    [ -f "$STATUS" ] || return 0
    jq -r --arg k "$1" '(.[$k] // "") | tostring' "$STATUS" 2>/dev/null || true
}

write_status() { # <last_build_rc> <binary_rev> <built_at>
    local rc="$1" brev="$2" bat="$3" tmp
    tmp="$(mktemp "$STATE_ROOT/.build-status.XXXXXX" 2>/dev/null)" || return 0
    if jq -n --arg component "$COMPONENT" --arg built_at "$bat" \
        --arg source_rev "$SOURCE_REV" --arg binary_rev "$brev" \
        --argjson last_build_rc "$rc" \
        --arg checked_at "$(date -u +%FT%TZ)" \
        '{component: $component, built_at: $built_at, source_rev: $source_rev,
          binary_rev: $binary_rev, last_build_rc: $last_build_rc,
          restart_pending: false, checked_at: $checked_at}' \
        > "$tmp" 2>/dev/null; then
        mv -f "$tmp" "$STATUS" 2>/dev/null || rm -f -- "$tmp" 2>/dev/null
    else
        rm -f -- "$tmp" 2>/dev/null
    fi
    return 0
}

# Build inputs: *.go plus go.mod/go.sum, which `-name '*.go'` misses and a
# dependency bump must still rebuild.
newer_than_binary() {
    find "$MOD" \( -name '*.go' -o -name go.mod -o -name go.sum \) -newer "$BIN" -print -quit 2>/dev/null
}

pid_alive() {
    if [ -d /proc ]; then
        [ -e "/proc/$1" ]
    else
        kill -0 "$1" 2>/dev/null
    fi
}

# Reclaim stranded staging files; an hour is far past the slowest build here.
find "$BIN_DIR" -maxdepth 1 -type f -name '.gctk.build.*' -mmin +60 -delete 2>/dev/null || true

# `find -newer` cannot see a DELETED input: after a deletion-only commit
# nothing that remains is newer than the binary. binary_rev is the revision the
# binary was actually built from, so it is what separates a current binary from
# one the tree has moved past.
need_build=0
if [ ! -x "$BIN" ]; then
    need_build=1
elif [ -n "$(newer_than_binary)" ]; then
    need_build=1
elif [ -n "$SOURCE_REV" ] && [ "$(prev_field binary_rev)" != "$SOURCE_REV" ]; then
    need_build=1
fi
if [ "$need_build" -eq 0 ]; then
    # No input is newer and the record already names this revision, so the
    # binary IS this revision. built_at comes off its mtime when no earlier
    # record names it.
    CURRENT_BUILT_AT="$(prev_field built_at)"
    [ -n "$CURRENT_BUILT_AT" ] || CURRENT_BUILT_AT="$(date -u -r "$BIN" +%FT%TZ 2>/dev/null || true)"
    echo "gc-gctk-build: $BIN is up to date"
    write_status 0 "$SOURCE_REV" "$CURRENT_BUILT_AT"
    exit 0
fi

# Keep linker/cgo scratch off the size-capped shared /tmp; GOCACHE stays at its
# default, which is what keeps rebuilds fast.
GOTMP="${GC_GCTK_GOTMP:-/var/tmp/gotmp}"
mkdir -p "$GOTMP"

# Bound $GOTMP the way the helm builder does: reclaim dead-pid run.<pid> dirs on
# sight, and anything else a day old. A concurrent build's scratch is fresh AND
# alive, so nothing in flight is swept.
for gotmp_entry in "$GOTMP"/run.*; do
    [ -d "$gotmp_entry" ] || continue          # no match: the glob itself
    gotmp_pid="${gotmp_entry##*/run.}"
    case "$gotmp_pid" in ''|*[!0-9]*) continue ;; esac   # not pid-owned
    if pid_alive "$gotmp_pid"; then continue; fi
    rm -rf -- "$gotmp_entry" 2>/dev/null || true
done
find "$GOTMP" -mindepth 1 -maxdepth 1 -mmin +1440 -exec rm -rf -- {} + 2>/dev/null || true

GOTMP_RUN="$GOTMP/run.$$"
GOTMP_RUN_OWNED=0
rm -rf -- "$GOTMP_RUN" 2>/dev/null || true   # a recycled pid inherits nothing
if mkdir "$GOTMP_RUN" 2>/dev/null; then
    GOTMP_RUN_OWNED=1
else
    echo "gc-gctk-build: cannot create $GOTMP_RUN; building in $GOTMP" >&2
    GOTMP_RUN="$GOTMP"
fi

cleanup() {
    [ "$GOTMP_RUN_OWNED" -eq 1 ] && rm -rf -- "$GOTMP_RUN" 2>/dev/null
    [ -n "${BIN_TMP:-}" ] && rm -f -- "$BIN_TMP" 2>/dev/null
    return 0
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

# Publish only via atomic rename from a scratch file beside $BIN: an in-place
# -o could truncate the live binary into a half-written file that still passes
# the callers' -x test.
build_ok=0
BIN_TMP=""
echo "gc-gctk-build: building $MOD -> $BIN"
if BIN_TMP="$(mktemp "$BIN_DIR/.gctk.build.XXXXXX" 2>/dev/null)"; then
    if ( cd "$MOD" && TMPDIR="$GOTMP_RUN" GOTMPDIR="$GOTMP_RUN" "$GO" build -o "$BIN_TMP" ./cmd/gctk ) && chmod +x "$BIN_TMP" && mv -f "$BIN_TMP" "$BIN"; then
        build_ok=1
        BIN_TMP=""      # renamed away; nothing left for cleanup to remove
    fi
fi

if [ "$build_ok" -eq 0 ]; then
    # $BIN was never touched. The record keeps the last good revision, because
    # that is what the cadence is still running.
    echo "gc-gctk-build: BUILD FAILED; $BIN left unchanged" >&2
    write_status 1 "$(prev_field binary_rev)" "$(prev_field built_at)"
    exit 1
fi

echo "gc-gctk-build: built $BIN"
write_status 0 "$SOURCE_REV" "$(date -u +%FT%TZ)"
