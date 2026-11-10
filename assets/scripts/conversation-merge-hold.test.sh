#!/usr/bin/env bash
# Hermetic test: a conversation on an open PR holds the PR's merge until it
# closes, and otherwise blocks nothing.
#
# A conversation whose subject is an open PR's anchor, or a bead whose
# anchor_bead names one, holds the PR's merge through a plain dependency: the
# anchor depends on the conversation through bd's blocks edge (gc-helm.sh open,
# engage, and the converse hold step). bd lifts the block once the conversation
# closes, so no close path writes a release.
#
# Runs the REAL gc-helm.sh (as `sh`, as shipped) for open and dismiss, the REAL
# converse-signoff.sh, the close block of skills/converse-recheck-premise and the
# hold and lift blocks of skills/converse-hold as the skills write them, and the
# REAL gctk, built from this checkout, for `gctk pr status` and
# `gctk bead holds`, over one file-backed store behind a stubbed `gc`. No live
# city, Dolt, network or sessions. Covered:
#   (OPEN-ANCHOR)  opening a conversation on an open PR's anchor makes the anchor
#                  depend on the conversation and files no gate, and the PR then
#                  derives needs-attention with held: blocked, naming the
#                  conversation
#   (OPEN-JOIN)    a second concern joins the queued conversation, which still
#                  holds the merge through one edge
#   (OPEN-REVIEW)  opening one on the PR's review makes the anchor depend on it,
#                  and leaves the review itself free to dispatch
#   (SIGNOFF, DISMISS, MOOT, BARE-CLOSE) every close of the conversation, the
#                  sign-off, dismiss, the premise re-check's moot close and a
#                  bare `gc bd close`, frees the merge, with no write to the edge
#   (REVIEW-RULING) a ruling in a conversation on the PR's review reaches the PR
#                  whose merge it holds, and its rework is filed against the
#                  anchor and lands before the conversation's close
#   (ANSWER-REWORK) a ruling on a turn that does not sign off files that rework
#                  at once, while the conversation and its hold stay open, and the
#                  rework is free to dispatch
#   (SIGNOFF-RETIRE) a sign-off carrying --retire retires the PR before the close
#   (CLOSE-FAIL)   a close the store refuses both ways leaves the conversation
#                  open, so the merge stays held
#   (LIFT)         a sitting's lift removes the edge and records why on the
#                  conversation, and the PR reads what it did before
#   (HOLD-STEP)    a PR that opened after its conversation started is held from
#                  the hold step's add on
#   (NOT-PR)       a subject that is no open PR, one whose anchor has merged, a
#                  pre-open anchor and a review of one each take no edge
#   (OPEN-UNREAD)  an anchor that does not read files nothing
#   (HOLD-FAIL)    an edge the store refuses exits 4 naming the repair, the reply
#                  onto a gate open was pointed at is written all the same, and
#                  a re-run of open holds the merge
#   (REPLY-FAIL)   a reply onto the gate that the store refuses, for a
#                  conversation open files through a human gate on an open PR
#                  or joins in the queue, exits 4 with the merge held, and the
#                  PR stays held once the gate is answered elsewhere
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-conversation-merge-hold-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 (unexpected '$2' in: $1)" ;; *) ok "$3" ;; esac; }

mkdir -p "$TMP/bin" "$TMP/store/b" "$TMP/rig" "$TMP/cwd" "$TMP/pack/assets/scripts"

# gctk, built from this checkout once: gctk-real derives a PR's status over the
# gc stub below, and the wrapper holds-store.stub.sh prints runs the same build
# with HOLDS_STUB_READ set, which the stub sends to that seam's answer over this
# store, for what holds a bead.
HOLDS_STUB="$HERE/holds-store.stub.sh"
if GCTK_HOLDS="$("$HOLDS_STUB" build "$TMP/gctk" 2>"$TMP/gctk-build.log")"; then
    GCTK="$TMP/gctk/gctk-real"
else
    bad "gctk did not build, so no derivation below was exercised — $(tail -3 "$TMP/gctk-build.log" 2>/dev/null | tr '\n' ' ')"
    GCTK=false; GCTK_HOLDS=false
fi

