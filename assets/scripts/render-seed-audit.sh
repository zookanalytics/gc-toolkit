#!/usr/bin/env bash
# Render the agent seed as a committed, versioned audit artifact.
#
# WHAT THIS ANSWERS. "What text does agent X actually receive when it spawns?"
# Today that question is re-derived ad hoc from fragments every time somebody
# asks, and the largest part of the answer is invisible after the fact: a
# polecat transcript stores neither the skills appendix nor the standing prompt,
# so ~26k tokens per spawn have no post-hoc audit trail at all (tk-yhwfv.3).
# Rendering is the only way to see it. Committing the render is what makes it
# reviewable as ONE thing and diffable across time.
#
# WHAT IS RENDERED. Every agent the pack configures (`gc prime`) and every
# formula recipe it exposes (`gc formula show`), one file per scenario, plus an
# INDEX.md manifest of byte and token counts so a diff reads "keeper +1,400
# tokens" at a glance instead of as a wall of prose. The full text is the audit;
# the manifest is what makes it reviewable.
#
# WHY A SYNTHETIC CITY AND NOT THE LIVE ONE. `gc prime` renders against whatever
# city is in scope, and a city contributes real prompt text of its own: the
# loomington `city.toml` appends `command-glossary` and `operational-awareness`
# to every agent via [agent_defaults], which is 6,773 B — 19% — of the polecat
# seed. A golden file rendered against the operator's live city would move
# whenever that file moved, with no commit in this repo to explain it, and the
# check would fail for reasons nobody here controls. So the harness builds its
# own throwaway city from a scenario pinned BELOW (see synth_city), renders
# against that, and normalizes machine paths out of the result. The artifact is
# then a pure function of this repo plus the `gc` binary version, which is what
# a committed golden file has to be.
#
# Fidelity is not assumed, it is measured. Against `gc prime` in the live
# loomington city, seven of nine agents render BYTE-IDENTICAL (refinery, mayor,
# deacon, converse, mechanik, proactive, keeper); polecat and witness differ by
# one line of 36 KB — the rig checkout path, which in loomington happens to be
# the pack directory itself. Worst case 0.04%.
# specs/tk-yhwfv.3/seed-audit.md records the table and how to re-run it.
#
# WHAT IS NOT RENDERED — and cannot be, by this or any `gc prime` caller.
# `gc prime` resolves the CITY-scope agent and ignores rig-scoped patches
# entirely: with a rig whose [[rigs.patches]] appends two fragments to polecat,
# `gc config show` reports them on the resolved rig agent and `gc prime polecat
# --rig <that rig>` still renders byte-identical to every other rig. So the
# per-rig divergence in a multi-rig city is invisible here. INDEX.md carries the
# resolved per-rig fragment lists from `gc config show` instead, which is the
# part of that dimension the tooling can actually answer. See the spec.
#
# Also out of scope: the ~26k-token harness layer (base prompt, tool schemas,
# skills appendix, auto-memory index). That is a function of the Claude Code
# build, not of this repo, and a golden file over it would fail on every harness
# upgrade for reasons nobody here controls. specs/tk-yhwfv.2 already probes it.
#
# USAGE
#   render-seed-audit.sh                  regenerate generated/seed-audit/
#   render-seed-audit.sh --check          fail if the committed tree is stale
#   render-seed-audit.sh --check-merge <base> <head>
#                                         fail if that merge lands a stale tree
#   render-seed-audit.sh --print-sources  print the input manifest and exit
#   render-seed-audit.sh --install-hook   point core.hooksPath at assets/hooks
#   render-seed-audit.sh --out DIR        write somewhere else
#   render-seed-audit.sh --root DIR       audit a different pack checkout
#   render-seed-audit.sh --jobs N         parallelism (default: nproc, max 16)

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
OUT=""
JOBS=""
MODE="render"
MERGE_BASE=""
MERGE_HEAD=""

die() { printf 'render-seed-audit: %s\n' "$*" >&2; exit 2; }

while [ $# -gt 0 ]; do
    case "$1" in
        --check)        MODE="check" ;;
        --check-merge)  MODE="check-merge"; shift; MERGE_BASE="${1:-}"; shift; MERGE_HEAD="${1:-}" ;;
        --print-sources) MODE="sources" ;;
        --install-hook) MODE="install-hook" ;;
        --out)          shift; OUT="${1:-}" ;;
        --root)         shift; ROOT="$(cd "${1:-}" 2>/dev/null && pwd)" || die "--root: no such directory" ;;
        --jobs)         shift; JOBS="${1:-}" ;;
        -h|--help)      sed -n '/^# USAGE/,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)              die "unknown argument: $1" ;;
    esac
    shift
done

[ -n "$OUT" ] || OUT="$ROOT/generated/seed-audit"
[ -f "$ROOT/pack.toml" ] || die "not a pack checkout (no pack.toml): $ROOT"

if [ -z "$JOBS" ]; then
    JOBS="$(command -v nproc >/dev/null 2>&1 && nproc || echo 4)"
    [ "$JOBS" -gt 16 ] 2>/dev/null && JOBS=16
