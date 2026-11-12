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
# dispatch fragment the keeper composes calls deferred-dispatch.sh and
# gc-bd-watch.sh the work skill's way, and that the mechanik's prompt calls
# gc-bd-watch.sh and human-gate.sh under the binding it is rendered with, so
# each render reaches the pack's own copies. It pins the prs
# skill's supplement command: filed in the PR's rig, holding the anchor's merge,
# and slung only once its create names it. It pins that a formula's own
# description, not a doc, says which work
# the formula fits. It pins that a problem in software the rig does not own goes
# through the external-issue skill, which alone holds that path's commands and
# files the finding set aside, with no send drafted and no question asked.
# It runs each example whose second step depends on its first
# under a gc that refuses the first step, and fails if anything after it runs.
# It runs the settle step's arm under a gc that answers a dep add as bd does for
# a blocker in another store, and fails if the arm runs. It runs the premise
# re-check's moot or benign close under stubs, and fails unless the close
# settles a headline that still waits on a subject nothing holds any more,
# leaves one that an open blocker holds, and closes the conversation only once
# every read and write before it has answered. It pins that every skill and
# formula names a pack skill to load by its catalog name, never by its path, so
# an agent in any tree loads the installed pack's copy.
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
CONTINUE="$REPO/skills/converse-continue/SKILL.md"
ITERATE="$REPO/skills/converse-iterate-document/SKILL.md"
EPIC_REVIEW="$REPO/skills/converse-epic-review/SKILL.md"
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
for s in $BLOCKS; do
    f="$SKILLS/$s/SKILL.md"
    [ -r "$f" ] || continue
    found=""
    for probe in 'GC_RIG_ROOT' 'rev-parse --show-toplevel' '"$S/' 'GC_CITY_PATH/rigs'; do
        grep -qF -- "$probe" "$f" && found="$found [$probe]"
    done
    # CONV, the scripts directory a converse sitting sets, as a whole word: the
    # sitting's CONVERSATION, which a writer takes in its environment, is
    # another variable.
    grep -qE '(^|[^A-Za-z0-9_])CONV([^A-Za-z0-9_]|$)' "$f" && found="$found [CONV]"
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
# An epic may land through Deliveries, each an epic under it whose description
# opens with an Aim: line (docs/epics.md). Work under an epic goes into the open
# Delivery whose aim covers it, so the filer lists those first. A Delivery is
# filed by the operator's aim alone, and goes to no pool. A follow-up never goes
# under a closed parent, where it would follow no priority and sit under no open
# row, so the parent lookup gives the nearest open ancestor.
have "the work skill lists an epic's open Deliveries before filing under it" \
    'gc bd list --parent <epic> -t epic --limit 0 --json' "$WORK_SKILL"
have "…files a Delivery as an epic under its epic" \
    'gc bd create "Delivery: <what it lands>" -t epic --parent <epic>' "$WORK_SKILL"
have "…only by the operator's decision that aims it" \
    "A Delivery is filed only by the decision that aims it, and that decision is the" "$WORK_SKILL"
have "…and says the parent lookup climbs past a closed parent" \
    'This prints that parent, or the nearest open bead above it once' "$WORK_SKILL"
have "the settle step says the same of the subject's parent" \
    "It is the subject's own parent, or the nearest open" "$SETTLE"
have "the settle step gives the arm it names" 'deferred-dispatch.sh" arm <follow-up>' "$SETTLE"
have "…once the follow-up and the blocker carry one id prefix" '[ "$(echo <follow-up> | cut -d- -f1)" = "$(echo <blocker> | cut -d- -f1)" ]' "$SETTLE"
have "…and holds a follow-up on another rig's bead with a human gate in its own store" 'human-gate.sh" --subject <follow-up>' "$SETTLE"
have "the prompt gives the disposal writer's call" 'bead-rehome.sh" --origin "$SUBJECT"' "$PROMPT"
have "the prompt gives the retire call, through the sign-off" '--ruled yes --ruling "<the ruling, one line>" --no-wait --retire not-needed' "$PROMPT"
have "…as the prs skill does" '--ruled yes --ruling "<the ruling, one line>" --no-wait --retire not-needed' "$PRS_SKILL"
# A gate can hold a merge, so a sitting answers every gate through the sign-off
# writer, which carries out what the ruling does to the PR first.
have "the continue step answers a ruling on a turn that does not sign off through the writer" 'converse-signoff.sh" --conversation "$CONVERSATION" --answer <gate>' "$CONTINUE"
lacks "…and never through a bare gate resolve" 'gc bd gate resolve <gate>' "$CONTINUE" \
    "a bare resolve releases what the gate holds before the ruling's rework or retirement is in place"
# The hold keeps the subject's arm and route, so an answer that clears its last
# blocker releases it to them. Before the answer, a ruling that sends the
# subject elsewhere withdraws both, by the sign-off's own rule and block, which
# the dispatch-path section below compares whole and runs.
have "…and first withdraws an arm the ruling does not keep" '"$CONV/deferred-dispatch.sh" disarm "$SUBJECT" --reason "$WHY"' "$CONTINUE"
have "…and a pool route" 'gc bd update "$SUBJECT" --unset-metadata gc.routed_to' "$CONTINUE"
have "…by step 7's rule" "by step 7's" "$CONTINUE"
have "the prompt gives the call that withdraws a recommendation" 'converse-invalidate-recommendation.sh" "<why' "$PROMPT"
# One writer dispatches a recommendation, under the bead's acceptance lock and a
# token that finds a dispatch an Accept that stopped part way already poured. A
# sling of the agent's own pours the formula again once that run has finished.
have "the work skill takes a recommendation through Accept's writer" 'gc-helm.sh" accept <bead>' "$WORK_SKILL"
lacks "…and gives no sling of its own that records the dispatch" 'gc.recommended_formula_dispatched=' "$WORK_SKILL" \
    "a sling and record of its own bypasses Accept's lock and token, and dispatches the recommendation twice"
have "the settle step takes a subject's recommendation through the sign-off" '--ruled yes --no-wait --accept' "$SETTLE"
have "the prompt gives the call that opens a conversation" 'gc-helm.sh" open <bead>' "$PROMPT"
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
# The effort recipe pushes the effort's branch, and converse sittings, which
# push only the branch of a change the operator rules them make, load the work
# skill. So the skill and the recipe name the session that runs it, and the
# skill sends a sitting's effort to the Accept path or to that session. Read
# with whitespace squeezed, so a re-wrap keeps them.
WORK_JOINED="$TMP/work-squeezed"
tr -s '[:space:]' ' ' <"$WORK_SKILL" >"$WORK_JOINED"
EFFORT_JOINED="$TMP/effort-squeezed"
tr -s '[:space:]' ' ' <"$SKILLS/work/integration-effort.md" >"$EFFORT_JOINED"
have "the work skill names the session that runs the effort recipe" \
    'beside this file, which the mechanik runs.' "$WORK_JOINED"
have "…and the recipe names it too" 'The mechanik runs this recipe.' "$EFFORT_JOINED"
have "…and a sitting does not run it" "a converse sitting pushes only the branch of a change the operator rules it make, through Work's hand-off, so a sitting does not run it." "$WORK_JOINED"
have "…but takes a design-convoy recommendation through Accept" \
    "When the subject's recommendation is \`mol-design-convoy\`, the sign-off's \`--accept\` takes it" "$WORK_JOINED"
have "…and hands any other effort to the mechanik" 'Any other effort goes to the mechanik' "$WORK_JOINED"
lacks "the work skill claims no scope the recipe's push breaks" 'nothing here changes a repo.' "$WORK_JOINED" \
    "the effort recipe pushes the effort's branch"
