#!/usr/bin/env bash
# migrate-visits-to-gates.sh — the cutover's one-shot move of every open visit
# and every legacy demand onto native human gates and conversations
# (specs/tk-0ur8r9p/design.md section 11). It is not a standing sweep. The
# cutover runs it on every store, runs it again once no step that can still
# file a visit is left, and a follow-up deletes it once --check passes
# (section 12; the runbook is specs/tk-o6pd01i/cutover-runbook.md).
#
# A run takes each store in turn, the city store first, and in each:
#   1. ends every converse session whose alias names a visit, in any store, and
#      reads each back as gone from `gc session list`. While one will not stop,
#      the run names it and moves nothing, because a live sitting can still
#      write to a visit after the run has read it.
#   2. counts the step beads that carry the gate-visit block's opening line,
#      `# >>> gate-visit`, and can still file a visit: one that is not closed,
#      or one closed canceled or skipped while the session it is assigned to
#      is still listed. A visit such a step files is taken by a later run.
#   3. files each legacy demand (a bead carrying gc.demand_for with no await
#      type, not a visit) again as a human gate through human-gate.sh, gives
#      the gate the demand's keys, assignee, waits, framing and notes, then
#      releases the demand and closes it `migrated: gate <id>`.
#   4. migrates each open visit. A human gate that covers its situation, on its
#      subject or on the visit itself, becomes its gate. Otherwise, when
#      something waits on it, the visit becomes a gate filed through
#      human-gate.sh, and when nothing does, a conversation in the operator's
#      queue. Its waits, framing and notes move, and it is released from its
#      holder and closed `migrated: gate <id>` or `migrated: conversation <id>`.
#   5. shapes every open human gate that no visit still open needs: its await
#      id becomes its key and its title its takeaway, and then its pack keys go.
#   6. re-points the references read after the cutover: finding.visit,
#      finding.ruling_visit and pr_comment_disposition=visit:<id>.
#   7. in the city store, closes the "Human gate awaiting you" notices, which
#      nothing else closes once the notify order is off.
# Every write is read back before the next. A visit or a legacy demand closes
# last, so a run stopped part way leaves it open, and a rerun finishes it: the
# helper's dedup finds the gate a run filed, a conversation is found by the
# line its notes carry, and each step writes only what is still missing.
#
# Usage:
#   migrate-visits-to-gates.sh --all [--dry-run]
#   migrate-visits-to-gates.sh --rig <name> [--dry-run]
#   migrate-visits-to-gates.sh --check
#   --all      the city store, then every rig store, suspended rigs included
#   --rig      one store, by its name in `gc rig list` (the city's own row too)
#   --dry-run  print each item's plan and write nothing
#   --check    read every store and name each open visit, open legacy demand
#              and counted step; it passes only when there is none
# Run one at a time.
# Exit: 0 the run completed (its report names each item it left for a person),
# or --check found nothing · 1 --check found something, or a store's listing did
# not answer · 2 usage · 3 a converse session on a visit did not stop, or the
# session list did not answer, so nothing was moved in any store
set -u

PROG="migrate-visits-to-gates"
LIVE="open,in_progress,blocked,deferred,hooked,pinned"
MARK_VISIT="Carried from visit"
MARK_DEMAND="Carried from legacy demand"
# The pack keys a demand carries, which a shaped gate sheds as its last write.
PACK_KEYS="gc.demand_for gc.demand_topic gc.gate_visit gc.routed_to gc.takeaway gc.takeaway_at gc.takeaway_by gc.takeaway_settled"
SWEEP_CREATOR="order:gate-visit-sweep"
NOTICE_PREFIX="Human gate awaiting you: "
TAKEAWAY_MAX=140

usage() { sed -n '2,/^set -u/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//;/^set -u/d' >&2; }

MODE=""; ONLY_RIG=""; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --all)     MODE=run; shift ;;
    --rig)     [ $# -ge 2 ] || { echo "$PROG: --rig requires a value" >&2; exit 2; }
               MODE=run; ONLY_RIG="$2"; shift 2 ;;
    --check)   MODE=check; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) usage; exit 2 ;;
    *) echo "$PROG: unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done
[ -n "$MODE" ] || { echo "$PROG: name --all, --rig <name> or --check" >&2; usage; exit 2; }
if [ "$MODE" = check ] && [ "$DRY" = 1 ]; then
  echo "$PROG: --check writes nothing already; --dry-run applies to a run" >&2; exit 2
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$SCRIPT_DIR/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 1; }
# shellcheck source=conversation.sh
. "$SCRIPT_DIR/conversation.sh" || { echo "$PROG: cannot source conversation.sh beside this script" >&2; exit 1; }
HELPER="${MIGRATE_HUMAN_GATE:-$SCRIPT_DIR/human-gate.sh}"
command -v jq >/dev/null 2>&1 || { echo "$PROG: jq is required" >&2; exit 1; }
[ -x "$HELPER" ] || { echo "$PROG: human-gate.sh not found or not executable at $HELPER" >&2; exit 1; }

TAB=$(printf '\t')
NL='
'

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

warn() { echo "$PROG: $*" >&2; }

# The report. Each line names the store and what happened to one item, and the
# per-store tally counts each kind.
STORE_LABEL=""
N_GATE=0; N_MERGED=0; N_CONV=0; N_LEFT=0; N_DEMAND=0; N_DEMAND_LEFT=0
N_UNATTACHED=0; N_STEPS=0; N_REFS=0; N_NOTICES=0
note_line() { printf '%s: %s\n' "$STORE_LABEL" "$*"; }
left_open() { N_LEFT=$((N_LEFT + 1)); note_line "LEFT OPEN for a person: $*"; }

# rf <json> <jq-path> — one field of a row as a string, "" when absent.
rf() { printf '%s' "$1" | jq -r "($2) // \"\" | if type == \"string\" then . else tostring end" 2>/dev/null; }

# show_row <id> — sets ROW to the bead's own row. Returns 0 when it reads, 3
# when bd answers that no such bead exists, and 1 when the read did not answer,
# so "gone" and "could not tell" stay apart.
ROW=""
show_row() {
  local raw rc
  ROW=""
  raw=$(gc bd show "$1" --json </dev/null 2>/dev/null); rc=$?
  raw=$(printf '%s' "$raw" | grep -a -vE '^gc bd:' | scrub)
  ROW=$(printf '%s' "$raw" | jq -c --arg id "$1" \
    'if type == "array" then ([ .[] | objects | select((.id // "") == $id) ] | first) // empty else empty end' 2>/dev/null)
  [ -n "$ROW" ] && return 0
  if printf '%s' "$raw" | jq -e 'type == "object" and ((.error // "") | test("no issues found"))' >/dev/null 2>&1; then
    return 3
  fi
  if [ "$rc" -eq 0 ] && printf '%s' "$raw" | jq -e 'type == "array" and length == 0' >/dev/null 2>&1; then
    return 3
  fi
  return 1
}

# deps_of <id> <type> [up] — the rows `gc bd dep list` answers: the beads <id>
# depends on through <type> edges, or with `up` the beads that depend on <id>
# through them. Returns 1 when the read did not answer an array.
deps_of() {
  local dir=down raw
  [ "${3:-}" = up ] && dir=up
  raw=$(gc bd dep list "$1" --direction="$dir" --type "$2" --json </dev/null 2>/dev/null) || return 1
  printf '%s' "$raw" | grep -a -vE '^gc bd:' | scrub \
    | jq -ce 'if type == "array" then [ .[] | objects ] else error("not an array") end' 2>/dev/null
}

# open_ids <rows> — the ids of the rows that are not closed, in row order, one
# per line.
open_ids() {
  printf '%s' "$1" | jq -r '.[] | select(((.status // "open") | tostring | ascii_downcase) != "closed") | (.id // empty)' 2>/dev/null
}

# in_list <word> <newline-list> — 0 when the word is a line of the list.
in_list() { case "$NL$2$NL" in *"$NL$1$NL"*) return 0 ;; esac; return 1; }

