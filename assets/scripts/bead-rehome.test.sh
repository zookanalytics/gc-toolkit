#!/usr/bin/env bash
# Hermetic test for bead-rehome.sh.
#
# Fakes `gc rig list --json` and `bd` (a file-per-bead ledger under each fake
# rig's .beads/) on PATH. No dependency on the live city, Dolt, or the network.
#
# The invariants under test:
#   (a) a disposition closes the origin and records its successor in bd's own
#       edge, `supersedes` under every kind but duplicate, with a note naming
#       kind + successor + store, and writes no successor key at all;
#   (a2) a duplicate's edge is `duplicates`;
#   (a3) a successor in another rig's store is recorded in the origin's store;
#   (b) the successor must exist in the named store, or nothing is written at
#       all (an edge onto a missing bead is worse than no edge);
#   (c) an edge that does not write closes nothing and is reported (exit 4), with
#       the re-run that finishes the disposition;
#   (d) a refused close writes nothing: no edge, no note, no outcome;
#   (e) an existing disposition naming a different successor is never
#       overwritten, nor an edge of another type on the same pair;
#   (f) each kind renders its own note phrasing;
#   (g) an id prefix no rig claims is refused, not guessed;
#   (h) a bead named as its own successor is refused;
#   (i) --dry-run writes nothing;
#   (j) an already-closed bead is REPAIRED (edge + note), not refused, and a
#       wait edge a forced close left behind gives way to the edge;
#   (k) that repair is idempotent;
#   (n) a `blocks` edge naming the SUCCESSOR is dropped just before the close,
#       so the wait a converse sitting wired beside the ruling does not refuse
#       the ruling's own close, and it comes back when the close does not land;
#   (o) any OTHER blocker is left alone and its refusal still stands;
#   (q) the successor is required under EVERY kind, `not-needed` included;
#   (s) a re-home writes no outcome of its own: neither gc.outcome nor
#       gc.work_outcome;
#   (x) an open human gate on the origin holds the close at the finalize gate,
#       which is asked before anything is written;
#   (y) --except-key reaches that gate, and nothing is excepted without it, and
#       --check under it reads what would hold the close, writing nothing, with the
#       gate asked about the origin as the close will leave it;
#   (ad) once the close lands, the branch the bead names in metadata.branch
#       goes to branch-end.sh with the bead's rig and id, once, after the close;
#   (ae) a branch-end that cannot end the branch leaves the close standing: exit
#       0, the bead closed and named, and a WARN naming the branch and the
#       command that ends it;
#   (af) a branch kept for a live owner is reported, not warned about;
#   (ag) no branch-end runs when the close is refused or held, when the bead
#       names no branch, or on a dry run, which names the branch in its plan;
#   (ah) the repair path ends an already-closed bead's branch too;
#   (aj) end to end, through the real branch-end.sh and a bare origin: a retire
#       ends the branch with its tip pinned, and a delete origin refuses leaves
#       the close standing;
#   (ak) the command a WARN names, pasted, hands branch-end a branch name that
#       carries shell metacharacters as one argument and runs nothing it spells;
#   (al) the close is conditional on the status and assignee the gates read, so
#       a claim, or a second closer's close, that lands between that read and
#       the close refuses it (exit 4): nothing is recorded, the wait edge comes
#       back, and the claim or the first disposition stands;
#   (am) the retry withdraws its own gates before the close: each open human
#       gate under the --except-key key that blocks the origin and no person is
#       assigned is resolved with a reason that names the retry and carries no
#       outcome word, and then the origin closes;
#   (an) anything else that would refuse the close (another live blocker, a
#       gate under the key a person is assigned, an open child) holds it before
#       any gate is resolved, and so does a blocker or child read that fails;
#   (ao) a gate the store will not resolve holds the close, and a run stopped after
#       the withdrawal is completed by the next one;
#   (ap) the dry run names the withdrawal it would make;
#   (aq) the template, the pin and the assignee an unforced close refuses hold
#       the retry before any gate is resolved: an origin no one is assigned,
#       or one assigned to exactly the actor the close runs as, goes ahead,
#       and one assigned to anyone else, under any other name this session
#       carries included, keeps its gates open and closes nothing;
#   (ar) before a duplicate of a canonical that has neither closed nor shipped
#       closes, each open bead it blocks gains a blocks edge onto the canonical,
#       written before the close and named in its note, so none goes ready
#       before the canonical delivers. A closed waiter, the canonical, a waiter
#       it already blocks, a delivered canonical, another kind and the repair
#       path move none. A waiter that cannot take the edge (another edge type,
#       a canonical in another store, a read that fails) and a blocker of the
#       duplicate refuse the close before anything is written; an edge bd
#       refuses, or one that does not read back, refuses it after the edges
#       before it, which stay;
#   (as) the edge goes on before the close and is read back, so two callers
#       cannot both leave a successor: a caller that finds a first one's edge,
#       with the first paused before or after its close or the bead reopened
#       since, refuses another successor; a caller whose read came before the
#       other's write finds the other's edge beside its own and takes its own
#       back, on the repair path too; a close that does not land takes the edge
#       back, unless a close naming the same successor beat it; and an edge an
#       earlier run wrote stays through this run's refused close;
#   (at) callers naming one successor share one edge, and each reads after it acts,
#       so a close naming it keeps its edge whichever order another caller's
#       take-back and that close fall in, a wait put back included;
#   (au) the repair's note is written only while the origin has the status and
#       assignee this run read, so a reopen or a claim since that read keeps its
#       bead with no edge and no note (exit 4);
#   (av) what comes to wait on a duplicate after the first read of its waiters
#       moves once the close has landed. One that cannot move leaves the close
#       standing, exit 4, a WARN and a note, and does not hold back one that can.
#       Another kind and a delivered canonical read no waiters after the close;
#   (aw) with no identity of its own the writer compares an assignee with the actor
#       bd itself defaults to, read off a create's preview that writes nothing, and
#       passes that actor on its writes. It asks only when the origin has an
#       assignee, and a preview that does not read holds an assigned origin.
# The evidence gates this writer enforces for every caller:
#   (gate-a) EVERY kind — no close over a review, step, or workflow bead;
#   (gate-held) EVERY kind — no close over a bead another session holds
#       in_progress, while a bead this session holds is fine;
#   (gate-b) fixed-upstream|duplicate — the successor is in the same store and
#       the origin did no work (no-op stamp, or no work-product key, so unlanded
#       work is refused), the no-op stamp overriding a twin's leftover branch;
#       fixed-upstream also needs the successor closed or shipped, while a
#       duplicate closes over an open canonical; a judgment kind is not held to
#       it, and an origin carrying the operator's pre-recorded PR-close
#       disposition for that kind and successor satisfies it;
#   (check) --check evaluates all of the above and writes nothing, exit 0/1.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/bead-rehome.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-bead-rehome-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (got '$1', wanted substring '$2')" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (got '$1', wanted no '$2')" ;; *) ok "$3" ;; esac; }

# --- fake stores ------------------------------------------------------------
mkdir -p "$TMP/rigs/alpha/.beads" "$TMP/rigs/beta/.beads" "$TMP/bin"
cat > "$TMP/rigs.json" <<JSON
{"rigs":[
  {"name":"alpha","path":"$TMP/rigs/alpha","prefix":"al","hq":false},
  {"name":"beta","path":"$TMP/rigs/beta","prefix":"bt","hq":true}
]}
JSON

# A bead is a file of `key=value` lines: status, notes, m.<key> metadata, and
# `dep.<other>=<type>` for each edge the bead carries from itself onto <other>,
# the side `bd show` and `bd list` report in `.dependencies[]` and the side a
# close consults. A gate also carries issue_type, await_type and await_id lines,
# a bead with a person on it an assignee line, and a child a parent line.
mkbead() { printf 'status=%s\n' "${2:-open}" > "$TMP/rigs/$1/.beads/$3"; }
field()  { sed -n "s/^$2=//p" "$TMP/rigs/$1/.beads/$3" 2>/dev/null | tail -1; }
# edge <rig> <bead> <other> — the type of the bead's edge onto <other>, or "".
edge()   { field "$1" "dep.$3" "$2"; }

{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
# Only the surface bead-rehome.sh touches.
case "$1 $2" in
  "rig list") cat "$FAKE_RIGS_JSON" ;;
  # The bd stub runs in this process rather than a second bash's.
  "bd "*)    shift; export VIA_GC_BD=1; . "${0%/*}/bd" "$@"; exit ;;
  *) exit 1 ;;
esac
GC

{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/bd" <<'BD'
# The writer reaches the store through `gc bd`; a direct `bd` is the regression
# this guard catches, so only the gc stub above may run this one.
[ -n "${VIA_GC_BD:-}" ] || { echo "stub bd: called directly, not through gc bd" >&2; exit 127; }
# Fake bd: --db <path>/.beads [--actor X] <list|show|update|dep|gate|statuses> ...
set -euo pipefail
DB=""; ACTOR_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --db) DB="$2"; shift 2 ;;
    --actor) ACTOR_ARG="$2"; echo "$2" >> "$FAKE_ACTOR_LOG"; shift 2 ;;
    *) break ;;
  esac
done
sub="${1:-}"; shift || true
[ -z "${FAKE_CALL_LOG:-}" ] || printf '%s %s\n' "$sub" "$*" >> "$FAKE_CALL_LOG"

meta_of() { # <file>
  local lines
  lines=$(sed -n 's/^m\.//p' "$1" 2>/dev/null || true)
  if [ -z "$lines" ]; then printf '{}'; return; fi
  printf '%s' "$lines" | jq -R -s 'split("\n") | map(select(length > 0))
    | map(split("=") | {key: .[0], value: (.[1:] | join("="))}) | from_entries'
}
# The edges a bead carries, one {other, type} per line. The order is the one bd
# keeps them in, the order they were added, which is the first a reader takes.
edges_of() { # <file>
  sed -n 's/^dep\.\([^=]*\)=\(.*\)$/\1 \2/p' "$1" 2>/dev/null
}
# race_at <point> — run the script FAKE_RACE_<point> names, once per bead, while
# this write waits: a second caller's whole run, made with this one paused there.
# BEFORE_EDGE is just before a duplicates or supersedes edge is added, BEFORE_CLOSE
# just before an update that closes, AFTER_CLOSE just after it, BEFORE_NOTE just
# before an update that does not close, and BEFORE_TAKE_BACK just before a
# duplicates or supersedes edge is removed.
race_at() { # <point>
  local v="FAKE_RACE_$1" s
  s="${!v:-}"
  [ -n "$s" ] && [ ! -e "$DB/.raced.$1.$id" ] || return 0
  : > "$DB/.raced.$1.$id"
  bash "$s" || true
}
# A `bd list` row: the far end of an edge by depends_on_id, its type as type.
list_row() { # <file>
  local f="$1" id="${1##*/}" deps='[]' o t
  while read -r o t; do
    [ -n "$o" ] || continue
    deps=$(jq -nc --argjson d "$deps" --arg i "$id" --arg o "$o" --arg t "$t" '$d + [{issue_id: $i, depends_on_id: $o, type: $t}]')
  done < <(edges_of "$f")
  jq -nc --arg id "$id" --arg st "$(sed -n 's/^status=//p' "$f" | tail -1)" \
        --arg as "$(sed -n 's/^assignee=//p' "$f" | tail -1)" \
        --arg it "$(sed -n 's/^issue_type=//p' "$f" | tail -1)" \
        --arg tpl "$(sed -n 's/^is_template=//p' "$f" | tail -1)" \
        --arg notes "$(sed -n 's/^notes=//p' "$f" | tr '\n' ' ')" \
        --argjson meta "$(meta_of "$f")" --argjson deps "$deps" \
    '{id: $id, status: $st, issue_type: (if $it == "" then "task" else $it end), notes: $notes, metadata: $meta, dependencies: $deps}
     | if $as != "" then .assignee = $as else . end
     | if $tpl == "true" then .is_template = true else . end'
}
# The blockers still holding a bead, by the rule real bd applies: a blocks
# edge counts unless the bead it names is closed or pinned.
open_blockers() { # <file>
  local o t bf st out=""
  while read -r o t; do
    [ "$t" = blocks ] || continue
    st=""; bf="$DB/$o"
    [ -f "$bf" ] && st=$(sed -n 's/^status=//p' "$bf" | tail -1)
    case "$st" in closed|pinned) ;; *) out="$out $o" ;; esac
  done < <(edges_of "$1")
  printf '%s' "${out# }"
}

# `bd dep <verb> <id> <depends-on-id>` puts the verb where every other
# subcommand puts the bead id, so it is parsed on its own.
if [ "$sub" = "dep" ]; then
  verb="${1:-}"; shift || true
  id="${1:-}"; shift || true
  # `bd dep list <id> --type blocks --json`: one row per `blocks` edge the bead
  # carries onto a bead this store holds, the far bead's fields with the edge's
  # dependency_type, a field whose value is empty left out as real bd leaves it
  # out. FAKE_BD_DEP_LIST_FAIL makes that read fail. With --direction=up the rows
  # are the beads in this store whose `blocks` edge names <id>, the beads that
  # wait on it, and FAKE_BD_DEP_LIST_UP_FAIL makes that read fail, as
  # FAKE_UP_FAIL_AFTER_CLOSE does from the moment a close lands.
  if [ "$verb" = "list" ]; then
    up=""
    for a in "$@"; do case "$a" in --direction=up) up=1 ;; esac; done
    if [ -n "$up" ]; then
      { [ -z "${FAKE_BD_DEP_LIST_UP_FAIL:-}" ] && [ ! -e "$DB/.up-list-fails" ]; } || { echo "Error: simulated dep list failure" >&2; exit 1; }
    else
      [ -z "${FAKE_BD_DEP_LIST_FAIL:-}" ] || { echo "Error: simulated dep list failure" >&2; exit 1; }
    fi
    f="$DB/$id"
    [ -f "$f" ] || { printf '{"error":"no issues found matching the provided IDs","schema_version":1}\n'; exit 1; }
    rows='[]'
    while read -r b t; do
      [ "$t" = blocks ] || continue
      bf="$DB/$b"
      [ -f "$bf" ] || continue
      row=$(jq -nc --arg id "$b" \
        --arg st "$(sed -n 's/^status=//p' "$bf" | tail -1)" \
        --arg it "$(sed -n 's/^issue_type=//p' "$bf" | tail -1)" \
        --arg at "$(sed -n 's/^await_type=//p' "$bf" | tail -1)" \
        --arg ai "$(sed -n 's/^await_id=//p' "$bf" | tail -1)" \
        --arg as "$(sed -n 's/^assignee=//p' "$bf" | tail -1)" \
        '{id: $id, status: $st, issue_type: (if $it == "" then "task" else $it end),
          await_type: $at, await_id: $ai, assignee: $as, dependency_type: "blocks"}
         | with_entries(select(.value != ""))')
      rows=$(jq -nc --argjson r "$rows" --argjson x "$row" '$r + [$x]')
    done < <(if [ -n "$up" ]; then
               for wf in "$DB"/*; do
                 [ -f "$wf" ] || continue
                 edges_of "$wf" | awk -v i="$id" -v w="${wf##*/}" '$1 == i && $2 == "blocks" { print w, "blocks" }'
               done
             else edges_of "$f"; fi)
    printf '%s\n' "$rows"
    exit 0
  fi
  other="${1:-}"; shift || true
  f="$DB/$id"
  [ -f "$f" ] || { printf '{"error":"no issues found matching the provided IDs","schema_version":1}\n'; exit 1; }
  case "$verb" in
    add)
      # bd keeps one edge per pair: a re-add of the same type changes nothing,
      # and another type on the pair is refused. A target this store does not
      # hold is kept unverified when its prefix names another store.
      # FAKE_BD_DEP_ADD_FAIL refuses every add, FAKE_BD_DEP_ADD_REFUSE_FROM=<id>
      # refuses an add from that bead as bd refuses one across a parent chain,
      # and FAKE_BD_DEP_ADD_NOOP_FROM=<id> reports one from it that never
      # persisted.
      [ -z "${FAKE_BD_DEP_ADD_FAIL:-}" ] || { echo "Error: simulated dep add failure" >&2; exit 1; }
      [ "${FAKE_BD_DEP_ADD_REFUSE_FROM:-}" != "$id" ] \
        || { echo "Error: cannot add blocks dependency: $id and $other are in the same parent chain" >&2; exit 1; }
      [ "${FAKE_BD_DEP_ADD_NOOP_FROM:-}" != "$id" ] || { echo "✓ Added dependency: $id depends on $other"; exit 0; }
      type=blocks
      while [ $# -gt 0 ]; do
        case "$1" in --type|-t) type="$2"; shift 2 ;; --type=*) type="${1#--type=}"; shift ;; *) shift ;; esac
      done
      case "$type" in duplicates|supersedes) race_at BEFORE_EDGE ;; esac
      cur=$(edges_of "$f" | awk -v o="$other" '$1 == o { print $2 }')
      if [ -n "$cur" ] && [ "$cur" != "$type" ]; then
        echo "Error: dependency $id -> $other already exists with type $cur" >&2; exit 1
      fi
      [ -n "$cur" ] || printf 'dep.%s=%s\n' "$other" "$type" >> "$f"
      [ -z "${FAKE_DEP_LOG:-}" ] || printf '%s %s %s\n' "$id" "$other" "$type" >> "$FAKE_DEP_LOG"
      case "$type" in duplicates|supersedes) [ -z "${FAKE_LIST_FAIL_AFTER_EDGE:-}" ] || : > "$DB/.list-id-fails" ;; esac ;;
    # Real `bd dep remove` reports success for an edge that never existed.
    # FAKE_BD_DEP_REMOVE_FAIL refuses a remove of a disposition edge.
    remove)
      case "$(edges_of "$f" | awk -v o="$other" '$1 == o { print $2 }')" in
        duplicates|supersedes)
          [ -z "${FAKE_BD_DEP_REMOVE_FAIL:-}" ] || { echo "Error: simulated dep remove failure" >&2; exit 1; }
          race_at BEFORE_TAKE_BACK ;;
      esac
      awk -v p="dep.$other=" 'index($0, p) != 1' "$f" > "$DB/.removing.$id"
      mv "$DB/.removing.$id" "$f"
      echo "✓ removed dependency: $id -> $other" ;;
    *)      exit 1 ;;
  esac
  exit 0
