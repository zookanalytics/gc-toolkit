#!/usr/bin/env bash
# Hermetic test for doctor/check-epic-closed-implies-ruled (I15). Stub gc/bd only.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-check-epic-ruled-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2')" ;; *) ok "$3" ;; esac; }

mkdir -p "$TMP/bin" "$TMP/stores" "$TMP/alpha"
cat > "$TMP/rigs.json" <<EOF
{"rigs":[{"name":"alpha","path":"$TMP/alpha"}]}
EOF
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "rig list")
    rc="${RIGS_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"; cat "$RIGS_JSON" ;;
  "bd "*)    shift; VIA_GC_BD=1 exec "$(dirname "$0")/bd" "$@" ;;
  *) exit 0 ;;
esac
GC
# Deliberately looser than bd: it serves the whole store whatever the query
# filters on (the --type=epic / --status closed scoping is bd's, proven here by
# asserting the query shape in BD_ARGS), so a fixture controls exactly the rows.
cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
[ -n "${VIA_GC_BD:-}" ] || { echo "stub bd: called directly, not through gc bd" >&2; exit 127; }
printf '%s\n' "$*" >> "${BD_ARGS:-/dev/null}"
db=""; prev=""
for a in "$@"; do [ "$prev" = "--db" ] && db="$a"; prev="$a"; done
name=$(basename "$(dirname "$db")")
[ "$name" = "${BD_FAIL_STORE:-}" ] && exit 3
f="$STORES/$name.json"; if [ -f "$f" ]; then cat "$f"; else printf '[]'; fi
BD
chmod +x "$TMP/bin/gc" "$TMP/bin/bd"
export PATH="$TMP/bin:$PATH" STORES="$TMP/stores" BD_ARGS="$TMP/bd-args.log"
run_check() { : > "$BD_ARGS"; RIGS_JSON="$TMP/rigs.json" GC_PACK_DIR="$TMP" bash "$CHECK" 2>&1; }
# issue_type is cosmetic here (the check trusts --type=epic from the query); the
# verdict is read from status + metadata.
epic() { printf '{"id":"%s","issue_type":"epic","status":"%s","metadata":%s}' "$1" "$2" "$3"; }
store() { local IFS=,; printf '[%s]' "$*" > "$TMP/stores/alpha.json"; }

# --- 1. a closed epic ruled close passes, and the query is scoped to epics ----
# The close ruling with its outcome is read before the hypothesis, so an Epic
# ruled closed with no hypothesis (E2) passes too.
store "$(epic E1 closed '{"epic_hypothesis":"for X","epic_ruling":"close","epic_ruling_reason":"held"}')" \
      "$(epic E2 closed '{"epic_ruling":"close","epic_ruling_reason":"its work is ordinary flow"}')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "closed epics ruled close pass"
has "$OUT" "OK:" "the pass message is the OK line"
ARGS=$(cat "$BD_ARGS")
has "$ARGS" "--type=epic" "the scan asks only for epics"
has "$ARGS" "--all" "the scan reads open epics too, since a closed Delivery's parent may be open"
hasnt "$ARGS" "--status" "…with no status filter that would hide that parent"
has "$ARGS" "--limit 0" "the scan is not truncated by a default limit"

# --- 2. a STEWARDED (has a hypothesis) closed epic with no ruling is an ERROR -
store "$(epic E3 closed '{"epic_hypothesis":"for X, Y, signal Z"}')"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a stewarded closed epic carrying no epic_ruling is an ERROR"
has "$OUT" "E3" "the unruled epic is named"
has "$OUT" "update E3 --set-metadata epic_ruling=close --set-metadata epic_ruling_reason=" "the remedy records the close ruling and its outcome on the closed epic"
has "$OUT" "reopen E3" "the remedy offers reopening to rule"
hasnt "$OUT" "lifecycle.sh reopen" "the remedy does not offer lifecycle.sh reopen, which refuses an epic"
has "$OUT" "--db $TMP/alpha/.beads" "the remedy names the store the epic lives in"
has "$OUT" "docs/epics.md" "the finding cites the contract"

# --- 2a. a close ruling carries its outcome: a closed epic ruled close with no
# epic_ruling_reason, or one of whitespace alone, is an ERROR naming the field --
store "$(epic E3nr closed '{"epic_hypothesis":"for X","epic_ruling":"close"}')" \
      "$(epic E3ws closed '{"epic_hypothesis":"for X","epic_ruling":"close","epic_ruling_reason":" "}')"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a closed epic ruled close with no outcome is an ERROR"
has "$OUT" "E3nr" "the outcome-less epic is named"
has "$OUT" "E3ws" "the whitespace-outcome epic is named"
has "$OUT" "no outcome (epic_ruling_reason)" "the finding names the missing outcome field"

# --- 2b. continue and shift keep an epic open: a closed epic carrying either was
# closed on a ruling that does not end it, an ERROR naming the ruling ---------
for r in continue shift; do
  store "$(epic "E3$r" closed "{\"epic_hypothesis\":\"for X\",\"epic_ruling\":\"$r\"}")"
  OUT=$(run_check); RC=$?
  eq "$RC" "2" "a closed epic ruled $r (non-terminal) is an ERROR"
  has "$OUT" "E3$r" "the $r-ruled epic is named"
  has "$OUT" "non-terminal ruling '$r'" "the finding names the non-terminal ruling"
