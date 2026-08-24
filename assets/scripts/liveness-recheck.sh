#!/usr/bin/env bash
# liveness-recheck.sh — re-validate a liveness-sweep visit's census at CLAIM
# time (bead tk-gvas6: 60% of one body was wrong on arrival). Two batched
# bead reads re-derive every listed id's class and print a corrected census.
# Bead state only — no network: a merge_result marker is FLAGGED for the
# sitting, never used to drop a bead, and every failure path leaves a bead
# VISIBLE (a failed batched read prints NO census; a failed ready read skips
# the not-ready rule and says `unverified`; an unreturned id gets its own
# `unreadable` bucket, counted into the live agenda).
# Callers: the converse prep step, via the visit.recheck stamp
# liveness-sweep.sh writes on each batch visit.
# Usage:
#   liveness-recheck.sh <visit-bead-id> [--all] [--json]
#   liveness-recheck.sh --ids <id[,id ...]> [--all] [--json]
# With a visit id it reads sweep.new_ids / sweep.carried_ids / sweep.pass_at.
#   --all   also enumerate carried ids that are still idle
#   --json  emit the census as one JSON object
# Read-only: never writes a bead, never touches git, never calls the network.
# Exit: 0 census printed · 1 unreadable · 2 usage · 3 visit carries no stamps.
# NOT set -e: every failure is handled explicitly, routed to the visible side.
set -uo pipefail

usage() {
    sed -n '/^# Usage:/,/^# Read-only/p' "$0" | sed 's/^# \{0,1\}//'
}

VISIT=""
IDS_ARG=""
WANT_JSON=0
WANT_ALL=0

while [ $# -gt 0 ]; do
    case "$1" in
        --json) WANT_JSON=1 ;;
        --all)  WANT_ALL=1 ;;
        --ids)
            if [ $# -lt 2 ]; then echo "liveness-recheck: --ids needs a value" >&2; exit 2; fi
            shift
            IDS_ARG="$1"
            ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "liveness-recheck: unknown flag: $1" >&2; usage >&2; exit 2 ;;
        *)
            if [ -n "$VISIT" ]; then echo "liveness-recheck: unexpected argument: $1" >&2; exit 2; fi
            VISIT="$1"
            ;;
    esac
    shift
done

command -v jq >/dev/null 2>&1 || { echo "liveness-recheck: jq is required" >&2; exit 1; }

# Strip control chars (they break jq), sparing TAB and NEWLINE.
strip_ctrl() { tr -d '\000-\010\013\014\016-\037'; }

# Split on commas/whitespace, drop empties, keep first-seen order.
split_ids() {
    printf '%s' "${1:-}" \
        | tr ',' ' ' \
        | awk '{ for (i = 1; i <= NF; i++) if (!seen[$i]++) print $i }'
}

PASS_AT=""
SUBJECT=""
NEW_RAW=""
CARRIED_RAW=""

if [ -n "$VISIT" ] && [ -n "$IDS_ARG" ]; then
    echo "liveness-recheck: pass a visit id OR --ids, not both" >&2
    exit 2
fi

if [ -n "$VISIT" ]; then
    VISIT_JSON=$(gc bd show "$VISIT" --json 2>/dev/null | strip_ctrl)
    if ! printf '%s' "$VISIT_JSON" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
        echo "liveness-recheck: cannot read visit $VISIT — nothing re-checked" >&2
        exit 1
    fi
    VISIT_META=$(printf '%s' "$VISIT_JSON" | jq -c '.[0].metadata // {}')
    NEW_RAW=$(printf   '%s' "$VISIT_META" | jq -r '.["sweep.new_ids"]     // ""')
    CARRIED_RAW=$(printf '%s' "$VISIT_META" | jq -r '.["sweep.carried_ids"] // ""')
    PASS_AT=$(printf   '%s' "$VISIT_META" | jq -r '.["sweep.pass_at"]     // ""')
    SUBJECT=$(printf   '%s' "$VISIT_META" | jq -r '.["gc.continuation_group"] // ""')
    if [ -z "$NEW_RAW" ] && [ -z "$CARRIED_RAW" ]; then
        echo "liveness-recheck: visit $VISIT carries no sweep.new_ids / sweep.carried_ids." >&2
        echo "  Either it is not a liveness-sweep visit, or it was filed before those stamps" >&2
        echo "  shipped. Re-check by hand with: liveness-recheck.sh --ids <ids from the body>" >&2
        exit 3
    fi
