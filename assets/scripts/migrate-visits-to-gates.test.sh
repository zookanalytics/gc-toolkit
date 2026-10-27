#!/usr/bin/env bash
# migrate-visits-to-gates.test.sh — hermetic test for the cutover's migration
# (assets/scripts/migrate-visits-to-gates.sh; specs/tk-0ur8r9p/design.md
# section 11). A gc stub keeps a city store and two rig stores, one of them
# suspended, a session list and a rig list in files, with the bd behaviour the
# migration leans on. Each part loads the fixture states section 11 names, runs
# the migration, and checks where every visit, legacy demand, gate, wait and
# reference ends. A part that sweeps then stops a run after each write it makes,
# runs the migration again, and checks that the store ends exactly where an
# uninterrupted run leaves it. No live city, Dolt, gc, bd or gh.
# run-tests-parts: review holds opened gates sittings stuck steps legacy
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-migrate-visits-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

# The stub gc. It replaces the harness's, which serves one store and none of
# the gate, session or dependency verbs the migration uses.
{ _stub_shebang; cat; } > "$BIN/gc" <<'STUB'
# The test's gc: a bead store, a session list and a rig list kept in files,
# with the bd behaviour the migration leans on. A store per rig is one id
# prefix in one JSON file.
#
# The behaviour it keeps from bd: a plain list hides gates (--include-gates or
# --type gate shows them) and infra (--include-infra), and closed beads unless a
# status or --all says otherwise; one dependency per ordered pair, re-adding the
# same type a no-op and another type refused; an update guarded by --if-assignee
# or --if-status writes nothing on a mismatch and exits 13; a close is refused
# for a bead an open blocks blocker holds, one with an open parent-child child,
# and, without --force, an assigned one; `gate create` files a human gate that
# blocks the named bead, its description bd's own head over the reason.
#
# What the test drives through the environment:
#   MIG_STORE, MIG_SESSIONS, MIG_RIGS  the files
#   MIG_WRITES                         the count of writes that changed state
#   MIG_LOG                            one line per call
#   MIG_STOP_AFTER=<n>                 after the n-th such write, kill the run's
#                                      process group (never the test's own)
#   MIG_TEST_PGID                      the test's process group, spared
#   MIG_SESSION_STUCK="<id> ..."       sessions whose close fails
#   MIG_STUCK_NOTE="<bead>:<text>"     a stuck session's close appends this
#                                      note once, as its live sitting would
#   MIG_CHANGE_HOLDER="<bead>:<who>"   the first guarded release of the bead
#                                      finds this holder instead
set -u
S="${MIG_STORE:?}"
printf '%s\n' "$*" >> "${MIG_LOG:-/dev/null}"

counted() { # after a write that changed the store or the sessions
  local n
  n=$(( $(cat "$MIG_WRITES" 2>/dev/null || echo 0) + 1 ))
  echo "$n" > "$MIG_WRITES"
  if [ -n "${MIG_STOP_AFTER:-}" ] && [ "$n" -eq "$MIG_STOP_AFTER" ]; then
    local pg
    pg=$(ps -o pgid= -p $$ | tr -d ' ')
    if [ -n "$pg" ] && [ "$pg" != "${MIG_TEST_PGID:-}" ]; then
      kill -KILL -- "-$pg"
    fi
    echo "stub: refused to stop the test's own process group" >&2
    exit 99
  fi
}

# commit <new-store-file> — swap it in, counting the write when it changed.
commit() {
  if cmp -s "$1" "$S"; then rm -f "$1"; return 0; fi
  mv "$1" "$S"; counted
}

pfx_of_db() { # <store path> -> the id prefix of the rig whose store it is
  jq -r --arg d "$1" '.rigs[] | select((.path + "/.beads") == $d) | .prefix' "${MIG_RIGS:?}"
}

case "${1:-}" in
  rig)
    [ "${2:-}" = list ] && { cat "${MIG_RIGS:?}"; exit 0; }
    exit 2 ;;
  session)
    case "${2:-}" in
      list) jq -c '{sessions: .}' "${MIG_SESSIONS:?}"; exit 0 ;;
      close)
        sid="${3:-}"
        case " ${MIG_SESSION_STUCK:-} " in
          *" $sid "*)
            if [ -n "${MIG_STUCK_NOTE:-}" ] && [ ! -e "$S.stuck-noted" ]; then
              : > "$S.stuck-noted"
              b="${MIG_STUCK_NOTE%%:*}"; t="${MIG_STUCK_NOTE#*:}"
              jq --arg b "$b" --arg t "$t" 'map(if .id == $b then .notes = (if (.notes // "") == "" then $t else .notes + "\n" + $t end) else . end)' "$S" > "$S.new" && mv "$S.new" "$S"
            fi
            echo "gc session close: runtime did not stop" >&2; exit 1 ;;
        esac
        jq --arg s "$sid" 'map(if .id == $s or .alias == $s then .closed = true | .state = "closed" else . end)' "$MIG_SESSIONS" > "$MIG_SESSIONS.new"
        if cmp -s "$MIG_SESSIONS.new" "$MIG_SESSIONS"; then rm -f "$MIG_SESSIONS.new"; exit 1; fi
        mv "$MIG_SESSIONS.new" "$MIG_SESSIONS"; counted; exit 0 ;;
    esac
    exit 2 ;;
  bd) shift ;;
  *) echo "stub gc: unsupported '$*'" >&2; exit 2 ;;
esac

# Drop --db (the store) and --json from anywhere in the words.
DB=""; ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --db) DB="${2:-}"; shift 2 ;;
    --db=*) DB="${1#--db=}"; shift ;;
    --json) shift ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
set -- ${ARGS[@]+"${ARGS[@]}"}
PFX=""; [ -n "$DB" ] && PFX=$(pfx_of_db "$DB")
verb="${1:-}"; shift || true

# The far bead of an edge, as bd prints it in a show row or a dep list row.
FAR='def far($all; $id): (($all | map(select(.id == $id)) | first) // {id: $id}) | del(.dependencies);'

