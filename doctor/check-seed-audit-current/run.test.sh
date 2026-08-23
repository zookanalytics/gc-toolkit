#!/usr/bin/env bash
# Hermetic test for doctor/check-seed-audit-current (tk-yhwfv.3).
#
# WHAT IS EXERCISED
#   * the MISSING arm — the renderer ships but the artifact does not;
#   * the STALE arm — an input file moves and the recorded digest no longer
#     matches, which is the whole reason the check exists;
#   * the RENDERER-only STALE arm — the script carries the synthetic city the
#     prompts render against, so editing its scenario moves the artifact. This
#     one shipped broken (tk-wchab P1): digest_inputs() hashed the content
#     directories and not the renderer, so `--check` saw the tree stale while
#     this check called it current;
#   * that assets/hooks/pre-commit's INPUT_RE covers every root
#     digest_inputs() hashes — two hand-synced lists, asserted against drift —
#     and does NOT match the generated tree;
#   * the UNVERIFIABLE arm — an INDEX.md with no digest line (hand-edited, or
#     written by an older renderer) is a finding, not a silent pass;
#   * the OK arm, with core.hooksPath wired;
#   * the hook-not-wired WARNING, and that it does not mask a current artifact;
#   * the gc-version WARNING being a warning and not an error, which is the
#     tier-1/tier-2 split this artifact was scoped on;
#   * the no-renderer skip, so a pack without the script is not reported broken;
#   * ...and that a renderer which is PRESENT but NOT EXECUTABLE is NOT read as
#     absent. Testing -x for both was a fail-open (pre-open signoff P1): a
#     committed `chmod -x` turned the upkeep loop off while this check printed
#     OK and the pre-commit hook silently skipped. The mode bit must not be able
#     to decide whether this pack is audited, so the staleness read still fires
#     with the bit off;
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
             "$d/assets/scripts" "$d/assets/hooks" "$d/generated/seed-audit/agents" \
             "$d/generated/seed-audit/formulas"
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
    printf 'placeholder\n' > "$d/generated/seed-audit/agents/sample.md"
    printf 'placeholder\n' > "$d/generated/seed-audit/formulas/mol-x.md"
    {
        echo "# Agent Seed Audit"
        echo ""
        echo "- \`gc\` version: \`$gcver\`"
        echo "- source digest: \`$digest\`"
    } > "$d/generated/seed-audit/INDEX.md"
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

# ------------------------------------------------- renderer present, not +x
# The fail-open the pre-open signoff caught. `chmod -x` is a COMMITTED change —
# a mode bit rides in a commit like any other — so this is reachable by an
# ordinary diff, and it used to silence both gates at once while each reported
# success. Two things must hold: the check must not call the renderer absent,
# and the staleness read must still work, because a mode bit deciding whether a
# pack is audited is the whole defect.
P="$TMP/noexec"; make_pack "$P"
chmod -x "$P/assets/scripts/render-seed-audit.sh"
write_index "$P" "$(bash "$P/assets/scripts/render-seed-audit.sh" --root "$P" --print-digest)"
run_check "$P"
if grep -F 'no render-seed-audit.sh' <<< "$(out_of)" >/dev/null; then
    bad "(NOEXEC) a non-executable renderer is reported as ABSENT — the fail-open is back"
else
    ok "(NOEXEC) a present-but-not-executable renderer is not reported as absent"
fi
if [ "$(rc_of)" = "0" ]; then
    bad "(NOEXEC) the check passed clean with the upkeep loop's entry point unrunnable"
else
    ok "(NOEXEC) it is reported (rc=$(rc_of)), not passed as OK"
fi
if grep -qiF 'NOT EXECUTABLE' <<< "$(out_of)"; then
    ok "(NOEXEC) the report names the mode bit, so the fix is obvious"
else
    bad "(NOEXEC) the report must name the executable bit: $(out_of | head -2)"
fi

# ...and the gate is still LIVE with the bit off: stale the artifact and the
# check must still catch it. This is the assertion that makes the arm mean
# something — reporting the mode while going blind to staleness would trade one
# silent failure for another.
printf 'moved\n' >> "$P/agents/sample/prompt.template.md"
run_check "$P"
if [ "$(rc_of)" = "2" ] && grep -F 'STALE' <<< "$(out_of)" >/dev/null; then
    ok "(NOEXEC) staleness is still detected with the renderer non-executable"
else
    bad "(NOEXEC) the mode bit darkened the staleness read (rc=$(rc_of)): $(out_of | head -1)"
fi

