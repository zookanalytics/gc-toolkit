#!/usr/bin/env bash
# Hermetic test for gc-visit-open.sh — the operator-origin visit intake
# (tk-4ojka). Runs the REAL script (via `sh`, as shipped) with `gc`,
# `gc-helm.sh` and `gc-proactive.sh` stubbed on PATH — no live city, Dolt,
# network, or sessions.
#
# What the cases are guarding, and why each one was worth a test:
#
#   (DIRECT)    --no-react files the visit NOW, through gc-helm.sh open —
#               the script must never hand-roll a gate-visit block of its own.
#   (SINGLE)    the react path files NO visit: mol-first-reaction's
#               advance-and-drain step files it, and a second one would split
#               the conversation into two sittings of the same subject.
#   (SHED)      the whole reason the fallback exists. `gc sling` is
#               fire-and-forget and returns 0 whether or not anything will
#               ever pick the bead up, so an unguarded react path leaves the
#               topic routed, unclaimed, and WITHOUT a visit — filed-looking
#               and silently forgotten. Both clamps that cause it (auto-spawn
#               disabled — the DEFAULT — and the city session cap) are asked
#               about up front, and a "no" must divert to the direct path.
#   (RECOVER)   a react path that fails outright still ends in a visit rather
#               than a subject bead nobody is coming to.
#   (RIG)       the default rig is FIXED (gc-toolkit), never inferred from
#               cwd: this is fired from wherever the operator is sitting, and
#               a silently varying destination is the worst failure mode an
#               intake path can have. An unknown --rig files nothing.
#   (SUBJECT)   an existing bead is its own subject — no second bead is
#               minted — and a contradictory --rig/--type is refused rather
#               than ignored.
#   (SHAPE)     "dolt-latency" is a topic, "tk-abc12" is a bead id, and the
#               difference is the RIG PREFIX, not the hyphen. A prefix-shaped
#               string no ledger answers for must not become a bead literally
#               titled "tk-abc12".
#   (TYPE)      a question becomes a decision bead; --type overrides.
#   (FAILCLOSE) a subject that could not be created files no visit, and a
#               missing argument creates nothing at all.
#   (PARAGRAPH) the topic key exists so the operator can type a PARAGRAPH, and
#               the popup is sized multi-line to invite one — so a paragraph is
#               the DESIGNED input, not an edge case. Passing it through as the
#               title made it the one input guaranteed to fail: `bd create`
#               refuses a title over 500 bytes, so a 579-character topic filed
#               nothing at all (tk-wp50s, hit live). The title is a derived
#               label; the BODY is where the operator's words have to survive.
#   (WHY)       a create refused for a stated reason must relay that reason.
#               Keeping only .id off the response reported every refusal as
#               "bd create returned no id", which sent the operator looking for
#               a broken ledger instead of an over-long title.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/gc-visit-open.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { grep -qF -- "$2" <<< "$1" && ok "$3" || bad "$3 (in: $1)"; }
hasnt() { grep -qF -- "$2" <<< "$1" && bad "$3 (in: $1)" || ok "$3"; }
# The ledger's title limit is counted in BYTES (a 600-character CJK title is
# refused as "got 1800"), while bash's ${#var} counts CHARACTERS under a UTF-8
# locale. Measuring the wrong unit would let a 500-character/1500-byte title
# pass an assertion the ledger would reject, so measure bytes explicitly.
bytes() { printf '%s' "$1" | wc -c | tr -d ' '; }

[ -f "$SCRIPT" ] && ok "gc-visit-open.sh present" || { bad "gc-visit-open.sh missing at $SCRIPT"; exit 1; }

mkdir -p "$TMP/bin" "$TMP/rigs/gc-toolkit/.beads" "$TMP/rigs/gascity/.beads"