# --- gc stub ------------------------------------------------------------------
# One JSON file per bead under $STORE/b/<id>.json, its edges as deps
# [{type, on}] on the bead the edge starts from: a blocked bead carries
# {blocks, <blocker>}, a conversation {tracks, <subject>} and {replies-to,
# <gate>}. `bd show` names each edge's far bead whole, as bd does, for one id or
# several, and `bd list` names each edge as {issue_id, depends_on_id, type}.
# `bd create` mints tk-c<n>, and `bd gate resolve` closes a gate. Every write is
# appended to $CALLS. A read gctk makes with HOLDS_STUB_READ set is answered by
# holds-store.stub.sh over this store's rows. Hooks: SHOW_DOWN=<id> fails a
# show naming that bead; DEP_ADD_FAIL refuses every `blocks` edge add, and
# REPLY_FAIL every `replies-to` edge add, writing nothing; CLOSE_FAIL=<id>
# refuses every close of that bead, plain or forced, writing nothing.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
B="$STORE/b"
log() { printf '%s\n' "$*" >> "$CALLS"; }
row() { cat "$B/$1.json" 2>/dev/null; }
put() { cat > "$B/$1.json.tmp" && mv "$B/$1.json.tmp" "$B/$1.json"; }
all_ids() { for f in "$B"/*.json; do [ -f "$f" ] && basename "$f" .json; done; }
mint() { local n; n=$(( $(cat "$STORE/seq" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$STORE/seq"; printf '%s%s' "$1" "$n"; }
stamp() { printf '2026-11-09T00:%02d:00Z' "$(cat "$STORE/seq" 2>/dev/null || echo 0)"; }
show_row() {
  local r d far deps='[]'
  r=$(row "$1") || return 1
  for d in $(printf '%s' "$r" | jq -r '.deps[] | "\(.type)|\(.on)"'); do
    far=$(row "${d#*|}" | jq -c 'del(.deps)' 2>/dev/null) || far=""
    [ -n "$far" ] || far=$(jq -nc --arg i "${d#*|}" '{id: $i}')
    deps=$(printf '%s' "$deps" | jq -c --argjson f "$far" --arg t "${d%%|*}" '. + [$f + {dependency_type: $t}]')
  done
  printf '%s' "$r" | jq -c --argjson d "$deps" '. + {dependencies: $d} | del(.deps)'
}
list_row() { row "$1" | jq -c '. + {dependencies: [ .deps[] as $d | {issue_id: .id, depends_on_id: $d.on, type: $d.type} ]} | del(.deps)'; }
add_dep() { # <bead> <type> <on>
  row "$1" | jq -c --arg t "$2" --arg o "$3" 'if any(.deps[]; .type == $t and .on == $o) then . else .deps += [{type: $t, on: $o}] end' | put "$1"
}
if [ -n "${HOLDS_STUB_READ:-}" ] && [ "${1:-}" = bd ]; then
  shift
  for i in $(all_ids); do list_row "$i"; done | jq -sc '.' > "$STORE/holds.json"
  HOLDS_STORE="$STORE/holds.json" exec "$HOLDS_STUB" answer "$@"
fi
case "$1 ${2:-}" in
  "rig list")
    jq -n --arg p "$RIG_DIR" '{rigs: [{name: "gc-toolkit", prefix: "tk", path: $p, hq: false}]}' ;;
  "session list") printf '{"sessions":[]}\n' ;;
  "runtime drain-ack") log "$*" ;;
  "bd show")
    shift 2
    _out='[]'; _any=0
    for a in "$@"; do
      case "$a" in --*) continue ;; esac
      [ -n "${SHOW_DOWN:-}" ] && [ "$a" = "$SHOW_DOWN" ] && { echo "bd show: data plane down" >&2; exit 1; }
      [ -f "$B/$a.json" ] || continue
      _any=1; _out=$(printf '%s' "$_out" | jq -c --argjson r "$(show_row "$a")" '. + [$r]')
    done
    [ "$_any" = 1 ] || { printf '{"error":"no issues found matching the provided IDs"}\n'; exit 1; }
    printf '%s\n' "$_out" ;;
  "bd list")
    shift 2
    _ids=""; _st=""; _all=0; _fields=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --id) _ids="${2:-}"; shift ;;
        --id=*) _ids="${1#--id=}" ;;
        --status) _st="${2:-}"; shift ;;
        --status=*) _st="${1#--status=}" ;;
        --metadata-field) _fields+=("${2:-}"); shift ;;
        --all) _all=1 ;;
      esac
      shift
    done
    for i in $(all_ids); do
      if [ -n "$_ids" ]; then case ",$_ids," in *",$i,"*) ;; *) continue ;; esac; fi
      list_row "$i"
    done | jq -sc --arg st "$_st" --argjson all "$_all" --arg ids "$_ids" --args '
      ($ARGS.positional | map(split("=") | {k: .[0], v: (.[1:] | join("="))})) as $f
      | [ .[] | (.status // "open") as $s
          | select($st == "" or (($st | split(",")) | index($s)))
          | select($st != "" or $all == 1 or $ids != "" or $s != "closed")
          | select($ids != "" or (.issue_type // "") != "gate")
          | . as $r | select(all($f[]; ((($r.metadata // {})[.k]) // "" | tostring) == .v)) ]' \
      ${_fields[@]+"${_fields[@]}"} ;;
  "bd dep")
    case "$3" in
      list)
        _who="$4"; _ty=""; _dir=down; _p=""
        for a in "$@"; do
          case "$a" in --direction=*) _dir="${a#--direction=}" ;; --type=*) _ty="${a#--type=}" ;; esac
          { [ "$_p" = "--type" ] || [ "$_p" = "-t" ]; } && _ty="$a"
          [ "$_p" = "--direction" ] && _dir="$a"
          _p="$a"
        done
        [ -f "$B/$_who.json" ] || { printf '{"error":"not found: issue %s"}\n' "$_who"; exit 1; }
        if [ "$_dir" = up ]; then
          for i in $(all_ids); do
            row "$i" | jq -c --arg w "$_who" --arg t "$_ty" '[ .deps[] | select(.on == $w and ($t == "" or .type == $t)) | .type ] as $ts
              | select(($ts | length) > 0) | del(.deps) + {dependency_type: $ts[0]}'
          done | jq -sc '.'
        else
          for d in $(row "$_who" | jq -r --arg t "$_ty" '.deps[] | select($t == "" or .type == $t) | "\(.type)|\(.on)"'); do
            row "${d#*|}" | jq -c --arg t "${d%%|*}" 'del(.deps) + {dependency_type: $t}'
          done | jq -sc '.'
        fi ;;
      add)
        log "$*"
        _a="$4"; _b="$5"; _t="blocks"; _p=""
        for a in "$@"; do { [ "$_p" = "--type" ] || [ "$_p" = "-t" ]; } && _t="$a"; case "$a" in --type=*) _t="${a#--type=}" ;; esac; _p="$a"; done
        [ -f "$B/$_a.json" ] && [ -f "$B/$_b.json" ] || { echo "Error: issue not found" >&2; exit 1; }
        [ -n "${DEP_ADD_FAIL:-}" ] && [ "$_t" = blocks ] && { echo "Error adding dependency: simulated refusal" >&2; exit 1; }
        [ -n "${REPLY_FAIL:-}" ] && [ "$_t" = replies-to ] && { echo "Error adding dependency: simulated refusal" >&2; exit 1; }
        add_dep "$_a" "$_t" "$_b" ;;
      remove)
        log "$*"
        [ -f "$B/$4.json" ] || { echo "Error: issue not found" >&2; exit 1; }
        row "$4" | jq -c --arg o "$5" '.deps |= map(select(.on != $o))' | put "$4" ;;
      *) log "$*" ;;
    esac ;;
  "bd create")
    log "$*"
    shift 2
    _t=""; _d=""; _deps=""; _a=""; _ty=task; _m='{}'
    while [ $# -gt 0 ]; do
      case "$1" in
        --title) _t="$2"; shift ;;
        -d|--description) _d="$2"; shift ;;
        --deps) _deps="$2"; shift ;;
        --assignee) _a="$2"; shift ;;
        -t|--type) _ty="$2"; shift ;;
        --metadata) _m="$2"; shift ;;
      esac
      shift
    done
    _id=$(mint tk-c)
    jq -nc --arg i "$_id" --arg t "$_t" --arg d "$_d" --arg a "$_a" --arg ty "$_ty" --arg at "$(stamp)" --argjson m "$_m" \
      '{id: $i, title: $t, description: $d, notes: "", status: "open", issue_type: $ty, assignee: $a, created_at: $at, metadata: $m, deps: []}' | put "$_id"
    for dep in $(printf '%s' "$_deps" | tr ',' ' '); do add_dep "$_id" "${dep%%:*}" "${dep#*:}"; done
    printf '{"id":"%s"}\n' "$_id" ;;
  "bd gate")
    case "$3" in
      resolve)
        log "$*"
        _g="$4"; _r=""; _p=""
        for a in "$@"; do [ "$_p" = "--reason" ] && _r="$a"; _p="$a"; done
        if [ "$(row "$_g" | jq -r .status)" != closed ]; then
          row "$_g" | jq -c --arg r "$_r" '.status = "closed" | .close_reason = $r' | put "$_g"
        fi
        echo "✓ Gate resolved: $_g" ;;
      *) log "$*" ;;
    esac ;;
  "bd update")
    log "$*"
    _id="$3"; shift 3
    _r=$(row "$_id") || { echo "bd update: no such issue $_id" >&2; exit 1; }
    _args=("$@"); _i=0
    while [ "$_i" -lt "${#_args[@]}" ]; do
      case "${_args[$_i]}" in
        --if-assignee) [ "$(printf '%s' "$_r" | jq -r '.assignee // ""')" = "${_args[$((_i + 1))]}" ] || exit 13 ;;
        --if-status) [ "$(printf '%s' "$_r" | jq -r '.status // ""')" = "${_args[$((_i + 1))]}" ] || exit 13 ;;
      esac
      _i=$((_i + 1))
    done
    while [ $# -gt 0 ]; do
      case "$1" in
        --set-metadata) _k="${2%%=*}"; _v="${2#*=}"; _r=$(printf '%s' "$_r" | jq -c --arg k "$_k" --arg v "$_v" '.metadata[$k] = $v'); shift 2 ;;
        --unset-metadata) _r=$(printf '%s' "$_r" | jq -c --arg k "$2" 'del(.metadata[$k])'); shift 2 ;;
        --assignee) _r=$(printf '%s' "$_r" | jq -c --arg v "$2" '.assignee = $v'); shift 2 ;;
        --assignee=*) _r=$(printf '%s' "$_r" | jq -c --arg v "${1#--assignee=}" '.assignee = $v'); shift ;;
        --status) _r=$(printf '%s' "$_r" | jq -c --arg v "$2" '.status = $v'); shift 2 ;;
        --status=*) _r=$(printf '%s' "$_r" | jq -c --arg v "${1#--status=}" '.status = $v'); shift ;;
        --description) _r=$(printf '%s' "$_r" | jq -c --arg v "$2" '.description = $v'); shift 2 ;;
        --append-notes) _r=$(printf '%s' "$_r" | jq -c --arg v "$2" '.notes = (if (.notes // "") == "" then $v else .notes + "\n" + $v end)'); shift 2 ;;
        --if-assignee|--if-status) shift 2 ;;
        *) shift ;;
      esac
    done
    printf '%s' "$_r" | put "$_id" ;;
  "bd close")
    log "$*"
    [ -n "${CLOSE_FAIL:-}" ] && [ "$3" = "$CLOSE_FAIL" ] && { echo "bd close: simulated refusal of $3" >&2; exit 1; }
    _id="$3"; _r=""; _p=""
    for a in "$@"; do [ "$_p" = "--reason" ] && _r="$a"; _p="$a"; done
    row "$_id" | jq -c --arg r "$_r" '.status = "closed" | .close_reason = $r' | put "$_id" ;;
  "bd comments") cat "$B/$3.comments.json" 2>/dev/null || printf '[]\n' ;;
  "bd comment")
    log "$*"
    _c=$(cat "$B/$3.comments.json" 2>/dev/null || printf '[]')
    printf '%s' "$_c" | jq -c --arg t "$4" '. + [{text: $t}]' > "$B/$3.comments.json" ;;
  *) echo "gc stub: unsupported '$*'" >&2; exit 2 ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

# gh answers nothing, so no call reaches a network.
printf '#!/bin/sh\nexit 1\n' > "$TMP/bin/gh"
chmod +x "$TMP/bin/gh"

# --- the pack the sign-off and the premise re-check run from --------------------
# The real scripts these writers are, linked beside the stand-ins for the PR's
# rework, its retirement and the visit's PR comment, which log what they do.
# converse-rework.sh files a rework child that blocks the anchor, as
# rework-child.sh does, and pr-dispose.sh records the disposition.
P="$TMP/pack/assets/scripts"
cat > "$P/converse-rework.sh" <<'R'
#!/usr/bin/env bash
printf 'converse-rework %s\n' "$*" >> "$CALLS"
_a=""; _p=""; for a in "$@"; do [ "$_p" = "--anchor" ] && _a="$a"; _p="$a"; done
_c=$(gc bd create -t task --title "rework $_a" --metadata "{\"task_kind\":\"rework\",\"anchor_bead\":\"$_a\"}" --json | jq -r .id)
gc bd dep add "$_a" "$_c" --type blocks >/dev/null
echo "$_c gc-toolkit/gc-toolkit.polecat filed"
R
cat > "$P/pr-dispose.sh" <<'D'
#!/usr/bin/env bash
printf 'pr-dispose %s\n' "$*" >> "$CALLS"
_a=""; _k=""; _p=""; for a in "$@"; do [ "$_p" = "--anchor" ] && _a="$a"; [ "$_p" = "--kind" ] && _k="$a"; _p="$a"; done
gc bd update "$_a" --set-metadata "gc.pr_close_disposition_kind=$_k" >/dev/null
echo "pr-dispose: closed the PR of $_a as $_k"
D
cat > "$P/pr-sitting-comment.sh" <<'C'
#!/usr/bin/env bash
printf 'pr-sitting-comment %s\n' "$*" >> "$CALLS"
C
chmod +x "$P"/*.sh
for _s in converse-signoff.sh gc-helm.sh human-gate.sh conversation.sh work-outcome.sh bd-lib.sh \
          review-verdict.sh review-dismissal.sh bead-store.sh rig-map.sh; do
    ln -s "$HERE/$_s" "$P/$_s"
done

export PATH="$TMP/bin:$PATH" STORE="$TMP/store" CALLS="$TMP/calls" RIG_DIR="$TMP/rig" HOLDS_STUB
export GC_SITTING_COMMENT_TOOL="$P/pr-sitting-comment.sh" GC_NO_API=1 TMPDIR="$TMP"
unset GC_HELM_FIXTURE GC_RIG GC_RIG_ROOT BEADS_DIR GC_SESSION_ID GC_SESSION_NAME GC_ALIAS GC_CITY GC_CITY_PATH GC_CITY_ROOT 2>/dev/null || true

# --- fixtures -----------------------------------------------------------------
fresh() { rm -rf "$STORE"; mkdir -p "$STORE/b"; : > "$CALLS"; }
# bead <id> [type] [status] [metadata-json]
bead() {
    jq -nc --arg i "$1" --arg t "${2:-task}" --arg s "${3:-open}" --argjson m "${4:-"{}"}" \
        '{id: $i, title: ("the bead " + $i), description: "", notes: "", issue_type: $t, status: $s, assignee: "", created_at: "2026-11-08T00:00:00Z", metadata: $m, deps: []}' \
        > "$STORE/b/$1.json"
}
setf() { jq -c --arg k "$2" --arg v "$3" '.[$k] = $v' "$STORE/b/$1.json" > "$STORE/b/x" && mv "$STORE/b/x" "$STORE/b/$1.json"; }
setm() { jq -c --arg k "$2" --arg v "$3" '.metadata[$k] = $v' "$STORE/b/$1.json" > "$STORE/b/x" && mv "$STORE/b/x" "$STORE/b/$1.json"; }
edge() { jq -c --arg t "$2" --arg o "$3" '.deps += [{type: $t, on: $o}]' "$STORE/b/$1.json" > "$STORE/b/x" && mv "$STORE/b/x" "$STORE/b/$1.json"; }
field() { jq -r --arg k "$2" '.[$k] // "" | tostring' "$STORE/b/$1.json" 2>/dev/null; }
deps_of() { jq -r --arg t "$2" '[ .deps[] | select(.type == $t) | .on ] | sort | join(" ")' "$STORE/b/$1.json" 2>/dev/null; }
acts() { jq -r '[.[].text] | join("|")' "$STORE/b/$1.comments.json" 2>/dev/null; }
# An open PR's anchor, and the PR's review in flight.
pr() { fresh; bead tk-anc task open '{"merge_result":"pull_request","pr_number":"41"}'; }
pr_review() { pr; bead tk-rev task open '{"task_kind":"review","anchor_bead":"tk-anc"}'; }
# gate_on <bead> <gate> — an open human gate the bead waits on.
gate_on() {
    bead "$2" gate open; setf "$2" await_type human; setf "$2" await_id "review-needs-you.$2"
    setf "$2" title "should this land as built?"; edge "$1" blocks "$2"
}
# filed_on <bead> — the conversation that tracks the bead, read from the store.
filed_on() { jq -r --arg b "$1" 'objects | select((.deps // []) | any(.type == "tracks" and .on == $b)) | .id' "$STORE"/b/*.json | head -1; }
derive() { (cd "$TMP/cwd" && "$GCTK" pr status "$1" --json 2>/dev/null) || echo "derive-failed"; }
status_of() { derive "$1" | jq -r '"\(.status) [\(.held | join(","))]"' 2>/dev/null; }
# holds_of <bead> — what holds the bead by gctk bead holds, the rule the work
# gate at load-context and every reader of a bead's waits share: its status,
# then the waits of its own that have not landed.
holds_of() {
    (cd "$TMP/cwd" && "$GCTK_HOLDS" bead holds "$1" 2>/dev/null) \
        | jq -r '"\(.status) \([.pending[]?.id] | join(","))"' 2>/dev/null || echo "holds-failed"
}
# no_release — the calls since the last reset wrote nothing to the edge or to a
# gate: no dep remove, no gate write.
no_release() { ! grep -qE '^bd dep remove |^bd gate ' "$CALLS"; }
# run_open <args...> -> RC, OUT (stdout), ERR (stderr)
run_open() {
    set +e
    OUT="$(cd "$TMP/cwd" && sh "$HERE/gc-helm.sh" open "$@" 2>"$TMP/err")"; RC=$?
    ERR="$(cat "$TMP/err")"
    set -e
}
opened_conv() { printf '%s' "$OUT" | jq -r '.conversation // empty' 2>/dev/null; }
run_signoff() {
    set +e
    OUT="$(cd "$TMP/cwd" && bash "$P/converse-signoff.sh" "$@" 2>&1)"; RC=$?
    set -e
}
run_dismiss() {
    set +e
    OUT="$(cd "$TMP/cwd" && sh "$HERE/gc-helm.sh" dismiss "$@" 2>&1)"; RC=$?
    set -e
}
# skill_block <skill> <marker> — the fenced bash block of the skill that holds
# <marker>, as the skill writes it.
skill_block() {
    awk -v m="$2" '/^```bash[ \t]*$/ { inb = 1; buf = ""; hit = 0; next }
         inb && /^```[ \t]*$/ { if (hit) { printf "%s", buf; exit } inb = 0; next }
         inb { buf = buf $0 "\n"; if (index($0, m)) hit = 1 }' "$ROOT/skills/$1/SKILL.md"
}
# The premise re-check's close, a moot reading filled in for its placeholders.
skill_block converse-recheck-premise 'closed $CONVERSATION as $KIND' \
    | sed -e 's#KIND="<moot|benign>"#KIND="moot"#' \
          -e 's#WHY="<[^>]*>"#WHY="the PR it asked about was answered on GitHub"#' \
          -e 's#ACTION="<[^>]*>"#ACTION="The visit ended: its question was already answered."#' > "$TMP/moot-close.sh"
[ -s "$TMP/moot-close.sh" ] && ok "the premise re-check's close is found in the skill" \
    || bad "the premise re-check's close is found in the skill"
# The hold step's add and its lift, the anchor filled in.
skill_block converse-hold 'gc bd dep add "$ANCHOR" "$CONVERSATION" --type blocks' \
    | sed -e 's#ANCHOR="<[^>]*>"#ANCHOR="tk-anc"#' > "$TMP/hold-add.sh"
skill_block converse-hold 'gc bd dep remove "$ANCHOR" "$CONVERSATION"' \
    | sed -e 's#ANCHOR="<[^>]*>"#ANCHOR="tk-anc"#' \
          -e 's#WHY="<[^>]*>"#WHY="the operator opened this to get the PR merged"#' > "$TMP/hold-lift.sh"
[ -s "$TMP/hold-add.sh" ] && [ -s "$TMP/hold-lift.sh" ] && ok "the hold step's add and lift are found in the skill" \
    || bad "the hold step's add and lift are found in the skill"
run_block() { # <file> <conversation> <subject>
    set +e
    OUT="$(cd "$TMP/cwd" && GCTK_BIN="$GCTK_HOLDS" CONV="$P" CONVERSATION="$2" SUBJECT="$3" bash "$1" 2>&1)"; RC=$?
    set -e
}
# lands_before <a> <b> — the first call in $CALLS that carries <a> was made
# before the first that carries <b>, and both were made.
lands_before() {
    _la=$(grep -n -F -- "$1" "$CALLS" | head -1 | cut -d: -f1)
    _lb=$(grep -n -F -- "$2" "$CALLS" | head -1 | cut -d: -f1)
    [ -n "$_la" ] && [ -n "$_lb" ] && [ "$_la" -lt "$_lb" ]
}
# rework_of <anchor> — the rework child the stand-in filed against the anchor.
rework_of() {
    for f in "$STORE"/b/*.json; do
        jq -r --arg a "$1" 'select((.metadata.task_kind // "") == "rework" and (.metadata.anchor_bead // "") == $a) | .id' "$f"
    done | head -1
}

echo "# opening a conversation on an open PR's anchor holds the PR's merge"
pr
eq "$(status_of tk-anc)" "needs-review []" "(OPEN-ANCHOR) before any conversation, the PR reads needs-review"
run_open tk-anc --reason "should this land as built?" --json
C=$(opened_conv)
eq "$RC" 0 "(OPEN-ANCHOR) open exits 0"
eq "$(deps_of tk-anc blocks)" "$C" "(OPEN-ANCHOR) the anchor depends on the conversation through a blocks edge"
eq "$(deps_of "$C" tracks)" "tk-anc" "(OPEN-ANCHOR) …and the conversation tracks the anchor, its subject"
hasnt "$(cat "$CALLS")" "bd gate" "(OPEN-ANCHOR) …and no gate is filed"
has "$ERR" "conversation $C holds the merge of the PR of tk-anc until it closes" "(OPEN-ANCHOR) open says the conversation holds the merge"
eq "$(derive tk-anc | jq -c '{status, held, reasons: [.reasons[] | .id]}')" "{\"status\":\"needs-attention\",\"held\":[\"blocked\"],\"reasons\":[\"$C\"]}" \
    "(OPEN-ANCHOR) gctk pr status then reads needs-attention with held: blocked, naming the conversation"
eq "$(holds_of tk-anc)" "blocked $C" "(OPEN-ANCHOR) …and gctk bead holds reads the anchor blocked by the conversation"

echo "# a second concern joins the queued conversation, which still holds the merge"
: > "$CALLS"
run_open tk-anc --reason "and the docs?"
eq "$RC" 0 "(OPEN-JOIN) the second open exits 0"
has "$OUT" "conversation $C is already open for tk-anc" "(OPEN-JOIN) …joining the queued conversation"
eq "$(deps_of tk-anc blocks)" "$C" "(OPEN-JOIN) …and one edge still holds the anchor"

echo "# the sign-off closes the conversation, and the close frees the merge"
: > "$CALLS"
run_signoff --conversation "$C" --outcome "lands as built" --ruled yes --ruling "it lands as built" --no-wait --no-rework
eq "$RC" 0 "(SIGNOFF) the sign-off exits 0"
eq "$(field "$C" status)" "closed" "(SIGNOFF) the conversation is closed"
no_release && ok "(SIGNOFF) …and nothing is written to release the merge" \
    || bad "(SIGNOFF) …and nothing is written to release the merge ($(tr '\n' ';' < "$CALLS"))"
eq "$(status_of tk-anc)" "needs-review []" "(SIGNOFF) the PR derives what it did before the conversation opened"
eq "$(holds_of tk-anc)" "clear " "(SIGNOFF) …and nothing holds the anchor, though the edge onto the closed conversation stays"

echo "# dismiss closes the conversation, and the close frees the merge"
pr; run_open tk-anc --json; C=$(opened_conv)
: > "$CALLS"
run_dismiss "$C" --reason "done here"
eq "$RC" 0 "(DISMISS) dismiss exits 0"
eq "$(field "$C" status)" "closed" "(DISMISS) the conversation is closed"
no_release && ok "(DISMISS) …with nothing written to release the merge" \
    || bad "(DISMISS) …with nothing written to release the merge ($(tr '\n' ';' < "$CALLS"))"
eq "$(status_of tk-anc)" "needs-review []" "(DISMISS) the PR derives what it did before the conversation opened"

echo "# the premise re-check's moot close frees the merge, and the conversation keeps no headline"
pr; run_open tk-anc --json; C=$(opened_conv)
setm tk-anc gc.takeaway "holding — should this land as built?"
: > "$CALLS"
run_block "$TMP/moot-close.sh" "$C" tk-anc
eq "$RC" 0 "(MOOT) the moot close exits 0"
has "$OUT" "closed $C as moot" "(MOOT) …closing the conversation"
has "$OUT" "replaced the headline of tk-anc, which waited on nothing" "(MOOT) …and the conversation, about to close, kept no headline"
no_release && ok "(MOOT) …with nothing written to release the merge" \
    || bad "(MOOT) …with nothing written to release the merge ($(tr '\n' ';' < "$CALLS"))"
eq "$(status_of tk-anc)" "needs-review []" "(MOOT) the PR derives what it did before the conversation opened"

echo "# a bare close of the conversation frees the merge too"
pr; run_open tk-anc --json; C=$(opened_conv)
gc bd close "$C" --reason "closed by hand" >/dev/null
eq "$(status_of tk-anc)" "needs-review []" "(BARE-CLOSE) a gc bd close by hand frees the merge"
eq "$(holds_of tk-anc)" "clear " "(BARE-CLOSE) …and nothing holds the anchor"

echo "# a conversation on the PR's review holds the anchor's merge, and the review goes on"
pr_review
eq "$(status_of tk-anc)" "working []" "(OPEN-REVIEW) with its review in flight, the PR reads working"
run_open tk-rev --reason "is this review stuck?" --json
C=$(opened_conv)
eq "$RC" 0 "(OPEN-REVIEW) open exits 0"
eq "$(deps_of tk-anc blocks)" "$C" "(OPEN-REVIEW) the anchor the review names depends on the conversation"
eq "$(deps_of "$C" tracks)" "tk-rev" "(OPEN-REVIEW) …which tracks the review"
eq "$(deps_of tk-rev blocks)" "" "(OPEN-REVIEW) the review itself waits on nothing"
eq "$(holds_of tk-rev)" "clear " "(OPEN-REVIEW) …so gctk bead holds reads it clear, and it keeps dispatching"
eq "$(status_of tk-anc)" "needs-attention [blocked]" "(OPEN-REVIEW) the PR reads needs-attention, held: blocked"

echo "# a ruling in a conversation on the PR's review says what it does to the PR"
: > "$CALLS"
run_signoff --conversation "$C" --outcome "sent back" --ruled yes --ruling "fix the retry first" --no-wait
eq "$RC" 2 "(REVIEW-RULING) a ruling that gives no answer for the PR whose merge the conversation holds exits 2"
has "$OUT" "as the PR whose merge this conversation holds" "(REVIEW-RULING) …naming the PR it reaches that way"
eq "$(grep -c '' "$CALLS" | tr -d ' ')" "0" "(REVIEW-RULING) …writing nothing"
run_signoff --conversation "$C" --outcome "sent back for the retry" --ruled yes --ruling "fix the retry first" --no-wait --rework
eq "$RC" 0 "(REVIEW-RULING) with --rework it exits 0"
has "$(cat "$CALLS")" "converse-rework --anchor tk-anc --ruling-bead $C" "(REVIEW-RULING) the rework is filed against the PR's anchor"
lands_before "converse-rework " "bd close $C " \
    && ok "(REVIEW-RULING) …and lands before the conversation's close, so the merge is never free in between" \
    || bad "(REVIEW-RULING) …and lands before the conversation's close ($(tr '\n' ';' < "$CALLS"))"
RW=$(rework_of tk-anc)
eq "$(field "$C" status)" "closed" "(REVIEW-RULING) the conversation is closed"
eq "$(holds_of tk-anc)" "blocked $RW" "(REVIEW-RULING) the anchor now waits on the rework alone"
eq "$(status_of tk-anc)" "working []" "(REVIEW-RULING) …so the PR reads working"

echo "# a ruling on a turn that does not sign off files the rework at once, and the rework goes on"
pr_review
bead tk-q gate open; setf tk-q await_type human; setf tk-q await_id "review-needs-you.tk-q"; setf tk-q title "is the retry in scope?"
edge tk-rev blocks tk-q
run_open tk-rev --reason "is the retry in scope?" --json
C=$(opened_conv); edge "$C" replies-to tk-q
: > "$CALLS"
run_signoff --conversation "$C" --answer tk-q --ruling "fix the retry first" \
    --outcome "ruled on the retry; the conversation stays open" --no-wait --rework
eq "$RC" 0 "(ANSWER-REWORK) the answer exits 0"
eq "$(field tk-q status)" "closed" "(ANSWER-REWORK) the gate it names is answered"
has "$(cat "$CALLS")" "converse-rework --anchor tk-anc --ruling-bead $C" "(ANSWER-REWORK) the rework is filed against the PR's anchor at once"
RW=$(rework_of tk-anc)
eq "$(field "$C" status)" "open" "(ANSWER-REWORK) the conversation stays open"
eq "$(holds_of tk-anc)" "blocked $C,$RW" "(ANSWER-REWORK) …so its hold stands beside the rework's"
eq "$(holds_of "$RW")" "clear " "(ANSWER-REWORK) the rework waits on nothing, so it dispatches while the merge waits"
eq "$(holds_of tk-rev)" "clear " "(ANSWER-REWORK) …and so does the review, its question answered"

echo "# a sign-off carrying --retire retires the PR before the conversation closes"
pr; run_open tk-anc --json; C=$(opened_conv)
: > "$CALLS"
run_signoff --conversation "$C" --outcome "will not land" --ruled yes --ruling "the work moved to the new design" --no-wait \
    --retire re-homed --successor tk-new
eq "$RC" 0 "(SIGNOFF-RETIRE) the sign-off exits 0"
lands_before "pr-dispose " "bd close $C " \
    && ok "(SIGNOFF-RETIRE) the PR is retired before the conversation's close" \
    || bad "(SIGNOFF-RETIRE) the PR is retired before the conversation's close ($(tr '\n' ';' < "$CALLS"))"

echo "# a close the store refuses leaves the merge held"
pr; run_open tk-anc --json; C=$(opened_conv)
CLOSE_FAIL="$C" run_signoff --conversation "$C" --outcome "lands as built" --ruled yes --ruling "it lands as built" --no-wait --no-rework
[ "$RC" -ne 0 ] && ok "(CLOSE-FAIL) a sign-off whose close is refused both ways fails" || bad "(CLOSE-FAIL) a sign-off whose close is refused both ways fails (exit $RC)"
eq "$(field "$C" status)" "open" "(CLOSE-FAIL) the conversation stays open"
eq "$(status_of tk-anc)" "needs-attention [blocked]" "(CLOSE-FAIL) …so the merge stays held"
CLOSE_FAIL="$C" run_block "$TMP/moot-close.sh" "$C" tk-anc
hasnt "$OUT" "closed $C as moot" "(CLOSE-FAIL) a moot close the store refuses stops short of its closed line"
eq "$(status_of tk-anc)" "needs-attention [blocked]" "(CLOSE-FAIL) …and the merge stays held"

echo "# a sitting that is helping the PR land lifts the hold"
pr; run_open tk-anc --json; C=$(opened_conv)
: > "$CALLS"
run_block "$TMP/hold-lift.sh" "$C" tk-anc
eq "$RC" 0 "(LIFT) the lift exits 0"
has "$OUT" "the merge of tk-anc no longer waits for this conversation" "(LIFT) …saying the merge no longer waits"
eq "$(deps_of tk-anc blocks)" "" "(LIFT) the anchor's edge onto the conversation is gone"
eq "$(acts "$C")" "Lifted the hold on the PR's merge: the operator opened this to get the PR merged" "(LIFT) …and the conversation records why, among the visit's actions"
eq "$(field "$C" status)" "open" "(LIFT) the conversation stays open"
eq "$(status_of tk-anc)" "needs-review []" "(LIFT) the PR reads what it did before the conversation opened"
run_block "$TMP/hold-lift.sh" "$C" tk-anc
eq "$RC" 0 "(LIFT) a second lift, with no edge left to remove, still exits 0"

echo "# a PR that opened after its conversation started is held from the hold step on"
fresh; bead tk-anc task open '{"merge_result":"pre_open_gate"}'
run_open tk-anc --json; C=$(opened_conv)
eq "$(deps_of tk-anc blocks)" "" "(HOLD-STEP) a conversation on a pre-open anchor takes no edge, which would stop the work"
setm tk-anc merge_result pull_request; setm tk-anc pr_number 41
run_block "$TMP/hold-add.sh" "$C" tk-anc
eq "$RC" 0 "(HOLD-STEP) the hold step's add exits 0 once the PR has opened"
has "$OUT" "the merge of tk-anc waits for this conversation" "(HOLD-STEP) …saying the merge waits"
eq "$(deps_of tk-anc blocks)" "$C" "(HOLD-STEP) the anchor now depends on the conversation"
run_block "$TMP/hold-add.sh" "$C" tk-anc
eq "$RC/$(deps_of tk-anc blocks)" "0/$C" "(HOLD-STEP) a second hold adds no second edge"
eq "$(status_of tk-anc)" "needs-attention [blocked]" "(HOLD-STEP) the PR reads needs-attention, held: blocked"

echo "# a subject that is no open PR takes no edge"
fresh; bead tk-plain
run_open tk-plain --json
eq "$RC" 0 "(NOT-PR) a plain subject's conversation is filed"
hasnt "$(cat "$CALLS")" "--type blocks" "(NOT-PR) …and nothing is added for a merge"
fresh; bead tk-anc task closed '{"merge_result":"merged"}'; bead tk-rev task open '{"task_kind":"review","anchor_bead":"tk-anc"}'
run_open tk-rev --json
eq "$RC" 0 "(NOT-PR) a conversation on the review of a merged PR is filed"
hasnt "$(cat "$CALLS")" "--type blocks" "(NOT-PR) …and takes no edge"
fresh; bead tk-anc task open '{"merge_result":"pre_open_gate"}'; bead tk-rev task open '{"task_kind":"review","anchor_bead":"tk-anc"}'
run_open tk-rev --json
hasnt "$(cat "$CALLS")" "--type blocks" "(NOT-PR) a review of a pre-open anchor takes no edge either"

echo "# an anchor that does not read files nothing"
pr_review
SHOW_DOWN=tk-anc run_open tk-rev --json
eq "$RC" 4 "(OPEN-UNREAD) an anchor that does not read exits 4"
has "$ERR" "could not read tk-anc, the anchor tk-rev names" "(OPEN-UNREAD) …saying so"
hasnt "$(cat "$CALLS")" "bd create" "(OPEN-UNREAD) …and files no conversation"

echo "# an edge the store refuses is reported, and a re-run of open holds the merge"
pr
DEP_ADD_FAIL=1 run_open tk-anc --json
eq "$RC" 4 "(HOLD-FAIL) an edge the store refuses exits 4"
C=$(filed_on tk-anc)
[ -n "$C" ] && ok "(HOLD-FAIL) …with the conversation filed" || bad "(HOLD-FAIL) …with the conversation filed"
has "$ERR" "gc bd dep add tk-anc $C --type blocks" "(HOLD-FAIL) …naming the edge to add by hand"
eq "$(deps_of tk-anc blocks)" "" "(HOLD-FAIL) …and no edge holds the anchor yet"
run_open tk-anc --json
eq "$RC/$(deps_of tk-anc blocks)" "0/$C" "(HOLD-FAIL) a re-run of open joins that conversation and holds the merge"
pr; gate_on tk-anc tk-q
DEP_ADD_FAIL=1 run_open tk-q --json
eq "$RC" 4 "(HOLD-FAIL) an edge the store refuses on a conversation open files through a gate exits 4"
C=$(filed_on tk-anc)
has "$ERR" "gc bd dep add tk-anc $C --type blocks" "(HOLD-FAIL) …naming the edge to add by hand"
eq "$(deps_of "$C" replies-to)" "tk-q" "(HOLD-FAIL) …and the conversation replies to the gate all the same"

echo "# a reply onto the gate that the store refuses leaves the merge held"
pr; gate_on tk-anc tk-q
REPLY_FAIL=1 run_open tk-q --json
eq "$RC" 4 "(REPLY-FAIL) open through a gate whose reply the store refuses exits 4"
C=$(filed_on tk-anc)
[ -n "$C" ] && ok "(REPLY-FAIL) …with the conversation filed on the bead the gate holds" \
    || bad "(REPLY-FAIL) …with the conversation filed on the bead the gate holds"
has "$ERR" "gc bd dep add $C tk-q --type replies-to" "(REPLY-FAIL) …naming the reply to add by hand"
eq "$(deps_of tk-anc blocks)" "$C tk-q" "(REPLY-FAIL) the anchor depends on the conversation all the same"
lands_before "bd dep add tk-anc $C --type blocks" "bd dep add $C tk-q --type replies-to" \
    && ok "(REPLY-FAIL) …through a hold written before the reply" \
    || bad "(REPLY-FAIL) …through a hold written before the reply ($(tr '\n' ';' < "$CALLS"))"
gc bd gate resolve tk-q --reason "answered in another sitting" >/dev/null
eq "$(status_of tk-anc)" "needs-attention [blocked]" "(REPLY-FAIL) once another sitting answers the gate, the PR stays held"
eq "$(holds_of tk-anc)" "blocked $C" "(REPLY-FAIL) …by the conversation, which is still open"
# A conversation filed before its PR opened holds no merge until open joins it.
fresh; bead tk-anc task open '{"merge_result":"pre_open_gate"}'
run_open tk-anc --json; C=$(opened_conv)
setm tk-anc merge_result pull_request; setm tk-anc pr_number 41; gate_on tk-anc tk-q
: > "$CALLS"
REPLY_FAIL=1 run_open tk-q --reason "and should it wait for the gate?" --json
eq "$RC" 4 "(REPLY-FAIL) joining a queued conversation through a gate whose reply the store refuses exits 4"
has "$ERR" "conversation $C waits in the queue for tk-anc, but the store refused its reply onto gate tk-q" \
    "(REPLY-FAIL) …saying the joined conversation's reply was refused"
hasnt "$(cat "$CALLS")" "bd create" "(REPLY-FAIL) …filing no second conversation"
eq "$(deps_of tk-anc blocks)" "$C tk-q" "(REPLY-FAIL) the conversation it joined holds the merge all the same"
gc bd gate resolve tk-q --reason "answered in another sitting" >/dev/null
eq "$(status_of tk-anc)" "needs-attention [blocked]" "(REPLY-FAIL) …so the PR stays held once the gate is answered"

echo
echo "conversation-merge-hold: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
