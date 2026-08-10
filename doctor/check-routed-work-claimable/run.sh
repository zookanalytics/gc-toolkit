#!/usr/bin/env bash
# Pack doctor check: a routed, unclaimed bead names a route target that exists.
#
# Background (tk-5cgyk, and the mayor's note on it). A pool is offered a bead by
# EXACT string equality between the bead's `gc.routed_to` and one of the pool's
# own route targets — `hookClaimMatchesRoute` in gascity's cmd/gc/cmd_hook_claim.go
# compares `routedTo == target` and nothing else, and the runtime's offer query
# (cmd/gc/dispatch_runtime.go) is the same equality expressed as
# `bd ready --metadata-field "gc.routed_to=$route" --unassigned`. There is no
# late qualification, no prefix search, no fallback. A route that is one
# character off the pool's identity is not a near miss; it is invisible.
#
# The way that happens in practice is a RIG-UNQUALIFIED pool name. Pool
# identities are `<rig>/<binding>.<agent>` — `gc-toolkit/gc-toolkit.polecat`.
# The bare `gc-toolkit.polecat` is the correct at-rest form in an ORDER file,
# where `qualifyPool` prepends the rig at fire time, and orders/liveness-sweep.toml
# says so in its own header. Written straight onto a bead it is qualified by
# nobody, so it matches no pool, and the bead sits open, unassigned, and
# unclaimable for as long as anyone leaves it there.
#
# tk-5cgyk is the case this check was written from, and its shape is the whole
# argument for having it: the bead that carried the durable fix for the
# order-side strand was itself stranded by the bead-side twin of that same
# defect, routed to a bare `gc-toolkit.polecat`. It sat unworked while the orders
# it fixes kept re-stranding every cooldown, and NOTHING reported it — not the
# session model, not any pack check, not the doctor run that was red about the
# order side the entire time.
#
# WHY THE BUILTIN DOES NOT COVER THIS. `v2-routed-to-namespace` looks like it
# should and does not. It builds its short→canonical alias map from
# `unboundRouteIdentity` (gascity cmd/gc/doctor_routed_to_checks.go), which is
# `Dir + "/" + Name` — the agent's RAW name, before the binding prefix. So it
# maps the BINDING-unqualified form (`gc-toolkit/polecat`, missing the
# `gc-toolkit.`) and never the RIG-unqualified form (`gc-toolkit.polecat`,
# missing the `gc-toolkit/`). Those are different short forms of different
# halves of the identity; that check is the PackV2 binding-name migration and
# this is not it. On the live city, with tk-5cgyk open and bare-routed,
# `v2-routed-to-namespace` reports OK.
#
# THE DURABLE FIX IS NOT HERE. Refusing the write beats detecting it afterwards,
# and that guard belongs where the route is stamped — `gc sling`'s
# SetMetadata(gc.routed_to) site in gascity, next to the existing
# `NormalizePoolRouteTarget`, which already normalizes a slot-suffixed target at
# exactly that point and whose docstring names this same failure ("leaves the
# bead structurally invisible to the pool"). Tracked as gc-xaqpf in the gascity
# rig alongside the order-side guard; the design is in
# specs/tk-5cgyk/unqualified-route-targets.md. This check is the pack-side
# backstop that keeps the failure loud until then, and the regression gate after.
#
# WHAT IS FLAGGED — an OPEN, UNASSIGNED bead whose `gc.routed_to` is non-empty,
# is not a live agent identity, and whose rig-qualified form IS one:
#   * `<rig>/<route>` is live, where <rig> is the rig whose store the bead is in
#     → error naming the exact repair. This is the tk-5cgyk shape.
#   * some other `<other-rig>/<route>` is live → error listing the candidates.
#     The bead is just as unclaimable; only the repair is not ours to pick. This
#     is the shape a wisp poured into the city store takes (tk-gi2pc): a bare
#     rig-pool name at city scope, where no rig prefix applies.
#
# WHAT IS NOT FLAGGED:
#   * An exact live identity. That is a working route.
#   * `human` — the deliberate escalation sentinel ("a person must decide"),
#     written by the signoff round cap and read by the quiesce sweeps. It names
#     no agent ON PURPOSE.
#   * An empty `gc.routed_to`. Clearing the route is how the done sequence hands
#     a bead to an assignee; the key is present and blank all over a healthy store.
#   * An ASSIGNED bead. An assignee is its own reachability — the route is not
#     what is carrying it.
#   * A route matching no identity and no `*/route` either. It is unclaimable,
#     but we cannot tell an unknown sentinel from a typo, and `human` proves
#     unknown sentinels exist. Reported in the details, left out of the verdict.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

