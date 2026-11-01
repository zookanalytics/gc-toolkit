#!/usr/bin/env bash
# Hermetic test for the gc-helm `engage` verb.
#
# engage holds a conversation about a bead in a converse sitting: it attaches
# to a live sitting on the bead, or takes the bead's conversation from the
# operator's queue (or one whose sitting's session has closed), or files one,
# then spawns a manual converse-<model> sitting named for the conversation,
# binds the conversation to the sitting's alias with a write guarded on the
# holder it read, and attaches once the reconciler has started it. Pointed at a
# human gate, it takes the one bead still waiting on the gate, and the
# conversation it lands on replies to the gate.
#
# Runs the REAL gc-helm.sh (invoked via `sh`, as shipped) with a stubbed `gc` on
# PATH — no live city, Dolt, network, or sessions. Covered:
#   (MODEL, NOARG) an unknown --model or a missing bead is refused (exit 2)
#   (CONVID)  engaging a conversation in the queue spawns converse-opus --alias
#             <conversation> --no-attach and binds it to the sitting's alias,
#             guarded on `human`, the holder engage read
#   (NO-KICK, KICK-CODEX) an opus/fable sitting self-starts from its prompt and
#             is not kicked; a codex sitting keeps the START-directive kick
#   (SUBJECT) engaging a bead takes its conversation from the queue, says so,
#             and offers --reason; a bead with none gets one filed
#   (JOIN-RACE) a conversation another open files in the queue after engage's
#             listing is the one engage takes, through the open it runs
#   (REASON-NEW) --reason files a fresh conversation even when one waits
#   (CONVID-REASON) --reason on an explicit conversation id is refused
#   (LIVE)    a conversation a live sitting holds is attached to, not doubled
#   (REUSE-*) a live sitting engage reuses is attached only once it reads
#             active: one still start-pending or creating is waited on and left
#             unattached at the bound, which exits 4, one that ends first is
#             reported, and --no-attach does not wait
#   (LEFT)    a conversation whose sitting's session closed is resumed under
#             the same alias, with no bind needed
#   (TWO-TRACKS, UNREAD) a task assigned to human that tracks the bead and
#             another is no conversation engage takes, and a candidate whose
#             own row does not read starts nothing
#   (CUT-SHORT) a session still holding the alias of a conversation back in
#             the queue is closed first, so the new sitting can take the alias
#   (GATE)    a gate names the one bead waiting on it; the conversation engage
#             lands on — filed, taken from the queue, or live — replies to the
#             gate before any sitting starts; two waiting beads, or none, start
#             nothing and say why
#   (WARN)    a second live sitting on the bead, or one replying to a gate the
#             bead waits on, is warned about, never refused
#   (TAKEN, BIND-FAIL, STOMP, NOPERSIST) a bind that misses or does not stick
#             closes the sitting it spawned and overwrites nothing
#   (DISMISSED-*) a conversation a dismiss closes while the sitting spawns, in
#             the queue, filed by engage, or resumed under the same alias or
#             another, fails the bind's status guard or its read-back: the
#             sitting is closed, and the conversation stays closed with the
#             holder the dismiss left
#   (ALIAS-*, RACE-CONCURRENT) a spawn refused at the alias spawns nothing and
#             waits for the holder's bind; two engages of one conversation spawn
#             once and bind once
#   (ALIAS-RETRY) an id the runtime refuses as an alias is retried under c-
#   (ATTACH, START-*, NOATTACH-*) the attach waits until the sitting reads
#             active, because an attach that reaches a sitting the reconciler
#             has not started launches it without its prompt. It waits however
#             long the start takes (START-LONG, minutes on a fake clock), and
#             says so when the wait opens, when the state changes, and every
#             30s (START-PROGRESS). One that ends first exits 4 at once, early
#             or late; a sitting not yet listed, or a listing that fails, is
#             waited through. A sitting still unstarted at
#             GC_HELM_ENGAGE_WAIT_TIMEOUT, 15 minutes by default
#             (START-BACKSTOP), is left unattached and exits 4, with the attach
#             to run later. (START-INTERRUPT) Ctrl-C stops the wait, leaves the
#             conversation bound and the sitting open, and prints the attach,
#             after kicking a codex sitting (INTERRUPT-KICK); a hang-up or a
#             TERM stops it the same way (INTERRUPT-HUP, INTERRUPT-TERM).
#   (ENDED*, DETACHED, UNREAD, ATTACH-FAIL-*) once the attach returns, the
#             conversation says what the tab prints: a closed conversation
#             prints how it closed and the last hand-back recorded on it, its
#             control bytes dropped; a conversation still open prints the
#             re-attach command; an unreadable one says the ending is unknown;
#             and a failed attach on a closed conversation reports the ending
#             rather than an attach to retry
#   (SUSPENDED, CTRL-*) a suspended rig or a down controller refuses first
#   (IA-*)    the interactive prompts: subject, conversation or starter, model,
#             skill
#   (NEWSUBJ*) --new-subject files a marked subject and its one conversation
#   (SKILL*)  --skill files a new conversation whose ask is the lens brief
#   (HOLD-*)  the open human gates that hold a bead, read through gctk: the prompt
#             offers each on the numbers after the conversations, a pick engages
#             it as if it were named, or takes the bead it was picked from when
#             several wait on the gate, with a conversation to take or none, an
#             engage that asks nothing names them, and one pointed at a gate or a
#             conversation does not read them. A read
#             that does not answer is said and stops nothing. (HOLD-REAL) runs the
#             real gctk reader over the fixture of an anchor, its rework and the
#             gate on the rework.
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

mkdir -p "$TMP/bin" "$TMP/state"

# --- gc stub ------------------------------------------------------------------
# One rig (prefix tk). The subject is tk-subj; its conversations are tk-conv
# and tk-conv2, and a conversation engage files is tk-new. Each conversation's
# assignee and status live in $STATE/<id>.assignee and $STATE/<id>.status
# (defaults human and open), so a bind and its read-back see what the store
# would. $HAVE_CONV says which conversations track tk-subj: unset or 1 tk-conv,
# 2 tk-conv and tk-conv2, two tk-conv and tk-two, 0 none. tk-two is an older
# task assigned to human that tracks tk-subj and tk-elsewhere, so it is no
# conversation. `bd list --id` answers each named row with its edges, leaving
# out an id in $LIST_DROPS, as a row the store did not return. The gate tk-gate
# is a human gate; the beads waiting on it are $GATE_WAITERS (JSON). The live
# converse sessions are the lines of
# $STATE/live ("<sid> <alias>"), seeded per case from $LIVE_SITTINGS; `session
# close` removes one. Every session call and every mutating bd call is appended
# to $CALLS; reads are not, except the ones a case counts.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
SNAME="s-gc-77"
SID="gc-77"
ST="$STATE_DIR"
# A mkdir lock, so two concurrent engages see one atomic check-and-write: the
# alias reservation below, and the compare-and-swap of a guarded bd update.
stub_lock()   { _t=0; until mkdir "$1" 2>/dev/null; do sleep 0.02; _t=$((_t + 1)); [ "$_t" -lt 1500 ] || break; done; }
stub_unlock() { rmdir "$1" 2>/dev/null || true; }
asg_of()  { cat "$ST/$1.assignee" 2>/dev/null || printf 'human'; }
stat_of() { cat "$ST/$1.status" 2>/dev/null || printf 'open'; }
subj_of() { cat "$ST/$1.subject" 2>/dev/null || printf 'tk-subj'; }
conv_ids() {
  case "${HAVE_CONV-1}" in
    2) printf 'tk-conv tk-conv2' ;;
    two) printf 'tk-two tk-conv' ;;
    0|"") ;;
    *) printf 'tk-conv' ;;
  esac
}
# conv_row <id> <shape> — a conversation's row, in the `gc bd show` edge shape
# (show) or the `gc bd list` one (list), with the replies-to edges `dep add`
# recorded.
conv_row() {
  _reps=$(awk -v c="$1" '$1 == c {print $2}' "$ST/replies" 2>/dev/null | jq -Rsc '[ split("\n")[] | select(. != "") ]')
  _created="2026-10-01T00:00:00Z"; [ "$1" = tk-conv2 ] && _created="2026-10-02T00:00:00Z"
  _title="an earlier concern"; [ "$1" = tk-conv2 ] && _title="a second concern"
  _also=""
  if [ "$1" = tk-two ]; then _created="2026-09-01T00:00:00Z"; _title="a task about two beads"; _also="tk-elsewhere"; fi
  # $ST/<id>.meta (a JSON object) and $ST/<id>.reason seed the metadata and
  # the close reason a closed sitting leaves, such as its hand-back.
  _meta=$(cat "$ST/$1.meta" 2>/dev/null || true); [ -n "$_meta" ] || _meta='{}'
  jq -n --arg c "$1" --arg a "$(asg_of "$1")" --arg st "$(stat_of "$1")" --arg s "$(subj_of "$1")" \
        --arg t "$_title" --arg cr "$_created" --arg shape "$2" --arg x "$_also" --argjson r "${_reps:-[]}" \
        --argjson md "$_meta" --arg why "$(cat "$ST/$1.reason" 2>/dev/null || true)" '
    ([$s] + (if $x == "" then [] else [$x] end)) as $tracked
    | {id:$c, issue_type:"task", status:$st, assignee:$a, title:$t, created_at:$cr, metadata:$md}
    + (if $why == "" then {} else {close_reason:$why} end)
    + (if $shape == "show"
       then {dependencies:([ $tracked[] | {id:., dependency_type:"tracks"} ] + [ $r[] | {id:., dependency_type:"replies-to"} ])}
       else {dependencies:([ $tracked[] | {issue_id:$c, depends_on_id:., type:"tracks"} ] + [ $r[] | {issue_id:$c, depends_on_id:., type:"replies-to"} ])} end)'
}
# The walk's read in gctk, under the (HOLD-REAL) wrapper: a row per id, its edges
# from $WALK_EDGES, a JSON object of each bead's dependency rows.
if [ -n "${STUB_WALK:-}" ] && [ "$1 ${2:-}" = "bd show" ]; then
  shift 2
  _ids=()
  for a in "$@"; do case "$a" in --*) ;; *) _ids+=("$a") ;; esac; done
  printf '%s' "${WALK_EDGES:-{\}}" | jq -c --args '. as $e | [$ARGS.positional[] | {id: ., dependencies: ($e[.] // [])}]' "${_ids[@]}"
  exit 0
