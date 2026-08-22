#!/usr/bin/env bash
# Hermetic test for detect-parked-dispositions.sh (tk-2cyxo). Stubs `gc` (bd
# list/show/update) and `gc-helm.sh` on PATH. No live city, Dolt, or network.
#
# The pass files ONE visit back to converse when a parked, operator-origin subject's
# routed work has all landed. Covered:
#
#   (BLOCKS)    readiness via a closed `blocks` edge — the shape `gc-helm takeaway
#               --waiting-on` writes and the board's disposition_due reads
#   (CHILD)     readiness via a closed CHILD and NO blocks edge — the CANONICAL
#               converse shape, and the one disposition_due can never see. A parent
#               cannot be blocked by its own descendant (bd refuses the edge:
#               "blocked status cascades to descendants"), so a sitting that files
#               its work as a child of the subject leaves waiting_on empty forever.
#               Without this case the pass cannot fire for tk-z9nln — the very
#               subject the 4h19m incident was measured on
#   (MIXED)     both kinds at once: the landed key is the sorted UNION
#   (OPENCHILD) one open child holds the whole subject — readiness is all-or-nothing
#   (OPENBLOCK) one open blocker does the same
#   (PARENTDEP) a parent-child row on the SUBJECT means the subject is somebody's
#               CHILD, never that it routed work. The edge is stored on the child, so
#               reading the subject's own dependency list for it inverts the relation
#               and would call a subject ready because its PARENT closed
#   (NOWAIT)    parked with no recorded wait at all — the ordinary "we talked, here
#               is the conclusion" park — is never signalled. Without the
#               at-least-one half, every such park reads as ready forever
#   (NOTOP)     parked but NOT gc.origin=operator: exempt. The ruling is deliberately
#               narrow — the operator-origin set is where a standing expectation of
#               an answer exists
#   (EMPTYPARK) an EMPTY gc.takeaway is a CLEARED park, not a park: not a candidate,
#               the same absent-vs-empty tri-state the rest of the city reads
#   (HELD)      a subject already under an open visit is skipped — by the
#               gc.continuation_group stamp, AND by the tracks edge alone when the
#               stamp landed empty (su-ab9je, 2026-08-20). Either recording counts;
#               keying on the stamp alone files the duplicate the guard exists for
#   (DEDUP)     disposition_flagged equal to the current landed set: silent
#   (REFLAG)    a DIFFERENT landed set (a second round of work routed and landed)
#               earns exactly one more visit
#   (UNRESOLVED) a blocker id the store cannot answer for reads as STILL OPEN. Wrong
#               in the quiet direction on purpose: a false "the work landed" invites
#               the operator into a conversation about work still in flight
#   (LISTFAIL)  an unreadable open listing files NOTHING at all
#   (KIDFAIL)   an unreadable child listing skips that subject rather than reading
#               "no children" as "nothing is waiting"
#   (VERIFY)    gc-helm.sh open exiting 0 without filing anything does NOT stamp the
#               marker — a create that reports success and persists nothing is
#               exactly what a marker would retire forever
#   (HELMFAIL)  a refused filing leaves the subject unflagged and exits non-zero
#   (NOCLEAR)   the takeaway is never cleared and never rewritten: the pass writes
#               exactly one key, disposition_flagged, and only after a visit exists
#   (NOHELM)    with gc-helm.sh unavailable the pass degrades to REPORT-ONLY — the
#               selection still reaches the operator, and no marker is stamped over a
#               visit that was never filed
#   (DRY)       --dry-run reports the same selection and issues no write
#   (REPEAT)    repeated passes against one persistent store, with the stub bumping
#               updated_at on every update as beads does, file ONE visit: pass 2 held
#               by the visit-already-open guard, pass 3 (visit closed, nothing
#               changed) held by the id-keyed marker despite the bump. A marker keyed
#               on a timestamp re-files here, forever — the amplifier tk-1g9yw
#   (SPENT)     --wait-spent, the predicate detect-stalled-workflows.sh asks before
#               letting a takeaway mute a stall: 0 when the recorded wait has fully
#               closed, non-zero when anything is open, when nothing was ever
#               recorded, and when the read failed
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/detect-parked-dispositions.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { grep -q -- "$2" "$1" && ok "$3" || bad "$3 (not found: $2)"; }
hasnt() { grep -q -- "$2" "$1" && bad "$3 (unexpectedly found: $2)" || ok "$3"; }

