#!/usr/bin/env bash
# Hermetic test for lint-step-text.sh — the lint that fails a change adding a
# procedure to formula step text or to a skill.
#
# The defects it guards against: a single script call read as a procedure (a
# substitution in an argument, the body of a here-document whose delimiter is
# quoted, a quoted separator, a redirection, a TOML-escaped continuation or
# quote, the gctk-bin block before a gctk call, a placeholder that names
# alternatives), a procedure read as a single call (a pipeline, a sequence, a
# substitution holding a pipeline, && or ||, a substitution an expanding
# here-document's body runs, a command inside the gctk-bin markers, on a line
# of its own or joined to the assignment, a command after a placeholder that
# holds an apostrophe, shell syntax between a < and a > read as a placeholder),
# step text left unread (a TOML string of any kind wherever it sits, an edit
# inside a here-document's body, a block fenced with tildes, a longer run or a
# capitalized language, a block a fence line inside it cut short, a block
# inline code at a line's start hid), skill text left unread (a new skill, a
# sub-pack's or an agent's skill, a file moved into a skill), text that
# predates the rule failing because a change touched its file, a moved or
# trimmed block read as new (within a formula, or across a skill's files and
# between skills, a file the change deletes included), text read that is not
# the skill's own (a symlinked file, a block a file leaves open running into
# the next), and a change it cannot read passing as clean (an unreadable file,
# a file that is not TOML, no Python to decode it).
#
# Hermetic: each case runs in a throwaway git repo whose main is the base the
# change is measured from (refs/remotes/origin/main). A case writes the formula
# or the skill into the working tree and runs the lint on it from the repo's
# root.
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
  mkdir -p "$REPO/formulas"
  g init -q -b main
  g config user.email t@t
  g config user.name t
  g config commit.gpgsign false
  base_formula > "$REPO/$F"
  printf 'readme\n' > "$REPO/README.md"
  g add -A
  g commit -qm base
  g update-ref refs/remotes/origin/main HEAD
}

# run_lint <args> — runs the lint from the repo root; sets rc and OUT.
run_lint() {
  if OUT=$(cd "$REPO" && bash "$SUT" "$@" 2>&1); then rc=0; else rc=$?; fi
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
expect 0 "no formula or skill among the files: exit 0" "no formula or skill file given"

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

with_step new "$(block "\"\$(gc gc-toolkit scripts-dir)/new.sh\" --check <test|lint|build> --bead <the PR's bead>")" > "$REPO/$F"
run_lint "$F"
expect 0 "placeholders, one naming alternatives and one with an apostrophe, are words of one call: exit 0"

# The gctk-bin block sets GCTK to the one tested line, so a block that holds it
# and one gctk call is one call. Between the markers, only an assignment to
# GCTK that runs no command weighs nothing.
GCTK_BLOCK='# >>> gctk-bin
GCTK="${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"
# <<< gctk-bin'
with_step new "$(block "$GCTK_BLOCK"$'\n''"$GCTK" bead takeaway "$X" y')" > "$REPO/$F"
run_lint "$F"
expect 0 "a step whose block is the gctk-bin block and one gctk call: exit 0"

with_step new "$(block '# >>> gctk-bin
GCTK=x;echo
# <<< gctk-bin
"$GCTK" bead takeaway "$X" y')" > "$REPO/$F"
run_lint "$F"
expect 1 "a command joined to the gctk-bin assignment with no blank weighs: exit 1" "with 3 commands\. "

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

# A cd that && runs after the call moves the agent's own shell, which the call
# cannot do for its caller, so it and its && weigh nothing. Any other cd weighs.
with_step new "$(block '"$S/new.sh" "$X" && cd "$D"')" > "$REPO/$F"
run_lint "$F"
expect 0 "a cd that && runs after the call weighs nothing, nor does its &&: exit 0"

with_step new "$(block 'cd "$D" && "$S/new.sh" "$X"')" > "$REPO/$F"
run_lint "$F"
expect 1 "a cd ahead of the call weighs, and so does its &&: exit 1" "with 2 commands and control flow (&&)\. "

with_step new "$(block '"$S/new.sh" "$X" || cd "$D"')" > "$REPO/$F"
run_lint "$F"
expect 1 "a cd that runs when the call fails weighs, and so does its ||: exit 1" "with 2 commands and control flow (||)\. "

