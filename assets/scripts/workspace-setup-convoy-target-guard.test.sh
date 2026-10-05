#!/usr/bin/env bash
# Hermetic test for mol-polecat-work's workspace-setup convoy target guard.
#
# `gc sling` resolves base_branch from the bead's own metadata.target, else the
# first convoy target on the ONE parent chain bd reports, else the rig default
# branch. A child filed under an epic and also linked to an owned convoy can
# report the epic, so the lookup never reaches the convoy: the child is poured
# from the default branch and would land there, and the integration branch never
# receives it. The guard reads every parent-child edge on the work bead and
# holds the molecule before any worktree is poured.
#
# What it holds:
#   1. THE CASE — a child of an epic AND an open convoy targeting a branch other
#      than base_branch, with no target or branch of its own: notes, escalates,
#      holds workspace-setup, drain-acks, exits 1. The visit names the stake
#      and the release.
#   2. DISCRIMINATION — passes (no writes) when the bead names its own target or
#      a branch to resume, when the convoy targets base_branch itself, when the
#      convoy has no target or is closed, and when only a non-convoy parent
#      carries a target.
#   3. FAIL CLOSED — no release path recorded means no hold and no drain; a hold
#      that did not land means no drain.
#   4. UNREADABLE BEAD — passes with a warning and writes nothing: the hold
#      would write to the store the read just failed on.
#   5. ORDER — the guard runs before the worktree is poured from base_branch.
#
# EXECUTES the real snippet extracted verbatim from the formula against fake
# `gc` and stub scripts, so the test cannot drift from the shipped instruction.
# No live city, Dolt, network, or worktrees.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-polecat-work.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-workspace-setup-convoy-target-guard-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3" "got '$1' want '$2'"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "'$2' not in '$1'" ;; esac; }
no()  { case "$1" in *"$2"*) bad "$3" "'$2' unexpectedly in '$1'" ;; *) ok "$3" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }
[ -f "$TOML" ] || { echo "formula not found: $TOML" >&2; exit 1; }

# --- Extract the REAL snippet from the formula. -------------------------------
# The flag-flip pulls the lines between the markers (exclusive). Remove or
# rename the markers and extraction yields nothing, so the checks below fail
# loudly.
extract() {
  awk -v m="$1" '
    $0 ~ ("# >>> " m "$") {f=1; next}
    $0 ~ ("# <<< " m "$") {f=0}
    f' "$TOML"
}

GUARD="$(extract workspace-setup-convoy-target-guard)"

[ -n "$GUARD" ] \
  && ok "guard extracted between workspace-setup-convoy-target-guard markers" \
  || bad "guard extraction EMPTY — markers missing from $TOML"

# Two regions sharing one marker name would concatenate into one extraction and
# double every assertion below; pin the opener to a single occurrence.
eq "$(grep -c '^# >>> workspace-setup-convoy-target-guard$' "$TOML")" "1" \
   "exactly one workspace-setup-convoy-target-guard region"

# TOML `"""` strings eat a trailing backslash (line-ending escape), silently
# joining lines. The snippet is written backslash-free; assert it, because
# reintroducing a continuation is an easy and invisible edit.
case "$GUARD" in
  *\\*) bad "snippet contains a backslash — TOML line-ending escapes will mangle it" ;;
  *)    ok  "snippet is backslash-free (safe inside a TOML triple-quoted string)" ;;
esac

printf '%s\n' "$GUARD" > "$TMP/guard.raw"
bash -n "$TMP/guard.raw" \
  && ok "extracted guard is syntactically valid bash" \
  || bad "extracted guard failed bash -n"

