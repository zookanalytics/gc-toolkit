#!/usr/bin/env bash
# gc-helm-build.sh — build the Helm backend binary, OUT OF BAND from the service.
#
# This is the only thing in the tree that builds helm-svc. The service launcher
# (gc-helm-svc.sh) execs whatever binary this leaves behind and builds nothing.
#
# WHY THE SPLIT EXISTS. The launcher used to build inline and then exec. That
# cannot be made to work, and the numbers are not close:
#
#   * the supervisor gives a proxy_process 5s to answer its health probe
#     (proxyProcessReadyTimeout, gascity internal/workspacesvc/proxy_process.go)
#   * a WARM build of this module takes ~12.5s; a COLD one took 2m29s measured
#     on 2026-08-22 (161MB binary, ~170 deps, 1.3G of build cache)
#
# So a build inside the start path never finishes inside the window — not on a
# slow day, ever. What follows is not a race but a certainty: waitReady's
# deadline fires, the supervisor calls stopProcessGroup() on the whole group,
# and the build dies with it. The next start begins again from wherever the
# cache got to, and is killed at 5s again.
#
# That loop left fingerprints. On 2026-08-22 this service's bin/ held 2,677
# zero-byte .helm-svc.build.XXXXXX staging files laid down between 08-19 05:51
# and 08-22 02:40 — one per killed start, each a `mktemp` that never reached its
# `mv` or its `rm -f` because the kill landed mid-compile. Zero-byte because the
# linker writes the output last and the build never got that far.
#
# Building here instead means the start path is an exec: nothing to race the
# readiness probe, nothing for the readiness kill to destroy, and a build that
# is allowed to take the two and a half minutes it actually needs.
#
# Staleness is an ordinary artifact-older-than-sources dependency — `find
# -newer`, the same question make asks — not a probe of the binary's behaviour.
#
# Usage:
#   gc-helm-build.sh              build iff the binary is missing or stale
#   gc-helm-build.sh --deploy     the order's mode: do nothing unless the helm
#                                 service is registered in this city; build iff
#                                 stale; restart the service iff a new binary
#                                 was published
#
# Exit: 0 = the binary is current (built now, or already fresh, or this city
#           does not run helm); 1 = a build was needed and failed, in which case
#           the previously-built binary is left exactly as it was.
#
# Env honoured: GC_SERVICE_STATE_ROOT (binary cache location; the supervisor
# sets it, and it wins when present), GC_CITY_ROOT / GC_CITY (used to derive
# that location when it is not), GC_GO_BIN (override the go toolchain),
# GC_HELM_GOTMP (build-scratch root), GC_HELM_SERVICE_NAME (default "helm"),
# GC_HELM_GC_BIN (override the gc binary used to locate and restart the service).
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

# Ask the city about the service once, and get two answers out of it: whether
# this city runs helm at all, and — authoritatively — where its state root is.
#
# The listing reports `service_name` (not `name`) plus `city_path` and a
# `state_root` that is relative to it. Reading the real path beats reproducing
# gascity's StateRootOrDefault() here and hoping the two stay in step.
#
# A `gc service list` that errors is NOT taken as "not registered": that would
# silently stop deploying on any transient CLI failure, which is the class of
# silent stall this bead exists to end. Only a successful listing that omits the
# service is proof of absence.
SERVICES=""
if SERVICES="$("$GC_BIN" service list --json 2>/dev/null)"; then
    # Distinguish "jq ran and found nothing" from "jq could not run". `jq -e`
    # exits 1 for a false result and something else entirely for a missing
    # binary, a parse error or a bad filter. Collapsing those into "absent"
    # would be the same silent-stall bug the failed-listing arm below avoids:
    # one missing dependency and the order deploys nothing, forever, quietly.
    set +e
    printf '%s' "$SERVICES" | jq -e --arg n "$SERVICE_NAME" \
        '[.services[]? | select((.service_name // .name) == $n)] | length > 0' >/dev/null 2>&1
    _q_rc=$?
    set -e
    if [ "$_q_rc" -eq 1 ]; then
        # The city was asked and does not run helm. In --deploy mode this order
        # ships everywhere but only some cities declare the service, and
        # building a 161MB binary for one that will never run it is pure waste.
        # A hand-run build is not gated: someone asking for a build means it.
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

