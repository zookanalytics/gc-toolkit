#!/usr/bin/env bash
# Hermetic test for assets/scripts/step-close.sh (tk-niu2f).
#
# THE BUG the script guards: a graph.v2 step closing its own bead on
# `$GC_TRIGGER_BEAD_ID`. `gc hook --claim` does not refresh that variable, so
# after a claim it still names whatever the session was spawned with — observed
# live as another session's in_progress step bead in an unrelated molecule. The
# close SUCCEEDS, so nothing in the log looks wrong: one workflow loses a step
# it never ran, and the closing session's own step stays open and is re-offered
# forever.
#
# What is exercised here:
#   * the REGRESSION ANCHOR — a stale env id pointing at a foreign in_progress
#     bead, with a legitimate own-bead present. The foreign bead must be
#     untouched and the own bead closed;
#   * resolution by (assignee, gc.step_ref) with no env id at all — the path
#     that makes the environment irrelevant rather than merely checked;
#   * --bead as a HINT: honoured when it verifies, ignored (with a note) when it
#     does not, so a caller carrying a stale claim id cannot re-create the bug;
#   * the SUBSTRING trap — jq's `inside`/`contains` match substrings, so a
#     session named lx-zzk would "own" lx-zzk9's bead. Exact membership only;
#   * the OPEN-STATUS anchor (tk-jww3y) — a graph.v2 step is assigned by the
#     graph, not by the claim, so it executes at status `open` and never reaches
#     in_progress. Resolution must turn on the (assignee, step_ref) pair, not on
#     a status the dispatch never sets. With it: that a SIBLING step, open and
#     pre-assigned to the same session, is still never touched; that in_progress
#     outranks open rather than merging with it; and that ambiguity inside the
#     open tier is refused like any other;
#   * ambiguity: two in_progress beads for one step, which is refused rather
#     than guessed, because guessing is how the original defect writes;
#   * the refusal DIAGNOSTIC distinguishing "not your bead" from "your bead, in
#     a status this script will not close" — they have different fixes, and
#     conflating them sent a reader hunting a stale-environment bug that had not
#     happened;
#   * idempotence: an already-closed step bead is a normal re-run, exit 0;
#   * the last-resort env path, which still requires verification;
#   * refusal arms write NOTHING — the invariant that makes a stall the safe
#     failure;
#   * usage errors, including a value-taking option at the end of argv (the
#     parse loop must exit 2, not spin);
#   * control characters inside bd's JSON, which break an unfiltered `| jq` and
#     would otherwise read as "no such bead".
#
# No live city, Dolt, network, or beads — only a tmpdir, a `gc` stub, and the
# script itself.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/step-close.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
# `grep -q` fed by a here-string, never by a pipe: under pipefail a piped writer
# takes SIGPIPE when grep quits at its first match and a successful match is
# reported as a failure (doctor/check-pipefail-grep-q).
# `--` before the pattern: several asserted strings start with `--` (option
# names), which grep would otherwise parse as its own flags.
hasin()  { grep -q -- "$2" <<< "$1"; }
has()    { if hasin "$1" "$2"; then ok "$3"; else bad "$3 (missing '$2' in: $1)"; fi; }
hasnt()  { if hasin "$1" "$2"; then bad "$3 (found '$2' in: $1)"; else ok "$3"; fi; }

mkdir -p "$TMP/bin"

# --- gc stub. ----------------------------------------------------------------
# Bead table, one per line: id|assignee|step_ref|status[|root[|session_id]]
# Root defaults to root-1 and the session id to absent, so a row that does not
# care about the molecule stays four fields wide.
# `bd show`   : the single bead, as a one-element array (unknown id -> []).
# `bd list`   : every bead matching --status=, --assignee= and
#               --metadata-field=<key>=<value>. Status takes a comma list, and
#               an unsupported metadata key matches nothing — bd filters on the
#               key it was given, and a stub that ignored it would answer a
#               question the real one never would.
# `bd update` : records "<id> <outcome>" in $FAKE_CLOSED; refuses ids listed in
#               $FAKE_UPDFAIL so the write-failure arm is reachable.
# FAKE_CTRL=1 injects a raw control character into every title, reproducing the
# bd payloads that make an unfiltered `| jq` exit "invalid".
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
[ "$1" = "bd" ] || exit 0
shift

emit_one() {
  # $1 id  $2 assignee  $3 step_ref  $4 status  $5 root  $6 session id
  local title="step $1" meta
  [ "${FAKE_CTRL:-0}" = "1" ] && title="step $(printf '\001')$1"
  meta=$(printf '"gc.step_ref":"%s","gc.root_bead_id":"%s"' "$3" "${5:-root-1}")
  [ -n "${6:-}" ] && meta="$meta,\"gc.session_id\":\"$6\""
  printf '{"id":"%s","title":"%s","status":"%s","assignee":"%s","metadata":{%s}}' \
    "$1" "$title" "$4" "$2" "$meta"
}

