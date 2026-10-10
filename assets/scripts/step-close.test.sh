#!/usr/bin/env bash
# Hermetic test for assets/scripts/step-close.sh.
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
#     does not, so a caller carrying a stale claim id cannot re-create the bug —
#     including a hint that carries this session's assignee and this step's ref
#     but belongs to an earlier molecule, with the molecule supplied and
#     derived, and a hint offered as the only thing naming the molecule that
#     would then scope it — which is no scope at all, and is refused;
#   * the SUBSTRING trap — jq's `inside`/`contains` match substrings, so a
#     session named lx-zzk would "own" lx-zzk9's bead. Exact membership only;
#   * OWNERSHIP BY SESSION STAMP — inside a known molecule an unassigned step
#     bead is ours only when its gc.session_id stamp is empty or this session's;
#     one another session stamped is neither discovered nor accepted as a hint;
#   * the OPEN-STATUS anchor — a graph.v2 step is assigned by the graph, not by
#     the claim, so it executes at status `open` and never reaches in_progress.
#     Resolution must turn on the (assignee, step_ref) pair, not on a status the
#     dispatch never sets. With it: that a SIBLING step, open and pre-assigned
#     to the same session, is still never touched; that in_progress outranks
#     open rather than merging with it; and that ambiguity inside the open tier
#     is refused like any other;
#   * --convoy naming the molecule: the live root poured over the input convoy,
#     taken only when this session holds or held a bead in it, so neither a
#     re-pour over the same convoy nor an alias every session of an agent
#     shares makes the fresh root this shell's; the derivation is the fallback;
#   * the session stamp read from open and in_progress rows first, with closed
#     rows read only when none of those carries it;
#   * the chain-close loop the formula ships, run against the script: a loop
#     that names its molecule issues no gc.session_id read;
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
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-step-close-test.XXXXXX")"
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
# Bead table, one per line:
#   id|assignee|step_ref|status[|root[|session_id[|input_convoy|formula]]]
# Root defaults to root-1 and the session id to absent, so a row that does not
# care about the molecule stays four fields wide. A row with an input convoy is
# a workflow root, as gascity pours one: gc.kind=workflow, gc.input_convoy_id
# and gc.formula_name, and no gc.step_ref or gc.root_bead_id of its own.
# `bd show`   : the single bead, as a one-element array (unknown id -> []).
# `bd list`   : every bead matching --status=, --assignee= and
#               --metadata-field=<key>=<value>. Status takes a comma list, and
#               an unsupported metadata key matches nothing — bd filters on the
#               key it was given, and a stub that ignored it would answer a
#               question the real one never would. With $FAKE_CALLS set, each
#               list call's argv is appended there, one line per call, so a
#               case can assert which reads a close issued.
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
  # $7 input convoy (a workflow root when set)  $8 the root's formula
  local title="step $1" meta
  [ "${FAKE_CTRL:-0}" = "1" ] && title="step $(printf '\001')$1"
  if [ -n "${7:-}" ]; then
    meta=$(printf '"gc.kind":"workflow","gc.formula_contract":"graph.v2","gc.input_convoy_id":"%s","gc.formula_name":"%s"' "$7" "${8:-}")
  else
    meta=$(printf '"gc.step_ref":"%s","gc.root_bead_id":"%s"' "$3" "${5:-root-1}")
  fi
  [ -n "${6:-}" ] && meta="$meta,\"gc.session_id\":\"$6\""
  printf '{"id":"%s","title":"%s","status":"%s","assignee":"%s","metadata":{%s}}' \
    "$1" "$title" "$4" "$2" "$meta"
}

case "$1" in
  show)
    want="$2"
    out=""
    while IFS='|' read -r id assignee step status root sid convoy formula; do
      [ -n "$id" ] || continue
      [ "$id" = "$want" ] || continue
      out=$(emit_one "$id" "$assignee" "$step" "$status" "${root:-root-1}" "${sid:-}" "${convoy:-}" "${formula:-}")
    done < "$FAKE_BEADS"
    if [ -n "$out" ]; then printf '[%s]\n' "$out"; else printf '[]\n'; fi ;;
  list)
    [ -n "${FAKE_CALLS:-}" ] && printf '%s\n' "$*" >> "$FAKE_CALLS"
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
    while IFS='|' read -r id assignee step status root sid convoy formula; do
      [ -n "$id" ] || continue
      root="${root:-root-1}"
      if [ -n "$wstatus" ]; then
        case ",$wstatus," in *",$status,"*) ;; *) continue ;; esac
      fi
      [ -n "$wassignee" ] && [ "$assignee" != "$wassignee" ] && continue
      case "$wkey" in
        "") ;;
        gc.root_bead_id)    [ -z "${convoy:-}" ] && [ "$root" = "$wval" ] || continue ;;
        gc.session_id)      [ "${sid:-}" = "$wval" ] || continue ;;
        gc.step_ref)        [ -z "${convoy:-}" ] && [ "$step" = "$wval" ] || continue ;;
        gc.input_convoy_id) [ -n "${convoy:-}" ] && [ "$convoy" = "$wval" ] || continue ;;
        *) continue ;;
      esac
      obj=$(emit_one "$id" "$assignee" "$step" "$status" "$root" "${sid:-}" "${convoy:-}" "${formula:-}")
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
export FAKE_BEADS="$TMP/beads" FAKE_CLOSED="$TMP/closed" FAKE_UPDFAIL="$TMP/updfail" FAKE_CALLS="$TMP/calls"
: > "$FAKE_CLOSED"; : > "$FAKE_UPDFAIL"; : > "$FAKE_CALLS"

