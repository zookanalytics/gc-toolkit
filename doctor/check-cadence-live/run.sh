#!/usr/bin/env bash
# doctor/check-cadence-live — I10: every order this pack ships is registered
# and firing. Per orders/*.toml (name, interval, scope; scope defaults to rig
# in the loader): a registration exists — per importing rig for scope="rig"
# (importing = the rig has ANY of this pack's orders registered), once
# otherwise — and the order fired within max(3×interval, 15m). `--limit 0` on
# the history read is LOAD-BEARING: any positive limit returns city-store rows
# only under a RIG column, so the answer looks city-wide and is not.
# Condition-triggered orders (no interval) get the registration arm alone.
# `gc order list` omits disabled orders, so a disabled clock presents as a
# missing registration — the right thing to say about it either way.
# Read-only. Exit 0=OK 1=Warning 2=Error. stdout: message, then "  - detail"
# lines. Probes bounded; an UNREADABLE probe warns (1), never passes.

set -u

dir="${GC_PACK_DIR:-.}"
BOUND="${GC_DOCTOR_CHECK_TIMEOUT:-30}"
FLOOR=900   # 15m — dispatchers fire cooldown orders slower than declared

errors=(); warnings=(); notes=()
run_bounded() { if command -v timeout >/dev/null 2>&1; then timeout "$BOUND" "$@" </dev/null; else "$@" </dev/null; fi; }
detail() { local v; for v in "$@"; do printf '  - %s\n' "$v"; done; }

[ -d "$dir/orders" ] || { echo "OK: no orders/ directory under GC_PACK_DIR ($dir) — this pack ships no cadence"; exit 0; }

