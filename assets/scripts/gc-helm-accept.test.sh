#!/usr/bin/env bash
# Hermetic test for the gc-helm `accept` verb: Accept clears the
# recommendation's human gate and nothing else, under the bead's acceptance
# lock, and dispatches the recommendation once.
#
# A recommendation is gc.recommended_formula on a bead, put to the operator by
# the open human gate under the key first-reaction that blocks the bead. Accept
# is offered while the bead carries the recommendation, that gate is open and
# unassigned (or closed with an acceptance an earlier Accept did not finish),
# and no other open human gate blocks the bead. Every run holds the bead's
# acceptance lock, a flock under <city>/.gc/runtime/packs/gc-toolkit, from
# before its live read to its last write. On an open gate it resolves the gate
# with `ruled: accepted <formula> accept:<token>`, reads its own answer back,
# reads back that no open human gate blocks the bead, releases a bead that
# reads held to unanchored, slings the formula titled
# `<formula> accept:<token>`, and records the dispatch. A run that finds the
# gate closed with an Accept's answer beside the recommendation finishes that
# acceptance under its token.
#
# Covered (specs/tk-0ur8r9p/design.md section 12, unit C's acceptance case and
# its fixtures):
#   (STALE)    a recommendation beside a review gate: Accept refuses and names
#              the review gate, writing nothing
#   (ACCEPT)   with the recommendation's gate the last one open, Accept records
#              the acceptance's dispatch input on the gate, answers the gate
#              alone, slings with the token in the root's title and records
#   (LATE)     a gate filed after the live read stops the dispatch and reopens
#              the recommendation's gate
#   (EARLIER)  a sitting's answer that reaches the gate first stands: nothing is
#              slung or reopened, and the declined gate leaves nothing to finish
#   (OTHER-BEAD) a gate filed on another bead that the bead waits on withholds
#              Accept the same way
#   (LIVE-SITTING) a live sitting replying to the recommendation's gate is
#              warned about, and Accept clears the gate
#   (PARENT)   a recommendation on a bead with an open child is accepted as on
#              any bead
#   (HELD, HELD-FAIL, HELD-FINISH) a bead a sitting's hold left at held is
#              released to unanchored after Accept's answer and before its
#              sling; a release that does not land slings nothing and leaves the
#              acceptance for the next Accept, which releases and slings once
#   (STOP-*)   an Accept stopped after its resolve, before its sling, or after
#              its sling leaves the gate answered, the recommendation in place
#              and the lock free, and the next Accept finishes it once
#   (HOLD-*)   a gate filed after the stop holds the finish
#   (RACE-*)   two runs on one acceptance pour once: the second refuses at the
#              lock and names the first
#   (LINGER, NO-CITY, NO-FLOCK) the lock outlives no run, and a run that cannot
#              take it refuses
#   (SELF-KILL) a run killed by itself keeps the lock until its sling exits
#   (OUTLIVE)  a sling that outlives the lock meets Gas City's launch lock
#   (SLING-*)  a failed sling is judged by the token's root
#   (VAR-*)    each --var rides the sling as given and is recorded on the gate
#              before the resolve; a finish slings the recorded vars, refuses a
#              --var that differs from them and an acceptance that records none;
#              a root already poured keeps its own vars; and a --var that is not
#              <key>=<value> is refused
#   (SITTING-*) a sitting's sign-off takes the recommendation through this
#              same writer (converse-signoff.sh --accept), so the board's Accept
#              and the sitting dispatch it once between them, whichever runs
#              first, stops part way, or holds the lock, and a var the
#              sitting's ruling settled rides Accept's sling, also when the
#              board's Accept finishes a take that stopped after its resolve;
#              a held subject is released before Accept's sling at a sign-off,
#              by the sign-off, and on a turn that does not sign off, by Accept
#
# Runs the REAL gc-helm.sh (as `sh`, as shipped) with a stubbed `gc` on PATH
# over a file-backed store: no live city, Dolt, network or sessions. The stub's
# sling behaves as Gas City's does: under a per-bead launch lock it refuses a
# second launch of the formula at the bead, exiting 3, only while an earlier
# root is live, and pours again once that root has closed.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/gc-helm.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-gc-helm-accept-test.XXXXXX")"
cleanup() {
    if [ -s "$TMP/lingerers" ]; then
        while read -r _p; do kill "$_p" 2>/dev/null || true; done < "$TMP/lingerers"
    fi
    rm -rf "$TMP"
}
trap cleanup EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 (unexpected '$2' in: $1)" ;; *) ok "$3" ;; esac; }

[ -f "$SCRIPT" ] && ok "gc-helm.sh present" || bad "gc-helm.sh missing at $SCRIPT"
command -v flock >/dev/null 2>&1 || { echo "FAIL - flock is not on PATH; Accept's lock needs it"; exit 1; }

mkdir -p "$TMP/bin" "$TMP/store/b" "$TMP/city/.gc"