fi
case "$1 ${2:-}" in
  "rig list")
    # The HQ row leads, as gc lists it; its running flag is gc's probe of the city
    # controller, injected via $HQ_RUNNING. The rig's suspended/running are
    # injected via $RIG_SUSPENDED/$RIG_RUNNING. Unset means the field is ABSENT (an
    # older gc that does not report it), which the liveness guard reads as unknown
    # and does not refuse on — the default for every case that does not set them.
    # $NO_HQ_ROW drops the HQ row altogether, which reads as unknown the same way.
    jq -n --arg susp "${RIG_SUSPENDED-}" --arg run "${RIG_RUNNING-}" --arg hq "${HQ_RUNNING-}" \
          --arg nohq "${NO_HQ_ROW-}" \
      '{rigs:[ (if $nohq != "" then empty
                else {name:"mycity", path:"/nonexistent-city", prefix:"hq", hq:true}
                     + (if $hq   != "" then {running:   ($hq   == "true")} else {} end) end),
               ({name:"gc-toolkit", path:(env.RIG_PATH // "/nonexistent-rig"), prefix:"tk", hq:false}
               + (if $susp != "" then {suspended: ($susp == "true")} else {} end)
               + (if $run  != "" then {running:   ($run  == "true")} else {} end)) ]}' ;;
  "status --json")
    # The supervisor-aware controller reading the liveness guard asks before an
    # HQ running=false counts. $STATUS_CONTROLLER sets .controller.running
    # ("true"/"false"); "unknown" is the supervisor that is up but cannot say;
    # "broken" prints something that is not JSON. Unset prints nothing.
    printf 'status --json\n' >> "$CALLS"
    case "${STATUS_CONTROLLER-}" in
      true)    printf '{"controller":{"running":true,"pid":7,"mode":"supervisor"}}\n' ;;
      false)   printf '{"controller":{"running":false,"mode":"supervisor"}}\n'; exit 1 ;;
      unknown) printf '{"controller":{"running":false,"pid":7,"mode":"supervisor","status":"unknown"}}\n' ;;
      broken)  printf 'gc status: not json\n' ;;
    esac ;;
  "session list")
    # The live converse sittings ($STATE/live), plus, once `session new` has
    # spawned one, that sitting's own row, which engage's start wait reads. Its
    # state walks $START_STATES, one entry per listing after the spawn, the last
    # repeating: "active" (the default), start-pending, creating, or a token.
    # "gone" lists no row, the way a closed session reads from the store;
    # "blank" lists an empty state, the way it reads from the supervisor; and
    # "broken" fails the listing. $SESSION_LIST_BROKEN fails every listing.
    printf 'session list\n' >> "$CALLS"
    if [ -n "${SESSION_LIST_BROKEN:-}" ]; then echo "session list: data plane down" >&2; exit 1; fi
    _st=""
    if [ -s "$SPAWNED" ]; then
      _n=$(( $(cat "$POLLS" 2>/dev/null || echo 0) + 1 )); printf '%s' "$_n" > "$POLLS"
      set -- ${START_STATES:-active}
      [ "$_n" -le $# ] || _n=$#
      eval "_st=\${$_n}"
      [ "$_st" = broken ] && { echo "session list: data plane down" >&2; exit 1; }
    fi
    # A sitting $STATE/live seeds was created long ago; $ALIAS_HOLDER, the
    # session holding tk-conv's alias that a concurrent engage has just spawned,
    # was created now, as are the sittings the race spawns. $ALIAS_DECOYS adds,
    # ahead of it, an open sitting of ANOTHER conversation whose alias shares the
    # prefix and a CLOSED sitting that once held tk-conv's alias; neither holds
    # it. In the concurrent race the sittings the stub spawned are listed too.
    _spawned=""
    if [ -n "${ALIAS_REGISTRY:-}" ]; then
      for _f in "$ALIAS_REGISTRY"/held.*; do
        [ -f "$_f" ] && _spawned="$_spawned $(cat "$_f")=${_f##*/held.}"
      done
    fi
    _live=$(awk 'NF == 2 {printf "%s=%s ", $1, $2}' "$ST/live" 2>/dev/null)
    _salias="$(cat "$ST/spawned-alias" 2>/dev/null || true)"
    # The sittings $STATE/live seeds read active, unless $LIVE_STATES walks
    # their state, one entry per listing, the last repeating, with the same
    # tokens as $START_STATES: a sitting an earlier engage spawned with
    # --no-attach is live while it waits for the reconciler's launch.
    _lst=active
    if [ -n "${LIVE_STATES:-}" ]; then
      _ln=$(( $(cat "$ST/live-polls" 2>/dev/null || echo 0) + 1 )); printf '%s' "$_ln" > "$ST/live-polls"
      set -- $LIVE_STATES
      [ "$_ln" -le $# ] || _ln=$#
      eval "_lst=\${$_ln}"
    fi
    jq -n --arg live "$_live" --arg st "$_st" --arg sid "$SID" --arg sn "$SNAME" --arg sa "$_salias" \
          --arg holder "${ALIAS_HOLDER:-}" --arg decoys "${ALIAS_DECOYS:-}" --arg spawned "$_spawned" --arg lst "$_lst" \
      '{sessions:([ $live | split(" ")[] | select(. != "" and $lst != "gone") | split("=") | {id:.[0], session_name:("s-" + .[0]), alias:.[1], template:"gc-toolkit/gc-toolkit.converse-opus", state:(if $lst == "blank" then "" else $lst end), closed:false, created_at:"2026-10-01T00:00:00Z", attached:false} ]
         + (if $st == "" or $st == "gone" then []
            else [{id:$sid, session_name:$sn, alias:$sa, template:"gc-toolkit/gc-toolkit.converse-opus", state:(if $st == "blank" then "" else $st end)}] end)
         + (if $decoys != "" then [{id:"gc-90", session_name:"s-gc-90", alias:"gc-toolkit/gc-toolkit.tk-conv2x", template:"gc-toolkit/gc-toolkit.converse-opus", state:"active", closed:false},
                                   {id:"gc-91", session_name:"s-gc-91", alias:"gc-toolkit/gc-toolkit.tk-conv", template:"gc-toolkit/gc-toolkit.converse-opus", state:"closed", closed:true}] else [] end)
         + (if $holder != "" then [{id:$holder, session_name:("s-" + $holder), alias:"gc-toolkit/gc-toolkit.tk-conv", template:"gc-toolkit/gc-toolkit.converse-opus", state:"creating", closed:false, created_at:(now | todate)}] else [] end)
         + [ $spawned | split(" ")[] | select(. != "") | split("=") | {id:.[0], session_name:("s-" + .[0]), alias:("gc-toolkit/gc-toolkit." + .[1]), template:"gc-toolkit/gc-toolkit.converse-opus", state:"creating", closed:false, created_at:(now | todate)} ])}' ;;
  "agent list")
    # The import-resolved roster rig_carries_converse reads. Default: gc-toolkit
    # carries converse (base + variants). $NO_CONVERSE drops the converse
    # entries; it keeps a proactive entry to prove the guard is converse-specific.
    if [ -n "${NO_CONVERSE:-}" ]; then
      jq -n '{agents:[{qualified_name:"gc-toolkit/gc-toolkit.proactive"}]}'
    else
      jq -n '{agents:[ "gc-toolkit/gc-toolkit.converse","gc-toolkit/gc-toolkit.converse-opus","gc-toolkit/gc-toolkit.converse-fable","gc-toolkit/gc-toolkit.converse-codex" | {qualified_name:.} ]}'
    fi ;;
  "bd show")
    id="$3"
    case "$id" in
      tk-conv|tk-conv2|tk-new)
        [ -f "$ST/$id.unread" ] && { echo "bd show: data plane down" >&2; exit 1; }
        # Once a spawn is refused at the alias ($ALIAS_REFUSED exists), the
        # refused engage polls the conversation. The change it waits for lands
        # on the $AFTER_REFUSAL_READS-th read: a concurrent engage's bind
        # ($AFTER_REFUSAL_ASSIGNEE) or a close ($AFTER_REFUSAL_STATUS).
        # $AFTER_REFUSAL_UNREADABLE makes every read after the refusal fail.
        if [ -f "$ALIAS_REFUSED" ]; then
          if [ -n "${AFTER_REFUSAL_UNREADABLE:-}" ]; then echo "bd show: data plane down" >&2; exit 1; fi
          _reads=$(( $(cat "$ALIAS_REFUSED.reads" 2>/dev/null || echo 0) + 1 ))
          printf '%s' "$_reads" > "$ALIAS_REFUSED.reads"
          if [ -n "${AFTER_REFUSAL_READS:-}" ] && [ "$_reads" -ge "$AFTER_REFUSAL_READS" ]; then
            [ -n "${AFTER_REFUSAL_ASSIGNEE:-}" ] && printf '%s' "$AFTER_REFUSAL_ASSIGNEE" > "$ST/$id.assignee"
            [ -n "${AFTER_REFUSAL_STATUS:-}" ] && printf '%s' "$AFTER_REFUSAL_STATUS" > "$ST/$id.status"
          fi
        fi
        jq -c -n --argjson r "$(conv_row "$id" show)" '[$r]' ;;
      tk-gate)
        jq -n '[{id:"tk-gate", title:"Approve the rollout", description:"Gate on the waiting bead.", status:"open", issue_type:"gate", await_type:"human", await_id:"rollout"}]' ;;
      *)
        jq -n --arg i "$id" --arg t "${SUBJ_TITLE:-the subject under engagement}" \
          '[{id:$i, title:$t, status:"open", issue_type:"task", priority:2, assignee:""}]' ;;
    esac ;;
  "bd list")
    _id=""; _prev=""
    for a in "$@"; do [ "$_prev" = "--id" ] && _id="$a"; _prev="$a"; done
    if [ -n "$_id" ]; then
      _rows='[]'
      for _i in $(printf '%s' "$_id" | tr ',' ' '); do
        case ",${LIST_DROPS:-}," in *",$_i,"*) continue ;; esac
        _rows=$(jq -c --argjson r "$(conv_row "$_i" list)" '. + [$r]' <<< "$_rows")
      done
      printf '%s\n' "$_rows"
      exit 0
    fi
    case "$*" in
      *--title-contains*)
        # The subject title search. $SEARCH_HIT injects a matching bead so a
        # search resolves; unset = no match.
        if [ -n "${SEARCH_HIT:-}" ]; then
          jq -n '[{id:"tk-subj", status:"open", issue_type:"task", assignee:"", title:"a searchable subject"}]'
        else printf '[]\n'; fi ;;
      *) printf '[]\n' ;;
    esac ;;
  "bd dep")
    case "$3" in
      list)
        _who="$4"
        case " $* " in
          *" --type tracks "*)
            if [ "$_who" = "${CONV_SUBJECT:-tk-subj}" ]; then
              # $CONV_FILED_AFTER: a concurrent open files tk-conv in the queue
              # once that many listings of the bead's conversations have
              # answered without it.
              _ids=$(conv_ids)
              if [ -n "${CONV_FILED_AFTER:-}" ]; then
                _n=$(( $(cat "$ST/tracks-reads" 2>/dev/null || echo 0) + 1 )); printf '%s' "$_n" > "$ST/tracks-reads"
                [ "$_n" -le "$CONV_FILED_AFTER" ] || _ids="tk-conv"
              fi
              _rows='[]'
              for c in $_ids; do
                _rows=$(jq -c --argjson r "$(conv_row "$c" list)" '. + [$r | del(.dependencies) + {dependency_type:"tracks"}]' <<< "$_rows")
              done
              printf '%s\n' "$_rows"
            else printf '[]\n'; fi ;;
          *" --type blocks "*)
            if [ "$_who" = tk-gate ]; then printf '%s\n' "${GATE_WAITERS:-[]}"
            else printf '%s\n' "${BEAD_GATES:-[]}"; fi ;;
          *" --type replies-to "*) printf '%s\n' "${GATE_REPLIES:-[]}" ;;
          *) printf '[]\n' ;;
        esac ;;
      add)
        printf 'bd dep %s\n' "$*" >> "$CALLS"
        [ -n "${REPLY_FAIL:-}" ] || printf '%s %s\n' "$4" "$5" >> "$ST/replies" ;;
      *) printf 'bd dep %s\n' "$*" >> "$CALLS" ;;
    esac ;;
  "session new")
    printf 'session new %s\n' "$*" >> "$CALLS"
    # Record the rig context engage supplies: `gc session new` resolves a bare
    # template through GC_DIR/cwd, so engage must point it at the subject's rig.
    printf 'GC_DIR=%s\n' "${GC_DIR-<unset>}" >> "$CALLS"
    _al=$(printf '%s\n' "$*" | sed -n 's/.* --alias \([^ ]*\).*/\1/p')
    # gascity checks an alias and creates the session holding it inside one
    # city-wide lock, and refuses an alias an open session holds before creating
    # anything, on stderr, with the sentinel "session alias already exists".
    if [ -n "${ALIAS_REGISTRY:-}" ]; then
      # The concurrent race. Each spawn first waits at a barrier until
      # $SPAWN_BARRIER spawns have arrived, so every engage has passed its
      # pre-spawn guards before any reserves; then the alias is checked and
      # taken under one lock. The first spawn holds it; a later one is refused.
      stub_lock "$ALIAS_REGISTRY/lock"
      _arr=$(( $(cat "$ALIAS_REGISTRY/arrivals" 2>/dev/null || echo 0) + 1 ))
      printf '%s' "$_arr" > "$ALIAS_REGISTRY/arrivals"
      stub_unlock "$ALIAS_REGISTRY/lock"
      _i=0
      while [ "$(cat "$ALIAS_REGISTRY/arrivals")" -lt "${SPAWN_BARRIER:-1}" ] && [ "$_i" -lt 600 ]; do sleep 0.05; _i=$((_i + 1)); done
      stub_lock "$ALIAS_REGISTRY/lock"
      if [ -f "$ALIAS_REGISTRY/held.$_al" ]; then
        _holder=$(cat "$ALIAS_REGISTRY/held.$_al")
        stub_unlock "$ALIAS_REGISTRY/lock"
        echo "gc session new: session alias already exists: \"gc-toolkit/gc-toolkit.$_al\" already belongs to $_holder" >&2
        exit 1
      fi
      cat "$ALIAS_REGISTRY/arrivals" > "$ALIAS_REGISTRY/arrivals-at-reserve"
      _sid="gc-$$"
      printf '%s' "$_sid" > "$ALIAS_REGISTRY/held.$_al"
      stub_unlock "$ALIAS_REGISTRY/lock"
      printf 'spawned %s\n' "$_sid" >> "$CALLS"
      jq -n --arg id "$_sid" --arg n "s-$_sid" --arg a "gc-toolkit/gc-toolkit.$_al" '{schema_version:"1", ok:true, session_id:$id, session_name:$n, alias:$a, template:"t", transport:"tmux", work_dir:"/w", deferred_start:true, attached:false}'
      exit 0
    fi
    if [ -n "${ALIAS_HELD:-}" ]; then
      # Scripted: the session $ALIAS_HELD already holds the alias.
      : > "$ALIAS_REFUSED"
      echo "gc session new: session alias already exists: \"gc-toolkit/gc-toolkit.tk-conv\" already belongs to $ALIAS_HELD" >&2
      exit 1
    fi
    if [ -n "${SPAWN_EMPTY:-}" ]; then
      echo "gc session new: agent \"converse-opus\" not found in city.toml" >&2; jq -n '{ok:true}'
    elif [ -n "${ALIAS_COLLIDE:-}" ] && case "$*" in *"--alias c-"*) false ;; *) true ;; esac; then
      # ValidateAlias refuses an alias matching the session-id syntax (a gascity
      # all-numeric bead id, gc-62297) before any session spawns, wrapping the
      # sentinel "invalid session alias"; only the c- retry passes here.
      echo 'gc session new: invalid session alias: "gc-62297" conflicts with session ID syntax' >&2; jq -n '{ok:true}'
    else
      printf '%s' "$SID" > "$SPAWNED"
      # $DISMISS_ON_SPAWN: a dismiss closes that conversation while the spawn
      # runs, keeping its holder, as bd's close does.
      [ -n "${DISMISS_ON_SPAWN:-}" ] && printf 'closed' > "$ST/$DISMISS_ON_SPAWN.status"
      _qa="gc-toolkit/gc-toolkit.$_al"; [ -n "${SPAWN_NO_ALIAS:-}" ] && _qa=""
      printf '%s' "gc-toolkit/gc-toolkit.$_al" > "$ST/spawned-alias"
      jq -n --arg id "$SID" --arg n "$SNAME" --arg a "$_qa" '{schema_version:"1", ok:true, session_id:$id, session_name:$n, alias:$a, template:"t", transport:"tmux", work_dir:"/w", deferred_start:true, attached:false}'
    fi ;;
  "skill list")
    # The sitting's skill roster engage --skill resolves against; the --agent it
    # was asked about is recorded. Default: review-arch and review-pm, each
    # listed twice the way the live listing repeats a skill the city and the rig
    # both import, beside a core skill. $SKILL_AMBIG adds a second pack's
    # review-arch so the bare name is ambiguous; $SKILL_ROSTER_BROKEN fails the
    # listing, the fail-open path.
    printf 'skill list %s\n' "$*" >> "$CALLS"
    if [ -n "${SKILL_ROSTER_BROKEN:-}" ]; then echo "skill list: data plane down" >&2; exit 1; fi
    jq -n --arg amb "${SKILL_AMBIG:-}" \
      '{schema_version:"1", ok:true, agent:"a", entries:(
          [ "core.gc-work", "gc-toolkit.review-arch", "gc-toolkit.review-arch",
            "gc-toolkit.review-pm", "gc-toolkit.review-pm" ]
          + (if $amb != "" then ["contributing.review-arch"] else [] end)
          | map({name:., source:(split(".")[0]), path:("/skills/" + . + "/SKILL.md")}))}' ;;
  "session attach")
    # The attach returns when the tab's client exits. $ATTACH_ENDS is tk-conv's
    # status by then: closed for a sitting that ended under the tab,
    # in_progress for one the operator detached from. $ATTACH_UNREADABLE makes
    # every later read of tk-conv fail, and $ATTACH_FAIL fails the attach itself.
    printf 'session attach %s\n' "$*" >> "$CALLS"
    [ -n "${ATTACH_ENDS:-}" ] && printf '%s' "$ATTACH_ENDS" > "$ST/tk-conv.status"
    [ -n "${ATTACH_UNREADABLE:-}" ] && : > "$ST/tk-conv.unread"
    [ -n "${ATTACH_FAIL:-}" ] && { echo "gc session attach: session not found" >&2; exit 1; } ;;
  "session close")
    printf 'session close %s\n' "$*" >> "$CALLS"
    [ -n "${CLOSE_STICKS:-}" ] || { awk -v s="$3" '$1 != s' "$ST/live" > "$ST/live.tmp" 2>/dev/null; mv "$ST/live.tmp" "$ST/live" 2>/dev/null || true; } ;;
  "session nudge")
    printf 'session nudge %s\n' "$*" >> "$CALLS" ;;
  "bd update")
    printf 'bd update %s\n' "$*" >> "$CALLS"
    _id="$3"; shift 3
    _ifa_set=0; _ifa=""; _ifs_set=0; _ifs=""; _new_set=0; _new=""; _notes=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --if-assignee) _ifa_set=1; _ifa="${2-}"; shift 2 ;;
        --if-status)   _ifs_set=1; _ifs="${2-}"; shift 2 ;;
        --assignee)    _new_set=1; _new="${2-}"; shift 2 ;;
        --append-notes) _notes=1; shift 2 ;;
        *) shift ;;
      esac
    done
    # bd's --if-assignee and --if-status guards, checked and written under one
    # lock, as the store does: a mismatch writes nothing and exits 13.
    # $RACE_LOST makes the guard lose: another writer took the conversation in
    # the spawn window, recorded as $RACE_WINNER (empty for none) with status
    # $RACE_STATUS. $BIND_FAIL fails it for another reason, $BIND_NOPERSIST
    # reports success and writes nothing, $BIND_STOMP overwrites the binding
    # just written, and $CLOSE_AFTER_BIND closes the conversation just after
    # it, as a dismiss landing between the bind and its read-back does.
    if [ "$_ifa_set" = 1 ]; then
      if [ -n "${RACE_LOST:-}" ]; then
        printf '%s' "${RACE_WINNER-gc-toolkit/gc-toolkit.tk-conv-elsewhere}" > "$ST/$_id.assignee"
        [ -n "${RACE_STATUS:-}" ] && printf '%s' "$RACE_STATUS" > "$ST/$_id.status"
        exit 13
      fi
      [ -n "${BIND_FAIL:-}" ] && exit 1
      [ -n "${BIND_NOPERSIST:-}" ] && exit 0
      stub_lock "$ST/$_id.lock"
      _cur="$(cat "$ST/$_id.assignee" 2>/dev/null || printf 'human')"
      if [ "$_cur" != "$_ifa" ]; then stub_unlock "$ST/$_id.lock"; exit 13; fi
      if [ "$_ifs_set" = 1 ] && [ "$(stat_of "$_id")" != "$_ifs" ]; then stub_unlock "$ST/$_id.lock"; exit 13; fi
      [ "$_new_set" = 1 ] && printf '%s' "$_new" > "$ST/$_id.assignee"
      stub_unlock "$ST/$_id.lock"
      [ -n "${BIND_STOMP:-}" ] && printf '%s' "$BIND_STOMP" > "$ST/$_id.assignee"
      [ -n "${CLOSE_AFTER_BIND:-}" ] && printf 'closed' > "$ST/$_id.status"
      exit 0
    fi
    [ "$_new_set" = 1 ] && printf '%s' "$_new" > "$ST/$_id.assignee"
    exit 0 ;;
  "bd create")
    printf 'bd create %s\n' "$*" >> "$CALLS"
    # open files a conversation (a task that tracks its bead, --deps tracks:);
    # --new-subject creates the SUBJECT bead (with --db). The deps tell them
    # apart. $SUBJ_CREATE_FAIL makes the subject create fail.
    case "$*" in
      *"--deps tracks:"*)
        _p=""; for a in "$@"; do
          case "$_p" in
            --deps) printf '%s' "${a#tracks:}" > "$ST/tk-new.subject" ;;
            --assignee) printf '%s' "$a" > "$ST/tk-new.assignee" ;;
          esac
          _p="$a"
        done
        jq -n '{id:"tk-new"}' ;;
      *)
        if [ -n "${SUBJ_CREATE_FAIL:-}" ]; then jq -n '{error:"store write refused"}'
        else jq -n --arg i "${NEW_SUBJECT_ID:-tk-newsubj}" '{id:$i}'; fi ;;
    esac ;;
  "bd close")
    printf 'bd close %s\n' "$*" >> "$CALLS" ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

# --- clock stubs --------------------------------------------------------------
# engage's start wait reads the time with `date +%s` and sleeps a second between
# listings. With $FAKE_CLOCK naming a file, `date +%s` prints the epoch second
# the file holds, and a whole-second `sleep N` returns at once and moves that
# clock N times ${FAKE_CLOCK_SCALE:-1} seconds on, so a case can wait minutes in
# a few listings. Without it, and for every other argument, both are the real
# commands.
REAL_DATE=$(command -v date); REAL_SLEEP=$(command -v sleep)
cat > "$TMP/bin/date" <<EOF
#!/bin/sh
if [ -n "\${FAKE_CLOCK:-}" ] && [ "\$*" = "+%s" ]; then cat "\$FAKE_CLOCK"; exit 0; fi
exec "$REAL_DATE" "\$@"
EOF
cat > "$TMP/bin/sleep" <<EOF
#!/bin/sh
[ -n "\${FAKE_CLOCK:-}" ] || exec "$REAL_SLEEP" "\$@"
case "\${1:-}" in ''|*[!0-9]*) exec "$REAL_SLEEP" "\$@" ;; esac
echo \$(( \$(cat "\$FAKE_CLOCK") + \$1 * \${FAKE_CLOCK_SCALE:-1} )) > "\$FAKE_CLOCK"
EOF
chmod +x "$TMP/bin/date" "$TMP/bin/sleep"
# reps <token> <n> — the token n times over, for a START_STATES walk.
reps() { _r=""; _n=0; while [ "$_n" -lt "$2" ]; do _r="$_r $1"; _n=$((_n + 1)); done; printf '%s' "$_r"; }

export PATH="$TMP/bin:$PATH"
export CALLS="$TMP/calls" STATE_DIR="$TMP/state" ALIAS_REFUSED="$TMP/alias-refused"
export SPAWNED="$TMP/spawned" POLLS="$TMP/polls"
unset GC_HELM_FIXTURE || true
# The START-BACKSTOP case reads the default bound, and only a case's own prefix
# runs the clock stubs fake or picks the signal an interrupted case sends.
unset GC_HELM_ENGAGE_WAIT_TIMEOUT FAKE_CLOCK FAKE_CLOCK_SCALE INTERRUPT_SIG || true
export TMPDIR="$TMP"

# A fixture agents dir, so the converse-<model> list engage globs is hermetic —
# independent of the repo's live agents/. A bare `converse` is present to prove
# it is EXCLUDED from the model list.
mkdir -p "$TMP/agents/converse-opus" "$TMP/agents/converse-fable" \
         "$TMP/agents/converse-codex" "$TMP/agents/converse"
export GC_HELM_AGENTS_DIR="$TMP/agents"

# The subject rig's checkout. Converse CAPABILITY comes from the resolved roster
# (gc agent list), not a glob of this tree, so these converse-* dirs do not gate
# engage — they stay only as a realistic checkout. $TMP/rig-bare is a checkout
# with NO converse templates but a .beads ledger: the importer case proves
# engage still proceeds from it when the roster registers converse.
mkdir -p "$TMP/rig/agents/converse-opus" "$TMP/rig/agents/converse-fable" \
         "$TMP/rig/agents/converse-codex" "$TMP/rig/.beads" \
         "$TMP/rig-bare" "$TMP/rig-bare/.beads"
export RIG_PATH="$TMP/rig"

# A recorder standing in for pr-sitting-comment.sh, to prove engage posts the
# "open" reminder for the bead the conversation tracks.
cat > "$TMP/rec-psc" <<'REC'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$REC_PSC_LOG"
REC
chmod +x "$TMP/rec-psc"
export GC_SITTING_COMMENT_TOOL="$TMP/rec-psc" REC_PSC_LOG="$TMP/psc.log"

# reset — a clean store for a case: every conversation in the queue, open, no
# reply, no live sitting but the ones $LIVE_SITTINGS seeds ("<sid>=<alias> ...").
reset() {
    : > "$CALLS"; : > "$SPAWNED"; : > "$POLLS"; : > "$TMP/psc.log"
    rm -f "$ALIAS_REFUSED" "$ALIAS_REFUSED.reads"
    find "${STATE_DIR:?}" -type f \( -name '*.assignee' -o -name '*.status' -o -name '*.subject' -o -name '*.meta' -o -name '*.reason' -o -name '*.unread' -o -name spawned-alias -o -name tracks-reads -o -name live-polls \) -delete
    printf '1700000000' > "$TMP/clock"
    : > "$STATE_DIR/replies"; : > "$STATE_DIR/live"
    for _l in ${LIVE_SITTINGS:-}; do printf '%s %s\n' "${_l%%=*}" "${_l#*=}" >> "$STATE_DIR/live"; done
    return 0
}
# held <conversation> <assignee> [status] — seed a conversation's holder.
held() { printf '%s' "$2" > "$STATE_DIR/$1.assignee"; printf '%s' "${3:-in_progress}" > "$STATE_DIR/$1.status"; }
asg()  { cat "$STATE_DIR/$1.assignee" 2>/dev/null || printf 'human'; }

