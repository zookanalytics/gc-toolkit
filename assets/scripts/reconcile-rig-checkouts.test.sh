#!/usr/bin/env bash
# Hermetic test for reconcile-rig-checkouts.sh.
#
# Builds throwaway git fixtures (a bare "origin" + a "checkout" that has drifted)
# and drives the reconcile script through its test seams (RECONCILE_RIGS_OVERRIDE,
# RECONCILE_ESCALATE=0, RECONCILE_LEDGER_DIR), so it needs neither the `gc`
# binary nor any live city. Run directly:
#
#   assets/scripts/reconcile-rig-checkouts.test.sh
#
# Covers (acceptance: tk-nu5u):
#   * the 3-bucket classifier — KNOWN / ALREADY-UPSTREAM / NOVEL-CONFLICT
#   * --dry-run / DRY_RUN makes ZERO checkout mutations (the safety invariant)
#   * a blocked rig is never advanced, even in enforce mode
#   * the advance path: drops already-upstream, preserves allowlisted .beads/
#     and non-conflicting novel work, and lands HEAD on origin/main
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECONCILE="$SCRIPT_DIR/reconcile-rig-checkouts.sh"
ALLOWLIST="$SCRIPT_DIR/../config/reconcile-rig-checkouts.allowlist"

TESTROOT="$(mktemp -d)"
trap 'rm -rf "$TESTROOT"' EXIT

FAILS=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
    printf 'FAIL - %s\n' "$1"
    FAILS=$((FAILS + 1))
}
assert_eq() { # desc want got
    if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (want='$2' got='$3')"; fi
}

git_q() { git -C "$1" "${@:2}"; }
gitcfg() {
    git_q "$1" config user.email tester@example.com
    git_q "$1" config user.name tester
    git_q "$1" config commit.gpgsign false
}

# new_fixture NAME -> creates $TESTROOT/NAME/{origin.git,upstream,checkout}
new_fixture() {
    local root="$TESTROOT/$1"
    rm -rf "$root"
    mkdir -p "$root"
    git init -q -b main "$root/upstream"
    gitcfg "$root/upstream"
    mkdir -p "$root/upstream/.beads"
    printf 'v1\n' >"$root/upstream/app.txt"
    printf 'shared\n' >"$root/upstream/shared.txt"
    printf 'base\n' >"$root/upstream/conflict.txt"
    printf 'flush=on\n' >"$root/upstream/event.conf"
    printf 'f1\n' >"$root/upstream/formula.txt"
    printf 'seed\n' >"$root/upstream/notes.txt"
    printf 'telemetry: off\n' >"$root/upstream/.beads/config.yaml"
    git_q "$root/upstream" add -A
    git_q "$root/upstream" commit -q -m init
    git init -q --bare "$root/origin.git"
    git_q "$root/origin.git" symbolic-ref HEAD refs/heads/main
    git_q "$root/upstream" remote add origin "$root/origin.git"
    git_q "$root/upstream" push -q origin main
    git clone -q "$root/origin.git" "$root/checkout"
    gitcfg "$root/checkout"
}

# Author a commit on upstream and publish it to origin (simulates a merged PR
# that the checkout has not yet pulled).
origin_commit() { # root msg
    git_q "$TESTROOT/$1/upstream" add -A
    git_q "$TESTROOT/$1/upstream" commit -q -m "$2"
    git_q "$TESTROOT/$1/upstream" push -q origin main
}

run_reconcile() { # root dry(0/1)
    local root="$TESTROOT/$1"
    RECONCILE_RIGS_OVERRIDE="rig=$root/checkout" \
        RECONCILE_ESCALATE=0 \
        RECONCILE_DRY_RUN="$2" \
        RECONCILE_ALLOWLIST_FILE="$ALLOWLIST" \
        RECONCILE_LEDGER_DIR="$root/ledger" \
        RECONCILE_STATE_FILE="$root/state.json" \
        bash "$RECONCILE" >"$root/out.log" 2>&1
}

ledger() { jq -r "$3" "$TESTROOT/$1/ledger/rig.json" 2>/dev/null; }

echo "== Fixture 1: three buckets present (KNOWN + ALREADY-UPSTREAM + CONFLICT) =="
new_fixture f1
# origin advances: app.txt -> v2, and conflict.txt -> an upstream change.
printf 'v2\n' >"$TESTROOT/f1/upstream/app.txt"
printf 'upstream-change\n' >"$TESTROOT/f1/upstream/conflict.txt"
origin_commit f1 "upstream: bump app, edit conflict"
# checkout drifts (uncommitted):
printf 'telemetry: off\nlocal: 1\n' >"$TESTROOT/f1/checkout/.beads/config.yaml" # KNOWN (allowlisted)
printf 'v2\n' >"$TESTROOT/f1/checkout/app.txt"                                   # ALREADY-UPSTREAM (== origin)
printf 'local-change\n' >"$TESTROOT/f1/checkout/conflict.txt"                    # NOVEL-CONFLICT (both sides changed)

