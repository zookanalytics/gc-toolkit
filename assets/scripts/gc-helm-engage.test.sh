#!/usr/bin/env bash
# Hermetic test for the gc-helm `engage` verb (tk-4abhrt).
#
# engage is the spawn-on-engagement entry point that replaces the retired
# converse routed-pool: it spawns a manual converse-<model> sitting, binds the
# picked visit to that session's runtime NAME (so the session's own
# `gc hook --claim` adopts it with no pool routing), and attaches.
#
# Runs the REAL gc-helm.sh (invoked via `sh`, as shipped) with a stubbed `gc` on
# PATH — no live city, Dolt, network, or sessions. Covered:
#   (MODEL)   an unknown --model is refused before anything spawns (exit 2)
#   (NOARG)   a missing bead-id is refused (exit 2)
#   (VISIT)   engaging an OPEN visit spawns converse-opus --alias <visit>
#             --no-attach and binds the visit to the session's runtime name
#   (KICK)    a bound sitting is sent its START-directive opening turn — a manual
#             converse session holds until a user turn — and (KICK-ORDER) that
#             turn precedes the attach; a lost/failed bind never kicks
#   (SUBJECT) engaging a subject resolves the one open visit tracking it
#   (MODELFLAG) --model codex spawns converse-codex
#   (BUSY)    a visit already in_progress under an owner is not re-spawned (exit 4)
#   (CLOSED)  a closed explicit visit is refused before spawning (exit 4)
#   (BLOCKED) a blocked explicit visit is refused before spawning (exit 4)
#   (NOSPAWN) a session new that returns no identity aborts without assigning
#   (RACE)    a bind whose --if-assignee guard is rejected (a concurrent engage
#             won in the spawn window) does not overwrite the winner, CLOSES the
#             loser sitting (a suspended one keeps its alias, so the re-run the
#             message advertises would be refused at `session new`), and exits 4
#   (ATTACH)  the default attaches to the captured session id; --no-attach does not
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/gc-helm.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-gc-helm-engage-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 (unexpected '$2')" ;; *) ok "$3" ;; esac; }

[ -f "$SCRIPT" ] && ok "gc-helm.sh present" || bad "gc-helm.sh missing at $SCRIPT"

mkdir -p "$TMP/bin"

