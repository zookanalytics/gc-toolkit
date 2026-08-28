#!/usr/bin/env bash
# doctor/check-recycle-capable — cycle-recycle can actually fire. The Stop hook
# in overlays/cycle-recycle exits 0 on every uncertainty (docs/cycle-recycle.md:
# "uncertain -> skip ... There is no fallback heuristic"), which is right per
# turn and leaves a permanently dead mechanism indistinguishable from an idle
# one. This check asserts the preconditions the hook needs before it can measure
# or act: the city name resolves the way the hook resolves it, the supervisor
# agent endpoint carries a numeric input_tokens for every awake patrol agent,
# and the refinery's git-op defer guard is not latched. Capability, not
# installation — check-config-bound already asserts the overlay_dir exists.
# The guard arm reads the rig's canonical checkout only; the hook also reads its
# own CWD, which is the refinery's worktree and is not addressable from here.
# Read-only. Exit 0=OK 1=Warning 2=Error. stdout: message, then "  - detail"
# lines. Probes bounded; an UNREADABLE probe warns (1), never passes.

set -u

dir="${GC_PACK_DIR:-.}"
city="${GC_CITY_PATH:-${GC_CITY:-}}"
API_URL="${GC_API_URL:-http://127.0.0.1:8372}"
BOUND="${GC_DOCTOR_CHECK_TIMEOUT:-30}"
LATCH_HOURS="${GC_DOCTOR_RECYCLE_LATCH_HOURS:-24}"
THRESHOLD=200000   # the hook's own absolute recycle threshold

errors=(); warnings=(); notes=()
run_bounded() { if command -v timeout >/dev/null 2>&1; then timeout "$BOUND" "$@" </dev/null; else "$@" </dev/null; fi; }
detail() { local v; for v in "$@"; do printf '  - %s\n' "$v"; done; }
mtime_of() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || printf ''; }
commas() { local out="" v; for v in "$@"; do out="${out:+$out, }$v"; done; printf '%s' "$out"; }
duration() { # <seconds> -> "3d 4h" / "4h 12m" / "7m"
    local s="$1"
    if   [ "$s" -ge 86400 ]; then printf '%dd %dh' "$((s / 86400))" "$(((s % 86400) / 3600))"
    elif [ "$s" -ge 3600 ];  then printf '%dh %dm' "$((s / 3600))"  "$(((s % 3600) / 60))"
    else                          printf '%dm' "$((s / 60))"; fi
}

[ -f "$dir/overlays/cycle-recycle/.claude/hooks/cycle-recycle.sh" ] \
    || { echo "OK: this pack ships no cycle-recycle hook — no recycle capability to assert"; exit 0; }
command -v gc >/dev/null 2>&1 \
    || { echo "OK: gc is not on PATH — recycle capability is a runtime property, not verifiable here"; exit 0; }
[ -n "$city" ] \
    || { echo "OK: no city in scope (GC_CITY_PATH/GC_CITY unset) — recycle capability not verifiable here"; exit 0; }

# --- Arm 1a: the city name resolves ---------------------------------------
# The hook maps its city PATH to a NAME through `gc cities` and builds the API
# URL from it; an unmatched path is its first silent exit.
cities_json=$(run_bounded gc cities --json 2>/dev/null)
if ! printf '%s' "$cities_json" | jq -e '(.cities | type) == "array"' >/dev/null 2>&1; then
    echo "recycle capability undetermined — cannot read the city roster"
    detail "\`gc cities --json\` returned no .cities array (timeout ${BOUND}s, or schema drift). The hook resolves its city name from the same read, so neither arm below ran."
    exit 1
fi
city_name=$(printf '%s' "$cities_json" | jq -r --arg p "$city" \
    'first(.cities[]? | select(.path == $p) | .name // empty) // empty' 2>/dev/null)
if [ -z "$city_name" ]; then
    echo "cycle-recycle cannot fire: its city name does not resolve"
    detail "no entry in \`gc cities --json\` has .path == \"$city\", so the hook's own lookup yields empty and it exits before measuring — for every patrol agent, every turn."
    exit 2
fi

# --- Arm 1b: the endpoint carries a numeric input_tokens -------------------
# Same URL shape the hook uses, so the probe fails exactly when the hook does.
status_json=$(run_bounded gc --city "$city" status --json 2>/dev/null)
if ! printf '%s' "$status_json" | jq -e '(.agents | type) == "array"' >/dev/null 2>&1; then
    echo "recycle capability undetermined — cannot read the agent roster"
    detail "\`gc --city $city status --json\` returned no .agents array (timeout ${BOUND}s, or schema drift) — the patrol agents to probe are unknown, so neither arm below ran."
    exit 1
