#!/usr/bin/env bash
# reconcile-rig-checkouts — keep managed rigs/* checkouts synced to origin/main.
#
# Design: tk-yjtf. Implementation: tk-nu5u. See orders/reconcile-rig-checkouts.toml
# for the order wiring and the rollout (ships in dry-run / observe mode).
#
# Per run, for each managed rig checkout: `git fetch origin`, then classify every
# local deviation (a commit in origin/main..HEAD OR a dirty hunk) into one of
# three buckets and act on the rig as a whole:
#
#   1. KNOWN DIVERGENCE  — allowlisted path (seed .beads/**). KEEP, never block.
#   2. ALREADY UPSTREAM  — patch-equivalent commit (`git cherry`) or blob-identical
#                          dirty file. Obsolete residue; dropped on advance.
#   3. NOVEL REAL WORK    — not on origin, not allowlisted:
#        * conflicts (upstream also changed those paths since the merge-base)
#          -> BLOCK the rig, escalate to the mayor, do NOT mutate the checkout.
#        * no conflict -> advance the checkout to origin/main but PRESERVE the
#          novel work on top, and flag it in the ledger as a PR-promotion
#          candidate (docs/gascity-local-patching.md candidate-set model, one
#          level down).
#
# A rig BLOCKS iff it has at least one novel-conflicting deviation. Otherwise it
# advances (live mode) or is reported as would-advance (dry-run). Advancing
# preserves allowlisted paths and non-conflicting novel work; already-upstream
# local commits are dropped (the pre-advance sha is logged + recorded in the
# ledger, and git reflog is the backstop).
#
# Runs as an exec order (no LLM, no agent, no wisp). Best-effort: a failure on
# one rig must never crash the controller's order loop or stop other rigs.
#
# Environment (controller-provided unless noted):
#   PACK_DIR / GC_PACK_DIR     pack directory (for default allowlist path)
#   GC_PACK_STATE_DIR          durable state dir (ledger + escalation dedup)
#   GC_CITY / GC_CITY_ROOT     city root (default scope for mayor escalation beads)
# Tunables (order.env or shell):
#   RECONCILE_DRY_RUN=1        observe mode: classify + report, ZERO checkout
#                              mutations (default 1; also via --dry-run flag)
#   RECONCILE_MAYOR_ADDR=mayor escalation target (owner/route of blocked-rig bead)
#   RECONCILE_ESCALATE=1       create/refresh/close mayor beads + nudge (default 1)
#   RECONCILE_INCLUDE_UNTRACKED=0  also classify untracked files (default 0:
#                              tracked + staged + commits only; untracked survive
#                              an advance and are usually machine-local cruft)
#   RECONCILE_ALLOWLIST_FILE   allowlist path (default $PACK_DIR/assets/config/
#                              reconcile-rig-checkouts.allowlist)
#   RECONCILE_ALLOWLIST_EXTRA  extra patterns, newline- or ':'-separated
#   RECONCILE_LEDGER_DIR       ledger output dir (default $GC_PACK_STATE_DIR/
#                              reconcile-rig-checkouts/ledger)
#   RECONCILE_STATE_FILE       escalation dedup state file
#   RECONCILE_RIGS_OVERRIDE    test seam: "name=path" lines, bypass `gc rig list`
set -uo pipefail

log() { printf 'reconcile-rig-checkouts: %s\n' "$*"; }
err() { printf 'reconcile-rig-checkouts: %s\n' "$*" >&2; }

# jq and git are hard dependencies; fail loud (mirrors cascade-nudge).
for dep in git jq; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        err "$dep is required but not found in PATH"
        exit 1
    fi
done

# ---- configuration -----------------------------------------------------------

DRY_RUN="${RECONCILE_DRY_RUN:-1}"
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --apply) DRY_RUN=0 ;;
    esac
done
case "$DRY_RUN" in 0 | false | no) DRY_RUN=0 ;; *) DRY_RUN=1 ;; esac

MAYOR_ADDR="${RECONCILE_MAYOR_ADDR:-mayor}"
ESCALATE="${RECONCILE_ESCALATE:-1}"
case "$ESCALATE" in 0 | false | no) ESCALATE=0 ;; *) ESCALATE=1 ;; esac

