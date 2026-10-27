#!/usr/bin/env bash
# Hermetic test for bead-rehome.sh.
#
# Fakes `gc rig list --json` and `bd` (a file-per-bead ledger under each fake
# rig's .beads/) on PATH. No dependency on the live city, Dolt, or the network.
#
# The invariants under test are the ones the incident turned on:
#   (a) a re-home stamps the forward pointer AND closes with a populated reason
#       naming kind + successor + store — never a bare `[Closed]`;
#   (b) the successor must exist in the named store, or nothing is written at
#       all (a pointer to a missing bead is worse than no pointer);
#   (c) if the pointer does not read back, the origin is NOT closed — an open
#       pointed bead is visible, an unpointed closed one is the defect;
#   (d) a refused close still leaves the pointer recorded;
#   (e) an existing disposition naming a different successor is never
#       overwritten;
#   (f) each kind renders its own reason phrasing;
#   (g) an id prefix no rig claims is refused, not guessed;
#   (h) a self-pointer is refused;
#   (i) --dry-run writes nothing;
#   (j) an already-closed bead is REPAIRED (pointer + note), not refused;
#   (k) that repair is idempotent;
#   (l) a pointer the live sweep half-wrote (`gc.superseded_by`, no store) is
#       completed rather than read as a conflict;
#   (m) the legacy bare `superseded_by` still counts as a prior disposition;
#   (n) a `blocks` edge naming the SUCCESSOR is dropped, so the wait a converse
#       sitting wired beside the ruling does not refuse the ruling's own close;
#   (o) any OTHER blocker is left alone and its refusal still stands;
#   (p) every repair command the script hands back runs through `gc bd`;
#   (q) the successor is required under EVERY kind, `not-needed` included —
#       the kind where nothing carries the work forward is where dropping the
#       pointer looks reasonable, and it is exactly as unreadable there;
#   (r) a task_kind=visit origin records gc.work_outcome=no-op for the
#       work-record gate the close runs, and no gc.outcome;
#   (s) a non-visit origin records NO gc.outcome either;
#   (t) an outcome the visit already carries is left as it was, while
#       gc.work_outcome=no-op still lands before the close;
#   (u) an already-closed visit missing its work outcome is repaired with it;
#   (x) an open human gate on the origin holds the close at the finalize gate;
#   (y) --except-key reaches that gate, and nothing is excepted without it;
#   (z) an already-closed visit that records an outcome is repaired with
#       gc.work_outcome=no-op, and its outcome is left as it was;
#   (aa) a store that refuses gc.work_outcome still re-homes and closes the
#       visit — the key is a write of its own, never a precondition;
#   (ab) a dropped gc.work_outcome is read back and written again before the
#       close;
#   (ac) a work outcome the visit already records is never written over;
#   (ad) once the close reads back, the branch the bead names in metadata.branch
#       goes to branch-end.sh with the bead's rig and id, once, after the close;
#   (ae) a branch-end that cannot end the branch leaves the close standing: exit
#       0, the bead closed and pointed, and a WARN naming the branch and the
#       command that ends it;
#   (af) a branch kept for a live owner is reported, not warned about;
#   (ag) no branch-end runs when the close is refused or held, when the bead
#       names no branch, or on a dry run, which names the branch in its plan;
#   (ah) the repair path ends an already-closed bead's branch too;
#   (ai) a close that does not read back closed leaves the branch, with a WARN;
#   (aj) end to end, through the real branch-end.sh and a bare origin: a retire
#       ends the branch with its tip pinned, and a delete origin refuses leaves
#       the close standing;
#   (ak) the command a WARN names, pasted, hands branch-end a branch name that
#       carries shell metacharacters as one argument and runs nothing it spells;
#   (al) the stamp is conditional on the status
#       and assignee the gates read, so a claim that lands between that read
#       and the stamp refuses it (exit 4): nothing is stamped or closed and the
#       claim stands, and a reopen does the same on the repair path;
#   (am) the retry withdraws its own gates before the close: each open human
#       gate under the --except-key key that blocks the origin and no person is
#       assigned is resolved with a reason that names the retry and carries no
#       outcome word, and then the origin closes;
#   (an) anything else that would refuse the close (another live blocker, a
#       gate under the key a person is assigned, an open child) holds it before
#       any gate is resolved, and so does a blocker or child read that fails;
#   (ao) a gate that does not resolve holds the close, and a run stopped after
#       the withdrawal is completed by the next one;
#   (ap) the dry run names the withdrawal it would make;
#   (aq) the template, the pin and the assignee an unforced close refuses hold
#       the retry before any gate is resolved: an origin no one is assigned,
#       or one assigned to exactly the actor the close runs as, goes ahead,
#       and one assigned to anyone else, under any other name this session
#       carries included, keeps its gates open and closes nothing.
# The evidence gates this writer enforces for every caller:
#   (gate-a) EVERY kind — no close over a review, step, or workflow bead;
#   (gate-held) EVERY kind — no close over a bead another session holds
#       in_progress, while a bead this session holds is fine;
#   (gate-b) fixed-upstream|duplicate — the successor is in the same store and
#       is closed or shipped, and the origin did no work (no-op stamp, or no
#       work-product key, so unlanded work is refused), the no-op stamp
#       overriding a twin's leftover branch; a judgment kind is not held to it,
#       and an origin carrying the operator's pre-recorded PR-close disposition
#       for that kind and successor satisfies it;
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

# A bead is a file of `key=value` lines: status, reason, m.<key> metadata, and
# `dep.<blocker>=<type>` for each edge the bead carries as the BLOCKED side —
# which is the side `bd show` reports in `.dependencies[]` and the side
# `bd close` consults. A gate also carries issue_type, await_type and await_id
# lines, a bead with a person on it an assignee line, and a child a parent line.
mkbead() { printf 'status=%s\n' "${2:-open}" > "$TMP/rigs/$1/.beads/$3"; }
field()  { sed -n "s/^$2=//p" "$TMP/rigs/$1/.beads/$3" 2>/dev/null | tail -1; }

{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
# Only the surface bead-rehome.sh touches.
case "$1 $2" in
  "rig list") cat "$FAKE_RIGS_JSON" ;;
  "bd "*)    shift; VIA_GC_BD=1 exec "$(dirname "$0")/bd" "$@" ;;
  *) exit 1 ;;
esac
GC

{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/bd" <<'BD'
# The check reaches the store through `gc bd`; a direct `bd` is the regression
# this guard catches, so only the gc stub above may run this one.
[ -n "${VIA_GC_BD:-}" ] || { echo "stub bd: called directly, not through gc bd" >&2; exit 127; }
# Fake bd: --db <path>/.beads [--actor X] <show|update|close> <id> ...
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

# `bd dep <verb> <id> <depends-on-id>` puts the verb where every other
# subcommand puts the bead id, so it is parsed on its own.
if [ "$sub" = "dep" ]; then
  verb="${1:-}"; shift || true
  id="${1:-}"; shift || true
  # `bd dep list <id> --type blocks --json`: one row per `blocks` edge the bead
  # carries, the far bead's fields with the edge's dependency_type, a field
  # whose value is empty left out as real bd leaves it out.
  # FAKE_BD_DEP_LIST_FAIL makes that read fail.
  if [ "$verb" = "list" ]; then
    [ -z "${FAKE_BD_DEP_LIST_FAIL:-}" ] || { echo "Error: simulated dep list failure" >&2; exit 1; }
    f="$DB/$id"
    [ -f "$f" ] || { printf '{"error":"no issues found matching the provided IDs","schema_version":1}\n'; exit 1; }
    rows='[]'
    for b in $(sed -n 's/^dep\.\([^=]*\)=blocks$/\1/p' "$f" | sort -u); do
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
    done
    printf '%s\n' "$rows"
    exit 0
  fi
  other="${1:-}"; shift || true
  f="$DB/$id"
  [ -f "$f" ] || { printf '{"error":"no issues found matching the provided IDs","schema_version":1}\n'; exit 1; }
  case "$verb" in
    add)    printf 'dep.%s=blocks\n' "$other" >> "$f" ;;
    # Real `bd dep remove` prints ✓ and exits 0 for an edge that never existed,
    # so a stub that failed there would let a read-back-free caller pass.
    # FAKE_BD_DEP_REMOVE_NOOP keeps that success report over an edge that
    # survives — the case the read-back guard exists for.
    remove) if [ -z "${FAKE_BD_DEP_REMOVE_NOOP:-}" ]; then
              { grep -v "^dep\.$other=" "$f" || true; } > "$f.tmp"; mv "$f.tmp" "$f"
            fi
            echo "✓ removed dependency: $id -> $other" ;;
    *)      exit 1 ;;
  esac
  exit 0