# run_engage <bead> [extra-args...] -> RC/OUT/CALLED. stdin is /dev/null so the
# run is non-interactive regardless of the terminal the suite runs from. It does
# not reset the store, so a case can seed a holder first; call reset before it.
run_engage() {
    set +e
    OUT="$(sh "$SCRIPT" engage "$@" </dev/null 2>"$TMP/err")"; RC=$?
    set -e
    OUT="$OUT$(cat "$TMP/err")"
    CALLED="$(cat "$CALLS")"
}

# polls_read — how many listings the start wait has made, 0 before the first.
polls_read() { _p=$(cat "$POLLS" 2>/dev/null || true); printf '%s' "${_p:-0}"; }

# run_engage_interrupted <bead> [extra-args...] — run_engage, with a Ctrl-C sent
# once the start wait has read the sitting twice: SIGINT, or the signal
# $INTERRUPT_SIG names. Job control puts engage in a process group of its own,
# as a terminal puts its foreground job, and the signal goes to that whole
# group, as a terminal's Ctrl-C does. A shell that starts with a signal ignored
# cannot trap it, and a suite started in the background by a shell without job
# control inherits SIGINT ignored, so perl puts the default back for each
# signal a case sends before engage starts. The case's own bound turns a signal
# that never lands into a failure within a minute, not a hang.
run_engage_interrupted() {
    set +e
    set -m
    if command -v perl >/dev/null 2>&1; then
        GC_HELM_ENGAGE_WAIT_TIMEOUT=60 perl -e '$SIG{$_} = "DEFAULT" for qw(INT TERM HUP); exec @ARGV or die "exec: $!\n"' \
            sh "$SCRIPT" engage "$@" </dev/null >"$TMP/out" 2>"$TMP/err" &
    else
        GC_HELM_ENGAGE_WAIT_TIMEOUT=60 sh "$SCRIPT" engage "$@" </dev/null >"$TMP/out" 2>"$TMP/err" &
    fi
    _eng_pid=$!
    set +m
    _w=0
    while [ "$(polls_read)" -lt 2 ] && [ "$_w" -lt 1200 ] && kill -0 "$_eng_pid" 2>/dev/null; do
        sleep 0.05; _w=$((_w + 1))
    done
    kill -"${INTERRUPT_SIG:-INT}" -- "-$_eng_pid" 2>/dev/null
    wait "$_eng_pid"; RC=$?
    set -e
    OUT="$(cat "$TMP/out")$(cat "$TMP/err")"
    CALLED="$(cat "$CALLS")"
}

# run_engage_tty <printf-format-of-answers> [args...] -> RC/OUT. Drives the
# interactive prompts: GC_HELM_ASSUME_TTY forces the interactive path when stdin
# is a pipe, and the answers feed the reads in order. The answer string is a
# printf %b format, so lines are '\n'-separated.
run_engage_tty() {
    _ans="$1"; shift
    set +e
    OUT="$(printf '%b' "$_ans" | GC_HELM_ASSUME_TTY=1 sh "$SCRIPT" engage "$@" 2>"$TMP/err")"; RC=$?
    set -e
    OUT="$OUT$(cat "$TMP/err")"
    CALLED="$(cat "$CALLS")"
}

echo "# argument validation refuses before anything spawns"
reset; run_engage tk-conv --model bogus
eq "$RC" 2 "(MODEL) an unknown --model exits 2"
hasnt "$CALLED" "session new" "(MODEL) …and nothing was spawned"
reset; run_engage ""
eq "$RC" 2 "(NOARG) a missing bead-id exits 2"

echo "# engaging a conversation in the queue spawns a sitting named for it and binds it"
reset; run_engage tk-conv --no-attach
eq "$RC" 0 "(CONVID) engaging a queued conversation exits 0"
has "$CALLED" "session new converse-opus --alias tk-conv --no-attach --json" "(CONVID) spawns converse-opus --alias <conversation> --no-attach"
eq "$(asg tk-conv)" "gc-toolkit/gc-toolkit.tk-conv" "(BIND) the conversation is assigned to the sitting's qualified alias, the actor its claim runs as"
has "$CALLED" "bd update tk-conv --if-assignee human --if-status open --unset-metadata gc.session_id --unset-metadata gc.session_name --assignee gc-toolkit/gc-toolkit.tk-conv" "(BIND) …guarded on the holder and the status engage read, the operator's queue and open"
# Orphan recovery resolves a bead's owner from gc.session_id ahead of its
# assignee, so a pin an earlier sitting left beside the fresh binding would have
# it find that sitting dead and take the conversation from the fresh one. The
# bind drops both pins in the same guarded write.
bind_write=$(printf '%s\n' "$CALLED" | grep -- '--assignee gc-toolkit/gc-toolkit.tk-conv' || true)
has "$bind_write" "--unset-metadata gc.session_id --unset-metadata gc.session_name" \
    "(BIND-PINS) …and drops any session pin an earlier sitting left, in the same write"
has "$(cat "$TMP/psc.log")" "engage --sitting tk-conv --subject tk-subj" "(CONVID-PRCOMMENT) engage posts the open reminder on the bead the conversation tracks"
hasnt "$CALLED" "session nudge" "(NO-KICK) an opus sitting self-starts from its prompt and is not kicked"
hasnt "$OUT" "took the conversation" "(CONVID) an explicit conversation id is not reported as one engage chose"
has "$OUT" "✓ converse-opus on existing conversation tk-conv for tk-subj" "(CONVID) the summary names the conversation and its bead"
hasnt "$OUT" "visit" "(CONVID) engage's words name no visit"

echo "# --model selects the tier; codex is the one provider that keeps the kick"
reset; run_engage tk-conv --model codex --no-attach
has "$CALLED" "session new converse-codex --alias tk-conv" "(MODELFLAG) --model codex spawns converse-codex"
has "$CALLED" "session nudge gc-77" "(KICK-CODEX) a codex sitting is sent its START-directive opening turn"
has "$CALLED" "Begin now: claim your conversation (tk-conv)" "(KICK-CODEX) …as a START directive naming its conversation"

echo "# engage supplies the subject's rig context so a bare template resolves"
reset
set +e
OUT="$(cd "$TMP" && sh "$SCRIPT" engage tk-conv --no-attach 2>"$TMP/err")"; RC=$?
set -e
CALLED="$(cat "$CALLS")"
eq "$RC" 0 "(RIGCTX) engaging from a non-rig cwd exits 0"
has "$CALLED" "GC_DIR=$TMP/rig" "(RIGCTX) session new runs under the subject's rig via GC_DIR, not the ambient cwd"

echo "# engaging a bead takes its conversation from the queue"
reset; run_engage tk-subj --no-attach
eq "$RC" 0 "(SUBJECT) engaging a bead with a queued conversation exits 0"
hasnt "$CALLED" "bd create" "(SUBJECT) …files nothing"
has "$CALLED" "session new converse-opus --alias tk-conv --no-attach --json" "(SUBJECT) …and spawns for that conversation"
has "$OUT" 'took the conversation "an earlier concern" already on tk-subj' "(SUBJECT) …saying which conversation it took"
has "$OUT" "engage tk-subj --reason" "(SUBJECT) …and offering --reason to open a fresh one instead"

echo "# a bead with no conversation gets one filed in the queue, then held"
export HAVE_CONV=0
reset; run_engage tk-subj --no-attach
eq "$RC" 0 "(SUBJECT-NONE) engaging a bead with no conversation exits 0"
has "$CALLED" "bd create" "(SUBJECT-NONE) …a conversation is filed"
has "$CALLED" "--deps tracks:tk-subj" "(SUBJECT-NONE) …tracking the bead"
has "$CALLED" "--assignee human" "(SUBJECT-NONE) …in the operator's queue"
has "$CALLED" "session new converse-opus --alias tk-new" "(SUBJECT-NONE) …then a sitting is spawned named for it"
eq "$(asg tk-new)" "gc-toolkit/gc-toolkit.tk-new" "(SUBJECT-NONE) …and the new conversation is bound to it"
has "$OUT" "✓ converse-opus on new conversation tk-new for tk-subj" "(SUBJECT-NONE) the summary names it new"
hasnt "$OUT" "no session spawned" "(SUBJECT-NONE) open's own success chatter is not repeated"

echo "# a conversation another open files after engage's listing is the one engage takes"
reset; CONV_FILED_AFTER=1 run_engage tk-subj --no-attach
eq "$RC" 0 "(JOIN-RACE) engaging a bead whose conversation another open filed in the meantime exits 0"
hasnt "$CALLED" "bd create" "(JOIN-RACE) …filing no second conversation"
has "$CALLED" "session new converse-opus --alias tk-conv --no-attach --json" "(JOIN-RACE) …and spawning the sitting for the queued one"
eq "$(asg tk-conv)" "gc-toolkit/gc-toolkit.tk-conv" "(JOIN-RACE) …bound to it"
has "$OUT" "✓ converse-opus on existing conversation tk-conv for tk-subj" "(JOIN-RACE) the summary names it as one that already existed"
unset HAVE_CONV

echo "# --reason files a fresh conversation for a distinct concern, even when one waits"
reset; run_engage tk-subj --reason "a distinct concern" --no-attach
eq "$RC" 0 "(REASON-NEW) engaging a bead with a conversation WITH --reason exits 0"
has "$CALLED" "bd create" "(REASON-NEW) …a NEW conversation is filed"
has "$CALLED" "--title a distinct concern" "(REASON-NEW) …titled with the reason"
has "$CALLED" "-d a distinct concern" "(REASON-NEW) …and asking it"
has "$CALLED" "session new converse-opus --alias tk-new" "(REASON-NEW) …then a sitting is spawned for it"
hasnt "$OUT" "took the conversation" "(REASON-NEW) …no took-an-existing hint"
reset; run_engage tk-subj --reason "a distinct concern" --model codex --no-attach
has "$CALLED" "The operator's reason: a distinct concern" "(REASON-CODEX) the reason rides the codex opening-turn kick"

echo "# --reason on an explicit conversation id is refused"
reset; run_engage tk-conv --reason "some reason" --no-attach
eq "$RC" 2 "(CONVID-REASON) --reason with an explicit conversation id exits 2"
hasnt "$CALLED" "session new" "(CONVID-REASON) …nothing is spawned"
hasnt "$CALLED" "bd create" "(CONVID-REASON) …and nothing filed"
has "$OUT" "--reason" "(CONVID-REASON) …the message explains the flag conflict"

echo "# a conversation a live sitting holds is attached to, not doubled"
export LIVE_SITTINGS="gc-50=gc-toolkit/gc-toolkit.tk-conv"
reset; held tk-conv gc-toolkit/gc-toolkit.tk-conv
run_engage tk-subj --no-attach
eq "$RC" 0 "(LIVE) engaging a bead whose conversation a live sitting holds exits 0"
hasnt "$CALLED" "session new" "(LIVE) …spawning no second sitting"
hasnt "$CALLED" "bd update" "(LIVE) …and binding nothing"
has "$OUT" "the live sitting gc-50 holds conversation tk-conv for tk-subj" "(LIVE) …naming the live sitting"
has "$OUT" "gc session attach gc-50" "(LIVE) …and how to attach to it"
hasnt "$CALLED" "session attach" "(LIVE) --no-attach attaches nothing"
reset; held tk-conv gc-toolkit/gc-toolkit.tk-conv
run_engage tk-subj
has "$CALLED" "session attach gc-50" "(LIVE-ATTACH) the default attaches the operator to the live sitting"
hasnt "$OUT" "waiting for the reconciler" "(LIVE-ATTACH) …a started one at once, with no wait announced"

echo "# a live sitting engage reuses is attached only once the reconciler has started it"
# A sitting is live from the spawn that created it, so one an earlier
# `engage --no-attach` spawned can still read start-pending or creating when
# another engage reuses it. An attach then would launch it from its stored
# command without the converse prompt, so the reuse waits as a new sitting's
# attach does.
reset; held tk-conv gc-toolkit/gc-toolkit.tk-conv
GC_HELM_ENGAGE_WAIT_TIMEOUT=2 LIVE_STATES="start-pending" run_engage tk-subj
eq "$RC" 4 "(REUSE-PENDING) reusing a live sitting that does not start within the wait exits 4: the engage put no sitting in front of the operator"
hasnt "$CALLED" "session attach" "(REUSE-PENDING) …and is NOT attached, since the attach would launch it without its prompt"
hasnt "$CALLED" "session new" "(REUSE-PENDING) …spawning no second sitting"
has "$OUT" "has not started s-gc-50 after 2s" "(REUSE-PENDING) …saying the reconciler has not started it"
has "$OUT" "start-pending" "(REUSE-PENDING) …naming the state it last read"
has "$OUT" "Attach once it reads active there: gc session attach gc-50" "(REUSE-PENDING) …and giving the attach to run once it is up"
reset; held tk-conv gc-toolkit/gc-toolkit.tk-conv
GC_HELM_ENGAGE_WAIT_TIMEOUT=2 LIVE_STATES="creating" run_engage tk-subj
hasnt "$CALLED" "session attach" "(REUSE-CREATING) a reused sitting still creating is not attached either"
has "$OUT" "creating" "(REUSE-CREATING) …naming the state it last read"
reset; held tk-conv gc-toolkit/gc-toolkit.tk-conv
LIVE_STATES="start-pending start-pending start-pending start-pending start-pending active" run_engage tk-subj
eq "$RC" 0 "(REUSE-WAIT) reusing a live sitting that starts during the wait exits 0"
has "$OUT" "waiting for the reconciler to start s-gc-50" "(REUSE-WAIT) …announcing the wait"
last_poll=$(printf '%s\n' "$CALLED" | grep -n '^session list' | tail -1 | cut -d: -f1 || true)
attach_line=$(printf '%s\n' "$CALLED" | grep -n '^session attach' | head -1 | cut -d: -f1 || true)
if [ -n "$last_poll" ] && [ -n "$attach_line" ] && [ "$last_poll" -lt "$attach_line" ]; then
  ok "(REUSE-WAIT) …and attaching only after the listing that reads it active"
else
  bad "(REUSE-WAIT) expected the last listing (line ${last_poll:-none}) before the attach (line ${attach_line:-none})"
fi
reset; held tk-conv gc-toolkit/gc-toolkit.tk-conv
GC_HELM_ENGAGE_WAIT_TIMEOUT=60 LIVE_STATES="start-pending start-pending start-pending start-pending gone" run_engage tk-subj
eq "$RC" 4 "(REUSE-ENDED) a reused sitting that ends before it starts exits 4"
hasnt "$CALLED" "session attach" "(REUSE-ENDED) …without attaching"
has "$OUT" "ended before the reconciler started it" "(REUSE-ENDED) …saying it ended"
has "$OUT" "gc-helm engage tk-subj" "(REUSE-ENDED) …and pointing at the engage that starts a sitting on it"
reset; held tk-conv gc-toolkit/gc-toolkit.tk-conv
GC_HELM_ENGAGE_WAIT_TIMEOUT=60 LIVE_STATES="start-pending" run_engage tk-subj --no-attach
eq "$RC" 0 "(REUSE-NOATTACH) --no-attach on a reused unstarted sitting exits 0"
hasnt "$OUT" "waiting for the reconciler" "(REUSE-NOATTACH) …without waiting, since it attaches nothing"
hasnt "$CALLED" "session attach" "(REUSE-NOATTACH) …and attaches nothing"

reset; held tk-conv gc-toolkit/gc-toolkit.tk-conv
run_engage tk-subj --reason "another angle" --no-attach
eq "$RC" 0 "(LIVE-CONCERN) a concern beside a live sitting still files its own conversation"
has "$CALLED" "session new converse-opus --alias tk-new" "(LIVE-CONCERN) …and spawns its own sitting"
has "$OUT" "warning: another live sitting is on tk-subj already — conversation tk-conv" "(WARN-LIVE) …warning of the live sitting beside it, not refusing"
unset LIVE_SITTINGS

echo "# a conversation whose sitting's session closed is resumed under the same alias"
# A closed session does not reserve its alias, so a new session under it takes
# the in-progress conversation as its own: no bind is needed.
reset; held tk-conv gc-toolkit/gc-toolkit.tk-conv
run_engage tk-subj --no-attach
eq "$RC" 0 "(LEFT) engaging a conversation left by a closed session exits 0"
has "$CALLED" "session new converse-opus --alias tk-conv" "(LEFT) …spawning a new sitting under the same alias"
hasnt "$CALLED" "bd update" "(LEFT) …with no bind, since it is already assigned to that alias"
eq "$(asg tk-conv)" "gc-toolkit/gc-toolkit.tk-conv" "(LEFT) …and the conversation stays assigned to the alias"

echo "# a session still holding the alias of a conversation back in the queue is closed first"
# A sitting cut short hands its conversation back to the queue and leaves its
# session for converse-reap. A session that is not closed keeps its alias, so
# engage closes it and reads it gone before spawning under the alias.
export LIVE_SITTINGS="gc-60=gc-toolkit/gc-toolkit.tk-conv"
reset; run_engage tk-subj --no-attach
eq "$RC" 0 "(CUT-SHORT) engaging a queued conversation beside its old session exits 0"
has "$CALLED" "session close gc-60" "(CUT-SHORT) …closing the old session that holds the alias"
case "$CALLED" in
  *"session close gc-60"*"session new converse-opus --alias tk-conv"*) ok "(CUT-SHORT) …before spawning under it" ;;
  *) bad "(CUT-SHORT) the close should precede the spawn (calls: $CALLED)" ;;
esac
reset; CLOSE_STICKS=1 run_engage tk-subj --no-attach
eq "$RC" 4 "(CUT-SHORT-STUCK) an old session that will not close exits 4"
hasnt "$CALLED" "session new" "(CUT-SHORT-STUCK) …spawning nothing"
has "$OUT" "gc session close gc-60" "(CUT-SHORT-STUCK) …and naming the session to close by hand"
unset LIVE_SITTINGS

echo "# a closed explicit conversation is refused without spawning"
reset; printf 'closed' > "$STATE_DIR/tk-conv.status"
run_engage tk-conv --no-attach
eq "$RC" 4 "(CLOSED) engaging a closed conversation exits 4"
hasnt "$CALLED" "session new" "(CLOSED) …and spawns nothing"
has "$OUT" "is not an open conversation about tk-subj" "(CLOSED) …saying it is not open"

echo "# engage pointed at a gate takes the one bead still waiting on it, and the conversation replies to the gate"
export GATE_WAITERS='[{"id":"tk-subj","status":"open","dependency_type":"blocks"},{"id":"tk-done","status":"closed","dependency_type":"blocks"}]'
reset; run_engage tk-gate --no-attach
eq "$RC" 0 "(GATE) engaging a gate with one open bead waiting on it exits 0"
has "$OUT" "tk-gate is a gate about tk-subj" "(GATE) …saying which bead it takes"
has "$CALLED" "bd dep bd dep add tk-conv tk-gate --type replies-to" "(GATE-REPLY-QUEUE) the conversation taken from the queue replies to the gate"
case "$CALLED" in
  *"--type replies-to"*"session new"*) ok "(GATE-REPLY-QUEUE) …before the sitting starts" ;;
  *) bad "(GATE-REPLY-QUEUE) the reply should precede the spawn (calls: $CALLED)" ;;
