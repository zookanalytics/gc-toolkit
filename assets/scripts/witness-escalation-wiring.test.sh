#!/usr/bin/env bash
# Hermetic test for mol-witness-patrol's ESCALATION WIRING (tk-z4aka / tk-yxwr7 P3).
#
# escalation-gate.sh has strong coverage of its own behaviour, but nothing
# covered the formula lines that CALL it — and the wiring is where the storm
# comes back. Every one of these edits leaves the script's tests green while
# reopening the bug:
#
#   - dropping `--anchor`      -> no dedup key at all
#   - dropping `--state`       -> the gate becomes a mute: real news (a new head
#                                 oid, an approval) waits out the full cooldown
#   - moving the SCRIPTS_DIR resolution out of the sending shell -> each tool
#     call is a fresh shell, so `$SCRIPTS_DIR` is empty, `/escalation-gate.sh`
#     fails, and NOTHING is sent — silent mute, worse than the storm
#   - replacing the gated call with a bare `gc mail send` -> the original bug,
#     verbatim
#
# So this executes the wiring EXTRACTED VERBATIM from the formula (between the
# `escalation-wiring-*` markers) against stubs, and asserts what reaches the
# gate. No live city, Dolt, mail, network, or real repo — `gc`, `gh` and `git`
# are all stubbed, and `git` is stubbed specifically so the "$(git rev-parse
# --show-toplevel)/assets/scripts" candidate cannot silently resolve to the real
# checkout this test is running inside.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-witness-patrol.toml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { case "$2" in *"$1"*) ok "$3" ;; *) bad "$3 (not found in: $2)" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }

# --- Stubs --------------------------------------------------------------------
# Each stub records its argv as a JSON array, one element per argument. A
# line-oriented log would be ambiguous here: the body is always multi-line, so
# "next line" cannot be told apart from "second line of this argument".
export STUB_LOG="$TMP/log"
mkdir -p "$STUB_LOG" "$TMP/bin"
export PATH="$TMP/bin:$PATH"

make_gate() { # make_gate <dir> — plant a stub gate the resolution loop can find
  mkdir -p "$1"
  cat > "$1/escalation-gate.sh" <<'GATE'
#!/usr/bin/env bash
for a in "$@"; do printf '%s' "$a" | jq -Rs .; done | jq -s . > "$STUB_LOG/gate-args.json"
echo "gate" >> "$STUB_LOG/calls"
exit 0
GATE
  chmod +x "$1/escalation-gate.sh"
}

# `gc bd show` returns the anchor; PR_NUMBER (exported per case) decides whether
# it is PR-backed, which is what selects the STATE fingerprint branch.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
if [ "${1:-}" = "bd" ] && [ "${2:-}" = "show" ]; then
  jq -nc --arg id "$3" --arg pr "${PR_NUMBER:-}" '
    [{ id: $id,
       status: "open",
       updated_at: "2026-07-27T04:00:00Z",
       metadata: ({ merge_result: "pre_open_gate" }
                  + (if $pr == "" then {} else { pr_number: $pr } end)) }]'
  exit 0
fi
if [ "${1:-}" = "mail" ] && [ "${2:-}" = "send" ]; then
  # Drop the "mail send" subcommand so element 0 is the recipient.
  for a in "${@:3}"; do printf '%s' "$a" | jq -Rs .; done | jq -s . > "$STUB_LOG/mail-args.json"
  echo "mail" >> "$STUB_LOG/calls"
  exit 0
fi
exit 0
GC

# The fingerprint the formula asks for: headRefOid/reviewDecision/mergeStateStatus.
cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "oid123/APPROVED/BLOCKED"
GH

# Not a repo, unless a case exports STUB_TOPLEVEL. Without this the middle
# resolution candidate would find the real gc-toolkit checkout and the
# "nothing resolves" case could never be tested.
cat > "$TMP/bin/git" <<'GIT'
#!/usr/bin/env bash
if [ "${1:-}" = "rev-parse" ] && [ "${2:-}" = "--show-toplevel" ]; then
  [ -n "${STUB_TOPLEVEL:-}" ] || exit 128
  echo "$STUB_TOPLEVEL"; exit 0
fi
exit 0
GIT
chmod +x "$TMP/bin/gc" "$TMP/bin/gh" "$TMP/bin/git"