done

# --- 3. an empty epic_ruling reads the same as an absent one ------------------
store "$(epic E4 closed '{"epic_hypothesis":"for X","epic_ruling":""}')"
OUT=$(run_check); RC=$?
eq "$RC" "2" "an epic_ruling stamped EMPTY is not a ruling"
has "$OUT" "E4" "the empty-ruling epic is named"

# --- 3b. a present-but-off-enum ruling ("pending", a typo) is not a ruling: the
# enum is continue|shift|close (docs/epics.md), so I15 reads it as unruled. -----
store "$(epic E4off closed '{"epic_hypothesis":"for X","epic_ruling":"pending"}')"
OUT=$(run_check); RC=$?
eq "$RC" "2" "an off-enum epic_ruling ('pending') reads as unruled"
has "$OUT" "E4off" "the off-enum epic is named as an error"

# --- 4. a disposed epic carries its own terminal state -----------------------
store '{"id":"E5","issue_type":"epic","status":"closed","metadata":{"epic_hypothesis":"for X"},"dependencies":[{"issue_id":"E5","depends_on_id":"s-9","type":"supersedes"}]}'
OUT=$(run_check); RC=$?
eq "$RC" "0" "a supersedes edge onto a successor is the explicit disposition the check accepts"
hasnt "$OUT" "E5" "the disposed epic is not named"
has "$OUT" "retired into it" "the disposal is counted"
# The retired successor key alone records nothing a reader acts on.
store "$(epic E5k closed '{"epic_hypothesis":"for X","gc.superseded_by":"s-9"}')"
OUT=$(run_check); RC=$?
eq "$RC" "2" "an epic carrying only the retired gc.superseded_by key is judged"
has "$OUT" "E5k" "…and named"

# --- 5. a closed top-level epic with no hypothesis is an incomplete Epic: an
# ERROR whose remedy records the hypothesis and the close ruling ---------------
store "$(epic E5b closed '{}')"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a closed top-level epic with no hypothesis is an ERROR"
has "$OUT" "epic E5b" "the incomplete Epic is named"
has "$OUT" "incomplete Epic" "…as an incomplete Epic"
has "$OUT" "update E5b --set-metadata epic_hypothesis=\"<hypothesis>\" --set-metadata epic_ruling=close --set-metadata epic_ruling_reason=" "the remedy records its hypothesis and the close ruling with its outcome"
has "$OUT" "reopen E5b" "the remedy offers reopening it"
# A close ruling with no outcome, or a ruling that keeps an epic open, does not
# stand in for the hypothesis either.
for m in '{"epic_ruling":"close"}' '{"epic_ruling":"continue"}'; do
  store "$(epic E5n closed "$m")"
  OUT=$(run_check); RC=$?
  eq "$RC" "2" "a closed epic carrying $m and no hypothesis is an ERROR"
  has "$OUT" "incomplete Epic" "…as an incomplete Epic"
done

# --- 5a. a closed Delivery, an epic with no hypothesis whose parent-child edge
# reaches an epic of the store, open or closed, passes and is counted ----------
delivery() { printf '{"id":"%s","issue_type":"epic","status":"closed","metadata":{},"dependencies":[{"issue_id":"%s","depends_on_id":"%s","type":"parent-child"}]}' "$1" "$1" "$2"; }
for ps in open closed; do
  store "$(epic P5 "$ps" '{"epic_hypothesis":"for X","epic_ruling":"close","epic_ruling_reason":"held"}')" "$(delivery D5 P5)"
  OUT=$(run_check); RC=$?
  eq "$RC" "0" "a closed Delivery whose epic is $ps passes"
  hasnt "$OUT" "epic D5" "…and is not named"
  has "$OUT" "1 closed Delivery epic(s)" "…and is counted"
done

# --- 5b. under a parent that is not an epic of the store, an epic with no
# hypothesis is no Delivery: an ERROR ------------------------------------------
store "$(delivery D5t T5)"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a closed epic with no hypothesis under a parent that is not an epic is an ERROR"
has "$OUT" "epic D5t" "…naming it"
has "$OUT" "incomplete Epic" "…as an incomplete Epic"

# --- 5c. a disposed epic with no hypothesis passes ------------------------------
store '{"id":"E5d","issue_type":"epic","status":"closed","metadata":{},"dependencies":[{"issue_id":"E5d","depends_on_id":"s-9","type":"supersedes"}]}'
OUT=$(run_check); RC=$?
eq "$RC" "0" "a disposed top-level epic with no hypothesis passes"
hasnt "$OUT" "epic E5d" "…and is not named"
has "$OUT" "retired into it" "…and is counted as disposed"

