#!/usr/bin/env bash
# Hermetic test for the gc-helm `engage` verb.
#
# engage is the spawn-on-engagement entry point that replaces the retired
# converse routed-pool: it spawns a manual converse-<model> sitting, binds the
# picked visit to that session's runtime NAME (so the session's own
# `gc hook --claim` adopts it with no pool routing), and attaches once the
# reconciler has started it.
#
# Runs the REAL gc-helm.sh (invoked via `sh`, as shipped) with a stubbed `gc` on
# PATH — no live city, Dolt, network, or sessions. Covered:
#   (MODEL)   an unknown --model is refused before anything spawns (exit 2)
#   (NOARG)   a missing bead-id is refused (exit 2)
#   (VISIT)   engaging an OPEN visit spawns converse-opus --alias <visit>
#             --no-attach and binds the visit to the session's runtime name
#   (NO-KICK) an opus/fable (claude) sitting self-starts from its argv prompt and
#             is NOT kicked — a kick would land as a stale deferred reminder
#   (KICK-CODEX) a codex sitting, whose CLI is not trusted to consume the argv
#             prompt, keeps the START-directive kick, and (KICK-ORDER) that turn
#             precedes the attach; a lost/failed bind never kicks
#   (SUBJECT) engaging a subject resolves the one open visit tracking it
#   (REASON-NEW) a subject that already has a visit, engaged WITH --reason, gets
#             a SECOND new visit carrying the reason (title + body); the reason
#             reaches the sitting through that body, and rides the kick for codex
#   (NOREASON-EXISTING) the same subject with NO reason engages the existing
#             visit, filing nothing
#   (VISITID-REASON) --reason on an explicit visit id is refused (exit 2): a fresh
#             visit needs a subject, and the reason is never dropped silently
#   (VISITID-SUBJECT) an interactive engage of a visit id grounds the operator in
#             the SUBJECT the visit tracks and the reason it was filed (not the
#             visit's own row), skips the join-or-new prompt, and names the
#             subject in the success line
#   (MODELFLAG) --model codex spawns converse-codex
#   (BUSY)    a visit already in_progress under an owner is not re-spawned (exit 4)
#   (CLOSED)  a closed explicit visit is refused before spawning (exit 4)
#   (BLOCKED) a blocked explicit visit is refused before spawning (exit 4)
#   (NOSPAWN) a session new that returns no identity aborts without assigning
#   (TAKEN)   a bind whose --if-assignee guard is rejected (another writer took
#             or closed the visit in the spawn window) does not overwrite the
#             holder, CLOSES the sitting it spawned (a suspended one keeps its
#             alias, so the re-run the message advertises would be refused at
#             `session new`), and exits 4
#   (ALIAS)   a spawn refused because a session holds the visit's alias spawns
#             nothing, waits for the holder's bind and points at the winner, and
#             names the holder as left over, to close, only after the wait
#   (RACE-CONCURRENT) two engages of one visit run at once against a stub that
#             reserves the alias under a lock, as gascity does: one spawns and
#             binds, and the other spawns nothing and points at the winner
#   (ATTACH)  the default attaches to the captured session id; --no-attach does not
#   (START-*) the attach waits until the sitting's `gc session list` state reads
#             active, because an attach that reaches a sitting the reconciler
#             has not started launches it without its prompt. A sitting still
#             unstarted at GC_HELM_ENGAGE_WAIT_TIMEOUT is left unattached, with
#             the attach to run later; one that ends first exits 4 at once; a
#             sitting not yet listed, or a listing that fails, is waited through.
#             (NOATTACH-*) --no-attach does not wait, and (KICK-AFTER-START) a
#             codex kick on the attach path follows the wait
#   (BOUND-EXISTING) engaging a SUBJECT that binds a pre-existing visit names that
#             visit's subject and offers --reason to open a fresh one instead; an
#             explicit visit id and a freshly filed visit get no such hint
#   (MOOT-GATE) a bound pre-existing visit whose blocks-gate has since closed is
#             flagged possibly-moot from a read-only check of its blocks-deps
#   (SKILL)   --skill files a NEW visit whose body is the lens brief, the name
#             checked against the sitting's own roster (rig + model) and a bare
#             name resolved to its full one; the title and summary name it
#   (SKILL-TEMPLATE/REASON) an opener follows the lens brief and rides the title
#   (SKILL-CODEX) the codex roster is read for a codex sitting, and the brief
#             rides its kick
#   (SKILL-UNKNOWN/AMBIG/BADNAME) a name the roster lacks, a bare name two packs
#             carry, and a malformed or empty name are refused before anything
#             is filed or spawned (exit 2)
#   (SKILL-VISITID) --skill on an explicit visit id is refused (exit 2): its
#             brief is already written, so the message points at the subject
#   (SKILL-UNREAD) an unreadable roster seeds the typed name unverified
#   (SKILL-NEWSUBJ) --new-subject with --skill: the title is the opener
#   (IA-SKILL*) on a TTY a new visit is asked for a skill after the model (Enter
#             = none, ? lists, a number picks, an unknown name is asked again);
#             an existing visit is not asked
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
# A mkdir lock, so two concurrent engages see one atomic check-and-write: the
# alias reservation below, and the compare-and-swap of a REAL_CAS bd update.
stub_lock()   { _t=0; until mkdir "$1" 2>/dev/null; do sleep 0.02; _t=$((_t + 1)); [ "$_t" -lt 1500 ] || break; done; }
stub_unlock() { rmdir "$1" 2>/dev/null || true; }
case "$1 ${2:-}" in
  "rig list")
    # The HQ row leads, as gc lists it; its running flag is gc's probe of the city
    # controller, injected via $HQ_RUNNING. The rig's suspended/running are
    # injected via $RIG_SUSPENDED/$RIG_RUNNING. Unset means the field is ABSENT (an
    # older gc that does not report it), which the liveness guard reads as unknown
    # and does not refuse on — the default for every case that does not set them.
    # The rig's checkout path is $RIG_PATH, a fixture that carries converse
    # templates so the converse-template guard passes; a case points it at a
    # template-less dir to exercise the refusal.
    jq -n --arg susp "${RIG_SUSPENDED-}" --arg run "${RIG_RUNNING-}" --arg hq "${HQ_RUNNING-}" \
      '{rigs:[ ({name:"loomington", path:"/nonexistent-city", prefix:"lx", hq:true}
               + (if $hq   != "" then {running:   ($hq   == "true")} else {} end)),
               ({name:"gc-toolkit", path:(env.RIG_PATH // "/nonexistent-rig"), prefix:"tk", hq:false}
               + (if $susp != "" then {suspended: ($susp == "true")} else {} end)
               + (if $run  != "" then {running:   ($run  == "true")} else {} end)) ]}' ;;
  "session list")
    # Sessions the reclaim probe (sitting_is_gone) reads. Default: the current
    # $VIS_OWNER counts as live, so the pending/busy refusals hold unchanged. A
    # dead-sitting-reclaim case sets $LIVE_SITTINGS explicitly (space-separated
    # session names; empty = none live, so a bound owner reads as gone).
    # $SESSION_LIST_BROKEN makes the listing FAIL, so the probe fails closed.
    #
    # Once `session new` has spawned the sitting, each listing also carries that
    # sitting's own row, which engage's start wait reads. Its state walks
    # $START_STATES, one entry per listing, the last repeating: "active" (the
    # default: the reconciler has started it), start-pending, creating, or a
    # token. "gone" lists no row, the way a closed session reads from the store;
    # "blank" lists an empty state, the way it reads from the supervisor; and
    # "broken" fails the listing.
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
    _live="${LIVE_SITTINGS-$VIS_OWNER}"
    # $ALIAS_HOLDER adds the sitting that holds tk-vis's alias, stored qualified
    # the way gascity stores a multi-session template's alias. $ALIAS_DECOYS adds,
    # ahead of it, an open sitting of ANOTHER visit whose alias shares the prefix
    # and a CLOSED sitting that once held tk-vis's alias; neither holds it. In
    # the concurrent race the sittings the stub spawned are listed too.
    _spawned=""
    if [ -n "${ALIAS_REGISTRY:-}" ]; then
      for _f in "$ALIAS_REGISTRY"/held.*; do
        [ -f "$_f" ] && _spawned="$_spawned $(cat "$_f")=${_f##*/held.}"
      done
    fi
    jq -n --arg live "$_live" --arg st "$_st" --arg sid "$SID" --arg sn "$SNAME" \
          --arg holder "${ALIAS_HOLDER:-}" --arg decoys "${ALIAS_DECOYS:-}" --arg spawned "$_spawned" \
      '{sessions:([ $live | split(" ")[] | select(. != "") | {session_name:., name:., id:., state:"running", closed:false} ]
         + (if $st == "" or $st == "gone" then []
            else [{id:$sid, session_name:$sn, name:$sn, state:(if $st == "blank" then "" else $st end)}] end)
         + (if $decoys != "" then [{id:"gc-90", session_name:"s-gc-90", alias:"gc-toolkit/gc-toolkit.tk-vis2", template:"gc-toolkit/gc-toolkit.converse-opus", state:"active", closed:false},
                                   {id:"gc-91", session_name:"s-gc-91", alias:"gc-toolkit/gc-toolkit.tk-vis", template:"gc-toolkit/gc-toolkit.converse-opus", state:"closed", closed:true}] else [] end)
         + (if $holder != "" then [{id:$holder, session_name:("s-" + $holder), name:"gc-toolkit/gc-toolkit.tk-vis", alias:"gc-toolkit/gc-toolkit.tk-vis", template:"gc-toolkit/gc-toolkit.converse-opus", state:"active", closed:false}] else [] end)
         + [ $spawned | split(" ")[] | select(. != "") | split("=") | {id:.[0], session_name:("s-" + .[0]), alias:("gc-toolkit/gc-toolkit." + .[1]), template:"gc-toolkit/gc-toolkit.converse-opus", state:"creating", closed:false} ])}' ;;
  "agent list")
    # The import-resolved roster rig_carries_converse reads — capability comes
    # from here, NOT from a glob of $RIG_PATH's checkout. Default: gc-toolkit
    # carries converse (base + variants), so engage's converse guard passes.
    # $NO_CONVERSE drops the converse entries (the roster shows the rig without
    # converse — an HQ root, or a rig that does not import the pack); it keeps a
    # proactive entry to prove the guard is converse-specific. $ROSTER_BROKEN
    # fails the listing and $ROSTER_MALFORMED prints non-roster JSON, both to
    # exercise the fail-open path.
    if [ -n "${ROSTER_BROKEN:-}" ]; then echo "agent list: data plane down" >&2; exit 1; fi
    if [ -n "${ROSTER_MALFORMED:-}" ]; then printf '{"not":"a roster"}\n'; exit 0; fi
    if [ -n "${NO_CONVERSE:-}" ]; then
      jq -n '{agents:[{qualified_name:"gc-toolkit/gc-toolkit.proactive"}]}'
    else
      jq -n '{agents:[ "gc-toolkit/gc-toolkit.converse","gc-toolkit/gc-toolkit.converse-opus","gc-toolkit/gc-toolkit.converse-fable","gc-toolkit/gc-toolkit.converse-codex" | {qualified_name:.} ]}'
    fi ;;
  "bd show")
    id="$3"
    if [ "$id" = "tk-vis" ]; then
      # Once a spawn is refused at the alias ($ALIAS_REFUSED exists), the
      # refused engage polls this visit. The change it waits for lands on the
      # $AFTER_REFUSAL_READS-th read: a concurrent engage's bind
      # ($AFTER_REFUSAL_ASSIGNEE) or a status change ($AFTER_REFUSAL_STATUS).
      # $AFTER_REFUSAL_UNREADABLE makes every read after the refusal fail.
      if [ -f "$ALIAS_REFUSED" ]; then
        if [ -n "${AFTER_REFUSAL_UNREADABLE:-}" ]; then echo "bd show: data plane down" >&2; exit 1; fi
        _reads=$(( $(cat "$ALIAS_REFUSED.reads" 2>/dev/null || echo 0) + 1 ))
        printf '%s' "$_reads" > "$ALIAS_REFUSED.reads"
        if [ -n "${AFTER_REFUSAL_READS:-}" ] && [ "$_reads" -ge "$AFTER_REFUSAL_READS" ]; then
          [ -n "${AFTER_REFUSAL_ASSIGNEE:-}" ] && printf '%s' "$AFTER_REFUSAL_ASSIGNEE" > "$ASSIGNEE"
          [ -n "${AFTER_REFUSAL_STATUS:-}" ] && printf '%s' "$AFTER_REFUSAL_STATUS" > "$VIS_STATUS"
        fi
      fi
      st="$(cat "$VIS_STATUS" 2>/dev/null || echo open)"
      who="$(cat "$ASSIGNEE" 2>/dev/null)"; [ -n "$who" ] || who="$VIS_OWNER"
      # The subject rides on the gc.continuation_group stamp by default. A case may
      # blank $VIS_CGROUP and set $VIS_TRACKS to exercise the tracks-edge fallback:
      # `gc bd show` renders that edge as a dependency bead row keyed
      # .dependency_type/.id, which is the shape the fallback must read.
      jq -n --arg i "$id" --arg s "$st" --arg a "$who" \
            --arg cg "${VIS_CGROUP-tk-subj}" --arg tr "${VIS_TRACKS-}" \
        '[{id:$i, title:"visit: tk-subj — compare notes on the WIP proposals", status:$s, assignee:$a, metadata:{task_kind:"visit","gc.continuation_group":$cg}}
          + (if $tr != "" then {dependencies:[{id:$tr, dependency_type:"tracks", title:"the subject under engagement", status:"open", issue_type:"task", priority:2}]} else {} end)]'
    else
      jq -n --arg i "$id" --arg k "${BEAD_KIND:-task}" --arg t "${SUBJ_TITLE:-the subject under engagement}" \
        '[{id:$i, title:$t, status:"open", issue_type:"task", priority:2, assignee:"", metadata:{task_kind:$k}}]'
    fi ;;
  "bd list")
    case "$*" in
      *--title-contains*)
        # The subject title search (engage_prompt_subject). $SEARCH_HIT injects a
        # matching NON-visit bead so a search resolves; unset = no match.
        if [ -n "${SEARCH_HIT:-}" ]; then
          jq -n '[{id:"tk-subj", status:"open", assignee:"", title:"a searchable subject", metadata:{task_kind:"task"}}]'
        else printf '[]\n'; fi ;;
      *)
        # The open visit(s) tracking tk-subj, when $HAVE_VISIT is set. Titles are
        # carried so the interactive visit menu has something to show.
        if [ "${HAVE_VISIT:-}" = "2" ]; then
          jq -n '[{id:"tk-vis2", status:"open", assignee:"", created_at:"2026-09-02T00:00:00Z", title:"visit: tk-subj — second concern", metadata:{task_kind:"visit","gc.continuation_group":"tk-subj"}},
                  {id:"tk-vis", status:"open", assignee:"", created_at:"2026-09-01T00:00:00Z", title:"visit: tk-subj — first concern", metadata:{task_kind:"visit","gc.continuation_group":"tk-subj"}}]'
        elif [ "${HAVE_VISIT:-}" = "held" ]; then
          jq -n '[{id:"tk-vis2", status:"in_progress", assignee:"gc-toolkit__converse-3", title:"visit: tk-subj — held", metadata:{task_kind:"visit","gc.continuation_group":"tk-subj"}},
                  {id:"tk-vis", status:"open", assignee:"", title:"visit: tk-subj — parked", metadata:{task_kind:"visit","gc.continuation_group":"tk-subj"}}]'
        elif [ -n "${HAVE_VISIT:-}" ]; then
          jq -n '[{id:"tk-vis", status:"open", assignee:"", title:"visit: tk-subj — the concern", metadata:{task_kind:"visit","gc.continuation_group":"tk-subj"}}]'
        else printf '[]\n'; fi ;;
    esac ;;
  "session new")
    printf 'session new %s\n' "$*" >> "$CALLS"
    # Record the rig context engage supplies: `gc session new` resolves a bare
    # template through GC_DIR/cwd, so engage must point it at the subject's rig.
    printf 'GC_DIR=%s\n' "${GC_DIR-<unset>}" >> "$CALLS"
    # gascity checks an alias and creates the session holding it inside one
    # city-wide lock, and refuses an alias an open session holds before creating
    # anything, on stderr, with the sentinel "session alias already exists" and
    # the alias in its stored qualified form.
    if [ -n "${ALIAS_REGISTRY:-}" ]; then
      # The concurrent race. Each spawn first waits at a barrier until
      # $SPAWN_BARRIER spawns have arrived, so every engage has passed its
      # pre-spawn guards before any reserves; then the alias is checked and
      # taken under one lock. The first spawn holds it, and records how many
      # spawns had arrived when it reserved; a later one is refused.
      _al=$(printf '%s\n' "$*" | sed -n 's/.* --alias \([^ ]*\).*/\1/p')
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
      echo "gc session new: session alias already exists: \"gc-toolkit/gc-toolkit.tk-vis\" already belongs to $ALIAS_HELD" >&2
      exit 1
    fi
    if [ -n "${SPAWN_EMPTY:-}" ]; then
      echo "gc session new: agent \"converse-opus\" not found in city.toml" >&2; jq -n '{ok:true}'
    elif [ -n "${ALIAS_COLLIDE:-}" ] && case "$*" in *"--alias v-"*) false ;; *) true ;; esac; then
      # ValidateAlias refuses an alias matching the session-id syntax (a gascity
      # all-numeric bead id, gc-62297) before any session spawns, wrapping the
      # sentinel "invalid session alias"; only the v- retry passes here.
      echo 'gc session new: invalid session alias: "gc-62297" conflicts with session ID syntax' >&2; jq -n '{ok:true}'
    else
      printf '%s' "$SID" > "$SPAWNED"
      jq -n --arg id "$SID" --arg n "$SNAME" '{schema_version:"1", ok:true, session_id:$id, session_name:$n, alias:"tk-vis", template:"t", transport:"tmux", work_dir:"/w", deferred_start:true, attached:false}'
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
  "session suspend")
    printf 'session suspend %s\n' "$*" >> "$CALLS" ;;
  "session close")
    printf 'session close %s\n' "$*" >> "$CALLS" ;;
  "session nudge")
    printf 'session nudge %s\n' "$*" >> "$CALLS" ;;
  "bd update")
    printf 'bd update %s\n' "$*" >> "$CALLS"
    _a="$*"
    if [ -n "${REAL_CAS:-}" ]; then
      # bd's --if-assignee/--if-status guard, checked and written under one
      # lock, as the store does: a mismatch writes nothing and exits 13.
      shift 3
      _ifa_set=0; _ifa=""; _ifs=""; _new_set=0; _new=""
      while [ $# -gt 0 ]; do
        case "$1" in
          --if-assignee) _ifa_set=1; _ifa="${2-}"; shift 2 ;;
          --if-status)   _ifs="${2-}"; shift 2 ;;
          --assignee)    _new_set=1; _new="${2-}"; shift 2 ;;
          *) shift ;;
        esac
      done
      stub_lock "$ASSIGNEE.lock"
      _cur="$(cat "$ASSIGNEE" 2>/dev/null)"; [ -n "$_cur" ] || _cur="${VIS_OWNER:-}"
      _cst="$(cat "$VIS_STATUS" 2>/dev/null || echo open)"
      if { [ "$_ifa_set" = 1 ] && [ "$_cur" != "$_ifa" ]; } || { [ -n "$_ifs" ] && [ "$_cst" != "$_ifs" ]; }; then
        stub_unlock "$ASSIGNEE.lock"; exit 13
      fi
      [ "$_new_set" = 1 ] && printf '%s' "$_new" > "$ASSIGNEE"
      stub_unlock "$ASSIGNEE.lock"
      exit 0
    fi
    # Model the real `bd update --if-assignee/--if-status` guard: on a mismatch
    # it writes nothing and exits 13 (vs 1 for other failures). $RACE_LOST forces
    # the guarded bind to lose: another writer took the visit in the spawn window.
    # It records that holder ($RACE_WINNER; set it empty for none) and the visit's
    # new status ($RACE_STATUS) so the read-back `bd show` reports them. An
    # unconditional update (no --if-assignee) always writes, as before.
    case "$_a" in
      *" --if-assignee "*)
        if [ -n "${RACE_LOST:-}" ]; then
          printf '%s' "${RACE_WINNER-gc-toolkit__converse-9}" > "$ASSIGNEE"
          [ -n "${RACE_STATUS:-}" ] && printf '%s' "$RACE_STATUS" > "$VIS_STATUS"
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
    printf 'bd create %s\n' "$*" >> "$CALLS"
    # --new-subject creates the SUBJECT bead with --metadata (and --db); cmd_open
    # creates the VISIT with neither. Distinguish so each returns its own id.
    # $SUBJ_CREATE_FAIL makes the subject create fail (bare error object, no id).
    case "$*" in
      *--metadata*)
        if [ -n "${SUBJ_CREATE_FAIL:-}" ]; then jq -n '{error:"store write refused"}'
        else jq -n --arg i "${NEW_SUBJECT_ID:-tk-newsubj}" '{id:$i}'; fi ;;
      *) jq -n '{id:"tk-vis"}' ;;
    esac ;;
  "bd dep")   printf 'bd dep %s\n' "$*" >> "$CALLS"
              # engage probes the visit's blockers (dep list --direction=down)
              # before spawning: default none. $VIS_BLOCKERS injects OPEN "blocks"
              # edges so a blocked visit can be exercised; $VIS_CLOSED_GATES injects
              # CLOSED "blocks" edges — a satisfied gate whose closure means the
              # visit's premise may be moot. Both empty yields the [] default.
              jq -n --arg open "${VIS_BLOCKERS:-}" --arg closed "${VIS_CLOSED_GATES:-}" \
                '[ ($open   | split(" ")[] | select(. != "") | {id:., dependency_type:"blocks", status:"open"}),
                   ($closed | split(" ")[] | select(. != "") | {id:., dependency_type:"blocks", status:"closed"}) ]' ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

