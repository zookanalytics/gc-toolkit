#!/usr/bin/env bash
# liveness-sweep-precheck.sh — decide, without an agent session, whether one
# liveness-sweep pass has anything to say (bead tk-7h51d).
#
# THE DEFECT. mol-liveness-sweep spent a whole polecat session every pass to
# reach the conclusion "nothing new", and then filed nothing. The order fires
# per rig on a 6h cooldown, so that is ~4 passes/day/rig, ~16 sessions/day
# across four rigs. The classify step is O(open beads) — every open bead read, a
# per-candidate `gc bd show` for the edge checks, plus batched GitHub and convoy
# reads — so the price of concluding "nothing" grew with the backlog, which is
# the wrong direction for a check whose whole job is to be boring most of the
# time. Measured on this rig: the three batched reads plus the jq below reach
# the same verdict in ~2.7s.
#
# THE SPLIT THIS PRESERVES: determination is mechanical, narration is judgment.
# Deciding WHETHER the new-candidate set is empty is jq. Writing "why it reads
# idle" per candidate, grouping overflow into labelled cohorts and calling out
# epic what-comes-next candidates is real judgment and keeps its agent. Only the
# empty path short-circuits; everything else runs the agent pass unchanged.
#
# HOW IT IS WIRED. `orders/liveness-sweep.toml` is a `condition` order whose
# `check` is this script: exit 0 means "run the pass", non-zero means "do not".
# The formula, the pool, the rig scope and every dispatch mechanic — the
# single-flight open-work gate that stops wisps accumulating when a pool stalls,
# the order-tracking beads, `gc order history` — are untouched, so a non-empty
# pass is dispatched by exactly the path that dispatched it before. What this
# script replaces is only the CLOCK: a condition trigger has no interval, so the
# 6h cadence is enforced here (see THE COOLDOWN below).
#
# ---------------------------------------------------------------------------
# WHY SKIPPING IS PROVABLY SAFE, not probably safe
#
# This script does NOT re-implement the classifier. It applies a deliberately
# SMALLER filter, whose every exclusion is one the shipped classifier also makes
# (mol-liveness-sweep.toml, the `classify-candidates` block plus its
# per-candidate edge check):
#
#   * assignee non-empty      — via `gc bd ready --unassigned`, the same read
#                               the classifier starts from;
#   * gc.routed_to non-empty  — class 1;
#   * task_kind=visit         — class 3;
#   * task_kind=triage-subject— class 4(a). NOT optional: the standing sweep
#                               subject is a permanent open, unassigned,
#                               unblocked bead in every rig, so without this the
#                               survivor set could never be empty and the whole
#                               precheck would be dead code;
#   * a live visit's continuation group — class 3;
#   * gc.takeaway non-empty   — class 4(c);
#   * triage.hold non-empty   — class 4(d);
#   * the class 2(i) structural edges to NON-CLOSED beads — (a) a non-closed
#     parent-child child, (b)/(c) an outgoing `tracks` edge to something still
#     alive.
#
# It deliberately does NOT apply the classifier's other three exclusions —
# worked-via-convoy (class 1's molecule indirection), the open-PR intersection
# and the pre-open gate verdicts (class 2(ii)). Two reasons, and the second is
# the load-bearing one:
#
#   1. They are not local. worked-via-convoy costs one `gc bd show` per convoy
#      and the PR half costs a `gh pr list` per repository; the empty path here
#      makes NO network call at all.
#   2. The PR read is NON-MONOTONE. The formula warns that a naive "carries
#      merge_result, skip it" rule "builds the inverse defect and hides rejected
#      work permanently, exactly when it most matters" — a GitHub read can both
#      exclude a gated bead and un-exclude one whose PR was rejected. An
#      exclusion whose direction depends on a network answer has no place in a
#      probe that decides whether anyone looks at the board at all.
#
# Because the exclusions are a strict SUBSET, the local survivor set is a
# SUPERSET of the classifier's true candidate set. So:
#
#       zero local survivors that are new  =>  zero true candidates that are new
#
# and the converse never has to hold: a non-empty local set simply runs the
# pass, where the full classifier applies the remaining three exclusions and may
# well report nothing. Over-reporting costs one agent pass — exactly what
# happens today. Under-reporting is the thing that cannot happen, and the subset
# argument is what rules it out. `liveness-sweep-precheck.test.sh` pins the
# containment against the classifier block extracted from the formula itself.
#
# The same asymmetry makes every read failure safe by construction. Each
# structural exclusion needs an edge to be PRESENT to drop a candidate, so a
# listing that renders fewer edges than exist drops fewer candidates, survives
# more, and runs the pass. There is no failure of these reads that manufactures
# an empty set.
#
# ---------------------------------------------------------------------------
# THE INVERTED FAILURE MODE, handled explicitly
#
# The formula's governing bias is that a probe which cannot be read excludes
# nothing — "its failure mode is to re-report, never to hide" (operator decision
# 2026-08-10, bead tk-snnpp). A programmatic short-circuit INVERTS that: a
# script that silently returns empty because of a bad jq, a schema change, a
# degraded store or a torn read files nothing and looks perfectly healthy. The
# sweep goes quiet and nobody notices, because there is no agent left to find
# the result strange.
#
# So this script concludes "empty" ONLY from positively verified reads, and the
# structure enforces it rather than the prose asking for it:
#
#   * DECISION is initialised to `run` and exactly ONE line in the file sets it
#     to `skip`, guarded on every positive fact at once;
#   * every read must BOTH succeed — the bounded call's own exit status, which
#     `pipefail` makes the pipeline's — and validate as a JSON array before it
#     is used, because a failed call can still print a well-formed array and
#     `[]` from a dead store is byte-identical to `[]` from an idle board; the
#     jq output is validated as a JSON array before it is counted;
#   * an EXIT trap fires when the script leaves without having decided — an
#     abort, a signal, a bad edit — and that path exits 0, i.e. RUNS THE PASS.
#
# Every abnormal path therefore ends in the agent pass. "Nothing to do" is
# reachable only from a complete set of good reads.
#
# One skip window is outside this script's reach and is bounded deliberately: a
# condition check killed by its `check_timeout` never proves its condition, so
# the order does not fire. Two things keep that from being silent. The order
# sets check_timeout well above this script's own worst case (three bounded
# reads at LIVENESS_SWEEP_CALL_TIMEOUT each), so the internal bound fires first
# and turns a wedged store into an UNREADABLE verdict that runs the pass; and
# the controller logs that specific case distinctly rather than as an ordinary
# false condition (`cmd/gc/order_dispatch.go`, gastownhall/gascity ga-ocypq2).
# Keep the inequality if you touch either number.
#
# THE COOLDOWN. A condition trigger has no interval and its check runs on every
# dispatch tick, so the 6h cadence lives here as a stamp file. Order of
# operations is due-check, then STAMP, then classify — never the reverse. A
# stamp written after the verdict would let a crash mid-classification re-offer
# the pass on the very next tick, and a degraded store would then dispatch an
# agent pass every tick instead of one per window. Stamping first costs at most
# one missed cycle and cannot storm.
#
# ---------------------------------------------------------------------------
# WHAT IT DOES NOT DO
#
#   * It never writes a bead. In particular it does NOT advance the sweep's
#     `sweep.reported` baseline on the skip path — that stamp is the agent
#     pass's, and writing the local (superset) survivor set into it would mark
#     beads as reported that were never classified, which is the one direction
#     that could hide one. A skipped pass therefore leaves the baseline exactly
#     as a pass that never ran would: departed ids stay in it one cycle longer
#     and read as CARRIED rather than NEW if they ever regress. Carried ids are
#     listed in full in every visit body and re-checked by liveness-recheck.sh,
#     so nothing is hidden — only the agenda/background split is one pass
#     behind.
#   * It never creates the standing triage subject. No subject means no
#     baseline, which means every candidate is new; it runs the pass and the
#     agent creates it.
#   * It makes no network call and reads no repository.
#
# Usage:
#   liveness-sweep-precheck.sh [--dry-run] [--force]
#
#   --dry-run  classify and report, but never stamp the cooldown. The exit code
#              is the same verdict a real run would give.
#   --force    classify even if the cooldown window has not elapsed.
#
# Exit codes: 0 = RUN the agent pass (the condition is due). 1 = do not run
# (nothing new, or the window has not elapsed). 2 = usage.
#
# The controller discards a condition check's stdout, so the report is also
# appended to $STATE_DIR/pass.log — that log is the only place a long run of
# quiet skips is visible, which is exactly the thing this change makes possible.
#
# NOT set -e: every failure mode above is handled explicitly and routed to the
# run-the-pass side, and an errexit abort would skip the diagnostics that make
# the failure legible. The EXIT trap covers what is left.
set -uo pipefail

