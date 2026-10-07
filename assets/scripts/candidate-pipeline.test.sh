#!/usr/bin/env bash
# Hermetic test for the witness-patrol CANDIDATE PIPELINE.
#
# THE GUARDRAIL: mol-witness-patrol's recover-orphaned-beads builds its candidate
# set as ONE pipeline: a single `gc bd list` of both live statuses, a control-byte
# strip, then host-bead-skip, downstream-court-skip and topology-root-skip on
# stdin. It prints one `<bead> <owner>` row per candidate, and the listing never
# sits in a shell variable. A step that leaves the agent to combine two listings
# and chain the filters gets the JSON held in a variable and re-fed with
# `echo "$X" | jq`. The agent's shell is zsh, whose builtin echo expands the
# escapes inside JSON strings, so jq rejects the listing and the cycle loses
# every candidate.
#
# A failed listing must not read as a rig with nothing to recover, so the block
# reports a listing that does not parse instead of printing no rows.
#
# This test EXECUTES the real block extracted verbatim from the formula (between
# the candidate-pipeline markers) against a stub gc that serves a fixture
# listing. It runs the block under bash, under bash with xpg_echo set (whose
# echo expands escapes the way zsh's does, so the hazard reproduces where zsh is
# not installed), and under zsh where it is. No live city, Dolt, network, or
# sessions — only jq, a stub and a tmpdir.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-witness-patrol.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-candidate-pipeline-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }

# --- Extract the REAL block from the formula. --------------------------------
# Pulls the lines between the markers (exclusive). If the markers or the block
# are removed/renamed, extraction yields nothing and the check below fails
# loudly — the guardrail cannot silently disappear.
BLOCK="$(awk '
  /# >>> candidate-pipeline$/ {f=1; next}
  /# <<< candidate-pipeline$/ {f=0}
  f' "$TOML")"

[ -n "$BLOCK" ] \
  && ok "block extracted between candidate-pipeline markers" \
  || bad "block extraction EMPTY — markers missing from $TOML"

printf '%s\n' "$BLOCK" > "$TMP/block.sh"
bash -n "$TMP/block.sh" \
  && ok "extracted block is syntactically valid bash" \
  || bad "extracted block failed bash -n"

case "$BLOCK" in
  *'\'*) bad "the block carries a backslash — TOML triple-quote eats continuations" ;;
  *)     ok "the block is backslash-free, as the formula header requires" ;;
esac

# The three filters are stages of this one pipeline, in this order: the owner
# stamp first, then the state exclusion, then the kind exclusion.
STAGES=$(printf '%s\n' "$BLOCK" | sed -n 's/^# >>> \([a-z-]*\)$/\1/p' | paste -sd ' ' -)
eq "$STAGES" "host-bead-skip downstream-court-skip topology-root-skip" \
   "host-bead-skip, downstream-court-skip and topology-root-skip are stages of the one pipeline"

# --- Stub gc. ----------------------------------------------------------------
# Serves the fixture listing for exactly the one listing the block may make, and
# refuses anything else, so a step that goes back to two listings (or any other
# shape) fails here. Like the real gc bd, it names its store on stderr.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GC_STUB_LOG"
echo 'gc bd: answering from the rig "stub" store' >&2
if [ "$*" = "bd list --status=in_progress,open --json --limit=0" ]; then
  cat "$GC_STUB_LISTING"
  exit "${GC_STUB_RC:-0}"
fi
echo "stub gc: unexpected call: $*" >&2
exit 64
STUB
chmod +x "$TMP/bin/gc"

# --- Fixtures. ---------------------------------------------------------------
# w1  owned work bead whose text carries JSON escapes -> KEEP (owner: assignee)
# s1  workflow STEP pinned to a session id            -> KEEP (owner: session id)
# u1  names no owner                                  -> DROP (host-bead-skip)
# d1  owned, in-flight PR                             -> DROP (downstream-court-skip)
# h1  owned, human gate                               -> DROP (downstream-court-skip)
# r1  graph.v2 topology root                          -> DROP (topology-root-skip)
# c1  owned, a RAW control byte and a raw tab inside a string -> KEEP only
#     because the strip runs ahead of the first jq
#
# w1's description is the shape zsh's echo corrupts: a \n escape, an escaped
# backslash ahead of $ and (, a \t escape and a \u001f escape.
W1='  {"id":"w1","assignee":"gc-toolkit/gc-toolkit.furiosa","description":"line one\nline two \\$HOME \\(x) a\ttab a\u001fsep a \"quote\"","metadata":{}}'
S1='  {"id":"s1","metadata":{"gc.session_id":"lx-dead","gc.session_name":"slot-1","gc.step_ref":"mol-polecat-work.implement"}}'
U1='  {"id":"u1","assignee":"","metadata":{}}'
D1='  {"id":"d1","assignee":"gc-toolkit/gc-toolkit.refinery","metadata":{"merge_result":"pull_request"}}'
H1='  {"id":"h1","assignee":"gc-toolkit/gc-toolkit.refinery","metadata":{"gc.routed_to":"human"}}'
R1='  {"id":"r1","metadata":{"gc.kind":"workflow","gc.session_name":"gc-toolkit--gc-toolkit__polecat-1-pool"}}'

# listing <file> [raw] — writes the listing the stub serves, pretty-printed one
# bead per line the way bd prints it. With `raw`, c1 joins it.
listing() {
  {
    printf '[\n'
    printf '%s,\n' "$W1" "$S1" "$U1" "$D1" "$H1"
    if [ "${2:-}" = raw ]; then
      printf '  {"id":"c1","assignee":"gc-toolkit/gc-toolkit.rictus","description":"a raw%bbyte and a raw%btab","metadata":{}},\n' '\001' '\t'
    fi
    printf '%s\n' "$R1"
    printf ']\n'
  } > "$1"
}