MINE="gc-toolkit__polecat-lx-zzk9"
STEP="mol-feedback-distiller.load-and-gate"
OTHER_STEP="mol-feedback-miner.load-context"

# The fixture shape: my own step bead, plus the bead the stale env variable
# actually named — another session, another molecule, in progress.
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

# This suite is hermetic and deterministic: a fixed fixture, a file-backed `gc`
# stub, and the script. Nothing in a result varies between runs except the
# host, and a saturated parallel run can starve a child of CPU long enough that
# a signal kills it (seen as SIGTERM, exit 143). The suite sets no timeout of
# its own and the script chooses its own exit codes, so a 128+signal code comes
# from outside and is not a verdict the script reached; asserting it as a
# refusal reddens a required check for a reason unrelated to the code. `invoke`
# returns the script's own exit (0, 1, or 2) on the first try and retries only
# a signal death (RC >= 128), on a re-run that reproduces the case exactly. It
# drops the killed attempt's partial write first, so the sink reflects only an
# attempt that ran to the end. A kill that outlasts every try is left as its
# signal code, so a persistent one fails loudly instead of looping or passing.
SCRIPT_TRIES=5
invoke() {  # invoke [VAR=VALUE ...] -- <script args ...>; sets OUT and RC
  local -a envv=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do envv+=("$1"); shift; done
  [ "${1:-}" = "--" ] && shift
  local try=1
  while :; do
    RC=0
    OUT=$(gcenv "${envv[@]}" bash "$SCRIPT" "$@" 2>&1) || RC=$?
    { [ "$RC" -lt 128 ] || [ "$try" -ge "$SCRIPT_TRIES" ]; } && break
    try=$((try + 1))
    : > "$FAKE_CLOSED"
  done
}

run() {
  # run <args...>; sets OUT (stdout+stderr) and RC.
  invoke GC_SESSION_NAME="$MINE" GC_SESSION_ID="lx-zzk9" -- "$@"
}

# --- 1. THE REGRESSION ANCHOR ------------------------------------------------
# Stale GC_TRIGGER_BEAD_ID naming a live foreign bead, own bead present.
reset_beads
invoke GC_SESSION_NAME="$MINE" GC_SESSION_ID="lx-zzk9" GC_TRIGGER_BEAD_ID="tk-dy6cn" \
       -- --step "$STEP" --outcome pass
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
invoke GC_SESSION_NAME="$MINE" GC_TRIGGER_BEAD_ID="tk-step1" \
       -- --step mol-feedback-distiller.judge-and-cluster
eq "$RC" "0" "(SELF-STALE) a stale id naming this session's OWN earlier step still resolves"
has "$(cat "$FAKE_CLOSED")" "tk-step2 pass" "(SELF-STALE) closed the step actually being executed"
hasnt "$(cat "$FAKE_CLOSED")" "tk-step1" "(SELF-STALE) the already-closed step 1 was not re-closed"
has "$OUT" "GC_TRIGGER_BEAD_ID=tk-step1 is not this step's bead" \
    "(SELF-STALE) the mismatch is reported even though both beads are ours"

# --- 1c. THE FOREIGN-MOLECULE ANCHOR -----------------------------------------
# The assignee is not a molecule. A pool agent wears the same one on every run
# it has ever made, so the same gc.step_ref of every earlier molecule matches
# it — and the earlier ones are all closed. Resolution therefore has to turn on
# gc.root_bead_id, with the assignee as corroboration rather than as the key.
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

# (e) A hint carrying this session's assignee and this step's ref, from an
#     earlier molecule. With the molecule known the root decides, and no
#     assignee can vouch for a candidate outside it.
cat > "$FAKE_BEADS" <<B
tk-mine11|$MINE|$FSTEP|open|root-mine|lx-zzk9
tk-old111|$MINE|$FSTEP|closed|root-old|lx-old
B
: > "$FAKE_CLOSED"
run --step "$FSTEP" --root root-mine --bead tk-old111
eq "$RC" "0" "(STALE-HINT-ROOT) a stale same-assignee hint does not stop the close"
has "$(cat "$FAKE_CLOSED")" "tk-mine11 pass" "(STALE-HINT-ROOT) closed the bead in the named molecule"
hasnt "$(cat "$FAKE_CLOSED")" "tk-old111" "(STALE-HINT-ROOT) the earlier molecule's bead was NOT closed"
hasnt "$OUT" "nothing to do" "(STALE-HINT-ROOT) the false-green line is not emitted"
has "$OUT" "belongs to molecule root-old" "(STALE-HINT-ROOT) the hint's own molecule is named"

# (f) The same hint with no --root. The session stamp a claim leaves on the
#     step it hands out names the molecule; a same-assignee hint must not
#     outrank it, or the wrong root scopes every resolution below.
cat > "$FAKE_BEADS" <<B
tk-mine11|$MINE|$FSTEP|open|root-mine|lx-zzk9
tk-old111|$MINE|$FSTEP|closed|root-old|lx-old
B
: > "$FAKE_CLOSED"
run --step "$FSTEP" --bead tk-old111
eq "$RC" "0" "(STALE-HINT-SESSION) the session root outranks a same-assignee hint"
has "$(cat "$FAKE_CLOSED")" "tk-mine11 pass" "(STALE-HINT-SESSION) closed this molecule's bead"
hasnt "$(cat "$FAKE_CLOSED")" "tk-old111" "(STALE-HINT-SESSION) the earlier molecule's bead was NOT closed"
hasnt "$OUT" "nothing to do" "(STALE-HINT-SESSION) the false-green line is not emitted"
has "$OUT" "belongs to molecule root-old" "(STALE-HINT-SESSION) the hint's own molecule is named"

