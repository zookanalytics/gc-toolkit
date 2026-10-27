#!/usr/bin/env bash
# pack-self-location.test.sh — pack text reaches the pack's own files through
# gc, never by guessing where a checkout of the pack sits.
#
# Every pack text that runs a pack script calls the copy gc <binding>
# scripts-dir names (docs/pack-authoring.md, "Step text and skills reach pack
# scripts at runtime"). A guess names the pack only in a city laid out like
# this one: $GC_CITY_PATH/rigs/gc-toolkit is the pack only where a city clones
# it as a rig of that name, $GC_RIG_ROOT only in the pack's own rig, and
# git rev-parse --show-toplevel is whatever checkout the caller stands in, the
# branch under review included. A city that imports the pack from a URL has
# none of them.
#
#   1. No file under the pack's content directories, suites aside, finds pack
#      content through a loop over candidate directories, the city root joined
#      with rigs/gc-toolkit, the caller's checkout or rig root joined with a
#      pack directory, or GC_PACK_DIR in text an agent session runs, where gc
#      never sets it.
#   2. Each kind of text names the binding the way its rendering allows: a
#      formula drops the dot from {{binding_prefix}}, a prompt or fragment
#      renders {{ .BindingName }}, and a skill writes <binding> for the agent
#      to fill in.
#   3. A formula's resolver line, run under a stub gc, takes the directory gc
#      names and nothing else: empty when gc refuses the binding or a probe
#      fails, even with the script sitting in every directory the old lookup
#      tried.
#   4. With GC_BIN naming a real gc: a scratch city that imports this tree
#      from git, under another binding, pours a formula, and the poured step
#      reaches a pack script in the copy gc fetched into its cache.
#
# Hermetic: reads the pack's own files and runs extracted lines under a stub gc.
# Part 4 runs the real gc against a scratch city and a git repository it builds,
# with no live city, store or network, and is skipped when GC_BIN is unset.
#
# run-tests-scope: tree
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; [ -z "${2:-}" ] || printf '       %s\n' "$2"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/pack-self-location.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# The physical path: part 4 hands it to git inside a file:// URL, which a
# doubled slash or a symlinked prefix breaks.
TMP="$(cd "$TMP" && pwd -P)"

# The pack's content: every directory whose files an agent, an order or a
# pack command runs or reads. Suites are left out, since a fixture may lay out
# a city on purpose.
DIRS="formulas agents skills template-fragments assets/scripts doctor tools lifecycle orders commands"
( cd "$ROOT" && for d in $DIRS; do [ -d "$d" ] && find "$d" -type f; done ) \
  | grep -v -E '\.test\.sh$|/lint-learned\.d/' | LC_ALL=C sort > "$TMP/files"
scanned=$(grep -c . "$TMP/files" || true)
[ "$scanned" -ge 100 ] && ok "scanning $scanned files of pack content" \
  || bad "scanning pack content found only $scanned files under $DIRS; the scan is not reading the pack"

echo "── 1. no pack text guesses where the pack is ──"
# scan <label> <ERE> <a line it must flag> <a line it must pass> [<file filter>]
# reports every non-comment line of pack content the ERE matches. A shell or
# toml comment is prose about a lookup, not one. The two sample lines prove
# the ERE flags the form it names and passes the form that replaced it, so a
# clean scan is the pack being clean, not a pattern that matches nothing.
scan() {
  local label="$1" re="$2" flag="$3" pass="$4" only="${5:-.}" hits
  printf '%s\n' "$flag" | grep -q -E "$re" || bad "$label: the pattern does not flag its sample" "$flag"
  ! printf '%s\n' "$pass" | grep -q -E "$re" || bad "$label: the pattern flags the replacement" "$pass"
  hits=$(grep -E "$only" "$TMP/files" | while IFS= read -r f; do
           grep -n -E "$re" "$ROOT/$f" 2>/dev/null | grep -v -E '^[0-9]+:[[:space:]]*#' | sed "s#^#$f:#"
         done)
  if [ -z "$hits" ]; then ok "$label"; else bad "$label" "$(printf '%s\n' "$hits" | head -20)"; fi
}
RESOLVED='SCRIPTS=$(b='"'"'{{binding_prefix}}'"'"'; gc "${b%.}" scripts-dir) && [ -x "$SCRIPTS/escalate.sh" ] || SCRIPTS=""'
PACKDIRS='(assets|tools|formulas|agents|skills|template-fragments|lifecycle|commands|doctor|orders)'
scan "no text joins the city root with rigs/gc-toolkit" \
  '(GC_CITY_PATH|GC_CITY_ROOT|GC_CITY)[^/"'"'"' ]*/rigs/gc-toolkit' \
  '"${GC_CITY_PATH:-}/rigs/gc-toolkit/assets/scripts/escalate.sh" --subject x' "$RESOLVED"
