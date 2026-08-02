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
#   - putting the anchor's own `updated_at` in the fingerprint -> the gate stamps
#     that same anchor before mailing, so its own write makes the next cycle look
#     changed and the item re-mails forever (SELFREOPEN below runs the wiring
#     twice against a stub that advances updated_at on every write)
#   - dropping `--cooldown` -> the configured escalation_cooldown is inert and
#     only the script's built-in default is ever in force
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
#
# The stub is STATE-BACKED, and metadata writes ADVANCE `updated_at`. That is not
# incidental realism: a real `gc bd update` touches the bead it writes, and the
# gate stamps the anchor before mailing, so the anchor's modification time is
# downstream of the gate itself. A stub with a frozen timestamp cannot see the
# P1 self-reopen bug at all — the second cycle would look unchanged for the wrong
# reason and the test would pass over the defect.
#
# `$STUB_LOG/meta` holds the anchor's mutable metadata as `<key>|<value>` lines;
# a case may seed it before the run. `$STUB_LOG/writes` counts writes and is what
# updated_at is derived from.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
S="$STUB_LOG"
[ -f "$S/meta" ]   || : > "$S/meta"
[ -f "$S/writes" ] || printf '0\n' > "$S/writes"

if [ "${1:-}" = "bd" ] && [ "${2:-}" = "show" ]; then
  w=$(cat "$S/writes")
  meta=$(jq -nc --arg pr "${PR_NUMBER:-}" '
    { merge_result: "pre_open_gate", branch: "polecat/su-lou.10.8", target: "main" }
    + (if $pr == "" then {} else { pr_number: $pr } end)')
  while IFS='|' read -r k v; do
    [ -n "$k" ] || continue
    meta=$(printf '%s' "$meta" | jq -c --arg k "$k" --arg v "$v" '. + {($k): $v}')
  done < "$S/meta"
  jq -nc --arg id "$3" --arg ts "$(printf '2026-07-27T04:%02d:00Z' "$w")" --argjson meta "$meta" \
    '[{ id: $id, status: "open", updated_at: $ts, metadata: $meta }]'
  exit 0
fi

if [ "${1:-}" = "bd" ] && [ "${2:-}" = "update" ]; then
  shift 3
  while [ $# -gt 0 ]; do
    case "$1" in
      --set-metadata)
        kv="$2"; k="${kv%%=*}"; v="${kv#*=}"
        grep -v "^$k|" "$S/meta" > "$S/meta.new" 2>/dev/null || true; mv "$S/meta.new" "$S/meta"
        printf '%s|%s\n' "$k" "$v" >> "$S/meta"
        shift 2 ;;
      --unset-metadata)
        grep -v "^$2|" "$S/meta" > "$S/meta.new" 2>/dev/null || true; mv "$S/meta.new" "$S/meta"
        shift 2 ;;
      *) shift ;;
    esac
  done
  printf '%s\n' "$(( $(cat "$S/writes") + 1 ))" > "$S/writes"   # the self-touch
  echo "update" >> "$S/calls"
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
eq "$(gate_arg --state)" "open/pre_open_gate/polecat/su-lou.10.8/main/-" \
   "NOPR: --state falls back to the bead's own hold inputs"
case "$(gate_arg --state)" in
  *2026-07-27T*) bad "NOPR: fingerprint must not contain updated_at (the gate's own write bumps it)" ;;
  *)             ok  "NOPR: fingerprint contains no timestamp" ;;
esac

# --- CHECKMARK: the gate markers are part of the non-PR fingerprint -----------
# For a pre-open anchor, `check.<gate>` flipping IS the news. Leaving it out
# would hold a genuinely changed situation for a full cooldown.
reset
make_gate "$TMP/rig/assets/scripts"
printf 'check.codex|green@oid9\n' > "$STUB_LOG/meta"
PR_NUMBER="" GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" bash "$TMP/escalation-wiring-refinery.sh" >/dev/null 2>&1
eq "$(gate_arg --state)" "open/pre_open_gate/polecat/su-lou.10.8/main/check.codex=green@oid9" \
   "CHECKMARK: a check.<gate> marker is part of the fingerprint"

