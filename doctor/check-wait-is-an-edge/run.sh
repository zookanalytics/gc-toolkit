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
# Whether a held bead still waits is its own pending waits, as `gctk bead holds`
# answers them (docs/gctk-architecture.md, "The bead holds contract"): a wait of
# the store's blocked rule onto a bead in the same store that is neither closed
# nor pinned. One read per store answers every live bead that carries a marker
# or a wait edge.
#
# Three degrees, reported apart because their remedies differ: UNEDGED, where
# the bead carries no wait edge at all and one has to be filed; STALE, where
# every wait it names has landed, is pinned or lives in another store, so the
# marker has outlived its edge; and FOREIGN, a wait edge of any live bead,
# marked or not, onto a bead in another store, which `bd dep add` accepts and
# which holds nothing. They take one posture, which lifecycle.toml declares in
# `hold_severity`: a warning while the standing backlog of marker-only holds is
# converted, an error once it is. A waits-for edge, which the store cannot
# judge yet, is noted as unjudged.
# Read-only. Exit 0=OK 1=Warning 2=Error. stdout: first line = message, then
# "  - detail" lines. Live probes are bounded; an UNREADABLE probe warns (1),
# never passes.

set -u

dir="${GC_PACK_DIR:-.}"
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
# The terminal end of a wait — the bead others block ON. It can carry no
# `blocks` edge of its own by construction (the gated bead blocks on it; it
# blocks on nothing), so a marker it carries is exempt, not a finding. It is a
# gate: a human gate is filed blocking the bead that waits, and a park is a
# plain gate a bead's own edge points at. The rule is the bead's issue type.
# Same declared-or-standby role as the marker list.
BUILTIN_TERMINAL_WAIT_TYPE='gate'
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
marker_keys=""; settled_keys=""; severity=""; terminal_wait_type=""; declared=""
if [ -f "$lifecycle" ]; then
    marker_keys=$(toml_array "$lifecycle" "marker_keys")
    settled_keys=$(toml_array "$lifecycle" "settled_keys")
    terminal_wait_type=$(toml_scalar "$lifecycle" "terminal_wait_type")
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
    terminal_wait_type="$BUILTIN_TERMINAL_WAIT_TYPE"
