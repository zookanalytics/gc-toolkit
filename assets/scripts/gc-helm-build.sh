#!/usr/bin/env bash
# gc-helm-build.sh — build the Helm backend binary, OUT OF BAND from the
# service. The only thing in the tree that builds helm-svc; the launcher
# (gc-helm-svc.sh) execs what this leaves behind and builds nothing — the
# supervisor gives a proxy_process 5s to answer its health probe, and this
# module builds in ~12.5s warm / 2m29s cold, so an in-start-path build is
# always killed mid-compile (2,677 stranded staging files proved it).
# Usage:
#   gc-helm-build.sh              build iff the binary is missing or stale
#   gc-helm-build.sh --deploy     order mode: skip cities without the helm
#                                 service; build iff stale; restart onto a
#                                 published binary not yet serving
# Staleness is an ordinary artifact-older-than-sources check (find -newer).
# Exit: 0 current and serving (or nothing to do) · 1 build/restart failed
# (the previous binary is left exactly as it was) · 2 usage.
# Env: GC_SERVICE_STATE_ROOT / GC_CITY_ROOT / GC_CITY (state root), GC_GO_BIN,
# GC_HELM_GOTMP, GC_HELM_SERVICE_NAME, GC_HELM_GC_BIN. Caller: orders/helm-build.
set -euo pipefail

DEPLOY=0
for arg in "$@"; do
    case "$arg" in
        --deploy) DEPLOY=1 ;;
        *) echo "gc-helm-build: unknown argument: $arg" >&2; exit 2 ;;
    esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOD="$(cd "$HERE/../../services/helm" && pwd)"
SERVICE_NAME="${GC_HELM_SERVICE_NAME:-helm}"
GC_BIN="${GC_HELM_GC_BIN:-gc}"

# One `gc service list` answers two questions: does this city run helm, and
# where is its state root (authoritative — beats reproducing
# StateRootOrDefault). Only a SUCCESSFUL listing that omits the service is
# proof of absence; an erroring one must not silently stop deploys.
SERVICES=""
if SERVICES="$("$GC_BIN" service list --json 2>/dev/null)"; then
    # jq -e: 1 = found nothing; anything else = jq could not run (not absent).
    set +e
    printf '%s' "$SERVICES" | jq -e --arg n "$SERVICE_NAME" \
        '[.services[]? | select((.service_name // .name) == $n)] | length > 0' >/dev/null 2>&1
    _q_rc=$?
    set -e
    if [ "$_q_rc" -eq 1 ]; then
        # This city does not run helm; a hand-run build is not gated.
        if [ "$DEPLOY" -eq 1 ]; then
            echo "gc-helm-build: no '$SERVICE_NAME' service in this city; nothing to deploy"
            exit 0
        fi
        SERVICES=""
    elif [ "$_q_rc" -ne 0 ]; then
        echo "gc-helm-build: could not read the service listing (jq exit $_q_rc); proceeding" >&2
        SERVICES=""
    fi
else
    SERVICES=""
    if [ "$DEPLOY" -eq 1 ]; then
        echo "gc-helm-build: could not list services; proceeding on the assumption '$SERVICE_NAME' is registered" >&2
    fi
fi

# State root: GC_SERVICE_STATE_ROOT wins, else the city's reported path,
# else derived (hand runs outside a live city).
STATE_ROOT=""
if [ -n "${GC_SERVICE_STATE_ROOT:-}" ]; then
    STATE_ROOT="$GC_SERVICE_STATE_ROOT"
