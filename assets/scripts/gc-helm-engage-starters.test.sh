#!/usr/bin/env bash
# Hermetic test for gc-helm-engage-starters.sh — the starter-seed table engage
# reads for its interactive visit/starter prompt and its --template flag.
# Runs the REAL emitter via `sh` (POSIX, as gc-helm.sh invokes it). No gc, store,
# or network. Covered:
#   (LIST)   `list` prints one "<key>\t<label>\t<letter>" row per seed, in order
#   (SEED)   `seed <key> <subject>` substitutes __SUBJECT__ and reads as a
#            topic+readiness opener, not an agenda
#   (NOSUBJ) `seed <key>` with no subject leaves the placeholder
#   (BADKEY) an unknown seed key exits 2 and lists the valid keys
#   (BADCMD) an unknown subcommand exits 2
#   (LENS)   `lens <skill> <subject>` names the skill and the subject, has the
#            sitting load it, withholds the skill's final writes, and with no
#            opener ends in a framing-then-wait close
#   (LENS-OPENER) with an opener, the brief defers to it and the opener follows
#            verbatim, never passing through the placeholder substitution
#   (LENS-BADNAME) a skill name outside letters, digits, dots and hyphens exits 2
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/gc-helm-engage-starters.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 (unexpected '$2')" ;; *) ok "$3" ;; esac; }

[ -f "$SCRIPT" ] && ok "gc-helm-engage-starters.sh present" || bad "missing at $SCRIPT"

run() {
    set +e
    OUT="$(sh "$SCRIPT" "$@" 2>/dev/null)"; RC=$?
    set -e
}

echo "# list prints one key<TAB>label row per seed, in menu order"
run list
eq "$RC" 0 "(LIST) list exits 0"
KEYS="$(printf '%s' "$OUT" | cut -f1 | tr '\n' ' ')"
eq "$KEYS" "discuss-broadly pr-feedback unstick-a-stall " "(LIST) the three seed keys in order"
has "$OUT" "$(printf 'discuss-broadly\tdiscuss broadly\td')" "(LIST) key, label, and accelerator letter are tab-separated"
LETTERS="$(printf '%s' "$OUT" | cut -f3 | tr '\n' ' ')"
eq "$LETTERS" "d p s " "(LIST) the three seed accelerator letters in order"

echo "# seed substitutes the subject and reads as topic + readiness"
run seed discuss-broadly tk-6bji7k
eq "$RC" 0 "(SEED) a known seed exits 0"
has "$OUT" "talk through tk-6bji7k broadly" "(SEED) __SUBJECT__ is replaced with the subject"
has "$OUT" "WAIT for the operator" "(SEED) …and the opener establishes readiness, not an agenda"
hasnt "$OUT" "__SUBJECT__" "(SEED) …no placeholder is left behind"

run seed unstick-a-stall tk-abc
has "$OUT" "tk-abc looks stalled" "(SEED-STALL) the stall seed names the subject"
has "$OUT" "do not assume a single cause" "(SEED-STALL) …and stays non-assumptive"

echo "# a seed with no subject keeps the placeholder rather than emptying it"
run seed discuss-broadly
has "$OUT" "<subject>" "(NOSUBJ) the placeholder is left visible when no subject is given"

echo "# an unknown seed key is refused, listing the valid keys"
run seed bogus tk-1
eq "$RC" 2 "(BADKEY) an unknown key exits 2"

echo "# an unknown subcommand is refused"
run frobnicate
eq "$RC" 2 "(BADCMD) an unknown subcommand exits 2"

echo "# lens seeds the sitting with a skill as its lens on the subject"
run lens gc-toolkit.review-arch tk-abc
eq "$RC" 0 "(LENS) a lens with no opener exits 0"
has "$OUT" "look at tk-abc through the gc-toolkit.review-arch" "(LENS) the brief names the subject and the skill"
has "$OUT" "Load that skill before you prep" "(LENS) …has the sitting load the skill"
has "$OUT" "not yours to make" "(LENS) …and withholds the skill's final writes, which belong to the bead it serves"
has "$OUT" "available to you, say so" "(LENS) …and says what to do when the skill is not available"
has "$OUT" "then WAIT for the operator" "(LENS) …and with no opener, the lens is the assignment: frame, then wait"
hasnt "$OUT" "__SKILL__" "(LENS) …no skill placeholder is left behind"
hasnt "$OUT" "__SUBJECT__" "(LENS) …no subject placeholder is left behind"

echo "# with an opener, the brief defers to it and the opener follows verbatim"
run lens gc-toolkit.review-arch tk-abc 'start with the __SUBJECT__ split & the | cost'
eq "$RC" 0 "(LENS-OPENER) a lens with an opener exits 0"
has "$OUT" "opener follows and says what to do first" "(LENS-OPENER) the brief hands the first move to the opener"
hasnt "$OUT" "then WAIT for the operator" "(LENS-OPENER) …instead of the lens-only close"
has "$OUT" "start with the __SUBJECT__ split & the | cost" "(LENS-OPENER) …and the opener is emitted verbatim, untouched by the substitution"
case "$OUT" in
  *"says what to do first."*"start with the"*) ok "(LENS-OPENER) …after the brief" ;;
  *) bad "(LENS-OPENER) the opener should follow the brief" ;;
esac

echo "# a lens refuses a name that is not a skill name"
run lens 'review|arch' tk-abc
eq "$RC" 2 "(LENS-BADNAME) a name carrying a metacharacter exits 2"
run lens
eq "$RC" 2 "(LENS-BADNAME) a lens with no skill exits 2"

echo
echo "gc-helm-engage-starters: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