elif [ -n "$IDS_ARG" ]; then
    NEW_RAW="$IDS_ARG"
else
    echo "liveness-recheck: give a visit bead id, or --ids <id,...>" >&2
    usage >&2
    exit 2
fi

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
BEADFILE=$(mktemp)
trap 'rm -f "$BEADFILE"' EXIT
gc bd list --id "$ID_CSV" --all --brief --json --limit=0 2>/dev/null | strip_ctrl > "$BEADFILE"
if ! jq -e 'type == "array"' "$BEADFILE" >/dev/null 2>&1; then
    echo "liveness-recheck: the batched bead read FAILED — no census printed." >&2
    echo "  (gc bd list --id … --all --brief --json --limit=0 returned no JSON array; a bd" >&2
    echo "  without --id or --brief would fail exactly here.)" >&2
    echo "  Nothing in the visit body has been re-verified; treat its census as unchecked," >&2
    echo "  and re-run this before routing anything." >&2
    exit 1
fi

# --- read 2: the ready set (best-effort, never load-bearing) ------------------
READY_STATE=verified
READY_RAW=$(gc bd ready --unassigned --limit=0 --json 2>/dev/null | strip_ctrl)
if printf '%s' "$READY_RAW" | jq -e 'type == "array"' >/dev/null 2>&1; then
    READY_JSON=$(printf '%s' "$READY_RAW" | jq -c '[.[].id]')
else
    READY_STATE=unverified
    READY_JSON=null
fi

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
AGE=""
if [ -n "$PASS_AT" ]; then
    PASS_EPOCH=$(date -u -d "$PASS_AT" +%s 2>/dev/null || echo "")
    NOW_EPOCH=$(date -u +%s 2>/dev/null || echo "")
    if [ -n "$PASS_EPOCH" ] && [ -n "$NOW_EPOCH" ] && [ "$NOW_EPOCH" -ge "$PASS_EPOCH" ]; then
        AGE=$(awk -v a="$PASS_EPOCH" -v b="$NOW_EPOCH" 'BEGIN { printf "%.1fh", (b - a) / 3600 }')
    fi
fi

