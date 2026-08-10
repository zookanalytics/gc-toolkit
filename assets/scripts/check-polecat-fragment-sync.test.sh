#!/usr/bin/env bash
# Hermetic test for doctor/check-polecat-fragment-sync (tk-t41dq).
#
# THE BUG the check guards: gc-toolkit's polecat doctrine IS the fragment list,
# and that list is written twice with no propagation between the copies —
# pack.toml's `[[patches.agent]] name = "polecat"` inject_fragments_append for
# the imported gastown pool, and inject_fragments in each native agent.toml
# that shares the base prompt by reference. A fragment added to one and
# forgotten in the other leaves that pool priming cleanly, exit 0, and running
# the UNPATCHED base doctrine for exactly what the fragment corrected.
#
# What is exercised here:
#   * the ERROR arm, both directions (a pool missing a fragment, and a pool
#     carrying one the patch does not);
#   * a native pool that declares NO inject_fragments at all — maximal drift,
#     not an opt-out;
#   * the scoping rules that decide WHICH files are compared: only the
#     name = "polecat" patch block (not a sibling agent's list) and only agents
#     that reference the base prompt (not ones with their own prompt file);
#   * comment-stripping inside the array, which is what keeps the real
#     pack.toml's in-array prose from being scraped as fragment names;
#   * the fail-CLOSED arms — a missing patch block or an unparseable list warns
#     rather than passing, because an empty expected set compares clean against
#     everything, which is the false-green the check exists to remove;
#   * a POSITIVE CONTROL over the real shipped pack.toml + agents/, so a
#     passing suite cannot mean "the parser matches nothing anymore".
#
# No live city, Dolt, network, or gc binary — only awk/comm and a tmpdir.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
CHECK="$ROOT/doctor/check-polecat-fragment-sync/run.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

# Build a throwaway pack dir. $1 = name, $2 = pack.toml body,
# $3 = polecat-codex agent.toml body (empty string = do not create the agent).
mkpack() {
    local name="$1" packtoml="$2" agenttoml="$3"
    local p="$TMP/$name"
    mkdir -p "$p/agents"
    printf '%s\n' "$packtoml" > "$p/pack.toml"
    if [ -n "$agenttoml" ]; then
        mkdir -p "$p/agents/polecat-codex"
        printf '%s\n' "$agenttoml" > "$p/agents/polecat-codex/agent.toml"
    fi
    printf '%s' "$p"
}

SHARED_PROMPT='prompt_template = "gastown//agents/polecat/prompt.template.md"'

PACK_OK='[pack]
name = "t"
schema = 2

[[patches.agent]]
name = "deacon"
inject_fragments_append = ["canonical-self-rename"]

[[patches.agent]]
name = "polecat"
inject_fragments_append = [
    "polecat-convoys",
    "polecat-append-notes",
    "polecat-non-impl-done",
]'