fi

# ---------------------------------------------------------------- placeholders
#
# Machine paths leak into the render through {{.ConfigDir}}-style expansions
# (mechanik and keeper cite their own pack dir; twelve agents cite the city
# root). Substituting them is what makes the committed bytes reproducible on
# another checkout. The tokens are bracketed rather than brace-wrapped because
# `gc formula show` output contains LITERAL un-rendered {{var}} syntax, and a
# {{PACK_ROOT}} placeholder would read as one more of those.
PH_PACK="[[PACK-ROOT]]"
PH_CITY="[[CITY-ROOT]]"
PH_HOME="[[HOME]]"

# ------------------------------------------------------------- source manifest
#
# The inputs a render is a function of. Over-inclusive on purpose: an extra
# input can only trigger a re-render nobody needed, while a missing one lets a
# stale artifact pass the cheap check. pack.toml earns its place twice over —
# it holds the per-agent inject_fragments_append lists AND the `sha:` pin for
# the imported gastown pack, so an upstream prompt change moves it too.
#
# THIS SCRIPT IS ITSELF AN INPUT, and leaving it out was a hole in the gate
# (tk-wchab, pre-open signoff P1). The synthetic city below is not a wrapper
# around the render — it is a variable the rendered prompts depend on, and the
# scenario comment says so. Edit one line of its [agent_defaults] and 13 agent
# prompts move; with only the content directories hashed, `--check` reported the
# tree stale while doctor/check-seed-audit-current still reported it current.
# That is the exact failure the check exists to catch, in the check.
#
# Hashing the whole file rather than parsing the scenario out of it is the same
# over-inclusive trade as above: a comment-only edit now costs one re-render,
# and no scenario edit can ever slip past. `assets/hooks/pre-commit` watches the
# same path for the same reason — the two input sets are kept in step by hand,
# and doctor/check-seed-audit-current/run.test.sh asserts a renderer-only change
# is seen by both.
#
# The `gc` version is deliberately NOT folded in. Prompt composition lives in
# the binary, so an upgrade really can move every byte of the artifact — but with
# no commit in this repo to explain it. INDEX.md records the version on its own
# line instead, which lets doctor/check-seed-audit-current call a content
# mismatch an error and a version-only mismatch a warning, and lets the manifest
# be recomputed on a host with no `gc` at all.
#
# The manifest is committed as generated/seed-audit/SOURCES.txt, one record per
# input, sorted by path. Per-input records rather than one digest over all of
# them is what keeps the artifact out of the merge queue's way: a repo-global
# value in a per-branch committed file moves on EVERY seed-input edit, so two
# pull requests touching two different agents collide on it unconditionally and
# each landing forces a rebase of everything still open. Per-input records move
# only where the input moved, so those two merge the way their sources do. The
# same reasoning keeps the per-agent byte rows in INDEX.md and leaves their
# totals out: a total is a repo-global line derived from rows already committed
# beside it.
#
# A record is two lines, path then hash, and the split is load-bearing rather
# than cosmetic. Git needs one unchanged line between two changes to merge them;
# a flat `<hash>  <path>` list leaves none, so the neighbouring entries of two
# different inputs still collide — measured on agents/deacon/prompt.template.md
# against agents/dog/agent.toml, adjacent in sort order, which conflicted. With
# the path on its own line only the hash moves, and the next record's path line
# is the separation.
digest_inputs() {
    local root="$1"
    find "$root/agents" "$root/template-fragments" "$root/formulas" "$root/packs" \
        -type f \( -name '*.md' -o -name '*.toml' \) -print 2>/dev/null | LC_ALL=C sort
    printf '%s\n' "$root/pack.toml"
    printf '%s\n' "$root/assets/scripts/render-seed-audit.sh"
}

MANIFEST_HEADER='# Every input generated/seed-audit is rendered from: one record per input,
# path then sha256, sorted by path. Written and read by
# assets/scripts/render-seed-audit.sh; the path line between two hashes is what
# lets two branches that moved different inputs merge.'

source_manifest() {
    local root="$1" f
    printf '%s\n' "$MANIFEST_HEADER"
    {
        while IFS= read -r f; do
            [ -f "$f" ] || continue
            printf '%s\t%s\n' "${f#"$root"/}" "$(sha256sum "$f" | cut -d' ' -f1)"
        done < <(digest_inputs "$root")
    } | LC_ALL=C sort | tr '\t' '\n'
}

# path<TAB>hash, one input per line — the manifest folded back into the shape a
# set comparison can be taken over.
manifest_pairs() { grep -v '^#' "$1" | paste - -; }

# Reported by the render summary so a run has a one-line identity. Nothing
# commits it: a stored copy is the churning line this artifact was cured of.
source_digest() {
    source_manifest "$1" | sha256sum | cut -d' ' -f1
}

if [ "$MODE" = "sources" ]; then
    source_manifest "$ROOT"
    exit 0