case "$1" in
  show)
    want="$2"
    out=""
    while IFS='|' read -r id assignee step status root sid; do
      [ -n "$id" ] || continue
      [ "$id" = "$want" ] || continue
      out=$(emit_one "$id" "$assignee" "$step" "$status" "${root:-root-1}" "${sid:-}")
    done < "$FAKE_BEADS"
    if [ -n "$out" ]; then printf '[%s]\n' "$out"; else printf '[]\n'; fi ;;
  list)
    # FAKE_LIST_BLIND makes the listing return nothing while `show` still
    # answers — the only way to reach the last-resort env path, which is
    # otherwise shadowed by discovery.
    [ "${FAKE_LIST_BLIND:-0}" = "1" ] && { printf '[]\n'; exit 0; }
    # FAKE_LIST_GARBAGE: bd reporting an error as a JSON OBJECT rather than the
    # expected array — the shape that turns an unguarded `.[]` into a jq error.
    [ "${FAKE_LIST_GARBAGE:-0}" = "1" ] && { printf '{"error":"store unavailable"}\n'; exit 0; }
    wstatus=""; wassignee=""; wkey=""; wval=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --status=*)   wstatus="${1#--status=}" ;;
        --status)     wstatus="${2:-}"; shift ;;
        --assignee=*) wassignee="${1#--assignee=}" ;;
        --assignee)   wassignee="${2:-}"; shift ;;
        --metadata-field=*) f="${1#--metadata-field=}"; wkey="${f%%=*}"; wval="${f#*=}" ;;
        --metadata-field)   f="${2:-}"; wkey="${f%%=*}"; wval="${f#*=}"; shift ;;
      esac
      shift
    done
    out=""
    while IFS='|' read -r id assignee step status root sid; do
      [ -n "$id" ] || continue
      root="${root:-root-1}"
      if [ -n "$wstatus" ]; then
        case ",$wstatus," in *",$status,"*) ;; *) continue ;; esac
      fi
      [ -n "$wassignee" ] && [ "$assignee" != "$wassignee" ] && continue
      case "$wkey" in
        "") ;;
        gc.root_bead_id) [ "$root" = "$wval" ] || continue ;;
        gc.session_id)   [ "${sid:-}" = "$wval" ] || continue ;;
        *) continue ;;
      esac
      obj=$(emit_one "$id" "$assignee" "$step" "$status" "$root" "${sid:-}")
      if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
    done < "$FAKE_BEADS"
    printf '[%s]\n' "$out" ;;
  update)
    target="$2"
    if [ -f "$FAKE_UPDFAIL" ] && grep -qx "$target" "$FAKE_UPDFAIL" 2>/dev/null; then
      echo "bd: $target: permission denied (stub)" >&2
      exit 1
    fi
    outcome=""
    for a in "$@"; do
      case "$a" in gc.outcome=*) outcome="${a#gc.outcome=}" ;; esac
    done
    printf '%s %s\n' "$target" "$outcome" >> "$FAKE_CLOSED"
    echo "✓ Updated issue: $target" ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH"
export FAKE_BEADS="$TMP/beads" FAKE_CLOSED="$TMP/closed" FAKE_UPDFAIL="$TMP/updfail"
: > "$FAKE_CLOSED"; : > "$FAKE_UPDFAIL"

MINE="gc-toolkit__polecat-lx-zzk9"
STEP="mol-feedback-distiller.load-and-gate"
OTHER_STEP="mol-feedback-miner.load-context"

# The live 2026-08-13 shape: my own step bead, plus the bead the stale env
# variable actually named — another session, another molecule, in progress.
reset_beads() {
  cat > "$FAKE_BEADS" <<B
tk-9b3d8|$MINE|$STEP|in_progress
tk-dy6cn|gc-toolkit__polecat-lx-dq84|$OTHER_STEP|in_progress
B
  : > "$FAKE_CLOSED"
  : > "$FAKE_UPDFAIL"
}

# This suite runs INSIDE a live session, whose own GC_SESSION_NAME, GC_ALIAS and
# GC_TRIGGER_BEAD_ID would otherwise leak in as extra identities and make the
# results depend on who ran it. Every invocation starts from a cleared set.
gcenv() { env -u GC_SESSION_NAME -u GC_SESSION_ID -u GC_ALIAS -u GC_TRIGGER_BEAD_ID "$@"; }

run() {
  # run <args...>; sets OUT (stdout+stderr) and RC.
  RC=0
  OUT=$(gcenv GC_SESSION_NAME="$MINE" GC_SESSION_ID="lx-zzk9" bash "$SCRIPT" "$@" 2>&1) || RC=$?
}

