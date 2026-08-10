#!/usr/bin/env bash
# Pack doctor check: the near-miss refinery-address recovery is shipped and wired.
#
# What it guards (tk-0nn3f). A merge handoff addressed to "<rig>/refinery" instead
# of "<rig>/{{binding_prefix}}refinery" is accepted as free text and then polled by
# nobody: it is invisible to the refinery's exact assignee filter, to every
# bead-keyed reconcile pass (it carries no merge_result and no pr_url), and to the
# witness's orphan recovery (a refinery-shaped assignee reads as an infrastructure
# identity and is skipped). An idle refinery with an empty queue is what a healthy
# city looks like, so nothing escalates — the live case sat 1h07m with completed,
# pushed work until a human noticed.
#
# Why a doctor check rather than trust. Both call sites live in formulas that are
# ALLOWLISTED MIRRORS of base artifacts (see check-base-artifact-collision), so
# they are periodically reconciled against an upstream that does not carry this
# pass. A reconciliation that drops either call restores the blind spot silently
# and in exactly the state where nothing reports it. The script existing without a
# caller is the same failure: "whichever session notices" is not an owner.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

dir="${GC_PACK_DIR:-.}"
script="assets/scripts/reconcile-refinery-handoffs.sh"
errors=()

# --- the pass itself -------------------------------------------------------
if [ ! -s "$dir/$script" ]; then
    errors+=("missing: $script — nothing recovers a near-miss handoff address")
else
    [ -x "$dir/$script" ] \
        || errors+=("$script is not executable — every call site guards on -x, so a non-executable script is silently never run")
    # The refusal arms are the reason this pass is allowed to rewrite an assignee
    # at all. Losing them turns a guarded repair into a blind one.
    grep -q 'FAIL SAFE' "$dir/$script" \
        || errors+=("$script: the empty/unreadable-roster fail-safe is gone — an empty roster makes every address look unheld and every assignee rewritable")
    grep -q 'is_alive' "$dir/$script" \
        || errors+=("$script: the liveness guard is gone — the pass may rewrite an address a live session still answers to")
fi
[ -s "$dir/${script%.sh}.test.sh" ] \
    || errors+=("missing: ${script#assets/scripts/} regression test (${script%.sh}.test.sh)")

# --- both call sites -------------------------------------------------------
check_wired() { # <formula> <human description of the call site>
    local f="$dir/formulas/$1"
    if [ ! -s "$f" ]; then errors+=("missing formula: formulas/$1"); return; fi
    grep -q 'reconcile-refinery-handoffs.sh' "$f" \
        || errors+=("formulas/$1: no longer calls reconcile-refinery-handoffs.sh ($2) — a handoff sent to a near-miss address goes unseen again")
    grep -q -- '--refinery' "$f" \
        || errors+=("formulas/$1: calls the pass without --refinery; with no canonical identity it skips every bead")
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "import tomllib,sys; tomllib.load(open('$f','rb'))" 2>/dev/null \
            || errors+=("formulas/$1: does not parse as TOML")
    fi
}

check_wired "mol-refinery-patrol.toml" "the find-work idle loop — the primary owner, it repairs and re-checks in one cycle"
check_wired "mol-witness-patrol.toml"  "the check-refinery step — the backstop for a refinery that is down or never woke"

if [ "${#errors[@]}" -eq 0 ]; then
    echo "OK: near-miss refinery-address recovery shipped and wired (refinery find-work + witness check-refinery)"
    exit 0
fi
echo "refinery handoff-address recovery mis-wired: ${#errors[@]} problem(s)"
printf '%s\n' "${errors[@]}"
exit 2