fi

patrol_jq='
  ["witness","deacon","refinery"] as $patrol
  | .agents[]?
  | ((.qualified_name // .name // "") | tostring) as $qn
  | select($qn != "")
  | ($qn | split("/") | last | split(".") | last) as $role
  | select($patrol | index($role))'
rows=$(printf '%s' "$status_json" | jq -r "$patrol_jq"'
  | [$qn, $role, ((.running // false) | tostring), ((.suspended // false) | tostring)] | @tsv' 2>/dev/null)
expected=$(printf '%s' "$status_json" | jq -r "[ $patrol_jq | 1 ] | length" 2>/dev/null)

absent=(); nonnumeric=(); unreachable=(); unreadable=(); measured=0; seen=0; refinery_rigs=""
total_agents=$(printf '%s' "$status_json" | jq -r '(.agents | length)' 2>/dev/null)
while IFS=$'\t' read -r qn role running suspended; do
    [ -n "$qn" ] || continue
    seen=$((seen + 1))
    [ "$role" = refinery ] && [ "$running" = true ] && [ "$suspended" != true ] \
        && case "$qn" in */*) refinery_rigs="$refinery_rigs ${qn%%/*}" ;; esac
    if [ "$suspended" = true ]; then
        notes+=("$qn: suspended — not expected to recycle"); continue
    fi
    if [ "$running" != true ]; then
        notes+=("$qn: not running — no context to measure"); continue
    fi
    body=$(run_bounded curl -sf --max-time 5 "$API_URL/v0/city/$city_name/agent/$qn" 2>/dev/null)
    if [ -z "$body" ]; then unreachable+=("$qn"); continue; fi
    # A body jq cannot read leaves this empty, which is a different claim from
    # an object that carries no such key — only the latter indicts the schema.
    tokens=$(printf '%s' "$body" | jq -r \
        'if (has("input_tokens") | not) or (.input_tokens == null) then "<none>" else (.input_tokens | tostring) end' 2>/dev/null)
    case "$tokens" in
        '')       unreadable+=("$qn") ;;
        '<none>') absent+=("$qn") ;;
        *[!0-9]*) nonnumeric+=("$qn (input_tokens=$tokens)") ;;
        *)        measured=$((measured + 1)) ;;
    esac
done <<< "$rows"

# A silently short enumeration would report the same OK as a healthy city — the
# failure this whole check exists to refuse. `expected` is the same filter as
# `rows`, so it catches a partial loss but agrees with a total one.
if [ "$seen" -eq 0 ] && [ "${total_agents:-0}" -gt 0 ] 2>/dev/null; then
    warnings+=("none of the $total_agents agent(s) in \`gc --city $city status --json\` carries a witness, deacon or refinery role, which is what the hook self-gates to — either this city runs no patrol agent or the roster's naming moved and nothing was measured")
fi
if [ "${expected:-0}" -ne "$seen" ] 2>/dev/null; then
    warnings+=("the patrol roster enumerated $seen of $expected agent(s) — the measurement arm is incomplete, so a dead endpoint would not be visible for the rest")
fi

if [ "${#absent[@]}" -ne 0 ]; then
    errors+=("$API_URL/v0/city/$city_name/agent/<agent> answers with no input_tokens field for $(commas "${absent[@]}") — the hook reads \`.input_tokens // 0\`, compares 0 against its $THRESHOLD threshold and exits, so no recycle can fire for these agents however full their context is")
fi
if [ "${#nonnumeric[@]}" -ne 0 ]; then
    errors+=("$API_URL/v0/city/$city_name/agent/<agent> answers with a non-numeric input_tokens for $(commas "${nonnumeric[@]}") — the hook's numeric guard rejects it and exits, so no recycle can fire for these agents")
fi
if [ "${#unreachable[@]}" -ne 0 ]; then
    warnings+=("$API_URL/v0/city/$city_name/agent/<agent> returned nothing for $(commas "${unreachable[@]}") — the supervisor API is the hook's only measurement, and whether it carries input_tokens is undetermined for these agents")
fi
if [ "${#unreadable[@]}" -ne 0 ]; then
    warnings+=("$API_URL/v0/city/$city_name/agent/<agent> answered with a body jq could not read as a JSON object for $(commas "${unreadable[@]}") — the hook reads it with jq too and would measure nothing, but whether the field is gone or the answer is a transient gateway page is undetermined")
fi

# --- Arm 2: the refinery's git-op defer guard is not latched ---------------
# The guard is correct per turn and cannot tell a rebase in flight from a
# tracked file nobody has committed. Age it: the guard has been continuously
# true at least since the OLDEST currently-dirty path was last written.
rig_paths=""
rigs_json=$(run_bounded gc --city "$city" rig list --json 2>/dev/null)
if printf '%s' "$rigs_json" | jq -e '(.rigs | type) == "array"' >/dev/null 2>&1; then
    rig_paths=$(printf '%s' "$rigs_json" | jq -r \
        '.rigs[]? | select((.suspended // false) | not) | [(.name // "-"), (.path // "-")] | @tsv' 2>/dev/null)
elif [ -n "$refinery_rigs" ]; then
    warnings+=("could not read the rig roster (\`gc --city $city rig list --json\`) — the defer-guard arm did not run, so a latched guard would not be visible")
    refinery_rigs=""
fi

LATCH_SECS=$((LATCH_HOURS * 3600))
now=$(date +%s)
for rig in $(printf '%s' "$refinery_rigs" | tr ' ' '\n' | sort -u); do
    [ -n "$rig" ] || continue
    root=$(printf '%s\n' "$rig_paths" | awk -F'\t' -v r="$rig" '$1 == r { print $2; exit }')
    if [ -z "$root" ] || [ "$root" = "-" ]; then
        notes+=("rig $rig: no checkout path in the rig roster (suspended, or unlisted) — its refinery's defer guard was not read")
        continue
    fi
    if ! git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        warnings+=("rig $rig: $root is not a git worktree, yet the refinery's defer guard reads it — the guard's state there is undetermined")
        continue
    fi
    gd=$(git -C "$root" rev-parse --git-dir 2>/dev/null)
    case "$gd" in /*) ;; *) gd="$root/$gd" ;; esac

    oldest=""; latched_by=""; held=0
    for marker in rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD; do
        [ -e "$gd/$marker" ] || continue
        held=$((held + 1))
        ts=$(mtime_of "$gd/$marker"); [ -n "$ts" ] || continue
        if [ -z "$oldest" ] || [ "$ts" -lt "$oldest" ]; then oldest="$ts"; latched_by="$marker (git-op in progress)"; fi
    done
    # -z, so a path with a space or a quote survives; a rename emits its origin
    # as a second field, which the inner read consumes.
    while IFS= read -r -d '' entry; do
        [ "${#entry}" -gt 3 ] || continue
        path="${entry:3}"
        case "${entry:0:2}" in R* | C*) IFS= read -r -d '' _origin || true ;; esac
        held=$((held + 1))
        ts=$(mtime_of "$root/$path"); [ -n "$ts" ] || continue
        if [ -z "$oldest" ] || [ "$ts" -lt "$oldest" ]; then oldest="$ts"; latched_by="$path"; fi
    done < <(git -C "$root" status --porcelain=v1 -z --untracked-files=no 2>/dev/null)

    [ "$held" -eq 0 ] && continue   # guard clear — the healthy case is silent
    if [ -z "$oldest" ]; then
        warnings+=("rig $rig: the refinery's defer guard is true in $root but nothing datable backs it — a git op in flight cannot be told from a latch")
        continue
    fi
    age=$((now - oldest)); [ "$age" -lt 0 ] && age=0
    if [ "$age" -ge "$LATCH_SECS" ]; then
        errors+=("rig $rig: the refinery's git-op defer guard has been true for $(duration "$age") in $root, latched by \"$latched_by\" — past the ${LATCH_HOURS}h bound that is not a git op in flight, and every recycle for that refinery defers forever. Commit or revert it.")
    else
        notes+=("rig $rig: defer guard true in $root (\"$latched_by\", $(duration "$age")) — inside the ${LATCH_HOURS}h bound, a git op in flight")
    fi
done

if [ "${#errors[@]}" -ne 0 ]; then
    echo "cycle-recycle cannot fire: ${#errors[@]} finding(s)"
    detail "${errors[@]}"
    detail ${warnings[@]+"${warnings[@]}"}
    detail ${notes[@]+"${notes[@]}"}
    exit 2
fi
if [ "${#warnings[@]}" -ne 0 ]; then
    echo "recycle capability partially determined"
    detail "${warnings[@]}"
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
echo "OK: $measured patrol agent(s) report a numeric input_tokens and no refinery defer guard is latched"
detail ${notes[@]+"${notes[@]}"}
exit 0
