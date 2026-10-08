#!/usr/bin/env bash
# Tests for review-workspace.sh against a real git repository and a synthetic
# workspace directory. Only `gc` is stubbed: it serves the city's rigs and each
# bead's status from a table, and logs the store every lookup was sent to.
#
# Covers path and its id rails; add making a detached worktree at the commit,
# reusing it at the same commit, rebuilding it at another, re-creating one whose
# directory was deleted by hand, and refusing an oid that is not a commit and a
# workspace name that is a symlink; remove taking every worktree inside a
# workspace, a nested one included, with its registration, and a read-only
# subtree, while another worktree's stale registration is left for
# worktree-reap; the formulas' own add and remove lines, run verbatim; and
# reap's gates — the workspace of a closed review goes, its bead looked up in
# the store its prefix names; a review that is not closed and a status that
# cannot be read hold at any age; a bead the ledger no longer has, a name with no
# bead, and a name with anything after the bead id age out on the idle horizon,
# measured by the newest entry inside, and one whose age cannot be read is held;
# a process standing in a workspace or holding a file in it holds it until it
# exits, and an lsof listing that reads nothing or fails holds everything; a
# symlink is unlinked and its target kept; --dry-run removes nothing; unreadable
# rigs reap nothing; and the pass reads no directory but the one it was given.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-review-workspace-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
PIDS=()
cleanup() {
    for p in ${PIDS[@]+"${PIDS[@]}"}; do kill "$p" 2>/dev/null; done
    chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"
}
trap cleanup EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"   # assertions only; harness_init would stub out git
PASS=0; FAIL=0

SUT="$HERE/review-workspace.sh"
unset "${!GC_@}" "${!BEADS_@}" 2>/dev/null || true
# The user's git config can sign commits or add hooks; this repository is ours.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export REVIEW_WORKSPACE_DIR="$TMP/ws"
mkdir -p "$REVIEW_WORKSPACE_DIR"
WS="$REVIEW_WORKSPACE_DIR"

REPO="$TMP/repo"
git init -q "$REPO"
g() { git -C "$REPO" -c user.name=t -c user.email=t@example.com "$@"; }
echo one > "$REPO/f"; g add f; g commit -q -m one; C1="$(g rev-parse HEAD)"
echo two > "$REPO/f"; g commit -q -am two; C2="$(g rev-parse HEAD)"
is_registered() { grep -qxF "worktree $1" < <(git -C "$REPO" worktree list --porcelain); }
exists() { [ -e "$1" ] || [ -L "$1" ]; }
run() { bash "$SUT" "$@" 2>&1; }

# --- the gc stub ---------------------------------------------------------------
BIN="$TMP/bin"; mkdir -p "$BIN"
export STUB_STATUS="$TMP/status.tsv" STUB_GC_LOG="$TMP/gc.log" STUB_ROOT="$TMP" STUB_RIGS_FAIL=""
: > "$STUB_STATUS"; : > "$STUB_GC_LOG"
cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_GC_LOG"
case "$1 $2" in
    "rig list")
        [ -z "$STUB_RIGS_FAIL" ] || { echo "not in a city directory" >&2; exit 1; }
        printf '{"city_path":"%s","rigs":[{"name":"city","path":"%s","prefix":"lx","hq":true},{"name":"toolkit","path":"%s/rig-tk","prefix":"tk"},{"name":"loom","path":"%s/rig-sl","prefix":"sl"}]}\n' \
            "$STUB_ROOT" "$STUB_ROOT" "$STUB_ROOT" "$STUB_ROOT"
        exit 0 ;;
    "bd show")
        st="$(awk -F'\t' -v id="$3" '$1 == id { print $2 }' "$STUB_STATUS")"
        case "$st" in
            '') printf '{"error":"no issues found matching the provided IDs","schema_version":1}\n'; exit 1 ;;
            unreadable) echo "dial tcp: connection refused" >&2; exit 1 ;;
            *) printf '[{"id":"%s","status":"%s"}]\n' "$3" "$st"; exit 0 ;;
        esac ;;
esac
echo "stub gc: unexpected call: $*" >&2
exit 3
STUB
chmod +x "$BIN/gc"
export PATH="$BIN:$PATH"
status() { printf '%s\t%s\n' "$1" "$2" >> "$STUB_STATUS"; }

# Age every entry under <path> to <hours> old, the path itself included. GNU
# and BSD touch -d both read a UTC ISO-8601 stamp.
age() { # <path> <hours>
    local at
    at="$(jq -nr --argjson t "$(($(date +%s) - $2 * 3600))" '$t | todate')"
    find "$1" -depth -exec touch -h -d "$at" {} +
}

