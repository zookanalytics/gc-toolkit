#!/usr/bin/env bash
# pack-script-calls.test.sh — every pack script the pack's text calls is one
# the pack ships.
#
# A formula, a skill, a prompt template or a template fragment calls a pack
# script through one of the call forms below, and nothing fails when the
# script it names is gone until an agent runs the call. The pack's text is the
# root pack's formulas, skills, agents' prompt templates and template
# fragments, and the same files of each sub-pack under packs/. Each form
# reaches a script this way:
#
#   - A scripts-dir resolution, however the text names the binding:
#     $(b='{{binding_prefix}}'; gc "${b%.}" scripts-dir) in a formula,
#     $(b='{binding_prefix}'; gc "${b%.}" scripts-dir) in an expansion formula,
#     and $(gc {{ .BindingName }} scripts-dir) or $(gc <binding> scripts-dir)
#     in a prompt, a fragment or a skill. It reaches the root pack's
#     assets/scripts, because only the root pack ships the scripts-dir
#     command, and a sub-pack's text that runs one of its own scripts reaches
#     it from there, as ../../packs/<sub-pack>/assets/scripts/<name>.
#   - A variable the file binds to such a resolution, under any name and with
#     any path after the resolution, such as SCRIPTS, or TOOLS bound to
#     "$(gc {{ .BindingName }} scripts-dir)/../../tools".
#   - $CONV, which converse-entry.sh prints as its own directory.
#   - {{ .ConfigDir }}, which Gas City renders as the directory of the pack
#     the agent comes from, here taken as the pack the file sits in, so a
#     sub-pack's text reaches the sub-pack's own scripts.
#
# A path a form reaches that ends in .sh is a pack script. The pack must ship
# it, and ship it executable unless the text sources it (. or source) or only
# tests that it is there to read (-r, -f or -e), as a library's callers do. A
# placeholder such as <writer> names no script, and a path that is not a
# script, such as a fragment a skill reads through $CONV, is outside the check.
#
# Hermetic: reads the repo, and builds fixture packs in a temporary directory.
#
# run-tests-scope: tree

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

PASS=0
FAIL=0
ok() {
    PASS=$((PASS + 1))
    printf '  ok    %s\n' "$1"
}
bad() {
    FAIL=$((FAIL + 1))
    printf '  FAIL  %s\n' "$1"
    [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/        /'
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/pack-script-calls.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# pack_text <root> — the files of the pack's text under <root>, relative to it.
pack_text() {
    (
        cd "$1" || exit 1
        for p in . packs/*; do
            [ "$p" = . ] || [ -f "$p/pack.toml" ] || continue
            for d in formulas skills template-fragments; do
                [ -d "$p/$d" ] && find -L "$p/$d" -type f \( -name '*.toml' -o -name '*.md' \)
            done
            [ -d "$p/agents" ] && find -L "$p/agents" -type f -name 'prompt.template.md'
        done | sed 's#^\./##' | LC_ALL=C sort
    )
}

# The scan reads each file twice in a row. The first read records the
# variables the file binds to a scripts-dir resolution, so a use above its
# binding still resolves, and the second prints one line for each pack script
# a call form reaches:
#   <file>:<line> TAB <the call as written> TAB <the script's path> TAB <run|read>
SCAN=$(
    cat <<'AWK'
function norm(p,    n, a, i, k, out) {
    n = split(p, a, "/")
    k = 0
    for (i = 1; i <= n; i++) {
        if (a[i] == "" || a[i] == ".") continue
        if (a[i] == ".." && k > 0 && part[k] != "..") k--
        else part[++k] = a[i]
    }
    out = ""
    for (i = 1; i <= k; i++) out = out (i > 1 ? "/" : "") part[i]
    return out
}
BEGIN {
    SCRIPTS = "assets/scripts"
    RES = "[$][(](b='[^']*'; gc \"[$][{]b%[.][}]\"|gc [{][{] ?[.]BindingName ?[}][}]|gc [^ ()]+) scripts-dir[)]"
    CFG = "[{][{] ?[.]ConfigDir ?[}][}]"
    VAR = "[$][{]?[A-Za-z_][A-Za-z_0-9]*[}]?"
    PATHC = "[A-Za-z0-9._/-]*"
    BIND = "[A-Za-z_][A-Za-z_0-9]*=\"?" RES "\"?" PATHC
    CALL = "(" RES "|" CFG "|" VAR ")\"?/" PATHC
}
FNR == 1 {
    if (FILENAME == last) pass = 2
    else {
        pass = 1
        last = FILENAME
        split("", bound)
        pack = ""
        if (match(FILENAME, "^packs/[^/]+/")) pack = substr(FILENAME, 1, RLENGTH - 1)
    }
}
pass == 1 {
    rest = $0
    while (match(rest, BIND)) {
        m = substr(rest, RSTART, RLENGTH)
        rest = substr(rest, RSTART + RLENGTH)
        name = m
        sub(/=.*/, "", name)
        tail = m
        sub(/^.*scripts-dir[)]"?/, "", tail)
        bound[name] = SCRIPTS tail
    }
    next
}
{
    rest = $0
    seen = ""
    while (match(rest, CALL)) {
        before = seen substr(rest, 1, RSTART - 1)
        m = substr(rest, RSTART, RLENGTH)
        seen = before m
        rest = substr(rest, RSTART + RLENGTH)
        if (match(m, "^" RES)) base = SCRIPTS
        else if (match(m, "^" CFG)) base = pack
        else {
            match(m, "^" VAR)
            name = substr(m, 1, RLENGTH)
            gsub(/[^A-Za-z_0-9]/, "", name)
            if (name in bound) base = bound[name]
            else if (name == "CONV") base = SCRIPTS
            else continue
        }
        path = substr(m, RLENGTH + 1)
        sub("^\"?/", "", path)
        sub(/[.]+$/, "", path)
        if (path !~ /[.]sh$/) continue
        use = "run"
        if ((" " before) ~ /[^A-Za-z0-9_.]([.]|source)[ \t]+"?$/ || before ~ /-[rfe][ \t]+"?$/) use = "read"
        printf "%s:%d\t%s\t%s\t%s\n", FILENAME, FNR, m, norm(base "/" path), use
    }
}
AWK
)