# (g) A hint may not establish the molecule that is then used to vouch for it.
#     Our own bead carries neither an assignee nor a session stamp, so nothing
#     independent names root-mine and the hint is the only candidate; taking
#     root-old from it scopes verify() straight back onto the hint, which
#     reports a foreign closed bead as this chain's own.
cat > "$FAKE_BEADS" <<B
tk-mine11||$FSTEP|open|root-mine|
tk-old111|$MINE|$FSTEP|closed|root-old|
B
: > "$FAKE_CLOSED"
invoke GC_SESSION_NAME="$MINE" -- --step "$FSTEP" --bead tk-old111
eq "$RC" "2" "(HINT-NOT-A-ROOT) a closed hint from another molecule is not a close"
eq "$(wc -l < "$FAKE_CLOSED" | tr -d ' ')" "0" "(HINT-NOT-A-ROOT) nothing was written"
hasnt "$OUT" "nothing to do" "(HINT-NOT-A-ROOT) the false-green line is not emitted"
has "$OUT" "no molecule is established" "(HINT-NOT-A-ROOT) the dropped hint is reported"
has "$OUT" "Pass --root" "(HINT-NOT-A-ROOT) names what would make the hint usable"
has "$OUT" "root-old" "(HINT-NOT-A-ROOT) the molecule the hint belongs to is named"
has "$OUT" "still UNCLOSED" "(HINT-NOT-A-ROOT) names the consequence"

# (h) The wrong-close half of the same hint, with the molecule established
#     independently: being LIVE does not buy a foreign bead past the root gate.
cat > "$FAKE_BEADS" <<B
tk-mine11||$FSTEP|open|root-mine|
tk-old222|$MINE|$FSTEP|in_progress|root-old|
B
: > "$FAKE_CLOSED"
run --step "$FSTEP" --root root-mine --bead tk-old222
eq "$RC" "0" "(LIVE-HINT-ROOT) a live foreign hint does not stop the close"
has "$(cat "$FAKE_CLOSED")" "tk-mine11 pass" "(LIVE-HINT-ROOT) closed the bead in the named molecule"
hasnt "$(cat "$FAKE_CLOSED")" "tk-old222" "(LIVE-HINT-ROOT) the other molecule's live step was NOT closed"
has "$OUT" "belongs to molecule root-old" "(LIVE-HINT-ROOT) the hint's own molecule is named"

# (i) A molecule the assignee alone names authorizes no close while another
#     live bead for this step could equally be ours. Our own bead carries no
#     assignee and no session stamp, and an earlier molecule's bead for the
#     same step is live under our assignee: the derivation reads that one,
#     names its molecule, and the scoped close then lands there while our own
#     step stays open. The assignee cannot tell the two apart, so the answer
#     is a guess and the guess is refused.
cat > "$FAKE_BEADS" <<B
tk-mine11||$FSTEP|open|root-mine|
tk-old222|$MINE|$FSTEP|in_progress|root-old|
B
: > "$FAKE_CLOSED"
invoke GC_SESSION_NAME="$MINE" -- --step "$FSTEP"
eq "$RC" "2" "(ASSIGNEE-ONLY) a molecule named by the assignee alone does not authorize a close"
eq "$(wc -l < "$FAKE_CLOSED" | tr -d ' ')" "0" "(ASSIGNEE-ONLY) nothing was written"
hasnt "$(cat "$FAKE_CLOSED")" "tk-old222" "(ASSIGNEE-ONLY) the other molecule's live step was NOT closed"
has "$OUT" "tk-mine11 (molecule root-mine)" "(ASSIGNEE-ONLY) the bead that could equally be ours is named"
has "$OUT" "Pass --root" "(ASSIGNEE-ONLY) names what would settle it"
has "$OUT" "still UNCLOSED" "(ASSIGNEE-ONLY) names the consequence"

# (j) ...and the two independent sources both settle it, on the same store.
: > "$FAKE_CLOSED"
invoke GC_SESSION_NAME="$MINE" -- --step "$FSTEP" --root root-mine
eq "$RC" "0" "(ASSIGNEE-ONLY) --root closes the bead in the named molecule"
has "$(cat "$FAKE_CLOSED")" "tk-mine11 pass" "(ASSIGNEE-ONLY) it is our own bead that closes"
hasnt "$(cat "$FAKE_CLOSED")" "tk-old222" "(ASSIGNEE-ONLY) the earlier molecule stays untouched"

cat > "$FAKE_BEADS" <<B
tk-mine11||$FSTEP|open|root-mine|lx-zzk9
tk-old222|$MINE|$FSTEP|in_progress|root-old|
B
: > "$FAKE_CLOSED"
run --step "$FSTEP"
eq "$RC" "0" "(ASSIGNEE-ONLY) the gc.session_id stamp settles it too"
has "$(cat "$FAKE_CLOSED")" "tk-mine11 pass" "(ASSIGNEE-ONLY) the stamped molecule is the one closed in"

