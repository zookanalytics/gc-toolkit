#!/usr/bin/env bash
# liveness-recheck.sh — re-validate a liveness-sweep visit's census AT CLAIM
# TIME, so the sitting works the board as it is now rather than as it was at
# pass time (bead tk-gvas6).
#
# THE DEFECT. mol-liveness-sweep's classify step writes the census into the
# visit body at PASS time. The converse sitting reads that body whenever the
# visit is claimed, which is routinely a day or more later, and nothing
# re-checks it in between. Measured on visit 8 of tk-hok6w (visit tk-3qeq0):
# pass cut 2026-08-12T00:10Z reporting 10 new unnamed waits; the sitting read
# it 2026-08-13T17:45Z, ~41.5 hours later; FIVE of the ten had already merged
# AND deployed (tk-1u8mi #316, tk-7g37t #322, tk-xesf6 #325, tk-5ttye #328,
# tk-pe1hd #332 — the headline P0). 60% of the body was wrong on arrival,
# including the three items the body itself called "worth deciding first".
# Three of those five closed within two and a half hours of the pass, so the
# body was already half wrong long before anyone opened it.
#
# The cost is not wasted reading. A sitting that TRUSTS the body routes work
# that is already merged and burns a polecat on a no-op — already on this
# scope's record (visit 4 routed tk-yjtf, closed as a no-op 30 minutes later).
# A sitting that DISTRUSTS it spends its whole prep budget re-verifying claims
# a batched read settles in under a second.
#
# THE REMEDY. Two batched reads — every listed id in one `gc bd list --id`,
# plus the ready set — re-derive each id's class and print a corrected census.
# The sweep itself is unchanged; this runs at claim time, when the answer is
# still true. Measured on the 115 ids of that same visit: 0.15s + 0.19s.
#
# WHAT IT DOES NOT DO — and says so in its own output. It re-reads BEAD state
# only. It makes no network call, so it never re-checks whether a pull request
# is still open. A `merge_result` marker is therefore FLAGGED for the sitting
# to verify, never used to drop a bead. That asymmetry is deliberate and is
# the same bias the formula is built on (mol-liveness-sweep.toml: "a probe
# that cannot be read excludes nothing"): every uncertainty here leaves a bead
# VISIBLE. The inverse — a re-check that hides a bead on a signal it did not
# actually verify — would be a worse defect than the staleness it fixes,
# because a hidden bead has no next pass that surfaces it.
#
# The same bias governs every failure path:
#   - the batched bead read fails      -> print NO census at all, exit 1. A
#                                         partial census that looks complete
#                                         is the one output worse than none.
#   - the ready read fails             -> the not-ready rule is SKIPPED
#                                         entirely and the word `unverified`
#                                         is printed. Trusting a failed ready
#                                         read would classify every listed
#                                         bead as gated — hiding the whole
#                                         agenda behind a transient.
#   - an id the read did not return    -> its own `unreadable` bucket, counted
#                                         INTO the live agenda.
#
# Every verdict that takes a bead off the agenda — `resolved`, `worked`,
# `held`, `standing` — is a positive property read out of the same batched
# listing, never a probe, so no failure here can turn into a silent hide.
# `standing` is the newest of them (bead tk-rw2ra): the standing-record
# idioms (`task_kind=triage-subject`, `feedback-pattern`) are created open,
# unrouted and unassigned BY DESIGN and never close, so every other test here
# reads them as idle work — permanently, because no state change would ever
# retire them. It is its own verdict rather than a flavour of `held` because
# nobody is holding it and nothing changed since the pass: a sitting can
# route, gate, kill, park or hold a held bead, and can do none of those to
# this one. The list is deliberately the same one mol-liveness-sweep.toml
# holds in its classify block; adding an idiom means adding it to both, and
# liveness-recheck.test.sh fails if the two ever disagree.
#
# Usage:
#   liveness-recheck.sh <visit-bead-id> [--all] [--json]
#   liveness-recheck.sh --ids <id[,id ...]> [--all] [--json]
#
# With a visit id it reads the id lists the normalize step stamped on the
# visit (`sweep.new_ids` / `sweep.carried_ids`, plus `sweep.pass_at`) — the
# machine handle that exists precisely so nothing has to parse ids back out of
# prose. A visit filed before those stamps shipped carries none, and says so.
#
#   --all   also enumerate the carried ids that are still idle (by default the
#           carried section prints counts plus the ids that CHANGED, which is
#           the news; the unchanged carried ids are already in the visit body).
#   --json  emit the census as one JSON object instead of the report.
#
# Read-only: never writes a bead, never touches git, never calls the network.
#
# NOT set -e: every failure mode above is handled explicitly, and an errexit
# abort would skip the diagnostics that make the failure legible.
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