# --- gc stub ------------------------------------------------------------------
# One rig (prefix tk). The subject bead is tk-subj (task_kind from $BEAD_KIND);
# the visit is tk-vis. `session new` prints a fixed identity and records its
# argv; `bd update --assignee` records the assignee to $ASSIGNEE so the read-back
# `bd show tk-vis` reflects it, the way the real store would. $VIS_STATUS drives
# the busy guard. Every session/mutating call is appended to $CALLS.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
SNAME="gc-toolkit__converse-1"
SID="gc-77"
case "$1 ${2:-}" in
  "rig list")
    # suspended/running are injected per-case via $RIG_SUSPENDED/$RIG_RUNNING.
    # Unset means the field is ABSENT (an older gc that does not report it), which
    # the liveness guard reads as unknown and does not refuse on — the default for
    # every case that does not set them.
    jq -n --arg susp "${RIG_SUSPENDED-}" --arg run "${RIG_RUNNING-}" \
      '{rigs:[ ({name:"gc-toolkit", path:"/nonexistent-rig", prefix:"tk"}
               + (if $susp != "" then {suspended: ($susp == "true")} else {} end)
               + (if $run  != "" then {running:   ($run  == "true")} else {} end)) ]}' ;;
  "session list")
    # Sessions the reclaim probe (sitting_is_gone) reads. Default: the current
    # $VIS_OWNER counts as live, so the pending/busy refusals hold unchanged. A
    # dead-sitting-reclaim case sets $LIVE_SITTINGS explicitly (space-separated
    # session names; empty = none live, so a bound owner reads as gone).
    # $SESSION_LIST_BROKEN makes the listing FAIL, so the probe fails closed.
    if [ -n "${SESSION_LIST_BROKEN:-}" ]; then echo "session list: data plane down" >&2; exit 1; fi
    _live="${LIVE_SITTINGS-$VIS_OWNER}"
    jq -n --arg live "$_live" \
      '{sessions:[ $live | split(" ")[] | select(. != "") | {session_name:., name:., id:., state:"running", closed:false} ]}' ;;
  "bd show")
    id="$3"
    if [ "$id" = "tk-vis" ]; then
      st="$(cat "$VIS_STATUS" 2>/dev/null || echo open)"
      who="$(cat "$ASSIGNEE" 2>/dev/null)"; [ -n "$who" ] || who="$VIS_OWNER"
      jq -n --arg i "$id" --arg s "$st" --arg a "$who" \
        '[{id:$i, status:$s, assignee:$a, metadata:{task_kind:"visit","gc.continuation_group":"tk-subj"}}]'
    else
      jq -n --arg i "$id" --arg k "${BEAD_KIND:-task}" \
        '[{id:$i, status:"open", assignee:"", metadata:{task_kind:$k}}]'
    fi ;;
  "bd list")
    # The one open visit tracking tk-subj, when $HAVE_VISIT is set.
    if [ "${HAVE_VISIT:-}" = "2" ]; then
      jq -n '[{id:"tk-vis2", status:"open", assignee:"", created_at:"2026-09-02T00:00:00Z", metadata:{task_kind:"visit","gc.continuation_group":"tk-subj"}},
              {id:"tk-vis", status:"open", assignee:"", created_at:"2026-09-01T00:00:00Z", metadata:{task_kind:"visit","gc.continuation_group":"tk-subj"}}]'
    elif [ "${HAVE_VISIT:-}" = "held" ]; then
      jq -n '[{id:"tk-vis2", status:"in_progress", assignee:"gc-toolkit__converse-3", metadata:{task_kind:"visit","gc.continuation_group":"tk-subj"}},
              {id:"tk-vis", status:"open", assignee:"", metadata:{task_kind:"visit","gc.continuation_group":"tk-subj"}}]'
    elif [ -n "${HAVE_VISIT:-}" ]; then
      jq -n '[{id:"tk-vis", status:"open", assignee:"", metadata:{task_kind:"visit","gc.continuation_group":"tk-subj"}}]'
    else printf '[]\n'; fi ;;
  "session new")
    printf 'session new %s\n' "$*" >> "$CALLS"
    # Record the rig context engage supplies: `gc session new` resolves a bare
    # template through GC_DIR/cwd, so engage must point it at the subject's rig.
    printf 'GC_DIR=%s\n' "${GC_DIR-<unset>}" >> "$CALLS"
    if [ -n "${SPAWN_EMPTY:-}" ]; then
      echo "gc session new: agent \"converse-opus\" not found in city.toml" >&2; jq -n '{ok:true}'; else
      jq -n --arg id "$SID" --arg n "$SNAME" '{schema_version:"1", ok:true, session_id:$id, session_name:$n, alias:"tk-vis", template:"t", transport:"tmux", work_dir:"/w", deferred_start:true, attached:false}'
    fi ;;
  "session attach")
    printf 'session attach %s\n' "$*" >> "$CALLS" ;;
  "session suspend")
    printf 'session suspend %s\n' "$*" >> "$CALLS" ;;
  "session close")
    printf 'session close %s\n' "$*" >> "$CALLS" ;;
  "session nudge")
    printf 'session nudge %s\n' "$*" >> "$CALLS" ;;
  "bd update")
    printf 'bd update %s\n' "$*" >> "$CALLS"
    _a="$*"
    # Model the real `bd update --if-assignee/--if-status` guard: on a mismatch
    # it writes nothing and exits 13 (vs 1 for other failures). $RACE_LOST forces
    # the guarded bind to lose — a concurrent engage took the visit in the spawn
    # window — and records the winner so the read-back `bd show` reports who holds
    # it. An unconditional update (no --if-assignee) always writes, as before.
    case "$_a" in
      *" --if-assignee "*)
        if [ -n "${RACE_LOST:-}" ]; then
          printf '%s' "${RACE_WINNER:-gc-toolkit__converse-9}" > "$ASSIGNEE"
          exit 13
        fi
        # $BIND_FAIL: the guarded bind fails for a reason other than the race
        # (a transient store error) — exit non-zero and non-13, writing nothing.
        if [ -n "${BIND_FAIL:-}" ]; then exit 1; fi
        # $BIND_NOPERSIST: the bind returns success but does not stick, so the
        # read-back finds the visit still unassigned.
        if [ -n "${BIND_NOPERSIST:-}" ]; then exit 0; fi ;;
    esac
    case "$_a" in *" --assignee "*)
      _a="${_a##* --assignee }"; printf '%s' "${_a%% *}" > "$ASSIGNEE"
      # $BIND_STOMP: a concurrent writer overwrites the just-written binding in
      # the window before the read-back, so the visit ends up held by another.
      [ -n "${BIND_STOMP:-}" ] && printf '%s' "$BIND_STOMP" > "$ASSIGNEE" ;;
    esac ;;
  "bd create")
    printf 'bd create %s\n' "$*" >> "$CALLS"; jq -n '{id:"tk-vis"}' ;;
  "bd dep")   printf 'bd dep %s\n' "$*" >> "$CALLS"
              # engage probes the visit's blockers (dep list --direction=down)
              # before spawning: default no blockers, $VIS_BLOCKERS injects open
              # "blocks" edges so a blocked visit can be exercised.
              if [ -n "${VIS_BLOCKERS:-}" ]; then
                jq -n --arg ids "$VIS_BLOCKERS" \
                  '[$ids | split(" ")[] | {id:., dependency_type:"blocks", status:"open"}]'
              else printf '[]\n'; fi ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

