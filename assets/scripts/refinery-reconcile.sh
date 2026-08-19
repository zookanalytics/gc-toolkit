#!/usr/bin/env bash
# refinery-reconcile.sh — ONE reconcile pass over one rig's refinery merge
# queue. Driven by orders/refinery-reconcile.toml (trigger = cooldown,
# scope = "rig"), which is what supplies the cadence (tk-d83wm).
#
# WHAT THIS REPLACES. The merge cadence used to be a hand-authored daemon:
# /tmp/gc-refinery-idle-<rig>/idle-loop.sh, one per rig, armed into a transient
# `systemd --user` unit by assets/scripts/refinery-idle-arm.sh. That daemon ran
# the same passes this script runs, wrapped in `while true; sleep 60; done`.
# It sat outside the city entirely — `gc` shutting down did not stop it, `gc
# status` did not show it, city.toml did not declare it, and a host reboot took
# all four rigs' copies with it (measured 2026-08-19: 07:05 -> 07:52, ~47min,
# four rigs at once, invisible to `gc doctor` by construction because a
# post-hoc probe cannot distinguish "never went down" from "came back").
#
# WHAT IS DIFFERENT NOW. Everything the daemon hand-built, the order runner
# already provides, and provides better:
#
#   * The LOOP and the SLEEP are the `cooldown` trigger. There is no loop here.
#     This script runs one pass and exits; the controller calls it again.
#   * The FLOCK is the controller's open-tracking gate. A cooldown order whose
#     previous run has not finished is skipped, not re-dispatched: the tracking
#     bead is created synchronously before the run and closed in a `defer`
#     after it (cmd/gc/order_dispatch.go dispatchOne), and the first dispatch
#     gate reads exactly that. The gate keys on ScopedName() — `<order>:rig:<rig>`
#     — so each rig gets its own single-flight without sharing one with its
#     co-tenants. That is the two-merge-skill-writers guarantee the canonical
#     lock existed to give, enforced one level up.
#   * The WORKING DIRECTORY is `target.ScopeRoot`, i.e. this rig's own root.
#     No `--working-directory` to forget: merge-skill.sh's `git remote get-url
#     origin` resolves because the runner put us in a work tree.
#   * The ENVIRONMENT is built by orderExecEnvWithError: GC_RIG, GC_RIG_ROOT,
#     BEADS_DIR, GC_BEADS_PREFIX, PACK_DIR, GC_PACK_STATE_DIR, the canonical
#     Dolt projection, and the controller's `gh` token. No `--setenv` to forget,
#     and no inherited-shell dependency at all.
#   * The CGROUP problem is gone. There is no long-lived process to keep alive
#     outside an agent session, so there is nothing for a session rotation to
#     SIGKILL and nothing to re-arm.
#
# The full history of the daemon — the four liveness signals that look right and
# are not, the measured outages, why `setsid` did not help — is in
# specs/tk-agzpl/refinery-idle-driver-liveness.md. It is kept as history: every
# failure it catalogues is a property of running a driver the controller cannot
# see, and none of them can recur through this path.
#
# NOT set -e: best-effort by contract. Each pass is independent, a failing pass
# must not skip the passes after it, and the next cooldown retries everything.
# No pipefail either — several arms grep for optional markers, and a no-match
# must not abort the pass.
set -u

PROG="refinery-reconcile"

# --- identity ----------------------------------------------------------------
# GC_RIG is set by the order runner for every rig-scoped order (see
# orderExecEnvWithError; it is a controller-owned key an order's [order.env]
# cannot override). Without it there is no rig to reconcile and no safe guess:
# picking one would run a rig's merge writer against another rig's store.
RIG="${GC_RIG:-}"
if [ -z "$RIG" ]; then
    echo "$PROG: GC_RIG is unset — this script runs as a scope=\"rig\" order and has no rig to reconcile" >&2
    exit 2
fi