reset() { rm -f "$STUB_LOG"/*; }
# The value that followed <flag> in the recorded argv, "" if the flag is absent.
arg_after() { jq -r --arg k "$2" 'index($k) as $i | if $i == null then "" else (.[$i+1] // "") end' \
                "$STUB_LOG/$1" 2>/dev/null; }
gate_arg() { arg_after gate-args.json "$1"; }
mail_arg() { arg_after mail-args.json "$1"; }
mail_to()  { jq -r '.[0] // ""' "$STUB_LOG/mail-args.json" 2>/dev/null; }
count()    { local n; n=$(grep -c "^$1\$" "$STUB_LOG/calls" 2>/dev/null); printf '%s' "${n:-0}"; }

# --- Extract the wiring from the formula --------------------------------------
extract() { # extract <marker> -> the block, placeholders substituted
  awk -v m="$1" '
    $0 ~ ("# >>> " m "$") {f=1; next}
    $0 ~ ("# <<< " m "$") {f=0}
    f' "$TOML" | sed 's/<bead-id>/su-lou.10.8/g; s/<bead>/su-lou.10.8/g'
}

for marker in escalation-wiring-discipline escalation-wiring-refinery; do
  block="$(extract "$marker")"
  [ -n "$block" ] && ok "$marker: extracted between markers" \
    || bad "$marker: extraction EMPTY — markers missing from $TOML"
  printf '%s\n' "$block" > "$TMP/$marker.sh"

  # A TOML `"""` block silently collapses a trailing backslash continuation, so
  # syntax-check what actually ships, not what it looks like in the editor.
  bash -n "$TMP/$marker.sh" \
    && ok "$marker: extracted wiring is valid bash" \
    || bad "$marker: extracted wiring failed bash -n"

  # The resolution loop must live in the SAME block as the send.
  has 'escalation-gate.sh' "$block" "$marker: resolves the gate script"
  has 'if [ -x "$cand/escalation-gate.sh" ]' "$block" "$marker: resolution loop is in the sending shell"

  # Ordering: the gated call comes first, the bare mail only in the else arm.
  gate_line=$(grep -n 'SCRIPTS_DIR/escalation-gate.sh' "$TMP/$marker.sh" | head -1 | cut -d: -f1)
  mail_line=$(grep -n 'gc mail send' "$TMP/$marker.sh" | head -1 | cut -d: -f1)
  if [ -n "$gate_line" ] && [ -n "$mail_line" ] && [ "$gate_line" -lt "$mail_line" ]; then
    ok "$marker: gated call comes first; the bare mail is the fallback arm"
  else
    bad "$marker: gate must precede the fallback mail (gate@${gate_line:-none} mail@${mail_line:-none})"
  fi
done

# --- RIGROOT: the gc-toolkit rig resolves through GC_RIG_ROOT -----------------
reset
make_gate "$TMP/rig/assets/scripts"
PR_NUMBER=35 GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" bash "$TMP/escalation-wiring-refinery.sh" >/dev/null 2>&1
eq "$(count gate)" "1" "RIGROOT: escalates through the gate"
eq "$(count mail)" "0" "RIGROOT: sends no bare mail"
eq "$(gate_arg --anchor)" "su-lou.10.8" "RIGROOT: passes --anchor (the dedup key)"
eq "$(gate_arg --state)" "oid123/APPROVED/BLOCKED" \
   "RIGROOT: --state is the PR fingerprint that lets real news through"
has "QUEUE_HEALTH" "$(gate_arg --subject)" "RIGROOT: passes --subject"
has "Recommendation" "$(gate_arg --body)" "RIGROOT: passes --body intact (multi-line)"

# --- TOPLEVEL: resolving from the checkout ------------------------------------
reset
make_gate "$TMP/repo/assets/scripts"
PR_NUMBER=35 GC_RIG_ROOT="" GC_CITY_PATH="" STUB_TOPLEVEL="$TMP/repo" \
  bash "$TMP/escalation-wiring-refinery.sh" >/dev/null 2>&1
eq "$(count gate)" "1" "TOPLEVEL: resolves via git rev-parse --show-toplevel"
eq "$(count mail)" "0" "TOPLEVEL: sends no bare mail"

# --- CITYPATH: the other three rigs have no assets/scripts of their own -------
reset
make_gate "$TMP/city/rigs/gc-toolkit/assets/scripts"
PR_NUMBER=35 GC_RIG_ROOT="" GC_CITY_PATH="$TMP/city" bash "$TMP/escalation-wiring-refinery.sh" >/dev/null 2>&1
eq "$(count gate)" "1" "CITYPATH: a rig without its own assets/scripts still resolves the gate"
eq "$(count mail)" "0" "CITYPATH: sends no bare mail"

# --- NOPR: a bead with no PR still gets a real fingerprint --------------------
# The fallback jq is the easiest thing in the wiring to break silently: an empty
# --state makes every non-PR anchor look identical, so the gate suppresses until
# the cooldown and the change never surfaces.
reset
make_gate "$TMP/rig/assets/scripts"
PR_NUMBER="" GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" bash "$TMP/escalation-wiring-refinery.sh" >/dev/null 2>&1
eq "$(gate_arg --state)" "open/pre_open_gate/2026-07-27T04:00:00Z" \
   "NOPR: --state falls back to status/merge_result/updated_at"

# --- FALLBACK: an unsynced rig mails directly, it does not go silent ----------
reset
PR_NUMBER=35 GC_RIG_ROOT="$TMP/absent" GC_CITY_PATH="$TMP/absent" \
  bash "$TMP/escalation-wiring-refinery.sh" >/dev/null 2>&1
eq "$(count gate)" "0" "FALLBACK: no gate to call"
eq "$(count mail)" "1" "FALLBACK: still escalates directly — old behaviour, not a dropped escalation"
eq "$(mail_to)" "mayor/" "FALLBACK: still addressed to the mayor"
has "QUEUE_HEALTH" "$(mail_arg -s)" "FALLBACK: and carries the same subject"

# --- DISCIPLINE: the general block every step is told to copy -----------------
reset
make_gate "$TMP/rig/assets/scripts"
GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" bash "$TMP/escalation-wiring-discipline.sh" >/dev/null 2>&1
eq "$(count gate)" "1" "DISCIPLINE: escalates through the gate"
eq "$(count mail)" "0" "DISCIPLINE: sends no bare mail"
eq "$(gate_arg --anchor)" "su-lou.10.8" "DISCIPLINE: passes --anchor"
[ -n "$(gate_arg --state)" ] && ok "DISCIPLINE: passes --state" || bad "DISCIPLINE: passes --state"

reset
GC_RIG_ROOT="$TMP/absent" GC_CITY_PATH="$TMP/absent" \
  bash "$TMP/escalation-wiring-discipline.sh" >/dev/null 2>&1
eq "$(count mail)" "1" "DISCIPLINE: falls back to a direct mail when the script is absent"

echo
echo "witness-escalation-wiring.test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
