#!/usr/bin/env bash
# skill-needs.test.sh — a pack skill's description is all an agent has to decide
# whether to load the skill. Every agent in the pack receives every pack skill
# at session start, and only the name and description are in its context until
# it loads one. So a description has to carry the words an agent has in mind at
# the moment it feels the need.
#
# Each row of NEEDS is a need an agent wrote in its own words, just before it
# went searching script source, docs and memory for how to act, paired with the
# skill that answers it. Bead ids in a need are elided as <bead>.
# specs/tk-fqw7x2b/hunts.md records where each one was found and what the agent
# did next. The test scores every pack skill's name
# and description against each need and fails unless the expected skill scores
# highest.
#
# The score counts the words a need shares with a description, after common
# words are dropped and word endings stripped, and weights each word by how few
# descriptions carry it, so a word most descriptions use decides little. It is
# a floor, not a model of the agent: a description that fails it lacks the words
# a real need used, and one that passes still has to read well. A description
# that carries more than the load decision fails on its own: over the character
# limit, with a contents list opening on "Covers", or with a step number.
#
# The same file pins the skills' shape: each names its neighbors, keeps
# converse's vocabulary out of its description, and calls every writer as the
# pack's own copy through the pack command `gc <binding> scripts-dir`, leaving
# the agent to fill in the binding the city imports the pack under, so no pack
# skill names one. It pins that command and checks it against the real gc
# under a renamed import. It pins that the converse steps and the mechanik give
# the exact command for each act they name while the skills explain the act
# once, with one fragment pointing both prompts at the skills. It pins how the
# prompt's hand-back definition has a framing name its subject, and that the
# hold skill points at it. It pins that the
# dispatch fragment the mechanik and the keeper compose calls deferred-dispatch.sh
# and gc-bd-watch.sh the work skill's way, so both renders reach the pack's own
# copies. It pins the prs
# skill's supplement command: filed in the PR's rig, holding the anchor's merge,
# and slung only once that hold reads back, with the mechanik's copy the same
# command. It pins that a formula's own description, not a doc, says which work
# the formula fits. It runs each example whose second step depends on its first
# under a gc that refuses the first step, and fails if anything after it runs.
# It runs the settle step's arm under a gc that answers a dep add as bd does for
# a blocker in another store, and fails if the arm runs. It pins that every
# skill and formula names a pack skill to load by its catalog name, never by
# its path, so an agent in any tree loads the installed pack's copy. It pins that
# a problem in software the rig does not own goes through the external-issue
# skill, which alone holds that path's commands.
#
# Hermetic: reads the repo, and runs the pack command and the writer call shape
# in a temporary directory outside any git repo, with a stub gc. The one case
# that runs the real gc, the one GC_BIN names, points it at a scratch city that
# is never started, where gc reads the config, lists skills and runs the pack
# command. With no GC_BIN, as in CI, that case prints SKIP.
#
# run-tests-scope: tree

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/../.."
SKILLS="$REPO/skills"
PROMPT="$REPO/agents/_converse/prompt.template.md"
SETTLE="$REPO/skills/converse-settle/SKILL.md"
MECHANIK="$REPO/agents/mechanik/prompt.template.md"
WORK_SKILL="$REPO/skills/work/SKILL.md"
PRS_SKILL="$REPO/skills/prs/SKILL.md"
DESIGN_DOC="$REPO/docs/design-convoy.md"
DESIGN_FORMULA="$REPO/formulas/mol-design-convoy.toml"
BLOCKS="work waits records prs"

PASS=0
FAIL=0
ok() {
    PASS=$((PASS + 1))
    printf '  ok    %s\n' "$1"
}
bad() {
    FAIL=$((FAIL + 1))
    if [ -n "${2:-}" ]; then
        printf '  FAIL  %s\n        %s\n' "$1" "$2"
    else
        printf '  FAIL  %s\n' "$1"
    fi
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-skill-needs-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# frontmatter <file> <key> — one key's value from a SKILL.md's frontmatter.
frontmatter() {
    awk -v k="$2" '
        NR == 1 && $0 != "---" { exit }
        NR > 1 && $0 == "---" { exit }
        NR > 1 && index($0, k ":") == 1 { v = substr($0, length(k) + 2); sub(/^[ \t]+/, "", v); print v; exit }
    ' "$1"
}

# The corpus: one line per pack skill, "<dir>\t<name> <description>", the text
# an agent's session lists for it.
: >"$TMP/corpus"
for f in "$SKILLS"/*/SKILL.md; do
    [ -r "$f" ] || continue
    d=$(basename "$(dirname "$f")")
    printf '%s\t%s %s\n' "$d" "$(frontmatter "$f" name)" "$(frontmatter "$f" description)" >>"$TMP/corpus"
done

echo "── each building-block skill is a well-formed pack skill ──"
for s in $BLOCKS; do
    f="$SKILLS/$s/SKILL.md"
    if [ ! -r "$f" ]; then
        bad "$s: skills/$s/SKILL.md exists" "missing $f"
        continue
    fi
    name=$(frontmatter "$f" name)
    desc=$(frontmatter "$f" description)
    compat=$(frontmatter "$f" compatibility)
    [ "$name" = "$s" ] && ok "$s: name equals its directory" || bad "$s: name equals its directory" "got '$name'"
    [ -n "$desc" ] && ok "$s: has a description" || bad "$s: has a description"
    [ -n "$compat" ] && ok "$s: declares its compatibility" || bad "$s: declares its compatibility"
    # Every agent reads these descriptions, so they speak in the words any role
    # uses, and say which neighbor to load instead.
    lower=$(printf '%s' "$desc" | tr '[:upper:]' '[:lower:]')
    case "$lower" in
        *sitting* | *converse* | *ruling*) bad "$s: description keeps converse's vocabulary out" "$desc" ;;
        *) ok "$s: description keeps converse's vocabulary out" ;;
    esac
    named=""
    for n in $BLOCKS; do
        [ "$n" = "$s" ] && continue
        case "$lower" in *"use $n"*) named="$named $n" ;; esac
    done
    [ -n "$named" ] && ok "$s: description names a neighbor to use instead ($named )" \
        || bad "$s: description names a neighbor to use instead" "no 'use <work|waits|records|prs>' in: $desc"
done

echo "── every description carries only what decides whether to load the skill ──"
# Every agent holds every description in context in every session, so a
# description says when to load the skill and the body carries the rest
# (docs/skills.md, Frontmatter). The needs below hold a description to the words
# a real need used. These checks hold back what no need asks for: a list of the
# skill's contents, and a step number that goes stale when the steps move. The
# limit sits a little above the longest description the needs justify, because
# the cost is the length, however the text is worded.
DESCRIPTION_LIMIT=650
for f in "$SKILLS"/*/SKILL.md; do
    [ -r "$f" ] || continue
    s=$(basename "$(dirname "$f")")
    desc=$(frontmatter "$f" description)
    [ "${#desc}" -le "$DESCRIPTION_LIMIT" ] && ok "$s: description fits the $DESCRIPTION_LIMIT-character limit" \
        || bad "$s: description fits the $DESCRIPTION_LIMIT-character limit" "${#desc} characters; what goes beyond the load decision belongs in the body"
    case "$desc" in
        Covers\ * | *". Covers "*) bad "$s: description lists no contents" "$desc" ;;
        *) ok "$s: description lists no contents" ;;
    esac
    case "$(printf '%s' "$desc" | tr '[:upper:]' '[:lower:]')" in
        *"step "[0-9]* | *"steps "[0-9]*) bad "$s: description carries no step number" "$desc" ;;
        *) ok "$s: description carries no step number" ;;
    esac