export PATH="$TMP/bin:$PATH"
export CALLS="$TMP/calls" ASSIGNEE="$TMP/assignee" VIS_STATUS="$TMP/vstatus" ALIAS_REFUSED="$TMP/alias-refused"
export SPAWNED="$TMP/spawned" POLLS="$TMP/polls"
unset GC_HELM_FIXTURE || true
export TMPDIR="$TMP"

# A fixture agents dir, so the converse-<model> list engage globs is hermetic —
# independent of the repo's live agents/. A bare `converse` is present to prove
# it is EXCLUDED from the model list.
mkdir -p "$TMP/agents/converse-opus" "$TMP/agents/converse-fable" \
         "$TMP/agents/converse-codex" "$TMP/agents/converse"
export GC_HELM_AGENTS_DIR="$TMP/agents"

# The subject rig's checkout. Converse CAPABILITY now comes from the resolved
# roster (gc agent list), not a glob of this tree, so these converse-* dirs no
# longer gate engage — they stay only as a realistic checkout. $TMP/rig-bare is a
# checkout with NO converse templates but a .beads ledger: the importer case
# proves engage still proceeds from it when the roster registers converse.
# Distinct from GC_HELM_AGENTS_DIR above (the pack's own model-menu dir).
mkdir -p "$TMP/rig/agents/converse-opus" "$TMP/rig/agents/converse-fable" \
         "$TMP/rig/agents/converse-codex" "$TMP/rig/.beads" \
         "$TMP/rig-bare" "$TMP/rig-bare/.beads"
export RIG_PATH="$TMP/rig"

# run_engage <bead> [extra-args...] -> RC/OUT, with per-case env preset by caller.
# stdin is /dev/null so the run is non-interactive regardless of the terminal the
# suite is launched from ([ -t 0 ] is false); the interactive path is driven by
# run_engage_tty below.
run_engage() {
    : > "$CALLS"; : > "$ASSIGNEE"; : > "$SPAWNED"; : > "$POLLS"; rm -f "$ALIAS_REFUSED" "$ALIAS_REFUSED.reads"
    set +e
    OUT="$(sh "$SCRIPT" engage "$@" </dev/null 2>"$TMP/err")"; RC=$?
    set -e
    OUT="$OUT$(cat "$TMP/err")"
    CALLED="$(cat "$CALLS")"
}

