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
#   --waiting-on edges
#   the ≤140-codepoint length gate
#   the retired board verb refuses and names helm-svc board
#   the rig-enumeration helper leaving no trap installed on its caller
#   the react verb: an already-reacted sling skip (exit 3) re-raised as react's
#     own no-op code (5), distinct from a dispatch (0) and a real failure (4),
#     a live-workflow sling skip (exit 4) re-raised as react's code (6), and a
#     dispatch-path sling skip (exit 5) re-raised as react's code (7)
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

# Fold dispositions: bead_id|superseded_by
cat > "$TMP/superseded" <<'S'
CLOSED-A-FOLD|CARRIER-1
S

: > "$TMP/updates"     # one line per `gc bd update` invocation (the full argv)

# --- gc stub ------------------------------------------------------------------
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
case "$1 ${2:-}" in
  "rig list")
    # Two rigs. gc-toolkit's path has no .beads dir, so gc-helm issues
    # un-scoped bd calls for `tk-` ids; rig-a's does, so an `ra-` id
    # exercises the rig pin.
    jq -n --arg ra "$FAKE_RA_PATH" \
       '{rigs:[{name:"gc-toolkit", path:"/nonexistent-rig", prefix:"tk"},
               {name:"signal-loom", path:$sl, prefix:"sl"}]}' ;;
  "bd list")
    # Record the store this list actually read, so a lookup that searched the
    # caller's rig instead of the subject's is visible rather than silent.
    printf '%s\n' "${BEADS_DIR:-<unpinned>}" >> "$FAKE_LISTS"
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
    # UNKNOWN- ids resolve to nothing, the way `bd show` answers for a bead
    # that is not there: a bare error OBJECT, never an array.
    case "$id" in UNKNOWN-*) printf '{"error":"no issues found"}\n'; exit 0 ;; esac
    # CLOSED- ids answer status=closed; everything else is open. --release on a
    # closed anchor ends its run without the park.
    st=open; case "$id" in CLOSED-*) st=closed ;; esac
    convoy=$(awk -F'|' -v r="$id" '$1==r{print $2; exit}' "$FAKE_ROOTS")
    # What gc.routed_to reads back as. FAKE_ROUTED holds it, so a test can
    # model the route LANDING and the route landing EMPTY (the silent drop a
    # multi-pair --set-metadata update can produce) with the same stub.
    routed="$(cat "${FAKE_ROUTED:-/dev/null}" 2>/dev/null || true)"
    # What gc.execution_routed_to reads back as: the pour stamp a --release
    # retires. FAKE_EXEC holds it, so a test models the clear LANDING (empty)
    # and the clear being DROPPED (the stamp still standing) with one stub.
    exec_routed="$(cat "${FAKE_EXEC:-/dev/null}" 2>/dev/null || true)"
    # What gc.takeaway_settled reads back as. Every landed write updates it
    # below, so the default fixture models a store that keeps what it was told;
    # FAKE_SETTLED_DROP models the pair that silently does not land.
    settled="$(cat "${FAKE_SETTLED:-/dev/null}" 2>/dev/null || true)"
    # What gc.takeaway, the headline itself, reads back as. It lands below the
    # same way gc.takeaway_settled does, and FAKE_TAKEAWAY_DROP is its silent drop.
    takeaway="$(cat "${FAKE_TAKEAWAY:-/dev/null}" 2>/dev/null || true)"
    # What gc.session_name / gc.session_id read back as: the executor identity a
    # --release clears via --unset-metadata. FAKE_SNAME/FAKE_SID hold them, so a
    # test models the clear LANDING (empty) and being DROPPED (the pin still
    # standing) with one stub, the way FAKE_EXEC does for the pour stamp.
    sname="$(cat "${FAKE_SNAME:-/dev/null}" 2>/dev/null || true)"
    sid="$(cat "${FAKE_SID:-/dev/null}" 2>/dev/null || true)"
    # A folded anchor names the bead that carried its work on. The release
    # path reads it to say which disposition it is preserving; an empty
    # string reads the same as an absent key, which is every other bead.
    sup="$(awk -F'|' -v i="$id" '$1==i{print $2; exit}' "$FAKE_SUPERSEDED" 2>/dev/null || true)"
    # metadata.branch is what the refinery records when work rides another bead's
    # branch; --waiting-on reads it to tell a same-branch rider from a separate
    # deliverable. Absent id -> empty, which reads the same as an absent key.
    br="$(awk -F'|' -v i="$id" '$1==i{print $2; exit}' "$FAKE_BRANCHES" 2>/dev/null || true)"
    # Top-level assignee, from FAKE_ASSIGNEES (id|assignee). --waiting-on reads it
    # as one proof a same-branch wait's work has LANDED on the branch: the handoff
    # submit-and-exit writes only after it verifies the push. Absent id -> empty.
    asg="$(awk -F'|' -v i="$id" '$1==i{print $2; exit}' "$FAKE_ASSIGNEES" 2>/dev/null || true)"
    if [ -n "$convoy" ]; then row=$(jq -n --arg i "$id" --arg s "$st" --arg a "$asg" --arg c "$convoy" --arg rt "$routed" --arg er "$exec_routed" --arg sp "$sup" --arg sd "$settled" --arg tk "$takeaway" --arg sn "$sname" --arg si "$sid" --arg br "$br" '[{id:$i,status:$s,assignee:$a,metadata:{"gc.input_convoy_id":$c,"gc.routed_to":$rt,"gc.execution_routed_to":$er,"gc.superseded_by":$sp,"gc.takeaway":$tk,"gc.takeaway_settled":$sd,"gc.session_name":$sn,"gc.session_id":$si,"branch":$br}}]')
    else row=$(jq -n --arg i "$id" --arg s "$st" --arg a "$asg" --arg rt "$routed" --arg er "$exec_routed" --arg sp "$sup" --arg sd "$settled" --arg tk "$takeaway" --arg sn "$sname" --arg si "$sid" --arg br "$br" '[{id:$i,status:$s,assignee:$a,metadata:{"gc.routed_to":$rt,"gc.execution_routed_to":$er,"gc.superseded_by":$sp,"gc.takeaway":$tk,"gc.takeaway_settled":$sd,"gc.session_name":$sn,"gc.session_id":$si,"branch":$br}}]'); fi
    # The placement marker intake writes, and a parent-child parent: the release's
    # pour-stamp read-back judges both through placement.sh. FAKE_PLACEMENT and
    # FAKE_PARENT hold them, and an empty file leaves the key off the row, as on
    # every bead intake never held.
    pl="$(cat "${FAKE_PLACEMENT:-/dev/null}" 2>/dev/null || true)"
    pa="$(cat "${FAKE_PARENT:-/dev/null}" 2>/dev/null || true)"
    if [ -n "$pl$pa" ]; then
      row=$(printf '%s' "$row" | jq --arg pl "$pl" --arg pa "$pa" \
        '(if $pl != "" then .[0].metadata.placement = $pl else . end) | (if $pa != "" then .[0].parent = $pa else . end)')
    fi
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
    # a bead fails to land.
    case "$3" in *NOPIN*) exit 1 ;; esac
    # gc.takeaway_settled lands here so a read-back sees what was written.
    # FAKE_SETTLED_DROP=1 loses every one of them (no repair recovers it);
    # =multi loses it only out of a multi-pair stamp, which is the shape a lone
    # repair write recovers — the two halves of one silent-drop story.
    pairs=0
    for a in "$@"; do [ "$a" = "--set-metadata" ] && pairs=$((pairs + 1)); done
    for a in "$@"; do
      case "$a" in
        gc.takeaway_settled=*)
          case "${FAKE_SETTLED_DROP:-}" in
            1)     ;;
            multi) [ "$pairs" -le 1 ] && printf '%s' "${a#gc.takeaway_settled=}" > "$FAKE_SETTLED" ;;
            *)     printf '%s' "${a#gc.takeaway_settled=}" > "$FAKE_SETTLED" ;;
          esac ;;
        # gc.takeaway, the headline, lands here too. FAKE_TAKEAWAY_DROP=1 loses
        # every one; =once loses only the first, marked by $FAKE_TAKEAWAY.dropped,
        # the transient drop a repair recovers. The repair re-stamps the
        # disposition beside the headline, so it is a multi-pair write itself,
        # and a pair-count rule like the settled key's would drop it as well.
        gc.takeaway=*)
          case "${FAKE_TAKEAWAY_DROP:-}" in
            1)    ;;
            once) if [ -e "$FAKE_TAKEAWAY.dropped" ]; then printf '%s' "${a#gc.takeaway=}" > "$FAKE_TAKEAWAY"
                  else : > "$FAKE_TAKEAWAY.dropped"; fi ;;
            *)    printf '%s' "${a#gc.takeaway=}" > "$FAKE_TAKEAWAY" ;;
          esac ;;
        # gc.execution_routed_to is CLEARED via --unset-metadata, so its token
        # arrives bare (no =value). A landed clear empties FAKE_EXEC, so the
        # read-back reads absent. FAKE_EXEC_DROP=1 loses every clear (the store
        # that will not take it, no repair recovers it); =multi loses it only
        # out of the multi-pair release write, the shape the lone repair clears.
        gc.execution_routed_to)
          case "${FAKE_EXEC_DROP:-}" in
            1)     ;;
            multi) [ "$pairs" -le 1 ] && : > "$FAKE_EXEC" ;;
            *)     : > "$FAKE_EXEC" ;;
          esac ;;
        # gc.session_name / gc.session_id are CLEARED via --unset-metadata, bare
        # like the pour stamp. A landed clear empties the pin file so the read-back
        # reads absent. FAKE_SNAME_DROP/FAKE_SID_DROP=1 lose every clear (no repair
        # recovers it); =multi loses it only out of the multi-pair release write,
        # the shape the lone repair unset clears.
        gc.session_name)
          case "${FAKE_SNAME_DROP:-}" in
            1)     ;;
            multi) [ "$pairs" -le 1 ] && : > "$FAKE_SNAME" ;;
            *)     : > "$FAKE_SNAME" ;;
          esac ;;
        gc.session_id)
          case "${FAKE_SID_DROP:-}" in
            1)     ;;
            multi) [ "$pairs" -le 1 ] && : > "$FAKE_SID" ;;
            *)     : > "$FAKE_SID" ;;
          esac ;;
      esac
    done ;;
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
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