[ -f "$SCRIPT" ] && ok "detect-parked-dispositions.sh present" || { bad "missing at $SCRIPT"; exit 1; }
mkdir -p "$TMP/bin"

PARKED='{"gc.takeaway":"holding — waiting on the routed work","gc.takeaway_at":"2026-08-22T05:25:00Z","gc.takeaway_by":"converse","gc.origin":"operator"}'

# --- fixture ------------------------------------------------------------------
# One mutable store per run: the stub reads it, and update/helm-open mutate it in
# place, so a read-back sees exactly what a write persisted. `_parent` models the
# parent-child edge, which is stored on the CHILD — `bd list --parent X` is the only
# way to ask for children, and the fixture answers it the same way.
cat > "$TMP/beads.json" <<EOF
[
 {"id":"s-blocks","title":"parked, waiting by edge","status":"open","metadata":$PARKED,
  "dependencies":[{"issue_id":"s-blocks","depends_on_id":"w-blocks","type":"blocks"}]},
 {"id":"w-blocks","title":"the routed work","status":"closed","metadata":{}},

 {"id":"s-child","title":"parked, waiting by child","status":"open","metadata":$PARKED},
 {"id":"w-child","title":"the routed work","status":"closed","metadata":{},"_parent":"s-child"},

 {"id":"s-mixed","title":"parked, both kinds","status":"open","metadata":$PARKED,
  "dependencies":[{"issue_id":"s-mixed","depends_on_id":"w-mixblock","type":"blocks"}]},
 {"id":"w-mixblock","title":"blocker","status":"closed","metadata":{}},
 {"id":"w-mixkid","title":"child","status":"closed","metadata":{},"_parent":"s-mixed"},

 {"id":"s-openchild","title":"parked, child still open","status":"open","metadata":$PARKED},
 {"id":"w-openkid","title":"still going","status":"open","metadata":{},"_parent":"s-openchild"},
 {"id":"w-donekid","title":"landed","status":"closed","metadata":{},"_parent":"s-openchild"},

 {"id":"s-openblock","title":"parked, blocker still open","status":"open","metadata":$PARKED,
  "dependencies":[{"issue_id":"s-openblock","depends_on_id":"w-openblock","type":"blocks"}]},
 {"id":"w-openblock","title":"still going","status":"open","metadata":{}},

 {"id":"s-parentdep","title":"parked, and is itself somebody's child","status":"open","metadata":$PARKED,
  "dependencies":[{"issue_id":"s-parentdep","depends_on_id":"p-closed","type":"parent-child"},
                  {"issue_id":"s-parentdep","depends_on_id":"t-tracked","type":"tracks"}]},
 {"id":"p-closed","title":"the parent, closed","status":"closed","metadata":{}},
 {"id":"t-tracked","title":"tracked, closed","status":"closed","metadata":{}},

 {"id":"s-nowait","title":"parked, routed nothing","status":"open","metadata":$PARKED},

 {"id":"s-notop","title":"parked, agent-origin","status":"open",
  "metadata":{"gc.takeaway":"agent parked this","gc.origin":"proactive"},
  "dependencies":[{"issue_id":"s-notop","depends_on_id":"w-notop","type":"blocks"}]},
 {"id":"w-notop","title":"landed","status":"closed","metadata":{}},

 {"id":"s-emptypark","title":"park was cleared","status":"open",
  "metadata":{"gc.takeaway":"","gc.origin":"operator"},
  "dependencies":[{"issue_id":"s-emptypark","depends_on_id":"w-empty","type":"blocks"}]},
 {"id":"w-empty","title":"landed","status":"closed","metadata":{}},

 {"id":"s-held","title":"parked, already in conversation","status":"open","metadata":$PARKED,
  "dependencies":[{"issue_id":"s-held","depends_on_id":"w-held","type":"blocks"}]},
 {"id":"w-held","title":"landed","status":"closed","metadata":{}},
 {"id":"v-held","title":"visit: s-held","status":"open",
  "metadata":{"task_kind":"visit","gc.continuation_group":"s-held"}},

 {"id":"s-heldedge","title":"parked, visit stamp landed EMPTY","status":"open","metadata":$PARKED,
  "dependencies":[{"issue_id":"s-heldedge","depends_on_id":"w-heldedge","type":"blocks"}]},
 {"id":"w-heldedge","title":"landed","status":"closed","metadata":{}},
 {"id":"v-heldedge","title":"visit: s-heldedge","status":"open",
  "metadata":{"task_kind":"visit","gc.continuation_group":""},
  "dependencies":[{"issue_id":"v-heldedge","depends_on_id":"s-heldedge","type":"tracks"}]},

 {"id":"s-dedup","title":"parked, already signalled","status":"open",
  "metadata":{"gc.takeaway":"holding","gc.origin":"operator","disposition_flagged":"w-dedup"},
  "dependencies":[{"issue_id":"s-dedup","depends_on_id":"w-dedup","type":"blocks"}]},
 {"id":"w-dedup","title":"landed","status":"closed","metadata":{}},

 {"id":"s-reflag","title":"parked, a second round landed","status":"open",
  "metadata":{"gc.takeaway":"holding","gc.origin":"operator","disposition_flagged":"w-round1"},
  "dependencies":[{"issue_id":"s-reflag","depends_on_id":"w-round1","type":"blocks"},
                  {"issue_id":"s-reflag","depends_on_id":"w-round2","type":"blocks"}]},
 {"id":"w-round1","title":"landed","status":"closed","metadata":{}},
 {"id":"w-round2","title":"landed too","status":"closed","metadata":{}},

 {"id":"s-unresolved","title":"parked, blocker in another store","status":"open","metadata":$PARKED,
  "dependencies":[{"issue_id":"s-unresolved","depends_on_id":"zz-elsewhere","type":"blocks"}]}
]
EOF

