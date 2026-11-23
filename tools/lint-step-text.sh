#!/usr/bin/env bash
# lint-step-text.sh — flags a change that adds a procedure to formula step text
# or to a skill.
#
# A formula step or a skill calls a tested script, and anything two of them
# need is one script (docs/pack-authoring.md, "Step text calls a tested
# script"). A shell block in step text or a skill that does more than make one
# call is a procedure: it holds control flow (if, elif, else, case, for,
# select, while, until, a function definition, && or ||), or more than one
# command. A sequence and a pipeline are more than one command, and so is a
# command substitution that holds more than one. A substitution holding a
# single command is an argument of the command around it, so
# `"$(gc <binding> scripts-dir)/foo.sh" --bead X` is one call. A placeholder
# outside a quote, such as <the PR's bead> or <approve|request-changes>, is one
# word, since the agent writes a value in its place, unless it holds shell
# syntax: a ; or an &, a parenthesis, a backquote, or a | that does not join two
# words. Then it is shell, as `sort <in.txt | uniq>out.txt` is. A cd that &&
# runs after a call weighs nothing, and neither does that &&: it moves the
# agent's own shell once the call exits 0, which no script can do for its
# caller. Between the markers of a gctk-bin block, an assignment to GCTK that
# runs no command weighs nothing, so the block and one "$GCTK" call are one
# call.
#
# The lint judges only what a change adds, so text that predates the rule
# passes until its own rewrite. It weighs each formula step, named by its id,
# and each skill, named by its directory and weighed whole across its files, by
# the commands and the control flow of the procedures its blocks hold, and
# fails a step or a skill that a change makes heavier in either count. A new
# step or skill fails when it holds a procedure at all. A block the change
# leaves alone, or moves without editing it, weighs nothing on either side, so
# a step or a skill that only gains single calls, or trades a procedure for a
# call, passes. A formula's blocks pair within its own file, and a skill's
# blocks with those of every skill file the change names, so a block moved from
# one skill to another weighs nothing either.
#
# The change runs from the merge base of BASE and HEAD to the working tree,
# the change `git diff --name-only BASE...HEAD` names for the rig's
# lint_command. Each FILE that is a formula (formulas/*.toml, or a sub-pack's
# <dir>/formulas/*.toml) or a Markdown file of a skill (skills/<name>/...*.md,
# or a sub-pack's or an agent's <dir>/skills/<name>/...*.md) is checked, any
# other FILE is ignored, and a renamed file is compared with its old path. A
# skill file that is a symlink is skipped, since its text is the file it points
# to, such as a prompt fragment. A skill file the change deletes keeps its old
# blocks, so a block moved out of it pairs. A FILE is a path from the top of
# the repository, as git prints it.
#
# The agent reads step text as TOML decodes it, and so does the lint. Python's
# tomllib decodes each string in the file, whatever its kind and wherever it
# sits, so an escape such as `\n` or `\\` reads as what it stands for, and a
# backslash that ends a line of a multi-line basic string joins the next line
# to it. The lint finds each string in the file to tie its text to the file's
# lines. When the strings it finds are not all the strings tomllib reads in the
# file, it cannot operate. A skill is Markdown, read line by line, with a
# control character other than a tab read as a blank. Only a block fenced as
# bash, sh, shell, zsh, ksh or dash, in any case, holds commands, and a fence of
# backticks or tildes is read as CommonMark reads it. A block a TOML string or a
# skill file leaves open ends where it does. A here-document's body is data,
# except where no part of its delimiter is quoted. The shell then expands the
# body, so a command substitution in it weighs as one in an argument does.
#
# Usage: lint-step-text.sh [--base REV] [FILE ...]
#   --base REV  the revision a change is measured from (default: origin/main)
#
# Output: each finding as `<file>:<line>: <message>`, then one summary line.
# Exit: 0 no finding; 1 a finding; 2 it could not operate (not a repository, a
#       BASE git cannot read, a file it cannot read or parse, or no Python 3.11
#       or newer on PATH to decode a formula's TOML, which a change that names
#       no formula does not need).

set -uo pipefail

PROG=lint-step-text
BASE=origin/main

usage() {
  cat >&2 <<'EOF'
Usage: lint-step-text.sh [--base REV] [FILE ...]
  --base REV  the revision a change is measured from (default: origin/main)
EOF
}

files=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --base)
      [ "$#" -ge 2 ] || { echo "$PROG: --base needs a revision" >&2; usage; exit 2; }
      BASE=$2; shift 2 ;;
    --base=*) BASE=${1#--base=}; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; files+=("$@"); break ;;
    -*) echo "$PROG: unknown option '$1'" >&2; usage; exit 2 ;;
    *) files+=("$1"); shift ;;
  esac
done

if ! ROOT=$(git rev-parse --show-toplevel 2>/dev/null); then
  echo "$PROG: not inside a git repository" >&2
  exit 2
fi
cd "$ROOT" || { echo "$PROG: cannot enter repo root $ROOT" >&2; exit 2; }