# (k) The refusal is scoped to the doubt, not to the derivation. With no live
#     bead for this step outside the derived molecule there is nothing this
#     shell could be running instead, and the close proceeds on the assignee as
#     it always has.
cat > "$FAKE_BEADS" <<B
tk-mine11|$MINE|$FSTEP|in_progress|root-mine|
tk-oldsib|$MINE|mol-polecat-work.implement|open|root-old|
B
: > "$FAKE_CLOSED"
invoke GC_SESSION_NAME="$MINE" -- --step "$FSTEP"
eq "$RC" "0" "(ASSIGNEE-ONLY) an assignee-derived molecule with no rival still closes"
has "$(cat "$FAKE_CLOSED")" "tk-mine11 pass" "(ASSIGNEE-ONLY) closed the bead for this step"

# (l) A live same-step bead another session holds is that session's, not a
#     candidate for ours: neither its assignee nor the stamp a claim left on it
#     can be this shell, so it must not stall a close.
cat > "$FAKE_BEADS" <<B
tk-mine11|$MINE|$FSTEP|in_progress|root-mine|
tk-their1|gc-toolkit__polecat-lx-other|$FSTEP|open|root-thm|
tk-their2||$FSTEP|open|root-thn|lx-other
B
: > "$FAKE_CLOSED"
invoke GC_SESSION_NAME="$MINE" -- --step "$FSTEP"
eq "$RC" "0" "(ASSIGNEE-ONLY) another session's live step is not a rival for ours"
has "$(cat "$FAKE_CLOSED")" "tk-mine11 pass" "(ASSIGNEE-ONLY) our own bead still closes"
hasnt "$(cat "$FAKE_CLOSED")" "tk-their" "(ASSIGNEE-ONLY) nothing of theirs was written"

# (m) The false-green half: reporting another molecule's closed bead as done is
#     an acting verdict, so it takes the same gate.
cat > "$FAKE_BEADS" <<B
tk-mine11||$FSTEP|open|root-mine|
tk-oldsib|$MINE|mol-polecat-work.implement|in_progress|root-old|
tk-old111|$MINE|$FSTEP|closed|root-old|
B
: > "$FAKE_CLOSED"
invoke GC_SESSION_NAME="$MINE" -- --step "$FSTEP"
eq "$RC" "2" "(ASSIGNEE-ONLY) a closed bead in an assignee-derived molecule is not a pass"
eq "$(wc -l < "$FAKE_CLOSED" | tr -d ' ')" "0" "(ASSIGNEE-ONLY) nothing was written"
hasnt "$OUT" "nothing to do" "(ASSIGNEE-ONLY) the false-green line is not emitted"
has "$OUT" "tk-mine11 (molecule root-mine)" "(ASSIGNEE-ONLY) the bead that could be ours is named"

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

# (f) The unassigned half of the same condition. The finalizer strips the
# assignee at a terminal exit, so a blank assignee alone cannot tell our own
# stripped bead from a live one a second worker holds — the gc.session_id stamp
# a claim leaves is what tells them apart. A bead our molecule holds under
# another session's stamp is that session's, so the root-scoped discovery must
# not close it even with --root naming our molecule.
cat > "$FAKE_BEADS" <<B
tk-frgn11||$FSTEP|open|root-mine|lx-other
B
: > "$FAKE_CLOSED"
run --step "$FSTEP" --root root-mine
eq "$RC" "2" "(FOREIGN-STAMP) an unassigned bead our molecule holds under another session's stamp is not closed"
eq "$(wc -l < "$FAKE_CLOSED" | tr -d ' ')" "0" "(FOREIGN-STAMP) nothing was written"
hasnt "$(cat "$FAKE_CLOSED")" "tk-frgn11" "(FOREIGN-STAMP) the other session's bead was NOT closed"

# (g) The hint path takes the same gate: a --bead naming that bead does not
# verify as ours, so it is reported and dropped rather than obeyed.
: > "$FAKE_CLOSED"
run --step "$FSTEP" --root root-mine --bead tk-frgn11
eq "$RC" "2" "(FOREIGN-STAMP-HINT) a hint on another session's unassigned bead does not verify"
eq "$(wc -l < "$FAKE_CLOSED" | tr -d ' ')" "0" "(FOREIGN-STAMP-HINT) nothing was written"
hasnt "$(cat "$FAKE_CLOSED")" "tk-frgn11" "(FOREIGN-STAMP-HINT) the hinted foreign-stamp bead was NOT closed"

# (h) The positive control on the same shape and the same --root: the stamp
# naming THIS session is our own finalizer-stripped bead, and it still closes.
# The gate rejects another session's stamp, not every unassigned bead.
cat > "$FAKE_BEADS" <<B
tk-mine11||$FSTEP|open|root-mine|lx-zzk9
B
: > "$FAKE_CLOSED"
run --step "$FSTEP" --root root-mine
eq "$RC" "0" "(FOREIGN-STAMP) our own stamp on an unassigned bead still closes"
has "$(cat "$FAKE_CLOSED")" "tk-mine11 pass" "(FOREIGN-STAMP) closed our own stripped bead"

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