# --- gc stub ------------------------------------------------------------------
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
set -uo pipefail
printf '%s\n' "gc $*" >> "$FAKE_CALLS"

[ "${1:-}" = "bd" ] || { echo '[]'; exit 0; }
shift
[ "${1:-}" = "--rig" ] && shift 2
sub="${1:-}"; shift || true

case "$sub" in
  show)
    # `bd show` answers with an ARRAY when any id resolves and a bare OBJECT when
    # none do, rc=0 either way — the shape the caller has to test rather than
    # assume. The stub reproduces both, or the fail-closed path is never exercised.
    ids=""
    while [ $# -gt 0 ]; do case "$1" in --*) [ "$1" = "--json" ] || shift ;; *) ids="$ids $1" ;; esac; shift; done
    out=$(jq -c --arg ids "$ids" '($ids | split(" ") | map(select(length > 0))) as $want
          | [ .[] | select(.id as $i | $want | index($i)) ]' "$FAKE_STORE")
    n=$(printf '%s' "$out" | jq 'length' 2>/dev/null); [ -n "$n" ] || n=0
    if [ "$n" -eq 0 ]; then
      echo '{"error":"no issues found matching the provided IDs","schema_version":1}'
    else
      printf '%s\n' "$out"
    fi
    exit 0 ;;
  update)
    printf 'update %s\n' "$*" >> "$FAKE_UPDATES"
    id="${1:-}"; shift || true
    # Persist --set-metadata pairs AND bump updated_at, exactly as beads does. The
    # bump is what makes the REPEAT coverage real: a marker keyed on a last-touch
    # would be invalidated by its own stamp.
    bump="${FAKE_BUMP_TS:-2026-08-22T23:59:00Z}"
    pairs=""
    while [ $# -gt 0 ]; do
      if [ "${1:-}" = "--set-metadata" ]; then pairs="${pairs}${2:-}
"; shift; fi
      shift
    done
    printf '%s' "$pairs" | jq -c -R -s --arg id "$id" --arg bump "$bump" --slurpfile store "$FAKE_STORE" '
      (split("\n") | map(select(length > 0))
       | map((index("=")) as $i | if $i == null then {key: ., value: ""} else {key: .[0:$i], value: .[$i+1:]} end)
       | from_entries) as $new
      | ($store[0] // [])
      | map(if .id == $id then (.metadata = ((.metadata // {}) + $new)) | (.updated_at = $bump) else . end)' \
      > "$FAKE_STORE.tmp" && mv "$FAKE_STORE.tmp" "$FAKE_STORE"
    exit 0 ;;
  list)
    if [ "${FAKE_LIST_BROKEN:-0}" = "1" ]; then echo 'not json'; exit 0; fi
    statuses=""; parent=""; all=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --status=*) statuses="${1#--status=}" ;;
        --parent)   parent="${2:-}"; shift ;;
        --parent=*) parent="${1#--parent=}" ;;
        --all)      all=1 ;;
      esac
      shift
    done
    if [ -n "$parent" ]; then
      if [ "${FAKE_KIDS_BROKEN:-}" = "$parent" ]; then echo 'not json'; exit 0; fi
      # --parent returns the CHILDREN of that bead and never the bead itself;
      # without --all it hides closed ones, exactly as bd does.
      jq -c --arg p "$parent" --argjson all "$all" \
        '[ .[] | select((._parent // "") == $p) | select($all == 1 or (.status != "closed")) ]' "$FAKE_STORE"
      exit 0
    fi
    jq -c --arg s "$statuses" '($s | split(",")) as $w | [ .[] | select(.status as $st | $w | index($st)) ]' "$FAKE_STORE"
    exit 0 ;;
esac
echo '[]'
GC
chmod +x "$TMP/bin/gc"

# --- gc-helm.sh stub ----------------------------------------------------------
# `open` is the real filing path. The stub appends a visit bead carrying BOTH
# recordings of its subject, so the pass's read-back and the next pass's
# already-open guard see exactly what a real filing leaves behind.
#   FAKE_HELM_RC=N     the verb refuses
#   FAKE_HELM_SILENT=1 it exits 0 and files NOTHING — the failure that a marker,
#                      stamped on trust, would retire forever
cat > "$TMP/bin/gc-helm.sh" <<'HELM'
#!/usr/bin/env bash
set -uo pipefail
printf 'helm %s\n' "$*" >> "$FAKE_CALLS"
[ "${1:-}" = "open" ] || exit 0
subj="${2:-}"
printf '%s\n' "$*" >> "$FAKE_HELM_OPENS"
rc="${FAKE_HELM_RC:-0}"
[ "$rc" = "0" ] || exit "$rc"
if [ "${FAKE_HELM_SILENT:-0}" = "1" ]; then exit 0; fi
n=$(( $(wc -l < "$FAKE_HELM_OPENS") ))
jq -c --arg s "$subj" --arg v "v-new$n" \
  '. + [{id:$v, title:("visit: " + $s), status:"open",
         metadata:{"task_kind":"visit","gc.continuation_group":$s},
         dependencies:[{issue_id:$v, depends_on_id:$s, type:"tracks"}]}]' \
  "$FAKE_STORE" > "$FAKE_STORE.tmp" && mv "$FAKE_STORE.tmp" "$FAKE_STORE"