esac
has "$OUT" "conversation tk-conv for tk-subj" "(GATE) …and the sitting holds tk-subj's conversation"
export HAVE_CONV=0
reset; run_engage tk-gate --no-attach
eq "$RC" 0 "(GATE-NEW) a gate whose bead has no conversation exits 0"
has "$CALLED" "--deps tracks:tk-subj" "(GATE-NEW) …filing a conversation that tracks the waiting bead, never the gate"
hasnt "$CALLED" "--deps tracks:tk-gate" "(GATE-NEW) …no conversation tracks the gate"
has "$CALLED" "--title Approve the rollout" "(GATE-NEW) …titled with what the gate asks"
has "$CALLED" "bd dep bd dep add tk-new tk-gate --type replies-to" "(GATE-REPLY-NEW) …and the conversation it filed replies to the gate"
unset HAVE_CONV
export LIVE_SITTINGS="gc-50=gc-toolkit/gc-toolkit.tk-conv"
reset; held tk-conv gc-toolkit/gc-toolkit.tk-conv
run_engage tk-gate --no-attach
eq "$RC" 0 "(GATE-LIVE) a gate whose bead a live sitting holds exits 0"
has "$CALLED" "bd dep bd dep add tk-conv tk-gate --type replies-to" "(GATE-REPLY-LIVE) the live sitting's conversation replies to the gate"
hasnt "$CALLED" "session new" "(GATE-LIVE) …and engage attaches to it rather than spawning"
unset LIVE_SITTINGS
reset; REPLY_FAIL=1 run_engage tk-gate --no-attach
eq "$RC" 4 "(GATE-NOREPLY) a reply that does not read back exits 4"
hasnt "$CALLED" "session new" "(GATE-NOREPLY) …starting no sitting that would not know its gate"
has "$OUT" "gc bd dep add tk-conv tk-gate --type replies-to" "(GATE-NOREPLY) …and naming the edge to add by hand"

echo "# a gate two open beads wait on starts nothing and names both"
export GATE_WAITERS='[{"id":"tk-subj","status":"open"},{"id":"tk-child","status":"in_progress"}]'
reset; run_engage tk-gate --no-attach
eq "$RC" 4 "(GATE-TWO) a gate two open beads wait on exits 4"
has "$OUT" "tk-subj tk-child" "(GATE-TWO) …naming both, so the operator engages the one they mean"
hasnt "$CALLED" "bd create" "(GATE-TWO) …filing no conversation"
hasnt "$CALLED" "session new" "(GATE-TWO) …and starting no session"
export GATE_WAITERS='[{"id":"tk-subj","status":"closed"},{"id":"tk-child","status":"closed"}]'
reset; run_engage tk-gate --no-attach
eq "$RC" 4 "(GATE-NONE) a gate nothing waits on exits 4"
has "$OUT" "nothing waits on gate tk-gate" "(GATE-NONE) …saying nothing waits on it"
has "$OUT" "tk-subj tk-child" "(GATE-NONE) …naming the closed beads it was about"
hasnt "$CALLED" "session new" "(GATE-NONE) …and starting nothing"
unset GATE_WAITERS

echo "# a live sitting replying to a gate the bead waits on is warned about, never refused"
# The shared-gate variant: the anchor's sitting replies to the bring-current gate
# its rework child also waits on. Engaging the child files the child's own
# conversation, which tracks the child alone, and warns of the anchor's sitting.
export HAVE_CONV=0 CONV_SUBJECT=tk-child LIVE_SITTINGS="gc-50=gc-toolkit/gc-toolkit.tk-conv"
export BEAD_GATES='[{"id":"tk-gate","issue_type":"gate","await_type":"human","await_id":"bring-current","status":"open","title":"Rule on the merge-in","dependency_type":"blocks"}]'
export GATE_REPLIES='[{"id":"tk-conv","issue_type":"task","status":"in_progress","assignee":"gc-toolkit/gc-toolkit.tk-conv","dependency_type":"replies-to"}]'
reset; held tk-conv gc-toolkit/gc-toolkit.tk-conv
run_engage tk-child --no-attach
eq "$RC" 0 "(WARN-GATE) engaging the child beside the anchor's sitting exits 0"
has "$CALLED" "--deps tracks:tk-child" "(WARN-GATE) …filing the child's own conversation, which tracks the child alone"
has "$OUT" "tk-conv (replies to gate tk-gate)" "(WARN-GATE) …warning that a live sitting replies to a gate the child waits on"
has "$CALLED" "session new converse-opus --alias tk-new" "(WARN-GATE) …and still starting the child's sitting"
unset HAVE_CONV CONV_SUBJECT LIVE_SITTINGS BEAD_GATES GATE_REPLIES

echo "# a spawn that yields no identity aborts without binding"
reset; SPAWN_EMPTY=1 run_engage tk-conv --no-attach
eq "$RC" 4 "(NOSPAWN) a session with no identity exits 4"
eq "$(asg tk-conv)" "human" "(NOSPAWN) …and the conversation stays in the queue"

echo "# a conversation another writer takes in the spawn window is not overwritten"
# Run on codex, the one provider engage kicks: the abort precedes the kick
# block, so "never kicked" proves that order rather than passing vacuously.
reset; RACE_LOST=1 RACE_WINNER="gc-toolkit/gc-toolkit.tk-conv-x" run_engage tk-conv --model codex --no-attach
eq "$RC" 4 "(TAKEN) a bind lost to another writer exits 4"
has "$CALLED" "session new" "(TAKEN) …the sitting did spawn: the conversation changed after engage read it"
has "$CALLED" "bd update tk-conv --if-assignee human" "(TAKEN) …the bind is conditional, so the store rejects it (exit 13)"
eq "$(asg tk-conv)" "gc-toolkit/gc-toolkit.tk-conv-x" "(TAKEN) …the holder stays, never this engage's sitting"
has "$CALLED" "session close gc-77" "(TAKEN) …the sitting that holds nothing is closed"
has "$OUT" "not overwriting" "(TAKEN) …and the operator is told the holder was not overwritten"
hasnt "$CALLED" "session nudge" "(TAKEN) …and the closed codex sitting is never kicked"

echo "# a failed bind (not the race): the sitting spawned but nothing holds the conversation"
reset; BIND_FAIL=1 run_engage tk-conv --model codex --no-attach
eq "$RC" 4 "(BIND-FAIL) a failed bind exits 4"
has "$CALLED" "session close gc-77" "(BIND-FAIL) …the spawned sitting is closed, not left orphaned"
eq "$(asg tk-conv)" "human" "(BIND-FAIL) …the conversation stays in the queue"
hasnt "$CALLED" "session nudge" "(BIND-FAIL) …and the closed codex sitting is never kicked"

echo "# a bind another writer stomps: the read-back shows a different holder"
reset; BIND_STOMP="gc-toolkit/gc-toolkit.tk-conv-y" run_engage tk-conv --no-attach
eq "$RC" 4 "(STOMP) a stomped bind exits 4"
has "$CALLED" "session close gc-77" "(STOMP) …the stranded sitting is closed"
has "$OUT" "gc-toolkit/gc-toolkit.tk-conv-y" "(STOMP) …and the operator is told who holds it"

echo "# a bind that does not persist: the read-back finds the conversation still in the queue"
reset; BIND_NOPERSIST=1 run_engage tk-conv --no-attach
eq "$RC" 4 "(NOPERSIST) a non-persisting bind exits 4"
has "$CALLED" "session close gc-77" "(NOPERSIST) …the spawned sitting is closed"
has "$OUT" "the bind did not persist" "(NOPERSIST) …and the operator is told the bind did not persist"

echo "# a conversation a dismiss closes while the sitting spawns is not bound, and the sitting is closed"
# bd's close keeps the assignee, so the holder engage read still holds a
# dismissed conversation: only the status guard and the read-back tell a closed
# conversation, which no claim adopts. Run on codex, the one provider engage
# kicks, so "never kicked" proves the abort comes first.
reset; DISMISS_ON_SPAWN=tk-conv run_engage tk-conv --model codex --no-attach
eq "$RC" 4 "(DISMISSED-QUEUE) a queued conversation dismissed during the spawn exits 4"
has "$CALLED" "bd update tk-conv --if-assignee human --if-status open" "(DISMISSED-QUEUE) …the bind is guarded on the status engage read, so the store rejects it (exit 13)"
has "$OUT" "was closed while this sitting spawned" "(DISMISSED-QUEUE) …saying the conversation closed"
has "$CALLED" "session close gc-77" "(DISMISSED-QUEUE) …closing the sitting it spawned"
eq "$(asg tk-conv)/$(cat "$STATE_DIR/tk-conv.status")" "human/closed" "(DISMISSED-QUEUE) …and the conversation stays closed with the holder the dismiss left"
hasnt "$CALLED" "session nudge" "(DISMISSED-QUEUE) …and the closed codex sitting is never kicked"
hasnt "$OUT" "✓ converse-codex" "(DISMISSED-QUEUE) …never reporting a sitting"
export HAVE_CONV=0
reset; DISMISS_ON_SPAWN=tk-new run_engage tk-subj --no-attach
eq "$RC" 4 "(DISMISSED-NEW) a conversation engage filed, dismissed during the spawn, exits 4"
has "$CALLED" "bd update tk-new --if-assignee human --if-status open" "(DISMISSED-NEW) …its bind guarded on the queue and open, as open filed it"
has "$CALLED" "session close gc-77" "(DISMISSED-NEW) …and the sitting it spawned is closed"
unset HAVE_CONV
reset; held tk-conv gc-toolkit/gc-toolkit.tk-conv
DISMISS_ON_SPAWN=tk-conv run_engage tk-subj --model codex --no-attach
eq "$RC" 4 "(DISMISSED-LEFT) a conversation resumed under its own alias, dismissed during the spawn, exits 4"
hasnt "$CALLED" "bd update" "(DISMISSED-LEFT) …binding nothing, since it is already assigned to the alias"
has "$OUT" "reads closed" "(DISMISSED-LEFT) …its read-back finding it closed"
has "$CALLED" "session close gc-77" "(DISMISSED-LEFT) …and closing the sitting it spawned"
hasnt "$CALLED" "session nudge" "(DISMISSED-LEFT) …which is never kicked"
reset; held tk-conv gc-toolkit/gc-toolkit.c-tk-conv
run_engage tk-subj --no-attach
eq "$RC" 0 "(LEFT-REBIND) a conversation left under its c- alias, resumed under its bare id, exits 0"
has "$CALLED" "bd update tk-conv --if-assignee gc-toolkit/gc-toolkit.c-tk-conv --if-status in_progress --unset-metadata gc.session_id --unset-metadata gc.session_name --assignee gc-toolkit/gc-toolkit.tk-conv" "(LEFT-REBIND) …binding it guarded on the alias and the status its sitting left"
reset; held tk-conv gc-toolkit/gc-toolkit.c-tk-conv
DISMISS_ON_SPAWN=tk-conv run_engage tk-subj --no-attach
eq "$RC" 4 "(DISMISSED-LEFT-REBIND) that conversation dismissed during the spawn exits 4"
has "$OUT" "was closed while this sitting spawned" "(DISMISSED-LEFT-REBIND) …the status guard missing on the closed conversation"
eq "$(asg tk-conv)/$(cat "$STATE_DIR/tk-conv.status")" "gc-toolkit/gc-toolkit.c-tk-conv/closed" "(DISMISSED-LEFT-REBIND) …which keeps the holder the dismiss left"
has "$CALLED" "session close gc-77" "(DISMISSED-LEFT-REBIND) …and the sitting it spawned is closed"
reset; CLOSE_AFTER_BIND=1 run_engage tk-conv --no-attach
eq "$RC" 4 "(DISMISSED-AFTER-BIND) a conversation closed between the bind and its read-back exits 4"
has "$OUT" "reads closed" "(DISMISSED-AFTER-BIND) …the read-back finding it closed"
has "$CALLED" "session close gc-77" "(DISMISSED-AFTER-BIND) …and closing the sitting it spawned"

echo "# a spawn whose answer names no alias reads it from the session list"
reset; SPAWN_NO_ALIAS=1 run_engage tk-conv --no-attach
eq "$RC" 0 "(NOALIAS-JSON) a spawn with no alias in its answer still binds"
eq "$(asg tk-conv)" "gc-toolkit/gc-toolkit.tk-conv" "(NOALIAS-JSON) …to the alias the session list reports"

echo "# an engage refused at the alias waits for the winner's bind, then points at it"
# Of two engages of one conversation the second is refused at `gc session new`
# having spawned nothing. Its alias holder is the engage that won, about to bind
# the conversation. The refused engage waits for that bind; the bind lands on the
# second read, so an engage that read the conversation once would name the
# winner as left over and tell the operator to close it.
export ALIAS_HELD="gc-81" ALIAS_HOLDER="gc-81" AFTER_REFUSAL_READS=2 AFTER_REFUSAL_ASSIGNEE="gc-toolkit/gc-toolkit.tk-conv" GC_HELM_ENGAGE_BIND_WAIT=5
reset; run_engage tk-conv --model codex --no-attach
eq "$RC" 4 "(ALIAS-BOUND) an engage refused at the alias exits 4"
has "$CALLED" "session new converse-codex --alias tk-conv" "(ALIAS-BOUND) …after its spawn was refused"
has "$OUT" "held by 'gc-toolkit/gc-toolkit.tk-conv', bound while this engage was spawning" "(ALIAS-BOUND) …reporting the winner once its bind lands"
has "$OUT" "gc-helm engage tk-conv" "(ALIAS-BOUND) …and pointing the operator at engaging it, which attaches"
hasnt "$OUT" "gc session close" "(ALIAS-BOUND) …never telling them to close the sitting that won"
hasnt "$CALLED" "bd update" "(ALIAS-BOUND) …writing nothing to the conversation"
hasnt "$CALLED" "session close" "(ALIAS-BOUND) …closing nothing"
hasnt "$CALLED" "session nudge" "(ALIAS-BOUND) …and kicking nothing"
unset AFTER_REFUSAL_READS AFTER_REFUSAL_ASSIGNEE

echo "# a holder that never binds is named as left over, and closing it is suggested only then"
export ALIAS_DECOYS=1 GC_HELM_ENGAGE_BIND_WAIT=5
reset; run_engage tk-conv --no-attach
eq "$RC" 4 "(ALIAS-LEFTOVER) a holder that never binds exits 4"
has "$OUT" "did not bind it within 5s" "(ALIAS-LEFTOVER) …after waiting for a bind that never came"
has "$OUT" "gc session close gc-81" "(ALIAS-LEFTOVER) …naming the holder to close"
has "$OUT" "If no other engage of tk-conv is still running" "(ALIAS-LEFTOVER) …only on the condition that no engage is still binding it"
hasnt "$OUT" "gc-90" "(ALIAS-LEFTOVER) …never another conversation's sitting whose alias shares the prefix"
hasnt "$OUT" "gc-91" "(ALIAS-LEFTOVER) …nor a closed sitting that once held the alias"
hasnt "$CALLED" "session close" "(ALIAS-LEFTOVER) …and it closes nothing itself"
unset ALIAS_HOLDER

echo "# an alias holder gone by the end of the wait: re-run"
reset; run_engage tk-conv --no-attach
eq "$RC" 4 "(ALIAS-GONE) an alias no open session holds any more exits 4"
has "$OUT" "no open session holds it now" "(ALIAS-GONE) …saying the holder is gone"
has "$OUT" "re-run" "(ALIAS-GONE) …and that a re-run will spawn"
hasnt "$OUT" "gc session close" "(ALIAS-GONE) …with nothing to close"
unset ALIAS_DECOYS

echo "# a conversation closed during the wait is reported, not attached to"
export AFTER_REFUSAL_READS=1 AFTER_REFUSAL_STATUS=closed
reset; run_engage tk-conv --no-attach
eq "$RC" 4 "(ALIAS-CLOSED) a conversation closed while the engage waited exits 4"
has "$OUT" "closed while this engage was spawning" "(ALIAS-CLOSED) …saying so"
hasnt "$OUT" "gc session close" "(ALIAS-CLOSED) …and naming nothing to close"
unset AFTER_REFUSAL_READS AFTER_REFUSAL_STATUS

echo "# a conversation unreadable through the wait is no proof the holder is left over"
export ALIAS_HOLDER="gc-81" AFTER_REFUSAL_UNREADABLE=1
reset; run_engage tk-conv --no-attach
eq "$RC" 4 "(ALIAS-UNREAD) an unreadable conversation exits 4"
has "$OUT" "could not be read" "(ALIAS-UNREAD) …saying it could not be read"
hasnt "$OUT" "gc session close" "(ALIAS-UNREAD) …and never telling the operator to close the holder"
unset ALIAS_HELD ALIAS_HOLDER AFTER_REFUSAL_UNREADABLE GC_HELM_ENGAGE_BIND_WAIT

echo "# two concurrent engages of one conversation: the alias admits one, and the other spawns nothing"
# A real race, not a scripted one. Both engages start together, and the stub's
# spawn holds each at a barrier until both have arrived, so both have read the
# conversation in the queue and passed every pre-spawn guard before either
# reserves anything. The stub then reserves the alias under one lock, as gascity
# does, and runs every bind as bd's compare-and-swap under one lock.
REG="$TMP/alias-registry"; rm -rf "$REG"; mkdir -p "$REG"
reset
set +e
for r in a b; do
  ( ALIAS_REGISTRY="$REG" SPAWN_BARRIER=2 \
      sh "$SCRIPT" engage tk-conv --no-attach --no-input </dev/null >"$TMP/race-$r.out" 2>&1
    echo "$?" > "$TMP/race-$r.rc" ) &
done
wait
set -e
RC_A="$(cat "$TMP/race-a.rc")"; RC_B="$(cat "$TMP/race-b.rc")"
CALLED="$(cat "$CALLS")"
eq "$(cat "$REG/arrivals-at-reserve" 2>/dev/null)" "2" "(RACE-CONCURRENT) both engages had passed the pre-spawn guards when the first reserved the alias"
eq "$(grep -c '^session new ' "$CALLS" || true)" "2" "(RACE-CONCURRENT) both engages attempted the spawn"
eq "$(grep -c '^spawned ' "$CALLS" || true)" "1" "(RACE-CONCURRENT) exactly one sitting was spawned"
LOSER=""
if [ "$RC_A" = 0 ] && [ "$RC_B" = 4 ]; then LOSER=b; elif [ "$RC_A" = 4 ] && [ "$RC_B" = 0 ]; then LOSER=a; fi
[ -n "$LOSER" ] && ok "(RACE-CONCURRENT) one engage succeeds and the other exits 4" \
  || bad "(RACE-CONCURRENT) expected one engage to exit 0 and the other 4 (got a=$RC_A b=$RC_B)"
eq "$(asg tk-conv)" "gc-toolkit/gc-toolkit.tk-conv" "(RACE-CONCURRENT) the conversation is bound once, to the sitting that was spawned"
eq "$(grep -c 'bd update tk-conv --if-assignee' "$CALLS" || true)" "1" "(RACE-CONCURRENT) only the winner writes the conversation; the refused engage never reaches the bind"
LOSER_OUT="$(cat "$TMP/race-${LOSER:-b}.out")"
has "$LOSER_OUT" "held by 'gc-toolkit/gc-toolkit.tk-conv'" "(RACE-CONCURRENT) the refused engage reports the winner's hold"
hasnt "$LOSER_OUT" "gc session close" "(RACE-CONCURRENT) …and never tells them to close it"
hasnt "$CALLED" "session close" "(RACE-CONCURRENT) no sitting is closed, because none was spawned that holds nothing"

