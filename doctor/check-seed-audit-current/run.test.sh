#!/usr/bin/env bash
# Hermetic test for doctor/check-seed-audit-current (tk-yhwfv.3).
#
# WHAT IS EXERCISED
#   * the MISSING arm — the renderer ships but the artifact does not;
#   * the STALE arm — an input file moves and the recorded digest no longer
#     matches, which is the whole reason the check exists;
#   * the UNVERIFIABLE arm — an INDEX.md with no digest line (hand-edited, or
#     written by an older renderer) is a finding, not a silent pass;
#   * the OK arm, with core.hooksPath wired;
#   * the hook-not-wired WARNING, and that it does not mask a current artifact;
#   * the gc-version WARNING being a warning and not an error, which is the
#     tier-1/tier-2 split this artifact was scoped on;
#   * the no-renderer skip, so a pack without the script is not reported broken;
#   * that the check reads GC_PACK_DIR rather than its own location, since
#     `gc doctor` runs it against an installed pack, not this checkout.
#
# The digest is recomputed by the SHIPPED renderer (--print-digest), so these
# fixtures carry a real digest rather than a hardcoded one: hardcoding would
# make the test pass while the two halves drifted apart.
#
# No live city, Dolt, network, or beads — only a tmpdir, git, and the check.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
CHECK="$HERE/run.sh"
RENDERER="$ROOT/assets/scripts/render-seed-audit.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

# A minimal pack fixture: enough shape for digest_inputs() to find something,
# plus the shipped renderer so --print-digest is the real implementation.
make_pack() {
    local d="$1"
    mkdir -p "$d/agents/sample" "$d/template-fragments" "$d/formulas" "$d/packs" \
             "$d/assets/scripts" "$d/assets/hooks" "$d/docs/seed-audit/agents" \
             "$d/docs/seed-audit/formulas"
    printf 'name = "fixture"\n' > "$d/pack.toml"
    printf 'prompt body\n'      > "$d/agents/sample/prompt.template.md"
    printf 'fragment body\n'    > "$d/template-fragments/frag.template.md"
    printf 'formula = "mol-x"\n' > "$d/formulas/mol-x.toml"
    cp "$RENDERER" "$d/assets/scripts/render-seed-audit.sh"
    cp "$ROOT/assets/hooks/pre-commit" "$d/assets/hooks/pre-commit"
    chmod +x "$d/assets/scripts/render-seed-audit.sh" "$d/assets/hooks/pre-commit"
    git -C "$d" init -q .
    git -C "$d" config core.hooksPath assets/hooks
}

write_index() {
    local d="$1" digest="$2" gcver="${3:-1.4.1}"
    printf 'placeholder\n' > "$d/docs/seed-audit/agents/sample.md"
    printf 'placeholder\n' > "$d/docs/seed-audit/formulas/mol-x.md"
    {
        echo "# Agent Seed Audit"
        echo ""
        echo "- \`gc\` version: \`$gcver\`"
        echo "- source digest: \`$digest\`"
    } > "$d/docs/seed-audit/INDEX.md"
}

run_check() {
    local d="$1"
    GC_PACK_DIR="$d" bash "$CHECK" > "$TMP/out.txt" 2>"$TMP/err.txt"
    echo "$?" > "$TMP/rc.txt"
}

rc_of()  { cat "$TMP/rc.txt"; }
out_of() { cat "$TMP/out.txt"; }

# ---------------------------------------------------------------- no renderer
P="$TMP/no-renderer"; make_pack "$P"; rm -f "$P/assets/scripts/render-seed-audit.sh"
run_check "$P"
if [ "$(rc_of)" = "0" ] && grep -F 'no render-seed-audit.sh' <<< "$(out_of)" >/dev/null; then
    ok "a pack without the renderer is skipped, not reported broken"
else
    bad "no-renderer skip (rc=$(rc_of)): $(out_of | head -1)"
fi

# ------------------------------------------------------------------- missing
P="$TMP/missing"; make_pack "$P"
run_check "$P"
if [ "$(rc_of)" = "2" ] && grep -F 'MISSING' <<< "$(out_of)" >/dev/null; then
    ok "a shipped renderer with no committed artifact is an ERROR"
else
    bad "missing-artifact arm (rc=$(rc_of)): $(out_of | head -1)"
fi

# --------------------------------------------------------------- no digest
P="$TMP/nodigest"; make_pack "$P"
printf '# Agent Seed Audit\n\nno digest line here\n' > "$P/docs/seed-audit/INDEX.md"
run_check "$P"
if [ "$(rc_of)" = "2" ] && grep -F 'UNVERIFIABLE' <<< "$(out_of)" >/dev/null; then
    ok "an INDEX.md with no digest line is a finding, not a silent pass"
else
    bad "no-digest arm (rc=$(rc_of)): $(out_of | head -1)"
fi

# --------------------------------------------------------------------- OK
P="$TMP/ok"; make_pack "$P"
D="$("$P/assets/scripts/render-seed-audit.sh" --root "$P" --print-digest)"
GCVER="$(gc version 2>/dev/null | head -1)"; [ -n "$GCVER" ] || GCVER="1.4.1"
write_index "$P" "$D" "$GCVER"
run_check "$P"
if [ "$(rc_of)" = "0" ] && grep -F 'OK: seed audit current' <<< "$(out_of)" >/dev/null; then
    ok "a current artifact with the hook wired is OK"
