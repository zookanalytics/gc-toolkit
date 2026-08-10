#!/usr/bin/env bash
# Pack doctor check: the learned-rules prompt surface stays traceable, capped,
# and wired on both sides of its documented hand-sync hazard.
#
# The learned-conventions fragments
# (template-fragments/learned-conventions-<role>.template.md) are the learning
# distiller's write target: every rule it promotes lands as one bullet under
# one anchor comment naming the pattern bead that owns it, the evidence it
# cites, and the day it was adopted
# (specs/2026-08-learning-system/implementation-design.md §5). Three failure
# modes this check prevents:
#
#   ORPHAN BULLET — a bullet with no well-formed anchor immediately above it
#   is a rule no pattern bead owns: the challenge pass cannot age it, a
#   demotion PR cannot find it, and it binds every future agent with no
#   provenance. The same defect in reverse — an anchor with no bullet
#   immediately after it — is dead provenance that reads as a live rule in a
#   diff review.
#
#   SILENT CAP OVERFLOW — the distiller's file-and-dispatch step holds each
#   fragment to fragment_bullet_cap bullets and proposes a demotion when the
#   fragment is full. A hand edit or distiller bug that pushes past the cap
#   grows the always-injected prompt surface unboundedly and nothing else
#   notices.
#
#   HALF-APPLIED WIRING — learned-conventions-polecat is injected at TWO sites
#   kept in sync by hand (the hazard agents/polecat-codex/agent.toml's own
#   comment documents: "no automatic propagation"): pack.toml's polecat
#   patch inject_fragments_append (base gastown polecat pool) and
#   agents/polecat-codex/agent.toml inject_fragments (codex pool). A
#   fragment-list change applied to one site leaves the other pool running
#   without the adopted rules — silently, because an unlisted fragment is
#   simply absent, not an error. The general form of the same hazard: a
#   learned-conventions fragment that exists but is wired NOWHERE (no
#   inject_fragments/append entry, no {{ template "…" }} reference) binds
#   nobody while looking adopted in the repo.
#
# WARN (exit 1) when any anchor's adopted: date is older than 180 days — the
# age signal the challenge pass reads (retire the rule, or harden it into a
# lint under tools/lint-learned.d/). A signal, not a defect. An empty seeded
# fragment (heading + managed-by comment, no bullets, no anchors) is the
# healthy phase-1 state and passes.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

dir="${GC_PACK_DIR:-.}"
pack_toml="$dir/pack.toml"
polecat_codex_toml="$dir/agents/polecat-codex/agent.toml"

errors=()
stale=()

# Mirrors the distiller's fragment_bullet_cap default
# (specs/2026-08-learning-system/implementation-design.md §3 vars, §5 cap
# comment). Hardcoded on purpose, and the value lives in FIVE places that
# move together — change one, change them all:
#   - formulas/mol-feedback-distiller.toml [vars.fragment_bullet_cap] default
#   - this hardcode
#   - doctor/check-learned-rule-anchors/doctor.toml description ("15-bullet cap")
#   - docs/feedback-learning.md ("at most 15 bullets")
#   - the seed fragment's managed-by comment
#     (template-fragments/learned-conventions-polecat.template.md, "cap: 15")
bullet_cap=15

# The anchor contract from implementation-design.md §5:
#   <!-- rule:<pattern-bead> src:<PR/bead refs> adopted:<YYYY-MM-DD> -->
# Anchors and bullets are distiller-written, flat, column-0 lines; the check
# holds them to exactly that shape.
anchor_re='^<!-- rule:[a-z0-9-]+ src:.+ adopted:([0-9]{4}-[0-9]{2}-[0-9]{2}) -->$'

# ISO dates compare correctly as strings, so the staleness test needs no
# per-anchor date parsing.
cutoff="$(date -d "180 days ago" +%F)"

shopt -s nullglob
fragments=("$dir"/template-fragments/learned-conventions-*.template.md)
shopt -u nullglob

