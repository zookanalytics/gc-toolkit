#!/usr/bin/env bash
# doctor/check-gate-integrity — I6+I7 surface: gates are declared and their
# markers well-formed. Per store, every OPEN gating anchor (merge_result =
# pre_open_gate|pull_request) must declare a non-empty check_set — the "none"
# sentinel is the one legal opt-out; merge.sh reads empty as UNGATED, so an
# empty or absent declaration silently drops the gate (error). Every
# check.<g> marker (sidecar keys like check.<g>.reason excluded) must match
# the grammar green|fixable|exception@<40-hex oid> — a malformed marker is
# evidence bound to nothing (error). A green marker on an anchor with no
# branch metadata is a warning: the oid cannot be compared to any head.
# Charter-mandated gates are the third clause and WARN-ONLY: when the rig
# ships docs/review-charter.md, each open anchor's branch diff is re-derived
# and a gate the charter mandates for a touched path must be declared in
# check_set or waived on the anchor. This is the mechanical backstop for a
# triage miss; a missing charter, branch or diff is a skip, never a finding.
# A triage waiver suppresses the finding only at the commit check.triage last
# passed at: a push stales that marker, triage re-classifies the grown diff,
# and a waiver issued against a smaller one stops counting.
# Read-only. Exit 0=OK 1=Warning 2=Error. stdout: message, then "  - detail"
# lines. Probes bounded; an UNREADABLE store warns (1), never passes.

set -u

dir="${GC_PACK_DIR:-.}"
BOUND="${GC_DOCTOR_CHECK_TIMEOUT:-30}"
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
CHARTER_PARSER="$dir/assets/scripts/review-charter.sh"
[ -x "$CHARTER_PARSER" ] || CHARTER_PARSER="$HERE/../../assets/scripts/review-charter.sh"

errors=(); warnings=(); notes=()
run_bounded() { if command -v timeout >/dev/null 2>&1; then timeout "$BOUND" "$@" </dev/null; else "$@" </dev/null; fi; }
detail() { local v; for v in "$@"; do printf '  - %s\n' "$v"; done; }
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

