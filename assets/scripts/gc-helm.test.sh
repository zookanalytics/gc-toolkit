#!/usr/bin/env bash
# Hermetic tests for gc-helm.sh's takeaway verb (the board half lives in
# services/helm; open, engage, accept and dismiss each have a suite of their
# own, gc-helm-<verb>.test.sh). Runs the
# REAL script with a stubbed `gc` on PATH — no live city, Dolt, network, or
# sessions. Covered:
#   --release ends the run beneath the anchor through run-cancel.sh (gascity's
#     run cancel) and writes no step or root itself, while a run the releasing
#     session holds a step of is left to close its own chain
#   --release on a CLOSED anchor: the run's end without the resurrecting park
#   the release write guarded on the status and assignee it read: a close or a
#     claim after the read refuses it, and a close takes the closed path
#   a claim a live session holds is kept: the headline alone, a nudge to its
#     holder and exit 4, while a gone holder's or this session's is released
#   --route through gc sling once the run has ended, and the refusal of a route
#     or an assignee on a detached anchor and of a route beside a named wait
#   --waiting-on edges, and the refusal of a wait in another store
#   the ≤140-codepoint length gate
#   the retired board verb refuses and names helm-svc board
#   the rig-enumeration helper leaving no trap installed on its caller
#   the react verb: an already-reacted sling skip (exit 3) re-raised as react's
#     own no-op code (5), distinct from a dispatch (0) and a real failure (4),
#     a live-workflow sling skip (exit 4) re-raised as react's code (6), a
#     dispatch-path sling skip (exit 5) re-raised as react's code (7), and a
#     standing-record sling skip (exit 6) re-raised as react's code (8)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/gc-helm.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-gc-helm-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

[ -f "$SCRIPT" ] && ok "gc-helm.sh present" || bad "gc-helm.sh missing at $SCRIPT"

mkdir -p "$TMP/bin"

# --- Fixture ------------------------------------------------------------------
# A-PARKED anchors the molecule root-PARKED (via convoy-PARKED). The run holds
# no session identity, so no step of it is the releasing session's, and the
# release ENDS that run through run-cancel.sh. gc-helm.sh writes none of its
# steps or its root: gascity's cancel closes them. The rest of the fixture is
# what the walk must leave alone:
#   s-other / root-OTHER   : a different molecule, anchored elsewhere
#   s-orphan / root-ORPHAN : a root with no convoy (anchor unresolvable)
#   s-noref                : a pinned bead with no gc.step_ref
#   s-fold / root-FOLD     : the molecule of the CLOSED anchor CLOSED-A-FOLD,
#                            which the FOLDED section releases
cat > "$TMP/steps.json" <<'JSON'
[
  {"id":"s-load","assignee":"gc-toolkit__polecat-hq-dead","metadata":{"gc.step_ref":"mol-polecat-work.load-context","gc.root_bead_id":"root-PARKED","gc.routed_to":"gc-toolkit/gc-toolkit.polecat","gc.session_affinity":"require"}},
  {"id":"s-impl","assignee":"","metadata":{"gc.step_ref":"mol-polecat-work.implement","gc.root_bead_id":"root-PARKED","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}},
  {"id":"s-held","status":"blocked","assignee":"gc-toolkit__polecat-hq-gone","metadata":{"gc.step_ref":"mol-polecat-work.workspace-setup","gc.root_bead_id":"root-PARKED","blocked_reason":"declined: premise falsified"}},
  {"id":"s-final","assignee":"","metadata":{"gc.step_ref":"mol-polecat-work.workflow-finalize","gc.root_bead_id":"root-PARKED","gc.routed_to":"gc-toolkit/core.control-dispatcher"}},
  {"id":"s-quiet","assignee":"","metadata":{"gc.step_ref":"mol-polecat-work.self-review","gc.root_bead_id":"root-PARKED"}},
  {"id":"s-nonmol","assignee":"someone","metadata":{"gc.step_ref":"mol-other-formula.step","gc.root_bead_id":"root-PARKED","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}},
  {"id":"s-noref","assignee":"someone-else","metadata":{"gc.root_bead_id":"root-PARKED","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}},
  {"id":"s-other","assignee":"gc-toolkit__polecat-hq-live","metadata":{"gc.step_ref":"mol-polecat-work.load-context","gc.root_bead_id":"root-OTHER","gc.routed_to":"gc-toolkit/gc-toolkit.polecat","gc.session_affinity":"require"}},
  {"id":"s-orphan","assignee":"gc-toolkit__polecat-hq-x","metadata":{"gc.step_ref":"mol-polecat-work.implement","gc.root_bead_id":"root-ORPHAN","gc.routed_to":"gc-toolkit/gc-toolkit.polecat","gc.session_affinity":"require"}},
  {"id":"s-NOPIN","assignee":"gc-toolkit__polecat-hq-gone","metadata":{"gc.step_ref":"mol-polecat-work.preflight-tests","gc.root_bead_id":"root-PARKED","gc.routed_to":"gc-toolkit/gc-toolkit.polecat","gc.session_affinity":"require"}},
  {"id":"root-PARKED","assignee":"","metadata":{"gc.kind":"workflow","gc.step_id":"mol-polecat-work","gc.input_convoy_id":"convoy-PARKED","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}},
  {"id":"root-OTHER","assignee":"","metadata":{"gc.kind":"workflow","gc.step_id":"mol-polecat-work","gc.input_convoy_id":"convoy-OTHER","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}},
  {"id":"root-ORPHAN","assignee":"","metadata":{"gc.kind":"workflow","gc.step_id":"mol-polecat-work","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}},
  {"id":"s-fold","assignee":"gc-toolkit__polecat-hq-gone","metadata":{"gc.step_ref":"mol-polecat-work.implement","gc.root_bead_id":"root-FOLD","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}},
  {"id":"root-FOLD","assignee":"","metadata":{"gc.kind":"workflow","gc.step_id":"mol-polecat-work","gc.input_convoy_id":"convoy-FOLD","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}}
]
JSON

# Roots: root_id|convoy_id   (root-ORPHAN deliberately absent -> no convoy)
cat > "$TMP/roots" <<'R'
root-PARKED|convoy-PARKED
root-OTHER|convoy-OTHER
root-FOLD|convoy-FOLD
R

# Convoys: convoy_id|anchor_id
# CLOSED-A-FOLD is the folded anchor: closed, superseded, and still the anchor
# of a molecule the pour left routed.
cat > "$TMP/convoys" <<'C'
convoy-PARKED|A-PARKED
convoy-OTHER|A-OTHER
convoy-FOLD|CLOSED-A-FOLD
C

# Fold dispositions: bead_id|the successor its supersedes edge names
cat > "$TMP/superseded" <<'S'
CLOSED-A-FOLD|CARRIER-1
S

: > "$TMP/updates"     # one line per `gc bd update` invocation (the full argv)

# --- gc stub ------------------------------------------------------------------
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
# A read the gctk under test makes answers through the seam holds-store.stub.sh
# keeps. A read naming a bead the suite gives a dep-list fixture starts the
# store: that bead, open and carrying the fixture's edges, each far bead the
# fixture names, and a bare open row for any other bead the read names. Every
# later read of the same call answers from it. A-PROBEDEAD and A-PROBEJUNK fail
# the read, as they fail the dep list.
if [ -n "${HOLDS_STUB_READ:-}" ] && [ "${1:-}" = bd ]; then
  shift
  case " $* " in *A-PROBEDEAD*|*A-PROBEJUNK*) echo "gc bd: simulated read failure" >&2; exit 1 ;; esac
  hs="$FAKE_DEPLISTS/.holds-store.json"
  asked=$(printf '%s\n' "$@" | awk 'p { print; exit } $0 == "--id" { p = 1 }')
  fixtures=""
  for b in $(printf '%s' "$asked" | tr ',' ' '); do
    [ -f "$FAKE_DEPLISTS/$b.json" ] && fixtures="$fixtures $b"
  done
  if [ -n "$fixtures" ] || [ ! -f "$hs" ]; then
    { for b in $fixtures; do
        jq -c --arg b "$b" '[{id: $b, status: "open", dependencies: [ .[] | {id, dependency_type} ]}] + [ .[] | del(.dependency_type) ]' "$FAKE_DEPLISTS/$b.json"
      done
      jq -nc --arg ids "$asked" '[ $ids | split(",")[] | select(. != "") | {id: ., status: "open"} ]'
    } | jq -s -c 'add // [] | unique_by(.id)' > "$hs"
  fi
  HOLDS_STORE="$hs" exec "${HOLDS_STUB:?}" answer "$@"
fi
# What the bead shows now. FAKE_STATUSES (id|status, the last line wins) sets
# a status the id prefix does not: a claim, or a close that lands between a
# release's read and its write. FAKE_ASSIGNEES (id|assignee) sets the assignee.
cur_status() {
  _cs=open; case "$1" in CLOSED-*|A-CLOSED-*) _cs=closed ;; esac
  _co="$(awk -F'|' -v i="$1" '$1==i{s=$2} END{print s}' "${FAKE_STATUSES:-/dev/null}" 2>/dev/null || true)"
  printf '%s' "${_co:-$_cs}"
}
cur_assignee() { awk -F'|' -v i="$1" '$1==i{print $2; exit}' "$FAKE_ASSIGNEES" 2>/dev/null || true; }
case "$1 ${2:-}" in
  "rig list")
    # Two rigs. gc-toolkit's path has no .beads dir, so gc-helm issues
    # un-scoped bd calls for `tk-` ids; rig-a's does, so an `ra-` id
    # exercises the rig pin.
    jq -n --arg ra "$FAKE_RA_PATH" \
       '{rigs:[{name:"gc-toolkit", path:"/nonexistent-rig", prefix:"tk"},
               {name:"rig-a", path:$ra, prefix:"ra"}]}' ;;
  "bd list")
    # Record the store this list actually read, so a lookup that searched the
    # caller's rig instead of the subject's is visible rather than silent.
    printf '%s\n' "${BEADS_DIR:-<unpinned>}" >> "$FAKE_LISTS"
    # A folded bead's `list --id` row carries its supersedes edge onto the bead
    # FAKE_SUPERSEDED names, as bd's list row carries every edge of the bead.
    _lid=""; _prev=""
    for _a in "$@"; do [ "$_prev" = "--id" ] && _lid="$_a"; _prev="$_a"; done
    _sup=""; [ -z "$_lid" ] || _sup="$(awk -F'|' -v i="$_lid" '$1==i{print $2; exit}' "$FAKE_SUPERSEDED" 2>/dev/null || true)"
    if [ -n "$_sup" ]; then
      jq -n --arg i "$_lid" --arg sp "$_sup" \
        '[{id:$i,status:"closed",dependencies:[{issue_id:$i,depends_on_id:$sp,type:"supersedes"}]}]'
      exit 0
    fi
    # A store that will not answer. Distinct from one that answers "none":
    # callers that read the two the same way act on an absence they never saw.
    # FAKE_LIST_RC is the non-answer that carries an exit code; FAKE_LIST_OUT
    # is the one that does not, and it is set to the payload to emit at rc 0.
    [ -n "${FAKE_LIST_RC:-}" ] && exit "$FAKE_LIST_RC"
    [ -n "${FAKE_LIST_OUT+x}" ] && { printf '%s' "$FAKE_LIST_OUT"; exit 0; }
    # Honor --status the way real `bd list` does, but only for a row that
    # DECLARES a status: a fixture row without one lists unconditionally, so the
    # pre-existing rows are returned exactly as before. A row that sets status is
    # filtered against the requested set, which is what lets a status=blocked
    # held step hide from an open,in_progress enumeration and surface only once
    # the caller asks for blocked too.
    _st=""
    for _a in "$@"; do case "$_a" in --status=*) _st="${_a#--status=}" ;; esac; done
    if [ -n "$_st" ]; then
      jq --arg s "$_st" '($s | split(",")) as $want
        | [ .[] | .status as $st | select(($st == null) or ($want | any(. == $st))) ]' "$FAKE_STEPS_JSON"
    else
      cat "$FAKE_STEPS_JSON"
    fi ;;
  "bd show")
    id="$3"
    # UNKNOWN- ids, and ids carrying -UNREAD, resolve to nothing, the way
    # `bd show` answers for a bead that is not there: a bare error OBJECT, never
    # an array.
    case "$id" in UNKNOWN-*|*-UNREAD*) printf '{"error":"no issues found"}\n'; exit 0 ;; esac
    # CLOSED- ids answer status=closed; everything else is open, unless
    # FAKE_STATUSES says otherwise. --release on a closed anchor ends its run
    # without the park.
    st=$(cur_status "$id")
    convoy=$(awk -F'|' -v r="$id" '$1==r{print $2; exit}' "$FAKE_ROOTS")
    # What gc.routed_to reads as: FAKE_ROUTED holds it.
    routed="$(cat "${FAKE_ROUTED:-/dev/null}" 2>/dev/null || true)"
    # What gc.execution_routed_to reads as, the pour stamp a --release retires:
    # FAKE_EXEC holds it.
    exec_routed="$(cat "${FAKE_EXEC:-/dev/null}" 2>/dev/null || true)"
    # What gc.takeaway_settled reads as. Every landed write updates it below.
    settled="$(cat "${FAKE_SETTLED:-/dev/null}" 2>/dev/null || true)"
    # What gc.takeaway, the headline itself, reads as. It lands below the same
    # way gc.takeaway_settled does.
    takeaway="$(cat "${FAKE_TAKEAWAY:-/dev/null}" 2>/dev/null || true)"
    # What gc.session_name / gc.session_id read as: the executor identity a
    # --release clears via --unset-metadata. FAKE_SNAME/FAKE_SID hold them.
    sname="$(cat "${FAKE_SNAME:-/dev/null}" 2>/dev/null || true)"
    sid="$(cat "${FAKE_SID:-/dev/null}" 2>/dev/null || true)"
    # metadata.branch is what the refinery records when work rides another bead's
    # branch; --waiting-on reads it to tell a same-branch rider from a separate
    # deliverable. Absent id -> empty, which reads the same as an absent key.
    br="$(awk -F'|' -v i="$id" '$1==i{print $2; exit}' "$FAKE_BRANCHES" 2>/dev/null || true)"
    # Top-level assignee, from FAKE_ASSIGNEES (id|assignee). --waiting-on reads it
    # as one proof a same-branch wait's work has LANDED on the branch: the handoff
    # submit-and-exit writes only after it verifies the push. Absent id -> empty.
    asg="$(awk -F'|' -v i="$id" '$1==i{print $2; exit}' "$FAKE_ASSIGNEES" 2>/dev/null || true)"
    # The bead's labels, from FAKE_LABELS (id|label, one per line): a hold a
    # release that sends the bead on lifts. Absent id -> no labels.
    lbl="$(awk -F'|' -v i="$id" '$1==i{print $2}' "${FAKE_LABELS:-/dev/null}" 2>/dev/null | jq -Rsc 'split("\n") | map(select(length > 0))')"
    if [ -n "$convoy" ]; then row=$(jq -n --arg i "$id" --arg s "$st" --arg a "$asg" --arg c "$convoy" --arg rt "$routed" --arg er "$exec_routed" --arg sd "$settled" --arg tk "$takeaway" --arg sn "$sname" --arg si "$sid" --arg br "$br" --argjson lb "${lbl:-[]}" '[{id:$i,status:$s,assignee:$a,labels:$lb,metadata:{"gc.input_convoy_id":$c,"gc.routed_to":$rt,"gc.execution_routed_to":$er,"gc.takeaway":$tk,"gc.takeaway_settled":$sd,"gc.session_name":$sn,"gc.session_id":$si,"branch":$br}}]')
    else row=$(jq -n --arg i "$id" --arg s "$st" --arg a "$asg" --arg rt "$routed" --arg er "$exec_routed" --arg sd "$settled" --arg tk "$takeaway" --arg sn "$sname" --arg si "$sid" --arg br "$br" --argjson lb "${lbl:-[]}" '[{id:$i,status:$s,assignee:$a,labels:$lb,metadata:{"gc.routed_to":$rt,"gc.execution_routed_to":$er,"gc.takeaway":$tk,"gc.takeaway_settled":$sd,"gc.session_name":$sn,"gc.session_id":$si,"branch":$br}}]'); fi
    # merge_result, from FAKE_MERGE (id|merge_result). An id carrying -HGATE is
    # a human gate, as its type and await type say.
    _mr="$(awk -F'|' -v i="$id" '$1==i{print $2; exit}' "${FAKE_MERGE:-/dev/null}" 2>/dev/null || true)"
    row=$(printf '%s' "$row" | jq -c --arg mr "$_mr" --arg i "$id" '
      (if $mr != "" then .[0].metadata.merge_result = $mr else . end)
      | (if ($i | contains("-HGATE")) then .[0].issue_type = "gate" | .[0].await_type = "human" else . end)')
    printf '%s\n' "$row" ;;
  "bd close")
    printf '%s\n' "$*" >> "$FAKE_CLOSES" ;;
  "convoy status")
    # Record each convoy resolved, so a test can prove the release confirms only
    # the ONE molecule the reverse-tracks lookup matched — not one status call
    # per open root in the store.
    printf '%s\n' "$3" >> "${FAKE_CONVOY_CALLS:-/dev/null}"
    anchor=$(awk -F'|' -v c="$3" '$1==c{print $2; exit}' "$FAKE_CONVOYS")
    if [ -n "$anchor" ]; then jq -n --arg a "$anchor" '{children:[{id:$a}]}'
    else printf '{"children":[]}\n'; fi ;;
  "bd update")
    printf '%s\n' "$*" >> "$FAKE_UPDATES"
    # A store that rejects the write. NOPIN stands for every reason a write on
    # a bead fails to land, and FAKE_UPDATE_RC refuses every update.
    case "$3" in *NOPIN*) exit 1 ;; esac
    [ -z "${FAKE_UPDATE_RC:-}" ] || exit "$FAKE_UPDATE_RC"
    # A guarded write compares --if-status and --if-assignee with what the bead
    # shows now, as bd does, and a mismatch writes nothing and exits 13.
    # FAKE_CLOSE_ON_WRITE (an id) closes the bead, and FAKE_CLAIM_ON_WRITE
    # (id|holder) claims it, just before its guarded write is compared: the
    # change that lands between a release's read and its write.
    _ifs=""; _ifa=""; _has_ifs=""; _has_ifa=""
    for a in "$@"; do
      case "$a" in
        --if-status=*)   _has_ifs=1; _ifs="${a#--if-status=}" ;;
        --if-assignee=*) _has_ifa=1; _ifa="${a#--if-assignee=}" ;;
      esac
    done
    if [ -n "$_has_ifs$_has_ifa" ]; then
      if [ "${FAKE_CLOSE_ON_WRITE:-}" = "$3" ]; then printf '%s|closed\n' "$3" >> "$FAKE_STATUSES"; fi
      if [ -n "${FAKE_CLAIM_ON_WRITE:-}" ] && [ "${FAKE_CLAIM_ON_WRITE%%|*}" = "$3" ]; then
        printf '%s|in_progress\n' "$3" >> "$FAKE_STATUSES"
        printf '%s|%s\n' "$3" "${FAKE_CLAIM_ON_WRITE#*|}" >> "$FAKE_ASSIGNEES"
      fi
      if { [ -n "$_has_ifs" ] && [ "$_ifs" != "$(cur_status "$3")" ]; } \
         || { [ -n "$_has_ifa" ] && [ "$_ifa" != "$(cur_assignee "$3")" ]; }; then
        echo "Error updating $3: the --if-assignee/--if-status precondition no longer holds" >&2
        exit 13
      fi
    fi
    # A --remove-label lands on FAKE_LABELS, by the label's exact text.
    _prev=""
    for a in "$@"; do
      if [ "$_prev" = "--remove-label" ] && [ -n "${FAKE_LABELS:-}" ]; then
        { grep -v -F -x "$3|$a" "$FAKE_LABELS" || true; } > "$FAKE_LABELS.tmp"; mv "$FAKE_LABELS.tmp" "$FAKE_LABELS"
      fi
      _prev="$a"
    done
    # The keys a release writes land here, so a read of the bead sees them.
    for a in "$@"; do
      case "$a" in
        gc.takeaway_settled=*) printf '%s' "${a#gc.takeaway_settled=}" > "$FAKE_SETTLED" ;;
        gc.takeaway=*) printf '%s' "${a#gc.takeaway=}" > "$FAKE_TAKEAWAY" ;;
        gc.execution_routed_to) : > "$FAKE_EXEC" ;;
        gc.session_name) : > "$FAKE_SNAME" ;;
        gc.session_id) : > "$FAKE_SID" ;;
      esac
    done
    ;;
  "bd dep")
    # `dep list` is a READ: it answers from a per-bead fixture and never lands
    # in FAKE_DEPS, which models the graph writes the edge assertions count.
    # A bead with no fixture has no edges. Two beads model a store the guard
    # cannot read: A-PROBEDEAD does not answer at all, and A-PROBEJUNK answers
    # the way the real `dep list` reports a bead it cannot resolve — a JSON
    # error OBJECT on stdout, beside the non-zero exit a pipeline never sees.
    if [ "${3:-}" = "list" ]; then
      case "${4:-}" in
        A-PROBEDEAD*) exit 1 ;;
        A-PROBEJUNK*) printf '{"error":"resolving %s: no issue found","schema_version":1}\n' "${4:-}"; exit 1 ;;
      esac
      if [ -f "$FAKE_DEPLISTS/${4:-}.json" ]; then cat "$FAKE_DEPLISTS/${4:-}.json"; else printf '[]\n'; fi
      exit 0
    fi
    printf '%s\n' "$*" >> "$FAKE_DEPS"
    # A blocker named NOPE stands for every edge that cannot be written.
    case "$*" in *NOPE*) exit 1 ;; esac ;;
  "session list")
    # FAKE_SESSIONS holds the listing, an empty file none; FAKE_SESSIONS_RC is
    # a list that does not read.
    [ -z "${FAKE_SESSIONS_RC:-}" ] || exit "$FAKE_SESSIONS_RC"
    if [ -s "${FAKE_SESSIONS:-/dev/null}" ]; then cat "$FAKE_SESSIONS"; else printf '{"sessions":[]}\n'; fi ;;
  "session nudge")
    printf '%s\n' "$*" >> "${FAKE_NUDGES:-/dev/null}"
    exit "${FAKE_NUDGE_RC:-0}" ;;
  "sling "*)
    # gc sling writes the route it was asked for, as a raw route does, and
    # FAKE_GC_SLING_RC refuses it. FAKE_ORDER interleaves the sling with the
    # run's end, so a test can read which came first.
    printf '%s\n' "$*" >> "${FAKE_SLINGS:-/dev/null}"
    printf 'sling %s\n' "${3:-}" >> "${FAKE_ORDER:-/dev/null}"
    if [ -n "${FAKE_GC_SLING_RC:-}" ]; then echo "gc sling: agent \"$2\" not found in city.toml" >&2; exit "$FAKE_GC_SLING_RC"; fi
    printf '%s' "$2" > "${FAKE_ROUTED:-/dev/null}" ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