# run_engage_tty <printf-format-of-answers> [args...] -> RC/OUT. Drives the
# interactive prompts: GC_HELM_ASSUME_TTY forces the interactive path when stdin
# is a pipe (a hermetic test has no real tty), and the answers feed the reads in
# order. The answer string is a printf %b format, so lines are '\n'-separated.
run_engage_tty() {
    _ans="$1"; shift
    : > "$CALLS"; : > "$ASSIGNEE"; : > "$SPAWNED"; : > "$POLLS"; rm -f "$ALIAS_REFUSED" "$ALIAS_REFUSED.reads"
    set +e
    OUT="$(printf '%b' "$_ans" | GC_HELM_ASSUME_TTY=1 sh "$SCRIPT" engage "$@" 2>"$TMP/err")"; RC=$?
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

# A recorder standing in for pr-visit-comment.sh, to prove engage posts the
# "open" reminder for the subject the visit tracks (not the visit itself).
cat > "$TMP/rec-pvc" <<'REC'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$REC_PVC_LOG"
REC
chmod +x "$TMP/rec-pvc"
export GC_VISIT_COMMENT_TOOL="$TMP/rec-pvc" REC_PVC_LOG="$TMP/pvc.log"

echo "# engaging an OPEN visit spawns a sitting and binds the visit to it"
export BEAD_KIND=visit VIS_OWNER="" HAVE_VISIT=""
printf 'open' > "$VIS_STATUS"
: > "$TMP/pvc.log"
run_engage tk-vis --no-attach
eq "$RC" 0 "(VISIT) engaging an open visit exits 0"
has "$(cat "$TMP/pvc.log")" "engage --visit tk-vis --subject tk-subj" \
    "(VISIT-PRCOMMENT) engage posts the open reminder on the subject the visit tracks, not the visit id"
has "$CALLED" "session new converse-opus --alias tk-vis --no-attach --json" "(VISIT) spawns converse-opus --alias <visit> --no-attach"
eq "$(cat "$ASSIGNEE")" "gc-toolkit__converse-1" "(BIND) the visit is assigned to the session's runtime name"
has "$CALLED" "bd update tk-vis --if-assignee" "(BIND) …conditionally, on the open+unassigned state the guards read"
has "$CALLED" "--if-status open" "(BIND) …and on the open status, so a lost race writes nothing"
has "$CALLED" "--assignee gc-toolkit__converse-1" "(BIND) …by name, the identity the claim adopts"
# An opus (claude) sitting self-starts from the prompt its launch delivers on
# argv, so engage sends it no kick. A kick here would land as a deferred reminder
# after the sitting has already framed — the stale "begin now" this removes.
hasnt "$CALLED" "session nudge" "(NO-KICK) an opus sitting self-starts from its prompt and is not kicked"
# An explicit visit id is engaged as-is; it is not the subject-binds-a-pre-existing
# case, so it gets no "bound the pre-existing …" hint or --reason alternative.
hasnt "$OUT" "bound the pre-existing" "(VISIT) an explicit visit id is not reported as a subject-bound pre-existing visit"

echo "# an explicit visit whose group stamp is empty resolves the PR subject from its tracks edge"
export BEAD_KIND=visit VIS_OWNER="" HAVE_VISIT="" VIS_CGROUP="" VIS_TRACKS="tk-subj"
printf 'open' > "$VIS_STATUS"
: > "$TMP/pvc.log"
run_engage tk-vis --no-attach
unset VIS_CGROUP VIS_TRACKS
eq "$RC" 0 "(VISIT-PRCOMMENT-TRACKS) engaging a visit with an empty group stamp exits 0"
has "$(cat "$TMP/pvc.log")" "engage --visit tk-vis --subject tk-subj" \
    "(VISIT-PRCOMMENT-TRACKS) the reminder lands on the tracked subject recovered from the edge, not the visit id"

echo "# --model selects the tier; codex is the one provider that keeps the kick"
run_engage tk-vis --model codex --no-attach
has "$CALLED" "session new converse-codex --alias tk-vis" "(MODELFLAG) --model codex spawns converse-codex"
# The codex CLI is not trusted to consume its argv prompt at launch, so a codex
# sitting can wake idle; it keeps the START-directive kick. An idle session takes
# it immediately, so no turn is in flight for the harness to defer it behind.
has "$CALLED" "session nudge gc-77" "(KICK-CODEX) a codex sitting is sent its START-directive opening turn"
has "$CALLED" "Begin now" "(KICK-CODEX) …as a START directive, not a bare poke read as a connectivity check"

echo "# engage supplies the subject's rig context so a bare template resolves"
# The converse templates are rig-scoped — there is no city-scoped bare
# converse-<model>, and `gc session new` resolves the name through GC_DIR/cwd,
# not GC_RIG. So from a non-rig cwd (the city root, where the tmux board picker
# runs) engage must point GC_DIR at the subject's rig or nothing spawns.
export BEAD_KIND=visit VIS_OWNER="" HAVE_VISIT=""
printf 'open' > "$VIS_STATUS"
: > "$CALLS"; : > "$ASSIGNEE"; : > "$SPAWNED"; : > "$POLLS"
set +e
OUT="$(cd "$TMP" && sh "$SCRIPT" engage tk-vis --no-attach 2>"$TMP/err")"; RC=$?
set -e
CALLED="$(cat "$CALLS")"
eq "$RC" 0 "(RIGCTX) engaging from a non-rig cwd exits 0"
has "$CALLED" "GC_DIR=$TMP/rig" "(RIGCTX) session new runs under the subject's rig via GC_DIR, not the ambient cwd"

echo "# engaging a SUBJECT resolves the one open visit tracking it"
export BEAD_KIND=task HAVE_VISIT=1
printf 'open' > "$VIS_STATUS"
run_engage tk-subj --no-attach
eq "$RC" 0 "(SUBJECT) engaging a subject with an open visit exits 0"
has "$CALLED" "session new converse-opus --alias tk-vis --no-attach --json" "(SUBJECT) spawns for the tracking visit"
unset HAVE_VISIT

echo "# --reason files a fresh visit for a distinct concern, even when one exists"
# A reason typed at engage time is a likely-distinct concern, so it gets its OWN
# new visit rather than folding into an existing one. The reason reaches the
# sitting through the new visit's body (its claim-time brief), which every
# sitting reads when it claims; for codex it also rides the kick.
export BEAD_KIND=task HAVE_VISIT=1 VIS_OWNER=""
printf 'open' > "$VIS_STATUS"
run_engage tk-subj --reason "a distinct concern" --no-attach
eq "$RC" 0 "(REASON-NEW) engaging a subject-with-visit WITH --reason exits 0"
has "$CALLED" "bd create" "(REASON-NEW) …a NEW visit is filed, not the existing one engaged"
has "$CALLED" "visit: tk-subj — a distinct concern" "(REASON-NEW) …its title tail carries the reason"
has "$CALLED" "-d a distinct concern" "(REASON-NEW) …and its body (the claim-time brief) too"
hasnt "$OUT" "already open" "(REASON-NEW) …bypassing the one-visit-per-subject dedup on purpose"
# The internal file-a-visit path must not leak cmd_open's terminal success
# chatter: engage emits the human summary on stdout and one [debug] line on
# stderr, and cmd_open's "…filed / Engage it when ready" advice is stale once
# engage binds the sitting. run_engage folds stderr into OUT, so this catches a
# leak on either stream.
hasnt "$OUT" "no session spawned" "(REASON-NEW) …cmd_open's success chatter is suppressed, not redirected to stderr"
hasnt "$OUT" "Engage it when ready" "(REASON-NEW) …including its now-stale engage-later advice"
has "$CALLED" "session new converse-opus --alias tk-vis" "(REASON-NEW) …then spawns a sitting for the new visit"
hasnt "$CALLED" "session nudge" "(REASON-NEW) …and the opus sitting is not kicked; it reads the reason from the body"
hasnt "$OUT" "bound the pre-existing" "(REASON-NEW) …and no pre-existing-bind hint: --reason filed a fresh visit, it did not bind an old one"
# codex keeps the kick, so the reason also rides it — the sitting has it without
# waiting to read the body.
export BEAD_KIND=task HAVE_VISIT=1 VIS_OWNER=""
printf 'open' > "$VIS_STATUS"
run_engage tk-subj --reason "a distinct concern" --model codex --no-attach
has "$CALLED" "The operator's reason: a distinct concern" "(REASON-CODEX) the reason rides the codex opening-turn kick"
unset HAVE_VISIT

echo "# with NO reason, a subject-with-visit engages the EXISTING visit, filing nothing"
# The other half of the rule: no reason means engage what is already parked.
export BEAD_KIND=task HAVE_VISIT=1 VIS_OWNER=""
printf 'open' > "$VIS_STATUS"
run_engage tk-subj --no-attach
eq "$RC" 0 "(NOREASON-EXISTING) engaging a subject-with-visit and no reason exits 0"
hasnt "$CALLED" "bd create" "(NOREASON-EXISTING) …no new visit is filed"
has "$CALLED" "session new converse-opus --alias tk-vis" "(NOREASON-EXISTING) …the existing visit is engaged"
has "$OUT" "bound the pre-existing" "(BOUND-EXISTING) …and the output flags that a visit that already existed was bound"
has "$OUT" "compare notes on the WIP proposals" "(BOUND-EXISTING) …naming the bound visit's subject, not just its id"
has "$OUT" "engage tk-subj --reason" "(BOUND-EXISTING) …and offering --reason on the subject to open a fresh visit instead"
hasnt "$OUT" "moot" "(BOUND-EXISTING) …with no moot warning when the visit gates nothing"
unset HAVE_VISIT

echo "# --reason on an EXPLICIT visit id is refused — a fresh visit needs a subject"
# Naming an exact visit and --reason conflict: the reason has nowhere to go, and
# silently dropping it is the bug this verb exists to stop. Refuse and point at
# the subject form; never fold the reason into the named visit.
export BEAD_KIND=visit VIS_OWNER="" HAVE_VISIT=""
printf 'open' > "$VIS_STATUS"
run_engage tk-vis --reason "some reason" --no-attach
eq "$RC" 2 "(VISITID-REASON) --reason with an explicit visit id is a usage error (exit 2)"
hasnt "$CALLED" "session new" "(VISITID-REASON) …nothing is spawned"
hasnt "$CALLED" "bd create" "(VISITID-REASON) …and no visit is filed"
has "$OUT" "--reason" "(VISITID-REASON) …the message explains the flag conflict"

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

echo "# a visit another writer takes in the spawn window is not overwritten"
# Another engage of this visit never reaches the bind, because the alias refuses
# it (the ALIAS and RACE-CONCURRENT cases below), but `gc session new` takes real
# time and any other writer can change the visit in that window. The bind is
# conditional (--if-assignee "" --if-status open), so it writes nothing and exits
# 13. The sitting this engage spawned holds nothing and is closed, and the
# operator is pointed at whoever holds the visit now. The stub rejects the
# guarded update and records that holder.
# Run on codex, the one provider engage kicks: the abort precedes the kick block,
# so "never kicked" here proves that order rather than passing vacuously the way
# an un-kicked claude sitting would.
export BEAD_KIND=visit VIS_OWNER="" HAVE_VISIT=""
export RACE_LOST=1 RACE_WINNER="gc-toolkit__converse-8"
run_engage tk-vis --model codex --no-attach
eq "$RC" 4 "(TAKEN) a bind lost to another writer exits 4"
has "$CALLED" "session new" "(TAKEN) …the sitting did spawn: the visit changed after the pre-spawn guards read it"
has "$CALLED" "bd update tk-vis --if-assignee" "(TAKEN) …the bind is conditional, so the store rejects it (exit 13)"
eq "$(cat "$ASSIGNEE")" "gc-toolkit__converse-8" "(TAKEN) …the assignee stays the holder, never this engage's sitting"
has "$CALLED" "session close gc-77" "(TAKEN) …the sitting that holds nothing is closed"
has "$OUT" "not overwriting" "(TAKEN) …and the operator is told the holder was not overwritten"
has "$OUT" "gc session attach gc-toolkit__converse-8" "(TAKEN) …and is pointed at the holder"
hasnt "$CALLED" "session nudge" "(TAKEN) …and the closed codex sitting is never kicked — the abort precedes the kick"
unset RACE_LOST RACE_WINNER

echo "# a visit closed in the spawn window: nothing to bind and no holder to attach to"
export BEAD_KIND=visit VIS_OWNER="" HAVE_VISIT=""
printf 'open' > "$VIS_STATUS"
export RACE_LOST=1 RACE_WINNER="" RACE_STATUS=closed
run_engage tk-vis --no-attach
eq "$RC" 4 "(TAKEN-CLOSED) a bind lost to a close exits 4"
has "$CALLED" "session close gc-77" "(TAKEN-CLOSED) …the spawned sitting is closed"
has "$OUT" "became 'closed'" "(TAKEN-CLOSED) …and the operator is told the visit closed"
hasnt "$OUT" "session attach" "(TAKEN-CLOSED) …not pointed at a holder that does not exist"
unset RACE_LOST RACE_WINNER RACE_STATUS
printf 'open' > "$VIS_STATUS"

echo "# an engage refused at the alias waits for the winner's bind, then points at the winner"
# gascity checks an alias and creates the session holding it under one city-wide
# lock, and engage spawns under the visit id, so of two engages of one visit the
# second is refused at `gc session new` having spawned nothing. Its alias holder
# is the engage that won, about to bind the visit. The refused engage waits for
# that bind, then points the operator at the winner; it must never tell them to
# close a sitting that may be the one that won. The bind lands on the second
# read, so an engage that read the visit only once would name the winner as left
# over and tell the operator to close it.
export BEAD_KIND=visit VIS_OWNER="" HAVE_VISIT=""
printf 'open' > "$VIS_STATUS"
export ALIAS_HELD="gc-81" ALIAS_HOLDER="gc-81" AFTER_REFUSAL_READS=2 AFTER_REFUSAL_ASSIGNEE="s-gc-81" GC_HELM_ENGAGE_BIND_WAIT=5
run_engage tk-vis --model codex --no-attach
eq "$RC" 4 "(ALIAS-BOUND) an engage refused at the alias exits 4"
has "$CALLED" "session new converse-codex --alias tk-vis" "(ALIAS-BOUND) …after its spawn was refused"
has "$OUT" "engaged by 's-gc-81'" "(ALIAS-BOUND) …reporting the winner once its bind lands"
has "$OUT" "gc session attach s-gc-81" "(ALIAS-BOUND) …and pointing the operator at it to attach"
hasnt "$OUT" "gc session close" "(ALIAS-BOUND) …never telling them to close the sitting that won"
hasnt "$CALLED" "bd update" "(ALIAS-BOUND) …writing nothing to the visit"
hasnt "$CALLED" "session close" "(ALIAS-BOUND) …closing nothing"
hasnt "$CALLED" "session nudge" "(ALIAS-BOUND) …and kicking nothing, since it spawned nothing"
unset AFTER_REFUSAL_READS AFTER_REFUSAL_ASSIGNEE
printf 'open' > "$VIS_STATUS"

echo "# a holder that never binds is named as left over, and closing it is suggested only then"
# An engage that stopped between its spawn and its bind leaves a sitting that
# holds the alias and nothing else, and the visit stays parked. Once the wait
# ends with the visit still unbound, the refused engage names that sitting and
# says to close it if no other engage of the visit is running. The holder is
# matched by the whole final segment of its alias, so another visit's sitting
# whose alias shares the prefix, and a closed sitting, are never named.
export ALIAS_DECOYS=1 GC_HELM_ENGAGE_BIND_WAIT=1
run_engage tk-vis --no-attach
eq "$RC" 4 "(ALIAS-LEFTOVER) a holder that never binds exits 4"
has "$OUT" "did not bind the visit within 1s" "(ALIAS-LEFTOVER) …after waiting for a bind that never came"
has "$OUT" "gc session close gc-81" "(ALIAS-LEFTOVER) …naming the holder to close"
has "$OUT" "If no other engage of tk-vis is still running" "(ALIAS-LEFTOVER) …only on the condition that no engage is still binding it"
hasnt "$OUT" "gc-90" "(ALIAS-LEFTOVER) …never another visit's sitting whose alias shares the prefix"
hasnt "$OUT" "gc-91" "(ALIAS-LEFTOVER) …nor a closed sitting that once held the alias"
hasnt "$CALLED" "session close" "(ALIAS-LEFTOVER) …and it closes nothing itself"
unset ALIAS_HOLDER

echo "# an alias holder gone by the end of the wait: re-run"
run_engage tk-vis --no-attach
eq "$RC" 4 "(ALIAS-GONE) an alias no open session holds any more exits 4"
has "$OUT" "no open session holds it now" "(ALIAS-GONE) …saying the holder is gone"
has "$OUT" "re-run" "(ALIAS-GONE) …and that a re-run will spawn"
hasnt "$OUT" "gc session close" "(ALIAS-GONE) …with nothing to close"
unset ALIAS_DECOYS

echo "# an unreadable session list names no holder and proves none gone"
export ALIAS_HOLDER="gc-81" SESSION_LIST_BROKEN=1
run_engage tk-vis --no-attach
eq "$RC" 4 "(ALIAS-LISTFAIL) an unreadable session list exits 4"
has "$OUT" "could not be read to name it" "(ALIAS-LISTFAIL) …saying the holder could not be named"
hasnt "$OUT" "no open session holds it now" "(ALIAS-LISTFAIL) …never claiming the holder is gone"
hasnt "$OUT" "gc session close" "(ALIAS-LISTFAIL) …and naming nothing to close"
unset ALIAS_HOLDER SESSION_LIST_BROKEN

echo "# a visit closed during the wait is reported as not open"
export AFTER_REFUSAL_READS=1 AFTER_REFUSAL_STATUS=closed
run_engage tk-vis --no-attach
eq "$RC" 4 "(ALIAS-CLOSED) a visit closed while the engage waited exits 4"
has "$OUT" "is 'closed', not open" "(ALIAS-CLOSED) …saying so"
hasnt "$OUT" "gc session close" "(ALIAS-CLOSED) …and naming nothing to close"
unset AFTER_REFUSAL_READS AFTER_REFUSAL_STATUS
printf 'open' > "$VIS_STATUS"

echo "# a visit unreadable through the wait is no proof the holder is left over"
export ALIAS_HOLDER="gc-81" AFTER_REFUSAL_UNREADABLE=1
run_engage tk-vis --no-attach
eq "$RC" 4 "(ALIAS-UNREAD) an unreadable visit exits 4"
has "$OUT" "could not be read" "(ALIAS-UNREAD) …saying the visit could not be read"
hasnt "$OUT" "gc session close" "(ALIAS-UNREAD) …and never telling the operator to close the holder"
unset ALIAS_HELD ALIAS_HOLDER AFTER_REFUSAL_UNREADABLE GC_HELM_ENGAGE_BIND_WAIT

echo "# two concurrent engages of one visit: the alias admits one, and the other spawns nothing"
# A real race, not a scripted one. Both engages start together, and the stub's
# spawn holds each at a barrier until both have arrived, so both have read the
# visit open and unassigned and passed every pre-spawn guard before either
# reserves anything. The stub then reserves the alias under one lock, as gascity
# does, and runs every bind as bd's compare-and-swap under one lock.
export BEAD_KIND=visit VIS_OWNER="" HAVE_VISIT=""
printf 'open' > "$VIS_STATUS"
REG="$TMP/alias-registry"; rm -rf "$REG"; mkdir -p "$REG"
: > "$CALLS"; : > "$ASSIGNEE"; : > "$SPAWNED"; : > "$POLLS"; rm -f "$ALIAS_REFUSED" "$ALIAS_REFUSED.reads"
set +e
for r in a b; do
  ( ALIAS_REGISTRY="$REG" SPAWN_BARRIER=2 REAL_CAS=1 \
      sh "$SCRIPT" engage tk-vis --no-attach --no-input </dev/null >"$TMP/race-$r.out" 2>&1
    echo "$?" > "$TMP/race-$r.rc" ) &
done
wait
set -e
RC_A="$(cat "$TMP/race-a.rc")"; RC_B="$(cat "$TMP/race-b.rc")"
CALLED="$(cat "$CALLS")"
eq "$(cat "$REG/arrivals-at-reserve" 2>/dev/null)" "2" "(RACE-CONCURRENT) both engages had passed the pre-spawn guards when the first reserved the alias"
eq "$(grep -c '^session new ' "$CALLS" || true)" "2" "(RACE-CONCURRENT) both engages attempted the spawn"
eq "$(grep -c '^spawned ' "$CALLS" || true)" "1" "(RACE-CONCURRENT) exactly one sitting was spawned"
WIN_SID="$(sed -n 's/^spawned //p' "$CALLS" | head -n1)"
LOSER=""
if [ "$RC_A" = 0 ] && [ "$RC_B" = 4 ]; then LOSER=b; elif [ "$RC_A" = 4 ] && [ "$RC_B" = 0 ]; then LOSER=a; fi
[ -n "$LOSER" ] && ok "(RACE-CONCURRENT) one engage succeeds and the other exits 4" \
  || bad "(RACE-CONCURRENT) expected one engage to exit 0 and the other 4 (got a=$RC_A b=$RC_B)"
eq "$(cat "$ASSIGNEE")" "s-$WIN_SID" "(RACE-CONCURRENT) the visit is bound once, to the sitting that was spawned"
eq "$(grep -c 'bd update tk-vis --if-assignee' "$CALLS" || true)" "1" "(RACE-CONCURRENT) only the winner writes the visit; the refused engage never reaches the bind"
LOSER_OUT="$(cat "$TMP/race-${LOSER:-b}.out")"
has "$LOSER_OUT" "gc session attach s-$WIN_SID" "(RACE-CONCURRENT) the refused engage points the operator at the winner's sitting"
hasnt "$LOSER_OUT" "gc session close" "(RACE-CONCURRENT) …and never tells them to close it"
hasnt "$CALLED" "session close" "(RACE-CONCURRENT) no sitting is closed, because none was spawned that holds nothing"

echo "# a failed bind (not the race): the sitting spawned but nothing holds the visit"
# A non-13 bd-update failure (a transient store error, not the guarded-race
# rejection) leaves the visit open and unassigned, but the sitting has already
# spawned. It must be closed — a converse slot sets nudge=\"\"/idle_timeout=0
# and has no idle-claim rescue — and the operator told to re-run, not to
# hand-assign a visit to a closed sitting.
# codex again, so "never kicked" proves the abort precedes the kick block.
export BEAD_KIND=visit VIS_OWNER="" HAVE_VISIT=""
export BIND_FAIL=1
run_engage tk-vis --model codex --no-attach
eq "$RC" 4 "(BIND-FAIL) a failed bind exits 4"
has "$CALLED" "session new" "(BIND-FAIL) …the sitting did spawn"
has "$CALLED" "session close gc-77" "(BIND-FAIL) …the spawned sitting is closed, not left orphaned"
eq "$(cat "$ASSIGNEE")" "" "(BIND-FAIL) …the visit stays unassigned"
hasnt "$OUT" "Assign by hand" "(BIND-FAIL) …the operator is not told to hand-assign to a closed sitting"
hasnt "$CALLED" "session nudge" "(BIND-FAIL) …and the closed codex sitting is never kicked into a turn it cannot serve"
unset BIND_FAIL

echo "# a bind another writer stomps: read-back shows a different holder"
# The guarded bind succeeds, but another writer overwrites the assignee in the
# window before the read-back. This sitting holds nothing; close it and point
# the operator at the holder.
export BIND_STOMP="gc-toolkit__converse-8"
run_engage tk-vis --no-attach
eq "$RC" 4 "(STOMP) a stomped bind exits 4"
has "$CALLED" "session close gc-77" "(STOMP) …the stranded sitting is closed"
has "$OUT" "gc-toolkit__converse-8" "(STOMP) …and the operator is pointed at the holder that won"
unset BIND_STOMP

echo "# a bind that does not persist: read-back finds the visit still unassigned"
# The bind returns success but nothing sticks. The sitting spawned and holds
# nothing, so close it and tell the operator to re-run — the visit is unchanged.
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
has "$OUT" "bound the pre-existing" "(PARKED-FIRST) …and reports binding the pre-existing parked visit"
export BEAD_KIND=visit HAVE_VISIT=""

echo "# a bound pre-existing visit whose gate has since closed is flagged possibly-moot"
# escalate.sh files conditional visits that wait on a gate; once that gate closes
# the premise may no longer hold and the sitting can self-dismiss. engage does a
# read-only check of the bound visit's blocks-deps and warns when one is already
# closed, so the operator is not surprised when the thread self-dismisses.
export BEAD_KIND=task HAVE_VISIT=1 VIS_OWNER="" VIS_CLOSED_GATES="tk-gate9"
printf 'open' > "$VIS_STATUS"
run_engage tk-subj --no-attach
eq "$RC" 0 "(MOOT-GATE) engaging a subject whose visit has a closed gate still exits 0"
has "$CALLED" "session new converse-opus --alias tk-vis" "(MOOT-GATE) …the existing visit is still engaged — a closed gate is not an open blocker"
has "$OUT" "tk-gate9" "(MOOT-GATE) …and the output names the closed gate"
has "$OUT" "moot" "(MOOT-GATE) …warning the premise may be satisfied and the sitting may self-dismiss"
unset VIS_CLOSED_GATES HAVE_VISIT
export BEAD_KIND=visit
printf 'open' > "$VIS_STATUS"

echo "# a spawn failure carries gc's reason"
# gc says WHY only on stderr; a template a rig does not carry (the converse
# templates are rig-scoped) must reach the operator as that, not as an empty output.
export SPAWN_EMPTY=1
run_engage tk-vis --no-attach
eq "$RC" 4 "(SPAWN-WHY) a spawn that yields no identity exits 4"
has "$OUT" "gc said: gc session new: agent" "(SPAWN-WHY) …quoting gc's stderr"
has "$OUT" "rig-scoped" "(SPAWN-WHY) …and explaining the rig-scoped template"
hasnt "$CALLED" "--alias v-" "(SPAWN-WHY) …a non-alias spawn failure is not retried under a v- prefix"
unset SPAWN_EMPTY

echo "# a visit id ValidateAlias rejects is retried once under a v- prefix"
# gascity session ids match ^gc-[0-9]+$, and ValidateAlias refuses any alias
# that does — so a gascity visit whose bead id is all-numeric (gc-62297) cannot
# be the bare --alias, and nothing would spawn. engage tries the bare visit id
# first, then retries under a v- prefix no ValidateAlias rule can match, so the
# visit stays engageable. The stub refuses every --alias that is not v-prefixed.
export ALIAS_COLLIDE=1
printf 'open' > "$VIS_STATUS"
run_engage tk-vis --no-attach
eq "$RC" 0 "(ALIAS-RETRY) a rejected bare alias is retried and engage exits 0"
has "$CALLED" "session new converse-opus --alias tk-vis --no-attach --json" "(ALIAS-RETRY) …the bare visit id is tried first"
has "$CALLED" "session new converse-opus --alias v-tk-vis --no-attach --json" "(ALIAS-RETRY) …then retried under a v- prefix"
eq "$(cat "$ASSIGNEE")" "gc-toolkit__converse-1" "(ALIAS-RETRY) …and the visit binds to the retried sitting"
unset ALIAS_COLLIDE
printf 'open' > "$VIS_STATUS"

echo "# a bead whose prefix names no rig is refused before anything runs"
run_engage zz-vis --no-attach
eq "$RC" 4 "(NORIG) an unknown prefix exits 4"
has "$OUT" "matches no rig" "(NORIG) …saying so"
hasnt "$CALLED" "session new" "(NORIG) …and spawns nothing"

echo "# a subject whose rig carries no converse is refused with no side effect"
# An HQ / city-store root carries no converse in the resolved roster, so no
# converse sitting could spawn there. engage refuses BEFORE it files a visit or
# exports GC_RIG, rather than half-acting and failing at the spawn. Capability is
# read from the roster (gc agent list), not the checkout — $NO_CONVERSE makes the
# roster show gc-toolkit without converse (a proactive-only entry remains, to
# prove the guard is converse-specific).
export BEAD_KIND=visit VIS_OWNER="" HAVE_VISIT=""
export NO_CONVERSE=1
printf 'open' > "$VIS_STATUS"
run_engage tk-vis --no-attach
eq "$RC" 4 "(NOCONVERSE) a rig with no converse exits 4"
has "$OUT" "carries no converse template" "(NOCONVERSE) …saying why"
hasnt "$CALLED" "session new" "(NOCONVERSE) …spawning nothing"
hasnt "$CALLED" "bd create" "(NOCONVERSE) …filing no visit"
hasnt "$CALLED" "bd update" "(NOCONVERSE) …binding nothing"
unset NO_CONVERSE

echo "# an importer whose CHECKOUT holds no converse template is still engageable (roster-sourced)"
# The regression: capability must come from the import-resolved roster,
# not a glob of the rig's checkout. Only the pack-source rig keeps agents/converse-*
# in its tree; every importer obtains converse through the roster. $TMP/rig-bare is
# a checkout with no converse templates, yet the default roster registers converse
# for gc-toolkit — so engage clears the converse guard and spawns, where the old
# glob predicate would have refused.
export BEAD_KIND=visit VIS_OWNER="" HAVE_VISIT=""
export RIG_PATH="$TMP/rig-bare"
printf 'open' > "$VIS_STATUS"
run_engage tk-vis --no-attach
eq "$RC" 0 "(IMPORTER) an importer with converse in the roster but not the checkout engages"
has "$CALLED" "session new converse-opus --alias tk-vis" "(IMPORTER) …spawning the converse sitting"
export RIG_PATH="$TMP/rig"

echo "# attach behaviour: default attaches, --no-attach does not"
run_engage tk-vis --no-attach
hasnt "$CALLED" "session attach" "(ATTACH) --no-attach does not attach"
run_engage tk-vis
has "$CALLED" "session attach gc-77" "(ATTACH) the default attaches to the captured session id"
hasnt "$CALLED" "session nudge" "(ATTACH) …and an opus sitting is not kicked; it self-starts before the operator lands"

echo "# for codex (the kicked provider), the kick precedes the attach"
# attach is a foreground handoff to the pane: nothing after it in cmd_engage runs
# until the operator detaches, so a codex kick sent after the attach would never
# fire and the operator would land on a blank pane.
run_engage tk-vis --model codex
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
export BEAD_KIND=visit VIS_OWNER="" HAVE_VISIT=""
printf 'open' > "$VIS_STATUS"
run_engage tk-vis
eq "$(cat "$POLLS")" 1 "(START-ACTIVE) a sitting already started is read once"
hasnt "$OUT" "waiting up to" "(START-ACTIVE) …and attached with no wait announced"

START_STATES="start-pending creating active" run_engage tk-vis
eq "$RC" 0 "(START-WAIT) an engage whose sitting starts on the third listing exits 0"
eq "$(cat "$POLLS")" 3 "(START-WAIT) …reading the sitting until it reads active"
last_poll=$(printf '%s\n' "$CALLED" | grep -n '^session list' | tail -1 | cut -d: -f1 || true)
attach_line=$(printf '%s\n' "$CALLED" | grep -n '^session attach' | head -1 | cut -d: -f1 || true)
if [ -n "$last_poll" ] && [ -n "$attach_line" ] && [ "$last_poll" -lt "$attach_line" ]; then
  ok "(START-WAIT) …and attaching only after the listing that reads it active"
else
  bad "(START-WAIT) expected the last listing (line ${last_poll:-none}) before the attach (line ${attach_line:-none})"
fi
has "$OUT" "waiting up to 120s for the reconciler to start gc-toolkit__converse-1" \
    "(START-WAIT) …telling the operator what it waits on, and for how long"

GC_HELM_ENGAGE_WAIT_TIMEOUT=2 START_STATES="start-pending" run_engage tk-vis
eq "$RC" 0 "(START-TIMEOUT) a sitting still unstarted at the bound exits 0: the visit is bound and the sitting may yet start"
hasnt "$CALLED" "session attach" "(START-TIMEOUT) …and is NOT attached, since the attach would launch it without its prompt"
polls=$(cat "$POLLS")
if [ "${polls:-0}" -ge 2 ]; then
  ok "(START-TIMEOUT) …after reading it more than once"
else
  bad "(START-TIMEOUT) expected at least 2 listings before giving up (got ${polls:-0})"
fi
has "$OUT" "the reconciler has not started gc-toolkit__converse-1 after 2s" "(START-TIMEOUT) …saying the reconciler has not started it"
has "$OUT" "start-pending" "(START-TIMEOUT) …naming the state it last read"
has "$OUT" "gc session attach gc-77" "(START-TIMEOUT) …and giving the attach to run once it is up"

GC_HELM_ENGAGE_WAIT_TIMEOUT=60 START_STATES="start-pending gone" run_engage tk-vis
eq "$RC" 4 "(START-CLOSED) a sitting listed and then gone from the list (closed, read from the store) exits 4"
hasnt "$CALLED" "session attach" "(START-CLOSED) …without attaching"
eq "$(cat "$POLLS")" 2 "(START-CLOSED) …at the first listing it is gone from, not at the bound"
has "$OUT" "ended before the reconciler started it (its state in 'gc session list': gone)" "(START-CLOSED) …saying the sitting ended"
has "$OUT" "gc bd update tk-vis --assignee" "(START-CLOSED) …and how to put its still-bound visit back on the board"

GC_HELM_ENGAGE_WAIT_TIMEOUT=60 START_STATES="blank" run_engage tk-vis
eq "$RC" 4 "(START-BLANK) a sitting listed with an empty state (closed, read from the supervisor) exits 4"
hasnt "$CALLED" "session attach" "(START-BLANK) …without attaching"
eq "$(cat "$POLLS")" 1 "(START-BLANK) …at the first listing"
has "$OUT" "state in 'gc session list': closed" "(START-BLANK) …naming it closed"

GC_HELM_ENGAGE_WAIT_TIMEOUT=60 START_STATES="failed-create" run_engage tk-vis
eq "$RC" 4 "(START-FAILED) a sitting whose create failed exits 4"
hasnt "$CALLED" "session attach" "(START-FAILED) …without attaching"
has "$OUT" "state in 'gc session list': failed-create" "(START-FAILED) …naming the state"

# A sitting not listed yet may only lag the supervisor's read cache, and a
# listing that fails says nothing about the sitting, so neither ends the wait.
GC_HELM_ENGAGE_WAIT_TIMEOUT=60 START_STATES="gone gone active" run_engage tk-vis
eq "$RC" 0 "(START-UNLISTED) a sitting not yet listed is waited on, not read as closed"
has "$CALLED" "session attach gc-77" "(START-UNLISTED) …and attached once it reads active"
GC_HELM_ENGAGE_WAIT_TIMEOUT=60 START_STATES="broken active" run_engage tk-vis
eq "$RC" 0 "(START-UNREADABLE) a listing that fails is waited through"
has "$CALLED" "session attach gc-77" "(START-UNREADABLE) …and the sitting attached once a listing reads it active"

echo "# --no-attach has no attach to gate, so it does not wait"
GC_HELM_ENGAGE_WAIT_TIMEOUT=60 START_STATES="start-pending" run_engage tk-vis --no-attach
eq "$RC" 0 "(NOATTACH-NOWAIT) --no-attach on an unstarted sitting exits 0"
polls=$(cat "$POLLS")
eq "${polls:-0}" 0 "(NOATTACH-NOWAIT) …without reading the sitting's state"
hasnt "$OUT" "waiting up to" "(NOATTACH-NOWAIT) …or announcing a wait"
GC_HELM_ENGAGE_WAIT_TIMEOUT=60 START_STATES="start-pending" run_engage tk-vis --model codex --no-attach
has "$CALLED" "session nudge gc-77" "(NOATTACH-KICK) a codex sitting on --no-attach is kicked without a start wait"

echo "# for codex, the kick follows the start wait"
START_STATES="start-pending active" run_engage tk-vis --model codex
last_poll=$(printf '%s\n' "$CALLED" | grep -n '^session list' | tail -1 | cut -d: -f1 || true)
nudge_line=$(printf '%s\n' "$CALLED" | grep -n '^session nudge' | head -1 | cut -d: -f1 || true)
attach_line=$(printf '%s\n' "$CALLED" | grep -n '^session attach' | head -1 | cut -d: -f1 || true)
if [ -n "$last_poll" ] && [ -n "$nudge_line" ] && [ -n "$attach_line" ] \
   && [ "$last_poll" -lt "$nudge_line" ] && [ "$nudge_line" -lt "$attach_line" ]; then
  ok "(KICK-AFTER-START) the codex kick reaches a started sitting and precedes the attach"
else
  bad "(KICK-AFTER-START) expected listing (${last_poll:-none}) < nudge (${nudge_line:-none}) < attach (${attach_line:-none})"
fi
GC_HELM_ENGAGE_WAIT_TIMEOUT=1 START_STATES="start-pending" run_engage tk-vis --model codex
has "$CALLED" "session nudge gc-77" "(TIMEOUT-KICK) a codex sitting unstarted at the bound is still kicked, so it begins once it starts"
hasnt "$CALLED" "session attach" "(TIMEOUT-KICK) …but not attached"
GC_HELM_ENGAGE_WAIT_TIMEOUT=60 START_STATES="start-pending gone" run_engage tk-vis --model codex
hasnt "$CALLED" "session nudge" "(CLOSED-NOKICK) a codex sitting that ended before it started is not kicked"

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

echo "# a city whose controller is down is refused before anything spawns"
# The reconciler, the controller's loop, is what launches the sitting; the HQ
# row's running is gc's probe of that controller.
export HQ_RUNNING=false
run_engage tk-vis --no-attach
eq "$RC" 4 "(CTRL-DOWN) engaging while the city controller is down exits 4"
hasnt "$CALLED" "session new" "(CTRL-DOWN) …and spawns nothing"
has "$OUT" "city controller is down" "(CTRL-DOWN) …saying the controller is down"
has "$OUT" "gc status" "(CTRL-DOWN) …and pointing at the city's status"
hasnt "$OUT" "gc rig status" "(CTRL-DOWN) …not at the subject rig's"
unset HQ_RUNNING

echo "# an idle subject rig (running=false) engages while the controller is up"
# A rig row's running=false is what gc reports for an idle rig, and an idle rig
# is not a down one: the reconciler launches the sitting there like anywhere else.
export HQ_RUNNING=true RIG_SUSPENDED=false RIG_RUNNING=false
run_engage tk-vis --no-attach
eq "$RC" 0 "(IDLE) engaging on an idle rig exits 0"
has "$CALLED" "session new converse-opus --alias tk-vis" "(IDLE) …and spawns the sitting"
unset HQ_RUNNING RIG_SUSPENDED RIG_RUNNING

echo "# a suspended rig is refused even while the controller is up"
export HQ_RUNNING=true RIG_SUSPENDED=true
run_engage tk-vis --no-attach
eq "$RC" 4 "(SUSPENDED-CTRL-UP) a suspended rig still exits 4 with the controller up"
has "$OUT" "is suspended" "(SUSPENDED-CTRL-UP) …on the suspension"
unset HQ_RUNNING RIG_SUSPENDED

echo "# an explicitly live city (controller running, rig not suspended) spawns as normal"
# The guard refuses only on suspended=true or an HQ running=false, so a city gc
# reports as live must engage exactly as one that reports neither flag.
export HQ_RUNNING=true RIG_SUSPENDED=false RIG_RUNNING=true
run_engage tk-vis --no-attach
eq "$RC" 0 "(LIVE) engaging on an explicitly live city exits 0"
has "$CALLED" "session new converse-opus --alias tk-vis" "(LIVE) …and spawns the sitting"
unset HQ_RUNNING RIG_SUSPENDED RIG_RUNNING

echo "# an open visit bound to a GONE sitting is reclaimed, then re-engaged"
# A sitting bound while its rig was suspended or the controller was down never
# registers, leaving the visit open+assigned to a session absent from
# `gc session list`. engage must not point the operator at that dead session: it
# reclaims the visit (clears the binding, re-parks on the board) and spawns a
# fresh sitting.
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

# ── Interactive TTY flow + starter/model/debug ───────────────────────
echo
echo "# the model set is the configured converse-* variants; bare 'converse' is excluded"
# --model validates against the globbed variants (opus/fable/codex from the
# fixture agents dir); the bare 'converse' pool template is not an engage variant.
export BEAD_KIND=visit VIS_OWNER="" HAVE_VISIT=""
printf 'open' > "$VIS_STATUS"
run_engage tk-vis --model converse --no-attach
eq "$RC" 2 "(IA-MODEL-SET) --model converse (the bare pool template) is not a variant, exit 2"
hasnt "$CALLED" "session new" "(IA-MODEL-SET) …and nothing spawned"
has "$OUT" "must be one of: opus" "(IA-MODEL-SET) …the message lists the configured variants"

echo "# every success carries a ✓ summary on stdout and an always-on [debug] line"
run_engage tk-vis --no-attach
eq "$RC" 0 "(IA-DEBUG) engaging exits 0"
has "$OUT" "[debug] visit=tk-vis" "(IA-DEBUG) the provenance rides an always-on [debug] line"
has "$OUT" "sitting=gc-77" "(IA-DEBUG) …carrying the sitting id"
has "$OUT" "work_dir=/w" "(IA-DEBUG) …and the sitting work_dir"
has "$OUT" "✓ converse-opus" "(IA-DEBUG) …and the human summary names the sitting template"

echo "# --no-input keeps the non-interactive one-shot behavior (engages the existing visit)"
export BEAD_KIND=task HAVE_VISIT=1 VIS_OWNER=""
printf 'open' > "$VIS_STATUS"
run_engage tk-subj --no-input --no-attach
eq "$RC" 0 "(IA-NOINPUT) --no-input on a subject-with-visit exits 0"
hasnt "$CALLED" "bd create" "(IA-NOINPUT) …engaging the existing visit, filing nothing"
has "$CALLED" "session new converse-opus --alias tk-vis" "(IA-NOINPUT) …with no prompts"
unset HAVE_VISIT

echo "# on a TTY a subject with a parked visit is offered engage-existing vs new"
export BEAD_KIND=task HAVE_VISIT=1 VIS_OWNER=""
printf 'open' > "$VIS_STATUS"
# [1] engage the existing visit · Enter at the model prompt (Opus)
run_engage_tty '1\n\n' tk-subj --no-attach
eq "$RC" 0 "(IA-VISIT-EXISTING) picking the existing visit exits 0"
has "$OUT" "Subject has open visit" "(IA-VISIT-EXISTING) …after listing the open visit(s)"
has "$OUT" "[d] discuss broadly" "(IA-VISIT-EXISTING) …in one prompt that also offers the new-visit seed letters"
hasnt "$CALLED" "bd create" "(IA-VISIT-EXISTING) …files nothing"
has "$CALLED" "session new converse-opus --alias tk-vis" "(IA-VISIT-EXISTING) …and engages it"
# An existing visit's brief was written when it was filed, so there is no new
# body for a skill to seed: the skill prompt is not asked.
hasnt "$OUT" "Skill — Enter" "(IA-SKILL-EXISTING) …and asks no skill, since its brief is already written"
unset HAVE_VISIT

echo "# a subject engage grounds the operator with a one-line summary before the visit prompt"
export BEAD_KIND=task HAVE_VISIT=1 VIS_OWNER=""
printf 'open' > "$VIS_STATUS"
run_engage_tty '1\n\n' tk-subj --no-attach
eq "$RC" 0 "(IA-SUMMARY) engaging a subject exits 0"
has "$OUT" "the subject under engagement" "(IA-SUMMARY) the summary carries the picked bead's title"
has "$OUT" "task · open · p2" "(IA-SUMMARY) …with its type, status, and priority"
# The summary precedes the visit prompt, so the operator reads what they picked
# while deciding which visit to open or select.
case "$OUT" in
  *"the subject under engagement"*"Subject has open visit"*) ok "(IA-SUMMARY) …ahead of the visit prompt" ;;
  *) bad "(IA-SUMMARY) the summary should precede the visit prompt" ;;