exit 0
HELM
chmod +x "$TMP/bin/gc-helm.sh"

export PATH="$TMP/bin:$PATH"
export FAKE_STORE="$TMP/store.json"
export GC_HELM_TOOL="$TMP/bin/gc-helm.sh"

run() { # <label> [args...]
  : > "$TMP/updates"; : > "$TMP/calls"; : > "$TMP/opens"
  cp "$TMP/beads.json" "$FAKE_STORE"
  export FAKE_UPDATES="$TMP/updates" FAKE_CALLS="$TMP/calls" FAKE_HELM_OPENS="$TMP/opens"
  set +e
  "$SCRIPT" "$@" > "$TMP/out" 2> "$TMP/err"
  RC=$?
  set -e
}

# --- main pass ----------------------------------------------------------------
run main
eq "$RC" "0" "main pass exits 0"

has "$TMP/out" "s-blocks DISPOSITION DUE" "(BLOCKS) a closed blocks-edge wait is signalled"
has "$TMP/out" "s-child DISPOSITION DUE"  "(CHILD) a closed CHILD is signalled — the canonical converse shape, which waiting_on can never carry"
has "$TMP/out" "s-mixed DISPOSITION DUE"  "(MIXED) both edge kinds at once"
has "$TMP/updates" "update s-mixed --set-metadata disposition_flagged=w-mixblock,w-mixkid" \
  "(MIXED) the landed key is the sorted UNION of both kinds"