HEAD_BEFORE="$(git_q "$TESTROOT/f1/checkout" rev-parse HEAD)"
run_reconcile f1 1 # dry-run

assert_eq "f1 dry: status blocked"            "blocked" "$(ledger f1 . .status)"
assert_eq "f1 dry: known count"               "1"       "$(ledger f1 . .counts.known)"
assert_eq "f1 dry: already_upstream count"    "1"       "$(ledger f1 . .counts.already_upstream)"
assert_eq "f1 dry: novel_conflict count"      "1"       "$(ledger f1 . .counts.novel_conflict)"
assert_eq "f1 dry: novel_nonconflicting zero" "0"       "$(ledger f1 . .counts.novel_nonconflicting)"
assert_eq "f1 dry: ledger marked dry_run"     "true"    "$(ledger f1 . .dry_run)"
assert_eq "f1 dry: behind > 0"                "1"       "$(ledger f1 . '.behind')"
# Zero mutation: HEAD and dirty files untouched, origin untouched.
assert_eq "f1 dry: HEAD unchanged"            "$HEAD_BEFORE" "$(git_q "$TESTROOT/f1/checkout" rev-parse HEAD)"
assert_eq "f1 dry: conflict.txt untouched"    "local-change" "$(cat "$TESTROOT/f1/checkout/conflict.txt")"
assert_eq "f1 dry: app.txt untouched"         "v2"           "$(cat "$TESTROOT/f1/checkout/app.txt")"

echo "== Fixture 1b: blocked rig is NOT advanced even in enforce mode =="
run_reconcile f1 0 # enforce
assert_eq "f1 enforce: still blocked"         "blocked" "$(ledger f1 . .status)"
assert_eq "f1 enforce: HEAD still unchanged"  "$HEAD_BEFORE" "$(git_q "$TESTROOT/f1/checkout" rev-parse HEAD)"
assert_eq "f1 enforce: conflict.txt untouched" "local-change" "$(cat "$TESTROOT/f1/checkout/conflict.txt")"

echo "== Fixture 2: clean advance (KNOWN + ALREADY-UPSTREAM commit + NOVEL non-conflicting) =="
new_fixture f2
# origin advances app.txt -> v2 ...
printf 'v2\n' >"$TESTROOT/f2/upstream/app.txt"
origin_commit f2 "upstream: bump app to v2"
# ... and origin also adds an "extra" line to shared.txt (a published change the
# checkout will reproduce locally, to exercise patch-equivalent already-upstream).
printf 'shared\nextra\n' >"$TESTROOT/f2/upstream/shared.txt"
origin_commit f2 "upstream: add extra to shared"

# checkout makes the SAME shared.txt change as a local commit -> git cherry marks
# it '-' (already upstream) and the advance must drop it without losing content.
printf 'shared\nextra\n' >"$TESTROOT/f2/checkout/shared.txt"
git_q "$TESTROOT/f2/checkout" add shared.txt
git_q "$TESTROOT/f2/checkout" commit -q -m "local: add extra to shared (dup of upstream)"
# KNOWN dirty (allowlisted) — must be preserved across the advance.
printf 'telemetry: off\nmanaged: true\n' >"$TESTROOT/f2/checkout/.beads/config.yaml"
# NOVEL non-conflicting (tracked edit to a file origin did NOT touch) — advance
# must preserve it on top of origin/main and flag it.
printf 'seed\nlocal note\n' >"$TESTROOT/f2/checkout/notes.txt"
# Untracked cruft — must be IGNORED by default (-uno) and survive the advance.
printf 'scratch\n' >"$TESTROOT/f2/checkout/scratch.tmp"

run_reconcile f2 1 # dry-run first
assert_eq "f2 dry: status would_advance"      "would_advance" "$(ledger f2 . .status)"
assert_eq "f2 dry: no conflicts"              "0" "$(ledger f2 . .counts.novel_conflict)"
assert_eq "f2 dry: already_upstream commit"   "1" "$(ledger f2 . .counts.already_upstream)"
assert_eq "f2 dry: known count"               "1" "$(ledger f2 . .counts.known)"
assert_eq "f2 dry: novel_nonconflicting"      "1" "$(ledger f2 . .counts.novel_nonconflicting)"
# Two tracked-dirty deviations (.beads known + notes.txt novel_nc); untracked
# scratch.tmp must be excluded by default (-uno), else this would be 3.
assert_eq "f2 dry: untracked ignored" "2" "$(ledger f2 . '[.deviations[] | select(.kind=="dirty")] | length')"
HEAD_F2_BEFORE="$(git_q "$TESTROOT/f2/checkout" rev-parse HEAD)"
assert_eq "f2 dry: HEAD unchanged"            "$HEAD_F2_BEFORE" "$(git_q "$TESTROOT/f2/checkout" rev-parse HEAD)"

