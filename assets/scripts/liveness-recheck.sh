#!/usr/bin/env bash
# liveness-recheck.sh — re-validate a liveness-sweep gate's census when a
# person acts on it. The gate's message is a snapshot cut at pass time, and a
# person routinely reaches it a day or more later. Three batched bead reads
# re-derive every listed id's class and print a corrected census.
# Bead state only — no network: a merge_result marker and a recorded takeaway
# are FLAGGED for the sitting (never grounds for dropping a bead), and every
# failure path leaves a bead VISIBLE (a failed batched read prints NO census;
# a failed ready read skips the not-ready rule and says `unverified`; a failed
# human-gate read holds nothing and says so; an unreturned id gets its own
# `unreadable` bucket, counted into the live agenda).
# Callers: whoever acts on a liveness-sweep gate, by the command its message
# carries: liveness-sweep.sh writes the census into it as these flags.
# Usage:
#   liveness-recheck.sh --ids <id[,id ...]> [--carried <id[,id ...]>] [--pass-at <time>] [--all] [--json]
#   --ids      the ids new at the pass
#   --carried  the ids an earlier pass already reported, still unnamed
#   --pass-at  when the pass cut its census (an ISO-8601 UTC time), for its age
#   --all      also enumerate carried ids that are still idle
#   --json     emit the census as one JSON object
# Read-only: never writes a bead, never touches git, never calls the network.
# Exit: 0 census printed · 1 unreadable · 2 usage.
# NOT set -e: every failure is handled explicitly, routed to the visible side.
set -uo pipefail

usage() {
    sed -n '/^# Usage:/,/^# Read-only/p' "$0" | sed 's/^# \{0,1\}//'
}

IDS_ARG=""
CARRIED_ARG=""
PASS_AT=""
WANT_JSON=0
WANT_ALL=0

while [ $# -gt 0 ]; do
    case "$1" in
        --json) WANT_JSON=1 ;;
        --all)  WANT_ALL=1 ;;
        --ids|--carried|--pass-at)
            if [ $# -lt 2 ]; then echo "liveness-recheck: $1 needs a value" >&2; exit 2; fi
            case "$1" in
                --ids)     IDS_ARG="$2" ;;
                --carried) CARRIED_ARG="$2" ;;
                --pass-at) PASS_AT="$2" ;;
            esac
            shift
            ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "liveness-recheck: unknown flag: $1" >&2; usage >&2; exit 2 ;;
        *)
            # The form that took a visit id read the census the sweep stamped on
            # its visit. A gate carries none, and its message carries the
            # command with the census in these flags instead.
            echo "liveness-recheck: unexpected argument: $1 — the census rides the flags now: run the command the liveness-sweep gate's message carries (--ids, --carried, --pass-at)" >&2
            exit 2
            ;;
    esac
    shift
done

command -v jq >/dev/null 2>&1 || { echo "liveness-recheck: jq is required" >&2; exit 1; }

# The one definition of the standing kinds, shared with liveness-sweep.sh and
# its precheck, the proactive scan and the doctor checks. Exposes
# $STANDING_KINDS_JQ, which the classify block splices in.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=standing-kinds.sh
. "$HERE/standing-kinds.sh" || { echo "liveness-recheck: cannot source standing-kinds.sh from $HERE" >&2; exit 1; }
# The one definition of a bead that waits for placement, and the dispatch path
# it reads, shared with liveness-sweep.sh and its precheck, gc-helm.sh unplaced,
# the proactive scan and the doctor checks. Exposes $DISPATCH_PATH_JQ and
# $PLACEMENT_JQ, which the classify block splices in.
# shellcheck source=dispatch-path.sh
. "$HERE/dispatch-path.sh" || { echo "liveness-recheck: cannot source dispatch-path.sh from $HERE" >&2; exit 1; }
# shellcheck source=placement.sh
. "$HERE/placement.sh" || { echo "liveness-recheck: cannot source placement.sh from $HERE" >&2; exit 1; }
# The one rule of which human gates still hold the bead they block, shared with
# every reader of a bead's gates. Exposes $HUMAN_GATE_JQ, whose open_human_gates
# the gate read below keeps and whose gates_blocking the classify block splices
# in.
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$HERE/bd-lib.sh}" || { echo "liveness-recheck: cannot source bd-lib.sh from $HERE" >&2; exit 1; }

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