# run-cancel.sh stand-in: each call's argv on one line of FAKE_CANCELS, and
# FAKE_CANCEL_RC as its exit, so a test can make a run that will not end.
cat > "$TMP/bin/run-cancel-stub" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${FAKE_CANCELS:?}"
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
       FAKE_EXEC="$TMP/exec" FAKE_PLACEMENT="$TMP/placement" FAKE_PARENT="$TMP/parent" \
       FAKE_SNAME="$TMP/sname" FAKE_SID="$TMP/sid" FAKE_DEPLISTS="$TMP/deplists" \
       FAKE_BRANCHES="$TMP/branches" FAKE_ASSIGNEES="$TMP/assignees" \
       FAKE_CONVOY_CALLS="$TMP/convoy-calls"
mkdir -p "$TMP/signal-loom/.beads" "$TMP/deplists"
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
[{"id":"w-child","status":"open","dependency_type":"blocks","metadata":{}},
 {"id":"g-mine","status":"open","issue_type":"gate","await_type":"human","await_id":"rollout","dependency_type":"blocks","metadata":{}}]
J
cat > "$TMP/deplists/A-GATED.json" <<'J'
[{"id":"g-mine","status":"open","issue_type":"gate","await_type":"human","await_id":"rollout","dependency_type":"blocks","metadata":{}}]
J
cat > "$TMP/deplists/A-DONEBLK.json" <<'J'
[{"id":"w-child","status":"closed","dependency_type":"blocks","metadata":{}}]
J
cat > "$TMP/deplists/CLOSED-A-FOLD.json" <<'J'
[{"id":"w-child","status":"open","dependency_type":"blocks","metadata":{}}]
J
cat > "$TMP/deplists/A-PROBEDEAD.json" <<'J'
[{"id":"w-child","status":"open","dependency_type":"blocks","metadata":{}}]
J
cat > "$TMP/deplists/A-PROBEJUNK.json" <<'J'
[{"id":"w-child","status":"open","dependency_type":"blocks","metadata":{}}]
J
export FAKE_RA_PATH="$TMP/rig-a"
: > "$TMP/deps"; : > "$TMP/closes"; : > "$TMP/lists"; : > "$TMP/routed"
: > "$TMP/settled"; : > "$TMP/takeaway"
# metadata.branch per bead, for the --waiting-on landed-rider skip. w-same,
# w-pend and CLOSED-w-rider all share A-ONBR's branch; w-diff rides its own and
# w-nobr has none. A-PARKED/tk-blk* stay branchless so the edge tests above them
# keep writing edges. A shared branch alone is not landing: the proof is the
# status/assignee below — w-same is handed off to the refinery and CLOSED-w-rider
# has merged (both landed riders), while w-pend is still open under a pool, so its
# work is not on the branch yet and its edge stands.
cat > "$TMP/branches" <<'BR'
A-ONBR|polecat/A-ONBR
w-same|polecat/A-ONBR
w-pend|polecat/A-ONBR
CLOSED-w-rider|polecat/A-ONBR
w-diff|polecat/w-diff
BR
# Top-level assignee per bead. The refinery is the post-push handoff that makes
# w-same a LANDED rider; w-pend's pool assignee is work still owed, not that proof.
cat > "$TMP/assignees" <<'ASG'
w-same|gc-toolkit/gc-toolkit.refinery
w-pend|gc-toolkit/gc-toolkit.polecat-3
ASG
unset GC_HELM_FIXTURE || true
# GC_RIG and BEADS_DIR too: the current-sitting lookup resolves the session's
# rig, and an ambient value from the runner's own agent env would pin a store
# the fixtures never set up.
unset GC_SESSION_NAME GC_SESSION_ID GC_ALIAS GC_RIG BEADS_DIR || true

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
grep -q 'gc.routed_to=' <<< "$A" \
  && ok "(RELEASE) anchor route cleared" || bad "(RELEASE) anchor route cleared"
# The pour that dispatched this bead stamped gc.execution_routed_to; a release
# ends that pour, so the stamp is retired in the same write, and a parked or
# re-routed bead does not linger advertising a finished pour's pool. The stamp's
# read-back is covered with the EXEC cases below.
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
#   (EDGEFAIL)  a rejected edge never loses the takeaway, and the verb exits 0
#   (EDGENONE)  no flag, no edges
: > "$TMP/updates"; : > "$TMP/deps"
sh "$SCRIPT" takeaway A-PARKED "routed — the fix is slung" --by converse \
   --waiting-on tk-blk1 --waiting-on=tk-blk2 >/dev/null 2>"$TMP/werr" || true
DEPS="$(cat "$TMP/deps")"

grep -qE '^bd dep add A-PARKED tk-blk1 -t blocks' <<< "$DEPS" \
  && ok "(EDGE) the wait is written as an edge: A-PARKED depends on tk-blk1" \
  || bad "(EDGE) no depends-on edge for tk-blk1 (got: ${DEPS:-<none>})"
grep -qE '^bd dep add A-PARKED tk-blk2 -t blocks' <<< "$DEPS" \
  && ok "(EDGEMANY) --waiting-on repeats, and the =VALUE form parses" \
  || bad "(EDGEMANY) tk-blk2 missing (got: ${DEPS:-<none>})"
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

# (EDGEFAIL) the takeaway is written FIRST; a failed edge warns, exit stays 0.
: > "$TMP/updates"; : > "$TMP/deps"
WRC=0
sh "$SCRIPT" takeaway A-PARKED "held for review" --waiting-on NOPE >/dev/null 2>"$TMP/werr" || WRC=$?
grep -q -- '--set-metadata gc.takeaway=held for review' "$TMP/updates" \
  && ok "(EDGEFAIL) a rejected edge does not cost the takeaway" \
  || bad "(EDGEFAIL) the stamp was lost when the edge failed: $(cat "$TMP/updates")"
grep -q 'could not wire' "$TMP/werr" \
  && ok "(EDGEFAIL) …and the failure is reported, not swallowed" \
  || bad "(EDGEFAIL) the failed edge was silent (stderr: $(cat "$TMP/werr"))"
eq "$WRC" "0" "(EDGEFAIL) …and the verb still succeeds: the takeaway landed"

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
   --waiting-on w-same >/dev/null 2>"$TMP/werr" || true
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
   --waiting-on CLOSED-w-rider >/dev/null 2>&1 || true
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
   --waiting-on w-pend >/dev/null 2>&1 || true
grep -qE '^bd dep add A-ONBR w-pend -t blocks' "$TMP/deps" \
  && ok "(EDGEUNLANDED) a same-branch wait not yet landed keeps its edge" \
  || bad "(EDGEUNLANDED) a same-branch wait was dropped without proof it landed (got: $(cat "$TMP/deps"))"
grep -q -- '--set-metadata gc.takeaway_settled=1' "$TMP/updates" \
  && bad "(EDGEUNLANDED) an unlanded same-branch wait must NOT settle — the edge is the hold" \
  || ok "(EDGEUNLANDED) …and the sitting stays unsettled"