# A supplement goes to the PR's own rig, because a pool reads only its rig's
# store, and the anchor waits on it, because the merge holds on what blocks the
# anchor and never on a bead that only names the PR's branch. The hold rides the
# create, and the sling runs only once the create names the supplement.
have "the prs skill files a supplement in the PR's rig" 'SUP=$(gc bd --rig <rig> create' "$PRS_SKILL"
have "…as a child of the anchor" '"anchor_bead":"<anchor>"' "$PRS_SKILL"
have "…born joined to the anchor and holding its merge" '--deps related:<anchor>,blocks:<anchor>' "$PRS_SKILL"
have "…and slings only once the create names the supplement" '&& [ -n "$SUP" ]' "$PRS_SKILL"
have "…then slings it" '&& gc sling <rig>/<pool> "$SUP"' "$PRS_SKILL"
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
# The dispatch fragment renders into the keeper's prompt. The keeper comes from
# the gascity-keeper sub-pack, and a pack path rendered for it names that
# sub-pack, which holds none of the scripts the fragment calls. So the fragment
# calls each of them the work skill's way, and the render's calls resolve
# through the pack command to the pack's own copy. The mechanik comes from this
# pack, so its prompt calls its watch and its gate withdrawal under the binding
# it is rendered with, which the seed audit renders as gc-toolkit.
DISPATCH="$REPO/template-fragments/watch-dispatched-work.template.md"
DD_CALL='"$(gc <binding> scripts-dir)/deferred-dispatch.sh"'
WATCH_CALL='"$(gc <binding> scripts-dir)/gc-bd-watch.sh"'
KEEPER_RENDER="$REPO/generated/seed-audit/agents/keeper.md"
MECHANIK_RENDER="$REPO/generated/seed-audit/agents/mechanik.md"
have "the dispatch fragment gives the work skill's notice call" "$DD_CALL notify <bead> --agent <qualified-name>" "$DISPATCH"
have "…the call the work skill gives" "$DD_CALL notify <bead> --agent <qualified-name>" "$WORK_SKILL"
have "…and runs its watch through the pack command" "command: '$WATCH_CALL <bead>'" "$DISPATCH"
# named_only_via <render> <script> [<binding>] — prose names a script by its bare
# name in backticks. Every other mention is a call, and goes through the pack
# command under <binding>, the placeholder itself when none is given.
named_only_via() {
    call="\"\$(gc ${3:-<binding>} scripts-dir)/$2\""
    named=$(grep -oF -- "$2" "$1" | wc -l | tr -d ' ')
    prose=$(grep -oF -- "\`$2\`" "$1" | wc -l | tr -d ' ')
    via=$(grep -oF -- "$call" "$1" | wc -l | tr -d ' ')
    [ "$via" -gt 0 ] && [ "$named" = "$((via + prose))" ] && ok "…and names $2 no other way ($via calls)" \
        || bad "…and names $2 no other way" "$via of its $((named - prose)) calls go through the pack command"
}
verbs=$(grep -oF -- "$DD_CALL notify
$DD_CALL arm" "$KEEPER_RENDER" | sed 's/.* //' | sort -u | tr '\n' ' ')
[ "$verbs" = "arm notify " ] && ok "keeper's render gives the notice and the arm as calls through the pack command" \
    || bad "keeper's render gives the notice and the arm as calls through the pack command" "found: '$verbs'"
have "…and the watch" "command: '$WATCH_CALL <bead>'" "$KEEPER_RENDER"
for script in deferred-dispatch.sh gc-bd-watch.sh; do
    named_only_via "$KEEPER_RENDER" "$script"
done
MECHANIK_WATCH_CALL='"$(gc gc-toolkit scripts-dir)/gc-bd-watch.sh"'
have "the mechanik's render gives the watch as a call through the pack command" "command: '$MECHANIK_WATCH_CALL <bead>'" "$MECHANIK_RENDER"
have "…and the withdrawal of its own gate" '"$(gc gc-toolkit scripts-dir)/human-gate.sh" --retract --subject <bead>' "$MECHANIK_RENDER"
for script in gc-bd-watch.sh human-gate.sh; do
    named_only_via "$MECHANIK_RENDER" "$script" gc-toolkit
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
# It arises rarely, so its procedure is a skill the situation loads rather than
# a section every polecat run carries, and each command is stated there once.
# The origin guard stays the hard stop, so a run that never loads the skill is
# still stopped, and the guard's refusal names the skill. The finding is filed
# whole in one create, already deferred and labelled, so no reader of
# ready work ever offers it, and nothing in the skill drafts a send or asks the
# operator anything. A create whose reply was lost may still have filed the
# finding, so the skill looks again in the stores themselves, which the
# supervisor's cache can lag, before it files a second.
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
    lacks "$(basename "$f"): leaves a problem in someone else's software to the skill" 'upstream-finding' "$f" \
        "this runs on every polecat turn and applies rarely, so it lives in the skill"
done
have "the outbound-sends doc links the skill" '../skills/external-issue/SKILL.md' "$OUTBOUND"
fences=$(grep -c '^ *```' "$OUTBOUND")
[ "$fences" = 0 ] && ok "the outbound-sends doc holds no command block: each command an agent runs lives in the skill" \
    || bad "the outbound-sends doc holds no command block: each command an agent runs lives in the skill" "$fences fence lines"
for probe in 'gc beads list --label upstream-finding' '--status deferred' '-l upstream-finding' \
    '--deps "discovered-from:' 'isSecurityPolicyEnabled securityPolicyUrl' \
    '/private-vulnerability-reporting'; do
    have "the skill gives the command: $probe" "$probe" "$EXTERNAL"
done
have "the skill looks for the finding in the stores themselves before it files again" \
    'GC_NO_API=1 gc beads list --label upstream-finding' "$EXTERNAL"
lacks "the skill gives a finding no pack kind: bd's status, label and edge carry it" 'task_kind' "$EXTERNAL" \
    "nothing counts findings or branches on one, and a pack kind is a pack noun that needs a warrant (docs/warrants.md)"
for probe in '--status deferred' 'isSecurityPolicyEnabled' 'private-vulnerability-reporting'; do
    lacks "…and the doc does not: $probe" "$probe" "$OUTBOUND" "each command an agent runs lives only in the skill"
done
for probe in 'human-gate.sh' 'escalate.sh' 'gh issue create' 'gh pr create' 'gh issue comment' 'upstream-finding.sh'; do
    lacks "the skill drafts no send and asks nothing: no $probe" "$probe" "$EXTERNAL" \
        "a finding is set aside with nothing drafted and no question owed; the send is drafted when the operator picks it up"
done

echo "── a step that depends on the one before it runs only once that one succeeded ──"
# An example that records an outcome and then closes, files a bead and then
# sends it, or adds a wait and then arms, chains the second step onto the first
# with &&. Run apart, a refused first step lets the second act on what never
# happened: a close with no recorded outcome, a sling of a bead never filed, or
# an arm with no edge, which sends its bead on the next pass. Each example
# runs as written, its placeholders filled, under a stub gc that refuses its
# first call, and nothing may run after that call.
CH="$TMP/chain"
mkdir -p "$CH/bin" "$CH/pack/assets/scripts"
cat >"$CH/bin/gc" <<'STUB'
#!/usr/bin/env bash
# Logs each call on one line, and refuses the one numbered CHAIN_FAIL_AT. It answers
# scripts-dir under any binding, prints an id for a create, and applies an
# update's --set-metadata and --unset-metadata to a store of one file per key.
# An --append-notes adds to one notes file that a show prints.
# A dep add records its edge as a "<waiting> <blocker>" line that a dep list
# prints and a dep remove deletes, in the one store a --rig names or not.
n=$(( $(cat "$CHAIN_DIR/count" 2>/dev/null || echo 0) + 1 ))
echo "$n" >"$CHAIN_DIR/count"
{ printf 'gc %s' "$*" | tr '\n' ' '; echo; } >>"$CHAIN_DIR/log"
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
                --append-notes) printf '%s\n' "$2" >>"$CHAIN_DIR/notes"; shift 2 ;;
                *) shift ;;
            esac
        done ;;
    "bd show") jq -Rs '[{notes: .}]' "$CHAIN_DIR/notes" ;;
    "bd dep")
        case "${3:-}" in
            add)
                printf '%s %s\n' "$4" "$5" >>"$CHAIN_DIR/edges"
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
{ printf 'writer %s %s' "${0##*/}" "$*" | tr '\n' ' '; echo; } >>"$CHAIN_DIR/log"
if [ "$n" = "${CHAIN_FAIL_AT:-}" ]; then echo "writer: refused" >&2; exit 1; fi
exit 0
STUB
cp "$CH/pack/assets/scripts/bead-rehome.sh" "$CH/pack/assets/scripts/deferred-dispatch.sh"
cp "$CH/pack/assets/scripts/bead-rehome.sh" "$CH/pack/assets/scripts/human-gate.sh"
cp "$CH/pack/assets/scripts/bead-rehome.sh" "$CH/pack/assets/scripts/finalize-gate.sh"
chmod +x "$CH/bin/gc" "$CH/pack/assets/scripts/bead-rehome.sh" "$CH/pack/assets/scripts/deferred-dispatch.sh" \
    "$CH/pack/assets/scripts/human-gate.sh" "$CH/pack/assets/scripts/finalize-gate.sh"
