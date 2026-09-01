#!/usr/bin/env bash
# Hermetic test for the find-work gating-anchor selection guard (tk-jcal4,
# formulas/mol-refinery-patrol.toml find-work step) and for the PRE_OPEN
# decision reading every key a PR can be recorded under.
#
# The defect: find-work selected work beads on `assignee=$GC_AGENT + open +
# has metadata.branch` with NO exclusion for beads that are already gating
# anchors. A parked anchor is open and carries `branch` BY DESIGN ("open means
# unlanded"; the resolver needs the branch), so the only thing keeping one out
# of the queue was `assignee=""` — an unenforced convention writable by any
# actor. On 2026-08-11 a rig witness wrote `assignee=<refinery>` onto two
# correctly parked shutupandlisten anchors (merge_result=pull_request,
# codex-green, PR#55/PR#56 open awaiting human approval). Re-processing them
# would have reset both to merge_result=pre_open_gate, orphaned two live PRs
# from their anchors, dispatched duplicate codex reviews, and had
# pre-open-resolve.sh open a SECOND PR per branch — every write reporting
# success. It was caught by a human noticing the dispatch line.
#
# The fix under test, in two parts:
#   1. find-work post-filters the listing, dropping any bead that carries a
#      `merge_result` — the invariant is enforced by the query, not by
#      convention. The listing limit had to rise above 1 for that filter to be
#      safe: a client-side filter over a 1-row window turns one parked anchor
#      at the head of the result set into "no work", starving a refinery that
#      has real work queued.
#   2. the PRE_OPEN decision consults `pr_url`/`pr_number`, not only the
#      caller-supplied `existing_pr`, so a post-open anchor that reaches
#      merge-push by ANY route converges on the PR it already owns instead of
#      being re-parked to pre_open_gate.
#
# Both marked blocks are extracted VERBATIM from the formula and executed
# against a fake `gc`, so they cannot drift from the shipped instruction. No
# live city, Dolt, network, or PRs.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-refinery-patrol.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-find-work-gating-guard-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3" "got '$1' want '$2'"; }

[ -s "$TOML" ] || { echo "missing $TOML"; exit 1; }

extract() {
  awk -v m="$1" '
    $0 ~ ("# >>> " m "$") {f=1; next}
    $0 ~ ("# <<< " m "$") {f=0}
    f' "$2"
}

extract find-work-select     "$TOML" > "$TMP/select.sh"
extract pre-open-recorded-pr "$TOML" > "$TMP/preopen.sh"
[ -s "$TMP/select.sh" ]  || { echo "no marked find-work-select block"; exit 1; }
[ -s "$TMP/preopen.sh" ] || { echo "no marked pre-open-recorded-pr block"; exit 1; }

echo "── the extracted blocks survive TOML unchanged and are valid shell ──"
bash -n "$TMP/select.sh"  && ok "find-work-select: valid bash" \
    || bad "find-work-select: valid bash" "bash -n failed"
bash -n "$TMP/preopen.sh" && ok "pre-open-recorded-pr: valid bash" \
    || bad "pre-open-recorded-pr: valid bash" "bash -n failed"

# The blocks live inside a TOML `"""` string, so TOML consumes escapes before
# an agent ever sees them: a trailing backslash joins two lines and jq's
# backslash-paren interpolation is not a valid TOML escape at all. This test
# extracts the RAW file text while the agent runs the PARSED string, so a
# backslash anywhere in a marked block means the two texts differ and this test
# stops pinning what actually runs.
python3 -c 'import tomllib,sys; tomllib.load(open(sys.argv[1],"rb"))' "$TOML" 2>/dev/null \
    && ok "formula parses as TOML" || bad "formula parses as TOML" "tomllib rejected it"
for blk in select preopen; do
  grep -q '[\]' "$TMP/$blk.sh" \
    && bad "$blk: no backslash (TOML would eat it)" "found a backslash" \
    || ok "$blk: no backslash (TOML would eat it)"
done

# --- gc stub: the find-work listing. -----------------------------------------
# `gc bd list ... --limit=N --json` over a fixture of `id|merge_result` rows.
# The stub HONORS --limit (truncating the array server-side, as bd does) so the
# starvation case below actually exercises the widened window: with --limit=1 a
# leading parked anchor is the only row the filter ever sees.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
[ "$1" = "bd" ] && [ "$2" = "list" ] || exit 0
[ "${FAKE_BD_FAILS:-0}" = "1" ] && exit 0   # bd fails open: empty stdout
lim=0
for a in "$@"; do
  case "$a" in --limit=*) lim="${a#--limit=}" ;; esac
