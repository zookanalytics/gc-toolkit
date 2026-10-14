#!/usr/bin/env bash
# doctor/check-seed-audit-current — generated/seed-audit/ is present, and the
# hook that regenerates it is wired. The audit is the rendered standing prompt
# of every agent and the compiled recipe of every formula, committed for
# review. Whether it is current is a question only a render answers, and this
# check renders nothing: `assets/scripts/render-seed-audit.sh --check`
# re-renders a checkout, and merge.sh holds a merge that would land a render the
# merge itself made stale (`--check-merge`). This check reads what that
# machinery depends on: an artifact to hold merges to, and the pre-commit hook
# that keeps a branch current before it reaches the merge.
# An ABSENT audit is a WARNING — a fresh clone before the first render is
# expected, and it renders on first install (--install-hook). A renderer that
# is not executable, and an unwired hook, are warnings too.
# Read-only. Exit 0=OK 1=Warning; nothing here is an error. stdout: message,
# "  - detail" lines.

set -u

dir="${GC_PACK_DIR:-.}"
audit="$dir/generated/seed-audit"
index="$audit/INDEX.md"
script="$dir/assets/scripts/render-seed-audit.sh"

warnings=()
detail() { local v; for v in "$@"; do printf '  - %s\n' "$v"; done; }

# ABSENT and PRESENT-BUT-NOT-EXECUTABLE are different facts: a renderer that
# ships is one this pack expects to keep the audit current, whatever its mode
# bit says.
if [ ! -e "$script" ]; then
    echo "OK: no render-seed-audit.sh in this pack — nothing to keep current"
    exit 0
fi
[ -x "$script" ] || warnings+=("assets/scripts/render-seed-audit.sh is NOT executable — merge.sh and the pre-commit hook run it through bash, so the upkeep still works, but the documented operator command and --install-hook invoke it directly and will fail; chmod +x it")

if [ ! -f "$index" ]; then
    echo "seed audit ABSENT — generated/seed-audit/INDEX.md does not exist (warning, not error)"
    detail "A fresh clone ships without the rendered audit and regenerates it on first install; until then nothing shows what any agent receives, and merge.sh has no artifact to hold a merge to."
    detail "Render it: assets/scripts/render-seed-audit.sh && git add generated/seed-audit (wire upkeep with --install-hook)."
    detail ${warnings[@]+"${warnings[@]}"}
    exit 1
fi

# The pre-commit hook is what keeps a branch's artifact current before the
# merge gate sees it.
if command -v git >/dev/null 2>&1 && git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
    hookspath=$(git -C "$dir" config --get core.hooksPath 2>/dev/null)
    if [ "$hookspath" != "assets/hooks" ]; then
        shown="${hookspath:+\"$hookspath\"}"
        warnings+=("core.hooksPath is ${shown:-unset}, not assets/hooks — nothing regenerates the audit on commit, so a branch that moves a prompt input reaches the merge gate stale and is held there; wire it: assets/scripts/render-seed-audit.sh --install-hook (deliberate on rigs that disable hooks — there, render by hand before pushing: assets/scripts/render-seed-audit.sh)")
    fi
fi

n_agents=$(find "$audit/agents" -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')
n_formulas=$(find "$audit/formulas" -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')

if [ "${#warnings[@]}" -ne 0 ]; then
    echo "seed audit present ($n_agents agents, $n_formulas formulas) but its upkeep is not fully wired"
    detail "${warnings[@]}"
    exit 1
fi
echo "OK: seed audit present — $n_agents agent prompt(s), $n_formulas formula recipe(s), hook wired"
exit 0