esac
unset HAVE_VISIT

echo "# an over-long title is truncated so the summary stays one short line"
export BEAD_KIND=task HAVE_VISIT=1 VIS_OWNER="" \
  SUBJ_TITLE="AAAA BBBB CCCC DDDD EEEE FFFF GGGG HHHH IIII JJJJ KKKK LLLL MMMM NNNN OOOO PPPP QQQQ RRRR SSSS TTTT ZEND"
printf 'open' > "$VIS_STATUS"
run_engage_tty '1\n\n' tk-subj --no-attach
eq "$RC" 0 "(IA-SUMMARY-TRUNC) engaging a long-titled subject exits 0"
has "$OUT" "AAAA" "(IA-SUMMARY-TRUNC) the title head is kept"
has "$OUT" "…" "(IA-SUMMARY-TRUNC) …with an ellipsis where it was cut"
hasnt "$OUT" "ZEND" "(IA-SUMMARY-TRUNC) …and the tail past the cut is dropped"
unset HAVE_VISIT SUBJ_TITLE

echo "# --no-input suppresses the grounding summary — its stdout is a script's to parse"
export BEAD_KIND=task HAVE_VISIT=1 VIS_OWNER=""
printf 'open' > "$VIS_STATUS"
run_engage tk-subj --no-input --no-attach
eq "$RC" 0 "(IA-SUMMARY-NOINPUT) --no-input on a subject exits 0"
hasnt "$OUT" "the subject under engagement" "(IA-SUMMARY-NOINPUT) …and no grounding summary is printed"
unset HAVE_VISIT

