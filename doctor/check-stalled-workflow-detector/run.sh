#!/usr/bin/env bash
# Pack doctor check: the workflow-stall detector is shipped and wired.
#
# What it guards (tk-xesf6). A graph.v2 workflow whose frontier stops advancing emits
# nothing — no alarm, no escalation, no board entry. Every other consumer keys on
# BEADS, and a stalled workflow's beads are each individually healthy: open, in a
# queue, nothing malformed. Two signal-loom workflows sat silent for 2h and 7h and
# were found only because a human asked after the work by name.
#
# Why a doctor check rather than trust. The call site lives in
# formulas/mol-witness-patrol.toml, an ALLOWLISTED MIRROR of a base artifact (see
# check-base-artifact-collision), so it is periodically reconciled against an upstream
# that does not carry this pass. A reconciliation that drops the step restores the
# blind spot silently — and silence is the whole defect, so nothing would report it.
# The script existing without a caller is the same failure.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

dir="${GC_PACK_DIR:-.}"
script="assets/scripts/detect-stalled-workflows.sh"
test_script="assets/scripts/detect-stalled-workflows.test.sh"
formula="formulas/mol-witness-patrol.toml"
errors=()

# --- the pass itself -------------------------------------------------------
if [ ! -s "$dir/$script" ]; then
    errors+=("missing: $script — nothing computes whether a workflow is still advancing")
else
    [ -x "$dir/$script" ] \
        || errors+=("$script is not executable — the call site guards on -x, so a non-executable script is silently never run")

    # THE discrimination. A rework molecule is poured against an anchor that ALREADY
    # carries the previous round's merge_result=pull_request, and mol-scoped-work
    # stamps that marker at its own submit step, before its graph finishes. Widening
    # the anchor test to the states quiesce-completed-workflows.sh calls terminal
    # exempts exactly the workflows this pass exists to find — it is what made both
    # live instances invisible.
    grep -q 'amerge" = "merged"' "$dir/$script" \
        || errors+=("$script: the anchor test no longer keys on merged — if it now accepts pull_request/pre_open_gate/refinery-handoff as proof of completion, every rework molecule's stall is exempt and the pass finds nothing")
    grep -q 'pull_request' "$dir/$script" \
        || errors+=("$script: the note explaining why pull_request must NOT exempt is gone — that is the one decision a later widening will get wrong")

    # The husk guard. Without it the pass reports every inline-execution molecule in
    # the rig (mol-polecat-work closes no step, ever), which is the escalation noise
    # tk-jbv0r and tk-76jxq are already about.
    grep -q 'closed_count" -eq 0' "$dir/$script" \
        || errors+=("$script: the zero-closed-step husk guard is gone — mol-polecat-work closes no step ever, so without it the pass reports most molecules in the rig")

    # Closed members are what date a workflow. A workflow's most recent event is
    # routinely a step CLOSING, so dating it by live members alone reports a workflow
    # that has just advanced.
    grep -q -- '--status=closed' "$dir/$script" \
        || errors+=("$script: the closed-member read is gone — a workflow's latest movement is usually a step closing, so it would be dated by its stale live members and reported as stalled")

    # Liveness. Implementation routinely outlasts any wall-clock threshold; the
    # roster is what protects a running molecule from being called stalled.
    grep -q 'is_alive' "$dir/$script" \
        || errors+=("$script: the session-liveness lookup is gone — every long-running implementation would be reported as a stalled workflow")

    # Fail-safes. Each one, if lost, turns an unreadable input into a confident wrong
    # answer: an unread roster makes every live molecule look unheld, and an
    # unreadable ready listing makes every frontier look unclaimable.
    grep -q 'FAIL-SAFE' "$dir/$script" \
        || errors+=("$script: the fail-safe refusals are gone — an unreadable roster or listing would be read as 'nothing is alive' and every workflow reported")

    # The dedupe marker. This patrol runs continuously, so a signal that is not keyed
    # to the observation is a signal every pass, forever.
    grep -q 'stall_flagged' "$dir/$script" \
        || errors+=("$script: the stall_flagged dedupe marker is gone — the witness patrol runs continuously, so every stalled workflow would be re-reported every pass")

    # Rows are joined on US (0x1f), never a tab. Tab is IFS whitespace: empty interior
    # fields collapse and every later field shifts left, so a workflow's TITLE lands
    # in triage.hold and reads as an operator hold. It suppresses real signals in
    # SILENCE, which is the exact failure mode this whole check exists against.
    grep -q 'join("\\u001f")' "$dir/$script" \
        || errors+=("$script: the row separator is no longer \\u001f — under IFS whitespace an empty triage.hold collapses and the title reads as a hold, silently suppressing every signal")

    # This pass reports; it never repairs. A close path here would retire a workflow
    # nobody has looked at.
    if grep -qE '(^|[^-[:alnum:]_])(bd|gc bd) close|--status=closed[^ ]' "$dir/$script"; then
        errors+=("$script: contains a bead-close path — this pass reports a stall, it never disposes of one")
    fi
fi

# --- the regression test ---------------------------------------------------
if [ ! -s "$dir/$test_script" ]; then
    errors+=("missing: $test_script — the guards above would have no executable proof")
else
    [ -x "$dir/$test_script" ] \
        || errors+=("$test_script is not executable")
    # The cases a refactor is most likely to quietly drop, each pinning one of the
    # decisions above.
    grep -q 'PRANCHOR' "$dir/$test_script" \
        || errors+=("$test_script: no pull_request-anchor case — that a rework molecule's stall is still reported is unproven, and that is the case both live instances wore")
    grep -q 'NEVER' "$dir/$test_script" \
        || errors+=("$test_script: no zero-closed-step case — the guard that keeps every inline-execution husk out of the report is unproven")
    grep -q 'CLOSEDMOVE' "$dir/$test_script" \
        || errors+=("$test_script: no closed-member-movement case — that a workflow which just advanced is not reported as stalled is unproven")
    grep -q 'DEDUP' "$dir/$test_script" \
        || errors+=("$test_script: no dedupe case — one signal per stalled workflow is unproven, and this patrol runs continuously")
    grep -q 'ROSTER' "$dir/$test_script" \
        || errors+=("$test_script: no unreadable-roster case — the fail-safe that stops every live molecule being reported is unproven")
fi

# --- the call site ---------------------------------------------------------
if [ ! -s "$dir/$formula" ]; then
    errors+=("missing: $formula — the witness patrol that owns this pass")
else
    grep -q 'detect-stalled-workflows.sh' "$dir/$formula" \
        || errors+=("$formula: the witness patrol no longer calls detect-stalled-workflows.sh — the pass has no owner, and 'whichever session notices' is not one")
    grep -q 'id = "detect-stalled-workflows"' "$dir/$formula" \
        || errors+=("$formula: the detect-stalled-workflows step is gone from the patrol")
    # A step nothing depends on is never reached: the patrol chain is what runs it.
    grep -q 'needs = \["detect-stalled-workflows"\]' "$dir/$formula" \
        || errors+=("$formula: no step depends on detect-stalled-workflows, so the chain skips it — the next step must need it")
fi

if [ "${#errors[@]}" -eq 0 ]; then
    echo "OK: workflow-stall detector shipped and wired (witness patrol detect-stalled-workflows step)"
    exit 0
fi
echo "workflow-stall detector mis-wired: ${#errors[@]} problem(s)"
printf '%s\n' "${errors[@]}"
exit 2
