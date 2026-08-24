#!/usr/bin/env bash
# Hermetic test for mol-deacon-patrol's ESCALATION WIRING (tk-mvc72).
#
# THE BUG THIS EXISTS TO PREVENT. The deacon re-derives its alert conditions from
# live state on every patrol cycle, and those conditions stay true for as long as
# the thing is broken. So it mailed the mayor again, and again: on 2026-08-02 it
# sent NINE identical HIGH escalations for ONE already-tracked finding (lx-9d6me)
# in a single day — lx-wisp-zpf4p, h5bh9, br7jp, czs3b, ssui3, vrjp7, dbi56,
# 4v4zz, 48x69 — differing only in an age that ticked up. A mayor nudge asking it
# to stop did not stop it.
#
# The cost was burial. In the middle of those nine, the same patrol emitted
# `dolt-noms-size: lx 2.24 GB, largest of 5` — a third independent symptom of the
# same root cause and the most useful datapoint of the cycle — and it was nearly
# lost between the duplicates. Re-confirmed 2026-08-24: 26 messages in one mayor
# cycle, ~6 of them re-escalations of already-tracked findings, dolt-noms-size
# again among them.
#
# escalation-gate.sh was already the city's answer to this and was already wired
# into mol-witness-patrol (tk-z4aka) and mol-refinery-patrol (tk-76jxq). It could
# not be wired here because it stamps a BEAD and a deacon finding is about a
# database or a doctor check. finding-anchor.sh supplies that missing anchor.
#
# escalation-gate.sh and finding-anchor.sh both have coverage of their own
# behaviour. Nothing covers the FORMULA LINES THAT CALL THEM — and the wiring is
# where the storm comes back. Every edit below leaves both scripts' suites green
# while reopening the bug:
#
#   - dropping `--anchor`        -> no dedup key at all
#   - dropping `--kind deacon`   -> the deacon escalates on the gate's DEFAULT
#                                   kind, which is the witness's. One anchor +
#                                   kind = one open escalation, so a shared kind
#                                   lets whichever role got there first MUTE the
#                                   other (KIND)
#   - dropping `--state`         -> the gate becomes a mute: a finding that gets
#                                   genuinely worse waits out the full cooldown
#   - putting the AGE in         -> the storm, rebuilt while looking gated. A
#     `--state`                     Step 2a line says "manifest is 40h old", next
#                                   cycle "41h old", so every cycle is a state
#                                   change and every cycle mails (AGEFREE)
#   - mailing when finding-anchor -> an escalation with no anchor is one nothing
#     could not answer                can bound: the unbounded storm, exactly
#                                   (NOANCHOR)
#   - replacing a gated call with -> the original bug, verbatim (NOBARE)
#     a bare `gc mail send`
#   - moving the SCRIPTS_DIR      -> each tool call is a fresh shell, so
#     resolution out of the           `$SCRIPTS_DIR` is empty, the call fails, and
#     sending shell                   NOTHING is sent — a silent mute, worse than
#                                   the storm (SAMESHELL)
#
# So this executes the wiring EXTRACTED VERBATIM from the formula (between the
# `deacon-escalation-wiring` markers) against stubs, and asserts what reaches the
# gate. No live city, Dolt, mail or network: `gc` and `git` are both stubbed, and
# `git` specifically so the "$(git rev-parse --show-toplevel)/assets/scripts"
# candidate cannot silently resolve to the real checkout this test runs inside.
#
# Companions: witness-escalation-wiring.test.sh and refinery-escalation-wiring.test.sh
# (same shape, other two patrols). The parts are covered by escalation-gate.test.sh
# and finding-anchor.test.sh.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-deacon-patrol.toml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { case "$2" in *"$1"*) ok "$3" ;; *) bad "$3 (not found in: $2)" ;; esac; }
hasnt() { case "$2" in *"$1"*) bad "$3 (unexpectedly found '$1' in: $2)" ;; *) ok "$3" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required for this test" >&2; exit 1; }
[ -f "$TOML" ] || { echo "formula not found: $TOML" >&2; exit 1; }

