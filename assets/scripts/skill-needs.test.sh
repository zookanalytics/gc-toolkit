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
# a real need used, and one that passes still has to read well.
#
# The same file pins the skills' shape: each names its neighbors, keeps
# converse's vocabulary out of its description, and calls every writer as the
# pack's own copy through the pack command `gc gc-toolkit scripts-dir`. It pins
# that command, and that the converse steps give the exact command for each act
# they name while the skills explain the act once.
#
# Hermetic: reads the repo, and runs the pack command and the writer call shape
# in a temporary directory outside any git repo, with a stub gc.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/../.."
SKILLS="$REPO/skills"
PROMPT="$REPO/agents/_converse/prompt.template.md"
SETTLE="$REPO/skills/converse-settle/SKILL.md"
MECHANIK="$REPO/agents/mechanik/prompt.template.md"
WORK_SKILL="$REPO/skills/work/SKILL.md"
DESIGN_DOC="$REPO/docs/design-convoy.md"
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
    [ "${#desc}" -le 1024 ] && ok "$s: description fits the 1024-character limit" \
        || bad "$s: description fits the 1024-character limit" "${#desc} characters"
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

echo "── each building-block skill calls the pack's own writers, never a checkout's ──"
# A skill's writers are the pack's own scripts. The pack command
# commands/scripts-dir prints their directory from GC_PACK_DIR, which gc sets
# to the pack it loaded, so an example calls "$(gc gc-toolkit scripts-dir)/<writer>"
# inside the one command that runs it. Nothing looks in the rig checkout or the
# caller's git toplevel, which can be a branch's worktree, and nothing relies on
# a variable an earlier tool call set, since each call starts a fresh shell.
ROOT="$(cd "$REPO" && pwd)"
RESOLVE='"$(gc gc-toolkit scripts-dir)/'
for s in $BLOCKS; do
    f="$SKILLS/$s/SKILL.md"
    [ -r "$f" ] || continue
    found=""
    for probe in 'GC_RIG_ROOT' 'rev-parse --show-toplevel' 'CONV' '"$S/' 'GC_CITY_PATH/rigs'; do
        grep -qF -- "$probe" "$f" && found="$found [$probe]"
    done
    [ -z "$found" ] && ok "$s: looks for no writer in a checkout or a variable an earlier call set" \
        || bad "$s: looks for no writer in a checkout or a variable an earlier call set" "found:$found"
    refs=$(grep -oF -- "$RESOLVE" "$f" | wc -l | tr -d ' ')
    writers=$(grep -oE '"\$\(gc gc-toolkit scripts-dir\)/[A-Za-z0-9._-]+"' "$f" | sed 's#.*/##; s#"$##' | sort -u)
    [ "${refs:-0}" -gt 0 ] && ok "$s: calls its writers through gc gc-toolkit scripts-dir (calls: $refs)" \
        || bad "$s: calls its writers through gc gc-toolkit scripts-dir" "no $RESOLVE<writer>\" call found"
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