# `gc doctor` applies no timeout to pack checks, so an unbounded probe against a
# wedged control plane or bead store would hang the whole doctor run.
BOUND="${GC_DOCTOR_CHECK_TIMEOUT:-30}"

# Routes that name no agent BY DESIGN. `human` is the escalation marker the
# signoff round cap stamps and the quiesce sweeps read; flagging it would turn
# every parked human decision into a doctor error.
SENTINEL_ROUTES='["human"]'

errors=()
warnings=()
notes=()

run_bounded() {
    if command -v timeout >/dev/null 2>&1; then
        timeout "$BOUND" "$@" </dev/null
    else
        # No coreutils timeout (some macOS hosts). Degrade to an unbounded call
        # rather than skipping the check entirely.
        "$@" </dev/null
    fi
}

# `printf '%s\n' "${arr[@]}"` with an EMPTY array still prints a blank line,
# which reads as an unexplained detail row in doctor output. Print nothing.
print_lines() { [ "$#" -eq 0 ] || printf '%s\n' "$@"; }

# Bead notes and titles can carry control characters that make jq abort mid-parse,
# which would otherwise cost us a whole store. Everything below 0x20 except the
# newline goes, which is wider than the usual pack idiom: a literal TAB is
# invalid inside a JSON string just like the rest, and this check reduces to TSV,
# so a tab that survived the parse would split a row instead. Nothing here reads
# free text — only ids and route strings — so there is no payload to preserve.
strip_ctl() { tr -d '\000-\011\013-\037'; }

# ---------------------------------------------------------------------------
# The live route-target universe. Unreadable is a WARNING, never a pass: with no
# identity set every route looks dead, and reporting that as clean is the same
# fail-open this check exists to remove.
# ---------------------------------------------------------------------------
agents_raw=$(run_bounded gc agent list --json 2>/dev/null)
agents_rc=$?

if [ "$agents_rc" -ne 0 ] || [ -z "$agents_raw" ]; then
    echo "cannot determine whether routed work is claimable"
    echo "\`gc agent list --json\` failed (rc=$agents_rc) or returned nothing; re-run once the control plane answers."
    exit 1
fi

if ! printf '%s' "$agents_raw" | jq -e 'type == "object" and (.agents | type == "array")' >/dev/null 2>&1; then
    echo "cannot determine whether routed work is claimable"
    echo "\`gc agent list --json\` returned a payload with no .agents array; the listing shape changed or the output is corrupt."
    exit 1
fi

identities=$(printf '%s' "$agents_raw" \
    | jq -c '[.agents[]? | (.qualified_name // "") | select(. != "")] | unique' 2>/dev/null)

if [ -z "$identities" ] || [ "$identities" = "[]" ]; then
    echo "cannot determine whether routed work is claimable"
    echo "\`gc agent list --json\` listed no qualified agent identities; with no identity set every route would look dead."
    exit 1
fi

city_path=$(printf '%s' "$agents_raw" | jq -r '.city_path // ""' 2>/dev/null)

# ---------------------------------------------------------------------------
# The stores to scan: every rig, plus the city root (which `gc rig list`
# includes). A bead is only claimable by a pool that reads its own store, so the
# store a bead sits in is what decides which rig prefix would repair its route.
# ---------------------------------------------------------------------------
rigs_raw=$(run_bounded gc rig list --json 2>/dev/null)
rigs_rc=$?

if [ "$rigs_rc" -ne 0 ] || [ -z "$rigs_raw" ]; then
    echo "cannot determine whether routed work is claimable"
    echo "\`gc rig list --json\` failed (rc=$rigs_rc) or returned nothing; there is no set of bead stores to scan."
    exit 1
fi

scopes=$(printf '%s' "$rigs_raw" \
    | jq -r '.rigs[]? | select((.path // "") != "") | [(.name // ""), .path] | @tsv' 2>/dev/null)

if [ -z "$scopes" ]; then
    echo "cannot determine whether routed work is claimable"
    echo "\`gc rig list --json\` listed no rig paths; the listing shape changed or the output is corrupt."
    exit 1
fi

