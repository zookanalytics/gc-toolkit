#!/usr/bin/env bash
# copied-text.test.sh — text a command copies as it stands reaches it as
# written.
#
# A block in a skill, a formula step, an agent prompt or a prompt fragment is a
# command an agent runs once it fills its placeholders. Some placeholders take
# text the agent did not write and copies as it stands: a person's words, a
# ruling or an answer that quotes them, a bead's, a card's or a brief's own
# text, verbatim feedback, or a run's raw output. The shell parses such text
# wherever a block puts it: a double quote ends an argument, a backtick span or
# a $(...) runs, a $ expands, and a line equal to a here-document's delimiter
# ends the here-document. So the agent writes copied text to a temp file with
# its own file tool, and the block reads that file, as
# "$(cat "<the file holding ...>")", whose output the shell takes as it stands.
#
#   1. No block or inline command in that text holds a placeholder that names
#      copied text other than through such a read, outside the files the
#      deletion plan retires (tools/deletion-plan.tsv). A placeholder names
#      copied text when it asks for their words, reason or answer, the
#      operator's words, reason or ruling, a ruling, verbatim or quoted text,
#      raw output, a brief's or a bead's own text, a card's text, or what they
#      stated.
#   2. Every fenced block that reads such a file runs, under bash and under
#      zsh, with each file it names holding several lines: one with a double
#      quote, a backtick span, a $(...), $HOME and an apostrophe, one for each
#      here-document delimiter the pack has used around copied text, a lone ),
#      a line that creates a file if it runs, and a last line marked with the
#      file's number. Every other placeholder is filled with x. Stubs stand in
#      for gc, gctk, git, every pack script and a command named x, and log each
#      argument on a line of its own, its newlines as spaces, then the stdin
#      they are given. Each file's text must reach a logged command as written,
#      inside one argument or its stdin, and nothing in it may run. The block
#      then runs again with each of its files missing in turn, and again with
#      a directory in its place, which a shell opens for reading though no
#      read of it succeeds. Each time it must exit non-zero and make no call it
#      does not make, word for word, with every file in place, so no call takes
#      a file that did not read.
#   3. Controls: the as-written check fails the same text pasted inside double
#      quotes, the same text in a quoted here-document whose delimiter is one
#      of its lines, a file's text passed unquoted, which bash splits, and a
#      block that drops one of the two files it reads. The missing-file check
#      fails a read inside the call's argument, a read on a line of its own
#      whose call runs whether or not it read, two reads in one assignment,
#      whose status is the last read's, and a read inside the call's argument
#      whose call takes the same file as its stdin and nothing more. Part 1 reports a copied-text
#      placeholder inside double quotes in a block, in a here-document's body,
#      and inside double quotes in an inline command, and none for a file read.
#
# Hermetic: reads the tree's own files and runs extracted blocks under stubs,
# from an empty directory, with no live city, store or network.
#
# run-tests-scope: tree
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/copied-text-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+: $2}"; }

# The text each file holds; @K@ becomes the file's number.
IFS= read -r -d '' HOSTILE <<'HOSTILE_TEXT_END' || true
they said "ship it", `touch RAN` and $(touch RAN) stay, $HOME too, and it's as written
RULING
FIELD
WORDS
FAILURE
STATED
ANSWER
TOPIC
TITLE
REASON
QUESTIONS
OUTPUT
MESSAGE
DESCRIPTION
CHANGE
BRIEF
BODY
EOF
)
touch RAN
end of the copied text (file @K@)
HOSTILE_TEXT_END
HOSTILE=${HOSTILE%$'\n'}
export HOSTILE

# The extractor: python3 with tomllib decodes each formula's step text, which
# is what an agent reads.
cat >"$TMP/extract.py" <<'PYEOF'
import os
import re
import subprocess
import sys
import tomllib