# --- 1f. --convoy names the molecule -----------------------------------------
# A formula step passes `--convoy {{convoy_id}}`, and the live workflow root
# poured over that convoy is its molecule. The refusal it answers was live: a
# step claimed with `gc bd update --claim` carries no gc.session_id stamp, so
# only the assignee names its molecule, and every queued molecule's unassigned
# bead for the same step is a rival the guard refuses over.
FR="mol-first-reaction.advance-and-drain"
convoy_store() {
  cat > "$FAKE_BEADS" <<B
root-mine|||in_progress|||conv-mine|mol-first-reaction
root-q1|||open|||conv-q1|mol-first-reaction
root-q2|||open|||conv-q2|mol-first-reaction
tk-own11|$MINE|$FR|in_progress|root-mine|
tk-q1aaa||$FR|open|root-q1|
tk-q2aaa||$FR|open|root-q2|
B
  : > "$FAKE_CLOSED"; : > "$FAKE_CALLS"
}
convoy_store
run --step "$FR"
eq "$RC" "2" "(CONVOY) with nothing naming the molecule, the queued rivals refuse the close"
eq "$(wc -l < "$FAKE_CLOSED" | tr -d ' ')" "0" "(CONVOY) …and nothing is written"
has "$OUT" "gc.root_bead_id on the step bead" "(CONVOY) the refusal points at the step bead's own root"
hasnt "$OUT" "gc hook --claim --json" "(CONVOY) …not at a claim, which takes new work on a pool worker"

convoy_store
run --step "$FR" --convoy conv-mine
eq "$RC" "0" "(CONVOY) --convoy names the molecule, so the close proceeds past the queued rivals"
has "$(cat "$FAKE_CLOSED")" "tk-own11 pass" "(CONVOY) it closes this molecule's bead"
hasnt "$(cat "$FAKE_CLOSED")" "tk-q" "(CONVOY) no queued molecule's bead is touched"
hasnt "$(cat "$FAKE_CALLS")" "gc.session_id" "(CONVOY) no gc.session_id read is issued"
eq "$(wc -l < "$FAKE_CALLS" | tr -d ' ')" "2" "(CONVOY) two reads in all: the convoy's root, then the molecule's live rows"

# (b) A forced re-pour over the same convoy closes the old root and pours a
#     fresh one. A shell still running the old molecule resolves the fresh
#     root from the convoy, and that molecule's steps are open and unassigned,
#     exactly as an unclaimed successor of its own would be. This session holds
#     nothing in it, so the convoy's root is not taken, and the derivation finds
#     the molecule this shell actually ran.
cat > "$FAKE_BEADS" <<B
root-old|||closed|||conv-1|mol-polecat-work
root-new|||open|||conv-1|mol-polecat-work
tk-oldlc|$MINE|$FSTEP|closed|root-old|lx-zzk9
tk-newlc||$FSTEP|open|root-new|
B
: > "$FAKE_CLOSED"
run --step "$FSTEP" --convoy conv-1
eq "$RC" "0" "(CONVOY-REPOURED) a shell whose molecule was replaced exits clean"
eq "$(wc -l < "$FAKE_CLOSED" | tr -d ' ')" "0" "(CONVOY-REPOURED) the fresh molecule's step is NOT closed"
has "$OUT" "re-pour" "(CONVOY-REPOURED) says why the convoy's root was not taken"
has "$OUT" "tk-oldlc ($FSTEP) is already closed" "(CONVOY-REPOURED) the replaced molecule's own step reads as done"

# (c) A convoy with no live root, as after the finalizer closed it, falls back
#     to the derivation rather than refusing.
cat > "$FAKE_BEADS" <<B
tk-mine11||$FSTEP|open|root-mine|lx-zzk9
B
: > "$FAKE_CLOSED"
run --step "$FSTEP" --convoy conv-none
eq "$RC" "0" "(CONVOY-NONE) a convoy with no live root falls back to the derivation"
has "$(cat "$FAKE_CLOSED")" "tk-mine11 pass" "(CONVOY-NONE) …which closes this session's stamped bead"
has "$OUT" "names no single live workflow root" "(CONVOY-NONE) the fallback is reported"

# (d) Several live roots over one convoy: the one of this step's formula is
#     taken when it stands alone, and a tie is no answer at all.
cat > "$FAKE_BEADS" <<B
root-pw|||in_progress|||conv-2|mol-polecat-work
root-rv|||in_progress|||conv-2|mol-review
tk-mine22|$MINE|$FSTEP|in_progress|root-pw|
tk-rv1111|$MINE|mol-review.review|open|root-rv|
tk-q3aaaa||$FSTEP|open|root-q3|
B
: > "$FAKE_CLOSED"
run --step "$FSTEP" --convoy conv-2
eq "$RC" "0" "(CONVOY-FORMULA) the root of this step's formula is taken among several"
has "$(cat "$FAKE_CLOSED")" "tk-mine22 pass" "(CONVOY-FORMULA) it closes the bead in that molecule"
hasnt "$(cat "$FAKE_CLOSED")" "tk-q3aaaa" "(CONVOY-FORMULA) the queued rival is untouched"

cat > "$FAKE_BEADS" <<B
root-a|||in_progress|||conv-3|mol-polecat-work
root-b|||in_progress|||conv-3|mol-polecat-work
tk-mine33||$FSTEP|open|root-a|lx-zzk9
B
: > "$FAKE_CLOSED"
run --step "$FSTEP" --convoy conv-3
has "$OUT" "names no single live workflow root" "(CONVOY-TIE) two roots of one formula over the convoy are no answer"
has "$(cat "$FAKE_CLOSED")" "tk-mine33 pass" "(CONVOY-TIE) …and the derivation still closes this session's bead"

