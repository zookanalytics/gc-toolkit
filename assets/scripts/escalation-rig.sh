#!/usr/bin/env bash
# escalation-rig.sh — name the rig whose store holds a bead.
#   escalation-rig.sh <bead-id>
# A visit lands in the store GC_RIG selects, and only a pool that reads that
# store can claim it, so a caller escalating about a bead needs that bead's own
# rig. Its route does not carry one: the shipped contracts route to a bare
# identity with no rig segment. An ambient default does not carry one either:
# it names whatever store the caller happens to sit in, which for a city-scoped
# agent is not the subject's. The id prefix is the derivation, and
# bead-store.sh is where it is resolved — the same guard the destructive gates
# ask, so an escalation and a prune agree about which store owns a bead.
# Anything but exactly one rig carrying that prefix is a refusal: a guessed
# store files the visit where its subject cannot be reached, which reads as an
# escalation nobody ever receives.
# Exit: 0 resolved, rig name on stdout · 1 unresolvable · 2 usage
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BEAD_STORE="${GC_BEAD_STORE_TOOL:-$HERE/bead-store.sh}"

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

[ -x "$BEAD_STORE" ] || {
  echo "escalation-rig: cannot execute $BEAD_STORE, so the store for $BEAD is unproven and nothing may be filed against it" >&2
  exit 1
}

# bead-store.sh separates a prefix no rig carries from a store it could not
# read, which have different repairs; both are the one refusal here, because a
# caller binding GC_RIG=$(...) has the same nothing to bind either way.
"$BEAD_STORE" "$BEAD" || exit 1
