#!/usr/bin/env bash
# doctor/check-state-space — I2: the anchor state space is closed.
# Per bead store: every open bead's merge_result value is a state declared in
# lifecycle/lifecycle.toml (built-in enum when the declaration is absent or
# unparseable); a closed-only state (merged) on an OPEN bead is an error; and
# an open bead in a declared detached state is held by nobody and offered to no
# pool. The merge cadence drives those states, so its assignee must be empty and
# its gc.routed_to must be empty or the declared park_route sentinel that no
# pool claims; any other value is a second driver racing the cadence. Finally,
# no open bead carries a metadata key from the deleted healer-bookkeeping
# registry — those keys have no writer any more, so their presence means a
# retired repair pass is still writing state.
# Read-only. Exit 0=OK 1=Warning 2=Error. stdout: first line = message, then
# "  - detail" lines. Live probes are bounded; an UNREADABLE probe warns (1),
# never passes.

set -u

dir="${GC_PACK_DIR:-.}"
BOUND="${GC_DOCTOR_CHECK_TIMEOUT:-30}"

# The declared enum. "unanchored" (merge_result absent) has no stored value on
# the ordinary path, but a literal write of it is a declared state, not a drift.
BUILTIN_STATES="unanchored pre_open_gate pull_request merged abandoned retargeted blocked refused_false_completion held"
BUILTIN_CLOSED="merged"
BUILTIN_DETACHED="pre_open_gate pull_request"
BUILTIN_PARK_ROUTE="human"
lifecycle="$dir/lifecycle/lifecycle.toml"
toml_scalar() { # <file> <key> — the quoted string of the first `<key> = "..."`
    awk -v k="$2" '$0 ~ ("^[[:space:]]*" k "[[:space:]]*=[[:space:]]*\"") {
        sub(/^[^"]*"/, ""); sub(/".*$/, ""); print; exit }' "$1" 2>/dev/null
}
toml_array() { # <file> <key> — quoted strings of the first `<key> = [...]`
    awk -v k="$2" 'ok { print } $0 ~ ("^[[:space:]]*" k "[[:space:]]*=[[:space:]]*\\[") { ok = 1; print }' "$1" 2>/dev/null \
        | awk '{ print } /\]/ { exit }' | grep -o '"[^"]*"' | tr -d '"'
}
states=""; closed_states=""; detached_states=""; park_route=""
if [ -f "$lifecycle" ]; then
    states=$(toml_array "$lifecycle" "states")
    closed_states=$(toml_array "$lifecycle" "closed_states")
    detached_states=$(toml_array "$lifecycle" "detached_states")
    park_route=$(toml_scalar "$lifecycle" "park_route")
fi
[ -n "$states" ] || states=$(printf '%s\n' $BUILTIN_STATES)
[ -n "$closed_states" ] || closed_states=$(printf '%s\n' $BUILTIN_CLOSED)
[ -n "$detached_states" ] || detached_states=$(printf '%s\n' $BUILTIN_DETACHED)
[ -n "$park_route" ] || park_route="$BUILTIN_PARK_ROUTE"
states_json=$(printf '%s\n' "$states" | jq -R . | jq -cs 'map(select(. != ""))')
closed_json=$(printf '%s\n' "$closed_states" | jq -R . | jq -cs 'map(select(. != ""))')
detached_json=$(printf '%s\n' "$detached_states" | jq -R . | jq -cs 'map(select(. != ""))')
enum_str=$(printf '%s' "$states_json" | jq -r 'join(", ")')

# Keys deleted from the metadata registry along with their healer writers.
HEALER_RE='^(check_set_healed|merge_result_healed|reopened_not_landed|anchorless_flagged|close_failures|close_escalated|gate_verdict_condemned)$'

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
# US-joined so a rig with an empty name still yields its path field intact.
scopes=$(printf '%s' "$rigs_raw" | jq -r '.rigs[]? | select((.path // "") != "")
    | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path, ((.suspended // false) | tostring)]
    | join("\u001f")' 2>/dev/null)
if [ "$rigs_rc" -ne 0 ] || [ -z "$scopes" ]; then
    echo "cannot determine whether the state space holds (I2)"
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
    raw=$(run_bounded gc bd list --db "$rig_path/.beads" --status open --json --limit 0 2>/dev/null); rc=$?
    if [ "$rc" -ne 0 ] || [ -z "$raw" ]; then
        warnings+=("$label: could not list open beads in $rig_path/.beads (rc=$rc) — this store was NOT checked")
        continue
    fi
    rows=$(printf '%s' "$raw" | scrub | jq -r \
        --argjson states "$states_json" --argjson closed "$closed_json" \
        --argjson detached "$detached_json" --arg park "$park_route" --arg hre "$HEALER_RE" '
        def clean: tostring | gsub("[[:cntrl:]]"; " ");
        .[]? | . as $b | ($b.metadata // {}) as $m
        | (($b.id // "?") | clean) as $id
        | (($b.assignee // "") | clean) as $as
        | (($m["gc.routed_to"] // "") | clean) as $rt
        | ( (if ($m | has("merge_result")) then
               ((($m.merge_result // "") | tostring)) as $mr
               | (if $mr == "" then []
                  elif ($states | index($mr)) == null then [["badmr", $id, $mr, ""]]
                  elif ($closed | index($mr)) != null then [["openclosed", $id, $mr, ""]]
                  elif ($detached | index($mr)) != null then
                    ((if $rt == "" or $rt == $park then [] else [["detachedroute", $id, $mr, $rt]] end)
                     + (if $as == "" then [] else [["detachedassignee", $id, $mr, $as]] end))
                  else [] end)
             else [] end)
            + [ $m | keys[]
                | select(test($hre) or startswith("stranded_branch_") or startswith("stale_gate_"))
                | ["healer", $id, ., ""] ] )[]
        | join("\u001f")' 2>/dev/null)
    if [ $? -ne 0 ]; then
        warnings+=("$label: open-bead listing from $rig_path/.beads could not be parsed — this store was NOT checked")
        continue
    fi
    [ -n "$rows" ] || continue
    while IFS=$'\037' read -r kind id val extra; do
        [ -n "$kind" ] || continue
        case "$kind" in
            badmr)      errors+=("$label bead $id: merge_result=\"$val\" is not a declared state ($enum_str) — an unknown state has no handler and every reader defaults differently on it; surface it via escalate.sh, never invent a reading") ;;
            openclosed) errors+=("$label bead $id: OPEN with merge_result=$val — a closed-only state on an open bead means the close half of the transition was lost or a landed anchor was reopened") ;;
            detachedroute)    errors+=("$label bead $id: merge_result=$val carries gc.routed_to=\"$extra\" — $val is a detached state (lifecycle/lifecycle.toml detached_states), driven by the merge cadence and offered to no pool, so any route but the \"$park_route\" park is demand for work already in the merge queue; the claim it invites moves the anchor out of \`--status=open\`, where merge.sh and pr-facts.sh both stop seeing it") ;;
            detachedassignee) errors+=("$label bead $id: merge_result=$val carries assignee=\"$extra\" — $val is a detached state (lifecycle/lifecycle.toml detached_states) and rests unheld; a holder here is a second driver racing the cadence on one anchor") ;;
            healer)     errors+=("$label bead $id: carries deleted healer-bookkeeping key \"$val\" — lifecycle/lifecycle.toml removed it with its writer, so something retired is still writing state") ;;
        esac
    done <<< "$rows"
done <<< "$scopes"

if [ "${#errors[@]}" -ne 0 ]; then
    echo "state space violated (I2): ${#errors[@]} finding(s)"
    detail "${errors[@]}"
    detail ${warnings[@]+"${warnings[@]}"}
    detail ${notes[@]+"${notes[@]}"}
    exit 2
fi
if [ "${#warnings[@]}" -ne 0 ]; then
    echo "state space partially determined (I2)"
    detail "${warnings[@]}"
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
echo "OK: every open bead's merge_result is a declared state, every detached state rests unheld and offered to no pool, and no deleted healer key survives"
detail ${notes[@]+"${notes[@]}"}
exit 0