# --- 5. Order: the guard holds before the worktree is poured. ------------------
# Holding after `git worktree add ... origin/{{base_branch}}` would be too late
# to be the "before pouring" stop, so the guard's region must open first.
GUARD_LINE=$(grep -n '^# >>> workspace-setup-convoy-target-guard$' "$TOML" | cut -d: -f1)
ADD_LINE=$(grep -n '^# >>> workspace-setup-worktree-add$' "$TOML" | cut -d: -f1)
if [ -n "$GUARD_LINE" ] && [ -n "$ADD_LINE" ] && [ "$GUARD_LINE" -lt "$ADD_LINE" ]; then
  ok "guard region opens before the worktree-add region"
else
  bad "guard region must open before the worktree-add region" "guard=${GUARD_LINE:-none} add=${ADD_LINE:-none}"
fi

# --- Fakes. -------------------------------------------------------------------
# gc : `bd show` answers $FAKE_SHOW (exit $FAKE_SHOW_RC); `bd update` and
#      `runtime drain-ack` record into the ordered verb log, and the update argv
#      is captured where the note assertions can read it.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "bd show")           printf '%s' "${FAKE_SHOW:-}"; exit "${FAKE_SHOW_RC:-0}" ;;
  "bd update")         shift 2; printf 'UPDATE\n' >> "$FAKE_LOG"; printf '%s\n' "$*" >> "${FAKE_UPDATE:-/dev/null}"; exit 0 ;;
  "runtime drain-ack") printf 'DRAIN\n' >> "$FAKE_LOG"; exit 0 ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH"

# molecule-hold.sh and escalate.sh resolved out of $GC_PACK_DIR exactly as the
# arm resolves them. Each records its verb into the ordered trace and its argv
# where the reason assertions can read it, and returns a code the assertions
# control.
mkdir -p "$TMP/pack/assets/scripts"
cat > "$TMP/pack/assets/scripts/molecule-hold.sh" <<'HOLD'
#!/usr/bin/env bash
printf 'HOLD\n' >> "$FAKE_LOG"
printf '%s\n' "$*" >> "${FAKE_HOLD:-/dev/null}"
exit "${FAKE_HOLD_RC:-0}"
HOLD
cat > "$TMP/pack/assets/scripts/escalate.sh" <<'ESC'
#!/usr/bin/env bash
printf 'ESCALATE\n' >> "$FAKE_LOG"
printf '%s\n' "$*" >> "${FAKE_ESC:-/dev/null}"
exit "${FAKE_ESC_RC:-0}"
ESC
chmod +x "$TMP/pack/assets/scripts/molecule-hold.sh" "$TMP/pack/assets/scripts/escalate.sh"
export GC_PACK_DIR="$TMP/pack" GC_RIG_ROOT="" GC_CITY_PATH=""

# run <base_branch> <work-bead-json> -> prints "<rc>|<ordered verb log>"
#   `{{base_branch}}` is a formula placeholder, substituted here the way the
#   pour renders it. FAKE_*_RC control each stub's exit; FAKE_UPDATE/HOLD/ESC
#   capture argv and $TMP/err the block's stderr.
run() {
  : > "$TMP/log"; : > "$TMP/update"; : > "$TMP/hold"; : > "$TMP/esc"
  sed "s|{{base_branch}}|$1|g" "$TMP/guard.raw" > "$TMP/guard.sh"
  local rc=0
  WORK_BEAD_ID=tk-work \
  CLAIMED_STEP_BEAD_ID=st-setup \
  FAKE_SHOW="$2" FAKE_SHOW_RC="${FAKE_SHOW_RC:-0}" \
  FAKE_LOG="$TMP/log" FAKE_UPDATE="$TMP/update" FAKE_HOLD="$TMP/hold" FAKE_ESC="$TMP/esc" \
  FAKE_HOLD_RC="${FAKE_HOLD_RC:-0}" FAKE_ESC_RC="${FAKE_ESC_RC:-0}" \
    bash "$TMP/guard.sh" > "$TMP/out" 2> "$TMP/err" || rc=$?
  printf '%s|%s' "$rc" "$(tr '\n' ';' < "$TMP/log")"
}