echo "# two parked visits become a numbered choice, replacing the error-on-two refusal"
export BEAD_KIND=task HAVE_VISIT=2 VIS_OWNER=""
printf 'open' > "$VIS_STATUS"
# parked-first, oldest first: [1]=tk-vis (09-01) · [2]=tk-vis2 (09-02); pick [1]
run_engage_tty '1\n\n' tk-subj --no-attach
eq "$RC" 0 "(IA-VISIT-MULTI) two parked visits, picking one, exits 0 (no error-on-two)"
hasnt "$OUT" "parked visits" "(IA-VISIT-MULTI) …the multi-visit refusal is replaced by the prompt"
has "$OUT" "tk-vis2" "(IA-VISIT-MULTI) …both parked visits are listed"
has "$CALLED" "session new converse-opus --alias tk-vis " "(IA-VISIT-MULTI) …spawning for the picked visit"
unset HAVE_VISIT

echo "# a seed letter at the one prompt files a NEW visit carrying that seed, even with a visit present"
export BEAD_KIND=task HAVE_VISIT=1 VIS_OWNER=""
printf 'open' > "$VIS_STATUS"
# [d] new visit seeded discuss-broadly (one prompt, no separate starter) · Enter
# model (Opus) · Enter skill (none)
run_engage_tty 'd\n\n\n' tk-subj --no-attach
eq "$RC" 0 "(IA-NEW-TEMPLATE) new visit + template exits 0"
has "$CALLED" "bd create" "(IA-NEW-TEMPLATE) …a new visit is filed"
hasnt "$OUT" "already open" "(IA-NEW-TEMPLATE) …deliberately, past the one-visit dedup"
has "$CALLED" "talk through tk-subj broadly" "(IA-NEW-TEMPLATE) …its body is the seed, subject filled in"
has "$CALLED" "visit: tk-subj — discuss broadly" "(IA-NEW-TEMPLATE) …titled by the seed label"
has "$CALLED" "session new converse-opus" "(IA-NEW-TEMPLATE) …then a sitting is spawned"
has "$OUT" "Skill — Enter = none" "(IA-SKILL-NONE) a new visit is asked for a skill"
hasnt "$CALLED" "Load that skill" "(IA-SKILL-NONE) …and Enter seeds none, leaving the seed as the whole brief"
unset HAVE_VISIT

