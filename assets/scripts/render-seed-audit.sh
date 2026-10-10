#!/usr/bin/env bash
# Render the agent seed as a committed, versioned audit artifact.
#
# WHAT THIS ANSWERS. "What text does agent X actually receive when it spawns?"
# Today that question is re-derived ad hoc from fragments every time somebody
# asks, and the largest part of the answer is invisible after the fact: a
# polecat transcript stores neither the skills appendix nor the standing prompt,
# so ~26k tokens per spawn have no post-hoc audit trail at all.
# Rendering is the only way to see it. Committing the render is what makes it
# reviewable as ONE thing and diffable across time.
#
# WHAT IS RENDERED. Every agent the pack configures (`gc prime`) and every
# formula recipe it exposes (`gc formula show`), one file per scenario, plus an
# INDEX.md that links each of them and carries what `gc prime` cannot show (see
# below). The full text is the audit, and its diff is the review.
#
# Byte and token counts print on request (--sizes) and are never committed. A
# committed size row moves on every edit to its agent's prompt, so two pull
# requests that touch two different agents conflict on neighbouring rows, and
# one fragment edit rewrites the row of every agent that composes it. INDEX.md
# holds only what moves when the pack's composition moves.
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
# then a pure function of this repo, which is what a committed golden file has
# to be.
#
# Fidelity is not assumed, it is measured. Against `gc prime` in the live
# loomington city, seven of nine agents render BYTE-IDENTICAL (refinery, mayor,
# deacon, converse, mechanik, proactive, keeper); polecat and witness differ by
# one line of 36 KB — the rig checkout path, which in loomington happens to be
# the pack directory itself. Worst case 0.04%.
# specs/tk-yhwfv.3/seed-audit.md records the table and how to re-run it.
#
# WHOSE TEXT IT IS. Rendering every agent the synthetic city configures means
# the tree also holds prompts this pack does not author. claude.md, codex.md
# and gemini.md come from the `builtin:` providers, and their startup protocol
# is the core pack's shared claim-protocol fragment; dog.md comes from the bd
# example pack. In the gascity repo those two sources are
# internal/bootstrap/packs/core/template-fragments/claim-protocol.template.md
# and examples/bd/dolt/agents/dog/prompt.template.md. A render is a mirror of
# what the running binary emits, so prose that reads wrong in one of these
# files is corrected upstream and arrives here on the next regeneration.
# Editing the render instead would make the audit disagree with the text the
# agents actually receive.
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
#                                         render that merge, and fail if it lands
#                                         a render the merge made stale
#   render-seed-audit.sh --sizes [<rev>]  print each render's bytes and tokens,
#                                         and the change since <rev> when given
#   render-seed-audit.sh --install-hook   point core.hooksPath at assets/hooks
#   render-seed-audit.sh --out DIR        write somewhere else
#   render-seed-audit.sh --root DIR       audit a different pack checkout
#   render-seed-audit.sh --jobs N         parallelism (default: nproc, max 16)

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$HERE/$(basename "${BASH_SOURCE[0]}")"
ROOT="$(cd "$HERE/../.." && pwd)"
OUT=""
JOBS=""
MODE="render"
MERGE_BASE=""
MERGE_HEAD=""
SIZES_BASE=""

die() { printf 'render-seed-audit: %s\n' "$*" >&2; exit 2; }

