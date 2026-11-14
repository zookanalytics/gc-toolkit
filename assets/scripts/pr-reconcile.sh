#!/usr/bin/env bash
# pr-reconcile.sh — one run of the landing order over this rig's pending
# records, for orders/pr-reconcile.toml.
#   pr-reconcile.sh [gctk pr reconcile's flags]
#
# `gctk pr reconcile` (services/gctk/internal/cli/prland.go) is the run: it reads
# each PR the refinery recorded as pending, merges a ready one with its head
# pinned, and closes its bead once the merge commit is on the target. This
# script names the refinery the run acts for, which the order's environment does
# not carry: the agent the roster places in $GC_RIG under the name refinery
# (resolve-route.sh), whose name carries the binding the rig imports the pack
# under. A run acts only on a bead still assigned to that refinery, and treats
# any other marked bead as released, so a roster that does not read runs
# nothing and exits 2, for the next tick to try again. A rig whose roster names
# no refinery has no publication to read, so its run says so and exits 0.
#
# Then it execs the run through gctk-resolve.sh, which finds the binary from an
# environment with no city variable and exports the scripts directory the run
# reads the definition of feedback and human-gate.sh from. With no binary to
# exec, the call exits 1 and names the gctk-build order.
set -u

HERE="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

REFINERY=""
RC=0
REFINERY="$("$HERE/resolve-route.sh" refinery 2>/dev/null)" || RC=$?
case "$RC" in
    0) ;;
    1) echo "pr-reconcile: the roster places no refinery in rig ${GC_RIG:-?}, so no record here has a publisher; nothing to read"
       exit 0 ;;
    *) echo "pr-reconcile: the roster did not read (resolve-route.sh exit $RC), so the run cannot tell the refinery's beads from released ones; nothing was read" >&2
       exit 2 ;;
esac

# shellcheck source=gctk-resolve.sh
. "$HERE/gctk-resolve.sh" || { echo "pr-reconcile: cannot source gctk-resolve.sh beside this script" >&2; exit 1; }
gctk_require pr reconcile --refinery "$REFINERY" "$@"