# --- GHFAIL / GHEMPTY: a PR-backed anchor whose gh lookup yields nothing ------
# `gh pr view` fails (rate limit, auth, deleted PR) or prints an empty
# fingerprint. Passing that through as an EMPTY --state would read as "no state
# tracked" and mute real news until the cooldown, so it must fall back to the
# bead's own inputs.
for ghcase in fail empty; do
  reset
  make_gate "$TMP/rig/assets/scripts"
  if [ "$ghcase" = "fail" ]; then printf '#!/usr/bin/env bash\nexit 1\n' > "$TMP/bin/gh"
  else printf '#!/usr/bin/env bash\necho ""\n' > "$TMP/bin/gh"; fi
  chmod +x "$TMP/bin/gh"
  PR_NUMBER=35 GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" bash "$TMP/escalation-wiring-refinery.sh" >/dev/null 2>&1
  eq "$(gate_arg --state)" "open/pre_open_gate/polecat/su-lou.10.8/main/-" \
     "GH${ghcase}: an unusable PR fingerprint degrades to the bead's, never to empty"
done
printf '#!/usr/bin/env bash\necho "oid123/APPROVED/BLOCKED"\n' > "$TMP/bin/gh"   # restore
chmod +x "$TMP/bin/gh"

# --- COOLDOWN: the configured value must actually reach the gate --------------
# `[vars.escalation_cooldown]` documents an override and the step renders it as
# Config. If the invocation does not pass it, the variable is decoration and only
# the script's built-in default is ever in force.
reset
make_gate "$TMP/rig/assets/scripts"
PR_NUMBER=35 GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" bash "$TMP/escalation-wiring-refinery.sh" >/dev/null 2>&1
eq "$(gate_arg --cooldown)" '{{escalation_cooldown}}' "COOLDOWN: the refinery wiring passes --cooldown"
reset
make_gate "$TMP/rig/assets/scripts"
GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" bash "$TMP/escalation-wiring-discipline.sh" >/dev/null 2>&1
eq "$(gate_arg --cooldown)" '{{escalation_cooldown}}' "COOLDOWN: the discipline wiring passes --cooldown too"

# A NON-DEFAULT rendered value, which is the case the variable exists for.
sed 's/{{escalation_cooldown}}/300/g' "$TMP/escalation-wiring-refinery.sh" > "$TMP/refinery-rendered.sh"
reset
make_gate "$TMP/rig/assets/scripts"
PR_NUMBER=35 GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" bash "$TMP/refinery-rendered.sh" >/dev/null 2>&1
eq "$(gate_arg --cooldown)" "300" "COOLDOWN: a rendered non-default value reaches the gate unchanged"

# --- SELFREOPEN: the gate's own stamp must not reopen the fingerprint ---------
# THE P1 REGRESSION. This runs the REAL gate, not the recording stub, twice over
# an unchanged non-PR anchor. The gate stamps `escalated.witness` on that anchor
# before mailing, and the `gc` stub advances `updated_at` on every write — so any
# fingerprint built from the anchor's modification time differs on cycle 2
# BECAUSE THE GATE RAN, and the item re-mails every patrol forever.
#
# It also exercises the unrendered `--cooldown {{escalation_cooldown}}` the
# --root-only pour actually ships: cycle 1 must still deliver.
mkdir -p "$TMP/realrig/assets/scripts"
cp "$HERE/escalation-gate.sh" "$TMP/realrig/assets/scripts/escalation-gate.sh"
chmod +x "$TMP/realrig/assets/scripts/escalation-gate.sh"
reset
PR_NUMBER="" GC_RIG_ROOT="$TMP/realrig" GC_CITY_PATH="" bash "$TMP/escalation-wiring-refinery.sh" >/dev/null 2>&1
eq "$(count mail)" "1" "SELFREOPEN: cycle 1 escalates (an unrendered --cooldown still delivers)"
PR_NUMBER="" GC_RIG_ROOT="$TMP/realrig" GC_CITY_PATH="" bash "$TMP/escalation-wiring-refinery.sh" >/dev/null 2>&1
eq "$(count mail)" "1" "SELFREOPEN: cycle 2 over an unchanged anchor is SUPPRESSED, not re-mailed"

# ...and a genuine change still gets through on the very next cycle.
printf 'check.codex|green@oid9\n' >> "$STUB_LOG/meta"
PR_NUMBER="" GC_RIG_ROOT="$TMP/realrig" GC_CITY_PATH="" bash "$TMP/escalation-wiring-refinery.sh" >/dev/null 2>&1
eq "$(count mail)" "2" "SELFREOPEN: a real state change still escalates immediately — dedup, not mute"

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
