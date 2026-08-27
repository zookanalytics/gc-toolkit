#!/usr/bin/env bash
# doctor/check-claim-advancing — I11: a claimed step is being advanced by the
# session holding it.
#
# A pool session reports active and running whether it is working or parked at
# an idle prompt, so a claimed step can sit untouched with every other alarm
# green. The discriminator is the HOLDER's clock, not the bead's:
# check-step-terminal's stall arm is bead-clocked at 48h and never looks at who
# holds the step, so it cannot see a holder that stopped hours ago.
#
# Per store, every in_progress bead carrying gc.step_ref whose claim is older
# than the stall bound is joined to its holder, matched on session id,
# session_name or alias — the three identities a claim can be stamped with.
# Claims younger than the bound are never judged, which is also what keeps a
# pool recycle (the holder's incarnation changes under a live claim) from
# reading as a fault.
#
#   UNHELD    the bead carries no assignee at all         -> error
#   ORPHANED  the assignee names no session at all        -> error
#   DEAD      the holding session is not running          -> error
#   STALLED   the holder runs, but its last_active is     -> error
#             older than the bound as well
#
# UNHELD is reachable by neither path: nothing holds it, and `bd ready` skips
# it because its status is not open. The two checks that would otherwise see it
# both scan --status open, so an in_progress step with no assignee is invisible
# to all of them. Clearing an assignee and setting a status are separate writes,
# so this state exists briefly during a legitimate release; the bound covers it.
#
# last_active is derived from tmux pane changes and is hardened upstream
# against self-inflation (gc's own nudge keystrokes do not ratchet it), so a
# working agent refreshes it and a parked one does not. `gc session list` is
# served from a cache: when that cache is itself older than the bound the
# observation cannot outlive it, so STALLED degrades to a warning.
# Read-only. Exit 0=OK 1=Warning 2=Error. stdout: message, then "  - detail"
# lines. Probes bounded; an UNREADABLE probe warns (1), never passes.

set -u

BOUND="${GC_DOCTOR_CHECK_TIMEOUT:-30}"
STALL_MINUTES="${GC_DOCTOR_CLAIM_STALL_MINUTES:-30}"
case "$STALL_MINUTES" in *[!0-9]*|"") STALL_MINUTES=30 ;; esac
STALL=$((STALL_MINUTES * 60))

errors=(); warnings=(); notes=()
run_bounded() { if command -v timeout >/dev/null 2>&1; then timeout "$BOUND" "$@" </dev/null; else "$@" </dev/null; fi; }
detail() { local v; for v in "$@"; do printf '  - %s\n' "$v"; done; }
strip_ctl() { tr -d '\000-\011\013-\037'; }

sessions_raw=$(run_bounded gc session list --json 2>/dev/null); sessions_rc=$?
sessions=$(printf '%s' "$sessions_raw" | strip_ctl \
    | jq -c '[(.sessions // [])[]? | select(type == "object")]' 2>/dev/null)
if [ "$sessions_rc" -ne 0 ] || [ -z "$sessions" ]; then
    echo "cannot determine whether claimed steps are being advanced (I11)"
    detail "\`gc session list --json\` failed (rc=$sessions_rc) or could not be parsed; with no session set every claim would look orphaned."
    exit 1
fi
# An empty roster is a real state (a stopped city), but it cannot distinguish a
# held claim from an abandoned one, so it is reported rather than judged.
if [ "$sessions" = "[]" ]; then
    echo "cannot determine whether claimed steps are being advanced (I11)"
    detail "\`gc session list --json\` listed no sessions; every claim would classify as ORPHANED against an empty roster."
    exit 1
fi
cache_age=$(printf '%s' "$sessions_raw" | strip_ctl \
    | jq -r '(._cache_age_s // 0) | if type == "number" then floor else 0 end' 2>/dev/null)
case "${cache_age:-}" in *[!0-9]*|"") cache_age=0 ;; esac

