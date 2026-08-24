#!/usr/bin/env bash
# Hermetic test for doctor/check-one-anchor-per-pr (tk-qz6081, component-model I4).
#
# THE PROPERTY the check guards: a pull request has exactly one OPEN gating
# anchor, and an open gating anchor names exactly one pull request. The merge
# skill needs this to be true — it validates each anchor INDEPENDENTLY, so a PR
# claimed by two anchors is gated by the WEAKER of them (tk-ynz4b) — but since
# tk-3sdfq it COALESCES such a pair into a union gate and merges anyway. The
# merge is then safe and the ledger state is never repaired, so the condition is
# silent, self-perpetuating, and visible to nothing until this check.
#
# What is exercised here:
#   * both ERROR arms: (A) one PR claimed by two open gating anchors, and (B) one
#     open gating anchor naming two PR numbers;
#   * the ANCHOR PREDICATE, key by key — status, the merge_result marker, and all
#     three PR-number keys (pr_number, fork_pr, fork_pr_url). Each is asserted in
#     BOTH directions: the shape it must catch, and the neighbouring shape it must
#     NOT. A predicate that drifts from merge-skill.sh's stops backstopping it;
#   * REPOSITORY scoping — the same number in two different repositories is two
#     different pull requests and must never be reported as one, while the same
#     number in one repository claimed from two different STORES must be;
#   * the `?` (unresolvable origin) narrowing: store-local comparison only, so an
#     unknown repository cannot match another ledger that merely shares a number;
#   * the QUERY itself. If it drifts, the check silently stops seeing the beads it
#     exists to find, and reports clean over a store full of them;
#   * the fail-CLOSED arms. Every probe that cannot be READ must warn, never pass.
#     A check that reports OK when it cannot see reproduces the invisibility it
#     was written to remove.
#
# No live city, Dolt, network, git or beads — only jq, stub `gc`/`bd`/`git`, and
# a tmpdir.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

[ -x "$CHECK" ] || chmod +x "$CHECK" 2>/dev/null

mkdir -p "$TMP/stores" "$TMP/bin" "$TMP/origins"

# --- Fixtures ---------------------------------------------------------------
# Three stores. `alpha` and `beta` push to DIFFERENT repositories, which is what
# makes "same number, different repository" testable; `gamma` has no resolvable
# origin, which is the `?` narrowing.
cat > "$TMP/rigs.json" <<EOF
{"schema_version":"1","ok":true,"rigs":[
  {"name":"alpha","path":"$TMP/alpha"},
  {"name":"beta","path":"$TMP/beta"},
  {"name":"gamma","path":"$TMP/gamma"}
]}
EOF

printf 'https://github.com/acme/alpha.git' > "$TMP/origins/alpha"
printf 'git@github.com:acme/beta.git'      > "$TMP/origins/beta"
# gamma: no origin file -> the stub `git` fails -> unresolvable.