# ── Stores ────────────────────────────────────────────────────────────
# RIG_ROWS: one line per store, the city's first: name, id prefix, store path
# and kind, joined by the unit separator. A suspended rig's store is read too,
# because every store answers from the city's one Dolt server.
RIG_ROWS=""; CITY_DB=""
load_rigs() {
  local raw
  raw=$(gc rig list --json </dev/null 2>/dev/null | grep -a -vE '^gc bd:' | scrub)
  RIG_ROWS=$(printf '%s' "$raw" | jq -r '
    (.rigs // []) | (map(select(.hq == true)) + map(select(.hq != true)))[]
    | select(((.path // "") != "") and ((.prefix // "") != ""))
    | [ ((.name // "") | gsub("[[:cntrl:]]"; " ")), .prefix, (.path + "/.beads"),
        (if .hq == true then "city" else "rig" end) ] | join("\u001f")' 2>/dev/null)
  [ -n "$RIG_ROWS" ] || { warn "\`gc rig list --json\` named no store; nothing was read or moved"; exit 1; }
  CITY_DB=$(printf '%s\n' "$RIG_ROWS" | awk -F'\037' '$4 == "city" { print $3; exit }')
}

# db_of <bead-id> — the store a bead lives in, by its id prefix.
db_of() {
  local p="${1%%-*}" name pfx db kind
  while IFS=$'\037' read -r name pfx db kind; do
    [ "$pfx" = "$p" ] && { printf '%s' "$db"; return 0; }
  done <<EOF
$RIG_ROWS
EOF
  return 1
}

# ── Sessions ──────────────────────────────────────────────────────────
# SESSIONS: the sessions `gc session list` holds that have not ended, as
# {id, alias, session_name, template} objects. A closed session is left out,
# and so is one listed with an empty state, which is how a closed session reads
# when gc answers from the supervisor.
SESSIONS="[]"
read_sessions() {
  local raw
  raw=$(gc session list --state all --json </dev/null 2>/dev/null) || return 1
  SESSIONS=$(printf '%s' "$raw" | scrub | jq -ce '
    if type == "object" and ((.sessions // null) | type) == "array"
    then [ .sessions[] | objects
           | select((.closed // false) != true)
           | select(((.state // "") | tostring) as $st | $st != "" and $st != "closed" and $st != "failed-create")
           | { id: ((.id // "") | tostring), alias: ((.alias // "") | tostring),
               session_name: ((.session_name // "") | tostring),
               template: ((.template // "") | tostring) } ]
    else error("sessions array unreadable") end' 2>/dev/null) || return 1
}

# alias_candidates <alias> — the bead ids an alias can name, one per line. A
# claim qualifies an alias as `<rig>/<binding>.<alias>`, and engage's fallback
# alias for a visit is `v-<id>`, so each tail after a dot is a candidate, with
# the `v-` taken off.
alias_candidates() {
  local r="${1##*/}"
  while [ -n "$r" ]; do
    printf '%s\n' "${r#v-}"
    case "$r" in *.*) r="${r#*.}" ;; *) r="" ;; esac
  done
}

# find_old_sittings — sets OLD to one "<session id><TAB><visit id>" line per
# converse session whose alias names a visit, open or closed, in any store.
# Returns 1 when the session list or a candidate's row did not answer, because
# then whether an old sitting still runs is unknown.
OLD=""
find_old_sittings() {
  local rows sid alias cand
  OLD=""
  read_sessions || return 1
  rows=$(printf '%s' "$SESSIONS" | jq -r '.[] | select(.template | test("converse")) | [.id, .alias] | @tsv' 2>/dev/null)
  while IFS=$'\t' read -r sid alias; do
    [ -n "$sid" ] && [ -n "$alias" ] || continue
    while IFS= read -r cand; do
      [[ "$cand" =~ ^[a-z0-9]+-[a-z0-9-]+(\.[0-9]+)*$ ]] || continue
      db_of "$cand" >/dev/null || continue
      show_row "$cand"
      case $? in
        0) if [ "$(rf "$ROW" '.metadata.task_kind')" = visit ]; then
             OLD="$OLD$sid$TAB$cand$NL"; break
           fi ;;
        3) ;;
        *) return 1 ;;
      esac
    done <<EOF
$(alias_candidates "$alias")
EOF
  done <<EOF
$rows
EOF
  return 0
}

# end_old_sittings — step 1. Returns 0 once no converse session on a visit is
# left, and 3 when one did not stop or the list did not answer.
end_old_sittings() {
  local sid vid stuck=""
  if ! find_old_sittings; then
    warn "the session list, or the row of a visit a converse session's alias names, did not answer, so whether an old sitting still runs is unknown. Nothing was moved in any store; run again once both answer."
    return 3
  fi
  [ -n "$OLD" ] || return 0
  if [ "$DRY" = 1 ]; then
    while IFS="$TAB" read -r sid vid; do
      [ -n "$sid" ] && note_line "would end the sitting $sid on visit $vid before anything moves"
    done <<EOF
$OLD
EOF
    return 0
  fi
  while IFS="$TAB" read -r sid vid; do
    [ -n "$sid" ] || continue
    gc session close "$sid" </dev/null >/dev/null 2>&1 || true
  done <<EOF
$OLD
EOF
  if ! read_sessions; then
    warn "the sittings on visits were asked to stop, but the session list did not answer the read-back. Nothing was moved in any store; run again."
    return 3
  fi
  while IFS="$TAB" read -r sid vid; do
    [ -n "$sid" ] || continue
    if printf '%s' "$SESSIONS" | jq -e --arg s "$sid" 'any(.[]; .id == $s)' >/dev/null 2>&1; then
      stuck="$stuck$sid$TAB$vid$NL"
    else
      echo "ended the sitting $sid on visit $vid"
    fi
  done <<EOF
$OLD
EOF
  if [ -n "$stuck" ]; then
    while IFS="$TAB" read -r sid vid; do
      [ -n "$sid" ] && warn "the converse session $sid on visit $vid did not stop: it is still listed by 'gc session list'."
    done <<EOF
$stuck
EOF
    warn "nothing was moved in any store, because a live sitting can still write to a visit after this run reads it. Stop each session named above (gc session close <id>), then run again."
    return 3
  fi
  return 0
}

# ── Step 2: the steps that can still file a visit ─────────────────────
# A step's assignee names a listed session by its id, its session name or its
# alias, bare or qualified.
STEP_JQ='
  def listed($s): ((.assignee // "") | tostring) as $a
    | $a != "" and any($s[]; .alias as $al
                              | .id == $a or .session_name == $a or $al == $a
                                or ($al != "" and (($al | endswith("/" + $a)) or ($a | endswith("/" + $al)))));
  def has_block: ((.description // "") | test("(^|\n)[ \t]*# >>> gate-visit[ \t]*(\r?\n|$)"));
'
# count_steps <db> — sets STEP_LINES, one line per step bead in the store that
# carries the block and can still run it. Returns 1 when a listing did not
# answer. bd's --desc-contains narrows the listing, and each candidate's own
# description is then matched for the opening line itself, so a work bead that
# quotes the block (no gc.step_ref) or a longer marker is not counted.
STEP_LINES=""
count_steps() {
  local db="$1" open closed ids full
  STEP_LINES=""
  open=$(bd_list --db "$db" --has-metadata-key gc.step_ref --desc-contains "# >>> gate-visit" --status "$LIVE" --brief) || return 1
  closed=$(bd_list --db "$db" --has-metadata-key gc.step_ref --desc-contains "# >>> gate-visit" --status closed --brief) || return 1
  read_sessions || return 1
  ids=$(printf '%s\n%s\n%s\n' "$open" "$closed" "$SESSIONS" | jq -rs "$STEP_JQ"'
    .[0] as $o | .[1] as $c | .[2] as $s
    | ( [ $o[] | .id ]
      + [ $c[] | select(((.metadata["gc.outcome"] // "") | tostring) as $out | $out == "canceled" or $out == "skipped")
                | select(listed($s)) | .id ] )
    | unique | join(",")' 2>/dev/null) || return 1
  [ -n "$ids" ] || return 0
  full=$(bd_list --db "$db" --id "$ids" --all) || return 1
  STEP_LINES=$(printf '%s' "$full" | jq -r "$STEP_JQ"'
    .[] | select(((.metadata["gc.step_ref"] // "") | tostring) != "") | select(has_block)
    | "\(.id) (\((.metadata["gc.step_ref"] // "") | tostring), run \((.metadata["gc.root_bead_id"] // "?") | tostring), \(.status // "open"), assigned \((.assignee // "") | tostring | if . == "" then "to no session" else . end))"' 2>/dev/null) || return 1
  return 0
}

# ── Keys and subjects ─────────────────────────────────────────────────
# A visit's subject is its tracks target, else its gc.continuation_group. A
# `gc bd show` row spells an edge {dependency_type, id}, a `gc bd list` row
# {type, depends_on_id}, and both are read.
SUBJECT_JQ='
  def tracked: [ (.dependencies // [])[]? | objects
                 | select(((.dependency_type // .type) // "") == "tracks")
                 | ((.depends_on_id // .id) // "") | tostring | select(. != "") ];
  def visit_subject: (tracked[0] // "") as $t
    | if $t != "" then $t else ((.metadata["gc.continuation_group"] // "") | tostring) end;
  def headline: (.title // "") as $t
    | ((try ($t | capture("^visit: [^ ]+ — (?<h>.+)$").h) catch null) // $t);
'

# own_key <visit row> — a visit's key: its escalation_key, else the fallback
# key that names it, conversation.<visit id>.
own_key() {
  local k
  k=$(rf "$1" '.metadata.escalation_key')
  [ -n "$k" ] || k="conversation.$(rf "$1" '.id')"
  printf '%s' "$k"
}

# gate_key <gate row> — the key a human gate answers to. A shaped gate's await
# id is its key. A demand's await id, gc-demand:<gated>[:<topic>], names the
# bead it blocks instead, so its key is its gc.demand_topic, else the key of the
# visit whose gc.hold_demand names it (converse-hold gave its demands the
# visit's own key), else conversation.<demand id>. Returns 1 when that visit
# lookup did not answer.
gate_key() {
  local row="$1" id await topic db hold v
  id=$(rf "$row" '.id'); await=$(rf "$row" '.await_id')
  if [ -n "$await" ] && [ "${await#gc-demand:}" = "$await" ]; then printf '%s' "$await"; return 0; fi
  topic=$(rf "$row" '.metadata["gc.demand_topic"]')
  [ -n "$topic" ] && { printf '%s' "$topic"; return 0; }
  db=$(db_of "$id") || { printf 'conversation.%s' "$id"; return 0; }
  hold=$(bd_list --db "$db" --metadata-field "gc.hold_demand=$id" --all) || return 1
  v=$(printf '%s' "$hold" | jq -c '[ .[] | select(((.metadata.task_kind // "") | tostring) == "visit") ]
    | sort_by((.created_at // ""), .id) | first // empty' 2>/dev/null)
  if [ -n "$v" ]; then own_key "$v"; else printf 'conversation.%s' "$id"; fi
}

# demand_key <legacy demand row> — its topic, else the hold visit's key, else
# conversation.<demand id>: gate_key's rule for a bead with no await id.
demand_key() { gate_key "$(printf '%s' "$1" | jq -c '.await_id = ""' 2>/dev/null)"; }

is_human_gate() { [ "$(rf "$1" '.issue_type')" = gate ] && [ "$(rf "$1" '.await_type')" = human ]; }

# migrated_gate <row> — the gate a `migrated: gate <id>` close reason names.
migrated_gate() {
  local reason
  [ "$(rf "$1" '.status')" = closed ] || return 1
  reason=$(rf "$1" '.close_reason')
  case "$reason" in "migrated: gate "*) printf '%s' "${reason#migrated: gate }" | awk '{print $1}' ;; *) return 1 ;; esac
}

# message <headline> <framing> — a filing's message: the headline, which the
# helper makes the gate's title, then the framing.
message() { if [ -n "$2" ]; then printf '%s\n\n%s' "$1" "$2"; else printf '%s' "$1"; fi; }

# file_gate <subject> <key> <message> — files or finds the gate through the
# helper, which declares no quiet window here. Sets GATE and GATE_FOUND (1 when
# the helper returned a gate already open under the key). Returns non-zero when
# the helper did not answer with a gate.
GATE=""; GATE_FOUND=0
file_gate() {
  local out err rc
  GATE=""; GATE_FOUND=0
  err=$(mktemp "${TMPDIR:-/tmp}/migrate-visits.XXXXXX" 2>/dev/null) || err=/dev/null
  out=$("$HELPER" --subject "$1" --key "$2" --message "$3" 2>"$err" </dev/null); rc=$?
  GATE=$(printf '%s\n' "$out" | awk 'NF { last = $1 } END { print last }')
  if [ "$err" != /dev/null ]; then
    grep -q "already asks" "$err" 2>/dev/null && GATE_FOUND=1
    [ "$rc" -eq 0 ] || sed 's/^/  /' "$err" >&2
    rm -f "$err"
  fi
  [ "$rc" -eq 0 ] && [ -n "$GATE" ]
}

# carry_onto <bead> <marker line> <framing> <notes> <extra> — append the line,
# the framing unless the bead's description already contains it, the extra text
# and the notes, unless the bead's notes already carry the line. Returns 0 once
# the line reads back.
carry_onto() {
  local b="$1" line="$2" framing="$3" notes="$4" extra="$5" cur desc body
  show_row "$b" || return 1
  cur=$(rf "$ROW" '.notes'); desc=$(rf "$ROW" '.description')
  in_list "$line" "$cur" && return 0
  body="$line"
  if [ -n "$framing" ]; then
    case "$desc" in *"$framing"*) ;; *) body="$body${NL}What it asked:${NL}$framing" ;; esac
  fi
  [ -n "$extra" ] && body="$body$NL$extra"
  [ -n "$notes" ] && body="$body${NL}Its notes:${NL}$notes"
  gc bd update "$b" --append-notes "$body" </dev/null >/dev/null 2>&1 || true
  show_row "$b" || return 1
  in_list "$line" "$(rf "$ROW" '.notes')"
}

# move_waits <gate> <blocks rows> <until rows> — give every open bead that
# waited through a blocks or until edge the same edge onto the gate, and read
# each back from the gate's end. Sets MOVE_MISSING to what did not land.
MOVE_MISSING=""
move_waits() {
  local g="$1" b u w got_b got_u
  MOVE_MISSING=""
  b=$(open_ids "$2"); u=$(open_ids "$3")
  while IFS= read -r w; do
    [ -n "$w" ] && [ "$w" != "$g" ] && gc bd dep add "$w" "$g" --type blocks </dev/null >/dev/null 2>&1
  done <<EOF
$b
EOF
  while IFS= read -r w; do
    [ -n "$w" ] && [ "$w" != "$g" ] && gc bd dep add "$w" "$g" --type until </dev/null >/dev/null 2>&1
  done <<EOF
$u
EOF
  got_b=$(deps_of "$g" blocks up) || { MOVE_MISSING="(the gate's waiters did not read back)"; return 1; }
  got_u=$(deps_of "$g" until up) || { MOVE_MISSING="(the gate's waiters did not read back)"; return 1; }
  got_b=$(printf '%s' "$got_b" | jq -r '.[].id // empty'); got_u=$(printf '%s' "$got_u" | jq -r '.[].id // empty')
  while IFS= read -r w; do
    [ -n "$w" ] && [ "$w" != "$g" ] && ! in_list "$w" "$got_b" && MOVE_MISSING="$MOVE_MISSING $w(blocks)"
  done <<EOF
$b
EOF
  while IFS= read -r w; do
    [ -n "$w" ] && [ "$w" != "$g" ] && ! in_list "$w" "$got_u" && MOVE_MISSING="$MOVE_MISSING $w(until)"
  done <<EOF
$u
EOF
  [ -z "$MOVE_MISSING" ]
}

# release_and_close <bead> <reason> <label> — release the bead from the holder
# it names, in one write guarded on that holder and its status, then close it
# unforced. bd refuses an unforced close of an assigned bead by anyone but its
# assignee, and a sitting's claim outlives its session. Returns 0 once it reads
# back closed; otherwise it reports why it stays open.
release_and_close() {
  local b="$1" reason="$2" label="$3" holder status
  show_row "$b" || { left_open "$label $b did not read before its release; a rerun closes it"; return 1; }
  holder=$(rf "$ROW" '.assignee'); status=$(rf "$ROW" '.status')
  [ "$status" = closed ] && return 0
  if [ -n "$holder" ]; then
    gc bd update "$b" --if-assignee "$holder" --if-status "$status" --status open --assignee "" </dev/null >/dev/null 2>&1 || true
    if ! show_row "$b" || [ -n "$(rf "$ROW" '.assignee')" ] || [ "$(rf "$ROW" '.status')" != open ]; then
      left_open "$label $b: its release from $holder did not land, because it changed after this run read it or bd refused it; a rerun releases it from the holder it names then"
      return 1
    fi
  fi
  gc bd close "$b" --reason "$reason" </dev/null >/dev/null 2>&1 || true
  if ! show_row "$b" || [ "$(rf "$ROW" '.status')" != closed ]; then
    left_open "$label $b: bd refused its close (another bead still blocks it, or it has an open child); it stays open and unassigned"
    return 1
  fi
  return 0
}

# ── Step 3: legacy demands ────────────────────────────────────────────
migrate_legacy_demand() {
  local d="$1" row forbead title takeaway desc notes holder ups untils blocks target key head rc k v have args
  show_row "$d" || { left_open "legacy demand $d did not read"; N_DEMAND_LEFT=$((N_DEMAND_LEFT + 1)); return; }
  row="$ROW"
  [ "$(rf "$row" '.status')" = closed ] && return
  forbead=$(rf "$row" '.metadata["gc.demand_for"]')
  title=$(rf "$row" '.title'); takeaway=$(rf "$row" '.metadata["gc.takeaway"]')
  desc=$(rf "$row" '.description'); notes=$(rf "$row" '.notes'); holder=$(rf "$row" '.assignee')
  if ! ups=$(deps_of "$d" blocks up) || ! untils=$(deps_of "$d" until up); then
    left_open "legacy demand $d: what waits on it did not read"; N_DEMAND_LEFT=$((N_DEMAND_LEFT + 1)); return
  fi
  blocks=$(open_ids "$ups")
  if in_list "$forbead" "$blocks"; then target="$forbead"; else target=$(printf '%s\n' "$blocks" | awk 'NF { print; exit }'); fi
  if [ -z "$target" ]; then
    left_open "legacy demand $d: no open bead waits on it through a blocks edge, so a gate would add a wait it never held"
    N_DEMAND_LEFT=$((N_DEMAND_LEFT + 1)); return
  fi
  key=$(demand_key "$row") || { left_open "legacy demand $d: the visit that may name it as its hold did not read"; N_DEMAND_LEFT=$((N_DEMAND_LEFT + 1)); return; }
  head="${takeaway:-$title}"
  if [ "$DRY" = 1 ]; then
    note_line "would file legacy demand $d again as a human gate on $target [$key]"; return
  fi
  # 1. The gate, through the helper. Its dedup returns the gate a stopped run
  #    filed, because the demand stays open until its own close.
  if ! file_gate "$target" "$key" "$(message "$head" "$desc")"; then
    left_open "legacy demand $d: human-gate.sh filed no gate on $target [$key]"; N_DEMAND_LEFT=$((N_DEMAND_LEFT + 1)); return
  fi
  # 2. The keys a visit's step 1 and step 3 read, wherever the gate has none.
  show_row "$GATE" || { left_open "legacy demand $d: its gate $GATE did not read"; N_DEMAND_LEFT=$((N_DEMAND_LEFT + 1)); return; }
  args=()
  for k in gc.demand_for gc.demand_topic gc.takeaway; do
    v=$(rf "$row" ".metadata[\"$k\"]"); have=$(rf "$ROW" ".metadata[\"$k\"]")
    [ -n "$v" ] && [ -z "$have" ] && args+=(--set-metadata "$k=$v")
  done
  if [ "${#args[@]}" -gt 0 ]; then
    gc bd update "$GATE" "${args[@]}" </dev/null >/dev/null 2>&1 || true
    show_row "$GATE" || true
    for k in gc.demand_for gc.demand_topic gc.takeaway; do
      v=$(rf "$row" ".metadata[\"$k\"]")
      if [ -n "$v" ] && [ -z "$(rf "$ROW" ".metadata[\"$k\"]")" ]; then
        left_open "legacy demand $d: $k did not land on its gate $GATE"; N_DEMAND_LEFT=$((N_DEMAND_LEFT + 1)); return
      fi
    done
  fi
  # 3. The person the demand was assigned to, when the gate names nobody.
  if [ -n "$holder" ] && [ -z "$(rf "$ROW" '.assignee')" ]; then
    gc bd update "$GATE" --assignee "$holder" </dev/null >/dev/null 2>&1 || true
    if ! show_row "$GATE" || [ "$(rf "$ROW" '.assignee')" != "$holder" ]; then
      left_open "legacy demand $d: its gate $GATE did not take the assignee $holder"; N_DEMAND_LEFT=$((N_DEMAND_LEFT + 1)); return
    fi
  fi
  # 4. The waits. 5. The framing and notes. 6. The release and the close.
  if ! move_waits "$GATE" "$ups" "$untils"; then
    left_open "legacy demand $d: a wait did not move onto its gate $GATE:$MOVE_MISSING"; N_DEMAND_LEFT=$((N_DEMAND_LEFT + 1)); return
  fi
  if ! carry_onto "$GATE" "$MARK_DEMAND $d, which this gate replaces:" "$desc" "$notes" ""; then
    left_open "legacy demand $d: its framing and notes did not land on its gate $GATE"; N_DEMAND_LEFT=$((N_DEMAND_LEFT + 1)); return
  fi
  release_and_close "$d" "migrated: gate $GATE" "legacy demand" || { N_DEMAND_LEFT=$((N_DEMAND_LEFT + 1)); return; }
  N_DEMAND=$((N_DEMAND + 1))
  note_line "legacy demand $d is now human gate $GATE on $target [$key]"
}

legacy_pass() {
  local db="$1" rows ids d
  rows=$(bd_list --db "$db" --include-gates --has-metadata-key gc.demand_for --status "$LIVE") || return 1
  ids=$(printf '%s' "$rows" | jq -r '[ .[] | select(((.await_type // "") | tostring) == "")
      | select(((.metadata.task_kind // "") | tostring) != "visit") ]
    | sort_by((.created_at // ""), .id) | .[].id' 2>/dev/null) || return 1
  while IFS= read -r d; do
    [ -n "$d" ] && migrate_legacy_demand "$d"
  done <<EOF
$ids
EOF
  return 0
}

# ── Step 4: visits ────────────────────────────────────────────────────
# visit_situation <visit row> — step 1's read, which writes nothing. Sets
# SIT_SUBJECT (the bead the visit is about), SIT_KEY, SIT_REPLY (the gate its
# subject named, which a conversation replies to), SIT_FIRST (the subject as
# the visit names it) and SIT_PROBLEM (why it cannot move, empty when it can).
SIT_SUBJECT=""; SIT_KEY=""; SIT_REPLY=""; SIT_FIRST=""; SIT_PROBLEM=""
visit_situation() {
  local row="$1" v dm g waiters n ids
  SIT_SUBJECT=""; SIT_KEY=""; SIT_REPLY=""; SIT_FIRST=""; SIT_PROBLEM=""
  v=$(rf "$row" '.id')
  SIT_FIRST=$(printf '%s' "$row" | jq -r "$SUBJECT_JQ"'visit_subject' 2>/dev/null)
  if [ -z "$SIT_FIRST" ]; then SIT_PROBLEM="it names no subject (no tracks edge, no gc.continuation_group)"; return; fi
  SIT_KEY=$(own_key "$row")
  # The sweep's visit puts one demand to a person, so while that demand is open
  # its key is the demand's, and a demand the legacy pass filed again hands it
  # the key of the gate its close reason names.
  if [ "$(rf "$row" '.created_by')" = "$SWEEP_CREATOR" ]; then
    dm=$(rf "$row" '.description' | sed -n 's/^A human gate (\([^)]*\)) blocks .*/\1/p' | head -n 1)
    if [ -n "$dm" ]; then
      show_row "$dm"
      case $? in
        0) if [ "$(rf "$ROW" '.status')" != closed ]; then
             if is_human_gate "$ROW"; then
               SIT_KEY=$(gate_key "$ROW") || { SIT_PROBLEM="the key of its demand $dm did not read"; return; }
             else
               SIT_PROBLEM="it is the sweep's visit for legacy demand $dm, which no bead waits on through a blocks edge, so it stays open beside that demand"; return
             fi
           elif g=$(migrated_gate "$ROW"); then
             show_row "$g" && [ "$(rf "$ROW" '.status')" != closed ] && { SIT_KEY=$(gate_key "$ROW") || { SIT_PROBLEM="the key of gate $g did not read"; return; }; }
           fi ;;
        3) ;;
        *) SIT_PROBLEM="its demand $dm did not read"; return ;;
      esac
    fi
  fi
  SIT_SUBJECT="$SIT_FIRST"
  show_row "$SIT_SUBJECT"
  case $? in
    0) ;;
    3) return ;;
    *) SIT_PROBLEM="its subject $SIT_SUBJECT did not read"; return ;;
  esac
  # A legacy demand the legacy pass filed again stands for its gate.
  if g=$(migrated_gate "$ROW"); then
    SIT_SUBJECT="$g"
    show_row "$g" || { SIT_PROBLEM="gate $g, which replaced its subject, did not read"; return; }
  fi
  # A conversation is about a bead, never a gate: a gate gives way to the one
  # open bead still waiting on it, as engage takes it.
  if [ "$(rf "$ROW" '.issue_type')" = gate ]; then
    g="$SIT_SUBJECT"
    waiters=$(deps_of "$g" blocks up) || { SIT_PROBLEM="the beads that wait on gate $g did not read"; return; }
    ids=$(open_ids "$waiters"); n=$(printf '%s\n' "$ids" | awk 'NF' | wc -l | tr -d ' ')
    if [ "$n" -ne 1 ]; then
      SIT_PROBLEM="it is about gate $g, which leaves $n open beads waiting${ids:+ ($(printf '%s' "$ids" | paste -sd' ' -))}, and a conversation is about one bead"
      return
    fi
    SIT_SUBJECT="$ids"
    is_human_gate "$ROW" && SIT_REPLY="$g"
  fi
}

# taken_demands <visit id> — step 3's choice, which writes nothing: the open
# human gates carrying gc.demand_for that name the visit's subject or the visit
# itself, oldest first, as rows with .covers (its key is the visit's key) and
# .on_visit (filed on the visit itself). Each covering one and each one on the
# visit is taken. Returns 1 when a listing did not answer.
TAKEN="[]"
taken_demands() {
  local v="$1" rows="" r db one id key on keys=""
  TAKEN="[]"
  for r in "$SIT_SUBJECT" "$v"; do
    [ -n "$r" ] || continue
    db=$(db_of "$r") || continue
    one=$(bd_list --db "$db" --include-gates --metadata-field "gc.demand_for=$r" --status "$LIVE") || return 1
    rows="$rows$one$NL"
  done
  rows=$(printf '%s' "$rows" | jq -cs '[ .[][] | select((.issue_type // "") == "gate" and (.await_type // "") == "human") ]
    | unique_by(.id) | sort_by((.created_at // ""), .id)' 2>/dev/null) || return 1
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    key=$(gate_key "$(printf '%s' "$rows" | jq -c --arg id "$id" '.[] | select(.id == $id)')") || return 1
    on=0; [ "$(printf '%s' "$rows" | jq -r --arg id "$id" '.[] | select(.id == $id) | (.metadata["gc.demand_for"] // "") | tostring')" = "$v" ] && on=1
    keys="$keys$id"$'\037'"$key"$'\037'"$on$NL"
  done <<EOF
$(printf '%s' "$rows" | jq -r '.[].id')
EOF
  TAKEN=$(printf '%s' "$rows" | jq -c --arg keys "$keys" --arg vk "$SIT_KEY" '
    ($keys | split("\n") | map(select(. != "") | split("\u001f") | {key: .[0], value: {k: .[1], on: (.[2] == "1")}}) | from_entries) as $m
    | [ .[] | select($m[.id] != null) | . + {key: $m[.id].k, on_visit: $m[.id].on, covers: ($m[.id].k == $vk)}
            | select(.covers or .on_visit) ]' 2>/dev/null) || return 1
}

# shape_taken <demand row with .key> <visit> <subject is open: 0|1> — step 3's
# writes on one taken demand. A demand filed on the visit moves its edge to the
# subject first, because bd refuses to close a blocked visit. Its title becomes
# its takeaway, and its await id becomes its key last, because the await id is
# what marks a gate shaped. Its pack keys stay until its visit has closed.
shape_taken() {
  local t="$1" v="$2" open_subject="$3" id key tk title ups
  id=$(rf "$t" '.id'); key=$(rf "$t" '.key')
  if [ "$(rf "$t" '.on_visit')" = true ]; then
    if [ "$open_subject" = 1 ]; then
      gc bd dep add "$SIT_SUBJECT" "$id" --type blocks </dev/null >/dev/null 2>&1 || true
      ups=$(deps_of "$id" blocks up) || return 1
      printf '%s' "$ups" | jq -e --arg s "$SIT_SUBJECT" 'any(.[]; .id == $s)' >/dev/null 2>&1 || return 1
    fi
    ups=$(deps_of "$id" blocks up) || return 1
    if printf '%s' "$ups" | jq -e --arg v "$v" 'any(.[]; .id == $v)' >/dev/null 2>&1; then
      gc bd dep remove "$v" "$id" </dev/null >/dev/null 2>&1 || true
      ups=$(deps_of "$id" blocks up) || return 1
      printf '%s' "$ups" | jq -e --arg v "$v" 'any(.[]; .id == $v)' >/dev/null 2>&1 && return 1
    fi
  fi
  show_row "$id" || return 1
  tk=$(rf "$ROW" '.metadata["gc.takeaway"]'); title=$(rf "$ROW" '.title')
  if [ -n "$tk" ] && [ "$tk" != "$title" ]; then
    gc bd update "$id" --title "$tk" </dev/null >/dev/null 2>&1 || true
    show_row "$id" && [ "$(rf "$ROW" '.title')" = "$tk" ] || return 1
  fi
  if [ "$(rf "$ROW" '.await_id')" != "$key" ]; then
    gc bd update "$id" --await-id "$key" </dev/null >/dev/null 2>&1 || true
    show_row "$id" && [ "$(rf "$ROW" '.await_id')" = "$key" ] || return 1
  fi
  return 0
}

# has_open_child <bead> — 0 when the bead has a parent-child child that is not
# closed or pinned, a gate or a wisp among them, the children bd's blocked
# cascade reaches; 1 when it has none; 2 when the read did not answer.
has_open_child() {
  local db raw
  db=$(db_of "$1") || return 2
  raw=$(gc bd list --db "$db" --parent "$1" --include-gates --include-infra --include-templates --json --limit 1 </dev/null 2>/dev/null) || return 2
  raw=$(printf '%s' "$raw" | grep -a -vE '^gc bd:' | scrub)
  printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 2
  printf '%s' "$raw" | jq -e 'length > 0' >/dev/null 2>&1 && return 0
  return 1
}

# recheck_line <visit row> — the re-check command a liveness gate carries in
# its message, built from the census a liveness sweep's visit stamped, with the
# script named rather than the stamp's path. Empty for any other visit.
recheck_line() {
  local new carried at cmd
  [ -n "$(rf "$1" '.metadata["visit.recheck"]')" ] || return 0
  new=$(rf "$1" '.metadata["sweep.new_ids"]'); carried=$(rf "$1" '.metadata["sweep.carried_ids"]'); at=$(rf "$1" '.metadata["sweep.pass_at"]')
  [ -n "$new" ] || return 0
  cmd="liveness-recheck.sh --ids $new"
  [ -n "$carried" ] && cmd="$cmd --carried $carried"
  [ -n "$at" ] && cmd="$cmd --pass-at $at"
  printf 'Re-check the census before acting: %s' "$cmd"
}

# conversation_title <text> — the title gc-helm.sh gives a conversation: one
# line, at most 140 codepoints and 400 bytes, an over-cap tail cut with an
# ellipsis.
conversation_title() {
  printf '%s' "$1" | jq -Rsr --argjson n "$TAKEAWAY_MAX" \
    '((gsub("\\s+"; " ")) | sub("^ "; "") | sub(" $"; "")) as $h
     | if ($h | length) > $n then (($h[:($n - 1)]) | sub("\\s+$"; "")) + "…" else $h end
     | until(utf8bytelength <= 400; (.[:-2] | sub("\\s+$"; "")) + "…")' 2>/dev/null \
    || printf '%s' "$1" | cut -c1-"$TAKEAWAY_MAX"
}

# file_conversation <visit row> <headline> <framing> <notes> <extra> — step 7.
# Finds the task an earlier run filed by the line its notes carry, or files
# one: a task in the operator's queue that tracks the subject, in the subject's
# store, with the line and the visit's notes riding the create. Sets CONV.
CONV=""
file_conversation() {
  local v="$1" head="$2" framing="$3" notes="$4" extra="$5" db line found json body
  CONV=""
  line="$MARK_VISIT $v:"
  db=$(db_of "$SIT_SUBJECT") || db="$STORE_DB"
  found=$(bd_list --db "$db" --notes-contains "$line" --all) || return 1
  CONV=$(printf '%s' "$found" | jq -r --arg l "$line" '
    [ .[] | select((.issue_type // "task") == "task")
          | select(((.notes // "") | split("\n")) | any(. == $l)) ]
    | sort_by((.created_at // ""), .id) | first | .id // empty' 2>/dev/null)
  if [ -z "$CONV" ]; then
    body="$line"
    [ -n "$extra" ] && body="$body$NL$extra"
    [ -n "$notes" ] && body="$body${NL}Its notes:${NL}$notes"
    json=$(gc bd create -t task --title "$(conversation_title "$head")" -d "${framing:-$head}" \
      --deps "tracks:$SIT_SUBJECT" --assignee human --notes "$body" --db "$db" --json </dev/null 2>/dev/null)
    CONV=$(printf '%s' "$json" | grep -a -vE '^gc bd:' | scrub \
      | jq -r 'if type == "array" then (.[0].id // empty) else (.id // empty) end' 2>/dev/null)
    [ -n "$CONV" ] || return 1
  fi
  # Its tracks edge is what makes the task a conversation about the subject.
  if ! bd_list --db "$db" --id "$CONV" --all | jq -e --arg c "$CONV" --arg s "$SIT_SUBJECT" "$CONVERSATION_JQ"'
      any(.[]; (.id // "") == $c and (conversation_subjects | index($s)) != null)' >/dev/null 2>&1; then
    gc bd dep add "$CONV" "$SIT_SUBJECT" --type tracks </dev/null >/dev/null 2>&1 || true
    bd_list --db "$db" --id "$CONV" --all | jq -e --arg c "$CONV" --arg s "$SIT_SUBJECT" "$CONVERSATION_JQ"'
      any(.[]; (.id // "") == $c and (conversation_subjects | index($s)) != null)' >/dev/null 2>&1 || return 1
  fi
  if [ -n "$SIT_REPLY" ] && ! replies_to "$db" "$CONV" "$SIT_REPLY"; then
    gc bd dep add "$CONV" "$SIT_REPLY" --type replies-to </dev/null >/dev/null 2>&1 || true
    replies_to "$db" "$CONV" "$SIT_REPLY" || return 1
  fi
  return 0
}

# replies_to <db> <conversation> <gate> — 0 when the conversation's own row
# carries a replies-to edge onto the gate.
replies_to() {
  bd_list --db "$1" --id "$2" --all | jq -e --arg c "$2" --arg g "$3" '
    any(.[] | select((.id // "") == $c) | (.dependencies // [])[]? | objects;
        ((.type // .dependency_type) // "") == "replies-to" and ((.depends_on_id // .id) // "") == $g)' >/dev/null 2>&1
}

migrate_visit() {
  local v="$1" row head framing notes extra vb vu b u waits=0 subj_row="" subj_state=missing blockable=0
  local covering gv="" t n i findings comments target="" kind db
  show_row "$v" || { left_open "visit $v did not read"; return; }
  row="$ROW"
  [ "$(rf "$row" '.status')" = closed ] && return
  head=$(printf '%s' "$row" | jq -r "$SUBJECT_JQ"'headline' 2>/dev/null)
  framing=$(rf "$row" '.description'); notes=$(rf "$row" '.notes'); extra=$(recheck_line "$row")
  # 1. The subject and the key.
  visit_situation "$row"
  [ -z "$SIT_PROBLEM" ] || { left_open "visit $v: $SIT_PROBLEM"; return; }
  # 2. The subject's state.
  if show_row "$SIT_SUBJECT"; then
    subj_row="$ROW"
    if [ "$(rf "$subj_row" '.status')" = closed ]; then subj_state=closed; else subj_state=open; fi
  else
    case $? in 3) subj_state=missing ;; *) left_open "visit $v: its subject $SIT_SUBJECT did not read"; return ;; esac
  fi
  if ! vb=$(deps_of "$v" blocks up) || ! vu=$(deps_of "$v" until up); then
    left_open "visit $v: what waits on it did not read"; return
  fi
  b=$(open_ids "$vb"); u=$(open_ids "$vu")
  # 3. The human gates that cover its situation, and the ones filed on it.
  taken_demands "$v" || { left_open "visit $v: the demands on its subject did not read"; return; }
  covering=$(printf '%s' "$TAKEN" | jq -r '[ .[] | select(.covers) ][0].id // empty')
  # 4. Whether anything waits on it, and the bead a gate of its own would block.
  findings=$(bd_list --db "$STORE_DB" --metadata-field "finding.visit=$v" --status "$LIVE") || { left_open "visit $v: the findings that may name it did not read"; return; }
  comments="[]"
  if db=$(db_of "$SIT_SUBJECT"); then
    comments=$(bd_list --db "$db" --metadata-field "pr_comment_disposition=visit:$v" --status "$LIVE") || { left_open "visit $v: the anchors whose comments may name it did not read"; return; }
  fi
  [ -n "$b$u" ] && waits=1
  printf '%s' "$findings$comments" | jq -se 'add | length > 0' >/dev/null 2>&1 && waits=1
  if [ "$subj_state" = open ]; then
    [ -n "$(rf "$row" '.metadata.escalation_key')" ] && waits=1
    [ -n "$(rf "$subj_row" '.metadata.merge_result')" ] && waits=1
    blockable=1
    in_list "$SIT_SUBJECT" "$u" && blockable=0
    if [ "$blockable" = 1 ]; then
      has_open_child "$SIT_SUBJECT"
      case $? in
        0) blockable=0 ;;
        1) ;;
        *) left_open "visit $v: whether its subject $SIT_SUBJECT has open children did not read"; return ;;
      esac
    fi
  fi
  if [ -n "$covering" ]; then
    kind=merged
  elif [ "$waits" = 1 ]; then
    if [ "$blockable" = 1 ]; then target="$SIT_SUBJECT"
    else target=$(printf '%s\n' "$b" | awk 'NF { print; exit }'); fi
    if [ -n "$target" ]; then kind=gate
    elif [ -n "$u" ]; then left_open "visit $v: only until edges wait on it, on a subject a gate cannot block, so the migration has no bead to block"; return
    else kind=conversation; fi
  else
    kind=conversation
  fi
  if [ "$kind" = conversation ] && [ "$subj_state" = missing ]; then
    left_open "visit $v: its subject $SIT_SUBJECT no longer exists and no bead waits on it, so nothing can track it"; return
  fi
  if [ "$DRY" = 1 ]; then
    case "$kind" in
      merged)       note_line "would close visit $v into human gate $covering [$SIT_KEY]" ;;
      gate)         note_line "would file visit $v as a human gate on $target [$SIT_KEY]" ;;
      conversation) note_line "would make visit $v a conversation about $SIT_SUBJECT${SIT_REPLY:+ that replies to gate $SIT_REPLY}" ;;
    esac
    return
  fi
  # 3. Shape each taken demand, its edge moved off the visit first.
  n=$(printf '%s' "$TAKEN" | jq 'length')
  i=0
  while [ "$i" -lt "$n" ]; do
    t=$(printf '%s' "$TAKEN" | jq -c --argjson i "$i" '.[$i]')
    if ! shape_taken "$t" "$v" "$([ "$subj_state" = open ] && echo 1 || echo 0)"; then
      left_open "visit $v: the demand $(rf "$t" '.id') it takes did not take its shape (edge, title or await id)"; return
    fi
    i=$((i + 1))
  done
  case "$kind" in
    merged) gv="$covering" ;;
    gate)
      if ! file_gate "$target" "$SIT_KEY" "$(message "$head" "$framing")"; then
        left_open "visit $v: human-gate.sh filed no gate on $target [$SIT_KEY]"; return
      fi
      gv="$GATE"; [ "$GATE_FOUND" = 1 ] && kind=merged ;;
  esac
  if [ -n "$gv" ]; then
    # 5. The waits. 6. The framing and notes, and the re-check.
    if ! move_waits "$gv" "$vb" "$vu"; then left_open "visit $v: a wait did not move onto gate $gv:$MOVE_MISSING"; return; fi
    if ! carry_onto "$gv" "$MARK_VISIT $v:" "$framing" "$notes" "$extra"; then
      left_open "visit $v: its framing and notes did not land on gate $gv"; return
    fi
    # 8. The release and the close.
    release_and_close "$v" "migrated: gate $gv" "visit" || return
    if [ "$kind" = merged ]; then
      N_MERGED=$((N_MERGED + 1)); note_line "visit $v closed into human gate $gv [$SIT_KEY], already open"
    else
      N_GATE=$((N_GATE + 1)); note_line "visit $v is now human gate $gv on $target [$SIT_KEY]"
    fi
    return
  fi
  # 7. A conversation in the operator's queue. 8. The release and the close.
  if ! file_conversation "$v" "$head" "$framing" "$notes" "$extra"; then
    left_open "visit $v: its conversation about $SIT_SUBJECT did not file or read back${CONV:+ ($CONV)}"; return
  fi
  release_and_close "$v" "migrated: conversation $CONV" "visit" || return
  N_CONV=$((N_CONV + 1))
  note_line "visit $v is now conversation $CONV about $SIT_SUBJECT${SIT_REPLY:+, replying to gate $SIT_REPLY}"
}

visit_pass() {
  local rows ids v
  rows=$(bd_list --db "$STORE_DB" --metadata-field task_kind=visit --status "$LIVE") || return 1
  ids=$(printf '%s' "$rows" | jq -r 'sort_by((.created_at // ""), .id) | .[].id' 2>/dev/null) || return 1
  while IFS= read -r v; do
    [ -n "$v" ] && migrate_visit "$v"
  done <<EOF
$ids
EOF
  return 0
}

# ── Step 5: shape the gates no open visit needs ───────────────────────
# deferred_gates — the demands step 3 takes for a visit still open in this
# store, which keep their keys for the next run's step 3. For a visit whose
# situation does not read, every demand on its subject or on it is kept.
deferred_gates() {
  local rows v row db r one
  DEFER=""
  rows=$(bd_list --db "$STORE_DB" --metadata-field task_kind=visit --status "$LIVE") || return 1
  while IFS= read -r v; do
    [ -n "$v" ] || continue
    row=$(printf '%s' "$rows" | jq -c --arg v "$v" '.[] | select(.id == $v)')
    visit_situation "$row"
    if [ -z "$SIT_PROBLEM" ] && taken_demands "$v"; then
      DEFER="$DEFER$(printf '%s' "$TAKEN" | jq -r '.[].id')$NL"
      continue
    fi
    for r in "$SIT_FIRST" "$v"; do
      [ -n "$r" ] || continue
      db=$(db_of "$r") || continue
      one=$(bd_list --db "$db" --include-gates --metadata-field "gc.demand_for=$r" --status "$LIVE") || return 1
      DEFER="$DEFER$(printf '%s' "$one" | jq -r '.[].id')$NL"
    done
  done <<EOF
$(printf '%s' "$rows" | jq -r '.[].id')
EOF
  return 0
}

DEFER=""
shape_pass() {
  local gates ids g row key tk title shaped present ups
  gates=$(bd_list --db "$STORE_DB" --include-gates --type gate --status "$LIVE") || return 1
  deferred_gates || return 1
  ids=$(printf '%s' "$gates" | jq -r '[ .[] | select((.await_type // "") == "human") ] | sort_by((.created_at // ""), .id) | .[].id' 2>/dev/null) || return 1
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    if in_list "$g" "$DEFER"; then
      note_line "gate $g keeps its demand keys: a visit still open takes it, and a rerun finishes both"; continue
    fi
    show_row "$g" || { left_open "gate $g did not read, so it was not shaped"; continue; }
    row="$ROW"; shaped=0
    case "$(rf "$row" '.await_id')" in
      gc-demand:*)
        key=$(gate_key "$row") || { left_open "gate $g: the visit that may name it as its hold did not read"; continue; }
        if [ "$DRY" = 1 ]; then note_line "would shape gate $g [$key]"; continue; fi
        tk=$(rf "$row" '.metadata["gc.takeaway"]'); title=$(rf "$row" '.title')
        if [ -n "$tk" ] && [ "$tk" != "$title" ]; then
          gc bd update "$g" --title "$tk" </dev/null >/dev/null 2>&1 || true
          show_row "$g" && [ "$(rf "$ROW" '.title')" = "$tk" ] || { left_open "gate $g did not take its title"; continue; }
        fi
        gc bd update "$g" --await-id "$key" </dev/null >/dev/null 2>&1 || true
        show_row "$g" && [ "$(rf "$ROW" '.await_id')" = "$key" ] || { left_open "gate $g did not take its key [$key] as its await id"; continue; }
        row="$ROW"; shaped=1 ;;
    esac
    present=$(printf '%s' "$row" | jq -r --arg keys "$PACK_KEYS" \
      '[ ($keys | split(" "))[] as $k | select((.metadata // {}) | has($k)) | $k ] | join(" ")' 2>/dev/null)
    if [ -n "$present" ]; then
      if [ "$DRY" = 1 ]; then note_line "would remove $present from gate $g"; continue; fi
      local args=() k
      for k in $present; do args+=(--unset-metadata "$k"); done
      gc bd update "$g" "${args[@]}" </dev/null >/dev/null 2>&1 || true
      if ! show_row "$g" || printf '%s' "$ROW" | jq -e --arg keys "$PACK_KEYS" \
          'any(($keys | split(" "))[]; . as $k | (.metadata // {}) | has($k))' >/dev/null 2>&1; then
        left_open "gate $g: its pack keys did not all go"; continue
      fi
    fi
    if [ "$shaped" = 1 ]; then
      ups=$(deps_of "$g" blocks up) || ups="[]"
      if printf '%s' "$ups" | jq -e 'length == 0' >/dev/null 2>&1; then
        N_UNATTACHED=$((N_UNATTACHED + 1))
        note_line "gate $g is shaped but blocks no bead (its demand's blocks edge never landed); the board gives it a row of its own, and its description's first line names the bead its filer meant"
      fi
    fi
  done <<EOF
$ids
EOF
  return 0
}

# ── Step 6: references ────────────────────────────────────────────────
# walk <visit> — the copy of finding.sh's visit walk the cutover needs, since
# the pack's finding.sh no longer reads visits. From the named visit it follows
# gc.folded_into, gc.superseded_by and this script's `migrated: gate` close
# reason to what carries the situation now. Prints "<end> <id>": gate (a human
# gate), ruled (a visit closed with gc.ruling), unruled (a visit closed with no
# ruling and no successor), open (a visit still open), or unreadable.
walk() {
  local v="$1" seen=" " g next
  while [ -n "$v" ]; do
    case "$seen" in *" $v "*) printf 'unruled %s\n' "$v"; return ;; esac
    seen="$seen$v "
    show_row "$v" || { printf 'unreadable %s\n' "$v"; return; }
    if is_human_gate "$ROW"; then printf 'gate %s\n' "$v"; return; fi
    [ "$(rf "$ROW" '.metadata.task_kind')" = visit ] || { printf 'unruled %s\n' "$v"; return; }
    [ "$(rf "$ROW" '.status')" = closed ] || { printf 'open %s\n' "$v"; return; }
    if g=$(migrated_gate "$ROW"); then v="$g"; continue; fi
    if [ -n "$(rf "$ROW" '.metadata["gc.ruling"]' | tr -d '[:space:]')" ]; then printf 'ruled %s\n' "$v"; return; fi
    next=$(rf "$ROW" '.metadata["gc.folded_into"]'); [ -n "$next" ] || next=$(rf "$ROW" '.metadata["gc.superseded_by"]')
    [ -n "$next" ] || { printf 'unruled %s\n' "$v"; return; }
    v="$next"
  done
  printf 'unreadable %s\n' "$1"
}

ref_pass() {
  local rows f v end id reply posted args disp anchor
  # finding.visit on a live finding.
  rows=$(bd_list --db "$STORE_DB" --has-metadata-key finding.visit --status "$LIVE") || return 1
  while IFS=$'\037' read -r f v reply posted; do
    [ -n "$f" ] || continue
    read -r end id <<EOF
$(walk "$v")
EOF
    case "$end" in
      open|unreadable) left_open "finding $f still names visit $v, which is $end; a rerun converts it"; continue ;;
    esac
    if [ "$DRY" = 1 ]; then note_line "would re-point finding $f from visit $v ($end $id)"; continue; fi
    args=(--unset-metadata finding.visit)
    case "$end" in
      gate)
        args+=(--set-metadata "finding.gate=$id")
        if [ -z "$posted" ] && [ -n "$reply" ]; then
          case "$reply" in *"$v"*)
            args+=(--set-metadata "finding.reply=This comment needs your decision, and human gate $id already asks you for it. The review stays changes-requested until you clear that gate with your ruling and the work it calls for lands.") ;;
          esac
        fi ;;
      ruled) args+=(--set-metadata "finding.ruling_bead=$id") ;;
      unruled) args+=(--append-notes "Cutover: visit $v, which carried this finding's question, closed with no ruling before the cutover (the walk ends at $id), so nothing has answered it.") ;;
    esac
    gc bd update "$f" "${args[@]}" </dev/null >/dev/null 2>&1 || true
    show_row "$f" || { left_open "finding $f did not read back"; continue; }
    if [ -n "$(rf "$ROW" '.metadata["finding.visit"]')" ] \
       || { [ "$end" = gate ] && [ "$(rf "$ROW" '.metadata["finding.gate"]')" != "$id" ]; } \
       || { [ "$end" = ruled ] && [ "$(rf "$ROW" '.metadata["finding.ruling_bead"]')" != "$id" ]; }; then
      left_open "finding $f: its reference to visit $v did not move"; continue
    fi
    N_REFS=$((N_REFS + 1)); note_line "finding $f: visit $v became $end $id"
  done <<EOF
$(printf '%s' "$rows" | jq -r '.[] | [.id, ((.metadata["finding.visit"] // "") | tostring),
    ((.metadata["finding.reply"] // "") | tostring | gsub("[[:cntrl:]]"; " ")),
    ((.metadata["finding.reply_posted"] // "") | tostring)] | join("\u001f")')
EOF
  # finding.ruling_visit on any finding, closed ones included.
  rows=$(bd_list --db "$STORE_DB" --has-metadata-key finding.ruling_visit --all) || return 1
  while IFS=$'\037' read -r f v id; do
    [ -n "$f" ] || continue
    if [ "$DRY" = 1 ]; then note_line "would rename finding.ruling_visit on $f"; continue; fi
    args=(--unset-metadata finding.ruling_visit)
    [ -n "$id" ] || args+=(--set-metadata "finding.ruling_bead=$v")
    gc bd update "$f" "${args[@]}" </dev/null >/dev/null 2>&1 || true
    if ! show_row "$f" || [ -n "$(rf "$ROW" '.metadata["finding.ruling_visit"]')" ] || [ -z "$(rf "$ROW" '.metadata["finding.ruling_bead"]')" ]; then
      left_open "finding $f: finding.ruling_visit did not become finding.ruling_bead"; continue
    fi
    N_REFS=$((N_REFS + 1))
  done <<EOF
$(printf '%s' "$rows" | jq -r '.[] | [.id, ((.metadata["finding.ruling_visit"] // "") | tostring), ((.metadata["finding.ruling_bead"] // "") | tostring)] | join("\u001f")')
EOF
  # pr_comment_disposition=visit:<id> on a live anchor. Its reader reads only the
  # status of the bead it names, so only the migrated: reason is followed.
  rows=$(bd_list --db "$STORE_DB" --has-metadata-key pr_comment_disposition --status "$LIVE") || return 1
  while IFS=$'\037' read -r anchor disp; do
    [ -n "$anchor" ] || continue
    v="${disp#visit:}"
    show_row "$v" || { left_open "anchor $anchor: its disposition names visit $v, which did not read"; continue; }
    if [ "$(rf "$ROW" '.status')" != closed ]; then left_open "anchor $anchor: its disposition names visit $v, which is still open; a rerun converts it"; continue; fi
    id=$(migrated_gate "$ROW") || id="$v"
    if [ "$DRY" = 1 ]; then note_line "would re-point anchor $anchor's disposition to human:$id"; continue; fi
    gc bd update "$anchor" --set-metadata "pr_comment_disposition=human:$id" </dev/null >/dev/null 2>&1 || true
    if ! show_row "$anchor" || [ "$(rf "$ROW" '.metadata.pr_comment_disposition')" != "human:$id" ]; then
      left_open "anchor $anchor: its disposition did not become human:$id"; continue
    fi
    N_REFS=$((N_REFS + 1)); note_line "anchor $anchor: disposition visit:$v became human:$id"
  done <<EOF
$(printf '%s' "$rows" | jq -r '.[] | ((.metadata.pr_comment_disposition // "") | tostring) as $d | select($d | startswith("visit:")) | [.id, $d] | join("\u001f")')
EOF
  return 0
}

# ── Step 7: the gate notices ──────────────────────────────────────────
notice_pass() {
  local rows n
  rows=$(bd_list --db "$CITY_DB" --include-infra --status open) || return 1
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    if [ "$DRY" = 1 ]; then N_NOTICES=$((N_NOTICES + 1)); continue; fi
    # core assigns these notices to human, so the close passes bd's assignee
    # guard with --force; each is a notice this run has read as one.
    gc bd close "$n" --force --reason "migrated: the board is where a human gate reaches the operator, and the notify order is off" </dev/null >/dev/null 2>&1 || true
    if show_row "$n" && [ "$(rf "$ROW" '.status')" = closed ]; then
      N_NOTICES=$((N_NOTICES + 1))
    else
      warn "could not close the gate notice $n; a rerun closes it"
    fi
  done <<EOF
$(printf '%s' "$rows" | jq -r --arg p "$NOTICE_PREFIX" '.[] | select((.issue_type // "") == "message") | select((.title // "") | startswith($p)) | .id')
EOF
  return 0
}

# ── Driving it ────────────────────────────────────────────────────────
STORE_DB=""
run_store() {
  local name="$1" db="$2" kind="$3" rc=0
  STORE_LABEL="$name"; STORE_DB="$db"
  N_GATE=0; N_MERGED=0; N_CONV=0; N_LEFT=0; N_DEMAND=0; N_DEMAND_LEFT=0
  N_UNATTACHED=0; N_STEPS=0; N_REFS=0; N_NOTICES=0
  echo "== $name ($db)"
  end_old_sittings || return 3
  if count_steps "$db"; then
    if [ -n "$STEP_LINES" ]; then
      N_STEPS=$(printf '%s\n' "$STEP_LINES" | awk 'NF' | wc -l | tr -d ' ')
      printf '%s\n' "$STEP_LINES" | sed "s|^|$name: step that can still file a visit: |"
    fi
  else
    warn "$name: the steps carrying the gate-visit block did not read"; rc=1
  fi
  legacy_pass "$db" || { warn "$name: its legacy demands did not read; nothing past them was moved"; return 1; }
  visit_pass || { warn "$name: its visits did not read; nothing past them was moved"; return 1; }
  shape_pass || { warn "$name: its gates did not read; nothing past them was shaped"; rc=1; }
  ref_pass || { warn "$name: a listing of its references did not read"; rc=1; }
  if [ "$kind" = city ]; then notice_pass || { warn "$name: the gate notices did not read"; rc=1; }; fi
  local tally="visits into gates $N_GATE, merged into a gate $N_MERGED, into conversations $N_CONV; legacy demands into gates $N_DEMAND, left open $N_DEMAND_LEFT; items left for a person $N_LEFT; gates blocking no bead $N_UNATTACHED; steps that can still file a visit $N_STEPS; references moved $N_REFS"
  [ "$kind" = city ] && tally="$tally; gate notices closed $N_NOTICES"
  [ "$DRY" = 1 ] && tally="(dry run, nothing written) $tally"
  echo "$name: $tally"
  return "$rc"
}

check_store() {
  local name="$1" db="$2" visits demands legacy found=0
  if ! visits=$(bd_list --db "$db" --metadata-field task_kind=visit --status "$LIVE") \
     || ! demands=$(bd_list --db "$db" --include-gates --has-metadata-key gc.demand_for --status "$LIVE") \
     || ! count_steps "$db"; then
    echo "$name: did not answer, so the check cannot pass" ; return 1
  fi
  legacy=$(printf '%s' "$demands" | jq -r '.[] | select(((.await_type // "") | tostring) == "")
    | select(((.metadata.task_kind // "") | tostring) != "visit") | .id')
  while IFS= read -r v; do [ -n "$v" ] && { echo "$name: open visit $v"; found=1; }; done <<EOF
$(printf '%s' "$visits" | jq -r '.[].id')
EOF
  while IFS= read -r v; do [ -n "$v" ] && { echo "$name: open legacy demand $v"; found=1; }; done <<EOF
$legacy
EOF
  while IFS= read -r v; do [ -n "$v" ] && { echo "$name: step that can still file a visit: $v"; found=1; }; done <<EOF
$STEP_LINES
EOF
  return "$found"
}

load_rigs
if [ "$MODE" = check ]; then
  rc=0
  while IFS=$'\037' read -r name pfx db kind; do
    [ -n "$db" ] || continue
    check_store "$name" "$db" || rc=1
  done <<EOF
$RIG_ROWS
EOF
  if [ "$rc" -eq 0 ]; then
    echo "$PROG: check passed: no store holds an open visit, an open legacy demand or a step that can still file a visit"
  else
    echo "$PROG: check failed: the items named above remain; resolve them and run the migration again" >&2
  fi
  exit "$rc"
fi

[ "$DRY" = 1 ] && echo "$PROG: dry run; nothing is written"
rc=0; matched=0
while IFS=$'\037' read -r name pfx db kind; do
  [ -n "$db" ] || continue
  [ -z "$ONLY_RIG" ] || [ "$name" = "$ONLY_RIG" ] || continue
  matched=1
  run_store "$name" "$db" "$kind"
  case $? in
    0) ;;
    3) exit 3 ;;
    *) rc=1 ;;
  esac
done <<EOF
$RIG_ROWS
EOF
if [ "$matched" = 0 ]; then echo "$PROG: no store is named '$ONLY_RIG' in gc rig list" >&2; exit 2; fi
exit "$rc"
