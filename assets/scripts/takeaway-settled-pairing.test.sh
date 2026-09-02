#!/usr/bin/env bash
# Tree-wide invariant: a headline is stamped with its own disposition.
#
# lifecycle/lifecycle.toml `[holds]` declares gc.takeaway a hold marker and
# names gc.takeaway_settled as the key that answers it, so a bead carrying the
# headline without that key is a wait doctor/check-wait-is-an-edge reports. The
# marker is REPLACED by every sitting and the key beside it is not, unless each
# writer rewrites both: a settled sign-off would otherwise answer for the park
# that follows it on the same bead, and the park would go unreported for as
# long as it stands.
#
# So every site that writes the marker writes its settled-key in the same
# statement — empty unless the writer means settled, which only
# `gc-helm.sh takeaway --no-wait` does. A new writer that stamps a headline and
# says nothing about the wait fails this suite.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2')" ;; esac; }

cd "$ROOT" || exit 1

# The pairing, read from the declaration rather than hardcoded: a rename there
# has to move this suite with it, and a suite pinned to the old key would pass
# while nothing wrote the new one.
LIFECYCLE=lifecycle/lifecycle.toml
PAIR=$(sed -n 's/^settled_keys = \["\([^"]*\)".*/\1/p' "$LIFECYCLE" | head -1)
MARKER="${PAIR%%=*}"; SETTLED="${PAIR#*=}"
if [ -n "$MARKER" ] && [ -n "$SETTLED" ] && [ "$MARKER" != "$PAIR" ]; then
  ok "the pairing is declared in $LIFECYCLE ($MARKER -> $SETTLED)"
else
  bad "no <marker>=<settled-key> pair in $LIFECYCLE [holds] settled_keys (read '$PAIR')"
  echo; echo "passed: $PASS  failed: $FAIL"; exit 1
fi
grep -q "\"$MARKER\"" "$LIFECYCLE" \
  && ok "…and the marker it answers is declared a hold marker" \
  || bad "$MARKER is paired but not in marker_keys — the pairing answers nothing"
grep -q "\"$SETTLED\"" "$LIFECYCLE" \
  && ok "…and the settled-key is in the metadata registry" \
  || bad "$SETTLED is written by the tree and registered nowhere in $LIFECYCLE"

# Files that STATE the rule rather than break it: the generated re-render, the
# specs and docs describing it, and the suites that test it.
skip_file() {
  case "${1#./}" in
    generated/*|specs/*|docs/*|*/README.md|README.md) return 0 ;;
    *.test.sh|*_test.go) return 0 ;;
    *) return 1 ;;
  esac
}

# The one logical statement CONTAINING <file>:<line>: the lines it continues
# onto with a trailing backslash, and the lines of an argument list still
# inside an open `(`. Both shapes ship — `gc bd update ... \` in a script and
# `ARGS+=(--set-metadata ...` in lifecycle.sh — and a match can land on any
# line of either. TOML """ blocks collapse backslash continuations at parse
# time, so the same join reads a formula's shell too.
statement() { # <file> <line>
  awk -v line="$2" '
    function opens(s) { return gsub(/\(/, "(", s) > gsub(/\)/, ")", s) }
    { l[NR] = $0 }
    END {
      start = line
      while (start > 1 && (l[start - 1] ~ /\\[[:space:]]*$/ || opens(l[start - 1]))) start--
      depth = 0
      for (i = start; i <= NR; i++) {
        buf = buf l[i] " "
        depth += gsub(/\(/, "(", l[i]) - gsub(/\)/, ")", l[i])
        if (l[i] !~ /\\[[:space:]]*$/ && depth <= 0) break
      }
      print buf
    }
  ' "$1"
}

echo "# every writer of $MARKER"
checked=0
while IFS=: read -r f n _; do
  [ -n "$f" ] || continue
  skip_file "$f" && continue
  stmt=$(statement "$f" "$n")
  checked=$((checked + 1))
  has "$stmt" "$SETTLED=" "$f:$n writes $SETTLED in the same statement"
done < <(grep -rn -- "--set-metadata" --include='*.sh' --include='*.toml' --include='*.md' . 2>/dev/null \
           | grep -v '^\./\.git/' | grep -F "$MARKER=")

[ "$checked" -gt 0 ] && ok "headline writers found and checked ($checked)" \
  || bad "no writer of $MARKER found — the discovery pattern has gone stale"

# Only the flag can say "settled". A site that hardcodes the value writes a
# disposition no caller asked for, and the one writer that may is the verb
# whose flag means it.
echo "# the settled value comes from the flag"
while IFS=: read -r f n _; do
  [ -n "$f" ] || continue
  skip_file "$f" && continue
  bad "$f:$n hardcodes a settled disposition; it is $SETTLED's writer only under --no-wait"
done < <(grep -rn -F -- "$SETTLED=1" --include='*.sh' --include='*.toml' --include='*.md' . 2>/dev/null \
           | grep -v '^\./\.git/')
ok "no site outside the verb stamps a settled disposition of its own"

HELM="$HERE/gc-helm.sh"
has "$(cat "$HELM")" "--no-wait) no_wait=1" "gc-helm.sh takeaway parses --no-wait"
has "$(cat "$HELM")" "$SETTLED=\$no_wait" "…and the flag is the only source of the value it stamps"
CONTRA=$(awk '/-n "\$no_wait" \] && \[ -n "\$waiting_ids" \]/,/^    fi$/' "$HELM")
has "${CONTRA:-<none>}" "exit 2" "…and a takeaway claiming both refuses before it writes"

# lifecycle.sh owns the stamp behind --takeaway, so --set must not be a second
# door to one half of it.
LC="$HERE/lifecycle.sh"
GUARD=$(grep -n -A1 -F "gc.takeaway|gc.takeaway_at" "$LC" | head -4)
has "${GUARD:-<none>}" "$SETTLED" "lifecycle.sh refuses --set on the settled-key too"

echo
echo "takeaway settled-key pairing: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
