#!/usr/bin/env bash
# Hermetic test for doctor/check-operator-next-step-wiring/run.sh (tk-l1pj6).
#
# THE HOLE IT CLOSES: this check reads four different wiring surfaces and one
# of them (inheritance, surface (d)) follows a path out of one file into
# another. A resolver that is too permissive would report the refinery as wired
# because SOME file somewhere mentions the fragment — and a check that cannot
# fail is worse than no check, because it certifies a distribution that has
# stopped happening, and every failure of this distribution is silent by design
# (the agent primes fine and spends the operator's attention).
#
# Two cases carry most of that weight:
#   (4)  a pack-QUALIFIED prompt_template must NOT satisfy inheritance. Those
#        resolve to upstream's base prompts, which carry no gc-toolkit
#        fragment; accepting them would mark polecat-codex-shaped agents wired
#        by nothing.
#   (11) a fragment named inside a COMMENT in the array must not count. The
#        pack.toml patch comments discuss this fragment by name at length, so a
#        comment-inclusive scrape would score the explanation as the wiring.
#
# Surfaces (b) and (d) lost their shipped users when the thread agents were
# retired (tk-5savt), so cases (4), (14) and (15) exercise them by REWIRING an
# agent that does ship — converse, which is classified operator-facing and
# whose wiring the check must therefore resolve. (4) and (14) are a matched
# pair: the same relocation is asserted to be found when it is legitimate and
# NOT found when it points out of the pack, which is what keeps the (d)
# resolver honest now that nothing ships on it.
#
# Every case mutates a throwaway copy of the SHIPPED artifacts, so the fixtures
# cannot drift from what the pack actually ships. No live city, Dolt, or network.
#
# Covered:
#   (1)  shipped tree satisfies every assertion -> OK (exit 0)
#   (2)  refinery loses the pack.toml wiring -> ERROR (the tk-l1pj6 regression)
#   (3)  converse loses its inline template call -> ERROR
#   (4)  inheritance via a pack-qualified prompt_template -> ERROR (false-green)
#   (5)  mechanik loses the inline call -> ERROR
#   (7)  a new, unclassified agent appears -> ERROR (the roster-drift guard)
#   (8)  a new `_`-prefixed (disabled) agent appears -> still OK
#   (9)  a dir under agents/ with no agent.toml -> still OK
#   (10) the fragment file is deleted -> ERROR
#   (11) real entry replaced by a commented-out one -> ERROR (vacuous-green)
#   (12) a classified agent no longer exists -> WARNING (stale roster)
#   (13) a non-operator-facing agent gains the fragment -> WARNING (stray)
#   (14) inheritance via a pack-root-relative prompt_template -> OK (surface d)
#   (15) wiring relocated to append_fragments -> OK (surface b)
# (6) was the retired thread agent's append_fragments case; (14) and (15)
# replace the coverage it carried.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/../.."
CHECK="$HERE/run.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

