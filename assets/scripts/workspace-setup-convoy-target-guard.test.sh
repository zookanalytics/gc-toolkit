#!/usr/bin/env bash
# Hermetic test for mol-polecat-work's workspace-setup convoy target guard.
#
# `gc sling` resolves base_branch from the bead's own metadata.target, else the
# first convoy target on the ONE parent chain bd reports, else the rig default
# branch. A child filed under an epic and also linked to an owned convoy can
# report the epic, so the lookup never reaches the convoy: the child is poured
# from the default branch and would land there, and the integration branch never
# receives it. The guard reads every parent-child edge on the work bead and
# cancels the run before any worktree is poured.
#
# What it holds:
#   1. THE CASE — a child of an epic AND an open convoy targeting a branch other
#      than base_branch, with no target or branch of its own: notes, files a
#      human gate on the work bead, makes the work bead wait on it
#      (await-ruling.sh), cancels the run of workspace-setup (run-cancel.sh),
#      drain-acks, exits 1. The gate names the stake and the release: stamp the
#      target, then clear the gate, which re-slings the work from its own
#      target.
#   2. DISCRIMINATION — passes (no writes) when the bead names a branch to
#      resume, when its own target equals base_branch, when its convoys target
#      base_branch itself, when the convoy has no target or is closed, and when
#      only a non-convoy parent carries a target. Targets compare trimmed, the
#      way sling reads them.
#   3. FAIL CLOSED — no gate recorded means no wait, no cancel and no drain; a
#      wait that did not land means no cancel and no drain; a cancel that did
#      not land means no drain; a note the store refuses still cancels.
#   4. UNREADABLE BEAD — files a patrol finding under load-context's
#      unreadable-work key and cancels, with no wait (a bead no read reaches
#      cannot be blocked), and neither cancels nor drains when the finding
#      cannot be recorded either.
#   5. ORDER — the guard runs before the worktree is poured from base_branch.
#   6. THE GUARD WRITES NO MOLECULE MEMBER — it names no convoy delete and no
#      delete-source, and looks up no root: gascity's run cancel ends the run.
#   7. AN OWN TARGET THAT IS NOT THE BASE — a convoy child whose own target
#      differs from base_branch is declined: the target was stamped after the
#      pour or a --var override chose the base.
#   8. CONFLICTING CONVOYS — a child of convoys that target different branches
#      is declined with a gate that names every convoy, even when base_branch
#      is one of them, and passes once its own target names the base.
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

# --- 5. Order: the guard declines before the worktree is poured. ---------------
# Declining after `git worktree add ... origin/{{base_branch}}` would be too late
# to be the "before pouring" stop, so the guard's region must open first.
GUARD_LINE=$(grep -n '^# >>> workspace-setup-convoy-target-guard$' "$TOML" | cut -d: -f1)
ADD_LINE=$(grep -n '^# >>> workspace-setup-worktree-add$' "$TOML" | cut -d: -f1)
if [ -n "$GUARD_LINE" ] && [ -n "$ADD_LINE" ] && [ "$GUARD_LINE" -lt "$ADD_LINE" ]; then
  ok "guard region opens before the worktree-add region"
else
  bad "guard region must open before the worktree-add region" "guard=${GUARD_LINE:-none} add=${ADD_LINE:-none}"
fi

# --- Fakes. -------------------------------------------------------------------
# gc : `bd show` answers $FAKE_SHOW (exit $FAKE_SHOW_RC); `bd list` answers
#      $FAKE_LIST (exit $FAKE_LIST_RC) and captures its argv; `bd update`
#      (exit $FAKE_UPDATE_RC) and `runtime drain-ack` record into the ordered
#      verb log, and the update argv is captured where the note assertions can
#      read it.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "bd show")           printf '%s' "${FAKE_SHOW:-}"; exit "${FAKE_SHOW_RC:-0}" ;;
  "bd list")           shift 2; printf '%s\n' "$*" >> "${FAKE_LISTARGS:-/dev/null}"; printf '%s' "${FAKE_LIST:-}"; exit "${FAKE_LIST_RC:-0}" ;;
  "bd update")         shift 2; printf 'UPDATE\n' >> "$FAKE_LOG"; printf '%s\n' "$*" >> "${FAKE_UPDATE:-/dev/null}"; exit "${FAKE_UPDATE_RC:-0}" ;;
  "runtime drain-ack") printf 'DRAIN\n' >> "$FAKE_LOG"; exit 0 ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH"

