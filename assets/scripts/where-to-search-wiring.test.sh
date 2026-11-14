#!/usr/bin/env bash
# where-to-search-wiring.test.sh — every agent this repository ships renders
# the where-to-search rule once, and no prompt cites a formula by its file.
#
# An agent that does not know where a thing lives searches the disk for it, and
# on macOS a search of the home folder, /Users or the disk root waits on a
# privacy prompt that nobody answers. The where-to-search fragment says where
# to search and where to look up everything else. A new agent, or a prompt that
# drops the include, renders without the rule, and nothing at runtime says so.
# So this suite reads each agent's seed-audit render, which is its prompt as gc
# composes it, nested fragments included.
#
#   (1) the fragment defines where-to-search;
#   (2) every agent under agents/, and under a sub-pack's agents/ in packs/,
#       renders the rule's heading exactly once, except two: the mechanik,
#       whose prime has no room for it under the session-start cap
#       mechanik-prime-cap.test.sh holds it to, and the dog, whose prompt the
#       deletion plan retires (tools/deletion-plan.tsv), so it takes no new
#       text;
#   (3) no prompt or fragment cites a formula by its file path, which reads as
#       a file to go and find, where `gc formula show <name>` reads it.
#
# run-tests-scope: tree
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
FRAG="$ROOT/template-fragments/where-to-search.template.md"
RENDERS="$ROOT/generated/seed-audit/agents"
HEADING='## Where to search'
EXEMPT=" agents/mechanik agents/dog "

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }

[ -s "$FRAG" ] || { echo "missing $FRAG" >&2; exit 1; }

# --- (1) the fragment -----------------------------------------------------
if grep -qE '^\{\{-? *define "where-to-search" *-?\}\}' "$FRAG"; then
  ok "the fragment defines where-to-search"
else
  bad "the fragment defines where-to-search" "$FRAG has no define of that name"
fi
if grep -qxF "$HEADING" "$FRAG"; then
  ok "the fragment carries the heading this suite counts"
else
  bad "the fragment carries the heading this suite counts" "no line '$HEADING' in $FRAG: update HEADING"
fi

# --- (2) every agent renders it once --------------------------------------
# A render is named for the agent, or for <binding>.<agent> where agents from
# two packs share a name, and the render binds each pack under the name its
# pack.toml gives it. The loader skips a directory whose name starts with `_`,
# which holds a prompt that agents share and is no agent of its own.
pack_name() { sed -n 's/^name = "\(.*\)"$/\1/p' "$1/pack.toml" | head -n 1; }
for dir in "$ROOT"/agents/*/ "$ROOT"/packs/*/agents/*/; do
  [ -d "$dir" ] || continue
  dir="${dir%/}"
  name="$(basename "$dir")"
  rel="${dir#"$ROOT"/}"
  case "$name" in _*) continue ;; esac
  case "$EXEMPT" in *" $rel "*) continue ;; esac
  pack="$(pack_name "$(dirname "$(dirname "$dir")")")"
  if [ -z "$pack" ]; then
    bad "$rel has a pack name" "no [pack] name in the pack.toml two levels above it"
    continue
  fi
  render=""
  for cand in "$RENDERS/$name.md" "$RENDERS/$pack.$name.md"; do
    [ -f "$cand" ] && { render="$cand"; break; }
  done
  if [ -z "$render" ]; then
    bad "$rel has a seed-audit render" "none under generated/seed-audit/agents: run assets/scripts/render-seed-audit.sh"
    continue
  fi
  n="$(grep -cxF "$HEADING" "$render")"
  if [ "$n" -eq 1 ]; then
    ok "$rel renders the rule once"
  else
    bad "$rel renders the rule once" "$(basename "$render") carries '$HEADING' $n times: compose {{ template \"where-to-search\" . }} once"
  fi
done

# --- (3) no formula cited by its file -------------------------------------
cited="$(grep -nE 'formulas/[A-Za-z0-9._-]+\.toml' "$ROOT"/agents/*/prompt.template.md "$ROOT"/template-fragments/*.template.md \
  "$ROOT"/packs/*/agents/*/prompt.template.md "$ROOT"/packs/*/template-fragments/*.template.md 2>/dev/null | sed "s|^$ROOT/||")"
if [ -z "$cited" ]; then
  ok "no prompt or fragment cites a formula by its file path"
else
  bad "no prompt or fragment cites a formula by its file path" "name it for \`gc formula show <name>\` instead: $cited"
fi

printf '\nwhere-to-search-wiring: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
