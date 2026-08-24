#!/usr/bin/env bash
# Pack doctor check: the `merge_result` state space is declared, and the code
# that writes it and the code that reads it are both held to that declaration.
#
# THE INVARIANT (docs/component-model.md §3, I2): the set of states is closed,
# and every state has exactly one handler.
#
# THE DEFECT. `merge_result` is the anchor's second state field, and its value
# set is the pack's own — nothing outside this repo constrains it. Seven
# literals were written across five files while every reader kept its own
# hand-maintained list of them, and the lists disagreed on the one case that
# matters, the value a list has never heard of:
#
#   refinery-reconcile.sh   excluded five values; anything else read as
#                           *not yet anchored* and was reported as a fresh
#                           handoff on every pass.
#   check-set-heal.sh       allows the two in-flight spellings; anything else
#                           reads as *terminal* and is left alone.
#
# Neither list contained `blocked` or `refused_false_completion`. Opposite
# defaults for the same unknown value, and the formula that specifies the
# second one concedes the gap in its own prose: "anything else, including a
# marker no pass here has heard of, reads as a disposition and is left alone."
#
# A hand-rolled list is not wrong when it is written. It is wrong on the day
# the eighth state lands, in whichever direction that list's default happens to
# point, and nothing about the list changes at that moment — which is why this
# is a check and not a convention.
#
# WHAT IS ASSERTED.
#
#   1. A single declared enumeration exists, in docs/work-bead-state-machine.md
#      between the `merge-result-state-space` fences, and it parses: every row
#      names a state and a kind, and both kinds are populated.
#   2. Every `merge_result=<literal>` written by pack code is a declared state,
#      and every declared state is written by at least one pack site. The
#      second half is what keeps the declaration from rotting into fiction —
#      a documented state nothing writes is as much a lie as an undocumented
#      one that is written.
#   3. Every reader that discriminates among two or more declared states either
#      names exactly one declared KIND-SET — all `handoff`, all `disposition`,
#      or the whole space — or carries an explicit declaration:
#
#          # merge-result-reader: covers=<states> default=<what an unknown does>
#
#      within the ten lines above it. Those are the two halves of "covers the
#      declared set, or declares its default", and a list that does neither is
#      an ERROR.
#
# WHY A KIND-SET PASSES WITHOUT A COMMENT. A reader keyed on a kind is not
# hand-rolling anything: it is naming a partition this declaration owns, and it
# stays correct when an eighth state lands because the declaration assigns that
# state a kind. That is the fix this check is steering toward, not a loophole —
# the escape hatch is the explicit declaration, which costs a reviewed sentence
# saying what an unrecognised value does.
#
# WHAT IS NOT ASSERTED. That a declared default is the RIGHT default. Two
# readers may legitimately disagree — `escalation-gate.sh` declining to treat
# an unknown value as a fault and `quiesce-completed-workflows.sh` declining to
# treat one as terminal are both the safe direction for their own pass, and
# they point opposite ways. What this check ends is the SILENT disagreement:
# after it, a default is a sentence someone wrote and a reviewer read.
#
# Nor is a single-value selector a reader. `--metadata-field merge_result=X`
# and `$mr == "X"` name one state and act on it; an undeclared value is simply
# not selected, which is closed under the state space by construction. The same
# goes for presence tests (`== ""`, `!= ""`), which discriminate ABSENT from
# ANY-VALUE — a partition adding a state cannot disturb. ABSENT is deliberately
# not a declared state; see the doc section for why.
#
# THIS CHECK DOES NOT EXEMPT ITSELF. doctor/*/run.sh is in scope, and the
# literals here are read out of the declaration at run time rather than spelled
# in this file, so the scanner below is applied to this file on the same terms
# as every other (the convention doctor/check-pipefail-grep-q set).
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details
#
# The declared set is carried as a space-separated string and iterated by
# splitting it, at ~8 sites. That is deliberate everywhere it appears and the
# string is never empty when it is split — the declaration parse above exits 2
# on an empty table — so the splitting is declared once here rather than at
# each site. bash 3.2 is in scope (the pack runs on macOS), which is also why
# the set is not an array.
# shellcheck disable=SC2086

set -u

