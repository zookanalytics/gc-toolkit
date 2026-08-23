#!/usr/bin/env bash
# Hermetic test for doctor/check-step-close-owns-bead (tk-niu2f).
#
# THE BUG the check guards: a formula step closing its own bead on an id read
# from the environment. `gc hook --claim` does not refresh $GC_TRIGGER_BEAD_ID,
# so the close lands on whichever bead the session was spawned with — observed
# live as another session's in-progress step in an unrelated molecule, closed
# successfully, exit status 0.
#
# What is exercised here:
#   * the ERROR arm, naming file, line and the offending text, for both the
#     `bd update ... --status=closed` and the `bd close` spellings;
#   * every variable spelling that reaches the same place — "$GC_BEAD_ID",
#     ${GC_TRIGGER_BEAD_ID}, "${GC_BEAD_ID:-}", bare $GC_BEAD_ID — because the
#     guarded `[ -n ... ] &&` form is how it is actually written;
#   * PROSE, which these formulas use to document the hazard by quoting it, and
#     which must never be a finding — otherwise the check forbids writing down
#     the rule it enforces;
#   * a comment line, same reasoning, including this pack's habit of pasting the
#     bad idiom into a header to explain it;
#   * the remedy shape (step-close.sh --step ...), recognised as clean;
#   * a non-closing `--set-metadata` write, deliberately NOT flagged;
#   * an id that appears as a later flag VALUE rather than the update target,
#     which is not a self-close;
#   * base-snapshots exclusion (vendored upstream, never executed);
#   * the generated/ tier exclusion, asserted against two distinct trees under
#     it, because it is a tier rule and not a carve-out for one artifact;
#   * the SHIPPED pack tree, asserted clean — the regression anchor. If a future
#     formula reintroduces the idiom, this line goes red.
#
# No live city, Dolt, network, or beads — only a tmpdir and the check itself.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

[ -x "$CHECK" ] || chmod +x "$CHECK" 2>/dev/null

run()   { GC_PACK_DIR="$1" bash "$CHECK" 2>&1; }
rc_of() { GC_PACK_DIR="$1" bash "$CHECK" >/dev/null 2>&1; echo $?; }

# The banned shapes are assembled at runtime rather than written literally: the
# check scans *.sh under the pack, this file is one, and a fixture spelled out
# in full would make the suite flag itself.
U='update'; C='close'; S='--status=closed'
BD='gc bd'

# --- 1. the ERROR arm, both spellings ----------------------------------------
mkdir -p "$TMP/dirty"
{
    echo '```bash'
    echo "$BD $U \"\$GC_TRIGGER_BEAD_ID\" --set-metadata gc.outcome=pass $S"
    echo "[ -n \"\${GC_BEAD_ID:-}\" ] && $BD $U \"\$GC_BEAD_ID\" $S"
    echo "$BD $C \"\$GC_BEAD_ID\""
    echo "  $BD $U \${GC_TRIGGER_BEAD_ID} --set-metadata gc.outcome=fail $S"
    echo '```'
} > "$TMP/dirty/mol-bad.toml"

OUT="$(run "$TMP/dirty")"
eq "$(rc_of "$TMP/dirty")" "2" "(ERROR) an env-id close is an error"
has "$OUT" "4 step-close site(s)" "(ERROR) all four spellings are found"
has "$OUT" "mol-bad.toml:2" "(ERROR) quoted \$GC_TRIGGER_BEAD_ID update+status=closed"
has "$OUT" "mol-bad.toml:3" "(ERROR) the guarded [ -n ... ] && form"
has "$OUT" "mol-bad.toml:4" "(ERROR) the bare 'bd close' form"
has "$OUT" "mol-bad.toml:5" "(ERROR) the \${...} braced form, indented"
has "$OUT" "step-close.sh" "(ERROR) the message names the remedy"

# --- 2. prose and comments are not findings ----------------------------------
mkdir -p "$TMP/prose"
{
    echo "Do not write \`$BD $U \"\$GC_TRIGGER_BEAD_ID\" $S\` — it closes another"
    echo "session's bead. The guarded \`[ -n \"\$GC_BEAD_ID\" ]\` form is no better."
    echo "    # $BD $U \"\$GC_BEAD_ID\" $S"
    echo "  #   $BD $C \"\$GC_TRIGGER_BEAD_ID\""
} > "$TMP/prose/notes.md"
eq "$(rc_of "$TMP/prose")" "0" "(PROSE) documenting the banned idiom is not a finding"

