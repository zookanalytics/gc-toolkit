#!/usr/bin/env bash
# lifecycle.sh — the plain write of a bead's merge_result.
#   lifecycle.sh transition <bead-id> --to <value> [--expect <value>] [--set k=v]...
#     [--set-dated k=<value>@<oid>]... [--unset k]... [--assignee <a>]
#     [--route <rig>/<agent> | --keep-route] [--takeaway <text>] [--close]
#     [--append-notes <t>] [--json]
# transition: ONE atomic `gc bd update` carrying every field, whose exit is the
# transition's. --to sets merge_result, and --to unanchored clears it. It checks
# no edge between values: the doctor checks the beads after the write
# (doctor/check-closed-implies-landed, doctor/check-state-space).
# --expect is a compare-and-swap on the merge_result the bead carries, with
# unanchored for none.
# --set-dated writes a key in the dated shape <value>@<oid>@<since>, appending
# the third component under compare-and-preserve: the existing instant survives
# while value and oid both hold, and a change to either stamps a fresh one. The
# reconcile cadence re-derives the same verdict at the same head every few
# minutes, so a naive clock would restart a three-day wait on every pass.
# --to merged is a landing. The same write clears rejection_reason and
# blocked_reason, and records the work the landing shipped: gc.work_outcome=
# shipped, gc.work_commit (the merged_sha) and gc.work_branch (merged_target),
# each unless the call writes that key itself. A landing whose merged_sha is no
# object id, or that names no merged_target, records none of the three, and the
# bead keeps the record it already had.
# --route takes a rig-qualified <rig>/<agent>, or an empty value that clears the
# route, so a bare name such as `human` is refused. --keep-route writes no route
# at all, and is refused with --route. An --assignee "" write also clears the
# executor identity (gc.session_id, gc.session_name).
# --takeaway writes the triple (text/_at/_by) in the same atomic call, capped at
# 140 codepoints and refused when it normalizes to nothing.
# Callers: direct-merge-push.sh (the direct landing), pr-facts.sh and
# gate-ensure.sh.
# Exits: 0 ok; 1 --expect mismatch / bd refusal / usage, or no gctk binary to
# run; 2 the bead could not be read before the write, or a landed write could
# not be reported as JSON.
# CAVEAT (docs/gascity/routing-model.md, "Clearing an assignee can be refused"):
# clearing an assignee on a bead another actor holds in_progress is refused by
# bd, and the refusal drops the WHOLE atomic update — a caller that passes
# --assignee "" must hold the claim.
#
# `gctk lifecycle` (services/gctk/internal/cli/lifecycle.go) implements the
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