dir="${GC_PACK_DIR:-.}"

DECL_DOC="docs/work-bead-state-machine.md"
OPEN_FENCE='<!-- merge-result-state-space: declared -->'
CLOSE_FENCE='<!-- /merge-result-state-space -->'
MARKER='merge-result-reader:'

# --- 1. Parse the declaration -----------------------------------------------
# Fail closed on every step. An unparseable declaration must never read as
# "nothing to check": that is the state this check exists to leave behind.

if [ ! -f "$dir/$DECL_DOC" ]; then
    echo "the merge_result state space is not declared — $DECL_DOC is missing"
    echo "This check reads the declared enumeration out of that file, between the fences $OPEN_FENCE and $CLOSE_FENCE. Without it there is no closed set to hold the code to, which is the condition component-model.md I2 records as FALSE."
    exit 2
fi

BLOCK=$(awk -v o="$OPEN_FENCE" -v c="$CLOSE_FENCE" '
    index($0, o) { inb = 1; next }
    index($0, c) { inb = 0 }
    inb { print }
' "$dir/$DECL_DOC" 2>/dev/null)

# Table rows only: | `state` | kind | ... |. The header and its separator are
# dropped by requiring a backticked first cell.
DECL_ROWS=$(printf '%s\n' "$BLOCK" | awk -F'|' '
    NF >= 4 && $2 ~ /`/ {
        s = $2; k = $3
        gsub(/[` \t]/, "", s); gsub(/[ \t]/, "", k)
        if (s != "" && k != "") print s "\t" k
    }')

DECL_STATES=""
DECL_PAIRS=""
HANDOFF=""
DISPOSITION=""
badkind=()
while IFS=$'\t' read -r s k; do
    [ -n "$s" ] || continue
    case "$k" in
        handoff)     HANDOFF="$HANDOFF $s" ;;
        disposition) DISPOSITION="$DISPOSITION $s" ;;
        *)           badkind+=("$s (kind '$k')"); continue ;;
    esac
    DECL_STATES="$DECL_STATES $s"
    DECL_PAIRS="$DECL_PAIRS $s:$k"
done <<< "$DECL_ROWS"

DECL_STATES="${DECL_STATES# }"
n_decl=$(printf '%s\n' $DECL_STATES | grep -c . )

if [ "${#badkind[@]}" -gt 0 ]; then
    echo "${#badkind[@]} declared merge_result state(s) carry a kind that is not handoff or disposition"
    printf '  %s\n' "${badkind[@]}"
    echo "The kind column is what readers key on, so an unrecognised kind silently removes that state from every kind-set. Use handoff (still in flight, a later pass is expected to act) or disposition (a pass has decided this unit is finished with the merge queue). Declared in $DECL_DOC."
    exit 2
fi

if [ "$n_decl" -eq 0 ] || [ -z "$HANDOFF" ] || [ -z "$DISPOSITION" ]; then
    echo "the merge_result state-space declaration in $DECL_DOC is empty or one-sided"
    echo "parsed states: ${DECL_STATES:-<none>}"
    echo "handoff: ${HANDOFF:-<none>}"
    echo "disposition: ${DISPOSITION:-<none>}"
    echo "The table between $OPEN_FENCE and $CLOSE_FENCE must have at least one row of each kind, written as | \`state\` | kind | ... |. Both kinds are load-bearing: a reader passes this check by naming one of them exactly, so an empty kind makes every such reader unclassifiable."
    exit 2
fi

is_declared() { # $1 = literal
    local s
    for s in $DECL_STATES; do [ "$s" = "$1" ] && return 0; done
    return 1
}

# --- 2. Scope ----------------------------------------------------------------
# Pack code that runs. Tests spell literals to build fixtures, specs and docs
# discuss them in prose, and generated/ is a rendered copy of formulas that
# doctor/check-seed-audit-current owns — none of them are a writer or a reader.
FILES=$( {
    find "$dir/assets/scripts" -type f -name '*.sh' ! -name '*.test.sh'
    find "$dir/formulas" -type f -name '*.toml'
    find "$dir/doctor" -type f -name 'run.sh'
    find "$dir/template-fragments" -type f -name '*.md'
    find "$dir/orders" -type f -name '*.toml'
    find "$dir/packs" -type f \( -name '*.sh' -o -name '*.toml' -o -name '*.md' \) ! -name '*.test.sh'
    find "$dir/tools" -type f
} 2>/dev/null | sort -u)

