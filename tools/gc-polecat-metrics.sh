#!/usr/bin/env bash
# gc-polecat-metrics.sh — read-only per-polecat metrics report over CLOSED work
# beads. Answers the operator's standing question (tk-4juzgd): how long polecats
# take, how many PRs they open, how many review/rework rounds a change costs,
# and how many tokens / dollars a session spent. Every column is a query over
# data Gas City already records; this tool collects nothing new and writes
# nothing (it reads the bead store and the local usage sink).
#
# One row per closed work bead (an anchor carrying a merge_result). Columns:
#   - completion time: closed_at minus the bead's start. started_at is null on
#     many beads, so start falls back to gc.claimed_at, then created_at, and the
#     row is flagged with which start it used rather than dropped.
#   - PR facts: pr_number, pr_url, merge_result, merged_sha.
#   - review / rework rounds: reviews counted from the gate-review beads on the
#     anchor's branch (task_kind=review, grouped by review_branch), reworks from
#     the "Rework PR#..." beads on that branch; check_set and dispatch_count are
#     surfaced when present.
#   - tokens + estimated cost: joined from the usage sink by session id.
#
# Token attribution, and why it needs a trace. The sink is keyed by session id;
# a bead carries gc.session_id only while a polecat holds it, and the refinery
# handoff clears it from the anchor (confirmed: ~18% of merged anchors still
# carry one). The build session survives on the workflow's load-context step,
# so this tool recovers it by tracing anchor <- input-convoy <- mol-polecat-work
# root -> load-context.gc.session_id (recoverable for ~89% of workflows), and
# falls back to the anchor's own gc.session_id when present. A bead whose
# session cannot be resolved shows tokens as n/a, counted in the coverage line.
#
# Attribution is per SESSION, not per bead: most polecat sessions build one bead
# but roughly one in five build several, and for those the token figure is the
# session total shared across its beads. Each row names its session(s) and how
# many beads each session built (session_beads); tokens_shared flags a row whose
# figure is shared. The durable fix — a per-bead usage affordance, or preserving
# the build session on the anchor at handoff — is tracked separately; until it
# lands, this trace is the join.
#
# Data source. The usage sink (.gc/usage.jsonl) is the only interface that
# serves historical per-session usage: `gc costs` has no --json and aggregates
# by run id city-wide, and the API's usage route serves only a live dashboard
# summary (a 5-minute recent-by-session window and city-wide today/24h totals,
# self-reported partial). So this tool reads the sink directly, filtered to the
# sessions the report needs. See specs/tk-6lvz29/per-polecat-metrics.md.
#
# Usage:
#   gc-polecat-metrics.sh [--since N] [--all] [--merge-result v,v] [--json]
#                         [--sink PATH]
#   --since N        include beads closed within the last N days (default 30)
#   --all            ignore the window; include every closed work bead
#   --merge-result   comma list of merge_result values to include
#                    (default: merged,pull_request,abandoned,held,pre_open_gate,duplicate)
#   --json           machine-readable object {meta, rows} instead of a table
#   --sink PATH      usage sink path (default: $GC_USAGE_SINK, else <city>/.gc/usage.jsonl)
#
# Scope note: `gc bd` answers from the store the current directory resolves, so
# the report covers the rig you run it in.
#
# Test seam: GC_POLECAT_METRICS_FIXTURE=<dir> replaces every live read with a
# canned file in <dir> (anchors.json, reviews.json, reworks.json,
# loadcontext.json, roots.json, convoys.json, usage.jsonl), so the test drives
# the tool with no live city. See tools/gc-polecat-metrics.test.sh.
#
# Read-only and stateless; recomputes from live bd / sink on every call.
# exit: 0 report emitted · 1 usage / argument error · 3 could not read anchors
set -uo pipefail

PROG="${0##*/}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../assets/scripts/bd-lib.sh
. "${GC_BD_LIB:-$REPO_ROOT/assets/scripts/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh" >&2; exit 1; }

SINCE_DAYS=30
ALL=0
JSON=0
SINK_OVERRIDE=""
MERGE_RESULTS="merged,pull_request,abandoned,held,pre_open_gate,duplicate"
FIXTURE="${GC_POLECAT_METRICS_FIXTURE:-}"

log() { printf '%s: %s\n' "$PROG" "$*" >&2; }
die() { log "$*"; exit 1; }

usage() { sed -n '2,/^set -uo pipefail/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --since) SINCE_DAYS="${2:-}"; shift 2 || die "--since needs a value" ;;
    --since=*) SINCE_DAYS="${1#*=}"; shift ;;
    --all) ALL=1; shift ;;
    --json) JSON=1; shift ;;
    --sink) SINK_OVERRIDE="${2:-}"; shift 2 || die "--sink needs a value" ;;
    --sink=*) SINK_OVERRIDE="${1#*=}"; shift ;;
    --merge-result) MERGE_RESULTS="${2:-}"; shift 2 || die "--merge-result needs a value" ;;
    --merge-result=*) MERGE_RESULTS="${1#*=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
