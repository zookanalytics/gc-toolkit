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
#   - dropping a var from the `next-iteration` pour -> each wisp is ONE iteration
#     and the next is poured `--root-only`, which materializes no formula
#     defaults, so an unforwarded var arrives unrendered and every cycle after the
#     first silently runs the consumer's own fallback (PROPAGATE below)
#   - fingerprinting `target` instead of `merged_target // target` -> a
#     `pre_open_gate` anchor records its landing target in `merged_target`, so the
#     component collapses to a constant on exactly the anchor kind this fallback
#     exists for, and a retarget waits out the cooldown (MERGEDTARGET below)
#   - reading `gc bd show --json` without stripping control characters -> jq
#     fails, STATE is empty, and the gate reads that as "no state tracked": every
#     real change is then held for a full cooldown (CTRLJSON below)
#   - calling the gate bare instead of `if ! ...; then echo` -> a gate that
#     refuses (it could not BOUND the escalation) takes the best-effort patrol
#     block down with it (GATEFAIL below)
#   - performing a one-shot recovery's irreversible transition after a gate
#     refusal -> the transition CLEARS the condition that would have re-derived
#     the escalation, so "next cycle retries" becomes impossible and the notice is
#     lost silently. ORPHAN_CLOSED must withhold its `gc bd close`; the two whose
#     transition cannot be withheld must say BEST-EFFORT instead of promising a
#     retry (ONESHOT below)
#   - adding a bead-scoped `gc mail send` anywhere else in the formula -> that new
#     one storms, and the gated ones look like the exception (ALLOWLIST below)
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
# SELFREOPEN runs the REAL gate, which takes an anchor+kind mutex. Keep it inside
# this run's tmpdir so a live witness patrolling the same anchor id — or a second
# copy of this test — cannot suppress it.
export GC_ESCALATION_GATE_LOCKDIR="$TMP/locks"

make_gate() { # make_gate <dir> [exit-code] — a stub gate the resolution loop finds
  mkdir -p "$1"
  cat > "$1/escalation-gate.sh" <<GATE
#!/usr/bin/env bash
for a in "\$@"; do printf '%s' "\$a" | jq -Rs .; done | jq -s . > "\$STUB_LOG/gate-args.json"
echo "gate" >> "\$STUB_LOG/calls"
exit ${2:-0}
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

if [ "${1:-}" = "formula" ] && [ "${2:-}" = "show" ]; then
  # The [vars.*] declarations the startup pour materializes (FRAGMENT below).
  # Unset models a lookup that returns nothing — a `gc` too old for the flag, a
  # formula not installed — which must degrade to a pour without the extra vars.
  printf '%s\n' "${STUB_FORMULA_JSON-}"
  exit 0
fi

if [ "${1:-}" = "bd" ] && [ "${2:-}" = "show" ]; then
  # A payload no jq filter can parse: bd printing a diagnostic instead of JSON, or
  # a truncated read. Distinct from STUB_CTRL, which the wiring's `tr -d` cleans —
  # this one survives sanitizing, so the caller's own state build genuinely fails
  # and the never-empty-state guard is what has to hold (STATEGUARD).
  if [ -n "${STUB_BAD_JSON:-}" ]; then printf 'gc: unexpected error\n'; exit 0; fi
  w=$(cat "$S/writes")
  # `${STUB_TARGET-main}` (not `:-`) so a case can set it to "" to model a
  # pre_open_gate anchor that carries NO `target` at all — the shape that made
  # reading `target` alone collapse the landing-target component to "-".
  meta=$(jq -nc --arg pr "${PR_NUMBER:-}" --arg tgt "${STUB_TARGET-main}" '
    { merge_result: "pre_open_gate", branch: "polecat/su-lou.10.8" }
    + (if $tgt == "" then {} else { target: $tgt } end)
    + (if $pr == "" then {} else { pr_number: $pr } end)')
  while IFS='|' read -r k v; do
    [ -n "$k" ] || continue
    meta=$(printf '%s' "$meta" | jq -c --arg k "$k" --arg v "$v" '. + {($k): $v}')
  done < "$S/meta"
  row=$(jq -nc --arg id "$3" --arg ts "$(printf '2026-07-27T04:%02d:00Z' "$w")" --argjson meta "$meta" \
    '[{ id: $id, status: "open", updated_at: $ts, metadata: $meta }]')
  # STUB_CTRL splices a RAW control character into a notes field, which is what bd
  # does with prose. It cannot be built with jq: jq escapes a control character to
  # its escaped \uXXXX form and emits VALID JSON, which is exactly the case that
  # NOT reproduce the bug. Raw, it is invalid JSON an unsanitized read cannot parse.
  if [ -n "${STUB_CTRL:-}" ]; then
    row="${row%\}]}"
    row="$row,\"notes\":\"line$(printf '%b' "$STUB_CTRL")two\"}]"
  fi
  printf '%s\n' "$row"
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

if [ "${1:-}" = "bd" ] && [ "${2:-}" = "close" ]; then
  echo "close" >> "$S/calls"
  exit 0
fi

if [ "${1:-}" = "mail" ] && [ "${2:-}" = "send" ]; then
  # Drop the "mail send" subcommand so element 0 is the recipient.
  for a in "${@:3}"; do printf '%s' "$a" | jq -Rs .; done | jq -s . > "$STUB_LOG/mail-args.json"
  echo "mail" >> "$STUB_LOG/calls"
  # STUB_MAIL_RC models a failing send, which is what the unsynced-rig fallback
  # arm of a one-shot recovery block has to survive without spending its trigger.
  exit "${STUB_MAIL_RC:-0}"
fi
exit 0
GC

# The fingerprint the formula asks for: headRefOid/reviewDecision/mergeStateStatus.
# Records its argv so the WIRING's gh call can be asserted exactly — a stub that
# only echoes proves the gate got a fingerprint, not that the wiring asked for the
# right three fields. `${GH_FINGERPRINT-<default>}` (not `:-`) so a case can set it
# to the empty string to model a PR lookup that returns nothing.
make_gh() { # make_gh [exit-code]
  cat > "$TMP/bin/gh" <<GH
#!/usr/bin/env bash
for a in "\$@"; do printf '%s' "\$a" | jq -Rs .; done | jq -s . > "\$STUB_LOG/gh-args.json"
[ "${1:-0}" -ne 0 ] && exit ${1:-0}
echo "\${GH_FINGERPRINT-oid123/APPROVED/BLOCKED}"
GH
  chmod +x "$TMP/bin/gh"
}
make_gh 0

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
gh_argv()  { jq -r 'join(" ")' "$STUB_LOG/gh-args.json" 2>/dev/null; }
gh_arg()   { arg_after gh-args.json "$1"; }
mail_arg() { arg_after mail-args.json "$1"; }
mail_to()  { jq -r '.[0] // ""' "$STUB_LOG/mail-args.json" 2>/dev/null; }
count()    { local n; n=$(grep -c "^$1\$" "$STUB_LOG/calls" 2>/dev/null); printf '%s' "${n:-0}"; }

# --- Extract the wiring from the formula --------------------------------------
extract() { # extract <marker> -> the block, placeholders substituted
  awk -v m="$1" '
    $0 ~ ("# >>> " m "$") {f=1; next}
    $0 ~ ("# <<< " m "$") {f=0}
    f' "$TOML" | sed 's/<bead-id>/su-lou.10.8/g; s/<bead>/su-lou.10.8/g; s|<agent>|su/polecat-lx-dead1|g'
}

# Every gated block in the formula, not just the two general ones: the
# orphan-recovery notices are bead-scoped too, and an ungated one there is the
# same storm from a different step.
for marker in escalation-wiring-discipline escalation-wiring-refinery \
              escalation-wiring-salvage-refused escalation-wiring-orphan-closed \
              escalation-wiring-orphan-recovered; do
  block="$(extract "$marker")"
  [ -n "$block" ] && ok "$marker: extracted between markers" \
    || bad "$marker: extraction EMPTY — markers missing from $TOML"
  printf '%s\n' "$block" > "$TMP/$marker.sh"

  # A TOML `"""` block silently collapses a trailing backslash continuation, so
  # syntax-check what actually ships, not what it looks like in the editor.
  bash -n "$TMP/$marker.sh" \
    && ok "$marker: extracted wiring is valid bash" \
    || bad "$marker: extracted wiring failed bash -n"

  # NO BACKSLASHES IN A MARKED BLOCK. This test reads the raw TOML, but the
  # witness reads the RENDERED description — and a `"""` string transforms
  # escapes, so `tr -d '\\000-\\037'` in the source ships as `\000-\037` and the
  # two differ. The test would then be green against a command the witness never
  # runs (and the shipped one can be the broken half: an unrendered `\\000-\\037`
  # is a reverse tr range that deletes nothing and errors out). Nothing here needs
  # a backslash, so ban them and keep source and shipped byte-identical.
  case "$block" in
    *\\*) bad "$marker: contains a backslash — TOML \"\"\" will transform it, so what ships differs from what this test runs. Use an escape-free form ([:cntrl:], [:space:])." ;;
    *)    ok "$marker: escape-free, so the extracted block is what actually ships" ;;
  esac

  # The resolution loop must live in the SAME block as the send.
  has 'escalation-gate.sh' "$block" "$marker: resolves the gate script"
  has 'if [ -x "$cand/escalation-gate.sh" ]' "$block" "$marker: resolution loop is in the sending shell"

  # The gated call must be non-fatal. The gate exits non-zero only when it could
  # not BOUND the escalation, and this is a best-effort patrol pass that has to
  # reach its later checks — a bare call makes one refusal the block's exit status.
  has 'if ! "$SCRIPTS_DIR/escalation-gate.sh"' "$block" \
      "$marker: the gated call is wrapped non-fatally (if ! ...)"

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
   "NOPR: --state falls back to the bead's own hold inputs (landing target via target, merged_target absent)"
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

