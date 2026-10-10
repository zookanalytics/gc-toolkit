#!/usr/bin/env bash
# Hermetic test for mol-polecat-work's load-context duplicate-dispatch guard.
#
# Two dispatch surfaces can reach one work bead — a mol-polecat-work molecule
# and a direct pool route on the bead itself. When both fire, one worker can
# rebuild a branch the other already carried to a PR or a merge. At
# load-context, before the workspace is touched, this guard refuses to build a
# bead that is unreadable, parked, in flight under a live owner, or already
# finished elsewhere. Status decides first: only an open or in_progress bead
# reaches the owner check.
#
# What it holds:
#   1. DISCRIMINATION — a no-op on work that is genuinely this session's to
#      build: unowned (empty assignee, fresh or rework dispatch), owned by this
#      session, or in_progress under an owner that has since crashed (absent
#      from `gc session list`, so the work is ours to take over).
#   2. FINISHED — quiesces WITHOUT escalation when a foreign assignee holds the
#      bead open (the refinery handoff leaves it open+assigned), when the bead
#      carries a merge_result stamp even with the assignee cleared (a PR/merge
#      already exists for it), or when the bead is closed under any assignee (a
#      merge closes it, and a close that lands between the pour and this claim,
#      such as a duplicate, stamps no merge_result). A finished bead is not a
#      live conflict — its work landed, is landing with the refinery, or was
#      ruled unnecessary, and no human has a decision to make — so the gate
#      holds and drains but files no visit. It reaches a polecat both as a
#      redundant dispatch and as a lease-expiry re-offer of the SAME molecule's
#      own load-context after its work finished. A closed bead's note and hold
#      reason name the close and what the bead records about it, not a
#      duplicate dispatch; a merge_result names the stamp.
#   3. ESCALATED — files a visit, then holds: an in_progress bead under a live
#      foreign owner (two dispatches building at once), an unreadable bead
#      (no liveness answer can clear it), and a parked bead (blocked, deferred,
#      hooked, pinned), whose release does not resume a held molecule. Each
#      situation has its own key.
#   4. FAIL CLOSED — an escalate failure records no release path, so the gate
#      neither holds nor drains. A hold that did not land does not drain. A note
#      the store refuses is reported, and the hold still runs. The step is never
#      left silently claimable or silently parked.
#   5. THE WORK'S TREE — a bead that would otherwise build is checked for a
#      live session working it in its tree, because this workflow never claims
#      its work bead. The gate passes the bead's work_dir and branch to
#      work-tree-holder.sh. Exit 1 (a live holder) and every other non-zero
#      exit (undecided) hold as a duplicate dispatch and file the visit; the
#      finding rides into the note, the hold reason and the visit. A bead
#      refused on its status or assignee never reaches the check.
#
# EXECUTES the real snippet extracted verbatim from the formula against fake
# `gc` and stub scripts, so the test cannot drift from the shipped instruction.
# Section 8 runs it with the real work-tree-holder.sh against a real repository
# laid out like pool slots; everything else needs no live city, Dolt, network,
# or worktrees.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-polecat-work.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-load-context-duplicate-dispatch-gate-test.XXXXXX")"
# git lists a worktree by its resolved path, and section 8 compares the trees it
# reports with paths built here, so the root is resolved.
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3" "got '$1' want '$2'"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "'$2' not in '$1'" ;; esac; }
no()  { case "$1" in *"$2"*) bad "$3" "'$2' unexpectedly in '$1'" ;; *) ok "$3" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }
[ -f "$TOML" ] || { echo "formula not found: $TOML" >&2; exit 1; }

# --- Extract the REAL snippet from the formula. -------------------------------
# The flag-flip pulls the lines between the markers (exclusive). If the markers
# are removed or renamed — the exact thing a wholesale reconciliation against
# base does — extraction yields nothing and the checks below fail loudly.
extract() {
  awk -v m="$1" '
    $0 ~ ("# >>> " m "$") {f=1; next}
    $0 ~ ("# <<< " m "$") {f=0}
    f' "$TOML"
}

GATE="$(extract load-context-duplicate-dispatch-hold)"

[ -n "$GATE" ] \
  && ok "gate extracted between load-context-duplicate-dispatch-hold markers" \
  || bad "gate extraction EMPTY — markers missing from $TOML"

# Two regions sharing one marker name would concatenate into one extraction and
# double every assertion below; pin the opener to a single occurrence.
eq "$(grep -c '^# >>> load-context-duplicate-dispatch-hold$' "$TOML")" "1" \
   "exactly one load-context-duplicate-dispatch-hold region"

# TOML `"""` strings eat a trailing backslash (line-ending escape), silently
# joining lines. The snippet is written backslash-free; assert it, because
# reintroducing a continuation is an easy and invisible edit.
case "$GATE" in
  *\\*) bad "snippet contains a backslash — TOML line-ending escapes will mangle it" ;;
  *)    ok  "snippet is backslash-free (safe inside a TOML triple-quoted string)" ;;
esac

printf '%s\n' "$GATE" > "$TMP/gate.sh"
bash -n "$TMP/gate.sh" \
  && ok "extracted gate is syntactically valid bash" \
  || bad "extracted gate failed bash -n"