fi

# --------------------------------------------------------- merge-result check
#
# `--check` asks whether the artifact is current in ONE working tree, which is
# what assets/hooks/pre-commit already answers on every branch. What neither can
# see is that the artifact is a function of the whole source tree while it is
# committed per branch. A branch that moves a prompt input and a branch that
# re-renders from a base without that input touch no common file, so both merge
# cleanly and the second one's render lands on top of the first one's input.
# Rebase opens the same hole from the other side: a replayed commit runs no hook.
#
# This mode asks the question of the MERGE RESULT instead. `git merge-tree`
# writes the merged tree to the object store without touching any working tree,
# and the inputs of that tree are hashed and compared against the manifest the
# tree itself commits. Hashes only, no render: the merge cadence runs every
# minute per rig, a render costs half a minute and a `gc` binary, and "an input
# moved without the artifact moving" is the whole of the clobber. An artifact
# edited by hand together with its manifest stays `--check`'s question.
#
# The manifest comes from the renderer IN THE MERGED TREE when there is one,
# because the input set is whatever digest_inputs names there: a change that
# widens it records SOURCES.txt under the wider set, and this checkout's
# older copy would call that stale for a reason that is not the clobber. What
# runs is only its --print-sources, which returns before any render and needs no
# `gc`, under a timeout. Running it at all is the trust the merge is a second
# from extending anyway, and this arm sits after the review and approval gates.
if [ "$MODE" = "check-merge" ]; then
    [ -n "$MERGE_BASE" ] && [ -n "$MERGE_HEAD" ] || die "--check-merge needs <base-rev> <head-rev>"
    git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || die "--check-merge: not a git repository: $ROOT"
    for rev in "$MERGE_BASE" "$MERGE_HEAD"; do
        git -C "$ROOT" rev-parse --verify --quiet "$rev^{commit}" >/dev/null 2>&1 \
            || die "--check-merge: '$rev' names no commit in $ROOT; fetch it first"
    done

    mt_out="$(git -C "$ROOT" merge-tree --write-tree "$MERGE_BASE" "$MERGE_HEAD" 2>/dev/null)"; mt_rc=$?
    merged_tree="${mt_out%%$'\n'*}"
    if [ "$mt_rc" -ne 0 ] || [ -z "$merged_tree" ]; then
        die "--check-merge: '$MERGE_HEAD' does not merge into '$MERGE_BASE' in memory — a conflict, or a git without 'merge-tree --write-tree' (2.38)"
    fi

    SCRATCH="$(mktemp -d)" || die "mktemp failed"
    trap 'rm -rf "$SCRATCH"' EXIT
    # The merged tree materializes into its own subdirectory so the manifest
    # computed beside it is never mistaken for part of the tree under test.
    WORK="$SCRATCH/tree"
    mkdir -p "$WORK"
    git -C "$ROOT" archive --format=tar "$merged_tree" | tar -x -C "$WORK" \
        || die "--check-merge: could not materialize merged tree $merged_tree"

    merged_audit="$WORK/generated/seed-audit"
    merged_sources="$merged_audit/SOURCES.txt"
    if [ ! -d "$merged_audit" ]; then
        printf 'merging %s into %s carries no seed audit — nothing to keep current\n' \
            "$MERGE_HEAD" "$MERGE_BASE"
        exit 0
    fi
    [ -f "$merged_sources" ] || die "--check-merge: the merged seed audit commits no SOURCES.txt, so staleness is unverifiable"

    run_bounded() { if command -v timeout >/dev/null 2>&1; then timeout 60 "$@" </dev/null; else "$@" </dev/null; fi; }
    actual_sources="$SCRATCH/actual.txt"
    merged_renderer="$WORK/assets/scripts/render-seed-audit.sh"
    if [ -f "$merged_renderer" ]; then
        run_bounded bash "$merged_renderer" --root "$WORK" --print-sources >"$actual_sources" 2>/dev/null
    else
        source_manifest "$WORK" >"$actual_sources"
    fi
    [ -s "$actual_sources" ] || die "--check-merge: could not compute the input manifest of the merged tree"

    if cmp -s "$merged_sources" "$actual_sources"; then
        printf 'seed audit is current at the merge of %s into %s (%s inputs)\n' \
            "$MERGE_HEAD" "$MERGE_BASE" "$(manifest_pairs "$actual_sources" | wc -l | tr -d ' ')"
        exit 0
    fi

    # One record per input means the mismatch names the drifting files outright,
    # rather than reporting that two opaque digests differ. A changed input
    # contributes its recorded pair and its actual one, so the paths are
    # deduplicated; an added or removed input contributes one.
    drifted="$(LC_ALL=C comm -3 <(manifest_pairs "$merged_sources" | LC_ALL=C sort) \
                              <(manifest_pairs "$actual_sources" | LC_ALL=C sort) \
        | sed 's/^\t//' | cut -f1 | LC_ALL=C sort -u | head -10)"
    printf 'seed audit would be STALE at the merge of %s into %s:\n' "$MERGE_HEAD" "$MERGE_BASE" >&2
    printf 'inputs whose content does not match the manifest the merged tree commits:\n' >&2
    while IFS= read -r f; do [ -n "$f" ] && printf '  %s\n' "$f" >&2; done <<< "$drifted"
    printf 'Neither branch is wrong on its own: the artifact is a function of the whole source\n' >&2
    printf 'tree, so a branch that moves an input and a branch that re-renders clobber each\n' >&2
    printf 'other on landing. Bring the head branch current with %s, then:\n' "$MERGE_BASE" >&2
    printf '  assets/scripts/render-seed-audit.sh && git add generated/seed-audit\n' >&2
    exit 1
