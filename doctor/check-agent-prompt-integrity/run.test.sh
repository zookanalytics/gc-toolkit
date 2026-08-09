#!/usr/bin/env bash
# Hermetic test for doctor/check-agent-prompt-integrity/run.sh (tk-5wdy8).
#
# THE HOLE IT CLOSES: the check used to warn on the mere SPELLING of a
# prompt_template — any value carrying the cross-pack "<pack>//<subpath>"
# form — which made it structurally incapable of being right. It warned on
# healthy references (case 1: both live agents resolve to 243- and 326-line
# prompts) and stayed silent on the only configuration that actually renders
# the stub (case 2: a declared template that does not exist). Case 1 is the
# regression that matters; under the old check it exited 1.
#
# Every case drives the SHIPPED run.sh against a throwaway pack dir, a
# throwaway city, and a fake `gc` on PATH that emits a fixture config — so the
# check is exercised through its real interface (resolve, then test
# readability) with no live city, Dolt, or network.
#
# Covered:
#   (1)  every prompt_template resolves, incl. one outside the city tree
#        (the imported-pack/cross-pack case) -> OK (exit 0)   [was exit 1]
#   (2)  a declared template that does not exist -> ERROR (exit 2), naming
#        the agent                                            [was exit 0]
#   (3)  an agent with no prompt_template is skipped, not faulted
#   (4)  a RELATIVE template resolves against the city path -> OK
#   (5)  a RELATIVE template that is missing -> ERROR
#   (6)  no agents/ dir in the pack -> OK
#   (7)  gc not on PATH -> OK (resolution is a runtime property)
#   (8)  no city in scope -> OK
#   (9)  `gc config show` exits non-zero -> WARNING (exit 1), never a false OK
#   (10) `gc config show` prints nothing -> WARNING (exit 1)
#   (11) two missing templates -> both named and counted in the first line
#   (12) a prompt_template in a NON-agent table is not attributed to an agent
#   (13) a sub-table inside an agent block does not swallow the next agent
#
# Cases 9 and 10 are the fail-closed pair. An unverified check that reported OK
# would be indistinguishable from a verified-clean one, which is the failure
# mode the old check shipped with: a status nobody could act on.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/run.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { if grep -q -- "$1" "$2"; then ok "$3"; else bad "$3 (missing '$1' in: $(cat "$2"))"; fi; }
hasnt() { if grep -q -- "$1" "$2"; then bad "$3 (unexpected '$1' in: $(cat "$2"))"; else ok "$3"; fi; }

# case_dir <n> — throwaway pack + city + bin, with an agents/ dir so the
# check does not short-circuit on "no agents/".
case_dir() {
    local d="$TMP/$1"
    mkdir -p "$d/pack/agents/some-agent" "$d/city" "$d/bin"
    printf 'scope = "rig"\n' > "$d/pack/agents/some-agent/agent.toml"
    echo "$d"
}

# fake_gc <dir> <mode> — install a `gc` shim. mode: ok|fail|empty.
# It ignores its arguments exactly as the real command's contract allows here:
# the check only ever calls `gc --city <path> config show`.
fake_gc() {
    local d="$1" mode="$2"
    {
        echo '#!/usr/bin/env bash'
        case "$mode" in
            fail)  echo 'echo "config error" >&2; exit 3' ;;
            empty) echo 'exit 0' ;;
            *)     printf 'cat %s\n' "$(printf '%q' "$d/config.toml")" ;;
        esac
    } > "$d/bin/gc"
    chmod +x "$d/bin/gc"
}

# run_check <dir> [city-override] -> echoes exit code; output in <dir>/out
# BOTH city vars are pinned, never just GC_CITY_PATH: run.sh reads
# GC_CITY as the fallback, so a test that left it alone would inherit the
# REAL city from the runner's environment and quietly check the live config
# instead of the fixture. Case 8 is where that leak shows up.
run_check() {
    local d="$1" city="${2-$1/city}"
    PATH="$d/bin:$PATH" GC_PACK_DIR="$d/pack" GC_CITY_PATH="$city" GC_CITY="$city" \
        bash "$SCRIPT" > "$d/out" 2>&1
    echo $?
}

# ---------------------------------------------------------------- case 1
# The regression. A cross-pack reference that RESOLVES is healthy: the old
# check flagged this exact shape on both of the rig's live agents.
d="$(case_dir 1)"
mkdir -p "$d/imported-pack/agents/polecat" "$d/city/agents/local"
echo "canonical polecat doctrine" > "$d/imported-pack/agents/polecat/prompt.template.md"
echo "local doctrine" > "$d/city/agents/local/prompt.template.md"
cat > "$d/config.toml" <<EOF
[[agent]]
name = "polecat-codex"
prompt_template = "$d/imported-pack/agents/polecat/prompt.template.md"

[[agent]]
name = "local-agent"
prompt_template = "$d/city/agents/local/prompt.template.md"
EOF
fake_gc "$d" ok
eq "$(run_check "$d")" "0" "case 1: resolvable cross-pack reference is OK"
has "OK: all 2 agent" "$d/out" "case 1: counts both references"
has "polecat-codex" "$d/out" "case 1: names the out-of-city reference as informational"

# ---------------------------------------------------------------- case 2
# The hazard the check exists for: a declared template that is not there.
d="$(case_dir 2)"
cat > "$d/config.toml" <<EOF
[[agent]]
name = "ghost-agent"
prompt_template = "$d/imported-pack/agents/gone/prompt.template.md"
EOF
fake_gc "$d" ok
eq "$(run_check "$d")" "2" "case 2: unreadable template is an ERROR"
has "ghost-agent" "$d/out" "case 2: names the offending agent"
has "1 agent(s) would render the generic stub" "$d/out" "case 2: message states the consequence"

