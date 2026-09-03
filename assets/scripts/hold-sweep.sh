#!/usr/bin/env bash
# hold-sweep.sh — a hold names what would end it, and something evaluates that
# name. `triage.hold` hides a bead from the liveness sweep
# (liveness-sweep.sh classifies it `held-by-design`, and
# liveness-sweep-precheck.sh drops it from the survivor set), so a hold whose
# premise has died keeps the bead hidden with nobody watching:
#   hold <bead> --until <condition> --reason "<prose>"
# records the release condition as metadata beside the prose; `reconcile`
# (orders/hold-sweep.toml, cooldown, scope="rig") evaluates every live hold
# each pass and releases the ones whose condition has fired. `list` answers
# "what is held, and what would end it?"; `release` ends one by hand.
#
# RELEASING IS NOT CLOSING AND NOT DISPATCHING. It clears the marker, which
# returns the bead to the sweep's census. Whether the work should then be
# routed is a separate decision this script does not make.
#
# Per-bead best-effort (one bad hold never skips the rest; the next cooldown
# retries), but a failure to ENUMERATE exits non-zero. An unreadable board of
# holds must never read as an empty one: this pass exists to end a silence, and
# a zero-count summary it could not stand behind is that silence again.
set -u

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

PROG="hold-sweep"

# The marker itself, and the record kept beside it. `triage.hold` non-empty is
# the hold; an EMPTY value is a CLEARED hold, which is the shape every reader
# of this marker already uses, so release empties rather than unsets. _at/_by
# are the pack's existing hold stamps and survive a release as the record of
# when the bead was held.
K_HOLD="triage.hold"
K_AT="triage.hold_at"
K_BY="triage.hold_by"
K_CLEARED_BY="triage.hold_cleared_by"
K_CLEARED_AT="triage.hold_cleared_at"

# The release condition. lifecycle/lifecycle.toml `[holds]` is the declaration
# so the key is readable beside the markers it qualifies; the built-in below is
# the same value and stands in only when that file cannot be read.
BUILTIN_UNTIL_KEY="triage.hold_until"
K_UNTIL="$BUILTIN_UNTIL_KEY"

