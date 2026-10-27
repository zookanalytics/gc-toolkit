#!/usr/bin/env bash
# Hermetic test for lint-step-text.sh — the lint that fails a formula change
# adding a procedure to step text.
#
# The defects it guards against: a single script call read as a procedure (a
# substitution in an argument, the body of a here-document whose delimiter is
# quoted, a quoted separator, a redirection, a TOML-escaped continuation or
# quote), a procedure read as a single call (a pipeline, a sequence, a
# substitution holding a pipeline, && or ||, a substitution an expanding
# here-document's body runs), step text left unread (a TOML string of any kind
# wherever it sits, an edit inside a here-document's body, a block fenced with
# tildes, a longer run or a capitalized language, a block a fence line inside
# it cut short, a block inline code at a line's start hid), step text that
# predates the rule failing because a change touched its file, a moved or
# trimmed block read as new, a branch listed as in flight stalled by its own
# lines, a branch built on it let through with lines of its own, and a change
# it cannot read passing as clean (an unreadable file, a file that is not
# TOML, no Python to decode it).
#
# Hermetic: each case runs in a throwaway git repo whose main is the base the
# change is measured from (refs/remotes/origin/main), with a copy of the lint
# under tools/ so it reads the in-flight list beside it. A case writes the
# formula into the working tree and runs the lint on it.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/lint-step-text.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-lint-step-text-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

[ -f "$SUT" ] && ok "SUT exists at $SUT" || bad "SUT missing: $SUT"
bash -n "$SUT" && ok "lint-step-text.sh is syntactically valid bash" || bad "lint-step-text.sh failed bash -n"
[ -x "$SUT" ] && ok "lint-step-text.sh is executable" || bad "lint-step-text.sh is not executable"

REPO="$TMP/repo"
F=formulas/mol-x.toml
g() { git -C "$REPO" "$@"; }

# The base formula: step one is a single call, and step two holds a procedure
# that predates the rule.
base_formula() {
  cat <<'EOF'
description = """
A test formula.
"""

[[steps]]
id = "one"
title = "One"
description = """
Run the call:
```bash
"$GC_RIG_ROOT/assets/scripts/one.sh" --bead "$X"
```
"""

[[steps]]
id = "two"
title = "Two"
description = """
The old procedure:
```bash
A=$(gc bd show "$B" --json)
if [ -n "$A" ]; then
  echo "$A"
fi
```
"""
EOF
}

# A fresh repo whose main, and origin/main, hold the base formula.
fresh_repo() {
  rm -rf "$REPO"
  mkdir -p "$REPO/formulas" "$REPO/tools"
  g init -q -b main
  g config user.email t@t
  g config user.name t
  g config commit.gpgsign false
  cp "$SUT" "$REPO/tools/lint-step-text.sh"
  base_formula > "$REPO/$F"
  printf 'readme\n' > "$REPO/README.md"
  g add -A
  g commit -qm base
  g update-ref refs/remotes/origin/main HEAD
}

# run_lint <args> — runs the repo's copy from the repo root; sets rc and OUT.
run_lint() {
  if OUT=$(cd "$REPO" && bash tools/lint-step-text.sh "$@" 2>&1); then rc=0; else rc=$?; fi
}