export PATH="$TMP/bin:$PATH"
export CALLS="$TMP/calls" ASSIGNEE="$TMP/assignee" VIS_STATUS="$TMP/vstatus"
unset GC_HELM_FIXTURE || true
export TMPDIR="$TMP"

# run_engage <bead> [extra-args...] -> RC/OUT, with per-case env preset by caller
run_engage() {
    : > "$CALLS"; : > "$ASSIGNEE"
    set +e
    OUT="$(sh "$SCRIPT" engage "$@" 2>"$TMP/err")"; RC=$?
    set -e
    OUT="$OUT$(cat "$TMP/err")"
    CALLED="$(cat "$CALLS")"
}

echo "# argument validation refuses before anything spawns"
BEAD_KIND=visit run_engage tk-vis --model bogus
eq "$RC" 2 "(MODEL) an unknown --model exits 2"
hasnt "$CALLED" "session new" "(MODEL) …and nothing was spawned"

run_engage ""
eq "$RC" 2 "(NOARG) a missing bead-id exits 2"

echo "# engaging an OPEN visit spawns a sitting and binds the visit to it"
export BEAD_KIND=visit VIS_OWNER="" HAVE_VISIT=""
printf 'open' > "$VIS_STATUS"
run_engage tk-vis --no-attach
eq "$RC" 0 "(VISIT) engaging an open visit exits 0"
has "$CALLED" "session new converse-opus --alias tk-vis --no-attach --json" "(VISIT) spawns converse-opus --alias <visit> --no-attach"
eq "$(cat "$ASSIGNEE")" "gc-toolkit__converse-1" "(BIND) the visit is assigned to the session's runtime name"
has "$CALLED" "bd update tk-vis --if-assignee" "(BIND) …conditionally, on the open+unassigned state the guards read"
has "$CALLED" "--if-status open" "(BIND) …and on the open status, so a lost race writes nothing"
has "$CALLED" "--assignee gc-toolkit__converse-1" "(BIND) …by name, the identity the claim adopts"
# A manual converse sitting holds until it receives a user turn, so a bound
# visit alone leaves the operator on a blank pane. engage sends the sitting its
# opening turn after the bind — on the --no-attach (board picker) path too, so
# the sitting starts for whoever attaches later.
has "$CALLED" "session nudge gc-77" "(KICK) the bound sitting is sent its opening turn"
has "$CALLED" "Begin now" "(KICK) …as a START directive, not a bare poke the agent reads as a connectivity check"

echo "# --model selects the tier"
run_engage tk-vis --model codex --no-attach
has "$CALLED" "session new converse-codex --alias tk-vis" "(MODELFLAG) --model codex spawns converse-codex"

echo "# engage supplies the subject's rig context so a bare template resolves"
# The converse templates are rig-scoped — there is no city-scoped bare
# converse-<model>, and `gc session new` resolves the name through GC_DIR/cwd,
# not GC_RIG. So from a non-rig cwd (the city root, where the tmux board picker
# runs) engage must point GC_DIR at the subject's rig or nothing spawns.
export BEAD_KIND=visit VIS_OWNER="" HAVE_VISIT=""
printf 'open' > "$VIS_STATUS"
: > "$CALLS"; : > "$ASSIGNEE"
set +e
OUT="$(cd "$TMP" && sh "$SCRIPT" engage tk-vis --no-attach 2>"$TMP/err")"; RC=$?
set -e
CALLED="$(cat "$CALLS")"
eq "$RC" 0 "(RIGCTX) engaging from a non-rig cwd exits 0"
has "$CALLED" "GC_DIR=/nonexistent-rig" "(RIGCTX) session new runs under the subject's rig via GC_DIR, not the ambient cwd"