echo "# free text at the one prompt opens a NEW visit carrying it verbatim as the opener"
export BEAD_KIND=task HAVE_VISIT=1 VIS_OWNER=""
printf 'open' > "$VIS_STATUS"
# free text (not a number or seed letter) · Enter model · Enter skill (none)
run_engage_tty 'lets revisit the scope\n\n\n' tk-subj --no-attach
eq "$RC" 0 "(IA-NEW-FREETEXT) new visit + free text exits 0"
has "$CALLED" "bd create" "(IA-NEW-FREETEXT) …a new visit is filed"
has "$CALLED" "lets revisit the scope" "(IA-NEW-FREETEXT) …with the typed message as its body"
unset HAVE_VISIT

echo "# the model prompt is a numbered choice; picking codex spawns converse-codex + kick"
export BEAD_KIND=visit VIS_OWNER="" HAVE_VISIT=""
printf 'open' > "$VIS_STATUS"
# model list = opus, codex, fable (opus first, then glob order); [2] = codex
run_engage_tty '2\n' tk-vis --no-attach
eq "$RC" 0 "(IA-MODEL-PICK) picking a model exits 0"
has "$CALLED" "session new converse-codex --alias tk-vis" "(IA-MODEL-PICK) …spawning the picked variant"
has "$CALLED" "session nudge gc-77" "(IA-MODEL-PICK) …and codex, the kicked provider, gets its opening turn"

echo "# Enter at the model prompt keeps Opus (the work-tier default)"
run_engage_tty '\n' tk-vis --no-attach
eq "$RC" 0 "(IA-MODEL-DEFAULT) Enter at the model prompt exits 0"
has "$CALLED" "session new converse-opus" "(IA-MODEL-DEFAULT) …keeping Opus"