# step_two_with <fenced shell> — the base formula with step two's block replaced.
step_two_with() {
  base_formula | BODY="$1" awk '
    /^The old procedure:$/ { print; getline; print; print ENVIRON["BODY"]; skip = 1; next }
    skip && /^```$/ { skip = 0 }
    skip { next }
    { print }'
}

# with_step <id> <text> — the base formula with a new step appended.
with_step() {
  base_formula
  printf '\n[[steps]]\nid = "%s"\ntitle = "New"\ndescription = """\n%s\n"""\n' "$1" "$2"
}

expect() {  # <want rc> <description> [grep pattern the output must hold]
  if [ "$rc" -eq "$1" ] && { [ -z "${3:-}" ] || printf '%s\n' "$OUT" | grep -e "$3" >/dev/null; }; then
    ok "$2"
  else
    bad "$2 (rc=$rc, want $1)"
    printf '%s\n' "$OUT" | sed 's/^/        /'
  fi
}

block() { printf '```bash\n%s\n```' "$1"; }

# --- Usage and scope. --------------------------------------------------------
fresh_repo
run_lint README.md
expect 0 "no formula among the files: exit 0" "no formula file given"

run_lint "$F"
expect 0 "an unchanged formula: exit 0" "no procedure added"

run_lint --base nope "$F"
expect 2 "a base git cannot read: exit 2" "cannot read base revision"

run_lint --bogus
expect 2 "an unknown option: exit 2" "unknown option"

mkdir -p "$TMP/notrepo"
if OUT=$(cd "$TMP/notrepo" && bash "$SUT" "$F" 2>&1); then rc=0; else rc=$?; fi
expect 2 "outside a repository: exit 2" "not inside a git repository"

# --- A new step is judged whole. ---------------------------------------------
with_step new "$(block '"$GC_RIG_ROOT/assets/scripts/new.sh" --bead "$X" --why "a; b | c && d"')" > "$REPO/$F"
run_lint "$F"
expect 0 "a new step whose block is one call, separators quoted: exit 0"

with_step new "$(block '"$(gc gc-toolkit scripts-dir)/new.sh" --bead "$X" 2>&1 >/dev/null')" > "$REPO/$F"
run_lint "$F"
expect 0 "a substitution holding one command and redirections stay one call: exit 0"

with_step new "$(block 'gc bd show "$X" --json | jq -r .id')" > "$REPO/$F"
run_lint "$F"
expect 1 "a pipeline is a procedure: exit 1" "the new step new has shell blocks that do more than call a script, with 2 commands"

with_step new "$(block 'gc bd update "$X" --append-notes y; gc runtime drain-ack')" > "$REPO/$F"
run_lint "$F"
expect 1 "a sequence on one line is a procedure: exit 1" "with 2 commands"

with_step new "$(block '"$S/new.sh" --id "$(gc bd show "$X" --json | jq -r .id)"')" > "$REPO/$F"
run_lint "$F"
expect 1 "a substitution holding a pipeline is a procedure: exit 1" "with 3 commands"

with_step new "$(block '[ -n "$X" ] && "$S/new.sh" "$X"')" > "$REPO/$F"
run_lint "$F"
expect 1 "&& is control flow: exit 1" "control flow (&&)"

with_step new "$(block 'for x in a b; do
  "$S/new.sh" "$x"
done')" > "$REPO/$F"
run_lint "$F"
expect 1 "a for loop is control flow: exit 1" "control flow (for)"

run_lint "$F"
printf '%s\n' "$OUT" | grep -e "^$F:[0-9]*: step text gains a procedure" >/dev/null \
  && ok "a finding names the file and a line" || bad "a finding names the file and a line: $OUT"
line=$(printf '%s\n' "$OUT" | sed -n "s#^$F:\([0-9]*\): .*#\1#p" | head -1)
[ "$(sed -n "${line}p" "$REPO/$F")" = 'for x in a b; do' ] \
  && ok "the finding's line is the first line the change adds to the procedure" \
  || bad "the finding's line is the first line the change adds to the procedure (line $line)"

# A subshell's last command ends in its closing parenthesis and is still a
# command. Only a case clause's pattern label is a word ending in ) that is no
# command: it opens a clause, after case ... in or after ;; ;& ;;&, and it is
# skipped whole, alternatives and all.
for body in '(gc status; true)' '("$S/foo.sh"; exit)' '(cd "$D"; make)'; do
  with_step new "$(block "$body")" > "$REPO/$F"
  run_lint "$F"
  expect 1 "a sequence in a subshell counts its last command: $body" "with 2 commands\. "
done

with_step new "$(block '("$S/x.sh" --bead "$X")')" > "$REPO/$F"
run_lint "$F"
expect 0 "a single call in a subshell stays one call: exit 0"

with_step new "$(block 'case "$X" in
  a) "$S/a.sh" ;;
  (b) "$S/b.sh" ;;
esac')" > "$REPO/$F"
run_lint "$F"
expect 1 "pat) and (pat) labels are not commands" "with 2 commands and control flow (case)\. "

with_step new "$(block 'case "$X" in
  a)
    "$S/a.sh"
    ;;
  (b|c)
    "$S/b.sh"
    ;;&
  d|e) "$S/d.sh" ;&
  *) ;;
esac')" > "$REPO/$F"
run_lint "$F"
expect 1 "a label is skipped whole, alternatives and all, after each kind of ;;" "with 3 commands and control flow (case)\. "

with_step new "$(block 'case "$X"
in
  a) "$S/a.sh" ;;
esac')" > "$REPO/$F"
run_lint "$F"
expect 1 "a case's in on a line of its own is no command, and a label follows it" "with 1 command and control flow (case)\. "

with_step new "$(block 'case "$X" in
  a) (cd "$D"; make) ;;
esac')" > "$REPO/$F"
run_lint "$F"
expect 1 "a subshell in a clause's body counts its last command" "with 2 commands and control flow (case)\. "

with_step new "$(block 'x=$( (gc status; true) )')" > "$REPO/$F"
run_lint "$F"
expect 1 "a subshell inside a substitution counts its last command" "with 3 commands\. "

with_step new "$(block 'cat > "$F" <<'"'"'EOF'"'"'
if x; then y; fi | z && w; v
EOF')" > "$REPO/$F"
run_lint "$F"
expect 0 "a here-document's body is data: exit 0"

with_step new "$(block '"$S/new.sh" --summary "$(cat <<'"'"'BODY'"'"'
a; b | c
BODY
)"')" > "$REPO/$F"
run_lint "$F"
expect 0 "a here-document inside an argument's substitution is data: exit 0"

with_step new "$(printf '```json\n{"a": "b; c | d"}\n```\n```\nx=1; y=2 | z\n```')" > "$REPO/$F"
run_lint "$F"
expect 0 "a block not fenced as shell holds no commands: exit 0"

# A fence is read as CommonMark reads one: three or more backticks or tildes,
# with the language in any case. Only a run of the same character, at least as
# long and with nothing after it, closes a block, and a backtick run whose line
# holds another backtick is inline code.
with_step new "$(printf '~~~bash\necho first; echo second\n~~~')" > "$REPO/$F"
run_lint "$F"
expect 1 "a block fenced with tildes holds commands: exit 1" "with 2 commands\. "

with_step new "$(printf '```Bash\necho first; echo second\n```')" > "$REPO/$F"
run_lint "$F"
expect 1 "a fence's language is read in any case: exit 1" "with 2 commands\. "

with_step new "$(printf '~~~json\n{"a": "b; c | d"}\n~~~\n~~~\nx=1; y=2 | z\n~~~')" > "$REPO/$F"
run_lint "$F"
expect 0 "a tilde block not fenced as shell holds no commands: exit 0"

FENCED=$(cat <<'EOT'
````bash
cat > "$F" <<'EOF'
```
EOF
echo first; echo second
````
EOT
)
with_step new "$FENCED" > "$REPO/$F"
run_lint "$F"
expect 1 "a shorter run inside a longer fence is the block's own text: exit 1" "with 3 commands\. "