fi

# The status contract: the read branch-end.sh makes besides show and list, for
# the end-to-end case.
if [ "$sub" = "statuses" ]; then
  printf '%s\n' '{"built_in_statuses":[{"name":"open","category":"active"},{"name":"in_progress","category":"wip"},{"name":"closed","category":"done"}]}'
  exit 0
fi
if [ "$sub" = "list" ]; then
  # --id lists the beads it names, closed ones only with --all. --parent lists
  # the beads whose parent line names it, leaving out the closed and pinned ones
  # as bd does. Otherwise --status filters and --metadata-field is bd's: split
  # at the first `=`, every pair must match. FAKE_BD_LIST_PARENT_FAIL makes a
  # --parent read fail, and FAKE_BD_LIST_ID_FAIL an --id read.
  st=""; mf='[]'; parent=""; ids=""; all=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --status) st="$2"; shift 2 ;;
      --status=*) st="${1#--status=}"; shift ;;
      --parent) parent="$2"; shift 2 ;;
      --id) ids="$2"; shift 2 ;;
      --id=*) ids="${1#--id=}"; shift ;;
      --all) all=1; shift ;;
      --metadata-field)
        mf=$(jq -cn --argjson m "$mf" --arg k "${2%%=*}" --arg v "${2#*=}" '$m + [{k: $k, v: $v}]')
        shift 2 ;;
      *) shift ;;
    esac
  done
  if [ -n "$parent" ] && [ -n "${FAKE_BD_LIST_PARENT_FAIL:-}" ]; then
    echo "Error: simulated list failure" >&2; exit 1
  fi
  if [ -n "$ids" ] && { [ -n "${FAKE_BD_LIST_ID_FAIL:-}" ] || [ -e "$DB/.list-id-fails" ]; }; then
    echo "Error: simulated list failure" >&2; exit 1
  fi
  rows='[]'
  for bf in "$DB"/*; do
    [ -f "$bf" ] || continue
    bid="${bf##*/}"
    bs=$(sed -n 's/^status=//p' "$bf" | tail -1)
    if [ -n "$ids" ]; then
      case ",$ids," in *",$bid,"*) ;; *) continue ;; esac
      [ -n "$all" ] || [ "$bs" != closed ] || continue
    elif [ -n "$parent" ]; then
      [ "$(sed -n 's/^parent=//p' "$bf" | tail -1)" = "$parent" ] || continue
      if [ -z "$st" ]; then
        case "$bs" in closed|pinned) continue ;; esac
      else
        case ",$st," in *",$bs,"*) ;; *) continue ;; esac
      fi
    else
      case ",$st," in *",$bs,"*) ;; *) continue ;; esac
    fi
    rows=$(jq -nc --argjson r "$rows" --argjson x "$(list_row "$bf")" '$r + [$x]')
  done
  printf '%s\n' "$rows" | jq -c --argjson mf "$mf" \
    '[.[] | select(. as $row | all($mf[]; $row.metadata[.k] as $x | $x != null and ($x | tostring) == .v))]'
  exit 0
fi

# `bd create --dry-run --json` previews the bead bd would create, created_by naming
# the actor it runs as: --actor, or the one it defaults to, FAKE_BD_DEFAULT_ACTOR.
# With neither the preview fails. A create that would write is the regression this
# guard catches, since this writer files nothing.
if [ "$sub" = "create" ]; then
  case " $* " in *" --dry-run "*) ;; *) echo "stub bd: a create that writes" >&2; exit 127 ;; esac
  [ -n "${ACTOR_ARG:-${FAKE_BD_DEFAULT_ACTOR:-}}" ] || { echo "Error: simulated preview failure" >&2; exit 1; }
  jq -nc --arg a "${ACTOR_ARG:-$FAKE_BD_DEFAULT_ACTOR}" '{id: "", created_by: $a}'
  exit 0
fi

# `bd gate resolve <id> --reason <r>` closes the gate with that reason. On a
# gate already closed it changes nothing and still reports success, as bd does.
# FAKE_BD_GATE_RESOLVE_REFUSE refuses the resolve.
if [ "$sub" = "gate" ]; then
  verb="${1:-}"; shift || true
  id="${1:-}"; shift || true
  f="$DB/$id"
  [ "$verb" = "resolve" ] && [ -f "$f" ] || exit 1
  [ -z "${FAKE_RESOLVE_LOG:-}" ] || printf '%s %s\n' "$id" "$*" >> "$FAKE_RESOLVE_LOG"
  [ -z "${FAKE_BD_GATE_RESOLVE_REFUSE:-}" ] || { echo "Error resolving gate $id: the store refused it" >&2; exit 1; }
  reason=""
  while [ $# -gt 0 ]; do
    case "$1" in --reason) reason="$2"; shift 2 ;; *) shift ;; esac
  done
  [ "$(sed -n 's/^status=//p' "$f" | tail -1)" = "closed" ] || printf 'status=closed\nreason=%s\n' "$reason" >> "$f"
  echo "✓ Gate resolved: $id"
  exit 0
fi

id="${1:-}"; shift || true
f="$DB/$id"
[ -f "$f" ] || { printf '{"error":"no issues found matching the provided IDs","schema_version":1}\n'; exit 1; }