PACK_DIR="${GC_PACK_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
toml_scalar() { # <file> <key> — the quoted string of the first `<key> = "..."`
    awk -v k="$2" '$0 ~ ("^[[:space:]]*" k "[[:space:]]*=[[:space:]]*\"") {
        sub(/^[^"]*"/, ""); sub(/".*$/, ""); print; exit }' "$1" 2>/dev/null
}
if [ -f "$PACK_DIR/lifecycle/lifecycle.toml" ]; then
    declared_until="$(toml_scalar "$PACK_DIR/lifecycle/lifecycle.toml" release_condition_key)"
    [ -n "$declared_until" ] && K_UNTIL="$declared_until"
fi

# The store, pinned: `gc bd` resolves its ledger from the invoking rig and
# ignores BEADS_DIR, so an unpinned read in the rig-scoped order env answers
# about whatever rig gc resolves rather than the one the pass is for.
# `--db` overrides it.
BD_DB="${GC_RIG_ROOT:+$GC_RIG_ROOT/.beads}"
DRY_RUN=0

TMPFILES=()
cleanup() { [ "${#TMPFILES[@]}" -gt 0 ] && rm -f "${TMPFILES[@]}"; return 0; }
trap cleanup EXIT
mktemp_tracked() { local f; f="$(mktemp)" || return 1; TMPFILES+=("$f"); printf '%s' "$f"; }

bd_() {
    if [ -n "$BD_DB" ]; then gc bd --db "$BD_DB" "$@"; else gc bd "$@"; fi
}

now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }
now_epoch() { date -u +%s 2>/dev/null || printf '0'; }
actor() { printf '%s' "${GC_AGENT:-${BEADS_ACTOR:-${USER:-unknown}}}"; }

# ISO-8601 to epoch seconds, GNU then BSD date. The caller treats a failure as
# unreadable — an untimeable stamp is not evidence a condition fired.
epoch_of() {
    local ts="$1" out base
    out=$(date -u -d "$ts" +%s 2>/dev/null) && [ -n "$out" ] && { printf '%s' "$out"; return 0; }
    base="${ts%Z}"; base="${base%%.*}"
    out=$(date -u -j -f '%Y-%m-%dT%H:%M:%S' "$base" +%s 2>/dev/null) && [ -n "$out" ] && { printf '%s' "$out"; return 0; }
    return 1
}

usage() {
    cat <<'EOF'
Usage:
  hold-sweep.sh hold <bead> --until <condition> [--reason <text>] [--db <path>]
  hold-sweep.sh release <bead> [--reason <text>] [--db <path>]
  hold-sweep.sh list [--json] [--db <path>]
  hold-sweep.sh reconcile [--dry-run] [--db <path>]

Verbs:
  hold       Hide <bead> from the liveness sweep until <condition> fires.
             --until is REQUIRED: a hold with no checkable condition and no
             review-by date is one nothing can ever end.
  release    Clear a hold by hand. Does not close and does not dispatch.
  list       Every live hold in this store, its condition, and its verdict.
  reconcile  One pass: release every hold whose condition has fired, and name
             every hold that carries none. Driven by orders/hold-sweep.toml
             (cooldown, scope="rig").

Conditions (--until):
  merged-within:<N>h    fires once a merge landed in THIS rig within the last
                        N hours ("re-open when anything has merged lately")
  bead-closed:<id>[,<id>...]
                        fires once EVERY named bead has closed ("sequenced
                        behind that call")
  date:<YYYY-MM-DD>     fires on that date, UTC. The review-by date a hold no
                        condition can express must carry, so it cannot be
                        silent forever.

A condition that cannot be evaluated — malformed, or naming a bead this store
cannot read — never releases. It is reported every pass instead.
EOF
}

# --- conditions --------------------------------------------------------------
# Syntax only. Used by `hold` to refuse a condition no pass could evaluate,
# and by the pass to tell malformed from merely unfired.
condition_wellformed() { # condition -> rc
    local c="$1" n ids id
    case "$c" in
        merged-within:*h)
            n="${c#merged-within:}"; n="${n%h}"
            case "$n" in ''|*[!0-9]*) return 1 ;; esac
            [ "$n" -gt 0 ] 2>/dev/null || return 1
            ;;
        bead-closed:*)
            ids="${c#bead-closed:}"
            [ -n "$ids" ] || return 1
            case "$ids" in *,,*|,*|*,) return 1 ;; esac
            for id in $(printf '%s' "$ids" | tr ',' ' '); do
                case "$id" in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac
            done
            ;;
        date:????-??-??)
            epoch_of "${c#date:}T00:00:00Z" >/dev/null || return 1
            ;;
        *) return 1 ;;
    esac
    return 0
}

