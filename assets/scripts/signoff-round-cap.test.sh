#!/usr/bin/env bash
# Hermetic test for the signoff rework-round cap (tk-uqfk1).
#
# Every REQUEST_CHANGES verdict files a rework child and wakes the fix pool;
# the hand-back then makes the refinery mint a fresh codex review and wake the
# codex pool. Both pools are wake_mode="fresh", so each round pays two cold
# full contexts. The loop is unbounded by construction — docs/work-bead-state-
# machine.md:360 says the PR is "a long-lived object across however many rework
# rounds it takes" — and one PR was observed reaching 15 rounds.
#
# The cap counts rounds off the anchor's own parent-child children (one child
# per round, by construction) and past the cap escalates INSTEAD of filing.
# Not filing is the fail-safe: the merge hold derives from OPEN children
# (assets/scripts/merge-skill.sh), so an anchor with zero children stays held
# and parks for a human with nothing left to spawn.
#
# This test EXECUTES the real counting snippet extracted verbatim from the
# template (between the `signoff-round-cap` markers) against a fake `gc`, so it
# cannot drift from the shipped instruction. No live city, Dolt, or network.
#
# It also pins what the cap WRITES, in both of its two independent halves — the
# polecat one in the template and the refinery one in mol-refinery-patrol.toml —
# because that write is where tk-mf3em lived. Both halves used to
# `--unset-metadata check.<name>` on the same event that
# assets/scripts/reconcile-gate-verdicts.sh's R11 records as
# `exception@<head>`: ONE convergence-cap event, two opposite terminal gate
# states, and which one survived decided by pass ordering rather than by design.
# Both orderings were observed in production (su-uzy9.5 2026-08-13, sl-ew4w
# 2026-08-19), and because the cap arms run in the patrol's merge-push step while
# reconcile-gate-verdicts runs earlier in the same wake from find-work, the
# marker oscillated stamped/cleared once per wake — and check-set-heal.sh, which
# dispatches on an ABSENT marker and skips on `exception@*`, re-dispatched codex
# every wake against a gate that had already given up.
#
# So the invariant these arms hold is narrow and worth stating exactly: the cap
# stops the SPAWN and routes to a human, and it writes NOTHING under `check.`.
# The verdict has one writer.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TEMPLATE="$ROOT/template-fragments/polecat-non-impl-done.template.md"
PATROL="$ROOT/formulas/mol-refinery-patrol.toml"
VERDICTS="$ROOT/assets/scripts/reconcile-gate-verdicts.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

mkdir -p "$TMP/bin"

# --- gc stub: the single read the counting snippet performs. -----------------
# gc bd dep list <anchor> --direction=up -t parent-child --json
# FAKE_CHILDREN is a raw JSON array of child beads, echoed verbatim, so a test
# case can mix rework children (source_review_bead present) with other children
# (rebase/convoy members) and assert only the rework ones are counted.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
# Every invocation is logged when GC_LOG is set, so the write arms can assert on
# the ARGUMENTS the shipped block actually passes rather than on its source text.
[ -n "${GC_LOG:-}" ] && printf '%s\n' "$*" >> "$GC_LOG"
[ "$1" = "bd" ] || exit 0
[ "$2" = "dep" ] || exit 0
if [ -n "${FAKE_CHILDREN:-}" ]; then printf '%s\n' "$FAKE_CHILDREN"; else printf '[]\n'; fi
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH"

# --- extract the shipped snippet verbatim ------------------------------------
awk '/# >>> signoff-round-cap/{f=1;next} /# <<< signoff-round-cap/{f=0} f' \
  "$TEMPLATE" > "$TMP/cap.sh"
[ -s "$TMP/cap.sh" ] || { echo "FAIL - could not extract signoff-round-cap snippet"; exit 1; }
grep -q 'source_review_bead' "$TMP/cap.sh" \
  && ok "snippet extracted from template and counts on source_review_bead" \
  || bad "extracted snippet does not filter on source_review_bead"