: > "$TMP/deps"
sh "$SCRIPT" takeaway A-ONBR "waiting on a separate PR" --waiting-on w-diff >/dev/null 2>&1 || true
grep -qE '^bd dep add A-ONBR w-diff -t blocks' "$TMP/deps" \
  && ok "(EDGESEP) a wait on its OWN branch still records its edge" \
  || bad "(EDGESEP) the separate-deliverable edge was dropped (got: $(cat "$TMP/deps"))"

: > "$TMP/deps"
sh "$SCRIPT" takeaway A-ONBR "waiting on a branchless bead" --waiting-on w-nobr >/dev/null 2>&1 || true
grep -qE '^bd dep add A-ONBR w-nobr -t blocks' "$TMP/deps" \
  && ok "(EDGENOBR) a wait with no branch still records its edge (fail toward keeping)" \
  || bad "(EDGENOBR) a branchless wait was dropped (got: $(cat "$TMP/deps"))"

: > "$TMP/deps"
sh "$SCRIPT" takeaway A-PARKED "branchless subject" --waiting-on w-same >/dev/null 2>&1 || true
grep -qE '^bd dep add A-PARKED w-same -t blocks' "$TMP/deps" \
  && ok "(EDGENOSUBJ) a branchless subject never skips — the guard needs the subject's own branch" \
  || bad "(EDGENOSUBJ) a branchless subject wrongly skipped an edge (got: $(cat "$TMP/deps"))"

: > "$TMP/deps"; : > "$TMP/updates"
sh "$SCRIPT" takeaway A-ONBR "one rides, one is separate" \
   --waiting-on w-same --waiting-on w-diff >/dev/null 2>&1 || true
eq "$(grep -c '^bd dep add' "$TMP/deps" || true)" "1" "(EDGEMIX) exactly one edge from a rider+separate pair"
grep -qE '^bd dep add A-ONBR w-diff -t blocks' "$TMP/deps" \
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
sh "$SCRIPT" takeaway A-PARKED "routed — the fix is slung" --waiting-on tk-blk1 >/dev/null 2>&1 || true
grep -q -- '--set-metadata gc.takeaway_settled=$' "$TMP/updates" \
  && ok "(UNSETTLED) …and so does a takeaway whose wait is an edge" \
  || bad "(UNSETTLED) --waiting-on left a settled key standing: $(cat "$TMP/updates")"

: > "$TMP/updates"; : > "$TMP/deps"
BRC=0
sh "$SCRIPT" takeaway A-PARKED "both" --no-wait --waiting-on tk-blk1 >/dev/null 2>"$TMP/berr" || BRC=$?
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

# ── the disposition is READ BACK: a stamp that did not land is not one ───────
# One `--set-metadata` pair in a multi-pair update can silently not land, which
# is why the route beside it is read back. The settled-key is the pair whose
# miss is a WRONG answer rather than a missing one: a park that inherits the
# previous sitting's "1" reads as a wait already discharged, and
# doctor/check-wait-is-an-edge — the one reader that would report it — skips it
# for as long as the stamp stands. Covered:
#   (SETTLEDOK)   a disposition that reads back is written once, exit 0
#   (SETTLEDFIX)  a dropped clear over a stale "1" is repaired, and says so
#   (SETTLEDDEAD) a repair that also misses is a verb failure, writes kept
#   (SETTLEDBACK) the same guard the other way: a settled stamp that lands empty
: > "$TMP/updates"; printf '1' > "$TMP/settled"
ORC=0
sh "$SCRIPT" takeaway A-PARKED "settled — the board was right" --no-wait >/dev/null 2>"$TMP/serr" || ORC=$?
eq "$ORC" "0" "(SETTLEDOK) a disposition that reads back exits 0"
eq "$(grep -c -- '--set-metadata gc.takeaway_settled=' "$TMP/updates" || true)" "1" \
   "(SETTLEDOK) …and is written once, with no repair"
eq "$(cat "$TMP/serr")" "" "(SETTLEDOK) …and says nothing about a read-back"

# (SETTLEDFIX) the stale "1" of the sitting before this park, and a clear that
# does not land: the multi-pair stamp drops it, the lone repair write carries it.
: > "$TMP/updates"; printf '1' > "$TMP/settled"
FRC=0
FAKE_SETTLED_DROP=multi sh "$SCRIPT" takeaway A-PARKED "holding — needs a ruling" \
  >/dev/null 2>"$TMP/serr" || FRC=$?
eq "$(grep -c -- '--set-metadata gc.takeaway_settled=$' "$TMP/updates" || true)" "2" \
   "(SETTLEDFIX) a clear that did not land is re-written"
grep -q "gc.takeaway_settled on A-PARKED read back as '1'" "$TMP/serr" \
  && ok "(SETTLEDFIX) …and the miss is reported with the value that stood" \
  || bad "(SETTLEDFIX) the dropped clear was silent (stderr: $(cat "$TMP/serr"))"
grep -q 'the disposition repair landed' "$TMP/serr" \
  && ok "(SETTLEDFIX) …and so is the repair that fixed it" \
  || bad "(SETTLEDFIX) the repair did not report landing (stderr: $(cat "$TMP/serr"))"
eq "$FRC" "0" "(SETTLEDFIX) …and a repaired disposition is not a verb failure"
eq "$(cat "$TMP/settled")" "" "(SETTLEDFIX) …the bead ends on the park's own disposition"

# (SETTLEDDEAD) the store that will not take the clear at all. The headline is
# stamped and the bead reads settled, so a zero exit would report a park that
# no wait check will ever report.
: > "$TMP/updates"; printf '1' > "$TMP/settled"
DRC=0
FAKE_SETTLED_DROP=1 sh "$SCRIPT" takeaway A-PARKED "holding — needs a ruling" \
  >"$TMP/sout" 2>"$TMP/serr" || DRC=$?
eq "$DRC" "4" "(SETTLEDDEAD) a disposition that will not stamp is a verb runtime failure"
grep -q "still reads gc.takeaway_settled='1'" "$TMP/serr" \
  && ok "(SETTLEDDEAD) …and the message names the value left standing" \
  || bad "(SETTLEDDEAD) the persistent miss does not name the stale value (stderr: $(cat "$TMP/serr"))"
grep -q -- '--set-metadata gc.takeaway_settled=' "$TMP/serr" \
  && ok "(SETTLEDDEAD) …and carries the by-hand repair" \
  || bad "(SETTLEDDEAD) no repair spelled out (stderr: $(cat "$TMP/serr"))"
grep -q 'takeaway set on' "$TMP/sout" \
  && bad "(SETTLEDDEAD) the verb reported success on a bead reading settled" \
  || ok "(SETTLEDDEAD) …and does not report the takeaway as set"
grep -q -- '--set-metadata gc.takeaway=holding — needs a ruling' "$TMP/updates" \
  && ok "(SETTLEDDEAD) …the headline it did write is kept, not rolled back" \
  || bad "(SETTLEDDEAD) the headline write was lost: $(cat "$TMP/updates")"

# (SETTLEDBACK) the miss in the other direction costs a false finding rather
# than a missing one, and is still a write that did not land.
: > "$TMP/updates"; : > "$TMP/settled"
BRC2=0
FAKE_SETTLED_DROP=1 sh "$SCRIPT" takeaway A-PARKED "settled — nothing waits" --no-wait \
  >/dev/null 2>"$TMP/serr" || BRC2=$?
eq "$BRC2" "4" "(SETTLEDBACK) a settled stamp that reads back empty fails the verb too"
grep -q "expected '1'" "$TMP/serr" \
  && ok "(SETTLEDBACK) …and the message names what the writer asked for" \
  || bad "(SETTLEDBACK) the refusal does not name the intended value (stderr: $(cat "$TMP/serr"))"
: > "$TMP/settled"

# ── the headline is READ BACK: a headline that did not land is not set ───────
# The headline rides the same multi-pair write as the disposition, so the same
# silent drop can leave it out. A headline that does not land leaves the one the
# bead carried before: empty, or an earlier sitting's. The read-back compares
# with the text this call wrote, so a stale headline is a miss as much as an
# empty one. Covered:
#   (TAKEAWAYOK)    a headline that reads back is written once, exit 0, no word
#   (TAKEAWAYFIX)   a stale headline the stamp did not replace is re-stamped
#                   with its disposition, exit 0
#   (TAKEAWAYDEAD)  a repair that also misses is a verb failure, writes kept
#   (TAKEAWAYEMPTY) a headline that reads back empty fails the verb the same way
#   (TAKEAWAYREL)   under --release, the exit waits for the edges and the run's end
#   (TAKEAWAYFOLD)  on a closed anchor's run end too
#   (TAKEAWAYQUOTE) the by-hand repair, pasted into a shell, stamps the exact text
: > "$TMP/updates"; : > "$TMP/settled"; printf 'holding — an earlier sitting' > "$TMP/takeaway"
TORC=0
sh "$SCRIPT" takeaway A-PARKED "settled — the board was right" --no-wait >"$TMP/tout" 2>"$TMP/terr" || TORC=$?
eq "$TORC" "0" "(TAKEAWAYOK) a headline that reads back exits 0"
eq "$(grep -c -- '--set-metadata gc.takeaway=' "$TMP/updates" || true)" "1" \
   "(TAKEAWAYOK) …and is written once, with no repair"