# fill_block — an example with each <placeholder> filled with x, the stub pack in
# for a template's {{ .ConfigDir }}, and the disposition kinds cut to one.
fill_block() {
    sed -e "s#{{ \\.ConfigDir }}#$CH/pack#g" \
        -e 's#--kind re-homed|folded|fixed-upstream|duplicate|not-needed#--kind not-needed#' \
        -e 's#<[^>]*>#x#g'
}
# run_chain <shell> <block> [fail-at] — one run of a filled example
# in a fresh shell, from an empty log, no edges and an empty store, with call
# number <fail-at> refused; prints its status.
run_chain() {
    rm -rf "$CH/store" "$CH/count"
    mkdir -p "$CH/store"
    : >"$CH/log"
    : >"$CH/edges"
    : >"$CH/notes"
    (cd "$TMP/away" && env -u BASH_ENV -u ENV CHAIN_DIR="$CH" CHAIN_FAIL_AT="${3:-}" \
        CONV="$CH/pack/assets/scripts" SUBJECT=tk-x CONVERSATION=tk-v EPIC=tk-e \
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
work: closing a bead that needs no work|$WORK_SKILL|gc.work_outcome=no-op
converse prompt: disposing of a no-work subject|$PROMPT|gc.work_outcome=no-op
converse-settle: filing and sending routed work|$SETTLE|gc sling <rig>/<pool> "\$WORK"
converse-settle: arming a follow-up|$SETTLE|gc bd --rig <rig> dep add <follow-up> <blocker>
converse-settle: arming a follow-up on a human gate|$SETTLE|"\$CONV/human-gate.sh" --subject <follow-up> --key waits-for-<blocker>
converse-epic-review: closing a bead the ruling closes|$EPIC_REVIEW|finalize-gate.sh" check <bead>
converse-epic-review: retiring a bead that served only this hypothesis|$EPIC_REVIEW|gc.work_outcome=no-op
SPECS
# The edge is written only when the follow-up and the blocker carry one id
# prefix, because a dep add onto a bead in another store prints success and
# exits 0 but holds nothing, and the arm runs only once the add exits 0. When
# the wait goes on a human gate instead, a gate that did not land arms nothing
# either.
fenced_block "$SETTLE" 'gc bd --rig <rig> dep add <follow-up> <blocker>' | fill_block >"$CH/block"
fenced_block "$SETTLE" 'gc bd --rig <rig> dep add <follow-up> <blocker>' \
    | sed -e 's/<follow-up>/tk-f/g' -e 's/<blocker>/hq-b/g' | fill_block >"$CH/xstore-block"
fenced_block "$SETTLE" '"$CONV/human-gate.sh" --subject <follow-up> --key waits-for-<blocker>' | fill_block >"$CH/gate-block"
for sh_ in $shells; do
    run=$sh_
    [ "$sh_" = zsh ] && run="zsh -f"
    rc=$(run_chain "$run" "$CH/xstore-block")
    if [ "$rc" -ne 0 ] && ! grep -q ' dep add ' "$CH/log" && ! grep -q '^writer deferred-dispatch.sh arm ' "$CH/log"; then
        ok "($sh_) converse-settle: a blocker in another store gets no edge and no arm"
    else
        bad "($sh_) converse-settle: a blocker in another store gets no edge and no arm" "exit $rc, calls: $(tr '\n' ';' <"$CH/log")"
    fi
    rc=$(run_chain "$run" "$CH/block")
    if [ "$rc" -eq 0 ] && grep -q '^gc bd --rig x dep add x x ' "$CH/log" && grep -q '^writer deferred-dispatch.sh arm ' "$CH/log"; then
        ok "($sh_) converse-settle: …and a blocker in the follow-up's store is waited on and armed"
    else
        bad "($sh_) converse-settle: …and a blocker in the follow-up's store is waited on and armed" "exit $rc, calls: $(tr '\n' ';' <"$CH/log")"
    fi
    rc=$(run_chain "$run" "$CH/gate-block" 1)
    if [ "$rc" -ne 0 ] && grep -q '^writer human-gate.sh --subject ' "$CH/log" && ! grep -q '^writer deferred-dispatch.sh arm ' "$CH/log"; then
        ok "($sh_) converse-settle: a gate that did not land arms nothing"
    else
        bad "($sh_) converse-settle: a gate that did not land arms nothing" "exit $rc, calls: $(tr '\n' ';' <"$CH/log")"
    fi
done
echo "── a sitting iterating on a document writes one scaffold and names it in the ruling ──"
have "the step table sends a sitting iterating on a document to its skill" '**Steps 5–8, when the operator is iterating on a document**' "$PROMPT"
have "…by name" '`converse-iterate-document` |' "$PROMPT"
have "the ruling line names the block the worker starts from" 'to the scaffold in the notes of <bead>, the block headed ## Current state (<date>)' "$ITERATE"
have "…and the sign-off files the rework" '--no-wait --rework' "$ITERATE"
have "a self-review that starts fresh finds the block through the worker's notes" "so your work bead's notes name this block" "$ITERATE"
have "a block on another bead leaves the next sitting its name" "name that bead in the subject's record" "$ITERATE"
fenced_block "$ITERATE" '--append-notes "$SCAFFOLD"' | fill_block >"$CH/block"
for sh_ in $shells; do
    run=$sh_
    [ "$sh_" = zsh ] && run="zsh -f"
    rc=$(run_chain "$run" "$CH/block")
    if [ "$rc" -eq 0 ] && head -n 1 "$CH/notes" | grep -qE '^## Current state \([0-9]{4}-[0-9]{2}-[0-9]{2}\)$' \
        && grep -qxF 'Where a file'"'"'s text and this block disagree, this block wins.' "$CH/notes" \
        && grep -qF 'goes to the operator through a human gate. Never decide it.' "$CH/notes" \
        && grep -qxF 'Open questions: none' "$CH/notes"; then
        ok "($sh_) converse-iterate-document: the block lands dated, carrying the worker's rules and no open question"
    else
        bad "($sh_) converse-iterate-document: the block lands dated, carrying the worker's rules and no open question" "exit $rc, notes: $(head -c 400 "$CH/notes")"
    fi
    if [ "$rc" -eq 0 ] && grep -qxF 'It gives the direction of each change, and the words are yours to write, except words it marks exact, which go in as they stand.' "$CH/notes" \
        && grep -qxF 'A section it does not name stays as it is, apart from what a WHOLE DOCUMENT line changes in it.' "$CH/notes"; then
        ok "($sh_) converse-iterate-document: the block leaves the worker the words, and a section it does not name as it is"
    else
        bad "($sh_) converse-iterate-document: the block leaves the worker the words, and a section it does not name as it is" "exit $rc, notes: $(head -c 400 "$CH/notes")"
    fi
    sed 's/^x$/the `echo ran` and $HOME stay as written/' "$CH/block" >"$CH/literal-block"
    rc=$(run_chain "$run" "$CH/literal-block")
    if [ "$rc" -eq 0 ] && grep -qxF 'the `echo ran` and $HOME stay as written' "$CH/notes"; then
        ok "($sh_) converse-iterate-document: what the block quotes stays as written"
    else
        bad "($sh_) converse-iterate-document: what the block quotes stays as written" "exit $rc, notes: $(head -c 400 "$CH/notes")"
    fi
    rc=$(run_chain "$run" "$CH/block" 1)
    if [ "$rc" -ne 0 ] && [ ! -s "$CH/notes" ]; then
        ok "($sh_) converse-iterate-document: a scaffold the store refuses is not reported as written"
    else
        bad "($sh_) converse-iterate-document: a scaffold the store refuses is not reported as written" "exit $rc"
    fi
done
echo "── a sitting makes a change the operator rules it make through Work's writers ──"
# A sitting's change is held on its conversation and goes through the writers a
# polecat's work goes through, under --held-by, so the step table loads the edit
# skill by name and the skill calls both writers that way.
EDIT="$REPO/skills/converse-edit/SKILL.md"
have "the step table sends a sitting the operator rules make a change to its skill" '**Steps 5–8, when the operator rules that the sitting make a change with them**' "$PROMPT"
have "…by name" '`converse-edit` |' "$PROMPT"
have "the edit skill holds the change on the conversation" 'gc bd dep add "$CHANGE" "$CONVERSATION" --type=blocks' "$EDIT"
have "…cuts its tree through Work's setup under --held-by" '"$CONV/work-setup.sh" --bead "$CHANGE" --held-by "$CONVERSATION"' "$EDIT"
have "…and hands it off through Work's hand-off under --held-by" '"$CONV/work-submit.sh" --bead "$CHANGE" --held-by "$CONVERSATION"' "$EDIT"
have "…and reads the polecat class's standards before the first edit" 'template-fragments/work-quality-polecats.template.md' "$EDIT"
echo "── a moot or benign close settles a headline that waits on nothing ──"
# A cut-short sitting leaves its hold's headline on the subject, and the next
# sitting's premise re-check can find the conversation moot and close it. The
# block runs as written, its placeholders filled, under stubs: gc answers the
# subject's row from RL_ROW and exits RL_SHOW_RC after printing it, and gctk,
# built from this checkout, answers what holds the subject from a store of that
# row with an edge onto each bead RL_GATES lists, `blocks` unless the bead names
# its `edge`, those beads, and the rows RL_MORE adds. Its reads fail at
# RL_DEPS_RC, or when RL_GATES is not a list.
RECHECK="$REPO/skills/converse-recheck-premise/SKILL.md"
RL="$TMP/release"
mkdir -p "$RL/bin" "$RL/pack/assets/scripts"
export HOLDS_STUB="$REPO/assets/scripts/holds-store.stub.sh" GC_NO_API=1
GCTK_BIN="$("$HOLDS_STUB" build "$TMP/gctk")" || { echo "FAIL - gctk did not build, so the premise re-check cannot run"; exit 1; }
export GCTK_BIN
cat >"$RL/bin/gc" <<'STUB'
#!/usr/bin/env bash
if [ -n "${HOLDS_STUB_READ:-}" ] && [ "${1:-}" = bd ]; then
    shift
    printf '%s\n' "$RL_GATES" | jq -e 'type == "array"' >/dev/null 2>&1 || { echo "gc bd: simulated read failure" >&2; exit 1; }
    [ "${RL_DEPS_RC:-0}" -eq 0 ] || { echo "gc bd: simulated read failure" >&2; exit "$RL_DEPS_RC"; }
    jq -nc --argjson row "$RL_ROW" --argjson g "$RL_GATES" --argjson more "${RL_MORE:-[]}" \
        '[ ($row[0] + {_deps: [ $g[] | {id, dependency_type: (.edge // "blocks")} ]}) ] + $g + $more' >"$RL_DIR/holds.json" || exit 1
    HOLDS_STORE="$RL_DIR/holds.json" exec "$HOLDS_STUB" answer "$@"
fi
printf 'gc %s\n' "$*" >>"$RL_DIR/log"
case "$1 ${2:-} ${3:-}" in
    "bd show "*)
        [ -z "${RL_SHOW_DOWN:-}" ] || { printf '%s\n' '{"error":"no issues found matching the provided IDs"}'; exit 1; }
        printf '%s\n' "$RL_ROW"; exit "${RL_SHOW_RC:-0}" ;;
    "bd comment "*) [ -z "${RL_COMMENT_REFUSE:-}" ] || exit 1 ;;
