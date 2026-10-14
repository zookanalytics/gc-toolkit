#!/usr/bin/env bash
# distiller-file-for-placement.test.sh — mol-feedback-distiller files each
# proposal for the operator's placement sitting, not into the polecat pool.
#
# A prompt-update or engineering bead is new work, so it follows the intake rule
# a finding follows (docs/steering.md): it is filed marked placement=pending and
# routed to no pool, and the sitting places it under an epic or routes it on its
# own. The marker rides the create, so the bead is never in the store without it.
#
# The filing block is extracted verbatim between the
# distiller-file-for-placement markers and EXECUTED against a stubbed gc, so what
# passes is the shipped formula text and not a paraphrase of it. The rest of the
# filing step is read as text, so a route re-introduced beside the block fails
# here too.
#
# Hermetic: no gc, no city.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/../.."
TOML="$REPO/formulas/mol-feedback-distiller.toml"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "missing '$2' in: $1" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3" "found '$2' in: $1" ;; *) ok "$3" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/gctk-distiller-file-test.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT
trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP

echo "── the block extracts ──"
BLOCK="$(awk '
  /# >>> distiller-file-for-placement/ { inb = 1; next }
  /# <<< distiller-file-for-placement/ { inb = 0; next }
  inb' "$TOML")"
if [ -n "$BLOCK" ]; then
  ok "block extracted between distiller-file-for-placement markers"
else
  bad "block extracted between distiller-file-for-placement markers" "no marked block in $TOML"
  printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"; exit 1
fi
# The formula body is a TOML basic string, where a backslash would reach the
# file doubled. The block carries none, so it runs exactly as extracted.
eq "$(printf '%s\n' "$BLOCK" | grep -c '\\' || true)" "0" "the block carries no backslash to unescape"

# The block runs once per surviving proposal, inside the agent's loop, and skips
# a proposal whose create fails with `continue`. One pass of a loop stands in.
# The body is one line, so the stub's log keeps each call on one line.
{ printf 'set -u\nBODY="## Rule: x"; PATTERN=tk-pat\nfor _proposal in 1; do\n'
  printf '%s\n' "$BLOCK"
  printf 'done\n'; } > "$SANDBOX/block.sh"
if bash -n "$SANDBOX/block.sh" 2>"$SANDBOX/syntax.err"; then
  ok "extracted block is syntactically valid bash"
else
  bad "extracted block is syntactically valid bash" "$(cat "$SANDBOX/syntax.err")"
fi

mkdir -p "$SANDBOX/bin"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$SANDBOX/bin/gc" <<'GC'
printf '%s\n' "$*" >> "${STUB_GC_LOG:?}"
case "${1:-} ${2:-}" in
  "bd create")
    [ -n "${STUB_CREATE_FAIL:-}" ] && { printf '%s\n' '{"error":"store refused the create"}'; exit 0; }
    printf '%s\n' '[{"id":"tk-prop"}]' ;;
  *) : ;;
esac
GC
chmod +x "$SANDBOX/bin/gc"
export STUB_GC_LOG="$SANDBOX/gc.log"

run() {
  : > "$STUB_GC_LOG"
  OUT=$(PATH="$SANDBOX/bin:$PATH" bash "$SANDBOX/block.sh" 2>&1); RC=$?
  LOG=$(cat "$STUB_GC_LOG")
}

echo "── a proposal is filed for placement ──"
run
eq "$RC" "0" "the block runs clean"
has "$LOG" "bd create prompt-update:" "the proposal is filed as a prompt-update bead"
CREATE_META=$(printf '%s\n' "$LOG" | grep -F 'bd create' | sed 's/^.*--metadata //;s/ --json.*$//')
printf '%s' "$CREATE_META" | jq -e . >/dev/null 2>&1 \
  && ok "the create's metadata is parseable JSON" || bad "the create's metadata is parseable JSON" "$CREATE_META"
eq "$(printf '%s' "$CREATE_META" | jq -r '.placement // ""' 2>/dev/null)" "pending" \
  "the create marks it placement=pending, which puts it in the sitting's queue"
eq "$(printf '%s' "$CREATE_META" | jq -r '.task_kind // ""' 2>/dev/null)" "prompt-update" "…as a prompt-update"
eq "$(printf '%s' "$CREATE_META" | jq -r '.target // ""' 2>/dev/null)" "main" "…landing on main once built"
eq "$(printf '%s' "$CREATE_META" | jq -r '.merge_strategy // ""' 2>/dev/null)" "mr" "…through the refinery's mr path"
hasnt "$LOG" "gc.routed_to" "and it is routed to no pool"
hasnt "$LOG" "bd update" "with no second write that could leave it unmarked"
has "$OUT" "filed prompt-update tk-prop for placement" "the run says where the bead went"

echo "── a create that fails skips the proposal ──"
STUB_CREATE_FAIL=1 run
eq "$RC" "0" "the run survives a refused create"
has "$OUT" "could not create prompt-update bead for tk-pat (store refused the create); skipping" \
  "the refusal is reported with the store's cause"
hasnt "$LOG" "bd update" "and nothing is written after it"

echo "── the filing step routes nothing ──"
# Read the step from its section 1 heading to section 2, so a route written
# beside the marked block, or a pool resolved for one, fails here.
STEP_TEXT="$(awk '/^## 1\. File one bead per surviving proposal/ { inb = 1 }
                  /^## 2\. Stamp every consumed observation/ { inb = 0 }
                  inb' "$TOML")"
[ -n "$STEP_TEXT" ] && ok "sections 1 and 1b of the filing step read" \
  || bad "sections 1 and 1b of the filing step read" "headings not found in $TOML"
hasnt "$STEP_TEXT" "gc.routed_to" "no route is stamped on a filed bead"
hasnt "$STEP_TEXT" "pool-route.sh" "no pool is resolved for one"
has "$STEP_TEXT" '{"placement":"pending"}' "the engineering bead's create carries the marker too"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
