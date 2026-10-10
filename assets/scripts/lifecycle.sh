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
# and merge_result move together). --to merged also requires a non-empty
# --set merged_sha, the landing the state names; a bead that never had a PR is
# no merge anchor and closes with a plain `gc bd close`. A state's declared
# routing rides in the same call unless --route is given: human states stamp
# gc.routed_to=human, and detached states clear it unless the bead already rests
# on the park route.
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

# gctk-resolve.sh resolves the binary and execs `gctk lifecycle`, or refuses the
# call when there is none to run. It never returns here.
# shellcheck source=gctk-resolve.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/gctk-resolve.sh" || { echo "lifecycle: cannot source gctk-resolve.sh beside this script" >&2; exit 1; }
gctk_require lifecycle "$@"