done

echo "── each building-block skill calls the pack's own writers, never a checkout's ──"
# A skill's writers are the pack's own scripts. The pack command
# commands/scripts-dir prints their directory from GC_PACK_DIR, which gc sets
# to the pack it loaded, so an example calls "$(gc <binding> scripts-dir)/<writer>"
# inside the one command that runs it. gc registers the command under the
# binding the city imports the pack as, which a skill's text cannot know, so
# the call leaves <binding> for the agent and the skill says where to read it.
# Nothing looks in the rig checkout or the caller's git toplevel, which can be a
# branch's worktree, and nothing relies on a variable an earlier tool call set,
# since each call starts a fresh shell.
ROOT="$(cd "$REPO" && pwd)"
RESOLVE='"$(gc <binding> scripts-dir)/'
for s in $BLOCKS external-issue; do
    f="$SKILLS/$s/SKILL.md"
    [ -r "$f" ] || continue
    found=""
    for probe in 'GC_RIG_ROOT' 'rev-parse --show-toplevel' 'CONV' '"$S/' 'GC_CITY_PATH/rigs'; do
        grep -qF -- "$probe" "$f" && found="$found [$probe]"
    done
    [ -z "$found" ] && ok "$s: looks for no writer in a checkout or a variable an earlier call set" \
        || bad "$s: looks for no writer in a checkout or a variable an earlier call set" "found:$found"
    refs=$(grep -oF -- "$RESOLVE" "$f" | wc -l | tr -d ' ')
    writers=$(grep -oE '"\$\(gc <binding> scripts-dir\)/[A-Za-z0-9._-]+"' "$f" | sed 's#.*/##; s#"$##' | sort -u)
    [ "${refs:-0}" -gt 0 ] && ok "$s: calls its writers through gc <binding> scripts-dir (calls: $refs)" \
        || bad "$s: calls its writers through gc <binding> scripts-dir" "no $RESOLVE<writer>\" call found"
    tr '\n' ' ' <"$f" >"$TMP/joined-$s"
    if grep -qF "\`gc-toolkit\` in \`gc-toolkit.$s\`" "$TMP/joined-$s" \
        && grep -qF "\`gc skill list\` prints it in this skill's FROM column" "$TMP/joined-$s"; then
        ok "$s: says where the agent reads the binding: this skill's name, and gc skill list's FROM"
    else
        bad "$s: says where the agent reads the binding" "no \`gc-toolkit\` in \`gc-toolkit.$s\` with gc skill list's FROM column"
    fi
    stray=$(grep -oE '"\$(\{[^}]*\}|[A-Za-z_][A-Za-z_0-9]*)/[A-Za-z0-9._-]+' "$f" | sort -u | tr '\n' ' ')
    [ -z "$stray" ] && ok "$s: every writer an example calls goes through the pack command" \
        || bad "$s: every writer an example calls goes through the pack command" "stray: $stray"
    missing=""
    for w in $writers; do
        [ -x "$ROOT/assets/scripts/$w" ] || missing="$missing $w"
    done
    [ -n "$writers" ] && [ -z "$missing" ] && ok "$s: every writer an example calls is an executable in assets/scripts" \
        || bad "$s: every writer an example calls is an executable in assets/scripts" "missing:${missing:- none named}"
done
# gc answers `gc gc-toolkit <command>` only in a city that imports the pack as
# gc-toolkit, so no pack skill writes that binding into a command.
bound=$(grep -lE 'gc gc-toolkit [a-z]' "$SKILLS"/*/SKILL.md 2>/dev/null | sed "s#^$SKILLS/##" | tr '\n' ' ')
[ -z "$bound" ] && ok "no pack skill writes a binding into a gc command" \
    || bad "no pack skill writes a binding into a gc command" "found in: $bound"

echo "── a skill or formula names a pack skill to load by its catalog name, never its path ──"
# An agent's skill catalog links each pack skill, under its catalog name
# gc-toolkit.<name>, into the installed pack. A path to the skill,
# skills/<name>/SKILL.md or skills/<name>, resolves against whatever tree the
# agent stands in: in another rig it names nothing, and in a gc-toolkit
# worktree it opens that tree's copy, such as a branch under review. A path
# that goes on into a skill's directory names a file there, not the skill.
#
# A path that names a file to edit stays a path. The feedback distiller's
# formula and its rubric name the skills its proposals change, which the
# polecat that builds a proposal edits in its own checkout, and the formula
# reads the rubric from origin/main as a git object. EDIT_TARGETS holds each of
# those files with each skill it names that way, and nothing else is exempt.
EDIT_TARGETS="formulas/mol-feedback-distiller.toml:learning-distill
formulas/mol-feedback-distiller.toml:review-correctness
skills/learning-distill/SKILL.md:learning-distill
skills/learning-distill/SKILL.md:review-correctness"
# skill_paths <root> — each path to a pack skill in the text of <root>'s skills
# and formulas, as "<file>:<line>: <path>", leaving out EDIT_TARGETS.
skill_paths() {
    (
        cd "$1" || exit 1
        names=""
        for f in skills/*/SKILL.md; do
            [ -r "$f" ] && names="$names $(basename "$(dirname "$f")")"
        done
        files=()
        while IFS= read -r f; do files+=("$f"); done < <(
            { find skills -type f; ls formulas/*.toml 2>/dev/null; } | LC_ALL=C sort
        )
        [ "${#files[@]}" -gt 0 ] || exit 0
        LC_ALL=C awk -v names="$names" -v targets="$(printf '%s' "$EDIT_TARGETS" | tr '\n' ' ')" '
            BEGIN {
                n = split(names, a, " ")
                for (i = 1; i <= n; i++) skill[a[i]] = 1
                n = split(targets, a, " ")
                for (i = 1; i <= n; i++) { split(a[i], p, ":"); target[p[1], p[2]] = 1 }
            }
            {
                rest = $0 " "
                while (match(rest, /skills\/[a-z0-9][a-z0-9-]*/)) {
                    name = substr(rest, RSTART + 7, RLENGTH - 7)
                    rest = substr(rest, RSTART + RLENGTH)
                    path = ""
                    if (rest ~ /^\/SKILL\.md/) path = "skills/" name "/SKILL.md"
                    else if (rest !~ /^\/?([A-Za-z0-9_-]|\.[A-Za-z0-9])/) path = "skills/" name
                    if (path != "" && (name in skill) && !((FILENAME, name) in target))
                        printf "%s:%d: %s\n", FILENAME, FNR, path
                }
            }
        ' "${files[@]}"
    )
}
hits=$(skill_paths "$ROOT")
if [ -z "$hits" ]; then
    ok "no pack skill or formula names a pack skill to load by its path"
else
    bad "no pack skill or formula names a pack skill to load by its path" \
        "name each one gc-toolkit.<name>; a file a proposal edits is an EDIT_TARGETS entry:"
    printf '%s\n' "$hits" | sed 's/^/          /'
