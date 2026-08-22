#!/usr/bin/env bash
# gc-helm-svc.sh — proxy_process launcher for the Attention Canvas backend.
#
# The supervisor invokes this as a workspace-service `command` (declared in a
# city-scoped [[service]]; see services/helm/README.md). cmd.Dir is the city
# root, so the relative command path resolves there. This wrapper exists because
# the Go binary lives in the rig (rigs/gc-toolkit/services/helm) while the
# [[service]] must be declared city-scoped: it locates the cached binary and
# exec's it, so the supervisor's SIGTERM reaches the Go process directly.
#
# THIS SCRIPT DOES NOT BUILD. It used to, and that could not work: the
# supervisor allows a proxy_process 5s to answer its health probe
# (proxyProcessReadyTimeout, gascity internal/workspacesvc/proxy_process.go),
# while a warm build of this module takes ~12.5s and a cold one 2m29s. The
# deadline always won, and waitReady's stopProcessGroup() then killed the build
# along with the start — 2,677 abandoned staging files in three days, and a
# restart that could only ever report "did not become ready before timeout".
#
# Building now belongs to assets/scripts/gc-helm-build.sh, driven out of band by
# the `helm-build` order (orders/helm-build.toml). Start is an exec: it cannot
# race the readiness probe, and there is nothing here for the readiness kill to
# destroy.
#
# Env honoured: GC_SERVICE_SOCKET (required, set by the supervisor),
# GC_SERVICE_STATE_ROOT (binary cache location).
set -euo pipefail

BIN_DIR="${GC_SERVICE_STATE_ROOT:-${TMPDIR:-/tmp}}/bin"
BIN="$BIN_DIR/helm-svc"

if [ ! -x "$BIN" ]; then
    # Nothing to serve. Exiting non-zero puts the service in `degraded` with a
    # reason, and the supervisor's restart backoff will pick it up again once
    # the builder has run — which is the right shape, because the fix is a
    # build this process is deliberately not allowed to attempt.
    cat >&2 <<MSG
gc-helm-svc: no binary at $BIN — nothing to exec.
The build runs out of band and has not produced one yet.
  build now: assets/scripts/gc-helm-build.sh
  automatic: the 'helm-build' order (orders/helm-build.toml) builds and restarts
             this service whenever services/helm is newer than the binary.
Deliberately NOT building here: the readiness window is 5s and this build needs
12.5s warm / 2m29s cold, so a build started here is always killed with the start.
MSG
    exit 1
fi

exec "$BIN" "$@"