eq "$(cat "$TMP/terr")" "" "(TAKEAWAYOK) …and says nothing about a read-back"
grep -q 'takeaway set on A-PARKED' "$TMP/tout" \
  && ok "(TAKEAWAYOK) …and reports the takeaway as set" \
  || bad "(TAKEAWAYOK) the success line is missing (stdout: $(cat "$TMP/tout"))"

# (TAKEAWAYFIX) the headline of the sitting before this one, and a stamp that
# does not replace it: the stamp drops the pair, the repair carries it.
# Non-empty and wrong, so only an equality check sees it.
: > "$TMP/updates"; : > "$TMP/settled"; printf 'holding — an earlier sitting' > "$TMP/takeaway"
rm -f "$TMP/takeaway.dropped"
TFRC=0
FAKE_TAKEAWAY_DROP=once sh "$SCRIPT" takeaway A-PARKED "settled — the board was right" --no-wait \
  >"$TMP/tout" 2>"$TMP/terr" || TFRC=$?
eq "$(grep -c -- '--set-metadata gc.takeaway=settled — the board was right' "$TMP/updates" || true)" "2" \
   "(TAKEAWAYFIX) a headline that did not land is re-written"
# Every headline write carries its disposition (lifecycle.toml [holds]), the
# repair included, so the repaired headline never stands beside a disposition
# an earlier sitting left.
eq "$(grep -cxF -- 'bd update A-PARKED --set-metadata gc.takeaway=settled — the board was right --set-metadata gc.takeaway_settled=1' "$TMP/updates" || true)" "1" \
   "(TAKEAWAYFIX) …and the repair re-stamps this call's disposition beside it"
grep -q "gc.takeaway on A-PARKED read back as 'holding — an earlier sitting'" "$TMP/terr" \
  && ok "(TAKEAWAYFIX) …and the miss is reported with the stale headline that stood" \
  || bad "(TAKEAWAYFIX) the stale headline was read as landed (stderr: $(cat "$TMP/terr"))"
grep -q 'the headline repair landed' "$TMP/terr" \
  && ok "(TAKEAWAYFIX) …and so is the repair that fixed it" \
  || bad "(TAKEAWAYFIX) the repair did not report landing (stderr: $(cat "$TMP/terr"))"
eq "$TFRC" "0" "(TAKEAWAYFIX) …and a repaired headline is not a verb failure"
eq "$(cat "$TMP/takeaway")" "settled — the board was right" "(TAKEAWAYFIX) …the bead ends on this call's headline"
grep -q 'takeaway set on A-PARKED' "$TMP/tout" \
  && ok "(TAKEAWAYFIX) …and the takeaway is reported as set" \
  || bad "(TAKEAWAYFIX) a repaired headline was not reported (stdout: $(cat "$TMP/tout"))"

# (TAKEAWAYDEAD) the store that will not take the headline at all. The bead
# still carries the earlier sitting's headline, so a zero exit would tell the
# caller the board shows a conclusion it does not show.
: > "$TMP/updates"; : > "$TMP/settled"; printf 'holding — an earlier sitting' > "$TMP/takeaway"
TDRC=0
FAKE_TAKEAWAY_DROP=1 sh "$SCRIPT" takeaway A-PARKED "settled — the board was right" --no-wait \
  >"$TMP/tout" 2>"$TMP/terr" || TDRC=$?
eq "$TDRC" "4" "(TAKEAWAYDEAD) a headline that will not stamp is a verb runtime failure"
grep -q "still reads gc.takeaway='holding — an earlier sitting'" "$TMP/terr" \
  && ok "(TAKEAWAYDEAD) …and the message names the headline left standing" \
  || bad "(TAKEAWAYDEAD) the persistent miss does not name the stale headline (stderr: $(cat "$TMP/terr"))"
grep -q -- "--set-metadata 'gc.takeaway=settled — the board was right' --set-metadata gc.takeaway_settled=1$" "$TMP/terr" \
  && ok "(TAKEAWAYDEAD) …and carries the by-hand repair, the headline with its disposition" \
  || bad "(TAKEAWAYDEAD) no repair spelled out (stderr: $(cat "$TMP/terr"))"
grep -q 'takeaway set on' "$TMP/tout" \
  && bad "(TAKEAWAYDEAD) the verb reported a headline as set that the bead does not carry" \
  || ok "(TAKEAWAYDEAD) …and does not report the takeaway as set"
eq "$(cat "$TMP/settled")" "1" "(TAKEAWAYDEAD) …the disposition written beside it is kept, not rolled back"

# (TAKEAWAYEMPTY) the same miss with no earlier headline to stand in its place.
: > "$TMP/updates"; : > "$TMP/settled"; : > "$TMP/takeaway"
TERC=0
FAKE_TAKEAWAY_DROP=1 sh "$SCRIPT" takeaway A-PARKED "holding — needs a ruling" \
  >/dev/null 2>"$TMP/terr" || TERC=$?
eq "$TERC" "4" "(TAKEAWAYEMPTY) a headline that reads back empty fails the verb too"
grep -q "gc.takeaway on A-PARKED read back as '', expected 'holding — needs a ruling'" "$TMP/terr" \
  && ok "(TAKEAWAYEMPTY) …and the message names what the writer asked for" \
  || bad "(TAKEAWAYEMPTY) the miss does not name the intended headline (stderr: $(cat "$TMP/terr"))"

# (TAKEAWAYREL) a park, with a wait, whose headline will not stamp. The exit
# comes last, so the wait is still wired as an edge and the run beneath the
# anchor still ends: only the headline is left to repair by hand.
: > "$TMP/updates"; : > "$TMP/deps"; : > "$TMP/settled"; : > "$FAKE_CANCELS"; printf 'holding — an earlier sitting' > "$TMP/takeaway"
TRRC=0
FAKE_TAKEAWAY_DROP=1 sh "$SCRIPT" takeaway A-PARKED "parked — waiting on the fix" --by proactive \
  --release --waiting-on tk-blk9 >"$TMP/tout" 2>"$TMP/terr" || TRRC=$?
eq "$TRRC" "4" "(TAKEAWAYREL) a release whose headline will not stamp is a verb failure"
grep -qE '^bd dep add A-PARKED tk-blk9 -t blocks' "$TMP/deps" \
  && ok "(TAKEAWAYREL) …after the wait is wired as an edge" \
  || bad "(TAKEAWAYREL) the failure exited before the edge (deps: $(cat "$TMP/deps"))"
grep -q -- '--root root-PARKED' "$FAKE_CANCELS" \
  && ok "(TAKEAWAYREL) …and after the run beneath the anchor is ended" \
  || bad "(TAKEAWAYREL) the failure exited before ending the run beneath the anchor"
TRL="$(grep -E "^bd update A-PARKED( |\$)" "$TMP/updates" | head -n1)"
case "$TRL" in
  *"--status=open"*"--assignee="*) ok "(TAKEAWAYREL) …and the release it already wrote is kept, not rolled back" ;;
  *) bad "(TAKEAWAYREL) the release write was lost: ${TRL:-<none>}" ;;
esac
grep -q 'takeaway set on' "$TMP/tout" \
  && bad "(TAKEAWAYREL) the verb reported the takeaway as set" \
  || ok "(TAKEAWAYREL) …and success is not reported"

# (TAKEAWAYFOLD) a closed anchor takes the headline and the run's end alone, and
# its headline is read back the same way.
: > "$TMP/updates"; : > "$TMP/settled"; : > "$FAKE_CANCELS"; printf 'holding — an earlier sitting' > "$TMP/takeaway"
TCRC=0
FAKE_TAKEAWAY_DROP=1 sh "$SCRIPT" takeaway CLOSED-A-FOLD "folded into CARRIER-1" --by proactive --release \
  >"$TMP/tout" 2>"$TMP/terr" || TCRC=$?
eq "$TCRC" "4" "(TAKEAWAYFOLD) a closed anchor's headline that will not stamp is a verb failure"
grep -q -- '--root root-FOLD' "$FAKE_CANCELS" \
  && ok "(TAKEAWAYFOLD) …after the folded anchor's run is ended" \
  || bad "(TAKEAWAYFOLD) the failure exited before the run's end"