# bd emits stray control characters often enough to break jq (a single one kills
# the whole parse). Strip them, sparing TAB (\011) and NEWLINE (\012).
strip_ctrl() { tr -d '\000-\010\013\014\016-\037'; }

# Split a list on commas AND any whitespace, drop empties, keep first-seen order.
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
# A carried id that is also new is listed once, as new: the new set is the
# sitting's agenda and the carried set is background, so the more urgent
# classification wins the duplicate.
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

# --- read 1: every listed bead, in one call, closed ones included ------------
# --all is what makes the resolved bucket possible: without it a bead that
# closed since the pass simply vanishes from the answer and would be
# indistinguishable from one that was never there. Into a FILE, read back with
# --slurpfile: a large rig's candidate set is hundreds of rows, and pushing that
# through argv would meet ARG_MAX as a truncation rather than an error.
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

# --- classify ----------------------------------------------------------------
# Precedence is the whole design, so it is stated once here and nowhere else:
#
#   resolved   closed. Nothing else matters — do not route it.
#   worked     an assignee or a gc.routed_to appeared. Someone has it.
#   held       gc.takeaway or triage.hold appeared. A human is holding it.
#   not-ready  gone from the ready set: a blocker, a gate, or a park edge
#              appeared. SKIPPED ENTIRELY when the ready read failed.
#   marker     carries a merge_result but is otherwise still a candidate.
#              FLAGGED, never dropped: PR liveness is not re-checked here.
#   idle       unchanged — the live agenda.
#   unreadable the batched read did not return it. Stays visible.
#
# The order matters where a bead satisfies two: a closed bead that still
# carries a route reads as resolved, not worked, because the disposition a
# sitting would take differs (nothing vs. leave it alone).
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
  # The standing-record idioms, held-by-design class 4(a) — kept as ONE named
  # list here for the same reason mol-liveness-sweep.toml keeps it as one:
  # each is created open, unrouted and unassigned ON PURPOSE and is never
  # claimable, so every test below reads them as an idle bead, and they never
  # close (bead tk-rw2ra). Same strings as standing_kinds in that classify block.
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
            detail: "task_kind=" + ($b | mv("task_kind"))
                    + " — open, unrouted and unassigned by design; it never closes, and there is no disposition to make"}
         elif ((($b | mv("gc.takeaway")) != "") or (($b | mv("triage.hold")) != "")) then
           {verdict: "held",
            detail: ((if ($b | mv("triage.hold")) != "" then ["triage.hold=" + ($b | mv("triage.hold"))] else [] end)
                     + (if ($b | mv("gc.takeaway")) != "" then ["gc.takeaway=" + ($b | mv("gc.takeaway"))] else [] end))
                    | join("  ")}
         elif ($readyset != null and (($readyset[$id] // false) == false)) then
           {verdict: "not-ready",
            detail: "status=" + ($b.status // "?") + " — it left the ready set (a blocker, a gate, a park edge, or a status change)"}
         elif (($b | mv("merge_result")) != "") then
           {verdict: "marker",
            detail: (["merge_result=" + ($b | mv("merge_result"))]
                     + (if ($b | mv("pr_number")) != "" then ["pr=" + ($b | mv("pr_number"))] else [] end))
                    | join("  ") + "  (PR liveness NOT re-checked — verify before routing)"}
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
  # Pads, never truncates: a clipped bead id is not a bead id, and ids here run
  # from 8 to 12 characters (tk-1co, tk-yw3zb.19).
  def pad($n): (($n - length) as $k | if $k > 0 then . + (" " * $k) else . end);
  # A takeaway or hold reason is prose and runs to hundreds of characters. This
  # is a census, not the record — the full value is one `gc bd show` away.
  def clip($n): if length > $n then (.[0:$n] + "…") else . end;
  # An empty bucket returns [], NEVER `empty`: jq propagates an empty stream
  # through the enclosing `+`, so one absent bucket would silently suppress the
  # ENTIRE report — which is exactly how this printed nothing at all the first
  # time it ran.
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
