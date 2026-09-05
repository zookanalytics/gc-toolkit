#!/usr/bin/env bash
# Hermetic test for assets/scripts/bead-store.sh.
#
# The finding it guards: a bare `gc bd show` resolves a live id from whichever
# store holds it, but a miss is answered by the store the caller stands in, so
# a bead absent from ANOTHER store answers "no issues found" byte-for-byte like
# one that exists nowhere. A gate reading that miss as "nothing owns this,
# delete it" destroys on an answer about the wrong subject. So the
# assertions are about which store was ASKED, and about every shape that must
# not read as absence: an unknown prefix, a prefix two rigs carry, an
# unreadable rig list, and a store that answers nothing at all.
#
# `gc` is stubbed over a file-per-bead ledger under each fake rig; a direct
# `bd` is a regression the stub fails on. No live city, Dolt, or network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/bead-store.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }

# --- fake city --------------------------------------------------------------
# alpha and beta are ordinary rigs; hq is the city's own store, which no --rig
# value names and only a --db path reaches. `void` carries a prefix and no
# path at all, which is a store that cannot be addressed.
mkdir -p "$TMP/bin" "$TMP/rigs/alpha/.beads" "$TMP/rigs/beta/.beads" "$TMP/hq/.beads"
cat > "$TMP/rigs.json" <<JSON
{"rigs":[
  {"name":"alpha","path":"$TMP/rigs/alpha","prefix":"al","hq":false},
  {"name":"beta","path":"$TMP/rigs/beta","prefix":"bt","hq":false},
  {"name":"town","path":"$TMP/hq","prefix":"lx","hq":true},
  {"name":"void","path":"","prefix":"vd","hq":false}
]}
JSON
export FAKE_RIGS="$TMP/rigs.json"
export FAKE_GC_LOG="$TMP/gc.log"; : > "$FAKE_GC_LOG"
export FAKE_BD_LOG="$TMP/bd.log"; : > "$FAKE_BD_LOG"
mkbead() { : > "$1/.beads/$2"; }

cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
# Only the surface bead-store.sh touches. Every call is logged so the test can
# prove which store was asked, not merely what came back.
set -u
printf '%s\n' "$*" >> "$FAKE_GC_LOG"
case "$1 $2" in
  "rig list")
    [ -n "${FAKE_RIGS_FAIL:-}" ] && { echo "gc: rig list unavailable" >&2; exit 1; }
    cat "$FAKE_RIGS" ;;
  "bd --db")
    DB="$3"; shift 3
    [ "${1:-}" = "show" ] || exit 1
    ID="${2:-}"
    # A store that cannot be opened prints NOTHING and exits 1 — the same exit
    # code a genuine miss uses. That is why the payload decides, not the code.
    [ -d "$DB" ] || exit 1
    # A bare `<prefix>-` has an empty local part: real bd reads it as an invalid
    # marker and answers the generic not-found, not a prefix scan. Model that, or
    # the naive scan below calls it "ambiguous" and masks the fail-open a bare
    # marker opens for `--absent`.
    case "$ID" in
      *-) printf '{"error":"no issues found matching the provided IDs","schema_version":1}\n'
          echo "Issue $ID not found" >&2
          exit 1 ;;
    esac
    # bd resolves a bare id as an exact match first, then as a prefix, and a
    # prefix matching several ids is ambiguous rather than a miss. Each shape
    # answers with the SAME miss object on stdout for the two error cases and
    # states the reason on stderr, exactly as the real tool does — the guard has
    # to survive all three.
    if [ -f "$DB/$ID" ]; then
      printf '[{"id":"%s","status":"open"}]\n' "$ID"; exit 0
    fi
    MATCHES=$(ls "$DB" 2>/dev/null | awk -v p="$ID" 'index($0,p)==1')
    N=$(printf '%s' "$MATCHES" | grep -c . || true)
    if [ "$N" = 1 ]; then
      printf '[{"id":"%s","status":"open"}]\n' "$MATCHES"; exit 0
    elif [ "$N" = 0 ]; then
      printf '{"error":"no issues found matching the provided IDs","schema_version":1}\n'
      echo "Issue $ID not found" >&2
      exit 1
    else
      printf '{"error":"no issues found matching the provided IDs","schema_version":1}\n'
      echo "ambiguous issue ID: \"$ID\" matches $N issues: [$(printf '%s' "$MATCHES" | tr '\n' ' ' | sed 's/ *$//')]" >&2
      exit 1
    fi ;;
  *) exit 1 ;;
esac
GC

cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
# The guard reaches every store through `gc bd --db`; a direct `bd` is the
# regression this stub exists to fail on. It records the call rather than only
# failing it, so the assertion reads a log of the whole run.
printf '%s\n' "$*" >> "$FAKE_BD_LOG"
echo "stub bd: called directly instead of through gc bd" >&2
exit 127
BD
chmod +x "$TMP/bin/gc" "$TMP/bin/bd"
export PATH="$TMP/bin:$PATH"
unset FAKE_RIGS_FAIL 2>/dev/null || true

mkbead "$TMP/rigs/alpha" al-lives
mkbead "$TMP/rigs/beta"  bt-lives
mkbead "$TMP/hq"         lx-lives
# For the exact-id checks below: `al-uniq` is a prefix of exactly one bead, and
# `al-dup` a prefix of two — a unique-partial hit and an ambiguous reference.
mkbead "$TMP/rigs/alpha" al-uniqfull
mkbead "$TMP/rigs/alpha" al-dup1
mkbead "$TMP/rigs/alpha" al-dup2

run() { OUT=$("$SUT" "$@" 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err"); }

# --- resolution -------------------------------------------------------------
run al-lives
eq "$RC" 0     "an alpha id resolves (rc)"
eq "$OUT" alpha "  ... to alpha"

run --path bt-anything
eq "$OUT" "$TMP/rigs/beta" "--path names the owning rig's repo, resolved from the prefix alone"

run --db lx-anything
eq "$OUT" "$TMP/hq/.beads" "--db reaches the HQ store, which no --rig value names"

# --- the finding: a foreign bead is not an absent one -----------------------
# The caller stands in alpha and asks about a beta bead. The ambient store has
# never heard of it; the store its prefix names has.
export GC_RIG=alpha
run --absent bt-lives
eq "$RC" 1 "a bead living in ANOTHER store is not absent, whatever the ambient rig says"
eq "$OUT" "" "  ... and a verdict prints nothing on stdout"
has "$ERR" "EXISTS in beta" "  ... naming the store that actually holds it"
has "$(cat "$FAKE_GC_LOG")" "bd --db $TMP/rigs/beta/.beads show bt-lives" \
  "  ... because beta's store was the one asked"

run --present bt-lives
eq "$RC" 0 "--present proves the same bead present from the same wrong ambient rig"

# The one shape that licenses a destructive act: the owning store answered, and
# it does not have the bead.
run --absent bt-gone
eq "$RC" 0 "a bead absent from its OWN store is proven absent"
has "$ERR" "absent from beta" "  ... saying which store answered"
run --present bt-gone
eq "$RC" 1 "  ... and --present refuses it"

# --- every unproven shape refuses, and none of them reads as absence --------
run --absent zz-nope
eq "$RC" 3 "an unknown prefix is unproven, never absent"
has "$ERR" "no rig carries the prefix 'zz'" "  ... naming the prefix it could not place"
run --present zz-nope
eq "$RC" 3 "  ... and --present is unproven too, so the two are not negations"

run zz-nope
eq "$RC" 1 "the same unknown prefix is a plain refusal in resolution mode"
eq "$OUT" "" "  ... printing no rig to stdout"

run --absent nodashes
eq "$RC" 3 "an id with no '<prefix>-' segment is unproven"
run nodashes
eq "$RC" 1 "  ... and refuses in resolution mode"

# A bare `<prefix>-` is the fail-open one step past an unknown prefix: `al` DOES
# resolve to alpha, so an empty id would probe alpha's store and read its generic
# not-found as this id's absence. The refusal has to come BEFORE the probe.
run --absent al-
eq "$RC" 3 "a prefix-only id ('<prefix>-') is unproven, never absent, even when its prefix resolves"
run al-
eq "$RC" 1 "  ... and refuses in resolution mode"
eq "$(grep -c "show al- --json" "$FAKE_GC_LOG" || true)" "0" \
  "  ... and no store was probed about 'al-' — the refusal precedes any lookup"

FAKE_RIGS_FAIL=1 run --absent al-gone
eq "$RC" 3 "an unreadable rig list is unproven, not absent"
has "$ERR" "could not read" "  ... reported apart from 'no such prefix', which has a different repair"
FAKE_RIGS_FAIL=1 run al-lives
eq "$RC" 3 "  ... and resolution reports it apart from a prefix nobody carries"

printf 'not a rig list\n' > "$TMP/garbage.json"
FAKE_RIGS="$TMP/garbage.json" run --absent al-gone
eq "$RC" 3 "a rig list that is not one is unproven, not a prefix nobody carries"
has "$ERR" "did not answer with a rig list" "  ... and says the answer was the wrong shape"

run --absent vd-anything
eq "$RC" 3 "a rig that reports no path is a store that cannot be asked"
has "$ERR" "reports no path" "  ... and says so"
run vd-anything
eq "$OUT" void "  ... while the rig NAME still resolves, which needs no store"

# A store that answers nothing at all is the case the exit code cannot tell
# from a miss: real `gc bd --db` exits 1 both ways and prints only on the miss.
rm -rf "$TMP/rigs/beta/.beads"
run --absent bt-lives
eq "$RC" 3 "a store that cannot be read is unproven — an empty payload is not absence"
has "$ERR" "no readable answer" "  ... and says no verdict exists"
mkdir -p "$TMP/rigs/beta/.beads"; mkbead "$TMP/rigs/beta" bt-lives

# --- ambiguity is never guessed --------------------------------------------
cat > "$TMP/dup.json" <<JSON
{"rigs":[{"name":"one","path":"$TMP/rigs/alpha","prefix":"dp"},
         {"name":"two","path":"$TMP/rigs/beta","prefix":"dp"}]}
JSON
FAKE_RIGS="$TMP/dup.json" run dp-lives
eq "$RC" 3 "a prefix two rigs carry refuses rather than picking one"
eq "$OUT" "" "  ... printing no rig to stdout"
has "$ERR" "carried by 2 rigs" "  ... and saying how many carry it"
FAKE_RIGS="$TMP/dup.json" run --absent dp-lives
eq "$RC" 3 "  ... and the verdict is unproven, so neither store's answer is used"

# --- within the owning store, only an EXACT id is a verdict ------------------
# bd resolves a bare id as an exact-or-prefix match. A prefix landing on one
# longer bead is a hit about a DIFFERENT bead; a prefix landing on several
# answers with the same miss object a true not-found uses, and says "ambiguous"
# only on stderr. Neither is a verdict about the id that was asked for, so a
# destructive gate must read both as unproven.
run --present al-uniq
eq "$RC" 3 "a unique-prefix hit names a longer bead, so this id's presence is unproven"
has "$ERR" "only as a prefix" "  ... and says the match was a prefix, not the id"
run --absent al-uniq
eq "$RC" 3 "  ... and --absent is unproven too: a prefix hit is not an absence"

run --absent al-dup
eq "$RC" 3 "an ambiguous reference is unproven, never absent"
has "$ERR" "ambiguous reference" "  ... naming why no verdict is owed"
run --present al-dup
eq "$RC" 3 "  ... and --present refuses the same ambiguity"

# The exact not-found that the ambiguous miss is byte-identical to still
# resolves cleanly to absence — the stderr is what tells the two apart.
run --absent al-nope
eq "$RC" 0 "an exact not-found is still proven absent, distinct from ambiguity"
run --present al-nope
eq "$RC" 1 "  ... and --present reports it absent"

# --- the shape a destructive gate is written in -----------------------------
# `--absent && destroy` must fire on exactly one input and refuse the rest.
fired=""
for id in bt-lives zz-nope nodashes vd-anything dp-lives bt-gone al-uniq al-dup al-; do
  R="$FAKE_RIGS"; [ "$id" = dp-lives ] && R="$TMP/dup.json"
  FAKE_RIGS="$R" "$SUT" --absent "$id" >/dev/null 2>&1 && fired="$fired $id"
done
eq "${fired# }" "bt-gone" "as a gate, --absent authorizes only the bead its own store denies"

# --- usage ------------------------------------------------------------------
run;                    eq "$RC" 2 "no argument is a usage error"
run al-lives extra;     eq "$RC" 2 "a second argument is a usage error"
run --absent a b;       eq "$RC" 2 "a verdict mode takes exactly one id"
run --nope al-lives;    eq "$RC" 2 "an unknown flag is a usage error"
run --help;             eq "$RC" 2 "--help is a usage error"

# Callers bind resolution output directly, so it must carry nothing but the name.
BOUND=$(GC_RIG="$("$SUT" bt-lives)" sh -c 'printf "[%s]" "$GC_RIG"')
eq "$BOUND" "[beta]" "the resolved name binds straight into GC_RIG with no trailing junk"

# Read over the whole run, not one command's stderr: a direct `bd` anywhere
# above would have logged a line here.
eq "$(wc -l < "$FAKE_BD_LOG" | tr -d ' ')" "0" \
  "no probe reached a store through a direct \`bd\` at any point in the run"
# An id whose store never resolved must never have been asked about anywhere:
# the refusal has to come BEFORE a probe, or some store answered for it.
for id in zz-nope nodashes vd-anything dp-lives; do
  eq "$(grep -c "bd --db .* show $id\$" "$FAKE_GC_LOG" || true)" "0" \
    "  ... and no store was probed about $id, whose store never resolved"
done

echo
echo "bead-store: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
