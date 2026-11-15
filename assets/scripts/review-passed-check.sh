#!/usr/bin/env bash
# review-passed-check.sh — the check of a review run's loop
# (formulas/mol-pr-review.toml, review-loop): whether the iteration that just
# closed passed, by the pass rule `gctk review passed` holds.
#
# Gas City runs it in the control dispatcher after each iteration closes, with
# GC_BEAD_ID naming the iteration's bead and GC_ITERATION its number, from 1, a
# PATH of the directories of bd, gc, dolt and jq plus the system's, and
# GC_CITY_PATH set (formula-spec-v2.md, section 3.1). It takes no arguments.
#
# Exit: 0 passed · 1 not yet, so the next iteration runs · 75 no verdict: the
#       store did not answer, or there is no gctk to ask, which re-runs the
#       check without spending an attempt.
set -uo pipefail

HERE="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gctk-resolve.sh
. "$HERE/gctk-resolve.sh" || { echo "review-passed-check: cannot source gctk-resolve.sh" >&2; exit 75; }
gctk=$(gctk_path) || { echo "review-passed-check: no gctk binary to judge the iteration with" >&2; exit 75; }
[ -n "${GC_BEAD_ID:-}" ] && [ -n "${GC_ITERATION:-}" ] \
    || { echo "review-passed-check: GC_BEAD_ID and GC_ITERATION name no iteration" >&2; exit 75; }
exec "$gctk" review passed "$GC_BEAD_ID" --iteration "$GC_ITERATION"