# --- gc stub -----------------------------------------------------------------
# Two rigs, so "which ledger" is a real question the test can check. Every
# mutating call is appended to $FAKE_CALLS so "nothing was created" is asserted
# against the actual argv, not against exit status alone.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "rig list")
    jq -n --arg t "$FAKE_RIGS/gc-toolkit" --arg g "$FAKE_RIGS/gascity" \
      '{rigs:[{name:"gc-toolkit", path:$t, prefix:"tk"},
              {name:"gascity",    path:$g, prefix:"gc"}]}' ;;
  "bd create")
    printf 'bd create %s\n' "$*" >> "$FAKE_CALLS"
    # The argv line above flattens the title and body into one blob. Record
    # each as its own exact value too: the title is precisely what tk-wp50s is
    # about, and "the paragraph survived verbatim" is an assertion about the
    # body alone.
    prev=""; title=""
    for a in "$@"; do
      case "$prev" in
        --title) title="$a"; printf '%s' "$a" > "$FAKE_TITLE" ;;
        -d)      printf '%s' "$a" > "$FAKE_BODY" ;;
      esac
      prev="$a"
    done
    # $FAKE_CREATE_ERROR is the .error the ledger states; the default keeps the
    # original stub's payload for the cases that only care that it failed.
    if [ -n "${FAKE_CREATE_FAIL:-}" ]; then
      jq -n --arg e "${FAKE_CREATE_ERROR:-nope}" '{error:$e}'; exit 1
    fi
    # A failure that states nothing at all — the caller still owes the operator
    # a message, so the fallback has to carry one.
    if [ -n "${FAKE_CREATE_SILENT:-}" ]; then exit 1; fi
    # THE TITLE CAP, because a stub that accepts what the tool refuses hides the
    # bug behind a green suite: with the cap left out, "an over-cap paragraph
    # files" passes against the very script that could not file one. Mirrored
    # from the live tool — refused over 500 BYTES (a 600-character CJK title is
    # refused as "got 1800"), exit 1, reason in .error, and no id.
    tbytes=$(printf '%s' "$title" | wc -c | tr -d ' ')
    if [ "$tbytes" -gt 500 ]; then
      jq -n --arg e "validation failed: validation failed for issue : title must be 500 characters or less (got $tbytes)" '{error:$e}'
      exit 1
    fi
    jq -n '{id:"tk-newsub"}' ;;
esac
exit 0
GC

# --- gc-helm.sh stub ----------------------------------------------------------
# Records the verb and argv; $FAKE_HELM_RC drives the failure cases.
cat > "$TMP/bin/gc-helm.sh" <<'HELM'
#!/usr/bin/env bash
printf 'helm %s\n' "$*" >> "$FAKE_CALLS"
exit "${FAKE_HELM_RC:-0}"
HELM

# --- gc-proactive.sh stub -----------------------------------------------------
# $FAKE_DELIVERABLE picks which clamp answers: yes / disabled / cap.
cat > "$TMP/bin/gc-proactive.sh" <<'PRO'
#!/usr/bin/env bash
printf 'proactive %s\n' "$*" >> "$FAKE_CALLS"
case "${FAKE_DELIVERABLE:-yes}" in
  yes)      echo "yes: proactive enabled and under the city cap (3/20)"; exit 0 ;;
  disabled) echo "no: proactive auto-spawn is disabled (GC_PROACTIVE_ENABLED unset or not truthy) — a slung reaction would sit routed and unclaimed"; exit 1 ;;
  cap)      echo "no: city at session cap (20/20) — proactive sheds first under session pressure"; exit 1 ;;
esac
PRO

chmod +x "$TMP/bin/gc" "$TMP/bin/gc-helm.sh" "$TMP/bin/gc-proactive.sh"

export PATH="$TMP/bin:$PATH"
export FAKE_CALLS="$TMP/calls"
export FAKE_TITLE="$TMP/title"
export FAKE_BODY="$TMP/body"
export FAKE_RIGS="$TMP/rigs"
export GC_HELM_TOOL="$TMP/bin/gc-helm.sh"
export GC_PROACTIVE_TOOL="$TMP/bin/gc-proactive.sh"
export TMPDIR="$TMP"

# run <deliverable> [args...] -> sets RC/OUT/ERR/CALLS
run() {
    : > "$FAKE_CALLS"; : > "$FAKE_TITLE"; : > "$FAKE_BODY"
    export FAKE_DELIVERABLE="$1"; shift
    set +e
    OUT="$(sh "$SCRIPT" "$@" 2>"$TMP/err")"; RC=$?
    set -e
    ERR="$(cat "$TMP/err")"
    CALLS="$(cat "$FAKE_CALLS")"
}