echo "# two conversations in the queue: engage takes the oldest"
export HAVE_CONV=2
reset; run_engage tk-subj --no-attach
eq "$RC" 0 "(MULTI) a bead with two queued conversations exits 0"
has "$CALLED" "session new converse-opus --alias tk-conv --no-attach" "(MULTI) …taking the oldest, the first the queue offers"
unset HAVE_CONV

echo "# a task assigned to human that tracks the bead and another is no conversation"
# A conversation tracks exactly one bead (conversation.sh), and its sign-off
# refuses any other task, so engage never binds a sitting to the two-bead task,
# though it is older than the real conversation beside it.
export HAVE_CONV=two
reset; run_engage tk-subj --no-attach
eq "$RC" 0 "(TWO-TRACKS) a bead with a two-bead task beside its queued conversation exits 0"
has "$CALLED" "session new converse-opus --alias tk-conv --no-attach" "(TWO-TRACKS) …taking the real conversation"
hasnt "$CALLED" "tk-two" "(TWO-TRACKS) …and neither spawning for nor binding the two-bead task"
unset HAVE_CONV

echo "# a candidate whose own row does not read is not guessed a conversation"
reset; LIST_DROPS=tk-conv run_engage tk-subj --no-attach
eq "$RC" 4 "(UNREAD) a conversation candidate whose own row does not read exits 4"
hasnt "$CALLED" "session new" "(UNREAD) …spawning nothing"
hasnt "$CALLED" "bd update" "(UNREAD) …and binding nothing"
has "$OUT" "could not read the conversations on tk-subj" "(UNREAD) …naming the read"

echo "# a spawn failure carries gc's reason"
reset; SPAWN_EMPTY=1 run_engage tk-conv --no-attach
eq "$RC" 4 "(SPAWN-WHY) a spawn that yields no identity exits 4"
has "$OUT" "gc said: gc session new: agent" "(SPAWN-WHY) …quoting gc's stderr"
has "$OUT" "rig-scoped" "(SPAWN-WHY) …and explaining the rig-scoped template"
hasnt "$CALLED" "--alias c-" "(SPAWN-WHY) …a non-alias spawn failure is not retried under a c- prefix"

echo "# a conversation id the runtime refuses as an alias is retried once under c-"
# gascity session ids match ^gc-[0-9]+$, and ValidateAlias refuses any alias that
# does, so a conversation on the gascity rig with an all-numeric id cannot be the
# bare --alias. engage retries under a c- prefix no ValidateAlias rule can match.
reset; ALIAS_COLLIDE=1 run_engage tk-conv --no-attach
eq "$RC" 0 "(ALIAS-RETRY) a rejected bare alias is retried and engage exits 0"
has "$CALLED" "session new converse-opus --alias tk-conv --no-attach --json" "(ALIAS-RETRY) …the bare conversation id is tried first"
has "$CALLED" "session new converse-opus --alias c-tk-conv --no-attach --json" "(ALIAS-RETRY) …then retried under a c- prefix"
eq "$(asg tk-conv)" "gc-toolkit/gc-toolkit.c-tk-conv" "(ALIAS-RETRY) …and the conversation binds to the retried sitting's alias"

# run_fresh / run_fresh_tty — a clean store, then run_engage / run_engage_tty.
run_fresh()     { reset; run_engage "$@"; }
run_fresh_tty() { reset; run_engage_tty "$@"; }

echo "# a bead whose prefix names no rig is refused before anything runs"
run_fresh zz-subj --no-attach
eq "$RC" 4 "(NORIG) an unknown prefix exits 4"
has "$OUT" "matches no rig" "(NORIG) …saying so"
hasnt "$CALLED" "session new" "(NORIG) …and spawns nothing"

echo "# a subject whose rig carries no converse is refused with no side effect"
# An HQ / city-store root carries no converse in the resolved roster, so no
# converse sitting could spawn there. engage refuses BEFORE it files a conversation
# or exports GC_RIG, rather than half-acting and failing at the spawn. Capability is
# read from the roster (gc agent list), not the checkout — $NO_CONVERSE makes the
# roster show gc-toolkit without converse (a proactive-only entry remains, to
# prove the guard is converse-specific).
export NO_CONVERSE=1
run_fresh tk-conv --no-attach
eq "$RC" 4 "(NOCONVERSE) a rig with no converse exits 4"
has "$OUT" "carries no converse template" "(NOCONVERSE) …saying why"
hasnt "$CALLED" "session new" "(NOCONVERSE) …spawning nothing"
hasnt "$CALLED" "bd create" "(NOCONVERSE) …filing no conversation"
hasnt "$CALLED" "bd update" "(NOCONVERSE) …binding nothing"
unset NO_CONVERSE

echo "# an importer whose CHECKOUT holds no converse template is still engageable (roster-sourced)"
# The regression: capability must come from the import-resolved roster,
# not a glob of the rig's checkout. Only the pack-source rig keeps agents/converse-*
# in its tree; every importer obtains converse through the roster. $TMP/rig-bare is
# a checkout with no converse templates, yet the default roster registers converse
# for gc-toolkit — so engage clears the converse guard and spawns, where the old
# glob predicate would have refused.
export RIG_PATH="$TMP/rig-bare"
run_fresh tk-conv --no-attach
eq "$RC" 0 "(IMPORTER) an importer with converse in the roster but not the checkout engages"
has "$CALLED" "session new converse-opus --alias tk-conv" "(IMPORTER) …spawning the converse sitting"
export RIG_PATH="$TMP/rig"

echo "# attach behaviour: default attaches, --no-attach does not"
run_fresh tk-conv --no-attach
hasnt "$CALLED" "session attach" "(ATTACH) --no-attach does not attach"
run_fresh tk-conv
has "$CALLED" "session attach gc-77" "(ATTACH) the default attaches to the captured session id"
hasnt "$CALLED" "session nudge" "(ATTACH) …and an opus sitting is not kicked; it self-starts before the operator lands"

echo "# for codex (the kicked provider), the kick precedes the attach"
# attach is a foreground handoff to the pane: nothing after it in cmd_engage runs
# until the operator detaches, so a codex kick sent after the attach would never
# fire and the operator would land on a blank pane.
run_fresh tk-conv --model codex
nudge_line=$(printf '%s\n' "$CALLED" | grep -n "session nudge" | head -1 | cut -d: -f1)
attach_line=$(printf '%s\n' "$CALLED" | grep -n "session attach" | head -1 | cut -d: -f1)
if [ -n "$nudge_line" ] && [ -n "$attach_line" ] && [ "$nudge_line" -lt "$attach_line" ]; then
  ok "(KICK-ORDER) the codex opening turn is sent before the attach"
else
  bad "(KICK-ORDER) expected nudge (line ${nudge_line:-none}) before attach (line ${attach_line:-none})"
fi

echo "# the attach waits for the reconciler to start the sitting"
# `gc session attach` on a sitting the reconciler has not launched yet launches it
# itself, with no prompt, and the sitting idles until someone types into it. So
# the attach path polls the sitting's state in `gc session list` and attaches
# only once it reads active, never while it is start-pending or creating.
run_fresh tk-conv
eq "$(cat "$POLLS")" 1 "(START-ACTIVE) a sitting already started is read once"
hasnt "$OUT" "waiting for the reconciler" "(START-ACTIVE) …and attached with no wait announced"

START_STATES="start-pending creating active" run_fresh tk-conv
eq "$RC" 0 "(START-WAIT) an engage whose sitting starts on the third listing exits 0"
eq "$(cat "$POLLS")" 3 "(START-WAIT) …reading the sitting until it reads active"
last_poll=$(printf '%s\n' "$CALLED" | grep -n '^session list' | tail -1 | cut -d: -f1 || true)
attach_line=$(printf '%s\n' "$CALLED" | grep -n '^session attach' | head -1 | cut -d: -f1 || true)
if [ -n "$last_poll" ] && [ -n "$attach_line" ] && [ "$last_poll" -lt "$attach_line" ]; then
  ok "(START-WAIT) …and attaching only after the listing that reads it active"
else
  bad "(START-WAIT) expected the last listing (line ${last_poll:-none}) before the attach (line ${attach_line:-none})"
fi
has "$OUT" "waiting for the reconciler to start s-gc-77 (it is start-pending), then attaching; Ctrl-C stops the wait and leaves it starting" \
    "(START-WAIT) …telling the operator what it waits on, and that Ctrl-C leaves it starting"

# A start on a busy controller can take minutes, so nothing short of the
# backstop ends the wait. On the fake clock the listings are ten seconds apart,
# so the fifteenth reads the sitting 140s after the wait opened.
FAKE_CLOCK="$TMP/clock" FAKE_CLOCK_SCALE=10 START_STATES="$(reps start-pending 14) active" run_fresh tk-conv
eq "$RC" 0 "(START-LONG) a sitting still start-pending after two minutes is waited on"
eq "$(cat "$POLLS")" 15 "(START-LONG) …read until it reads active, 140s in"
has "$CALLED" "session attach gc-77" "(START-LONG) …and attached then"
hasnt "$OUT" "has not started" "(START-LONG) …with no give-up"
has "$OUT" "still waiting after 2m00s: s-gc-77 is start-pending" \
    "(START-LONG) …reporting the time waited as it passes two minutes"

# The wait reports itself: a line when it opens, one when the state changes,
# and one every 30s. A listing that did not read is no change of state, and
# neither is the same state read again after it.
FAKE_CLOCK="$TMP/clock" FAKE_CLOCK_SCALE=10 START_STATES="start-pending start-pending creating broken creating active" run_fresh tk-conv
eq "$RC" 0 "(START-PROGRESS) an engage whose sitting goes start-pending, creating, active exits 0"
has "$OUT" "waiting for the reconciler to start s-gc-77 (it is start-pending)" \
    "(START-PROGRESS) the wait opens with the state it read"
has "$OUT" "s-gc-77 is now creating, after 20s" "(START-PROGRESS) …prints a line when the state changes"
eq "$(printf '%s\n' "$OUT" | grep -c 'is now' || true)" 1 \
    "(START-PROGRESS) …and only then: neither a listing that did not read nor the same state read again prints one"
has "$OUT" "still waiting after 30s: s-gc-77 could not be read from 'gc session list'" \
    "(START-PROGRESS) …and a line every 30s with the time waited and what the last listing read"
has "$CALLED" "session attach gc-77" "(START-PROGRESS) …then attaches"

GC_HELM_ENGAGE_WAIT_TIMEOUT=2 START_STATES="start-pending" run_fresh tk-conv
eq "$RC" 4 "(START-TIMEOUT) a sitting still unstarted at the GC_HELM_ENGAGE_WAIT_TIMEOUT bound exits 4: the engage put no sitting in front of the operator"
hasnt "$CALLED" "session attach" "(START-TIMEOUT) …and is NOT attached, since the attach would launch it without its prompt"
polls=$(cat "$POLLS")
if [ "${polls:-0}" -ge 2 ]; then
  ok "(START-TIMEOUT) …after reading it more than once"
else
  bad "(START-TIMEOUT) expected at least 2 listings before giving up (got ${polls:-0})"
fi
has "$OUT" "the reconciler has not started s-gc-77 after 2s" "(START-TIMEOUT) …saying the reconciler has not started it"
has "$OUT" "start-pending" "(START-TIMEOUT) …naming the state it last read"
has "$OUT" "Attach once it reads active there: gc session attach gc-77" "(START-TIMEOUT) …and giving the attach to run once it is up"
eq "$(asg tk-conv)" "gc-toolkit/gc-toolkit.tk-conv" "(START-TIMEOUT) …leaving the conversation bound to the sitting"

# The bound is a backstop set above the controller's own limits: 15 minutes
# unless GC_HELM_ENGAGE_WAIT_TIMEOUT says otherwise. On the fake clock the
# listings are a minute apart, at minutes 0 through 15.
FAKE_CLOCK="$TMP/clock" FAKE_CLOCK_SCALE=60 START_STATES="start-pending" run_fresh tk-conv
eq "$RC" 4 "(START-BACKSTOP) a sitting that never leaves start-pending exits 4 at the default bound"
eq "$(cat "$POLLS")" 16 "(START-BACKSTOP) …which is 15 minutes"
has "$OUT" "the reconciler has not started s-gc-77 after 15m00s" "(START-BACKSTOP) …naming the wait in minutes"
hasnt "$CALLED" "session attach" "(START-BACKSTOP) …without attaching"

FAKE_CLOCK="$TMP/clock" FAKE_CLOCK_SCALE=10 START_STATES="$(reps start-pending 14) gone" run_fresh tk-conv
eq "$RC" 4 "(START-ENDED-LATE) a sitting that ends after a wait of minutes exits 4"
eq "$(cat "$POLLS")" 15 "(START-ENDED-LATE) …at the first listing it is gone from"
has "$OUT" "ended before the reconciler started it (its state in 'gc session list': gone)" "(START-ENDED-LATE) …saying the sitting ended"
hasnt "$CALLED" "session attach" "(START-ENDED-LATE) …without attaching"

GC_HELM_ENGAGE_WAIT_TIMEOUT=60 START_STATES="start-pending gone" run_fresh tk-conv
eq "$RC" 4 "(START-CLOSED) a sitting listed and then gone from the list (closed, read from the store) exits 4"
hasnt "$CALLED" "session attach" "(START-CLOSED) …without attaching"
eq "$(cat "$POLLS")" 2 "(START-CLOSED) …at the first listing it is gone from, not at the bound"
has "$OUT" "ended before the reconciler started it (its state in 'gc session list': gone)" "(START-CLOSED) …saying the sitting ended"
has "$OUT" "gc bd update tk-conv --if-assignee" "(START-CLOSED) …and how to hand its still-bound conversation back to the queue"

GC_HELM_ENGAGE_WAIT_TIMEOUT=60 START_STATES="blank" run_fresh tk-conv
eq "$RC" 4 "(START-BLANK) a sitting listed with an empty state (closed, read from the supervisor) exits 4"
hasnt "$CALLED" "session attach" "(START-BLANK) …without attaching"
eq "$(cat "$POLLS")" 1 "(START-BLANK) …at the first listing"
has "$OUT" "state in 'gc session list': closed" "(START-BLANK) …naming it closed"

GC_HELM_ENGAGE_WAIT_TIMEOUT=60 START_STATES="failed-create" run_fresh tk-conv
eq "$RC" 4 "(START-FAILED) a sitting whose create failed exits 4"
hasnt "$CALLED" "session attach" "(START-FAILED) …without attaching"
has "$OUT" "state in 'gc session list': failed-create" "(START-FAILED) …naming the state"

# A sitting not listed yet may only lag the supervisor's read cache, and a
# listing that fails says nothing about the sitting, so neither ends the wait.
GC_HELM_ENGAGE_WAIT_TIMEOUT=60 START_STATES="gone gone active" run_fresh tk-conv
eq "$RC" 0 "(START-UNLISTED) a sitting not yet listed is waited on, not read as closed"
has "$CALLED" "session attach gc-77" "(START-UNLISTED) …and attached once it reads active"
GC_HELM_ENGAGE_WAIT_TIMEOUT=60 START_STATES="broken active" run_fresh tk-conv
eq "$RC" 0 "(START-UNREADABLE) a listing that fails is waited through"
has "$CALLED" "session attach gc-77" "(START-UNREADABLE) …and the sitting attached once a listing reads it active"

echo "# --no-attach has no attach to gate, so it does not wait"
GC_HELM_ENGAGE_WAIT_TIMEOUT=60 START_STATES="start-pending" run_fresh tk-conv --no-attach
eq "$RC" 0 "(NOATTACH-NOWAIT) --no-attach on an unstarted sitting exits 0"
polls=$(cat "$POLLS")
eq "${polls:-0}" 0 "(NOATTACH-NOWAIT) …without reading the sitting's state"
hasnt "$OUT" "waiting for the reconciler" "(NOATTACH-NOWAIT) …or announcing a wait"
GC_HELM_ENGAGE_WAIT_TIMEOUT=60 START_STATES="start-pending" run_fresh tk-conv --model codex --no-attach
has "$CALLED" "session nudge gc-77" "(NOATTACH-KICK) a codex sitting on --no-attach is kicked without a start wait"

echo "# for codex, the kick follows the start wait"
START_STATES="start-pending active" run_fresh tk-conv --model codex
last_poll=$(printf '%s\n' "$CALLED" | grep -n '^session list' | tail -1 | cut -d: -f1 || true)
nudge_line=$(printf '%s\n' "$CALLED" | grep -n '^session nudge' | head -1 | cut -d: -f1 || true)
attach_line=$(printf '%s\n' "$CALLED" | grep -n '^session attach' | head -1 | cut -d: -f1 || true)
if [ -n "$last_poll" ] && [ -n "$nudge_line" ] && [ -n "$attach_line" ] \
   && [ "$last_poll" -lt "$nudge_line" ] && [ "$nudge_line" -lt "$attach_line" ]; then
  ok "(KICK-AFTER-START) the codex kick reaches a started sitting and precedes the attach"
else
  bad "(KICK-AFTER-START) expected listing (${last_poll:-none}) < nudge (${nudge_line:-none}) < attach (${attach_line:-none})"
fi
GC_HELM_ENGAGE_WAIT_TIMEOUT=1 START_STATES="start-pending" run_fresh tk-conv --model codex
has "$CALLED" "session nudge gc-77" "(TIMEOUT-KICK) a codex sitting unstarted at the bound is still kicked, so it begins once it starts"
hasnt "$CALLED" "session attach" "(TIMEOUT-KICK) …but not attached"
GC_HELM_ENGAGE_WAIT_TIMEOUT=60 START_STATES="start-pending gone" run_fresh tk-conv --model codex
hasnt "$CALLED" "session nudge" "(CLOSED-NOKICK) a codex sitting that ended before it started is not kicked"

echo "# Ctrl-C during the wait stops the wait and leaves the sitting starting"
# The operator who stops waiting keeps the engage: the conversation stays
# bound, the sitting is neither closed nor attached, and engage says how to
# reach it once it is up.
reset; START_STATES="start-pending" run_engage_interrupted tk-conv
eq "$RC" 130 "(START-INTERRUPT) Ctrl-C during the wait exits 130"
has "$OUT" "stopped waiting after" "(START-INTERRUPT) …saying the wait stopped"
has "$OUT" "Conversation tk-conv stays held by s-gc-77, which the reconciler goes on starting; attach once it reads active in 'gc session list': gc session attach gc-77" \
    "(START-INTERRUPT) …and printing the attach to run once the sitting is up"