# is_skill_text <path> — whether the path is a Markdown file of a skill.
is_skill_text() {
  case "$1" in
    skills/*/*.md | */skills/*/*.md) return 0 ;;
  esac
  return 1
}

# skill_dir <path> — the directory of the skill a skill file belongs to,
# <prefix>skills/<name>, which names the skill.
skill_dir() {
  local pre rest
  case "$1" in
    skills/*) pre=""; rest=${1#skills/} ;;
    *) pre=${1%%/skills/*}/; rest=${1#"$pre"skills/} ;;
  esac
  printf '%sskills/%s\n' "$pre" "${rest%%/*}"
}

formulas=(); skills=()
for f in ${files[@]+"${files[@]}"}; do
  f=${f#./}
  case "$f" in
    formulas/*.toml | */formulas/*.toml) [ -f "$f" ] && formulas+=("$f") ;;
    *) is_skill_text "$f" && [ ! -L "$f" ] && skills+=("$f") ;;
  esac
done
if [ "${#formulas[@]}" -eq 0 ] && [ "${#skills[@]}" -eq 0 ]; then
  echo "$PROG: no formula or skill file given"
  exit 0
fi
if ! BASE_OID=$(git rev-parse -q --verify "$BASE^{commit}"); then
  echo "$PROG: cannot read base revision '$BASE', so the lines a change adds are unknown" >&2
  exit 2
fi
if ! MERGE_BASE=$(git merge-base "$BASE_OID" HEAD); then
  echo "$PROG: HEAD shares no history with '$BASE'" >&2
  exit 2
fi

# A Python whose standard library has tomllib (3.11 and newer) decodes a
# formula's TOML: python3, or else the newest python3.N on PATH.
PY=""
if [ "${#formulas[@]}" -gt 0 ]; then
  for name in python3 $(compgen -c python3. 2>/dev/null | grep -xE 'python3\.[0-9]+' | sort -t. -k2,2nr -u); do
    cand=$(command -v "$name") || continue
    "$cand" -I -c 'import tomllib' >/dev/null 2>&1 && { PY=$cand; break; }
  done
  if [ -z "$PY" ]; then
    echo "$PROG: decoding a formula's TOML needs a Python with tomllib (3.11 or newer), and PATH has none" >&2
    exit 2
  fi
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/gctk-lint-step-text.XXXXXX") || exit 2
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP

# DECODE_PY reads a formula file and prints its strings as the agent reads
# them. It finds each string in the file, of any of TOML's four kinds, outside
# the comments, and decodes it with the place each character came from. That
# decoding must equal tomllib's, and the strings it finds must hold every
# string tomllib reads in the file. It prints, for each step,
# `S<FS>step<FS>id<FS>line`, and then, for each string, `T<FS>step` for the
# step it sits in, `R<FS>lines<FS>text` for each line of its decoded text with
# the file lines that line came from, and `E`. A step is each [[steps]] table,
# named by its id. Text before the first one is the formula's own, step 0 with
# an empty name.
DECODE_PY=$(cat <<'PYEOF'
import bisect, collections, re, sys, tomllib

def fail(msg):
    sys.stderr.write(msg + "\n")
    sys.exit(1)

try:
    with open(sys.argv[1], "rb") as fh:
        src = fh.read().decode("utf-8")
    doc = tomllib.loads(src)
except (OSError, UnicodeDecodeError, tomllib.TOMLDecodeError) as err:
    fail(str(err))
src = src.replace("\r\n", "\n")
n = len(src)
eols = [m.start() for m in re.finditer("\n", src)]

def line(pos):
    return bisect.bisect_left(eols, pos) + 1

# Each string as (start, end, delimiter), and where each [[steps]] line starts.
# A closing delimiter of three quotes can follow up to two quotes the string
# holds.
HEADER = re.compile(r"[ \t]*\[\[[ \t]*(?:steps|\"steps\"|'steps')[ \t]*\]\][ \t]*(?:#.*)?$")
tokens, headers, i = [], [], 0
while i < n:
    if i == 0 or src[i - 1] == "\n":
        end = src.find("\n", i)
        if HEADER.match(src, i, n if end < 0 else end):
            headers.append(i)
    c = src[i]
    if c == "#":
        end = src.find("\n", i)
        i = n if end < 0 else end
    elif c in "\"'":
        q = c * 3 if src.startswith(c * 3, i) else c
        j = i + len(q)
        while not src.startswith(q, j):
            if j >= n or (len(q) == 1 and src[j] == "\n"):
                fail(f"line {line(i)}: a string the lint finds no end of")
            j += 2 if c == '"' and src[j] == "\\" else 1
        if len(q) == 3:
            for _ in range(2):
                if src.startswith(c, j + 3):
                    j += 1
        tokens.append((i, j + len(q), q))
        i = j + len(q)
    else:
        i += 1

ESCAPES = {"b": "\b", "t": "\t", "n": "\n", "f": "\f", "r": "\r", "e": "\x1b", '"': '"', "\\": "\\"}
HEX = {"x": 2, "u": 4, "U": 8}

# A string's decoded characters, each with the place it came from, or None on
# an escape this does not know. A multi-line string drops the newline that
# follows its opening delimiter.
def decode(start, end, q):
    pos, stop, out = start + len(q), end - len(q), []
    if len(q) == 3 and src.startswith("\n", pos):
        pos += 1
    while pos < stop:
        ch = src[pos]
        if ch == "\\" and q[0] == '"':
            nx = src[pos + 1]
            if nx in " \t\n":
                pos += 1
                while pos < stop and src[pos] in " \t\n":
                    pos += 1
            elif nx in ESCAPES:
                out.append((ESCAPES[nx], pos))
                pos += 2
            elif nx in HEX:
                try:
                    out.append((chr(int(src[pos + 2:pos + 2 + HEX[nx]], 16)), pos))
                except ValueError:
                    return None
                pos += 2 + HEX[nx]
            else:
                return None
            continue
        out.append((ch, pos))
        pos += 1
    return out

# A control character other than a tab reads as a blank, so no text carries
# the record separators.
PLAIN = {c: " " for c in list(range(32)) + [127] if c != 9}

def rendered(text, lines):
    span = " ".join(str(x) for x in range(lines[0], lines[-1] + 1))
    return "R\x1c" + span + "\x1c" + "".join(text).translate(PLAIN)

steps = doc.get("steps")
named = isinstance(steps, list) and len(steps) == len(headers)
out = ["S\x1c0\x1c\x1c0"]
for k, at in enumerate(headers, 1):
    sid = steps[k - 1].get("id") if named and isinstance(steps[k - 1], dict) else None
    sid = sid if isinstance(sid, str) else f"#{k}"
    out.append(f"S\x1c{k}\x1c{sid.translate(PLAIN)}\x1c{line(at)}")
found = collections.Counter()
for start, end, q in tokens:
    want = tomllib.loads("v = " + src[start:end])["v"]
    chars = decode(start, end, q)
    if chars is None or "".join(ch for ch, _ in chars) != want:
        fail(f"line {line(start)}: a string the lint cannot decode the way TOML does")
    found[want] += 1
    out.append(f"T\x1c{bisect.bisect_right(headers, start)}")
    text, lines = [], []
    for ch, pos in chars:
        lines.append(line(pos))
        if ch == "\n":
            out.append(rendered(text, lines))
            text, lines = [], []
        else:
            text.append(ch)
    out.append(rendered(text, lines or [line(end - 1)]))
    out.append("E")

def strings(v):
    if isinstance(v, str):
        yield v
    elif isinstance(v, (dict, list)):
        for x in (v.values() if isinstance(v, dict) else v):
            yield from strings(x)

missing = collections.Counter(strings(doc)) - found
if missing:
    fail(f"a string tomllib reads in the file is not one the lint found there: {next(iter(missing))[:60]!r}")
sys.stdout.buffer.write(("\n".join(out) + "\n").encode("utf-8", "replace"))
PYEOF
) || { echo "$PROG: could not load its decoder" >&2; exit 2; }

# CONVERT_AWK prints the skill files of one side of the change as the records
# DECODE_PY prints for a formula, with each skill as a step, named by its
# directory. It reads a list whose lines are `S<TAB>dir`, a skill on this side,
# and `F<TAB>dir<TAB>source<TAB>path`, a file of the skill, read from source. It
# prints `S<FS>step<FS>dir<FS>0` for each skill, where step numbers the skill in
# the order it first comes, and for each file `T<FS>step`, `R<FS>line<FS>text`
# for each of its lines and `E`. Its files' lines follow one another in VIRT,
# and line is a line of VIRT. MAP gets `line<TAB>path` for each file, the line
# of VIRT its first line takes. A control character other than a tab reads as a
# blank, as in DECODE_PY.
CONVERT_AWK=$(cat <<'AWKEOF'
function step(d) {
    if (!(d in num)) { num[d] = ++n; print "S\034" n "\034" d "\034" 0 }
    return num[d]
}
BEGIN { FS = "\t" }
$1 == "S" { step($2); next }
$1 == "F" {
    print "T\034" step($2)
    print (v + 1) "\t" $4 > MAP
    while ((r = (getline t < $3)) > 0) {
        sub(/\r$/, "", t)
        gsub(/[\001-\010\013-\037\177]/, " ", t)
        print t > VIRT
        print "R\034" (++v) "\034" t
    }
    if (r < 0) { print "cannot read " $4 > "/dev/stderr"; exit 2 }
    close($3)
    print "E"
}
AWKEOF
) || { echo "$PROG: could not load its skill reader" >&2; exit 2; }

# PARSE_AWK reads what DECODE_PY prints for a formula file, or CONVERT_AWK for
# skill files, and prints, for each shell block in its strings or files,
# `F<FS>open<FS>commands<FS>control<FS>words<FS>text<FS>step`; for each line of
# a block's code, here-document bodies included, `L<FS>line<FS>open`; and each
# step's S record as it came. <FS> is \034, open is the line of the block's
# opening fence, words names its control flow, text is its code with every
# newline written as \035, and step is the step's place in the file.
PARSE_AWK=$(cat <<'AWKEOF'
function fill(w,   o) { o = ""; while (w-- > 0) o = o "."; return o }
function blanks(w,   o) { o = ""; while (w-- > 0) o = o " "; return o }
function word_start(s, i,   p) {
    if (i == 1) return 1
    p = substr(s, i - 1, 1)
    return (p == " " || p == "\t" || p == "\n" || p == ";" || p == "&" || p == "|" || p == "(" || p == ")" || p == "{" || p == "!")
}
# A here-document operator at i: record its delimiter, whether it strips
# leading tabs, and whether any part of its word is quoted, which keeps the
# shell from expanding the body, and return the width of the operator and its
# word.
function heredoc_op(s, i,   j, n, tabs, d, c, q, lit) {
    n = length(s); j = i + 2; tabs = 0; lit = 0
    if (substr(s, j, 1) == "-") { tabs = 1; j++ }
    while (j <= n && substr(s, j, 1) ~ /[ \t]/) j++
    d = ""
    while (j <= n) {
        c = substr(s, j, 1)
        if (c == "'" || c == "\"") {
            lit = 1
            q = index(substr(s, j + 1), c)
            if (!q) { d = d substr(s, j + 1); j = n + 1; break }
            d = d substr(s, j + 1, q - 1); j += q + 1; continue
        }
        if (c == "\\") { lit = 1; d = d substr(s, j + 1, 1); j += 2; continue }
        if (c ~ /[ \t\n;&|<>()]/) break
        d = d c; j++
    }
    if (d != "") { SHD[++SHN] = d; SHT[SHN] = tabs; SHQ[SHN] = lit }
    return j - i
}
# Walk shell text s once. SM is s with every character that is not at the top
# level of the command line written as a dot, and a comment as blanks, so a
# separator inside a quote, a substitution, a [[ test or arithmetic never
# counts. SS[1..SN] are the outermost command substitutions, SO the depth still
# open at the end (0 when s is whole), and SHD/SHT[1..SHN] the here-documents
# it opens. The context stack holds S '', E $'', D "", K ``, C $() <() >(),
# P a ( inside C, A $(( )) or (( )), Q a ( inside A, Z ${ } and T [[ ]]. With
# SCAN_BODY set, s is an expanding here-document's body, which the stack opens
# as H: a D in which " is a plain character. A PLACEHOLDER outside a quote, with
# no shell syntax PLACEHOLDER_SHELL finds in it, is one word.
function scan(s,   n, i, c, nx, k, top, st, w, out, subd, at, j) {
    n = length(s); top = 0; out = ""; SN = 0; SHN = 0; subd = 0; at = 0
    if (SCAN_BODY) { st[1] = "H"; top = 1 }
    i = 1
    while (i <= n) {
        c = substr(s, i, 1); nx = substr(s, i + 1, 1)
        k = top ? st[top] : ""
        w = 1
        if (k == "S") {
            if (c == "'") top--
        } else if (k == "E") {
            if (c == "\\") w = 2
            else if (c == "'") top--
        } else if (c == "\\") {
            w = 2
        } else if (k == "D" || k == "H") {
            if (c == "\"") { if (k == "D") top-- }
            else if (c == "`") { st[++top] = "K"; if (subd++ == 0) at = i + 1 }
            else if (c == "$" && nx == "(" && substr(s, i + 2, 1) == "(") { st[++top] = "A"; w = 3 }
            else if (c == "$" && nx == "(") { st[++top] = "C"; w = 2; if (subd++ == 0) at = i + 2 }
            else if (c == "$" && nx == "{") { st[++top] = "Z"; w = 2 }
        } else if (k == "K" && c == "`") {
            top--
            if (--subd == 0) SS[++SN] = substr(s, at, i - at)
        } else if (c == "#" && (k == "" || k == "C" || k == "P" || k == "K") && word_start(s, i)) {
            j = index(substr(s, i), "\n")
            w = j ? j - 1 : n - i + 1
            if (k == "") { out = out blanks(w); i += w; continue }
        } else if (c == "<" && (k == "" || k == "C" || k == "P" || k == "K") && match(substr(s, i), PLACEHOLDER) && substr(s, i, RLENGTH) !~ PLACEHOLDER_SHELL) {
            w = RLENGTH
        } else if (c == "'") {
            st[++top] = "S"
        } else if (c == "\"") {
            st[++top] = "D"
        } else if (c == "`") {
            st[++top] = "K"; if (subd++ == 0) at = i + 1
        } else if (c == "$" && nx == "'") {
            st[++top] = "E"; w = 2
        } else if (c == "$" && nx == "(" && substr(s, i + 2, 1) == "(") {
            st[++top] = "A"; w = 3
        } else if ((c == "$" || ((c == "<" || c == ">") && k != "A" && k != "Q")) && nx == "(") {
            st[++top] = "C"; w = 2; if (subd++ == 0) at = i + 2
        } else if (c == "$" && nx == "{") {
            st[++top] = "Z"; w = 2
        } else if (c == "<" && nx == "<" && substr(s, i + 2, 1) != "<" && (i == 1 || substr(s, i - 1, 1) != "<") && (k == "" || k == "C" || k == "P" || k == "K")) {
            w = heredoc_op(s, i)
        } else if (k == "") {
            if (c == "(" && nx == "(") { st[++top] = "A"; w = 2 }
            else if (c == "[" && nx == "[" && word_start(s, i) && substr(s, i + 2, 1) ~ /[ \t]/) { st[++top] = "T"; w = 2 }
            else { out = out c; i++; continue }
        } else if (k == "C" || k == "P") {
            if (c == "(") st[++top] = "P"
            else if (c == ")") { top--; if (k == "C" && --subd == 0) SS[++SN] = substr(s, at, i - at) }
        } else if (k == "A" || k == "Q") {
            if (c == "(") st[++top] = "Q"
            else if (k == "Q" && c == ")") top--
            else if (k == "A" && c == ")" && nx == ")") { top--; w = 2 }
        } else if (k == "Z") {
            if (c == "}") top--
        } else if (k == "T") {
            if (c == "]" && nx == "]") { top--; w = 2 }
        }
        out = out fill(w)
        i += w
    }
    SO = top
    SM = out
}
# Count one command segment of a masked line: its control flow into SC_CF and
# SC_W, and the command it runs, if any, into SC_CMD. Only a word in command
# position is a keyword. segs drops a case clause's pattern label before this
# reads the segment, so a word that ends in ) closes a subshell and is the
# subshell's last command. A cd that an && runs takes back that &&, which segs
# counted when it split there, and counts no command.
function seg_end(g,   nw, ww, j, t, and) {
    nw = split(g, ww, /[ \t]+/)
    j = 1
    while (j <= nw && ww[j] == "") j++
    if (j > nw) return
    and = SC_AND; SC_AND = 0
    if (and && ww[j] == "cd") { SC_CF--; sub(/ &&$/, "", SC_W); return }
    j = 1
    while (j <= nw) {
        t = ww[j]
        sub(/^\(+/, "", t)
        if (t == "" || t ~ /^[{}!]+$/ || t == "then" || t == "do") { j++; continue }
        if (t == "if" || t == "elif" || t == "else" || t == "while" || t == "until") { SC_CF++; SC_W = SC_W " " t; j++; continue }
        if (t == "fi" || t == "done" || t == "esac" || t ~ /^[)}]/) return
        if (t == "case") { SC_CF++; SC_W = SC_W " case"; SC_LBL = 1; return }
        if (t == "for" || t == "select" || t == "function") { SC_CF++; SC_W = SC_W " " t; return }
        if (t ~ /^[A-Za-z_][A-Za-z0-9_:.-]*\(\)/ || ww[j + 1] ~ /^\(\)/) { SC_CF++; SC_W = SC_W " function"; return }
        break
    }
    if (j <= nw) SC_CMD++
}
# Split a masked line into commands at ; ;; & | |& && || and newlines. A
# redirection's & or | (>& <& &> >|) is part of a word. A case clause opens
# with its pattern label, which is no command: the first word after case ...
# in, or after ;; ;& or ;;&. SC_LBL says one is due, across lines, and the
# label is skipped whole, alternatives and all, so its | is not a pipe.
function segs(m,   n, i, c, nx, pv, g) {
    n = length(m); g = ""; SC_CMD = 0; SC_CF = 0; SC_W = ""; SC_AND = 0
    for (i = 1; i <= n; i++) {
        c = substr(m, i, 1); nx = substr(m, i + 1, 1); pv = (i > 1) ? substr(m, i - 1, 1) : ""
        if (SC_LBL && c != " " && c != "\t" && c != "\n") {
            if (substr(m, i) ~ CASE_IN) { i++; continue }
            SC_LBL = 0
            if (match(substr(m, i), CASE_LABEL)) { i += RLENGTH - 1; continue }
        }
        if (c == "&") {
            if (nx == "&") { seg_end(g); g = ""; SC_CF++; SC_W = SC_W " &&"; SC_AND = 1; i++; continue }
            if (pv == ">" || pv == "<" || nx == ">") { g = g c; continue }
            seg_end(g); g = ""; continue
        }
        if (c == "|") {
            if (nx == "|") { seg_end(g); g = ""; SC_CF++; SC_W = SC_W " ||"; i++; continue }
            if (pv == ">") { g = g c; continue }
            if (nx == "&") i++
            seg_end(g); g = ""; continue
        }
        if (c == ";") {
            if (nx == ";" || nx == "&") {
                i++; if (substr(m, i + 1, 1) == "&") i++
                seg_end(g); g = ""; SC_LBL = 1; continue
            }
            seg_end(g); g = ""; continue
        }
        if (c == "\n") { seg_end(g); g = ""; continue }
        g = g c
    }
    seg_end(g)
}
# AC_CMD, AC_CF and AC_W for a whole command line: its own commands and
# control flow, plus each command substitution's control flow, and the
# substitution's commands when it holds more than one. A substitution is a
# command line of its own, so it starts with no case label due, and the line's
# own wait for one outlasts it.
function analyze(s, depth,   m, n, i, subs, cmd, cf, w, lbl) {
    scan(s)
    m = SM; n = SN
    for (i = 1; i <= n; i++) subs[i] = SS[i]
    segs(m)
    cmd = SC_CMD; cf = SC_CF; w = SC_W; lbl = SC_LBL
    if (depth < 16) {
        for (i = 1; i <= n; i++) {
            SC_LBL = 0
            analyze(subs[i], depth + 1)
            cf += AC_CF; w = w AC_W
            if (AC_CMD > 1) cmd += AC_CMD
        }
    }
    SC_LBL = lbl
    AC_CMD = cmd; AC_CF = cf; AC_W = w
}
function finish() {
    if (!(gctkbin && gctk_line(buf))) {
        analyze(buf, 0)
        fcmd += AC_CMD; fcf += AC_CF; fwords = fwords AC_W
    }
    ftext = ftext buf "\n"
    code_lines(blines)
    buf = ""; blines = ""; bsep = ""; bhd = 0
}
# Whether command line s is the line a gctk-bin block holds between its
# markers, which weighs nothing: one assignment to GCTK that runs no command.
# With its quotes masked, the line holds no blank and no ;, & or |, any of which
# could join a command to the assignment.
function gctk_line(s,   t) {
    scan(s)
    t = SM; gsub(/^[ \t]+|[ \t]+$/, "", t)
    return SN == 0 && t ~ /^GCTK=[^ \t;&|]*$/
}
# An L record for each of the block's lines not yet recorded.
function code_lines(lines,   n, i, bl) {
    n = split(lines, bl, " ")
    for (i = 1; i <= n; i++)
        if (bl[i] != "" && !((fopen, bl[i]) in lseen)) { lseen[fopen, bl[i]] = 1; print "L\034" bl[i] "\034" fopen }
}
# The command substitutions an expanding here-document body runs weigh as a
# command line's do: their control flow, and the commands of each that holds
# more than one. A case label due on the command line around the body still
# waits once the body is weighed.
function body_weigh(b,   n, i, subs, lbl) {
    lbl = SC_LBL
    SCAN_BODY = 1; scan(b); SCAN_BODY = 0
    n = SN
    for (i = 1; i <= n; i++) subs[i] = SS[i]
    for (i = 1; i <= n; i++) {
        SC_LBL = 0
        analyze(subs[i], 1)
        fcf += AC_CF; fwords = fwords AC_W
        if (AC_CMD > 1) fcmd += AC_CMD
    }
    SC_LBL = lbl
}
function fence_close(   t) {
    if (!infence) return
    if (fshell) {
        if (hdn > hdi && !hdq[hdi + 1]) body_weigh(hbody)
        if (buf != "") finish()
        t = ftext; gsub(/\n/, "\035", t)
        print "F\034" fopen "\034" fcmd "\034" fcf "\034" fwords "\034" t "\034" stepn
    }
    infence = 0; fshell = 0; hdn = 0; hdi = 0; hbody = ""; buf = ""; blines = ""; bsep = ""; bhd = 0; gctkbin = 0
}
# One line of a shell block, as the agent reads it. A command whose quote,
# substitution or continuation is still open runs on into the next line. A line
# inside a here-document is the body's, and joins the block's text and lines.
# Once a body whose delimiter is unquoted ends, the shell expands it, so its
# substitutions are weighed then; a block that closes first ends the body. A
# comment line that opens a gctk-bin block, or closes one, sets gctkbin.
function shell_line(s, lines,   t, i) {
    if (hdn > hdi) {
        t = s
        if (hdt[hdi + 1]) sub(/^\t+/, "", t)
        if (t == hdd[hdi + 1]) {
            hdi++
            if (!hdq[hdi]) body_weigh(hbody)
            hbody = ""
            if (hdi >= hdn) { hdn = 0; hdi = 0 }
            return
        }
        hbody = hbody s "\n"; ftext = ftext s "\n"
        code_lines(lines)
        return
    }
    if (buf == "") {
        if (s ~ /^[ \t]*$/) return
        if (s ~ /^[ \t]*#/) {
            if (s ~ /^[ \t]*# >>> gctk-bin[ \t]*$/) gctkbin = 1
            else if (s ~ /^[ \t]*# <<< gctk-bin[ \t]*$/) gctkbin = 0
            return
        }
        buf = s; blines = lines
    } else {
        buf = buf bsep s; blines = blines " " lines
    }
    scan(buf)
    for (i = bhd + 1; i <= SHN; i++) { hdn++; hdd[hdn] = SHD[i]; hdt[hdn] = SHT[i]; hdq[hdn] = SHQ[i] }
    if (SHN > bhd) bhd = SHN
    if (SO == 0 && buf ~ /\\$/) {
        t = buf; sub(/\\+$/, "", t)
        if ((length(buf) - length(t)) % 2 == 1) { buf = substr(buf, 1, length(buf) - 1); bsep = ""; return }
    }
    if (SO > 0) { bsep = "\n"; return }
    finish()
}
# A line of a TOML string as the agent reads it, with the file lines it came
# from. A fence is read as CommonMark reads one, at any indentation. A run of
# three or more backticks or tildes opens a block, unless the run is backticks
# and its line holds another backtick, which makes it inline code. The first
# word after the run names the block's language, in any case. Only a run of the
# same character, at least as long and with nothing after it, closes the block,
# so any other fence line inside it is the block's own text. A line inside a
# shell block is read as shell.
function rendered(s, lines,   first, t, c, n, tag) {
    first = lines; sub(/ .*$/, "", first)
    t = s; sub(/^[ \t]*/, "", t)
    c = substr(t, 1, 1); n = 0
    if (c == "`" || c == "~") while (substr(t, n + 1, 1) == c) n++
    if (n >= 3 && infence && c == fchar && n >= flen && substr(t, n + 1) ~ /^[ \t]*$/) { fence_close(); return }
    if (n >= 3 && !infence && !(c == "`" && index(substr(t, n + 1), "`"))) {
        tag = tolower(substr(t, n + 1)); sub(/^[ \t]*/, "", tag); sub(/[^a-z0-9_+-].*$/, "", tag)
        infence = 1; fchar = c; flen = n
        fshell = (tag == "bash" || tag == "sh" || tag == "shell" || tag == "zsh" || tag == "ksh" || tag == "dash")
        fopen = first; fcmd = 0; fcf = 0; fwords = ""; ftext = ""
        buf = ""; blines = ""; bsep = ""; bhd = 0; hdn = 0; hdi = 0; hbody = ""; SC_LBL = 0; gctkbin = 0
        return
    }
    if (infence && fshell) shell_line(s, lines)
}
# Each record DECODE_PY or CONVERT_AWK printed: a step, the step the next
# string or file sits in, a line of it, or its end, which closes a block still
# open in it.
# CASE_IN is a case's own `in` on a line of its own, and CASE_LABEL a pattern
# label: an optional (, one or more patterns joined by |, and the closing ).
# PLACEHOLDER is a placeholder: a < and a letter, then the line's text up to the
# next >, whose last character before it is no blank, so a redirection such as
# `<in >out` is no placeholder. Nor is a span that holds shell syntax, which
# PLACEHOLDER_SHELL finds: a ; or an &, a parenthesis, a backquote, or a | beside
# a blank, another | or the closing >. So `<in.txt | uniq>out.txt` is a pipeline
# between two redirections, and a | in a placeholder joins two alternatives, as
# in <approve|request-changes>.
BEGIN {
    FS = "\034"
    CASE_IN = "^in([ \t\n]|$)"
    CASE_LABEL = "^[(]?[^ \t\n;&|()<>]+([|][^ \t\n;&|()<>]+)*[)]"
    PLACEHOLDER = "^<[A-Za-z]([^<>\n]*[^<>\n \t])?>"
    PLACEHOLDER_SHELL = "[;&()`]|[ \t][|]|[|][ \t|>]"
}
$1 == "S" { print; next }
$1 == "T" { stepn = $2 + 0; next }
$1 == "R" { rendered($3, $2); next }
$1 == "E" { fence_close() }
AWKEOF
) || { echo "$PROG: could not load its parser" >&2; exit 2; }