hasnt "$TMP/out" "s-openchild DISPOSITION" "(OPENCHILD) one open child holds the whole subject"
hasnt "$TMP/out" "s-openblock DISPOSITION" "(OPENBLOCK) one open blocker does the same"
hasnt "$TMP/out" "s-parentdep DISPOSITION" \
  "(PARENTDEP) a parent-child row on the SUBJECT is the subject being somebody's child — never work it routed"
hasnt "$TMP/out" "s-nowait DISPOSITION"    "(NOWAIT) a park that routed nothing is never signalled"
hasnt "$TMP/out" "s-notop DISPOSITION"     "(NOTOP) an agent-origin park is out of scope"
hasnt "$TMP/out" "s-emptypark DISPOSITION" "(EMPTYPARK) an EMPTY takeaway is a cleared park, not a park"
hasnt "$TMP/out" "s-held DISPOSITION"      "(HELD) a subject already under an open visit is skipped"
hasnt "$TMP/out" "s-heldedge DISPOSITION"  "(HELD) ...including when only the TRACKS edge carries the subject and the stamp landed empty (su-ab9je)"
hasnt "$TMP/out" "s-dedup DISPOSITION"     "(DEDUP) the same landed set already flagged is silent"
has "$TMP/out" "s-reflag DISPOSITION"      "(REFLAG) a DIFFERENT landed set earns one more visit"
has "$TMP/updates" "update s-reflag --set-metadata disposition_flagged=w-round1,w-round2" \
  "(REFLAG) and the marker moves to the new observation"
hasnt "$TMP/out" "s-unresolved DISPOSITION" \
  "(UNRESOLVED) a blocker the store cannot answer for reads as still open — the quiet direction"

# (CENSUS) every candidate lands in exactly one bucket, and the summary line names
# which. Asserted as one exact string because the buckets can MASK each other: a
# subject with no recorded wait has an empty landed key, which equals an empty
# disposition_flagged, so dropping the at-least-one-wait guard does not produce a
# visit — it silently reclassifies the park as "already flagged" and every
# hasnt-assertion above still passes. The counts are the only place that shows it.
has "$TMP/out" "4 disposition(s) signalled; 3 still waiting, 2 with no recorded wait, 2 already under an open visit, 1 already flagged, 0 unreadable, 0 failed" \
  "(CENSUS) 12 candidates, one bucket each — the classification itself is pinned, not just the absence of a report"

# The filing goes through gc-helm.sh open — the one place the canonical gate-visit
# block lives, which also owns the subject-exists gate, the one-visit-per-subject
# gate and the board cache bust. A hand-rolled create here would lose three of them.
has "$TMP/opens" "open s-child" "(CHILD) the visit is filed through gc-helm.sh open"
has "$TMP/opens" "parked · routed work landed" "(BLOCKS) the visit says what it is for"

# (PREMISE) the body states its own premise, so converse's step-2 re-check can kill
# it cheaply: what was parked, what landed, and the command to re-ask.
has "$TMP/opens" "Parked subject: s-child" "(PREMISE) the body names the subject"
has "$TMP/opens" "w-child" "(PREMISE) and the work that landed"
has "$TMP/opens" "gc bd list --parent s-child" "(PREMISE) with the command that re-asks it"