# --- Extract the marked wiring, through a real TOML decode --------------------
# Reading the raw file would test the ESCAPED text, not what the agent executes:
# the description is a TOML `"""` basic string, where `\\` decodes to a single
# backslash. A line continuation that gets eaten by the encoding is precisely the
# kind of break this test has to see, so the snippet is taken from the decoded
# value (MARKERS).
python3 - "$TOML" > "$TMP/wiring.sh" <<'PY'
import re, sys, tomllib
d = tomllib.load(open(sys.argv[1], "rb"))
body = "\n".join(s["description"] for s in d["steps"])
m = re.search(r"# >>> deacon-escalation-wiring\n(.*?)# <<< deacon-escalation-wiring",
              body, re.S)
if not m:
    sys.exit("deacon-escalation-wiring markers not found in mol-deacon-patrol.toml")
sys.stdout.write(m.group(1))
PY
[ -s "$TMP/wiring.sh" ] || { echo "extracted wiring is empty" >&2; exit 1; }
ok "MARKERS: the deacon-escalation-wiring snippet is present and non-empty"

bash -n "$TMP/wiring.sh" && ok "SYNTAX: extracted wiring parses as bash" \
  || bad "SYNTAX: extracted wiring does not parse as bash"

# --- Stubs --------------------------------------------------------------------
export STUB_LOG="$TMP/log"
mkdir -p "$STUB_LOG" "$TMP/bin" "$TMP/scripts"
export PATH="$TMP/bin:$PATH"

# `git rev-parse --show-toplevel` must NOT reach the real checkout, or the
# fallback case (no scripts anywhere) would silently resolve to the live
# assets/scripts and the test would assert nothing.
cat > "$TMP/bin/git" <<'GIT'
#!/usr/bin/env bash
[ "${1:-}" = "rev-parse" ] && { echo "/nonexistent-toplevel"; exit 0; }
exit 1
GIT
chmod +x "$TMP/bin/git"

cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
S="$STUB_LOG"
if [ "${1:-}" = "mail" ] && [ "${2:-}" = "send" ]; then
  shift 2
  for a in "$@"; do printf '%s' "$a" | jq -Rs .; done | jq -s . > "$S/mail-args.json"
  echo mail >> "$S/calls"
fi
exit 0
GC
chmod +x "$TMP/bin/gc"

make_scripts() { # make_scripts <anchor-stdout> <anchor-rc> <gate-rc>
  cat > "$TMP/scripts/finding-anchor.sh" <<ANCH
#!/usr/bin/env bash
for a in "\$@"; do printf '%s' "\$a" | jq -Rs .; done | jq -s . > "\$STUB_LOG/anchor-args.json"
echo anchor >> "\$STUB_LOG/calls"
printf '%s' "$1"
[ -n "$1" ] && echo
exit ${2:-0}
ANCH
  cat > "$TMP/scripts/escalation-gate.sh" <<GATE
#!/usr/bin/env bash
for a in "\$@"; do printf '%s' "\$a" | jq -Rs .; done | jq -s . > "\$STUB_LOG/gate-args.json"
echo gate >> "\$STUB_LOG/calls"
exit ${3:-0}
GATE
  chmod +x "$TMP/scripts/finding-anchor.sh" "$TMP/scripts/escalation-gate.sh"
}

reset() { rm -rf "$STUB_LOG"; mkdir -p "$STUB_LOG"; }

# The wiring resolves SCRIPTS_DIR from ${GC_RIG_ROOT}/assets/scripts first.
LINK="$TMP/rig"
mkdir -p "$LINK/assets"
ln -sfn "$TMP/scripts" "$LINK/assets/scripts"

run_wiring() { # run_wiring — execute the extracted snippet with BODY preset
  ( export GC_RIG_ROOT="$LINK" GC_CITY_PATH="/nonexistent-city"
    # Consumed by the sourced snippet below, which shellcheck cannot follow.
    # shellcheck disable=SC2034
    BODY="lx: manifest is 40h old"
    # shellcheck disable=SC1090
    . "$TMP/wiring.sh" ) >"$TMP/out" 2>"$TMP/err"
  echo $?
}

gate_args()   { jq -r '.[]' < "$STUB_LOG/gate-args.json" 2>/dev/null; }
anchor_args() { jq -r '.[]' < "$STUB_LOG/anchor-args.json" 2>/dev/null; }
gate_flag() { # gate_flag <flag> — the value that followed <flag>
  jq -r --arg f "$1" 'to_entries[] | select(.value == $f) | .key + 1' \
    < "$STUB_LOG/gate-args.json" 2>/dev/null | head -1 \
    | while read -r i; do jq -r ".[$i]" < "$STUB_LOG/gate-args.json"; done
}

echo "== mol-deacon-patrol escalation wiring =="

