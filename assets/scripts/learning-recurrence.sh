#!/usr/bin/env bash
# learning-recurrence.sh — the feedback-learning loop's success metric.
# Recurrence after adoption is the honest measure: if the loop works, a
# correction the city adopted a rule for stops coming back. Reads observation
# beads across every store, collapses duplicate captures of one event, and
# reports, for each adopted rule, the events the distiller attributed to its
# pattern since adoption, with the coverage that qualifies the count.
#   learning-recurrence.sh [--window-days N] [--json]
#   learning-recurrence.sh --inventory [--ref <git-ref>]
# Runs standalone — it needs no distiller run and no order. The distiller
# echoes it at the end of a run.
# Exit: 0 report written · 1 a store was unreadable (no partial number) · 2 usage
set -uo pipefail

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

usage() {
  cat >&2 <<'U'
usage: learning-recurrence.sh [--window-days N] [--json] [--repo PATH]
       learning-recurrence.sh --inventory [--ref <git-ref>] [--repo PATH]

  --window-days  the window, in days, whose attribution coverage the report
                 states (default 30)
  --json         emit the report as JSON instead of text
  --inventory    print the adopted-rule inventory (one TSV row per entry) and
                 exit; the retirement pass reads this instead of re-parsing
                 anchors itself
  --ref          git ref to read the adopted-rule carriers from, in report
                 mode as well as --inventory; default is the working tree
                 (the distiller passes origin/main)
  --repo         pack checkout to read fragments from; default is the
                 enclosing git worktree
U
}

_bd_lib_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$_bd_lib_dir/bd-lib.sh}" || { echo "cannot source bd-lib.sh beside this script" >&2; exit 1; }

WINDOW_DAYS=30; AS_JSON=""; INVENTORY=""; REF=""; REPO_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --window-days) WINDOW_DAYS="${2:-}"; shift 2 || { usage; exit 2; } ;;
    --json)        AS_JSON=1; shift ;;
    --inventory)   INVENTORY=1; shift ;;
    --ref)         REF="${2:-}"; shift 2 || { usage; exit 2; } ;;
    --repo)        REPO_ARG="${2:-}"; shift 2 || { usage; exit 2; } ;;
    -h|--help)     usage; exit 2 ;;
    *) warn "unknown argument '$1'"; usage; exit 2 ;;
  esac
done
case "$WINDOW_DAYS" in ''|*[!0-9]*) warn "--window-days must be a positive integer"; exit 2 ;; esac
[ "$WINDOW_DAYS" -gt 0 ] || { warn "--window-days must be a positive integer"; exit 2; }

REPO="$REPO_ARG"
[ -n "$REPO" ] || REPO=$(git rev-parse --show-toplevel 2>/dev/null)
[ -n "$REPO" ] || { warn "no pack checkout: pass --repo"; exit 2; }

# --- the adopted-rule inventory ------------------------------------------
# Anchors carry two shapes. `rule:<pattern-bead>` names the ledger row an
# entry descends from, which is what makes post-adoption recurrence
# attributable; an anchor without one is adopted but unmeasurable, and the
# report says so rather than counting it as zero recurrence.
# The review-rubric carrier is the correctness method's What to check list.
# Its anchors sit in skills/review-correctness/rubric-ledger.md, one line per
# amendment naming the dimension it amends, not in the method a reviewer reads.
inventory_files() {
  if [ -n "$REF" ]; then
    git -C "$REPO" ls-tree -r --name-only "$REF" 2>/dev/null \
      | grep -E '^(template-fragments/(learned-conventions-|operator-profile|work-quality|learning-exemplars)|skills/review-correctness/rubric-ledger\.md$)'
  else
    local f
    for f in "$REPO"/template-fragments/learned-conventions-*.template.md \
             "$REPO"/template-fragments/operator-profile.template.md \
             "$REPO"/template-fragments/work-quality-*.template.md \
             "$REPO"/template-fragments/learning-exemplars.template.md \
             "$REPO"/skills/review-correctness/rubric-ledger.md; do
      [ -r "$f" ] && printf '%s\n' "${f#"$REPO"/}"
    done
  fi
}

read_file() {
  if [ -n "$REF" ]; then git -C "$REPO" show "$REF:$1" 2>/dev/null
  else cat "$REPO/$1" 2>/dev/null; fi
}