esac
exit 0
STUB
cat >"$RL/pack/assets/scripts/gc-helm.sh" <<'STUB'
#!/usr/bin/env bash
printf 'gc-helm %s\n' "$*" >>"$RL_DIR/log"
[ -z "${RL_TAKEAWAY_FAIL:-}" ] || exit 1
STUB
cat >"$RL/pack/assets/scripts/pr-sitting-comment.sh" <<'STUB'
#!/usr/bin/env bash
printf 'pr-sitting-comment %s\n' "$*" >>"$RL_DIR/log"
STUB
chmod +x "$RL/bin/gc" "$RL/pack/assets/scripts/"*.sh
fenced_block "$RECHECK" 'replaced the headline of $SUBJECT' | fill_block >"$RL/block"
[ -s "$RL/block" ] && ok "the premise re-check's close is found" \
    || bad "the premise re-check's close is found" "no fenced bash block replaces the headline in $RECHECK"
# run_release <shell> <row-json> <gates-json> [NAME=VALUE...] — one run of the
# close on a subject whose row is <row-json>; prints its status.
run_release() {
    local run=$1 row=$2 gates=$3
    shift 3
    : >"$RL/log"
    (cd "$TMP/away" && env -u BASH_ENV -u ENV RL_DIR="$RL" RL_ROW="$row" RL_GATES="$gates" "$@" CONV="$RL/pack/assets/scripts" \
        SUBJECT=tk-x CONVERSATION=tk-v PATH="$RL/bin:$PATH" $run "$RL/block" >"$RL/out" 2>&1)
    echo $?
}
WAITING='[{"id":"tk-x","metadata":{"gc.takeaway":"holding — x","gc.takeaway_settled":""}}]'
SETTLED='[{"id":"tk-x","metadata":{"gc.takeaway":"ruled: x","gc.takeaway_settled":"1"}}]'
NONE_HOLDS='[{"id":"tk-g1","issue_type":"gate","await_type":"human","status":"closed"},{"id":"tk-w","issue_type":"task","status":"closed"}]'
GATE_HOLDS='[{"id":"tk-g2","issue_type":"gate","await_type":"human","status":"open"}]'
WORK_HOLDS='[{"id":"tk-w","issue_type":"task","status":"open"}]'
# A waits-for edge of the subject's own onto a spawner whose child is open: the
# store cannot judge it yet, so the subject reads unjudged, still held.
SPAWN_HOLDS='[{"id":"tk-sp","issue_type":"task","status":"open","edge":"waits-for"}]'
SPAWN_CHILD='[{"id":"tk-spc","issue_type":"task","status":"open","parent":"tk-sp"}]'
for sh_ in $shells; do
    run=$sh_
    [ "$sh_" = zsh ] && run="zsh -f"
    rc=$(run_release "$run" "$WAITING" "$NONE_HOLDS")
    calls=$(tr '\n' ';' <"$RL/log")
    case "$rc:$calls" in
        0:*"gc-helm takeaway tk-x x: x --by converse --no-wait;"*"gc bd close tk-v --reason x: x;"*)
            ok "($sh_) recheck close: a waiting headline on a subject nothing holds is settled with the reading, before the conversation closes" ;;
        *) bad "($sh_) recheck close: a waiting headline on a subject nothing holds is settled with the reading, before the conversation closes" "exit $rc, calls: $calls" ;;
    esac
    for held_by in "$GATE_HOLDS|an open human gate|[]" "$WORK_HOLDS|open work|[]" "$SPAWN_HOLDS|a waits-for edge it cannot judge yet|$SPAWN_CHILD"; do
        gates=${held_by%%|*}; rest=${held_by#*|}; what=${rest%%|*}; more=${rest#*|}
        rc=$(run_release "$run" "$WAITING" "$gates" RL_MORE="$more")
        calls=$(tr '\n' ';' <"$RL/log")
        case "$rc:$calls" in
            *"gc-helm takeaway"*) bad "($sh_) recheck close: a subject $what still holds keeps its headline" "exit $rc, calls: $calls" ;;
            0:*"gc bd close tk-v "*) ok "($sh_) recheck close: a subject $what still holds keeps its headline, and the conversation closes" ;;
            *) bad "($sh_) recheck close: a subject $what still holds keeps its headline" "exit $rc, calls: $calls" ;;
        esac
    done
    # A conversation on an open PR holds the PR's merge through the anchor's
    # blocks edge onto it, so on an anchor the conversation, tk-v, is among the
    # subject's pending waits. The close ends that wait, so it keeps no
    # headline, while any other wait beside it still does, and is named alone.
    CONV_HOLDS='[{"id":"tk-v","issue_type":"task","status":"in_progress"}]'
    rc=$(run_release "$run" "$WAITING" "$CONV_HOLDS")
    calls=$(tr '\n' ';' <"$RL/log")
    case "$rc:$calls" in
        0:*"gc-helm takeaway tk-x x: x --by converse --no-wait;"*"gc bd close tk-v --reason x: x;"*)
            ok "($sh_) recheck close: the conversation's own hold on the anchor keeps no headline, and the conversation closes" ;;
        *) bad "($sh_) recheck close: the conversation's own hold on the anchor keeps no headline, and the conversation closes" "exit $rc, calls: $calls" ;;
    esac
    CONV_AND_GATE='[{"id":"tk-v","issue_type":"task","status":"in_progress"},{"id":"tk-g2","issue_type":"gate","await_type":"human","status":"open"}]'
    rc=$(run_release "$run" "$WAITING" "$CONV_AND_GATE")
    calls=$(tr '\n' ';' <"$RL/log")
    case "$rc:$calls:$(cat "$RL/out")" in
        *"gc-helm takeaway"*) bad "($sh_) recheck close: a gate beside the conversation's hold still keeps the headline" "exit $rc, calls: $calls" ;;
        0:*"gc bd close tk-v "*"tk-x keeps its headline: tk-g2 still holds it"*)
            ok "($sh_) recheck close: a gate beside the conversation's hold still keeps the headline, named without the conversation" ;;
        *) bad "($sh_) recheck close: a gate beside the conversation's hold still keeps the headline" "exit $rc, calls: $calls, out: $(cat "$RL/out")" ;;
    esac
    rc=$(run_release "$run" "$SETTLED" '[]')
    calls=$(tr '\n' ';' <"$RL/log")
    case "$rc:$calls" in
        *"gc-helm takeaway"*) bad "($sh_) recheck close: a settled headline is not written" "exit $rc, calls: $calls" ;;
        0:*"gc bd close tk-v "*) ok "($sh_) recheck close: a settled headline is not written, and the conversation closes" ;;
        *) bad "($sh_) recheck close: a settled headline is not written" "exit $rc, calls: $calls" ;;
    esac
    case "$rc:$calls" in
        0:*"gc bd close tk-v --reason x: x;gc bd comment tk-v x;pr-sitting-comment refresh --sitting tk-v;"*)
            ok "($sh_) recheck close: the close is recorded among the visit's actions, then the visit's PR comment is drawn again" ;;
        *) bad "($sh_) recheck close: the close is recorded among the visit's actions, then the visit's PR comment is drawn again" "exit $rc, calls: $calls" ;;
    esac
    rc=$(run_release "$run" "$SETTLED" '[]' RL_COMMENT_REFUSE=1)
    calls=$(tr '\n' ';' <"$RL/log")
    case "$rc:$calls:$(cat "$RL/out")" in
        0:*"gc bd close tk-v "*"pr-sitting-comment refresh --sitting tk-v;"*"the close was not recorded among the actions of tk-v"*)
            ok "($sh_) recheck close: an action the store will not record still closes the conversation, says so, and draws the comment" ;;
        *) bad "($sh_) recheck close: an action the store will not record still closes the conversation, says so, and draws the comment" "exit $rc, calls: $calls, out: $(cat "$RL/out")" ;;
    esac
    for stop in "RL_TAKEAWAY_FAIL=1|a headline that does not land|$NONE_HOLDS" "RL_SHOW_DOWN=1|a subject that does not read|$NONE_HOLDS" \
        "RL_NONE=1|a hold read that does not answer|{\"error\":\"no issue found\"}"; do
        IFS='|' read -r setting what gates <<EOF