# --- GATED: the happy path goes through the gate, never bare ------------------
reset; make_scripts "tk-track1" 0 0
RC=$(run_wiring)
eq "$RC" 0 "GATED: wiring exits 0"
has "gate" "$(cat "$STUB_LOG/calls")" "GATED: escalation-gate was called"
hasnt "mail" "$(cat "$STUB_LOG/calls" 2>/dev/null)" "GATED: no bare gc mail send"

# --- ANCHOR: the gate is anchored on what finding-anchor returned -------------
eq "$(gate_flag --anchor)" "tk-track1" "ANCHOR: --anchor carries the resolved tracker id"

# --- KIND: deacon, never the gate's witness default --------------------------
eq "$(gate_flag --kind)" "deacon" "KIND: --kind deacon (not the witness default)"

# --- STATE / COOLDOWN present ------------------------------------------------
has "--state" "$(gate_args)" "STATE: --state is passed"
has "--cooldown" "$(gate_args)" "COOLDOWN: --cooldown is passed"

# --- NOANCHOR: no anchor means NOTHING is mailed -----------------------------
# The fail-closed property. An escalation with no anchor is one nothing can
# bound, which is the unbounded storm this whole change exists to stop. It must
# NOT fall back to a bare mail.
reset; make_scripts "" 2 0
RC=$(run_wiring)
hasnt "mail" "$(cat "$STUB_LOG/calls" 2>/dev/null)" "NOANCHOR: does not fall back to a bare mail"
hasnt "gate" "$(cat "$STUB_LOG/calls" 2>/dev/null)" "NOANCHOR: does not call the gate without an anchor"
has "NOT mailing unbounded" "$(cat "$TMP/err")" "NOANCHOR: says why on stderr"

# --- GATEFAIL: a refusing gate is logged, never worked around ----------------
reset; make_scripts "tk-track1" 0 1
RC=$(run_wiring)
eq "$RC" 0 "GATEFAIL: a non-zero gate does not abort the patrol pass"
hasnt "mail" "$(cat "$STUB_LOG/calls" 2>/dev/null)" "GATEFAIL: does not mail past a gate that refused"
has "NOT falling back to a bare mail" "$(cat "$TMP/err")" "GATEFAIL: logs the refusal"

# --- FALLBACK: an unsynced rig keeps the OLD behavior, not silence -----------
reset
rm -f "$TMP/scripts/escalation-gate.sh" "$TMP/scripts/finding-anchor.sh"
RC=$(run_wiring)
has "mail" "$(cat "$STUB_LOG/calls" 2>/dev/null)" "FALLBACK: a rig without the scripts still mails"
eq "$RC" 0 "FALLBACK: exits 0"

# --- BOTHSCRIPTS: the resolution loop requires BOTH scripts ------------------
# A dir holding only the gate would be selected, and then finding-anchor.sh would
# be invoked by a path that does not exist — the call fails, ANCHOR is empty, and
# the escalation is silently dropped rather than falling back.
reset; make_scripts "tk-track1" 0 0
rm -f "$TMP/scripts/finding-anchor.sh"
RC=$(run_wiring)
has "mail" "$(cat "$STUB_LOG/calls" 2>/dev/null)" "BOTHSCRIPTS: a half-synced rig falls back to mailing, not silence"

# --- SAMESHELL: the snippet resolves SCRIPTS_DIR itself ----------------------
# If the resolution loop is ever moved out, the snippet inherits an empty
# SCRIPTS_DIR, `/escalation-gate.sh` fails, and nothing is sent.
has 'for cand in' "$(cat "$TMP/wiring.sh")" "SAMESHELL: the snippet resolves SCRIPTS_DIR in its own shell"
has 'SCRIPTS_DIR=""' "$(cat "$TMP/wiring.sh")" "SAMESHELL: SCRIPTS_DIR is initialised in the snippet"

# --- Static assertions over the real call sites ------------------------------
DECODED="$TMP/decoded.txt"
python3 - "$TOML" > "$DECODED" <<'PY'
import sys, tomllib
d = tomllib.load(open(sys.argv[1], "rb"))
for s in d["steps"]:
    if s["id"] in ("dolt-health", "system-health"):
        sys.stdout.write("### %s\n%s\n" % (s["id"], s["description"]))
PY

