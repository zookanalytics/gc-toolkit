#!/usr/bin/env bash
# dispatch-feeder.sh — convert ready work into an armed dispatch, so the
# deferred-dispatch pipeline has an input.
#
# THE PROBLEM (tk-ku1uvv). The city ships a complete deferred-dispatch
# pipeline: `deferred-dispatch.sh arm` writes a pending dispatch onto a bead,
# and orders/deferred-dispatch.toml performs the sling the moment bd reports
# that bead ready. Both halves work. Nothing ever calls `arm`.
#
# Measured in the gc-toolkit store on 2026-08-24: 252 ready work beads, all
# unrouted; 147 of them (58%) older than a week; 51 older than 30 days; the
# oldest, tk-1co, 123 days. `deferred-dispatch.sh list` reported "no pending
# dispatches in this store" throughout — zero owed, nothing queued to fire.
# core.control-dispatcher and the polecat pools were ACTIVE on all four rigs
# the whole time. This was never a dead-actor outage. The machine ran; the
# hopper was empty.
#
# The governing operator ruling (tk-jr8rw, recorded standing as tk-nv0z5m):
# "why are we asking to fund? We are a city intended to get work done, if it
# needs to be slung, sling it."
#
# THE FIX, AND WHAT IT DELIBERATELY IS NOT. This is a FEEDER for the pipeline
# that already exists, not a second dispatch path. It selects ready, unrouted
# work and calls the shipped `arm` verb; the existing reconcile pass is what
# slings. That matters beyond tidiness: `arm` is itself fail-closed (it refuses
# a closed bead, an already-dispatched bead, a bead with no target) and
# reconcile adds the assignee and already-routed guards on top. Calling `gc
# sling` from here would bypass both layers and re-implement a dispatcher that
# already exists and is already tested. doctor/check-deferred-dispatch-wired
# asserts this script calls `arm` and never `gc sling`.
#
# OLDEST FIRST. Candidates are ordered by created_at ascending, so the 31d+
# tail drains instead of starving behind every fresh arrival. A newest-first or
# priority-first feeder would leave exactly the beads that motivated this file
# untouched forever, which is the failure it exists to end.
#
# BOUNDED BY CONSTRUCTION, NOT BY INSTRUCTION. An unbounded feeder over a
# 252-deep queue is a spend incident, not a fix. Two caps, both enforced here
# rather than asked of a caller:
#
#   * DISPATCH_FEEDER_MAX_IN_FLIGHT (default 2) — how many beads this feeder
#     may have auto-armed and still open at once, per rig. It matches the
#     polecat pool ceiling of 2/rig, so the feeder can never commit more work
#     than the pool can actually execute. Four rigs x 2 = 8 city-wide, which is
#     the ceiling that already exists.
#   * DISPATCH_FEEDER_MAX_PER_TICK (default 1) — how many arms one pass may
#     write, so a cold start cannot empty half the queue into the pool in one
#     tick even if the in-flight cap were raised.
#
# DISPATCH_FEEDER_ENABLED (default 1) turns the whole thing off. All three are
# `[order.env]` defaults in orders/dispatch-feeder.toml and are overridable
# from city.toml with `[[orders.overrides]]` + `[orders.overrides.env]`, so
# tooling spend stays a mechanical knob the operator turns without a pack
# change — consistent with the 2026-08-20..23 spend controls (gated
# feedback-distiller, liveness-sweep 6h->24h, feedback-miner 24h->48h).
#
# FAIL CLOSED, ALWAYS. Every read is checked and every read failure exits
# non-zero having armed nothing. Two of them matter especially:
#
#   * An unreadable candidate listing must never print a summary that reads
#     like a healthy quiet pass. That fail-open is the exact class of defect
#     this whole mechanism exists against — see deferred-dispatch.sh.
#   * An unreadable IN-FLIGHT count must never be treated as zero in flight.
#     Reading a broken count as 0 does not merely under-report: it hands the
#     pass a full budget and blows the cap, which is the one failure that
#     turns this file into the spend incident it was written to avoid.
#
# NOT set -e: per-bead, best-effort by contract, exactly like its sibling. One
# bead that cannot be armed must not skip the beads after it.
set -u

