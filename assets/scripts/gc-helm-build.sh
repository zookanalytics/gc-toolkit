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
# Staleness has TWO axes. Sources newer than the artifact (find -newer) is the
# ordinary one. The other is the binary's ability to READ the stores it serves:
# that is fixed by the beads library it embedded at build time, while the store
# schema moves under it on a `bd` upgrade, so a binary can be newer than every
# source and still fail every gather. `helm-svc probe` is the binary's own
# answer, and this gate will not report ok without it.
# Exit: 0 current and serving (or nothing to do) · 1 build/restart failed
# (the previous binary is left exactly as it was), or the published binary
# cannot read the city's bead stores · 2 usage.
# build-status: `ok <ts>` built/current AND probed readable · `unreadable <ts>
# <why>` · `unprobed <ts>` no city to probe against · `failed <ts>`.
# Env: GC_SERVICE_STATE_ROOT / GC_CITY_ROOT / GC_CITY (state root), GC_GO_BIN,
# GC_HELM_GOTMP, GC_HELM_SERVICE_NAME, GC_HELM_GC_BIN,
# GC_HELM_BUILD_PROBE_TIMEOUT (seconds, default 60). Caller: orders/helm-build.
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

# The city whose bead stores the served binary must read. The env chain is what
# helm-svc itself resolves (source.DiscoverCityPath), so a hand run probes the
# city its operator meant. The listing is the fallback that makes this work
# where it matters: the supervisor that runs the helm-build order carries no
# GC_CITY at all, so an env-only lookup would report "unprobed" on every tick
# forever — a gate that never fires, which is the shape of the defect it exists
# to close. Empty means there is genuinely nothing to probe.
CITY_PATH=""
for _city_env in "${GC_HELM_CITY_PATH:-}" "${GC_CITY_PATH:-}" "${GC_CITY:-}"; do
    if [ -n "$_city_env" ]; then CITY_PATH="$_city_env"; break; fi
done
if [ -z "$CITY_PATH" ] && [ -n "$SERVICES" ]; then
    CITY_PATH="$(printf '%s' "$SERVICES" | jq -r '.city_path // empty' 2>/dev/null || true)"
fi

# Generous on purpose: a false "unreadable" turns a healthy city red and buys a
# futile rebuild, so a slow cold Dolt open must be allowed to finish.
PROBE_TIMEOUT="${GC_HELM_BUILD_PROBE_TIMEOUT:-60}"
PROBE_DETAIL=""

# The beads library the binary EMBEDDED. A rebuild changes what a binary can
# read only if this moves, so it is the key that separates "retry the build"
# from "the go.mod pin is the problem".
BEADS_MODULE="github.com/steveyegge/beads"
PROBE_LATCH="$STATE_ROOT/probe-failed"

# probe_binary <path> — 0 readable, 1 not, with the reason in PROBE_DETAIL.
# A binary too old to know the verb answers non-zero too, which is the right
# answer: it predates the check and is worth rebuilding.
probe_binary() {
    local out=""
    PROBE_DETAIL=""
    # Handed the city explicitly: the probe must answer for the city this run
    # resolved, not for whatever the ambient environment happens to name.
    if out="$(GC_HELM_CITY_PATH="$CITY_PATH" "$1" probe --timeout="$PROBE_TIMEOUT" 2>&1)"; then
        return 0
    fi
    # One line, bounded: build-status is a single-line file and the live
    # schema-skew message names every rig in the city.
    PROBE_DETAIL="$(printf '%s' "$out" | tr '\n\t' '  ' | sed 's/  */ /g; s/^ *//; s/ *$//' | cut -c1-300)"
    [ -n "$PROBE_DETAIL" ] || PROBE_DETAIL="the probe produced no diagnostic"
    return 1
}

embedded_beads() { # <binary> — the pinned library version, or "unknown"
    local v=""
    v="$("$GO" version -m "$1" 2>/dev/null | awk -v m="$BEADS_MODULE" '$1 == "dep" && $2 == m { print $3; exit }' || true)"
    printf '%s' "${v:-unknown}"
}

write_status() { # <kind> [detail]
    local line
    line="$1 $(date -u +%FT%TZ)"
    if [ -n "${2:-}" ]; then line="$line $2"; fi
    printf '%s\n' "$line" > "$STATE_ROOT/build-status" 2>/dev/null || true
}

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
    fi

    # Newer than every source proves nothing about the store. Ask the binary.
    if [ -z "$CITY_PATH" ]; then
        echo "gc-helm-build: $BIN is up to date (no city in the environment; readability unprobed)"
        write_status unprobed
        exit 0
    fi
    if probe_binary "$BIN"; then
        echo "gc-helm-build: $BIN is up to date and can read the city's bead stores"
        write_status ok
        rm -f -- "$PROBE_LATCH" 2>/dev/null || true
        exit 0
    fi

    # Unreadable. Rebuilding is the remedy only while it can produce a
    # different binary; once it has been tried against this exact library
    # version, repeating it every five minutes changes nothing and buries the
    # real remedy — a dependency bump — under a rebuild loop.
    EMBEDDED="$(embedded_beads "$BIN")"
    if [ "$(cat "$PROBE_LATCH" 2>/dev/null || true)" = "$EMBEDDED" ]; then
        echo "gc-helm-build: $BIN CANNOT READ the city's bead stores, and a rebuild would embed the same $BEADS_MODULE $EMBEDDED; bump it in $MOD/go.mod. Detail: $PROBE_DETAIL" >&2
        write_status unreadable "$PROBE_DETAIL"
        exit 1
    fi
    echo "gc-helm-build: $BIN cannot read the city's bead stores; rebuilding. Detail: $PROBE_DETAIL"
    need_build=1
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
    write_status failed
    exit 1
fi
echo "gc-helm-build: built $BIN"

# A compiling binary is not a working one. `ok` is spent here and nowhere else,
# so nothing downstream can read this file as a healthy board while the gather
# it reports on cannot run.
STATUS_KIND=unprobed
if [ -n "$CITY_PATH" ]; then
    if probe_binary "$BIN"; then
        STATUS_KIND=ok
        rm -f -- "$PROBE_LATCH" 2>/dev/null || true
    else
        STATUS_KIND=unreadable
        # What was just tried, so the next tick can tell a retry from a loop.
        printf '%s\n' "$(embedded_beads "$BIN")" > "$PROBE_LATCH" 2>/dev/null || true
    fi
fi
write_status "$STATUS_KIND" "$PROBE_DETAIL"

# Record the unfinished half BEFORE the restart, so whatever stops this run
# leaves the evidence; it also carries a hand-run build to the next tick.
printf 'published %s\n' "$(date -u +%FT%TZ)" > "$RESTART_PENDING" 2>/dev/null \
    || echo "gc-helm-build: could not write $RESTART_PENDING; a failed restart will not be retried" >&2

# Build and restart are one step: a binary nothing restarts onto is inert.
if [ "$DEPLOY" -eq 1 ]; then
    restart_service || exit 1
fi

if [ "$STATUS_KIND" = "unreadable" ]; then
    echo "gc-helm-build: the binary just built CANNOT READ the city's bead stores; the board will not render. Detail: $PROBE_DETAIL" >&2
    exit 1
fi