if [ ${#fragments[@]} -eq 0 ]; then
    echo "OK: no learned-conventions fragments exist yet — nothing to check (pre-seed state)"
    exit 0
fi

# --- per-fragment scan: anchor/bullet pairing, well-formedness, cap ---------
for frag in "${fragments[@]}"; do
    rel="template-fragments/$(basename "$frag")"
    in_block=0
    pending_anchor=""    # line number of a well-formed anchor awaiting its bullet
    pending_malformed="" # line number of a malformed rule comment (already reported)
    bullets=0
    lineno=0
    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno + 1))
        if [[ $line == *"{{ define "* || $line == *"{{define "* ]]; then
            in_block=1
            pending_anchor=""
            pending_malformed=""
            continue
        fi
        if [ "$in_block" -eq 1 ] && [[ $line == *"{{ end }}"* || $line == *"{{end}}"* ]]; then
            if [ -n "$pending_anchor" ]; then
                errors+=("$rel:$pending_anchor: anchor comment with no bullet following it — dead provenance that reads as a live rule")
            fi
            in_block=0
            pending_anchor=""
            pending_malformed=""
            continue
        fi
        [ "$in_block" -eq 1 ] || continue

        if [[ $line =~ $anchor_re ]]; then
            adopted="${BASH_REMATCH[1]}"
            if [ -n "$pending_anchor" ]; then
                errors+=("$rel:$pending_anchor: anchor comment with no bullet following it (another anchor starts before its rule)")
            fi
            pending_anchor="$lineno"
            pending_malformed=""
            if [[ "$adopted" < "$cutoff" ]]; then
                stale+=("$rel:$lineno: adopted $adopted is older than 180 days")
            fi
            continue
        fi
        if [[ $line == "<!-- rule:"* && $line != "<!-- rule:<"* ]]; then
            # Intends to be an anchor, is not well-formed. Two cases, kept
            # distinct. Exemplar case: `rule:<` is exempt from this branch —
            # the seeded fragment documents the anchor format with a
            # placeholder exemplar (<!-- rule:<pattern-bead> src:<refs>
            # adopted:<date> -->, per implementation-design.md §5), a real
            # rule id is [a-z0-9-]+ so the angle bracket is unambiguous, and
            # the exemplar is plain documentation — a bullet placed under it
            # is still faulted as unanchored below. Malformed-anchor case:
            # the defect is reported once here, and a bullet right after it
            # is NOT additionally faulted as unanchored, so one defect reads
            # as one finding.
            errors+=("$rel:$lineno: malformed anchor comment (expected <!-- rule:<id> src:<refs> adopted:YYYY-MM-DD -->)")
            if [ -n "$pending_anchor" ]; then
                errors+=("$rel:$pending_anchor: anchor comment with no bullet following it")
            fi
            pending_anchor=""
            pending_malformed="$lineno"
            continue
        fi
        if [[ $line == "- "* ]]; then
            bullets=$((bullets + 1))
            if [ -n "$pending_anchor" ]; then
                pending_anchor="" # anchored rule — the healthy pair
            elif [ -n "$pending_malformed" ]; then
                pending_malformed="" # its anchor was already reported as malformed
            else
                errors+=("$rel:$lineno: bullet not immediately preceded by a well-formed anchor — an orphan rule no pattern bead owns")
            fi
            continue
        fi
        # Any other line (prose, blank, managed-by comment) breaks adjacency.
        if [ -n "$pending_anchor" ]; then
            errors+=("$rel:$pending_anchor: anchor comment with no bullet following it — dead provenance that reads as a live rule")
        fi
        pending_anchor=""
        pending_malformed=""
    done < "$frag"
    if [ -n "$pending_anchor" ]; then
        # File ended inside a define block with an anchor still pending.
        errors+=("$rel:$pending_anchor: anchor comment with no bullet following it — dead provenance that reads as a live rule")
    fi

    if [ "$bullets" -gt "$bullet_cap" ]; then
        errors+=("$rel: $bullets bullets exceed the $bullet_cap-bullet cap (mirrors the distiller's fragment_bullet_cap default — a full fragment demands a demotion, not silent growth)")
    fi