elif [ -n "$SERVICES" ]; then
    _city="$(printf '%s' "$SERVICES" | jq -r '.city_path // empty' 2>/dev/null || true)"
    _root="$(printf '%s' "$SERVICES" | jq -r --arg n "$SERVICE_NAME" \
        'first(.services[]? | select((.service_name // .name) == $n) | .state_root // empty) // empty' 2>/dev/null || true)"
    case "$_root" in
        "")  ;;                              # nothing reported; fall through
        /*)  STATE_ROOT="$_root" ;;          # already absolute
        *)   [ -n "$_city" ] && STATE_ROOT="$_city/$_root" ;;
    esac
fi
if [ -n "$STATE_ROOT" ]; then
    :
elif [ -n "${GC_CITY_ROOT:-}" ]; then
    STATE_ROOT="$GC_CITY_ROOT/.gc/services/$SERVICE_NAME"
elif [ -n "${GC_CITY:-}" ]; then
    STATE_ROOT="$GC_CITY/.gc/services/$SERVICE_NAME"
else
    # Walk up from the module looking for the city runtime dir.
    probe="$MOD"
    while [ "$probe" != "/" ]; do
        if [ -d "$probe/.gc/services" ]; then
            STATE_ROOT="$probe/.gc/services/$SERVICE_NAME"
            break
        fi
        probe="$(dirname "$probe")"
    done
    if [ -z "$STATE_ROOT" ]; then
        echo "gc-helm-build: cannot locate the city runtime dir; set GC_SERVICE_STATE_ROOT or GC_CITY_ROOT" >&2
        exit 1
    fi
fi

BIN_DIR="$STATE_ROOT/bin"
BIN="$BIN_DIR/helm-svc"
mkdir -p "$BIN_DIR"

# Present while a published binary has nothing running on it; removed only
# by a restart that succeeded (see restart_service).
RESTART_PENDING="$STATE_ROOT/restart-pending"

# Go toolchain: override, PATH, then the conventional system install.
GO="${GC_GO_BIN:-}"
if [ -z "$GO" ]; then
    if command -v go >/dev/null 2>&1; then GO="go"; else GO="/usr/local/go/bin/go"; fi
fi

# Build inputs: *.go, go.mod/go.sum (explicit — `-name '*.go'` misses them,
# and a dependency-only bump must still rebuild, tk-ohdex), and web/dist
# (go:embed). node_modules pruned.
newer_than_binary() {
    find "$MOD" -name node_modules -prune -o \( -name '*.go' -o -name go.mod -o -name go.sum -o -path "$MOD/web/dist/*" \) -newer "$BIN" -print -quit 2>/dev/null
}

# Is the pid alive? Tells a live scratch dir from a stranded one.
pid_alive() {
    if [ -d /proc ]; then
        [ -e "/proc/$1" ]
    else
        kill -0 "$1" 2>/dev/null
    fi
}

# Restart onto the published binary; clear the pending marker only on
# success. "Published" and "serving" differ, and only the first is on disk:
# a failed restart leaves a binary newer than every source, so no later tick
# would ever be stale — the marker is what carries the unfinished restart to
# the next run.
restart_service() {
    echo "gc-helm-build: restarting service '$SERVICE_NAME'"
    if ! "$GC_BIN" service restart "$SERVICE_NAME"; then
        echo "gc-helm-build: 'gc service restart $SERVICE_NAME' failed; the new binary is published but not yet serving" >&2
        return 1
    fi
    # Only success clears it; a failed clear costs one redundant restart.
    rm -f -- "$RESTART_PENDING" 2>/dev/null \
        || echo "gc-helm-build: could not clear $RESTART_PENDING; the next run will restart again" >&2
    return 0
}

# Reclaim stranded staging files; an hour is far past the slowest build, so
# nothing in flight can be swept.
find "$BIN_DIR" -maxdepth 1 -type f -name '.helm-svc.build.*' -mmin +60 -delete 2>/dev/null || true

# Build when the binary is missing or any source file is newer than it.
need_build=0
if [ ! -x "$BIN" ]; then
    need_build=1
elif [ -n "$(newer_than_binary)" ]; then
    need_build=1
fi
if [ "$need_build" -eq 0 ]; then
    # Current is not serving: an unrestarted publish leaves its marker, and
    # this branch is the only one a later run can reach.
    if [ "$DEPLOY" -eq 1 ] && [ -e "$RESTART_PENDING" ]; then
        echo "gc-helm-build: $BIN is up to date but not yet serving; retrying the restart"
        restart_service || exit 1
        exit 0
    fi
    echo "gc-helm-build: $BIN is up to date"
    exit 0
fi

# Keep linker/cgo scratch off the size-capped shared /tmp; GOCACHE stays at
# its default (~/.cache/go-build) — it is what keeps rebuilds at ~12s.
GOTMP="${GC_HELM_GOTMP:-/var/tmp/gotmp}"
mkdir -p "$GOTMP"

# Bound $GOTMP (a killed build strands ~300MB per go-link dir on the root
# fs — 33G once, tk-m18ml): reclaim dead-pid run.<pid> dirs on sight, and
# anything else a day old. A concurrent build's scratch is fresh AND alive.
for gotmp_entry in "$GOTMP"/run.*; do
    [ -d "$gotmp_entry" ] || continue          # no match: the glob itself
    gotmp_pid="${gotmp_entry##*/run.}"
    case "$gotmp_pid" in ''|*[!0-9]*) continue ;; esac   # not pid-owned
    if pid_alive "$gotmp_pid"; then continue; fi
    rm -rf -- "$gotmp_entry" 2>/dev/null || true
