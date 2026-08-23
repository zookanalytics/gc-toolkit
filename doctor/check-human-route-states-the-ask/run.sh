#!/usr/bin/env bash
# Pack doctor check: a human-routed bead states the judgment it is asking for.
#
# THE RULE (docs/gascity-routing-model.md, "gc.routed_to=human means
# unclaimable, not unclaimed"). `human` is the one value of `gc.routed_to` that
# names no agent. Every other value is a pool or session identity that some
# worker matches byte-for-byte; `human` matches nobody by design, and the checks
# that hunt dead routes exempt it as a sentinel (check-routed-work-claimable
# lists it in SENTINEL_ROUTES for exactly that reason).
#
# Which makes it the one route value nothing can correct. A misspelled pool name
# is LOUD — the bead sits unclaimed and that sibling check names the repair.
# `human` is SILENTLY unclaimed, forever, and looks deliberate while it is. So
# it drifts into meaning "nobody picked this up": on the 2026-08-23 board, four
# of the nine ELEVATED `human` rows were plain agent work (a polecat rework
# dispatch, a doctor check that could not be computed, a witness bug with a code
# fix, a reaper nobody had built), and three of the nine carried the marker and
# nothing else at all — no reason, no owner, no ask (tk-wfufb9).
#
# WHAT IS FLAGGED — an open or blocked bead whose `gc.routed_to` is EXACTLY
# `human` and whose `blocked_reason` is absent, or present and made only of
# whitespace. Nothing else about the bead is judged.
#
# WHY THAT IS THE TEST, and not something cleverer. No check can decide from
# outside whether a route was CORRECT — that is the judgment the route was
# supposed to record. What it can decide is whether anybody made one. Every pack
# writer of the marker already writes `blocked_reason` in the SAME
# `gc bd update`: the refinery patrol merge-blocked and signoff-cap arms, the
# merge reconciler retargeted / abandoned / stale-base arms, check-set-heal
# reopen-flap arm. So the pair — not the marker — is the convention the
# machinery keeps and a hand-written route drops, and the missing half is a
# reliable proxy for a route nobody decided.
#
# EXACT match on `human`, like every reader of the marker. A padded `" human "`
# is not this sentinel: the quiesce sweeps compare byte-for-byte, and
# check-routed-work-claimable already reports that shape as an unknown route.
# Flagging it here too would give one bead two different diagnoses.
#
# WHAT IS NOT FLAGGED:
#   * A `human` bead WITH a non-blank `blocked_reason`. The ask is recorded;
#     whether it is a GOOD ask is a human judgement, not a check.
#   * Any other route value — that is check-routed-work-claimable question.
#   * Closed beads. The route stops meaning anything once the bead is closed,
#     and reconcile-merged-prs deliberately leaves the pair on a bead it left
#     closed, as the findable record of an out-of-band close.
#
# WARNS, never errors. An unexplained route is a debt, not a break: the bead is
# still reachable and nothing is stalled behind it. The cost is the operator
# attention, and the helm board half of this fix already charges for that (a row
# with no ask now reads "unexplained human route — state the ask or return it to
# the pool" instead of the old constant "operator action").
#
# The `blocked` half is why this exists as a check at all rather than as board
# rendering alone. The helm gather takes OPEN beads only, so a bead parked
# `status=blocked` + `gc.routed_to=human` — the shape mol-witness-patrol
# documents — is on no board anywhere. For those, this line is the only place it
# is ever said.
#
# Exit codes: 0=OK, 1=Warning, 2=Error (unused — see WARNS above)
# stdout: first line=message, rest=details

set -u

# `gc doctor` applies no timeout to pack checks, so an unbounded probe against a
# wedged control plane or bead store would hang the whole doctor run.
BOUND="${GC_DOCTOR_CHECK_TIMEOUT:-30}"

# The sentinel, spelled once. Compared byte-for-byte, exactly as every reader of
# the marker compares it.
HUMAN_ROUTE="human"

findings=()
warnings=()

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

# Bead titles carry control characters that make jq abort mid-parse, which would
# otherwise cost a whole store. Everything below 0x20 except the newline goes —
# a literal TAB is invalid inside a JSON string just like the rest, and it also
# clears the 0x1F this check joins its rows on, so no payload byte can pose as a
# field separator.
strip_ctl() { tr -d '\000-\011\013-\037'; }

# ---------------------------------------------------------------------------
# The stores to scan: every rig, plus the city root (which `gc rig list`
# includes). Unreadable is a WARNING, never a pass — a store that cannot be read
# hides exactly the beads this check exists to find.
# ---------------------------------------------------------------------------
rigs_raw=$(run_bounded gc rig list --json 2>/dev/null)
rigs_rc=$?

if [ "$rigs_rc" -ne 0 ] || [ -z "$rigs_raw" ]; then
    echo "cannot determine whether human-routed work states its ask"
    echo "\`gc rig list --json\` failed (rc=$rigs_rc) or returned nothing; there is no set of bead stores to scan."
    exit 1
fi