while [ $# -gt 0 ]; do
    case "$1" in
        --check)         MODE="check" ;;
        --check-merge)   MODE="check-merge"; shift; MERGE_BASE="${1:-}"; shift; MERGE_HEAD="${1:-}" ;;
        # The base is optional, so an argument that is a flag is not one.
        --sizes)         MODE="sizes"
                         if [ $# -gt 1 ] && [ "${2#-}" = "$2" ]; then shift; SIZES_BASE="$1"; fi ;;
        --install-hook)  MODE="install-hook" ;;
        --out)           shift; OUT="${1:-}" ;;
        --root)          shift; ROOT="$(cd "${1:-}" 2>/dev/null && pwd)" || die "--root: no such directory" ;;
        --jobs)          shift; JOBS="${1:-}" ;;
        -h|--help)       sed -n '/^# USAGE/,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)               die "unknown argument: $1" ;;
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
# (mechanik and keeper cite their own pack dir; mechanik, polecat and
# polecat-codex cite the city root). Substituting them is what makes the
# committed bytes reproducible on another checkout. The tokens are bracketed
# rather than brace-wrapped because `gc formula show` output contains LITERAL
# un-rendered {{var}} syntax, and a {{PACK_ROOT}} placeholder would read as one
# more of those.
PH_PACK="[[PACK-ROOT]]"
PH_CITY="[[CITY-ROOT]]"
PH_HOME="[[HOME]]"

# ---------------------------------------------------------- trees at a revision
#
# --check-merge and --sizes <rev> render trees that are not checked out. Each
# tree is written out of the object store into a scratch directory and rendered
# by the copy of this script the tree carries. This script is part of what a
# tree renders to, because the synthetic city below is a variable every rendered
# prompt depends on, so a revision that edits the script is rendered by its own
# copy. A tree that carries no copy is rendered by this one.
#
# A render is bounded. The merge gate runs inside the refinery's merge cadence,
# where a `gc` that never returns would stall the whole pass, and a bounded
# render holds a single merge instead.
RENDER_BOUND=180

# The archive goes through a file, not a pipe. tar stops reading at the
# end-of-archive marker, and git archive, still writing the padding after it,
# can die of SIGPIPE, which pipefail reports as a failed materialize.
materialize() { # <commit-or-tree> <dir>
    mkdir -p "$2" && git -C "$ROOT" archive --format=tar -o "$2.tar" "$1" \
        && tar -x -f "$2.tar" -C "$2" && rm -f "$2.tar"
}

run_bounded() { # <seconds> <command...>
    local secs="$1"; shift
    if command -v timeout >/dev/null 2>&1; then timeout "$secs" "$@" </dev/null; else "$@" </dev/null; fi
}

# Renders <tree> into <out>, and leaves what the render said in <out>.log.
render_tree() { # <tree> <out>
    local renderer="$1/assets/scripts/render-seed-audit.sh"
    [ -f "$renderer" ] || renderer="$SELF"
    run_bounded "$RENDER_BOUND" bash "$renderer" --root "$1" --out "$2" --jobs "$JOBS" >"$2.log" 2>&1
}

render_failed() { # <what was rendered> <out> <rc>
    if [ "$3" -eq 124 ]; then
        printf 'render-seed-audit: could not render %s: the render did not finish within %ss\n' \
            "$1" "$RENDER_BOUND" >&2
    else
        printf 'render-seed-audit: could not render %s (exit %s):\n' "$1" "$3" >&2
        tail -n 12 "$2.log" 2>/dev/null | sed 's/^/  /' >&2
    fi
    exit 2
}

if [ "$MODE" = "sizes" ] && [ -n "$SIZES_BASE" ]; then
    git -C "$ROOT" rev-parse --verify --quiet "$SIZES_BASE^{commit}" >/dev/null 2>&1 \
        || die "--sizes: '$SIZES_BASE' names no commit in $ROOT"
fi