# The reconciler syncs TRACKED content (commits + staged/modified files). By
# default it ignores untracked files: they survive an advance untouched (reset
# --hard never removes them) and in practice are machine-local cruft (backup/*,
# LOCK, .local_version, runtime settings) rather than work pending promotion.
# Set RECONCILE_INCLUDE_UNTRACKED=1 to also classify untracked files (the only
# case where this matters is an untracked file colliding with an upstream-added
# path; expect cruft noise otherwise).
UNTRACKED_FLAG="-uno"
case "${RECONCILE_INCLUDE_UNTRACKED:-0}" in 1 | true | yes) UNTRACKED_FLAG="-uall" ;; esac

CITY="${GC_CITY:-${GC_CITY_ROOT:-.}}"
PACK_DIR_RESOLVED="${PACK_DIR:-${GC_PACK_DIR:-}}"
STATE_DIR="${GC_PACK_STATE_DIR:-${GC_CITY_RUNTIME_DIR:-$CITY/.gc/runtime}/packs/gc-toolkit}"

ALLOWLIST_FILE="${RECONCILE_ALLOWLIST_FILE:-$PACK_DIR_RESOLVED/assets/config/reconcile-rig-checkouts.allowlist}"
LEDGER_DIR="${RECONCILE_LEDGER_DIR:-$STATE_DIR/reconcile-rig-checkouts/ledger}"
STATE_FILE="${RECONCILE_STATE_FILE:-$STATE_DIR/reconcile-rig-checkouts/escalations.json}"

mkdir -p "$LEDGER_DIR" 2>/dev/null || true
mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null || true

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Bound each network fetch so a hung remote cannot stall the controller's order
# slot. Falls back to a plain fetch if `timeout` is unavailable.
FETCH_TIMEOUT="${RECONCILE_FETCH_TIMEOUT:-120}"
do_fetch() {
    if command -v timeout >/dev/null 2>&1; then
        timeout "$FETCH_TIMEOUT" git -C "$1" fetch --quiet origin 2>/dev/null
    else
        git -C "$1" fetch --quiet origin 2>/dev/null
    fi
}

# ---- allowlist ---------------------------------------------------------------