fi

# The status contract and the live listing: the two reads branch-end.sh makes
# besides show, for the end-to-end case.
if [ "$sub" = "statuses" ]; then
  printf '%s\n' '{"built_in_statuses":[{"name":"open","category":"active"},{"name":"in_progress","category":"wip"},{"name":"closed","category":"done"}]}'
  exit 0
fi
if [ "$sub" = "list" ]; then
  # --metadata-field is bd's: split at the first `=`, every pair must match.
  # --parent lists the beads whose parent line names it; with no --status it
  # leaves out the closed and pinned ones, as bd does.
  # FAKE_BD_LIST_PARENT_FAIL makes a --parent read fail.
  st=""; mf='[]'; parent=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --status) st="$2"; shift 2 ;;
      --status=*) st="${1#--status=}"; shift ;;
      --parent) parent="$2"; shift 2 ;;
      --metadata-field)
        mf=$(jq -cn --argjson m "$mf" --arg k "${2%%=*}" --arg v "${2#*=}" '$m + [{k: $k, v: $v}]')
        shift 2 ;;
      *) shift ;;
    esac
  done
  if [ -n "$parent" ] && [ -n "${FAKE_BD_LIST_PARENT_FAIL:-}" ]; then
    echo "Error: simulated list failure" >&2; exit 1
  fi
  rows='[]'
  for bf in "$DB"/*; do
    [ -f "$bf" ] || continue
    bs=$(sed -n 's/^status=//p' "$bf" | tail -1)
    if [ -n "$parent" ]; then
      [ "$(sed -n 's/^parent=//p' "$bf" | tail -1)" = "$parent" ] || continue
      if [ -z "$st" ]; then
        case "$bs" in closed|pinned) continue ;; esac
      else
        case ",$st," in *",$bs,"*) ;; *) continue ;; esac
      fi
    else
      case ",$st," in *",$bs,"*) ;; *) continue ;; esac
    fi
    lines=$(sed -n 's/^m\.//p' "$bf")
    meta='{}'
    [ -z "$lines" ] || meta=$(printf '%s' "$lines" | jq -R -s 'split("\n") | map(select(length > 0))
      | map(split("=") | {key: .[0], value: (.[1:] | join("="))}) | from_entries')
    rows=$(jq -nc --argjson r "$rows" --arg id "${bf##*/}" --arg st "$bs" --argjson m "$meta" \
      '$r + [{id: $id, status: $st, metadata: $m}]')
  done
  printf '%s\n' "$rows" | jq -c --argjson mf "$mf" \
    '[.[] | select(. as $row | all($mf[]; $row.metadata[.k] as $x | $x != null and ($x | tostring) == .v))]'
  exit 0
fi

# `bd gate resolve <id> --reason <r>` closes the gate with that reason. On a
# gate already closed it changes nothing and still reports success, as bd does.
# FAKE_BD_GATE_RESOLVE_NOOP reports a resolve that never persisted.
if [ "$sub" = "gate" ]; then
  verb="${1:-}"; shift || true
  id="${1:-}"; shift || true
  f="$DB/$id"
  [ "$verb" = "resolve" ] && [ -f "$f" ] || exit 1
  [ -z "${FAKE_RESOLVE_LOG:-}" ] || printf '%s %s\n' "$id" "$*" >> "$FAKE_RESOLVE_LOG"
  [ -z "${FAKE_BD_GATE_RESOLVE_NOOP:-}" ] || { echo "✓ Gate resolved: $id"; exit 0; }
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

meta_json() {
  local lines
  lines=$(sed -n 's/^m\.//p' "$f" 2>/dev/null || true)
  if [ -z "$lines" ]; then printf '{}'; return; fi
  printf '%s' "$lines" | jq -R -s 'split("\n") | map(select(length > 0))
    | map(split("=") | {key: .[0], value: (.[1:] | join("="))}) | from_entries'
}

deps_json() {
  local lines
  lines=$(sed -n 's/^dep\.//p' "$f" 2>/dev/null || true)
  if [ -z "$lines" ]; then printf '[]'; return; fi
  printf '%s' "$lines" | jq -R -s 'split("\n") | map(select(length > 0))
    | map(split("=") | {id: .[0], dependency_type: (.[1:] | join("="))})'
}

# The blockers still holding this bead, by the same rule real bd applies: an
# edge counts unless the bead it names is closed.
open_blockers() {
  local b bf st out=""
  for b in $(sed -n 's/^dep\.\([^=]*\)=blocks$/\1/p' "$f" 2>/dev/null | sort -u); do
    st=""; bf="$DB/$b"
    [ -f "$bf" ] && st=$(sed -n 's/^status=//p' "$bf" | tail -1)
    [ "$st" = "closed" ] || out="$out $b"
  done
  printf '%s' "${out# }"
}

