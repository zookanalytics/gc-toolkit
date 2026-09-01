#!/usr/bin/env bash
# Tree-wide invariant: nothing routes a bead to the operator without recording
# what is owed.
#
# The helm board spends an anchor's gc.takeaway as its NEEDS sentence
# (services/helm/internal/board/derive.go). On a row routed to a person with an
# empty takeaway it renders "routed to you — no question recorded", and it is
# right to: whoever parked the row never said what it wants. So every writer
# that puts a bead on the park route has to write the sentence beside it.
#
# Two enforcement surfaces, and this suite checks both:
#   - lifecycle.sh refuses the park without one at runtime (lifecycle.test.sh
#     proves the refusal); here we only assert the guard is still wired.
#   - a raw `gc bd update` bypasses lifecycle.sh entirely, so each such site is
#     read out of the tree and required to carry the takeaway in the same
#     statement.
#
# A new writer that parks a bead and says nothing fails this suite.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2')" ;; esac; }

cd "$ROOT" || exit 1

# The park sentinel, read from the declared machine rather than hardcoded.
PARK=$(sed -n 's/^park_route = "\(.*\)"/\1/p' lifecycle/lifecycle.toml)
eq "${PARK:-<empty>}" "human" "the park route is read from lifecycle.toml"

# Files that STATE the rule rather than break it: the generated re-render, the
# specs and docs describing the defect, this suite's siblings, and prose that
# quotes the marker while explaining it.
skip_file() {
  case "${1#./}" in
    generated/*|specs/*|docs/*|*/README.md|README.md) return 0 ;;
    *.test.sh|*_test.go|*.test.tsx|*.fixture.json) return 0 ;;
    template-fragments/*|services/helm/*) return 0 ;;
    *) return 1 ;;
  esac
}

# A takeaway stamped above a park is the other way a site records its question:
# the converse hold stamps through gc-helm and then transitions, and by the
# time lifecycle.sh reads the bead the sentence is on it.
#
# What makes a stamp vouch for a park is that it names the SAME bead. A stamp
# for some other subject says nothing about this one however close it sits, and
# distance alone cannot find the right one either — the hold files its demand
# between the stamp and the transition, so the two are no longer adjacent. The
# search is bounded to the enclosing block: the fenced block in a prompt
# template, a line window elsewhere.
LOOKBACK=40
block_start() { # <file> <line> — first line of the enclosing fenced block, else the window
  local from=$(( $2 - LOOKBACK )); [ "$from" -lt 1 ] && from=1
  case "$1" in
    *.md)
      local fence
      fence=$(awk -v line="$2" '
        NR < line && /^[[:space:]]*```/ { if (open) { open = 0 } else { open = 1; at = NR } }
        END { if (open) print at }
      ' "$1")
      [ -n "$fence" ] && [ "$fence" -gt "$from" ] && from="$fence"
      ;;
  esac
  printf '%s' "$from"
}
stamps_takeaway_above() { # <file> <line> <subject>
  local subj="$3"
  [ -n "$subj" ] || return 1
  local from; from=$(block_start "$1" "$2")
  local above; above=$(sed -n "${from},$(( $2 - 1 ))p" "$1")
  grep -qF "takeaway $subj" <<< "$above"
}

# The one logical shell statement CONTAINING <file>:<line> — every line it
# continues onto with a trailing backslash, and every line it continues FROM.
# A match can land on any line of a continuation, and an argument list that
# accumulates the route last (set -- ... "gc.routed_to=human") carries its
# takeaway on an earlier line of the same statement. TOML """ blocks collapse
# those continuations at parse time, so the same join reads both.
statement() { # <file> <line>
  awk -v line="$2" '
    { l[NR] = $0 }
    END {
      start = line
      while (start > 1 && l[start - 1] ~ /\\[[:space:]]*$/) start--
      for (i = start; i <= NR; i++) {
        buf = buf l[i] " "
        if (l[i] !~ /\\[[:space:]]*$/) break
      }
      print buf
    }
  ' "$1"
}

# --- raw writers: the takeaway must ride the same statement ---------------------
echo "# raw gc.routed_to writers"
raw_checked=0
while IFS=: read -r f n _; do
  [ -n "$f" ] || continue
  skip_file "$f" && continue
  stmt=$(statement "$f" "$n")
  raw_checked=$((raw_checked + 1))
  has "$stmt" "gc.takeaway=" "$f:$n writes the takeaway in the same update"
done < <(grep -rn 'gc\.routed_to="\?human"\?' --include='*.sh' --include='*.toml' --include='*.md' . 2>/dev/null \
           | grep -v '^\./\.git/' | grep -F -- '--set-metadata')

# A route that FALLS BACK to the park sentinel is a park too, whatever the
# variable is called: the fallback is what runs when nobody was named.
while IFS=: read -r f n _; do
  [ -n "$f" ] || continue
  skip_file "$f" && continue
  var=$(sed -n "${n}p" "$f" | sed -n 's/.*\[ -z "\$\([A-Z_][A-Z0-9_]*\)" \] && \1="'"$PARK"'".*/\1/p')
  [ -n "$var" ] || continue
  # The nearest write of that variable into gc.routed_to, at or below here.
  wn=$(awk -v start="$n" -v v="$var" 'NR >= start && index($0, "gc.routed_to=\"$" v "\"") { print NR; exit }' "$f")
  [ -n "$wn" ] || continue
  stmt=$(statement "$f" "$wn")
  raw_checked=$((raw_checked + 1))
  has "$stmt" "gc.takeaway=" "$f:$wn parks via \$$var and writes the takeaway with it"
