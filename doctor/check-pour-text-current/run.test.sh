#!/usr/bin/env bash
# Hermetic test for doctor/check-pour-text-current (tk-5w3boh, invariant I9).
#
# THE INVARIANT the check guards: "a molecule executes the formula text that is
# current when it runs." It breaks two ways — the CHECKOUT the runtime executes
# falls behind what landed, and a molecule's step text is frozen at pour and
# never re-renders. Measured on tk-24aj5w: PR #443 merged at 16:06:49Z, the
# molecule poured 18 seconds earlier from the pre-#443 formula, and the checkout
# advanced 8 minutes later. The molecule ran superseded text for its whole life.
#
# What is exercised here:
#   * every ERROR arm, with a POSITIVE CONTROL for each. A check that has only
#     ever been run against a healthy city proves nothing: the live city was
#     clean when this landed, so "it exits 0" is not evidence it can fail.
#   * THE FAIL-OPEN CASE, which is the reason this check is not three lines of
#     `git rev-list`. `HEAD..origin/main` compares against the LOCAL
#     remote-tracking ref, and only the reconciler's own fetch advances it —
#     so when the reconciler dies, both sides freeze together and the naive
#     behind-count reads 0 at exactly the moment the invariant is most broken.
#     (UNFETCHED) and (FLOOR) are that control.
#   * the self-heal WINDOW, in both directions. A lag inside the reconciler's
#     cooldown is its duty cycle; reporting it would train everyone to ignore
#     the check. A lag past the window is a reconciler that stopped.
#   * the SCOPE of the stale-text half — in_progress only (an `open` root is a
#     husk, which is I8's defect), inside the liveness cap, and resolved
#     against whichever checkout OWNS the formula rather than the molecule's
#     own rig. That last one is not a nicety: gc-toolkit is rig-imported by
#     four rigs, and judging only same-rig formulas would skip nearly every
#     molecule outside gc-toolkit.
#   * the QUERY itself. If `--status in_progress`, `--has-metadata-key
#     gc.formula_source` or `--limit 0` drifts, the check silently stops seeing
#     the roots it exists to find and reports a clean city.
#   * the QUIET path — a healthy city exits 0 and names no rig as a finding.
#   * the fail-CLOSED arms. Every probe that cannot be READ must warn, never
#     pass.
#
# No live city, Dolt, or network — real throwaway git repos in a tmpdir, plus
# stub `gc`/`bd` on PATH.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

[ -x "$CHECK" ] || chmod +x "$CHECK" 2>/dev/null