listing "$TMP/clean.json"
listing "$TMP/raw.json" raw
printf 'not json at all\n' > "$TMP/garbage.json"
printf '[]\n' > "$TMP/empty.json"
: > "$TMP/nothing.json"

# --- Premises: the fixtures exercise both hazards. ---------------------------
jq -e 'length == 6' "$TMP/clean.json" >/dev/null \
  && ok "(premise) the clean fixture is valid JSON as bd prints it" \
  || bad "(premise) the clean fixture does not parse"
if jq length "$TMP/raw.json" >/dev/null 2>&1; then
  bad "(premise) the raw-byte fixture parses without the strip, so it proves nothing"
else
  ok "(premise) the raw-byte fixture aborts a bare jq, so the strip is load-bearing"
fi

# The failure the pipeline exists to prevent, reproduced on the same bytes: an
# echo that expands escapes corrupts the captured listing, printf does not.
# echo_corrupts <shell...> — 0 when that shell's echo breaks the fixture.
echo_corrupts() {
  local echo_rc=0 printf_rc=0
  "$@" -c 'X=$(cat "$1"); echo "$X" | jq length' _ "$TMP/clean.json" >/dev/null 2>&1 || echo_rc=$?
  "$@" -c 'X=$(cat "$1"); printf "%s\n" "$X" | jq length' _ "$TMP/clean.json" >/dev/null 2>&1 || printf_rc=$?
  [ "$echo_rc" -ne 0 ] && [ "$printf_rc" -eq 0 ]
}
echo_corrupts bash -O xpg_echo \
  && ok "(premise) under bash -O xpg_echo, echo \"\$X\" | jq rejects the fixture and printf parses it" \
  || bad "(premise) the fixture does not reproduce the echo corruption under bash -O xpg_echo"

SHELLS=(bash "bash -O xpg_echo")
if command -v zsh >/dev/null 2>&1; then
  SHELLS+=("zsh -f")
  echo_corrupts zsh -f \
    && ok "(premise) under zsh, echo \"\$X\" | jq rejects the fixture and printf parses it" \
    || bad "(premise) the fixture does not reproduce the zsh echo corruption"
else
  echo "skip - zsh not installed; the zsh premise and zsh run are skipped"
fi

# run <shell> <listing> [rc] — runs the extracted block under <shell> (a command
# and its flags, as one word) against the stub. Stdout goes to $TMP/out, stderr
# to $TMP/err, the stub's calls to $TMP/calls. TMPDIR is a fresh empty
# directory, so a leftover file is visible.
run() {
  local -a sh
  read -r -a sh <<< "$1"
  rm -rf "$TMP/runtmp"; mkdir -p "$TMP/runtmp"
  : > "$TMP/calls"
  local rc=0
  PATH="$TMP/bin:$PATH" TMPDIR="$TMP/runtmp" GC_STUB_LOG="$TMP/calls" \
    GC_STUB_LISTING="$2" GC_STUB_RC="${3:-0}" \
    "${sh[@]}" "$TMP/block.sh" > "$TMP/out" 2> "$TMP/err" || rc=$?
  return "$rc"
}

rows() { sort "$TMP/out" | paste -sd ',' -; }
said_unreadable() { grep -q 'did not parse' "$TMP/err"; }
leftovers() { find "$TMP/runtmp" -mindepth 1 | wc -l | tr -d ' '; }

WANT="c1 gc-toolkit/gc-toolkit.rictus,s1 lx-dead,w1 gc-toolkit/gc-toolkit.furiosa"

for SH in "${SHELLS[@]}"; do
  if run "$SH" "$TMP/raw.json"; then ok "[$SH] the block exits 0"; else bad "[$SH] the block exited non-zero"; fi
  eq "$(rows)" "$WANT" \
     "[$SH] prints one <bead> <owner> row per candidate: drops unowned, downstream and root beads; keeps c1 through its raw byte"
  if said_unreadable; then bad "[$SH] a readable listing reported 'did not parse'"; else ok "[$SH] a readable listing reports no parse failure"; fi
  eq "$(cat "$TMP/calls")" "bd list --status=in_progress,open --json --limit=0" \
     "[$SH] makes exactly one listing, of both live statuses"
  eq "$(leftovers)" "0" "[$SH] leaves no temp file behind"
done

# --- A failed listing is not an empty rig. -----------------------------------
for SH in "${SHELLS[@]}"; do
  run "$SH" "$TMP/garbage.json" || true
  eq "$(rows)" "" "[$SH] a listing that is not JSON prints no rows"
  if said_unreadable; then ok "[$SH] ...and says the listing did not parse"; else bad "[$SH] a non-JSON listing read as an empty rig"; fi

  run "$SH" "$TMP/nothing.json" 1 || true
  eq "$(rows)" "" "[$SH] a listing that failed with no output prints no rows"
  if said_unreadable; then ok "[$SH] ...and says the listing did not parse"; else bad "[$SH] a failed listing read as an empty rig"; fi
  eq "$(leftovers)" "0" "[$SH] a failed listing leaves no temp file behind"

  run "$SH" "$TMP/empty.json" || true
  eq "$(rows)" "" "[$SH] an empty listing prints no rows"
  if said_unreadable; then bad "[$SH] an empty listing was reported as a parse failure"; else ok "[$SH] ...and is not a parse failure"; fi
done

echo
echo "candidate-pipeline: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