# (e) The inline chain: this session claimed load-context and has closed it,
#     and the successor it is closing now was never claimed, so it carries no
#     assignee and no stamp. The session also ran an earlier molecule of the
#     same formula, so its stamp names two roots and the derivation cannot
#     settle it. The closed rows of the convoy's molecule still show this
#     session's hand, and the close proceeds.
cat > "$FAKE_BEADS" <<B
root-mine|||in_progress|||conv-4|mol-polecat-work
tk-lc111|$MINE|mol-polecat-work.load-context|closed|root-mine|lx-zzk9
tk-ws111||mol-polecat-work.workspace-setup|open|root-mine|
tk-lc222|$MINE|mol-polecat-work.load-context|closed|root-old|lx-zzk9
tk-ws222|$MINE|mol-polecat-work.workspace-setup|closed|root-old|lx-zzk9
B
: > "$FAKE_CLOSED"
run --step mol-polecat-work.workspace-setup
eq "$RC" "2" "(CONVOY-INLINE) with the stamp naming two molecules, the derivation refuses"
eq "$(wc -l < "$FAKE_CLOSED" | tr -d ' ')" "0" "(CONVOY-INLINE) …and writes nothing"
: > "$FAKE_CLOSED"; : > "$FAKE_CALLS"
run --step mol-polecat-work.workspace-setup --convoy conv-4
eq "$RC" "0" "(CONVOY-INLINE) --convoy closes the unclaimed successor in this session's molecule"
has "$(cat "$FAKE_CLOSED")" "tk-ws111 pass" "(CONVOY-INLINE) it is this molecule's bead that closes"
hasnt "$(cat "$FAKE_CLOSED")" "tk-ws222" "(CONVOY-INLINE) the earlier molecule is untouched"
hasnt "$(cat "$FAKE_CALLS")" "gc.session_id" "(CONVOY-INLINE) no gc.session_id read is issued"

# (f) An agent alias is shared by every session of that agent. When another
#     session of the same agent has claimed the fresh molecule's step, that step
#     carries this shell's alias as its assignee, but its stamp names the other
#     session, so the convoy's root is still not taken and their step is not
#     closed.
cat > "$FAKE_BEADS" <<B
root-old|||closed|||conv-5|mol-review
root-new|||open|||conv-5|mol-review
tk-oldrv|gc-toolkit/gc-toolkit.nux|mol-review.review|closed|root-old|lx-zzk9
tk-newrv|gc-toolkit/gc-toolkit.nux|mol-review.review|in_progress|root-new|lx-other
B
: > "$FAKE_CLOSED"
invoke GC_SESSION_NAME="$MINE" GC_SESSION_ID="lx-zzk9" GC_ALIAS="gc-toolkit/gc-toolkit.nux" \
       -- --step mol-review.review --convoy conv-5
eq "$RC" "0" "(CONVOY-ALIAS) a shell whose molecule was replaced exits clean"
eq "$(wc -l < "$FAKE_CLOSED" | tr -d ' ')" "0" "(CONVOY-ALIAS) the other session's step under the shared alias is NOT closed"
has "$OUT" "re-pour" "(CONVOY-ALIAS) the shared alias does not make the fresh root this shell's"
has "$OUT" "tk-oldrv (mol-review.review) is already closed" "(CONVOY-ALIAS) this shell's own step reads as done"

# --- 1g. the session stamp is read from live rows first -----------------------
# The step this shell is executing is open or in_progress, and a read of those
# rows stays cheap where one that includes closed rows scans the store. One live
# root answers, even when closed rows name an earlier molecule this session
# finished; before, that pair was ambiguous and a stripped bead was refused.
cat > "$FAKE_BEADS" <<B
tk-mine11||$FSTEP|open|root-mine|lx-zzk9
tk-old111|$MINE|$FSTEP|closed|root-old|lx-zzk9
B
: > "$FAKE_CLOSED"; : > "$FAKE_CALLS"
run --step "$FSTEP"
eq "$RC" "0" "(LIVE-FIRST) a live stamped bead names the molecule past an earlier closed one"
has "$(cat "$FAKE_CLOSED")" "tk-mine11 pass" "(LIVE-FIRST) it closes this molecule's bead"
hasnt "$(cat "$FAKE_CLOSED")" "tk-old111" "(LIVE-FIRST) the earlier molecule is untouched"
has "$(cat "$FAKE_CALLS")" "gc.session_id=lx-zzk9 --status=open,in_progress " "(LIVE-FIRST) the stamp is read from open and in_progress rows"
hasnt "$(cat "$FAKE_CALLS")" "blocked,closed" "(LIVE-FIRST) …and closed rows are never read for it"

# A re-run over a closed chain finds no live stamp, and only then reads closed rows.
cat > "$FAKE_BEADS" <<B
tk-9b3d8|$MINE|$STEP|closed|root-1|lx-zzk9
B
: > "$FAKE_CLOSED"; : > "$FAKE_CALLS"
run --step "$STEP"
eq "$RC" "0" "(LIVE-EMPTY) a re-run over a closed chain still resolves"
has "$(cat "$FAKE_CALLS")" "gc.session_id=lx-zzk9 --status=blocked,closed " "(LIVE-EMPTY) the closed rows are read once no live row carries the stamp"