case "$sub" in
  show)
    # A show row: the far end of each edge onto a bead this store holds, by id,
    # its type as dependency_type. An edge into another store is left out.
    deps='[]'
    while read -r o t; do
      [ -f "$DB/$o" ] || continue
      deps=$(jq -nc --argjson d "$deps" --arg o "$o" --arg t "$t" '$d + [{id: $o, dependency_type: $t}]')
    done < <(edges_of "$f")
    jq -nc --argjson row "$(list_row "$f")" --argjson deps "$deps" '[$row | .dependencies = $deps]'
    ;;
  update)
    # FAKE_UPDATE_LOG, when set, gets each update's bead id and arguments.
    [ -z "${FAKE_UPDATE_LOG:-}" ] || printf '%s %s\n' "$id" "$*" >> "$FAKE_UPDATE_LOG"
    closing=""
    for a in "$@"; do case "$a" in --status=closed) closing=1 ;; esac; done
    # FAKE_BD_CLAIM_BEFORE_CLOSE="<status> <assignee>" lands another actor's
    # write on the bead just before the first update that closes it is
    # answered: a claim, an assignment, a status change or another close made
    # after the caller read the bead.
    if [ -n "$closing" ]; then race_at BEFORE_CLOSE; else race_at BEFORE_NOTE; fi
    if [ -n "$closing" ] && [ -n "${FAKE_BD_CLAIM_BEFORE_CLOSE:-}" ] && [ ! -e "$DB/.claimed-before-close.$id" ]; then
      : > "$DB/.claimed-before-close.$id"
      printf 'status=%s\nassignee=%s\n' "${FAKE_BD_CLAIM_BEFORE_CLOSE%% *}" "${FAKE_BD_CLAIM_BEFORE_CLOSE#* }" >> "$f"
    fi
    # bd's --if-status and --if-assignee guards: the update lands only while the
    # bead still has that status and that assignee ("" is unassigned), checked in
    # the same write; a stale guard writes nothing and exits 13.
    if_st="-"; if_as="-"; prev=""
    for a in "$@"; do
      case "$a" in
        --if-status=*) if_st="${a#--if-status=}" ;;
        --if-assignee=*) if_as="${a#--if-assignee=}" ;;
      esac
      case "$prev" in --if-status) if_st="$a" ;; --if-assignee) if_as="$a" ;; esac
      prev="$a"
    done
    # FAKE_BD_NOTE_FAIL fails an update that does not close, as a store that does
    # not answer fails it, which is not a guard's refusal.
    [ -n "$closing" ] || [ -z "${FAKE_BD_NOTE_FAIL:-}" ] || { echo "Error: simulated update failure" >&2; exit 1; }
    cur_st="$(sed -n 's/^status=//p' "$f" | tail -1)"
    cur_as="$(sed -n 's/^assignee=//p' "$f" | tail -1)"
    if { [ "$if_st" != "-" ] && [ "$if_st" != "$cur_st" ]; } || { [ "$if_as" != "-" ] && [ "$if_as" != "$cur_as" ]; }; then
      echo "Error: precondition failed for $id: status/assignee changed" >&2
      exit 13
    fi
    if [ -n "$closing" ]; then
      # A move into closed is bd's checked close: it refuses a bead a live
      # blocker or an open child holds, and with FAKE_BD_ENFORCE_CLOSE_GUARDS a
      # template, a pinned bead and a bead assigned to anyone but the --actor.
      # FAKE_BD_CLOSE_REFUSE refuses it outright.
      [ -z "${FAKE_BD_CLOSE_REFUSE:-}" ] || { echo "cannot close issue assigned to other-agent (actor: someone-else)" >&2; exit 1; }
      if [ -n "${FAKE_BD_ENFORCE_CLOSE_GUARDS:-}" ]; then
        [ "$(sed -n 's/^is_template=//p' "$f" | tail -1)" != "true" ] \
          || { echo "Error: cannot close template $id" >&2; exit 1; }
        [ "$cur_st" != "pinned" ] \
          || { echo "Error: cannot close pinned issue $id (use --force to override)" >&2; exit 1; }
        [ -z "$cur_as" ] || [ "$cur_as" = "$ACTOR_ARG" ] \
          || { echo "cannot close $id: assignee is \"$cur_as\", actor is \"$ACTOR_ARG\"; reclaim or use --force to override" >&2; exit 1; }
      fi
      BLOCKED=$(open_blockers "$f")
      if [ -n "$BLOCKED" ]; then
        echo "cannot close blocked issue: $id is blocked by [${BLOCKED// /, }] (use --force to override)" >&2
        exit 1
      fi
      for cf in "$DB"/*; do
        [ -f "$cf" ] && [ "$(sed -n 's/^parent=//p' "$cf" | tail -1)" = "$id" ] || continue
        case "$(sed -n 's/^status=//p' "$cf" | tail -1)" in closed|pinned) ;; *)
          echo "cannot close $id: it has open children (use --force to override)" >&2; exit 1 ;; esac
      done
    fi
    while [ $# -gt 0 ]; do
      case "$1" in
        --set-metadata) printf 'm.%s\n' "$2" >> "$f"; shift 2 ;;
        --append-notes) printf 'notes=%s\n' "$2" >> "$f"; shift 2 ;;
        --status=*) printf 'status=%s\n' "${1#--status=}" >> "$f"; shift ;;
        *) shift ;;
      esac
    done
    if [ -n "$closing" ]; then
      [ -z "${FAKE_UP_FAIL_AFTER_CLOSE:-}" ] || : > "$DB/.up-list-fails"
      [ -z "${FAKE_LIST_FAIL_AFTER_CLOSE:-}" ] || : > "$DB/.list-id-fails"
      race_at AFTER_CLOSE
    fi
    ;;
  *) exit 1 ;;
esac
BD

chmod +x "$TMP/bin/gc" "$TMP/bin/bd"
export PATH="$TMP/bin:$PATH"
export FAKE_RIGS_JSON="$TMP/rigs.json"
export FAKE_ACTOR_LOG="$TMP/actors.log"
: > "$FAKE_ACTOR_LOG"
export BEADS_ACTOR="test__rehome-hq-0000"

# The finalize gate is a sibling bead-rehome forks before any write. Stub it so
# this suite tests the WIRING (a refusal holds the close and writes nothing)
# without a live gate probe — the gate's own logic is covered by
# finalize-gate.test.sh. Default: allow; FG_VERDICT=hold makes it refuse. Each
# call's argv is appended to FG_LOG.
FG_STUB="$TMP/bin/finalize-gate-stub.sh"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "${FG_LOG:?}"\ncase "${FG_VERDICT:-pass}" in\n  hold) echo "held by open human gate gate-x — a person owes an answer before ${2:-?} is finalized"; exit 1 ;;\n  *) exit 0 ;;\nesac\n' > "$FG_STUB"
chmod +x "$FG_STUB"
export GC_FINALIZE_GATE_TOOL="$FG_STUB"
export FG_LOG="$TMP/finalize-gate.log"; : > "$FG_LOG"

# branch-end.sh is a sibling bead-rehome forks once the close reads back. Stub it
# so this suite tests the wiring; its own logic is covered by branch-end.test.sh,
# and case (aj) runs the real one end to end. Each call's argv, with the bead's
# status as the stub finds it in the fake store, is appended to BE_LOG; BE_RC
# picks its exit (0 ended, 3 kept, anything else not ended).
BE_STUB="$TMP/bin/branch-end-stub.sh"
cat > "$BE_STUB" <<'STUB'
#!/usr/bin/env bash
args="$*"; bead=""; rig=""
while [ $# -gt 0 ]; do
  case "$1" in
    --bead) bead="$2"; shift 2 ;;
    --rig) rig="$2"; shift 2 ;;
    *) shift ;;
  esac
done
st=$(sed -n 's/^status=//p' "${FAKE_RIGS_ROOT:?}/$rig/.beads/$bead" 2>/dev/null | tail -1)
printf '%s status-at-call=%s\n' "$args" "$st" >> "${BE_LOG:?}"
case "${BE_RC:-0}" in
  0) echo "branch-end (stub): ended" ;;
  3) echo "branch-end (stub): kept for a live owner" ;;
  *) echo "branch-end (stub): did NOT end" >&2 ;;
esac
exit "${BE_RC:-0}"
STUB
chmod +x "$BE_STUB"
export GC_BRANCH_END_TOOL="$BE_STUB" BE_LOG="$TMP/branch-end.log" FAKE_RIGS_ROOT="$TMP/rigs"
: > "$BE_LOG"

run() { "$SCRIPT" "$@" >"$TMP/out" 2>"$TMP/err"; }
# A bead's whole record, to prove a refused run wrote nothing.
snap() { cat "$TMP/rigs/$1/.beads/$2"; }

# --- (a) happy path: closed, the supersedes edge, a populated note ----------
mkbead alpha open al-origin1
mkbead alpha open al-succ1
rc=0; run --origin al-origin1 --successor al-succ1 --kind re-homed --note "operator ruling rb-a3ny" || rc=$?
eq "$rc" 0 "re-home succeeds"
eq "$(field alpha status al-origin1)" closed "origin is closed"
eq "$(edge alpha al-origin1 al-succ1)" supersedes "the origin's supersedes edge names the successor"
NOTE=$(field alpha notes al-origin1)
has "$NOTE" "re-homed to al-succ1 in rig:alpha" "the close's note names kind, successor and store"
has "$NOTE" "operator ruling rb-a3ny" "the close's note carries the note"
eq "$(grep -c '^m\.' "$TMP/rigs/alpha/.beads/al-origin1" || true)" 0 "no metadata key records the successor"
eq "$(grep -c '^m\.' "$TMP/rigs/alpha/.beads/al-succ1" || true)" 0 "and the successor gains no back-pointer key"
has "$(cat "$TMP/out")" "events" "output points at the events table for attribution"
has "$(cat "$FAKE_ACTOR_LOG")" "test__rehome-hq-0000" "the actor is passed through for the audit trail"

# --- (a2) a duplicate is recorded as a duplicate -----------------------------
mkbead alpha open al-dup1
mkbead alpha open al-canon1
rc=0; run --origin al-dup1 --successor al-canon1 --kind duplicate || rc=$?
eq "$rc" 0 "a duplicate of an open canonical closes at once"
eq "$(field alpha status al-dup1)" closed "…the duplicate is closed"
eq "$(edge alpha al-dup1 al-canon1)" duplicates "…its duplicates edge names the canonical"
eq "$(field alpha status al-canon1)" open "…and the canonical is untouched"

# --- (a3) a successor in another rig's store --------------------------------
mkbead alpha open al-xrig1
mkbead beta  open bt-xsucc1
BEFORE=$(snap beta bt-xsucc1)
rc=0; run --origin al-xrig1 --successor bt-xsucc1 --kind re-homed || rc=$?
eq "$rc" 0 "a re-home onto another store's bead succeeds"
eq "$(edge alpha al-xrig1 bt-xsucc1)" supersedes "…its edge is recorded in the origin's store"
has "$(field alpha notes al-xrig1)" "re-homed to bt-xsucc1 in rig:beta" "…and its note names the successor's store"
eq "$(snap beta bt-xsucc1)" "$BEFORE" "…and the successor is not written"

# --- (x) an open human gate on the origin holds the close (finalize gate) ----
# The gate refuses while a human gate blocks the origin, and it is asked before
# anything is written, so the bead stays exactly as it was.
mkbead alpha open al-vhold
mkbead alpha open al-vsucc
BEFORE=$(snap alpha al-vhold)
rc=0; FG_VERDICT=hold run --origin al-vhold --successor al-vsucc --kind re-homed --note "ruling" || rc=$?
eq "$rc" 5 "an open human gate holds the close (exit 5)"
eq "$(snap alpha al-vhold)" "$BEFORE" "…and nothing is written to the origin"
has "$(cat "$TMP/err")" "is held" "…stderr says the close is held"
has "$(cat "$TMP/err")" "held by open human gate" "…and carries the gate's reason"

# --- (y) --except-key reaches the finalize gate, and only when given -------
mkbead alpha open al-except
mkbead alpha open al-exsucc
: > "$FG_LOG"
rc=0; run --origin al-except --successor al-exsucc --kind not-needed --except-key pr-dispose-failed.7 || rc=$?
eq "$rc" 0 "a close naming an excepted key lands when the gate passes"
eq "$(cat "$FG_LOG")" "check al-except --as-disposed --except-key pr-dispose-failed.7" \
   "the gate is asked with the caller's excepted key, about the origin as the close will leave it"
mkbead alpha open al-noexcept
mkbead alpha open al-noexsucc
: > "$FG_LOG"
rc=0; run --origin al-noexcept --successor al-noexsucc --kind not-needed || rc=$?
eq "$(cat "$FG_LOG")" "check al-noexcept --as-disposed" "without the flag the gate is asked with no exception"

# --- (b) missing successor: nothing written at all --------------------------
mkbead alpha open al-origin2
BEFORE=$(snap alpha al-origin2)
rc=0; run --origin al-origin2 --successor bt-ghost --kind folded || rc=$?
eq "$rc" 3 "a successor that does not exist is refused"
eq "$(snap alpha al-origin2)" "$BEFORE" "…and the origin is untouched"

# --- (c) an edge that does not write closes nothing --------------------------
mkbead alpha open al-origin3
mkbead alpha open al-succ3
rc=0; FAKE_BD_DEP_ADD_FAIL=1 run --origin al-origin3 --successor al-succ3 --kind re-homed || rc=$?
eq "$rc" 4 "an edge that does not write exits 4"
eq "$(field alpha status al-origin3)" open "…and the bead is not closed, so no close stands without its successor"
has "$(cat "$TMP/err")" "did not write" "…and says so"
has "$(cat "$TMP/err")" "Re-run this call" "…with the re-run that finishes it"
rc=0; run --origin al-origin3 --successor al-succ3 --kind re-homed || rc=$?
eq "$rc" 0 "the re-run succeeds"
eq "$(field alpha status al-origin3)" closed "…closes the bead"
eq "$(edge alpha al-origin3 al-succ3)" supersedes "…and records the edge"

# --- (d) a refused close writes nothing --------------------------------------
# A judgment kind: its close reaches bd's checked close, which is where the
# refusal under test happens.
mkbead alpha open al-origin4
mkbead alpha open al-succ4
BEFORE=$(snap alpha al-origin4)
rc=0; FAKE_BD_CLOSE_REFUSE=1 run --origin al-origin4 --successor al-succ4 --kind folded || rc=$?
eq "$rc" 5 "a refused close exits 5"
eq "$(snap alpha al-origin4)" "$BEFORE" "…and writes nothing: no edge, no note, no outcome"
has "$(cat "$TMP/err")" "cannot close issue" "…bd's refusal is passed on"
has "$(cat "$TMP/err")" "nothing is recorded" "…and the writer says nothing is recorded"

# --- (e) a different prior disposition is never overwritten ---------------
mkbead alpha closed al-origin5
mkbead alpha open al-other5
mkbead alpha open al-succ5
printf 'dep.al-other5=supersedes\n' >> "$TMP/rigs/alpha/.beads/al-origin5"
BEFORE=$(snap alpha al-origin5)
rc=0; run --origin al-origin5 --successor al-succ5 --kind folded || rc=$?
eq "$rc" 6 "an existing disposition onto another successor is refused"
eq "$(snap alpha al-origin5)" "$BEFORE" "…and the prior disposition is untouched"
# An edge of another kind on the same pair is not rewritten either.
mkbead alpha open al-origin5b
mkbead alpha open al-succ5b
printf 'dep.al-succ5b=related\n' >> "$TMP/rigs/alpha/.beads/al-origin5b"
rc=0; run --origin al-origin5b --successor al-succ5b --kind folded || rc=$?
eq "$rc" 6 "a related edge onto the successor is refused, since bd keeps one edge per pair"
has "$(cat "$TMP/err")" "dep remove al-origin5b al-succ5b" "…and names the command that clears it"
eq "$(field alpha status al-origin5b)" open "…and the origin is not closed"
mkbead alpha closed al-origin5c
mkbead alpha open al-succ5c
printf 'dep.al-succ5c=duplicates\n' >> "$TMP/rigs/alpha/.beads/al-origin5c"
rc=0; run --origin al-origin5c --successor al-succ5c --kind folded || rc=$?
eq "$rc" 6 "a duplicate disposition is not rewritten as another kind"

# --- (f) each kind renders its own phrasing -------------------------------
for pair in "re-homed:re-homed to:supersedes" "folded:folded into:supersedes" "not-needed:not needed, per:supersedes"; do
  kind="${pair%%:*}"; rest="${pair#*:}"; want="${rest%%:*}"; etype="${rest#*:}"
  mkbead alpha open "al-k$kind"; mkbead beta open "bt-k$kind"
  rc=0; run --origin "al-k$kind" --successor "bt-k$kind" --kind "$kind" || rc=$?
  eq "$rc" 0 "kind '$kind' is accepted"
  has "$(field alpha notes "al-k$kind")" "$want" "kind '$kind' renders '$want'"
  eq "$(edge alpha "al-k$kind" "bt-k$kind")" "$etype" "kind '$kind' records a $etype edge"
done
for pair in "fixed-upstream:fixed upstream by:supersedes" "duplicate:duplicate of:duplicates"; do
  kind="${pair%%:*}"; rest="${pair#*:}"; want="${rest%%:*}"; etype="${rest#*:}"
  mkbead alpha open "al-k$kind"; printf 'm.gc.work_outcome=no-op\n' >> "$TMP/rigs/alpha/.beads/al-k$kind"
  mkbead alpha closed "al-s$kind"
  rc=0; run --origin "al-k$kind" --successor "al-s$kind" --kind "$kind" || rc=$?
  eq "$rc" 0 "kind '$kind' is accepted with its evidence"
  has "$(field alpha notes "al-k$kind")" "$want" "kind '$kind' renders '$want'"
  eq "$(edge alpha "al-k$kind" "al-s$kind")" "$etype" "kind '$kind' records a $etype edge"
done

# --- (q) the successor is mandatory under every kind ----------------------
mkbead alpha open al-origin17
for kind in re-homed folded fixed-upstream duplicate not-needed; do
  rc=0; run --origin al-origin17 --kind "$kind" || rc=$?
  eq "$rc" 64 "kind '$kind' still requires a successor"
  has "$(cat "$TMP/err")" "--successor is required" "kind '$kind' says which successor is missing"
done
eq "$(field alpha status al-origin17)" open "no close without a successor reached the store"

# --- (g) an unclaimed id prefix is refused, not guessed -------------------
mkbead alpha open al-origin7
rc=0; run --origin al-origin7 --successor zz-nope --kind re-homed || rc=$?
eq "$rc" 2 "an id prefix no rig claims is refused"
eq "$(field alpha status al-origin7)" open "origin untouched when the store cannot be derived"
has "$(cat "$TMP/err")" "cannot derive the store" "the refusal explains what to pass"

# --- (h) a bead named as its own successor is refused --------------------
mkbead alpha open al-origin8
rc=0; run --origin al-origin8 --successor al-origin8 --kind folded || rc=$?
eq "$rc" 64 "a bead cannot supersede itself"

# --- (j) repair path: an already-closed bead gets the edge + a note -------
mkbead alpha closed al-origin10
mkbead beta  open   bt-succ10
rc=0; run --origin al-origin10 --successor bt-succ10 --kind re-homed || rc=$?
eq "$rc" 0 "an already-closed origin is repaired, not refused"
eq "$(edge alpha al-origin10 bt-succ10)" supersedes "the edge is recorded on the closed bead"
eq "$(field alpha status al-origin10)" closed "the bead is not reopened or re-closed"
has "$(field alpha notes al-origin10)" "Disposition recorded" "the disposition is appended to the notes"
has "$(field alpha notes al-origin10)" "re-homed to bt-succ10 in rig:beta" "the note names kind, successor and store"
has "$(cat "$TMP/out")" "ALREADY closed" "the output says the close was left alone"
# A wait edge a forced close left behind gives way to the disposition's edge.
mkbead alpha closed al-origin10w
mkbead alpha open al-succ10w
printf 'dep.al-succ10w=blocks\n' >> "$TMP/rigs/alpha/.beads/al-origin10w"
rc=0; run --origin al-origin10w --successor al-succ10w --kind folded || rc=$?
eq "$rc" 0 "a closed bead still waiting on its successor is repaired"
eq "$(edge alpha al-origin10w al-succ10w)" supersedes "…its wait edge gives way to the supersedes edge"

# --- (k) the repair is idempotent: no duplicate note on a re-run ---------
rc=0; run --origin al-origin10 --successor bt-succ10 --kind re-homed || rc=$?
eq "$rc" 0 "re-running the repair succeeds"
eq "$(grep -c '^notes=' "$TMP/rigs/alpha/.beads/al-origin10")" 1 "the disposition note is not duplicated"
has "$(cat "$TMP/out")" "already records this disposition" "the re-run says it is a no-op"

# --- (n) the wait edge to the successor does not refuse the disposition ---
mkbead alpha open al-origin13
mkbead alpha open al-succ13
printf 'dep.al-succ13=blocks\n' >> "$TMP/rigs/alpha/.beads/al-origin13"
rc=0; run --origin al-origin13 --successor al-succ13 --kind folded --note "operator ruling" || rc=$?
eq "$rc" 0 "a subject blocked by its own successor is still disposed"
eq "$(field alpha status al-origin13)" closed "the close is not refused by the wait edge"
eq "$(edge alpha al-origin13 al-succ13)" supersedes "the wait edge gives way to the supersedes edge"

# --- (o) any OTHER blocker is a real hold: untouched, and it still refuses -
mkbead alpha open al-origin14
mkbead alpha open al-succ14
mkbead alpha open al-block14
printf 'dep.al-succ14=blocks\ndep.al-block14=blocks\n' >> "$TMP/rigs/alpha/.beads/al-origin14"
rc=0; run --origin al-origin14 --successor al-succ14 --kind folded || rc=$?
eq "$rc" 5 "an unrelated blocker still refuses the close"
eq "$(field alpha status al-origin14)" open "the bead is left open"
eq "$(edge alpha al-origin14 al-block14)" blocks "the unrelated blocker's edge is left alone"
eq "$(edge alpha al-origin14 al-succ14)" blocks "…and the wait onto the successor comes back, as it was"
has "$(cat "$TMP/err")" "blocked by" "the refusal names the hold the caller must judge"

# --- (o2) the guards bd's close keeps and its update does not ---------------
# A pinned bead, and a bead assigned to anyone but the actor the close runs as,
# are refused before anything is written, as `bd close` refuses them.
mkbead alpha open al-owned
mkbead alpha open al-osucc
printf 'assignee=someone-else\n' >> "$TMP/rigs/alpha/.beads/al-owned"
BEFORE=$(snap alpha al-owned)
rc=0; run --origin al-owned --successor al-osucc --kind folded || rc=$?
eq "$rc" 5 "an open bead assigned to someone else is refused"
eq "$(snap alpha al-owned)" "$BEFORE" "…and nothing is written"
has "$(cat "$TMP/err")" "assigned to someone-else" "…and the refusal names the assignee"
mkbead alpha pinned al-pinned
mkbead alpha open al-psucc
BEFORE=$(snap alpha al-pinned)
rc=0; run --origin al-pinned --successor al-psucc --kind folded || rc=$?
eq "$rc" 5 "a pinned bead is refused"
eq "$(snap alpha al-pinned)" "$BEFORE" "…and nothing is written"

# --- (i) --dry-run writes nothing ----------------------------------------
mkbead alpha open al-origin9
mkbead beta  open bt-succ9
BEFORE=$(snap alpha al-origin9)
rc=0; run --origin al-origin9 --successor bt-succ9 --kind re-homed --dry-run || rc=$?
eq "$rc" 0 "--dry-run succeeds"
eq "$(snap alpha al-origin9)" "$BEFORE" "--dry-run writes nothing"
has "$(cat "$TMP/out")" "dry run" "--dry-run says so"
has "$(cat "$TMP/out")" "al-origin9 supersedes bt-succ9, in rig:alpha" "--dry-run names the edge it would record"
mkbead alpha open al-origin15
mkbead alpha open al-succ15
printf 'dep.al-succ15=blocks\n' >> "$TMP/rigs/alpha/.beads/al-origin15"
rc=0; run --origin al-origin15 --successor al-succ15 --kind folded --dry-run || rc=$?
eq "$rc" 0 "--dry-run succeeds over a wait edge"
has "$(cat "$TMP/out")" "drop the 'blocked by al-succ15' wait edge" "--dry-run names the edge it would drop"
eq "$(edge alpha al-origin15 al-succ15)" blocks "--dry-run does not drop it"

# --- (s) a re-home writes no outcome of its own ---------------------------
mkbead alpha open al-task1
mkbead beta open bt-tsucc1
rc=0; run --origin al-task1 --successor bt-tsucc1 --kind re-homed || rc=$?
eq "$rc" 0 "a re-home succeeds"
eq "$(field alpha m.gc.outcome al-task1)" "" "the origin gets no gc.outcome"
eq "$(field alpha m.gc.work_outcome al-task1)" "" "…and no gc.work_outcome"

# --- (gate-b) unlanded work: refused under an evidence kind ---------------
mkbead alpha open al-unlanded
mkbead alpha closed al-usucc
printf 'm.merge_result=pull_request\n' >> "$TMP/rigs/alpha/.beads/al-unlanded"
BEFORE=$(snap alpha al-unlanded)
rc=0; run --origin al-unlanded --successor al-usucc --kind duplicate || rc=$?
eq "$rc" 7 "unlanded work (merge_result set) refuses an evidence-kind close"
eq "$(snap alpha al-unlanded)" "$BEFORE" "…and nothing is written"
has "$(cat "$TMP/err")" "no work" "the refusal names the no-work requirement"
# A judgment kind carries the caller's judgment, which the writer does not
# re-judge: the converse retire path disposes an in-flight anchor through it.
mkbead alpha open al-retire
mkbead beta  open bt-rtsucc
printf 'm.merge_result=pull_request\n' >> "$TMP/rigs/alpha/.beads/al-retire"
rc=0; run --origin al-retire --successor bt-rtsucc --kind re-homed || rc=$?
eq "$rc" 0 "a judgment kind (re-homed) disposes an in-flight anchor"
eq "$(field alpha status al-retire)" closed "…and closes it"
# The operator's pre-recorded PR-close disposition (pr-dispose.sh) is a ruling
# already made.
mkbead alpha open al-ruled
mkbead alpha open al-rsucc
printf 'm.merge_result=pull_request\nm.branch=polecat/al-ruled\nm.gc.pr_close_disposition_kind=duplicate\nm.gc.pr_close_disposition_successor=al-rsucc\n' >> "$TMP/rigs/alpha/.beads/al-ruled"
rc=0; run --origin al-ruled --successor al-rsucc --kind duplicate || rc=$?
eq "$rc" 0 "a pre-recorded PR-close disposition consummates under the recorded evidence kind"
eq "$(field alpha status al-ruled)" closed "…and closes the anchor"
# …but only the disposition it records: another successor is judged afresh.
mkbead alpha open al-ruledx
mkbead alpha closed al-rxsucc
printf 'm.merge_result=pull_request\nm.gc.pr_close_disposition_kind=duplicate\nm.gc.pr_close_disposition_successor=al-other\n' >> "$TMP/rigs/alpha/.beads/al-ruledx"
rc=0; run --origin al-ruledx --successor al-rxsucc --kind duplicate || rc=$?
eq "$rc" 7 "a disposition record naming another successor is no ruling for this one"
eq "$(field alpha status al-ruledx)" open "…and the anchor is left open"

# --- (gate-a) not a review/step/workflow bead ------------------------------
mkbead alpha open al-merged
mkbead beta  open bt-msucc
printf 'm.merge_result=merged\n' >> "$TMP/rigs/alpha/.beads/al-merged"
rc=0; run --origin al-merged --successor bt-msucc --kind re-homed || rc=$?
eq "$rc" 0 "merge_result=merged is landed work and may be disposed"
mkbead alpha open al-review
mkbead beta  open bt-rsucc
printf 'm.task_kind=review\n' >> "$TMP/rigs/alpha/.beads/al-review"
rc=0; run --origin al-review --successor bt-rsucc --kind re-homed || rc=$?
eq "$rc" 7 "a review bead is refused: its own machinery closes it"
mkbead alpha open al-step
mkbead beta  open bt-ssucc
printf 'm.gc.step_ref=mol-x.load\n' >> "$TMP/rigs/alpha/.beads/al-step"
rc=0; run --origin al-step --successor bt-ssucc --kind re-homed || rc=$?
eq "$rc" 7 "a step bead is refused"
mkbead alpha open al-wf
mkbead beta  open bt-wsucc
printf 'm.gc.kind=workflow\n' >> "$TMP/rigs/alpha/.beads/al-wf"
rc=0; run --origin al-wf --successor bt-wsucc --kind re-homed || rc=$?
eq "$rc" 7 "a workflow root is refused"

# --- (gate-held) another actor holds it, but self may ---------------------
mkbead alpha in_progress al-held
mkbead beta  open bt-hsucc
printf 'assignee=someone-else-hq-9999\n' >> "$TMP/rigs/alpha/.beads/al-held"
rc=0; run --origin al-held --successor bt-hsucc --kind re-homed || rc=$?
eq "$rc" 7 "an origin in_progress under another actor is refused"
has "$(cat "$TMP/err")" "in_progress under someone-else-hq-9999" "the refusal names the holder"
mkbead alpha in_progress al-mine
mkbead beta  open bt-msucc2
printf 'assignee=%s\n' "$BEADS_ACTOR" >> "$TMP/rigs/alpha/.beads/al-mine"
rc=0; run --origin al-mine --successor bt-msucc2 --kind re-homed || rc=$?
eq "$rc" 0 "an origin this session holds is not treated as someone else's"

# --- (gate-b) the evidence gates for fixed-upstream|duplicate -------------
mkbead alpha open al-xstore; printf 'm.gc.work_outcome=no-op\n' >> "$TMP/rigs/alpha/.beads/al-xstore"
mkbead beta closed bt-xsucc
rc=0; run --origin al-xstore --successor bt-xsucc --kind duplicate || rc=$?
eq "$rc" 7 "a duplicate close needs the successor in the same store"
has "$(cat "$TMP/err")" "same store" "the refusal names the same-store requirement"
# A fix upstream must have landed.
mkbead alpha open al-openS; printf 'm.gc.work_outcome=no-op\n' >> "$TMP/rigs/alpha/.beads/al-openS"
mkbead alpha open al-openSucc
rc=0; run --origin al-openS --successor al-openSucc --kind fixed-upstream || rc=$?
eq "$rc" 7 "a fixed-upstream close needs the fix closed or shipped"
mkbead alpha open al-shipO; printf 'm.gc.work_outcome=no-op\n' >> "$TMP/rigs/alpha/.beads/al-shipO"
mkbead alpha open al-shipSucc; printf 'm.gc.work_outcome=shipped\n' >> "$TMP/rigs/alpha/.beads/al-shipSucc"
rc=0; run --origin al-shipO --successor al-shipSucc --kind fixed-upstream || rc=$?
eq "$rc" 0 "a shipped-but-open fix satisfies the evidence"
# Origin must have done no work.
mkbead alpha open al-didwork
mkbead alpha closed al-dwSucc
printf 'm.branch=polecat/al-didwork\n' >> "$TMP/rigs/alpha/.beads/al-didwork"
rc=0; run --origin al-didwork --successor al-dwSucc --kind duplicate || rc=$?
eq "$rc" 7 "an origin with a work-product key and no no-op stamp is refused"
has "$(cat "$TMP/err")" "no work" "the refusal names the no-work requirement"
mkbead alpha open al-twin
mkbead alpha closed al-twinSucc
printf 'm.branch=polecat/al-twinSucc\nm.gc.work_outcome=no-op\n' >> "$TMP/rigs/alpha/.beads/al-twin"
rc=0; run --origin al-twin --successor al-twinSucc --kind duplicate || rc=$?
eq "$rc" 0 "work_outcome=no-op is accepted even with a work-product key present"
eq "$(field alpha status al-twin)" closed "and the duplicate is closed"

# --- (ar) a duplicate's waiters come to wait on its canonical ------------------
# bd's ready rule never follows a duplicates edge, so each open bead the
# duplicate blocks gains a blocks edge onto the canonical, before the close.
mkbead alpha open al-wdup
mkbead alpha open al-wcanon
mkbead alpha open al-waiter1
mkbead alpha closed al-waiter2
mkbead alpha open al-waiter3
printf 'dep.al-wdup=blocks\n' >> "$TMP/rigs/alpha/.beads/al-waiter1"
printf 'dep.al-wdup=blocks\n' >> "$TMP/rigs/alpha/.beads/al-waiter2"
printf 'dep.al-wdup=blocks\ndep.al-wcanon=blocks\n' >> "$TMP/rigs/alpha/.beads/al-waiter3"
printf 'dep.al-wdup=blocks\n' >> "$TMP/rigs/alpha/.beads/al-wcanon"
B3=$(snap alpha al-waiter3)
rc=0; FAKE_CALL_LOG="$TMP/ar.calls" run --origin al-wdup --successor al-wcanon --kind duplicate || rc=$?
eq "$rc" 0 "a duplicate whose canonical is open closes at once"
eq "$(field alpha status al-wdup)" closed "…the duplicate is closed"
eq "$(edge alpha al-waiter1 al-wcanon)" blocks "…an open bead it blocked now waits on the canonical"
CARRY_AT=$(grep -n '^dep add al-waiter1 al-wcanon' "$TMP/ar.calls" | head -1 | cut -d: -f1 || true)
CLOSE_AT=$(grep -n '^update al-wdup .*--status=closed' "$TMP/ar.calls" | head -1 | cut -d: -f1 || true)
[ -n "$CARRY_AT" ] && [ -n "$CLOSE_AT" ] && [ "$CARRY_AT" -lt "$CLOSE_AT" ] \
    && ok "…its edge is written before the close" || bad "…its edge is written before the close (edge at '${CARRY_AT:-none}', close at '${CLOSE_AT:-none}')"
eq "$(edge alpha al-waiter2 al-wcanon)" "" "…a closed bead it blocked gains no edge"
eq "$(edge alpha al-wcanon al-wcanon)" "" "…nor does the canonical, whose wait on its duplicate ends"
eq "$(snap alpha al-waiter3)" "$B3" "…and a bead the canonical already blocks is not written"
has "$(field alpha notes al-wdup)" "waits on al-wcanon now: al-waiter1." "…the close's note names what moved"
has "$(cat "$TMP/out")" "al-waiter1, which al-wdup blocked, wait on al-wcanon now" "…and so does the output"
# No wait moves once the canonical has delivered, under another kind, or on the
# repair path, whose close already happened.
mkbead alpha open al-wdup2
mkbead alpha closed al-wcanon2
mkbead alpha open al-wdup3
mkbead alpha open al-wcanon3
printf 'm.gc.work_outcome=shipped\n' >> "$TMP/rigs/alpha/.beads/al-wcanon3"
mkbead alpha open al-wre
mkbead alpha open al-wresucc
mkbead alpha closed al-wdup4
mkbead alpha open al-wcanon4
mkbead alpha open al-waiter4
printf 'dep.al-wdup2=blocks\ndep.al-wdup3=blocks\ndep.al-wre=blocks\ndep.al-wdup4=blocks\n' >> "$TMP/rigs/alpha/.beads/al-waiter4"
rc=0; run --origin al-wdup2 --successor al-wcanon2 --kind duplicate || rc=$?
eq "$rc/$(edge alpha al-waiter4 al-wcanon2)" "0/" "a duplicate of a closed canonical moves no wait"
rc=0; run --origin al-wdup3 --successor al-wcanon3 --kind duplicate || rc=$?
eq "$rc/$(edge alpha al-waiter4 al-wcanon3)" "0/" "…nor one of a canonical that has shipped"
rc=0; run --origin al-wre --successor al-wresucc --kind re-homed || rc=$?
eq "$rc/$(edge alpha al-waiter4 al-wresucc)" "0/" "…nor a re-home, whose waits end on its caller's judgment"
rc=0; run --origin al-wdup4 --successor al-wcanon4 --kind duplicate || rc=$?
eq "$rc/$(edge alpha al-waiter4 al-wcanon4)" "0/" "…nor the repair path"
# A waiter that cannot take the edge refuses the close before anything is
# written: one the canonical already joins by another edge type, any waiter of a
# canonical in another store, and a waiter read that fails.
mkbead alpha open al-wdup5
mkbead alpha open al-wcanon5
mkbead alpha open al-waiter5
mkbead alpha open al-waiter6
printf 'dep.al-wdup5=blocks\n' >> "$TMP/rigs/alpha/.beads/al-waiter5"
printf 'dep.al-wdup5=blocks\ndep.al-wcanon5=related\n' >> "$TMP/rigs/alpha/.beads/al-waiter6"
BD=$(snap alpha al-wdup5); B5=$(snap alpha al-waiter5); B6=$(snap alpha al-waiter6)
rc=0; run --origin al-wdup5 --successor al-wcanon5 --kind duplicate || rc=$?
eq "$rc" 5 "a waiter joined to the canonical by another edge type refuses the close"
eq "$(snap alpha al-wdup5)|$(snap alpha al-waiter5)|$(snap alpha al-waiter6)" "$BD|$B5|$B6" "…before anything is written"
has "$(cat "$TMP/err")" "al-waiter6 by a 'related' edge" "…and the refusal names the waiter and its edge"
rc=0; run --origin al-wdup5 --successor al-wcanon5 --kind duplicate --check || rc=$?
eq "$rc" 1 "--check refuses it too"
mkbead alpha open al-wdup6
mkbead beta  open bt-wcanon6
mkbead alpha open al-waiter7
printf 'm.merge_result=pull_request\nm.gc.pr_close_disposition_kind=duplicate\nm.gc.pr_close_disposition_successor=bt-wcanon6\nm.gc.pr_close_disposition_successor_store=rig:beta\n' >> "$TMP/rigs/alpha/.beads/al-wdup6"
printf 'dep.al-wdup6=blocks\n' >> "$TMP/rigs/alpha/.beads/al-waiter7"
BD=$(snap alpha al-wdup6); B7=$(snap alpha al-waiter7)
rc=0; run --origin al-wdup6 --successor bt-wcanon6 --kind duplicate || rc=$?
eq "$rc" 5 "a ruled duplicate onto another store's canonical refuses while a bead waits on it"
eq "$(snap alpha al-wdup6)|$(snap alpha al-waiter7)" "$BD|$B7" "…and writes nothing"
has "$(cat "$TMP/err")" "holds nothing" "…because an edge across stores holds nothing"
has "$(cat "$TMP/err")" "dep remove <bead> al-wdup6, then re-run" "…and it names the wait to end before a re-run"
mkbead alpha open al-wdup7
mkbead alpha open al-wcanon7
BD=$(snap alpha al-wdup7)
rc=0; FAKE_BD_DEP_LIST_UP_FAIL=1 run --origin al-wdup7 --successor al-wcanon7 --kind duplicate || rc=$?
eq "$rc/$(snap alpha al-wdup7)" "5/$BD" "a waiter read that fails refuses the close and writes nothing"
has "$(cat "$TMP/err")" "did not read" "…and says the read failed"
# What would refuse bd's close holds a duplicate before any waiter is written.
mkbead alpha open al-wdup8
mkbead alpha open al-wcanon8
mkbead alpha open al-wblock8
mkbead alpha open al-waiter8
printf 'dep.al-wblock8=blocks\n' >> "$TMP/rigs/alpha/.beads/al-wdup8"
printf 'dep.al-wdup8=blocks\n' >> "$TMP/rigs/alpha/.beads/al-waiter8"
B8=$(snap alpha al-waiter8)
rc=0; run --origin al-wdup8 --successor al-wcanon8 --kind duplicate || rc=$?
eq "$rc/$(field alpha status al-wdup8)" "5/open" "a duplicate another bead blocks is held"
eq "$(snap alpha al-waiter8)" "$B8" "…before its waiter gains an edge"
has "$(cat "$TMP/err")" "held by blocker(s) al-wblock8" "…and the refusal names the blocker"
# With no --except-key no gate is the duplicate's own, so an open human gate no
# one is assigned holds it the same way and stays open.
mkbead alpha open al-wdup8g
mkbead alpha open al-wcanon8g
mkbead alpha open al-wgate8
printf 'issue_type=gate\nawait_type=human\nawait_id=some-key\n' >> "$TMP/rigs/alpha/.beads/al-wgate8"
mkbead alpha open al-waiter8g
printf 'dep.al-wgate8=blocks\n' >> "$TMP/rigs/alpha/.beads/al-wdup8g"
printf 'dep.al-wdup8g=blocks\n' >> "$TMP/rigs/alpha/.beads/al-waiter8g"
B8=$(snap alpha al-waiter8g)
rc=0; run --origin al-wdup8g --successor al-wcanon8g --kind duplicate || rc=$?
eq "$rc/$(field alpha status al-wgate8)/$(snap alpha al-waiter8g)" "5/open/$B8" "…and so does a human gate, which stays open"
# An edge bd refuses, or one that does not read back, refuses the close, and the
# edges written before it stay.
mkbead alpha open al-wdup9
mkbead alpha open al-wcanon9
mkbead alpha open al-waiterA
mkbead alpha open al-waiterB
printf 'dep.al-wdup9=blocks\n' >> "$TMP/rigs/alpha/.beads/al-waiterA"
printf 'dep.al-wdup9=blocks\n' >> "$TMP/rigs/alpha/.beads/al-waiterB"
rc=0; FAKE_BD_DEP_ADD_REFUSE_FROM=al-waiterB run --origin al-wdup9 --successor al-wcanon9 --kind duplicate || rc=$?
eq "$rc" 5 "a waiter bd refuses the edge refuses the close"
eq "$(field alpha status al-wdup9)/$(edge alpha al-wdup9 al-wcanon9)" "open/" "…the duplicate stays open with no edge"
eq "$(edge alpha al-waiterA al-wcanon9)" blocks "…a waiter carried before it keeps its edge"
has "$(cat "$TMP/err")" "same parent chain" "…bd's refusal is printed"
has "$(cat "$TMP/err")" "al-waiterA keep the blocks edge onto al-wcanon9" "…and the edges that stay are named"
# --check and the dry run name the waits that would move, and write nothing.
mkbead alpha open al-wdup11
mkbead alpha open al-wcanon11
mkbead alpha open al-waiterD
printf 'dep.al-wdup11=blocks\n' >> "$TMP/rigs/alpha/.beads/al-waiterD"
BD=$(snap alpha al-wdup11); BW=$(snap alpha al-waiterD)
rc=0; run --origin al-wdup11 --successor al-wcanon11 --kind duplicate --check || rc=$?
eq "$rc" 0 "--check finds a duplicate with waiters eligible"
has "$(cat "$TMP/out")" "once al-waiterD, which it blocks, wait on al-wcanon11 too" "…and names the wait that moves"
rc=0; run --origin al-wdup11 --successor al-wcanon11 --kind duplicate --dry-run || rc=$?
has "$(cat "$TMP/out")" "waiters:   al-waiterD, which al-wdup11 blocks, each gain a blocks edge onto al-wcanon11 before the close" "the dry run names it too"
eq "$(snap alpha al-wdup11)|$(snap alpha al-waiterD)" "$BD|$BW" "…and neither writes anything"

# --- (check) --check evaluates the gates and writes nothing --------------
mkbead alpha open al-chkok
mkbead beta  open bt-chkok
BEFORE=$(snap alpha al-chkok)
rc=0; run --origin al-chkok --successor bt-chkok --kind re-homed --check || rc=$?
eq "$rc" 0 "--check passes an eligible origin"
eq "$(snap alpha al-chkok)" "$BEFORE" "--check writes nothing"
has "$(cat "$TMP/out")" "eligible to close" "--check reports eligibility"
mkbead alpha open al-chkno
mkbead beta  closed bt-chkno
rc=0; run --origin al-chkno --successor bt-chkno --kind duplicate --check || rc=$?
eq "$rc" 1 "--check refuses a cross-store duplicate with exit 1"
eq "$(field alpha status al-chkno)" open "--check refusal writes nothing"
has "$(cat "$TMP/err")" "--check refused" "--check names the refusal"
mkbead alpha closed al-chkclosed
mkbead beta  open bt-chkclosed
rc=0; run --origin al-chkclosed --successor bt-chkclosed --kind re-homed --check || rc=$?
eq "$rc" 0 "--check over an already-closed origin passes (repair path)"
eq "$(edge alpha al-chkclosed bt-chkclosed)" "" "--check still writes nothing"

# A bead that names the branch its work was pushed to.
mkbranched() { mkbead "$1" "$2" "$3"; printf 'm.branch=polecat/%s\n' "$3" >> "$TMP/rigs/$1/.beads/$3"; }

# --- (ad) the retired bead's branch goes to branch-end, after the close ------
mkbranched alpha open al-br1
mkbead beta open bt-br1
: > "$BE_LOG"
rc=0; run --origin al-br1 --successor bt-br1 --kind re-homed || rc=$?
eq "$rc" 0 "a retire whose bead names a branch succeeds"
eq "$(field alpha status al-br1)" closed "…and closes the bead"
eq "$(cat "$BE_LOG")" "--rig alpha --branch polecat/al-br1 --bead al-br1 status-at-call=closed" \
   "branch-end is handed the bead's rig, branch and id, once, after the close"
has "$(cat "$TMP/out")" "branch-end (stub): ended" "…and its report is printed"
has "$(field alpha notes al-br1)" "branch-end (stub): ended" "…and recorded on the bead"

# --- (ae) a branch that cannot be ended leaves the close standing -----------
mkbranched alpha open al-br2
mkbead beta open bt-br2
rc=0; BE_RC=4 run --origin al-br2 --successor bt-br2 --kind not-needed || rc=$?
eq "$rc" 0 "a branch-end that fails does not fail the retire"
eq "$(field alpha status al-br2)" closed "…the close stands"
eq "$(edge alpha al-br2 bt-br2)" supersedes "…with its edge"
has "$(cat "$TMP/err")" "branch-end (stub): did NOT end" "…branch-end's own reason is passed on"
has "$(cat "$TMP/err")" "the close stands, but branch polecat/al-br2 is still on the git remote" "…and a WARN names the branch"
has "$(cat "$TMP/err")" "end it with: $BE_STUB --rig alpha --branch polecat/al-br2 --bead al-br2" "…and the command that ends it"
has "$(field alpha notes al-br2)" "Branch polecat/al-br2 is still on the git remote (branch-end exit 4: branch-end (stub): did NOT end)" \
    "…and the bead records that the branch is still there"

# --- (af) a branch kept for a live owner is reported, not warned about ------
mkbranched alpha open al-br3
mkbead beta open bt-br3
rc=0; BE_RC=3 run --origin al-br3 --successor bt-br3 --kind folded || rc=$?
eq "$rc" 0 "a branch kept for a live owner does not fail the retire"
has "$(cat "$TMP/out")" "kept for a live owner" "…its report is printed"
hasnt "$(cat "$TMP/err")" "WARN" "…and nothing is warned"
has "$(field alpha notes al-br3)" "kept for a live owner" "…and the bead records why its branch stays"

# --- (ag) no branch-end without a landed close, a branch, or a real run -----
mkbranched alpha open al-br4
mkbead beta open bt-br4
: > "$BE_LOG"
rc=0; FAKE_BD_CLOSE_REFUSE=1 run --origin al-br4 --successor bt-br4 --kind folded || rc=$?
eq "$rc" 5 "a refused close still exits 5"
eq "$(cat "$BE_LOG")" "" "…and ends no branch"
mkbranched alpha open al-br5
mkbead beta open bt-br5
rc=0; FG_VERDICT=hold run --origin al-br5 --successor bt-br5 --kind re-homed || rc=$?
eq "$rc" 5 "a held close still exits 5"
eq "$(cat "$BE_LOG")" "" "…and ends no branch"
mkbead alpha open al-br6
mkbead beta open bt-br6
rc=0; run --origin al-br6 --successor bt-br6 --kind re-homed || rc=$?
eq "$rc" 0 "a bead that names no branch retires"
eq "$(cat "$BE_LOG")" "" "…and calls no branch-end"
mkbranched alpha open al-br7
mkbead beta open bt-br7
rc=0; run --origin al-br7 --successor bt-br7 --kind re-homed --dry-run || rc=$?
eq "$rc" 0 "a dry run over a branch succeeds"
eq "$(cat "$BE_LOG")" "" "…and ends no branch"
has "$(cat "$TMP/out")" "end polecat/al-br7 on the git remote of rig:alpha once the close lands" "…and its plan names the branch"
eq "$(field alpha status al-br7)" open "…and closes nothing"

# --- (ah) the repair path ends an already-closed bead's branch too ----------
mkbranched alpha closed al-br8
mkbead beta open bt-br8
: > "$BE_LOG"
rc=0; run --origin al-br8 --successor bt-br8 --kind re-homed || rc=$?
eq "$rc" 0 "a repair over a bead that names a branch succeeds"
eq "$(cat "$BE_LOG")" "--rig alpha --branch polecat/al-br8 --bead al-br8 status-at-call=closed" \
   "the repair hands the closed bead's branch to branch-end"
rc=0; run --origin al-br8 --successor bt-br8 --kind re-homed || rc=$?
eq "$(grep -c 'branch-end (stub): ended' "$TMP/rigs/alpha/.beads/al-br8")" 1 \
   "a re-run that reaches the same outcome records it once"

# --- (aj) end to end: the real branch-end.sh against a bare origin -----------
# A rig of its own, gamma, is a git checkout whose origin is a bare repository:
# url.insteadOf sends a GitHub-shaped origin to it. Its pre-receive hook refuses
# branch deletes while the refuse-delete file exists. Nothing from the session's
# git environment reaches it.
unset "${!GIT_@}" 2>/dev/null || true
export GIT_CONFIG_GLOBAL="$TMP/gitconfig" GIT_CONFIG_NOSYSTEM=1
: > "$GIT_CONFIG_GLOBAL"
# A commit or tag made where no repository sets an identity takes it from here.
# Without it git falls back to the login account's name, which a Linux CI
# runner leaves empty, so such a commit fails there and passes on a Mac.
git config --file "$GIT_CONFIG_GLOBAL" user.name T
git config --file "$GIT_CONFIG_GLOBAL" user.email t@e.com
GM="$TMP/rigs/gamma"; GM_BARE="$TMP/gamma-origin.git"
mkdir -p "$GM/.beads"
cat > "$TMP/rigs.json" <<JSON
{"rigs":[
  {"name":"alpha","path":"$TMP/rigs/alpha","prefix":"al","hq":false},
  {"name":"beta","path":"$TMP/rigs/beta","prefix":"bt","hq":true},
  {"name":"gamma","path":"$GM","prefix":"gm","hq":false}
]}
JSON
git init -q --bare -b main "$GM_BARE"
cat > "$GM_BARE/hooks/pre-receive" <<HOOK
#!/usr/bin/env bash
while read -r old new ref; do
  case "\$ref" in refs/heads/*) case "\$new" in *[!0]*) ;; *) [ -e "$TMP/refuse-delete" ] && { echo "refusing branch deletes" >&2; exit 1; } ;; esac ;; esac
done
exit 0
HOOK
chmod +x "$GM_BARE/hooks/pre-receive"
git init -q -b main "$GM"
git -C "$GM" config user.email t@e.com
git -C "$GM" config user.name T
git -C "$GM" config commit.gpgsign false
git -C "$GM" remote add origin https://github.com/test/gamma.git
git -C "$GM" config "url.$GM_BARE.insteadOf" https://github.com/test/gamma.git
echo seed > "$GM/seed"; git -C "$GM" add seed; git -C "$GM" commit -qm seed
git -C "$GM" push -q origin main
for b in polecat/gm-e2e1 polecat/gm-e2e2 polecat/gm-bystander; do
  git -C "$GM" checkout -q -b "$b" main
  echo "$b" > "$GM/work"; git -C "$GM" add work; git -C "$GM" commit -qm "work on $b"
  git -C "$GM" push -q origin "$b"
  git -C "$GM" checkout -q main
done
gm_tip() { git -C "$GM_BARE" rev-parse -q --verify "refs/heads/$1" 2>/dev/null || true; }
TIP1=$(gm_tip polecat/gm-e2e1); TIP2=$(gm_tip polecat/gm-e2e2)

mkbranched gamma open gm-e2e1
mkbead beta open bt-e2e1
rc=0; GC_BRANCH_END_TOOL='' run --origin gm-e2e1 --successor bt-e2e1 --kind re-homed || rc=$?
eq "$rc" 0 "end to end: the retire succeeds"
eq "$(field gamma status gm-e2e1)" closed "end to end: the bead is closed"
eq "$(gm_tip polecat/gm-e2e1)" "" "end to end: its branch is gone from origin"
eq "$(git -C "$GM_BARE" rev-parse -q --verify "refs/tags/archive/polecat/gm-e2e1@${TIP1:0:12}^{commit}" || true)" "$TIP1" \
   "end to end: an archive tag on origin pins the tip"
has "$(cat "$TMP/out")" "branch-end: ended polecat/gm-e2e1" "end to end: the end is reported"
has "$(field gamma notes gm-e2e1)" "branch-end: ended polecat/gm-e2e1 at ${TIP1:0:12}; its tip is kept by refs/tags/archive/polecat/gm-e2e1@${TIP1:0:12}" \
    "end to end: the bead records where the tip is kept"
[ -n "$(gm_tip polecat/gm-bystander)" ] && ok "end to end: a branch no retire names stays" || bad "end to end: a branch no retire names stays"

mkbranched gamma open gm-e2e2
mkbead beta open bt-e2e2
: > "$TMP/refuse-delete"
rc=0; GC_BRANCH_END_TOOL='' run --origin gm-e2e2 --successor bt-e2e2 --kind re-homed || rc=$?
rm -f "$TMP/refuse-delete"
eq "$rc" 0 "end to end: a delete origin refuses does not fail the retire"
eq "$(field gamma status gm-e2e2)" closed "end to end: the close stands"
eq "$(gm_tip polecat/gm-e2e2)" "$TIP2" "end to end: the branch stays at its tip"
has "$(cat "$TMP/err")" "branch-end: did NOT end polecat/gm-e2e2: origin refused the delete" "end to end: branch-end's reason reaches the caller"
has "$(cat "$TMP/err")" "the close stands" "end to end: and the WARN says the close stands"
has "$(field gamma notes gm-e2e2)" "Branch polecat/gm-e2e2 is still on the git remote" "end to end: the bead records that its branch is still there"

# --- (ak) the command a WARN names survives a paste --------------------------
mkbead alpha open al-br10
printf 'm.branch=%s\n' 'polecat/al-br10;$(touch pwned)' >> "$TMP/rigs/alpha/.beads/al-br10"
mkbead beta open bt-br10
rc=0; BE_RC=4 run --origin al-br10 --successor bt-br10 --kind re-homed || rc=$?
eq "$rc" 0 "a retire whose branch name carries shell metacharacters succeeds"
PASTE=$(sed -n 's/.*(branch-end exit 4); end it with: //p' "$TMP/err" | tail -1)
: > "$BE_LOG"
( cd "$TMP" && eval "$PASTE" ) >/dev/null 2>&1 || true
has "$(cat "$BE_LOG")" '--branch polecat/al-br10;$(touch pwned) --bead al-br10 ' \
    "the WARN's command, pasted, hands branch-end the branch as one argument"
if [ -e "$TMP/pwned" ]; then bad "…and runs nothing the branch name spells"; else ok "…and runs nothing the branch name spells"; fi

# --- (al) the close lands only on the bead the gates judged ------------------
mkbead alpha open al-judged
mkbead beta  open bt-judged
: > "$TMP/updates.log"
rc=0; FAKE_UPDATE_LOG="$TMP/updates.log" run --origin al-judged --successor bt-judged --kind re-homed || rc=$?
eq "$rc" 0 "a bead nobody took since the gates read it is disposed"
has "$(grep -F -- '--status=closed' "$TMP/updates.log")" "al-judged --if-status=open --if-assignee= --status=closed" \
   "the close is conditional on the status and assignee the gates read"
mkbead alpha in_progress al-judged-mine
printf 'assignee=%s\n' "$BEADS_ACTOR" >> "$TMP/rigs/alpha/.beads/al-judged-mine"
mkbead beta  open bt-judged-mine
: > "$TMP/updates.log"
rc=0; FAKE_UPDATE_LOG="$TMP/updates.log" run --origin al-judged-mine --successor bt-judged-mine --kind re-homed || rc=$?
eq "$rc" 0 "a bead this session holds is disposed under its claim"
has "$(grep -F -- '--status=closed' "$TMP/updates.log")" "--if-status=in_progress --if-assignee=$BEADS_ACTOR --status=closed" \
   "…with the close conditional on that claim"
# Another actor claims the bead after the gates read it and before the close.
mkbead alpha open al-taken
mkbead alpha open al-tsucc
printf 'dep.al-tsucc=blocks\n' >> "$TMP/rigs/alpha/.beads/al-taken"
rc=0; FAKE_BD_CLAIM_BEFORE_CLOSE="in_progress deferred-dispatch" run --origin al-taken --successor al-tsucc --kind re-homed || rc=$?
eq "$rc" 4 "a claim that lands between the gates and the close refuses the close (exit 4)"
eq "$(field alpha status al-taken)/$(field alpha assignee al-taken)" "in_progress/deferred-dispatch" "…the claim stands"
eq "$(edge alpha al-taken al-tsucc)" blocks "…the wait onto the successor is back, and no disposition edge is recorded"
eq "$(field alpha notes al-taken)" "" "…and no note is written"
has "$(cat "$TMP/err")" "al-taken is no longer open and unassigned" "the refusal names the state the gates judged"
has "$(cat "$TMP/err")" "nothing is recorded" "…and says nothing was written"
# Two closers judge the same unclaimed bead: another closer's close lands
# between this one's read and its own, so this one records nothing over it.
mkbead alpha open al-race
mkbead alpha open al-race-b
rc=0; FAKE_BD_CLAIM_BEFORE_CLOSE="closed " run --origin al-race --successor al-race-b --kind re-homed || rc=$?
eq "$rc" 4 "a close that lands between a second closer's read and its own refuses the second"
eq "$(edge alpha al-race al-race-b)" "" "…and the second records no edge"
eq "$(field alpha notes al-race)" "" "…and no note"

# --- (as) the edge goes on before the close, so two callers cannot both name one
# racer <name> <bead-rehome args...> — write a script that makes a second caller's
# whole run, and print its path. The run's exit lands in racer.<name>.rc.
racer() {
  local name="$1"; shift
  { printf '%q ' "$SCRIPT" "$@"; printf '>%q 2>&1; echo $? >%q\n' "$TMP/racer.$name.out" "$TMP/racer.$name.rc"; } > "$TMP/racer.$name.sh"
  printf '%s' "$TMP/racer.$name.sh"
}
racer_rc() { cat "$TMP/racer.$1.rc" 2>/dev/null || printf 'did not run'; }
mkbead alpha open al-ord
mkbead alpha open al-ords
: > "$TMP/calls.log"
rc=0; FAKE_CALL_LOG="$TMP/calls.log" run --origin al-ord --successor al-ords --kind folded || rc=$?
eq "$rc" 0 "a disposition lands"
EDGE_AT=$(grep -n '^dep add al-ord al-ords' "$TMP/calls.log" | head -1 | cut -d: -f1 || true)
CLOSE_AT=$(grep -n '^update al-ord .*--status=closed' "$TMP/calls.log" | head -1 | cut -d: -f1 || true)
if [ -n "$EDGE_AT" ] && [ -n "$CLOSE_AT" ] && [ "$EDGE_AT" -lt "$CLOSE_AT" ]; then
  ok "…its edge is written before its close"
else
  bad "…its edge is written before its close (edge at line '${EDGE_AT:-none}', close at '${CLOSE_AT:-none}')"
fi

# A second caller reads the origin while the first is paused just after its close.
# A close with no edge on it was the opening for a second successor.
mkbead alpha open al-ra; mkbead alpha open al-ra-1; mkbead alpha open al-ra-2
R=$(racer ra --origin al-ra --successor al-ra-2 --kind folded)
rc=0; FAKE_RACE_AFTER_CLOSE="$R" run --origin al-ra --successor al-ra-1 --kind folded || rc=$?
eq "$rc" 0 "(as) the first closer, paused just after its close, finishes"
eq "$(racer_rc ra)" 6 "…a second caller that reads the closed origin in that pause refuses another successor"
has "$(cat "$TMP/racer.ra.out")" "already names al-ra-1" "…and names the first one's choice"
eq "$(edge alpha al-ra al-ra-1)" supersedes "…the first edge stands"
eq "$(edge alpha al-ra al-ra-2)" "" "…and the second writes none"

# The same, with the first paused between its edge and its close.
mkbead alpha open al-rb; mkbead alpha open al-rb-1; mkbead alpha open al-rb-2
R=$(racer rb --origin al-rb --successor al-rb-2 --kind folded)
rc=0; FAKE_RACE_BEFORE_CLOSE="$R" run --origin al-rb --successor al-rb-1 --kind folded || rc=$?
eq "$rc" 0 "(as) the first closer, paused between its edge and its close, finishes"
eq "$(racer_rc rb)" 6 "…a second caller in that pause refuses another successor"
eq "$(field alpha status al-rb)" closed "…the first close lands"
eq "$(edge alpha al-rb al-rb-1)" supersedes "…under the first edge"
eq "$(edge alpha al-rb al-rb-2)" "" "…and the second writes none"

# Both read the open origin before either wrote. The second caller runs whole
# while the first is paused before its edge, so the first's write is the later one.
mkbead alpha open al-rc; mkbead alpha open al-rc-1; mkbead alpha open al-rc-2
R=$(racer rc --origin al-rc --successor al-rc-2 --kind folded)
rc=0; FAKE_RACE_BEFORE_EDGE="$R" run --origin al-rc --successor al-rc-1 --kind folded || rc=$?
eq "$(racer_rc rc)" 0 "(as) of two callers that read the open origin first, the one that writes first disposes it"
eq "$rc" 6 "…the later writer reads the other's edge beside its own, and stops"
has "$(cat "$TMP/err")" "named al-rc-2 as the successor of al-rc" "…naming the other's choice"
eq "$(edge alpha al-rc al-rc-1)" "" "…its own edge comes back off"
eq "$(edge alpha al-rc al-rc-2)" supersedes "…the other's stands"
eq "$(grep -c '^notes=' "$TMP/rigs/alpha/.beads/al-rc")" 1 "…and it writes no note"

# Two repairs of one closed, unnamed origin, the same way.
mkbead alpha closed al-rd; mkbead alpha open al-rd-1; mkbead alpha open al-rd-2
R=$(racer rd --origin al-rd --successor al-rd-2 --kind folded)
rc=0; FAKE_RACE_BEFORE_EDGE="$R" run --origin al-rd --successor al-rd-1 --kind folded || rc=$?
eq "$(racer_rc rd)" 0 "(as) of two repairs of a closed bead, the one that writes first records it"
eq "$rc" 6 "…the later repair stops"
eq "$(edge alpha al-rd al-rd-1)" "" "…its own edge comes back off"
eq "$(edge alpha al-rd al-rd-2)" supersedes "…the other's stands"
eq "$(grep -c '^notes=' "$TMP/rigs/alpha/.beads/al-rd")" 1 "…and it writes no note"

# A person reopens a disposed bead. Its edge stays, so a second disposition still
# has to reconcile with the first, and the first's call finishes it again.
mkbead alpha open al-re; mkbead alpha open al-re-1; mkbead alpha open al-re-2
rc=0; run --origin al-re --successor al-re-1 --kind folded || rc=$?
eq "$rc" 0 "(as) a disposition lands"
printf 'status=open\n' >> "$TMP/rigs/alpha/.beads/al-re"
rc=0; run --origin al-re --successor al-re-2 --kind folded || rc=$?
eq "$rc" 6 "…once the bead is reopened, another successor is still refused"
eq "$(field alpha status al-re)" open "…and the bead stays open"
eq "$(edge alpha al-re al-re-2)" "" "…with no second edge"
rc=0; run --origin al-re --successor al-re-1 --kind folded || rc=$?
eq "$rc" 0 "…the same call closes it again"
eq "$(field alpha status al-re)" closed "…the bead closes"
eq "$(edge alpha al-re al-re-1)" supersedes "…under its one edge"

# A close naming this same successor beats this one's: the edge is its record too.
mkbead alpha open al-rf; mkbead alpha open al-rf-1
printf 'dep.al-rf-1=blocks\n' >> "$TMP/rigs/alpha/.beads/al-rf"
R=$(racer rf --origin al-rf --successor al-rf-1 --kind folded)
rc=0; FAKE_RACE_BEFORE_CLOSE="$R" run --origin al-rf --successor al-rf-1 --kind folded || rc=$?
eq "$(racer_rc rf)" 0 "(as) a second caller naming the same successor closes the bead first"
eq "$rc" 4 "…the first's close, beaten, exits 4"
eq "$(edge alpha al-rf al-rf-1)" supersedes "…and the edge stays, since the close that landed is recorded by it"
rc=0; run --origin al-rf --successor al-rf-1 --kind folded || rc=$?
eq "$rc" 0 "…a re-run finds the disposition recorded"
has "$(cat "$TMP/out")" "already records this disposition" "…and says so"

# Every disposition edge counts, not only the first a reader takes.
mkbead alpha open al-rk; mkbead alpha open al-rk-1; mkbead alpha open al-rk-2
printf 'dep.al-rk-1=supersedes\ndep.al-rk-2=supersedes\n' >> "$TMP/rigs/alpha/.beads/al-rk"
rc=0; run --origin al-rk --successor al-rk-1 --kind folded || rc=$?
eq "$rc" 6 "(as) a bead naming two successors is refused under the first as well"
eq "$(field alpha status al-rk)" open "…and is not closed"

# A close that was refused takes back only what this run wrote.
mkbead alpha open al-rg; mkbead alpha open al-rg-1
printf 'dep.al-rg-1=supersedes\n' >> "$TMP/rigs/alpha/.beads/al-rg"
rc=0; FAKE_BD_CLOSE_REFUSE=1 run --origin al-rg --successor al-rg-1 --kind folded || rc=$?
eq "$rc" 5 "(as) a close refused over an edge an earlier run wrote exits 5"
eq "$(edge alpha al-rg al-rg-1)" supersedes "…and leaves that edge"
rc=0; run --origin al-rg --successor al-rg-1 --kind folded || rc=$?
eq "$rc" 0 "…the same call then finishes it"
eq "$(field alpha status al-rg)" closed "…and closes the bead"

# An edge that does not come back off is said out loud, with what removes it.
mkbead alpha open al-rh; mkbead alpha open al-rh-1
rc=0; FAKE_BD_CLOSE_REFUSE=1 FAKE_BD_DEP_REMOVE_FAIL=1 run --origin al-rh --successor al-rh-1 --kind folded || rc=$?
eq "$rc" 5 "(as) a refused close whose edge will not come off still exits 5"
has "$(cat "$TMP/err")" "did not come back off" "…the WARN says the edge is still there"
has "$(cat "$TMP/err")" "dep remove al-rh al-rh-1" "…and names what removes it"

# The read-back decides before the close: unread, or missing, closes nothing.
mkbead alpha open al-ri; mkbead alpha open al-ri-1
rc=0; FAKE_LIST_FAIL_AFTER_EDGE=1 run --origin al-ri --successor al-ri-1 --kind folded || rc=$?
eq "$rc" 4 "(as) an edge whose read-back does not answer exits 4"
rm -f "$TMP/rigs/alpha/.beads/.list-id-fails"
eq "$(field alpha status al-ri)" open "…the bead is not closed"
eq "$(edge alpha al-ri al-ri-1)" "" "…and the edge comes back off"
has "$(cat "$TMP/err")" "did not read back" "…and it says so"
mkbead alpha open al-rj; mkbead alpha open al-rj-1
rc=0; FAKE_BD_DEP_ADD_NOOP_FROM=al-rj run --origin al-rj --successor al-rj-1 --kind folded || rc=$?
eq "$rc" 4 "(as) an edge reported written that reads back absent exits 4"
eq "$(field alpha status al-rj)" open "…and the bead is not closed"

# --- (at) a take-back never strips a close naming the same successor ---------
# Callers naming one successor share one edge. The first caller takes it back after
# its close loses to a holder's claim, and the holder read it as standing.
ALPHA="$TMP/rigs/alpha/.beads"
await_rc() { # <file> — wait for a backgrounded run to record its exit
  local n=0
  until [ -e "$1" ] || [ "$n" -ge 2400 ]; do sleep 0.05; n=$((n + 1)); done
}
# The holder claims while the first caller is paused before its close, reads the
# edge, and stays paused before its own close until the first caller has finished.
start_paused_holder() { # <name> <origin> <successor>
  local n="$1" o="$2" su="$3"
  cat > "$TMP/$n.held.sh" <<HOLD
: > "$TMP/$n.reached"
until [ -e "$TMP/$n.release" ]; do sleep 0.05; done
HOLD
  cat > "$TMP/$n.claim.sh" <<CLAIM
printf 'status=in_progress\nassignee=holder-b\n' >> "$ALPHA/$o"
rm -f "$ALPHA/.raced.BEFORE_CLOSE.$o"
( export BEADS_ACTOR=holder-b FAKE_RACE_BEFORE_CLOSE="$TMP/$n.held.sh"
  "$SCRIPT" --origin "$o" --successor "$su" --kind folded >"$TMP/$n.out" 2>&1
  echo \$? >"$TMP/$n.rc" ) >/dev/null 2>&1 </dev/null &
until [ -e "$TMP/$n.reached" ]; do sleep 0.05; done
CLAIM
  printf '%s' "$TMP/$n.claim.sh"
}
mkbead alpha open al-ta; mkbead alpha open al-ta-1
H=$(start_paused_holder ta al-ta al-ta-1)
rc=0; FAKE_RACE_BEFORE_CLOSE="$H" run --origin al-ta --successor al-ta-1 --kind folded || rc=$?
eq "$rc" 4 "(at) a close that loses to a holder's claim exits 4"
eq "$(field alpha status al-ta)/$(edge alpha al-ta al-ta-1)" "in_progress/" "…with the edge off and the holder's claim standing"
: > "$TMP/ta.release"; await_rc "$TMP/ta.rc"
eq "$(cat "$TMP/ta.rc" 2>/dev/null)" 0 "…the holder, who read that edge as standing, closes the bead"
eq "$(field alpha status al-ta)" closed "…the bead is closed"
eq "$(edge alpha al-ta al-ta-1)" supersedes "…and the holder's read after its close puts the edge back"
has "$(cat "$TMP/ta.out")" "its supersedes edge had gone, so it is back" "…and says so"
# The holder's whole run lands in the moment before the first caller's take-back, so
# the holder's read after its close finds the edge and only the taker can restore it.
mkbead alpha open al-tb; mkbead alpha open al-tb-1
printf "printf 'status=in_progress\\\\nassignee=holder-b\\\\n' >> %q\n" "$ALPHA/al-tb" > "$TMP/tb.claim.sh"
R=$(racer tb --origin al-tb --successor al-tb-1 --kind folded)
printf 'export BEADS_ACTOR=holder-b\nbash %q\n' "$R" > "$TMP/tb.holder.sh"
rc=0; FAKE_RACE_BEFORE_CLOSE="$TMP/tb.claim.sh" FAKE_RACE_BEFORE_TAKE_BACK="$TMP/tb.holder.sh" run --origin al-tb --successor al-tb-1 --kind folded || rc=$?
eq "$rc/$(racer_rc tb)" "4/0" "(at) a holder's whole run in the moment before a take-back: the first exits 4, the holder 0"
eq "$(field alpha status al-tb)" closed "…the bead is closed"
eq "$(edge alpha al-tb al-tb-1)" supersedes "…and the taker's read after its take-back puts the edge back"
has "$(cat "$TMP/out")" "its supersedes edge had gone, so it is back" "…and says so"
# The same two orders with a wait onto the successor the first caller dropped.
mkbead alpha open al-tc; mkbead alpha open al-tc-1
printf 'dep.al-tc-1=blocks\n' >> "$ALPHA/al-tc"
printf "printf 'status=in_progress\\\\nassignee=holder-b\\\\n' >> %q\n" "$ALPHA/al-tc" > "$TMP/tc.claim.sh"
R=$(racer tc --origin al-tc --successor al-tc-1 --kind folded)
printf 'export BEADS_ACTOR=holder-b\nbash %q\n' "$R" > "$TMP/tc.holder.sh"
rc=0; FAKE_RACE_BEFORE_CLOSE="$TMP/tc.claim.sh" FAKE_RACE_BEFORE_TAKE_BACK="$TMP/tc.holder.sh" run --origin al-tc --successor al-tc-1 --kind folded || rc=$?
eq "$rc/$(racer_rc tc)" "4/0" "(at) with a wait dropped first: the first exits 4, the holder 0"
eq "$(field alpha status al-tc)/$(edge alpha al-tc al-tc-1)" "closed/supersedes" "…and the disposition's edge replaces the wait the take-back put back"
mkbead alpha open al-td; mkbead alpha open al-td-1
printf 'dep.al-td-1=blocks\n' >> "$ALPHA/al-td"
H=$(start_paused_holder td al-td al-td-1)
rc=0; FAKE_RACE_BEFORE_CLOSE="$H" run --origin al-td --successor al-td-1 --kind folded || rc=$?
eq "$rc/$(edge alpha al-td al-td-1)" "4/blocks" "(at) a holder paused across the take-back: the first exits 4 and its wait is back"
: > "$TMP/td.release"; await_rc "$TMP/td.rc"
eq "$(cat "$TMP/td.rc" 2>/dev/null)" 5 "…which refuses the holder's close, so nothing closes unrecorded"
eq "$(field alpha status al-td)/$(edge alpha al-td al-td-1)" "in_progress/blocks" "…and the bead stays the holder's, waiting"
# A close that lands and cannot prove or restore its edge stands, and says so.
mkbead alpha open al-te; mkbead alpha open al-te-1
rc=0; FAKE_LIST_FAIL_AFTER_CLOSE=1 run --origin al-te --successor al-te-1 --kind folded || rc=$?
rm -f "$ALPHA/.list-id-fails"
eq "$rc/$(field alpha status al-te)" "4/closed" "(at) a read after the close that does not answer: exit 4, the close stands"
has "$(cat "$TMP/err")" "did not read after its edge changed" "…and it says so"
rc=0; run --origin al-te --successor al-te-1 --kind folded || rc=$?
eq "$rc" 0 "…the same call run again finds it recorded"
mkbead alpha open al-tf; mkbead alpha open al-tf-1
printf 'dep.al-tf-1=supersedes\n' >> "$ALPHA/al-tf"
printf "sed -i.bak '/^dep.al-tf-1=/d' %q\n" "$ALPHA/al-tf" > "$TMP/tf.gone.sh"
rc=0; FAKE_RACE_AFTER_CLOSE="$TMP/tf.gone.sh" FAKE_BD_DEP_ADD_FAIL=1 run --origin al-tf --successor al-tf-1 --kind folded || rc=$?
eq "$rc/$(field alpha status al-tf)/$(edge alpha al-tf al-tf-1)" "4/closed/" "(at) an edge that cannot go back: exit 4, the close stands"
has "$(cat "$TMP/err")" "the same call run again records it" "…and it names the re-run"
rc=0; run --origin al-tf --successor al-tf-1 --kind folded || rc=$?
eq "$rc/$(edge alpha al-tf al-tf-1)" "0/supersedes" "…which records it"
mkbead alpha open al-tg; mkbead alpha open al-tg-1; mkbead alpha open al-tg-2
printf 'dep.al-tg-1=supersedes\n' >> "$ALPHA/al-tg"
printf "sed -i.bak '/^dep.al-tg-1=/d' %q\nprintf 'dep.al-tg-2=supersedes\\\\n' >> %q\n" "$ALPHA/al-tg" "$ALPHA/al-tg" > "$TMP/tg.other.sh"
rc=0; FAKE_RACE_AFTER_CLOSE="$TMP/tg.other.sh" run --origin al-tg --successor al-tg-1 --kind folded || rc=$?
eq "$rc/$(edge alpha al-tg al-tg-1)/$(edge alpha al-tg al-tg-2)" "6//supersedes" "(at) another successor's edge in its place: exit 6 and no second edge"
has "$(cat "$TMP/err")" "reconcile the two by hand" "…and it says what is owed"
# A wait put back in the instant after a close's own read of it stands where the
# edge goes. The WARN says so, and the repair path replaces it on the re-run.
mkbead alpha open al-ti; mkbead alpha open al-ti-1
printf 'dep.al-ti-1=supersedes\n' >> "$ALPHA/al-ti"
printf "sed -i.bak '/^dep.al-ti-1=/d' %q\nprintf 'dep.al-ti-1=blocks\\\\n' >> %q\n" "$ALPHA/al-ti" "$ALPHA/al-ti" > "$TMP/ti.wait.sh"
rc=0; FAKE_RACE_AFTER_CLOSE="$TMP/ti.wait.sh" run --origin al-ti --successor al-ti-1 --kind folded || rc=$?
eq "$rc/$(field alpha status al-ti)/$(edge alpha al-ti al-ti-1)" "4/closed/blocks" "(at) a wait standing where the edge goes: exit 4, the close stands"
has "$(cat "$TMP/err")" "the same call run again records it" "…and it names the re-run"
rc=0; run --origin al-ti --successor al-ti-1 --kind folded || rc=$?
eq "$rc/$(edge alpha al-ti al-ti-1)" "0/supersedes" "…whose repair replaces the wait with the edge"
# A close that lands reads its edge in place and writes nothing more.
mkbead alpha open al-th; mkbead alpha open al-th-1
: > "$TMP/th.calls"
rc=0; FAKE_CALL_LOG="$TMP/th.calls" run --origin al-th --successor al-th-1 --kind folded || rc=$?
eq "$rc/$(grep -c '^dep add al-th al-th-1' "$TMP/th.calls")" "0/1" "(at) a close with its edge in place adds it once"
hasnt "$(cat "$TMP/out")" "had gone" "…and reports nothing back"

# --- (au) a repair records nothing on a bead reopened since its read ----------
reopen_hook() { # <name> <origin> — a holder reopens and claims the origin
  printf "printf 'status=in_progress\\\\nassignee=review-holder\\\\n' >> %q\n" "$ALPHA/$2" > "$TMP/$1.reopen.sh"
  printf '%s' "$TMP/$1.reopen.sh"
}
mkbead alpha closed al-ua; mkbead alpha open al-ua-1
H=$(reopen_hook ua al-ua)
rc=0; FAKE_RACE_BEFORE_EDGE="$H" run --origin al-ua --successor al-ua-1 --kind folded || rc=$?
eq "$rc" 4 "(au) a reopen and a claim landing just before a repair's edge: exit 4"
eq "$(field alpha status al-ua)/$(field alpha assignee al-ua)" "in_progress/review-holder" "…the reopen and the claim stand"
eq "$(edge alpha al-ua al-ua-1)" "" "…the edge comes back off"
eq "$(field alpha notes al-ua)" "" "…and no note is written"
has "$(cat "$TMP/err")" "under the status and assignee this run read (closed, unassigned)" "…and the refusal names the state it read"
mkbead alpha closed al-ub; mkbead alpha open al-ub-1
H=$(reopen_hook ub al-ub)
rc=0; FAKE_RACE_BEFORE_NOTE="$H" run --origin al-ub --successor al-ub-1 --kind folded || rc=$?
eq "$rc" 4 "(au) one landing between the edge and the note: exit 4"
eq "$(field alpha status al-ub)/$(edge alpha al-ub al-ub-1)/$(field alpha notes al-ub)" "in_progress//" "…the claim stands with no edge and no note"
# A wait a forced close left behind comes back with the rest.
mkbead alpha closed al-uc; mkbead alpha open al-uc-1
printf 'dep.al-uc-1=blocks\n' >> "$ALPHA/al-uc"
H=$(reopen_hook uc al-uc)
rc=0; FAKE_RACE_BEFORE_NOTE="$H" run --origin al-uc --successor al-uc-1 --kind folded || rc=$?
eq "$rc/$(edge alpha al-uc al-uc-1)" "4/blocks" "(au) a repair that loses puts back the wait it replaced"
# The control: a repair nothing raced records both.
mkbead alpha closed al-ud; mkbead alpha open al-ud-1
: > "$TMP/updates.log"
rc=0; FAKE_UPDATE_LOG="$TMP/updates.log" run --origin al-ud --successor al-ud-1 --kind folded || rc=$?
eq "$rc/$(edge alpha al-ud al-ud-1)" "0/supersedes" "(au) a repair nothing raced records the edge"
has "$(field alpha notes al-ud)" "Recorded after the close" "…and the note"
has "$(cat "$TMP/updates.log")" "al-ud --if-status=closed --if-assignee= --append-notes" "…conditional on what it read"
mkbead alpha closed al-ue; mkbead alpha open al-ue-1
printf 'assignee=earlier-holder\n' >> "$ALPHA/al-ue"
: > "$TMP/updates.log"
rc=0; FAKE_UPDATE_LOG="$TMP/updates.log" run --origin al-ue --successor al-ue-1 --kind folded || rc=$?
eq "$rc/$(edge alpha al-ue al-ue-1)" "0/supersedes" "(au) a closed bead keeping an assignee is repaired"
has "$(cat "$TMP/updates.log")" "al-ue --if-status=closed --if-assignee=earlier-holder --append-notes" "…under that same assignee"
# A note the store does not take cannot show the bead stayed closed. Nothing stays
# recorded, and the same call does it again.
mkbead alpha closed al-uf; mkbead alpha open al-uf-1
rc=0; FAKE_BD_NOTE_FAIL=1 run --origin al-uf --successor al-uf-1 --kind folded || rc=$?
eq "$rc/$(edge alpha al-uf al-uf-1)/$(field alpha notes al-uf)" "4//" "(au) a note that does not write: exit 4, no edge and no note"
rc=0; run --origin al-uf --successor al-uf-1 --kind folded || rc=$?
eq "$rc/$(edge alpha al-uf al-uf-1)" "0/supersedes" "…and the same call run again records it"

# --- (av) what comes to wait on a duplicate as it closes moves after the close --
waits_on() { # <name> <waiter> <duplicate> — a hook that gives the waiter the edge
  printf "printf 'dep.%s=blocks\\\\n' >> %q\n" "$3" "$ALPHA/$2" > "$TMP/$1.late.sh"
  printf '%s' "$TMP/$1.late.sh"
}
mkbead alpha open al-va; mkbead alpha open al-va-c; mkbead alpha open al-va-w; mkbead alpha open al-va-e
printf 'dep.al-va=blocks\n' >> "$ALPHA/al-va-e"
H=$(waits_on va al-va-w al-va)
rc=0; FAKE_RACE_BEFORE_CLOSE="$H" run --origin al-va --successor al-va-c --kind duplicate || rc=$?
eq "$rc/$(field alpha status al-va)" "0/closed" "(av) a bead that comes to wait just before the close does not stop it"
eq "$(edge alpha al-va-w al-va-c)" blocks "…and it waits on the canonical once the close has landed"
eq "$(edge alpha al-va-e al-va-c)" blocks "…beside the one the first read moved"
has "$(cat "$TMP/out")" "al-va-w came to wait on al-va as it closed, and wait on al-va-c now" "…and the output names it"
mkbead alpha open al-vb; mkbead alpha open al-vb-c; mkbead alpha open al-vb-w
H=$(waits_on vb al-vb-w al-vb)
rc=0; FAKE_RACE_AFTER_CLOSE="$H" run --origin al-vb --successor al-vb-c --kind duplicate || rc=$?
eq "$rc/$(edge alpha al-vb-w al-vb-c)" "0/blocks" "(av) one whose edge lands just after the close moves too"
# A wait that cannot move is too late to refuse: the close stands, and says so.
mkbead alpha open al-vc; mkbead alpha open al-vc-c; mkbead alpha open al-vc-w
printf 'dep.al-vc-c=related\n' >> "$ALPHA/al-vc-w"
H=$(waits_on vc al-vc-w al-vc)
rc=0; FAKE_RACE_BEFORE_CLOSE="$H" run --origin al-vc --successor al-vc-c --kind duplicate || rc=$?
eq "$rc/$(field alpha status al-vc)/$(edge alpha al-vc al-vc-c)" "4/closed/duplicates" "(av) a late waiter another edge type joins to the canonical: exit 4, the close stands"
eq "$(edge alpha al-vc-w al-vc-c)" related "…and its edge is left as it is"
has "$(cat "$TMP/err")" "al-vc-w by a 'related' edge" "…the WARN names it"
hasnt "$(cat "$TMP/err")" "re-run this close" "…and asks for no re-run, which would move nothing"
has "$(field alpha notes al-vc)" "did not all move to al-vc-c" "…and the bead's note records it"
mkbead alpha open al-vd; mkbead alpha open al-vd-c; mkbead alpha open al-vd-w
H=$(waits_on vd al-vd-w al-vd)
rc=0; FAKE_RACE_BEFORE_CLOSE="$H" FAKE_BD_DEP_ADD_REFUSE_FROM=al-vd-w run --origin al-vd --successor al-vd-c --kind duplicate || rc=$?
eq "$rc/$(field alpha status al-vd)" "4/closed" "(av) a late waiter bd refuses the edge: exit 4, the close stands"
has "$(cat "$TMP/err")" "bd refused al-vd-w a blocks edge onto al-vd-c" "…the WARN names it"
# One that cannot move does not hold back one that can.
mkbead alpha open al-ve; mkbead alpha open al-ve-c; mkbead alpha open al-ve-w; mkbead alpha open al-ve-x
printf 'dep.al-ve-c=related\n' >> "$ALPHA/al-ve-x"
printf "printf 'dep.al-ve=blocks\\\\n' >> %q\nprintf 'dep.al-ve=blocks\\\\n' >> %q\n" "$ALPHA/al-ve-w" "$ALPHA/al-ve-x" > "$TMP/ve.late.sh"
rc=0; FAKE_RACE_BEFORE_CLOSE="$TMP/ve.late.sh" run --origin al-ve --successor al-ve-c --kind duplicate || rc=$?
eq "$rc/$(edge alpha al-ve-w al-ve-c)/$(edge alpha al-ve-x al-ve-c)" "4/blocks/related" "(av) of two late waiters, the one that can move does"
has "$(cat "$TMP/err")" "dep list al-ve --direction=up" "…and the WARN gives the read that lists them"
mkbead alpha open al-vf; mkbead alpha open al-vf-c
rc=0; FAKE_UP_FAIL_AFTER_CLOSE=1 run --origin al-vf --successor al-vf-c --kind duplicate || rc=$?
rm -f "$ALPHA/.up-list-fails"
eq "$rc/$(field alpha status al-vf)" "4/closed" "(av) a second read that does not answer: exit 4, the close stands"
has "$(cat "$TMP/err")" "did not read" "…and the WARN says so"
# Only a duplicate of a canonical yet to deliver reads its waiters again.
mkbead alpha open al-vg; mkbead alpha open al-vg-s; mkbead alpha open al-vg-w
H=$(waits_on vg al-vg-w al-vg)
: > "$TMP/vg.calls"
rc=0; FAKE_RACE_BEFORE_CLOSE="$H" FAKE_CALL_LOG="$TMP/vg.calls" run --origin al-vg --successor al-vg-s --kind re-homed || rc=$?
eq "$rc/$(edge alpha al-vg-w al-vg-s)" "0/" "(av) another kind moves no late wait"
eq "$(grep -c -- '--direction=up' "$TMP/vg.calls" || true)" 0 "…and reads no waiters"
mkbead alpha open al-vh; mkbead alpha closed al-vh-c; mkbead alpha open al-vh-w
H=$(waits_on vh al-vh-w al-vh)
: > "$TMP/vh.calls"
rc=0; FAKE_RACE_BEFORE_CLOSE="$H" FAKE_CALL_LOG="$TMP/vh.calls" run --origin al-vh --successor al-vh-c --kind duplicate || rc=$?
eq "$rc/$(edge alpha al-vh-w al-vh-c)" "0/" "(av) a canonical already delivered moves no late wait"
eq "$(grep -c -- '--direction=up' "$TMP/vh.calls" || true)" 0 "…and reads no waiters"

# --- (am) the retry withdraws its own gates before the close ---------------
hgate() { # <id> <await_id> [<assignee>]: an open human gate in alpha
  mkbead alpha open "$1"
  printf 'issue_type=gate\nawait_type=human\nawait_id=%s\n' "$2" >> "$TMP/rigs/alpha/.beads/$1"
  [ -z "${3:-}" ] || printf 'assignee=%s\n' "$3" >> "$TMP/rigs/alpha/.beads/$1"
}
mkbead alpha open al-retry1
mkbead beta  open bt-retry1
hgate al-g1 pr-dispose-failed.9
hgate al-g1b pr-dispose-failed.9
printf 'dep.al-g1=blocks\ndep.al-g1b=blocks\n' >> "$TMP/rigs/alpha/.beads/al-retry1"
: > "$TMP/resolves.log"
rc=0; FAKE_RESOLVE_LOG="$TMP/resolves.log" run --origin al-retry1 --successor bt-retry1 --kind not-needed --except-key pr-dispose-failed.9 || rc=$?
eq "$rc" 0 "a retry with its own gates open closes"
eq "$(field alpha status al-retry1)" closed "…the origin is closed"
eq "$(field alpha status al-g1)" closed "…its own gate is resolved"
eq "$(field alpha status al-g1b)" closed "…and its twin under the key"
has "$(field alpha reason al-g1)" "Withdrawn by bead-rehome.sh" "the gate's reason names the retry"
case "$(field alpha reason al-g1)" in
    ruled:*|moot:*|benign:*) bad "the gate's reason carries no outcome word (got '$(field alpha reason al-g1)')" ;;
    *) ok "the gate's reason carries no outcome word" ;;
esac
has "$(cat "$TMP/out")" "withdrew the gate al-g1 [pr-dispose-failed.9] on al-retry1" "the withdrawal is reported"
eq "$(grep -c . "$TMP/resolves.log")" 2 "each own gate is resolved once, before the close bd would refuse while they block"
# A close with no --except-key resolves nothing: bd refuses the close a gate blocks.
mkbead alpha open al-retry2
mkbead beta  open bt-retry2
hgate al-g2 pr-dispose-failed.9
printf 'dep.al-g2=blocks\n' >> "$TMP/rigs/alpha/.beads/al-retry2"
rc=0; run --origin al-retry2 --successor bt-retry2 --kind not-needed || rc=$?
eq "$rc" 5 "without --except-key a gate blocking the origin refuses the close"
eq "$(field alpha status al-g2)" open "…and is not resolved"
# The edge's read-back comes before the withdrawal, so another caller's edge stops
# the retry with its gate still asking.
mkbead alpha open al-retry3
mkbead alpha open al-retry3-1
mkbead alpha open al-retry3-2
hgate al-g3 pr-dispose-failed.9
printf 'dep.al-g3=blocks\n' >> "$TMP/rigs/alpha/.beads/al-retry3"
printf '%q ' gc bd --db "$TMP/rigs/alpha/.beads" dep add al-retry3 al-retry3-2 --type supersedes > "$TMP/racer.g3.sh"
rc=0; FAKE_RACE_BEFORE_EDGE="$TMP/racer.g3.sh" run --origin al-retry3 --successor al-retry3-1 --kind not-needed --except-key pr-dispose-failed.9 || rc=$?
eq "$rc" 6 "(as) another caller's edge beside the retry's stops it"
eq "$(field alpha status al-g3)" open "…before its own gate is resolved"
eq "$(field alpha status al-retry3)" open "…and before the close"
eq "$(edge alpha al-retry3 al-retry3-1)" "" "…and its edge comes back off"

# --- (an) anything else that would refuse the close holds it first ----------
mkbead alpha open al-retry3
mkbead beta  open bt-retry3
hgate al-g3 pr-dispose-failed.9
mkbead alpha open al-work3
printf 'dep.al-g3=blocks\ndep.al-work3=blocks\n' >> "$TMP/rigs/alpha/.beads/al-retry3"
BEFORE=$(snap alpha al-retry3)
rc=0; run --origin al-retry3 --successor bt-retry3 --kind not-needed --except-key pr-dispose-failed.9 || rc=$?
eq "$rc" 5 "another live blocker holds the retry"
eq "$(field alpha status al-g3)" open "…the retry's own gate stays open"
eq "$(snap alpha al-retry3)" "$BEFORE" "…and nothing is written to the origin"
has "$(cat "$TMP/err")" "al-work3" "…and the refusal names the blocker"
mkbead alpha open al-retry3c
mkbead beta  open bt-retry3c
hgate al-g3c pr-dispose-failed.9
mkbead alpha closed al-done3c
mkbead alpha pinned al-pin3c
printf 'dep.al-g3c=blocks\ndep.al-done3c=blocks\ndep.al-pin3c=blocks\n' >> "$TMP/rigs/alpha/.beads/al-retry3c"
rc=0; run --origin al-retry3c --successor bt-retry3c --kind not-needed --except-key pr-dispose-failed.9 || rc=$?
eq "$(field alpha status al-g3c)" closed "a closed or pinned blocker beside its own gate does not hold the withdrawal"
mkbead alpha open al-retry4
mkbead beta  open bt-retry4
hgate al-g4 pr-dispose-failed.9 operator
printf 'dep.al-g4=blocks\n' >> "$TMP/rigs/alpha/.beads/al-retry4"
rc=0; run --origin al-retry4 --successor bt-retry4 --kind not-needed --except-key pr-dispose-failed.9 || rc=$?
eq "$rc" 5 "a gate under the key assigned to a person holds the retry"
eq "$(field alpha status al-g4)" open "…and is not resolved"
mkbead alpha open al-retry4k
mkbead beta  open bt-retry4k
hgate al-g4k pr-dispose-failed.9
hgate al-o4k another-question
printf 'dep.al-g4k=blocks\ndep.al-o4k=blocks\n' >> "$TMP/rigs/alpha/.beads/al-retry4k"
rc=0; run --origin al-retry4k --successor bt-retry4k --kind not-needed --except-key pr-dispose-failed.9 || rc=$?
eq "$rc" 5 "a gate under another key holds the retry"
eq "$(field alpha status al-g4k)/$(field alpha status al-o4k)" "open/open" "…and neither gate is resolved"
mkbead alpha open al-retry5
mkbead beta  open bt-retry5
hgate al-g5 pr-dispose-failed.9
printf 'dep.al-g5=blocks\n' >> "$TMP/rigs/alpha/.beads/al-retry5"
mkbead alpha in_progress al-kid5
printf 'parent=al-retry5\n' >> "$TMP/rigs/alpha/.beads/al-kid5"
rc=0; run --origin al-retry5 --successor bt-retry5 --kind not-needed --except-key pr-dispose-failed.9 || rc=$?
eq "$rc" 5 "an open child holds the retry"
eq "$(field alpha status al-g5)" open "…the retry's own gate stays open"
has "$(cat "$TMP/err")" "open child al-kid5" "…and the refusal names the child"
# --check with --except-key reads all of that and writes nothing.
check_held() { # <label> <origin> <text the refusal names> [env assignments...]
  local label="$1" origin="$2" text="$3" before after
  shift 3
  before=$(cat "$TMP/rigs/alpha/.beads/$origin")
  rc=0; env "$@" "$SCRIPT" --origin "$origin" --successor bt-check --kind not-needed --except-key pr-dispose-failed.9 --check >"$TMP/out" 2>"$TMP/err" || rc=$?
  after=$(cat "$TMP/rigs/alpha/.beads/$origin")
  eq "$rc" 1 "--check: $label refuses"
  has "$(cat "$TMP/err")" "$text" "--check: $label is named"
  eq "$after" "$before" "--check: $label writes nothing"
}
mkbead beta open bt-check
mkbead alpha open al-check1
hgate al-cg1 pr-dispose-failed.9
printf 'dep.al-cg1=blocks\n' >> "$TMP/rigs/alpha/.beads/al-check1"
BEFORE=$(snap alpha al-check1)
rc=0; "$SCRIPT" --origin al-check1 --successor bt-check --kind not-needed --except-key pr-dispose-failed.9 --check >"$TMP/out" 2>"$TMP/err" || rc=$?
eq "$rc" 0 "--check: its own gates under the key leave the close eligible"
eq "$(field alpha status al-cg1)" open "--check: …and stay open"
eq "$(snap alpha al-check1)" "$BEFORE" "--check: …and nothing is written"
mkbead alpha open al-check2
hgate al-cg2 another-question
printf 'dep.al-cg2=blocks\n' >> "$TMP/rigs/alpha/.beads/al-check2"
check_held "a gate under another key" al-check2 "al-cg2"
mkbead alpha open al-check3
hgate al-cg3 pr-dispose-failed.9 operator
printf 'dep.al-cg3=blocks\n' >> "$TMP/rigs/alpha/.beads/al-check3"
check_held "a gate a person is assigned" al-check3 "al-cg3"
mkbead alpha open al-check4
mkbead alpha open al-cw4
printf 'dep.al-cw4=blocks\n' >> "$TMP/rigs/alpha/.beads/al-check4"
check_held "another live blocker" al-check4 "al-cw4"
mkbead alpha open al-check5
mkbead alpha in_progress al-ckid5
printf 'parent=al-check5\n' >> "$TMP/rigs/alpha/.beads/al-ckid5"
check_held "an open child" al-check5 "al-ckid5"
mkbead alpha open al-check6
printf 'assignee=someone-else\n' >> "$TMP/rigs/alpha/.beads/al-check6"
check_held "an assignee bd would refuse the close for" al-check6 "someone-else"
mkbead alpha open al-check7
check_held "a blocker read that fails" al-check7 "did not read" FAKE_BD_DEP_LIST_FAIL=1
check_held "a child read that fails" al-check7 "did not read" FAKE_BD_LIST_PARENT_FAIL=1
mkbead alpha open al-check10
: > "$FG_LOG"
check_held "the finalize gate's refusal" al-check10 "held by open human gate" FG_VERDICT=hold
eq "$(cat "$FG_LOG")" "check al-check10 --except-key pr-dispose-failed.9 --as-disposed" "--check: the finalize gate is asked with the key, about the origin as the close will leave it"
# The close drops a wait edge onto its successor, so --check holds nothing on it.
mkbead alpha open al-check8
mkbead alpha open al-succ8
printf 'dep.al-succ8=blocks\n' >> "$TMP/rigs/alpha/.beads/al-check8"
rc=0; "$SCRIPT" --origin al-check8 --successor al-succ8 --kind not-needed --except-key pr-dispose-failed.9 --check >"$TMP/out" 2>"$TMP/err" || rc=$?
eq "$rc" 0 "--check: a wait edge onto the successor holds nothing"
# Without the key, --check judges the evidence alone.
mkbead alpha open al-check9
hgate al-cg9 another-question
printf 'dep.al-cg9=blocks\n' >> "$TMP/rigs/alpha/.beads/al-check9"
rc=0; "$SCRIPT" --origin al-check9 --successor bt-check --kind not-needed --check >"$TMP/out" 2>"$TMP/err" || rc=$?
eq "$rc" 0 "--check: with no --except-key it reads no holds"
# A read that fails proves nothing about what holds the close.
mkbead alpha open al-retry6
mkbead beta  open bt-retry6
hgate al-g6 pr-dispose-failed.9
printf 'dep.al-g6=blocks\n' >> "$TMP/rigs/alpha/.beads/al-retry6"
rc=0; FAKE_BD_DEP_LIST_FAIL=1 run --origin al-retry6 --successor bt-retry6 --kind not-needed --except-key pr-dispose-failed.9 || rc=$?
eq "$rc" 5 "an unreadable blocker list holds the retry"
eq "$(field alpha status al-g6)" open "…and resolves nothing"
rc=0; FAKE_BD_LIST_PARENT_FAIL=1 run --origin al-retry6 --successor bt-retry6 --kind not-needed --except-key pr-dispose-failed.9 || rc=$?
eq "$rc" 5 "an unreadable child list holds the retry"
eq "$(field alpha status al-g6)/$(field alpha status al-retry6)" "open/open" "…and resolves and closes nothing"
# The origin's own row that does not read holds everything.
mkbead alpha open al-retry6r
mkbead beta  open bt-retry6r
BEFORE=$(snap alpha al-retry6r)
rc=0; FAKE_BD_LIST_ID_FAIL=1 run --origin al-retry6r --successor bt-retry6r --kind not-needed || rc=$?
eq "$rc" 3 "a row that does not read is refused as unknown"
eq "$(snap alpha al-retry6r)" "$BEFORE" "…and nothing is written"

# --- (ao) a gate the store will not resolve, and a run stopped part way ------
mkbead alpha open al-retry7
mkbead beta  open bt-retry7
hgate al-g7 pr-dispose-failed.9
printf 'dep.al-g7=blocks\n' >> "$TMP/rigs/alpha/.beads/al-retry7"
rc=0; FAKE_BD_GATE_RESOLVE_REFUSE=1 run --origin al-retry7 --successor bt-retry7 --kind not-needed --except-key pr-dispose-failed.9 || rc=$?
eq "$rc" 5 "a gate the store will not resolve holds the close"
eq "$(field alpha status al-retry7)" open "…the origin stays open"
has "$(cat "$TMP/err")" "the store refused the resolve of the gate al-g7" "…and the refusal names the gate"
mkbead alpha open al-retry8
mkbead beta  open bt-retry8
hgate al-g8 pr-dispose-failed.9
printf 'dep.al-g8=blocks\n' >> "$TMP/rigs/alpha/.beads/al-retry8"
rc=0; FAKE_BD_CLOSE_REFUSE=1 run --origin al-retry8 --successor bt-retry8 --kind not-needed --except-key pr-dispose-failed.9 || rc=$?
eq "$rc" 5 "a close refused after the withdrawal exits 5"
eq "$(field alpha status al-g8)/$(field alpha status al-retry8)" "closed/open" "…with the gate withdrawn and the origin open"
rc=0; run --origin al-retry8 --successor bt-retry8 --kind not-needed --except-key pr-dispose-failed.9 || rc=$?
eq "$rc" 0 "the next run completes the close"
eq "$(field alpha status al-retry8)" closed "…and the origin is closed"

# --- (ap) the dry run names the withdrawal ----------------------------------
mkbead alpha open al-retry9
mkbead beta  open bt-retry9
rc=0; run --origin al-retry9 --successor bt-retry9 --kind not-needed --except-key pr-dispose-failed.9 --dry-run || rc=$?
has "$(cat "$TMP/out")" "gates:     resolve each open human gate under [pr-dispose-failed.9]" "the dry run names the gates it would withdraw"
rc=0; run --origin al-retry9 --successor bt-retry9 --kind not-needed --dry-run || rc=$?
has "$(cat "$TMP/out")" "gates:     none (no --except-key)" "…and none without --except-key"

# --- (aq) the close's own guards hold the retry before anything is resolved --
export FAKE_BD_ENFORCE_CLOSE_GUARDS=1
mkbead alpha open al-guard1
mkbead beta  open bt-guard1
printf 'assignee=someone-else\n' >> "$TMP/rigs/alpha/.beads/al-guard1"
hgate al-gg1 pr-dispose-failed.9
printf 'dep.al-gg1=blocks\n' >> "$TMP/rigs/alpha/.beads/al-guard1"
: > "$TMP/resolves.log"
rc=0; FAKE_RESOLVE_LOG="$TMP/resolves.log" run --origin al-guard1 --successor bt-guard1 --kind not-needed --except-key pr-dispose-failed.9 || rc=$?
eq "$rc" 5 "an open origin assigned to someone else holds the retry"
eq "$(field alpha status al-gg1)" open "…its own gate stays open"
eq "$(grep -c . "$TMP/resolves.log")" 0 "…with no resolve attempted"
eq "$(field alpha status al-guard1)" open "…the origin stays open"
has "$(cat "$TMP/err")" "assigned to someone-else" "…and the refusal names the assignee"
has "$(cat "$TMP/err")" "runs as $BEADS_ACTOR" "…and the actor the close runs as"
mkbead alpha in_progress al-guard2
mkbead beta  open bt-guard2
printf 'assignee=test__rehome-session-name\n' >> "$TMP/rigs/alpha/.beads/al-guard2"
hgate al-gg2 pr-dispose-failed.9
printf 'dep.al-gg2=blocks\n' >> "$TMP/rigs/alpha/.beads/al-guard2"
rc=0; GC_SESSION_NAME=test__rehome-session-name run --origin al-guard2 --successor bt-guard2 --kind not-needed --except-key pr-dispose-failed.9 || rc=$?
eq "$rc" 5 "an origin this session holds under a name other than the actor holds the retry"
eq "$(field alpha status al-gg2)/$(field alpha status al-guard2)" "open/in_progress" "…and resolves and closes nothing"
mkbead alpha pinned al-guard3
mkbead beta  open bt-guard3
hgate al-gg3 pr-dispose-failed.9
printf 'dep.al-gg3=blocks\n' >> "$TMP/rigs/alpha/.beads/al-guard3"
rc=0; run --origin al-guard3 --successor bt-guard3 --kind not-needed --except-key pr-dispose-failed.9 || rc=$?
eq "$rc" 5 "a pinned origin holds the retry"
eq "$(field alpha status al-gg3)" open "…its own gate stays open"
has "$(cat "$TMP/err")" "pinned" "…and the refusal says why"
mkbead alpha open al-guard4
mkbead beta  open bt-guard4
printf 'is_template=true\n' >> "$TMP/rigs/alpha/.beads/al-guard4"
hgate al-gg4 pr-dispose-failed.9
printf 'dep.al-gg4=blocks\n' >> "$TMP/rigs/alpha/.beads/al-guard4"
rc=0; run --origin al-guard4 --successor bt-guard4 --kind not-needed --except-key pr-dispose-failed.9 || rc=$?
eq "$rc" 5 "a template holds the retry"
eq "$(field alpha status al-gg4)" open "…its own gate stays open"
has "$(cat "$TMP/err")" "template" "…and the refusal says why"
mkbead alpha open al-guard5
mkbead beta  open bt-guard5
printf 'assignee=%s\n' "$BEADS_ACTOR" >> "$TMP/rigs/alpha/.beads/al-guard5"
hgate al-gg5 pr-dispose-failed.9
printf 'dep.al-gg5=blocks\n' >> "$TMP/rigs/alpha/.beads/al-guard5"
rc=0; run --origin al-guard5 --successor bt-guard5 --kind not-needed --except-key pr-dispose-failed.9 || rc=$?
eq "$rc" 0 "an origin assigned to exactly the actor closes"
eq "$(field alpha status al-gg5)/$(field alpha status al-guard5)" "closed/closed" "…its own gate withdrawn first"
unset FAKE_BD_ENFORCE_CLOSE_GUARDS

# --- (aw) with no identity of its own the writer uses bd's default actor -------
export FAKE_BD_ENFORCE_CLOSE_GUARDS=1
no_identity() { env -u BEADS_ACTOR -u GC_SESSION_NAME -u GC_AGENT -u GC_SESSION_ID -u GC_ALIAS "$@" >"$TMP/out" 2>"$TMP/err"; }
mkbead alpha open al-wa; mkbead alpha open al-wa-1
printf 'assignee=Operator Name\n' >> "$ALPHA/al-wa"
: > "$FAKE_ACTOR_LOG"
rc=0; no_identity FAKE_BD_DEFAULT_ACTOR="Operator Name" "$SCRIPT" --origin al-wa --successor al-wa-1 --kind folded || rc=$?
eq "$rc/$(field alpha status al-wa)" "0/closed" "(aw) an origin assigned to the actor bd defaults to closes"
eq "$(tail -1 "$FAKE_ACTOR_LOG")" "Operator Name" "…and the writes run as that actor"
mkbead alpha open al-wb; mkbead alpha open al-wb-1
printf 'assignee=someone-else\n' >> "$ALPHA/al-wb"
BEFORE=$(snap alpha al-wb)
rc=0; no_identity FAKE_BD_DEFAULT_ACTOR="Operator Name" "$SCRIPT" --origin al-wb --successor al-wb-1 --kind folded || rc=$?
eq "$rc/$(snap alpha al-wb)" "5/$BEFORE" "(aw) an origin assigned to anyone else is refused and nothing is written"
has "$(cat "$TMP/err")" "assigned to someone-else" "…naming the assignee"
has "$(cat "$TMP/err")" "runs as Operator Name" "…and the actor it read"
mkbead alpha open al-wc; mkbead alpha open al-wc-1
printf 'assignee=Operator Name\n' >> "$ALPHA/al-wc"
BEFORE=$(snap alpha al-wc)
rc=0; no_identity "$SCRIPT" --origin al-wc --successor al-wc-1 --kind folded || rc=$?
eq "$rc/$(snap alpha al-wc)" "5/$BEFORE" "(aw) a preview that does not read holds an assigned origin"
has "$(cat "$TMP/err")" "runs as the actor bd defaults to" "…and says which actor it could not name"
mkbead alpha in_progress al-wd; mkbead alpha open al-wd-1
printf 'assignee=Operator Name\n' >> "$ALPHA/al-wd"
rc=0; no_identity FAKE_BD_DEFAULT_ACTOR="Operator Name" "$SCRIPT" --origin al-wd --successor al-wd-1 --kind folded || rc=$?
eq "$rc/$(field alpha status al-wd)" "0/closed" "(aw) a bead held in_progress under that actor is its own to close"
mkbead alpha in_progress al-we; mkbead alpha open al-we-1
printf 'assignee=someone-else\n' >> "$ALPHA/al-we"
rc=0; no_identity FAKE_BD_DEFAULT_ACTOR="Operator Name" "$SCRIPT" --origin al-we --successor al-we-1 --kind folded || rc=$?
eq "$rc" 7 "(aw) one held in_progress under anyone else is not"
# It asks only when an assignee has to be compared.
mkbead alpha open al-wf; mkbead alpha open al-wf-1
: > "$TMP/wf.calls"; : > "$FAKE_ACTOR_LOG"
rc=0; no_identity FAKE_CALL_LOG="$TMP/wf.calls" "$SCRIPT" --origin al-wf --successor al-wf-1 --kind folded || rc=$?
eq "$rc/$(grep -c '^create' "$TMP/wf.calls" || true)" "0/0" "(aw) an unassigned origin needs no preview"
eq "$(grep -c . "$FAKE_ACTOR_LOG" || true)" 0 "…and its writes leave the actor to bd"
mkbead alpha open al-wg; mkbead alpha open al-wg-1
printf 'assignee=%s\n' "$BEADS_ACTOR" >> "$ALPHA/al-wg"
: > "$TMP/wg.calls"
rc=0; FAKE_CALL_LOG="$TMP/wg.calls" run --origin al-wg --successor al-wg-1 --kind folded || rc=$?
eq "$rc/$(grep -c '^create' "$TMP/wg.calls" || true)" "0/0" "(aw) a caller with an identity of its own needs no preview"
unset FAKE_BD_ENFORCE_CLOSE_GUARDS

echo "---"
echo "bead-rehome.test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