# --- (DIRECT) --no-react files the visit now, via gc-helm.sh open ------------
# A positive control first: a script that refused everything would satisfy
# every fail-closed assertion below while delivering nothing.
run yes "why is dolt wedging under load" --no-react
eq "$RC" "0" "(DIRECT) --no-react exits 0"
has "$CALLS" "bd create -t task --title why is dolt wedging under load" "(DIRECT) subject bead created from the topic"
has "$CALLS" "helm open tk-newsub" "(DIRECT) the visit is filed through gc-helm.sh open"
has "$CALLS" "--reason operator-origin topic intake" "(DIRECT) the visit says what it is actually for"
has "$CALLS" "--body" "(DIRECT) the claim-time brief is supplied"
hasnt "$CALLS" "helm react" "(DIRECT) no first reaction is slung"
has "$OUT" "visit filed" "(DIRECT) the summary reports a filed visit"
has "$OUT" "tk-newsub" "(DIRECT) the summary names the subject id"

# The subject body carries the topic as a durable seed, not just a title —
# the converse session reads the BODY at claim time.
has "$CALLS" "-d why is dolt wedging under load" "(DIRECT) the topic is the subject's durable body too"

# --- (SINGLE) the react path files NO visit ----------------------------------
run yes "how should we shard the refinery queue"
eq "$RC" "0" "(SINGLE) the react path exits 0"
has "$CALLS" "helm react tk-newsub" "(SINGLE) the first reaction is slung at the new subject"
hasnt "$CALLS" "helm open" "(SINGLE) no visit is filed — the reaction files it"
has "$OUT" "not filed yet" "(SINGLE) the operator is told the visit does not exist yet"
has "$OUT" "--no-react" "(SINGLE) and is told how to get the conversation now"

# --- (SHED) an undeliverable proactive surface diverts to the direct path ----
for why in disabled cap; do
    run "$why" "what should the deacon do about quota parks"
    eq "$RC" "0" "(SHED/$why) exits 0"
    hasnt "$CALLS" "helm react" "(SHED/$why) nothing is slung at a pool that cannot run it"
    has "$CALLS" "helm open tk-newsub" "(SHED/$why) the visit is filed directly instead"
    has "$OUT" "visit filed" "(SHED/$why) the summary reports a filed visit"
done
run disabled "a topic"
has "$OUT" "auto-spawn is disabled" "(SHED) the summary relays WHICH clamp said no"
run cap "a topic"
has "$OUT" "session cap" "(SHED) the cap answer is relayed verbatim too"

# A proactive tool that is missing entirely is the same situation: no reaction
# is coming, so the visit must be filed rather than waited for.
: > "$FAKE_CALLS"
set +e
OUT="$(GC_PROACTIVE_TOOL="$TMP/bin/nonexistent.sh" sh "$SCRIPT" "a topic" 2>"$TMP/err")"; RC=$?
set -e
CALLS="$(cat "$FAKE_CALLS")"
eq "$RC" "0" "(SHED/missing) a missing gc-proactive.sh still exits 0"
has "$CALLS" "helm open tk-newsub" "(SHED/missing) the visit is filed directly"

# --- (RECOVER) a failed sling still ends in a conversation --------------------
run yes "a topic that fails to sling"
FAKE_HELM_RC=4 run yes "a topic that fails to sling"
# helm is stubbed to fail for BOTH verbs here, so the run ends in the die() —
# what matters is that it TRIED the direct path after react failed.
has "$CALLS" "helm react tk-newsub" "(RECOVER) react was attempted"
has "$CALLS" "helm open tk-newsub" "(RECOVER) a failed react falls through to filing the visit"
has "$ERR" "falling back" "(RECOVER) the fallback is announced, not silent"
eq "$RC" "4" "(RECOVER) a direct path that also fails exits 4"
unset FAKE_HELM_RC