# anchor <id> <json-metadata-fragment>
# Always OPEN and always carrying the gating marker unless the fragment overrides.
anchor() {
    printf '{"id":"%s","status":"open","metadata":{"merge_result":"pull_request"%s}}' \
        "$1" "${2:+,$2}"
}
# raw <id> <status> <json-metadata-fragment> — full control, for the negatives.
raw() {
    printf '{"id":"%s","status":"%s","metadata":{%s}}' "$1" "$2" "$3"
}
store() { # store <name> <bead-json>...
    local name="$1"; shift
    local IFS=,
    printf '[%s]' "$*" > "$TMP/stores/$name.json"
}
clear_stores() { rm -f "$TMP"/stores/*.json; }

# --- Stubs ------------------------------------------------------------------
# `gc rig list`, answering from a file so a scenario can hand over malformed
# bytes. RIGS_RC forces a failed probe.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "rig list")
      rc="${RIGS_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"
      cat "$RIGS_JSON" ;;
  *) exit 0 ;;
esac
GC
chmod +x "$TMP/bin/gc"

# `git -C <path> remote get-url origin`: answers from $ORIGINS/<store>, keyed off
# the basename of the -C path. A missing file is an unresolvable origin, which is
# how `gamma` gets its `?`.
cat > "$TMP/bin/git" <<'GIT'
#!/usr/bin/env bash
path=""
prev=""
for a in "$@"; do
  [ "$prev" = "-C" ] && path="$a"
  prev="$a"
done
f="$ORIGINS/$(basename "$path")"
[ -f "$f" ] || exit 1
cat "$f"
GIT
chmod +x "$TMP/bin/git"

# `bd list`: answers per store from $STORES/<name>.json, keyed off the --db path.
# Every invocation appends its full argv to $BD_ARGS so the query itself can be
# asserted. BD_FAIL_STORE makes one named store fail; BD_EMPTY_STORE makes one
# return nothing at all (which is not the same as `[]`).
cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BD_ARGS"
db=""
prev=""
for a in "$@"; do
  [ "$prev" = "--db" ] && db="$a"
  prev="$a"
done
name=$(basename "$(dirname "$db")")
[ "$name" = "${BD_FAIL_STORE:-}" ] && exit 3
[ "$name" = "${BD_EMPTY_STORE:-}" ] && exit 0
f="$STORES/$name.json"
if [ -f "$f" ]; then cat "$f"; else printf '[]'; fi
BD
chmod +x "$TMP/bin/bd"

export PATH="$TMP/bin:$PATH"
export STORES="$TMP/stores"
export ORIGINS="$TMP/origins"
BD_ARGS="$TMP/bd-args.log"
export BD_ARGS

run_check() {
    : > "$BD_ARGS"
    RIGS_JSON="${RIGS_JSON_OVERRIDE:-$TMP/rigs.json}" \
    GC_PACK_DIR="$ROOT" bash "$CHECK" 2>&1
}

# --- 0. Positive control ----------------------------------------------------
# Prove the harness is real before trusting any verdict computed from it. A
# green run over stubs that answer nothing would pass every "not flagged" case
# for entirely the wrong reason.
eq "$(jq -r '.rigs | length' "$TMP/rigs.json" 2>/dev/null)" "3" \
   "positive control: the rig fixture parses and holds three stores"
eq "$(git -C "$TMP/alpha" remote get-url origin 2>/dev/null)" "https://github.com/acme/alpha.git" \
   "positive control: the git stub resolves alpha's origin"
eq "$(git -C "$TMP/gamma" remote get-url origin 2>/dev/null; echo "rc=$?")" "rc=1" \
   "positive control: gamma has NO resolvable origin"
clear_stores
store alpha "$(anchor a-1 '"pr_number":"7"')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "positive control: a single anchor on one PR is clean"
has "$OUT" "across 3 store(s)" "positive control: all three stores were actually scanned"

# --- 1. ERROR (A): two open anchors, one PR, one store ----------------------
clear_stores
store alpha "$(anchor a-1 '"pr_number":"7"')" "$(anchor a-2 '"pr_number":"7"')"
OUT=$(run_check); RC=$?
eq "$RC" "2" "two open gating anchors on one PR is an ERROR"
has "$OUT" "PR#7" "the error names the pull request"
has "$OUT" "a-1" "the error names the first anchor"
has "$OUT" "a-2" "the error names the second anchor"
has "$OUT" "github.com/acme/alpha" "the error qualifies the PR with the store's origin repository"

# --- 2. The query the check relies on ---------------------------------------
# Drop any one of these and the check reports clean over a store full of
# duplicates.
ARGS=$(cat "$BD_ARGS")
has "$ARGS" "--status open" "the scan asks for open beads"
has "$ARGS" "--metadata-field merge_result=pull_request" "the scan asks for the gating marker merge-skill enumerates on"
has "$ARGS" "--limit 0" "the scan is not silently truncated by a default limit"

# --- 3. ERROR (A) across stores, same repository -----------------------------
# One pull request can be claimed from two different ledgers. merge-skill reads
# only its own store and would never see this pair — it is the reason the check
# pools every store before grouping.
clear_stores
store alpha "$(anchor a-1 '"pr_number":"11","pr_url":"https://github.com/acme/shared/pull/11"')"
store beta  "$(anchor b-1 '"pr_number":"11","pr_url":"https://github.com/acme/shared/pull/11"')"
OUT=$(run_check); RC=$?
eq "$RC" "2" "one PR claimed from two different stores is an ERROR"
has "$OUT" "a-1 (alpha)" "the cross-store error names the first anchor and its store"
has "$OUT" "b-1 (beta)" "the cross-store error names the second anchor and its store"

# --- 4. NOT flagged: the same number in two DIFFERENT repositories -----------
# A PR NUMBER names a different pull request in every other repository. Keyed on
# the bare number these would be reported forever, and no operator could repair
# anything to clear it.
clear_stores
store alpha "$(anchor a-1 '"pr_number":"7"')"
store beta  "$(anchor b-1 '"pr_number":"7"')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "the same number in two different repositories is NOT a duplicate"

# --- 5. NOT flagged: a CLOSED bead sharing the PR ---------------------------
# merge-skill cannot enumerate a closed bead, so it is not a competing anchor.
# This is the ordinary shape after a coalesce or a land.
clear_stores
store alpha "$(anchor a-1 '"pr_number":"7"')" \
            "$(raw a-old closed '"merge_result":"pull_request","pr_number":"7"')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a closed bead sharing the PR is not a second anchor"
# ... and the status filter is what does it — flip only that byte and it fires.
clear_stores
store alpha "$(anchor a-1 '"pr_number":"7"')" \
            "$(raw a-old open '"merge_result":"pull_request","pr_number":"7"')"
OUT=$(run_check); RC=$?
eq "$RC" "2" "mutating that same bead to OPEN does fire — the status filter is load-bearing"

# --- 6. NOT flagged: a bead that is not a gating anchor ---------------------
# A review/rework child references the PR without gating it, and `tracking_only`
# records withhold merge_result by construction (tk-8329m). Neither is an anchor.
clear_stores
store alpha "$(anchor a-1 '"pr_number":"7"')" \
            "$(raw a-child open '"pr_number":"7"')" \
            "$(raw a-track open '"pr_number":"7","tracking_only":"true"')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a PR-referencing bead with no merge_result=pull_request is not an anchor"
# The marker is load-bearing too: give the child the gating marker and it fires.
clear_stores
store alpha "$(anchor a-1 '"pr_number":"7"')" \
            "$(raw a-child open '"pr_number":"7","merge_result":"pull_request"')"
OUT=$(run_check); RC=$?
eq "$RC" "2" "granting that child the gating marker does fire — the marker filter is load-bearing"

# --- 7. ERROR (B): one anchor, two PR numbers -------------------------------
clear_stores
store alpha "$(anchor a-1 '"pr_number":"7","fork_pr":"9"')"
OUT=$(run_check); RC=$?
eq "$RC" "2" "an open gating anchor naming two PR numbers is an ERROR"
has "$OUT" "names 2 pull requests" "the error says how many pull requests the anchor claims"
has "$OUT" "#7, #9" "the error lists both numbers"
has "$OUT" "a-1 (alpha)" "the error names the anchor and its store"

# --- 8. Every PR-number key is read -----------------------------------------
# merge-skill reads pr_number, fork_pr AND fork_pr_url. Reading only pr_number —
# as an earlier version of that pass did — made a fork-keyed anchor invisible to
# the guard that owns it. Each key must be able to collide with each other key.
clear_stores
store alpha "$(anchor a-1 '"pr_number":"21"')" "$(anchor a-2 '"fork_pr":"21"')"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a fork_pr-keyed anchor duplicates a pr_number-keyed one"
clear_stores
store alpha "$(anchor a-1 '"pr_number":"22"')" \
            "$(anchor a-3 '"fork_pr_url":"https://github.com/acme/alpha/pull/22"')"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a fork_pr_url-keyed anchor duplicates a pr_number-keyed one"

# --- 9. fork_pr_url naming ANOTHER repository is dropped --------------------
# That number is about somebody else's pull request. Keeping it would invent a
# duplicate out of two unrelated PRs that share a number.
clear_stores
store alpha "$(anchor a-1 '"pr_number":"23"')" \
            "$(anchor a-4 '"fork_pr_url":"https://github.com/other/repo/pull/23"')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a fork_pr_url in another repository is not a duplicate of this repository's number"

# --- 10. NOT flagged: an anchor naming no PR at all -------------------------
# A gating marker with nothing to gate is a different defect. Grouping such
# anchors would file every one of them in a store as a duplicate of the others.
clear_stores
store alpha "$(anchor a-1 '"branch":"x"')" "$(anchor a-2 '"branch":"y"')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "two anchors that name no PR are not duplicates of each other"

# --- 11. The `?` narrowing: unresolvable origin is store-LOCAL --------------
# gamma has no origin, so its unqualified anchors cannot be attributed to any
# repository. Comparing them across stores would match every repository at once.
clear_stores
store gamma "$(anchor g-1 '"pr_number":"31"')"
store alpha "$(anchor a-1 '"pr_number":"31"')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an unqualified anchor is NOT compared against another store's"
has "$OUT" "could not resolve an origin repository" "the narrowing is reported, not left silent"
# Within the SAME store, two unqualified anchors on one number are still a pair.
clear_stores
store gamma "$(anchor g-1 '"pr_number":"31"')" "$(anchor g-2 '"pr_number":"31"')"
OUT=$(run_check); RC=$?
eq "$RC" "2" "two unqualified anchors in ONE store are still a duplicate"
has "$OUT" "<unresolved repository>" "the finding says the repository could not be resolved"

# TWO stores that BOTH lack an origin. This is the case that actually pins the
# scoping: with `?` used as a bare comparison key rather than a store-scoped one,
# every unqualified anchor in the city collapses into one bucket and any two of
# them sharing a number are reported as a duplicate of each other. `gamma` alone
# cannot show that — there has to be a second unresolvable store for the wrong
# key to collide with.
printf '{"schema_version":"1","ok":true,"rigs":[{"name":"gamma","path":"%s"},{"name":"delta","path":"%s"}]}' \
    "$TMP/gamma" "$TMP/delta" > "$TMP/rigs-noorigin.json"
clear_stores
store gamma "$(anchor g-1 '"pr_number":"31"')"
store delta "$(anchor d-1 '"pr_number":"31"')"
OUT=$(RIGS_JSON_OVERRIDE="$TMP/rigs-noorigin.json" run_check); RC=$?
eq "$RC" "0" "two DIFFERENT origin-less stores sharing a number are not a duplicate"
hasnt "$OUT" "d-1" "the unqualified anchor in the other store is not named as a duplicate"

# --- 12. pr_url wins over the store's origin --------------------------------
# The repository comes from the anchor's own pr_url when it parses; the store's
# origin is only the fallback for an anchor that records none.
clear_stores
store alpha "$(anchor a-1 '"pr_number":"41","pr_url":"https://github.com/acme/elsewhere/pull/41"')" \
            "$(anchor a-2 '"pr_number":"41"')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an anchor whose pr_url names another repository is not a duplicate of an unqualified one"

# --- 13. Fail-closed: one store cannot be listed ----------------------------
# The strand in an unreadable store is exactly as invisible as it was before the
# check existed. Warn; never pass.
clear_stores
store alpha "$(anchor a-1 '"pr_number":"7"')"
OUT=$(BD_FAIL_STORE=beta run_check); RC=$?
eq "$RC" "1" "a store that cannot be listed is a WARNING, not a pass"
has "$OUT" "beta" "the warning names the store"
has "$OUT" "NOT checked" "the warning says the store was not checked"

# --- 14. Fail-closed: a store returns no output at all ----------------------
# `[]` is an empty store; empty output is a probe that produced nothing, and the
# two are not the same fact.
OUT=$(BD_EMPTY_STORE=beta run_check); RC=$?
eq "$RC" "1" "a store returning no output at all is a WARNING, not a pass"
has "$OUT" "returned no output" "the warning distinguishes no-output from an empty store"

# --- 15. A finding still wins over a warning --------------------------------
# A partially-readable scan that DID find a duplicate must report the duplicate,
# not downgrade it to the warning.
clear_stores
store alpha "$(anchor a-1 '"pr_number":"7"')" "$(anchor a-2 '"pr_number":"7"')"
OUT=$(BD_FAIL_STORE=beta run_check); RC=$?
eq "$RC" "2" "a duplicate found in a readable store outranks another store's warning"
has "$OUT" "beta" "the unreadable store is still reported alongside the finding"

# --- 16. Fail-closed: the store list itself is unreadable -------------------
clear_stores
OUT=$(RIGS_RC=4 run_check); RC=$?
eq "$RC" "1" "an unreadable rig list is a WARNING, not a pass"
has "$OUT" "gc rig list" "the warning names the probe that failed"
hasnt "$OUT" "OK:" "it does not report the clean verdict"

printf '{"schema_version":"1","ok":true,"rigs":[]}' > "$TMP/rigs-empty.json"
OUT=$(RIGS_JSON_OVERRIDE="$TMP/rigs-empty.json" run_check); RC=$?
eq "$RC" "1" "a rig list naming no paths is a WARNING, not a pass"

# --- 17. Fail-closed: EVERY store fails -------------------------------------
# Nothing was compared, so there is nothing to certify. The danger here is the
# clean verdict of an empty scan.
printf '{"schema_version":"1","ok":true,"rigs":[{"name":"alpha","path":"%s"}]}' "$TMP/alpha" \
    > "$TMP/rigs-one.json"
OUT=$(RIGS_JSON_OVERRIDE="$TMP/rigs-one.json" BD_FAIL_STORE=alpha run_check); RC=$?
eq "$RC" "1" "every store failing is a WARNING, not a pass"
has "$OUT" "not a clean result" "it says explicitly that this is not a clean result"
hasnt "$OUT" "OK:" "it does not report the clean verdict"

# --- 18. Control characters in a payload do not cost a store ----------------
# Bead notes carry them often enough to abort jq mid-parse, and they must not be
# able to pose as the row separators either.
clear_stores
printf '[{"id":"a-1","status":"open","metadata":{"merge_result":"pull_request","pr_number":"7","branch":"abc	d"}},{"id":"a-2","status":"open","metadata":{"merge_result":"pull_request","pr_number":"7"}}]' \
    > "$TMP/stores/alpha.json"
OUT=$(run_check); RC=$?
eq "$RC" "2" "separator bytes inside a payload neither break the scan nor forge a field"
has "$OUT" "a-1" "the finding survives a payload carrying separator bytes"
has "$OUT" "a-2" "and so does its pair"

echo
echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
