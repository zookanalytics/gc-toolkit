#!/usr/bin/env bash
# Hermetic test for doctor/check-merge-gate-drop/run.sh (the silently-dropped
# merge-gate detector). Stubs `gc` on PATH — rig roster, resolved config,
# formula var declarations, and the bead ledger — and builds a throwaway pack
# dir for the pour-site scan. No live city, Dolt, or network.
#
# Covered:
#   (1)  clean city: every rig resolves the declared default, live anchors
#        carry it -> OK (exit 0)
#   (2)  LIVE anchor stamped check_set="" vs declared "codex" -> ERROR (exit 2),
#        naming rig, bead, and expected-vs-actual  [the shutupandlisten class]
#   (3)  pre_open_gate anchor stamped "" -> ERROR too (both gating shapes)
#   (4)  UNSET check_set on a live pull_request anchor -> NOT flagged
#        (absent is the legacy-permissive norm; flagging it would strand ~325
#        anchors and regress the merge-skill.sh:157-164 fix)
#   (5)  merge_result=merged anchor stamped "" -> NOT flagged (landed work is
#        out of scope: past PRs are reviewed manually)
#   (6)  bead stamped "" with NO merge_result -> NOT flagged (direct-merge
#        beads never reach merge-skill.sh)
#   (7)  rig formula_vars.check_set="" -> WARN (exit 1) with expected-vs-actual
#   (8)  rig formula_vars.check_set="codex" (non-empty override) -> not flagged
#   (9)  declared default itself empty -> NOT flagged at either arm
#        (the signal is divergence, not gatelessness)
#   (10) pour-site `--var check_set=` (empty) -> WARN for every rig
#   (11) pour-site `--var check_set=codex` -> not flagged
#   (12) suspended rig -> skipped, and its bead store is never queried
#   (13) HQ rig -> skipped
#   (14) rig roster unavailable -> WARN (exit 1), never a silent OK
#   (15) bead store unavailable for a rig -> WARN (exit 1), never a silent OK
#   (16) formula var declarations unreadable -> WARN (exit 1)
#   (17) .config.Rigs schema drift -> WARN (exit 1), arm 1b declared unread
#   (18) error outranks warning when both fire
#   (INV) detect-only: no fix.sh ships next to run.sh (a sibling fix.sh would
#        auto-opt this check into `gc doctor --fix`)
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/run.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq() { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { grep -q -- "$1" "$2" && ok "$3" || bad "$3 (missing '$1' in $(cat "$2"))"; }
hasnt() { grep -q -- "$1" "$2" && bad "$3 (unexpected '$1')" || ok "$3"; }

# ---------------------------------------------------------------------------
# Stub `gc`. Every invocation is logged so a test can assert that a suspended
# rig's store was never touched.
# ---------------------------------------------------------------------------
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'STUB'
#!/usr/bin/env bash
D="${GC_STUB_DIR:?}"
echo "$*" >> "$D/calls.log"
sub="${1:-}"; shift || true
case "$sub" in
    rig)
        if [ -f "$D/rigs.json" ]; then cat "$D/rigs.json"; exit 0; fi
        exit 1
        ;;
    config)
        if [ -f "$D/config.json" ]; then cat "$D/config.json"; exit 0; fi
        exit 1
        ;;
    bd)
        rig=""
        if [ "${1:-}" = "--rig" ]; then rig="${2:-}"; shift 2; fi
        case "${1:-}" in
            formula) f="$D/formula-$rig.json" ;;
            list)    f="$D/anchors-$rig.json" ;;
            *)       exit 1 ;;
        esac
        if [ -f "$f" ]; then cat "$f"; exit 0; fi
        exit 1
        ;;
esac
exit 1
STUB
chmod +x "$TMP/bin/gc"

# ---------------------------------------------------------------------------
# Throwaway pack dirs for the pour-site scan (arm 1a).
#   pack-clean  — pour sites pass no --var check_set at all (today's shape)
#   pack-empty  — a pour site passes an EXPLICITLY empty --var check_set=
#   pack-codex  — a pour site passes a non-empty --var check_set=codex
# ---------------------------------------------------------------------------
make_pack() { # $1=dir  $2=pour-site var text (may be empty)
    mkdir -p "$1/formulas" "$1/template-fragments"
    cat > "$1/formulas/mol-refinery-patrol.toml" <<EOF
[vars.check_set]
default = "codex"
NEXT=\$(gc bd mol wisp mol-refinery-patrol --root-only --var target_branch=main $2 --json)
EOF
    cat > "$1/template-fragments/layered-startup-discovery.template.md" <<'EOF'
WISP=$(gc bd mol wisp mol-refinery-patrol --root-only --var rig_name=x --json)
EOF
}
make_pack "$TMP/pack-clean" ""
make_pack "$TMP/pack-empty" "--var check_set="
make_pack "$TMP/pack-codex" "--var check_set=codex"