# A pristine copy of every artifact the check reads: pack.toml, the fragment
# file, and each native agent's agent.toml + prompt.template.md.
mkpack() { # mkpack <dir>
    local d="$1"
    mkdir -p "$d/template-fragments" "$d/agents"
    cp "$REPO/pack.toml" "$d/pack.toml"
    cp "$REPO/template-fragments/operator-next-step-trailing.template.md" "$d/template-fragments/"
    local a name
    for a in "$REPO"/agents/*/; do
        [ -f "$a/agent.toml" ] || continue
        name="$(basename "$a")"
        mkdir -p "$d/agents/$name"
        cp "$a/agent.toml" "$d/agents/$name/"
        [ -f "$a/prompt.template.md" ] && cp "$a/prompt.template.md" "$d/agents/$name/"
    done
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
        bad "$name" "want exit $want, got $rc: $(printf '%s' "$out" | head -4 | tr '\n' ' ')"
    fi
    rm -rf "$d"
}

FRAG="operator-next-step-trailing"

none() { :; }

# Delete the fragment entry from the refinery patch only. The mayor patch names
# it too, so the match is anchored on the line that follows the refinery's
# layered-startup-discovery-refinery entry.
drop_refinery() {
    awk -v frag="\"$FRAG\"," '
        /layered-startup-discovery-refinery/ { seen = 1 }
        seen && index($0, frag) > 0 { seen = 0; next }
        { print }
    ' "$1/pack.toml" > "$1/pack.toml.new" && mv "$1/pack.toml.new" "$1/pack.toml"
}

drop_converse_inline() {
    sed -i "/{{ template \"$FRAG\" . }}/d" "$1/agents/converse/prompt.template.md"
}

drop_mechanik_inline() {
    sed -i "/{{ template \"$FRAG\" . }}/d" "$1/agents/mechanik/prompt.template.md"
}

# Move converse off its inline call and onto inheritance, expressed as a
# pack-QUALIFIED reference. Strip the `<pack>//` prefix and the path is a real
# file in the sandbox that carries the fragment, so a resolver that normalizes
# the prefix away instead of refusing it would report converse wired by a
# prompt this pack does not own.
qualify_converse_prompt() {
    sed -i "/{{ template \"$FRAG\" . }}/d" "$1/agents/converse/prompt.template.md"
    printf '\nprompt_template = "gastown//agents/mechanik/prompt.template.md"\n' \
        >> "$1/agents/converse/agent.toml"
}

# The same relocation with a pack-root-relative reference — the legitimate
# form of surface (d). Paired with the case above: together they assert that
# the resolver follows in-pack inheritance and refuses the qualified form,
# rather than being blind to both.
inherit_converse_prompt() {
    sed -i "/{{ template \"$FRAG\" . }}/d" "$1/agents/converse/prompt.template.md"
    printf '\nprompt_template = "agents/mechanik/prompt.template.md"\n' \
        >> "$1/agents/converse/agent.toml"
}

# Surface (b) on an operator-facing agent: converse gives up its inline call
# and declares the fragment in append_fragments instead. Stop reading that key
# and this goes red.
relocate_converse_to_append_fragments() {
    sed -i "/{{ template \"$FRAG\" . }}/d" "$1/agents/converse/prompt.template.md"
    printf '\nappend_fragments = ["%s"]\n' "$FRAG" >> "$1/agents/converse/agent.toml"
}

add_unclassified_agent() {
    mkdir -p "$1/agents/quartermaster"
    printf 'scope = "city"\n' > "$1/agents/quartermaster/agent.toml"
}

add_disabled_agent() {
    mkdir -p "$1/agents/_quartermaster"
    printf 'scope = "city"\n' > "$1/agents/_quartermaster/agent.toml"
}

add_bare_dir() {
    mkdir -p "$1/agents/notes"
    printf 'just a directory\n' > "$1/agents/notes/README.md"
}

rm_fragment() { rm -f "$1/template-fragments/$FRAG.template.md"; }

# The wiring becomes a comment that still quotes the fragment name, inside the
# array. Only comment-stripping keeps this red.
comment_out_refinery() {
    awk -v frag="\"$FRAG\"," '
        /layered-startup-discovery-refinery/ { seen = 1 }
        seen && index($0, frag) > 0 { seen = 0; print "    # " frag; next }
        { print }
    ' "$1/pack.toml" > "$1/pack.toml.new" && mv "$1/pack.toml.new" "$1/pack.toml"
}

# converse is classified; remove it from the pack entirely.
rm_converse() { rm -rf "$1/agents/converse"; }

# proactive is classified NOT operator-facing; give it the fragment anyway.
stray_on_proactive() {
    printf '\nappend_fragments = ["%s"]\n' "$FRAG" >> "$1/agents/proactive/agent.toml"
}

echo "── shipped tree ──"
run_check "pristine shipped artifacts pass"             0 none

echo "── wiring surfaces ──"
run_check "refinery loses pack.toml wiring"             2 drop_refinery
run_check "converse loses inline template call"         2 drop_converse_inline
run_check "mechanik loses inline call"                  2 drop_mechanik_inline
run_check "wiring relocated to append_fragments"        0 relocate_converse_to_append_fragments
run_check "pack-root-relative prompt_template inherited" 0 inherit_converse_prompt
run_check "pack-qualified prompt_template not inherited" 2 qualify_converse_prompt
run_check "commented-out entry does not count"          2 comment_out_refinery

echo "── roster ──"
run_check "new unclassified agent"                      2 add_unclassified_agent
run_check "new _-prefixed (disabled) agent ignored"     0 add_disabled_agent
run_check "agents/ dir without agent.toml ignored"      0 add_bare_dir
run_check "classified agent removed from pack"          1 rm_converse
run_check "fragment on a non-operator-facing agent"     1 stray_on_proactive

echo "── fragment ──"
run_check "fragment file deleted"                       2 rm_fragment

echo
echo "check-operator-next-step-wiring: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