# ---------------------------------------------- the hook, with the bit off
# The OTHER half of the same fail-open: assets/hooks/pre-commit tested -x and
# `exit 0`, so the identical `chmod -x` skipped the regeneration silently — the
# reviewer reproduced it by staging nothing but the mode change.
#
# The renderer is STUBBED here, and deliberately. What is under test is whether
# the hook INVOKES it when the executable bit is off, not what a render produces;
# and a real render cannot run against make_pack's fixture at all, because its
# one-line pack.toml does not compose a synthetic city (the renderer says so and
# refuses). The stub echoes a marker no skipped or refused invocation can forge,
# which is the only signal that actually separates the two behaviours — the
# hook's own "regenerating ..." banner is printed BEFORE the renderer is called
# and survives a render that fails outright. A first draft of this test asserted
# on that banner and passed while the hook was invoking a non-executable file and
# aborting the commit.
#
# The real render path is covered by the shipped-tree arm at the end of this file
# and by every --print-digest call above.
P="$TMP/hooknoexec"; make_pack "$P"
write_index "$P" "$(bash "$P/assets/scripts/render-seed-audit.sh" --root "$P" --print-digest)"
git -C "$P" add -A >/dev/null 2>&1
git -C "$P" -c user.email=t@t -c user.name=t commit -q --no-verify -m base >/dev/null 2>&1
cat > "$P/assets/scripts/render-seed-audit.sh" <<'STUB'
#!/usr/bin/env bash
printf 'STUB-RENDERER-RAN\n'
root="$(git rev-parse --show-toplevel)"
mkdir -p "$root/generated/seed-audit"
printf 'stub\n' > "$root/generated/seed-audit/STUB.md"
exit 0
STUB
chmod -x "$P/assets/scripts/render-seed-audit.sh"
printf 'moved by the test\n' >> "$P/agents/sample/prompt.template.md"
git -C "$P" add agents/sample/prompt.template.md >/dev/null 2>&1
( cd "$P" && bash assets/hooks/pre-commit >"$TMP/hook.out" 2>&1 ); hook_rc=$?
if grep -qF 'STUB-RENDERER-RAN' "$TMP/hook.out"; then
    ok "(HOOKNOEXEC) the hook INVOKES a non-executable renderer instead of skipping it"
else
    bad "(HOOKNOEXEC) the renderer was never run: $(head -4 "$TMP/hook.out")"
fi
if [ "$hook_rc" = "0" ]; then
    ok "(HOOKNOEXEC) ...and the hook completes, so the commit is not aborted"
else
    bad "(HOOKNOEXEC) the hook aborted the commit (rc=$hook_rc): $(tail -2 "$TMP/hook.out")"
fi
if grep -qF 'render FAILED' "$TMP/hook.out"; then
    bad "(HOOKNOEXEC) the invocation itself failed — the mode bit still breaks the loop"
else
    ok "(HOOKNOEXEC) ...with no render failure"
fi
if grep -qiF 'not executable' "$TMP/hook.out"; then
    ok "(HOOKNOEXEC) ...and the mode bit is noted, not silently tolerated forever"
else
    bad "(HOOKNOEXEC) the hook must note the mode bit: $(head -3 "$TMP/hook.out")"
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
printf '# Agent Seed Audit\n\nno digest line here\n' > "$P/generated/seed-audit/INDEX.md"
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

# THE REGRESSION THIS CHECK SHIPPED WITHOUT (tk-wchab, pre-open signoff P1).
# The renderer carries the synthetic city the prompts render against, so a
# renderer-only edit really does move the artifact — one line of its
# [agent_defaults] moves 13 agent prompts. While digest_inputs() hashed only the
# content directories, `render-seed-audit.sh --check` reported the tree stale
# and this check still reported it current: the gate was blind to the one file
# that defines what "current" means.
P="$TMP/stale-renderer"; make_pack "$P"
D="$("$P/assets/scripts/render-seed-audit.sh" --root "$P" --print-digest)"
write_index "$P" "$D" "$GCVER"
python3 - "$P/assets/scripts/render-seed-audit.sh" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = 'append_fragments = ["command-glossary", "operational-awareness"]'
assert old in s, "the embedded scenario no longer carries append_fragments — update this test"
open(p, "w", encoding="utf-8").write(s.replace(old, 'append_fragments = ["command-glossary"]', 1))
PY
run_check "$P"
if [ "$(rc_of)" = "2" ] && grep -F 'STALE' <<< "$(out_of)" >/dev/null; then
    ok "a renderer-only scenario edit is seen as STALE (the P1 gate hole)"
else
    bad "stale-renderer arm (rc=$(rc_of)): $(out_of | head -1)"
fi

# The hook and digest_inputs() are two hand-maintained lists of the same input
# set, which is precisely how one of them ends up missing a path. Assert the
# SHIPPED hook's INPUT_RE matches a representative path under every root
# digest_inputs() hashes, so the pair cannot drift silently.
hook_matches() {
    local path="$1" re
    re="$(sed -n "s/^INPUT_RE='\(.*\)'$/\1/p" "$ROOT/assets/hooks/pre-commit" | head -1)"
    [ -n "$re" ] || return 2
    grep -Eq "$re" <<< "$path"
}
drift=""
for probe in agents/x/prompt.template.md template-fragments/x.template.md \
             formulas/mol-x.toml packs/p/formulas/mol-y.toml pack.toml \
             assets/scripts/render-seed-audit.sh; do
    hook_matches "$probe" || drift="$drift $probe"
done
if [ -z "$drift" ]; then
    ok "the pre-commit INPUT_RE covers every root digest_inputs() hashes"
else
    bad "pre-commit INPUT_RE does not match:$drift"
fi
if hook_matches generated/seed-audit/INDEX.md; then
    bad "pre-commit INPUT_RE matches the generated tree — the hook would loop on its own output"
else
    ok "the pre-commit INPUT_RE does not match the generated tree"
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
# regenerating generated/seed-audit/, this line goes red. A hook-not-wired
# warning (rc=1) is tolerated here because core.hooksPath is per-checkout local config
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