grep -q 'anchor left closed' "$TMP/tout" \
  && bad "(TAKEAWAYFOLD) the verb reported the run's end as a set takeaway" \
  || ok "(TAKEAWAYFOLD) …and success is not reported"

# (TAKEAWAYQUOTE) the by-hand repair is pasted into a shell, and a headline is
# free text. Run the printed command against the store and read what it stamps.
QTEXT="it's the operator's call: \$HOME, \`date\` and C:\\new stay literal"
: > "$TMP/updates"; : > "$TMP/settled"; : > "$TMP/takeaway"
TQRC=0
FAKE_TAKEAWAY_DROP=1 sh "$SCRIPT" takeaway A-PARKED "$QTEXT" >/dev/null 2>"$TMP/terr" || TQRC=$?
eq "$TQRC" "4" "(TAKEAWAYQUOTE) a free-text headline that will not stamp fails the verb"
grep -qF "expected '$QTEXT' — repairing" "$TMP/terr" \
  && ok "(TAKEAWAYQUOTE) …and the miss prints the headline exactly as written" \
  || bad "(TAKEAWAYQUOTE) the miss rewrote the headline it reports (stderr: $(cat "$TMP/terr"))"
QREPAIR="$(sed -n 's/.*Stamp it by hand: //p' "$TMP/terr")"
case "$QREPAIR" in
  "gc bd update A-PARKED --set-metadata "*) ok "(TAKEAWAYQUOTE) …and prints a by-hand repair" ;;
  *) bad "(TAKEAWAYQUOTE) no by-hand repair to paste (stderr: $(cat "$TMP/terr"))" ;;
esac
sh -c "$QREPAIR" >/dev/null 2>&1 || true
eq "$(cat "$TMP/takeaway")" "$QTEXT" \
   "(TAKEAWAYQUOTE) …that, pasted into a shell, stamps the headline exactly"
: > "$TMP/takeaway"

# ── takeaway --release --route: release the bead TO a pool ────────────────────
# A first reaction that concludes "this is work" hands the bead on instead of
# back. The route rides the release write, so the disposition lands whole or
# not at all. Covered:
#   (ROUTE)     the route replaces the empty clear, in the SAME single update
#   (ROUTECLR)  no --route still clears the route (the release is unchanged)
#   (ROUTEQUAL) a bare agent name is refused before anything is written
#   (ROUTEREL)  --route without --release is refused (the unreadable half-state)
#   (ROUTEOK)   a route that reads back correct is not re-written
#   (ROUTEFIX)  a route that reads back EMPTY is repaired and reported
#   (ROUTEDEAD) a repair that also misses is a verb failure, with its writes kept
POOL="gc-toolkit/gc-toolkit.polecat"
: > "$TMP/updates"; printf '%s' "$POOL" > "$TMP/routed"
sh "$SCRIPT" takeaway A-PARKED "actionable — routed to the polecat pool" \
   --by proactive --release --route "$POOL" >/dev/null 2>"$TMP/rerr" || true
RLINE="$(grep -E "^bd update A-PARKED( |$)" "$TMP/updates" | head -n1)"
case "$RLINE" in
  *"--set-metadata gc.routed_to=$POOL"*) ok "(ROUTE) the release routes the bead to the pool" ;;
  *) bad "(ROUTE) no route stamp in the release write (got: ${RLINE:-<none>})" ;;
esac
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

# (ROUTEOK) a landed route is verified once and left alone.
: > "$TMP/updates"; printf '%s' "$POOL" > "$TMP/routed"
sh "$SCRIPT" takeaway A-PARKED "landed" --release --route "$POOL" >/dev/null 2>"$TMP/rerr" || true
eq "$(grep -cE "^bd update A-PARKED( |\$)" "$TMP/updates" || true)" "1" \
   "(ROUTEOK) a route that reads back correct is written once (the anchor, and no step of its run)"

# (ROUTEFIX) the silent drop: the stamp lands empty, so the bead is visible to
# no pool. The verb must notice and repair rather than report success.
: > "$TMP/updates"; : > "$TMP/routed"; : > "$FAKE_CANCELS"
FRC=0
sh "$SCRIPT" takeaway A-PARKED "dropped" --release --route "$POOL" >"$TMP/rout" 2>"$TMP/rerr" || FRC=$?
eq "$(grep -c -- "--set-metadata gc.routed_to=$POOL" "$TMP/updates" || true)" "2" \
   "(ROUTEFIX) an empty read-back is re-stamped"
grep -q 'read back as' "$TMP/rerr" \
  && ok "(ROUTEFIX) …and the miss is reported" \
  || bad "(ROUTEFIX) the dropped route was silent (stderr: $(cat "$TMP/rerr"))"
grep -q 'visible to no pool' "$TMP/rerr" \
  && ok "(ROUTEFIX) …and a repair that also misses says what it costs" \
  || bad "(ROUTEFIX) the persistent miss does not name its consequence (stderr: $(cat "$TMP/rerr"))"

# (ROUTEDEAD) --route promises the pool can see the bead. A caller that reads a
# zero exit as "released to that pool" would drain over a bead nothing can
# claim, so the persistent miss is a verb failure — with every write that DID
# land kept, and named, so a hand repair finishes it.
eq "$FRC" "4" "(ROUTEDEAD) a route that will not stamp is a verb runtime failure"
grep -q 'takeaway set on' "$TMP/rout" \
  && bad "(ROUTEDEAD) the verb reported success on an unrouted bead" \
  || ok "(ROUTEDEAD) …and it does not report the takeaway as set"
grep -q -- '--set-metadata gc.routed_to=' "$TMP/rerr" \
  && ok "(ROUTEDEAD) …the message carries the by-hand repair" \
  || bad "(ROUTEDEAD) no repair spelled out (stderr: $(cat "$TMP/rerr"))"
RD="$(grep -E "^bd update A-PARKED( |\$)" "$TMP/updates" | head -n1)"
case "$RD" in
  *"--status=open"*"--assignee="*) ok "(ROUTEDEAD) …the release it already wrote is kept, not rolled back" ;;
  *) bad "(ROUTEDEAD) the release write was lost: ${RD:-<none>}" ;;
esac
grep -q -- '--root root-PARKED' "$FAKE_CANCELS" \
  && ok "(ROUTEDEAD) …and the run beneath the anchor is still ended" \
  || bad "(ROUTEDEAD) the failure exited before ending the run beneath the anchor"

# A route that lands is unaffected by any of that.
: > "$TMP/updates"; printf '%s' "$POOL" > "$TMP/routed"
GRC=0
sh "$SCRIPT" takeaway A-PARKED "landed clean" --release --route "$POOL" >"$TMP/rout" 2>/dev/null || GRC=$?
eq "$GRC" "0" "(ROUTEDEAD) a route that stamps still exits zero"
grep -q "released to $POOL" "$TMP/rout" \
  && ok "(ROUTEDEAD) …and says where the bead went" \
  || bad "(ROUTEDEAD) the success line lost the route (stdout: $(cat "$TMP/rout"))"

# ── takeaway --release: the pour stamp read-back ──────────────────────────────
# gc.execution_routed_to is the stamp a pour leaves naming the pool it dispatched
# a bead to, and a release ends that pour, so the release clears it. No arm or
# reconcile guard reads the stamp (reconcile keys on its own
# gc.dispatch_when_ready_slung marker), but placement.sh reads it as a live pour,
# which places a bead. The clear rides the multi-pair release write; a pair
# silently dropped there leaves the stamp standing, so the release retries a lone
# unset. If that also misses, the release fails where the stamp is all that keeps
# a bead held for placement out of the queue, and elsewhere warns and stands.
# Covered:
#   (EXECOK)      a clear that reads back empty is verified once, no repair, no word
#   (EXECFIX)     a clear dropped from the multi-pair write is retried and reported
#   (EXECWARN)    a clear that will not land on a bead routed to a pool warns, and
#                 the release still stands
#   (EXECHELD)    a clear that will not land on a bead held for placement fails
#                 the verb, because gc-helm.sh unplaced would not list the bead
#   (EXECHELDFIX) the same held bead, its clear carried by the lone repair, exits 0
#   (EXECPLACED)  a marked bead its parent places: the stamp hides nothing from
#                 the queue, so the miss warns
STAMP="gc-toolkit/gc-toolkit.proactive"

# (EXECOK) the clear lands: the release's own unset is the only one written, and
# a read-back that finds it gone says nothing.
: > "$TMP/updates"; : > "$TMP/exec"; : > "$TMP/settled"; printf '%s' "$POOL" > "$TMP/routed"
XORC=0
sh "$SCRIPT" takeaway A-PARKED "released clean" --by proactive --release --route "$POOL" \
  >/dev/null 2>"$TMP/xerr" || XORC=$?