fi
FX="$TMP/skill-paths"
mkdir -p "$FX/formulas" "$FX/skills/a" "$FX/skills/b" "$FX/skills/learning-distill" "$FX/skills/review-correctness"
: >"$FX/skills/b/SKILL.md"
: >"$FX/skills/review-correctness/SKILL.md"
cat >"$FX/skills/a/SKILL.md" <<'MD'
Write the script by following `skills/b/SKILL.md`.
Deliver it the way the method in skills/b says.
Load `gc-toolkit.b` before you judge.
Its anchor goes in skills/b/ledger.md, and a check's method in skills/review-<check>/.
MD
cat >"$FX/formulas/mol-x.toml" <<'TOML'
description = "A bead whose work becomes the script, generated by following skills/b/SKILL.md."
TOML
cat >"$FX/formulas/mol-feedback-distiller.toml" <<'TOML'
RUBRIC_PATH="skills/learning-distill/SKILL.md"
- review-rubric -> skills/review-correctness/SKILL.md, What to check
Write each proposal the way skills/b/SKILL.md says.
TOML
cat >"$FX/skills/learning-distill/SKILL.md" <<'MD'
or a change to the correctness method itself (`skills/review-correctness/SKILL.md`)
a proposal against `skills/learning-distill/SKILL.md` rides the same pipeline
MD
got=$(skill_paths "$FX")
hit() { printf '%s\n' "$got" | grep -qxF -- "$1"; }
seen="got: $(printf '%s' "$got" | tr '\n' ';')"
hit 'skills/a/SKILL.md:1: skills/b/SKILL.md' && hit 'skills/a/SKILL.md:2: skills/b' \
    && ok "a skill that names a pack skill by its path fails, as skills/<name>/SKILL.md and as skills/<name>" \
    || bad "a skill that names a pack skill by its path fails, as skills/<name>/SKILL.md and as skills/<name>" "$seen"
hit 'formulas/mol-x.toml:1: skills/b/SKILL.md' && ok "a formula that names a pack skill by its path fails" \
    || bad "a formula that names a pack skill by its path fails" "$seen"
! printf '%s\n' "$got" | grep -qE '^(skills/learning-distill/SKILL\.md|formulas/mol-feedback-distiller\.toml:[12]):' \
    && hit 'formulas/mol-feedback-distiller.toml:3: skills/b/SKILL.md' \
    && ok "the distiller's edit targets pass, and its path to a skill it does not edit fails" \
    || bad "the distiller's edit targets pass, and its path to a skill it does not edit fails" "$seen"
! printf '%s\n' "$got" | grep -qE '^skills/a/SKILL\.md:[34]:' \
    && ok "a catalog name, a file in a skill's directory and a path to no pack skill pass" \
    || bad "a catalog name, a file in a skill's directory and a path to no pack skill pass" "$seen"

echo "── gc <binding> scripts-dir prints the scripts of the pack gc loaded ──"
CMD="$ROOT/commands/scripts-dir/run.sh"
[ -x "$CMD" ] && ok "commands/scripts-dir/run.sh is an executable pack command" \
    || bad "commands/scripts-dir/run.sh is an executable pack command" "missing or not executable: $CMD"
mkdir -p "$TMP/away" "$TMP/no-scripts"
got=$(cd "$TMP/away" && env -u GC_PACK_DIR GC_PACK_DIR="$ROOT" "$CMD" 2>/dev/null)
[ "$got" = "$ROOT/assets/scripts" ] && ok "it prints GC_PACK_DIR's assets/scripts" \
    || bad "it prints GC_PACK_DIR's assets/scripts" "printed '$got'"
if got=$(cd "$TMP/away" && env -u GC_PACK_DIR "$CMD" 2>/dev/null); then
    bad "with GC_PACK_DIR unset it fails" "exited 0 and printed '$got'"
else
    [ -z "$got" ] && ok "with GC_PACK_DIR unset it fails and prints nothing" \
        || bad "with GC_PACK_DIR unset it fails and prints nothing" "printed '$got'"
fi
if got=$(cd "$TMP/away" && env GC_PACK_DIR="$TMP/no-scripts" "$CMD" 2>/dev/null); then
    bad "with no assets/scripts under GC_PACK_DIR it fails" "exited 0 and printed '$got'"
else
    ok "with no assets/scripts under GC_PACK_DIR it fails"
fi
# gc registers a pack command under the binding the city imports the pack as,
# and under no other name, and runs it with GC_PACK_DIR set to the pack's root
# and the caller's arguments. The stub gc below does the same for a city that
# imports the pack as kit. The skills' call shape with that binding filled in
# then holds in a fresh bash and zsh, and the same call naming gc-toolkit fails,
# because its writer path names no file.
mkdir -p "$TMP/stub"
cat >"$TMP/stub/gc" <<STUB
#!/usr/bin/env bash
[ "\$1 \$2" = "kit scripts-dir" ] || { echo "gc: unknown command \\"\$1\\"" >&2; exit 1; }
GC_PACK_DIR="$ROOT" exec "$CMD"
STUB
chmod +x "$TMP/stub/gc"
# call_files <binding> — the skills' call shape with <binding> filled in: one
# file prints the path the call resolves, and one runs the writer there.
call_files() {
    printf 'printf "%%s" %sgc-helm.sh"\n' "${RESOLVE/<binding>/$1}" >"$TMP/call-path-$1"
    printf '%sgc-helm.sh" --help >/dev/null 2>&1\n' "${RESOLVE/<binding>/$1}" >"$TMP/call-writer-$1"
}
call_files kit
call_files gc-toolkit
# phys <path> — <path> with every symlink in its directory resolved.
phys() { (cd "$(dirname "$1")" 2>/dev/null && printf '%s/%s' "$(pwd -P)" "$(basename "$1")"); }
WANT="$(phys "$ROOT/assets/scripts/gc-helm.sh")"
shells="bash"
command -v zsh >/dev/null 2>&1 && shells="bash zsh"
for sh_ in $shells; do
    run=$sh_
    [ "$sh_" = zsh ] && run="zsh -f"
    got=$(cd "$TMP/away" && env -u GC_PACK_DIR -u BASH_ENV -u ENV PATH="$TMP/stub:$PATH" $run "$TMP/call-path-kit" 2>/dev/null)
    [ "$got" = "$ROOT/assets/scripts/gc-helm.sh" ] && ok "($sh_) the call with the city's binding resolves to the pack's own writer" \
        || bad "($sh_) the call with the city's binding resolves to the pack's own writer" "resolved '$got'"
    if (cd "$TMP/away" && env -u GC_PACK_DIR -u BASH_ENV -u ENV PATH="$TMP/stub:$PATH" $run "$TMP/call-writer-kit") 2>/dev/null; then
        ok "($sh_) …and the writer there runs"
    else
        bad "($sh_) …and the writer there runs" "gc-helm.sh --help through the call failed"
    fi
    if [ -e /gc-helm.sh ]; then
        bad "($sh_) the same call naming gc-toolkit fails" "/gc-helm.sh exists on this host, so the case cannot tell"
    elif (cd "$TMP/away" && env -u GC_PACK_DIR -u BASH_ENV -u ENV PATH="$TMP/stub:$PATH" $run "$TMP/call-writer-gc-toolkit") 2>/dev/null; then
        bad "($sh_) the same call naming gc-toolkit fails" "it exited 0"
    else
        ok "($sh_) the same call naming gc-toolkit fails"
    fi
done

echo "── under a renamed import, the real gc answers the binding the skill names ──"
# The stub above stands in for gc's registration; this case runs gc itself. A
# city that imports the pack as [imports.kit] lists the work skill as kit.work
# with kit as its FROM, answers gc kit scripts-dir with this pack's scripts, and
# has no gc gc-toolkit command at all. The scratch city is never started: gc
# reads its config, lists its skills and runs the pack command, with GC_CITY
# naming it and nothing in the environment naming a live city, rig or store.
if [ -z "${GC_BIN:-}" ] || [ ! -x "${GC_BIN:-}" ]; then
    printf '  SKIP  GC_BIN names no gc, so the renamed import was not checked against the real gc (set GC_BIN to run it)\n'
