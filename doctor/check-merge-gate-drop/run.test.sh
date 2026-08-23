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
#        anchors and regress merge-skill.sh's no-gate `hold_gate` fix)
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
#   (19) live anchor with check.<gate>=exception@<sha> -> WARN (exit 1), naming
#        the gate, the marker and the recorded reason  [WS4, tk-zgse0]
#   (20) the verdict arm's SIDECAR keys (.reason/.attempts/.exception_escalated)
#        are never mistaken for a gate marker, and green@/fixable@ are not flagged
#   (21) an exception on a MERGED anchor is out of scope, like every other arm
#   (22) an exception-held gate whose anchor has LIVE remediation naming it
#        (source_anchor_bead) -> NOT escalated: noted, exit 0, and counted in the
#        summary  [tk-ezgr2, the acceptance case]
#   (23) ...same via the BROAD surface, a live rework child on the anchor's branch
#   (24) an INERT bead on that branch (open, unrouted, unclaimed) does NOT
#        suppress — a stranded anchor must still be reported
#   (25) the anchor ITSELF is on its own branch, and does not suppress itself
#        (the live shape: a held anchor sits open with gc.routed_to=human)
#   (26) a live bead on the branch that names ANOTHER anchor does not suppress
#   (27) an unreadable ledger reports the exception anyway, as UNDETERMINED
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
            list)
                # Two shapes of `list` reach here and they must not share a
                # fixture: the anchor sweep (--has-metadata-key check_set) and
                # the ownership lookups (--metadata-field <key>=<value>). One
                # fixture for both would answer "is anything remediating this
                # anchor?" with the anchor list itself.
                mf=""; prev=""
                for a in "$@"; do
                    [ "$prev" = "--metadata-field" ] && mf="$a"
                    case "$a" in --metadata-field=*) mf="${a#--metadata-field=}" ;; esac
                    prev="$a"
                done
                if [ -n "$mf" ]; then
                    # `live-fail` makes the ledger unanswerable, which is NOT
                    # the same as answering "nothing in flight".
                    [ -f "$D/live-fail" ] && exit 1
                    key="${mf%%=*}"; val="${mf#*=}"
                    safe=$(printf '%s' "$val" | tr -c 'A-Za-z0-9._-' '_')
                    f="$D/live-$key-$safe.json"
                    # An absent fixture is an empty answer, not a broken store.
                    [ -f "$f" ] || { echo '[]'; exit 0; }
                else
                    f="$D/anchors-$rig.json"
                fi
                ;;
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
# The ownership lookups are per-exception, not per-rig: a city with no held gate
# must not spend a single extra query on them.
hasnt "metadata-field" "$D/calls.log" "(22) no ownership lookup runs when no gate is held in exception"

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

# --- (19) a gate held in EXCEPTION is surfaced as a warning ------------------
# WS4 (tk-zgse0): `check.<name>=exception@<sha>` is the third verdict verb. The
# hold is correct — it is the gate working — but it is unbounded and it announces
# itself to an operator exactly once per head, so `gc doctor` is the only place a
# human can later find it.
D=$(scenario gate-exception)
cat > "$D/anchors-alpha.json" <<'JSON'
[{"id":"a-x1","metadata":{"check_set":"codex","merge_result":"pull_request","pr_number":77,
  "check.codex":"exception@deadbeef",
  "check.codex.reason":"attempts-exhausted: 3 remediation round(s) spent against a cap of 3",
  "check.codex.attempts":"3@deadbeef",
  "check.codex.exception_escalated":"deadbeef"}}]
JSON
rc=$(run_check "$D")
eq "$rc" "1" "(19) exception-held gate -> exit 1 (warning, not error: the gate is working)"
has "alpha/a-x1" "$D/out" "(19) warning names rig and bead"
has "HELD IN EXCEPTION" "$D/out" "(19) warning names the state"
has "exception@deadbeef" "$D/out" "(19) warning carries the head-bound marker"
has "attempts-exhausted" "$D/out" "(19) warning carries the recorded reason"
has "#77" "$D/out" "(19) warning names the PR"