# run-cancel.sh stand-in: each call's argv on one line of FAKE_CANCELS, and
# FAKE_CANCEL_RC as its exit, so a test can make a run that will not end.
cat > "$TMP/bin/run-cancel-stub" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${FAKE_CANCELS:?}"
printf 'cancel %s\n' "${2:-}" >> "${FAKE_ORDER:-/dev/null}"
[ "${FAKE_CANCEL_RC:-0}" = 0 ] || echo "run-cancel: run is not cancelled: the supervisor answered 503" >&2
exit "${FAKE_CANCEL_RC:-0}"
STUB
chmod +x "$TMP/bin/run-cancel-stub"
export GC_RUN_CANCEL_TOOL="$TMP/bin/run-cancel-stub" FAKE_CANCELS="$TMP/cancels"
: > "$TMP/cancels"

export PATH="$TMP/bin:$PATH"
# run-lib.sh's verbs answer from the fixture store that is current: the live
# store while its section's gc stub is first on PATH, the main one otherwise.
# Its rows, with a convoy row for each "convoy|anchor" line tracking that
# anchor, are judged by run-lib.sh's own run_rows, at each call.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; printf '. %q || exit 1\n' "$HERE/run-lib.sh"; cat; } > "$TMP/bin/helm-runs" <<'RUNS'
store="$FAKE_STEPS_JSON"; convoys="$FAKE_CONVOYS"
if [ -n "${LIVE_STORE:-}" ] && [ "$(command -v gc)" = "${LIVE_STORE%/*}/bin/gc" ]; then
  store="$LIVE_STORE"; convoys="$LIVE_CONVOYS"
fi
jq -c --rawfile c "$convoys" "$RUN_JQ"'
  . + [ $c | split("\n")[] | select(length > 0) | split("|")
        | {id: .[0], issue_type: "convoy", status: "open", dependencies: [{depends_on_id: .[1], type: "tracks"}]} ]
  | run_rows' "$store"
RUNS
chmod +x "$TMP/bin/helm-runs"
export GC_RUN_LIB="$HERE/run-lib.stub.sh" RUN_LIB_STUB_CMD="$TMP/bin/helm-runs" RUN_LIB_STUB_LOG="$TMP/run-lib.log"
: > "$TMP/run-lib.log"
export FAKE_STEPS_JSON="$TMP/steps.json" FAKE_ROOTS="$TMP/roots" \
       FAKE_CONVOYS="$TMP/convoys" FAKE_UPDATES="$TMP/updates" \
       FAKE_DEPS="$TMP/deps" FAKE_CLOSES="$TMP/closes" FAKE_LISTS="$TMP/lists" \
       FAKE_ROUTED="$TMP/routed" FAKE_SUPERSEDED="$TMP/superseded" \
       FAKE_SETTLED="$TMP/settled" FAKE_TAKEAWAY="$TMP/takeaway" \
       FAKE_EXEC="$TMP/exec" \
       FAKE_SNAME="$TMP/sname" FAKE_SID="$TMP/sid" FAKE_DEPLISTS="$TMP/deplists" \
       FAKE_BRANCHES="$TMP/branches" FAKE_ASSIGNEES="$TMP/assignees" \
       FAKE_CONVOY_CALLS="$TMP/convoy-calls" FAKE_LABELS="$TMP/labels" \
       FAKE_STATUSES="$TMP/statuses" FAKE_MERGE="$TMP/merge" \
       FAKE_SESSIONS="$TMP/sessions" FAKE_NUDGES="$TMP/nudges" \
       FAKE_SLINGS="$TMP/slings" FAKE_ORDER="$TMP/order"
: > "$TMP/statuses"; : > "$TMP/merge"; : > "$TMP/sessions"; : > "$TMP/nudges"
: > "$TMP/slings"; : > "$TMP/order"
mkdir -p "$TMP/rig-a/.beads" "$TMP/deplists"
# What holds a bead is the answer of gctk bead holds, built from this checkout
# and run over the dep-list fixtures below.
export HOLDS_STUB="$HERE/holds-store.stub.sh" GC_NO_API=1
GCTK_BIN="$("$HOLDS_STUB" build "$TMP/gctk")" || { echo "FAIL - gctk did not build, so no hold can be read"; exit 1; }
export GCTK_BIN
: > "$TMP/convoy-calls"

# Blocker fixtures, in the shape `gc bd dep list --direction=down --json`
# returns: one full bead row per edge, keyed .dependency_type.
#   A-BLOCKED   an open bead that is not a human gate -> the work is there
#   A-GATED     an open human gate on it -> answering it makes A-GATED the work
#   A-DONEBLK   the same delegated child, closed -> the wait is over
#   CLOSED-A-FOLD  a disposed anchor that is ALSO blocked -> two refusals
# A-PROBEDEAD and A-PROBEJUNK are answered by the stub's own arms and never
# reach these files. Each keeps a fixture anyway, carrying a live blocker.
# Teach the stub to serve it instead of failing and both probe cases go red.
# That is what proves they pass on the unreadable path and not on an empty one.
cat > "$TMP/deplists/A-BLOCKED.json" <<'J'
[{"id":"A-w-child","status":"open","dependency_type":"blocks","metadata":{}},
 {"id":"g-mine","status":"open","issue_type":"gate","await_type":"human","await_id":"rollout","dependency_type":"blocks","metadata":{}}]
J
cat > "$TMP/deplists/A-GATED.json" <<'J'
[{"id":"g-mine","status":"open","issue_type":"gate","await_type":"human","await_id":"rollout","dependency_type":"blocks","metadata":{}}]
J
cat > "$TMP/deplists/A-DONEBLK.json" <<'J'
[{"id":"A-w-child","status":"closed","dependency_type":"blocks","metadata":{}}]
J
cat > "$TMP/deplists/CLOSED-A-FOLD.json" <<'J'
[{"id":"A-w-child","status":"open","dependency_type":"blocks","metadata":{}}]
J
# A-PINNEDBLK a pinned blocker, which the store counts as none -> nothing waits
# A-WAITSFOR  a waits-for edge of its own, which the store cannot judge yet ->
#             the bead waits on its spawner, unjudged
cat > "$TMP/deplists/A-PINNEDBLK.json" <<'J'
[{"id":"w-pin","status":"pinned","dependency_type":"blocks","metadata":{}}]
J
cat > "$TMP/deplists/A-WAITSFOR.json" <<'J'
[{"id":"w-spawn","status":"closed","dependency_type":"waits-for","metadata":{}}]
J
cat > "$TMP/deplists/A-PROBEDEAD.json" <<'J'
[{"id":"A-w-child","status":"open","dependency_type":"blocks","metadata":{}}]
J
cat > "$TMP/deplists/A-PROBEJUNK.json" <<'J'
[{"id":"A-w-child","status":"open","dependency_type":"blocks","metadata":{}}]
J
export FAKE_RA_PATH="$TMP/rig-a"
: > "$TMP/deps"; : > "$TMP/closes"; : > "$TMP/lists"; : > "$TMP/routed"
: > "$TMP/settled"; : > "$TMP/takeaway"
# metadata.branch per bead, for the --waiting-on landed-rider skip. A-w-same,
# A-w-pend and A-CLOSED-w-rider all share A-ONBR's branch; A-w-diff rides its own and
# A-w-nobr has none. A-PARKED/tk-blk* stay branchless so the edge tests above them
# keep writing edges. A shared branch alone is not landing: the proof is the
# status/assignee below — A-w-same is handed off to the refinery and A-CLOSED-w-rider
# has merged (both landed riders), while A-w-pend is still open under a pool, so its
# work is not on the branch yet and its edge stands.
cat > "$TMP/branches" <<'BR'
A-ONBR|polecat/A-ONBR
A-w-same|polecat/A-ONBR
A-w-pend|polecat/A-ONBR
A-CLOSED-w-rider|polecat/A-ONBR
A-w-diff|polecat/A-w-diff
BR
# Top-level assignee per bead. The refinery is the post-push handoff that makes
# A-w-same a LANDED rider; A-w-pend's pool assignee is work still owed, not that proof.
cat > "$TMP/assignees" <<'ASG'
A-w-same|gc-toolkit/gc-toolkit.refinery
A-w-pend|gc-toolkit/gc-toolkit.polecat-3
ASG
unset GC_HELM_FIXTURE || true
# GC_RIG and BEADS_DIR too: the current-sitting lookup resolves the session's
# rig, and an ambient value from the runner's own agent env would pin a store
# the fixtures never set up.
unset GC_SESSION_NAME GC_SESSION_ID GC_ALIAS GC_AGENT GC_RIG BEADS_DIR || true

# --- Run: park A-PARKED with --release. ---------------------------------------
: > "$TMP/run-lib.log"; : > "$FAKE_CANCELS"
OUT="$(sh "$SCRIPT" takeaway A-PARKED "parked" --by proactive --release --no-wait 2>"$TMP/err" || true)"
ERR="$(cat "$TMP/err")"
UP="$TMP/updates"

line_for() { grep -E "^bd update $1( |\$)" "$UP" || true; }

# (RELEASE) an anchor still standing gets the full reopen/unassign/clear-route
# bundle. What makes that bundle correct is that A-PARKED is OPEN; the FOLDED
# section below covers the anchor whose disposition already landed.
A="$(line_for A-PARKED)"
[ -n "$A" ] && ok "(RELEASE) anchor A-PARKED was updated" || bad "(RELEASE) anchor never updated"
grep -q -- '--status=open' <<< "$A" \
  && ok "(RELEASE) anchor reopened (--status=open)" || bad "(RELEASE) anchor --status=open (got: $A)"
grep -q 'gc.proactive_reaction' <<< "$A" \
  && bad "(RELEASE) anchor still stamps the retired proactive_reaction" || ok "(RELEASE) anchor no longer stamps the retired proactive_reaction"
grep -q 'gc.routed_to= ' <<< "$A" \
  && ok "(RELEASE) anchor route cleared" || bad "(RELEASE) anchor route cleared"
# (CAS) the park is a compare-and-swap on the status and the assignee the
# release read (open, unassigned), so a close or a claim after that read
# refuses the whole write.
grep -q -- '--if-status=open --if-assignee= --status=open --assignee= ' <<< "$A" \
  && ok "(CAS) the park write is guarded on the status and the assignee it read" \
  || bad "(CAS) the park write carries no guard on what it read (got: $A)"
# The pour that dispatched this bead stamped gc.execution_routed_to; a release
# ends that pour, so the stamp is retired in the same write, and a parked or
# re-routed bead does not linger advertising a finished pour's pool.
grep -q -- '--unset-metadata gc.execution_routed_to' <<< "$A" \
  && ok "(RELEASE) anchor pour stamp (gc.execution_routed_to) retired" || bad "(RELEASE) anchor execution_routed_to cleared (got: $A)"
# The unassign takes the departing executor's identity with it: a gc.session_name
# left on an open bead that later carries a mismatched route is what
# doctor/executor-identity-residue reports, and a gc.session_id left behind is a
# stale orphan-recovery pin. Both are cleared in the release write, beside the
# assignee.
grep -q -- '--unset-metadata gc.session_name' <<< "$A" \
  && ok "(RELEASE) anchor identity pointer gc.session_name cleared" || bad "(RELEASE) anchor gc.session_name cleared (got: $A)"
grep -q -- '--unset-metadata gc.session_id' <<< "$A" \
  && ok "(RELEASE) anchor identity pointer gc.session_id cleared" || bad "(RELEASE) anchor gc.session_id cleared (got: $A)"
grep -q 'gc.takeaway_by=proactive' <<< "$A" \
  && ok "(RELEASE) anchor takeaway headline stamped" || bad "(RELEASE) anchor takeaway stamped"

# No session the run carries holds a step of the molecule under A-PARKED, so the
# release ENDS that run through gascity: one run-cancel.sh call naming its root.
# gascity's cancel closes the root and its steps, so gc-helm.sh writes none of
# them.
CANCELS="$(cat "$FAKE_CANCELS")"
grep -qE '^--root root-PARKED .*--reason ' <<< "$CANCELS" \
  && ok "(CANCEL) the run under the released anchor is cancelled through run-cancel.sh --root" \
  || bad "(CANCEL) root-PARKED was not cancelled (cancels: ${CANCELS:-<none>})"
grep -q 'took its work out of play' <<< "$CANCELS" \
  && ok "(CANCEL) …with a reason naming the release" || bad "(CANCEL) the cancel carries no reason (cancels: $CANCELS)"
eq "$(grep -c . "$FAKE_CANCELS")" "1" "(CANCEL) exactly one run is cancelled: the one the anchor launched"

# (NOMEMBER) the pack writes no step and no root of any molecule: no status, no
# route, no assignee, no close.
MEMBER_WRITES="$(grep -E '^bd update (s-|root-)' "$UP" || true)"
[ -z "$MEMBER_WRITES" ] \
  && ok "(NOMEMBER) no step or root is written by gc-helm.sh" \
  || bad "(NOMEMBER) gc-helm.sh wrote molecule members: $MEMBER_WRITES"
[ ! -s "$TMP/closes" ] \
  && ok "(NOMEMBER) …and nothing is closed by gc-helm.sh" || bad "(NOMEMBER) closes: $(cat "$TMP/closes")"

# (SCOPE) a molecule anchored elsewhere, and a root whose anchor cannot be
# resolved, are never cancelled.
grep -q 'root-OTHER' <<< "$CANCELS" \
  && bad "(SCOPE) another anchor's run was cancelled" || ok "(SCOPE) a run whose anchor != the released bead is left alone"
grep -q 'root-ORPHAN' <<< "$CANCELS" \
  && bad "(FAILCLOSE) an unresolvable root was cancelled" || ok "(FAILCLOSE) a root with no resolvable convoy is skipped (fail closed)"

# (REPORT) the run says which run it ended.
grep -q 'ended run root-PARKED of A-PARKED' <<< "$OUT" \
  && ok "(REPORT) the run reports the run it ended" || bad "(REPORT) the ended run is unreported (out: $OUT)"

# (BOUND) the resolution is keyed on the parked anchor, not the store: one
# run-lib.sh runs read for the anchor, NOT a map of every run or a read per
# open root, which would touch convoy-PARKED, convoy-OTHER and convoy-FOLD.
eq "$(grep -c '^runs ' "$TMP/run-lib.log")" "1" \
  "(BOUND) --release reads the runs of the anchor once"
eq "$(cut -d' ' -f1,3 "$TMP/run-lib.log" | grep '^runs ')" "runs A-PARKED" \
  "(BOUND) …keyed on the parked anchor itself"
eq "$(grep -c '^map ' "$TMP/run-lib.log")" "0" "(BOUND) …and never maps every run in the store"

# (CANCELFAIL) a run that does not end is not a release that landed: nothing
# retries a cancel, so the verb exits 4 after every other write, names the run
# and how to end it by hand, and keeps the release it already wrote.
: > "$UP"; : > "$FAKE_CANCELS"
CFRC=0
FAKE_CANCEL_RC=1 sh "$SCRIPT" takeaway A-PARKED "parked" --by proactive --release --no-wait \
  >"$TMP/cfout" 2>"$TMP/cferr" || CFRC=$?