# --- (RIG) the default rig is fixed; --rig retargets; unknown rigs file nothing
run disabled "some cross-cutting topic"
has "$CALLS" "--db $TMP/rigs/gc-toolkit/.beads" "(RIG) the default rig is gc-toolkit, not inferred from cwd"
run disabled "a gascity topic" --rig gascity
has "$CALLS" "--db $TMP/rigs/gascity/.beads" "(RIG) --rig retargets the ledger"
run disabled "a topic" --rig nosuchrig
eq "$RC" "2" "(RIG) an unknown rig is a usage error"
eq "$CALLS" "" "(RIG) an unknown rig creates nothing and files nothing"
has "$ERR" "unknown rig" "(RIG) the error names the problem"
# die() takes the exit code as its SECOND argument; a $*-joined message printed
# it as trailing noise ("… shutupandlisten) 2"). Caught live, not by the
# substring assertion above — so assert the whole line, not a fragment.
[[ "$ERR" =~ \)$ ]] && ok "(RIG) the exit code does not leak into the message" \
    || bad "(RIG) the exit code leaks into the message (got: $ERR)"
# The env override exists so a differently-shaped city can move the default
# without editing the script.
: > "$FAKE_CALLS"
set +e
GC_VISIT_DEFAULT_RIG=gascity FAKE_DELIVERABLE=disabled sh "$SCRIPT" "a topic" >/dev/null 2>&1
set -e
has "$(cat "$FAKE_CALLS")" "--db $TMP/rigs/gascity/.beads" "(RIG) GC_VISIT_DEFAULT_RIG moves the default"

# --- (SUBJECT) an existing bead is its own subject ----------------------------
run disabled tk-abc12
eq "$RC" "0" "(SUBJECT) an existing bead id exits 0"
hasnt "$CALLS" "bd create" "(SUBJECT) no second bead is minted for an existing subject"
has "$CALLS" "helm open tk-abc12" "(SUBJECT) the visit is filed on the bead itself"
run disabled tk-abc12 --rig gascity
eq "$RC" "2" "(SUBJECT) --rig on an existing bead is refused, not ignored"
eq "$CALLS" "" "(SUBJECT) and files nothing"
run disabled tk-abc12 --type decision
eq "$RC" "2" "(SUBJECT) --type on an existing bead is refused"

# --- (SHAPE) prefix, not hyphen, decides id-vs-topic --------------------------
run disabled "dolt-latency"
has "$CALLS" "bd create" "(SHAPE) a hyphenated word whose prefix matches no rig is a topic"
has "$CALLS" "--title dolt-latency" "(SHAPE) and keeps its literal text"
run disabled "tk-abc12" --topic
has "$CALLS" "bd create" "(SHAPE) --topic forces a bead-shaped string to be a topic"
run disabled "gc-toolkit is slow"
has "$CALLS" "bd create" "(SHAPE) a multi-word string starting with a rig prefix is still a topic"

# --- (TYPE) a question is a decision -----------------------------------------
run disabled "should the refinery land siblings in one pass?"
has "$CALLS" "bd create -t decision" "(TYPE) a topic ending in ? becomes a decision bead"
run disabled "rework the refinery sibling pass"
has "$CALLS" "bd create -t task" "(TYPE) everything else is a task"
run disabled "should we do this?" --type task
has "$CALLS" "bd create -t task" "(TYPE) --type overrides the heuristic"

# --- (PARAGRAPH) the designed input: a paragraph, not a phrase ----------------
# Invoked exactly the way the key does it — `-- "$TOPIC"`, no --no-react — so
# this exercises the live reproduction rather than a convenient shape.
PARA_L1="The helm board is slow and the parked conversations show nothing useful at a glance."
PARA_L2="Jumping into one takes forever to load and the row gives no hint of what it was even about."
PARA_L3="I want the board to say something at a glance and to open in about a second, and I don't much care how."
PARA_L4="This is the third time this week it has cost me a real chunk of a morning, so please treat it as real."
PARA_L5="For reference the last one took about forty minutes of clicking around before I gave up and went to the beads directly."
PARA_L6="I don't need a design, I need someone to look at it and tell me what it would take."
PARAGRAPH="$PARA_L1
$PARA_L2
$PARA_L3
$PARA_L4
$PARA_L5
$PARA_L6"
# A positive control on the fixture itself: under the cap it would exercise
# nothing, and every assertion below would still pass.
[ "$(bytes "$PARAGRAPH")" -gt 500 ] \
    && ok "(PARAGRAPH) the fixture exceeds the 500-byte title cap ($(bytes "$PARAGRAPH") bytes)" \
    || bad "(PARAGRAPH) fixture is $(bytes "$PARAGRAPH") bytes — it must exceed 500 or it tests nothing"

