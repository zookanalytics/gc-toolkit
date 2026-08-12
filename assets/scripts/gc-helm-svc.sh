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
# (override the go toolchain), GC_SERVICE_STATE_ROOT (binary cache location).
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

# Sources that end up inside the binary: Go files, plus the built web bundle,
# which is compiled in by go:embed (services/helm/web/embed.go). A bundle-only
# change has to rebuild too, or the mount keeps serving the SPA that was
# embedded at the last Go edit. node_modules is pruned — nothing there is built
# from, and walking it costs more than the rest of the module together.
newer_than_binary() {
    find "$MOD" -name node_modules -prune -o \( -name '*.go' -o -path "$MOD/web/dist/*" \) -newer "$BIN" -print -quit 2>/dev/null
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
    GOTMP=/var/tmp/gotmp
    mkdir -p "$GOTMP"
    if ! ( cd "$MOD" && TMPDIR="$GOTMP" GOTMPDIR="$GOTMP" "$GO" build -o "$BIN" ./cmd/helm-svc ); then
        # A failed rebuild must not exit into an immediate supervisor restart:
        # the rerun rebuilds and fails again, and that loop is what turns a
        # transient build failure into the self-sustaining outage this guards
        # against. If a previously-built binary exists, keep serving it so the
        # failure surfaces in logs instead of a crash-restart storm; with no
        # binary to fall back on there is nothing to serve, so propagate it.
        if [ -x "$BIN" ]; then
            echo "gc-helm-svc: rebuild failed; continuing to serve existing $BIN" >&2
        else
            echo "gc-helm-svc: build failed and no cached binary to serve" >&2
            exit 1
        fi
    fi
fi

exec "$BIN" "$@"