done < <(grep -rn "=\"$PARK\"" --include='*.sh' --include='*.toml' . 2>/dev/null | grep -v '^\./\.git/' | grep -F '[ -z "$')

[ "$raw_checked" -gt 0 ] && ok "raw park writers found and checked ($raw_checked)" \
  || bad "no raw park writer found — the discovery patterns have gone stale"

# --- lifecycle.sh: the guard that covers every --route caller -------------------
# Callers reach the park through --route, and there the rule is enforced at
# runtime instead of by grep: a caller may satisfy it with --takeaway or with a
# takeaway already on the bead, and only lifecycle.sh can tell the two apart.
echo "# the lifecycle guard"
LC="$HERE/lifecycle.sh"
GUARD=$(awk '/LIFECYCLE_PARK_ROUTE" \] && \[ "\$TAKEAWAY_SET" = 0 \]/,/^  fi$/' "$LC")
[ -n "$GUARD" ] && ok "lifecycle.sh carries the park-route takeaway guard" \
  || bad "lifecycle.sh no longer refuses a park with no takeaway"
has "$GUARD" "exit 1" "the guard refuses rather than warning"
has "$GUARD" "no question recorded" "the refusal quotes what the board would render"

# The guard is only as good as the flag it accepts, and two arms carry that.
# One refuses text that normalizes to nothing: the flag's presence alone
# satisfies the guard above, so an empty one parks the bead mute — the state
# the guard exists to prevent, reached through the flag that answers it.
EMPTY=$(awk '/if \[ -z "\$TAKEAWAY" \]; then/,/fi$/' "$LC")
[ -n "$EMPTY" ] && ok "lifecycle.sh refuses a --takeaway that normalizes to nothing" \
  || bad "lifecycle.sh accepts an empty --takeaway"
has "$EMPTY" "exit 1" "…refusing rather than writing an empty headline"
has "$EMPTY" "no question recorded" "…and quoting what the board would render"

# The other spends the accepted text in the same atomic update as the route.
# Named by the args it builds, not by its position: the validating arms carry
# the same condition and only this one writes.
WRITE=$(awk '/TAKEAWAY_SET" = 1 \]; then/{buf = ""; f = 1}
             f {buf = buf $0 ORS}
             f && /^  fi$/ {f = 0; if (buf ~ /ARGS\+=/) {printf "%s", buf; exit}}' "$LC")
has "$WRITE" "gc.takeaway=" "--takeaway writes the headline"
has "$WRITE" "gc.takeaway_at=" "…its timestamp, which is when the wait started"
has "$WRITE" "gc.takeaway_by=" "…and its provenance"

# --- every human-state caller in the tree ---------------------------------------
# A human state routes to the park sentinel by default, so a `transition --to
# <human-state>` with neither --takeaway nor an explicit non-park --route is
# relying on the bead already carrying one. That is legitimate (the converse
# hold stamps first) but only when a stamp for THAT bead stands above it in the
# same block, so each site is listed.
echo "# human-state transition callers"
HUMAN_STATES=$(sed -n 's/^human_states = \[\(.*\)\]/\1/p' lifecycle/lifecycle.toml | tr -d '",')
for st in $HUMAN_STATES; do
  while IFS=: read -r f n _; do
    [ -n "$f" ] || continue
    skip_file "$f" && continue
    stmt=$(statement "$f" "$n")
    # The bead being transitioned, as written — the stamp that vouches for this
    # park has to name the same one.
    subj=$(printf '%s' "$stmt" | sed -n 's/.*transition[[:space:]]\{1,\}\([^[:space:]]\{1,\}\).*/\1/p')
    case "$stmt" in
      *"--takeaway"*) ok "$f:$n (--to $st) names what it waits for" ;;
      *"--route "[!h]*|*"--route \""[!h]*) ok "$f:$n (--to $st) routes off the park sentinel" ;;
      *) if stamps_takeaway_above "$f" "$n" "$subj"; then
           ok "$f:$n (--to $st) stamps ${subj}'s takeaway before transitioning"
         else
           bad "$f:$n parks with --to $st and records no question"
         fi ;;
    esac
  done < <(grep -rn -- "transition .* --to $st" --include='*.sh' --include='*.toml' --include='*.md' . 2>/dev/null | grep -v '^\./\.git/')
done

echo
echo "human-route-takeaway.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