hasnt "$CALLED" "session attach" "(START-INTERRUPT) …without attaching"
hasnt "$CALLED" "session close" "(START-INTERRUPT) …or closing the sitting"
eq "$(asg tk-conv)" "gc-toolkit/gc-toolkit.tk-conv" "(START-INTERRUPT) …and the conversation still bound to it"
hasnt "$CALLED" "session nudge" "(START-INTERRUPT) …and an opus sitting is not kicked"
reset; START_STATES="start-pending" run_engage_interrupted tk-conv --model codex
eq "$RC" 130 "(INTERRUPT-KICK) Ctrl-C during a codex sitting's wait exits 130"
has "$CALLED" "session nudge gc-77" "(INTERRUPT-KICK) …after kicking the sitting, so it begins once it starts"
# A terminal that goes away under the wait, and a TERM, stop it the same way.
reset; INTERRUPT_SIG=HUP START_STATES="start-pending" run_engage_interrupted tk-conv --model codex
eq "$RC" 129 "(INTERRUPT-HUP) a hang-up during a codex sitting's wait exits 129"
has "$OUT" "stopped waiting after" "(INTERRUPT-HUP) …through the same stop as Ctrl-C"
has "$CALLED" "session nudge gc-77" "(INTERRUPT-HUP) …kicking the sitting, so it begins once it starts"
hasnt "$CALLED" "session close" "(INTERRUPT-HUP) …and leaving it open"
eq "$(asg tk-conv)" "gc-toolkit/gc-toolkit.tk-conv" "(INTERRUPT-HUP) …with the conversation still bound to it"
reset; INTERRUPT_SIG=TERM START_STATES="start-pending" run_engage_interrupted tk-conv
eq "$RC" 143 "(INTERRUPT-TERM) a TERM during the wait exits 143"
has "$OUT" "stopped waiting after" "(INTERRUPT-TERM) …through the same stop as Ctrl-C"

echo "# a suspended subject rig is refused before anything spawns"
# engage spawns a sitting the reconciler must sustain; on a suspended rig the
# reconciler skips its agents, so the sitting never comes up and the conversation
# would strand bound to it. Refuse before spawning, and name the resume as the fix.
export RIG_SUSPENDED=true
run_fresh tk-conv --no-attach
eq "$RC" 4 "(SUSPENDED) engaging on a suspended rig exits 4"
hasnt "$CALLED" "session new" "(SUSPENDED) …and spawns nothing"
has "$OUT" "is suspended" "(SUSPENDED) …saying the rig is suspended"
has "$OUT" "gc rig resume gc-toolkit" "(SUSPENDED) …and naming the resume as the fix"
unset RIG_SUSPENDED

echo "# a city whose controller is down is refused before anything spawns"
# The reconciler, the controller's loop, is what launches the sitting; the HQ
# row's running is gc's probe of that controller, and gc status confirms it.
export HQ_RUNNING=false STATUS_CONTROLLER=false
run_fresh tk-conv --no-attach
eq "$RC" 4 "(CTRL-DOWN) engaging while the city controller is down exits 4"
hasnt "$CALLED" "session new" "(CTRL-DOWN) …and spawns nothing"
has "$CALLED" "status --json" "(CTRL-DOWN) …having asked gc status about the HQ reading"
has "$OUT" "city controller did not answer" "(CTRL-DOWN) …saying the controller did not answer"
has "$OUT" "both report it not running" "(CTRL-DOWN) …and that both readings agree"
has "$OUT" "gc status" "(CTRL-DOWN) …and pointing at the city's status"
hasnt "$OUT" "gc rig status" "(CTRL-DOWN) …not at the subject rig's"
unset HQ_RUNNING STATUS_CONTROLLER

echo "# an HQ running=false that gc status cannot confirm or clear still refuses"
# The ping missed and the second reading has nothing to say: a gc status that
# prints nothing, prints something that is not JSON, or reports a supervisor
# that is up but cannot tell. The HQ reading stands.
export HQ_RUNNING=false
for _st in "" broken unknown; do
    STATUS_CONTROLLER="$_st" run_fresh tk-conv --no-attach
    eq "$RC" 4 "(CTRL-NOREAD:${_st:-empty}) an unconfirmed HQ running=false exits 4"
    hasnt "$CALLED" "session new" "(CTRL-NOREAD:${_st:-empty}) …and spawns nothing"
    has "$OUT" "'gc status' could not tell" "(CTRL-NOREAD:${_st:-empty}) …saying gc status could not tell"
done
unset HQ_RUNNING

echo "# an HQ running=false that gc status contradicts engages"
# A loaded controller can miss the socket ping that sets the HQ row; the
# supervisor-aware reading in gc status answering running clears it.
export HQ_RUNNING=false STATUS_CONTROLLER=true
run_fresh tk-conv --no-attach
eq "$RC" 0 "(CTRL-PING-MISSED) engaging when gc status reports the controller running exits 0"
has "$CALLED" "status --json" "(CTRL-PING-MISSED) …after asking gc status"
has "$CALLED" "session new converse-opus --alias tk-conv" "(CTRL-PING-MISSED) …and spawns the sitting"
unset HQ_RUNNING STATUS_CONTROLLER

echo "# a rig list with no HQ row reads as unknown and does not refuse"
# An older gc, or one that stops listing the HQ, gives no controller reading.
# Unknown never refuses, and gc status is not asked for a reading nothing
# contradicts.
export NO_HQ_ROW=1 STATUS_CONTROLLER=false
run_fresh tk-conv --no-attach
eq "$RC" 0 "(NO-HQ) engaging with no HQ row in the rig list exits 0"
has "$CALLED" "session new converse-opus --alias tk-conv" "(NO-HQ) …and spawns the sitting"
hasnt "$CALLED" "status --json" "(NO-HQ) …without asking gc status"
unset NO_HQ_ROW STATUS_CONTROLLER

echo "# a suspended rig is refused on its suspension even while the controller is down"
# The suspension is checked first, so the refusal names the fix that is the
# subject rig's own, and gc status is never asked.
export HQ_RUNNING=false RIG_SUSPENDED=true STATUS_CONTROLLER=false
run_fresh tk-conv --no-attach
eq "$RC" 4 "(SUSPENDED-CTRL-DOWN) a suspended rig with the controller down exits 4"
has "$OUT" "is suspended" "(SUSPENDED-CTRL-DOWN) …on the suspension"
hasnt "$OUT" "city controller" "(SUSPENDED-CTRL-DOWN) …not on the controller"
hasnt "$CALLED" "status --json" "(SUSPENDED-CTRL-DOWN) …and gc status is not asked"
unset HQ_RUNNING RIG_SUSPENDED STATUS_CONTROLLER

echo "# an idle subject rig (running=false) engages while the controller is up"
# A rig row's running=false is what gc reports for an idle rig, and an idle rig
# is not a down one: the reconciler launches the sitting there like anywhere else.
export HQ_RUNNING=true RIG_SUSPENDED=false RIG_RUNNING=false
run_fresh tk-conv --no-attach
eq "$RC" 0 "(IDLE) engaging on an idle rig exits 0"
has "$CALLED" "session new converse-opus --alias tk-conv" "(IDLE) …and spawns the sitting"
hasnt "$CALLED" "status --json" "(IDLE) …and an HQ running=true asks gc status nothing"
unset HQ_RUNNING RIG_SUSPENDED RIG_RUNNING

echo "# a suspended rig is refused even while the controller is up"
export HQ_RUNNING=true RIG_SUSPENDED=true
run_fresh tk-conv --no-attach
eq "$RC" 4 "(SUSPENDED-CTRL-UP) a suspended rig still exits 4 with the controller up"
has "$OUT" "is suspended" "(SUSPENDED-CTRL-UP) …on the suspension"
unset HQ_RUNNING RIG_SUSPENDED

echo "# an explicitly live city (controller running, rig not suspended) spawns as normal"
# The guard refuses only on suspended=true or an HQ running=false, so a city gc
# reports as live must engage exactly as one that reports neither flag.
export HQ_RUNNING=true RIG_SUSPENDED=false RIG_RUNNING=true
run_fresh tk-conv --no-attach
eq "$RC" 0 "(LIVE) engaging on an explicitly live city exits 0"
has "$CALLED" "session new converse-opus --alias tk-conv" "(LIVE) …and spawns the sitting"
unset HQ_RUNNING RIG_SUSPENDED RIG_RUNNING

# ── Interactive TTY flow + starter/model/debug ───────────────────────
echo
echo "# the model set is the configured converse-* variants; bare 'converse' is excluded"
# --model validates against the globbed variants (opus/fable/codex from the
# fixture agents dir); the bare 'converse' pool template is not an engage variant.
run_fresh tk-conv --model converse --no-attach
eq "$RC" 2 "(IA-MODEL-SET) --model converse (the bare pool template) is not a variant, exit 2"
hasnt "$CALLED" "session new" "(IA-MODEL-SET) …and nothing spawned"
has "$OUT" "must be one of: opus" "(IA-MODEL-SET) …the message lists the configured variants"

echo "# every success carries a ✓ summary on stdout and an always-on [debug] line"
run_fresh tk-conv --no-attach
eq "$RC" 0 "(IA-DEBUG) engaging exits 0"
has "$OUT" "[debug] conversation=tk-conv" "(IA-DEBUG) the provenance rides an always-on [debug] line"
has "$OUT" "sitting=gc-77" "(IA-DEBUG) …carrying the sitting id"
has "$OUT" "work_dir=/w" "(IA-DEBUG) …and the sitting work_dir"
has "$OUT" "✓ converse-opus" "(IA-DEBUG) …and the human summary names the sitting template"

echo "# --no-input keeps the non-interactive one-shot behavior (takes the queued conversation)"
run_fresh tk-subj --no-input --no-attach
eq "$RC" 0 "(IA-NOINPUT) --no-input on a bead with a queued conversation exits 0"
hasnt "$CALLED" "bd create" "(IA-NOINPUT) …taking that conversation, filing nothing"
has "$CALLED" "session new converse-opus --alias tk-conv" "(IA-NOINPUT) …with no prompts"

echo "# on a TTY a bead with a queued conversation is offered take-it vs new"
# [1] take the queued conversation · Enter at the model prompt (Opus)
run_fresh_tty '1\n\n' tk-subj --no-attach
eq "$RC" 0 "(IA-CONV-EXISTING) picking the queued conversation exits 0"
has "$OUT" "Subject has open conversation" "(IA-CONV-EXISTING) …after listing the bead's open conversations"
has "$OUT" "[d] discuss broadly" "(IA-CONV-EXISTING) …in one prompt that also offers the new-conversation seed letters"
hasnt "$CALLED" "bd create" "(IA-CONV-EXISTING) …files nothing"
has "$CALLED" "session new converse-opus --alias tk-conv" "(IA-CONV-EXISTING) …and engages it"
# An existing conversation's ask was written when it was filed, so there is no
# new ask for a skill to seed: the skill prompt is not asked.
hasnt "$OUT" "Skill — Enter" "(IA-SKILL-EXISTING) …and asks no skill, since its ask is already written"

echo "# a subject engage grounds the operator with a one-line summary before the conversation prompt"
run_fresh_tty '1\n\n' tk-subj --no-attach
eq "$RC" 0 "(IA-SUMMARY) engaging a subject exits 0"
has "$OUT" "the subject under engagement" "(IA-SUMMARY) the summary carries the picked bead's title"
has "$OUT" "task · open · p2" "(IA-SUMMARY) …with its type, status, and priority"
# The summary precedes the conversation prompt, so the operator reads what they
# picked while deciding which conversation to take or open.
case "$OUT" in
  *"the subject under engagement"*"Subject has open conversation"*) ok "(IA-SUMMARY) …ahead of the conversation prompt" ;;
  *) bad "(IA-SUMMARY) the summary should precede the conversation prompt" ;;
esac

echo "# an over-long title is truncated so the summary stays one short line"
export \
  SUBJ_TITLE="AAAA BBBB CCCC DDDD EEEE FFFF GGGG HHHH IIII JJJJ KKKK LLLL MMMM NNNN OOOO PPPP QQQQ RRRR SSSS TTTT ZEND"
run_fresh_tty '1\n\n' tk-subj --no-attach
eq "$RC" 0 "(IA-SUMMARY-TRUNC) engaging a long-titled subject exits 0"
has "$OUT" "AAAA" "(IA-SUMMARY-TRUNC) the title head is kept"
has "$OUT" "…" "(IA-SUMMARY-TRUNC) …with an ellipsis where it was cut"
hasnt "$OUT" "ZEND" "(IA-SUMMARY-TRUNC) …and the tail past the cut is dropped"
unset SUBJ_TITLE

echo "# --no-input suppresses the grounding summary — its stdout is a script's to parse"
run_fresh tk-subj --no-input --no-attach
eq "$RC" 0 "(IA-SUMMARY-NOINPUT) --no-input on a subject exits 0"
hasnt "$OUT" "the subject under engagement" "(IA-SUMMARY-NOINPUT) …and no grounding summary is printed"

echo "# two queued conversations become a numbered choice"
export HAVE_CONV=2
# oldest first: [1]=tk-conv (10-01) · [2]=tk-conv2 (10-02); pick [1]
run_fresh_tty '1\n\n' tk-subj --no-attach
eq "$RC" 0 "(IA-CONV-MULTI) two queued conversations, picking one, exits 0"
has "$OUT" "tk-conv2" "(IA-CONV-MULTI) …both conversations are listed"
has "$CALLED" "session new converse-opus --alias tk-conv " "(IA-CONV-MULTI) …spawning for the picked conversation"

echo "# a seed letter at the one prompt files a NEW conversation carrying that seed, even with one queued"
# [d] a new conversation seeded discuss-broadly (one prompt, no separate starter) · Enter
# model (Opus) · Enter skill (none)
run_fresh_tty 'd\n\n\n' tk-subj --no-attach
eq "$RC" 0 "(IA-NEW-TEMPLATE) a new conversation + template exits 0"
has "$CALLED" "bd create" "(IA-NEW-TEMPLATE) …a new conversation is filed"
hasnt "$OUT" "already open" "(IA-NEW-TEMPLATE) …deliberately, past the queue's join"
has "$CALLED" "talk through tk-subj broadly" "(IA-NEW-TEMPLATE) …its body is the seed, subject filled in"
has "$CALLED" "--title discuss broadly" "(IA-NEW-TEMPLATE) …titled by the seed label"
has "$CALLED" "session new converse-opus" "(IA-NEW-TEMPLATE) …then a sitting is spawned"
has "$OUT" "Skill — Enter = none" "(IA-SKILL-NONE) a new conversation is asked for a skill"
hasnt "$CALLED" "Load that skill" "(IA-SKILL-NONE) …and Enter seeds none, leaving the seed as the whole brief"

echo "# free text at the one prompt opens a NEW conversation carrying it verbatim as the opener"
# free text (not a number or seed letter) · Enter model · Enter skill (none)
run_fresh_tty 'lets revisit the scope\n\n\n' tk-subj --no-attach
eq "$RC" 0 "(IA-NEW-FREETEXT) a new conversation + free text exits 0"
has "$CALLED" "bd create" "(IA-NEW-FREETEXT) …a new conversation is filed"
has "$CALLED" "lets revisit the scope" "(IA-NEW-FREETEXT) …with the typed message as its body"

echo "# the model prompt is a numbered choice; picking codex spawns converse-codex + kick"
# model list = opus, codex, fable (opus first, then glob order); [2] = codex
run_fresh_tty '2\n' tk-conv --no-attach
eq "$RC" 0 "(IA-MODEL-PICK) picking a model exits 0"
has "$CALLED" "session new converse-codex --alias tk-conv" "(IA-MODEL-PICK) …spawning the picked variant"
has "$CALLED" "session nudge gc-77" "(IA-MODEL-PICK) …and codex, the kicked provider, gets its opening turn"

echo "# Enter at the model prompt keeps Opus (the work-tier default)"
run_fresh_tty '\n' tk-conv --no-attach
eq "$RC" 0 "(IA-MODEL-DEFAULT) Enter at the model prompt exits 0"
has "$CALLED" "session new converse-opus" "(IA-MODEL-DEFAULT) …keeping Opus"

echo "# a conversation id is grounded by the bead it tracks and its own title"
# The conversation-or-starter prompt is skipped for a conversation id; the only
# read is the model choice (Enter = Opus).
run_fresh_tty '\n' tk-conv --no-attach
eq "$RC" 0 "(IA-CONVID-SUBJECT) engaging a conversation id exits 0"
has "$OUT" "Subject: tk-subj" "(IA-CONVID-SUBJECT) grounding names the bead the conversation tracks"
has "$OUT" "the subject under engagement" "(IA-CONVID-SUBJECT) …with that bead's own title"
has "$OUT" 'Conversation: tk-conv — "an earlier concern"' "(IA-CONVID-SUBJECT) …and the conversation's title"
hasnt "$OUT" "starts a new" "(IA-CONVID-SUBJECT) …and the conversation-or-starter prompt is skipped"
hasnt "$OUT" "Subject has open conversation" "(IA-CONVID-SUBJECT) …no conversation list is offered"
has "$CALLED" "session new converse-opus --alias tk-conv" "(IA-CONVID-SUBJECT) …then it engages the named conversation"
has "$OUT" "for tk-subj" "(IA-CONVID-SUBJECT) …and the success line names the bead, not the conversation id repeated"

echo "# a subject given by title search resolves and engages"
export SEARCH_HIT=1
# search text · [1] pick the match · Enter takes its queued conversation ·
# model Enter (Opus)
run_fresh_tty 'findme\n1\n\n\n\n' --no-attach
eq "$RC" 0 "(IA-SUBJECT-SEARCH) a title-searched subject resolves and engages, exit 0"
has "$CALLED" "session new converse-opus --alias tk-conv" "(IA-SUBJECT-SEARCH) …spawning for the resolved bead's conversation"
unset SEARCH_HIT

echo "# --template pre-fills the starter and skips its prompt (here under --no-input)"
run_fresh tk-subj --template unstick-a-stall --no-input --no-attach
eq "$RC" 0 "(IA-TEMPLATE-FLAG) --template files a new conversation with the seed, exit 0"
has "$CALLED" "bd create" "(IA-TEMPLATE-FLAG) …a new conversation is filed"
has "$CALLED" "looks stalled" "(IA-TEMPLATE-FLAG) …carrying the seed body"
hasnt "$OUT" "already open" "(IA-TEMPLATE-FLAG) …past the queue's join"

echo "# an unknown --template is refused before anything spawns"
run_fresh tk-subj --template bogus --no-input --no-attach
eq "$RC" 2 "(IA-TEMPLATE-BAD) an unknown --template exits 2"
has "$OUT" "unknown --template" "(IA-TEMPLATE-BAD) …naming the fault"
hasnt "$CALLED" "session new" "(IA-TEMPLATE-BAD) …and nothing spawned"

echo "# --reason and --template both set the opener — they conflict"
run_fresh tk-subj --reason x --template discuss-broadly --no-input --no-attach
eq "$RC" 2 "(IA-REASON-TEMPLATE) --reason and --template together exit 2"
has "$OUT" "both set the opening message" "(IA-REASON-TEMPLATE) …saying why"
hasnt "$CALLED" "bd create" "(IA-REASON-TEMPLATE) …and nothing filed"

