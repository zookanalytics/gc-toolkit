#!/usr/bin/env bash
# Pack doctor check: the no-landing-path recovery is shipped and wired.
#
# What it guards (tk-f69ay). A polecat that pushes its branch and then dies before
# its submit step leaves completed work on origin that NOTHING will ever carry
# further: the bead is unassigned (so orphan recovery and the refinery's queue both
# step over it), unrouted (so it is not pool demand), and carries no PR and no
# merge_result (so every bead-keyed reconcile pass is blind to it). The witness's
# own salvage cases are correct to report "nothing to salvage" — the work is
# already committed and pushed — which is exactly why nothing escalates. The live
# case was found by a human reading beads.
#
# Why a doctor check rather than trust. The call site lives in
# formulas/mol-witness-patrol.toml, an ALLOWLISTED MIRROR of a base artifact (see
# check-base-artifact-collision), so it is periodically reconciled against an
# upstream that does not carry this pass. A reconciliation that drops the step
# restores the blind spot silently and in exactly the state where nothing reports
# it. The script existing without a caller is the same failure.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

dir="${GC_PACK_DIR:-.}"
script="assets/scripts/recover-stranded-branches.sh"
test_script="assets/scripts/recover-stranded-branches.test.sh"
formula="formulas/mol-witness-patrol.toml"
errors=()

# --- the pass itself -------------------------------------------------------
if [ ! -s "$dir/$script" ]; then
    errors+=("missing: $script — nothing detects completed work stranded with no landing path")
else
    [ -x "$dir/$script" ] \
        || errors+=("$script is not executable — the call site guards on -x, so a non-executable script is silently never run")

    # THE guard. A work bead is open + unassigned + unrouted for the whole time its
    # polecat is working it (mol-polecat-work assigns the polecat to the STEP beads,
    # never to the anchor), so "unassigned" describes every in-flight molecule too.
    # Without the liveness resolution this pass would hand a RUNNING polecat's branch
    # to the refinery mid-implementation — the one way it can do harm.
    grep -q 'convoy_is_live' "$dir/$script" \
        || errors+=("$script: the molecule-liveness gate is gone — an unassigned anchor is what every in-flight molecule looks like, so without it the pass hands running polecats' branches to the refinery")
    grep -q 'is_alive' "$dir/$script" \
        || errors+=("$script: the session-liveness lookup is gone — nothing can prove a molecule husked")

    # Both fail-safes. Each one, if lost, converts an unreadable input into a
    # confident wrong answer: an unread roster makes every live session look dead,
    # and an unreadable bead listing removes the molecule map the liveness gate is
    # decided from.
    grep -q 'FAIL-SAFE' "$dir/$script" \
        || errors+=("$script: the fail-safe refusals are gone — an unreadable roster or bead listing would be read as 'nothing is alive' and every candidate handed off")

    # A failed `gh pr list` must never read as "no PR exists": that is the check
    # standing between this pass and handing a branch that already has an open PR
    # to the refinery a second time.
    grep -q 'a failed read is not proof' "$dir/$script" \
        || errors+=("$script: the PR-lookup fail-closed arm is gone — a failed gh call would count as 'no PR' and the pass would re-hand a branch that already has one")

    # The repository pin. `gh pr list` resolved from ambient context answers about
    # whatever repository the caller happens to sit in; this pass runs from a patrol
    # worktree, and a wrong answer there is a wrong handoff.
    grep -q 'REPO_SLUG' "$dir/$script" \
        || errors+=("$script: the PR lookup is no longer pinned to the rig's own repository — gh would answer from ambient context")

    # Only the refinery closes a work bead, after verifying the merge. A close path
    # here would retire work that never landed.
    if grep -qE '(^|[^-[:alnum:]_])(bd|gc bd) close|--status=closed' "$dir/$script"; then
        errors+=("$script: contains a bead-close path — only the refinery closes a work bead, after verifying the merge")
    fi

    # Notes are APPENDED. A replacing --notes at handoff time destroys the mayor's
    # dispatch note on the exact bead a human is about to read (tk-q9e9y).
    if grep -qE '[[:space:]]--notes[[:space:]]' "$dir/$script"; then
        errors+=("$script: uses replacing --notes — the handoff must use --append-notes or it destroys the bead's existing notes")
    fi
fi

# --- the regression test ---------------------------------------------------
if [ ! -s "$dir/$test_script" ]; then
    errors+=("missing: $test_script — the guards above would have no executable proof")
else
    [ -x "$dir/$test_script" ] \
        || errors+=("$test_script is not executable")
    # The two cases that matter most are the ones a refactor is most likely to
    # quietly drop: a live molecule must survive untouched, and an unverified
    # handoff must not exit 0.
    grep -q 'LIVEROOT' "$dir/$test_script" \
        || errors+=("$test_script: no live-molecule case — the guard against handing off a running polecat's branch is unproven")
    grep -q 'FAILED' "$dir/$test_script" \
        || errors+=("$test_script: no failed-handoff case — a silent exit 0 over a failed write is how this class of bug hides")
fi

# --- the call site ---------------------------------------------------------
if [ ! -s "$dir/$formula" ]; then
    errors+=("missing: $formula — the witness patrol that owns this pass")
else
    grep -q 'recover-stranded-branches.sh' "$dir/$formula" \
        || errors+=("$formula: the witness patrol no longer calls recover-stranded-branches.sh — the pass has no owner, and 'whichever session notices' is not one")
    grep -q 'id = "recover-stranded-branches"' "$dir/$formula" \
        || errors+=("$formula: the recover-stranded-branches step is gone from the patrol")
    # A step nothing depends on is never reached: the patrol chain is what runs it.
    grep -q 'needs = \["recover-stranded-branches"\]' "$dir/$formula" \
        || errors+=("$formula: no step depends on recover-stranded-branches, so the chain skips it — the next step must need it")
    # The pass cannot repair anything without an identity to hand off to; it exits
    # 0 immediately when --refinery is absent.
    awk '/recover-stranded-branches\.sh/{found=1} found && /--refinery/{ok=1} END{exit !ok}' "$dir/$formula" \
        || errors+=("$formula: the call site does not pass --refinery — without a canonical identity the pass exits immediately and recovers nothing")
fi

if [ "${#errors[@]}" -eq 0 ]; then
    echo "OK: no-landing-path recovery shipped and wired (witness patrol recover-stranded-branches step)"
    exit 0
fi
echo "stranded-branch recovery mis-wired: ${#errors[@]} problem(s)"
printf '%s\n' "${errors[@]}"
exit 2
