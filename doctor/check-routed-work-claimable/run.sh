#!/usr/bin/env bash
# doctor/check-routed-work-claimable — I3: routed and assigned work names a
# live target. Arm 1: an open, unassigned bead's gc.routed_to is byte-identical
# to a live agent identity or a sentinel — the pool offer is exact string
# equality (gascity hookClaimMatchesRoute), so a rig-unqualified or padded
# route is invisible to every pool. Arm 2: an open, ASSIGNED bead's assignee is
# held to the same test — assignment polls are the same exact-match contract.
# Arm 3: no scope="rig" order is registered with no rig bound (an unbound copy
# strands an unclaimable workflow root in the city store every fire).
# Values are compared AS STORED; normalization is a diagnostic, never a pass.
# Read-only. Exit 0=OK 1=Warning 2=Error. stdout: message, then "  - detail"
# lines. Probes bounded; an UNREADABLE probe warns (1), never passes.

set -u

dir="${GC_PACK_DIR:-.}"
BOUND="${GC_DOCTOR_CHECK_TIMEOUT:-30}"
# Deliberate "a person must decide" markers; exact match only.
SENTINELS='["human"]'

errors=(); warnings=(); notes=()
run_bounded() { if command -v timeout >/dev/null 2>&1; then timeout "$BOUND" "$@" </dev/null; else "$@" </dev/null; fi; }
detail() { local v; for v in "$@"; do printf '  - %s\n' "$v"; done; }
strip_ctl() { tr -d '\000-\011\013-\037'; }

agents_raw=$(run_bounded gc agent list --json 2>/dev/null); agents_rc=$?
identities=$(printf '%s' "$agents_raw" \
    | jq -c '[.agents[]? | (.qualified_name // "") | select(. != "")] | unique' 2>/dev/null)
if [ "$agents_rc" -ne 0 ] || [ -z "$identities" ] || [ "$identities" = "[]" ]; then
    echo "cannot determine whether routed/assigned work is claimable (I3)"
    detail "\`gc agent list --json\` failed (rc=$agents_rc) or listed no qualified identities; with no identity set every route looks dead."
    exit 1
fi
city_path=$(printf '%s' "$agents_raw" | jq -r '.city_path // ""' 2>/dev/null)

rigs_raw=$(run_bounded gc rig list --json 2>/dev/null); rigs_rc=$?
scopes=$(printf '%s' "$rigs_raw" | jq -r '.rigs[]? | select((.path // "") != "")
    | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path] | join("\u001f")' 2>/dev/null)
if [ "$rigs_rc" -ne 0 ] || [ -z "$scopes" ]; then
    echo "cannot determine whether routed/assigned work is claimable (I3)"
    detail "\`gc rig list --json\` failed (rc=$rigs_rc) or listed no rig paths; there is no set of bead stores to scan."
    exit 1
fi