mkdir -p "$TMP/bin" "$TMP/beads"

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# Timestamps are computed, never hardcoded: every threshold in the check is a
# distance from NOW, and a frozen literal would drift across it depending on
# when the suite runs.
NOW=$(date -u +%s)
iso_at() { date -u -d "@$(( NOW - $1 ))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
        || date -u -r "$(( NOW - $1 ))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null; }

# The check's defaults: 15m interval x 3 slack = 45m stale threshold, 24h
# liveness cap. The fixtures below sit unambiguously on one side or the other,
# never near an edge.
INSIDE_WINDOW=600        # 10m  — a lag the reconciler is still working through
PAST_WINDOW=7200         # 2h   — a lag that has stopped self-healing
LIVE=3600                # 1h   — a molecule plausibly still running
HUSK=172800              # 48h  — long past the liveness cap

# --- git fixtures ------------------------------------------------------------
# mkrepo <path> — a checkout whose HEAD equals its remote ref, with one formula
# committed <seconds-ago>.
mkrepo() {
    local path="$1" formula_age="$2"
    mkdir -p "$path/formulas"
    git -C "$path" init -q -b main 2>/dev/null
    printf 'step = "one"\n' > "$path/formulas/mol-test.toml"
    git -C "$path" add -A 2>/dev/null
    GIT_COMMITTER_DATE="$(iso_at "$formula_age")" GIT_AUTHOR_DATE="$(iso_at "$formula_age")" \
        git -C "$path" commit -q -m "formula" 2>/dev/null
    git -C "$path" update-ref refs/remotes/origin/main HEAD
    touch "$path/.git/FETCH_HEAD"
}

# advance_remote <path> <n> <age> — add n commits to the REMOTE ref only, dated
# <age> seconds ago, leaving HEAD behind by n.
advance_remote() {
    local path="$1" n="$2" age="$3" i
    local saved; saved=$(git -C "$path" rev-parse HEAD)
    for i in $(seq 1 "$n"); do
        printf 'extra %s\n' "$i" >> "$path/formulas/mol-test.toml"
        git -C "$path" add -A 2>/dev/null
        GIT_COMMITTER_DATE="$(iso_at "$age")" GIT_AUTHOR_DATE="$(iso_at "$age")" \
            git -C "$path" commit -q -m "landed $i" 2>/dev/null
    done
    git -C "$path" update-ref refs/remotes/origin/main HEAD
    git -C "$path" reset -q --hard "$saved"
}

# age_fetch <path> <seconds-ago> — pretend the last `git fetch` was that long ago.
age_fetch() { touch -d "@$(( NOW - $2 ))" "$1/.git/FETCH_HEAD" 2>/dev/null \
           || touch -t "$(date -r "$(( NOW - $2 ))" +%Y%m%d%H%M.%S)" "$1/.git/FETCH_HEAD"; }

# --- bead fixtures -----------------------------------------------------------
# root <id> <status> <age-seconds> <formula-path>
root() {
    printf '{"id":"%s","status":"%s","created_at":"%s","metadata":{"gc.formula_source":"%s"}}' \
        "$1" "$2" "$(iso_at "$3")" "$4"
}
beads() { printf '[%s]' "$(printf '%s' "$*" | sed 's/} {/},{/g')"; }

# --- stubs -------------------------------------------------------------------
# The `bd` stub records its argv so the QUERY can be asserted, and answers per
# --db from a file the test writes. A store with no file answers `[]` — an
# empty store, which is NOT the same as an unreadable one and must not warn.
#
# IT APPLIES --status AND --has-metadata-key rather than trusting them. A stub
# that answered every query with its whole fixture would let the check ask the
# WRONG question and still pass: the (OPENROOT) case — an open root must be out
# of scope — is only meaningful if the filter is what excludes it, and it
# caught this stub returning an open root to an `--status in_progress` query on
# the first run.
cat > "$TMP/bin/bd" <<'BDEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BD_CALLS"
db=""; want_status=""; want_key=""; prev=""
for a in "$@"; do
    case "$prev" in
        --db)                db="$a" ;;
        --status)            want_status="$a" ;;
        --has-metadata-key)  want_key="$a" ;;
    esac
    prev="$a"
