#!/usr/bin/env bash
# check-nx-patrol-chain-liveness — the chain-shape guard (spec §4).
#
# gc-next's patrols are chains of routed cycle beads on disposable pool
# sessions; the chain, not any session, is the continuity. A dead chain
# is silent by construction — nothing spawns, nothing complains — which
# is exactly why this check exists (phase-2 review B1: "a fresh import
# has no patrol bead and nothing ever spawns; any failed pour ends the
# chain permanently").
#
# Scope: the RIG chains only (land, health-rig), read from the ambient
# store this check runs against. The health-city chain is a stage-4
# activation (deviation D6, implementation-notes.md) and is not asserted
# here until it exists. When rig context cannot be established, the
# check reports OK-with-note rather than inventing a store to read.
#
# For each chain: ERROR if no open cycle bead exists (dead — the
# nx-patrol-anchor order should have re-seeded it; if it has not, the
# order is not firing, which is the second thing to check). WARN if the
# newest open link is older than twice the anchor interval (stale —
# cycles are not turning) or if more than one link is open (doubled —
# two claimants will race one chain).
set -uo pipefail

STATUS=0
ANCHOR_INTERVAL_H="${GC_NX_ANCHOR_INTERVAL_H:-1}"
STALE_S=$(( ANCHOR_INTERVAL_H * 2 * 3600 ))
NOW=$(date +%s)

if [ -z "${GC_RIG:-}" ] && [ -z "${GC_RIG_ROOT:-}" ]; then
  echo "OK: no rig context — rig-chain liveness is asserted per rig; city chain is stage-4 (D6)"
  exit 0
fi

check_chain() { # check_chain <chain-tag>
  local chain="$1"
  local rows n newest_epoch
  rows=$(gc bd list --status=open --json 2>/dev/null \
    | jq --arg c "$chain" '[.[]? | select(.metadata["task_kind"] == "patrol-cycle" and .metadata["chain"] == $c)]' 2>/dev/null) || rows=""
  if [ -z "$rows" ]; then
    echo "WARN: chain '$chain': ledger unreadable — cannot certify liveness"
    [ "$STATUS" -lt 1 ] && STATUS=1
    return
  fi
  n=$(printf '%s' "$rows" | jq 'length')
  if [ "$n" -eq 0 ]; then
    echo "ERROR: chain '$chain' is DEAD — no open cycle bead; nx-patrol-anchor should re-seed it (is the order firing?)"
    STATUS=2
  elif [ "$n" -gt 1 ]; then
    echo "WARN: chain '$chain' is DOUBLED — $n open cycle beads; claimants will race"
    [ "$STATUS" -lt 1 ] && STATUS=1
  else
    # Staleness via jq's ISO8601 parsing (portable — no GNU date -d);
    # newest across however bd list happens to order.
    newest_epoch=$(printf '%s' "$rows" \
      | jq '[.[].created_at // empty | try fromdateiso8601] | max // empty' 2>/dev/null)
    if [ -n "$newest_epoch" ] && [ "$newest_epoch" != "null" ] \
       && [ $(( NOW - ${newest_epoch%.*} )) -gt "$STALE_S" ]; then
      echo "WARN: chain '$chain' is STALE — newest link older than ${STALE_S}s; cycles are not turning"
      [ "$STATUS" -lt 1 ] && STATUS=1
    fi
  fi
}

check_chain "land"
check_chain "health-rig"

if [ "$STATUS" -eq 0 ]; then
  echo "OK: rig patrol chains live"
fi
exit "$STATUS"