echo "── gc gc-toolkit scripts-dir prints the scripts of the pack gc loaded ──"
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
# gc runs a pack command with GC_PACK_DIR set to the pack's root and the
# caller's arguments, so a stub gc that does the same for this one command
# stands in for it. The call shape then holds in a fresh bash and zsh, and when
# the command cannot answer, the writer path names no file and the call fails.
mkdir -p "$TMP/stub-ok" "$TMP/stub-fail"
cat >"$TMP/stub-ok/gc" <<STUB
#!/usr/bin/env bash
[ "\$1 \$2" = "gc-toolkit scripts-dir" ] || { echo "gc: unknown command \\"\$1\\"" >&2; exit 1; }
GC_PACK_DIR="$ROOT" exec "$CMD"
STUB
printf '#!/usr/bin/env bash\necho "gc: unknown command \\"$1\\"" >&2\nexit 1\n' >"$TMP/stub-fail/gc"
chmod +x "$TMP/stub-ok/gc" "$TMP/stub-fail/gc"
printf '%s\n' 'printf "%s" "$(gc gc-toolkit scripts-dir)/gc-helm.sh"' >"$TMP/call-path"
printf '%s\n' '"$(gc gc-toolkit scripts-dir)/gc-helm.sh" --help >/dev/null 2>&1' >"$TMP/call-writer"
shells="bash"
command -v zsh >/dev/null 2>&1 && shells="bash zsh"
for sh_ in $shells; do
    run=$sh_
    [ "$sh_" = zsh ] && run="zsh -f"
    got=$(cd "$TMP/away" && env -u GC_PACK_DIR -u BASH_ENV -u ENV PATH="$TMP/stub-ok:$PATH" $run "$TMP/call-path" 2>/dev/null)
    [ "$got" = "$ROOT/assets/scripts/gc-helm.sh" ] && ok "($sh_) the call resolves to the pack's own writer" \
        || bad "($sh_) the call resolves to the pack's own writer" "resolved '$got'"
    if (cd "$TMP/away" && env -u GC_PACK_DIR -u BASH_ENV -u ENV PATH="$TMP/stub-ok:$PATH" $run "$TMP/call-writer") 2>/dev/null; then
        ok "($sh_) the resolved writer runs"
    else
        bad "($sh_) the resolved writer runs" "gc-helm.sh --help through the call failed"
    fi
    if [ -e /gc-helm.sh ]; then
        bad "($sh_) a call whose pack command cannot answer fails" "/gc-helm.sh exists on this host, so the case cannot tell"
    elif (cd "$TMP/away" && env -u GC_PACK_DIR -u BASH_ENV -u ENV PATH="$TMP/stub-fail:$PATH" $run "$TMP/call-writer") 2>/dev/null; then
        bad "($sh_) a call whose pack command cannot answer fails" "it exited 0"
    else
        ok "($sh_) a call whose pack command cannot answer fails"
    fi
done

echo "── a step that names an act gives its exact command, and the skill explains it once ──"
lacks() {
    if grep -qF -- "$2" "$3"; then bad "$1" "$4"; else ok "$1"; fi
}
have() {
    if grep -qF -- "$2" "$3"; then ok "$1"; else bad "$1" "missing: $2"; fi
}
have "the step table points acting on a ruling at the skills" '`work`, `waits`, `records`, `prs`' "$PROMPT"
have "the record step gives the append it runs" 'gc bd update "$SUBJECT" --append-notes' "$SETTLE"
have "the settle step gives the create and the sling for routed work" 'gc sling <rig>/<pool> "$WORK" --on <formula>' "$SETTLE"
have "the settle step gives the subject's parent lookup" 'converse-parent.sh" "$SUBJECT"' "$SETTLE"
have "the settle step gives the arm it names" 'deferred-dispatch.sh" arm <follow-up>' "$SETTLE"
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
# The skill descriptions every agent sees already say what each skill covers,
# so a prompt says it once or not at all, and no prompt singles out one formula.
lacks "the mechanik prompt does not restate the skills" 'Each act of asking for work is an option in a skill' "$MECHANIK" \
    "the skill descriptions reach the mechanik at session start"
lacks "the mechanik prompt does not single out a design-first initiative" 'design-first initiative' "$MECHANIK" \
    "choosing a formula is the work skill's option"
lacks "the converse prompt does not single out a design-convoy" 'design-convoy included' "$PROMPT" \
    "choosing a formula is the work skill's option"
lacks "the prompt no longer carries the design-convoy questions" 'design-convoy-routing' "$PROMPT" \
    "choosing the formula is the work skill's option"
have "the work skill reads the formulas a rig has now" 'gc formula list --rig <rig>' "$WORK_SKILL"
lacks "the work skill's formula choice carries no one formula's variables" 'design_gated' "$WORK_SKILL" \
    "a formula's own doc says when it fits and how to tune it"
have "the design-convoy doc says when to reach for one" 'high-blast-radius' "$DESIGN_DOC"

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