while IFS=$'\037' read -r rig_name rig_path; do
    [ -n "$rig_path" ] || continue
    label="${rig_name:-<city>}"
    qualifier="$rig_name"
    [ -n "$city_path" ] && [ "$rig_path" = "$city_path" ] && qualifier=""
    raw=$(run_bounded bd list --db "$rig_path/.beads" --status open --json --limit 0 2>/dev/null); rc=$?
    if [ "$rc" -ne 0 ] || [ -z "$raw" ]; then
        warnings+=("$label: could not list open beads in $rig_path/.beads (rc=$rc) — this store was NOT checked")
        continue
    fi
    rows=$(printf '%s' "$raw" | strip_ctl | jq -r \
        --argjson ids "$identities" --argjson sent "$SENTINELS" --arg q "$qualifier" '
        def class($v):
          ($v | sub("^[[:space:][:cntrl:]]+"; "") | sub("[[:space:][:cntrl:]]+$"; "")) as $n
          | (if ($ids | index($v)) != null or ($sent | index($v)) != null then ["ok", ""]
             elif $n == "" then ["blank", ""]
             elif ($ids | index($n)) != null or ($sent | index($n)) != null then ["padded", $n]
             elif $q != "" and ($ids | index($q + "/" + $n)) != null then ["repair", $q + "/" + $n]
             elif ([$ids[] | select(endswith("/" + $n))] | length) > 0
               then ["ambiguous", ([$ids[] | select(endswith("/" + $n))] | join(", "))]
             else ["unknown", ""] end);
        .[]? | . as $b
        | ((($b.id // "?") | tostring) | gsub("[[:cntrl:]]"; " ")) as $id
        | ((($b.assignee // "") | tostring)) as $as
        | ((($b.metadata // {})["gc.routed_to"] // "") | tostring) as $rt
        | ( (if $as == "" and $rt != ""
             then (class($rt) as $c | [["gc.routed_to", $rt, $c[0], $c[1]]]) else [] end)
          + (if $as != ""
             then (class($as) as $c | [["assignee", $as, $c[0], $c[1]]]) else [] end) )[]
        | select(.[2] != "ok")
        | [.[0], .[2], $id, (.[1] | tojson), .[3]] | join("\u001f")' 2>/dev/null)
    if [ $? -ne 0 ]; then
        warnings+=("$label: open-bead listing from $rig_path/.beads could not be parsed — this store was NOT checked")
        continue
    fi
    [ -n "$rows" ] || continue
    while IFS=$'\037' read -r key class id valjson fix; do
        [ -n "$key" ] || continue
        case "$class" in
            blank)     errors+=("$label bead $id: $key=$valjson is nothing but whitespace/control characters — it names no agent and is not the empty value that means \"none\"; clear it or set a live identity") ;;
            padded)    errors+=("$label bead $id: $key=$valjson names no agent — stripped of padding it would be \"$fix\", but matching is exact byte equality (the value is quoted as stored so the padding is visible); set $key=$fix") ;;
            repair)    errors+=("$label bead $id: $key=$valjson names no agent — it is the rig-unqualified form of $fix, matched by nothing; set $key=$fix") ;;
            ambiguous) errors+=("$label bead $id: $key=$valjson names no agent — it is the rig-unqualified form of $fix, none of which reads this store") ;;
            *)         notes+=("$label bead $id: $key=$valjson matches no live identity and no rig-qualified form of one — unreachable, but indistinguishable from an unknown sentinel; reported, not judged") ;;
        esac
    done <<< "$rows"
done <<< "$scopes"

# Arm 3 — a live registration with no rig bound whose order declares scope="rig".
declares_rig_scope() { grep -qE '^[[:space:]]*scope[[:space:]]*=[[:space:]]*"rig"' "$1" 2>/dev/null; }
orders_raw=$(run_bounded gc order list --json 2>/dev/null); orders_rc=$?
if [ "$orders_rc" -ne 0 ] || ! printf '%s' "$orders_raw" | jq -e '(.orders | type) == "array"' >/dev/null 2>&1; then
    warnings+=("could not read the order registry (\`gc order list --json\`, rc=$orders_rc) — the rig-scoped-order arm did not run, so an unbound rig-scoped order would not be visible here")
else
    while IFS=$'\t' read -r oname osrc; do
        [ -n "$oname" ] || continue
        if [ -n "$osrc" ] && [ -f "$osrc" ]; then
            declares_rig_scope "$osrc" \
                && errors+=("order $oname: registered with NO rig bound, but $osrc declares scope=\"rig\" — every fire strands an unclaimable workflow root in the city store")
        elif [ -f "$dir/orders/$oname.toml" ] && declares_rig_scope "$dir/orders/$oname.toml"; then
            errors+=("order $oname: registered with NO rig bound, and this pack ships orders/$oname.toml with scope=\"rig\" — every fire strands an unclaimable workflow root in the city store")
        elif [ -n "$osrc" ]; then
            notes+=("order $oname: registered with no rig bound; source $osrc is unreadable, so its declared scope is unknown — reported, not judged")
        fi
    done <<< "$(printf '%s' "$orders_raw" | jq -r '.orders[]?
        | select(((.rig // "") | tostring) == "")
        | [(.name // ""), (.source // "")] | @tsv' 2>/dev/null)"
fi

if [ "${#errors[@]}" -ne 0 ]; then
    echo "unreachable routed/assigned work or unbound rig-scoped orders (I3): ${#errors[@]} finding(s)"
    detail "${errors[@]}"
    detail ${warnings[@]+"${warnings[@]}"}
    detail ${notes[@]+"${notes[@]}"}
    exit 2
fi
if [ "${#warnings[@]}" -ne 0 ]; then
    echo "routed/assigned-work reachability partially determined (I3)"
    detail "${warnings[@]}"
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
echo "OK: every route and assignee on open work names a live agent identity, and every rig-scoped order is bound"
detail ${notes[@]+"${notes[@]}"}
exit 0
