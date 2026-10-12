#!/usr/bin/env bash
# Hermetic test for the pre-existing-failure dedup at its two call sites: the
# refinery's `handle-failures` step (mol-refinery-patrol.toml, the
# preexisting-failure-dedup block) and a polecat's `preflight-tests` step
# (mol-polecat-work.toml, the preflight-failure-lookup, preflight-fix-landed-check
# and preflight-failure-file blocks). Both must find the tracker a gate already
# filed for the same red and file no second one.
#
# A probe that reads a failure as "no duplicate" files a fresh P1 on every
# patrol. bd answers a flag it does not have, such as `--search`, on stderr
# with an EMPTY stdout, and a probe that matches only the title loses a tracker
# its fixer retitled to name the fix. Both gates go through
# assets/scripts/preexisting-failure.sh, and the load-bearing parts pinned here
# are:
#   1. the KEY is derived by the script from the failing test, target or linted
#      file, and the lookup and the filing use the same key;
#   2. the lookup matches the failure_key stamp, so a RETITLED tracker is still
#      found, and the key in a bug's title, so a tracker filed before the stamp
#      is too;
#   3. it reads every live status a tracker can hold, and leaves closed ones
#      out: a red that outlives a landed fix is new information;
#   4. an unreadable lookup is UNKNOWN, never "no duplicate": the refinery files
#      nothing and merges nothing, and the polecat tells a human;
#   5. the filing carries a BODY in -d, the field this pack's readers read, with
#      the raw log intact, and the stamp rides the create;
#   6. the refinery's observed-on branch comes off a work-bead read that is
#      SHAPE-checked, because `gc bd show` fails open and answers an OBJECT when
#      no id resolves, both at exit 0.
#
# This EXECUTES the real snippets extracted verbatim from the formulas (between
# the markers) against a fake `gc` and the real script, so the test cannot drift
# from the shipped instruction. No live city, Dolt, network, or PRs.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
REFINERY="$ROOT/formulas/mol-refinery-patrol.toml"
POLECAT="$ROOT/formulas/mol-polecat-work.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-preexisting-failure-dedup-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
hasin() { grep -qF -- "$2" <<< "$1"; }
has()   { if hasin "$1" "$2"; then ok "$3"; else bad "$3 (missing '$2')"; fi; }
hasnt() { if hasin "$1" "$2"; then bad "$3 (found '$2')"; else ok "$3"; fi; }

mkdir -p "$TMP/bin" "$TMP/cwd" "$TMP/nopack"

# --- gc stub: a JSON bead store behind the reads and writes both gates make. ---
#   gc runtime drain-ack   -> recorded as DRAIN
#   gc mail send ...       -> recorded as MAIL|<args>
#   gc convoy status <id>  -> one tracked member, work-1
#   gc bd list ...         -> filtered the way bd filters: --status takes one
#                             comma list, --type and --metadata-field match
#                             exactly, --title-contains is a case-insensitive
#                             substring, --closed-after compares the close time.
#                             LIST_SCENARIO=unreadable answers an EMPTY stdout
#                             at exit 0, bd's fail-open shape.
#   gc bd show work-1      -> one payload per SHOW_SCENARIO:
#       target     -> metadata.target set, the branch the body must name
#       notarget   -> metadata carries no target, so the formula default applies
#       unreadable -> EMPTY stdout, exit 0
#       noresolve  -> the OBJECT bd answers, still at exit 0, when no id resolves
#   gc bd show <other>     -> the bead from the store
#   gc bd create ...       -> appends the bead, --metadata merged in, and records
#                             CREATE plus the flags the body travelled in
#                             (STUB_CREATE_FAIL refuses and files nothing)
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
set -u
STORE="${STUB_STORE:?}"
printf '%s\n' "$*" >> "${STUB_LOG:?}"
case "${1:-}" in
  runtime) echo "DRAIN" >> "$FAKE_META"; exit 0 ;;
  mail) shift 2; printf 'MAIL|%s\n' "$*" >> "$FAKE_META"; exit 0 ;;
  convoy) printf '{"children":[{"id":"work-1"}]}\n'; exit 0 ;;
  bd) ;;
  *) exit 0 ;;