eq "$CFRC" "4" "(CANCELFAIL) a cancel that does not land is a verb failure"
grep -q 'run root-PARKED of A-PARKED did not end' "$TMP/cferr" \
  && ok "(CANCELFAIL) …the run is named" || bad "(CANCELFAIL) the failed cancel is unnamed (stderr: $(cat "$TMP/cferr"))"
grep -q 'end it by hand: .*--root root-PARKED' "$TMP/cferr" \
  && ok "(CANCELFAIL) …with the command that ends it by hand" || bad "(CANCELFAIL) no repair named (stderr: $(cat "$TMP/cferr"))"
grep -qE '^bd update A-PARKED .*--status=open' "$UP" \
  && ok "(CANCELFAIL) …and the release already written is kept" || bad "(CANCELFAIL) the release write was lost: $(cat "$UP")"
grep -q 'takeaway set on' "$TMP/cfout" \
  && bad "(CANCELFAIL) the verb reported success" || ok "(CANCELFAIL) …and success is not reported"

# (RUNSUNREAD) runs that cannot be read are not runs that ended: the verb exits
# 4 after every other write, says what it could not read and how to end a run
# by hand, and cancels nothing on a guess.
: > "$UP"; : > "$FAKE_CANCELS"
RURC=0
RUN_LIB_STUB_FAIL="runs:A-PARKED" sh "$SCRIPT" takeaway A-PARKED "parked" --by proactive --release --no-wait \
  >"$TMP/ruout" 2>"$TMP/ruerr" || RURC=$?
eq "$RURC" "4" "(RUNSUNREAD) an unreadable read of the runs beneath the anchor is a verb failure"
grep -q 'could not read the runs beneath A-PARKED' "$TMP/ruerr" \
  && ok "(RUNSUNREAD) …which says what it could not read" || bad "(RUNSUNREAD) the failed read is unnamed (stderr: $(cat "$TMP/ruerr"))"
eq "$(grep -c . "$FAKE_CANCELS")" "0" "(RUNSUNREAD) …and nothing is cancelled on a guess"
grep -qE '^bd update A-PARKED .*--status=open' "$UP" \
  && ok "(RUNSUNREAD) …and the release already written is kept" || bad "(RUNSUNREAD) the release write was lost: $(cat "$UP")"

# (static) the release block writes no member: no update, close, or status write
# beyond the bd list read filter.
CBLOCK="$(awk '/# >>> cancel-release-molecules/{f=1;next} /# <<< cancel-release-molecules/{f=0} f' "$SCRIPT")"
[ -n "$CBLOCK" ] && ok "(MARKERS) the run-end block is extracted between its markers" || bad "(MARKERS) block extraction EMPTY — markers missing"
CDANGER="$(printf '%s\n' "$CBLOCK" | grep -v 'bd list --status' | grep -E 'bd update|bd close|--status=|--assignee' || true)"
[ -z "$CDANGER" ] \
  && ok "(NOMEMBER static) the run-end block writes no member; gascity's cancel does" \
  || bad "(NOMEMBER static) the run-end block writes a member: $CDANGER"

if [ -n "$ERR" ]; then printf 'note: script stderr:\n%s\n' "$ERR" >&2; fi

# ── takeaway --waiting-on: the wait as a GRAPH EDGE ────────────────
# --waiting-on writes `subject depends on <work bead>` as a `blocks` edge
# beside the prose, which is what the board re-asks. Covered:
#   (EDGE)      one flag, one edge, depends-on direction
#   (EDGEMANY)  repeatable; --waiting-on=<id> parses too
#   (EDGESTAMP) the takeaway is still stamped in the same run
#   (EDGESELF)  a bead cannot wait on itself
#   (EDGEFAIL)  a rejected edge never loses the takeaway, and the verb exits 4
#   (EDGENONE)  no flag, no edges
: > "$TMP/updates"; : > "$TMP/deps"
sh "$SCRIPT" takeaway A-PARKED "routed — the fix is slung" --by converse \
   --waiting-on A-blk1 --waiting-on=A-blk2 >/dev/null 2>"$TMP/werr" || true
DEPS="$(cat "$TMP/deps")"

grep -qE '^bd dep add A-PARKED A-blk1 -t blocks' <<< "$DEPS" \
  && ok "(EDGE) the wait is written as an edge: A-PARKED depends on A-blk1" \
  || bad "(EDGE) no depends-on edge for A-blk1 (got: ${DEPS:-<none>})"
grep -qE '^bd dep add A-PARKED A-blk2 -t blocks' <<< "$DEPS" \
  && ok "(EDGEMANY) --waiting-on repeats, and the =VALUE form parses" \
  || bad "(EDGEMANY) A-blk2 missing (got: ${DEPS:-<none>})"
eq "$(grep -c '^bd dep add' <<< "$DEPS")" "2" "(EDGEMANY) exactly one edge per flag, no duplicates"
grep -q -- '--set-metadata gc.takeaway=routed — the fix is slung' "$TMP/updates" \
  && ok "(EDGESTAMP) the takeaway itself is still stamped in the same run" \
  || bad "(EDGESTAMP) the stamp was lost: $(cat "$TMP/updates")"

# (EDGESELF) refuse a self-wait here, where the message can name the flag.
: > "$TMP/updates"; : > "$TMP/deps"
sh "$SCRIPT" takeaway A-PARKED "self" --waiting-on A-PARKED >/dev/null 2>"$TMP/werr" || true
eq "$(grep -c '^bd dep add' "$TMP/deps" || true)" "0" "(EDGESELF) a bead is never made to wait on itself"
grep -q 'bead itself' "$TMP/werr" \
  && ok "(EDGESELF) …and the refusal names the reason" \
  || bad "(EDGESELF) silent skip (stderr: $(cat "$TMP/werr"))"

# (EDGEFAIL) the takeaway is written FIRST; a failed edge warns, and the exit is
# 4, so a caller that holds on the edge does not take the wait as wired.
: > "$TMP/updates"; : > "$TMP/deps"
WRC=0
sh "$SCRIPT" takeaway A-PARKED "held for review" --waiting-on A-NOPE >/dev/null 2>"$TMP/werr" || WRC=$?
grep -q -- '--set-metadata gc.takeaway=held for review' "$TMP/updates" \
  && ok "(EDGEFAIL) a rejected edge does not cost the takeaway" \
  || bad "(EDGEFAIL) the stamp was lost when the edge failed: $(cat "$TMP/updates")"
grep -q 'could not wire' "$TMP/werr" \
  && ok "(EDGEFAIL) …and the failure is reported, not swallowed" \
  || bad "(EDGEFAIL) the failed edge was silent (stderr: $(cat "$TMP/werr"))"
eq "$WRC" "4" "(EDGEFAIL) …and the verb exits 4, the takeaway landed and the wait unwired"

# (EDGENONE) the flag is opt-in; existing callers are unchanged.
: > "$TMP/updates"; : > "$TMP/deps"
sh "$SCRIPT" takeaway A-PARKED "no edges here" >/dev/null 2>&1 || true
eq "$(grep -c '^bd dep' "$TMP/deps" || true)" "0" "(EDGENONE) no --waiting-on, no graph writes"
grep -q -- '--set-metadata gc.takeaway=no edges here' "$TMP/updates" \
  && ok "(EDGENONE) …and the plain stamp path is unchanged" \
  || bad "(EDGENONE) the plain path changed: $(cat "$TMP/updates")"

# ── takeaway --waiting-on: a LANDED rider on the SUBJECT's own branch
# A landed rider both rode A's branch (X.branch == A.branch) and has already put
# its work there, proven by a post-push state: X closed (merged), or handed off
# to the refinery. Then A's own merge is what lands X, and an edge would gate
# that merge on work that merges WITH A — merge.sh's dep-edge lane holds on it
# with no release and the PR wedges forever. So a landed rider is written as NO
# edge, and when every wait is one the sitting is stamped settled (I1: no held
# marker without an edge). Same branch WITHOUT the landing proof is not that
# case: metadata.branch is set at workspace-setup, before X pushes, so a
# still-open same-branch wait may not be on the branch yet and its edge stands.
# A wait on its own branch keeps its edge, and the fail-closed rule keeps it
# whenever the test cannot be made. Covered:
#   (EDGERIDE)     a handed-off same-branch rider writes no edge, and says why
#   (EDGERIDE)     …and the takeaway stamp still lands (subsumed, not dropped)
#   (EDGERIDE)     …and the all-rider sitting is stamped settled (keeps I1 clean)
#   (EDGECLOSED)   a merged (closed) same-branch rider is landed too — no edge
#   (EDGEUNLANDED) a same-branch wait NOT yet landed keeps its edge, unsettled
#   (EDGESEP)      a wait on its OWN branch still records its edge
#   (EDGENOBR)     a wait with no branch still records its edge (fail toward keeping)
#   (EDGENOSUBJ)   a branchless subject never skips — the guard needs A's branch
#   (EDGEMIX)      one rider + one separate: only the separate lands, unsettled
: > "$TMP/updates"; : > "$TMP/deps"
sh "$SCRIPT" takeaway A-ONBR "routed — folded onto this branch" --by converse \
   --waiting-on A-w-same >/dev/null 2>"$TMP/werr" || true
eq "$(grep -c '^bd dep add' "$TMP/deps" || true)" "0" \
  "(EDGERIDE) a wait that rode the subject's own branch writes no edge"
grep -q "landed rider on A-ONBR's own branch" "$TMP/werr" \
  && ok "(EDGERIDE) …and the skip names why (the subject's merge lands it)" \
  || bad "(EDGERIDE) the skip was silent or misworded (stderr: $(cat "$TMP/werr"))"
grep -q -- '--set-metadata gc.takeaway=routed — folded onto this branch' "$TMP/updates" \
  && ok "(EDGERIDE) …and the takeaway stamp still lands (the wait is subsumed, not lost)" \
  || bad "(EDGERIDE) the stamp was lost: $(cat "$TMP/updates")"
grep -q -- '--set-metadata gc.takeaway_settled=1' "$TMP/updates" \
  && ok "(EDGERIDE) …and the all-rider sitting is stamped settled (I1: no held marker without an edge)" \
  || bad "(EDGERIDE) all-rider takeaway left unsettled — I1 would flag it: $(cat "$TMP/updates")"

# (EDGECLOSED) the other landing proof: a same-branch rider that has MERGED.
: > "$TMP/deps"; : > "$TMP/updates"
sh "$SCRIPT" takeaway A-ONBR "routed — the rider already merged" --by converse \
   --waiting-on A-CLOSED-w-rider >/dev/null 2>&1 || true
eq "$(grep -c '^bd dep add' "$TMP/deps" || true)" "0" \
  "(EDGECLOSED) a merged same-branch rider is landed — no edge"
grep -q -- '--set-metadata gc.takeaway_settled=1' "$TMP/updates" \
  && ok "(EDGECLOSED) …and the all-rider sitting is stamped settled" \
  || bad "(EDGECLOSED) a merged rider left the sitting unsettled: $(cat "$TMP/updates")"

# (EDGEUNLANDED) the hole this fix closes: same branch, but the wait is still
# open under a pool — its work is NOT on the branch, so the edge must stand and
# the sitting must NOT settle. Dropping it would let A merge past unlanded work.
: > "$TMP/deps"; : > "$TMP/updates"
sh "$SCRIPT" takeaway A-ONBR "waiting on same-branch work still in flight" --by converse \
   --waiting-on A-w-pend >/dev/null 2>&1 || true
grep -qE '^bd dep add A-ONBR A-w-pend -t blocks' "$TMP/deps" \
  && ok "(EDGEUNLANDED) a same-branch wait not yet landed keeps its edge" \
  || bad "(EDGEUNLANDED) a same-branch wait was dropped without proof it landed (got: $(cat "$TMP/deps"))"
grep -q -- '--set-metadata gc.takeaway_settled=1' "$TMP/updates" \
  && bad "(EDGEUNLANDED) an unlanded same-branch wait must NOT settle — the edge is the hold" \
  || ok "(EDGEUNLANDED) …and the sitting stays unsettled"

: > "$TMP/deps"
sh "$SCRIPT" takeaway A-ONBR "waiting on a separate PR" --waiting-on A-w-diff >/dev/null 2>&1 || true
grep -qE '^bd dep add A-ONBR A-w-diff -t blocks' "$TMP/deps" \
  && ok "(EDGESEP) a wait on its OWN branch still records its edge" \
  || bad "(EDGESEP) the separate-deliverable edge was dropped (got: $(cat "$TMP/deps"))"

: > "$TMP/deps"
sh "$SCRIPT" takeaway A-ONBR "waiting on a branchless bead" --waiting-on A-w-nobr >/dev/null 2>&1 || true
grep -qE '^bd dep add A-ONBR A-w-nobr -t blocks' "$TMP/deps" \
  && ok "(EDGENOBR) a wait with no branch still records its edge (fail toward keeping)" \
  || bad "(EDGENOBR) a branchless wait was dropped (got: $(cat "$TMP/deps"))"

: > "$TMP/deps"
sh "$SCRIPT" takeaway A-PARKED "branchless subject" --waiting-on A-w-same >/dev/null 2>&1 || true
grep -qE '^bd dep add A-PARKED A-w-same -t blocks' "$TMP/deps" \
  && ok "(EDGENOSUBJ) a branchless subject never skips — the guard needs the subject's own branch" \
  || bad "(EDGENOSUBJ) a branchless subject wrongly skipped an edge (got: $(cat "$TMP/deps"))"

: > "$TMP/deps"; : > "$TMP/updates"
sh "$SCRIPT" takeaway A-ONBR "one rides, one is separate" \
   --waiting-on A-w-same --waiting-on A-w-diff >/dev/null 2>&1 || true
eq "$(grep -c '^bd dep add' "$TMP/deps" || true)" "1" "(EDGEMIX) exactly one edge from a rider+separate pair"
grep -qE '^bd dep add A-ONBR A-w-diff -t blocks' "$TMP/deps" \
  && ok "(EDGEMIX) …and it is the separate deliverable, not the rider" \
  || bad "(EDGEMIX) the wrong edge survived (got: $(cat "$TMP/deps"))"
grep -q -- '--set-metadata gc.takeaway_settled=1' "$TMP/updates" \
  && bad "(EDGEMIX) a mix with a real wait must NOT settle (the real edge is the hold)" \
  || ok "(EDGEMIX) …and a surviving real wait keeps the sitting unsettled"

# ── takeaway --no-wait: the disposition beside the headline ──────────────────
# One ritual, two outcomes: a sitting that settled its subject and one that
# parked it write the same sentence, and only the writer can tell them apart.
# --no-wait is that answer, and lifecycle.toml [holds] settled_keys is what
# reads it. Covered:
#   (SETTLED)   --no-wait stamps gc.takeaway_settled=1 in the headline's write
#   (UNSETTLED) every other takeaway stamps it EMPTY, so no stamp outlives its
#               own sitting and answers for the park that follows
#   (BOTH)      --no-wait and --waiting-on contradict, and nothing is written
#   (SETTLEDREL) it rides a --release --route write like the rest of the stamp
: > "$TMP/updates"; : > "$TMP/deps"
sh "$SCRIPT" takeaway A-PARKED "resolved — the board was right" --by converse --no-wait >/dev/null 2>&1 || true
U="$(cat "$TMP/updates")"
grep -q -- '--set-metadata gc.takeaway_settled=1' <<< "$U" \
  && ok "(SETTLED) --no-wait stamps the settled key" \
  || bad "(SETTLED) no settled key stamped: $U"
grep -q -- '--set-metadata gc.takeaway=resolved — the board was right' <<< "$U" \
  && ok "(SETTLED) …in the same update as the headline" \
  || bad "(SETTLED) the headline and the disposition did not ride together: $U"
eq "$(grep -c '^bd dep' "$TMP/deps" || true)" "0" "(SETTLED) …and it writes no edge, having none to write"

: > "$TMP/updates"
sh "$SCRIPT" takeaway A-PARKED "holding — needs a ruling" --by converse >/dev/null 2>&1 || true
U="$(cat "$TMP/updates")"
grep -q -- '--set-metadata gc.takeaway_settled=$' <<< "$U" \
  && ok "(UNSETTLED) a takeaway with no disposition clears the settled key" \
  || bad "(UNSETTLED) the key was left standing for the next sitting to inherit: $U"
: > "$TMP/updates"
sh "$SCRIPT" takeaway A-PARKED "routed — the fix is slung" --waiting-on A-blk1 >/dev/null 2>&1 || true
grep -q -- '--set-metadata gc.takeaway_settled=$' "$TMP/updates" \
  && ok "(UNSETTLED) …and so does a takeaway whose wait is an edge" \
  || bad "(UNSETTLED) --waiting-on left a settled key standing: $(cat "$TMP/updates")"

: > "$TMP/updates"; : > "$TMP/deps"
BRC=0
sh "$SCRIPT" takeaway A-PARKED "both" --no-wait --waiting-on A-blk1 >/dev/null 2>"$TMP/berr" || BRC=$?
eq "$BRC" "2" "(BOTH) --no-wait beside --waiting-on is refused"
eq "$(wc -c < "$TMP/updates" | tr -d ' ')" "0" "(BOTH) …before anything is written"
eq "$(grep -c '^bd dep' "$TMP/deps" || true)" "0" "(BOTH) …and no edge is wired"
grep -q 'contradicts' "$TMP/berr" \
  && ok "(BOTH) …and the refusal says why" \
  || bad "(BOTH) the refusal does not name the contradiction (stderr: $(cat "$TMP/berr"))"

# (NEITHERPARK) a --release that PARKS for a person (no --route) a bead with NO
# open blocker (A-PARKED) would leave a prose-only hold, so it must state its
# disposition — refused before anything is written, no edge wired. A bead already
# held by an open blocker is exempt (DELEGBARE, below); a --release --route
# DISPATCHES and is exempt (ROUTEOK/ROUTEFIX pass neither flag and land); a bare
# headline (no --release) parks nothing (NEITHERBARE).
: > "$TMP/updates"; : > "$TMP/deps"
NPRC=0
sh "$SCRIPT" takeaway A-PARKED "parked on prose alone" --by proactive --release >/dev/null 2>"$TMP/nperr" || NPRC=$?
eq "$NPRC" "2" "(NEITHERPARK) a --release park with neither --waiting-on nor --no-wait is refused"
eq "$(wc -c < "$TMP/updates" | tr -d ' ')" "0" "(NEITHERPARK) …before anything is written"
eq "$(grep -c '^bd dep' "$TMP/deps" || true)" "0" "(NEITHERPARK) …and no edge is wired"
grep -q 'states its disposition' "$TMP/nperr" \
  && ok "(NEITHERPARK) …and the refusal says why" \
  || bad "(NEITHERPARK) the refusal does not explain itself (stderr: $(cat "$TMP/nperr"))"