# --- 1. THE REGRESSION ANCHOR ------------------------------------------------
# Stale GC_TRIGGER_BEAD_ID naming a live foreign bead, own bead present.
reset_beads
RC=0
OUT=$(gcenv GC_SESSION_NAME="$MINE" GC_SESSION_ID="lx-zzk9" GC_TRIGGER_BEAD_ID="tk-dy6cn" \
      bash "$SCRIPT" --step "$STEP" --outcome pass 2>&1) || RC=$?
eq "$RC" "0" "(STALE-ENV) a stale env id does not stop the close"
has "$(cat "$FAKE_CLOSED")" "tk-9b3d8 pass" "(STALE-ENV) closed THIS session's bead for this step"
hasnt "$(cat "$FAKE_CLOSED")" "tk-dy6cn" "(STALE-ENV) the other session's bead was NOT closed"
has "$OUT" "GC_TRIGGER_BEAD_ID=tk-dy6cn is not this step's bead" \
    "(STALE-ENV) the stale-environment fingerprint is reported"

# --- 1b. the SAME-SESSION stale variant --------------------------------------
# The commoner half of the same defect, and the one that fires on the happy
# path: a formula whose steps deliberately share one session (continuation-group
# affinity) gets a CORRECT variable on step 1 and the same, now-stale, value on
# steps 2 and 3. It points at this session's OWN already-closed step 1, so the
# old idiom re-closes a closed bead — a successful, exit-0 no-op — and steps 2
# and 3 are re-offered forever. Nothing foreign is touched, so the foreign-bead
# fixture above does not cover it.
cat > "$FAKE_BEADS" <<B
tk-step1|$MINE|mol-feedback-distiller.load-and-gate|closed
tk-step2|$MINE|mol-feedback-distiller.judge-and-cluster|in_progress
B
: > "$FAKE_CLOSED"
RC=0
OUT=$(gcenv GC_SESSION_NAME="$MINE" GC_TRIGGER_BEAD_ID="tk-step1" \
      bash "$SCRIPT" --step mol-feedback-distiller.judge-and-cluster 2>&1) || RC=$?
eq "$RC" "0" "(SELF-STALE) a stale id naming this session's OWN earlier step still resolves"
has "$(cat "$FAKE_CLOSED")" "tk-step2 pass" "(SELF-STALE) closed the step actually being executed"
hasnt "$(cat "$FAKE_CLOSED")" "tk-step1" "(SELF-STALE) the already-closed step 1 was not re-closed"
has "$OUT" "GC_TRIGGER_BEAD_ID=tk-step1 is not this step's bead" \
    "(SELF-STALE) the mismatch is reported even though both beads are ours"

# --- 1c. THE FOREIGN-MOLECULE ANCHOR (tk-xgfhj3) -----------------------------
# The assignee is not a molecule. A pool agent wears the same one on every run
# it has ever made, so the same gc.step_ref of every earlier molecule matches
# it — and the earlier ones are all closed. Resolution therefore has to turn on
# gc.root_bead_id, with the assignee as corroboration rather than as the key.
#
# Live shape (2026-08-24, root tk-ginxk4): the six step beads of the running
# chain had lost their assignee, the same agent's earlier molecules had theirs,
# and the close loop answered "already closed — nothing to do" six times, exit
# 0, over ids belonging to two other roots. The chain stayed open and was
# re-offered as new work; nothing in the log said so.
FSTEP="mol-polecat-work.load-context"

# (a) Nothing proves which molecule this shell is executing, and the only
#     candidate belongs to another root: a refusal, never a reported pass.
cat > "$FAKE_BEADS" <<B
tk-mine11||$FSTEP|open|root-mine|
tk-old111|$MINE|$FSTEP|closed|root-old|lx-old
B
: > "$FAKE_CLOSED"
run --step "$FSTEP"
eq "$RC" "2" "(FOREIGN-ROOT) a closed bead from another molecule is not a close"
eq "$(wc -l < "$FAKE_CLOSED" | tr -d ' ')" "0" "(FOREIGN-ROOT) nothing was written"
hasnt "$OUT" "nothing to do" "(FOREIGN-ROOT) the false-green line is not emitted"
has "$OUT" "root-old" "(FOREIGN-ROOT) the molecule the stray bead belongs to is named"
has "$OUT" "still UNCLOSED" "(FOREIGN-ROOT) names the consequence"

# (b) The same store, plus the gc.session_id a claim stamps on the step it
#     hands out. That names the molecule, so the chain closes on its own bead
#     even though the finalizer stripped the assignee off it.
cat > "$FAKE_BEADS" <<B
tk-mine11||$FSTEP|open|root-mine|lx-zzk9
tk-old111|$MINE|$FSTEP|closed|root-old|lx-old
B
: > "$FAKE_CLOSED"
run --step "$FSTEP"
eq "$RC" "0" "(STRIPPED-ASSIGNEE) an unassigned bead inside our own molecule resolves"
has "$(cat "$FAKE_CLOSED")" "tk-mine11 pass" "(STRIPPED-ASSIGNEE) closed this chain's bead"
hasnt "$(cat "$FAKE_CLOSED")" "tk-old111" "(STRIPPED-ASSIGNEE) the earlier molecule was untouched"