# NOBARE: no un-gated mayor mail survives in the two escalating steps. The only
# permitted `gc mail send mayor/` is the fallback inside the marked snippet.
BARE=$(grep -c 'gc mail send mayor/' "$DECODED" || true)
eq "$BARE" "1" "NOBARE: exactly one gc mail send mayor/ remains (the unsynced-rig fallback)"
grep -n 'gc mail send mayor/' "$DECODED" | grep -q '"<subject>"' \
  && ok "NOBARE: the survivor is the fallback, not a real escalation site" \
  || bad "NOBARE: the surviving bare mail is not the documented fallback"

# EVERYGATE: every escalation site pairs finding-anchor with the gate.
#
# The counts are asserted against a FLOOR as well as against each other. A
# pattern that stops matching would otherwise make every comparison below
# vacuously true — 0 == 0 is not evidence that every call site is wired, it is
# evidence that the test went blind.
NA=$(grep -c 'finding-anchor.sh' "$DECODED" || true)
NG=$(grep -c 'escalation-gate.sh" --anchor' "$DECODED" || true)
[ "$NA" -ge 5 ] && ok "EVERYGATE: $NA finding-anchor call sites" \
  || bad "EVERYGATE: only $NA finding-anchor call sites (expected >= 5)"
[ "$NG" -ge 5 ] && ok "EVERYGATE: $NG anchored gate call sites" \
  || bad "EVERYGATE: only $NG anchored gate call sites (expected >= 5)"

# KINDEVERY: every gate call in the formula names --kind deacon. One missing kind
# silently shares the witness's channel and lets it mute the deacon.
NKIND=$(grep -c 'escalation-gate.sh" --anchor "$ANCHOR" --kind deacon' "$DECODED" || true)
[ "$NKIND" -ge 5 ] && ok "KINDEVERY: $NKIND gate calls name --kind deacon" \
  || bad "KINDEVERY: only $NKIND gate calls name --kind deacon (expected >= 5)"
eq "$NKIND" "$NG" "KINDEVERY: every anchored gate call passes --kind deacon"

# AGEFREE: the storm-rebuilding trap. No --state at a real call site may carry a
# value that drifts every cycle. The FLAG line itself is the specific one: it
# contains the manifest age in hours.
if grep -E -- '--state "\$FLAG_LINE"|--state "\$finding"|--state "\$BODY"' "$DECODED" >/dev/null; then
  bad "AGEFREE: a --state carries a whole finding line (its age/size drifts every cycle)"
else
  ok "AGEFREE: no --state is built from a raw finding line"
fi
has 'never the age' "$(cat "$DECODED")" "AGEFREE: the formula documents the class-not-age rule"

# --- CLASSMAP -----------------------------------------------------------------
# The Step 3 fingerprint is derived from the Step 2a verdict line by a `case`
# block. That mapping is the whole dedup: if a verdict falls through to the
# generic arm, or two DIFFERENT failures land on one class, they share a
# fingerprint and mute each other — and if a verdict's wording changes in Step 2a
# without the mapping following, that happens silently.
#
# So drive the formula's OWN Step 2a verdict wordings through the formula's OWN
# case block. Nothing here is hand-copied: both sides are extracted from the
# shipped file, so the two cannot drift apart without this failing.
python3 - "$TOML" > "$TMP/classmap.sh" <<'PY'
import re, sys, tomllib
d = tomllib.load(open(sys.argv[1], "rb"))
steps = {s["id"]: s["description"] for s in d["steps"]}
dh = steps["dolt-health"]

case = re.search(r'(case "\$FLAG_LINE" in.*?esac)', dh, re.S)
if not case:
    sys.exit("Step 3 FLAG_LINE case block not found")
print("classify() { FLAG_LINE=\"$1\"")
print(case.group(1))
print('printf "%s\\n" "$CLASS"; }')

root = re.search(r'(case "\$FLAG_ROOT_LINE" in.*?esac)', dh, re.S)
if not root:
    sys.exit("Step 3 FLAG_ROOT_LINE case block not found")
print("rootclassify() { FLAG_ROOT_LINE=\"$1\"")
print(root.group(1))
print('printf "%s\\n" "$ROOT_CLASS"; }')

