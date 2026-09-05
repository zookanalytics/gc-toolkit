#!/usr/bin/env bash
# Hermetic test for branch-context.sh — the witness patrol's repo-pinning
# helper (resolve, merged, push-target-ok).
#
# THE BUG (SECURITY / DATA-LOSS): mol-witness-patrol decided branch existence and
# merge geometry with UNPINNED git/gh calls. Run from the witness's agent home
# (the town repo) or from another rig, `git ls-remote origin <branch>` and the gh
# commit/compare lookups resolve against the wrong repo, so a live rig branch reads
# as GONE and its pushed commits look discardable. A shallow rig checkout adds a
# second trap: its grafted boundary makes merge-base and rev-list report a false
# count, so a landed branch reads as unmerged. The salvage push had the write-side
# mirror: a worktree that is its own root but points `origin` at the wrong repo
# would publish rig commits to that repo.
#
# THE FIX: resolve the OWNING rig from the bead (store ref, then work_dir, then the
# patrol's own rig), pin every existence/geometry/push to it, treat a shallow
# checkout as unable to answer geometry (defer to the compare API), and never
# report absence — or push — from a context whose origin was not asserted to be the
# owning repo.
#
# This drives the REAL script's subcommands the way the formula does — `resolve`
# through `eval "$(...)"`, `merged` and `push-target-ok` directly — against a
# synthetic city of real local git repos (rig checkouts + bare origins and a
# separate town repo), plus a stub `gh` for the compare-API path. No live city,
# Dolt, network, or PRs — only git, a tmpdir, and one tiny gh stub.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SCRIPT="$HERE/branch-context.sh"
TOML="$ROOT/formulas/mol-witness-patrol.toml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
absent() { if grep -qF "$2" "$1"; then bad "$3 (still present in $(basename "$1"))"; else ok "$3"; fi; }
val() { printf '%s\n' "$2" | sed -n "s/^$1=//p" | head -n1; }

[ -x "$SCRIPT" ] && ok "branch-context.sh is executable" || bad "branch-context.sh missing or not executable"
bash -n "$SCRIPT" && ok "branch-context.sh parses (bash -n)" || bad "branch-context.sh failed bash -n"

# --- Build a synthetic city: bare origins + rig checkouts + a town repo. ------
CITY="$TMP/city"
mkdir -p "$CITY/rigs" "$CITY/remotes"
gitq() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

setup_rig() { # $1 = rig name -> bare origin + checkout carrying main
  local name="$1" remote="$CITY/remotes/$1.git" rig="$CITY/rigs/$1"
  git init --bare -q "$remote"
  git clone -q "$remote" "$rig" 2>/dev/null
  gitq "$rig" commit -q --allow-empty -m init
  gitq "$rig" branch -M main
  gitq "$rig" push -q -u origin main
}

setup_rig gascity
setup_rig gc-toolkit
G="$CITY/rigs/gascity"
# An UNMERGED branch (exists on origin, one commit ahead of main).
gitq "$G" checkout -q -b polecat/gc-dyjoe
gitq "$G" commit -q --allow-empty -m "dyjoe work"
gitq "$G" push -q -u origin polecat/gc-dyjoe
# A MERGED branch (its commit is reachable from main after the merge).
gitq "$G" checkout -q main
gitq "$G" checkout -q -b feature/merged
gitq "$G" commit -q --allow-empty -m "merged work"
gitq "$G" push -q -u origin feature/merged
gitq "$G" checkout -q main
gitq "$G" merge -q --no-ff -m "merge feature/merged" feature/merged
gitq "$G" push -q origin main
gitq "$G" checkout -q main

# The town repo: the witness's agent home. Its origin has NO gascity branch.
git init --bare -q "$CITY/remotes/town.git"
TOWN="$CITY/town"
git clone -q "$CITY/remotes/town.git" "$TOWN" 2>/dev/null
gitq "$TOWN" commit -q --allow-empty -m init
gitq "$TOWN" branch -M main
gitq "$TOWN" push -q -u origin main