# --- path ----------------------------------------------------------------------
eq "$(bash "$SUT" path --review-bead tk-abc)" "$WS/gc-review-tk-abc" "path names the workspace for the bead"
for id in "../x" "a/b" ".hidden" "tk-a..b" ""; do
    bash "$SUT" path --review-bead "$id" >/dev/null 2>&1
    eq "$?" "2" "path refuses the id '$id'"
done
bash "$SUT" frobnicate >/dev/null 2>&1; eq "$?" "2" "an unknown subcommand is a usage error"

# --- add -----------------------------------------------------------------------
cd "$REPO" || exit 1
WT="$(bash "$SUT" add --review-bead tk-abc --oid "$C1" 2>/dev/null)"
eq "$?" "0" "add exits 0"
eq "$WT" "$WS/gc-review-tk-abc/wt" "add prints the worktree path inside the workspace"
eq "$(git -C "$WT" rev-parse HEAD)" "$C1" "the worktree is at the commit"
eq "$(git -C "$WT" symbolic-ref -q HEAD || echo detached)" "detached" "the worktree is detached"
if is_registered "$WT"; then ok "the worktree is registered in the repository"; else bad "the worktree is registered in the repository"; fi
eq "$(ls -ld "$WS/gc-review-tk-abc" | cut -c1-10)" "drwx------" "the workspace is private to its user"

touch "$WT/marker"
eq "$(bash "$SUT" add --review-bead tk-abc --oid "$C1" 2>/dev/null)" "$WT" "add at the same commit prints the same path"
if exists "$WT/marker"; then ok "add at the same commit reuses the worktree as it stands"; else bad "add at the same commit reuses the worktree as it stands"; fi

eq "$(bash "$SUT" add --review-bead tk-abc --oid "$C2" 2>/dev/null)" "$WT" "add at another commit keeps the path"
eq "$(git -C "$WT" rev-parse HEAD)" "$C2" "add at another commit rebuilds the worktree there"
if exists "$WT/marker"; then bad "the rebuilt worktree starts clean"; else ok "the rebuilt worktree starts clean"; fi

cd "$TMP" || exit 1
WT="$(bash "$SUT" add --review-bead tk-repo --oid "$C1" --repo "$REPO" 2>/dev/null)"
eq "$(git -C "$WT" rev-parse HEAD)" "$C1" "--repo names the repository from another directory"

# A full-length sha resolves without the object existing unless it is peeled,
# so this one checks that add asks for a commit rather than a name.
for oid in deadbeef 0123456789abcdef0123456789abcdef01234567; do
    bash "$SUT" add --review-bead tk-bad --oid "$oid" --repo "$REPO" >/dev/null 2>&1
    eq "$?" "1" "add refuses $oid, which is not a commit"
done
if exists "$WS/gc-review-tk-bad"; then bad "a refused add leaves no workspace"; else ok "a refused add leaves no workspace"; fi

mkdir -p "$TMP/elsewhere"
ln -s "$TMP/elsewhere" "$WS/gc-review-tk-link"
bash "$SUT" add --review-bead tk-link --oid "$C1" --repo "$REPO" >/dev/null 2>&1
eq "$?" "1" "add refuses a workspace name that is a symlink"
eq "$(ls -A "$TMP/elsewhere")" "" "and writes nothing through it"
rm -f "$WS/gc-review-tk-link"

# Parallel shells of one review run add at once; every one gets the worktree.
for n in 1 2 3 4 5 6; do
    (bash "$SUT" add --review-bead tk-race --oid "$C1" --repo "$REPO" > "$TMP/race.$n" 2>/dev/null; echo "$?" > "$TMP/race.$n.rc") &
done
wait
for n in 1 2 3 4 5 6; do
    eq "$(cat "$TMP/race.$n.rc")/$(cat "$TMP/race.$n")" "0/$WS/gc-review-tk-race/wt" "concurrent add $n succeeds with the one path"
done
eq "$(git -C "$REPO" worktree list --porcelain | grep -cxF "worktree $WS/gc-review-tk-race/wt")" "1" "concurrent adds register one worktree"

WT="$(bash "$SUT" add --review-bead tk-stale --oid "$C1" --repo "$REPO" 2>/dev/null)"
rm -rf "$WS/gc-review-tk-stale"
WT2="$(bash "$SUT" add --review-bead tk-stale --oid "$C1" --repo "$REPO" 2>/dev/null)"
eq "$?" "0" "add re-creates a worktree whose directory was deleted by hand"
eq "$(git -C "$WT2" rev-parse HEAD 2>/dev/null)" "$C1" "the re-created worktree is at the commit"