# Where the built binary lives. The supervisor exports GC_SERVICE_STATE_ROOT
# when it launches the service, but this script runs from an order, which does
# not — so take the path the city just reported, and fall back to deriving it
# only when there was no listing to read (a hand-run outside a live city).
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
    # Walk up from the module looking for the city's runtime dir. Covers a
    # human running this straight out of a rig checkout with no order env.
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

# Resolve a Go toolchain: explicit override, then PATH, then the conventional
# system install (an order's PATH may not include Go).
GO="${GC_GO_BIN:-}"
if [ -z "$GO" ]; then
    if command -v go >/dev/null 2>&1; then GO="go"; else GO="/usr/local/go/bin/go"; fi
fi

# Sources that end up inside the binary: Go files, the module's dependency
# manifests, plus the built web bundle, which is compiled in by go:embed
# (services/helm/web/embed.go). A bundle-only change has to rebuild too, or the
# mount keeps serving the SPA that was embedded at the last Go edit.
#
# go.mod and go.sum are listed EXPLICITLY because `-name '*.go'` does not match
# them — they end in .mod/.sum. Without them a dependency-only bump touches no
# file this predicate inspects, so the stale binary keeps serving as if the bump
# never landed. That is not hypothetical: helm-svc served a blind board for days
# on a beads pin whose schema support the city had migrated past, and the fix
# looked like it had not landed because this find never saw go.mod (tk-ohdex).
#
# node_modules is pruned — nothing there is built from, and walking it costs
# more than the rest of the module together.
newer_than_binary() {
    find "$MOD" -name node_modules -prune -o \( -name '*.go' -o -name go.mod -o -name go.sum -o -path "$MOD/web/dist/*" \) -newer "$BIN" -print -quit 2>/dev/null
}

# Does a pid still hold a slot on the process table? Used to tell a build's
# live scratch dir from one a killed build stranded. /proc is authoritative
# where it exists; `kill -0` is the portable fallback, and while it cannot
# distinguish "gone" from "not ours", every build here runs as the same user,
# so the distinction never arises.
pid_alive() {
    if [ -d /proc ]; then
        [ -e "/proc/$1" ]
    else
        kill -0 "$1" 2>/dev/null
    fi
}

# Reclaim the staging files the inline-build era stranded in $BIN_DIR, and any
# this script itself loses to a kill. `mktemp` publishes the name before the
# build writes a byte, so anything interrupted between the two leaves one
# behind; 2,677 had accumulated by 2026-08-22. An hour is far longer than the
# 2m29s cold build that is the slowest thing that can legitimately hold one, so
# no build in flight — this one or a concurrent one — can be swept.
find "$BIN_DIR" -maxdepth 1 -type f -name '.helm-svc.build.*' -mmin +60 -delete 2>/dev/null || true

# Build when the binary is missing or any source file is newer than it.
need_build=0
if [ ! -x "$BIN" ]; then
    need_build=1
elif [ -n "$(newer_than_binary)" ]; then
    need_build=1
fi
if [ "$need_build" -eq 0 ]; then
    echo "gc-helm-build: $BIN is up to date"
    exit 0
fi

# Keep the Go linker's and cgo's scratch off /tmp. /tmp is a size-capped tmpfs
# shared by the whole fleet; the linker maps its output object under $TMPDIR
# (and cgo's gcc ignores $GOTMPDIR), so a build left on the default /tmp leaks a
# multi-hundred-MB go-link dir on every failed link. Pin both to a root-fs path,
# per the Build Cache Conventions in gascity AGENTS.md. GOCACHE is deliberately
# NOT set: its default (~/.cache/go-build) is the correct warm on-disk cache and
# must not be redirected — it is what keeps a rebuild at ~12s instead of 2m29s.
GOTMP="${GC_HELM_GOTMP:-/var/tmp/gotmp}"
mkdir -p "$GOTMP"

