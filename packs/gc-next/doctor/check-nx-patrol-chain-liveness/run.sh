#!/usr/bin/env bash
# check-nx-patrol-chain-liveness — the chain-shape guard (spec §4).
#
# gc-next's patrols are chains of routed cycle beads on disposable pool
# sessions; the chain, not any session, is the continuity. A dead chain is
# therefore silent by construction — nothing spawns, nothing complains —
# which is exactly why this check exists. B1 of the phase-2 technical
# review is the provenance: "a fresh import has no patrol bead and nothing
# ever spawns; any failed pour ends the chain permanently."
#
# For each expected chain: ERROR if no open cycle bead exists (dead —
# nx-patrol-anchor should have re-seeded it; if it has not, the order is
# not firing, which is the second thing to check). WARN if the newest open
# link is older than twice the anchor interval (stale — cycles are not
# turning) or if more than one link is open (doubled — two claimants will
# race one chain).
set -euo pipefail

STATUS=0
ANCHOR_INTERVAL_H="${GC_NX_ANCHOR_INTERVAL_H:-1}"
STALE_S=$(( ANCHOR_INTERVAL_H * 2 * 3600 ))
NOW=$(date +%s)

check_chain() { # check_chain <chain-tag> <scope-label>
  local chain="$1" label="$2"
  local rows
  rows=$(gc bd list --status=open --json 2>/dev/null \
    | jq --arg c "$chain" '[.[]? | select(.metadata["task_kind"] == "patrol-cycle" and .metadata["chain"] == $c)]' 2>/dev/null) || rows=""
  if [ -z "$rows" ]; then
    echo "WARN: chain '$chain' ($label): ledger unreadable — cannot certify liveness"
    STATUS=$(( STATUS == 2 ? 2 : 1 ))
    return
  fi
  local n newest_ts
  n=$(printf '%s' "$rows" | jq 'length')
  if [ "$n" -eq 0 ]; then
    echo "ERROR: chain '$chain' ($label) is DEAD — no open cycle bead; nx-patrol-anchor should re-seed it (is the order firing?)"
    STATUS=2
  elif [ "$n" -gt 1 ]; then
    echo "WARN: chain '$chain' ($label) is DOUBLED — $n open cycle beads; claimants will race"
    STATUS=$(( STATUS == 2 ? 2 : 1 ))
  else
    newest_ts=$(printf '%s' "$rows" | jq -r '.[0].created_at // empty' | xargs -I{} date -d {} +%s 2>/dev/null || echo "")
    if [ -n "$newest_ts" ] && [ $(( NOW - newest_ts )) -gt "$STALE_S" ]; then
      echo "WARN: chain '$chain' ($label) is STALE — newest link older than ${STALE_S}s; cycles are not turning"
      STATUS=$(( STATUS == 2 ? 2 : 1 ))
    fi
  fi
}

check_chain "land" "rig"
check_chain "health-rig" "rig"
check_chain "health-city" "city"

[ "$STATUS" -eq 0 ] && echo "OK: all patrol chains live"
exit "$STATUS"
