#!/usr/bin/env bash
# reconcile-rig-checkouts — keep the live rigs/* checkouts advanced to origin.
#
# The live rigs/* checkouts are what the runtime executes (pack
# source = "rigs/<rig>"); the refinery merges PRs via its own clone, so a
# merged PR is NOT live until the checkout syncs. For each rig this does
# `git fetch origin && git merge --ff-only origin/<default>`.
#
# --ff-only is safe by construction: it advances only on a clean fast-forward,
# preserves a non-conflicting dirty file for free, and REFUSES (mutates
# nothing) on any divergence or conflicting dirty file. So this ships enabled —
# it cannot clobber work.
#
# When --ff-only refuses, the divergence is almost always SHA churn from an
# upstream rebase/squash/force-push: the live rigs/* checkout is a pure
# deployment mirror (commits are authored in worktrees and the refinery clone,
# never here), so its tracked content is already fully represented in origin.
# That case is provably lossless to reset, so the refusal branch first tries to
# auto-heal. The reset runs only when every check holds, and fails closed
# (escalates, mutates nothing) on anything it cannot prove:
#   - git cherry (patch-id) finds no unique local commit, so a rebased or
#     squashed commit with a new SHA still matches;
#   - git rev-list --merges finds no merge commit unique to local — git cherry
#     ignores merges, so a local merge's tree content is not provably upstream
#     and the guard refuses rather than reset it away;
#   - git status --porcelain is readable (a failed read is not proof of a clean
#     tree), and no dirty tracked path carries local-only content: its working
#     tree differs from the remote, or its staged index matches neither the
#     remote nor the committed HEAD.
# It then resets --hard to the remote (untracked files are preserved) and closes
# the divergence bead. Set RECONCILE_NO_AUTOHEAL=1 to disable this and escalate
# every divergence instead.
#
# A genuine divergence — a unique local commit, or a tracked change not yet
# upstream — fails that guard and takes the exception path: the checkout is
# left untouched, one idempotent bead per blocked rig records the divergence,
# and escalate.sh raises it so someone actually acts.
#
# The escalation must never rot silently, which is the whole reason this script
# exists: a stalled deploy has to reach someone. So a blocked rig is NOT handed
# to a fixed agent address — an address no agent holds is a bead nobody works,
# and a nudge into the void is worse than no safety net. The per-rig bead is the
# durable, self-healing SUBJECT: it carries the diagnosis and auto-closes when
# the rig next fast-forwards cleanly. escalate.sh then files a board-visible
# visit that tracks it. escalate.sh proves its route against the live agent set,
# exits non-zero rather than escalate into the void, and defaults to the human
# helm board, which resolves in every city. Set RECONCILE_ESCALATION_POOL to a
# rig-qualified pool to route the visit to a coordination agent instead; a pool
# that does not resolve falls back to the human board.
#
# Runs as an exec order (no LLM, no agent, no wisp).
set -euo pipefail

warn() { echo "reconcile-rig-checkouts: $*" >&2; }

SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
ESCALATE_SH="${GC_RECONCILE_ESCALATE_TOOL:-$SELF_DIR/escalate.sh}"

# The store the per-rig subject bead lives in, and whose board shows the visit.
RECONCILE_RIG="${RECONCILE_BEAD_RIG:-gc-toolkit}"
# Operator knob: route the divergence visit to a coordination pool. Unset means
# escalate.sh's human helm board. RECONCILE_MAYOR_ADDR is the prior name for
# this knob and is still honored.
ESC_POOL="${RECONCILE_ESCALATION_POOL:-${RECONCILE_MAYOR_ADDR:-}}"

# id of the single open reconcile bead for a rig (empty if none).
open_bead() {
    gc bd --rig "$RECONCILE_RIG" list --metadata-field "reconcile_rig=$1" --json 2>/dev/null \
        | jq -r '.[0].id // empty' 2>/dev/null || true
}

# Raise a divergence through escalate.sh. A configured pool is tried first —
# escalate.sh proves it addresses a live agent — and anything unroutable falls
# back to the human board so the divergence still reaches someone. The exit
# status is that of the path that ran, so the caller can report a total failure.
escalate_divergence() {
    local subject="$1" key="$2" message="$3"
    if [ -n "$ESC_POOL" ]; then
        if GC_RIG="$RECONCILE_RIG" "$ESCALATE_SH" \
                --subject "$subject" --key "$key" --message "$message" --pool "$ESC_POOL"; then
            return 0
        fi
        warn "escalation pool '$ESC_POOL' did not route for $subject — falling back to the human board"
    fi
    GC_RIG="$RECONCILE_RIG" "$ESCALATE_SH" \
        --subject "$subject" --key "$key" --message "$message"
}

advanced=0; healed=0; blocked=0
rigs=$(gc rig list --json 2>/dev/null | jq -r '.rigs[] | select(.hq != true) | "\(.name)\t\(.path)"') || exit 0