# This rig's own checkout. The runner already made it our cwd; naming it
# explicitly keeps the git-facing reads correct if that ever changes.
RIG_ROOT="${GC_RIG_ROOT:-$PWD}"

# The reconcile scripts are this script's own siblings. Resolving from $0 rather
# than from GC_RIG_ROOT is what makes one copy serve every rig: the pack lives
# under the OWNING rig (all four rigs import "source = rigs/gc-toolkit"), so an
# importer rig's own root has no assets/scripts at all.
SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

# --- the refinery identity and its sibling pools ------------------------------
# Three addresses are needed: the refinery itself (handoff-address recovery,
# check-set heal) and the two polecat pools the heal and observer passes route
# rework and re-review children to. All three share one binding prefix, so they
# are derived TOGETHER from the resolved refinery address — deriving them
# separately is how a rename produces a script that repairs beads for one
# identity and dispatches children to another.
#
# Discovery beats a hardcoded prefix: `{{binding_prefix}}` is a formula var this
# script has no channel to, and its formula default is empty while every rig on
# this host binds "gc-toolkit.". Fall back to the pack name, which IS the import
# binding for a pack imported under its own name.
resolve_refinery() {
    local found
    found="$(gc agent list --json 2>/dev/null \
        | jq -r --arg rig "$RIG" '
            .agents[]?
            | .qualified_name // empty
            | select(startswith($rig + "/"))
            | select(endswith("refinery"))' 2>/dev/null | head -1)"
    if [ -n "$found" ]; then printf '%s' "$found"; return 0; fi
    if [ -n "${GC_PACK_NAME:-}" ]; then printf '%s/%s.refinery' "$RIG" "$GC_PACK_NAME"; return 0; fi
    return 1
}

AGENT="${REFINERY_RECONCILE_AGENT:-$(resolve_refinery)}"
if [ -z "$AGENT" ]; then
    echo "${PROG}[$RIG]: no refinery agent bound for this rig; nothing to reconcile"
    exit 0
fi

# "<rig>/<prefix>refinery" -> "<prefix>". An unbound agent ("<rig>/refinery")
# yields an empty prefix, which is the correct address for that rig.
BINDING_PREFIX="${AGENT#"$RIG"/}"
BINDING_PREFIX="${BINDING_PREFIX%refinery}"
FIX_POOL="$RIG/${BINDING_PREFIX}polecat"
REVIEW_POOL="$RIG/${BINDING_PREFIX}polecat-codex"

# Merge gating check-set default, and the convoy graduation kill-switch. Both
# mirror mol-refinery-patrol vars of the same name; set them in [order.env] to
# diverge from the formula's defaults.
CHECK_SET_DEFAULT="${REFINERY_RECONCILE_CHECK_SET:-codex}"
INTEGRATION_AUTO_LAND="${REFINERY_RECONCILE_INTEGRATION_AUTO_LAND:-true}"

# The branch a graduated integration convoy lands onto. Derived from THIS rig's
# own origin/HEAD, not from a shared constant: one `[order.env]` serves all four
# registrations of a scope="rig" order, so a hardcoded target would be exactly
# the per-rig drift this script exists to remove. The old per-rig drivers each
# hardcoded `main`, which is what every rig here resolves to anyway — so an
# unset or unreadable origin/HEAD falls back to it rather than guessing.
TARGET="${REFINERY_RECONCILE_TARGET:-}"
if [ -z "$TARGET" ]; then
    TARGET="$(git -C "$RIG_ROOT" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)"
    TARGET="${TARGET#origin/}"
fi
[ -n "$TARGET" ] || TARGET=main