# --- classify ------------------------------------------------------------
# Precedence: resolved > worked > standing > held > not-ready (skipped when
# the ready read failed) > marker (flagged, never dropped) > idle;
# unreadable = the batched read did not return it (stays visible).
CENSUS=$(jq -n \
    --slurpfile beadfile "$BEADFILE" \
    --argjson ready "$READY_JSON" \
    --argjson new "$NEW_JSON" \
    --argjson carried "$CARRIED_JSON" \
    --arg visit "$VISIT" \
    --arg subject "$SUBJECT" \
    --arg pass_at "$PASS_AT" \
    --arg checked_at "$NOW" \
    --arg age "$AGE" \
    --arg ready_state "$READY_STATE" '
  def meta: (.metadata // {});
  def mv($k): ((meta[$k] // "") | tostring);
  # Standing-record idioms (never claimable, never close) — the SAME list as
  # standing_kinds in liveness-sweep.sh; liveness-recheck.test.sh pins the pair.
  def standing_kinds: ["triage-subject", "feedback-pattern"];
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
         elif ((($b.assignee // "") != "") or (($b | mv("gc.routed_to")) != "")) then
           {verdict: "worked",
            detail: ((if ($b.assignee // "") != "" then ["assignee=" + $b.assignee] else [] end)
                     + (if ($b | mv("gc.routed_to")) != "" then ["routed_to=" + ($b | mv("gc.routed_to"))] else [] end))
                    | join("  ")}
         elif ((standing_kinds | index($b | mv("task_kind"))) != null) then
           {verdict: "standing",
            detail: ("task_kind=" + ($b | mv("task_kind"))
                    + " — open, unrouted and unassigned by design; it never closes, and there is no disposition to make")}
         elif ((($b | mv("gc.takeaway")) != "") or (($b | mv("triage.hold")) != "")) then
           {verdict: "held",
            detail: ((if ($b | mv("triage.hold")) != "" then ["triage.hold=" + ($b | mv("triage.hold"))] else [] end)
                     + (if ($b | mv("gc.takeaway")) != "" then ["gc.takeaway=" + ($b | mv("gc.takeaway"))] else [] end))
                    | join("  ")}
         elif ($readyset != null and (($readyset[$id] // false) == false)) then
           {verdict: "not-ready",
            detail: ("status=" + ($b.status // "?") + " — it left the ready set (a blocker, a gate, a park edge, or a status change)")}
         elif (($b | mv("merge_result")) != "") then
           {verdict: "marker",
            detail: ((["merge_result=" + ($b | mv("merge_result"))]
                     + (if ($b | mv("pr_number")) != "" then ["pr=" + ($b | mv("pr_number"))] else [] end)
                     | join("  ")) + "  (PR liveness NOT re-checked — verify before routing)")}
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
  def live: [.[] | select(.verdict == "idle" or .verdict == "marker" or .verdict == "unreadable")] | length;
  ($new | map(classify(.))) as $newr
  | ($carried | map(classify(.))) as $carr
  | {visit: $visit, subject: $subject,
     pass_at: $pass_at, checked_at: $checked_at, age: $age,
     ready_state: $ready_state,
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
         + " listed -> " + (([$rows[] | select(.verdict == "idle" or .verdict == "marker" or .verdict == "unreadable")] | length) | tostring)
         + " still live"]
    + bucket($rows; "idle";       "still idle — the live agenda"; $titles)
    + bucket($rows; "marker";     "carries a merge marker — verify the gate is live before routing"; true)
    + bucket($rows; "unreadable"; "unreadable — still listed, nothing is hidden"; true)
    + bucket($rows; "resolved";   "resolved — closed since the pass; do NOT route"; true)
    + bucket($rows; "worked";     "now worked — someone has it"; true)
    + bucket($rows; "held";       "now held — a human is holding it"; true)
    + bucket($rows; "standing";   "not work — a standing record, held by design; it was never dispositionable"; true)
    + bucket($rows; "not-ready";  "no longer ready — a blocker, gate or park appeared"; true)
    end;
  ([ "liveness re-check — visit " + (if .visit == "" then "(ad-hoc id list)" else .visit end)
       + (if .subject == "" then "" else " · subject " + .subject end),
     "  pass cut " + (if .pass_at == "" then "(unstamped)" else .pass_at end)
       + " · re-checked " + .checked_at
       + (if .age == "" then "" else " · " + .age + " old" end),
     "  reads: bead state OK · ready set " + .ready_state
       + " · PR liveness NOT re-checked (a merge marker is flagged, never dropped)" ]
   + (if .ready_state == "unverified"
      then ["  WARNING: the ready read failed, so the not-ready rule was SKIPPED. A bead that has",
            "  since been parked or blocked still reads as idle here — nothing is hidden, but the",
            "  agenda may be longer than it truly is."]
      else [] end)
   + section(.new; "NEW"; true)
   + section(.carried; "CARRIED"; ($all == 1))
   + ["",
      "Corrected census: " + (.summary.new_listed | tostring) + " new listed -> "
        + (.summary.new_live | tostring) + " live; "
        + (.summary.carried_listed | tostring) + " carried listed -> "
        + (.summary.carried_live | tostring) + " live.",
      "The visit body is the snapshot; this is the board. Work from this."]
  ) | .[]'