# (NOCLEAR) the takeaway is the durable record of what the sitting concluded, and the
# visit is additive. The pass writes exactly one key, and only to subjects it filed for.
hasnt "$TMP/updates" "gc.takeaway" "(NOCLEAR) the takeaway is never cleared or rewritten"
hasnt "$TMP/updates" "status=closed" "(NOCLEAR) nothing is ever closed"
hasnt "$TMP/calls" "bd close" "(NOCLEAR) and no close path is reached"
WROTE=$(grep -c 'update ' "$TMP/updates")
STAMPS=$(grep -c 'disposition_flagged=' "$TMP/updates")
eq "$WROTE" "$STAMPS" "(NOCLEAR) every write this pass made is a disposition_flagged stamp"
eq "$(grep -c 'set-metadata' "$TMP/updates")" "$STAMPS" "(NOCLEAR) one key per write, nothing bundled alongside"

# --- (KIDFAIL) an unreadable child listing skips that subject ------------------
FAKE_KIDS_BROKEN=s-child run kidfail
unset FAKE_KIDS_BROKEN
hasnt "$TMP/out" "s-child DISPOSITION" "(KIDFAIL) an unreadable child listing is not read as 'no children'"
has "$TMP/err" "child listing for s-child was unreadable" "(KIDFAIL) and says so on stderr"
has "$TMP/out" "1 unreadable" "(KIDFAIL) counted as unreadable, not as ready"
has "$TMP/out" "s-blocks DISPOSITION" "(KIDFAIL) while every other subject is still judged"

# --- (LISTFAIL) an unreadable open listing files nothing at all ----------------
FAKE_LIST_BROKEN=1 run listfail
unset FAKE_LIST_BROKEN
eq "$RC" "0" "(LISTFAIL) exits 0 — a patrol pass must never abort the wisp"
has "$TMP/err" "FAIL-SAFE" "(LISTFAIL) and says why"
eq "$(wc -l < "$TMP/opens")" "0" "(LISTFAIL) nothing is filed on a listing that was not read"
eq "$(wc -l < "$TMP/updates")" "0" "(LISTFAIL) and nothing is written"

# --- (VERIFY) a filing that reports success and persists nothing ---------------
FAKE_HELM_SILENT=1 run verify
unset FAKE_HELM_SILENT
has "$TMP/err" "no open visit names this subject" "(VERIFY) the filing is READ BACK, not trusted"
hasnt "$TMP/updates" "disposition_flagged" "(VERIFY) and the marker is not stamped over a visit nobody can see"
eq "$RC" "1" "(VERIFY) the pass exits non-zero so the failure is visible"

# --- (HELMFAIL) a refused filing leaves the subject unflagged ------------------
FAKE_HELM_RC=4 run helmfail
unset FAKE_HELM_RC
has "$TMP/err" "refused to file the visit (exit 4)" "(HELMFAIL) the refusal is reported, with the filer's own exit code"
hasnt "$TMP/updates" "disposition_flagged" "(HELMFAIL) and nothing is retired on it"
eq "$RC" "1" "(HELMFAIL) exits non-zero"

# --- (NOHELM) no filer: report the selection, file nothing ---------------------
# Visit filing lives in gc-helm.sh. Without it the pass can still decide, and the
# selection is the useful half — a per-subject "could not file" every cycle would bury
# the one line that says why.
export GC_HELM_TOOL="$TMP/bin/no-such-helm.sh"
run nohelm
export GC_HELM_TOOL="$TMP/bin/gc-helm.sh"
has "$TMP/err" "cannot find gc-helm.sh" "(NOHELM) the missing filer is reported once, not once per subject"
has "$TMP/out" "s-child DISPOSITION DUE" "(NOHELM) and the selection is still reported"
eq "$(wc -l < "$TMP/updates")" "0" "(NOHELM) nothing is stamped over a visit that was never filed"

# --- (DRY) --dry-run reports the same selection and writes nothing -------------
run dry --dry-run
has "$TMP/out" "s-child DISPOSITION DUE" "(DRY) the same subjects are selected"
has "$TMP/out" "(dry-run)" "(DRY) the summary says so"
eq "$(wc -l < "$TMP/opens")" "0" "(DRY) no visit is filed"
eq "$(wc -l < "$TMP/updates")" "0" "(DRY) and no marker is stamped"