else
    CITY="$TMP/city-kit"
    mkdir -p "$CITY" "$TMP/real-gc" "$TMP/gc-home"
    ln -s "$GC_BIN" "$TMP/real-gc/gc"
    printf '[workspace]\nprovider = "claude"\n\n[providers.claude]\nbase = "builtin:claude"\n\n[providers.codex]\nbase = "builtin:codex"\n\n[providers.gemini]\nbase = "builtin:gemini"\n' >"$CITY/city.toml"
    printf '[pack]\nname = "skill-needs-probe"\nschema = 2\n\n[imports.kit]\nsource = "%s"\n' "$ROOT" >"$CITY/pack.toml"
    # in_city <command...> — run in the scratch city, with the real gc first on PATH.
    in_city() {
        (cd "$CITY" && env -u GC_CITY_PATH -u GC_RIG -u GC_RIG_ROOT -u GC_DIR -u GC_PACK_DIR \
            -u BEADS_DIR -u GC_BEADS_SCOPE_ROOT -u GC_DOLT_PORT -u BEADS_DOLT_SERVER_PORT -u BASH_ENV -u ENV \
            GC_CITY="$CITY" GC_HOME="$TMP/gc-home" PATH="$TMP/real-gc:$PATH" "$@")
    }
    binding=$(in_city gc skill list --json 2>/dev/null \
        | jq -r '[.entries[]? | select((.path // "") | endswith("/skills/work/SKILL.md")) | .source] | unique | join(" ")')
    [ "$binding" = kit ] && ok "gc lists the work skill with FROM kit, the binding the city imports the pack as" \
        || bad "gc lists the work skill with FROM kit, the binding the city imports the pack as" "FROM '$binding'"
    for sh_ in $shells; do
        run=$sh_
        [ "$sh_" = zsh ] && run="zsh -f"
        got=$(in_city $run "$TMP/call-path-kit" 2>/dev/null)
        [ -n "$got" ] && [ "$(phys "$got")" = "$WANT" ] && ok "($sh_) with kit filled in, the real gc resolves the call to the pack's own writer" \
            || bad "($sh_) with kit filled in, the real gc resolves the call to the pack's own writer" "resolved '$got'"
        if in_city $run "$TMP/call-writer-kit" 2>/dev/null; then
            ok "($sh_) …and the writer there runs"
        else
            bad "($sh_) …and the writer there runs" "gc-helm.sh --help through the call failed"
        fi
    done
    if in_city gc gc-toolkit scripts-dir >/dev/null 2>&1; then
        bad "the real gc has no gc gc-toolkit scripts-dir under [imports.kit]" "it exited 0"
    else
        ok "the real gc has no gc gc-toolkit scripts-dir under [imports.kit]"
    fi
fi

echo "── a step that names an act gives its exact command, and the skill explains it once ──"
lacks() {
    if grep -qF -- "$2" "$3"; then bad "$1" "$4"; else ok "$1"; fi
}
have() {
    if grep -qF -- "$2" "$3"; then ok "$1"; else bad "$1" "missing: $2"; fi
}
have "the step table points acting on a ruling at the skills" '`work`, `waits`, `records`, `prs`' "$PROMPT"
have "the record step gives the append it runs" 'gc bd update "$SUBJECT" --append-notes "<the decision>.' "$SETTLE"
have "…and the append of a current-state block" 'gc bd update "$SUBJECT" --append-notes "## Current state' "$SETTLE"
have "the settle step gives the create and the sling for routed work" 'gc sling <rig>/<pool> "$WORK" --on <formula>' "$SETTLE"
have "the settle step gives the subject's parent lookup" 'converse-parent.sh" "$SUBJECT"' "$SETTLE"
# Where new work is filed has two cases (docs/component-model.md, I1). A
# dependency sits beside the bead that waits on it, because bd refuses a blocks
# edge from a parent to its own descendant. Work that decomposes an epic is that
# epic's member, and nothing makes the epic wait on it. A blanket "never under
# the bead it came from" would keep an epic's own decomposition out of it.
have "…and the work skill states the rule it serves: a dependency goes beside the bead it came from" \
    'A dependency goes beside the bead it came from, never under it.' "$WORK_SKILL"
have "…and work that decomposes an epic is that epic's member" \
    'Work that genuinely decomposes an epic is a member of that epic.' "$WORK_SKILL"
lacks "…and no blanket rule keeps new work out from under the bead it came from" \
    'Never file it under the bead it came from' "$WORK_SKILL" \
    "an epic's decomposition is filed under that epic, even when the epic is the bead it came from"
lacks "…in the body or in the description every agent reads" \
    'never under the bead it came from' "$WORK_SKILL" \
    "the description carries the rule to every role, so it states both cases"
have "the settle step files an epic subject's decomposition as its member" \
    'created with `--parent "$SUBJECT"`' "$SETTLE"
have "…and gives that member no --waiting-on" \
    'it gets no `--waiting-on`' "$SETTLE"
lacks "…and keeps no blanket rule against filing under the subject" \
    'Never file it under the subject' "$SETTLE" \
    "an epic subject's decomposition is filed as its member"
have "the settle step gives the arm it names" 'deferred-dispatch.sh" arm <follow-up>' "$SETTLE"
have "…once the follow-up's own store reads the edge back" '&& gc bd --rig <rig> dep list <follow-up> --direction=down -t blocks --json' "$SETTLE"
have "…and holds a follow-up on another rig's bead with a demand in its own store" 'gc-helm.sh" demand <follow-up>' "$SETTLE"
have "the prompt gives the disposal writer's call" 'bead-rehome.sh" --origin "$SUBJECT"' "$PROMPT"
have "the prompt gives the retire call" 'pr-dispose.sh" --anchor "$SUBJECT"' "$PROMPT"
have "the prompt gives the call that withdraws a recommendation" 'converse-invalidate-recommendation.sh" "<why' "$PROMPT"
have "the prompt gives the call that asks for a visit" 'gc-helm.sh" open <bead>' "$PROMPT"
have "the prompt gives the PR post calls" 'pr-post.sh" reply --host github.com' "$PROMPT"
for f in "$PROMPT" "$SETTLE"; do
    missing=""
    for w in $(grep -oE '"\$CONV/[A-Za-z0-9._-]+"' "$f" | sed 's#.*/##; s#"$##' | sort -u); do
        [ -x "$ROOT/assets/scripts/$w" ] || missing="$missing $w"
    done
    [ -z "$missing" ] && ok "$(basename "$(dirname "$f")")/$(basename "$f"): every \$CONV writer it calls is in assets/scripts" \
        || bad "$(basename "$(dirname "$f")")/$(basename "$f"): every \$CONV writer it calls is in assets/scripts" "missing:$missing"
done
# The roles that route work point at the four skills through one fragment, so
# the pointer is written once: each prompt includes it and keeps no copy of its
# own. The skill descriptions every agent sees say when to load each skill, so
# no prompt restates that, and no prompt singles out one formula.
ASK="$REPO/template-fragments/ask-for-work.template.md"
tr '\n' ' ' <"$ASK" >"$TMP/ask-joined"
have "one fragment names the four skills" '`work`, `waits`, `records` or `prs`' "$TMP/ask-joined"
for f in "$PROMPT" "$MECHANIK"; do
    role=$(basename "$(dirname "$f")")
    have "$role: the prompt includes that fragment" '{{ template "ask-for-work" . }}' "$f"
    tr '\n' ' ' <"$f" >"$TMP/joined-$role"
    lacks "$role: …and keeps no copy of its own" '`records` or `prs`' "$TMP/joined-$role" \
        "the ask-for-work fragment says it once for every prompt that includes it"
done
lacks "the mechanik prompt does not single out a design-first initiative" 'design-first initiative' "$MECHANIK" \
    "choosing a formula is the work skill's option"