# Two live roots under the stamp are no answer, and reading closed rows could
# not make one, so they are not read.
cat > "$FAKE_BEADS" <<B
tk-mine11|$MINE|$FSTEP|open|root-mine|lx-zzk9
tk-oth111||mol-polecat-work.implement|in_progress|root-other|lx-zzk9
B
: > "$FAKE_CLOSED"; : > "$FAKE_CALLS"
run --step "$FSTEP"
eq "$RC" "0" "(LIVE-AMBIG) the assignee still settles a step the live stamp cannot"
has "$(cat "$FAKE_CLOSED")" "tk-mine11 pass" "(LIVE-AMBIG) it closes this session's bead"
hasnt "$(cat "$FAKE_CALLS")" "blocked,closed" "(LIVE-AMBIG) two live roots skip the closed read"

# --- 2. resolution with no env id at all -------------------------------------
reset_beads
run --step "$STEP"
eq "$RC" "0" "(NO-ENV) resolves with GC_TRIGGER_BEAD_ID unset"
has "$(cat "$FAKE_CLOSED")" "tk-9b3d8 pass" "(NO-ENV) closed by (assignee, step_ref)"
has "$OUT" "resolved by (molecule root-1, step_ref)" "(NO-ENV) reports how it resolved"

# --- 2b. THE OPEN-STATUS REGRESSION ANCHOR -----------------------------------
# A graph.v2 step bead is assigned to its session by the GRAPH, not by the
# claim, so `gc hook --claim` finds the assignee already set and advances
# nothing: the step is executed at status `open` and never reaches in_progress.
# The fixture shape: a step bead that goes open/unassigned -> open/assigned ->
# closed, with no in_progress state anywhere in its history. Resolution must
# not turn on a status the dispatch never sets; the ownership proof is the
# (assignee, step_ref) pair, and it holds here.
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
invoke GC_SESSION_NAME="$MINE" GC_TRIGGER_BEAD_ID="tk-solo2" FAKE_LIST_BLIND=1 \
       -- --step "$STEP"
eq "$RC" "0" "(OPEN-ENV) the last-resort env path accepts a verified open bead"
has "$(cat "$FAKE_CLOSED")" "tk-solo2 pass" "(OPEN-ENV) it closed the verified bead"

# --- 2g. "your bead, unexpected status" is not reported as "not your bead" ---
# The diagnostic that sent a reader hunting a stale-environment defect after
# what was really a status mismatch. `blocked` is owned by this session for
# this step and is still not closed — but the refusal must say so, because
# "not this step's bead" is a different problem with a different fix.
cat > "$FAKE_BEADS" <<B
tk-blockd|$MINE|$STEP|blocked
B
: > "$FAKE_CLOSED"
invoke GC_SESSION_NAME="$MINE" GC_TRIGGER_BEAD_ID="tk-blockd" \
       -- --step "$STEP"
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
invoke GC_SESSION_NAME="gc-toolkit__polecat-lx-zzk" \
       -- --step "$STEP" --bead tk-9b3d8
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
invoke GC_SESSION_NAME="$MINE" GC_TRIGGER_BEAD_ID="tk-solo1" FAKE_LIST_BLIND=1 \
       -- --step "$STEP"
eq "$RC" "0" "(ENV-OK) an env id that verifies is honoured"
has "$(cat "$FAKE_CLOSED")" "tk-solo1 pass" "(ENV-OK) it closed the verified bead"

# --- 9. nothing resolvable — FATAL, nothing written --------------------------
cat > "$FAKE_BEADS" <<B
tk-dy6cn|gc-toolkit__polecat-lx-dq84|$OTHER_STEP|in_progress
B
: > "$FAKE_CLOSED"
invoke GC_SESSION_NAME="$MINE" GC_TRIGGER_BEAD_ID="tk-dy6cn" \
       -- --step "$STEP"
eq "$RC" "2" "(UNRESOLVABLE) no own bead anywhere is a refusal"
eq "$(wc -l < "$FAKE_CLOSED" | tr -d ' ')" "0" "(UNRESOLVABLE) nothing was written"
has "$OUT" "cannot identify this session's bead" "(UNRESOLVABLE) says what it could not do"
has "$OUT" "still UNCLOSED and will be re-offered" "(UNRESOLVABLE) names the consequence"

# --- 9b. bd answers with an error OBJECT, not an array -----------------------
# A degraded store must refuse, not crash and not fall through to a guess. The
# unguarded `.[]` on an object is a jq error, and a swallowed jq error is
# indistinguishable from "no bead found".
reset_beads
invoke GC_SESSION_NAME="$MINE" FAKE_LIST_GARBAGE=1 \
       -- --step "$STEP"
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
invoke GC_SESSION_NAME="$MINE" FAKE_CTRL=1 -- --step "$STEP"
eq "$RC" "0" "(CTRL) a raw control char in the payload does not break resolution"
has "$(cat "$FAKE_CLOSED")" "tk-9b3d8 pass" "(CTRL) the right bead was still closed"

# --- 11. identity via GC_ALIAS ------------------------------------------------
cat > "$FAKE_BEADS" <<B
tk-alias|gc-toolkit/gc-toolkit.nux|$STEP|in_progress
B
: > "$FAKE_CLOSED"
invoke GC_ALIAS="gc-toolkit/gc-toolkit.nux" -- --step "$STEP"
eq "$RC" "0" "(ALIAS) a bead assigned to the alias resolves"
has "$(cat "$FAKE_CLOSED")" "tk-alias pass" "(ALIAS) closed the alias-assigned bead"