echo "# --new-subject: file a fresh marked subject in a chosen rig, then engage it"
# One-shot: --rig names the rig, the positional is the subject title. The subject
# is created MARKED (gc.reaction_owned=1 + gc.origin=operator) in that rig's
# .beads store, then its one conversation is filed and a sitting spawned. The
# marker is what stands the async first-reaction/proactive worker down.
run_fresh "ship the new intake flow" --new-subject --rig gc-toolkit --no-input --no-attach
eq "$RC" 0 "(NEWSUBJ) --new-subject --rig --no-input exits 0"
SUBJ_CREATE="$(printf '%s\n' "$CALLED" | grep '^bd create' | grep -v -- '--deps tracks:' | head -n1)"
has "$SUBJ_CREATE" "reaction_owned" "(NEWSUBJ) the subject is created with the gc.reaction_owned marker"
has "$SUBJ_CREATE" "gc.origin" "(NEWSUBJ) …and gc.origin=operator (honest origin)"
has "$SUBJ_CREATE" "--db $TMP/rig/.beads" "(NEWSUBJ) …in the chosen rig's store (cross-rig create)"
has "$SUBJ_CREATE" "ship the new intake flow" "(NEWSUBJ) …titled with the subject text"
has "$OUT" "filed subject tk-newsubj in rig 'gc-toolkit'" "(NEWSUBJ) reports the filed subject"
has "$CALLED" "session new converse-opus --alias tk-new --no-attach" "(NEWSUBJ) then engages the one conversation it filed"
# The title doubles as the opener when no --reason/--template is given: the
# conversation cmd_open files carries it as its title and its ask.
CONV_CREATE="$(printf '%s\n' "$CALLED" | grep '^bd create' | grep -- '--deps tracks:' | head -n1)"
has "$CONV_CREATE" "--title ship the new intake flow" "(NEWSUBJ-OPENER) the title doubles as the conversation's opener"
# The marker outlives a SUCCESSFUL engage (it is what stands the async worker
# down); the abort backstop must be disarmed once the conversation is filed, so a clean
# engage never revokes it. (The disarm's control; its arm is NEWSUBJ-ABORT below.)
hasnt "$CALLED" "unset-metadata gc.reaction_owned" "(NEWSUBJ) a successful engage keeps the marker — the backstop is disarmed once the conversation is filed"

echo "# --new-subject one-shot without --rig is refused (no id prefix to derive a rig)"
run_fresh "some topic" --new-subject --no-input --no-attach
eq "$RC" 2 "(NEWSUBJ-NORIG) --new-subject --no-input without --rig exits 2"
has "$OUT" "needs a rig" "(NEWSUBJ-NORIG) …naming the fault"
hasnt "$CALLED" "--metadata" "(NEWSUBJ-NORIG) …and no subject was created"

echo "# --new-subject and --subject are mutually exclusive"
run_fresh --new-subject --subject tk-subj --rig gc-toolkit --no-input --no-attach
eq "$RC" 2 "(NEWSUBJ-CONFLICT) --new-subject with --subject exits 2"
has "$OUT" "pass only one" "(NEWSUBJ-CONFLICT) …saying why"
hasnt "$CALLED" "--metadata" "(NEWSUBJ-CONFLICT) …and nothing created"

echo "# --rig without --new-subject is refused (an existing subject's rig comes from its id)"
run_fresh tk-subj --rig gc-toolkit --no-input --no-attach
eq "$RC" 2 "(NEWSUBJ-RIG-ALONE) --rig without --new-subject exits 2"
has "$OUT" "applies only with --new-subject" "(NEWSUBJ-RIG-ALONE) …naming the fault"

echo "# --new-subject with an unknown rig is refused before any create"
run_fresh "x" --new-subject --rig nope --no-input --no-attach
eq "$RC" 4 "(NEWSUBJ-BADRIG) an unknown --rig exits 4"
has "$OUT" "matches no rig" "(NEWSUBJ-BADRIG) …naming the unknown rig"
hasnt "$CALLED" "--metadata" "(NEWSUBJ-BADRIG) …and nothing created"

echo "# --new-subject one-shot with no subject text is refused"
run_fresh --new-subject --rig gc-toolkit --no-input --no-attach
eq "$RC" 2 "(NEWSUBJ-NOTITLE) a missing subject text exits 2"
has "$OUT" "needs a subject" "(NEWSUBJ-NOTITLE) …naming the fault"
hasnt "$CALLED" "--metadata" "(NEWSUBJ-NOTITLE) …and nothing created"

echo "# --new-subject whose subject create fails aborts without spawning"
export SUBJ_CREATE_FAIL=1
run_fresh "doomed subject" --new-subject --rig gc-toolkit --no-input --no-attach
eq "$RC" 4 "(NEWSUBJ-CREATEFAIL) a failed subject create exits 4"
has "$OUT" "could not create the subject" "(NEWSUBJ-CREATEFAIL) …naming the fault"
hasnt "$CALLED" "session new" "(NEWSUBJ-CREATEFAIL) …and no sitting spawned"
hasnt "$CALLED" "unset-metadata gc.reaction_owned" "(NEWSUBJ-CREATEFAIL) …and no cleanup runs — nothing was created to clean up"
unset SUBJ_CREATE_FAIL

echo "# --new-subject whose post-create gate aborts still files the subject's one conversation"
# The subject is created MARKED before the gates that can still refuse the live
# engage (here an unknown --model, like the suspended, controller-down and unknown
# --template gates). An abort there must not leave the operator-origin subject with
# no conversation: the async worker will not supply one (gc-proactive drops a
# marked bead, a reaction that reaches one stands down, and even unmarked a first
# reaction files none for gc.origin=operator). So the backstop files the one
# conversation itself in the operator's queue (via cmd_open, carrying the opener)
# and LEAVES the marker,
# exactly as a successful engage does, so the async worker still stands down.
run_fresh "topic after a bad model" --new-subject --rig gc-toolkit --model bogus --no-input --no-attach
eq "$RC" 2 "(NEWSUBJ-ABORT) a post-create --model abort exits 2"
SUBJ_CREATE="$(printf '%s\n' "$CALLED" | grep '^bd create' | grep -v -- '--deps tracks:' | head -n1)"
has "$SUBJ_CREATE" "reaction_owned" "(NEWSUBJ-ABORT) the subject was already created with the marker (the abort is post-create)"
CONV_CREATE="$(printf '%s\n' "$CALLED" | grep '^bd create' | grep -- '--deps tracks:' | head -n1)"
has "$CONV_CREATE" "topic after a bad model" "(NEWSUBJ-ABORT) …so the backstop files the subject's one conversation, carrying its opener"
hasnt "$CALLED" "unset-metadata gc.reaction_owned" "(NEWSUBJ-ABORT) …and LEAVES the marker, exactly as a successful engage does"
has "$OUT" "waiting in the operator's queue" "(NEWSUBJ-ABORT) …and tells the operator it waits in their queue to engage"
hasnt "$CALLED" "session new" "(NEWSUBJ-ABORT) …and nothing was spawned"

echo "# --new-subject interactive: a lone converse rig auto-selects; prompts title, then model"
# One converse-capable rig in the stub, so the rig step auto-selects (reads no
# input); the answers then feed the title prompt, the model prompt (Enter=Opus),
# and the skill prompt a new conversation gets (Enter=none).
run_fresh_tty 'draft the Q3 plan\n\n\n' --new-subject --no-attach
eq "$RC" 0 "(NEWSUBJ-IA) interactive --new-subject exits 0"
has "$OUT" "the only converse-capable rig" "(NEWSUBJ-IA) the lone converse rig auto-selects"
SUBJ_CREATE="$(printf '%s\n' "$CALLED" | grep '^bd create' | grep -v -- '--deps tracks:' | head -n1)"
has "$SUBJ_CREATE" "draft the Q3 plan" "(NEWSUBJ-IA) the typed title becomes the subject"
has "$SUBJ_CREATE" "reaction_owned" "(NEWSUBJ-IA) …created with the marker"
has "$CALLED" "session new converse-opus" "(NEWSUBJ-IA) …then a sitting spawns (Opus, the Enter default)"

# ── --skill: a sitting seeded with a skill as its lens ────────────────
echo
echo "# --skill files a NEW conversation whose ask is the lens brief, even with one queued"
# The lens brief is the new conversation's ask, which every sitting reads at its
# claim, so the skill reaches the sitting on any model with no per-skill
# template. The name is checked against the roster of the sitting that will
# spawn: its rig, and its model's converse agent.
run_fresh tk-subj --skill review-arch --no-input --no-attach
eq "$RC" 0 "(SKILL) --skill on a subject exits 0"
has "$CALLED" "skill list --agent gc-toolkit/gc-toolkit.converse-opus" "(SKILL) the name is checked against the sitting's own roster (its rig and model)"
has "$CALLED" "bd create" "(SKILL) …a NEW conversation is filed, past the queued one"
hasnt "$OUT" "already open" "(SKILL) …deliberately, past the queue's join"
has "$CALLED" "--title review-arch lens" "(SKILL) …titled by the skill, so the board row says whose view it brings"
has "$CALLED" "look at tk-subj through the gc-toolkit.review-arch" "(SKILL) …its ask is the lens brief, the bare name resolved to the full one"
has "$CALLED" "Load that skill" "(SKILL) …which has the sitting load the skill"
has "$CALLED" "then WAIT for the operator" "(SKILL) …and, with no opener, frame through the lens and wait"
has "$CALLED" "session new converse-opus --alias tk-new" "(SKILL) …then a sitting spawns for the new conversation"
hasnt "$CALLED" "session nudge" "(SKILL) …and the opus sitting reads the lens from its ask, unkicked"
has "$OUT" "✓ converse-opus with review-arch on new conversation" "(SKILL) the summary names the skill the sitting was seeded with"

echo "# a full skill name resolves to exactly that skill"
run_fresh tk-subj --skill gc-toolkit.review-pm --no-input --no-attach
eq "$RC" 0 "(SKILL-FULL) a full --skill name exits 0"
has "$CALLED" "through the gc-toolkit.review-pm" "(SKILL-FULL) …and seeds exactly that skill"

echo "# with an opener, the lens brief leads and the opener follows it"
run_fresh tk-subj --skill review-arch --template discuss-broadly --no-input --no-attach
eq "$RC" 0 "(SKILL-TEMPLATE) --skill with --template exits 0"
case "$CALLED" in
  *"-d The operator engaged this sitting"*"says what to do first."*"talk through tk-subj broadly"*)
    ok "(SKILL-TEMPLATE) the ask is the lens brief, then the seed as the opener that says what to do first" ;;
  *) bad "(SKILL-TEMPLATE) the ask should be the lens brief followed by the seed (got: $CALLED)" ;;
esac
has "$CALLED" "--title review-arch lens: discuss broadly" "(SKILL-TEMPLATE) …and the title carries the skill, then the seed label"
run_fresh tk-subj --skill review-arch --reason "is the split justified" --no-input --no-attach
eq "$RC" 0 "(SKILL-REASON) --skill with --reason exits 0"
case "$CALLED" in
  *"-d The operator engaged this sitting"*"says what to do first."*"is the split justified"*)
    ok "(SKILL-REASON) the reason follows the brief as the opener" ;;
  *) bad "(SKILL-REASON) the ask should be the lens brief followed by the reason (got: $CALLED)" ;;
esac
has "$CALLED" "--title review-arch lens: is the split justified" "(SKILL-REASON) …and rides the title after the skill"

echo "# a codex sitting is checked against codex's roster, and the brief rides its kick"
run_fresh tk-subj --skill review-arch --model codex --no-input --no-attach
eq "$RC" 0 "(SKILL-CODEX) --skill with --model codex exits 0"
has "$CALLED" "skill list --agent gc-toolkit/gc-toolkit.converse-codex" "(SKILL-CODEX) the roster read is the codex sitting's"
has "$(printf '%s\n' "$CALLED" | grep '^session nudge')" "through the gc-toolkit.review-arch" "(SKILL-CODEX) …and the codex kick carries the lens brief"

echo "# a name the roster does not carry is refused before anything is filed"
run_fresh tk-subj --skill nope --no-input --no-attach
eq "$RC" 2 "(SKILL-UNKNOWN) an unknown --skill exits 2"
has "$OUT" "unknown --skill 'nope'" "(SKILL-UNKNOWN) …naming the fault"
has "$OUT" "core.gc-work gc-toolkit.review-arch gc-toolkit.review-pm" "(SKILL-UNKNOWN) …and listing what the sitting carries, deduped"
hasnt "$CALLED" "bd create" "(SKILL-UNKNOWN) …nothing filed"
hasnt "$CALLED" "session new" "(SKILL-UNKNOWN) …nothing spawned"

echo "# a bare name two packs both carry is ambiguous until named in full"
export SKILL_AMBIG=1
run_fresh tk-subj --skill review-arch --no-input --no-attach
eq "$RC" 2 "(SKILL-AMBIG) an ambiguous bare --skill exits 2"
has "$OUT" "contributing.review-arch gc-toolkit.review-arch" "(SKILL-AMBIG) …naming both candidates"
hasnt "$CALLED" "bd create" "(SKILL-AMBIG) …nothing filed"
run_fresh tk-subj --skill gc-toolkit.review-arch --no-input --no-attach
eq "$RC" 0 "(SKILL-AMBIG) …and the full name settles it"
has "$CALLED" "through the gc-toolkit.review-arch" "(SKILL-AMBIG) …seeding the named one"
unset SKILL_AMBIG

echo "# a malformed or empty --skill is refused before the roster is read"
run_fresh tk-subj --skill 'review|arch' --no-input --no-attach
eq "$RC" 2 "(SKILL-BADNAME) a --skill carrying a metacharacter exits 2"
hasnt "$CALLED" "skill list" "(SKILL-BADNAME) …refused before the roster is read"
hasnt "$CALLED" "bd create" "(SKILL-BADNAME) …nothing filed"
run_fresh tk-subj --skill '' --no-input --no-attach
eq "$RC" 2 "(SKILL-BADNAME) an empty --skill exits 2"
run_fresh tk-subj --skill=review-arch --no-input --no-attach
eq "$RC" 0 "(SKILL-BADNAME) the --skill=<name> spelling is accepted"

echo "# --skill on an explicit conversation id is refused — its ask is already written"
run_fresh tk-conv --skill review-arch --no-input --no-attach
eq "$RC" 2 "(SKILL-CONVID) --skill with an explicit conversation id exits 2"
has "$OUT" "engage tk-subj --skill review-arch" "(SKILL-CONVID) …pointing at the bead it tracks"
hasnt "$CALLED" "bd create" "(SKILL-CONVID) …nothing filed"
hasnt "$CALLED" "session new" "(SKILL-CONVID) …nothing spawned"

echo "# a roster that will not read seeds the typed name unverified"
# The same fail-open reading engage takes for a model it cannot confirm: the
# operator's choice goes through, says it went unverified, and the brief tells
# the sitting to say so if it cannot load the skill.
export SKILL_ROSTER_BROKEN=1
run_fresh tk-subj --skill review-arch --no-input --no-attach
eq "$RC" 0 "(SKILL-UNREAD) an unreadable roster does not block the engage"
has "$OUT" "seeded unverified" "(SKILL-UNREAD) …it says the name went unverified"
has "$CALLED" "through the review-arch" "(SKILL-UNREAD) …and the brief carries the name as typed"
unset SKILL_ROSTER_BROKEN

echo "# --new-subject with --skill: the subject title is the opener after the brief"
run_fresh "weigh the renderer split" --new-subject --rig gc-toolkit --skill review-arch --no-input --no-attach
eq "$RC" 0 "(SKILL-NEWSUBJ) --new-subject with --skill exits 0"
# The lens brief is several lines, so the create is matched by its title alone.
has "$CALLED" "--title review-arch lens: weigh the renderer split" "(SKILL-NEWSUBJ) the conversation is titled by the skill, then the subject"
has "$CALLED" "look at tk-newsubj through the gc-toolkit.review-arch" "(SKILL-NEWSUBJ) …and briefed with the lens on the new subject"

echo "# on a TTY a new conversation is asked for a skill after the model; a name seeds it"
# [d] a new conversation seeded discuss-broadly · Enter model (Opus) · skill review-arch
run_fresh_tty 'd\n\nreview-arch\n' tk-subj --no-attach
eq "$RC" 0 "(IA-SKILL) a skill typed at the prompt exits 0"
case "$OUT" in
  *"Model —"*"Skill — Enter = none"*) ok "(IA-SKILL) the skill prompt follows the model prompt" ;;
  *) bad "(IA-SKILL) the skill prompt should follow the model prompt" ;;
esac
has "$CALLED" "through the gc-toolkit.review-arch" "(IA-SKILL) …the typed bare name seeds the resolved skill"
has "$CALLED" "talk through tk-subj broadly" "(IA-SKILL) …with the picked seed following as the opener"
has "$CALLED" "--title review-arch lens: discuss broadly" "(IA-SKILL) …and both in the title"

echo "# ? lists the sitting's skills, a number picks one, and an unknown name is asked again"
# [d] seed · Enter model · "nope" (unknown, re-asked) · ? (list) · [2]
run_fresh_tty 'd\n\nnope\n?\n2\n' tk-subj --no-attach
eq "$RC" 0 "(IA-SKILL-LIST) list-then-pick exits 0"
has "$OUT" 'no skill "nope" on this sitting' "(IA-SKILL-LIST) an unknown name is asked again, not refused"
has "$OUT" "[2] gc-toolkit.review-arch" "(IA-SKILL-LIST) ? lists the roster, numbered"
has "$OUT" "[3] gc-toolkit.review-pm" "(IA-SKILL-LIST) …deduped, each skill once"
hasnt "$OUT" "[4]" "(IA-SKILL-LIST) …with no repeated entries"
has "$CALLED" "through the gc-toolkit.review-arch" "(IA-SKILL-LIST) …and the number picks from that list"

echo "# --skill on a TTY skips the conversation/starter prompt: it already chose a new conversation"
run_fresh_tty '\n' tk-subj --skill review-arch --no-attach
eq "$RC" 0 "(IA-SKILL-FLAG) --skill on a TTY exits 0 with only the model asked"
hasnt "$OUT" "starts a new one" "(IA-SKILL-FLAG) …no conversation/starter prompt"
hasnt "$OUT" "Skill — Enter" "(IA-SKILL-FLAG) …and no skill prompt, the flag answered it"
has "$CALLED" "--title review-arch lens" "(IA-SKILL-FLAG) …filing the new conversation with the lens"

echo "# after the attach returns, the tab says how the sitting it showed ended"
# The attach returns once the tab's tmux client exits. A closed conversation is
# a sitting that ended under the tab, and the tab prints how it closed and the
# last hand-back it recorded; a conversation still open is one the operator
# detached from, and the tab prints how to re-attach.
HB_TEXT='tk-subj — the board redesign

