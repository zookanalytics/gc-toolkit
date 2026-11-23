#!/usr/bin/env bash
# copied-text.test.sh — text a command copies as it stands reaches it as
# written.
#
# A block in a skill, a formula step, an agent prompt or a prompt fragment is a
# command an agent runs once it fills its placeholders. Some placeholders take
# text the agent did not write and copies as it stands: a person's words, a
# ruling or an answer that quotes them, a bead's, a card's or a brief's own
# text, verbatim feedback, or a run's raw output. Pasted inside a double-quoted
# argument, a double quote in that text ends the argument, a backtick span or
# a $(...) runs as a command, and a $ expands. So each such placeholder sits
# alone in the body of a quoted here-document, whose text the shell hands on
# untouched, and the command takes what the here-document captured.
#
#   1. No block or inline command in that text puts a placeholder that names
#      copied text inside double quotes, or in the body of an unquoted
#      here-document, which expands it the same way, outside the files the
#      deletion plan retires (tools/deletion-plan.tsv). A placeholder names
#      copied text when it asks for their words, reason or answer, the
#      operator's words, reason or ruling, a ruling, verbatim or quoted text,
#      raw output, a brief's or a bead's own text, a card's text, or what they
#      stated.
#   2. Every fenced block whose quoted here-document holds a placeholder runs,
#      under bash and under zsh, with each placeholder in such a body filled
#      with text that holds a double quote, a backtick span, a $(...), $HOME
#      and an apostrophe, marked with the body's number, and every other
#      placeholder filled with x. Stubs stand in for gc, gctk, git, every pack
#      script and a command named x, and log each argument on a line of its
#      own, then the stdin they are given. Each body's text must reach a
#      logged command as written, inside one argument or its stdin, and
#      nothing in it may run.
#   3. Controls: that check fails the same text pasted inside double quotes, a
#      captured text passed unquoted, which bash splits, and a block that
#      drops one of its two bodies. Part 1 reports a copied-text placeholder
#      left inside double quotes.
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

IFS= read -r HOSTILE <<'TEXT'
they said "ship it", `touch RAN` and $(touch RAN) stay, $HOME too, and it's as written
TEXT
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
PLACEHOLDER = re.compile(r"<([^\s<>'\"$(][^<>\n]*)>")
FILL_OUTSIDE = re.compile(r"(?<![<\w])<([^\s<>'\"$(][^<>\n]*)>")
FENCE_ANY = re.compile(r"^[ \t]*```")
FENCE_BASH = re.compile(r"^([ \t]*)```bash[ \t]*$")
HEREDOC = re.compile(r"<<-?[ \t]*(?:'([A-Za-z_][A-Za-z0-9_]*)'|\"([A-Za-z_][A-Za-z0-9_]*)\"|\\([A-Za-z_][A-Za-z0-9_]*)|([A-Za-z_][A-Za-z0-9_]*))")
INLINE = re.compile(r"(?<!`)`([^`\n]+)`(?!`)")
TEMPLATE = [
    (re.compile(r"\{\{binding_prefix\}\}"), "kit."),
    (re.compile(r"\{\{ *\.BindingName *\}\}"), "kit"),
    (re.compile(r"\{\{ *\.RigName *\}\}"), "rig"),
    (re.compile(r"\{\{[^}]*\}\}"), "x"),
]


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