# --- MERGEDTARGET: the landing target is `merged_target // target` ------------
# A `pre_open_gate` anchor records where it intends to land in `merged_target`
# (that is the field pre-open-resolve.sh reads, in this same order); `target` is
# the polecat-era field and may be absent or stale after a retarget. Reading
# `target` alone therefore collapses this component to a constant on exactly the
# anchor kind this fallback exists for, so a retarget — a real change in where
# the work is trying to go — would wait out the whole cooldown.
reset
make_gate "$TMP/rig/assets/scripts"
printf 'merged_target|integration/su-lou\n' > "$STUB_LOG/meta"
PR_NUMBER="" GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" bash "$TMP/escalation-wiring-refinery.sh" >/dev/null 2>&1
eq "$(gate_arg --state)" "open/pre_open_gate/polecat/su-lou.10.8/integration/su-lou/-" \
   "MERGEDTARGET: merged_target wins over target (a retarget is news)"

# Same anchor with NO `target` at all: the pre-open shape that the old reader
# turned into "-". merged_target must still supply the component.
reset
make_gate "$TMP/rig/assets/scripts"
printf 'merged_target|integration/su-lou\n' > "$STUB_LOG/meta"
PR_NUMBER="" STUB_TARGET="" GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" \
  bash "$TMP/escalation-wiring-refinery.sh" >/dev/null 2>&1
eq "$(gate_arg --state)" "open/pre_open_gate/polecat/su-lou.10.8/integration/su-lou/-" \
   "MERGEDTARGET: an anchor with merged_target but no target still fingerprints it"

# Neither field: the placeholder must hold the slot, so the component count stays
# fixed and the remaining fields cannot shift into each other's positions.
reset
make_gate "$TMP/rig/assets/scripts"
PR_NUMBER="" STUB_TARGET="" GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" \
  bash "$TMP/escalation-wiring-refinery.sh" >/dev/null 2>&1
eq "$(gate_arg --state)" "open/pre_open_gate/polecat/su-lou.10.8/-/-" \
   "MERGEDTARGET: neither field present degrades to the placeholder, not to empty"