PROG="dispatch-feeder"

# --- the vocabulary ----------------------------------------------------------
# Our own marker, distinct from deferred-dispatch's gc.dispatch_when_ready*
# keys. It has to be: reconcile CLEARS those keys the moment it slings, so
# counting them would show every dispatched bead dropping out of the in-flight
# tally within one 2m tick and the cap would bind on nothing. This marker
# survives the arm being consumed and is what makes the cap mean "work I put
# into the pipeline that has not finished", which is the quantity worth
# capping.
K_AUTO_BY="gc.auto_armed_by"
K_AUTO_AT="gc.auto_armed_at"

# deferred-dispatch's own key, gc.dispatch_when_ready, is read here too — but
# only from inside the jq exclusion filter below, where it is spelled literally
# alongside every other excluded marker. Hoisting it to a variable here would
# put one of that filter's dozen keys somewhere different from the other eleven.

BD_DB=""          # optional --db passthrough; otherwise BEADS_DIR pins the rig
DRY_RUN=0

TMPFILES=()
cleanup() { [ "${#TMPFILES[@]}" -gt 0 ] && rm -f "${TMPFILES[@]}"; return 0; }
trap cleanup EXIT
mktemp_tracked() { local f; f="$(mktemp)" || return 1; TMPFILES+=("$f"); printf '%s' "$f"; }

bd_() {
    if [ -n "$BD_DB" ]; then bd --db "$BD_DB" "$@"; else bd "$@"; fi
}

now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# The sibling script. Resolved next to this one so a pack copied or relocated
# whole still finds it; fail-closed if it is absent, because arming through
# anything else would be the second dispatch path this file refuses to be.
# DISPATCH_FEEDER_ARM_TOOL is a TEST SEAM, not an operator knob — it is not in
# the order's [order.env] and not in the usage text, and pointing it anywhere
# but the shipped deferred-dispatch.sh defeats the whole design.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARM_TOOL="${DISPATCH_FEEDER_ARM_TOOL:-$HERE/deferred-dispatch.sh}"

# --- knobs -------------------------------------------------------------------
# Defaults live here AND in orders/dispatch-feeder.toml's [order.env]. The
# duplication is deliberate: the order file is where an operator reads them,
# and these are what protect a hand-run of the script.
# Every knob below is read with `${VAR-default}`, NOT `${VAR:-default}`. The colon
# form treats an explicitly-empty override as unset and silently restores the
# default, which is indistinguishable from the override having worked — and the
# first thing anyone does with a spend knob is lower it. With the bare form an
# empty value survives to the validation below and is refused out loud.
ENABLED="${DISPATCH_FEEDER_ENABLED-1}"
MAX_IN_FLIGHT="${DISPATCH_FEEDER_MAX_IN_FLIGHT-2}"
MAX_PER_TICK="${DISPATCH_FEEDER_MAX_PER_TICK-1}"
# `${GC_RIG:+$GC_RIG/}` is the pack's rig-qualification idiom: bare outside a
# rig, `<rig>/` inside one. The pool name keeps the pack prefix in every
# importing rig — signal-loom's polecats are `signal-loom/gc-toolkit.polecat`.
TARGET="${DISPATCH_FEEDER_TARGET-${GC_RIG:+$GC_RIG/}gc-toolkit.polecat}"

# Three-way, never two. An unrecognised enable flag is neither on nor off: a
# spend switch that guesses is one an operator cannot trust they have thrown.
enabled_state() {
    case "$(printf '%s' "$ENABLED" | tr '[:upper:]' '[:lower:]')" in
        1|true|yes|on)  printf 'on' ;;
        0|false|no|off) printf 'off' ;;
        *)              printf 'invalid' ;;
    esac
}