# name<TAB>interval_secs<TAB>scope per shipped order ("" interval = none).
order_rows=""
for f in "$dir"/orders/*.toml; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .toml)
    read -r interval scope <<EOF
$(awk '
    /^\[order\]/ { inb = 1; next }
    /^\[/        { inb = 0 }
    inb && /^interval[[:space:]]*=/ { v = $0; sub(/^[^"]*"/, "", v); sub(/".*$/, "", v); iv = v }
    inb && /^scope[[:space:]]*=/    { v = $0; sub(/^[^"]*"/, "", v); sub(/".*$/, "", v); sc = v }
    END { print (iv == "" ? "-" : iv), (sc == "" ? "rig" : sc) }' "$f")
EOF
    # "-" = no interval (condition-triggered). A literal placeholder, never an
    # empty field: TAB is IFS whitespace, and an empty field would collapse.
    secs="-"
    case "$interval" in
        [0-9]*s) secs="${interval%s}" ;;
        [0-9]*m) secs=$(( ${interval%m} * 60 )) ;;
        [0-9]*h) secs=$(( ${interval%h} * 3600 )) ;;
        -) ;;
        *) warnings+=("$name: interval \"$interval\" is unparseable — the liveness arm cannot compute its window; registration checked only") ;;
    esac
    order_rows="$order_rows$name	$secs	$scope
"
done
[ -n "$order_rows" ] || { echo "OK: orders/ is empty — this pack ships no cadence"; exit 0; }

orders_json=$(run_bounded gc order list --json 2>/dev/null)
if ! printf '%s' "$orders_json" | jq -e '(.orders | type) == "array"' >/dev/null 2>&1; then
    echo "cadence liveness undetermined (I10) — cannot read the order registry"
    detail "\`gc order list --json\` returned no .orders array (timeout ${BOUND}s, or schema drift); neither arm ran, so a stopped cadence would not be visible."
    exit 1
fi

# Rigs importing this pack = rigs where ANY shipped order is registered.
pack_names=$(printf '%s' "$order_rows" | cut -f1)
pack_rigs=$(printf '%s' "$orders_json" | jq -r --arg names "$pack_names" '
    ($names | split("\n") | map(select(length > 0))) as $ours
    | [.orders[]? | select((.rig // "") != "") | select(.name as $n | $ours | index($n)) | .rig]
    | unique | .[]' 2>/dev/null)

suspended_rigs=""
rigs_json=$(run_bounded gc rig list --json 2>/dev/null)
if printf '%s' "$rigs_json" | jq -e '(.rigs | type) == "array"' >/dev/null 2>&1; then
    suspended_rigs=$(printf '%s' "$rigs_json" \
        | jq -r '.rigs[]? | select((.suspended // false) == true) | .name // empty' 2>/dev/null)
else
    warnings+=("could not read the rig roster (\`gc rig list --json\`) — a suspended rig cannot be told apart from a stalled one below")
fi
is_suspended() { [ -n "$suspended_rigs" ] && printf '%s\n' "$suspended_rigs" | grep -qxF "$1"; }

while IFS=$'\t' read -r name secs scope; do
    [ -n "$name" ] || continue
    # Rig-bound registrations by name; a city registration has rig == "" and
    # shows up only in the count.
    reg_rigs=$(printf '%s' "$orders_json" | jq -r --arg n "$name" '
        [.orders[]? | select(.name == $n) | (.rig // "") | select(. != "")] | unique | .[]' 2>/dev/null)
    reg_count=$(printf '%s' "$orders_json" | jq -r --arg n "$name" '
        [.orders[]? | select(.name == $n)] | length' 2>/dev/null)

    # Arm 1 — registration.
    if [ "$scope" = "rig" ]; then
        if [ -z "$pack_rigs" ]; then
            warnings+=("$name: no rig has any of this pack's orders registered — either the pack is not imported anywhere or the registry answered empty; liveness unverifiable")
            continue
        fi
        while read -r rig; do
            [ -n "$rig" ] || continue
            printf '%s\n' "$reg_rigs" | grep -qxF "$rig" \
                || errors+=("$name: rig $rig imports this pack but has NO registration for this order — its pass never runs there (a city.toml enabled=false override presents the same way)")
        done <<< "$pack_rigs"
    else
        [ "${reg_count:-0}" -gt 0 ] 2>/dev/null \
            || errors+=("$name: scope=\"$scope\" order has NO live registration anywhere — its pass never runs (a city.toml enabled=false override presents the same way)")
    fi

    # Arm 2 — fired within max(3×interval, 15m). Condition orders opt out.
    if [ "$secs" = "-" ] || [ -z "$secs" ]; then
        notes+=("$name: no interval declared (condition-triggered) — registration checked, cadence not time-bound")
        continue
    fi
    window=$(( secs * 3 )); [ "$window" -lt "$FLOOR" ] && window=$FLOOR
    hist=$(run_bounded gc order history "$name" --since "${window}s" --limit 0 --json 2>/dev/null)
    if ! printf '%s' "$hist" | jq -e '(.entries | type) == "array"' >/dev/null 2>&1; then
        warnings+=("$name: could not read run history (\`gc order history $name --since ${window}s --limit 0 --json\`) — the liveness arm did not run for this order")
        continue
    fi
    fresh=$(printf '%s' "$hist" | jq -r '[.entries[]? | (.rig // "")] | unique | .[]' 2>/dev/null)
    if [ "$scope" = "rig" ]; then
        while read -r rig; do
            [ -n "$rig" ] || continue
            if is_suspended "$rig"; then
                notes+=("$name: rig $rig skipped (suspended — not expected to run its cadence)")
                continue
            fi
            printf '%s\n' "$fresh" | grep -qxF "$rig" \
                || errors+=("$name: registered on rig $rig but has NOT fired there in the last ${window}s (3×interval, floor 15m) — that rig's pass is stopped. A city started within the window clears on the next tick; otherwise the controller is not dispatching this order.")
        done <<< "$reg_rigs"
    else
        entry_count=$(printf '%s' "$hist" | jq -r '[.entries[]?] | length' 2>/dev/null)
        if [ "${reg_count:-0}" -gt 0 ] 2>/dev/null && [ "${entry_count:-0}" -eq 0 ] 2>/dev/null; then
            errors+=("$name: registered but has NOT fired in the last ${window}s (3×interval, floor 15m) — the pass is stopped. A city started within the window clears on the next tick; otherwise the controller is not dispatching this order.")
        fi
    fi
done <<< "$order_rows"

if [ "${#errors[@]}" -ne 0 ]; then
    echo "pack cadence not live (I10): ${#errors[@]} finding(s)"
    detail "${errors[@]}"
    detail ${warnings[@]+"${warnings[@]}"}
    detail ${notes[@]+"${notes[@]}"}
    exit 2
fi
if [ "${#warnings[@]}" -ne 0 ]; then
    echo "pack cadence partially determined (I10)"
    detail "${warnings[@]}"
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
echo "OK: every shipped order is registered and fired inside its window"
detail ${notes[@]+"${notes[@]}"}
exit 0