while IFS=$'\t' read -r name path; do
    [ -n "${name:-}" ] && [ -d "$path/.git" ] || continue
    git -C "$path" fetch origin --quiet 2>/dev/null || continue
    remote=$(git -C "$path" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)

    if git -C "$path" merge --ff-only "$remote" >/dev/null 2>&1; then
        # Advanced or already up to date — clear any lingering escalation.
        advanced=$((advanced + 1))
        bead=$(open_bead "$name")
        [ -n "$bead" ] && gc bd --rig "$RECONCILE_RIG" close "$bead" \
            --reason "rigs/$name fast-forwarded cleanly to $remote" >/dev/null 2>&1 || true
        continue
    fi

    # ff-only refused. Almost always this is SHA churn from an upstream
    # rebase/squash/force-push and the checkout's content is already upstream, so
    # try to auto-heal before escalating. reset --hard is lossless only when the
    # guard proves it: git cherry (patch-id) finds no unique local commit, no
    # merge commit is unique to local (git cherry ignores merges, so a local
    # merge's tree content is not provably upstream), the status read succeeds,
    # and no dirty tracked path carries local-only content (a working tree that
    # differs from the remote, or a staged index matching neither remote nor
    # HEAD). Untracked files are
    # never touched by reset --hard. Anything the guard cannot prove — a real
    # divergence, an unreadable status, a local merge — falls through to the
    # escalation path unchanged. RECONCILE_NO_AUTOHEAL=1 disables the heal.
    if [ "${RECONCILE_NO_AUTOHEAL:-0}" != "1" ] \
       && cherry_out=$(git -C "$path" cherry "$remote" HEAD 2>/dev/null) \
       && [ -z "$(printf '%s' "$cherry_out" | grep '^+' || true)" ] \
       && merges=$(git -C "$path" rev-list --merges "$remote"..HEAD 2>/dev/null) \
       && [ -z "$merges" ] \
       && status_out=$(git -C "$path" -c core.quotepath=false status --porcelain 2>/dev/null); then
        unique_tracked=0
        while IFS= read -r changed; do
            [ -n "$changed" ] || continue
            # reset --hard overwrites both the working tree and the staged index
            # for this path, so neither may carry content the reset would lose.
            # Working tree: safe only when it already equals the remote (the
            # regenerated-to-upstream case). Index: safe when it equals the remote,
            # or equals HEAD — committed content, proven upstream by the cherry
            # check above. Content staged but never committed (differs from both
            # HEAD and the remote) is discarded with no way back, even when an
            # upstream-matching worktree copy hides it from a diff against remote.
            if ! git -C "$path" diff --quiet "$remote" -- "$changed" 2>/dev/null; then
                unique_tracked=$((unique_tracked + 1))
            elif ! git -C "$path" diff --cached --quiet "$remote" -- "$changed" 2>/dev/null \
                 && ! git -C "$path" diff --cached --quiet HEAD -- "$changed" 2>/dev/null; then
                unique_tracked=$((unique_tracked + 1))
            fi
        done < <(printf '%s\n' "$status_out" | grep -v '^??' | sed -E 's/^.{3}//; s/^.* -> //')
        if [ "$unique_tracked" -eq 0 ] && git -C "$path" reset --hard "$remote" >/dev/null 2>&1; then
            healed=$((healed + 1))
            bead=$(open_bead "$name")
            [ -n "$bead" ] && gc bd --rig "$RECONCILE_RIG" close "$bead" \
                --reason "rigs/$name auto-healed: already-upstream, reset --hard to $remote" >/dev/null 2>&1 || true
            continue
        fi
    fi

    # ff-only refused and the divergence is genuine (or auto-heal is disabled):
    # do NOT touch the checkout — escalate.
    blocked=$((blocked + 1))
    body=$(printf 'rigs/%s could not fast-forward to %s — the live checkout diverged.\nPath: %s\n\nJudge and act, then close this bead (it auto-closes when the rig next\nff-s cleanly): already-upstream -> git -C %s reset --hard %s; machine-local\nconfig -> leave it; real work -> handle it.\n\n## git status --porcelain\n%s\n\n## git log --oneline %s..HEAD\n%s\n' \
        "$name" "$remote" "$path" "$path" "$remote" \
        "$(git -C "$path" status --porcelain 2>/dev/null)" \
        "$remote" "$(git -C "$path" log --oneline "$remote"..HEAD 2>/dev/null)")

    bead=$(open_bead "$name")
    if [ -n "$bead" ]; then
        gc bd --rig "$RECONCILE_RIG" update "$bead" --description "$body" >/dev/null 2>&1 || true
    else
        bead=$(gc bd --rig "$RECONCILE_RIG" create "Reconcile: rigs/$name diverged from $remote" \
            -t task -d "$body" --json 2>/dev/null | jq -r '.id // empty' 2>/dev/null || true)
        [ -n "$bead" ] || { warn "could not file a reconcile bead for rigs/$name — divergence UNTRACKED and UNESCALATED"; continue; }
        gc bd --rig "$RECONCILE_RIG" update "$bead" --set-metadata reconcile_rig="$name" >/dev/null 2>&1 || true
    fi

    # Make someone hear about it. A failure here is reported, never swallowed —
    # an unescalated divergence is the exact silent rot this script prevents.
    msg=$(printf 'rigs/%s cannot fast-forward to %s — its live checkout diverged and its deploy is stalled.\nPath: %s\nSubject bead %s carries the full git status and divergence log, and clears when rigs/%s next ff-s cleanly.\nalready-upstream -> git -C %s reset --hard %s; machine-local config -> leave it; real work -> handle it.' \
        "$name" "$remote" "$path" "$bead" "$name" "$path" "$remote")
    if ! escalate_divergence "$bead" "reconcile-diverged-$name" "$msg"; then
        warn "rigs/$name divergence could NOT be escalated (escalate.sh failed) — subject bead $bead"
    fi
done <<< "$rigs"

echo "reconcile-rig-checkouts: $advanced advanced, $healed auto-healed, $blocked blocked"
