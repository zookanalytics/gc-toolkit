#!/usr/bin/env bash
# Hermetic test for lint-step-text.sh — the lint that fails a formula change
# adding a procedure to step text.
#
# The defects it guards against: a single script call read as a procedure (a
# substitution in an argument, a here-document's body, a quoted separator, a
# redirection, a TOML-escaped continuation), a procedure read as a single call
# (a pipeline, a sequence, a substitution holding a pipeline, && or ||), step
# text that predates the rule failing because a change touched its file, a
# moved or trimmed block read as new, a branch listed as in flight stalled by
# its own lines, a branch built on it let through with lines of its own, and a
# change it cannot read passing as clean.
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
