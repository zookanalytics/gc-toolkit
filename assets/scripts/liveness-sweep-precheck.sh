#!/usr/bin/env bash
# liveness-sweep-precheck.sh — decide, mechanically and cheaply, whether one
# liveness-sweep pass has anything to say (bead tk-7h51d). It is the `check`
# of the condition order orders/liveness-sweep.toml: exit 0 = run the pass,
# non-zero = do not.
# ITS CONDITION IS A STRICT SUBSET of liveness-sweep.sh's classification:
# every exclusion made here, the sweep also makes, and the three non-local /
# non-monotone ones (worked-via-convoy, the open-PR intersection, the
# pre-open gate verdicts) are deliberately NOT made — so the local survivor
# set is a SUPERSET of the sweep's true candidates and "zero survivors
# locally" proves "zero candidates really", but only for the batch triage
# visit. The skip is gated on that empty survivor set, not on an empty delta:
# the sweep files a visit — or rotates a slice of the carried backlog back
# into the enumerated agenda — whenever ANY candidate survives, so a stable
# carried set (nothing new, but a backlog to rotate) still owes a pass and the
# check must open the gate for it. The pass also has a second output — the
# per-anchor stale-gate escalation — that no unnamed-waits baseline can
# represent, so the check ALSO runs whenever a PR-gated anchor's re-escalation
# floor is up (the stale-due gate below). Anything else — any unreadable
# probe, a missing subject, its own abort — RUNS the pass: a probe that cannot
# be read excludes nothing. It also sets the 6h cadence (a condition trigger
# has no interval). The per-rig window is spent by whichever side ends the pass's
# chance to run: liveness-sweep.sh when a pass starts, or this check when it
# has proved the board quiet, since then no pass will. A RUN verdict never
# spends it, because more callers evaluate a check than dispatch from it (the
# controller tick, the API order evaluator, `gc order check`) and a check that
# closed its own window on RUN would hand the pass to whichever caller asked
# first. Never writes a bead and never advances the sweep's baseline.
# Usage: liveness-sweep-precheck.sh [--force]
#   --force    classify inside the window, and leave the window where it is
# Exit: 0 = RUN the agent pass · 1 = do not (nothing new / window) · 2 usage.
# NOT set -e: every failure is handled and routed to the run-the-pass side.
set -uo pipefail

INTERVAL="${LIVENESS_SWEEP_INTERVAL:-21600}"     # the 6h cadence lives HERE only
CALL_TIMEOUT="${LIVENESS_SWEEP_CALL_TIMEOUT:-45}"
KILL_AFTER="${LIVENESS_SWEEP_KILL_AFTER:-5}"
# The floor between two stale-gate escalations about one anchor, mirrored from
# liveness-sweep.sh so the "may owe an escalation" run-gate below reads the same
# stamp with the same arithmetic the pass does.
STALE_REESCALATE_DAYS="${LIVENESS_SWEEP_STALE_REESCALATE_DAYS:-3}"
case "$STALE_REESCALATE_DAYS" in ''|*[!0-9]*) STALE_REESCALATE_DAYS=3 ;; esac

FORCE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --force)   FORCE=1 ;;
        -h|--help) sed -n '/^# Usage:/,/^# NOT set -e/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "liveness-sweep-precheck: unexpected argument: $1" >&2; exit 2 ;;
    esac
    shift
done

# Initialised to the safe side; ONE guarded assignment below may change it.
DECISION=run
REASON="precheck did not complete"
DECIDED=0
TMP=""

# The state dir MUST be per rig: GC_PACK_STATE_DIR is city+pack scoped while
# this order runs per rig, so an unkeyed stamp would let the first rig
# silence every other rig's sweep for the window. Same keying as
# liveness-sweep.sh, which keeps its delta baseline beside this stamp.
state_key() {
    local readable="$1" identity="$2" safe
    safe="$(printf '%s' "$readable" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_')"
    case "$safe" in ''|.|..) safe=rig ;; esac
    if [ "$safe" = "$readable" ] && [ "$readable" = "$identity" ] && [ "${#safe}" -le 64 ]; then
        printf '%s' "$safe"
    else
        printf '%s-%s' "${safe:0:64}" "$(printf '%s' "$identity" | cksum | cut -d' ' -f1)"
    fi
}
if [ -n "${GC_RIG:-}" ]; then
    RIG_KEY="$(state_key "$GC_RIG" "$GC_RIG")"
