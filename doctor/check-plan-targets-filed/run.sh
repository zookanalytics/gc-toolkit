#!/usr/bin/env bash
# doctor/check-plan-targets-filed — a landed plan's targets are a filing
# checklist. A table marked `<!-- plan-targets -->` claims that every one of its
# rows became tracked work; this check reads that claim back against the ledger.
# An unbound row is the silent drop the check exists to catch: a set can be
# three-quarters converted and still read as finished, because nothing else
# records which rows were dealt with.
# A bead ID is verified by membership in a store listing rather than by
# `bd show`, which returns an object instead of an array when nothing resolves.
# Read-only. Exit 0=OK 1=Warning 2=Error. stdout: first line = message, then
# "  - detail" lines. Probes bounded; an UNREADABLE store warns (1), never passes.

set -u

dir="${GC_PACK_DIR:-.}"
BOUND="${GC_DOCTOR_CHECK_TIMEOUT:-30}"

errors=(); warnings=(); notes=(); still_open=()
unbound=(); nomarker=(); unresolved=()
docs_seen=0; rows_seen=0; bead_rows=0; none_rows=0; landed_rows=0
run_bounded() { if command -v timeout >/dev/null 2>&1; then timeout "$BOUND" "$@" </dev/null; else "$@" </dev/null; fi; }
detail() { local v; for v in "$@"; do printf '  - %s\n' "$v"; done; }
strip_ctl() { tr -d '\000-\011\013-\037'; }

US=$'\037'