done
out=""; n=0
while IFS='|' read -r id mr; do
  [ -n "$id" ] || continue
  [ "$lim" -gt 0 ] && [ "$n" -ge "$lim" ] && break
  n=$((n + 1))
  if [ "$mr" = "-" ]; then
    obj=$(printf '{"id":"%s","metadata":{"branch":"polecat/%s"}}' "$id" "$id")
  else
    obj=$(printf '{"id":"%s","metadata":{"branch":"polecat/%s","merge_result":"%s"}}' "$id" "$id" "$mr")
  fi
  if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
done < "$FAKE_ROWS"
printf '[%s]\n' "$out"
exit 0
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH"
export FAKE_ROWS="$TMP/rows"
export GC_RIG="testrig" GC_AGENT="testrig/gc-toolkit.refinery"

{ cat "$TMP/select.sh"; printf 'printf "%%s\\n" "$WORK"\n'; } > "$TMP/run-select.sh"

# select -> stdout is the chosen WORK id; stderr captured separately.
select_work() { FAKE_BD_FAILS="${1:-0}" bash "$TMP/run-select.sh" 2>"$TMP/err"; }
select_err()  { cat "$TMP/err"; }

echo "── 1. selection: a gating anchor is never work ──"

# (1) Ordinary hand-off: a polecat's bead carries branch and NO merge_result.
printf 'tk-plain|-\n' > "$FAKE_ROWS"
eq "$(select_work)" "tk-plain" "(1) plain work bead is selected (unchanged behavior)"

# (2) The live near-miss: a parked post-open anchor wearing an assignee. It must
#     not be selected — selecting it is what reset PR#55/PR#56 to pre-open.
printf 'tk-anchor|pull_request\n' > "$FAKE_ROWS"
eq "$(select_work)" "" "(2) parked pull_request anchor is NOT selected"
case "$(select_err)" in
  *tk-anchor*pull_request*) ok "(2b) the skipped anchor is flagged on stderr, named with its state" ;;
  *) bad "(2b) skipped anchor must be flagged on stderr" "got '$(select_err)'" ;;
esac

# (3) STARVATION REGRESSION. A parked anchor sorts ahead of real work. With the
#     old --limit=1 the filter would see only the anchor and report no work,
#     idling a refinery whose queue is non-empty — trading a false positive for
#     a false negative. The widened window is what makes the filter safe.
printf 'tk-anchor|pull_request\ntk-real|-\n' > "$FAKE_ROWS"
eq "$(select_work)" "tk-real" "(3) real work behind a parked anchor is still found (limit > 1)"

# (4) The pre-open sub-state is equally a gating anchor.
printf 'tk-pre|pre_open_gate\n' > "$FAKE_ROWS"
eq "$(select_work)" "" "(4) parked pre_open_gate anchor is NOT selected"

# (5) ANY merge_result, not just the gating pair. Every path that legitimately
#     returns a bead to this queue clears the field first (mr-aware-rejection
#     folds --unset-metadata merge_result into the repool), so a value present
#     means some pass recorded a disposition and this queue is not it.
for mr in merged blocked refused_false_completion abandoned retargeted held; do
  printf 'tk-d|%s\n' "$mr" > "$FAKE_ROWS"
  eq "$(select_work)" "" "(5) merge_result=$mr is excluded"
done

# (6) Tri-state: an EMPTY merge_result is "no disposition recorded", the same as
#     absent — it must stay selectable, matching the pre-fix behavior for a bead
#     no pass has dispositioned.
printf 'tk-empty|\n' > "$FAKE_ROWS"
eq "$(select_work)" "tk-empty" "(6) empty merge_result reads as absent, stays selectable"

# (7) bd fails open (errors to stderr, empty stdout). Selection must yield NO
#     work rather than a garbage id: idling is recoverable, re-gating is not.
printf 'tk-plain|-\n' > "$FAKE_ROWS"
eq "$(select_work 1)" "" "(7) unreadable listing selects nothing (fails safe)"