# (NEITHERBARE) a bare headline (no --release) parks nothing, so it is unaffected
# — it still stamps the headline and clears the settled key with neither flag.
: > "$TMP/updates"
sh "$SCRIPT" takeaway A-PARKED "a headline beside a gate" --by converse >/dev/null 2>"$TMP/nberr" || true
grep -q -- '--set-metadata gc.takeaway=a headline beside a gate' "$TMP/updates" \
  && ok "(NEITHERBARE) a bare takeaway with neither flag still lands" \
  || bad "(NEITHERBARE) a bare takeaway was refused or dropped: $(cat "$TMP/updates") / $(cat "$TMP/nberr")"

# (NEITHERPROBE) the park guard fails CLOSED on an unreadable probe. Unlike the
# --route guard below (DELEGPROBE/DELEGJUNK), a bare --release park that cannot
# read its blockers cannot prove an edge holds the bead, and a headline stamped
# anyway is the unedged hold this guard exists to stop. A store that will not
# answer (A-PROBEDEAD) is refused before any write, and the refusal names the
# unread probe and sends the caller to a disposition.
: > "$TMP/updates"; : > "$TMP/deps"
NPP=0
sh "$SCRIPT" takeaway A-PROBEDEAD "parked, store silent" --by proactive --release >/dev/null 2>"$TMP/nperr" || NPP=$?
eq "$NPP" "2" "(NEITHERPROBE) a park whose blocker probe will not answer is refused"
eq "$(wc -c < "$TMP/updates" | tr -d ' ')" "0" "(NEITHERPROBE) …before anything is written"
eq "$(grep -c '^bd dep' "$TMP/deps" || true)" "0" "(NEITHERPROBE) …and no edge is wired"
grep -q 'could not be read' "$TMP/nperr" \
  && ok "(NEITHERPROBE) …and the refusal says the probe did not run" \
  || bad "(NEITHERPROBE) the refusal does not name the unreadable probe (stderr: $(cat "$TMP/nperr"))"
grep -q -- '--waiting-on' "$TMP/nperr" \
  && ok "(NEITHERPROBE) …and points the caller at a disposition" \
  || bad "(NEITHERPROBE) the refusal offers no move (stderr: $(cat "$TMP/nperr"))"

# (NEITHERJUNK) the non-array error object `dep list` returns for a bead it
# cannot resolve is unreadable the same way — read as "no edges" it would pass
# the guard, so the SHAPE must refuse, not the exit code a pipeline never sees.
: > "$TMP/updates"; : > "$TMP/deps"
NPJ=0
sh "$SCRIPT" takeaway A-PROBEJUNK "parked, junk payload" --by proactive --release >/dev/null 2>"$TMP/njerr" || NPJ=$?
eq "$NPJ" "2" "(NEITHERJUNK) a park whose probe returns a non-array payload is refused too"
eq "$(wc -c < "$TMP/updates" | tr -d ' ')" "0" "(NEITHERJUNK) …before anything is written"
grep -q 'could not be read' "$TMP/njerr" \
  && ok "(NEITHERJUNK) …and it is reported unreadable, not empty" \
  || bad "(NEITHERJUNK) an error object was read as an empty edge list (stderr: $(cat "$TMP/njerr"))"

: > "$TMP/updates"
sh "$SCRIPT" takeaway A-PARKED "actionable — slung to the pool" \
   --release --route "gc-toolkit/gc-toolkit.polecat" --no-wait >/dev/null 2>&1 || true
U="$(cat "$TMP/updates")"
case "$U" in
  *"--set-metadata gc.takeaway_settled=1"*) ok "(SETTLEDREL) the disposition rides the release write" ;;
  *) bad "(SETTLEDREL) the settled key is missing from the release write: $U" ;;
esac

# ── takeaway --release --route: send the bead TO a pool ──────────────────────
# A first reaction that concludes "this is work" hands the bead on instead of
# back. The release write parks the bead and writes no route, and once the run
# beneath it has ended, gc sling routes it raw: no formula poured, no convoy
# filed. Covered:
#   (ROUTE)     the release write clears the route, and gc sling routes the
#               bead once the run beneath it has ended
#   (ROUTECLR)  no --route still clears the route (the release is unchanged)
#   (ROUTEQUAL) a bare agent name is refused before anything is written
#   (ROUTEREL)  --route without --release is refused (the unreadable half-state)
#   (ROUTEONE)  the release is one write, whose exit decides, and says where
#               the bead went
#   (REFUSED)   an update the store refuses fails the verb: no success line, no
#               edge, no run ended and no sling
POOL="gc-toolkit/gc-toolkit.polecat"
: > "$TMP/updates"; : > "$TMP/routed"; : > "$TMP/slings"; : > "$TMP/order"; : > "$FAKE_CANCELS"
sh "$SCRIPT" takeaway A-PARKED "actionable — routed to the polecat pool" \
   --by proactive --release --route "$POOL" >/dev/null 2>"$TMP/rerr" || true
RLINE="$(grep -E "^bd update A-PARKED( |$)" "$TMP/updates" | head -n1)"
case "$RLINE" in
  *"--set-metadata gc.routed_to= "*) ok "(ROUTE) the release write clears the route and writes none" ;;
  *) bad "(ROUTE) the release write does not clear the route (got: ${RLINE:-<none>})" ;;
esac
grep -q "gc.routed_to=$POOL" "$TMP/updates" \
  && bad "(ROUTE) an update wrote the pool route by hand: $(cat "$TMP/updates")" \
  || ok "(ROUTE) …and no update writes the pool route"
eq "$(cat "$TMP/slings")" "sling $POOL A-PARKED --no-formula --no-convoy" \
   "(ROUTE) the pool is reached through gc sling, raw: no formula poured, no convoy filed"
eq "$(cat "$TMP/order")" "cancel root-PARKED
sling A-PARKED" "(ROUTE) …once the run beneath the bead has ended"
case "$RLINE" in
  *"--status=open"*"--assignee="*) ok "(ROUTE) …in the same write that reopens and unassigns" ;;
  *) bad "(ROUTE) the release halves split off the route write: ${RLINE:-<none>}" ;;
esac
case "$RLINE" in
  *"--unset-metadata gc.execution_routed_to"*) ok "(ROUTE) …and the prior pour stamp is retired, not carried into the new route" ;;
  *) bad "(ROUTE) the release-to-pool write kept gc.execution_routed_to: ${RLINE:-<none>}" ;;
esac
case "$RLINE" in
  *"--set-metadata gc.takeaway=actionable — routed to the polecat pool"*) ok "(ROUTE) …and the headline still rides it" ;;
  *) bad "(ROUTE) the headline was lost: ${RLINE:-<none>}" ;;
esac

# (ROUTECLR) the plain release is untouched: it still hands the bead back.
: > "$TMP/updates"; : > "$TMP/routed"
sh "$SCRIPT" takeaway A-PARKED "back to the human" --by proactive --release --no-wait >/dev/null 2>&1 || true
grep -q -- '--set-metadata gc.routed_to= ' "$TMP/updates" \
  && ok "(ROUTECLR) no --route still clears the route" \
  || bad "(ROUTECLR) the plain release changed shape: $(cat "$TMP/updates")"

# (ROUTEQUAL) a bare name is matched against nothing and would sit forever.
: > "$TMP/updates"
QRC=0
sh "$SCRIPT" takeaway A-PARKED "bare" --release --route "gc-toolkit.polecat" >/dev/null 2>"$TMP/rerr" || QRC=$?
eq "$QRC" "2" "(ROUTEQUAL) a bare agent name is a usage error"
eq "$(grep -c '^bd update' "$TMP/updates" || true)" "0" "(ROUTEQUAL) …and nothing was written"
grep -q 'rig-qualified' "$TMP/rerr" \
  && ok "(ROUTEQUAL) …and the refusal names the cause" \
  || bad "(ROUTEQUAL) the refusal does not explain itself (stderr: $(cat "$TMP/rerr"))"

# (ROUTEREL) routed but still assigned to the reacting session reads as neither.
: > "$TMP/updates"
RRC=0
sh "$SCRIPT" takeaway A-PARKED "no release" --route "$POOL" >/dev/null 2>"$TMP/rerr" || RRC=$?
eq "$RRC" "2" "(ROUTEREL) --route without --release is a usage error"
eq "$(grep -c '^bd update' "$TMP/updates" || true)" "0" "(ROUTEREL) …and nothing was written"

# (ROUTEONE) bd applies every pair of the release as one atomic operation, so
# the release is one write, whose exit says whether all of it landed.
: > "$TMP/updates"; : > "$TMP/routed"
GRC=0
sh "$SCRIPT" takeaway A-PARKED "landed clean" --release --route "$POOL" >"$TMP/rout" 2>/dev/null || GRC=$?
eq "$GRC" "0" "(ROUTEONE) a release the store takes exits zero"
eq "$(grep -cE "^bd update A-PARKED( |\$)" "$TMP/updates" || true)" "1" \
   "(ROUTEONE) …in one write to the anchor"
grep -q "released to $POOL" "$TMP/rout" \
  && ok "(ROUTEONE) …and says where the bead went" \
  || bad "(ROUTEONE) the success line lost the route (stdout: $(cat "$TMP/rout"))"

# ── takeaway --release to a pool or an agent: the hold lifts ──────────────────
# Sending a held bead on is a placement, and Gas City serves no bead a hold
# label holds, so a --release with --route or --assign lifts hold:mayor in its
# own write. Covered:
#   (HOLDROUTE)  --route removes each spelling of hold:mayor in the release write
#   (HOLDAGENT)  --assign does the same
#   (HOLDPARK)   a release back to the person keeps the hold
printf 'A-PARKED|hold:mayor\nA-PARKED|Hold:Mayor\nA-PARKED|learning\n' > "$TMP/labels"
: > "$TMP/updates"; printf '%s' "$POOL" > "$TMP/routed"
HRC=0
sh "$SCRIPT" takeaway A-PARKED "placed — routed to the polecat pool" --release --route "$POOL" >"$TMP/hout" 2>"$TMP/herr" || HRC=$?
eq "$HRC" "0" "(HOLDROUTE) a release to a pool of a held bead exits 0"
HLINE="$(grep -E "^bd update A-PARKED( |\$)" "$TMP/updates" | head -n1)"
case "$HLINE" in
  *"--set-metadata gc.routed_to= "*"--remove-label hold:mayor --remove-label Hold:Mayor"*) ok "(HOLDROUTE) the release write that sends the bead on also lifts each spelling of its hold" ;;
  *) bad "(HOLDROUTE) the lift did not ride the release write (got: ${HLINE:-<none>})" ;;
esac
eq "$(cat "$TMP/labels")" "A-PARKED|learning" "(HOLDROUTE) the hold is gone and the other labels stay"
grep -q 'hold:mayor lifted' "$TMP/hout" \
  && ok "(HOLDROUTE) the success line says the hold was lifted" \
  || bad "(HOLDROUTE) the success line does not say so: $(cat "$TMP/hout")"
cp "$TMP/assignees" "$TMP/assignees.hold"
printf 'A-PARKED|gc-toolkit.mechanik\n' >> "$TMP/assignees"
printf 'A-PARKED|hold:mayor\n' > "$TMP/labels"
: > "$TMP/updates"; : > "$TMP/routed"
sh "$SCRIPT" takeaway A-PARKED "a city.toml edit, mechanik's" --release --assign gc-toolkit.mechanik --no-wait >/dev/null 2>&1 || true
HLINE="$(grep -E "^bd update A-PARKED( |\$)" "$TMP/updates" | head -n1 || true)"
grep -q -- '--remove-label hold:mayor' <<< "$HLINE" \
  && ok "(HOLDAGENT) a release to a named agent lifts the hold in the same write" \
  || bad "(HOLDAGENT) no lift in the release write: $(head -n1 "$TMP/updates")"
cp "$TMP/assignees.hold" "$TMP/assignees"
printf 'A-PARKED|hold:mayor\n' > "$TMP/labels"
: > "$TMP/updates"; : > "$TMP/routed"
sh "$SCRIPT" takeaway A-PARKED "back to the person" --release --no-wait >/dev/null 2>&1 || true
grep -q -- '--remove-label' "$TMP/updates" \
  && bad "(HOLDPARK) a release back to the person lifted the hold: $(cat "$TMP/updates")" \
  || ok "(HOLDPARK) a release back to the person keeps the hold"
eq "$(cat "$TMP/labels")" "A-PARKED|hold:mayor" "(HOLDPARK) …and the label stands"
: > "$TMP/labels"; : > "$TMP/routed"

# (REFUSED) the update's exit is the verdict on the whole stamp.
: > "$TMP/updates"; : > "$TMP/deps"; : > "$FAKE_CANCELS"; : > "$TMP/slings"
URC=0
FAKE_UPDATE_RC=1 sh "$SCRIPT" takeaway A-PARKED "refused" --release \
   --waiting-on A-w-child >"$TMP/rout" 2>"$TMP/rerr" || URC=$?
eq "$URC" "4" "(REFUSED) an update the store refuses is a verb runtime failure"
grep -q "could not update 'A-PARKED'" "$TMP/rerr" \
  && ok "(REFUSED) …and says the write did not land" \
  || bad "(REFUSED) the refusal was silent (stderr: $(cat "$TMP/rerr"))"
grep -q 'takeaway set on' "$TMP/rout" \
  && bad "(REFUSED) the verb reported success on a refused write" \
  || ok "(REFUSED) …and success is not reported"
eq "$(wc -l < "$TMP/deps" | tr -d ' ')|$(wc -l < "$FAKE_CANCELS" | tr -d ' ')" "0|0" \
   "(REFUSED) …with no edge written and no run ended"
URC=0
FAKE_UPDATE_RC=1 sh "$SCRIPT" takeaway A-PARKED "refused" --release --route "$POOL" >/dev/null 2>&1 || URC=$?
eq "$URC|$(wc -l < "$TMP/slings" | tr -d ' ')" "4|0" "(REFUSED) …and a --route whose release was refused is never slung"

# ── takeaway --waiting-on in another store: refused before anything is written ─
# An id's prefix names its store, and bd stores an edge onto another store's
# bead without finding it, so the edge holds nothing. The wait is refused before
# the update, so neither the headline nor an edge is written.
: > "$TMP/updates"; : > "$TMP/deps"; : > "$FAKE_CANCELS"
XRC=0
sh "$SCRIPT" takeaway A-PARKED "held for the other rig's fix" --waiting-on tk-blk9 >/dev/null 2>"$TMP/xerr" || XRC=$?
eq "$XRC" "2" "(XSTORE) a wait in another store is refused"
grep -q -- '--waiting-on tk-blk9 lives in another store than A-PARKED' "$TMP/xerr" \
  && ok "(XSTORE) …naming the wait and the store it is not in" \
  || bad "(XSTORE) the refusal does not say why (stderr: $(cat "$TMP/xerr"))"
eq "$(grep -c . "$TMP/updates" || true)" "0" "(XSTORE) …before the headline is written"
eq "$(grep -c '^bd dep add' "$TMP/deps" || true)" "0" "(XSTORE) …and with no edge written"

# ── takeaway --release on a CLOSED anchor: the run's end without the park ────
# A fold that lands after the pour leaves a molecule routed under an anchor
# that is already disposed. --release is the only writer that walks that
# molecule, and its park half (reopen, unassign, stamp the route) would
# resurrect the anchor in every reader of open beads — so the walk was
# unreachable on exactly the shape that needs it most. Covered:
#   (FOLDED)    a closed anchor keeps its disposition and still gets the walk
#   (FOLDROUTE) --route there is refused: a pool must not claim disposed work
#   (FOLDBLIND) a status that will not read refuses the release outright
: > "$TMP/updates"; : > "$TMP/routed"; : > "$FAKE_CANCELS"
CRC=0
sh "$SCRIPT" takeaway CLOSED-A-FOLD "folded into CARRIER-1" --by proactive --release \
   >"$TMP/rout" 2>"$TMP/rerr" || CRC=$?
eq "$CRC" "0" "(FOLDED) a release on a closed anchor still succeeds"
FA="$(line_for CLOSED-A-FOLD)"
[ -n "$FA" ] && ok "(FOLDED) the closed anchor is still stamped" || bad "(FOLDED) nothing was written to the anchor"
grep -q -- '--status=open' <<< "$FA" \
  && bad "(FOLDED) the closed anchor was REOPENED — disposed work is visible again ($FA)" \
  || ok "(FOLDED) …and not reopened"
grep -q -- '--assignee' <<< "$FA" \
  && bad "(FOLDED) the closed anchor was unassigned ($FA)" || ok "(FOLDED) …not unassigned"
grep -q 'gc.proactive_reaction' <<< "$FA" \
  && bad "(FOLDED) a landed disposition was re-marked as a fresh reaction ($FA)" \
  || ok "(FOLDED) …and not re-marked as a reaction release"
grep -q 'gc.routed_to' <<< "$FA" \
  && bad "(FOLDED) the closed anchor's route was rewritten ($FA)" || ok "(FOLDED) …its route left alone"
grep -q 'gc.takeaway=folded into CARRIER-1' <<< "$FA" \
  && ok "(FOLDED) …while the headline the sitting owes still lands" \
  || bad "(FOLDED) the headline was lost with the park write ($FA)"
grep -q -- '--root root-FOLD' "$FAKE_CANCELS" \
  && ok "(FOLDED) the run the fold outran is ended through run-cancel.sh" \
  || bad "(FOLDED) the folded anchor's run was never ended (cancels: $(cat "$FAKE_CANCELS"))"
grep -qE '^bd update (s-fold|root-FOLD)( |$)' "$TMP/updates" \
  && bad "(FOLDED) gc-helm.sh wrote the folded run's members itself" \
  || ok "(FOLDED) …and gc-helm.sh writes none of its members"
grep -q 'superseded by CARRIER-1' "$TMP/rerr" \
  && ok "(FOLDED) …and the run names the disposition it preserved" \
  || bad "(FOLDED) the skipped park is unexplained (stderr: $(cat "$TMP/rerr"))"
grep -q 'anchor left closed' "$TMP/rout" \
  && ok "(FOLDED) …and the success line does not claim a release it did not make" \
  || bad "(FOLDED) the run reported a release (stdout: $(cat "$TMP/rout"))"

# (FOLDROUTE) --route asks a pool to pick the bead up. On a disposed anchor
# that is the resurrection in its purest form: the pool claims it and cuts a
# branch for superseded work. The writes that DO land are kept, and the exit
# is non-zero so no caller reads it as "released to that pool". The stub is set
# to report the route as LANDED, so nothing but the closed anchor can be what
# produces the refusal.
: > "$TMP/updates"; : > "$FAKE_CANCELS"; printf '%s' "$POOL" > "$TMP/routed"
XRC=0
sh "$SCRIPT" takeaway CLOSED-A-FOLD "route a disposed bead" --by proactive --release --route "$POOL" \
   >"$TMP/rout" 2>"$TMP/rerr" || XRC=$?
eq "$XRC" "4" "(FOLDROUTE) --route on a closed anchor is a verb runtime failure"
grep -q "CLOSED-A-FOLD" "$TMP/slings" \
  && bad "(FOLDROUTE) a disposed bead was handed to a pool: $(cat "$TMP/slings")" \
  || ok "(FOLDROUTE) …and gc sling never routes it"
