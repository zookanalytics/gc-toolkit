#!/usr/bin/env bash
# Hermetic test for detect-stalled-workflows.sh (tk-xesf6). Stubs `gc` (bd list/show/
# ready/create/update/dep, convoy status, session list) on PATH. No live city, Dolt,
# or network.
#
# The pass signals a graph.v2 workflow that stopped advancing and that nothing in the
# city can pick up. Covered:
#   (STALL)    silent, unheld, started, frontier ready+unassigned+unrouted -> ONE
#              visit filed on the standing subject, root stamped stall_flagged
#   (PRANCHOR) the same shape under an anchor carrying merge_result=pull_request is
#              STILL reported. This is the whole discrimination the pass exists for:
#              a rework molecule is poured against an anchor that already wears the
#              PREVIOUS round's PR marker, and treating that marker as proof of
#              completion is what made both live stalls (sl-xhfl, sl-jnjd) invisible
#   (LANDED)   anchor CLOSED, and anchor merge_result=merged -> exempt. The narrow
#              half of the anchor test, and the only half: measured live, three
#              husks whose anchors had landed (PR#306, PR#299) were reported by the
#              closed-step test alone
#   (MOVING)   touched inside the window -> exempt
#   (CLOSEDMOVE) the workflow's most recent write is on a CLOSED member while every
#              live member is stale -> exempt. Without reading closed members a
#              workflow that just advanced reads as stalled; verified live on
#              sl-xhfl, whose closed steps were 11 minutes NEWER than every open one
#   (NEVER)    zero closed members -> exempt (the inline-execution husk:
#              mol-polecat-work closes no step, ever, so this is most of the city)
#   (LIVEMEM)  a member held by a live session -> exempt
#   (LIVEROOT) the ROOT records a live session -> exempt; the two liveness signals
#              cover different moments and each must hold alone
#   (ROUTED)   a frontier bead carrying gc.routed_to -> exempt (demand exists; a
#              quiet pool is not this pass's business)
#   (ASSIGNED) a frontier bead with an assignee -> exempt (orphan recovery owns it)
#   (GATED)    no member is ready -> exempt, the wait has a name in the graph
#   (HOLD)     triage.hold on the root, and gc.takeaway on the ANCHOR -> exempt
#   (EMPTYHOLD) an EMPTY triage.hold is a CLEARED hold, not a hold -> still reported
#   (DEDUP)    stall_flagged already equal to the current FRONTIER key -> silent
#   (REFLAG)   ... but a stall_flagged from a DIFFERENT frontier (it advanced and
#              stalled again) is reported once more. The marker is keyed on the sorted
#              frontier bead-id set, NOT the last-touch — stamping it bumps updated_at,
#              and a last-touch key would invalidate itself (Defect A, tk-1g9yw)
#   (REPEAT)   the detector run REPEATEDLY against one persistent store, with the stub
#              bumping updated_at on every update as beads does, files ONE visit per
#              stalled bead: pass 2 skipped by the visit-already-open guard while the
#              visit is open, pass 3 (visit closed, stall unchanged) held silent by the
#              frontier marker despite the bump. On a last-touch marker pass 3 re-flags —
#              the self-defeating loop the old stub could not see
#   (SEP)      fields survive empty interior values: a root with an empty hold and a
#              non-empty title must not read as held. Joining on a TAB collapses
#              empty fields and shifts the title into triage.hold — a SILENT
#              suppression of every real signal, observed on the first live pass
#   (ORDER)    the visit is created BEFORE the marker is stamped, so a failed create
#              leaves the stall un-retired
#   (NOMARK)   a visit create that returns no id does NOT stamp the marker and exits
#              non-zero
#   (ROUTEBACK) the visit's routing metadata is READ BACK before the marker is stamped
#   (UNROUTED) a routing write that exits 0 and persists NOTHING leaves the stall
#              un-retired. An unrouted, untyped visit is offered to no pool and
#              resolved by no board row, so retiring the stall over it re-creates the
#              exact defect this pass exists to end — with the marker asserting the
#              signal was sent
#   (ROSTER)   an unreadable session roster reports NOTHING at all
#   (LISTFAIL) an unreadable bead listing reports NOTHING at all
#   (NOWRITE)  the pass never closes a bead and never writes to a member or an anchor
#   (DRY)      --dry-run reports the same selection and issues no write
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/detect-stalled-workflows.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { grep -q -- "$2" "$1" && ok "$3" || bad "$3 (not found: $2)"; }
hasnt() { grep -q -- "$2" "$1" && bad "$3 (unexpectedly found: $2)" || ok "$3"; }

mkdir -p "$TMP/bin"

