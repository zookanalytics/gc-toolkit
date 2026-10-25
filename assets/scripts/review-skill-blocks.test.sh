#!/usr/bin/env bash
# review-skill-blocks.test.sh — every shell block of each check's skill runs on
# the values a review is told and nothing else, iterating the pack's index.
#
# A skill has no template pass and no shell variable reaches it from a formula
# block, so a block names each value as <key>, which the agent fills in from the
# step text. Here each ```bash block of skills/review-<check>/SKILL.md is filled
# in from a fixture record and run in a fresh shell under `set -u`, in bash and
# in zsh: <worktree> is a checkout of the fixture's commit in a scratch rig
# repository, and `gc <binding> scripts-dir` answers a directory holding the
# pack's scripts. What reaches past the scratch repository is stubbed: gc's
# store, gh, gctk and bring-current-audit.sh's read of the store. Every
# placeholder a block uses is a key of the record, <worktree> or <binding>.
#
# Beyond running, three blocks are held to what they do:
#   review-test-evidence  reads gctk rig's record at the reviewed commit, in the
#                         worktree: a pass of the full suite or the affected
#                         subset is evidence and runs no suite, a fail the
#                         anchor's pre-existing mark holds at that commit is
#                         not run again, any other fail is run again with
#                         --force, no record, a pass that ran nothing or a
#                         machine failure runs the suites through the gate, and
#                         no binary is named and runs them plain.
#   triage-index-read     lists the pack's checks with the rig's own laid over
#                         them, from a checkout that holds no pack; a commit
#                         with no index lists the pack's alone; a commit the
#                         checkout cannot read, an empty commit and a scripts
#                         dir gc cannot print fail loudly.
#   triage-round-read     reads the round of the anchor the record names.
#   triage-index-gap      files the observation with that anchor in its title,
#                         provenance and quote.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-review-skill-blocks-test.XXXXXX")" || exit 1
TMP="$(cd "$TMP" && pwd -P)"
trap 'git -C "$TMP/rig" worktree remove --force "$TMP/wt" >/dev/null 2>&1; rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "missing '$2' in: $1" ;; esac; }

command -v jq  >/dev/null 2>&1 || { echo "jq is required"  >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "git is required" >&2; exit 1; }
SHELLS="bash"; command -v zsh >/dev/null 2>&1 && SHELLS="bash zsh"

# The blocks run as an agent's shell runs them: nothing from the city reaches
# them, and git reads no user or system config.
unset GC_PACK_DIR GC_RIG_ROOT GC_RIG GC_CITY GC_CITY_PATH GC_REVIEW_CHECKS_INDEX GCTK_BIN 2>/dev/null || true
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR 2>/dev/null || true
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# --- the scratch rig ------------------------------------------------------------
# main holds the base; polecat/x adds a source file, a visual beside it and an
# index carrying a pack check restated and a check of the rig's own. origin
# holds both, so origin/main is the review's base. Its checkout holds no
# assets/scripts: the pack's scripts are reached through scripts-dir alone.
RIG="$TMP/rig"; mkdir -p "$RIG"
git -C "$RIG" init -q -b main
printf 'base\n' > "$RIG/README"; git -C "$RIG" add README; git -C "$RIG" commit -q -m base
git -C "$RIG" checkout -q -b polecat/x
mkdir -p "$RIG/web"; printf 'page\n' > "$RIG/web/page.html"; printf 'PNG\n' > "$RIG/web/page.png"
printf '[checks.correctness]\npurpose = "p"\nphase = "pre-open"\n[checks.ux]\npurpose = "p2"\nphase = "pre-open"\n' > "$RIG/review-checks.toml"
git -C "$RIG" add -A; git -C "$RIG" commit -q -m "the change"
OID=$(git -C "$RIG" rev-parse HEAD)
git -C "$RIG" rm -q review-checks.toml; git -C "$RIG" commit -q -m "no index"
NO_INDEX=$(git -C "$RIG" rev-parse HEAD)
git -C "$RIG" checkout -q main
git init -q --bare "$TMP/origin.git"
git -C "$RIG" push -q "$TMP/origin.git" main polecat/x
git -C "$RIG" remote add origin "$TMP/origin.git"; git -C "$RIG" fetch -q origin
git -C "$RIG" worktree add -q --detach "$TMP/wt" "$OID"
WT="$TMP/wt"

