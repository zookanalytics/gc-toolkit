#!/usr/bin/env bash
# Hermetic test for doctor/check-cycle-recycle-hook. Fixture pack only — the
# check reads pack.toml and the agent prompts, with no gc, city, or network.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-check-cycle-recycle-hook-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2')" ;; *) ok "$3" ;; esac; }

P="$TMP/pack"
run() { GC_PACK_DIR="$P" bash "$CHECK" 2>&1; }

reset()  { rm -rf "$P"; mkdir -p "$P/agents"; printf '[pack]\nname = "fixture"\n' > "$P/pack.toml"; }
# One [[patches.agent]] stanza carrying an overlay_dir.
patch()  { printf '\n[[patches.agent]]\nname = "%s"\noverlay_dir = "%s"\n' "$1" "$2" >> "$P/pack.toml"; }
# An agent with its own prompt that injects the fragment, or does not.
inject() { mkdir -p "$P/agents/$1"; : > "$P/agents/$1/agent.toml"; printf '# prompt\n{{ template "heartbeat-no-consent-ui" . }}\n' > "$P/agents/$1/prompt.template.md"; }
plain()  { mkdir -p "$P/agents/$1"; : > "$P/agents/$1/agent.toml"; printf '# prompt\nno doctrine\n' > "$P/agents/$1/prompt.template.md"; }
# An agent that shares another file as its prompt (no own prompt.template.md).
shares() { mkdir -p "$P/agents/$1"; printf 'prompt_template = "%s"\n' "$2" > "$P/agents/$1/agent.toml"; }

# --- 1. matched sets pass ----------------------------------------------------
reset
patch refinery "overlays/cycle-recycle"; patch witness "overlays/cycle-recycle"
inject refinery; inject witness
OUT=$(run); RC=$?
eq "$RC" "0" "the overlay carriers and the fragment injectors being equal passes"
has "$OUT" "OK:" "the pass message is the OK line"
has "$OUT" "refinery,witness" "the shared set is listed, sorted"

# --- 2. overlay but no fragment is an ERROR ----------------------------------
plain witness   # witness keeps the overlay; its prompt no longer injects
OUT=$(run); RC=$?
eq "$RC" "2" "a role with the overlay but no fragment is an ERROR"
has "$OUT" "\"witness\" carries overlay_dir" "the role that recycles without the doctrine is named"
has "$OUT" "injects no" "the finding says the fragment is missing"
hasnt "$OUT" "\"refinery\" carries" "the matched role is not flagged"

# --- 3. fragment but no overlay is an ERROR ----------------------------------
reset
patch refinery "overlays/cycle-recycle"
inject refinery; inject deacon   # deacon injects but has no overlay stanza
OUT=$(run); RC=$?
eq "$RC" "2" "a role injecting the fragment with no overlay is an ERROR"
has "$OUT" "\"deacon\" injects" "the role with dead doctrine is named"
has "$OUT" "carries no overlay_dir" "the finding says the overlay is missing"

# --- 4. both directions at once → two findings -------------------------------
reset
patch refinery "overlays/cycle-recycle"   # overlay, but its prompt is plain → overlay-only
plain refinery
inject deacon                             # fragment, no overlay → fragment-only
OUT=$(run); RC=$?
eq "$RC" "2" "a mismatch in both directions errors"
has "$OUT" "2 finding(s)" "both halves are reported"
has "$OUT" "refinery" "the overlay-only role is named"
has "$OUT" "deacon" "the fragment-only role is named"

# --- 5. injection is read from the RESOLVED prompt_template ------------------
# refinery carries the overlay and shares a template that injects, and has no
# prompt.template.md of its own — so a check that read the directory default
# would wrongly flag it overlay-only. A pass proves the pointer is followed.
reset
mkdir -p "$P/prompts"
printf '{{ template "heartbeat-no-consent-ui" . }}\n' > "$P/prompts/shared.md"
patch refinery "overlays/cycle-recycle"
shares refinery "prompts/shared.md"
OUT=$(run); RC=$?
eq "$RC" "0" "a prompt_template pointer to an injecting file counts as injection"
has "$OUT" "refinery" "the role resolving through the pointer is in the set"

# --- 6. a shared NON-injecting template is not a false injector --------------
# The converse-* shape: variants share a base prompt that injects nothing.
# Neither the base nor the variant should read as a fragment injector.
reset
plain base
shares variant "agents/base/prompt.template.md"
OUT=$(run); RC=$?
eq "$RC" "0" "sharing a plain base template injects nothing"
has "$OUT" "nothing to assert" "no overlay and no fragment is the empty-set pass"

# --- 7. a different overlay alone asserts nothing ----------------------------
reset
patch worker "overlays/work-context"
plain worker
OUT=$(run); RC=$?
eq "$RC" "0" "an unrelated overlay and no fragment is the empty-set pass"
has "$OUT" "nothing to assert" "it is the empty-set message"

# --- 8. stanza field order and inline comments do not fool the parser --------
reset
# overlay_dir BEFORE name, a trailing comment on the value, and a full-line
# comment that names the overlay for nobody.
printf '\n[[patches.agent]]\noverlay_dir = "overlays/cycle-recycle"  # trailing\nname = "refinery"\n# overlay_dir = "overlays/cycle-recycle" belongs to no stanza\n' >> "$P/pack.toml"
inject refinery
OUT=$(run); RC=$?
eq "$RC" "0" "overlay_dir before name still pairs with the stanza; a commented overlay is ignored"
has "$OUT" "refinery" "the correctly-parsed carrier is in the set"
hasnt "$OUT" "finding(s)" "the decoy comment adds no phantom carrier"

# --- 9. fail-closed: no pack.toml warns, never passes ------------------------
rm -rf "$P"; mkdir -p "$P"
OUT=$(run); RC=$?
eq "$RC" "1" "a missing pack.toml warns rather than passing"
has "$OUT" "undetermined" "the warning says the answer is unknown"

echo
echo "check-cycle-recycle-hook: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