# --- every dispatcher carries the SAME block ---------------------------------
# The cap belongs to the ANCHOR, not to whoever is about to dispatch (tk-j5wrs
# ruling 3), and it only belongs to the anchor if all four dispatchers read the
# same count the same way. Three of them had no cap at all until tk-vie5k, which is
# how round N+1 got minted in exactly the window the cap exists to close — so a
# copy going missing, or drifting, is the regression this census exists to catch.
# The template is canonical; every other host is diffed against it, modulo the
# indentation its own surface adds.
CAP_CANON="$(sed 's/^[[:space:]]*//' "$TMP/cap.sh")"
CAP_HOSTS="$PATROL $ROOT/assets/scripts/check-set-heal.sh $ROOT/assets/scripts/reconcile-merged-prs.sh"
CAP_COPIES=0
for capf in $CAP_HOSTS; do
  capname="$(basename "$capf")"
  capblk="$(awk '/# >>> signoff-round-cap/{f=1;next} /# <<< signoff-round-cap/{f=0} f' "$capf" \
              | sed 's/^[[:space:]]*//')"
  if [ -z "$capblk" ]; then
    bad "$capname carries the signoff-round-cap block (none found — unmarked or hand-rolled?)"
    continue
  fi
  CAP_COPIES=$((CAP_COPIES + 1))
  if [ "$capblk" = "$CAP_CANON" ]; then
    ok "$capname carries the canonical cap block, byte-identical"
  else
    bad "$capname cap block DRIFTED from the template copy"
  fi
done
[ "$CAP_COPIES" -ge 3 ] \
  && ok "every known dispatcher carries the cap block ($CAP_COPIES + the template)" \
  || bad "a dispatcher lost its cap block (found $CAP_COPIES of 3 besides the template)"

# run_cap <anchor> <children-json> [max] -> "ROUNDS CAP_HIT"
#
# CAP_ANCHOR is the block's input, not the host's local name: the same block now
# ships in four files whose anchor variables are ANCHOR, GATING_ANCHOR and `id`,
# and one shared block cannot read three different names (tk-vie5k).
run_cap() {
  CAP_ANCHOR="$1" FAKE_CHILDREN="$2" GC_MAX_REVIEW_ROUNDS="${3-}" \
  bash -c 'set -euo pipefail; source "$1"; echo "$ROUNDS $CAP_HIT"' _ "$TMP/cap.sh"
}

child() { printf '{"id":"%s","metadata":{"source_review_bead":"rv-%s"}}' "$1" "$1"; }

# --- default cap is 3 --------------------------------------------------------
eq "$(run_cap tk-anchor '[]')"                          "0 0" "no children -> 0 rounds, no cap"
eq "$(run_cap tk-anchor "[$(child a)]")"                "1 0" "1 round -> under cap"
eq "$(run_cap tk-anchor "[$(child a),$(child b)]")"     "2 0" "2 rounds -> under cap"
eq "$(run_cap tk-anchor "[$(child a),$(child b),$(child c)]")" \
                                                        "3 1" "3 rounds -> cap trips"
eq "$(run_cap tk-anchor "[$(child a),$(child b),$(child c),$(child d)]")" \
                                                        "4 1" "past cap stays tripped"