echo "# a visit id is grounded by its SUBJECT and reason, not the visit's own row"
export BEAD_KIND=visit VIS_OWNER="" HAVE_VISIT=""
printf 'open' > "$VIS_STATUS"
# the join-or-new prompt is skipped for a visit id; the only read is the model
# choice (Enter = Opus), so this exercises the visit-id grounding straight through.
run_engage_tty '\n' tk-vis --no-attach
eq "$RC" 0 "(IA-VISITID-SUBJECT) engaging a visit id exits 0"
has "$OUT" "Subject: tk-subj" "(IA-VISITID-SUBJECT) grounding names the subject the visit tracks"
has "$OUT" "the subject under engagement" "(IA-VISITID-SUBJECT) …with the subject's OWN title, resolved from the visit"
has "$OUT" "compare notes on the WIP proposals" "(IA-VISITID-SUBJECT) …and the visit reason (the title tail after the em dash)"
# the subject/join-or-new prompt belongs to a subject id; a visit id skips it
hasnt "$OUT" "starts a new visit" "(IA-VISITID-SUBJECT) …and the join-or-new prompt is skipped"
hasnt "$OUT" "Subject has open visit" "(IA-VISITID-SUBJECT) …no visit list is offered"
has "$CALLED" "session new converse-opus --alias tk-vis" "(IA-VISITID-SUBJECT) …then it engages the named visit"
has "$OUT" "for tk-subj" "(IA-VISITID-SUBJECT) …and the success line reads 'for <subject>', not the visit id repeated"

echo "# a visit id with an EMPTY continuation-group stamp still grounds via its tracks edge"
export BEAD_KIND=visit VIS_OWNER="" HAVE_VISIT="" VIS_CGROUP="" VIS_TRACKS="tk-subj"
printf 'open' > "$VIS_STATUS"
# The stamp landed empty, so the subject is only reachable through the tracks
# edge, which `gc bd show` renders keyed .dependency_type/.id. Reading the
# .type/.depends_on_id shape `gc bd list` uses would drop it and print
# "this visit names no subject" — this case guards that exact regression.
run_engage_tty '\n' tk-vis --no-attach
eq "$RC" 0 "(IA-VISITID-TRACKS) engaging an empty-stamp visit id exits 0"
has "$OUT" "Subject: tk-subj" "(IA-VISITID-TRACKS) the subject resolves from the tracks edge when the continuation-group stamp is empty"
hasnt "$OUT" "names no subject" "(IA-VISITID-TRACKS) …so the subject-less degrade line is not printed"
has "$CALLED" "session new converse-opus --alias tk-vis" "(IA-VISITID-TRACKS) …then it engages the named visit"
has "$OUT" "for tk-subj" "(IA-VISITID-TRACKS) …and the success line names the subject, not the visit id"
unset VIS_CGROUP VIS_TRACKS

echo "# a subject given by title search resolves and engages"
export BEAD_KIND=task HAVE_VISIT="" VIS_OWNER="" SEARCH_HIT=1
printf 'open' > "$VIS_STATUS"
# search text · [1] pick the match · starter Enter (none) · model Enter (Opus) ·
# skill Enter (none)
run_engage_tty 'findme\n1\n\n\n\n' --no-attach
eq "$RC" 0 "(IA-SUBJECT-SEARCH) a title-searched subject resolves and engages, exit 0"
has "$CALLED" "session new converse-opus" "(IA-SUBJECT-SEARCH) …spawning for the resolved subject's visit"
unset SEARCH_HIT

echo "# --template pre-fills the starter and skips its prompt (here under --no-input)"
export BEAD_KIND=task HAVE_VISIT=1 VIS_OWNER=""
printf 'open' > "$VIS_STATUS"
run_engage tk-subj --template unstick-a-stall --no-input --no-attach
eq "$RC" 0 "(IA-TEMPLATE-FLAG) --template files a new visit with the seed, exit 0"
has "$CALLED" "bd create" "(IA-TEMPLATE-FLAG) …a new visit is filed"
has "$CALLED" "looks stalled" "(IA-TEMPLATE-FLAG) …carrying the seed body"
hasnt "$OUT" "already open" "(IA-TEMPLATE-FLAG) …past the dedup"
unset HAVE_VISIT

echo "# an unknown --template is refused before anything spawns"
export BEAD_KIND=task VIS_OWNER=""
run_engage tk-subj --template bogus --no-input --no-attach
eq "$RC" 2 "(IA-TEMPLATE-BAD) an unknown --template exits 2"
has "$OUT" "unknown --template" "(IA-TEMPLATE-BAD) …naming the fault"
hasnt "$CALLED" "session new" "(IA-TEMPLATE-BAD) …and nothing spawned"

echo "# --reason and --template both set the opener — they conflict"
run_engage tk-subj --reason x --template discuss-broadly --no-input --no-attach
eq "$RC" 2 "(IA-REASON-TEMPLATE) --reason and --template together exit 2"
has "$OUT" "both set the opening message" "(IA-REASON-TEMPLATE) …saying why"
hasnt "$CALLED" "bd create" "(IA-REASON-TEMPLATE) …and nothing filed"

echo "# --new-subject: file a fresh marked subject in a chosen rig, then engage it"
# One-shot: --rig names the rig, the positional is the subject title. The subject
# is created MARKED (gc.reaction_owned=1 + gc.origin=operator) in that rig's
# .beads store, then the ONE visit is filed and a sitting spawned. The marker is
# what keeps the async first-reaction/proactive worker from filing a second visit.
export BEAD_KIND=task VIS_OWNER="" HAVE_VISIT=""
printf 'open' > "$VIS_STATUS"
run_engage "ship the new intake flow" --new-subject --rig gc-toolkit --no-input --no-attach
eq "$RC" 0 "(NEWSUBJ) --new-subject --rig --no-input exits 0"
SUBJ_CREATE="$(printf '%s\n' "$CALLED" | grep '^bd create' | grep -- '--metadata' | head -n1)"
has "$SUBJ_CREATE" "reaction_owned" "(NEWSUBJ) the subject is created with the gc.reaction_owned marker"
has "$SUBJ_CREATE" "gc.origin" "(NEWSUBJ) …and gc.origin=operator (honest origin; the force-to-visit invariant is preserved)"
has "$SUBJ_CREATE" "--db $TMP/rig/.beads" "(NEWSUBJ) …in the chosen rig's store (cross-rig create)"
has "$SUBJ_CREATE" "ship the new intake flow" "(NEWSUBJ) …titled with the subject text"
has "$OUT" "filed subject tk-newsubj in rig 'gc-toolkit'" "(NEWSUBJ) reports the filed subject"
has "$CALLED" "session new converse-opus --alias tk-vis --no-attach" "(NEWSUBJ) then engages the one visit it filed"
# The title doubles as the opener when no --reason/--template is given: the visit
# cmd_open files carries it (visit title tail is the opener).
VISIT_CREATE="$(printf '%s\n' "$CALLED" | grep '^bd create' | grep -v -- '--metadata' | head -n1)"
has "$VISIT_CREATE" "ship the new intake flow" "(NEWSUBJ-OPENER) the title doubles as the visit's opener"
# The marker outlives a SUCCESSFUL engage (it is what stands the async worker
# down); the abort backstop must be disarmed once the visit is filed, so a clean
# engage never revokes it. (The disarm's control; its arm is NEWSUBJ-ABORT below.)
hasnt "$CALLED" "unset-metadata gc.reaction_owned" "(NEWSUBJ) a successful engage keeps the marker — the backstop is disarmed once the visit is filed"

echo "# --new-subject one-shot without --rig is refused (no id prefix to derive a rig)"
export BEAD_KIND=task
run_engage "some topic" --new-subject --no-input --no-attach
eq "$RC" 2 "(NEWSUBJ-NORIG) --new-subject --no-input without --rig exits 2"
has "$OUT" "needs a rig" "(NEWSUBJ-NORIG) …naming the fault"
hasnt "$CALLED" "--metadata" "(NEWSUBJ-NORIG) …and no subject was created"

echo "# --new-subject and --subject are mutually exclusive"
run_engage --new-subject --subject tk-subj --rig gc-toolkit --no-input --no-attach
eq "$RC" 2 "(NEWSUBJ-CONFLICT) --new-subject with --subject exits 2"
has "$OUT" "pass only one" "(NEWSUBJ-CONFLICT) …saying why"
hasnt "$CALLED" "--metadata" "(NEWSUBJ-CONFLICT) …and nothing created"

echo "# --rig without --new-subject is refused (an existing subject's rig comes from its id)"
export BEAD_KIND=task
run_engage tk-subj --rig gc-toolkit --no-input --no-attach
eq "$RC" 2 "(NEWSUBJ-RIG-ALONE) --rig without --new-subject exits 2"
has "$OUT" "applies only with --new-subject" "(NEWSUBJ-RIG-ALONE) …naming the fault"

echo "# --new-subject with an unknown rig is refused before any create"
run_engage "x" --new-subject --rig nope --no-input --no-attach
eq "$RC" 4 "(NEWSUBJ-BADRIG) an unknown --rig exits 4"
has "$OUT" "matches no rig" "(NEWSUBJ-BADRIG) …naming the unknown rig"
hasnt "$CALLED" "--metadata" "(NEWSUBJ-BADRIG) …and nothing created"

echo "# --new-subject one-shot with no subject text is refused"
run_engage --new-subject --rig gc-toolkit --no-input --no-attach
eq "$RC" 2 "(NEWSUBJ-NOTITLE) a missing subject text exits 2"
has "$OUT" "needs a subject" "(NEWSUBJ-NOTITLE) …naming the fault"
hasnt "$CALLED" "--metadata" "(NEWSUBJ-NOTITLE) …and nothing created"

echo "# --new-subject whose subject create fails aborts without spawning"
export SUBJ_CREATE_FAIL=1
run_engage "doomed subject" --new-subject --rig gc-toolkit --no-input --no-attach
eq "$RC" 4 "(NEWSUBJ-CREATEFAIL) a failed subject create exits 4"
has "$OUT" "could not create the subject" "(NEWSUBJ-CREATEFAIL) …naming the fault"
hasnt "$CALLED" "session new" "(NEWSUBJ-CREATEFAIL) …and no sitting spawned"
hasnt "$CALLED" "unset-metadata gc.reaction_owned" "(NEWSUBJ-CREATEFAIL) …and no cleanup runs — nothing was created to clean up"
unset SUBJ_CREATE_FAIL

echo "# --new-subject whose post-create gate aborts still files the subject's one visit"
# The subject is created MARKED before the gates that can still refuse the live
# engage (here an unknown --model, like the suspended, controller-down and unknown
# --template gates). An abort there must not leave the operator-origin subject with
# no visit: the async worker will not supply one (gc-proactive drops a marked bead,
# mol-first-reaction consumes-and-ignores it, and even unmarked a first reaction
# does not force a visit for gc.origin=operator). So the backstop files the one
# parked visit itself (via cmd_open, carrying the opener) and LEAVES the marker,
# exactly as a successful engage does, so the async worker still stands down.
export BEAD_KIND=task VIS_OWNER="" HAVE_VISIT=""
printf 'open' > "$VIS_STATUS"
run_engage "topic after a bad model" --new-subject --rig gc-toolkit --model bogus --no-input --no-attach
eq "$RC" 2 "(NEWSUBJ-ABORT) a post-create --model abort exits 2"
SUBJ_CREATE="$(printf '%s\n' "$CALLED" | grep '^bd create' | grep -- '--metadata' | head -n1)"
has "$SUBJ_CREATE" "reaction_owned" "(NEWSUBJ-ABORT) the subject was already created with the marker (the abort is post-create)"
VISIT_CREATE="$(printf '%s\n' "$CALLED" | grep '^bd create' | grep -v -- '--metadata' | head -n1)"
has "$VISIT_CREATE" "topic after a bad model" "(NEWSUBJ-ABORT) …so the backstop files the subject's one parked visit, carrying its opener"
hasnt "$CALLED" "unset-metadata gc.reaction_owned" "(NEWSUBJ-ABORT) …and LEAVES the marker, exactly as a successful engage does"
has "$OUT" "parked on the helm board" "(NEWSUBJ-ABORT) …and tells the operator the visit is parked for them to engage"
hasnt "$CALLED" "session new" "(NEWSUBJ-ABORT) …and nothing was spawned"

