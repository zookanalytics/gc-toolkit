#!/usr/bin/env bash
# doctor/check-recycle-capable — cycle-recycle can actually fire. The Stop hook
# in overlays/cycle-recycle exits 0 on every uncertainty (docs/cycle-recycle.md:
# "uncertain -> skip ... There is no fallback heuristic"), which is right per
# turn and leaves a permanently dead mechanism indistinguishable from an idle
# one. This check asserts the preconditions the hook needs before it can measure
# or act: a Stop event is wired to the hook with its stdin intact, the hook's own
# measurement returns the context size a transcript carries, and the refinery's
# git-op defer guard is not latched. Capability, not installation —
# check-config-bound already asserts the overlay_dir exists.
# The measurement arms drive the SHIPPED script (`cycle-recycle.sh --measure`)
# rather than a copy of its logic, so a check that passes is evidence about the
# hook and not about the fixture. The guard arm reads the rig's canonical
# checkout only; the hook also reads its own CWD, which is the refinery's
# worktree and is not addressable from here.
# Read-only. Exit 0=OK 1=Warning 2=Error. stdout: message, then "  - detail"
# lines. Probes bounded; an UNREADABLE probe warns (1), never passes.

set -u

dir="${GC_PACK_DIR:-.}"
city="${GC_CITY_PATH:-${GC_CITY:-}}"
BOUND="${GC_DOCTOR_CHECK_TIMEOUT:-30}"
LATCH_HOURS="${GC_DOCTOR_RECYCLE_LATCH_HOURS:-24}"
THRESHOLD=200000   # the hook's own absolute recycle threshold

errors=(); warnings=(); notes=()
run_bounded() { if command -v timeout >/dev/null 2>&1; then timeout "$BOUND" "$@" </dev/null; else "$@" </dev/null; fi; }
# The measurement probe feeds the hook a payload, so it cannot borrow
# run_bounded's </dev/null.
run_piped() { if command -v timeout >/dev/null 2>&1; then timeout "$BOUND" "$@"; else "$@"; fi; }
detail() { local v; for v in "$@"; do printf '  - %s\n' "$v"; done; }
mtime_of() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || printf ''; }
duration() { # <seconds> -> "3d 4h" / "4h 12m" / "7m"
    local s="$1"
    if   [ "$s" -ge 86400 ]; then printf '%dd %dh' "$((s / 86400))" "$(((s % 86400) / 3600))"
    elif [ "$s" -ge 3600 ];  then printf '%dh %dm' "$((s / 3600))"  "$(((s % 3600) / 60))"
    else                          printf '%dm' "$((s / 60))"; fi
}

HOOK="$dir/overlays/cycle-recycle/.claude/hooks/cycle-recycle.sh"
SETTINGS="$dir/overlays/cycle-recycle/.claude/settings.json"
[ -f "$HOOK" ] \
    || { echo "OK: this pack ships no cycle-recycle hook — no recycle capability to assert"; exit 0; }
if ! command -v jq >/dev/null 2>&1; then
    echo "recycle capability undetermined — jq is not on PATH"
    detail "jq is the hook's only measurement tool and this check's only reader, so nothing below was asserted. The hook prepends \$HOME/go/bin and \$HOME/.local/bin to PATH, which this check does not, so a patrol agent may still resolve it."
    exit 1
fi

# --- Arm 1a: a Stop event reaches the hook, with its stdin intact ----------
# The hook measures from the transcript path on hook stdin. A Stop entry that
# does not invoke it, or invokes it with stdin redirected away, leaves the same
# permanently-silent no-op the whole check exists to refuse.
if [ ! -f "$SETTINGS" ]; then
    errors+=("the overlay ships $HOOK but no .claude/settings.json beside it — nothing wires the hook to the Stop event, so it never runs")
else
    stop_cmds=$(jq -r '[.hooks.Stop[]?.hooks[]?
        | select((.type // "command") == "command") | .command // empty] | .[]' "$SETTINGS" 2>/dev/null)
    if [ -z "$stop_cmds" ]; then
        errors+=("no Stop hook in $SETTINGS runs a command — the recycle has no trigger, so it fires for no agent on any turn")
    else
        wired=$(printf '%s\n' "$stop_cmds" | grep -c 'cycle-recycle\.sh' || true)
        if [ "${wired:-0}" -eq 0 ]; then
            errors+=("no Stop hook in $SETTINGS invokes cycle-recycle.sh — the overlay ships the script with nothing to run it")
        else
            starved=$(printf '%s\n' "$stop_cmds" | grep 'cycle-recycle\.sh' \
                | grep -E '<[[:space:]]*/dev/null|0<' || true)
            if [ -n "$starved" ]; then
                errors+=("the Stop wiring in $SETTINGS redirects the hook's stdin away (\"$starved\") — the transcript path it measures from arrives ON stdin, so it would read no context size and exit under the $THRESHOLD threshold every turn")
            fi
        fi
    fi
fi

# --- Arm 1b: the hook's own measurement reads a transcript -----------------
# Drives `cycle-recycle.sh --measure`, which prints what the hook would compare
# against its threshold and acts on nothing. GC_AGENT is cleared so a script
# predating --measure self-gates out and returns empty rather than recycling
# whatever agent runs the doctor.
probe=$(mktemp -d 2>/dev/null || printf '')
if [ -z "$probe" ]; then
    warnings+=("could not create a temp dir — the hook's measurement was not exercised, so a hook that measures nothing would not be visible")
else
    t="$probe/transcript.jsonl"
    # A first line the 2MiB tail cut mid-record, an all-zero usage entry, an
    # older real one, then the newest — which is the live context size.
    {
        printf '%s\n' '"model":"claude-opus-5"},"cut":true}'
        printf '%s\n' '{"type":"assistant","message":{"model":"claude-opus-5","usage":{"input_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}'
        printf '%s\n' '{"type":"assistant","message":{"model":"claude-opus-5","usage":{"input_tokens":7,"cache_read_input_tokens":11,"cache_creation_input_tokens":13}}}'
        printf '%s\n' '{"type":"assistant","message":{"model":"claude-opus-5","usage":{"input_tokens":100,"cache_read_input_tokens":250000,"cache_creation_input_tokens":1000}}}'
    } > "$t"
    want=251100
    got=$(printf '{"transcript_path":"%s"}' "$t" \
        | GC_AGENT='' run_piped sh "$HOOK" --measure 2>/dev/null)
    case "$got" in
        "$want") : ;;
        '')      errors+=("\`sh $HOOK --measure\` returned nothing for a transcript whose newest usage entry totals $want tokens — the hook can read no context size, so it compares nothing against its $THRESHOLD threshold and exits on every turn, for every patrol agent") ;;
        *)       errors+=("\`sh $HOOK --measure\` returned \"$got\" for a transcript whose newest usage entry totals $want tokens — its measurement disagrees with the transcript, so the threshold it enforces is not the one docs/cycle-recycle.md declares") ;;
    esac
    rm -rf "$probe"