Settled: the new layout is on for the operator, and the rest wait a week.'
HB_META=$(jq -nc --arg t "$HB_TEXT" '{"gc.handback":$t,"gc.handback_at":"2026-10-26T12:00:00Z"}')
# ended_with <close-reason> <metadata> — seed what tk-conv carries once its
# sitting has closed it.
ended_with() { printf '%s' "$1" > "$STATE_DIR/tk-conv.reason"; printf '%s' "$2" > "$STATE_DIR/tk-conv.meta"; }
reset; ended_with "settled the rollout" "$HB_META"
ATTACH_ENDS=closed run_engage tk-conv
eq "$RC" 0 "(ENDED) a sitting that ended under the tab exits 0"
has "$OUT" "The sitting on tk-subj has ended: conversation tk-conv closed (settled the rollout)." \
    "(ENDED) the tab says the sitting ended, and how its conversation closed"
has "$OUT" "Its last hand-back, recorded 2026-10-26T12:00:00Z:" "(ENDED) …then introduces the last hand-back"
has "$OUT" "$HB_TEXT" "(ENDED) …and prints the hand-back whole"
hasnt "$OUT" "Re-attach" "(ENDED) …offering no re-attach to a sitting that is gone"

reset; ended_with "settled" "$(jq -nc --arg t "$(printf 'tk-subj — label\n\nred\033[31m text\rover')" '{"gc.handback":$t}')"
ATTACH_ENDS=closed run_engage tk-conv
case "$OUT" in
  *"$(printf '\033')"*|*"$(printf '\r')"*) bad "(ENDED-CTRL) control bytes in a recorded hand-back are not printed to the terminal" ;;
  *) ok "(ENDED-CTRL) control bytes in a recorded hand-back are not printed to the terminal" ;;
esac
has "$OUT" "red[31m textover" "(ENDED-CTRL) …while its text is"

reset; ended_with "dismissed by the operator" '{}'
ATTACH_ENDS=closed run_engage tk-conv
has "$OUT" "conversation tk-conv closed (dismissed by the operator)." "(ENDED-NONE) a sitting that recorded no hand-back still says how it ended"
has "$OUT" "It recorded no hand-back." "(ENDED-NONE) …and that it left none"

reset; ended_with "" "$HB_META"
ATTACH_ENDS=in_progress run_engage tk-conv
eq "$RC" 0 "(DETACHED) a tab the operator detached exits 0"
has "$OUT" "The sitting on tk-subj is still open (conversation tk-conv). Re-attach: gc session attach gc-77" \
    "(DETACHED) a conversation still open says the sitting is still going, with the re-attach command"
hasnt "$OUT" "$HB_TEXT" "(DETACHED) …and prints no hand-back as if it had ended"

reset; ATTACH_ENDS=in_progress ATTACH_UNREADABLE=1 run_engage tk-conv
has "$OUT" "Could not read conversation tk-conv, so whether its sitting has ended is unknown" \
    "(UNREAD) a conversation that does not read back is reported as unknown, not as ended or open"

reset; ended_with "settled the rollout" "$HB_META"
ATTACH_FAIL=1 ATTACH_ENDS=closed run_engage tk-conv
has "$OUT" "The sitting on tk-subj has ended" "(ATTACH-FAIL-ENDED) an attach that failed because the sitting already ended reports the ending"
hasnt "$OUT" "could not attach" "(ATTACH-FAIL-ENDED) …instead of an attach to retry"

reset; ATTACH_FAIL=1 ATTACH_ENDS=in_progress run_engage tk-conv
has "$OUT" "could not attach to gc-77 — attach when ready: gc session attach gc-77" \
    "(ATTACH-FAIL-OPEN) an attach that failed on a sitting still going says so, as before"

reset; ended_with "settled the rollout" "$HB_META"
ATTACH_ENDS=closed run_engage tk-conv --no-attach
hasnt "$OUT" "has ended" "(NOATTACH-REPORT) --no-attach attaches nothing, so it reports no ending"

export LIVE_SITTINGS="gc-50=gc-toolkit/gc-toolkit.tk-conv"
reset; held tk-conv gc-toolkit/gc-toolkit.tk-conv; ended_with "settled the rollout" "$HB_META"
ATTACH_ENDS=closed run_engage tk-subj
has "$CALLED" "session attach gc-50" "(LIVE-ENDED) a tab attached to the live sitting it reused"
has "$OUT" "The sitting on tk-subj has ended: conversation tk-conv closed (settled the rollout)." \
    "(LIVE-ENDED) …reports its ending the same way"
unset LIVE_SITTINGS
reset

# --- the human gates that hold the bead ----------------------------------------
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gctk-stub" <<'GCTK'
printf '%s\n' "$*" >> "$STATE_DIR/gctk.calls"
[ -z "${GCTK_GATES_FAIL:-}" ] || exit 2
printf '%s\n' "${GCTK_GATES:-[]}"
GCTK
chmod +x "$TMP/bin/gctk-stub"
export GCTK_BIN="$TMP/bin/gctk-stub"
ONE_GATE='[{"id":"tk-gate","title":"Approve the rollout"}]'
gctk_calls() { cat "$STATE_DIR/gctk.calls" 2>/dev/null || true; }
fresh_gctk() { rm -f "$STATE_DIR/gctk.calls"; }

echo "# on a TTY the gates that hold the bead are offered, and a pick engages the gate"
export GATE_WAITERS='[{"id":"tk-rework","status":"open","dependency_type":"blocks"}]'
export GCTK_GATES="$ONE_GATE" HAVE_CONV=0
fresh_gctk; run_fresh_tty '1\n\n' tk-subj --no-attach
eq "$RC" 0 "(HOLD-OFFER) picking a gate that holds the bead exits 0"
eq "$(gctk_calls)" "pr-status gates --anchor tk-subj" "(HOLD-OFFER) …read through the one reader"
has "$OUT" "Held by human gate(s):" "(HOLD-OFFER) …listed under their own heading"
has "$OUT" '[1] tk-gate — "Approve the rollout"' "(HOLD-OFFER) …numbered, with what the gate asks"
has "$OUT" "[1-1] engage a listed gate" "(HOLD-OFFER) …and the prompt says the number engages it"
has "$OUT" "tk-gate is a gate about tk-rework" "(HOLD-OFFER) …the pick takes the bead waiting on the gate"
has "$CALLED" "--deps tracks:tk-rework" "(HOLD-OFFER) …the conversation tracks that bead"
hasnt "$CALLED" "--deps tracks:tk-subj" "(HOLD-OFFER) …not the bead the gate was offered on"
has "$CALLED" "--title Approve the rollout" "(HOLD-OFFER) …titled with what the gate asks"
has "$CALLED" "bd dep bd dep add tk-new tk-gate --type replies-to" "(HOLD-OFFER) …and it replies to the gate"

fresh_gctk; run_fresh_tty '\n\n' tk-subj --no-attach
eq "$RC" 0 "(HOLD-ENTER) Enter with only gates listed exits 0"
has "$OUT" "Held by human gate(s):" "(HOLD-ENTER) …having offered the gate"
has "$CALLED" "--deps tracks:tk-subj" "(HOLD-ENTER) …and files a new conversation on the bead, as it does with none listed"
hasnt "$CALLED" "--type replies-to" "(HOLD-ENTER) …which replies to no gate"

export HAVE_CONV=1
fresh_gctk; run_fresh_tty '2\n\n' tk-subj --no-attach
eq "$RC" 0 "(HOLD-NUMBERS) a gate numbered after the conversations exits 0"
has "$OUT" '[1] tk-conv' "(HOLD-NUMBERS) …the conversation keeps number 1"
has "$OUT" '[2] tk-gate — "Approve the rollout"' "(HOLD-NUMBERS) …and the gate follows it"
has "$OUT" "[1-2] take a listed conversation or gate" "(HOLD-NUMBERS) …the prompt offers both"
has "$CALLED" "--deps tracks:tk-rework" "(HOLD-NUMBERS) …number 2 engages the gate"
fresh_gctk; run_fresh_tty '1\n\n' tk-subj --no-attach
has "$CALLED" "session new converse-opus --alias tk-conv" "(HOLD-NUMBERS) number 1 takes the conversation"
hasnt "$CALLED" "--type replies-to" "(HOLD-NUMBERS) …which replies to no gate"
fresh_gctk; run_fresh_tty '\n\n' tk-subj --no-attach
has "$OUT" "Enter = the first conversation" "(HOLD-NUMBERS) Enter names the conversation, not the first number's kind alone"
has "$CALLED" "session new converse-opus --alias tk-conv" "(HOLD-NUMBERS) …and takes it"

echo "# a gate several beads wait on takes the bead the operator came from"
export GATE_WAITERS='[{"id":"tk-subj","status":"open"},{"id":"tk-rework","status":"open"}]'
fresh_gctk; run_fresh_tty '2\n\n' tk-subj --no-attach
eq "$RC" 0 "(HOLD-FROM) a gate on the bead and another exits 0"
has "$CALLED" "bd dep bd dep add tk-conv tk-gate --type replies-to" "(HOLD-FROM) …and the bead's own conversation replies to it"
export HAVE_CONV=0
fresh_gctk; run_fresh_tty '1\n\n' tk-subj --no-attach
eq "$RC" 0 "(HOLD-FROM-NEW) a gate on the bead and another, with no conversation to take, exits 0"
has "$OUT" "tk-gate is a gate about tk-subj" "(HOLD-FROM-NEW) …saying which bead it takes"
hasnt "$OUT" "the one bead still waiting" "(HOLD-FROM-NEW) …which is one of two still waiting on it"
has "$CALLED" "--deps tracks:tk-subj" "(HOLD-FROM-NEW) …filing a conversation about the bead the gate was picked from"
hasnt "$CALLED" "--deps tracks:tk-rework" "(HOLD-FROM-NEW) …not the other bead waiting on it"
has "$CALLED" "--title Approve the rollout" "(HOLD-FROM-NEW) …titled with what the gate asks"
has "$CALLED" "Answer the human gate tk-gate on tk-subj" "(HOLD-FROM-NEW) …asking what the gate asks"
has "$CALLED" "bd dep bd dep add tk-new tk-gate --type replies-to" "(HOLD-FROM-NEW) …replying to the gate"
has "$CALLED" "session new converse-opus --alias tk-new" "(HOLD-FROM-NEW) …and holding it in a sitting"
fresh_gctk; run_fresh tk-gate --no-attach --no-input
eq "$RC" 4 "(HOLD-FROM-NEW) the same gate named outright is still refused"
hasnt "$CALLED" "bd create" "(HOLD-FROM-NEW) …filing nothing"
export HAVE_CONV=1
export GATE_WAITERS='[{"id":"tk-other","status":"open"},{"id":"tk-rework","status":"open"}]'
fresh_gctk; run_fresh_tty '2\n\n' tk-subj --no-attach
eq "$RC" 4 "(HOLD-FROM) a gate on two other beads is refused"
has "$OUT" "gate tk-gate is about 2 beads" "(HOLD-FROM) …naming them"
hasnt "$CALLED" "session new" "(HOLD-FROM) …and starts nothing"

echo "# nothing holding the bead leaves the prompt as it was"
export GATE_WAITERS='[{"id":"tk-rework","status":"open","dependency_type":"blocks"}]'
export GCTK_GATES='[]'
fresh_gctk; run_fresh_tty '\n\n' tk-subj --no-attach
hasnt "$OUT" "Held by human gate" "(HOLD-NONE) no heading"
has "$OUT" "[1-1] take a listed conversation · a letter or text starts a new one · Enter = the first listed" "(HOLD-NONE) …and the prompt it always had"
export HAVE_CONV=0
fresh_gctk; run_fresh_tty '\n\n' tk-subj --no-attach
has "$OUT" "a letter or text starts a new conversation · Enter = a new one, blank" "(HOLD-NONE) …with or without a conversation"

echo "# a reply beyond the list is an opener, not a gate"
export GCTK_GATES="$ONE_GATE"
fresh_gctk; run_fresh_tty '7\n\n\n' tk-subj --no-attach
has "$CALLED" "--deps tracks:tk-subj" "(HOLD-RANGE) a number no row carries opens a conversation on the bead"
hasnt "$CALLED" "--type replies-to" "(HOLD-RANGE) …and answers no gate"

echo "# an engage that asks nothing names the gates"
export HAVE_CONV=1
fresh_gctk; run_fresh tk-subj --no-attach --no-input
eq "$RC" 0 "(HOLD-NOINPUT) --no-input on a held bead exits 0"
has "$OUT" 'tk-subj is held by human gate tk-gate ("Approve the rollout"). To answer it: gc-helm engage tk-gate' "(HOLD-NOINPUT) …naming the gate and how to engage it"
hasnt "$(cat "$TMP/err")" "is held by human gate" "(HOLD-NOINPUT) …on stdout, all the board's route returns from an engage that exits 0"
has "$CALLED" "session new converse-opus --alias tk-conv" "(HOLD-NOINPUT) …and carrying on with the bead's conversation"
hasnt "$CALLED" "--type replies-to" "(HOLD-NOINPUT) …which answers no gate unasked"
fresh_gctk; run_fresh tk-subj --reason "a distinct concern" --no-attach
has "$OUT" "tk-subj is held by human gate tk-gate" "(HOLD-REASON) a concern on the argv names the gate too"
fresh_gctk; run_fresh_tty '\n' tk-subj --reason "a distinct concern" --no-attach
has "$OUT" "tk-subj is held by human gate tk-gate" "(HOLD-REASON) …on a TTY as well, whose prompt it skips"
export GCTK_GATES='[{"id":"tk-g1","title":"first"},{"id":"tk-g2","title":"second"}]'
fresh_gctk; run_fresh tk-subj --no-attach --no-input
has "$OUT" 'human gate tk-g1 ("first")' "(HOLD-NOINPUT) each gate is named"
has "$OUT" 'human gate tk-g2 ("second")' "(HOLD-NOINPUT) …the second too"
export GCTK_GATES='[]'
fresh_gctk; run_fresh tk-subj --no-attach --no-input
hasnt "$OUT" "is held by human gate" "(HOLD-NOINPUT) nothing holding it says nothing"
export GCTK_GATES="$ONE_GATE"

echo "# an engage pointed at a gate or a conversation does not look for others"
fresh_gctk; run_fresh tk-gate --no-attach --no-input
eq "$(gctk_calls)" "" "(HOLD-POINTED) a gate named on the argv reads no gates"
hasnt "$OUT" "is held by human gate" "(HOLD-POINTED) …and names none"
fresh_gctk; run_fresh_tty '\n\n' tk-gate --no-attach
eq "$(gctk_calls)" "" "(HOLD-POINTED) …nor at the prompt"
hasnt "$OUT" "Held by human gate" "(HOLD-POINTED) …which lists none"
fresh_gctk; run_fresh tk-conv --no-attach --no-input
eq "$(gctk_calls)" "" "(HOLD-CONVID) a conversation named on the argv reads no gates"

echo "# a read that does not answer is said, and stops nothing"
export GCTK_GATES_FAIL=1
fresh_gctk; run_fresh tk-subj --no-attach --no-input
eq "$RC" 0 "(HOLD-UNREAD) a reader that fails does not stop the engage"
has "$OUT" "could not read the human gates that hold tk-subj" "(HOLD-UNREAD) …which says so"
hasnt "$(cat "$TMP/err")" "could not read the human gates" "(HOLD-UNREAD) …on stdout, as the names of the gates are"
has "$CALLED" "session new converse-opus --alias tk-conv" "(HOLD-UNREAD) …and goes on"
fresh_gctk; run_fresh_tty '\n\n' tk-subj --no-attach
eq "$RC" 0 "(HOLD-UNREAD) …on a TTY as well"
has "$OUT" "could not read the human gates that hold tk-subj" "(HOLD-UNREAD) …saying so there"
unset GCTK_GATES_FAIL
GCTK_BIN=none run_fresh tk-subj --no-attach --no-input
has "$OUT" "could not read the human gates that hold tk-subj" "(HOLD-NOBIN) no gctk says the same"
eq "$RC" 0 "(HOLD-NOBIN) …and exits 0"
_hold_saved_bin="$GCTK_BIN"; unset GCTK_BIN
run_fresh tk-subj --no-attach --no-input
has "$OUT" "could not read the human gates that hold tk-subj" "(HOLD-NOBIN) a city root with no gctk built says the same"
mkdir -p "$TMP/city/.gc/services/gctk/bin"
cp "$TMP/bin/gctk-stub" "$TMP/city/.gc/services/gctk/bin/gctk"
GC_CITY_PATH="$TMP/city" run_fresh tk-subj --no-attach --no-input
has "$OUT" "tk-subj is held by human gate tk-gate" "(HOLD-CITYBIN) with no GCTK_BIN, engage reads the gctk the city deployed"
export GCTK_BIN="$_hold_saved_bin"

echo "# the real reader over an anchor, its rework and the gate on the rework"
ROOT="$(cd "$HERE/../.." && pwd)"
if ( cd "$ROOT/services/gctk" && go build -buildvcs=false -o "$TMP/gctk" ./cmd/gctk ) >"$TMP/gctk-build.log" 2>&1; then
  { printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; printf 'STUB_WALK=1 exec "%s/gctk" "$@"\n' "$TMP"; } > "$TMP/bin/gctk-real"
  chmod +x "$TMP/bin/gctk-real"
  export GCTK_BIN="$TMP/bin/gctk-real"
  REWORK_EDGE='{"id":"tk-rework","title":"fix the check","status":"open","issue_type":"task","dependency_type":"blocks"}'
  GATE_EDGE='{"id":"tk-gate","title":"Approve the rollout","status":"open","issue_type":"gate","await_type":"human","dependency_type":"blocks"}'
  export HAVE_CONV=0
  export WALK_EDGES='{"tk-subj":['"$REWORK_EDGE"'],"tk-rework":['"$GATE_EDGE"']}'
  run_fresh tk-subj --no-attach --no-input
  has "$OUT" 'tk-subj is held by human gate tk-gate ("Approve the rollout"). To answer it: gc-helm engage tk-gate' "(HOLD-REAL) a gate on the rework the anchor waits on is offered"
  run_fresh_tty '1\n\n' tk-subj --no-attach
  has "$OUT" '[1] tk-gate — "Approve the rollout"' "(HOLD-REAL) …at the prompt too"
  has "$CALLED" "--deps tracks:tk-rework" "(HOLD-REAL) …and engaging it takes the rework"
  export WALK_EDGES='{"tk-subj":['"$REWORK_EDGE"'],"tk-rework":[{"id":"tk-gate","status":"closed","issue_type":"gate","await_type":"human","dependency_type":"blocks"}]}'
  run_fresh tk-subj --no-attach --no-input
  hasnt "$OUT" "is held by human gate" "(HOLD-REAL) resolving the gate clears the offer"
  hasnt "$OUT" "could not read" "(HOLD-REAL) …on a read that answered"
  export WALK_EDGES='{"tk-subj":[{"id":"tk-c","status":"open","issue_type":"task","assignee":"human","dependency_type":"tracks"}]}'
  run_fresh tk-subj --no-attach --no-input
  hasnt "$OUT" "is held by human gate" "(HOLD-REAL) a conversation tracking the anchor offers nothing"
  unset WALK_EDGES
else
  bad "(HOLD-REAL) gctk did not build; the real reader was NOT exercised — $(tail -3 "$TMP/gctk-build.log" | tr '\n' ' ')"
fi
unset GCTK_BIN GCTK_GATES GATE_WAITERS HAVE_CONV
reset

echo
echo "gc-helm engage: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
