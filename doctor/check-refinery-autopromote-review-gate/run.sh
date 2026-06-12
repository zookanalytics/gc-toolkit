#!/usr/bin/env bash
# Pack doctor check: mol-refinery-patrol's direct→pr auto-promotion
# routes through the single mr PR-creation surface, so the codex review
# gate (draft PR + review-bead dispatch) fires for auto-promoted work.
#
# Symptom this guards against (tk-kcr8v6): when a direct push to a
# protected branch is rejected (GH013), the merge-push step auto-promotes
# to merge_strategy=pr and is supposed to fall through to the "mr" block,
# which opens the PR as --draft (under review_gate=codex) and dispatches a
# codex review bead. The refinery agent skipped that fall-through twice in
# a row (PR #68 / tk-sma1xw and PR #69 / tk-d8jhjb both opened non-draft
# with no review bead), shortcutting to `gh pr create` + close once the
# rebased branch was in hand. The gate steps lived ~110 lines downstream
# across two visually-similar shell blocks, so the long-distance
# fall-through was unreliable.
#
# The fix (Option B — single PR-creation surface, hardened with guards):
#   - The auto-promote arm only flips MERGE_STRATEGY=mr and resets; it
#     creates no PR and closes no bead itself.
#   - The direct-success tail (verify / merged-close / cleanup / auto-ff)
#     is each guarded with `[ "$MERGE_STRATEGY" = "direct" ]`, so after an
#     auto-promotion none of it fires (no false "merged" close, `temp`
#     survives for the PR).
#   - The "mr" block remains the ONE place a PR is created, carrying the
#     --draft flag and the review-bead dispatch, both gated on
#     review_gate=codex.
#
# Structural shape we pin (in the merge-push step's bash, comments and
# shell line-continuations folded out, if/else arms tracked by depth):
#   1. Auto-promote: inside the `if is_protected_branch_error ...` then-arm
#      there is a `MERGE_STRATEGY=mr` assignment (funnel to mr) and there
#      is NO `gh pr create` and NO `gc bd close` (the arm does not itself
#      terminate the handoff).
#   2. Guarded close: the direct merged-close (`gc bd close ... Merged`)
#      sits inside a `[ "$MERGE_STRATEGY" = "direct" ]` then-arm, so it
#      cannot fire after auto-promotion.
#   3. Draft gate: `PR_DRAFT_FLAG="--draft"` sits inside a
#      `[ "{{review_gate}}" = "codex" ]` then-arm.
#   4. Review-bead gate: the `--set-metadata task_kind=review` dispatch
#      sits inside a `[ "{{review_gate}}" = "codex" ]` then-arm.
#   5. Single surface: exactly one `gh pr create` in the whole step.
#
# Matches must live inside a ```bash fenced block within the merge-push
# [[steps]] description heredoc — not in prose, a bash comment, or another
# step. Guard membership is tracked by an if/else/fi depth stack so a line
# in an else-arm or outside the guard cannot satisfy a "within guard X"
# assertion.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

dir="${GC_PACK_DIR:-.}"
file="${GC_REFINERY_FORMULA:-$dir/formulas/mol-refinery-patrol.toml}"
violations=()

if [ ! -f "$file" ]; then
    echo "mol-refinery-patrol.toml: missing file $file"
    exit 2
fi