$stop
EOF
        rc=$(run_release "$run" "$WAITING" "$gates" "$setting")
        calls=$(tr '\n' ';' <"$RL/log")
        case "$rc:$calls" in
            0:*|*"bd close"*|*"bd update"*) bad "($sh_) recheck close: $what closes nothing" "exit $rc, calls: $calls" ;;
            *) ok "($sh_) recheck close: $what closes nothing" ;;
        esac
    done
    # A read is an answer only when gc exits 0 and the subject's read is its own
    # row, alone. Anything else could be read as a settled headline or as no
    # blocker, so the close writes nothing and stops.
    TWICE=$(printf '%s' "$WAITING" | jq -c '. + .')
    OTHER=$(printf '%s' "$WAITING" | jq -c '.[0].id = "tk-y"')
    for stop in "[]|RL_SHOW_RC=0|RL_DEPS_RC=0|a subject read that answers no row" \
        "$TWICE|RL_SHOW_RC=0|RL_DEPS_RC=0|a subject read that answers two rows" \
        "$OTHER|RL_SHOW_RC=0|RL_DEPS_RC=0|a subject read that answers another bead's row" \
        "$WAITING|RL_SHOW_RC=1|RL_DEPS_RC=0|a subject read that exits non-zero, whatever it printed," \
        "$WAITING|RL_SHOW_RC=0|RL_DEPS_RC=1|a hold read that fails,"; do
        IFS='|' read -r row show_rc deps_rc what <<EOF
$stop
EOF
        rc=$(run_release "$run" "$row" "$NONE_HOLDS" "$show_rc" "$deps_rc")
        calls=$(tr '\n' ';' <"$RL/log")
        case "$rc:$calls" in
            0:*|*"bd close"*|*"bd update"*|*"gc-helm takeaway"*) bad "($sh_) recheck close: $what closes nothing" "exit $rc, calls: $calls" ;;
            *) ok "($sh_) recheck close: $what closes nothing" ;;
        esac
    done
