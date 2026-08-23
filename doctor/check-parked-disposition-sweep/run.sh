#!/usr/bin/env bash
# Pack doctor check: the parked-disposition sweep is shipped and wired.
#
# What it guards (tk-2cyxo). A `gc.takeaway` stamp parks the board row at LOW AND
# mutes the stall detector, so the one automation in the city that files visits is
# silenced by the exact stamp that records the wait. A subject that dispatched work
# could only be brought back by the operator noticing a row: tk-z9nln parked "next
# sitting when findings land", the findings landed at 17:54Z, and the operator found
# it by eye at 22:13Z — 4h19m in which nothing in the system had noticed.
#
# ...and from the OTHER direction (tk-1g9yw). The pass files a visit, which spawns a
# converse session. A signal that is not keyed to an OBSERVATION is a signal every
# pass, and this runs from a patrol — one unrecoverable case became 24 sessions
# grinding for 13-23h the last time that happened. Both bounds are guarded here.
#
# Why a doctor check rather than trust. The call site lives in
# formulas/mol-witness-patrol.toml, a DELIBERATE MIRROR of a base artifact (see
# docs/gascity-packs.md §7a), so it is periodically reconciled against an upstream
# that does not carry this pass. A reconciliation that drops the step restores the
# blind spot silently — and silence is the whole defect, so nothing would report it.
# The script existing without a caller is the same failure, and so is the script
# existing without its PRODUCER: the sweep selects on `gc.origin=operator`, and if
# gc-visit-open.sh stops stamping that key the population quietly becomes empty and
# the pass reports "no parked operator-origin subjects, and nothing holding" forever.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

dir="${GC_PACK_DIR:-.}"
script="assets/scripts/detect-parked-dispositions.sh"
test_script="assets/scripts/detect-parked-dispositions.test.sh"
producer="assets/scripts/gc-visit-open.sh"
backfill="assets/scripts/backfill-operator-origin.sh"
backfill_test="assets/scripts/backfill-operator-origin.test.sh"
formula="formulas/mol-witness-patrol.toml"
errors=()

# --- the pass itself -------------------------------------------------------
if [ ! -s "$dir/$script" ]; then
    errors+=("missing: $script — nothing brings a parked conversation back when its routed work lands")