# Split on commas/whitespace, drop empties, keep first-seen order.
split_ids() {
    printf '%s' "${1:-}" \
        | tr ',' ' ' \
        | awk '{ for (i = 1; i <= NF; i++) if (!seen[$i]++) print $i }'
}

if [ -z "$IDS_ARG" ] && [ -z "$CARRIED_ARG" ]; then
    echo "liveness-recheck: give --ids <id,...>, the command a liveness-sweep gate's message carries" >&2
    usage >&2
    exit 2
fi
NEW_RAW="$IDS_ARG"
CARRIED_RAW="$CARRIED_ARG"

NEW_IDS=$(split_ids "$NEW_RAW")
CARRIED_IDS=$(split_ids "$CARRIED_RAW")
# A carried id that is also new is listed once, as new (the agenda wins).
if [ -n "$NEW_IDS" ] && [ -n "$CARRIED_IDS" ]; then
    CARRIED_IDS=$(printf '%s\n' "$CARRIED_IDS" | grep -Fxv -f <(printf '%s\n' "$NEW_IDS") || true)
fi

ALL_IDS=$(printf '%s\n%s\n' "$NEW_IDS" "$CARRIED_IDS" | awk 'NF && !seen[$0]++')
if [ -z "$ALL_IDS" ]; then
    echo "liveness-recheck: no ids to re-check"
    exit 0
fi
ID_CSV=$(printf '%s' "$ALL_IDS" | paste -sd, -)

to_json_array() { printf '%s' "${1:-}" | jq -R . | jq -sc 'map(select(length > 0))'; }
NEW_JSON=$(to_json_array "$NEW_IDS")
CARRIED_JSON=$(to_json_array "$CARRIED_IDS")

# --- read 1: every listed bead in ONE call, closed ones included (--all is
# what makes the resolved bucket possible). Into a FILE: hundreds of rows on
# argv would meet ARG_MAX as a truncation rather than an error.
BEADFILE=$(mktemp "${TMPDIR:-/tmp}/gctk-liveness-recheck.XXXXXX")
trap 'rm -f "$BEADFILE"' EXIT
gc bd list --id "$ID_CSV" --all --brief --json --limit=0 2>/dev/null | scrub > "$BEADFILE"
if ! jq -e 'type == "array"' "$BEADFILE" >/dev/null 2>&1; then
    echo "liveness-recheck: the batched bead read FAILED — no census printed." >&2
    echo "  (gc bd list --id … --all --brief --json --limit=0 returned no JSON array; a bd" >&2
    echo "  without --id or --brief would fail exactly here.)" >&2
    echo "  Nothing in the gate message has been re-verified; treat its census as unchecked," >&2
    echo "  and re-run this before routing anything." >&2
    exit 1
fi

# --- read 2: the ready set (best-effort, never load-bearing) ------------------
READY_STATE=verified
READY_RAW=$(gc bd ready --unassigned --limit=0 --json 2>/dev/null | scrub)
if printf '%s' "$READY_RAW" | jq -e 'type == "array"' >/dev/null 2>&1; then
    READY_JSON=$(printf '%s' "$READY_RAW" | jq -c '[.[].id]')
else
    READY_STATE=unverified
    READY_JSON=null
fi