# The 6h cadence, in seconds. It lives HERE and nowhere else: a condition
# trigger ignores `interval`, so an interval key in the order file would be an
# inert second copy that a later editor would change with no effect. The order
# file carries a pointer to this line instead.
INTERVAL="${LIVENESS_SWEEP_INTERVAL:-21600}"
CALL_TIMEOUT="${LIVENESS_SWEEP_CALL_TIMEOUT:-45}"
KILL_AFTER="${LIVENESS_SWEEP_KILL_AFTER:-5}"

DRY_RUN=0
FORCE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --force)   FORCE=1 ;;
        -h|--help)
            sed -n '/^# Usage:/,/^# NOT set -e/p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "liveness-sweep-precheck: unexpected argument: $1" >&2; exit 2 ;;
    esac
    shift
done

# The whole point of the file, in one variable. Initialised to the safe side;
# one guarded assignment below is the only thing that may change it.
DECISION=run
REASON="precheck did not complete"
DECIDED=0
TMP=""

DEFAULT_STATE_DIR="${GC_PACK_STATE_DIR:-${TMPDIR:-/tmp}/gc}"
STATE_DIR="${LIVENESS_SWEEP_STATE_DIR:-$DEFAULT_STATE_DIR/liveness-sweep}"
STAMP="$STATE_DIR/last-pass"
LOG="$STATE_DIR/pass.log"
LOG_KEEP="${LIVENESS_SWEEP_LOG_KEEP:-400}"

