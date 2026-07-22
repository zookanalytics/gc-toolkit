#!/usr/bin/env bash
# Pack doctor check: a DECLARED merge gate is never silently dropped.
#
# Background (tk-4na1b, full evidence in tk-4na1b.1): `check_set` names the
# merge gates that must each be green at the live head before an mr-mode merge
# fires. mol-refinery-patrol.toml declares `[vars.check_set] default = "codex"`.
# But the default only has effect at STAMP time — merge-skill.sh reads raw bead
# metadata and never consults the formula:
#
#   merge-skill.sh:67       (.metadata.check_set // "")  — unset collapses to ""
#   merge-skill.sh:157-173  an EMPTY check_set declares NO gates, BY DESIGN
#
# So an anchor stamped check_set="" is UNGATED, and nothing anywhere says the
# rig meant to run a `codex` gate. shutupandlisten landed 11 anchors that way
# over 19 days (2026-07-03..07-22) with zero automated review — invisible,
# because "empty check_set auto-lands on approval" reads as normal.
#
# This check turns that silent drop into a signal. It is DETECT ONLY: it
# changes no merge semantics, ships no fix script, and cannot alter what lands.
#
# WHAT IS FLAGGED — divergence from a NON-EMPTY declared default, in two arms:
#
#   (1) RIG-LEVEL (warning). The resolved check_set for a rig is EXPLICITLY
#       empty while the formula's declared default is non-empty. Resolution
#       follows the real precedence (internal/sling/sling.go buildSlingFormulaVars):
#           --var at a pour site  >  rig formula_vars  >  formula default
#       Warning, not error: a rig CAN legitimately opt out of a declared gate,
#       and the empty value is at least written down where a human can read it.
#
#   (2) ANCHOR-LEVEL (error). A LIVE gating anchor (merge_result=pull_request
#       or pre_open_gate) is stamped check_set="" while its rig's declared
#       default is non-empty. Nothing in config asked for that: the gate was
#       dropped at stamp time on a PR that has not landed yet. This is the
#       shutupandlisten class, and it is the arm that would have caught it on
#       2026-07-02 — su-5ls was a live merge_result=pull_request anchor when
#       the first check_set="" was written.
#
# WHAT IS NOT FLAGGED — deliberately:
#
#   - An UNSET/absent check_set, at either arm. Absent is the pre-#182 legacy
#     state and the city-wide norm (~325 anchors). merge-skill.sh:157-164
#     documents that landing a no-gate anchor is itself a fix — the former code
#     held on a missing marker and stranded human-approved CLEAN PRs forever.
#     Flagging absent would re-litigate that. EXPLICIT "" only, at every layer.
#   - A rig whose declared default is ITSELF empty. The signal is DIVERGENCE
#     from a declared gate, not gatelessness per se.
#   - Direct-merge beads. They never reach merge-skill.sh, so a missing gate
#     there is harmless; exposure is mr-mode anchors only.
#   - Historical PRs. A landed anchor carries merge_result=merged, so the
#     merge_result filter plus the live-bead query (no --all) scope this to
#     work that has not merged yet. Past PRs are reviewed manually and are
#     explicitly out of scope (operator, 2026-07-22).
#
# Suspended rigs are skipped, matching the doctor core's own per-rig rule:
# opening their bead store triggers bd auto-start of orphan Dolt servers.
#
# Every query is bounded — `gc doctor` applies no timeout to pack checks, so a
# wedged data plane must degrade to a warning here rather than hang the doctor.
# An undeterminable arm always reports; it never silently passes.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

dir="${GC_PACK_DIR:-.}"

# The formula that declares the gate and stamps it onto gating anchors, and the
# var it declares. Both are pack constants; the stamp sites are
# mol-refinery-patrol.toml's pre-open (:1469) and post-open (:1481) arms.
FORMULA="mol-refinery-patrol"
VAR="check_set"

# Per-query bound. `gc doctor` never times out a pack check, so an unbounded
# `gc bd` against a wedged Dolt would hang the whole doctor run.
BOUND="${GC_DOCTOR_CHECK_TIMEOUT:-30}"

errors=()
warnings=()
notes=()

# Every query runs with stdin closed: the per-rig loops below read their work
# list from a heredoc on fd 0, and a child that consumed it would silently
# truncate the rig sweep.
run_bounded() {
    if command -v timeout >/dev/null 2>&1; then
        timeout "$BOUND" "$@" </dev/null
    else
        # No coreutils timeout (some macOS hosts). Degrade to an unbounded
        # call rather than skipping the check entirely.
        "$@" </dev/null
    fi
}

