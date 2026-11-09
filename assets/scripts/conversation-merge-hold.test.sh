#!/usr/bin/env bash
# Hermetic test: a conversation on an open PR holds the PR's merge for exactly as
# long as the conversation is open.
#
# A conversation whose subject is an open PR's anchor, or a bead whose
# anchor_bead names one, holds the PR's merge with a human gate under the
# conversation's key, conversation.<id>, on the anchor, and the conversation
# replies to it (gc-helm.sh open). Every writer that closes the conversation
# answers that gate or withdraws it.
#
# Runs the REAL gc-helm.sh (as `sh`, as shipped) for open and dismiss, the REAL
# human-gate.sh they file and withdraw the gate through, the REAL
# converse-signoff.sh, the close block of skills/converse-recheck-premise as the
# skill writes it, and the REAL `gctk pr-status derive`, built from this
# checkout, over one file-backed store behind a stubbed `gc`. No live city,
# Dolt, network or sessions. Covered:
#   (OPEN-ANCHOR)  opening a conversation on an open PR's anchor files the gate on
#                  the anchor under the conversation's key, with the
#                  conversation's reply onto it, and the PR then derives
#                  needs-attention with held: gate, naming that gate
#   (OPEN-REVIEW)  opening one on the PR's review files the gate on the anchor,
#                  and leaves the review itself unblocked
#   (OPEN-JOIN)    a second concern joins the queued conversation and files no
#                  second gate
#   (NOT-PR)       a subject that is no open PR, one whose anchor has merged, and
#                  a pre-open anchor each file no gate
#   (OPEN-UNREAD)  an anchor that does not read files nothing
#   (HOLD-FAIL)    a gate that does not file exits 4 naming the repair, and a
#                  re-run of open holds the merge
#   (SIGNOFF)      the sign-off answers the gate with the ruling, and the PR
#                  derives what it did before the conversation opened
#   (SIGNOFF-REWORK, SIGNOFF-RETIRE) a sign-off carrying --rework or --retire
#                  puts the rework child or the retirement in place before it
#                  answers the gate, so the merge is never free in between
#   (LEAVE-OWN)    the sign-off refuses --leave on the conversation's own gate
#   (MOOT)         the premise re-check's moot close withdraws the gate
#   (DISMISS)      dismiss withdraws the gate, on the anchor and on the review
#   (DISMISS-FAIL) a withdrawal that does not land exits 4 naming the repair
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

# The derivation every reader of a PR's hold asks, built from this checkout.
GCTK="$TMP/gctk"
if ! command -v go >/dev/null 2>&1 \
    || ! ( cd "$ROOT/services/gctk" && go build -buildvcs=false -o "$GCTK" ./cmd/gctk ) >"$TMP/gctk-build.log" 2>&1; then
    bad "gctk did not build, so no derivation below was exercised — $(tail -3 "$TMP/gctk-build.log" 2>/dev/null | tr '\n' ' ')"
    GCTK=false
fi

# --- gc stub ------------------------------------------------------------------
# One JSON file per bead under $STORE/b/<id>.json, its edges as deps
# [{type, on}] on the bead the edge starts from: a blocked bead carries
# {blocks, <blocker>}, a conversation {tracks, <subject>} and {replies-to,
# <gate>}. `bd show` names each edge's far bead whole, as bd does, for one id or
# several, and `bd list` names each edge as {issue_id, depends_on_id, type}.
# `bd create` mints tk-c<n> and `bd gate create` tk-g<n>. Every write is
# appended to $CALLS. Hooks: SHOW_DOWN=<id> fails a show naming that bead;
# GATE_CREATE_FAIL refuses every gate create; GATE_RESOLVE_FAIL makes every
# resolve fail, writing nothing.
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
        add_dep "$_a" "$_t" "$_b" ;;
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
      create)
        log "$*"
        [ -n "${GATE_CREATE_FAIL:-}" ] && { printf '{"error":"simulated gate create refusal"}\n'; exit 1; }
        _blk=""; _k=""; _t=""; _r=""; _ty=""; _p=""
        for a in "$@"; do
          case "$_p" in --blocks) _blk="$a" ;; --await-id) _k="$a" ;; --title) _t="$a" ;; --reason) _r="$a" ;; esac
          case "$a" in --type=*) _ty="${a#--type=}" ;; esac
          _p="$a"
        done
        [ -f "$B/$_blk.json" ] || { printf '{"error":"issue not found"}\n'; exit 1; }
        _g=$(mint tk-g)
        jq -nc --arg i "$_g" --arg t "$_t" --arg d "Ad-hoc gate blocking $_blk