rigs_raw=$(run_bounded gc rig list --json 2>/dev/null); rigs_rc=$?
scopes=$(printf '%s' "$rigs_raw" | jq -r '.rigs[]? | select((.path // "") != "")
    | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path, ((.suspended // false) | tostring)]
    | join("\u001f")' 2>/dev/null)
if [ "$rigs_rc" -ne 0 ] || [ -z "$scopes" ]; then
    echo "cannot determine whether claimed steps are being advanced (I11)"
    detail "\`gc rig list --json\` failed (rc=$rigs_rc) or listed no rig paths; there is no set of bead stores to scan."
    exit 1
fi

while IFS=$'\037' read -r rig_name rig_path suspended; do
    [ -n "$rig_path" ] || continue
    label="${rig_name:-<city>}"
    db="$rig_path/.beads"
    if [ "$suspended" = "true" ]; then
        notes+=("$label: skipped (suspended — querying its store would auto-start an orphan Dolt server)")
        continue
    fi
    claims_raw=$(run_bounded bd list --db "$db" --status in_progress --has-metadata-key gc.step_ref --json --limit 0 2>/dev/null); rc=$?
    if [ "$rc" -ne 0 ] || [ -z "$claims_raw" ]; then
        warnings+=("$label: could not list in-progress step beads in $db (rc=$rc) — this store was NOT checked")
        continue
    fi
    rows=$(printf '%s' "$claims_raw" | strip_ctl | jq -r \
        --argjson sess "$sessions" --argjson stall "$STALL" --argjson cache "$cache_age" '
        def ep: (try ((tostring) | sub("\\.[0-9]+"; "") | fromdateiso8601) catch null);
        def trim: (tostring) | sub("^[[:space:]]+"; "") | sub("[[:space:]]+$"; "");
        # One session is reachable under every identity a claim may carry.
        ( reduce ($sess[]? | select(type == "object")) as $s ({};
            reduce ((([$s.id, $s.session_name, $s.alias] | map(tostring)
                      | map(select(. != ""))))[]) as $k (.; .[$k] = $s)) ) as $S
        | [ .[]? | . as $b
            | (($b.metadata // {})["gc.step_ref"] // "" | trim) as $ref
            | select($ref != "")
            | (($b.assignee // "") | trim) as $as
            | ((($b.id // "?") | tostring) | gsub("[[:cntrl:]]"; " ")) as $bid
            | (($b.metadata // {})["gc.claimed_at"] // $b.updated_at // $b.created_at // "" | trim) as $ca
            | ($ca | ep) as $ce
            | select($ce != null and (now - $ce) > $stall)
            | ((now - $ce) / 60 | floor) as $held
            | ($S[$as] // null) as $s
            | (if $as == ""
               then {cls: "unheld", bid: $bid, as: "", held: $held, ex: ""}
               elif $s == null
               then {cls: "orphaned", bid: $bid, as: $as, held: $held, ex: ""}
               elif (($s.running // false) | tostring) != "true"
               then {cls: "dead", bid: $bid, as: $as, held: $held,
                     ex: (($s.state // "unknown") | tostring | gsub("[[:cntrl:]]"; " "))}
               else (($s.last_active // "") | trim) as $la
                    | ($la | ep) as $le
                    | (if $le == null
                       then {cls: "unknown", bid: $bid, as: $as, held: $held, ex: $la}
                       elif (now - $le) > $stall
                       then {cls: (if $cache > $stall then "stalled_cached" else "stalled" end),
                             bid: $bid, as: $as, held: $held,
                             ex: (((now - $le) / 60 | floor) | tostring)}
                       else empty end)
               end) ]
        | .[] | [.cls, .bid, .as, (.held | tostring), .ex] | join("\u001f")' 2>/dev/null)
    if [ $? -ne 0 ]; then
        warnings+=("$label: in-progress step listing from $db could not be parsed — this store was NOT checked")
        continue
    fi
    [ -n "$rows" ] || continue
    while IFS=$'\037' read -r cls bid as held ex; do
        [ -n "$cls" ] || continue
        case "$cls" in
            unheld)   errors+=("$label step $bid: in_progress for ${held}m with NO assignee. Nothing holds it, and \`bd ready\` cannot offer it either because its status is not open, so it is reachable by neither path; release it (status=open) so a pool can re-offer it.") ;;
            orphaned) errors+=("$label step $bid: claimed ${held}m ago by \"$as\", which names no session — id, session_name and alias were all tried. Nothing holds this step and nothing will advance it; release it (status=open, assignee=\"\") so a pool can re-offer it.") ;;
            dead)     errors+=("$label step $bid: claimed ${held}m ago by \"$as\", whose session is not running (state=$ex). The claim outlived its holder; release it so a pool can re-offer it.") ;;
            stalled)  errors+=("$label step $bid: claimed ${held}m ago by \"$as\", which is running but has produced no output for ${ex}m. A holder quiet past the ${STALL_MINUTES}m bound is parked, not working; nudge it to deliver the step it holds, or release the claim.") ;;
            stalled_cached) warnings+=("$label step $bid: claimed ${held}m ago by \"$as\", last output ${ex}m ago — but \`gc session list\` answered from a ${cache_age}s cache, itself older than the ${STALL_MINUTES}m bound, so the holder may have produced output since. Re-run once the cache is fresh.") ;;
            unknown)  notes+=("$label step $bid: claimed ${held}m ago by \"$as\", whose last_active is \"$ex\" and does not parse as a timestamp — liveness could not be judged for this holder; reported, not judged") ;;
        esac
    done <<< "$rows"
done <<< "$scopes"

if [ "${#errors[@]}" -ne 0 ]; then
    echo "claimed steps nothing is advancing (I11): ${#errors[@]} finding(s)"
    detail "${errors[@]}"
    detail ${warnings[@]+"${warnings[@]}"}
    detail ${notes[@]+"${notes[@]}"}
    exit 2
fi
if [ "${#warnings[@]}" -ne 0 ]; then
    echo "claim-advancing partially determined (I11)"
    detail "${warnings[@]}"
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
echo "OK: every step claimed longer than ${STALL_MINUTES}m is held by a running session that is still producing output"
detail ${notes[@]+"${notes[@]}"}
exit 0