# --- GHFAIL / GHEMPTY: a PR-backed anchor whose gh lookup yields nothing ------
# `gh pr view` fails (rate limit, auth, deleted PR) or prints an empty
# fingerprint. Two different things must NOT happen. Passing that through as an
# EMPTY --state would read as "no state tracked" and mute real news until the
# cooldown. And substituting the BEAD fingerprint on the same channel — what this
# block used to do — makes the outage itself mail twice (GHFLAP below). So the
# degraded observation goes on its own --kind, carrying a value that names what is
# unavailable and nothing that varies while it is: constant for the whole outage,
# so it mails once and then rides its own cooldown.
for ghcase in fail empty; do
  reset
  make_gate "$TMP/rig/assets/scripts"
  if [ "$ghcase" = "fail" ]; then
    make_gh 1
    PR_NUMBER=35 GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" bash "$TMP/escalation-wiring-refinery.sh" >/dev/null 2>&1
  else
    make_gh 0
    PR_NUMBER=35 GH_FINGERPRINT="" GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" bash "$TMP/escalation-wiring-refinery.sh" >/dev/null 2>&1
  fi
  eq "$(gate_arg --state)" "unavailable/gh/pr-35" \
     "GH${ghcase}: names what is unavailable — not the bead fingerprint, which is not comparable to a PR one"
  eq "$(gate_arg --kind)" "witness-degraded" \
     "GH${ghcase}: on its own channel, so the PR channel's stamp and cooldown survive the outage"
  [ -n "$(gate_arg --state)" ] && ok "GH${ghcase}: and is never EMPTY, which the gate would stamp as 'no state tracked'" \
    || bad "GH${ghcase}: --state must never be empty"
done
make_gh 0   # restore

# --- GHFLAP: an outage must not mail on the way in AND on the way out ---------
# THE REGRESSION (pre-open signoff round 3 on tk-z4aka). The bead fingerprint used
# to stand in for the PR one on the SAME channel whenever `gh pr view` failed. The
# gate compares each --state against the last one sent on that kind, so an
# unchanged PR compared unequal when the substitute appeared AND unequal again
# when the real one came back: one hiccup, two mails, cooldown reset twice, on a
# PR that never moved. Run the REAL gate across a healthy/down/down/healthy
# sequence and count.
mkdir -p "$TMP/realrig/assets/scripts"
cp "$HERE/escalation-gate.sh" "$TMP/realrig/assets/scripts/escalation-gate.sh"
chmod +x "$TMP/realrig/assets/scripts/escalation-gate.sh"
stub_meta() { grep "^$1|" "$STUB_LOG/meta" 2>/dev/null | head -1 | cut -d'|' -f2-; }
flap_cycle() { PR_NUMBER=35 GC_RIG_ROOT="$TMP/realrig" GC_CITY_PATH="" \
                 bash "$TMP/escalation-wiring-refinery.sh" >/dev/null 2>&1; }
reset
make_gh 0; flap_cycle
eq "$(count mail)" "1" "GHFLAP: cycle 1 escalates on the healthy PR fingerprint"
make_gh 1; flap_cycle
eq "$(count mail)" "2" "GHFLAP: cycle 2 reports the outage once, on the degraded channel"
flap_cycle
eq "$(count mail)" "2" "GHFLAP: a second cycle of the same outage is suppressed — the degraded value is constant"
make_gh 0; flap_cycle
eq "$(count mail)" "2" "GHFLAP: gh recovering on an UNCHANGED PR is not news — no mail on the way out"
case "$(stub_meta escalated.witness)" in
  oid123-APPROVED-BLOCKED*) ok "GHFLAP: the PR channel's stamp still holds the last PR fingerprint actually observed" ;;
  *) bad "GHFLAP: the outage overwrote the PR channel's stamp (got '$(stub_meta escalated.witness)')" ;;
esac
[ -n "$(stub_meta escalated.witness-degraded)" ] \
  && ok "GHFLAP: and the outage was recorded on its own key" \
  || bad "GHFLAP: no escalated.witness-degraded stamp — the degraded channel did not dedup"
# ...and the dedup is not a mute: a PR that genuinely moves during all this still
# escalates on the very next cycle.
PR_NUMBER=35 GH_FINGERPRINT="oidNEW/APPROVED/BLOCKED" GC_RIG_ROOT="$TMP/realrig" GC_CITY_PATH="" \
  bash "$TMP/escalation-wiring-refinery.sh" >/dev/null 2>&1
eq "$(count mail)" "3" "GHFLAP: a real head change after the outage still escalates immediately"

# --- STATEGUARD: the block must never hand the gate an EMPTY --state ----------
# The gate treats empty as the legitimate fingerprint "no state tracked" and
# stamps it durably, so a caller that MEANT to track state and failed marks the
# anchor stateless: every real change then waits out a full cooldown. The failure
# does not need gh — an unparseable `gc bd show` empties the bead branch too.
reset
make_gate "$TMP/rig/assets/scripts"
PR_NUMBER="" STUB_BAD_JSON=1 GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" \
  bash "$TMP/escalation-wiring-refinery.sh" >/dev/null 2>&1
[ -n "$(gate_arg --state)" ] \
  && ok "STATEGUARD: an unparseable bead read still produces a non-empty --state" \
  || bad "STATEGUARD: --state came out EMPTY, which the gate stamps as 'no state tracked'"
eq "$(gate_arg --kind)" "witness-degraded" \
   "STATEGUARD: and it is sent on the degraded channel, not stamped over the normal one"
has '--kind "$KIND"' "$(extract escalation-wiring-refinery)" \
    "STATEGUARD: the gate call carries the channel the block selected"

# --- GHCALL: the wiring must ask gh for the right three fields ----------------
# A stub that only echoes proves the gate received SOME fingerprint. It does not
# prove the wiring requested head oid, review decision and mergeability — drop one
# from --json and the fingerprint silently stops tracking that input, so a change
# in it waits out the whole cooldown.
reset
make_gate "$TMP/rig/assets/scripts"
PR_NUMBER=35 GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" bash "$TMP/escalation-wiring-refinery.sh" >/dev/null 2>&1
eq "$(gh_arg pr)" "view" "GHCALL: invokes 'gh pr view'"
eq "$(gh_arg view)" "35" "GHCALL: on the PR number from the bead"
eq "$(gh_arg --json)" "headRefOid,reviewDecision,mergeStateStatus" \
   "GHCALL: requests exactly the three hold inputs"
has 'join("/")' "$(gh_argv)" "GHCALL: and joins them into one fingerprint"

# Each field must move the fingerprint ON ITS OWN. Varying all three together
# would pass even if two of them were being dropped on the floor.
prev="oid123/APPROVED/BLOCKED"
for fp in "oidNEW/APPROVED/BLOCKED" "oid123/CHANGES_REQUESTED/BLOCKED" "oid123/APPROVED/CLEAN"; do
  reset
  make_gate "$TMP/rig/assets/scripts"
  PR_NUMBER=35 GH_FINGERPRINT="$fp" GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" \
    bash "$TMP/escalation-wiring-refinery.sh" >/dev/null 2>&1
  got=$(gate_arg --state)
  eq "$got" "$fp" "GHFIELD: --state carries '$fp' verbatim"
  [ "$got" != "$prev" ] && ok "GHFIELD: '$fp' differs from the baseline fingerprint" \
    || bad "GHFIELD: '$fp' collapsed onto the baseline — that field is not tracked"
