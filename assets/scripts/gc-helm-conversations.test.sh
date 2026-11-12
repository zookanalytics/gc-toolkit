#!/usr/bin/env bash
# Hermetic test for the reads and the save the terminal conversation form makes
# through gc-helm.sh: `conversations` and `open --new-subject`.
#
# Runs the REAL gc-helm.sh (invoked via `sh`, as shipped) with a stubbed `gc` on
# PATH that answers from JSON files under $STATE — no live city, Dolt, network
# or sessions. Covered:
#   (CITY)        every open conversation in the city's stores, each with its
#                 state, its session and its readiness: a sitting that has posted
#                 a hand-back since its session started is ready, one that has
#                 not is preparing, one whose session has not started is
#                 starting, one whose session closed is ended, one in the queue
#                 is queued; a bound conversation its sitting has not claimed
#                 reads starting; each row carries its subject's title, and a
#                 task that is not a conversation is left out; the rigs a new
#                 topic can be filed in, each with its prefix, whether it
#                 carries converse and whether it is suspended
#   (CITY-SEATS)  the seats the form's People page lists: mechanik, then the po
#                 of each rig a new topic can go to, each with the open session
#                 the session list holds under the name the agent roster gives
#                 its session, or null, read from the one session list the
#                 conversations were read from and the one roster the rigs'
#                 converse was read from
#   (CITY-SEATS-KIT) under a city that imports the pack as kit, each seat's
#                 session is the one under kit's name, and a session under
#                 gc-toolkit's name is no seat's
#   (CITY-SEATS-NAME) a seat whose template the roster names no agent for in
#                 its rig, or two, is left out
#   (CITY-SEATS-ROSTER) a roster that cannot be read lists no seat, says so in
#                 roster_unread and exits 4, and lists the conversations and
#                 the unread stores as a roster that reads does, and the rigs,
#                 and the list without --json, which shows no seat, still lists
#   (CITY-ENDED)  a bound conversation whose sitting ended before it claimed it
#                 is found by its own row and reads ended, as conversations
#                 <subject> reads it
#   (CITY-UNREAD) a store that does not answer is named, the others listed, and
#                 the verb exits 4 after the list
#   (CITY-NOLEDGER) a rig whose ledger is not there is named as unread too, and
#                 the verb exits 4 after the list
#   (CITY-SCRATCH) the list never reads as complete when its scratch files fail:
#                 a store whose read failed is named unread even when no marker
#                 of its failure could be written, and so is one whose list was
#                 written but not marked done; a rig list that cannot be written
#                 exits 3, and a list that holds nothing although its store
#                 answered exits 4, each listing nothing
#   (CITY-TEXT)   without --json the list reads as one line per conversation
#   (ABOUT)       a subject is resolved as engage resolves it: its rig, whether
#                 a sitting can start there, its open conversations and what
#                 holds it; a conversation id names its subject and itself; a gate
#                 names the bead waiting on it and itself
#   (ABOUT-FROM)  a gate two beads wait on is about the one --from names, and
#                 read from nothing about the one whose wait on it is oldest,
#                 the same one each read, then the lowest id, a wait with no
#                 recorded time reading last; a read of those waits that does
#                 not answer exits 4; a gate that holds the --from bead only
#                 through another bead is read as without --from, and one that
#                 no longer holds it is refused; --from with no reference is
#                 refused, exit 2; accept, dismiss and handback refuse a gate
#                 two beads wait on, naming both
#   (ABOUT-SUSPENDED) a subject in a suspended rig reads with rig_suspended
#                 and no refusal, and the text says it waits until the rig
#                 resumes
#   (ABOUT-REFUSE) a rig with no converse and a closed subject are said as the
#                 refusal a sitting would meet; a bead that does not resolve
#                 exits 4
#   (ABOUT-PR)    a bare PR number two live anchors record answers both as
#                 candidates, and one that one anchor records resolves to it
#   (NEWSUBJ)     open --new-subject files the subject in the --rig rig, titled
#                 from the question's opening, the question unchanged in its
#                 description, marked reaction-owned, then its conversation, whose
#                 ask is the question unchanged; --json's last answer names both
#   (NEWSUBJ-EARLY) --json answers the subject the moment it is filed, before
#                 open reads anything after it, so a caller that stops waiting
#                 there still knows it
#   (NEWSUBJ-PART) a subject filed whose conversation is not says so, names the
#                 subject on stderr and in --json, and exits 4
#   (NEWSUBJ-RIG) no --rig, an unknown rig and a rig that carries no converse
#                 are refused before anything is created; --rig without
#                 --new-subject is refused
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/gc-helm.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-gc-helm-conversations-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()    { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has()   { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (unexpected '$2' in: $1)" ;; *) ok "$3" ;; esac; }

# The session's own city must not reach a hermetic run.
unset GC_CITY_PATH GC_CITY GC_CITY_ROOT GC_RIG BEADS_DIR GC_HELM_FIXTURE || true
export STATE="$TMP/state" CALLS="$TMP/calls"
mkdir -p "$TMP/bin" "$STATE" "$TMP/.beads" "$TMP/rig/.beads" "$TMP/rig2/.beads" "$TMP/rig3/.beads" "$TMP/agents/converse-claude-opus" "$TMP/agents/converse-claude-fable"
export GC_HELM_AGENTS_DIR="$TMP/agents"

cat > "$TMP/bin/gc" <<'STUB'
#!/usr/bin/env bash
# The stub reads each store's rows from $STATE/<prefix>.json.
printf '%s\n' "$*" | tr '\n' ' ' >> "$CALLS"; printf '\n' >> "$CALLS"
# The first call after a new subject's create keeps what open had printed on
# stdout by then, when the case names the file its stdout goes to.
if [ -n "${ANSWER_FILE:-}" ] && [ -f "$STATE/subj.title" ] && [ ! -e "$STATE/answer.at-next-call" ]; then
  cp "$ANSWER_FILE" "$STATE/answer.at-next-call"
fi
# A read with no --db reads the store BEADS_DIR names, as bd does.
db_prefix() { case "${1:-${BEADS_DIR:-}}" in */rig/.beads) echo tk ;; */rig2/.beads) echo gc ;; */rig3/.beads) echo dx ;; *) echo hq ;; esac; }
arg_after() { _want="$1"; shift; _prev=""; for a in "$@"; do [ "$_prev" = "$_want" ] && { printf '%s' "$a"; return; }; _prev="$a"; done; }
case "$1 ${2:-}" in
  "rig list") cat "$STATE/rigs.json" ;;
  "session list") cat "$STATE/sessions.json" ;;
  "agent list") cat "$STATE/agents.json" ;;
  "status --json") echo '{"controller":{"running":true}}' ;;
  "bd list")
    shift 2
    db=$(arg_after --db "$@"); p=$(db_prefix "$db")
    [ -f "$STATE/$p.unread" ] && exit 1
    rows="$STATE/$p.json"; [ -f "$rows" ] || { echo '[]'; exit 0; }
    ids=$(arg_after --id "$@"); status=$(arg_after --status "$@"); asg=$(arg_after --assignee "$@")
    # $LIST_ID_FAIL fails a listing by id that names it, as a store that did not answer.
    if [ -n "${LIST_ID_FAIL:-}" ]; then case ",$ids," in *",$LIST_ID_FAIL,"*) exit 1 ;; esac; fi
    jq -c --arg ids "$ids" --arg st "$status" --arg asg "$asg" '
      [ .[] | select($ids == "" or (.id as $i | ($ids | split(",")) | index($i)))
            | select($ids != "" or $st == "" or (.status as $s | ($st | split(",")) | index($s)))
            | select($asg == "" or .assignee == $asg) ]' "$rows" ;;
  "bd show")
    id="$3"; p="${id%%-*}"
    jq -c --arg i "$id" '[ .[] | select(.id == $i) ]' "$STATE/$p.json" 2>/dev/null || echo '[]' ;;
  "bd dep")
    # dep list <id> --direction=up --type tracks|blocks : the beads that point at <id>
    id="$4"; p="${id%%-*}"; typ=$(arg_after --type "$@")
    case "$*" in *--direction=up*)
      jq -c --arg i "$id" --arg t "$typ" '[ .[] | select(any(.dependencies[]?; .type == $t and .depends_on_id == $i)) | {id, status, assignee, issue_type, dependency_type: $t} ]' "$STATE/$p.json" 2>/dev/null || echo '[]' ;;
    *) echo '[]' ;;
    esac ;;
  "bd create")
    shift 2
    title=$(arg_after --title "$@"); desc=$(arg_after -d "$@"); deps=$(arg_after --deps "$@")
    if [ -n "$deps" ]; then
      [ -n "${CONV_CREATE_FAIL:-}" ] && { echo '{"error":"store write refused"}'; exit 0; }
      printf '%s' "$title" > "$STATE/conv.title"; printf '%s' "$desc" > "$STATE/conv.description"
      subj="${deps#tracks:}"; p="${subj%%-*}"
      jq --arg s "$subj" --arg t "$title" '. + [{id:"tk-newconv", issue_type:"task", status:"open", assignee:"human", title:$t, dependencies:[{type:"tracks", depends_on_id:$s}]}]' "$STATE/$p.json" > "$STATE/tmp.json" && mv "$STATE/tmp.json" "$STATE/$p.json"
      echo '{"id":"tk-newconv"}'
    else
      printf '%s' "$title" > "$STATE/subj.title"; printf '%s' "$desc" > "$STATE/subj.description"
      arg_after --metadata "$@" > "$STATE/subj.metadata"; arg_after --db "$@" > "$STATE/subj.db"
      jq --arg t "$title" '. + [{id:"tk-newsubj", issue_type:"task", status:"open", title:$t}]' "$STATE/tk.json" > "$STATE/tmp.json" && mv "$STATE/tmp.json" "$STATE/tk.json"
      echo '{"id":"tk-newsubj"}'
    fi ;;
  "bd update"|"bd close") : ;;
  *) echo "stub gc: unhandled: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$TMP/bin/gc"