# ---------------------------------------------------------------- case 3
d="$(case_dir 3)"
cat > "$d/config.toml" <<EOF
[[agent]]
name = "no-template-agent"
work_dir = "somewhere"
EOF
fake_gc "$d" ok
eq "$(run_check "$d")" "0" "case 3: agent without a prompt_template is not faulted"
has "no agent declares a prompt_template" "$d/out" "case 3: says why it is OK"

# ---------------------------------------------------------------- case 4
d="$(case_dir 4)"
mkdir -p "$d/city/prompts"
echo "doctrine" > "$d/city/prompts/mayor.template.md"
cat > "$d/config.toml" <<EOF
[[agent]]
name = "rel-agent"
prompt_template = "prompts/mayor.template.md"
EOF
fake_gc "$d" ok
eq "$(run_check "$d")" "0" "case 4: relative template resolves against the city path"

# ---------------------------------------------------------------- case 5
d="$(case_dir 5)"
cat > "$d/config.toml" <<EOF
[[agent]]
name = "rel-ghost"
prompt_template = "prompts/absent.template.md"
EOF
fake_gc "$d" ok
eq "$(run_check "$d")" "2" "case 5: missing relative template is an ERROR"
has "rel-ghost" "$d/out" "case 5: names the offending agent"

# ---------------------------------------------------------------- case 6
d="$(case_dir 6)"
rm -rf "$d/pack/agents"
fake_gc "$d" ok
printf '[[agent]]\nname = "x"\nprompt_template = "/nope"\n' > "$d/config.toml"
eq "$(run_check "$d")" "0" "case 6: pack with no agents/ dir is OK"

# ---------------------------------------------------------------- case 7
d="$(case_dir 7)"
printf '[[agent]]\nname = "x"\nprompt_template = "/nope"\n' > "$d/config.toml"
# Deliberately no gc shim, and a PATH that cannot reach a real one. The shell
# and awk are symlinked in so stripping PATH removes `gc` and nothing else,
# and bash is invoked by absolute path so the interpreter itself does not
# depend on the PATH under test.
ln -s "$(command -v bash)" "$d/bin/bash"
ln -s "$(command -v awk)" "$d/bin/awk"
out_rc=$(PATH="$d/bin" GC_PACK_DIR="$d/pack" GC_CITY_PATH="$d/city" GC_CITY="$d/city" \
    "$d/bin/bash" "$SCRIPT" > "$d/out" 2>&1; echo $?)
eq "$out_rc" "0" "case 7: no gc on PATH is OK, not a finding"
has "not verifiable here" "$d/out" "case 7: says the check could not verify"

# ---------------------------------------------------------------- case 8
d="$(case_dir 8)"
printf '[[agent]]\nname = "x"\nprompt_template = "/nope"\n' > "$d/config.toml"
fake_gc "$d" ok
eq "$(run_check "$d" "")" "0" "case 8: no city in scope is OK"
has "no city in scope" "$d/out" "case 8: says why"

# ---------------------------------------------------------------- case 9
d="$(case_dir 9)"
fake_gc "$d" fail
eq "$(run_check "$d")" "1" "case 9: unresolvable config is a WARNING, not a false OK"
has "UNVERIFIED" "$d/out" "case 9: labels the result unverified"
hasnt "^OK:" "$d/out" "case 9: does not report OK"

# ---------------------------------------------------------------- case 10
d="$(case_dir 10)"
fake_gc "$d" empty
eq "$(run_check "$d")" "1" "case 10: empty config output is a WARNING"
has "UNVERIFIED" "$d/out" "case 10: labels the result unverified"

# ---------------------------------------------------------------- case 11
d="$(case_dir 11)"
cat > "$d/config.toml" <<EOF
[[agent]]
name = "ghost-one"
prompt_template = "/definitely/not/here/one.md"

[[agent]]
name = "ghost-two"
prompt_template = "/definitely/not/here/two.md"
EOF
fake_gc "$d" ok
eq "$(run_check "$d")" "2" "case 11: multiple missing templates are an ERROR"
has "2 agent(s) would render" "$d/out" "case 11: first line counts both"
has "ghost-one" "$d/out" "case 11: names the first"
has "ghost-two" "$d/out" "case 11: names the second"

# ---------------------------------------------------------------- case 12
# A prompt_template outside an [[agent]] block belongs to something else.
# TOML forbids a flat key after a sub-table opens, so ending the agent's
# key region at the next header is exactly the language's own scoping.
d="$(case_dir 12)"
cat > "$d/config.toml" <<EOF
[workspace]
prompt_template = "/not/an/agent/field.md"

[[agent]]
name = "fine-agent"
work_dir = "somewhere"
EOF
fake_gc "$d" ok
eq "$(run_check "$d")" "0" "case 12: non-agent prompt_template is not attributed to an agent"
hasnt "not/an/agent" "$d/out" "case 12: does not report the foreign field"

# ---------------------------------------------------------------- case 13
d="$(case_dir 13)"
cat > "$d/config.toml" <<EOF
[[agent]]
name = "first-agent"
work_dir = "somewhere"

[agent.pool]
size = 2

[[agent]]
name = "second-ghost"
prompt_template = "/definitely/not/here/second.md"
EOF
fake_gc "$d" ok
eq "$(run_check "$d")" "2" "case 13: a sub-table does not swallow the following agent"
has "second-ghost" "$d/out" "case 13: names the agent after the sub-table"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