# --- remove --------------------------------------------------------------------
WT="$(bash "$SUT" add --review-bead tk-rm --oid "$C1" --repo "$REPO" 2>/dev/null)"
g worktree add -q --detach "$WS/gc-review-tk-rm/base" "$C2"
g worktree add -q --detach "$WT/nested" "$C2"
mkdir -p "$WS/gc-review-tk-rm/gomod/pkg"; touch "$WS/gc-review-tk-rm/gomod/pkg/f"
chmod -R a-w "$WS/gc-review-tk-rm/gomod"
# Another worktree's directory deleted by hand: its registration is
# worktree-reap's to pin and prune, never a side effect of this script.
g worktree add -q --detach "$TMP/other" "$C1"; rm -rf "$TMP/other"
OUT="$(run remove --review-bead tk-rm)"
eq "$?" "0" "remove exits 0"
if exists "$WS/gc-review-tk-rm"; then bad "remove takes the whole workspace"; else ok "remove takes the whole workspace"; fi
for p in "$WT" "$WS/gc-review-tk-rm/base" "$WT/nested"; do
    if is_registered "$p"; then bad "remove deregisters ${p#"$WS"/}"; else ok "remove deregisters ${p#"$WS"/}"; fi
done
if is_registered "$TMP/other"; then ok "remove prunes nothing outside the workspace"; else bad "remove prunes nothing outside the workspace"; fi
g worktree prune
OUT="$(run remove --review-bead tk-rm)"
eq "$?" "0" "remove of an absent workspace exits 0"
has "$OUT" "no workspace" "and says there was none"

# --- the formulas' own lines ---------------------------------------------------
extract() { # <toml> <marker>
    awk -v m="$2" '$0 ~ ("# >>> " m "$") {f=1; next} $0 ~ ("# <<< " m "$") {f=0} f' "$1"
}
ADD="$(extract "$ROOT/formulas/mol-review.toml" review-workspace-add)"
REMOVE="$(extract "$ROOT/formulas/mol-review.toml" review-workspace-remove)"
QREMOVE="$(extract "$ROOT/formulas/mol-review-quorum-signoff.toml" quorum-review-workspace-remove)"
for v in ADD REMOVE QREMOVE; do
    if [ -n "${!v}" ]; then ok "the formula's $v lines extract"; else bad "the formula's $v lines extract (markers missing)"; fi
done
PACK="$TMP/pack"; mkdir -p "$PACK/assets/scripts"; cp "$SUT" "$PACK/assets/scripts/"
cd "$REPO" || exit 1
# The add lines refuse to run without a rig root, so each run names this
# repository as the rig.
for n in 1 2; do
    GOT="$(GC_PACK_DIR="$PACK" GC_RIG_ROOT="$REPO" REVIEW_BEAD=tk-fx REVIEWED_OID="$C1" bash -c "$ADD
pwd -P" 2>/dev/null)"
    eq "$GOT" "$WS/gc-review-tk-fx/wt" "block $n running the formula's add lines stands in the review's worktree"
done
eq "$(git -C "$WS/gc-review-tk-fx/wt" rev-parse HEAD)" "$C1" "at the reviewed commit"
GC_PACK_DIR="$PACK" REVIEW_BEAD=tk-fx SC="$PACK/assets/scripts/step-close.sh" bash -c "$REMOVE" >/dev/null 2>&1
if exists "$WS/gc-review-tk-fx"; then bad "the verdict step's remove line takes the workspace"; else ok "the verdict step's remove line takes the workspace"; fi
GC_PACK_DIR="$PACK" GC_RIG_ROOT="$REPO" REVIEW_BEAD=tk-fq REVIEWED_OID="$C1" bash -c "$ADD" >/dev/null 2>&1
REVIEW_BEAD=tk-fq SC="$PACK/assets/scripts/step-close.sh" bash -c "$QREMOVE" >/dev/null 2>&1
if exists "$WS/gc-review-tk-fq"; then bad "the quorum's remove line takes the workspace"; else ok "the quorum's remove line takes the workspace"; fi

# --- reap ----------------------------------------------------------------------
export REVIEW_WORKSPACE_DIR="$TMP/ws-reap"
R="$REVIEW_WORKSPACE_DIR"; mkdir -p "$R"
cd "$REPO" || exit 1
mk() { # <name> <hours old> — a workspace directory with one file in it
    mkdir -p "$R/$1"; echo x > "$R/$1/log"; age "$R/$1" "$2"
}

