#!/usr/bin/env bash
# liveness-sweep.sh — the P3 exec pass, fully mechanical (no agent session).
# Job: classify every open bead in this rig as worked / gated / conversing /
# held-by-design / routed-and-claimable / machine residue — anything left is
# an UNNAMED WAIT — then file/refresh ONE batch triage visit (delta only)
# on the standing per-rig unnamed-waits subject via escalate.sh. Also owns
# the standing-subject recurrence: each task_kind=triage-subject bead gets a
# visit iff its scope set CHANGED and no visit is live.
# Replaces formulas/mol-liveness-sweep.toml + mol-triage-recurrence.toml.
# Caller: orders/liveness-sweep.toml (exec), after liveness-sweep-precheck.sh
# proves the delta non-empty; safe to run by hand.
# State: $GC_PACK_STATE_DIR/liveness-sweep/<rig>/ — `reported`, the delta
# baseline (comma-joined ids), beside `last-pass`, the cadence window. Both
# are keyed per rig the same way the precheck keys them. A pass that starts
# closes the window, and the precheck closes it too once it has proved there
# is no pass to start.
# Bias everywhere: an unreadable probe excludes nothing (re-report, never
# hide). Exit: 0 pass completed (filed or nothing to file), 1 aborted on an
# unreadable listing, 2 usage.
set -uo pipefail

PROG="liveness-sweep"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ESCALATE="${GC_ESCALATE_TOOL:-$HERE/escalate.sh}"
CALL_TIMEOUT="${LIVENESS_SWEEP_CALL_TIMEOUT:-45}"
KILL_AFTER="${LIVENESS_SWEEP_KILL_AFTER:-5}"
LIST_CAP="${LIVENESS_SWEEP_LIST_CAP:-20}"

DRY_RUN=0
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "$PROG: unexpected argument: $1" >&2; exit 2 ;;
    esac
    shift
done

command -v jq >/dev/null 2>&1 || { echo "$PROG: jq is required" >&2; exit 1; }