done

# --- CTRLJSON: raw control characters in the bead read ------------------------
# THE OTHER P1. The gate defends its own anchor read, but the wiring builds STATE
# from its own `gc bd show`. bd emits raw control characters from prose notes and
# jq rejects every one of them, so an unsanitized read fails BOTH jq calls, STATE
# comes out EMPTY, and the gate reads empty as "no state tracked" — suppressing
# real PR/head/check changes for a full cooldown. The dedup gate becomes a mute.
for ctl in '\001' '\011' '\015'; do
  reset
  make_gate "$TMP/rig/assets/scripts"
  PR_NUMBER="" STUB_CTRL="$ctl" GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" \
    bash "$TMP/escalation-wiring-refinery.sh" >/dev/null 2>&1
  eq "$(gate_arg --state)" "open/pre_open_gate/polecat/su-lou.10.8/main/-" \
     "CTRLJSON($ctl): a control character in the payload does not empty --state"
done
# ...and the PR-backed branch survives it too: pr_number is read from the same row.
reset
make_gate "$TMP/rig/assets/scripts"
PR_NUMBER=35 STUB_CTRL='\011' GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" \
  bash "$TMP/escalation-wiring-refinery.sh" >/dev/null 2>&1
eq "$(gate_arg --state)" "oid123/APPROVED/BLOCKED" \
   "CTRLJSON: pr_number is still read out of a payload carrying control characters"

# --- GATEFAIL: a refusing gate must not take the patrol block down ------------
# escalation-gate.sh exits 1 when it cannot BOUND an escalation (unreadable
# anchor, unwritable stamp). That is correct for the gate and must be survivable
# for the caller: this is a best-effort pass that has to reach its later checks.
# And it must NOT fall back to a bare mail — the gate refused precisely because
# the escalation could not be bounded, so mailing anyway is the storm.
reset
make_gate "$TMP/rig/assets/scripts" 1
PR_NUMBER=35 GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" bash "$TMP/escalation-wiring-refinery.sh" >/dev/null 2>&1
rc=$?
eq "$rc" "0" "GATEFAIL: the block still exits 0 when the gate refuses"
eq "$(count gate)" "1" "GATEFAIL: the gate was called"
eq "$(count mail)" "0" "GATEFAIL: and no bare mail is sent behind its back"

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

# --- PROPAGATE: the loop's own pour must carry every var to the next wisp ------
# Passing --cooldown only makes the configured value good for ONE cycle. Each
# wisp is one iteration, and `next-iteration` pours the next one `--root-only` —
# which materializes no formula defaults — so a var that is not on that command
# arrives unrendered at the next wisp and every later cycle silently runs the
# consumer's own fallback instead (86400 for escalation_cooldown). A setting that
# survives only the first cycle is not a setting, and nothing about it looks
# broken from the outside: the gate still runs, still dedups, just on the wrong
# number. Enumerating [vars.*] rather than listing names here means a var added
# later cannot quietly stop propagating.
POUR="$(extract patrol-wisp-pour)"
[ -n "$POUR" ] && ok "patrol-wisp-pour: extracted between markers" \
  || bad "patrol-wisp-pour: extraction EMPTY — markers missing from $TOML"
printf '%s\n' "$POUR" > "$TMP/patrol-wisp-pour.sh"
bash -n "$TMP/patrol-wisp-pour.sh" \
  && ok "patrol-wisp-pour: extracted block is valid bash" \
  || bad "patrol-wisp-pour: extracted block failed bash -n"
# Same escape ban as the gated blocks, and here it bites hardest: the pour is one
# long line that invites a backslash wrap, and a TOML """ string eats exactly that
# continuation — the witness would then run a truncated pour plus a stray fragment.
case "$POUR" in
  *\\*) bad "patrol-wisp-pour: contains a backslash — TOML \"\"\" transforms it, so what ships differs from what this test runs. Keep the pour on one line." ;;
  *)    ok "patrol-wisp-pour: escape-free, so the extracted block is what actually ships" ;;
esac
has "mol wisp mol-witness-patrol --root-only" "$POUR" "PROPAGATE: pours the next iteration root-only"

DECLARED_VARS=$(awk -F'.' '/^\[vars\.[a-z_]+\]$/ {n=$2; sub(/\]$/, "", n); print n}' "$TOML")
[ -n "$DECLARED_VARS" ] \
  && ok "PROPAGATE: read the formula's [vars.*] declarations" \
  || bad "PROPAGATE: found no [vars.*] in $TOML — the per-var checks below would be vacuous"
case "$DECLARED_VARS" in
  *escalation_cooldown*) ok "PROPAGATE: escalation_cooldown is a declared var" ;;
  *)                     bad "PROPAGATE: escalation_cooldown is no longer declared in $TOML" ;;
esac
for v in $DECLARED_VARS; do
  # The value must be the placeholder, not a literal: hardcoding the default here
  # would freeze every downstream cycle at that number no matter what the bootstrap
  # set, which is the same bug wearing a plausible-looking fix.
  case "$POUR" in
    *"--var $v='{{$v}}'"*) ok "PROPAGATE: the pour forwards $v to the next wisp" ;;
    *) bad "PROPAGATE: the pour drops $v — a --root-only wisp materializes no defaults, so a configured $v dies after this cycle (want --var $v='{{$v}}')" ;;
  esac
done

# --- FRAGMENT: the pours BEFORE the loop must carry the vars too --------------
# PROPAGATE covers the loop's own `next-iteration` pour, and that is the last
# command of a cycle — so it says nothing about the pour that STARTS the witness.
# Those live in the agent template (`patrol-wisp-vars` / `patrol-wisp-fallback`),
# and while they passed only binding_prefix the declared vars were already lost by
# the time the loop began forwarding them: every cycle up to the first
# next-iteration ran on whatever fallback each consumer happened to have, and a
# crash-recovery pour dropped them again. Same defect as PROPAGATE, one file over,
# which is exactly why this check had to leave the formula.
FRAG="$ROOT/template-fragments/layered-startup-discovery.template.md"
[ -f "$FRAG" ] && ok "FRAGMENT: located the startup template" \
  || bad "FRAGMENT: $FRAG is missing — the startup pours cannot be checked"