grep -q -- '--root root-FOLD' "$FAKE_CANCELS" \
  && ok "(FOLDROUTE) …while the run's end the operator came for still runs" \
  || bad "(FOLDROUTE) the refusal took the run's end with it"
grep -q 'takeaway set on' "$TMP/rout" \
  && bad "(FOLDROUTE) the verb reported success on an unrouted bead" \
  || ok "(FOLDROUTE) …and success is not reported"

# (FOLDBLIND) a status that did not ANSWER is not proof the anchor is open. The
# reopen is the one write whose cost is unbounded, so an unreadable status
# refuses the whole verb before anything is written.
: > "$TMP/updates"
URC=0
sh "$SCRIPT" takeaway UNKNOWN-A "unreadable" --by proactive --release >/dev/null 2>"$TMP/rerr" || URC=$?
eq "$URC" "4" "(FOLDBLIND) an unreadable status refuses the release"
eq "$(grep -c '^bd update' "$TMP/updates" || true)" "0" "(FOLDBLIND) …and nothing was written"
grep -q 'could not read the status' "$TMP/rerr" \
  && ok "(FOLDBLIND) …and the refusal names the cause" \
  || bad "(FOLDBLIND) the refusal does not explain itself (stderr: $(cat "$TMP/rerr"))"
: > "$TMP/updates"
sh "$SCRIPT" takeaway UNKNOWN-A "plain stamp" --by host >/dev/null 2>&1 || true
grep -qE '^bd update UNKNOWN-A( |$)' "$TMP/updates" \
  && ok "(FOLDBLIND) …while a takeaway WITHOUT --release is unchanged by the gate" \
  || bad "(FOLDBLIND) the gate now blocks a plain takeaway: $(cat "$TMP/updates")"

# ── takeaway --route on a DELEGATED subject: refused ─────────────────────────
# A pool route says "this bead is the work". A bead blocked by anything but a
# human gate has its work on the blocker, so the route would only wait for the
# blocker to close and then offer a bead with no method, forever. Covered:
#   (DELEG)      an open blocker that is no human gate refuses the route, before
#                any write
#   (DELEGWHY)   …and the message names the blocker and the re-run
#   (GATED)      blocked only by a human gate: the route still lands
#   (DELEGDONE)  a closed blocker is not a wait: the route still lands
#   (DELEGBARE)  the guard is scoped to --route; --release alone still stamps
#   (DELEGPROBE) a store that will not answer allows the route, and warns
#   (DELEGJUNK)  a payload that is not an edge array is unreadable the same way
#   (DELEGFOLD)  a closed anchor is refused on its disposition, not on this
: > "$TMP/updates"; : > "$TMP/deps"; printf '%s' "$POOL" > "$TMP/routed"
DRC=0
sh "$SCRIPT" takeaway A-BLOCKED "routed — the fix is slung" --by converse \
   --release --route "$POOL" >/dev/null 2>"$TMP/derr" || DRC=$?
eq "$DRC" "2" "(DELEG) an open blocker that is no human gate makes --route a usage error"
eq "$(wc -l < "$TMP/updates" | tr -d ' ')" "0" "(DELEG) …refused before any write: the bead is untouched"
grep -q 'A-w-child' "$TMP/derr" \
  && ok "(DELEGWHY) the refusal names the blocker the work is on" \
  || bad "(DELEGWHY) the blocker is unnamed (stderr: $(cat "$TMP/derr"))"
grep -q 'g-mine' "$TMP/derr" \
  && bad "(DELEGWHY) the human gate on the bead was counted as delegated work" \
  || ok "(DELEGWHY) …and a human gate on this bead is not one of them"
grep -q -- '--release alone' "$TMP/derr" \
  && ok "(DELEGWHY) …and it names the call that does land" \
  || bad "(DELEGWHY) no re-run spelled out (stderr: $(cat "$TMP/derr"))"

# (GATED) a human gate holds the bead for a person: answering it is what makes
# the bead ready, and then the bead IS the work.
: > "$TMP/updates"; printf '%s' "$POOL" > "$TMP/routed"
MRC=0
sh "$SCRIPT" takeaway A-GATED "actionable — the pool takes it once ruled" \
   --by converse --release --route "$POOL" >/dev/null 2>"$TMP/derr" || MRC=$?
eq "$MRC" "0" "(GATED) a bead blocked only by a human gate still routes"
grep -q "^sling $POOL A-GATED " "$TMP/slings" \
  && ok "(GATED) …and gc sling routes it" \
  || bad "(GATED) the route was lost: $(cat "$TMP/slings")"
grep -q 'could not read the blockers' "$TMP/derr" \
  && bad "(GATED) a probe that answered still warned it had not (stderr: $(cat "$TMP/derr"))" \
  || ok "(GATED) …and a probe that answered says nothing: the warning stays a signal"

# (DELEGDONE) a closed blocker is history, not a wait.
: > "$TMP/updates"; printf '%s' "$POOL" > "$TMP/routed"
CRC2=0
sh "$SCRIPT" takeaway A-DONEBLK "actionable — nothing outstanding" \
   --release --route "$POOL" >/dev/null 2>"$TMP/derr" || CRC2=$?
eq "$CRC2" "0" "(DELEGDONE) a closed blocker does not refuse the route"

# (DELEGPIN) a pinned blocker holds nothing, as the store counts it, so the
# route lands.
: > "$TMP/updates"; printf '%s' "$POOL" > "$TMP/routed"
CRC3=0
sh "$SCRIPT" takeaway A-PINNEDBLK "actionable — its blocker is pinned" \
   --release --route "$POOL" >/dev/null 2>"$TMP/derr" || CRC3=$?
eq "$CRC3" "0" "(DELEGPIN) a pinned blocker does not refuse the route"

# (DELEGWAITS) a waits-for edge of the bead's own is a wait the store cannot
# judge yet, so the bead's work may still sit on its spawner: the route is
# refused, and the refusal names the spawner.
: > "$TMP/updates"; printf '%s' "$POOL" > "$TMP/routed"
WRC=0
sh "$SCRIPT" takeaway A-WAITSFOR "routed — it waits for its spawner" --by converse \
   --release --route "$POOL" >/dev/null 2>"$TMP/derr" || WRC=$?
eq "$WRC" "2" "(DELEGWAITS) a waits-for edge of its own refuses the route"
grep -q 'w-spawn' "$TMP/derr" \
  && ok "(DELEGWAITS) …and the refusal names the spawner" \
  || bad "(DELEGWAITS) the spawner is unnamed (stderr: $(cat "$TMP/derr"))"
eq "$(wc -l < "$TMP/updates" | tr -d ' ')" "0" "(DELEGWAITS) …before any write"

# (DELEGBARE) the release without a route is the disposition this guard sends
# callers back to, so it has to keep working on the very bead it refuses.
: > "$TMP/updates"
BRC=0
sh "$SCRIPT" takeaway A-BLOCKED "ruled — the work is on the child" \
   --by converse --release >/dev/null 2>"$TMP/derr" || BRC=$?
eq "$BRC" "0" "(DELEGBARE) --release alone on the same bead is not refused"
grep -q -- '--set-metadata gc.takeaway=ruled — the work is on the child' "$TMP/updates" \
  && ok "(DELEGBARE) …and the headline lands" \
  || bad "(DELEGBARE) the stamp was lost: $(cat "$TMP/updates")"

# (DELEGPROBE) a store that will not answer must not cost a sitting its
# disposition. The guard degrades to the behaviour it replaced, and says it
# did: "no blockers" and "never looked" are otherwise the same silence.
: > "$TMP/updates"; printf '%s' "$POOL" > "$TMP/routed"
PRC=0
sh "$SCRIPT" takeaway A-PROBEDEAD "actionable — routed" \
   --release --route "$POOL" >/dev/null 2>"$TMP/derr" || PRC=$?
eq "$PRC" "0" "(DELEGPROBE) an unreadable blocker probe allows the route"
grep -q "^sling $POOL A-PROBEDEAD " "$TMP/slings" \
  && ok "(DELEGPROBE) …and gc sling routes it" \
  || bad "(DELEGPROBE) the route was lost: $(cat "$TMP/slings")"
grep -q 'could not read the blockers on A-PROBEDEAD' "$TMP/derr" \
  && ok "(DELEGPROBE) …and the caller is told the check did not run" \
  || bad "(DELEGPROBE) the guard was skipped in silence (stderr: $(cat "$TMP/derr"))"
grep -q -- '--release alone' "$TMP/derr" \
  && ok "(DELEGPROBE) …and named the call that needs no probe" \
  || bad "(DELEGPROBE) the warning offers no move (stderr: $(cat "$TMP/derr"))"

# (DELEGJUNK) `dep list` reports a bead it cannot resolve as a JSON error
# object on stdout. A pipeline never sees the exit code, so the SHAPE is the
# only signal, and reading it as "no edges" would silently pass the guard.
: > "$TMP/updates"; printf '%s' "$POOL" > "$TMP/routed"
JRC=0
sh "$SCRIPT" takeaway A-PROBEJUNK "actionable — routed" \
   --release --route "$POOL" >/dev/null 2>"$TMP/derr" || JRC=$?
eq "$JRC" "0" "(DELEGJUNK) a non-array payload allows the route too"
grep -q "^sling $POOL A-PROBEJUNK " "$TMP/slings" \
  && ok "(DELEGJUNK) …and gc sling routes it" \
  || bad "(DELEGJUNK) the route was lost: $(cat "$TMP/slings")"
grep -q 'could not read the blockers on A-PROBEJUNK' "$TMP/derr" \
  && ok "(DELEGJUNK) …and it is reported unreadable, not empty" \
  || bad "(DELEGJUNK) an error object was read as an edge list (stderr: $(cat "$TMP/derr"))"

# (DELEGFOLD) a closed anchor blocked by delegated work meets two refusals.
# This one yields: refusing here would exit before the headline and the run's
# end a folded anchor still needs, and a disposed bead is never routed anyway.
: > "$TMP/updates"; : > "$FAKE_CANCELS"; printf '%s' "$POOL" > "$TMP/routed"
FRC=0
sh "$SCRIPT" takeaway CLOSED-A-FOLD "folded, and blocked" --by converse \
   --release --route "$POOL" >/dev/null 2>"$TMP/derr" || FRC=$?
eq "$FRC" "4" "(DELEGFOLD) a closed anchor is refused on its disposition"
grep -q 'has no method a pool can perform' "$TMP/derr" \
  && bad "(DELEGFOLD) the blocker refusal preempted it (stderr: $(cat "$TMP/derr"))" \
  || ok "(DELEGFOLD) …not on its blockers"
grep -q -- '--root root-FOLD' "$FAKE_CANCELS" \
  && ok "(DELEGFOLD) …so the run's end a fold still needs survives the refusal" \
  || bad "(DELEGFOLD) the run's end was lost: $(cat "$FAKE_CANCELS")"

# ── takeaway --release --assign: release the bead TO a named agent ────────────
# The pack addresses a named agent by its assignee (docs/deferred-dispatch.md),
# so work that is its own (a town-repo edit is mechanik's) is released to it as
# its assignee, with no route. The stub reads a bead's assignee from the
# assignees fixture, and the release's guarded write compares its guard with
# that row. Covered:
#   (TOAGENT)      the assignee replaces the empty clear in the one release
#                  write, and the route beside it stays empty
#   (TOAGENTOK)    the release is written once, exits 0, and the success
#                  line names the agent
#   (TOAGENTREL)   --assign without --release is refused
#   (TOAGENTBOTH)  --assign beside --route is refused before any write
#   (TOAGENTBLK)   an open blocker that is no human gate refuses a bare --assign
#   (TOAGENTWAIT)  …and a call that names its waits lands, edge and all
#   (TOAGENTFOLD)  a closed anchor is refused on its disposition, run's end kept
AGENT="gc-toolkit.mechanik"
cp "$TMP/assignees" "$TMP/assignees.orig"
printf 'A-PARKED|%s\nA-BLOCKED|%s\n' "$AGENT" "$AGENT" >> "$TMP/assignees"
: > "$TMP/updates"; : > "$TMP/routed"
ARC=0
sh "$SCRIPT" takeaway A-PARKED "actionable — a city.toml edit, mechanik's" \
   --by proactive --release --assign "$AGENT" --no-wait >"$TMP/aout" 2>"$TMP/aerr" || ARC=$?
ALINE="$(grep -E "^bd update A-PARKED( |\$)" "$TMP/updates" | head -n1)"
case "$ALINE" in
  *"--status=open --assignee=$AGENT --set-metadata gc.routed_to= "*) ok "(TOAGENT) the release assigns the bead to the named agent, with no route beside it" ;;
  *) bad "(TOAGENT) the release write did not assign the agent with an empty route (got: ${ALINE:-<none>})" ;;
esac
case "$ALINE" in
  *"--if-status=open --if-assignee=$AGENT "*) ok "(TOAGENT) …guarded on the open bead and the assignee the release read" ;;
  *) bad "(TOAGENT) the assign write is not guarded on what the release read (got: ${ALINE:-<none>})" ;;
esac
case "$ALINE" in
  *"--set-metadata gc.takeaway=actionable — a city.toml edit, mechanik's"*) ok "(TOAGENT) …in the write that carries the headline" ;;
  *) bad "(TOAGENT) the headline split off the assign write: ${ALINE:-<none>}" ;;
esac
case "$ALINE" in
  *"gc.proactive_reaction"*) bad "(TOAGENT) the assign write still stamps the retired proactive_reaction: ${ALINE:-<none>}" ;;
  *) ok "(TOAGENT) …and stamps no retired proactive_reaction beside it" ;;
esac
case "$ALINE" in
  *"--unset-metadata gc.session_name --unset-metadata gc.session_id"*) ok "(TOAGENT) …and the prior executor's session pins go with the old assignee" ;;
  *) bad "(TOAGENT) the assign write kept the prior executor's pins: ${ALINE:-<none>}" ;;
esac
eq "$ARC" "0" "(TOAGENTOK) a release to an agent exits 0"
eq "$(grep -cE "^bd update A-PARKED( |\$)" "$TMP/updates" || true)" "1" \
   "(TOAGENTOK) …and is written once"
grep -q "released to $AGENT" "$TMP/aout" \
  && ok "(TOAGENTOK) …and the success line names the agent" \
  || bad "(TOAGENTOK) the success line lost the agent (stdout: $(cat "$TMP/aout"))"

: > "$TMP/updates"
RRC2=0
sh "$SCRIPT" takeaway A-PARKED "no release" --assign "$AGENT" >/dev/null 2>"$TMP/aerr" || RRC2=$?
eq "$RRC2" "2" "(TOAGENTREL) --assign without --release is a usage error"
eq "$(grep -c '^bd update' "$TMP/updates" || true)" "0" "(TOAGENTREL) …and nothing was written"

: > "$TMP/updates"
BRC3=0
sh "$SCRIPT" takeaway A-PARKED "both" --release --route "$POOL" --assign "$AGENT" >/dev/null 2>"$TMP/aerr" || BRC3=$?
eq "$BRC3" "2" "(TOAGENTBOTH) --assign beside --route is a usage error"
eq "$(grep -c '^bd update' "$TMP/updates" || true)" "0" "(TOAGENTBOTH) …and nothing was written"
grep -q 'never both' "$TMP/aerr" \
  && ok "(TOAGENTBOTH) …and the refusal says a bead takes one address" \
  || bad "(TOAGENTBOTH) the refusal does not explain itself (stderr: $(cat "$TMP/aerr"))"

: > "$TMP/updates"; : > "$TMP/deps"
KRC=0
sh "$SCRIPT" takeaway A-BLOCKED "assigned — the fix is mechanik's" \
   --release --assign "$AGENT" --no-wait >/dev/null 2>"$TMP/aerr" || KRC=$?
eq "$KRC" "2" "(TOAGENTBLK) an open blocker that is no human gate refuses a bare --assign"
eq "$(wc -l < "$TMP/updates" | tr -d ' ')" "0" "(TOAGENTBLK) …before any write"
grep -q 'A-w-child' "$TMP/aerr" \
  && ok "(TOAGENTBLK) …naming the blocker the work is on" \
  || bad "(TOAGENTBLK) the blocker is unnamed (stderr: $(cat "$TMP/aerr"))"
grep -q -- '--then-assign' "$TMP/aerr" \
  && ok "(TOAGENTBLK) …and the blocked exit that names the wait" \
  || bad "(TOAGENTBLK) no blocked-exit re-run named (stderr: $(cat "$TMP/aerr"))"

: > "$TMP/updates"; : > "$TMP/deps"
WRC3=0
sh "$SCRIPT" takeaway A-BLOCKED "held — mechanik edits once the child lands" \
   --release --assign "$AGENT" --waiting-on A-w-child >/dev/null 2>"$TMP/aerr" || WRC3=$?
eq "$WRC3" "0" "(TOAGENTWAIT) an --assign that names its wait lands"
grep -qE "^bd update A-BLOCKED .*--assignee=$AGENT" "$TMP/updates" \
  && ok "(TOAGENTWAIT) …assigned to the agent" \
  || bad "(TOAGENTWAIT) the assignee was lost: $(cat "$TMP/updates")"
grep -qE '^bd dep add A-BLOCKED A-w-child -t blocks' "$TMP/deps" \
  && ok "(TOAGENTWAIT) …and held on the named wait, which gates the hand-off" \
  || bad "(TOAGENTWAIT) the wait edge was not written (got: $(cat "$TMP/deps"))"

: > "$TMP/updates"; : > "$FAKE_CANCELS"
FRC3=0
sh "$SCRIPT" takeaway CLOSED-A-FOLD "assign a disposed bead" --by proactive \
   --release --assign "$AGENT" >"$TMP/aout" 2>"$TMP/aerr" || FRC3=$?
eq "$FRC3" "4" "(TOAGENTFOLD) --assign on a closed anchor is a verb runtime failure"
grep -q -- '--assignee' <<< "$(line_for CLOSED-A-FOLD)" \
  && bad "(TOAGENTFOLD) a disposed bead was handed to an agent" \
  || ok "(TOAGENTFOLD) …and the agent is never assigned"
grep -q 'NOT assigned' "$TMP/aerr" \
  && ok "(TOAGENTFOLD) …and the refusal says so" \
  || bad "(TOAGENTFOLD) the refusal is unexplained (stderr: $(cat "$TMP/aerr"))"
grep -q -- '--root root-FOLD' "$FAKE_CANCELS" \
  && ok "(TOAGENTFOLD) …while the run's end a fold still needs runs" \
  || bad "(TOAGENTFOLD) the refusal took the run's end with it"
mv "$TMP/assignees.orig" "$TMP/assignees"

