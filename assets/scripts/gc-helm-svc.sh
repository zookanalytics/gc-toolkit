#!/usr/bin/env bash
# gc-helm-svc.sh — proxy_process launcher for the Attention Canvas backend.
#
# The supervisor invokes this as a workspace-service `command` (declared in a
# city-scoped [[service]]; see services/helm/README.md). cmd.Dir is the
# city root, so the relative command path resolves there. This wrapper exists
# because the Go binary lives in the rig (rigs/gc-toolkit/services/helm)
# while the [[service]] must be declared city-scoped: it locates the module
# relative to its own path, builds the binary on demand (Go's build cache makes
# restarts cheap), and exec's it so the supervisor's SIGTERM reaches the Go
# process directly.
#
# Env honoured: GC_SERVICE_SOCKET (required, set by the supervisor), GC_GO_BIN
# (override the go toolchain), GC_SERVICE_STATE_ROOT (binary cache location),
# GC_HELM_GOTMP (build-scratch root; the test points it off /var/tmp),
# GC_HELM_ALLOW_STALE (serve a cached binary that fails its own self-check),
# GC_HELM_BUILD_WAIT (seconds to wait on a build another start left running),
# GC_HELM_BUILDER (internal: marks the detached build re-exec of this script).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOD="$(cd "$HERE/../../services/helm" && pwd)"
SELF="${BASH_SOURCE[0]}"

# Cache the built binary under the service state root when the supervisor
# provides one (durable across restarts); otherwise fall back to a temp dir.
BIN_DIR="${GC_SERVICE_STATE_ROOT:-${TMPDIR:-/tmp}}/bin"
BIN="$BIN_DIR/helm-svc"
mkdir -p "$BIN_DIR"

# Durable build telemetry, all beside the binary so it survives restarts and an
# operator can read it without reconstructing anything.
#
# WHY THIS EXISTS (tk-y3tks). A rebuild failure used to leave exactly one trace:
# a line on this script's stderr, which the supervisor folds into the service
# log nobody reads until something is already known to be wrong. What the
# operator actually saw was `gc service list` reporting `did not become ready
# before timeout` — a message that names neither the stale artifact nor the
# reason it was stale. Helm was down for days on that gap. These files make the
# failure legible as itself: `build-status` is one line of prose, `build.log`
# holds the toolchain's own output.
BUILD_LOG="$BIN_DIR/build.log"
BUILD_LOCK="$BIN_DIR/.build.pid"
BUILD_RESULT="$BIN_DIR/.build.result"
BUILD_STATUS="$BIN_DIR/build-status"

# Record one line of operator-facing state, and echo it to stderr so it also
# lands in the service log. Best-effort: telemetry must never be the reason a
# service fails to start, so every write degrades.
record_status() { # <prose>
    printf '%s  %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" "$1" \
        > "$BUILD_STATUS" 2>/dev/null || true
    echo "gc-helm-svc: $1" >&2
}

# Replay what the build actually said onto this script's stderr, so the reason
# reaches the SERVICE LOG and not only the file beside the binary.
#
# The build is detached, so its output goes to $BUILD_LOG and nowhere the
# supervisor can see. That is the right home for it — it is durable and it
# outlives the start that produced it — but it also means a failure would
# otherwise surface to an operator as `did not become ready before timeout`
# with the actual toolchain error (ENOSPC, a compile error, unwritable scratch)
# sitting in a file nobody has been told to open. Bounded to the tail: a Go
# build can emit a lot, and the last lines are where the failure is.
BUILD_LOG_TAIL_LINES=20
emit_build_log_tail() {
    [ -s "$BUILD_LOG" ] || return 0
    echo "gc-helm-svc: --- last ${BUILD_LOG_TAIL_LINES} lines of $BUILD_LOG ---" >&2
    tail -n "$BUILD_LOG_TAIL_LINES" "$BUILD_LOG" 2>/dev/null | sed 's/^/gc-helm-svc:   /' >&2 || true
    echo "gc-helm-svc: --- end of $BUILD_LOG ---" >&2
}

# When was the cached artifact built? Named in every message about serving or
# refusing it — "the binary is stale" is not actionable, "the binary is from
# Aug 11" is.
bin_mtime() {
    date -u -r "$BIN" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
        || stat -c %y "$BIN" 2>/dev/null \
        || echo "unknown date"
}

# Resolve a Go toolchain: explicit override, then PATH, then the conventional
# system install (the supervisor's PATH may not include Go).
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
# file this predicate inspects, so the service restarts, the stale binary passes
# the `-x "$BIN"` check below, and the old dependency keeps serving as if the
# bump never landed. That is not hypothetical: helm-svc served a blind board for
# days on a beads pin whose schema support the city had migrated past, and the
# fix looked like it had not landed because this find never saw go.mod (tk-ohdex).
#
# node_modules is pruned — nothing there is built from, and walking it costs
# more than the rest of the module together.
newer_than_binary() {
    find "$MOD" -name node_modules -prune -o \( -name '*.go' -o -name go.mod -o -name go.sum -o -path "$MOD/web/dist/*" \) -newer "$BIN" -print -quit 2>/dev/null
}