# A SHALLOW gascity checkout: grafted boundary; local geometry cannot be trusted.
git clone -q --depth 1 "file://$CITY/remotes/gascity.git" "$CITY/rigs/gascity-shallow" 2>/dev/null

# Stub gh for the compare-API path. git stays REAL.
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/gh" <<'GH'
#!/usr/bin/env bash
[ "${STUB_GH_RC:-0}" = "0" ] || exit "${STUB_GH_RC}"
printf '%s\n' "${STUB_AHEAD:-}"
GH
chmod +x "$BIN/gh"

export GC_CITY_PATH="$CITY"
export PATH="$BIN:$PATH"
OWN_URL=$(gitq "$G" remote get-url origin)

# `resolve` as the formula runs it: eval its output, then reprint the vars flat.
# The GC_* env and cwd come from the caller's subshell, so this proves the real
# `eval "$(branch-context.sh resolve ...)"` contract, not an extracted fragment.
resolve_flat() { # <store-ref> <worktree> <branch> [cwd]
  ( [ -n "${4:-}" ] && cd "$4"
    eval "$("$SCRIPT" resolve --store-ref "$1" --worktree "$2" --branch "$3")"
    printf 'RIG_ROOT=%s\n'          "${RIG_ROOT:-}"
    printf 'OWNER_REPO=%s\n'        "${OWNER_REPO:-}"
    printf 'OWNING_ORIGIN_URL=%s\n' "${OWNING_ORIGIN_URL:-}"
    printf 'REPO_CTX=%s\n'          "${REPO_CTX:-}"
    printf 'BRANCH_ON_ORIGIN=%s\n'  "${BRANCH_ON_ORIGIN:-}" )
}

# --- (Premise) an UNPINNED existence check from town reports a live branch absent.
PREMISE=$(cd "$TOWN" && git ls-remote --heads origin polecat/gc-dyjoe 2>/dev/null || true)
[ -z "$PREMISE" ] \
  && ok "(premise) unpinned ls-remote from the town repo does NOT see the gascity branch" \
  || bad "(premise) expected the town repo to lack the gascity branch"

# ============================ resolve: owning repo ===========================
# The owning rig resolves from the store ref, then work_dir, then GC_RIG — and
# RIG_ROOT lands on the gascity checkout even when cwd is the town repo.
OUT=$( export GC_RIG=gc-toolkit GC_RIG_ROOT="$CITY/rigs/gc-toolkit"; resolve_flat "rig:gascity" "" "" "$TOWN" )
eq "$(val RIG_ROOT "$OUT")" "$CITY/rigs/gascity" "(R1) store ref rig:gascity -> gascity checkout (from town cwd)"
eq "$(val REPO_CTX "$OUT")" "ok"                 "(R1) REPO_CTX ok"

OUT=$( export GC_RIG=gc-toolkit GC_RIG_ROOT="$CITY/rigs/gc-toolkit"; resolve_flat "" "/home/x/.gc/worktrees/gascity/polecats/p/worktrees/tk-1" "" )
eq "$(val RIG_ROOT "$OUT")" "$CITY/rigs/gascity" "(R2) work_dir under .gc/worktrees/<rig> -> gascity"

OUT=$( export GC_RIG=gc-toolkit GC_RIG_ROOT="$CITY/rigs/gc-toolkit"; resolve_flat "" "/home/x/rigs/gascity/foo" "" )
eq "$(val RIG_ROOT "$OUT")" "$CITY/rigs/gascity" "(R3) work_dir under rigs/<rig> -> gascity"