echo "# engaging a SUBJECT resolves the one open visit tracking it"
export BEAD_KIND=task HAVE_VISIT=1
printf 'open' > "$VIS_STATUS"
run_engage tk-subj --no-attach
eq "$RC" 0 "(SUBJECT) engaging a subject with an open visit exits 0"
has "$CALLED" "session new converse-opus --alias tk-vis --no-attach --json" "(SUBJECT) spawns for the tracking visit"
unset HAVE_VISIT

echo "# a visit already engaged is not re-spawned"
export BEAD_KIND=visit VIS_OWNER="gc-toolkit__converse-9"
printf 'in_progress' > "$VIS_STATUS"
run_engage tk-vis --no-attach
eq "$RC" 4 "(BUSY) an in_progress visit under an owner exits 4"
hasnt "$CALLED" "session new" "(BUSY) …and spawns no duplicate sitting"
has "$OUT" "already engaged" "(BUSY) …and points at the running session"

echo "# an OPEN visit that already carries an assignee is a pending engagement"
# The window finding: engage binds the visit while it is still open, and the
# hook adopts an open+assignee visit through ready_assignment. A second engage
# before the sitting claims must NOT spawn a duplicate and overwrite the binding.
export VIS_OWNER="gc-toolkit__converse-7"
printf 'open' > "$VIS_STATUS"
run_engage tk-vis --no-attach
eq "$RC" 4 "(PENDING) an open visit with an assignee exits 4"
hasnt "$CALLED" "session new" "(PENDING) …and spawns no duplicate sitting"
has "$OUT" "pending engagement" "(PENDING) …and names it a pending engagement"

export VIS_OWNER=""
printf 'open' > "$VIS_STATUS"

echo "# a closed explicit visit is not claimable — refuse without spawning"
# The spawned sitting only ever holds the visit if its own hook claim finds it
# in `bd ready --assignee` (open and unblocked). A closed visit assigned to the
# sitting never becomes a claim, so engage must refuse it before anything spawns.
printf 'closed' > "$VIS_STATUS"
run_engage tk-vis --no-attach
eq "$RC" 4 "(CLOSED) engaging a closed visit exits 4"
hasnt "$CALLED" "session new" "(CLOSED) …and spawns nothing"
has "$OUT" "not open" "(CLOSED) …because a closed visit is not adoptable as a claim"

echo "# a blocked explicit visit is not in bd ready — refuse without spawning"
printf 'open' > "$VIS_STATUS"
export VIS_BLOCKERS="tk-blk"
run_engage tk-vis --no-attach
eq "$RC" 4 "(BLOCKED) engaging a blocked visit exits 4"
hasnt "$CALLED" "session new" "(BLOCKED) …and spawns nothing"
has "$OUT" "blocked by tk-blk" "(BLOCKED) …and names the blocker holding it out of bd ready"
unset VIS_BLOCKERS
printf 'open' > "$VIS_STATUS"

echo "# a spawn that yields no identity aborts without assigning"
export SPAWN_EMPTY=1
run_engage tk-vis --no-attach
eq "$RC" 4 "(NOSPAWN) a session with no identity exits 4"
eq "$(cat "$ASSIGNEE")" "" "(NOSPAWN) …and the visit is not assigned"
unset SPAWN_EMPTY
printf 'open' > "$VIS_STATUS"

echo "# a lost bind race: the visit was taken in the spawn window — do not overwrite"
# `gc session new` takes real time, so a second engage can pass the same
# open/unassigned/unblocked guards and reach the bind before this one does. The
# bind is conditional (--if-assignee "" --if-status open), so the loser's update
# writes nothing and exits 13. It must NOT overwrite the winner, must suspend the
# sitting it spawned (which holds nothing), and must point the operator at the
# winner. The stub rejects the guarded update and records the winner as the owner.
export BEAD_KIND=visit VIS_OWNER="" HAVE_VISIT=""
export RACE_LOST=1 RACE_WINNER="gc-toolkit__converse-8"
run_engage tk-vis --no-attach
eq "$RC" 4 "(RACE) a lost bind race exits 4"
has "$CALLED" "session new" "(RACE) …the sitting did spawn — the race is in the bind window, past the pre-spawn guards"
has "$CALLED" "bd update tk-vis --if-assignee" "(RACE) …the bind is conditional, so the store rejects the loser (exit 13)"
eq "$(cat "$ASSIGNEE")" "gc-toolkit__converse-8" "(RACE) …the assignee stays the winner, never the loser"
has "$CALLED" "session close gc-77" "(RACE) …the stranded loser sitting is closed"
has "$OUT" "not overwriting" "(RACE) …and the operator is told the winner was not overwritten"
hasnt "$CALLED" "session nudge" "(RACE) …and the loser sitting is never kicked — the kick is past the bind"
unset RACE_LOST RACE_WINNER

