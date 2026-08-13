#!/usr/bin/env bash
# Hermetic test for doctor/check-work-context-hook/run.sh (tk-osf13).
#
# THE HOLE IT CLOSES: the check scores an artifact by grepping it, and the
# check's own header names every trap it looks for. So does the hook's. A
# comment-inclusive grep would score the *explanation* of a fix as the fix —
# the check would stay green after the code line was deleted, which is the one
# outcome that makes it worse than no check at all (it certifies delivery that
# has stopped happening, and every failure of this hook is silent by design).
# Case (11) deletes the code line and leaves the prose, and must still ERROR.
#
# Every case mutates a throwaway copy of the SHIPPED artifacts, so the fixtures
# cannot drift from what the pack actually ships. No live city, Dolt, or network.
#
# Covered:
#   (1)  shipped tree satisfies every assertion -> OK (exit 0)
#   (2)  hook script deleted -> ERROR
#   (3)  hook loses the GC_TEMPLATE gate -> ERROR
#   (4)  hook loses the tojson unescape -> ERROR (silent-forever trap)
#   (5)  hook caps with `cut -c` instead of `head -c` -> ERROR (per-line trap)
#   (6)  hook not executable -> ERROR (staging preserves mode)
#   (7)  hook loses the convoy resolution -> ERROR
#   (8)  settings.json loses the PostToolUse registration -> ERROR
#   (9)  settings.json loses the Bash matcher -> ERROR
#   (10) pack.toml loses the overlay_dir wiring -> ERROR (ships but never stages)
#   (11) hook keeps the prose but loses the emitter line -> ERROR (vacuous-green
#        guard: the header explains additionalContext in words)
#   (12) hermetic test deleted -> ERROR

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/../.."
CHECK="$HERE/run.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

# Build a pristine copy of the four artifacts the check reads.
mkpack() { # mkpack <dir>
    local d="$1"
    mkdir -p "$d/overlays/work-context/.claude/hooks" "$d/assets/scripts"
    cp "$REPO/overlays/work-context/.claude/hooks/work-context.sh" "$d/overlays/work-context/.claude/hooks/"
    cp "$REPO/overlays/work-context/.claude/settings.json" "$d/overlays/work-context/.claude/"
    cp "$REPO/pack.toml" "$d/pack.toml"
    cp "$REPO/assets/scripts/work-context-hook.test.sh" "$d/assets/scripts/"
    chmod +x "$d/overlays/work-context/.claude/hooks/work-context.sh"
}

# run_check <case-name> <expected-rc> <mutation-fn>
run_check() {
    local name="$1" want="$2" mutate="$3"
    local d="$SANDBOX/case-$PASS-$FAIL-$RANDOM"
    mkpack "$d"
    "$mutate" "$d"
    local out rc
    out="$(GC_PACK_DIR="$d" bash "$CHECK" 2>&1)"
    rc=$?
    if [ "$rc" -eq "$want" ]; then
        ok "$name (exit $rc)"
    else
        bad "$name" "want exit $want, got $rc: $(printf '%s' "$out" | head -3 | tr '\n' ' ')"
    fi
    rm -rf "$d"
}

HOOK_REL="overlays/work-context/.claude/hooks/work-context.sh"

none()          { :; }
rm_hook()       { rm -f "$1/$HOOK_REL"; }
drop_template() { sed -i 's/GC_TEMPLATE/GC_AGENTNAME/g' "$1/$HOOK_REL"; }
drop_unescape() { sed -i "s@| sed 's/\\\\\\\\\"/\"/g')\"@)\"@" "$1/$HOOK_REL"; }
use_cut()       { sed -i 's@| head -c "$limit")@| cut -c 1-"$limit")@' "$1/$HOOK_REL"; }
unexec()        { chmod -x "$1/$HOOK_REL"; }
drop_convoy()   { sed -i 's/gc convoy status/gc convoy stat_us/g' "$1/$HOOK_REL"; }
drop_post()     { sed -i 's/"PostToolUse"/"PreToolUse"/' "$1/overlays/work-context/.claude/settings.json"; }
drop_matcher()  { sed -i 's/"matcher": "Bash"/"matcher": "Edit"/' "$1/overlays/work-context/.claude/settings.json"; }
drop_wiring()   { sed -i 's@overlay_dir = "overlays/work-context"@# removed@' "$1/pack.toml"; }
rm_test()       { rm -f "$1/assets/scripts/work-context-hook.test.sh"; }
# Prose survives, code line does not: the header sentence "it exits 0 and prints
# nothing" plus the invariant block still mention additionalContext by name.
prose_only()    { sed -i '/^  | jq -Rs/d' "$1/$HOOK_REL"; }

echo "── shipped tree ──"
run_check "pristine shipped artifacts pass"        0 none

echo "── hook script ──"
run_check "hook deleted"                           2 rm_hook
run_check "GC_TEMPLATE gate removed"               2 drop_template
run_check "tojson unescape removed"                2 drop_unescape
run_check "capped with cut -c (per-line)"          2 use_cut
run_check "hook not executable"                    2 unexec
run_check "convoy resolution removed"              2 drop_convoy
run_check "emitter deleted, prose kept"            2 prose_only

echo "── wiring ──"
run_check "PostToolUse registration removed"       2 drop_post
run_check "Bash matcher removed"                   2 drop_matcher
run_check "pack.toml overlay_dir removed"          2 drop_wiring
run_check "hermetic test deleted"                  2 rm_test

echo
echo "check-work-context-hook: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