# OWNER_REPO parses from github-style origins (https and ssh both -> owner/repo).
git init -q "$CITY/rigs/ghslug"
gitq "$CITY/rigs/ghslug" remote add origin https://github.com/zookanalytics/coolrepo.git
OUT=$( export GC_RIG=x; resolve_flat "rig:ghslug" "" "" )
eq "$(val OWNER_REPO "$OUT")" "zookanalytics/coolrepo" "(R4a) https origin -> owner/repo"
gitq "$CITY/rigs/ghslug" remote set-url origin git@github.com:zookanalytics/coolrepo.git
OUT=$( export GC_RIG=x; resolve_flat "rig:ghslug" "" "" )
eq "$(val OWNER_REPO "$OUT")" "zookanalytics/coolrepo" "(R4b) ssh origin -> owner/repo"

# Unresolvable owning rig (not the patrol's own) -> no RIG_ROOT, unknown context.
OUT=$( export GC_RIG=gascity GC_RIG_ROOT="$CITY/rigs/gascity"; resolve_flat "rig:nope" "" "" )
eq "$(val RIG_ROOT "$OUT")" ""        "(R5) unknown rig, not the patrol's own -> RIG_ROOT empty"
eq "$(val REPO_CTX "$OUT")" "unknown" "(R5) REPO_CTX unknown (fail closed)"

# ============================ resolve: branch existence ======================
# THE CORE ASSERTION: existence is found regardless of cwd, never falsely absent.
OUT=$( export GC_RIG=gc-toolkit GC_RIG_ROOT="$CITY/rigs/gc-toolkit"; resolve_flat "rig:gascity" "" "polecat/gc-dyjoe" "$TOWN" )
eq "$(val BRANCH_ON_ORIGIN "$OUT")" "present" "(E1) from the town cwd: gascity branch reads PRESENT, not absent"
OUT=$( export GC_RIG=gc-toolkit GC_RIG_ROOT="$CITY/rigs/gc-toolkit"; resolve_flat "rig:gascity" "" "polecat/gc-dyjoe" "$CITY/rigs/gc-toolkit" )
eq "$(val BRANCH_ON_ORIGIN "$OUT")" "present" "(E2) from the gc-toolkit rig cwd: gascity branch reads PRESENT"
OUT=$( export GC_RIG=gc-toolkit GC_RIG_ROOT="$CITY/rigs/gc-toolkit"; resolve_flat "rig:gascity" "" "polecat/does-not-exist" "$TOWN" )
eq "$(val BRANCH_ON_ORIGIN "$OUT")" "absent" "(E3) a genuinely missing branch reads absent (from the asserted owning context)"
OUT=$( export GC_RIG=gascity GC_RIG_ROOT="$CITY/rigs/gascity"; resolve_flat "rig:nope" "" "polecat/gc-dyjoe" "$TOWN" )
eq "$(val BRANCH_ON_ORIGIN "$OUT")" "unknown" "(E4) unresolved owning repo -> unknown, never absent"

# ============================ merged ========================================
merged_out() { # <store-ref> <worktree> <branch> <target>
  "$SCRIPT" merged --store-ref "$1" --worktree "$2" --branch "$3" --target "$4"
}
OUT=$( export GC_RIG=gc-toolkit; merged_out "rig:gascity" "" "feature/merged" "main" )
eq "$OUT" "yes" "(M1) full checkout: a merged branch -> yes"
OUT=$( export GC_RIG=gc-toolkit; merged_out "rig:gascity" "" "polecat/gc-dyjoe" "main" )
eq "$OUT" "no" "(M2) full checkout: an unmerged branch -> no"
# Shallow: local geometry must NOT be trusted; with the API unavailable -> unknown.
OUT=$( export GC_RIG=gc-toolkit STUB_GH_RC=1; merged_out "rig:gascity-shallow" "" "polecat/gc-dyjoe" "main" )
eq "$OUT" "unknown" "(M3) shallow checkout + no API answer -> unknown (no local-count claim)"
# Shallow + the compare API answers ahead_by=0 -> merged.
OUT=$( export GC_RIG=gc-toolkit STUB_GH_RC=0 STUB_AHEAD=0; merged_out "rig:gascity-shallow" "" "polecat/gc-dyjoe" "main" )
eq "$OUT" "yes" "(M4) shallow checkout: compare API ahead_by=0 -> yes"
eq "$(git -C "$CITY/rigs/gascity-shallow" rev-parse --is-shallow-repository)" "true" "(premise) the shallow rig checkout is shallow"