def walk(lines):
    """Return the placeholders that expand, as (line, text): inside double quotes
    or in the body of an unquoted here-document. Also the bodies of the quoted
    here-documents, as (start, end)."""
    found, bodies, stack = [], [], []
    i = 0
    while i < len(lines):
        line, j, pending = lines[i], 0, []
        while j < len(line):
            c = line[j]
            top = stack[-1] if stack else None
            if top == "sq":
                if c == "'":
                    stack.pop()
                j += 1
                continue
            if top == "dq":
                if c == "\\":
                    j += 2
                    continue
                if c == '"':
                    stack.pop()
                    j += 1
                    continue
                if line.startswith("$(", j):
                    stack.append("sub")
                    j += 2
                    continue
                if c == "`":
                    stack.append("bt")
                    j += 1
                    continue
                m = PLACEHOLDER.match(line, j)
                if m:
                    found.append((i, m.group(1)))
                    j = m.end()
                    continue
                j += 1
                continue
            if c == "\\":
                j += 2
                continue
            if c == "#" and (j == 0 or line[j - 1] in " \t;(|&"):
                break
            if c == "'":
                stack.append("sq")
                j += 1
                continue
            if c == '"':
                stack.append("dq")
                j += 1
                continue
            if line.startswith("$(", j):
                stack.append("sub")
                j += 2
                continue
            if c == "`":
                if top == "bt":
                    stack.pop()
                else:
                    stack.append("bt")
                j += 1
                continue
            if c == "(" and top in ("sub", "paren"):
                stack.append("paren")
                j += 1
                continue
            if c == ")" and top in ("sub", "paren"):
                stack.pop()
                j += 1
                continue
            m = HEREDOC.match(line, j)
            if m:
                quoted = m.group(4) is None
                pending.append((m.group(1) or m.group(2) or m.group(3) or m.group(4), quoted))
                j = m.end()
                continue
            j += 1
        i += 1
        for delim, quoted in pending:
            start = i
            while i < len(lines) and lines[i] != delim:
                if not quoted:
                    found.extend((i, m.group(1)) for m in PLACEHOLDER.finditer(lines[i]))
                i += 1
            if quoted:
                bodies.append((start, i))
            i += 1
    return found, bodies


def fill(lines, bodies):
    """Return the filled block and the number of bodies that hold a placeholder.
    The k-th such body takes the hostile text marked (body k)."""
    body_of, k = {}, 0
    for start, end in bodies:
        if any(PLACEHOLDER.search(lines[n]) for n in range(start, end)):
            k += 1
            body_of.update((n, k) for n in range(start, end))
    out = []
    for n, line in enumerate(lines):
        for pat, val in TEMPLATE:
            line = pat.sub(val, line)
        if n in body_of:
            text = f"{os.environ['HOSTILE']} (body {body_of[n]})"
            line = PLACEHOLDER.sub(lambda m: text, line)
        else:
            line = FILL_OUTSIDE.sub("x", line)
        out.append(line)
    return "\n".join(out) + "\n", k


def main():
    root, outdir = sys.argv[1], sys.argv[2]
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
                    found, bodies = walk(lines)
                    for i, ph in found:
                        if COPIED.search(ph):
                            static.write(f"{label}:{start + i + 1}: <{ph}>\n")
                    filled, count = fill(lines, bodies)
                    if count:
                        n += 1
                        with open(os.path.join(outdir, f"{n}.sh"), "w") as fh:
                            fh.write(filled)
                        index.write(f"{n}\t{count}\t{label}:{start + 1}\n")
                for i, span in inline_spans(text):
                    found, _ = walk([span])
                    for _, ph in found:
                        if COPIED.search(ph):
                            static.write(f"{label}:{i + 1}: <{ph}> (inline)\n")


main()
PYEOF

if ! python3 -c 'import tomllib' 2>/dev/null; then
    bad "python3 decodes TOML" "the extractor needs a python3 with tomllib (3.11 or newer)"
    echo
    echo "copied-text: $PASS passed, $FAIL failed"
    exit 1
fi

echo "── copied text never sits inside double quotes ──"
if python3 -I "$TMP/extract.py" "$ROOT" "$TMP/blocks"; then
    ok "the extractor read the pack's text"
else
    bad "the extractor read the pack's text" "it exited non-zero"
fi
if [ -s "$TMP/blocks/static" ]; then
    while IFS= read -r line; do
        bad "copied text enters through a quoted here-document" "$line"
    done <"$TMP/blocks/static"
else
    ok "no placeholder for copied text sits inside double quotes"
fi

echo "── each quoted here-document hands its text on as written ──"
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
# as_written <bodies> — the last run handed each body's text on as written,
# inside one argument or the stdin of a logged call, and ran none of it.
as_written() {
    local k=1
    while [ "$k" -le "$1" ]; do
        grep -qF -- "$HOSTILE (body $k)" "$TMP/log" || return 1
        k=$((k + 1))
    done
    [ ! -e "$TMP/away/RAN" ]
}