# --------------------------------------------------------- merge-result check
#
# `--check` asks whether the artifact is current in ONE working tree, which is
# what assets/hooks/pre-commit keeps true on a branch it runs on. What neither
# can see is that the artifact is a function of the whole source tree while it
# is committed per branch. A branch that moves a prompt input and a branch that
# re-renders from a base without that input touch no common file, so both merge
# cleanly and the second one's render lands on top of the first one's input.
# Rebase opens the same hole from the other side: a replayed commit runs no hook.
#
# This mode asks the question of the MERGE RESULT instead. `git merge-tree`
# writes the merged tree to the object store without touching any working tree,
# and that tree is rendered (see above). Each file the render writes or the
# merge commits is then judged on its own:
#
#   - It passes when the merge result commits it exactly as rendered.
#   - Otherwise it passes when the merge keeps it as <base> commits it and it
#     renders the same on <base> as on the merge result. <base> was already
#     stale there and the head did not cause it, so the file is reported as
#     <base>'s own staleness and holds nothing. Holding it would hold every
#     merge behind a defect none of them carries, such as a newer `gc`
#     rendering a builtin provider's prompt differently.
#   - Otherwise it fails.
#
# Agents and formulas added or removed are judged by the same rule: a render the
# merge does not commit fails, and so does a committed render of something that
# no longer exists. <base> is rendered only when some file fails the first test.
# Exits 0 when every file passes, 1 when one fails, and 2 when the merge cannot
# be judged: a conflict, no `gc` to render with, or a render that fails.
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

    SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/gctk-render-seed-audit.XXXXXX")" || die "mktemp failed"
    trap 'rm -rf "$SCRATCH"' EXIT
    # Each tree and each render gets a directory of its own, so nothing written
    # beside a tree is mistaken for part of it.
    AUDIT="generated/seed-audit"
    MERGED="$SCRATCH/merged"
    MERGED_RENDER="$SCRATCH/merged.render"
    BASE="$SCRATCH/base"
    BASE_RENDER="$SCRATCH/base.render"
    materialize "$merged_tree" "$MERGED" \
        || die "--check-merge: could not materialize merged tree $merged_tree"

    # No INDEX.md in the merge result means no artifact, or the stub tree a pack
    # carries before its first render. Either way there is nothing to keep
    # current, and nothing to render.
    if [ ! -f "$MERGED/$AUDIT/INDEX.md" ]; then
        printf 'merging %s into %s carries no seed audit — nothing to keep current\n' \
            "$MERGE_HEAD" "$MERGE_BASE"
        exit 0
    fi
    command -v gc >/dev/null 2>&1 \
        || die "--check-merge: gc is not on PATH, and judging what a merge lands means rendering it"

    render_tree "$MERGED" "$MERGED_RENDER"; rc=$?
    [ "$rc" -eq 0 ] || render_failed "the merge of $MERGE_HEAD into $MERGE_BASE" "$MERGED_RENDER" "$rc"

    # Two files with the same bytes, or two paths that both hold no file.
    same() { if [ -f "$1" ] && [ -f "$2" ]; then cmp -s "$1" "$2"; else [ ! -f "$1" ] && [ ! -f "$2" ]; fi; }
    files_under() { [ -d "$1" ] && ( cd "$1" && find . -type f -print ) | sed 's|^\./||'; }

    unmatched=()
    while IFS= read -r p; do
        same "$MERGED_RENDER/$p" "$MERGED/$AUDIT/$p" || unmatched+=("$p")
    done < <({ files_under "$MERGED_RENDER"; files_under "$MERGED/$AUDIT"; } | LC_ALL=C sort -u)

    held=()
    base_stale=()
    if [ "${#unmatched[@]}" -gt 0 ]; then
        materialize "$MERGE_BASE" "$BASE" || die "--check-merge: could not materialize $MERGE_BASE"
        render_tree "$BASE" "$BASE_RENDER"; rc=$?
        [ "$rc" -eq 0 ] || render_failed "$MERGE_BASE" "$BASE_RENDER" "$rc"
        for p in "${unmatched[@]}"; do
            if same "$MERGED/$AUDIT/$p" "$BASE/$AUDIT/$p" && same "$BASE_RENDER/$p" "$MERGED_RENDER/$p"; then
                base_stale+=("$p")
            else
                held+=("$p")
            fi
        done
    fi

    # Why one file fails both tests, in the terms a person fixing it acts on.
    why_held() { # <path>
        if [ ! -f "$MERGED/$AUDIT/$1" ]; then
            printf 'rendered, but the merge does not commit it'
        elif [ ! -f "$MERGED_RENDER/$1" ]; then
            printf 'committed, but nothing renders it'
        elif same "$MERGED/$AUDIT/$1" "$BASE/$AUDIT/$1"; then
            printf 'the merge changes its render but keeps the copy %s commits' "$MERGE_BASE"
        else
            printf 'the merge commits a copy that is neither %s'"'"'s nor its render' "$MERGE_BASE"
        fi
    }
    list() { # <path>... — at most 20 lines, so a wholesale miss stays readable
        local p n=0
        for p in "$@"; do
            n=$((n + 1))
            if [ "$n" -gt 20 ]; then printf '  … and %s more\n' "$(($# - 20))"; break; fi
            printf '  %s\n' "$p"
        done
    }
    report_base_stale() {
        [ "${#base_stale[@]}" -gt 0 ] || return 0
        printf '%s is already stale in these files, which the merge leaves as %s has them (not held):\n' \
            "$MERGE_BASE" "$MERGE_BASE"
        list "${base_stale[@]}"
    }

    n_rendered="$(files_under "$MERGED_RENDER" | wc -l | tr -d ' ')"
    if [ "${#held[@]}" -eq 0 ] && [ "${#base_stale[@]}" -eq 0 ]; then
        printf 'seed audit is current at the merge of %s into %s (%s rendered files)\n' \
            "$MERGE_HEAD" "$MERGE_BASE" "$n_rendered"
        exit 0
    fi
    if [ "${#held[@]}" -eq 0 ]; then
        printf 'the merge of %s into %s makes no render stale (%s rendered files)\n' \
            "$MERGE_HEAD" "$MERGE_BASE" "$n_rendered"
        report_base_stale
        exit 0
    fi
    {
        printf 'seed audit would be STALE at the merge of %s into %s:\n' "$MERGE_HEAD" "$MERGE_BASE"
        reasons=()
        for p in "${held[@]}"; do reasons+=("$p ($(why_held "$p"))"); done
        list "${reasons[@]}"
        report_base_stale
        printf 'Bring the head branch current with %s, then:\n' "$MERGE_BASE"
        printf '  assets/scripts/render-seed-audit.sh && git add generated/seed-audit\n'
    } >&2
    exit 1
