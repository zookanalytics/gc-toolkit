#!/usr/bin/env bash
# Pack doctor check: detect gc-toolkit artifacts that collide with the
# imported gastown base pack, and warn when allowlisted mirrors drift
# behind base.
#
# Background: the 2026-05-27 audit (tk-kdu2v5) found three classes of
# silent mirrors that froze gc-toolkit on stale base snapshots —
#   - formula files in formulas/ shadowing newer base formulas
#   - assets/scripts/ files shadowing newer base scripts
#   - {{ define "name" }} blocks in template-fragments/ shadowing base defines
# Each accumulated drift because no check warned that the base counterpart
# also existed (and had advanced). This check is the structural guard.
#
# Behavior:
#   - For each gc-toolkit artifact whose basename matches a base artifact,
#     decide based on the allowlist:
#       NOT on allowlist                                       → ERROR
#       ON allowlist + base file == base-snapshot              → OK
#       ON allowlist + base file != base-snapshot              → WARN
#     The base-snapshot captures the base file content at the time of
#     the last reconciliation (stored under
#     doctor/check-base-artifact-collision/base-snapshots/<rel>). The
#     check is silent while base is unchanged; it WARNs when base
#     advances so deliberate mirrors do not silently rot.
#
#   - For template-fragments {{ define "name" }} blocks: any define
#     whose name also appears in base is ERROR. There is no allowlist
#     for define-name shadows today; the template engine looks them up
#     by name, not by file, and a redefined block silently replaces
#     the base block at render time.
#
# Reconciliation workflow when this check WARNs:
#   1. cd into the rig and inspect the diff:
#        diff -u doctor/check-base-artifact-collision/base-snapshots/<rel> \
#                /home/.../.gc/system/packs/gastown/<rel>
#   2. Decide whether to fold base advances into the local mirror.
#   3. After reconciling, refresh the snapshot:
#        cp <city>/.gc/system/packs/gastown/<rel> \
#           doctor/check-base-artifact-collision/base-snapshots/<rel>
#   4. Commit the reconciled file + the refreshed snapshot together.
#
# Allowlist policy (HEAD-frozen pairs):
#   - assets/scripts/worktree-setup.sh — base + whitespace-safe branch-create
#     argv local delta (the base built the worktree-add invocation as an
#     unquoted command string, splitting rig/worktree paths that contain
#     whitespace; the mirror builds argv via `set --` instead). Native
#     gc-toolkit polecat-codex / _polecat-gemini agents reference
#     {{.ConfigDir}}/assets/scripts/worktree-setup.sh, and ConfigDir does not
#     fall through to imported packs. Preserve this delta when reconciling.
#   - formulas/mol-deacon-patrol.toml — base + cycle-recycle + gc doctor
#     --json local deltas (validated 2026-05-27).
#   - formulas/mol-refinery-patrol.toml — base + default_merge_strategy +
#     auto_ff_rig_main + check_set (merge-gate check-set, retires review_gate +
#     signoff_head) + protected-branch auto-promote +
#     integration-branch INFO local deltas.
#   - formulas/mol-witness-patrol.toml — base + cycle-recycle +
#     snake_case session-list jq + .work_dir metadata + completed-workflow
#     quiesce step (tk-p9ji9) local deltas.
#
# The allowlist is intentionally narrow. Adding a new entry means the
# rig is taking on the maintenance cost of re-reconciling that artifact
# every time base advances.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

dir="${GC_PACK_DIR:-.}"
city="${GC_CITY_PATH:-}"

if [ -z "$city" ]; then
    # Fall back to discovery from $dir for direct-invocation tests.
    candidate=$(cd "$dir" && pwd)
    while [ -n "$candidate" ] && [ "$candidate" != "/" ] && [ ! -d "$candidate/.gc/system/packs/gastown" ]; do
        candidate=$(dirname "$candidate")
    done
    city="$candidate"
fi

base="$city/.gc/system/packs/gastown"
if [ ! -d "$base" ]; then
    # The .gc/system/packs tree was retired upstream — builtin/imported packs
    # now resolve from the user-global pack cache at a content-addressed path
    # this check cannot locate without a gc affordance to resolve a transitive
    # import's dir. Skip (visible WARN) instead of erroring until gc-xdzml
    # reconnects the base lookup.
    echo "gastown base pack not materialized (import-cache model); collision check skipped — see gc-xdzml"
    exit 1
fi

snap_root="$dir/doctor/check-base-artifact-collision/base-snapshots"

# Allowlist: gc-toolkit-relative paths that are deliberate mirrors.
# Anything NOT in this list that has the same basename as a base
# artifact is treated as an unexpected mirror.
is_allowlisted() {
    case "$1" in
        assets/scripts/worktree-setup.sh) return 0 ;;
        formulas/mol-deacon-patrol.toml) return 0 ;;
        formulas/mol-refinery-patrol.toml) return 0 ;;
        formulas/mol-witness-patrol.toml) return 0 ;;
        *) return 1 ;;
    esac
}

