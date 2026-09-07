#!/bin/sh
# converse-backlog-repoint.sh — one-time converse-cutover migration (tk-4abhrt).
#
# Re-points every open bead still routed to the retired converse work-pool
# (an address ending in `/gc-toolkit.converse`) onto `gc.routed_to=human`, so it
# parks on the helm board's backlog instead of stranding on a pool that no
# longer runs. The board's gather selects a human anchor by the exact value
# `gc.routed_to == "human"` (services/helm/internal/source/beads.go), so `human`
# is the value that makes a parked visit visible to the operator.
#
# WHEN TO RUN: after the cutover PR lands and the `gc-helm engage` verb is live,
# and before (or as) the retired pool config leaves the running checkout. It is
# idempotent — a re-run re-points only what still carries the pool route — so a
# transient bead routed to the retired pool self-heals on the next run.
#
# It matches the POOL address (`gc-toolkit.converse`, bare or rig-qualified) and NOT the per-model
# manual sitting templates (`.../gc-toolkit.converse-opus|-fable|-codex`), whose
# addresses end in `-opus`/`-fable`/`-codex`.
#
# Usage: converse-backlog-repoint.sh [--rig <name>] [--apply]
#   Default is a DRY RUN: it prints what it would change and writes nothing.
#   --apply performs the re-point.
#   --rig  selects the rig store (default: the rig discovered from the cwd).
#
# The pack pool is deployed to more than one rig; run this once per rig that
# carries a backlog (at cutover time: gc-toolkit, and gascity when it resumes).
set -eu

RIG=""
APPLY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --rig=*)  RIG="${1#--rig=}"; shift ;;
        --rig)    shift; [ $# -gt 0 ] || { echo "converse-backlog-repoint: --rig requires a value" >&2; exit 2; }; RIG="$1"; shift ;;
        --apply)  APPLY=1; shift ;;
        -h|--help)
            awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
        *) echo "converse-backlog-repoint: unknown argument '$1'" >&2; exit 2 ;;
    esac
done

command -v gc >/dev/null 2>&1 || { echo "converse-backlog-repoint: gc is required" >&2; exit 3; }
command -v jq >/dev/null 2>&1 || { echo "converse-backlog-repoint: jq is required" >&2; exit 3; }

RIG_FLAG=""
[ -n "$RIG" ] && RIG_FLAG="--rig $RIG"

# The retired pool's address is `<rig>/gc-toolkit.converse`, or the BARE
# `gc-toolkit.converse` from a rig-less caller on code that predates escalate's
# route gate (its own tests seed that form). Match both so every rig-qualified
# form is caught, and no converse-* manual template is.
# shellcheck disable=SC2086  # $RIG_FLAG is 0 or 2 space-free fields, intentionally split.
LISTING=$(gc bd list $RIG_FLAG --status open,in_progress,blocked --limit 0 --json 2>/dev/null) \
    || { echo "converse-backlog-repoint: 'gc bd list' failed for rig '${RIG:-<current>}'" >&2; exit 4; }

if ! printf '%s' "$LISTING" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "converse-backlog-repoint: 'gc bd list' did not answer a JSON array — refusing to guess" >&2
    exit 4
fi

TARGETS=$(printf '%s' "$LISTING" | jq -r '
    [ .[] | select(((.metadata // {})["gc.routed_to"] // "") | (. == "gc-toolkit.converse" or endswith("/gc-toolkit.converse"))) ]
    | .[] | "\(.id)\t\(.status)\t\((.metadata["task_kind"]) // "-")\t\(.metadata["gc.routed_to"])"')

if [ -z "$TARGETS" ]; then
    echo "converse-backlog-repoint: nothing routed to the retired converse pool in rig '${RIG:-<current>}' — already migrated."
    exit 0
fi

COUNT=$(printf '%s\n' "$TARGETS" | grep -c .)
echo "converse-backlog-repoint: rig '${RIG:-<current>}' — $COUNT bead(s) routed to the retired converse pool:"
printf '%s\n' "$TARGETS" | awk -F'\t' '{ by[$2"/"$3]++ } END { for (k in by) printf "    %4d  status/kind=%s\n", by[k], k }'

if [ "$APPLY" -ne 1 ]; then
    echo "converse-backlog-repoint: DRY RUN — re-run with --apply to set gc.routed_to=human on the above."
    exit 0
fi

printf '%s\n' "$TARGETS" | while IFS="$(printf '\t')" read -r id _; do
    [ -n "$id" ] || continue
    # A metadata write bypasses bd's claim guard, so an actively-held visit is
    # re-pointed too: the sitting holds it by assignee, not by route, and the
    # route change only stops a retired pool from ever offering it again.
    # shellcheck disable=SC2086
    if gc bd update "$id" $RIG_FLAG --set-metadata "gc.routed_to=human" >/dev/null 2>&1; then
        echo "    re-pointed $id -> human"
    else
        echo "    FAILED to re-point $id (re-run to retry)" >&2
    fi
done

# The while-loop runs in a pipeline subshell, so the outcome is re-derived from
# the store rather than carried out of the loop.
# shellcheck disable=SC2086
REMAIN=$(gc bd list $RIG_FLAG --status open,in_progress,blocked --limit 0 --json 2>/dev/null \
    | jq -r '[ .[] | select(((.metadata // {})["gc.routed_to"] // "") | (. == "gc-toolkit.converse" or endswith("/gc-toolkit.converse"))) ] | length' 2>/dev/null || echo "?")
if [ "$REMAIN" = "0" ]; then
    echo "converse-backlog-repoint: done — nothing remains on the retired converse pool in rig '${RIG:-<current>}'."
    exit 0
fi
echo "converse-backlog-repoint: $REMAIN bead(s) still on the retired pool in rig '${RIG:-<current>}' — re-run --apply to retry." >&2
exit 4