frag_extract() { awk -v m="$1" '
    $0 ~ ("# >>> " m "$") {f=1; next}
    $0 ~ ("# <<< " m "$") {f=0}
    f' "$FRAG"; }

POUR_LINES=$(grep -c 'mol wisp mol-witness-patrol --root-only' "$FRAG" 2>/dev/null)
VAR_LINES=$(grep 'mol wisp mol-witness-patrol --root-only' "$FRAG" 2>/dev/null | grep -c 'PATROL_VARS')
[ "${POUR_LINES:-0}" -ge 3 ] \
  && ok "FRAGMENT: found the startup and fallback pours ($POUR_LINES of them)" \
  || bad "FRAGMENT: expected at least 3 witness pours in the template, found ${POUR_LINES:-0}"
eq "${VAR_LINES:-0}" "${POUR_LINES:-0}" \
   "FRAGMENT: every witness pour forwards the materialized vars"

VARS_BLOCK=$(frag_extract patrol-wisp-vars)
[ -n "$VARS_BLOCK" ] && ok "patrol-wisp-vars: extracted between markers" \
  || bad "patrol-wisp-vars: extraction EMPTY — markers missing from $FRAG"
printf '%s\n' "$VARS_BLOCK" > "$TMP/patrol-wisp-vars.sh"
bash -n "$TMP/patrol-wisp-vars.sh" \
  && ok "patrol-wisp-vars: extracted block is valid bash" \
  || bad "patrol-wisp-vars: extracted block failed bash -n"
# Enumerated, not named: a var declared later must propagate without anyone
# remembering to edit this template.
has '.vars[]?.name' "$VARS_BLOCK" \
    "FRAGMENT: enumerates the formula's declared vars instead of listing names"

# Behavioural, against the REAL declared vars and their REAL defaults — so a var
# added to the formula tomorrow is covered by this assertion the day it lands.
toml_default() { awk -v v="$1" '$0 == "[vars." v "]" {f=1; next} f && /^default = /{sub(/^default = /, ""); gsub(/"/, ""); print; exit} f && /^\[/{exit}' "$TOML"; }
FORMULA_JSON=$(for v in $DECLARED_VARS; do printf '%s\t%s\n' "$v" "$(toml_default "$v")"; done \
  | jq -Rsc 'split("\n") | map(select(length > 0) | split("\t")) | {vars: map({name: .[0], default: (.[1] // "")})}')
{ printf '%s\n' "$VARS_BLOCK"; printf 'printf "%%s" "$PATROL_VARS"\n'; } > "$TMP/vars-probe.sh"
GOT_VARS=$(STUB_FORMULA_JSON="$FORMULA_JSON" bash "$TMP/vars-probe.sh" 2>/dev/null)
for v in $DECLARED_VARS; do
  d=$(toml_default "$v")
  if [ "$v" = "binding_prefix" ]; then
    # Agent identity, rendered into the pour from the template's own data. The
    # materialization must not override it with a formula default.
    case "$GOT_VARS" in
      *"--var binding_prefix="*) bad "FRAGMENT: materializes binding_prefix, overriding the rendered identity" ;;
      *)                         ok  "FRAGMENT: leaves binding_prefix to the rendered template" ;;
    esac
    continue
  fi
  case "$GOT_VARS" in
    *"--var $v=$d"*) ok "FRAGMENT: the startup pour materializes $v=$d from the formula's own declaration" ;;
    *) bad "FRAGMENT: the startup pour drops $v — a --root-only pour materializes no defaults, so the witness runs without it until next-iteration (got '$GOT_VARS')" ;;
  esac
done
# The value must come from the formula, not from a number retyped in the template:
# a literal freezes every witness at whatever the default was the day it was typed.
case "$VARS_BLOCK" in
  *86400*|*'=180'*) bad "FRAGMENT: a default is hardcoded in the template — it will drift from [vars.*]" ;;
  *)                ok  "FRAGMENT: no default is hardcoded; the values come from gc formula show" ;;
esac
# A lookup that returns nothing degrades to today's pour rather than emitting a
# broken command line — the failure mode has to be "no worse than before".
GOT_NONE=$(STUB_FORMULA_JSON="" bash "$TMP/vars-probe.sh" 2>/dev/null)
eq "$GOT_NONE" "" "FRAGMENT: an unavailable formula lookup pours without the extra vars, as it did before"
# ...and a default carrying shell metacharacters is skipped, not word-split into
# the pour. The values are read from a file this template does not control.
GOT_HOSTILE=$(STUB_FORMULA_JSON='{"vars":[{"name":"event_timeout","default":"180"},{"name":"hostile","default":"a b; touch pwned"}]}' \
  bash "$TMP/vars-probe.sh" 2>/dev/null)
case "$GOT_HOSTILE" in
  *hostile*) bad "FRAGMENT: a default with shell metacharacters reached the pour ('$GOT_HOSTILE')" ;;
  *)         ok  "FRAGMENT: a default that is not a plain word is skipped, not word-split into the command" ;;
esac
has "--var event_timeout=180" "$GOT_HOSTILE" \
    "FRAGMENT: and the well-formed vars alongside it still propagate"

# The crash-recovery block is run STANDALONE — a fresh shell, no Step 2 above it —
# so it cannot inherit PATROL_VARS and must materialize them itself. Referencing
# the variable without building it expands to nothing and silently pours bare,
# which is the drop this whole section is about, now only on the recovery path.
FB_BLOCK=$(frag_extract patrol-wisp-fallback)
[ -n "$FB_BLOCK" ] && ok "patrol-wisp-fallback: extracted between markers" \
  || bad "patrol-wisp-fallback: extraction EMPTY — markers missing from $FRAG"
printf '%s\n' "$FB_BLOCK" > "$TMP/patrol-wisp-fallback.sh"
bash -n "$TMP/patrol-wisp-fallback.sh" \
  && ok "patrol-wisp-fallback: extracted block is valid bash" \
  || bad "patrol-wisp-fallback: extracted block failed bash -n"
case "$FB_BLOCK" in
  *'PATROL_VARS='*'gc formula show mol-witness-patrol'*)
    ok "FRAGMENT: the crash-recovery block materializes the vars itself before pouring" ;;
  *)
    bad "FRAGMENT: the crash-recovery block references PATROL_VARS without building it — standalone, that expands to nothing" ;;
