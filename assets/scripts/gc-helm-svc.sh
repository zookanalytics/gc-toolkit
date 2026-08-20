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
# GC_HELM_GOTMP (build-scratch root; the test points it off /var/tmp).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOD="$(cd "$HERE/../../services/helm" && pwd)"

# Cache the built binary under the service state root when the supervisor
# provides one (durable across restarts); otherwise fall back to a temp dir.
BIN_DIR="${GC_SERVICE_STATE_ROOT:-${TMPDIR:-/tmp}}/bin"
BIN="$BIN_DIR/helm-svc"
mkdir -p "$BIN_DIR"

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

# Build when the binary is missing or any source file is newer than it.
need_build=0
if [ ! -x "$BIN" ]; then
    need_build=1
elif [ -n "$(newer_than_binary)" ]; then
    need_build=1
fi
if [ "$need_build" -eq 1 ]; then
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
        rm -rf -- "$gotmp_entry"
    done
    find "$GOTMP" -mindepth 1 -maxdepth 1 -mmin +1440 -exec rm -rf -- {} + 2>/dev/null || true

    # Build in scratch this invocation owns: it is what makes the sweep above
    # able to tell stranded from live, and it is deleted below whichever way
    # the build goes.
    GOTMP_RUN="$GOTMP/run.$$"
    rm -rf -- "$GOTMP_RUN"        # a recycled pid must not inherit stale scratch
    mkdir -p "$GOTMP_RUN"
    trap 'rm -rf -- "$GOTMP_RUN"' EXIT

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
    if [ "$build_ok" -eq 0 ]; then
        # No fresh binary was published and the live $BIN was never touched, so
        # a rebuild failure (or an inability to stage the scratch) must not exit
        # into an immediate supervisor restart: the rerun fails again, and that
        # loop is what turns a transient failure into the self-sustaining outage
        # this guards against. If a previously-built binary exists, keep serving
        # it so the failure surfaces in logs instead of a crash-restart storm;
        # with no binary to fall back on there is nothing to serve, so propagate.
        if [ -x "$BIN" ]; then
            echo "gc-helm-svc: rebuild failed; continuing to serve existing $BIN" >&2
        else
            echo "gc-helm-svc: build failed and no cached binary to serve" >&2
            exit 1
        fi
    fi

    # Drop this invocation's scratch here rather than leaving it to the EXIT
    # trap: the script ends in `exec`, which replaces the shell without running
    # traps, so on every successful start the dir would survive under a pid that
    # is now helm-svc's own — live for the whole service lifetime, and invisible
    # to the sweep above for exactly as long. That is the leak again, one dir per
    # restart. The trap stays armed until here to cover the `exit 1` above.
    rm -rf -- "$GOTMP_RUN"
    trap - EXIT
fi

exec "$BIN" "$@"
