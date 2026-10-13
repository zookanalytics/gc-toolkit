#!/usr/bin/env bash
# merge — arm 2 of the merge cadence: the single writer of merged truth.
#   merge.sh [--deadline <epoch-secs>] [--cursor <file>]
# For each open pull_request anchor: pinned `gh pr view`, identity gates (right
# repo, not a fork), live anchor re-read (still open, still gating on
# pull_request, still naming this PR by number, url and head branch), then
# either the record for a PR already merged — landing and recording are two
# writes, and a pass killed between them leaves an anchor that says
# pull_request over a PR that landed — or, for an OPEN non-draft PR, the
# merge: validate in order: non-empty check_set (empty is never the 'none'
# opt-out — an unnormalized anchor holds); merge_hold; unanswered review
# comments (pr_posture, read OFF THE ANCHOR, never re-derived from GitHub
# here); one-anchor-per-PR (hold + escalate once — fail-closed defense; the
# structural check is doctor's); base == merged_target; every declared lane
# DERIVES green through lane-state.sh (no stored marker; a lane with no local
# review bead is backed by an operator's GitHub approval on the PR, the shared
# fallback); no unclosed rework/review child or open must-fix finding (metadata
# keys naming this PR AND dependency edges, the finding held by its own blocks
# edge; unreadable holds); no open visit on the anchor (finalize-gate.sh);
# approval (a UNIVERSAL merge rule armed for every PR, not a check_set member —
# satisfied only by a latest APPROVED from an account other than the city's,
# given at any commit, because an approval stands across later pushes until it
# is dismissed; dismissed reviews are dropped before each reviewer's latest is
# taken, so a dismissed approval does not count and a dismissed
# CHANGES_REQUESTED does not hide its author's older approval; a standing
# CHANGES_REQUESTED from any other account vetoes); mergeStateStatus CLEAN
# (UNSTABLE decided on required contexts only; an UNKNOWN, which is GitHub still
# computing it, read again within one budget per pass); generated/seed-audit
# current at the MERGE RESULT (its inputs re-hashed in the tree `git
# merge-tree` writes, so a render clobbered by a base that moved holds and
# escalates rather than landing). The FULL anchor-local authorization set is
# re-read immediately before the merge; any mismatch holds. `gh pr merge
# --squash --match-head-commit`, then ONE lifecycle transition --to merged
# --close. A failed record exits non-zero loudly and the anchor is recovered by
# the already-merged arm above on a later pass — that arm is here, and not left
# to pr-facts.sh alone, because the arms are ordered and a killed pass loses
# the later ones. A record that keeps failing is bounded rather than retried
# forever: record-failure-cap.sh counts the failures on the anchor and
# escalates past the cap, so a cause no later pass can clear reaches a person
# instead of one stderr line per pass.
# Visit order: anchors whose PR has left the open list, or could land this pass
# by everything read without a per-PR call (draft flag, anchor-local holds,
# approval, the merge state the posture arm recorded), are visited first and
# never paced; --deadline and --cursor pace the rest through a rotation.
# Caller: refinery-reconcile.sh, with BEADS_ACTOR projected to the refinery
# identity.
# Exits: 0 a pass ran, whatever it held, or there was no gh or no origin
# repository to merge into; 1 the check resolver is missing, the gating
# anchors could not be enumerated, a merged PR's record failed, or there is no
# gctk binary to run.
#
# `gctk merge` (services/gctk/internal/cli/merge.go) implements the pass, and
# this script execs it. The gctk-build order publishes the binary. With no
# binary to exec the pass exits 1, names that order, and merges nothing. That
# covers a fresh city before the order's first build and a city whose builds
# have never succeeded. A build that fails later leaves the last good binary in
# place, and that binary keeps answering.
set -u

# gctk-resolve.sh resolves the binary and execs `gctk merge`, or refuses the
# pass when there is none to run. It never returns here.
# shellcheck source=gctk-resolve.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/gctk-resolve.sh" || { echo "merge: cannot source gctk-resolve.sh beside this script" >&2; exit 1; }
gctk_require merge "$@"
