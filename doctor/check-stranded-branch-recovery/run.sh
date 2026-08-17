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
# formulas/mol-witness-patrol.toml, a DELIBERATE MIRROR of a base artifact (see
# docs/gascity-packs.md §7a), so it is periodically reconciled against an
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

    # And it must be REACHED. The guard used to sit last, after the "branch is not on
    # origin" refusal had already returned — which made it unreachable for the one
    # bead it protects: a polecat carries `metadata.branch` from workspace-setup and
    # nothing on origin until it pushes, so every implementation outlasting the age
    # gate was marked as vanished work while it was healthily mid-edit (tk-pwm2g).
    # A reordering that puts any refusal back above the liveness resolution restores
    # that, and it is invisible from the outside — the marker is written on beads
    # whose work lands normally.
    awk '
      /MOLECULE_LIVE=1/              { if (!live) live = NR }
      /report_only .*BRANCH@missing/ { if (!miss) miss = NR }
      END { exit !(live && miss && live < miss) }
    ' "$dir/$script" \
        || errors+=("$script: the unpublished-branch refusal is no longer gated by the liveness resolution — a running polecat that has not pushed yet would be flagged as vanished work on every pass")

    # A refusal this pass can outlive has to be withdrawable. `<branch>@missing` is
    # the only marker that does not name a tip, so nothing about a later push expires
    # it, and the bead it sits on is usually handed to the refinery minutes later —
    # out of the candidate set, where no future pass would revisit it.
    grep -q -- '--unset-metadata stranded_branch_flagged' "$dir/$script" \
        || errors+=("$script: the stale-marker retraction is gone — a '<branch>@missing' marker would outlive the branch it claims never existed, on a bead a human reads next")

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

    # The handoff is VERIFIED, not merely issued. `gc bd update` reporting success is
    # not proof that a write is durable, and every write in this pass is best-effort,
    # so an assignee that sticks over a branch/target that did NOT both removes the
    # bead from this pass's candidate set (it is no longer unassigned) and hands the
    # refinery a branch to rebase onto a missing or stale base.
    grep -q 'read_handoff' "$dir/$script" \
        || errors+=("$script: the handoff read-back is gone — a branch/target write that reports success and is not durable would still reach the refinery, which would then rebase the work onto the wrong base with nothing left to retry it")

    # status=open is what makes a recovered bead VISIBLE at all. The refinery's
    # find-work polls `--assignee=$GC_AGENT --status=open` and the candidate scan
    # admits in_progress beads, so a handoff that does not set it assigns the bead to
    # an actor that never polls it — and, being assigned, it is no longer a candidate
    # here either. That is a strictly worse strand than the one the pass found.
    grep -q -- '--status=open' "$dir/$script" \
        || errors+=("$script: the handoff no longer sets status=open — the refinery's find-work step polls --status=open, so an in_progress strand would be handed to an actor that never sees it and would no longer be retryable by this pass")

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
    grep -q 'VERIFY' "$dir/$test_script" \
        || errors+=("$test_script: no unverified-handoff case — that a non-durable branch/target write stops the handoff BEFORE the assignee is unproven")
    grep -q 'INPROG' "$dir/$test_script" \
        || errors+=("$test_script: no in_progress-strand case — that a recovered bead is handed over as status=open, the only status the refinery's find-work polls, is unproven")
    grep -q 'LIVEMISS' "$dir/$test_script" \
        || errors+=("$test_script: no live-but-unpushed case — that the liveness gate is reached BEFORE the unpublished-branch refusal, and not merely present, is unproven")
    grep -q 'RETRACT' "$dir/$test_script" \
        || errors+=("$test_script: no retraction case — that a '<branch>@missing' marker is withdrawn once the branch appears on origin is unproven")
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
