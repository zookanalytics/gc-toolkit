#!/bin/sh
# converse-capability.sh — the single definition of "does a rig carry converse".
#
# Sourced (never executed) by gc-helm.sh (engage's guards and the new-subject
# rig picker) and gc-visit-open.sh (require_reaction_agent), so the two answer
# the same question the same way and cannot diverge.
#
# Converse is a PACK capability. Only gc-toolkit's own checkout holds
# agents/converse-* templates, because gc-toolkit is the pack source; every
# other rig obtains converse by IMPORTING the pack (city.toml source =
# "rigs/gc-toolkit"), so its converse templates live in the import-resolved
# ROSTER, not under rigs/<rig>/agents/. The capability is read from the roster
# `gc agent list --json` reports, keyed on rig NAME — a filesystem glob of one
# checkout sees converse in the source rig alone and refuses every importer.
#
# Fail open: an unreadable or malformed roster refuses nothing. A degraded data
# plane is not a dead zone, so a rig reads as converse-capable when the roster
# cannot be read. An HQ / city-store root carries no converse in a readable
# roster and is correctly excluded.

# converse_roster — populate $_CONVERSE_ROSTER with the import-resolved agent
# roster JSON, fetched once and memoized for the life of this shell (the
# enumerate_rigs/$RIGS idiom: a helper sets a global its callers read, so the
# memo survives — a $(converse_roster) subshell would discard it). $_CONVERSE_ROSTER
# is empty when gc could not answer or the answer was malformed; callers read
# empty as fail-open. Memoized because the new-subject rig picker tests every rig
# against the one roster, and a per-rig fetch would pay the query — and its
# timeout on a degraded plane — once per rig.
converse_roster() {
    if [ "${_CONVERSE_ROSTER_SET:-0}" != 1 ]; then
        _CONVERSE_ROSTER_SET=1
        if command -v timeout >/dev/null 2>&1; then
            _CONVERSE_ROSTER=$(timeout "${GC_ROSTER_TIMEOUT:-15}" gc agent list --json 2>/dev/null || true)
        else
            _CONVERSE_ROSTER=$(gc agent list --json 2>/dev/null || true)
        fi
        # Keep only a well-formed roster — an object carrying an .agents array.
        # Malformed, truncated, or preface-prefixed output is a degraded data
        # plane, so blank it and let every caller fail open on one clean test.
        printf '%s' "$_CONVERSE_ROSTER" \
            | jq -e 'type == "object" and (.agents | type == "array")' >/dev/null 2>&1 \
            || _CONVERSE_ROSTER=""
    fi
}

# rig_carries_converse <rig-name> — 0 iff the resolved roster registers a
# converse-<model> sitting template for the rig, the only kind of converse
# agent gc-helm engage can spawn. Fail open: an unreadable/malformed/empty
# roster returns 0 (serviceable). The "/" in the key stops one rig name
# matching another it is a prefix of.
rig_carries_converse() {
    _rcc_rig="${1:-}"
    converse_roster
    [ -n "${_CONVERSE_ROSTER:-}" ] || return 0
    printf '%s' "$_CONVERSE_ROSTER" | jq -e --arg r "$_rcc_rig" \
        '[ .agents[]? | (.qualified_name // "")
           | select(startswith($r + "/gc-toolkit.converse-")) ] | length > 0' \
        >/dev/null 2>&1
}