# A branch MERGED into main and then DELETED on the bare origin by another actor
# leaves THIS full checkout a STALE refs/remotes/origin/<branch>. Swallowing the
# fetch failure read that stale ancestor as merged and returned "yes" — a discard
# signal for work the owning origin no longer has (the 53-commit near-miss). The
# targeted fetch is load-bearing: a branch that cannot be freshly fetched from the
# owning origin is "unknown", never yes/no from a stale ref.
gitq "$G" checkout -q main
gitq "$G" checkout -q -b feature/stale-merged
gitq "$G" commit -q --allow-empty -m "stale-merged work"
gitq "$G" push -q -u origin feature/stale-merged
gitq "$G" checkout -q main
gitq "$G" merge -q --no-ff -m "merge feature/stale-merged" feature/stale-merged
gitq "$G" push -q origin main
gitq "$G" branch -q -D feature/stale-merged
# Another actor deletes the branch straight on the bare origin, so this checkout
# never prunes its now-stale remote-tracking ref (push --delete would have).
git -C "$CITY/remotes/gascity.git" update-ref -d refs/heads/feature/stale-merged
eq "$(gitq "$G" ls-remote --heads origin feature/stale-merged | wc -l | tr -d ' ')" "0" \
  "(premise) the merged branch is gone on the bare origin"
gitq "$G" rev-parse --verify --quiet refs/remotes/origin/feature/stale-merged >/dev/null \
  && ok "(premise) the full checkout still holds the STALE remote-tracking ref" \
  || bad "(premise) expected a stale remote-tracking ref to survive the upstream delete"
gitq "$G" merge-base --is-ancestor refs/remotes/origin/feature/stale-merged refs/remotes/origin/main \
  && ok "(premise) the stale ref looks merged — the old swallow-the-fetch code would read 'yes' (discard)" \
  || bad "(premise) expected the stale ref to look merged to the old code"
OUT=$( export GC_RIG=gc-toolkit; merged_out "rig:gascity" "" "feature/stale-merged" "main" )
eq "$OUT" "unknown" "(M5) full checkout, branch deleted upstream + stale ref -> unknown (fetch is load-bearing; never a stale-ref discard)"
if ( export GC_RIG=gc-toolkit; "$SCRIPT" merged --store-ref rig:gascity --worktree "" --branch feature/stale-merged --target main ) >/dev/null 2>&1; then
  ok "(M6) merged exits clean when the branch fetch fails (deleted upstream)"
else
  bad "(M6) merged exited non-zero when the branch fetch failed"
fi

# ============================ push-target-ok ================================
ptok() { # <worktree> <owning-origin>
  "$SCRIPT" push-target-ok --worktree "$1" --owning-origin "$2" --bead tk-test 2>/dev/null
}
ptok "$G" "$OWN_URL"    && ok "(W1) worktree origin == owning origin -> push OK (exit 0)" || bad "(W1) expected exit 0"
ptok "$TOWN" "$OWN_URL" && bad "(W2) expected REFUSED (exit 1)" || ok "(W2) worktree origin != owning origin -> REFUSED (exit 1)"
ptok "$G" ""            && bad "(W3) expected REFUSED (exit 1)" || ok "(W3) owning origin unknown -> REFUSED (fail closed)"
ERR=$("$SCRIPT" push-target-ok --worktree "$TOWN" --owning-origin "$OWN_URL" --bead tk-test 2>&1 >/dev/null || true)
case "$ERR" in *"REFUSING salvage push"*) ok "(W4) origin mismatch emits a REFUSING diagnostic naming the bead" ;; *) bad "(W4) expected a REFUSING diagnostic (got: $ERR)" ;; esac

