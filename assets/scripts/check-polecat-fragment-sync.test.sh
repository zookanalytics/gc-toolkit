#!/usr/bin/env bash
# Hermetic test for doctor/check-polecat-fragment-sync (tk-t41dq, tk-0981e).
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
#   * the DECLARED EXCEPTIONS (tk-0981e), in all three directions that make one
#     an expectation rather than a mute button: honoured on its own pool,
#     REQUIRED there, still extra anywhere else, and warned about once the patch
#     re-absorbs it;
#   * a POSITIVE CONTROL over the real shipped pack.toml + agents/, so a
#     passing suite cannot mean "the parser matches nothing anymore" — and which
#     pins both halves of the NARROW disposition: polecat-non-impl-done absent
#     from the patch list, present as a declared exception.
#
# Fixture pools are named `polecat-fixture` unless an arm is specifically about
# the exception table, which is keyed on the REAL pool name (`polecat-codex`).
# Keeping the generic arms off that name is what stops them from inheriting the
# shipped exception and testing something other than what they claim to.
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
# $3 = native agent.toml body (empty string = do not create the agent),
# $4 = that agent's pool directory name (default: a name the shipped exception
# table does not mention, so generic arms exercise plain set equality).
mkpack() {
    local name="$1" packtoml="$2" agenttoml="$3" pool="${4:-polecat-fixture}"
    local p="$TMP/$name"
    mkdir -p "$p/agents"
    printf '%s\n' "$packtoml" > "$p/pack.toml"
    if [ -n "$agenttoml" ]; then
        mkdir -p "$p/agents/$pool"
        printf '%s\n' "$agenttoml" > "$p/agents/$pool/agent.toml"
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
    "file-work-records",
]'

