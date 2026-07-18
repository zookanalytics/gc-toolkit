#!/usr/bin/env bash
# Pack doctor check: keeper re-pours mint the resume hand-off token and
# the rebase convention requires it.
#
# The convention "Re-pour over a paused rebase is resume, not duplicate
# dispatch" (rebase-conventions fragment) lets a pool polecat resume a
# paused mol-upstream-gc-rebase instead of parking it as a duplicate.
# Its state conditions (rebase_in_progress + work_dir + commit_verdicts)
# are also true for a spurious re-fire racing a live driver, so the
# proceed path additionally REQUIRES the keeper's hand-off token:
# metadata.resume_handoff on the issue, minted only at the keeper's
# deliberate re-pour and threaded through the sling as
# --var resume_handoff (gc-lwc5p).
#
# The token is load-bearing only while BOTH sides hold: every keeper
# re-pour sling site must stamp and thread it, and the convention
# fragment must demand the exact issue-vs-root match, consume it on
# resume, and keep park as the default. This check pins the two files
# together so they can't drift apart — a keeper that stops minting
# silently parks every legitimate resume; a convention that stops
# requiring silently re-opens the double-rebase-continue race.
#
# Site discovery mirrors check-keeper-repour-reassign: shell
# line-continuations are joined before applying the discriminator, and
# an expected-count assertion guards against silent drift when sling
# sites are added or removed.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

dir="${GC_PACK_DIR:-.}"
violations=()

prompt="$dir/packs/gascity-keeper/agents/keeper/prompt.template.md"
fragment="$dir/packs/gascity-keeper/template-fragments/rebase-conventions.template.md"

# Distinct keeper re-pour-to-pool sling sites in the keeper prompt (the
# same set check-keeper-repour-reassign audits):
#   1. Rebase-in-progress handback (rework/review re-pour)
#   2. Conflict-questions "skip the commit" path
# Both are deliberate hand-offs over a paused rebase, so BOTH must mint
# the token. If a site is added or removed, bump this counter (and the
# one in check-keeper-repour-reassign) and give the new site the
# stamp + sling-var pair.
EXPECTED_SITES=2

# For every re-pour sling site in $1, print "<head_line>\t<joined_cmd>".
# A site is a logical shell command whose JOINED text
# (line-continuations folded in) matches the placeholder-bead +
# concrete-mol discriminator, so a flag on any physical line of the
# command is visible to the caller.
find_repour_sites() {
    awk '
        function check_logical_line(    ok) {
            ok = (cmd ~ /gc sling [^ ]+\/gc-toolkit\.polecat <bead>/) \
              && (cmd ~ /--on mol-/)
            if (ok) print start "\t" cmd
            cmd = ""
            start = 0
        }
        BEGIN { cmd = ""; start = 0 }
        {
            line = $0
            cont = sub(/\\$/, "", line)
            if (cmd == "") start = NR
            cmd = (cmd == "" ? line : cmd " " line)
            if (!cont) check_logical_line()
        }
        END { if (cmd != "") check_logical_line() }
    ' "$1"
}

# --- Keeper side: every re-pour sling threads the token, and each site
# stamps it on the issue first.
if [ ! -f "$prompt" ]; then
    violations+=("keeper prompt: missing file $prompt")
else
    sites=$(find_repour_sites "$prompt")
    if [ -z "$sites" ]; then
        found=0
    else
        found=$(printf '%s\n' "$sites" | wc -l | tr -d ' ')
    fi

    if [ "$found" -ne "$EXPECTED_SITES" ]; then
        violations+=("keeper prompt: expected $EXPECTED_SITES keeper re-pour sling sites, found $found. Site discovery is stale OR a sling site was added/removed; update EXPECTED_SITES here (and in check-keeper-repour-reassign) and give every site the resume_handoff stamp + sling var")
    else
        while IFS=$'\t' read -r line_no cmd; do
            [ -z "$line_no" ] && continue
            if ! echo "$cmd" | grep -q -- '--var resume_handoff='; then
                violations+=("keeper prompt:$line_no: re-pour sling without '--var resume_handoff=' (resuming polecat cannot prove the hand-off, so the legitimate resume parks; gc-lwc5p)")
            fi
        done <<< "$sites"
    fi

    stamps=$(grep -c -- '--set-metadata resume_handoff=' "$prompt")
    if [ "$stamps" -ne "$EXPECTED_SITES" ]; then
        violations+=("keeper prompt: expected $EXPECTED_SITES '--set-metadata resume_handoff=' stamp sites (one per re-pour), found $stamps")
    fi
fi

# --- Convention side: the proceed path requires the exact issue-vs-root
# token match, consumes it on resume, and park stays the default.
if [ ! -f "$fragment" ]; then
    violations+=("rebase-conventions fragment: missing file $fragment")
else
    if ! grep -q 'metadata\.resume_handoff' "$fragment" \
        || ! grep -q 'gc\.var\.resume_handoff' "$fragment"; then
        violations+=("rebase-conventions fragment: proceed path no longer requires the metadata.resume_handoff == gc.var.resume_handoff match; the resume-vs-duplicate guard is one-sided")
    fi
    if ! grep -q -- 'unset-metadata resume_handoff' "$fragment"; then
        violations+=("rebase-conventions fragment: missing the consume step (unset-metadata resume_handoff); an unconsumed token lets a later spurious re-fire validate")
    fi
    if ! grep -q 'Still park a true duplicate' "$fragment"; then
        violations+=("rebase-conventions fragment: 'Still park a true duplicate' safe-default paragraph is gone; park must remain the default for tokenless roots")
    fi
fi

if [ ${#violations[@]} -eq 0 ]; then
    echo "keeper re-pours mint the resume hand-off token; rebase convention requires and consumes it"
    exit 0
fi

echo "${#violations[@]} resume hand-off token violation(s) across keeper prompt / rebase convention"
for v in "${violations[@]}"; do
    echo "$v"
done
exit 2