# ---------------------------------------------------------------------------
# Fixture builders.
# ---------------------------------------------------------------------------
FORMULA_CODEX='{"vars":{"check_set":{"default":"codex"},"other":{"default":"x"}}}'
FORMULA_GATELESS='{"vars":{"check_set":{"default":""}}}'

rigs_default() { # active alpha + active beta + suspended zulu + hq
    cat > "$1/rigs.json" <<'EOF'
{"ok":true,"rigs":[
 {"name":"loomington","hq":true,"suspended":false},
 {"name":"alpha","hq":false,"suspended":false},
 {"name":"beta","hq":false,"suspended":false},
 {"name":"zulu","hq":false,"suspended":true}
]}
EOF
}

config_no_overrides() {
    cat > "$1/config.json" <<'EOF'
{"ok":true,"config":{"Rigs":[
 {"Name":"alpha","FormulaVars":null},
 {"Name":"beta","FormulaVars":null},
 {"Name":"zulu","FormulaVars":null}
]}}
EOF
}

# Baseline scenario: two active rigs, codex declared, one healthy live anchor.
scenario() { # $1=name -> echoes dir
    local d="$TMP/$1"
    mkdir -p "$d"
    rigs_default "$d"
    config_no_overrides "$d"
    printf '%s' "$FORMULA_CODEX" > "$d/formula-alpha.json"
    printf '%s' "$FORMULA_CODEX" > "$d/formula-beta.json"
    echo '[{"id":"a-1","metadata":{"check_set":"codex","merge_result":"pull_request","pr_number":10}}]' > "$d/anchors-alpha.json"
    echo '[]' > "$d/anchors-beta.json"
    echo "$d"
}

run_check() { # $1=scenario dir  $2=pack dir (default pack-clean)
    local d="$1" pack="${2:-$TMP/pack-clean}"
    GC_STUB_DIR="$d" GC_PACK_DIR="$pack" PATH="$TMP/bin:$PATH" \
        bash "$SCRIPT" > "$d/out" 2>&1
    echo $?
}

# --- (1) clean city --------------------------------------------------------
D=$(scenario clean)
rc=$(run_check "$D")
eq "$rc" "0" "(1) clean city -> exit 0"
has "no silently-dropped merge gates" "$D/out" "(1) clean city reports the green summary"
has "2 rig(s)" "$D/out" "(1) clean city counts both active rigs"

# --- (12)(13) suspended + HQ rigs skipped ----------------------------------
has "zulu: skipped (suspended" "$D/out" "(12) suspended rig is reported as skipped"
hasnt "\-\-rig zulu" "$D/calls.log" "(12) suspended rig's bead store is never queried"
hasnt "\-\-rig loomington" "$D/calls.log" "(13) HQ rig is never queried"

# --- (2) live pull_request anchor stamped "" -------------------------------
D=$(scenario live-empty)
echo '[{"id":"a-9","metadata":{"check_set":"","merge_result":"pull_request","pr_number":42}}]' > "$D/anchors-alpha.json"
rc=$(run_check "$D")
eq "$rc" "2" "(2) live anchor stamped empty -> exit 2 (error)"
has "alpha/a-9" "$D/out" "(2) error names rig and bead"
has "#42" "$D/out" "(2) error names the PR"
has 'expected "codex", actual ""' "$D/out" "(2) error reports expected-vs-actual"

# --- (3) pre_open_gate anchor stamped "" -----------------------------------
D=$(scenario live-preopen)
echo '[{"id":"a-8","metadata":{"check_set":"","merge_result":"pre_open_gate"}}]' > "$D/anchors-alpha.json"
rc=$(run_check "$D")
eq "$rc" "2" "(3) pre_open_gate anchor stamped empty -> exit 2"
has "merge_result=pre_open_gate" "$D/out" "(3) error names the gating shape"

# --- (4) unset check_set is NOT a drop -------------------------------------
D=$(scenario unset-ok)
echo '[{"id":"a-7","metadata":{"merge_result":"pull_request","pr_number":7}}]' > "$D/anchors-alpha.json"
rc=$(run_check "$D")
eq "$rc" "0" "(4) unset check_set on a live anchor -> exit 0 (absent is not empty)"

# --- (5) landed anchor is out of scope -------------------------------------
D=$(scenario merged-out-of-scope)
echo '[{"id":"a-6","metadata":{"check_set":"","merge_result":"merged","pr_number":6}}]' > "$D/anchors-alpha.json"
rc=$(run_check "$D")
eq "$rc" "0" "(5) merged anchor stamped empty -> exit 0 (historical, out of scope)"

# --- (6) non-anchor bead is out of scope -----------------------------------
D=$(scenario no-merge-result)
echo '[{"id":"a-5","metadata":{"check_set":""}}]' > "$D/anchors-alpha.json"
rc=$(run_check "$D")
eq "$rc" "0" "(6) bead stamped empty with no merge_result -> exit 0 (direct-merge)"