# --- gc stub ------------------------------------------------------------------
# The store is one JSON file per bead under $STORE/b/<id>.json, with its edges
# as deps [{type, on}] on the bead the edge starts from: a bead's `blocks` edge
# onto a gate, a conversation's `tracks` edge onto its bead and `replies-to`
# edge onto a gate. Roots the sling pours are beads too, with `at` and
# `formula`. Every write takes $STORE/lock, so concurrent runs see one store.
# Every write and every sling is appended to $CALLS; reads are not.
#
# Hooks a case sets in a run's environment:
#   STOP_AT=resolve|sling|after-sling  kill the run (its gc-helm.sh process and
#        the subshells between) after the gate resolve, at the sling before it
#        does anything, or after the sling has poured
#   LATE_GATE_ON_RESOLVE=<gate>  file that open human gate on the bead first,
#        inside the resolve call: a gate filed between the live read and the
#        resolve
#   LATE_GATE_ON_SEARCH=<gate>   file it inside the token search: between a
#        finishing run's live read and its step 3
#   EARLIER_ANSWER=<reason>      a sitting's answer that reaches the gate inside
#        the resolve call, before Accept's own
#   SLING_FAIL=committed|partial|plain  the sling exits 1 after a committed pour,
#        after a pour that failed part way (a closed root marked
#        molecule_failed), or having poured nothing
#   SLING_PAUSE=<dir>    at the sling, touch <dir>/arrived and wait for <dir>/go
#   SLING_HOLD_AFTER_POUR=<dir>  pour, touch <dir>/poured, wait for <dir>/go
#   SLING_HOLD_BEFORE_POUR=<dir> take the launch lock, write the run's pids to
#        <dir>/pids, touch <dir>/locked, wait for <dir>/go, then pour
#   SLING_LINGER=1       leave a process running after the sling exits
#   SHOW_DOWN=1          every `bd show` fails, as a data plane that is down
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
ST="$STORE"
B="$ST/b"
lock()   { _t=0; until mkdir "$ST/lock" 2>/dev/null; do sleep 0.02; _t=$((_t + 1)); [ "$_t" -lt 3000 ] || break; done; }
unlock() { rmdir "$ST/lock" 2>/dev/null || true; }
now()    { date -u +%Y-%m-%dT%H:%M:%SZ; }
row()    { cat "$B/$1.json" 2>/dev/null; }
put()    { cat > "$B/$1.json.tmp" && mv "$B/$1.json.tmp" "$B/$1.json"; }
log()    { printf '%s\n' "$*" >> "$CALLS"; }
# kill_run — stop the Accept that called this stub, as a killed process group
# or a host that went down stops it: walk up from the subshell that ran the
# stub through every gc-helm.sh process (a forked subshell carries its parent's
# command line) and kill each.
kill_run() {
  _p=$PPID; _kill=""; _i=0
  while [ -n "$_p" ] && [ "$_p" -gt 1 ] && [ "$_i" -lt 8 ]; do
    case "$(ps -o args= -p "$_p" 2>/dev/null)" in
      *gc-helm.sh*) _kill="$_kill $_p" ;;
      *) break ;;
    esac
    _p=$(ps -o ppid= -p "$_p" 2>/dev/null | tr -d ' '); _i=$((_i + 1))
  done
  # shellcheck disable=SC2086
  kill -9 $_kill 2>/dev/null || true
  exit 0
}
wait_for() { _i=0; until [ -e "$1" ]; do sleep 0.05; _i=$((_i + 1)); [ "$_i" -lt 1200 ] || break; done; }
# file_gate <gate> — an open human gate blocking $BEAD (the bead the run is on).
file_gate() {
  jq -n --arg g "$1" --arg t "$(now)" '{id:$g, title:("A late question " + $g), status:"open", issue_type:"gate",
        await_type:"human", await_id:"late", assignee:"", created_at:$t, updated_at:$t, metadata:{}, deps:[]}' | put "$1"
  row "$ACC_BEAD" | jq --arg g "$1" '.deps += [{type:"blocks", on:$g}]' | put "$ACC_BEAD"
}
# show_row <id> / list_row <id> — a bead as `gc bd show` / `gc bd list` spell it.
show_row() { row "$1" | jq -c '. + {dependencies: [ .deps[] | {id: .on, dependency_type: .type} ]} | del(.deps)'; }
list_row() { row "$1" | jq -c '. + {dependencies: [ .deps[] as $d | {issue_id: .id, depends_on_id: $d.on, type: $d.type} ]} | del(.deps)'; }
all_ids()  { for f in "$B"/*.json; do [ -f "$f" ] && basename "$f" .json; done; }

case "$1 ${2:-}" in
  "rig list")
    jq -n --arg city "$CITY_ROOT" '{rigs:[{name:"mycity", path:$city, prefix:"hq", hq:true},
                                          {name:"gc-toolkit", path:"/nonexistent-rig", prefix:"tk", hq:false}]}' ;;
  "session list")
    jq -n --slurpfile s "$ST/sessions.json" '{sessions: $s[0]}' ;;
  "bd show")
    [ -n "${SHOW_DOWN:-}" ] && { echo "bd show: data plane down" >&2; exit 1; }
    if [ -f "$B/$3.json" ]; then jq -c -n --argjson r "$(show_row "$3")" '[$r]'
    else printf '{"error":"no issues found matching the provided IDs"}\n'; exit 1; fi ;;
  "bd list")
    _id=""; _tc=""; _p=""
    for a in "$@"; do
      case "$_p" in --id) _id="$a" ;; --title-contains) _tc="$a" ;; esac; _p="$a"
    done
    if [ -n "$_id" ]; then
      [ -f "$B/$_id.json" ] && jq -c -n --argjson r "$(list_row "$_id")" '[$r]' || printf '[]\n'
    elif [ -n "$_tc" ]; then
      if [ -n "${LATE_GATE_ON_SEARCH:-}" ] && [ ! -f "$B/$LATE_GATE_ON_SEARCH.json" ]; then
        lock; file_gate "$LATE_GATE_ON_SEARCH"; log "late gate $LATE_GATE_ON_SEARCH"; unlock
      fi
      for i in $(all_ids); do list_row "$i"; done | jq -sc --arg t "$_tc" '[ .[] | select((.title // "") | contains($t)) ]'
    else printf '[]\n'; fi ;;
  "bd dep")
    case "$3" in
      list)
        _who="$4"; _up=0; _ty=""; _p=""
        for a in "$@"; do
          case "$a" in --direction=up) _up=1 ;; esac
          [ "$_p" = "--type" ] && _ty="$a"; _p="$a"
        done
        [ -f "$B/$_who.json" ] || { echo "bd dep list: no issue $_who" >&2; exit 1; }
        if [ "$_up" = 1 ]; then
          for i in $(all_ids); do
            row "$i" | jq -c --arg w "$_who" --arg t "$_ty" 'select(any(.deps[]; .type == $t and .on == $w))
              | . + {dependency_type: $t} | del(.deps)'
          done | jq -sc '.'
        else
          for o in $(row "$_who" | jq -r --arg t "$_ty" '.deps[] | select(.type == $t) | .on'); do
            row "$o" | jq -c --arg t "$_ty" '. + {dependency_type: $t} | del(.deps)'
          done | jq -sc '.'
        fi ;;
      *) log "bd dep $*" ;;
    esac ;;
  "bd gate")
    # bd resolves a closed gate without changing it, and reports success either way.
    _g="$4"; _r=""; _p=""
    for a in "$@"; do [ "$_p" = "--reason" ] && _r="$a"; _p="$a"; done
    lock
    if [ -n "${LATE_GATE_ON_RESOLVE:-}" ] && [ ! -f "$B/$LATE_GATE_ON_RESOLVE.json" ]; then
      file_gate "$LATE_GATE_ON_RESOLVE"; log "late gate $LATE_GATE_ON_RESOLVE"
    fi
    if [ -n "${EARLIER_ANSWER:-}" ] && [ "$(row "$_g" | jq -r .status)" != closed ]; then
      row "$_g" | jq --arg r "$EARLIER_ANSWER" --arg t "$(now)" '.status = "closed" | .close_reason = $r | .closed_at = $t' | put "$_g"
      log "sitting resolve $_g $EARLIER_ANSWER"
    fi
    log "bd gate resolve $_g $_r"
    if [ "$(row "$_g" | jq -r .status)" != closed ]; then
      row "$_g" | jq --arg r "$_r" --arg t "$(now)" '.status = "closed" | .close_reason = $r | .closed_at = $t' | put "$_g"
    fi
    unlock
    [ "${STOP_AT:-}" = resolve ] && kill_run
    exit 0 ;;
  "bd reopen")
    _g="$3"; lock; log "bd reopen $_g"
    row "$_g" | jq '.status = "open" | del(.close_reason) | del(.closed_at)' | put "$_g"; unlock ;;
  "bd update")
    _id="$3"; shift 3; lock; log "bd update $_id $*"
    _r=$(row "$_id")
    while [ $# -gt 0 ]; do
      case "$1" in
        --set-metadata)   _k="${2%%=*}"; _v="${2#*=}"; _r=$(printf '%s' "$_r" | jq --arg k "$_k" --arg v "$_v" '.metadata[$k] = $v'); shift 2 ;;
        --unset-metadata) _r=$(printf '%s' "$_r" | jq --arg k "$2" 'del(.metadata[$k])'); shift 2 ;;
        --append-notes)   _r=$(printf '%s' "$_r" | jq --arg n "$2" '.notes = ((.notes // "") + (if (.notes // "") == "" then "" else "\n" end) + $n)'); shift 2 ;;
        *) shift ;;
      esac
    done
    printf '%s' "$_r" | put "$_id"; unlock ;;
  "bd close")
    _id="$3"; lock; log "bd close $*"
    [ -f "$B/$_id.json" ] && row "$_id" | jq '.status = "closed"' | put "$_id"
    unlock ;;
  "sling "*|"sling")
    _bead=""; _formula=""; _title=""; _p=""; _var=""
    for a in "$@"; do
      case "$_p" in --on) _formula="$a" ;; --title) _title="$a" ;; --var) _var="$_var --var $a" ;; esac
      case "$a" in tk-*) [ "$_p" = "--rig" ] || _bead="$a" ;; esac
      _p="$a"
    done
    log "sling $_bead --on $_formula --title $_title$_var"
    if [ -n "${SLING_PAUSE:-}" ]; then touch "$SLING_PAUSE/arrived"; wait_for "$SLING_PAUSE/go"; fi
    [ "${STOP_AT:-}" = sling ] && kill_run
    # Gas City's per-bead launch lock, held across processes.
    _w=0
    until mkdir "$ST/launch-$_bead" 2>/dev/null; do
      [ "$_w" = 0 ] && : > "$ST/launch-waiting.$$"; _w=1; sleep 0.05
    done
    if [ -n "${SLING_HOLD_BEFORE_POUR:-}" ]; then
      _sub=$PPID; _main=$(ps -o ppid= -p "$_sub" 2>/dev/null | tr -d ' ')
      printf '%s %s\n' "$_main" "$_sub" > "$SLING_HOLD_BEFORE_POUR/pids"
      touch "$SLING_HOLD_BEFORE_POUR/locked"; wait_for "$SLING_HOLD_BEFORE_POUR/go"
    fi
    lock
    _live=$(for i in $(all_ids); do row "$i"; done | jq -sr --arg b "$_bead" --arg f "$_formula" \
      '[ .[] | select(.at == $b and .formula == $f and .status != "closed") | .id ] | first // empty')
    if [ -n "$_live" ]; then
      unlock; rmdir "$ST/launch-$_bead"
      log "sling refused $_bead: $_live live"
      echo "gc sling: $_formula already has a live root $_live at $_bead" >&2; exit 3
    fi
    if [ "${SLING_FAIL:-}" = plain ]; then unlock; rmdir "$ST/launch-$_bead"; echo "gc sling: pour failed" >&2; exit 1; fi
    _n=$(( $(cat "$ST/root-seq" 2>/dev/null || echo 0) + 1 )); printf '%s' "$_n" > "$ST/root-seq"
    _root="tk-root$_n"
    jq -n --arg id "$_root" --arg t "$_title" --arg b "$_bead" --arg f "$_formula" --arg ts "$(now)" --arg fail "${SLING_FAIL:-}" \
      '{id:$id, title:$t, status:(if $fail == "partial" then "closed" else "open" end), issue_type:"molecule",
        assignee:"", created_at:$ts, updated_at:$ts, at:$b, formula:$f,
        metadata:(if $fail == "partial" then {molecule_failed:"true"} else {} end), deps:[]}' | put "$_root"
    log "poured $_root $_title"
    unlock; rmdir "$ST/launch-$_bead"
    if [ -n "${SLING_LINGER:-}" ]; then
      ( exec sleep 300 ) </dev/null >/dev/null 2>&1 &
      printf '%s\n' "$!" >> "$LINGERERS"
    fi
    if [ -n "${SLING_HOLD_AFTER_POUR:-}" ]; then touch "$SLING_HOLD_AFTER_POUR/poured"; wait_for "$SLING_HOLD_AFTER_POUR/go"; fi
    [ "${STOP_AT:-}" = after-sling ] && kill_run
    case "${SLING_FAIL:-}" in committed|partial) echo "gc sling: failed after the pour" >&2; exit 1 ;; esac
    exit 0 ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

# --- lifecycle writer stub ----------------------------------------------------
# lifecycle.sh over the same store, which Accept runs as $GC_LIFECYCLE_TOOL and
# the sign-off finds at $GC_RIG_ROOT. `state <bead>` prints the bead's
# merge_result, unanchored when it carries none. `transition <bead> --to
# unanchored` is recorded, then refused (exit 1, nothing written) when --expect
# names a state the bead is not in, or when the case sets $LC_FAIL; otherwise it
# drops merge_result and writes its --route as gc.routed_to, through the gc stub.
cat > "$TMP/lifecycle-stub" <<'L'
#!/usr/bin/env bash
cur() { jq -r '.metadata.merge_result // "unanchored"' "$STORE/b/$1.json" 2>/dev/null; }
case "${1:-}" in
  state) [ -f "$STORE/b/$2.json" ] || exit 2; cur "$2" ;;
  transition)
    _b="$2"; shift 2
    printf 'lifecycle transition %s %s\n' "$_b" "$*" >> "$CALLS"
    _to=""; _exp=""; _route=""; _route_set=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --to) _to="$2"; shift 2 ;;
        --expect) _exp="$2"; shift 2 ;;
        --route) _route="$2"; _route_set=1; shift 2 ;;
        *) shift ;;
      esac
    done
    [ -z "${LC_FAIL:-}" ] || exit 1
    [ -z "$_exp" ] || [ "$(cur "$_b")" = "$_exp" ] || exit 1
    [ "$_to" = unanchored ] || exit 1
    if [ "$_route_set" = 1 ]; then gc bd update "$_b" --unset-metadata merge_result --set-metadata "gc.routed_to=$_route" >/dev/null
    else gc bd update "$_b" --unset-metadata merge_result >/dev/null; fi ;;
esac
exit 0
L
chmod +x "$TMP/lifecycle-stub"

export PATH="$TMP/bin:$PATH"
export GC_LIFECYCLE_TOOL="$TMP/lifecycle-stub"
export STORE="$TMP/store" CALLS="$TMP/calls" LINGERERS="$TMP/lingerers" CITY_ROOT="$TMP/city"
export GC_CITY_PATH="$TMP/city" ACC_BEAD=tk-anc
unset GC_HELM_FIXTURE GC_CITY GC_CITY_ROOT GC_RIG BEADS_DIR 2>/dev/null || true
export TMPDIR="$TMP"
LOCKFILE() { printf '%s/.gc/runtime/packs/gc-toolkit/accept-gc-toolkit-%s.lock' "$TMP/city" "${1:-tk-anc}"; }

# --- fixtures -----------------------------------------------------------------
# fresh — an empty store: no beads, no sessions, no calls, no roots.
fresh() {
    rm -rf "$STORE"; mkdir -p "$STORE/b"; printf '[]' > "$STORE/sessions.json"; : > "$CALLS"
    rm -rf "$TMP/city/.gc/runtime"
}
# bead <id> [formula] — an open task, carrying the recommendation when given.
bead() {
    jq -n --arg id "$1" --arg f "${2:-}" '{id:$id, title:("the bead " + $id), status:"open", issue_type:"task",
        assignee:"", created_at:"2026-10-01T00:00:00Z", updated_at:"2026-10-01T00:00:00Z",
        metadata:(if $f == "" then {} else {"gc.recommended_formula": $f} end), deps:[]}' > "$STORE/b/$1.json"
}
# gate <id> <key> <title> [created_at] [assignee] — an open human gate.
gate() {
    jq -n --arg id "$1" --arg k "$2" --arg t "$3" --arg c "${4:-2026-10-02T00:00:00Z}" --arg a "${5:-}" \
        '{id:$id, title:$t, status:"open", issue_type:"gate", await_type:"human", await_id:$k, assignee:$a,
          created_at:$c, updated_at:$c, metadata:{}, deps:[]}' > "$STORE/b/$1.json"
}
# edge <from> <type> <on>
edge() { jq --arg t "$2" --arg o "$3" '.deps += [{type:$t, on:$o}]' "$STORE/b/$1.json" > "$STORE/b/$1.tmp" && mv "$STORE/b/$1.tmp" "$STORE/b/$1.json"; }
# close_gate <gate> <reason> — a gate answered outside Accept.
close_gate() { jq --arg r "$2" '.status = "closed" | .close_reason = $r' "$STORE/b/$1.json" > "$STORE/b/$1.tmp" && mv "$STORE/b/$1.tmp" "$STORE/b/$1.json"; }
# close_bead <id>
close_bead() { jq '.status = "closed"' "$STORE/b/$1.json" > "$STORE/b/$1.tmp" && mv "$STORE/b/$1.tmp" "$STORE/b/$1.json"; }
# rec — the base fixture: tk-anc recommends mol-fix, put by the open gate tk-rec.
rec() { fresh; bead tk-anc mol-fix; gate tk-rec first-reaction "Accept mol-fix on tk-anc: the reaction recommends it"; edge tk-anc blocks tk-rec; }
# record_on <gate> <token> <formula> [<key>=<value>...] — the dispatch input an
# Accept records on the gate before it resolves it.
record_on() {
    _g="$1"; _t="$2"; _f="$3"; shift 3
    _v=$(jq -nc '$ARGS.positional' --args "$@")
    jq --arg t "$_t" --arg f "$_f" --argjson v "$_v" '.metadata["gc.acceptance"] = ({token: $t, formula: $f, vars: $v} | tojson)' \
        "$STORE/b/$_g.json" > "$STORE/b/$_g.tmp" && mv "$STORE/b/$_g.tmp" "$STORE/b/$_g.json"
}
# unfinished <token> — the base fixture with tk-rec closed by an Accept that
# stopped, its dispatch input recorded on the gate as that Accept left it.
unfinished() { rec; record_on tk-rec "$1" mol-fix; close_gate tk-rec "ruled: accepted mol-fix accept:$1"; }
# held_bead <id> — the bead as a sitting's hold leaves it: at held, routed to
# human.
held_bead() { jq '.metadata.merge_result = "held" | .metadata["gc.routed_to"] = "human"' "$STORE/b/$1.json" > "$STORE/b/$1.tmp" && mv "$STORE/b/$1.tmp" "$STORE/b/$1.json"; }

# --- readers ------------------------------------------------------------------
field()   { jq -r --arg k "$2" '.[$k] // "" | tostring' "$STORE/b/$1.json" 2>/dev/null; }
meta()    { jq -r --arg k "$2" '.metadata[$k] // ""' "$STORE/b/$1.json" 2>/dev/null; }
token_of(){ field "$1" close_reason | sed -n 's/^ruled: accepted [^ ]* accept:\([0-9a-f]*\)$/\1/p'; }
roots()   { cat "$STORE"/b/tk-root*.json 2>/dev/null | jq -s --arg t "${1:-}" '[ .[] | select((.title | contains($t))) ] | length'; }
live_roots() { cat "$STORE"/b/tk-root*.json 2>/dev/null | jq -s --arg t "${1:-}" '[ .[] | select((.title | contains($t)) and .status != "closed" and (.metadata.molecule_failed // "") != "true") ] | length'; }
slings()  { grep -c '^sling ' "$CALLS" 2>/dev/null || true; }
writes()  { grep -c -v '^sling refused' "$CALLS" 2>/dev/null || true; }
lock_free() { flock -n "$(LOCKFILE "${1:-tk-anc}")" true; }
# lock_free_soon — the lock is free within 5s: a killed process's descriptors
# close as it exits, a moment after its parent's wait returns.
lock_free_soon() { _i=0; until lock_free "${1:-tk-anc}"; do sleep 0.05; _i=$((_i + 1)); [ "$_i" -lt 100 ] || return 1; done; }

# run_accept <args...> -> RC, OUT. Output goes to a file, never a pipe, so a
# process the sling leaves running cannot hold the capture open.
run_accept() {
    set +e
    sh "$SCRIPT" accept "$@" > "$TMP/out" 2>&1; RC=$?
    set -e
    OUT="$(cat "$TMP/out")"
}
# bg_accept <name> <args...> — start a run in the background; BG_PID is its pid.
bg_accept() { _n="$1"; shift; sh "$SCRIPT" accept "$@" > "$TMP/$_n.out" 2>&1 & BG_PID=$!; }
# wait_file <path> — wait for a stub hook's marker, failing the case after 30s.
wait_file() { _i=0; until [ -e "$1" ]; do sleep 0.05; _i=$((_i + 1)); [ "$_i" -lt 600 ] || { bad "timed out waiting for $1"; return 1; }; done; }
wait_lock_free() { _i=0; until lock_free "${1:-tk-anc}"; do sleep 0.05; _i=$((_i + 1)); [ "$_i" -lt 600 ] || { bad "the lock on ${1:-tk-anc} never came free"; return 1; }; done; }

echo "# the guards: discuss-only, no gate asking, a gate assigned to a person, an unverifiable bead"
fresh; bead tk-anc
run_accept tk-anc
eq "$RC" 2 "(DISCUSS-ONLY) a bead with no recommendation exits 2"
has "$OUT" "discuss-only" "(DISCUSS-ONLY) …saying it is discuss-only"
eq "$(writes)" 0 "(DISCUSS-ONLY) …and writes nothing"
fresh; bead tk-anc mol-fix
run_accept tk-anc
eq "$RC" 4 "(NO-GATE) a recommendation no first-reaction gate asks exits 4"
has "$OUT" "no human gate under the key first-reaction" "(NO-GATE) …saying nothing asks for an Accept"
eq "$(writes)" 0 "(NO-GATE) …and writes nothing"
rec; jq '.assignee = "alice"' "$STORE/b/tk-rec.json" > "$STORE/b/tk-rec.tmp" && mv "$STORE/b/tk-rec.tmp" "$STORE/b/tk-rec.json"
run_accept tk-anc
eq "$RC" 4 "(ASSIGNED) a recommendation's gate assigned to a person exits 4"
has "$OUT" "tk-rec (assigned to alice)" "(ASSIGNED) …naming whose it is"
eq "$(writes)" 0 "(ASSIGNED) …and writes nothing"
rec; SHOW_DOWN=1 run_accept tk-anc
eq "$RC" 4 "(UNVERIFIED) a bead that cannot be read exits 4"
eq "$(writes)" 0 "(UNVERIFIED) …and writes nothing"
rec; run_accept tk-nope
eq "$RC" 4 "(NOT-FOUND) an unknown bead exits 4"
eq "$(writes)" 0 "(NOT-FOUND) …and writes nothing"

echo "# the acceptance case: a recommendation beside a review gate"
rec; gate tk-rev review-needs-you.tk-find "Rule on finding tk-find: the retry drops a write"; edge tk-anc blocks tk-rev
run_accept tk-anc
eq "$RC" 4 "(STALE) Accept with a review gate open beside the recommendation exits 4"
has "$OUT" "tk-rev (Rule on finding tk-find: the retry drops a write)" "(STALE) …naming the review gate by id and title"
has "$OUT" "engage tk-anc" "(STALE) …with Discuss as the way forward"
eq "$(field tk-rec status)/$(field tk-rev status)" "open/open" "(STALE) …both gates stay open"
eq "$(meta tk-anc gc.recommended_formula)" "mol-fix" "(STALE) …the recommendation stays"
eq "$(writes)" 0 "(STALE) …and nothing is written or slung"
# Discuss answers the review gate: its sitting's sign-off resolves it.
close_gate tk-rev "ruled: fix the retry before the merge"
run_accept tk-anc --reason "the reaction is right"
eq "$RC" 0 "(ACCEPT) with the recommendation's gate the last one open, Accept exits 0"
TOK="$(token_of tk-rec)"
[ -n "$TOK" ] && ok "(ACCEPT) the recommendation's gate is resolved with Accept's answer, ruled: accepted <formula> accept:<token>" \
  || bad "(ACCEPT) tk-rec's close reason is not an Accept's answer (got '$(field tk-rec close_reason)')"
eq "$(field tk-rec close_reason)" "ruled: accepted mol-fix accept:$TOK" "(ACCEPT) …naming the formula it accepts"
eq "${#TOK}" 16 "(ACCEPT) …under a fixed-length token, so no token is another's prefix"
eq "$(slings)" 1 "(ACCEPT) the formula is slung once"
has "$(grep '^sling ' "$CALLS")" "sling tk-anc --on mol-fix --title mol-fix accept:$TOK" "(ACCEPT) …at the bead, titled with the token"
hasnt "$(grep '^sling ' "$CALLS")" "--var" "(ACCEPT) …with no --var of its own"
eq "$(roots "accept:$TOK")" 1 "(ACCEPT) …so the root it pours names the acceptance"
eq "$(meta tk-anc gc.recommended_formula_dispatched)" "mol-fix" "(ACCEPT) the dispatch is recorded"
eq "$(meta tk-anc gc.recommended_formula)" "" "(ACCEPT) …in the write that withdraws the recommendation"
has "$(field tk-anc notes)" "Accept dispatched mol-fix (acceptance $TOK): the reaction is right" "(ACCEPT) --reason rides the dispatch note"
eq "$(field tk-rev close_reason)" "ruled: fix the retry before the merge" "(ACCEPT) the review gate's close reason is still the sitting's ruling"
case "$(cat "$CALLS")" in
  *"bd gate resolve tk-rec"*"sling tk-anc"*) ok "(ACCEPT) the resolve comes before the sling" ;;
  *) bad "(ACCEPT) the resolve should precede the sling (calls: $(cat "$CALLS"))" ;;
esac
eq "$(meta tk-rec gc.acceptance | jq -c .)" "{\"token\":\"$TOK\",\"formula\":\"mol-fix\",\"vars\":[]}" "(ACCEPT) the gate records the acceptance's dispatch input under its token"
case "$(cat "$CALLS")" in
  *"bd update tk-rec --set-metadata gc.acceptance="*"bd gate resolve tk-rec"*) ok "(ACCEPT) …before the resolve that names the token" ;;
  *) bad "(ACCEPT) the dispatch input should be recorded before the resolve (calls: $(cat "$CALLS"))" ;;
esac
hasnt "$(cat "$CALLS")" "bd close" "(ACCEPT) Accept runs no dismiss"
: > "$CALLS"; run_accept tk-anc
eq "$RC" 2 "(DISPATCHED) an Accept run after the first one's record exits 2"
has "$OUT" "was dispatched (mol-fix)" "(DISPATCHED) …because the recommendation is dispatched"
eq "$(writes)" 0 "(DISPATCHED) …and writes nothing"

echo "# a gate filed after the live read stops the dispatch"
rec; LATE_GATE_ON_RESOLVE=tk-late run_accept tk-anc
eq "$RC" 4 "(LATE) a gate filed between the live read and the resolve exits 4"
has "$OUT" "tk-late" "(LATE) …naming the late gate"
eq "$(field tk-rec status)" "open" "(LATE) …and the recommendation's gate is reopened"
eq "$(field tk-rec close_reason)" "" "(LATE) …its close and reason cleared"
has "$OUT" "is open again, back on the board" "(LATE) …and read back as open"
eq "$(slings)" 0 "(LATE) …nothing is slung"
eq "$(meta tk-anc gc.recommended_formula)" "mol-fix" "(LATE) …and the recommendation stays"

echo "# an earlier answer stops Accept"
rec; EARLIER_ANSWER="ruled: declined" run_accept tk-anc
eq "$RC" 4 "(EARLIER) a sitting's answer reaching the gate first exits 4"
has "$OUT" 'another answer reached tk-anc'"'"'s recommendation gate first — tk-rec: "ruled: declined"' "(EARLIER) …reporting that answer"
eq "$(field tk-rec close_reason)" "ruled: declined" "(EARLIER) …the gate keeps the sitting's reason"
eq "$(field tk-rec status)" "closed" "(EARLIER) …nothing is reopened"
eq "$(slings)" 0 "(EARLIER) …and nothing is slung"
: > "$CALLS"; run_accept tk-anc
eq "$RC" 4 "(DECLINED) a declined recommendation leaves nothing to finish: Accept exits 4"
has "$OUT" '"ruled: declined". That answer stands' "(DECLINED) …saying the sitting's answer stands"
eq "$(writes)" 0 "(DECLINED) …and writes nothing"

echo "# a gate filed on another bead that the bead waits on withholds Accept"
rec; bead tk-other; gate tk-ob bring-current "Rule on bringing tk-other current"; edge tk-other blocks tk-ob; edge tk-anc blocks tk-ob
run_accept tk-anc
eq "$RC" 4 "(OTHER-BEAD) a gate filed on another bead that tk-anc waits on exits 4"
has "$OUT" "tk-ob (Rule on bringing tk-other current)" "(OTHER-BEAD) …naming that gate"
eq "$(writes)" 0 "(OTHER-BEAD) …and nothing is written or slung"

echo "# a live sitting whose conversation replies to the recommendation's gate is warned about"
rec; bead tk-conv; edge tk-conv tracks tk-anc; edge tk-conv replies-to tk-rec
jq '.assignee = "gc-toolkit/gc-toolkit.tk-conv" | .status = "in_progress"' "$STORE/b/tk-conv.json" > "$STORE/b/tk-conv.tmp" && mv "$STORE/b/tk-conv.tmp" "$STORE/b/tk-conv.json"
jq -n '[{id:"gc-50", session_name:"s-gc-50", alias:"gc-toolkit/gc-toolkit.tk-conv", template:"gc-toolkit/gc-toolkit.converse-opus", state:"active", closed:false}]' > "$STORE/sessions.json"
run_accept tk-anc
eq "$RC" 0 "(LIVE-SITTING) Accept beside a live sitting replying to the gate exits 0"
has "$OUT" "warning: a live sitting holds conversation tk-conv" "(LIVE-SITTING) …warning of the sitting"
has "$(field tk-rec close_reason)" "ruled: accepted mol-fix accept:" "(LIVE-SITTING) …and clearing the gate anyway"
eq "$(slings)" 1 "(LIVE-SITTING) …slinging once"
eq "$(field tk-conv status)" "in_progress" "(LIVE-SITTING) …and leaving the sitting's conversation to the operator"

echo "# a bead a sitting's hold left at held is released before the dispatch"
# A sitting's hold moves an unanchored bead to held while the operator owes the
# answer of a gate that blocks it, and mol-polecat-work's load-context cancels a
# run poured at a bead that carries any merge_result. Accept's answer is the one
# the hold waited for, so it releases the bead after that answer reads back and
# before its sling.
rec; held_bead tk-anc
run_accept tk-anc
eq "$RC" 0 "(HELD) Accept on a bead a sitting's hold left at held exits 0"
eq "$(meta tk-anc merge_result)" "" "(HELD) …releasing it from held"
eq "$(meta tk-anc gc.routed_to)" "human" "(HELD) …routed to human, as a sign-off that takes the recommendation leaves it"
case "$(cat "$CALLS")" in
  *"bd gate resolve tk-rec"*"lifecycle transition tk-anc --to unanchored --expect held --route human"*"sling tk-anc"*)
    ok "(HELD) …after its answer and before its sling" ;;
  *) bad "(HELD) the release should follow the resolve and precede the sling (calls: $(cat "$CALLS"))" ;;
esac
eq "$(slings)" 1 "(HELD) …slinging once"
eq "$(meta tk-anc gc.recommended_formula_dispatched)/$(meta tk-anc gc.recommended_formula)" "mol-fix/" "(HELD) …and recording the dispatch"
rec; held_bead tk-anc
LC_FAIL=1 run_accept tk-anc
T="$(token_of tk-rec)"
eq "$RC" 4 "(HELD-FAIL) a release that does not land exits 4"
has "$OUT" "its release to unanchored did not read back" "(HELD-FAIL) …saying the release did not land"
eq "$(slings)" 0 "(HELD-FAIL) …slinging nothing at a bead that still reads held"
eq "$(meta tk-anc merge_result)" "held" "(HELD-FAIL) …which still reads held"
eq "$(meta tk-anc gc.recommended_formula)" "mol-fix" "(HELD-FAIL) …with the recommendation in place"
[ -n "$T" ] && ok "(HELD-FAIL) …and the gate answered, an acceptance the next Accept finishes" \
  || bad "(HELD-FAIL) tk-rec's close reason is not an Accept's answer (got '$(field tk-rec close_reason)')"
: > "$CALLS"; run_accept tk-anc
eq "$RC" 0 "(HELD-FINISH) the next Accept finishes the acceptance"
has "$OUT" "an earlier Accept left unfinished ($T)" "(HELD-FINISH) …under its token"
eq "$(meta tk-anc merge_result)" "" "(HELD-FINISH) …releasing the bead"
eq "$(slings)" 1 "(HELD-FINISH) …and slinging once"
has "$(grep '^sling ' "$CALLS")" "--title mol-fix accept:$T" "(HELD-FINISH) …titled with the acceptance's token"

echo "# a recommendation on a bead with an open child is accepted as on any bead"
fresh; bead tk-par mol-fix; bead tk-kid; edge tk-kid parent-child tk-par
gate tk-rec first-reaction "Accept mol-fix on tk-par"; edge tk-par blocks tk-rec
ACC_BEAD=tk-par run_accept tk-par
eq "$RC" 0 "(PARENT) Accept on a parent with an open child exits 0"
has "$(grep '^sling ' "$CALLS")" "sling tk-par --on mol-fix" "(PARENT) …slinging at the parent"
eq "$(meta tk-par gc.recommended_formula_dispatched)" "mol-fix" "(PARENT) …and recording it"

echo "# a gate or conversation id names the bead it is about"
rec; run_accept tk-rec
eq "$RC" 0 "(GATE-ID) Accept given the recommendation's gate id exits 0"
has "$(grep '^sling ' "$CALLS")" "sling tk-anc --on mol-fix" "(GATE-ID) …accepting for the bead the gate blocks"

echo "# an Accept stopped part way is finished by the next one"
for stop in resolve sling after-sling; do
    rec; STOP_AT=$stop run_accept tk-anc
    T="$(token_of tk-rec)"
    [ -n "$T" ] && ok "(STOP-$stop) the stopped run's answer is on the gate" || bad "(STOP-$stop) no Accept answer on tk-rec (got '$(field tk-rec close_reason)')"
    eq "$(meta tk-anc gc.recommended_formula)" "mol-fix" "(STOP-$stop) …the bead still carries the recommendation"
    lock_free_soon && ok "(STOP-$stop) …and the bead's acceptance lock is free" || bad "(STOP-$stop) the lock is still held after the run stopped"
    SL_BEFORE="$(slings)"
    run_accept tk-anc
    eq "$RC" 0 "(STOP-$stop) the next Accept finishes the acceptance"
    has "$OUT" "an earlier Accept left unfinished ($T)" "(STOP-$stop) …under the stopped run's token"
    eq "$(roots "accept:$T")" 1 "(STOP-$stop) …with one root under that token"
    if [ "$stop" = after-sling ]; then
        eq "$(slings)" "$SL_BEFORE" "(STOP-$stop) …slinging nothing, since the stopped run's root is found by the token"
    else
        eq "$(( $(slings) - SL_BEFORE ))" 1 "(STOP-$stop) …slinging once"
        has "$(grep '^sling ' "$CALLS" | tail -1)" "--title mol-fix accept:$T" "(STOP-$stop) …titled with the stopped run's token"
    fi
    eq "$(meta tk-anc gc.recommended_formula_dispatched)/$(meta tk-anc gc.recommended_formula)" "mol-fix/" "(STOP-$stop) …and recording the dispatch"
done
# After the third stop, the next Accept does the same once its root has closed.
rec; STOP_AT=after-sling run_accept tk-anc
T="$(token_of tk-rec)"
for r in "$STORE"/b/tk-root*.json; do jq '.status = "closed"' "$r" > "$r.tmp" && mv "$r.tmp" "$r"; done
SL_BEFORE="$(slings)"; run_accept tk-anc
eq "$RC" 0 "(STOP-after-sling-closed) a finish whose stopped root has closed exits 0"
eq "$(slings)" "$SL_BEFORE" "(STOP-after-sling-closed) …slinging nothing: the closed root still carries the token"
eq "$(roots "accept:$T")" 1 "(STOP-after-sling-closed) …so no second root is poured"
eq "$(meta tk-anc gc.recommended_formula_dispatched)" "mol-fix" "(STOP-after-sling-closed) …and the dispatch is recorded"

echo "# each --var rides the sling, and a root already poured keeps its own vars"
rec; run_accept tk-anc --var design_gated=false --var note=a=b
TOK="$(token_of tk-rec)"
eq "$RC" 0 "(VAR) an Accept given vars exits 0"
has "$(grep '^sling ' "$CALLS")" "sling tk-anc --on mol-fix --title mol-fix accept:$TOK --var design_gated=false --var note=a=b" "(VAR) …slinging each var as given, in order"
rec; STOP_AT=after-sling run_accept tk-anc
SL_BEFORE="$(slings)"; run_accept tk-anc --var design_gated=false
eq "$RC" 0 "(VAR-POURED) a finish given vars, after a stopped run poured its root, exits 0"
eq "$(slings)" "$SL_BEFORE" "(VAR-POURED) …slinging nothing"
has "$OUT" "That root keeps the vars it was poured with, so the --var given here does not reach it" "(VAR-POURED) …and saying the root keeps its own vars"
for v in design_gated =false "$(printf 'a=b\nc=d')"; do
    rec; run_accept tk-anc --var "$v"
    eq "$RC" 2 "(VAR-FORM) a --var that is not <key>=<value> on one line ('$v') exits 2"
    eq "$(writes)" 0 "(VAR-FORM) …writing nothing"
done

echo "# an acceptance's vars are recorded before its resolve, and whoever finishes it slings them"
rec; run_accept tk-anc --var design_gated=false --var note=a=b
TOK="$(token_of tk-rec)"
eq "$(meta tk-rec gc.acceptance | jq -c .)" "{\"token\":\"$TOK\",\"formula\":\"mol-fix\",\"vars\":[\"design_gated=false\",\"note=a=b\"]}" "(VAR-RECORD) the gate records each var under the acceptance's token"
for stop in resolve sling; do
    rec; STOP_AT=$stop run_accept tk-anc --var design_gated=false
    T="$(token_of tk-rec)"
    eq "$(roots "accept:$T")" 0 "(VAR-STOP-$stop) an Accept given a var stopped before its pour leaves nothing poured"
    run_accept tk-anc
    eq "$RC" 0 "(VAR-STOP-$stop) the board's plain Accept finishes the acceptance"
    has "$OUT" "slings the vars it was accepted with: --var design_gated=false" "(VAR-STOP-$stop) …saying it slings the vars the acceptance recorded"
    has "$(grep '^sling ' "$CALLS" | tail -1)" "--title mol-fix accept:$T --var design_gated=false" "(VAR-STOP-$stop) …and slinging the var the acceptance was made with, not the retry's none"
    eq "$(roots "accept:$T")" 1 "(VAR-STOP-$stop) …pouring one root under the token"
done
rec; STOP_AT=resolve run_accept tk-anc --var design_gated=false
T="$(token_of tk-rec)"; W_BEFORE="$(writes)"
run_accept tk-anc --var design_gated=true
eq "$RC" 4 "(VAR-MISMATCH) a finish given a var that differs from the acceptance's exits 4"
has "$OUT" "was accepted with --var design_gated=false, and this run was given --var design_gated=true" "(VAR-MISMATCH) …naming both"
eq "$(writes)" "$W_BEFORE" "(VAR-MISMATCH) …writing and slinging nothing"
run_accept tk-anc --var design_gated=false
eq "$RC" 0 "(VAR-MISMATCH) a finish given the same var exits 0"
has "$(grep '^sling ' "$CALLS" | tail -1)" "--title mol-fix accept:$T --var design_gated=false" "(VAR-MISMATCH) …slinging it once"
unfinished 0123456789abcdef
jq 'del(.metadata["gc.acceptance"])' "$STORE/b/tk-rec.json" > "$STORE/b/tk-rec.tmp" && mv "$STORE/b/tk-rec.tmp" "$STORE/b/tk-rec.json"
run_accept tk-anc
eq "$RC" 4 "(VAR-NO-RECORD) an unfinished acceptance whose gate records no dispatch input exits 4"
has "$OUT" "records no dispatch input for acceptance 0123456789abcdef" "(VAR-NO-RECORD) …saying the vars it was accepted with cannot be told"
eq "$(writes)" 0 "(VAR-NO-RECORD) …and writes and slings nothing"
unfinished 0123456789abcdef; record_on tk-rec 0123456789abcdef mol-other design_gated=false
run_accept tk-anc
eq "$RC" 4 "(VAR-NO-RECORD) a record made for another formula is no record of this acceptance"

echo "# a gate filed after the stop holds the finish"
unfinished 0123456789abcdef; gate tk-hold liveness "Is the rig still alive?"; edge tk-anc blocks tk-hold
run_accept tk-anc
eq "$RC" 4 "(HOLD) a gate filed after the stop makes the finishing Accept exit 4"
has "$OUT" "tk-hold (Is the rig still alive?)" "(HOLD) …naming that gate"
eq "$(writes)" 0 "(HOLD) …and writing nothing"
close_gate tk-hold "benign: the rig answered"
run_accept tk-anc
eq "$RC" 0 "(HOLD-CLEARED) once that gate is cleared, the next Accept finishes"
eq "$(roots accept:0123456789abcdef)" 1 "(HOLD-CLEARED) …pouring one root under the stopped run's token"
eq "$(meta tk-anc gc.recommended_formula_dispatched)" "mol-fix" "(HOLD-CLEARED) …and recording it"
unfinished 0123456789abcdef
LATE_GATE_ON_SEARCH=tk-late2 run_accept tk-anc
eq "$RC" 4 "(HOLD-LATE) a gate filed between a finishing run's live read and its step 3 exits 4"
eq "$(field tk-rec status)" "open" "(HOLD-LATE) …the recommendation's gate is reopened, back on the board, owed"
eq "$(slings)" 0 "(HOLD-LATE) …and nothing is slung"

echo "# two runs on one unfinished acceptance pour once"
unfinished fedcba9876543210; mkdir -p "$TMP/pA"; rm -f "$TMP/pA"/*
SLING_PAUSE="$TMP/pA" bg_accept raceA tk-anc; A_PID=$BG_PID
wait_file "$TMP/pA/arrived"
W_BEFORE="$(writes)"
run_accept tk-anc
eq "$RC" 4 "(RACE-FINISH) the second finishing run exits 4"
has "$OUT" "holds its acceptance lock (pid $A_PID" "(RACE-FINISH) …refusing at the lock and naming the first run"
eq "$(writes)" "$W_BEFORE" "(RACE-FINISH) …and writing nothing"
for r in "$STORE"/b/tk-root*.json; do [ -f "$r" ] && { jq '.status = "closed"' "$r" > "$r.tmp" && mv "$r.tmp" "$r"; }; done
touch "$TMP/pA/go"; set +e; wait "$A_PID"; A_RC=$?; set -e
eq "$A_RC" 0 "(RACE-FINISH) the first run then slings and records"
eq "$(roots accept:fedcba9876543210)" 1 "(RACE-FINISH) …one root under the token"
eq "$(slings)" 1 "(RACE-FINISH) …one sling"
eq "$(meta tk-anc gc.recommended_formula_dispatched)" "mol-fix" "(RACE-FINISH) …one recorded dispatch"

rec; mkdir -p "$TMP/pB"; rm -f "$TMP/pB"/*
SLING_PAUSE="$TMP/pB" bg_accept raceB tk-anc; A_PID=$BG_PID
wait_file "$TMP/pB/arrived"
W_BEFORE="$(writes)"
run_accept tk-anc
eq "$RC" 4 "(RACE-OPEN) an Accept beside a first one paused between its resolve and its sling exits 4"
has "$OUT" "holds its acceptance lock (pid $A_PID" "(RACE-OPEN) …refusing at the lock, naming the first"
eq "$(writes)" "$W_BEFORE" "(RACE-OPEN) …and writing nothing, where without the lock it would finish the first one's acceptance"
touch "$TMP/pB/go"; set +e; wait "$A_PID"; A_RC=$?; set -e
eq "$A_RC" 0 "(RACE-OPEN) the first run then slings and records"
eq "$(slings)" 1 "(RACE-OPEN) …slung once in all"

echo "# the lock outlives no run, and a run that cannot take it refuses"
rec; SLING_LINGER=1 run_accept tk-anc
eq "$RC" 0 "(LINGER) an Accept whose sling leaves a process running exits 0"
[ -s "$LINGERERS" ] && ok "(LINGER) …and the sling's process is still running" || bad "(LINGER) the stub left no process running"
lock_free && ok "(LINGER) …yet the lock is free: the sling ran with the lock's descriptor closed" || bad "(LINGER) the lingering process holds the lock"
run_accept tk-anc
eq "$RC" 2 "(LINGER) the next Accept takes the lock (and finds the recommendation dispatched)"
hasnt "$OUT" "holds its acceptance lock" "(LINGER) …never refused at the lock"
rec; GC_CITY_PATH="" CITY_ROOT="$TMP/no-city" run_accept tk-anc
eq "$RC" 3 "(NO-CITY) an Accept that cannot name the city root exits 3"
has "$OUT" "no city root could be named" "(NO-CITY) …saying so"
eq "$(writes)" 0 "(NO-CITY) …and writes nothing"
# A PATH that carries every tool but flock.
mkdir -p "$TMP/noflock"
IFS=: read -r -a _dirs <<< "$PATH"
for _d in "${_dirs[@]}"; do
    [ -d "$_d" ] || continue
    for _f in "$_d"/*; do
        _b="${_f##*/}"
        [ "$_b" = flock ] && continue
        [ -e "$TMP/noflock/$_b" ] || ln -s "$_f" "$TMP/noflock/$_b" 2>/dev/null || true
    done
