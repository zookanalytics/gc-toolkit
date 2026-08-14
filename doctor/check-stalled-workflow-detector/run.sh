#!/usr/bin/env bash
# Pack doctor check: the workflow-stall detector is shipped and wired.
#
# What it guards (tk-xesf6). A graph.v2 workflow whose frontier stops advancing emits
# nothing — no alarm, no escalation, no board entry. Every other consumer keys on
# BEADS, and a stalled workflow's beads are each individually healthy: open, in a
# queue, nothing malformed. Two signal-loom workflows sat silent for 2h and 7h and
# were found only because a human asked after the work by name.
#
# ...and from the OTHER direction (tk-1g9yw). The pass must file exactly ONE visit per
# stalled workflow. The original dedupe keyed the marker on the root's last-touch — but
# stamping the marker is a bd update, which bumps updated_at, the very field the key was
# read from, so the same workflow re-flagged every stall window, minting a fresh visit
# and a fresh converse session forever. One unrecoverable stall became a city-wide token
# burn (24 converse sessions grinding 13-23h). The marker is now keyed on the frontier
# set, with a visit-already-open guard as the primary bound; this check guards both, and
# a reconciliation that drops either restores the amplifier as silently as the blind spot.
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

    # ...and the marker must be keyed on the FRONTIER set, never the root's last-touch.
    # A last-touch key is self-defeating: stamping the marker is a bd update, every
    # update bumps updated_at — the very field the key is read from — so one stall
    # window later the SAME workflow re-flags, minting a fresh visit and converse
    # session, forever. That was the token amplifier (tk-1g9yw).
    grep -qF "stall_flagged=\$frontier_key" "$dir/$script" \
        || errors+=("$script: the dedupe marker is no longer keyed on the frontier set — if it reverted to the last-touch timestamp, stamping it bumps updated_at and the same workflow re-flags every stall window (the amplifier tk-1g9yw)")

    # The visit-already-open guard: ONE open visit per stalled root. A visit may sit
    # open indefinitely (the operator gets to it), so without this guard a stall whose
    # visit is still open is re-filed every pass, stacking a converse session each time
    # — the same amplifier from the other direction. The guard matches open visits by
    # the stall_root the visit is stamped with.
    grep -qF "stall_root=\$root" "$dir/$script" \
        || errors+=("$script: the visit-already-open guard is gone — a stalled workflow whose visit is still open would be re-filed every pass, stacking a converse session each time (the amplifier tk-1g9yw)")

    # ...and the marker may only be stamped over a signal that DURABLY routed. A visit
    # missing gc.routed_to/task_kind/gc.continuation_group is offered to no pool and
    # resolved by no board row, so a --set-metadata that exits 0 without persisting
    # would retire the stall on a bead nobody is ever handed — this pass's own defect,
    # re-created by the pass, with the dedupe marker asserting it was reported.
    grep -q 'did not read back as routed' "$dir/$script" \
        || errors+=("$script: the visit routing read-back is gone — the dedupe marker would be stamped over an unrouted visit, and the workflow goes silent again while the root records that it was signalled")

    # The frontier holds only beads that can take demand. graph.v2 pours inert
    # descriptor beads next to its steps (gc.kind=spec/scope) which are ready and
    # unroutable BY CONSTRUCTION, so they satisfy the unclaimable test forever without
    # meaning it — 7 of the 8 beads in one live report were spec beads, telling the
    # operator to route beads that cannot be routed. And because the frontier set is
    # also the dedup key, ids that never close pin the key to constants and suppress
    # re-reports after the real frontier has moved (tk-6mccf).
    grep -q 'is_executable_kind' "$dir/$script" \
        || errors+=("$script: the frontier no longer filters on executable gc.kind — graph.v2's own inert descriptor beads (spec/scope) are ready and unroutable forever, so every mol-scoped-work graph reads as stalled through them, and they dominate the dedup key (tk-6mccf)")

    # ...and that allow-list must be the dispatcher's WHOLE vocabulary. beadmeta.ControlKinds
    # is exactly eight; the first cut of the filter was sampled from this rig's ledger, which
    # had never poured five of them, and a kind missing from an allow-list does not fail
    # loudly — it reads as INERT. An unrouted `check`/`ralph`/`fanout`/`drain`/`retry-eval`
    # frontier filters to empty, the workflow is counted as a descriptor-only wait, and the
    # stall goes unreported. That is the missing-route class the pass exists to surface, so
    # a narrowing here re-creates the blind spot inside the fix for it.
    for kind in retry ralph check retry-eval fanout drain scope-check workflow-finalize; do
        sed -n '/^is_executable_kind()/,/^}/p' "$dir/$script" \
            | grep -qE "(^|\|)[[:space:]]*${kind}[[:space:]]*(\||\))" \
            || errors+=("$script: is_executable_kind no longer allows gc.kind=$kind — beadmeta.ControlKinds has exactly eight members (internal/beadmeta/kindsets.go, one ProcessControl case each) and an unnamed control kind reads as inert, so an unrouted one filters the frontier to empty and its stall is never reported (tk-6mccf)")
    done

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
    grep -q 'UNROUTED' "$dir/$test_script" \
        || errors+=("$test_script: no unrouted-visit case — that a routing write which exits 0 and persists nothing leaves the stall un-retired is unproven, and a stub that always agrees would never show it")
    grep -q 'INERT' "$dir/$test_script" \
        || errors+=("$test_script: no descriptor-only-frontier case — that a frontier of nothing but graph.v2's own inert spec/scope beads is NOT reported as a stall is unproven (tk-6mccf)")
    grep -q 'MIXED' "$dir/$test_script" \
        || errors+=("$test_script: no mixed-frontier case — that descriptor beads are dropped from BOTH the report and the stall_flagged key, while the real step is still reported, is unproven; that key is what suppresses re-reports once the real frontier moves (tk-6mccf)")
    grep -q 'CONTROL' "$dir/$test_script" \
        || errors+=("$test_script: no control-kind case — that all eight beadmeta.ControlKinds survive the frontier filter is unproven, and five of them have never been poured in this rig, so nothing else in the suite would notice them being dropped back out (tk-6mccf)")
    grep -q 'REPEAT' "$dir/$test_script" \
        || errors+=("$test_script: no repeated-pass case — that ONE visit is filed per stalled bead across passes (the guard while the visit is open, the frontier marker once it is closed) is unproven, and a stub that never bumps updated_at would hide the re-flag amplifier tk-1g9yw fixed")
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