OLD=$(date -u -d '-6 hours' +%Y-%m-%dT%H:%M:%SZ)
FRESH=$(date -u -d '-5 minutes' +%Y-%m-%dT%H:%M:%SZ)

# --- fixture ------------------------------------------------------------------
# This array plus closed.json are merged into one MUTABLE store per run (see run()):
# create appends to it, update mutates metadata AND bumps updated_at, and list/show/ready
# read it — so a read-back sees exactly what a write persisted. `_ready` marks the rows
# `gc bd ready` returns (the store models readiness by fiat; it does not model blockers).
# closed.json holds the closed members the per-root metadata-field query answers with.
#
# Each root is one case. Anchors are separate beads resolved through the convoy.
cat > "$TMP/beads.json" <<EOF
[
 {"id":"r-stall","title":"mol-scoped-work","status":"open","updated_at":"$OLD",
  "metadata":{"gc.kind":"workflow","gc.input_convoy_id":"c-stall"}},
 {"id":"m-stall","status":"open","updated_at":"$OLD","_ready":true,
  "metadata":{"gc.root_bead_id":"r-stall","gc.step_ref":"mol-scoped-work.workspace-setup"}},

 {"id":"r-pr","title":"mol-scoped-work","status":"open","updated_at":"$OLD",
  "metadata":{"gc.kind":"workflow","gc.input_convoy_id":"c-pr"}},
 {"id":"m-pr","status":"open","updated_at":"$OLD","_ready":true,
  "metadata":{"gc.root_bead_id":"r-pr","gc.step_ref":"mol-scoped-work.workspace-setup"}},

 {"id":"r-landed","title":"mol-scoped-work","status":"open","updated_at":"$OLD",
  "metadata":{"gc.kind":"workflow","gc.input_convoy_id":"c-landed"}},
 {"id":"m-landed","status":"open","updated_at":"$OLD","_ready":true,
  "metadata":{"gc.root_bead_id":"r-landed","gc.step_ref":"mol-polecat-work.workspace-setup"}},

 {"id":"r-merged","title":"mol-scoped-work","status":"open","updated_at":"$OLD",
  "metadata":{"gc.kind":"workflow","gc.input_convoy_id":"c-merged"}},
 {"id":"m-merged","status":"open","updated_at":"$OLD","_ready":true,
  "metadata":{"gc.root_bead_id":"r-merged","gc.step_ref":"mol-polecat-work.workspace-setup"}},

 {"id":"r-moving","title":"mol-scoped-work","status":"open","updated_at":"$FRESH",
  "metadata":{"gc.kind":"workflow","gc.input_convoy_id":"c-moving"}},
 {"id":"m-moving","status":"open","updated_at":"$OLD","_ready":true,
  "metadata":{"gc.root_bead_id":"r-moving","gc.step_ref":"mol-scoped-work.implement"}},

 {"id":"r-closedmove","title":"mol-scoped-work","status":"open","updated_at":"$OLD",
  "metadata":{"gc.kind":"workflow","gc.input_convoy_id":"c-closedmove"}},
 {"id":"m-closedmove","status":"open","updated_at":"$OLD","_ready":true,
  "metadata":{"gc.root_bead_id":"r-closedmove","gc.step_ref":"mol-scoped-work.implement"}},

 {"id":"r-never","title":"mol-polecat-work","status":"open","updated_at":"$OLD",
  "metadata":{"gc.kind":"workflow","gc.input_convoy_id":"c-never"}},
 {"id":"m-never","status":"open","updated_at":"$OLD","_ready":true,
  "metadata":{"gc.root_bead_id":"r-never","gc.step_ref":"mol-polecat-work.load-context"}},

 {"id":"r-livemem","title":"mol-scoped-work","status":"open","updated_at":"$OLD",
  "metadata":{"gc.kind":"workflow","gc.input_convoy_id":"c-livemem"}},
 {"id":"m-livemem","status":"in_progress","updated_at":"$OLD","assignee":"polecat-lx-busy",
  "metadata":{"gc.root_bead_id":"r-livemem","gc.step_ref":"mol-scoped-work.implement"}},
 {"id":"m-livemem2","status":"open","updated_at":"$OLD","_ready":true,
  "metadata":{"gc.root_bead_id":"r-livemem","gc.step_ref":"mol-scoped-work.self-review"}},

 {"id":"r-liveroot","title":"mol-scoped-work","status":"open","updated_at":"$OLD",
  "metadata":{"gc.kind":"workflow","gc.input_convoy_id":"c-liveroot","gc.session_name":"polecat-lx-busy"}},
 {"id":"m-liveroot","status":"open","updated_at":"$OLD","_ready":true,
  "metadata":{"gc.root_bead_id":"r-liveroot","gc.step_ref":"mol-scoped-work.implement"}},

 {"id":"r-routed","title":"mol-scoped-work","status":"open","updated_at":"$OLD",
  "metadata":{"gc.kind":"workflow","gc.input_convoy_id":"c-routed"}},
 {"id":"m-routed","status":"open","updated_at":"$OLD","_ready":true,
  "metadata":{"gc.root_bead_id":"r-routed","gc.step_ref":"mol-scoped-work.implement","gc.routed_to":"rig/gc-toolkit.polecat"}},

 {"id":"r-assigned","title":"mol-scoped-work","status":"open","updated_at":"$OLD",
  "metadata":{"gc.kind":"workflow","gc.input_convoy_id":"c-assigned"}},
 {"id":"m-assigned","status":"open","updated_at":"$OLD","_ready":true,"assignee":"polecat-lx-dead",
  "metadata":{"gc.root_bead_id":"r-assigned","gc.step_ref":"mol-scoped-work.implement"}},

 {"id":"r-gated","title":"mol-scoped-work","status":"open","updated_at":"$OLD",
  "metadata":{"gc.kind":"workflow","gc.input_convoy_id":"c-gated"}},
 {"id":"m-gated","status":"open","updated_at":"$OLD",
  "metadata":{"gc.root_bead_id":"r-gated","gc.step_ref":"mol-scoped-work.implement"}},

 {"id":"r-hold","title":"mol-scoped-work","status":"open","updated_at":"$OLD",
  "metadata":{"gc.kind":"workflow","gc.input_convoy_id":"c-hold","triage.hold":"waiting on the operator"}},
 {"id":"m-hold","status":"open","updated_at":"$OLD","_ready":true,
  "metadata":{"gc.root_bead_id":"r-hold","gc.step_ref":"mol-scoped-work.implement"}},

 {"id":"r-ahold","title":"mol-scoped-work","status":"open","updated_at":"$OLD",
  "metadata":{"gc.kind":"workflow","gc.input_convoy_id":"c-ahold"}},
 {"id":"m-ahold","status":"open","updated_at":"$OLD","_ready":true,
  "metadata":{"gc.root_bead_id":"r-ahold","gc.step_ref":"mol-scoped-work.implement"}},

 {"id":"r-emptyhold","title":"mol-scoped-work","status":"open","updated_at":"$OLD",
  "metadata":{"gc.kind":"workflow","gc.input_convoy_id":"c-emptyhold","triage.hold":"","gc.takeaway":""}},
 {"id":"m-emptyhold","status":"open","updated_at":"$OLD","_ready":true,
  "metadata":{"gc.root_bead_id":"r-emptyhold","gc.step_ref":"mol-scoped-work.implement"}},

 {"id":"r-dedup","title":"mol-scoped-work","status":"open","updated_at":"$OLD",
  "metadata":{"gc.kind":"workflow","gc.input_convoy_id":"c-dedup","stall_flagged":"m-dedup"}},
 {"id":"m-dedup","status":"open","updated_at":"$OLD","_ready":true,
  "metadata":{"gc.root_bead_id":"r-dedup","gc.step_ref":"mol-scoped-work.implement"}},

 {"id":"r-reflag","title":"mol-scoped-work","status":"open","updated_at":"$OLD",
  "metadata":{"gc.kind":"workflow","gc.input_convoy_id":"c-reflag","stall_flagged":"m-reflag-prev"}},
 {"id":"m-reflag","status":"open","updated_at":"$OLD","_ready":true,
  "metadata":{"gc.root_bead_id":"r-reflag","gc.step_ref":"mol-scoped-work.implement"}},

 {"id":"a-stall","status":"open","updated_at":"$OLD","metadata":{}},
 {"id":"a-pr","status":"open","updated_at":"$OLD","metadata":{"merge_result":"pull_request"}},
 {"id":"a-landed","status":"closed","updated_at":"$OLD","metadata":{"merge_result":"merged"}},
 {"id":"a-merged","status":"open","updated_at":"$OLD","metadata":{"merge_result":"merged"}},
 {"id":"a-ahold","status":"open","updated_at":"$OLD","metadata":{"gc.takeaway":"the operator is deciding"}},
 {"id":"a-plain","status":"open","updated_at":"$OLD","metadata":{}}
]
EOF