fi

# ------------------------------------------------------------------ hook install
if [ "$MODE" = "install-hook" ]; then
    top="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null)" || die "not a git repo: $ROOT"
    hookdir="$(git -C "$ROOT" rev-parse --git-common-dir 2>/dev/null)/hooks"
    # Refuse to shadow hooks somebody already installed by hand: core.hooksPath
    # replaces .git/hooks wholesale rather than layering on top of it.
    existing=""
    if [ -d "$hookdir" ]; then
        existing="$(find "$hookdir" -maxdepth 1 -type f ! -name '*.sample' -printf '%f\n' 2>/dev/null)"
    fi
    if [ -n "$existing" ]; then
        printf 'refusing to set core.hooksPath: %s already holds hand-installed hook(s):\n' "$hookdir" >&2
        printf '  %s\n' $existing >&2
        printf 'core.hooksPath REPLACES that directory rather than layering onto it. Move or merge them first.\n' >&2
        exit 2
    fi
    git -C "$top" config core.hooksPath assets/hooks || die "could not set core.hooksPath"
    printf 'core.hooksPath = assets/hooks (repo: %s)\n' "$top"
    printf 'The path is relative, so it resolves in every linked worktree too.\n'
    exit 0
fi

# Everything past this point renders. --print-digest and --install-hook return
# above it precisely so they still work where gc does not exist: the doctor
# check recomputes the digest, and a pack linted outside a city has no binary.
command -v gc >/dev/null 2>&1 || die "gc is not on PATH — the render needs the gc binary"

# ------------------------------------------------------------ synthetic city
#
# A fixed basename ("seed-audit-city") because the city name reaches the
# rendered text; a mktemp parent so concurrent runs do not collide. Deliberately
# hand-written rather than produced by `gc init`: init reaches for the beads
# store and, on a host with a live Dolt server, talks to it.
TMPROOT="$(mktemp -d)" || die "mktemp failed"
CITY="$TMPROOT/seed-audit-city"
cleanup() { rm -rf "$TMPROOT"; }
trap cleanup EXIT

# The scenario is written with a QUOTED heredoc and @@ROOT@@ substituted
# afterwards. An unquoted one would expand every $ and every backtick in the
# prose below — and the prose talks about `gc prime`, so the first run spliced a
# whole rendered agent prompt into the middle of the TOML.
synth_city() {
    mkdir -p "$CITY/.gc" "$CITY/rigs/gc-toolkit" "$CITY/rigs/gascity"
    cat > "$CITY/city.toml.in" <<'EOF'
# Throwaway city built by assets/scripts/render-seed-audit.sh. Never started,
# never registered, deleted when the render finishes. Its content IS part of the
# audited surface: every line here is a variable the rendered prompts depend on.
[workspace]
provider = "claude"

[providers]
[providers.claude]
base = "builtin:claude"
[providers.codex]
base = "builtin:codex"
[providers.gemini]
base = "builtin:gemini"

[imports]
# core and bd are the required builtin packs; without them the formula roster
# comes back at 14 of 28. Both spellings of a bundled source resolve to the same
# cache entry, and the running binary pre-seeds that cache, so this needs no
# network.
[imports.core]
source = "https://github.com/gastownhall/gascity.git//internal/bootstrap/packs/core"
[imports.bd]
source = "https://github.com/gastownhall/gascity.git//examples/bd"
[imports.gc-toolkit]
source = "@@ROOT@@"

# Mirrors the loomington city.toml. These two fragments are 19% of the polecat
# seed and they are a CITY-level setting, so a pack-only render omits them and
# under-reports every agent. Pinning them here is what makes the artifact match
# what agents actually receive.
[agent_defaults]
default_sling_formula = "mol-polecat-work"
append_fragments = ["command-glossary", "operational-awareness"]

# Two rig shapes, and they carry the names of the two that exist in loomington
# because the rig name is substituted INTO the rendered prompt ("a worker agent
# in the gc-toolkit rig", "gc session nudge gc-toolkit/..."). A scenario rig
# called "plain" would render an audit nobody can compare against a live seed.
#
# gc-toolkit is the plain shape: this pack and nothing else, shared with
# signal-loom and shutupandlisten. gascity adds the opt-in sub-pack plus the
# [[rigs.patches]] that append its rebase doctrine to two agents — not
# decoration, it is the only way the fragment table in INDEX.md can show the
# rig-scope divergence that `gc prime` cannot render.
[[rigs]]
name = "gc-toolkit"
prefix = "tk"
[rigs.imports]
[rigs.imports.gc-toolkit]
source = "@@ROOT@@"

[[rigs]]
name = "gascity"
prefix = "gc"
[rigs.imports]
[rigs.imports.gc-toolkit]
source = "@@ROOT@@"
[rigs.imports.gascity-keeper]
source = "@@ROOT@@/packs/gascity-keeper"
[[rigs.patches]]
agent = "polecat"
inject_fragments_append = ["rebase-conventions", "polecat-patterns"]
[[rigs.patches]]
agent = "refinery"
inject_fragments_append = ["rebase-conventions", "refinery-rebase-handling"]
EOF
    cat > "$CITY/.gc/site.toml" <<'EOF'
[[rig]]
name = "gc-toolkit"
path = "rigs/gc-toolkit"

[[rig]]
name = "gascity"
path = "rigs/gascity"
EOF
    ROOT="$ROOT" python3 -c '
import os, sys
src = open(sys.argv[1], encoding="utf-8").read()
open(sys.argv[2], "w", encoding="utf-8").write(src.replace("@@ROOT@@", os.environ["ROOT"]))
' "$CITY/city.toml.in" "$CITY/city.toml" || die "could not materialize the scenario city.toml"
    rm -f "$CITY/city.toml.in"
}