Reason: $_r" --arg ty "$_ty" --arg k "$_k" --arg at "$(stamp)" \
          '{id: $i, title: $t, description: $d, status: "open", issue_type: "gate", await_type: $ty, await_id: $k, assignee: "", created_at: $at, metadata: {}, deps: []}' | put "$_g"
        add_dep "$_blk" blocks "$_g"
        printf '{"id":"%s"}\n' "$_g" ;;
      resolve)
        log "$*"
        [ -n "${GATE_RESOLVE_FAIL:-}" ] && { echo "bd gate resolve: simulated failure" >&2; exit 1; }
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

export PATH="$TMP/bin:$PATH" STORE="$TMP/store" CALLS="$TMP/calls" RIG_DIR="$TMP/rig"
export GC_SITTING_COMMENT_TOOL="$P/pr-sitting-comment.sh" GC_NO_API=1 TMPDIR="$TMP"
unset GC_HELM_FIXTURE GC_RIG GC_RIG_ROOT BEADS_DIR GC_SESSION_ID GC_SESSION_NAME GC_ALIAS GC_CITY GC_CITY_PATH GC_CITY_ROOT GC_HUMAN_GATE_TOOL 2>/dev/null || true

# --- fixtures -----------------------------------------------------------------
fresh() { rm -rf "$STORE"; mkdir -p "$STORE/b"; : > "$CALLS"; }
# bead <id> [type] [status] [metadata-json]
bead() {
    jq -nc --arg i "$1" --arg t "${2:-task}" --arg s "${3:-open}" --argjson m "${4:-"{}"}" \
        '{id: $i, title: ("the bead " + $i), description: "", notes: "", issue_type: $t, status: $s, assignee: "", created_at: "2026-11-08T00:00:00Z", metadata: $m, deps: []}' \
        > "$STORE/b/$1.json"
}
field() { jq -r --arg k "$2" '.[$k] // "" | tostring' "$STORE/b/$1.json" 2>/dev/null; }
notes() { field "$1" notes; }
deps_of() { jq -r --arg t "$2" '[ .deps[] | select(.type == $t) | .on ] | join(" ")' "$STORE/b/$1.json" 2>/dev/null; }
# gates_on <bead> — "<id> <status> <await_id>" for each gate that blocks the bead.
gates_on() {
    for g in $(deps_of "$1" blocks); do
        [ "$(field "$g" issue_type)" = gate ] && printf '%s %s %s\n' "$g" "$(field "$g" status)" "$(field "$g" await_id)"
    done
}
# An open PR's anchor, and the PR's review in flight.
pr() { fresh; bead tk-anc task open '{"merge_result":"pull_request","pr_number":"41"}'; }
pr_review() { pr; bead tk-rev task open '{"task_kind":"review","anchor_bead":"tk-anc"}'; }
derive() { (cd "$TMP/cwd" && "$GCTK" pr-status derive --anchor "$1" --json 2>/dev/null) || echo "derive-failed"; }
status_of() { derive "$1" | jq -r '"\(.status) [\(.held | join(","))]"' 2>/dev/null; }
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
# The premise re-check's close, from the skill as it is written, a moot reading
# filled in for its placeholders.
awk '/^```bash[ \t]*$/ { inb = 1; buf = ""; hit = 0; next }
     inb && /^```[ \t]*$/ { if (hit) { printf "%s", buf; exit } inb = 0; next }
     inb { buf = buf $0 "\n"; if (index($0, "closed $CONVERSATION as $KIND")) hit = 1 }' \
    "$ROOT/skills/converse-recheck-premise/SKILL.md" \
    | sed -e 's#KIND="<moot|benign>"#KIND="moot"#' \
          -e 's#WHY="<[^>]*>"#WHY="the PR it asked about was answered on GitHub"#' \
          -e 's#ACTION="<[^>]*>"#ACTION="The visit ended: its question was already answered."#' > "$TMP/moot-close.sh"
[ -s "$TMP/moot-close.sh" ] && ok "the premise re-check's close is found in the skill" \
    || bad "the premise re-check's close is found in the skill"
run_moot() { # <conversation> <subject>
    set +e
    OUT="$(cd "$TMP/cwd" && CONV="$P" CONVERSATION="$1" SUBJECT="$2" bash "$TMP/moot-close.sh" 2>&1)"; RC=$?
    set -e
}

echo "# opening a conversation on an open PR's anchor holds the PR's merge"
pr
eq "$(status_of tk-anc)" "needs-review []" "(OPEN-ANCHOR) before any conversation, the PR reads needs-review"
run_open tk-anc --reason "should this land as built?" --json
C=$(opened_conv)
eq "$RC" 0 "(OPEN-ANCHOR) open exits 0"
G=$(gates_on tk-anc | awk '{print $1}')
eq "$(gates_on tk-anc)" "$G open conversation.$C" "(OPEN-ANCHOR) one open human gate blocks the anchor, under the conversation's key"
eq "$(field "$G" await_type)" "human" "(OPEN-ANCHOR) …and it is a human gate"
eq "$(deps_of "$C" replies-to)" "$G" "(OPEN-ANCHOR) the conversation replies to it"
eq "$(deps_of "$C" tracks)" "tk-anc" "(OPEN-ANCHOR) …and tracks the anchor, its subject"
has "$(field "$G" title)" "Conversation $C is open on this PR" "(OPEN-ANCHOR) the gate's title names the conversation"
eq "$(field "$G" description | head -1)" "$(field "$G" title)" "(OPEN-ANCHOR) …and its description is the whole message, the human-gate helper's"
has "$ERR" "conversation $C holds the merge of the PR of tk-anc through gate $G until it closes" "(OPEN-ANCHOR) open says the conversation holds the merge"
eq "$(derive tk-anc | jq -c '{status, held, reasons: [.reasons[] | .id]}')" "{\"status\":\"needs-attention\",\"held\":[\"gate\"],\"reasons\":[\"$G\"]}" \
    "(OPEN-ANCHOR) gctk pr-status derive then reads needs-attention with held: gate, naming the gate"

echo "# a second concern joins the queued conversation and files no second gate"
: > "$CALLS"
run_open tk-anc --reason "and the docs?"
eq "$RC" 0 "(OPEN-JOIN) the second open exits 0"
has "$OUT" "conversation $C is already open for tk-anc" "(OPEN-JOIN) …joining the queued conversation"
hasnt "$(cat "$CALLS")" "bd gate create" "(OPEN-JOIN) …and files no second gate"
eq "$(gates_on tk-anc | wc -l | tr -d ' ')" "1" "(OPEN-JOIN) one gate still holds the anchor"

echo "# the sign-off answers the gate with the ruling"
run_signoff --conversation "$C" --outcome "lands as built" --ruled yes --ruling "it lands as built" --no-wait --no-rework
eq "$RC" 0 "(SIGNOFF) the sign-off exits 0"
eq "$(field "$G" status)/$(field "$G" close_reason)" "closed/ruled: it lands as built" "(SIGNOFF) the conversation's gate is answered with the ruling"
eq "$(field "$C" status)" "closed" "(SIGNOFF) …and the conversation is closed"
eq "$(status_of tk-anc)" "needs-review []" "(SIGNOFF) the PR derives what it did before the conversation opened"

echo "# the sign-off refuses --leave on the conversation's own gate"
pr; run_open tk-anc --json; C=$(opened_conv); G=$(gates_on tk-anc | awk '{print $1}')
: > "$CALLS"
run_signoff --conversation "$C" --outcome "x" --ruled yes --ruling "x" --no-wait --no-rework --leave "$G"
eq "$RC" 2 "(LEAVE-OWN) --leave on the conversation's own hold on the merge exits 2"
has "$OUT" "names this conversation's own hold on the merge of tk-anc" "(LEAVE-OWN) …saying why"
eq "$(grep -c '' "$CALLS" 2>/dev/null || true)" "0" "(LEAVE-OWN) …writing nothing"
eq "$(field "$G" status)" "open" "(LEAVE-OWN) …so the gate still holds the merge"

echo "# a sign-off carrying --rework files the rework before it answers the gate"
pr; run_open tk-anc --json; C=$(opened_conv); G=$(gates_on tk-anc | awk '{print $1}')
: > "$CALLS"
run_signoff --conversation "$C" --outcome "rework first" --ruled yes --ruling "fix the retry first" --no-wait --rework
eq "$RC" 0 "(SIGNOFF-REWORK) the sign-off exits 0"
REWORK_AT=$(grep -n '^converse-rework ' "$CALLS" | head -1 | cut -d: -f1)
EDGE_AT=$(grep -n "^bd dep add tk-anc tk-c" "$CALLS" | head -1 | cut -d: -f1)
RESOLVE_AT=$(grep -n "^bd gate resolve $G " "$CALLS" | head -1 | cut -d: -f1)
[ -n "$EDGE_AT" ] && [ -n "$RESOLVE_AT" ] && [ "$REWORK_AT" -lt "$RESOLVE_AT" ] && [ "$EDGE_AT" -lt "$RESOLVE_AT" ] \
    && ok "(SIGNOFF-REWORK) the rework child and its blocks edge onto the anchor land before the gate is answered" \
    || bad "(SIGNOFF-REWORK) the rework child and its blocks edge onto the anchor land before the gate is answered (rework $REWORK_AT, edge $EDGE_AT, resolve $RESOLVE_AT)"
CHILD=$(grep -o "^bd dep add tk-anc tk-c[0-9]*" "$CALLS" | head -1 | awk '{print $5}')
eq "$(field "$G" status)/$(field "$CHILD" status)" "closed/open" "(SIGNOFF-REWORK) the gate is answered, and the rework child is open"
eq "$(status_of tk-anc)" "working []" "(SIGNOFF-REWORK) …so the PR derives working, its merge waiting on the rework"

echo "# a sign-off carrying --retire retires the PR before it answers the gate"
pr; run_open tk-anc --json; C=$(opened_conv); G=$(gates_on tk-anc | awk '{print $1}')
: > "$CALLS"
run_signoff --conversation "$C" --outcome "retired" --ruled yes --ruling "the work moved" --no-wait --retire not-needed
eq "$RC" 0 "(SIGNOFF-RETIRE) the sign-off exits 0"
DISPOSE_AT=$(grep -n '^pr-dispose ' "$CALLS" | head -1 | cut -d: -f1)
RESOLVE_AT=$(grep -n "^bd gate resolve $G " "$CALLS" | head -1 | cut -d: -f1)
[ -n "$DISPOSE_AT" ] && [ -n "$RESOLVE_AT" ] && [ "$DISPOSE_AT" -lt "$RESOLVE_AT" ] \
    && ok "(SIGNOFF-RETIRE) the retirement lands before the gate is answered" \
    || bad "(SIGNOFF-RETIRE) the retirement lands before the gate is answered (dispose $DISPOSE_AT, resolve $RESOLVE_AT)"
eq "$(field "$G" status)/$(field "$C" status)" "closed/closed" "(SIGNOFF-RETIRE) …then the gate is answered and the conversation closes"

echo "# the premise re-check's moot close withdraws the gate"
pr; run_open tk-anc --json; C=$(opened_conv); G=$(gates_on tk-anc | awk '{print $1}')
run_moot "$C" tk-anc
eq "$RC" 0 "(MOOT) the close block exits 0"
has "$OUT" "closed $C as moot" "(MOOT) …printing its closed line"
eq "$(field "$G" status)/$(field "$G" close_reason)" "closed/moot: conversation $C closed as moot: the PR it asked about was answered on GitHub" \
    "(MOOT) the conversation's gate is withdrawn, moot"
eq "$(field "$C" status)" "closed" "(MOOT) …and the conversation is closed"
eq "$(status_of tk-anc)" "needs-review []" "(MOOT) the PR derives what it did before the conversation opened"

echo "# dismiss withdraws the gate"
pr; run_open tk-anc --json; C=$(opened_conv); G=$(gates_on tk-anc | awk '{print $1}')
run_dismiss "$C" --reason "done here"
eq "$RC" 0 "(DISMISS) dismiss exits 0"
eq "$(field "$C" status)" "closed" "(DISMISS) the conversation is closed"
eq "$(field "$G" status)/$(field "$G" close_reason)" "closed/moot: conversation $C was dismissed, so it no longer holds this PR's merge" \
    "(DISMISS) …and its gate is withdrawn"
eq "$(status_of tk-anc)" "needs-review []" "(DISMISS) the PR derives what it did before the conversation opened"

echo "# a conversation on the PR's review holds the anchor's merge, not the review"
pr_review
eq "$(status_of tk-anc)" "working []" "(OPEN-REVIEW) with its review in flight, the PR reads working"
run_open tk-rev --reason "is this review stuck?" --json
C=$(opened_conv)
eq "$RC" 0 "(OPEN-REVIEW) open exits 0"
G=$(gates_on tk-anc | awk '{print $1}')
eq "$(gates_on tk-anc)" "$G open conversation.$C" "(OPEN-REVIEW) the gate blocks the PR's anchor"
eq "$(gates_on tk-rev)" "" "(OPEN-REVIEW) …and nothing blocks the review, which keeps running"
eq "$(deps_of "$C" replies-to)/$(deps_of "$C" tracks)" "$G/tk-rev" "(OPEN-REVIEW) the conversation replies to the gate and tracks the review"
eq "$(status_of tk-anc)" "needs-attention [gate]" "(OPEN-REVIEW) the PR reads needs-attention with held: gate"
run_dismiss "$C"
eq "$RC/$(field "$G" status)" "0/closed" "(DISMISS) dismissing it withdraws the gate on the anchor"
eq "$(status_of tk-anc)" "working []" "(DISMISS) …and the PR reads working again"

echo "# a subject that is no open PR files no gate"
fresh; bead tk-task
run_open tk-task --reason "talk this over" --json
eq "$RC/$(grep -c 'bd gate create' "$CALLS" || true)" "0/0" "(NOT-PR) a plain task gets a conversation and no gate"
fresh; bead tk-anc task closed '{"merge_result":"merged"}'; bead tk-rw task open '{"task_kind":"rework","anchor_bead":"tk-anc"}'
run_open tk-rw --json
eq "$RC/$(grep -c 'bd gate create' "$CALLS" || true)" "0/0" "(NOT-PR) a bead whose anchor has merged files no gate"
fresh; bead tk-pre task open '{"merge_result":"pre_open_gate"}'
run_open tk-pre --json
eq "$RC/$(grep -c 'bd gate create' "$CALLS" || true)" "0/0" "(NOT-PR) a pre-open anchor, which has no PR yet, files no gate"

echo "# an anchor that does not read files nothing"
pr_review; SHOW_DOWN=tk-anc run_open tk-rev --json
eq "$RC" 4 "(OPEN-UNREAD) an anchor the subject names that does not read exits 4"
has "$ERR" "could not read tk-anc, the anchor tk-rev names" "(OPEN-UNREAD) …saying why"
hasnt "$(cat "$CALLS")" "bd create" "(OPEN-UNREAD) …and files no conversation"

echo "# a gate that does not file is reported, and a re-run of open holds the merge"
pr; GATE_CREATE_FAIL=1 run_open tk-anc --json
eq "$RC" 4 "(HOLD-FAIL) a gate that does not file exits 4"
has "$ERR" "the human gate that holds that PR's merge did not file" "(HOLD-FAIL) …saying the merge is not held"
has "$ERR" "--key conversation." "(HOLD-FAIL) …and naming the repair"
eq "$(gates_on tk-anc)" "" "(HOLD-FAIL) no gate holds the anchor"
run_open tk-anc --json
C=$(opened_conv); G=$(gates_on tk-anc | awk '{print $1}')
eq "$RC/$(printf '%s' "$OUT" | jq -r .filed)" "0/false" "(HOLD-FAIL) a re-run joins the queued conversation"
eq "$(gates_on tk-anc)" "$G open conversation.$C" "(HOLD-FAIL) …and its gate now holds the merge"
eq "$(deps_of "$C" replies-to)" "$G" "(HOLD-FAIL) …with the conversation's reply onto it"

echo "# a withdrawal that does not land is reported"
pr; run_open tk-anc --json; C=$(opened_conv); G=$(gates_on tk-anc | awk '{print $1}')
GATE_RESOLVE_FAIL=1 run_dismiss "$C"
eq "$RC" 4 "(DISMISS-FAIL) a gate that does not withdraw exits 4"
eq "$(field "$C" status)/$(field "$G" status)" "closed/open" "(DISMISS-FAIL) the conversation is closed and its gate still open"
has "$OUT" "--retract --subject tk-anc --key conversation.$C" "(DISMISS-FAIL) …and the message names the withdrawal to run"

echo
echo "conversation-merge-hold: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