# --- the stubs ------------------------------------------------------------------
# scripts-dir answers a pack laid out as the installed one is, its scripts and
# its index linked from this checkout, with bring-current-audit.sh standing in
# to log how it was called. gc answers `kit scripts-dir`, the anchor's
# `bd show`, and `bd create` with an id.
SCRIPTS="$TMP/pack/assets/scripts"; mkdir -p "$SCRIPTS"
for s in "$ROOT"/assets/scripts/*; do ln -s "$s" "$SCRIPTS/$(basename "$s")"; done
ln -s "$ROOT/review-checks.toml" "$TMP/pack/review-checks.toml"
rm -f "$SCRIPTS/bring-current-audit.sh"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$AUDIT_LOG"\n' > "$SCRIPTS/bring-current-audit.sh"
chmod +x "$SCRIPTS/bring-current-audit.sh"
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/gc" <<'GC'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
case "$1 ${2:-}" in
  "kit scripts-dir") [ -n "${STUB_SCRIPTS:-}" ] || { echo "gc: unknown command" >&2; exit 1; }
                     printf '%s\n' "$STUB_SCRIPTS" ;;
  "bd show") [ "${STUB_BD_FAIL:-0}" = 1 ] && exit 1; printf '%s\n' "${STUB_ANCHOR_JSON:-[{\"id\":\"tk-anchor1\",\"metadata\":{}}]}" ;;
  "bd create") shift 2
               for a in "$@"; do printf '%s\n' "$a"; done > "$STUB_CREATE"
               printf '{"id":"tk-obs1"}\n' ;;
  *) exit 1 ;;
esac
GC
# A stub gctk answers `rig test --check` with STUB_REC and STUB_RC, logging its
# call and the directory it ran in.
cat > "$TMP/gctk" <<'GCTK'
#!/usr/bin/env bash
printf '%s|%s\n' "$*" "$(pwd -P)" >> "$STUB_LOG"
[ -n "${STUB_REC:-}" ] && printf '%s\n' "$STUB_REC"
exit "${STUB_RC:-3}"
GCTK
printf '#!/usr/bin/env bash\nprintf "gh %%s\\n" "$*" >> "$STUB_LOG"\nexit 1\n' > "$BIN/gh"
chmod +x "$BIN/gc" "$BIN/gh" "$TMP/gctk"
export STUB_LOG="$TMP/stub.log" STUB_CREATE="$TMP/create.args" AUDIT_LOG="$TMP/audit.log"

# The values a review is told, and <worktree> and <binding>, as the agent fills
# them in from the step text.
ALLOWED="review_bead check anchor_bead review_branch review_base reviewed_oid review_pr_url review_pr_number review_context worktree binding"
fill() { # <check> <oid> : the block on stdin, its placeholders filled in
  sed -e 's|<review_bead>|tk-review1|g' -e "s|<check>|$1|g" -e 's|<anchor_bead>|tk-anchor1|g' \
      -e 's|<review_branch>|polecat/x|g' -e 's|<review_base>|main|g' -e "s|<reviewed_oid>|$2|g" \
      -e 's|<review_pr_url>||g' -e 's|<review_pr_number>||g' -e 's|<review_context>|a lane short of green|g' \
      -e "s|<worktree>|$WT|g" -e 's|<binding>|kit|g'
}
# blocks <skill> <dir> : each ```bash block of the skill, one file per block, named
# by its marker when it has one and by its position otherwise.
blocks() {
  awk -v dir="$2" '
    /^ *```bash *$/ { n++; f = dir "/" n ".sh"; inb = 1; next }
    inb && /^ *``` *$/ { inb = 0; close(f); next }
    inb { line = $0; sub(/^  /, "", line); print line > f }' "$1"
}
# run <shell> <file> [env...] : the block's stdout in OUT, stderr in ERR, status in RC, from <worktree>.
run() {
  local sh="$1" f="$2"; shift 2
  : > "$STUB_LOG"; RC=0
  OUT=$(cd "$WT" && env PATH="$BIN:$PATH" STUB_SCRIPTS="$SCRIPTS" "$@" "$sh" -u "$f" 2>"$TMP/err") || RC=$?
  ERR=$(cat "$TMP/err")
}

echo "# every block of every check's skill runs on the record's values alone"
NAMES=$("$ROOT/assets/scripts/review-checks.sh" --file "$ROOT/review-checks.toml" 2>/dev/null | cut -f1)
[ -n "$NAMES" ] && ok "the pack's index declares checks" || bad "the pack's index declares checks" "none read"
TOTAL=0
while IFS= read -r c; do
  [ -n "$c" ] || continue
  d="$TMP/blocks/$c"; mkdir -p "$d"
  blocks "$ROOT/skills/review-$c/SKILL.md" "$d"
  for b in "$d"/*.sh; do
    [ -e "$b" ] || continue
    TOTAL=$((TOTAL + 1)); name="$c block $(basename "$b" .sh)"
    marker=$(sed -n 's/^# >>> \(.*\)$/\1/p' "$b" | head -1); [ -z "$marker" ] || name="$c $marker"
    stray=$(grep -oE '<[a-z][a-z0-9_]*>' "$b" | tr -d '<>' | sort -u | grep -vxF -f <(printf '%s\n' $ALLOWED) | paste -sd' ' -)
    eq "$stray" "" "$name: every placeholder is a value a review is told, <worktree> or <binding>"
    fill "$c" "$OID" < "$b" > "$b.filled"
    for sh in $SHELLS; do
      run "$sh" "$b.filled" GCTK_BIN="$TMP/gctk" STUB_RC=0 STUB_REC='{"scope":"full","exit_code":0,"command":"t"}'
      eq "$RC" "0" "$name ($sh): runs under set -u with nothing but the record's values"
      case "$ERR" in *"unbound variable"*|*"parameter not set"*) bad "$name ($sh): reads a variable no block set" "$ERR" ;; esac
    done
  done
done <<< "$NAMES"
[ "$TOTAL" -gt 0 ] && ok "the check skills carry shell blocks ($TOTAL)" || bad "the check skills carry shell blocks" "none found"

echo "# the test evidence block, run as written"
EVIDENCE="$TMP/blocks/correctness/evidence.sh"
awk '/^# >>> review-test-evidence$/ {f = 1} f {print} /^# <<< review-test-evidence$/ {f = 0}' "$ROOT/skills/review-correctness/SKILL.md" \
  | fill correctness "$OID" > "$EVIDENCE"
[ -s "$EVIDENCE" ] && ok "the evidence block extracts from the correctness method" || bad "the evidence block extracts from the correctness method"
OTHER=fedcba9876543210fedcba9876543210fedcba98
record() { jq -nc --arg r "$1" --arg s "$2" --arg c "$OID" '{check: "test", result: $r, scope: $s, commit: $c, exit_code: (if $r == "pass" then 0 else 1 end), command: "tools/run-tests.sh --affected origin/main"}'; }
# marked <commit> <tracker> <record> : an anchor whose pre-existing mark holds <record>.
marked() { jq -nc --arg c "$1" --arg t "$2" --argjson r "$3" '[{id: "tk-anchor1", metadata: {"rig_check_pre_existing.test": ({commit: $c, record: $r, trackers: [$t]} | tojson)}}]'; }
# evidence <shell> <rc> <record> [anchor json] : the line the block prints.
evidence() {
  run "$1" "$EVIDENCE" GCTK_BIN="${STUB_GCTK-$TMP/gctk}" STUB_RC="$2" STUB_REC="$3" STUB_ANCHOR_JSON="${4-[{\"id\":\"tk-anchor1\",\"metadata\":{}}]}"
  printf '%s\n' "$OUT"
}
word() { printf '%s\n' "$1" | sed -nE 's/^(test evidence|no test evidence|recorded fail).*/\1/p'; }
WT_REAL=$(cd "$WT" && pwd -P)
for sh in $SHELLS; do
  O=$(evidence "$sh" 0 "$(record pass full)")
  eq "$(word "$O")" "test evidence" "($sh) a full-suite pass recorded at the reviewed commit is evidence"
  has "$O" "run no suite" "($sh) …and reads run no suite"
  grep -qx -- "rig test --check|$WT_REAL" "$STUB_LOG" && ok "($sh) the record is read with --check, in the review's worktree" \
    || bad "($sh) the record is read with --check, in the review's worktree" "log: $(tr '\n' ';' < "$STUB_LOG")"
  eq "$(word "$(evidence "$sh" 0 "$(record pass affected)")")" "test evidence" "($sh) a pass of the affected subset is evidence"
  O=$(evidence "$sh" 0 "$(record pass none)")
  eq "$(word "$O")" "no test evidence" "($sh) a pass that ran nothing is no evidence"
  has "$O" "run the suites the diff touches through the gate" "($sh) …and sends the reviewer through the gate"
  O=$(evidence "$sh" 1 "$(record fail affected)" "$(marked "$OID" tk-t1 "$(record fail affected)")")
  eq "$(word "$O")" "test evidence" "($sh) a fail the anchor marks pre-existing at the reviewed commit is evidence"
  has "$O" "tracked by tk-t1; do not run them again" "($sh) …which names its tracker and is not run again"
  O=$(evidence "$sh" 1 "$(record fail full)" "$(marked "$OID" tk-t1 "$(record fail affected)")")
  eq "$(word "$O")" "recorded fail" "($sh) a mark holding the record another run replaced does not answer for the fail"
  O=$(evidence "$sh" 1 "$(record fail affected)" "$(marked "$OTHER" tk-t1 "$(record fail affected)")")
  eq "$(word "$O")" "recorded fail" "($sh) a pre-existing mark naming another commit does not answer for the reviewed one"
  has "$O" "command: tools/run-tests.sh --affected origin/main" "($sh) …and the fail names its command"
  has "$O" "--force" "($sh) …to run again with --force"
  eq "$(word "$(evidence "$sh" 1 "$(record fail full)")")" "recorded fail" "($sh) a recorded fail on an anchor that carries no mark is the commit's"
  eq "$(word "$(STUB_BD_FAIL=1 evidence "$sh" 1 "$(record fail full)" "$(marked "$OID" tk-t1 "$(record fail full)")")")" "recorded fail" \
     "($sh) a recorded fail with an unreadable anchor is the commit's"
  O=$(evidence "$sh" 3 "")
  eq "$(word "$O")" "no test evidence" "($sh) nothing recorded at the reviewed commit is no evidence"
  has "$O" "run the suites the diff touches through the gate" "($sh) …and sends the reviewer through the gate"
  eq "$(word "$(evidence "$sh" 4 "")")" "no test evidence" "($sh) a machine failure is no evidence"
  O=$(STUB_GCTK="$TMP/no-gctk" evidence "$sh" 0 "$(record pass full)")
  eq "$(word "$O")" "no test evidence" "($sh) no gctk binary is no evidence"
  has "$O" "no gctk binary at '$TMP/no-gctk'" "($sh) …which names the binary it looked for"
  has "$O" "plain, each under the keepalive" "($sh) …and runs the suites plain"
  O=$(STUB_GCTK="" evidence "$sh" 0 "$(record pass full)")
  has "$O" "no gctk binary at '/.gc/services/gctk/bin/gctk'" "($sh) with no GCTK_BIN and no city, the block names a path no city holds"