printf '#!/bin/sh\necho "{\\"reasons\\":${GCTK_REASONS:-[]}}"\n' > "$TMP/bin/gctk"
chmod +x "$TMP/bin/gctk"
export PATH="$TMP/bin:$PATH" GCTK_BIN="$TMP/bin/gctk"

# The city: gc-toolkit (tk) carries converse, gascity (gc) is suspended, docs
# (dx) carries no converse, and the city's own store.
seed() {
  : > "$CALLS"; rm -f "$STATE"/*.unread "$STATE"/subj.* "$STATE"/conv.* "$STATE"/answer.*
  jq -n --arg r "$TMP/rig" --arg r2 "$TMP/rig2" --arg r3 "$TMP/rig3" --arg h "$TMP" '{rigs:[
    {name:"gc-toolkit", path:$r, prefix:"tk", suspended:false},
    {name:"gascity", path:$r2, prefix:"gc", suspended:true},
    {name:"docs", path:$r3, prefix:"dx", suspended:false},
    {name:"hq", path:$h, prefix:"hq", hq:true, running:true}]}' > "$STATE/rigs.json"
  jq -n '{agents:[
    {name:"converse-claude-opus", dir:"gc-toolkit", qualified_name:"gc-toolkit/gc-toolkit.converse-claude-opus"},
    {name:"converse-claude-opus", dir:"gascity", qualified_name:"gascity/gc-toolkit.converse-claude-opus"},
    {name:"mechanik", qualified_name:"gc-toolkit.mechanik", scope:"city"},
    {name:"po", dir:"gc-toolkit", qualified_name:"gc-toolkit/gc-toolkit.po", scope:"rig"},
    {name:"po", dir:"gascity", qualified_name:"gascity/gc-toolkit.po", scope:"rig"},
    {name:"po", dir:"docs", qualified_name:"docs/gc-toolkit.po", scope:"rig"}]}' > "$STATE/agents.json"
  jq -n '{sessions:[
    {id:"s1", alias:"gc-toolkit/gc-toolkit.tk-ready", session_name:"s-s1", state:"active", attached:false, created_at:"2026-11-08T10:00:00Z", template:"gc-toolkit/gc-toolkit.converse-claude-opus"},
    {id:"s2", alias:"gc-toolkit/gc-toolkit.tk-prep", session_name:"s-s2", state:"active", attached:true, created_at:"2026-11-08T11:00:00Z", template:"gc-toolkit/gc-toolkit.converse-claude-opus"},
    {id:"s3", alias:"gc-toolkit/gc-toolkit.tk-bound", session_name:"s-s3", state:"start-pending", attached:false, created_at:"2026-11-08T12:00:00Z", template:"gc-toolkit/gc-toolkit.converse-claude-opus"},
    {id:"s4", alias:"gc-toolkit/gc-toolkit.polecat-1", session_name:"s-s4", state:"active", attached:false, created_at:"2026-11-08T09:00:00Z", template:"gc-toolkit/gc-toolkit.polecat"},
    {id:"s5", alias:"gc-toolkit.mechanik", session_name:"gc-toolkit__mechanik", state:"active", attached:true, created_at:"2026-08-31T04:11:47Z", template:"gc-toolkit.mechanik"},
    {id:"s6", alias:"gascity/gc-toolkit.po", session_name:"gascity--gc-toolkit__po", state:"asleep", attached:false, created_at:"2026-11-08T08:00:00Z", template:"gascity/gc-toolkit.po"},
    {id:"s7", alias:"docs/gc-toolkit.po", session_name:"docs--gc-toolkit__po", state:"closed", attached:false, created_at:"2026-11-07T08:00:00Z", template:"docs/gc-toolkit.po"},
    {id:"s8", alias:"gc-toolkit/gc-toolkit.po", session_name:"gc-toolkit--gc-toolkit__po", state:"asleep", closed:true, attached:false, created_at:"2026-11-07T09:00:00Z", template:"gc-toolkit/gc-toolkit.po"}]}' > "$STATE/sessions.json"
  jq -n '[
    {id:"tk-subj", issue_type:"task", status:"open", title:"the subject"},
    {id:"tk-shut", issue_type:"task", status:"closed", title:"a closed subject"},
    {id:"tk-ready", issue_type:"task", status:"in_progress", assignee:"gc-toolkit/gc-toolkit.tk-ready", title:"ready one", created_at:"2026-11-08T09:59:00Z",
     metadata:{"gc.handback_at":"2026-11-08T10:05:00Z"}, dependencies:[{type:"tracks", depends_on_id:"tk-subj"}]},
    {id:"tk-prep", issue_type:"task", status:"in_progress", assignee:"gc-toolkit/gc-toolkit.tk-prep", title:"preparing one",
     metadata:{"gc.handback_at":"2026-11-08T10:30:00Z"}, dependencies:[{type:"tracks", depends_on_id:"tk-subj"}]},
    {id:"tk-bound", issue_type:"task", status:"open", assignee:"gc-toolkit/gc-toolkit.tk-bound", title:"starting one", dependencies:[{type:"tracks", depends_on_id:"tk-subj"}]},
    {id:"tk-left", issue_type:"task", status:"in_progress", assignee:"gc-toolkit/gc-toolkit.tk-left", title:"ended one", dependencies:[{type:"tracks", depends_on_id:"tk-subj"}]},
    {id:"tk-queue", issue_type:"task", status:"open", assignee:"human", title:"queued one", dependencies:[{type:"tracks", depends_on_id:"tk-subj"}]},
    {id:"tk-work", issue_type:"task", status:"in_progress", assignee:"gc-toolkit/gc-toolkit.polecat-1", title:"a step, not a conversation", dependencies:[{type:"tracks", depends_on_id:"tk-subj"}]},
    {id:"tk-shutconv", issue_type:"task", status:"closed", assignee:"gc-toolkit/gc-toolkit.tk-shutconv", title:"closed conversation", closed_at:"2026-11-07T10:00:00Z", dependencies:[{type:"tracks", depends_on_id:"tk-subj"}]},
    {id:"tk-gate", issue_type:"gate", await_type:"human", status:"open", title:"approve it"},
    {id:"tk-held", issue_type:"task", status:"open", title:"held bead", dependencies:[{type:"blocks", depends_on_id:"tk-gate"}]},
    {id:"tk-a1", issue_type:"task", status:"open", title:"anchor one", metadata:{pr_number:"77"}},
    {id:"tk-a2", issue_type:"task", status:"open", title:"anchor two", metadata:{pr_number:"88"}}]' > "$STATE/tk.json"
  jq -n '[{id:"gc-b1", issue_type:"task", status:"open", title:"other repo anchor", metadata:{pr_number:"77"}},
          {id:"gc-q", issue_type:"task", status:"open", assignee:"human", title:"gascity queued", dependencies:[{type:"tracks", depends_on_id:"gc-b1"}]}]' > "$STATE/gc.json"
  jq -n '[{id:"dx-1", issue_type:"task", status:"open", title:"docs bead"}]' > "$STATE/dx.json"
}
run() { set +e; OUT="$(sh "$SCRIPT" "$@" 2>"$TMP/err")"; RC=$?; set -e; ERR="$(cat "$TMP/err")"; }
row() { printf '%s' "$OUT" | jq -c --arg i "$1" '.conversations[] | select(.id == $i)'; }
field() { printf '%s' "$OUT" | jq -r --arg i "$1" ".conversations[] | select(.id == \$i) | $2"; }

echo "# conversations: every open conversation in the city, with its readiness"
seed; run conversations --json
eq "$RC" 0 "(CITY) the list exits 0"
eq "$(field tk-ready .readiness)" "ready" "(CITY) a hand-back since its session started reads ready"
eq "$(field tk-ready .session.attached)" "false" "(CITY) …with no terminal attached"
eq "$(field tk-ready .subject_title)" "the subject" "(CITY) …carrying its subject's title"
eq "$(field tk-prep .readiness)" "preparing" "(CITY) a hand-back older than its session reads preparing"
eq "$(field tk-prep .session.attached)" "true" "(CITY) …and says a terminal is attached"
eq "$(field tk-bound .readiness)" "starting" "(CITY) a bound conversation whose session has not started reads starting"
eq "$(field tk-left .readiness)" "ended" "(CITY) one whose session closed reads ended"
eq "$(field tk-left .state)" "left" "(CITY) …in engage's state left"
eq "$(field tk-queue .readiness)" "queued" "(CITY) one in the queue reads queued"
eq "$(field gc-q .rig)" "gascity" "(CITY) a suspended rig's conversations are listed with their rig"
eq "$(row tk-work)" "" "(CITY) a task held by a session that does not name it is no conversation"
eq "$(row tk-shutconv)" "" "(CITY) a closed conversation is not listed"
eq "$(printf '%s' "$OUT" | jq -c '[.rigs[] | [.name, .converse, .suspended]]')" '[["gc-toolkit",true,false],["gascity",true,true],["docs",false,false]]' "(CITY) the rigs a new topic can go to, but the city's own store, with converse and suspension"
eq "$(printf '%s' "$OUT" | jq -c '[.rigs[] | .prefix]')" '["tk","gc","dx"]' "(CITY) …each with its prefix, so the form can match one typed by it"
eq "$(printf '%s' "$OUT" | jq -c '.unread')" '[]' "(CITY) …and no store unread"
eq "$(printf '%s' "$OUT" | jq -c '[.seats[] | [.seat, .rig, (.session | if . == null then null else [.id, .state, .attached] end)]]')" \
  '[["mechanik","",["s5","active",true]],["po","gc-toolkit",null],["po","gascity",["s6","asleep",false]],["po","docs",null]]' \
  "(CITY-SEATS) mechanik, then each rig's po but the city's own store's, each with its open session or none, a closed one by its flag or its state counting as none"
eq "$(printf '%s' "$OUT" | jq -c '.seats[0].session | {name, created_at}')" '{"name":"gc-toolkit__mechanik","created_at":"2026-08-31T04:11:47Z"}' "(CITY-SEATS) …a session with its name and when it was created"
eq "$(grep -c '^session list' "$CALLS")" 1 "(CITY-SEATS) …from the one session list the conversations were read from"
eq "$(grep -c '^agent list' "$CALLS")" 1 "(CITY-SEATS) …and their names from the one agent roster the rigs' converse was read from"
eq "$(printf '%s' "$OUT" | jq -c '.roster_unread')" false "(CITY-SEATS) …which read"

echo "# a city that imports the pack under another name lists the same seats, under the names it gives them"
seed
jq '.agents |= map(.qualified_name |= sub("gc-toolkit\\.(?<t>mechanik|po)$"; "kit.\(.t)"))' "$STATE/agents.json" > "$STATE/tmp.json" && mv "$STATE/tmp.json" "$STATE/agents.json"
jq '.sessions |= map(if .id == "s5" or .id == "s6" then .alias |= sub("gc-toolkit\\."; "kit.") else . end)
    | .sessions += [{id:"s9", alias:"docs/gc-toolkit.po", session_name:"docs--gc-toolkit__po", state:"active", attached:false, created_at:"2026-11-09T08:00:00Z", template:"docs/gc-toolkit.po"}]' \
  "$STATE/sessions.json" > "$STATE/tmp.json" && mv "$STATE/tmp.json" "$STATE/sessions.json"
run conversations --json
eq "$RC" 0 "(CITY-SEATS-KIT) the list exits 0 under a city that imports the pack as kit"
eq "$(printf '%s' "$OUT" | jq -c '[.seats[] | [.seat, .rig, (.session | if . == null then null else [.id, .state, .attached] end)]]')" \
  '[["mechanik","",["s5","active",true]],["po","gc-toolkit",null],["po","gascity",["s6","asleep",false]],["po","docs",null]]' \
  "(CITY-SEATS-KIT) …each seat with its session under kit's name, docs' open session under gc-toolkit's name being no seat's"

echo "# a seat the roster gives no one name is left out"
seed
jq '.agents |= (map(select(.name != "mechanik" and .dir != "docs")) + [{name:"po", dir:"gascity", qualified_name:"gascity/kit.po", scope:"rig"}])' "$STATE/agents.json" > "$STATE/tmp.json" && mv "$STATE/tmp.json" "$STATE/agents.json"
run conversations --json
eq "$RC" 0 "(CITY-SEATS-NAME) the list exits 0"
eq "$(printf '%s' "$OUT" | jq -c '[.seats[] | [.seat, .rig]]')" '[["po","gc-toolkit"]]' \
  "(CITY-SEATS-NAME) mechanik and docs' po, which the roster names no agent for, and gascity's po, which it names two for, are left out"

echo "# a roster that cannot be read lists no seat, and the rest as it otherwise would"
seed; run conversations --json; READ_OUT="$OUT"
printf 'gc: warming up\n' > "$STATE/agents.json"
run conversations --json
eq "$RC" 4 "(CITY-SEATS-ROSTER) a roster that cannot be read exits 4"
has "$ERR" "could not read 'gc agent list', which gives each seat's session its name, so no seat is listed." "(CITY-SEATS-ROSTER) …saying so"
eq "$(printf '%s' "$OUT" | jq -c '[.seats, .roster_unread]')" '[[],true]' "(CITY-SEATS-ROSTER) …listing no seat, and saying the roster did not read"
eq "$(printf '%s' "$OUT" | jq -c '[.conversations, .unread]')" "$(printf '%s' "$READ_OUT" | jq -c '[.conversations, .unread]')" \
  "(CITY-SEATS-ROSTER) …and listing the conversations and the unread stores as a roster that reads lists them"
eq "$(field tk-ready .readiness)" "ready" "(CITY-SEATS-ROSTER) …a hand-back since its session started still reading ready"
eq "$(printf '%s' "$OUT" | jq -c '[.rigs[] | [.name, .prefix, .suspended]]')" '[["gc-toolkit","tk",false],["gascity","gc",true],["docs","dx",false]]' \
  "(CITY-SEATS-ROSTER) …and the rigs a new topic can go to"
run conversations
eq "$RC" 0 "(CITY-SEATS-ROSTER) the list without --json, which shows no seat, still lists"

echo "# a bound conversation whose sitting ended before it claimed it is still listed"
seed; jq '.sessions |= map(select(.id != "s3"))' "$STATE/sessions.json" > "$STATE/tmp.json" && mv "$STATE/tmp.json" "$STATE/sessions.json"
run conversations --json
eq "$RC" 0 "(CITY-ENDED) the list exits 0"
eq "$(field tk-bound .readiness)" "ended" "(CITY-ENDED) an open conversation bound to a sitting that is gone reads ended"
eq "$(field tk-bound .state)" "left" "(CITY-ENDED) …in engage's state left"
run conversations tk-subj --json
eq "$(printf '%s' "$OUT" | jq -r '.conversations[] | select(.id == "tk-bound") | .readiness')" "ended" "(CITY-ENDED) …as conversations <subject> reads it"

echo "# a store that does not answer is named, and the list still prints"
seed; : > "$STATE/gc.unread"; run conversations --json
eq "$RC" 4 "(CITY-UNREAD) an unread store exits 4"
eq "$(printf '%s' "$OUT" | jq -c '.unread')" '["gascity"]' "(CITY-UNREAD) …naming it"
eq "$(field tk-ready .readiness)" "ready" "(CITY-UNREAD) …after listing the stores that answered"

echo "# a rig whose ledger is not there is named as unread"
seed; jq --arg p "$TMP/noledger" '.rigs += [{name:"vanished", path:$p, prefix:"vx", suspended:false}]' "$STATE/rigs.json" > "$STATE/tmp.json" && mv "$STATE/tmp.json" "$STATE/rigs.json"
run conversations --json
eq "$RC" 4 "(CITY-NOLEDGER) a rig with no ledger exits 4"
eq "$(printf '%s' "$OUT" | jq -c '.unread')" '["vanished"]' "(CITY-NOLEDGER) …naming it"
eq "$(field tk-ready .readiness)" "ready" "(CITY-NOLEDGER) …after listing the stores that answered"
hasnt "$(cat "$CALLS")" "$TMP/noledger" "(CITY-NOLEDGER) …and no read is made against it"
run conversations
has "$ERR" "the store of vanished could not be read" "(CITY-NOLEDGER) without --json, stderr names it"

echo "# the list never reads as complete when its scratch files fail"
# mktemp makes the city list's scratch directory, then makes each name in
# $SPOIL_DIRS a directory there, so a write to it fails, and links each name in
# $SPOIL_NULL to /dev/null, so a write to it succeeds and keeps nothing. The
# rigs are numbered in the order the city lists them: gascity is 2 and
# gc-toolkit is 1. The cases make their scratch under $SCRATCH, which each leaves
# empty.
SCRATCH="$TMP/scratch"; mkdir -p "$SCRATCH"
REAL_MKTEMP="$(command -v mktemp)"
cat > "$TMP/bin/mktemp" <<MKTEMP
#!/bin/sh
d=\$("$REAL_MKTEMP" "\$@") || exit \$?
case "\$*" in *gc-helm-conversations*)
  for n in \${SPOIL_DIRS:-}; do mkdir "\$d/\$n"; done
  for n in \${SPOIL_NULL:-}; do ln -s /dev/null "\$d/\$n"; done ;;
esac
printf '%s\n' "\$d"
MKTEMP
chmod +x "$TMP/bin/mktemp"
seed; : > "$STATE/gc.unread"; TMPDIR="$SCRATCH" SPOIL_DIRS="2.unread" run conversations --json
eq "$RC" 4 "(CITY-SCRATCH) a store whose read failed exits 4 when no marker of its failure can be written"
eq "$(printf '%s' "$OUT" | jq -c '.unread')" '["gascity"]' "(CITY-SCRATCH) …naming it"
eq "$(field tk-ready .readiness)" "ready" "(CITY-SCRATCH) …after listing the stores that answered"
seed; TMPDIR="$SCRATCH" SPOIL_DIRS="2.done" run conversations --json
eq "$RC" 4 "(CITY-SCRATCH) a store whose list was not marked done exits 4"
eq "$(printf '%s' "$OUT" | jq -c '.unread')" '["gascity"]' "(CITY-SCRATCH) …naming it"
eq "$(row gc-q)" "" "(CITY-SCRATCH) …and lists none of its conversations"
seed; TMPDIR="$SCRATCH" SPOIL_DIRS="rigs" run conversations --json
eq "$RC" 3 "(CITY-SCRATCH) a rig list that cannot be written exits 3"
eq "$OUT" "" "(CITY-SCRATCH) …listing nothing"
has "$ERR" "could not write the list of rigs" "(CITY-SCRATCH) …and says so"
seed; TMPDIR="$SCRATCH" SPOIL_NULL="1.json" run conversations --json
eq "$RC" 4 "(CITY-SCRATCH) a list that holds nothing although its store answered exits 4"
eq "$OUT" "" "(CITY-SCRATCH) …listing nothing"
has "$ERR" "could not be put together" "(CITY-SCRATCH) …and says so"
eq "$(find "$SCRATCH" -mindepth 1 -maxdepth 1 -name 'gc-helm-conversations.*' | head -1)" "" "(CITY-SCRATCH) …and no case leaves its scratch directory behind"
rm -f "$TMP/bin/mktemp"

echo "# without --json, one line per conversation"
seed; run conversations
eq "$RC" 0 "(CITY-TEXT) the text list exits 0"
has "$OUT" "$(printf 'ready\ttk-ready\tgc-toolkit\tready one')" "(CITY-TEXT) a row reads readiness, id, rig and title"
has "$OUT" "preparing (attached)" "(CITY-TEXT) …and an attached sitting says so"

echo "# conversations <ref>: the subject engage would hold a conversation about"
seed; run conversations tk-subj --json
eq "$RC" 0 "(ABOUT) a subject exits 0"
eq "$(printf '%s' "$OUT" | jq -r '.subject.id + " " + .subject.rig')" "tk-subj gc-toolkit" "(ABOUT) …naming the subject and its rig"
eq "$(printf '%s' "$OUT" | jq -r '.refusal')" "" "(ABOUT) …where a sitting can start"
eq "$(printf '%s' "$OUT" | jq -c '[.conversations[].id] | sort')" '["tk-bound","tk-left","tk-prep","tk-queue","tk-ready"]' "(ABOUT) …with its open conversations"
eq "$(printf '%s' "$OUT" | jq -r '.holds_read')" "true" "(ABOUT) …and what holds it read"
seed; GCTK_REASONS='[{"held":"gate","id":"tk-gate","title":"approve it"}]' run conversations tk-subj --json
eq "$(printf '%s' "$OUT" | jq -c '.holds')" '[{"held":"gate","id":"tk-gate","title":"approve it"}]' "(ABOUT) a gate that holds it is named"
seed; run conversations tk-ready --json
eq "$(printf '%s' "$OUT" | jq -r '.subject.id + " " + .conversation')" "tk-subj tk-ready" "(ABOUT) a conversation id names its subject and itself"
seed; run conversations tk-shutconv --json
eq "$(printf '%s' "$OUT" | jq -r '.closed.id')" "tk-shutconv" "(ABOUT) a closed conversation is said to be closed"
has "$(printf '%s' "$OUT" | jq -r '.closed.said')" "closed at 2026-11-07T10:00:00Z" "(ABOUT) …and when"
seed; run conversations tk-gate --json
eq "$(printf '%s' "$OUT" | jq -r '.subject.id + " " + .gate')" "tk-held tk-gate" "(ABOUT) a gate names the bead waiting on it, and itself"

echo "# a gate two beads wait on is about the bead it was reached from, and read from nothing, the one whose wait on it is oldest"
# tk-held2's edge onto the gate is the older one, though its id sorts after tk-held's.
edges() { jq "$1" "$STATE/tk.json" > "$STATE/tmp.json" && mv "$STATE/tmp.json" "$STATE/tk.json"; }
seed; edges '[ .[] | if .id == "tk-held" then .dependencies = [{type:"blocks", depends_on_id:"tk-gate", created_at:"2026-11-02T09:00:00Z"}] else . end ]
    + [{id:"tk-held2", issue_type:"task", status:"open", title:"second held bead", dependencies:[{type:"blocks", depends_on_id:"tk-gate", created_at:"2026-11-01T09:00:00Z"}]}]'
run conversations tk-gate --from tk-held --json
eq "$RC" 0 "(ABOUT-FROM) a gate two beads wait on, read --from one of them, exits 0"
eq "$(printf '%s' "$OUT" | jq -r '.subject.id + " " + .gate')" "tk-held tk-gate" "(ABOUT-FROM) …naming that bead, and the gate, though the other has waited on it longer"
run conversations tk-gate --json
eq "$RC" 0 "(ABOUT-FROM) read from nothing, it exits 0"
eq "$(printf '%s' "$OUT" | jq -r '.subject.id + " " + .gate')" "tk-held2 tk-gate" "(ABOUT-FROM) …naming the bead whose wait on it is oldest, and the gate"
run conversations tk-gate --json
eq "$(printf '%s' "$OUT" | jq -r '.subject.id')" "tk-held2" "(ABOUT-FROM) …and the same bead when read again"
run conversations tk-gate --from tk-subj --json
eq "$RC" 4 "(ABOUT-FROM) read --from a bead the gate does not hold, it exits 4"
has "$ERR" "tk-subj does not wait on gate tk-gate now (the beads waiting on it are tk-held tk-held2)" "(ABOUT-FROM) …saying so"
GCTK_REASONS='[{"held":"gate","id":"tk-gate","title":"approve it"}]' run conversations tk-gate --from tk-subj --json
eq "$RC" 0 "(ABOUT-FROM) read --from a bead it holds only through another, it exits 0 while two beads wait on it"
eq "$(printf '%s' "$OUT" | jq -r '.subject.id')" "tk-held2" "(ABOUT-FROM) …naming the bead whose wait is oldest, as without --from"
LIST_ID_FAIL=tk-held2 run conversations tk-gate --json
eq "$RC" 4 "(ABOUT-FROM) a read of the beads' waits that does not answer exits 4"
has "$ERR" "gate tk-gate holds 2 beads (tk-held tk-held2), and when each began waiting on it could not be read" "(ABOUT-FROM) …saying which one cannot be told"
for v in accept dismiss; do
  run "$v" tk-gate
  eq "$RC" 4 "(ABOUT-FROM) $v on a gate two beads wait on exits 4"
  has "$ERR" "gc-helm: $v: gate tk-gate is about 2 beads still waiting on it (tk-held tk-held2), and a conversation is about one bead. Name the one you mean: gc-helm $v <bead>." "(ABOUT-FROM) …refusing it, naming both beads, since $v would act on a bead nobody named"
done
run handback tk-gate <<< "the hand-back"
eq "$RC" 4 "(ABOUT-FROM) handback on a gate two beads wait on exits 4"
has "$ERR" "gc-helm: handback: gate tk-gate is about 2 beads still waiting on it (tk-held tk-held2), and a conversation is about one bead. Name the one you mean: gc-helm handback <bead>. Nothing was recorded." "(ABOUT-FROM) …refusing it, naming both beads"
edges '[ .[] | if .id == "tk-held2" then .dependencies[0].created_at = "2026-11-02T09:00:00Z" else . end ]'
run conversations tk-gate --json
eq "$(printf '%s' "$OUT" | jq -r '.subject.id')" "tk-held" "(ABOUT-FROM) two waits as old as each other leave the bead whose id sorts first"
edges '[ .[] | if .id == "tk-held" then .dependencies[0] |= del(.created_at) else . end ]'
run conversations tk-gate --json
eq "$(printf '%s' "$OUT" | jq -r '.subject.id')" "tk-held2" "(ABOUT-FROM) a wait with no recorded time reads after one with a time"
seed; GCTK_REASONS='[{"held":"gate","id":"tk-gate","title":"approve it"}]' run conversations tk-gate --from tk-subj --json
eq "$(printf '%s' "$OUT" | jq -r '.subject.id + " " + .gate')" "tk-held tk-gate" "(ABOUT-FROM) a gate one bead waits on, holding the --from bead through it, is about that bead, as without --from"
run conversations tk-gate --from tk-subj --json
eq "$RC" 4 "(ABOUT-FROM) a gate that no longer holds the --from bead exits 4, though one bead waits on it"
has "$ERR" "tk-subj does not wait on gate tk-gate now (the beads waiting on it are tk-held)" "(ABOUT-FROM) …so no other bead stands in for it"
run conversations --from tk-held --json
eq "$RC" 2 "(ABOUT-FROM) --from with no reference exits 2"
has "$ERR" "--from names the bead a gate was reached from, so it needs the gate" "(ABOUT-FROM) …saying it needs the gate"

echo "# a subject in a suspended rig is said as suspended, which refuses nothing"
seed; run conversations gc-b1 --json
eq "$RC" 0 "(ABOUT-SUSPENDED) a subject in a suspended rig reads, exit 0"
eq "$(printf '%s' "$OUT" | jq -c '[.rig_suspended, .refusal]')" '[true,""]' "(ABOUT-SUSPENDED) …as rig_suspended, with no refusal"
seed; run conversations tk-subj --json
eq "$(printf '%s' "$OUT" | jq -c '[.rig_suspended, .refusal]')" '[false,""]' "(ABOUT-SUSPENDED) a subject in a rig that runs reads rig_suspended false"
seed; run conversations gc-b1
has "$OUT" "is suspended, and a conversation filed now waits in the queue until it resumes" "(ABOUT-SUSPENDED) the text says a conversation waits until the rig resumes"

echo "# a subject no sitting can start on is said as its refusal"
seed; run conversations dx-1 --json
has "$(printf '%s' "$OUT" | jq -r '.refusal')" "carries no converse template" "(ABOUT-REFUSE) a rig with no converse is said"
seed; run conversations tk-shut --json
has "$(printf '%s' "$OUT" | jq -r '.refusal')" "tk-shut is closed" "(ABOUT-REFUSE) a closed subject is said"
seed; run conversations tk-nope --json
eq "$RC" 4 "(ABOUT-REFUSE) a bead that does not resolve exits 4"
has "$ERR" "bead not found: 'tk-nope'" "(ABOUT-REFUSE) …naming it"

echo "# a PR number two live anchors record is offered as both"
seed; run conversations 77 --json
eq "$RC" 0 "(ABOUT-PR) an ambiguous PR number exits 0"
eq "$(printf '%s' "$OUT" | jq -c '[.candidates[] | [.id, .rig, .title]] | sort')" '[["gc-b1","gascity","other repo anchor"],["tk-a1","gc-toolkit","anchor one"]]' "(ABOUT-PR) …each anchor a candidate, with its rig and title"
seed; run conversations 88 --json
eq "$(printf '%s' "$OUT" | jq -r '.subject.id')" "tk-a2" "(ABOUT-PR) a PR number one anchor records resolves to it"

echo "# open --new-subject: the subject and its conversation, the question unchanged"
Q="$(printf 'Why do sittings start slowly?\n\n  Two lines in,  with spaces  \nand a third line that runs on %s' "$(printf 'y%.0s' $(seq 1 500))")"
seed; run open --new-subject --rig gc-toolkit --reason "$Q" --json
eq "$RC" 0 "(NEWSUBJ) a new subject files, exit 0"
eq "$(printf '%s\n' "$OUT" | tail -n 1)" '{"subject":"tk-newsubj","conversation":"tk-newconv","filed":true}' "(NEWSUBJ) --json's last answer names the subject and its conversation"
eq "$(printf '%s\n' "$OUT" | head -n 1)" '{"subject":"tk-newsubj","conversation":"","filed":false}' "(NEWSUBJ) …after the subject's own answer"
eq "$(cat "$STATE/subj.db")" "$TMP/rig/.beads" "(NEWSUBJ) the subject is filed in the --rig rig's store"
has "$(cat "$STATE/subj.metadata")" '"gc.reaction_owned":"1"' "(NEWSUBJ) …marked reaction-owned"
has "$(cat "$STATE/subj.metadata")" '"gc.origin":"operator"' "(NEWSUBJ) …with the operator as its origin"
case "$(cat "$STATE/subj.description")" in
  "$Q"$'\n\n---\n'*) ok "(NEWSUBJ) the subject's description opens with the question, unchanged" ;;
  *) bad "(NEWSUBJ) the subject's description should open with the question unchanged" ;;
esac
eq "$(cat "$STATE/conv.description")" "$Q" "(NEWSUBJ) the conversation's ask is the question, unchanged"
case "$(cat "$STATE/subj.title")" in
  "Why do sittings start slowly? Two lines in, with spaces and a third line"*"…") ok "(NEWSUBJ) the title is the question's opening on one line, cut with an ellipsis" ;;
  *) bad "(NEWSUBJ) the title should be the opening on one line (got: $(cat "$STATE/subj.title"))" ;;
esac
eq "$(cat "$STATE/conv.title")" "$(cat "$STATE/subj.title")" "(NEWSUBJ) …and the conversation carries the same title"

echo "# the subject is answered the moment it is filed, before open reads anything after it"
seed; set +e
ANSWER_FILE="$TMP/open.out" sh "$SCRIPT" open --new-subject --rig gc-toolkit --reason "a question" --json > "$TMP/open.out" 2>"$TMP/err"
RC=$?; set -e
eq "$RC" 0 "(NEWSUBJ-EARLY) the open exits 0"
eq "$(cat "$STATE/answer.at-next-call" 2>/dev/null)" '{"subject":"tk-newsubj","conversation":"","filed":false}' "(NEWSUBJ-EARLY) the subject's answer is on stdout before open's next call"
eq "$(tail -n 1 "$TMP/open.out")" '{"subject":"tk-newsubj","conversation":"tk-newconv","filed":true}' "(NEWSUBJ-EARLY) …and the answer open ends with comes last"

echo "# a subject filed whose conversation is not is named for a re-run onto it"
seed; CONV_CREATE_FAIL=1 run open --new-subject --rig gc-toolkit --reason "a question" --json
eq "$RC" 4 "(NEWSUBJ-PART) a conversation that is not filed exits 4"
eq "$(printf '%s\n' "$OUT" | tail -n 1)" '{"subject":"tk-newsubj","conversation":"","filed":false}' "(NEWSUBJ-PART) --json's last answer names the subject that was filed"
has "$ERR" "subject tk-newsubj was filed, but its conversation was not" "(NEWSUBJ-PART) …and so does stderr"
has "$ERR" "gc-helm open tk-newsubj --reason" "(NEWSUBJ-PART) …with the re-run onto it"

echo "# the rig of a new subject is the operator's, and is checked before anything is created"
seed; run open --new-subject --reason "q" --json
eq "$RC" 2 "(NEWSUBJ-RIG) no --rig exits 2"
has "$ERR" "it is never inferred" "(NEWSUBJ-RIG) …saying the rig is never guessed"
seed; run open --new-subject --rig nowhere --reason "q"
eq "$RC" 4 "(NEWSUBJ-RIG) an unknown rig exits 4"
seed; run open --new-subject --rig docs --reason "q"
eq "$RC" 4 "(NEWSUBJ-RIG) a rig with no converse exits 4"
has "$ERR" "carries no converse template" "(NEWSUBJ-RIG) …saying why"
hasnt "$(cat "$CALLS")" "bd create" "(NEWSUBJ-RIG) …and nothing was created"
seed; run open tk-subj --rig gc-toolkit --reason "q"
eq "$RC" 2 "(NEWSUBJ-RIG) --rig without --new-subject exits 2"
has "$ERR" "applies only with --new-subject" "(NEWSUBJ-RIG) …saying why"

echo
echo "gc-helm conversations: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
