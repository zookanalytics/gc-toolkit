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
# A third arm asks whether the DEPLOYED gctk binary is the one this checkout
# describes: the cadence's data plane is compiled now, so orders that fire on
# schedule can still be running logic several commits old.
# Read-only. Exit 0=OK 1=Warning 2=Error. stdout: message, then "  - detail"
# lines. Probes bounded; an UNREADABLE probe warns (1), never passes.

set -u

dir="${GC_PACK_DIR:-.}"
FLOOR=900   # 15m — dispatchers fire cooldown orders slower than declared

errors=(); warnings=(); notes=()
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
    detail "\`gc order list --json\` returned no .orders array (no answer inside the probe's slice of the budget, or schema drift); neither arm ran, so a stopped cadence would not be visible."
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

# Arm 3 — the compiled data plane is the one this tree describes.
#
# The cadence's data-plane logic now lives in a binary the gctk-build order
# publishes, so "the orders are firing" stops being the whole question: a build
# that failed leaves the LAST GOOD gctk running the merge queue while the tree
# moves on, and every order arm above stays green through it. `gctk version`
# stamps the revision it was built from, which is the only reading that comes
# from the binary itself rather than from a record the binary did not write.
#
# A mismatch WARNS rather than errors. The build order has minutes of lag by
# design and the state self-heals on the next tick; what an operator needs is to
# see it, and the board's PACK row is where a persistent one shows up.
gctk_bin="${GCTK_BIN:-}"
if [ -z "$gctk_bin" ]; then
    # The same precedence lifecycle.sh resolves the binary by. GC_CITY_PATH is
    # what an agent session carries, so a chain without it reads "no binary
    # deployed" on a city that has one.
    gctk_city="${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-}}}"
    [ -n "$gctk_city" ] && gctk_bin="$gctk_city/.gc/services/gctk/bin/gctk"
fi
# The identity is the services/gctk SUBTREE at HEAD, the same value the build
# order records and stamps: a merge that touches nothing under it neither
# rebuilds the binary nor changes what this arm expects, so unrelated commits
# never light this warning. A hand build carries the toolchain's commit stamp
# instead, and the subtree that commit holds is the comparable identity.
gctk_mod="$dir/services/gctk"
tree_rev=$(git -C "$gctk_mod" rev-parse 'HEAD:./' 2>/dev/null || true)
if [ -z "$gctk_bin" ] || [ ! -x "$gctk_bin" ]; then
    notes+=("gctk: no binary deployed — the cadence is running the shell fallbacks, which is the supported state until the last port lands")
elif [ -z "$tree_rev" ]; then
    warnings+=("gctk: cannot read this checkout's services/gctk revision (\`git -C $gctk_mod rev-parse HEAD:./\`) — the deployed binary cannot be compared against it")
else
    gctk_rev=$(run_bounded "$gctk_bin" version 2>/dev/null | head -1); gctk_rc=${PIPESTATUS[0]}
    if [ -z "$gctk_rev" ] && [ "$gctk_rc" -eq 124 ]; then
        # Refused for time, or timed out: the binary was not asked, or did not
        # answer inside the slice — neither is a fact about the binary.
        warnings+=("gctk: \`$gctk_bin version\` gave no answer inside the probe's slice of the doctor budget — the deployed binary was NOT identified")
    else
        case "$gctk_rev" in
            "")        warnings+=("gctk: \`$gctk_bin version\` answered nothing — the deployed binary cannot be identified") ;;
            unknown)   warnings+=("gctk: the deployed binary carries no revision stamp (built with -buildvcs=false outside the build order) — it cannot be compared against the tree") ;;
            "$tree_rev") notes+=("gctk: deployed binary matches this checkout (${tree_rev:0:12})") ;;
            *)
                mapped=$(git -C "$gctk_mod" rev-parse "${gctk_rev%-dirty}:./" 2>/dev/null || true)
                if [ "$mapped" = "$tree_rev" ]; then
                    notes+=("gctk: deployed binary matches this checkout (${tree_rev:0:12}, hand-built at commit ${gctk_rev:0:12})")
                else
                    warnings+=("gctk: the cadence is running ${gctk_rev%-dirty} but this checkout's services/gctk is at $tree_rev — a gctk-build tick has not caught up, or its last build FAILED and the previous binary is still serving. The board's PACK row says which.")
                fi ;;
        esac
    fi
fi

if budget_spent; then
    warnings+=("this run reached its ${BUDGET_TOTAL}s doctor budget before every probe ran — what follows is partial, and an arm skipped for time is not an arm that passed")
fi

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