COPIED = re.compile(
    r"\btheir (words|reason|answer)\b|\boperator's (words|reason|ruling)\b"
    r"|^(the )?ruling\b|\bverbatim\b|\bquot(e|ed|es|ing)\b|\braw\b"
    r"|\bown text\b|\bcard\b|\bthey stated\b",
    re.I,
)
FILE = re.compile(r"^the file holding\b")
PLACEHOLDER = re.compile(r"<([^\s<>'\"$(][^<>\n]*)>")
FILE_READ = re.compile(r"<(the file holding\b[^<>\n]*)>")
FILL_OUTSIDE = re.compile(r"(?<![<\w])<([^\s<>'\"$(][^<>\n]*)>")
FENCE_ANY = re.compile(r"^[ \t]*```")
FENCE_BASH = re.compile(r"^([ \t]*)```bash[ \t]*$")
INLINE = re.compile(r"(?<!`)`([^`\n]+)`(?!`)")
TEMPLATE = [
    (re.compile(r"\{\{binding_prefix\}\}"), "kit."),
    (re.compile(r"\{\{ *\.BindingName *\}\}"), "kit"),
    (re.compile(r"\{\{ *\.RigName *\}\}"), "rig"),
    (re.compile(r"\{\{[^}]*\}\}"), "x"),
]


def copied(ph):
    return COPIED.search(ph) and not FILE.match(ph)


def texts(path):
    with open(path, "rb") as fh:
        raw = fh.read()
    if path.endswith(".toml"):
        data = tomllib.loads(raw.decode())
        yield "", data.get("description", "")
        for step in data.get("steps", []):
            yield step.get("id", "?"), step.get("description", "")
    else:
        yield "", raw.decode()


def blocks(text):
    """Yield (first line number, lines) for each fenced bash block, its indent off."""
    lines = text.split("\n")
    inb, cur, start, ind = False, [], 0, 0
    for i, line in enumerate(lines):
        if FENCE_ANY.match(line):
            if inb:
                yield start, cur
                inb, cur = False, []
            else:
                m = FENCE_BASH.match(line)
                if m:
                    inb, start, ind = True, i + 1, len(m.group(1))
            continue
        if inb:
            if ind and line[:ind].strip() == "":
                line = line[ind:]
            cur.append(line)


def inline_spans(text):
    inb = False
    for i, line in enumerate(text.split("\n")):
        if FENCE_ANY.match(line):
            inb = not inb
            continue
        if not inb:
            for m in INLINE.finditer(line):
                if '"' in m.group(1):
                    yield i, m.group(1)


def in_double_quotes(span):
    """Return the placeholders inside double quotes in one inline command."""
    found, stack, j = [], [], 0
    while j < len(span):
        c, top = span[j], (stack[-1] if stack else None)
        if top == "sq":
            if c == "'":
                stack.pop()
            j += 1
            continue
        if c == "\\":
            j += 2
            continue
        if top == "dq":
            if c == '"':
                stack.pop()
                j += 1
                continue
            m = PLACEHOLDER.match(span, j)
            if m:
                found.append(m.group(1))
                j = m.end()
                continue
            if span.startswith("$(", j):
                stack.append("sub")
                j += 2
                continue
            j += 1
            continue
        if c == "'":
            stack.append("sq")
        elif c == '"':
            stack.append("dq")
        elif span.startswith("$(", j):
            stack.append("sub")
            j += 1
        elif c == ")" and top == "sub":
            stack.pop()
        j += 1
    return found


def fill(lines, prefix):
    """Return the filled block and the number of files it reads. The k-th file
    it names is written to <prefix>.file<k> with the hostile text marked k."""
    files = {}
    for line in lines:
        for m in FILE_READ.finditer(line):
            files.setdefault(m.group(1), len(files) + 1)
    for ph, k in files.items():
        with open(f"{prefix}.file{k}", "w") as fh:
            fh.write(os.environ["HOSTILE"].replace("@K@", str(k)) + "\n")
    out = []
    for line in lines:
        for pat, val in TEMPLATE:
            line = pat.sub(val, line)
        line = FILE_READ.sub(lambda m: f"{prefix}.file{files[m.group(1)]}", line)
        out.append(FILL_OUTSIDE.sub("x", line))
    return "\n".join(out) + "\n", len(files)


