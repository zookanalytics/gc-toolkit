#!/usr/bin/env bash
# check-nx-lander-single-writer — flags >1 live lander session per rig.
#
# The lander is a demand-scaled pool capped at max_active_sessions=1. The
# cap binds only the controller's desired-state math: `gc session new
# <pool-template>` spawns an extra instance beside it, and Tier-1/2 claim
# queries match the shared identity strings, so a duplicate co-owns any
# assigned gating anchor (docs/gascity-agents.md, the duplicate-session
# work-ownership footgun; spec §4). Detect only.
set -uo pipefail

# Bucket by the rig-qualified TEMPLATE string, the documented aggregation
# key (docs/gascity-agents.md: counting by session name conflates rigs;
# template carries the rig qualifier for rig-scoped pools). A trailing
# instance suffix (-N) is stripped so pool slots of one template bucket
# together.
DUPES=$(gc session list --json 2>/dev/null \
  | jq -r '[(.sessions // [])[]
            | select(.state == "active")
            | (.template // .name // "") as $t
            | select($t | test("(^|[./])lander(-[0-9]+)?$"))
            | ($t | sub("-[0-9]+$"; ""))]
           | group_by(.) | map(select(length > 1))
           | .[] | "\(.[0]): \(length) live lander sessions"' 2>/dev/null) || {
  echo "WARN: session list unreadable — cannot certify lander singleton"
  exit 1
}

if [ -n "$DUPES" ]; then
  echo "ERROR: lander duplicated — the merge queue has co-owners:"
  printf '%s\n' "$DUPES"
  echo "Remedy: drain the manual instance; never 'gc session new' a lander (its prompt and spec §4 ban it)."
  exit 2
fi
echo "OK: at most one live lander per rig"