# bead <own-metadata-json> <dependencies-json> -> one `gc bd show --json` row.
# Dependency rows carry the fields bd show renders for an edge on the child: the
# parent's id, status and issue_type, the edge's dependency_type, and the
# parent's metadata.
bead() {
  printf '[{"id":"tk-work","status":"in_progress","metadata":%s,"dependencies":%s}]' "$1" "$2"
}
EPIC='{"id":"tk-epic","status":"open","issue_type":"epic","dependency_type":"parent-child","metadata":{}}'
CONVOY_INT='{"id":"tk-cnv","status":"open","issue_type":"convoy","dependency_type":"parent-child","metadata":{"target":"integration/tk-cnv"}}'
ROUTED='{"gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat"}'

# --- 1. The case the guard exists for. ----------------------------------------
# The evidence shape: the child sits under its epic AND under the convoy, bd
# reports the epic, and sling poured the molecule from main.
TWO_PARENTS="$(bead "$ROUTED" "[$EPIC,$CONVOY_INT]")"
eq "$(run main "$TWO_PARENTS")" \
   "1|UPDATE;ESCALATE;HOLD;DRAIN;" \
   "epic + integration convoy, no own target: notes, escalates, holds, drain-acks, exits 1"

run main "$TWO_PARENTS" >/dev/null
has "$(cat "$TMP/esc")" "--key polecat-convoy-target-mismatch" "escalates under its own situation key"
has "$(cat "$TMP/esc")" "--subject tk-work" "the visit's subject is the work bead"
has "$(cat "$TMP/esc")" "integration/tk-cnv (convoy tk-cnv)" "the visit names the convoy and its branch"
has "$(cat "$TMP/esc")" "--message This work would branch from main and land there" "the visit opens with the stake, not an identifier"
has "$(cat "$TMP/esc")" "--set-metadata target=" "the visit names the target stamp that releases it"
has "$(cat "$TMP/esc")" "gc workflow delete-source tk-work --apply" "the visit names the retire step a re-sling needs"
has "$(cat "$TMP/esc")" "gc sling gc-toolkit/gc-toolkit.polecat tk-work" "the visit names the re-sling to the pour's pool"
has "$(cat "$TMP/hold")" "--step mol-polecat-work.workspace-setup" "holds THIS step"
has "$(cat "$TMP/hold")" "--bead st-setup" "passes the claimed step bead as the hold's hint"
has "$(cat "$TMP/hold")" "integration/tk-cnv" "the hold reason names the convoy branch"
has "$(cat "$TMP/update")" "--append-notes" "records the refusal on the work bead"
no  "$(cat "$TMP/update")" "--notes " "never REPLACES the work bead's notes"

# Only the convoy edge decides; the order the edges render in does not.
eq "$(run main "$(bead "$ROUTED" "[$CONVOY_INT,$EPIC]")")" \
   "1|UPDATE;ESCALATE;HOLD;DRAIN;" \
   "convoy edge listed first: holds the same way"

# Two convoys with different branches: the visit names both, so the reader
# picks the owner.
CONVOY_B='{"id":"tk-cnb","status":"open","issue_type":"convoy","dependency_type":"parent-child","metadata":{"target":"integration/tk-cnb"}}'
run main "$(bead "$ROUTED" "[$CONVOY_INT,$CONVOY_B]")" >/dev/null
has "$(cat "$TMP/esc")" "integration/tk-cnv (convoy tk-cnv)" "two convoys: names the first"
has "$(cat "$TMP/esc")" "integration/tk-cnb (convoy tk-cnb)" "two convoys: names the second"

# No route stamp to read: the re-sling still renders, with a placeholder pool.
run main "$(bead '{}' "[$EPIC,$CONVOY_INT]")" >/dev/null
has "$(cat "$TMP/esc")" "gc sling <pool> tk-work" "no route stamp: the re-sling names a placeholder pool"

# --- 2. Discrimination: no writes unless the base really is wrong. -------------

eq "$(run main "$(bead "$ROUTED" '[]')")" \
   "0|" \
   "no parents at all: passes"

