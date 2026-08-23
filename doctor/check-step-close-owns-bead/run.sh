#!/usr/bin/env bash
# Pack doctor check: no step closes a bead on an id read from the environment.
#
# THE DEFECT.
#
#     gc bd update "$GC_TRIGGER_BEAD_ID" --set-metadata gc.outcome=pass --status=closed
#     [ -n "${GC_BEAD_ID:-}" ] && gc bd update "$GC_BEAD_ID" --status=closed
#
# Both spellings assume an environment variable names the step bead the shell is
# currently executing. Neither does.
#
#   $GC_BEAD_ID           is not populated in the step-execution environment at
#                         all (tk-7w69a). The guarded form short-circuits, the
#                         bead is never closed, and the graph re-offers the same
#                         step forever — with exit status 0 and no output.
#   $GC_TRIGGER_BEAD_ID   is NOT refreshed by `gc hook --claim` (tk-niu2f). After
#                         a claim it still holds whatever the session was spawned
#                         with, so the close lands on an unrelated bead.
#
# WHY THE SECOND ONE IS WORSE, and why this is an error rather than a warning.
# The first fails CLOSED: nothing is written and one workflow is visibly stuck.
# The second fails OPEN. Observed 2026-08-13: session lx-2m6c, executing
# mol-feedback-distiller.load-and-gate (tk-9b3d8), held
# GC_TRIGGER_BEAD_ID=tk-dy6cn — mol-feedback-miner.load-context, in_progress,
# owned by the live session lx-dq84. Running the formula as written closes
# another session's unexecuted step AND leaves its own step open: two molecules
# corrupted by one successful write, exit status 0, nothing in the log that reads
# as an error.
#
# WHY A CHECK AND NOT A CONVENTION. The idiom is self-evidently correct on
# reading — it is guarded, it names a variable that sounds exactly right, and it
# works whenever the session happens to still be on its spawn bead, which is
# every case anyone tests by hand. It got copy-pasted to 21 sites across four
# formulas before a run happened to claim into a session whose spawn bead was
# someone else's. Nothing about the source line distinguishes the safe run from
# the corrupting one, so review cannot catch it and a green run does not prove
# its absence.
#
# WHAT IS ASSERTED. No COMMAND line in the pack closes a bead whose id comes from
# a GC_*BEAD_ID environment variable. Both `bd close <id>` and `bd update <id>
# --status=closed` count, in quoted, braced, and bare spellings.
#
# WHAT IS NOT ASSERTED. Non-closing writes (`--set-metadata` on its own) are not
# flagged. They carry the same staleness, but a stray metadata write is
# recoverable and a stray CLOSE is what actually strands a workflow — and
# `$GC_TRIGGER_WORK_BEAD_ID` is a legitimate handle for exactly that kind of
# annotation. Prose is not flagged either: these formulas document the hazard by
# quoting it, and a check that cannot tell an explanation from an instruction
# would forbid writing the warning down.
#
# THE FIX. Close through the pack helper, which resolves the bead from the store
# by (assignee, gc.step_ref) — a pair that names exactly one bead and cannot go
# stale across a claim:
#
#     SC=""; for c in "${GC_PACK_DIR:-}" "${GC_RIG_ROOT:-}" ...; do
#       [ -x "$c/assets/scripts/step-close.sh" ] && { SC="$c/assets/..."; break; }
#     done
#     "${SC:?...}" --step <formula>.<step-id> --outcome pass
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

dir="${GC_PACK_DIR:-.}"

# An environment-supplied bead id as a command argument: "$GC_BEAD_ID",
# ${GC_TRIGGER_BEAD_ID}, "${GC_BEAD_ID:-}", or bare $GC_BEAD_ID.
ENV_ID='"?\$\{?GC_[A-Z_]*BEAD_ID'

# `bd close <env-id>` — the whole command is the close.
CLOSE_CMD='bd[[:space:]]+close[[:space:]]+'"$ENV_ID"
# `bd update <env-id> ... --status=closed` — the close is in the flags. Anchored
# so the id must be the UPDATE TARGET, not some later flag value.
UPDATE_CLOSE='bd[[:space:]]+update[[:space:]]+'"$ENV_ID"'[^|;&]*--status[= ]closed'