# (c) ...and --root does the same job for a caller holding `.root_bead_id` from
#     `gc hook --claim --json`, with no session stamp anywhere.
cat > "$FAKE_BEADS" <<B
tk-mine11||$FSTEP|open|root-mine|
tk-old111|$MINE|$FSTEP|closed|root-old|lx-old
B
: > "$FAKE_CLOSED"
run --step "$FSTEP" --root root-mine
eq "$RC" "0" "(ROOT-FLAG) an explicit --root resolves what nothing else could"
has "$(cat "$FAKE_CLOSED")" "tk-mine11 pass" "(ROOT-FLAG) closed the bead in the named molecule"

# (d) The wrong-close half of the same defect: a LIVE earlier molecule, same
#     assignee, same step, at in_progress — the tier that outranks ours. Scoped
#     to the molecule it is invisible; unscoped it is the bead that gets closed.
cat > "$FAKE_BEADS" <<B
tk-mine11|$MINE|$FSTEP|open|root-mine|lx-zzk9
tk-old222|$MINE|$FSTEP|in_progress|root-old|lx-old
B
: > "$FAKE_CLOSED"
run --step "$FSTEP"
eq "$RC" "0" "(FOREIGN-LIVE) our own open bead resolves past a foreign in_progress one"
has "$(cat "$FAKE_CLOSED")" "tk-mine11 pass" "(FOREIGN-LIVE) closed this chain's bead"
hasnt "$(cat "$FAKE_CLOSED")" "tk-old222" "(FOREIGN-LIVE) the other molecule's live step was NOT closed"

# --- 1d. a step of our own molecule held by another session ------------------
# Molecule scope answers "which chain", not "who is running it". A second
# worker on the chain is a real condition with its own fix, so it is refused
# and named rather than closed underneath them.
cat > "$FAKE_BEADS" <<B
tk-held11|gc-toolkit__polecat-lx-other|$FSTEP|in_progress|root-mine|lx-other
tk-sib111|$MINE|mol-polecat-work.implement|open|root-mine|lx-zzk9
B
: > "$FAKE_CLOSED"
run --step "$FSTEP"
eq "$RC" "2" "(CONTENDED) a step held by another session is refused"
eq "$(wc -l < "$FAKE_CLOSED" | tr -d ' ')" "0" "(CONTENDED) nothing was written"
has "$OUT" "tk-held11 in_progress gc-toolkit__polecat-lx-other" "(CONTENDED) the holder is named"
has "$OUT" "second worker" "(CONTENDED) says what that means"

# (e) A step of our own molecule that someone else already closed is done, not
#     contended: within one molecule the step_ref names one bead, and a re-run
#     that finds it closed has nothing left to do.
cat > "$FAKE_BEADS" <<B
tk-mine11|gc-toolkit__polecat-lx-other|$FSTEP|closed|root-mine|lx-other
tk-sib111|$MINE|mol-polecat-work.implement|open|root-mine|lx-zzk9
B
: > "$FAKE_CLOSED"
run --step "$FSTEP"
eq "$RC" "0" "(CLOSED-BY-PEER) a step closed by another session in our molecule is done"
eq "$(wc -l < "$FAKE_CLOSED" | tr -d ' ')" "0" "(CLOSED-BY-PEER) nothing was re-written"
has "$OUT" "already closed" "(CLOSED-BY-PEER) says so"

# --- 1e. husks from earlier runs do not stall the close ----------------------
# The cost of scoping would be a stall whenever the scope cannot be derived, so
# the derivation reads this step's own live bead before it reads the formula's:
# open beads from two abandoned molecules say nothing about which one is ours,
# and the bead for THIS step still does.
cat > "$FAKE_BEADS" <<B
tk-mine11|$MINE|$FSTEP|in_progress|root-a|
tk-husk11|$MINE|mol-polecat-work.implement|open|root-b|
tk-husk22|$MINE|mol-polecat-work.self-review|open|root-c|
B
: > "$FAKE_CLOSED"
run --step "$FSTEP"
eq "$RC" "0" "(HUSKS) two abandoned molecules do not block a close"
has "$(cat "$FAKE_CLOSED")" "tk-mine11 pass" "(HUSKS) closed the bead for this step"

# --- 2. resolution with no env id at all -------------------------------------
reset_beads
run --step "$STEP"
eq "$RC" "0" "(NO-ENV) resolves with GC_TRIGGER_BEAD_ID unset"
has "$(cat "$FAKE_CLOSED")" "tk-9b3d8 pass" "(NO-ENV) closed by (assignee, step_ref)"
has "$OUT" "resolved by (molecule root-1, step_ref)" "(NO-ENV) reports how it resolved"