run disabled -- "$PARAGRAPH"
TITLE="$(cat "$FAKE_TITLE")"; BODY="$(cat "$FAKE_BODY")"
eq "$RC" "0" "(PARAGRAPH) an over-cap paragraph files instead of dying at the create"
has "$CALLS" "helm open tk-newsub" "(PARAGRAPH) the visit is filed on the new subject"
has "$OUT" "visit filed" "(PARAGRAPH) and the operator is told so"

# The title: short enough for the ledger to accept, and still the operator's
# own opening words rather than a stock label.
[ -n "$TITLE" ] && [ "$(bytes "$TITLE")" -le 500 ] \
    && ok "(PARAGRAPH) the title is within the cap ($(bytes "$TITLE") bytes)" \
    || bad "(PARAGRAPH) the title is $(bytes "$TITLE") bytes — bd create refuses over 500"
eq "$(printf '%s' "$TITLE" | wc -l | tr -d ' ')" "0" "(PARAGRAPH) the title is a single line"
has "$TITLE" "The helm board is slow" "(PARAGRAPH) the title leads with the operator's own words"
case "$TITLE" in
    *…) ok "(PARAGRAPH) the cut is marked with an ellipsis" ;;
    *)  bad "(PARAGRAPH) a truncated title does not say it was cut (got '$TITLE')" ;;
esac

# The body: the whole point. Every line the operator typed has to be recoverable
# from the bead, because the converse session reads the BODY at claim time.
has "$BODY" "$PARA_L1" "(PARAGRAPH) the body keeps the first line verbatim"
has "$BODY" "$PARA_L2" "(PARAGRAPH) the body keeps the second line verbatim"
has "$BODY" "$PARA_L3" "(PARAGRAPH) the body keeps the third line verbatim"
has "$BODY" "$PARA_L4" "(PARAGRAPH) the body keeps the fourth line verbatim"
has "$BODY" "$PARA_L5" "(PARAGRAPH) the body keeps the fifth line verbatim"
has "$BODY" "$PARA_L6" "(PARAGRAPH) the body keeps the last line verbatim"

# A topic that already fits is passed through untouched — the cap must not
# rewrite the ordinary case. Multi-line still collapses: a title with newlines
# in it renders as garbage on every surface that shows one.
run disabled "why is dolt wedging under load"
eq "$(cat "$FAKE_TITLE")" "why is dolt wedging under load" "(PARAGRAPH) a topic within the cap is used verbatim"
run disabled "$(printf 'the board is slow\nand jumping in is slower')"
eq "$(cat "$FAKE_TITLE")" "the board is slow and jumping in is slower" "(PARAGRAPH) a short multi-line topic collapses to one line"
# Not `has`: grep -F reads a multi-line pattern as one-per-line ALTERNATIVES, so
# it would pass on either line by itself — which is the very thing being denied.
case "$(cat "$FAKE_BODY")" in
    *"the board is slow"$'\n'"and jumping in is slower"*)
        ok "(PARAGRAPH) while the body keeps the line break" ;;
    *)  bad "(PARAGRAPH) the body lost the line break between the two lines" ;;
esac

# A paragraph in a writing system that does not space its words is one
# unbroken token: there is no word boundary to cut on, and cutting on the byte
# would leave half a character and a title the ledger refuses.
# Built with printf octal escapes rather than python3: a fallback to an ASCII
# token would silently retarget this case at the one shape it is not about.
CJK_TOPIC="$(printf '\344\270\255%.0s' $(seq 1 600))"
eq "$(bytes "$CJK_TOPIC")" "1800" "(PARAGRAPH) the CJK fixture is 600 unbroken 3-byte characters"
run disabled -- "$CJK_TOPIC"
TITLE="$(cat "$FAKE_TITLE")"
[ -n "$TITLE" ] && [ "$(bytes "$TITLE")" -le 500 ] \
    && ok "(PARAGRAPH) an unbroken 600-character token is cut to fit ($(bytes "$TITLE") bytes)" \
    || bad "(PARAGRAPH) an unbroken token was not cut ($(bytes "$TITLE") bytes)"