# --- read 3: the open human gates, in one listing -----------------------------
# What a person still owes on a bead is a human gate that blocks it. That is the
# hold; `gc.takeaway` is the record of a sitting, which nothing clears, so it
# cannot say whether anyone is coming back. A gate takes the bead it blocks out
# of the ready set, which is why the not-ready rule usually catches this
# first — this read names the person's wait outright. The gates come from one
# `gc bd gate list` of the store, kept to the open human gates by bd-lib.sh's
# rule (open_human_gates), and each listed bead's own blocks edges, from read 1,
# say which of them hold it (gates_blocking).
# Best-effort like the ready set: unread means no bead is held, which lists
# beads rather than hiding them.
GATE_STATE=verified
GATE_RAW=$(gc bd gate list --json --limit 0 2>/dev/null | grep -a -vE '^gc bd:' | scrub)
if printf '%s' "$GATE_RAW" | jq -e 'type == "array" or . == null' >/dev/null 2>&1; then
    GATES_JSON=$(printf '%s' "$GATE_RAW" | jq -c "$HUMAN_GATE_JQ"'(. // []) | open_human_gates')
else
    GATE_STATE=unverified
    GATES_JSON='[]'
fi

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
AGE=""
if [ -n "$PASS_AT" ]; then
    PASS_EPOCH=$(jq -rn --arg t "$PASS_AT" '$t | fromdateiso8601' 2>/dev/null || echo "")
    NOW_EPOCH=$(date -u +%s 2>/dev/null || echo "")
    if [ -n "$PASS_EPOCH" ] && [ -n "$NOW_EPOCH" ] && [ "$NOW_EPOCH" -ge "$PASS_EPOCH" ]; then
        AGE=$(awk -v a="$PASS_EPOCH" -v b="$NOW_EPOCH" 'BEGIN { printf "%.1fh", (b - a) / 3600 }')
    fi
fi