fi

# ------------------------------------------------------------------ hook install
if [ "$MODE" = "install-hook" ]; then
    top="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null)" || die "not a git repo: $ROOT"
    hookdir="$(git -C "$ROOT" rev-parse --git-common-dir 2>/dev/null)/hooks"
    # Refuse to shadow hooks somebody already installed by hand: core.hooksPath
    # replaces .git/hooks wholesale rather than layering on top of it. A listing
    # that fails refuses too, because a hook it could not see is a hook it could
    # shadow. BSD find has no -printf, so basename names the files.
    existing=""
    if [ -d "$hookdir" ]; then
        existing="$(find "$hookdir" -maxdepth 1 -type f ! -name '*.sample' -exec basename {} \;)" \
            || die "could not list $hookdir, so hand-installed hooks there cannot be ruled out"
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

# Everything past this point renders ROOT, which needs `gc`. --install-hook
# returns above it and needs none. --check-merge returns above it too, because
# it renders each tree with the renderer that tree carries, in a process of its
# own.
command -v gc >/dev/null 2>&1 || die "gc is not on PATH — the render needs the gc binary"

# ------------------------------------------------------------ synthetic city
#
# A fixed basename ("seed-audit-city") because the city name reaches the
# rendered text; a mktemp parent so concurrent runs do not collide. Deliberately
# hand-written rather than produced by `gc init`: init reaches for the beads
# store and, on a host with a live Dolt server, talks to it.
TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/gctk-render-seed-audit.XXXXXX")" || die "mktemp failed"
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