# calls <root> — the scan over <root>'s pack text.
calls() {
    local f args=()
    while IFS= read -r f; do args+=("$f" "$f"); done < <(pack_text "$1")
    [ "${#args[@]}" -gt 0 ] || return 0
    (cd "$1" && LC_ALL=C awk "$SCAN" "${args[@]}")
}

# unshipped <root> — each call in <root>'s pack text whose script the pack
# does not ship, or does not ship executable where the text runs it.
unshipped() {
    local where call script use
    calls "$1" | while IFS=$'\t' read -r where call script use; do
        case "$script" in
            ../*) printf '%s: %s reaches %s, outside the pack\n' "$where" "$call" "$script" ;;
            *)
                if [ ! -f "$1/$script" ]; then
                    printf '%s: %s reaches %s, which the pack does not ship\n' "$where" "$call" "$script"
                elif [ "$use" = run ] && [ ! -x "$1/$script" ]; then
                    printf '%s: %s runs %s, which is not executable\n' "$where" "$call" "$script"
                fi
                ;;
        esac
    done
}

echo "── the scan finds a call in each form, and fails one whose script the pack does not ship ──"
# A fixture pack whose text calls a script in each form, with ROOT_SH, TOOLS_SH
# and SUB_SH standing for the script's name in the root pack's assets/scripts,
# its tools and the sub-pack's assets/scripts. FORM_ROWS gives each form's file
# and the path its call must reach.
FX="$TMP/forms"
mkdir -p "$FX/assets/scripts" "$FX/tools" "$FX/packs/sub/assets/scripts" "$FX/packs/sub/formulas" \
    "$FX/packs/sub/agents/keeper" "$FX/packs/sub/template-fragments" "$FX/formulas" "$FX/template-fragments" \
    "$FX/agents/prompt" "$FX/agents/suffix" "$FX/agents/above" \
    "$FX/skills/skill" "$FX/skills/converse" "$FX/skills/library" "$FX/skills/none"
for s in assets/scripts/a.sh tools/t.sh packs/sub/assets/scripts/s.sh; do
    printf '#!/bin/sh\nexit 0\n' >"$FX/$s"
    chmod +x "$FX/$s"
done
printf 'lib_fn() { :; }\n' >"$FX/assets/scripts/lib.sh"
printf '[pack]\nname = "sub"\nschema = 2\n' >"$FX/packs/sub/pack.toml"
cat >"$FX/formulas/formula.toml" <<'EOF'
"$(b='{{binding_prefix}}'; gc "${b%.}" scripts-dir)/ROOT_SH" --step x
EOF
cat >"$FX/formulas/expansion.toml" <<'EOF'
"$(b='{binding_prefix}'; gc "${b%.}" scripts-dir)/ROOT_SH" --convoy x
EOF
cat >"$FX/skills/skill/SKILL.md" <<'EOF'
( cd <tree> && "$(gc <binding> scripts-dir)/ROOT_SH" --bead <bead> )
EOF
cat >"$FX/agents/prompt/prompt.template.md" <<'EOF'
"$(gc {{ .BindingName }} scripts-dir)/ROOT_SH" <bead>
EOF
cat >"$FX/formulas/scripts.toml" <<'EOF'
SCRIPTS=$(b='{{binding_prefix}}'; gc "${b%.}" scripts-dir) || SCRIPTS=""
"$SCRIPTS/ROOT_SH" --step x
EOF
cat >"$FX/agents/suffix/prompt.template.md" <<'EOF'
TOOLS="$(gc {{ .BindingName }} scripts-dir)/../../tools"
"$TOOLS/TOOLS_SH" slice <S>
EOF
cat >"$FX/agents/above/prompt.template.md" <<'EOF'
- Priority: `"$S/ROOT_SH" move <bead> <P0-P4>`
S="$(gc {{ .BindingName }} scripts-dir)"
EOF
cat >"$FX/skills/converse/SKILL.md" <<'EOF'
"$CONV/ROOT_SH" --conversation "$CONVERSATION"
EOF
cat >"$FX/template-fragments/configdir.template.md" <<'EOF'
"{{ .ConfigDir }}/assets/scripts/ROOT_SH" <bead_id>
EOF
cat >"$FX/packs/sub/formulas/own.toml" <<'EOF'
"$(b='{{binding_prefix}}'; gc "${b%.}" scripts-dir)/../../packs/sub/assets/scripts/SUB_SH" ask --convoy x
EOF
cat >"$FX/packs/sub/agents/keeper/prompt.template.md" <<'EOF'
"{{ .ConfigDir }}/assets/scripts/SUB_SH" --audit
EOF
cat >"$FX/packs/sub/template-fragments/shared.template.md" <<'EOF'
"$(gc <binding> scripts-dir)/ROOT_SH" <bead>
EOF
# A library its callers source or test for reading, which ships without the
# executable bit, and text that names no script through a call form.
cat >"$FX/skills/library/SKILL.md" <<'EOF'
. "$(gc <binding> scripts-dir)/lib.sh" && lib_fn
SCRIPTS=$(b='{{binding_prefix}}'; gc "${b%.}" scripts-dir) && [ -r "$SCRIPTS/lib.sh" ] || SCRIPTS=""
( . "$SCRIPTS/lib.sh"; lib_fn )
EOF
cat >"$FX/skills/none/SKILL.md" <<'EOF'
Every writer is "$(gc <binding> scripts-dir)/<writer>".
cat "$CONV"/../../template-fragments/x.template.md
"$GC_CITY_PATH/rigs/x/assets/scripts/x.sh"
EOF
FORM_ROWS="a formula's resolution|formulas/formula.toml|assets/scripts/ROOT_SH
an expansion formula's resolution|formulas/expansion.toml|assets/scripts/ROOT_SH
a skill's resolution|skills/skill/SKILL.md|assets/scripts/ROOT_SH
a prompt's resolution|agents/prompt/prompt.template.md|assets/scripts/ROOT_SH
\$SCRIPTS after a resolution|formulas/scripts.toml|assets/scripts/ROOT_SH
a variable bound to a path past the resolution|agents/suffix/prompt.template.md|tools/TOOLS_SH
a variable used above its binding|agents/above/prompt.template.md|assets/scripts/ROOT_SH
\$CONV|skills/converse/SKILL.md|assets/scripts/ROOT_SH
{{ .ConfigDir }} in the root pack|template-fragments/configdir.template.md|assets/scripts/ROOT_SH
a sub-pack formula's path into its own scripts|packs/sub/formulas/own.toml|packs/sub/assets/scripts/SUB_SH
{{ .ConfigDir }} in a sub-pack|packs/sub/agents/keeper/prompt.template.md|packs/sub/assets/scripts/SUB_SH
a sub-pack fragment's resolution|packs/sub/template-fragments/shared.template.md|assets/scripts/ROOT_SH"

# instance <dir> <root script> <tools script> <sub-pack script> — the fixture
# pack, its text calling the scripts named.
instance() {
    local f
    cp -Rp "$FX" "$1"
    find "$1" -type f \( -name '*.toml' -o -name '*.md' \) | while IFS= read -r f; do
        sed -e "s/ROOT_SH/$2/g" -e "s/TOOLS_SH/$3/g" -e "s/SUB_SH/$4/g" "$f" >"$f.new" && mv "$f.new" "$f"
    done
}
# fill <path> <root script> <tools script> <sub-pack script>
fill() {
    printf '%s' "$1" | sed -e "s/ROOT_SH/$2/g" -e "s/TOOLS_SH/$3/g" -e "s/SUB_SH/$4/g"
}

instance "$TMP/shipped" a.sh t.sh s.sh
SHIPPED=$(calls "$TMP/shipped")
while IFS='|' read -r label file path; do
    want=$(fill "$path" a.sh t.sh s.sh)
    if printf '%s\n' "$SHIPPED" | awk -F'\t' -v f="$file" -v p="$want" 'index($1, f ":") == 1 && $3 == p { hit = 1 } END { exit !hit }'; then
        ok "the scan finds a call through $label"
    else
        bad "the scan finds a call through $label" "no call in $file reaches $want; the scan printed:
$(printf '%s\n' "$SHIPPED" | awk -F'\t' -v f="$file" 'index($1, f ":") == 1')"
    fi
done <<<"$FORM_ROWS"
got=$(unshipped "$TMP/shipped")
[ -z "$got" ] && ok "a pack that ships every script its text calls passes, the library its callers source included" \
    || bad "a pack that ships every script its text calls passes, the library its callers source included" "$got"
got=$(printf '%s\n' "$SHIPPED" | awk -F'\t' 'index($1, "skills/none/SKILL.md:") == 1')
[ -z "$got" ] && ok "a placeholder, a path that is not a script and a variable bound to no scripts-dir resolution name no script" \
    || bad "a placeholder, a path that is not a script and a variable bound to no scripts-dir resolution name no script" "$got"

instance "$TMP/gone" gone.sh gone.sh gone.sh
GONE=$(unshipped "$TMP/gone")
while IFS='|' read -r label file path; do
    want=$(fill "$path" gone.sh gone.sh gone.sh)
    if printf '%s\n' "$GONE" | awk -v f="$file" -v p="$want" 'index($0, f ":") == 1 && index($0, " reaches " p ", which the pack does not ship") { hit = 1 } END { exit !hit }'; then
        ok "the check fails a call through $label to a script the pack does not ship"
    else
        bad "the check fails a call through $label to a script the pack does not ship" "nothing names $file reaching $want; the check printed:
$GONE"
    fi
done <<<"$FORM_ROWS"

cat >"$TMP/shipped/skills/library/SKILL.md" <<'EOF'
"$(gc <binding> scripts-dir)/lib.sh" --now
EOF
got=$(unshipped "$TMP/shipped")
case "$got" in
    "skills/library/SKILL.md:1: "*" runs assets/scripts/lib.sh, which is not executable") ok "the check fails text that runs a script the pack ships without the executable bit" ;;
    *) bad "the check fails text that runs a script the pack ships without the executable bit" "the check printed: ${got:-nothing}" ;;
esac

echo "── every script the pack's text calls ships ──"
# Every scripts-dir resolution reaches the root pack's scripts only while no
# sub-pack ships a scripts-dir command of its own.
own=""
for p in "$ROOT"/packs/*/; do
    [ -e "${p}commands/scripts-dir" ] && own="$own ${p#"$ROOT"/}"
done
[ -z "$own" ] && ok "no sub-pack ships a scripts-dir command, so every resolution reaches the root pack's scripts" \
    || bad "no sub-pack ships a scripts-dir command, so every resolution reaches the root pack's scripts" \
        "found in:$own; resolve that sub-pack's text against its own scripts"
files=$(pack_text "$ROOT" | wc -l | tr -d ' ')
found=$(calls "$ROOT" | wc -l | tr -d ' ')
[ "$files" -ge 50 ] && [ "$found" -ge 100 ] && ok "the scan reads the pack's text: $found script calls in $files files" \
    || bad "the scan reads the pack's text" "found $found script calls in $files files; the scan is not reading the pack"
got=$(unshipped "$ROOT")
[ -z "$got" ] && ok "every script the pack's text calls ships, executable where the text runs it" \
    || bad "every script the pack's text calls ships, executable where the text runs it" "$got"

printf '\npack-script-calls: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