esac

# --- FRAGMENT-DEACON: the deacon's startup pours must carry the vars too ------
# The same defect as FRAGMENT above, in the same file, one role over. The deacon
# block's two pours — the routed-work tier and the fresh-pour tier — forwarded
# only binding_prefix, so a deacon started by `gc session reset gc-toolkit.deacon`
# (the activation path for a changed cadence) poured a wisp whose event_timeout
# arrived unrendered. next-iteration then spends the interval as arithmetic over
# that value AND re-forwards it, so the drop is self-perpetuating: the loop
# either fails its wait or runs with no pacing at all, on the role that is 17.9%
# of city model calls. Raising the default alone would not have reached a single
# fresh deacon (tk-a3gb8).
#
# These checks live beside the witness ones because it is one mechanism in one
# file; they are the assertions above re-aimed at the deacon.
DTOML="$ROOT/formulas/mol-deacon-patrol.toml"
[ -f "$DTOML" ] && ok "FRAGMENT-DEACON: located mol-deacon-patrol.toml" \
  || bad "FRAGMENT-DEACON: $DTOML is missing — the deacon pours cannot be checked"
dtoml_default() { awk -v v="$1" '$0 == "[vars." v "]" {f=1; next} f && /^default = /{sub(/^default = /, ""); gsub(/"/, ""); print; exit} f && /^\[/{exit}' "$DTOML"; }
DDECLARED_VARS=$(awk -F'.' '/^\[vars\.[a-z_]+\]$/ {n=$2; sub(/\]$/, "", n); print n}' "$DTOML")
[ -n "$DDECLARED_VARS" ] \
  && ok "FRAGMENT-DEACON: read the deacon formula's [vars.*] declarations" \
  || bad "FRAGMENT-DEACON: found no [vars.*] in $DTOML — the per-var checks below would be vacuous"
case "$DDECLARED_VARS" in
  *event_timeout*) ok "FRAGMENT-DEACON: event_timeout is a declared deacon var" ;;
  *)               bad "FRAGMENT-DEACON: event_timeout is no longer declared in $DTOML" ;;
esac

# Every deacon pour in the fragment forwards the materialized vars — count-based,
# so a THIRD pour added later cannot quietly ship bare.
DPOUR_LINES=$(grep -c 'mol wisp mol-deacon-patrol --root-only' "$FRAG" 2>/dev/null)
DVAR_LINES=$(grep 'mol wisp mol-deacon-patrol --root-only' "$FRAG" 2>/dev/null | grep -c 'PATROL_VARS')
[ "${DPOUR_LINES:-0}" -ge 2 ] \
  && ok "FRAGMENT-DEACON: found the deacon startup pours ($DPOUR_LINES of them)" \
  || bad "FRAGMENT-DEACON: expected at least 2 deacon pours in the template, found ${DPOUR_LINES:-0}"
eq "${DVAR_LINES:-0}" "${DPOUR_LINES:-0}" \
   "FRAGMENT-DEACON: every deacon pour forwards the materialized vars"

DVARS_BLOCK=$(frag_extract deacon-patrol-wisp-vars)
[ -n "$DVARS_BLOCK" ] && ok "deacon-patrol-wisp-vars: extracted between markers" \
  || bad "deacon-patrol-wisp-vars: extraction EMPTY — markers missing from $FRAG"
printf '%s\n' "$DVARS_BLOCK" > "$TMP/deacon-patrol-wisp-vars.sh"
bash -n "$TMP/deacon-patrol-wisp-vars.sh" \
  && ok "deacon-patrol-wisp-vars: extracted block is valid bash" \
  || bad "deacon-patrol-wisp-vars: extracted block failed bash -n"
# It must read the DEACON formula. Copying the witness block verbatim would
# materialize the wrong formula's defaults and still pass a naive check.
has "gc formula show mol-deacon-patrol" "$DVARS_BLOCK" \
    "FRAGMENT-DEACON: the block reads mol-deacon-patrol's own declarations"
has '.vars[]?.name' "$DVARS_BLOCK" \
    "FRAGMENT-DEACON: enumerates the declared vars instead of listing names"

# Behavioural, against the REAL declared vars and their REAL defaults.
DFORMULA_JSON=$(for v in $DDECLARED_VARS; do printf '%s\t%s\n' "$v" "$(dtoml_default "$v")"; done \
  | jq -Rsc 'split("\n") | map(select(length > 0) | split("\t")) | {vars: map({name: .[0], default: (.[1] // "")})}')
{ printf '%s\n' "$DVARS_BLOCK"; printf 'printf "%%s" "$PATROL_VARS"\n'; } > "$TMP/deacon-vars-probe.sh"
DGOT_VARS=$(STUB_FORMULA_JSON="$DFORMULA_JSON" bash "$TMP/deacon-vars-probe.sh" 2>/dev/null)
for v in $DDECLARED_VARS; do
  d=$(dtoml_default "$v")
  if [ "$v" = "binding_prefix" ]; then
    case "$DGOT_VARS" in
      *"--var binding_prefix="*) bad "FRAGMENT-DEACON: materializes binding_prefix, overriding the rendered identity" ;;
      *)                         ok  "FRAGMENT-DEACON: leaves binding_prefix to the rendered template" ;;
    esac
    continue
  fi
  case "$DGOT_VARS" in
    *"--var $v=$d"*) ok "FRAGMENT-DEACON: the startup pour materializes $v=$d from the formula's own declaration" ;;
    *) bad "FRAGMENT-DEACON: the startup pour drops $v — a --root-only pour materializes no defaults, so a fresh deacon runs without it (got '$DGOT_VARS')" ;;
  esac
done
# The value must come from the formula, not from a number retyped in the
# template: a literal freezes every deacon at whatever the default was that day.
# Comments are stripped first: the cadence is discussed in prose all over this
# fragment, so a bare number match would fire on the explanation rather than on
# an actual hardcode. What is banned is a --var whose VALUE is a literal.
DVARS_CODE=$(printf '%s\n' "$DVARS_BLOCK" | grep -v '^[[:space:]]*#' || true)
case "$DVARS_CODE" in
  *'--var '*=[0-9]*) bad "FRAGMENT-DEACON: a default is hardcoded in the template — it will drift from [vars.*]" ;;
  *)                 ok  "FRAGMENT-DEACON: no default is hardcoded; the values come from gc formula show" ;;