# JUDGE_AWK weighs each step on both sides of the change and prints each step
# the change makes heavier as
# `line<FS>id<FS>new|edit<FS>old commands<FS>old control<FS>commands<FS>control<FS>words`,
# where line is the first line the change adds to the step's procedures. A
# block whose code is unchanged, wherever it moved, is paired by its text and
# weighs nothing. It pairs with a block of its own step before another step's,
# so a copied procedure weighs on the step it was copied into. A block that is
# one call weighs nothing either.
JUDGE_AWK=$(cat <<'AWKEOF'
FILENAME == OLD {
    split($0, f, "\034")
    if (f[1] == "S") osid[f[2]] = f[3]
    else if (f[1] == "F") { on++; ocmd[on] = f[3] + 0; ocf[on] = f[4] + 0; otext[on] = f[6]; ostep[on] = f[7] }
    next
}
FILENAME == NEW {
    split($0, f, "\034")
    if (f[1] == "S") { nsid[f[2]] = f[3]; if (f[2] + 0 > nsteps) nsteps = f[2] + 0 }
    else if (f[1] == "F") { nn++; nopen[nn] = f[2]; ncmd[nn] = f[3] + 0; ncf[nn] = f[4] + 0; nwords[nn] = f[5]; ntext[nn] = f[6]; nstep[nn] = f[7] }
    else if (f[1] == "L") { lc[f[3]]++; lat[f[3], lc[f[3]]] = f[2] }
    next
}
/^@@ / {
    h = $0; sub(/^@@ -/, "", h); split(h, parts, " ")
    k = split(substr(parts[2], 2), q, ","); c = q[1] + 0; d = (k > 1) ? q[2] + 0 : 1
    for (x = c; x < c + d; x++) added[x] = 1
}
END {
    for (j in osid) had[osid[j]] = 1
    for (i = 1; i <= nn; i++)
        for (j = 1; j <= on; j++)
            if (!oclaim[j] && ntext[i] == otext[j] && nsid[nstep[i]] == osid[ostep[j]]) { oclaim[j] = 1; nclaim[i] = 1; break }
    for (i = 1; i <= nn; i++)
        for (j = 1; j <= on && !nclaim[i]; j++)
            if (!oclaim[j] && ntext[i] == otext[j]) { oclaim[j] = 1; nclaim[i] = 1 }
    for (j = 1; j <= on; j++)
        if (!oclaim[j] && (ocmd[j] > 1 || ocf[j] > 0)) { s = osid[ostep[j]]; ox[s] += ocmd[j]; oy[s] += ocf[j] }
    for (i = 1; i <= nn; i++) {
        if (nclaim[i] || !(ncmd[i] > 1 || ncf[i] > 0)) continue
        s = nsid[nstep[i]]; p = nopen[i]
        nx[s] += ncmd[i]; ny[s] += ncf[i]; nw[s] = nw[s] nwords[i]
        if (!(s in at0)) at0[s] = p
        for (k = 1; k <= lc[p]; k++) {
            x = lat[p, k]
            if ((x in added) && !(s in at1)) at1[s] = x
        }
    }
    for (k = 0; k <= nsteps; k++) {
        s = nsid[k]
        if (!(s in nx) || (s in told)) continue
        told[s] = 1
        if (nx[s] > ox[s] + 0 || ny[s] > oy[s] + 0)
            print ((s in at1) ? at1[s] : at0[s]) "\034" s "\034" ((s in had) ? "edit" : "new") "\034" (ox[s] + 0) "\034" (oy[s] + 0) "\034" nx[s] "\034" ny[s] "\034" nw[s]
    }
}
AWKEOF
) || { echo "$PROG: could not load its judge" >&2; exit 2; }