with_step new "$(block '"$S/new.sh" "$X" && cd "$D" && "$S/other.sh"')" > "$REPO/$F"
run_lint "$F"
expect 1 "a command after the cd weighs, and so does the && that runs it: exit 1" "with 2 commands and control flow (&&)\. "

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
if OUT=$(cd "$REPO" && PATH="$TMP/nopy" "$BASH" "$SUT" "$F" 2>&1); then rc=0; else rc=$?; fi
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

base_formula | sed 's#^"$GC_RIG_ROOT/assets/scripts/one.sh" --bead "$X"$#"$GC_RIG_ROOT/assets/scripts/one.sh" --bead "$X" \&\& cd "$D"#' > "$REPO/$F"
grep -qF '"$GC_RIG_ROOT/assets/scripts/one.sh" --bead "$X" && cd "$D"' "$REPO/$F" \
  && ok "the cd fixture ends step one's call in && cd" || bad "the cd fixture ends step one's call in && cd"
run_lint "$F"
expect 0 "a call that gains a cd that && runs after it stays one call: exit 0"

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

# --- Skill text. ---------------------------------------------------------------
# A skill's Markdown is weighed as step text is, with the skill, named by its
# directory, as the step: all its files together, and every skill file the
# change names in one pass, so a block pairs with its old self wherever it now
# sits. Here main's skill makes one call, whose placeholder names alternatives,
# and holds one old procedure in its SKILL.md and another in a reference, and a
# doc page outside any skill holds a third. A sub-pack's skill on main makes one
# gctk call through the gctk-bin block.
SK=skills/s/SKILL.md
MORE=skills/s/references/more.md
GSK=packs/sub/skills/m/SKILL.md
OLD_PROC='```bash
A=$(gc bd show "$B" --json)
if [ -n "$A" ]; then
  echo "$A"
fi
```'
MORE_PROC='```bash
gc bd list --json | jq length
```'

base_skill() {
  printf -- '---\nname: s\ndescription: A test skill.\n---\n\n# S\n\n## Call\n\nRun the call:\n'
  block '"$(gc gc-toolkit scripts-dir)/one.sh" --bead "$X" --verdict <approve|request-changes>'
  printf '\n\n## Old\n\nThe old procedure:\n%s\n' "$OLD_PROC"
}

# skill_with_old <text> — the base skill with the old procedure's block replaced.
skill_with_old() {
  base_skill | BODY="$1" awk '
    /^The old procedure:$/ { print; print ENVIRON["BODY"]; skip = 1; next }
    skip && /^```$/ { skip = 0; next }
    skip { next }
    { print }'
}

# new_skill <dir> <text> — a skill at <dir> whose SKILL.md holds the text from
# its line 8.
new_skill() {
  mkdir -p "$REPO/$1"
  printf -- '---\nname: %s\ndescription: A new skill.\n---\n\n# New\n\n%s\n' "${1##*/}" "$2" > "$REPO/$1/SKILL.md"
}

fresh_repo
mkdir -p "$REPO/skills/s/references" "$REPO/docs" "$REPO/${GSK%/*}"
base_skill > "$REPO/$SK"
printf '# More\n\nAnother old procedure:\n%s\n' "$MORE_PROC" > "$REPO/$MORE"
printf '# Guide\n\n%s\n' "$MORE_PROC" > "$REPO/docs/guide.md"
printf -- '---\nname: m\ndescription: A sub-pack skill.\n---\n\n# M\n\n%s\n' \
  "$(block "$GCTK_BLOCK"$'\n''"$GCTK" bead takeaway "$X" y')" > "$REPO/$GSK"
g add -A
g commit -qm skill
g update-ref refs/remotes/origin/main HEAD
skill_reset() { g reset -q --hard; g clean -qfd; }

skill_with_old "$OLD_PROC" | cmp -s - "$REPO/$SK" \
  && ok "the skill fixture's helper rewrites the old procedure in place" \
  || bad "the skill fixture's helper rewrites the old procedure in place"
run_lint "$SK"
expect 0 "an unchanged skill: exit 0" "0 formula file(s), 1 skill file(s), no procedure added"

base_skill | sed 's/^Run the call:$/Run this one call, as written:/' > "$REPO/$SK"
run_lint "$SK"
expect 0 "a skill edit that leaves its blocks alone: exit 0" "1 skill file(s), no procedure added"

new_skill skills/t "$(block 'gc bd list --json | jq -r .[].id')"
run_lint skills/t/SKILL.md
expect 1 "a new skill whose block is a procedure: exit 1" \
  "^skills/t/SKILL.md:9: skill text gains a procedure: the new skill skills/t has shell blocks that do more than call a script, with 2 commands\. "