# --- the state dir, WHICH MUST BE PER RIG -------------------------------------
# GC_PACK_STATE_DIR is CITY+PACK scoped (citylayout.PackStateDir) but this order
# runs once per importing rig, so an unkeyed path is SHARED: the handoff dedup
# below would suppress one rig's fresh handoff because a different rig had
# already seen a bead with that id. Keyed exactly as
# liveness-sweep-precheck.sh keys its window, and for the same reason.
state_key() { # readable identity
    local readable="$1" identity="$2" safe
    safe="$(printf '%s' "$readable" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_')"
    case "$safe" in ''|.|..) safe=rig ;; esac
    if [ "$safe" = "$readable" ] && [ "$readable" = "$identity" ] && [ "${#safe}" -le 64 ]; then
        printf '%s' "$safe"
    else
        printf '%s-%s' "${safe:0:64}" "$(printf '%s' "$identity" | cksum | cut -d' ' -f1)"
    fi
}
RIG_KEY="$(state_key "$RIG" "$RIG")"
DEFAULT_STATE_DIR="${GC_PACK_STATE_DIR:-${TMPDIR:-/tmp}/gc}"
STATE_BASE="${REFINERY_RECONCILE_STATE_DIR:-$DEFAULT_STATE_DIR/refinery-reconcile}"
STATE_DIR="$STATE_BASE/$RIG_KEY"
LOG="$STATE_DIR/pass.log"
SEEN="$STATE_DIR/handoff.seen"
LOG_KEEP="${REFINERY_RECONCILE_LOG_KEEP:-2000}"

mkdir -p "$STATE_DIR" 2>/dev/null || true
PASS_OUT="$(mktemp "${TMPDIR:-/tmp}/$PROG.XXXXXX")" || PASS_OUT=""
# Reached through the EXIT trap, not by any call site a linter can see.
# shellcheck disable=SC2329
cleanup() { [ -n "$PASS_OUT" ] && rm -f "$PASS_OUT"; return 0; }
trap cleanup EXIT

TICK="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
FAILED=""
NOTED=""

# >>> heal-gates-merge
# The region below is EXTRACTED VERBATIM by check-set-heal.test.sh (run 6) and
# executed against the real check-set-heal.sh with a merge-skill stub, to prove
# that an unsafe heal HOLDS the merge in the same pass. It must stay executable
# with only a prologue supplying SCRIPTS_DIR, PASS_OUT, NOTED, FAILED, AGENT,
# CHECK_SET_DEFAULT, REVIEW_POOL and FIX_POOL — so keep it free of anything the
# rest of this file computes, and move the markers if the arms move.
note() { NOTED="${NOTED}$*"$'\n'; }
log()  { [ -n "$PASS_OUT" ] && printf '%s\n' "$*" >> "$PASS_OUT"; return 0; }

# Run one pass, capturing its output into the pass log. `label` names it in the
# failure summary; every rc other than the ones a caller declares OK becomes a
# recorded failure. Missing/non-executable scripts are skipped silently: the
# pass set has grown over time and an older pack copy legitimately lacks the
# newer arms.
run_pass() { # label script [args...]
    local label="$1" script="$2"; shift 2
    if [ ! -x "$SCRIPTS_DIR/$script" ]; then
        log "-- $label: SKIPPED (no $SCRIPTS_DIR/$script)"
        return 0
    fi
    log "-- $label"
    local rc=0
    if [ -n "$PASS_OUT" ]; then
        "$SCRIPTS_DIR/$script" "$@" >> "$PASS_OUT" 2>&1 || rc=$?
    else
        "$SCRIPTS_DIR/$script" "$@" >/dev/null 2>&1 || rc=$?
    fi
    return "$rc"
}

# --- the pass set, in order ---------------------------------------------------
# Order is load-bearing and is the formula's (mol-refinery-patrol, find-work).
# Each pass's rationale lives in that step; this is the caller, not the spec.

# (a-addr) Near-miss handoff ADDRESS recovery. FIRST, because it is the only
# pass that can make a bead visible to everything below: a handoff routed to a
# non-canonical "<rig>/refinery" carries no merge_result and is invisible to
# every bead-keyed pass at once.
run_pass "(a-addr) reconcile-refinery-handoffs" reconcile-refinery-handoffs.sh \
    --refinery "$AGENT" \
    || FAILED="${FAILED}reconcile-refinery-handoffs rc=$?; "