done

case "$SINCE_DAYS" in (*[!0-9]*|'') die "--since must be a whole number of days" ;; esac

# --- usage sink path ------------------------------------------------------
resolve_sink() {
  [ -n "$SINK_OVERRIDE" ] && { printf '%s' "$SINK_OVERRIDE"; return; }
  [ -n "$FIXTURE" ] && [ -f "$FIXTURE/usage.jsonl" ] && { printf '%s' "$FIXTURE/usage.jsonl"; return; }
  [ -n "${GC_USAGE_SINK:-}" ] && { printf '%s' "$GC_USAGE_SINK"; return; }
  local city="${GC_CITY_PATH:-}" d="$PWD"
  if [ -z "$city" ]; then
    while [ "$d" != "/" ]; do [ -d "$d/.gc" ] && { city="$d"; break; }; d="$(dirname "$d")"; done
  fi
  printf '%s' "$city/.gc/usage.jsonl"
}

# --- live reads (each honors the fixture seam) ----------------------------
# A failed guarded read returns non-zero without printing; a caller that must
# not render a failed read as empty checks the exit status.
fetch_anchors() {
  if [ -n "$FIXTURE" ]; then cat "$FIXTURE/anchors.json" 2>/dev/null || echo '[]'; return; fi
  local v combined="[]" one rc any=0
  local IFS=,
  for v in $MERGE_RESULTS; do
    [ -n "$v" ] || continue
    one="$(bd_list --status=closed --metadata-field "merge_result=$v")"; rc=$?
    if [ "$rc" -ne 0 ]; then log "anchor read for merge_result=$v failed; skipping"; continue; fi
    any=1
    combined="$(printf '%s\n%s' "$combined" "$one" | jq -s -c 'add | unique_by(.id)')"
  done
  [ "$any" -eq 1 ] || return 1
  printf '%s' "$combined"
}

fetch_or_empty() {  # $1 fixture file, rest: bd_list args; empty array on a failed read
  local fx="$1"; shift
  if [ -n "$FIXTURE" ]; then cat "$FIXTURE/$fx" 2>/dev/null || echo '[]'; return; fi
  local out; out="$(bd_list "$@")" && printf '%s' "$out" || echo '[]'
}

# --- epoch cutoff for the window -----------------------------------------
if [ "$ALL" -eq 1 ]; then
  SINCE_EPOCH=0
else
  SINCE_EPOCH="$(date -u -d "${SINCE_DAYS} days ago" +%s 2>/dev/null || date -u -v-"${SINCE_DAYS}"d +%s)"
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-polecat-metrics.XXXXXX")" || die "mktemp failed"
trap 'rm -rf "$TMP"' EXIT

ANCHORS="$(fetch_anchors)" || die "could not read anchor beads (fail-closed; not reporting an empty set over a broken read)" 3
printf '%s' "$ANCHORS"            > "$TMP/anchors.json"
fetch_or_empty reviews.json     --metadata-field task_kind=review --status all  > "$TMP/reviews.json"
fetch_or_empty reworks.json     --title-contains "Rework PR" --status all       > "$TMP/reworks.json"
fetch_or_empty loadcontext.json --metadata-field gc.step_ref=mol-polecat-work.load-context --status all > "$TMP/loadcontext.json"
fetch_or_empty roots.json       --metadata-field gc.formula_name=mol-polecat-work --status all          > "$TMP/roots.json"
fetch_or_empty convoys.json     --type convoy --status all                      > "$TMP/convoys.json"