# --- the store pin -----------------------------------------------------------
# `gc bd` resolves its ledger from the invoking RIG and IGNORES BEADS_DIR (the
# lesson boot-health.sh paid for: an unpinned query read the rig ledger while
# the beads it wanted lived in the town one, and returned [] on every pass from
# a query whose flags were all correct). A rig-scoped order's check gets
# GC_RIG_ROOT, so pin to it and say which store was read. Unset means "run from
# wherever you are" — correct for a hand run inside a rig worktree.
DB="${LIVENESS_SWEEP_DB-${GC_RIG_ROOT:+$GC_RIG_ROOT/.beads}}"

say() { printf '%s\n' "$*"; REPORT="${REPORT:-}$*"$'\n'; }
REPORT=""

# The three below are reached through the EXIT trap, not by any call site a
# linter can see.
# shellcheck disable=SC2329
flush_report() {
    [ -n "$REPORT" ] || return 0
    mkdir -p "$STATE_DIR" 2>/dev/null || return 0
    { printf '=== %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"; printf '%s' "$REPORT"; } >> "$LOG" 2>/dev/null || return 0
    # Bounded, so a quiet rig cannot grow this without limit.
    if [ -w "$LOG" ]; then
        tail -n "$LOG_KEEP" "$LOG" > "$LOG.trim" 2>/dev/null && mv "$LOG.trim" "$LOG" 2>/dev/null
    fi
    return 0
}

# shellcheck disable=SC2329
cleanup_tmp() { [ -n "$TMP" ] && rm -rf "$TMP"; return 0; }

# Fires when the script leaves without reaching the decision below — an
# unexpected abort, a signal, a bug in an edit. This is the case the bead calls
# out as the one most likely to be got wrong: it must never look like "nothing
# to do". Exit 0, which RUNS THE PASS, and leave the reason in the log.
# shellcheck disable=SC2329
on_exit() {
    local rc=$?
    if [ "$DECIDED" -eq 0 ]; then
        say "liveness-sweep precheck: ABORTED before deciding (rc=$rc) — this is NOT an empty board."
        say "  Running the agent pass so the sweep still happens."
        flush_report
        cleanup_tmp
        exit 0
    fi
    flush_report
    cleanup_tmp
    exit "$rc"
}
trap on_exit EXIT

command -v jq >/dev/null 2>&1 || {
    say "liveness-sweep precheck: jq is missing — cannot classify, so the agent pass runs."
    DECIDED=1; exit 0
}

# --- the cooldown ------------------------------------------------------------
# Cheap enough to run on every dispatch tick: one stat, no store read. Every
# other line in this file is downstream of it.
NOW="$(date -u +%s)"
if [ "$FORCE" -eq 0 ] && [ -f "$STAMP" ]; then
    LAST="$(cat "$STAMP" 2>/dev/null)"
    case "$LAST" in
        ''|*[!0-9]*) LAST=0 ;;   # an unreadable stamp is treated as "never" —
                                 # the re-report direction, not the hide one
    esac
    ELAPSED=$((NOW - LAST))
    if [ "$LAST" -gt 0 ] && [ "$ELAPSED" -ge 0 ] && [ "$ELAPSED" -lt "$INTERVAL" ]; then
        # Deliberately silent and unlogged: this is the answer on almost every
        # tick, and logging it would bury the passes that matter.
        DECISION=skip
        DECIDED=1
        exit 1
    fi