eq "$(run main "$(bead "$ROUTED" "[$EPIC]")")" \
   "0|" \
   "epic parent only: passes"

eq "$(run main "$(bead '{"target":"integration/tk-cnv"}' "[$EPIC,$CONVOY_INT]")")" \
   "0|" \
   "bead names its own target: passes (sling took it before any parent)"

eq "$(run main "$(bead '{"branch":"polecat/tk-work"}' "[$EPIC,$CONVOY_INT]")")" \
   "0|" \
   "bead names a branch to resume: passes (nothing is cut from base_branch)"

eq "$(run main "$(bead '{"target":""}' "[$EPIC,$CONVOY_INT]")")" \
   "1|UPDATE;ESCALATE;HOLD;DRAIN;" \
   "an EMPTY own target is no target: holds"

eq "$(run integration/tk-cnv "$TWO_PARENTS")" \
   "0|" \
   "base_branch already the convoy branch (explicit --var): passes"

CONVOY_MAIN='{"id":"tk-cnm","status":"open","issue_type":"convoy","dependency_type":"parent-child","metadata":{"target":"main"}}'
eq "$(run main "$(bead "$ROUTED" "[$EPIC,$CONVOY_MAIN]")")" \
   "0|" \
   "convoy targets base_branch itself: passes"

CONVOY_NONE='{"id":"tk-cn0","status":"open","issue_type":"convoy","dependency_type":"parent-child","metadata":{}}'
eq "$(run main "$(bead "$ROUTED" "[$EPIC,$CONVOY_NONE]")")" \
   "0|" \
   "convoy with no target: passes"

CONVOY_CLOSED='{"id":"tk-cnc","status":"closed","issue_type":"convoy","dependency_type":"parent-child","metadata":{"target":"integration/tk-cnc"}}'
eq "$(run main "$(bead "$ROUTED" "[$EPIC,$CONVOY_CLOSED]")")" \
   "0|" \
   "closed convoy: passes (it expects no more landings)"

EPIC_TARGETED='{"id":"tk-ept","status":"open","issue_type":"epic","dependency_type":"parent-child","metadata":{"target":"integration/tk-ept"}}'
eq "$(run main "$(bead "$ROUTED" "[$EPIC_TARGETED]")")" \
   "0|" \
   "a non-convoy parent with a target: passes (sling reads only convoy targets off parents)"

BLOCKS_CONVOY='{"id":"tk-cnk","status":"open","issue_type":"convoy","dependency_type":"blocks","metadata":{"target":"integration/tk-cnk"}}'
eq "$(run main "$(bead "$ROUTED" "[$BLOCKS_CONVOY]")")" \
   "0|" \
   "a convoy on a blocks edge is not a parent: passes"

# --- 3. Fail-closed arms. -----------------------------------------------------
# (The RC override must reach the `run` function itself — an env prefix on `eq`
# would apply after the command substitution has already expanded.)

out="$(FAKE_ESC_RC=1 run main "$TWO_PARENTS")"
eq "$out" "1|UPDATE;ESCALATE;" \
   "no release path recorded: does not hold, does not drain"

out="$(FAKE_HOLD_RC=1 run main "$TWO_PARENTS")"
eq "$out" "1|UPDATE;ESCALATE;HOLD;" \
   "hold did not land: does not drain"

# --- 4. Unreadable bead: pass with a warning, write nothing. -------------------

out="$(FAKE_SHOW_RC=1 run main "")"
eq "$out" "0|" "bd show fails: passes and writes nothing"
has "$(cat "$TMP/err")" "could not read tk-work" "bd show fails: warns on stderr"

eq "$(run main '{"error":"store unavailable"}')" \
   "0|" \
   "error object instead of a bead row: passes and writes nothing"
has "$(cat "$TMP/err")" "could not read tk-work" "error object: warns on stderr"

# --- Summary. -----------------------------------------------------------------
echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
