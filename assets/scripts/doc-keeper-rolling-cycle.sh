#!/usr/bin/env bash
# doc-keeper-rolling-cycle.sh — discover or open the current rolling docs cycle.
#
# The doc-keeper machinery (epic tk-yw3zb) merges many small doc-update
# branches into ONE long-lived "rolling" pull request that the operator
# reviews and merges as a batch. This script is the idempotent entry point
# every doc-keeper formula calls at step 0 to resolve that cycle's target
# branch:
#
#   * If an open rolling PR exists, print its head branch and exit.
#   * If none exists, open the next cycle: branch from <base>, seed an empty
#     marker commit (so the tracking PR has a diff to open against), push,
#     open the long-lived "<branch> -> <base>" PR, and print the branch.
#
# The single line on stdout is the rolling target branch (e.g.
# "docs/rolling-7"). Everything else goes to stderr, so a caller can do:
#
#     target="$(assets/scripts/doc-keeper-rolling-cycle.sh)"
#     gc bd update "$bead" --set-metadata target="$target"
#
# mol-polecat-work then branches from that target and the refinery's existing
# `direct` mode fast-forwards each doc edit onto it — GitHub auto-updates the
# PR as the branch advances. NO convoy, NO new refinery mode: a plain
# long-lived branch + long-lived PR. (Supersedes the convoy-batching sketch
# in specs/tk-yw3zb.1/doc-keeper-architecture.md §3; full design in
# specs/tk-yw3zb.4/rolling-cycle-mechanism.md.)
#
# Idempotent and safe to call repeatedly or concurrently — see the spec's
# "Races and idempotency" section. Design bead: tk-yw3zb.4.
#
# Overridable for tests (defaults are the production constants — the
# [doc-keeper] config block was dropped in the epic rescope, so these are
# inlined here, not read from pack.toml):
#   DOC_KEEPER_CYCLE_REMOTE  git remote to push/query   (default: origin)
#   DOC_KEEPER_CYCLE_BASE    base branch the PR targets (default: main)
#   DOC_KEEPER_CYCLE_PREFIX  rolling branch name prefix (default: docs/rolling-)
set -euo pipefail

REMOTE="${DOC_KEEPER_CYCLE_REMOTE:-origin}"
BASE="${DOC_KEEPER_CYCLE_BASE:-main}"
PREFIX="${DOC_KEEPER_CYCLE_PREFIX:-docs/rolling-}"

log() { printf 'doc-keeper-rolling-cycle: %s\n' "$*" >&2; }
die() { log "$*"; exit 1; }

command -v gh >/dev/null 2>&1 || die "gh not found on PATH"
command -v jq >/dev/null 2>&1 || die "jq not found on PATH"