esac
shift
case "${1:-}" in
  list)
    [ "${LIST_SCENARIO:-}" = "unreadable" ] && exit 0
    shift
    st=""; ty=""; tc=""; after=""; fields=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --status=*) st="${1#--status=}" ;;
        --status|-s) shift; st="${1:-}" ;;
        --type=*) ty="${1#--type=}" ;;
        --type|-t) shift; ty="${1:-}" ;;
        --title-contains) shift; tc="${1:-}" ;;
        --metadata-field) shift; fields+=("${1:-}") ;;
        --closed-after) shift; after="${1:-}" ;;
      esac
      shift || true
    done
    out=$(cat "$STORE")
    [ -n "$st" ] && out=$(printf '%s' "$out" | jq -c --arg st ",$st," '[ .[] | select((.status // "open") as $s | $st | contains("," + $s + ",")) ]')
    [ -n "$ty" ] && out=$(printf '%s' "$out" | jq -c --arg t "$ty" '[ .[] | select((.issue_type // "") == $t) ]')
    [ -n "$tc" ] && out=$(printf '%s' "$out" | jq -c --arg t "$tc" '[ .[] | select((.title // "") | ascii_downcase | contains($t | ascii_downcase)) ]')
    for f in ${fields[@]+"${fields[@]}"}; do
      out=$(printf '%s' "$out" | jq -c --arg k "${f%%=*}" --arg v "${f#*=}" '[ .[] | select(((.metadata // {})[$k] // "") == $v) ]')
    done
    [ -n "$after" ] && out=$(printf '%s' "$out" | jq -c --arg a "$after" '[ .[] | select((.closed_at // "") >= $a) ]')
    printf '%s\n' "$out" ;;
  show)
    shift; id="${1:-}"
    if [ "$id" = "work-1" ]; then
      case "${SHOW_SCENARIO:-target}" in
        target)     printf '[{"id":"work-1","metadata":{"target":"release/x"}}]\n' ;;
        notarget)   printf '[{"id":"work-1","metadata":{}}]\n' ;;
        unreadable) : ;;
        noresolve)  printf '{"error":"no issues found matching the provided IDs","schema_version":1}\n' ;;
      esac
      exit 0
    fi
    out=$(jq -c --arg id "$id" '[ .[] | select(.id == $id) ]' "$STORE")
    if [ "$(printf '%s' "$out" | jq 'length')" = "0" ]; then
      echo '{"error":"no issues found matching the provided IDs"}'
    else
      printf '%s\n' "$out"
    fi ;;
  create)
    [ -n "${STUB_CREATE_FAIL:-}" ] && { echo "bd: create refused" >&2; exit 1; }
    shift
    echo "CREATE" >> "$FAKE_META"
    title=""; body=""; ty="task"; meta="{}"
    while [ $# -gt 0 ]; do
      case "$1" in
        --title) shift; title="${1:-}" ;;
        --title=*) title="${1#--title=}" ;;
        -d|--description) shift; body="${1:-}" ;;
        --design|--design-file) shift; echo "DESIGN_USED" >> "$FAKE_META" ;;
        --type) shift; ty="${1:-}" ;;
        --type=*) ty="${1#--type=}" ;;
        --metadata) shift; meta="${1:-}" ;;
      esac
      shift || true
    done
    n=$(cat "$STUB_SEQ" 2>/dev/null || echo 0); n=$((n + 1)); printf '%s' "$n" > "$STUB_SEQ"
    jq -c --arg id "tk-new$n" --arg t "$title" --arg d "$body" --arg ty "$ty" --argjson m "$meta" \
      '. + [{id: $id, status: "open", issue_type: $ty, title: $t, description: $d, metadata: $m, closed_at: null}]' \
      "$STORE" > "$STORE.n" && mv "$STORE.n" "$STORE"
    printf '{"id":"tk-new%s"}\n' "$n" ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

export PATH="$TMP/bin:$PATH"
export FAKE_META="$TMP/meta" STUB_STORE="$TMP/store.json" STUB_LOG="$TMP/gc.log" STUB_SEQ="$TMP/seq"
unset GC_CITY_PATH GC_RIG

# bead <id> <status> <type> <title> [<metadata json>] [<closed_at>]
bead() {
  jq -nc --arg id "$1" --arg st "$2" --arg ty "$3" --arg t "$4" \
        --argjson m "${5:-null}" --arg c "${6:-}" \
    '{id: $id, status: $st, issue_type: $ty, title: $t, metadata: $m,
      closed_at: (if $c == "" then null else $c end)}'
}
store() {
  local IFS=,
  printf '[%s]\n' "$*" > "$STUB_STORE"
  : > "$STUB_LOG"; : > "$FAKE_META"; rm -f "$STUB_SEQ"
}
created() { grep -c '^CREATE$' "$FAKE_META"; }
field() { jq -r --arg id "$1" ".[] | select(.id == \$id) | $2" "$STUB_STORE"; }