# (a-norm) Check-set normalization. GATES the merge skill THIS pass: rc=3 means
# the heal could not establish a safe gating picture, and landing anything on
# that reading is exactly the unreviewed-merge this pass exists to prevent.
# rc=3 is a designed HOLD, not a fault — it is reported but does not fail the
# order, or an approval-gated queue would raise order.failed every cooldown.
HEAL_UNSAFE_RC=3
MERGE_SKILL_HELD=0
heal_rc=0
run_pass "(a-norm) check-set-heal" check-set-heal.sh \
    --default "$CHECK_SET_DEFAULT" \
    --review-pool "$REVIEW_POOL" \
    --fix-pool "$FIX_POOL" \
    --refinery "$AGENT" || heal_rc=$?
if [ "$heal_rc" = "$HEAL_UNSAFE_RC" ]; then
    MERGE_SKILL_HELD=1
    note "check-set-heal UNSAFE (rc=$heal_rc) — merge-skill HELD this pass"
elif [ "$heal_rc" != 0 ]; then
    FAILED="${FAILED}check-set-heal rc=$heal_rc; "
fi

# (a-pre) Pre-open PR-create resolver — opens the PR for each anchor parked in
# pre_open_gate whose codex signoff is green at the branch head.
run_pass "(a-pre) pre-open-resolve" pre-open-resolve.sh \
    || FAILED="${FAILED}pre-open-resolve rc=$?; "

# (a0) The merge skill — the single writer of merged truth.
if [ "$MERGE_SKILL_HELD" = 1 ]; then
    log "-- (a0) merge-skill: HELD this pass (check-set-heal unsafe)"
else
    run_pass "(a0) merge-skill" merge-skill.sh \
        || FAILED="${FAILED}merge-skill rc=$?; "
fi

# <<< heal-gates-merge

# (a1) Close-on-land observer (detect-only).
run_pass "(a1) reconcile-merged-prs" reconcile-merged-prs.sh \
    --fix-pool "$FIX_POOL" \
    --review-pool "$REVIEW_POOL" \
    || FAILED="${FAILED}reconcile-merged-prs rc=$?; "

# (a2) Merge-gate verdict arm — records exception/fixable verdicts so a gate
# that can never go green says so instead of holding silently forever.
run_pass "(a2) reconcile-gate-verdicts" reconcile-gate-verdicts.sh \
    || FAILED="${FAILED}reconcile-gate-verdicts rc=$?; "

# (b) Convoy graduation. Runs AFTER (a1), so the pass that closes a convoy's
# last merged child graduates the now-complete convoy on the same tick.
if [ "$INTEGRATION_AUTO_LAND" = "false" ]; then
    log "-- (b) reconcile-graduated-convoys: DISABLED (integration_auto_land=false)"
else
    # GC_AGENT is projected for THIS pass only, in a subshell.
    #
    # Why it is needed: core's order exec env (orderExecEnvWithError) supplies
    # BEADS_ACTOR, GC_RIG, GC_RIG_ROOT and BEADS_DIR but NOT GC_AGENT, and
    # reconcile-graduated-convoys.sh refuses to act without an identity — it
    # exits 0 with "GC_AGENT unset; skip" (:111) rather than strand a convoy
    # bead at assignee="", well before the assignment at :427. Under the order
    # that early exit is silent AND rc=0, so the cadence reported a healthy
    # queue every tick while owned integration convoys never graduated at all.
    #
    # Why it is NOT exported process-wide: reconcile-refinery-handoffs.sh
    # (:415) suppresses its "wake the refinery" nudge when GC_AGENT is already
    # the refinery, reasoning that the refinery's own idle loop re-checks
    # find-work in the same cycle. recover-stranded-branches.sh (:855) shares
    # the shape. That is an AGENT-SESSION premise, and it is false here: this
    # order is the session-less cadence that REPLACED that idle loop, so there
    # is no find-work re-check to fall back on. A process-wide export would fix
    # graduation and simultaneously silence those nudges, leaving a recovered
    # handoff to wake nobody. Scope the identity to the pass that consumes it.
    ( export GC_AGENT="$AGENT"
      run_pass "(b) reconcile-graduated-convoys" reconcile-graduated-convoys.sh \
          --target "$TARGET" ) \
        || FAILED="${FAILED}reconcile-graduated-convoys rc=$?; "
