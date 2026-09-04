#!/usr/bin/env bash
# doctor/check-wait-is-an-edge — I1: a hold is a graph edge, not a marker.
# Per bead store: a LIVE bead carrying one of the hold markers declared in
# lifecycle/lifecycle.toml `[holds]` must also carry a `blocks` edge naming a
# bead that is still live in the SAME store. A marker is a string, and a string
# answers no query: `bd ready` cannot see it, so the bead either deadlocks in
# silence or runs ahead of what it is waiting for (docs/component-model.md,
# "I1 in full"). Only `blocks` counts, because it is the one edge type that
# holds a bead out of `bd ready`. Only the same store counts, because a
# cross-store `bd dep add` returns success and holds nothing.
#
# The markers are DECLARED, not parsed out of prose. What a bead states about
# itself in prose is a conclusion, and a conclusion is prose by design
# (docs/lifecycle-composition.md §1): reading English for holds would treat
# prose as a hold carrier, which is the opposite of the rule this check
# asserts, and no verb list ever finishes, so every gap in one reads as clean.
#
# One marker can be answered by its own writer instead, where lifecycle.toml
# declares a settled-key for it in `settled_keys`: a bead carrying that key
# non-empty is one whose writer said, at the moment it stamped the marker, that
# nothing is waiting. That is the same refusal to read prose, from the other
# side — a sitting knows whether it settled its subject or parked it, and no
# reader can recover that afterwards from the sentence it left. The key is
# structural and the marker still stands beside it, so nothing here is a
# blanked hold.
#
# Two degrees, reported apart because their remedies differ: UNEDGED, where the
# bead carries no `blocks` edge at all and one has to be filed, and STALE,
# where every blocker it names has closed or lives in another store, so the
# marker has outlived its edge. Both are one defect and take one posture, which
# lifecycle.toml declares in `hold_severity`: a warning while the standing
# backlog of marker-only holds is converted, an error once it is.
# Read-only. Exit 0=OK 1=Warning 2=Error. stdout: first line = message, then
# "  - detail" lines. Live probes are bounded; an UNREADABLE probe warns (1),
# never passes.

set -u

dir="${GC_PACK_DIR:-.}"
# Blockers the live listing does not carry resolve through a batched
# `gc bd show`, split so a store with a large candidate set cannot build an
# argv past the exec limit.
CHUNK="${GC_DOCTOR_WAIT_CHUNK:-100}"
# How many findings are PRINTED, not how many are found: every count in the
# headline is taken before this cap, so no value here can make a store read as
# clean. 0 prints all, which is what draining the backlog wants.
DETAILS="${GC_DOCTOR_WAIT_DETAILS:-25}"

# EVERY NON-CLOSED STATUS. `closed` is the only value that ends a hold; a bead
# that has been claimed, parked or blocked still carries one, and its hold is
# as unanswerable as an open bead's. `hooked` is bd's "wip" category and
# `pinned` its "frozen" one. Not a parameter: an env knob here would let a
# caller narrow the invariant to a subset of beads and still read as a clean
# run. One comma-separated value, because repeating `--status` silently
# overwrites the previous one.
LIVE_STATUSES='open,in_progress,blocked,deferred,hooked,pinned'

# The hold markers. lifecycle/lifecycle.toml `[holds]` is the declaration, so a
# marker added there is asserted without a code change; the built-ins below are
# the same list and stand in only when that file cannot be read, which is
# noted rather than substituted in silence.
BUILTIN_MARKER_KEYS='triage.hold
blocked_reason
gc.takeaway'
# <marker>=<settled-key>: the marker holds only while the settled-key is absent
# or empty. Same list as the declaration, same standby role.
BUILTIN_SETTLED_KEYS='gc.takeaway=gc.takeaway_settled'
BUILTIN_MARKER_PREFIXES='dispatch_backstop.'
# No gate marker is a hold: a lane state is a state of one reviewer's lane, and
# each is one some actor moves on from. Empty disables the gate arm.
BUILTIN_GATE_PREFIX=''
BUILTIN_GATE_VERB=''
BUILTIN_ROUTE_KEY='gc.routed_to'
BUILTIN_PARK_ROUTE='human'
# The reporting posture, until lifecycle.toml says otherwise.
BUILTIN_SEVERITY='warn'