# Every gc call runs through here, and the render has to be hermetic against two
# ambient inputs: the environment and the working directory.
#
# `env -i` handles the environment. It is not tidiness: an inherited GC_CITY
# would point the render at the operator's live city, and inherited
# GC_RIG/GC_AGENT/GC_SESSION_* leak the CALLER's identity into the rendered
# prompt (a polecat running this by hand renders its own agent name and worktree
# path into the artifact).
#
# `cd "$CITY"` handles the working directory, which `env -i` does not scrub. `gc`
# discovers a city by walking up from cwd, and this script runs from whatever
# worktree invoked it, which for every polecat is one nested inside the live
# city. The explicit `--city "$CITY"` is meant to settle which city is in scope,
# but whether an explicit flag beats cwd discovery is the running binary's call,
# and the synthetic city exists precisely so the render depends on nothing
# outside this repo. Running from "$CITY" makes the upward walk resolve the
# synthetic city under either precedence, so scrubbing the environment and
# pinning the cwd are together what make the output depend on the scenario alone.
gcq() {
    ( cd "$CITY" && env -i \
        PATH="$PATH" \
        HOME="$HOME" \
        TERM=dumb \
        NO_COLOR=1 \
        gc --city "$CITY" "$@" )
}

synth_city

# gc names the city by the path it resolves, not the one --city hands it:
# gascity's pathutil.NormalizePathForCompare cleans the path, resolves its
# symlinks, and on darwin collapses the /private/tmp and /private/var host
# aliases back to /tmp and /var. The rig checkout and city.toml paths in the
# render carry that spelling, so the substitution needs it as well as "$CITY".
# The two differ for a TMPDIR that ends in a slash (macOS sets one), for one
# reached through a symlink, and for one spelled under /private.
CITY_GC="$(cd "$CITY" && pwd -P)" || die "could not resolve the synthetic city's path"
if [ "$(uname -s)" = Darwin ]; then
    case "$CITY_GC" in
        /private/tmp/*|/private/var/*) CITY_GC="${CITY_GC#/private}" ;;
    esac
fi
# mktemp's random directory name is in every spelling of the city, so a render
# still carrying it after the substitution leaked one (see render_one).
CITY_TOKEN="$(basename "$TMPROOT")"

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
while IFS= read -r atoml; do
    PACK_AGENTS="${PACK_AGENTS} $(basename "$(dirname "$atoml")")"
done < <(find "$ROOT/agents" "$ROOT/packs" -mindepth 2 -maxdepth 4 -name agent.toml -print 2>/dev/null | LC_ALL=C sort)

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
        "$CITY_GC" "$PH_CITY" \
        "$HOME" "$PH_HOME" \
        < "$raw" > "$dest"
    rm -f "$raw" "$raw.err"
    # A spelling of the city that none of the needles above names would
    # otherwise be written out. That path differs on every run, so --check would
    # call the tree stale straight after the render that wrote it, and a commit
    # would ship it.
    if grep -F -e "$CITY_TOKEN" < "$dest" > /dev/null; then
        printf 'FAILED %s %s (the throwaway city path survived normalization)\n' \
            "$kind" "$name" > "$dest.error"
        grep -F -e "$CITY_TOKEN" < "$dest" | head -3 | sed 's/^/  /' >> "$dest.error"
        return 1
    fi
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
# INDEX.md is committed beside the renders, so each of its lines is a line two
# branches can collide on. It holds what moves only when the pack's composition
# moves: which agents and formulas exist, the scope that resolves each formula,
# and the resolved fragment lists. Sizes print through --sizes instead.
#
# The `gc` version is not recorded either. Prompt composition lives in the
# binary, so an upgrade really can move every byte of the artifact with no
# commit in this repo to explain it, but the version is not a function of the
# repo: recording it drifts with the host binary and drags host state into
# commits that change nothing else. The commit that renders the artifact is the
# record of which `gc` built it.

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
    cat <<'EOF'
# Agent Seed Audit

Generated by `assets/scripts/render-seed-audit.sh`. **Do not hand-edit** — run
the script and commit its output.

Every file under `agents/` is the complete standing prompt one agent receives
at spawn. Every file under `formulas/` is one compiled formula recipe. Together
they are the part of the seed this repo controls.

## Scope

**Mandate.** What text each agent and formula in this pack renders to, as a
committed artifact that moves in reviewable diffs.

**Boundaries.** The pack's own contribution plus the city-level scenario pinned
in the render script. NOT the ~26k-token harness layer (base prompt, tool
schemas, skills appendix, auto-memory index) — that belongs to the Claude Code
build, and `specs/tk-yhwfv.2` probes it separately. NOT rig-scoped agent
patches, which `gc prime` does not honour; the fragment table below is what
covers that dimension.

## Regenerating

    assets/scripts/render-seed-audit.sh

Byte and token counts print on request, with the change since a base revision
when one is named, and are not committed:

    assets/scripts/render-seed-audit.sh --sizes [<base-rev>]

## Agent prompts

EOF

    for a in "${AGENTS[@]}"; do
        printf -- '- [`%s`](agents/%s.md)\n' "$a" "$a"
    done

    cat <<'EOF'

## Formula recipes

`scope` is the narrowest scenario scope that could resolve the recipe. `city`
means every rig sees it; a rig name means only that rig shape imports the pack
carrying it. `gc formula list` answers city-wide and offers all of them at every
scope, but `gc formula show` is scope-strict and reports the rig-only ones as
"not found in search paths" from anywhere else.

| formula | scope |
|---|---|
EOF

    for f in "${FORMULAS[@]}"; do
        sc="city"
        [ -f "$STAGE/formulas/$f.md.scope" ] && sc="$(cat "$STAGE/formulas/$f.md.scope")"
        printf '| [`%s`](formulas/%s.md) | `%s` |\n' "$f" "$f" "$sc"
    done

    cat <<'EOF'

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

# The per-formula scope sidecars were scratch for the table above; the emitted
# tree holds rendered text and INDEX.md.
find "$STAGE" -name '*.scope' -delete

# --------------------------------------------------------------------- sizes
#
# Token counts are bytes/4, the estimator the measurements this artifact was
# built on used (keeper 64,288 B -> 16,072 tok). It is an estimate and the
# table says so; its job is to make a change legible as "+1,400 tokens", not to
# bill anyone.
est_tokens() { printf '%s\n' "$(( $1 / 4 ))"; }
commas() { printf "%s\n" "$1" | sed -e :a -e 's/\(.*[0-9]\)\([0-9]\{3\}\)/\1,\2/;ta'; }
# BSD wc pads its count with leading blanks and GNU wc does not. Arithmetic
# expansion reads either as the bare number, so no padding reaches commas.
bytes_of() { printf '%s\n' "$(( $(wc -c < "$1") ))"; }
signed() { # <n> — grouped, with its sign spelled out and zero left bare
    if [ "$1" -gt 0 ]; then printf '+%s\n' "$(commas "$1")"
    elif [ "$1" -lt 0 ]; then printf -- '-%s\n' "$(commas "${1#-}")"
    else printf '0\n'; fi
}
names_in() { local f; for f in "$1"/*.md; do [ -f "$f" ] && basename "$f" .md; done; }
total_bytes() { local f t=0; for f in "$1"/*.md; do [ -f "$f" ] && t=$((t + $(bytes_of "$f"))); done; printf '%s\n' "$t"; }

# Said on stdout after a render and never committed: a total is a repo-global
# line, the kind that collides two otherwise unrelated pull requests.
report_totals() { # <render>
    local a f
    a="$(total_bytes "$1/agents")"; f="$(total_bytes "$1/formulas")"
    printf '  agents %s B / ~%s tok · formulas %s B / ~%s tok · total %s B / ~%s tok\n' \
        "$(commas "$a")" "$(commas "$(est_tokens "$a")")" \
        "$(commas "$f")" "$(commas "$(est_tokens "$f")")" \
        "$(commas "$((a + f))")" "$(commas "$(est_tokens "$((a + f))")")"
}

# One table for one kind of render. Given a base render too, every row carries
# its change since the base: a name only one side has is marked added or
# removed, and the side that lacks it counts as zero bytes.
size_table() { # <agents|formulas> <column label> <render> [<base render>]
    local cur="$3/$1" base="" n t0=0 t1=0 b0 b1 mark
    [ -n "${4:-}" ] && base="$4/$1"
    if [ -z "$base" ]; then
        printf '| %s | bytes | est. tokens |\n|---|---:|---:|\n' "$2"
    else
        printf '| %s | bytes | est. tokens | Δ bytes | Δ est. tokens |\n|---|---:|---:|---:|---:|\n' "$2"
    fi
    while IFS= read -r n; do
        b1=0; b0=0; mark=""
        [ -f "$cur/$n.md" ] && b1="$(bytes_of "$cur/$n.md")"
        t1=$((t1 + b1))
        if [ -z "$base" ]; then
            printf '| `%s` | %s | %s |\n' "$n" "$(commas "$b1")" "$(commas "$(est_tokens "$b1")")"
            continue
        fi
        if [ -f "$base/$n.md" ]; then b0="$(bytes_of "$base/$n.md")"; else mark=" (added)"; fi
        [ -f "$cur/$n.md" ] || mark=" (removed)"
        t0=$((t0 + b0))
        printf '| `%s`%s | %s | %s | %s | %s |\n' "$n" "$mark" \
            "$(commas "$b1")" "$(commas "$(est_tokens "$b1")")" \
            "$(signed "$((b1 - b0))")" "$(signed "$(( $(est_tokens "$b1") - $(est_tokens "$b0") ))")"
    done < <({ names_in "$cur"; [ -z "$base" ] || names_in "$base"; } | LC_ALL=C sort -u)
    if [ -z "$base" ]; then
        printf '| **total** | %s | %s |\n' "$(commas "$t1")" "$(commas "$(est_tokens "$t1")")"
    else
        printf '| **total** | %s | %s | %s | %s |\n' "$(commas "$t1")" "$(commas "$(est_tokens "$t1")")" \
            "$(signed "$((t1 - t0))")" "$(signed "$(( $(est_tokens "$t1") - $(est_tokens "$t0") ))")"
    fi
}

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
        printf 'seed audit is current (%s agents, %s formulas)\n' "${#AGENTS[@]}" "${#FORMULAS[@]}"
        report_totals "$STAGE"
        exit 0
    fi
    printf 'seed audit is STALE — the committed tree does not match a fresh render:\n' >&2
    sed "s|$STAGE|<fresh>|g; s|$OUT|<committed>|g" < "$TMPROOT/diff.txt" | head -40 >&2
    printf '\nrun: assets/scripts/render-seed-audit.sh && git add generated/seed-audit\n' >&2
    exit 1
fi

if [ "$MODE" = "sizes" ]; then
    base_render=""
    if [ -n "$SIZES_BASE" ]; then
        materialize "$SIZES_BASE" "$TMPROOT/base" || die "--sizes: could not materialize $SIZES_BASE"
        render_tree "$TMPROOT/base" "$TMPROOT/base.render"; rc=$?
        [ "$rc" -eq 0 ] || render_failed "$SIZES_BASE" "$TMPROOT/base.render" "$rc"
        base_render="$TMPROOT/base.render"
    fi
    against="${SIZES_BASE:+, change since $SIZES_BASE}"
    printf '## Agent prompts%s\n\n' "$against"
    size_table agents agent "$STAGE" "$base_render"
    printf '\n## Formula recipes%s\n\n' "$against"
    size_table formulas formula "$STAGE" "$base_render"
    printf '\nToken counts are `bytes / 4`, an estimate.\n'
    exit 0
fi

rm -rf "$OUT"
mkdir -p "$(dirname "$OUT")"
cp -r "$STAGE" "$OUT"
printf 'wrote %s (%s agents, %s formulas)\n' "${OUT#"$ROOT"/}" "${#AGENTS[@]}" "${#FORMULAS[@]}"
report_totals "$OUT"
