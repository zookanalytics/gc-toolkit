#!/usr/bin/env bash
# Pack doctor check: a DECLARED merge gate is never silently dropped.
#
# Background (tk-4na1b, full evidence in tk-4na1b.1): `check_set` names the
# merge gates that must each be green at the live head before an mr-mode merge
# fires. mol-refinery-patrol.toml declares `[vars.check_set] default = "codex"`.
# But the default only has effect at STAMP time — merge-skill.sh reads raw bead
# metadata and never consults the formula:
#
#   merge-skill.sh, the ROWS projection:  (.metadata.check_set // "")
#       — an unset check_set collapses to ""
#   merge-skill.sh, the `hold_gate` check-set gate:  an EMPTY check_set declares
#       NO gates, BY DESIGN
#
# (Cited by SYMBOL, not line number, on purpose: this file has already chased
# merge-skill.sh's line numbers across two reworks and the citations were stale
# both times. Grep the names.)
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
#   (3) EXCEPTION-HELD (warning). A LIVE gating anchor carries a gate marker
#       `check.<name>=exception@<sha>` — the third verdict verb (WS4, tk-zgse0),
#       recorded when a gate's result cannot be turned into pass-or-fixable. The
#       hold is correct and deliberate, so this is not a drop; what earns the line
#       is that the hold is UNBOUNDED and self-announces exactly once per head, so
#       nothing surfaces it afterwards. A PR held forever belongs in the answer to
#       "what is stuck" — but only while it is actually stuck. An anchor with live
#       remediation already in flight is NOT (see `remediation_for` below); it is
#       noted and not flagged, because a held anchor somebody is already fixing
#       costs an operator a re-triage and buys nothing (tk-ezgr2).
#
# WHAT IS NOT FLAGGED — deliberately:
#
#   - An UNSET/absent check_set, at either arm. Absent is the pre-#182 legacy
#     state and the city-wide norm (~325 anchors). merge-skill.sh's `hold_gate`
#     gate documents that landing a no-gate anchor is itself a fix — the former code
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
#   - An exception-held gate whose anchor ALREADY HAS live remediation. Arm 3
#     only asks an operator for a ruling; a ruling is already unnecessary when a
#     rework or rebase child is running against the anchor. It is downgraded to a
#     note, never dropped silently, and the green summary counts it. Suppression
#     requires a LIVE bead (the shared `acting` predicate) that is not the anchor
#     itself — an inert husk on the branch leaves the anchor reported, which is
#     the stranded-anchor case this check exists to catch.
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
# Is remediation for an exception-held anchor ALREADY RUNNING?
#
# Arm 3 reports a held gate so a human can rule on it. That is only worth an
# operator's attention when nothing is already coming for the anchor — and three
# times in under 24 hours it was not (tk-ezgr2): the hold was reported while a
# live rework ran against the very same branch, and each report cost a full mayor
# re-triage. One patrol earlier the same class was caught by hand and written
# down — "unassigned is not the right liveness test for a held anchor" — and the
# check still did not implement it. The deacon restarts fresh every cycle, so
# nothing instruction-shaped survives to the next patrol; the remedy has to be
# mechanical, and this is it.
#
# WHY TESTING THE ANCHOR CANNOT SEE IT. Remediation does not run on the anchor.
# It runs on a SEPARATE child bead with its own workflow — a rework, or a
# rebase-and-re-author child — which leaves the anchor unassigned and unmentioned
# by id in any bead title. An anchor with vigorous live work against its branch is
# indistinguishable, from the anchor alone, from an abandoned one. Asking the
# LEDGER for a bead that names the anchor is what distinguishes them.
#
# Two surfaces, each one indexed metadata lookup:
#   EXACT — `source_anchor_bead=<anchor>`, stamped by reconcile-merged-prs.sh on
#           every rebase child it files. Carrying it IS naming this anchor.
#   BROAD — `branch=<the anchor's branch>`. Rework children never carry
#           source_anchor_bead — check-set-heal.sh's `inflight_for` splits its own
#           surfaces on exactly that fact — and the branch they push to is what
#           ties them to this anchor.
#
# MEMBERSHIP IS THE SHARED PREDICATE, not a local rule. `acting` is what separates
# a live rework from an inert husk, and a local answer here would fail in the
# direction this check exists to prevent: a bead that merely EXISTS would silence
# a genuinely stranded anchor forever. Two live facts make that concrete — an
# anchor's own branch lookup returns THE ANCHOR ITSELF (the self-exclusion is
# load-bearing, not defensive), and a rebase child whose metadata stamp was
# dropped sits open, unrouted and unclaimed by design (reconcile-merged-prs.sh
# calls it "a bounded orphan"), which is not remediation. On the BROAD surface a
# bead naming ANOTHER anchor is dropped too: its own anchor holds its own merge.
#
# AN UNREADABLE LEDGER IS NOT "NOTHING IN FLIGHT". The lookup returns rc=2 and the
# exception is reported anyway with the failure named — the same rule every other
# arm here follows: an undeterminable arm always reports, never silently passes.
# The block below is COPIED VERBATIM from assets/scripts/check-set-heal.sh, the
# canonical copy, and is drift-checked by assets/scripts/inflight-membership.test.sh.
# Copy the markers too.
# >>> inflight-membership
# shellcheck disable=SC2034  # part of the shared block; not every host spends it
INFLIGHT_LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"
INFLIGHT_MEMBERSHIP_JQ='def claimable:
  . as $b
  | (($b.metadata // {})) as $m
  | ((($b.assignee // "") | tostring) | gsub("[[:space:]]"; "")) as $as
  | ((($m["gc.routed_to"] // "") | tostring) != "")
    or (((($m["gc.execution_routed_to"] // "") | tostring) != "") and ($as == ""));
def acting($live):
  . as $b
  | (($b.metadata // {})) as $m
  | (($live | split(",")) | map(select(. != "open"))) as $owning
  | ((($m.task_kind // "") | tostring) == "review")
    or (($owning | index(((($b.status // "") | tostring) | ascii_downcase))) != null)
    or ($b | claimable);
def anchor_authority($a):
  ((((. // {}).metadata // {}).anchor_bead // "") | tostring) as $ab
  | if $ab == "" then "unattributed" elif $ab == $a then "mine" else "theirs" end;
'
# <<< inflight-membership

# Echoes `<surface> <bead-id>` for a bead that is actively remediating
# <anchor-id>, or nothing when none is. rc=2 means the ledger could not answer
# and the caller must NOT read that as "nothing in flight".
#
# The surface is tagged — `inflight_for` tags review-vs-rework for the same
# reason — because the two are not equally strong evidence: `source_anchor_bead`
# NAMES this anchor, while a shared branch infers it. A human re-reading the note
# should not have to guess which one bought the silence.
remediation_for() { # <rig> <anchor-id> <anchor-branch>
    local rig="$1" aid="$2" br="$3" raw="" found=""

    raw=$(run_bounded gc bd --rig "$rig" list \
              --metadata-field "source_anchor_bead=$aid" \
              --status="$INFLIGHT_LIVE_STATUSES" --json --limit 0 --brief 2>/dev/null)
    printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 2
    found=$(printf '%s' "$raw" \
        | jq -r --arg a "$aid" --arg live "$INFLIGHT_LIVE_STATUSES" \
            "$INFLIGHT_MEMBERSHIP_JQ"'[.[] | select(.id != $a) | select(acting($live))]
                | .[0].id // empty' 2>/dev/null) || return 2
    if [ -n "$found" ]; then printf 'source_anchor_bead %s' "$found"; return 0; fi

    # The anchor's branch is the only tie a rework child leaves. No branch
    # recorded means this surface asks nothing — not that it answered "none".
    [ -n "$br" ] || return 0
    raw=$(run_bounded gc bd --rig "$rig" list \
              --metadata-field "branch=$br" \
              --status="$INFLIGHT_LIVE_STATUSES" --json --limit 0 --brief 2>/dev/null)
    printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 2
    found=$(printf '%s' "$raw" \
        | jq -r --arg a "$aid" --arg live "$INFLIGHT_LIVE_STATUSES" \
            "$INFLIGHT_MEMBERSHIP_JQ"'[.[] | select(.id != $a) | select(acting($live))
                | select(anchor_authority($a) != "theirs")]
                | .[0].id // empty' 2>/dev/null) || return 2
    [ -n "$found" ] && printf 'branch %s' "$found"
    return 0
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
# Exception-held gates suppressed because remediation is already in flight.
# Counted rather than dropped: a suppression nobody can see reads as "there was
# nothing to suppress", which is the failure this arm is one step away from.
exception_owned=0

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

    # --- Arm 3: gates HELD IN EXCEPTION ----------------------------------
    # The third verdict verb (WS4, tk-zgse0 —
    # specs/tk-zgse0.2/merge-gate-exception-lifecycle.md). A gate records
    # `check.<name>=exception@<sha>` when its result cannot be turned into
    # pass-or-fixable: the remediation rounds are spent (R11), or the check-skill
    # crashed, timed out, or emitted output the contract cannot map (R12). The
    # marker verb is not `green`, so merge-skill.sh holds — correctly, and
    # INDEFINITELY, because an exception has no mechanical remedy by definition.
    #
    # Warning, not error, and this is the distinction that keeps the check honest:
    # an exception is a gate working exactly as designed, not a gate silently
    # dropped. What earns a line here is that the hold is UNBOUNDED and its one
    # operator notification fires once per head — so after that single mail the
    # anchor sits held with nothing further to announce it. `gc doctor` is where a
    # human looks for "what is stuck"; an indefinitely-held PR belongs in that
    # answer. It clears when the operator acts and the head moves, which re-arms
    # every head-bound datum at once and re-evaluates the gate fresh.
    #
    # Read off the SAME anchor list as arm 2 — every gating anchor with a gate
    # carries check_set, which is what --has-metadata-key already selected. The
    # value test (not a key-shape test) is what keeps the arm off the sidecar keys
    # the verdict arm writes beside the marker: check.<name>.reason holds prose,
    # .attempts holds "<n>@<sha>", .exception_escalated holds a bare sha, and none
    # of them can begin with "exception@".
    #
    # `reason` stays LAST in the row: it is prose, and only the final field can
    # absorb a stray separator. (@tsv escapes tabs anyway; the ordering keeps that
    # from being the only thing standing between prose and a shifted field.)
    while IFS=$'\t' read -r bead gate marker merge_result pr branch reason; do
        [ -z "$bead" ] && continue
        held="$rig/$bead: merge gate '$gate' is HELD IN EXCEPTION ($marker) on a live gating anchor (merge_result=$merge_result, PR $pr) — reason: ${reason:-<none recorded>}. The gate holds the merge and no automated path will lift it; it re-arms only when the input changes and the head moves."
        owner_rc=0
        owner=$(remediation_for "$rig" "$bead" "$branch") || owner_rc=$?
        if [ "$owner_rc" != "0" ]; then
            warnings+=("$held Whether remediation is already in flight is UNDETERMINED (the ledger lookup failed or timed out at ${BOUND}s) — reported rather than assumed owned.")
        elif [ -n "$owner" ]; then
            # Live remediation names this anchor. The hold is tracked, so there is
            # nothing here for an operator to rule on until that work lands — and
            # reporting it anyway is what cost three mayor re-triages (tk-ezgr2).
            # Noted, not flagged: the trail stays readable in the details without
            # spending a warning.
            exception_owned=$((exception_owned + 1))
            # The broad surface names the branch it matched on; the exact one
            # needs no qualifier, and repeating the branch there would read as
            # though both surfaces had fired.
            via="${owner%% *}"
            [ "$via" = "branch" ] && via="branch $branch"
            notes+=("$rig/$bead: merge gate '$gate' held in exception ($marker) — NOT flagged: $rig/${owner#* } is live and remediating it (matched on $via). Nothing to rule on until that work lands.")
        else
            warnings+=("$held No live bead names this anchor or its branch${branch:+ ($branch)}, so nothing is remediating it.")
        fi
    done <<EOF
$(printf '%s' "$anchors_json" | jq -r '
    .[]?
    | select((.metadata.merge_result // "") | . == "pull_request" or . == "pre_open_gate")
    | . as $b
    | (.metadata // {}) | to_entries[]
    | select(.key | startswith("check."))
    | select((.value | type) == "string")
    | select(.value | startswith("exception@"))
    | [ $b.id,
        (.key | sub("^check\\."; "")),
        .value,
        ($b.metadata.merge_result // ""),
        ("#" + (($b.metadata.pr_number // "?") | tostring)),
        (($b.metadata.branch // "") | tostring),
        (($b.metadata[.key + ".reason"] // "") | tostring) ]
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
    echo "$n_warn rig-level $VAR divergence(s) / exception-held gate(s) / undetermined arm(s)"
    emit_details
    exit 1
fi

summary="no silently-dropped merge gates: $checked rig(s) checked, no empty $VAR override, 0 live gating anchor(s) stamped empty, 0 gate(s) held in exception"
[ "$exception_owned" -gt 0 ] && summary="$summary needing a ruling ($exception_owned already being remediated — see notes)"
[ "$skipped_suspended" -gt 0 ] && summary="$summary ($skipped_suspended suspended rig(s) skipped)"
[ -z "$formula_vars_readable" ] && summary="$summary [formula_vars overrides unread]"
echo "$summary"
emit_details
exit 0