shells="bash"
command -v zsh >/dev/null 2>&1 && shells="bash zsh"
count=$(grep -c . "$TMP/blocks/index" || true)
[ "$count" -gt 0 ] && ok "blocks with a quoted here-document were found ($count)" \
    || bad "blocks with a quoted here-document were found" "none"
while IFS="$(printf '\t')" read -r n bodies label; do
    for sh_ in $shells; do
        run=$sh_
        [ "$sh_" = zsh ] && run="zsh -f"
        rc=$(run_block "$run" "$TMP/blocks/$n.sh")
        if as_written "$bodies"; then
            ok "($sh_) $label"
        else
            bad "($sh_) $label" "exit $rc; calls: $(tr '\n' ';' <"$TMP/log" | head -c 600); output: $(tr '\n' ' ' <"$TMP/out" | head -c 300)"
        fi
    done
done <"$TMP/blocks/index"

echo "── controls ──"
printf 'gc bd update tk-x --append-notes "%s (body 1)"\n' "$HOSTILE" >"$TMP/pasted.sh"
for sh_ in $shells; do
    run=$sh_
    [ "$sh_" = zsh ] && run="zsh -f"
    run_block "$run" "$TMP/pasted.sh" >/dev/null
    if as_written 1; then
        bad "($sh_) the same text pasted inside double quotes fails the check" "it passed"
    else
        ok "($sh_) the same text pasted inside double quotes fails the check"
    fi
done
mkdir -p "$TMP/control"
cat >"$TMP/control/unquoted.md" <<'MD'
```bash
RULING=$(cat <<'RULING'
<the ruling, one line>
RULING
)
gc bd update tk-x --append-notes $RULING
```
MD
cat >"$TMP/control/dropped.md" <<'MD'
```bash
WORDS=$(cat <<'WORDS'
<their words>
WORDS
) && RULING=$(cat <<'RULING'
<the ruling, one line>
RULING
) && gc bd update tk-x --append-notes "$WORDS"
```
MD
# control <name> <bodies> <shells> <what> — the block in <name>.md, extracted
# as the pack's are with <bodies> bodies, fails the check under each shell.
control() {
    python3 -I "$TMP/extract.py" "$ROOT" "$TMP/control/$1" "$TMP/control/$1.md"
    local n bodies sh_ run
    IFS="$(printf '\t')" read -r n bodies _ <"$TMP/control/$1/index"
    if [ "$bodies" != "$2" ]; then
        bad "$4 is extracted with $2 bodies" "index: $(cat "$TMP/control/$1/index")"
        return
    fi
    for sh_ in $3; do
        run=$sh_
        [ "$sh_" = zsh ] && run="zsh -f"
        run_block "$run" "$TMP/control/$1/$n.sh" >/dev/null
        if as_written "$bodies"; then
            bad "($sh_) $4 fails the check" "it passed"
        else
            ok "($sh_) $4 fails the check"
        fi
    done
}
# zsh does not split an unquoted expansion, so only bash shows this one.
control unquoted 1 bash "a captured text passed unquoted"
control dropped 2 "$shells" "a block that drops one of its two bodies"
cat >"$TMP/control/pasted.md" <<'MD'
```bash
"$CONV/converse-signoff.sh" --conversation "$CONVERSATION" --ruled yes --ruling "<the ruling, one line>" --no-wait
```
And `gc bd gate resolve <gate> --reason "ruled: <their answer>"`.
MD
python3 -I "$TMP/extract.py" "$ROOT" "$TMP/control/out" "$TMP/control/pasted.md"
if [ "$(grep -c . "$TMP/control/out/static")" = 2 ]; then
    ok "part 1 reports a copied-text placeholder inside double quotes, in a block and inline"
else
    bad "part 1 reports a copied-text placeholder inside double quotes, in a block and inline" "$(cat "$TMP/control/out/static")"
fi

echo
echo "copied-text: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