# A control character other than a tab reads as a blank, so none can cut the
# line it sits in out of the lint's records.
skill_reset
new_skill skills/t "$(block "echo a$(printf '\034')b; echo c")"
run_lint skills/t/SKILL.md
expect 1 "a control character in a skill's line reads as a blank: exit 1" "with 2 commands\. "

skill_reset
new_skill skills/t "$(block '"$(gc gc-toolkit scripts-dir)/new.sh" --bead "$X"')"
run_lint skills/t/SKILL.md
expect 0 "a new skill whose block is one call: exit 0" "1 skill file(s), no procedure added"

skill_reset
new_skill skills/t "$(block "$GCTK_BLOCK"$'\n''"$GCTK" bead takeaway "$X" y')"
run_lint skills/t/SKILL.md
expect 0 "a new skill whose block is the gctk-bin block and one gctk call: exit 0" "1 skill file(s), no procedure added"

skill_reset
new_skill skills/t "$(block '# >>> gctk-bin
GCTK="$(command -v gctk)"
# <<< gctk-bin
"$GCTK" bead takeaway "$X" y')"
run_lint skills/t/SKILL.md
expect 1 "an assignment between the markers that runs a command weighs: exit 1" "with 2 commands\. "

skill_reset
new_skill skills/t "$(block '# >>> gctk-bin
GCTK="${GCTK_BIN:-x}"
gc bd show "$X"
# <<< gctk-bin
"$GCTK" bead takeaway "$X" y')"
run_lint skills/t/SKILL.md
expect 1 "any other command between the markers weighs: exit 1" "with 2 commands\. "

skill_reset
new_skill skills/t "$(block 'GCTK="${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"
"$GCTK" bead takeaway "$X" y')"
run_lint skills/t/SKILL.md
expect 1 "the assignment outside a gctk-bin block weighs: exit 1" "with 2 commands\. "

# A command joined to the assignment with no blank weighs, in a sub-pack's
# skill too, whose gctk-bin blocks gctk-bin.test.sh does not read.
for join in ';echo' '&&echo' '||echo' '|cat' '&echo'; do
  skill_reset
  new_skill packs/sub/skills/g "$(block '# >>> gctk-bin
GCTK="${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"'"$join"'
# <<< gctk-bin
"$GCTK" bead takeaway "$X" y')"
  run_lint packs/sub/skills/g/SKILL.md
  expect 1 "a command joined to the gctk-bin assignment by $join weighs: exit 1" "with 3 commands"
done

# The markers change what the assignment between them weighs, so they are part
# of the text a block pairs by, and a block that only loses them is edited.
skill_reset
run_lint "$GSK"
expect 0 "main's sub-pack skill, a gctk-bin block and one gctk call, unchanged: exit 0" "1 skill file(s), no procedure added"
sed '/gctk-bin/d' "$REPO/$GSK" > "$TMP/gsk.md"
cat "$TMP/gsk.md" > "$REPO/$GSK"
run_lint "$GSK"
expect 1 "a block that only loses its gctk-bin markers weighs the assignment: exit 1" \
  "^$GSK:[0-9]*: skill text gains a procedure: skill packs/sub/skills/m gains shell blocks that do more than call a script, with 2 commands\. "

skill_reset
base_skill | awk '{ print } /^  echo "\$A"$/ { print "  gc runtime drain-ack" }' > "$REPO/$SK"
run_lint "$SK"
expect 1 "an edit that adds a command to a skill's procedure: exit 1" \
  "in skill skills/s, the shell blocks that do more than call a script grow from 3 commands and 1 control-flow construct to 4 commands and 1 control-flow construct"
line=$(grep -n '^  gc runtime drain-ack$' "$REPO/$SK" | cut -d: -f1)
grep -q "^$SK:$line: skill text gains a procedure" <<< "$OUT" \
  && ok "the finding names the skill file and the line the change adds" \
  || bad "the finding names the skill file and the line the change adds (want $SK:$line): $OUT"

skill_reset
skill_with_old "$(block '"$(gc gc-toolkit scripts-dir)/two.sh" --bead "$B"')" > "$REPO/$SK"
run_lint "$SK"
expect 0 "a skill that trades its procedure for a call: exit 0" "1 skill file(s), no procedure added"

skill_reset
skill_with_old "" > "$REPO/$SK"
run_lint "$SK"
expect 0 "a skill edit that only removes: exit 0" "1 skill file(s), no procedure added"

# A placeholder outside a quote is one word, since the agent writes a value in
# its place: a | between its alternatives is no pipe, and an apostrophe in it
# opens no quote.
skill_reset
new_skill skills/t "$(block '"$(gc gc-toolkit scripts-dir)/two.sh" --bead "$X" --verdict <approve|request-changes>')"
run_lint skills/t/SKILL.md
expect 0 "a new skill whose one call names alternatives in a placeholder: exit 0" "1 skill file(s), no procedure added"

skill_reset
new_skill skills/t "$(block "gc bd show <the PR's bead> --json
gc bd show \"\$Y\"")"
run_lint skills/t/SKILL.md
expect 1 "an apostrophe in a placeholder hides no command after it: exit 1" "with 2 commands\. "