scan "no text joins the caller's checkout (git rev-parse --show-toplevel) with a pack directory" \
  'show-toplevel[^)]*\)"?/'"$PACKDIRS"'([/"]|$)' \
  'TOOLS="$(git rev-parse --show-toplevel 2>/dev/null)/tools"' 'TOOLS="$(gc {{ .BindingName }} scripts-dir)/../../tools"'
scan "no text joins a rig root with a pack directory" \
  '(GC_RIG_ROOT|[^_A-Z]RIG_ROOT)[^/"'"'"' ]*/'"$PACKDIRS"'([/"]|$)' \
  'JOB="$RIG_ROOT/assets/scripts/detached-job.sh"' 'git -C "$RIG_ROOT" worktree add "$WT" --detach origin/main'
# A loop over the rig root or the caller's checkout can be looking for the
# rig's own content, such as the repository a commit is in, so the loop rule
# below judges what a loop probes for; GC_PACK_DIR and rigs/gc-toolkit name
# nothing but the pack.
scan "no loop tries GC_PACK_DIR or rigs/gc-toolkit as a candidate" \
  'for [A-Za-z_]+ in [^;]*(GC_PACK_DIR|rigs/gc-toolkit)' \
  'for c in "${GC_PACK_DIR:-}" "${GC_CITY_PATH:-}/rigs/gc-toolkit"; do' 'for root in "$(git rev-parse --show-toplevel 2>/dev/null)" "${GC_RIG_ROOT:-}"; do'
scan "no text an agent session runs reads GC_PACK_DIR, which gc sets only for orders and pack commands" \
  '\$\{?GC_PACK_DIR' '[ -x "${GC_PACK_DIR:-}/assets/scripts/escalate.sh" ]' "$RESOLVED" \
  '^(formulas|agents|skills|template-fragments)/'

# A loop over any candidate list that probes for a pack file is the same guess
# whatever its candidates are named.
loop_probes() { # <label> <file>
  awk -v f="$1" '
    /^[[:space:]]*#/ { next }
    match($0, /for [A-Za-z_]+ in /) {
      v = substr($0, RSTART + 4, RLENGTH - 8); start = NR; until = NR + 3
    }
    v != "" && NR <= until && (index($0, "\"$" v "/assets/") || index($0, "\"$" v "/tools/") || index($0, "\"$" v "/scripts/") || index($0, "\"${" v "}/assets/")) {
      print f ":" start ": a loop over candidates probes $" v " for a pack file"; v = ""
    }
    NR > until { v = "" }
  ' "$2"
}
printf '%s\n' 'for cand in "$A" "$B"; do' '  [ -x "$cand/assets/scripts/escalate.sh" ] && { X="$cand/assets/scripts"; break; }' 'done' > "$TMP/loop-sample"
[ -n "$(loop_probes sample "$TMP/loop-sample")" ] || bad "the loop rule flags a loop that probes its candidates for a pack file" "$(cat "$TMP/loop-sample")"
loops=$(while IFS= read -r f; do loop_probes "$f" "$ROOT/$f"; done < "$TMP/files")
if [ -z "$loops" ]; then ok "no loop probes candidate directories for a pack file"
else bad "no loop probes candidate directories for a pack file" "$(printf '%s\n' "$loops" | head -20)"; fi