case "$verb" in
  show)
    id="${1:-}"
    out=$(jq -c --arg id "$id" "$FAR"'. as $all | [ .[] | select(.id == $id) ] as $r
      | if ($r | length) == 0 then {error: "no issues found matching the provided IDs"}
        else [ $r[0] | .dependencies = [ (.dependencies // [])[] as $d | far($all; $d.depends_on_id) + {id: $d.depends_on_id, dependency_type: $d.type} ] ] end' "$S")
    printf '%s\n' "$out"
    case "$out" in '{"error"'*) exit 1 ;; esac
    exit 0 ;;
  list)
    st=""; all=0; gates=0; infra=0; ty=""; hk=""; fields=(); dc=""; nc=""; parent=""; ids=""; brief=0; limit=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --status) st="$2"; shift ;;
        --status=*) st="${1#--status=}" ;;
        --all) all=1 ;;
        --include-gates) gates=1 ;;
        --include-infra) infra=1 ;;
        --include-templates) ;;
        --type) ty="$2"; shift ;;
        --type=*) ty="${1#--type=}" ;;
        --has-metadata-key) hk="$2"; shift ;;
        --metadata-field) fields+=("$2"); shift ;;
        --desc-contains) dc="$2"; shift ;;
        --notes-contains) nc="$2"; shift ;;
        --parent) parent="$2"; shift ;;
        --id) ids="$2"; shift ;;
        --brief) brief=1 ;;
        --limit) limit="$2"; shift ;;
        --limit=*) limit="${1#--limit=}" ;;
        *) echo "stub gc bd list: unsupported '$1'" >&2; exit 2 ;;
      esac
      shift
    done
    [ "$all" = 1 ] && st="ALL"
    jq -c --arg pfx "$PFX" --arg st "$st" --argjson gates "$gates" --argjson infra "$infra" --arg ty "$ty" \
      --arg hk "$hk" --arg dc "$dc" --arg nc "$nc" --arg parent "$parent" --arg ids "$ids" \
      --argjson brief "$brief" --argjson limit "$limit" '
      ($ARGS.positional | map(index("=") as $i | {k: .[:$i], v: .[$i + 1:]})) as $fields
      | [ .[]
          | select($pfx == "" or (.id | startswith($pfx + "-")))
          | select($ids == "" or (.id as $i | ($ids | split(",")) | index($i)) != null)
          | (.status // "open") as $s
          | select(if $st == "ALL" then true
                   elif $st == "" then ($s != "closed" and ($parent == "" or $s != "pinned"))
                   else (($st | split(",")) | index($s)) != null end)
          | select($gates == 1 or $ty == "gate" or (.issue_type // "task") != "gate")
          | select($infra == 1 or (((.issue_type // "task") | IN("message", "agent", "role")) | not))
          | select($ty == "" or (.issue_type // "task") == $ty)
          | select($hk == "" or ((.metadata // {}) | has($hk)))
          | . as $row | select(all($fields[]; ((($row.metadata // {})[.k]) // "" | tostring) == .v))
          | select($dc == "" or ((.description // "") | ascii_downcase | contains($dc | ascii_downcase)))
          | select($nc == "" or ((.notes // "") | ascii_downcase | contains($nc | ascii_downcase)))
          | select($parent == "" or any((.dependencies // [])[]; .type == "parent-child" and .depends_on_id == $parent))
          | .dependencies = [ (.dependencies // [])[] | {issue_id: $row.id, depends_on_id, type} ]
          | if $brief == 1 then del(.description, .notes) else . end ]
      | if $limit > 0 then .[:$limit] else . end' "$S" --args ${fields[@]+"${fields[@]}"}
    exit 0 ;;
  dep)
    sub="${1:-}"; shift || true
    case "$sub" in
      list)
        id="${1:-}"; shift || true; dir=down; ty=""
        while [ $# -gt 0 ]; do
          case "$1" in
            --direction=*) dir="${1#--direction=}" ;;
            --direction) dir="$2"; shift ;;
            --type|-t) ty="$2"; shift ;;
            --type=*) ty="${1#--type=}" ;;
          esac
          shift
        done
        jq -e --arg id "$id" 'any(.[]; .id == $id)' "$S" >/dev/null || { echo '{"error":"issue not found"}'; exit 1; }
        jq -c --arg id "$id" --arg dir "$dir" --arg ty "$ty" "$FAR"'. as $all
          | if $dir == "down" then
              [ (.[] | select(.id == $id) | (.dependencies // [])[]) | select($ty == "" or .type == $ty) as $d
                | far($all; $d.depends_on_id) + {dependency_type: $d.type} ]
            else
              [ .[] | . as $x | (.dependencies // [])[] | select(.depends_on_id == $id and ($ty == "" or .type == $ty))
                | ($x | del(.dependencies)) + {dependency_type: .type} ]
            end' "$S"
        exit 0 ;;
      add)
        a="${1:-}"; b="${2:-}"; shift 2 || true; ty=blocks
        while [ $# -gt 0 ]; do
          case "$1" in --type|-t) ty="$2"; shift ;; --type=*) ty="${1#--type=}" ;; esac; shift
        done
        jq -e --arg a "$a" --arg b "$b" 'any(.[]; .id == $a) and any(.[]; .id == $b)' "$S" >/dev/null \
          || { echo "Error: issue not found" >&2; exit 1; }
        have=$(jq -r --arg a "$a" --arg b "$b" '.[] | select(.id == $a) | (.dependencies // [])[] | select(.depends_on_id == $b) | .type' "$S")
        if [ -n "$have" ]; then
          [ "$have" = "$ty" ] && exit 0
          echo "Error: dependency $a -> $b already exists with type \"$have\" (requested \"$ty\")" >&2; exit 1
        fi
        jq --arg a "$a" --arg b "$b" --arg t "$ty" 'map(if .id == $a then .dependencies = ((.dependencies // []) + [{depends_on_id: $b, type: $t}]) else . end)' "$S" > "$S.new"
        commit "$S.new"; exit 0 ;;
      remove)
        a="${1:-}"; b="${2:-}"
        jq --arg a "$a" --arg b "$b" 'map(if .id == $a then .dependencies = [ (.dependencies // [])[] | select(.depends_on_id != $b) ] else . end)' "$S" > "$S.new"
        commit "$S.new"; exit 0 ;;
    esac
    exit 2 ;;
  gate)
    [ "${1:-}" = create ] || exit 2
    shift; blocks=""; await=""; title=""; reason=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --type=*) ;;
        --type) shift ;;
        --blocks) blocks="$2"; shift ;;
        --await-id) await="$2"; shift ;;
        --await-id=*) await="${1#--await-id=}" ;;
        --title) title="$2"; shift ;;
        --reason) reason="$2"; shift ;;
      esac
      shift
    done
    jq -e --arg b "$blocks" 'any(.[]; .id == $b)' "$S" >/dev/null || { echo '{"error":"issue not found"}'; exit 1; }
    n=$(( $(cat "$S.seq" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$S.seq"
    id="${blocks%%-*}-g$n"
    jq --arg id "$id" --arg b "$blocks" --arg a "$await" --arg t "$title" --arg r "$reason" --argjson n "$n" '
      map(if .id == $b then .dependencies = ((.dependencies // []) + [{depends_on_id: $id, type: "blocks"}]) else . end)
      + [ {id: $id, issue_type: "gate", await_type: "human", await_id: $a, title: $t, status: "open",
           description: ("Ad-hoc gate blocking " + $b + "\n\nReason: " + $r), created_at: ("2026-11-01T00:00:" + ($n | tostring)),
           metadata: {}, dependencies: []} ]' "$S" > "$S.new"
    commit "$S.new"
    printf '[{"id":"%s"}]\n' "$id"; exit 0 ;;
  update)
    id="${1:-}"; shift || true
    ifa="__unset__"; ifs="__unset__"; ops='[]'
    while [ $# -gt 0 ]; do
      case "$1" in
        --if-assignee) ifa="$2"; shift ;;
        --if-status) ifs="$2"; shift ;;
        --status|--status=*) v="${2:-}"; case "$1" in --status=*) v="${1#--status=}" ;; *) shift ;; esac
          ops=$(jq -c --arg v "$v" '. + [{f: "status", v: $v}]' <<<"$ops") ;;
        --assignee) ops=$(jq -c --arg v "$2" '. + [{f: "assignee", v: $v}]' <<<"$ops"); shift ;;
        --title) ops=$(jq -c --arg v "$2" '. + [{f: "title", v: $v}]' <<<"$ops"); shift ;;
        --description) ops=$(jq -c --arg v "$2" '. + [{f: "description", v: $v}]' <<<"$ops"); shift ;;
        --await-id) ops=$(jq -c --arg v "$2" '. + [{f: "await_id", v: $v}]' <<<"$ops"); shift ;;
        --append-notes) ops=$(jq -c --arg v "$2" '. + [{f: "append_notes", v: $v}]' <<<"$ops"); shift ;;
        --set-metadata) ops=$(jq -c --arg v "$2" '. + [{f: "set", v: $v}]' <<<"$ops"); shift ;;
        --unset-metadata) ops=$(jq -c --arg v "$2" '. + [{f: "unset", v: $v}]' <<<"$ops"); shift ;;
        *) echo "stub gc bd update: unsupported '$1'" >&2; exit 2 ;;
      esac
      shift
    done
    jq -e --arg id "$id" 'any(.[]; .id == $id)' "$S" >/dev/null || { echo "Error: issue $id not found" >&2; exit 1; }
    if [ -n "${MIG_CHANGE_HOLDER:-}" ] && [ "$ifa" != "__unset__" ] && [ "${MIG_CHANGE_HOLDER%%:*}" = "$id" ] && [ ! -e "$S.holder-changed" ]; then
      : > "$S.holder-changed"
      jq --arg id "$id" --arg w "${MIG_CHANGE_HOLDER#*:}" 'map(if .id == $id then .assignee = $w else . end)' "$S" > "$S.tmp" && mv "$S.tmp" "$S"
    fi
    if [ "$ifa" != "__unset__" ] || [ "$ifs" != "__unset__" ]; then
      jq -e --arg id "$id" --arg a "$ifa" --arg s "$ifs" '.[] | select(.id == $id)
        | ($a == "__unset__" or ((.assignee // "") == $a)) and ($s == "__unset__" or ((.status // "open") == $s))' "$S" >/dev/null \
        || { echo "Error: conditional update refused: $id changed" >&2; exit 13; }
    fi
    jq --arg id "$id" --argjson ops "$ops" 'map(if .id == $id then
        reduce $ops[] as $o (.;
          if $o.f == "append_notes" then .notes = (if (.notes // "") == "" then $o.v else .notes + "\n" + $o.v end)
          elif $o.f == "set" then ($o.v | index("=")) as $i | .metadata = ((.metadata // {}) + {($o.v[:$i]): $o.v[$i + 1:]})
          elif $o.f == "unset" then .metadata = ((.metadata // {}) | del(.[$o.v]))
          elif $o.f == "assignee" and $o.v == "" then del(.assignee)
          else .[$o.f] = $o.v end)
      else . end)' "$S" > "$S.new"
    commit "$S.new"; exit 0 ;;
  close)
    id="${1:-}"; shift || true; reason=""; force=0
    while [ $# -gt 0 ]; do
      case "$1" in --reason) reason="$2"; shift ;; --force) force=1 ;; esac; shift
    done
    why=$(jq -r --arg id "$id" --argjson force "$force" '. as $all | (.[] | select(.id == $id)) as $b
      | if $b == null then "not found"
        elif ($b.status // "open") == "closed" then ""
        elif $force == 0 and (($b.assignee // "") != "") then "assigned to " + $b.assignee
        elif any(($b.dependencies // [])[]; .type == "blocks" and (.depends_on_id as $d | any($all[]; .id == $d and (.status // "open") != "closed"))) then "blocked"
        elif any($all[]; (.status // "open") != "closed" and any((.dependencies // [])[]; .type == "parent-child" and .depends_on_id == $id)) then "has an open child"
        else "" end' "$S")
    [ -z "$why" ] || { echo "Error: cannot close $id: $why" >&2; exit 1; }
    jq --arg id "$id" --arg r "$reason" 'map(if .id == $id and (.status // "open") != "closed" then .status = "closed" | .close_reason = $r else . end)' "$S" > "$S.new"
    commit "$S.new"; exit 0 ;;
  create)
    title=""; desc=""; deps=""; assignee=""; notes=""; ty=task
    while [ $# -gt 0 ]; do
      case "$1" in
        -t|--type) ty="$2"; shift ;;
        --title) title="$2"; shift ;;
        -d|--description) desc="$2"; shift ;;
        --deps) deps="$2"; shift ;;
        --assignee|-a) assignee="$2"; shift ;;
        --notes) notes="$2"; shift ;;
        *) echo "stub gc bd create: unsupported '$1'" >&2; exit 2 ;;
      esac
      shift
    done
    [ -n "$PFX" ] || { echo '{"error":"no store named"}'; exit 1; }
    n=$(( $(cat "$S.seq" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$S.seq"
    id="$PFX-c$n"
    jq --arg id "$id" --arg ty "$ty" --arg t "$title" --arg d "$desc" --arg deps "$deps" --arg a "$assignee" --arg no "$notes" --argjson n "$n" '
      . + [ {id: $id, issue_type: $ty, title: $t, description: $d, notes: $no, status: "open", assignee: $a,
             created_at: ("2026-11-01T00:00:" + ($n | tostring)), metadata: {},
             dependencies: [ ($deps | split(",")[] | select(. != "") | index(":") as $i | {type: .[:$i], depends_on_id: .[$i + 1:]}) ]} ]' "$S" > "$S.new"
    commit "$S.new"
    printf '[{"id":"%s"}]\n' "$id"; exit 0 ;;
esac
echo "stub gc bd: unsupported verb '$verb'" >&2
exit 2
STUB
chmod +x "$BIN/gc"

SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/migrate-visits-to-gates.sh" "$HERE/human-gate.sh" "$HERE/conversation.sh"
SUT="$SD/migrate-visits-to-gates.sh"

export MIG_STORE="$TMP/store.json" MIG_SESSIONS="$TMP/sessions.json" MIG_RIGS="$TMP/rigs.json"
export MIG_WRITES="$TMP/writes" MIG_LOG="$TMP/gc-calls.log"
MIG_TEST_PGID="$(ps -o pgid= -p $$ | tr -d ' ')"; export MIG_TEST_PGID
export MIG_STOP_AFTER="" MIG_SESSION_STUCK="" MIG_STUCK_NOTE="" MIG_CHANGE_HOLDER=""
cat > "$MIG_RIGS" <<'RIGS'
{"city_path":"/city","rigs":[
 {"name":"mycity","prefix":"hq","path":"/city","hq":true,"suspended":false},
 {"name":"rig-a","prefix":"ra","path":"/city/rigs/rig-a","suspended":false},
 {"name":"rig-b","prefix":"rb","path":"/city/rigs/rig-b","suspended":true}]}
RIGS

# ── Fixtures ──────────────────────────────────────────────────────────
# b '<bead json>' adds a bead; its "deps" are [type, target] pairs, the edges
# the bead depends on (["blocks", G] = G blocks it). sess '<session json>' adds
# a session. fx_end assembles both and keeps a copy for fx_restore.
FX="$TMP/fx.jsonl"; SX="$TMP/sx.jsonl"
fx_begin() { : > "$FX"; : > "$SX"; }
b() { printf '%s\n' "$1" >> "$FX"; }
sess() { printf '%s\n' "$1" >> "$SX"; }
fx_end() {
  jq -s '[ to_entries[] | .key as $k | .value
           | .status //= "open" | .issue_type //= "task" | .metadata //= {} | .title //= .id
           | .created_at //= ("2026-10-01T" + ("00000" + ($k | tostring))[-5:])
           | .dependencies = [ (.deps // [])[] | {type: .[0], depends_on_id: .[1]} ] | del(.deps) ]' "$FX" > "$TMP/fixture.store"
  jq -s '.' "$SX" > "$TMP/fixture.sessions"
  fx_restore
}
fx_restore() {
  cp "$TMP/fixture.store" "$MIG_STORE"; cp "$TMP/fixture.sessions" "$MIG_SESSIONS"
  echo 0 > "$MIG_WRITES"; : > "$MIG_LOG"
  rm -f "$MIG_STORE.seq" "$MIG_STORE.stuck-noted" "$MIG_STORE.holder-changed"
}

# run_mig <args...> — one run in a process group of its own, so the stub can
# stop it after a write without touching the test. Sets OUT and RC.
OUT=""; RC=0
run_mig() {
  OUT=$(perl -e 'setpgrp(0, 0); exec @ARGV or die "exec: $!"' "$SUT" "$@" 2>&1); RC=$?
}

# ── Reads of the stub store ───────────────────────────────────────────
g() { jq -r --arg id "$1" "[ .[] | select(.id == \$id) | ($2) ] | if length == 0 then \"<absent>\" else (.[0] // \"\" | tostring) end" "$MIG_STORE"; }
# The await ids of the open human gates that block a bead, sorted.
gates_on() {
  jq -r --arg b "$1" '. as $all | [ .[] | select(.id == $b) | (.dependencies // [])[] | select(.type == "blocks") | .depends_on_id as $d
    | $all[] | select(.id == $d and .issue_type == "gate" and .await_type == "human" and (.status // "open") != "closed") | .await_id ] | sort | join(",")' "$MIG_STORE"
}
# The id of the open human gate under a key that blocks a bead.
gate_on() {
  jq -r --arg b "$1" --arg k "$2" '. as $all | [ .[] | select(.id == $b) | (.dependencies // [])[] | select(.type == "blocks") | .depends_on_id as $d
    | $all[] | select(.id == $d and .issue_type == "gate" and .await_type == "human" and .await_id == $k and (.status // "open") != "closed") | .id ] | first // "<none>"' "$MIG_STORE"
}
# The beads whose <type> edge names a bead, sorted.
waiters() {
  jq -r --arg b "$1" --arg t "$2" '[ .[] | select(any((.dependencies // [])[]; .type == $t and .depends_on_id == $b)) | .id ] | sort | join(",")' "$MIG_STORE"
}
# The conversations about a bead: tasks in the queue that track it.
convs_on() {
  jq -r --arg b "$1" '[ .[] | select(.issue_type == "task" and (.assignee // "") == "human" and (.status // "open") != "closed")
    | select([ (.dependencies // [])[] | select(.type == "tracks") | .depends_on_id ] == [$b]) | .id ] | join(",")' "$MIG_STORE"
}
pack_keys() { jq -r --arg id "$1" '.[] | select(.id == $id) | [ (.metadata // {}) | keys[] | select(IN("gc.demand_for","gc.demand_topic","gc.gate_visit","gc.routed_to","gc.takeaway","gc.takeaway_at","gc.takeaway_by","gc.takeaway_settled")) ] | join(",")' "$MIG_STORE"; }
writes() { cat "$MIG_WRITES"; }

# canon — the store and the sessions in one comparable form. A gate's
# description is left out: a run stopped between the helper's create and its
# description write leaves bd's own head over the message, which a rerun's
# dedup does not rewrite, and the title and await id are what a gate answers to.
canon() {
  jq -S '[ .[] | {id, issue_type, status: (.status // "open"), assignee: (.assignee // ""), title,
                  await_id: (.await_id // ""), close_reason: (.close_reason // ""),
                  description: (if .issue_type == "gate" then null else (.description // "") end),
                  notes: (.notes // ""), metadata: (.metadata // {}),
                  deps: ([ (.dependencies // [])[] | "\(.type):\(.depends_on_id)" ] | sort) } ] | sort_by(.id)' "$MIG_STORE"
  jq -S '[ .[] | {id, closed: (.closed // false)} ] | sort_by(.id)' "$MIG_SESSIONS"
}

# sweep <label> <args...> — the run, stopped after each write it makes and run
# again, ends where the uninterrupted run ends; and a run after an
# uninterrupted one writes nothing.
sweep() {
  local label="$1" total n stopped="" diverged=""
  shift
  fx_restore; run_mig "$@"; total=$(writes); canon > "$TMP/want.canon"
  echo 0 > "$MIG_WRITES"; run_mig "$@"
  eq "$(writes)" 0 "$label: a run after an uninterrupted one writes nothing"
  n=1
  while [ "$n" -le "$total" ]; do
    fx_restore
    MIG_STOP_AFTER="$n" run_mig "$@"
    [ "$RC" -eq 137 ] || stopped="$stopped $n(rc $RC)"
    MIG_STOP_AFTER="" run_mig "$@"
    canon > "$TMP/got.canon"
    cmp -s "$TMP/want.canon" "$TMP/got.canon" || { diverged="$diverged $n"; cp "$TMP/got.canon" "$TMP/diverged-$n.canon"; }
    n=$((n + 1))
  done
  [ "$total" -gt 0 ] || bad "$label: the uninterrupted run made no write to stop after"
  eq "${stopped:-none}" none "$label: each of the $total stopped runs was killed after its write"
  eq "${diverged:-none}" none "$label: a run stopped after any of its $total writes and run again ends as the uninterrupted run does"
  if [ -n "$diverged" ]; then
    n="${diverged# }"; n="${n%% *}"
    diff "$TMP/want.canon" "$TMP/diverged-$n.canon" | head -20 | sed 's/^/#   /'
  fi
}

# ── review: a recommendation beside a review's visit, references ──────
if part review; then
  echo "# a recommendation beside a review's visit, a sweep's visit, and the references"
  fx_begin
  b '{"id":"ra-anc1","title":"PR anchor one","metadata":{"merge_result":"pull_request","gc.recommended_formula":"mol-x"},"deps":[["blocks","ra-dfr1"]]}'
  b '{"id":"ra-dfr1","issue_type":"gate","await_type":"human","await_id":"gc-demand:ra-anc1:first-reaction","title":"Take mol-x?","description":"A first reaction recommends mol-x.","metadata":{"gc.demand_for":"ra-anc1","gc.demand_topic":"first-reaction","gc.takeaway":"Take the recommended mol-x?","gc.takeaway_at":"2026-10-01T00:00:00Z","gc.takeaway_by":"proactive","gc.takeaway_settled":"","gc.routed_to":"human","gc.gate_visit":"ra-vrev"}}'
  b '{"id":"ra-vrev","title":"visit: ra-anc1 — a review finding needs your decision","description":"Finding ra-f1 needs your decision on the retry bound.","notes":"sitting note on the review","created_by":"ra-wisp-rev","metadata":{"task_kind":"visit","escalation_key":"review-needs-you.ra-f1","gc.continuation_group":"ra-anc1","gc.routed_to":"human"},"deps":[["tracks","ra-anc1"]]}'
  b '{"id":"ra-f1","metadata":{"task_kind":"finding","anchor_bead":"ra-anc1","finding.disposition":"needs-you","finding.visit":"ra-vrev","finding.reply":"This comment needs your decision — opened visit ra-vrev. The review stays changes-requested until you rule it and the work your ruling calls for lands."}}'
  b '{"id":"ra-anc2","title":"PR anchor two","metadata":{"merge_result":"pull_request"},"deps":[["blocks","ra-dfr2"]]}'
  b '{"id":"ra-dfr2","issue_type":"gate","await_type":"human","await_id":"gc-demand:ra-anc2:first-reaction","title":"Take mol-y?","description":"","metadata":{"gc.demand_for":"ra-anc2","gc.demand_topic":"first-reaction","gc.takeaway":"Take the recommended mol-y?","gc.routed_to":"human","gc.gate_visit":"ra-vsw2"}}'
  b '{"id":"ra-vsw2","title":"visit: ra-anc2 — resolve the human gate on ra-anc2","description":"A human gate (ra-dfr2) blocks ra-anc2 and awaits a person.\nQuestion: Take mol-y?\nSettle it in this sitting, then resolve the gate: gc bd gate resolve ra-dfr2","created_by":"order:gate-visit-sweep","metadata":{"task_kind":"visit","gc.continuation_group":"ra-anc2","gc.routed_to":"human"},"deps":[["tracks","ra-anc2"]]}'
  b '{"id":"ra-vfold","status":"closed","close_reason":"folded","metadata":{"task_kind":"visit","gc.folded_into":"ra-vrev"}}'
  b '{"id":"ra-f2","metadata":{"task_kind":"finding","anchor_bead":"ra-anc1","finding.disposition":"needs-you","finding.visit":"ra-vfold"}}'
  b '{"id":"ra-vruled","status":"closed","close_reason":"ruled","metadata":{"task_kind":"visit","gc.ruling":"keep the bound at three"}}'
  b '{"id":"ra-f3","metadata":{"task_kind":"finding","anchor_bead":"ra-anc1","finding.disposition":"needs-you","finding.visit":"ra-vruled"}}'
  b '{"id":"ra-f4","status":"closed","metadata":{"task_kind":"finding","finding.disposition":"needs-you","finding.ruling_visit":"ra-vruled"}}'
  b '{"id":"ra-vnorule","status":"closed","close_reason":"benign","metadata":{"task_kind":"visit"}}'
  b '{"id":"ra-f5","metadata":{"task_kind":"finding","anchor_bead":"ra-anc1","finding.disposition":"needs-you","finding.visit":"ra-vnorule"}}'
  b '{"id":"ra-anc3","title":"PR anchor three","metadata":{"merge_result":"pull_request","pr_comment_disposition":"visit:ra-vop3"}}'
  b '{"id":"ra-vop3","title":"visit: ra-anc3 — a routed comment","description":"The comment asks for a rename.","created_by":"hq-wisp-op","metadata":{"task_kind":"visit","gc.continuation_group":"ra-anc3","gc.routed_to":"human"},"deps":[["tracks","ra-anc3"]]}'
  b '{"id":"ra-anc4","title":"PR anchor four","metadata":{"merge_result":"pull_request","pr_comment_disposition":"visit:ra-vold4"}}'
  b '{"id":"ra-vold4","status":"closed","close_reason":"answered","metadata":{"task_kind":"visit"}}'
  b '{"id":"hq-n1","issue_type":"message","assignee":"human","title":"Human gate awaiting you: ra-dfr1"}'
  b '{"id":"hq-n2","issue_type":"message","assignee":"human","title":"ESCALATION: a stalled patrol"}'
  fx_end

  cp "$MIG_STORE" "$TMP/before.json"
  run_mig --all --dry-run
  eq "$RC" 0 "a dry run exits 0"
  has "$OUT" "would file visit ra-vrev as a human gate on ra-anc1 [review-needs-you.ra-f1]" "a dry run names each visit's plan"
  eq "$(writes)" 0 "a dry run writes nothing"
  cmp -s "$MIG_STORE" "$TMP/before.json" && ok "a dry run leaves the store byte-identical" || bad "a dry run changed the store"

  run_mig --all
  eq "$RC" 0 "the run completes"
  eq "$(gates_on ra-anc1)" "first-reaction,review-needs-you.ra-f1" "the anchor waits on two gates: the recommendation's and the review's"
  G1=$(gate_on ra-anc1 review-needs-you.ra-f1)
  eq "$(g "$G1" '.title')" "a review finding needs your decision" "the review gate takes the visit's headline as its title"
  has "$(g "$G1" '.description')" "Finding ra-f1 needs your decision on the retry bound." "the review gate's description carries the visit's framing"
  has "$(g "$G1" '.notes')" "Carried from visit ra-vrev:" "the review gate's notes name the visit they carry"
  has "$(g "$G1" '.notes')" "sitting note on the review" "the review gate carries the visit's notes"
  hasnt "$(g "$G1" '.notes')" "What it asked:" "the framing the description already holds is not carried twice"
  eq "$(g ra-vrev '.status'):$(g ra-vrev '.close_reason')" "closed:migrated: gate $G1" "the review's visit closes migrated onto its gate"
  eq "$(g ra-dfr1 '.await_id')" "first-reaction" "the recommendation's demand is shaped: its await id is its key"
  eq "$(g ra-dfr1 '.title')" "Take the recommended mol-x?" "the recommendation's demand takes its takeaway as its title"
  eq "$(pack_keys ra-dfr1)" "" "the recommendation's demand sheds its pack keys"
  eq "$(g ra-anc1 '.metadata["gc.recommended_formula"]')" "mol-x" "the anchor keeps its recommendation"
  eq "$(g ra-f1 '.metadata["finding.gate"]')" "$G1" "the needs-you finding names the review gate"
  eq "$(g ra-f1 '.metadata["finding.visit"]')" "" "the needs-you finding no longer names the visit"
  has "$(g ra-f1 '.metadata["finding.reply"]')" "human gate $G1" "the unposted reply names the gate"
  eq "$(gates_on ra-anc2)" "first-reaction" "the sweep's visit leaves one gate on its anchor, the recommendation's"
  eq "$(g ra-vsw2 '.close_reason')" "migrated: gate ra-dfr2" "the sweep's visit closes into the demand it put to a person"
  has "$(g ra-dfr2 '.notes')" "A human gate (ra-dfr2) blocks ra-anc2" "the demand carries the sweep visit's framing"
  eq "$(g ra-f2 '.metadata["finding.gate"]')" "$G1" "a finding whose visit was folded walks the fold to the gate"
  eq "$(g ra-f3 '.metadata["finding.ruling_bead"]'):$(g ra-f3 '.status')" "ra-vruled:open" "a finding whose visit closed with a ruling records it and stays open"
  eq "$(g ra-f4 '.metadata["finding.ruling_bead"]'):$(g ra-f4 '.metadata["finding.ruling_visit"]')" "ra-vruled:" "finding.ruling_visit is renamed finding.ruling_bead"
  eq "$(g ra-f5 '.metadata["finding.visit"]')" "" "a finding whose visit closed with no ruling drops the visit"
  has "$(g ra-f5 '.notes')" "ra-vnorule" "and its notes name that visit"
  G3=$(gate_on ra-anc3 conversation.ra-vop3)
  eq "$(g ra-anc3 '.metadata.pr_comment_disposition')" "human:$G3" "a routed comment's disposition names the gate its visit became"
  eq "$(g ra-anc4 '.metadata.pr_comment_disposition')" "human:ra-vold4" "a disposition on a visit closed before the cutover names that visit"
  eq "$(g hq-n1 '.status'):$(g hq-n2 '.status')" "closed:open" "the city's gate notice closes and the escalation notice stays"
  sweep "review" --all
fi

# ── holds: held visits, the hold-merge pair, a liveness sweep's visit ──
if part holds; then
  echo "# held visits, the hold-merge pairs and a liveness sweep's census"
  fx_begin
  b '{"id":"ra-p4","title":"plain bead four","deps":[["blocks","ra-dh4"]]}'
  b '{"id":"ra-dh4","issue_type":"gate","await_type":"human","await_id":"gc-demand:ra-p4","title":"Should the cache stay?","description":"","metadata":{"gc.demand_for":"ra-p4","gc.takeaway":"Should the cache stay?","gc.routed_to":"human"}}'
  b '{"id":"ra-vhold","title":"visit: ra-p4 — the cache question","description":"The cache costs 2 GB and saves 40 s a pass. Keeping it means a nightly prune; dropping it means slower passes.","created_by":"hq-wisp-op","metadata":{"task_kind":"visit","gc.continuation_group":"ra-p4","gc.routed_to":"human","gc.hold_demand":"ra-dh4"},"deps":[["tracks","ra-p4"]]}'
  b '{"id":"ra-anc5","title":"PR anchor five","metadata":{"merge_result":"pull_request"},"deps":[["blocks","ra-dh5b"]]}'
  b '{"id":"ra-vhold5","title":"visit: ra-anc5 — hold for the naming call","description":"Hold the merge until the naming is settled.","created_by":"ra-wisp-esc","metadata":{"task_kind":"visit","escalation_key":"naming-call","gc.continuation_group":"ra-anc5","gc.routed_to":"human","gc.hold_demand":"ra-dh5a"},"deps":[["tracks","ra-anc5"],["blocks","ra-dh5a"]]}'
  b '{"id":"ra-dh5a","issue_type":"gate","await_type":"human","await_id":"gc-demand:ra-vhold5:naming-call","title":"Settle the naming","metadata":{"gc.demand_for":"ra-vhold5","gc.demand_topic":"naming-call","gc.takeaway":"Settle the naming","gc.routed_to":"human","gc.gate_visit":"ra-vhold5"}}'
  b '{"id":"ra-dh5b","issue_type":"gate","await_type":"human","await_id":"gc-demand:ra-anc5:naming-call","title":"Settle the naming","metadata":{"gc.demand_for":"ra-anc5","gc.demand_topic":"naming-call","gc.takeaway":"Settle the naming","gc.routed_to":"human"}}'
  b '{"id":"ra-anc6","title":"PR anchor six","metadata":{"merge_result":"pull_request"},"deps":[["blocks","ra-dh6b"]]}'
  b '{"id":"ra-vhold6","title":"visit: ra-anc6 — hold the merge","description":"Hold the merge for the operator.","created_by":"hq-wisp-op","metadata":{"task_kind":"visit","gc.continuation_group":"ra-anc6","gc.routed_to":"human","gc.hold_demand":"ra-dh6a"},"deps":[["tracks","ra-anc6"],["blocks","ra-dh6a"]]}'
  b '{"id":"ra-dh6a","issue_type":"gate","await_type":"human","await_id":"gc-demand:ra-vhold6","title":"Decide the merge","metadata":{"gc.demand_for":"ra-vhold6","gc.takeaway":"Decide the merge","gc.routed_to":"human"}}'
  b '{"id":"ra-dh6b","issue_type":"gate","await_type":"human","await_id":"gc-demand:ra-anc6","title":"Decide the merge","metadata":{"gc.demand_for":"ra-anc6","gc.takeaway":"Decide the merge","gc.routed_to":"human"}}'
  b '{"id":"ra-tri","title":"triage: stalled beads (this rig)","metadata":{"task_kind":"triage-subject","triage.scope":"liveness"}}'
  b '{"id":"ra-vlive","title":"visit: ra-tri — 3 beads look stalled","description":"Census cut 2026-10-20T00:00:00Z — a snapshot, not the board. Run the visit.recheck stamp on this visit before acting.","created_by":"order:liveness-sweep","metadata":{"task_kind":"visit","escalation_key":"liveness-stalled","gc.continuation_group":"ra-tri","gc.routed_to":"human","visit.recheck":"/old/pack/assets/scripts/liveness-recheck.sh","sweep.new_ids":"ra-x1,ra-x2","sweep.carried_ids":"ra-x3","sweep.pass_at":"2026-10-20T00:00:00Z"},"deps":[["tracks","ra-tri"]]}'
  fx_end

  run_mig --rig rig-a
  eq "$RC" 0 "the run completes"
  eq "$(g ra-vhold '.close_reason')" "migrated: gate ra-dh4" "a held visit closes into its hold's demand"
  has "$(g ra-dh4 '.notes')" "The cache costs 2 GB and saves 40 s a pass." "the demand, whose own description is empty, carries the held visit's description"
  eq "$(g ra-dh4 '.await_id')" "conversation.ra-vhold" "a keyless hold's demand takes the key that names its visit"
  eq "$(gates_on ra-p4)" "conversation.ra-vhold" "the held bead waits on that one gate"
  eq "$(g ra-vhold5 '.close_reason')" "migrated: gate ra-dh5a" "a held anchor's visit closes into its oldest demand"
  eq "$(gates_on ra-anc5)" "naming-call,naming-call" "both of the hold's demands block the anchor under the visit's key"
  eq "$(waiters ra-dh5a blocks)" "ra-anc5" "the demand filed on the visit moved its edge to the anchor"
  eq "$(gates_on ra-anc6)" "conversation.ra-dh6b,conversation.ra-vhold6" "a keyless hold-merge demand stays a second gate under a key of its own"
  eq "$(g ra-vhold6 '.close_reason')" "migrated: gate ra-dh6a" "the keyless held visit closes into the demand its hold filed"
  for d in ra-dh4 ra-dh5a ra-dh5b ra-dh6a ra-dh6b; do eq "$(pack_keys "$d")" "" "demand $d sheds its pack keys"; done
  GL=$(gate_on ra-tri liveness-stalled)
  has "$(g "$GL" '.notes')" "Re-check the census before acting: liveness-recheck.sh --ids ra-x1,ra-x2 --carried ra-x3 --pass-at 2026-10-20T00:00:00Z" "the liveness gate carries the re-check command built from the visit's census"
  hasnt "$(g "$GL" '.notes' | grep 'liveness-recheck.sh')" "ra-vlive" "the re-check command names no visit"
  hasnt "$(g "$GL" '.notes')" "/old/pack" "the command names the script, not the stamp's path"
  eq "$(g ra-vlive '.status')" "closed" "the liveness sweep's visit closes"
  sweep "holds" --rig rig-a
fi

# ── opened: visits the operator opened, and visits escalate.sh filed ──
if part opened; then
  echo "# visits the operator opened and visits escalate.sh filed"
  fx_begin
  b '{"id":"ra-p6","title":"plain bead six"}'
  b '{"id":"ra-vop6","title":"visit: ra-p6 — why is this slow?","description":"The operator asks why the pass is slow.","notes":"operator context: it doubled this week","created_by":"hq-wisp-op","metadata":{"task_kind":"visit","gc.continuation_group":"ra-p6","gc.routed_to":"human"},"deps":[["tracks","ra-p6"]]}'
  b '{"id":"ra-anc7","title":"PR anchor seven","metadata":{"merge_result":"pull_request"}}'
  b '{"id":"ra-vop7a","title":"visit: ra-anc7 — first look","created_by":"hq-wisp-op","metadata":{"task_kind":"visit","gc.continuation_group":"ra-anc7","gc.routed_to":"human"},"deps":[["tracks","ra-anc7"]]}'
  b '{"id":"ra-vop7b","title":"visit: ra-anc7 — second look","created_by":"hq-wisp-op","metadata":{"task_kind":"visit","gc.continuation_group":"ra-anc7","gc.routed_to":"human"},"deps":[["tracks","ra-anc7"]]}'
  b '{"id":"ra-epic8","issue_type":"epic","title":"an epic"}'
  b '{"id":"ra-e8c","title":"a member","deps":[["parent-child","ra-epic8"]]}'
  b '{"id":"ra-vesc8","title":"visit: ra-epic8 — the epic stalled","created_by":"ra-wisp-esc","metadata":{"task_kind":"visit","escalation_key":"epic-stalled","gc.continuation_group":"ra-epic8","gc.routed_to":"human"},"deps":[["tracks","ra-epic8"]]}'
  b '{"id":"ra-t9","title":"a task with a part"}'
  b '{"id":"ra-t9c","title":"its part","deps":[["parent-child","ra-t9"]]}'
  b '{"id":"ra-vesc9","title":"visit: ra-t9 — a blocker","created_by":"ra-wisp-esc","metadata":{"task_kind":"visit","escalation_key":"polecat-blocked","gc.continuation_group":"ra-t9","gc.routed_to":"human"},"deps":[["tracks","ra-t9"]]}'
  b '{"id":"ra-c12","status":"closed","title":"closed bead"}'
  b '{"id":"ra-v12","title":"visit: ra-c12 — a late question","description":"Was the close right?","created_by":"hq-wisp-op","metadata":{"task_kind":"visit","gc.continuation_group":"ra-c12","gc.routed_to":"human"},"deps":[["tracks","ra-c12"]]}'
  b '{"id":"ra-v13","title":"visit: ra-gone13 — a lost subject","created_by":"hq-wisp-op","metadata":{"task_kind":"visit","gc.continuation_group":"ra-gone13","gc.routed_to":"human"}}'
  b '{"id":"ra-p14","title":"plain bead fourteen"}'
  b '{"id":"ra-vesc14","title":"visit: ra-p14 — requirements unclear","description":"Which store does it read?","created_by":"ra-wisp-esc","metadata":{"task_kind":"visit","escalation_key":"polecat-unclear-requirements","gc.continuation_group":"ra-p14","gc.routed_to":"human"},"deps":[["tracks","ra-p14"]]}'
  b '{"id":"ra-p25","title":"pre-open anchor"}'
  b '{"id":"ra-vhyb25","title":"visit: ra-p25 — convergence stalled","created_by":"ra-wisp-esc","metadata":{"task_kind":"visit","escalation_key":"convergence-stalled","gc.demand_for":"ra-p25","gc.gate_visit":"ra-vhyb25","gc.continuation_group":"ra-p25","gc.routed_to":"human"},"deps":[["tracks","ra-p25"]]}'
  fx_end

  run_mig --rig rig-a
  eq "$RC" 0 "the run completes"
  C6=$(convs_on ra-p6)
  [ -n "$C6" ] && ok "a visit the operator opened on a plain bead becomes a conversation in the queue" || bad "no conversation on ra-p6"
  eq "$(g "$C6" '.title')" "why is this slow?" "the conversation takes the visit's headline"
  eq "$(g "$C6" '.description')" "The operator asks why the pass is slow." "its description is the visit's framing"
  has "$(g "$C6" '.notes')" "Carried from visit ra-vop6:" "its notes name the visit"
  has "$(g "$C6" '.notes')" "operator context: it doubled this week" "and carry the visit's notes"
  eq "$(gates_on ra-p6)" "" "the plain bead gains no wait"
  eq "$(g ra-vop6 '.close_reason')" "migrated: conversation $C6" "the visit closes migrated onto the conversation"
  eq "$(gates_on ra-anc7)" "conversation.ra-vop7a,conversation.ra-vop7b" "two operator visits on a PR anchor each leave a gate of their own that holds the merge"
  eq "$(gates_on ra-epic8)$(convs_on ra-epic8 | grep -c .)" "1" "a visit escalate.sh filed on an epic with open children becomes a conversation and adds no wait"
  eq "$(gates_on ra-t9)$(convs_on ra-t9 | grep -c .)" "1" "so does one on a task with an open part"
  eq "$(convs_on ra-c12 | grep -c .)" "1" "a visit on a closed subject that nothing waits on becomes a conversation tracking that subject"
  eq "$(g ra-v13 '.status')" "open" "a visit whose subject no longer exists, with no waiter, stays open"
  has "$OUT" "LEFT OPEN for a person: visit ra-v13" "and the report names it"
  eq "$(gates_on ra-p14)" "polecat-unclear-requirements" "a visit escalate.sh filed on a plain bead becomes a gate that blocks it"
  eq "$(gates_on ra-p25)" "convergence-stalled" "a visit carrying gc.demand_for for its own subject migrates as a visit"
  eq "$(g ra-vhyb25 '.close_reason')" "migrated: gate $(gate_on ra-p25 convergence-stalled)" "and closes onto its gate"
  echo 0 > "$MIG_WRITES"; run_mig --rig rig-a
  eq "$(convs_on ra-p6 | grep -c .)" "1" "a rerun files no second conversation"
  sweep "opened" --rig rig-a
fi

# ── gates: gates as subjects, until waits, the first blocks waiter ────
if part gates; then
  echo "# visits about gates, until waits and a gate on the first waiter"
  fx_begin
  b '{"id":"ra-p10","title":"bead with a part"}'
  b '{"id":"ra-p10c","title":"its part","deps":[["parent-child","ra-p10"]]}'
  b '{"id":"ra-v10","title":"visit: ra-p10 — q","created_by":"hq-wisp-op","metadata":{"task_kind":"visit","gc.continuation_group":"ra-p10","gc.routed_to":"human"},"deps":[["tracks","ra-p10"]]}'
  b '{"id":"ra-w10","title":"resolved by the answer","deps":[["until","ra-v10"]]}'
  b '{"id":"ra-p11","title":"self-resolving bead","deps":[["until","ra-v11"]]}'
  b '{"id":"ra-v11","title":"visit: ra-p11 — q","created_by":"hq-wisp-op","metadata":{"task_kind":"visit","gc.continuation_group":"ra-p11","gc.routed_to":"human"},"deps":[["tracks","ra-p11"]]}'
  b '{"id":"ra-p15","title":"plain bead fifteen","deps":[["blocks","ra-dt15"]]}'
  b '{"id":"ra-dt15","issue_type":"gate","await_type":"human","await_id":"gc-demand:ra-p15:t15","title":"Pick a store","metadata":{"gc.demand_for":"ra-p15","gc.demand_topic":"t15","gc.takeaway":"Pick a store","gc.routed_to":"human"}}'
  b '{"id":"ra-vop15","title":"visit: ra-dt15 — talk it through","description":"Talk through the store choice.","created_by":"hq-wisp-op","metadata":{"task_kind":"visit","gc.continuation_group":"ra-dt15","gc.routed_to":"human"},"deps":[["tracks","ra-dt15"]]}'
  b '{"id":"ra-g16","issue_type":"gate","await_type":"human","await_id":"k16","title":"A shared question"}'
  b '{"id":"ra-q16a","title":"waiter a","deps":[["blocks","ra-g16"]]}'
  b '{"id":"ra-q16b","title":"waiter b","deps":[["blocks","ra-g16"]]}'
  b '{"id":"ra-vop16","title":"visit: ra-g16 — about the shared question","created_by":"hq-wisp-op","metadata":{"task_kind":"visit","gc.continuation_group":"ra-g16","gc.routed_to":"human"},"deps":[["tracks","ra-g16"]]}'
  b '{"id":"ra-p17","title":"bead with a part"}'
  b '{"id":"ra-p17c","title":"its part","deps":[["parent-child","ra-p17"]]}'
  b '{"id":"ra-vesc17","title":"visit: ra-p17 — needs a call","created_by":"ra-wisp-esc","metadata":{"task_kind":"visit","escalation_key":"k17","gc.continuation_group":"ra-p17","gc.routed_to":"human"},"deps":[["tracks","ra-p17"]]}'
  b '{"id":"ra-w17","title":"declined work","deps":[["blocks","ra-vesc17"]]}'
  b '{"id":"ra-p18","title":"plain bead eighteen"}'
  b '{"id":"ra-vesc18","title":"visit: ra-p18 — blocked","created_by":"ra-wisp-esc","metadata":{"task_kind":"visit","escalation_key":"k18","gc.continuation_group":"ra-p18","gc.routed_to":"human"},"deps":[["tracks","ra-p18"]]}'
  b '{"id":"ra-w18","title":"work that waits on the ruling","deps":[["blocks","ra-vesc18"]]}'
  b '{"id":"ra-u18","title":"resolved by the ruling","deps":[["until","ra-vesc18"]]}'
  fx_end

  run_mig --rig rig-a
  eq "$RC" 0 "the run completes"
  eq "$(g ra-v10 '.status'):$(g ra-v11 '.status')" "open:open" "a visit whose only waiter holds an until edge, on a subject a gate cannot block, stays open, and so does one whose subject's own edge is until"
  eq "$(waiters ra-v10 until),$(waiters ra-v11 until)" "ra-w10,ra-p11" "no until waiter is resolved or moved"
  C15=$(convs_on ra-p15)
  [ -n "$C15" ] && ok "a visit the operator opened on a demand becomes a conversation about the bead the demand blocks" || bad "no conversation on ra-p15"
  eq "$(jq -r --arg c "$C15" '.[] | select(.id == $c) | [ .dependencies[] | select(.type == "replies-to") | .depends_on_id ] | join(",")' "$MIG_STORE")" "ra-dt15" "and the conversation replies to that demand"
  eq "$(g ra-dt15 '.await_id')" "t15" "the demand is shaped under its own topic"
  eq "$(g ra-vop16 '.status')" "open" "a visit about a gate two beads wait on stays open"
  has "$OUT" "leaves 2 open beads waiting" "and the report says why"
  eq "$(gates_on ra-p17)" "" "a gate cannot block a bead with an open part"
  eq "$(gates_on ra-w17)" "k17" "so it blocks the first bead that waited on the visit"
  G18=$(gate_on ra-p18 k18)
  eq "$(waiters "$G18" blocks)" "ra-p18,ra-w18" "the work that waited on the visit waits on its gate"
  eq "$(waiters "$G18" until)" "ra-u18" "and the until waiter's edge names the gate"
  sweep "gates" --rig rig-a
fi

# ── sittings: the sessions on visits end first, and holders release ──
if part sittings; then
  echo "# sittings end before anything moves, and each visit is released from its holder"
  fx_begin
  b '{"id":"ra-p18","title":"plain bead"}'
  b '{"id":"ra-v18","status":"in_progress","assignee":"rig-a/gc-toolkit.ra-v18","title":"visit: ra-p18 — a live sitting","description":"Live sitting framing.","notes":"last sitting note","created_by":"hq-wisp-op","metadata":{"task_kind":"visit","gc.continuation_group":"ra-p18","gc.routed_to":"human"},"deps":[["tracks","ra-p18"]]}'
  b '{"id":"ra-v19","status":"in_progress","assignee":"rig-a/gc-toolkit.ra-v19","title":"visit: ra-p18 — a gone sitting","created_by":"hq-wisp-op","metadata":{"task_kind":"visit","escalation_key":"k19","gc.continuation_group":"ra-p18","gc.routed_to":"human"},"deps":[["tracks","ra-p18"]]}'
  b '{"id":"ra-v20","assignee":"s-gone20","title":"visit: ra-p18 — bound, never claimed","created_by":"hq-wisp-op","metadata":{"task_kind":"visit","escalation_key":"k20","gc.continuation_group":"ra-p18","gc.routed_to":"human"},"deps":[["tracks","ra-p18"]]}'
  b '{"id":"rb-p21","title":"a suspended rig bead"}'
  b '{"id":"rb-v21","status":"in_progress","assignee":"rig-b/gc-toolkit.rb-v21","title":"visit: rb-p21 — a sitting in another store","created_by":"hq-wisp-op","metadata":{"task_kind":"visit","gc.continuation_group":"rb-p21","gc.routed_to":"human"},"deps":[["tracks","rb-p21"]]}'
  b '{"id":"ra-v23","title":"visit: ra-p18 — has a child","created_by":"hq-wisp-op","metadata":{"task_kind":"visit","escalation_key":"k23","gc.continuation_group":"ra-p18","gc.routed_to":"human"},"deps":[["tracks","ra-p18"]]}'
  b '{"id":"ra-v23c","title":"a child of the visit","deps":[["parent-child","ra-v23"]]}'
  b '{"id":"ra-v24","status":"in_progress","assignee":"hq-wisp-s24","title":"visit: ra-p18 — held by a city-store session id","created_by":"hq-wisp-op","metadata":{"task_kind":"visit","escalation_key":"k24","gc.continuation_group":"ra-p18","gc.routed_to":"human"},"deps":[["tracks","ra-p18"]]}'
  b '{"id":"ra-conv1","title":"a conversation","assignee":"rig-a/gc-toolkit.ra-conv1","deps":[["tracks","ra-p18"]]}'
  sess '{"id":"s18","alias":"rig-a/gc-toolkit.ra-v18","session_name":"s-s18","template":"rig-a/gc-toolkit.converse-opus","state":"active"}'
  sess '{"id":"s19","alias":"rig-a/gc-toolkit.ra-v19","session_name":"s-s19","template":"rig-a/gc-toolkit.converse-opus","state":"closed","closed":true}'
  sess '{"id":"s21","alias":"rig-b/gc-toolkit.rb-v21","session_name":"s-s21","template":"rig-b/gc-toolkit.converse-opus","state":"active"}'
  sess '{"id":"s22","alias":"rig-a/gc-toolkit.ra-conv1","session_name":"s-s22","template":"rig-a/gc-toolkit.converse-opus","state":"active"}'
  sess '{"id":"s23","alias":"rig-a/gc-toolkit.polecat-1","session_name":"s-s23","template":"rig-a/gc-toolkit.polecat","state":"active"}'
  fx_end

  run_mig --rig mycity
  eq "$RC" 0 "the city store's run completes"
  eq "$(jq -r '[ .[] | select(.closed == true) | .id ] | sort | join(",")' "$MIG_SESSIONS")" "s18,s19,s21" "the city store's run ends the sittings on visits in every store, and no other session"
  run_mig --rig rig-a
  eq "$RC" 0 "the rig's run completes"
  C18=$(jq -r '[ .[] | select(.issue_type == "task" and ((.notes // "") | contains("Carried from visit ra-v18:"))) | .id ] | first // "<none>"' "$MIG_STORE")
  has "$(g "$C18" '.notes')" "last sitting note" "the note the sitting appended last is carried"
  for v in ra-v18 ra-v19 ra-v20 ra-v24; do
    eq "$(g "$v" '.status'):$(g "$v" '.assignee')" "closed:" "visit $v is released from its holder and closed"
  done
  eq "$(g ra-v23 '.status'):$(g ra-v23 '.assignee')" "open:" "a released visit with an open child stays open and unassigned"
  has "$OUT" "LEFT OPEN for a person: visit ra-v23" "and the report names it"
  grep -q 'update ra-v24 --if-assignee hq-wisp-s24' "$MIG_LOG" && ok "the release of a visit held by a city-store session id is written to the visit" || bad "no guarded release of ra-v24 in the call log"
  run_mig --rig rig-b
  eq "$(g rb-v21 '.status')" "closed" "the visit in the suspended rig's store is migrated by its own run"
  sweep "sittings" --all
fi

# ── stuck: a sitting whose session will not stop moves nothing ────────
if part stuck; then
  echo "# a sitting that survives the run's first pass, and a holder that changes"
  fx_begin
  b '{"id":"ra-p26","title":"plain bead"}'
  b '{"id":"ra-v26","status":"in_progress","assignee":"rig-a/gc-toolkit.ra-v26","title":"visit: ra-p26 — the stuck sitting","created_by":"hq-wisp-op","metadata":{"task_kind":"visit","gc.continuation_group":"ra-p26","gc.routed_to":"human"},"deps":[["tracks","ra-p26"]]}'
  b '{"id":"ra-v27","title":"visit: ra-p26 — a second visit","created_by":"hq-wisp-op","metadata":{"task_kind":"visit","gc.continuation_group":"ra-p26","gc.routed_to":"human"},"deps":[["tracks","ra-p26"]]}'
  b '{"id":"ra-p28","title":"plain bead"}'
  b '{"id":"ra-v28","status":"in_progress","assignee":"rig-a/gc-toolkit.ra-v28","title":"visit: ra-p28 — a holder that changes","created_by":"hq-wisp-op","metadata":{"task_kind":"visit","escalation_key":"k28","gc.continuation_group":"ra-p28","gc.routed_to":"human"},"deps":[["tracks","ra-p28"]]}'
  sess '{"id":"s26","alias":"rig-a/gc-toolkit.ra-v26","session_name":"s-s26","template":"rig-a/gc-toolkit.converse-opus","state":"active"}'
  fx_end

  cp "$MIG_STORE" "$TMP/before.json"
  MIG_SESSION_STUCK=s26 MIG_STUCK_NOTE="ra-v27:late note from the surviving sitting" run_mig --all
  eq "$RC" 3 "a sitting whose session does not stop ends the run with exit 3"
  has "$OUT" "s26 on visit ra-v26 did not stop" "the report names the session and its visit"
  eq "$(writes)" 0 "and nothing is written in any store"
  eq "$(g ra-v26 '.status'):$(g ra-v27 '.status')" "in_progress:open" "both visits stay open"
  has "$(g ra-v27 '.notes')" "late note from the surviving sitting" "so the sitting's late note lands on an open visit"
  MIG_SESSION_STUCK=s26 run_mig --rig rig-b
  eq "$RC:$(writes)" "3:0" "a run for another store moves nothing while the sitting survives"
  MIG_CHANGE_HOLDER="ra-v28:rig-a/gc-toolkit.someone-else" run_mig --all
  eq "$RC" 0 "once the session stops, the run completes"
  C27=$(jq -r '[ .[] | select(.issue_type == "task" and ((.notes // "") | contains("Carried from visit ra-v27:"))) | .id ] | first // "<none>"' "$MIG_STORE")
  has "$(g "$C27" '.notes')" "late note from the surviving sitting" "the second visit's conversation carries the late note"
  eq "$(g ra-v28 '.status'):$(g ra-v28 '.assignee')" "in_progress:rig-a/gc-toolkit.someone-else" "a release that finds a new holder writes nothing"
  has "$OUT" "its release from rig-a/gc-toolkit.ra-v28 did not land" "and the report names the visit"
  MIG_CHANGE_HOLDER="ra-v28:rig-a/gc-toolkit.someone-else" run_mig --all
  eq "$(g ra-v28 '.status')" "closed" "a rerun releases it from the holder it reads then, and closes it"
fi

# ── steps: the steps poured with the gate-visit block ────────────────
if part steps; then
  echo "# steps poured with the gate-visit block, and the check"
  BLOCK='Run this.\n```bash\n# >>> gate-visit\nPOOL=human\n# <<< gate-visit\n```'
  fx_begin
  b "{\"id\":\"ra-sA\",\"assignee\":\"sA\",\"title\":\"validate and resolve\",\"description\":\"$BLOCK\",\"metadata\":{\"gc.step_ref\":\"mol-validate-close.validate-and-resolve\",\"gc.root_bead_id\":\"ra-rA\"}}"
  b "{\"id\":\"ra-sB\",\"title\":\"file and dispatch\",\"description\":\"$BLOCK\",\"metadata\":{\"gc.step_ref\":\"mol-feedback-distiller.file-and-dispatch\",\"gc.root_bead_id\":\"ra-rB\"}}"
  b "{\"id\":\"ra-sC\",\"status\":\"closed\",\"assignee\":\"sC\",\"title\":\"cancelled step\",\"description\":\"$BLOCK\",\"metadata\":{\"gc.step_ref\":\"mol-validate-close.validate-and-resolve\",\"gc.root_bead_id\":\"ra-rC\",\"gc.outcome\":\"canceled\"}}"
  b "{\"id\":\"ra-sD\",\"status\":\"closed\",\"assignee\":\"sD\",\"title\":\"replaced step\",\"description\":\"$BLOCK\",\"metadata\":{\"gc.step_ref\":\"mol-feedback-distiller.file-and-dispatch\",\"gc.root_bead_id\":\"ra-rD\",\"gc.outcome\":\"skipped\"}}"
  b "{\"id\":\"ra-sE\",\"status\":\"closed\",\"assignee\":\"sE-gone\",\"title\":\"cancelled, its session gone\",\"description\":\"$BLOCK\",\"metadata\":{\"gc.step_ref\":\"mol-validate-close.validate-and-resolve\",\"gc.root_bead_id\":\"ra-rE\",\"gc.outcome\":\"canceled\"}}"
  b "{\"id\":\"ra-wq\",\"title\":\"a work bead quoting the block\",\"description\":\"$BLOCK\"}"
  b '{"id":"ra-sF","title":"a longer marker","description":"# >>> gate-visit-extra\n","metadata":{"gc.step_ref":"mol-x.y","gc.root_bead_id":"ra-rF"}}'
  for s in A B C D; do b "{\"id\":\"ra-p$s\",\"title\":\"subject $s\"}"; done
  sess '{"id":"sC","alias":"rig-a/gc-toolkit.polecat-3","session_name":"s-sC","template":"rig-a/gc-toolkit.polecat","state":"active"}'
  sess '{"id":"sD","alias":"rig-a/gc-toolkit.polecat-4","session_name":"s-sD","template":"rig-a/gc-toolkit.polecat","state":"active"}'
  fx_end

  run_mig --rig rig-a
  eq "$RC" 0 "the run completes"
  for s in ra-sA ra-sB ra-sC ra-sD; do has "$OUT" "step that can still file a visit: $s " "the run reports step $s"; done
  for s in ra-sE ra-wq ra-sF; do hasnt "$OUT" "step that can still file a visit: $s " "the run does not count $s"; done
  # Each step files its keyless visit after the run, as the block would.
  for s in A B C D; do
    jq --arg s "$s" '. + [{id: ("ra-v" + $s), issue_type: "task", status: "open", title: ("visit: ra-p" + $s + " — proposed close did not validate: accept or redirect"), description: "Accept or redirect the close.", created_by: "sA", metadata: {task_kind: "visit", "gc.continuation_group": ("ra-p" + $s), "gc.routed_to": "human"}, dependencies: [{type: "tracks", depends_on_id: ("ra-p" + $s)}]}]' "$MIG_STORE" > "$MIG_STORE.new" && mv "$MIG_STORE.new" "$MIG_STORE"
  done
  run_mig --check
  eq "$RC" 1 "the check fails while a step can still file a visit"
  has "$OUT" "rig-a: step that can still file a visit: ra-sA" "and names each step"
  has "$OUT" "rig-a: open visit ra-vA" "and each open visit"
  jq 'map(if .id == "ra-sA" or .id == "ra-sB" then .status = "closed" | .metadata["gc.outcome"] = "pass" else . end)' "$MIG_STORE" > "$MIG_STORE.new" && mv "$MIG_STORE.new" "$MIG_STORE"
  run_mig --check
  has "$OUT" "step that can still file a visit: ra-sC" "the check still names a cancelled step while its session is listed"
  echo '[]' > "$MIG_SESSIONS"
  run_mig --rig rig-a
  for s in A B C D; do
    eq "$(g "ra-v$s" '.status'):$(convs_on "ra-p$s" | grep -c .)" "closed:1" "the visit step $s filed becomes a conversation that tracks its subject"
  done
  run_mig --check
  eq "$RC" 0 "the check passes once no store holds a visit, a legacy demand or a step that can still file one"
  has "$OUT" "check passed" "and says so"
  run_mig
  eq "$RC" 2 "a run that names no store is a usage error"
  run_mig --check --dry-run
  eq "$RC" 2 "--check with --dry-run is a usage error"
fi

# ── legacy: legacy demands filed again as gates ───────────────────────
if part legacy; then
  echo "# legacy demands"
  fx_begin
  b '{"id":"ra-p30","title":"plain bead thirty","deps":[["blocks","ra-L1"]]}'
  b '{"id":"ra-L1","issue_type":"decision","title":"approve the plan","description":"Legacy framing: the plan doubles the pass budget.","notes":"legacy note","metadata":{"gc.demand_for":"ra-p30","gc.demand_topic":"t30","gc.takeaway":"Approve the plan?","gc.routed_to":"human","gc.gate_visit":"ra-vsw30"}}'
  b '{"id":"ra-vsw30","title":"visit: ra-p30 — resolve the human gate on ra-p30","description":"A human gate (ra-L1) blocks ra-p30 and awaits a person.\nQuestion: Approve the plan?\nSettle it in this sitting, then resolve the gate: gc bd gate resolve ra-L1","created_by":"order:gate-visit-sweep","metadata":{"task_kind":"visit","gc.continuation_group":"ra-p30","gc.routed_to":"human"},"deps":[["tracks","ra-p30"]]}'
  b '{"id":"ra-p31","title":"plain bead thirty-one","deps":[["blocks","ra-L2"]]}'
  b '{"id":"ra-q31","title":"a second waiter","deps":[["blocks","ra-L2"]]}'
  b '{"id":"ra-r31","title":"an until waiter","deps":[["until","ra-L2"]]}'
  b '{"id":"ra-L2","issue_type":"decision","title":"pick the retry bound","metadata":{"gc.demand_for":"ra-p31","gc.takeaway":"Pick the retry bound","gc.routed_to":"human"}}'
  b '{"id":"ra-p32","title":"plain bead thirty-two","deps":[["blocks","ra-L3"]]}'
  b '{"id":"ra-L3","title":"rotate the key","assignee":"person-a","metadata":{"gc.demand_for":"ra-p32","gc.takeaway":"Rotate the key","gc.routed_to":"human"}}'
  b '{"id":"ra-p33","title":"plain bead thirty-three"}'
  b '{"id":"ra-L4","issue_type":"decision","title":"an unattached demand","metadata":{"gc.demand_for":"ra-p33","gc.routed_to":"human","gc.gate_visit":"ra-vsw33"}}'
  b '{"id":"ra-vsw33","title":"visit: ra-p33 — resolve the human gate on ra-p33","description":"A human gate (ra-L4) blocks ra-p33 and awaits a person.\nQuestion: an unattached demand\nSettle it in this sitting, then resolve the gate: gc bd gate resolve ra-L4","created_by":"order:gate-visit-sweep","metadata":{"task_kind":"visit","gc.continuation_group":"ra-p33","gc.routed_to":"human"},"deps":[["tracks","ra-p33"]]}'
  b '{"id":"ra-timer","issue_type":"gate","await_type":"timer","await_id":"1h","title":"a timer gate","metadata":{"gc.demand_for":"ra-p33"}}'
  fx_end

  run_mig --rig rig-a --dry-run
  eq "$RC:$(writes)" "0:0" "a dry run over legacy demands writes nothing"
  has "$OUT" "would file legacy demand ra-L1 again as a human gate on ra-p30 [t30]" "the dry run plans the legacy demand's gate"
  has "$OUT" "would close visit ra-vsw30 into the gate legacy demand ra-L1 becomes [t30]" "and plans its sweep visit's close into that gate, which a dry run cannot file"
  has "$OUT" "LEFT OPEN for a person: visit ra-vsw33: it is the sweep's visit for legacy demand ra-L4, which no bead waits on" "a sweep visit whose legacy demand nothing waits on is planned to stay open"

  run_mig --rig rig-a
  eq "$RC" 0 "the run completes"
  G30=$(gate_on ra-p30 t30)
  eq "$(gates_on ra-p30)" "t30" "the subject waits on one human gate under the legacy demand's topic"
  eq "$(g "$G30" '.title')" "Approve the plan?" "the gate takes the demand's takeaway as its title"
  has "$(g "$G30" '.description')" "Legacy framing: the plan doubles the pass budget." "and its framing"
  has "$(g "$G30" '.notes')" "Carried from legacy demand ra-L1, which this gate replaces:" "its notes name the demand it replaces"
  has "$(g "$G30" '.notes')" "legacy note" "and carry the demand's notes"
  eq "$(g ra-L1 '.status'):$(g ra-L1 '.close_reason')" "closed:migrated: gate $G30" "the legacy demand closes migrated onto its gate"
  eq "$(g ra-vsw30 '.close_reason')" "migrated: gate $G30" "the sweep's visit for it closes into that gate"
  eq "$(pack_keys "$G30")" "" "the gate sheds the keys it was given"
  G31=$(gate_on ra-p31 conversation.ra-L2)
  eq "$(waiters "$G31" blocks)" "ra-p31,ra-q31" "the gate blocks the subject and the second waiter"
  eq "$(waiters "$G31" until)" "ra-r31" "and the until waiter's edge names the gate"
  G32=$(gate_on ra-p32 conversation.ra-L3)
  eq "$(g "$G32" '.assignee')" "person-a" "a legacy task demand's gate is assigned to the demand's person"
  eq "$(g ra-L3 '.status')" "closed" "and the demand is released and closed"
  eq "$(g ra-L4 '.status'):$(g ra-vsw33 '.status')" "open:open" "a legacy demand nothing waits on through blocks stays open, with the sweep's visit for it"
  eq "$(gates_on ra-p33)" "" "and no wait is added on its subject"
  has "$OUT" "LEFT OPEN for a person: legacy demand ra-L4" "the report names the demand"
  has "$OUT" "LEFT OPEN for a person: visit ra-vsw33" "and the sweep's visit"
  eq "$(g ra-timer '.status'):$(g ra-timer '.await_id')" "open:1h" "a timer gate is no demand and is left as it is"
  run_mig --check
  eq "$RC" 1 "the check fails while a legacy demand is open"
  has "$OUT" "rig-a: open legacy demand ra-L4" "and names it"
  sweep "legacy" --rig rig-a
fi

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