# --- 1. In sync -------------------------------------------------------------
P=$(mkpack insync "$PACK_OK" "$SHARED_PROMPT
inject_fragments = [\"polecat-convoys\", \"polecat-append-notes\", \"polecat-non-impl-done\"]")
OUT=$(GC_PACK_DIR="$P" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "0" "matching fragment sets pass"
has "$OUT" "polecat-codex" "the OK line names the pool it compared"

# --- 2. Order differs, membership does not ----------------------------------
# Set equality by design: order changes reading sequence, not doctrine.
P=$(mkpack reordered "$PACK_OK" "$SHARED_PROMPT
inject_fragments = [\"polecat-non-impl-done\", \"polecat-convoys\", \"polecat-append-notes\"]")
OUT=$(GC_PACK_DIR="$P" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "0" "a reordered but identical set is not a finding"

# --- 3. ERROR: the pool is missing a fragment -------------------------------
# The tk-t41dq case: the --notes correction wired into pack.toml only.
P=$(mkpack missing "$PACK_OK" "$SHARED_PROMPT
inject_fragments = [\"polecat-convoys\", \"polecat-non-impl-done\"]")
OUT=$(GC_PACK_DIR="$P" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "2" "a pool missing a fragment is an ERROR"
has "$OUT" "missing [polecat-append-notes]" "the finding names the missing fragment"
has "$OUT" "agents/polecat-codex/agent.toml" "the finding names the file to fix"

# --- 4. ERROR: the pool carries one the patch does not ----------------------
# Drift in the other direction is equally a divergence, and equally silent.
P=$(mkpack extra "$PACK_OK" "$SHARED_PROMPT
inject_fragments = [\"polecat-convoys\", \"polecat-append-notes\", \"polecat-non-impl-done\", \"file-work-records\"]")
OUT=$(GC_PACK_DIR="$P" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "2" "a pool with an extra fragment is an ERROR"
has "$OUT" "extra [file-work-records]" "the finding names the extra fragment"

# --- 5. ERROR: the pool declares no fragments at all ------------------------
P=$(mkpack nofrags "$PACK_OK" "$SHARED_PROMPT")
OUT=$(GC_PACK_DIR="$P" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "2" "a sharing pool with no inject_fragments is an ERROR, not an opt-out"
has "$OUT" "polecat-append-notes" "the no-fragments finding lists what it is missing"

# --- 6. An agent with its own prompt file is out of the class ---------------
# Whole-file prompts have no base doctrine to patch, so they are not compared.
P=$(mkpack ownprompt "$PACK_OK" "provider = \"gemini\"
inject_fragments = [\"nothing-like-the-patch\"]")
OUT=$(GC_PACK_DIR="$P" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "0" "an agent that does not reference the base prompt is not compared"
has "$OUT" "nothing to keep in sync" "and the OK line says why nothing was compared"

# --- 7. Comments inside the array are not scraped as fragment names ---------
# The real pack.toml carries prose INSIDE the polecat array, and that prose
# quotes prompt section headings. A naive quote-scrape reads those as names and
# then reports every pool as missing them.
PACK_COMMENTED='[pack]
name = "t"

[[patches.agent]]
name = "polecat"
inject_fragments_append = [
    "polecat-convoys",
    # Supersedes "### The Done Sequence" and "## FINAL REMINDER" in base.
    "polecat-append-notes",  # trailing comment with a "quoted" word
    "polecat-non-impl-done",
]'
P=$(mkpack commented "$PACK_COMMENTED" "$SHARED_PROMPT
inject_fragments = [\"polecat-convoys\", \"polecat-append-notes\", \"polecat-non-impl-done\"]")
OUT=$(GC_PACK_DIR="$P" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "0" "quoted prose inside the array is not mistaken for a fragment name"
hasnt "$OUT" "FINAL REMINDER" "the comment's quoted heading never enters the fragment set"

# --- 8. The comparison is scoped to the name = "polecat" block --------------
# A sibling patch block's list must not stand in for a missing polecat one.
PACK_NO_POLECAT='[pack]
name = "t"

[[patches.agent]]
name = "witness"
inject_fragments_append = ["polecat-convoys", "polecat-append-notes", "polecat-non-impl-done"]'
P=$(mkpack nopolecat "$PACK_NO_POLECAT" "$SHARED_PROMPT
inject_fragments = [\"polecat-convoys\", \"polecat-append-notes\", \"polecat-non-impl-done\"]")
OUT=$(GC_PACK_DIR="$P" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "1" "no polecat patch block warns instead of borrowing a sibling's list"
has "$OUT" "UNVERIFIED" "the warning says the comparison did not happen"

# --- 9. Fail-closed: a polecat block with no parseable list -----------------
# An empty expected set compares clean against every pool. Warn, never pass.
PACK_EMPTY='[pack]
name = "t"

[[patches.agent]]
name = "polecat"
overlay_dir = "overlays/whatever"'
P=$(mkpack emptylist "$PACK_EMPTY" "$SHARED_PROMPT
inject_fragments = [\"anything\"]")
OUT=$(GC_PACK_DIR="$P" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "1" "a polecat patch with no inject_fragments_append warns"
has "$OUT" "UNVERIFIED" "the empty-expected-set warning is explicit about not verifying"

# --- 10. Degenerate inputs skip cleanly, they do not crash ------------------
mkdir -p "$TMP/nopack"
OUT=$(GC_PACK_DIR="$TMP/nopack" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "0" "a dir with no pack.toml is a clean skip"
P=$(mkpack noagents "$PACK_OK" "")
rmdir "$P/agents"
OUT=$(GC_PACK_DIR="$P" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "0" "a pack with no agents/ is a clean skip"

# --- 11. Positive control over the REAL shipped pack ------------------------
# Pins the check to the files it actually guards. Without this, every arm above
# could pass against synthetic fixtures while the parser silently matched
# nothing in the real pack.toml — a green suite over a dead check.
OUT=$(GC_PACK_DIR="$ROOT" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "0" "shipped pack: the real polecat fragment lists are in sync"
has "$OUT" "polecat-codex" "shipped pack: the real polecat-codex pool is found and compared"
has "$OUT" "polecat-append-notes" "shipped pack: the tk-t41dq fragment is in the compared set"
has "$OUT" "polecat-non-impl-done" "shipped pack: the pre-existing fragments are still parsed"

echo
echo "check-polecat-fragment-sync: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