# Every gc call runs through here. `env -i` is not tidiness: an inherited
# GC_CITY would point the render at the operator's live city, and inherited
# GC_RIG/GC_AGENT/GC_SESSION_* leak the CALLER's identity into the rendered
# prompt (a polecat running this by hand renders its own agent name and worktree
# path into the artifact). Scrubbing is what makes the output depend on the
# scenario alone.
gcq() {
    env -i \
        PATH="$PATH" \
        HOME="$HOME" \
        TERM=dumb \
        NO_COLOR=1 \
        gc --city "$CITY" "$@"
}

synth_city

# `gc config show` is the load gate: if the scenario does not compose, `gc prime`
# does NOT inherit the failure — it prints a 16-line stub and exits 0. Checking
# here is what stops the audit from silently recording stubs for every agent.
if ! gcq config show >"$TMPROOT/config.txt" 2>"$TMPROOT/config.err"; then
    printf 'the synthetic city failed to compose — the render cannot proceed:\n' >&2
    grep -v '^named_session ' < "$TMPROOT/config.err" | head -20 >&2
    exit 2
fi

# --------------------------------------------------------- template preflight
#
# An agent whose prompt template file is MISSING does not fail anything: pack
# composition quietly drops the agent's prompt_template, and `gc prime` — even
# with --strict, which by contract does not object to an agent that "intentionally
# lacks a prompt_template" — renders the builtin worker prompt and exits 0.
# Measured: remove agents/mechanik/prompt.template.md and mechanik renders 4,461 B
# of generic "# Graph Worker" instead of 36,222 B of its own doctrine, with a
# clean exit everywhere. Nothing downstream can tell that apart from an agent
# that never had a prompt.
#
# So the readability of this pack's own templates is asserted here, before any
# rendering, by the convention gascity resolves them with: an agent directory
# either declares prompt_template or ships prompt.template.md beside its
# agent.toml. (A declared cross-pack "<pack>//<subpath>" reference resolves
# against the import closure and is checked against a live city by
# doctor/check-agent-prompt-integrity, which owns that question.)
missing_templates=""
while IFS= read -r atoml; do
    adir="$(dirname "$atoml")"
    if grep -E '^prompt_template *=' < "$atoml" > /dev/null 2>&1; then
        continue
    fi
    [ -f "$adir/prompt.template.md" ] && continue
    missing_templates="${missing_templates}${adir#"$ROOT"/}
"
done < <(find "$ROOT/agents" "$ROOT/packs" -mindepth 2 -maxdepth 4 -name agent.toml -print 2>/dev/null | LC_ALL=C sort)

if [ -n "$missing_templates" ]; then
    printf 'agent template(s) missing — refusing to render a seed that would silently\n' >&2
    printf 'substitute the builtin worker prompt for real doctrine:\n' >&2
    printf '%s' "$missing_templates" >&2
    exit 2
fi

# Agents this pack owns. Only these are held to the "must not render a builtin
# fallback" rule below: claude, codex, gemini and control-dispatcher legitimately
# ARE the builtin worker prompt, and banning it outright would fail them.
PACK_AGENTS=""
while IFS= read -r adir; do
    PACK_AGENTS="${PACK_AGENTS} $(basename "$adir")"
done < <(find "$ROOT/agents" "$ROOT/packs" -mindepth 2 -maxdepth 4 -name agent.toml -printf '%h\n' 2>/dev/null | LC_ALL=C sort)

