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
    ( cd "$MOD" && "$GO" build -o "$BIN" ./cmd/helm-svc )
fi

exec "$BIN" "$@"