# --- Fakes. -------------------------------------------------------------------
# gc : `bd update` (the refusal note) and `runtime drain-ack` record to
#      $FAKE_LOG; `session list` returns $FAKE_SESSIONS (the liveness probe) and
#      `bd list` returns $FAKE_BEADS (section 8's claims). Both reads are
#      intentionally NOT logged, so the verb trace reads the same whether or not
#      a check consulted them. `bd update` exits $FAKE_UPDATE_RC, so a refused
#      note can be driven. The block reads the work bead from $WORK_BEAD_JSON
#      (set by the step), so no `bd show` is needed.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "runtime drain-ack") printf 'DRAIN\n' >> "$FAKE_LOG"; exit 0 ;;
  "bd update")         shift 2; printf 'UPDATE\n' >> "$FAKE_LOG"; printf '%s\n' "$*" >> "${FAKE_UPDATE:-/dev/null}"; exit "${FAKE_UPDATE_RC:-0}" ;;
  "session list")      printf '%s' "${FAKE_SESSIONS:-}"; exit 0 ;;
  "bd list")           printf '%s' "${FAKE_BEADS:-[]}"; exit 0 ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH"

# molecule-hold.sh, escalate.sh and work-tree-holder.sh resolved out of
# $GC_PACK_DIR exactly as the gate resolves them. The first two record their
# verb into the ordered trace and their argv where the reason/message
# assertions can read it, returning a code the assertions control. The tree
# check records its argv apart from the trace, so the trace of every other arm
# reads the same with it, and answers $FAKE_TREE_OUT with exit $FAKE_TREE_RC.
mkdir -p "$TMP/pack/assets/scripts"
cat > "$TMP/pack/assets/scripts/molecule-hold.sh" <<'HOLD'
#!/usr/bin/env bash
printf 'HOLD\n' >> "$FAKE_LOG"
printf '%s\n' "$*" >> "${FAKE_HOLD:-/dev/null}"
exit "${FAKE_HOLD_RC:-0}"
HOLD
cat > "$TMP/pack/assets/scripts/escalate.sh" <<'ESC'
#!/usr/bin/env bash
printf 'ESCALATE\n' >> "$FAKE_LOG"
printf '%s\n' "$*" >> "${FAKE_ESC:-/dev/null}"
exit "${FAKE_ESC_RC:-0}"
ESC
cat > "$TMP/pack/assets/scripts/work-tree-holder.sh" <<'TREE'
#!/usr/bin/env bash
for a in "$@"; do printf '<%s>' "$a"; done >> "${FAKE_TREE_ARGS:-/dev/null}"
printf '\n' >> "${FAKE_TREE_ARGS:-/dev/null}"
[ -z "${FAKE_TREE_OUT:-}" ] || printf '%s\n' "$FAKE_TREE_OUT"
exit "${FAKE_TREE_RC:-0}"
TREE
chmod +x "$TMP/pack/assets/scripts/molecule-hold.sh" \
         "$TMP/pack/assets/scripts/escalate.sh" \
         "$TMP/pack/assets/scripts/work-tree-holder.sh"
export GC_PACK_DIR="$TMP/pack" GC_RIG_ROOT="" GC_CITY_PATH="" GC_DIR=""

# This session's four identity forms. A work bead whose assignee is any of them
# is "owned by you" and must be a no-op; anything else is a foreign owner.
SELF_NAME="lx-me-pool"; SELF_ID="sess-me"; SELF_AGENT="rig/rig.polecat"; SELF_ALIAS="me-alias"
REFINERY="gc-toolkit/gc-toolkit.refinery"
SESS_EMPTY='{"sessions":[]}'
# A session list that answers, naming live sessions none of the fixtures' owners
# match: the probe returns 0 for any owner not listed here.
SESS_REAL='{"sessions":[{"session_name":"lx-busy","id":"sess-busy","alias":"rig/rig.polecat-busy"}]}'

# run <work-bead-json> -> prints "<rc>|<ordered verb log>"
#   FAKE_SESSIONS controls the liveness probe; FAKE_TREE_RC/OUT the tree check;
#   FAKE_*_RC control each stub's exit; FAKE_UPDATE/HOLD/ESC and
#   $TMP/tree-args capture argv; $TMP/out holds the gate's output. The gate runs
#   from $RUN_DIR, a directory outside any repository unless a case sets one, so
#   the pack lookup's `git rev-parse --show-toplevel` candidate finds nothing.
run() {
  : > "$TMP/log"; : > "$TMP/update"; : > "$TMP/hold"; : > "$TMP/esc"; : > "$TMP/tree-args"
  local rc=0
  ( cd "${RUN_DIR:-$TMP}" || exit 97
    WORK_BEAD_ID=tk-work \
    WORK_BEAD_JSON="$1" \
    CLAIMED_STEP_BEAD_ID=st-load \
    GC_SESSION_NAME="$SELF_NAME" GC_SESSION_ID="$SELF_ID" GC_AGENT="$SELF_AGENT" GC_ALIAS="$SELF_ALIAS" \
    GC_PACK_DIR="$GC_PACK_DIR" GC_RIG_ROOT="$GC_RIG_ROOT" GC_DIR="$GC_DIR" \
    FAKE_LOG="$TMP/log" FAKE_UPDATE="$TMP/update" FAKE_HOLD="$TMP/hold" FAKE_ESC="$TMP/esc" \
    FAKE_SESSIONS="${FAKE_SESSIONS-$SESS_EMPTY}" FAKE_BEADS="${FAKE_BEADS:-[]}" \
    FAKE_TREE_ARGS="$TMP/tree-args" FAKE_TREE_RC="${FAKE_TREE_RC:-0}" FAKE_TREE_OUT="${FAKE_TREE_OUT:-}" \
    FAKE_HOLD_RC="${FAKE_HOLD_RC:-0}" FAKE_ESC_RC="${FAKE_ESC_RC:-0}" FAKE_UPDATE_RC="${FAKE_UPDATE_RC:-0}" \
      bash "$TMP/gate.sh" ) > "$TMP/out" 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$(tr '\n' ';' < "$TMP/log")"
}