# ------------------------------------------------------------------ inventory
#
# One entry per distinct agent NAME. Qualified and rig-scoped spellings
# (audit/gc-toolkit.polecat) are deliberately collapsed: they were measured to
# render byte-identically, because gc prime does not honour rig scope.
mapfile -t AGENTS < <(gcq agent list --json 2>/dev/null \
    | jq -r '.agents[].name' 2>/dev/null | LC_ALL=C sort -u)
mapfile -t FORMULAS < <(gcq formula list 2>/dev/null \
    | grep -E '^[a-z0-9][a-z0-9._-]*$' | LC_ALL=C sort -u)

[ "${#AGENTS[@]}" -gt 0 ]   || die "no agents resolved from the synthetic city"
[ "${#FORMULAS[@]}" -gt 0 ] || die "no formulas resolved from the synthetic city"

# ------------------------------------------------------------------ normalize
#
# A literal string replace rather than sed: these are filesystem paths from the
# caller, and any delimiter sed could use is a legal character in one.
py_normalize="$TMPROOT/normalize.py"
cat > "$py_normalize" <<'PYEOF'
import sys

src = sys.stdin.buffer.read().decode("utf-8", "surrogateescape")
# (needle, token) pairs, applied longest-needle-first so that a path nested
# under another (pack root under $HOME, city root under $TMPDIR under $HOME)
# is not half-rewritten by the shorter one.
pairs = []
argv = sys.argv[1:]
for i in range(0, len(argv), 2):
    needle = argv[i]
    if needle:
        pairs.append((needle, argv[i + 1]))
for needle, token in sorted(pairs, key=lambda p: len(p[0]), reverse=True):
    src = src.replace(needle, token)
# Every rendered file ends with exactly one newline, whatever the source prompt
# ends with: a trailing blank line is a whitespace defect in a committed file,
# and the sources are the wrong place to fix it — the next prompt edit would
# restore it.
src = src.rstrip("\n") + "\n"
sys.stdout.buffer.write(src.encode("utf-8", "surrogateescape"))
PYEOF

# ------------------------------------------------------------------- rendering
#
# The two prompts gascity substitutes when it has nothing else to render: the
# 16-line default (`gc prime` on an unresolvable name — exit 0, nothing on
# stderr) and the builtin worker (an agent with no resolvable prompt_template).
# For an agent this pack owns, either one means the audit is about to record a
# generic prompt as that agent's doctrine, which is worse than recording nothing.
# --strict catches the first; only this catches the second.
FALLBACK_MARKERS=(
    'You are an agent in a Gas City workspace. Claim available work and execute it.'
    'You are a worker agent in a Gas City workspace using the graph-first workflow'
)

# Formula scopes, tried in order. `gc formula list` answers CITY-WIDE and names
# every formula in every rig's import closure, but `gc formula show` is
# scope-strict: the four mol-upstream-gc-* recipes live in the opt-in
# gascity-keeper sub-pack, which only the gascity-shaped rig imports, so a
# city-scope show reports them "not found in search paths" even though list just
# offered them. Walking the scopes is what closes that gap.
FORMULA_SCOPES=("" "gc-toolkit" "gascity")

render_one() {
    local kind="$1" name="$2" dest="$3" raw rc scope
    raw="$TMPROOT/raw.$kind.$name"
    if [ "$kind" = "agent" ]; then
        gcq prime "$name" --strict >"$raw" 2>"$raw.err"
        rc=$?
    else
        rc=1
        for scope in "${FORMULA_SCOPES[@]}"; do
            if [ -z "$scope" ]; then
                gcq formula show "$name" >"$raw" 2>"$raw.err"
            else
                gcq formula show "$name" --rig "$scope" >"$raw" 2>"$raw.err"
            fi
            rc=$?
            if [ "$rc" -eq 0 ] && [ -s "$raw" ]; then
                printf '%s\n' "${scope:-city}" > "$dest.scope"
                break
            fi
        done
    fi
    if [ "$rc" -ne 0 ]; then
        printf 'FAILED %s %s (exit %s)\n' "$kind" "$name" "$rc" > "$dest.error"
        grep -v '^named_session ' < "$raw.err" | head -5 >> "$dest.error"
        return 1
    fi
    if [ ! -s "$raw" ]; then
        printf 'FAILED %s %s (empty render)\n' "$kind" "$name" > "$dest.error"
        return 1
    fi
    if [ "$kind" = "agent" ] && [[ " $PACK_AGENTS " == *" $name "* ]]; then
        local marker
        for marker in "${FALLBACK_MARKERS[@]}"; do
            if grep -F -e "$marker" < "$raw" > /dev/null; then
                printf 'FAILED agent %s (rendered a builtin fallback prompt, not its own doctrine)\n' \
                    "$name" > "$dest.error"
                printf '  matched: %s\n' "$marker" >> "$dest.error"
                return 1
            fi
        done
    fi
    python3 "$py_normalize" \
        "$ROOT" "$PH_PACK" \
        "$CITY" "$PH_CITY" \
        "$HOME" "$PH_HOME" \
        < "$raw" > "$dest"
    rm -f "$raw" "$raw.err"
}

