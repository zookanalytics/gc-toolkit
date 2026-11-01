#!/usr/bin/env bash
# Hermetic test for the gc-helm `dismiss` verb: the operator's explicit "end
# this sitting".
#
# A sitting holds one conversation, a task that tracks the bead it is about and
# is assigned to the sitting's alias. dismiss closes the conversations a live
# sitting holds on the bead, or the conversation an id names, with a reason
# that names the dismissal. It answers nothing: every human gate the
# conversation replies to stays open and owed, and it writes nothing to the
# bead. It then stops the converse session that held each conversation it
# closed, with `gc runtime drain-ack`.
#
# Covered:
#   (SITTING, WHY, FORCE) the live sitting's conversation is closed over its
#             holder's claim, with the operator's words in its reason
#   (WORK-OUTCOME, WORK-REFUSED, WORK-KEPT) gc.work_outcome=no-op is stamped in
#             a write of its own before the close, and never holds it
#   (ANSWERS-NOTHING, NOSUBJECT) no gate is resolved and the bead is not written
#   (PRCOMMENT) the PR reminder is updated to say the sitting closed
#   (QUEUE, LEFT, IDEM) a bead with no live sitting has nothing to end
#   (CONVID, GATEID) a conversation id names its own conversation, a gate id the
#             bead still waiting on it
#   (SCOPE, KIND) another bead's sitting and a bead that is not a conversation
#             are untouched
#   (JSON)    --json prints one machine object
#   (STUCK, BLIND, VERIFY) a conversation that will not close, a read that does
#             not answer, and an id that does not resolve all fail the run
#   (RIG)     the lookup reads the bead's own rig store
#   (INFER*)  with no bead named, the conversation this session holds
#   (STOP-*)  the session that held a closed conversation is stopped after the
#             close: acked as an operator from outside the sitting, by its own
#             ack from inside it, as an operator under --operator, and never
#             when the holder is no converse sitting or a stop fails the run
#   (KEY)     prefix+X runs the real dismiss, which stops the sitting with one
#             operator ack Gas City takes
#   (ARGS)    an unknown flag is a usage error
#
# Runs the REAL gc-helm.sh (as `sh`, as shipped) with a stubbed `gc` on PATH
# over a file-backed store: no live city, Dolt, network or sessions.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/gc-helm.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-gc-helm-dismiss-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 (unexpected '$2' in: $1)" ;; *) ok "$3" ;; esac; }

[ -f "$SCRIPT" ] && ok "gc-helm.sh present" || bad "gc-helm.sh missing at $SCRIPT"

mkdir -p "$TMP/bin" "$TMP/store/b" "$TMP/ra/.beads"