else
    [ -x "$dir/$script" ] \
        || errors+=("$script is not executable — the call site guards on -x, so a non-executable script is silently never run")

    # THE scope ruling (operator, 2026-08-22): the DISPOSITION arm covers
    # operator-origin subjects only, because that is the set where a standing
    # expectation of an answer exists. Widening it files visits on every parked
    # conversation in the rig. (The stranded-hold arm carries no origin filter and is
    # not scoped by this ruling — a hold is by contract a wait on the operator
    # whoever filed the subject — but it is bounded by the hold predicate instead,
    # checked below.)
    grep -qF 'if [ "$origin" = "operator" ] && [ "$READY" = "1" ] && [ "$flagged" != "$LANDED_KEY" ]; then' "$dir/$script" \
        || errors+=("$script: the disposition arm no longer requires gc.origin=operator — the ruling scopes it to operator-origin subjects, and without the filter every parked conversation in the rig gets a visit and a converse session")

    # THE readiness half the board cannot express. A sitting files its routed work as
    # a CHILD of the subject, and a parent cannot be blocked by its own descendant, so
    # the canonical converse shape has no `waiting_on` edge at all. Keyed on blocks
    # edges alone this pass cannot fire for the subject the incident was measured on.
    grep -q 'list --parent' "$dir/$script" \
        || errors+=("$script: the child half of the recorded wait is gone — a converse sitting files its routed work as a CHILD (a parent cannot be blocked by its descendant, so there is no waiting_on edge), so a blocks-only predicate never fires for the canonical shape")

    # ...and the at-least-one half. Without it every parked conversation that routed
    # NOTHING reads as ready forever — the ordinary "we talked, here is the
    # conclusion" park, which is most of them.
    #
    # Anchored on the READY computation in the PASS, not on the `-z "$WAIT_IDS"` test
    # in the --wait-spent verb: both exist, they say the same thing, and matching the
    # loose string keeps this check green while the pass's own guard is gone.
    grep -qF '[ -n "$WAIT_IDS" ] && [ -z "$WAIT_OPEN" ] && READY=1' "$dir/$script" \
        || errors+=("$script: the at-least-one-recorded-wait guard is gone from the pass — a park that routed nothing has an empty wait set, which trivially satisfies 'all closed', so every such park would be signalled")

    # The dedupe marker, and that it is keyed on the OBSERVATION. A key keyed on a
    # timestamp is self-defeating: stamping the marker is a bd update, every update
    # bumps updated_at, so the same subject re-files every pass forever (tk-1g9yw).
    grep -qF "disposition_flagged=\$LANDED_KEY" "$dir/$script" \
        || errors+=("$script: the dedupe marker is no longer keyed on the landed id set — a timestamp key is invalidated by its own stamp and re-files the same subject every pass, minting a converse session each time (the amplifier tk-1g9yw)")

    # --- the stranded-hold arm (tk-jsyci7) ---------------------------------
    # The second observation, and the three things that keep it from manufacturing
    # work. It exists because the field that RECORDS a hold is the field that MUTES
    # the stall detector, and the un-mute keys on a recorded wait closing — which a
    # hold, waiting on a human answer, never has. Measured: tk-fhlv4, 10h16m
    # unattended and permanently invisible, because its disposition marker had
    # already retired the other arm.
    grep -qF 'test("^holding' "$dir/$script" \
        || errors+=("$script: the hold predicate is gone — nothing then distinguishes a sitting reaped mid-hold from an ordinary park, and the case tk-fhlv4 was measured on goes back to being invisible")

    # The half that keeps it off work still in flight. A hold whose recorded wait is
    # OPEN is waiting, not stranded, and the disposition arm fires for it when that
    # work lands. Drop this and every ordinary mid-flight hold becomes a visit about
    # work still in progress — the one thing this whole pass is written not to do.
    grep -qF '[ "$is_hold" = "1" ] && [ -z "$WAIT_OPEN" ]' "$dir/$script" \
        || errors+=("$script: the hold arm no longer requires the recorded wait to be empty of open ids — a hold that is merely mid-flight would be signalled, inviting the operator into a conversation about work still in progress")

    # The live-visit union must include stall_root. A takeaway lands on the ITEM, not
    # the shared bucket, so a stalled-workflow sitting stamps the ROOT while its
    # visit's continuation_group names the triage subject. This guard is the ONLY one
    # standing there: gc-helm.sh open's own already-held check reads the stamp and the
    # tracks edge only, so it would file the duplicate rather than refuse it.
    grep -qF '(((.metadata // {}).stall_root // "") | tostring),' "$dir/$script" \
        || errors+=("$script: stall_root is gone from the live-visit union — an item a live sitting holds as its stall_root reads as having no visit, and the hold arm files a second one onto a conversation in progress")

    # Keyed on the HOLD, and recorded by BOTH arms. `hold_flagged=<gc.takeaway_at>`
    # says which hold was last put in front of converse; a dispose filing records it
    # too, or the two arms amplify each other — a sitting concludes a disposition
    # visit and closes it WITHOUT clearing a takeaway that still begins "holding",
    # which is ordinary, and the next pass reads a stranded hold. One visit per round,
    # forever, which is the amplifier tk-1g9yw in a new place.
    grep -qF 'MARK2="hold_flagged=$tk_at"' "$dir/$script" \
        || errors+=("$script: a disposition filing no longer records the hold stamp — closing its visit hands the same subject straight to the hold arm, and the two arms amplify each other one visit per pass")

    # The filing goes through gc-helm.sh open — the one place the canonical gate-visit
    # block lives, which also owns the subject-exists gate, the one-open-visit-per-
    # subject gate (matching BOTH recordings of a visit's subject) and the board cache
    # bust. A hand-rolled create here loses three of those four.
    grep -qF "\"\$HELM\" open" "$dir/$script" \
        || errors+=("$script: the filing no longer goes through gc-helm.sh open — that verb owns the canonical gate-visit block, the subject-exists gate, the one-open-visit-per-subject gate and the cache bust; a hand-rolled create re-derives all four and drifts from them")
    grep -qE '(^|[^-[:alnum:]_])(gc )?bd create' "$dir/$script" \
        && errors+=("$script: it creates a bead directly — visit filing lives in exactly one place (gc-helm.sh open's marked gate-visit block), and a second creator is how the metadata shape drifts")

    # The read-back. `open` exits 0 both when it files and when it finds an existing
    # visit, and a create that reports success without persisting is exactly what a
    # marker, stamped on trust, would retire forever.
    grep -q 'no open visit names this subject' "$dir/$script" \
        || errors+=("$script: the filing is no longer read back before the marker is stamped — a filing that exits 0 and persists nothing would retire the disposition on a conversation nobody ever had")

    # The takeaway is the durable record of what the sitting concluded, and the
    # operator's own headline on the board. The visit is ADDITIVE.
    grep -q -- '--set-metadata "gc.takeaway' "$dir/$script" \
        && errors+=("$script: it writes gc.takeaway — the takeaway is the record of what the sitting concluded and must never be cleared or rewritten by this pass")
    if grep -qE '(^|[^-[:alnum:]_])(bd|gc bd) close|--status=closed' "$dir/$script"; then
        errors+=("$script: contains a bead-close path — this pass files a conversation, it never disposes of a subject")
    fi

    # Fail-safes: an unreadable listing must file NOTHING rather than read "no
    # children" as "nothing is waiting".
    grep -q 'FAIL-SAFE' "$dir/$script" \
        || errors+=("$script: the fail-safe refusals are gone — an unreadable listing would read as 'nothing is waiting' and file visits on work still in flight")

    # The shared predicate detect-stalled-workflows.sh asks for. Losing the flag does
    # not fail loudly there: that pass falls back to muting, and the carve-out silently
    # stops working.
    grep -q -- '--wait-spent' "$dir/$script" \
        || errors+=("$script: the --wait-spent query verb is gone — detect-stalled-workflows.sh asks it whether a takeaway's wait has ended, and its absence silently restores the mute that hid the stall")