esac
# A lookup that returns nothing degrades to today's pour rather than emitting a
# broken command line.
DGOT_NONE=$(STUB_FORMULA_JSON="" bash "$TMP/deacon-vars-probe.sh" 2>/dev/null)
eq "$DGOT_NONE" "" "FRAGMENT-DEACON: an unavailable formula lookup pours without the extra vars, as it did before"
# ...and a default carrying shell metacharacters is skipped, not word-split into
# the pour.
DGOT_HOSTILE=$(STUB_FORMULA_JSON='{"vars":[{"name":"event_timeout","default":"600"},{"name":"hostile","default":"a b; touch pwned"}]}' \
  bash "$TMP/deacon-vars-probe.sh" 2>/dev/null)
case "$DGOT_HOSTILE" in
  *hostile*) bad "FRAGMENT-DEACON: a default with shell metacharacters reached the pour ('$DGOT_HOSTILE')" ;;
  *)         ok  "FRAGMENT-DEACON: a default that is not a plain word is skipped, not word-split into the command" ;;
esac
has "--var event_timeout=600" "$DGOT_HOSTILE" \
    "FRAGMENT-DEACON: and the well-formed vars alongside it still propagate"

# The loop's own pour must keep forwarding them too — the deacon equivalent of
# PROPAGATE. Placeholders, never literals, for the same reason as above.
DNEXT_POUR=$(grep 'mol wisp mol-deacon-patrol --root-only' "$DTOML" || true)
[ -n "$DNEXT_POUR" ] \
  && ok "FRAGMENT-DEACON: located the deacon next-iteration pour" \
  || bad "FRAGMENT-DEACON: no next-iteration pour found in $DTOML"
for v in $DDECLARED_VARS; do
  case "$DNEXT_POUR" in
    *"--var $v='{{$v}}'"*) ok "FRAGMENT-DEACON: the next-iteration pour forwards $v" ;;
    *) bad "FRAGMENT-DEACON: the next-iteration pour drops $v — a configured $v dies after this cycle (want --var $v='{{$v}}')" ;;
  esac
done

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

# --- RECOVERY: the orphan-recovery notices are gated too ----------------------
# They are bead-scoped, so the "any escalation ABOUT A BEAD goes through the gate"
# rule covers them. Left bare they teach the witness — which re-reads this formula
# every cycle — that a bead-scoped `gc mail send` is fine, which is how four of
# the five storm mails were composed in the first place.
for marker in escalation-wiring-salvage-refused escalation-wiring-orphan-closed \
              escalation-wiring-orphan-recovered; do
  short="${marker#escalation-wiring-}"
  reset
  make_gate "$TMP/rig/assets/scripts"
  GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" bash "$TMP/$marker.sh" >/dev/null 2>&1
  rc=$?
  eq "$rc" "0" "RECOVERY($short): the block exits 0"
  eq "$(count gate)" "1" "RECOVERY($short): escalates through the gate"
  eq "$(count mail)" "0" "RECOVERY($short): sends no bare mail"
  eq "$(gate_arg --anchor)" "su-lou.10.8" "RECOVERY($short): passes --anchor"
  [ -n "$(gate_arg --state)" ] && ok "RECOVERY($short): passes a non-empty --state" \
    || bad "RECOVERY($short): passes a non-empty --state"
  eq "$(gate_arg --cooldown)" '{{escalation_cooldown}}' "RECOVERY($short): passes --cooldown"
  # An unsynced rig still mails directly rather than going silent.
  reset
  GC_RIG_ROOT="$TMP/absent" GC_CITY_PATH="$TMP/absent" bash "$TMP/$marker.sh" >/dev/null 2>&1
  eq "$(count mail)" "1" "RECOVERY($short): falls back to a direct mail when the script is absent"
done

# The gate call must come BEFORE `gc bd close`: the gate stamps escalated.<kind>
# on this same bead, and that write belongs on a bead that is still open.
reset
make_gate "$TMP/rig/assets/scripts"
GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" bash "$TMP/escalation-wiring-orphan-closed.sh" >/dev/null 2>&1
gate_at=$(grep -n '^gate$' "$STUB_LOG/calls" | head -1 | cut -d: -f1)
close_at=$(grep -n '^close$' "$STUB_LOG/calls" | head -1 | cut -d: -f1)
if [ -n "$gate_at" ] && [ -n "$close_at" ] && [ "$gate_at" -lt "$close_at" ]; then
  ok "RECOVERY(orphan-closed): the gate stamps before the bead is closed"
else
  bad "RECOVERY(orphan-closed): gate must precede close (gate@${gate_at:-none} close@${close_at:-none})"
fi

# --- ONESHOT: a refused gate must not spend a one-shot recovery ---------------
# GATEFAIL above covers the RE-DERIVED escalations, where "next cycle retries" is
# true because the patrol re-derives the same condition. The orphan-recovery
# notices are one-shot: the same pass performs the transition that CLEARS the
# condition, so if that transition runs after a refusal, the retry the message
# promises can never happen and the mayor is never told.
#
# ORPHAN_CLOSED is the one whose transition the block owns, so the block must
# withhold it. Closing the bead is what makes it stop being an orphan.
reset
make_gate "$TMP/rig/assets/scripts" 1
GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" bash "$TMP/escalation-wiring-orphan-closed.sh" >/dev/null 2>&1
rc=$?
eq "$rc" "0" "ONESHOT(orphan-closed): the block still exits 0 when the gate refuses"
eq "$(count gate)" "1" "ONESHOT(orphan-closed): the gate was called"
eq "$(count mail)" "0" "ONESHOT(orphan-closed): no bare mail behind the refusal"
eq "$(count close)" "0" \
   "ONESHOT(orphan-closed): the bead stays OPEN — closing it would spend the retry the refusal just promised"

# The same must hold for the unsynced-rig fallback arm: a failed bare mail is the
# same lost notice, so it must not close the bead either.
reset
STUB_MAIL_RC=1 GC_RIG_ROOT="$TMP/absent" GC_CITY_PATH="$TMP/absent" \
  bash "$TMP/escalation-wiring-orphan-closed.sh" >/dev/null 2>&1