# ============================ set -u / exit-code hygiene =====================
# Every query exits 0 (a verdict, never an abort) even on the fail-closed paths.
( export GC_RIG=gascity GC_RIG_ROOT="$CITY/rigs/gascity"; "$SCRIPT" resolve --store-ref rig:nope --worktree "" --branch x >/dev/null ) \
  && ok "(S1) resolve exits 0 on an unresolved owning repo" || bad "(S1) resolve aborted on an unresolved repo"
( export GC_RIG=gc-toolkit; "$SCRIPT" merged --store-ref rig:gascity --worktree "" --branch feature/merged --target main >/dev/null ) \
  && ok "(S2) merged exits 0 on the happy path" || bad "(S2) merged aborted on the happy path"
RC=0; "$SCRIPT" bogus-subcommand >/dev/null 2>&1 || RC=$?
[ "$RC" = "2" ] && ok "(S3) an unknown subcommand is a usage error (exit 2)" || bad "(S3) expected exit 2 for a bad subcommand (got $RC)"

# ============================ formula wiring ================================
# The formula calls the script and gates the salvage push; the moved geometry
# lives in the script, not inline in the step.
grep -qF 'branch-context.sh' "$TOML" \
  && ok "(T1) the formula calls branch-context.sh" || bad "(T1) the formula must call branch-context.sh"
grep -qF '"$BC" resolve' "$TOML" \
  && ok "(T2) the formula evals resolve for the repo context" || bad "(T2) the formula must eval branch-context.sh resolve"
grep -qF '"$BC" merged' "$TOML" \
  && ok "(T3) the formula reads the merged verdict" || bad "(T3) the formula must read branch-context.sh merged"
grep -qF 'if [ "$BRANCH_ON_ORIGIN" = "present" ]' "$TOML" \
  && ok "(T4) salvage branches on BRANCH_ON_ORIGIN" || bad "(T4) salvage must branch on BRANCH_ON_ORIGIN"
GUARD_LN=$(grep -nF 'push-target-ok' "$TOML" | head -1 | cut -d: -f1)
PUSH_LN=$(grep -nE '^[[:space:]]*git push origin HEAD' "$TOML" | head -1 | cut -d: -f1)
[ -n "$GUARD_LN" ] && [ -n "$PUSH_LN" ] && [ "$GUARD_LN" -lt "$PUSH_LN" ] \
  && ok "(T5) push-target-ok gates and precedes the salvage push" \
  || bad "(T5) push-target-ok must gate the salvage push (guard@${GUARD_LN:-none} push@${PUSH_LN:-none})"
absent "$TOML" 'is-shallow-repository' "(T6) shallow-detect geometry moved out of the formula"
absent "$TOML" 'gh -R ' "(T7) gh calls moved out of the formula"
absent "$TOML" 'ls-remote' "(T8) existence check moved out of the formula"

# The geometry the formula used to inline now lives in the script, still pinned.
grep -qF 'is-shallow-repository' "$SCRIPT" \
  && ok "(T9) the script detects a shallow checkout" || bad "(T9) the script must detect a shallow checkout"
grep -qF 'gh -R "$OWNER_REPO"' "$SCRIPT" \
  && ok "(T10) the script pins gh to the owning repo" || bad "(T10) the script must pin gh -R owner/repo"
grep -qF 'git -C "$RIG_ROOT" ls-remote' "$SCRIPT" \
  && ok "(T11) the script pins ls-remote to RIG_ROOT" || bad "(T11) the script must pin git -C RIG_ROOT ls-remote"
grep -qF '[ "$REPO_CTX" = "ok" ]' "$SCRIPT" \
  && ok "(T12) the script gates existence/geometry on REPO_CTX=ok" || bad "(T12) the script must gate on REPO_CTX=ok"

# --- The formula still parses as TOML. ---------------------------------------
if command -v python3 >/dev/null 2>&1; then
  python3 - "$TOML" <<'PY' && ok "(T13) formula still parses as TOML" || bad "(T13) formula failed to parse as TOML"
import sys, tomllib
with open(sys.argv[1], "rb") as f: tomllib.load(f)
PY
fi

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