skill_reset
new_skill skills/t "$(block "K=\$(\"\$S/key.sh\" --bead <the PR's bead>)
gc bd show \"\$K\"")"
run_lint skills/t/SKILL.md
expect 1 "an apostrophe in a placeholder inside a substitution hides no command after it: exit 1" "with 2 commands\. "

skill_reset
new_skill skills/t "$(block 'sort <in.txt | uniq >out.txt')"
run_lint skills/t/SKILL.md
expect 1 "a redirection is no placeholder, so a pipe between its < and a later > counts: exit 1" "with 2 commands\. "

# Text between a < and a > that holds shell syntax is no placeholder either,
# with no blank before the >.
skill_reset
new_skill skills/t "$(block 'sort <in.txt | uniq>out.txt')"
run_lint skills/t/SKILL.md
expect 1 "a pipe beside a blank between a < and a > is no placeholder: exit 1" "with 2 commands\. "

skill_reset
new_skill skills/t "$(block 'cat <in.txt && echo yes>out.txt')"
run_lint skills/t/SKILL.md
expect 1 "an && between a < and a > is no placeholder: exit 1" "with 2 commands and control flow (&&)\. "

for text in 'cat <in.txt; echo yes>out.txt' 'cat <in.txt & echo yes>out.txt' 'cat <in.txt||echo no>out.txt' \
  'sort <in.txt |uniq>out.txt' 'cat <in.txt|>out.txt' 'cat <in $(a|b)>out' 'cat <in `a|b`>out'; do
  skill_reset
  new_skill skills/t "$(block "$text")"
  run_lint skills/t/SKILL.md
  expect 1 "shell syntax between a < and a > is no placeholder, in $text: exit 1" "skill text gains a procedure"
done

# Main's one call names alternatives in a placeholder, so it weighs nothing, and
# a change that rewrites it into a procedure gains one.
skill_reset
base_skill | sed 's#^"\$(gc gc-toolkit scripts-dir)/one.sh" .*$#gc bd show "$X" | jq -r .title#' > "$REPO/$SK"
grep -qx 'gc bd show "$X" | jq -r .title' "$REPO/$SK" && ok "the rewrite fixture replaces main's one call" \
  || bad "the rewrite fixture replaces main's one call"
run_lint "$SK"
expect 1 "a one call whose placeholder names alternatives, rewritten into a procedure: exit 1" \
  "skill skills/s gains shell blocks that do more than call a script, with 2 commands\. "

# A skill is weighed whole, so a procedure that leaves one of its files pays
# for a lighter one that another of its files gains.
skill_reset
skill_with_old "" > "$REPO/$SK"
printf '\n%s\n' "$(block 'gc bd show "$X" | jq -r .title')" >> "$REPO/$MORE"
run_lint "$SK" "$MORE"
expect 0 "a skill whose files trade a procedure for a lighter one: exit 0" "2 skill file(s), no procedure added"

run_lint "$MORE"
expect 1 "the lighter procedure alone, its trade unnamed, weighs: exit 1" \
  "^$MORE:9: skill text gains a procedure: skill skills/s gains shell blocks that do more than call a script, with 2 commands\. "

skill_reset
skill_with_old "" | BLOCK="$OLD_PROC" awk '/^Run the call:$/ { print ENVIRON["BLOCK"] } { print }' > "$REPO/$SK"
[ "$(grep -c '^A=\$(gc bd show' "$REPO/$SK")" = 1 ] && ok "the section-move fixture holds the procedure once" \
  || bad "the section-move fixture holds the procedure once"
run_lint "$SK"
expect 0 "a block moved unedited to another section of its skill: exit 0" "1 skill file(s), no procedure added"

skill_reset
skill_with_old "" > "$REPO/$SK"
printf '\n%s\n' "$OLD_PROC" >> "$REPO/$MORE"
run_lint "$SK" "$MORE"
expect 0 "a block moved unedited to another file of its skill: exit 0" "2 skill file(s), no procedure added"