done
key=$(printf '%s' "$db" | tr -c 'A-Za-z0-9' '_')
if [ -f "$BD_FIXTURES/$key.rc" ]; then exit "$(cat "$BD_FIXTURES/$key.rc")"; fi
if [ -f "$BD_FIXTURES/$key.empty" ]; then exit 0; fi
if [ ! -f "$BD_FIXTURES/$key.json" ]; then printf '[]'; exit 0; fi
jq -c --arg st "$want_status" --arg k "$want_key" \
   '[ .[] | select($st == "" or .status == $st)
          | select($k == "" or (.metadata // {} | has($k))) ]' \
   < "$BD_FIXTURES/$key.json"
BDEOF

cat > "$TMP/bin/gc" <<'GCEOF'
#!/usr/bin/env bash
if [ "${1:-}" = "rig" ] && [ "${2:-}" = "list" ]; then
    [ -f "$GC_RIGS_RC" ] && exit "$(cat "$GC_RIGS_RC")"
    cat "$GC_RIGS"; exit 0
fi
exit 0
GCEOF
chmod +x "$TMP/bin/bd" "$TMP/bin/gc"

export BD_CALLS="$TMP/bd-calls" BD_FIXTURES="$TMP/beads"
export GC_RIGS="$TMP/rigs.json" GC_RIGS_RC="$TMP/rigs.rc"

# run <case-tag> -> sets OUT / RC. Each case gets its own fixture dir and call log.
run() {
    local tag="$1"; shift
    BD_CALLS="$TMP/calls-$tag"; : > "$BD_CALLS"
    RC=0
    OUT="$(BD_CALLS="$BD_CALLS" PATH="$TMP/bin:$PATH" "$@" bash "$CHECK" 2>&1)" || RC=$?
    CALLS="$(cat "$BD_CALLS" 2>/dev/null || true)"
}

fixture_for() { # fixture_for <db-path> ; echoes the key file prefix
    printf '%s/%s' "$BD_FIXTURES" "$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '_')"
}

rigs_json() { printf '{"rigs":[%s]}' "$1" > "$TMP/rigs.json"; rm -f "$TMP/rigs.rc"; }

echo "── currency: the checkout the runtime executes ──"

# (CURRENT) the healthy city. This is the QUIET control: without it, every arm
# below could pass while the check flagged a clean city on every run.
A="$TMP/a"; mkrepo "$A" "$HUSK"
rigs_json "{\"name\":\"alpha\",\"path\":\"$A\",\"hq\":false}"
run current
eq "$RC" "0" "(CURRENT) a checkout at its remote tip exits 0"
has "$OUT" "executed pack is current across 1 checkout" "(CURRENT) …and says so"
hasnt "$OUT" "behind" "(CURRENT) …naming no lag"

# (LAGGED) behind, past the self-heal window, with a FRESH fetch — so the
# behind-count is trustworthy and the lag is real.
B="$TMP/b"; mkrepo "$B" "$HUSK"; advance_remote "$B" 2 "$PAST_WINDOW"; touch "$B/.git/FETCH_HEAD"
rigs_json "{\"name\":\"beta\",\"path\":\"$B\",\"hq\":false}"
run lagged
eq "$RC" "2" "(LAGGED) a lag past the self-heal window is an ERROR"
has "$OUT" "2 commit(s) behind" "(LAGGED) …naming how far behind"
has "$OUT" "past the" "(LAGGED) …and that it is past the window"

# (LAGWINDOW) behind, but the oldest unmerged commit is INSIDE the window.
# This is the reconciler's ordinary duty cycle and must not be a finding —
# a check that fires every 15 minutes teaches everyone to ignore it.
C="$TMP/c"; mkrepo "$C" "$HUSK"; advance_remote "$C" 1 "$INSIDE_WINDOW"; touch "$C/.git/FETCH_HEAD"
rigs_json "{\"name\":\"gamma\",\"path\":\"$C\",\"hq\":false}"
run lagwindow
eq "$RC" "0" "(LAGWINDOW) a lag inside the reconciler's window is NOT a finding"
has "$OUT" "self-healing" "(LAGWINDOW) …and is noted as self-healing"

# (UNFETCHED) THE FAIL-OPEN CONTROL. behind reads 0, and that 0 is worthless
# because the ref it was measured against has not moved either.
D="$TMP/d"; mkrepo "$D" "$HUSK"; age_fetch "$D" "$PAST_WINDOW"
rigs_json "{\"name\":\"delta\",\"path\":\"$D\",\"hq\":false}"
run unfetched
eq "$RC" "1" "(UNFETCHED) behind=0 with a stale remote ref WARNS instead of passing"
has "$OUT" "has not been refreshed" "(UNFETCHED) …saying the ref is stale"
has "$OUT" "FLOOR" "(UNFETCHED) …and that the behind-count is a floor, not the lag"

# (FLOOR) behind AND unfetched: the true lag cannot be measured from here.
E="$TMP/e"; mkrepo "$E" "$HUSK"; advance_remote "$E" 3 "$PAST_WINDOW"; age_fetch "$E" "$PAST_WINDOW"
rigs_json "{\"name\":\"eps\",\"path\":\"$E\",\"hq\":false}"
run floor
eq "$RC" "2" "(FLOOR) behind + stale ref is an ERROR"
has "$OUT" "remote ref is itself stale" "(FLOOR) …and says the number is a lower bound"

# (NOFETCHHEAD) no FETCH_HEAD at all — unreadable, so it warns rather than passes.
F="$TMP/f"; mkrepo "$F" "$HUSK"; rm -f "$F/.git/FETCH_HEAD"
rigs_json "{\"name\":\"zeta\",\"path\":\"$F\",\"hq\":false}"
run nofetchhead
eq "$RC" "1" "(NOFETCHHEAD) a missing FETCH_HEAD warns"
has "$OUT" "unverifiable" "(NOFETCHHEAD) …and says the count is unverifiable"

# (HQ) the HQ rig is excluded from CURRENCY by construction — the reconciler
# selects .hq != true — but must be named, not silently dropped.
G="$TMP/g"; mkrepo "$G" "$HUSK"; advance_remote "$G" 5 "$PAST_WINDOW"; touch "$G/.git/FETCH_HEAD"
rigs_json "{\"name\":\"hq\",\"path\":\"$G\",\"hq\":true},{\"name\":\"alpha\",\"path\":\"$A\",\"hq\":false}"
run hq
eq "$RC" "0" "(HQ) an HQ rig behind its remote is not a currency finding"
has "$OUT" "HQ rig" "(HQ) …but is named as deliberately excluded"

# (NOTGIT) a rig path that is not a checkout: warn, never silently skip.
mkdir -p "$TMP/notgit"
rigs_json "{\"name\":\"nope\",\"path\":\"$TMP/notgit\",\"hq\":false},{\"name\":\"alpha\",\"path\":\"$A\",\"hq\":false}"
run notgit
eq "$RC" "1" "(NOTGIT) a non-checkout rig path warns"
has "$OUT" "not a git checkout" "(NOTGIT) …saying so"

echo "── stale text: a molecule running superseded step text ──"

# (STALETEXT) the invariant itself: the root poured BEFORE its formula last
# changed, so its step descriptions were rendered from text that is gone.
H="$TMP/h"; mkrepo "$H" 1800   # formula last changed 30m ago
rigs_json "{\"name\":\"eta\",\"path\":\"$H\",\"hq\":false}"
printf '%s' "$(root mol-old in_progress "$LIVE" "$H/formulas/mol-test.toml")" \
  | sed 's/^/[/; s/$/]/' > "$(fixture_for "$H/.beads").json"
mkdir -p "$H/.beads"
run staletext
eq "$RC" "2" "(STALETEXT) a live molecule poured before its formula changed is an ERROR"
has "$OUT" "mol-old" "(STALETEXT) …naming the root"
has "$OUT" "AFTER the pour" "(STALETEXT) …and saying the change came after the pour"
has "$OUT" "I9" "(STALETEXT) …and citing the invariant"

# (CURRENTTEXT) the same shape with the pour AFTER the change — must be silent.
# Without this the arm above could be firing on every molecule.
printf '%s' "$(root mol-new in_progress 600 "$H/formulas/mol-test.toml")" \
  | sed 's/^/[/; s/$/]/' > "$(fixture_for "$H/.beads").json"
run currenttext
eq "$RC" "0" "(CURRENTTEXT) a molecule poured AFTER the change is not flagged"
hasnt "$OUT" "mol-new" "(CURRENTTEXT) …and is not named at all"

# (OPENROOT) an `open` root with unambiguously stale text. Live roots are
# in_progress; open ones are husks, and reporting them buries the real finding
# — measured 71 husks to 1 live finding in gc-toolkit.
printf '%s' "$(root mol-husk open "$LIVE" "$H/formulas/mol-test.toml")" \
  | sed 's/^/[/; s/$/]/' > "$(fixture_for "$H/.beads").json"
run openroot
eq "$RC" "0" "(OPENROOT) an open root is out of scope (husk, not a live molecule)"
hasnt "$OUT" "mol-husk" "(OPENROOT) …and is not named"

# (AGEDOUT) in_progress but long past the liveness cap: excluded, and COUNTED,
# so the scoping is visible rather than silent.
printf '%s' "$(root mol-aged in_progress "$HUSK" "$H/formulas/mol-test.toml")" \
  | sed 's/^/[/; s/$/]/' > "$(fixture_for "$H/.beads").json"
run agedout
eq "$RC" "0" "(AGEDOUT) an in_progress root past the liveness cap is not an error"
has "$OUT" "excluded as husks" "(AGEDOUT) …but the exclusion is reported, not silent"

# (IMPORTED) the coverage case: the molecule lives in one rig and its formula in
# ANOTHER scanned checkout. gc-toolkit is rig-imported by four rigs, so judging
# only same-rig formulas would skip nearly every molecule outside it.
I="$TMP/i"; mkrepo "$I" "$HUSK"; mkdir -p "$I/.beads"
rigs_json "{\"name\":\"eta\",\"path\":\"$H\",\"hq\":false},{\"name\":\"iota\",\"path\":\"$I\",\"hq\":false}"
: > "$(fixture_for "$H/.beads").json"; printf '[]' > "$(fixture_for "$H/.beads").json"
printf '%s' "$(root mol-imported in_progress "$LIVE" "$H/formulas/mol-test.toml")" \
  | sed 's/^/[/; s/$/]/' > "$(fixture_for "$I/.beads").json"
run imported
eq "$RC" "2" "(IMPORTED) a molecule running ANOTHER rig's formula is still judged"
has "$OUT" "mol-imported" "(IMPORTED) …and named"

# (UNSCANNED) a formula under no scanned checkout — a materialized pack cache.
# There is no git history to date it against, so it is unanswerable, not clean.
mkdir -p "$TMP/packcache/formulas"; printf 'x\n' > "$TMP/packcache/formulas/mol-test.toml"
printf '%s' "$(root mol-cached in_progress "$LIVE" "$TMP/packcache/formulas/mol-test.toml")" \
  | sed 's/^/[/; s/$/]/' > "$(fixture_for "$I/.beads").json"
run unscanned
eq "$RC" "0" "(UNSCANNED) a formula outside every checkout is not an error"
has "$OUT" "unanswerable" "(UNSCANNED) …but is reported as unanswerable, not as clean"

# (MISSINGFILE) gc.formula_source names a file that is not there.
printf '%s' "$(root mol-gone in_progress "$LIVE" "$I/formulas/nope.toml")" \
  | sed 's/^/[/; s/$/]/' > "$(fixture_for "$I/.beads").json"
run missingfile
eq "$RC" "1" "(MISSINGFILE) an unreadable formula warns"
has "$OUT" "does not exist" "(MISSINGFILE) …saying so"

echo "── the query, and the fail-closed arms ──"

# (QUERY) the three flags that decide what the check can SEE. If any drifts the
# check silently stops finding roots and reports a clean city.
rigs_json "{\"name\":\"eta\",\"path\":\"$H\",\"hq\":false}"
printf '[]' > "$(fixture_for "$H/.beads").json"
run query
has "$CALLS" "--status in_progress"                "(QUERY) scopes to live roots"
has "$CALLS" "--has-metadata-key gc.formula_source" "(QUERY) selects molecule roots by their formula source"
has "$CALLS" "--limit 0"                            "(QUERY) is uncapped, so a windowed listing cannot false-empty it"
has "$CALLS" "--db $H/.beads"                       "(QUERY) reads the rig's own store"

# (BDFAIL) the store cannot be listed: warn, and say the store was NOT checked.
printf '3' > "$(fixture_for "$H/.beads").rc"
run bdfail
eq "$RC" "1" "(BDFAIL) an unreadable bead store warns"
has "$OUT" "NOT checked" "(BDFAIL) …and says the store was not checked"
rm -f "$(fixture_for "$H/.beads").rc"

# (BDEMPTY) rc=0 with NO output. An empty store answers `[]`; empty output is a
# probe that produced nothing, which is not the same thing and is not a pass.
: > "$(fixture_for "$H/.beads").empty"
run bdempty
eq "$RC" "1" "(BDEMPTY) empty output is not an empty store"
has "$OUT" "returned no output" "(BDEMPTY) …and is reported as unread"
rm -f "$(fixture_for "$H/.beads").empty"

# (RIGFAIL) no roster at all — the check cannot run and must say so, not pass.
printf '2' > "$TMP/rigs.rc"
run rigfail
eq "$RC" "1" "(RIGFAIL) a failed rig listing exits 1"
has "$OUT" "cannot determine" "(RIGFAIL) …and refuses to judge"
rm -f "$TMP/rigs.rc"

echo ""
echo "check-pour-text-current: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