echo "# a failed bind (not the race): the sitting spawned but nothing holds the visit"
# A non-13 bd-update failure (a transient store error, not the guarded-race
# rejection) leaves the visit open and unassigned, but the sitting has already
# spawned. It must be suspended — a converse slot sets nudge=\"\"/idle_timeout=0
# and has no idle-claim rescue — and the operator told to re-run, not to
# hand-assign a visit to a suspended sitting.
export BEAD_KIND=visit VIS_OWNER="" HAVE_VISIT=""
export BIND_FAIL=1
run_engage tk-vis --no-attach
eq "$RC" 4 "(BIND-FAIL) a failed bind exits 4"
has "$CALLED" "session new" "(BIND-FAIL) …the sitting did spawn"
has "$CALLED" "session close gc-77" "(BIND-FAIL) …the spawned sitting is closed, not left orphaned"
eq "$(cat "$ASSIGNEE")" "" "(BIND-FAIL) …the visit stays unassigned"
hasnt "$OUT" "Assign by hand" "(BIND-FAIL) …the operator is not told to hand-assign to a suspended sitting"
hasnt "$CALLED" "session nudge" "(BIND-FAIL) …and the closed sitting is never kicked into a turn it cannot serve"
unset BIND_FAIL

echo "# a bind another writer stomps: read-back shows a different holder"
# The guarded bind succeeds, but a concurrent engage overwrites the assignee in
# the window before the read-back. This sitting holds nothing; suspend it and
# point the operator at the holder that won.
export BIND_STOMP="gc-toolkit__converse-8"
run_engage tk-vis --no-attach
eq "$RC" 4 "(STOMP) a stomped bind exits 4"
has "$CALLED" "session close gc-77" "(STOMP) …the stranded sitting is closed"
has "$OUT" "gc-toolkit__converse-8" "(STOMP) …and the operator is pointed at the holder that won"
unset BIND_STOMP

echo "# a bind that does not persist: read-back finds the visit still unassigned"
# The bind returns success but nothing sticks. The sitting spawned and holds
# nothing, so suspend it and tell the operator to re-run — the visit is unchanged.
export BIND_NOPERSIST=1
run_engage tk-vis --no-attach
eq "$RC" 4 "(NOPERSIST) a non-persisting bind exits 4"
has "$CALLED" "session close gc-77" "(NOPERSIST) …the spawned sitting is closed"
has "$OUT" "did not persist" "(NOPERSIST) …and the operator is told the bind did not persist"
unset BIND_NOPERSIST

echo "# a closed visit that still carries its last holder is 'not open', not 'attach to it'"
# bd close never clears the assignee, so every dismissed visit is closed+assigned.
# The status must be settled before the owner is read as a live sitting.
export VIS_OWNER="gc-toolkit__converse-7"
printf 'closed' > "$VIS_STATUS"
run_engage tk-vis --no-attach
eq "$RC" 4 "(CLOSED-OWNER) a closed visit with a stale assignee exits 4"
has "$OUT" "not open" "(CLOSED-OWNER) …as not open"
hasnt "$OUT" "attach to it" "(CLOSED-OWNER) …never pointing the operator at the ended sitting"
hasnt "$CALLED" "session new" "(CLOSED-OWNER) …and spawns nothing"
export VIS_OWNER=""
printf 'open' > "$VIS_STATUS"

echo "# a subject with several parked visits is an ambiguity the operator settles"
# escalate.sh files one visit per (subject, key), so a subject can carry more
# than one parked visit. engage must not pick one at random.
export BEAD_KIND=task HAVE_VISIT=2
run_engage tk-subj --no-attach
eq "$RC" 4 "(MULTI) two parked visits on the subject exit 4"
has "$OUT" "2 parked visits" "(MULTI) …naming the count"
has "$OUT" "tk-vis2" "(MULTI) …and the ids"
hasnt "$CALLED" "session new" "(MULTI) …and spawns nothing"