# ---------------------------------------------------------------------------
# Arm 1a — pack-level: an explicit `--var check_set=<empty>` at a pour site.
#
# A --var override wins over both the rig formula_vars and the declared
# default, and the pour sites are shared by every rig, so one empty override
# here silently ungates the whole city. Only a LITERALLY empty value counts: a
# `{{...}}` placeholder cannot be resolved statically and is not evidence of
# emptiness.
#
# Scanned dirs are the ones that can carry a pour command (formulas/ holds the
# self-pour chain, template-fragments/ the startup-discovery pours). doctor/,
# specs/, docs/, and assets/ are NOT scanned: they discuss the flag in prose
# and test fixtures — including this very check — and a documentation mention
# is not a pour site.
# ---------------------------------------------------------------------------
pour_override_empty=""
pour_override_site=""
POUR_DIRS="formulas template-fragments agents orders packs"

while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    site="${hit%%:*}"
    rest="${hit#*:}"
    lineno="${rest%%:*}"
    value=$(printf '%s' "$hit" | sed -n "s/.*--var[[:space:]]*${VAR}=\\([^[:space:]]*\\).*/\\1/p")
    # Strip one layer of surrounding quotes so --var check_set="" reads empty.
    case "$value" in
        '""' | "''") value="" ;;
    esac
    if [ -z "$value" ]; then
        pour_override_empty="yes"
        pour_override_site="${site#"$dir"/}:$lineno"
    fi
done <<EOF
$(for d in $POUR_DIRS; do
    [ -d "$dir/$d" ] && grep -rn -- "--var[[:space:]]*${VAR}=" "$dir/$d" 2>/dev/null
done)
EOF