# The newest merge in this store, as epoch seconds. Computed at most once per
# pass and cached, because every merged-within hold asks the same question.
# A merged anchor is `merge_result=merged` with the close that recorded it, so
# `closed_at` IS the merge time — merge-push closes the anchor on a verified
# merge and nothing else writes that pair.
MERGE_EPOCH_CACHE=""
newest_merge_epoch() { # -> epoch on stdout, rc 1 if the probe could not be read
    if [ -n "$MERGE_EPOCH_CACHE" ]; then
        [ "$MERGE_EPOCH_CACHE" = "none" ] && return 1
        printf '%s' "$MERGE_EPOCH_CACHE"; return 0
    fi
    local raw newest
    raw="$(bd_ list --has-metadata-key merge_result --all --json --limit 0 2>/dev/null)" || { MERGE_EPOCH_CACHE=none; return 1; }
    [ -n "$raw" ] || { MERGE_EPOCH_CACHE=none; return 1; }
    newest="$(printf '%s' "$raw" | scrub | jq -r '
        if type != "array" then empty
        else [ .[]
               | select((.metadata.merge_result // "") == "merged")
               | (.closed_at // "") | select(. != "") ] | max // ""
        end' 2>/dev/null)" || { MERGE_EPOCH_CACHE=none; return 1; }
    [ -n "$newest" ] || { MERGE_EPOCH_CACHE=none; return 1; }
    local e; e="$(epoch_of "$newest")" || { MERGE_EPOCH_CACHE=none; return 1; }
    MERGE_EPOCH_CACHE="$e"
    printf '%s' "$e"
}

# `bd show --json` answers an array on a hit and an {"error":...} object on a
# miss, both at rc=0 — discriminate on type, not exit status.
show_bead() { # id -> single bead object on stdout, or nothing (rc 1)
    local id="$1" raw
    raw="$(bd_ show "$id" --json 2>/dev/null)" || return 1
    printf '%s' "$raw" | scrub | jq -c '
        if type == "array" then (.[0] // empty)
        elif type == "object" then (if has("error") then empty else . end)
        else empty end' 2>/dev/null
}

meta_of() { # bead-json key -> value or empty
    printf '%s' "$1" | jq -r --arg k "$2" '(.metadata[$k] // "") | tostring' 2>/dev/null
}

# The one evaluator. Prints "<verdict>\t<why>", where verdict is one of:
#   fired          the condition is true now — release
#   waiting        the condition is well-formed and not yet true
#   unconditioned  no condition recorded; nothing can ever end this hold
#   unreadable     a condition that cannot be evaluated — never releases
evaluate() { # condition -> "<verdict>\t<why>"
    local c="$1"
    if [ -z "$c" ]; then
        printf 'unconditioned\tno %s recorded — nothing evaluates this hold\n' "$K_UNTIL"; return 0
    fi
    if ! condition_wellformed "$c"; then
        printf 'unreadable\tcondition "%s" is not one this pass can evaluate\n' "$c"; return 0
    fi
    case "$c" in
        merged-within:*h)
            local n secs merged now age
            n="${c#merged-within:}"; n="${n%h}"; secs=$((n * 3600))
            merged="$(newest_merge_epoch)" || {
                printf 'unreadable\tthe merge probe could not be read — not releasing on an unreadable probe\n'; return 0; }
            now="$(now_epoch)"
            [ "$now" -gt 0 ] || { printf 'unreadable\tdate(1) produced no epoch\n'; return 0; }
            age=$((now - merged))
            if [ "$age" -le "$secs" ]; then
                printf 'fired\ta merge landed in this rig %dh ago, within the %dh window\n' "$((age / 3600))" "$n"
            else
                printf 'waiting\tthe newest merge in this rig is %dh old, outside the %dh window\n' "$((age / 3600))" "$n"
            fi
            ;;
        bead-closed:*)
            local ids id json status open_ids="" missing=""
            # Split on the comma without touching IFS: this runs inside the
            # pass's own loop, and a stray IFS here would resplit its rows.
            ids="$(printf '%s' "${c#bead-closed:}" | tr ',' ' ')"
            for id in $ids; do
                json="$(show_bead "$id")" || json=""
                if [ -z "$json" ]; then missing="$missing $id"; continue; fi
                status="$(printf '%s' "$json" | jq -r '.status // ""')"
                [ "$status" = "closed" ] || open_ids="$open_ids $id"
            done
            if [ -n "$missing" ]; then
                printf 'unreadable\tnamed bead(s)%s do not resolve in this store — not releasing on a bead this pass cannot see\n' "$missing"
            elif [ -n "$open_ids" ]; then
                printf 'waiting\tstill open:%s\n' "$open_ids"
            else
                printf 'fired\tevery named bead has closed: %s\n' "${c#bead-closed:}"
            fi
            ;;
        date:*)
            local d due now
            d="${c#date:}"
            due="$(epoch_of "${d}T00:00:00Z")" || { printf 'unreadable\treview-by date "%s" could not be read\n' "$d"; return 0; }
            now="$(now_epoch)"
            [ "$now" -gt 0 ] || { printf 'unreadable\tdate(1) produced no epoch\n'; return 0; }
            if [ "$now" -ge "$due" ]; then
                printf 'fired\tthe review-by date %s has arrived\n' "$d"
            else
                printf 'waiting\tthe review-by date is %s, %dd away\n' "$d" "$(((due - now) / 86400))"
            fi
            ;;
    esac
}

# --- hold --------------------------------------------------------------------
cmd_hold() {
    local bead="" until_c="" reason=""
    bead="${1:-}"; shift || true
    case "$bead" in ""|-*) echo "$PROG: hold requires a bead id" >&2; return 2 ;; esac
    while [ $# -gt 0 ]; do
        case "$1" in
            --until)  shift; until_c="${1:-}" ;;
            --reason) shift; reason="${1:-}" ;;
            --db)     shift; BD_DB="${1:-}" ;;
            *) echo "$PROG: hold: unknown flag '$1'" >&2; return 2 ;;
        esac
        shift || true
    done

    if [ -z "$until_c" ]; then
        echo "$PROG: hold requires --until <condition>. A hold with no condition is one nothing can ever end; if no condition expresses it, give it a review-by date: --until date:YYYY-MM-DD" >&2
        return 2
    fi
    if ! condition_wellformed "$until_c"; then
        echo "$PROG: hold: '$until_c' is not a condition this pass can evaluate — writing it would hide the bead behind a name nothing reads" >&2
        usage >&2
        return 2
    fi

    local json status
    json="$(show_bead "$bead")" || json=""
    [ -n "$json" ] || { echo "$PROG: hold: $bead does not resolve in this store" >&2; return 1; }
    status="$(printf '%s' "$json" | jq -r '.status // ""')"
    if [ "$status" = "closed" ]; then
        echo "$PROG: hold: $bead is closed — a closed bead is not in the sweep's census, so there is nothing to hide" >&2
        return 1
    fi

    # A bead already held is re-held, not refused: the condition is what a
    # re-hold usually means to change, and refusing would leave the stale one
    # standing. Say which one was replaced.
    local prior; prior="$(meta_of "$json" "$K_UNTIL")"
    local text="${reason:-held by $(actor)}"
    local note
    note="$PROG: held by $(actor) at $(now_utc) — until=$until_c. Reason: $text. The hold-sweep reconcile pass releases this bead when that condition fires; releasing restores it to the liveness census and dispatches nothing."
    bd_ update "$bead" \
        --set-metadata "$K_HOLD=$text" \
        --set-metadata "$K_UNTIL=$until_c" \
        --set-metadata "$K_BY=$(actor)" \
        --set-metadata "$K_AT=$(now_utc)" \
        --append-notes "$note" >/dev/null 2>&1 || {
            echo "$PROG: hold: failed to write the hold onto $bead" >&2; return 1; }

    if [ -n "$prior" ] && [ "$prior" != "$until_c" ]; then
        echo "$PROG: held $bead until $until_c (replacing the earlier condition $prior)"
    else
        echo "$PROG: held $bead until $until_c"
    fi

    # Say now whether the hold is already spent, rather than letting the next
    # pass release something the caller believed it had just parked.
    local verdict; verdict="$(evaluate "$until_c" | cut -f1)"
    [ "$verdict" = "fired" ] && echo "$PROG: note: that condition is ALREADY true — the next reconcile pass will release $bead" >&2
    return 0
}