echo "# a subject whose only parked visit sits beside a held one engages the parked one"
export HAVE_VISIT=held
run_engage tk-subj --no-attach
eq "$RC" 0 "(PARKED-FIRST) the parked visit is engaged, not the held sibling"
has "$CALLED" "session new converse-opus --alias tk-vis " "(PARKED-FIRST) …spawning for the parked visit"
export BEAD_KIND=visit HAVE_VISIT=""

echo "# a spawn failure carries gc's reason"
# gc says WHY only on stderr; a template a rig does not carry (the converse
# templates are rig-scoped) must reach the operator as that, not as an empty output.
export SPAWN_EMPTY=1
run_engage tk-vis --no-attach
eq "$RC" 4 "(SPAWN-WHY) a spawn that yields no identity exits 4"
has "$OUT" "gc said: gc session new: agent" "(SPAWN-WHY) …quoting gc's stderr"
has "$OUT" "rig-scoped" "(SPAWN-WHY) …and explaining the rig-scoped template"
unset SPAWN_EMPTY

echo "# a bead whose prefix names no rig is refused before anything runs"
run_engage zz-vis --no-attach
eq "$RC" 4 "(NORIG) an unknown prefix exits 4"
has "$OUT" "matches no rig" "(NORIG) …saying so"
hasnt "$CALLED" "session new" "(NORIG) …and spawns nothing"

echo "# attach behaviour: default attaches, --no-attach does not"
run_engage tk-vis --no-attach
hasnt "$CALLED" "session attach" "(ATTACH) --no-attach does not attach"
run_engage tk-vis
has "$CALLED" "session attach gc-77" "(ATTACH) the default attaches to the captured session id"
# attach is a foreground handoff to the pane — nothing after it in cmd_engage
# runs until the operator detaches — so the opening turn must be sent first for
# the operator to land on a live, framed sitting rather than a blank one.
nudge_line=$(printf '%s\n' "$CALLED" | grep -n "session nudge" | head -1 | cut -d: -f1)
attach_line=$(printf '%s\n' "$CALLED" | grep -n "session attach" | head -1 | cut -d: -f1)
if [ -n "$nudge_line" ] && [ -n "$attach_line" ] && [ "$nudge_line" -lt "$attach_line" ]; then
  ok "(KICK-ORDER) the opening turn is sent before the attach"
else
  bad "(KICK-ORDER) expected nudge (line ${nudge_line:-none}) before attach (line ${attach_line:-none})"
fi

echo "# a suspended subject rig is refused before anything spawns"
# engage spawns a sitting the reconciler must sustain; on a suspended rig the
# reconciler skips its agents, so the sitting never comes up and the visit would
# strand bound to it. Refuse before spawning, and name the resume as the fix.
export BEAD_KIND=visit VIS_OWNER="" HAVE_VISIT=""
printf 'open' > "$VIS_STATUS"
export RIG_SUSPENDED=true
run_engage tk-vis --no-attach
eq "$RC" 4 "(SUSPENDED) engaging on a suspended rig exits 4"
hasnt "$CALLED" "session new" "(SUSPENDED) …and spawns nothing"
has "$OUT" "is suspended" "(SUSPENDED) …saying the rig is suspended"
has "$OUT" "gc rig resume gc-toolkit" "(SUSPENDED) …and naming the resume as the fix"
unset RIG_SUSPENDED

echo "# a subject rig with no agents running is refused before anything spawns"
export RIG_RUNNING=false
run_engage tk-vis --no-attach
eq "$RC" 4 "(NOTRUNNING) engaging on a not-running rig exits 4"
hasnt "$CALLED" "session new" "(NOTRUNNING) …and spawns nothing"
has "$OUT" "no agents running" "(NOTRUNNING) …saying so"
unset RIG_RUNNING

echo "# an explicitly live rig (suspended=false, running=true) spawns as normal"
# The guard refuses only on suspended=true or running=false, so a rig gc reports
# as live must engage exactly as one that reports neither flag.
export RIG_SUSPENDED=false RIG_RUNNING=true
run_engage tk-vis --no-attach
eq "$RC" 0 "(LIVE) engaging on an explicitly live rig exits 0"
has "$CALLED" "session new converse-opus --alias tk-vis" "(LIVE) …and spawns the sitting"
unset RIG_SUSPENDED RIG_RUNNING