ALLOW_PATTERNS=()
load_allowlist() {
    local line
    if [ -f "$ALLOWLIST_FILE" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            line="${line%%#*}"                       # strip comments
            line="${line#"${line%%[![:space:]]*}"}"  # ltrim
            line="${line%"${line##*[![:space:]]}"}"  # rtrim
            [ -n "$line" ] && ALLOW_PATTERNS+=("$line")
        done <"$ALLOWLIST_FILE"
    fi
    if [ -n "${RECONCILE_ALLOWLIST_EXTRA:-}" ]; then
        local extra="${RECONCILE_ALLOWLIST_EXTRA//:/$'\n'}"
        while IFS= read -r line; do
            line="${line#"${line%%[![:space:]]*}"}"
            line="${line%"${line##*[![:space:]]}"}"
            [ -n "$line" ] && ALLOW_PATTERNS+=("$line")
        done <<<"$extra"
    fi
}

# path_allowlisted PATH -> 0 if matched by any allowlist pattern.
path_allowlisted() {
    local p="${1#./}" pat base
    for pat in "${ALLOW_PATTERNS[@]:-}"; do
        [ -n "$pat" ] || continue
        case "$pat" in
            */\*\*) base="${pat%/\*\*}"; [ "$p" = "$base" ] && return 0; case "$p" in "$base"/*) return 0 ;; esac ;;
            */) base="${pat%/}"; [ "$p" = "$base" ] && return 0; case "$p" in "$base"/*) return 0 ;; esac ;;
            *[\*\?\[]*) [[ $p == $pat ]] && return 0 ;;
            *) [ "$p" = "$pat" ] && return 0; case "$p" in "$pat"/*) return 0 ;; esac ;;
        esac
    done
    return 1
}

# all_paths_allowlisted "<newline paths>" -> 0 iff every non-empty path matches.
all_paths_allowlisted() {
    local p any=1
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        any=0
        path_allowlisted "$p" || return 1
    done <<<"$1"
    return $any  # empty input -> 1 (not "all allowlisted")
}

# ---- escalation state (rig -> bead id), atomic, jq-backed -------------------

STATE='{}'
state_load() {
    STATE="$(cat "$STATE_FILE" 2>/dev/null || true)"
    echo "$STATE" | jq -e 'type == "object"' >/dev/null 2>&1 || STATE='{}'
}
state_persist() {
    local tmp
    tmp="$(mktemp "$(dirname "$STATE_FILE")/.escalations.XXXXXX")" || return 0
    printf '%s\n' "$STATE" >"$tmp" && mv -f "$tmp" "$STATE_FILE"
}
state_get() { echo "$STATE" | jq -r --arg r "$1" '.[$r] // empty' 2>/dev/null; }
state_set() { STATE="$(echo "$STATE" | jq --arg r "$1" --arg v "$2" '.[$r]=$v')"; state_persist; }
state_del() { STATE="$(echo "$STATE" | jq --arg r "$1" 'del(.[$r])')"; state_persist; }

bead_open() {
    local st
    st="$(gc bd show "$1" --json 2>/dev/null | jq -r '.[0].status // empty' 2>/dev/null)"
    case "$st" in open | in_progress | blocked | escalated) return 0 ;; *) return 1 ;; esac
}

# ---- per-rig classification state (reset each rig) ---------------------------

declare -a DEV_JSON          # JSON deviation records for the ledger
declare -a NOVEL_NC_PATHS    # paths of non-conflicting novel work (for advance)
declare -a CONFLICT_LINES    # human-readable conflict rows (for the bead body)
N_KNOWN=0 N_ALREADY=0 N_NOVEL_NC=0 N_CONFLICT=0

reset_rig_state() {
    DEV_JSON=()
    NOVEL_NC_PATHS=()
    CONFLICT_LINES=()
    N_KNOWN=0 N_ALREADY=0 N_NOVEL_NC=0 N_CONFLICT=0
}

# record_dev KIND REF BUCKET "<newline paths>" NOTE
record_dev() {
    local kind="$1" ref="$2" bucket="$3" paths="$4" note="$5" paths_json
    paths_json="$(printf '%s\n' "$paths" | jq -R . | jq -s 'map(select(. != ""))')"
    DEV_JSON+=("$(jq -nc --arg k "$kind" --arg r "$ref" --arg b "$bucket" \
        --argjson p "$paths_json" --arg n "$note" \
        '{kind:$k, ref:$r, bucket:$b, paths:$p, note:$n}')")
    case "$bucket" in
        known) N_KNOWN=$((N_KNOWN + 1)) ;;
        already_upstream) N_ALREADY=$((N_ALREADY + 1)) ;;
        novel_nonconflicting)
            N_NOVEL_NC=$((N_NOVEL_NC + 1))
            while IFS= read -r _p; do [ -n "$_p" ] && NOVEL_NC_PATHS+=("$_p"); done <<<"$paths"
            ;;
        novel_conflict)
            N_CONFLICT=$((N_CONFLICT + 1))
            CONFLICT_LINES+=("$kind $ref :: $(echo "$paths" | tr '\n' ' ')")
            ;;
    esac
}

# A novel set of paths conflicts iff upstream also changed any non-allowlisted
# path since the merge-base (REMOTE:path blob != BASE:path blob). Conservative:
# file-level overlap is treated as a textual conflict — safe (over-blocks to the
# mayor rather than risking silent loss of real work).
paths_conflict() {
    local dir="$1" base="$2" remote="$3" paths="$4" p rb bb
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        path_allowlisted "$p" && continue
        rb="$(git -C "$dir" rev-parse --verify --quiet "$remote:$p" 2>/dev/null || true)"
        bb="$(git -C "$dir" rev-parse --verify --quiet "$base:$p" 2>/dev/null || true)"
        [ "$rb" != "$bb" ] && return 0
    done <<<"$paths"
    return 1
}

# ---- classify one rig --------------------------------------------------------
# Sets: RIG_BRANCH RIG_REMOTE RIG_HEAD RIG_REMOTE_HEAD RIG_BASE RIG_BEHIND
#       RIG_AHEAD RIG_STATUS, plus the per-rig arrays/counters above.
classify_rig() {
    local dir="$1"
    RIG_BRANCH="" RIG_REMOTE="" RIG_HEAD="" RIG_REMOTE_HEAD="" RIG_BASE=""
    RIG_BEHIND=0 RIG_AHEAD=0 RIG_STATUS="error"

    if ! git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
        err "$dir is not a git repository — skipping"
        return 1
    fi
    if ! do_fetch "$dir"; then
        err "fetch origin failed or timed out for $dir — skipping"
        return 1
    fi

    # Resolve the rig's default branch from origin/HEAD; fall back to main.
    local rref
    rref="$(git -C "$dir" symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null || true)"
    if [ -n "$rref" ]; then RIG_BRANCH="${rref#refs/remotes/origin/}"; else RIG_BRANCH="main"; fi
    RIG_REMOTE="origin/$RIG_BRANCH"
    if ! git -C "$dir" rev-parse --verify --quiet "$RIG_REMOTE^{commit}" >/dev/null 2>&1; then
        err "$RIG_REMOTE does not exist in $dir — skipping"
        return 1
    fi

    RIG_HEAD="$(git -C "$dir" rev-parse HEAD 2>/dev/null)"
    RIG_REMOTE_HEAD="$(git -C "$dir" rev-parse "$RIG_REMOTE" 2>/dev/null)"
    RIG_BASE="$(git -C "$dir" merge-base HEAD "$RIG_REMOTE" 2>/dev/null || true)"
    RIG_BEHIND="$(git -C "$dir" rev-list --count "HEAD..$RIG_REMOTE" 2>/dev/null || echo 0)"
    RIG_AHEAD="$(git -C "$dir" rev-list --count "$RIG_REMOTE..HEAD" 2>/dev/null || echo 0)"

    # --- local commits ahead of the remote (origin/main..HEAD) ---
    # `git cherry` marks each with '-' (patch-equivalent already upstream) or '+'.
    local sign sha cpaths bucket
    while read -r sign sha; do
        [ -n "$sha" ] || continue
        cpaths="$(git -C "$dir" diff-tree --no-commit-id --name-only -r "$sha" 2>/dev/null)"
        if [ "$sign" = "-" ]; then
            bucket="already_upstream"
        elif all_paths_allowlisted "$cpaths"; then
            bucket="known"
        elif paths_conflict "$dir" "$RIG_BASE" "$RIG_REMOTE" "$cpaths"; then
            bucket="novel_conflict"
        else
            bucket="novel_nonconflicting"
        fi
        record_dev "commit" "$sha" "$bucket" "$cpaths" ""
    done < <(git -C "$dir" cherry "$RIG_REMOTE" HEAD 2>/dev/null)

    # --- working-tree deviations (dirty hunks, staged, untracked, deletions) ---
    local line xy rest path wt_hash rb bb
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        xy="${line:0:2}"
        rest="${line:3}"
        case "$xy" in
            R* | C*) path="${rest##* -> }" ;;  # rename/copy: classify the new path
            *) path="$rest" ;;
        esac
        # git quotes paths with unusual chars in double quotes; strip them.
        case "$path" in \"*\") path="${path#\"}"; path="${path%\"}" ;; esac
        [ -n "$path" ] || continue

        if path_allowlisted "$path"; then
            record_dev "dirty" "$path" "known" "$path" "$xy"
            continue
        fi
        # A directory entry (submodule, or a symlink-to-dir) has no single blob to
        # compare — never treat it as already-upstream/droppable; flag as novel
        # non-conflicting (its files, if untracked, survive an advance untouched).
        if [ -d "$dir/$path" ] && [ ! -L "$dir/$path" ]; then
            record_dev "dirty" "$path" "novel_nonconflicting" "$path" "$xy"
            continue
        fi
        wt_hash=""
        [ -e "$dir/$path" ] && wt_hash="$(git -C "$dir" hash-object -- "$dir/$path" 2>/dev/null || true)"
        rb="$(git -C "$dir" rev-parse --verify --quiet "$RIG_REMOTE:$path" 2>/dev/null || true)"
        bb="$(git -C "$dir" rev-parse --verify --quiet "$RIG_BASE:$path" 2>/dev/null || true)"
        if [ -n "$rb" ] && [ "$wt_hash" = "$rb" ]; then
            # Working-tree content is already exactly what is on origin/main.
            record_dev "dirty" "$path" "already_upstream" "$path" "$xy"
        elif [ -z "$wt_hash" ] && [ -z "$rb" ]; then
            # Local deletion of a path origin also lacks — no divergence to resolve.
            record_dev "dirty" "$path" "already_upstream" "$path" "$xy"
        elif [ "$rb" != "$bb" ]; then
            # Upstream also touched this path since the merge-base -> conflict.
            record_dev "dirty" "$path" "novel_conflict" "$path" "$xy"
        else
            record_dev "dirty" "$path" "novel_nonconflicting" "$path" "$xy"
        fi
    done < <(git -C "$dir" -c core.quotepath=false status --porcelain=v1 "$UNTRACKED_FLAG" 2>/dev/null)

    # --- decide the rig's status ---
    # An advance is only NEEDED when there is something to pull in (behind>0) or
    # obsolete residue to drop (already-upstream local commits). KNOWN and novel
    # non-conflicting deviations are KEPT in place — they do not require moving
    # HEAD — so a rig already at origin/main that merely carries those is clean
    # (reported, never reset every cycle).
    if [ "$N_CONFLICT" -gt 0 ]; then
        RIG_STATUS="blocked"
    elif [ "$RIG_BEHIND" -eq 0 ] && [ "$N_ALREADY" -eq 0 ]; then
        if [ "${#DEV_JSON[@]}" -eq 0 ]; then
            RIG_STATUS="in_sync"
        else
            RIG_STATUS="synced_with_divergence"  # at origin/main + kept/flagged divergence
        fi
    else
        RIG_STATUS="advanceable"  # may become advanced/blocked below
    fi
    return 0
}

# ---- advance one rig to origin/main (live mode only) -------------------------
# Preserves allowlisted tracked files and non-conflicting novel work; drops
# already-upstream local commits. Returns 0 advanced, 2 reapply failed (treat as
# blocked, checkout reverted), 1 hard failure (checkout untouched).
advance_rig() {
    local dir="$1" remote="$2" pre_sha="$3"
    local snap f
    snap="$(mktemp -d)" || return 1

    # 1. Snapshot working-tree content of tracked allowlisted files (.beads/
    #    config.yaml, metadata.json). Gitignored .beads/* dolt data is untracked
    #    and survives reset --hard untouched, so it needs no snapshot.
    local -a tracked_allow=()
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        if path_allowlisted "$f"; then
            tracked_allow+=("$f")
            if [ -e "$dir/$f" ]; then
                mkdir -p "$snap/allow/$(dirname "$f")"
                cp -p "$dir/$f" "$snap/allow/$f" 2>/dev/null || true
            fi
        fi
    done < <(git -C "$dir" ls-files 2>/dev/null)

    # 2. Capture non-conflicting novel work (committed + tracked-dirty) as a diff
    #    whose pre-image is the remote tree, so it re-applies cleanly post-reset.
    #    Untracked novel files survive reset --hard and need no capture.
    local patch="$snap/novel.patch" have_patch=0
    if [ "${#NOVEL_NC_PATHS[@]}" -gt 0 ]; then
        local -a upaths=()
        while IFS= read -r f; do [ -n "$f" ] && upaths+=("$f"); done \
            < <(printf '%s\n' "${NOVEL_NC_PATHS[@]}" | sort -u)
        if git -C "$dir" diff "$remote" -- "${upaths[@]}" >"$patch" 2>/dev/null && [ -s "$patch" ]; then
            have_patch=1
        fi
    fi

    # 3. Advance HEAD + tracked content to origin/main. Untracked/ignored files
    #    (incl. .beads/ dolt data) are left in place by reset --hard.
    if ! git -C "$dir" reset --hard "$remote" >/dev/null 2>&1; then
        err "advance: reset --hard $remote failed for $dir; checkout left untouched"
        rm -rf "$snap"
        return 1
    fi

    # 4. Restore allowlisted tracked files exactly as bd left them.
    for f in "${tracked_allow[@]:-}"; do
        [ -n "$f" ] || continue
        if [ -e "$snap/allow/$f" ]; then
            mkdir -p "$dir/$(dirname "$f")"
            cp -p "$snap/allow/$f" "$dir/$f" 2>/dev/null || true
        fi
    done

    # 5. Re-apply non-conflicting novel work on top. By construction the patch's
    #    pre-image is the remote tree we just reset to, so it applies cleanly;
    #    if it does not, revert wholesale to pre_sha and signal a block — novel
    #    work is never silently lost.
    if [ "$have_patch" -eq 1 ]; then
        if ! git -C "$dir" apply "$patch" 2>/dev/null; then
            err "advance: re-applying novel work failed for $dir; reverting to $pre_sha"
            git -C "$dir" reset --hard "$pre_sha" >/dev/null 2>&1 || true
            for f in "${tracked_allow[@]:-}"; do
                [ -n "$f" ] || continue
                [ -e "$snap/allow/$f" ] && cp -p "$snap/allow/$f" "$dir/$f" 2>/dev/null || true
            done
            rm -rf "$snap"
            return 2
        fi
    fi
    rm -rf "$snap"
    return 0
}

# ---- ledger ------------------------------------------------------------------

write_ledger() {
    local rig="$1" path="$2" status="$3" pre_sha="$4" ledger_file="$5"
    local devs="[]"
    [ "${#DEV_JSON[@]}" -gt 0 ] && devs="$(printf '%s\n' "${DEV_JSON[@]}" | jq -s .)"
    jq -n \
        --arg rig "$rig" --arg path "$path" --arg branch "$RIG_BRANCH" \
        --arg remote "$RIG_REMOTE" --arg head "$RIG_HEAD" --arg rhead "$RIG_REMOTE_HEAD" \
        --arg base "$RIG_BASE" --argjson behind "${RIG_BEHIND:-0}" --argjson ahead "${RIG_AHEAD:-0}" \
        --arg status "$status" --argjson dry "$([ "$DRY_RUN" -eq 1 ] && echo true || echo false)" \
        --argjson k "$N_KNOWN" --argjson a "$N_ALREADY" --argjson nc "$N_NOVEL_NC" --argjson cf "$N_CONFLICT" \
        --arg pre "$pre_sha" --argjson devs "$devs" --arg now "$NOW" \
        '{
            rig:$rig, path:$path, branch:$branch, remote:$remote,
            head:$head, remote_head:$rhead, merge_base:$base,
            behind:$behind, ahead:$ahead, status:$status, dry_run:$dry,
            counts:{known:$k, already_upstream:$a, novel_nonconflicting:$nc, novel_conflict:$cf},
            pre_advance_sha:(if $pre=="" then null else $pre end),
            deviations:$devs, updated_at:$now
        }' >"$ledger_file" 2>/dev/null || err "failed to write ledger $ledger_file"
}

escalation_body() {
    local rig="$1" path="$2" status="$3" ledger_file="$4" mode="observe"
    [ "$DRY_RUN" -eq 0 ] && mode="enforce"
    {
        echo "Rig checkout '$rig' has NOVEL local work that CONFLICTS with origin/$RIG_BRANCH."
        echo "Reconciliation is BLOCKED — the checkout was NOT mutated (mode: $mode)."
        echo
        echo "Checkout: $path"
        echo "HEAD: ${RIG_HEAD:-?}  origin/$RIG_BRANCH: ${RIG_REMOTE_HEAD:-?}  (behind ${RIG_BEHIND:-?}, ahead ${RIG_AHEAD:-?})"
        echo
        echo "Conflicting deviations (local change collides with an upstream change):"
        local c
        for c in "${CONFLICT_LINES[@]:-}"; do [ -n "$c" ] && echo "  - $c"; done
        echo
        echo "Do NOT blindly reset --hard (that drops the local work) or force-merge"
        echo "(that drops upstream). Reconcile the listed paths by hand, or promote the"
        echo "local work into a PR (docs/gascity-local-patching.md). This bead auto-closes"
        echo "when the rig stops conflicting."
        echo
        echo "Divergence ledger (candidate set for PR-promotion): $ledger_file"
    }
}

manage_escalation() {
    local rig="$1" path="$2" status="$3" ledger_file="$4"
    [ "$ESCALATE" -eq 1 ] || return 0
    local existing body
    existing="$(state_get "$rig")"

    if [ "$status" = "blocked" ]; then
        if [ -n "$existing" ] && bead_open "$existing"; then
            # Refresh WITHOUT appending a note (no per-tick spam): just touch
            # metadata and re-point at the ledger, which carries the live
            # conflict detail. The open bead itself is the durable signal.
            gc bd update "$existing" \
                --set-metadata ledger_path="$ledger_file" \
                --set-metadata rig="$rig" \
                --set-metadata reconcile_last_seen="$NOW" >/dev/null 2>&1 \
                && log "refreshed escalation $existing for $rig"
        else
            local new
            body="$(escalation_body "$rig" "$path" "$status" "$ledger_file")"
            new="$(gc bd create "Reconcile blocked: $rig checkout conflicts with origin/$RIG_BRANCH" \
                -t task --json 2>/dev/null | jq -r '.id // .[0].id // empty' 2>/dev/null)"
            if [ -n "$new" ]; then
                gc bd update "$new" \
                    --assignee "$MAYOR_ADDR" \
                    --set-metadata gc.routed_to="$MAYOR_ADDR" \
                    --set-metadata ledger_path="$ledger_file" \
                    --set-metadata rig="$rig" \
                    --set-metadata reconcile_block=true \
                    --notes "$body" >/dev/null 2>&1
                state_set "$rig" "$new"
                gc session nudge "$MAYOR_ADDR" \
                    "reconcile: $rig checkout blocked on conflicting local work — see $new" >/dev/null 2>&1 || true
                log "filed escalation $new for $rig (owner $MAYOR_ADDR)"
            else
                err "could not create escalation bead for $rig"
            fi
        fi
    else
        # No conflict -> ensure any prior escalation is closed (idempotent).
        if [ -n "$existing" ] && bead_open "$existing"; then
            gc bd close "$existing" \
                --reason "rig $rig no longer conflicts with origin/$RIG_BRANCH (reconciled)" >/dev/null 2>&1 \
                && log "closed escalation $existing for $rig (reconciled)"
        fi
        [ -n "$existing" ] && state_del "$rig"
    fi
}

# ---- main --------------------------------------------------------------------

load_allowlist
state_load

# Enumerate managed rig checkouts: "name=path" per line. HQ is excluded.
RIGS_RAW=""
if [ -n "${RECONCILE_RIGS_OVERRIDE:-}" ]; then
    RIGS_RAW="$RECONCILE_RIGS_OVERRIDE"
else
    RIGS_RAW="$(gc rig list --json 2>/dev/null \
        | jq -r '.rigs[]? | select(.hq != true) | "\(.name)=\(.path)"' 2>/dev/null)"
fi
if [ -z "$RIGS_RAW" ]; then
    log "no managed rig checkouts found — nothing to reconcile"
    exit 0
fi

TOTAL=0 BLOCKED=0 ADVANCED=0 INSYNC=0 ERRORS=0
while IFS='=' read -r rig_name rig_path; do
    [ -n "$rig_name" ] || continue
    [ -n "$rig_path" ] || continue
    TOTAL=$((TOTAL + 1))
    reset_rig_state

    if ! classify_rig "$rig_path"; then
        ERRORS=$((ERRORS + 1))
        continue
    fi

    pre_sha="$RIG_HEAD"
    final_status="$RIG_STATUS"

    if [ "$RIG_STATUS" = "advanceable" ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
            final_status="would_advance"
        else
            advance_rig "$rig_path" "$RIG_REMOTE" "$pre_sha"
            case "$?" in
                0) final_status="advanced" ;;
                2) final_status="blocked"
                    N_CONFLICT=$((N_CONFLICT + 1))
                    CONFLICT_LINES+=("advance reapply failed — novel work could not be preserved on top of $RIG_REMOTE")
                    ;;
                *) final_status="error"; ERRORS=$((ERRORS + 1)) ;;
            esac
        fi
    fi

    ledger_file="$LEDGER_DIR/${rig_name}.json"
    write_ledger "$rig_name" "$rig_path" "$final_status" "$pre_sha" "$ledger_file"
    manage_escalation "$rig_name" "$rig_path" "$final_status" "$ledger_file"

    case "$final_status" in
        blocked) BLOCKED=$((BLOCKED + 1)) ;;
        advanced) ADVANCED=$((ADVANCED + 1)) ;;
        in_sync | synced_with_divergence) INSYNC=$((INSYNC + 1)) ;;
    esac

    log "$rig_name: $final_status (behind=$RIG_BEHIND ahead=$RIG_AHEAD; known=$N_KNOWN already_upstream=$N_ALREADY novel_nc=$N_NOVEL_NC conflict=$N_CONFLICT)"
done <<EOF
$RIGS_RAW
EOF

MODE="$([ "$DRY_RUN" -eq 1 ] && echo dry-run || echo enforce)"
log "done ($MODE): $TOTAL rigs — $INSYNC in-sync, $ADVANCED advanced, $BLOCKED blocked, $ERRORS errors"
exit 0