# --- (20) sidecar keys and non-exception verbs are not gate exceptions -------
# The arm filters on the VALUE, not the key shape, precisely so the three sidecar
# keys the verdict arm writes beside the marker cannot be read as gates of their
# own — `.attempts` in particular holds a "<n>@<sha>" that looks marker-shaped.
D=$(scenario gate-verbs-ok)
cat > "$D/anchors-alpha.json" <<'JSON'
[{"id":"a-x2","metadata":{"check_set":"codex","merge_result":"pull_request","pr_number":78,
  "check.codex":"green@cafe1234","check.codex.attempts":"1@cafe1234"}},
 {"id":"a-x3","metadata":{"check_set":"codex","merge_result":"pull_request","pr_number":79,
  "check.codex":"fixable@cafe5678","check.codex.attempts":"2@cafe5678"}}]
JSON
rc=$(run_check "$D")
eq "$rc" "0" "(20) green@ and fixable@ markers are not flagged"
hasnt "HELD IN EXCEPTION" "$D/out" "(20) no exception reported for the non-exception verbs"
has "0 gate(s) held in exception" "$D/out" "(20) the clean summary counts the new arm"

# --- (21) an exception on a landed anchor is out of scope -------------------
D=$(scenario gate-exception-merged)
cat > "$D/anchors-alpha.json" <<'JSON'
[{"id":"a-x4","metadata":{"check_set":"codex","merge_result":"merged","pr_number":80,
  "check.codex":"exception@deadbeef"}}]
JSON
rc=$(run_check "$D")
eq "$rc" "0" "(21) exception on a merged anchor -> exit 0 (landed work is out of scope)"

# --- (22) a held gate with LIVE remediation is not escalated -----------------
# The tk-ezgr2 acceptance case. Three false escalations in under 24 hours, each
# sent while a rebase-and-re-author child was mid-flight against the same branch,
# and each costing a full mayor re-triage. Remediation does not run on the anchor
# — it runs on a separate child that names the anchor — so testing the anchor
# alone cannot see it.
D=$(scenario gate-exception-owned)
cat > "$D/anchors-alpha.json" <<'JSON'
[{"id":"a-x5","metadata":{"check_set":"codex","merge_result":"pull_request","pr_number":81,
  "branch":"polecat/a-x5",
  "check.codex":"exception@deadbeef",
  "check.codex.reason":"attempts-exhausted: 3 remediation round(s) spent against a cap of 3"}}]
JSON
cat > "$D/live-source_anchor_bead-a-x5.json" <<'JSON'
[{"id":"a-fix","status":"in_progress","assignee":"alpha/rig.polecat",
  "metadata":{"source_anchor_bead":"a-x5","branch":"polecat/a-x5"}}]
JSON
rc=$(run_check "$D")
eq "$rc" "0" "(22) held gate with live remediation -> exit 0 (nothing to rule on)"
hasnt "HELD IN EXCEPTION" "$D/out" "(22) the held gate is not escalated"
has "a-fix" "$D/out" "(22) the note names the bead that is remediating it"
has "matched on source_anchor_bead" "$D/out" "(22) the note names the surface that linked them"
has "NOT flagged" "$D/out" "(22) the suppression is stated, never silent"
has "already being remediated" "$D/out" "(22) the green summary counts it"

# --- (23) ...and via the BROAD surface: a rework child on the branch ---------
# Rework children never carry source_anchor_bead; the branch they push to is the
# only thing tying them to the anchor.
D=$(scenario gate-exception-owned-branch)
cat > "$D/anchors-alpha.json" <<'JSON'
[{"id":"a-x6","metadata":{"check_set":"codex","merge_result":"pull_request","pr_number":82,
  "branch":"polecat/a-x6","check.codex":"exception@cafe0001"}}]
JSON
cat > "$D/live-branch-polecat_a-x6.json" <<'JSON'
[{"id":"a-rework","status":"open","assignee":"",
  "metadata":{"branch":"polecat/a-x6","gc.routed_to":"alpha/rig.polecat"}}]
JSON
rc=$(run_check "$D")
eq "$rc" "0" "(23) live rework child on the anchor's branch -> exit 0"
has "a-rework" "$D/out" "(23) the note names the rework child"
has "matched on branch" "$D/out" "(23) the note names the weaker surface as such"

