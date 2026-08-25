#!/usr/bin/env bash
# Pack doctor check: the hold-a-dispatch mechanism stays wired end to end.
#
# WHAT IT GUARDS (tk-oqseh6). A polecat that HOLDS a dispatch before doing any
# work parks the bead. The documented park cleared the ANCHOR's `gc.routed_to`
# and its assignee — and nothing parked the MOLECULE. `mol-polecat-work`
# materializes seven chained step beads, each carrying
# `gc.routed_to=<rig>/<prefix>polecat`; the chain is dep-ordered, so
# `load-context` is the only unblocked step, the holder's drain releases the
# step assignees, and open + unassigned + routed + ready is exactly the pool's
# offer predicate. The dead chain is then served to every idle polecat, forever.
#
# WHY IT IS CHECKED RATHER THAN ASSUMED. Both halves are needed and only one of
# them is visible when it breaks:
#
#   * the WRITER can ship and go uncalled. A hold is a judgement an agent makes
#     mid-workflow; if the prompt does not name the script, the agent writes the
#     park by hand, which is what produced the defect. The bead still looks
#     parked afterwards, so nothing reports it.
#   * the PROMPT can name a script that is missing, unreadable, or not
#     executable. The fragment invokes it by path behind `[ -x ]`, so a
#     mis-shipped script degrades to the hand-park it was meant to replace —
#     silently, at the moment the agent is about to drain.
#
# Neither shows up in a bead, a log, or a test: the failure surfaces hours later
# as a fresh polecat holding a dead chain, and by then nothing connects it back.
# That silence is the defect, which is why the wiring is asserted.
#
# AND THE FOOTGUN IS ASSERTED ABSENT. Closing `load-context` to stop the churn
# unblocks `workspace-setup` and walks the next polecat onto a branch that may
# already be green-gated under a live review. It is also irreversible as a
# containment strategy: specs/tk-8m8d4 guard 2 records that a molecule with a
# closed step reads as "being driven step by step", so the witness's automated
# sweep declines it forever after. A close path acquired here would turn the
# remedy into a worse instance of the disease, so the check refuses to let one
# appear — in the script or in the instructions.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

dir="${GC_PACK_DIR:-.}"
script="$dir/assets/scripts/hold-dispatch.sh"
tests="$dir/assets/scripts/hold-dispatch.test.sh"
frag="$dir/template-fragments/polecat-close-step-chain.template.md"
pack="$dir/pack.toml"
errors=()

# Comments in this pack quote the hazards they warn about, so every source
# assertion below reads the CODE only. A check that cannot tell an explanation
# from an instruction would forbid writing the warning down.
code_only() { grep -vE '^[[:space:]]*#' "$1"; }

# --- the writer half ---------------------------------------------------------
if [ ! -s "$script" ]; then
    errors+=("missing script: assets/scripts/hold-dispatch.sh — without it the fragment's \`[ -x \]\` probe fails and the agent falls back to the hand-park this mechanism replaces")
else
    [ -x "$script" ] || errors+=("assets/scripts/hold-dispatch.sh is not executable — the fragment runs it by path")

    # The molecule half. A writer that parks only the anchor IS the defect.
    grep -q 'gc.root_bead_id' "$script" \
        || errors+=("hold-dispatch.sh never reads gc.root_bead_id — it cannot be walking the anchor's molecule, which is the whole point")
    grep -q 'gc.input_convoy_id' "$script" \
        || errors+=("hold-dispatch.sh never resolves gc.input_convoy_id — without the root->convoy->anchor walk it cannot prove a molecule belongs to the bead being held")

    # The escape path. The finalize step's control-dispatcher route is what
    # closes the graph out; de-routing it strands the molecule for good.
    grep -q 'workflow-finalize' < <(code_only "$script") \
        || errors+=("hold-dispatch.sh does not exempt workflow-finalize — de-routing it removes the molecule's only finalize path")
    grep -q 'control-dispatcher' < <(code_only "$script") \
        || errors+=("hold-dispatch.sh does not guard the control-dispatcher route — the finalize exemption must hold by route as well as by step id")

    # The footgun, asserted absent (see the header).
    if grep -qE -- '--status=closed|--status closed|bd close' < <(code_only "$script"); then
        errors+=("hold-dispatch.sh contains a close path — closing a step makes the husk PERMANENTLY unsweepable (specs/tk-8m8d4 guard 2) and walks the next polecat onto a branch that may be under review")
    fi