# --- classify ------------------------------------------------------------
# Precedence: resolved > worked > standing > held > awaiting-placement >
# not-ready (skipped when the ready read failed) > marker (flagged, never
# dropped) > recorded (flagged, never dropped) > idle; unreadable = the
# batched read did not return it (stays visible).
CENSUS=$(jq -n \
    --slurpfile beadfile "$BEADFILE" \
    --argjson ready "$READY_JSON" \
    --argjson gates "$GATES_JSON" \
    --argjson new "$NEW_JSON" \
    --argjson carried "$CARRIED_JSON" \
    --arg pass_at "$PASS_AT" \
    --arg checked_at "$NOW" \
    --arg age "$AGE" \
    --arg ready_state "$READY_STATE" \
    --arg gate_state "$GATE_STATE" '
  def meta: (.metadata // {});
  def mv($k): ((meta[$k] // "") | tostring);
  # The open human gates a listed bead waits on, through its own blocks edges:
  # gates_blocking, from $HUMAN_GATE_JQ.
  '"$HUMAN_GATE_JQ"'
  def held_by($b): $b | gates_blocking($gates);
  # Standing-record idioms (never claimable, never close): standing_kinds,
  # from standing-kinds.sh, the list liveness-sweep.sh classifies by.
  '"$STANDING_KINDS_JQ"'
  # awaiting_placement, from placement.sh, which asks has_dispatch_path from
  # dispatch-path.sh: the queue gc-helm.sh unplaced lists.
  '"$DISPATCH_PATH_JQ$PLACEMENT_JQ"'
  (($beadfile[0] // []) | map({key: .id, value: .}) | from_entries) as $by
  | (if $ready == null then null
     else ($ready | map({key: ., value: true}) | from_entries) end) as $readyset
  | def classify($id):
      ($by[$id]) as $b
      | (if $b == null then
           {verdict: "unreadable",
            detail: "not returned by the batched read (deleted, re-homed, or in another store)"}
         elif (($b.status // "") == "closed") then
           {verdict: "resolved",
            detail: ([("closed " + (($b.closed_at // "") | if . == "" then "at an unrecorded time" else . end))]
                     + (if ($b | mv("merge_result")) != "" then ["merge_result=" + ($b | mv("merge_result"))] else [] end)
                     + (if ($b | mv("pr_number"))   != "" then ["pr=" + ($b | mv("pr_number"))] else [] end))
                    | join("  ")}
         # A work bead under execution carries gc.execution_routed_to while
         # assignee and gc.routed_to are empty, so a worked test on those two
         # alone misreads in-flight work as idle and a sitting re-dispatches it.
         elif ((($b.assignee // "") != "") or (($b | mv("gc.routed_to")) != "") or (($b | mv("gc.execution_routed_to")) != "")) then
           {verdict: "worked",
            detail: ((if ($b.assignee // "") != "" then ["assignee=" + $b.assignee] else [] end)
                     + (if ($b | mv("gc.routed_to")) != "" then ["routed_to=" + ($b | mv("gc.routed_to"))] else [] end)
                     + (if ($b | mv("gc.execution_routed_to")) != "" then ["execution_routed_to=" + ($b | mv("gc.execution_routed_to"))] else [] end))
                    | join("  ")}
         elif ((standing_kinds | index($b | mv("task_kind"))) != null) then
           {verdict: "standing",
            detail: ("task_kind=" + ($b | mv("task_kind"))
                    + " — open, unrouted and unassigned by design; it never closes, and there is no disposition to make")}
         elif (((held_by($b) | length) > 0) or (($b | mv("triage.hold")) != "")) then
           {verdict: "held",
            detail: ((if ($b | mv("triage.hold")) != "" then ["triage.hold=" + ($b | mv("triage.hold"))] else [] end)
                     + (if (held_by($b) | length) > 0 then
                          ["human gate " + (held_by($b) | join(", ")) + " is open on it — a person owes this answer"]
                        else [] end))
                    | join("  ")}
         # Intake held it as new work for the placement sitting, and gc-helm.sh
         # unplaced lists it there, so this gate would put the same decision
         # on a second agenda. That queue lists the bead whether or not a
         # blocker holds it or a first reaction left a takeaway on it, so this
         # rule comes before the not-ready, marker, recorded and idle rules.
         elif ($b | awaiting_placement) then
           {verdict: "awaiting-placement",
            detail: ("placement=pending"
                     + (if ($b | mv("gc.takeaway")) != "" then "  gc.takeaway=" + ($b | mv("gc.takeaway")) else "" end))}
         elif ($readyset != null and (($readyset[$id] // false) == false)) then
           {verdict: "not-ready",
            detail: ("status=" + ($b.status // "?") + " — it left the ready set (a blocker, a gate, a park edge, or a status change)")}
         elif (($b | mv("merge_result")) != "") then
           {verdict: "marker",
            detail: ((["merge_result=" + ($b | mv("merge_result"))]
                     + (if ($b | mv("pr_number")) != "" then ["pr=" + ($b | mv("pr_number"))] else [] end)
                     | join("  ")) + "  (PR liveness NOT re-checked — verify before routing)")}
         elif (($b | mv("gc.takeaway")) != "") then
           {verdict: "recorded",
            detail: ("gc.takeaway=" + ($b | mv("gc.takeaway"))
                     + (if ($b | mv("gc.takeaway_at")) != "" then "  (" + ($b | mv("gc.takeaway_at")) + ")" else "" end))}
         else
           {verdict: "idle", detail: ""}
         end)
      + {id: $id,
         title: ($b.title // ""),
         status: ($b.status // ""),
         kind: (((($b.issue_type // "") | tostring)
                 + (if ($b.priority // null) == null then "" else ("/p" + (($b.priority) | tostring)) end))
                | if . == "" then "?" else . end)}
  ;
  def live: [.[] | select(.verdict == "idle" or .verdict == "marker"
                          or .verdict == "recorded" or .verdict == "unreadable")] | length;
  ($new | map(classify(.))) as $newr
  | ($carried | map(classify(.))) as $carr
  | {pass_at: $pass_at, checked_at: $checked_at, age: $age,
     ready_state: $ready_state,
     gate_state: $gate_state,
     pr_liveness: "not-rechecked",
     new: $newr, carried: $carr,
     summary: {new_listed: ($newr | length), new_live: ($newr | live),
               carried_listed: ($carr | length), carried_live: ($carr | live)}}
')

if [ -z "$CENSUS" ]; then
    echo "liveness-recheck: classification FAILED — no census printed." >&2
    exit 1
fi

if [ "$WANT_JSON" -eq 1 ]; then
    printf '%s\n' "$CENSUS" | jq .
    exit 0
fi

printf '%s' "$CENSUS" | jq -r --argjson all "$WANT_ALL" '
  # Pads, never truncates: a clipped bead id is not a bead id.
  def pad($n): (($n - length) as $k | if $k > 0 then . + (" " * $k) else . end);
  def clip($n): if length > $n then (.[0:$n] + "…") else . end;
  # An empty bucket returns [], NEVER `empty` — an empty stream through the
  # enclosing `+` would suppress the whole report.
  def bucket($rows; $v; $label; $titles):
    ($rows | map(select(.verdict == $v))) as $sel
    | if ($sel | length) == 0 then []
      else
        ["  " + $label + " (" + (($sel | length) | tostring) + ")"]
        + (if $titles then
             ($sel | map("      " + (.id | pad(11)) + " " + (.kind | pad(8)) + " "
                         + (if .detail == "" then (.title // "") else (.detail | clip(140)) end)))
           else
             ["      " + ($sel | map(.id) | join(", "))]
           end)
      end;
  def section($rows; $name; $titles):
    if ($rows | length) == 0 then [] else
    ["", $name + " at pass time: " + (($rows | length) | tostring)
         + " listed -> " + (([$rows[] | select(.verdict == "idle" or .verdict == "marker"
                                               or .verdict == "recorded" or .verdict == "unreadable")] | length) | tostring)
         + " still live"]
    + bucket($rows; "idle";       "still idle — the live agenda"; $titles)
    + bucket($rows; "marker";     "carries a merge marker — verify the gate is live before routing"; true)
    + bucket($rows; "recorded";   "a sitting ended here — its takeaway is the record, not a wait; still on the agenda"; true)
    + bucket($rows; "unreadable"; "unreadable — still listed, nothing is hidden"; true)
    + bucket($rows; "resolved";   "resolved — closed since the pass; do NOT route"; true)
    + bucket($rows; "worked";     "now worked — someone has it"; true)
    + bucket($rows; "held";       "now held — a person owes an answer on it"; true)
    + bucket($rows; "awaiting-placement"; "waits for placement — the placement sitting places it (gc-helm.sh unplaced lists it); do NOT route it from here"; true)
    + bucket($rows; "standing";   "not work — a standing record, held by design; it was never dispositionable"; true)
    + bucket($rows; "not-ready";  "no longer ready — a blocker, gate or park appeared"; true)
    end;
  ([ "liveness re-check",
     "  pass cut " + (if .pass_at == "" then "(not given)" else .pass_at end)
       + " · re-checked " + .checked_at
       + (if .age == "" then "" else " · " + .age + " old" end),
     "  reads: bead state OK · ready set " + .ready_state + " · open human gates " + .gate_state
       + " · PR liveness NOT re-checked (a merge marker is flagged, never dropped)" ]
   + (if .ready_state == "unverified"
      then ["  WARNING: the ready read failed, so the not-ready rule was SKIPPED. A bead that has",
            "  since been parked or blocked still reads as idle here — nothing is hidden, but the",
            "  agenda may be longer than it truly is."]
      else [] end)
   + (if .gate_state == "unverified"
      then ["  WARNING: the human-gate read failed, so no bead reads as held. One a person is",
            "  answering right now is listed here — nothing is hidden, but check the item before",
            "  routing it."]
      else [] end)
   + section(.new; "NEW"; true)
   + section(.carried; "CARRIED"; ($all == 1))
   + ["",
      "Corrected census: " + (.summary.new_listed | tostring) + " new listed -> "
        + (.summary.new_live | tostring) + " live; "
        + (.summary.carried_listed | tostring) + " carried listed -> "
        + (.summary.carried_live | tostring) + " live.",
      "The message on the gate is the snapshot; this is the board. Work from this."]
  ) | .[]'