fi
# The posture is the exception: it is one value with a safe default, and a
# declaration that omits it is asking for the default rather than for silence.
[ -n "$severity" ] || severity="$BUILTIN_SEVERITY"
MKEYS_JSON=$(printf '%s\n' "$marker_keys" | jq -R . | jq -cs 'map(select(. != ""))')
# {<marker>: <settled-key>}. A pair with either half missing is dropped rather
# than half-applied: half of this declaration is a marker answered by a key
# nothing writes, which reads every hold as settled.
SETTLED_JSON=$(printf '%s\n' "$settled_keys" | jq -R '
    select(index("=") != null)
    | (index("=")) as $i
    | {key: .[0:$i], value: .[$i+1:]}
    | select(.key != "" and .value != "")' | jq -cs 'from_entries')

stale=(); unedged=(); foreign=(); warnings=(); notes=()
# What holds a bead is the answer of `gctk bead holds`, from the binary the city
# builds.
# >>> gctk-bin
GCTK="${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"
# <<< gctk-bin
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
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

# ---------------------------------------------------------------------------
# One pass over a store's live listing. Emits, for each live bead carrying a
# hold marker:
#   <id> US <status> US <marker=value; ...> US <wait-target-ids,comma>
#
# The wait edges ride along from that one listing: `bd list --json` puts each
# bead's outgoing dependency rows on the bead itself, keyed `.type` with the
# target in `.depends_on_id`, while `bd show` keys the same edge
# `.dependency_type` with the target in `.id`. Both spellings are read, so
# neither shape can silently return no edges at all. Whether a wait is still
# pending is the bead read's to answer, not this listing's.
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
| $beads[]
| . as $b
| ($b.id | tostring) as $id
| ($b.status | txt) as $st
| ($b.metadata // {}) as $m
# The terminal end of a wait — the bead others block ON — can carry no `blocks`
# edge of its own, so a marker it holds is exempt rather than unedged. This is a
# whole-bead skip, not a settled marker: the settled-key answers ONE marker and
# the bead is judged on the rest, while a gate IS the thing waited on and has
# no forward edge to file at all. Declared like the markers: an empty $twtype
# (the declaration dropped it) disables this arm and every bead is scanned.
| select($twtype == "" or ($b.issue_type | txt) != $twtype)
| ( [ $m | to_entries[]
      | .key as $k | (.value | txt) as $v
      | select(($mkeys | index($k)) != null and ($v | length) > 0 and unsettled($m; $k))
      | $k + "=" + ($v | clip) ] | sort ) as $marks
| select(($marks | length) > 0)
| ( [ ($b.dependencies // [])[]
      | select(((.type // .dependency_type // "") | tostring) as $t
               | $t == "blocks" or $t == "conditional-blocks" or $t == "waits-for")
      | ((.depends_on_id // .id // "") | tostring)
      | select(. != "") ] | unique ) as $blk
| [ $id, $st, ($marks | join("; ")), ($blk | join(",")) ]
| join("\u001f")
'

# rig-map.sh prints the map when the listing reads and only its reason when it
# does not, so one capture holds whichever came back.
RIG_MAP="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/assets/scripts/rig-map.sh"
rigs_raw=$(run_bounded "$RIG_MAP" 2>&1); rigs_rc=$?
if [ "$rigs_rc" -ne 0 ] || [ -z "$rigs_raw" ]; then
    echo "cannot determine whether every hold is recorded as an edge (I1)"
    detail "\`gc rig list --json\` failed (rc=$rigs_rc) or returned nothing; there is no set of bead stores to scan."
    [ "$rigs_rc" -eq 0 ] || [ -z "$rigs_raw" ] || detail "$rigs_raw"
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
        --argjson mkeys "$MKEYS_JSON" \
        --argjson settled "$SETTLED_JSON" \
        --arg twtype "$terminal_wait_type" \
        "$WAIT_JQ" 2>/dev/null); rows_rc=$?
    if [ "$rows_rc" -ne 0 ]; then
        warnings+=("$label: could not read hold markers off the live listing — this store was NOT checked")
        continue
    fi

    # Each live bead's status, which the note and the verdicts below read. It and
    # the marked rows reach jq as files, since both grow with the store and an
    # argument past the kernel's cap fails the program. A pass below that does
    # not run leaves the store NOT checked, since a verdict nobody computed is
    # not a clean one.
    statuses=$(printf '%s' "$live_json" | jq -c '[.[] | {key: ((.id // "") | tostring), value: ((.status // "") | tostring)}] | from_entries' 2>/dev/null) || statuses=""
    if [ -z "$statuses" ]; then
        warnings+=("$label: could not read the live beads' statuses off the listing — this store was NOT checked")
        continue
    fi

    # What holds each live bead that carries a marker or a wait edge, in one
    # read of the store: a bead with neither has no wait to be pending and none
    # to point into another store. A read that answers none of them is the
    # store's read failing, so the store is NOT checked; a bead it could not
    # answer is left out, and warned.
    holds='{}'
    ids=$(printf '%s' "$live_json" | jq -r --rawfile rows <(printf '%s' "$rows") '
        ($rows | split("\n") | map(select(length > 0) | split("\u001f")[0])) as $marked
        | [ .[] | ((.id // "") | tostring) as $id | select($id != "")
            | select(($marked | index([$id])) != null
                     or any((.dependencies // [])[]?; ((.type // .dependency_type // "") | tostring) as $t
                            | $t == "blocks" or $t == "conditional-blocks" or $t == "waits-for"))
            | $id ] | join(" ")' 2>/dev/null) || {
        warnings+=("$label: could not list the beads to ask what holds them — this store was NOT checked")
        continue
    }
    if [ -n "$ids" ]; then
        holds=""
        # shellcheck disable=SC2086  # one id per word
        [ -x "$GCTK" ] && holds=$(run_bounded "$GCTK" bead holds --db "$rig_path/.beads" $ids 2>/dev/null | scrub \
            | jq -s -c 'map(select(type == "object" and (.id // "") != "") | {key: .id, value: .}) | from_entries' 2>/dev/null)
        if [ -z "$holds" ] || ! printf '%s' "$holds" | jq -e 'any(.[]; .error == null)' >/dev/null 2>&1; then
            warnings+=("$label: could not read what holds its live beads (gctk bead holds at $GCTK answered none) — this store was NOT checked")
            continue
        fi
        unread=$(printf '%s' "$holds" | jq -r '[.[] | select(.error != null) | .id] | join(", ")' 2>/dev/null)
        [ -z "$unread" ] || warnings+=("$label: could not read what holds $unread — those beads were NOT checked")
    fi

    # Each marked bead's verdict, in one pass over the answers: live while a wait
    # of its own is pending, unedged with no wait edge at all, stale otherwise,
    # naming why each wait holds nothing. A bead the read could not answer is
    # left to the warning above.
    verdicts=""
    if [ -n "$rows" ]; then
        verdicts=$(printf '%s' "$holds" | jq -r --rawfile rows <(printf '%s' "$rows") --slurpfile statuses <(printf '%s' "$statuses") '
            ($statuses[0]) as $st | . as $h
            | $rows | split("\n")[] | select(length > 0) | split("\u001f") as [$id, $bst, $marks, $ids]
            | ($h[$id] // null) as $r
            | if $r == null or $r.error != null then empty
              elif (($r.pending // []) | length) > 0 then empty
              elif ($ids // "") == "" then ["unedged", $id, $bst, $marks, ""]
              else ([$r.foreign[]?.id]) as $far
                | ["stale", $id, $bst, $marks,
                   (($ids | split(",") | map(select(. != "")) | map(. as $w
                      | $w + " is " + (if ($far | index([$w])) != null then "in another store, where an edge holds nothing"
                                       elif ($st[$w] // "") == "pinned" then "pinned"
                                       elif ($st[$w] // "") != "" then ($st[$w] + ", which the store does not count")
                                       else "closed" end))) | join(", "))]
              end
            | join("\u001f")' 2>/dev/null) || {
            warnings+=("$label: could not judge the waits of its held beads — this store was NOT checked")
            continue
        }
    fi
    checked=$((checked + 1))

    # A pending wait the live listing did not carry is a live bead this scan
    # misses, so the listing's own reach is short of the store: the next hold on
    # such a bead is a finding this check would never raise.
    missed=$(printf '%s' "$holds" | jq -r --slurpfile statuses <(printf '%s' "$statuses") '
        ($statuses[0]) as $st
        | [ .[] | select(.error == null) | (.pending // [])[] | select(.ancestor == null)
          | select(.id as $i | $st | has($i) | not) | .id + " (" + (.status // "?") + ")" ] | unique | join(", ")' 2>/dev/null)
    if [ -n "$missed" ]; then
        notes+=("$label: the live listing did not carry $missed, which this store reports as not closed — the scanned status set or the category flags are short of what the store holds")
    fi

    # Every wait edge into another store, on any live bead, and every wait the
    # store cannot judge yet.
    while IFS= read -r line; do
        [ -n "$line" ] && foreign+=("$label bead $line")
    done < <(printf '%s' "$holds" | jq -r '.[] | select(.error == null and ((.foreign // []) | length) > 0)
        | "\(.id): its wait edge onto " + ([.foreign[] | "\(.id) (\(.type))"] | join(", ")) + " points into another store, and holds nothing"' 2>/dev/null)
    while IFS= read -r line; do
        [ -n "$line" ] && notes+=("$label bead $line")
    done < <(printf '%s' "$holds" | jq -r '.[] | select(.error == null and .status == "unjudged")
        | "\(.id): waits on " + ([.waits[] | select(.type == "waits-for") | .id] | join(", ")) + " by a waits-for edge, which the store cannot judge yet (unjudged)"' 2>/dev/null)

    while IFS=$'\037' read -r kind id st marks why; do
        case "$kind" in
            unedged) unedged+=("$label bead $id ($st): held by $marks, and carries no wait edge") ;;
            stale) stale+=("$label bead $id ($st): held by $marks, and $why") ;;
        esac
    done < <(printf '%s\n' "$verdicts")
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
found=$(( ${#stale[@]} + ${#unedged[@]} + ${#foreign[@]} ))
if [ "$found" -ne 0 ]; then
    case "$severity" in
        error) rc=2; posture="" ;;
        warn)  rc=1; posture=" — reported as a warning while the conversion backlog stands (lifecycle/lifecycle.toml hold_severity)" ;;
        *)     rc=1; posture=" — reported as a warning"
               notes+=("hold_severity=\"$severity\" is not one of warn|error; the findings above are reported as warnings until the declaration names a posture this check knows") ;;
    esac
    echo "waits a live bead records that hold nothing (I1): $found finding(s) across $checked store(s)$posture"
    if [ "${#unedged[@]}" -ne 0 ]; then
        detail "${#unedged[@]} carry a hold marker and no wait edge at all. \`bd ready\` cannot answer whether any of them is still waiting, and no close releases one. For each: file what it waits on as a bead in the same store and block this one on it, or close it where the reason has expired."
        detail_capped "$DETAILS" "${unedged[@]}"
    fi
    if [ "${#stale[@]}" -ne 0 ]; then
        detail "${#stale[@]} carry a hold marker none of whose waits is pending. The graph reports these ready while the marker reports them held, so the hold rests on the string alone: give each its disposition, or record the live wait as an edge."
        detail_capped "$DETAILS" "${stale[@]}"
    fi
    if [ "${#foreign[@]}" -ne 0 ]; then
        detail "${#foreign[@]} carry a wait edge into another store. \`bd dep add\` accepts a foreign id, reports success, and the edge holds nothing, so the bead runs ahead of what it names: record the wait in the bead's own store, or remove the edge."
        detail_capped "$DETAILS" "${foreign[@]}"
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
echo "OK: every hold marker a live bead carries across $checked store(s) sits beside a pending wait, and no wait edge points into another store"
detail ${notes[@]+"${notes[@]}"}
exit 0