STAGE="$TMPROOT/stage"
mkdir -p "$STAGE/agents" "$STAGE/formulas"

running=0
for a in "${AGENTS[@]}"; do
    render_one agent "$a" "$STAGE/agents/$a.md" &
    running=$((running + 1))
    if [ "$running" -ge "$JOBS" ]; then wait -n 2>/dev/null || true; running=$((running - 1)); fi
done
for f in "${FORMULAS[@]}"; do
    render_one formula "$f" "$STAGE/formulas/$f.md" &
    running=$((running + 1))
    if [ "$running" -ge "$JOBS" ]; then wait -n 2>/dev/null || true; running=$((running - 1)); fi
done
wait

errors="$(find "$STAGE" -name '*.error' -print 2>/dev/null)"
if [ -n "$errors" ]; then
    printf 'render failed — refusing to write a partial audit:\n' >&2
    while IFS= read -r e; do cat "$e" >&2; done <<< "$errors"
    exit 2
fi

# --------------------------------------------------------------------- INDEX
#
# Token counts are bytes/4, the same estimator the measurements in the bead used
# (keeper 64,288 B -> 16,072 tok). It is an estimate and INDEX.md says so; its
# job is to make a diff legible as "+1,400 tokens", not to bill anyone.
est_tokens() { printf '%s\n' "$(( $1 / 4 ))"; }
commas() { printf "%s\n" "$1" | sed -e :a -e 's/\(.*[0-9]\)\([0-9]\{3\}\)/\1,\2/;ta'; }

# Said on stdout, not committed. The number is worth knowing on a render; a copy
# of it in a per-branch file is a repo-global line that every seed-input edit
# rewrites, which is what collides two otherwise unrelated pull requests.
report_totals() {
    printf '  agents %s B / ~%s tok · formulas %s B / ~%s tok · total %s B / ~%s tok\n' \
        "$(commas "$total_a")" "$(commas "$(est_tokens "$total_a")")" \
        "$(commas "$total_f")" "$(commas "$(est_tokens "$total_f")")" \
        "$(commas "$((total_a + total_f))")" "$(commas "$(est_tokens "$((total_a + total_f))")")"
}

DIGEST="$(source_digest "$ROOT")"
GCVER="$(gc version 2>/dev/null | head -1)"

# Resolved per-rig fragment composition, straight out of the composed config.
# This is the one place the per-rig dimension is visible at all: `gc prime`
# collapses it (see the header), so a reader who needs to know that one rig's
# polecat carries two extra fragments has to read it here.
fragment_table() {
    python3 - "$TMPROOT/config.txt" <<'PYEOF'
import sys, re

# `gc config show` emits flat `key = value` lines inside each [[agent]] block,
# but a block can also carry an [agent.env] sub-table BEFORE inject_fragments.
# Treating that sub-table header as the end of the block would silently drop the
# fragment list of every agent that has one, so only a non-`[agent.` header
# closes a block.
blocks, cur = [], None
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    line = line.rstrip("\n")
    if line == "[[agent]]":
        cur = {}
        blocks.append(cur)
        continue
    if line.startswith("[agent.") or line.startswith("[[agent."):
        continue
    if line.startswith("["):
        cur = None
        continue
    if cur is None:
        continue
    m = re.match(r'^(name|dir|inject_fragments) = (.*)$', line)
    if not m:
        continue
    key, raw = m.group(1), m.group(2)
    if key == "inject_fragments":
        cur[key] = re.findall(r'"([^"]*)"', raw)
    else:
        cur[key] = raw.strip('"')

rows = {}
for b in blocks:
    name = b.get("name")
    if not name:
        continue
    scope = b.get("dir") or "city"
    rows.setdefault(name, {}).setdefault(tuple(b.get("inject_fragments", [])), set()).add(scope)

print("| agent | scopes | distinct fragment sets | fragments |")
print("|---|---|---:|---|")
for name in sorted(rows):
    variants = sorted(rows[name])
    flag = " **DIVERGES**" if len(variants) > 1 else ""
    for i, frags in enumerate(variants):
        label = name + flag if i == 0 else ""
        scopes = ", ".join("`%s`" % s for s in sorted(rows[name][frags]))
        body = ", ".join("`%s`" % f for f in frags) if frags else "_none_"
        print("| %s | %s | %d | %s |" % (label, scopes, len(variants), body))
PYEOF
}

