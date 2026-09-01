#!/usr/bin/env bash
# escalation-rig.sh — name the rig whose store holds a bead.
#   escalation-rig.sh <bead-id>
# A visit lands in the store GC_RIG selects, and only a pool that reads that
# store can claim it, so a caller escalating about a bead needs that bead's own
# rig. Its route does not carry one: the shipped contracts route to a bare
# identity with no rig segment. An ambient default does not carry one either:
# it names whatever store the caller happens to sit in, which for a city-scoped
# agent is not the subject's. The id prefix is the derivation, resolved through
# `gc rig list`.
# Anything but exactly one rig carrying that prefix is a refusal: a guessed
# store files the visit where its subject cannot be reached, which reads as an
# escalation nobody ever receives.
# Exit: 0 resolved, rig name on stdout · 1 unresolvable · 2 usage
set -uo pipefail

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

usage() {
  cat >&2 <<'U'
usage: escalation-rig.sh <bead-id>

Prints the rig name whose store holds <bead-id>, derived from the id prefix
through `gc rig list`. Bind it as GC_RIG for the escalate.sh call so the visit
lands in the store its subject lives in and routes to a pool that reads it.
U
}

BEAD="${1:-}"
[ "$#" -eq 1 ] && [ -n "$BEAD" ] || { usage; exit 2; }
case "$BEAD" in -*) usage; exit 2 ;; esac

PREFIX="${BEAD%%-*}"
[ -n "$PREFIX" ] && [ "$PREFIX" != "$BEAD" ] || {
  echo "escalation-rig: '$BEAD' has no '<prefix>-' segment to resolve a store from" >&2
  exit 1
}

RIGS=$(if command -v timeout >/dev/null 2>&1; then timeout 15 gc rig list --json 2>/dev/null
       else gc rig list --json 2>/dev/null; fi | scrub)
NAMES=$(printf '%s' "$RIGS" | jq -r --arg p "$PREFIX" '.rigs[]? | select(.prefix == $p) | .name' 2>/dev/null)
COUNT=$(printf '%s' "$NAMES" | grep -c . || true)

if [ "$COUNT" = "1" ]; then
  printf '%s\n' "$NAMES"
  exit 0
fi

# Empty means UNREADABLE as often as it means "no such prefix", and the two
# have different repairs, so they are reported apart.
if [ -z "$RIGS" ]; then
  echo "escalation-rig: could not read \`gc rig list --json\` — the store for $BEAD is unproven, so nothing may be filed against it" >&2
elif [ "$COUNT" = "0" ]; then
  echo "escalation-rig: no rig carries the prefix '$PREFIX' (from $BEAD); \`gc rig list\` has $(printf '%s' "$RIGS" | jq -r '[.rigs[]?.prefix] | join(", ")' 2>/dev/null)" >&2
else
  echo "escalation-rig: prefix '$PREFIX' (from $BEAD) is carried by $COUNT rigs ($(printf '%s' "$NAMES" | tr '\n' ' ')) — pass the subject's rig explicitly" >&2
fi
exit 1
