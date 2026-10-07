#!/usr/bin/env bash
# escalation-rig.sh — name the store that holds a bead.
#   escalation-rig.sh <bead-id>        the rig whose store holds it
#   escalation-rig.sh --db <bead-id>   that store's path, <rig path>/.beads
# A visit about a bead belongs in that bead's own store, beside the subject its
# tracks edge points at. Its route does not carry that store: the shipped
# contracts route to a bare identity with no rig segment. An ambient default
# does not carry it either: it names whatever store the caller happens to sit
# in, which for a city-scoped agent is not the subject's. The id prefix is the
# derivation, and bead-store.sh is where it is resolved — the same guard the
# destructive gates ask, so an escalation and a prune agree about which store
# owns a bead.
# The rig name does not select every store. `gc bd` honors GC_RIG only when it
# names a bound rig, and the city's own store is not one: GC_RIG set to the
# city's rig name draws a warning and is ignored, and the call answers from the
# caller's working directory. The --db path selects every store, the city's
# included, and escalate.sh pins its board-route reads and writes to it.
# Anything but exactly one rig carrying that prefix is a refusal: a guessed
# store files the visit where its subject cannot be reached, which reads as an
# escalation nobody ever receives. --db also refuses a rig that reports no
# path, since there is no store to pin.
# Exit: 0 resolved, answer on stdout · 1 the subject names no placeable bead
# — no <prefix>-<id> shape, or a prefix the readable rig set does not carry · 2
# usage · 3 unproven — bead-store.sh could not be run, the rig set was
# unreadable, the prefix is carried by two rigs, or (--db) the rig carrying it
# reports no path. 1 is a proof, so only bead-store.sh's own answer may exit 1;
# a helper that cannot be run has proven nothing and exits 3. A caller that
# only binds GC_RIG treats 1 and 3 alike (nothing to bind); one that must act
# differently on a non-bead subject than on an unreadable store reads them
# apart.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BEAD_STORE="${GC_BEAD_STORE_TOOL:-$HERE/bead-store.sh}"

usage() {
  cat >&2 <<'U'
usage: escalation-rig.sh [--db] <bead-id>

Prints the rig name whose store holds <bead-id>, derived from the id prefix
through `gc rig list`. With --db, prints that store's path (<rig path>/.beads)
instead: the form `gc bd --db` takes, which reaches every store, the city's
included. `gc bd` ignores the city's rig name as GC_RIG.
U
}

MODE=""
case "${1:-}" in
  --db) MODE=--db; shift ;;
esac
BEAD="${1:-}"
[ "$#" -eq 1 ] && [ -n "$BEAD" ] || { usage; exit 2; }
case "$BEAD" in -*) usage; exit 2 ;; esac

[ -x "$BEAD_STORE" ] || {
  echo "escalation-rig: cannot execute $BEAD_STORE, so the store for $BEAD is unproven and nothing may be filed against it" >&2
  exit 3
}

# bead-store.sh separates a prefix no rig carries (exit 1) from a store it could
# not read (exit 3), which have different repairs. Its exit code passes straight
# through: a caller binding GC_RIG=$(...) or --db "$(...)" has the same nothing
# to bind for either, but escalate.sh reads exit 1 as a subject that is provably
# no bead (redirect it to the triage subject) and exit 3 as a possibly-real bead
# whose store is unproven (fail closed).
"$BEAD_STORE" ${MODE:+"$MODE"} "$BEAD"