# --- per-rig state (same keying as liveness-sweep-precheck.sh) ---------------
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
if [ -n "${GC_RIG:-}" ]; then RIG_KEY="$(state_key "$GC_RIG" "$GC_RIG")"
elif [ -n "${GC_RIG_ROOT:-}" ]; then ROOT_TAIL="${GC_RIG_ROOT%/}"; RIG_KEY="$(state_key "${ROOT_TAIL##*/}" "$GC_RIG_ROOT")"
else RIG_KEY=_unscoped; fi
STATE_BASE="${LIVENESS_SWEEP_STATE_DIR:-${GC_PACK_STATE_DIR:-${TMPDIR:-/tmp}/gc}/liveness-sweep}"
STATE_DIR="$STATE_BASE/$RIG_KEY"
BASELINE_FILE="$STATE_DIR/reported"
STAMP="$STATE_DIR/last-pass"

# Close the cadence window. liveness-sweep-precheck.sh, the order's `check`,
# never spends it on a RUN verdict: a check is evaluated by callers that never
# dispatch, so a RUN has to survive until the pass it dispatches starts.
# Stamped before the reads, so a pass that aborts costs one window instead of
# re-offering itself on every tick. The replace is atomic and matches the
# check's, whose guard probes $STATE_DIR: rename(2) consults the directory's
# mode and never the stamp's own, so a last-pass left read-only still takes
# the window rather than leaving the cadence with no floor.
spend_window() { # spend_window <epoch-seconds>
    local tmp="$STAMP.$$.tmp"
    mkdir -p "$STATE_DIR" 2>/dev/null || return 1
    if printf '%s\n' "$1" > "$tmp" 2>/dev/null && mv -f "$tmp" "$STAMP" 2>/dev/null; then
        return 0
    fi
    rm -f "$tmp" 2>/dev/null
    return 1
}
if [ "$DRY_RUN" -eq 0 ]; then
    spend_window "$(date -u +%s)" \
        || echo "$PROG: WARN: cannot stamp the cadence window at $STAMP" >&2
fi

# gc bd resolves its ledger from the invoking rig; pin to GC_RIG_ROOT when set.
DB="${LIVENESS_SWEEP_DB-${GC_RIG_ROOT:+$GC_RIG_ROOT/.beads}}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

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
bd_read() { # bd_read <outfile> <subcommand> <flags...>; both rc AND shape checked
    local out="$1"; shift
    local rc
    if [ -n "$DB" ]; then
        bounded gc bd "$1" --db "$DB" "${@:2}" 2>/dev/null | scrub > "$out"; rc=$?
    else
        bounded gc bd "$@" 2>/dev/null | scrub > "$out"; rc=$?
    fi
    [ "$rc" -eq 0 ] && jq -e 'type == "array"' "$out" >/dev/null 2>&1
}
bd_write() { # writes go unpinned through gc bd, honoring the same --db pin
    if [ -n "$DB" ]; then gc bd "$1" --db "$DB" "${@:2}"; else gc bd "$@"; fi
}

# --- census: fail-safe first — never classify on partial data ----------------
READY="$TMP/ready.json"; LIVE="$TMP/live.json"; WIDEN="$TMP/widen.json"; ALIVE="$TMP/alive.json"
bd_read "$READY" ready --unassigned --limit=0 --json \
    || { echo "$PROG: FAIL-SAFE: ready listing unreadable — sweep aborts, nothing filed" >&2; exit 1; }
bd_read "$LIVE" list --status=open,in_progress --limit=0 --json \
    || { echo "$PROG: FAIL-SAFE: live listing unreadable — sweep aborts, nothing filed" >&2; exit 1; }
# WIDEN carries every non-closed status LIVE omits: "is that target still
# alive?" means NOT CLOSED (a blocked/deferred target still names the wait).
bd_read "$WIDEN" list --status=blocked,deferred,pinned,hooked --limit=0 --json \
    || { echo "$PROG: FAIL-SAFE: widen listing unreadable — sweep aborts, nothing filed" >&2; exit 1; }
jq -s 'add' "$LIVE" "$WIDEN" > "$ALIVE" 2>/dev/null
jq -e 'type=="array"' "$ALIVE" >/dev/null 2>&1 \
    || { echo "$PROG: FAIL-SAFE: alive merge unreadable — sweep aborts, nothing filed" >&2; exit 1; }
PASS_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# --- open PRs, read ONCE per pass, repo-qualified from the beads' own pr_url --
# Three-valued liveness (none/verified/unverified): a failed read hides
# nothing — an unread repository contributes no open PRs, so its beads are
# reported — but the visit body owes the word.
PRURLS="$TMP/prurls"; : > "$PRURLS"
PR_LIVENESS=none
jq -r '[ .[] | select((.metadata.merge_result // "") == "pull_request")
       | [ ((.metadata.pr_url // "") | ascii_downcase) | capture("://(?<h>[^/]+)/(?<o>[^/]+/[^/]+)/pull/[0-9]+") ]
       | .[0] | select(. != null) | (.h + "/" + .o) ] | unique | .[]' "$READY" 2>/dev/null > "$TMP/prrepos"
while IFS= read -r R; do
    [ -n "$R" ] || continue
    if [ "$PR_LIVENESS" = "none" ]; then PR_LIVENESS=verified; fi
    # --limit is required: gh pr list defaults to 30 and truncates in silence.
    if ROWS=$(bounded gh pr list --repo "$R" --state open --limit 1000 --json url 2>/dev/null) \
       && [ -n "$ROWS" ] && printf '%s' "$ROWS" | jq -e 'type == "array"' >/dev/null 2>&1; then
        printf '%s' "$ROWS" | jq -r '.[].url // empty' >> "$PRURLS"
    else
        PR_LIVENESS=unverified
        echo "$PROG: WARN: open-PR read FAILED for $R — its PR-parked beads are reported, never hidden" >&2
    fi
done < "$TMP/prrepos"
OPEN_PRS=$(jq -R . < "$PRURLS" | jq -sc 'map(select(length > 0))')

# --- worked-via-convoy: live molecules resolved FORWARD to their work beads --
# A slung work bead carries no worker stamp of its own; coverage requires a
# LIVE NAMER (a not-closed bead naming the convoy), never the convoy's mere
# existence — a dead synthetic convoy's tracks edge is not coverage.
WORKED_TMP="$TMP/worked"; : > "$WORKED_TMP"
CONVOY_LIVENESS=none
jq -r '[ .[] | (.metadata["gc.input_convoy_id"] // "") | select(. != "") ] | unique | .[]' "$ALIVE" 2>/dev/null > "$TMP/convoys"
while IFS= read -r C; do
    [ -n "$C" ] || continue
    if [ "$CONVOY_LIVENESS" = "none" ]; then CONVOY_LIVENESS=verified; fi
    # gc bd show, NOT list: only show renders this edge (.dependency_type + .id).
    if ROWS=$(bounded gc bd show "$C" --json 2>/dev/null) && printf '%s' "$ROWS" | jq -e 'type == "array"' >/dev/null 2>&1; then
        printf '%s' "$ROWS" | jq -r '.[0].dependencies[]? | select(.dependency_type == "tracks") | .id' >> "$WORKED_TMP"
    else
        CONVOY_LIVENESS=unverified
        echo "$PROG: WARN: convoy read FAILED for $C — the beads it tracks are reported, never hidden" >&2
    fi
done < "$TMP/convoys"
WORKED=$(jq -R . < "$WORKED_TMP" | jq -sc 'map(select(length > 0)) | unique')

# --- landed-anchor husks: steps of a finished workflow are teardown, not waits
# Resolved per ROOT (root -> gc.input_convoy_id -> tracks members -> each
# anchor's own state). Landed is status=closed OR merge_result=merged and
# deliberately only that pair — every other marker is worn mid-flight.
HUSK_TMP="$TMP/husks"; HUSK_ROOTS_TMP="$TMP/huskroots"; : > "$HUSK_TMP"; : > "$HUSK_ROOTS_TMP"
HUSK_LIVENESS=none
jq -r '[ .[] | (.metadata["gc.root_bead_id"] // "") | select(. != "") ] | unique | .[]' "$READY" 2>/dev/null > "$TMP/roots"
while IFS= read -r R; do
    [ -n "$R" ] || continue
    if [ "$HUSK_LIVENESS" = "none" ]; then HUSK_LIVENESS=verified; fi
    CONVOY=""
    if RJSON=$(bounded gc bd show "$R" --json 2>/dev/null) && printf '%s' "$RJSON" | jq -e 'type == "array"' >/dev/null 2>&1; then
        CONVOY=$(printf '%s' "$RJSON" | jq -r '.[0].metadata["gc.input_convoy_id"] // ""')
    else
        HUSK_LIVENESS=unverified
        echo "$PROG: WARN: root read FAILED for $R — its step beads are reported, never hidden" >&2
    fi
    # A root naming no convoy has no anchor that could have landed: not a husk.
    [ -n "$CONVOY" ] || continue
    MEMBERS=""
    if CJSON=$(bounded gc bd show "$CONVOY" --json 2>/dev/null) && printf '%s' "$CJSON" | jq -e 'type == "array"' >/dev/null 2>&1; then
        MEMBERS=$(printf '%s' "$CJSON" | jq -r '.[0].dependencies[]? | select(.dependency_type == "tracks") | .id')
    else
        HUSK_LIVENESS=unverified
        echo "$PROG: WARN: convoy read FAILED for $CONVOY — root $R is reported, never hidden" >&2
    fi
    [ -n "$MEMBERS" ] || continue
    # ALL tracked members must be landed; a convoy with none is not a husk.
    ALL_LANDED=1
    printf '%s\n' "$MEMBERS" > "$TMP/members"
    while IFS= read -r A; do
        [ -n "$A" ] || continue
        LANDED=""
        if AJSON=$(bounded gc bd show "$A" --json 2>/dev/null) && printf '%s' "$AJSON" | jq -e 'type == "array"' >/dev/null 2>&1; then
            LANDED=$(printf '%s' "$AJSON" | jq -r 'if ((.[0].status // "") == "closed") or ((((.[0].metadata // {}).merge_result // "") | tostring) == "merged") then "yes" else "" end')
        else
            HUSK_LIVENESS=unverified
            echo "$PROG: WARN: anchor read FAILED for $A — root $R is reported, never hidden" >&2
        fi
        if [ -z "$LANDED" ]; then ALL_LANDED=0; fi
    done < "$TMP/members"
    if [ "$ALL_LANDED" = "1" ]; then
        echo "$R" >> "$HUSK_ROOTS_TMP"
        jq -r --arg r "$R" '[ .[] | select((.metadata["gc.root_bead_id"] // "") == $r) | .id ] | .[]' "$READY" >> "$HUSK_TMP"
    fi
done < "$TMP/roots"
HUSK_STEPS=$(jq -R . < "$HUSK_TMP" | jq -sc 'map(select(length > 0)) | unique')
HUSK_ROOTS=$(jq -R . < "$HUSK_ROOTS_TMP" | jq -sc 'map(select(length > 0)) | unique')

# --- classify -----------------------------------------------------------------
# One jq over the ready set: every drop is a NAMED class; the survivors are
# the unnamed waits. Structural edges (2i) fold in from ALIVE — a parent is
# gated iff a not-closed child names it (the child holds the edge), and an
# outgoing tracks edge to a not-closed bead is a named wait. Every `// ""` is
# load-bearing: most beads carry no metadata key at all, and an empty
# takeaway/hold is a CLEARED hold, not a hold.
# >>> classify
CLASSIFIED=$(jq -n --slurpfile live "$LIVE" --slurpfile ready "$READY" --slurpfile alive "$ALIVE" \
      --argjson openprs "${OPEN_PRS:-[]}" --argjson worked "${WORKED:-[]}" --argjson husks "${HUSK_STEPS:-[]}" '
  def pr_key:
    [ ((. // "") | tostring | ascii_downcase)
      | capture("://(?<h>[^/]+)/(?<o>[^/]+/[^/]+)/pull/(?<n>[0-9]+)") ]
    | .[0] | if . == null then "" else (.h + "/" + .o + "/pull/" + .n) end;
  def standing_kinds: ["triage-subject", "feedback-pattern"];
  def machine_convoy:
    (.issue_type // "") == "convoy"
    and ((((.title // "") | startswith("sling-"))
          or ((.title // "") | startswith("input convoy for"))
          or ((.metadata["gc.synthetic"] // "") == "true")));
  # The tracking bead of an order is a wisp: issue_type task, no metadata
  # until it closes, and no edges, so it reaches no structural class and
  # every order in flight reports itself. Both conjuncts are machine-minted
  # and immutable, which keeps the exclusion locally decidable and monotone.
  # Requiring BOTH is what keeps a human bead titled "order: ..." visible,
  # and a wisp of some other kind too.
  def order_wisp:
    ((.id // "") | contains("-wisp-"))
    and ((.title // "") | startswith("order:"));
  def pre_open_all_green:
    (.metadata // {}) as $m
    | (($m.check_set // "")
        | split(",") | map(gsub("^[[:space:]]+|[[:space:]]+$"; "")) | map(select(length > 0))
        | map(select((ascii_downcase) as $g | $g != "none" and $g != "off" and $g != "approval"))) as $gates
    | ($gates | length) > 0
      and all($gates[]; ($m["check." + .] // "") | startswith("green@"));
  # Live-visit subjects: union of the gc.continuation_group stamp and the
  # tracks edge — the stamp alone has landed empty on a live visit (su-ab9je).
  ([ ($live[0] // [])[]
     | select((.metadata.task_kind // "") == "visit")
     | ((.metadata["gc.continuation_group"] // ""),
        (.dependencies[]? | select((.type // "") == "tracks") | (.depends_on_id // "")))
     | select(. != "") ]) as $convgroups
  | ([ ($live[0] // [])[]
     | select((.metadata.task_kind // "") == "visit")
     | (.metadata.stall_root // empty) | select(. != "") ]) as $rootvisits
  | ([ ($openprs // [])[] | pr_key ] | map(select(. != ""))) as $openkeys
  | (($alive[0] // []) | map({key: .id, value: true}) | from_entries) as $aliveset
  | ([ ($alive[0] // [])[] | .dependencies[]?
       | select((.type // "") == "parent-child") | (.depends_on_id // empty) ] | unique) as $gatedparents
  | [ ($ready[0] // [])[]
      | . as $b
      | (if machine_convoy or order_wisp then "machine"
         elif ($husks | index($b.id)) != null then "husk"
         elif ((.metadata["gc.routed_to"] // "") != "") then "routed-and-claimable"
         elif (($worked | index($b.id)) != null) then "worked"
         elif ((.metadata.task_kind // "") == "visit") then "conversing"
         elif ((.metadata.task_kind // "") as $k | (standing_kinds | index($k)) != null) then "held-by-design"
         elif ((.metadata["gc.takeaway"] // "") != "") then "held-by-design"
         elif ((.metadata["triage.hold"] // "") != "") then "held-by-design"
         elif ((.metadata["gc.root_bead_id"] // "") as $r | $r != "" and (($rootvisits | index($r)) != null)) then "conversing"
         elif (($convgroups | index($b.id)) != null) then "conversing"
         elif (((.metadata.merge_result // "") == "pull_request")
               and (((.metadata.pr_url // "") | pr_key) as $k | $k != "" and ($openkeys | index($k)) != null)) then "gated"
         elif (((.metadata.merge_result // "") == "pre_open_gate") and pre_open_all_green) then "gated"
         elif (($gatedparents | index($b.id)) != null) then "gated"
         elif ([ .dependencies[]? | select((.type // "") == "tracks")
                 | select(($aliveset[(.depends_on_id // "")] // false)) ] | length > 0) then "gated"
         else "unnamed" end) as $class
      | {id, title: (.title // ""), type: (.issue_type // ""), class: $class}
    ]')
printf '%s' "$CLASSIFIED" | jq -e 'type == "array"' >/dev/null 2>&1 \
    || { echo "$PROG: FAIL-SAFE: classification did not produce an array — nothing filed" >&2; exit 1; }
CANDIDATES=$(printf '%s' "$CLASSIFIED" | jq -c 'map(select(.class == "unnamed") | {id, title, type})')
# <<< classify
echo "$PROG: funnel: $(printf '%s' "$CLASSIFIED" | jq -r 'group_by(.class) | map("\(.[0].class) \(length)") | join(" · ")')"
echo "$PROG: liveness: pr=$PR_LIVENESS convoy=$CONVOY_LIVENESS husk=$HUSK_LIVENESS · husk roots: $(printf '%s' "$HUSK_ROOTS" | jq -r 'join(",") | if . == "" then "(none)" else . end')"

# --- the standing unnamed-waits subject (create on first run) -----------------
SWEEP_SUBJECT=$(jq -r '[.[] | select((.metadata.task_kind // "") == "triage-subject")
  | select((.metadata["triage.scope"] // "") == "unnamed-waits")] | (.[0].id // "")' "$LIVE")
if [ -z "$SWEEP_SUBJECT" ] && [ "$DRY_RUN" -eq 0 ]; then
    SWEEP_SUBJECT=$(bd_write create -t task --title "triage: unnamed waits (this rig)" \
        -d "Standing triage scope: open beads with no worker, route, structure-wait, gate, or visit. Each visit lists the unnamed waits NEW since the previous pass. Dispositions: route / gate / kill / park (a real dep edge onto a scope bead) / demand (a sibling bead naming what a person owes, plus a blocks edge)." \
        --json | scrub | jq -r '.id // .[0].id')
    [ -n "$SWEEP_SUBJECT" ] && [ "$SWEEP_SUBJECT" != "null" ] \
        || { echo "$PROG: could not create the standing subject — nothing filed" >&2; exit 1; }
    bd_write update "$SWEEP_SUBJECT" --set-metadata "task_kind=triage-subject" \
        --set-metadata "triage.scope=unnamed-waits" >/dev/null
fi

# --- the delta (baseline: per-rig state file) ---------------------------------
BASELINE=$(cat "$BASELINE_FILE" 2>/dev/null || true)
# index() returns a POSITION and position 0 is a real hit; CARRIED tests
# `!= null` explicitly so the first baseline id can never re-report forever.
NEW=$(printf '%s' "$CANDIDATES" | jq -c --arg seen "$BASELINE" '
  ($seen | split(",") | map(gsub("^[[:space:]]+|[[:space:]]+$"; "")) | map(select(. != ""))) as $s
  | map(select(.id as $id | ($s | index($id)) | not))')
CARRIED=$(printf '%s' "$CANDIDATES" | jq -c --arg seen "$BASELINE" '
  ($seen | split(",") | map(gsub("^[[:space:]]+|[[:space:]]+$"; "")) | map(select(. != ""))) as $s
  | map(select(.id as $id | ($s | index($id)) != null))')
NEW_COUNT=$(printf '%s' "$NEW" | jq 'length')
CARRIED_COUNT=$(printf '%s' "$CARRIED" | jq 'length')
CUR_IDS=$(printf '%s' "$CANDIDATES" | jq -r '[.[].id] | sort | join(",")')
echo "$PROG: delta: $NEW_COUNT new, $CARRIED_COUNT carried (baseline $(printf '%s' "$BASELINE" | tr ',' '\n' | grep -c . || true) id(s))"

advance_baseline() {
    [ "$DRY_RUN" -eq 0 ] || return 0
    mkdir -p "$STATE_DIR" 2>/dev/null || { echo "$PROG: WARN: cannot write baseline at $BASELINE_FILE" >&2; return 0; }
    printf '%s\n' "$CUR_IDS" > "$BASELINE_FILE" 2>/dev/null \
        || echo "$PROG: WARN: cannot write baseline at $BASELINE_FILE" >&2
}

# resolve the claim-time re-check script — searched, never assumed (importer
# rigs have no assets/ of their own).
RECHECK_SH=""
for cand in "$HERE/.." "${GC_RIG_ROOT:+$GC_RIG_ROOT/assets}" "${GC_CITY_PATH:+$GC_CITY_PATH/rigs/gc-toolkit/assets}"; do
    [ -n "$cand" ] && [ -x "$cand/scripts/liveness-recheck.sh" ] \
        && { RECHECK_SH="$(cd "$cand/scripts" && pwd)/liveness-recheck.sh"; break; }
done

sweep_visit() {
    # Live-visit guard: a sitting already live on the subject self-limits the
    # backlog to one conversation. Do NOT advance the baseline here — these
    # new candidates were never put in front of anyone.
    local live_visit
    live_visit=$(jq -r --arg s "$SWEEP_SUBJECT" '[.[] | select((.metadata.task_kind // "") == "visit")
        | ((.metadata["gc.continuation_group"] // ""),
           (.dependencies[]? | select((.type // "") == "tracks") | (.depends_on_id // "")))
        | select(. != "")] | (index($s) // "") | tostring' "$LIVE")
    if [ -n "$live_visit" ]; then
        echo "$PROG: batch visit already live on $SWEEP_SUBJECT; $CARRIED_COUNT carried, $NEW_COUNT new await it (baseline not advanced)"
        return 0
    fi
    if [ "$NEW_COUNT" = "0" ]; then
        echo "$PROG: nothing new — nothing filed"
        advance_baseline
        return 0
    fi
    # Re-file guard: an agenda a sitting already closed out `dispositioned` is
    # not news. The test is the id SET; a cut-short or unreadable prior files.
    # Fail-open on a non-zero read even when it printed a matching array.
    local new_key prior_rc prior refile=""
    new_key=$(printf '%s' "$NEW" | jq -r '[.[].id] | sort | join(",")')
    prior_rc=0
    prior=$( { if [ -n "$DB" ]; then gc bd list --db "$DB" --status=closed --metadata-field "gc.continuation_group=$SWEEP_SUBJECT" --limit=0 --json; else gc bd list --status=closed --metadata-field "gc.continuation_group=$SWEEP_SUBJECT" --limit=0 --json; fi; } 2>/dev/null) || prior_rc=$?
    if [ "$prior_rc" -eq 0 ]; then
        refile=$(printf '%s' "$prior" | scrub | jq -r --arg key "$new_key" '
            if type == "array" then
              [ .[]
                | select(((.metadata // {}).task_kind // "") == "visit")
                | select((((.metadata // {})["gc.outcome"] // "") | tostring) == "dispositioned")
                | select(((((.metadata // {})["sweep.new_ids"] // "") | tostring)
                          | split(",") | map(select(length > 0)) | sort | join(",")) == $key)
                | .id ] | (.[0] // "")
            else "" end' 2>/dev/null)
    fi
    if [ -n "$refile" ] && [ -n "$new_key" ]; then
        echo "$PROG: same NEW set as dispositioned visit $refile; not re-filed (baseline advanced)"
        advance_baseline
        return 0
    fi

    # Build the body: new candidates enumerated (capped), carried as bare ids.
    local body
    body=$(jq -nr --argjson new "$NEW" --argjson carried "$CARRIED" \
        --arg pass_at "$PASS_AT" --arg cap "$LIST_CAP" \
        --arg pr "$PR_LIVENESS" --arg convoy "$CONVOY_LIVENESS" --arg husk "$HUSK_LIVENESS" '
      ($cap | tonumber) as $c
      | [ "unnamed waits: \($new | length) new, \($carried | length) carried",
          "Census cut \($pass_at) — a snapshot, not the board. Run the visit.recheck stamp on this visit before acting.",
          (if $pr == "unverified" then "WARNING: the open-PR read failed for at least one repository — PR-parked beads may be listed." else empty end),
          (if $convoy == "unverified" then "WARNING: a convoy read failed — a molecule-driven work bead may be listed." else empty end),
          (if $husk == "unverified" then "WARNING: a root/convoy/anchor read failed — a landed workflow step may be listed." else empty end),
          "",
          "New this pass:",
          ($new[0:$c][] | "  \(.id) — \(.title) [\(.type)]"),
          (if ($new | length) > $c then "  …plus \(($new | length) - $c) more: \($new[$c:] | map(.id) | join(", "))" else empty end),
          "",
          "Carried (still unnamed from earlier passes, not re-litigated): \($carried | length)",
          (if ($carried | length) > 0 then "  \($carried | map(.id) | join(", "))" else empty end),
          "",
          "Dispositions: route (gc sling <pool> <id>; never --on here) · gate (file a visit/gate) · kill (gc bd close <id> --reason) · park (gc bd dep add <bead> <scope> — the edge IS the park; prose parks nothing) · demand (gc-helm.sh demand <id> \"<what a person owes>\" — files that as a SIBLING bead and blocks <id> on it; a hold written as prose is not a disposition, it is a field someone has to come back and clear)"
        ] | join("\n")')
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "$PROG: dry-run: would file batch visit on $SWEEP_SUBJECT [liveness-sweep]"
        return 0
    fi
    local out visit
    if ! out=$("$ESCALATE" --subject "$SWEEP_SUBJECT" --key liveness-sweep --message "$body"); then
        echo "$PROG: escalate.sh failed — baseline NOT advanced; the next pass re-reports" >&2
        return 1
    fi
    printf '%s\n' "$out"
    # Stamp the census as machine state on the visit so a claim-time re-check
    # is one command, then advance the baseline (visit first, stamp second: a
    # failed create must leave the baseline for the next pass to re-report).
    visit=$(printf '%s' "$out" | grep -oE 'visit [A-Za-z0-9._-]+' | head -n1 | cut -d' ' -f2)
    if [ -n "$visit" ]; then
        bd_write update "$visit" \
            --set-metadata "sweep.new_ids=$(printf '%s' "$NEW" | jq -r 'map(.id) | join(",")')" \
            --set-metadata "sweep.carried_ids=$(printf '%s' "$CARRIED" | jq -r 'map(.id) | join(",")')" \
            --set-metadata "sweep.pass_at=$PASS_AT" >/dev/null 2>&1 \
            || echo "$PROG: WARN: could not stamp the census on visit $visit" >&2
        if [ -n "$RECHECK_SH" ]; then
            bd_write update "$visit" --set-metadata "visit.recheck=$RECHECK_SH" >/dev/null 2>&1 \
                || echo "$PROG: WARN: could not stamp visit.recheck on $visit" >&2
        else
            echo "$PROG: WARN: no liveness-recheck.sh found — the visit carries id lists but no runnable re-check" >&2
        fi
    fi
    advance_baseline
}
if [ -n "$SWEEP_SUBJECT" ]; then
    sweep_visit || exit 1
else
    echo "$PROG: dry-run: no standing subject yet ($NEW_COUNT would be new)"
fi

# --- triage recurrence (absorbs mol-triage-recurrence) -------------------------
# Each standing triage subject gets ONE visit iff its scope set CHANGED since
# triage.last_seen AND no visit is live. Scope tokens: p<=N · label:X ·
# kind:X · unrouted. last_seen is a TRI-STATE: absent = never evaluated
# (file when non-empty), "" = last saw an empty scope. An emptied scope is a
# change — the visit names what left, then the subject goes quiet.
recurrence() {
    local subjects
    subjects=$(jq -c '[.[] | select((.metadata.task_kind // "") == "triage-subject")
        | {id, title: (.title // ""),
           scope: (.metadata["triage.scope"] // ""),
           last_seen: (if ((.metadata // {}) | has("triage.last_seen"))
                       then (.metadata["triage.last_seen"] // "") else null end)}] | .[]' "$LIVE")
    [ -n "$subjects" ] || return 0
    local convgroups
    convgroups=$(jq -c '[.[] | select((.metadata.task_kind // "") == "visit")
        | ((.metadata["gc.continuation_group"] // ""),
           (.dependencies[]? | select((.type // "") == "tracks") | (.depends_on_id // "")))
        | select(. != "")]' "$LIVE")
    printf '%s\n' "$subjects" > "$TMP/subjects"
    while IFS= read -r row; do
        local sid scope was now n delta
        sid=$(printf '%s' "$row" | jq -r '.id')
        scope=$(printf '%s' "$row" | jq -r '.scope')
        was=$(printf '%s' "$row" | jq -r '.last_seen // "<absent>"')
        case "$scope" in
            unnamed-waits) echo "$PROG: $sid: skipped-owned-by-sweep"; continue ;;
            "") echo "$PROG: $sid: skipped-no-machine-scope"; continue ;;
        esac
        if printf '%s' "$convgroups" | jq -e --arg s "$sid" 'index($s) != null' >/dev/null 2>&1; then
            # Stamp nothing here: a bead entering the scope mid-sitting must
            # still surface on the first run after that visit closes.
            echo "$PROG: $sid: skipped-live-visit"; continue
        fi
        # Evaluate the scope tokens over the OPEN beads; a token outside the
        # schema is ignored (logged); no recognized token means no guessing.
        now=$(jq -r --arg scope "$scope" '
            ($scope | split(" ") | map(select(. != ""))) as $tokens
            | [ .[] | select((.status // "open") == "open")
                | select((.metadata.task_kind // "") != "visit")
                | select((.metadata.task_kind // "") != "triage-subject")
                | . as $b
                | select(all($tokens[];
                    (if startswith("p<=") then (($b.priority // 99) <= (ltrimstr("p<=") | tonumber? // 99))
                     elif startswith("label:") then (($b.labels // []) | index(ltrimstr("label:")) != null)
                     elif startswith("kind:") then (($b.metadata.task_kind // "") == ltrimstr("kind:"))
                     elif . == "unrouted" then ((($b.metadata["gc.routed_to"] // "") == "") and (($b.assignee // "") == ""))
                     else true end)))
                | .id ] | sort | join(",")' "$LIVE" 2>/dev/null)
        local recognized
        recognized=$(printf '%s' "$scope" | tr ' ' '\n' | grep -cE '^(p<=[0-9]+|label:.+|kind:.+|unrouted)$' || true)
        if [ "${recognized:-0}" = "0" ]; then echo "$PROG: $sid: skipped-no-machine-scope"; continue; fi
        n=$(printf '%s' "$now" | tr ',' '\n' | grep -c . || true)
        if [ -z "$now" ] && { [ "$was" = "" ] || [ "$was" = "<absent>" ]; }; then
            echo "$PROG: $sid: skipped-no-candidates"
            # Stamp "" only when the key was ABSENT, so the first entering
            # bead reads as a change; an already-recorded "" is this same set.
            if [ "$was" = "<absent>" ] && [ "$DRY_RUN" -eq 0 ]; then
                bd_write update "$sid" --set-metadata "triage.last_seen=" >/dev/null 2>&1 || true
            fi
            continue
        fi
        if [ "$now" = "$was" ]; then echo "$PROG: $sid: skipped-unchanged ($n in scope)"; continue; fi
        delta=$(jq -rn --arg now "$now" --arg was "$was" '
            def ids: split(",") | map(select(. != ""));
            ($now | ids) as $n
            | (if $was == "<absent>" then null else ($was | ids) end) as $w
            | if $w == null then
                "First evaluation of this subject: all \($n | length) are simply what is in scope now."
              else
                "Entered since the last visit: " + (($n - $w) | if length == 0 then "(none)" else join(", ") end)
                + ". Left: " + (($w - $n) | if length == 0 then "(none)" else join(", ") end) + "."
              end')
        if [ "$DRY_RUN" -eq 1 ]; then
            echo "$PROG: $sid: dry-run: would file recurrence visit ($n in scope)"
            continue
        fi
        if "$ESCALATE" --subject "$sid" --key triage-recurrence \
                --message "triage recurrence: $n candidates in scope
$delta
Current set: $now"; then
            # Stamp only AFTER the visit exists: an unfiled delta is never
            # recorded as seen, so the next run re-files it.
            bd_write update "$sid" --set-metadata "triage.last_seen=$now" >/dev/null 2>&1 \
                || echo "$PROG: WARN: could not stamp triage.last_seen on $sid" >&2
            echo "$PROG: $sid: filed recurrence visit ($n in scope)"
        else
            echo "$PROG: $sid: escalate.sh failed — last_seen not advanced; re-files next pass" >&2
        fi
    done < "$TMP/subjects"
}
recurrence
exit 0