eq "$XORC" "0" "(EXECOK) a pour stamp that reads back cleared exits 0"
eq "$(grep -c -- '--unset-metadata gc.execution_routed_to' "$TMP/updates" || true)" "1" \
   "(EXECOK) …and the clear is written once, with no repair"
grep -q 'gc.execution_routed_to on' "$TMP/xerr" \
  && bad "(EXECOK) a landed clear should say nothing (stderr: $(cat "$TMP/xerr"))" \
  || ok "(EXECOK) …and says nothing about a read-back"

# (EXECFIX) the stamp of the pour that dispatched this bead, and a clear that
# does not land: the multi-pair release drops it, the lone repair unset carries
# it. The stamp stood after the first write, so the read-back re-issues the clear.
: > "$TMP/updates"; printf '%s' "$STAMP" > "$TMP/exec"; : > "$TMP/settled"; printf '%s' "$POOL" > "$TMP/routed"
XFRC=0
FAKE_EXEC_DROP=multi sh "$SCRIPT" takeaway A-PARKED "actionable — routed to the pool" \
  --by proactive --release --route "$POOL" >/dev/null 2>"$TMP/xerr" || XFRC=$?
eq "$(grep -c -- '--unset-metadata gc.execution_routed_to' "$TMP/updates" || true)" "2" \
   "(EXECFIX) a clear that did not land is re-issued"
grep -q "gc.execution_routed_to on A-PARKED read back as '$STAMP'" "$TMP/xerr" \
  && ok "(EXECFIX) …and the miss is reported with the stamp that stood" \
  || bad "(EXECFIX) the dropped clear was silent (stderr: $(cat "$TMP/xerr"))"
grep -q 'execution-stamp repair landed' "$TMP/xerr" \
  && ok "(EXECFIX) …and the repair that fixed it says so" \
  || bad "(EXECFIX) the repair did not report landing (stderr: $(cat "$TMP/xerr"))"
eq "$XFRC" "0" "(EXECFIX) …and a repaired stamp is not a verb failure"
eq "$(cat "$TMP/exec")" "" "(EXECFIX) …the bead ends with the pour stamp cleared"

# (EXECWARN) the store that will not take the clear at all, on a bead the release
# routes to a pool and that nothing holds for placement. No reader misreads the
# stamp there, so it WARNS and the release still stands (exit 0). Failing here
# would exit 4 into first-reaction-dispose's die before its --then-route arm,
# skipping the arm over a stamp nothing misreads.
: > "$TMP/updates"; printf '%s' "$STAMP" > "$TMP/exec"; : > "$TMP/settled"; printf '%s' "$POOL" > "$TMP/routed"
XDRC=0
FAKE_EXEC_DROP=1 sh "$SCRIPT" takeaway A-PARKED "actionable — routed to the pool" \
  --by proactive --release --route "$POOL" >"$TMP/xout" 2>"$TMP/xerr" || XDRC=$?
eq "$XDRC" "0" "(EXECWARN) a pour stamp that will not clear does NOT fail the release"
grep -q "still carries gc.execution_routed_to='$STAMP'" "$TMP/xerr" \
  && ok "(EXECWARN) …and the warning names the stamp left standing" \
  || bad "(EXECWARN) the persistent miss does not name the stale stamp (stderr: $(cat "$TMP/xerr"))"
grep -q -- '--unset-metadata gc.execution_routed_to' "$TMP/xerr" \
  && ok "(EXECWARN) …and carries the by-hand repair" \
  || bad "(EXECWARN) no repair spelled out (stderr: $(cat "$TMP/xerr"))"
grep -q 'takeaway set on' "$TMP/xout" \
  && ok "(EXECWARN) …and the release still stands, reported as set" \
  || bad "(EXECWARN) the release was not reported despite the harmless stamp (stdout: $(cat "$TMP/xout"))"
grep -q -- '--set-metadata gc.takeaway=actionable — routed to the pool' "$TMP/updates" \
  && ok "(EXECWARN) …the headline write is kept" \
  || bad "(EXECWARN) the headline write was lost: $(cat "$TMP/updates")"

# (EXECHELD) a first reaction's held exit: the bead carries placement=pending, the
# release gives it no route, and the store will not take the clear. The stamp is
# then all that places the bead, so gc-helm.sh unplaced would not list it, and the
# release fails rather than report a hold the queue cannot see. The headline and
# the release are kept, so the by-hand repair finishes it.
: > "$TMP/updates"; printf '%s' "$STAMP" > "$TMP/exec"; : > "$TMP/settled"; : > "$TMP/routed"
printf 'pending' > "$TMP/placement"; : > "$TMP/parent"
XHRC=0
FAKE_EXEC_DROP=1 sh "$SCRIPT" takeaway A-PARKED "held for placement" --by proactive --release --no-wait \
  >"$TMP/xout" 2>"$TMP/xerr" || XHRC=$?
eq "$XHRC" "4" "(EXECHELD) a pour stamp left on a bead held for placement fails the release"
grep -q "A-PARKED is held for placement but still carries gc.execution_routed_to='$STAMP'" "$TMP/xerr" \
  && ok "(EXECHELD) …and the failure names the hold and the stamp left standing" \
  || bad "(EXECHELD) the failure does not name the hold and the stamp (stderr: $(cat "$TMP/xerr"))"
grep -q 'gc-helm.sh unplaced does not list A-PARKED' "$TMP/xerr" \
  && ok "(EXECHELD) …says the placement queue cannot see the bead" \
  || bad "(EXECHELD) the failure does not say what the stamp hides (stderr: $(cat "$TMP/xerr"))"
grep -q -- '--unset-metadata gc.execution_routed_to' "$TMP/xerr" \
  && ok "(EXECHELD) …and carries the by-hand repair" \
  || bad "(EXECHELD) no repair spelled out (stderr: $(cat "$TMP/xerr"))"
grep -q 'takeaway set on' "$TMP/xout" \
  && bad "(EXECHELD) a failed release still printed its success line (stdout: $(cat "$TMP/xout"))" \
  || ok "(EXECHELD) …and prints no success line"
grep -q -- '--set-metadata gc.takeaway=held for placement' "$TMP/updates" \
  && ok "(EXECHELD) …the headline write is kept" \
  || bad "(EXECHELD) the headline write was lost: $(cat "$TMP/updates")"

# (EXECHELDFIX) the same held bead, its clear dropped only from the multi-pair
# write: the lone repair carries it, so the queue lists the bead and the release
# exits 0.
: > "$TMP/updates"; printf '%s' "$STAMP" > "$TMP/exec"; : > "$TMP/settled"; : > "$TMP/routed"
printf 'pending' > "$TMP/placement"; : > "$TMP/parent"
XHFRC=0
FAKE_EXEC_DROP=multi sh "$SCRIPT" takeaway A-PARKED "held for placement" --by proactive --release --no-wait \
  >/dev/null 2>"$TMP/xerr" || XHFRC=$?
eq "$XHFRC" "0" "(EXECHELDFIX) a held bead whose stamp the repair clears exits 0"
grep -q 'execution-stamp repair landed' "$TMP/xerr" \
  && ok "(EXECHELDFIX) …and the repair says so" \
  || bad "(EXECHELDFIX) the repair did not report landing (stderr: $(cat "$TMP/xerr"))"
eq "$(cat "$TMP/exec")" "" "(EXECHELDFIX) …the bead ends with the pour stamp cleared"

# (EXECPLACED) the marker outlived a placement: the bead has a parent, which
# places it whatever its stamp says. The stamp hides nothing from the queue, so a
# clear that will not land warns, as it does on any other bead.
: > "$TMP/updates"; printf '%s' "$STAMP" > "$TMP/exec"; : > "$TMP/settled"; : > "$TMP/routed"
printf 'pending' > "$TMP/placement"; printf 'tk-epic' > "$TMP/parent"
XPRC=0
FAKE_EXEC_DROP=1 sh "$SCRIPT" takeaway A-PARKED "placed under its epic" --by proactive --release --no-wait \
  >"$TMP/xout" 2>"$TMP/xerr" || XPRC=$?
eq "$XPRC" "0" "(EXECPLACED) a stamp on a bead its parent places does not fail the release"
grep -q 'A-PARKED is not held for placement' "$TMP/xerr" \
  && ok "(EXECPLACED) …and the warning says the bead is not held" \
  || bad "(EXECPLACED) the warning does not say why the stamp hides nothing (stderr: $(cat "$TMP/xerr"))"
grep -q 'takeaway set on' "$TMP/xout" \
  && ok "(EXECPLACED) …and the release stands" \
  || bad "(EXECPLACED) the release was not reported (stdout: $(cat "$TMP/xout"))"
: > "$TMP/exec"; : > "$TMP/placement"; : > "$TMP/parent"