# closed members, answered per root by the --metadata-field query
cat > "$TMP/closed.json" <<EOF
[
 {"id":"c1","status":"closed","updated_at":"$OLD","metadata":{"gc.root_bead_id":"r-stall"}},
 {"id":"c2","status":"closed","updated_at":"$OLD","metadata":{"gc.root_bead_id":"r-pr"}},
 {"id":"c3","status":"closed","updated_at":"$OLD","metadata":{"gc.root_bead_id":"r-landed"}},
 {"id":"c4","status":"closed","updated_at":"$OLD","metadata":{"gc.root_bead_id":"r-merged"}},
 {"id":"c5","status":"closed","updated_at":"$OLD","metadata":{"gc.root_bead_id":"r-moving"}},
 {"id":"c6","status":"closed","updated_at":"$FRESH","metadata":{"gc.root_bead_id":"r-closedmove"}},
 {"id":"c7","status":"closed","updated_at":"$OLD","metadata":{"gc.root_bead_id":"r-livemem"}},
 {"id":"c8","status":"closed","updated_at":"$OLD","metadata":{"gc.root_bead_id":"r-liveroot"}},
 {"id":"c9","status":"closed","updated_at":"$OLD","metadata":{"gc.root_bead_id":"r-routed"}},
 {"id":"c10","status":"closed","updated_at":"$OLD","metadata":{"gc.root_bead_id":"r-assigned"}},
 {"id":"c11","status":"closed","updated_at":"$OLD","metadata":{"gc.root_bead_id":"r-gated"}},
 {"id":"c12","status":"closed","updated_at":"$OLD","metadata":{"gc.root_bead_id":"r-hold"}},
 {"id":"c13","status":"closed","updated_at":"$OLD","metadata":{"gc.root_bead_id":"r-ahold"}},
 {"id":"c14","status":"closed","updated_at":"$OLD","metadata":{"gc.root_bead_id":"r-emptyhold"}},
 {"id":"c15","status":"closed","updated_at":"$OLD","metadata":{"gc.root_bead_id":"r-dedup"}},
 {"id":"c16","status":"closed","updated_at":"$OLD","metadata":{"gc.root_bead_id":"r-reflag"}}
]
EOF