lacks "the converse prompt does not single out a design-convoy" 'design-convoy included' "$PROMPT" \
    "choosing a formula is the work skill's option"
lacks "the prompt no longer carries the design-convoy questions" 'design-convoy-routing' "$PROMPT" \
    "choosing the formula is the work skill's option"
# Every converse framing is composed from the prompt's hand-back definition, so
# the definition says how a framing places its subject and the step skills point
# at it. These read the prompt with its whitespace squeezed, so a re-wrap keeps
# them.
PROMPT_JOINED="$TMP/prompt-squeezed"
tr -s '[:space:]' ' ' <"$PROMPT" >"$PROMPT_JOINED"
have "a hand-back names its subject by what it is to the operator" \
    'names its subject by what it is to the operator' "$PROMPT_JOINED"
have "a PR, or a decision about one, is named by the PR's number and what it does" \
    "by the PR's number and what it does for them" "$PROMPT_JOINED"
have "a report is named by who filed it and what it found" \
    'by who filed it and what it found' "$PROMPT_JOINED"
have "the operator's own ask stands in their words, ahead of what was proposed from it" \
    'in their words rather than anything proposed from it' "$PROMPT_JOINED"
have "the body opens on the subject, its state and why it reached the operator, before any mechanism" \
    'why it reached the operator now, before any mechanism' "$PROMPT_JOINED"
have "a report with no PR involved says so" 'a report with no PR involved says so' "$PROMPT_JOINED"
have "a message with detail opens the way the body does" \
    'A message with detail above its hand-back opens the way the body does' "$PROMPT_JOINED"
have "the message keeps pipeline vocabulary out or says what it means" \
    'Pipeline vocabulary (moot, twin, fold, retract, park) and names learned from code stay out, or say what they mean' "$PROMPT_JOINED"
have "an option says what it does rather than what it avoids" \
    'saying what it does rather than what it avoids' "$PROMPT_JOINED"
have "an option that accepts a known defect names what it breaks" \
    'names what the defect breaks and where' "$PROMPT_JOINED"
lacks "the hold skill points at the shape and keeps no copy of its order" 'detail and evidence' \
    "$SKILLS/converse-hold/SKILL.md" "the prompt's definition is the one place a framing's order is stated"
have "the work skill reads the formulas a rig has now" 'gc formula list --rig <rig>' "$WORK_SKILL"
lacks "the work skill's formula choice carries no one formula's variables" 'design_gated' "$WORK_SKILL" \
    "a formula's own description says when it fits and how to tune it"
# Which work a formula fits is its own description, the text `gc formula show`
# prints and the work skill reads. A doc describes the pattern; it does not
# tell an agent which formula to choose.
lacks "the work skill's formula choice sends an agent to no doc" 'any doc a description names' "$WORK_SKILL" \
    "the description is where an agent's choice comes from"