# --- gc stub ------------------------------------------------------------------
# One JSON file per bead under $STORE/b/<id>.json, its edges as deps
# [{type, on}] on the bead the edge starts from. Two rigs: gc-toolkit (prefix
# tk, no .beads, so its reads run unpinned) and rig-a (prefix ra, whose
# .beads makes the pin visible). Every write is appended to $CALLS, and the
# store each tracks lookup and each listing read is appended to $READS.
# Hooks: DEP_DOWN fails every `bd dep list`, LIST_DOWN every `bd list`,
# SESSIONS_DOWN `gc session list`; STUCK=<id> refuses every close of that
# bead; WORK_REFUSE refuses a gc.work_outcome write. `runtime drain-ack` logs
# to $DRAINS.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
B="$STORE/b"
row() { cat "$B/$1.json" 2>/dev/null; }
put() { cat > "$B/$1.json.tmp" && mv "$B/$1.json.tmp" "$B/$1.json"; }
log() { printf '%s\n' "$*" >> "$CALLS"; }
all_ids() { for f in "$B"/*.json; do [ -f "$f" ] && basename "$f" .json; done; }
show_row() { row "$1" | jq -c '. + {dependencies: [ .deps[] | {id: .on, dependency_type: .type} ]} | del(.deps)'; }
list_row() { row "$1" | jq -c '. + {dependencies: [ .deps[] as $d | {issue_id: .id, depends_on_id: $d.on, type: $d.type} ]} | del(.deps)'; }
case "$1 ${2:-}" in
  "rig list")
    jq -n --arg ra "$RA_PATH" '{rigs:[{name:"gc-toolkit", path:"/nonexistent-rig", prefix:"tk"},
                                     {name:"rig-a", path:$ra, prefix:"ra"}]}' ;;
  "session list")
    [ -n "${SESSIONS_DOWN:-}" ] && { echo "session list: data plane down" >&2; exit 1; }
    jq -n --slurpfile s "$STORE/sessions.json" '{sessions: $s[0]}' ;;
  "bd show")
    if [ -f "$B/$3.json" ]; then jq -c -n --argjson r "$(show_row "$3")" '[$r]'
    else printf '{"error":"no issues found matching the provided IDs"}\n'; exit 1; fi ;;
  "bd list")
    printf 'list %s\n' "${BEADS_DIR:-<unpinned>}" >> "$READS"
    [ -n "${LIST_DOWN:-}" ] && { echo "bd list: data plane down" >&2; exit 1; }
    for i in $(all_ids); do list_row "$i"; done \
      | jq -sc '[ .[] | select(.status == "open" or .status == "in_progress") ]' ;;
  "bd dep")
    case "$3" in
      list)
        printf 'dep %s %s\n' "$4" "${BEADS_DIR:-<unpinned>}" >> "$READS"
        [ -n "${DEP_DOWN:-}" ] && { echo "bd dep list: data plane down" >&2; exit 1; }
        _who="$4"; _ty=""; _p=""
        for a in "$@"; do [ "$_p" = "--type" ] && _ty="$a"; _p="$a"; done
        for i in $(all_ids); do
          row "$i" | jq -c --arg w "$_who" --arg t "$_ty" 'select(any(.deps[]; .type == $t and .on == $w))
            | . + {dependency_type: $t} | del(.deps)'
        done | jq -sc '.' ;;
      *) log "$*" ;;
    esac ;;
  "runtime drain-ack")
    # The stop dismiss sends the session that held a conversation. The log line
    # names the caller's own session id and how many closes had landed, so a
    # test can tell a self-ack from an operator ack and the stop from the close
    # it follows. FAKE_DRAIN_RC fails it.
    #
    # Gas City's incarnation rules (cmd/gc/cmd_runtime_drain.go), which refuse
    # with nothing acknowledged: an --operator ack names its target, and is
    # refused when the caller's GC_SESSION_ID or GC_INSTANCE_TOKEN names that
    # session, under either reconciler. Under v2 (FAKE_DRAIN_V2) a self-ack
    # must carry the token on its own session's row. FAKE_SESSION_TOKENS holds
    # the rows' tokens as <session-id>=<token> words. A refusal ends its log
    # line with "| refused" and exits 1.
    shift 2
    tok_of() { local w; for w in ${FAKE_SESSION_TOKENS:-}; do [ "${w%%=*}" = "$1" ] && { printf '%s' "${w#*=}"; return 0; }; done; }
    refused=""
    if [ "${1:-}" = "--operator" ]; then
      if [ -z "${2:-}" ] || [ "${GC_SESSION_ID:-}" = "$2" ] \
         || { [ -n "${GC_INSTANCE_TOKEN:-}" ] && [ "$GC_INSTANCE_TOKEN" = "$(tok_of "$2")" ]; }; then
        refused=1
      fi
    elif [ -n "${FAKE_DRAIN_V2:-}" ]; then
      own=$(tok_of "${GC_SESSION_ID:-${GC_SESSION_NAME:-}}")
      if [ -z "${GC_INSTANCE_TOKEN:-}" ] || [ "$GC_INSTANCE_TOKEN" != "$own" ]; then refused=1; fi
    fi
    printf 'drain-ack %s | self=%s | closes=%s%s\n' "$*" "${GC_SESSION_ID:-}" \
        "$(grep -c '^bd close' "$CALLS" 2>/dev/null || echo 0)" "${refused:+ | refused}" >> "${DRAINS:-/dev/null}"
    [ -z "$refused" ] || { echo "gc runtime drain-ack: refused by the incarnation rules; nothing acknowledged" >&2; exit 1; }
    exit "${FAKE_DRAIN_RC:-0}" ;;
  "bd gate")
    log "$*" ;;
  "bd close")
    log "$*"
    _id="$3"; _r=""; _force=""; _p=""
    for a in "$@"; do [ "$_p" = "--reason" ] && _r="$a"; [ "$a" = "--force" ] && _force=1; _p="$a"; done
    [ "${STUCK:-}" = "$_id" ] && { echo "bd close: refused" >&2; exit 1; }
    # bd's close guard: a bead another actor holds closes only with --force.
    _st=$(row "$_id" | jq -r '.status'); _a=$(row "$_id" | jq -r '.assignee // ""')
    if [ "$_st" = in_progress ] && [ -n "$_a" ] && [ -z "$_force" ]; then
      echo "bd close: $_id is claimed by $_a" >&2; exit 1
    fi
    row "$_id" | jq --arg r "$_r" '.status = "closed" | .close_reason = $r' | put "$_id" ;;
  "bd update")
    log "$*"
    _id="$3"; shift 3
    case " $* " in *" gc.work_outcome="*) [ -n "${WORK_REFUSE:-}" ] && exit 1 ;; esac
    _r=$(row "$_id")
    while [ $# -gt 0 ]; do
      case "$1" in
        --set-metadata) _k="${2%%=*}"; _v="${2#*=}"; _r=$(printf '%s' "$_r" | jq --arg k "$_k" --arg v "$_v" '.metadata[$k] = $v'); shift 2 ;;
        *) shift ;;
      esac
    done
    printf '%s' "$_r" | put "$_id" ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

# A recorder standing in for pr-sitting-comment.sh.
cat > "$TMP/rec-psc" <<'REC'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$REC_PSC_LOG"
REC
chmod +x "$TMP/rec-psc"

export PATH="$TMP/bin:$PATH"
export STORE="$TMP/store" CALLS="$TMP/calls" READS="$TMP/reads" RA_PATH="$TMP/ra"
export GC_SITTING_COMMENT_TOOL="$TMP/rec-psc" REC_PSC_LOG="$TMP/psc.log"
unset GC_HELM_FIXTURE GC_RIG BEADS_DIR GC_SESSION_ID GC_SESSION_NAME GC_ALIAS 2>/dev/null || true
export TMPDIR="$TMP"

# --- fixtures -----------------------------------------------------------------
# The bead tk-subj with a gate tk-gate blocking it. The conversation tk-conv
# tracks it and replies to the gate; tk-conv is held by the live sitting gc-50
# (alias gc-toolkit/gc-toolkit.tk-conv). tk-other has a live sitting of its own
# (tk-oconv, held by gc-51), and tk-find is a patrol finding that tracks
# tk-subj, assigned to nobody, which is no conversation.
fresh() {
    rm -rf "$STORE"; mkdir -p "$STORE/b"; : > "$CALLS"; : > "$READS"; : > "$REC_PSC_LOG"
    bead tk-subj task open ""
    bead tk-gate gate open ""; jq '.await_type = "human" | .await_id = "rollout"' "$STORE/b/tk-gate.json" > "$STORE/b/x" && mv "$STORE/b/x" "$STORE/b/tk-gate.json"
    edge tk-subj blocks tk-gate
    bead tk-conv task in_progress gc-toolkit/gc-toolkit.tk-conv; edge tk-conv tracks tk-subj; edge tk-conv replies-to tk-gate
    bead tk-other task open ""
    bead tk-oconv task in_progress gc-toolkit/gc-toolkit.tk-oconv; edge tk-oconv tracks tk-other
    bead tk-find task open ""; edge tk-find tracks tk-subj
    sessions '[{"id":"gc-50","session_name":"s-gc-50","alias":"gc-toolkit/gc-toolkit.tk-conv","template":"gc-toolkit/gc-toolkit.converse-opus","state":"active","closed":false,"rig":"gc-toolkit"},
               {"id":"gc-51","session_name":"s-gc-51","alias":"gc-toolkit/gc-toolkit.tk-oconv","template":"gc-toolkit/gc-toolkit.converse-opus","state":"active","closed":false,"rig":"gc-toolkit"}]'
}
# bead <id> <type> <status> <assignee>
bead() {
    jq -n --arg id "$1" --arg t "$2" --arg s "$3" --arg a "$4" '{id:$id, title:("the bead " + $id), issue_type:$t, status:$s,
        assignee:$a, created_at:"2026-10-01T00:00:00Z", metadata:{}, deps:[]}' > "$STORE/b/$1.json"
}
edge() { jq --arg t "$2" --arg o "$3" '.deps += [{type:$t, on:$o}]' "$STORE/b/$1.json" > "$STORE/b/$1.tmp" && mv "$STORE/b/$1.tmp" "$STORE/b/$1.json"; }
sessions() { printf '%s' "$1" > "$STORE/sessions.json"; }
field() { jq -r --arg k "$2" '.[$k] // "" | tostring' "$STORE/b/$1.json" 2>/dev/null; }
meta()  { jq -r --arg k "$2" '.metadata[$k] // ""' "$STORE/b/$1.json" 2>/dev/null; }
calls() { cat "$CALLS"; }

# run_dismiss <args...> -> RC, OUT (stdout), ERR (stderr).
run_dismiss() {
    set +e
    OUT="$(sh "$SCRIPT" dismiss "$@" 2>"$TMP/err")"; RC=$?
    set -e
    ERR="$(cat "$TMP/err")"
}

echo "# dismiss ends the live sitting on a bead"
fresh; run_dismiss tk-subj --reason "settled offline"
eq "$RC" 0 "(SITTING) dismissing a bead with a live sitting exits 0"
eq "$(field tk-conv status)" "closed" "(SITTING) …the sitting's conversation is closed"
has "$OUT" "closed over its holder's claim conversation tk-conv — the sitting on tk-subj ends" "(SITTING) …and the run says so"
eq "$(grep -c '^bd close tk-conv' "$CALLS")" "2" "(FORCE) the holder's claim is overridden once, after the plain close is refused"
has "$(grep '^bd close tk-conv' "$CALLS" | tail -1)" "--force" "(FORCE) …by --force"
eq "$(field tk-conv close_reason)" "dismissed by the operator: settled offline" "(WHY) the close reason names the dismissal and carries the operator's words"
eq "$(meta tk-conv gc.work_outcome)" "no-op" "(WORK-OUTCOME) the conversation is stamped gc.work_outcome=no-op"
case "$(calls)" in
  *"bd update tk-conv --set-metadata gc.work_outcome=no-op"*"bd close tk-conv"*) ok "(WORK-OUTCOME) …in a write of its own, before the close" ;;
  *) bad "(WORK-OUTCOME) the work stamp should precede the close (calls: $(calls))" ;;
esac
hasnt "$(calls)" "bd gate" "(ANSWERS-NOTHING) no gate is resolved: the gate it replies to stays open and owed"
eq "$(field tk-gate status)" "open" "(ANSWERS-NOTHING) …and reads open"
hasnt "$(calls)" "bd update tk-subj" "(NOSUBJECT) the bead is never written"
hasnt "$(calls)" "bd dep" "(NOSUBJECT) …and no edge is touched"
has "$(cat "$REC_PSC_LOG")" "close --sitting tk-conv --subject tk-subj --outcome dismissed" "(PRCOMMENT) the PR reminder is updated to say the sitting closed"
eq "$(field tk-oconv status)" "in_progress" "(SCOPE) another bead's live sitting is untouched"
eq "$(field tk-find status)" "open" "(KIND) a bead that tracks the subject but is no conversation is never closed"
run_dismiss tk-subj
eq "$RC" 0 "(IDEM) a second dismiss exits 0"
has "$OUT" "no live sitting on tk-subj — nothing to end" "(IDEM) …saying there is nothing to end"

echo "# a bead with no live sitting has nothing to end"
fresh; jq '.assignee = "human" | .status = "open"' "$STORE/b/tk-conv.json" > "$STORE/b/x" && mv "$STORE/b/x" "$STORE/b/tk-conv.json"
run_dismiss tk-subj
eq "$RC" 0 "(QUEUE) a bead whose conversation waits in the queue exits 0"
has "$OUT" "no live sitting on tk-subj — nothing to end" "(QUEUE) …saying nothing is live"
eq "$(field tk-conv status)" "open" "(QUEUE) …and the queued conversation stays"
eq "$(grep -c '^bd ' "$CALLS" || true)" "0" "(QUEUE) …writing nothing"
fresh; sessions '[]'
run_dismiss tk-subj
eq "$RC" 0 "(LEFT) a conversation whose sitting's session closed exits 0"
eq "$(field tk-conv status)" "in_progress" "(LEFT) …and stays for the next engage to resume"

echo "# a conversation id names its own conversation, and a gate id the bead waiting on it"
fresh; jq '.assignee = "human" | .status = "open"' "$STORE/b/tk-conv.json" > "$STORE/b/x" && mv "$STORE/b/x" "$STORE/b/tk-conv.json"
run_dismiss tk-conv --reason "not needed"
eq "$RC" 0 "(CONVID) dismissing a conversation id exits 0"
eq "$(field tk-conv status)" "closed" "(CONVID) …closing that conversation, even one waiting in the queue"
has "$ERR" "tk-conv is a conversation on tk-subj" "(CONVID) …naming the bead it is about"
eq "$(field tk-gate status)" "open" "(CONVID) …and answering nothing"
fresh; run_dismiss tk-gate
eq "$RC" 0 "(GATEID) dismissing a gate id exits 0"
has "$ERR" "tk-gate is a gate about tk-subj" "(GATEID) …taking the bead still waiting on it"
eq "$(field tk-conv status)" "closed" "(GATEID) …and ending the live sitting there"
eq "$(field tk-gate status)" "open" "(GATEID) …while the gate stays open"

echo "# --json prints one machine object"
fresh; run_dismiss tk-subj --json
eq "$RC" 0 "(JSON) --json exits 0"
eq "$(printf '%s' "$OUT" | jq -c '.')" '{"subject":"tk-subj","matched":[{"id":"tk-conv"}],"closed":1,"ok":true}' "(JSON) …stdout is the one object naming what it closed"
has "$ERR" "conversation tk-conv" "(JSON) …and the human line goes to stderr"
fresh; sessions '[]'; run_dismiss tk-subj --json
eq "$(printf '%s' "$OUT" | jq -c '.')" '{"subject":"tk-subj","matched":[],"closed":0,"ok":true}' "(JSON) …and with nothing to end, an empty match"

echo "# a conversation that will not close, a read that does not answer, an id that does not resolve"
fresh; STUCK=tk-conv run_dismiss tk-subj
eq "$RC" 4 "(STUCK) a conversation that will not close exits 4"
has "$ERR" "gc bd close tk-conv --force" "(STUCK) …naming the command that finishes the job"
has "$ERR" "was NOT dismissed" "(STUCK) …and saying the bead was not dismissed"
eq "$(field tk-conv status)" "in_progress" "(STUCK) …leaving the sitting its pane"
fresh; WORK_REFUSE=1 run_dismiss tk-subj
eq "$RC" 0 "(WORK-REFUSED) a refused work stamp does not fail the dismiss"
eq "$(field tk-conv status)" "closed" "(WORK-REFUSED) …and the conversation still closes"
fresh; jq '.metadata["gc.work_outcome"] = "abandoned"' "$STORE/b/tk-conv.json" > "$STORE/b/x" && mv "$STORE/b/x" "$STORE/b/tk-conv.json"
run_dismiss tk-subj
eq "$(field tk-conv status)" "closed" "(WORK-KEPT) a conversation already recording a work outcome closes"
eq "$(meta tk-conv gc.work_outcome)" "abandoned" "(WORK-KEPT) …and nothing is written over it"
hasnt "$(calls)" "gc.work_outcome=no-op" "(WORK-KEPT) …no no-op stamp is attempted"
fresh; DEP_DOWN=1 run_dismiss tk-subj
eq "$RC" 4 "(BLIND) a conversation lookup that does not answer exits 4"
has "$ERR" "could not read the conversations on tk-subj" "(BLIND) …naming the read"
eq "$(grep -c '^bd ' "$CALLS" || true)" "0" "(BLIND) …and writing nothing"
fresh; SESSIONS_DOWN=1 run_dismiss tk-subj
eq "$RC" 4 "(BLIND) a session list that does not answer exits 4"
has "$ERR" "could not read 'gc session list'" "(BLIND) …naming that read"
eq "$(grep -c '^bd ' "$CALLS" || true)" "0" "(BLIND) …and writing nothing"
fresh; run_dismiss tk-nope
eq "$RC" 4 "(VERIFY) an id that does not resolve exits 4"
has "$ERR" "bead not found" "(VERIFY) …saying why"
eq "$(grep -c '^bd ' "$CALLS" || true)" "0" "(VERIFY) …and writing nothing"

echo "# the lookup reads the bead's own rig store"
fresh; bead ra-9001 task open ""
run_dismiss ra-9001
has "$(grep '^dep ra-9001' "$READS")" "$TMP/ra/.beads" "(RIG) the conversation lookup is pinned at the bead's rig"

echo "# with no bead named, dismiss ends the sitting this session holds"
fresh; GC_SESSION_ID=gc-toolkit/gc-toolkit.tk-conv run_dismiss --reason "from the pane"
eq "$RC" 0 "(INFER) a bare dismiss in a sitting exits 0"
has "$ERR" "inferred the current sitting's conversation tk-conv on tk-subj" "(INFER) …naming what it inferred"
eq "$(field tk-conv status)" "closed" "(INFER) …and closing that conversation"
eq "$(field tk-conv close_reason)" "dismissed by the operator: from the pane" "(INFER) …with the operator's words"
eq "$(field tk-oconv status)" "in_progress" "(INFER) …and no other"
fresh; run_dismiss
eq "$RC" 2 "(INFER-NOID) no identity and no bead is a usage error"
has "$ERR" "dismiss <bead-id>" "(INFER-NOID) …naming the runnable form"
fresh; GC_SESSION_ID=gc-toolkit/gc-toolkit.nobody run_dismiss
eq "$RC" 2 "(INFER-NONE) a session holding no conversation refuses to guess"
has "$ERR" "no open conversation is assigned to this session" "(INFER-NONE) …saying so"
fresh; LIST_DOWN=1 GC_SESSION_ID=gc-toolkit/gc-toolkit.tk-conv run_dismiss
eq "$RC" 4 "(INFER-BLIND) a listing that does not answer exits 4"
fresh; jq '.assignee = "gc-toolkit/gc-toolkit.tk-conv"' "$STORE/b/tk-oconv.json" > "$STORE/b/x" && mv "$STORE/b/x" "$STORE/b/tk-oconv.json"
bead tk-conv3 task in_progress gc-toolkit/gc-toolkit.tk-conv3; edge tk-conv3 tracks tk-other
GC_ALIAS=gc-toolkit/gc-toolkit.tk-conv GC_SESSION_ID=gc-toolkit/gc-toolkit.tk-conv3 run_dismiss
eq "$RC" 2 "(INFER-AMBIG) a session holding two conversations refuses to guess"
has "$ERR" "more than one open conversation" "(INFER-AMBIG) …naming the ambiguity"
eq "$(grep -c '^bd ' "$CALLS" || true)" "0" "(INFER-AMBIG) …and writing nothing"
fresh; bead ra-subj task open ""; bead ra-conv task in_progress gc-toolkit/gc-toolkit.ra-conv; edge ra-conv tracks ra-subj
sessions '[{"id":"gc-60","session_name":"s-gc-60","alias":"gc-toolkit/gc-toolkit.ra-conv","template":"gc-toolkit/gc-toolkit.converse-opus","state":"active","closed":false,"rig":"rig-a"}]'
GC_SESSION_ID=gc-60 GC_ALIAS=gc-toolkit/gc-toolkit.ra-conv run_dismiss
has "$(grep '^list' "$READS")" "$TMP/ra/.beads" "(INFER-RIG) the current-sitting lookup is pinned at the session's own rig"
eq "$(field ra-conv status)" "closed" "(INFER-RIG) …and finds the conversation there"

echo "# dismiss stops the session that held the conversation it closed"
# A sitting must not outlive its conversation, and a session viewed in a tab is
# not kept up by the viewing. The stop is `gc runtime drain-ack`, so the
# controller ends the session outside the verb's process: the holder the verb
# runs in acks itself, after every close; any other holder is acked as an
# operator. Only a live converse session counts as a holder, and a stop that
# fails leaves the dismiss standing and names converse-reap.
export DRAINS="$TMP/drains"
drains() { cat "$DRAINS"; }
fresh; : > "$DRAINS"; run_dismiss tk-subj
eq "$RC" 0 "(STOP-OTHER) a dismiss from outside the sitting exits 0"
eq "$(drains)" "drain-ack --operator gc-50 | self= | closes=2" \
   "(STOP-OTHER) …and acks the holding session as an operator, once, after the conversation's close"
has "$OUT" "stopped session gc-50, which held the sitting" "(STOP-OTHER) …and says which session it stopped"
fresh; : > "$DRAINS"; GC_SESSION_ID=gc-50 run_dismiss tk-subj
eq "$RC" 0 "(STOP-OWN) a dismiss typed into the sitting exits 0"
eq "$(drains)" "drain-ack  | self=gc-50 | closes=2" "(STOP-OWN) …and the sitting acks its own session, after the conversation's close"
has "$OUT" "ending this session (gc-50), which held the sitting" "(STOP-OWN) …saying so before it does"
fresh; : > "$DRAINS"; FAKE_DRAIN_RC=1 run_dismiss tk-subj
eq "$RC" 0 "(STOP-FAIL) a stop that fails leaves the dismiss standing"
has "$ERR" "could not stop session gc-50, which held the sitting; converse-reap closes it on its next pass, because its conversation is closed" \
    "(STOP-FAIL) …and names converse-reap as what closes the session"
# A holder that runs another template is no sitting, so the close stops nothing.
fresh; : > "$DRAINS"
sessions '[{"id":"gc-50","session_name":"s-gc-50","alias":"gc-toolkit/gc-toolkit.tk-conv","template":"gc-toolkit/gc-toolkit.polecat","state":"active","closed":false,"rig":"gc-toolkit"}]'
jq '.assignee = "human" | .status = "open"' "$STORE/b/tk-conv.json" > "$STORE/b/x" && mv "$STORE/b/x" "$STORE/b/tk-conv.json"
jq '.assignee = "gc-toolkit/gc-toolkit.tk-conv"' "$STORE/b/tk-conv.json" > "$STORE/b/x" && mv "$STORE/b/x" "$STORE/b/tk-conv.json"
run_dismiss tk-conv
eq "$(field tk-conv status)" "closed" "(STOP-CONVERSE) a conversation held under a session that is no converse sitting closes"
eq "$(drains)" "" "(STOP-CONVERSE) …and stops nothing"
# A conversation waiting in the queue is held by nobody.
fresh; : > "$DRAINS"; jq '.assignee = "human" | .status = "open"' "$STORE/b/tk-conv.json" > "$STORE/b/x" && mv "$STORE/b/x" "$STORE/b/tk-conv.json"
run_dismiss tk-conv
eq "$(field tk-conv status)" "closed" "(STOP-NOHOLDER) a conversation in the queue closes by its id"
eq "$(drains)" "" "(STOP-NOHOLDER) …and, held by nobody, stops nothing"
# The claim stamps the holder's id on the conversation, so the gc.session_id
# pin finds a holder whose name the assignee does not carry.
fresh; : > "$DRAINS"
jq '.metadata["gc.session_id"] = "gc-81" | .metadata["gc.session_name"] = "s-gc-81"' "$STORE/b/tk-conv.json" > "$STORE/b/x" && mv "$STORE/b/x" "$STORE/b/tk-conv.json"
sessions '[{"id":"gc-81","session_name":"s-gc-81","alias":"gc-toolkit/gc-toolkit.tk-conv-other","template":"gc-toolkit/gc-toolkit.converse-fable","state":"active","closed":false,"rig":"gc-toolkit"}]'
run_dismiss tk-conv
case "$(drains)" in
  "drain-ack --operator gc-81 "*) ok "(STOP-PIN) the conversation's gc.session_id names the holder to stop" ;;
  *) bad "(STOP-PIN) the pinned holder was not stopped (drains: $(drains); out: $OUT $ERR)" ;;
esac

# From here on the stub knows the sittings' tokens, so its drain-ack applies
# every incarnation rule. A sitting's tmux environment carries its session id
# and token, and a run-shell job inherits that environment, so a caller outside
# the sitting can carry both.
export FAKE_SESSION_TOKENS="gc-50=tok-50 gc-51=tok-51"
fresh; : > "$DRAINS"; FAKE_DRAIN_V2=1 GC_SESSION_ID=gc-50 GC_INSTANCE_TOKEN=tok-50 run_dismiss tk-subj
eq "$(drains)" "drain-ack  | self=gc-50 | closes=2" \
   "(STOP-OWN-V2) a dismiss in the sitting acks its own session with its own token, which v2 takes"
# --operator: the caller runs under the sitting's identity and token, as the
# prefix+X job does, and is still outside it. The stop is an operator ack run
# with neither, which Gas City takes under either reconciler, and nothing acks
# itself.
for _mode in legacy v2; do
    _v2=""; [ "$_mode" = v2 ] && _v2=1
    fresh; : > "$DRAINS"
    FAKE_DRAIN_V2="$_v2" GC_SESSION_ID=gc-50 GC_SESSION_NAME=s-gc-50 GC_INSTANCE_TOKEN=tok-50 run_dismiss --operator tk-subj
    eq "$RC" "0" "(STOP-OPERATOR) [$_mode] dismiss --operator under the sitting's identity exits 0"
    eq "$(drains)" "drain-ack --operator gc-50 | self= | closes=2" \
       "(STOP-OPERATOR) [$_mode] …and acks the sitting as an operator, with no session identity or token, which Gas City takes"
    has "$OUT" "stopped session gc-50" "(STOP-OPERATOR) [$_mode] …and says which session it stopped"
    hasnt "$OUT" "ending this session" "(STOP-OPERATOR) [$_mode] …and never takes the sitting for its own session"
done
# Another sitting dismissing this one's bead acks it as an operator too, and its
# own identity never reaches that ack.
fresh; : > "$DRAINS"; FAKE_DRAIN_V2=1 GC_SESSION_ID=gc-51 GC_INSTANCE_TOKEN=tok-51 run_dismiss tk-subj
eq "$(drains)" "drain-ack --operator gc-50 | self= | closes=2" \
   "(STOP-OTHER-V2) a dismiss from another sitting acks the holder as an operator, without its own identity"

# prefix+X through the real dismiss. tmux-dismiss-sitting.sh runs THIS dismiss
# under the sitting's identity, so dismiss infers the conversation, and its job
# inherits the pressed sitting's tmux environment. Its stop must still be an
# operator ack Gas City takes: under v2 with the inherited token, under v2 when
# the job inherited none, and under legacy. A self-ack fails the second, and an
# operator ack that kept the sitting's session id fails all three.
mkdir -p "$TMP/keybin"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/keybin/tmux" <<'TMUXSTUB'
# display-message -p answers the format it is asked for; any other
# display-message is a message to the operator, logged to FAKE_KEY_SAID.
if [ "$1" = display-message ]; then
    for a in "$@"; do
        if [ "$a" = "-p" ]; then
            case "${!#}" in
                '#{client_tty}')     printf '/dev/pts/7\n' ;;
                '#{client_session}') printf 's-gc-50\n' ;;
            esac
            exit 0
        fi
    done
    printf '%s\n' "${!#}" >> "$FAKE_KEY_SAID"
fi
exit 0
TMUXSTUB
chmod +x "$TMP/keybin/tmux"
KEY_CFG="$(cd "$HERE/../.." && pwd)"
export FAKE_KEY_SAID="$TMP/key-said"
for _mode in v2-inherited v2-bare legacy-inherited; do
    _v2=""; case "$_mode" in v2-*) _v2=1 ;; esac
    _tok=tok-50; [ "$_mode" = v2-bare ] && _tok=""
    fresh; : > "$DRAINS"; : > "$FAKE_KEY_SAID"
    KRC=0; KOUT="$(PATH="$TMP/keybin:$PATH" FAKE_DRAIN_V2="$_v2" \
        GC_SESSION_ID=gc-50 GC_SESSION_NAME=s-gc-50 GC_INSTANCE_TOKEN="$_tok" \
        sh "$HERE/tmux-dismiss-sitting.sh" "$KEY_CFG" 2>/dev/null)" || KRC=$?
    eq "$KRC/$KOUT" "0/" "(KEY) [$_mode] prefix+X exits 0 with nothing on stdout"
    eq "$(drains)" "drain-ack --operator gc-50 | self= | closes=2" \
       "(KEY) [$_mode] …and the real dismiss stops the sitting with one operator ack that Gas City takes"
    has "$(cat "$FAKE_KEY_SAID")" "the sitting on tk-subj is over (conversation tk-conv closed), and its session is ending" \
        "(KEY) [$_mode] …and tells the operator the sitting is over"
done
unset DRAINS FAKE_SESSION_TOKENS FAKE_KEY_SAID

echo "# argument checks"
fresh; run_dismiss tk-subj --nope
eq "$RC" 2 "(ARGS) an unknown flag is a usage error"

echo
echo "gc-helm dismiss: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
