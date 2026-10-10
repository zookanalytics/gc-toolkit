#!/usr/bin/env bash
# Tests for the properties generated/seed-audit and its renderer have to hold.
# Two are about the artifact at a merge: --check-merge refuses a merge that lands
# a file it does not render, and the artifact's committed shape lets two
# branches that re-rendered different agents merge at all. Real git: both are
# questions about trees, and stubbing git would leave the merge itself
# unexercised. Two are about sizes: --sizes prints them, against a base revision
# when given one, and nothing commits them. Three are about the renderer: the gcq
# wrapper pins its working directory so the render resolves the synthetic city
# and not one discovered from the cwd it was invoked in, the render is one tree
# however TMPDIR spells the scratch directory, and a byte count reads as the bare
# number whichever wc counted it. Three are refusals: --install-hook will not
# shadow a hand-installed hook, a render fails when an agent the pack owns
# renders the builtin worker prompt, and a render fails when the throwaway
# city's path survives the substitution. Every render runs against a stub `gc`
# on PATH that answers from the files of the pack it is asked about, so a render
# is a function of the tree rendered and no real `gc`, city or network is
# involved; the hermeticity check reads the renderer's text.
#
# Covers, for the merge gate: a head that moves a render input without
# re-rendering, named with its reason; a head that commits the fresh render,
# judged on one render; a base already stale in a file the head leaves alone,
# reported as base's and not held; a hand-edited render; an agent added without
# its render and one removed with its render kept; a head that changes the
# renderer, judged by the renderer it ships, against a control rendered by this
# checkout's; no gc on PATH; a merge result that does not render; a merge result
# carrying no audit, and the stub tree before a first render; the cannot-tell
# exits (unresolvable rev, conflicting merge, missing revs, no scratch dir); and
# the merge shape, against a control carrying the per-agent size rows the index
# no longer commits. For the renderer and sizes: what INDEX.md carries and
# SOURCES.txt's absence; --sizes with and without a base; the gcq wrapper's cwd
# pin; the hook install's refusal, for a hand-installed hook and for a listing
# that fails, against a control holding only a sample hook; the builtin-fallback
# guard, which holds the pack's own agents and not a builtin provider's; a TMPDIR
# spelled with a trailing slash, by its physical path and through a symlink, each
# against the tree a plain one renders; a city spelling no needle names, which
# fails the render; and a wc that pads its count, against the host's.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-render-seed-audit-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# Host signing of commits and tags must not make this suite need a signing agent.
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false \
  GIT_CONFIG_KEY_1=tag.gpgsign GIT_CONFIG_VALUE_1=false
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"   # assertions only; harness_init would stub out git
PASS=0; FAIL=0

SUT="$HERE/render-seed-audit.sh"