# REPORT_AWK prints each judged step as a finding and exits 1 on a finding.
# KIND is step, for a formula's steps, or skill, for the skills. A finding names
# PATHNAME and the judged line, or, with MAP set, the file and the line of it
# that the judged line of VIRT is.
REPORT_AWK=$(cat <<'AWKEOF'
BEGIN { while (MAP != "" && (getline m < MAP) > 0) { split(m, p, "\t"); nm++; mline[nm] = p[1] + 0; mpath[nm] = p[2] } }
function place(n,   k) {
    if (!nm) return PATHNAME ":" n
    k = nm
    while (k > 1 && mline[k] > n) k--
    return mpath[k] ":" (n - mline[k] + 1)
}
function plural(n, one, many) { return n " " (n == 1 ? one : many) }
function words(w,   n, a, i, seen, out) {
    n = split(w, a, " "); out = ""
    for (i = 1; i <= n; i++) if (a[i] != "" && !(a[i] in seen)) { seen[a[i]] = 1; out = out (out == "" ? "" : ", ") a[i] }
    return out
}
function shape(n, c, w) { return plural(n, "command", "commands") (c > 0 ? " and control flow (" words(w) ")" : "") }
function weight(n, c) { return plural(n, "command", "commands") " and " (c > 0 ? plural(c, "control-flow construct", "control-flow constructs") : "no control flow") }
{
    split($0, f, "\034")
    if (KIND == "skill") where = "skill " f[2]
    else where = (f[2] == "" ? "the formula's own text" : "step " f[2])
    if (f[3] == "new") what = "the new " where " has shell blocks that do more than call a script, with " shape(f[6], f[7], f[8])
    else if (f[4] == 0 && f[5] == 0) what = where " gains shell blocks that do more than call a script, with " shape(f[6], f[7], f[8])
    else what = "in " where ", the shell blocks that do more than call a script grow from " weight(f[4], f[5]) " to " weight(f[6], f[7])
    print place(f[1] + 0) ": " KIND " text gains a procedure: " what ". A " KIND "'s shell block makes one call, so move the procedure into a tested script or a gctk verb and call that (docs/pack-authoring.md#step-text-calls-a-tested-script)"
    found++
}
END {
    print found + 0 > COUNTS
    exit (found > 0)
}
AWKEOF
) || { echo "$PROG: could not load its report" >&2; exit 2; }