# --- (24) an INERT bead on the branch does NOT suppress ---------------------
# The failure mode this check exists to catch is a stranded anchor, so mere
# EXISTENCE must never buy silence. Open + unrouted + unclaimed carries no actor:
# it is exactly what a rebase child whose metadata stamp was dropped leaves
# behind ("a bounded orphan"), and it is not remediation.
D=$(scenario gate-exception-inert)
cat > "$D/anchors-alpha.json" <<'JSON'
[{"id":"a-x7","metadata":{"check_set":"codex","merge_result":"pull_request","pr_number":83,
  "branch":"polecat/a-x7","check.codex":"exception@cafe0002"}}]
JSON
cat > "$D/live-branch-polecat_a-x7.json" <<'JSON'
[{"id":"a-husk","status":"open","assignee":"","metadata":{"branch":"polecat/a-x7"}}]
JSON
rc=$(run_check "$D")
eq "$rc" "1" "(24) an inert husk on the branch -> exit 1 (still reported)"
has "HELD IN EXCEPTION" "$D/out" "(24) the stranded anchor is still escalated"
has "nothing is remediating it" "$D/out" "(24) the warning says the lookup came back empty"

# --- (25) the anchor does not suppress ITSELF --------------------------------
# The branch lookup returns the anchor: it carries its own metadata.branch. Live
# shape, verified against signal-loom/sl-kg9z6.1.2 — open, routed to `human`,
# which makes it claimable and therefore ACTING. Without the self-exclusion this
# arm would go silent on every held anchor in the city.
D=$(scenario gate-exception-self)
cat > "$D/anchors-alpha.json" <<'JSON'
[{"id":"a-x8","metadata":{"check_set":"codex","merge_result":"pull_request","pr_number":84,
  "branch":"polecat/a-x8","check.codex":"exception@cafe0003"}}]
JSON
cat > "$D/live-branch-polecat_a-x8.json" <<'JSON'
[{"id":"a-x8","status":"open","assignee":"",
  "metadata":{"branch":"polecat/a-x8","gc.routed_to":"human"}}]
JSON
rc=$(run_check "$D")
eq "$rc" "1" "(25) the anchor alone on its own branch -> exit 1 (no self-suppression)"
has "HELD IN EXCEPTION" "$D/out" "(25) the held anchor is still escalated"

# --- (26) a bead naming ANOTHER anchor does not suppress --------------------
# `anchor_bead` is authoritative: a bead naming another anchor is positively not
# about this one, and its own anchor holds its own merge.
D=$(scenario gate-exception-theirs)
cat > "$D/anchors-alpha.json" <<'JSON'
[{"id":"a-x9","metadata":{"check_set":"codex","merge_result":"pull_request","pr_number":85,
  "branch":"polecat/a-x9","check.codex":"exception@cafe0004"}}]
JSON
cat > "$D/live-branch-polecat_a-x9.json" <<'JSON'
[{"id":"a-other","status":"in_progress","assignee":"",
  "metadata":{"branch":"polecat/a-x9","anchor_bead":"a-zzz"}}]
JSON
rc=$(run_check "$D")
eq "$rc" "1" "(26) a live bead naming another anchor -> exit 1 (still reported)"
has "HELD IN EXCEPTION" "$D/out" "(26) the held anchor is still escalated"

# --- (27) an unreadable ledger is not "nothing in flight" -------------------
D=$(scenario gate-exception-undetermined)
cat > "$D/anchors-alpha.json" <<'JSON'
[{"id":"a-xa","metadata":{"check_set":"codex","merge_result":"pull_request","pr_number":86,
  "branch":"polecat/a-xa","check.codex":"exception@cafe0005"}}]
JSON
touch "$D/live-fail"
rc=$(run_check "$D")
eq "$rc" "1" "(27) unreadable ownership lookup -> exit 1, never a silent OK"
has "HELD IN EXCEPTION" "$D/out" "(27) the exception is reported anyway"
has "UNDETERMINED" "$D/out" "(27) the failed lookup is named, not assumed owned"

# --- (INV) detect-only: no fix script --------------------------------------
[ -e "$HERE/fix.sh" ] \
    && bad "(INV) a sibling fix.sh would auto-opt this detect-only check into gc doctor --fix" \
    || ok "(INV) no fix.sh ships next to run.sh (detect only)"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