done
echo "── every answer to a gate settles the subject's dispatch path first ──"
# The hold leaves the subject's arm and route in place, and the writer leaves
# them too, so an answer that clears the subject's last blocker releases the
# subject to them. The sign-off (step 7) and a turn's --answer (step 8) settle
# that path by one procedure, the same read and the same withdrawal, run before
# the answer. Compared whole, the two copies cannot drift apart.
DP_READ_MARK='"arm: '
DP_WITHDRAW_MARK='carries no arm and no pool route"'
for pair in "$DP_READ_MARK|read" "$DP_WITHDRAW_MARK|withdrawal"; do
    mark=${pair%|*}; what=${pair##*|}
    fenced_block "$SETTLE" "$mark" >"$TMP/dp-settle"
    fenced_block "$CONTINUE" "$mark" >"$TMP/dp-continue"
    if [ -s "$TMP/dp-settle" ] && cmp -s "$TMP/dp-settle" "$TMP/dp-continue"; then
        ok "the continue step settles the dispatch path with the sign-off's own $what"
    else
        bad "the continue step settles the dispatch path with the sign-off's own $what" \
            "$(diff "$TMP/dp-settle" "$TMP/dp-continue" 2>&1 | head -4 | tr '\n' ' ')"
    fi
done
withdraw_at=$(grep -nF "$DP_WITHDRAW_MARK" "$CONTINUE" | head -1 | cut -d: -f1)
answer_at=$(grep -nF 'converse-signoff.sh" --conversation "$CONVERSATION" --answer <gate>' "$CONTINUE" | head -1 | cut -d: -f1)
if [ -n "$withdraw_at" ] && [ -n "$answer_at" ] && [ "$withdraw_at" -lt "$answer_at" ]; then
    ok "…and withdraws the path before its --answer call"
else
    bad "…and withdraws the path before its --answer call" "withdrawal at line ${withdraw_at:-none}, answer at line ${answer_at:-none}"
fi
# The blocks run as written, their placeholders filled, under stubs over one
# subject's row in $DP/row.json: gc reads and unsets its metadata, the disarm
# drops its arm, and the writer's --answer logs the arm and route the answer
# would release the subject to. DP_SHOW_EMPTY answers the read with [],
# DP_SHOW_RC makes it exit with that status after printing the row, and
# DP_UPDATE_REFUSE refuses the update.
DP="$TMP/dispatch"
mkdir -p "$DP/bin" "$DP/pack/assets/scripts"
cat >"$DP/bin/gc" <<'STUB'
#!/usr/bin/env bash
printf 'gc %s\n' "$*" >>"$DP_DIR/log"
case "$1 ${2:-}" in
    "bd show")
        [ -z "${DP_SHOW_EMPTY:-}" ] || { printf '[]\n'; exit 0; }
        cat "$DP_DIR/row.json"; exit "${DP_SHOW_RC:-0}" ;;
    "bd update")
        [ -z "${DP_UPDATE_REFUSE:-}" ] || exit 1
        k=""; p=""
        for a in "$@"; do [ "$p" = "--unset-metadata" ] && k="$a"; p="$a"; done
        [ -z "$k" ] || { jq -c --arg k "$k" '.[0].metadata |= del(.[$k])' "$DP_DIR/row.json" >"$DP_DIR/row.tmp" \
            && mv "$DP_DIR/row.tmp" "$DP_DIR/row.json"; } ;;
esac
exit 0
STUB
cat >"$DP/pack/assets/scripts/deferred-dispatch.sh" <<'STUB'
#!/usr/bin/env bash
printf 'deferred-dispatch.sh %s\n' "$*" >>"$DP_DIR/log"
[ "${1:-}" = disarm ] || exit 2
jq -c '.[0].metadata |= with_entries(select(.key | startswith("gc.dispatch_when_ready") | not))' "$DP_DIR/row.json" >"$DP_DIR/row.tmp" \
    && mv "$DP_DIR/row.tmp" "$DP_DIR/row.json"
STUB
cat >"$DP/pack/assets/scripts/converse-signoff.sh" <<'STUB'
#!/usr/bin/env bash
printf 'converse-signoff.sh %s\n' "$*" >>"$DP_DIR/log"
jq -r '.[0].metadata | "answered with arm \(.["gc.dispatch_when_ready"] // "none") route \(.["gc.routed_to"] // "none")"' "$DP_DIR/row.json" >>"$DP_DIR/log"
STUB
chmod +x "$DP/bin/gc" "$DP/pack/assets/scripts/"*.sh
fenced_block "$CONTINUE" "$DP_WITHDRAW_MARK" | fill_block >"$DP/withdraw"
fenced_block "$CONTINUE" 'converse-signoff.sh" --conversation "$CONVERSATION" --answer <gate>' | fill_block >"$DP/answer"
# dp_seed <metadata-json> — a store whose subject tk-x carries that metadata,
# and an empty log.
dp_seed() { jq -cn --argjson m "$1" '[{id: "tk-x", metadata: $m}]' >"$DP/row.json"; : >"$DP/log"; }
# run_dp <shell> <block> [NAME=VALUE...] — one run of <block> over the store as
# it stands; prints its status.
run_dp() {
    local run=$1 block=$2
    shift 2
    (cd "$TMP/away" && env -u BASH_ENV -u ENV DP_DIR="$DP" "$@" CONV="$DP/pack/assets/scripts" \
        SUBJECT=tk-x CONVERSATION=tk-v PATH="$DP/bin:$PATH" $run "$block" >"$DP/out" 2>&1)
    echo $?
}
POOLED='{"gc.dispatch_when_ready":"rig-a/old-pool","gc.dispatch_when_ready_args":"[\"--on\",\"mol-polecat-work\"]","gc.routed_to":"rig-a/old-pool","gc.takeaway":"holding — x"}'
for sh_ in $shells; do
    run=$sh_
    [ "$sh_" = zsh ] && run="zsh -f"
    # A ruling on a turn that does not sign off sends the subject to another
    # pool: the continue step withdraws the old arm and route, then answers,
    # and the answer releases the subject to neither.
    dp_seed "$POOLED"
    rc=$(run_dp "$run" "$DP/withdraw")
    out=$(cat "$DP/out")
    rc2=$(run_dp "$run" "$DP/answer")
    calls=$(tr '\n' ';' <"$DP/log")
    case "$rc:$rc2:$calls" in
        0:0:*"deferred-dispatch.sh disarm tk-x --reason x;"*"gc bd update tk-x --unset-metadata gc.routed_to;"*"converse-signoff.sh --conversation tk-v --answer x "*"answered with arm none route none;")
            ok "($sh_) dispatch path: a turn's ruling that sends the subject elsewhere answers only once its old arm and pool route are gone" ;;
        *) bad "($sh_) dispatch path: a turn's ruling that sends the subject elsewhere answers only once its old arm and pool route are gone" "exit $rc/$rc2, calls: $calls" ;;
    esac
    has "$out" "tk-x carries no arm and no pool route" "($sh_) dispatch path: …and the withdrawal says so"
    for keep in '{"gc.routed_to":"human"}|a human route' '{}|no arm and no route'; do
        meta=${keep%%|*}; what=${keep#*|}
        dp_seed "$meta"
        rc=$(run_dp "$run" "$DP/withdraw")
        calls=$(tr '\n' ';' <"$DP/log")
        case "$rc:$calls:$(cat "$DP/out")" in
            *"deferred-dispatch.sh"*|*"bd update"*) bad "($sh_) dispatch path: a subject with $what is left as it is" "exit $rc, calls: $calls" ;;
            0:*"carries no arm and no pool route"*) ok "($sh_) dispatch path: a subject with $what is left as it is, and the withdrawal says so" ;;
            *) bad "($sh_) dispatch path: a subject with $what is left as it is" "exit $rc, calls: $calls, out: $(cat "$DP/out")" ;;
        esac
    done
    [ "$(jq -r '.[0].metadata["gc.routed_to"]' "$DP/row.json" 2>/dev/null)" = null ] \
        && ok "($sh_) dispatch path: …and nothing is written to it" \
        || bad "($sh_) dispatch path: …and nothing is written to it" "row: $(cat "$DP/row.json")"
    dp_seed '{"gc.routed_to":"human"}'
    run_dp "$run" "$DP/withdraw" >/dev/null
    eq "$(jq -r '.[0].metadata["gc.routed_to"]' "$DP/row.json")" human "($sh_) dispatch path: a human route stays"
    # A withdrawal the store refuses, or a subject read that is not its own
    # row alone, prints no success line and exits non-zero, so the sitting
    # answers nothing. A read that does not answer writes nothing at all.
    for stop in "DP_UPDATE_REFUSE=1|an update the store refuses|" \
        "DP_SHOW_EMPTY=1|a subject read that answers no row|" \
        "DP_SHOW_RC=1|a subject read that exits non-zero, whatever it printed,|"; do
        IFS='|' read -r setting what says <<EOF