fi

# Stamp BEFORE classifying — see THE COOLDOWN above. An unwritable state dir
# means the cadence cannot be enforced at all, and a condition order with no
# cadence dispatches an agent pass every tick; that storm is worse than a missed
# patrol, so it is the one condition that refuses to run the pass, loudly.
if [ "$DRY_RUN" -eq 0 ]; then
    if ! ( mkdir -p "$STATE_DIR" 2>/dev/null && printf '%s\n' "$NOW" > "$STAMP" 2>/dev/null ); then
        say "liveness-sweep precheck: CANNOT WRITE the cooldown stamp at $STAMP."
        say "  Refusing to run the pass: with no cadence this check would dispatch an agent"
        say "  session on every dispatch tick. Fix the state directory — the sweep is OFF"
        say "  for this rig until it is writable."
        DECISION=skip
        REASON="cooldown stamp unwritable"
        DECIDED=1
        exit 1
    fi
fi

TMP="$(mktemp -d)"

# Bounded calls. A wedged store is exactly the condition under which a probe
# must not hang the controller's order tick. `-k` adds the hard kill; hosts
# whose timeout(1) lacks it fall back to signal-only, and hosts with no
# timeout(1) at all run unbounded rather than not at all.
if command -v timeout >/dev/null 2>&1; then
    if timeout -k 1 1 true >/dev/null 2>&1; then
        bounded() { timeout -k "$KILL_AFTER" "$CALL_TIMEOUT" "$@"; }
    else
        bounded() { timeout "$CALL_TIMEOUT" "$@"; }
    fi
else
    bounded() { "$@"; }
fi

# bd emits stray control characters often enough to break jq (a single one kills
# the whole parse). Strip them, sparing TAB (\011) and NEWLINE (\012).
strip_ctrl() { tr -d '\000-\010\013\014\016-\037'; }

