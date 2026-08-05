#!/bin/sh
# nx-patrol-anchor.sh — idempotently re-seed dead patrol chains.
# (The repair half; detection is doctor/check-nx-patrol-chain-liveness.)
#
# For each chain expected in this store: if no open cycle bead carries
# (task_kind=patrol-cycle, chain=<tag>), file one, routed to the chain's
# pool by DIRECT metadata stamp — stamp-don't-sling, because a bare sling
# under a city default_sling_formula is a silent Lane-4 attach that
# routes nothing (docs/gascity-routing-model.md).
set -eu

seed_chain() { # seed_chain <chain-tag> <pool> <scope-label>
  chain="$1"; pool="$2"; label="$3"
  n=$(gc bd list --status=open --json 2>/dev/null \
    | jq --arg c "$chain" '[.[]? | select(.metadata["task_kind"] == "patrol-cycle" and .metadata["chain"] == $c)] | length' 2>/dev/null) || n=""
  if [ -z "$n" ]; then
    echo "nx-patrol-anchor: ledger unreadable for chain '$chain'; not seeding (cannot certify dead)" >&2
    return 0
  fi
  if [ "$n" -eq 0 ]; then
    B=$(gc bd create --title "patrol-${chain%%-*} cycle ($label)" --json 2>/dev/null | jq -r '.[0].id // empty')
    if [ -n "$B" ]; then
      gc bd update "$B" --set-metadata "gc.routed_to=$pool,task_kind=patrol-cycle,chain=$chain" \
        && echo "nx-patrol-anchor: re-seeded chain '$chain' as $B" \
        || echo "nx-patrol-anchor: created $B but could not stamp routing — chain '$chain' still dead" >&2
    else
      echo "nx-patrol-anchor: could not create cycle bead for chain '$chain'" >&2
    fi
  fi
}

# Rig-store chains; the city expansion of the order seeds health-city in
# the city store with the same idempotent logic.
if [ -n "${GC_RIG:-}" ]; then
  seed_chain "land"        "gc-next.lander" "rig"
  seed_chain "health-rig"  "gc-next.sentry" "rig"
else
  seed_chain "health-city" "gc-next.sentry" "city"
fi