# The files the change renamed, as `R<score><TAB>old<TAB>new`, from one
# rename-aware diff.
if ! renames=$(git diff -M --name-status --no-color --diff-filter=R "$MERGE_BASE" --); then
  echo "$PROG: cannot list the renames since $MERGE_BASE" >&2
  exit 2
fi

found=0; i=0
for f in ${formulas[@]+"${formulas[@]}"}; do
  i=$((i + 1))
  old="$WORK/old.$i"; new_rec="$WORK/new.$i.rec"; old_rec="$WORK/old.$i.rec"
  src=$(printf '%s\n' "$renames" | awk -F'\t' -v p="$f" '$3 == p { print $2; exit }')
  [ -n "$src" ] || src=$f
  if git cat-file -e "$MERGE_BASE:$src" 2>/dev/null; then
    git show "$MERGE_BASE:$src" > "$old" || { echo "$PROG: cannot read $src at $MERGE_BASE" >&2; exit 2; }
  else
    : > "$old"
  fi
  if ! "$PY" -I -c "$DECODE_PY" "$old" > "$WORK/old.$i.str" 2> "$WORK/err"; then
    echo "$PROG: cannot parse $src at $MERGE_BASE: $(head -c 300 "$WORK/err" | tr '\n' ' ')" >&2; exit 2
  fi
  if ! "$PY" -I -c "$DECODE_PY" "$f" > "$WORK/new.$i.str" 2> "$WORK/err"; then
    echo "$PROG: cannot parse $f: $(head -c 300 "$WORK/err" | tr '\n' ' ')" >&2; exit 2
  fi
  awk "$PARSE_AWK" "$WORK/old.$i.str" > "$old_rec" || { echo "$PROG: cannot parse $src at $MERGE_BASE" >&2; exit 2; }
  awk "$PARSE_AWK" "$WORK/new.$i.str" > "$new_rec" || { echo "$PROG: cannot parse $f" >&2; exit 2; }
  git diff --no-index --no-color --no-ext-diff --histogram -U0 -- "$old" "$f" > "$WORK/diff.$i"
  rc=$?
  [ "$rc" -le 1 ] || { echo "$PROG: cannot diff $f against $src at $MERGE_BASE" >&2; exit 2; }
  awk -v OLD="$old_rec" -v NEW="$new_rec" "$JUDGE_AWK" "$old_rec" "$new_rec" "$WORK/diff.$i" > "$WORK/judged.$i" \
    || { echo "$PROG: cannot judge $f" >&2; exit 2; }
  [ -s "$WORK/judged.$i" ] || continue

  awk -v KIND=step -v PATHNAME="$f" -v COUNTS="$WORK/counts.$i" "$REPORT_AWK" "$WORK/judged.$i"
  rc=$?
  [ "$rc" -le 1 ] && [ -s "$WORK/counts.$i" ] || { echo "$PROG: cannot report on $f" >&2; exit 2; }
  read -r nf < "$WORK/counts.$i"
  found=$((found + nf))
