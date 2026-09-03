#!/usr/bin/env bash
# pool-route.sh — name the route a pool offer is actually claimed on.
#   pool-route.sh <pool-name>        prints the validated route
#   pool-route.sh --verdict <route>  prints ok|unknown|cross-rig|no-identity|
#                                    unbound-store
# A pool offer matches by exact byte equality (gascity hookClaimMatchesRoute),
# so a well-formed name no agent carries is claimed by nobody while every stamp
# of it still reads back clean. GC_RIG picks BOTH the store `gc bd` writes to
# and the rig segment a rig-scoped pool must carry, so a caller that builds the
# route out of GC_RIG alone turns a missing rig into a bare name addressing
# nobody. A <pool-name> already carrying a '<rig>/' segment is taken as given;
# a bare one is qualified with GC_RIG when it is set. The store half stays the
# caller's: only the caller can move where its bead lands, so a route this
# script cannot reconcile with the caller's store is refused, never repaired.
# Only proof refuses: an unreadable agent set returns the route with a loud
# UNVERIFIED warning, because a route nobody could check still beats an outage.
# Callers: the gate-visit copies (formulas/mol-visit.toml and every consumer),
# escalate.sh, signoff.sh's rework route.
# Exit: 0 route on stdout · 1 nothing routable · 2 usage
set -uo pipefail

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

usage() {
  cat >&2 <<'U'
usage: pool-route.sh <pool-name>
       pool-route.sh --verdict <route>

  <pool-name>  the pool to route to: '<binding>.<pool>', qualified with GC_RIG
               when that is set, or '<rig>/<binding>.<pool>' taken as given.
               The validated route is printed; nothing is printed on a refusal
  --verdict    classify a route that already exists, for a caller deciding
               whether a stamp it did not write still addresses someone.
               Prints one of ok, unknown (agent set unreadable), cross-rig,
               no-identity, unbound-store (no GC_RIG, so a rig-qualified route
               has no store to be reconciled with) — and exits 0 for all five:
               this is a reading, not a judgment
U
}

warn() { echo "pool-route: $*" >&2; }

# The live agent identity set, read once. Empty means UNREADABLE, never "no
# agents" — an empty answer is the absence of proof, not a refusal.
AGENT_IDS=""; AGENT_IDS_READ=0
agent_ids() {
  if [ "$AGENT_IDS_READ" = 0 ]; then
    AGENT_IDS_READ=1
    AGENT_IDS=$(if command -v timeout >/dev/null 2>&1; then timeout 15 gc agent list --json 2>/dev/null
                else gc agent list --json 2>/dev/null; fi \
      | scrub \
      | jq -c '[.agents[]? | (.qualified_name // "") | select(. != "")]' 2>/dev/null)
    [ "$AGENT_IDS" = "[]" ] && AGENT_IDS=""
  fi
  printf '%s' "$AGENT_IDS"
}

# ok | unknown | cross-rig | no-identity.
route_verdict() {
  local route="$1" rig_seg ids
  [ -z "$route" ] && { printf 'no-identity'; return 0; }
  # `human` is the city's durable "the operator owns it; no agent will take
  # it" marker (services/helm/README.md), so it is already held by the reader
  # a caller wants — not a pool name that failed to resolve.
  [ "$route" = "human" ] && { printf 'ok'; return 0; }
  rig_seg="${route%%/*}"; [ "$rig_seg" = "$route" ] && rig_seg=""
  # A route naming another rig addresses a pool that never reads the store
  # this caller's bead lands in, so it is unreachable however live it is.
  if [ -n "${GC_RIG:-}" ] && [ -n "$rig_seg" ] && [ "$rig_seg" != "$GC_RIG" ]; then
    printf 'cross-rig'; return 0
  fi
  ids=$(agent_ids)
  [ -z "$ids" ] && { printf 'unknown'; return 0; }
  printf '%s' "$ids" | jq -e --arg r "$route" 'index($r) != null' >/dev/null 2>&1 \
    && printf 'ok' || printf 'no-identity'
}

# The reading for a route the caller did NOT write, which asks a second
# question: does that route address somebody who reads the store the row was
# read from. GC_RIG names that store, so with GC_RIG unset a rig-qualified
# route has nothing to be reconciled against — the row came from whatever
# store the ambient environment picked, and a rig-scoped pool never lists
# another one. Calling it ok there buys the same silence the bare name does:
# the caller concludes somebody was asked, and nobody was. Only the caller can
# name its store, so this refuses the reading rather than picking a rig.
existing_route_verdict() {
  local route="$1" rig_seg
  rig_seg="${route%%/*}"; [ "$rig_seg" = "$route" ] && rig_seg=""
  if [ -z "${GC_RIG:-}" ] && [ -n "$rig_seg" ]; then
    printf 'unbound-store'
    return 0
  fi
  route_verdict "$route"
}

case "${1:-}" in
  --verdict)
    [ "$#" -eq 2 ] || { usage; exit 2; }
    existing_route_verdict "$2"; echo
    exit 0 ;;
  -h|--help) usage; exit 2 ;;
  -*) warn "unknown argument '$1'"; usage; exit 2 ;;
  "") usage; exit 2 ;;
esac
[ "$#" -eq 1 ] || { usage; exit 2; }

NAME="$1"
# Already rig-qualified: the caller named the store as well as the pool. Which
# of the two it was decides the repair a refusal can honestly suggest.
case "$NAME" in
  */*) ROUTE="$NAME"; QUALIFIED=1 ;;
  *)   ROUTE="${GC_RIG:+$GC_RIG/}$NAME"; QUALIFIED=0 ;;
esac

case "$(route_verdict "$ROUTE")" in
  ok)
    printf '%s\n' "$ROUTE"
    exit 0 ;;
  unknown)
    warn "could not read the live agent set (\`gc agent list --json\`); returning '$ROUTE' UNVERIFIED — confirm a pool claims it"
    printf '%s\n' "$ROUTE"
    exit 0 ;;
  cross-rig)
    warn "route '$ROUTE' is scoped to rig '${ROUTE%%/*}' but the caller writes to the '${GC_RIG:-}' store, which that pool never reads. Name a '${GC_RIG:-}/' pool, or run with GC_RIG=${ROUTE%%/*} so the store and the route agree."
    exit 1 ;;
esac

NEAR=$(agent_ids | jq -r --arg r "$ROUTE" \
  '[.[] | select(endswith("/" + $r))] | join(", ")' 2>/dev/null)
warn "route '$ROUTE' matches no live agent identity — nothing addressed (a route no pool claims reads back clean forever)."
[ -n "$NEAR" ] && warn "  live rig-qualified forms of that name: $NEAR"
if [ "$QUALIFIED" = 1 ]; then
  warn "  repair: name a pool that exists — this one was given rig-qualified, so nothing here can supply the missing half."
else
  warn "  repair: name the pool as <rig>/$NAME, or run with GC_RIG set so the bare name qualifies itself."
fi
exit 1