n_files=$(printf '%s\n' "$FILES" | grep -c . )
if [ "$n_files" -eq 0 ]; then
    echo "OK: no pack code found under $dir — nothing to hold to the declaration"
    exit 0
fi

rel() { printf '%s' "${1#"$dir"/}"; }

# --- 3. Writes ---------------------------------------------------------------
# Every write in this pack is a literal (no `merge_result=$VAR` site exists), so
# scanning literals is complete rather than a sample. A variable-valued write
# would defeat that, and is reported rather than passed over in silence.
undeclared=()
written=""
varwrite=()
while IFS= read -r f; do
    [ -n "$f" ] || continue
    while IFS= read -r ln; do
        no="${ln%%:*}"; body="${ln#*:}"
        stripped="${body#"${body%%[![:space:]]*}"}"
        case "$stripped" in '#'*) continue ;; esac
        lit=$(sed -E 's/.*--set-metadata[[:space:]]+merge_result=//; s/[^A-Za-z0-9_].*//' <<< "$body")
        if [ -z "$lit" ]; then
            varwrite+=("$(rel "$f"):$no: $(cut -c1-100 <<< "$stripped")")
            continue
        fi
        if is_declared "$lit"; then
            written="$written $lit"
        else
            undeclared+=("$(rel "$f"):$no: writes merge_result=$lit, which is not declared in $DECL_DOC")
        fi
    done < <(grep -nE -- '--set-metadata[[:space:]]+merge_result=' "$f" 2>/dev/null)
done <<< "$FILES"

unwritten=()
for s in $DECL_STATES; do
    found=0
    for w in $written; do [ "$w" = "$s" ] && { found=1; break; }; done
    [ "$found" -eq 0 ] && unwritten+=("$s")
done

# --- 4. Readers --------------------------------------------------------------
# A reader is a line that discriminates among two or more declared states. The
# literals must sit in a VALUE position — quoted, a case/alternation pattern, or
# a word in a `for X in ...` list — because these names are also ordinary
# English ("merged", "blocked", "abandoned") and this pack's prose uses them on
# nearly every page. Backticked prose is markup, not a value, and is skipped by
# the same rule.
ALT=$(printf '%s\n' $DECL_STATES | paste -sd'|' -)
FOR_IN='(^|[^A-Za-z0-9_])for[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]+in[[:space:]]'

set_of() { # echoes the sorted, space-joined set matched on a line
    printf '%s\n' $1 | sort | paste -sd' ' -
}
HANDOFF_SET=$(set_of "$HANDOFF")
DISPOSITION_SET=$(set_of "$DISPOSITION")
ALL_SET=$(set_of "$DECL_STATES")

undeclared_reader=()
bad_declaration=()
ok_readers=0
declared_readers=0

