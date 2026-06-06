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
# nothing) on any divergence or conflicting dirty file. So this ships enabled
# — it cannot clobber work. The refusal IS the exception signal: we don't
# touch the checkout, we file one idempotent bead per blocked rig for the
# mayor, whose LLM judgment resolves the rare exception in ~2 lines. See
# docs/rig-checkout-reconciler.md and design bead tk-yjtf.
#
# Runs as an exec order (no LLM, no agent, no wisp).
set -euo pipefail

MAYOR_ADDR="${RECONCILE_MAYOR_ADDR:-gc-toolkit.mayor}"
MAYOR_RIG="${MAYOR_ADDR%.*}"   # ledger the mayor reads (e.g. gc-toolkit)

# id of the single open reconcile bead for a rig (empty if none).
open_bead() {
    gc bd --rig "$MAYOR_RIG" list --metadata-field "reconcile_rig=$1" --json 2>/dev/null \
        | jq -r '.[0].id // empty' 2>/dev/null || true
}

advanced=0; blocked=0
rigs=$(gc rig list --json 2>/dev/null | jq -r '.rigs[] | select(.hq != true) | "\(.name)\t\(.path)"') || exit 0

while IFS=$'\t' read -r name path; do
    [ -n "${name:-}" ] && [ -d "$path/.git" ] || continue
    git -C "$path" fetch origin --quiet 2>/dev/null || continue
    remote=$(git -C "$path" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)

    if git -C "$path" merge --ff-only "$remote" >/dev/null 2>&1; then
        # Advanced or already up to date — clear any lingering escalation.
        advanced=$((advanced + 1))
        bead=$(open_bead "$name")
        [ -n "$bead" ] && gc bd --rig "$MAYOR_RIG" close "$bead" \
            --reason "rigs/$name fast-forwarded cleanly to $remote" >/dev/null 2>&1 || true
        continue
    fi

    # ff-only refused: the checkout diverged. Do NOT touch it — escalate.
    blocked=$((blocked + 1))
    body=$(printf 'rigs/%s could not fast-forward to %s — the live checkout diverged.\nPath: %s\n\nJudge and act, then close this bead (it auto-closes when the rig next\nff-s cleanly): already-upstream -> git -C %s reset --hard %s; machine-local\nconfig -> leave it; real work -> handle it.\n\n## git status --porcelain\n%s\n\n## git log --oneline %s..HEAD\n%s\n' \
        "$name" "$remote" "$path" "$path" "$remote" \
        "$(git -C "$path" status --porcelain 2>/dev/null)" \
        "$remote" "$(git -C "$path" log --oneline "$remote"..HEAD 2>/dev/null)")

    bead=$(open_bead "$name")
    if [ -n "$bead" ]; then
        gc bd --rig "$MAYOR_RIG" update "$bead" --description "$body" >/dev/null 2>&1 || true
    else
        bead=$(gc bd --rig "$MAYOR_RIG" create "Reconcile: rigs/$name diverged from $remote" \
            -t task -a "$MAYOR_ADDR" -d "$body" --json 2>/dev/null | jq -r '.id // empty' 2>/dev/null || true)
        [ -n "$bead" ] || continue
        gc bd --rig "$MAYOR_RIG" update "$bead" --set-metadata reconcile_rig="$name" >/dev/null 2>&1 || true
        gc session nudge "$MAYOR_ADDR" "Reconcile: rigs/$name diverged — needs judgment ($bead)" 2>/dev/null || true
    fi
done <<< "$rigs"

echo "reconcile-rig-checkouts: $advanced advanced, $blocked blocked"