WT_CLOSED="$(bash "$SUT" add --review-bead tk-closed --oid "$C1" 2>/dev/null)"; status tk-closed closed
mk gc-review-sl-done 1;          status sl-done closed
mk gc-review-lx-city 1;          status lx-city closed
# A name with anything after the bead id is not looked up: it ages out.
g worktree add -q --detach "$R/gc-review-tk-old.Ab12Cd" "$C1"; age "$R/gc-review-tk-old.Ab12Cd" 48
status tk-old closed
mk gc-review-tk-new.Zz99Yy 1;    status tk-new closed
mk gc-review-tk-open 100;        status tk-open open
mk gc-review-tk-prog 100;        status tk-prog in_progress
mk gc-review-tk-unread 100;      status tk-unread unreadable
mk gc-review-tk-gone 48
mk gc-review-tk-gonefresh 1
mk gc-review-probe.Xy12Ab 48
echo x > "$R/gc-review-db-status.out"; age "$R/gc-review-db-status.out" 48
mk gc-review-render 1
mk gc-review-mixed 100; touch "$R/gc-review-mixed/recent"
mk gc-review-tk-held 100;        status tk-held closed
mk gc-review-tk-fdheld 100;      status tk-fdheld closed
mkdir -p "$TMP/target"; echo keep > "$TMP/target/f"
ln -s "$TMP/target" "$R/gc-review-tk-symclosed"; status tk-symclosed closed
mk other-tenant 100

(cd "$R/gc-review-tk-held" && exec sleep 120) & PIDS+=("$!"); HELD_PID=$!
(exec 3< "$R/gc-review-tk-fdheld/log"; exec sleep 120) & PIDS+=("$!"); FD_PID=$!
# A backgrounded subshell forks first and only then changes directory or opens
# its file, so wait for lsof, the probe the reap reads, to show both.
lists() { # <pid> <path>
    lsof -w -n -P -F n -p "$1" 2>/dev/null | awk -v n="n$2" '$0 == n { f = 1 } END { exit f ? 0 : 1 }'
}
for _ in $(seq 50); do
    lists "$HELD_PID" "$R/gc-review-tk-held" && lists "$FD_PID" "$R/gc-review-tk-fdheld/log" && break
    sleep 0.1
done

: > "$STUB_GC_LOG"
OUT="$(run reap --dry-run)"
eq "$?" "0" "a dry run exits 0"
has "$OUT" "remove $R/gc-review-tk-closed (review tk-closed closed)" "the dry run names what it would remove, and why"
has "$OUT" "keep   $R/gc-review-tk-open (review tk-open not closed)" "and what it would keep, and why"
hasnt "$OUT" "/tmp/gc-review-" "a pass given REVIEW_WORKSPACE_DIR reads no other directory"
if exists "$WT_CLOSED"; then ok "a dry run removes nothing"; else bad "a dry run removes nothing"; fi

STUB_RIGS_FAIL=1 run reap > "$TMP/norigs.out"
eq "$?" "1" "unreadable rigs fail the pass"
has "$(cat "$TMP/norigs.out")" "reaping nothing" "and say so"
if exists "$WT_CLOSED"; then ok "unreadable rigs reap nothing"; else bad "unreadable rigs reap nothing"; fi