errors=()
warnings=()

count_added() {
    diff -u "$1" "$2" 2>/dev/null | grep -c '^+[^+]' || true
}
count_removed() {
    diff -u "$1" "$2" 2>/dev/null | grep -c '^-[^-]' || true
}

check_mirror() {
    local rel="$1"
    local ours_file="$dir/$rel"
    local base_file="$base/$rel"
    local snap_file="$snap_root/$rel"

    [ -f "$ours_file" ] || return 0    # We don't have this artifact; nothing to check.
    [ -f "$base_file" ] || return 0    # No collision; gc-toolkit-only artifact.

    if ! is_allowlisted "$rel"; then
        errors+=("$rel: not allowlisted; basename collides with $base_file — delete the gc-toolkit copy or add to allowlist with a documented local-delta rationale")
        return 0
    fi

    if [ ! -f "$snap_file" ]; then
        errors+=("$rel: allowlisted but no base snapshot under doctor/check-base-artifact-collision/base-snapshots/$rel — re-reconcile and capture: cp \"$base_file\" \"$snap_file\"")
        return 0
    fi

    if cmp -s "$snap_file" "$base_file"; then
        return 0   # Base unchanged since reconciliation. Silent OK.
    fi

    # Base advanced since reconciliation. Warn with a one-line summary.
    local added removed base_ver our_ver ver_drift
    added=$(count_added "$snap_file" "$base_file")
    removed=$(count_removed "$snap_file" "$base_file")
    ver_drift=""
    if [[ "$rel" == *.toml ]]; then
        base_ver=$(grep -E '^version *=' "$base_file" | head -1 | tr -d ' ' || true)
        our_ver=$(grep -E '^version *=' "$snap_file" | head -1 | tr -d ' ' || true)
        if [ -n "$base_ver" ] && [ -n "$our_ver" ] && [ "$base_ver" != "$our_ver" ]; then
            ver_drift=" (snapshot $our_ver vs base $base_ver)"
        fi
    fi
    warnings+=("$rel: base advanced since reconciliation$ver_drift — +$added/-$removed lines vs snapshot; re-reconcile and refresh snapshot")
}

# --- Scan 1: formulas/*.toml ---------------------------------------------
if [ -d "$dir/formulas" ]; then
    for f in "$dir"/formulas/*.toml; do
        [ -f "$f" ] || continue
        check_mirror "formulas/$(basename "$f")"
    done
fi

# --- Scan 2: assets/scripts/* --------------------------------------------
if [ -d "$dir/assets/scripts" ]; then
    for f in "$dir"/assets/scripts/*; do
        [ -f "$f" ] || continue
        check_mirror "assets/scripts/$(basename "$f")"
    done
fi

# --- Scan 3: template-fragments {{ define }} names -----------------------
# Define-name collisions ARE the silent shadow path for fragments (the
# template engine looks up by define name, not file name). The audit
# already removed the three drifted fragments; this scan keeps it that way.
# No allowlist for fragment defines today — if a deliberate override becomes
# necessary later, extend the allowlist policy above with a documented
# rationale.
if [ -d "$dir/template-fragments" ] && [ -d "$base/template-fragments" ]; then
    base_defines=$(grep -h -oE '\{\{ *define +"[^"]+" *\}\}' "$base"/template-fragments/*.template.md 2>/dev/null \
        | sed -E 's/.*"([^"]+)".*/\1/' | sort -u)
    for ours_file in "$dir"/template-fragments/*.template.md; do
        [ -f "$ours_file" ] || continue
        rel="template-fragments/$(basename "$ours_file")"
        while IFS= read -r define_name; do
            [ -n "$define_name" ] || continue
            if printf '%s\n' "$base_defines" | grep -qx "$define_name"; then
                errors+=("$rel: {{ define \"$define_name\" }} shadows base define of the same name (no fragment-define allowlist)")
            fi
        done < <(grep -oE '\{\{ *define +"[^"]+" *\}\}' "$ours_file" 2>/dev/null | sed -E 's/.*"([^"]+)".*/\1/')
    done
fi

err_count=${#errors[@]}
warn_count=${#warnings[@]}

if [ "$err_count" -eq 0 ] && [ "$warn_count" -eq 0 ]; then
    echo "no base-artifact collisions detected"
    exit 0
fi

if [ "$err_count" -gt 0 ]; then
    echo "$err_count base-artifact collision(s); $warn_count allowlisted-drift warning(s)"
    for e in "${errors[@]}"; do
        echo "ERROR: $e"
    done
    if [ "$warn_count" -gt 0 ]; then
        for w in "${warnings[@]}"; do
            echo "WARN: $w"
        done
    fi
    exit 2
fi

echo "$warn_count allowlisted mirror(s) drifted from snapshot — base advanced; re-reconcile"
for w in "${warnings[@]}"; do
    echo "WARN: $w"
done
exit 1