fi

# --- Arm 2: the refinery's git-op defer guard is not latched ---------------
# The guard is correct per turn and cannot tell a rebase in flight from a
# tracked file nobody has committed. Age it: the guard has been continuously
# true at least since the OLDEST currently-dirty path was last written.
refinery_rigs=""
if ! command -v gc >/dev/null 2>&1; then
    notes+=("gc is not on PATH — the refinery defer-guard arm did not run")
elif [ -z "$city" ]; then
    notes+=("no city in scope (GC_CITY_PATH/GC_CITY unset) — the refinery defer-guard arm did not run")
else
    status_json=$(run_bounded gc --city "$city" status --json 2>/dev/null)
    if ! printf '%s' "$status_json" | jq -e '(.agents | type) == "array"' >/dev/null 2>&1; then
        warnings+=("\`gc --city $city status --json\` returned no .agents array (timeout ${BOUND}s, or schema drift) — the refineries to read are unknown, so a latched defer guard would not be visible")
    else
        refinery_jq='
          .agents[]?
          | ((.qualified_name // .name // "") | tostring) as $qn
          | select($qn != "")
          | select(($qn | split("/") | last | split(".") | last) == "refinery")'
        rows=$(printf '%s' "$status_json" | jq -r "$refinery_jq"'
          | [$qn, ((.running // false) | tostring), ((.suspended // false) | tostring)] | @tsv' 2>/dev/null)
        expected=$(printf '%s' "$status_json" | jq -r "[ $refinery_jq | 1 ] | length" 2>/dev/null)
        total_agents=$(printf '%s' "$status_json" | jq -r '(.agents | length)' 2>/dev/null)

        seen=0
        while IFS=$'\t' read -r qn running suspended; do
            [ -n "$qn" ] || continue
            seen=$((seen + 1))
            if [ "$suspended" = true ]; then
                notes+=("$qn: suspended — its defer guard is not read"); continue
            fi
            if [ "$running" != true ]; then
                notes+=("$qn: not running — its defer guard is not read"); continue
            fi
            case "$qn" in */*) refinery_rigs="$refinery_rigs ${qn%%/*}" ;; esac
        done <<< "$rows"

        # A silently short enumeration would report the same OK as a healthy
        # city — the failure this whole check exists to refuse. `expected` is the
        # same filter as `rows`, so it catches a partial loss but agrees with a
        # total one; only the roster's own size tells that from a city that runs
        # no refinery.
        if [ "$seen" -eq 0 ] && [ "${total_agents:-0}" -gt 0 ] 2>/dev/null; then
            warnings+=("none of the $total_agents agent(s) in \`gc --city $city status --json\` carries a refinery role, which is the only role whose defer guard is addressable from here — either this city runs no refinery or the roster's naming moved and no guard was read")
        fi
        if [ "${expected:-0}" -ne "$seen" ] 2>/dev/null; then
            warnings+=("the refinery roster enumerated $seen of $expected agent(s) — the defer-guard arm is incomplete, so a latched guard would not be visible for the rest")
        fi
    fi
fi

rig_paths=""
if [ -n "$refinery_rigs" ]; then
    rigs_json=$(run_bounded gc --city "$city" rig list --json 2>/dev/null)
    if printf '%s' "$rigs_json" | jq -e '(.rigs | type) == "array"' >/dev/null 2>&1; then
        rig_paths=$(printf '%s' "$rigs_json" | jq -r \
            '.rigs[]? | select((.suspended // false) | not) | [(.name // "-"), (.path // "-")] | @tsv' 2>/dev/null)
    else
        warnings+=("could not read the rig roster (\`gc --city $city rig list --json\`) — the defer-guard arm did not run, so a latched guard would not be visible")
        refinery_rigs=""
    fi
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
echo "OK: the Stop wiring reaches the hook with stdin intact, its measurement reads a transcript, and no refinery defer guard is latched"
detail ${notes[@]+"${notes[@]}"}
exit 0