FENCED=$(cat <<'EOT'
```bash
cat > "$F" <<'EOF'
~~~
```text
EOF
echo first; echo second
```
EOT
)
with_step new "$FENCED" > "$REPO/$F"
run_lint "$F"
expect 1 "a run of the other character, or one with text after it, closes no block: exit 1" "with 3 commands\. "

FENCED=$(cat <<'EOT'
```x``` names a command inline.
```bash
echo first; echo second
```
EOT
)
with_step new "$FENCED" > "$REPO/$F"
run_lint "$F"
expect 1 "inline code at the start of a line opens no block: exit 1" "with 2 commands\. "

with_step new "$(block '# a comment; with | separators
"$S/new.sh" --bead "$X"   # trailing; comment | too

')" > "$REPO/$F"
run_lint "$F"
expect 0 "comments and blank lines are not commands: exit 0"

# TOML decodes the block first: `\\` at a line's end is a shell continuation,
# and a lone backslash there joins the next line in TOML itself.
with_step new "$(block 'gc bd update "$X" \\
  --append-notes "y"')" > "$REPO/$F"
run_lint "$F"
expect 0 "a TOML-escaped continuation keeps one command: exit 0"

with_step new "$(block 'gc bd update "$X" \
  --append-notes "y"')" > "$REPO/$F"
run_lint "$F"
expect 0 "a TOML line-ending backslash keeps one command: exit 0"

# The shell expands a here-document's body when no part of its delimiter is
# quoted, and runs each command substitution in it. A substitution there weighs
# as one in an argument does: its control flow, and its commands when it holds
# more than one.
with_step new "$(block 'cat <<EOF
$(echo first; echo second)
EOF')" > "$REPO/$F"
run_lint "$F"
expect 1 "an expanding body's substitution that holds a sequence is a procedure: exit 1" "with 3 commands\. "

for op in "<<'EOF'" '<<"EOF"' '<<\\EOF' '<<E"O"F'; do
  with_step new "$(block "cat $op
\$(echo first; echo second)
EOF")" > "$REPO/$F"
  run_lint "$F"
  expect 0 "a body whose delimiter is quoted ($op) is not expanded, so it is data: exit 0"
done

with_step new "$(block 'cat <<EOF
on $(date -u +%F), "$X" says: it is done
EOF')" > "$REPO/$F"
run_lint "$F"
expect 0 "an expanding body's single-command substitution is an argument: exit 0"

with_step new "$(block 'cat <<EOF
\\$(echo first; echo second)
EOF')" > "$REPO/$F"
run_lint "$F"
expect 0 "an escaped \$ in an expanding body starts no substitution: exit 0"

with_step new "$(block 'cat <<EOF
"$(echo first; echo second)"
EOF')" > "$REPO/$F"
run_lint "$F"
expect 1 "a \" in an expanding body is a plain character and hides no substitution: exit 1" "with 3 commands\. "

with_step new "$(block 'cat <<EOF
$(if [ -n "$X" ]; then echo y; fi)
EOF')" > "$REPO/$F"
run_lint "$F"
expect 1 "control flow in an expanding body's substitution counts: exit 1" "control flow (if)"

with_step new "$(block "$(printf 'cat <<-EOF\n\t$(echo first; echo second)\n\tEOF')")" > "$REPO/$F"
run_lint "$F"
expect 1 "a <<- body whose delimiter is indented by tabs is weighed too: exit 1" "with 3 commands\. "

with_step new "$(block 'cat <<EOF
$(echo first; echo second)')" > "$REPO/$F"
run_lint "$F"
expect 1 "an expanding body the block closes before its delimiter is still weighed: exit 1" "with 3 commands\. "

# Each string in the file is decoded as TOML decodes it, whatever its kind and
# wherever it sits, so step text that renders a procedure fails however the
# string is written.
procedure_step() {  # <the step's description line, as written in the file>
  base_formula
  printf '\n[[steps]]\nid = "new"\ntitle = "New"\n%s\n' "$1"
}
procedure_step 'description = "Run:\n```bash\necho first; echo second\n```\n"' > "$REPO/$F"
run_lint "$F"
expect 1 "a basic string whose escaped newlines render a procedure: exit 1" "the new step new has shell blocks that do more than call a script, with 2 commands"

procedure_step 'description = """Run:\n```bash\necho first; echo second\n```\n"""' > "$REPO/$F"
run_lint "$F"
expect 1 "a triple-quoted string closed on its opening line: exit 1" "with 2 commands"

procedure_step 'description = """
Run:\n```bash\necho first; echo second\n```
"""' > "$REPO/$F"
run_lint "$F"
expect 1 "a line of a multi-line string whose escaped newlines render a procedure: exit 1" "with 2 commands"

procedure_step '"description" = """
```bash
echo first; echo second
```
"""' > "$REPO/$F"
run_lint "$F"
expect 1 "a step whose key is quoted: exit 1" "with 2 commands"

procedure_step "description = '''
\`\`\`bash
echo first; echo second
\`\`\`
'''" > "$REPO/$F"
run_lint "$F"
expect 1 "a multi-line literal string: exit 1" "with 2 commands"

procedure_step 'description = "# not a comment\n```bash\necho first; echo second\n```\n"   # a comment with """ in it' > "$REPO/$F"
run_lint "$F"
expect 1 "a # inside a string is text, and quotes inside a comment open no string: exit 1" "with 2 commands"

DQ=$(printf '%su%04x' "$(printf '\134')" 34)   # TOML's unicode escape for "
with_step new "$(block "echo ${DQ}first; second${DQ}")" > "$REPO/$F"
grep -qF "echo ${DQ}first" "$REPO/$F" && ok "the escape fixture holds the escape" || bad "the escape fixture holds the escape"
run_lint "$F"
expect 0 "an escaped quote decodes to a quote, so the separator it quotes stays in one argument: exit 0"

printf 'steps = [{ id = "a", description = "```bash\\necho first; echo second\\n```" }]\n' > "$REPO/formulas/mol-inline.toml"
run_lint formulas/mol-inline.toml
expect 1 "steps written as an inline array still have their strings read: exit 1" "the formula's own text gains shell blocks"
rm -f "$REPO/formulas/mol-inline.toml"

base_formula | awk '
  /^description = """$/ && ++n == 3 { printf "description = \"The old procedure:\\n```bash\\nA=$(gc bd show \\\"$B\\\" --json)\\nif [ -n \\\"$A\\\" ]; then\\n  echo \\\"$A\\\"\\nfi\\n```\\n\"\n"; skip = 1; next }
  skip && /^"""$/ { skip = 0; next }
  skip { next }
  { print }' > "$REPO/$F"
grep -q '^description = "The old procedure:' "$REPO/$F" && ! grep -q '^The old procedure:$' "$REPO/$F" \
  && ok "the re-written fixture holds step two as one basic string" || bad "the re-written fixture holds step two as one basic string"
run_lint "$F"
expect 0 "a step re-written as a basic string that decodes to the same text weighs nothing: exit 0"

printf 'a = """\nunclosed\n' > "$REPO/formulas/bad.toml"
run_lint formulas/bad.toml
expect 2 "a formula that is not valid TOML: exit 2" "cannot parse formulas/bad.toml"
rm -f "$REPO/formulas/bad.toml"

# The lint decodes TOML with a Python that has tomllib, and with none on PATH
# it cannot operate.
mkdir -p "$TMP/nopy"
for t in git awk mktemp rm cat tr head grep sort dirname sed; do
  p=$(command -v "$t") && ln -sf "$p" "$TMP/nopy/$t"
done
if OUT=$(cd "$REPO" && PATH="$TMP/nopy" "$BASH" tools/lint-step-text.sh "$F" 2>&1); then rc=0; else rc=$?; fi
expect 2 "no Python with tomllib on PATH: exit 2" "needs a Python with tomllib"
g checkout -q -- "$F"

# --- An existing step is weighed against its old self. -----------------------
step_two_with 'A=$(gc bd show "$B" --json)
if [ -n "$A" ]; then
  echo "A=$A"
fi' > "$REPO/$F"
run_lint "$F"
expect 0 "an edit that leaves both counts as they were: exit 0"

step_two_with 'A=$(gc bd show "$B" --json)
if [ -n "$A" ]; then
  echo "$A"
  gc runtime drain-ack
fi' > "$REPO/$F"
run_lint "$F"
expect 1 "an edit that adds a command to a procedure: exit 1" \
  "in step two, the shell blocks that do more than call a script grow from 3 commands and 1 control-flow construct to 4 commands and 1 control-flow construct"

step_two_with 'A=$(gc bd show "$B" --json)
if [ -n "$A" ]; then
  echo "$A" || true
fi' > "$REPO/$F"
run_lint "$F"
expect 1 "an edit that adds control flow to a procedure: exit 1" "grow from"

step_two_with 'A=$(gc bd show "$B" --json)' > "$REPO/$F"
run_lint "$F"
expect 0 "an edit that only removes: exit 0"

step_two_with '"$GC_RIG_ROOT/assets/scripts/two.sh" --bead "$B"' > "$REPO/$F"
run_lint "$F"
expect 0 "a step that trades its procedure for a call: exit 0"

base_formula | sed 's#^"$GC_RIG_ROOT/assets/scripts/one.sh" --bead "$X"$#"$GC_RIG_ROOT/assets/scripts/one.sh" --bead "$X"; gc runtime drain-ack#' > "$REPO/$F"
run_lint "$F"
expect 1 "a call that grows into a sequence: exit 1" "step one gains shell blocks that do more than call a script, with 2 commands"

# The old procedure moves, unedited, from step two into step one.
base_formula | awk '
  /^Run the call:$/ { print "The old procedure, moved:"; print "```bash"; print "A=$(gc bd show \"$B\" --json)"; print "if [ -n \"$A\" ]; then"; print "  echo \"$A\""; print "fi"; print "```" }
  /^The old procedure:$/ { skip = 1 }
  skip && /^"""$/ { skip = 0 }
  skip { next }
  { print }' > "$REPO/$F"
grep -q '^The old procedure, moved:$' "$REPO/$F" && ! grep -q '^The old procedure:$' "$REPO/$F" \
  && ok "the move fixture moved the block" || bad "the move fixture moved the block"
run_lint "$F"
expect 0 "a block moved unedited to another step weighs nothing: exit 0"

# The old procedure is copied, unedited, from step two into step one, and the
# finding names step one, where the copy went.
base_formula | awk '
  /^Run the call:$/ { print "The old procedure, copied:"; print "```bash"; print "A=$(gc bd show \"$B\" --json)"; print "if [ -n \"$A\" ]; then"; print "  echo \"$A\""; print "fi"; print "```" }
  { print }' > "$REPO/$F"
grep -q '^The old procedure, copied:$' "$REPO/$F" && grep -q '^The old procedure:$' "$REPO/$F" \
  && ok "the copy fixture copied the block" || bad "the copy fixture copied the block"
run_lint "$F"
expect 1 "a procedure copied into another step weighs on the step it was copied into: exit 1" \
  "^$F:11: step text gains a procedure: step one gains shell blocks that do more than call a script, with 3 commands and control flow (if)"

# A here-document's body is part of its block's text, so an edit to the body is
# an edit to the block, and a substitution it adds to an expanding body weighs
# on the step. Here step two's procedure, already on main, writes a body.
for quoting in expanding quoted; do
  fresh_repo
  op='<<EOF'; [ "$quoting" = quoted ] && op="<<'EOF'"
  step_two_with "A=\$(gc bd show \"\$B\" --json)
cat $op
note: \$A
EOF" > "$REPO/$F"
  g commit -qam "a body on main"
  g update-ref refs/remotes/origin/main HEAD
  step_two_with "A=\$(gc bd show \"\$B\" --json)
cat $op
note: \$A, id \$(gc bd show \"\$B\" --json | jq -r .id)
EOF" > "$REPO/$F"
  run_lint "$F"
  if [ "$quoting" = expanding ]; then
    expect 1 "a substitution added to an existing expanding body weighs on its step: exit 1" \
      "^$F:[0-9]*: .*grow from 2 commands and no control flow to 4 commands and no control flow"
    line=$(printf '%s\n' "$OUT" | sed -n "s#^$F:\([0-9]*\): .*#\1#p" | head -1)
    case "$(sed -n "${line}p" "$REPO/$F")" in
      "note: \$A, id "*) ok "the finding's line is the body line the change edits" ;;
      *) bad "the finding's line is the body line the change edits (line $line)" ;;
    esac
  else
    expect 0 "the same edit to a quoted body is an edit to data: exit 0"
  fi
done

# --- Other formula paths. ------------------------------------------------------
fresh_repo
g mv "$F" formulas/mol-y.toml
run_lint formulas/mol-y.toml
expect 0 "a renamed formula is compared with its old path: exit 0"

fresh_repo
mkdir -p "$REPO/packs/sub/formulas"
with_step new "$(block 'a; b')" > "$REPO/packs/sub/formulas/mol-z.toml"
g add -A
run_lint packs/sub/formulas/mol-z.toml
expect 1 "a new sub-pack formula's procedure: exit 1" "the new step new"

# --- Work in flight. -----------------------------------------------------------
fresh_repo
g checkout -q -b polecat/tk-a
with_step built "$(block 'gc bd show "$X" --json | jq -r .id')" > "$REPO/$F"
g commit -qam "in flight"
g update-ref refs/remotes/origin/polecat/tk-a HEAD
printf '# a comment\npolecat/tk-a\n' > "$REPO/tools/lint-step-text.in-flight"
run_lint "$F"
expect 0 "a listed branch's own procedure warns: exit 0" "warning: .* in flight on origin/polecat/tk-a"

rm "$REPO/tools/lint-step-text.in-flight"
run_lint "$F"
expect 1 "the same procedure with no list: exit 1"

printf 'polecat/tk-a\n' > "$REPO/tools/lint-step-text.in-flight"
g checkout -q -b polecat/tk-b
with_step built "$(block 'gc bd show "$X" --json | jq -r .id
gc runtime drain-ack')" > "$REPO/$F"
run_lint "$F"
expect 1 "a branch built on a listed one, adding a command of its own: exit 1" "^$F:[0-9]*: step text gains"

g checkout -q -- "$F"
g checkout -q polecat/tk-a
g branch -q -D polecat/tk-b
g update-ref -d refs/remotes/origin/polecat/tk-a
run_lint "$F"
expect 0 "a listed branch read from its local branch alone still warns: exit 0" "in flight on polecat/tk-a"

# --- A change the lint cannot read fails closed. ---------------------------------
fresh_repo
printf 'a = """\n```bash\nx; y\n```\n"""\n' > "$REPO/formulas/bad.toml"
chmod 000 "$REPO/formulas/bad.toml"
if [ -r "$REPO/formulas/bad.toml" ]; then
  echo "skip - an unreadable formula (running as a user that reads mode 000)"
else
  run_lint formulas/bad.toml
  expect 2 "an unreadable formula: exit 2" "cannot parse"
fi
chmod 644 "$REPO/formulas/bad.toml"

echo
echo "lint-step-text.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
