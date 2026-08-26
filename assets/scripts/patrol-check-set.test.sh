#!/usr/bin/env bash
# Hermetic test for the check_set the refinery patrol stamps on a NEW anchor
# (formulas/mol-refinery-patrol.toml merge-push, steps 4 and 5).
#
# The defect: gate-ensure.sh stamps the declared default only when check_set is
# absent or empty. merge-push stamps a non-empty value on every anchor it
# transitions, so the formula's own default is the one fresh work actually
# gets. While the formula said `codex` and the registry said `codex,triage`,
# every new anchor was born gated on codex alone and check.triage was never
# dispatched — the declared default bypassed on exactly the path that mints
# anchors.
#
# So this pins two things. Statically: one default, agreed by the three files
# that name it (the lifecycle registry, the patrol formula, gate-ensure.sh).
# Executably: the merge-push path itself, running the normalize snippet and the
# terminal transition arm extracted verbatim from the formula, so the value the
# lifecycle call receives is the shipped instruction's and cannot drift from it.
# No live city, Dolt, network, or PRs.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-refinery-patrol.toml"
LIFECYCLE="$ROOT/lifecycle/lifecycle.toml"
GATE="$HERE/gate-ensure.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }

# --- The declared default, and the three files that must agree on it. --------
# lifecycle/lifecycle.toml is the registry: it declares the state space, so it
# is the one this reads first and the others are held to.
DECLARED=$(sed -n 's/^check_set_default[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$LIFECYCLE" | head -1)
[ -n "$DECLARED" ] \
  && ok "(1) lifecycle.toml declares check_set_default ($DECLARED)" \
  || bad "(1) lifecycle.toml declares no check_set_default — nothing to hold the others to"
case "$DECLARED" in
  *,*) ok "(1b) the declared default is a multi-gate set" ;;
  *)   bad "(1b) the declared default '$DECLARED' names one gate; triage is meant to be standing" ;;
esac

FORMULA_DEFAULT=$(awk '
  /^\[vars\.check_set\]/ { f = 1; next }
  f && /^\[/ { exit }
  f && /^default[[:space:]]*=/ {
    sub(/^default[[:space:]]*=[[:space:]]*"/, ""); sub(/".*$/, ""); print; exit
  }' "$TOML")
eq "$FORMULA_DEFAULT" "$DECLARED" "(2) the patrol formula's check_set var carries the declared default"

FORMULA_EMPTY=$(sed -n "s/^  '')[[:space:]]*CHECK_SET=\"\([^\"]*\)\".*/\1/p" "$TOML" | head -1)
eq "$FORMULA_EMPTY" "$DECLARED" "(3) …and its empty-normalization recovers the same default, not an older one"

GATE_DEFAULT=$(sed -n 's/^DEFAULT_CHECK_SET="\([^"]*\)".*/\1/p' "$GATE" | head -1)
eq "$GATE_DEFAULT" "$DECLARED" "(4) gate-ensure.sh stamps the declared default"
GATE_EMPTY=$(sed -n "s/^  '')[[:space:]]*DEFAULT_CHECK_SET=\"\([^\"]*\)\".*/\1/p" "$GATE" | head -1)
eq "$GATE_EMPTY" "$DECLARED" "(5) …and recovers it from an empty --default"
GATE_ARG=$(sed -n 's/.*--default).*DEFAULT_CHECK_SET="${2:-\([^}]*\)}".*/\1/p' "$GATE" | head -1)
eq "$GATE_ARG" "$DECLARED" "(6) …and from a --default given with no value"

# --- The merge-push path, executed. ------------------------------------------
# The normalize snippet and the terminal transition arm, verbatim from the
# formula, wired to a lifecycle stub that records its argv. This is the path
# that mints anchors; a static read of the var default alone would not have
# caught the defect, because the value has to survive normalization AND reach
# the transition call.
NORMALIZE=$(awk '/# >>> check-set-normalize/{f=1;next} /# <<< check-set-normalize/{f=0} f' "$TOML")
TERMINAL=$(awk '/# >>> one-anchor-per-pr-terminal/{f=1;next} /# <<< one-anchor-per-pr-terminal/{f=0} f' "$TOML")
[ -n "$NORMALIZE" ] \
  && ok "(7a) normalize snippet extracted between check-set-normalize markers" \
  || bad "(7a) normalize snippet extraction EMPTY — markers missing from $TOML"
[ -n "$TERMINAL" ] \
  && ok "(7b) terminal snippet extracted between one-anchor-per-pr-terminal markers" \
  || bad "(7b) terminal snippet extraction EMPTY — markers missing from $TOML"

mkdir -p "$TMP/bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/git"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/gc"
cat > "$TMP/bin/lc-stub" <<'L'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${LCLOG:?}"
L
chmod +x "$TMP/bin/git" "$TMP/bin/gc" "$TMP/bin/lc-stub"
export LCLOG="$TMP/lc.log"
PATH="$TMP/bin:$PATH"

# {{check_set}} is hand-substituted by the --root-only pour, so the snippet is
# rendered the way the pour renders it rather than fed a pre-set variable, and
# the default cases render it from the formula's OWN var default — what an
# unparameterized pour actually writes — then hold the result to the registry.
run_mergepush() { # <rendered {{check_set}}> <pre_open> <pr_url> <pr_number>
  : > "$LCLOG"
  { printf 'CHECK_SET="%s"\n' "$1"; printf '%s\n' "$NORMALIZE"; printf '%s\n' "$TERMINAL"; } > "$TMP/mergepush.sh"
  EXISTING_ANCHOR="" WORK=w1 BRANCH=polecat/w1 TARGET=main \
    LC="$TMP/bin/lc-stub" PRE_OPEN="$2" PR_URL="$3" PR_NUMBER="$4" \
    bash "$TMP/mergepush.sh" >/dev/null 2>&1
  cat "$LCLOG"
}
stamped() { sed -n 's/.*check_set=\([^ ]*\).*/\1/p' <<< "$1" | head -1; }

lc_out=$(run_mergepush "$FORMULA_DEFAULT" 1 "" "")
eq "$(stamped "$lc_out")" "$DECLARED" "(8) a fresh pre-open anchor is stamped the declared default"
case "$lc_out" in
  *"--to pre_open_gate"*) ok "(8b) …on the pre_open_gate transition" ;;
  *) bad "(8b) expected a pre_open_gate transition (got: $lc_out)" ;;
esac

lc_out=$(run_mergepush "$FORMULA_DEFAULT" 0 "https://github.com/o/r/pull/7" 7)
eq "$(stamped "$lc_out")" "$DECLARED" "(9) a fresh post-open anchor is stamped the declared default"
case "$lc_out" in
  *"--to pull_request"*) ok "(9b) …on the pull_request transition" ;;
  *) bad "(9b) expected a pull_request transition (got: $lc_out)" ;;
esac

# A mis-substituted pour renders {{check_set}} empty. Empty must never reach an
# anchor: it is not the `none` opt-out, and merge.sh holds on it forever.
lc_out=$(run_mergepush "" 1 "" "")
eq "$(stamped "$lc_out")" "$DECLARED" "(10) an empty render recovers the declared default rather than un-gating"

lc_out=$(run_mergepush "none" 1 "" "")
eq "$(stamped "$lc_out")" "none" "(11) the none sentinel is stamped as itself, never widened to the default"

lc_out=$(run_mergepush "codex,triage,arch" 1 "" "")
eq "$(stamped "$lc_out")" "codex,triage,arch" "(12) an explicit wider set is passed through untouched"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