# Does a pid still hold a slot on the process table? Used to tell a build's
# live scratch dir from one a killed build stranded. /proc is authoritative
# where it exists; `kill -0` is the portable fallback, and while it cannot
# distinguish "gone" from "not ours", every build here runs as the supervisor's
# own user, so the distinction never arises.
pid_alive() {
    if [ -d /proc ]; then
        [ -e "/proc/$1" ]
    else
        kill -0 "$1" 2>/dev/null
    fi
}

# ---------------------------------------------------------------------------
# Builder mode
# ---------------------------------------------------------------------------
# The build runs in a DETACHED session and this block is that session's
# entrypoint: the script re-execs itself with GC_HELM_BUILDER=1 so the scratch
# hygiene and publish logic have exactly one implementation.
#
# WHY THE BUILD IS DETACHED (tk-y3tks). Rebuild-on-start runs INSIDE the
# supervisor's readiness window, and a ~160MB link does not finish in time. When
# the window expires the supervisor kills this script — and, when the build was
# an ordinary inline child, the build with it. Every restart therefore threw
# away the same partial link and left the cached binary untouched: `gc service
# restart helm` could not fix the failure `gc service restart helm` is the
# documented remedy for, and the service stayed down until someone built it by
# hand. Detaching decouples the two clocks. The build now outlives the window,
# so a start that is killed still leaves progress behind, and the next start
# attaches to that build (or finds it finished) instead of restarting it.
if [ -n "${GC_HELM_BUILDER:-}" ]; then
    # Keep the Go linker's and cgo's scratch off /tmp. /tmp is a size-capped
    # tmpfs shared by the whole fleet; the linker maps its output object under
    # $TMPDIR (and cgo's gcc ignores $GOTMPDIR), so a build left on the default
    # /tmp leaks a multi-hundred-MB go-link dir on every failed link. Pin both
    # to a root-fs path, per the Build Cache Conventions in gascity AGENTS.md.
    # GOCACHE is deliberately NOT set: its default (~/.cache/go-build) is the
    # correct warm on-disk cache and must not be redirected.
    GOTMP="${GC_HELM_GOTMP:-/var/tmp/gotmp}"
    mkdir -p "$GOTMP"

    # Bound $GOTMP. Nothing outside this script ever deletes from it, and a
    # build that dies before its own cleanup runs — OOM kill, supervisor
    # SIGKILL, ENOSPC — strands a ~300MB go-link dir here permanently. Unlike
    # the /tmp tmpfs this scratch was moved off, /var/tmp survives reboot and
    # sits on the root filesystem, the same device as the Dolt journal, so the
    # leak is monotonic and lands on the data plane: one post-reboot rebuild
    # storm stranded 222 dirs (33G) and filled the root fs (tk-m18ml).
    #
    # Two sweeps, because the two kinds of debris carry different evidence:
    #
    #   * run.<pid> whose pid is gone was stranded by a killed build. Reclaim
    #     it on sight — that storm deposited its 33G inside four hours, so an
    #     age threshold alone would still have been waiting when the disk
    #     filled.
    #   * anything else still here a day later is un-owned: the pre-fix
    #     go-link-*/go-build* backlog, or a run dir whose pid was recycled. A
    #     day is orders of magnitude longer than a helm-svc build, so no build
    #     in flight can match.
    #
    # Neither sweep can take a concurrent build's scratch: that dir is fresh
    # AND its pid is alive.
    for gotmp_entry in "$GOTMP"/run.*; do
        [ -d "$gotmp_entry" ] || continue          # no match: the glob itself
        gotmp_pid="${gotmp_entry##*/run.}"
        case "$gotmp_pid" in ''|*[!0-9]*) continue ;; esac   # not pid-owned
        if pid_alive "$gotmp_pid"; then continue; fi
        rm -rf -- "$gotmp_entry" 2>/dev/null || true
    done
    find "$GOTMP" -mindepth 1 -maxdepth 1 -mmin +1440 -exec rm -rf -- {} + 2>/dev/null || true

    # Build in scratch this invocation owns: it is what makes the sweep above
    # able to tell stranded from live, and it is deleted below whichever way
    # the build goes.
    #
    # Every step of the hygiene degrades rather than fails, because none of it
    # is worth a service that will not start. `set -e` is live here, so an
    # unguarded mkdir would abort the script — and the case where it aborts is
    # a full disk, precisely when the fallback below (keep serving the cached
    # binary, log, do not restart-loop) is the behaviour that matters. Falling
    # back to the shared root is no worse than before this bounding existed,
    # and the sweeps above still reclaim what lands there.
    GOTMP_RUN="$GOTMP/run.$$"
    GOTMP_RUN_OWNED=0
    rm -rf -- "$GOTMP_RUN" 2>/dev/null || true   # a recycled pid inherits nothing
    if mkdir "$GOTMP_RUN" 2>/dev/null; then
        GOTMP_RUN_OWNED=1
        trap 'rm -rf -- "$GOTMP_RUN" 2>/dev/null || true' EXIT
    else
        echo "gc-helm-svc: cannot create $GOTMP_RUN; building in $GOTMP" >&2
        GOTMP_RUN="$GOTMP"
    fi

    # Publish a freshly built binary to $BIN only via an atomic rename from a
    # scratch file beside it. Building `-o "$BIN"` in place would let a failed
    # link truncate the live cached binary: the fallback below only tests
    # `-x "$BIN"`, so a zero-byte or half-written file still passes as a
    # servable binary and the final `exec` dies with "Exec format error",
    # re-arming the crash-restart loop this guard exists to break. The scratch
    # sits in $BIN_DIR (same filesystem as $BIN) so the rename is atomic;
    # renaming over a running binary is safe on Linux (the old inode lives on
    # for the running exec), unlike an in-place `-o` that truncates it.
    # TMPDIR/GOTMPDIR still steer the linker's own scratch off the /tmp tmpfs.
    build_ok=0
    if BIN_TMP="$(mktemp "$BIN_DIR/.helm-svc.build.XXXXXX" 2>/dev/null)"; then
        if ( cd "$MOD" && TMPDIR="$GOTMP_RUN" GOTMPDIR="$GOTMP_RUN" "$GO" build -o "$BIN_TMP" ./cmd/helm-svc ) && mv -f "$BIN_TMP" "$BIN"; then
            build_ok=1
        else
            rm -f "$BIN_TMP"
        fi
    fi

    # Drop this invocation's scratch here rather than leaving it to the EXIT
    # trap, so the dir is gone before the waiting start execs. Guarded on
    # ownership: on the degraded path $GOTMP_RUN *is* $GOTMP, and removing that
    # would take every concurrent build's scratch with it.
    if [ "$GOTMP_RUN_OWNED" -eq 1 ]; then
        rm -rf -- "$GOTMP_RUN" 2>/dev/null || true
        trap - EXIT
    fi

    # The result file is the ONLY channel back to the waiting start — the
    # builder is detached, so its exit status reaches nobody once the start that
    # spawned it has been killed. Write it last, and unconditionally.
    if [ "$build_ok" -eq 1 ]; then
        printf 'ok\n' > "$BUILD_RESULT" 2>/dev/null || true
    else
        printf 'fail\n' > "$BUILD_RESULT" 2>/dev/null || true
    fi
    exit 0
