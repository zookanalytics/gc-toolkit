#!/usr/bin/env bash
# learning-recurrence.sh — the feedback-learning loop's success metric.
# Repeat feedback is the honest measure: if the loop works, the same
# correction stops coming back. Reads observation beads across every store,
# collapses exact duplicate captures, and reports two numbers plus the
# coverage that qualifies them.
#   learning-recurrence.sh [--window-days N] [--json]
#   learning-recurrence.sh --inventory [--ref <git-ref>]
# Runs standalone — it needs no distiller run and no order. The distiller
# echoes it at the end of a run; with the distiller disabled this script IS
# how the metric is read.
# Exit: 0 report written · 1 a store was unreadable (no partial number) · 2 usage
set -uo pipefail

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

usage() {
  cat >&2 <<'U'
usage: learning-recurrence.sh [--window-days N] [--json] [--repo PATH]
       learning-recurrence.sh --inventory [--ref <git-ref>] [--repo PATH]

  --window-days  comparison window in days; the report contrasts it with the
                 window immediately before it (default 30)
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

warn() { echo "learning-recurrence: $*" >&2; }

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
# formulas/mol-review.toml is the review-rubric carrier: its anchors sit in
# a TOML comment ledger, not in the step description a reviewer reads.
inventory_files() {
  if [ -n "$REF" ]; then
    git -C "$REPO" ls-tree -r --name-only "$REF" 2>/dev/null \
      | grep -E '^(template-fragments/(learned-conventions-|operator-profile|work-quality|learning-exemplars)|formulas/mol-review\.toml$)'
  else
    local f
    for f in "$REPO"/template-fragments/learned-conventions-*.template.md \
             "$REPO"/template-fragments/operator-profile.template.md \
             "$REPO"/template-fragments/work-quality.template.md \
             "$REPO"/template-fragments/learning-exemplars.template.md \
             "$REPO"/formulas/mol-review.toml; do
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
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
RIGSET="$TMP/rigs"
gc rig list --json 2>/dev/null \
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
  jq --arg rig "$R" '[.[] | {
        id, created_at,
        rig: $rig,
        provenance: (.metadata["obs.provenance"] // ""),
        category:   (.metadata["obs.category"]   // ""),
        pattern:    (.metadata["obs.distilled"]  // ""),
        source:     (.metadata["obs.source"]     // "")
      }]' "$RAW" > "$RAW.norm"
  jq -s 'add' "$OBS" "$RAW.norm" > "$OBS.next" && mv "$OBS.next" "$OBS"
done < "$RIGSET"

emit_inventory > "$TMP/inventory.tsv"

# One event per correction. Observations with no provenance key stand alone
# rather than collapsing into each other.
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
  | ($now - (2 * $span))           as $p_start
  | ($obs[0] // [])                as $all
  | ($all | length)                as $raw_count

  # Two observations are one correction when they share a provenance key AND
  # a category: the self-report and the miner reading of one event. A
  # provenance key can name a whole turn, and a turn carries several distinct
  # corrections, so provenance alone is not the key. The survivor keeps the
  # earliest capture time and any attribution the group carries — the
  # distiller stamps obs.distilled on one member, not on all of them.
  # \u001f cannot appear in a value: the reader above strips control
  # characters from every store.
  | ( $all
      | map(. + {ts: (.created_at | epoch)})
      | map(select(.ts != null))
      | group_by(if .provenance == "" then "id:" + .id
                 else "prov:" + .provenance + "\u001f" + .category end)
      | map( (sort_by(.ts) | .[0])
             + {pattern: ((map(.pattern) | map(select(. != "")) | first) // "")} ) ) as $events

  | ($events | map(select(.ts >= $w_start)))                       as $window_ev
  | ($events | map(select(.ts >= $p_start and .ts < $w_start)))    as $prior_ev

  # M1 — repeat feedback by category. obs.category is stamped at capture, so
  # this half survives the distiller being disabled. An event is a REPEAT when
  # an earlier event already carried its category: the correction has been
  # made before. Anchoring on the corpus rather than on the window boundary
  # keeps the number readable on a corpus younger than two windows.
  | ( $events | map(select(.category != ""))
      | group_by(.category)
      | map({key: .[0].category, value: (map(.ts) | min)})
      | from_entries )                                             as $cat_first
  | def repeats($set): $set | map(select(.category != "" and $cat_first[.category] < .ts));
    ($window_ev | map(select(.category != "")))                    as $w_cat
  | (repeats($window_ev))                                          as $w_repeat
  | ($prior_ev  | map(select(.category != "")))                    as $p_cat
  | (repeats($prior_ev))                                           as $p_repeat

  # obs.category is a free slug minted at capture. When nearly every event
  # mints its own, M1 under-counts recurrence that a human would see, so the
  # report states the fragmentation beside the rate instead of letting a low
  # number read as a healthy loop.
  | ($events | map(select(.category != "")))                       as $all_cat
  | ($all_cat | map(.category) | unique | length)                  as $distinct_cats

  # M2 — post-adoption recurrence, attributable only through obs.distilled.
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

  # Coverage qualifies M2: an undistilled observation cannot be attributed to
  # any rule, so a zero recurrence count over an unattributed window means
  # "not measured", not "no recurrence".
  | ($window_ev | map(select(.pattern != "")) | length)            as $w_attributed

  | {
      corpus: {
        observations: $raw_count,
        events_after_dedup: ($events | length),
        stores: ($all | map(.rig) | unique | length)
      },
      window_days: $window,
      m1_category_repeat: {
        window:  {events: ($window_ev|length), categorised: ($w_cat|length), repeats: ($w_repeat|length),
                  rate: (if ($w_cat|length) == 0 then null else (($w_repeat|length) / ($w_cat|length)) end)},
        prior:   {events: ($prior_ev|length), categorised: ($p_cat|length), repeats: ($p_repeat|length),
                  rate: (if ($p_cat|length) == 0 then null else (($p_repeat|length) / ($p_cat|length)) end)},
        fragmentation: {categorised: ($all_cat|length), distinct: $distinct_cats,
                        events_per_category: (if $distinct_cats == 0 then null else (($all_cat|length) / $distinct_cats) end)},
        key_discriminating: (if $distinct_cats == 0 then null
                             else ((($all_cat|length) / $distinct_cats) >= 1.5) end),
        top_repeating: ( $w_repeat | group_by(.category)
                         | map({category: .[0].category, count: length})
                         | sort_by(-.count) | .[0:8] )
      },
      m2_post_adoption: {
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
  def arrow($a; $b): if $a == null or $b == null then ""
                     elif $a < $b then "  (falling)" elif $a > $b then "  (rising)" else "  (flat)" end;
  "feedback-learning recurrence — \(.window_days)d window",
  "",
  "corpus: \(.corpus.observations) observations across \(.corpus.stores) stores, \(.corpus.events_after_dedup) events after duplicate-capture dedup",
  "",
  "M1  repeat feedback by category (measurable with the distiller off)",
  ( if .m1_category_repeat.key_discriminating == false then
      "      this window: \(.m1_category_repeat.window.repeats)/\(.m1_category_repeat.window.categorised) events repeat a category already seen  = rate withheld",
      "      prior window: \(.m1_category_repeat.prior.repeats)/\(.m1_category_repeat.prior.categorised)  = rate withheld"
    else
      "      this window: \(.m1_category_repeat.window.repeats)/\(.m1_category_repeat.window.categorised) events repeat a category already seen  = \(.m1_category_repeat.window.rate | pct)",
      "      prior window: \(.m1_category_repeat.prior.repeats)/\(.m1_category_repeat.prior.categorised)  = \(.m1_category_repeat.prior.rate | pct)\(arrow(.m1_category_repeat.window.rate; .m1_category_repeat.prior.rate))"
    end ),
  ( if (.m1_category_repeat.top_repeating | length) == 0 then "      no category recurred this window"
    else "      recurring: " + (.m1_category_repeat.top_repeating | map("\(.category) x\(.count)") | join(", ")) end),
  "      category spread: \(.m1_category_repeat.fragmentation.distinct) distinct categories over \(.m1_category_repeat.fragmentation.categorised) events",
  ( if .m1_category_repeat.key_discriminating == false
    then "      HIGH FRAGMENTATION: capture mints a fresh slug for nearly every event, so repeats is pinned to (categorised - distinct) and M1 restates the category spread instead of measuring recurrence. Its rate is withheld above; read the M2 pattern-bead clusters."
    else empty end),
  "",
  "M2  recurrence after adoption (needs obs.distilled — the distiller attributes it)",
  "      adopted entries: \(.m2_post_adoption.adopted_total), of which \(.m2_post_adoption.measurable) carry a rule:<pattern-bead> anchor",
  "      recurring after adoption: \(.m2_post_adoption.recurring)  (from the day after the adoption date)",
  "      window attribution: \(.m2_post_adoption.window_attribution.attributed)/\(.m2_post_adoption.window_attribution.events) events carry obs.distilled = \(.m2_post_adoption.window_attribution.coverage | pct) coverage",
  ( if (.m2_post_adoption.window_attribution.coverage // 0) < 0.5
    then "      LOW COVERAGE: most of this window is unattributed, so a low M2 reads as unmeasured, not as improvement."
    else empty end),
  ( .m2_post_adoption.rules
    | map(select(.measurable and .since_adoption > 0))
    | if length == 0 then empty
      else ["      rules with recurrence since adoption:"] + map("        \(.pattern) (\(.file), adopted \(.adopted)): \(.since_adoption)") | .[]
      end),
  ( .m2_post_adoption.rules
    | map(select(.measurable | not))
    | if length == 0 then empty
      else ["      unmeasurable (no pattern-bead anchor): " + (map(.file) | unique | join(", "))] | .[]
      end)
' "$TMP/report.json"