# ---------------------------------------------------------------------------
# Rig roster. `gc rig list --json` reports EFFECTIVE suspension (runtime state,
# not just the config's suspended_on_start), which is what the skip needs.
# ---------------------------------------------------------------------------
rigs_json=$(run_bounded gc rig list --json 2>/dev/null)
rig_rows=$(printf '%s' "$rigs_json" | jq -r '
    .rigs[]?
    | select((.hq // false) | not)
    | [(.name // ""), ((.suspended // false) | tostring)]
    | @tsv' 2>/dev/null)

if [ -z "$rig_rows" ]; then
    echo "could not enumerate rigs — merge-gate drop undetermined"
    echo "\`gc rig list --json\` returned no usable rig roster (timeout ${BOUND}s, or schema drift)."
    echo "Both arms of this check are unresolved; a dropped merge gate would not be visible."
    exit 1
fi

# ---------------------------------------------------------------------------
# Arm 1b input — rig-scoped formula_vars overrides, from the RESOLVED config
# (includes, packs, patches, overrides all folded in). The dump is keyed by Go
# field names; if that shape ever drifts, say so rather than silently reading
# every rig as "no override".
# ---------------------------------------------------------------------------
cfg_json=$(run_bounded gc config show --json 2>/dev/null)
formula_var_rows=""
formula_vars_readable=""
if printf '%s' "$cfg_json" | jq -e '(.config.Rigs | type) == "array"' >/dev/null 2>&1; then
    formula_vars_readable="yes"
    formula_var_rows=$(printf '%s' "$cfg_json" | jq -r --arg var "$VAR" '
        .config.Rigs[]?
        | (.FormulaVars // {}) as $fv
        | [ (.Name // ""),
            (if ($fv | type) == "object" and ($fv | has($var)) then "set" else "absent" end),
            (if ($fv | type) == "object" then ($fv[$var] // "") else "" end) ]
        | @tsv' 2>/dev/null)
else
    warnings+=("rig formula_vars overrides unreadable: \`gc config show --json\` has no .config.Rigs array (timeout ${BOUND}s, or config schema drift). A rig-scoped ${VAR}=\"\" override would not be visible to arm 1.")
fi

rig_formula_var_state() {
    # echo "<state>\t<value>" — state is set|absent.
    local rig="$1" row
    row=$(printf '%s\n' "$formula_var_rows" | awk -F'\t' -v r="$rig" '$1 == r { print $2 "\t" $3; exit }')
    [ -n "$row" ] && printf '%s' "$row" || printf 'absent\t'
}

# ---------------------------------------------------------------------------
# Per-rig evaluation.
# ---------------------------------------------------------------------------
checked=0
skipped_suspended=0

while IFS=$'\t' read -r rig suspended; do
    [ -z "$rig" ] && continue

    if [ "$suspended" = "true" ]; then
        skipped_suspended=$((skipped_suspended + 1))
        notes+=("$rig: skipped (suspended — querying its store would auto-start an orphan Dolt server)")
        continue
    fi

    # Declared default, read from the formula THIS rig resolves (rigs symlink
    # the pack copy today, but a divergent copy must be read on its own terms).
    formula_json=$(run_bounded gc bd --rig "$rig" formula show "$FORMULA" --json 2>/dev/null)
    if ! printf '%s' "$formula_json" | jq -e '(.vars | type) == "object"' >/dev/null 2>&1; then
        warnings+=("$rig: could not read \`$FORMULA\` var declarations (timeout ${BOUND}s, formula absent, or schema drift) — merge-gate drop undetermined for this rig")
        continue
    fi
    if ! printf '%s' "$formula_json" | jq -e --arg var "$VAR" '.vars | has($var)' >/dev/null 2>&1; then
        notes+=("$rig: \`$FORMULA\` declares no [vars.$VAR] — nothing to diverge from")
        continue
    fi
    declared=$(printf '%s' "$formula_json" | jq -r --arg var "$VAR" '.vars[$var].default // ""' 2>/dev/null)

    checked=$((checked + 1))

    if [ -z "$declared" ]; then
        # A gateless declaration is a legitimate configuration, not a drop.
        notes+=("$rig: declared default for $VAR is empty — gateless by declaration, not flagged")
        continue
    fi

    # --- Arm 1: resolved-vs-declared -------------------------------------
    IFS=$'\t' read -r fv_state fv_value <<EOF
$(rig_formula_var_state "$rig")
EOF
    if [ -n "$pour_override_empty" ]; then
        warnings+=("$rig: resolved $VAR is empty but the declared default is \"$declared\" — expected \"$declared\", actual \"\" (source: pour-site override \`--var $VAR=\` at $pour_override_site, which outranks the declared default for every rig)")
    elif [ "$fv_state" = "set" ] && [ -z "$fv_value" ]; then
        warnings+=("$rig: resolved $VAR is empty but the declared default is \"$declared\" — expected \"$declared\", actual \"\" (source: rig formula_vars.$VAR = \"\", which outranks the declared default)")
    fi

    # --- Arm 2: live gating anchors stamped empty -------------------------
    # No --all: closed beads are out of scope, so a landed anchor cannot be
    # reported. --has-metadata-key keeps the result set to anchors that carry
    # the key at all, which is also what makes "" distinguishable from unset.
    anchors_json=$(run_bounded gc bd --rig "$rig" list --has-metadata-key "$VAR" --json --limit 0 2>/dev/null)
    if ! printf '%s' "$anchors_json" | jq -e 'type == "array"' >/dev/null 2>&1; then
        warnings+=("$rig: could not list beads carrying $VAR (timeout ${BOUND}s, or bead store unavailable) — live ungated anchors undetermined for this rig")
        continue
    fi

    while IFS=$'\t' read -r bead merge_result pr; do
        [ -z "$bead" ] && continue
        errors+=("$rig/$bead: live gating anchor (merge_result=$merge_result, PR $pr) stamped $VAR=\"\" — expected \"$declared\", actual \"\" (no config asked for this; the gate was dropped at stamp time and this PR can land with no automated review)")
    done <<EOF
$(printf '%s' "$anchors_json" | jq -r --arg var "$VAR" '
    .[]?
    | select(.metadata | has($var))
    | select(.metadata[$var] == "")
    | select((.metadata.merge_result // "") | . == "pull_request" or . == "pre_open_gate")
    | [ .id,
        (.metadata.merge_result // ""),
        ("#" + ((.metadata.pr_number // "?") | tostring)) ]
    | @tsv' 2>/dev/null)
EOF
done <<EOF
$rig_rows
EOF

# ---------------------------------------------------------------------------
# Report. Errors outrank warnings; an undeterminable arm still surfaces.
# ---------------------------------------------------------------------------
emit_details() {
    local v
    for v in ${errors[@]+"${errors[@]}"}; do echo "ERROR: $v"; done
    for v in ${warnings[@]+"${warnings[@]}"}; do echo "WARN:  $v"; done
    for v in ${notes[@]+"${notes[@]}"}; do echo "note:  $v"; done
}

n_err=${#errors[@]}
n_warn=${#warnings[@]}

if [ "$n_err" -gt 0 ]; then
    echo "$n_err live gating anchor(s) stamped $VAR=\"\" against a non-empty declared default"
    emit_details
    echo "Remedy: stamp the declared gate on the anchor (\`gc bd update <bead> --set-metadata $VAR=<gate>\`)"
    echo "and dispatch that gate's review, or record the opt-out where a human can see it"
    echo "(rig formula_vars.$VAR). Detect only — this check changes no merge semantics."
    exit 2
fi

if [ "$n_warn" -gt 0 ]; then
    echo "$n_warn rig-level $VAR divergence(s) / undetermined arm(s)"
    emit_details
    exit 1
fi

summary="no silently-dropped merge gates: $checked rig(s) checked, no empty $VAR override, 0 live gating anchor(s) stamped empty"
[ "$skipped_suspended" -gt 0 ] && summary="$summary ($skipped_suspended suspended rig(s) skipped)"
[ -z "$formula_vars_readable" ] && summary="$summary [formula_vars overrides unread]"
echo "$summary"
emit_details
exit 0