# extract <toml> <marker> <out> — the lines between `# >>> <marker>` and
# `# <<< <marker>`; prints how many blocks carried the marker.
extract() {
  awk -v m="$2" -v out="$3" '
    $0 ~ "# >>> " m "$" { n++; f=1; next }
    $0 ~ "# <<< " m "$" { f=0; next }
    f { print > out }
    END { print n + 0 }
  ' "$1"
}

LOG_LINE='--- FAIL: test_widget_rebase (0.12s) internal/widget: want `ok`, got $STATUS'

# ============================================================================
# The refinery: handle-failures
# ============================================================================
eq "$(extract "$REFINERY" preexisting-failure-dedup "$TMP/refinery.sh")" "1" "refinery: one block between the preexisting-failure-dedup markers"
# The shipped snippet carries placeholders; substitute concrete values so the
# block is executable, exactly as the refinery would fill them in. The stand-in
# log carries a backtick and a $ on purpose: real failure output does, and they
# must reach the bead as text rather than running.
sed -i.bak -e 's/<failing test function>/test_widget_rebase/' \
  -e 's|<the check that failed, the package or target it ran in, and its raw output>|--- FAIL: test_widget_rebase (0.12s) internal/widget: want `ok`, got $STATUS|' \
  -e 's/{{target_branch}}/main/g' "$TMP/refinery.sh" && rm -f "$TMP/refinery.sh.bak"
REF_TMPL="$TMP/refinery.sh"

# refinery [show-scenario] [list-scenario] [block] -> the block's exit code.
# It runs from a cwd outside any checkout, with GC_RIG_ROOT naming this one, so
# the block resolves the real script the way a refinery does.
refinery() {
  if (cd "$TMP/cwd" && SHOW_SCENARIO="${1:-target}" LIST_SCENARIO="${2:-}" GC_RIG_ROOT="${PACK:-$ROOT}" WORK=work-1 \
        bash "${3:-$REF_TMPL}" >"$TMP/out" 2>&1); then
    echo 0
  else
    echo "$?"
  fi
}

KEY="test_widget_rebase"
echo "# refinery: a live tracker exists -> proceed, file nothing"
store "$(bead tk-dup open bug "Pre-existing failure: $KEY (fails on main)")"
eq "$(refinery)" "0" "(A) an unstamped twin found by its title -> proceeds (exit 0)"
eq "$(created)" "0" "(A) no second bead filed"
has "$(cat "$STUB_LOG")" "--title-contains $KEY" "(A) the probe uses --title-contains with the derived key"
hasnt "$(cat "$STUB_LOG")" "--search" "(A) the probe never passes --search"
store "$(bead tk-fix in_progress bug "Make widget rebase wait for the lock" "{\"failure_key\":\"$KEY\"}")"
eq "$(refinery)" "0" "(A2) a RETITLED twin -> proceeds (exit 0)"
eq "$(created)" "0" "(A2) the retitled twin is found by its stamp; nothing filed"
has "$(cat "$TMP/out")" "already filed as tk-fix" "(A2) the cited tracker is the retitled one"
for st in open in_progress blocked deferred hooked pinned; do
  store "$(bead tk-twin "$st" bug "Renamed by its fixer" "{\"failure_key\":\"$KEY\"}")"
  eq "$(refinery)/$(created)" "0/0" "(H) a $st twin is live -> nothing filed"
done

echo "# refinery: no tracker -> file exactly one, keyed and stamped"
store
eq "$(refinery)" "0" "(B) a readable empty result -> proceeds (exit 0)"
eq "$(created)" "1" "(B) exactly one bead filed"
eq "$(field tk-new1 .title)" "Pre-existing failure: $KEY" "(B) the title carries the probe's key and nothing unsubstituted"
eq "$(field tk-new1 .metadata.failure_key)" "$KEY" "(B) the key is stamped in the create, so a retitle cannot hide it"
eq "$(grep -c '^DESIGN_USED$' "$FAKE_META")" "0" "(B) the evidence is not filed as --design, which nothing reads"
BODY=$(field tk-new1 .description)
has "$BODY" "$LOG_LINE" "(B) the body carries the raw failure output verbatim (quoted heredoc: nothing expanded)"
has "$BODY" "Observed on release/x while merging work-1" "(B) the body names the branch the failure was observed on"
has "$(cat "$TMP/out")" "tracked as tk-new1" "(B) the filed id is reported for the merge notes"
eq "$(refinery)/$(created)" "0/1" "(B) the next patrol finds the bead the last one filed"
jq -c 'map(if .id == "tk-new1" then .title = "Make widget rebase wait for the lock" else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
eq "$(refinery)/$(created)" "0/1" "(B) and still finds it once its fixer retitles it"