fi

# --- the producer of the key it selects on ---------------------------------
if [ ! -s "$dir/$producer" ]; then
    errors+=("missing: $producer — the operator-origin intake front door, which is what stamps the key the sweep selects on")
else
    grep -q 'gc.origin=operator' "$dir/$producer" \
        || errors+=("$producer: it no longer stamps gc.origin=operator — the sweep's population silently becomes empty, and 'no parked operator-origin subjects, and nothing holding' reads exactly like a healthy pass. The prose line in the body is NOT a substitute: it has drifted across script generations and a --desc-contains sweep for it matches beads that merely quote it")
fi
[ -s "$dir/$backfill" ] \
    || errors+=("missing: $backfill — the subjects filed before the key existed keep the prose and nothing else, so the sweep cannot see them")
[ -s "$dir/$backfill_test" ] \
    || errors+=("missing: $backfill_test — the anchored intake-line match is what keeps the backfill off beads that merely quote the sentence, and it would have no executable proof")

# --- the regression test ---------------------------------------------------
if [ ! -s "$dir/$test_script" ]; then
    errors+=("missing: $test_script — the guards above would have no executable proof")
else
    [ -x "$dir/$test_script" ] || errors+=("$test_script is not executable")
    # The cases a refactor is most likely to quietly drop, each pinning one decision.
    grep -q 'CHILD' "$dir/$test_script" \
        || errors+=("$test_script: no closed-CHILD case — that the pass fires for the canonical converse shape (routed work filed as a child, so waiting_on is empty forever) is unproven, and that is the shape the incident was measured on")
    grep -q 'NOWAIT' "$dir/$test_script" \
        || errors+=("$test_script: no routed-nothing case — that an ordinary park is never signalled is unproven")
    grep -q 'NOTOP' "$dir/$test_script" \
        || errors+=("$test_script: no agent-origin case — that the ruling's narrow scope holds is unproven")
    grep -q 'HELD' "$dir/$test_script" \
        || errors+=("$test_script: no already-in-conversation case — one visit per subject is the primary bound on the converse fleet, and a subject whose visit stamp landed empty is skipped only if the TRACKS edge is matched too (su-ab9je)")
    grep -q 'REPEAT' "$dir/$test_script" \
        || errors+=("$test_script: no repeated-pass case — that ONE visit is filed across passes with the real updated_at bump in play is unproven, and a stub that never bumps would hide the amplifier tk-1g9yw fixed")
    grep -q 'VERIFY' "$dir/$test_script" \
        || errors+=("$test_script: no silent-filing case — that a filing which exits 0 without persisting leaves the disposition un-retired is unproven")
    grep -q 'NOCLEAR' "$dir/$test_script" \
        || errors+=("$test_script: no takeaway-preserved case — that the pass writes exactly one key and never touches the takeaway is unproven")
    grep -q 'HOLDSPENT' "$dir/$test_script" \
        || errors+=("$test_script: no already-disposed-then-re-parked case — that is tk-fhlv4's actual shape (its disposition marker equals its landed set, so that arm can never fire again), and it is the reason the hold arm exists at all")
    grep -q 'HOLDWAIT' "$dir/$test_script" \
        || errors+=("$test_script: no mid-flight-hold case — that a hold whose routed work is still open is never signalled is unproven, and that is the failure that would put the operator in a conversation about work in progress")
    grep -q 'HOLDSTALL' "$dir/$test_script" \
        || errors+=("$test_script: no stall_root case — that an item a LIVE sitting holds only through its visit's stall_root is skipped is unproven, and gc-helm.sh open does not catch that one")
    grep -q 'HOLDSPACEY' "$dir/$test_script" \
        || errors+=("$test_script: no non-ISO-stamp case — gc.takeaway_at is hand-editable, and a stamp with a space in it word-splits a joined marker list into a truncated key, after which the subject re-files every pass (tk-1g9yw through a quoting bug)")
    grep -q 'NOAMPLIFY' "$dir/$test_script" \
        || errors+=("$test_script: no cross-arm amplifier case — that closing a disposition visit does not hand the subject to the hold arm is unproven, and the takeaway is not cleared on the ordinary path")
    grep -q 'CENSUS' "$dir/$test_script" \
        || errors+=("$test_script: no bucket census — the skip buckets MASK each other (a park with no recorded wait has an empty landed key, which equals an empty marker, so dropping the at-least-one guard silently reclassifies it instead of filing), and the counts are the only place that shows it")
fi

# --- the call site ---------------------------------------------------------
if [ ! -s "$dir/$formula" ]; then
    errors+=("missing: $formula — the witness patrol that owns this pass")
else
    grep -q 'detect-parked-dispositions.sh' "$dir/$formula" \
        || errors+=("$formula: the witness patrol no longer calls detect-parked-dispositions.sh — the pass has no owner, and 'whichever session notices' is not one")
    grep -q 'id = "detect-parked-dispositions"' "$dir/$formula" \
        || errors+=("$formula: the detect-parked-dispositions step is gone from the patrol")
    # A step nothing depends on is never reached: the patrol chain is what runs it.
    grep -q 'needs = \["detect-parked-dispositions"\]' "$dir/$formula" \
        || errors+=("$formula: no step depends on detect-parked-dispositions, so the chain skips it — the next step must need it")
fi

if [ "${#errors[@]}" -eq 0 ]; then
    echo "OK: parked-disposition sweep shipped and wired (witness patrol detect-parked-dispositions step)"
    exit 0
fi

echo "parked-disposition sweep is not fully shipped/wired (${#errors[@]} issue(s))"
for e in "${errors[@]}"; do echo "  - $e"; done
exit 2