# --- 1. Discrimination: no-op on work that is this session's to build. --------

eq "$(run '[{"status":"open","assignee":"","metadata":{}}]')" \
   "0|" \
   "fresh work (open, unassigned): no-op, load-context proceeds"

eq "$(run '[{"status":"open","metadata":{}}]')" \
   "0|" \
   "open with assignee absent entirely: treated as unowned, no-op"

eq "$(run "[{\"status\":\"in_progress\",\"assignee\":\"$SELF_NAME\",\"metadata\":{}}]")" \
   "0|" \
   "owned by this session (in_progress): no-op — you are resuming your own claim"

eq "$(run '[{"status":"open","assignee":"","metadata":{"branch":"polecat/tk-work"}}]')" \
   "0|" \
   "rework child (open, unassigned, branch set, no merge_result): no-op"

# A foreign owner on an in_progress bead is a no-op ONLY when that owner has
# crashed — absent from the session list, the work is ours to take over.
eq "$(FAKE_SESSIONS="$SESS_EMPTY" run '[{"status":"in_progress","assignee":"lx-dead","metadata":{}}]')" \
   "0|" \
   "in_progress under a CRASHED foreign owner: no-op — take over abandoned work"

# --- 2. Finished elsewhere: a completed hand-off or a merge. ------------------
# A refinery handoff leaves the work bead open, assigned to the refinery, route
# cleared. `open` is neither in_progress nor unknown, so the in-flight liveness
# arm does not apply; a dedicated arm stops it rebuilding finished work. The
# work is with the refinery and no human has a decision to make, so this arm
# holds and drains but files NO visit — a human gate here is what stranded
# finished work (the SAME-molecule lease-expiry re-offer this fixes).

eq "$(run "[{\"status\":\"open\",\"assignee\":\"$REFINERY\",\"metadata\":{}}]")" \
   "1|UPDATE;HOLD;DRAIN;" \
   "completed handoff (open under the refinery): quiesces silently, drains, exits 1 — no escalation"

eq "$(run "[{\"status\":\"closed\",\"assignee\":\"$REFINERY\",\"metadata\":{}}]")" \
   "1|UPDATE;HOLD;DRAIN;" \
   "merged (closed under the refinery): quiesces silently, drains, exits 1 — no escalation"

# A merge_result stamp outlives a cleared assignee (an anchor whose child rework
# is in flight reads open + unassigned + merge_result). The unowned arm would
# otherwise sail its live PR through.
eq "$(run '[{"status":"open","assignee":"","metadata":{"merge_result":"pull_request"}}]')" \
   "1|UPDATE;HOLD;DRAIN;" \
   "merge_result set with assignee cleared: quiesces silently — a PR already exists for the bead"

# A closed bead is finished whoever holds it, including the shape a close
# between the pour and this claim leaves: an empty assignee and no
# merge_result. The closed rework child carries the branch it would rebuild.
eq "$(run '[{"status":"closed","assignee":"","metadata":{}}]')" \
   "1|UPDATE;HOLD;DRAIN;" \
   "closed and unowned, no merge_result: quiesces silently, drains, exits 1 — no escalation"

eq "$(run '[{"status":"closed","metadata":{}}]')" \
   "1|UPDATE;HOLD;DRAIN;" \
   "closed with assignee absent entirely: quiesces silently"

eq "$(run '[{"status":"closed","assignee":"","metadata":{"branch":"integration/feature","gc.superseded_by":"tk-twin"}}]')" \
   "1|UPDATE;HOLD;DRAIN;" \
   "closed rework child superseded by a twin (branch set, no merge_result): quiesces silently"

for self in "$SELF_NAME" "$SELF_ID" "$SELF_AGENT" "$SELF_ALIAS"; do
  eq "$(run "[{\"status\":\"closed\",\"assignee\":\"$self\",\"metadata\":{}}]")" \
     "1|UPDATE;HOLD;DRAIN;" \
     "closed under this session's own identity '$self': quiesces silently"
done

# A closed bead is decided by its status before any owner or liveness check, so
# a closed bead under a foreign owner the session list reports live is finished,
# not a live conflict, and files no visit.
eq "$(FAKE_SESSIONS='{"sessions":[{"session_name":"lx-other"}]}' \
      run '[{"status":"closed","assignee":"lx-other","metadata":{}}]')" \
   "1|UPDATE;HOLD;DRAIN;" \
   "closed under a LIVE foreign owner: finished, quiesces silently — the liveness probe does not apply"

eq "$(run '[{"status":"closed","metadata":{"merge_result":"merged"}}]')" \
   "1|UPDATE;HOLD;DRAIN;" \
   "closed with a merge_result: quiesces silently"

# --- 3. Escalated: a human must look before anything is built. ----------------

eq "$(FAKE_SESSIONS='{"sessions":[{"session_name":"lx-other"}]}' \
      run '[{"status":"in_progress","assignee":"lx-other","metadata":{}}]')" \
   "1|UPDATE;ESCALATE;HOLD;DRAIN;" \
   "in_progress under a LIVE foreign owner: holds, escalates, drains, exits 1"

# A liveness probe that answers nothing cannot disprove a live owner, so the
# gate assumes one.
eq "$(FAKE_SESSIONS='' run '[{"status":"in_progress","assignee":"lx-other","metadata":{}}]')" \
   "1|UPDATE;ESCALATE;HOLD;DRAIN;" \
   "in_progress under a foreign owner the liveness probe cannot answer for: assumes live, escalates"

# A live owner is a conflict even when a merge_result says a PR exists: the
# in-flight check runs before the stamp is read.
eq "$(FAKE_SESSIONS='{"sessions":[{"session_name":"lx-other"}]}' \
      run '[{"status":"in_progress","assignee":"lx-other","metadata":{"merge_result":"pull_request"}}]')" \
   "1|UPDATE;ESCALATE;HOLD;DRAIN;" \
   "in_progress under a LIVE foreign owner with a merge_result: still the live conflict, escalates"

# An unreadable bead proves nothing, whatever the session list says. Every shape
# a failed or empty `gc bd show` can leave in WORK_BEAD_JSON is held for a human,
# both when the liveness probe answers nothing and when it answers with sessions
# that match no owner.
for shape in '' '[]' 'null' '{"error":"not found"}' '[{}]' 'not json'; do
  for sessions in "$SESS_REAL" "$SESS_EMPTY" ''; do
    eq "$(FAKE_SESSIONS="$sessions" run "$shape")" \
       "1|UPDATE;ESCALATE;HOLD;DRAIN;" \
       "unreadable bead <$shape> with session list <${sessions:-no answer}>: fails closed, escalates, holds"
  done
done

# A parked bead waits on whoever parked it. It is not built under any assignee,
# and its release does not resume a held molecule, so a visit says so.
for st in blocked deferred hooked pinned; do
  eq "$(FAKE_SESSIONS="$SESS_REAL" run "[{\"status\":\"$st\",\"assignee\":\"\",\"metadata\":{}}]")" \
     "1|UPDATE;ESCALATE;HOLD;DRAIN;" \
     "parked ($st) and unowned: not built, escalates, holds"
done
eq "$(run '[{"status":"deferred","metadata":{"branch":"polecat/tk-work"}}]')" \
   "1|UPDATE;ESCALATE;HOLD;DRAIN;" \
   "parked rework child (deferred, branch set, assignee absent): not built, escalates"
eq "$(run "[{\"status\":\"blocked\",\"assignee\":\"$SELF_AGENT\",\"metadata\":{}}]")" \
   "1|UPDATE;ESCALATE;HOLD;DRAIN;" \
   "parked (blocked) under this session's own agent address: not built, escalates"
eq "$(run "[{\"status\":\"deferred\",\"assignee\":\"$REFINERY\",\"metadata\":{}}]")" \
   "1|UPDATE;ESCALATE;HOLD;DRAIN;" \
   "parked (deferred) under a foreign assignee: escalates"

# A merge_result outranks a park: the PR is with the refinery, so it is finished.
eq "$(run '[{"status":"blocked","assignee":"","metadata":{"merge_result":"pull_request"}}]')" \
   "1|UPDATE;HOLD;DRAIN;" \
   "parked (blocked) with a merge_result: finished, quiesces silently"

# --- 4. Messages name the true reason so a reader can act. --------------------

# FINISHED (handoff): the refusal note and the hold reason name the completed
# hand-off, the note records the silent quiesce, and NO escalation is filed.
run "[{\"status\":\"open\",\"assignee\":\"$REFINERY\",\"metadata\":{}}]" >/dev/null
has "$(cat "$TMP/update")" 'already handed off' "handoff: note names the completed hand-off"
has "$(cat "$TMP/update")" 'quiesced without escalation' "handoff: note records the silent quiesce"
has "$(cat "$TMP/hold")"   'mol-polecat-work.load-context' "hold names THIS step"
has "$(cat "$TMP/hold")"   'already handed off' "hold reason names the completed hand-off"
has "$(cat "$TMP/hold")"   'duplicate dispatch (work finished)' "handoff: hold reason reads as a duplicate dispatch of finished work"
eq  "$(cat "$TMP/esc")"    '' "handoff: no escalation filed — a finished bead needs no human"

# FINISHED (merge_result): the hold reason names the stamp; no escalation.
run '[{"status":"open","assignee":"","metadata":{"merge_result":"pull_request"}}]' >/dev/null
has "$(cat "$TMP/hold")" 'merge_result=pull_request' "merge_result: hold reason names the stamp"
eq  "$(cat "$TMP/esc")"  '' "merge_result: no escalation filed"

# FINISHED (closed): the note and the hold reason name the close, under a label
# of their own rather than a duplicate dispatch; no escalation.
run '[{"status":"closed","assignee":"","metadata":{}}]' >/dev/null
has "$(cat "$TMP/update")" 'already closed' "closed: note names the close"
has "$(cat "$TMP/update")" 'Closed before claim; quiesced without escalation' "closed: note records the close label and the silent quiesce"
no  "$(cat "$TMP/update")" 'Duplicate dispatch' "closed: note does not call the close a duplicate dispatch"
has "$(cat "$TMP/hold")"   'closed before claim: tk-work already closed' "closed: hold reason names the close"
no  "$(cat "$TMP/hold")"   'duplicate dispatch' "closed: hold reason does not call the close a duplicate dispatch"
eq  "$(cat "$TMP/esc")"    '' "closed: no escalation filed — a closed bead needs no human"

# The close's provenance rides into the note and the hold reason, so a reader
# can tell a duplicate close from a merge or a no-work close without opening
# the bead. A long close reason is cut to 200 characters on one line.
run '[{"status":"closed","assignee":"","close_reason":"duplicate of tk-twin:\n  landed there first","metadata":{"branch":"integration/feature","gc.superseded_by":"tk-twin","gc.outcome":"duplicate"}}]' >/dev/null
has "$(cat "$TMP/update")" 'superseded by tk-twin' "closed: note names the superseding bead"
has "$(cat "$TMP/hold")"   'superseded by tk-twin' "closed: hold reason names the superseding bead"
has "$(cat "$TMP/hold")"   'outcome duplicate' "closed: hold reason names gc.outcome"
has "$(cat "$TMP/hold")"   'close reason: duplicate of tk-twin: landed there first' "closed: hold reason carries the close reason on one line"
LONG_REASON="$(printf 'r%.0s' $(seq 1 260))"
run "[{\"status\":\"closed\",\"close_reason\":\"$LONG_REASON\",\"metadata\":{}}]" >/dev/null
has "$(cat "$TMP/hold")" "close reason: $(printf 'r%.0s' $(seq 1 200)));" "closed: a long close reason is cut to 200 characters"
no  "$(cat "$TMP/hold")" "$(printf 'r%.0s' $(seq 1 201))" "closed: nothing past the 200th character survives"

# FINISHED (closed with a merge_result): the stamp is the reason, under the
# finished-dispatch label, not the bare close.
run '[{"status":"closed","metadata":{"merge_result":"merged"}}]' >/dev/null
has "$(cat "$TMP/hold")" 'merge_result=merged' "closed + merge_result: hold reason names the stamp"
no  "$(cat "$TMP/hold")" 'closed before claim' "closed + merge_result: the stamp's reason wins over the bare close"
eq  "$(cat "$TMP/esc")"  '' "closed + merge_result: no escalation filed"

# LIVE conflict: the escalation names the live owner and uses the
# duplicate-dispatch key; the hold reason names the live owner.
FAKE_SESSIONS='{"sessions":[{"session_name":"lx-other"}]}' \
  run '[{"status":"in_progress","assignee":"lx-other","metadata":{}}]' >/dev/null
has "$(cat "$TMP/esc")"  'under live lx-other' "in-flight: escalation names the live owner"
has "$(cat "$TMP/esc")"  'polecat-duplicate-dispatch' "in-flight: escalation uses the duplicate-dispatch key"
has "$(cat "$TMP/hold")" 'under live lx-other' "in-flight: hold reason names the live owner"

# UNREADABLE: its own key, and the messages say the bead could not be read
# rather than naming a duplicate dispatch.
FAKE_SESSIONS="$SESS_REAL" run '' >/dev/null
has "$(cat "$TMP/esc")"  'polecat-unreadable-work' "unreadable: escalation uses its own key"
has "$(cat "$TMP/esc")"  'Could not read work bead tk-work' "unreadable: escalation says the bead could not be read"
no  "$(cat "$TMP/esc")"  'Duplicate dispatch' "unreadable: escalation does not claim a duplicate dispatch"
has "$(cat "$TMP/hold")" 'unreadable work bead: tk-work unreadable' "unreadable: hold reason names it"

# PARKED: its own key, and the escalation names the status and says a release
# does not resume the held molecule.
run '[{"status":"deferred","assignee":"","metadata":{}}]' >/dev/null
has "$(cat "$TMP/esc")"    'polecat-parked-work' "parked: escalation uses its own key"
has "$(cat "$TMP/esc")"    'tk-work is deferred' "parked: escalation names the status"
has "$(cat "$TMP/esc")"    'does not resume the molecule' "parked: escalation says a release does not resume the held molecule"
has "$(cat "$TMP/update")" 'Parked work bead; held for a human' "parked: note names the park"
has "$(cat "$TMP/hold")"   'parked work bead: tk-work parked (status deferred)' "parked: hold reason names the status"

# --- 5. Fail-closed arms. -----------------------------------------------------

# LIVE conflict, escalate could not record a release path: NEVER hold or drain —
# the step stays claimable and the next worker retries the escalation.
out="$(FAKE_ESC_RC=1 FAKE_SESSIONS='{"sessions":[{"session_name":"lx-other"}]}' \
      run '[{"status":"in_progress","assignee":"lx-other","metadata":{}}]')"
eq "$out" "1|UPDATE;ESCALATE;" \
   "in-flight escalate fails: does not hold, does not drain"

# LIVE conflict, release recorded but the hold did not land: do NOT drain — the
# molecule can still be re-offered.
out="$(FAKE_HOLD_RC=1 FAKE_SESSIONS='{"sessions":[{"session_name":"lx-other"}]}' \
      run '[{"status":"in_progress","assignee":"lx-other","metadata":{}}]')"
eq "$out" "1|UPDATE;ESCALATE;HOLD;" \
   "in-flight hold fails after escalate: does not drain"

# FINISHED, the silent quiesce did not land: do NOT drain — no escalation is
# filed on this arm, and the molecule can still be re-offered.
out="$(FAKE_HOLD_RC=1 run "[{\"status\":\"open\",\"assignee\":\"$REFINERY\",\"metadata\":{}}]")"
eq "$out" "1|UPDATE;HOLD;" \
   "finished hold fails: does not drain, files no escalation"

out="$(FAKE_HOLD_RC=1 run '[{"status":"closed","assignee":"","metadata":{}}]')"
eq "$out" "1|UPDATE;HOLD;" \
   "closed hold fails: does not drain, files no escalation"

# Escalated, the release path could not be recorded: no hold, no drain, for the
# unreadable and parked situations as for the live conflict.
eq "$(FAKE_ESC_RC=1 FAKE_SESSIONS="$SESS_REAL" run '')" "1|UPDATE;ESCALATE;" \
   "unreadable escalate fails: does not hold, does not drain"
eq "$(FAKE_ESC_RC=1 run '[{"status":"deferred","metadata":{}}]')" "1|UPDATE;ESCALATE;" \
   "parked escalate fails: does not hold, does not drain"

# The refusal note is refused by the store (a closed-bead policy, a guard, a
# transient error): the failure is reported, and the hold and drain still run,
# because the hold reason on the step carries the same record.
out="$(FAKE_UPDATE_RC=1 run '[{"status":"closed","assignee":"","metadata":{}}]')"
eq "$out" "1|UPDATE;HOLD;DRAIN;" \
   "closed, refusal note refused: still holds and drains"
has "$(cat "$TMP/out")" 'The refusal note did not land on tk-work' "closed, refusal note refused: the failure is reported"
has "$(cat "$TMP/hold")" 'already closed' "closed, refusal note refused: the hold reason still records the refusal"

out="$(FAKE_UPDATE_RC=1 FAKE_SESSIONS='{"sessions":[{"session_name":"lx-other"}]}' \
      run '[{"status":"in_progress","assignee":"lx-other","metadata":{}}]')"
eq "$out" "1|UPDATE;ESCALATE;HOLD;DRAIN;" \
   "in-flight, refusal note refused: still escalates, holds and drains"
has "$(cat "$TMP/out")" 'The refusal note did not land on tk-work' "in-flight, refusal note refused: the failure is reported"

out="$(run '[{"status":"closed","assignee":"","metadata":{}}]')"
no "$(cat "$TMP/out")" 'did not land' "a note that landed reports nothing"

# --- 6. The work's tree. ------------------------------------------------------
# This workflow never claims its work bead, so a bead that would otherwise
# build is checked for a live session working it in its tree.

eq "$(run '[{"status":"open","assignee":"","metadata":{}}]')" "0|" \
   "fresh work the tree check clears: the gate passes"
eq "$(cat "$TMP/tree-args")" "<--bead><tk-work><--work-dir><><--branch><>" \
   "fresh work: the tree check gets the bead, an empty work_dir and an empty branch"

run '[{"status":"open","assignee":"","metadata":{"branch":"polecat/tk-anchor","work_dir":"/w/slots/p/worktrees/tk-work"}}]' >/dev/null
eq "$(cat "$TMP/tree-args")" "<--bead><tk-work><--work-dir></w/slots/p/worktrees/tk-work><--branch><polecat/tk-anchor>" \
   "rework child: the tree check gets the recorded work_dir and branch"

run "[{\"status\":\"in_progress\",\"assignee\":\"$SELF_NAME\",\"metadata\":{}}]" >/dev/null
eq "$(grep -c . "$TMP/tree-args")" "1" "owned by this session: the tree check runs"

FAKE_SESSIONS="$SESS_EMPTY" run '[{"status":"in_progress","assignee":"lx-dead","metadata":{}}]' >/dev/null
eq "$(grep -c . "$TMP/tree-args")" "1" "in_progress under a crashed foreign owner: the tree check runs"

# A bead refused on its status or assignee never reaches the tree check.
run "[{\"status\":\"open\",\"assignee\":\"$REFINERY\",\"metadata\":{}}]" >/dev/null
eq "$(cat "$TMP/tree-args")" "" "completed handoff: no tree check"
run '[{"status":"closed","assignee":"","metadata":{}}]' >/dev/null
eq "$(cat "$TMP/tree-args")" "" "closed: no tree check"
run '[{"status":"open","assignee":"","metadata":{"merge_result":"pull_request"}}]' >/dev/null
eq "$(cat "$TMP/tree-args")" "" "merge_result: no tree check"
run '[{"status":"deferred","assignee":"","metadata":{}}]' >/dev/null
eq "$(cat "$TMP/tree-args")" "" "parked: no tree check"
FAKE_SESSIONS="$SESS_REAL" run '' >/dev/null
eq "$(cat "$TMP/tree-args")" "" "unreadable: no tree check"
FAKE_SESSIONS='{"sessions":[{"session_name":"lx-other"}]}' \
  run '[{"status":"in_progress","assignee":"lx-other","metadata":{}}]' >/dev/null
eq "$(cat "$TMP/tree-args")" "" "in_progress under a live foreign owner: no tree check"

# Held: a live session is working this work in its tree.
FINDING_HELD="worktree /w/slots/p/worktrees/tk-work (uncommitted paths: 2) is held by live pool__polecat-lx-p, which is working tk-work"
eq "$(FAKE_TREE_RC=1 FAKE_TREE_OUT="$FINDING_HELD" run '[{"status":"open","assignee":"","metadata":{"work_dir":"/w/slots/p/worktrees/tk-work"}}]')" \
   "1|UPDATE;ESCALATE;HOLD;DRAIN;" \
   "a live session working this bead in its tree: escalates, holds, drains, exits 1"
has "$(cat "$TMP/update")" "Duplicate dispatch refused: $SELF_NAME found tk-work in flight in another session's tree: $FINDING_HELD." \
    "held tree: the note carries the finding"
has "$(cat "$TMP/hold")" "duplicate dispatch: tk-work in flight in another session's tree: $FINDING_HELD" \
    "held tree: the hold reason carries the finding"
has "$(cat "$TMP/esc")" "--key polecat-duplicate-dispatch" "held tree: the visit uses the duplicate-dispatch key"
has "$(cat "$TMP/esc")" "Duplicate dispatch on tk-work: it is in flight in another session's tree: $FINDING_HELD" \
    "held tree: the visit names the tree, its uncommitted paths and its holder"
has "$(cat "$TMP/esc")" "salvage the tree's uncommitted and unpushed work" "held tree: the visit asks for the salvage"

# Undecided: anything but a clear answer holds, under the same key.
FINDING_UNDECIDED="worktree /w/elsewhere/tk-work (uncommitted paths: 0) could not be cleared: no session directory accounts for it"
eq "$(FAKE_TREE_RC=2 FAKE_TREE_OUT="$FINDING_UNDECIDED" run '[{"status":"open","assignee":"","metadata":{"branch":"polecat/tk-work"}}]')" \
   "1|UPDATE;ESCALATE;HOLD;DRAIN;" \
   "a tree the check cannot clear: fails closed, escalates, holds"
has "$(cat "$TMP/esc")" "--key polecat-duplicate-dispatch" "undecided tree: the visit uses the duplicate-dispatch key"
has "$(cat "$TMP/esc")" "Possible duplicate dispatch on tk-work: it is possibly in flight in another session's tree: $FINDING_UNDECIDED" \
    "undecided tree: the visit names the tree and why it could not be cleared"
has "$(cat "$TMP/esc")" "Check the tree" "undecided tree: the visit says how to release it"
has "$(cat "$TMP/hold")" "duplicate dispatch: tk-work possibly in flight in another session's tree: $FINDING_UNDECIDED" \
    "undecided tree: the hold reason carries the finding"

eq "$(FAKE_TREE_RC=127 run '[{"status":"open","assignee":"","metadata":{}}]')" \
   "1|UPDATE;ESCALATE;HOLD;DRAIN;" \
   "a tree check that dies with no finding: fails closed, escalates, holds"
has "$(cat "$TMP/hold")" "work-tree-holder.sh exited 127 with no finding" "dead tree check: the hold reason says what failed"

# Adoptable: a foreign tree no live session is working. The finding is printed.
eq "$(FAKE_TREE_OUT="worktree /w/x (uncommitted paths: 0) is adoptable: no listed session works in /w/slots/p" \
      run '[{"status":"open","assignee":"","metadata":{"work_dir":"/w/x"}}]')" "0|" \
   "an adoptable foreign tree: the gate passes"
has "$(cat "$TMP/out")" "is adoptable: no listed session works in /w/slots/p" "adoptable tree: the finding is printed"

eq "$(FAKE_ESC_RC=1 FAKE_TREE_RC=1 FAKE_TREE_OUT="$FINDING_HELD" run '[{"status":"open","assignee":"","metadata":{}}]')" \
   "1|UPDATE;ESCALATE;" \
   "held tree, escalate fails: does not hold, does not drain"
eq "$(FAKE_HOLD_RC=1 FAKE_TREE_RC=1 FAKE_TREE_OUT="$FINDING_HELD" run '[{"status":"open","assignee":"","metadata":{}}]')" \
   "1|UPDATE;ESCALATE;HOLD;" \
   "held tree, hold fails after escalate: does not drain"

# --- 7. Pack resolution. ------------------------------------------------------
# The pack is the first candidate carrying every script the gate calls. A
# candidate without work-tree-holder.sh is a pack this formula does not ship
# with, so the lookup moves on rather than hold through it.
mkdir -p "$TMP/stale/assets/scripts"
printf '#!/usr/bin/env bash\nprintf "STALE-HOLD\\n" >> "$FAKE_LOG"\n' > "$TMP/stale/assets/scripts/molecule-hold.sh"
printf '#!/usr/bin/env bash\nprintf "STALE-ESCALATE\\n" >> "$FAKE_LOG"\n' > "$TMP/stale/assets/scripts/escalate.sh"
chmod +x "$TMP/stale/assets/scripts/molecule-hold.sh" "$TMP/stale/assets/scripts/escalate.sh"

eq "$(GC_PACK_DIR="$TMP/stale" GC_RIG_ROOT="$TMP/pack" run '[{"status":"closed","metadata":{}}]')" \
   "1|UPDATE;HOLD;DRAIN;" \
   "a candidate without work-tree-holder.sh is skipped for the next complete pack"

eq "$(GC_PACK_DIR="$TMP/stale" run '[{"status":"open","assignee":"","metadata":{}}]')" "1|" \
   "no complete pack: the gate stops before any note, check, hold or drain"
eq "$(cat "$TMP/tree-args")" "" "no complete pack: no tree check"
has "$(cat "$TMP/out")" "work-tree-holder.sh not found in the pack" "no complete pack: the stop names the scripts"

# --- 8. End to end with the real work-tree-holder.sh. -------------------------
# A real repository laid out like pool slots: this session's slot ($ME) and a
# peer slot whose per-bead tree holds uncommitted work. The pack serves the
# real tree check beside the stub hold and escalate.
E2E="$TMP/e2e"; E2E_REPO="$E2E/repo"; ME="$E2E/slots/me"; PEER="$E2E/slots/peer"
(
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1
  git init -q -b main "$E2E_REPO" &&
  git -C "$E2E_REPO" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q --allow-empty -m init &&
  git -C "$E2E_REPO" worktree add -q --detach "$ME" &&
  git -C "$E2E_REPO" worktree add -q --detach "$PEER" &&
  git -C "$E2E_REPO" worktree add -q --detach "$PEER/worktrees/tk-work"
) && ok "section 8 repository laid out" || bad "section 8 repository laid out"
echo wip > "$PEER/worktrees/tk-work/wip.txt"
mkdir -p "$TMP/e2e-pack/assets/scripts"
cp "$TMP/pack/assets/scripts/molecule-hold.sh" "$TMP/pack/assets/scripts/escalate.sh" "$TMP/e2e-pack/assets/scripts/"
ln -s "$HERE/work-tree-holder.sh" "$TMP/e2e-pack/assets/scripts/work-tree-holder.sh"

E2E_SESSIONS=$(jq -nc --arg me "$ME" --arg peer "$PEER" '{sessions: [
  {id: "lx-me", session_name: "pool__polecat-lx-me", name: "pool__polecat-lx-me", agent_name: "rig/rig.me", alias: null, state: "active", work_dir: $me},
  {id: "lx-peer", session_name: "pool__polecat-lx-peer", name: "pool__polecat-lx-peer", agent_name: "rig/rig.peer", alias: null, state: "active", work_dir: $peer}]}')
# e2e_beads <work bead the peer's molecule tracks> — the peer's claimed step,
# its root and input convoy, and that work bead's row.
e2e_beads() {
  jq -nc --arg w "$1" --arg tree "$PEER/worktrees/$1" '[
    {id: "st-p", status: "in_progress", assignee: "lx-peer", metadata: {"gc.root_bead_id": "root-p"}, dependencies: []},
    {id: "root-p", status: "in_progress", assignee: null, metadata: {"gc.input_convoy_id": "cv-p"}, dependencies: []},
    {id: "cv-p", status: "open", assignee: null, metadata: {}, dependencies: [{issue_id: "cv-p", depends_on_id: $w, type: "tracks"}]},
    {id: $w, status: "open", assignee: null, metadata: {branch: ("polecat/" + $w), work_dir: $tree}, dependencies: []}]'
}
E2E_BEAD="[{\"status\":\"open\",\"assignee\":\"\",\"metadata\":{\"work_dir\":\"$PEER/worktrees/tk-work\",\"branch\":\"polecat/tk-work\"}}]"

eq "$(RUN_DIR="$ME" GC_DIR="$ME" GC_PACK_DIR="$TMP/e2e-pack" FAKE_SESSIONS="$E2E_SESSIONS" FAKE_BEADS="$(e2e_beads tk-work)" run "$E2E_BEAD")" \
   "1|UPDATE;ESCALATE;HOLD;DRAIN;" \
   "end to end: a live peer running a molecule over this bead in its recorded tree holds the dispatch"
has "$(cat "$TMP/esc")" "worktree $PEER/worktrees/tk-work (uncommitted paths: 1) is held by live pool__polecat-lx-peer, which is working tk-work" \
    "end to end: the visit names the peer's tree, its uncommitted path and the peer"

eq "$(RUN_DIR="$ME" GC_DIR="$ME" GC_PACK_DIR="$TMP/e2e-pack" FAKE_SESSIONS="$E2E_SESSIONS" FAKE_BEADS="$(e2e_beads tk-other)" run "$E2E_BEAD")" \
   "0|" \
   "end to end: the peer slot's session on other work leaves the tree adoptable, and the gate passes"
has "$(cat "$TMP/out")" "is adoptable: live pool__polecat-lx-peer in $PEER is working other work (tk-other)" \
    "end to end: the adoptable finding is printed"

# --- Summary. -----------------------------------------------------------------
echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