# A cap that cannot be parsed is not a cap. Refuse rather than fall back to a
# default an operator believes they have overridden — a typo'd
# `DISPATCH_FEEDER_MAX_IN_FLIGHT="two"` silently restoring 2 would be
# indistinguishable from the override working.
positive_int() { case "$1" in ''|*[!0-9]*) return 1 ;; *) [ "$1" -ge 0 ] ;; esac; }

usage() {
    cat <<'EOF'
Usage:
  dispatch-feeder.sh feed   [--dry-run] [--db <path>]
  dispatch-feeder.sh status [--db <path>]

Verbs:
  feed    One pass: arm the oldest ready, unrouted, un-held work beads for
          dispatch, up to the in-flight and per-tick caps. Driven by
          orders/dispatch-feeder.toml (cooldown, scope="rig").
  status  Report the caps, what this feeder has in flight, and how deep the
          candidate queue is. Reads only; writes nothing.

Environment (defaults also set in orders/dispatch-feeder.toml [order.env],
overridable from city.toml via [[orders.overrides]] + [orders.overrides.env]):
  DISPATCH_FEEDER_ENABLED        1 | 0    (default 1)
  DISPATCH_FEEDER_MAX_IN_FLIGHT  integer  (default 2)
  DISPATCH_FEEDER_MAX_PER_TICK   integer  (default 1)
  DISPATCH_FEEDER_TARGET         agent    (default <rig>/gc-toolkit.polecat)
EOF
}

# --- readers -----------------------------------------------------------------
# bd can emit control characters into --json that kill jq (see
# deferred-dispatch.sh show_bead). Strip them everywhere a listing is parsed,
# preserving tab (011), LF (012) and CR (015).
strip_ctl() { tr -d '\000-\010\013\014\016-\037'; }

# How many beads this feeder has auto-armed that have not finished.
#
# `--all` then filter on status in jq, rather than narrowing server-side with
# an explicit `--status open,in_progress,...`: this number is a SAFETY bound,
# and an enumerated status list fails OPEN. Anything not closed is in flight —
# open, in_progress, blocked, deferred alike, plus any status bd grows later —
# and a status missing from a hand-written list would silently drop beads out
# of the tally and let the pass arm past the cap. A blocked auto-armed bead is
# still capacity this feeder committed.
#
# The accepted cost is that the marker outlives the work, so this listing grows
# by roughly (arms per day) rows per day and is never pruned. At the shipped
# caps that is ~48 rows/rig/day. It is a read of ids and statuses once per 10
# minutes, so the growth is affordable for a long time, and the alternative —
# pruning the marker on close — would need a writer that runs when a bead
# closes, which does not exist. Fail-closed accounting is worth the read.
inflight_count() { # -> count on stdout, rc 1 if it could not be determined
    local raw n
    raw="$(bd_ list --has-metadata-key "$K_AUTO_BY" --all --json --limit 0 2>/dev/null)" || return 1
    [ -n "$raw" ] || return 1
    printf '%s' "$raw" | strip_ctl | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
    n="$(printf '%s' "$raw" | strip_ctl | jq -r '[ .[] | select((.status // "") != "closed") ] | length' 2>/dev/null)" || return 1
    positive_int "$n" || return 1
    printf '%s' "$n"
}

