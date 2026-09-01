#!/usr/bin/env bash
# Hermetic test for bead-rehome.sh.
#
# Fakes `gc rig list --json` and `bd` (a file-per-bead ledger under each fake
# rig's .beads/) on PATH. No dependency on the live city, Dolt, or the network.
#
# The invariants under test are the ones the incident turned on (tk-isyz0):
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
#   (p) every repair command the script hands back runs through `gc bd`.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/bead-rehome.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (got '$1', wanted substring '$2')" ;; esac; }

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

cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
# Only the surface bead-rehome.sh touches.
case "$1 $2" in
  "rig list") cat "$FAKE_RIGS_JSON" ;;
  "bd "*)    shift; VIA_GC_BD=1 exec "$(dirname "$0")/bd" "$@" ;;
  *) exit 1 ;;
esac
GC

cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
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
    while [ $# -gt 0 ]; do
      case "$1" in
        --set-metadata)
          # FAKE_BD_DROP_META simulates a write that reports success and does
          # not persist — the case the read-back guard exists for.
          [ -n "${FAKE_BD_DROP_META:-}" ] || printf 'm.%s\n' "$2" >> "$f"
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
for pair in "folded:folded into" "fixed-upstream:fixed upstream by" "duplicate:duplicate of"; do
  kind="${pair%%:*}"; want="${pair#*:}"
  mkbead alpha open "al-k$kind"; mkbead beta open "bt-k$kind"
  rc=0; run --origin "al-k$kind" --successor "bt-k$kind" --kind "$kind" || rc=$?
  eq "$rc" 0 "kind '$kind' is accepted"
  has "$(field alpha reason "al-k$kind")" "$want" "kind '$kind' renders '$want'"
done

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
# it was written beside (tk-hs5rz, live at visit tk-e9ffv). A disposed bead is
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

echo "---"
echo "bead-rehome.test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
