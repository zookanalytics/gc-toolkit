#!/usr/bin/env bash
# liveness-recheck.sh — re-validate a liveness-sweep visit's census at CLAIM
# time. The visit body is a snapshot cut at pass time and a sitting routinely
# claims it a day or more later. Three batched bead reads re-derive every
# listed id's class and print a corrected census.
# Bead state only — no network: a merge_result marker and a recorded takeaway
# are FLAGGED for the sitting (never grounds for dropping a bead), and every
# failure path leaves a bead VISIBLE (a failed batched read prints NO census;
# a failed ready read skips the not-ready rule and says `unverified`; a failed
# demand read holds nothing and says so; an unreturned id gets its own
# `unreadable` bucket, counted into the live agenda).
# Callers: the converse prep step, via the visit.recheck stamp
# liveness-sweep.sh writes on each batch visit.
# Usage:
#   liveness-recheck.sh <visit-bead-id> [--all] [--json]
#   liveness-recheck.sh --ids <id[,id ...]> [--all] [--json]
# With a visit id it reads sweep.new_ids / sweep.carried_ids /
# sweep.carried_promoted_ids / sweep.pass_at. The promoted slice is the bounded
# set the sweep rotated back into the agenda this pass; it prints as its own
# titled RE-EXAMINED section so a sitting sees those beads by title from the
# census alone, which is the board the claim-time hook works from.
#   --all   also enumerate the REST of the carried backlog with titles; the
#           promoted slice is always titled, and without --all the rest stay bare
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

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

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
PROMOTED_RAW=""

if [ -n "$VISIT" ] && [ -n "$IDS_ARG" ]; then
    echo "liveness-recheck: pass a visit id OR --ids, not both" >&2
    exit 2
fi

if [ -n "$VISIT" ]; then
    VISIT_JSON=$(gc bd show "$VISIT" --json 2>/dev/null | scrub)
    if ! printf '%s' "$VISIT_JSON" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
        echo "liveness-recheck: cannot read visit $VISIT — nothing re-checked" >&2
        exit 1
    fi
    VISIT_META=$(printf '%s' "$VISIT_JSON" | jq -c '.[0].metadata // {}')
    NEW_RAW=$(printf   '%s' "$VISIT_META" | jq -r '.["sweep.new_ids"]     // ""')
    CARRIED_RAW=$(printf '%s' "$VISIT_META" | jq -r '.["sweep.carried_ids"] // ""')
    PROMOTED_RAW=$(printf '%s' "$VISIT_META" | jq -r '.["sweep.carried_promoted_ids"] // ""')
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
PROMOTED_IDS=$(split_ids "$PROMOTED_RAW")
CARRIED_IDS=$(split_ids "$CARRIED_RAW")
# The agenda outranks the background, and each id is listed once: a NEW id wins
# over a promoted or carried copy, and a promoted (re-examined this pass) id wins
# over a plain carried copy. The promoted slice is a subset of the carried set,
# so it is removed from the bare carried list and rendered as its own titled
# section — this is what stops the claim-time census from collapsing the rotated
# slice back into the untitled carried block, where a promoted bead reads as a
# bare id a sitting skips and so is never re-examined.
if [ -n "$NEW_IDS" ] && [ -n "$PROMOTED_IDS" ]; then
    PROMOTED_IDS=$(printf '%s\n' "$PROMOTED_IDS" | grep -Fxv -f <(printf '%s\n' "$NEW_IDS") || true)
fi
HIGHER_IDS=$(printf '%s\n%s\n' "$NEW_IDS" "$PROMOTED_IDS" | awk 'NF && !seen[$0]++')
if [ -n "$HIGHER_IDS" ] && [ -n "$CARRIED_IDS" ]; then
    CARRIED_IDS=$(printf '%s\n' "$CARRIED_IDS" | grep -Fxv -f <(printf '%s\n' "$HIGHER_IDS") || true)
fi

ALL_IDS=$(printf '%s\n%s\n%s\n' "$NEW_IDS" "$PROMOTED_IDS" "$CARRIED_IDS" | awk 'NF && !seen[$0]++')
if [ -z "$ALL_IDS" ]; then
    echo "liveness-recheck: no ids to re-check"
    exit 0
fi
ID_CSV=$(printf '%s' "$ALL_IDS" | paste -sd, -)

to_json_array() { printf '%s' "${1:-}" | jq -R . | jq -sc 'map(select(length > 0))'; }
NEW_JSON=$(to_json_array "$NEW_IDS")
PROMOTED_JSON=$(to_json_array "$PROMOTED_IDS")
CARRIED_JSON=$(to_json_array "$CARRIED_IDS")

# --- read 1: every listed bead in ONE call, closed ones included (--all is
# what makes the resolved bucket possible). Into a FILE: hundreds of rows on
# argv would meet ARG_MAX as a truncation rather than an error.
BEADFILE=$(mktemp)
trap 'rm -f "$BEADFILE"' EXIT
gc bd list --id "$ID_CSV" --all --brief --json --limit=0 2>/dev/null | scrub > "$BEADFILE"
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
READY_RAW=$(gc bd ready --unassigned --limit=0 --json 2>/dev/null | scrub)
if printf '%s' "$READY_RAW" | jq -e 'type == "array"' >/dev/null 2>&1; then
    READY_JSON=$(printf '%s' "$READY_RAW" | jq -c '[.[].id]')