# --- 12. no identity at all ---------------------------------------------------
reset_beads
invoke GC_TRIGGER_BEAD_ID="tk-9b3d8" -- --step "$STEP"
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

# Every step-close call in a formula that has an input convoy names its
# molecule with it. A formula without one has nothing to pass, and its closes
# rest on the derivation.
NAMED=0
for FORMULA in "$ROOT"/formulas/*.toml; do
  grep -q '{{convoy_id}}' "$FORMULA" || continue
  SC_CALLS=$(grep -nE 'SC(:\?[^}]*\})?" --step ' "$FORMULA")
  [ -n "$SC_CALLS" ] || continue
  NAMED=$((NAMED + 1))
  UNNAMED=$(printf '%s\n' "$SC_CALLS" | grep -v -- '--convoy {{convoy_id}}')
  if [ -z "$UNNAMED" ]; then
    ok "(SHIPPED) every step-close call in $(basename "$FORMULA") passes --convoy {{convoy_id}}"
  else
    bad "(SHIPPED) $(basename "$FORMULA") calls step-close without naming its molecule: $UNNAMED"
  fi
done
[ "$NAMED" -ge 2 ] && ok "(SHIPPED) the convoy check reached the formulas that close steps ($NAMED)" \
                   || bad "(SHIPPED) expected formulas calling step-close with an input convoy, found $NAMED"

# --- 18. a step loop that names its molecule never scans gc.session_id --------
# The terminal chain-close runs step-close once per step. Deriving the molecule
# on each call read the session stamp over closed rows every time, about 6 to 9
# seconds a call on a loaded store. The loop the formula ships is extracted and
# run against the real script: every step resolves inside the named molecule,
# and no read keys on gc.session_id.
LOOP_SRC=$(awk '/^# >>> submit-chain-close$/ {f = 1; next} /^# <<< submit-chain-close$/ {f = 0} f' \
  "$ROOT/formulas/mol-polecat-work.toml")
if [ -n "$LOOP_SRC" ]; then ok "(LOOP) the submit-chain-close loop is extracted"; else bad "(LOOP) submit-chain-close markers missing from mol-polecat-work.toml"; fi
loop_store() {
  cat > "$FAKE_BEADS" <<B
root-loop|||in_progress|||conv-loop|mol-polecat-work
tk-s1aaa|gc-toolkit__polecat-lx-a|mol-polecat-work.load-context|closed|root-loop|lx-a
tk-s2aaa||mol-polecat-work.workspace-setup|closed|root-loop|
tk-s3aaa||mol-polecat-work.preflight-tests|closed|root-loop|
tk-s4aaa||mol-polecat-work.implement|closed|root-loop|
tk-s5aaa|$MINE|mol-polecat-work.submit-and-exit|in_progress|root-loop|lx-zzk9
tk-wfaaa||mol-polecat-work.workflow-finalize|open|root-loop|
tk-q1aaa||mol-polecat-work.submit-and-exit|open|root-q1|
tk-q2aaa||mol-polecat-work.load-context|open|root-q2|
B
  : > "$FAKE_CLOSED"; : > "$FAKE_CALLS"
}
run_loop() { # <loop file>; sets OUT and RC
  RC=0
  OUT=$(gcenv GC_SESSION_NAME="$MINE" GC_SESSION_ID="lx-zzk9" GC_PACK_DIR="$ROOT" GC_RIG_ROOT="" GC_CITY_PATH="" \
    bash "$1" 2>&1) || RC=$?
}

printf '%s\n' "$LOOP_SRC" | sed 's/{{convoy_id}}/conv-loop/g' > "$TMP/loop-convoy.sh"
loop_store
run_loop "$TMP/loop-convoy.sh"
eq "$RC" "0" "(LOOP) the shipped loop runs clean"
eq "$(cat "$FAKE_CLOSED")" "tk-s5aaa pass" "(LOOP) it closes this session's step and nothing else"
eq "$(grep -c 'is already closed' <<< "$OUT")" "4" "(LOOP) the four steps other sessions closed read as done"
hasnt "$(cat "$FAKE_CALLS")" "gc.session_id" "(LOOP) a loop that names its molecule issues no gc.session_id read"

# The same loop given --root, as a caller holding the root passes it.
printf '%s\n' "$LOOP_SRC" | sed 's/--convoy {{convoy_id}}/--root root-loop/' > "$TMP/loop-root.sh"
loop_store
run_loop "$TMP/loop-root.sh"
eq "$(cat "$FAKE_CLOSED")" "tk-s5aaa pass" "(LOOP-ROOT) a loop given --root closes this session's step"
hasnt "$(cat "$FAKE_CALLS")" "gc.session_id" "(LOOP-ROOT) a loop given --root issues no gc.session_id read"

# CONTROL: the loop with the molecule's name removed derives it on every call,
# which is the read the two runs above are asserted not to issue.
printf '%s\n' "$LOOP_SRC" | sed 's/ --convoy {{convoy_id}}//' > "$TMP/loop-bare.sh"
loop_store
run_loop "$TMP/loop-bare.sh"
has "$(cat "$FAKE_CALLS")" "gc.session_id=lx-zzk9" "(LOOP-CONTROL) without the molecule's name, every call reads the session stamp"

echo
echo "step-close.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