case "$sub" in
  show)
    as="$(sed -n 's/^assignee=//p' "$f" | tail -1)"
    jq -n --arg id "$id" --arg st "$(sed -n 's/^status=//p' "$f" | tail -1)" \
          --arg as "$as" \
          --arg tpl "$(sed -n 's/^is_template=//p' "$f" | tail -1)" \
          --arg notes "$(sed -n 's/^notes=//p' "$f" | tr '\n' ' ')" \
          --argjson meta "$(meta_json)" \
          --argjson deps "$(deps_json)" \
          '[{id: $id, status: $st, assignee: (if $as == "" then null else $as end), notes: $notes, metadata: $meta, dependencies: $deps}
            | if $tpl == "true" then .is_template = true else . end]'
    ;;
  update)
    # FAKE_BD_REFUSE_WORK_OUTCOME refuses any update naming gc.work_outcome,
    # writing nothing: the store or gate that rejects the key.
    if [ -n "${FAKE_BD_REFUSE_WORK_OUTCOME:-}" ]; then
      case " $* " in *" gc.work_outcome="*) echo "refused: gc.work_outcome" >&2; exit 1 ;; esac
    fi
    # FAKE_UPDATE_LOG, when set, gets each update's bead id and arguments.
    [ -z "${FAKE_UPDATE_LOG:-}" ] || printf '%s %s\n' "$id" "$*" >> "$FAKE_UPDATE_LOG"
    # FAKE_BD_CLAIM_BEFORE_STAMP="<status> <assignee>" lands another actor's
    # write on the bead just before the first update that stamps its
    # gc.superseded_by is answered: a claim, an assignment or a status change
    # made after the caller read the bead.
    if [ -n "${FAKE_BD_CLAIM_BEFORE_STAMP:-}" ] && [ ! -e "$DB/.claimed-before-stamp.$id" ]; then
      case " $* " in
        *" gc.superseded_by="*)
          : > "$DB/.claimed-before-stamp.$id"
          printf 'status=%s\nassignee=%s\n' "${FAKE_BD_CLAIM_BEFORE_STAMP%% *}" "${FAKE_BD_CLAIM_BEFORE_STAMP#* }" >> "$f" ;;
      esac
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
    cur_st="$(sed -n 's/^status=//p' "$f" | tail -1)"
    cur_as="$(sed -n 's/^assignee=//p' "$f" | tail -1)"
    if { [ "$if_st" != "-" ] && [ "$if_st" != "$cur_st" ]; } || { [ "$if_as" != "-" ] && [ "$if_as" != "$cur_as" ]; }; then
      echo "Error: precondition failed for $id: status/assignee changed" >&2
      exit 13
    fi
    while [ $# -gt 0 ]; do
      case "$1" in
        --set-metadata)
          # FAKE_BD_DROP_META simulates a write that reports success and does
          # not persist — the case the read-back guard exists for.
          # FAKE_BD_DROP_WORK_OUTCOME_ONCE drops the first gc.work_outcome key
          # an update carries, landing its other keys; later ones land.
          drop=""
          [ -z "${FAKE_BD_DROP_META:-}" ] || drop=1
          case "$2" in gc.work_outcome=*)
            if [ -n "${FAKE_BD_DROP_WORK_OUTCOME_ONCE:-}" ] && [ ! -e "$DB/.work-dropped" ]; then
              : > "$DB/.work-dropped"; drop=1
            fi ;;
          esac
          [ -n "$drop" ] || printf 'm.%s\n' "$2" >> "$f"
          shift 2 ;;
        --append-notes)
          printf 'notes=%s\n' "$2" >> "$f"; shift 2 ;;
        *) shift ;;
      esac
    done
    ;;
  close)
    if [ -n "${FAKE_BD_CLOSE_REFUSE:-}" ]; then
      echo "cannot close issue assigned to other-agent (actor: someone-else)" >&2
      exit 1
    fi
    # FAKE_BD_CLOSE_NOOP reports a close that never persisted.
    [ -z "${FAKE_BD_CLOSE_NOOP:-}" ] || exit 0
    # FAKE_BD_ENFORCE_CLOSE_GUARDS: bd's own close guards, which refuse an
    # unforced close of a template, of a pinned bead, and of a bead assigned to
    # anyone but the --actor the close is given.
    if [ -n "${FAKE_BD_ENFORCE_CLOSE_GUARDS:-}" ]; then
      [ "$(sed -n 's/^is_template=//p' "$f" | tail -1)" != "true" ] \
        || { echo "Error: cannot close template $id" >&2; exit 1; }
      [ "$(sed -n 's/^status=//p' "$f" | tail -1)" != "pinned" ] \
        || { echo "Error: cannot close pinned issue $id (use --force to override)" >&2; exit 1; }
      cas="$(sed -n 's/^assignee=//p' "$f" | tail -1)"
      [ -z "$cas" ] || [ "$cas" = "$ACTOR_ARG" ] \
        || { echo "cannot close $id: assignee is \"$cas\", actor is \"$ACTOR_ARG\"; reclaim or use --force to override" >&2; exit 1; }
    fi
    # A stub that closes a blocked bead would report a green suite for the bug
    # in case (n) below: the whole defect is that real bd refuses here.
    BLOCKED=$(open_blockers)
    if [ -n "$BLOCKED" ]; then
      echo "cannot close blocked issue: $id is blocked by [${BLOCKED// /, }] (use --force to override)" >&2
      exit 1
    fi
    for cf in "$DB"/*; do
      [ -f "$cf" ] && [ "$(sed -n 's/^parent=//p' "$cf" | tail -1)" = "$id" ] || continue
      case "$(sed -n 's/^status=//p' "$cf" | tail -1)" in closed|pinned) ;; *)
        echo "cannot close $id: it has open children (use --force to override)" >&2; exit 1 ;; esac
    done
    reason=""
    while [ $# -gt 0 ]; do
      case "$1" in --reason) reason="$2"; shift 2 ;; *) shift ;; esac
    done
    printf 'status=closed\nreason=%s\n' "$reason" >> "$f"
    ;;
  *) exit 1 ;;
esac
BD

chmod +x "$TMP/bin/gc" "$TMP/bin/bd"
export PATH="$TMP/bin:$PATH"
export FAKE_RIGS_JSON="$TMP/rigs.json"
export FAKE_ACTOR_LOG="$TMP/actors.log"
: > "$FAKE_ACTOR_LOG"
export BEADS_ACTOR="test__rehome-lx-0000"

# The finalize gate is a sibling bead-rehome forks before the close. Stub it so
# this suite tests the WIRING (a refusal holds the close, leaving an open pointed
# bead) without a live gate probe — the gate's own logic is covered by
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

# --- (a) happy path: pointer + populated reason + back-pointer --------------
mkbead alpha open al-origin1
mkbead beta  open bt-succ1
rc=0; run --origin al-origin1 --successor bt-succ1 --kind re-homed --note "operator ruling su-a3ny" || rc=$?
eq "$rc" 0 "re-home succeeds"
eq "$(field alpha status al-origin1)" closed "origin is closed"
eq "$(field alpha m.gc.superseded_by al-origin1)" bt-succ1 "forward pointer names the successor"
eq "$(field alpha m.gc.superseded_by_store al-origin1)" rig:beta "forward pointer names the successor's store"
REASON=$(field alpha reason al-origin1)
has "$REASON" "re-homed to bt-succ1 in rig:beta" "close reason names kind, successor and store"
has "$REASON" "operator ruling su-a3ny" "close reason carries the note"
eq "$(field beta m.gc.supersedes bt-succ1)" al-origin1 "back-pointer names the origin"
eq "$(field beta m.gc.supersedes_store bt-succ1)" rig:alpha "back-pointer names the origin's store"
has "$(cat "$TMP/out")" "events" "output points at the events table for attribution"
has "$(cat "$FAKE_ACTOR_LOG")" "test__rehome-lx-0000" "the actor is passed through for the audit trail"

# --- (x) an open human gate on the origin holds the close (finalize gate) ----
# The gate refuses while a human gate blocks the origin. bead-rehome stamps the
# successor pointer, then leaves the bead OPEN — the same shape a refused close
# leaves — so the disposition stays legible and the gate can be cleared first.
mkbead alpha open al-vhold
mkbead beta  open bt-vsucc
rc=0; FG_VERDICT=hold run --origin al-vhold --successor bt-vsucc --kind re-homed --note "ruling" || rc=$?
eq "$rc" 5 "an open human gate holds the close (exit 5)"
eq "$(field alpha status al-vhold)" open "…the origin stays OPEN under the hold"
eq "$(field alpha m.gc.superseded_by al-vhold)" bt-vsucc "…the pointer is still stamped, so the disposition is findable"
has "$(cat "$TMP/err")" "the close is held" "…stderr says the close is held"
has "$(cat "$TMP/err")" "held by open human gate" "…and carries the gate's reason"

# --- (y) --except-key reaches the finalize gate, and only when given -------
# The caller's own reports of an earlier refused close ask for this retry, so
# their situation key is named to the gate, which owns what an exception may
# pass.
mkbead alpha open al-except
mkbead beta  open bt-except
: > "$FG_LOG"
rc=0; run --origin al-except --successor bt-except --kind not-needed --except-key pr-dispose-failed.7 || rc=$?
eq "$rc" 0 "a close naming an excepted key lands when the gate passes"
eq "$(cat "$FG_LOG")" "check al-except --except-key pr-dispose-failed.7" "the gate is asked with the caller's excepted key"
mkbead alpha open al-noexcept
mkbead beta  open bt-noexcept
: > "$FG_LOG"
rc=0; run --origin al-noexcept --successor bt-noexcept --kind not-needed || rc=$?
eq "$(cat "$FG_LOG")" "check al-noexcept" "without the flag the gate is asked with no exception"

# --- (b) missing successor: nothing written at all --------------------------
mkbead alpha open al-origin2
rc=0; run --origin al-origin2 --successor bt-ghost --kind folded || rc=$?
eq "$rc" 3 "a successor that does not exist is refused"
eq "$(field alpha status al-origin2)" open "origin stays open"
eq "$(field alpha m.gc.superseded_by al-origin2)" "" "no pointer is written to a missing bead"

# --- (c) pointer does not read back: origin must NOT be closed -------------
mkbead alpha open al-origin3
mkbead beta  open bt-succ3
rc=0; FAKE_BD_DROP_META=1 run --origin al-origin3 --successor bt-succ3 --kind re-homed || rc=$?
eq "$rc" 4 "a pointer that does not read back refuses the close"
eq "$(field alpha status al-origin3)" open "origin stays OPEN when the pointer did not stick"
has "$(cat "$TMP/err")" "NOT closing" "the refusal says the close was skipped"

# --- (d) close refused: the pointer is still recorded ----------------------
# A judgment kind: its close reaches `bd close` (the evidence kinds are gated
# earlier and never would), which is where the refusal under test happens.
mkbead alpha open al-origin4
mkbead beta  open bt-succ4
rc=0; FAKE_BD_CLOSE_REFUSE=1 run --origin al-origin4 --successor bt-succ4 --kind folded || rc=$?
eq "$rc" 5 "a refused close exits non-zero"
eq "$(field alpha m.gc.superseded_by al-origin4)" bt-succ4 "the pointer survives a refused close"
eq "$(field alpha status al-origin4)" open "the bead is left open, pointed and visible"
has "$(cat "$TMP/err")" "gc bd --db $TMP/rigs/alpha/.beads close al-origin4 --reason" \
   "the refusal's finishing command runs through gc bd, against the origin's store"

# --- (e) a different prior disposition is never overwritten ---------------
mkbead alpha open al-origin5
printf 'm.gc.superseded_by=bt-other\nm.gc.superseded_by_store=rig:beta\n' >> "$TMP/rigs/alpha/.beads/al-origin5"
mkbead beta open bt-succ5
rc=0; run --origin al-origin5 --successor bt-succ5 --kind folded || rc=$?
eq "$rc" 6 "an existing pointer to another successor is refused"
eq "$(field alpha m.gc.superseded_by al-origin5)" bt-other "the prior disposition is untouched"
eq "$(field alpha status al-origin5)" open "the bead is not closed over a conflicting disposition"

# --- (f) each kind renders its own phrasing -------------------------------
# The judgment kinds re-home work that is being carried elsewhere and gate only
# on the origin, so a cross-store open successor is fine.
for pair in "re-homed:re-homed to" "folded:folded into" "not-needed:not needed, per"; do
  kind="${pair%%:*}"; want="${pair#*:}"
  mkbead alpha open "al-k$kind"; mkbead beta open "bt-k$kind"
  rc=0; run --origin "al-k$kind" --successor "bt-k$kind" --kind "$kind" || rc=$?
  eq "$rc" 0 "kind '$kind' is accepted"
  has "$(field alpha reason "al-k$kind")" "$want" "kind '$kind' renders '$want'"
done
# The evidence kinds assert the work already shipped, so they carry that
# evidence: same-store successor, closed, over a no-op origin.
for pair in "fixed-upstream:fixed upstream by" "duplicate:duplicate of"; do
  kind="${pair%%:*}"; want="${pair#*:}"
  mkbead alpha open "al-k$kind"; printf 'm.gc.work_outcome=no-op\n' >> "$TMP/rigs/alpha/.beads/al-k$kind"
  mkbead alpha closed "al-s$kind"
  rc=0; run --origin "al-k$kind" --successor "al-s$kind" --kind "$kind" || rc=$?
  eq "$rc" 0 "kind '$kind' is accepted with its evidence"
  has "$(field alpha reason "al-k$kind")" "$want" "kind '$kind' renders '$want'"
done

# --- (q) the pointer is mandatory under every kind ------------------------
# `not-needed` is the one kind whose successor carries no work, so it is the
# one where an unpointed close reads as harmless. It is not: a close naming
# nothing is a careless close from the store the bead lived in, and here the
# pointer names the evidence that concluded the bead was unnecessary.
mkbead alpha open al-origin17
for kind in re-homed folded fixed-upstream duplicate not-needed; do
  rc=0; run --origin al-origin17 --kind "$kind" || rc=$?
  eq "$rc" 64 "kind '$kind' still requires a successor"
  has "$(cat "$TMP/err")" "--successor is required" "kind '$kind' says which pointer is missing"
done
eq "$(field alpha status al-origin17)" open "no unpointed close reached the store"
eq "$(field alpha m.gc.superseded_by al-origin17)" "" "and nothing was stamped"

# --- (g) an unclaimed id prefix is refused, not guessed -------------------
mkbead alpha open al-origin7
rc=0; run --origin al-origin7 --successor zz-nope --kind re-homed || rc=$?
eq "$rc" 2 "an id prefix no rig claims is refused"
eq "$(field alpha status al-origin7)" open "origin untouched when the store cannot be derived"
# The resolvers must not abort under `set -e` before this message is reachable:
# an unresolvable store that exits silently is indistinguishable from a crash.
has "$(cat "$TMP/err")" "cannot derive the store" "the refusal explains what to pass"

# --- (h) a self-pointer is refused ---------------------------------------
mkbead alpha open al-origin8
rc=0; run --origin al-origin8 --successor al-origin8 --kind folded || rc=$?
eq "$rc" 64 "a bead cannot supersede itself"

# --- (j) repair path: an already-closed bead gets the pointer + a note ----
# This is the shape every pre-rule bare close left behind, the incident's eight
# included: closed, unpointed, and unfixable by reopening. `bd` cannot rewrite a
# close reason, so the note is the prose a reader actually sees.
mkbead alpha closed al-origin10
mkbead beta  open   bt-succ10
rc=0; run --origin al-origin10 --successor bt-succ10 --kind re-homed || rc=$?
eq "$rc" 0 "an already-closed origin is repaired, not refused"
eq "$(field alpha m.gc.superseded_by al-origin10)" bt-succ10 "the pointer is stamped on the closed bead"
eq "$(field alpha status al-origin10)" closed "the bead is not reopened or re-closed"
has "$(field alpha notes al-origin10)" "Disposition recorded" "the disposition is appended to the notes"
has "$(field alpha notes al-origin10)" "re-homed to bt-succ10 in rig:beta" "the note names kind, successor and store"
has "$(cat "$TMP/out")" "ALREADY closed" "the output says the close reason was left alone"

# --- (k) the repair is idempotent: no duplicate note on a re-run ---------
rc=0; run --origin al-origin10 --successor bt-succ10 --kind re-homed || rc=$?
eq "$rc" 0 "re-running the repair succeeds"
eq "$(grep -c '^notes=' "$TMP/rigs/alpha/.beads/al-origin10")" 1 "the disposition note is not duplicated"
has "$(cat "$TMP/out")" "already records this disposition" "the re-run says it is a no-op"

# --- (l) interop: completes a pointer the live sweep left half-written ----
# The converse session retro-stamping the incident's beads writes ONLY
# `gc.superseded_by` — no store half. Running such a bead through here must
# recognise its own successor (not read it as a conflicting disposition) and
# simply add the missing half.
mkbead alpha open al-origin11
printf 'm.gc.superseded_by=bt-succ11\n' >> "$TMP/rigs/alpha/.beads/al-origin11"
mkbead beta open bt-succ11
rc=0; run --origin al-origin11 --successor bt-succ11 --kind re-homed || rc=$?
eq "$rc" 0 "a half-stamped pointer to the SAME successor is completed, not refused"
eq "$(field alpha m.gc.superseded_by_store al-origin11)" rig:beta "the missing store half is added"
eq "$(field alpha status al-origin11)" closed "and the bead closes with a populated reason"

# --- (m) the LEGACY bare key is read as a prior disposition --------------
# Both conventions are in the wild; a conflict guard that knew only the
# canonical key would silently overwrite a disposition written the other way.
mkbead alpha open al-origin12
printf 'm.superseded_by=bt-other\n' >> "$TMP/rigs/alpha/.beads/al-origin12"
mkbead beta open bt-succ12
rc=0; run --origin al-origin12 --successor bt-succ12 --kind folded || rc=$?
eq "$rc" 6 "a legacy bare superseded_by naming another successor is refused"
eq "$(field alpha status al-origin12)" open "the bead is not closed over it"

# --- (n) the wait edge to the successor does not refuse the disposition ---
# A converse sitting that BOTH routes work and disposes of its subject writes
# `--waiting-on <successor>` onto the subject — a real `blocks` edge — and then
# closes it. `bd close` refuses a blocked issue, so the wait refused the ruling
# it was written beside. A disposed bead is
# not waiting to proceed, and gc.superseded_by already records the relationship,
# so the edge to THIS successor goes. Same store: a `blocks` edge can only join
# two beads in one.
mkbead alpha open al-origin13
mkbead alpha open al-succ13
printf 'dep.al-succ13=blocks\n' >> "$TMP/rigs/alpha/.beads/al-origin13"
rc=0; run --origin al-origin13 --successor al-succ13 --kind folded --note "operator ruling" || rc=$?
eq "$rc" 0 "a subject blocked by its own successor is still disposed"
eq "$(field alpha status al-origin13)" closed "the close is not refused by the wait edge"
eq "$(grep -c '^dep\.al-succ13=' "$TMP/rigs/alpha/.beads/al-origin13")" 0 \
   "the wait edge to the successor is dropped"
eq "$(field alpha m.gc.superseded_by al-origin13)" al-succ13 "the pointer is the record that replaces it"
has "$(cat "$TMP/out")" "dropped the wait edge" "the drop is reported, not silent"

# --- (o) any OTHER blocker is a real hold: untouched, and it still refuses -
# The narrow drop is the point. A script that cleared the origin's blockers to
# make the close succeed would close beads somebody is genuinely holding — the
# same overreach `--force` was rejected for above.
mkbead alpha open al-origin14
mkbead alpha open al-succ14
mkbead alpha open al-block14
printf 'dep.al-succ14=blocks\ndep.al-block14=blocks\n' >> "$TMP/rigs/alpha/.beads/al-origin14"
rc=0; run --origin al-origin14 --successor al-succ14 --kind folded || rc=$?
eq "$rc" 5 "an unrelated blocker still refuses the close"
eq "$(field alpha status al-origin14)" open "the bead is left open, pointed and visible"
eq "$(field alpha m.gc.superseded_by al-origin14)" al-succ14 "the pointer is recorded either way"
eq "$(grep -c '^dep\.al-block14=' "$TMP/rigs/alpha/.beads/al-origin14")" 1 \
   "the unrelated blocker's edge is left alone"
# The drop is not conditional on the close succeeding: the edge to the successor
# is a wrong assertion the moment the pointer is stamped, whoever else holds it.
eq "$(grep -c '^dep\.al-succ14=' "$TMP/rigs/alpha/.beads/al-origin14")" 0 \
   "…while the successor's edge goes even though the close was refused"
has "$(cat "$TMP/err")" "blocked by" "the refusal names the hold the caller must judge"

# --- (p) a drop that does not stick: the WARN hands back a gc bd command ---
# `bd dep remove` reports success either way, so the read-back decides. When
# the edge survives, the close below is refused and a human finishes by hand
# — through the same client the script reaches the store with, since raw bd
# resolves that store from ambient state instead.
mkbead alpha open al-origin16
mkbead alpha open al-succ16
printf 'dep.al-succ16=blocks\n' >> "$TMP/rigs/alpha/.beads/al-origin16"
rc=0; FAKE_BD_DEP_REMOVE_NOOP=1 run --origin al-origin16 --successor al-succ16 --kind folded || rc=$?
eq "$rc" 5 "a wait edge that survives the drop still refuses the close"
has "$(cat "$TMP/err")" "WARN could not drop" "the surviving edge is reported, not swallowed"
has "$(cat "$TMP/err")" "gc bd --db $TMP/rigs/alpha/.beads dep remove al-origin16 al-succ16" \
   "the WARN's repair command runs through gc bd, against the origin's store"

# --- (i) --dry-run writes nothing ----------------------------------------
mkbead alpha open al-origin9
mkbead beta  open bt-succ9
rc=0; run --origin al-origin9 --successor bt-succ9 --kind re-homed --dry-run || rc=$?
eq "$rc" 0 "--dry-run succeeds"
eq "$(field alpha status al-origin9)" open "--dry-run does not close"
eq "$(field alpha m.gc.superseded_by al-origin9)" "" "--dry-run does not stamp"
has "$(cat "$TMP/out")" "dry run" "--dry-run says so"
mkbead alpha open al-origin15
mkbead alpha open al-succ15
printf 'dep.al-succ15=blocks\n' >> "$TMP/rigs/alpha/.beads/al-origin15"
rc=0; run --origin al-origin15 --successor al-succ15 --kind folded --dry-run || rc=$?
eq "$rc" 0 "--dry-run succeeds over a wait edge"
has "$(cat "$TMP/out")" "drop the 'blocked by al-succ15' wait edge" "--dry-run names the edge it would drop"
eq "$(grep -c '^dep\.al-succ15=' "$TMP/rigs/alpha/.beads/al-origin15")" 1 "--dry-run does not drop it"

# --- (r) a visit origin records its work outcome, and no outcome pair -------
# A visit's close runs the work-record gate, so it gets gc.work_outcome=no-op.
# The outcome pair a sitting's board row read is written by nothing here.
mkbead alpha open al-visit1
printf 'm.task_kind=visit\n' >> "$TMP/rigs/alpha/.beads/al-visit1"
mkbead beta open bt-vsucc1
rc=0; run --origin al-visit1 --successor bt-vsucc1 --kind not-needed --note "premise fixed by bt-vsucc1" || rc=$?
eq "$rc" 0 "a visit re-home succeeds"
eq "$(field alpha status al-visit1)" closed "the visit is closed"
eq "$(field alpha m.gc.outcome al-visit1)" "" "no gc.outcome is stamped on the visit"
eq "$(field alpha m.gc.outcome_reason al-visit1)" "" "no gc.outcome_reason is stamped on the visit"
has "$(field alpha reason al-visit1)" "premise fixed by bt-vsucc1" "the close reason carries the note"
eq "$(field alpha m.gc.work_outcome al-visit1)" no-op "gc.work_outcome records no-op, since a visit ships no commit"

# --- (s) a non-visit origin records NO outcome either ---------------------
# A work bead or task carries its disposition in the pointer and the close
# reason, so re-homing one invents no outcome.
mkbead alpha open al-task1
mkbead beta open bt-tsucc1
rc=0; run --origin al-task1 --successor bt-tsucc1 --kind re-homed || rc=$?
eq "$rc" 0 "a non-visit re-home succeeds"
eq "$(field alpha m.gc.outcome al-task1)" "" "a non-visit origin gets no gc.outcome"

# --- (t) an outcome the visit already records is left as it was -----------
# A visit a sitting closed and that is later re-homed already carries the word
# the sitting signed off with; the re-home writes no outcome over it.
mkbead alpha open al-visit2
printf 'm.task_kind=visit\nm.gc.outcome=dismissed\n' >> "$TMP/rigs/alpha/.beads/al-visit2"
mkbead beta open bt-vsucc2
rc=0; run --origin al-visit2 --successor bt-vsucc2 --kind folded --dry-run || rc=$?
has "$(cat "$TMP/out")" "gc.work_outcome=no-op" "--dry-run plans the work outcome for a visit that already has an outcome"
case "$(cat "$TMP/out")" in
    *"gc.outcome="*) bad "--dry-run plans no gc.outcome (got '$(cat "$TMP/out")')" ;;
    *) ok "--dry-run plans no gc.outcome" ;;
esac
rc=0; run --origin al-visit2 --successor bt-vsucc2 --kind folded || rc=$?
eq "$rc" 0 "a visit that already has an outcome still re-homes"
eq "$(field alpha m.gc.outcome al-visit2)" dismissed "the sitting's own outcome word is not overwritten"
# gc.work_outcome is not the sitting's word: a visit ships no commit, so the
# work-record gate the close runs wants no-op whatever outcome it records.
eq "$(field alpha m.gc.work_outcome al-visit2)" no-op "gc.work_outcome records no-op on a visit that already had an outcome"
FIRST=$(grep -m1 -e '^m\.gc\.work_outcome=' -e '^status=closed$' "$TMP/rigs/alpha/.beads/al-visit2" || true)
eq "${FIRST%%=*}" m.gc.work_outcome "gc.work_outcome lands before the close the work-record gate checks"

# --- (u) an already-closed visit missing its work outcome is repaired -----
# The repair path stamps the work outcome the same as the live close does, and
# no outcome pair.
mkbead alpha closed al-visit3
printf 'm.task_kind=visit\n' >> "$TMP/rigs/alpha/.beads/al-visit3"
mkbead beta open bt-vsucc3
rc=0; run --origin al-visit3 --successor bt-vsucc3 --kind duplicate || rc=$?
eq "$rc" 0 "an already-closed visit missing its work outcome is repaired"
eq "$(field alpha status al-visit3)" closed "it stays closed"
eq "$(field alpha m.gc.outcome al-visit3)" "" "no outcome is stamped on the closed visit"
eq "$(field alpha m.gc.work_outcome al-visit3)" no-op "the repair stamps gc.work_outcome=no-op on the closed visit"

# --- (z) a closed visit with an outcome still gains the work outcome -------
# A visit closed with its outcome but without gc.work_outcome lacks the field
# the work-record gate reads. The repair adds it and leaves the outcome alone.
mkbead alpha closed al-visit6
printf 'm.task_kind=visit\nm.gc.outcome=folded\nm.gc.outcome_reason=the sitting folded it\n' >> "$TMP/rigs/alpha/.beads/al-visit6"
mkbead beta open bt-vsucc6
rc=0; run --origin al-visit6 --successor bt-vsucc6 --kind folded || rc=$?
eq "$rc" 0 "an already-closed visit with an outcome is repaired"
eq "$(field alpha status al-visit6)" closed "it stays closed"
eq "$(field alpha m.gc.work_outcome al-visit6)" no-op "the repair stamps gc.work_outcome=no-op beside the recorded outcome"
eq "$(field alpha m.gc.outcome al-visit6)" folded "the recorded outcome word is untouched"
eq "$(field alpha m.gc.outcome_reason al-visit6)" "the sitting folded it" "the recorded headline is untouched"

# --- (aa) a store that refuses gc.work_outcome still re-homes the visit ----
# The key the gate only warns about never rides the pointer write, so a store
# that rejects it fails that write alone: the gated stamp lands and the visit
# closes.
mkbead alpha open al-visit7
printf 'm.task_kind=visit\n' >> "$TMP/rigs/alpha/.beads/al-visit7"
mkbead beta open bt-vsucc7
rc=0; FAKE_BD_REFUSE_WORK_OUTCOME=1 run --origin al-visit7 --successor bt-vsucc7 --kind folded || rc=$?
eq "$rc" 0 "a visit re-homes though the store refuses gc.work_outcome"
eq "$(field alpha status al-visit7)" closed "…and it closes"
eq "$(field alpha m.gc.superseded_by al-visit7)" bt-vsucc7 "…carrying its pointer"
eq "$(field alpha m.gc.work_outcome al-visit7)" "" "…with the refused key unrecorded"

# --- (ab) a dropped gc.work_outcome is repaired before the close ----------
# The store lands the write's other keys and drops this one while exiting 0,
# so only the work-outcome read-back catches the drop, before the close.
mkbead alpha open al-visit8
printf 'm.task_kind=visit\nm.gc.outcome=folded\nm.gc.outcome_reason=the sitting folded it\n' >> "$TMP/rigs/alpha/.beads/al-visit8"
mkbead beta open bt-vsucc8
rm -f "$TMP/rigs/alpha/.beads/.work-dropped"
rc=0; FAKE_BD_DROP_WORK_OUTCOME_ONCE=1 run --origin al-visit8 --successor bt-vsucc8 --kind folded || rc=$?
eq "$rc" 0 "a visit whose work-outcome write was dropped still re-homes"
[ -e "$TMP/rigs/alpha/.beads/.work-dropped" ] && ok "…after the store dropped the first write" \
    || bad "…after the store dropped the first write (the drop never fired, so this case proves nothing)"
eq "$(field alpha m.gc.work_outcome al-visit8)" no-op "the dropped work outcome is written again and lands"
FIRST=$(grep -m1 -e '^m\.gc\.work_outcome=' -e '^status=closed$' "$TMP/rigs/alpha/.beads/al-visit8" || true)
eq "${FIRST%%=*}" m.gc.work_outcome "…before the close the work-record gate checks"
rm -f "$TMP/rigs/alpha/.beads/.work-dropped"

# --- (ac) a work outcome the visit already records is left as it is --------
# Another writer's value is not rewritten, and the dry run does not plan it.
mkbead alpha open al-visit9
printf 'm.task_kind=visit\nm.gc.work_outcome=abandoned\n' >> "$TMP/rigs/alpha/.beads/al-visit9"
mkbead beta open bt-vsucc9
rc=0; run --origin al-visit9 --successor bt-vsucc9 --kind folded --dry-run || rc=$?
case "$(cat "$TMP/out")" in
    *"gc.work_outcome="*) bad "--dry-run plans no gc.work_outcome over a recorded one (got '$(cat "$TMP/out")')" ;;
    *) ok "--dry-run plans no gc.work_outcome over a recorded one" ;;
esac
rc=0; run --origin al-visit9 --successor bt-vsucc9 --kind folded || rc=$?
eq "$rc" 0 "a visit that records a work outcome still re-homes"
eq "$(field alpha status al-visit9)" closed "…and closes"
eq "$(grep -c '^m\.gc\.work_outcome=' "$TMP/rigs/alpha/.beads/al-visit9")" 1 "…with nothing written over its work outcome"
eq "$(field alpha m.gc.work_outcome al-visit9)" abandoned "…which still reads as it was"

# --- (gate-b) unlanded work: refused under an evidence kind ---------------
# merge_result names in-flight work, so an evidence kind (which claims the origin
# did no work) is refused over it.
mkbead alpha open al-unlanded
mkbead alpha closed al-usucc
printf 'm.merge_result=pull_request\n' >> "$TMP/rigs/alpha/.beads/al-unlanded"
rc=0; run --origin al-unlanded --successor al-usucc --kind duplicate || rc=$?
eq "$rc" 7 "unlanded work (merge_result set) refuses an evidence-kind close"
eq "$(field alpha status al-unlanded)" open "the origin is left open"
eq "$(field alpha m.gc.superseded_by al-unlanded)" "" "and nothing is stamped"
has "$(cat "$TMP/err")" "no work" "the refusal names the no-work requirement"
# A judgment kind carries the caller's judgment, which the writer does not
# re-judge: the converse retire path disposes an in-flight anchor through it on
# the operator's ruling.
mkbead alpha open al-retire
mkbead beta  open bt-rtsucc
printf 'm.merge_result=pull_request\n' >> "$TMP/rigs/alpha/.beads/al-retire"
rc=0; run --origin al-retire --successor bt-rtsucc --kind re-homed || rc=$?
eq "$rc" 0 "a judgment kind (re-homed) disposes an in-flight anchor"
eq "$(field alpha status al-retire)" closed "…and closes it"
# The operator's pre-recorded PR-close disposition (pr-dispose.sh) is a ruling
# already made: pr-facts.sh consummates it under whatever kind was recorded, so an
# evidence kind recorded for this successor is not re-judged.
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
# merge_result=merged is landed work, not in-flight: it may be disposed.
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
printf 'assignee=someone-else-lx-9999\n' >> "$TMP/rigs/alpha/.beads/al-held"
rc=0; run --origin al-held --successor bt-hsucc --kind re-homed || rc=$?
eq "$rc" 7 "an origin in_progress under another actor is refused"
has "$(cat "$TMP/err")" "in_progress under someone-else-lx-9999" "the refusal names the holder"
# A worker re-homing the bead it holds is the holder.
mkbead alpha in_progress al-mine
mkbead beta  open bt-msucc2
printf 'assignee=%s\n' "$BEADS_ACTOR" >> "$TMP/rigs/alpha/.beads/al-mine"
rc=0; run --origin al-mine --successor bt-msucc2 --kind re-homed || rc=$?
eq "$rc" 0 "an origin this session holds is not treated as someone else's"

# --- (gate-b) the evidence gates for fixed-upstream|duplicate -------------
# Same store required.
mkbead alpha open al-xstore; printf 'm.gc.work_outcome=no-op\n' >> "$TMP/rigs/alpha/.beads/al-xstore"
mkbead beta closed bt-xsucc
rc=0; run --origin al-xstore --successor bt-xsucc --kind duplicate || rc=$?
eq "$rc" 7 "a duplicate close needs the successor in the same store"
has "$(cat "$TMP/err")" "same store" "the refusal names the same-store requirement"
# Successor must be closed or shipped.
mkbead alpha open al-openS; printf 'm.gc.work_outcome=no-op\n' >> "$TMP/rigs/alpha/.beads/al-openS"
mkbead alpha open al-openSucc
rc=0; run --origin al-openS --successor al-openSucc --kind duplicate || rc=$?
eq "$rc" 7 "a duplicate close needs the successor closed or shipped"
# An OPEN successor that records work_outcome=shipped is accepted.
mkbead alpha open al-shipO; printf 'm.gc.work_outcome=no-op\n' >> "$TMP/rigs/alpha/.beads/al-shipO"
mkbead alpha open al-shipSucc; printf 'm.gc.work_outcome=shipped\n' >> "$TMP/rigs/alpha/.beads/al-shipSucc"
rc=0; run --origin al-shipO --successor al-shipSucc --kind fixed-upstream || rc=$?
eq "$rc" 0 "a shipped-but-open successor satisfies the evidence"
# Origin must have done no work: no work_outcome AND a work-product key refuses.
mkbead alpha open al-didwork
mkbead alpha closed al-dwSucc
printf 'm.branch=polecat/al-didwork\n' >> "$TMP/rigs/alpha/.beads/al-didwork"
rc=0; run --origin al-didwork --successor al-dwSucc --kind duplicate || rc=$?
eq "$rc" 7 "an origin with a work-product key and no no-op stamp is refused"
has "$(cat "$TMP/err")" "no work" "the refusal names the no-work requirement"
# …but a no-op stamp is accepted even beside that work-product key (the twin's
# branch names the twin, not a push this bead made).
mkbead alpha open al-twin
mkbead alpha closed al-twinSucc
printf 'm.branch=polecat/al-twinSucc\nm.gc.work_outcome=no-op\n' >> "$TMP/rigs/alpha/.beads/al-twin"
rc=0; run --origin al-twin --successor al-twinSucc --kind duplicate || rc=$?
eq "$rc" 0 "work_outcome=no-op is accepted even with a work-product key present"
eq "$(field alpha status al-twin)" closed "and the duplicate is closed"

# --- (check) --check evaluates the gates and writes nothing --------------
mkbead alpha open al-chkok
mkbead beta  open bt-chkok
rc=0; run --origin al-chkok --successor bt-chkok --kind re-homed --check || rc=$?
eq "$rc" 0 "--check passes an eligible origin"
eq "$(field alpha status al-chkok)" open "--check does not close"
eq "$(field alpha m.gc.superseded_by al-chkok)" "" "--check stamps nothing"
has "$(cat "$TMP/out")" "eligible to close" "--check reports eligibility"

mkbead alpha open al-chkno
mkbead beta  closed bt-chkno
rc=0; run --origin al-chkno --successor bt-chkno --kind duplicate --check || rc=$?
eq "$rc" 1 "--check refuses a cross-store duplicate with exit 1"
eq "$(field alpha status al-chkno)" open "--check refusal writes nothing"
eq "$(field alpha m.gc.superseded_by al-chkno)" "" "--check refusal stamps nothing"
has "$(cat "$TMP/err")" "--check refused" "--check names the refusal"

# --check over an already-closed origin: the repair path is not gated.
mkbead alpha closed al-chkclosed
mkbead beta  open bt-chkclosed
rc=0; run --origin al-chkclosed --successor bt-chkclosed --kind re-homed --check || rc=$?
eq "$rc" 0 "--check over an already-closed origin passes (repair path)"
eq "$(field alpha m.gc.superseded_by al-chkclosed)" "" "--check still writes nothing"

# A bead that names the branch its work was pushed to.
mkbranched() { mkbead "$1" "$2" "$3"; printf 'm.branch=polecat/%s\n' "$3" >> "$TMP/rigs/$1/.beads/$3"; }

# --- (ad) the retired bead's branch goes to branch-end, after the close ------
# A merge ends a landed branch; a retire ends its own the same way, once the
# bead it retires reads back closed.
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
eq "$(field alpha m.gc.superseded_by al-br2)" bt-br2 "…with its pointer"
has "$(cat "$TMP/err")" "branch-end (stub): did NOT end" "…branch-end's own reason is passed on"
has "$(cat "$TMP/err")" "the close stands, but branch polecat/al-br2 is still on the git remote" "…and a WARN names the branch"
has "$(cat "$TMP/err")" "end it with: $BE_STUB --rig alpha --branch polecat/al-br2 --bead al-br2" "…and the command that ends it"
has "$(field alpha notes al-br2)" "Branch polecat/al-br2 is still on the git remote (branch-end exit 4: branch-end (stub): did NOT end)" \
    "…and the bead records that the branch is still there"
has "$(field alpha notes al-br2)" "End it with: $BE_STUB --rig alpha --branch polecat/al-br2 --bead al-br2" "…with the command that ends it"

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
has "$(cat "$TMP/out")" "end polecat/al-br7 on the git remote of rig:alpha once the close reads back" "…and its plan names the branch"
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

# --- (ai) a close that does not read back closed leaves the branch ----------
mkbranched alpha open al-br9
mkbead beta open bt-br9
: > "$BE_LOG"
rc=0; FAKE_BD_CLOSE_NOOP=1 run --origin al-br9 --successor bt-br9 --kind re-homed || rc=$?
eq "$(cat "$BE_LOG")" "" "a close that does not read back ends no branch"
has "$(cat "$TMP/err")" "did not read back closed" "…and a WARN says why the branch was left"

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

# --- (al) the stamp lands only on the bead the gates judged -----------------
# bd holds a claimed bead against another actor's assignment and close, never
# against a metadata write, so the stamp itself carries the status and assignee
# the gates read.
mkbead alpha open al-judged
mkbead beta  open bt-judged
: > "$TMP/updates.log"
rc=0; FAKE_UPDATE_LOG="$TMP/updates.log" run --origin al-judged --successor bt-judged --kind re-homed || rc=$?
eq "$rc" 0 "a bead nobody took since the gates read it is disposed"
has "$(grep -F 'gc.superseded_by=' "$TMP/updates.log")" "al-judged --if-status=open --if-assignee= --set-metadata gc.superseded_by=bt-judged" \
   "the stamp is conditional on the status and assignee the gates read"
mkbead alpha in_progress al-judged-mine
printf 'assignee=%s\n' "$BEADS_ACTOR" >> "$TMP/rigs/alpha/.beads/al-judged-mine"
mkbead beta  open bt-judged-mine
: > "$TMP/updates.log"
rc=0; FAKE_UPDATE_LOG="$TMP/updates.log" run --origin al-judged-mine --successor bt-judged-mine --kind re-homed || rc=$?
eq "$rc" 0 "a bead this session holds is disposed under its claim"
has "$(grep -F 'gc.superseded_by=' "$TMP/updates.log")" "--if-status=in_progress --if-assignee=$BEADS_ACTOR --set-metadata gc.superseded_by=bt-judged-mine" \
   "…with the stamp conditional on that claim"
# Another actor claims the bead after the gates read it and before the stamp.
mkbead alpha open al-taken
mkbead beta  open bt-taken
: > "$FG_LOG"
rc=0; FAKE_BD_CLAIM_BEFORE_STAMP="in_progress deferred-dispatch" run --origin al-taken --successor bt-taken --kind re-homed || rc=$?
eq "$rc" 4 "a claim that lands between the gates and the stamp refuses the stamp (exit 4)"
eq "$(field alpha m.gc.superseded_by al-taken)" "" "…nothing is stamped under that claim"
eq "$(field alpha status al-taken)/$(field alpha assignee al-taken)" "in_progress/deferred-dispatch" "…the claim stands"
eq "$(field alpha reason al-taken)" "" "…nothing is closed"
eq "$(cat "$FG_LOG")" "" "…the close is never attempted"
eq "$(field beta m.gc.supersedes bt-taken)" "" "…and the successor gains no back-pointer"
has "$(cat "$TMP/err")" "al-taken is no longer open and unassigned" "the refusal names the state the gates judged"
has "$(cat "$TMP/err")" "nothing is stamped" "…and says nothing was written"
# The repair path reads a closed bead; a reopen before its stamp refuses it too.
mkbead alpha closed al-reopened
mkbead beta  open bt-reopened
rc=0; FAKE_BD_CLAIM_BEFORE_STAMP="open " run --origin al-reopened --successor bt-reopened --kind re-homed || rc=$?
eq "$rc" 4 "a reopen between the repair path's read and its stamp refuses the stamp"
eq "$(field alpha m.gc.superseded_by al-reopened)" "" "…so the reopened bead carries no pointer"
eq "$(field alpha status al-reopened)" "open" "…and stays open"

# --- (am) the retry withdraws its own gates before the close ---------------
# pr-facts.sh files its report of a refused close as a human gate that blocks
# the anchor, and names that key when it retries. bd refuses to close a bead an
# open gate blocks, so the retry resolves its own gates first, with a reason
# that names the retry and carries no outcome word, so no quiet period starts.
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

# A close with no --except-key resolves nothing: a gate that blocks the origin
# is left for the person, and bd refuses the close it blocks.
mkbead alpha open al-retry2
mkbead beta  open bt-retry2
hgate al-g2 pr-dispose-failed.9
printf 'dep.al-g2=blocks\n' >> "$TMP/rigs/alpha/.beads/al-retry2"
rc=0; run --origin al-retry2 --successor bt-retry2 --kind not-needed || rc=$?
eq "$rc" 5 "without --except-key a gate blocking the origin refuses the close"
eq "$(field alpha status al-g2)" open "…and is not resolved"

# --- (an) anything else that would refuse the close holds it first ----------
# The gates are resolved only once nothing else would refuse the close, so a
# held close leaves the report of it standing.
mkbead alpha open al-retry3
mkbead beta  open bt-retry3
hgate al-g3 pr-dispose-failed.9
mkbead alpha open al-work3
printf 'dep.al-g3=blocks\ndep.al-work3=blocks\n' >> "$TMP/rigs/alpha/.beads/al-retry3"
rc=0; run --origin al-retry3 --successor bt-retry3 --kind not-needed --except-key pr-dispose-failed.9 || rc=$?
eq "$rc" 5 "another live blocker holds the retry"
eq "$(field alpha status al-g3)" open "…the retry's own gate stays open"
eq "$(field alpha status al-retry3)" open "…the origin stays open"
eq "$(field alpha m.gc.superseded_by al-retry3)" bt-retry3 "…pointed"
has "$(cat "$TMP/err")" "al-work3" "…and the refusal names the blocker"
# A blocker that is closed or pinned holds nothing, as in bd.
mkbead alpha open al-retry3c
mkbead beta  open bt-retry3c
hgate al-g3c pr-dispose-failed.9
mkbead alpha closed al-done3c
mkbead alpha pinned al-pin3c
printf 'dep.al-g3c=blocks\ndep.al-done3c=blocks\ndep.al-pin3c=blocks\n' >> "$TMP/rigs/alpha/.beads/al-retry3c"
rc=0; run --origin al-retry3c --successor bt-retry3c --kind not-needed --except-key pr-dispose-failed.9 || rc=$?
eq "$(field alpha status al-g3c)" closed "a closed or pinned blocker beside its own gate does not hold the withdrawal"
# A gate under the key that a person is assigned is theirs to clear.
mkbead alpha open al-retry4
mkbead beta  open bt-retry4
hgate al-g4 pr-dispose-failed.9 operator
printf 'dep.al-g4=blocks\n' >> "$TMP/rigs/alpha/.beads/al-retry4"
rc=0; run --origin al-retry4 --successor bt-retry4 --kind not-needed --except-key pr-dispose-failed.9 || rc=$?
eq "$rc" 5 "a gate under the key assigned to a person holds the retry"
eq "$(field alpha status al-g4)" open "…and is not resolved"
# A gate under another key holds it as well.
mkbead alpha open al-retry4k
mkbead beta  open bt-retry4k
hgate al-g4k pr-dispose-failed.9
hgate al-o4k another-question
printf 'dep.al-g4k=blocks\ndep.al-o4k=blocks\n' >> "$TMP/rigs/alpha/.beads/al-retry4k"
rc=0; run --origin al-retry4k --successor bt-retry4k --kind not-needed --except-key pr-dispose-failed.9 || rc=$?
eq "$rc" 5 "a gate under another key holds the retry"
eq "$(field alpha status al-g4k)/$(field alpha status al-o4k)" "open/open" "…and neither gate is resolved"
# An open child holds it.
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

# --- (ao) a gate that does not resolve, and a run stopped part way ----------
mkbead alpha open al-retry7
mkbead beta  open bt-retry7
hgate al-g7 pr-dispose-failed.9
printf 'dep.al-g7=blocks\n' >> "$TMP/rigs/alpha/.beads/al-retry7"
rc=0; FAKE_BD_GATE_RESOLVE_NOOP=1 run --origin al-retry7 --successor bt-retry7 --kind not-needed --except-key pr-dispose-failed.9 || rc=$?
eq "$rc" 5 "a gate that does not resolve holds the close"
eq "$(field alpha status al-retry7)" open "…the origin stays open"
has "$(cat "$TMP/err")" "al-g7" "…and the refusal names the gate"
# The withdrawal landed but the close did not: the next run finds no own gate
# open and closes.
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
# bd refuses an unforced close of a template, of a pinned bead, and of a bead
# assigned to anyone but the close's --actor, whatever its status. Gate (a) lets
# an OPEN bead under another assignee through, so the retry reads these before
# it withdraws a gate: withdrawn ahead of a refused close, the question would go
# and the next refused retry would file it again. The store here refuses such a
# close the way bd does.
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
eq "$(field alpha m.gc.superseded_by al-guard1)" bt-guard1 "…pointed"
has "$(cat "$TMP/err")" "assigned to someone-else" "…and the refusal names the assignee"
has "$(cat "$TMP/err")" "runs as $BEADS_ACTOR" "…and the actor the close runs as"
# A bead this session holds under another of its names passes gate (a), which
# accepts every name of the session, but bd compares the assignee with the
# actor alone.
mkbead alpha in_progress al-guard2
mkbead beta  open bt-guard2
printf 'assignee=test__rehome-session-name\n' >> "$TMP/rigs/alpha/.beads/al-guard2"
hgate al-gg2 pr-dispose-failed.9
printf 'dep.al-gg2=blocks\n' >> "$TMP/rigs/alpha/.beads/al-guard2"
rc=0; GC_SESSION_NAME=test__rehome-session-name run --origin al-guard2 --successor bt-guard2 --kind not-needed --except-key pr-dispose-failed.9 || rc=$?
eq "$rc" 5 "an origin this session holds under a name other than the actor holds the retry"
eq "$(field alpha status al-gg2)/$(field alpha status al-guard2)" "open/in_progress" "…and resolves and closes nothing"
# A pinned origin and a template hold it the same way.
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
# An origin assigned to exactly the actor closes, its own gate withdrawn.
mkbead alpha open al-guard5
mkbead beta  open bt-guard5
printf 'assignee=%s\n' "$BEADS_ACTOR" >> "$TMP/rigs/alpha/.beads/al-guard5"
hgate al-gg5 pr-dispose-failed.9
printf 'dep.al-gg5=blocks\n' >> "$TMP/rigs/alpha/.beads/al-guard5"
rc=0; run --origin al-guard5 --successor bt-guard5 --kind not-needed --except-key pr-dispose-failed.9 || rc=$?
eq "$rc" 0 "an origin assigned to exactly the actor closes"
eq "$(field alpha status al-gg5)/$(field alpha status al-guard5)" "closed/closed" "…its own gate withdrawn first"
unset FAKE_BD_ENFORCE_CLOSE_GUARDS

echo "---"
echo "bead-rehome.test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