# ------------------------------------------------ a gc that renders from files
#
# The render runs every gc call through `env -i` from inside the synthetic city,
# so the stub receives no environment and finds the pack it is asked about the
# way gc does, from the city's own city.toml: the pack this repo imports is the
# first absolute source there. Each answer is then read from that pack's files.
# Every call logs the pack it answered for, which is how a case counts the trees
# one check rendered.
STUB="$TMP/stub-gc"
mkdir -p "$STUB"
BUILTIN_WORKER='You are a worker agent in a Gas City workspace using the graph-first workflow'
cat > "$STUB/gc" <<STUB
#!/usr/bin/env bash
[ "\${1:-}" = --city ] && shift 2
root="\$(sed -n 's|^source = "\(/[^"]*\)"\$|\1|p' city.toml | head -1)"
printf '%s\n' "\$root" >> "$STUB/roots.log"
agents() { local d; for d in "\$root"/agents/*/; do [ -f "\$d/agent.toml" ] && basename "\$d"; done; }
case "\$1 \${2:-}" in
    "config show")  agents | while IFS= read -r a; do printf '[[agent]]\nname = "%s"\n' "\$a"; done ;;
    "agent list")   { agents; echo claude; } | sed 's/.*/{"name":"&"}/' | paste -s -d, - \
                        | sed 's/.*/{"agents":[&]}/' ;;
    "formula list") for f in "\$root"/formulas/*.toml; do [ -f "\$f" ] && basename "\$f" .toml; done ;;
    "formula show") cat "\$root/formulas/\$3.toml" ;;
    "prime claude") printf '%s\n' "$BUILTIN_WORKER" ;;
    "prime "*)      "$STUB/spell-city" < "\$root/agents/\$2/prompt.template.md" ;;
    *)              exit 1 ;;
esac
STUB
chmod +x "$STUB/gc"
# A prompt can name the city the way a real prime does. @@CITY@@ is gc's
# spelling of the path --city was given, which is gascity's
# pathutil.NormalizePathForCompare: cleaned, symlinks resolved, and the darwin
# /private/tmp and /private/var aliases collapsed. @@FOREIGN@@ is a spelling no
# rule derives, the city's own directory names under a root the render never
# saw. gcq runs every call from the city, so the working directory names it.
cat > "$STUB/spell-city" <<'STUB'
#!/usr/bin/env bash
city="$(pwd -P)"
if [ "$(uname -s)" = Darwin ]; then
    case "$city" in /private/tmp/*|/private/var/*) city="${city#/private}" ;; esac
fi
foreign="/elsewhere/$(basename "$(dirname "$city")")/$(basename "$city")"
sed -e "s|@@CITY@@|$city|g" -e "s|@@FOREIGN@@|$foreign|g"
STUB
chmod +x "$STUB/spell-city"

# A PATH with no gc anywhere on it. The directories that hold one are dropped,
# and git and tar keep a link of their own in case they shared one of them.
without_gc() {
    local d out="$TMP/no-gc" IFS=:
    mkdir -p "$TMP/no-gc"
    ln -sf "$(command -v git)" "$TMP/no-gc/git"
    ln -sf "$(command -v tar)" "$TMP/no-gc/tar"
    for d in $PATH; do [ -x "$d/gc" ] || out="$out:$d"; done
    printf '%s\n' "$out"
}

# ---------------------------------------------------------------- the fixture
#
# c0 is the shape a pack has before its first render: sources and the renderer,
# no artifact. `base` renders it, so base is current, and every branch below
# answers base unless it says otherwise.
R="$TMP/repo"
mkdir -p "$R/agents/alpha" "$R/agents/beta" "$R/formulas" "$R/assets/scripts"
cp "$SUT" "$R/assets/scripts/render-seed-audit.sh"
printf 'name = "fixture"\n' > "$R/pack.toml"
for a in alpha beta; do
    printf 'name = "%s"\n' "$a" > "$R/agents/$a/agent.toml"
    printf '# %s doctrine\n' "$a" > "$R/agents/$a/prompt.template.md"
done
printf 'formula = "mol-x"\n' > "$R/formulas/mol-x.toml"
git -C "$R" init -q -b c0
git -C "$R" config user.email test@example.invalid
git -C "$R" config user.name "test"

on() { # <branch> — check out a branch with no residue from the last one
    git -C "$R" checkout -q "$1" && git -C "$R" clean -qfd
}
branch() { on "$1" && git -C "$R" checkout -q -b "$2"; } # <from> <new>
commit() { git -C "$R" add -A && git -C "$R" commit -q --allow-empty -m "$1"; }
# The render a commit would carry, made by the renderer in the tree itself.
render() { PATH="$STUB:$PATH" bash "$R/assets/scripts/render-seed-audit.sh" --jobs 1 >/dev/null 2>&1; }
check_merge() { : > "$STUB/roots.log"; PATH="$STUB:$PATH" bash "$SUT" --root "$R" --check-merge "$1" "$2" 2>&1; }
renders() { LC_ALL=C sort -u "$STUB/roots.log" | grep -c .; } # trees the last check rendered
edit_prompt() { printf '%s\n' "$2" >> "$R/agents/$1/prompt.template.md"; } # <agent> <line>

commit "sources, no audit yet"
git -C "$R" checkout -q -b base
render; commit "render the audit"

# ------------------------------------------------------------- the merge gate
echo "# a head that moves a render input without re-rendering is held"
branch base moved
edit_prompt alpha "moved by the head"
commit "move alpha's prompt, render nothing"
out=$(check_merge base moved); rc=$?
eq "$rc" 1 "the unrendered input exits 1"
has "$out" "would be STALE at the merge of moved into base" "the verdict names both sides"
has "$out" "agents/alpha.md (the merge changes its render but keeps the copy base commits)" \
    "the file whose render moved is named, with why"
hasnt "$out" "agents/beta.md" "…and a file whose render did not move is not"
has "$out" "assets/scripts/render-seed-audit.sh && git add generated/seed-audit" "the remedy is spelled out"

echo "# a head that commits the fresh render is current, on one render"
branch base fresh
edit_prompt alpha "moved and rendered"
render; commit "move alpha's prompt and render it"
out=$(check_merge base fresh); rc=$?
eq "$rc" 0 "a fresh render exits 0"
has "$out" "seed audit is current at the merge of fresh into base" "…and says so"
eq "$(renders)" 1 "…having rendered the merge result alone, since every file matched it"

echo "# a base that is already stale holds no head that leaves the file alone"
branch base stale-base
edit_prompt beta "moved on the base, never rendered"
commit "the base moves beta's prompt without rendering"
branch stale-base bystander
mkdir -p "$R/docs"; printf 'a doc\n' > "$R/docs/d.md"
commit "touch nothing the audit renders"
out=$(check_merge stale-base bystander); rc=$?
eq "$rc" 0 "the base's own staleness does not hold the merge"
has "$out" "the merge of bystander into stale-base makes no render stale" "…which is what the verdict says"
hasnt "$out" "seed audit is current" "…without calling a tree current that is not"
has "$out" "stale-base is already stale in these files" "…and the staleness is reported as the base's"
has "$out" "agents/beta.md" "…naming the stale file"
eq "$(renders)" 2 "…which took a render of the base as well"

echo "# a hand-edited render is held"
branch base hand-edit
printf 'a line no render writes\n' >> "$R/generated/seed-audit/agents/alpha.md"
commit "edit a rendered file by hand"
out=$(check_merge base hand-edit); rc=$?
eq "$rc" 1 "a hand-edited render exits 1"
has "$out" "agents/alpha.md (the merge commits a copy that is neither base's nor its render)" \
    "…naming the file and why"

echo "# agents added and removed are judged by the same rule"
branch base added
mkdir -p "$R/agents/gamma"
printf 'name = "gamma"\n' > "$R/agents/gamma/agent.toml"
printf '# gamma doctrine\n' > "$R/agents/gamma/prompt.template.md"
commit "add an agent, render nothing"
out=$(check_merge base added); rc=$?
eq "$rc" 1 "an agent added without its render exits 1"
has "$out" "agents/gamma.md (rendered, but the merge does not commit it)" "…naming the missing render"
has "$out" "INDEX.md (the merge changes its render" "…and the index that lists it"
branch base removed
git -C "$R" rm -rq agents/beta
commit "remove an agent, keep its render"
out=$(check_merge base removed); rc=$?
eq "$rc" 1 "an agent removed with its render kept exits 1"
has "$out" "agents/beta.md (committed, but nothing renders it)" "…naming the orphaned render"

echo "# a head that changes the renderer is judged by the renderer it ships"
branch base new-renderer
python3 - "$R/assets/scripts/render-seed-audit.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = "# Agent Seed Audit\n"
assert s.count(old) == 1, "fixture patch no longer matches the INDEX.md title"
open(p, "w").write(s.replace(old, "# Agent Seed Audit, as the head renders it\n"))
PY
render; commit "change what the renderer writes, and render with it"
out=$(check_merge base new-renderer); rc=$?
eq "$rc" 0 "a render made by the renderer the head ships is current"
mt=$(git -C "$R" merge-tree --write-tree base new-renderer)
mkdir -p "$TMP/mt" && git -C "$R" archive --format=tar -o "$TMP/mt.tar" "$mt" && tar -x -f "$TMP/mt.tar" -C "$TMP/mt"
PATH="$STUB:$PATH" bash "$SUT" --root "$TMP/mt" --out "$TMP/mt-ours" --jobs 1 >/dev/null 2>&1
if cmp -s "$TMP/mt-ours/INDEX.md" "$TMP/mt/generated/seed-audit/INDEX.md"; then
    bad "control: this checkout's renderer agrees, so the case above proves nothing"
else ok "control: this checkout's renderer renders that tree differently"; fi

echo "# a merge result carrying no audit has nothing to keep current"
out=$(check_merge c0 c0); rc=$?
eq "$rc" 0 "no artifact in the merge result exits 0"
has "$out" "carries no seed audit" "…as a stated fact, not a silent pass"
eq "$(renders)" 0 "…and renders nothing"

echo "# the stub tree a pack carries before its first render is MISSING, not stale"
branch c0 stub
mkdir -p "$R/generated/seed-audit"
printf 'rendered on first install\n' > "$R/generated/seed-audit/README.md"
commit "the pre-render stub"
out=$(check_merge c0 stub); rc=$?
eq "$rc" 0 "a stub carrying no INDEX.md exits 0"
has "$out" "carries no seed audit" "…for the stated reason, not by falling through a file test"

echo "# cannot-tell exits 2 rather than passing"
out=$(PATH="$(without_gc)" "$BASH" "$SUT" --root "$R" --check-merge base fresh 2>&1); rc=$?
eq "$rc" 2 "a host with no gc exits 2"
has "$out" "gc is not on PATH" "…and says why"

branch base unrenderable
mkdir -p "$R/agents/delta"
printf 'name = "delta"\n' > "$R/agents/delta/agent.toml"
commit "an agent with no prompt template, which the render refuses"
out=$(check_merge base unrenderable); rc=$?
eq "$rc" 2 "a merge result that does not render exits 2"
has "$out" "could not render the merge of unrenderable into base" "…naming what did not render"
has "$out" "agents/delta" "…and quoting the render's own reason"

out=$(check_merge base no-such-branch); rc=$?
eq "$rc" 2 "an unresolvable rev exits 2"
has "$out" "names no commit" "…and says which"

branch base conflicting
edit_prompt alpha "a different line where fresh added its own"
render; commit "move the input fresh moved, another way"
out=$(check_merge fresh conflicting); rc=$?
eq "$rc" 2 "a conflicting merge exits 2"
has "$out" "does not merge into" "…rather than reporting on a tree that cannot exist"

out=$(bash "$SUT" --root "$R" --check-merge 2>&1); rc=$?
eq "$rc" 2 "--check-merge without its two revs exits 2"

# Both arms fail closed here; what the guard buys is the diagnosis, so the
# assertion is on the message rather than the exit.
out=$(TMPDIR=/nonexistent-under-test bash "$SUT" --root "$R" --check-merge base fresh 2>&1); rc=$?
eq "$rc" 2 "a scratch dir that cannot be made exits 2"
has "$out" "mktemp failed" "…naming the cause, not the tar failure downstream of it"

# ------------------------------------------------ the shape that has to merge
#
# The gate above is only half of what the artifact owes the merge queue. A line
# that moves on every edit to one agent's prompt, committed beside lines that
# move for every other agent, collides two pull requests that touched two
# unrelated agents. Neighbouring agents are the case that loses: git needs one
# unchanged line between two changes, and adjacent rows leave none.
echo "# two branches that re-render two different agents merge"
two_branches() { # <suffix> <extra-line-writer> — returns 0 when the merge is clean
    local sfx="$1" extra="$2" a
    # The two branches have to MODIFY the extra lines, which means a base that
    # already carries them: two branches that each add them conflict as add/add
    # whatever the lines say.
    branch base "shape-base-$sfx"
    "$extra" "$R"; commit "the shape under test"
    for a in alpha beta; do
        branch "shape-base-$sfx" "edit-$a-$sfx"
        edit_prompt "$a" "moved by edit-$a"
        render; "$extra" "$R"
        commit "move and render $a"
    done
    git -C "$R" merge-tree --write-tree "edit-alpha-$sfx" "edit-beta-$sfx" >/dev/null 2>&1
}
no_extra() { :; }
add_size_rows() { local a; for a in alpha beta; do
    printf '| `%s` | %s |\n' "$a" "$(wc -c < "$1/generated/seed-audit/agents/$a.md" | tr -d ' ')" \
        >> "$1/generated/seed-audit/INDEX.md"; done; }

if two_branches shape no_extra; then ok "neighbouring agents re-rendered on two branches: the merge is clean"
else bad "two re-rendered agents collide — the artifact re-serializes the merge queue"; fi

# The control proves the fixture can fail: the same two branches, with a size
# row per agent added back to the index.
if two_branches control add_size_rows; then
    bad "control: per-agent size rows merged, so the case above proves nothing"
else ok "control: the per-agent size rows these two each moved conflict"; fi

# ------------------------------------------------------- the committed shape
echo "# the index carries composition only, and no manifest is written"
on base
idx="$(cat "$R/generated/seed-audit/INDEX.md")"
has "$idx" '- [`alpha`](agents/alpha.md)' "the index links each agent"
has "$idx" '| [`mol-x`](formulas/mol-x.md) | `city` |' "…and each formula, with its scope"
hasnt "$idx" '| bytes |' "…but carries no byte column"
hasnt "$idx" 'est. tokens' "…no token column"
hasnt "$idx" 'agents: ' "…no count line"
hasnt "$idx" 'SOURCES.txt' "…and names no manifest"
if [ -e "$R/generated/seed-audit/SOURCES.txt" ]; then bad "a render writes SOURCES.txt"
else ok "a render writes no SOURCES.txt"; fi

# ----------------------------------------------------------------- the sizes
echo "# --sizes prints each render's bytes and tokens, and commits nothing"
on fresh
out=$(PATH="$STUB:$PATH" bash "$R/assets/scripts/render-seed-audit.sh" --sizes --jobs 1 2>&1); rc=$?
eq "$rc" 0 "--sizes exits 0"
has "$out" '| `alpha` | 36 | 9 |' "…printing each agent's bytes and estimated tokens"
has "$out" '| `mol-x` | 18 | 4 |' "…and each formula's"
has "$out" '| **total** | 18 | 4 |' "…with the total for each kind"
eq "$(git -C "$R" status --porcelain)" "" "…and leaves the working tree as it was"

echo "# --sizes <rev> prints the change since that revision"
out=$(PATH="$STUB:$PATH" bash "$R/assets/scripts/render-seed-audit.sh" --sizes base --jobs 1 2>&1); rc=$?
eq "$rc" 0 "--sizes <rev> exits 0"
has "$out" 'change since base' "…naming the revision"
has "$out" '| `alpha` | 36 | 9 | +19 | +5 |' "…with the change on the row that moved"
has "$out" '| `beta` | 16 | 4 | 0 | 0 |' "…and none on the row that did not"
on added
out=$(PATH="$STUB:$PATH" bash "$R/assets/scripts/render-seed-audit.sh" --sizes base --jobs 1 2>&1); rc=$?
has "$out" '| `gamma` (added) | 17 | 4 | +17 | +4 |' "an agent the base lacks is marked added"
on removed
out=$(PATH="$STUB:$PATH" bash "$R/assets/scripts/render-seed-audit.sh" --sizes base --jobs 1 2>&1); rc=$?
has "$out" '| `beta` (removed) | 0 | 0 | -16 | -4 |' "…and one the head lacks, removed"
out=$(PATH="$STUB:$PATH" bash "$R/assets/scripts/render-seed-audit.sh" --sizes no-such-rev 2>&1); rc=$?
eq "$rc" 2 "--sizes against a revision that names nothing exits 2"
has "$out" "names no commit" "…and says so"

# ------------------------------------------------ the renderer's cwd hermeticity
#
# gcq is the one chokepoint every gc call passes through. `env -i` scrubs the
# environment but not the working directory, and `gc` discovers a city by walking
# up from cwd, so a render invoked from a worktree nested inside the live city
# could resolve that city rather than the synthetic one. The wrapper pins cwd to
# the synthetic city to close that path. This reads the wrapper's text rather than
# rendering: proving the behavior needs a gc binary and a city this suite does
# without, and a dropped pin is a text change the read catches.
echo "# gcq pins cwd so the render cannot inherit a city from the caller's cwd"
gcq_body="$(sed -n '/^gcq() {/,/^}/p' "$SUT")"
has "$gcq_body" 'cd "$CITY"' "gcq runs gc from the synthetic city, not the invoking cwd"
has "$gcq_body" 'env -i' "gcq still scrubs the environment"
has "$gcq_body" 'gc --city "$CITY"' "gcq still names the synthetic city explicitly"

# ------------------------------------------------ the hook install's refusal
#
# core.hooksPath replaces .git/hooks rather than layering onto it, so the install
# refuses while a hand-installed hook sits there. The listing that finds one has
# to work under BSD find as well as GNU find: a listing that comes back empty
# reads as "no hooks" and shadows the hook it was meant to protect. Run from the
# repo root, the way the install is run.
echo "# --install-hook refuses to shadow a hand-installed hook"
H="$TMP/hooked"
mkdir -p "$H"
printf 'name = "fixture"\n' > "$H/pack.toml"
git -C "$H" init -q
mkdir -p "$H/.git/hooks"
printf '#!/bin/sh\n' > "$H/.git/hooks/pre-commit.sample"
printf '#!/bin/sh\nexit 0\n' > "$H/.git/hooks/pre-push"
chmod +x "$H/.git/hooks/pre-push"
out=$(cd "$H" && bash "$SUT" --root "$H" --install-hook 2>&1); rc=$?
eq "$rc" 2 "a hand-installed hook refuses the install"
has "$out" "pre-push" "…and the refusal names it"
hasnt "$out" "pre-commit.sample" "…but not a sample git ships"
eq "$(git -C "$H" config --get core.hooksPath)" "" "…and core.hooksPath is left unset"
rm "$H/.git/hooks/pre-push"
# A find that fails stands in for any listing that cannot see the directory.
mkdir -p "$TMP/failing-find"
printf '#!/bin/sh\necho "find: listing refused" >&2\nexit 1\n' > "$TMP/failing-find/find"
chmod +x "$TMP/failing-find/find"
out=$(cd "$H" && PATH="$TMP/failing-find:$PATH" bash "$SUT" --root "$H" --install-hook 2>&1); rc=$?
eq "$rc" 2 "a hook listing that fails refuses the install"
has "$out" "hand-installed hooks there cannot be ruled out" "…and says why"
eq "$(git -C "$H" config --get core.hooksPath)" "" "…and core.hooksPath is still unset"
out=$(cd "$H" && bash "$SUT" --root "$H" --install-hook 2>&1); rc=$?
eq "$rc" 0 "control: with only a sample hook left, the install proceeds"
eq "$(git -C "$H" config --get core.hooksPath)" "assets/hooks" "…and points core.hooksPath at assets/hooks"

# ------------------------------------------------ the builtin-fallback guard
#
# An agent this pack owns that renders the builtin worker prompt fails the render,
# while a builtin-provider agent may render it. Which agents the pack owns comes
# from its agent.toml files, and that list has to come out the same under BSD and
# GNU find: an empty list holds no agent to the rule.
echo "# a pack agent that renders the builtin worker prompt fails the render"
P="$TMP/render-pack"
mkdir -p "$P/agents/alpha" "$P/formulas"
printf 'name = "fixture"\n' > "$P/pack.toml"
printf 'name = "alpha"\n' > "$P/agents/alpha/agent.toml"
printf 'formula = "mol-fixture"\n' > "$P/formulas/mol-fixture.toml"
render_stub() { PATH="$STUB:$PATH" bash "$SUT" --root "$P" --out "$TMP/render-out" --jobs 1 2>&1; }

printf '# alpha doctrine\n' > "$P/agents/alpha/prompt.template.md"
out=$(render_stub); rc=$?
eq "$rc" 0 "control: the pack agent renders its own doctrine and the builtin claude its builtin prompt"
printf '%s\n' "$BUILTIN_WORKER" > "$P/agents/alpha/prompt.template.md"
out=$(render_stub); rc=$?
eq "$rc" 2 "the pack agent rendering the builtin worker prompt fails the render"
has "$out" "FAILED agent alpha (rendered a builtin fallback prompt" "…and names the agent and the reason"
hasnt "$out" "FAILED agent claude" "…while claude, which the pack does not own, still passes"

# ------------------------------------------------ the throwaway city's spellings
#
# The city is built under TMPDIR, and gc prints it under the path it resolves
# rather than the one it was handed. A TMPDIR ending in a slash (macOS sets one),
# one spelled by its physical path (/private/var on macOS), and one reached
# through a symlink must each render the tree a plain TMPDIR renders. Otherwise
# the random scratch path lands in the render, and --check calls the tree stale
# straight after the render that wrote it.
echo "# the city's path is substituted however TMPDIR spells it"
D="$(cd "$TMP" && pwd)/scratch"
mkdir -p "$D"
ln -s "$D" "$TMP/scratch-link"
render_under() { # <TMPDIR> <out>
    TMPDIR="$1" PATH="$STUB:$PATH" bash "$SUT" --root "$P" --out "$2" --jobs 1 2>&1
}
printf '# alpha doctrine\ncity: @@CITY@@/city.toml\n' > "$P/agents/alpha/prompt.template.md"
out=$(render_under "$D" "$TMP/city-plain"); rc=$?
eq "$rc" 0 "control: a render under a plain TMPDIR succeeds"
has "$(cat "$TMP/city-plain/agents/alpha.md" 2>/dev/null)" "city: [[CITY-ROOT]]/city.toml" \
    "…and substitutes the city's path"
for spelling in "a trailing slash|$D/" "its physical path|$(cd "$D" && pwd -P)" \
        "a symlink|$TMP/scratch-link"; do
    out=$(render_under "${spelling#*|}" "$TMP/city-other"); rc=$?
    eq "$rc" 0 "a TMPDIR spelled with ${spelling%%|*} renders"
    if diff -r "$TMP/city-plain" "$TMP/city-other" > /dev/null 2>&1; then
        ok "…the same tree as the plain TMPDIR"
    else
        bad "…a tree that differs from the plain TMPDIR's: $(diff -r "$TMP/city-plain" "$TMP/city-other" 2>&1 | head -4)"
    fi
    rm -rf "$TMP/city-other"
done

echo "# a spelling of the city that no needle names fails the render"
printf '# alpha doctrine\ncity: @@FOREIGN@@/city.toml\n' > "$P/agents/alpha/prompt.template.md"
out=$(render_under "$D" "$TMP/city-foreign"); rc=$?
eq "$rc" 2 "a city path that survives the substitution fails the render"
has "$out" "FAILED agent alpha (the throwaway city path survived normalization)" "…naming the agent"
has "$out" "city: /elsewhere/" "…and quoting the line that carries the path"
if [ -e "$TMP/city-foreign" ]; then bad "…but it wrote a tree anyway"; else ok "…and writes no tree"; fi

# ------------------------------------------------ a byte count, however wc pads it
#
# BSD wc pads its count with leading blanks and GNU wc prints it bare. The
# stand-in pads on either host, so the case exercises the BSD shape under GNU
# too, and the row assertion holds on a host whose own wc pads.
echo "# a padded wc count reaches the sizes table as the bare number"
mkdir -p "$TMP/padding-wc"
cat > "$TMP/padding-wc/wc" <<STUB
#!/usr/bin/env bash
printf '%8s\n' "\$("$(command -v wc)" "\$@" | tr -d ' ')"
STUB
chmod +x "$TMP/padding-wc/wc"
printf '# alpha doctrine\n' > "$P/agents/alpha/prompt.template.md"
host=$(TMPDIR="$D" PATH="$STUB:$PATH" bash "$SUT" --root "$P" --sizes --jobs 1 2>&1); rc=$?
eq "$rc" 0 "control: --sizes with the host's wc succeeds"
padded=$(TMPDIR="$D" PATH="$TMP/padding-wc:$STUB:$PATH" bash "$SUT" --root "$P" --sizes --jobs 1 2>&1); rc=$?
eq "$rc" 0 "--sizes with a padding wc succeeds"
has "$padded" '| `alpha` | 17 | 4 |' "…and its row carries the bare byte count"
eq "$padded" "$host" "…the same table as the host's wc prints"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