# --- 5d. a closed child epic with a hypothesis of its own is an epic, not a
# Delivery, so it is judged as one ---------------------------------------------
store "$(epic P5h open '{"epic_hypothesis":"for X"}')" \
      '{"id":"C5h","issue_type":"epic","status":"closed","metadata":{"epic_hypothesis":"its own"},"dependencies":[{"issue_id":"C5h","depends_on_id":"P5h","type":"parent-child"}]}'
OUT=$(run_check); RC=$?
eq "$RC" "2" "a closed child epic with its own hypothesis and no ruling is an ERROR"
has "$OUT" "epic C5h" "…naming it"

# --- 6. an open epic is out of scope (only closed epics are judged) -----------
store "$(epic E6 open '{"epic_hypothesis":"for X"}')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an open, unruled epic is not a finding — the ruling is owed only at close"

# --- 7. mixed: only the unruled one is reported -------------------------------
store "$(epic E7 closed '{"epic_hypothesis":"for X","epic_ruling":"close","epic_ruling_reason":"disproven"}')" \
      "$(epic E8 closed '{"epic_hypothesis":"for X"}')" \
      "$(delivery E9 E7)"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a mix flags the unruled epic"
has "$OUT" "E8" "the unruled epic is named"
hasnt "$OUT" "epic E7" "the ruled epic is not named"
hasnt "$OUT" "epic E9" "the Delivery is not flagged as an error"

# --- 7. fail-CLOSED ----------------------------------------------------------
OUT=$(RIGS_RC=1 run_check); RC=$?
eq "$RC" "1" "a failing \`gc rig list\` warns, never passes"
has "$OUT" "cannot determine" "the enumeration failure is named"
OUT=$(BD_FAIL_STORE=alpha run_check); RC=$?
eq "$RC" "1" "an unreadable store warns"
has "$OUT" "NOT checked" "the warning says the store was skipped"
printf 'not json' > "$TMP/stores/alpha.json"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an unparseable store listing warns"
# A VALID {"error":...} object is bd's shape when a query does not resolve
# (bead-context.sh) — unreadable, not "no epics". `.[]?` would iterate the object
# and the downstream `//` swallow the index error, yielding zero rows at exit 0 and
# a false OK; the type guard makes jq error so the store lands in warnings.
printf '{"error":"ledger unavailable"}' > "$TMP/stores/alpha.json"
OUT=$(run_check); RC=$?
eq "$RC" "1" "a store answering with an {error} object warns, never passes"
has "$OUT" "NOT checked" "the error-object store is named as not checked"

# --- 8. offline-safe: the check never calls gh -------------------------------
if grep -qE '(^|[^a-z])gh[[:space:]]' < <(grep -vE '^[[:space:]]*#' "$CHECK"); then
    bad "the check shells out to gh — it is specified ledger-only"
else
    ok "the check is ledger-only (no gh calls)"
fi

# --- 9. disk pressure must not forge an all-clear ----------------------------
# bash backs a `<<<` here-string longer than a pipe buffer with a temp file;
# under disk pressure that file cannot be created and the loop it feeds runs zero
# times, so a store fed through one reads as empty and the check prints its OK
# line. The check stages each enumeration through a checked `mktemp -d` instead.
# This mktemp stub stands in for a full /tmp at each staging point:
# STAGE_FAIL=mktemp fails the command, and STAGE_FAIL=scopes or rows hands back a
# dir in which that staging file cannot be written, because a directory already
# sits at its path. bash's own here-string temp file never goes through the
# mktemp command, so a check that still feeds the scopes loop or the rows loop
# from `<<<` reports the epic and fails the matching case.
cat > "$TMP/bin/mktemp" <<'MK'
#!/usr/bin/env bash
if [ "${STAGE_FAIL:-}" = "mktemp" ]; then
    echo "mktemp: stubbed disk-pressure failure" >&2; exit 1
fi
d="$(dirname "$0")/../stage.$$"
mkdir -p "$d/${STAGE_FAIL:-}" && printf '%s\n' "$d"
MK
chmod +x "$TMP/bin/mktemp"
store "$(epic Edp closed '{"epic_hypothesis":"for X"}')"
# Mirror: through the stub with nothing failed, the fixture yields its finding,
# so the assertions below are not vacuously satisfied by an empty store or a
# broken stub.
OUT=$(run_check); RC=$?
eq "$RC" "2" "mirror: the fixture reports its finding when staging works"
has "$OUT" "epic Edp" "mirror: the finding names the epic"
for fail in mktemp scopes rows; do
  OUT=$(STAGE_FAIL=$fail run_check); RC=$?
  eq "$RC" "1" "a failed $fail staging warns (1): it neither passes (0) nor errors (2)"
  hasnt "$OUT" "OK:" "a failed $fail staging does not forge the OK line"
  hasnt "$OUT" "epic Edp" "a failed $fail staging judges nothing it did not read"
  case "$fail" in
    rows) has "$OUT" "this store was NOT checked" "a failed rows staging names the store it skipped" ;;
    *)    has "$OUT" "not an all-clear" "a failed $fail staging says nothing was scanned" ;;
  esac
done
rm -f "$TMP/bin/mktemp"

echo
echo "check-epic-closed-implies-ruled: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
