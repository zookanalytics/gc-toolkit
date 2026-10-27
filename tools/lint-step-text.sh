#!/usr/bin/env bash
# lint-step-text.sh — flags a formula change that adds a procedure to step text.
#
# A formula step calls a tested script, and anything two steps need is one
# script (docs/pack-authoring.md, "Step text calls a tested script"). A shell
# block in step text that does more than make one call is a procedure: it holds
# control flow (if, elif, else, case, for, select, while, until, a function
# definition, && or ||), or more than one command. A sequence and a pipeline
# are more than one command, and so is a command substitution that holds more
# than one. A substitution holding a single command is an argument of the
# command around it, so `"$(gc <binding> scripts-dir)/foo.sh" --bead X` is one
# call.
#
# The lint judges only what a change adds, so step text that predates the rule
# passes until its own rewrite. It weighs each step, named by its id, by the
# commands and the control flow of the procedures its blocks hold, and fails a
# step that a change makes heavier in either count. A new step fails when it
# holds a procedure at all. A block the change leaves alone, or moves without
# editing it, weighs nothing on either side, so a step that only gains single
# calls, or trades a procedure for a call, passes.
#
# The change runs from the merge base of BASE and HEAD to the working tree,
# the change `git diff --name-only BASE...HEAD` names for the rig's
# lint_command. Each FILE that is a formula (formulas/*.toml, or a sub-pack's
# <dir>/formulas/*.toml) is checked, any other FILE is ignored, and a renamed
# formula is compared with its old path. A FILE is a path from the top of the
# repository, as git prints it.
#
# The agent reads step text as TOML decodes it, and so does the lint: a step's
# description is a TOML string, so `\\` in the file is one backslash, and a
# backslash that ends a line joins the next line to it. Only a block fenced as
# bash, sh, shell, zsh, ksh or dash holds commands, and a here-document's body
# is data, not commands.
#
# lint-step-text.in-flight, beside this script, lists the branches whose
# formula changes were in flight when the rule landed, each read from its origin
# ref and from a local branch of that name. A finding prints as a warning and
# does not fail when one of those branches adds every line the finding's step
# gains, at least as many times as the change adds it, against the same base,
# so the branch lands as it was built. A line is counted by its text, so how a
# diff aligns the two sides decides nothing. Any line the list does not cover
# fails as usual.
#
# Usage: lint-step-text.sh [--base REV] [FILE ...]
#   --base REV  the revision a change is measured from (default: origin/main)
#
# Output: each finding as `<file>:<line>: <message>`, each in-flight warning as
# `<file>:<line>: warning: <message>`, then one summary line.
# Exit: 0 no finding, warnings or not; 1 a finding; 2 it could not operate (not
#       a repository, a BASE git cannot read, a file it cannot read or parse).

set -uo pipefail

PROG=lint-step-text
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IN_FLIGHT_LIST="$HERE/lint-step-text.in-flight"
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