# Emits US-separated records: KIND, path, line, payload, extra.
# A ROW carries its binding state; a REF carries one bead ID cited in the
# binding cell. A row may cite more than one bead — a target whose halves were
# filed separately is exactly the shape that lost one of them — so every ID in
# the cell is emitted for verification, not just the one that opens it.
scan_awk='
function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
FNR == 1 { intable = 0; armed = 0; hdr = 0; fence = 0 }
{
    fline = trim($0)
    # A fenced block showing the convention is documentation of it, not an
    # instance, so nothing inside one is scanned.
    if (fline ~ /^(```|~~~)/) { fence = !fence; if (intable) { intable = 0; armed = 0 } next }
    if (fence) next
}
# The marker arms only as a standalone line. Prose naming it, as the rule and
# the skill both do, is a mention rather than a declaration.
fline ~ /^<!--[ \t]*plan-targets[ \t]*-->$/ { armed = 1; armed_line = FNR; intable = 0; hdr = 0; next }
{
    line = trim($0)
    isrow = (substr(line, 1, 1) == "|")
    if (!isrow) {
        if (intable) { intable = 0; armed = 0 }
        else if (armed && line != "") { print "NOTABLE" US FILENAME US armed_line US "" US ""; armed = 0 }
        next
    }
    if (!armed && !intable) next
    if (armed && !intable) { intable = 1; armed = 0; hdr = 1; next }
    if (hdr) { hdr = 0; next }
    n = split(line, f, "|")
    last = (substr(line, length(line), 1) == "|") ? n - 1 : n
    cell = (last >= 2) ? trim(f[last]) : ""
    state = "UNBOUND"
    if (match(cell, /^`[a-z][a-z0-9]*-[a-z0-9]+(\.[0-9]+)?`/)) state = "BEAD"
    else if (tolower(cell) ~ /^none[^a-z0-9]/ && trim(substr(cell, 5)) ~ /[a-z0-9]/) state = "NONE"
    else if (tolower(cell) ~ /^landed:/ && trim(substr(cell, 8)) != "") state = "LANDED"
    print "ROW" US FILENAME US FNR US state US ((state == "UNBOUND") ? line : "")
    rest = cell
    while (match(rest, /`[a-z][a-z0-9]*-[a-z0-9]+(\.[0-9]+)?`/)) {
        print "REF" US FILENAME US FNR US substr(rest, RSTART + 1, RLENGTH - 2) US ""
        rest = substr(rest, RSTART + RLENGTH)
    }
}
END { if (armed) print "NOTABLE" US FILENAME US armed_line US "" US "" }
'

mapfile -t md_files < <(find "$dir" -name '*.md' -type f -not -path '*/generated/*' -not -path '*/.git/*' 2>/dev/null | sort)
if [ "${#md_files[@]}" -eq 0 ]; then
    echo "no markdown documents found under $dir — plan checklists could not be examined"
    detail "A pack with no documents cannot be shown to have converted its plan targets."
    exit 1
fi

# An enumeration fed by a here-string goes silently empty when its backing temp
# file cannot be written, which reads exactly like a clean pack. Route it
# through a checked file and assert the row count instead.
records_file=$(mktemp 2>/dev/null) || {
    echo "cannot scan for plan checklists (mktemp failed)"
    detail "Scratch space is unavailable, so an empty result here would be indistinguishable from a clean pack."
    exit 1
}
trap 'rm -f "$records_file"' EXIT
printf '%s\n' "${md_files[@]}" | xargs -d '\n' awk -v US="$US" "$scan_awk" > "$records_file" 2>/dev/null
expected=$(wc -l < "$records_file" 2>/dev/null | tr -d ' ')
[ -n "$expected" ] || expected=0

declare -A wanted_ids=()
processed=0
while IFS="$US" read -r kind path line payload extra; do
    processed=$((processed + 1))
    [ -n "$kind" ] || continue
    rel="${path#"$dir"/}"
    case "$kind" in
        ROW)
            rows_seen=$((rows_seen + 1))
            case "$payload" in
                BEAD)    bead_rows=$((bead_rows + 1)) ;;
                NONE)    none_rows=$((none_rows + 1)) ;;
                LANDED)  landed_rows=$((landed_rows + 1)) ;;
                *)       unbound+=("$rel:$line: ${extra:0:120}") ;;
            esac ;;
        REF)
            wanted_ids["$payload"]="${wanted_ids[$payload]:-}${wanted_ids[$payload]:+, }$rel:$line" ;;
        NOTABLE) nomarker+=("$rel:$line") ;;
    esac
done < "$records_file"

if [ "$processed" -ne "$expected" ]; then
    echo "plan-checklist scan did not complete ($processed of $expected rows read)"
    detail "A partial read would under-report unbound rows, so this is not a pass."
    exit 1
fi
docs_seen=$(awk -v US="$US" -F"$US" '$1 == "ROW" && $2 != "" { print $2 }' "$records_file" 2>/dev/null | sort -u | grep -c .)
[ -n "$docs_seen" ] || docs_seen=0

# --- resolve every referenced bead against the reachable stores ---------------
resolved_any=0
if [ "${#wanted_ids[@]}" -gt 0 ]; then
    rigs_raw=$(run_bounded gc rig list --json 2>/dev/null); rigs_rc=$?
    scopes=$(printf '%s' "$rigs_raw" | jq -r '.rigs[]? | select((.path // "") != "")
        | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path, ((.suspended // false) | tostring)]
        | join("\u001f")' 2>/dev/null)
    if [ "$rigs_rc" -ne 0 ] || [ -z "$scopes" ]; then
        warnings+=("could not list bead stores (\`gc rig list --json\` rc=$rigs_rc); ${#wanted_ids[@]} bead reference(s) were NOT verified")
    else
        declare -A known=()
        while IFS="$US" read -r rig_name rig_path suspended; do
            [ -n "$rig_path" ] || continue
            label="${rig_name:-<city>}"
            if [ "$suspended" = "true" ]; then
                notes+=("$label: skipped (suspended — querying its store would auto-start an orphan Dolt server)")
                continue
            fi
            raw=$(run_bounded bd list --db "$rig_path/.beads" --status open,closed --json --limit 0 2>/dev/null); rc=$?
            if [ "$rc" -ne 0 ] || [ -z "$raw" ]; then
                warnings+=("$label: could not list beads in $rig_path/.beads (rc=$rc) — bead references were NOT verified against this store")
                continue
            fi
            ids=$(printf '%s' "$raw" | strip_ctl | jq -r '.[]? | "\(.id // "")\t\(.status // "?")"' 2>/dev/null)
            if [ -z "$ids" ]; then
                warnings+=("$label: bead listing from $rig_path/.beads could not be parsed — bead references were NOT verified against this store")
                continue
            fi
            resolved_any=1
            while IFS=$'\t' read -r one st; do [ -n "$one" ] && known["$one"]="$st"; done <<< "$ids"
        done <<< "$scopes"

        if [ "$resolved_any" -eq 1 ]; then
            still_open=()
            for id in "${!wanted_ids[@]}"; do
                st="${known[$id]:-}"
                if [ -z "$st" ]; then unresolved+=("$id (cited at ${wanted_ids[$id]})")
                elif [ "$st" != "closed" ]; then still_open+=("$id [$st]")
                fi
            done
            if [ "${#still_open[@]}" -gt 0 ]; then
                shown=""; n=0
                for s in "${still_open[@]}"; do
                    n=$((n + 1)); [ "$n" -gt 10 ] && break
                    shown="${shown}${shown:+, }$s"
                done
                [ "${#still_open[@]}" -gt 10 ] && shown="$shown, +$(( ${#still_open[@]} - 10 )) more"
                notes+=("${#still_open[@]} of ${#wanted_ids[@]} bound bead(s) still outstanding: $shown")
            fi
        else
            warnings+=("no bead store could be read; ${#wanted_ids[@]} bead reference(s) were NOT verified")
        fi
    fi
fi

# --- report -------------------------------------------------------------------
if [ "${#unbound[@]}" -gt 0 ]; then
    errors+=("${#unbound[@]} target row(s) bind to nothing — the row schedules work that nothing tracks:")
    for u in "${unbound[@]}"; do errors+=("    $u"); done
fi
if [ "${#unresolved[@]}" -gt 0 ]; then
    errors+=("${#unresolved[@]} bead reference(s) resolve in no reachable store:")
    for u in "${unresolved[@]}"; do errors+=("    $u"); done
fi
if [ "${#nomarker[@]}" -gt 0 ]; then
    warnings+=("${#nomarker[@]} \`<!-- plan-targets -->\` marker(s) introduce no table: ${nomarker[*]}")
fi

summary="$docs_seen document(s), $rows_seen target row(s): $bead_rows bead-bound, $none_rows deliberate none, $landed_rows landed"
if [ "$rows_seen" -eq 0 ]; then
    notes+=("No document in this pack declares a \`<!-- plan-targets -->\` checklist, so no plan's target list is being watched.")
fi

if [ "${#errors[@]}" -gt 0 ]; then
    echo "a plan's target list schedules work that nothing tracks ($summary)"
    detail "${errors[@]}"
    [ "${#warnings[@]}" -gt 0 ] && detail "${warnings[@]}"
    [ "${#notes[@]}" -gt 0 ] && detail "${notes[@]}"
    exit 2
fi
if [ "${#warnings[@]}" -gt 0 ]; then
    echo "plan target lists partially verified ($summary)"
    detail "${warnings[@]}"
    [ "${#notes[@]}" -gt 0 ] && detail "${notes[@]}"
    exit 1
fi
echo "every declared plan target binds to tracked work ($summary)"
[ "${#notes[@]}" -gt 0 ] && detail "${notes[@]}"
exit 0