echo "# an open visit bound to a GONE sitting is reclaimed, then re-engaged"
# A sitting whose rig was suspended/down at bind time never registers, leaving
# the visit open+assigned to a session absent from `gc session list`. engage must
# not point the operator at that dead session: it reclaims the visit (clears the
# binding, re-parks on the board) and spawns a fresh sitting.
export BEAD_KIND=visit VIS_OWNER="gc-toolkit__converse-dead" HAVE_VISIT=""
printf 'open' > "$VIS_STATUS"
export LIVE_SITTINGS=""
run_engage tk-vis --no-attach
eq "$RC" 0 "(RECLAIM) engaging a visit bound to a gone sitting exits 0"
has "$OUT" "reclaimed visit tk-vis" "(RECLAIM) …announcing the reclaim"
has "$CALLED" "bd update tk-vis --if-assignee gc-toolkit__converse-dead --if-status open" "(RECLAIM) …clearing the binding only while it still holds the gone owner"
has "$CALLED" "gc.routed_to=human" "(RECLAIM) …and re-parks it on the board"
has "$CALLED" "session new converse-opus --alias tk-vis" "(RECLAIM) …then spawns a fresh sitting"
eq "$(cat "$ASSIGNEE")" "gc-toolkit__converse-1" "(RECLAIM) …bound to the fresh sitting's runtime name"
unset LIVE_SITTINGS

echo "# a reclaim whose guarded clear loses the race defers to the winner, spawning nothing"
# `gc session list` and the reclaim write are two calls: a second engage that
# read the same gone owner can reclaim and re-engage in the window between them.
# The guarded clear (--if-assignee/--if-status) then writes nothing and exits 13,
# so this engage points at the winner instead of overwriting the live binding.
export BEAD_KIND=visit VIS_OWNER="gc-toolkit__converse-dead" HAVE_VISIT=""
printf 'open' > "$VIS_STATUS"
export LIVE_SITTINGS="" RACE_LOST=1 RACE_WINNER="gc-toolkit__converse-9"
run_engage tk-vis --no-attach
eq "$RC" 4 "(RECLAIM-RACE) a reclaim that loses the guarded clear exits 4"
hasnt "$CALLED" "session new" "(RECLAIM-RACE) …and spawns no duplicate"
has "$OUT" "gc-toolkit__converse-9" "(RECLAIM-RACE) …pointing at the winner that took the visit"
unset LIVE_SITTINGS RACE_LOST RACE_WINNER
export VIS_OWNER=""

echo "# an open visit bound to a LIVE sitting stays a pending engagement, not a reclaim"
# Reclaim fires only when the bound sitting is PROVABLY gone. A live owner keeps
# the pending-engagement refusal, so a second engage never steals a live binding.
export VIS_OWNER="gc-toolkit__converse-7"
printf 'open' > "$VIS_STATUS"
export LIVE_SITTINGS="gc-toolkit__converse-7"
run_engage tk-vis --no-attach
eq "$RC" 4 "(LIVE-OWNER) an open visit under a live sitting exits 4"
hasnt "$CALLED" "session new" "(LIVE-OWNER) …and spawns no duplicate"
has "$OUT" "pending engagement" "(LIVE-OWNER) …naming it a pending engagement, not a reclaim"
hasnt "$OUT" "reclaimed" "(LIVE-OWNER) …and never reclaims a live binding"
unset LIVE_SITTINGS
export VIS_OWNER=""

echo "# an unreadable session list fails CLOSED — a bound visit is not reclaimed"
# sitting_is_gone must PROVE the sitting gone; a session list it cannot read is
# not that proof, so the pending-engagement refusal holds rather than reclaiming
# a possibly-live binding on a transient read failure.
export VIS_OWNER="gc-toolkit__converse-7"
printf 'open' > "$VIS_STATUS"
export SESSION_LIST_BROKEN=1
run_engage tk-vis --no-attach
eq "$RC" 4 "(GONE-UNREADABLE) an unreadable session list exits 4 (fails closed)"
hasnt "$CALLED" "session new" "(GONE-UNREADABLE) …and spawns nothing"
has "$OUT" "pending engagement" "(GONE-UNREADABLE) …keeping the pending-engagement refusal"
unset SESSION_LIST_BROKEN
export VIS_OWNER=""

echo
echo "gc-helm engage: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