$stop
EOF
        dp_seed "$POOLED"
        rc=$(run_dp "$run" "$DP/withdraw" "$setting")
        calls=$(tr '\n' ';' <"$DP/log")
        out=$(cat "$DP/out")
        case "$rc:$out" in
            0:*|*"carries no arm and no pool route"*) bad "($sh_) dispatch path: $what clears nothing for the answer" "exit $rc, out: $out" ;;
            *) ok "($sh_) dispatch path: $what clears nothing for the answer" ;;
        esac
        [ -z "$says" ] || has "$out" "$says" "($sh_) dispatch path: …and names what is left"
        case "$setting:$calls" in
            DP_SHOW_*:*"deferred-dispatch.sh"*|DP_SHOW_*:*"bd update"*) bad "($sh_) dispatch path: …$what writes nothing" "calls: $calls" ;;
            DP_SHOW_*) ok "($sh_) dispatch path: …and writes nothing" ;;
        esac
    done
done
echo "── a review of an epic gates what waits on its ruling, records it, and closes through the close gate ──"
# A sitting that reviews an epic is sent to its skill by name, and the prompt
# sends the closes its ruling makes to that skill, none forced, apart from the
# disposition writer it gives other subjects. The skill holds each landed
# Delivery's close, and only the work that waits on the ruling, with a human
# gate, and reads every epic not yet closed for the ground it owns, in a read
# that lists the epic itself, so an empty one is no answer. It records
# the review under its dated heading, then the contract the ruling sets and the
# ruling, with the gates it clears as its evidence, in one write whatever the
# ruling. It answers the landed Deliveries' gates before any close, and leaves
# the gates on waiting work to the sign-off, because an answer sends that work
# on and the work must start on what the ruling wrote. A close stands down
# waiting work it retires, which disarms it before the answer, and disarms and
# releases waiting work it closes as re-homed before answering its gate, because
# the disposition writer refuses a bead a gate holds. Each bead closes
# through the close gate, never forced, because bd refuses a close over an open
# child or a live blocker. The sign-off records the PR a retirement acts on
# under the words of its ruling, so each gate on a PR's anchor is answered under
# that PR's own ruling, and the final sign-off reaches none of those PRs. A
# subject that is itself a PR's anchor is reached by every call, so each call
# under the review's own ruling gives that PR's answer, the same each time, and
# its gate waits for the sign-off unless a close retires the PR, whose bead must
# close before the beads above it can. A re-home into another store names the
# new bead on each of those calls, so it is filed before the first. A call under
# another PR's ruling leaves the subject's PR standing, so the writer adds its
# Approve clause to that call's outcome too, and what the call prints about it
# answers nothing. A park's gate can hold other beads, so a release closes it
# only once nothing else waits on it, and never closes a blocker that is not a
# park's own gate.
have "the step table sends a sitting that reviews an epic to its skill" '**Steps 4–8, when the operator judges an epic'"'"'s contract or its course, or the subject is a landed Delivery or work that waits on a judgment about an epic**' "$PROMPT"
have "…by name" '`converse-epic-review` |' "$PROMPT"
have "the prompt sends a review's closes to its skill, none of them forced" \
    'A review of an epic makes its own closes, none of them forced, through the `converse-epic-review` skill.' "$PROMPT_JOINED"
have "…and an epic ruled close is the disposition writer's exception, which that skill closes" \
    'An epic ruled close is the exception to the disposition writer: the `converse-epic-review` skill closes it.' "$PROMPT_JOINED"
EPIC_REVIEW_JOINED="$TMP/epic-review-squeezed"
tr -s '[:space:]' ' ' <"$EPIC_REVIEW" >"$EPIC_REVIEW_JOINED"
have "the hold gates each landed Delivery's close" \
    'file the gate on each landed Delivery, with that Delivery as the bead that must wait' "$EPIC_REVIEW_JOINED"
have "…and never the epic, whose gate would hold its unstarted work" \
    'Gate no other part of the epic, and never the epic itself' "$EPIC_REVIEW_JOINED"
have "the ruling's evidence is the gates it clears, read off the conversation" \
    'select(.type == "replies-to")' "$EPIC_REVIEW"
have "…and is unset when it clears none" '--unset-metadata epic_ruling_evidence' "$EPIC_REVIEW"
have "the gates are answered before any close, through the sign-off's writer" \
    'converse-signoff.sh" --conversation "$CONVERSATION" --answer <gate>' "$EPIC_REVIEW"
have "the boundary read takes every epic not yet closed, whatever its status" \
    'gc bd list -t epic --status open,in_progress,blocked,deferred,hooked,pinned --limit 0 --json' "$EPIC_REVIEW"
lacks "…never the open status alone" '-t epic --status open --' "$EPIC_REVIEW" \
    "an epic in progress, blocked or deferred still owns its ground, and a read of the open status leaves it out"
have "…and a read that does not list the epic under review has not answered" \
    'The list always includes this epic, so a run without it has not answered' "$EPIC_REVIEW_JOINED"
fenced_block "$EPIC_REVIEW" 'epic_ruling=<continue|shift|close>' >"$CH/ruling-write"
if grep -qF -- '--set-metadata epic_hypothesis=' "$CH/ruling-write" \
    && grep -qF -- '--set-metadata epic_boundaries=' "$CH/ruling-write"; then
    ok "every ruling records the contract it sets in the write that records the ruling"
else
    bad "every ruling records the contract it sets in the write that records the ruling" "the ruling's write: $(head -c 400 "$CH/ruling-write")"
fi
review_contract_at=$(grep -nF -- '--set-metadata epic_boundaries=' "$EPIC_REVIEW" | head -1 | cut -d: -f1)
review_answer_at=$(grep -nF -- 'converse-signoff.sh" --conversation "$CONVERSATION" --answer <gate>' "$EPIC_REVIEW" | head -1 | cut -d: -f1)
if [ -n "$review_contract_at" ] && [ -n "$review_answer_at" ] && [ "$review_contract_at" -lt "$review_answer_at" ]; then
    ok "…before the gates are answered"
else
    bad "…before the gates are answered" "the contract's write at line ${review_contract_at:-none}, the first answer at line ${review_answer_at:-none}"
fi
have "the answers before the closes are the landed Deliveries' gates" \
    '# --answer <gate> once for each gate on a landed Delivery' "$EPIC_REVIEW"
have "…and a gate on waiting work is the sign-off's, once every write has landed" \
    'A gate on work that waits for a judgment takes no call here, because its answer sends that work on. The sign-off answers it once every write below has landed' "$EPIC_REVIEW_JOINED"
have "a close stands down waiting work it retires, which disarms it before the answer" \
    '"$CONV/stand-down.sh" <bead> --key <situation-key> --ruling "<the ruling, one sentence>" --successor "$CONVERSATION"' "$EPIC_REVIEW"
have "…and disarms and releases waiting work it re-homes into another store before its gate is answered" \
    '"$CONV/deferred-dispatch.sh" disarm <bead> --reason "<the ruling, one sentence>" && "$CONV/gc-helm.sh" takeaway <bead> "<the ruling, one sentence>" --release --no-wait' "$EPIC_REVIEW"
have "…then answers that gate on its own call and runs the writer last" \
    'then answer its gate on a call of its own, as write 2 answers one, and run the writer last' "$EPIC_REVIEW_JOINED"