done

# The skill files are judged together, each side read as one text whose steps
# are the skills, so a block pairs with its old self in whichever file or skill
# it now sits. Each file the change names is read from the working tree, and
# from the merge base under its old path: the path the change renamed it from,
# or its own. It has no old text when it came into a skill from outside one, or
# when it is the path another named file was renamed from, whose old text that
# file reads. A skill is on the old side when its directory is at the merge base.
if [ "${#skills[@]}" -gt 0 ]; then
  renamed=(); sources=$'\n'
  for f in "${skills[@]}"; do
    src=$(printf '%s\n' "$renames" | awk -F'\t' -v p="$f" '$3 == p { print $2; exit }')
    renamed+=("$src")
    [ -z "$src" ] || sources="$sources$src"$'\n'
  done
  : > "$WORK/skill.old.list"; : > "$WORK/skill.new.list"
  i=0
  for f in "${skills[@]}"; do
    src=${renamed[i]}; i=$((i + 1))
    if [ -z "$src" ]; then
      src=$f
      case "$sources" in *$'\n'"$f"$'\n'*) src="" ;; esac
    fi
    if [ -n "$src" ] && is_skill_text "$src"; then
      entry=$(git ls-tree "$MERGE_BASE" -- "$src") || { echo "$PROG: cannot list $src at $MERGE_BASE" >&2; exit 2; }
      case "$entry" in
        "100644 "* | "100755 "*)
          git show "$MERGE_BASE:$src" > "$WORK/skill.old.$i" || { echo "$PROG: cannot read $src at $MERGE_BASE" >&2; exit 2; }
          printf 'F\t%s\t%s\t%s\n' "$(skill_dir "$src")" "$WORK/skill.old.$i" "$src" >> "$WORK/skill.old.list" ;;
      esac
    fi
    [ ! -f "$f" ] || printf 'F\t%s\t%s\t%s\n' "$(skill_dir "$f")" "$f" "$f" >> "$WORK/skill.new.list"
  done
  while IFS="$(printf '\t')" read -r _ dir _; do
    git cat-file -e "$MERGE_BASE:$dir" 2>/dev/null && printf 'S\t%s\n' "$dir" >> "$WORK/skill.old.list"
  done < "$WORK/skill.new.list"

  for side in old new; do
    : > "$WORK/skill.$side.virt"; : > "$WORK/skill.$side.map"
    if ! awk -v VIRT="$WORK/skill.$side.virt" -v MAP="$WORK/skill.$side.map" "$CONVERT_AWK" "$WORK/skill.$side.list" > "$WORK/skill.$side.str" 2> "$WORK/err"; then
      echo "$PROG: $(head -c 300 "$WORK/err" | tr '\n' ' ')" >&2; exit 2
    fi
    awk "$PARSE_AWK" "$WORK/skill.$side.str" > "$WORK/skill.$side.rec" || { echo "$PROG: cannot parse the skill files ($side side)" >&2; exit 2; }
  done
  git diff --no-index --no-color --no-ext-diff --histogram -U0 -- "$WORK/skill.old.virt" "$WORK/skill.new.virt" > "$WORK/skill.diff"
  rc=$?
  [ "$rc" -le 1 ] || { echo "$PROG: cannot diff the skill files against $MERGE_BASE" >&2; exit 2; }
  awk -v OLD="$WORK/skill.old.rec" -v NEW="$WORK/skill.new.rec" "$JUDGE_AWK" "$WORK/skill.old.rec" "$WORK/skill.new.rec" "$WORK/skill.diff" > "$WORK/skill.judged" \
    || { echo "$PROG: cannot judge the skill files" >&2; exit 2; }
  if [ -s "$WORK/skill.judged" ]; then
    awk -v KIND=skill -v MAP="$WORK/skill.new.map" -v COUNTS="$WORK/skill.counts" "$REPORT_AWK" "$WORK/skill.judged"
    rc=$?
    [ "$rc" -le 1 ] && [ -s "$WORK/skill.counts" ] || { echo "$PROG: cannot report on the skill files" >&2; exit 2; }
    read -r nf < "$WORK/skill.counts"
    found=$((found + nf))
  fi
fi

summary="$PROG: ${#formulas[@]} formula file(s), ${#skills[@]} skill file(s)"
if [ "$found" -gt 0 ]; then
  echo "$summary, $found procedure(s) added to step or skill text"
  exit 1
fi
echo "$summary, no procedure added to step or skill text"
exit 0