printf '%s' "$TITLE" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1 \
    && ok "(PARAGRAPH) and is still valid UTF-8 — no half character at the cut" \
    || bad "(PARAGRAPH) the cut left an incomplete multi-byte character"

# --- (FAILCLOSE) nothing half-filed -------------------------------------------
: > "$FAKE_CALLS"
set +e
OUT="$(FAKE_CREATE_FAIL=1 FAKE_DELIVERABLE=disabled sh "$SCRIPT" "a topic" 2>"$TMP/err")"; RC=$?
set -e
CALLS="$(cat "$FAKE_CALLS")"; ERR="$(cat "$TMP/err")"
eq "$RC" "4" "(FAILCLOSE) a subject that cannot be created exits 4"
hasnt "$CALLS" "helm open" "(FAILCLOSE) and files no visit"
has "$ERR" "nothing filed" "(FAILCLOSE) the message says nothing was filed"

# --- (WHY) a stated refusal reaches the operator ------------------------------
# `bd create --json` says WHY it refused in .error. Keeping only .id off the
# response threw all of it away and reported every refusal as "returned no id",
# so the operator was told the ledger returned nothing when in fact it had
# refused for a stated, fixable reason — and went looking for a broken data
# plane instead of a long title (tk-wp50s).
: > "$FAKE_CALLS"
set +e
LEDGER_SAID="validation failed: validation failed for issue : title must be 500 characters or less (got 579)"
OUT="$(FAKE_CREATE_FAIL=1 FAKE_CREATE_ERROR="$LEDGER_SAID" FAKE_DELIVERABLE=disabled \
       sh "$SCRIPT" "a topic" 2>"$TMP/err")"; RC=$?
set -e
CALLS="$(cat "$FAKE_CALLS")"; ERR="$(cat "$TMP/err")"
eq "$RC" "4" "(WHY) a refused create still exits 4"
has "$ERR" "$LEDGER_SAID" "(WHY) the ledger's stated reason reaches the operator verbatim"
hasnt "$ERR" "returned no id" "(WHY) and is not replaced by the generic no-id message"
has "$ERR" "nothing filed" "(WHY) while still saying nothing was filed"
hasnt "$CALLS" "helm open" "(WHY) and no visit is filed on a subject that does not exist"

# A response with no .error at all still has to say something useful rather
# than nothing — the fallback names the missing id and the exit status.
: > "$FAKE_CALLS"
set +e
FAKE_CREATE_SILENT=1 FAKE_DELIVERABLE=disabled sh "$SCRIPT" "a topic" >/dev/null 2>"$TMP/err"; RC=$?
set -e
ERR="$(cat "$TMP/err")"
eq "$RC" "4" "(WHY) a silent create failure exits 4"
has "$ERR" "no error" "(WHY) a response with no .error says so, rather than reporting nothing"

run disabled
eq "$RC" "2" "(FAILCLOSE) no argument is a usage error"
eq "$CALLS" "" "(FAILCLOSE) and creates nothing"
run disabled "a topic" --bogus
eq "$RC" "2" "(FAILCLOSE) an unknown flag is a usage error"
eq "$CALLS" "" "(FAILCLOSE) and creates nothing"
run disabled "topic one" "topic two"
eq "$RC" "2" "(FAILCLOSE) two positionals are a usage error (quote the topic)"
eq "$CALLS" "" "(FAILCLOSE) and create nothing"

