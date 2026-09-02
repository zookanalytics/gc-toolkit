#!/usr/bin/env bash
# distiller-pending-scratch.test.sh — mol-feedback-distiller's load-and-gate
# block owns every temp it allocates, the pending set included.
#
# The pending set outlives the block on purpose: the later blocks read it, and
# each block is its own shell, so the block cannot simply trap it. That makes
# the trap conditional, and a conditional cleanup has two failure directions —
# it can leak on an abort, or it can delete a set the later blocks still need.
# Both are asserted here, because either one alone is satisfiable by a wrong
# fix.
#
# The block is extracted verbatim between the distiller-pending-scratch
# markers and EXECUTED against stubs, so what passes is the shipped formula
# text and not a paraphrase of it.
#
# Hermetic: no gc, no city. TMPDIR is a private sandbox, so every allocation
# the block makes is countable, and the block runs in an empty cwd that must
# stay empty.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/../.."
TOML="$REPO/formulas/mol-feedback-distiller.toml"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/gctk-distiller-pending-test.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT
trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP

echo "── the block extracts ──"
# The formula body is a TOML basic string, so a backslash reaches the file
# doubled. `\\` is the only escape the block carries; the census below fails
# if another form appears, which would make this one-rule unescape wrong.
RAW_BLOCK="$(awk '
  /# >>> distiller-pending-scratch/ { inb = 1; next }
  /# <<< distiller-pending-scratch/ { inb = 0; next }
  inb' "$TOML")"

if [ -n "$RAW_BLOCK" ]; then
  ok "block extracted between distiller-pending-scratch markers"
else
  bad "block extracted between distiller-pending-scratch markers" "no marked block in $TOML"
  printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"; exit 1
fi

ODD="$(printf '%s\n' "$RAW_BLOCK" | grep -c '\(^\|[^\\]\)\\\([^\\]\|$\)' || true)"
eq "$ODD" "0" "every backslash in the block is a TOML-doubled pair"

BLOCK="$(printf '%s\n' "$RAW_BLOCK" | sed 's/\\\\/\\/g; s/{{rig_list}}/r-alpha r-beta/g')"

printf '%s\n' "$BLOCK" > "$SANDBOX/block.sh"
if bash -n "$SANDBOX/block.sh" 2>"$SANDBOX/syntax.err"; then
  ok "extracted block is syntactically valid bash"
else
  bad "extracted block is syntactically valid bash" "$(cat "$SANDBOX/syntax.err")"
fi

# ── stubs ─────────────────────────────────────────────────────────────────
mkdir -p "$SANDBOX/bin" "$SANDBOX/stores" "$SANDBOX/pack/assets/scripts"

cat > "$SANDBOX/bin/gc" <<'STUB'
#!/usr/bin/env bash
# Only `gc bd --rig <R> list ...` is reachable from the block: the poured rig
# list means `gc rig list` is never called, and a poured name carries no path.
rig=""; prev=""
for a in "$@"; do
  [ "$prev" = "--rig" ] && rig="$a"
  prev="$a"
done
f="$STUB_STORE_DIR/$rig.json"
if [ -f "$f" ]; then cat "$f"; else printf 'no such store: %s\n' "$rig" >&2; exit 1; fi
STUB
chmod +x "$SANDBOX/bin/gc"

cat > "$SANDBOX/pack/assets/scripts/step-close.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_CLOSE_LOG"
STUB
chmod +x "$SANDBOX/pack/assets/scripts/step-close.sh"

# write_store <path> <bead-id> <category> — one pending observation.
write_store() {
  jq -n --arg id "$2" --arg cat "$3" \
    '[{id: $id, status: "closed", created_at: "2026-08-01T00:00:00Z",
       metadata: {task_kind: "observation", "obs.category": $cat}}]' > "$1"
}

# run_block <label> — execute the extracted block with the fixtures now in
# place, in a fresh TMPDIR and a fresh empty cwd.
run_block() {
  label="$1"
  RUN_TMP="$SANDBOX/tmp-$label"; RUN_CWD="$SANDBOX/cwd-$label"
  mkdir -p "$RUN_TMP" "$RUN_CWD"
  : > "$SANDBOX/close-$label.log"
  {
    printf '%s\n' 'SC="$STUB_SC"'
    printf '%s\n' "$BLOCK"
  } > "$SANDBOX/run-$label.sh"
  (
    cd "$RUN_CWD" || exit 1
    TMPDIR="$RUN_TMP" \
    PATH="$SANDBOX/bin:$PATH" \
    STUB_STORE_DIR="$SANDBOX/stores" \
    STUB_SC="$SANDBOX/pack/assets/scripts/step-close.sh" \
    STUB_CLOSE_LOG="$SANDBOX/close-$label.log" \
    GC_PACK_DIR="$SANDBOX/pack" GC_RIG_ROOT="" GC_CITY_PATH="" \
      bash "$SANDBOX/run-$label.sh"
  ) > "$SANDBOX/out-$label.txt" 2>&1
}

# leftovers <label> — every temp the block allocated that still exists.
leftovers() { find "$SANDBOX/tmp-$1" -maxdepth 1 -name 'gctk-feedback-distiller.*' | LC_ALL=C sort; }
count_leftovers() { leftovers "$1" | grep -c . || true; }

echo "── an unreadable store aborts the block and leaves nothing behind ──"
write_store "$SANDBOX/stores/r-alpha.json" tk-aaaaaa first-cat
printf '%s\n' '{"error":"store unreadable"}' > "$SANDBOX/stores/r-beta.json"
run_block abort

has_abort_msg="$(grep -c 'FAIL-SAFE: observation listing for store' "$SANDBOX/out-abort.txt" || true)"
eq "$has_abort_msg" "1" "abort path announced the fail-safe"
eq "$(grep -c -- '--outcome fail' "$SANDBOX/close-abort.log" || true)" "1" \
  "abort path closed the step --outcome fail"
eq "$(count_leftovers abort)" "0" \
  "abort path left no gctk-feedback-distiller.* temp behind"
eq "$(find "$SANDBOX/cwd-abort" -mindepth 1 | grep -c . || true)" "0" \
  "abort path wrote nothing into the cwd"

echo "── a readable set reaches the handoff and survives it ──"
write_store "$SANDBOX/stores/r-beta.json" tk-bbbbbb second-cat
run_block keep

eq "$(count_leftovers keep)" "1" \
  "handoff left exactly the pending set behind"
KEPT="$(leftovers keep)"
case "$KEPT" in
  *.next) bad "the surviving temp is the pending set, not its .next scratch" "kept: $KEPT" ;;
  "")     bad "the surviving temp is the pending set, not its .next scratch" "nothing survived" ;;
  *)      ok "the surviving temp is the pending set, not its .next scratch" ;;
esac

if [ -n "$KEPT" ] && [ -f "$KEPT" ]; then
  eq "$(jq -r 'length' "$KEPT" 2>/dev/null || echo ERR)" "2" \
    "the pending set carries one observation from each store"
  eq "$(jq -r '[.[].obs_rig] | sort | join(",")' "$KEPT" 2>/dev/null || echo ERR)" "r-alpha,r-beta" \
    "each observation is tagged with the store it came from"
fi
eq "$(grep -c -- '--outcome fail' "$SANDBOX/close-keep.log" || true)" "0" \
  "handoff path closed no step --outcome fail"
eq "$(find "$SANDBOX/cwd-keep" -mindepth 1 | grep -c . || true)" "0" \
  "handoff path wrote nothing into the cwd"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