formulas=()
for f in ${files[@]+"${files[@]}"}; do
  f=${f#./}
  case "$f" in
    formulas/*.toml | */formulas/*.toml) [ -f "$f" ] && formulas+=("$f") ;;
  esac
done
if [ "${#formulas[@]}" -eq 0 ]; then
  echo "$PROG: no formula file given"
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

WORK=$(mktemp -d "${TMPDIR:-/tmp}/gctk-lint-step-text.XXXXXX") || exit 2
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP

# PARSE_AWK reads a formula file and prints, for each shell block in its TOML
# strings, `F<FS>open<FS>commands<FS>control<FS>words<FS>text<FS>step`; for
# each line that holds code, `L<FS>line<FS>open`; and for each step,
# `S<FS>step<FS>id<FS>line`. <FS> is \034, open is the line of the block's
# opening fence, words names its control flow, text is its code with every
# newline written as \035, and step is the step's place in the file.
PARSE_AWK=$(cat <<'AWKEOF'
function fill(w,   o) { o = ""; while (w-- > 0) o = o "."; return o }
function blanks(w,   o) { o = ""; while (w-- > 0) o = o " "; return o }
# One line of a TOML basic string, decoded. TJOIN is set when the line ends in
# the line-ending backslash, which joins the next line to this one.
function toml_decode(s,   out, i, n, c, nx) {
    out = ""; n = length(s); TJOIN = 0; i = 1
    while (i <= n) {
        c = substr(s, i, 1)
        if (c != "\\") { out = out c; i++; continue }
        if (substr(s, i + 1) ~ /^[ \t]*$/) { TJOIN = 1; break }
        nx = substr(s, i + 1, 1)
        if (nx == "\\" || nx == "\"") out = out nx
        else if (nx == "n") out = out "\n"
        else if (nx == "t") out = out "\t"
        else if (nx == "b" || nx == "f" || nx == "r" || nx == "e") out = out " "
        else if (nx == "u") { out = out "?"; i += 4 }
        else if (nx == "U") { out = out "?"; i += 8 }
        else out = out c nx
        i += 2
    }
    return out
}
function word_start(s, i,   p) {
    if (i == 1) return 1
    p = substr(s, i - 1, 1)
    return (p == " " || p == "\t" || p == "\n" || p == ";" || p == "&" || p == "|" || p == "(" || p == ")" || p == "{" || p == "!")
}
# A here-document operator at i: record its delimiter, and whether it strips
# leading tabs, and return the width of the operator and its word.
function heredoc_op(s, i,   j, n, tabs, d, c, q) {
    n = length(s); j = i + 2; tabs = 0
    if (substr(s, j, 1) == "-") { tabs = 1; j++ }
    while (j <= n && substr(s, j, 1) ~ /[ \t]/) j++
    d = ""
    while (j <= n) {
        c = substr(s, j, 1)
        if (c == "'" || c == "\"") {
            q = index(substr(s, j + 1), c)
            if (!q) { d = d substr(s, j + 1); j = n + 1; break }
            d = d substr(s, j + 1, q - 1); j += q + 1; continue
        }
        if (c == "\\") { d = d substr(s, j + 1, 1); j += 2; continue }
        if (c ~ /[ \t\n;&|<>()]/) break
        d = d c; j++
    }
    if (d != "") { SHD[++SHN] = d; SHT[SHN] = tabs }
    return j - i
}
# Walk shell text s once. SM is s with every character that is not at the top
# level of the command line written as a dot, and a comment as blanks, so a
# separator inside a quote, a substitution, a [[ test or arithmetic never
# counts. SS[1..SN] are the outermost command substitutions, SO the depth still
# open at the end (0 when s is whole), and SHD/SHT[1..SHN] the here-documents
# it opens. The context stack holds S '', E $'', D "", K ``, C $() <() >(),
# P a ( inside C, A $(( )) or (( )), Q a ( inside A, Z ${ } and T [[ ]].
function scan(s,   n, i, c, nx, k, top, st, w, out, subd, at, j) {
    n = length(s); top = 0; out = ""; SN = 0; SHN = 0; subd = 0; at = 0
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
        } else if (k == "D") {
            if (c == "\"") top--
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
# subshell's last command.
function seg_end(g,   nw, ww, j, t) {
    nw = split(g, ww, /[ \t]+/)
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
    n = length(m); g = ""; SC_CMD = 0; SC_CF = 0; SC_W = ""
    for (i = 1; i <= n; i++) {
        c = substr(m, i, 1); nx = substr(m, i + 1, 1); pv = (i > 1) ? substr(m, i - 1, 1) : ""
        if (SC_LBL && c != " " && c != "\t" && c != "\n") {
            if (substr(m, i) ~ CASE_IN) { i++; continue }
            SC_LBL = 0
            if (match(substr(m, i), CASE_LABEL)) { i += RLENGTH - 1; continue }
        }
        if (c == "&") {
            if (nx == "&") { seg_end(g); g = ""; SC_CF++; SC_W = SC_W " &&"; i++; continue }
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
function finish(   n, i, bl) {
    analyze(buf, 0)
    fcmd += AC_CMD; fcf += AC_CF; fwords = fwords AC_W
    ftext = ftext buf "\n"
    n = split(blines, bl, " ")
    for (i = 1; i <= n; i++) if (bl[i] != "") print "L\034" bl[i] "\034" fopen
    buf = ""; blines = ""; bsep = ""; bhd = 0
}
function fence_close(   t) {
    if (!infence) return
    if (fshell) {
        if (buf != "") finish()
        t = ftext; gsub(/\n/, "\035", t)
        print "F\034" fopen "\034" fcmd "\034" fcf "\034" fwords "\034" t "\034" stepn
    }
    infence = 0; fshell = 0; hdn = 0; hdi = 0; buf = ""; blines = ""; bsep = ""; bhd = 0
}
# One line of a shell block, as the agent reads it. A line inside a
# here-document is data. A command whose quote, substitution or continuation
# is still open runs on into the next line.
function shell_line(s, lines,   t, i) {
    if (hdn > hdi) {
        t = s
        if (hdt[hdi + 1]) sub(/^\t+/, "", t)
        if (t == hdd[hdi + 1]) hdi++
        if (hdi >= hdn) { hdn = 0; hdi = 0 }
        return
    }
    if (buf == "") {
        if (s ~ /^[ \t]*$/ || s ~ /^[ \t]*#/) return
        buf = s; blines = lines
    } else {
        buf = buf bsep s; blines = blines " " lines
    }
    scan(buf)
    for (i = bhd + 1; i <= SHN; i++) { hdn++; hdd[hdn] = SHD[i]; hdt[hdn] = SHT[i] }
    if (SHN > bhd) bhd = SHN
    if (SO == 0 && buf ~ /\\$/) {
        t = buf; sub(/\\+$/, "", t)
        if ((length(buf) - length(t)) % 2 == 1) { buf = substr(buf, 1, length(buf) - 1); bsep = ""; return }
    }
    if (SO > 0) { bsep = "\n"; return }
    finish()
}
# A line of a TOML string as the agent reads it, with the physical lines it
# came from. A fence opens or closes a block; a line inside a shell block is
# read as shell.
function rendered(s, lines,   first, tag) {
    first = lines; sub(/ .*$/, "", first)
    if (s ~ /^[ \t]*```/) {
        if (infence) { fence_close(); return }
        tag = s; sub(/^[ \t]*```[ \t]*/, "", tag); sub(/[^A-Za-z0-9_+-].*$/, "", tag)
        infence = 1
        fshell = (tag == "bash" || tag == "sh" || tag == "shell" || tag == "zsh" || tag == "ksh" || tag == "dash")
        fopen = first; fcmd = 0; fcf = 0; fwords = ""; ftext = ""
        buf = ""; blines = ""; bsep = ""; bhd = 0; hdn = 0; hdi = 0; SC_LBL = 0
        return
    }
    if (infence && fshell) shell_line(s, lines)
}
function string_line(text, nr,   d) {
    if (strq == "'''") { rendered(text, nr); return }
    if (tpend) {
        sub(/^[ \t]+/, "", text)
        if (text == "") { tlines = tlines " " nr; return }
    }
    d = toml_decode(text)
    if (tpend) { tbuf = tbuf d; tlines = tlines " " nr } else { tbuf = d; tlines = nr }
    if (TJOIN) { tpend = 1; return }
    tpend = 0
    rendered(tbuf, tlines)
}
function string_end() {
    if (tpend) { tpend = 0; rendered(tbuf, tlines) }
    fence_close()
}
# The position of the delimiter that closes the open string on line s, or 0.
function close_at(s,   p, off) {
    off = 0
    while ((p = index(substr(s, off + 1), strq)) > 0) {
        p += off
        if (strq == "'''" || p == 1 || substr(s, p - 1, 1) != "\\") return p
        off = p
    }
    return 0
}
# A step is each [[steps]] table, named by its id. Text before the first one is
# the formula's own, step 0 with an empty name.
# CASE_IN is a case's own `in` on a line of its own, and CASE_LABEL a pattern
# label: an optional (, one or more patterns joined by |, and the closing ).
BEGIN {
    stepn = 0; sid[0] = ""; sline[0] = 0
    CASE_IN = "^in([ \t\n]|$)"
    CASE_LABEL = "^[(]?[^ \t\n;&|()<>]+([|][^ \t\n;&|()<>]+)*[)]"
}
{
    raw = $0
    if (!instr) {
        if (raw ~ /^[ \t]*\[\[[ \t]*steps[ \t]*\]\][ \t]*$/) { stepn++; sid[stepn] = "#" stepn; sline[stepn] = NR; intop = 1; next }
        if (raw ~ /^[ \t]*\[/) { intop = 0; next }
        if (intop && !named[stepn] && match(raw, /^[ \t]*id[ \t]*=[ \t]*"[^"]*"/)) {
            v = substr(raw, RSTART, RLENGTH); sub(/^[ \t]*id[ \t]*=[ \t]*"/, "", v); sub(/"$/, "", v)
            sid[stepn] = v; named[stepn] = 1
        }
        if (match(raw, /^[ \t]*[A-Za-z0-9_.-]+[ \t]*=[ \t]*("""|''')/)) {
            strq = substr(raw, RSTART + RLENGTH - 3, 3)
            rest = substr(raw, RSTART + RLENGTH)
            if (index(rest, strq) == 0) {
                instr = 1; tpend = 0
                if (rest != "") string_line(rest, NR)
            }
        }
        next
    }
    p = close_at(raw)
    if (p) {
        string_line(substr(raw, 1, p - 1), NR)
        string_end()
        instr = 0
        next
    }
    string_line(raw, NR)
}
END {
    if (instr) string_end()
    for (k = 0; k <= stepn; k++) print "S\034" k "\034" sid[k] "\034" sline[k]
}
AWKEOF
) || { echo "$PROG: could not load its parser" >&2; exit 2; }

# JUDGE_AWK weighs each step on both sides of the change and prints each step
# the change makes heavier as
# `line<FS>id<FS>new|edit<FS>old commands<FS>old control<FS>commands<FS>control<FS>words<FS>code lines`,
# where line is the first line the change adds to the step's procedures, and
# code lines are every line of code in those procedures. A
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
            cl[s] = cl[s] " " x
            if ((x in added) && !(s in at1)) at1[s] = x
        }
    }
    for (k = 0; k <= nsteps; k++) {
        s = nsid[k]
        if (!(s in nx) || (s in told)) continue
        told[s] = 1
        if (nx[s] > ox[s] + 0 || ny[s] > oy[s] + 0)
            print ((s in at1) ? at1[s] : at0[s]) "\034" s "\034" ((s in had) ? "edit" : "new") "\034" (ox[s] + 0) "\034" (oy[s] + 0) "\034" nx[s] "\034" ny[s] "\034" nw[s] "\034" cl[s]
    }
}
AWKEOF
) || { echo "$PROG: could not load its judge" >&2; exit 2; }

# REPORT_AWK prints each judged step as a finding, or as a warning when one
# in-flight branch adds every line the step gains at least as many times as the
# change does, and exits 1 on a finding. A line the change gains is a text that
# occurs more often in the new file than in the old one.
REPORT_AWK=$(cat <<'AWKEOF'
FILENAME == FLIGHT {
    split($0, f, "\034")
    gain[f[1], f[3]] = f[2] + 0
    if (!(f[1] in seen)) { seen[f[1]] = 1; refs[++nrefs] = f[1] }
    next
}
FILENAME == OLDF { was[$0]++; next }
FILENAME == SRC { raw[FNR] = $0; now[$0]++; next }
function plural(n, one, many) { return n " " (n == 1 ? one : many) }
function words(w,   n, a, i, seen, out) {
    n = split(w, a, " "); out = ""
    for (i = 1; i <= n; i++) if (a[i] != "" && !(a[i] in seen)) { seen[a[i]] = 1; out = out (out == "" ? "" : ", ") a[i] }
    return out
}
function shape(n, c, w) { return plural(n, "command", "commands") (c > 0 ? " and control flow (" words(w) ")" : "") }
function weight(n, c) { return plural(n, "command", "commands") " and " (c > 0 ? plural(c, "control-flow construct", "control-flow constructs") : "no control flow") }
# The in-flight branch that adds every text in want[] as often as the change
# does, or "" when none does.
function carrier(   r, t, ok) {
    for (r = 1; r <= nrefs; r++) {
        ok = 1
        for (t in want) if (gain[refs[r], t] + 0 < want[t]) { ok = 0; break }
        if (ok) return refs[r]
    }
    return ""
}
{
    split($0, f, "\034")
    where = (f[2] == "" ? "the formula's own text" : "step " f[2])
    if (f[3] == "new") what = "the new " where " has shell blocks that do more than call a script, with " shape(f[6], f[7], f[8])
    else if (f[4] == 0 && f[5] == 0) what = where " gains shell blocks that do more than call a script, with " shape(f[6], f[7], f[8])
    else what = "in " where ", the shell blocks that do more than call a script grow from " weight(f[4], f[5]) " to " weight(f[6], f[7])
    msg = "step text gains a procedure: " what ". A step calls one tested script, so move the procedure into a script with its own test and call that (docs/pack-authoring.md#step-text-calls-a-tested-script)"
    for (t in want) delete want[t]
    n = split(f[9], at, " "); wanted = 0
    for (i = 1; i <= n; i++) {
        if (at[i] == "") continue
        t = raw[at[i]]
        if (now[t] - was[t] > 0 && !(t in want)) { want[t] = now[t] - was[t]; wanted++ }
    }
    by = wanted ? carrier() : ""
    if (by != "") { print PATHNAME ":" f[1] ": warning: " msg ". Every line it adds is in flight on " by ", so it warns until that branch lands."; warned++ }
    else { print PATHNAME ":" f[1] ": " msg; found++ }
}
END {
    print found + 0 " " warned + 0 > COUNTS
    exit (found > 0)
}
AWKEOF
) || { echo "$PROG: could not load its report" >&2; exit 2; }

# In-flight branches, read once: the names in the list that resolve to a ref,
# origin's and a local branch's both.
in_flight_refs=()
if [ -f "$IN_FLIGHT_LIST" ]; then
  while IFS= read -r name || [ -n "$name" ]; do
    name=${name%%#*}
    name=$(printf '%s' "$name" | tr -d '[:space:]')
    [ -n "$name" ] || continue
    for ref in "refs/remotes/origin/$name" "refs/heads/$name"; do
      git rev-parse -q --verify "$ref^{commit}" >/dev/null && in_flight_refs+=("$ref")
    done
  done < "$IN_FLIGHT_LIST"
fi

# The formulas the change renamed, as `new<TAB>old`, from one rename-aware diff.
if ! renames=$(git diff -M --name-status --no-color --diff-filter=R "$MERGE_BASE" --); then
  echo "$PROG: cannot list the renames since $MERGE_BASE" >&2
  exit 2
fi

found=0; warned=0; i=0
for f in "${formulas[@]}"; do
  i=$((i + 1))
  old="$WORK/old.$i"; new_rec="$WORK/new.$i.rec"; old_rec="$WORK/old.$i.rec"
  src=$(printf '%s\n' "$renames" | awk -F'\t' -v p="$f" '$3 == p { print $2; exit }')
  [ -n "$src" ] || src=$f
  if git cat-file -e "$MERGE_BASE:$src" 2>/dev/null; then
    git show "$MERGE_BASE:$src" > "$old" || { echo "$PROG: cannot read $src at $MERGE_BASE" >&2; exit 2; }
  else
    : > "$old"
  fi
  awk "$PARSE_AWK" "$old" > "$old_rec" || { echo "$PROG: cannot parse $src at $MERGE_BASE" >&2; exit 2; }
  awk "$PARSE_AWK" "$f" > "$new_rec" || { echo "$PROG: cannot parse $f" >&2; exit 2; }
  git diff --no-index --no-color --no-ext-diff --histogram -U0 -- "$old" "$f" > "$WORK/diff.$i"
  rc=$?
  [ "$rc" -le 1 ] || { echo "$PROG: cannot diff $f against $src at $MERGE_BASE" >&2; exit 2; }
  awk -v OLD="$old_rec" -v NEW="$new_rec" "$JUDGE_AWK" "$old_rec" "$new_rec" "$WORK/diff.$i" > "$WORK/judged.$i" \
    || { echo "$PROG: cannot judge $f" >&2; exit 2; }
  [ -s "$WORK/judged.$i" ] || continue

  # What each in-flight branch adds to this formula, as `ref<FS>times<FS>line`:
  # each line's text, and how many more times it occurs at the branch's head
  # than at its merge base.
  : > "$WORK/flight.$i"
  for ref in ${in_flight_refs[@]+"${in_flight_refs[@]}"}; do
    mb=$(git merge-base "$BASE_OID" "$ref") || continue
    git cat-file -e "$ref:$f" 2>/dev/null || continue
    git show "$ref:$f" > "$WORK/flight.head" || { echo "$PROG: cannot read $f at $ref" >&2; exit 2; }
    if git cat-file -e "$mb:$f" 2>/dev/null; then
      git show "$mb:$f" > "$WORK/flight.base" || { echo "$PROG: cannot read $f at $mb" >&2; exit 2; }
    else
      : > "$WORK/flight.base"
    fi
    awk -v r="${ref#refs/*/}" -v B="$WORK/flight.base" '
      FILENAME == B { was[$0]++; next }
      { now[$0]++ }
      END { for (t in now) if (now[t] > was[t]) print r "\034" (now[t] - was[t]) "\034" t }
    ' "$WORK/flight.base" "$WORK/flight.head" >> "$WORK/flight.$i" \
      || { echo "$PROG: cannot count what $ref adds to $f" >&2; exit 2; }
  done

  awk -v FLIGHT="$WORK/flight.$i" -v OLDF="$old" -v SRC="$f" -v PATHNAME="$f" -v COUNTS="$WORK/counts.$i" \
    "$REPORT_AWK" "$WORK/flight.$i" "$old" "$f" "$WORK/judged.$i"
  rc=$?
  [ "$rc" -le 1 ] && [ -s "$WORK/counts.$i" ] || { echo "$PROG: cannot report on $f" >&2; exit 2; }
  read -r nf nw < "$WORK/counts.$i"
  found=$((found + nf)); warned=$((warned + nw))
done

summary="$PROG: ${#formulas[@]} formula file(s)"
[ "$warned" -eq 0 ] || summary="$summary, $warned in-flight warning(s)"
if [ "$found" -gt 0 ]; then
  echo "$summary, $found procedure(s) added to step text"
  exit 1
fi
echo "$summary, no procedure added to step text"
exit 0
