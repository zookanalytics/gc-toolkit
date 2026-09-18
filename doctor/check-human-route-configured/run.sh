#!/usr/bin/env bash
# doctor/check-human-route-configured — the bare "human" park route resolves to
# a config agent. gc-toolkit parks operator-owned work with gc.routed_to=human
# (lifecycle/lifecycle.toml park_route; also stamped by escalate.sh, gc-helm.sh,
# signoff.sh). Core's session-model check reports "stale-routed-config" for
# every such bead while no config agent resolves the route: it fires when
# FindAgent(cfg,"human") is nil, and FindAgent matches a bare (dotless) route
# only by an exact QualifiedName — so a rig-imported, binding-prefixed
# gc-toolkit.human does NOT satisfy it, only a top-level [[agent]] name="human"
# in the town's own city.toml does. That agent must set max_active_sessions = 0,
# or the supervisor spawns a "human" pool against the parked beads.
#
# Reports the bare agent's absence (the finding will fire) and a present agent
# that can still spawn (max_active_sessions != 0). The fix is written by
# assets/scripts/ensure-human-route-agent.sh.
# Read-only. Exit 0=OK 1=Warning 2=Error. stdout: message, then "  - detail"
# lines. Without gc and a city in scope the roster is not readable; there this
# notes that and passes rather than guessing.

set -u

city="${GC_CITY_PATH:-${GC_CITY:-}}"
writer="assets/scripts/ensure-human-route-agent.sh"

detail() { local v; for v in "$@"; do printf '  - %s\n' "$v"; done; }

if ! command -v gc >/dev/null 2>&1; then
    echo "human route configuration not verifiable here"
    detail "gc is not on PATH — the resolved agent roster is a runtime property, not readable without it"
    exit 0
fi
if [ -z "$city" ]; then
    echo "human route configuration not verifiable here"
    detail "no city in scope (GC_CITY_PATH/GC_CITY unset) — the resolved agent roster is not readable"
    exit 0
fi

roster=$(gc --city "$city" agent list --json 2>/dev/null); rc=$?
if [ "$rc" -ne 0 ] || [ -z "$roster" ]; then
    echo "human route configuration UNVERIFIED"
    detail "could not read the resolved agent roster (gc --city \"$city\" agent list --json rc=$rc)"
    detail "whether the bare human route resolves is unknown, which is not a benign skip: a missing agent lets stale-routed-config fire on every gc.routed_to=human bead"
    exit 1
fi

# The bare route resolves iff some agent's QualifiedName is exactly "human". gc
# agent list --json reports QualifiedName as .qualified_name (older builds
# expose only .name).
human_count=$(printf '%s' "$roster" | jq '[.agents[]? | select((.qualified_name // .name) == "human")] | length' 2>/dev/null)
case "$human_count" in ''|*[!0-9]*) human_count=0 ;; esac

if [ "$human_count" -eq 0 ]; then
    echo "the bare \"human\" route resolves to no config agent — stale-routed-config will fire on parked work"
    detail "core's session-model check reports stale-routed-config for every gc.routed_to=human bead while FindAgent(cfg,\"human\") is nil"
    detail "declare it top-level (bare, no rig binding) in the town's city.toml so the route resolves for every store at once:"
    detail "    [[agent]]"
    detail "    name = \"human\""
    detail "    max_active_sessions = 0"
    detail "max_active_sessions = 0 is load-bearing: a plain entry makes the supervisor spawn a \"human\" pool against the parked beads"
    detail "apply and reload: $writer --city \"$city\" && gc reload"
    exit 1
fi

# Present, so FindAgent resolves the route. Confirm it cannot spawn a pool:
# max_active_sessions reaches gc agent list --json as .pool.max.
human_max=$(printf '%s' "$roster" | jq -r '[.agents[]? | select((.qualified_name // .name) == "human") | (.pool.max // "unset")][0] // "unset"' 2>/dev/null)
if [ "$human_max" != "0" ]; then
    echo "the \"human\" route resolves, but its agent can spawn a pool (max_active_sessions=$human_max)"
    detail "FindAgent resolves the route, so stale-routed-config is silenced, but a non-zero max_active_sessions lets the supervisor spawn a \"human\" pool against the parked beads"
    detail "set max_active_sessions = 0 on the bare human agent in the town's city.toml, then: gc reload"
    exit 1
fi

echo "OK: the bare \"human\" route resolves to a config agent (max_active_sessions=0) — stale-routed-config cannot fire on gc.routed_to=human"
exit 0