fi

# The regression the fragment points readers at has to exist, or the citation is
# the only thing guarding the behaviour.
[ -s "$tests" ] \
    || errors+=("missing tests: assets/scripts/hold-dispatch.test.sh — the fragment cites it as the regression for this behaviour")

# --- the instruction half ----------------------------------------------------
if [ ! -s "$frag" ]; then
    errors+=("missing fragment: template-fragments/polecat-close-step-chain.template.md — this is where a polecat is told what to do with its step chain before drain-ack")
else
    grep -q 'hold-dispatch.sh' "$frag" \
        || errors+=("polecat-close-step-chain does not name hold-dispatch.sh — a writer nothing tells anyone to call is the same silent hold, one layer down")
    # The fragment's other half: a held run must NOT run the close loop.
    grep -q 'steps-only' "$frag" \
        || errors+=("polecat-close-step-chain does not mention --steps-only — the duplicate-dispatch case parks a molecule whose anchor belongs to a live owner, and without it an agent will either hand-park or take the owner's claim")
    grep -qi 'never closed\|closes nothing\|not run the close loop' "$frag" \
        || errors+=("polecat-close-step-chain does not say that a held run closes NO step — the fragment's own close loop is directly above it, and applying it to a hold is the permanently-unsweepable footgun")

    # The instruction must honour the writer's exit status. hold-dispatch.sh
    # exits 1 on a PARTIAL park (a write did not land, or a step is held by
    # another session) and 2 when it refuses; both mean delivery keys are still
    # live somewhere in the molecule. A snippet that runs the writer and then
    # drains on the next line regardless reintroduces the exact defect the
    # writer was built to report — the session dies with the chain still
    # offerable, and the only evidence is a stderr line nobody reads. In the
    # shell shape an agent actually runs, a non-zero command does NOT stop the
    # next one, so the gate has to be spelled out in the prompt or it does not
    # exist. Scoped to the hold snippet: read from the invocation to the drain
    # it guards, so an unrelated `||` elsewhere in the fragment cannot satisfy
    # this and prose about the gate cannot satisfy it either.
    hold_drain=$(awk '
        /^[[:space:]]*"\$HD" --bead/ { seen = 1 }
        seen                          { print }
        seen && /drain-ack/           { exit }
    ' "$frag")
    if [ -z "$hold_drain" ]; then
        errors+=("polecat-close-step-chain no longer invokes \"\$HD\" --bead — the hold path lost its call to the one writer that parks anchor+molecule")
    elif ! grep -q 'drain-ack' <<< "$hold_drain"; then
        errors+=("polecat-close-step-chain invokes hold-dispatch.sh but never reaches gc runtime drain-ack — the hold path must still end the session, gated on the park having landed")
    elif ! grep -qE '\|\||&&' <<< "$hold_drain"; then
        errors+=("polecat-close-step-chain drains unconditionally after hold-dispatch.sh — a partial park (exit 1: a write did not land, or a foreign-held step) would drain the session with step delivery pins still live, which is the re-offer this mechanism exists to prevent")
    fi
fi

# --- the fragment actually reaches the polecat -------------------------------
# Injection parity across pools is check-polecat-fragment-sync's question; this
# is the narrower one that this mechanism depends on — an un-injected fragment
# ships the script to a prompt that never mentions it.
if [ ! -s "$pack" ]; then
    errors+=("missing pack.toml — cannot confirm the fragment is injected into the polecat prompt")
elif ! grep -q '"polecat-close-step-chain"' "$pack"; then
    errors+=("pack.toml does not inject polecat-close-step-chain — the fragment exists but no polecat prompt renders it")
fi

if [ "${#errors[@]}" -gt 0 ]; then
    echo "holding a dispatch is not wired end to end: a park would clear the anchor and leave its molecule re-offering itself forever"
    printf '  - %s\n' "${errors[@]}"
    exit 2
fi

echo "OK: hold-dispatch ships both halves — the one writer that parks anchor+molecule, and the injected polecat fragment that tells a holder to call it"
exit 0