# A COMMAND line, not prose: optional leading whitespace, then the command
# itself or a test that guards it. Prose in these formulas quotes the banned
# idiom on purpose (including in this file's own header).
CMD_SHAPE='^[[:space:]]*(gc[[:space:]]+bd|bd|\[)[[:space:]]'

# base-snapshots: vendored upstream copies, never executed — the same exclusion
# check-pipefail-grep-q uses. The pack vendors none today (the check that kept
# them was retired, tk-3w7p7); the scope rule is what makes re-vendoring safe,
# so it stays.
#
# specs/: dated records of what was found or decided at the time, not
# instructions anyone executes. Several of them quote this exact defect *while
# diagnosing it* — specs/2026-08-fresh-start/live-adoption-findings-round3.md
# R3-07 is the live finding that named the `$GC_BEAD_ID` no-op — and editing a
# finding to satisfy a lint falsifies the record it exists to keep. Live docs
# under docs/ are NOT excluded: those state what is true now, and docs/
# gascity-packs.md §4 prescribing the broken idiom is how it reached four
# formulas in the first place.
#
# generated/: the machine-written tier. Everything under it is emitted by a
# script in this pack from sources this check already scans, and that property
# belongs to the TIER rather than to any one tree — so the rule is written once
# here and a second generated artifact inherits it without another case arm.
# Two things follow from a file being generated. It reports duplicates: whatever
# this check would find there, it already finds in the source the render read.
# And the findings it adds are unfixable in place —
# `generated/seed-audit/formulas/mol-shutdown-dance.md` carries a `bd close
# "$GC_BEAD_ID"` line from the builtin `core` pack, which this repo does not own,
# and editing the artifact only survives until the next render. Excluding the
# tier keeps the check pointed at files somebody can actually change (tk-yhwfv.3).
is_excluded() {
    case "$1" in
        */base-snapshots/*) return 0 ;;
        */specs/*) return 0 ;;
        */generated/*) return 0 ;;
        *) return 1 ;;
    esac
}

findings=()
scanned=0

scan_file() {
    local path="$1" line no body
    while IFS= read -r line; do
        no="${line%%:*}"
        body="${line#*:}"
        # A fully-commented line is documentation, not an instruction.
        case "$(printf '%s' "$body" | tr -d '[:space:]')" in
            '#'*) continue ;;
        esac
        grep -qE "$CMD_SHAPE" <<< "$body" || continue
        findings+=("$path:$no:${body#"${body%%[![:space:]]*}"}")
    done < <(grep -nE "$CLOSE_CMD"'|'"$UPDATE_CLOSE" "$path" 2>/dev/null)
}

while IFS= read -r f; do
    is_excluded "$f" && continue
    scanned=$((scanned + 1))
    scan_file "$f"
done < <(find "$dir" -type f \( -name '*.toml' -o -name '*.sh' -o -name '*.md' \) 2>/dev/null | sort)

if [ "${#findings[@]}" -gt 0 ]; then
    echo "${#findings[@]} step-close site(s) close a bead on an id taken from the environment — after a \`gc hook --claim\` that id can name ANOTHER session's bead"
    printf '%s\n' "${findings[@]}"
    echo "\`gc hook --claim\` does not refresh \$GC_TRIGGER_BEAD_ID, and \$GC_BEAD_ID is not set in the step environment at all. The first spelling closes someone else's in-progress step (fails open, exit 0); the second closes nothing and the step is re-offered forever (fails closed)."
    echo "Fix: close through assets/scripts/step-close.sh --step <formula>.<step-id>, which resolves the bead from the store by (assignee, gc.step_ref)."
    exit 2
fi

if [ "$scanned" -eq 0 ]; then
    echo "OK: no formula, script, or doc found under $dir — nothing to check"
    exit 0
fi

echo "OK: $scanned file(s) scanned; every step-bead close resolves its own id rather than reading it from the environment"