# --- (7) rig formula_vars empty override -> WARN ---------------------------
D=$(scenario formula-vars-empty)
cat > "$D/config.json" <<'EOF'
{"ok":true,"config":{"Rigs":[
 {"Name":"alpha","FormulaVars":{"check_set":""}},
 {"Name":"beta","FormulaVars":null}
]}}
EOF
rc=$(run_check "$D")
eq "$rc" "1" "(7) rig formula_vars check_set=\"\" -> exit 1 (warning)"
has "rig formula_vars.check_set" "$D/out" "(7) warning names the override source"
has 'expected "codex", actual ""' "$D/out" "(7) warning reports expected-vs-actual"
hasnt "beta: resolved" "$D/out" "(7) the sibling rig without the override is not flagged"

# --- (8) non-empty override is not a drop ----------------------------------
D=$(scenario formula-vars-codex)
cat > "$D/config.json" <<'EOF'
{"ok":true,"config":{"Rigs":[{"Name":"alpha","FormulaVars":{"check_set":"codex"}}]}}
EOF
rc=$(run_check "$D")
eq "$rc" "0" "(8) rig formula_vars check_set=codex -> exit 0"

# --- (9) empty declared default is gateless by declaration -----------------
D=$(scenario gateless-declaration)
printf '%s' "$FORMULA_GATELESS" > "$D/formula-alpha.json"
printf '%s' "$FORMULA_GATELESS" > "$D/formula-beta.json"
echo '[{"id":"a-4","metadata":{"check_set":"","merge_result":"pull_request","pr_number":4}}]' > "$D/anchors-alpha.json"
rc=$(run_check "$D")
eq "$rc" "0" "(9) empty declared default -> exit 0 (divergence, not emptiness, is the signal)"
has "gateless by declaration" "$D/out" "(9) the gateless declaration is noted, not flagged"

# --- (10) pour-site empty --var override -> WARN for every rig -------------
D=$(scenario pour-empty)
rc=$(run_check "$D" "$TMP/pack-empty")
eq "$rc" "1" "(10) pour-site --var check_set= (empty) -> exit 1 (warning)"
has "pour-site override" "$D/out" "(10) warning names the pour-site source"
has "formulas/mol-refinery-patrol.toml:" "$D/out" "(10) warning names file:line"
eq "$(grep -c 'pour-site override' "$D/out")" "2" "(10) a pour-site override is reported for every rig"

# --- (11) non-empty pour-site override is not a drop -----------------------
D=$(scenario pour-codex)
rc=$(run_check "$D" "$TMP/pack-codex")
eq "$rc" "0" "(11) pour-site --var check_set=codex -> exit 0"

# --- (14) rig roster unavailable -------------------------------------------
D=$(scenario no-roster)
rm -f "$D/rigs.json"
rc=$(run_check "$D")
eq "$rc" "1" "(14) unavailable rig roster -> exit 1, never a silent OK"
has "could not enumerate rigs" "$D/out" "(14) the undetermined roster is reported"

# --- (15) bead store unavailable for a rig ---------------------------------
D=$(scenario no-store)
rm -f "$D/anchors-alpha.json"
rc=$(run_check "$D")
eq "$rc" "1" "(15) unavailable bead store -> exit 1, never a silent OK"
has "live ungated anchors undetermined" "$D/out" "(15) the undetermined arm is reported"

# --- (16) formula declarations unreadable ----------------------------------
D=$(scenario no-formula)
rm -f "$D/formula-alpha.json"
rc=$(run_check "$D")
eq "$rc" "1" "(16) unreadable formula vars -> exit 1"
has "merge-gate drop undetermined for this rig" "$D/out" "(16) the undetermined rig is reported"

# --- (17) resolved-config schema drift -------------------------------------
D=$(scenario config-drift)
echo '{"ok":true,"config":{"rigs":[]}}' > "$D/config.json"
rc=$(run_check "$D")
eq "$rc" "1" "(17) .config.Rigs schema drift -> exit 1"
has "rig formula_vars overrides unreadable" "$D/out" "(17) the unread override layer is reported"

# --- (18) error outranks warning -------------------------------------------
D=$(scenario error-outranks)
echo '[{"id":"a-3","metadata":{"check_set":"","merge_result":"pull_request","pr_number":3}}]' > "$D/anchors-alpha.json"
rm -f "$D/formula-beta.json"   # also produces a warning
rc=$(run_check "$D")
eq "$rc" "2" "(18) error + warning -> exit 2"
has "ERROR: alpha/a-3" "$D/out" "(18) the error is reported"
has "WARN:  beta" "$D/out" "(18) the warning is still reported alongside it"

# --- (INV) detect-only: no fix script --------------------------------------
[ -e "$HERE/fix.sh" ] \
    && bad "(INV) a sibling fix.sh would auto-opt this detect-only check into gc doctor --fix" \
    || ok "(INV) no fix.sh ships next to run.sh (detect only)"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
