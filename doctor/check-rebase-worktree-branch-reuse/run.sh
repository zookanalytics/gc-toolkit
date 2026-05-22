#!/usr/bin/env bash
# Pack doctor check: mol-upstream-gc-rebase's workspace-setup step
# branches the worktree-create on whether `refs/heads/rebase/<issue>`
# already exists (recovery after a worktree wipe).
#
# Symptom this guards against: a polecat session that drained while
# holding a rebase worktree leaves `refs/heads/rebase/<issue>` behind
# in the rig's shared repo even after the worktree dir was reaped. A
# fresh re-pour of the rebase mol then hits `git worktree add ... -b
# rebase/<issue>` -- which fails with "A branch named '...' already
# exists" and strands the bead. See tk-y883hr for the trip diagnostic
# and tk-n5gldl for the structural-assertion follow-up.
#
# Structural shape we pin (not three independent exact-string greps):
#   1. Inside some `[[steps]]` description bash block, an `if` opens
#      whose condition includes
#      `rev-parse --verify "refs/heads/rebase/{{issue}}"`.
#   2. The if's then-arm (before the matching `else` at the outer
#      depth) contains a `worktree add "$WORKTREE_PATH" "rebase/{{issue}}"`
#      line — re-attach the existing branch, no `-b`.
#   3. The if's else-arm (after `else`, before the matching outer `fi`)
#      contains a `worktree add "$WORKTREE_PATH" -b "rebase/{{issue}}"
#      "{{origin_remote}}/{{upstream_branch}}"` line — fresh create.
#   4. Earlier in the same step's bash, `worktree prune` runs so the
#      re-attach doesn't trip on stale `.git/worktrees/<name>/` admin
#      from a reaped worktree.
#
# Matches must live inside a ```bash fenced block within a [[steps]]
# description heredoc — not in the top-level formula description, in a
# bash comment, or in a TOML field value elsewhere in the file. Quotes
# around the literal strings can be single or double; arms are tracked
# by depth so nested if/else/fi inside the guarded block can't
# mis-classify which arm a worktree-add line lives in.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

dir="${GC_PACK_DIR:-.}"
file="$dir/packs/gascity-keeper/formulas/mol-upstream-gc-rebase.toml"
violations=()

if [ ! -f "$file" ]; then
    echo "mol-upstream-gc-rebase.toml: missing file $file"
    exit 2
fi