# ── takeaway --release: the guarded park, a held claim, a detached anchor ─────
# The park write is a compare-and-swap on the status and the assignee the
# release read, a claim is taken from no live session, a --route or an --assign
# sends on no anchor the merge cadence drives, and a --route reaches its pool
# only through gc sling. Covered:
#   (RACECLOSE)  a close between the read and the write refuses the park, and
#                the bead keeps its close, takes the headline alone and still
#                has its run ended; a --route on it is never slung
#   (RACECLAIM)  a claim between the read and the write: nothing more is
#                written, and the exit names who holds it now
#   (HELD)       a claim a live session holds: the headline alone, its waits,
#                a nudge to its holder, and exit 4 naming the holder
#   (HELDROUTE)  …and a --route on it is not slung
#   (HELDUNREAD) a session list that does not read keeps the claim, and the
#                holder is nudged by its own name
#   (HELDNUDGE)  a nudge that does not land is said
#   (GONE)       a claim whose holder the list does not name is released in the
#                park's one guarded write
#   (MINE)       this session's own claim is released with no session list read
#   (DETACHED)   --route and --assign are refused on a detached anchor before
#                any write, and --release alone still lands
#   (NAMEDWAIT)  a --route beside a named wait that is open and no human gate,
#                or whose row does not read, is refused before any write; one
#                onto a human gate or a closed bead still routes
#   (SLINGFAIL)  a sling that fails is a verb failure that names the repair,
#                with the release kept
#   (SLINGHOLD)  a run that did not end, or a wait that did not wire, sends
#                nothing to the pool
last_status() { awk -F'|' -v i="$1" '$1==i{s=$2} END{print s}' "$TMP/statuses"; }
# (RACECLOSE) the bead closes after the release read it open, before its write.
: > "$TMP/updates"; : > "$TMP/deps"; : > "$FAKE_CANCELS"; : > "$TMP/slings"; : > "$TMP/statuses"
RCRC=0
FAKE_CLOSE_ON_WRITE=A-PARKED sh "$SCRIPT" takeaway A-PARKED "parked — its premise fell" --by converse \
   --release --no-wait >"$TMP/rcout" 2>"$TMP/rcerr" || RCRC=$?
eq "$RCRC" "0" "(RACECLOSE) a release on a bead that closed after its read still exits 0"
RC1="$(sed -n 1p "$TMP/updates")"; RC2="$(sed -n 2p "$TMP/updates")"
grep -q -- '--if-status=open --if-assignee= --status=open' <<< "$RC1" \
  && ok "(RACECLOSE) the park write was guarded on the open bead the release read" \
  || bad "(RACECLOSE) the first write was not the guarded park (got: ${RC1:-<none>})"
eq "$(last_status A-PARKED)" "closed" "(RACECLOSE) …so the close stands"
grep -q -- '--set-metadata gc.takeaway=parked — its premise fell' <<< "$RC2" \
  && ok "(RACECLOSE) …and the headline lands on the closed bead" \
  || bad "(RACECLOSE) the headline was lost (got: ${RC2:-<none>})"
grep -qE -- '(^| )--(status|assignee|if-status|if-assignee)=|gc\.routed_to' <<< "$RC2" \
  && bad "(RACECLOSE) the second write reopened or reassigned the closed bead: $RC2" \
  || ok "(RACECLOSE) …in a write that reopens and reassigns nothing"
eq "$(grep -c . "$TMP/updates")" "2" "(RACECLOSE) …and no third write"
grep -q -- '--root root-PARKED' "$FAKE_CANCELS" \
  && ok "(RACECLOSE) the run beneath it is still ended" \
  || bad "(RACECLOSE) the run was not ended (cancels: $(cat "$FAKE_CANCELS"))"
grep -q 'A-PARKED closed after the release read it' "$TMP/rcerr" \
  && ok "(RACECLOSE) …and the close is named" \
  || bad "(RACECLOSE) the skipped park is unexplained (stderr: $(cat "$TMP/rcerr"))"
grep -q 'anchor left closed' "$TMP/rcout" \
  && ok "(RACECLOSE) …and the success line claims no release" \
  || bad "(RACECLOSE) the success line claims a release (stdout: $(cat "$TMP/rcout"))"
: > "$TMP/updates"; : > "$TMP/slings"; : > "$TMP/statuses"
RCRC=0
FAKE_CLOSE_ON_WRITE=A-PARKED sh "$SCRIPT" takeaway A-PARKED "routed — then it closed" \
   --release --route "$POOL" >/dev/null 2>&1 || RCRC=$?
eq "$RCRC|$(grep -c . "$TMP/slings" || true)" "4|0" "(RACECLOSE) a --route on a bead that closed after the read is refused and never slung"
: > "$TMP/statuses"

# (RACECLAIM) a session claims the bead after the release read it open.
: > "$TMP/updates"; : > "$TMP/deps"; : > "$FAKE_CANCELS"; : > "$TMP/slings"
cp "$TMP/assignees" "$TMP/assignees.race"
RKRC=0
FAKE_CLAIM_ON_WRITE="A-PARKED|gc-toolkit__polecat-hq-new" sh "$SCRIPT" takeaway A-PARKED "stopped" \
   --release --waiting-on A-w-child >"$TMP/rkout" 2>"$TMP/rkerr" || RKRC=$?
eq "$RKRC" "4" "(RACECLAIM) a release on a bead claimed after its read is a verb failure"
eq "$(grep -c . "$TMP/updates")" "1" "(RACECLAIM) …the refused park is the only write"
eq "$(grep -c . "$TMP/deps" || true)|$(grep -c . "$FAKE_CANCELS" || true)|$(grep -c . "$TMP/slings" || true)" "0|0|0" \
   "(RACECLAIM) …with no edge wired, no run ended and nothing slung"
grep -q 'now shows status in_progress under gc-toolkit__polecat-hq-new' "$TMP/rkerr" \
  && ok "(RACECLAIM) …and the exit names who holds it now" \
  || bad "(RACECLAIM) the new holder is unnamed (stderr: $(cat "$TMP/rkerr"))"
mv "$TMP/assignees.race" "$TMP/assignees"; : > "$TMP/statuses"

# (HELD) a live session holds the claim: its row is in the session list.
printf '{"sessions":[{"id":"hq-other-1","alias":"","session_name":"gc-toolkit__polecat-hq-other","state":"active"}]}\n' > "$TMP/sessions"
printf 'A-HELD|in_progress\n' > "$TMP/statuses"
cp "$TMP/assignees" "$TMP/assignees.held"
printf 'A-HELD|gc-toolkit__polecat-hq-other\n' >> "$TMP/assignees"
: > "$TMP/updates"; : > "$TMP/deps"; : > "$TMP/nudges"; : > "$TMP/slings"
HDRC=0
sh "$SCRIPT" takeaway A-HELD "stopped — the PR it rebuilds was retired" --by converse \
   --release --waiting-on A-w-child >"$TMP/hdout" 2>"$TMP/hderr" || HDRC=$?
eq "$HDRC" "4" "(HELD) a release on a claim a live session holds exits 4"
HD="$(cat "$TMP/updates")"
eq "$(grep -c . <<< "$HD")" "1" "(HELD) …in one write"
grep -q -- '--set-metadata gc.takeaway=stopped — the PR it rebuilds was retired' <<< "$HD" \
  && ok "(HELD) …which lands the headline" || bad "(HELD) the headline was lost: $HD"
grep -qE -- '(^| )--(status|assignee|if-status|if-assignee)=|gc\.routed_to|--unset-metadata' <<< "$HD" \
  && bad "(HELD) the write touched the claim: $HD" \
  || ok "(HELD) …and nothing else: no status, assignee, guard, route or pin"
grep -qE '^bd dep add A-HELD A-w-child -t blocks' "$TMP/deps" \
  && ok "(HELD) …the wait is still wired" || bad "(HELD) the wait was not wired: $(cat "$TMP/deps")"
NUDGE="$(cat "$TMP/nudges")"
case "$NUDGE" in
  "session nudge --delivery immediate hq-other-1 Stop work on A-HELD: "*"stopped — the PR it rebuilds was retired"*"hand-back.sh A-HELD --set-metadata gc.routed_to= --reference-bead A-HELD")
    ok "(HELD) the holder's session is nudged to stop, with why and the write that gives the bead back" ;;
  *) bad "(HELD) the nudge is missing or misshapen (got: ${NUDGE:-<none>})" ;;
esac
grep -q 'A-HELD is in_progress under gc-toolkit__polecat-hq-other' "$TMP/hderr" \
  && ok "(HELD) …and the exit names the holder" || bad "(HELD) the holder is unnamed (stderr: $(cat "$TMP/hderr"))"
grep -q 'takeaway set on' "$TMP/hdout" \
  && bad "(HELD) success was reported on a kept claim" || ok "(HELD) …and success is not reported"
: > "$TMP/updates"; : > "$TMP/slings"; : > "$TMP/nudges"
HDRC=0
sh "$SCRIPT" takeaway A-HELD "stopped — sent elsewhere" --release --route "$POOL" >/dev/null 2>"$TMP/hderr" || HDRC=$?
eq "$HDRC|$(grep -c . "$TMP/slings" || true)" "4|0" "(HELDROUTE) a --route on a claim a live session holds is not slung"
grep -q "was not released to $POOL" "$TMP/hderr" \
  && ok "(HELDROUTE) …and the exit says so" || bad "(HELDROUTE) the unsent route is unexplained (stderr: $(cat "$TMP/hderr"))"
: > "$TMP/updates"; : > "$TMP/nudges"
HDRC=0
FAKE_SESSIONS_RC=1 sh "$SCRIPT" takeaway A-HELD "stopped" --release --no-wait >/dev/null 2>"$TMP/hderr" || HDRC=$?
eq "$HDRC" "4" "(HELDUNREAD) a session list that does not read keeps the claim"
grep -qE -- '(^| )--(status|assignee|if-assignee)=' "$TMP/updates" \
  && bad "(HELDUNREAD) the write took the claim: $(cat "$TMP/updates")" \
  || ok "(HELDUNREAD) …and the write takes nothing from the holder"
grep -q '^session nudge --delivery immediate gc-toolkit__polecat-hq-other Stop work on A-HELD' "$TMP/nudges" \
  && ok "(HELDUNREAD) …the holder is nudged by its own name" || bad "(HELDUNREAD) no nudge (got: $(cat "$TMP/nudges"))"
grep -q 'could not be read' "$TMP/hderr" \
  && ok "(HELDUNREAD) …and the exit says the list did not read" || bad "(HELDUNREAD) unexplained (stderr: $(cat "$TMP/hderr"))"
: > "$TMP/updates"
HDRC=0
FAKE_NUDGE_RC=1 sh "$SCRIPT" takeaway A-HELD "stopped" --release --no-wait >/dev/null 2>"$TMP/hderr" || HDRC=$?
eq "$HDRC" "4" "(HELDNUDGE) a nudge that does not land still keeps the claim"
grep -q 'The nudge to gc-toolkit__polecat-hq-other did not land' "$TMP/hderr" \
  && ok "(HELDNUDGE) …and the exit says the nudge did not land" || bad "(HELDNUDGE) unexplained (stderr: $(cat "$TMP/hderr"))"
mv "$TMP/assignees.held" "$TMP/assignees"

# (GONE) the holder is in no row of the session list.
printf 'A-GONE|in_progress\nA-MINE|in_progress\nA-MINE2|in_progress\n' > "$TMP/statuses"
cp "$TMP/assignees" "$TMP/assignees.gone"
printf 'A-GONE|gc-toolkit__polecat-hq-dead\nA-MINE|hq-me\nA-MINE2|gc-toolkit.mechanik\n' >> "$TMP/assignees"
: > "$TMP/updates"; : > "$TMP/nudges"
GNRC=0
sh "$SCRIPT" takeaway A-GONE "stopped — its holder is gone" --release --no-wait >/dev/null 2>"$TMP/gnerr" || GNRC=$?
eq "$GNRC" "0" "(GONE) a claim whose holder the session list does not name is released"
grep -q -- '--if-status=in_progress --if-assignee=gc-toolkit__polecat-hq-dead --status=open --assignee= ' "$TMP/updates" \
  && ok "(GONE) …in the park's one guarded write, which names the holder it read" \
  || bad "(GONE) the release did not name the gone holder (got: $(cat "$TMP/updates"))"
eq "$(grep -c . "$TMP/updates")|$(grep -c . "$TMP/nudges" || true)" "1|0" "(GONE) …with no other write and no nudge"

# (MINE) this session's own claim needs no session list, which does not read here.
: > "$TMP/updates"
MNRC=0
GC_SESSION_ID=hq-me FAKE_SESSIONS_RC=1 sh "$SCRIPT" takeaway A-MINE "released — this session's own" \
   --release --no-wait >/dev/null 2>&1 || MNRC=$?
eq "$MNRC" "0" "(MINE) this session's own claim is released with no session list read"
grep -q -- '--if-status=in_progress --if-assignee=hq-me --status=open --assignee= ' "$TMP/updates" \
  && ok "(MINE) …in the guarded park" || bad "(MINE) the release did not name this session (got: $(cat "$TMP/updates"))"
: > "$TMP/updates"
MNRC=0
GC_AGENT=gc-toolkit.mechanik FAKE_SESSIONS_RC=1 sh "$SCRIPT" takeaway A-MINE2 "released — mechanik's own" \
   --release --no-wait >/dev/null 2>&1 || MNRC=$?
eq "$MNRC" "0" "(MINE) …and so is a named agent's, under its agent address"
mv "$TMP/assignees.gone" "$TMP/assignees"; : > "$TMP/statuses"; : > "$TMP/sessions"

# (DETACHED) the merge cadence drives an anchor in pre_open_gate or pull_request.
printf 'A-DETPR|pull_request\nA-DETPRE|pre_open_gate\n' > "$TMP/merge"
: > "$TMP/updates"; : > "$TMP/slings"
DTRC=0
sh "$SCRIPT" takeaway A-DETPR "routed" --release --route "$POOL" >/dev/null 2>"$TMP/dterr" || DTRC=$?
eq "$DTRC" "2" "(DETACHED) --route on an anchor in pull_request is refused"
eq "$(grep -c . "$TMP/updates" || true)|$(grep -c . "$TMP/slings" || true)" "0|0" "(DETACHED) …before anything is written"
grep -q 'merge_result is pull_request' "$TMP/dterr" \
  && ok "(DETACHED) …naming the state" || bad "(DETACHED) the state is unnamed (stderr: $(cat "$TMP/dterr"))"
DTRC=0
sh "$SCRIPT" takeaway A-DETPRE "assigned" --release --assign gc-toolkit.mechanik --no-wait >/dev/null 2>&1 || DTRC=$?
eq "$DTRC|$(grep -c . "$TMP/updates" || true)" "2|0" "(DETACHED) --assign on an anchor at its pre-open gate is refused too, before any write"
DTRC=0
sh "$SCRIPT" takeaway A-DETPR "stopped" --release --no-wait >/dev/null 2>&1 || DTRC=$?
eq "$DTRC" "0" "(DETACHED) --release alone on a detached anchor still lands"
grep -qE '^bd update A-DETPR .*--status=open' "$TMP/updates" \
  && ok "(DETACHED) …with its park" || bad "(DETACHED) the park was lost: $(cat "$TMP/updates")"
: > "$TMP/merge"

# (NAMEDWAIT) a wait the call names is a claim on the bead as an edge is.
: > "$TMP/updates"; : > "$TMP/deps"; : > "$TMP/slings"
NWRC=0
sh "$SCRIPT" takeaway A-PARKED "routed — once its fix lands" --release --route "$POOL" \
   --waiting-on A-w-open >/dev/null 2>"$TMP/nwerr" || NWRC=$?
eq "$NWRC" "2" "(NAMEDWAIT) a --route beside a named wait that is open and no human gate is refused"
eq "$(grep -c . "$TMP/updates" || true)|$(grep -c . "$TMP/deps" || true)|$(grep -c . "$TMP/slings" || true)" "0|0|0" \
   "(NAMEDWAIT) …before anything is written"
grep -q 'whose --waiting-on names A-w-open' "$TMP/nwerr" \
  && ok "(NAMEDWAIT) …naming the wait" || bad "(NAMEDWAIT) the wait is unnamed (stderr: $(cat "$TMP/nwerr"))"
grep -q 'Re-run without --route' "$TMP/nwerr" \
  && ok "(NAMEDWAIT) …and the call that does land" || bad "(NAMEDWAIT) no re-run named (stderr: $(cat "$TMP/nwerr"))"
NWRC=0
sh "$SCRIPT" takeaway A-PARKED "routed — the pool takes it once ruled" --release --route "$POOL" \
   --waiting-on A-HGATE1 >/dev/null 2>&1 || NWRC=$?
eq "$NWRC" "0" "(NAMEDWAIT) a named wait onto a human gate still routes"
grep -qE '^bd dep add A-PARKED A-HGATE1 -t blocks' "$TMP/deps" \
  && ok "(NAMEDWAIT) …held on the gate" || bad "(NAMEDWAIT) the gate edge was not written: $(cat "$TMP/deps")"
grep -q "^sling $POOL A-PARKED " "$TMP/slings" \
  && ok "(NAMEDWAIT) …and slung" || bad "(NAMEDWAIT) not slung: $(cat "$TMP/slings")"
: > "$TMP/slings"
NWRC=0
sh "$SCRIPT" takeaway A-PARKED "routed — its wait is done" --release --route "$POOL" \
   --waiting-on A-CLOSED-w1 >/dev/null 2>&1 || NWRC=$?
eq "$NWRC|$(grep -c . "$TMP/slings" || true)" "0|1" "(NAMEDWAIT) a named wait that is closed still routes"
: > "$TMP/updates"; : > "$TMP/slings"
NWRC=0
sh "$SCRIPT" takeaway A-PARKED "routed" --release --route "$POOL" \
   --waiting-on A-w-UNREAD >/dev/null 2>"$TMP/nwerr" || NWRC=$?
eq "$NWRC|$(grep -c . "$TMP/updates" || true)|$(grep -c . "$TMP/slings" || true)" "2|0|0" \
   "(NAMEDWAIT) a named wait whose row does not read is refused, before any write"
grep -q 'A-w-UNREAD did not read' "$TMP/nwerr" \
  && ok "(NAMEDWAIT) …and the refusal says its row did not read" || bad "(NAMEDWAIT) unexplained (stderr: $(cat "$TMP/nwerr"))"

# (SLINGFAIL) gc sling refuses the route after the release has landed.
: > "$TMP/updates"; : > "$TMP/slings"
SFRC=0
FAKE_GC_SLING_RC=1 sh "$SCRIPT" takeaway A-PARKED "routed" --release --route "$POOL" \
   >"$TMP/sfout" 2>"$TMP/sferr" || SFRC=$?
eq "$SFRC" "4" "(SLINGFAIL) a sling that fails is a verb failure"
grep -q "gc sling did not route it to '$POOL'" "$TMP/sferr" \
  && ok "(SLINGFAIL) …which says the route did not land" || bad "(SLINGFAIL) unexplained (stderr: $(cat "$TMP/sferr"))"
grep -q "gc sling $POOL A-PARKED --no-formula --no-convoy" "$TMP/sferr" \
  && ok "(SLINGFAIL) …and names the sling that routes it" || bad "(SLINGFAIL) no repair named (stderr: $(cat "$TMP/sferr"))"
grep -qE '^bd update A-PARKED .*--status=open' "$TMP/updates" \
  && ok "(SLINGFAIL) …with the release kept" || bad "(SLINGFAIL) the release was lost: $(cat "$TMP/updates")"