# ── takeaway --release: the executor-identity read-back ───────────────────────
# The unassign takes the departing executor's identity with it, so the release
# clears gc.session_name and gc.session_id via --unset-metadata. Both have
# readers: a surviving gc.session_name is the residue doctor/executor-identity-
# residue reports on the next route, and a surviving gc.session_id lets orphan
# recovery resolve a dead owner for a bead nobody holds. So each is read back, a
# lone unset retried, and a persistent miss is a verb failure on any bead, the way
# the route is, where the pour stamp fails the verb only on a bead held for
# placement. orphan-dispose.sh
# verifies the same pair after its own release. Covered:
#   (SNAMEOK/SIDOK)  a clear that reads back empty is verified once, no repair
#   (SNAMEFIX/SIDFIX)  a clear dropped from the multi-pair write is retried
#   (SNAMEDEAD/SIDDEAD)  a clear that will not land is a verb failure, writes kept
SNAME="gc-toolkit__polecat-hq-gone"
SID="hq-gone"

# (SNAMEOK/SIDOK) both pins clear: the release's own unset is the only write for
# each, and a read-back that finds them gone says nothing.
: > "$TMP/updates"; : > "$TMP/exec"; : > "$TMP/settled"; printf '%s' "$POOL" > "$TMP/routed"
printf '%s' "$SNAME" > "$TMP/sname"; printf '%s' "$SID" > "$TMP/sid"
IORC=0
sh "$SCRIPT" takeaway A-PARKED "released clean" --by proactive --release --route "$POOL" \
  >/dev/null 2>"$TMP/ierr" || IORC=$?
eq "$IORC" "0" "(SNAMEOK) pins that read back cleared exit 0"
eq "$(grep -c -- '--unset-metadata gc.session_name' "$TMP/updates" || true)" "1" \
   "(SNAMEOK) …and gc.session_name is cleared once, with no repair"
eq "$(grep -c -- '--unset-metadata gc.session_id' "$TMP/updates" || true)" "1" \
   "(SIDOK) …and gc.session_id is cleared once, with no repair"
grep -qE 'gc.session_name on|gc.session_id on' "$TMP/ierr" \
  && bad "(SNAMEOK) a landed clear should say nothing (stderr: $(cat "$TMP/ierr"))" \
  || ok "(SNAMEOK) …and says nothing about a read-back"

# (SNAMEFIX) the identity clear dropped from the multi-pair release write, carried
# by the lone repair unset. The pin stood after the first write, so the read-back
# re-issues the clear and the release still exits 0.
: > "$TMP/updates"; : > "$TMP/exec"; : > "$TMP/settled"; printf '%s' "$POOL" > "$TMP/routed"
printf '%s' "$SNAME" > "$TMP/sname"; : > "$TMP/sid"
SFRC=0
FAKE_SNAME_DROP=multi sh "$SCRIPT" takeaway A-PARKED "actionable — routed to the pool" \
  --by proactive --release --route "$POOL" >/dev/null 2>"$TMP/ierr" || SFRC=$?
eq "$(grep -c -- '--unset-metadata gc.session_name' "$TMP/updates" || true)" "2" \
   "(SNAMEFIX) a clear that did not land is re-issued"
grep -q "gc.session_name on A-PARKED read back as '$SNAME'" "$TMP/ierr" \
  && ok "(SNAMEFIX) …and the miss is reported with the pin that stood" \
  || bad "(SNAMEFIX) the dropped clear was silent (stderr: $(cat "$TMP/ierr"))"
grep -q 'session-name repair landed' "$TMP/ierr" \
  && ok "(SNAMEFIX) …and the repair that fixed it says so" \
  || bad "(SNAMEFIX) the repair did not report landing (stderr: $(cat "$TMP/ierr"))"
eq "$SFRC" "0" "(SNAMEFIX) …and a repaired pin is not a verb failure"
eq "$(cat "$TMP/sname")" "" "(SNAMEFIX) …the bead ends with the identity cleared"

# (SNAMEDEAD) the store that will not take the clear at all. The bead is released,
# so a zero exit would report a park still carrying the executor identity this
# release exists to remove — the next route reproduces the residue. So the
# persistent miss is a verb failure, with its writes kept and named.
: > "$TMP/updates"; : > "$TMP/exec"; : > "$TMP/settled"; printf '%s' "$POOL" > "$TMP/routed"
printf '%s' "$SNAME" > "$TMP/sname"; : > "$TMP/sid"
SDRC=0
FAKE_SNAME_DROP=1 sh "$SCRIPT" takeaway A-PARKED "actionable — routed to the pool" \
  --by proactive --release --route "$POOL" >"$TMP/iout" 2>"$TMP/ierr" || SDRC=$?
eq "$SDRC" "4" "(SNAMEDEAD) an identity pin that will not clear is a verb runtime failure"
grep -q "still carries gc.session_name='$SNAME'" "$TMP/ierr" \
  && ok "(SNAMEDEAD) …and the message names the pin left standing" \
  || bad "(SNAMEDEAD) the persistent miss does not name the stale pin (stderr: $(cat "$TMP/ierr"))"
grep -q -- '--unset-metadata gc.session_name' "$TMP/ierr" \
  && ok "(SNAMEDEAD) …and carries the by-hand repair" \
  || bad "(SNAMEDEAD) no repair spelled out (stderr: $(cat "$TMP/ierr"))"
grep -q 'takeaway set on' "$TMP/iout" \
  && bad "(SNAMEDEAD) the verb reported success on a bead still carrying the identity" \
  || ok "(SNAMEDEAD) …and does not report the takeaway as set"
IDLINE="$(grep -E "^bd update A-PARKED( |\$)" "$TMP/updates" | head -n1)"
case "$IDLINE" in
  *"--status=open"*"--assignee="*) ok "(SNAMEDEAD) …the release it already wrote is kept, not rolled back" ;;
  *) bad "(SNAMEDEAD) the release write was lost: ${IDLINE:-<none>}" ;;
esac
: > "$TMP/sname"

# (SIDFIX) the same silent drop on gc.session_id: the multi-pair write drops it,
# the lone repair unset carries it, and the release still exits 0.
: > "$TMP/updates"; : > "$TMP/exec"; : > "$TMP/settled"; printf '%s' "$POOL" > "$TMP/routed"
: > "$TMP/sname"; printf '%s' "$SID" > "$TMP/sid"
DFRC=0
FAKE_SID_DROP=multi sh "$SCRIPT" takeaway A-PARKED "actionable — routed to the pool" \
  --by proactive --release --route "$POOL" >/dev/null 2>"$TMP/ierr" || DFRC=$?
eq "$(grep -c -- '--unset-metadata gc.session_id' "$TMP/updates" || true)" "2" \
   "(SIDFIX) a clear that did not land is re-issued"
grep -q "gc.session_id on A-PARKED read back as '$SID'" "$TMP/ierr" \
  && ok "(SIDFIX) …and the miss is reported with the pin that stood" \
  || bad "(SIDFIX) the dropped clear was silent (stderr: $(cat "$TMP/ierr"))"
grep -q 'session-id repair landed' "$TMP/ierr" \
  && ok "(SIDFIX) …and the repair that fixed it says so" \
  || bad "(SIDFIX) the repair did not report landing (stderr: $(cat "$TMP/ierr"))"
eq "$DFRC" "0" "(SIDFIX) …and a repaired pin is not a verb failure"
eq "$(cat "$TMP/sid")" "" "(SIDFIX) …the bead ends with the pin cleared"

# (SIDDEAD) the store that will not take the gc.session_id clear at all. A stale
# pin lets orphan recovery resolve a dead owner for a released bead, so the miss
# is a verb failure, with its writes kept and named.
: > "$TMP/updates"; : > "$TMP/exec"; : > "$TMP/settled"; printf '%s' "$POOL" > "$TMP/routed"
: > "$TMP/sname"; printf '%s' "$SID" > "$TMP/sid"
DDRC=0
FAKE_SID_DROP=1 sh "$SCRIPT" takeaway A-PARKED "actionable — routed to the pool" \
  --by proactive --release --route "$POOL" >"$TMP/iout" 2>"$TMP/ierr" || DDRC=$?
eq "$DDRC" "4" "(SIDDEAD) an orphan-recovery pin that will not clear is a verb runtime failure"
grep -q "still carries gc.session_id='$SID'" "$TMP/ierr" \
  && ok "(SIDDEAD) …and the message names the pin left standing" \
  || bad "(SIDDEAD) the persistent miss does not name the stale pin (stderr: $(cat "$TMP/ierr"))"
grep -q -- '--unset-metadata gc.session_id' "$TMP/ierr" \
  && ok "(SIDDEAD) …and carries the by-hand repair" \
  || bad "(SIDDEAD) no repair spelled out (stderr: $(cat "$TMP/ierr"))"