eq "$(count mail)" "1" "ONESHOT(orphan-closed): the fallback mail was attempted"
eq "$(count close)" "0" "ONESHOT(orphan-closed): a FAILED fallback mail does not close the bead either"

# ...and the positive control, or the guard above would pass by never closing at
# all. A gate that accepts — or that SUPPRESSES, which also exits 0 and also means
# the mayor was told, on an earlier cycle for this same state — closes normally.
reset
make_gate "$TMP/rig/assets/scripts" 0
GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" bash "$TMP/escalation-wiring-orphan-closed.sh" >/dev/null 2>&1
eq "$(count close)" "1" "ONESHOT(orphan-closed): a gate that accepts still closes the bead"
reset
STUB_MAIL_RC=0 GC_RIG_ROOT="$TMP/absent" GC_CITY_PATH="$TMP/absent" \
  bash "$TMP/escalation-wiring-orphan-closed.sh" >/dev/null 2>&1
eq "$(count close)" "1" "ONESHOT(orphan-closed): so does a successful fallback mail"

# SALVAGE_REFUSED and ORPHAN_RECOVERED cannot withhold their transition — the
# recovery is load-bearing and the notice is advisory, so blocking a husk's
# recovery on a mail failure would strand real work. They are therefore genuinely
# best-effort, and the requirement is that they SAY so: a refusal message that
# promises a retry which cannot happen reads as handled in the patrol log, which
# is how the lost notification stays invisible.
for marker in escalation-wiring-salvage-refused escalation-wiring-orphan-recovered; do
  short="${marker#escalation-wiring-}"
  reset
  make_gate "$TMP/rig/assets/scripts" 1
  err=$(GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" bash "$TMP/$marker.sh" 2>&1 >/dev/null)
  rc=$?
  eq "$rc" "0" "ONESHOT($short): survives a refusing gate"
  eq "$(count mail)" "0" "ONESHOT($short): and does not fall back to a bare mail"
  has "BEST-EFFORT" "$err" "ONESHOT($short): the refusal says the notice is best-effort"
  case "$err" in
    *"Next cycle retries"*)
      bad "ONESHOT($short): still promises a retry the recovery makes impossible" ;;
    *)
      ok "ONESHOT($short): makes no retry promise it cannot keep" ;;
  esac
  # The state transition these two cannot withhold is elsewhere in the step, so
  # the block itself must not have quietly grown a close.
  eq "$(count close)" "0" "ONESHOT($short): the block performs no close of its own"
done

# --- ALLOWLIST: no NEW ungated bead-scoped mail may appear in the formula ------
# The discipline section states the rule; this enforces it. Every `gc mail send`
# in the file must be inside a gated `escalation-wiring-*` block (where it is the
# documented fallback arm) or be one of the two escalations that have no bead to
# key a stamp on. A third bare bead-scoped mail is a new storm channel, and it is
# exactly the kind of thing that gets added later by someone reading the OTHER
# examples in this file.
ALLOWED_1='ESCALATION: <polecat> needs help'   # about an AGENT; its trigger mail is archived
ALLOWED_2='WITNESS: orphan-recovery disabled'  # rig-global fail-safe; no anchor exists
UNGATED=0
while IFS='	' read -r ln inblock content; do
  [ -n "$ln" ] || continue
  [ "$inblock" = "1" ] && continue
  case "$content" in
    *"$ALLOWED_1"*|*"$ALLOWED_2"*) continue ;;
  esac
  UNGATED=$((UNGATED + 1))
  bad "ALLOWLIST: ungated bead-scoped 'gc mail send' at $TOML:$ln — route it through escalation-gate.sh (or add it to the allowlist with a reason)"
done <<EOF
$(awk '
  /^# >>> escalation-wiring-/ {inblock=1}
  /^# <<< escalation-wiring-/ {inblock=0; next}
  # Match the call ANYWHERE on the line, not just at its start. A send is just as
  # ungated when it is a conditional or a chained clause — `if gc mail send ...`
  # is already in this formula — and an anchored scan reports those as clean.
  # Prose quotes commands in backticks and this section is full of it, so strip
  # backtick-quoted spans from a COPY of the line first (the report still shows the
  # original). A prose mention outside backticks would false-positive, which is the
  # right way to be wrong here: it is loud and one allowlist entry fixes it, while
  # a missed call is a silent storm channel.
  {
    code = $0
    gsub(/`[^`]*`/, "", code)
    if (code ~ /gc mail send/) printf "%d\t%d\t%s\n", NR, inblock, $0
  }
' "$TOML")
EOF
[ "$UNGATED" -eq 0 ] && ok "ALLOWLIST: every bead-scoped 'gc mail send' goes through the gate"
# A stale allowlist entry hides nothing but rots, so require each to still match.
for allowed in "$ALLOWED_1" "$ALLOWED_2"; do
  grep -qF "$allowed" "$TOML" \
    && ok "ALLOWLIST: exception still present in the formula ($allowed)" \
    || bad "ALLOWLIST: exception no longer exists — drop it from the list ($allowed)"
done

# --- DEFAULTDRIFT: the two cooldown defaults must agree -----------------------
# `[vars.escalation_cooldown] default` is what the formula documents and renders
# as Config; DEFAULT_COOLDOWN is what actually governs whenever the var reaches
# the script unrendered — which is the common case on a --root-only pour. If they
# drift, the documented value is a lie in exactly the situation nobody tests.
TOML_COOLDOWN=$(awk '/^\[vars\.escalation_cooldown\]/{f=1; next} f && /^default =/{gsub(/[^0-9]/, "", $0); print; exit}' "$TOML")
SCRIPT_COOLDOWN=$(grep -oE '^DEFAULT_COOLDOWN=[0-9]+' "$HERE/escalation-gate.sh" | cut -d= -f2)
[ -n "$TOML_COOLDOWN" ] && ok "DEFAULTDRIFT: found the formula's escalation_cooldown default" \
  || bad "DEFAULTDRIFT: could not read [vars.escalation_cooldown] default from $TOML"
[ -n "$SCRIPT_COOLDOWN" ] && ok "DEFAULTDRIFT: found the script's DEFAULT_COOLDOWN" \
  || bad "DEFAULTDRIFT: could not read DEFAULT_COOLDOWN from escalation-gate.sh"
eq "$SCRIPT_COOLDOWN" "$TOML_COOLDOWN" "DEFAULTDRIFT: script default matches the formula's documented default"

echo
echo "witness-escalation-wiring.test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