run_reconcile f2 0 # enforce — perform the advance
REMOTE_HEAD="$(git_q "$TESTROOT/f2/checkout" rev-parse origin/main)"
assert_eq "f2 enforce: status advanced"       "advanced" "$(ledger f2 . .status)"
assert_eq "f2 enforce: HEAD == origin/main"   "$REMOTE_HEAD" "$(git_q "$TESTROOT/f2/checkout" rev-parse HEAD)"
assert_eq "f2 enforce: app.txt advanced to v2" "v2" "$(cat "$TESTROOT/f2/checkout/app.txt")"
assert_eq "f2 enforce: .beads preserved"      "telemetry: off
managed: true" "$(cat "$TESTROOT/f2/checkout/.beads/config.yaml")"
assert_eq "f2 enforce: novel work preserved"  "seed
local note" "$(cat "$TESTROOT/f2/checkout/notes.txt" 2>/dev/null)"
assert_eq "f2 enforce: untracked cruft survived" "scratch" "$(cat "$TESTROOT/f2/checkout/scratch.tmp" 2>/dev/null)"
assert_eq "f2 enforce: pre_advance_sha recorded" "$HEAD_F2_BEFORE" "$(ledger f2 . .pre_advance_sha)"
# Idempotent: a second pass needs no advance — HEAD is at origin/main and only
# the kept .beads edit + preserved novel work remain (no behind, no residue).
run_reconcile f2 0
assert_eq "f2 enforce again: synced_with_divergence" "synced_with_divergence" "$(ledger f2 . .status)"
assert_eq "f2 enforce again: HEAD still at origin" "$REMOTE_HEAD" "$(git_q "$TESTROOT/f2/checkout" rev-parse HEAD)"
assert_eq "f2 enforce again: still carries known"  "1" "$(ledger f2 . .counts.known)"

echo "== Fixture 3: the real 2026-06-05 gc-toolkit incident (canonical fixture) =="
# 7 merged PRs behind, plus three local changes that are ALL already on origin:
#   - a bd auto-commit of .beads/config.yaml          -> KNOWN (allowlisted)
#   - a dirty 'disable-event-flush' tuning mod        -> ALREADY-UPSTREAM
#   - a staged formula edit                           -> ALREADY-UPSTREAM
# Expected: dry-run classifies everything KNOWN/ALREADY-UPSTREAM, reports it
# WOULD advance cleanly with 0 blockers, and mutates nothing.
new_fixture f3
# origin moves 7 commits ahead, folding in the final event.conf / formula.txt
# states that the checkout also (independently) carries locally.
for n in 1 2 3 4 5 6 7; do
    printf 'v%s\n' "$((n + 1))" >"$TESTROOT/f3/upstream/app.txt"
    [ "$n" = 3 ] && printf 'flush=off\n' >"$TESTROOT/f3/upstream/event.conf"
    [ "$n" = 5 ] && printf 'f2\n' >"$TESTROOT/f3/upstream/formula.txt"
    origin_commit f3 "upstream commit $n"
done
# checkout (still at the initial commit) carries the three already-landed changes:
git_q "$TESTROOT/f3/checkout" config commit.gpgsign false
printf 'telemetry: off\nmanaged: true\n' >"$TESTROOT/f3/checkout/.beads/config.yaml" # bd auto-commit
git_q "$TESTROOT/f3/checkout" add .beads/config.yaml
git_q "$TESTROOT/f3/checkout" commit -q -m "bd: commit canonical .beads/config.yaml"
printf 'flush=off\n' >"$TESTROOT/f3/checkout/event.conf"  # dirty already-upstream tuning
printf 'f2\n' >"$TESTROOT/f3/checkout/formula.txt"        # staged already-upstream edit
git_q "$TESTROOT/f3/checkout" add formula.txt

HEAD_F3="$(git_q "$TESTROOT/f3/checkout" rev-parse HEAD)"
run_reconcile f3 1 # dry-run / observe
assert_eq "f3 incident: would advance cleanly"  "would_advance" "$(ledger f3 . .status)"
assert_eq "f3 incident: 0 blockers"             "0"  "$(ledger f3 . .counts.novel_conflict)"
assert_eq "f3 incident: 7 behind"               "7"  "$(ledger f3 . .behind)"
assert_eq "f3 incident: .beads commit is KNOWN" "1"  "$(ledger f3 . .counts.known)"
assert_eq "f3 incident: tuning+formula already-upstream" "2" "$(ledger f3 . .counts.already_upstream)"
assert_eq "f3 incident: dry-run mutates nothing" "$HEAD_F3" "$(git_q "$TESTROOT/f3/checkout" rev-parse HEAD)"
assert_eq "f3 incident: event.conf untouched"   "flush=off" "$(cat "$TESTROOT/f3/checkout/event.conf")"

echo
if [ "$FAILS" -eq 0 ]; then
    echo "ALL TESTS PASSED"
    exit 0
fi
echo "$FAILS TEST(S) FAILED"
exit 1