while IFS= read -r f; do
    [ -n "$f" ] || continue
    while IFS= read -r ln; do
        no="${ln%%:*}"; body="${ln#*:}"
        stripped="${body#"${body%%[![:space:]]*}"}"
        case "$stripped" in '#'*) continue ;; esac
        isfor=0
        grep -qE "$FOR_IN" <<< "$body" && isfor=1
        found=""
        for s in $DECL_STATES; do
            hit=0
            grep -qE "[\"']$s[\"']" <<< "$body" && hit=1
            grep -qE "(^|[[:space:]|(])$s[|)]" <<< "$body" && hit=1
            if [ "$isfor" -eq 1 ] && grep -qE "(^|[^A-Za-z0-9_])$s([^A-Za-z0-9_]|$)" <<< "$body"; then hit=1; fi
            [ "$hit" -eq 1 ] && found="$found $s"
        done
        cnt=$(printf '%s\n' $found | grep -c . )
        [ "$cnt" -ge 2 ] || continue
        got=$(set_of "$found")

        # (a) exactly one declared kind-set — nothing hand-rolled, no comment owed.
        if [ "$got" = "$HANDOFF_SET" ] || [ "$got" = "$DISPOSITION_SET" ] || [ "$got" = "$ALL_SET" ]; then
            ok_readers=$((ok_readers + 1))
            continue
        fi

        # (b) an explicit declaration in the ten lines above, or on the line.
        from=$(( no > 10 ? no - 10 : 1 ))
        decl=$(sed -n "${from},${no}p" "$f" 2>/dev/null | grep -F -- "$MARKER" | tail -1)
        if [ -z "$decl" ]; then
            undeclared_reader+=("$(rel "$f"):$no: keys on {${got}} — neither a declared kind-set nor a declared default
      $(cut -c1-110 <<< "$stripped")")
            continue
        fi
        covers=$(sed -E "s/.*${MARKER}[[:space:]]*//; s/.*covers=//; s/[[:space:]].*//" <<< "$decl")
        default=$(sed -E 's/.*default=//; s/[[:space:]]*$//' <<< "$decl")
        if [ -z "$default" ] || [ "$default" = "$decl" ]; then
            bad_declaration+=("$(rel "$f"):$no: the $MARKER declaration names no default=")
            continue
        fi
        if [ -z "$covers" ] || [ "$covers" = "$decl" ]; then
            bad_declaration+=("$(rel "$f"):$no: the $MARKER declaration names no covers=")
            continue
        fi
        badcov=""
        for c in $(tr ',' ' ' <<< "$covers"); do
            [ -n "$c" ] || continue
            [ "$c" = "absent" ] && continue
            is_declared "$c" || badcov="$badcov $c"
        done
        if [ -n "$badcov" ]; then
            bad_declaration+=("$(rel "$f"):$no: the $MARKER declaration covers${badcov}, which $DECL_DOC does not declare")
            continue
        fi
        declared_readers=$((declared_readers + 1))
    done < <(grep -nE "(^|[^A-Za-z0-9_])($ALT)([^A-Za-z0-9_]|$)" "$f" 2>/dev/null)
done <<< "$FILES"

# --- 5. Report ---------------------------------------------------------------
nerr=$(( ${#undeclared[@]} + ${#unwritten[@]} + ${#varwrite[@]} + ${#undeclared_reader[@]} + ${#bad_declaration[@]} ))
if [ "$nerr" -gt 0 ]; then
    echo "$nerr merge_result state-space finding(s): the declared set and the code have diverged"
    [ "${#undeclared[@]}" -gt 0 ] && printf 'UNDECLARED WRITE: %s\n' "${undeclared[@]}"
    [ "${#varwrite[@]}" -gt 0 ] && printf 'NON-LITERAL WRITE: %s\n' "${varwrite[@]}"
    [ "${#unwritten[@]}" -gt 0 ] && printf 'DECLARED BUT NEVER WRITTEN: %s\n' "${unwritten[@]}"
    [ "${#undeclared_reader[@]}" -gt 0 ] && printf 'HAND-ROLLED READER: %s\n' "${undeclared_reader[@]}"
    [ "${#bad_declaration[@]}" -gt 0 ] && printf 'MALFORMED DECLARATION: %s\n' "${bad_declaration[@]}"
    echo ""
    echo "Declared states: $ALL_SET"
    echo "  handoff     = $HANDOFF_SET"
    echo "  disposition = $DISPOSITION_SET"
    echo ""
    echo "Fix an UNDECLARED WRITE by adding the state to the table in $DECL_DOC with a kind, or by not writing it. Fix a DECLARED BUT NEVER WRITTEN state by removing its row — a state nothing writes is fiction, and readers that cover it are covering nothing. Fix a HAND-ROLLED READER by keying on a declared kind-set instead, or, when the set really is that reader's own judgement, by declaring it: put '# $MARKER covers=<states> default=<what an unrecognised value does>' within ten lines above the line. A NON-LITERAL WRITE defeats the scan entirely and must become a literal."
    exit 2
fi

echo "OK: $n_decl declared merge_result state(s), every literal written by pack code declared, $ok_readers reader(s) on a declared kind-set and $declared_readers with an explicit default"
echo "Declared: $ALL_SET (handoff = $HANDOFF_SET; disposition = $DISPOSITION_SET), parsed from $DECL_DOC"
echo "Scanned $n_files pack file(s)."
