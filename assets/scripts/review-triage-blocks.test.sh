#!/usr/bin/env bash
# review-triage-blocks.test.sh — the triage skill's shell blocks, run as written
# in a rig whose checkout holds no pack.
#
# A triage review runs in any rig's checkout, and only gc-toolkit's carries the
# pack's scripts, so a block reaches the pack's own copy through
# `gc <binding> scripts-dir`. The formula's pin block sets $M, $REVIEW_BEAD and
# $REVIEWED_OID and no $ANCHOR, so a block that names the anchor reads it from
# $M. Each block is taken from skills/review-triage/SKILL.md between its
# markers, its <binding> filled in as an agent fills it in, and run under bash
# and zsh:
#   triage-index-read  in a scratch rig repo whose reviewed commit carries an
#                      index, with GC_PACK_DIR unset and no pack under
#                      GC_RIG_ROOT: the pack's parser lists the rig's checks. A
#                      commit with no index lists nothing and runs no parser,
#                      and a scripts dir gc cannot print fails loudly instead.
#   triage-round-read  reads the bring-current round of the anchor $M names.
#   triage-index-gap   files the observation with that anchor in its title,
#                      provenance and quote.
# Hermetic: a stub gc answers `kit scripts-dir` and `bd create`. No city, store
# or network.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SKILL="$ROOT/skills/review-triage/SKILL.md"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-review-triage-blocks-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "missing '$2' in: $1" ;; esac; }

[ -r "$SKILL" ] || { echo "skill not found: $SKILL" >&2; exit 1; }
command -v jq  >/dev/null 2>&1 || { echo "jq is required"  >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "git is required" >&2; exit 1; }

# The blocks run as an agent's shell runs them: nothing from the city reaches
# them, and git reads no user or system config.
unset GC_PACK_DIR GC_RIG_ROOT GC_RIG GC_CITY GC_CITY_PATH GC_REVIEW_CHECKS_INDEX 2>/dev/null || true
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR 2>/dev/null || true
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# block <name> : the skill's <name> block between its markers, with <binding>
# filled in as kit, a binding a city may import the pack under.
block() {
  awk -v m="$1" '$0 == "# <<< " m {f = 0} f {print} $0 == "# >>> " m {f = 1}' "$SKILL" | sed 's/<binding>/kit/g'
}
for m in triage-index-read triage-round-read triage-index-gap; do
  block "$m" > "$TMP/$m.sh"
  [ -s "$TMP/$m.sh" ] && ok "$m extracts from the skill" || bad "$m extracts from the skill" "no '# >>> $m' block in $SKILL"
done

# A stub gc: `kit scripts-dir` prints $STUB_SCRIPTS, or fails when it is empty;
# `bd create` records its arguments and answers an id. Every call is logged.
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/gc" <<'GC'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
case "$1 ${2:-}" in
  "kit scripts-dir") [ -n "${STUB_SCRIPTS:-}" ] || { echo "gc: unknown command" >&2; exit 1; }
                     printf '%s\n' "$STUB_SCRIPTS" ;;
  "bd create") shift 2
               for a in "$@"; do printf '%s\n' "$a"; done > "$STUB_CREATE"
               printf '{"id":"tk-obs1"}\n' ;;
  *) exit 1 ;;
esac
GC
chmod +x "$BIN/gc"
export STUB_LOG="$TMP/gc.log" STUB_CREATE="$TMP/create.args"

# A rig that is not the pack's: its commit carries an index declaring a check
# no pack declares, and its checkout holds no assets/scripts.
RIG="$TMP/rig"; mkdir -p "$RIG"
git -C "$RIG" init -q
printf '[checks.correctness]\nmethod = "m"\npurpose = "p"\nphase = "pre-open"\n[checks.ux]\nmethod = "m2"\npurpose = "p2"\nphase = "pre-open"\n' > "$RIG/review-checks.toml"
git -C "$RIG" add review-checks.toml
git -C "$RIG" commit -q -m index
WITH_INDEX=$(git -C "$RIG" rev-parse HEAD)
git -C "$RIG" rm -q review-checks.toml
git -C "$RIG" commit -q -m "no index"
NO_INDEX=$(git -C "$RIG" rev-parse HEAD)