# Candidates: ready, unrouted, unheld, un-armed implementation work, oldest
# first.
#
# Readiness is NOT re-implemented. `bd list --ready` applies beads' own
# predicate — open, no active blocker of a blocking type, not in_progress /
# blocked / deferred / hooked, parent-child blocked-flag cascade included.
# Asking bd is what keeps this from drifting away from the predicate every
# other reader uses, and it is the same read deferred-dispatch.sh makes.
#
# Everything below it is an EXCLUSION, and each one is a thing that must not be
# auto-slung. Measured against the live gc-toolkit ready listing (330 beads) on
# 2026-08-24, these remove 188 and leave 142 real candidates:
#
#   type allow-list   epics (6) and convoys (40) decompose into work, they are
#                     not work; specs (21), decisions (6) and events (1) are
#                     records, not assignments. Wisps never appear at all —
#                     they need --include-infra, which is deliberately not
#                     passed.
#   graph.v2 markers  67 of the 330 are formula STEP beads. Arming one pours a
#                     workflow onto a bead that is already inside a workflow.
#                     This is the single most destructive thing the feeder
#                     could do, so it is excluded three ways.
#   gc.kind           graph.v2's own descriptor beads (spec, scope-check) are
#                     ready and unroutable by construction. Any value at all is
#                     excluded: an unrecognised kind must read as "machinery",
#                     never as "ordinary work".
#   routed            already dispatched. Tested by VALUE, not presence: the
#                     polecat done sequence sets gc.routed_to="" to mean
#                     unrouted, and that empty value round-trips.
#   armed             deferred-dispatch already owes a dispatch on it.
#   takeaway / hold   deliberate operator holds. By value, matching how
#                     detect-stalled-workflows.sh reads the same two markers.
#   assignee          somebody has it. reconcile refuses to sling over a held
#                     bead anyway, so arming one would only mint an arm that
#                     can never fire.
#   task_kind         absent or "implementation" only. A DENY-by-default
#                     allow-list: review, doc-update, feedback-pattern,
#                     triage-subject and design beads are each dispatched by
#                     their own machinery, and a task_kind invented next month
#                     must not become auto-slingable by default.
#   hold:* labels     the same holds the startup hook refuses to claim past.
candidate_rows() { # writes "<id>\t<created_at>\t<type>" oldest-first to $1
    local out="$1" raw
    raw="$(bd_ list --ready --json --limit 0 2>/dev/null)" || return 1
    [ -n "$raw" ] || return 1
    printf '%s' "$raw" | strip_ctl | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
    printf '%s' "$raw" | strip_ctl | jq -r '
        [ .[]
          | . as $b
          | (.metadata // {}) as $m
          | select(["task","bug","feature","chore"] | index($b.issue_type // ""))
          | select(($b.assignee // "") == "")
          | select(($m["gc.step_ref"] // "") == "")
          | select(($m["gc.step_id"] // "") == "")
          | select(($m["gc.root_bead_id"] // "") == "")
          | select(($m["gc.kind"] // "") == "")
          | select(($m["gc.routed_to"] // "") == "")
          | select(($m["gc.execution_routed_to"] // "") == "")
          | select(($m["gc.dispatch_when_ready"] // "") == "")
          | select(($m["gc.takeaway"] // "") == "")
          | select(($m["triage.hold"] // "") == "")
          | select(($m["task_kind"] // "implementation") == "implementation")
          | select([ ($b.labels // [])[] | select(startswith("hold:")) ] | length == 0)
        ]
        | sort_by((.created_at // ""), .id)
        | .[] | [ .id, (.created_at // ""), (.issue_type // "") ] | @tsv' > "$out" 2>/dev/null || return 1
    return 0
}

# --- feed --------------------------------------------------------------------
mark_reserved() { # id -> rc.  Stamped BEFORE the arm; see cmd_feed.
    bd_ update "$1" \
        --set-metadata "$K_AUTO_BY=$PROG" \
        --set-metadata "$K_AUTO_AT=$(now_utc)" >/dev/null 2>&1
}

release_reserved() { # id -> rc
    bd_ update "$1" \
        --unset-metadata "$K_AUTO_BY" \
        --unset-metadata "$K_AUTO_AT" >/dev/null 2>&1
}

cmd_feed() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run) DRY_RUN=1 ;;
            --db) shift; BD_DB="${1:-}" ;;
            *) echo "$PROG: feed: unknown flag '$1'" >&2; return 2 ;;
        esac
        shift || true
    done

    case "$(enabled_state)" in
        off)
            echo "$PROG: disabled (DISPATCH_FEEDER_ENABLED=$ENABLED) — arming nothing; hand-slung work and hand-written arms are unaffected"
            return 0 ;;
        invalid)
            echo "$PROG: DISPATCH_FEEDER_ENABLED='$ENABLED' is neither on (1/true/yes/on) nor off (0/false/no/off) — refusing rather than guessing which way an operator meant to throw a spend switch" >&2
            return 2 ;;
    esac
    positive_int "$MAX_IN_FLIGHT" || {
        echo "$PROG: DISPATCH_FEEDER_MAX_IN_FLIGHT='$MAX_IN_FLIGHT' is not a non-negative integer — refusing to run uncapped" >&2; return 2; }
    positive_int "$MAX_PER_TICK" || {
        echo "$PROG: DISPATCH_FEEDER_MAX_PER_TICK='$MAX_PER_TICK' is not a non-negative integer — refusing to run uncapped" >&2; return 2; }
    [ -n "$TARGET" ] || {
        echo "$PROG: DISPATCH_FEEDER_TARGET is empty — refusing to arm a dispatch with no destination" >&2; return 2; }
    [ -x "$ARM_TOOL" ] || {
        echo "$PROG: $ARM_TOOL is missing or not executable — this feeder arms through the shipped verb and has no second dispatch path to fall back on" >&2; return 2; }

    # The in-flight read is a safety bound. An unreadable one is NOT zero.
    local in_flight
    in_flight="$(inflight_count)" || {
        echo "$PROG: could not determine how many auto-armed beads are in flight — refusing to arm, because reading this as 0 would hand the pass a full budget and blow the cap" >&2
        return 1; }

    local slots budget
    slots=$(( MAX_IN_FLIGHT - in_flight ))
    [ "$slots" -lt 0 ] && slots=0
    budget="$slots"
    [ "$budget" -gt "$MAX_PER_TICK" ] && budget="$MAX_PER_TICK"

    if [ "$budget" -le 0 ]; then
        echo "$PROG: $in_flight/$MAX_IN_FLIGHT auto-armed in flight — at cap, arming nothing this pass"
        return 0
    fi

    local rows; rows="$(mktemp_tracked)" || { echo "$PROG: feed: mktemp failed" >&2; return 1; }
    # Enumeration failure is NOT an empty queue. Exit non-zero so the order logs
    # it; a silent zero here would read exactly like "no work was ready", which
    # is the sentence this whole mechanism exists to stop being a lie.
    candidate_rows "$rows" || {
        echo "$PROG: could not enumerate ready work — NOT treating this as an empty queue" >&2
        return 1; }

    # A refused arm does not spend the budget — the next candidate is tried, which
    # is right, because a refusal here is a RACE (arm refuses closed / in_progress
    # / routed beads, and every one of those also drops the bead out of the next
    # `--ready` listing or the exclusions above) rather than a durable state.
    # But "try the next one" without a bound turns a SYSTEMIC failure — bd writes
    # failing, the store read-only mid-migration — into one pass attempting all
    # 145 candidates at three writes each, which blows the order timeout and gets
    # the pass killed instead of reporting. Consecutive failures are what tell the
    # two apart: a race is isolated, a broken store fails identically every time.
    local -r MAX_CONSEC_FAIL=3
    local available armed=0 failed=0 consec_fail=0 id created itype rc
    local -a dbarg=()
    [ -n "$BD_DB" ] && dbarg=(--db "$BD_DB")
    available="$(wc -l < "$rows" | tr -d ' ')"

    if [ "$available" = "0" ]; then
        echo "$PROG: 0 armed ($in_flight/$MAX_IN_FLIGHT in flight, 0 candidates ready)"
        return 0
    fi

    while IFS=$'\t' read -r id created itype; do
        [ -n "${id:-}" ] || continue
        [ "$armed" -lt "$budget" ] || break

        if [ "$DRY_RUN" = 1 ]; then
            echo "$PROG: DRY-RUN would arm $id ($itype, created $created) -> $TARGET"
            armed=$((armed + 1))
            continue
        fi

        # Reserve the slot BEFORE arming. The two writes cannot be atomic, so
        # the order decides which way a crash between them fails. Reserving
        # first over-counts (a slot held by a bead that never got armed);
        # arming first under-counts (an armed bead invisible to the cap, which
        # is the cap leaking). A safety bound must fail toward being too
        # tight, and the over-count is self-healing: the bead is still ready,
        # still unrouted and still un-armed, so the next pass finds it as a
        # candidate again and arms it, and the re-stamp is idempotent.
        if ! mark_reserved "$id"; then
            echo "$PROG: WARN could not reserve a slot on $id — skipping it rather than arming past the cap" >&2
            failed=$((failed + 1)); consec_fail=$((consec_fail + 1))
            [ "$consec_fail" -lt "$MAX_CONSEC_FAIL" ] || {
                echo "$PROG: $MAX_CONSEC_FAIL consecutive failures — stopping this pass; that is a broken store, not a race, and retrying every remaining candidate would only run the pass into its timeout" >&2
                break; }
            continue
        fi

        "$ARM_TOOL" arm "$id" --target "$TARGET" \
            ${dbarg[@]+"${dbarg[@]}"} \
            --reason "auto-armed by $PROG: ready, unrouted and unheld since $created" >/dev/null 2>&1
        rc=$?
        if [ "$rc" != 0 ]; then
            # arm is fail-closed and refuses a bead that got closed or
            # dispatched between our listing and this call. Release the slot so
            # a bead that is not ours does not hold capacity forever.
            if release_reserved "$id"; then
                echo "$PROG: WARN arm of $id -> $TARGET failed (rc=$rc) — slot released, retrying next pass" >&2
            else
                echo "$PROG: WARN arm of $id -> $TARGET failed (rc=$rc) AND the reserved slot could not be released — this rig is now one slot tighter until $id closes" >&2
            fi
            failed=$((failed + 1)); consec_fail=$((consec_fail + 1))
            [ "$consec_fail" -lt "$MAX_CONSEC_FAIL" ] || {
                echo "$PROG: $MAX_CONSEC_FAIL consecutive failures — stopping this pass; that is a broken store, not a race, and retrying every remaining candidate would only run the pass into its timeout" >&2
                break; }
            continue
        fi

        echo "$PROG: armed $id ($itype, created $created) -> $TARGET"
        armed=$((armed + 1)); consec_fail=0
    done < "$rows"

    echo "$PROG: $armed armed, $failed failed ($in_flight/$MAX_IN_FLIGHT in flight before this pass, budget $budget, $available candidate(s) ready)"
    [ "$failed" = 0 ]
}

# --- status ------------------------------------------------------------------
cmd_status() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --db) shift; BD_DB="${1:-}" ;;
            *) echo "$PROG: status: unknown flag '$1'" >&2; return 2 ;;
        esac
        shift || true
    done

    echo "$PROG: enabled=$(enabled_state) (DISPATCH_FEEDER_ENABLED='$ENABLED') max_in_flight=$MAX_IN_FLIGHT max_per_tick=$MAX_PER_TICK target='$TARGET'"

    local in_flight
    in_flight="$(inflight_count)" || {
        echo "$PROG: could not read the in-flight count" >&2; return 1; }
    echo "$PROG: $in_flight auto-armed bead(s) in flight"

    local rows; rows="$(mktemp_tracked)" || { echo "$PROG: status: mktemp failed" >&2; return 1; }
    candidate_rows "$rows" || { echo "$PROG: could not enumerate ready work" >&2; return 1; }

    local n; n="$(wc -l < "$rows" | tr -d ' ')"
    echo "$PROG: $n candidate(s) ready, oldest first:"
    if [ "$n" = "0" ]; then
        echo "  (none)"
    else
        head -10 "$rows" | while IFS=$'\t' read -r id created itype; do
            printf '  %s  %-8s %s\n' "${created:0:10}" "$itype" "$id"
        done
        [ "$n" -gt 10 ] && echo "  ... and $((n - 10)) more"
    fi
    return 0
}

# --- main --------------------------------------------------------------------
verb="${1:-}"; shift || true
case "$verb" in
    feed)   cmd_feed "$@" ;;
    status) cmd_status "$@" ;;
    -h|--help|help|"") usage; [ -n "$verb" ] && exit 0 || exit 2 ;;
    *) echo "$PROG: unknown verb '$verb'" >&2; usage >&2; exit 2 ;;
esac