grep -q 'takeaway set on' "$TMP/iout" \
  && bad "(SIDDEAD) the verb reported success on a bead still carrying the pin" \
  || ok "(SIDDEAD) …and does not report the takeaway as set"
: > "$TMP/sid"

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
grep -q "gc.routed_to=$POOL" <<< "$(line_for CLOSED-A-FOLD)" \
  && bad "(FOLDROUTE) a disposed bead was handed to a pool" \
  || ok "(FOLDROUTE) …and the pool route is never stamped"
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
grep -q 'w-child' "$TMP/derr" \
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
grep -q -- "--set-metadata gc.routed_to=$POOL" "$TMP/updates" \
  && ok "(GATED) …and the route is written" \
  || bad "(GATED) the route was lost: $(cat "$TMP/updates")"
grep -q 'could not read the blockers' "$TMP/derr" \
  && bad "(GATED) a probe that answered still warned it had not (stderr: $(cat "$TMP/derr"))" \
  || ok "(GATED) …and a probe that answered says nothing: the warning stays a signal"

# (DELEGDONE) a closed blocker is history, not a wait.
: > "$TMP/updates"; printf '%s' "$POOL" > "$TMP/routed"
CRC2=0
sh "$SCRIPT" takeaway A-DONEBLK "actionable — nothing outstanding" \
   --release --route "$POOL" >/dev/null 2>"$TMP/derr" || CRC2=$?
eq "$CRC2" "0" "(DELEGDONE) a closed blocker does not refuse the route"

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
grep -q -- "--set-metadata gc.routed_to=$POOL" "$TMP/updates" \
  && ok "(DELEGPROBE) …and the route is written" \
  || bad "(DELEGPROBE) the route was lost: $(cat "$TMP/updates")"
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
grep -q -- "--set-metadata gc.routed_to=$POOL" "$TMP/updates" \
  && ok "(DELEGJUNK) …and the route is written" \
  || bad "(DELEGJUNK) the route was lost: $(cat "$TMP/updates")"
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
# assignees fixture, so a row there models an assignee that landed and its
# absence models one that did not. Covered:
#   (TOAGENT)      the assignee replaces the empty clear in the one release
#                  write, and the route beside it stays empty
#   (TOAGENTOK)    an assignee that reads back is written once, exit 0, and
#                  the success line names the agent
#   (TOAGENTREL)   --assign without --release is refused
#   (TOAGENTBOTH)  --assign beside --route is refused before any write
#   (TOAGENTDEAD)  an assignee that will not land is re-written once, then
#                  fails the verb with the repair spelled out
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
eq "$ARC" "0" "(TOAGENTOK) an assignee that reads back exits 0"
eq "$(grep -cE "^bd update A-PARKED( |\$)" "$TMP/updates" || true)" "1" \
   "(TOAGENTOK) …and is written once, with no repair"
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

# A-UNASSIGNED has no assignees row, so its assignee reads back empty however
# often it is written: the store that will not take it.
: > "$TMP/updates"
DRC3=0
sh "$SCRIPT" takeaway A-UNASSIGNED "dropped" --release --assign "$AGENT" --no-wait \
   >"$TMP/aout" 2>"$TMP/aerr" || DRC3=$?
eq "$(grep -c -- "--assignee=$AGENT" "$TMP/updates" || true)" "2" \
   "(TOAGENTDEAD) an assignee that read back wrong is re-written once"
grep -q "the assignee on A-UNASSIGNED read back as ''" "$TMP/aerr" \
  && ok "(TOAGENTDEAD) …and the miss is reported" \
  || bad "(TOAGENTDEAD) the dropped assignee was silent (stderr: $(cat "$TMP/aerr"))"
eq "$DRC3" "4" "(TOAGENTDEAD) an assignee that will not land is a verb runtime failure"
grep -q 'NOT assigned' "$TMP/aerr" \
  && ok "(TOAGENTDEAD) …and the failure says the bead reaches no agent" \
  || bad "(TOAGENTDEAD) the persistent miss does not name its consequence (stderr: $(cat "$TMP/aerr"))"
grep -q -- "--assignee $AGENT" "$TMP/aerr" \
  && ok "(TOAGENTDEAD) …with the by-hand repair spelled out" \
  || bad "(TOAGENTDEAD) no repair spelled out (stderr: $(cat "$TMP/aerr"))"
grep -q 'takeaway set on' "$TMP/aout" \
  && bad "(TOAGENTDEAD) the verb reported success on an unassigned bead" \
  || ok "(TOAGENTDEAD) …and success is not reported"

: > "$TMP/updates"; : > "$TMP/deps"
KRC=0
sh "$SCRIPT" takeaway A-BLOCKED "assigned — the fix is mechanik's" \
   --release --assign "$AGENT" --no-wait >/dev/null 2>"$TMP/aerr" || KRC=$?
eq "$KRC" "2" "(TOAGENTBLK) an open blocker that is no human gate refuses a bare --assign"
eq "$(wc -l < "$TMP/updates" | tr -d ' ')" "0" "(TOAGENTBLK) …before any write"
grep -q 'w-child' "$TMP/aerr" \
  && ok "(TOAGENTBLK) …naming the blocker the work is on" \
  || bad "(TOAGENTBLK) the blocker is unnamed (stderr: $(cat "$TMP/aerr"))"
grep -q -- '--then-assign' "$TMP/aerr" \
  && ok "(TOAGENTBLK) …and the blocked exit that names the wait" \
  || bad "(TOAGENTBLK) no blocked-exit re-run named (stderr: $(cat "$TMP/aerr"))"

: > "$TMP/updates"; : > "$TMP/deps"
WRC3=0
sh "$SCRIPT" takeaway A-BLOCKED "held — mechanik edits once the child lands" \
   --release --assign "$AGENT" --waiting-on w-child >/dev/null 2>"$TMP/aerr" || WRC3=$?
eq "$WRC3" "0" "(TOAGENTWAIT) an --assign that names its wait lands"
grep -qE "^bd update A-BLOCKED .*--assignee=$AGENT" "$TMP/updates" \
  && ok "(TOAGENTWAIT) …assigned to the agent" \
  || bad "(TOAGENTWAIT) the assignee was lost: $(cat "$TMP/updates")"
grep -qE '^bd dep add A-BLOCKED w-child -t blocks' "$TMP/deps" \
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
sh "$SCRIPT" takeaway A-PARKED "$T141" --release --waiting-on tk-blk1 >/dev/null 2>&1 || true
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
 {"id":"A-FOLD","status":"closed","assignee":"gc-toolkit__polecat-hq-old","metadata":{"gc.superseded_by":"A-CARRIER","gc.routed_to":"human"}},
 {"id":"root-FOLD","status":"in_progress","assignee":"","metadata":{"gc.kind":"workflow","gc.step_id":"mol-polecat-work","gc.input_convoy_id":"convoy-FOLD","gc.routed_to":"$POOL"}},
 {"id":"F-held","status":"in_progress","assignee":"gc-toolkit__polecat-hq-other","metadata":{"gc.step_ref":"mol-polecat-work.load-context","gc.root_bead_id":"root-FOLD","gc.routed_to":"$POOL","gc.session_affinity":"require"}},
 {"id":"F-work","status":"open","assignee":"gc-toolkit__polecat-hq-gone","metadata":{"gc.step_ref":"mol-polecat-work.workspace-setup","gc.root_bead_id":"root-FOLD","gc.routed_to":"$POOL","gc.session_affinity":"require"}}
]
JSON
printf 'convoy-LIVE|A-LIVE\nconvoy-FOLD|A-FOLD\n' > "$LIVE_CONVOYS"
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
    # beads refuses to clear the assignee of an in_progress bead ANOTHER
    # session holds, and refuses the whole update along with it. Checked
    # before anything is applied, so the refusal is atomic here too: a stub
    # that let the other keys through would hide the loss this split prevents.
    for a in "$@"; do
      case "$a" in
        --assignee|--assignee=*)
          st=$(jq -r --arg i "$id" '.[] | select(.id==$i) | .status // ""' "$LIVE_STORE")
          who=$(jq -r --arg i "$id" '.[] | select(.id==$i) | .assignee // ""' "$LIVE_STORE")
          if [ "$st" = "in_progress" ] && [ -n "$who" ] && [ "$who" != "${GC_SESSION_NAME:-}" ]; then
            printf 'refused %s (held by %s)\n' "$id" "$who" >> "$LIVE_LOG"
            exit 1
          fi ;;
      esac
    done
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
eq "$(field A-FOLD gc.superseded_by)" "A-CARRIER" \
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
unset GC_PROACTIVE_TOOL FAKE_SLING_RC

echo ""
echo "gc-helm takeaway + react (release run end, waiting-on edges, length gate, react no-op exit): $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