done
find "$GOTMP" -mindepth 1 -maxdepth 1 -mmin +1440 -exec rm -rf -- {} + 2>/dev/null || true

# Build in scratch this invocation owns; every hygiene step degrades rather
# than fails (an unguarded mkdir under set -e would abort on the full disk
# where finishing matters most).
GOTMP_RUN="$GOTMP/run.$$"
GOTMP_RUN_OWNED=0
rm -rf -- "$GOTMP_RUN" 2>/dev/null || true   # a recycled pid inherits nothing
if mkdir "$GOTMP_RUN" 2>/dev/null; then
    GOTMP_RUN_OWNED=1
else
    echo "gc-helm-build: cannot create $GOTMP_RUN; building in $GOTMP" >&2
    GOTMP_RUN="$GOTMP"
fi

# One trap for every exit path: drop owned scratch (never the shared root on
# the degraded path) and the staging file.
cleanup() {
    [ "$GOTMP_RUN_OWNED" -eq 1 ] && rm -rf -- "$GOTMP_RUN" 2>/dev/null
    [ -n "${BIN_TMP:-}" ] && rm -f -- "$BIN_TMP" 2>/dev/null
    return 0
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

# Publish only via atomic rename from a scratch file beside $BIN: an
# in-place -o could truncate the live binary into a half-written file that
# still passes the launcher's -x test.
build_ok=0
BIN_TMP=""
echo "gc-helm-build: building $MOD -> $BIN"
if BIN_TMP="$(mktemp "$BIN_DIR/.helm-svc.build.XXXXXX" 2>/dev/null)"; then
    if ( cd "$MOD" && TMPDIR="$GOTMP_RUN" GOTMPDIR="$GOTMP_RUN" "$GO" build -o "$BIN_TMP" ./cmd/helm-svc ) && mv -f "$BIN_TMP" "$BIN"; then
        build_ok=1
        BIN_TMP=""      # renamed away; nothing left for cleanup to remove
    fi
fi

if [ "$build_ok" -eq 0 ]; then
    # $BIN was never touched; failing here costs a log line and a retry.
    echo "gc-helm-build: BUILD FAILED; $BIN left unchanged" >&2
    printf 'failed %s\n' "$(date -u +%FT%TZ)" > "$STATE_ROOT/build-status" 2>/dev/null || true
    exit 1
fi

printf 'ok %s\n' "$(date -u +%FT%TZ)" > "$STATE_ROOT/build-status" 2>/dev/null || true
echo "gc-helm-build: built $BIN"

# Record the unfinished half BEFORE the restart, so whatever stops this run
# leaves the evidence; it also carries a hand-run build to the next tick.
printf 'published %s\n' "$(date -u +%FT%TZ)" > "$RESTART_PENDING" 2>/dev/null \
    || echo "gc-helm-build: could not write $RESTART_PENDING; a failed restart will not be retried" >&2

# Build and restart are one step: a binary nothing restarts onto is inert.
if [ "$DEPLOY" -eq 1 ]; then
    restart_service || exit 1
fi