# --- 1. In sync -------------------------------------------------------------
P=$(mkpack insync "$PACK_OK" "$SHARED_PROMPT
inject_fragments = [\"polecat-convoys\", \"polecat-append-notes\", \"file-work-records\"]")
OUT=$(GC_PACK_DIR="$P" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "0" "matching fragment sets pass"
has "$OUT" "(polecat-fixture)" "the OK line names the pool it compared"

# --- 2. Order differs, membership does not ----------------------------------
# Set equality by design: order changes reading sequence, not doctrine.
P=$(mkpack reordered "$PACK_OK" "$SHARED_PROMPT
inject_fragments = [\"file-work-records\", \"polecat-convoys\", \"polecat-append-notes\"]")
OUT=$(GC_PACK_DIR="$P" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "0" "a reordered but identical set is not a finding"

# --- 3. ERROR: the pool is missing a fragment -------------------------------
# The tk-t41dq case: the --notes correction wired into pack.toml only.
P=$(mkpack missing "$PACK_OK" "$SHARED_PROMPT
inject_fragments = [\"polecat-convoys\", \"file-work-records\"]")
OUT=$(GC_PACK_DIR="$P" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "2" "a pool missing a fragment is an ERROR"
has "$OUT" "missing [polecat-append-notes]" "the finding names the missing fragment"
has "$OUT" "agents/polecat-fixture/agent.toml" "the finding names the file to fix"

# --- 4. ERROR: the pool carries one the patch does not ----------------------
# Drift in the other direction is equally a divergence, and equally silent.
P=$(mkpack extra "$PACK_OK" "$SHARED_PROMPT
inject_fragments = [\"polecat-convoys\", \"polecat-append-notes\", \"file-work-records\", \"heartbeat-no-consent-ui\"]")
OUT=$(GC_PACK_DIR="$P" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "2" "a pool with an extra fragment is an ERROR"
has "$OUT" "extra [heartbeat-no-consent-ui]" "the finding names the extra fragment"

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
    "file-work-records",
]'
P=$(mkpack commented "$PACK_COMMENTED" "$SHARED_PROMPT
inject_fragments = [\"polecat-convoys\", \"polecat-append-notes\", \"file-work-records\"]")
OUT=$(GC_PACK_DIR="$P" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "0" "quoted prose inside the array is not mistaken for a fragment name"
hasnt "$OUT" "FINAL REMINDER" "the comment's quoted heading never enters the fragment set"

# --- 8. The comparison is scoped to the name = "polecat" block --------------
# A sibling patch block's list must not stand in for a missing polecat one.
PACK_NO_POLECAT='[pack]
name = "t"

[[patches.agent]]
name = "witness"
inject_fragments_append = ["polecat-convoys", "polecat-append-notes", "file-work-records"]'
P=$(mkpack nopolecat "$PACK_NO_POLECAT" "$SHARED_PROMPT
inject_fragments = [\"polecat-convoys\", \"polecat-append-notes\", \"file-work-records\"]")
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

# --- 11. Declared exception: honoured on the pool it names ------------------
# tk-0981e narrowed polecat-non-impl-done (70 KB, 68% of the polecat prompt) to
# the codex pool that actually runs the non-impl path. Without the exception
# this is arm 4 — a pool carrying what the patch does not — and the check would
# fail the build on a divergence the ledger asked for on purpose.
P=$(mkpack excok "$PACK_OK" "$SHARED_PROMPT
inject_fragments = [\"polecat-convoys\", \"polecat-append-notes\", \"file-work-records\", \"polecat-non-impl-done\"]" polecat-codex)
OUT=$(GC_PACK_DIR="$P" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "0" "the declared polecat-codex exception is not reported as drift"
has "$OUT" "Declared exception: polecat-non-impl-done is expected on polecat-codex ONLY" \
    "the OK output states the exception instead of silently swallowing the name"

# --- 12. Declared exception: REQUIRED on the pool it names ------------------
# The distinction that makes an exception an expectation rather than a mute
# button. Tolerating the name would leave the one pool that depends on the
# fragment able to lose it silently — the original failure class, relocated.
P=$(mkpack excmissing "$PACK_OK" "$SHARED_PROMPT
inject_fragments = [\"polecat-convoys\", \"polecat-append-notes\", \"file-work-records\"]" polecat-codex)
OUT=$(GC_PACK_DIR="$P" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "2" "dropping the exception fragment from its own pool is an ERROR"
has "$OUT" "missing [polecat-non-impl-done]" "the finding names the fragment the exception requires"
has "$OUT" "agents/polecat-codex/agent.toml" "and the file that has to carry it"

# --- 13. Declared exception: scoped to its pool, extra anywhere else --------
P=$(mkpack excscope "$PACK_OK" "$SHARED_PROMPT
inject_fragments = [\"polecat-convoys\", \"polecat-append-notes\", \"file-work-records\", \"polecat-non-impl-done\"]")
OUT=$(GC_PACK_DIR="$P" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "2" "the exception fragment on a pool the table does not name is still extra"
has "$OUT" "extra [polecat-non-impl-done]" "the finding names it, on the pool that should not carry it"

# --- 14. Stale exception: the patch re-absorbed the fragment ----------------
# Not drift — the lists agree — but the table now documents a divergence that
# no longer exists, and the patch list lives in another file, so no reader can
# catch it by eye.
PACK_READDED='[pack]
name = "t"

[[patches.agent]]
name = "polecat"
inject_fragments_append = ["polecat-convoys", "polecat-append-notes", "file-work-records", "polecat-non-impl-done"]'
P=$(mkpack excstale "$PACK_READDED" "$SHARED_PROMPT
inject_fragments = [\"polecat-convoys\", \"polecat-append-notes\", \"file-work-records\", \"polecat-non-impl-done\"]" polecat-codex)
OUT=$(GC_PACK_DIR="$P" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "1" "an exception the patch has re-absorbed warns instead of passing quietly"
has "$OUT" "no longer describe a divergence" "the warning says what is stale, not that something is mis-injected"
has "$OUT" "the pack.toml polecat patch injects it too" "and names why the entry now grants nothing"

# --- 15. Positive control over the REAL shipped pack ------------------------
# Pins the check to the files it actually guards. Without this, every arm above
# could pass against synthetic fixtures while the parser silently matched
# nothing in the real pack.toml — a green suite over a dead check. The last two
# assertions pin both halves of the tk-0981e NARROW: the fragment is out of the
# patch list, and it is out of it *by declaration* rather than by omission.
OUT=$(GC_PACK_DIR="$ROOT" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "0" "shipped pack: the real polecat fragment lists are in sync"
has "$OUT" "(polecat-codex)" "shipped pack: the real polecat-codex pool is found and compared"
FRAGLINE=$(printf '%s\n' "$OUT" | grep '^Fragments: ')
has "$FRAGLINE" "polecat-append-notes" "shipped pack: the tk-t41dq fragment is in the compared set"
has "$FRAGLINE" "file-work-records" "shipped pack: the pre-existing fragments are still parsed"
hasnt "$FRAGLINE" "polecat-non-impl-done" "shipped pack: the narrowed fragment is NOT in the polecat patch list"
has "$OUT" "Declared exception: polecat-non-impl-done is expected on polecat-codex ONLY" \
    "shipped pack: it is absent by declaration, and the codex pool is held to carrying it"

echo
echo "check-polecat-fragment-sync: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
