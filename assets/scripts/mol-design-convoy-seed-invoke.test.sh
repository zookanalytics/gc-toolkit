#!/usr/bin/env bash
# Hermetic test for mol-design-convoy's seed-convoy invocation of convoy-seed.sh.
#
# The step promises crash-resume: once `gc.design_convoy_id` is recorded it hands
# the id back as `--convoy <id>` so convoy-seed.sh reuses the first convoy instead
# of minting a second. That hand-back only works if `--convoy` and the id reach
# convoy-seed.sh as two separate arguments. The agent shell is zsh, which does
# NOT word-split an unquoted ${CONVOY_ID:+--convoy "$CONVOY_ID"}: it arrives as
# the single argument `--convoy <id>`, convoy-seed.sh rejects it as an unknown
# argument, and the resume fails on exactly the path it exists for. The shipped
# form builds the argv as an array; this reverts by one edit, so it is pinned
# from both sides and executed under every shell present (tk-2cy79 is the same
# bug one script over).
#
# EXECUTES the real snippet extracted verbatim between the formula markers, so
# the test cannot drift from the shipped instruction. No live city or network.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-design-convoy.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-seed-invoke-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

[ -f "$TOML" ] || { echo "formula not found: $TOML" >&2; exit 1; }

# Pull the lines between the markers (exclusive). A rename or removal of the
# markers — what a wholesale reconciliation against base does — yields nothing
# and the checks below fail loudly.
extract() {
  awk -v m="$1" '
    $0 ~ ("# >>> " m "$") {f=1; next}
    $0 ~ ("# <<< " m "$") {f=0}
    f' "$TOML"
}

BLOCK="$(extract seed-convoy-invoke)"

[ -n "$BLOCK" ] \
  && ok "seed-convoy-invoke extracted between markers" \
  || bad "seed-convoy-invoke extraction EMPTY — markers missing from $TOML"

# A TOML triple-quoted string eats a trailing backslash (line-ending escape) and
# silently joins lines, so the shipped snippet must be backslash-free.
case "$BLOCK" in
  *\\*) bad "snippet contains a backslash — TOML escapes will mangle it" ;;
  *)    ok  "snippet is backslash-free" ;;
esac

# Pinned from both sides: the argv is an array, and the unquoted form zsh will
# not split is gone.
case "$BLOCK" in
  *'"${SEED_ARGS[@]}"'*) ok 'invocation expands the argv array "${SEED_ARGS[@]}"' ;;
  *) bad 'invocation does not expand an argv array — zsh will not split a bare ${..:+..}' ;;
esac
case "$BLOCK" in
  *'${CONVOY_ID:+'*) bad 'the unquoted ${CONVOY_ID:+--convoy ...} form is back — zsh passes it as one argument (tk-2cy79 class)' ;;
  *) ok 'no unquoted ${CONVOY_ID:+--convoy ...} form (which zsh does not word-split)' ;;
esac

# --- Execute the snippet under each available shell. --------------------------
# The convoy-seed.sh stub records argv one element per line, then parses it the
# way the real script does (assets/scripts/convoy-seed.sh): an unrecognized
# argument is fatal. So the glued `--convoy <id>` the old form produced under zsh
# makes the stub exit nonzero, exactly as the real script does, and the argv
# transcript shows whether --convoy and the id arrived separate or fused.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/convoy-seed.sh" <<'STUB'
#!/usr/bin/env bash
: > "$ARGV_OUT"
for a in "$@"; do printf '%s\n' "$a" >> "$ARGV_OUT"; done
IDF=""
while [ $# -gt 0 ]; do
  case "$1" in
    --name)    shift 2 ;;
    --convoy)  shift 2 ;;
    --id-file) IDF="${2:-}"; shift 2 ;;
    --json)    shift ;;
    *)         echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$IDF" ] && printf 'cv-stub\n' > "$IDF"
printf '{"convoy_id":"cv-stub","branch":"integration/cv-stub"}\n'
exit 0
STUB
chmod +x "$TMP/bin/convoy-seed.sh"

# run_block <shell> <convoy_id>: runs the extracted block under <shell> with the
# step's variables in the environment, writes argv to $TMP/argv.out, and echoes
# the resulting SEED_RC.
run_block() {
  local sh="$1" cid="$2"
  {
    printf 'SEED_RC=0\n'
    printf '%s\n' "$BLOCK"
    printf 'printf "SEED_RC=%%s\\n" "$SEED_RC"\n'
  } > "$TMP/run.sh"
  SCRIPTS="$TMP/bin" INITIATIVE="design the thing" CONVOY_ID="$cid" \
    IDFILE="$TMP/idfile" ARGV_OUT="$TMP/argv.out" \
    "$sh" "$TMP/run.sh"
}

SHELLS=(bash)
if command -v zsh >/dev/null 2>&1; then
  SHELLS+=(zsh)
else
  echo "note - zsh not present; executing under bash only (the source-pin above still guards the zsh case)"
fi

for sh in "${SHELLS[@]}"; do
  # Resume: CONVOY_ID set -> --convoy and the id must arrive as TWO tokens, and
  # convoy-seed.sh must accept them.
  rc_out="$(run_block "$sh" "cv-seed-1")"
  seed_rc="$(printf '%s' "$rc_out" | sed -n 's/^SEED_RC=//p')"
  eq "$seed_rc" "0" "[$sh] resume: convoy-seed.sh accepted the argv (SEED_RC=0)"
  if grep -qxF -- '--convoy' "$TMP/argv.out" && grep -qxF -- 'cv-seed-1' "$TMP/argv.out"; then
    ok "[$sh] resume: --convoy and the id arrive as separate arguments"
  else
    bad "[$sh] resume: --convoy/id not separate (argv: $(tr '\n' '|' < "$TMP/argv.out"))"
  fi
  if grep -qxF -- '--convoy cv-seed-1' "$TMP/argv.out"; then
    bad "[$sh] resume: --convoy and the id collapsed into one argument"
  else
    ok "[$sh] resume: --convoy was not fused to the id"
  fi
  # Fresh: CONVOY_ID empty -> no --convoy at all.
  run_block "$sh" "" >/dev/null
  if grep -qxF -- '--convoy' "$TMP/argv.out"; then
    bad "[$sh] fresh: --convoy present though no convoy id was recorded"
  else
    ok "[$sh] fresh: no --convoy when there is no recorded convoy"
  fi
done

echo
echo "seed-invoke: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
