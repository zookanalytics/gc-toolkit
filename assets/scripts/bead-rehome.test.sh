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
#   (r) a task_kind=visit origin also records gc.outcome (= the kind) and
#       gc.outcome_reason (= the close reason), so the board can report it,
#       plus gc.work_outcome=no-op for the work-record gate the close runs;
#   (s) a non-visit origin records NO gc.outcome — the field is a sitting's;
#   (t) an outcome the visit already carries is the sitting's own word and is
#       never overwritten, while gc.work_outcome=no-op still lands before the
#       close;
#   (u) an already-closed visit missing the outcome is repaired with it;
#   (v) an outcome that does not read back refuses the close, the same way a
#       dropped pointer does — a closed outcome-less visit is unreachable;
#   (w) a dropped gc.outcome_reason refuses the close too — the board shows the
#       reason as the sitting's headline, so an outcome without it is unreadable;
#   (x) an open visit on the origin holds the close at the finalize gate;
#   (y) --except-key reaches that gate, and nothing is excepted without it;
#   (z) an already-closed visit that records its outcome is repaired with
#       gc.work_outcome=no-op, and its outcome is left as it was;
#   (aa) a store that refuses gc.work_outcome still re-homes and closes the
#       visit — the key is a write of its own, never a precondition;
#   (ab) a dropped gc.work_outcome on a visit that records its outcome is read
#       back and written again before the close;
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
#       carries shell metacharacters as one argument and runs nothing it spells.
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
# `bd close` consults.
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
DB=""
while [ $# -gt 0 ]; do
  case "$1" in
    --db) DB="$2"; shift 2 ;;
    --actor) echo "$2" >> "$FAKE_ACTOR_LOG"; shift 2 ;;
    *) break ;;
  esac
done
sub="${1:-}"; shift || true

