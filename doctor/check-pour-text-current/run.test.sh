#!/usr/bin/env bash
# Hermetic test for doctor/check-pour-text-current (I9). Real
# throwaway git repos plus a stub `gc` on PATH; no live city, Dolt, network.
# Exercised: every ERROR arm with a positive control each; the fail-open case
# (a stale remote-tracking ref makes the naive behind-count read 0, so it must
# warn as a floor, never pass); the self-heal window in both directions; a run
# poured before its formula last changed, which is no finding; the quiet path;
# the fail-closed arms (every unreadable probe warns, never passes).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-check-pour-text-current-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

mkdir -p "$TMP/bin" "$TMP/beads"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
# Host signing of commits and tags must not make this suite need a signing agent.
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false \
  GIT_CONFIG_KEY_1=tag.gpgsign GIT_CONFIG_VALUE_1=false

# Timestamps are computed, never hardcoded: every threshold in the check is a
# distance from NOW, and a frozen literal would drift across it.
NOW=$(date -u +%s)
iso_at() { date -u -d "@$(( NOW - $1 ))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
        || date -u -r "$(( NOW - $1 ))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null; }

# The check's defaults: 15m interval x 3 slack = 45m stale threshold.
# Fixtures sit unambiguously on one side, never near an edge.
INSIDE_WINDOW=600        # 10m  — a lag the reconciler is still working through
PAST_WINDOW=7200         # 2h   — a lag that has stopped self-healing
LIVE=3600                # 1h   — a run plausibly still going
OLD=172800               # 48h  — a formula long since landed

# mkrepo <path> <formula-age> — a checkout whose HEAD equals its remote ref,
# with one formula committed <formula-age> seconds ago.
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

# advance_remote <path> <n> <age> — add n commits to the REMOTE ref only,
# dated <age> seconds ago, leaving HEAD behind by n.
advance_remote() {
    local path="$1" n="$2" age="$3" i saved
    saved=$(git -C "$path" rev-parse HEAD)
    for i in $(seq 1 "$n"); do
        printf 'extra %s\n' "$i" >> "$path/formulas/mol-test.toml"
        git -C "$path" add -A 2>/dev/null
        GIT_COMMITTER_DATE="$(iso_at "$age")" GIT_AUTHOR_DATE="$(iso_at "$age")" \
            git -C "$path" commit -q -m "landed $i" 2>/dev/null
    done
    git -C "$path" update-ref refs/remotes/origin/main HEAD
    git -C "$path" reset -q --hard "$saved"
}

# age_fetch <path> <seconds-ago> — pretend the last `git fetch` was then.
age_fetch() { touch -d "@$(( NOW - $2 ))" "$1/.git/FETCH_HEAD" 2>/dev/null \
           || touch -t "$(date -r "$(( NOW - $2 ))" +%Y%m%d%H%M.%S)" "$1/.git/FETCH_HEAD"; }

# root <id> <status> <age-seconds> <formula-path> — one molecule-root row.
root() {
    printf '{"id":"%s","status":"%s","created_at":"%s","metadata":{"gc.formula_source":"%s"}}' \
        "$1" "$2" "$(iso_at "$3")" "$4"
}

# The stub `gc` serves the rig roster and the bead listing. bd records its argv
# and answers per --db from a fixture file, so a check that listed a store
# would see the run the (POUREDBEFORE) case puts there.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GCEOF'
if [ "${1:-}" = "rig" ] && [ "${2:-}" = "list" ]; then
    [ -f "$GC_RIGS_RC" ] && exit "$(cat "$GC_RIGS_RC")"
    cat "$GC_RIGS"; exit 0
fi
if [ "${1:-}" = "bd" ]; then
    printf '%s\n' "$*" >> "$BD_CALLS"
    db=""; prev=""
    for a in "$@"; do [ "$prev" = "--db" ] && db="$a"; prev="$a"; done
    fixture="$BD_FIXTURES/$(printf '%s' "$db" | tr -c 'A-Za-z0-9' '_').json"
    if [ -f "$fixture" ]; then cat "$fixture"; else printf '[]'; fi
    exit 0
fi
exit 0
GCEOF
chmod +x "$TMP/bin/gc"

export BD_FIXTURES="$TMP/beads"
export GC_RIGS="$TMP/rigs.json" GC_RIGS_RC="$TMP/rigs.rc"

# run <case-tag> -> sets OUT / RC / CALLS. Each case gets its own call log.
run() {
    local tag="$1"
    BD_CALLS="$TMP/calls-$tag"; : > "$BD_CALLS"
    RC=0
    OUT="$(BD_CALLS="$BD_CALLS" PATH="$TMP/bin:$PATH" bash "$CHECK" 2>&1)" || RC=$?
    CALLS="$(cat "$BD_CALLS" 2>/dev/null || true)"
}

fixture_for() { printf '%s/%s' "$BD_FIXTURES" "$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '_')"; }
rigs_json() { printf '{"rigs":[%s]}' "$1" > "$TMP/rigs.json"; rm -f "$TMP/rigs.rc"; }

echo "── currency: the checkout the runtime executes ──"

# (CURRENT) the healthy city — the quiet control: without it, every arm below
# could pass while the check flagged a clean city on every run.
A="$TMP/a"; mkrepo "$A" "$OLD"
rigs_json "{\"name\":\"alpha\",\"path\":\"$A\",\"hq\":false}"
run current
eq "$RC" "0" "(CURRENT) a checkout at its remote tip exits 0"
has "$OUT" "executed pack is current across 1 checkout" "(CURRENT) …and says so"
hasnt "$OUT" "behind" "(CURRENT) …naming no lag"

# (LAGGED) behind, past the self-heal window, with a FRESH fetch — the
# behind-count is trustworthy and the lag is real.
B="$TMP/b"; mkrepo "$B" "$OLD"; advance_remote "$B" 2 "$PAST_WINDOW"; touch "$B/.git/FETCH_HEAD"
rigs_json "{\"name\":\"beta\",\"path\":\"$B\",\"hq\":false}"
run lagged
eq "$RC" "2" "(LAGGED) a lag past the self-heal window is an ERROR"
has "$OUT" "2 commit(s) behind" "(LAGGED) …naming how far behind"
has "$OUT" "past the" "(LAGGED) …and that it is past the window"

# (LAGWINDOW) behind, but the oldest unmerged commit is INSIDE the window —
# the reconciler's ordinary duty cycle, not a finding.
C="$TMP/c"; mkrepo "$C" "$OLD"; advance_remote "$C" 1 "$INSIDE_WINDOW"; touch "$C/.git/FETCH_HEAD"
rigs_json "{\"name\":\"gamma\",\"path\":\"$C\",\"hq\":false}"
run lagwindow
eq "$RC" "0" "(LAGWINDOW) a lag inside the reconciler's window is NOT a finding"
has "$OUT" "self-healing" "(LAGWINDOW) …and is noted as self-healing"

# (UNFETCHED) the fail-open control: behind reads 0, and that 0 is worthless
# because the ref it was measured against has not moved either.
D="$TMP/d"; mkrepo "$D" "$OLD"; age_fetch "$D" "$PAST_WINDOW"
rigs_json "{\"name\":\"delta\",\"path\":\"$D\",\"hq\":false}"
run unfetched
eq "$RC" "1" "(UNFETCHED) behind=0 with a stale remote ref WARNS instead of passing"
has "$OUT" "has not been refreshed" "(UNFETCHED) …saying the ref is stale"
has "$OUT" "a floor" "(UNFETCHED) …and that the behind-count is a floor, not the lag"

# (FLOOR) behind AND unfetched: the true lag cannot be measured from here.
E="$TMP/e"; mkrepo "$E" "$OLD"; advance_remote "$E" 3 "$PAST_WINDOW"; age_fetch "$E" "$PAST_WINDOW"
rigs_json "{\"name\":\"eps\",\"path\":\"$E\",\"hq\":false}"
run floor
eq "$RC" "2" "(FLOOR) behind + stale ref is an ERROR"
has "$OUT" "remote ref is itself stale" "(FLOOR) …and says the number is a lower bound"

# (NOFETCHHEAD) no FETCH_HEAD at all — unreadable, so warn, never pass.
F="$TMP/f"; mkrepo "$F" "$OLD"; rm -f "$F/.git/FETCH_HEAD"
rigs_json "{\"name\":\"zeta\",\"path\":\"$F\",\"hq\":false}"
run nofetchhead
eq "$RC" "1" "(NOFETCHHEAD) a missing FETCH_HEAD warns"
has "$OUT" "unverifiable" "(NOFETCHHEAD) …and says the count is unverifiable"

# (HQ) the HQ rig is excluded from currency by construction (the reconciler
# selects .hq != true) but must be named, not silently dropped.
G="$TMP/g"; mkrepo "$G" "$OLD"; advance_remote "$G" 5 "$PAST_WINDOW"; touch "$G/.git/FETCH_HEAD"
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

echo "── a run poured before its formula last changed ──"

# (POUREDBEFORE) nothing re-renders a poured run, so the run finishes on the
# step text it poured with whatever the change did. That is no finding, and
# the check lists no bead store to look for it.
H="$TMP/h"; mkrepo "$H" 1800   # formula last changed 30m ago
mkdir -p "$H/.beads"
rigs_json "{\"name\":\"eta\",\"path\":\"$H\",\"hq\":false}"
printf '[%s]' "$(root mol-old in_progress "$LIVE" "$H/formulas/mol-test.toml")" \
  > "$(fixture_for "$H/.beads").json"
run pouredbefore
eq "$RC" "0" "(POUREDBEFORE) a live run poured before its formula last changed reads OK"
hasnt "$OUT" "mol-old" "(POUREDBEFORE) …and is not named"
eq "$CALLS" "" "(POUREDBEFORE) …and no bead store is listed"

echo "── the fail-closed arms ──"

# (RIGFAIL) no roster at all — the check cannot run and must say so, not pass.
printf '2' > "$TMP/rigs.rc"
run rigfail
eq "$RC" "1" "(RIGFAIL) a failed rig listing exits 1"
has "$OUT" "cannot determine" "(RIGFAIL) …and refuses to judge"
rm -f "$TMP/rigs.rc"

echo ""
echo "check-pour-text-current: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