echo "── 2. each kind of text names the binding its rendering carries ──"
FORMULA_FORM="\$(b='{{binding_prefix}}'; gc \"\${b%.}\" scripts-dir)"
calls=0; wrong=""
for f in "$ROOT"/formulas/*.toml; do
  while IFS= read -r line; do
    calls=$((calls + 1))
    case "$line" in
      *"$FORMULA_FORM"*) ;;
      *) wrong="$wrong${f##*/}: $line"$'\n' ;;
    esac
  done < <(grep -E 'gc [^ ]+ scripts-dir|scripts-dir\)' "$f" | grep -v -E '^description[[:space:]]*=' || true)
done
[ "$calls" -ge 100 ] && ok "the formulas call scripts-dir ($calls lines)" \
  || bad "the formulas call scripts-dir on only $calls lines; the scan is not reading them"
[ -z "$wrong" ] && ok "every formula call drops the dot from {{binding_prefix}}: $FORMULA_FORM" \
  || bad "every formula call drops the dot from {{binding_prefix}}" "$(printf '%s' "$wrong" | head -10)"
# A formula that names the var declares it with a default, which an order's
# pour takes (formula-binding-prefix-default.test.sh holds the default).
undeclared=""
for f in "$ROOT"/formulas/*.toml; do
  grep -qF "$FORMULA_FORM" "$f" || continue
  grep -Eq '^\[vars\.binding_prefix\][[:blank:]]*$' "$f" || undeclared="$undeclared ${f##*/}"
done
[ -z "$undeclared" ] && ok "every formula that resolves the pack declares [vars.binding_prefix]" \
  || bad "every formula that resolves the pack declares [vars.binding_prefix]" "missing in:$undeclared"