fi

# --- fresh-handoff detector (mail-loss fallback) ------------------------------
# Every pass above enumerates ANCHORED beads (merge_result set). A handoff whose
# MERGE_READY nudge was lost carries metadata.branch and no merge_result, so it
# is invisible to all of them — the queue reads healthy while a pushed branch
# waits. Report it once per bead id.
#
# Gate on the branch EXISTING ON ORIGIN: a bead carries metadata.branch from the
# moment a polecat claims it, long before anything is pushed, so "has branch"
# alone reports live in-flight work as a lost handoff.
HANDOFF_ROWS="$(gc bd list --rig="$RIG" --status=open --exclude-type=epic \
        --has-metadata-key=branch --limit=400 --json 2>/dev/null \
    | tr -d '\000-\010\013\014\016-\037' \
    | jq -r --arg me "$AGENT" '
        .[]?
        | select((.metadata.branch // "") != "")
        | select((.metadata.merge_result // "") as $mr
                 | (["pull_request","pre_open_gate","merged","abandoned","retargeted"]
                    | index($mr)) | not)
        | select(((.metadata["gc.routed_to"] // "") == $me)
                 or (((.metadata["gc.routed_to"] // "") == "") and ((.assignee // "") == "")))
        | "\(.id)\t\(.metadata.branch)"' 2>/dev/null | sort -u)"

HANDOFF=""
while IFS=$'\t' read -r hid hbr; do
    [ -n "$hid" ] && [ -n "$hbr" ] || continue
    if git -C "$RIG_ROOT" ls-remote --exit-code origin "refs/heads/$hbr" >/dev/null 2>&1; then
        HANDOFF="${HANDOFF}${hid}"$'\n'
    fi
done <<HANDOFF_EOF
$HANDOFF_ROWS
HANDOFF_EOF

HANDOFF="$(printf '%s' "$HANDOFF" | sed '/^$/d' | sort -u)"
[ -f "$SEEN" ] || : > "$SEEN" 2>/dev/null || true
NEW_HANDOFF="$(printf '%s\n' "$HANDOFF" | sed '/^$/d' | grep -vxF -f "$SEEN" 2>/dev/null | paste -sd, -)"
printf '%s\n' "$HANDOFF" | sed '/^$/d' > "$SEEN" 2>/dev/null || true
if [ -n "$NEW_HANDOFF" ]; then
    note "FRESH HANDOFF (branch pushed, no anchor): $NEW_HANDOFF"
fi

# --- report -------------------------------------------------------------------
# The controller keeps this pass's combined output only when the command exits
# non-zero (it folds a bounded tail into the order.failed event). So the log is
# where a healthy pass is readable, and the exit code is the alarm.
{
    printf '=== %s rig=%s refinery=%s\n' "$TICK" "$RIG" "$AGENT"
    [ -n "$PASS_OUT" ] && cat "$PASS_OUT"
    [ -n "$NOTED" ] && printf '%s' "$NOTED"
    [ -n "$FAILED" ] && printf 'FAILED: %s\n' "$FAILED"
} >> "$LOG" 2>/dev/null || true
if [ -w "$LOG" ]; then
    tail -n "$LOG_KEEP" "$LOG" > "$LOG.trim" 2>/dev/null && mv "$LOG.trim" "$LOG" 2>/dev/null
fi

[ -n "$NOTED" ] && printf '%s' "$NOTED"

if [ -n "$FAILED" ]; then
    echo "${PROG}[$RIG]: $FAILED"
    echo "${PROG}[$RIG]: pass log: $LOG"
    exit 1
fi
exit 0