# `bd dep <verb> <id> <depends-on-id>` puts the verb where every other
# subcommand puts the bead id, so it is parsed on its own.
if [ "$sub" = "dep" ]; then
  verb="${1:-}"; shift || true
  id="${1:-}"; shift || true
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
  st=""; mf='[]'
  while [ $# -gt 0 ]; do
    case "$1" in
      --status) st="$2"; shift 2 ;;
      --status=*) st="${1#--status=}"; shift ;;
      --metadata-field)
        mf=$(jq -cn --argjson m "$mf" --arg k "${2%%=*}" --arg v "${2#*=}" '$m + [{k: $k, v: $v}]')
        shift 2 ;;
      *) shift ;;
    esac
  done
  rows='[]'
  for bf in "$DB"/*; do
    [ -f "$bf" ] || continue
    bs=$(sed -n 's/^status=//p' "$bf" | tail -1)
    case ",$st," in *",$bs,"*) ;; *) continue ;; esac
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
    jq -n --arg id "$id" --arg st "$(sed -n 's/^status=//p' "$f" | tail -1)" \
          --arg notes "$(sed -n 's/^notes=//p' "$f" | tr '\n' ' ')" \
          --argjson meta "$(meta_json)" \
          --argjson deps "$(deps_json)" \
          '[{id: $id, status: $st, notes: $notes, metadata: $meta, dependencies: $deps}]'
    ;;
  update)
    # FAKE_BD_REFUSE_WORK_OUTCOME refuses any update naming gc.work_outcome,
    # writing nothing: the store or gate that rejects the key.
    if [ -n "${FAKE_BD_REFUSE_WORK_OUTCOME:-}" ]; then
      case " $* " in *" gc.work_outcome="*) echo "refused: gc.work_outcome" >&2; exit 1 ;; esac
    fi
    while [ $# -gt 0 ]; do
      case "$1" in
        --set-metadata)
          # FAKE_BD_DROP_META simulates a write that reports success and does
          # not persist — the case the read-back guard exists for.
          # FAKE_BD_DROP_OUTCOME drops ONLY the gc.outcome key and
          # FAKE_BD_DROP_OUTCOME_REASON drops ONLY the gc.outcome_reason key
          # (each leaving the other) to exercise either half of the
          # visit-outcome read-back gate on its own.
          # FAKE_BD_DROP_WORK_OUTCOME_ONCE drops the first gc.work_outcome key
          # an update carries, landing its other keys; later ones land.
          drop=""
          [ -z "${FAKE_BD_DROP_META:-}" ] || drop=1
          case "$2" in gc.outcome=*) [ -z "${FAKE_BD_DROP_OUTCOME:-}" ] || drop=1 ;; esac
          case "$2" in gc.outcome_reason=*) [ -z "${FAKE_BD_DROP_OUTCOME_REASON:-}" ] || drop=1 ;; esac
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
    # A stub that closes a blocked bead would report a green suite for the bug
    # in case (n) below: the whole defect is that real bd refuses here.
    BLOCKED=$(open_blockers)
    if [ -n "$BLOCKED" ]; then
      echo "cannot close blocked issue: $id is blocked by [${BLOCKED// /, }] (use --force to override)" >&2
      exit 1
    fi
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
# bead) without a live tracks-edge probe — the gate's own logic is covered by
# finalize-gate.test.sh. Default: allow; FG_VERDICT=hold makes it refuse. Each
# call's argv is appended to FG_LOG.
FG_STUB="$TMP/bin/finalize-gate-stub.sh"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "${FG_LOG:?}"\ncase "${FG_VERDICT:-pass}" in\n  hold) echo "held by open visit vis-x — its subject ${2:-?} owes a conversation before finalize"; exit 1 ;;\n  *) exit 0 ;;\nesac\n' > "$FG_STUB"
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

# --- (x) an OPEN visit on the origin holds the close (finalize gate) ---------
# The gate refuses while a visit tracks the origin. bead-rehome stamps the
# successor pointer, then leaves the bead OPEN — the same shape a refused close
# leaves — so the disposition stays legible and the visit can be concluded first.
mkbead alpha open al-vhold
mkbead beta  open bt-vsucc
rc=0; FG_VERDICT=hold run --origin al-vhold --successor bt-vsucc --kind re-homed --note "ruling" || rc=$?
eq "$rc" 5 "an open visit holds the close (exit 5)"
eq "$(field alpha status al-vhold)" open "…the origin stays OPEN under the hold"
eq "$(field alpha m.gc.superseded_by al-vhold)" bt-vsucc "…the pointer is still stamped, so the disposition is findable"
has "$(cat "$TMP/err")" "the close is held" "…stderr says the close is held"
has "$(cat "$TMP/err")" "held by open visit" "…and carries the gate's reason"

# --- (y) --except-key reaches the finalize gate, and only when given -------
# The caller's own reports of an earlier refused close ask for this retry, so
# their escalation key is named to the gate, which owns what an exception may
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
mkbead alpha open al-origin4
mkbead beta  open bt-succ4
rc=0; FAKE_BD_CLOSE_REFUSE=1 run --origin al-origin4 --successor bt-succ4 --kind duplicate || rc=$?
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
for pair in "folded:folded into" "fixed-upstream:fixed upstream by" "duplicate:duplicate of" "not-needed:not needed, per"; do
  kind="${pair%%:*}"; want="${pair#*:}"
  mkbead alpha open "al-k$kind"; mkbead beta open "bt-k$kind"
  rc=0; run --origin "al-k$kind" --successor "bt-k$kind" --kind "$kind" || rc=$?
  eq "$rc" 0 "kind '$kind' is accepted"
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
rc=0; run --origin al-origin14 --successor al-succ14 --kind duplicate || rc=$?
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

# --- (r) a visit origin also records the outcome the board reads -----------
# doctor/check-visit-outcome-recorded flags a closed task_kind=visit with no
# gc.outcome — a sitting the board cannot report. bead-rehome is a visit-close
# path (converse dispositions re-home visits), so it stamps the outcome beside
# the pointer: gc.outcome = the kind, gc.outcome_reason = the close reason.
mkbead alpha open al-visit1
printf 'm.task_kind=visit\n' >> "$TMP/rigs/alpha/.beads/al-visit1"
mkbead beta open bt-vsucc1
rc=0; run --origin al-visit1 --successor bt-vsucc1 --kind not-needed --note "premise fixed by bt-vsucc1" || rc=$?
eq "$rc" 0 "a visit re-home succeeds"
eq "$(field alpha status al-visit1)" closed "the visit is closed"
eq "$(field alpha m.gc.outcome al-visit1)" not-needed "gc.outcome records the kind as the sitting's outcome"
has "$(field alpha m.gc.outcome_reason al-visit1)" "not needed, per bt-vsucc1 in rig:beta" "gc.outcome_reason carries the close reason as the headline"
has "$(field alpha m.gc.outcome_reason al-visit1)" "premise fixed by bt-vsucc1" "the headline carries the note too"
eq "$(field alpha m.gc.work_outcome al-visit1)" no-op "gc.work_outcome records no-op, since a visit ships no commit"

# --- (s) a non-visit origin records NO outcome (the field is visit-only) ---
# gc.outcome is a sitting's column; a work bead or task carries its disposition
# elsewhere, so re-homing one must not invent one.
mkbead alpha open al-task1
mkbead beta open bt-tsucc1
rc=0; run --origin al-task1 --successor bt-tsucc1 --kind re-homed || rc=$?
eq "$rc" 0 "a non-visit re-home succeeds"
eq "$(field alpha m.gc.outcome al-task1)" "" "a non-visit origin gets no gc.outcome"

# --- (t) an outcome the visit already records is the sitting's own word -----
# A visit closed through visit-close.sh and later re-homed already carries the
# word the sitting signed off with; the re-home must not overwrite it.
mkbead alpha open al-visit2
printf 'm.task_kind=visit\nm.gc.outcome=dismissed\n' >> "$TMP/rigs/alpha/.beads/al-visit2"
mkbead beta open bt-vsucc2
rc=0; run --origin al-visit2 --successor bt-vsucc2 --kind folded --dry-run || rc=$?
has "$(cat "$TMP/out")" "gc.work_outcome=no-op" "--dry-run plans the work outcome for a visit that already has an outcome"
case "$(cat "$TMP/out")" in
    *"gc.outcome="*) bad "--dry-run plans no gc.outcome over the sitting's own word (got '$(cat "$TMP/out")')" ;;
    *) ok "--dry-run plans no gc.outcome over the sitting's own word" ;;
esac
rc=0; run --origin al-visit2 --successor bt-vsucc2 --kind folded || rc=$?
eq "$rc" 0 "a visit that already has an outcome still re-homes"
eq "$(field alpha m.gc.outcome al-visit2)" dismissed "the sitting's own outcome word is not overwritten"
# gc.work_outcome is not the sitting's word: a visit ships no commit, so the
# work-record gate the close runs wants no-op whatever outcome it records.
eq "$(field alpha m.gc.work_outcome al-visit2)" no-op "gc.work_outcome records no-op on a visit that already had an outcome"
FIRST=$(grep -m1 -e '^m\.gc\.work_outcome=' -e '^status=closed$' "$TMP/rigs/alpha/.beads/al-visit2" || true)
eq "${FIRST%%=*}" m.gc.work_outcome "gc.work_outcome lands before the close the work-record gate checks"

# --- (u) an already-closed visit missing the outcome is repaired -----------
# This is the shape where bead-rehome closed the visit before this guard, so
# the repair path stamps the outcome the same as the live close does.
mkbead alpha closed al-visit3
printf 'm.task_kind=visit\n' >> "$TMP/rigs/alpha/.beads/al-visit3"
mkbead beta open bt-vsucc3
rc=0; run --origin al-visit3 --successor bt-vsucc3 --kind duplicate || rc=$?
eq "$rc" 0 "an already-closed visit missing the outcome is repaired"
eq "$(field alpha status al-visit3)" closed "it stays closed"
eq "$(field alpha m.gc.outcome al-visit3)" duplicate "the missing outcome is stamped on the closed visit"
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
# The key the gate only warns about never rides the pointer or outcome write,
# so a store that rejects it fails that write alone: the gated stamps land and
# the visit closes.
mkbead alpha open al-visit7
printf 'm.task_kind=visit\n' >> "$TMP/rigs/alpha/.beads/al-visit7"
mkbead beta open bt-vsucc7
rc=0; FAKE_BD_REFUSE_WORK_OUTCOME=1 run --origin al-visit7 --successor bt-vsucc7 --kind folded || rc=$?
eq "$rc" 0 "a visit re-homes though the store refuses gc.work_outcome"
eq "$(field alpha status al-visit7)" closed "…and it closes"
eq "$(field alpha m.gc.superseded_by al-visit7)" bt-vsucc7 "…carrying its pointer"
eq "$(field alpha m.gc.outcome al-visit7)" folded "…and its outcome"
eq "$(field alpha m.gc.work_outcome al-visit7)" "" "…with the refused key unrecorded"

# --- (ab) a dropped gc.work_outcome is repaired on a visit with an outcome --
# The store lands the write's other keys and drops this one while exiting 0.
# A visit that already records its outcome stamps no outcome here, so only the
# work-outcome read-back catches the drop, before the close.
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
# The same rule as the sitting's own outcome word: another writer's value is
# not rewritten, and the dry run does not plan it.
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

# --- (v) an outcome that does not read back refuses the close --------------
# The same permanence as the pointer: once the visit closes no re-run reaches
# it, so a dropped outcome stamp leaves the visit OPEN, not silently closed.
mkbead alpha open al-visit4
printf 'm.task_kind=visit\n' >> "$TMP/rigs/alpha/.beads/al-visit4"
mkbead beta open bt-vsucc4
rc=0; FAKE_BD_DROP_OUTCOME=1 run --origin al-visit4 --successor bt-vsucc4 --kind folded || rc=$?
eq "$rc" 4 "a visit outcome that does not read back refuses the close"
eq "$(field alpha status al-visit4)" open "the visit stays OPEN when the outcome did not stick"
has "$(cat "$TMP/err")" "outcome did NOT stick" "the refusal names the missing outcome"
eq "$(field alpha m.gc.superseded_by al-visit4)" bt-vsucc4 "the pointer is still recorded, so the bead is findable"

# --- (w) a dropped gc.outcome_reason refuses the close too -----------------
# gc.outcome_reason is the sitting's board headline, so the read-back gate must
# cover the reason as well as the word: dropping only the reason must leave the
# visit OPEN, not close it into a headline-less row that no re-run can repair
# (PRIOR_OUTCOME is nonempty once gc.outcome lands, so a re-run never re-arms).
mkbead alpha open al-visit5
printf 'm.task_kind=visit\n' >> "$TMP/rigs/alpha/.beads/al-visit5"
mkbead beta open bt-vsucc5
rc=0; FAKE_BD_DROP_OUTCOME_REASON=1 run --origin al-visit5 --successor bt-vsucc5 --kind folded || rc=$?
eq "$rc" 4 "a visit outcome_reason that does not read back refuses the close"
eq "$(field alpha status al-visit5)" open "the visit stays OPEN when the reason did not stick"
has "$(cat "$TMP/err")" "outcome did NOT stick" "the refusal names the missing outcome stamp"
eq "$(field alpha m.gc.outcome_reason al-visit5)" "" "the reason really was dropped by the fake"
eq "$(field alpha m.gc.superseded_by al-visit5)" bt-vsucc5 "the pointer is still recorded, so the bead is findable"

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
rc=0; FAKE_BD_CLOSE_REFUSE=1 run --origin al-br4 --successor bt-br4 --kind duplicate || rc=$?
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

echo "---"
echo "bead-rehome.test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
