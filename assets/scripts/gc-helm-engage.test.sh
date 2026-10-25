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
#   (REASON-NEW) --reason files a fresh conversation even when one waits
#   (CONVID-REASON) --reason on an explicit conversation id is refused
#   (LIVE)    a conversation a live sitting holds is attached to, not doubled
#   (LEFT)    a conversation whose sitting's session closed is resumed under
#             the same alias, with no bind needed
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
#   (ALIAS-*, RACE-CONCURRENT) a spawn refused at the alias spawns nothing and
#             waits for the holder's bind; two engages of one conversation spawn
#             once and bind once
#   (ALIAS-RETRY) an id the runtime refuses as an alias is retried under c-
#   (ATTACH, START-*, NOATTACH-*) the attach waits until the sitting reads active
#   (SUSPENDED, CTRL-*) a suspended rig or a down controller refuses first
#   (IA-*)    the interactive prompts: subject, conversation or starter, model,
#             skill
#   (NEWSUBJ*) --new-subject files a marked subject and its one conversation
#   (SKILL*)  --skill files a new conversation whose ask is the lens brief
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
# 2 tk-conv and tk-conv2, 0 none. The gate tk-gate is a human gate; the beads waiting on
# it are $GATE_WAITERS (JSON). The live converse sessions are the lines of
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
  jq -n --arg c "$1" --arg a "$(asg_of "$1")" --arg st "$(stat_of "$1")" --arg s "$(subj_of "$1")" \
        --arg t "$_title" --arg cr "$_created" --arg shape "$2" --argjson r "${_reps:-[]}" '
    {id:$c, issue_type:"task", status:$st, assignee:$a, title:$t, created_at:$cr}
    + (if $shape == "show"
       then {dependencies:([{id:$s, dependency_type:"tracks"}] + [ $r[] | {id:., dependency_type:"replies-to"} ])}
       else {dependencies:([{issue_id:$c, depends_on_id:$s, type:"tracks"}] + [ $r[] | {issue_id:$c, depends_on_id:., type:"replies-to"} ])} end)'
}
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
                else {name:"loomington", path:"/nonexistent-city", prefix:"lx", hq:true}
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
    jq -n --arg live "$_live" --arg st "$_st" --arg sid "$SID" --arg sn "$SNAME" --arg sa "$_salias" \
          --arg holder "${ALIAS_HOLDER:-}" --arg decoys "${ALIAS_DECOYS:-}" --arg spawned "$_spawned" \
      '{sessions:([ $live | split(" ")[] | select(. != "") | split("=") | {id:.[0], session_name:("s-" + .[0]), alias:.[1], template:"gc-toolkit/gc-toolkit.converse-opus", state:"active", closed:false, created_at:"2026-10-01T00:00:00Z", attached:false} ]
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
      jq -c -n --argjson r "$(conv_row "$_id" list)" '[$r]'
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
              _rows='[]'
              for c in $(conv_ids); do
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
    printf 'session attach %s\n' "$*" >> "$CALLS" ;;
  "session close")
    printf 'session close %s\n' "$*" >> "$CALLS"
    [ -n "${CLOSE_STICKS:-}" ] || { awk -v s="$3" '$1 != s' "$ST/live" > "$ST/live.tmp" 2>/dev/null; mv "$ST/live.tmp" "$ST/live" 2>/dev/null || true; } ;;
  "session nudge")
    printf 'session nudge %s\n' "$*" >> "$CALLS" ;;
  "bd update")
    printf 'bd update %s\n' "$*" >> "$CALLS"
    _id="$3"; shift 3
    _ifa_set=0; _ifa=""; _new_set=0; _new=""; _notes=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --if-assignee) _ifa_set=1; _ifa="${2-}"; shift 2 ;;
        --assignee)    _new_set=1; _new="${2-}"; shift 2 ;;
        --append-notes) _notes=1; shift 2 ;;
        *) shift ;;
      esac
    done
    # bd's --if-assignee guard, checked and written under one lock, as the store
    # does: a mismatch writes nothing and exits 13. $RACE_LOST makes the guard
    # lose: another writer took the conversation in the spawn window, recorded
    # as $RACE_WINNER (empty for none) with status $RACE_STATUS. $BIND_FAIL fails
    # it for another reason, $BIND_NOPERSIST reports success and writes nothing,
    # and $BIND_STOMP overwrites the binding just written.
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
      [ "$_new_set" = 1 ] && printf '%s' "$_new" > "$ST/$_id.assignee"
      stub_unlock "$ST/$_id.lock"
      [ -n "${BIND_STOMP:-}" ] && printf '%s' "$BIND_STOMP" > "$ST/$_id.assignee"
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

export PATH="$TMP/bin:$PATH"
export CALLS="$TMP/calls" STATE_DIR="$TMP/state" ALIAS_REFUSED="$TMP/alias-refused"
export SPAWNED="$TMP/spawned" POLLS="$TMP/polls"
unset GC_HELM_FIXTURE || true
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
    find "${STATE_DIR:?}" -type f \( -name '*.assignee' -o -name '*.status' -o -name '*.subject' -o -name spawned-alias \) -delete
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
has "$CALLED" "bd update tk-conv --if-assignee human --assignee gc-toolkit/gc-toolkit.tk-conv" "(BIND) …guarded on the holder engage read, the operator's queue"
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
export ALIAS_DECOYS=1 GC_HELM_ENGAGE_BIND_WAIT=1
reset; run_engage tk-conv --no-attach
eq "$RC" 4 "(ALIAS-LEFTOVER) a holder that never binds exits 4"
has "$OUT" "did not bind it within 1s" "(ALIAS-LEFTOVER) …after waiting for a bind that never came"
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

echo
echo "gc-helm engage: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