# --- 2b. THE OPEN-STATUS REGRESSION ANCHOR (tk-jww3y) ------------------------
# A graph.v2 step bead is assigned to its session by the GRAPH, not by the
# claim, so `gc hook --claim` finds the assignee already set and advances
# nothing: the step is executed at status `open` and never reaches in_progress.
# Live shape from mol-feedback-distiller run tk-u67el (2026-08-14) — tk-jihd0
# and tk-xf0ly both went open/unassigned -> open/assigned -> closed, with no
# in_progress state anywhere in their history. Resolution must not turn on a
# status the dispatch never sets; the ownership proof is the (assignee,
# step_ref) pair, and it holds here.
cat > "$FAKE_BEADS" <<B
tk-xf0ly|$MINE|$STEP|open
B
: > "$FAKE_CLOSED"
run --step "$STEP"
eq "$RC" "0" "(OPEN) a step bead left at open by the claim resolves"
has "$(cat "$FAKE_CLOSED")" "tk-xf0ly pass" "(OPEN) it is closed like any other own bead"
has "$OUT" "resolved by (molecule root-1, step_ref)" "(OPEN) resolved on the ownership pair, not on status"

# --- 2c. a SIBLING step, pre-assigned open, is not touched -------------------
# The safety property that makes 2b safe. The graph assigns every step of the
# molecule to the same session at once (both live beads above were assigned
# within one second of each other), so at any moment several open beads carry
# this session's name. They are told apart by `gc.step_ref` — the one fact the
# arm passes in — so accepting `open` cannot close a step that has not run.
cat > "$FAKE_BEADS" <<B
tk-jihd0|$MINE|mol-feedback-distiller.judge-and-cluster|open
tk-xf0ly|$MINE|mol-feedback-distiller.file-and-dispatch|open
B
: > "$FAKE_CLOSED"
run --step mol-feedback-distiller.judge-and-cluster
eq "$RC" "0" "(SIBLING) one of several open beads for this session resolves"
has "$(cat "$FAKE_CLOSED")" "tk-jihd0 pass" "(SIBLING) closed the step this arm named"
hasnt "$(cat "$FAKE_CLOSED")" "tk-xf0ly" "(SIBLING) the next step's pre-assigned bead was NOT closed"

# --- 2d. in_progress outranks open -------------------------------------------
# The two statuses are tiers, not one merged set. Merging them would make this
# fixture — a bead the claim DID advance, plus a same-step bead pre-assigned by
# a second molecule — an ambiguity refusal, breaking a case that works today.
cat > "$FAKE_BEADS" <<B
tk-live1|$MINE|$STEP|in_progress
tk-pend1|$MINE|$STEP|open
B
: > "$FAKE_CLOSED"
run --step "$STEP"
eq "$RC" "0" "(TIER) in_progress resolves even when an open same-step bead exists"
has "$(cat "$FAKE_CLOSED")" "tk-live1 pass" "(TIER) the started bead is the one closed"
hasnt "$(cat "$FAKE_CLOSED")" "tk-pend1" "(TIER) the open one was left alone"
eq "$(wc -l < "$FAKE_CLOSED" | tr -d ' ')" "1" "(TIER) exactly one write"

# --- 2e. ambiguity within the open tier is still refused ---------------------
cat > "$FAKE_BEADS" <<B
tk-open1|$MINE|$STEP|open
tk-open2|$MINE|$STEP|open
B
: > "$FAKE_CLOSED"
run --step "$STEP"
eq "$RC" "2" "(OPEN-AMBIG) two open beads for one step is a refusal, not a guess"
eq "$(wc -l < "$FAKE_CLOSED" | tr -d ' ')" "0" "(OPEN-AMBIG) nothing was written"
has "$OUT" "tk-open1" "(OPEN-AMBIG) both candidates are named — tk-open1"
has "$OUT" "tk-open2" "(OPEN-AMBIG) both candidates are named — tk-open2"

# --- 2f. --bead and the env path both accept open ----------------------------
cat > "$FAKE_BEADS" <<B
tk-open1|$MINE|$STEP|open
tk-open2|$MINE|$STEP|open
B
: > "$FAKE_CLOSED"
run --step "$STEP" --bead tk-open2
eq "$RC" "0" "(OPEN-HINT) a hint verifying at open breaks the ambiguity"
has "$(cat "$FAKE_CLOSED")" "tk-open2 pass" "(OPEN-HINT) the named open bead is the one closed"

