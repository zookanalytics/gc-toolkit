#!/usr/bin/env bash
# Hermetic test for doctor/check-learned-rule-anchors/run.sh.
#
# Every case builds a throwaway pack dir in mktemp — a learned-conventions
# fragment, a pack.toml carrying the polecat patch, an
# agents/polecat-codex/agent.toml — and drives the SHIPPED run.sh at it via
# GC_PACK_DIR. No live city, Dolt, or network.
#
# Covered:
#   (1)  clean empty seed (heading + managed-by comment, no bullets) -> OK.
#        This is the phase-1 state the check must not fault.
#   (2)  well-formed anchor + bullet pair, recent adopted date -> OK
#   (3)  bullet with no anchor above it -> ERROR (orphan rule)
#   (4)  anchor with no bullet after it -> ERROR (dead provenance)
#   (5)  16 anchored bullets -> ERROR (cap is 15, mirroring the distiller's
#        fragment_bullet_cap default)
#   (6)  pack.toml polecat patch has the fragment, polecat-codex agent.toml
#        does not -> ERROR (the hand-sync hazard, pack-side applied)
#   (7)  the reverse asymmetry -> ERROR (agent-side applied)
#   (8)  stale adopted date (>180d) on an otherwise clean fragment -> WARNING
#   (9)  fragment exists but is wired nowhere -> ERROR
#   (10) wiring satisfied by a {{ template "…" }} reference alone -> OK
#        (native inclusion is a legitimate third wiring site)
#   (11) malformed anchor above a bullet -> ERROR, reported ONCE — the bullet
#        is not additionally faulted as unanchored, so one defect is one line
#   (12) no learned-conventions fragments at all -> OK (pre-seed state)
#   (13) stale date alongside a real violation -> ERROR (2 beats 1; the WARN
#        must not mask the defect, nor downgrade it)
#   (14) anchor followed by prose, bullet after the prose -> BOTH the orphan
#        anchor and the unanchored bullet are reported (adjacency is strict
#        in each direction)
#
# Case (6)/(7) are the point of the check: agent.toml's own comment documents
# that the two fragment lists are synced by hand with no propagation, so a
# half-applied change runs one polecat pool without the adopted rules and
# nothing else reports it.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/run.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

TODAY="$(date +%F)"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { if grep -q -- "$1" "$2"; then ok "$3"; else bad "$3 (missing '$1' in: $(cat "$2"))"; fi; }
hasnt() { if grep -q -- "$1" "$2"; then bad "$3 (unexpected '$1' in: $(cat "$2"))"; else ok "$3"; fi; }

# pack <name> — throwaway pack dir with BOTH polecat wiring sites carrying
# learned-conventions-polecat (the symmetric, healthy shape). Cases mutate
# from there. Echoes the dir.
pack() {
    local d="$TMP/$1"
    mkdir -p "$d/template-fragments" "$d/agents/polecat-codex"
    cat > "$d/pack.toml" <<'EOF'
[pack]
name = "fixture"

[[patches.agent]]
name = "polecat"
inject_fragments_append = ["polecat-convoys", "learned-conventions-polecat"]

[[patches.agent]]
name = "refinery"
inject_fragments_append = ["layered-startup-discovery-refinery"]
EOF
    cat > "$d/agents/polecat-codex/agent.toml" <<'EOF'
scope = "rig"
provider = "codex"
inject_fragments = ["polecat-convoys", "learned-conventions-polecat"]
EOF
    echo "$d"
}

# seed <dir> — the phase-1 empty polecat seed per implementation-design.md §5.
seed() {
    cat > "$1/template-fragments/learned-conventions-polecat.template.md" <<'EOF'
{{ define "learned-conventions-polecat" }}
## Learned conventions

<!-- managed by the learning distiller; every bullet carries its anchor. cap: 15 -->
{{ end }}
EOF
}

# frag <dir> <role> — write a fragment body (stdin) wrapped in its define block.
frag() {
    {
        printf '{{ define "learned-conventions-%s" }}\n## Learned conventions\n\n' "$2"
        printf '<!-- managed by the learning distiller; every bullet carries its anchor. cap: 15 -->\n'
        cat
        printf '{{ end }}\n'
    } > "$1/template-fragments/learned-conventions-$2.template.md"
}