# --- only rework children count ----------------------------------------------
# A rebase/convoy child carries no source_review_bead and must not inflate the
# count; otherwise an anchor with unrelated children caps before its first
# real rework round and parks live work for a human.
eq "$(run_cap tk-anchor "[{\"id\":\"reb\",\"metadata\":{}},$(child a)]")" \
   "1 0" "non-rework children are not counted as rounds"
eq "$(run_cap tk-anchor '[{"id":"reb","metadata":{}},{"id":"cv","metadata":{"branch":"x"}}]')" \
   "0 0" "children with no source_review_bead at all -> 0 rounds"

# --- cap is tunable ----------------------------------------------------------
eq "$(run_cap tk-anchor "[$(child a)]" 1)"              "1 1" "GC_MAX_REVIEW_ROUNDS=1 trips at 1"
eq "$(run_cap tk-anchor "[$(child a),$(child b)]" 5)"   "2 0" "GC_MAX_REVIEW_ROUNDS=5 raises the bar"

# --- no anchor never caps ----------------------------------------------------
# Without an anchor there is no reliable round history. Capping on a guess would
# park live work for a human, so the cap must stay off.
eq "$(run_cap '' "[$(child a),$(child b),$(child c),$(child d)]")" \
   "0 0" "empty anchor -> never caps"

# --- degraded store must not cap ---------------------------------------------
# A failing/empty `gc bd dep list` reads as zero rounds, not as "past the cap".
# The wrong direction here would strand every review during a store outage.
eq "$(run_cap tk-anchor 'not-json')" "0 0" "unparseable dep list -> 0 rounds, no cap"

# =============================================================================
# What the cap WRITES — both halves, and the single writer of the verdict.
# =============================================================================
has()   { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2')" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2')" ;; *) ok "$3" ;; esac; }

# Pull the block between the shared markers out of whichever file hosts it.
#
# This reads the RAW file, so for the patrol formula it is the pre-TOML text: a
# `"""` string silently eats a trailing-backslash line continuation, joining those
# lines before the shell ever sees them. That difference cannot change the answer
# here, because the block is a comment plus one backslash-continued command and
# the shell joins exactly the same lines — so both readings issue identical argv,
# and argv is what the assertions below read.
#
# Reading argv rather than source text is the point. The blocks describe the very
# write they must not make, so `check.` appears in their prose; a grep over the
# text would fail on the comment and pass on a re-introduced flag with the wording
# removed. Executing them against a logging stub inverts that.
extract_cap_write() {
    awk '/# >>> signoff-cap-no-gate-write/{f=1;next} /# <<< signoff-cap-no-gate-write/{f=0} f' "$1"
}

# run_cap_write <file> <anchor-var-name> -> the gc argv the block issued
run_cap_write() {
    local src="$1" anchorvar="$2" blk="$TMP/capwrite.sh" log="$TMP/gc.log"
    extract_cap_write "$src" > "$blk"
    : > "$log"
    GC_LOG="$log" ROUNDS=3 CHECK_NAME=codex GC_MAX_REVIEW_ROUNDS=3 \
      env "$anchorvar=tk-anchor" bash -c 'set -uo pipefail; source "$1"' _ "$blk" >/dev/null 2>&1
    cat "$log"
}

for pair in "$TEMPLATE:ANCHOR:polecat half (template fragment)" \
            "$PATROL:GATING_ANCHOR:refinery half (mol-refinery-patrol.toml)"; do
    src="${pair%%:*}"; rest="${pair#*:}"; var="${rest%%:*}"; label="${rest#*:}"
    blk="$(extract_cap_write "$src")"

    # POSITIVE CONTROL. An extraction that matches nothing passes every "does not
    # contain" assertion below, so a suite that silently stopped finding the block
    # would read as green — the exact false-green this pair of arms exists to rule
    # out.
    [ -n "$blk" ] && ok "$label: cap-write block extracted between markers" \
        || bad "$label: extraction EMPTY — markers missing from $src"

    printf '%s\n' "$blk" > "$TMP/blk.sh"
    bash -n "$TMP/blk.sh" && ok "$label: the shipped block is valid bash" \
        || bad "$label: extracted block failed bash -n"

    argv="$(run_cap_write "$src" "$var")"

    # The cap's actual job, asserted on the argv so a block that stopped running
    # at all cannot pass by saying the right words in a comment.
    has "$argv" "gc.routed_to=human" "$label: routes the anchor to a human"
    has "$argv" "blocked_reason=signoff did not converge" \
        "$label: records WHY it is held, in the anchor's own state"

    # THE REGRESSION (tk-mf3em). Not "does not unset" — does not touch `check.`
    # at all. Stamping the exception here instead of clearing it would look like
    # agreement and would re-create the same defect: two writers of one field,
    # each resolving the head its own way.
    hasnt "$argv" "check." "$label: writes NOTHING under check.<gate> — the verdict has one writer"
done

# THE OTHER HALF OF THE CONTRACT. Dropping the clear is only correct because the
# condition is still recorded, by the pass that owns the verdict. If R11 is ever
# removed or renamed, the cap arms above go silent about a gate that has given
# up — so pin it here, across the file boundary the fix depends on.
VERDICT_SRC="$(cat "$VERDICTS")"
has "$VERDICT_SRC" "attempts-exhausted:" \
    "reconcile-gate-verdicts.sh R11 still records the exhaustion the cap arms no longer write"
has "$VERDICT_SRC" 'check.$gate=$GATE_VERB_EXCEPTION@$head' \
    "and records it as the exception verb bound to the live head"

# NOT AN ACROSS-THE-BOARD BAN. The fixable path — a rework child IS filed, so
# remediation is in flight — still retracts the marker, and must: re-arming
# check-set-heal.sh is the point there, because the fix moves the head and a
# fresh review has to run against it. Past the cap nothing is coming, which is
# what makes that write a terminal verdict instead of a retraction. An
# over-broad reading of the fix would delete this one too.
REWORK_BLK="$(awk '/# >>> signoff-rework-dispatch/{f=1;next} /# <<< signoff-rework-dispatch/{f=0} f' "$TEMPLATE")"
[ -n "$REWORK_BLK" ] && ok "rework-dispatch block extracted (positive control)" \
    || bad "rework-dispatch extraction EMPTY — markers missing from $TEMPLATE"
has "$REWORK_BLK" '--unset-metadata "check.$CHECK_NAME"' \
    "the UNDER-cap fixable path still retracts the marker — the ban is on the terminal arm only"

echo "--- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