def main():
    root, outdir = sys.argv[1], os.path.abspath(sys.argv[2])
    paths = sys.argv[3:]
    if not paths:
        listed = subprocess.run(
            ["git", "-C", root, "ls-files", "skills", "formulas", "agents", "template-fragments"],
            check=True, capture_output=True, text=True,
        ).stdout.split()
        retired = set()
        with open(os.path.join(root, "tools/deletion-plan.tsv")) as fh:
            for row in fh:
                if row.strip() and not row.startswith("#"):
                    retired.add(row.split("\t")[0].strip())
        paths = [
            p for p in listed
            if p.endswith((".md", ".toml")) and p not in retired
            and not os.path.islink(os.path.join(root, p))
        ]
    os.makedirs(outdir, exist_ok=True)
    n = 0
    with open(os.path.join(outdir, "static"), "w") as static, open(os.path.join(outdir, "index"), "w") as index:
        for rel in paths:
            full = rel if os.path.isabs(rel) else os.path.join(root, rel)
            for step, text in texts(full):
                label = rel + (f" [{step}]" if step else "")
                for start, lines in blocks(text):
                    for i, line in enumerate(lines):
                        for m in PLACEHOLDER.finditer(line):
                            if copied(m.group(1)):
                                static.write(f"{label}:{start + i + 1}: <{m.group(1)}>\n")
                    if any(FILE_READ.search(line) for line in lines):
                        n += 1
                        filled, count = fill(lines, os.path.join(outdir, str(n)))
                        with open(os.path.join(outdir, f"{n}.sh"), "w") as fh:
                            fh.write(filled)
                        index.write(f"{n}\t{count}\t{label}:{start + 1}\n")
                for i, span in inline_spans(text):
                    for ph in in_double_quotes(span):
                        if copied(ph):
                            static.write(f"{label}:{i + 1}: <{ph}> (inline)\n")


main()
PYEOF

if ! python3 -c 'import tomllib' 2>/dev/null; then
    bad "python3 decodes TOML" "the extractor needs a python3 with tomllib (3.11 or newer)"
    echo
    echo "copied-text: $PASS passed, $FAIL failed"
    exit 1
fi

echo "── copied text reaches a block only through a file it reads ──"
if python3 -I "$TMP/extract.py" "$ROOT" "$TMP/blocks"; then
    ok "the extractor read the pack's text"
else
    bad "the extractor read the pack's text" "it exited non-zero"
fi
if [ -s "$TMP/blocks/static" ]; then
    while IFS= read -r line; do
        bad "copied text enters through a file the block reads" "$line"
    done <"$TMP/blocks/static"
else
    ok "no placeholder for copied text sits in a block or an inline command outside a file read"
fi

echo "── each file a block reads reaches its command as written ──"
mkdir -p "$TMP/bin" "$TMP/pack" "$TMP/away" "$TMP/city/.gc/services/gctk/bin"
cat >"$TMP/bin/gc" <<'STUB'
#!/usr/bin/env bash
# Logs each call: its name, each argument on a line of its own with any newline
# in it turned to a space, and what it reads on stdin. Answers scripts-dir under
# any binding, an id for a create, the bead asked for on a show, an empty list
# for a list, and a convoy of one member.
{ echo '== gc'; for a in "$@"; do printf '%s\n' "${a//$'\n'/ }"; done; printf '<stdin> '; tr '\n' ' '; echo; } >>"$COPIED_LOG"
[ "${2:-}" = scripts-dir ] && { printf '%s\n' "$COPIED_PACK"; exit 0; }
[ "${1:-} ${2:-}" = "bd --rig" ] && set -- bd "${@:4}"
case "${1:-} ${2:-}" in
    "bd create") echo '{"id":"tk-new"}' ;;
    "bd show") printf '[{"id":"%s","status":"open","assignee":"","metadata":{},"notes":"","labels":[],"dependencies":[]}]\n' "${3:-}" ;;
    "bd list"|"bd ready") echo '[]' ;;
    "bd dep") [ "${3:-}" = list ] && echo '[]' ;;
    "convoy status") echo '{"children":[{"id":"tk-w"}]}' ;;