cat > "$TMP/convoys" <<'C'
c-stall|a-stall
c-pr|a-pr
c-landed|a-landed
c-merged|a-merged
c-moving|a-plain
c-closedmove|a-plain
c-never|a-plain
c-livemem|a-plain
c-liveroot|a-plain
c-routed|a-plain
c-assigned|a-plain
c-gated|a-plain
c-hold|a-plain
c-ahold|a-ahold
c-emptyhold|a-plain
c-dedup|a-plain
c-reflag|a-plain
C

cat > "$TMP/sessions.json" <<'S'
{"sessions":[{"id":"lx-busy","name":"polecat-lx-busy","state":"running","closed":false}]}
S

# --- gc stub ------------------------------------------------------------------
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
set -uo pipefail
printf '%s\n' "gc $*" >> "$FAKE_CALLS"

if [ "${1:-}" = "session" ] && [ "${2:-}" = "list" ]; then
  if [ "${FAKE_ROSTER_BROKEN:-0}" = "1" ]; then echo '{"oops":true}'; exit 0; fi
  cat "$FAKE_SESSIONS"; exit 0
fi

if [ "${1:-}" = "convoy" ] && [ "${2:-}" = "status" ]; then
  a=$(awk -F'|' -v c="${3:-}" '$1==c{print $2; exit}' "$FAKE_CONVOYS")
  [ -n "$a" ] || { echo '{"children":[]}'; exit 0; }
  jq -nc --arg a "$a" '{children:[{id:$a}]}'; exit 0
fi