bd_read() { # bd_read <outfile> <subcommand> <flags...>
    local out="$1"; shift
    local rc
    if [ -n "$DB" ]; then
        bounded gc bd "$1" --db "$DB" "${@:2}" 2>/dev/null | strip_ctrl > "$out"
        rc=$?
    else
        bounded gc bd "$@" 2>/dev/null | strip_ctrl > "$out"
        rc=$?
    fi
    # BOTH halves are required, and the status is the half that cannot be
    # inferred from the answer. A failing call can still leave a well-formed
    # array on stdout — `timeout` killing the call after the opening `[` was
    # flushed, a store erroring partway through a listing, a `gc` that writes its
    # complaint to stderr and exits non-zero — and `[]` from a call that FAILED
    # is byte-identical to `[]` from a healthy empty board. Shape alone therefore
    # reads an outage as "nothing to report", which is the one direction this
    # script must never take: an unreadable probe excludes nothing, so a read
    # that did not demonstrably succeed can never be eligible for SKIP.
    # `set -o pipefail` is in force (see the top of the file), so $rc is the
    # bounded `gc bd` call's own failure or timeout, not merely strip_ctrl's.
    LAST_READ_ERR=""
    if [ "$rc" -ne 0 ]; then
        LAST_READ_ERR="the call failed or timed out, rc=$rc"
        return 1
    fi
    jq -e 'type == "array"' "$out" >/dev/null 2>&1 && return 0
    LAST_READ_ERR="the answer is not a JSON array"
    return 1
}

# --- the three reads ---------------------------------------------------------
# The same three the classify step takes, and for the same reasons. LIVE is
# open+in_progress (the visit-liveness and subject reads need exactly that
# narrower set). WIDEN carries every other non-closed status, because "is that
# target still alive?" means NOT CLOSED, not "present in LIVE" — a candidate
# waiting on a blocked, deferred, pinned or hooked target is a NAMED wait (live
# case tk-dhue: a convoy tracking a BLOCKED bead).
READY="$TMP/ready.json"; LIVE="$TMP/live.json"; WIDEN="$TMP/widen.json"; ALIVE="$TMP/alive.json"
READS_OK=1
READ_FAIL=""
# Set by every bd_read, and read only on its failure branch. Declared here as
# well because `set -u` is in force: a first assignment that lives inside the
# function would abort the script on any path that reached the branch first.
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