done
rec; PATH="$TMP/noflock" run_accept tk-anc
eq "$RC" 3 "(NO-FLOCK) an Accept that finds no flock exits 3"
has "$OUT" "flock is not on PATH" "(NO-FLOCK) …saying so"
eq "$(writes)" 0 "(NO-FLOCK) …and writes nothing"

echo "# a run killed by itself keeps the lock until its sling exits"
rec; mkdir -p "$TMP/k"; rm -f "$TMP/k"/*
SLING_HOLD_AFTER_POUR="$TMP/k" bg_accept selfkill tk-anc; A_PID=$BG_PID
wait_file "$TMP/k/poured"
kill -9 "$A_PID" 2>/dev/null || true; wait "$A_PID" 2>/dev/null || true
W_BEFORE="$(writes)"
run_accept tk-anc
eq "$RC" 4 "(SELF-KILL) a finishing run started while the killed run's sling pours exits 4"
has "$OUT" "holds its acceptance lock (pid $A_PID" "(SELF-KILL) …refusing at the lock, naming the stopped run"
eq "$(writes)" "$W_BEFORE" "(SELF-KILL) …and writing nothing"
touch "$TMP/k/go"; wait_lock_free
SL_BEFORE="$(slings)"; T="$(token_of tk-rec)"
run_accept tk-anc
eq "$RC" 0 "(SELF-KILL) once the sling exits, the next Accept takes the lock and finishes"
eq "$(slings)" "$SL_BEFORE" "(SELF-KILL) …slinging nothing, since it finds the root by the token"
eq "$(roots "accept:$T")" 1 "(SELF-KILL) …one root under the token"
eq "$(meta tk-anc gc.recommended_formula_dispatched)" "mol-fix" "(SELF-KILL) …and the dispatch recorded"

echo "# a sling that outlives the lock meets Gas City's launch lock"
rec; mkdir -p "$TMP/o"; rm -f "$TMP/o"/*; rm -f "$STORE"/launch-waiting.*
SLING_HOLD_BEFORE_POUR="$TMP/o" bg_accept outlive tk-anc; A_PID=$BG_PID
wait_file "$TMP/o/locked"
read -r _main _sub < "$TMP/o/pids"
kill -9 "$_main" "$_sub" 2>/dev/null || true; wait "$A_PID" 2>/dev/null || true
wait_lock_free
T="$(token_of tk-rec)"
bg_accept finisher tk-anc; F_PID=$BG_PID
_i=0; until ls "$STORE"/launch-waiting.* >/dev/null 2>&1; do sleep 0.05; _i=$((_i + 1)); [ "$_i" -lt 600 ] || { bad "(OUTLIVE) the finishing run never reached the launch lock"; break; }; done
touch "$TMP/o/go"
set +e; wait "$F_PID"; F_RC=$?; set -e
F_OUT="$(cat "$TMP/finisher.out")"
eq "$F_RC" 0 "(OUTLIVE) the finishing run exits 0"
has "$(cat "$CALLS")" "sling refused tk-anc" "(OUTLIVE) …its sling refused by the launch lock while the outliving sling's root is live"
has "$F_OUT" "exited 3" "(OUTLIVE) …exiting 3"
has "$F_OUT" "carries acceptance $T, so the dispatch landed" "(OUTLIVE) …and it finds the root by the token"
eq "$(roots "accept:$T")" 1 "(OUTLIVE) …one root under the token"
eq "$(meta tk-anc gc.recommended_formula_dispatched)" "mol-fix" "(OUTLIVE) …and records the dispatch"

echo "# a failed sling is judged by the token's root"
rec; SLING_FAIL=committed run_accept tk-anc
eq "$RC" 0 "(SLING-COMMITTED) a sling that fails after its pour committed exits 0"
has "$OUT" "so the dispatch landed" "(SLING-COMMITTED) …the token's root says the dispatch landed"
eq "$(field tk-rec status)" "closed" "(SLING-COMMITTED) …nothing is reopened"
eq "$(meta tk-anc gc.recommended_formula_dispatched)" "mol-fix" "(SLING-COMMITTED) …and the dispatch is recorded"
rec; SLING_FAIL=committed STOP_AT=after-sling run_accept tk-anc
T="$(token_of tk-rec)"; SL_BEFORE="$(slings)"
run_accept tk-anc
eq "$RC" 0 "(SLING-COMMITTED-STOP) after a committed pour and a stop, the next Accept exits 0"
eq "$(slings)" "$SL_BEFORE" "(SLING-COMMITTED-STOP) …slinging nothing"
eq "$(meta tk-anc gc.recommended_formula_dispatched)" "mol-fix" "(SLING-COMMITTED-STOP) …and recording the dispatch"
rec; SLING_FAIL=partial run_accept tk-anc
eq "$RC" 1 "(SLING-PARTIAL) a sling whose pour failed part way exits 1"
eq "$(field tk-rec status)" "open" "(SLING-PARTIAL) …the recommendation's gate is reopened"
eq "$(meta tk-anc gc.recommended_formula)" "mol-fix" "(SLING-PARTIAL) …the recommendation stays"
eq "$(meta tk-anc gc.recommended_formula_dispatched)" "" "(SLING-PARTIAL) …and no dispatch is recorded"
rec; SLING_FAIL=partial STOP_AT=after-sling run_accept tk-anc
T="$(token_of tk-rec)"; SL_BEFORE="$(slings)"
run_accept tk-anc
eq "$RC" 0 "(SLING-PARTIAL-STOP) after a failed pour and a stop, the next Accept exits 0"
eq "$(( $(slings) - SL_BEFORE ))" 1 "(SLING-PARTIAL-STOP) …slinging once"
eq "$(live_roots "accept:$T")" 1 "(SLING-PARTIAL-STOP) …one root under the token that is not a failed pour"
eq "$(meta tk-anc gc.recommended_formula_dispatched)" "mol-fix" "(SLING-PARTIAL-STOP) …and recording the dispatch"
rec; SLING_FAIL=plain run_accept tk-anc
eq "$RC" 1 "(SLING-PLAIN) a sling that poured nothing exits 1"
eq "$(field tk-rec status)" "open" "(SLING-PLAIN) …and the recommendation's gate is reopened"
rec; jq -n '{id:"tk-other-root", title:"mol-fix", status:"open", issue_type:"molecule", at:"tk-anc", formula:"mol-fix", metadata:{}, deps:[]}' > "$STORE/b/tk-other-root.json"
run_accept tk-anc
eq "$RC" 1 "(SLING-REFUSED) a sling Gas City refuses because the formula already runs at the bead exits 1"
has "$OUT" "already runs at tk-anc from another dispatch" "(SLING-REFUSED) …naming the other dispatch"
eq "$(field tk-rec status)" "open" "(SLING-REFUSED) …and the recommendation's gate is reopened"

# --- a sitting takes the recommendation through the same writer --------------
# The REAL converse-signoff.sh, taking the recommendation (--accept), runs the
# REAL gc-helm.sh accept over the same store. The sign-off runs the pack
# scripts beside it, so it runs as a link in a stub pack, where they stand in:
# the headline writes gc.takeaway, the lifecycle writer is the stub above, and
# the PR reminder records nothing.
mkdir -p "$TMP/rig/assets/scripts" "$TMP/cwd"
cat > "$TMP/rig/assets/scripts/gc-helm.sh" <<H
#!/usr/bin/env bash
case "\$1" in
  accept)   exec sh "$SCRIPT" "\$@" ;;
  takeaway) gc bd update "\$2" --set-metadata "gc.takeaway=\$3" >/dev/null ;;
esac
H
cp "$TMP/lifecycle-stub" "$TMP/rig/assets/scripts/lifecycle.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/rig/assets/scripts/pr-sitting-comment.sh"
chmod +x "$TMP/rig/assets/scripts/"*.sh
# Linked after the chmod, which would otherwise follow each link and change the
# mode of the pack's own file.
for _lib in converse-signoff.sh conversation.sh work-outcome.sh bd-lib.sh review-verdict.sh bead-store.sh rig-map.sh; do
    ln -s "$HERE/$_lib" "$TMP/rig/assets/scripts/$_lib"
done
SIGNOFF="$TMP/rig/assets/scripts/converse-signoff.sh"
# sitting — a live sitting holds tk-conv, a conversation on tk-anc that took up
# the recommendation's gate tk-rec.
sitting() {
    bead tk-conv; edge tk-conv tracks tk-anc; edge tk-conv replies-to tk-rec
    jq '.assignee = "gc-toolkit/gc-toolkit.tk-conv" | .status = "in_progress"' "$STORE/b/tk-conv.json" > "$STORE/b/tk-conv.tmp" && mv "$STORE/b/tk-conv.tmp" "$STORE/b/tk-conv.json"
    jq -n '[{id:"gc-50", session_name:"s-gc-50", alias:"gc-toolkit/gc-toolkit.tk-conv", template:"gc-toolkit/gc-toolkit.converse-opus", state:"active", closed:false}]' > "$STORE/sessions.json"
}
# run_take [<arg>...] -> RC, OUT: the sitting's sign-off on the operator's
# ruling to take the recommendation, with any further sign-off args, from a
# cwd outside any checkout.
run_take() {
    set +e
    ( cd "$TMP/cwd" && GC_RIG_ROOT="$TMP/rig" bash "$SIGNOFF" --conversation tk-conv --outcome "mol-fix is taken" \
        --ruled yes --ruling "take the reaction's mol-fix" --route human --no-wait --accept "$@" ) > "$TMP/out" 2>&1; RC=$?
    set -e
    OUT="$(cat "$TMP/out")"
}
# run_answer [<arg>...] -> RC, OUT: the same ruling on a turn that does not sign
# off, answering the recommendation's gate with --answer.
run_answer() {
    set +e
    ( cd "$TMP/cwd" && GC_RIG_ROOT="$TMP/rig" bash "$SIGNOFF" --conversation tk-conv --answer tk-rec \
        --ruling "take the reaction's mol-fix" --outcome "mol-fix is taken; the rollout is still open" --no-wait --accept "$@" ) > "$TMP/out" 2>&1; RC=$?
    set -e
    OUT="$(cat "$TMP/out")"
}
close_roots() { for r in "$STORE"/b/tk-root*.json; do [ -f "$r" ] && { jq '.status = "closed"' "$r" > "$r.tmp" && mv "$r.tmp" "$r"; }; done; return 0; }

echo "# a sitting's take after a board Accept that stopped past its sling dispatches nothing more"
rec; sitting
STOP_AT=after-sling run_accept tk-anc
T="$(token_of tk-rec)"; close_roots
eq "$(roots)" 1 "(SITTING-FINISH) the stopped Accept poured one root, and that root has finished"
eq "$(meta tk-anc gc.recommended_formula)" "mol-fix" "(SITTING-FINISH) …while the bead still carries the recommendation"
SL_BEFORE="$(slings)"
run_take
eq "$RC" 0 "(SITTING-FINISH) the sitting's sign-off taking the recommendation exits 0"
has "$OUT" "an earlier Accept left unfinished ($T)" "(SITTING-FINISH) …finishing the stopped Accept's acceptance under its token"
eq "$(slings)" "$SL_BEFORE" "(SITTING-FINISH) …slinging nothing"
eq "$(roots)" 1 "(SITTING-FINISH) …so the formula still has one root at the bead"
eq "$(meta tk-anc gc.recommended_formula_dispatched)/$(meta tk-anc gc.recommended_formula)" "mol-fix/" "(SITTING-FINISH) …and the dispatch is recorded"
eq "$(field tk-rec close_reason)" "ruled: accepted mol-fix accept:$T" "(SITTING-FINISH) the gate keeps the Accept's answer"
hasnt "$(cat "$CALLS")" "bd gate resolve tk-rec ruled: take" "(SITTING-FINISH) …and the sign-off never resolves it with its own"
eq "$(field tk-conv status)" "closed" "(SITTING-FINISH) the conversation closes"
eq "$(jq -r '[.deps[] | select(.type == "replies-to") | .on] | join(" ")' "$STORE/b/tk-conv.json")" "tk-rec" "(SITTING-FINISH) …keeping its reply onto the gate"
hasnt "$OUT" "warning: a live sitting holds conversation tk-conv" "(SITTING-FINISH) Accept does not warn the sitting of itself"

echo "# a sitting's take before a board Accept: the board's Accept dispatches nothing more"
rec; sitting
run_take
TS="$(token_of tk-rec)"
eq "$RC" 0 "(SITTING-FIRST) a sitting's take on an open gate exits 0"
[ -n "$TS" ] && ok "(SITTING-FIRST) the gate carries an Accept's answer, under the sitting's token" \
  || bad "(SITTING-FIRST) tk-rec's close reason is not an Accept's answer (got '$(field tk-rec close_reason)')"
eq "$(slings)" 1 "(SITTING-FIRST) …and the formula is slung once"
has "$(grep '^sling ' "$CALLS")" "--title mol-fix accept:$TS" "(SITTING-FIRST) …titled with that token"
: > "$CALLS"; run_accept tk-anc
eq "$RC" 2 "(SITTING-FIRST) a board Accept after the take exits 2"
eq "$(writes)" 0 "(SITTING-FIRST) …writing nothing"
eq "$(roots)" 1 "(SITTING-FIRST) …so one root in all"

echo "# a sitting's take after a board Accept that finished: nothing more"
rec; sitting
run_accept tk-anc
SL_BEFORE="$(slings)"
run_take
eq "$RC" 0 "(SITTING-AFTER) a sitting's take after the board's Accept finished exits 0"
has "$OUT" "the recommendation was already taken" "(SITTING-AFTER) …finding it already taken"
eq "$(slings)" "$SL_BEFORE" "(SITTING-AFTER) …slinging nothing"
eq "$(field tk-conv status)" "closed" "(SITTING-AFTER) …and the conversation closes"

echo "# a sitting's take while a board Accept holds the lock stops short, and its re-run finds the take done"
rec; sitting; mkdir -p "$TMP/pS"; rm -f "$TMP/pS"/*
SLING_PAUSE="$TMP/pS" bg_accept board tk-anc; A_PID=$BG_PID
wait_file "$TMP/pS/arrived"
run_take
eq "$RC" 1 "(SITTING-RACE) a take while a board Accept holds the lock stops short"
has "$OUT" "holds its acceptance lock (pid $A_PID" "(SITTING-RACE) …naming the Accept that holds it"
has "$OUT" "the recommendation was not taken" "(SITTING-RACE) …saying nothing was taken"
eq "$(field tk-conv status)" "in_progress" "(SITTING-RACE) …and leaving the conversation open"
touch "$TMP/pS/go"; set +e; wait "$A_PID"; A_RC=$?; set -e
eq "$A_RC" 0 "(SITTING-RACE) the board's Accept then slings and records"
run_take
eq "$RC" 0 "(SITTING-RACE) the take's re-run exits 0"
has "$OUT" "the recommendation was already taken" "(SITTING-RACE) …finding it taken"
eq "$(slings)" 1 "(SITTING-RACE) …one sling in all"
eq "$(field tk-conv status)" "closed" "(SITTING-RACE) …and the conversation closes"

echo "# a sitting's take hands Accept's sling the var its ruling settled"
rec; sitting
run_take --var design_gated=false
TS="$(token_of tk-rec)"
eq "$RC" 0 "(SITTING-VAR) a sitting's take that settles a var exits 0"
has "$(grep '^sling ' "$CALLS")" "--title mol-fix accept:$TS --var design_gated=false" "(SITTING-VAR) …and Accept slings the formula with it"

echo "# a sitting's take that stops after its resolve, finished from the board, keeps the var"
rec; sitting
STOP_AT=resolve run_take --var design_gated=false
TS="$(token_of tk-rec)"
eq "$RC" 1 "(SITTING-VAR-STOP) a take whose Accept stopped after its resolve stops the sign-off short"
eq "$(roots "accept:$TS")" 0 "(SITTING-VAR-STOP) …with nothing poured"
run_accept tk-anc
eq "$RC" 0 "(SITTING-VAR-STOP) the board's Accept finishes the take's acceptance"
has "$(grep '^sling ' "$CALLS" | tail -1)" "--title mol-fix accept:$TS --var design_gated=false" "(SITTING-VAR-STOP) …slinging the var the sitting's ruling settled, so the dispatch is the one the operator ruled"

echo "# a sitting that held its subject: either take releases it before Accept's sling"
# The sign-off releases a held subject itself before it runs Accept's writer,
# which then finds nothing to release. A turn that does not sign off releases
# nothing of its own, so Accept's writer releases the subject.
rec; sitting; held_bead tk-anc
run_take
eq "$RC" 0 "(SITTING-HELD) a sign-off that takes a held subject's recommendation exits 0"
eq "$(meta tk-anc merge_result)" "" "(SITTING-HELD) …releasing the subject"
eq "$(grep -c '^lifecycle transition' "$CALLS")" 1 "(SITTING-HELD) …once, at the sign-off's own release, so Accept's writer finds nothing to release"
case "$(cat "$CALLS")" in
  *"lifecycle transition tk-anc --to unanchored --route human"*"sling tk-anc"*) ok "(SITTING-HELD) …before Accept's sling" ;;
  *) bad "(SITTING-HELD) the release should precede the sling (calls: $(cat "$CALLS"))" ;;
esac
eq "$(slings)" 1 "(SITTING-HELD) …which slings once"
rec; sitting; held_bead tk-anc
run_answer
eq "$RC" 0 "(SITTING-ANSWER-HELD) an --answer turn that takes a held subject's recommendation exits 0"
eq "$(meta tk-anc merge_result)" "" "(SITTING-ANSWER-HELD) …and Accept's writer releases the subject"
case "$(cat "$CALLS")" in
  *"bd gate resolve tk-rec"*"lifecycle transition tk-anc --to unanchored --expect held --route human"*"sling tk-anc"*)
    ok "(SITTING-ANSWER-HELD) …after its answer and before its sling" ;;
  *) bad "(SITTING-ANSWER-HELD) the release should follow the answer and precede the sling (calls: $(cat "$CALLS"))" ;;
esac
eq "$(slings)" 1 "(SITTING-ANSWER-HELD) …slinging once"
eq "$(field tk-conv status)" "in_progress" "(SITTING-ANSWER-HELD) …and the conversation stays open under its sitting"

echo
echo "gc-helm accept: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