# State machine walking the file. Captures:
#   rev_parse=0|1            — saw the outer `if rev-parse ... rebase/{{issue}}` open
#   reattach=0|1             — saw re-attach line at outer depth in the then-arm
#   fresh=0|1                — saw fresh-create line at outer depth in the else-arm
#   prune=0|1                — saw `worktree prune` anywhere in step bash
#   prune_before_guard=0|1   — saw `worktree prune` BEFORE entering the guard
#                              (in the same step, in the same fence)
# Line numbers for diagnostics on the found patterns are also returned.
report=$(awk '
function trim(s) {
    sub(/^[[:space:]]+/, "", s)
    sub(/[[:space:]]+$/, "", s)
    return s
}

BEGIN {
    # Quote class: single or double quote.
    Q = "[\"'\'']"

    # Anchored on the {{issue}} placeholder so a literal `rebase/foo` example
    # elsewhere cannot satisfy the pattern. `-C "$..."` is optional so a
    # refactor that drops or renames the cwd flag still matches.
    REVPARSE = "rev-parse[[:space:]]+--verify[[:space:]]+" Q "refs/heads/rebase/\\{\\{issue\\}\\}" Q

    # Re-attach: `worktree add` followed by `$WORKTREE_PATH` then the
    # branch name. The pattern intentionally has no `-b` between
    # `$WORKTREE_PATH` and `rebase/{{issue}}`; the fresh-create line has
    # `-b` there, so the fresh-create line will not accidentally match.
    REATTACH = "worktree[[:space:]]+add[[:space:]]+" Q "\\$WORKTREE_PATH" Q "[[:space:]]+" Q "rebase/\\{\\{issue\\}\\}" Q

    # Fresh create: `worktree add ... -b "rebase/{{issue}}"
    # "{{origin_remote}}/{{upstream_branch}}"`.
    FRESH = "worktree[[:space:]]+add[[:space:]]+" Q "\\$WORKTREE_PATH" Q "[[:space:]]+-b[[:space:]]+" Q "rebase/\\{\\{issue\\}\\}" Q "[[:space:]]+" Q "\\{\\{origin_remote\\}\\}/\\{\\{upstream_branch\\}\\}" Q

    # Prune: `worktree prune` is enough; the surrounding `git -C "$..."`
    # framing is incidental.
    PRUNE = "worktree[[:space:]]+prune([[:space:]]|$)"

    in_heredoc = 0
    heredoc_is_step_desc = 0
    in_step = 0
    in_fence = 0

    in_guarded = 0
    nest = 0
    arm = ""
    pending_prune_in_fence = 0

    rev_parse_seen = 0
    reattach_seen = 0
    fresh_seen = 0
    prune_seen = 0
    prune_before_guard = 0

    rev_parse_line = 0
    reattach_line = 0
    fresh_line = 0
}

# Outside any """heredoc""": parse TOML structure.
!in_heredoc {
    if ($0 ~ /^\[\[steps\]\][[:space:]]*$/) {
        in_step = 1
        in_guarded = 0; nest = 0; arm = ""
        pending_prune_in_fence = 0
        next
    }
    if ($0 ~ /^\[/) {
        # Some other TOML table header (e.g. [vars.X]) — closes step context.
        in_step = 0
        in_guarded = 0; nest = 0; arm = ""
        pending_prune_in_fence = 0
        next
    }
    if ($0 ~ /^description[[:space:]]*=[[:space:]]*"""[[:space:]]*$/) {
        in_heredoc = 1
        heredoc_is_step_desc = in_step
        in_fence = 0
        next
    }
    next
}

# Inside a """heredoc""". TOML allows the closing `"""` either on its
# own line or at the end of a content line (`...text."""`); match both.
in_heredoc {
    if (index($0, "\"\"\"") > 0) {
        in_heredoc = 0
        heredoc_is_step_desc = 0
        in_fence = 0
        in_guarded = 0; nest = 0; arm = ""
        pending_prune_in_fence = 0
        next
    }
    # Code fence toggle (``` opens or closes a fenced block).
    if ($0 ~ /^```/) {
        in_fence = !in_fence
        if (!in_fence) {
            # Closing fence ends any in-flight guarded if without a matching `fi`.
            in_guarded = 0; nest = 0; arm = ""
            pending_prune_in_fence = 0
        }
        next
    }
    # Only inspect bash inside a step descriptions fenced block.
    if (!heredoc_is_step_desc || !in_fence) next

    trimmed = trim($0)
    # Skip blank lines and bash comments — a `# else: explanation`
    # comment must not toggle the arm tracker, and a `# worktree add ...`
    # comment must not satisfy the worktree-add patterns.
    if (trimmed == "" || substr(trimmed, 1, 1) == "#") next

    # `worktree prune` anywhere in step bash. Track its position relative
    # to the rev-parse guard so we can flag a missing pre-guard prune.
    if (match(trimmed, PRUNE)) {
        prune_seen = 1
        if (!in_guarded) {
            pending_prune_in_fence = 1
        }
    }

    # Outer rev-parse guard open: a line starting with `if ` whose body
    # includes the rev-parse-refs/heads/rebase/{{issue}} pattern. Only
    # treated as the outer guard if we are not already inside one (a
    # nested rev-parse guard would be the inner if and decrement `nest`
    # accordingly).
    if (!in_guarded && trimmed ~ /^if[[:space:]]/ && match(trimmed, REVPARSE)) {
        in_guarded = 1
        nest = 0
        arm = "then"
        rev_parse_seen = 1
        rev_parse_line = NR
        if (pending_prune_in_fence) prune_before_guard = 1
        next
    }

    # Inside the guarded if: track depth so nested else/fi cannot
    # mis-classify the outer arm.
    if (in_guarded) {
        # Nested if open. `elif` is treated as switching out of the
        # then-arm into an unclassified arm at depth 0 — our contract is
        # plain `if/then/else/fi`, so an `elif` between guard arms is a
        # structural change worth flagging by mis-matching.
        if (trimmed ~ /^if[[:space:]]/) {
            nest++
            next
        }
        if (trimmed ~ /^elif[[:space:]]/) {
            if (nest == 0) {
                arm = "elif"
            }
            next
        }
        # else at outer depth toggles the arm.
        if (nest == 0 && trimmed ~ /^else([[:space:]]|$)/) {
            arm = "else"
            next
        }
        # fi: pop nested first, else close the outer guard.
        if (trimmed ~ /^fi([[:space:]]|$)/) {
            if (nest > 0) {
                nest--
            } else {
                in_guarded = 0
                arm = ""
            }
            next
        }

        # Pattern detection only fires at outer depth (nest == 0). A
        # worktree-add wrapped in a nested if would be a structural
        # change — failing here is the intended signal.
        if (nest == 0) {
            if (arm == "then" && match(trimmed, REATTACH)) {
                reattach_seen = 1
                reattach_line = NR
            }
            if (arm == "else" && match(trimmed, FRESH)) {
                fresh_seen = 1
                fresh_line = NR
            }
        }
    }
}

END {
    printf "rev_parse=%d\n", rev_parse_seen
    printf "reattach=%d\n", reattach_seen
    printf "fresh=%d\n", fresh_seen
    printf "prune=%d\n", prune_seen
    printf "prune_before_guard=%d\n", prune_before_guard
    printf "rev_parse_line=%d\n", rev_parse_line
    printf "reattach_line=%d\n", reattach_line
    printf "fresh_line=%d\n", fresh_line
}
' "$file")

extract() {
    echo "$report" | awk -F= -v key="$1" '$1 == key { print $2; exit }'
}

rev_parse=$(extract rev_parse)
reattach=$(extract reattach)
fresh=$(extract fresh)
prune=$(extract prune)
prune_before_guard=$(extract prune_before_guard)

if [ "$rev_parse" != "1" ]; then
    violations+=("missing 'if ... rev-parse --verify refs/heads/rebase/{{issue}}' guard inside a [[steps]] bash block (recovery branch-reuse not gated)")
fi

if [ "$reattach" != "1" ]; then
    violations+=("missing 'worktree add \"\$WORKTREE_PATH\" \"rebase/{{issue}}\"' (no -b) in the then-arm of the rev-parse guard (recovery path absent or in wrong arm)")
fi

if [ "$fresh" != "1" ]; then
    violations+=("missing 'worktree add \"\$WORKTREE_PATH\" -b \"rebase/{{issue}}\" \"{{origin_remote}}/{{upstream_branch}}\"' in the else-arm of the rev-parse guard (create path absent or in wrong arm)")
fi

if [ "$prune" != "1" ]; then
    violations+=("missing 'worktree prune' inside a [[steps]] bash block (stale-worktree recovery absent)")
elif [ "$rev_parse" = "1" ] && [ "$prune_before_guard" != "1" ]; then
    # Only meaningful when the guard exists; if rev_parse=0 the "missing
    # guard" violation already covers the gap and the ordering note is
    # noise.
    violations+=("'worktree prune' must appear before the rev-parse guard in the same step bash (otherwise re-attach trips on stale .git/worktrees admin)")
fi

if [ ${#violations[@]} -eq 0 ]; then
    echo "mol-upstream-gc-rebase workspace-setup handles existing rebase/<issue> branch (recovery after worktree wipe)"
    exit 0
fi

echo "${#violations[@]} branch-reuse gap(s) in mol-upstream-gc-rebase workspace-setup — see tk-y883hr / tk-n5gldl"
for v in "${violations[@]}"; do
    echo "$v"
done
exit 2
