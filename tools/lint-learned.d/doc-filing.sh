#!/usr/bin/env bash
# doc-filing.sh — hardened learned rule: a page carries what its tier requires.
#
# docs/file-structure.md asks one thing of each tier. A page under docs/
# carries a `## Scope` section, its charter. A page under specs/ opens with
# frontmatter whose `description` says why it exists, which is what makes a
# record findable when its filename is not. A description on a docs/ page is
# encouraged there, not required, so it is not checked. The tiers are the
# root docs/ and specs/ directories, and only their markdown pages.
#
# A docs/ page with no Scope is one of two things, and only its author can
# tell which. It may be a central doc that has not stated its charter. Or it
# is not a central doc at all: a doc belongs in docs/ only if it is durable,
# authoritative, and owned, and a record of one piece of work belongs in
# specs/<bead-id>/. The finding names both.
#
# Paths are read relative to the repository root, which is how
# tools/lint-learned.sh passes them.
#
# Exit: 0 clean, 1 findings as `<file>:<line>: <message>`, 2 a page that
# could not be read, or a scan that failed.

set -uo pipefail

export LC_ALL=C

NO_SCOPE="no \"## Scope\" section. A page belongs in docs/ only if it is durable, authoritative, and owned, and its Scope says what it covers and where its edges are. A record of one piece of work, such as one component's design, belongs in specs/<bead-id>/ instead. The author decides which this page is (docs/file-structure.md: \"Inside docs/\", \"The Scope section\") (learned rule: doc-filing)"
NO_DESC="no frontmatter description. A spec page opens with a --- block whose description says why the page exists, which is what makes a bead's record findable (docs/file-structure.md: \"Frontmatter\") (learned rule: doc-filing)"

# One line per page: "<scope> <description> <path>", each flag 1 or 0. A
# Scope heading counts only outside a code fence and outside frontmatter. A
# description counts only as a top-level key, with a value, inside a ---
# block that opens on line 1 and closes. A block that never closes is not
# frontmatter, so its lines count as the page's body.
SCAN=$(cat <<'AWK'
function fence_run(s,    c, n) {
    sub(/^ ? ? ?/, "", s)
    c = substr(s, 1, 1)
    if (c != "`" && c != "~") return ""
    n = 0
    while (substr(s, n + 1, 1) == c) n++
    return n >= 3 ? substr(s, 1, n) : ""
}
function finish() {
    if (file == "") return
    if (fm == 1) scope = scope || fmscope
    S[file] = scope
    D[file] = desc
}
FNR == 1 {
    finish()
    file = FILENAME
    scope = 0; desc = 0; pend = 0; fmscope = 0; fm = 0; cont = 0; fence = ""
}
{ line = $0; sub(/\r$/, "", line) }
FNR == 1 && line == "---" { fm = 1; next }
fm == 1 {
    if (line == "---") { fm = 2; desc = pend; next }
    if (line ~ /^ ? ? ?##[ \t]+Scope([ \t]+#+)?[ \t]*$/) fmscope = 1
    if (cont) {
        if (line ~ /^[ \t]/) { if (line ~ /[^ \t]/) pend = 1; next }
        if (line == "") next
        cont = 0
    }
    if (line ~ /^description[ \t]*:/) {
        v = line
        sub(/^description[ \t]*:[ \t]*/, "", v)
        if (v == "" || v ~ /^[|>#]/) { cont = 1; next }
        gsub(/["' \t]/, "", v)
        if (v != "" && v != "~" && v != "null" && v != "Null" && v != "NULL") pend = 1
    }
    next
}
{
    run = fence_run(line)
    if (fence != "") {
        if (run != "" && substr(run, 1, 1) == substr(fence, 1, 1) && length(run) >= length(fence)) {
            rest = line
            sub(/^ ? ? ?/, "", rest)
            if (substr(rest, length(run) + 1) ~ /^[ \t]*$/) fence = ""
        }
        next
    }
    if (run != "") { fence = run; next }
    if (line ~ /^ ? ? ?##[ \t]+Scope([ \t]+#+)?[ \t]*$/) scope = 1
}
END {
    finish()
    for (i = 1; i < ARGC; i++) {
        f = ARGV[i]
        if (f in seen) continue
        seen[f] = 1
        printf "%d %d %s\n", S[f] + 0, D[f] + 0, f
    }
}
AWK
)

# awk reads an operand shaped like `name=value` as an assignment, so every
# page goes to it with a ./ prefix.
pages=()
unreadable=0
for f in "$@"; do
    p="${f#./}"
    case "$p" in docs/*.md | specs/*.md) ;; *) continue ;; esac
    [ -f "$p" ] || continue
    if [ ! -r "$p" ]; then
        echo "$p: cannot read it to check what its tier requires (doc-filing)"
        unreadable=1
        continue
    fi
    pages+=("./$p")
done

found=0
if [ "${#pages[@]}" -gt 0 ]; then
    if ! results="$(awk "$SCAN" "${pages[@]}")"; then
        echo "doc-filing: the page scan failed, so no page was checked"
        exit 2
    fi
    while read -r scope desc page; do
        page="${page#./}"
        [ -n "$page" ] || continue
        case "$page" in
            docs/*) has="$scope"; missing="$NO_SCOPE" ;;
            *) has="$desc"; missing="$NO_DESC" ;;
        esac
        if [ "$has" != 1 ]; then
            echo "$page:1: $missing"
            found=1
        fi
    done <<< "$results"
fi

[ "$unreadable" -eq 0 ] || exit 2
[ "$found" -eq 0 ]
