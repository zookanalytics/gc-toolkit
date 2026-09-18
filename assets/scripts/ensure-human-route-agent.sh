#!/usr/bin/env bash
# ensure-human-route-agent.sh — ensure the town city.toml declares the bare
# "human" route agent.
#
# gc-toolkit parks operator-owned work with gc.routed_to=human
# (lifecycle/lifecycle.toml park_route). Core resolves a bare route only against
# an agent whose QualifiedName is exactly "human"; a rig-imported agent is
# binding-prefixed (gc-toolkit.human) and does not match, so the declaration has
# to be a TOP-LEVEL [[agent]] in the town's own city.toml:
#
#     [[agent]]
#     name = "human"
#     max_active_sessions = 0
#
# max_active_sessions = 0 is load-bearing: a plain entry makes the supervisor
# spawn a "human" pool against the parked beads. Without this agent, core's
# session-model doctor check reports stale-routed-config on every parked bead;
# doctor/check-human-route-configured is the read-only detector that names this
# script as its remedy.
#
# Idempotent: appends the stanza only when the file has no bare [[agent]] block
# named "human" — a [[patches.agent]] does not count, it patches an imported
# agent rather than declaring the bare one. Writes atomically (temp + rename)
# and leaves existing content untouched. Does NOT reload: applying the change to
# the running city is `gc reload`, the operator's step.
#
# Usage: ensure-human-route-agent.sh [--city <path>] [--check]
#   --city   town root holding city.toml (default: $GC_CITY_PATH, then $GC_CITY)
#   --check  report only, write nothing (exit 0 present, 1 absent, 2 error)

set -u

city="${GC_CITY_PATH:-${GC_CITY:-}}"
check_only=0
while [ $# -gt 0 ]; do
    case "$1" in
        --city) city="${2:-}"; shift 2 ;;
        --check) check_only=1; shift ;;
        -h|--help)
            echo "Usage: ensure-human-route-agent.sh [--city <path>] [--check]"
            echo "  Ensure the town city.toml declares the bare \"human\" route agent"
            echo "  (top-level [[agent]] name=\"human\", max_active_sessions=0)."
            echo "  --city   town root holding city.toml (default: \$GC_CITY_PATH, then \$GC_CITY)"
            echo "  --check  report only, write nothing (exit 0 present, 1 absent, 2 error)"
            exit 0 ;;
        *) echo "ensure-human-route-agent: unknown argument: $1" >&2; exit 2 ;;
    esac
done

if [ -z "$city" ]; then
    echo "ensure-human-route-agent: no city in scope (pass --city or set GC_CITY_PATH)" >&2
    exit 2
fi
cfg="$city/city.toml"
if [ ! -f "$cfg" ]; then
    echo "ensure-human-route-agent: no city.toml at $cfg" >&2
    exit 2
fi

# A bare [[agent]] block (exactly "[[agent]]", not "[[patches.agent]]" or any
# other array-of-tables) whose name is "human". Keys on the double-quoted form,
# which is what this script writes and what the config uses.
has_bare_human() {
    awk '
        /^[[:space:]]*\[\[agent\]\][[:space:]]*$/ { inblk=1; next }
        /^[[:space:]]*\[/                         { inblk=0 }
        inblk && /^[[:space:]]*name[[:space:]]*=[[:space:]]*"human"[[:space:]]*$/ { found=1 }
        END { exit(found ? 0 : 1) }
    ' "$1"
}

if has_bare_human "$cfg"; then
    echo "OK: $cfg already declares the bare \"human\" route agent — no change"
    exit 0
fi
if [ "$check_only" -eq 1 ]; then
    echo "MISSING: $cfg has no bare \"human\" route agent"
    echo "  - run without --check to append it, then: gc reload"
    exit 1
fi

tmp="$(mktemp "${TMPDIR:-/tmp}/gctk-ensure-human-route.XXXXXX")" || { echo "ensure-human-route-agent: mktemp failed" >&2; exit 2; }
trap 'rm -f "$tmp"' EXIT
cat "$cfg" > "$tmp" || { echo "ensure-human-route-agent: could not read $cfg" >&2; exit 2; }
# One blank line before the stanza, only when the file does not already end with
# one, so re-runs stay diff-clean.
[ -n "$(tail -c1 "$tmp")" ] && printf '\n' >> "$tmp"
cat >> "$tmp" <<'STANZA'

# Resolves the bare gc.routed_to=human park route so core's session-model
# doctor check does not report stale-routed-config on operator-owned work.
# max_active_sessions = 0 keeps the supervisor from spawning a "human" pool.
[[agent]]
name = "human"
max_active_sessions = 0
STANZA
mv "$tmp" "$cfg" || { echo "ensure-human-route-agent: could not write $cfg" >&2; exit 2; }
trap - EXIT
echo "APPENDED the bare \"human\" route agent to $cfg"
echo "  - now run: gc reload"
exit 0