# Every verdict wording Step 2a can emit, taken from its own echo statements.
for kind, pat in (("FLAG", r'echo "(FLAG \$name: [^"]*)"'),
                  ("ROOT", r'echo "(FLAG-ROOT: [^"]*)"')):
    for line in re.findall(pat, dh):
        lit = (line.replace("$name", "lx")
                   .replace("${age_h}", "40").replace("$age_h", "40")
                   .replace("${STALE_H}", "12").replace("$STALE_H", "12")
                   .replace("$scan_fail", "permission denied")
                   .replace("$newest", "chunk.darc")
                   .replace("${since}", "90").replace("$since", "90")
                   .replace("$BACKUP_ROOT", "/b").replace("$DB_NAMES", "lx tk")
                   .replace("$db", "/b/lx"))
        print('VERDICTS+=("%s|%s")' % (kind, lit.replace('"', '\\"')))
PY
# shellcheck disable=SC1090
VERDICTS=()
. "$TMP/classmap.sh"

[ "${#VERDICTS[@]}" -ge 6 ] && ok "CLASSMAP: extracted ${#VERDICTS[@]} Step 2a verdict wordings" \
  || bad "CLASSMAP: only ${#VERDICTS[@]} verdict wordings extracted (expected >= 6)"

CLASSMAP_UNMAPPED=0
for v in "${VERDICTS[@]}"; do
  kind="${v%%|*}"; line="${v#*|}"
  if [ "$kind" = "FLAG" ]; then c=$(classify "$line"); generic=flagged
  else c=$(rootclassify "$line"); generic=flag-root; fi
  if [ -z "$c" ] || [ "$c" = "$generic" ]; then
    CLASSMAP_UNMAPPED=$((CLASSMAP_UNMAPPED + 1))
    echo "     unmapped -> $line"
  fi
done
eq "$CLASSMAP_UNMAPPED" 0 "CLASSMAP: every Step 2a verdict maps to a specific class (none fall through)"

# The scan-failure verdicts also contain "no manifest" / "manifest is Nh old", so
# an arm order that puts those first swallows them and a read failure is
# fingerprinted as an ordinary stale manifest. Assert they keep their own class.
SF=$(classify "FLAG lx: backup directory scan failed (permission denied) and the manifest is 40h old (>12h = 2x backup cadence)")
eq "$SF" "scan-failed" "CLASSMAP: a scan failure is not swallowed by the stale-manifest arm"
SF2=$(classify "FLAG lx: backup directory scan failed (permission denied) and there is no manifest - nothing verifiably restorable")
eq "$SF2" "scan-failed" "CLASSMAP: a scan failure is not swallowed by the no-manifest arm"

# THE STORM PROPERTY. The same failure at a different age must produce the SAME
# fingerprint, or every cycle reads as "state changed" and mails.
A=$(classify "FLAG lx: manifest is 40h old (>12h = 2x backup cadence)")
B=$(classify "FLAG lx: manifest is 41h old (>12h = 2x backup cadence)")
C=$(classify "FLAG lx: manifest is 99h old (>12h = 2x backup cadence)")
if [ "$A" = "$B" ] && [ "$B" = "$C" ] && [ -n "$A" ]; then
  ok "CLASSMAP: the manifest age does not change the fingerprint (40h/41h/99h all '$A')"
else
  bad "CLASSMAP: the age changes the fingerprint ($A/$B/$C) — every cycle would re-mail"
fi

# ...and genuinely different failures must NOT collapse onto one class.
D1=$(classify "FLAG lx: no backup directory at /b/lx - never backed up")
D2=$(classify "FLAG lx: newest file is 'chunk.darc', not the manifest - uploaded but never committed; not restorable past 40h ago")
if [ "$D1" != "$D2" ] && [ "$D1" != "$A" ] && [ "$D2" != "$A" ]; then
  ok "CLASSMAP: distinct failure classes stay distinct ($D1 / $D2 / $A)"
else
  bad "CLASSMAP: distinct failures collapsed onto one class ($D1 / $D2 / $A) — they would mute each other"
fi

# COOLDOWNVAR: the cooldown var must reach the loop through the pour, or from
# cycle 2 it arrives as the literal {{escalation_cooldown}}. This is exactly the
# defect that made event_timeout dead letter (tk-2qa85).
RAW=$(cat "$TOML")
has 'escalation_cooldown' "$RAW" "COOLDOWNVAR: the var exists"
POURS=$(grep -c "mol wisp mol-deacon-patrol --root-only" "$TOML" || true)
FWD=$(grep "mol wisp mol-deacon-patrol --root-only" "$TOML" | grep -c 'escalation_cooldown' || true)
eq "$FWD" "$POURS" "COOLDOWNVAR: every pour forwards escalation_cooldown (a --root-only wisp materializes no defaults)"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