# --- release -----------------------------------------------------------------
release_bead() { # id why -> rc
    local id="$1" why="$2"
    bd_ update "$id" \
        --set-metadata "$K_HOLD=" \
        --set-metadata "$K_CLEARED_BY=$(actor)" \
        --set-metadata "$K_CLEARED_AT=$(now_utc)" \
        --append-notes "$PROG: hold released at $(now_utc) by $(actor) — $why. The bead is back in the liveness census; nothing was closed and nothing was dispatched." >/dev/null 2>&1
}

cmd_release() {
    local bead="" reason=""
    bead="${1:-}"; shift || true
    case "$bead" in ""|-*) echo "$PROG: release requires a bead id" >&2; return 2 ;; esac
    while [ $# -gt 0 ]; do
        case "$1" in
            --reason) shift; reason="${1:-}" ;;
            --db)     shift; BD_DB="${1:-}" ;;
            *) echo "$PROG: release: unknown flag '$1'" >&2; return 2 ;;
        esac
        shift || true
    done

    local json held
    json="$(show_bead "$bead")" || json=""
    [ -n "$json" ] || { echo "$PROG: release: $bead does not resolve in this store" >&2; return 1; }
    held="$(meta_of "$json" "$K_HOLD")"
    [ -n "$held" ] || { echo "$PROG: release: $bead carries no hold" >&2; return 1; }

    release_bead "$bead" "${reason:-released by hand}" || {
        echo "$PROG: release: failed to clear the hold on $bead" >&2; return 1; }
    echo "$PROG: released $bead"
}