elif [ -n "${GC_RIG_ROOT:-}" ]; then
    ROOT_TAIL="${GC_RIG_ROOT%/}"
    RIG_KEY="$(state_key "${ROOT_TAIL##*/}" "$GC_RIG_ROOT")"
else
    RIG_KEY=_unscoped
fi
DEFAULT_STATE_DIR="${GC_PACK_STATE_DIR:-${TMPDIR:-/tmp}/gc}"
STATE_BASE="${LIVENESS_SWEEP_STATE_DIR:-$DEFAULT_STATE_DIR/liveness-sweep}"
STATE_DIR="$STATE_BASE/$RIG_KEY"
STAMP="$STATE_DIR/last-pass"
BASELINE_FILE="$STATE_DIR/reported"    # written only by liveness-sweep.sh
LOG="$STATE_DIR/pass.log"
LOG_KEEP="${LIVENESS_SWEEP_LOG_KEEP:-400}"

# gc bd resolves its ledger from the invoking rig (BEADS_DIR is ignored), so
# pin to GC_RIG_ROOT when set.
DB="${LIVENESS_SWEEP_DB-${GC_RIG_ROOT:+$GC_RIG_ROOT/.beads}}"

say() { printf '%s\n' "$*"; REPORT="${REPORT:-}$*"$'\n'; }
REPORT=""

# Reached through the EXIT trap, not a visible call site.
# shellcheck disable=SC2329
flush_report() {
    [ -n "$REPORT" ] || return 0
    mkdir -p "$STATE_DIR" 2>/dev/null || return 0
    { printf '=== %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"; printf '%s' "$REPORT"; } >> "$LOG" 2>/dev/null || return 0
    if [ -w "$LOG" ]; then
        tail -n "$LOG_KEEP" "$LOG" > "$LOG.trim" 2>/dev/null && mv "$LOG.trim" "$LOG" 2>/dev/null
    fi
    return 0
}
# shellcheck disable=SC2329
cleanup_tmp() { [ -n "$TMP" ] && rm -rf "$TMP"; return 0; }
# An abort before the decision must never look like "nothing to do": exit 0.
# shellcheck disable=SC2329
on_exit() {
    local rc=$?
    if [ "$DECIDED" -eq 0 ]; then
        say "liveness-sweep precheck: ABORTED before deciding (rc=$rc) — this is NOT an empty board."
        say "  Running the agent pass so the sweep still happens."
        flush_report; cleanup_tmp
        exit 0
    fi
    flush_report; cleanup_tmp
    exit "$rc"
}
trap on_exit EXIT

command -v jq >/dev/null 2>&1 || {
    say "liveness-sweep precheck: jq is missing — cannot classify, so the agent pass runs."
    DECIDED=1; exit 0
}

# The cooldown. A RUN verdict this script hands out must be the same one the
# next caller gets, because the caller that acts on it is not necessarily the
# caller that asked; liveness-sweep.sh stamps $STAMP once the pass starts.
# Repeating RUN cannot storm: the controller gates on an open order-tracking
# bead before it evaluates a check at all, so the pass in flight is the one
# that closes the window.
NOW="$(date -u +%s)"
if [ "$FORCE" -eq 0 ] && [ -f "$STAMP" ]; then
    LAST="$(cat "$STAMP" 2>/dev/null)"
    case "$LAST" in ''|*[!0-9]*) LAST=0 ;; esac    # unreadable = "never" (re-report side)
    ELAPSED=$((NOW - LAST))
    if [ "$LAST" -gt 0 ] && [ "$ELAPSED" -ge 0 ] && [ "$ELAPSED" -lt "$INTERVAL" ]; then
        # Silent: this is the answer on almost every tick.
        DECISION=skip; DECIDED=1
        exit 1
    fi
fi
# Both writers of $STAMP — this check and liveness-sweep.sh — replace it
# atomically, a temp file in $STATE_DIR renamed over the stamp. rename(2)
# consults the DIRECTORY's mode and never the stamp's own, so creating a file
# in $STATE_DIR probes exactly the permission the real write needs and a
# last-pass left read-only still takes the window. What rename cannot replace
# is a $STAMP that is not a regular file, so that is refused here too. With
# neither the stamp nor the refusal the cadence has no floor and every
# dispatch tick would run a pass.
spend_window() { # spend_window <epoch-seconds>
    local tmp="$STAMP.$$.tmp"
    mkdir -p "$STATE_DIR" 2>/dev/null || return 1
    if printf '%s\n' "$1" > "$tmp" 2>/dev/null && mv -f "$tmp" "$STAMP" 2>/dev/null; then
        return 0
    fi
    rm -f "$tmp" 2>/dev/null
    return 1
}
STAMP_WRITABLE=0
if ( mkdir -p "$STATE_DIR" 2>/dev/null && : > "$STAMP.probe" 2>/dev/null ); then
    { [ ! -e "$STAMP" ] || [ -f "$STAMP" ]; } && STAMP_WRITABLE=1
fi
rm -f "$STAMP.probe" 2>/dev/null || true
if [ "$STAMP_WRITABLE" -eq 0 ]; then
    say "liveness-sweep precheck: CANNOT WRITE the cooldown stamp at $STAMP."
    say "  Refusing to run the pass: with no cadence this check would dispatch a pass"
    say "  on every dispatch tick. Fix the state directory — the sweep is OFF"
    say "  for this rig until it is writable."
    DECISION=skip; REASON="cooldown stamp unwritable"; DECIDED=1
    exit 1
fi

TMP="$(mktemp -d)"

if command -v timeout >/dev/null 2>&1; then
    if timeout -k 1 1 true >/dev/null 2>&1; then
        bounded() { timeout -k "$KILL_AFTER" "$CALL_TIMEOUT" "$@"; }
    else
        bounded() { timeout "$CALL_TIMEOUT" "$@"; }
    fi
else
    bounded() { "$@"; }
fi
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

bd_read() { # bd_read <outfile> <subcommand> <flags...>
    local out="$1"; shift
    local rc
    if [ -n "$DB" ]; then
        bounded gc bd "$1" --db "$DB" "${@:2}" 2>/dev/null | scrub > "$out"; rc=$?
    else
        bounded gc bd "$@" 2>/dev/null | scrub > "$out"; rc=$?
    fi
    # BOTH halves required: a failed call can still print a well-formed array,
    # and [] from a dead store is byte-identical to [] from an idle board.
    LAST_READ_ERR=""
    if [ "$rc" -ne 0 ]; then LAST_READ_ERR="the call failed or timed out, rc=$rc"; return 1; fi
    jq -e 'type == "array"' "$out" >/dev/null 2>&1 && return 0
    LAST_READ_ERR="the answer is not a JSON array"
    return 1
}

# The same three reads liveness-sweep.sh takes. WIDEN carries every non-closed
# status LIVE omits: "still alive" means NOT CLOSED (live case tk-dhue).
READY="$TMP/ready.json"; LIVE="$TMP/live.json"; WIDEN="$TMP/widen.json"; ALIVE="$TMP/alive.json"
READS_OK=1
READ_FAIL=""
LAST_READ_ERR=""
bd_read "$READY" ready --unassigned --limit=0 --json || { READS_OK=0; READ_FAIL="ready: $LAST_READ_ERR"; }
bd_read "$LIVE"  list --status=open,in_progress --limit=0 --json || { READS_OK=0; READ_FAIL="${READ_FAIL:+$READ_FAIL; }live: $LAST_READ_ERR"; }
bd_read "$WIDEN" list --status=blocked,deferred,pinned,hooked --limit=0 --json || { READS_OK=0; READ_FAIL="${READ_FAIL:+$READ_FAIL; }widen: $LAST_READ_ERR"; }
if [ "$READS_OK" -eq 1 ]; then
    jq -s 'add' "$LIVE" "$WIDEN" > "$ALIVE" 2>/dev/null
    jq -e 'type == "array"' "$ALIVE" >/dev/null 2>&1 \
        || { READS_OK=0; READ_FAIL="alive-merge: the merged not-closed set is not a JSON array"; }
fi
N_READY=""; N_LIVE=""; N_ALIVE=""
if [ "$READS_OK" -eq 1 ]; then
    N_READY=$(jq 'length' "$READY" 2>/dev/null)
    N_LIVE=$(jq 'length' "$LIVE" 2>/dev/null)
    N_ALIVE=$(jq 'length' "$ALIVE" 2>/dev/null)
fi

# The standing subject (live-visit guard) and the sweep's state-file baseline.
# Zero subjects, or more than one, runs the pass rather than guessing.
SUBJECT=""; N_SUBJECTS=0; BASELINE=""; N_BASELINE=0; LIVE_VISIT=""
if [ "$READS_OK" -eq 1 ]; then
    N_SUBJECTS=$(jq '[.[] | select((.metadata.task_kind // "") == "triage-subject")
                          | select((.metadata["triage.scope"] // "") == "unnamed-waits")] | length' "$LIVE" 2>/dev/null)
    case "${N_SUBJECTS:-}" in ''|*[!0-9]*) N_SUBJECTS=0 ;; esac
    if [ "$N_SUBJECTS" = "1" ]; then
        SUBJECT=$(jq -r '[.[] | select((.metadata.task_kind // "") == "triage-subject")
                              | select((.metadata["triage.scope"] // "") == "unnamed-waits")] | .[0].id // ""' "$LIVE" 2>/dev/null)
        BASELINE=$(cat "$BASELINE_FILE" 2>/dev/null || true)
        N_BASELINE=$(printf '%s' "$BASELINE" | tr ',' '\n' | awk 'NF { n++ } END { print n + 0 }')
        # A visit names its subject twice (gc.continuation_group stamp + tracks
        # edge) and only the edge has proved reliable (su-ab9je): read BOTH.
        # select(. != "") keeps an empty stamp from matching an empty subject.
        LIVE_VISIT=$(jq -r --arg s "$SUBJECT" '[.[] | select((.metadata.task_kind // "") == "visit")
                                                    | ((.metadata["gc.continuation_group"] // ""),
                                                       (.dependencies[]? | select((.type // "") == "tracks") | (.depends_on_id // "")))
                                                    | select(. != "")]
                                               | (index($s) // "") | tostring' "$LIVE" 2>/dev/null)
    fi
fi

# The local survivor set — every exclusion here is one liveness-sweep.sh also
# makes. Every `// ""` is load-bearing (most beads carry no metadata key at
# all); an empty hold is a CLEARED hold, not a hold. Class 2(i)(a) is a
# REVERSE index: the child holds the parent-child edge. `gc.takeaway` is not
# an exclusion, for the reason the sweep's classify block gives; $demanded is
# the sweep's arm of the same name, and it has to stay in step with it or a
# bead the sweep would report is dropped here and never reaches a pass.
SURVIVORS=""; N_SURVIVORS=""; NEW_IDS=""; N_NEW=""
JQ_OK=0
if [ "$READS_OK" -eq 1 ] && [ -n "$SUBJECT" ]; then
    SURVIVORS=$(jq -n --slurpfile ready "$READY" --slurpfile live "$LIVE" --slurpfile alive "$ALIVE" '
      ([ ($live[0] // [])[]
         | select((.metadata.task_kind // "") == "visit")
         | ((.metadata["gc.continuation_group"] // ""),
            (.dependencies[]? | select((.type // "") == "tracks") | (.depends_on_id // "")))
         | select(. != "") ]) as $convgroups
      | (($alive[0] // []) | map({key: .id, value: true}) | from_entries) as $aliveset
      | ([ ($alive[0] // [])[]
           | .dependencies[]?
           | select((.type // "") == "parent-child")
           | (.depends_on_id // empty) ] | unique) as $gatedparents
      | ([ ($alive[0] // [])[]
           | (.metadata["gc.demand_for"] // "") | select(. != "") ] | unique) as $demanded
      | [ ($ready[0] // [])[]
          | select((.metadata["gc.routed_to"] // "") == "")
          | select((.metadata.task_kind // "") != "visit")
          | select((.metadata.task_kind // "") != "triage-subject")
          | select(.id as $id | ($demanded | index($id)) | not)
          | select((.metadata["triage.hold"] // "") == "")
          | select(.id as $id | ($convgroups | index($id)) | not)
          | select(.id as $id | ($gatedparents | index($id)) | not)
          | select([ .dependencies[]?
                     | select((.type // "") == "tracks")
                     | select(($aliveset[(.depends_on_id // "")] // false)) ] | length == 0)
          | .id
        ]' 2>/dev/null)
    if printf '%s' "$SURVIVORS" | jq -e 'type == "array"' >/dev/null 2>&1; then
        NEW_IDS=$(printf '%s' "$SURVIVORS" | jq -c --arg seen "$BASELINE" '
          ($seen | split(",") | map(gsub("^[[:space:]]+|[[:space:]]+$"; "")) | map(select(. != ""))) as $s
          | map(select(. as $id | ($s | index($id)) | not))' 2>/dev/null)
        if printf '%s' "$NEW_IDS" | jq -e 'type == "array"' >/dev/null 2>&1; then
            N_SURVIVORS=$(printf '%s' "$SURVIVORS" | jq 'length')
            N_NEW=$(printf '%s' "$NEW_IDS" | jq 'length')
            JQ_OK=1
        fi
    fi
fi

# The baseline speaks only for the batch triage visit. The pass has a second
# output the baseline cannot represent: a per-anchor stale-gate escalation. On a
# pass whose gh read failed, liveness-sweep.sh cannot intersect the open-PR set,
# so a PR-gated anchor falls open to `unnamed` and is advanced into the reported
# baseline; once gh recovers and the PR is past its age, that id is no longer new
# and a baseline-only skip would bury the escalation for good. So run the pass
# whenever a PR-gated anchor's re-escalation floor is up, regardless of the
# baseline — the same stale_escalated_at stamp and floor arithmetic the sweep
# gates on. PR age is the sweep's gh read, not this local check, so every
# floor-elapsed PR-gated anchor is included: a superset of the sweep's stale-gate
# set, the same run-the-pass bias as every probe above.
STALE_DUE=""; N_STALE_DUE=""
if [ "$READS_OK" -eq 1 ]; then
    STALE_DUE=$(jq -n --slurpfile ready "$READY" \
        --argjson now "$NOW" --argjson floor "$((STALE_REESCALATE_DAYS * 86400))" '
      [ ($ready[0] // [])[]
        | select((.metadata.merge_result // "") == "pull_request")
        | select((.metadata.pr_url // "") != "")
        | (.metadata.stale_escalated_at // "") as $e
        | select($e == ""
                 or ((try ($e | fromdateiso8601) catch null) as $t
                     | if $t == null then true else ($now - $t) >= $floor end))
        | .id ]' 2>/dev/null)
    if printf '%s' "$STALE_DUE" | jq -e 'type == "array"' >/dev/null 2>&1; then
        N_STALE_DUE=$(printf '%s' "$STALE_DUE" | jq 'length')
    fi
fi

# The ONE place DECISION may become skip — it needs every positive fact at once.
# Gated on the whole survivor set, not the delta: the sweep rotates a slice of
# the carried backlog every pass, so a stable carried set (0 new) still owes a
# pass; only an empty survivor set means the sweep would file nothing. And on no
# stale-due anchor: N_STALE_DUE empty (its jq failed) defaults to the run side,
# like every probe.
if [ "$READS_OK" -eq 1 ] && [ "$JQ_OK" -eq 1 ] && [ "$N_SURVIVORS" = "0" ] && [ -z "$LIVE_VISIT" ] && [ "${N_STALE_DUE:-1}" = "0" ]; then
    DECISION=skip
    REASON="0 unnamed-wait candidates ($N_BASELINE previously reported, none still unnamed) and no live visit on $SUBJECT"
elif [ "$READS_OK" -ne 1 ]; then
    REASON="a required bead read was UNREADABLE ($READ_FAIL) — an unreadable probe excludes nothing"
elif [ "$N_SUBJECTS" = "0" ]; then
    REASON="no standing unnamed-waits triage subject on this rig — no baseline, so every candidate is new"
elif [ "$N_SUBJECTS" != "1" ]; then
    REASON="$N_SUBJECTS unnamed-waits triage subjects — cannot tell which baseline the agent pass would read"
elif [ "$JQ_OK" -ne 1 ]; then
    REASON="the local classification did not produce a JSON array — treating that as unknown, never as empty"
elif [ -n "$LIVE_VISIT" ]; then
    REASON="a visit is already live on $SUBJECT; $N_NEW new local candidate(s) await it"
elif [ "$N_NEW" != "0" ]; then
    REASON="$N_NEW new local candidate(s) since the last reported pass"
elif [ "${N_STALE_DUE:-0}" != "0" ]; then
    REASON="$N_STALE_DUE PR-gated anchor(s) past the re-escalation floor may owe a stale-gate escalation the unnamed baseline cannot represent"
else
    REASON="$N_SURVIVORS carried candidate(s) to rotate back into the enumerated agenda (0 new since the last reported pass)"
fi
DECIDED=1

say "liveness-sweep precheck — rig ${GC_RIG:-<none>} · store ${DB:-<ambient>} · window $STAMP"
if [ "$READS_OK" -eq 1 ]; then
    say "  reads: ready $N_READY · live $N_LIVE · alive $N_ALIVE — every call exited 0 and answered a JSON array"
else
    say "  reads: FAILED — $READ_FAIL"
fi
if [ -n "$SUBJECT" ]; then
    if [ -n "$LIVE_VISIT" ]; then VISIT_WORD=yes; else VISIT_WORD=no; fi
    say "  subject $SUBJECT · baseline $N_BASELINE id(s) · live visit: $VISIT_WORD"
fi
if [ "$JQ_OK" -eq 1 ]; then
    say "  local survivors $N_SURVIVORS -> new $N_NEW"
    if [ "$N_NEW" != "0" ]; then
        say "  new: $(printf '%s' "$NEW_IDS" | jq -r 'join(", ")')"
    fi
fi
if [ "${N_STALE_DUE:-0}" != "0" ]; then
    say "  PR-gated anchors past the stale re-escalation floor: $N_STALE_DUE -> $(printf '%s' "$STALE_DUE" | jq -r 'join(", ")')"
fi

if [ "$DECISION" = "skip" ]; then
    say "SKIP: $REASON — no agent session this pass."
    # A proven-quiet board spends the window here, because nothing else will:
    # the exec is the only other writer and a SKIP never starts it. Left
    # unspent, the whole classification re-runs on every evaluation of a board
    # that has nothing to say, which is the poll this cadence exists to bound.
    # Spending a SKIP is safe in a way spending a RUN is not, because every
    # caller inside the window gets the same "do not run" either way. --force
    # is diagnostic and leaves the window where it found it. The two earlier
    # skips never reach here: one is already inside a window, the other could
    # not write.
    if [ "$FORCE" -eq 0 ]; then
        spend_window "$NOW" \
            || say "  WARN: cannot stamp the cadence window at $STAMP — the next tick reclassifies."
    fi
    exit 1
fi
say "RUN: $REASON."
exit 0