echo "# --new-subject interactive: a lone converse rig auto-selects; prompts title, then model"
# One converse-capable rig in the stub, so the rig step auto-selects (reads no
# input); the answers then feed the title prompt, the model prompt (Enter=Opus),
# and the skill prompt a new visit gets (Enter=none).
export BEAD_KIND=task VIS_OWNER="" HAVE_VISIT=""
printf 'open' > "$VIS_STATUS"
run_engage_tty 'draft the Q3 plan\n\n\n' --new-subject --no-attach
eq "$RC" 0 "(NEWSUBJ-IA) interactive --new-subject exits 0"
has "$OUT" "the only converse-capable rig" "(NEWSUBJ-IA) the lone converse rig auto-selects"
SUBJ_CREATE="$(printf '%s\n' "$CALLED" | grep '^bd create' | grep -- '--metadata' | head -n1)"
has "$SUBJ_CREATE" "draft the Q3 plan" "(NEWSUBJ-IA) the typed title becomes the subject"
has "$SUBJ_CREATE" "reaction_owned" "(NEWSUBJ-IA) …created with the marker"
has "$CALLED" "session new converse-opus" "(NEWSUBJ-IA) …then a sitting spawns (Opus, the Enter default)"

# ── --skill: a sitting seeded with a skill as its lens ────────────────
echo
echo "# --skill files a NEW visit whose body is the lens brief, even with one parked"
# The lens brief is the new visit's body, the claim-time brief every sitting
# reads, so the skill reaches the sitting on any model with no per-skill
# template. The name is checked against the roster of the sitting that will
# spawn: its rig, and its model's converse agent.
export BEAD_KIND=task HAVE_VISIT=1 VIS_OWNER=""
printf 'open' > "$VIS_STATUS"
run_engage tk-subj --skill review-arch --no-input --no-attach
eq "$RC" 0 "(SKILL) --skill on a subject exits 0"
has "$CALLED" "skill list --agent gc-toolkit/gc-toolkit.converse-opus" "(SKILL) the name is checked against the sitting's own roster (its rig and model)"
has "$CALLED" "bd create" "(SKILL) …a NEW visit is filed, past the parked one"
hasnt "$OUT" "already open" "(SKILL) …deliberately, past the one-visit dedup"
has "$CALLED" "visit: tk-subj — review-arch lens" "(SKILL) …titled by the skill, so the board row says whose view it brings"
has "$CALLED" "look at tk-subj through the gc-toolkit.review-arch" "(SKILL) …its body is the lens brief, the bare name resolved to the full one"
has "$CALLED" "Load that skill" "(SKILL) …which has the sitting load the skill"
has "$CALLED" "then WAIT for the operator" "(SKILL) …and, with no opener, frame through the lens and wait"
has "$CALLED" "session new converse-opus --alias tk-vis" "(SKILL) …then a sitting spawns for the new visit"
hasnt "$CALLED" "session nudge" "(SKILL) …and the opus sitting reads the lens from the body, unkicked"
has "$OUT" "✓ converse-opus with review-arch on new visit" "(SKILL) the summary names the skill the sitting was seeded with"

echo "# a full skill name resolves to exactly that skill"
run_engage tk-subj --skill gc-toolkit.review-pm --no-input --no-attach
eq "$RC" 0 "(SKILL-FULL) a full --skill name exits 0"
has "$CALLED" "through the gc-toolkit.review-pm" "(SKILL-FULL) …and seeds exactly that skill"

echo "# with an opener, the lens brief leads and the opener follows it"
run_engage tk-subj --skill review-arch --template discuss-broadly --no-input --no-attach
eq "$RC" 0 "(SKILL-TEMPLATE) --skill with --template exits 0"
case "$CALLED" in
  *"-d The operator engaged this sitting"*"says what to do first."*"talk through tk-subj broadly"*)
    ok "(SKILL-TEMPLATE) the body is the lens brief, then the seed as the opener that says what to do first" ;;
  *) bad "(SKILL-TEMPLATE) the body should be the lens brief followed by the seed (got: $CALLED)" ;;
esac
has "$CALLED" "visit: tk-subj — review-arch lens: discuss broadly" "(SKILL-TEMPLATE) …and the title carries the skill, then the seed label"
run_engage tk-subj --skill review-arch --reason "is the split justified" --no-input --no-attach
eq "$RC" 0 "(SKILL-REASON) --skill with --reason exits 0"
case "$CALLED" in
  *"-d The operator engaged this sitting"*"says what to do first."*"is the split justified"*)
    ok "(SKILL-REASON) the reason follows the brief as the opener" ;;
  *) bad "(SKILL-REASON) the body should be the lens brief followed by the reason (got: $CALLED)" ;;
esac
has "$CALLED" "visit: tk-subj — review-arch lens: is the split justified" "(SKILL-REASON) …and rides the title after the skill"

echo "# a codex sitting is checked against codex's roster, and the brief rides its kick"
run_engage tk-subj --skill review-arch --model codex --no-input --no-attach
eq "$RC" 0 "(SKILL-CODEX) --skill with --model codex exits 0"
has "$CALLED" "skill list --agent gc-toolkit/gc-toolkit.converse-codex" "(SKILL-CODEX) the roster read is the codex sitting's"
has "$(printf '%s\n' "$CALLED" | grep '^session nudge')" "through the gc-toolkit.review-arch" "(SKILL-CODEX) …and the codex kick carries the lens brief"
unset HAVE_VISIT

echo "# a name the roster does not carry is refused before anything is filed"
export BEAD_KIND=task HAVE_VISIT="" VIS_OWNER=""
run_engage tk-subj --skill nope --no-input --no-attach
eq "$RC" 2 "(SKILL-UNKNOWN) an unknown --skill exits 2"
has "$OUT" "unknown --skill 'nope'" "(SKILL-UNKNOWN) …naming the fault"
has "$OUT" "core.gc-work gc-toolkit.review-arch gc-toolkit.review-pm" "(SKILL-UNKNOWN) …and listing what the sitting carries, deduped"
hasnt "$CALLED" "bd create" "(SKILL-UNKNOWN) …nothing filed"
hasnt "$CALLED" "session new" "(SKILL-UNKNOWN) …nothing spawned"

echo "# a bare name two packs both carry is ambiguous until named in full"
export SKILL_AMBIG=1
run_engage tk-subj --skill review-arch --no-input --no-attach
eq "$RC" 2 "(SKILL-AMBIG) an ambiguous bare --skill exits 2"
has "$OUT" "contributing.review-arch gc-toolkit.review-arch" "(SKILL-AMBIG) …naming both candidates"
hasnt "$CALLED" "bd create" "(SKILL-AMBIG) …nothing filed"
run_engage tk-subj --skill gc-toolkit.review-arch --no-input --no-attach
eq "$RC" 0 "(SKILL-AMBIG) …and the full name settles it"
has "$CALLED" "through the gc-toolkit.review-arch" "(SKILL-AMBIG) …seeding the named one"
unset SKILL_AMBIG

echo "# a malformed or empty --skill is refused before the roster is read"
run_engage tk-subj --skill 'review|arch' --no-input --no-attach
eq "$RC" 2 "(SKILL-BADNAME) a --skill carrying a metacharacter exits 2"
hasnt "$CALLED" "skill list" "(SKILL-BADNAME) …refused before the roster is read"
hasnt "$CALLED" "bd create" "(SKILL-BADNAME) …nothing filed"
run_engage tk-subj --skill '' --no-input --no-attach
eq "$RC" 2 "(SKILL-BADNAME) an empty --skill exits 2"
run_engage tk-subj --skill=review-arch --no-input --no-attach
eq "$RC" 0 "(SKILL-BADNAME) the --skill=<name> spelling is accepted"

echo "# --skill on an explicit visit id is refused — its brief is already written"
export BEAD_KIND=visit VIS_OWNER="" HAVE_VISIT=""
printf 'open' > "$VIS_STATUS"
run_engage tk-vis --skill review-arch --no-input --no-attach
eq "$RC" 2 "(SKILL-VISITID) --skill with an explicit visit id exits 2"
has "$OUT" "engage tk-subj --skill review-arch" "(SKILL-VISITID) …pointing at the visit's subject"
hasnt "$CALLED" "bd create" "(SKILL-VISITID) …nothing filed"
hasnt "$CALLED" "session new" "(SKILL-VISITID) …nothing spawned"

echo "# a roster that will not read seeds the typed name unverified"
# The same fail-open reading engage takes for a model it cannot confirm: the
# operator's choice goes through, says it went unverified, and the brief tells
# the sitting to say so if it cannot load the skill.
export BEAD_KIND=task HAVE_VISIT="" VIS_OWNER="" SKILL_ROSTER_BROKEN=1
run_engage tk-subj --skill review-arch --no-input --no-attach
eq "$RC" 0 "(SKILL-UNREAD) an unreadable roster does not block the engage"
has "$OUT" "seeded unverified" "(SKILL-UNREAD) …it says the name went unverified"
has "$CALLED" "through the review-arch" "(SKILL-UNREAD) …and the brief carries the name as typed"
unset SKILL_ROSTER_BROKEN

echo "# --new-subject with --skill: the subject title is the opener after the brief"
export BEAD_KIND=task VIS_OWNER="" HAVE_VISIT=""
printf 'open' > "$VIS_STATUS"
run_engage "weigh the renderer split" --new-subject --rig gc-toolkit --skill review-arch --no-input --no-attach
eq "$RC" 0 "(SKILL-NEWSUBJ) --new-subject with --skill exits 0"
VISIT_CREATE="$(printf '%s\n' "$CALLED" | grep '^bd create' | grep -v -- '--metadata' | head -n1)"
has "$VISIT_CREATE" "visit: tk-newsubj — review-arch lens: weigh the renderer split" "(SKILL-NEWSUBJ) the visit is titled by the skill, then the subject"
has "$CALLED" "look at tk-newsubj through the gc-toolkit.review-arch" "(SKILL-NEWSUBJ) …and briefed with the lens on the new subject"

echo "# on a TTY a new visit is asked for a skill after the model; a name seeds it"
export BEAD_KIND=task HAVE_VISIT=1 VIS_OWNER=""
printf 'open' > "$VIS_STATUS"
# [d] new visit seeded discuss-broadly · Enter model (Opus) · skill review-arch
run_engage_tty 'd\n\nreview-arch\n' tk-subj --no-attach
eq "$RC" 0 "(IA-SKILL) a skill typed at the prompt exits 0"
case "$OUT" in
  *"Model —"*"Skill — Enter = none"*) ok "(IA-SKILL) the skill prompt follows the model prompt" ;;
  *) bad "(IA-SKILL) the skill prompt should follow the model prompt" ;;
esac
has "$CALLED" "through the gc-toolkit.review-arch" "(IA-SKILL) …the typed bare name seeds the resolved skill"
has "$CALLED" "talk through tk-subj broadly" "(IA-SKILL) …with the picked seed following as the opener"
has "$CALLED" "visit: tk-subj — review-arch lens: discuss broadly" "(IA-SKILL) …and both in the title"

echo "# ? lists the sitting's skills, a number picks one, and an unknown name is asked again"
# [d] seed · Enter model · "nope" (unknown, re-asked) · ? (list) · [2]
run_engage_tty 'd\n\nnope\n?\n2\n' tk-subj --no-attach
eq "$RC" 0 "(IA-SKILL-LIST) list-then-pick exits 0"
has "$OUT" 'no skill "nope" on this sitting' "(IA-SKILL-LIST) an unknown name is asked again, not refused"
has "$OUT" "[2] gc-toolkit.review-arch" "(IA-SKILL-LIST) ? lists the roster, numbered"
has "$OUT" "[3] gc-toolkit.review-pm" "(IA-SKILL-LIST) …deduped, each skill once"
hasnt "$OUT" "[4]" "(IA-SKILL-LIST) …with no repeated entries"
has "$CALLED" "through the gc-toolkit.review-arch" "(IA-SKILL-LIST) …and the number picks from that list"

echo "# --skill on a TTY skips the visit/starter prompt: it already chose a new visit"
run_engage_tty '\n' tk-subj --skill review-arch --no-attach
eq "$RC" 0 "(IA-SKILL-FLAG) --skill on a TTY exits 0 with only the model asked"
hasnt "$OUT" "starts a new one" "(IA-SKILL-FLAG) …no visit/starter prompt"
hasnt "$OUT" "Skill — Enter" "(IA-SKILL-FLAG) …and no skill prompt, the flag answered it"
has "$CALLED" "visit: tk-subj — review-arch lens" "(IA-SKILL-FLAG) …filing the new visit with the lens"
unset HAVE_VISIT

echo
echo "gc-helm engage: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