# --- (RIGWHY) this script's own enumerate_rigs names WHICH failure it hit -----
# The same defect as gc-helm.sh's (tk-lzdty half 2), in this script's hand-rolled
# copy — and worse here, because it piped `gc rig list` STRAIGHT into jq. A
# pipeline reports the LAST command's status, so gc's exit code was discarded
# structurally, not just by a `|| true`, and its stderr went to /dev/null. A
# wedged data plane, unparseable output and a city that genuinely has no rigs
# all produced one sentence and exit 3.
#
# This matters here specifically because the topic path shells out to
# `gc-helm.sh open`: if the two front doors disagree about why a city has no
# rigs, the operator gets a different story depending on which one they hit.
# There is no timeout arm — unlike gc-helm.sh this script does not bound the
# call, so there is no kill to report.
mkdir -p "$TMP/rigbin"
cat > "$TMP/rigbin/gc" <<'RIGSTUB'
#!/usr/bin/env bash
if [ "$1 ${2:-}" = "rig list" ]; then
  case "${RIGMODE:-}" in
    exitfail) echo "dial tcp 127.0.0.1:3307: connect: connection refused" >&2; exit 7 ;;
    empty)    : ;;
    notjson)  echo "warning: rebuilding stale rig cache" ;;
    shape)    jq -n '{other:[]}' ;;
    rigless)  jq -n '{rigs:[]}' ;;
  esac
  exit 0
fi
printf '%s %s\n' "$1" "${2:-}" >> "$FAKE_CALLS"
exit 0
RIGSTUB
chmod +x "$TMP/rigbin/gc"

# A bead-id-shaped argument is what sends this script down the rig-resolution
# path in the first place, so drive it with one.
rigwhy() {
    : > "$FAKE_CALLS"
    set +e
    PATH="$TMP/rigbin:$TMP/bin:$PATH" RIGMODE="$1" sh "$SCRIPT" tk-abc12 >/dev/null 2>"$TMP/rigerr"
    RIGWHY_RC=$?
    set -e
    RIGWHY_ERR="$(cat "$TMP/rigerr")"
}
saysv() {
    rigwhy "$1"
    has "$RIGWHY_ERR" "$2" "(RIGWHY) $3"
    eq "$RIGWHY_RC" "3" "(RIGWHY) …and still exits 3 ($3)"
    eq "$(cat "$FAKE_CALLS")" "" "(RIGWHY) …having filed nothing ($3)"
}
saysv exitfail "exited 7"                     "a non-zero gc exit reports the status, not 'returned nothing'"
saysv exitfail "connection refused"           "…and carries gc's stderr, which the old pipeline discarded"
saysv empty    "exited 0 but printed nothing" "a silent empty answer is not read as an empty city"
saysv notjson  "is not JSON"                  "unparseable output says so"
saysv shape    "no '.rigs' array"             "valid JSON of the wrong shape is a gc contract change"
saysv rigless  "no rigs in this city"         "a genuinely rigless city is reported as a CITY state"

: > "$TMP/rigmsgs"
for m in exitfail empty notjson shape rigless; do
    rigwhy "$m"; printf '%s\n' "$RIGWHY_ERR" >> "$TMP/rigmsgs"
done
eq "$(sort -u "$TMP/rigmsgs" | wc -l | tr -d ' ')" "5" \
   "(RIGWHY-DISTINCT) five causes produce five different sentences"

# Guard the evidence itself: if the pipeline form comes back, gc's status is
# structurally unavailable again and every message above degrades to one.
# Match "gc rig list" and a jq pipe on the SAME code line, with the redirect
# that sits between them left unspecified — the old form was
# `gc rig list --json 2>/dev/null | jq`, so requiring the two to be adjacent
# missed it and this guard passed against the very code it exists to catch.
# Comment lines are excluded so the prose above cannot satisfy it either.
awk '/^enumerate_rigs\(\)/{f=1} f&&/^\}/{f=0} f&&!/^[[:space:]]*#/&&/gc rig list/&&/\|[[:space:]]*jq/' "$SCRIPT" | grep -q . \
  && bad "(RIGWHY-EVIDENCE) the pipe-into-jq form is back — gc's exit status is discarded" \
  || ok "(RIGWHY-EVIDENCE) gc is run on its own, so its exit status survives"

# --- (HELP/SYNTAX) ------------------------------------------------------------
run yes --help
eq "$RC" "0" "(HELP) --help exits 0"
eq "$CALLS" "" "(HELP) --help touches nothing"
sh -n "$SCRIPT" 2>/dev/null && ok "(SYNTAX) gc-visit-open.sh parses as POSIX sh" || bad "(SYNTAX) sh -n failed"

echo ""
echo "gc-visit-open operator intake: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