skill_reset
skill_with_old "" > "$REPO/$SK"
new_skill skills/u "$OLD_PROC"
run_lint "$SK" skills/u/SKILL.md
expect 0 "a block moved unedited to another skill: exit 0" "2 skill file(s), no procedure added"

skill_reset
g rm -q "$MORE"
{ base_skill; printf '\n%s\n' "$MORE_PROC"; } > "$REPO/$SK"
run_lint "$SK" "$MORE"
expect 0 "a block moved out of a file the change deletes pairs with its old self: exit 0" "2 skill file(s), no procedure added"

# The copy goes into a skill named after the one it came from, so its finding
# maps a line past the first file's lines back to the file it is in.
skill_reset
new_skill skills/u "$OLD_PROC"
run_lint "$SK" skills/u/SKILL.md
expect 1 "a procedure copied into another skill weighs on the skill it went into: exit 1" \
  "^skills/u/SKILL.md:9: skill text gains a procedure: the new skill skills/u has shell blocks that do more than call a script, with 3 commands and control flow (if)\. "

skill_reset
g mv skills/s skills/s2
run_lint skills/s2/SKILL.md skills/s2/references/more.md
expect 0 "a renamed skill is compared with its old paths: exit 0" "2 skill file(s), no procedure added"

# A listing made without rename detection names a renamed file's old path too.
# The old text is read once, as the renamed file's, so it cannot weigh as an
# old procedure that a new one is traded against. The skill now holds two
# copies of one procedure, and the finding may name either.
skill_reset
g mv "$MORE" skills/s/references/other.md
{ base_skill; printf '\n%s\n' "$MORE_PROC"; } > "$REPO/$SK"
run_lint "$SK" "$MORE" skills/s/references/other.md
expect 1 "a renamed file's old path, named too, is read once: exit 1" \
  "^skills/s/[^:]*:[0-9]*: skill text gains a procedure: skill skills/s gains shell blocks that do more than call a script, with 2 commands\. "

skill_reset
g mv docs/guide.md skills/s/references/guide.md
run_lint skills/s/references/guide.md
expect 1 "a file moved into a skill from outside one is new skill text: exit 1" \
  "skill skills/s gains shell blocks that do more than call a script, with 2 commands\. "

for dir in packs/sub/skills/v agents/a/skills/w; do
  skill_reset
  new_skill "$dir" "$MORE_PROC"
  run_lint "$dir/SKILL.md"
  expect 1 "a skill under $dir is skill text: exit 1" "^$dir/SKILL.md:9: skill text gains a procedure: the new skill $dir has"
done

# A skill's reference can be a symlink to a prompt fragment, which is not the
# skill's own text.
skill_reset
mkdir -p "$REPO/template-fragments"
printf '# Frag\n\n%s\n' "$MORE_PROC" > "$REPO/template-fragments/frag.template.md"
ln -s ../../../template-fragments/frag.template.md "$REPO/skills/s/references/frag.template.md"
run_lint skills/s/references/frag.template.md
expect 0 "a skill file that is a symlink is skipped: exit 0" "no formula or skill file given"

# A block a skill file leaves open ends with the file: it is weighed there, and
# the next file's text is not its own.
skill_reset
new_skill skills/t "$(printf 'Run:\n```bash\necho first; echo second')"
run_lint skills/t/SKILL.md
expect 1 "a block a skill file leaves open is weighed: exit 1" "with 2 commands\. "

skill_reset
new_skill skills/t "$(printf 'Run:\n```bash\n"$S/new.sh" --bead "$X"')"
printf '# B\n\nfirst; second | third\n```\n' > "$REPO/skills/t/b.md"
run_lint skills/t/SKILL.md skills/t/b.md
expect 0 "a block a skill file leaves open ends with the file: exit 0" "2 skill file(s), no procedure added"

skill_reset
base_skill | sed 's/^Run the call:$/Run this one call, as written:/' > "$REPO/$SK"
if OUT=$(cd "$REPO" && PATH="$TMP/nopy" "$BASH" "$SUT" "$SK" 2>&1); then rc=0; else rc=$?; fi
expect 0 "a change that names no formula needs no Python: exit 0" "1 skill file(s), no procedure added"

skill_reset
chmod 000 "$REPO/$SK"
if [ -r "$REPO/$SK" ]; then
  echo "skip - an unreadable skill file (running as a user that reads mode 000)"
else
  run_lint "$SK"
  expect 2 "an unreadable skill file: exit 2" "cannot read $SK"
fi
chmod 644 "$REPO/$SK"

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