# --- the standing triage subject and its delta baseline ----------------------
# Read out of LIVE, not with a fourth call: the subject is an open bead, so it
# is already in hand. Exactly one must resolve. Zero means no baseline yet
# (first pass on this rig); more than one means the baseline this precheck would
# read is not necessarily the one the agent pass writes. In both cases the
# honest answer is to run the pass rather than guess.
SUBJECT=""; N_SUBJECTS=0; BASELINE=""; N_BASELINE=0; LIVE_VISIT=""
if [ "$READS_OK" -eq 1 ]; then
    N_SUBJECTS=$(jq '[.[] | select((.metadata.task_kind // "") == "triage-subject")
                          | select((.metadata["triage.scope"] // "") == "unnamed-waits")] | length' "$LIVE" 2>/dev/null)
    case "${N_SUBJECTS:-}" in ''|*[!0-9]*) N_SUBJECTS=0 ;; esac
    if [ "$N_SUBJECTS" = "1" ]; then
        SUBJECT=$(jq -r '[.[] | select((.metadata.task_kind // "") == "triage-subject")
                              | select((.metadata["triage.scope"] // "") == "unnamed-waits")] | .[0].id // ""' "$LIVE" 2>/dev/null)
        BASELINE=$(jq -r --arg s "$SUBJECT" '[.[] | select(.id == $s)] | .[0].metadata["sweep.reported"] // ""' "$LIVE" 2>/dev/null)
        N_BASELINE=$(printf '%s' "$BASELINE" | tr ',' '\n' | awk 'NF { n++ } END { print n + 0 }')
        # Class 3 at the subject level: a sitting is already live on this
        # subject. `index` returns a POSITION or null, and position 0 is a real
        # hit — the same reading the normalize step's step-3 skip uses.
        LIVE_VISIT=$(jq -r --arg s "$SUBJECT" '[.[] | select((.metadata.task_kind // "") == "visit")
                                                    | (.metadata["gc.continuation_group"] // "")]
                                               | (index($s) // "") | tostring' "$LIVE" 2>/dev/null)
    fi
fi

# --- the local survivor set --------------------------------------------------
SURVIVORS=""; N_SURVIVORS=""; NEW_IDS=""; N_NEW=""
JQ_OK=0
if [ "$READS_OK" -eq 1 ] && [ -n "$SUBJECT" ]; then
    SURVIVORS=$(jq -n --slurpfile ready "$READY" --slurpfile live "$LIVE" --slurpfile alive "$ALIVE" '
      # Live-visit continuation groups (class 3), from the open+in_progress set:
      # a visit being HELD is in_progress, so an open-only read would re-file on
      # exactly the subjects whose sittings are live.
      ([ ($live[0] // [])[]
         | select((.metadata.task_kind // "") == "visit")
         | (.metadata["gc.continuation_group"] // empty) ]) as $convgroups

      # Every NOT-CLOSED id: the set every "is that target still alive?" test
      # resolves against. Never $live alone — that is open+in_progress only, and
      # a blocked target still names the wait.
      | (($alive[0] // []) | map({key: .id, value: true}) | from_entries) as $aliveset

      # Class 2(i)(a). The CHILD holds the parent-child edge (verified on this
      # store: a bug row carries {"type":"parent-child","depends_on_id":"<epic>"}
      # while the epic row carries none), so a parent has no outgoing edge to
      # read and the index must be built in reverse, from the not-closed set. An
      # epic whose children have ALL closed is absent from it and survives —
      # which is the "what comes next?" candidate the sitting wants.
      | ([ ($alive[0] // [])[]
           | .dependencies[]?
           | select((.type // "") == "parent-child")
           | (.depends_on_id // empty) ] | unique) as $gatedparents

      | [ ($ready[0] // [])[]
          | select((.metadata["gc.routed_to"] // "") == "")
          | select((.metadata.task_kind // "") != "visit")
          | select((.metadata.task_kind // "") != "triage-subject")
          | select((.metadata["gc.takeaway"] // "") == "")
          | select((.metadata["triage.hold"] // "") == "")
          | select(.id as $id | ($convgroups | index($id)) | not)
          | select(.id as $id | ($gatedparents | index($id)) | not)
          # Class 2(i)(b)+(c): an outgoing `tracks` edge to something not closed
          # — a convoy waiting on what it carries, or a bead hanging off a root
          # still alive. Same edge direction, so one test covers both.
          | select([ .dependencies[]?
                     | select((.type // "") == "tracks")
                     | select(($aliveset[(.depends_on_id // "")] // false)) ] | length == 0)
          | .id
        ]' 2>/dev/null)
    # Every `// ""` above is load-bearing, not style: on a real store most beads
    # carry no gc.routed_to, no task_kind, no gc.takeaway and no triage.hold key
    # at all, so a strict ==/!= against a missing key compares to null and
    # matches the wrong set. Both hold filters drop a bead whose stamp is
    # NON-EMPTY and keep one whose stamp is present-but-empty: an empty
    # takeaway, and an empty triage.hold, are cleared holds, not holds.
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

# --- the decision ------------------------------------------------------------
# The ONE place DECISION may become `skip`, and it needs every positive fact at
# once: all three reads verified, the subject resolved, the classification
# actually produced a JSON array, that array's delta is empty, and no sitting is
# live on the subject. Anything missing leaves the initialised value.
if [ "$READS_OK" -eq 1 ] && [ "$JQ_OK" -eq 1 ] && [ "$N_NEW" = "0" ] && [ -z "$LIVE_VISIT" ]; then
    DECISION=skip
    REASON="0 new local candidates (of $N_SURVIVORS still unnamed, $N_BASELINE already reported) and no live visit on $SUBJECT"
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
else
    REASON="$N_NEW new local candidate(s) since the last reported pass"
fi
DECIDED=1

# --- report ------------------------------------------------------------------
say "liveness-sweep precheck — rig ${GC_RIG:-<none>} · store ${DB:-<ambient>}"
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

if [ "$DECISION" = "skip" ]; then
    say "SKIP: $REASON — no agent session this pass."
    exit 1
fi
say "RUN: $REASON."
exit 0