echo "# refinery: a closed tracker does not count"
store "$(bead tk-done closed bug "Pre-existing failure: $KEY" "{\"failure_key\":\"$KEY\"}" 2026-10-09T08:00:00Z)"
eq "$(refinery)/$(created)" "0/1" "(I) a closed twin -> exactly one new bead: a red that outlives a fix is new"

echo "# refinery: unknown files nothing and merges nothing"
store "$(bead tk-dup open bug "Pre-existing failure: $KEY")"
eq "$(refinery target unreadable)" "1" "(C) an unreadable probe -> fail-closed defer (exit 1)"
eq "$(created)" "0" "(C) nothing filed on an unreadable probe"
has "$(cat "$FAKE_META")" "DRAIN" "(C) the refinery drains rather than merging"
has "$(cat "$TMP/out")" "duplicate probe unreadable" "(C) the block's own probe check is what stops it"
store
eq "$(refinery notarget)" "0" "(E) a readable bead with no target -> proceeds (exit 0)"
has "$(field tk-new1 .description)" "Observed on main while merging work-1" "(E) an unset metadata.target falls back to the formula default"
store
eq "$(refinery unreadable)/$(created)" "1/0" "(F) an unreadable work-bead read -> defers, nothing filed"
store
eq "$(refinery noresolve)/$(created)" "1/0" "(G) an unresolved work bead (object payload) -> defers, nothing filed"
store
eq "$(STUB_CREATE_FAIL=1 refinery)" "1" "(J) a filing that did not land -> no merge (exit 1)"
store
eq "$(PACK="$TMP/nopack" refinery)/$(created)" "1/0" "(K) the script not found -> no merge, nothing filed"
sed 's/test_widget_rebase/<failing test function>/' "$REF_TMPL" > "$TMP/refinery-placeholder.sh"
store
eq "$(refinery target "" "$TMP/refinery-placeholder.sh")/$(created)" "1/0" "(L) an unsubstituted key placeholder -> no merge, nothing filed"

# ============================================================================
# The polecat: preflight-tests 3a-3e
# ============================================================================
render() { sed -e 's/{{convoy_id}}/cv-1/g' -e 's/{{escalation_target}}/human/g' -e 's/{{base_branch}}/main/g' "$1" > "$1.r" && mv "$1.r" "$1"; }
eq "$(extract "$POLECAT" preflight-failure-lookup "$TMP/lookup.sh")" "1" "polecat: one preflight-failure-lookup block"
eq "$(extract "$POLECAT" preflight-fix-landed-check "$TMP/landed.sh")" "1" "polecat: one preflight-fix-landed-check block"
eq "$(extract "$POLECAT" preflight-failure-file "$TMP/file.sh")" "1" "polecat: one preflight-failure-file block"
render "$TMP/lookup.sh"; render "$TMP/landed.sh"; render "$TMP/file.sh"
sed -i.bak 's|<failing test function, e.g. TestFoo/some_subtest>|TestWidget/rebase_case|' "$TMP/lookup.sh" && rm -f "$TMP/lookup.sh.bak"
echo 'echo "EXISTING=$EXISTING LOOKUP_RC=$LOOKUP_RC KEY=$SYMPTOM_KEY"' >> "$TMP/lookup.sh"
echo 'echo "CLOSED_MATCH=$CLOSED_MATCH CLOSED_RC=$CLOSED_RC"' >> "$TMP/landed.sh"
sed -i.bak -e 's|<the full failure: the test or check, its subtest or lines, the package, and the raw output>|--- FAIL: TestWidget/rebase_case (0.12s) want `ok`, got $STATUS|' \
  -e 's|<short description>|rebase loses the lock|' "$TMP/file.sh" && rm -f "$TMP/file.sh.bak"

# polecat <block> [list-scenario] -> the block's stdout. GC_PACK_DIR names this
# checkout, the first place the block's loop looks. The key and the work bead
# the later blocks reuse from 3b are passed in.
polecat() {
  (cd "$TMP/cwd" && LIST_SCENARIO="${2:-}" GC_PACK_DIR="$ROOT" SYMPTOM_KEY=TestWidget WORK_BEAD_ID=work-1 \
     bash "$1" 2>/dev/null)
}
PKEY="TestWidget"