else
    bad "OK arm (rc=$(rc_of)): $(out_of | head -3)"
fi

# ------------------------------------------------------------------- stale
P="$TMP/stale"; make_pack "$P"
D="$("$P/assets/scripts/render-seed-audit.sh" --root "$P" --print-digest)"
write_index "$P" "$D" "$GCVER"
printf 'a fragment moved after the render\n' >> "$P/template-fragments/frag.template.md"
run_check "$P"
if [ "$(rc_of)" = "2" ] && grep -F 'STALE' <<< "$(out_of)" >/dev/null; then
    ok "an input moving after the render is an ERROR"
else
    bad "stale arm (rc=$(rc_of)): $(out_of | head -1)"
fi

# Same again through a path the bead's hook trigger list also names, to prove the
# digest is not watching template-fragments/ alone.
P="$TMP/stale-formula"; make_pack "$P"
D="$("$P/assets/scripts/render-seed-audit.sh" --root "$P" --print-digest)"
write_index "$P" "$D" "$GCVER"
printf 'extra = true\n' >> "$P/formulas/mol-x.toml"
run_check "$P"
if [ "$(rc_of)" = "2" ]; then
    ok "a formula edit also moves the digest"
else
    bad "stale-formula arm (rc=$(rc_of)): $(out_of | head -1)"
fi

# A file OUTSIDE the input set must NOT move the digest, or every commit in the
# repo would be reported stale and the check would be noise.
P="$TMP/unrelated"; make_pack "$P"
D="$("$P/assets/scripts/render-seed-audit.sh" --root "$P" --print-digest)"
write_index "$P" "$D" "$GCVER"
mkdir -p "$P/docs"; printf 'unrelated prose\n' > "$P/docs/something-else.md"
run_check "$P"
if [ "$(rc_of)" = "0" ]; then
    ok "an edit outside the input set leaves the artifact current"
else
    bad "unrelated-edit arm should stay OK (rc=$(rc_of)): $(out_of | head -1)"
fi

# ------------------------------------------------------------- hook not wired
P="$TMP/nohook"; make_pack "$P"
git -C "$P" config --unset core.hooksPath
D="$("$P/assets/scripts/render-seed-audit.sh" --root "$P" --print-digest)"
write_index "$P" "$D" "$GCVER"
run_check "$P"
if [ "$(rc_of)" = "1" ] && grep -F 'core.hooksPath is unset' <<< "$(out_of)" >/dev/null; then
    ok "a current artifact with no hook wired is a WARNING"
else
    bad "hook-unwired arm (rc=$(rc_of)): $(out_of | head -2)"
fi
if grep -F 'STALE' <<< "$(out_of)" >/dev/null; then
    bad "hook-unwired warning must not claim the content is stale"
else
    ok "the hook warning does not misreport current content as stale"
fi

# --------------------------------------------------------------- gc version
P="$TMP/gcver"; make_pack "$P"
D="$("$P/assets/scripts/render-seed-audit.sh" --root "$P" --print-digest)"
write_index "$P" "$D" "0.0.0-not-the-host-version"
run_check "$P"
if command -v gc >/dev/null 2>&1; then
    if [ "$(rc_of)" = "1" ] && grep -F 'gc version drift' <<< "$(out_of)" >/dev/null; then
        ok "gc version drift is a WARNING, never an error"
    else
        bad "gc-version arm (rc=$(rc_of)): $(out_of | head -2)"
    fi
else
    if [ "$(rc_of)" = "0" ]; then
        ok "gc version drift is not reported on a host with no gc (skipped)"
    else
        bad "no-gc host should not report version drift (rc=$(rc_of))"
    fi
fi

# ------------------------------------------------------------- GC_PACK_DIR
# The check must read the pack it was pointed at, not the checkout it lives in.
# Running it from an unrelated cwd against a stale fixture proves it.
P="$TMP/packdir"; make_pack "$P"
D="$("$P/assets/scripts/render-seed-audit.sh" --root "$P" --print-digest)"
write_index "$P" "$D" "$GCVER"
printf 'moved\n' >> "$P/agents/sample/prompt.template.md"
( cd "$TMP" && GC_PACK_DIR="$P" bash "$CHECK" > "$TMP/out.txt" 2>&1; echo "$?" > "$TMP/rc.txt" )
if [ "$(rc_of)" = "2" ] && grep -F 'STALE' <<< "$(out_of)" >/dev/null; then
    ok "the check honours GC_PACK_DIR rather than its own location"
else
    bad "GC_PACK_DIR arm (rc=$(rc_of)): $(out_of | head -1)"
fi

# ------------------------------------------------------ the SHIPPED pack tree
# The regression anchor. If a future change edits a fragment without
# regenerating docs/seed-audit/, this line goes red. A hook-not-wired warning
# (rc=1) is tolerated here because core.hooksPath is per-checkout local config
# and cannot travel in a commit; a STALE or MISSING content finding is not.
run_check "$ROOT"
case "$(rc_of)" in
    0) ok "the shipped pack tree reports a current seed audit" ;;
    1) if grep -F 'content is current' <<< "$(out_of)" >/dev/null; then
           ok "the shipped pack tree's audit content is current (upkeep warning only)"
       else
           bad "shipped tree warning is not an upkeep warning: $(out_of | head -1)"
       fi ;;
    *) bad "the shipped pack tree's seed audit is not current: $(out_of | head -1)" ;;
esac

echo ""
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