report=$(awk '
function reset_block(    i) {
    depth = 0
    pending = ""
    pending_cond = ""
    await_then = 0
    for (i in gcond) delete gcond[i]
    for (i in garm) delete garm[i]
}

# Classify one logical (continuation-folded) bash line and update facts.
function process_line(line,    c, i, in_ipbe, in_direct, in_codex) {
    sub(/^[[:space:]]+/, "", line)
    sub(/[[:space:]]+$/, "", line)
    if (line == "") return
    if (substr(line, 1, 1) == "#") return        # bash comment

    # `then` on its own line completes a pending multi-line `if`.
    if (await_then) {
        if (line ~ /^then([[:space:]]|$)/) {
            depth++; gcond[depth] = pending_cond; garm[depth] = "then"
            await_then = 0; pending_cond = ""
            return
        }
        await_then = 0; pending_cond = ""
    }

    if (line ~ /^if[[:space:]]/) {
        c = line
        sub(/^if[[:space:]]+/, "", c)
        if (c ~ /;[[:space:]]*then$/) {
            sub(/;[[:space:]]*then$/, "", c)
            depth++; gcond[depth] = c; garm[depth] = "then"
        } else {
            pending_cond = c; await_then = 1       # expect `then` next line
        }
        return
    }
    if (line ~ /^elif[[:space:]]/) { if (depth > 0) garm[depth] = "elif"; return }
    if (line ~ /^else([[:space:]]|$)/) { if (depth > 0) garm[depth] = "else"; return }
    if (line ~ /^fi([[:space:]]|$)/) {
        if (depth > 0) { delete gcond[depth]; delete garm[depth]; depth-- }
        return
    }

    # Content line. Compute enclosing then-arm guard membership.
    in_ipbe = 0; in_direct = 0; in_codex = 0
    for (i = 1; i <= depth; i++) {
        if (garm[i] != "then") continue
        if (gcond[i] ~ /is_protected_branch_error/) in_ipbe = 1
        if (gcond[i] ~ /MERGE_STRATEGY.*"direct"/) in_direct = 1
        if (gcond[i] ~ /review_gate.*codex/) in_codex = 1
    }

    # 1. Auto-promote arm: funnel + no self-terminating handoff.
    if (in_ipbe && line ~ /^MERGE_STRATEGY="?mr"?[[:space:]]*$/) ap_funnel = 1
    if (in_ipbe && line ~ /gh[[:space:]]+pr[[:space:]]+create/) ap_pr_leak = 1
    if (in_ipbe && line ~ /gc[[:space:]]+bd[[:space:]]+close/) ap_close_leak = 1

    # 2. Guarded direct merged-close.
    if (line ~ /gc[[:space:]]+bd[[:space:]]+close[[:space:]].*Merged/) {
        direct_close_seen = 1
        if (in_direct) direct_close_guarded = 1
    }

    # 3. Draft-PR gate.
    if (line ~ /PR_DRAFT_FLAG=.*--draft/) {
        draft_seen = 1
        if (in_codex) draft_guarded = 1
    }

    # 4. Review-bead dispatch gate.
    if (line ~ /set-metadata[[:space:]]+task_kind=review/) {
        review_seen = 1
        if (in_codex) review_guarded = 1
    }

    # 5. Single PR-creation surface.
    if (line ~ /gh[[:space:]]+pr[[:space:]]+create/) pr_create_count++
}

BEGIN {
    in_step = 0; target_step = 0
    in_heredoc = 0; heredoc_is_target = 0; in_fence = 0
    reset_block()
    ap_funnel = 0; ap_pr_leak = 0; ap_close_leak = 0
    direct_close_seen = 0; direct_close_guarded = 0
    draft_seen = 0; draft_guarded = 0
    review_seen = 0; review_guarded = 0
    pr_create_count = 0
}

# Outside a """heredoc""": track TOML step structure.
!in_heredoc {
    if ($0 ~ /^\[\[steps\]\][[:space:]]*$/) { in_step = 1; target_step = 0; next }
    if ($0 ~ /^\[/) { in_step = 0; target_step = 0; next }
    if (in_step && $0 ~ /^id[[:space:]]*=[[:space:]]*"merge-push"[[:space:]]*$/) { target_step = 1; next }
    if ($0 ~ /^description[[:space:]]*=[[:space:]]*"""[[:space:]]*$/) {
        in_heredoc = 1
        heredoc_is_target = (in_step && target_step)
        in_fence = 0
        reset_block()
        next
    }
    next
}

# Inside a """heredoc""".
in_heredoc {
    if (index($0, "\"\"\"") > 0) {
        in_heredoc = 0; heredoc_is_target = 0; in_fence = 0
        reset_block()
        next
    }
    if ($0 ~ /^```/) { in_fence = !in_fence; reset_block(); next }
    if (!heredoc_is_target || !in_fence) next

    # Fold shell line-continuations into one logical line.
    line = $0
    if (line ~ /\\[[:space:]]*$/) {
        sub(/\\[[:space:]]*$/, "", line)
        pending = (pending == "" ? line : pending " " line)
        next
    }
    pending = (pending == "" ? line : pending " " line)
    process_line(pending)
    pending = ""
}

END {
    printf "ap_funnel=%d\n", ap_funnel
    printf "ap_pr_leak=%d\n", ap_pr_leak
    printf "ap_close_leak=%d\n", ap_close_leak
    printf "direct_close_seen=%d\n", direct_close_seen
    printf "direct_close_guarded=%d\n", direct_close_guarded
    printf "draft_seen=%d\n", draft_seen
    printf "draft_guarded=%d\n", draft_guarded
    printf "review_seen=%d\n", review_seen
    printf "review_guarded=%d\n", review_guarded
    printf "pr_create_count=%d\n", pr_create_count
}
' "$file")

extract() {
    echo "$report" | awk -F= -v key="$1" '$1 == key { print $2; exit }'
}

ap_funnel=$(extract ap_funnel)
ap_pr_leak=$(extract ap_pr_leak)
ap_close_leak=$(extract ap_close_leak)
direct_close_seen=$(extract direct_close_seen)
direct_close_guarded=$(extract direct_close_guarded)
draft_seen=$(extract draft_seen)
draft_guarded=$(extract draft_guarded)
review_seen=$(extract review_seen)
review_guarded=$(extract review_guarded)
pr_create_count=$(extract pr_create_count)

if [ "$ap_funnel" != "1" ]; then
    violations+=("auto-promote arm missing 'MERGE_STRATEGY=mr' funnel inside the 'if is_protected_branch_error ...' then-arm (protected-branch rejection must promote into the mr block)")
fi
if [ "$ap_pr_leak" = "1" ]; then
    violations+=("auto-promote arm contains 'gh pr create' — the protected-branch arm must not create a PR itself; route PR creation through the single mr surface (tk-kcr8v6)")
fi
if [ "$ap_close_leak" = "1" ]; then
    violations+=("auto-promote arm contains 'gc bd close' — the protected-branch arm must not close the bead; the mr block performs the terminal handoff (tk-kcr8v6)")
fi
if [ "$direct_close_seen" != "1" ]; then
    violations+=("could not find the direct merged-close ('gc bd close ... Merged') in merge-push bash — structure changed; re-verify the guard")
elif [ "$direct_close_guarded" != "1" ]; then
    violations+=("direct merged-close is not wrapped in '[ \"\$MERGE_STRATEGY\" = \"direct\" ]' — after auto-promotion this would falsely close the bead as merged (tk-kcr8v6)")
fi
if [ "$draft_seen" != "1" ]; then
    violations+=("could not find 'PR_DRAFT_FLAG=\"--draft\"' in merge-push bash — the draft-PR gate is absent")
elif [ "$draft_guarded" != "1" ]; then
    violations+=("'PR_DRAFT_FLAG=\"--draft\"' is not gated on '[ \"{{review_gate}}\" = \"codex\" ]' — the draft gate must key on review_gate")
fi
if [ "$review_seen" != "1" ]; then
    violations+=("could not find the review-bead dispatch ('--set-metadata task_kind=review') in merge-push bash — the codex review gate is absent")
elif [ "$review_guarded" != "1" ]; then
    violations+=("review-bead dispatch is not gated on '[ \"{{review_gate}}\" = \"codex\" ]' — the review gate must key on review_gate")
fi
if [ "$pr_create_count" != "1" ]; then
    violations+=("expected exactly one 'gh pr create' in merge-push (single PR-creation surface), found $pr_create_count — a second creation site can bypass the draft/review gate (tk-kcr8v6)")
fi

if [ ${#violations[@]} -eq 0 ]; then
    echo "refinery auto-promote funnels into the single mr PR surface; codex review gate (draft + review bead) is reachable and the direct-success tail is guarded"
    exit 0
fi

echo "${#violations[@]} refinery auto-promote review-gate gap(s) in mol-refinery-patrol merge-push — see tk-kcr8v6"
for v in "${violations[@]}"; do
    echo "$v"
done
exit 2