OUT="$(run reap)"
eq "$?" "0" "the pass exits 0"
gone_ok() { if exists "$R/$1"; then bad "$2"; else ok "$2"; fi; }
kept_ok() { if exists "$R/$1"; then ok "$2"; else bad "$2"; fi; }
gone_ok gc-review-tk-closed          "the workspace of a closed review goes"
if is_registered "$WT_CLOSED"; then bad "and its worktree registration with it"; else ok "and its worktree registration with it"; fi
gone_ok gc-review-sl-done            "a closed review in another rig's store goes"
has "$(cat "$STUB_GC_LOG")" "bd show sl-done --db $TMP/rig-sl/.beads --json" "a bead is looked up in the store its prefix names"
has "$(cat "$STUB_GC_LOG")" "bd show lx-city --db $TMP/.beads --json" "the city's own prefix reads the city store"
gone_ok gc-review-lx-city            "a closed review in the city store goes"
gone_ok gc-review-tk-old.Ab12Cd      "a suffixed name idle past the horizon goes"
if is_registered "$R/gc-review-tk-old.Ab12Cd"; then bad "and its worktree registration with it"; else ok "and its worktree registration with it"; fi
kept_ok gc-review-tk-new.Zz99Yy      "a suffixed name inside the horizon is kept, its bead unread"
hasnt "$(cat "$STUB_GC_LOG")" "bd show tk-new" "a suffixed name is never looked up"
kept_ok gc-review-tk-open            "an open review holds its workspace at any age"
kept_ok gc-review-tk-prog            "an in-progress review holds its workspace at any age"
kept_ok gc-review-tk-unread          "an unreadable status holds the workspace"
gone_ok gc-review-tk-gone            "a bead the ledger no longer has ages out past the horizon"
kept_ok gc-review-tk-gonefresh       "and is kept inside it"
gone_ok gc-review-probe.Xy12Ab       "a name with no bead ages out past the horizon"
gone_ok gc-review-db-status.out      "a loose file with no bead ages out too"
kept_ok gc-review-render             "a name with no bead is kept inside the horizon"
kept_ok gc-review-mixed              "the newest entry sets the age, so one recent file keeps the workspace"
kept_ok gc-review-tk-held            "a process standing in a closed review's workspace holds it"
kept_ok gc-review-tk-fdheld          "a process holding a file open in it holds it"
gone_ok gc-review-tk-symclosed       "a symlink named for a closed review is unlinked"
eq "$(cat "$TMP/target/f" 2>/dev/null)" "keep" "and its target is untouched"
kept_ok other-tenant                 "an entry not named gc-review-* is never read"
has "$OUT" "removed 8 workspaces" "the summary counts the removals"
has "$OUT" "4 of closed reviews, 4 idle" "split by the gate that took them"
has "$OUT" "kept 2 of reviews not closed, 2 in use, 1 unreadable, 4 active" "and the keeps by the gate that held them"

kill "$HELD_PID" "$FD_PID" 2>/dev/null; wait "$HELD_PID" "$FD_PID" 2>/dev/null

# An lsof that lists nothing at all, or that fails after listing part of the
# host, cannot prove a workspace unheld.
NOLSOF="$TMP/nolsof-bin"; mkdir -p "$NOLSOF"
printf '#!/usr/bin/env bash\nexit 0\n' > "$NOLSOF/lsof"
FAILLSOF="$TMP/faillsof-bin"; mkdir -p "$FAILLSOF"
printf '#!/usr/bin/env bash\nprintf "p1\\nfcwd\\nn/\\n"\nexit 1\n' > "$FAILLSOF/lsof"
chmod +x "$NOLSOF/lsof" "$FAILLSOF/lsof"
OUT="$(PATH="$NOLSOF:$PATH" run reap)"
kept_ok gc-review-tk-held            "an lsof that lists nothing holds every workspace"
has "$OUT" "2 in use" "and counts them as in use"
OUT="$(PATH="$FAILLSOF:$PATH" run reap)"
kept_ok gc-review-tk-held            "an lsof that fails holds every workspace, whatever it listed first"
has "$OUT" "2 in use" "and counts them as in use"

OUT="$(run reap)"
gone_ok gc-review-tk-held            "once the process exits, the next pass takes the workspace"
gone_ok gc-review-tk-fdheld          "and the one whose file it held"
has "$OUT" "removed 2 workspaces" "the next pass counts them"

# An age that cannot be read is not idle. stat answers every read but the mtime,
# so the ledger and ownership gates still run, and a closed review's workspace
# is taken in the same pass.
mk gc-review-tk-ageless 48
mk gc-review-tk-closed2 1;       status tk-closed2 closed
NOMTIME="$TMP/nomtime-bin"; mkdir -p "$NOMTIME"
printf '#!/usr/bin/env bash\ncase " $* " in *" %%Y "* | *" %%m "*) exit 1 ;; esac\nexec %s "$@"\n' "$(command -v stat)" > "$NOMTIME/stat"
chmod +x "$NOMTIME/stat"
OUT="$(PATH="$NOMTIME:$PATH" run reap --dry-run)"
has "$OUT" "keep   $R/gc-review-tk-ageless (age unreadable)" "the dry run names an unreadable age as the reason to keep"
OUT="$(PATH="$NOMTIME:$PATH" run reap)"
kept_ok gc-review-tk-ageless         "an entry whose age cannot be read is held past the horizon"
gone_ok gc-review-tk-closed2         "while a closed review's workspace is taken in the same pass"
OUT="$(run reap)"
gone_ok gc-review-tk-ageless         "once its age reads, the entry ages out"

REVIEW_WORKSPACE_IDLE_AFTER=abc bash "$SUT" reap >/dev/null 2>&1
eq "$?" "2" "a horizon that is not a whole number is a usage error"
REVIEW_WORKSPACE_IDLE_AFTER=0 bash "$SUT" reap >/dev/null 2>&1
eq "$?" "2" "a zero horizon is a usage error"

echo
echo "review-workspace.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