run_check() { # $1=pack dir -> echoes exit code, output in <dir>/out
    GC_PACK_DIR="$1" bash "$SCRIPT" > "$1/out" 2>&1
    echo $?
}

# --- (1) clean empty seed ----------------------------------------------------
D=$(pack empty-seed)
seed "$D"
eq "$(run_check "$D")" "0" "(1) empty phase-1 seed -> exit 0"
has "OK:" "$D/out" "(1) reports OK"

# --- (2) well-formed anchor + bullet ------------------------------------------
D=$(pack well-formed)
frag "$D" polecat <<EOF
<!-- rule:pat-stale-ref src:PR#412,tk-abc12 adopted:$TODAY -->
- Never describe changed code by contrast with what it used to be.
EOF
eq "$(run_check "$D")" "0" "(2) anchored bullet with recent date -> exit 0"
has "every bullet anchored" "$D/out" "(2) summary claims the pairing it verified"

# --- (3) bullet missing its anchor --------------------------------------------
D=$(pack no-anchor)
frag "$D" polecat <<EOF
- An orphan rule nobody owns.
EOF
eq "$(run_check "$D")" "2" "(3) bullet without anchor -> exit 2"
has "not immediately preceded by a well-formed anchor" "$D/out" "(3) names the defect"
has "learned-conventions-polecat.template.md" "$D/out" "(3) names the file"

# --- (4) orphan anchor ---------------------------------------------------------
D=$(pack orphan-anchor)
frag "$D" polecat <<EOF
<!-- rule:pat-ghost src:PR#1 adopted:$TODAY -->
EOF
eq "$(run_check "$D")" "2" "(4) anchor without bullet -> exit 2"
has "no bullet following it" "$D/out" "(4) names the defect"

# --- (5) over the bullet cap ----------------------------------------------------
D=$(pack over-cap)
{
    for i in $(seq 1 16); do
        printf -- '<!-- rule:pat-rule-%d src:PR#%d adopted:%s -->\n- Rule number %d.\n' "$i" "$i" "$TODAY" "$i"
    done
} | frag "$D" polecat
eq "$(run_check "$D")" "2" "(5) 16 bullets -> exit 2"
has "exceed the 15-bullet cap" "$D/out" "(5) names the cap"
has "fragment_bullet_cap" "$D/out" "(5) ties the cap to the distiller default it mirrors"

# --- (6) asymmetry: pack.toml yes, agent.toml no --------------------------------
D=$(pack asym-pack-only)
seed "$D"
sed -i 's/, "learned-conventions-polecat"//' "$D/agents/polecat-codex/agent.toml"
eq "$(run_check "$D")" "2" "(6) pack.toml-only wiring -> exit 2"
has "agents/polecat-codex/agent.toml inject_fragments does not" "$D/out" \
    "(6) names the missing side"
has "hand-sync hazard" "$D/out" "(6) names the hazard"

# --- (7) asymmetry: agent.toml yes, pack.toml no --------------------------------
D=$(pack asym-agent-only)
seed "$D"
sed -i 's/, "learned-conventions-polecat"//' "$D/pack.toml"
eq "$(run_check "$D")" "2" "(7) agent.toml-only wiring -> exit 2"
has "pack.toml's polecat patch inject_fragments_append does not" "$D/out" \
    "(7) names the missing side"

# --- (8) stale adopted date ------------------------------------------------------
D=$(pack stale)
frag "$D" polecat <<EOF
<!-- rule:pat-old-timer src:PR#7 adopted:2020-01-01 -->
- A rule adopted long ago.
EOF
eq "$(run_check "$D")" "1" "(8) adopted >180d ago -> exit 1 (WARN)"
has "adopted 2020-01-01 is older than 180 days" "$D/out" "(8) names the anchor and date"
has "challenge pass" "$D/out" "(8) explains what the age signal feeds"