have "each gate on a PR's anchor is answered on a call of its own, under that PR's own ruling" \
    "Each gate on a PR's anchor is answered on a call of its own, under that PR's own ruling: the review's ruling and what it does to that PR, naming the PR." "$EPIC_REVIEW_JOINED"
have "…a retirement's ruling names its PR, and --pr-anchor names it as the target" \
    '--ruling "<the ruling, one line>; it retires PR #<number> (<its anchor>)" --pr-anchor <its anchor>' "$EPIC_REVIEW"
have "…and so does the ruling of a PR left standing" \
    '--ruling "<the ruling, one line>; PR #<number> (<its anchor>) stands" --no-rework' "$EPIC_REVIEW"
have "…so the final sign-off reaches none of those PRs and takes no PR answer" \
    'the sign-off reaches none of those PRs and takes none of `--rework`, `--no-rework` or `--retire`' "$EPIC_REVIEW_JOINED"
lacks "…and gives none of the PR answers again" 'that answer took' "$EPIC_REVIEW_JOINED" \
    "a sign-off under the review's ruling would answer a gate still open under that ruling, and two retirements under one ruling share one record"
have "a subject that is a PR's anchor is the exception, because the writer reaches it on every call" \
    "A subject that is itself a PR's anchor is the exception, because every call reaches it." "$EPIC_REVIEW_JOINED"
have "…so each call under the review's own ruling gives that PR's answer, write 2's answer to the Deliveries' gates among them" \
    "Each call under the review's own ruling gives that PR's answer, as the settle step gives it, and those are write 2's answer to the Deliveries' gates, write 5's to a re-homed bead's gate, and the sign-off." "$EPIC_REVIEW_JOINED"
have "…which write 2's call gives beside the Deliveries' gates" \
    "# and, when the subject is a PR's anchor, that PR's answer (the section above)" "$EPIC_REVIEW"
have "…keeping its outcome to 95 characters when it leaves that PR standing, since the writer adds that it still needs an Approve" \
    "at most 140 characters, or 95 when it leaves the subject's PR standing>\" --no-wait" "$EPIC_REVIEW"
have "…the same ruling and answer each time, which the first call carries out and the later ones find done" \
    'Each gives the same ruling, word for word, and the same answer, so the first carries out a rework or a retirement, and the calls after it find it done.' "$EPIC_REVIEW_JOINED"
have "…with the subject's gate left to the sign-off, unless a close retires the PR, when write 5 answers it before the closes" \
    "The subject's gate takes no call of its own, and the sign-off answers it, unless a close retires the PR. Then write 5 answers that gate on a call of its own, as write 2 answers one" "$EPIC_REVIEW_JOINED"
have "…and a re-home into another rig's store files the new bead before the first of those calls, each of which names it as the successor" \
    "When that answer re-homes the PR into another rig's store, each call names the new bead as its successor, so file that bead there first, as write 5 files one." "$EPIC_REVIEW_JOINED"
have "…while a call under another PR's ruling leaves the subject's PR standing, and what it prints about that PR is not passed on" \
    "A call under another PR's ruling leaves it standing, and what that call prints about the subject's PR is no answer for it, so pass on only its lines about the PR it names." "$EPIC_REVIEW_JOINED"
have "…so a retirement on its own call keeps its outcome to 95 characters too when it leaves the subject's PR standing" \
    "--retire <kind> --outcome \"<where the epic stands now, at most 140 characters, or 95 when it leaves the subject's PR standing>\" --no-wait" "$EPIC_REVIEW"
have "every close runs through the close gate" \
    '"$CONV/finalize-gate.sh" check <bead> && gc bd close <bead> --reason' "$EPIC_REVIEW"
lacks "…and none is forced" '--force' "$EPIC_REVIEW" \
    "bd refuses a close over an open child or a live blocker, and the review settles what holds the bead instead"
have "the next Delivery is filed after the epic's open Deliveries are listed" \
    'select(.issue_type == "epic" and .status != "closed")' "$EPIC_REVIEW"
have "what sits under a bead is read off its parent-child edges, as bd's close reads it" \
    'gc bd dep list <bead> --direction=up -t parent-child --json' "$EPIC_REVIEW"
lacks "…never off bd's parent filter, which also returns a bead moved out from under it" 'gc bd list --parent' "$EPIC_REVIEW" \
    "a bead whose parent edge was removed still lists under the parent its id names, so a close would wait on work that has left"
have "…as an epic under the epic, opening with its aim" \
    'gc bd create "Delivery: <what it lands>" -t epic --parent "$EPIC"' "$EPIC_REVIEW"
have "the next priority uses the steering move" '"$CONV/gc-helm.sh" priority "$EPIC" <P0-P4>' "$EPIC_REVIEW"
have "…and so does the park" '"$CONV/gc-helm.sh" park "$EPIC"' "$EPIC_REVIEW"
have "an unpark releases the epic by write 3's release step" \
    "A ruling that unparks the epic releases it from its park instead, by write 3's release step with \`\"\$EPIC\"\` as the bead." "$EPIC_REVIEW_JOINED"
have "…which takes only the epic's edge off a gate another bead waits on" 'gc bd dep remove "$EPIC" <park>' "$EPIC_REVIEW"
have "the release lists what else waits on the park, and says so when nothing does" \
    'if length == 0 then "nothing else waits on it" else .[] end' "$EPIC_REVIEW"
have "…and never closes a blocker that is not a park's own gate" \
    "A blocker that is not a park's own gate never closes here" "$EPIC_REVIEW_JOINED"
fenced_block "$EPIC_REVIEW" '--append-notes "$RECORD"' | fill_block >"$CH/block"
[ -s "$CH/block" ] && ok "the review record's block is found" \
    || bad "the review record's block is found" "no fenced bash block holds its append in $EPIC_REVIEW"
for sh_ in $shells; do
    run=$sh_
    [ "$sh_" = zsh ] && run="zsh -f"
    rc=$(run_chain "$run" "$CH/block")
    if [ "$rc" -eq 0 ] && head -n 1 "$CH/notes" | grep -qE '^## Epic review, [0-9]{4}-[0-9]{2}-[0-9]{2}$' \
        && grep -qxF 'Ruling: x. x' "$CH/notes" && grep -qxF 'Contract lacked: x' "$CH/notes" \
        && grep -q '^gc bd update tk-e --append-notes ' "$CH/log"; then
        ok "($sh_) converse-epic-review: the record lands on the epic under its dated heading"
    else
        bad "($sh_) converse-epic-review: the record lands on the epic under its dated heading" "exit $rc, notes: $(head -c 400 "$CH/notes")"
    fi
    sed 's/^Measures: x$/Measures: the `echo ran` and $HOME stay as written/' "$CH/block" >"$CH/literal-block"
    rc=$(run_chain "$run" "$CH/literal-block")
    if [ "$rc" -eq 0 ] && grep -qxF 'Measures: the `echo ran` and $HOME stay as written' "$CH/notes"; then
        ok "($sh_) converse-epic-review: what the record quotes stays as written"
    else
        bad "($sh_) converse-epic-review: what the record quotes stays as written" "exit $rc, notes: $(head -c 400 "$CH/notes")"
    fi
    rc=$(run_chain "$run" "$CH/block" 1)
    if [ "$rc" -ne 0 ] && [ ! -s "$CH/notes" ]; then
        ok "($sh_) converse-epic-review: a record the store refuses is not reported as written"
    else
        bad "($sh_) converse-epic-review: a record the store refuses is not reported as written" "exit $rc"
    fi
done
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
while read -r s; do
    [ -r "$SKILLS/$s/SKILL.md" ] && ok "$s: the skill the step table names exists" \
        || bad "$s: the skill the step table names exists" "no $SKILLS/$s/SKILL.md"
done <"$TMP/by-name"

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