scopes=$(printf '%s' "$rigs_raw" \
    | jq -r '.rigs[]? | select((.path // "") != "")
             | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path]
             | join("\u001f")' 2>/dev/null)

if [ -z "$scopes" ]; then
    echo "cannot determine whether human-routed work states its ask"
    echo "\`gc rig list --json\` listed no rig paths; the listing shape changed or the output is corrupt."
    exit 1
fi

# ---------------------------------------------------------------------------
# One targeted listing per store. The server-side `--metadata-field` filter is
# what keeps this cheap on a large ledger; `--limit 0` is what keeps it correct
# (the default 50-row window silently drops findings past the first page), and
# the explicit `--status` is what widens it past the open-only default a bare
# `--metadata-field` query carries.
# ---------------------------------------------------------------------------
# US-joined, not tab: a rig whose name is empty must still yield an empty FIRST
# field and a path in the second. Under a tab IFS bash would collapse the pair,
# land the path in rig_name, leave rig_path empty, and `continue` — silently
# skipping a whole store, which is the fail-open this check exists to remove.
while IFS=$'\037' read -r rig_name rig_path; do
    [ -n "$rig_path" ] || continue

    beads_raw=$(run_bounded bd list --db "$rig_path/.beads" \
        --status open,blocked --metadata-field "gc.routed_to=$HUMAN_ROUTE" \
        --json --limit 0 2>/dev/null)
    beads_rc=$?

    if [ "$beads_rc" -ne 0 ]; then
        warnings+=("${rig_name:-<city>}: could not list human-routed beads in $rig_path/.beads (rc=$beads_rc) — this store was NOT checked")
        continue
    fi

    # An empty store answers `[]`; an empty STRING means the probe produced
    # nothing at all, which is not the same thing and is not a pass.
    if [ -z "$beads_raw" ]; then
        warnings+=("${rig_name:-<city>}: \`bd list\` over $rig_path/.beads returned no output — this store was NOT checked")
        continue
    fi

    rows=$(printf '%s' "$beads_raw" | strip_ctl | jq -r \
        --arg human "$HUMAN_ROUTE" '
        .[]?
        | . as $b
        # The route EXACTLY as stored. `--metadata-field` did the selecting, but
        # this re-asserts it rather than trusting the filter: a server-side
        # matcher that ever normalized would hand us padded values, and those are
        # a DIFFERENT finding owned by a different check.
        | select((($b.metadata["gc.routed_to"] // "") | tostring) == $human)
        # Present-but-blank is not an ask. blocked_reason is routinely built by
        # interpolation, and an empty interpolation leaves a field that is
        # present, non-empty, and says nothing — which is exactly what the board
        # renderer treats as absent, so the two must agree.
        | (($b.metadata["blocked_reason"] // "") | tostring
           | gsub("[[:space:][:cntrl:]]"; "")) as $ask
        | select($ask == "")
        | [ (($b.id // "?") | gsub("[[:cntrl:]]"; " ")),
            (($b.status // "?") | gsub("[[:cntrl:]]"; " ")),
            (($b.title // "") | gsub("[[:cntrl:]]"; " ")) ]
        | join("\u001f")' 2>/dev/null)
    rows_rc=$?

    if [ "$rows_rc" -ne 0 ]; then
        warnings+=("${rig_name:-<city>}: human-routed listing from $rig_path/.beads could not be parsed — this store was NOT checked")
        continue
    fi

    [ -n "$rows" ] || continue

    while IFS=$'\037' read -r bead_id status title; do
        [ -n "$bead_id" ] || continue
        board_note=""
        [ "$status" != "blocked" ] || board_note=" — and it is \`blocked\`, so no helm board shows it either"
        findings+=("${rig_name:-<city>} bead $bead_id ($status): gc.routed_to=human with no blocked_reason — nothing on this bead says what the operator is being asked to decide$board_note. Title: $title")
    done <<< "$rows"
done <<< "$scopes"

if [ "${#findings[@]}" -ne 0 ]; then
    echo "human-routed beads that state no ask: ${#findings[@]} bead(s)"
    print_lines "${findings[@]}"
    print_lines "${warnings[@]+"${warnings[@]}"}"
    echo ""
    echo "gc.routed_to=human means ONLY a human can perform the next action — a judgment, a consent, an irreversible call. It is not a synonym for unassigned or unclaimed, and it is the one route value nothing can correct: no pool matches it, no sweep reclaims it, and it looks deliberate forever. Each bead above is therefore either a judgment nobody wrote down or work that was never the operator to do. Repair by adding the missing half — gc bd update <bead> --set-metadata blocked_reason=\"<the judgment being asked for>\" — or, where an agent can do the work, by routing it to the owning pool instead. The rule is docs/gascity-routing-model.md, \"gc.routed_to=human means unclaimable, not unclaimed\"; the board half is services/helm/README.md, \"What a human row asks for\"."
    exit 1
fi

if [ "${#warnings[@]}" -ne 0 ]; then
    echo "human-route asks partially determined"
    print_lines "${warnings[@]}"
    exit 1
fi

echo "OK: every human-routed bead states the judgment it is asking for"
exit 0