# run-cancel.sh, await-ruling.sh, human-gate.sh and patrol-finding.sh resolved
# out of $GC_PACK_DIR exactly as the arm resolves them. Each records its verb into the ordered trace
# and its argv where the reason assertions can read it, and returns a code the
# assertions control.
mkdir -p "$TMP/pack/assets/scripts"
cat > "$TMP/pack/assets/scripts/run-cancel.sh" <<'CANCEL'
#!/usr/bin/env bash
printf 'CANCEL\n' >> "$FAKE_LOG"
printf '%s\n' "$*" >> "${FAKE_CANCEL:-/dev/null}"
exit "${FAKE_CANCEL_RC:-0}"
CANCEL
cat > "$TMP/pack/assets/scripts/await-ruling.sh" <<'AWAIT'
#!/usr/bin/env bash
printf 'AWAIT\n' >> "$FAKE_LOG"
printf '%s\n' "$*" >> "${FAKE_AWAIT:-/dev/null}"
exit "${FAKE_AWAIT_RC:-0}"
AWAIT
cat > "$TMP/pack/assets/scripts/human-gate.sh" <<'GATE'
#!/usr/bin/env bash
printf 'GATE\n' >> "$FAKE_LOG"
printf '%s\n' "$*" >> "${FAKE_GATE:-/dev/null}"
exit "${FAKE_GATE_RC:-0}"
GATE
cat > "$TMP/pack/assets/scripts/patrol-finding.sh" <<'FINDING'
#!/usr/bin/env bash
printf 'FINDING\n' >> "$FAKE_LOG"
printf '%s\n' "$*" >> "${FAKE_FINDING:-/dev/null}"
exit "${FAKE_FINDING_RC:-0}"
FINDING
chmod +x "$TMP/pack/assets/scripts/run-cancel.sh" "$TMP/pack/assets/scripts/await-ruling.sh" \
         "$TMP/pack/assets/scripts/human-gate.sh" "$TMP/pack/assets/scripts/patrol-finding.sh"
export GC_PACK_DIR="$TMP/pack" GC_RIG_ROOT="" GC_CITY_PATH=""

