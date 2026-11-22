#!/usr/bin/env bash
# review-passed-check.sh — the check of a review run's loop
# (formulas/mol-pr-review.toml, review-loop), and the run's final validate and
# record: whether the iteration that just closed passed, by the pass rule
# `gctk review passed` holds, and, when that iteration ends the loop, the run's
# result written before the loop closes. An iteration ends the loop when it
# passes, or when it is the loop's last attempt by the run's max_attempts var
# and does not pass, which Gas City closes as exhausted. --record writes the
# result on the bead that owns the PR, closes the asks the run answered, and
# files the review-loop-exhausted gate at an exhausted loop, running the pack's
# scripts from this directory.
#
# Gas City runs it in the control dispatcher after each iteration closes, with
# GC_BEAD_ID naming the iteration's bead and GC_ITERATION its number, from 1, a
# PATH of the directories of bd, gc, dolt and jq plus the system's, the store's
# connection env and GC_CITY_PATH set (formula-spec-v2.md, section 3.1). It
# takes no arguments.
#
# Exit: 0 passed, its result recorded · 1 not yet, so the next iteration runs,
#       or the last attempt's result recorded, so the loop ends exhausted ·
#       75 no verdict: the store did not answer, a record did not land, or
#       there is no gctk to ask, which re-runs the check without spending an
#       attempt.
set -uo pipefail

HERE="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gctk-resolve.sh
. "$HERE/gctk-resolve.sh" || { echo "review-passed-check: cannot source gctk-resolve.sh" >&2; exit 75; }
gctk=$(gctk_path) || { echo "review-passed-check: no gctk binary to judge the iteration with" >&2; exit 75; }
[ -n "${GC_BEAD_ID:-}" ] && [ -n "${GC_ITERATION:-}" ] \
    || { echo "review-passed-check: GC_BEAD_ID and GC_ITERATION name no iteration" >&2; exit 75; }
GCTK_SCRIPTS_DIR="$HERE" exec "$gctk" review passed "$GC_BEAD_ID" --iteration "$GC_ITERATION" --record