rigs_raw=$(run_bounded gc rig list --json 2>/dev/null); rigs_rc=$?
scopes=$(printf '%s' "$rigs_raw" | jq -r '.rigs[]? | select((.path // "") != "")
    | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path, ((.suspended // false) | tostring)]
    | join("\u001f")' 2>/dev/null)
if [ "$rigs_rc" -ne 0 ] || [ -z "$scopes" ]; then
    echo "cannot determine gate integrity (I6/I7)"
    detail "\`gc rig list --json\` failed (rc=$rigs_rc) or listed no rig paths; there is no set of bead stores to scan."
    exit 1
fi

while IFS=$'\037' read -r rig_name rig_path suspended; do
    [ -n "$rig_path" ] || continue
    label="${rig_name:-<city>}"
    if [ "$suspended" = "true" ]; then
        notes+=("$label: skipped (suspended — querying its store would auto-start an orphan Dolt server)")
        continue
    fi
    raw=$(run_bounded bd list --db "$rig_path/.beads" --status open \
        --has-metadata-key merge_result --json --limit 0 2>/dev/null); rc=$?
    if [ "$rc" -ne 0 ] || [ -z "$raw" ]; then
        warnings+=("$label: could not list open anchors in $rig_path/.beads (rc=$rc) — this store was NOT checked")
        continue
    fi
    rows=$(printf '%s' "$raw" | scrub | jq -r '
        .[]? | (.metadata // {}) as $m
        | ((($m.merge_result // "") | tostring)) as $mr
        | select($mr == "pre_open_gate" or $mr == "pull_request")
        | ((.id // "?") | tostring | gsub("[[:cntrl:]]"; " ")) as $id
        | ((($m.check_set // "") | tostring)) as $cs
        | ((($m.branch // "") | tostring)) as $br
        | ( (if $cs == "" then [["nocs", $id, $mr, ""]] else [] end)
          + [ $m | to_entries[]
              | select(.key | test("^check\\.[^.]+$"))
              | select((.value | type) == "string")
              | (.value | gsub("[[:cntrl:]]"; " ")) as $v
              | (if ($v | test("^(green|fixable|exception)@[0-9a-f]{40}$")) | not
                 then ["badmark", $id, .key, $v]
                 elif ($v | startswith("green@")) and $br == ""
                 then ["greennobranch", $id, .key, $v]
                 else empty end) ] )[]
        | join("\u001f")' 2>/dev/null)
    if [ $? -ne 0 ]; then
        warnings+=("$label: anchor listing from $rig_path/.beads could not be parsed — this store was NOT checked")
        continue
    fi
    if [ -n "$rows" ]; then
        while IFS=$'\037' read -r kind id k v; do
            [ -n "$kind" ] || continue
            case "$kind" in
                nocs)          errors+=("$label bead $id: gating anchor (merge_result=$k) declares NO check_set — merge.sh reads empty as ungated, so this PR can land with no review; stamp the declared default (gate-ensure.sh) or the explicit \"none\" opt-out") ;;
                badmark)       errors+=("$label bead $id: gate marker $k=\"$v\" does not match the grammar <green|fixable|exception>@<40-hex oid> — a marker bound to no commit is not evidence, and merge.sh cannot compare it to the live head") ;;
                greennobranch) warnings+=("$label bead $id: $k=\"$v\" is green but the anchor records NO branch — nothing can verify the oid against a live head, so the marker's evidence binding is unverifiable") ;;
            esac
        done <<< "$rows"
    fi

    charter="$rig_path/docs/review-charter.md"
    menu=""
    if [ -r "$charter" ] && [ -x "$CHARTER_PARSER" ]; then
        menu=$(run_bounded "$CHARTER_PARSER" --file "$charter" 2>/dev/null)
    fi
    [ -n "$menu" ] || continue
    anchors=$(printf '%s' "$raw" | strip_ctl | jq -r '
        .[]? | (.metadata // {}) as $m
        | ((($m.merge_result // "") | tostring)) as $mr
        | select($mr == "pre_open_gate" or $mr == "pull_request")
        | ((($m.branch // "") | tostring)) as $br
        | select($br != "")
        | [ ((.id // "?") | tostring),
            (($m.check_set // "") | tostring),
            $br,
            (((($m.merged_target // "") | tostring)) as $t
             | if $t == "" then (($m.target // "") | tostring) else $t end),
            (((($m["check.triage"] // "") | tostring) | sub("^[a-z]+@"; "")) as $toid
             | ((.notes // "") | tostring)
             | [ scan("triage-waive:[[:space:]]*([A-Za-z0-9._-]+)[[:space:]]*@([0-9a-fA-F]+)")
                 | select($toid != "" and .[1] == $toid) | .[0] ] | join(",")) ]
        | @tsv' 2>/dev/null)
    [ -n "$anchors" ] || continue
    undiffed=0
    while IFS=$'\t' read -r a_id a_cs a_br a_tgt a_waived; do
        [ -n "$a_id" ] || continue
        [ -n "$a_tgt" ] || a_tgt=main
        # The `none` sentinel opts out of every gate obligation, mandatory rows
        # included: it is the human-only decision that this change is ungated.
        case "$(printf '%s' "$a_cs" | tr -d '[:blank:],' | tr '[:upper:]' '[:lower:]')" in
            none|off) continue ;;
        esac
        changed=$(run_bounded git -C "$rig_path" diff --name-only "origin/$a_tgt...origin/$a_br" 2>/dev/null) || changed=""
        if [ -z "$changed" ]; then undiffed=$((undiffed + 1)); continue; fi
        declared=",$(printf '%s' "$a_cs" | tr -d '[:blank:]' | tr '[:upper:]' '[:lower:]'),"
        while IFS=$'\t' read -r g_name g_method g_paths _; do
            [ -n "$g_name" ] || continue
            [ "$g_paths" = "-" ] && continue
            case "$declared" in *",$g_name,"*) continue ;; esac
            case ",$a_waived," in *",$g_name,"*) continue ;; esac
            hit=""
            for pat in $g_paths; do
                case "$pat" in
                    */'**') pfx="${pat%/'**'}/" ;;
                    *)      pfx="" ;;
                esac
                while IFS= read -r f; do
                    [ -n "$f" ] || continue
                    if [ -n "$pfx" ]; then
                        case "$f" in "$pfx"*) hit="$f"; break ;; esac
                    elif [ "$f" = "$pat" ]; then
                        hit="$f"; break
                    fi
                done <<< "$changed"
                [ -n "$hit" ] && break
            done
            [ -n "$hit" ] && warnings+=("$label bead $a_id: the charter mandates gate \"$g_name\" for a diff touching $hit, but check_set is \"$a_cs\" and no triage waiver records it — triage missed the row, or the gate was dropped after it ran (method: $g_method)")
        done <<< "$menu"
    done <<< "$anchors"
    [ "$undiffed" -eq 0 ] || notes+=("$label: $undiffed anchor(s) had no readable branch diff, so their charter-mandated gates were not checked (fetch origin in $rig_path)")
done <<< "$scopes"

if [ "${#errors[@]}" -ne 0 ]; then
    echo "gate integrity violated (I6/I7): ${#errors[@]} finding(s)"
    detail "${errors[@]}"
    detail ${warnings[@]+"${warnings[@]}"}
    detail ${notes[@]+"${notes[@]}"}
    exit 2
fi
if [ "${#warnings[@]}" -ne 0 ]; then
    echo "gate integrity holds with gaps (I6/I7)"
    detail "${warnings[@]}"
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
echo "OK: every open gating anchor declares its check_set and every gate marker is well-formed"
detail ${notes[@]+"${notes[@]}"}
exit 0
