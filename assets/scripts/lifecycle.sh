#!/usr/bin/env bash
# lifecycle.sh — THE writer of anchor lifecycle transitions (lifecycle/lifecycle.toml).
#   lifecycle.sh transition <bead-id> --to <state> [--expect <state>] [--set k=v]...
#     [--set-dated k=<value>@<oid>]... [--unset k]... [--assignee <a>] [--route <rig>/<agent>|human]
#     [--takeaway <text>] [--close] [--append-notes <t>] [--json]
#   lifecycle.sh state <bead-id>
#   lifecycle.sh reopen <bead-id>
# transition: validate the edge against the declared machine, perform ONE atomic
# `gc bd update` carrying every field, re-read and verify each written field.
# --set-dated writes a key in the dated shape <value>@<oid>@<since>, appending
# the third component under compare-and-preserve: the existing instant survives
# while value and oid both hold, and a change to either stamps a fresh one. The
# reconcile cadence re-derives the same verdict at the same head every few
# minutes, so a naive clock would restart a three-day wait on every pass.
# --close only into a closed state, and a closed state requires --close (status
# and merge_result move together). A state's declared routing rides in the same
# call unless --route is given: human states stamp gc.routed_to=human, and
# detached states clear it unless the bead already rests on the park route.
# A detached state also clears the assignee of a bead still at status=open,
# unless --assignee is given; that is the unheld half of the same property. A
# human state also refuses an EMPTY --route: a bead waiting on a person has to
# name one, and routing to the park sentinel refuses without a takeaway — the
# board spends gc.takeaway as the row's NEEDS sentence, so a park with none
# reaches the operator saying no question was recorded. --takeaway writes the
# triple (text/_at/_by) in the same atomic call, capped at 140 codepoints and
# refused when it normalizes to nothing; a bead that already carries a takeaway
# satisfies the guard.
# reopen: repair a bead closed while merge_result is a NON-closed state — set
# status=open, merge_result untouched. Human-invoked only (docs/authority-map.md).
# Callers: pr-open.sh, merge.sh, pr-facts.sh, mol-refinery-patrol.
# Exits: 0 ok; 1 illegal edge / --expect mismatch / bd refusal / usage, or no
# gctk binary to run; 2 post-write verification mismatch (or unreadable bead).
# CAVEAT (docs/gascity-routing-model.md row 46): clearing an assignee on a bead
# another actor holds in_progress is refused by bd, and the refusal drops the
# WHOLE atomic update — a caller that passes --assignee "" must hold the claim.
# The detached-state clear reads the status for that reason and stops at open.
#
# `gctk lifecycle` (services/gctk/internal/cli/lifecycle.go) implements every
# verb above, and this script execs it. The gctk-build order publishes the
# binary. With no binary to exec the call exits 1, names that order, and writes
# nothing. That covers a fresh city before the order's first build and a city
# whose builds have never succeeded. A build that fails later leaves the last
# good binary in place, and that binary keeps answering.
set -u

# Resolution is EXPLICIT: $GCTK_BIN, else the city named by GC_CITY_PATH,
# GC_CITY or GC_CITY_ROOT — the same precedence boot-health.sh, doctor-sweep.sh
# and the tmux pickers read, and GC_CITY_PATH is the one the supervisor puts in
# an agent session — else the city `gc service list --json` reports. The
# listing is what the merge cadence itself needs: the order runner that execs
# refinery-reconcile.sh carries no city variable at all (docs/
# refinery-merge-cadence.md). Never a walk up from this file's own path — the
# hermetic suites run from a tree inside a live city, and a filesystem hunt
# would find that city's binary instead of the one a suite built from the tree
# under test.
#
# A city-resolved binary is not held to this checkout's services/gctk revision.
# There is no other implementation to prefer, so refusing a binary the build
# order has not yet replaced would turn the order's ~5m lag into a refusal of
# every transition. doctor/check-cadence-live and the board's PACK row report
# that lag instead.
GCTK_BIN="${GCTK_BIN:-}"
_gctk_named="$GCTK_BIN"
_gctk_city=""
if [ -z "$GCTK_BIN" ]; then
    _gctk_city="${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-}}}"
    if [ -z "$_gctk_city" ]; then
        _gctk_city="$(gc service list --json 2>/dev/null | jq -r '.city_path // empty' 2>/dev/null || true)"
    fi
    [ -n "$_gctk_city" ] && GCTK_BIN="$_gctk_city/.gc/services/gctk/bin/gctk"
fi
if [ "$GCTK_BIN" != "none" ] && [ -n "$GCTK_BIN" ] && [ -x "$GCTK_BIN" ]; then
    exec "$GCTK_BIN" lifecycle "$@"
fi

# Nothing to exec. Each arm names what is missing, writes nothing, and exits 1,
# the code every caller already reads as a refused transition.
if [ "$_gctk_named" = "none" ]; then
    echo "lifecycle: GCTK_BIN=none names no binary, and gctk lifecycle is the only implementation; nothing was written" >&2
elif [ -n "$_gctk_named" ]; then
    echo "lifecycle: GCTK_BIN=$_gctk_named is not an executable gctk binary; nothing was written" >&2
elif [ -z "$_gctk_city" ]; then
    echo "lifecycle: no city to find the gctk binary in — GC_CITY_PATH, GC_CITY and GC_CITY_ROOT are unset and \`gc service list --json\` named none. Set one of them, or GCTK_BIN; nothing was written" >&2
else
    echo "lifecycle: no gctk binary at $GCTK_BIN, so nothing was written. The gctk-build order (orders/gctk-build.toml) publishes it: a fresh city has one after the order's first build, $_gctk_city/.gc/services/gctk/build-status.json records why the last build failed, and assets/scripts/gc-gctk-build.sh builds it now" >&2
fi
exit 1