# ---------------------------------------------------------------------------
# One targeted listing per store — open, unassigned, carrying a route key. Each
# row is classified against the identity set in jq.
# ---------------------------------------------------------------------------
while IFS=$'\t' read -r rig_name rig_path; do
    [ -n "$rig_path" ] || continue

    # At the city root no rig prefix applies, so a dead route there can be
    # reported with candidates but never with a single named repair.
    qualifier="$rig_name"
    if [ -n "$city_path" ] && [ "$rig_path" = "$city_path" ]; then
        qualifier=""
    fi

    beads_raw=$(run_bounded bd list --db "$rig_path/.beads" \
        --status open --no-assignee --has-metadata-key gc.routed_to \
        --json --limit 0 2>/dev/null)
    beads_rc=$?

    if [ "$beads_rc" -ne 0 ]; then
        warnings+=("${rig_name:-<city>}: could not list routed beads in $rig_path/.beads (rc=$beads_rc) — this store was NOT checked")
        continue
    fi

    # An empty store answers `[]`; an empty STRING means the probe produced
    # nothing at all, which is not the same thing and is not a pass.
    if [ -z "$beads_raw" ]; then
        warnings+=("${rig_name:-<city>}: \`bd list\` over $rig_path/.beads returned no output — this store was NOT checked")
        continue
    fi

    rows=$(printf '%s' "$beads_raw" | strip_ctl | jq -r \
        --argjson ids "$identities" \
        --argjson sentinels "$SENTINEL_ROUTES" \
        --arg qualifier "$qualifier" '
        .[]?
        | . as $b
        | (($b.metadata["gc.routed_to"] // "") | tostring | sub("^[[:space:]]+"; "") | sub("[[:space:]]+$"; "")) as $route
        | select($route != "")
        | select(($sentinels | index($route)) == null)
        | select(($ids | index($route)) == null)
        | ([$ids[] | select(endswith("/" + $route))]) as $cands
        | [ (if ($qualifier != "" and ($ids | index($qualifier + "/" + $route)) != null) then "repair"
             elif ($cands | length) > 0 then "ambiguous"
             else "unknown" end),
            ($b.id // "?"), $route, ($cands | join(", ")) ]
        | @tsv' 2>/dev/null)
    rows_rc=$?

    if [ "$rows_rc" -ne 0 ]; then
        warnings+=("${rig_name:-<city>}: routed-bead listing from $rig_path/.beads could not be parsed — this store was NOT checked")
        continue
    fi

    [ -n "$rows" ] || continue

    while IFS=$'\t' read -r class bead_id route cands; do
        [ -n "$class" ] || continue
        case "$class" in
            repair)
                errors+=("${rig_name:-<city>} bead $bead_id: gc.routed_to=\"$route\" names no agent — it is the rig-unqualified form of \"$qualifier/$route\", so no pool is ever offered this bead; set gc.routed_to=\"$qualifier/$route\"")
                ;;
            ambiguous)
                errors+=("${rig_name:-<city>} bead $bead_id: gc.routed_to=\"$route\" names no agent — it is the rig-unqualified form of ${cands}, none of which reads this store, so no pool is ever offered this bead")
                ;;
            *)
                notes+=("${rig_name:-<city>} bead $bead_id: gc.routed_to=\"$route\" matches no agent identity and no rig-qualified form of one; unclaimable, but indistinguishable from a sentinel like \"human\" — reported, not judged")
                ;;
        esac
    done <<< "$rows"
done <<< "$scopes"

if [ "${#errors[@]}" -ne 0 ]; then
    echo "routed work nobody can claim: ${#errors[@]} bead(s)"
    print_lines "${errors[@]}"
    print_lines "${warnings[@]+"${warnings[@]}"}" "${notes[@]+"${notes[@]}"}"
    echo ""
    echo "Each of these is open, unassigned, and invisible to every pool: the offer is an exact string match on gc.routed_to (gascity hookClaimMatchesRoute), so a rig-unqualified pool name is matched by nothing and the bead waits forever. Repair the route as named above. The write-time guard that makes this unwritable is gc-xaqpf in the gascity rig; the design is in specs/tk-5cgyk/unqualified-route-targets.md."
    exit 2
fi

if [ "${#warnings[@]}" -ne 0 ]; then
    echo "routed-work claimability partially determined"
    print_lines "${warnings[@]}"
    print_lines "${notes[@]+"${notes[@]}"}"
    exit 1
fi

echo "OK: every open, unassigned, routed bead names a live agent identity"
print_lines "${notes[@]+"${notes[@]}"}"
exit 0