done

echo "# the triage blocks, run as written"
TB="$TMP/blocks/triage"
for m in triage-index-read triage-round-read triage-index-gap; do
  awk -v m="$m" '$0 == "# <<< " m {f = 0} f {print} $0 == "# >>> " m {f = 1}' "$ROOT/skills/review-triage/SKILL.md" > "$TB/$m.tmpl"
  [ -s "$TB/$m.tmpl" ] && ok "$m extracts from the skill" || bad "$m extracts from the skill" "no '# >>> $m' block"
done
PACK_NAMES=$("$ROOT/assets/scripts/review-checks.sh" --file "$ROOT/review-checks.toml" 2>/dev/null | cut -f1 | tr '\n' ' ')
# triage <shell> <block> <oid> [env...] : the block filled in at <oid> and run.
triage() { local sh="$1" m="$2" oid="$3"; shift 3; fill triage "$oid" < "$TB/$m.tmpl" > "$TB/$m.sh"; run "$sh" "$TB/$m.sh" "$@"; }
for sh in $SHELLS; do
  triage "$sh" triage-index-read "$OID"
  eq "$RC" "0" "($sh) the index read exits 0"
  eq "$(printf '%s\n' "$OUT" | cut -f1 | tr '\n' ' ')" "${PACK_NAMES}ux " \
     "($sh) the pack's resolver lists the pack's checks and the rig's own, from a checkout that holds no pack"
  has "$(printf '%s\n' "$OUT" | grep '^correctness')" "	p	pre-open" "($sh) …the rig's row laid over the pack's correctness"
  grep -qx 'kit scripts-dir' "$STUB_LOG" && ok "($sh) the resolver is found through gc <binding> scripts-dir" \
    || bad "($sh) the resolver is found through gc <binding> scripts-dir" "gc calls: $(tr '\n' ';' < "$STUB_LOG")"
  triage "$sh" triage-index-read "$NO_INDEX"
  eq "$RC" "0" "($sh) a commit with no index exits 0"
  eq "$(printf '%s\n' "$OUT" | cut -f1 | tr '\n' ' ')" "$PACK_NAMES" "($sh) …listing the pack's checks alone"
  for unread in 0000000000000000000000000000000000000000 ""; do
    triage "$sh" triage-index-read "$unread"
    [ "$RC" -ne 0 ] && [ -n "$ERR" ] && [ -z "$OUT" ] && ok "($sh) a commit the checkout cannot read ('$unread') fails loudly, listing no menu" \
      || bad "($sh) a commit the checkout cannot read ('$unread') fails loudly, listing no menu" "rc=$RC out='$OUT' err='$ERR'"
  done
  triage "$sh" triage-index-read "$OID" STUB_SCRIPTS=""
  [ "$RC" -ne 0 ] && [ -n "$ERR" ] && ok "($sh) a scripts dir gc cannot print fails loudly" \
    || bad "($sh) a scripts dir gc cannot print fails loudly" "rc=$RC stderr='$ERR'"
  : > "$AUDIT_LOG"
  triage "$sh" triage-round-read "$OID"
  eq "$RC" "0" "($sh) the round read exits 0"
  eq "$(tr '\n' ';' < "$AUDIT_LOG")" "render --anchor tk-anchor1 --as comment;show --anchor tk-anchor1;" \
     "($sh) the pack's bring-current-audit.sh reads the round of the anchor the record names"
  rm -f "$STUB_CREATE"
  triage "$sh" triage-index-gap "$OID"
  eq "$RC" "0" "($sh) the index-gap observation is filed"
  ARGS=$(cat "$STUB_CREATE" 2>/dev/null)
  has "$(printf '%s\n' "$ARGS" | head -1)" "(bead:tk-anchor1)" "($sh) its title names the anchor"
  META=$(printf '%s\n' "$ARGS" | awk 'p {print; exit} $0 == "--metadata" {p = 1}')
  PROV=$(printf '%s' "$META" | jq -r '.["obs.provenance"] // empty' 2>/dev/null)
  case "$PROV" in
    bead:tk-anchor1:turn:????-??-??) ok "($sh) its provenance is the anchor's turn ($PROV)" ;;
    *) bad "($sh) its provenance is the anchor's turn" "got '$PROV'" ;;
  esac
  has "$ARGS" "Triage on tk-anchor1 at $OID." "($sh) its quote names the anchor and the reviewed commit"
done

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