echo "# polecat 3a/3b: the lookup"
store "$(bead tk-fix in_progress bug "Make widget rebase wait for the lock" "{\"failure_key\":\"$PKEY\"}")"
OUT=$(polecat "$TMP/lookup.sh")
has "$OUT" "KEY=$PKEY" "3a: the key is the test function, its subtest dropped"
has "$OUT" "EXISTING=tk-fix LOOKUP_RC=0" "3b: a RETITLED tracker is found by its stamp"
store "$(bead tk-old blocked bug "Pre-existing failure: $PKEY — rebase loses the lock")"
has "$(polecat "$TMP/lookup.sh")" "EXISTING=tk-old LOOKUP_RC=0" "3b: an unstamped tracker is found by its title, in a blocked status 3b once missed"
store
has "$(polecat "$TMP/lookup.sh")" "EXISTING= LOOKUP_RC=0" "3b: no tracker -> an empty, successful lookup"
eq "$(grep -c '^MAIL|' "$FAKE_META")" "0" "3b: a successful lookup mails nobody"
OUT=$(polecat "$TMP/lookup.sh" unreadable)
case "$OUT" in *"LOOKUP_RC=0"*) bad "3b: an unreadable store reads as a successful lookup" ;; *) ok "3b: an unreadable store fails the lookup" ;; esac
has "$(cat "$FAKE_META")" "MAIL|human -s NOTICE: main pre-flight failed, dedupe lookup broken" "3b: the broken lookup is mailed to the escalation target"
sed 's/TestWidget\/rebase_case/<failing test function, e.g. TestFoo\/some_subtest>/' "$TMP/lookup.sh" > "$TMP/lookup-placeholder.sh"
store
OUT=$(polecat "$TMP/lookup-placeholder.sh")
case "$OUT" in *"LOOKUP_RC=0"*) bad "3b: an unsubstituted key placeholder reads as a successful lookup" ;; *) ok "3b: an unsubstituted key placeholder fails the lookup" ;; esac

echo "# polecat 3d: the landed-fix check"
RECENT=$(date -u -d '1 day ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-1d +%Y-%m-%dT%H:%M:%SZ)
store "$(bead tk-landed closed bug "Make widget rebase wait for the lock" "{\"failure_key\":\"$PKEY\"}" "$RECENT")"
has "$(polecat "$TMP/landed.sh")" "CLOSED_MATCH=tk-landed CLOSED_RC=0" "3d: a retitled tracker closed this week is found by its stamp"
store "$(bead tk-landed closed bug "Make widget rebase wait for the lock" "{\"failure_key\":\"$PKEY\"}" 2020-01-01T00:00:00Z)"
has "$(polecat "$TMP/landed.sh")" "CLOSED_MATCH= CLOSED_RC=0" "3d: one closed long ago is no recent fix"
OUT=$(polecat "$TMP/landed.sh" unreadable)
case "$OUT" in *"CLOSED_RC=0"*) bad "3d: an unreadable store reads as a successful check" ;; *) ok "3d: an unreadable store fails the check" ;; esac

echo "# polecat 3e: the filing"
store
polecat "$TMP/file.sh" >/dev/null
eq "$(created)" "1" "3e: exactly one bead filed"
eq "$(field tk-new1 .title)" "Pre-existing failure: $PKEY — rebase loses the lock" "3e: the title carries the key, then the summary"
eq "$(field tk-new1 .metadata.failure_key)" "$PKEY" "3e: the key is stamped in the create"
eq "$(grep -c '^DESIGN_USED$' "$FAKE_META")" "0" "3e: the evidence is not filed as --design"
has "$(field tk-new1 .description)" '--- FAIL: TestWidget/rebase_case (0.12s) want `ok`, got $STATUS' "3e: the raw log reaches the body verbatim"
has "$(field tk-new1 .description)" "Observed on main while starting work-1" "3e: the body names the base branch and the work bead"
has "$(cat "$FAKE_META")" "Tracked as: tk-new1" "3e: the notice names the tracker"
store "$(bead tk-race open bug "Pre-existing failure: $PKEY")"
polecat "$TMP/file.sh" >/dev/null
eq "$(created)" "0" "3e: a tracker another gate filed since the lookup is not duplicated"
has "$(cat "$FAKE_META")" "Tracked as: tk-race" "3e: the notice names that tracker"
store
(cd "$TMP/cwd" && STUB_CREATE_FAIL=1 GC_PACK_DIR="$ROOT" SYMPTOM_KEY=TestWidget WORK_BEAD_ID=work-1 bash "$TMP/file.sh" >/dev/null 2>&1)
has "$(cat "$FAKE_META")" "Tracked as: nothing, the filing failed" "3e: a filing that did not land is reported as nothing filed"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