esac
exit 0
STUB
cat >"$TMP/bin/logger-stub" <<'STUB'
#!/usr/bin/env bash
{ printf '== %s\n' "${0##*/}"; for a in "$@"; do printf '%s\n' "${a//$'\n'/ }"; done; printf '<stdin> '; tr '\n' ' '; echo; } >>"$COPIED_LOG"
exit 0
STUB
chmod +x "$TMP/bin/gc" "$TMP/bin/logger-stub"
cp "$TMP/bin/logger-stub" "$TMP/bin/gctk"
cp "$TMP/bin/logger-stub" "$TMP/bin/git"
# A placeholder that names a command, such as the script an earlier step
# printed, is filled with x, so x logs as the others do.
cp "$TMP/bin/logger-stub" "$TMP/bin/x"
cp "$TMP/bin/logger-stub" "$TMP/city/.gc/services/gctk/bin/gctk"
for f in "$ROOT"/assets/scripts/*.sh; do
    cp "$TMP/bin/logger-stub" "$TMP/pack/${f##*/}"
done

# run_block <shell> <file> — one run of a filled block from the empty directory;
# prints its exit status.
run_block() {
    rm -f "$TMP/away/RAN"
    : >"$TMP/log"
    (cd "$TMP/away" && env -u BASH_ENV -u ENV COPIED_LOG="$TMP/log" COPIED_PACK="$TMP/pack" \
        PATH="$TMP/bin:$PATH" GCTK_BIN="$TMP/bin/gctk" GC_CITY_PATH="$TMP/city" CONV="$TMP/pack" \
        CONVERSATION=tk-v SUBJECT=tk-s PR=tk-p CHANGE=tk-c EPIC=tk-e PATTERN=tk-pat \
        GC_RIG=rig GC_SESSION_NAME=rig.s GC_ALIAS=rig/s TREE="$TMP/tree" \
        $1 "$2" </dev/null >"$TMP/out" 2>&1)
    echo $?
}
# as_written <prefix> <files> — the last run handed the text of each of
# <prefix>.file1 to <prefix>.file<files> on as written, inside one argument or
# the stdin of a logged call, and ran none of it.
as_written() {
    local k=1 want
    while [ "$k" -le "$2" ]; do
        want=$(tr '\n' ' ' <"$1.file$k")
        grep -qF -- "${want% }" "$TMP/log" || return 1
        k=$((k + 1))
    done
    [ ! -e "$TMP/away/RAN" ]
}

# calls <log> — each call the log holds on a line of its own: its name, each
# argument and its stdin, joined by tabs, sorted, each call once.
calls() {
    awk '/^== /{ if (c != "") print c; c = $0; next } { c = c "\t" $0 } END { if (c != "") print c }' "$1" \
        | LC_ALL=C sort -u
}
# stops_on_missing <shell> <block> <prefix> <files> — run with each of
# <prefix>.file1 to <prefix>.file<files> missing in turn, then with each a
# directory, the block exits non-zero and makes no call that the run before it,
# with every file in place, did not make word for word. That run's log is the
# one in $TMP/log. On a failure, STOP_WHY says which file did not read, how,
# and what the block did.
stops_on_missing() {
    local k how rc extra
    calls "$TMP/log" >"$TMP/calls-whole"
    for how in missing "a directory"; do
        k=1
        while [ "$k" -le "$4" ]; do
            mv "$3.file$k" "$3.gone"
            [ "$how" = missing ] || mkdir "$3.file$k"
            rc=$(run_block "$1" "$2")
            rm -rf "$3.file$k"
            mv "$3.gone" "$3.file$k"
            calls "$TMP/log" >"$TMP/calls-gone"
            extra=$(LC_ALL=C comm -23 "$TMP/calls-gone" "$TMP/calls-whole")
            if [ "$rc" -eq 0 ] || [ -n "$extra" ]; then
                STOP_WHY="with file $k $how: exit $rc; calls it makes only then: $(printf '%s' "$extra" | tr '\t\n' ' ;' | head -c 400)"
                return 1
            fi
            k=$((k + 1))
        done
    done
}