lifecycle="$dir/lifecycle/lifecycle.toml"
toml_scalar() { # <file> <key> — the quoted string of the first `<key> = "..."`
    awk -v k="$2" '$0 ~ ("^[[:space:]]*" k "[[:space:]]*=[[:space:]]*\"") {
        sub(/^[^"]*"/, ""); sub(/".*$/, ""); print; exit }' "$1" 2>/dev/null
}
toml_array() { # <file> <key> — quoted strings of the first `<key> = [...]`
    awk -v k="$2" 'ok { print } $0 ~ ("^[[:space:]]*" k "[[:space:]]*=[[:space:]]*\\[") { ok = 1; print }' "$1" 2>/dev/null \
        | awk '{ print } /\]/ { exit }' | grep -o '"[^"]*"' | tr -d '"'
}
marker_keys=""; marker_prefixes=""; gate_prefix=""; gate_verb=""; route_key=""; park_route=""
settled_keys=""; severity=""; declared=""
if [ -f "$lifecycle" ]; then
    marker_keys=$(toml_array "$lifecycle" "marker_keys")
    settled_keys=$(toml_array "$lifecycle" "settled_keys")
    marker_prefixes=$(toml_array "$lifecycle" "marker_prefixes")
    gate_prefix=$(toml_scalar "$lifecycle" "gate_marker_prefix")
    gate_verb=$(toml_scalar "$lifecycle" "gate_hold_verb")
    route_key=$(toml_scalar "$lifecycle" "route_key")
    park_route=$(toml_scalar "$lifecycle" "park_route")
    severity=$(toml_scalar "$lifecycle" "hold_severity")
    [ -n "$marker_keys" ] && declared=yes
fi
# All of the declaration or none of it. Filling a field the declaration left
# out from the built-ins would assert a marker the declaration deliberately
# dropped, and it would do so silently, which is the failure a declared list
# exists to remove. Each arm below tests its own field for emptiness, so an
# omitted one disables that arm rather than matching everything.
if [ -z "$declared" ]; then
    marker_keys="$BUILTIN_MARKER_KEYS"
    settled_keys="$BUILTIN_SETTLED_KEYS"
    marker_prefixes="$BUILTIN_MARKER_PREFIXES"
    gate_prefix="$BUILTIN_GATE_PREFIX"
    gate_verb="$BUILTIN_GATE_VERB"
    route_key="$BUILTIN_ROUTE_KEY"
    park_route="$BUILTIN_PARK_ROUTE"
fi
# The posture is the exception: it is one value with a safe default, and a
# declaration that omits it is asking for the default rather than for silence.
[ -n "$severity" ] || severity="$BUILTIN_SEVERITY"
MKEYS_JSON=$(printf '%s\n' "$marker_keys" | jq -R . | jq -cs 'map(select(. != ""))')
MPFX_JSON=$(printf '%s\n' "$marker_prefixes" | jq -R . | jq -cs 'map(select(. != ""))')
# {<marker>: <settled-key>}. A pair with either half missing is dropped rather
# than half-applied: half of this declaration is a marker answered by a key
# nothing writes, which reads every hold as settled.
SETTLED_JSON=$(printf '%s\n' "$settled_keys" | jq -R '
    select(index("=") != null)
    | (index("=")) as $i
    | {key: .[0:$i], value: .[$i+1:]}
    | select(.key != "" and .value != "")' | jq -cs 'from_entries')

# The separator the jq programs join their fields on and every reader splits
# on. Held once so no caller spells it differently.
US=$'\037'

stale=(); unedged=(); warnings=(); notes=()
# >>> doctor-budget
# One deadline for the whole check, anchored at process start. `gc doctor
# --check-timeout` (default 60s) abandons an overrunning check and discards
# everything it had buffered, so a check that has not printed by then is never
# heard. A per-probe constant does not hold that line: the probes below run
# once per rig, so their ceilings sum. Each probe gets the time still left
# instead, capped at half the budget so one wedged store cannot eat the rest,
# and a probe that no longer fits is refused with 124 — `timeout`'s own expiry
# code, which every caller's "this store was NOT checked" arm already handles.
# GC_DOCTOR_CHECK_TIMEOUT overrides the default, in whole seconds. Nothing
# exports it: the runner passes GC_CITY_PATH and GC_PACK_DIR and no budget.
BUDGET_DEFAULT=60; BUDGET_RESERVE=5; BUDGET_MIN_PROBE=2
budget_now() { if [ -n "${EPOCHSECONDS:-}" ]; then printf %s "$EPOCHSECONDS"; else date +%s; fi; }
budget_init() {
    BUDGET_TOTAL="${GC_DOCTOR_CHECK_TIMEOUT:-$BUDGET_DEFAULT}"; BUDGET_TOTAL="${BUDGET_TOTAL%s}"
    case "$BUDGET_TOTAL" in ''|*[!0-9]*) BUDGET_TOTAL="$BUDGET_DEFAULT" ;; esac
    BUDGET_CAP=$(( BUDGET_TOTAL / 2 ))
    BUDGET_DEADLINE=$(( $(budget_now) - SECONDS + BUDGET_TOTAL - BUDGET_RESERVE ))
}
budget_slice() {
    local left=$(( BUDGET_DEADLINE - $(budget_now) ))
    [ "$left" -le "$BUDGET_CAP" ] || left="$BUDGET_CAP"
    [ "$left" -ge 0 ] || left=0
    printf %s "$left"
}
budget_spent() { [ "$(budget_slice)" -lt "$BUDGET_MIN_PROBE" ]; }
run_bounded() { local s; s=$(budget_slice); [ "$s" -ge "$BUDGET_MIN_PROBE" ] || return 124
    if command -v timeout >/dev/null 2>&1; then timeout "$s" "$@" </dev/null; else "$@" </dev/null; fi; }
# A probe fed from a pipe cannot borrow run_bounded's </dev/null.
run_piped() { local s; s=$(budget_slice); [ "$s" -ge "$BUDGET_MIN_PROBE" ] || return 124
    if command -v timeout >/dev/null 2>&1; then timeout "$s" "$@"; else "$@"; fi; }
budget_init
# <<< doctor-budget
detail() { local v; for v in "$@"; do printf '  - %s\n' "$v"; done; }
detail_capped() { # <cap> <item...> — at most <cap> items, then the rest as a count
    local cap="$1"; shift
    local total=$# printed=0 v
    [ "$total" -ne 0 ] || return 0
    if [ "$cap" -le 0 ] || [ "$total" -le "$cap" ]; then detail "$@"; return 0; fi
    for v in "$@"; do
        printed=$((printed + 1)); [ "$printed" -le "$cap" ] || break
        printf '  - %s\n' "$v"
    done
    printf '  - ...and %s more, not printed (GC_DOCTOR_WAIT_DETAILS=0 prints every one)\n' "$((total - cap))"
}
# Rows below are joined on 0x1F, which this scrub also clears, so no payload
# byte can pose as a field separator.
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

# ---------------------------------------------------------------------------
# One pass over a store's live listing. Emits, for each live bead carrying a
# hold marker that the same listing shows no live blocker for:
#   <id> US <status> US <marker=value; ...> US <blocks-target-ids,comma>
#
# The blocking edges ride along from that one listing, which is what holds the
# check to a single query per store: `bd list --json` puts each bead's outgoing
# dependency rows on the bead itself, keyed `.type` with the target in
# `.depends_on_id`, while `bd show` keys the same edge `.dependency_type` with
# the target in `.id`. Both spellings are read, so neither shape can silently
# return no edges at all.
#
# A blocker still in the listing is a live bead in this store and answers the
# hold. Every other blocker goes to the resolve pass, because absent from a
# listing means closed, or in another store, or in a category the listing
# hides, and those are three different answers.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2016  # $mkeys and friends are jq variables fed by --arg; shell expansion here would be the bug
WAIT_JQ='
def txt: (. // "") | tostring | gsub("[[:cntrl:]]"; " ");
def clip: if (length > 60) then (.[0:57] + "...") else . end;
# A declared marker whose settled-key reads non-empty on this bead was answered
# by the writer that stamped it. No pair declared for the key means no such
# answer exists, so the marker holds on its own.
def unsettled($m; $k): ($settled[$k] // "") as $sk
    | $sk == "" or (($m[$sk] | txt) | length) == 0;
[ .[]? | select(((.id // "") | tostring) != "") ] as $beads
| ( [ $beads[] | (.id | tostring) ] ) as $liveids
| $beads[]
| . as $b
| ($b.id | tostring) as $id
| ($b.status | txt) as $st
| ($b.metadata // {}) as $m
| ( [ $m | to_entries[]
      | .key as $k | (.value | txt) as $v
      | select(
            (($mkeys | index($k)) != null and ($v | length) > 0 and unsettled($m; $k))
         or ($mpfx | any(. as $p | $k | startswith($p)))
         or ($gatepfx != "" and $gateverb != ""
             and ($k | startswith($gatepfx)) and ($v | startswith($gateverb + "@")))
         or ($routekey != "" and $park != "" and $k == $routekey and $v == $park)
        )
      | $k + "=" + ($v | clip) ] | sort ) as $marks
| select(($marks | length) > 0)
| ( [ ($b.dependencies // [])[]
      | select(((.type // .dependency_type // "") | tostring) == "blocks")
      | ((.depends_on_id // .id // "") | tostring)
      | select(. != "") ] | unique ) as $blk
| select(($blk | any(. as $c | ($liveids | index($c)) != null)) | not)
| [ $id, $st, ($marks | join("; ")), ($blk | join(",")) ]
| join("\u001f")
'

rigs_raw=$(run_bounded gc rig list --json 2>/dev/null); rigs_rc=$?
if [ "$rigs_rc" -ne 0 ] || [ -z "$rigs_raw" ]; then
    echo "cannot determine whether every hold is recorded as an edge (I1)"
    detail "\`gc rig list --json\` failed (rc=$rigs_rc) or returned nothing; there is no set of bead stores to scan."
    exit 1
fi
# The HQ entry is the city's own store. It is addressed by --city and is not a
# --rig target: `gc bd --rig <hq-name>` answers "rig not found", so reading it
# as a rig would drop the store holding the city's own beads.
CITY=$(printf '%s' "$rigs_raw" | jq -r 'first(.rigs[]? | select(.hq == true) | .path // empty) // empty' 2>/dev/null)
# US-joined so a rig with an empty name still yields its path field intact.
scopes=$(printf '%s' "$rigs_raw" | jq -r '.rigs[]? | select((.path // "") != "")
    | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path,
       ((.hq // false) | tostring), ((.suspended // false) | tostring)]
    | join("\u001f")' 2>/dev/null)
if [ -z "$scopes" ]; then
    echo "cannot determine whether every hold is recorded as an edge (I1)"
    detail "\`gc rig list --json\` listed no rig paths; the listing shape changed or the output is corrupt."
    exit 1
fi
if [ -z "$declared" ]; then
    notes+=("hold markers taken from this check's built-in list: $lifecycle is absent or declares no [holds] marker_keys, so a marker added to the declaration is not being asserted")
fi

checked=0
while IFS=$'\037' read -r rig_name rig_path hq suspended; do
    [ -n "$rig_path" ] || continue
    label="${rig_name:-<city>}"
    if [ "$suspended" = "true" ]; then
        notes+=("$label: skipped (suspended — querying its store would auto-start an orphan Dolt server)")
        continue
    fi
    # Every read goes through `gc bd`, which supplies the server wiring. Raw
    # `bd` reads a differently-wired store or fails outright, and a check whose
    # whole output is a claim about the bead graph cannot rest on that. The
    # scope is stated rather than discovered, so the answer does not depend on
    # the directory the check happens to run in.
    SCOPE=(gc)
    [ -n "$CITY" ] && SCOPE+=(--city "$CITY")
    [ "$hq" = "true" ] || SCOPE+=(--rig "$rig_name")
    SCOPE+=(bd)

    # The --include-* flags are load-bearing: `bd list` hides gate,
    # infrastructure and template beads by default, and a hold on a hidden bead
    # holds exactly as hard as a hold on a visible one.
    live_raw=$(run_bounded "${SCOPE[@]}" list --status "$LIVE_STATUSES" \
        --include-gates --include-infra --include-templates \
        --json --limit 0 2>/dev/null); live_rc=$?
    if [ "$live_rc" -ne 0 ]; then
        warnings+=("$label: could not list live beads (rc=$live_rc) — this store was NOT checked")
        continue
    fi
    # An empty store answers `[]`; an empty STRING is not that answer.
    if [ -z "$live_raw" ]; then
        warnings+=("$label: the live listing returned no output — this store was NOT checked")
        continue
    fi
    live_json=$(printf '%s' "$live_raw" | scrub)
    if ! printf '%s' "$live_json" | jq -e 'type=="array"' >/dev/null 2>&1; then
        warnings+=("$label: the live listing is not a JSON array — this store was NOT checked")
        continue
    fi

    rows=$(printf '%s' "$live_json" | jq -r \
        --argjson mkeys "$MKEYS_JSON" --argjson mpfx "$MPFX_JSON" \
        --argjson settled "$SETTLED_JSON" \
        --arg gatepfx "$gate_prefix" --arg gateverb "$gate_verb" \
        --arg routekey "$route_key" --arg park "$park_route" \
        "$WAIT_JQ" 2>/dev/null); rows_rc=$?
    if [ "$rows_rc" -ne 0 ]; then
        warnings+=("$label: could not read hold markers off the live listing — this store was NOT checked")
        continue
    fi
    # A store with nothing held is judged: counting it is what makes "across N
    # store(s)" mean the answer covered N stores, not that N were opened.
    if [ -z "$rows" ]; then checked=$((checked + 1)); continue; fi

    # Blockers the live listing did not carry. Whitespace is stripped per LINE:
    # a `tr -d` after the split would delete the newlines the split just made
    # and collapse every id into a single token.
    unknown=$(printf '%s\n' "$rows" | awk -F'\037' 'NF>=4 && $4 != "" {print $4}' \
        | tr ',' '\n' | sed 's/[[:space:]]//g' | grep -v '^$' | sort -u)

    resolved='{}'; chunk=(); chunk_failed=""
    flush_chunk() {
        local out rc merged
        [ "${#chunk[@]}" -ne 0 ] || return 0
        out=$(run_bounded "${SCOPE[@]}" show "${chunk[@]}" --json 2>/dev/null); rc=$?
        out=$(printf '%s' "$out" | scrub)
        if [ -z "$out" ]; then chunk_failed="rc=$rc, no output"; return 1; fi
        # `bd show` EXITS non-zero when nothing in the batch resolved, printing
        # a well-formed no-matches error on stdout. That is a determinate
        # answer — no id in the batch names a bead here — and not a failed
        # read. Narrow on purpose: any other non-zero exit fails the store
        # closed.
        if [ "$rc" -ne 0 ] \
           && ! printf '%s' "$out" | jq -e 'type == "object"
                   and ((.error // "") | test("no issues? found"; "i"))' >/dev/null 2>&1; then
            chunk_failed="rc=$rc"; return 1
        fi
        # An ARRAY when at least one id resolves, a bare OBJECT when none does.
        # Projected to id -> status: the bodies are large and nothing below
        # reads anything else off them.
        merged=$(printf '%s' "$out" | jq -c --argjson a "$resolved" '
            if type == "array" then
                $a + ([ .[] | {key: (.id // "" | tostring),
                               value: (.status // "?" | tostring)} ]
                      | map(select(.key != "")) | from_entries)
            elif type == "object" then $a
            else null end' 2>/dev/null)
        if [ -z "$merged" ] || [ "$merged" = "null" ]; then chunk_failed="unparseable"; return 1; fi
        resolved="$merged"; chunk=(); return 0
    }
    while IFS= read -r cid; do
        [ -n "$cid" ] || continue
        chunk+=("$cid")
        if [ "${#chunk[@]}" -ge "$CHUNK" ]; then flush_chunk || break; fi
    done <<UNKNOWN_EOF
$unknown
UNKNOWN_EOF
    [ -n "$chunk_failed" ] || flush_chunk || true
    if [ -n "$chunk_failed" ]; then
        # A partial resolve reports a live blocker as a dead one, which is an
        # invented error, and buries the real ones behind it.
        warnings+=("$label: could not resolve the blockers named by held beads ($chunk_failed) — this store was NOT checked")
        continue
    fi
    checked=$((checked + 1))

    # Anything the resolve found alive was alive all along and the listing did
    # not carry it. The join below is right either way, but a short listing is
    # its own defect: the next hold on such a bead is a finding this check
    # would never raise.
    missed=$(printf '%s' "$resolved" | jq -r '[ to_entries[]
        | select(.value != "" and .value != "closed" and .value != "?")
        | .key + " (" + .value + ")" ] | join(", ")' 2>/dev/null)
    if [ -n "$missed" ]; then
        notes+=("$label: the live listing did not carry $missed, which this store reports as not closed — the scanned status set or the category flags are short of what the store holds")
    fi

    while IFS=$'\037' read -r id st marks blk; do
        [ -n "$id" ] || continue
        if [ -z "$blk" ]; then
            unedged+=("$label bead $id ($st): held by $marks, and carries no \`blocks\` edge")
            continue
        fi
        verdict=$(printf '%s' "$resolved" | jq -r --arg ids "$blk" '
            . as $r
            | ($ids | split(",") | map(select(. != ""))
               | map({id: ., st: ($r[.] // "")})) as $rows
            | if ($rows | any(.st != "" and .st != "closed")) then "live"
              else "stale\u001f" + ($rows | map(.id + " is "
                    + (if .st == "" then "in no store this scope can read"
                       else .st end)) | join(", "))
              end' 2>/dev/null)
        case "$verdict" in
            live*|'') continue ;;
        esac
        stale+=("$label bead $id ($st): held by $marks, and ${verdict#stale$US}")
    done <<ROW_EOF
$rows
ROW_EOF
done <<SCOPE_EOF
$scopes
SCOPE_EOF

if budget_spent; then
    warnings+=("this run reached its ${BUDGET_TOTAL}s doctor budget before every probe ran — what follows is partial, and an arm skipped for time is not an arm that passed")
fi
if [ "$checked" -eq 0 ]; then
    echo "cannot determine whether every hold is recorded as an edge (I1)"
    detail "No bead store could be examined."
    detail ${warnings[@]+"${warnings[@]}"}
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
# One posture for both degrees: they are the same defect, told apart by
# whether the bead ever carried an edge, and they take different remedies.
found=$(( ${#stale[@]} + ${#unedged[@]} ))
if [ "$found" -ne 0 ]; then
    case "$severity" in
        error) rc=2; posture="" ;;
        warn)  rc=1; posture=" — reported as a warning while the conversion backlog stands (lifecycle/lifecycle.toml hold_severity)" ;;
        *)     rc=1; posture=" — reported as a warning"
               notes+=("hold_severity=\"$severity\" is not one of warn|error; the findings above are reported as warnings until the declaration names a posture this check knows") ;;
    esac
    echo "holds a live bead states as a marker with no live \`blocks\` blocker (I1): $found finding(s) across $checked store(s)$posture"
    if [ "${#unedged[@]}" -ne 0 ]; then
        detail "${#unedged[@]} carry a hold marker and no \`blocks\` edge at all. \`bd ready\` cannot answer whether any of them is still waiting, and no close releases one. For each: file what it waits on as a bead in the same store and block this one on it, or close it where the reason has expired."
        detail_capped "$DETAILS" "${unedged[@]}"
    fi
    if [ "${#stale[@]}" -ne 0 ]; then
        detail "${#stale[@]} carry a hold marker whose every \`blocks\` blocker is gone. The graph reports these ready while the marker reports them held, so the hold rests on the string alone: give each its disposition, or record the live wait as an edge. A blocker in another store never held it — \`bd dep add\` accepts a foreign id, reports success, and leaves the bead in \`bd ready\`."
        detail_capped "$DETAILS" "${stale[@]}"
    fi
    detail ${warnings[@]+"${warnings[@]}"}
    detail ${notes[@]+"${notes[@]}"}
    exit "$rc"
fi
if [ "${#warnings[@]}" -ne 0 ]; then
    echo "every hold found across $checked store(s) is an edge, but some probes could not be read (I1)"
    detail "${warnings[@]}"
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
echo "OK: every hold marker a live bead carries across $checked store(s) sits beside a live \`blocks\` blocker"
detail ${notes[@]+"${notes[@]}"}
exit 0