# run <base_branch> <work-bead-json> -> prints "<rc>|<ordered verb log>"
#   `{{base_branch}}` and `{{convoy_id}}` are formula placeholders, substituted
#   here the way the pour renders them. FAKE_*_RC control each stub's exit;
#   FAKE_UPDATE/CANCEL/AWAIT/GATE/FINDING/LISTARGS capture argv and $TMP/err the block's
#   stderr.
run() {
  : > "$TMP/log"; : > "$TMP/update"; : > "$TMP/cancel"; : > "$TMP/await"; : > "$TMP/gate"; : > "$TMP/finding"; : > "$TMP/listargs"
  sed -e "s|{{base_branch}}|$1|g" -e "s|{{convoy_id}}|tk-input|g" "$TMP/guard.raw" > "$TMP/guard.sh"
  local rc=0
  WORK_BEAD_ID=tk-work \
  CLAIMED_STEP_BEAD_ID=st-setup \
  FAKE_SHOW="$2" FAKE_SHOW_RC="${FAKE_SHOW_RC:-0}" \
  FAKE_LIST="${FAKE_LIST-[]}" FAKE_LIST_RC="${FAKE_LIST_RC:-0}" FAKE_LISTARGS="$TMP/listargs" \
  FAKE_LOG="$TMP/log" FAKE_UPDATE="$TMP/update" FAKE_CANCEL="$TMP/cancel" FAKE_AWAIT="$TMP/await" FAKE_GATE="$TMP/gate" FAKE_FINDING="$TMP/finding" \
  FAKE_CANCEL_RC="${FAKE_CANCEL_RC:-0}" FAKE_AWAIT_RC="${FAKE_AWAIT_RC:-0}" FAKE_GATE_RC="${FAKE_GATE_RC:-0}" FAKE_FINDING_RC="${FAKE_FINDING_RC:-0}" FAKE_UPDATE_RC="${FAKE_UPDATE_RC:-0}" \
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
   "1|UPDATE;GATE;AWAIT;CANCEL;DRAIN;" \
   "epic + integration convoy, no own target: notes, files a gate, waits on it, cancels, drain-acks, exits 1"

run main "$TWO_PARENTS" >/dev/null
has "$(cat "$TMP/gate")" "--key polecat-convoy-target-mismatch" "the gate uses its own situation key"
has "$(cat "$TMP/gate")" "--subject tk-work" "the gate blocks the work bead"
has "$(cat "$TMP/gate")" "integration/tk-cnv (convoy tk-cnv)" "the gate names the convoy and its branch"
has "$(cat "$TMP/gate")" "--message This work would branch from main and land there" "the gate opens with the stake, not an identifier"
has "$(cat "$TMP/gate")" "--set-metadata target=" "the gate names the target stamp that releases it"
has "$(cat "$TMP/gate")" "then clear this gate: tk-work waits on it, and clearing it re-slings tk-work, which pours from its own target" "the gate says clearing it re-slings the work from its own target"
has "$(cat "$TMP/gate")" "To stand down instead, close tk-work first" "the gate says how to stand down"
has "$(cat "$TMP/update")" "then clear this gate" "the work bead's note names the same release"
eq  "$(cat "$TMP/await")" "tk-work --key polecat-convoy-target-mismatch --formula mol-polecat-work" "the work bead waits on the gate under its key, re-slung through mol-polecat-work"
has "$(cat "$TMP/cancel")" "--step mol-polecat-work.workspace-setup" "cancels the run of THIS step"
has "$(cat "$TMP/cancel")" "--bead st-setup" "passes the claimed step bead as the cancel's hint"
has "$(cat "$TMP/cancel")" "integration/tk-cnv" "the cancel reason names the convoy branch"
has "$(cat "$TMP/update")" "--append-notes" "records the refusal on the work bead"
no  "$(cat "$TMP/update")" "--notes " "never REPLACES the work bead's notes"

# Only the convoy edge decides; the order the edges render in does not.
eq "$(run main "$(bead "$ROUTED" "[$CONVOY_INT,$EPIC]")")" \
   "1|UPDATE;GATE;AWAIT;CANCEL;DRAIN;" \
   "convoy edge listed first: declined the same way"

# Two convoys with different branches: the gate names both, so the reader
# picks the owner.
CONVOY_B='{"id":"tk-cnb","status":"open","issue_type":"convoy","dependency_type":"parent-child","metadata":{"target":"integration/tk-cnb"}}'
run main "$(bead "$ROUTED" "[$CONVOY_INT,$CONVOY_B]")" >/dev/null
has "$(cat "$TMP/gate")" "integration/tk-cnv (convoy tk-cnv)" "two convoys: names the first"
has "$(cat "$TMP/gate")" "integration/tk-cnb (convoy tk-cnb)" "two convoys: names the second"

# --- 2. Discrimination: no writes unless the base really is wrong. -------------

eq "$(run main "$(bead "$ROUTED" '[]')")" \
   "0|" \
   "no parents at all: passes"

eq "$(run main "$(bead "$ROUTED" "[$EPIC]")")" \
   "0|" \
   "epic parent only: passes"
eq "$(cat "$TMP/listargs")" "" "a passing bead costs no root lookup"

eq "$(run integration/tk-cnv "$(bead '{"target":"integration/tk-cnv"}' "[$EPIC,$CONVOY_INT]")")" \
   "0|" \
   "own target equals base_branch: passes (sling took it before any parent)"

eq "$(run main "$(bead '{"target":"main"}' "[$EPIC,$CONVOY_INT]")")" \
   "0|" \
   "own target equals base_branch but not the convoy's branch: passes (the bead's own target is the override)"

eq "$(run main "$(bead '{"target":"integration/tk-other"}' "[$EPIC]")")" \
   "0|" \
   "own target differs from base_branch, no convoy parent: passes (not a convoy child)"

eq "$(run main "$(bead '{"branch":"polecat/tk-work"}' "[$EPIC,$CONVOY_INT]")")" \
   "0|" \
   "bead names a branch to resume: passes (nothing is cut from base_branch)"

eq "$(run polecat/tk-anchor "$(bead '{"branch":"polecat/tk-anchor","target":"main"}' "[$EPIC,$CONVOY_INT]")")" \
   "0|" \
   "a branch to resume and a target that differs from base_branch: passes (a rework child branches from the branch under review)"

eq "$(run main "$(bead '{"target":""}' "[$EPIC,$CONVOY_INT]")")" \
   "1|UPDATE;GATE;AWAIT;CANCEL;DRAIN;" \
   "an EMPTY own target is no target: declined"

# Sling trims the targets it reads, so the guard compares them trimmed too.
eq "$(run main "$(bead '{"target":"  "}' "[$EPIC,$CONVOY_INT]")")" \
   "1|UPDATE;GATE;AWAIT;CANCEL;DRAIN;" \
   "a whitespace-only own target is no target: declined"
has "$(cat "$TMP/gate")" "--message This work would branch from main and land there" "a whitespace-only own target: the no-target gate"

eq "$(run integration/tk-cnv "$(bead '{"target":" integration/tk-cnv "}' "[$EPIC,$CONVOY_INT]")")" \
   "0|" \
   "own target padded with whitespace equals base_branch once trimmed: passes"

CONVOY_PADDED='{"id":"tk-cnp","status":"open","issue_type":"convoy","dependency_type":"parent-child","metadata":{"target":" integration/tk-cnv\t"}}'
eq "$(run integration/tk-cnv "$(bead "$ROUTED" "[$EPIC,$CONVOY_PADDED]")")" \
   "0|" \
   "convoy target padded with whitespace equals base_branch once trimmed: passes"

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

out="$(FAKE_GATE_RC=1 run main "$TWO_PARENTS")"
eq "$out" "1|UPDATE;GATE;" \
   "no gate recorded: no wait, no cancel, no drain"

out="$(FAKE_AWAIT_RC=1 run main "$TWO_PARENTS")"
eq "$out" "1|UPDATE;GATE;AWAIT;" \
   "the wait did not land: no cancel, no drain"

out="$(FAKE_CANCEL_RC=1 run main "$TWO_PARENTS")"
eq "$out" "1|UPDATE;GATE;AWAIT;CANCEL;" \
   "the cancel did not land: does not drain"

# The note is the bead's own record; the cancel reason carries the same facts, so
# a note the store refuses does not stop the cancel.
out="$(FAKE_UPDATE_RC=1 run main "$TWO_PARENTS")"
eq "$out" "1|UPDATE;GATE;AWAIT;CANCEL;DRAIN;" \
   "the note is refused: still files a gate, waits, cancels, drain-acks"
has "$(cat "$TMP/err")" "the cancel reason on this step still records it" "the note is refused: says where the record still lives"

# --- 4. Unreadable bead: decline the way load-context does. --------------------
# Nothing proves the base of a bead nobody can read, and a bead no read reaches
# cannot be blocked. The finding shares load-context's situation key, so one
# outage files one finding per bead, and it asks for the re-sling.

out="$(FAKE_SHOW_RC=1 run main "")"
eq "$out" "1|UPDATE;FINDING;CANCEL;DRAIN;" "bd show fails: notes, files a finding, cancels, drain-acks, exits 1"
has "$(cat "$TMP/finding")" "--scope polecat-findings --key polecat-unreadable-work.tk-work" "bd show fails: the finding uses load-context's unreadable-work key, per bead"
has "$(cat "$TMP/finding")" "--title Work bead tk-work could not be read at workspace-setup" "bd show fails: the finding names the work bead"
has "$(cat "$TMP/finding")" "--message Could not read work bead tk-work at workspace-setup" "bd show fails: the finding opens with the stake"
has "$(cat "$TMP/finding")" "then re-sling it" "bd show fails: the finding names the release"
eq  "$(cat "$TMP/gate")" "" "bd show fails: no gate, since a bead no read reaches cannot be blocked"
eq  "$(cat "$TMP/await")" "" "bd show fails: no wait"
has "$(cat "$TMP/cancel")" "--step mol-polecat-work.workspace-setup" "bd show fails: cancels the run of THIS step"
has "$(cat "$TMP/cancel")" "unreadable work bead" "bd show fails: the cancel reason says why"
eq "$(cat "$TMP/listargs")" "" "bd show fails: no store listing"

out="$(run main '{"error":"store unavailable"}')"
eq "$out" "1|UPDATE;FINDING;CANCEL;DRAIN;" "error object instead of a bead row: declined"
has "$(cat "$TMP/finding")" "--key polecat-unreadable-work.tk-work" "error object: the finding uses the unreadable-work key"

eq "$(run main '[]')" "1|UPDATE;FINDING;CANCEL;DRAIN;" "an empty array: declined"
eq "$(run main '[null]')" "1|UPDATE;FINDING;CANCEL;DRAIN;" "a row that is not an object: declined"
eq "$(run main 'not json')" "1|UPDATE;FINDING;CANCEL;DRAIN;" "output that is not JSON: declined"

out="$(FAKE_SHOW_RC=1 FAKE_FINDING_RC=1 run main "")"
eq "$out" "1|UPDATE;FINDING;" "unreadable, no finding recorded: does not cancel, does not drain"

out="$(FAKE_SHOW_RC=1 FAKE_CANCEL_RC=1 run main "")"
eq "$out" "1|UPDATE;FINDING;CANCEL;" "unreadable, cancel did not land: does not drain"

# --- 6. The guard writes no molecule member. -----------------------------------
# A molecule's lifecycle is gascity's: the guard ends the run through
# run-cancel.sh and the release re-slings the work, so it names no convoy delete
# or delete-source for a person to run and looks up no root.
run main "$TWO_PARENTS" >/dev/null
no "$(cat "$TMP/gate")" "convoy delete" "the gate names no convoy delete"
no "$(cat "$TMP/gate")" "delete-source" "the gate names no delete-source"
no "$(cat "$TMP/update")" "convoy delete" "the note names no convoy delete"
eq "$(cat "$TMP/listargs")" "" "the guard reads no root: gascity's cancel resolves the run from the step"
no "$GUARD" "convoy delete" "the guard block itself runs no convoy delete"

# --- 7. An own target that is not the base. ------------------------------------
# Sling pours from a bead's own target, so a convoy child whose target differs
# from base_branch was stamped after the pour, or a --var override chose the
# base. Its run is cancelled before a branch is cut from main, and the re-sling
# the gate releases pours from the bead's own target.
STAMPED="$(bead '{"target":"integration/tk-cnv","gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat"}' "[$EPIC,$CONVOY_INT]")"
eq "$(run main "$STAMPED")" \
   "1|UPDATE;GATE;AWAIT;CANCEL;DRAIN;" \
   "own target stamped after a pour from main: declined"
has "$(cat "$TMP/gate")" "--key polecat-convoy-target-mismatch" "stale own target: the gate uses the convoy guard's key"
has "$(cat "$TMP/gate")" "--message This work would branch from main but land on integration/tk-cnv" "stale own target: the gate opens with the stake"
has "$(cat "$TMP/gate")" "clearing it re-slings tk-work, which pours from its own target" "stale own target: the gate names the re-sling"
has "$(cat "$TMP/cancel")" "own target integration/tk-cnv differs from base_branch main" "stale own target: the cancel reason says why"

# The other direction: poured from the convoy's branch, but the bead names main,
# so main would receive the integration branch's unlanded history.
eq "$(run integration/tk-cnv "$(bead '{"target":"main"}' "[$EPIC,$CONVOY_INT]")")" \
   "1|UPDATE;GATE;AWAIT;CANCEL;DRAIN;" \
   "own target main on a run poured from the convoy's branch: declined"
has "$(cat "$TMP/gate")" "--message This work would branch from integration/tk-cnv but land on main" "own target main: the gate opens with the stake"

# --- 8. Conflicting convoys. ---------------------------------------------------
# The work can land on only one of two convoy branches, and nothing on the bead
# says which. A base_branch that matches one of them is the parent bd happened
# to report, not a choice, so the child is still declined, and the gate does not
# call that base wrong.
CONFLICT="$(bead "$ROUTED" "[$CONVOY_INT,$CONVOY_B]")"
eq "$(run integration/tk-cnv "$CONFLICT")" \
   "1|UPDATE;GATE;AWAIT;CANCEL;DRAIN;" \
   "two convoys on different branches, base_branch is one of them: declined"
has "$(cat "$TMP/gate")" "--message This work belongs to convoys that land on different branches: integration/tk-cnb (convoy tk-cnb), integration/tk-cnv (convoy tk-cnv)." "conflict: the gate opens with the stake and names every convoy"
has "$(cat "$TMP/gate")" "This run was poured from integration/tk-cnv" "conflict: the gate names the poured base"
no  "$(cat "$TMP/gate")" "and land there" "conflict: the gate does not call the poured base wrong"
has "$(cat "$TMP/gate")" "naming the convoy branch that should receive it" "conflict: the release asks which convoy receives it"
has "$(cat "$TMP/gate")" "clearing it re-slings tk-work" "conflict: the gate names the re-sling"
has "$(cat "$TMP/cancel")" "convoys target different branches" "conflict: the cancel reason says why"

eq "$(run main "$CONFLICT")" \
   "1|UPDATE;GATE;AWAIT;CANCEL;DRAIN;" \
   "two convoys on different branches, base_branch is neither: declined"
has "$(cat "$TMP/gate")" "land on different branches" "base_branch is neither: the conflict gate"

eq "$(run integration/tk-cnv "$(bead '{"target":"integration/tk-cnv"}' "[$CONVOY_INT,$CONVOY_B]")")" \
   "0|" \
   "two convoys, own target names base_branch: passes (the stamp chose one)"

CONVOY_SAME='{"id":"tk-cns","status":"open","issue_type":"convoy","dependency_type":"parent-child","metadata":{"target":"integration/tk-cnv"}}'
eq "$(run integration/tk-cnv "$(bead "$ROUTED" "[$CONVOY_INT,$CONVOY_SAME]")")" \
   "0|" \
   "two convoys on the same branch, which is base_branch: passes"
eq "$(run main "$(bead "$ROUTED" "[$CONVOY_INT,$CONVOY_SAME]")")" \
   "1|UPDATE;GATE;AWAIT;CANCEL;DRAIN;" \
   "two convoys on the same branch, base_branch differs: declined"
has "$(cat "$TMP/gate")" "--message This work would branch from main and land there" "two convoys on the same branch: the one-branch gate, not the conflict one"

CONVOY_B_CLOSED='{"id":"tk-cnb","status":"closed","issue_type":"convoy","dependency_type":"parent-child","metadata":{"target":"integration/tk-cnb"}}'
eq "$(run integration/tk-cnv "$(bead "$ROUTED" "[$CONVOY_INT,$CONVOY_B_CLOSED]")")" \
   "0|" \
   "a second convoy that is closed does not conflict: passes"

# --- Summary. -----------------------------------------------------------------
echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