grep -q 'takeaway set on' "$TMP/sfout" \
  && bad "(SLINGFAIL) success was reported" || ok "(SLINGFAIL) …and success is not reported"

# (SLINGHOLD) nothing reaches the pool while a run still works the bead, or
# while a wait the call asked for is not wired.
: > "$TMP/slings"
SHRC=0
FAKE_CANCEL_RC=1 sh "$SCRIPT" takeaway A-PARKED "routed" --release --route "$POOL" >/dev/null 2>&1 || SHRC=$?
eq "$SHRC|$(grep -c . "$TMP/slings" || true)" "4|0" "(SLINGHOLD) a run that did not end sends nothing to the pool"
SHRC=0
sh "$SCRIPT" takeaway A-PARKED "routed — once ruled" --release --route "$POOL" \
   --waiting-on A-HGATE-NOPE >/dev/null 2>&1 || SHRC=$?
eq "$SHRC|$(grep -c . "$TMP/slings" || true)" "4|0" "(SLINGHOLD) …and neither does a wait that did not wire"

# ── takeaway length: the ≤140 cap, ENFORCED ─────────────────────
# REJECT over the cap, never truncate; measured in codepoints, after the
# whitespace collapse, before every side effect.
T140="$(printf 'x%.0s' {1..140})"
T141="$(printf 'x%.0s' {1..141})"
T140M="$(printf '—%.0s' {1..140})"   # 140 codepoints, 420 bytes

: > "$TMP/updates"; : > "$TMP/deps"
CRC=0
sh "$SCRIPT" takeaway A-PARKED "$T141" >/dev/null 2>"$TMP/cerr" || CRC=$?
CERR="$(cat "$TMP/cerr")"
eq "$CRC" "2" "(CAP) a 141-char takeaway is a usage error"
eq "$(grep -c '^bd update' "$TMP/updates" || true)" "0" \
   "(CAPNOWRITE) nothing is written — the bead keeps whatever it had"
grep -q '141 chars' <<< "$CERR" && grep -q 'cap is 140' <<< "$CERR" \
  && ok "(CAPMSG) the refusal names the measured length and the cap" \
  || bad "(CAPMSG) the refusal does not say what was wrong (stderr: ${CERR:-<none>})"

: > "$TMP/updates"
sh "$SCRIPT" takeaway A-PARKED "$T140" >/dev/null 2>&1 || true
grep -q -- "--set-metadata gc.takeaway=$T140" "$TMP/updates" \
  && ok "(CAPOK) exactly 140 chars is accepted — the boundary is inclusive" \
  || bad "(CAPOK) a conforming 140-char headline was refused: $(cat "$TMP/updates")"

: > "$TMP/updates"
sh "$SCRIPT" takeaway A-PARKED "$T140M" >/dev/null 2>"$TMP/cerr" || true
grep -q -- "--set-metadata gc.takeaway=$T140M" "$TMP/updates" \
  && ok "(CAPRUNE) 140 multi-byte chars (420 bytes) are accepted: the unit is codepoints" \
  || bad "(CAPRUNE) a 140-CHARACTER headline was refused for its byte count (stderr: $(cat "$TMP/cerr"))"

# (CAPWS) the collapse runs first, so what is measured is what gets stored.
: > "$TMP/updates"
sh "$SCRIPT" takeaway A-PARKED "a$(printf ' %.0s' {1..200})b" >/dev/null 2>&1 || true
grep -q -- '--set-metadata gc.takeaway=a b' "$TMP/updates" \
  && ok "(CAPWS) the cap measures the collapsed text, not the raw argument" \
  || bad "(CAPWS) whitespace padding was counted against the cap: $(cat "$TMP/updates")"

# (CAPFIRST) a refusal must cost nothing: no park, no edge.
: > "$TMP/updates"; : > "$TMP/deps"
sh "$SCRIPT" takeaway A-PARKED "$T141" --release --waiting-on A-blk1 >/dev/null 2>&1 || true
eq "$(grep -c '^bd update' "$TMP/updates" || true)" "0" "(CAPFIRST) a refused takeaway does not park the bead"
eq "$(grep -c '^bd dep' "$TMP/deps" || true)"       "0" "(CAPFIRST) …and writes no waiting-on edge"

# (CAPNOTRIM static) the gate must REFUSE, not silently shorten.
GATE="$(awk '/# >>> takeaway-length-gate/{f=1;next} /# <<< takeaway-length-gate/{f=0} f' "$SCRIPT")"
[ -n "$GATE" ] && ok "(CAPNOTRIM) length-gate block extracted between markers" \
               || bad "(CAPNOTRIM) block extraction EMPTY — markers missing"
TRIM="$(printf '%s\n' "$GATE" | grep -vE '^\s*#' | grep -E 'text=|text:0:|cut -c' || true)"
[ -z "$TRIM" ] \
  && ok "(CAPNOTRIM) the gate never rewrites the text — it refuses it" \
  || bad "(CAPNOTRIM) the gate silently shortens the takeaway: $TRIM"

# ── the board verb is retired (moved to helm-svc board) ──────────────────────
BRC=0
BERRTXT="$(sh "$SCRIPT" board --json 2>&1 >/dev/null)" || BRC=$?
eq "$BRC" "2" "(NOBOARD) 'board' is a usage error now"
grep -q 'helm-svc board' <<< "$BERRTXT" \
  && ok "(NOBOARD) …and the refusal points at helm-svc board" \
  || bad "(NOBOARD) refusal must name the successor (got: $BERRTXT)"

# ── The releasing session's own run survives the release ─────────────────────
# A releasing session may itself own a step of a molecule anchored to the bead it
# disposes by `takeaway --release`, and then has to close its own chain.
# step-close.sh resolves that bead within its molecule and corroborates it by
# the assignee, so the release leaves that run alone: it writes none of its
# beads and cancels nothing. A run no step of which is this session's ends
# through the REAL run-cancel.sh, whose request a curl stub answers. This
# section runs the real release and then the real step-close.sh against ONE
# mutating store — a logging-only stub cannot show the second command failing
# on what the first wrote.
LIVE="$TMP/live"; mkdir -p "$LIVE/bin"
export LIVE_STORE="$LIVE/store.json" LIVE_CONVOYS="$LIVE/convoys" LIVE_LOG="$LIVE/log"
# A store write the stub cannot land must not pass silently. The stub mutates the
# store with a whole-file `jq > tmp && mv` rewrite — the largest write here and
# the first to hit ENOSPC when a concurrent run-tests.sh batch transiently
# exhausts the shared tmpfs. Unchecked, that failed rewrite leaves the store at
# its pre-takeaway value while the stub still exits 0, so every field() read
# below sees stale state and the release assertions FALSELY fault gc-helm.sh.
# The stub records this flag instead, and live_store_intact turns it into a
# distinct infra abort. Sited in $TMP, not $LIVE, so it still lands when $LIVE
# is the directory that cannot be written.
export LIVE_WRITE_FAILED="$TMP/live-store-write-failed"
SESSION="gc-toolkit--gc-toolkit__proactive-1-pool"
POOL="gc-toolkit/gc-toolkit.polecat"

# A-LIVE is the anchor; root-LIVE its molecule root. L-live is the terminal
# step this session is executing the release FROM, so root-LIVE is this
# session's own run; L-peer and L-held are its other steps, one pinned to a
# session that is gone and one in_progress under a different live session.
#
# A-FOLD is a second, independent anchor: CLOSED and superseded, with its own
# molecule (root-FOLD, F-work, F-held) still running under the pour. No step of
# it is this session's, so the release ends it through gascity's run cancel,
# and the store shows gc-helm.sh wrote none of its beads.
cat > "$LIVE_STORE" <<JSON
[
 {"id":"A-LIVE","status":"in_progress","assignee":"$SESSION","metadata":{}},
 {"id":"root-LIVE","status":"in_progress","assignee":"","metadata":{"gc.kind":"workflow","gc.step_id":"mol-sample","gc.input_convoy_id":"convoy-LIVE","gc.routed_to":"gc-toolkit/gc-toolkit.proactive"}},
 {"id":"L-live","status":"in_progress","assignee":"$SESSION","metadata":{"gc.step_ref":"mol-sample.advance-and-drain","gc.root_bead_id":"root-LIVE","gc.routed_to":"gc-toolkit/gc-toolkit.proactive","gc.session_affinity":"require"}},
 {"id":"L-peer","status":"open","assignee":"gc-toolkit__polecat-hq-gone","metadata":{"gc.step_ref":"mol-sample.load-bead","gc.root_bead_id":"root-LIVE","gc.routed_to":"gc-toolkit/gc-toolkit.proactive","gc.session_affinity":"require"}},
 {"id":"L-held","status":"in_progress","assignee":"gc-toolkit__polecat-hq-other","metadata":{"gc.step_ref":"mol-sample.decide","gc.root_bead_id":"root-LIVE","gc.routed_to":"gc-toolkit/gc-toolkit.proactive","gc.session_affinity":"require"}},
 {"id":"A-FOLD","status":"closed","assignee":"gc-toolkit__polecat-hq-old","dependencies":[{"issue_id":"A-FOLD","depends_on_id":"A-CARRIER","type":"supersedes"}],"metadata":{"gc.routed_to":"human"}},
 {"id":"root-FOLD","status":"in_progress","assignee":"","metadata":{"gc.kind":"workflow","gc.step_id":"mol-polecat-work","gc.input_convoy_id":"convoy-FOLD","gc.routed_to":"$POOL"}},
 {"id":"F-held","status":"in_progress","assignee":"gc-toolkit__polecat-hq-other","metadata":{"gc.step_ref":"mol-polecat-work.load-context","gc.root_bead_id":"root-FOLD","gc.routed_to":"$POOL","gc.session_affinity":"require"}},
 {"id":"F-work","status":"open","assignee":"gc-toolkit__polecat-hq-gone","metadata":{"gc.step_ref":"mol-polecat-work.workspace-setup","gc.root_bead_id":"root-FOLD","gc.routed_to":"$POOL","gc.session_affinity":"require"}},
 {"id":"A-HELD","status":"in_progress","assignee":"hq-held","metadata":{"gc.routed_to":"$POOL","gc.session_id":"hq-held","gc.session_name":"gc-toolkit__polecat-hq-held"}},
 {"id":"A-GONE","status":"in_progress","assignee":"hq-gone","metadata":{"gc.routed_to":"$POOL","gc.session_id":"hq-gone","gc.session_name":"gc-toolkit__polecat-hq-gone"}}
]
JSON
printf 'convoy-LIVE|A-LIVE\nconvoy-FOLD|A-FOLD\n' > "$LIVE_CONVOYS"
# A-HELD's holder is a session the list still names; A-GONE's is in no row.
export LIVE_SESSIONS="$LIVE/sessions.json"
printf '{"sessions":[{"id":"hq-held","alias":"","session_name":"gc-toolkit__polecat-hq-held","state":"active"}]}\n' > "$LIVE_SESSIONS"
: > "$LIVE_LOG"
# The real run-cancel.sh, against a supervisor a curl stub stands in for: it
# logs each request with its headers and answers 202, as gascity's cancel does.
export LIVE_CURL_LOG="$LIVE/curl.log"; : > "$LIVE_CURL_LOG"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$LIVE/bin/curl" <<'CURLL'
out=""; hdr=""; url=""; method=GET
while [ $# -gt 0 ]; do
  case "$1" in
    -o) shift; out="$1" ;;
    -X) shift; method="$1" ;;
    -H) shift; hdr="$hdr$1;" ;;
    -w|--max-time) shift ;;
    -s) ;;
    *) url="$1" ;;
  esac
  shift
done
printf '%s %s %s\n' "$method" "$url" "$hdr" >> "$LIVE_CURL_LOG"
[ -n "$out" ] && printf '{"status":"canceled","closed":3}' > "$out"
printf '202'
CURLL
chmod +x "$LIVE/bin/curl"

{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$LIVE/bin/gc" <<'GCL'
# A MUTATING store: `bd update` rewrites LIVE_STORE, so a later list/show
# answers the state the earlier write left behind.
# Fail CLOSED: an unchecked `jq > … && mv` drops the write silently when the
# rewrite cannot land (ENOSPC under disk pressure) and still returns success, so
# the SUT reads back pre-write state. Record the flag the suite checks instead.
sw() { jq "$@" "$LIVE_STORE" > "$LIVE_STORE.n" && mv "$LIVE_STORE.n" "$LIVE_STORE" && return 0; : >> "$LIVE_WRITE_FAILED"; return 1; }
case "$1 ${2:-}" in
  "rig list") printf '{"rigs":[{"name":"gc-toolkit","path":"/nonexistent-rig","prefix":"tk"}]}\n' ;;
  "bd list")
    st=""; who=""; seen_who=0
    for a in "$@"; do
      case "$a" in
        --status=*)   st="${a#--status=}" ;;
        --assignee=*) who="${a#--assignee=}"; seen_who=1 ;;
      esac
    done
    jq --arg st "$st" --arg who "$who" --argjson sw "$seen_who" '
      [ .[] | . as $b
        | select($st == "" or (($st | split(",")) | index($b.status // "")) != null)
        | select($sw == 0 or (($b.assignee // "") == $who)) ]' "$LIVE_STORE" ;;
  "bd show")
    row=$(jq -c --arg i "$3" '[ .[] | select(.id == $i) ]' "$LIVE_STORE")
    [ "$row" != "[]" ] && printf '%s\n' "$row" || printf '[{"id":"%s","status":"open","metadata":{}}]\n' "$3" ;;
  "bd update")
    printf 'update %s\n' "$*" >> "$LIVE_LOG"
    id="$3"; shift 3
    st=$(jq -r --arg i "$id" '.[] | select(.id==$i) | .status // ""' "$LIVE_STORE")
    who=$(jq -r --arg i "$id" '.[] | select(.id==$i) | .assignee // ""' "$LIVE_STORE")
    # A guarded write compares --if-status and --if-assignee with the row, and a
    # mismatch writes nothing and exits 13. bd skips its reassign fence for a
    # write guarded on the assignee, since the guard names the holder, and that
    # skip is why the release names a holder only once it is shown gone.
    has_ifs=""; ifs=""; has_ifa=""; ifa=""
    for a in "$@"; do
      case "$a" in
        --if-status=*)   has_ifs=1; ifs="${a#--if-status=}" ;;
        --if-assignee=*) has_ifa=1; ifa="${a#--if-assignee=}" ;;
      esac
    done
    if { [ -n "$has_ifs" ] && [ "$ifs" != "$st" ]; } || { [ -n "$has_ifa" ] && [ "$ifa" != "$who" ]; }; then
      printf 'mismatch %s\n' "$id" >> "$LIVE_LOG"
      exit 13
    fi
    # beads refuses to clear the assignee of an in_progress bead ANOTHER
    # session holds, and refuses the whole update along with it, unless the
    # write is guarded on the assignee. Checked before anything is applied, so
    # the refusal is atomic here too: a stub that let the other keys through
    # would hide the loss this split prevents.
    if [ -z "$has_ifa" ]; then
      for a in "$@"; do
        case "$a" in
          --assignee|--assignee=*)
            if [ "$st" = "in_progress" ] && [ -n "$who" ] && [ "$who" != "${GC_SESSION_NAME:-}" ]; then
              printf 'refused %s (held by %s)\n' "$id" "$who" >> "$LIVE_LOG"
              exit 1
            fi ;;
        esac
      done
    fi
    while [ $# -gt 0 ]; do
      case "$1" in
        --db)             shift 2 ;;
        --assignee=*)     sw --arg i "$id" --arg v "${1#--assignee=}" 'map(if .id==$i then .assignee=$v else . end)'; shift ;;
        --assignee)       sw --arg i "$id" --arg v "${2:-}" 'map(if .id==$i then .assignee=$v else . end)'; shift 2 ;;
        --status=*)       sw --arg i "$id" --arg v "${1#--status=}" 'map(if .id==$i then .status=$v else . end)'; shift ;;
        --set-metadata)   sw --arg i "$id" --arg k "${2%%=*}" --arg v "${2#*=}" 'map(if .id==$i then .metadata[$k]=$v else . end)'; shift 2 ;;
        --unset-metadata) sw --arg i "$id" --arg k "$2" 'map(if .id==$i then (.metadata |= del(.[$k])) else . end)'; shift 2 ;;
        *)                shift ;;
      esac
    done ;;
  "bd dep")
    printf 'dep %s\n' "$*" >> "$LIVE_LOG"
    [ "${3:-}" = "list" ] && printf '[]\n' ;;
  "session list")
    if [ -s "$LIVE_SESSIONS" ]; then cat "$LIVE_SESSIONS"; else printf '{"sessions":[]}\n'; fi ;;
  "session nudge")
    printf 'nudge %s\n' "$*" >> "$LIVE_LOG" ;;
  "sling "*)
    # A raw route: gc sling writes the bead's gc.routed_to and pours nothing.
    printf 'sling %s\n' "$*" >> "$LIVE_LOG"
    sw --arg i "$3" --arg v "$2" 'map(if .id==$i then .metadata["gc.routed_to"]=$v else . end)' ;;
esac
exit 0
GCL
chmod +x "$LIVE/bin/gc"

field() { jq -r --arg i "$1" --arg k "$2" '.[] | select(.id==$i) | (if $k=="status" then .status elif $k=="assignee" then (.assignee // "") else (.metadata[$k] // "") end)' "$LIVE_STORE"; }

# Call after each mutating run, at TOP LEVEL (never inside a $(field …), where an
# exit would only leave the subshell). A write the stub could not land leaves the
# store stale; reading it as a gc-helm.sh verdict would be the false failure this
# guards against, so stop with a distinct infra message the gate can tell from a
# real fault.
live_store_intact() {
  [ -e "$LIVE_WRITE_FAILED" ] || return 0
  echo "ABORT(disk-pressure): a LIVE fixture-store write did not land (ENOSPC on the filesystem backing $TMP); the assertions below neither fault nor exonerate gc-helm.sh. Re-run with free tmp space." >&2
  exit 1
}

SAVED_PATH="$PATH"; PATH="$LIVE/bin:$PATH"
SAVED_CANCEL_TOOL="$GC_RUN_CANCEL_TOOL"; unset GC_RUN_CANCEL_TOOL
export GC_CITY_PATH="$LIVE/town" GC_HOME="$LIVE/gchome"; mkdir -p "$GC_HOME"
RELOUT="$(GC_SESSION_NAME="$SESSION" GC_SESSION_ID="hq-live1" \
  sh "$SCRIPT" takeaway A-LIVE "released to the impl pool" --by proactive --release --route "$POOL" 2>&1 || true)"
live_store_intact   # the release writes landed, or this is disk pressure not a verdict

eq "$(field L-live assignee)" "$SESSION" \
   "(OWNRUN) the step the release runs FROM keeps its assignee"
eq "$(field L-live gc.routed_to)" "gc-toolkit/gc-toolkit.proactive" \
   "(OWNRUN) …and its route"
eq "$(field L-live gc.session_affinity)" "require" \
   "(OWNRUN) …and its session affinity"
