#!/usr/bin/env bash
# Hermetic test for doctor/check-gate-integrity (I6+I7 surface). Stub gc/bd/git.
# Third clause covered below: charter-mandated gates — the parse fixture, the
# `dir/**` and exact-path patterns, the triage waiver that suppresses a
# finding, and every skip that must never become one.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2')" ;; *) ok "$3" ;; esac; }

mkdir -p "$TMP/bin" "$TMP/stores" "$TMP/alpha"
cat > "$TMP/rigs.json" <<EOF
{"rigs":[{"name":"alpha","path":"$TMP/alpha"}]}
EOF
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "rig list") rc="${RIGS_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"; cat "$RIGS_JSON" ;;
  *) exit 0 ;;
esac
GC
cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
db=""; prev=""
for a in "$@"; do [ "$prev" = "--db" ] && db="$a"; prev="$a"; done
name=$(basename "$(dirname "$db")")
[ "$name" = "${BD_FAIL_STORE:-}" ] && exit 3
f="$STORES/$name.json"; if [ -f "$f" ]; then cat "$f"; else printf '[]'; fi
BD
# Only `git -C <rig> diff --name-only origin/<base>...origin/<branch>` is
# reached; the canned answer is keyed on the branch side of the range.
cat > "$TMP/bin/git" <<'GIT'
#!/usr/bin/env bash
range=""
for a in "$@"; do case "$a" in *...*) range="$a" ;; esac; done
f="$DIFFS/${range##*...origin/}.txt"
[ -f "$f" ] && cat "$f"
exit 0
GIT
chmod +x "$TMP/bin/gc" "$TMP/bin/bd" "$TMP/bin/git"
mkdir -p "$TMP/diffs"
export PATH="$TMP/bin:$PATH" STORES="$TMP/stores" DIFFS="$TMP/diffs"
run_check() { RIGS_JSON="$TMP/rigs.json" GC_PACK_DIR="$TMP" bash "$CHECK" 2>&1; }
bead() { printf '{"id":"%s","status":"open","metadata":%s}' "$1" "$2"; }
store() { local IFS=,; printf '[%s]' "$*" > "$TMP/stores/alpha.json"; }
OID="0123456789abcdef0123456789abcdef01234567"

# --- 1. healthy anchors pass ---------------------------------------------------
store "$(bead g-1 "{\"merge_result\":\"pull_request\",\"check_set\":\"codex\",\"branch\":\"polecat/g-1\",\"check.codex\":\"green@$OID\"}")" \
      "$(bead g-2 '{"merge_result":"pre_open_gate","check_set":"none","branch":"polecat/g-2"}')" \
      "$(bead g-3 "{\"merge_result\":\"pull_request\",\"check_set\":\"codex\",\"branch\":\"b\",\"check.codex\":\"exception@$OID\",\"check.codex.reason\":\"prose, not a marker\",\"check.codex.attempts\":\"2@$OID\"}")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "well-formed markers, the none sentinel, and sidecar keys all pass"
has "$OUT" "OK:" "the pass message is the OK line"

# --- 2. missing / empty check_set on a gating anchor ------------------------------
store "$(bead g-4 '{"merge_result":"pull_request","branch":"b"}')" \
      "$(bead g-5 '{"merge_result":"pre_open_gate","check_set":"","branch":"b"}')"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a gating anchor with no (or empty) check_set is an ERROR"
has "$OUT" "g-4" "the absent declaration is flagged"
has "$OUT" "g-5" "the explicitly empty declaration is flagged"
has "$OUT" "ungated" "the finding says what empty means to merge.sh"

# --- 3. malformed markers ---------------------------------------------------------
store "$(bead g-6 '{"merge_result":"pull_request","check_set":"codex","branch":"b","check.codex":"green@abc123"}')" \
      "$(bead g-7 "{\"merge_result\":\"pull_request\",\"check_set\":\"codex\",\"branch\":\"b\",\"check.codex\":\"passed@$OID\"}")" \
      "$(bead g-8 '{"merge_result":"pull_request","check_set":"codex","branch":"b","check.codex":"green"}')"
OUT=$(run_check); RC=$?
eq "$RC" "2" "malformed gate markers are ERRORs"
has "$OUT" "g-6" "a short oid is flagged"
has "$OUT" "g-7" "an undeclared verb is flagged"
has "$OUT" "g-8" "a marker with no @oid at all is flagged"

# --- 4. green marker with no branch metadata ---------------------------------------
store "$(bead g-9 "{\"merge_result\":\"pull_request\",\"check_set\":\"codex\",\"check.codex\":\"green@$OID\"}")"
OUT=$(run_check); RC=$?
eq "$RC" "1" "a green marker on an anchor with no branch is a WARNING"
has "$OUT" "g-9" "the unverifiable green is named"
has "$OUT" "branch" "the warning names the missing branch metadata"

# --- 5. non-gating anchors are out of scope ------------------------------------------
store "$(bead g-10 '{"merge_result":"abandoned"}')" \
      "$(bead g-11 '{"merge_result":"blocked","check.codex":"nonsense"}')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "human-parked states carry no gate obligations"

# --- 6. fail-CLOSED --------------------------------------------------------------
OUT=$(RIGS_RC=1 run_check); RC=$?
eq "$RC" "1" "a failed \`gc rig list\` warns, never passes"
OUT=$(BD_FAIL_STORE=alpha run_check); RC=$?
eq "$RC" "1" "an unreadable store warns"
has "$OUT" "NOT checked" "the warning says the store was skipped"
printf 'not json' > "$TMP/stores/alpha.json"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an unparseable store listing warns"