# --- (REPEAT) one visit per observation across passes --------------------------
# The store persists between passes and every update bumps updated_at, so this is
# the loop that a timestamp-keyed marker turns into a visit-per-pass amplifier.
: > "$TMP/calls"; : > "$TMP/opens"
cp "$TMP/beads.json" "$FAKE_STORE"
export FAKE_CALLS="$TMP/calls" FAKE_HELM_OPENS="$TMP/opens"
rp() { export FAKE_UPDATES="$TMP/updates.$1"; : > "$FAKE_UPDATES"; "$SCRIPT" > "$TMP/rout.$1" 2>&1 || true; }

rp 1
has "$TMP/rout.1" "s-child DISPOSITION DUE" "(REPEAT p1) signalled the first time"
FLAG=$(jq -r '.[] | select(.id=="s-child") | .metadata.disposition_flagged // ""' "$FAKE_STORE")
eq "$FLAG" "w-child" "(REPEAT) the marker is the landed id set, independent of any timestamp"
UPD=$(jq -r '.[] | select(.id=="s-child") | .updated_at // ""' "$FAKE_STORE")
eq "$UPD" "2026-08-22T23:59:00Z" "(REPEAT) stamping it bumped updated_at — the real bump a last-touch key would read back"

rp 2
hasnt "$TMP/rout.2" "s-child DISPOSITION DUE" "(REPEAT p2) with its visit still open it is NOT re-signalled"
has "$TMP/rout.2" "already under an open visit" "(REPEAT p2) held by the primary guard"

# Close the visit: now only the id-keyed marker stands between the bump and a duplicate.
jq -c '[ .[] | if ((.metadata.task_kind // "") == "visit" and (.metadata["gc.continuation_group"] // "") == "s-child")
               then .status = "closed" else . end ]' "$FAKE_STORE" > "$FAKE_STORE.tmp" && mv "$FAKE_STORE.tmp" "$FAKE_STORE"
rp 3
hasnt "$TMP/rout.3" "s-child DISPOSITION DUE" "(REPEAT p3) visit closed, nothing changed: the marker keeps it silent despite the bump"
has "$TMP/rout.3" "already flagged" "(REPEAT p3) deduped by the observation key, not by the guard"
eq "$(grep -c 'open s-child' "$TMP/opens")" "1" "(REPEAT) exactly ONE visit filed for it across all three passes"

# --- (SPENT) the shared predicate detect-stalled-workflows.sh asks -------------
cp "$TMP/beads.json" "$FAKE_STORE"
export FAKE_UPDATES="$TMP/updates" FAKE_CALLS="$TMP/calls"
spent() { "$SCRIPT" --wait-spent "$1" > "$TMP/spent.out" 2>&1; echo $?; }

eq "$(spent s-child)" "0" "(SPENT) a wait recorded as a closed CHILD is spent"
has "$TMP/spent.out" "SPENT" "(SPENT) and says so"
eq "$(spent s-blocks)" "0" "(SPENT) a wait recorded as a closed blocks edge is spent"
eq "$(spent s-openchild)" "1" "(SPENT) an open child is NOT spent"
has "$TMP/spent.out" "still open: w-openkid" "(SPENT) and names what is still open"
eq "$(spent s-openblock)" "1" "(SPENT) an open blocker is NOT spent"
eq "$(spent s-nowait)" "1" "(SPENT) no recorded wait at all is NOT spent — a takeaway that named nothing keeps muting"
has "$TMP/spent.out" "no recorded wait" "(SPENT) and says which of the two 'not spent' answers it is"
eq "$(spent s-unresolved)" "1" "(SPENT) an unresolvable blocker is NOT spent"
eq "$(spent s-parentdep)" "1" "(SPENT) a closed PARENT is not routed work, so the subject is not spent"
FAKE_KIDS_BROKEN=s-child; export FAKE_KIDS_BROKEN
eq "$(spent s-child)" "1" "(SPENT) an unreadable read is NOT spent — fail-closed, the mute stays"
unset FAKE_KIDS_BROKEN

echo
echo "detect-parked-dispositions: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