# TSV: file, pattern-bead (or "-"), adopted date (or "-"), anchor text
emit_inventory() {
  local f line pattern adopted
  inventory_files | while IFS= read -r f; do
    [ -n "$f" ] || continue
    read_file "$f" | grep -o '<!--[^>]*adopted:[^>]*-->' | while IFS= read -r line; do
      # The seeded placeholder documents the format; it is not an adopted rule.
      case "$line" in *'rule:<pattern-bead>'*) continue ;; esac
      pattern=$(printf '%s' "$line" | sed -n 's/.*rule:\([A-Za-z0-9._-]*\).*/\1/p')
      adopted=$(printf '%s' "$line" | sed -n 's/.*adopted:\([0-9][0-9-]*\).*/\1/p')
      printf '%s\t%s\t%s\t%s\n' "$f" "${pattern:--}" "${adopted:--}" "$line"
    done
  done
}

if [ -n "$INVENTORY" ]; then
  emit_inventory
  exit 0
fi

# --- the observation corpus ----------------------------------------------
# Fail closed on an unreadable store: a recurrence number computed over part
# of the city reads as improvement.
TMP=$(mktemp -d "${TMPDIR:-/tmp}/gctk-learning-recurrence.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
RIGSET="$TMP/rigs"
"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/rig-map.sh" \
  | jq -r '.rigs[]? | select((.name // "") != "") | [.name, (.path // "")] | @tsv' 2>/dev/null > "$RIGSET"
if [ ! -s "$RIGSET" ]; then
  warn "rig enumeration returned nothing — refusing to report on a partial city"
  exit 1
fi

OBS="$TMP/obs.json"; echo '[]' > "$OBS"
TAB=$(printf '\t')
while IFS="$TAB" read -r R RPATH; do
  [ -n "$R" ] || continue
  RAW="$TMP/raw.$R.json"
  if [ -n "$RPATH" ]; then
    gc bd -C "$RPATH" list -l observation --status=closed --json --limit=0 > "$RAW" 2>/dev/null
  else
    gc bd --rig "$R" list -l observation --status=closed --json --limit=0 > "$RAW" 2>/dev/null
  fi
  scrub < "$RAW" > "$RAW.clean" 2>/dev/null && mv "$RAW.clean" "$RAW"
  if ! jq -e 'type=="array"' "$RAW" >/dev/null 2>&1; then
    warn "observation listing for store '$R' unreadable — refusing to report on a partial city"
    exit 1
  fi
  # `-l observation` narrows the listing; `task_kind` decides what an
  # observation is (docs/component-model.md I12). A bead the label brought in
  # without the metadata is some other kind of bead and does not enter the
  # corpus — counting it would inflate the corpus the coverage is read over.
  jq --arg rig "$R" '[.[]
      | select((((.metadata // {}).task_kind // "") | tostring) == "observation")
      | {
        id, created_at,
        rig: $rig,
        provenance: (.metadata["obs.provenance"] // ""),
        pattern:    (.metadata["obs.distilled"]  // "")
      }]' "$RAW" > "$RAW.norm"
  jq -s 'add' "$OBS" "$RAW.norm" > "$OBS.next" && mv "$OBS.next" "$OBS"
done < "$RIGSET"

emit_inventory > "$TMP/inventory.tsv"

# One event per provenance key and pattern: two observations are one event
# when they share a provenance key and the distiller attributed both to one
# pattern, such as the self-report and the miner's reading of one post,
# whatever category slug each capture minted. A provenance key can name a
# whole turn, and a turn's corrections in different patterns are an event in
# each. Observations the distiller has not judged yet share the empty pattern,
# and an observation with no provenance key stands alone.
# The report is process-local: $TMP is the mktemp -d above and the EXIT trap
# removes it. --json prints it to stdout; nothing here persists an artifact.
NOW=$(date -u +%s)
jq -n \
  --slurpfile obs "$OBS" \
  --argjson now "$NOW" \
  --argjson window "$WINDOW_DAYS" \
  --rawfile inventory "$TMP/inventory.tsv" '
  def epoch: (try (sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) catch null);

  ($window * 86400)                as $span
  | ($now - $span)                 as $w_start
  | ($obs[0] // [])                as $all
  | ($all | length)                as $raw_count

  # The survivor keeps the earliest capture time, so a post captured before
  # adoption and captured again after it is not recurrence.
  # \u001f cannot appear in a value: the reader above strips control
  # characters from every store.
  | ( $all
      | map(. + {ts: (.created_at | epoch)})
      | map(select(.ts != null))
      | group_by(if .provenance == "" then "id:" + .id
                 else "prov:" + .provenance + "\u001f" + .pattern end)
      | map(sort_by(.ts) | .[0]) )                                 as $events

  | ($events | map(select(.ts >= $w_start)))                       as $window_ev

  # Recurrence after adoption, attributable only through obs.distilled.
  | ( $inventory
      | split("\n") | map(select(length > 0))
      | map(split("\t"))
      | map({file: .[0], pattern: .[1], adopted: .[2]}) )          as $rules
  # An anchor records a date, not a moment, and the distiller stamps consumed
  # observations at proposal time — before merge. Same-day evidence predates
  # adoption as often as it follows it, so counting starts the day after.
  | ( $rules
      | map( . as $r
             | ($r.adopted + "T00:00:00Z" | epoch) as $adopted_day
             | (if $adopted_day == null then null else $adopted_day + 86400 end) as $adopted_ts
             | $r + {
                 measurable: ($r.pattern != "-" and $adopted_ts != null),
                 since_adoption: (
                   if $r.pattern == "-" or $adopted_ts == null then null
                   else ($events | map(select(.pattern == $r.pattern and .ts >= $adopted_ts)) | length)
                   end)
               } ) )                                               as $rule_rows

  # Coverage qualifies the count: an undistilled observation cannot be
  # attributed to any rule, so a zero recurrence count over an unattributed
  # window means "not measured", not "no recurrence".
  | ($window_ev | map(select(.pattern != "")) | length)            as $w_attributed

  | {
      corpus: {
        observations: $raw_count,
        events_after_dedup: ($events | length),
        stores: ($all | map(.rig) | unique | length)
      },
      window_days: $window,
      post_adoption: {
        rules: $rule_rows,
        adopted_total: ($rule_rows | length),
        measurable: ($rule_rows | map(select(.measurable)) | length),
        recurring:  ($rule_rows | map(select(.measurable and .since_adoption > 0)) | length),
        window_attribution: {
          events: ($window_ev|length), attributed: $w_attributed,
          coverage: (if ($window_ev|length) == 0 then null else ($w_attributed / ($window_ev|length)) end)
        }
      }
    }' > "$TMP/report.json"

if [ -n "$AS_JSON" ]; then
  cat "$TMP/report.json"
  exit 0
fi

jq -r '
  def pct: if . == null then "n/a" else ((. * 1000 | round) / 10 | tostring) + "%" end;
  "feedback-learning recurrence after adoption",
  "",
  "corpus: \(.corpus.observations) observations across \(.corpus.stores) stores, \(.corpus.events_after_dedup) events after duplicate-capture dedup",
  "",
  "recurrence after adoption (needs obs.distilled — the distiller attributes it)",
  "      adopted entries: \(.post_adoption.adopted_total), of which \(.post_adoption.measurable) carry a rule:<pattern-bead> anchor",
  "      recurring after adoption: \(.post_adoption.recurring)  (from the day after the adoption date)",
  "      window attribution, last \(.window_days)d: \(.post_adoption.window_attribution.attributed)/\(.post_adoption.window_attribution.events) events carry obs.distilled = \(.post_adoption.window_attribution.coverage | pct) coverage",
  ( if (.post_adoption.window_attribution.coverage // 0) < 0.5
    then "      LOW COVERAGE: most of this window is unattributed, so a low count reads as unmeasured, not as improvement."
    else empty end),
  ( .post_adoption.rules
    | map(select(.measurable and .since_adoption > 0))
    | if length == 0 then empty
      else ["      rules with recurrence since adoption:"] + map("        \(.pattern) (\(.file), adopted \(.adopted)): \(.since_adoption)") | .[]
      end),
  ( .post_adoption.rules
    | map(select(.measurable | not))
    | if length == 0 then empty
      else ["      unmeasurable (no pattern-bead anchor): " + (map(.file) | unique | join(", "))] | .[]
      end)
' "$TMP/report.json"