# Bound $GOTMP. Nothing outside this script ever deletes from it, and a build
# that dies before its own cleanup runs — OOM kill, SIGKILL, ENOSPC — strands a
# ~300MB go-link dir here permanently. Unlike the /tmp tmpfs this scratch was
# moved off, /var/tmp survives reboot and sits on the root filesystem, the same
# device as the Dolt journal, so the leak is monotonic and lands on the data
# plane: one post-reboot rebuild storm stranded 222 dirs (33G) and filled the
# root fs (tk-m18ml).
#
# Two sweeps, because the two kinds of debris carry different evidence:
#
#   * run.<pid> whose pid is gone was stranded by a killed build. Reclaim it on
#     sight — that storm deposited its 33G inside four hours, so an age
#     threshold alone would still have been waiting when the disk filled.
#   * anything else still here a day later is un-owned: the pre-fix
#     go-link-*/go-build* backlog, or a run dir whose pid was recycled. A day is
#     orders of magnitude longer than a helm-svc build, so no build in flight
#     can match.
#
# Neither sweep can take a concurrent build's scratch: that dir is fresh AND its
# pid is alive.
for gotmp_entry in "$GOTMP"/run.*; do
    [ -d "$gotmp_entry" ] || continue          # no match: the glob itself
    gotmp_pid="${gotmp_entry##*/run.}"
    case "$gotmp_pid" in ''|*[!0-9]*) continue ;; esac   # not pid-owned
    if pid_alive "$gotmp_pid"; then continue; fi
    rm -rf -- "$gotmp_entry" 2>/dev/null || true
done
find "$GOTMP" -mindepth 1 -maxdepth 1 -mmin +1440 -exec rm -rf -- {} + 2>/dev/null || true

# Build in scratch this invocation owns: it is what makes the sweep above able
# to tell stranded from live, and it is deleted below whichever way the build
# goes.
#
# Every step of the hygiene degrades rather than fails. `set -e` is live here,
# so an unguarded mkdir would abort the script — and the case where it aborts is
# a full disk, precisely when finishing the build (or reporting honestly why it
# could not) is what matters. Falling back to the shared root is no worse than
# before this bounding existed, and the sweeps above still reclaim what lands
# there.
GOTMP_RUN="$GOTMP/run.$$"
GOTMP_RUN_OWNED=0
rm -rf -- "$GOTMP_RUN" 2>/dev/null || true   # a recycled pid inherits nothing
if mkdir "$GOTMP_RUN" 2>/dev/null; then
    GOTMP_RUN_OWNED=1
else
    echo "gc-helm-build: cannot create $GOTMP_RUN; building in $GOTMP" >&2
    GOTMP_RUN="$GOTMP"
fi

# One trap covers every exit path, including a SIGTERM from an order that hits
# its timeout. It drops this invocation's scratch (only when we own it — on the
# degraded path $GOTMP_RUN *is* $GOTMP, and removing that would take every
# concurrent build's scratch with it) and the staging file, which otherwise
# becomes another of the 2,677.
cleanup() {
    [ "$GOTMP_RUN_OWNED" -eq 1 ] && rm -rf -- "$GOTMP_RUN" 2>/dev/null
    [ -n "${BIN_TMP:-}" ] && rm -f -- "$BIN_TMP" 2>/dev/null
    return 0
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

# Publish a freshly built binary to $BIN only via an atomic rename from a
# scratch file beside it. Building `-o "$BIN"` in place would let a failed link
# truncate the live cached binary, and a zero-byte or half-written file is still
# executable enough for the launcher's `-x` test to pass, so the exec would die
# with "Exec format error" and re-arm the supervisor's restart backoff. The
# scratch sits in $BIN_DIR (same filesystem as $BIN) so the rename is atomic;
# renaming over a running binary is safe on Linux (the old inode lives on for
# the running exec), unlike an in-place `-o` that truncates it.
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
    # $BIN was never touched, so whatever was being served before is still
    # being served. Say so loudly and exit non-zero: this runs from an order,
    # not the start path, so failing here costs a log line and a retry next
    # tick rather than a crash-restart storm.
    echo "gc-helm-build: BUILD FAILED; $BIN left unchanged" >&2
    printf 'failed %s\n' "$(date -u +%FT%TZ)" > "$STATE_ROOT/build-status" 2>/dev/null || true
    exit 1
fi

printf 'ok %s\n' "$(date -u +%FT%TZ)" > "$STATE_ROOT/build-status" 2>/dev/null || true
echo "gc-helm-build: built $BIN"

# Build and restart are one step on purpose. A new binary that nothing restarts
# onto is the defect this replaced: three commits touching services/helm landed
# on 2026-08-22 and all three were inert in the served board because the process
# had been up 14h55m on an older artifact.
if [ "$DEPLOY" -eq 1 ]; then
    echo "gc-helm-build: restarting service '$SERVICE_NAME'"
    if ! "$GC_BIN" service restart "$SERVICE_NAME"; then
        echo "gc-helm-build: 'gc service restart $SERVICE_NAME' failed; the new binary is published but not yet serving" >&2
        exit 1
    fi
fi