grep -q 'kept run root-LIVE of A-LIVE' <<< "$RELOUT" \
  && ok "(OWNRUN) …and the run says which run it kept" \
  || bad "(OWNRUN) the kept run is unreported (out: $RELOUT)"
# This session's own run is left whole: no step of it, and not its root, is
# written, and nothing is sent to cancel it.
OWNW="$(grep -E '^update bd update (L-|root-LIVE)' "$LIVE_LOG" || true)"
[ -z "$OWNW" ] && ok "(OWNRUN) no bead of this session's own run is written" \
  || bad "(OWNRUN) the release wrote the session's own run: $OWNW"
grep -q '/runs/root-LIVE/' "$LIVE_CURL_LOG" \
  && bad "(OWNRUN) the session's own run was cancelled" || ok "(OWNRUN) …and it is not cancelled"
eq "$(field L-peer gc.routed_to)" "gc-toolkit/gc-toolkit.proactive" \
   "(OWNRUN) a sibling step keeps its route; gascity, not the pack, owns its lifecycle"
eq "$(field L-held assignee)" "gc-toolkit__polecat-hq-other" \
   "(OWNRUN) …and a step another live session holds keeps its holder"
eq "$(field root-LIVE gc.routed_to)" "gc-toolkit/gc-toolkit.proactive" \
   "(OWNRUN) …and the root is not rewritten"

# The disposition itself still lands whole.
eq "$(field A-LIVE status)" "open"  "(LIVESTEP) the anchor is released"
eq "$(field A-LIVE assignee)" ""    "(LIVESTEP) …and unassigned"
eq "$(field A-LIVE gc.routed_to)" "$POOL" "(LIVESTEP) …and routed to the pool"

# The proof the guard exists for: the terminal step is still CLOSABLE after the
# release, by the same resolution the formula's terminal block uses.
SCRC=0
SCOUT="$(GC_SESSION_NAME="$SESSION" GC_SESSION_ID="hq-live1" \
  bash "$HERE/step-close.sh" --step mol-sample.advance-and-drain --outcome pass 2>&1)" || SCRC=$?
live_store_intact   # step-close's close landed, or this is disk pressure not a verdict
eq "$SCRC" "0" "(LIVESTEP) step-close.sh still resolves this session's step after the release"
eq "$(field L-live status)" "closed" \
   "(LIVESTEP) …and closes it, so the molecule advances instead of re-offering"
[ "$SCRC" -eq 0 ] || printf 'note: step-close output:\n%s\n' "$SCOUT" >&2

# ── A FOLDED anchor, against the same mutating store ─────────────────────────
# The argv assertions in the FOLDED section prove which flags the verb sent.
# This one proves what the store holds afterwards, which is the thing the bug
# is about: a bead whose disposition landed must not come back as open work.
FOLDRC=0
FOLDOUT="$(GC_SESSION_NAME="$SESSION" GC_SESSION_ID="hq-live1" \
  sh "$SCRIPT" takeaway A-FOLD "superseded by A-CARRIER; the pour raced the fold" \
     --by proactive --release 2>"$LIVE/folderr")" || FOLDRC=$?
FOLDERR="$(cat "$LIVE/folderr")"
live_store_intact   # the fold release's writes landed, or this is disk pressure not a verdict
eq "$FOLDRC" "0" "(FOLDSTORE) the release on a folded anchor succeeds"
eq "$(field A-FOLD status)" "closed" \
   "(FOLDSTORE) the anchor is still CLOSED — its disposition was not resurrected"
eq "$(field A-FOLD assignee)" "gc-toolkit__polecat-hq-old" \
   "(FOLDSTORE) …still assigned as it was closed"
eq "$(field A-FOLD gc.routed_to)" "human" \
   "(FOLDSTORE) …and its route survives the release"
eq "$(field A-FOLD gc.proactive_reaction)" "" \
   "(FOLDSTORE) …with no fresh reaction marker over a landed disposition"
eq "$(jq -r '.[] | select(.id=="A-FOLD") | [.dependencies[]? | .type + ">" + .depends_on_id] | join(",")' "$LIVE_STORE")" "supersedes>A-CARRIER" \
   "(FOLDSTORE) …and the fold record itself untouched"
eq "$(field A-FOLD gc.takeaway)" "superseded by A-CARRIER; the pour raced the fold" \
   "(FOLDSTORE) the sitting's headline still lands on it"
grep -qE '^POST http://127\.0\.0\.1:8372/v0/city/town/runs/root-FOLD/cancel X-GC-Request:' "$LIVE_CURL_LOG" \
  && ok "(FOLDSTORE) the run the fold outran is cancelled through gascity's run cancel, with its anti-CSRF header" \
  || bad "(FOLDSTORE) no run cancel for root-FOLD (curl log: $(cat "$LIVE_CURL_LOG"))"
grep -q 'ended run root-FOLD of A-FOLD through gascity' <<< "$FOLDOUT" \
  && ok "(FOLDSTORE) …and the run reports it" || bad "(FOLDSTORE) the ended run is unreported (out: $FOLDOUT)"
FOLDW="$(grep -E '^update bd update (F-|root-FOLD)' "$LIVE_LOG" || true)"
[ -z "$FOLDW" ] && ok "(FOLDSTORE) gc-helm.sh writes none of that run's beads; gascity's cancel closes them" \
  || bad "(FOLDSTORE) the release wrote the folded run's beads: $FOLDW"
eq "$(field F-held assignee)" "gc-toolkit__polecat-hq-other" \
   "(FOLDSTORE) …so a step another live session holds is not reassigned under it"
grep -q 'superseded by A-CARRIER' <<< "$FOLDERR" \
  && ok "(FOLDSTORE) …and the run names the disposition it kept" \
  || bad "(FOLDSTORE) the skipped park is unexplained (stderr: $FOLDERR)"
grep -q 'anchor left closed' <<< "$FOLDOUT" \
  && ok "(FOLDSTORE) …and reports the run's end, not a release" \
  || bad "(FOLDSTORE) the run claimed a release (stdout: $FOLDOUT)"

# ── A claim another session holds, against the same mutating store ───────────
# This store refuses an unguarded write that takes another session's live
# claim, and skips that fence for a write guarded on the holder, as bd does. A
# release that named a live holder in its guard would take the claim here, so
# the store shows whether the claim of a session the list still names stands,
# and whether the claim of one that is gone is released whole. Covered:
#   (HELDSTORE) the live holder keeps its claim, its route and its pins, the
#               headline lands, and the holder is nudged
#   (GONESTORE) a gone holder's claim is released in one guarded write: open,
#               unassigned, routed to no pool, its pins gone
HSRC=0
HSOUT="$(GC_SESSION_NAME="$SESSION" GC_SESSION_ID="hq-live1" \
  sh "$SCRIPT" takeaway A-HELD "stopped — the PR it rebuilds was retired" --by converse --release --no-wait 2>&1)" || HSRC=$?
live_store_intact   # the headline landed, or this is disk pressure not a verdict
eq "$HSRC" "4" "(HELDSTORE) a release on a claim a live session holds exits 4"
eq "$(field A-HELD status)|$(field A-HELD assignee)" "in_progress|hq-held" \
   "(HELDSTORE) …and the claim stands, in_progress under its holder"
eq "$(field A-HELD gc.routed_to)|$(field A-HELD gc.session_id)" "$POOL|hq-held" \
   "(HELDSTORE) …with its route and its pins, which the holder's own hand-back clears"
eq "$(field A-HELD gc.takeaway)" "stopped — the PR it rebuilds was retired" \
   "(HELDSTORE) …while the headline lands"
grep -q '^nudge session nudge --delivery immediate hq-held Stop work on A-HELD' "$LIVE_LOG" \
  && ok "(HELDSTORE) …and the holder is nudged to stop" \
  || bad "(HELDSTORE) no nudge reached the holder (log: $(cat "$LIVE_LOG"))"
grep -q 'A-HELD is in_progress under hq-held' <<< "$HSOUT" \
  && ok "(HELDSTORE) …and the exit names the holder" \
  || bad "(HELDSTORE) the holder is unnamed (out: $HSOUT)"
GSRC=0
GC_SESSION_NAME="$SESSION" GC_SESSION_ID="hq-live1" \
  sh "$SCRIPT" takeaway A-GONE "stopped — its holder is gone" --by converse --release --no-wait >/dev/null 2>&1 || GSRC=$?
live_store_intact   # the release landed, or this is disk pressure not a verdict
eq "$GSRC" "0" "(GONESTORE) a release on a claim whose holder is gone succeeds"
eq "$(field A-GONE status)|$(field A-GONE assignee)|$(field A-GONE gc.routed_to)" "open||" \
   "(GONESTORE) …leaving it open, unassigned and routed to no pool"
eq "$(field A-GONE gc.session_id)|$(field A-GONE gc.session_name)" "|" \
   "(GONESTORE) …with the gone holder's pins removed"
grep -q '^nudge .*A-GONE' "$LIVE_LOG" \
  && bad "(GONESTORE) a holder that is gone was nudged" || ok "(GONESTORE) …and no holder is nudged"

# ── the disk-pressure guard itself ───────────────────────────────────────────
# The release assertions above read the store back through field(); a stub write
# the host could not land (ENOSPC under a concurrent run-tests.sh batch) would
# leave that store stale and read as a false gc-helm.sh failure — the flake this
# guard removes. Prove both halves so a regression that re-swallows the write is
# caught: the stub FLAGS a write it could not land, and the flag ABORTS the block
# distinctly instead of rendering a verdict on stale state. A store directory
# with no write bit is the hermetic stand-in for a full disk: jq's temp-file
# create fails exactly as ENOSPC would, while $LIVE stays readable/traversable so
# the stub still runs and the flag (in $TMP) still lands.
rm -f "$LIVE_WRITE_FAILED"
chmod 555 "$LIVE"
GUARD_WROTE="$("$LIVE/bin/gc" bd update A-LIVE --status=open 2>&1 || true)"
chmod 755 "$LIVE"
[ -e "$LIVE_WRITE_FAILED" ] \
  && ok "(DISKGUARD) a stub store write that cannot land is flagged, not dropped silently" \
  || bad "(DISKGUARD) a failed store write was swallowed (out: $GUARD_WROTE)"
GRC=0; GOUT="$(live_store_intact 2>&1)" || GRC=$?
rm -f "$LIVE_WRITE_FAILED"
eq "$GRC" "1" "(DISKGUARD) the flag aborts the LIVE block, not a verdict on stale state"
grep -q 'disk-pressure' <<< "$GOUT" \
  && ok "(DISKGUARD) …and the abort names disk pressure, not a gc-helm.sh fault" \
  || bad "(DISKGUARD) the abort is unexplained (out: $GOUT)"
PATH="$SAVED_PATH"; export GC_RUN_CANCEL_TOOL="$SAVED_CANCEL_TOOL"; unset GC_CITY_PATH GC_HOME

# ── the rig-enumeration helper restores the caller's trap table ──────────────
# A trap is process-global: one installed inside a helper and left there
# rewrites how every later line of the caller answers a signal. The helper is
# lifted and run directly, with the real rig-map.sh it reads the map through —
# every real call site is a command substitution, whose subshell would hide
# the residue. Assert the table is unchanged across the call, not that it is
# empty: a caller can inherit a disposition the helper never touches — a parent
# that ignores SIGPIPE shows up as `trap -- '' SIGPIPE`, which bash reports and
# the helper can neither set nor clear — and the invariant is that the helper
# leaves the table exactly as it found it.
ENUM="$TMP/enum-helper.sh"
sed -n '/^rigs_count() {/,/^}/p;/^enumerate_rigs() {/,/^}/p' "$SCRIPT" > "$ENUM"
mkdir -p "$TMP/enumbin"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/enumbin/gc" <<'ENUMGC'
[ "$1 ${2:-}" = "rig list" ] && printf '{"rigs":[{"name":"r","path":"/p","prefix":"tk"}]}\n'
exit 0
ENUMGC
chmod +x "$TMP/enumbin/gc"
# The probe sources city-liveness.sh ($2) first, for the projection the helper
# runs, as the script does, and finds rig-map.sh in $3, as the script finds it
# beside itself.
cat > "$TMP/enum-probe.sh" <<'ENUMPROBE'
set -eu
PROG=probe; FIXTURE=""; RIGS=""; SCRIPT_DIR="$3"
. "$2"
. "$1"
before="$(trap)"
enumerate_rigs
after="$(trap)"
printf 'RIGS[%s]\n' "$RIGS"
[ "$before" = "$after" ] && printf 'TRAPDELTA[]\n' \
  || printf 'TRAPDELTA[before=<%s> after=<%s>]\n' "$before" "$after"
ENUMPROBE
ENUMTMP="$TMP/enumtmp"; mkdir -p "$ENUMTMP"
EOUT="$(TMPDIR="$ENUMTMP" PATH="$TMP/enumbin:$PATH" bash "$TMP/enum-probe.sh" "$ENUM" "$HERE/city-liveness.sh" "$HERE" 2>&1 || true)"
grep -q 'RIGS\[\[' <<< "$EOUT" \
  && ok "(ENUM) the helper enumerated, through rig-map.sh" \
  || bad "(ENUM) the helper did not enumerate (out: $EOUT)"
grep -q 'TRAPDELTA\[\]' <<< "$EOUT" \
  && ok "(ENUM) …and left the caller's trap table as it found it" \
  || bad "(ENUM) the helper changed the caller's traps (out: $EOUT)"
eq "$(find "$ENUMTMP" -name 'gctk-rig-map.*' | wc -l | tr -d ' ')" "0" \
   "(ENUM) …and rig-map.sh removed its stderr capture"

echo ""
echo "── react: an already-reacted skip is a distinct exit, not a silent dispatch ──"
# react is a thin wrapper over tools/gc-proactive.sh `sling`. That tool exits
# RC_ALREADY_REACTED (3) when its guard skips a bead that already carries a
# first reaction — a no-op that dispatched nothing. react must re-raise that as
# its OWN no-op code (5), distinct from a dispatch (0) and a real failure (4),
# so an intake caller (operator-intake.sh) files its own conversation instead of
# waiting for a reaction that never ran. Drive the REAL react over a fake sling whose exit
# code is the one thing under test (rig resolution uses the gc `rig list` stub).
cat > "$TMP/bin/gc-proactive.sh" <<'PRO'
#!/usr/bin/env bash
exit "${FAKE_SLING_RC:-0}"
PRO
chmod +x "$TMP/bin/gc-proactive.sh"
export GC_PROACTIVE_TOOL="$TMP/bin/gc-proactive.sh"

rrc=0; FAKE_SLING_RC=3 sh "$SCRIPT" react tk-react1 >/dev/null 2>"$TMP/rerr" || rrc=$?
eq "$rrc" "5" "(REACT) an already-reacted skip (sling exit 3) becomes react exit 5"
grep -q "already has an open first reaction" "$TMP/rerr" \
  && ok "(REACT) …and names the no-op cause" \
  || bad "(REACT) react no-op message missing: $(cat "$TMP/rerr")"
grep -q "failed" "$TMP/rerr" \
  && bad "(REACT) a no-op must not be reported as a failure" \
  || ok "(REACT) …and is not reported as a failure"

rrc=0; FAKE_SLING_RC=0 sh "$SCRIPT" react tk-react1 >/dev/null 2>&1 || rrc=$?
eq "$rrc" "0" "(REACT) a dispatched sling (exit 0) exits 0"

rrc=0; FAKE_SLING_RC=1 sh "$SCRIPT" react tk-react1 >/dev/null 2>"$TMP/rerr2" || rrc=$?
eq "$rrc" "4" "(REACT) a real sling failure (exit 1) is react's failure (exit 4)"
grep -q "failed" "$TMP/rerr2" \
  && ok "(REACT) …and is reported as a failure" \
  || bad "(REACT) react failure message missing: $(cat "$TMP/rerr2")"

# The sling's live-workflow guard exits RC_LIVE_WORKFLOW (4) when a live workflow
# already drives the bead: also a no-op that dispatched nothing, with a different
# cause. react re-raises it as its own code (6) so the intake caller names that
# cause, never the already-reacted one or a failure.
rrc=0; FAKE_SLING_RC=4 sh "$SCRIPT" react tk-react1 >/dev/null 2>"$TMP/rerr3" || rrc=$?
eq "$rrc" "6" "(REACT) a live-workflow skip (sling exit 4) becomes react exit 6"
grep -q "a live workflow already drives tk-react1" "$TMP/rerr3" \
  && ok "(REACT) …and names the no-op cause" \
  || bad "(REACT) react live-workflow message missing: $(cat "$TMP/rerr3")"
grep -q "already carries a first reaction\|failed" "$TMP/rerr3" \
  && bad "(REACT) a live-workflow skip must not read as already reacted or as a failure" \
  || ok "(REACT) …and is neither an already-reacted skip nor a failure"

# The sling's dispatch-path guard exits RC_DISPATCH_PATH (5) when the bead is
# already routed or armed: a third no-op with its own cause. react re-raises it
# as its own code (7). Without that, react would report the skip as a failure
# (exit 4) and the intake caller would name a failure to file that never
# happened.
rrc=0; FAKE_SLING_RC=5 sh "$SCRIPT" react tk-react1 >/dev/null 2>"$TMP/rerr4" || rrc=$?
eq "$rrc" "7" "(REACT) a dispatch-path skip (sling exit 5) becomes react exit 7"
grep -q "tk-react1 is already routed or armed" "$TMP/rerr4" \
  && ok "(REACT) …and names the no-op cause" \
  || bad "(REACT) react dispatch-path message missing: $(cat "$TMP/rerr4")"
grep -q "already has an open first reaction\|live workflow\|failed" "$TMP/rerr4" \
  && bad "(REACT) a dispatch-path skip must not read as another skip or as a failure" \
  || ok "(REACT) …and is neither of the other skips nor a failure"

# The sling's standing-record guard exits RC_STANDING_RECORD (6) when the bead is
# a standing record, which never closes and gives a reaction nothing to
# dispose: a fourth no-op with its own cause. react re-raises it as its own code
# (8), so the intake caller names that cause, never one of the other skips or a
# failure to file.
rrc=0; FAKE_SLING_RC=6 sh "$SCRIPT" react tk-react1 >/dev/null 2>"$TMP/rerr5" || rrc=$?
eq "$rrc" "8" "(REACT) a standing-record skip (sling exit 6) becomes react exit 8"
grep -q "tk-react1 is a standing record" "$TMP/rerr5" \
  && ok "(REACT) …and names the no-op cause" \
  || bad "(REACT) react standing-record message missing: $(cat "$TMP/rerr5")"
grep -q "already has an open first reaction\|live workflow\|already routed or armed\|failed" "$TMP/rerr5" \
  && bad "(REACT) a standing-record skip must not read as another skip or as a failure" \
  || ok "(REACT) …and is neither of the other skips nor a failure"
unset GC_PROACTIVE_TOOL FAKE_SLING_RC

echo ""
echo "gc-helm takeaway + react (release run end, waiting-on edges, length gate, react no-op exit): $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