done

# --- every existing fragment is wired somewhere ------------------------------
# A learned-conventions fragment binds an agent only when something injects it:
# pack.toml inject_fragments_append, an agent.toml
# inject_fragments/append_fragments list, or a native {{ template "…" }}
# reference inside a prompt template. The quoted-name grep deliberately covers
# multi-line TOML arrays.
for frag in "${fragments[@]}"; do
    base="$(basename "$frag" .template.md)" # learned-conventions-<role>
    rel="template-fragments/$(basename "$frag")"
    wired=0
    if [ -f "$pack_toml" ] && grep -qF "\"$base\"" "$pack_toml"; then
        wired=1
    fi
    if [ "$wired" -eq 0 ] && grep -rqF --include=agent.toml "\"$base\"" "$dir" 2>/dev/null; then
        wired=1
    fi
    # `template "<name>"` matches only invocation sites — the fragment's own
    # {{ define "<name>" }} line says define, not template.
    if [ "$wired" -eq 0 ] && grep -rqF --include='*.template.md' "template \"$base\"" "$dir" 2>/dev/null; then
        wired=1
    fi
    if [ "$wired" -eq 0 ]; then
        errors+=("$rel: wired nowhere — not in pack.toml, no agent.toml inject_fragments/append_fragments entry, no {{ template \"$base\" }} reference; an unwired fragment silently binds nobody")
    fi
done

# --- the polecat dual-wiring symmetry ----------------------------------------
# learned-conventions-polecat lives at two hand-synced sites. Asymmetry is the
# half-applied change this check exists to catch, so it is asserted whether or
# not the fragment file exists yet. The pack.toml side is scoped to the
# [[patches.agent]] block whose name is exactly "polecat" (the closing quote in
# the match is what keeps "polecat-codex" from satisfying it).
in_pack=0
if [ -f "$pack_toml" ]; then
    if awk '
        function flush() {
            if (match(blk, /name = "polecat"\n/) && index(blk, "\"learned-conventions-polecat\"")) found = 1
        }
        /^\[\[patches\.agent\]\]/ { flush(); blk = ""; inb = 1; next }
        /^\[/                     { flush(); blk = ""; inb = 0; next }
        inb { blk = blk $0 "\n" }
        END { flush(); exit(found ? 0 : 1) }
    ' "$pack_toml"; then
        in_pack=1
    fi
fi
in_agent=0
if [ -f "$polecat_codex_toml" ] && grep -qF '"learned-conventions-polecat"' "$polecat_codex_toml"; then
    in_agent=1
fi
if [ "$in_pack" -ne "$in_agent" ]; then
    if [ "$in_pack" -eq 1 ]; then
        errors+=("pack.toml polecat patch injects learned-conventions-polecat but agents/polecat-codex/agent.toml inject_fragments does not — the hand-sync hazard half-applied: codex polecats run without the adopted rules")
    else
        errors+=("agents/polecat-codex/agent.toml injects learned-conventions-polecat but pack.toml's polecat patch inject_fragments_append does not — the hand-sync hazard half-applied: base-pool polecats run without the adopted rules")
    fi
fi

# --- verdict ------------------------------------------------------------------
if [ ${#errors[@]} -gt 0 ]; then
    echo "${#errors[@]} learned-rule anchor violation(s) — see specs/2026-08-learning-system/implementation-design.md §5-§6 for the contract"
    printf '%s\n' "${errors[@]}"
    exit 2
fi

if [ ${#stale[@]} -gt 0 ]; then
    echo "${#stale[@]} learned rule(s) adopted more than 180 days ago — the age signal for the distiller's challenge pass (retire the rule or harden it into a lint); a signal, not a defect"
    printf '%s\n' "${stale[@]}"
    exit 1
fi

echo "OK: ${#fragments[@]} learned-conventions fragment(s) — every bullet anchored, no orphan anchors, caps respected, wiring present and polecat sites in sync"
exit 0