wrong=""
while IFS= read -r f; do
  case "$f" in agents/*.template.md|template-fragments/*.template.md) ;; *) continue ;; esac
  while IFS= read -r hit; do
    case "$hit" in
      *'gc {{ .BindingName }} scripts-dir'*|*'gc <binding> scripts-dir'*) ;;
      *) wrong="$wrong$f: $hit"$'\n' ;;
    esac
  done < <(grep -n -E 'gc [^ ]+ scripts-dir|gc [^ ]+ [^ ]+ scripts-dir' "$ROOT/$f" | grep -v -E 'gc (\{\{ \.BindingName \}\}|<binding>) scripts-dir' || true)
done < "$TMP/files"
[ -z "$wrong" ] && ok "every prompt and fragment call names {{ .BindingName }}, or <binding> for the agent to fill in" \
  || bad "every prompt and fragment call names {{ .BindingName }}, or <binding> for the agent to fill in" "$(printf '%s' "$wrong" | head -10)"

wrong=$(grep '^skills/' "$TMP/files" | while IFS= read -r f; do
  grep -n -E 'gc [^ ]+ scripts-dir' "$ROOT/$f" | grep -v 'gc <binding> scripts-dir' | sed "s#^#$f:#"
done)
[ -z "$wrong" ] && ok "every skill call writes <binding> for the agent to fill in" \
  || bad "every skill call writes <binding> for the agent to fill in" "$(printf '%s\n' "$wrong" | head -10)"

echo "── 3. a formula's resolver takes the directory gc names, and nothing else ──"
# The lines under test are the formulas' own: one that resolves the directory
# under a probe, and one that resolves a script's path.
DIR_LINE=$(grep -h -m1 -E "^SCRIPTS=\\\$\(b='\{\{binding_prefix\}\}'; gc \"\\\$\{b%\.\}\" scripts-dir\) && \[ -x \"\\\$SCRIPTS/escalate\.sh\" \] \|\| SCRIPTS=\"\"\$" "$ROOT/formulas/mol-polecat-work.toml" || true)
PATH_LINE=$(grep -h -m1 -E "^SC=\"\\\$\(b='\{\{binding_prefix\}\}'; gc \"\\\$\{b%\.\}\" scripts-dir\)/step-close\.sh\" && \[ -x \"\\\$SC\" \] \|\| SC=\"\"\$" "$ROOT/formulas/mol-polecat-work.toml" || true)
[ -n "$DIR_LINE" ] && ok "mol-polecat-work carries a directory resolver under an escalate.sh probe" \
  || bad "mol-polecat-work carries a directory resolver under an escalate.sh probe" "no such line"
[ -n "$PATH_LINE" ] && ok "mol-polecat-work carries a step-close.sh path resolver" \
  || bad "mol-polecat-work carries a step-close.sh path resolver" "no such line"

# gc answers `kit scripts-dir` with the pack, and refuses every other binding
# the way the real gc refuses an unknown command.
mkdir -p "$TMP/bin" "$TMP/pack/assets/scripts" "$TMP/away"
cat > "$TMP/bin/gc" <<'STUB'
#!/usr/bin/env bash
[ "${1:-} ${2:-}" = "kit scripts-dir" ] && [ -n "${STUB_PACK:-}" ] && { printf '%s\n' "$STUB_PACK"; exit 0; }
echo "gc: unknown command \"${1:-}\"" >&2
exit 1
STUB
chmod +x "$TMP/bin/gc"
printf '#!/bin/sh\nexit 0\n' > "$TMP/pack/assets/scripts/escalate.sh"
printf '#!/bin/sh\nexit 0\n' > "$TMP/pack/assets/scripts/step-close.sh"
chmod +x "$TMP/pack/assets/scripts/escalate.sh" "$TMP/pack/assets/scripts/step-close.sh"
# Every place the old lookup tried holds the scripts too, so a line that still
# guessed would find one: the rig root, the city's rigs/gc-toolkit, and the
# git checkout the line runs in.
for d in rig city/rigs/gc-toolkit checkout; do
  mkdir -p "$TMP/$d/assets/scripts"
  cp "$TMP/pack/assets/scripts/"*.sh "$TMP/$d/assets/scripts/"
done
git -C "$TMP/checkout" init -q 2>/dev/null

# resolve <binding_prefix> <line> <var>: the var's value after the line runs.
resolve() {
  local line="${2//\{\{binding_prefix\}\}/$1}"
  ( cd "$TMP/checkout" && PATH="$TMP/bin:$PATH" GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="$TMP/city" \
      GC_PACK_DIR="$TMP/rig" STUB_PACK="${STUB_PACK-$TMP/pack/assets/scripts}" \
      bash -c "$line"'; printf "%s" "${'"$3"'}"' 2>/dev/null )
}
if [ -n "$DIR_LINE" ]; then
  eq_() { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1', want '$2'"; fi; }
  eq_ "$(resolve kit. "$DIR_LINE" SCRIPTS)" "$TMP/pack/assets/scripts" "the bound binding resolves the directory gc names"
  eq_ "$(resolve other. "$DIR_LINE" SCRIPTS)" "" "a binding gc does not know resolves nothing, though every old candidate holds the script"
  eq_ "$(resolve '' "$DIR_LINE" SCRIPTS)" "" "an empty binding_prefix resolves nothing: gc refuses the empty command"
  eq_ "$(resolve '{{binding_prefix}}' "$DIR_LINE" SCRIPTS)" "" "an unrendered {{binding_prefix}} resolves nothing"
  rm "$TMP/pack/assets/scripts/escalate.sh"
  eq_ "$(resolve kit. "$DIR_LINE" SCRIPTS)" "" "a pack that lacks the probed script resolves nothing, so the guard after it stops"
  printf '#!/bin/sh\nexit 0\n' > "$TMP/pack/assets/scripts/escalate.sh"; chmod +x "$TMP/pack/assets/scripts/escalate.sh"
  eq_ "$(STUB_PACK='' resolve kit. "$DIR_LINE" SCRIPTS)" "" "a gc that answers nothing resolves nothing"
fi
if [ -n "$PATH_LINE" ]; then
  eq_ "$(resolve kit. "$PATH_LINE" SC)" "$TMP/pack/assets/scripts/step-close.sh" "the path form resolves the pack's own script"
  eq_ "$(resolve other. "$PATH_LINE" SC)" "" "the path form resolves nothing for an unknown binding, never a bare /step-close.sh"
fi

echo "── 4. a city that imports the pack from git reaches the pack's scripts in its cache ──"
if [ -z "${GC_BIN:-}" ] || [ ! -x "${GC_BIN:-}" ]; then
  printf '  SKIP  GC_BIN names no gc, so the remote layout was not exercised (set GC_BIN to run it)\n'
else
  # This tree, committed into a repository of its own, is the pack the city
  # imports from git; the scratch city clones nothing as a rig. The city
  # imports it as kit, so the binding a step names is the one its pour carries.
  SRC="$TMP/src"; CITY="$TMP/city"; GCH="$TMP/gc-home"
  mkdir -p "$SRC" "$CITY" "$GCH" "$TMP/real-gc" "$TMP/away"
  ln -s "$GC_BIN" "$TMP/real-gc/gc"
  ( cd "$ROOT" && git ls-files -co --exclude-standard -z | xargs -0 tar -cf - 2>/dev/null ) | tar -xf - -C "$SRC"
  ( cd "$SRC" && git init -q -b main && git add -A \
      && git -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q -m "pack" )
  SHA=$(git -C "$SRC" rev-parse HEAD 2>/dev/null)
  printf '[workspace]\nprovider = "claude"\n\n[providers.claude]\nbase = "builtin:claude"\n\n[providers.codex]\nbase = "builtin:codex"\n\n[providers.gemini]\nbase = "builtin:gemini"\n' > "$CITY/city.toml"
  printf '[pack]\nname = "remote-probe"\nschema = 2\n\n[imports.kit]\nsource = "file://%s"\nversion = "sha:%s"\n' "$SRC" "$SHA" > "$CITY/pack.toml"
  # in_city <command...> — the real gc in the scratch city, with a file store,
  # and nothing in the environment naming a live city, rig or store.
  in_city() {
    (cd "${IN_DIR:-$CITY}" && env -u GC_CITY_PATH -u GC_RIG -u GC_RIG_ROOT -u GC_DIR -u GC_PACK_DIR \
        -u BEADS_DIR -u GC_BEADS_SCOPE_ROOT -u GC_DOLT_PORT -u BEADS_DOLT_SERVER_PORT -u BASH_ENV -u ENV \
        GC_CITY="$CITY" GC_HOME="$GCH" GC_BEADS=file PATH="$TMP/real-gc:$PATH" "$@")
  }
  in_city gc import install >"$TMP/install.out" 2>&1 \
    && ok "the city installs the pack from git" \
    || bad "the city installs the pack from git" "$(tail -3 "$TMP/install.out")"
  KIT=$(in_city gc kit scripts-dir 2>/dev/null)
  case "$KIT" in
    "$ROOT"*|"$SRC"*|"") bad "gc kit scripts-dir names the copy gc fetched, not this checkout or its source" "named '$KIT'" ;;
    *) ok "gc kit scripts-dir names the copy gc fetched, not this checkout or its source" ;;
  esac
  COOK=$(in_city gc formula cook mol-visit --var subject=rp-subj --var visit=probe --var binding_prefix=kit. --json 2>/dev/null)
  STEP=$(printf '%s' "$COOK" | jq -r '.id_mapping["mol-visit.file-visit"] // empty' 2>/dev/null)
  [ -n "$STEP" ] && ok "the city pours mol-visit from the fetched pack" \
    || bad "the city pours mol-visit from the fetched pack" "cook answered: $COOK"
  jq -r --arg id "$STEP" '[.. | objects | select(.id? == $id) | .description] | .[0] // empty' "$CITY/.gc/beads.json" > "$TMP/step.md" 2>/dev/null
  LINE=$(grep -m1 -E "^VI=\"\\\$\(b='kit\.'; gc " "$TMP/step.md")
  [ -n "$LINE" ] && ok "the poured step names the binding its pour carried" \
    || bad "the poured step names the binding its pour carried" "$(grep -m1 'scripts-dir' "$TMP/step.md")"
  GOT=$(IN_DIR="$TMP/away" in_city bash -c "$LINE"'; . "$VI" && printf "%s|%s" "$VI" "${VISIT_IDENTITY_JQ:+loaded}"' 2>/dev/null)
  if [ -n "$KIT" ] && [ "$GOT" = "$KIT/visit-identity.sh|loaded" ]; then
    ok "the poured step sources the pack's visit-identity.sh from the fetched copy"
  else
    bad "the poured step sources the pack's visit-identity.sh from the fetched copy" "got '$GOT'"
  fi
fi

printf '\npack-self-location: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