# --- enumeration -------------------------------------------------------------
# Unreadable is not empty: the read is checked and any failure returns 1.
# EVERY NON-CLOSED STATUS is live. `closed` is the only value that ends a hold:
# a bead that has been claimed, parked or blocked still carries one, and its
# hold hides it from the census just the same. Asked as `--all` + a filter
# rather than as bd's default status set, so the set this pass sweeps cannot
# drift with that default. An EMPTY marker is a CLEARED hold, not a hold.
# THE CONDITION GOES LAST. `read` splits on IFS, and TAB is IFS whitespace, so
# a run of tabs collapses to one delimiter and an EMPTY middle field shifts
# every column after it. The condition is the one field that is legitimately
# empty — that is what an unconditioned hold IS — so it goes last, where an
# empty value is a stripped trailing delimiter and `read` leaves the variable
# empty instead of filling it with the next column.
held_rows() { # writes "<id>\t<hold-text>\t<until>" to $1
    local out="$1" all
    all="$(bd_ list --has-metadata-key "$K_HOLD" --all --json --limit 0 2>/dev/null)" || return 1
    [ -n "$all" ] || return 1
    printf '%s' "$all" | scrub | jq -e 'type == "array"' >/dev/null 2>&1 || return 1

    printf '%s' "$all" | scrub | jq -r --arg h "$K_HOLD" --arg u "$K_UNTIL" '
        .[]
        | select((.status // "") != "closed")
        | select(((.metadata[$h] // "") | tostring) != "")
        | [ .id, ((.metadata[$h] // "") | tostring | gsub("[\n\t]"; " ")), ((.metadata[$u] // "") | tostring) ]
        | @tsv' > "$out" 2>/dev/null || return 1
    return 0
}

cmd_list() {
    local as_json=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --json) as_json=1 ;;
            --db)   shift; BD_DB="${1:-}" ;;
            *) echo "$PROG: list: unknown flag '$1'" >&2; return 2 ;;
        esac
        shift || true
    done

    if [ "$as_json" = 1 ]; then
        local all
        all="$(bd_ list --has-metadata-key "$K_HOLD" --all --json --limit 0 2>/dev/null)" || {
            echo "$PROG: list: could not enumerate holds" >&2; return 1; }
        printf '%s' "$all" | scrub | jq --arg h "$K_HOLD" --arg u "$K_UNTIL" '
            [ .[] | select((.status // "") != "closed")
                  | select(((.metadata[$h] // "") | tostring) != "")
                  | {id, status, hold: (.metadata[$h] | tostring),
                     until: ((.metadata[$u] // "") | tostring)} ]' 2>/dev/null
        return 0
    fi

    local rows; rows="$(mktemp_tracked)" || { echo "$PROG: list: mktemp failed" >&2; return 1; }
    held_rows "$rows" || { echo "$PROG: list: could not enumerate holds" >&2; return 1; }

    local n=0 id text until_c verdict why v
    while IFS=$'\t' read -r id text until_c; do
        [ -n "${id:-}" ] || continue
        n=$((n + 1))
        v="$(evaluate "$until_c")"
        verdict="$(printf '%s' "$v" | cut -f1)"
        why="$(printf '%s' "$v" | cut -f2)"
        printf '%s [%s] until=%s\n    %s\n    hold: %s\n' \
            "$id" "$(printf '%s' "$verdict" | tr '[:lower:]' '[:upper:]')" "${until_c:-<none>}" "$why" "$text"
    done < "$rows"
    [ "$n" -gt 0 ] || echo "$PROG: no live holds in this store"
    return 0
}

# --- reconcile ---------------------------------------------------------------
cmd_reconcile() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run) DRY_RUN=1 ;;
            --db)      shift; BD_DB="${1:-}" ;;
            *) echo "$PROG: reconcile: unknown flag '$1'" >&2; return 2 ;;
        esac
        shift || true
    done

    local rows; rows="$(mktemp_tracked)" || { echo "$PROG: reconcile: mktemp failed" >&2; return 1; }
    held_rows "$rows" || {
        echo "$PROG: reconcile: could not enumerate holds — NOT treating this as an empty board" >&2
        return 1; }

    local expected processed=0 released=0 waiting=0 unconditioned=0 unreadable=0 failed=0
    expected="$(wc -l < "$rows" | tr -d ' ')"

    local id text until_c v verdict why
    while IFS=$'\t' read -r id text until_c; do
        [ -n "${id:-}" ] || continue
        processed=$((processed + 1))
        v="$(evaluate "$until_c")"
        verdict="$(printf '%s' "$v" | cut -f1)"
        why="$(printf '%s' "$v" | cut -f2)"

        case "$verdict" in
            fired)
                if [ "$DRY_RUN" = 1 ]; then
                    echo "$PROG: DRY-RUN would release $id ($until_c: $why)"
                elif release_bead "$id" "the recorded condition $until_c fired — $why"; then
                    echo "$PROG: released $id ($until_c: $why)"
                else
                    echo "$PROG: WARN could not release $id — leaving the hold, retrying next pass" >&2
                    failed=$((failed + 1)); continue
                fi
                released=$((released + 1))
                ;;
            waiting)
                waiting=$((waiting + 1))
                ;;
            unconditioned)
                # Never released here: an unconditioned hold may be a
                # disposition somebody meant (the silence IS the answer), and
                # guessing would overwrite it. Naming it every pass is what
                # keeps it from being silent, which is the whole complaint.
                echo "$PROG: UNCONDITIONED $id carries a hold with no $K_UNTIL — nothing can ever end it. Give it a condition or a review-by date: hold-sweep.sh hold $id --until date:YYYY-MM-DD --reason '<why>'" >&2
                unconditioned=$((unconditioned + 1))
                ;;
            unreadable)
                echo "$PROG: UNREADABLE $id until='$until_c' — $why" >&2
                unreadable=$((unreadable + 1))
                ;;
        esac
    done < "$rows"

    # A partial pass must not print a summary that reads like success.
    if [ "$processed" != "$expected" ]; then
        echo "$PROG: reconcile: enumerated $expected hold(s) but processed $processed — aborting rather than reporting a partial pass as complete" >&2
        return 1
    fi
    echo "$PROG: $released released, $waiting waiting, $unconditioned unconditioned, $unreadable unreadable, $failed failed (of $expected held)"
    [ "$failed" = 0 ]
}

# --- main --------------------------------------------------------------------
verb="${1:-}"; shift || true
case "$verb" in
    hold)      cmd_hold "$@" ;;
    release)   cmd_release "$@" ;;
    list)      cmd_list "$@" ;;
    reconcile) cmd_reconcile "$@" ;;
    -h|--help|help|"") usage; [ -n "$verb" ] && exit 0 || exit 2 ;;
    *) echo "$PROG: unknown verb '$verb'" >&2; usage >&2; exit 2 ;;
esac