# A scripts dir holding a bring-current-audit.sh that records how it was called.
FAKE_SCRIPTS="$TMP/scripts"; mkdir -p "$FAKE_SCRIPTS"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$AUDIT_LOG"\n' > "$FAKE_SCRIPTS/bring-current-audit.sh"
chmod +x "$FAKE_SCRIPTS/bring-current-audit.sh"
export AUDIT_LOG="$TMP/audit.log"

M_JSON='{"task_kind":"review","check_name":"triage","anchor_bead":"tk-anchor1","review_branch":"polecat/x","review_base":"main"}'

# run <shell> <block> <scripts dir> <reviewed oid> : the block's stdout in OUT,
# its stderr in ERR and its status in RC, run in the rig's checkout.
run() {
  : > "$STUB_LOG"
  RC=0
  OUT=$(cd "$RIG" && PATH="$BIN:$PATH" STUB_SCRIPTS="$3" GC_RIG_ROOT="$RIG" GC_RIG=rig-x \
          M="$M_JSON" REVIEW_BEAD=tk-review1 REVIEWED_OID="$4" "$1" "$TMP/$2.sh" 2>"$TMP/err") || RC=$?
  ERR=$(cat "$TMP/err")
}

SHELLS="bash"; command -v zsh >/dev/null 2>&1 && SHELLS="bash zsh"
for sh in $SHELLS; do
  echo "# $sh: the index read"
  run "$sh" triage-index-read "$ROOT/assets/scripts" "$WITH_INDEX"
  eq "$RC" "0" "($sh) the read exits 0"
  eq "$(printf '%s\n' "$OUT" | cut -f1 | tr '\n' ' ')" "correctness ux " \
     "($sh) the pack's parser lists the rig's own checks, from a checkout that holds no pack"
  grep -qx 'kit scripts-dir' "$STUB_LOG" && ok "($sh) the parser is found through gc <binding> scripts-dir" \
    || bad "($sh) the parser is found through gc <binding> scripts-dir" "gc calls: $(tr '\n' ';' < "$STUB_LOG")"

  run "$sh" triage-index-read "$ROOT/assets/scripts" "$NO_INDEX"
  eq "$OUT" "" "($sh) a commit with no index lists no checks"
  eq "$(cat "$STUB_LOG")" "" "($sh) …and runs no parser"

  run "$sh" triage-index-read "" "$WITH_INDEX"
  [ "$RC" -ne 0 ] && [ -n "$ERR" ] && ok "($sh) a scripts dir gc cannot print fails loudly, unlike a missing index" \
    || bad "($sh) a scripts dir gc cannot print fails loudly, unlike a missing index" "rc=$RC stderr='$ERR'"

  echo "# $sh: the bring-current round read"
  : > "$AUDIT_LOG"
  run "$sh" triage-round-read "$FAKE_SCRIPTS" "$WITH_INDEX"
  eq "$RC" "0" "($sh) the round read exits 0"
  eq "$(tr '\n' ';' < "$AUDIT_LOG")" "render --anchor tk-anchor1 --as comment;show --anchor tk-anchor1;" \
     "($sh) the pack's bring-current-audit.sh reads the round of the anchor the review bead names"

  echo "# $sh: the index-gap observation"
  rm -f "$STUB_CREATE"
  run "$sh" triage-index-gap "$FAKE_SCRIPTS" "$WITH_INDEX"
  eq "$RC" "0" "($sh) the observation is filed"
  ARGS=$(cat "$STUB_CREATE" 2>/dev/null)
  has "$(printf '%s\n' "$ARGS" | head -1)" "(bead:tk-anchor1)" "($sh) its title names the anchor"
  META=$(printf '%s\n' "$ARGS" | awk 'p {print; exit} $0 == "--metadata" {p = 1}')
  PROV=$(printf '%s' "$META" | jq -r '.["obs.provenance"] // empty' 2>/dev/null)
  case "$PROV" in
    bead:tk-anchor1:turn:????-??-??) ok "($sh) its provenance is the anchor's turn ($PROV)" ;;
    *) bad "($sh) its provenance is the anchor's turn" "got '$PROV'" ;;
  esac
  has "$ARGS" "Triage on tk-anchor1 at $WITH_INDEX." "($sh) its quote names the anchor and the reviewed commit"
done

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