if [ "${1:-}" = "bd" ]; then
  shift
  # --rig <r> is accepted and ignored: the fixture is a single store.
  [ "${1:-}" = "--rig" ] && shift 2
  sub="${1:-}"; shift || true
  case "$sub" in
    ready)
      if [ "${FAKE_READY_BROKEN:-0}" = "1" ]; then echo 'not json'; exit 0; fi
      jq -c '[.[] | select(._ready == true)]' "$FAKE_STORE"; exit 0 ;;
    show)
      # The store is mutated in place by create/update, so a read-back sees exactly what
      # the writes persisted — a real round trip, not a stub that always agrees.
      jq -c --arg i "${1:-}" '[.[] | select(.id == $i)]' "$FAKE_STORE"; exit 0 ;;
    create)
      if [ "${FAKE_CREATE_BROKEN:-0}" = "1" ]; then echo '{}'; exit 0; fi
      n=$(( $(wc -l < "$FAKE_CREATED") + 1 ))
      printf '%s\n' "$*" >> "$FAKE_CREATED"
      # A subject create is recognised by its title, so the pass gets a stable id for the
      # standing scope and a fresh one for each visit. The created bead is APPENDED to the
      # store so the read-back and the NEXT pass's visit-already-open guard see it — a
      # visit persists exactly as a real one would.
      title=""
      while [ $# -gt 0 ]; do
        [ "${1:-}" = "--title" ] && title="${2:-}"
        shift
      done
      case "$title" in
        *"triage: stalled workflows"*) nid="subject-1" ;;
        *) nid="visit-$n" ;;
      esac
      jq -c --arg id "$nid" --arg t "$title" \
        '. + [{id:$id, status:"open", title:$t, updated_at:"", metadata:{}}]' \
        "$FAKE_STORE" > "$FAKE_STORE.tmp" && mv "$FAKE_STORE.tmp" "$FAKE_STORE"
      echo "{\"id\":\"$nid\"}"
      exit 0 ;;
    update|dep)
      printf '%s\n' "$sub $*" >> "$FAKE_UPDATES"
      # `update` PERSISTS its --set-metadata pairs into the store AND bumps updated_at,
      # exactly as beads does (internal/storage/issueops/update.go: every update sets
      # updated_at = now). That bump is the whole point of the repeated-pass coverage: a
      # marker keyed on the last-touch is invalidated by its own stamp. FAKE_BUMP_TS pins
      # the bump to a controllable time, so a re-elapsed stall window is simulated without
      # sleeping. FAKE_META_LOST=1 is the write that exits 0 and stores NOTHING — the
      # silent half of that failure, the only half `|| true` on the write cannot see.
      if [ "$sub" = "update" ] && [ "${FAKE_META_LOST:-0}" != "1" ]; then
        id="${1:-}"; shift || true
        bump="${FAKE_BUMP_TS:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
        pairs=""
        while [ $# -gt 0 ]; do
          if [ "${1:-}" = "--set-metadata" ]; then pairs="${pairs}${2:-}
"; shift; fi
          shift
        done
        printf '%s' "$pairs" | jq -c -R -s --arg id "$id" --arg bump "$bump" --slurpfile store "$FAKE_STORE" '
          (split("\n") | map(select(length > 0))
           | map((index("=")) as $i
                 | if $i == null then {key: ., value: ""}
                   else {key: .[0:$i], value: .[$i+1:]} end)
           | from_entries) as $new
          | ($store[0] // [])
          | map(if .id == $id
                 then (.metadata = ((.metadata // {}) + $new)) | (.updated_at = $bump)
                 else . end)' > "$FAKE_STORE.tmp" && mv "$FAKE_STORE.tmp" "$FAKE_STORE"
      fi
      exit 0 ;;
    list)
      if [ "${FAKE_LIST_BROKEN:-0}" = "1" ]; then echo 'not json'; exit 0; fi
      # the session-bead listing this pass makes alongside the roster
      case "$*" in *--type=session*) echo '[]'; exit 0 ;; esac
      statuses=""; mdkey=""; mdval=""
      while [ $# -gt 0 ]; do
        case "$1" in
          --status=*) statuses="${1#--status=}" ;;
          --metadata-field) mdkey="${2%%=*}"; mdval="${2#*=}"; shift ;;
        esac
        shift
      done
      # One store, one filter: the status set AND (when given) a metadata-field match.
      # The non-closed branch honours --metadata-field too — the visit-already-open
      # guard relies on it to count only the visits that name THIS root (stall_root),
      # never every open visit in the store.
      jq -c --arg s "$statuses" --arg k "$mdkey" --arg v "$mdval" '
        ($s | split(",")) as $w
        | [.[] | select(.status as $st | $w | index($st))
               | select($k == "" or (((.metadata // {})[$k] // "") == $v))]' "$FAKE_STORE"
      exit 0 ;;
  esac
  echo '[]'; exit 0
fi
echo '[]'
GC
chmod +x "$TMP/bin/gc"

export PATH="$TMP/bin:$PATH"
export FAKE_BEADS="$TMP/beads.json" FAKE_CLOSED="$TMP/closed.json"
export FAKE_CONVOYS="$TMP/convoys" FAKE_SESSIONS="$TMP/sessions.json"
export FAKE_STORE="$TMP/store.json"

run() { # <label> [args...]
  : > "$TMP/updates"; : > "$TMP/created"; : > "$TMP/calls"
  # A fresh mutable store per run: beads.json (live) plus closed.json (the closed
  # members), the single source the stub reads and mutates in place.
  jq -s 'add' "$FAKE_BEADS" "$FAKE_CLOSED" > "$FAKE_STORE"
  export FAKE_UPDATES="$TMP/updates" FAKE_CREATED="$TMP/created" FAKE_CALLS="$TMP/calls"
  set +e
  "$SCRIPT" --stall-minutes 120 "$@" > "$TMP/out" 2> "$TMP/err"
  RC=$?
  set -e
}

# --- main pass ----------------------------------------------------------------
run main
eq "$RC" "0" "main pass exits 0"

has "$TMP/out" "root r-stall STALLED"   "(STALL) a silent, unheld, started, unclaimable workflow is reported"
has "$TMP/out" "root r-pr STALLED"      "(PRANCHOR) an anchor carrying merge_result=pull_request does NOT exempt — the rework case both live stalls wore"
hasnt "$TMP/out" "root r-landed STALLED"  "(LANDED) a CLOSED anchor exempts"
hasnt "$TMP/out" "root r-merged STALLED"  "(LANDED) merge_result=merged exempts"
hasnt "$TMP/out" "root r-moving STALLED"  "(MOVING) a workflow touched inside the window is exempt"
hasnt "$TMP/out" "root r-closedmove STALLED" "(CLOSEDMOVE) recent movement on a CLOSED member counts as progress"
hasnt "$TMP/out" "root r-never STALLED"   "(NEVER) zero closed members is the inline-execution husk, exempt"
hasnt "$TMP/out" "root r-livemem STALLED" "(LIVEMEM) a member held by a live session exempts"
hasnt "$TMP/out" "root r-liveroot STALLED" "(LIVEROOT) a root recording a live session exempts"
hasnt "$TMP/out" "root r-routed STALLED"  "(ROUTED) a routed frontier bead exempts"
hasnt "$TMP/out" "root r-assigned STALLED" "(ASSIGNED) an assigned frontier bead exempts"
hasnt "$TMP/out" "root r-gated STALLED"   "(GATED) no ready member means the wait has a name"
hasnt "$TMP/out" "root r-hold STALLED"    "(HOLD) triage.hold on the root exempts"
hasnt "$TMP/out" "root r-ahold STALLED"   "(HOLD) gc.takeaway on the ANCHOR exempts"
has "$TMP/out" "root r-emptyhold STALLED" "(EMPTYHOLD) an EMPTY hold is a cleared hold, not a hold"
hasnt "$TMP/out" "root r-dedup STALLED"   "(DEDUP) stall_flagged equal to the current frontier key is silent"
has "$TMP/out" "root r-reflag STALLED"    "(REFLAG) a stall_flagged from a DIFFERENT frontier (it advanced and re-stalled) is reported once more"

# (SEP) r-emptyhold carries an empty triage.hold AND a non-empty title. Joined on a
# tab those collapse and the title lands in triage.hold, silently suppressing the
# signal — which is exactly what (EMPTYHOLD) passing proves did not happen. Assert
# the mechanism directly too, so a future refactor back to @tsv fails loudly here.
grep -q 'join("\\u001f")' "$SCRIPT" \
  && ok "(SEP) rows are joined on a non-whitespace separator, so empty interior fields cannot shift" \
  || bad "(SEP) rows are no longer joined on \\u001f — empty interior fields collapse under IFS whitespace and a title reads as an operator hold"

# --- the signal itself --------------------------------------------------------
eq "$(grep -c 'triage: stalled workflows' "$TMP/created")" "1" \
  "the standing triage subject is created once, not once per stalled workflow"
eq "$(grep -c 'visit: r-' "$TMP/created")" "4" \
  "one visit per stalled workflow — r-stall, r-pr, r-emptyhold and r-reflag, all four on the one subject"
has "$TMP/updates" "stall_flagged=" "the root is stamped with the dedupe marker"
has "$TMP/updates" "task_kind=visit" "the visit is stamped as a visit"
has "$TMP/updates" "gc.routed_to=" "the visit is routed to the conversation pool"
has "$TMP/updates" "dep add" "the visit tracks the standing subject"
has "$TMP/updates" "--type=tracks" "the visit hangs off the subject by TRACKS, never parent-child"

# (ORDER) the visit must exist before the marker retires the stall. Compare the
# first create against the first stall_flagged stamp in call order.
CREATE_LINE=$(grep -n 'bd create' "$TMP/calls" | head -1 | cut -d: -f1)
# Anchored on the UPDATE call, never on the bare word: the visit's own description says
# "The root is stamped stall_flagged=<marker>", and that body text is logged as part of
# the CREATE. A bare grep therefore matches a line inside the create and the comparison
# proves nothing — it holds even if the stamp really did come first.
MARK_LINE=$(grep -n 'bd update r-.*--set-metadata stall_flagged=' "$TMP/calls" | head -1 | cut -d: -f1)
[ -n "$CREATE_LINE" ] && [ -n "$MARK_LINE" ] && [ "$CREATE_LINE" -lt "$MARK_LINE" ] \
  && ok "(ORDER) the visit is filed BEFORE the marker is stamped" \
  || bad "(ORDER) the marker was stamped before the visit existed — a failed create would retire the stall unseen"

# (ROUTEBACK) filing it is not enough: the routing must be READ BACK before the marker
# retires the stall. gc.routed_to is what offers the visit to a pool and
# gc.continuation_group is what resolves it back to the subject, so a write that did
# not land leaves a bead nobody is ever handed.
has "$TMP/updates" "gc.continuation_group=subject-1" "the visit is tied to the standing subject"
SHOW_LINE=$(grep -n 'bd show visit-' "$TMP/calls" | head -1 | cut -d: -f1)
[ -n "$SHOW_LINE" ] && [ -n "$MARK_LINE" ] && [ "$SHOW_LINE" -lt "$MARK_LINE" ] \
  && ok "(ROUTEBACK) the visit's routing is read back BEFORE the marker is stamped" \
  || bad "(ROUTEBACK) the marker was stamped without reading the visit's routing back — a --set-metadata that exits 0 without persisting would retire the stall on a signal no pool is offered"

# (NOWRITE) the pass reports; it never repairs. Nothing may be closed, and no member
# or anchor may be written.
hasnt "$TMP/updates" "--status=closed" "(NOWRITE) no bead is ever closed"
hasnt "$TMP/calls" "bd close"          "(NOWRITE) no close path at all"
hasnt "$TMP/updates" "update m-"       "(NOWRITE) no member bead is written"
hasnt "$TMP/updates" "update a-"       "(NOWRITE) no anchor is written"

# --- dry run ------------------------------------------------------------------
run dry --dry-run
eq "$RC" "0" "(DRY) dry run exits 0"
has "$TMP/out" "root r-stall STALLED" "(DRY) the same selection is reported"
eq "$(wc -l < "$TMP/updates")" "0" "(DRY) no update is issued"
eq "$(wc -l < "$TMP/created")" "0" "(DRY) no bead is created"

# --- fail-safes ---------------------------------------------------------------
FAKE_ROSTER_BROKEN=1 run roster
unset FAKE_ROSTER_BROKEN
eq "$RC" "0" "(ROSTER) an unreadable roster still exits 0 — a patrol pass never aborts"
hasnt "$TMP/out" "STALLED" "(ROSTER) an unreadable roster reports NOTHING — an unread roster makes every live molecule look unheld"
has "$TMP/err" "FAIL-SAFE" "(ROSTER) and says so on stderr"

FAKE_LIST_BROKEN=1 run listfail
unset FAKE_LIST_BROKEN
eq "$RC" "0" "(LISTFAIL) an unreadable listing still exits 0"
hasnt "$TMP/out" "STALLED" "(LISTFAIL) an unreadable listing reports NOTHING"
has "$TMP/err" "FAIL-SAFE" "(LISTFAIL) and says so on stderr"

FAKE_READY_BROKEN=1 run readyfail
unset FAKE_READY_BROKEN
hasnt "$TMP/out" "STALLED" "(LISTFAIL) an unreadable ready listing reports NOTHING — it would make every frontier look unclaimable"

# (NOMARK) a create that yields no id must not stamp the marker, and must say so.
FAKE_CREATE_BROKEN=1 run createfail
unset FAKE_CREATE_BROKEN
hasnt "$TMP/updates" "stall_flagged=" "(NOMARK) a failed create never stamps the marker"
eq "$RC" "1" "(NOMARK) and the pass exits non-zero"

# (UNROUTED) the harder half: the routing write EXITS 0 and persists nothing. The visit
# bead exists, so every guard keyed on the create still passes — and the bead is
# invisible to the converse pool and to the board. Retiring the stall over it is this
# pass's own defect, with the marker asserting the signal was sent.
FAKE_META_LOST=1 run metalost
unset FAKE_META_LOST
hasnt "$TMP/updates" "stall_flagged=" "(UNROUTED) a routing write that did not persist never stamps the marker"
eq "$RC" "1" "(UNROUTED) and the pass exits non-zero"
has "$TMP/err" "did not read back as routed" "(UNROUTED) and names the unrouted visit on stderr"
has "$TMP/out" "root r-stall STALLED" "(UNROUTED) the stall is still reported on stdout — the signal failed to durably route, not to be detected"

# --- repeated passes: ONE visit per stalled bead, with the REAL updated_at bump --------
# The stub above now bumps updated_at on every update (as beads does), which the original
# r-reflag stub did NOT — and that omission is why the self-defeating marker (Defect A,
# tk-1g9yw) was invisible to the test. Here the detector is invoked REPEATEDLY against one
# persistent store, so the marker write's own updated_at bump is in play:
#
#   pass 1  a silent, unclaimable, started workflow -> ONE visit; the root is stamped
#           stall_flagged=<frontier-key>, and that stamp bumps the root's updated_at.
#   pass 2  the SAME workflow, its visit still OPEN -> the visit-already-open guard files
#           NOTHING, even though the bump left the root freshly touched then stale again
#           (FAKE_BUMP_TS puts the bump one stall-window in the past, so the window has
#           re-elapsed — the very case the last-touch marker re-flagged forever).
#   pass 3  the visit CLOSED, the workflow still stalled and unchanged -> the guard no
#           longer applies, and the frontier-keyed marker is the backstop that keeps it
#           silent. On the OLD last-touch marker this pass RE-FLAGS (the stamp bumped
#           updated_at, so the recomputed marker differs from the stored one); on the
#           frontier key it does not, because the frontier did not change.
#
# One visit across all three passes. That is the acceptance: repeated invocation while a
# visit is open — or closed but unchanged — files no duplicate.
MP="$TMP/mp"; mkdir -p "$MP"
# One stall-window (120 min) in the past: newer than the OLD last-touch (so a last-touch
# marker WOULD change) yet older than the window (so the root re-qualifies as silent).
MP_BUMP=$(date -u -d '-3 hours' +%Y-%m-%dT%H:%M:%SZ)

cat > "$MP/beads.json" <<EOF
[
 {"id":"mr","title":"mol-scoped-work","status":"open","updated_at":"$OLD",
  "metadata":{"gc.kind":"workflow","gc.input_convoy_id":"cmr"}},
 {"id":"mm","status":"open","updated_at":"$OLD","_ready":true,
  "metadata":{"gc.root_bead_id":"mr","gc.step_ref":"mol-scoped-work.implement"}},
 {"id":"ma","status":"open","updated_at":"$OLD","metadata":{}}
]
EOF
cat > "$MP/closed.json" <<EOF
[
 {"id":"mc","status":"closed","updated_at":"$OLD","metadata":{"gc.root_bead_id":"mr"}}
]
EOF
printf 'cmr|ma\n' > "$MP/convoys"
cat > "$MP/sessions.json" <<'S'
{"sessions":[{"id":"lx-other","name":"polecat-lx-other","state":"running","closed":false}]}
S
jq -s 'add' "$MP/beads.json" "$MP/closed.json" > "$MP/store.json"
: > "$MP/created"   # accumulates creates across all passes

mp_pass() { # <label> — same store, same fixtures, every update bumped to MP_BUMP
  FAKE_STORE="$MP/store.json" FAKE_CONVOYS="$MP/convoys" FAKE_SESSIONS="$MP/sessions.json" \
  FAKE_UPDATES="$MP/updates.$1" FAKE_CREATED="$MP/created" FAKE_CALLS="$MP/calls.$1" \
  FAKE_BUMP_TS="$MP_BUMP" \
    "$SCRIPT" --stall-minutes 120 > "$MP/out.$1" 2> "$MP/err.$1" || true
}

mp_pass 1
has "$MP/out.1" "root mr STALLED" "(REPEAT p1) the workflow is reported the first time"
# The two halves of the Defect A fix, asserted directly on the store: the marker is the
# FRONTIER set (not a timestamp), and stamping it DID bump the root's updated_at.
MP_FLAG=$(jq -r '.[] | select(.id=="mr") | .metadata.stall_flagged // ""' "$MP/store.json")
eq "$MP_FLAG" "mm" "(REPEAT) stall_flagged is the sorted frontier bead-id set, independent of updated_at"
MP_UPD=$(jq -r '.[] | select(.id=="mr") | .updated_at' "$MP/store.json")
eq "$MP_UPD" "$MP_BUMP" "(REPEAT) stamping the marker bumped the root's updated_at — the real bump the old stub suppressed"

mp_pass 2
hasnt "$MP/out.2" "root mr STALLED" "(REPEAT p2) with its visit still open the workflow is NOT re-reported"
has "$MP/out.2" "1 already under an open visit" "(REPEAT p2) it is skipped by the visit-already-open guard"

# Close the visit and run again: now ONLY the frontier-keyed marker stands between the
# bumped updated_at and a duplicate. On the old last-touch marker, this pass re-flags.
jq -c '[.[] | if (((.metadata // {}).task_kind == "visit") and ((.metadata // {}).stall_root == "mr"))
              then .status = "closed" else . end]' "$MP/store.json" > "$MP/store.tmp" \
  && mv "$MP/store.tmp" "$MP/store.json"

mp_pass 3
hasnt "$MP/out.3" "root mr STALLED" "(REPEAT p3) visit closed, stall unchanged: the frontier marker keeps it silent despite the updated_at bump"
has "$MP/out.3" "1 already flagged" "(REPEAT p3) it is deduped by the frontier-keyed marker, not the guard"
has "$MP/out.3" "0 moving" "(REPEAT p3) the bump did NOT mask the stall as movement — it genuinely re-qualified as silent"

eq "$(grep -c 'visit: mr' "$MP/created")" "1" \
  "(REPEAT) exactly ONE visit filed across all three passes — the duplicate minting is gone"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