else
    READY_STATE=unverified
    READY_JSON=null
fi

# --- read 3: the open demands, in one key-existence query ---------------------
# What a person still owes is its own bead (`gc-helm.sh demand`), stamped
# gc.demand_for=<gated bead>. That is the hold; `gc.takeaway` is the record of
# a sitting, which nothing clears, so it cannot say whether anyone is coming
# back. A demand also blocks its gated bead, which is why the not-ready rule
# usually catches this first — this read names the person's wait outright, and
# still sees the demand whose blocks edge did not land.
# Best-effort like the ready set: unread means no bead is held, which lists
# beads rather than hiding them.
DEMAND_STATE=verified
DEMAND_RAW=$(gc bd list --has-metadata-key gc.demand_for \
    --status=open,in_progress,blocked,deferred,hooked,pinned --limit=0 --json 2>/dev/null | scrub)
if printf '%s' "$DEMAND_RAW" | jq -e 'type == "array"' >/dev/null 2>&1; then
    DEMAND_JSON=$(printf '%s' "$DEMAND_RAW" | jq -c '
      [ .[] | {id, for: ((.metadata["gc.demand_for"] // "") | tostring)} | select(.for != "") ]
      | group_by(.for) | map({key: .[0].for, value: (map(.id) | join(", "))}) | from_entries')
else
    DEMAND_STATE=unverified
    DEMAND_JSON='{}'
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
# the ready read failed) > marker (flagged, never dropped) > recorded
# (flagged, never dropped) > idle; unreadable = the batched read did not
# return it (stays visible).
CENSUS=$(jq -n \
    --slurpfile beadfile "$BEADFILE" \
    --argjson ready "$READY_JSON" \
    --argjson demandby "$DEMAND_JSON" \
    --argjson new "$NEW_JSON" \
    --argjson promoted "$PROMOTED_JSON" \
    --argjson carried "$CARRIED_JSON" \
    --arg visit "$VISIT" \
    --arg subject "$SUBJECT" \
    --arg pass_at "$PASS_AT" \
    --arg checked_at "$NOW" \
    --arg age "$AGE" \
    --arg ready_state "$READY_STATE" \
    --arg demand_state "$DEMAND_STATE" '
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
         elif ((($demandby[$id] // "") != "") or (($b | mv("triage.hold")) != "")) then
           {verdict: "held",
            detail: ((if ($b | mv("triage.hold")) != "" then ["triage.hold=" + ($b | mv("triage.hold"))] else [] end)
                     + (if ($demandby[$id] // "") != "" then
                          ["demand " + $demandby[$id] + " is open on it — a person owes this answer"]
                        else [] end))
                    | join("  ")}
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
  | ($promoted | map(classify(.))) as $prom
  | ($carried | map(classify(.))) as $carr
  | {visit: $visit, subject: $subject,
     pass_at: $pass_at, checked_at: $checked_at, age: $age,
     ready_state: $ready_state,
     demand_state: $demand_state,
     pr_liveness: "not-rechecked",
     new: $newr, promoted: $prom, carried: $carr,
     summary: {new_listed: ($newr | length), new_live: ($newr | live),
               promoted_listed: ($prom | length), promoted_live: ($prom | live),
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
    + bucket($rows; "standing";   "not work — a standing record, held by design; it was never dispositionable"; true)
    + bucket($rows; "not-ready";  "no longer ready — a blocker, gate or park appeared"; true)
    end;
  ([ "liveness re-check — visit " + (if .visit == "" then "(ad-hoc id list)" else .visit end)
       + (if .subject == "" then "" else " · subject " + .subject end),
     "  pass cut " + (if .pass_at == "" then "(unstamped)" else .pass_at end)
       + " · re-checked " + .checked_at
       + (if .age == "" then "" else " · " + .age + " old" end),
     "  reads: bead state OK · ready set " + .ready_state + " · open demands " + .demand_state
       + " · PR liveness NOT re-checked (a merge marker is flagged, never dropped)" ]
   + (if .ready_state == "unverified"
      then ["  WARNING: the ready read failed, so the not-ready rule was SKIPPED. A bead that has",
            "  since been parked or blocked still reads as idle here — nothing is hidden, but the",
            "  agenda may be longer than it truly is."]
      else [] end)
   + (if .demand_state == "unverified"
      then ["  WARNING: the open-demand read failed, so no bead reads as held. One a person is",
            "  answering right now is listed here — nothing is hidden, but check the item before",
            "  routing it."]
      else [] end)
   + section(.new; "NEW"; true)
   + section(.promoted; "RE-EXAMINED (rotated in from the carried backlog)"; true)
   + section(.carried; "CARRIED"; ($all == 1))
   + ["",
      "Corrected census: " + (.summary.new_listed | tostring) + " new listed -> "
        + (.summary.new_live | tostring) + " live; "
        + (.summary.promoted_listed | tostring) + " re-examined -> "
        + (.summary.promoted_live | tostring) + " live; "
        + (.summary.carried_listed | tostring) + " carried listed -> "
        + (.summary.carried_live | tostring) + " live.",
      "The visit body is the snapshot; this is the board. Work from this."]
  ) | .[]'