cat > "$FAKE_BEADS" <<B
tk-solo2|$MINE|$STEP|open
B
: > "$FAKE_CLOSED"
RC=0
OUT=$(gcenv GC_SESSION_NAME="$MINE" GC_TRIGGER_BEAD_ID="tk-solo2" \
      FAKE_LIST_BLIND=1 bash "$SCRIPT" --step "$STEP" 2>&1) || RC=$?
eq "$RC" "0" "(OPEN-ENV) the last-resort env path accepts a verified open bead"
has "$(cat "$FAKE_CLOSED")" "tk-solo2 pass" "(OPEN-ENV) it closed the verified bead"

# --- 2g. "your bead, unexpected status" is not reported as "not your bead" ---
# The diagnostic that sent a reader hunting the stale-environment defect
# (tk-niu2f) after what was really a status mismatch. `blocked` is owned by this
# session for this step and is still not closed — but the refusal must say so,
# because "not this step's bead" is a different problem with a different fix.
cat > "$FAKE_BEADS" <<B
tk-blockd|$MINE|$STEP|blocked
B
: > "$FAKE_CLOSED"
RC=0
OUT=$(gcenv GC_SESSION_NAME="$MINE" GC_TRIGGER_BEAD_ID="tk-blockd" \
      bash "$SCRIPT" --step "$STEP" 2>&1) || RC=$?
eq "$RC" "2" "(DIAG) an owned bead in an unexecutable status is still refused"
eq "$(wc -l < "$FAKE_CLOSED" | tr -d ' ')" "0" "(DIAG) nothing was written"
has "$OUT" "IS this session's bead for this step" "(DIAG) ownership is reported as proven"
has "$OUT" "status is 'blocked'" "(DIAG) the actual status is named"
hasnt "$OUT" "not this step's bead, or unreadable" "(DIAG) the misleading line is not emitted"

# ...and the same distinction on the --bead hint arm.
: > "$FAKE_CLOSED"
run --step "$STEP" --bead tk-blockd
eq "$RC" "2" "(DIAG-HINT) an owned-but-parked hint does not resolve"
has "$OUT" "but its status is 'blocked'" "(DIAG-HINT) the hint arm names the status too"

# --- 3. --bead hint that verifies --------------------------------------------
reset_beads
run --step "$STEP" --bead tk-9b3d8 --outcome fail
eq "$RC" "0" "(HINT-OK) a verifying --bead is used"
has "$(cat "$FAKE_CLOSED")" "tk-9b3d8 fail" "(HINT-OK) --outcome fail is passed through"

# --- 4. --bead hint that does NOT verify -------------------------------------
reset_beads
run --step "$STEP" --bead tk-dy6cn
eq "$RC" "0" "(HINT-BAD) a non-verifying hint still resolves the right bead"
has "$(cat "$FAKE_CLOSED")" "tk-9b3d8 pass" "(HINT-BAD) closed the discovered bead, not the hint"
hasnt "$(cat "$FAKE_CLOSED")" "tk-dy6cn" "(HINT-BAD) the hinted foreign bead was NOT closed"
has "$OUT" "ignoring the hint" "(HINT-BAD) the ignored hint is reported"

# --- 5. the substring trap ---------------------------------------------------
# jq's inside/contains match substrings: a session named lx-zzk must NOT verify
# as the owner of a bead assigned to ...lx-zzk9.
reset_beads
RC=0
OUT=$(gcenv GC_SESSION_NAME="gc-toolkit__polecat-lx-zzk" bash "$SCRIPT" \
      --step "$STEP" --bead tk-9b3d8 2>&1) || RC=$?
eq "$RC" "2" "(SUBSTRING) a session whose name is a PREFIX of the owner is refused"
eq "$(wc -l < "$FAKE_CLOSED" | tr -d ' ')" "0" "(SUBSTRING) nothing was written"

# --- 6. ambiguity is refused, not guessed ------------------------------------
cat > "$FAKE_BEADS" <<B
tk-9b3d8|$MINE|$STEP|in_progress
tk-twin1|$MINE|$STEP|in_progress
B
: > "$FAKE_CLOSED"
run --step "$STEP"
eq "$RC" "2" "(AMBIG) two in_progress beads for one step is a refusal"
eq "$(wc -l < "$FAKE_CLOSED" | tr -d ' ')" "0" "(AMBIG) nothing was written"
has "$OUT" "tk-9b3d8" "(AMBIG) both candidates are named — tk-9b3d8"
has "$OUT" "tk-twin1" "(AMBIG) both candidates are named — tk-twin1"
# ...but an explicit verified --bead resolves the ambiguity the caller can see.
run --step "$STEP" --bead tk-twin1
eq "$RC" "0" "(AMBIG) an explicit verified --bead breaks the tie"
has "$(cat "$FAKE_CLOSED")" "tk-twin1 pass" "(AMBIG) the named bead is the one closed"