# --- 7. charter-mandated gates (warn-only) -----------------------------------------
mkdir -p "$TMP/alpha/docs"
cat > "$TMP/alpha/docs/review-charter.md" <<'CHARTER'
# Fixture charter

Prose before the menu, and a table that is not the menu:

| Thing | Other |
|---|---|
| `a` | `b` |

## Gate menu

| Gate | Applies when | Method | Mandatory paths | Waivable |
|---|---|---|---|---|
| `codex` | always | `formulas/mol-review.toml` | `-` | no |
| `triage` | always | `skills/review-triage/SKILL.md` | `-` | no |
| `arch` | layer changes | `skills/arch-review/SKILL.md` | `lifecycle/**` `assets/scripts/merge.sh` | no |
| `demo` | operator-visible | `skills/demo-capture/SKILL.md` | `-` | yes |

Trailing prose, which the parse must stop before.
CHARTER

gated() { # id check_set branch [extra-metadata-json] [notes]
  printf '{"id":"%s","status":"open","notes":"%s","metadata":{"merge_result":"pull_request","check_set":"%s","branch":"%s","merged_target":"main"%s}}' \
    "$1" "${5:-}" "$2" "$3" "${4:-}"
}
printf 'lifecycle/lifecycle.toml\ndocs/skills.md\n' > "$TMP/diffs/b-arch.txt"
printf 'docs/skills.md\n'                            > "$TMP/diffs/b-plain.txt"
printf 'assets/scripts/merge.sh\n'                   > "$TMP/diffs/b-exact.txt"
printf 'assets/scripts/merge.sh.bak\n'               > "$TMP/diffs/b-near.txt"

printf '[%s]' "$(gated m-1 codex,triage b-arch)" > "$TMP/stores/alpha.json"
OUT=$(run_check); RC=$?
eq "$RC" "1" "a diff touching a charter-mandated path with the gate undeclared is a WARNING"
has "$OUT" "m-1" "the anchor is named"
has "$OUT" "arch" "…and so is the gate the charter mandates"
has "$OUT" "lifecycle/lifecycle.toml" "…and the file that fired the row"

printf '[%s]' "$(gated m-2 codex,triage,arch b-arch)" > "$TMP/stores/alpha.json"
OUT=$(run_check); RC=$?
eq "$RC" "0" "declaring the mandated gate clears the finding"

OID2="89abcdef89abcdef89abcdef89abcdef89abcdef"
printf '[%s]' "$(gated m-3 codex,triage b-arch ",\"check.triage\":\"green@$OID\"" "triage-waive: arch @$OID — deliberate")" > "$TMP/stores/alpha.json"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a triage waiver at the commit triage passed at suppresses the finding"

printf '[%s]' "$(gated m-3b codex,triage b-arch ",\"check.triage\":\"green@$OID2\"" "triage-waive: arch @$OID — deliberate")" > "$TMP/stores/alpha.json"
OUT=$(run_check); RC=$?
eq "$RC" "1" "a waiver issued against an older commit than triage last passed at no longer counts"
has "$OUT" "m-3b" "…and the anchor is named"

printf '[%s]' "$(gated m-3c codex,triage b-arch "" "triage-waive: arch @$OID — deliberate")" > "$TMP/stores/alpha.json"
OUT=$(run_check); RC=$?
eq "$RC" "1" "a waiver with no triage verdict behind it does not count"

printf '[%s]' "$(gated m-4 none b-arch)" > "$TMP/stores/alpha.json"
OUT=$(run_check); RC=$?
eq "$RC" "0" "the none opt-out covers mandatory rows too"

printf '[%s]' "$(gated m-5 codex,triage b-plain)" > "$TMP/stores/alpha.json"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a diff touching no mandated path warns about nothing"

printf '[%s]' "$(gated m-6 codex,triage b-exact)" > "$TMP/stores/alpha.json"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an exact-path row fires on its own path"
printf '[%s]' "$(gated m-7 codex,triage b-near)" > "$TMP/stores/alpha.json"
OUT=$(run_check); RC=$?
eq "$RC" "0" "…and not on a path that merely starts with it"

printf '[%s]' "$(gated m-8 codex,triage b-unknown)" > "$TMP/stores/alpha.json"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an unreadable branch diff is a skip, never a finding"
has "$OUT" "not checked" "…and the skip is reported"

mv "$TMP/alpha/docs/review-charter.md" "$TMP/alpha/docs/review-charter.md.off"
printf '[%s]' "$(gated m-9 codex,triage b-arch)" > "$TMP/stores/alpha.json"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a rig with no charter carries no mandatory-gate obligation"
mv "$TMP/alpha/docs/review-charter.md.off" "$TMP/alpha/docs/review-charter.md"

echo "# the parser reads the menu, not the decorative table beside it"
MENU=$("$HERE/../../assets/scripts/review-charter.sh" --file "$TMP/alpha/docs/review-charter.md")
eq "$(printf '%s\n' "$MENU" | wc -l | tr -d ' ')" "4" "exactly the four menu rows are parsed"
eq "$(printf '%s\n' "$MENU" | awk -F'\t' '$1 == "demo" { print $4 }')" "yes" "the waivable column round-trips"
eq "$(printf '%s\n' "$MENU" | awk -F'\t' '$1 == "codex" { print $3 }')" "-" "a row with no mandatory path reads as none"

echo
echo "check-gate-integrity: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