# Pull the trailing rolling-cycle numbers out of a `gh pr list --json` blob and
# reduce them with a jq verb (min for discovery, max for numbering). Branches
# whose suffix is not a plain integer are ignored — only this script mints the
# names, so anything else is noise.
reduce_cycle_numbers() { # <jq-reduce-verb>  (reads gh JSON on stdin)
    jq -r --arg p "$PREFIX" --arg verb "$1" '
        [ .[].headRefName
          | select(startswith($p))
          | ltrimstr($p)
          | select(test("^[0-9]+$"))
          | tonumber ]
        | if $verb == "max" then (max // 0)
          else (min // -1) end'
}

# DISCOVER: the lowest-numbered OPEN rolling PR, or "" if none. Lowest-N is the
# convergence tiebreaker — if a race ever leaves two cycles open at once, every
# caller picks the same one and the operator closes the stray.
#
# A gh/jq failure is NOT "no open cycle": reading an errored query as empty would
# open a duplicate. Keep the query and the reduce as separate statements so a
# real failure of either propagates (die) instead of being masked — only a
# clean, genuinely-empty result returns "". This is the "refuse to guess"
# contract, enforced at the query itself rather than a single upfront probe.
discover() {
    local json n
    json=$(gh pr list --base "$BASE" --state open --limit 200 \
            --json number,headRefName) \
        || die "gh pr list (open cycles) failed (auth/network?) — refusing to guess cycle state"
    n=$(printf '%s\n' "$json" | reduce_cycle_numbers min) \
        || die "could not parse open-cycle PR list — refusing to guess cycle state"
    [ "${n:--1}" -ge 0 ] && printf '%s%s' "$PREFIX" "$n"
    return 0
}

existing="$(discover)"
if [ -n "$existing" ]; then
    log "current cycle: $existing"
    printf '%s\n' "$existing"
    exit 0
fi

# CREATE: open the next cycle. Number from PR HISTORY only (`--state all`), not
# from live branches. This is what makes the mechanism self-healing:
#   * a merged or closed (abandoned) cycle keeps its number reserved, so the
#     next cycle never reuses it;
#   * a crashed creation (branch pushed but PR never opened) does NOT inflate
#     the count, so the retry recomputes the SAME number, the push is a no-op,
#     and the missing PR gets opened — the half-done cycle heals instead of
#     forking a duplicate.
# Two concurrent callers therefore compute the same number and converge.
git fetch "$REMOTE" "$BASE" --quiet 2>/dev/null || die "cannot fetch $REMOTE/$BASE"
# A gh/jq failure here is unknown history, NOT "no prior cycles": a false
# max_pr=0 would mint cycle 1 again and reuse a retired number. Propagate either
# failure (die) rather than falling back — the same "refuse to guess" contract
# discover() enforces for the open-cycle query.
all_json=$(gh pr list --base "$BASE" --state all --limit 400 \
            --json headRefName) \
    || die "gh pr list (cycle history) failed (auth/network?) — refusing to guess cycle state"
max_pr=$(printf '%s\n' "$all_json" | reduce_cycle_numbers max) \
    || die "could not parse cycle-history PR list — refusing to guess cycle state"
next=$((max_pr + 1))
branch="${PREFIX}${next}"
log "no open cycle; opening $branch (highest prior cycle: $max_pr)"

# Empty seed commit so the tracking PR has a diff to open against. commit-tree
# writes the commit object WITHOUT touching HEAD, the index, or the working
# tree, so this never disturbs the caller's checkout.
base_sha=$(git rev-parse "$REMOTE/$BASE")
seed=$(printf 'docs: open rolling cycle %s\n\nTracking commit for the doc-keeper rolling PR (specs/tk-yw3zb.4).\n' \
        "$next" | git commit-tree "${base_sha}^{tree}" -p "$base_sha")

# Push the branch. A failed push is only benign when the branch is ALREADY on
# the remote — the expected race: a concurrent racer or a crashed prior
# creation that got as far as pushing. If the push fails AND the branch is
# absent, that is a hard auth/network/branch-protection failure; refuse to
# return a cycle whose branch does not exist.
if git push "$REMOTE" "${seed}:refs/heads/${branch}" >/dev/null 2>&1; then
    log "pushed ${branch}"
elif [ -n "$(git ls-remote --heads "$REMOTE" "$branch" 2>/dev/null)" ]; then
    log "branch ${branch} already on ${REMOTE} — ensuring its PR"
else
    die "push of ${branch} failed and it is absent on ${REMOTE} (auth/network/branch protection?)"
fi

# Open the long-lived tracking PR. A failed create is only benign when an open
# PR for this branch ALREADY exists — a racer or the heal of a crashed
# creation. If create fails AND no open PR exists, that is a hard failure;
# refuse to return a cycle with no tracking PR.
if gh pr create --base "$BASE" --head "$branch" \
        --title "docs: rolling agent-brief cycle ${next}" \
        --body "$(cat <<EOF
Rolling doc-keeper cycle **${next}**.

This is a long-lived tracking PR. doc-keeper update beads merge onto
\`${branch}\` one focused doc edit at a time (refinery \`direct\` mode); GitHub
auto-updates this PR as the branch advances. Review and merge the batch when
the cycle looks complete — merging it ends cycle ${next}, and the next audit
opens cycle $((next + 1)).

Mechanism: specs/tk-yw3zb.4/rolling-cycle-mechanism.md
EOF
)" >/dev/null 2>&1; then
    log "opened tracking PR for ${branch}"
elif gh pr list --base "$BASE" --head "$branch" --state open --json number 2>/dev/null \
        | jq -e 'length > 0' >/dev/null; then
    log "PR for ${branch} already open — continuing"
else
    die "gh pr create for ${branch} failed and no open PR exists (auth/network/branch protection?)"
fi

# Return the canonical open cycle (lowest-N) so all racers converge on one
# answer even if a duplicate slipped through. The guards above already
# confirmed this branch and its PR exist, so discovery must see at least this
# cycle; an empty result means the remote state is inconsistent — fail rather
# than emit an unverified branch (the old `${final:-$branch}` fallback could
# print a cycle whose tracking PR never opened).
final="$(discover)"
[ -n "$final" ] || die "post-create verification failed: no open rolling PR found after creating ${branch}"
printf '%s\n' "$final"