awk '/^\[/ { exit }
     /^description = """/ { f = 1; sub(/^description = """/, ""); if ($0 != "") print; next }
     f && /^"""/ { exit }
     f { print }' "$DESIGN_FORMULA" >"$TMP/design-description"
have "the design-convoy formula's own description says which work it fits" 'high-blast-radius' "$TMP/design-description"
lacks "the design-convoy doc carries no formula choice for an agent" 'When to reach for it' "$DESIGN_DOC" \
    "which work a formula fits is its own description, which the work skill reads"
# A supplement goes to the PR's own rig, because a pool reads only its rig's
# store, and the anchor waits on it, because the merge holds on what blocks the
# anchor and never on a bead that only names the PR's branch. The hold is read
# back before the sling.
have "the prs skill files a supplement in the PR's rig" 'SUP=$(gc bd --rig <rig> create' "$PRS_SKILL"
have "…as a child of the anchor" '"anchor_bead":"<anchor>"' "$PRS_SKILL"
have "…born joined to the anchor and holding its merge" '--deps related:<anchor>,blocks:<anchor>' "$PRS_SKILL"
have "…reads the hold back from the anchor in the same rig" '&& gc bd --rig <rig> dep list <anchor> --direction=down -t blocks --json' "$PRS_SKILL"
have "…and slings only after that read" '&& gc sling <rig>/<pool> "$SUP"' "$PRS_SKILL"
have "…whose target is the PR's base, the integration branch for a stage's PR" "the integration branch for a stage's PR" "$PRS_SKILL"
have "…one at a time on a branch" 'Send one supplement at a time' "$PRS_SKILL"
# fenced_block <file> <marker> — the fenced bash block that holds <marker>, with
# the fence's own indent taken off each of its lines.
fenced_block() {
    awk -v m="$2" '
        /^[ \t]*```/ {
            if (inb) { if (hit) { printf "%s", buf; exit } inb = 0; buf = ""; hit = 0 }
            else if ($0 ~ /```bash[ \t]*$/) { inb = 1; match($0, /^[ \t]*/); ind = RLENGTH }
            next
        }
        inb {
            l = $0
            if (ind > 0 && substr(l, 1, ind) ~ /^[ \t]+$/) l = substr(l, ind + 1)
            buf = buf l "\n"
            if (index($0, m)) hit = 1
        }
    ' "$1"
}
# The mechanik names the act where it routes work, so it gives the command too:
# the prs skill's own, sent to its rig's polecat pool. Compared whole, the two
# copies cannot drift apart.
SUP_MARK='SUP=$(gc bd --rig <rig> create'
fenced_block "$PRS_SKILL" "$SUP_MARK" >"$TMP/sup-prs"
fenced_block "$MECHANIK" "$SUP_MARK" | sed 's#{{ \.BindingPrefix }}polecat#<pool>#' >"$TMP/sup-mechanik"
if [ -s "$TMP/sup-prs" ] && cmp -s "$TMP/sup-prs" "$TMP/sup-mechanik"; then
    ok "the mechanik's supplement command is the prs skill's, sent to its rig's polecat pool"
else
    bad "the mechanik's supplement command is the prs skill's, sent to its rig's polecat pool" \
        "$(diff "$TMP/sup-prs" "$TMP/sup-mechanik" 2>&1 | head -4 | tr '\n' ' ')"
fi
# The mechanik's disposition fragment names the work skill's option and calls
# the pack's own writer, never a copy found in a checkout.
DISPOSITION="$REPO/template-fragments/bead-disposition.template.md"
have "the disposition fragment calls the pack's own writer" '"{{ .ConfigDir }}/assets/scripts/bead-rehome.sh" --origin <bead>' "$DISPOSITION"
found=""
for probe in 'GC_RIG_ROOT' 'rev-parse --show-toplevel' 'GC_CITY_PATH'; do
    grep -qF -- "$probe" "$DISPOSITION" && found="$found [$probe]"
done
[ -z "$found" ] && ok "…and looks for it in no checkout" || bad "…and looks for it in no checkout" "found:$found"
# The dispatch fragment renders into the mechanik's prompt and into the
# keeper's. The keeper comes from the gascity-keeper sub-pack, and a pack path
# rendered for it names that sub-pack, which holds none of the scripts the
# fragment calls. So the fragment calls each of them the work skill's way, and
# each render's calls resolve through the pack command to the pack's own copy.
DISPATCH="$REPO/template-fragments/watch-dispatched-work.template.md"
DD_CALL='"$(gc <binding> scripts-dir)/deferred-dispatch.sh"'
WATCH_CALL='"$(gc <binding> scripts-dir)/gc-bd-watch.sh"'
have "the dispatch fragment gives the work skill's notice call" "$DD_CALL notify <bead> --agent <qualified-name>" "$DISPATCH"
have "…the call the work skill gives" "$DD_CALL notify <bead> --agent <qualified-name>" "$WORK_SKILL"
have "…and runs its watch through the pack command" "command: '$WATCH_CALL <bead>'" "$DISPATCH"
for render in "$REPO/generated/seed-audit/agents/mechanik.md" "$REPO/generated/seed-audit/agents/keeper.md"; do
    agent=$(basename "$render" .md)
    verbs=$(grep -oF -- "$DD_CALL notify
$DD_CALL arm" "$render" | sed 's/.* //' | sort -u | tr '\n' ' ')
    [ "$verbs" = "arm notify " ] && ok "$agent's render gives the notice and the arm as calls through the pack command" \
        || bad "$agent's render gives the notice and the arm as calls through the pack command" "found: '$verbs'"
    have "…and the watch" "command: '$WATCH_CALL <bead>'" "$render"
    # Prose names a script by its bare name in backticks. Every other mention
    # is a call, and goes through the pack command.
    for script in deferred-dispatch.sh gc-bd-watch.sh; do
        call="\"\$(gc <binding> scripts-dir)/$script\""
        named=$(grep -oF -- "$script" "$render" | wc -l | tr -d ' ')
        prose=$(grep -oF -- "\`$script\`" "$render" | wc -l | tr -d ' ')
        via=$(grep -oF -- "$call" "$render" | wc -l | tr -d ' ')
        [ "$via" -gt 0 ] && [ "$named" = "$((via + prose))" ] && ok "…and names $script no other way ($via calls)" \
            || bad "…and names $script no other way" "$via of its $((named - prose)) calls go through the pack command"
    done
done
for script in deferred-dispatch.sh gc-bd-watch.sh; do
    call="\"\$(gc <binding> scripts-dir)/$script\""
    printf 'printf "%%s" %s\n' "${call/<binding>/kit}" >"$TMP/fragment-call-$script"
    got=$(cd "$TMP/away" && env -u GC_PACK_DIR -u BASH_ENV -u ENV PATH="$TMP/stub:$PATH" bash "$TMP/fragment-call-$script" 2>/dev/null)
    [ "$got" = "$ROOT/assets/scripts/$script" ] && [ -x "$got" ] \
        && ok "with the city's binding filled in, the fragment's call resolves to the pack's own $script" \
        || bad "with the city's binding filled in, the fragment's call resolves to the pack's own $script" "resolved '$got'"
done

echo "── a problem in software the rig does not own goes through one skill ──"
# It arises rarely, so its procedure is a skill the situation loads rather than a
# section every polecat run carries, and each command is stated there once. The
# origin guard and upstream-finding.sh's refusals stay the hard stops, so a run
# that never loads the skill is still stopped. The description is the only
# trigger, and specs/tk-nadehdk/skill-trigger-probe.md proves it fires.
EXTERNAL="$SKILLS/external-issue/SKILL.md"
OUTBOUND="$REPO/docs/outbound-sends.md"
ext_desc=$(frontmatter "$EXTERNAL" description)
[ "$(frontmatter "$EXTERNAL" name)" = external-issue ] && ok "external-issue: name equals its directory" \
    || bad "external-issue: name equals its directory"
[ -n "$(frontmatter "$EXTERNAL" compatibility)" ] && ok "external-issue: declares its compatibility" \
    || bad "external-issue: declares its compatibility"
case "$ext_desc" in
    *"bug, gap or vulnerability in software this rig does not own"*"gh write to such a repository was refused"*)
        ok "external-issue: the description names both occasions" ;;
    *) bad "external-issue: the description names both occasions" "$ext_desc" ;;
esac
for f in "$REPO/template-fragments/polecat-doctrine.template.md" "$REPO/agents/polecat/prompt.template.md" "$REPO/agents/polecat-codex/prompt.template.md"; do
    lacks "$(basename "$f"): leaves the send's commands to the skill" 'upstream-finding.sh' "$f" \
        "this runs on every polecat turn and applies rarely, so it lives in the skill"
done
have "the outbound-sends doc links the skill" '../skills/external-issue/SKILL.md' "$OUTBOUND"
fences=$(grep -c '^ *```' "$OUTBOUND")
[ "$fences" = 0 ] && ok "the outbound-sends doc holds no command block: each command lives in the skill" \
    || bad "the outbound-sends doc holds no command block: each command lives in the skill" "$fences fence lines"
for probe in 'upstream-finding.sh" \' 'isSecurityPolicyEnabled securityPolicyUrl' '/private-vulnerability-reporting' 'security-advisories/reports' 'escalate.sh" --subject'; do
    have "the skill gives the command: $probe" "$probe" "$EXTERNAL"
    lacks "…and the doc does not" "$probe" "$OUTBOUND" "each command lives only in the skill"
done

echo "── a step that depends on the one before it runs only once that one succeeded ──"
# An example that sends work and then records the dispatch, records an outcome
# and then closes, files a bead and then sends it, or adds a wait and then
# arms, chains the second step onto the first with &&. Run apart, a refused
# first step leaves the second recording what never happened: a dispatch marker
# over a failed sling strips the recommendation, and the board's Accept reads
# the marker as a dispatch already sent; an arm with no edge sends its bead on
# the next pass. Each example runs as written, its placeholders filled, under a
# stub gc that refuses its first call, and nothing may run after that call.
CH="$TMP/chain"
mkdir -p "$CH/bin" "$CH/pack/assets/scripts"
cat >"$CH/bin/gc" <<'STUB'
#!/usr/bin/env bash
# Logs each call, and refuses the one numbered CHAIN_FAIL_AT. It answers
# scripts-dir under any binding, prints an id for a create, and applies an
# update's --set-metadata and --unset-metadata to a store of one file per key.
# A dep add records its edge as a "<waiting> <blocker>" line that a dep list
# reads back and a dep remove deletes, in the one store a --rig names or not.
# With CHAIN_CROSS_STORE set, a dep add answers as bd does for a blocker in
# another store: it prints success and exits 0, and no edge reads back.
n=$(( $(cat "$CHAIN_DIR/count" 2>/dev/null || echo 0) + 1 ))
echo "$n" >"$CHAIN_DIR/count"
printf 'gc %s\n' "$*" >>"$CHAIN_DIR/log"
if [ "$n" = "${CHAIN_FAIL_AT:-}" ]; then echo "gc: refused" >&2; exit 1; fi
[ "${2:-}" = scripts-dir ] && { printf '%s\n' "$CHAIN_DIR/pack/assets/scripts"; exit 0; }
[ "${1:-} ${2:-}" = "bd --rig" ] && set -- bd "${@:4}"
case "$1 ${2:-}" in
    "bd create") echo '{"id":"tk-new"}' ;;
    "bd update")
        shift 3
        while [ $# -gt 0 ]; do
            case "$1" in
                --set-metadata) printf '%s' "${2#*=}" >"$CHAIN_DIR/store/${2%%=*}"; shift 2 ;;
                --unset-metadata) rm -f "$CHAIN_DIR/store/$2"; shift 2 ;;
                *) shift ;;
            esac
        done ;;
    "bd dep")
        case "${3:-}" in
            add)
                [ -n "${CHAIN_CROSS_STORE:-}" ] || printf '%s %s\n' "$4" "$5" >>"$CHAIN_DIR/edges"
                echo "✓ Added dependency: $4 depends on $5 (blocks)" ;;
            remove)
                grep -vxF -- "$4 $5" "$CHAIN_DIR/edges" >"$CHAIN_DIR/edges.new"
                mv "$CHAIN_DIR/edges.new" "$CHAIN_DIR/edges" ;;
            list)
                awk -v w="$4" '$1 == w { printf "%s{\"id\":\"%s\",\"dependency_type\":\"blocks\"}", (n++ ? "," : "["), $2 }
                    END { print (n ? "]" : "[]") }' "$CHAIN_DIR/edges" ;;
        esac ;;
esac
exit 0
STUB
cat >"$CH/pack/assets/scripts/bead-rehome.sh" <<'STUB'
#!/usr/bin/env bash
# Logs its call, numbered with gc's, and refuses the one numbered CHAIN_FAIL_AT.
n=$(( $(cat "$CHAIN_DIR/count" 2>/dev/null || echo 0) + 1 ))
echo "$n" >"$CHAIN_DIR/count"
printf 'writer %s %s\n' "${0##*/}" "$*" >>"$CHAIN_DIR/log"
if [ "$n" = "${CHAIN_FAIL_AT:-}" ]; then echo "writer: refused" >&2; exit 1; fi
exit 0
STUB
cp "$CH/pack/assets/scripts/bead-rehome.sh" "$CH/pack/assets/scripts/deferred-dispatch.sh"
cp "$CH/pack/assets/scripts/bead-rehome.sh" "$CH/pack/assets/scripts/gc-helm.sh"
chmod +x "$CH/bin/gc" "$CH/pack/assets/scripts/bead-rehome.sh" "$CH/pack/assets/scripts/deferred-dispatch.sh" \
    "$CH/pack/assets/scripts/gc-helm.sh"
# fill_block — an example with each <placeholder> filled with x, the stub pack in
# for a template's {{ .ConfigDir }}, and the disposition kinds cut to one.
fill_block() {
    sed -e "s#{{ \\.ConfigDir }}#$CH/pack#g" \
        -e 's#--kind re-homed|folded|fixed-upstream|duplicate|not-needed#--kind not-needed#' \
        -e 's#<[^>]*>#x#g'
}
# run_chain <shell> <block> [fail-at] [cross-store] — one run of a filled example
# in a fresh shell, from an empty log, no edges and a store holding one
# recommendation, with call number <fail-at> refused; prints its status.
run_chain() {
    rm -rf "$CH/store" "$CH/count"
    mkdir -p "$CH/store"
    : >"$CH/log"
    : >"$CH/edges"
    printf 'x' >"$CH/store/gc.recommended_formula"
    (cd "$TMP/away" && env -u BASH_ENV -u ENV CHAIN_DIR="$CH" CHAIN_FAIL_AT="${3:-}" \
        CHAIN_CROSS_STORE="${4:-}" CONV="$CH/pack/assets/scripts" SUBJECT=tk-x VISIT=tk-v \
        PATH="$CH/bin:$PATH" $1 "$2" </dev/null >/dev/null 2>&1)
    echo $?
}
while IFS='|' read -r label file marker; do
    fenced_block "$file" "$marker" | fill_block >"$CH/block"
    if [ ! -s "$CH/block" ]; then
        bad "$label: the example is found" "no fenced bash block holds '$marker' in $file"
        continue
    fi
    for sh_ in $shells; do
        run=$sh_
        [ "$sh_" = zsh ] && run="zsh -f"
        rc=$(run_chain "$run" "$CH/block" 1)
        calls=$(grep -c . "$CH/log")
        if [ "$rc" -ne 0 ] && [ "$calls" -eq 1 ]; then
            ok "($sh_) $label: a refused first step stops the example"
        else
            bad "($sh_) $label: a refused first step stops the example" "exit $rc, calls: $(tr '\n' ';' <"$CH/log")"
        fi
        rc=$(run_chain "$run" "$CH/block")
        calls=$(grep -c . "$CH/log")
        if [ "$rc" -eq 0 ] && [ "$calls" -ge 2 ]; then
            ok "($sh_) $label: …and the next step runs once the first succeeds"
        else
            bad "($sh_) $label: …and the next step runs once the first succeeds" "exit $rc, calls: $(tr '\n' ';' <"$CH/log")"
        fi
    done
done <<SPECS
work: taking a recommendation|$WORK_SKILL|gc.recommended_formula_dispatched=
work: closing a bead that needs no work|$WORK_SKILL|gc.work_outcome=no-op
converse prompt: disposing of a no-work subject|$PROMPT|gc.work_outcome=no-op
disposition fragment: closing a bead that did not land|$DISPOSITION|gc.work_outcome=no-op
converse-settle: filing and sending routed work|$SETTLE|gc sling <rig>/<pool> "\$WORK"
converse-settle: arming a follow-up|$SETTLE|gc bd --rig <rig> dep add <follow-up> <blocker>
converse-settle: arming a follow-up on a demand|$SETTLE|gc bd --rig <rig> dep remove <follow-up> <blocker>
SPECS
# The arm runs only once the follow-up's own store reads the edge back. A dep add
# onto a bead in another store prints success and exits 0 but holds nothing, so
# on that answer the example stops at the read-back and arms nothing. When the
# wait goes on a demand instead, a demand that did not land arms nothing either.
fenced_block "$SETTLE" 'gc bd --rig <rig> dep add <follow-up> <blocker>' | fill_block >"$CH/block"
fenced_block "$SETTLE" 'gc bd --rig <rig> dep remove <follow-up> <blocker>' | fill_block >"$CH/demand-block"
for sh_ in $shells; do
    run=$sh_
    [ "$sh_" = zsh ] && run="zsh -f"
    rc=$(run_chain "$run" "$CH/block" "" 1)
    if [ "$rc" -ne 0 ] && grep -q '^gc bd --rig x dep list x ' "$CH/log" && ! grep -q '^writer deferred-dispatch.sh arm ' "$CH/log"; then
        ok "($sh_) converse-settle: a dep add that holds nothing arms nothing"
    else
        bad "($sh_) converse-settle: a dep add that holds nothing arms nothing" "exit $rc, calls: $(tr '\n' ';' <"$CH/log")"
    fi
    rc=$(run_chain "$run" "$CH/block")
    if [ "$rc" -eq 0 ] && grep -q '^writer deferred-dispatch.sh arm ' "$CH/log"; then
        ok "($sh_) converse-settle: …and an edge that reads back is armed"
    else
        bad "($sh_) converse-settle: …and an edge that reads back is armed" "exit $rc, calls: $(tr '\n' ';' <"$CH/log")"
    fi
    rc=$(run_chain "$run" "$CH/demand-block" 2)
    if [ "$rc" -ne 0 ] && grep -q '^writer gc-helm.sh demand ' "$CH/log" && ! grep -q '^writer deferred-dispatch.sh arm ' "$CH/log"; then
        ok "($sh_) converse-settle: a demand that did not land arms nothing"
    else
        bad "($sh_) converse-settle: a demand that did not land arms nothing" "exit $rc, calls: $(tr '\n' ';' <"$CH/log")"
    fi
done
# Taking a recommendation records the dispatch only once the sling went: a
# refused sling leaves both keys as they were, and a sent one swaps them.
fenced_block "$WORK_SKILL" 'gc.recommended_formula_dispatched=' | fill_block >"$CH/block"
run_chain bash "$CH/block" 1 >/dev/null
if [ "$(cat "$CH/store/gc.recommended_formula" 2>/dev/null)" = x ] && [ ! -e "$CH/store/gc.recommended_formula_dispatched" ]; then
    ok "work: a refused sling leaves the recommendation and records no dispatch"
else
    bad "work: a refused sling leaves the recommendation and records no dispatch" "store holds: $(ls "$CH/store" | tr '\n' ' ')"
fi
run_chain bash "$CH/block" >/dev/null
if [ ! -e "$CH/store/gc.recommended_formula" ] && [ "$(cat "$CH/store/gc.recommended_formula_dispatched" 2>/dev/null)" = x ]; then
    ok "work: …and a sent one strips the recommendation and records the dispatch"
else
    bad "work: …and a sent one strips the recommendation and records the dispatch" "store holds: $(ls "$CH/store" | tr '\n' ' ')"
fi

echo "── each real need scores highest on the skill that answers it ──"
# <expected skill> TAB <the need, verbatim>
cat >"$TMP/needs" <<'NEEDS'
work	I'll check how the sitting should carry out the routing before acting.
work	Before I route, I need to get the mechanics exactly right — the subject <bead> is the implementation task ("Wire a Dolt reclaim cadence"), so I must understand whether --route releases the held subject itself or expects a separate sibling bead.
work	Before the safety-critical writes, I need three things: the subject's own parent (work must be filed as a sibling), the right formula to route through (not a bare sling), and the exact `converse-signoff.sh` semantics.
work	Let me confirm the exact sling incantation used elsewhere in the codebase for routing fresh implementation work to the polecat pool, so I route it the canonical way.
work	The record/sign-off procedure is clear, but I need to get the routing shape exactly right before I act — specifically whether `--route` in the sign-off itself performs the sling, and how a bug subject (already a workable bead) is routed versus filing a sibling.
work	Before dispatching a third time, let me confirm how the pool actually starts work — does the polecat pour the formula on claim, or does it need the convoy pre-built?
work	Checking the subject's parent and the routing options first.
work	Checking cross-rig filing mechanics and default sling targets before creating.
work	Since the drawing-board work is a **design** task, let me check which formula routes a design/spec pass while the subagents finish.
work	Now working out the right way to retire this duplicate, since polecats may not close work beads themselves.
waits	No existing tracker covers the class gap. Checking the deferred-dispatch arm's usage before filing.
waits	Before arming, I'll check that an arm behind the park gate fits how the gate is meant to work.
waits	I'm reading `escalate.sh` to see how it files the visit and whether it wires the subject to it.
waits	Wiring the approved cleanup so it comes back to you on its own once the fix lands, and can't delete anything until you've approved the list. Checking the demand-filing verb first.
waits	Checking the demand-resolution verb first.
waits	First, the disarm command's usage.
records	Let me confirm the notes-append verb (I must not clobber the rich Sitting-1 notes) and re-stamp the takeaway.
prs	While the suite runs, I'm reading `pr-post.sh` to see how it marks the city's reply, so I can draft the answer to the review.
prs	Still routing: I'm finding the right way to send rework back to an open PR's branch, so the polecat works on the same PR rather than starting a new one.
prs	Before acting on your ruling, I'm checking that the PR's state hasn't moved overnight and reading how the sign-off files the rework.
NEEDS

# The converse step skills are loaded by name from the step table in the
# converse prompt, never chosen by description, so they are not competitors.
grep -E '^\| \*\*Steps? ' "$PROMPT" | grep -oE '`converse-[a-z-]+`' | tr -d '`' | sort -u >"$TMP/by-name"
[ -s "$TMP/by-name" ] && ok "the step table names the skills it loads by name ($(tr '\n' ' ' <"$TMP/by-name"))" \
    || bad "the step table names the skills it loads by name" "no \`converse-…\` names in $PROMPT"

awk -F '\t' -v byname="$TMP/by-name" '
    BEGIN {
        # Function words, then the words a hunt uses for hunting itself (the
        # script, its usage, the syntax), which name no act.
        n = split("a about above after again against all also am an and any are as at be because been before being below between both but by can cannot could d did do does doing don down during each else even ever every exactly few first for from further get gets getting go going got had has have having he her here hers him his how i if in into is isn it its itself just know last let lets ll look looking looks m make me might more most must my myself need needed needs no nor not now of off on once only or other ought our ours out over own per re right s same see seems shall she should so some such sure t than that the their them then there these they this those though through to too under until up us use used uses using ve very want was way we well were what when where whether which while who whom why will with within without would yet you your yours " \
                  "check checks checked checking confirm confirming find figure understand covers cover read reads reading script scripts step steps flag flags verb verbs usage command commands syntax mechanic mechanics contract contracts interface semantics tool tools option options order", sw, " ")
        for (i = 1; i <= n; i++) stop[sw[i]] = 1
        while ((getline line < byname) > 0) skip[line] = 1
    }
    # stem <word> — strip one common ending. "ing" and "ed" come off only when
    # a vowel is left, so sling keeps its shape.
    function stem(w,   n, c, r) {
        n = length(w)
        if (n > 4 && w ~ /(ies|ied)$/) return substr(w, 1, n - 3) "y"
        r = ""
        if (n > 5 && w ~ /ings$/) r = substr(w, 1, n - 4)
        else if (n > 4 && w ~ /ing$/) r = substr(w, 1, n - 3)
        else if (n > 3 && w ~ /ed$/) r = substr(w, 1, n - 2)
        if (r != "" && r ~ /[aeiouy]/) {
            w = r
            n = length(w)
            c = substr(w, n, 1)
            if (n > 3 && c == substr(w, n - 1, 1) && c !~ /[lsz]/) w = substr(w, 1, n - 1)
        } else if (n > 3 && w ~ /es$/) w = substr(w, 1, n - 2)
        else if (n > 2 && w ~ /s$/ && w !~ /ss$/) w = substr(w, 1, n - 1)
        n = length(w)
        if (n > 3 && w ~ /e$/) w = substr(w, 1, n - 1)
        return w
    }
    # stems <text> — fill the global set S with the text'"'"'s stems.
    function stems(text,   k, n, words) {
        for (k in S) delete S[k]
        text = tolower(text)
        gsub(/[^a-z0-9]+/, " ", text)
        n = split(text, words, " ")
        for (k = 1; k <= n; k++) {
            if (words[k] == "" || (words[k] in stop)) continue
            S[stem(words[k])] = 1
        }
    }
    FNR == NR {
        if ($1 in skip) next
        nsk++; sk[nsk] = $1
        stems($2)
        for (k in S) { has[$1, k] = 1; df[k]++ }
        next
    }
    {
        want = $1; need = $2
        stems(need)
        best = ""; bestsc = -1; second = ""; secsc = -1; wantsc = 0; wanthits = ""
        for (i = 1; i <= nsk; i++) {
            s = sk[i]; sc = 0; hits = ""
            for (k in S) if ((s, k) in has) { sc += 1 / df[k]; hits = hits " " k }
            if (s == want) { wantsc = sc; wanthits = hits }
            if (sc > bestsc) { second = best; secsc = bestsc; best = s; bestsc = sc }
            else if (sc > secsc) { second = s; secsc = sc }
        }
        if (best == want && bestsc > 0 && bestsc > secsc)
            printf "ok\t%s\t%s scores %.2f (%s ), next %s %.2f\n", need, want, wantsc, wanthits, second, secsc
        else if (best == want)
            printf "bad\t%s\t%s ties %s at %.2f (%s )\n", need, want, second, wantsc, wanthits
        else
            printf "bad\t%s\t%s scores %.2f (%s ), but %s scores %.2f\n", need, want, wantsc, wanthits, best, bestsc
    }
' "$TMP/corpus" "$TMP/needs" >"$TMP/scores"

while IFS="$(printf '\t')" read -r verdict need detail; do
    if [ "$verdict" = ok ]; then
        ok "\"$need\": $detail"
    else
        bad "\"$need\"" "$detail"
    fi
done <"$TMP/scores"
rows=$(grep -c . "$TMP/needs")
scored=$(grep -c . "$TMP/scores")
[ "$rows" = "$scored" ] && ok "every need was scored ($scored)" || bad "every need was scored" "$scored of $rows"

echo
echo "skill-needs: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