# --- 3. the remedy, and near-misses that are not self-closes -----------------
mkdir -p "$TMP/clean"
{
    echo '```bash'
    echo 'SC=""; for c in "${GC_PACK_DIR:-}"; do'
    echo '  [ -x "$c/assets/scripts/step-close.sh" ] && { SC="$c/assets/scripts/step-close.sh"; break; }'
    echo 'done'
    echo '"${SC:?missing}" --step mol-x.step-one --outcome pass'
    # a non-closing write on the same variable: same staleness, not a close
    echo "$BD $U \"\$GC_TRIGGER_WORK_BEAD_ID\" --set-metadata branch=polecat/x"
    # the env id as a later flag VALUE, not the update target
    echo "$BD $U \"\$OTHER\" --set-metadata parent=\"\$GC_BEAD_ID\" $S"
    echo '```'
} > "$TMP/clean/mol-good.toml"
eq "$(rc_of "$TMP/clean")" "0" "(CLEAN) the step-close.sh remedy and near-misses pass"
has "$(run "$TMP/clean")" "OK:" "(CLEAN) reports OK"

# --- 4. base-snapshots are excluded ------------------------------------------
mkdir -p "$TMP/snap/doctor/check-x/base-snapshots/formulas"
cp "$TMP/dirty/mol-bad.toml" \
   "$TMP/snap/doctor/check-x/base-snapshots/formulas/mol-bad.toml"
eq "$(rc_of "$TMP/snap")" "0" "(SNAPSHOT) vendored base-snapshots are not scanned"

# --- 4b. specs/ are dated records, docs/ are live ----------------------------
# A finding that QUOTES the defect while diagnosing it must not be edited to
# satisfy a lint; a live doc that PRESCRIBES it must be.
mkdir -p "$TMP/rec/specs/2026-08-x" "$TMP/rec/docs"
cp "$TMP/dirty/mol-bad.toml" "$TMP/rec/specs/2026-08-x/findings.md"
eq "$(rc_of "$TMP/rec")" "0" "(SPECS) a dated spec record is not scanned"
cp "$TMP/dirty/mol-bad.toml" "$TMP/rec/docs/live-guide.md"
eq "$(rc_of "$TMP/rec")" "2" "(DOCS) the same content under docs/ IS scanned"

# --- 4c. generated/ is a TIER rule, not a per-tree exception -----------------
# The exclusion is written */generated/*, so any machine-written tree inherits
# it — not only generated/seed-audit/. Both fixtures below are the same content
# 4b just proved IS scanned under docs/, so a pass here is the exclusion firing
# and not an inert fixture.
mkdir -p "$TMP/gen/generated/seed-audit/formulas" \
         "$TMP/gen/generated/next-artifact"
cp "$TMP/dirty/mol-bad.toml" \
   "$TMP/gen/generated/seed-audit/formulas/mol-shutdown-dance.md"
cp "$TMP/dirty/mol-bad.toml" "$TMP/gen/generated/next-artifact/mol-bad.md"
eq "$(rc_of "$TMP/gen")" "0" "(GENERATED) the generated tier is not scanned"

# --- 5. an empty tree is OK, not a false pass on a broken scan ---------------
mkdir -p "$TMP/empty"
eq "$(rc_of "$TMP/empty")" "0" "(EMPTY) an empty tree exits 0"
has "$(run "$TMP/empty")" "nothing to check" "(EMPTY) says the scan found no files"

# --- 6. THE REGRESSION ANCHOR: the shipped pack tree is clean ----------------
eq "$(rc_of "$ROOT")" "0" "(SHIPPED) the pack tree has no env-id step close"
SHIPPED="$(run "$ROOT")"
has "$SHIPPED" "OK:" "(SHIPPED) the shipped tree reports OK"
hasnt "$SHIPPED" "step-close site(s) close a bead" "(SHIPPED) no findings on the shipped tree"

echo
echo "check-step-close-owns-bead: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