# --- phase A: join beads into rows (no tokens yet) + the session set ------
# Emits { rows: [...], sessions: [unique session ids across in-scope rows] }.
jq -n -c \
  --slurpfile anchors   "$TMP/anchors.json" \
  --slurpfile reviews   "$TMP/reviews.json" \
  --slurpfile reworks   "$TMP/reworks.json" \
  --slurpfile lc        "$TMP/loadcontext.json" \
  --slurpfile roots     "$TMP/roots.json" \
  --slurpfile convoys   "$TMP/convoys.json" \
  --argjson since_epoch "$SINCE_EPOCH" '
  def meta(k): .metadata[k] // null;
  def nz(k): (.metadata[k] // "") | if . == "" then null else . end;

  # root -> input convoy, convoy -> work bead (the convoy title names it)
  ($roots[0]   | map({key: .id, value: (.metadata["gc.input_convoy_id"] // "")}) | from_entries) as $root2convoy |
  ($convoys[0] | map({key: .id, value: (.title | sub("^input convoy for +";"") | gsub("^ +| +$";""))}) | from_entries) as $convoy2wb |

  # work bead -> [build sessions], traced through every load-context step
  (reduce $lc[0][] as $s ({};
     ($s.metadata["gc.root_bead_id"] // "")       as $r  |
     ($root2convoy[$r] // "")                      as $cv |
     ($convoy2wb[$cv] // "")                       as $wb |
     ($s.metadata["gc.session_id"] // "")          as $sid|
     if ($wb|length) > 0 and ($sid|length) > 0 then .[$wb] += [$sid] else . end)
   | map_values(unique)) as $wb2sessions |

  # session -> how many distinct work beads it built (global), for the caveat
  (reduce ($wb2sessions | to_entries[]) as $e ({};
     reduce ($e.value[]) as $sid (.; .[$sid] += [$e.key]))
   | map_values(unique | length)) as $session2beads |

  # session name, from load-context
  ($lc[0] | map(select((.metadata["gc.session_id"] // "") != "")
                 | {key: .metadata["gc.session_id"], value: (.metadata["gc.session_name"] // "")})
          | from_entries) as $session2name |

  # reviews grouped by branch, broken down by check
  (reduce $reviews[0][] as $r ({};
     ($r.metadata.review_branch // "") as $b |
     if ($b|length) > 0 then .[$b] += [ ($r.metadata.check_name // "?") ] else . end)) as $branch2reviews |
  (reduce $reworks[0][] as $r ({};
     ($r.metadata.branch // "") as $b |
     if ($b|length) > 0 then .[$b] += [1] else . end)) as $branch2reworks |

  [ $anchors[0][]
    | select((.closed_at // "") != "")
    | select((.closed_at | fromdateiso8601? // 0) >= $since_epoch)
    | . as $a
    | (.metadata.branch // "")                              as $branch
    | ($wb2sessions[.id] // [])                             as $traced
    | (if (nz("gc.session_id")) then [ .metadata["gc.session_id"] ] else [] end) as $stamped
    | (($traced + $stamped) | unique)                       as $sessions
    | (.started_at // null)                                 as $started
    | (if $started then {t:$started, src:"started_at"}
       elif meta("gc.claimed_at") then {t: meta("gc.claimed_at"), src:"claimed_at"}
       else {t: .created_at, src:"created_at"} end)         as $start
    | (($a.closed_at | fromdateiso8601? // null)) as $ce
    | (($start.t    | fromdateiso8601? // null))  as $se
    | {
        bead: .id,
        title: .title,
        merge_result: meta("merge_result"),
        pr_number: (meta("pr_number")),
        pr_url: meta("pr_url"),
        merged_sha: nz("merged_sha"),
        merged_target: nz("merged_target"),
        check_set: nz("check_set"),
        dispatch_count: (nz("dispatch_count")),
        created_at: .created_at,
        started_at: $started,
        start_at: $start.t,
        start_source: $start.src,
        closed_at: .closed_at,
        duration_seconds: (if $ce and $se then ($ce - $se) else null end),
        reviews: (($branch2reviews[$branch] // []) | length),
        reviews_by_check: (($branch2reviews[$branch] // []) | group_by(.) | map({(.[0]): length}) | add),
        reworks: (($branch2reworks[$branch] // []) | length),
        branch: $branch,
        sessions: $sessions,
        session_names: ($sessions | map($session2name[.] // null)),
        session_beads: ($sessions | map($session2beads[.] // 1) | max // null),
        tokens_shared: (($sessions | map($session2beads[.] // 1) | max // 1) > 1)
      }
  ]
  | sort_by(.closed_at) | reverse
  | { rows: ., sessions: ([.[].sessions[]] | unique) }
' > "$TMP/phaseA.json" || die "join phase failed"

# --- phase B: aggregate the sink for exactly the sessions we need ----------
SINK="$(resolve_sink)"
jq -r '.sessions[]' "$TMP/phaseA.json" > "$TMP/ids.txt"
SINK_AVAILABLE=1
if [ -s "$TMP/ids.txt" ] && [ -f "$SINK" ]; then
  WANT="$(jq -c '.sessions | map({key:., value:true}) | from_entries' "$TMP/phaseA.json")"
  # grep pre-filters the 100s of MB sink to candidate lines; a literal id can
  # appear in another field, so jq re-checks (.session_id // .run_id) exactly.
  { grep -F -f "$TMP/ids.txt" "$SINK" || true; } \
    | jq -s -c --argjson want "$WANT" '
        [ .[] | select(.kind=="model") | . as $r | (($r.session_id // $r.run_id) // "") as $s
          | select($want[$s]) | {s:$s, i:(.input_tokens//0), o:(.output_tokens//0),
            cr:(.cache_read_tokens//0), cc:(.cache_creation_tokens//0), cost:(.cost_usd_estimate//0)} ]
        | group_by(.s)
        | map({key:.[0].s, value:{input_tokens:(map(.i)|add), output_tokens:(map(.o)|add),
            cache_read_tokens:(map(.cr)|add), cache_creation_tokens:(map(.cc)|add),
            cost_usd_estimate:(map(.cost)|add), records:length}})
        | from_entries' > "$TMP/usage.json" || echo '{}' > "$TMP/usage.json"
else
  [ -f "$SINK" ] || SINK_AVAILABLE=0
  echo '{}' > "$TMP/usage.json"
fi

# --- phase C: fold per-session usage into each row, then render ------------
jq -n -c \
  --slurpfile a "$TMP/phaseA.json" \
  --slurpfile u "$TMP/usage.json" '
  ($u[0]) as $usage |
  ($a[0].rows | map(
    . as $row
    | [ .sessions[] | $usage[.] | select(. != null) ] as $hits
    | .tokens = (if ($hits|length) > 0 then {
          input_tokens:    ([$hits[].input_tokens]    | add),
          output_tokens:   ([$hits[].output_tokens]   | add),
          cache_read_tokens:([$hits[].cache_read_tokens]| add),
          cache_creation_tokens:([$hits[].cache_creation_tokens]| add),
          cost_usd_estimate:([$hits[].cost_usd_estimate]| add),
          records:         ([$hits[].records]         | add)
        } else null end)
  )) as $rows |
  { rows: $rows,
    meta: {
      total: ($rows|length),
      token_resolved: ([$rows[] | select(.tokens != null)] | length),
      token_unresolved: ([$rows[] | select(.tokens == null)] | length)
    }
  }
' > "$TMP/final.json" || die "render phase failed"

if [ "$JSON" -eq 1 ]; then
  jq -c \
    --arg sink "$SINK" --argjson sink_ok "$SINK_AVAILABLE" \
    --arg since "$SINCE_DAYS" --argjson all "$ALL" \
    '.meta += {sink:$sink, sink_available:($sink_ok==1), window_days:($since|tonumber), all:($all==1),
      attribution:"token/cost is per-session; a session may build >1 bead (session_beads), so a shared figure repeats across those rows"}
     | {meta, rows}' "$TMP/final.json"
  exit 0
fi

# Human table.
RANGE="closed in the last ${SINCE_DAYS}d"; [ "$ALL" -eq 1 ] && RANGE="all closed work beads"
printf 'Per-polecat metrics — %s\n' "$RANGE"
printf 'Token/cost is per SESSION (a session may build >1 bead; shared figure repeats). Session via load-context trace or anchor stamp.\n'
[ "$SINK_AVAILABLE" -eq 0 ] && printf 'WARNING: usage sink not found at %s — token/cost columns are n/a.\n' "$SINK"
printf '\n'
jq -r '
  def pad(n): (. // "") | tostring | (. + (" " * (n - length)))[:n];
  def dur: if . == null then "?" else
      (./86400|floor) as $d | ((. % 86400)/3600|floor) as $h | ((. % 3600)/60|floor) as $m
      | (if $d>0 then "\($d)d\($h)h" elif $h>0 then "\($h)h\($m)m" else "\($m)m" end) end;
  def num: if . == null then "" else (.|tostring) end;
  "\("BEAD"|pad(12)) \("PR"|pad(6)) \("RESULT"|pad(13)) \("DUR"|pad(7)) \("RVW"|pad(4)) \("RWK"|pad(4)) \("SESSION"|pad(14)) \("OUT_TOK"|pad(10)) \("COST"|pad(9)) SHARED",
  (.rows[] |
    "\(.bead|pad(12)) \((.pr_number|num)|pad(6)) \(.merge_result|pad(13)) \(.duration_seconds|dur|pad(7)) \((.reviews|num)|pad(4)) \((.reworks|num)|pad(4)) \((.sessions[0] // "n/a")|pad(14)) \((if .tokens then .tokens.output_tokens else "n/a" end)|tostring|pad(10)) \((if .tokens then ("$" + (.tokens.cost_usd_estimate|.*100|round/100|tostring)) else "n/a" end)|pad(9)) \(if .tokens_shared then "shared(\(.session_beads))" else "" end)"
  ),
  "",
  "Coverage: token/cost resolved for \(.meta.token_resolved)/\(.meta.total) beads (\(.meta.token_unresolved) n/a — session not recoverable)."
' "$TMP/final.json"