fi

# ---------------------------------------------------------------------------
# Start path
# ---------------------------------------------------------------------------

# Build when the binary is missing or any source file is newer than it.
need_build=0
if [ ! -x "$BIN" ]; then
    need_build=1
elif [ -n "$(newer_than_binary)" ]; then
    need_build=1
fi

# Is a build from an earlier (probably killed) start still running? Attaching to
# it is the whole point of detaching: a second build would restart the same link
# from scratch and be killed by the same window, which is the loop that kept
# helm down. The lock is written by the start that spawns the builder, so it is
# never read before it exists.
builder_pid=""
if [ -f "$BUILD_LOCK" ]; then
    lock_pid="$(cat "$BUILD_LOCK" 2>/dev/null || true)"
    case "$lock_pid" in
        ''|*[!0-9]*) ;;                                  # not a pid: ignore
        *) if pid_alive "$lock_pid"; then builder_pid="$lock_pid"; fi ;;
    esac
fi

if [ "$need_build" -eq 1 ] || [ -n "$builder_pid" ]; then
    builder_is_child=0
    if [ -n "$builder_pid" ]; then
        record_status "a build started by an earlier start is still running (pid $builder_pid); waiting for it"
    else
        # Clear the previous verdict only when actually starting a new build —
        # clearing it while attached would discard the running builder's answer.
        rm -f "$BUILD_RESULT" 2>/dev/null || true
        # setsid puts the build in its own session so the supervisor's kill at
        # the end of the readiness window cannot reach it. Without setsid the
        # build shares this script's process group and dies with it, which is
        # the defect. Degrade to a plain background child where setsid is
        # unavailable: still an improvement on an inline build, since the parent
        # exiting no longer waits on it.
        if command -v setsid >/dev/null 2>&1; then
            setsid env GC_HELM_BUILDER=1 bash "$SELF" >>"$BUILD_LOG" 2>&1 &
        else
            env GC_HELM_BUILDER=1 bash "$SELF" >>"$BUILD_LOG" 2>&1 &
        fi
        builder_pid=$!
        builder_is_child=1
        printf '%s\n' "$builder_pid" > "$BUILD_LOCK" 2>/dev/null || true
    fi

    if [ "$builder_is_child" -eq 1 ]; then
        # Our own child: `wait` reaps it, so it cannot linger as a zombie whose
        # /proc entry would read as "still building" forever. Deliberately
        # unbounded — if this start is killed while waiting, that is the
        # readiness window doing its job, and the detached build survives to be
        # picked up by the next one.
        wait "$builder_pid" 2>/dev/null || true
    else
        # Someone else's build: not waitable, so poll. Bounded, because a wedged
        # builder must not hold every subsequent start hostage; on expiry we
        # fall through and decide on whatever artifact we have.
        max_wait="${GC_HELM_BUILD_WAIT:-900}"
        case "$max_wait" in ''|*[!0-9]*) max_wait=900 ;; esac
        waited=0
        while pid_alive "$builder_pid" && [ "$waited" -lt "$((max_wait * 5))" ]; do
            sleep 0.2
            waited=$((waited + 1))
        done
    fi
    # Release the lock only if the builder is really gone. On the poll arm we
    # may have given up waiting while it is still linking, and clearing the
    # lock there would let the NEXT start begin a second build beside the first
    # — the duplicate-build loop this arm exists to prevent.
    if ! pid_alive "$builder_pid"; then
        rm -f "$BUILD_LOCK" 2>/dev/null || true
    fi

    build_result="$(cat "$BUILD_RESULT" 2>/dev/null || true)"
    if [ "$build_result" = ok ]; then
        record_status "rebuilt $BIN"
    else
        # No fresh binary was published and the live $BIN was never touched, so
        # a rebuild failure must not exit into an immediate supervisor restart:
        # the rerun fails again, and that loop is what turns a transient failure
        # into a self-sustaining outage.
        #
        # What it must ALSO not do is fall back blindly. Serving a binary that
        # cannot read the store is not availability — it is an outage that
        # reports itself as a running service. The cached artifact from the
        # tk-y3tks incident was executable, started, answered nothing useful,
        # and every board gather died on `schema version mismatch: database is
        # at v65, binary knows up to v61`. So the fallback is gated on the
        # artifact PROVING it still works: `-selfcheck` opens the live stores
        # through the same in-process backend the board reads. An artifact too
        # old to know the flag fails it by construction, which is the right
        # verdict — that vintage is precisely what this guard is for.
        #
        # KNOWN TRADE-OFF: -selfcheck cannot tell "this artifact is too old to
        # read the stores" from "the stores are unreachable right now". So a
        # rebuild failure that coincides with a Dolt outage refuses a binary
        # that may be fine. That intersection is narrow — the guard runs ONLY
        # when a rebuild was wanted AND failed, never on a healthy start — and
        # in it the board is degraded either way. GC_HELM_ALLOW_STALE is the
        # override when an operator knows better.
        emit_build_log_tail
        if [ ! -x "$BIN" ]; then
            record_status "build failed and no cached binary to serve; see $BUILD_LOG"
            exit 1
        fi
        stale_date="$(bin_mtime)"
        if [ "$need_build" -eq 0 ]; then
            # We never wanted a build — we only waited on one another start had
            # left running, and THAT failed. $BIN is still current with its own
            # sources, so nothing about it is superseded and there is nothing
            # for the guard below to distrust. Probing here would refuse a good
            # binary on the strength of someone else's failure.
            record_status "a concurrent build failed, but $BIN from $stale_date is current with its sources; serving it. See $BUILD_LOG"
        elif [ -n "${GC_HELM_ALLOW_STALE:-}" ]; then
            record_status "rebuild failed; continuing to serve existing $BIN from $stale_date — SELF-CHECK SKIPPED by GC_HELM_ALLOW_STALE; see $BUILD_LOG"
        elif ( "$BIN" -selfcheck ) >>"$BUILD_LOG" 2>&1; then
            record_status "rebuild failed; continuing to serve existing $BIN from $stale_date (self-check passed); see $BUILD_LOG"
        else
            # Refusing propagates, and the supervisor will restart us. That is
            # the correct loop rather than the one above: the detached build is
            # already running or already finished, so each restart is a fresh
            # chance to find a WORKING binary, and the reason is on the record
            # instead of being invisible behind "did not become ready".
            record_status "REFUSING to serve $BIN from $stale_date: the rebuild failed AND the cached artifact failed its own self-check (it cannot read the city's bead stores). Rebuild output: $BUILD_LOG"
            exit 1
        fi
    fi
fi

exec "$BIN" "$@"