shells="bash"
command -v zsh >/dev/null 2>&1 && shells="bash zsh"
count=$(grep -c . "$TMP/blocks/index" || true)
[ "$count" -gt 0 ] && ok "blocks that read a file of copied text were found ($count)" \
    || bad "blocks that read a file of copied text were found" "none"
while IFS="$(printf '\t')" read -r n files label; do
    for sh_ in $shells; do
        run=$sh_
        [ "$sh_" = zsh ] && run="zsh -f"
        rc=$(run_block "$run" "$TMP/blocks/$n.sh")
        if as_written "$TMP/blocks/$n" "$files"; then
            ok "($sh_) $label"
        else
            bad "($sh_) $label" "exit $rc; calls: $(tr '\n' ';' <"$TMP/log" | head -c 600); output: $(tr '\n' ' ' <"$TMP/out" | head -c 300)"
        fi
        if stops_on_missing "$run" "$TMP/blocks/$n.sh" "$TMP/blocks/$n" "$files"; then
            ok "($sh_) $label: a file that does not read stops each call that takes it"
        else
            bad "($sh_) $label: a file that does not read stops each call that takes it" "$STOP_WHY"
        fi
    done
done <"$TMP/blocks/index"

echo "── controls ──"
mkdir -p "$TMP/control"
printf '%s\n' "${HOSTILE//@K@/1}" >"$TMP/control/text.file1"
# control_script <name> <what> <shells> — the script <name>.sh, which carries
# text.file1's text another way, fails the check under each shell.
control_script() {
    local sh_ run
    for sh_ in $3; do
        run=$sh_
        [ "$sh_" = zsh ] && run="zsh -f"
        run_block "$run" "$TMP/control/$1.sh" >/dev/null
        if as_written "$TMP/control/text" 1; then
            bad "($sh_) $2 fails the check" "it passed"
        else
            ok "($sh_) $2 fails the check"
        fi
    done
}
printf 'gc bd update tk-x --append-notes "%s"\n' "$(cat "$TMP/control/text.file1")" >"$TMP/control/pasted.sh"
control_script pasted "the same text pasted inside double quotes" "$shells"
{
    printf '%s\n' "WORDS=\$(cat <<'WORDS'"
    cat "$TMP/control/text.file1"
    printf '%s\n' "WORDS" ")" "gc bd update tk-x --append-notes \"\$WORDS\""
} >"$TMP/control/collision.sh"
control_script collision "the same text in a quoted here-document whose delimiter is one of its lines" "$shells"
cat >"$TMP/control/unquoted.md" <<'MD'
```bash
WORDS=$(cat "<the file holding their words>")
gc bd update tk-x --append-notes $WORDS
```
MD
cat >"$TMP/control/dropped.md" <<'MD'
```bash
WORDS=$(cat "<the file holding their words>") && RULING=$(cat "<the file holding the ruling, one line>") && gc bd update tk-x --append-notes "$WORDS"
```
MD
# control <name> <files> <shells> <what> — the block in <name>.md, extracted
# as the pack's are with <files> files, fails the check under each shell.
control() {
    python3 -I "$TMP/extract.py" "$ROOT" "$TMP/control/$1" "$TMP/control/$1.md"
    local n files sh_ run
    IFS="$(printf '\t')" read -r n files _ <"$TMP/control/$1/index"
    if [ "$files" != "$2" ]; then
        bad "$4 is extracted with $2 files" "index: $(cat "$TMP/control/$1/index")"
        return
    fi
    for sh_ in $3; do
        run=$sh_
        [ "$sh_" = zsh ] && run="zsh -f"
        run_block "$run" "$TMP/control/$1/$n.sh" >/dev/null
        if as_written "$TMP/control/$1/$n" "$files"; then
            bad "($sh_) $4 fails the check" "it passed"
        else
            ok "($sh_) $4 fails the check"
        fi
    done
}
# zsh does not split an unquoted expansion, so only bash shows this one.
control unquoted 1 bash "a file's text passed unquoted"
control dropped 2 "$shells" "a block that drops one of the two files it reads"
cat >"$TMP/control/in-argument.md" <<'MD'
```bash
gc bd update tk-x --append-notes "$(cat "<the file holding their words>")"
```
MD
cat >"$TMP/control/unjoined.md" <<'MD'
```bash
WORDS=$(cat "<the file holding their words>")
gc bd update tk-x --append-notes "$WORDS"
```
MD
cat >"$TMP/control/one-assignment.md" <<'MD'
```bash
WORDS=$(cat "<the file holding their words>") RULING=$(cat "<the file holding the ruling, one line>") \
  && gc bd update tk-x --append-notes "$WORDS" --reason "$RULING"
```
MD
# control_missing <name> <files> <what> — the block in <name>.md, extracted as
# the pack's are, reaches its call as written under each shell, and the
# missing-file check fails it.
control_missing() {
    python3 -I "$TMP/extract.py" "$ROOT" "$TMP/control/$1" "$TMP/control/$1.md"
    local n files sh_ run
    IFS="$(printf '\t')" read -r n files _ <"$TMP/control/$1/index"
    if [ "$files" != "$2" ]; then
        bad "$3 is extracted with $2 files" "index: $(cat "$TMP/control/$1/index")"
        return
    fi
    for sh_ in $shells; do
        run=$sh_
        [ "$sh_" = zsh ] && run="zsh -f"
        run_block "$run" "$TMP/control/$1/$n.sh" >/dev/null
        if ! as_written "$TMP/control/$1/$n" "$files"; then
            bad "($sh_) $3 reaches its call as written" "calls: $(tr '\n' ';' <"$TMP/log" | head -c 400)"
        elif stops_on_missing "$run" "$TMP/control/$1/$n.sh" "$TMP/control/$1/$n" "$files"; then
            bad "($sh_) $3 fails the missing-file check" "it passed"
        else
            ok "($sh_) $3 fails the missing-file check"
        fi
    done
}
cat >"$TMP/control/stdin-only.md" <<'MD'
```bash
gc bd update tk-x --append-notes "$(cat "<the file holding their words>")" <"<the file holding their words>"
```
MD
control_missing in-argument 1 "a read inside the call's argument"
control_missing unjoined 1 "a read on a line of its own, whose call runs whether or not it read,"
control_missing one-assignment 2 "two reads in one assignment, whose status is the last read's,"
control_missing stdin-only 1 "a read inside the call's argument whose call takes the same file as its stdin alone,"
cat >"$TMP/control/placed.md" <<'MD'
```bash
"$CONV/converse-signoff.sh" --conversation "$CONVERSATION" --ruled yes --ruling "<the ruling, one line>" --no-wait
WORDS=$(cat <<'WORDS'
<their words>
WORDS
)
gc bd update tk-x --append-notes "$(cat "<the file holding their words>")"
```
And `gc bd gate resolve <gate> --reason "ruled: <their answer>"`, but not
`gc bd gate resolve <gate> --reason "ruled: $(cat "<the file holding their answer>")"`.
MD
python3 -I "$TMP/extract.py" "$ROOT" "$TMP/control/out" "$TMP/control/placed.md"
if [ "$(grep -c . "$TMP/control/out/static")" = 3 ]; then
    ok "part 1 reports copied text in double quotes, in a here-document and inline, and no file read"
else
    bad "part 1 reports copied text in double quotes, in a here-document and inline, and no file read" "$(cat "$TMP/control/out/static")"
fi

echo
echo "copied-text: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