{
    cat <<EOF
# Agent Seed Audit

Generated by \`assets/scripts/render-seed-audit.sh\`. **Do not hand-edit** — run
the script and commit its output.

Every file under \`agents/\` is the complete standing prompt one agent receives
at spawn. Every file under \`formulas/\` is one compiled formula recipe. Together
they are the part of the seed this repo controls.

- \`gc\` version: \`$GCVER\`
- agents: ${#AGENTS[@]} · formulas: ${#FORMULAS[@]}
- input manifest: \`SOURCES.txt\`

## Scope

**Mandate.** What text each agent and formula in this pack renders to, as a
committed artifact that moves in reviewable diffs.

**Boundaries.** The pack's own contribution plus the city-level scenario pinned
in the render script. NOT the ~26k-token harness layer (base prompt, tool
schemas, skills appendix, auto-memory index) — that belongs to the Claude Code
build, and \`specs/tk-yhwfv.2\` probes it separately. NOT rig-scoped agent
patches, which \`gc prime\` does not honour; the fragment table below is what
covers that dimension.

## Regenerating

    assets/scripts/render-seed-audit.sh

## Agent prompts

| agent | bytes | est. tokens |
|---|---:|---:|
EOF

    total_a=0
    for a in "${AGENTS[@]}"; do
        b=$(wc -c < "$STAGE/agents/$a.md")
        total_a=$((total_a + b))
        printf '| [`%s`](agents/%s.md) | %s | %s |\n' "$a" "$a" "$(commas "$b")" "$(commas "$(est_tokens "$b")")"
    done

    cat <<'EOF'

## Formula recipes

`scope` is the narrowest scenario scope that could resolve the recipe. `city`
means every rig sees it; a rig name means only that rig shape imports the pack
carrying it. `gc formula list` answers city-wide and offers all of them at every
scope, but `gc formula show` is scope-strict and reports the rig-only ones as
"not found in search paths" from anywhere else.

| formula | scope | bytes | est. tokens |
|---|---|---:|---:|
EOF

    total_f=0
    for f in "${FORMULAS[@]}"; do
        b=$(wc -c < "$STAGE/formulas/$f.md")
        total_f=$((total_f + b))
        sc="city"
        [ -f "$STAGE/formulas/$f.md.scope" ] && sc="$(cat "$STAGE/formulas/$f.md.scope")"
        printf '| [`%s`](formulas/%s.md) | `%s` | %s | %s |\n' \
            "$f" "$f" "$sc" "$(commas "$b")" "$(commas "$(est_tokens "$b")")"
    done

    cat <<'EOF'

Token counts are `bytes / 4`, the estimator the measurements this artifact was
built on used. They exist to make a diff legible ("keeper +1,400 tokens"), not
to bill anyone.

## Resolved fragment composition

`gc prime` resolves the CITY-scope agent and ignores rig-scoped
`[[rigs.patches]]`, so the prompts above are identical for every rig even where
the composed config says otherwise. This table is read from `gc config show`,
which does see rig scope. An agent marked **DIVERGES** renders one prompt above
but composes differently per rig — that difference reaches the agent at spawn
and is not visible in any `gc prime` output, including the one the agent itself
runs to re-prime after compaction.

EOF
    fragment_table

    cat <<'EOF'

## Path placeholders

Machine-specific paths are substituted so the bytes are reproducible on any
checkout:

| token | stands for |
|---|---|
| `[[PACK-ROOT]]` | the pack checkout the render ran against |
| `[[CITY-ROOT]]` | the throwaway city the render built |
| `[[HOME]]` | the rendering user's home directory |
EOF
} > "$STAGE/INDEX.md"

# What the freshness checks compare against, and the only machine-read file in
# the tree. It is written last so it describes the sources this render read.
source_manifest "$ROOT" > "$STAGE/SOURCES.txt"

# The per-formula scope sidecars were scratch for the tables above; the emitted
# tree holds rendered text, INDEX.md and the manifest.
find "$STAGE" -name '*.scope' -delete

# ---------------------------------------------------------------------- emit
if [ "$MODE" = "check" ]; then
    # An absent tree — or the README-only stub a fresh checkout ships — is
    # MISSING, not stale: the first render recreates it.
    if [ ! -d "$OUT" ] || [ ! -f "$OUT/INDEX.md" ]; then
        printf 'seed audit is MISSING at %s (first render recreates it)\n' "${OUT#"$ROOT"/}" >&2
        printf 'run: assets/scripts/render-seed-audit.sh && git add generated/seed-audit\n' >&2
        exit 1
    fi
    if diff -r -q "$OUT" "$STAGE" >"$TMPROOT/diff.txt" 2>&1; then
        printf 'seed audit is current (%s agents, %s formulas, digest %s)\n' \
            "${#AGENTS[@]}" "${#FORMULAS[@]}" "${DIGEST:0:12}"
        report_totals
        exit 0
    fi
    printf 'seed audit is STALE — the committed tree does not match a fresh render:\n' >&2
    sed "s|$STAGE|<fresh>|g; s|$OUT|<committed>|g" < "$TMPROOT/diff.txt" | head -40 >&2
    printf '\nrun: assets/scripts/render-seed-audit.sh && git add generated/seed-audit\n' >&2
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$(dirname "$OUT")"
cp -r "$STAGE" "$OUT"
printf 'wrote %s (%s agents, %s formulas, digest %s)\n' \
    "${OUT#"$ROOT"/}" "${#AGENTS[@]}" "${#FORMULAS[@]}" "${DIGEST:0:12}"
report_totals