echo "── 2. the query keeps a window wide enough for the filter ──"
QUERY="$(grep -m1 'gc bd list' "$TMP/select.sh")"
case "$QUERY" in
  *--limit=1\ *|*--limit=1) bad "(8) listing limit must exceed 1" "client-side filter over a 1-row window starves" ;;
  *--limit=*) ok "(8) listing limit exceeds 1 (filter cannot starve the queue)" ;;
  *) bad "(8) listing carries an explicit --limit" "none found in: $QUERY" ;;
esac
case "$QUERY" in
  *--assignee=\$GC_AGENT*) ok "(9) listing still scopes to this refinery's assignee" ;;
  *) bad "(9) listing must keep --assignee=\$GC_AGENT" ;;
esac
case "$QUERY" in
  *'${GC_RIG:+--rig="$GC_RIG"}'*) ok "(10) listing still scopes to the rig database" ;;
  *) bad "(10) listing must keep the \${GC_RIG:+--rig} scoping" ;;
esac

# The guard flags; it must not repair. Restoring assignee="" here would fight
# whichever writer set it, from a pass that cannot see why — the same reason
# gate-ensure.sh only flags a non-canonically-assigned anchor.
grep -q 'gc bd update' "$TMP/select.sh" \
  && bad "(11) selection must not write to beads" "found a gc bd update in the guard" \
  || ok "(11) selection flags only — no bead writes"

echo "── 3. PRE_OPEN reads every key a PR can be recorded under ──"

# preopen <existing_pr> <pr_url> <pr_number> -> "PRE_OPEN|RECORDED_PR"
{ cat "$TMP/preopen.sh"; printf 'printf "%%s|%%s\\n" "$PRE_OPEN" "$RECORDED_PR"\n'; } > "$TMP/run-preopen.sh"
preopen() {
  BEAD_JSON=$(jq -nc --arg u "${2:-}" --arg n "${3:-}" \
    '[{metadata: ({} + (if $u != "" then {pr_url: $u} else {} end)
                    + (if $n != "" then {pr_number: ($n | tonumber)} else {} end))}]')
  WORK="tk-w" EXISTING_PR="${1:-}" BEAD_JSON="$BEAD_JSON" CODEX_GATE=1 \
    bash "$TMP/run-preopen.sh" 2>/dev/null | tail -1
}
# `gh` must be present for PRE_OPEN to be reachable at all (the resolver opens
# the PR through it); stub it so the test does not depend on the host.
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/gh"; chmod +x "$TMP/bin/gh"

eq "$(preopen '' '' '')" "1|" \
   "(12) first handoff: no PR recorded anywhere -> PRE_OPEN (unchanged)"
eq "$(preopen 'https://github.com/o/r/pull/9' '' '')" "0|https://github.com/o/r/pull/9" \
   "(13) caller-supplied existing_pr -> post-open (unchanged)"
eq "$(preopen '' 'https://github.com/o/r/pull/55' '')" "0|https://github.com/o/r/pull/55" \
   "(14) THE BUG: a refinery-minted pr_url -> post-open, not re-parked to pre_open_gate"
eq "$(preopen '' '' '55')" "0|55" \
   "(15) pr_number alone (a recovered anchor before the pr_url backfill) -> post-open"
# jq's `//` falls through on null/false ONLY, so an empty-string pr_url would
# out-rank a real pr_number under a `//` chain and hand a PR reference of "" to
# the post-open path.
eq "$(preopen '' '' '' ; :)" "1|" "(16) no keys at all -> PRE_OPEN"
BEAD_JSON='[{"metadata":{"pr_url":"","pr_number":55}}]'
eq "$(WORK="tk-w" EXISTING_PR="" BEAD_JSON="$BEAD_JSON" CODEX_GATE=1 bash "$TMP/run-preopen.sh" 2>/dev/null | tail -1)" "0|55" \
   "(17) empty pr_url does not out-rank a real pr_number (jq // only skips null)"

# existing_pr keeps its own strict validation path; a refinery-minted pr_url
# must NOT be laundered into it, or an anchor whose PR drifted would
# block-and-escalate instead of being re-verified and re-stamped.
grep -q 'EXISTING_PR=' "$TMP/preopen.sh" \
  && bad "(18) the guard must not overwrite EXISTING_PR" "found an EXISTING_PR assignment" \
  || ok "(18) EXISTING_PR left intact (its block-and-escalate contract is unchanged)"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