# --- 7. idempotence ----------------------------------------------------------
# A re-run finds its own bead already closed and says so. The session stamp is
# what makes it *its own*: without a molecule this arm cannot tell a re-run
# from the foreign match in 1c, and it refuses instead (asserted there).
cat > "$FAKE_BEADS" <<B
tk-9b3d8|$MINE|$STEP|closed|root-1|lx-zzk9
B
: > "$FAKE_CLOSED"
run --step "$STEP"
eq "$RC" "0" "(IDEMPOTENT) an already-closed step bead exits 0"
eq "$(wc -l < "$FAKE_CLOSED" | tr -d ' ')" "0" "(IDEMPOTENT) it is not re-closed"
has "$OUT" "already closed" "(IDEMPOTENT) says so"

# --- 8. last-resort env path, still verified ---------------------------------
# The store listing finds nothing (bead not listed), but the env id IS this
# session's bead for this step: the old idiom's case, where it was right.
cat > "$FAKE_BEADS" <<B
tk-solo1|$MINE|$STEP|in_progress
B
: > "$FAKE_CLOSED"
RC=0
OUT=$(gcenv GC_SESSION_NAME="$MINE" GC_TRIGGER_BEAD_ID="tk-solo1" \
      FAKE_LIST_BLIND=1 bash "$SCRIPT" --step "$STEP" 2>&1) || RC=$?
eq "$RC" "0" "(ENV-OK) an env id that verifies is honoured"
has "$(cat "$FAKE_CLOSED")" "tk-solo1 pass" "(ENV-OK) it closed the verified bead"

# --- 9. nothing resolvable — FATAL, nothing written --------------------------
cat > "$FAKE_BEADS" <<B
tk-dy6cn|gc-toolkit__polecat-lx-dq84|$OTHER_STEP|in_progress
B
: > "$FAKE_CLOSED"
RC=0
OUT=$(gcenv GC_SESSION_NAME="$MINE" GC_TRIGGER_BEAD_ID="tk-dy6cn" \
      bash "$SCRIPT" --step "$STEP" 2>&1) || RC=$?
eq "$RC" "2" "(UNRESOLVABLE) no own bead anywhere is a refusal"
eq "$(wc -l < "$FAKE_CLOSED" | tr -d ' ')" "0" "(UNRESOLVABLE) nothing was written"
has "$OUT" "cannot identify this session's bead" "(UNRESOLVABLE) says what it could not do"
has "$OUT" "still UNCLOSED and will be re-offered" "(UNRESOLVABLE) names the consequence"

# --- 9b. bd answers with an error OBJECT, not an array -----------------------
# A degraded store must refuse, not crash and not fall through to a guess. The
# unguarded `.[]` on an object is a jq error, and a swallowed jq error is
# indistinguishable from "no bead found".
reset_beads
RC=0
OUT=$(gcenv GC_SESSION_NAME="$MINE" FAKE_LIST_GARBAGE=1 \
      bash "$SCRIPT" --step "$STEP" 2>&1) || RC=$?
eq "$RC" "2" "(GARBAGE) a non-array listing is a refusal, not a crash"
eq "$(wc -l < "$FAKE_CLOSED" | tr -d ' ')" "0" "(GARBAGE) nothing was written"

# --- 9c. a --bead hint naming a bead that does not exist ---------------------
reset_beads
run --step "$STEP" --bead tk-nosuch
eq "$RC" "0" "(NO-SUCH-BEAD) an unknown hint falls through to discovery"
has "$(cat "$FAKE_CLOSED")" "tk-9b3d8 pass" "(NO-SUCH-BEAD) the real bead is still closed"
hasnt "$(cat "$FAKE_CLOSED")" "tk-nosuch" "(NO-SUCH-BEAD) the phantom id was never written to"

# --- 10. control characters in bd's JSON -------------------------------------
reset_beads
RC=0
OUT=$(gcenv GC_SESSION_NAME="$MINE" FAKE_CTRL=1 bash "$SCRIPT" --step "$STEP" 2>&1) || RC=$?
eq "$RC" "0" "(CTRL) a raw control char in the payload does not break resolution"
has "$(cat "$FAKE_CLOSED")" "tk-9b3d8 pass" "(CTRL) the right bead was still closed"

# --- 11. identity via GC_ALIAS ------------------------------------------------
cat > "$FAKE_BEADS" <<B
tk-alias|gc-toolkit/gc-toolkit.nux|$STEP|in_progress
B
: > "$FAKE_CLOSED"
RC=0
OUT=$(gcenv GC_ALIAS="gc-toolkit/gc-toolkit.nux" bash "$SCRIPT" --step "$STEP" 2>&1) || RC=$?
eq "$RC" "0" "(ALIAS) a bead assigned to the alias resolves"
has "$(cat "$FAKE_CLOSED")" "tk-alias pass" "(ALIAS) closed the alias-assigned bead"