# --- (9) fragment wired nowhere ---------------------------------------------------
D=$(pack unwired)
seed "$D"
frag "$D" mechanik <<EOF
<!-- rule:pat-lonely src:PR#9 adopted:$TODAY -->
- A rule that binds nobody.
EOF
eq "$(run_check "$D")" "2" "(9) unwired fragment -> exit 2"
has "learned-conventions-mechanik.template.md: wired nowhere" "$D/out" \
    "(9) names the unwired fragment"
has "silently binds nobody" "$D/out" "(9) states the consequence"

# --- (10) wiring via a template reference ------------------------------------------
D=$(pack template-wired)
seed "$D"
frag "$D" review <<EOF
<!-- rule:pat-review src:PR#11 adopted:$TODAY -->
- A rule enforced at review time.
EOF
mkdir -p "$D/agents/reviewer"
cat > "$D/agents/reviewer/prompt.template.md" <<'EOF'
# Reviewer

{{ template "learned-conventions-review" . }}
EOF
eq "$(run_check "$D")" "0" "(10) {{ template }} reference alone satisfies wiring -> exit 0"

# --- (11) malformed anchor above a bullet -------------------------------------------
D=$(pack malformed)
frag "$D" polecat <<'EOF'
<!-- rule:pat-broken src:PR#3 -->
- A rule whose anchor lost its adopted date.
EOF
eq "$(run_check "$D")" "2" "(11) malformed anchor -> exit 2"
has "malformed anchor comment" "$D/out" "(11) names the defect"
eq "$(grep -c 'learned-conventions-polecat' "$D/out")" "1" \
    "(11) one defect, one finding — the bullet is not double-reported as unanchored"

# --- (12) no fragments at all --------------------------------------------------------
D=$(pack pre-seed)
eq "$(run_check "$D")" "0" "(12) no learned-conventions fragments -> exit 0"
has "pre-seed" "$D/out" "(12) says why it is OK"

# --- (13) stale date alongside a real violation ---------------------------------------
D=$(pack stale-plus-error)
frag "$D" polecat <<'EOF'
<!-- rule:pat-old src:PR#5 adopted:2020-01-01 -->
- An old but anchored rule.
- An orphan bullet.
EOF
eq "$(run_check "$D")" "2" "(13) violation + stale date -> exit 2, the WARN does not mask it"
has "not immediately preceded" "$D/out" "(13) the error is reported"

# --- (14) prose between anchor and bullet ----------------------------------------------
D=$(pack prose-between)
frag "$D" polecat <<EOF
<!-- rule:pat-gap src:PR#6 adopted:$TODAY -->
Some prose that breaks the adjacency.
- A bullet stranded from its anchor.
EOF
eq "$(run_check "$D")" "2" "(14) prose between anchor and bullet -> exit 2"
has "no bullet following it" "$D/out" "(14) the anchor is orphaned"
has "not immediately preceded" "$D/out" "(14) and the bullet is unanchored — adjacency is strict both ways"

# --- (15) the seed's placeholder exemplar is documentation, not an anchor ------
# The shipped seed documents the anchor format with placeholder tokens
# (<!-- rule:<pattern-bead> src:<refs> adopted:<date> -->, per
# implementation-design.md §5). A real rule id is [a-z0-9-]+, so the `rule:<`
# prefix is unambiguous and must not read as a malformed anchor.
D=$(pack exemplar-seed)
frag "$D" polecat <<'EOF'
<!-- rule:<pattern-bead> src:<refs> adopted:<date> -->
EOF
eq "$(run_check "$D")" "0" "(15) placeholder exemplar alone -> exit 0 (the shipped seed shape)"

# --- (16) ...but a bullet under the exemplar is still unanchored ----------------
# A promotion PR that copies the exemplar verbatim without filling it in has
# produced a rule with no provenance; the exemption must not cover that.
D=$(pack exemplar-bullet)
frag "$D" polecat <<'EOF'
<!-- rule:<pattern-bead> src:<refs> adopted:<date> -->
- A rule left under the unfilled exemplar.
EOF
eq "$(run_check "$D")" "2" "(16) bullet under an unfilled exemplar -> exit 2"
has "not immediately preceded by a well-formed anchor" "$D/out" \
    "(16) the exemplar does not count as this bullet's anchor"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