# --- 12. no identity at all ---------------------------------------------------
reset_beads
RC=0
OUT=$(gcenv GC_TRIGGER_BEAD_ID="tk-9b3d8" bash "$SCRIPT" --step "$STEP" 2>&1) || RC=$?
eq "$RC" "2" "(NO-IDENTITY) an unidentifiable session refuses to close anything"
eq "$(wc -l < "$FAKE_CLOSED" | tr -d ' ')" "0" "(NO-IDENTITY) nothing was written"
has "$OUT" "cannot prove ownership" "(NO-IDENTITY) says why"

# --- 13. --dry-run writes nothing ---------------------------------------------
reset_beads
run --step "$STEP" --dry-run
eq "$RC" "0" "(DRY) dry run exits 0"
eq "$(wc -l < "$FAKE_CLOSED" | tr -d ' ')" "0" "(DRY) dry run wrote nothing"
has "$OUT" "DRY RUN" "(DRY) says it is a dry run"

# --- 14. a failing update is fatal and says so --------------------------------
reset_beads
echo "tk-9b3d8" > "$FAKE_UPDFAIL"
run --step "$STEP"
eq "$RC" "2" "(WRITE-FAIL) a failed update exits 2"
has "$OUT" "still unclosed and will be re-offered" "(WRITE-FAIL) names the consequence"
has "$OUT" "permission denied (stub)" "(WRITE-FAIL) keeps bd's own diagnostic"

# --- 15. usage errors ---------------------------------------------------------
reset_beads
run --outcome pass
eq "$RC" "2" "(USAGE) --step is required"
has "$OUT" "--step is required" "(USAGE) says which option"

run --step "$STEP" --outcome "bad outcome"
eq "$RC" "2" "(USAGE) an outcome outside [A-Za-z0-9._-] is rejected"

run --step '{{step_id}}'
eq "$RC" "2" "(USAGE) an unsubstituted formula var is rejected by name"
has "$OUT" "unsubstituted" "(USAGE) says the pour did not render it"

run --step "$STEP" --nonsense
eq "$RC" "2" "(USAGE) an unknown argument is rejected"

run --step "$STEP" --root "not a root"
eq "$RC" "2" "(USAGE) a --root outside [A-Za-z0-9._-] is rejected"

run --step "$STEP" --root
eq "$RC" "2" "(USAGE) --root at the end of argv exits 2"

# A value-taking option at the END of argv must exit 2, not spin the parse loop.
RC=0
OUT=$(gcenv GC_SESSION_NAME="$MINE" timeout 10 bash "$SCRIPT" --step 2>&1) || RC=$?
eq "$RC" "2" "(USAGE) a value-taking option at end of argv exits 2 (not a hang)"
# ...and must not swallow the next option as its value.
run --step --outcome pass
eq "$RC" "2" "(USAGE) an option is not accepted as another option's value"

eq "$(wc -l < "$FAKE_CLOSED" | tr -d ' ')" "0" "(USAGE) no usage error wrote anything"

# --- 16. structural: every value-taking arm validates before shifting ---------
# No runtime test can cover an option that does not exist yet, so assert the
# shape.
ARMS=$(grep -c 'require_value "\$@"; ' "$SCRIPT")
SHIFT2=$(grep -c 'shift 2 ;;' "$SCRIPT")
eq "$ARMS" "$SHIFT2" "(STRUCT) every 'shift 2' arm is preceded by require_value on the same line"
[ "$ARMS" -ge 3 ] && ok "(STRUCT) the value-taking arms are present ($ARMS)" \
                  || bad "(STRUCT) expected at least 3 value-taking arms, found $ARMS"

# --- 17. the shipped formulas call it, and no longer close on the raw env id --
ROOT="$(cd "$HERE/../.." && pwd)"
for f in mol-feedback-distiller mol-feedback-miner; do
  FORMULA="$ROOT/formulas/$f.toml"
  if [ ! -f "$FORMULA" ]; then bad "(SHIPPED) $f.toml is missing"; continue; fi
  # Only COMMAND-shaped lines: the §0 prose explains the defect and names the
  # variable on purpose, and a check that cannot tell an explanation from an
  # instruction would forbid documenting the bug it enforces.
  CMDS=$(grep -nE '^[[:space:]]*(gc|\[)' "$FORMULA" | grep -v '^[0-9]*:[[:space:]]*#')
  hasnt "$CMDS" 'gc bd update "\$GC_TRIGGER_BEAD_ID"' "(SHIPPED) $f closes no bead on the raw env id"
  hasnt "$CMDS" 'gc bd update "\$GC_BEAD_ID"' "(SHIPPED) $f closes no bead on \$GC_BEAD_ID"
  has "$(cat "$FORMULA")" 'step-close.sh' "(SHIPPED) $f closes through step-close.sh"
done

echo
echo "step-close.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
