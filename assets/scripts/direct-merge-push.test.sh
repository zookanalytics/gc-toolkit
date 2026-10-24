#!/usr/bin/env bash
# Hermetic test for direct-merge-push.sh, the refinery's direct-mode landing.
#
# Runs the real script against real git repositories: a bare origin, the rig
# cloned from it, and the prep worktree the rebase step leaves at
# <rig git dir>/gc-refinery-prep. lifecycle.sh and gc are stubs that log their
# calls, and gc keeps the bead in a file its updates write. Proves:
#   - a prepared head that fast-forwards origin/main is stamped on the bead as
#     direct_landing_sha before the push, lands by commit id, is read back from
#     origin, and is recorded and closed through one lifecycle transition handed
#     the rig as GC_RIG_ROOT, which clears the stamp, with no scratch worktree,
#     no scratch file and no local branch moved;
#   - a bead the stamp does not reach, or whose stamp does not read back, is
#     not pushed;
#   - a prepared head origin/main moved past since it was prepared lands
#     nothing, records nothing and exits 4, whether origin/main moved before the
#     fetch or while the landing was stamped, and one that shares no history
#     with origin/main exits 1;
#   - a prepared head origin/main already carries closes as that tip, or at the
#     bead's stamp when origin/main carries the stamp too, and a bead that does
#     not read back is not recorded and keeps its stamp, so a later attempt
#     records the landing at the stamp and not at a later tip;
#   - a landing whose read-back fetch or transition fails is tried again, and
#     one that still fails exits 1 and keeps its stamp, so the next patrol's
#     attempt records it at the stamp, whether origin/main stayed at the
#     landing or moved on past it;
#   - a transition that writes and then fails, on any try, is recorded once the
#     bead reads merged at the landing, and is not written again;
#   - a commit landed on top of the push before the read-back does not fail it;
#   - a push that reports a failure after origin took it is read back and
#     recorded, and one whose target cannot be fetched again exits 1 and keeps
#     its stamp for the next patrol;
#   - a push refused for branch protection promotes the bead to
#     merge_strategy=pr and clears the stamp in one write, and exits 3, and any
#     other refused push, or a push origin does not read back, exits 1;
#   - a pause with a leading zero is read in base 10;
#   - an unresolvable rig and a missing prepared head land nothing;
#   - a prep worktree that records another bead's staging, or no staging,
#     lands, stamps and records nothing, before any store call;
#   - the script never drains the session.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-direct-merge-push-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "missing '$2' in: $1" ;; esac; }

command -v git >/dev/null 2>&1 || { echo "git is required" >&2; exit 1; }
command -v jq  >/dev/null 2>&1 || { echo "jq is required"  >&2; exit 1; }

unset GC_RIG_ROOT GC_RIG GC_CITY_PATH GC_PACK_DIR GC_BD_LIB GC_RECONCILE_BD_CACHE 2>/dev/null || true
unset DIRECT_MERGE_PUSH_ATTEMPTS DIRECT_MERGE_PUSH_BACKOFF 2>/dev/null || true
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR 2>/dev/null || true
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# The script under test, the bd-lib.sh it sources and the
# refinery-workspace.sh it checks the prep worktree's record with, beside a stub
# lifecycle.sh that logs each transition and the GC_RIG_ROOT it was handed. The
# stub refuses every call when LC_FAIL is set, and the first LC_FAIL_TIMES calls
# when that is set. With LC_WRITE_RC set, a call it does not refuse writes the
# transition to the bead file, as the real writer's one update does, and then
# exits LC_WRITE_RC; lifecycle.sh exits 2 when its read-back does not verify
# what it wrote.
SUT="$TMP/sut"
mkdir -p "$SUT" "$TMP/bin" "$TMP/gitshim" "$TMP/sleepshim"
cp "$HERE/direct-merge-push.sh" "$HERE/bd-lib.sh" "$HERE/refinery-workspace.sh" "$SUT/"
chmod +x "$SUT/direct-merge-push.sh"
cat > "$SUT/lifecycle.sh" <<'LC'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_LC_LOG"
echo "${GC_RIG_ROOT:-<unset>}" >> "$FAKE_LC_LOG.root"
[ -z "${LC_FAIL:-}" ] || { echo "lifecycle: refused" >&2; exit 1; }
if [ -n "${LC_FAIL_TIMES:-}" ] && [ "$(wc -l < "$FAKE_LC_LOG" | tr -d ' ')" -le "$LC_FAIL_TIMES" ]; then
  echo "lifecycle: the store is busy" >&2
  exit 1
fi
[ -n "${LC_WRITE_RC:-}" ] || exit 0
shift 2
while [ $# -gt 0 ]; do
  v=""
  case "$1" in
    --to) prog='.[0].metadata.merge_result = $v'; v="$2"; shift ;;
    --set) prog='.[0].metadata[($v | sub("=.*$"; ""))] = ($v | sub("^[^=]*="; ""))'; v="$2"; shift ;;
    --unset) prog='del(.[0].metadata[$v])'; v="$2"; shift ;;
    --close) prog='.[0].status = "closed"' ;;
    --append-notes) prog='.[0].notes = ((.[0].notes // "") + (if (.[0].notes // "") == "" then "" else "\n" end) + $v)'; v="$2"; shift ;;
    *) prog="" ;;
  esac
  [ -z "$prog" ] || { jq --arg v "$v" "$prog" "$FAKE_BEAD" > "$FAKE_BEAD.new" && mv "$FAKE_BEAD.new" "$FAKE_BEAD"; }
  shift
done
[ "$LC_WRITE_RC" = 0 ] || echo "lifecycle: wrote but did NOT verify" >&2
exit "$LC_WRITE_RC"
LC
chmod +x "$SUT/lifecycle.sh"
# gc answers the roster for `rig list` and the bead file for `bd show`, applies
# each --set-metadata and --unset-metadata of a `bd update` to that file, and
# logs every call. BD_UPDATE_DROP makes an update exit 0 and write nothing,
# which `gc bd update` can do. BD_UPDATE_THEN names a command each update runs
# once it has written. BD_SHOW_FAIL makes `bd show` answer with an error object
# and exit 1, as a store that does not return the bead does.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_GC_LOG"
case "$1 $2" in
  "rig list") cat "$FAKE_ROSTER" ;;
  "bd show")
    if [ -n "${BD_SHOW_FAIL:-}" ]; then
      echo '{"error":"the store did not answer"}'
      exit 1
    fi
    cat "$FAKE_BEAD" ;;
  "bd update")
    [ -z "${BD_UPDATE_DROP:-}" ] || exit 0
    shift 3
    while [ $# -gt 0 ]; do
      case "$1" in
        --set-metadata)
          jq --arg kv "$2" '.[0].metadata[($kv | sub("=.*$"; ""))] = ($kv | sub("^[^=]*="; ""))' "$FAKE_BEAD" > "$FAKE_BEAD.new" \
            && mv "$FAKE_BEAD.new" "$FAKE_BEAD"
          shift 2 ;;
        --unset-metadata)
          jq --arg k "$2" 'del(.[0].metadata[$k])' "$FAKE_BEAD" > "$FAKE_BEAD.new" && mv "$FAKE_BEAD.new" "$FAKE_BEAD"
          shift 2 ;;
        *) shift ;;
      esac
    done
    [ -z "${BD_UPDATE_THEN:-}" ] || "$BD_UPDATE_THEN" ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH"
# A git that fails a fetch from origin once FETCH_FAIL_MARK exists, which the
# origin's post-receive hook creates, so only the fetches after the push fail:
# the first FETCH_FAIL_TIMES of them. With PUSH_REPLY_LOST set, a push to
# origin runs and then reports a failure, as a push whose reply is lost does.
REAL_GIT=$(command -v git)
{ printf '#!/usr/bin/env bash\n'; printf 'REAL_GIT=%q\n' "$REAL_GIT"; cat; } > "$TMP/gitshim/git" <<'SHIM'
case " $* " in
  *" push origin "*)
    if [ -n "${PUSH_REPLY_LOST:-}" ]; then
      "$REAL_GIT" "$@" >/dev/null 2>&1
      echo "fatal: the remote end hung up unexpectedly" >&2
      exit 128
    fi ;;
  *" fetch origin "*)
    if [ -n "${FETCH_FAIL_MARK:-}" ] && [ -e "$FETCH_FAIL_MARK" ]; then
      n=$(( $(cat "$FETCH_FAIL_MARK.count" 2>/dev/null || echo 0) + 1 ))
      echo "$n" > "$FETCH_FAIL_MARK.count"
      if [ "$n" -le "${FETCH_FAIL_TIMES:-0}" ]; then
        echo "fatal: unable to access origin: the network is down" >&2
        exit 128
      fi
    fi ;;
esac
exec "$REAL_GIT" "$@"
SHIM
chmod +x "$TMP/gitshim/git"
# A sleep that logs its pause to SLEEP_LOG and returns at once.
printf '#!/usr/bin/env bash\necho "$*" >> "$SLEEP_LOG"\n' > "$TMP/sleepshim/sleep"
chmod +x "$TMP/sleepshim/sleep"

commit() { git -C "$1" commit -q --allow-empty -m "$2"; git -C "$1" rev-parse HEAD; }
wt_count() { git -C "$1" worktree list --porcelain | grep -c '^worktree '; }
stamp() { jq -r '.[0].metadata.direct_landing_sha // "none"' "$D/bead.json"; }
transitions() { if [ -s "$D/lc.log" ]; then wc -l < "$D/lc.log" | tr -d ' '; else echo 0; fi; }

# setup <dir>: origin with main and polecat/wb one commit ahead, the rig
# cloned from it, the prep worktree staged for wb at polecat/wb, and the bead.
# Sets D, BASE, FEATURE and PREP.
setup() {
  D="$1"
  mkdir -p "$D/tmp"
  git init -q --bare -b main "$D/origin.git"
  git init -q -b main "$D/seed"
  BASE=$(commit "$D/seed" "base")
  git -C "$D/seed" push -q "$D/origin.git" main
  git -C "$D/seed" checkout -q -b polecat/wb
  FEATURE=$(commit "$D/seed" "feature")
  git -C "$D/seed" push -q "$D/origin.git" polecat/wb
  git -C "$D/seed" checkout -q main
  git clone -q "$D/origin.git" "$D/rig"
  PREP="$(git -C "$D/rig" rev-parse --path-format=absolute --git-common-dir)/gc-refinery-prep"
  "$SUT/refinery-workspace.sh" stage --rig-root "$D/rig" --branch polecat/wb --work wb >/dev/null 2>&1
  printf '{"rigs":[{"name":"myrig","path":"%s"}]}\n' "$D/rig" > "$D/roster.json"
  printf '%s\n' '[{"id":"wb","status":"in_progress","metadata":{"branch":"polecat/wb","target":"main"}}]' > "$D/bead.json"
  : > "$D/gc.log"; : > "$D/lc.log"
}

# run [<env>...]: the script from a directory outside every repository, with
# GC_RIG_ROOT naming the rig unless the case overrides it, and no pause between
# tries. Sets RC and OUT.
run() {
  OUT=$(cd "$D/tmp" && env TMPDIR="$D/tmp" GC_RIG_ROOT="$D/rig" GC_RIG=myrig FAKE_ROSTER="$D/roster.json" \
    FAKE_GC_LOG="$D/gc.log" FAKE_LC_LOG="$D/lc.log" FAKE_BEAD="$D/bead.json" DIRECT_MERGE_PUSH_BACKOFF=0 \
    "$@" "$SUT/direct-merge-push.sh" --work wb --target main 2>&1)
  RC=$?
}
# next_patrol: what the next patrol's rebase step does before it lands again:
# fetch, stage the prep worktree at origin/polecat/wb, and merge origin/main in.
# The logs start over, so each attempt's assertions read only its own calls.
next_patrol() {
  git -C "$D/rig" fetch -q origin
  "$SUT/refinery-workspace.sh" stage --rig-root "$D/rig" --branch polecat/wb --work wb >/dev/null 2>&1
  git -C "$PREP" merge -q --no-edit origin/main
  : > "$D/gc.log"; : > "$D/lc.log"; : > "$D/lc.log.root"
}
no_drain() {
  if grep -q 'runtime drain-ack' "$D/gc.log"; then bad "$1: the script does not drain the session"; else ok "$1: the script does not drain the session"; fi
}
no_transition() {
  if [ -s "$D/lc.log" ]; then bad "$1: no lifecycle transition" "$(cat "$D/lc.log")"; else ok "$1: no lifecycle transition"; fi
}
recorded_at() { # <label> <sha>: exactly one transition, recording and closing at <sha> and clearing the stamp
  case "$(cat "$D/lc.log")" in
    "transition wb --to merged --close --set merged_sha=$2 --set merged_target=main --unset rejection_reason --unset direct_landing_sha --append-notes Merged to main at "*)
      ok "$1: recorded and closed at ${2:0:9} through one lifecycle transition that clears the stamp" ;;
    *) bad "$1: recorded and closed at ${2:0:9} through one lifecycle transition that clears the stamp" "$(cat "$D/lc.log")" ;;
  esac
}

echo "── a prepared head that fast-forwards main lands by commit id ──"
setup "$TMP/ff"
# The stamp the bead carries at the moment origin receives the push.
cat > "$D/origin.git/hooks/pre-receive" <<HOOK
#!/usr/bin/env bash
jq -r '.[0].metadata.direct_landing_sha // "none"' "$D/bead.json" > "$D/stamp-at-push"
HOOK
chmod +x "$D/origin.git/hooks/pre-receive"
RIG_HEAD_BEFORE=$(git -C "$D/rig" rev-parse HEAD)
run
eq "$RC" 0 "ff: exits 0"
eq "$(cat "$D/stamp-at-push" 2>/dev/null)" "$FEATURE" "ff: the bead carries the stamp when origin receives the push"
has "$(cat "$D/gc.log")" "bd update wb --set-metadata direct_landing_sha=$FEATURE" "ff: the stamp is written through gc bd"
eq "$(git -C "$D/origin.git" rev-parse main)" "$FEATURE" "ff: origin/main is the prepared head"
eq "$(git -C "$D/rig" rev-parse origin/main)" "$FEATURE" "ff: the rig's origin/main is read back at the prepared head"
recorded_at ff "$FEATURE"
eq "$(transitions)" 1 "ff: exactly one transition"
eq "$(cat "$D/lc.log.root")" "$D/rig" "ff: the transition is handed the rig as GC_RIG_ROOT"
eq "$(wt_count "$D/rig")" 2 "ff: no worktree is added; the rig and its prep worktree remain"
eq "$(ls -A "$D/tmp" | wc -l | tr -d ' ')" 0 "ff: nothing is written under TMPDIR"
eq "$(git -C "$D/rig" rev-parse HEAD)" "$RIG_HEAD_BEFORE" "ff: the rig's HEAD does not move"
eq "$(git -C "$D/rig" for-each-ref --format='%(refname)' refs/heads/ | tr '\n' ' ')" "refs/heads/main " "ff: no local branch is created"
no_drain ff

echo "── the roster names the rig when GC_RIG_ROOT is empty ──"
setup "$TMP/roster"
run GC_RIG_ROOT=
eq "$RC" 0 "roster: exits 0"
eq "$(git -C "$D/origin.git" rev-parse main)" "$FEATURE" "roster: the prepared head landed on the rig's origin"
eq "$(cat "$D/lc.log.root")" "$D/rig" "roster: the transition is handed the rig the roster named"

echo "── a bead the stamp does not reach is not pushed ──"
setup "$TMP/nostamp"
run BD_UPDATE_DROP=1
eq "$RC" 1 "nostamp: exits 1"
has "$OUT" "could not stamp direct_landing_sha=$FEATURE on wb" "nostamp: it says the stamp did not land"
eq "$(git -C "$D/origin.git" rev-parse main)" "$BASE" "nostamp: nothing pushed"
no_transition nostamp
no_drain nostamp

echo "── a stamp that does not read back is not pushed ──"
setup "$TMP/unread-stamp"
run BD_SHOW_FAIL=1
eq "$RC" 1 "unread-stamp: exits 1"
has "$OUT" "could not stamp direct_landing_sha=$FEATURE on wb (it reads back unreadable" "unread-stamp: it says the stamp did not read back"
eq "$(git -C "$D/origin.git" rev-parse main)" "$BASE" "unread-stamp: nothing pushed"
no_transition unread-stamp
no_drain unread-stamp

echo "── origin/main moved past the prepared head: nothing lands, exit 4 ──"
setup "$TMP/moved"
MOVED=$(commit "$D/seed" "landed while the gate ran")
git -C "$D/seed" push -q "$D/origin.git" main
run
eq "$RC" 4 "moved: exits 4"
has "$OUT" "is not a fast-forward of origin/main" "moved: it says the target moved"
eq "$(git -C "$D/origin.git" rev-parse main)" "$MOVED" "moved: origin/main is untouched"
eq "$(stamp)" none "moved: nothing is stamped"
no_transition moved
no_drain moved

echo "── origin/main moved while the landing was stamped: nothing lands, exit 4 ──"
setup "$TMP/moved-stamp"
MOVED=$(commit "$D/seed" "landed while the landing was stamped")
printf '#!/usr/bin/env bash\ngit -C %q push -q %q main\n' "$D/seed" "$D/origin.git" > "$D/move.sh"
chmod +x "$D/move.sh"
run BD_UPDATE_THEN="$D/move.sh"
eq "$RC" 4 "moved-stamp: exits 4"
has "$OUT" "origin/main has moved from $BASE to $MOVED since it was fetched" "moved-stamp: it says the target moved after the fetch"
eq "$(git -C "$D/origin.git" rev-parse main)" "$MOVED" "moved-stamp: origin/main is untouched by the refused push"
eq "$(stamp)" "$FEATURE" "moved-stamp: the stamp names the refused push, a commit origin/main does not carry"
no_transition moved-stamp
no_drain moved-stamp

echo "── origin/main shares no history with the prepared head: nothing lands ──"
setup "$TMP/unrelated"
git -C "$D/seed" checkout -q --orphan unrelated
UNRELATED=$(commit "$D/seed" "an unrelated root")
git -C "$D/seed" push -q -f "$D/origin.git" HEAD:main
run
eq "$RC" 1 "unrelated: exits 1"
has "$OUT" "share no history" "unrelated: it says why"
eq "$(git -C "$D/origin.git" rev-parse main)" "$UNRELATED" "unrelated: origin/main is untouched"
no_transition unrelated
no_drain unrelated

echo "── origin/main already carries the prepared head: it closes as that tip ──"
setup "$TMP/landed"
git -C "$D/seed" checkout -q polecat/wb
AHEAD=$(commit "$D/seed" "landed on top")
git -C "$D/seed" push -q "$D/origin.git" "HEAD:main"
# A stamp origin/main does not carry, left by a push that did not land.
git -C "$D/seed" checkout -q -b side "$BASE"
SIDE=$(commit "$D/seed" "a push that never landed")
git -C "$D/seed" push -q "$D/origin.git" side
git -C "$D/rig" fetch -q origin
jq --arg s "$SIDE" '.[0].metadata.direct_landing_sha = $s' "$D/bead.json" > "$D/bead.json.new" && mv "$D/bead.json.new" "$D/bead.json"
run
eq "$RC" 0 "landed: exits 0"
eq "$(git -C "$D/origin.git" rev-parse main)" "$AHEAD" "landed: origin/main stays at its tip"
recorded_at "landed, a stamp origin/main does not carry" "$AHEAD"
case "$(cat "$D/gc.log")" in *"bd update"*) bad "landed: nothing is stamped, since nothing is pushed" "$(cat "$D/gc.log")" ;; *) ok "landed: nothing is stamped, since nothing is pushed" ;; esac

echo "── a push refused for branch protection promotes the bead ──"
setup "$TMP/protected"
cat > "$D/origin.git/hooks/pre-receive" <<'HOOK'
#!/usr/bin/env bash
echo "GH006: Protected branch update failed for refs/heads/main." >&2
exit 1
HOOK
chmod +x "$D/origin.git/hooks/pre-receive"
run
eq "$RC" 3 "protected: exits 3"
has "$(cat "$D/gc.log")" "bd update wb --set-metadata merge_strategy=pr --unset-metadata direct_landing_sha" "protected: one write promotes the bead to merge_strategy=pr and clears the stamp"
eq "$(jq -r '.[0].metadata.merge_strategy // "none"' "$D/bead.json")/$(stamp)" "pr/none" "protected: the bead reads merge_strategy=pr and no stamp"
eq "$(git -C "$D/origin.git" rev-parse main)" "$BASE" "protected: origin/main is untouched"
no_transition protected
no_drain protected

echo "── any other refused push stops ──"
setup "$TMP/refused"
cat > "$D/origin.git/hooks/pre-receive" <<'HOOK'
#!/usr/bin/env bash
echo "the remote is read-only today" >&2
exit 1
HOOK
chmod +x "$D/origin.git/hooks/pre-receive"
run
eq "$RC" 1 "refused: exits 1"
has "$OUT" "Push failed:" "refused: it says the push failed"
has "$OUT" "the remote is read-only today" "refused: it prints what the remote said"
case "$(cat "$D/gc.log")" in *"merge_strategy=pr"*) bad "refused: the bead is not promoted" ;; *) ok "refused: the bead is not promoted" ;; esac
no_transition refused
no_drain refused

echo "── a push origin took, whose reply was lost, is read back and recorded ──"
setup "$TMP/lost-reply"
run PATH="$TMP/gitshim:$PATH" PUSH_REPLY_LOST=1
eq "$RC" 0 "lost-reply: exits 0"
has "$OUT" "the push of $FEATURE reported a failure, but origin/main at $FEATURE carries it" "lost-reply: it says the push landed though it reported a failure"
eq "$(git -C "$D/origin.git" rev-parse main)" "$FEATURE" "lost-reply: origin/main is the prepared head"
recorded_at lost-reply "$FEATURE"
no_drain lost-reply

echo "── the same, when origin cannot be fetched again: the stamp stays, and the next patrol records it ──"
setup "$TMP/lost-reply-down"
printf '#!/usr/bin/env bash\ntouch %q\n' "$D/pushed" > "$D/origin.git/hooks/post-receive"
chmod +x "$D/origin.git/hooks/post-receive"
run PATH="$TMP/gitshim:$PATH" PUSH_REPLY_LOST=1 FETCH_FAIL_MARK="$D/pushed" FETCH_FAIL_TIMES=100
eq "$RC" 1 "lost-reply-down: exits 1"
has "$OUT" "could not be fetched again to tell whether the push landed anyway" "lost-reply-down: it says nothing shows whether the push landed"
has "$OUT" "wb keeps direct_landing_sha=$FEATURE" "lost-reply-down: it says the bead keeps the stamp"
eq "$(git -C "$D/origin.git" rev-parse main)" "$FEATURE" "lost-reply-down: the landing stands"
eq "$(stamp)" "$FEATURE" "lost-reply-down: the bead keeps the stamp"
no_transition lost-reply-down
no_drain lost-reply-down
next_patrol
run
eq "$RC" 0 "lost-reply-down, next patrol: exits 0"
recorded_at "lost-reply-down, next patrol" "$FEATURE"

echo "── a push origin does not read back stops before any bead state moves ──"
setup "$TMP/unverified"
cat > "$D/origin.git/hooks/post-receive" <<'HOOK'
#!/usr/bin/env bash
read -r old new ref
git update-ref "$ref" "$old"
HOOK
chmod +x "$D/origin.git/hooks/post-receive"
run
eq "$RC" 1 "unverified: exits 1"
has "$OUT" "PUSH FAILED — origin/main is $BASE, which does not carry $FEATURE" "unverified: it names what origin holds"
no_transition unverified
no_drain unverified

echo "── a commit landed on top of the push before the read-back ──"
setup "$TMP/ontop"
cat > "$D/origin.git/hooks/post-receive" <<'HOOK'
#!/usr/bin/env bash
read -r old new ref
git update-ref "$ref" "$(git commit-tree -p "$new" -m "landed right after" "$new^{tree}")"
HOOK
chmod +x "$D/origin.git/hooks/post-receive"
run
eq "$RC" 0 "ontop: exits 0"
eq "$(git -C "$D/origin.git" rev-parse main^)" "$FEATURE" "ontop: origin/main carries the push one commit down"
recorded_at ontop "$FEATURE"

echo "── a read-back fetch that fails once is tried again ──"
setup "$TMP/fetch-once"
printf '#!/usr/bin/env bash\ntouch %q\n' "$D/pushed" > "$D/origin.git/hooks/post-receive"
chmod +x "$D/origin.git/hooks/post-receive"
run PATH="$TMP/gitshim:$PATH" FETCH_FAIL_MARK="$D/pushed" FETCH_FAIL_TIMES=1
eq "$RC" 0 "fetch-once: exits 0"
eq "$(cat "$D/pushed.count" 2>/dev/null)" 2 "fetch-once: the read-back fetch ran twice"
recorded_at fetch-once "$FEATURE"

echo "── a transition that fails once is tried again ──"
setup "$TMP/lc-once"
run LC_FAIL_TIMES=1
eq "$RC" 0 "lc-once: exits 0"
eq "$(transitions)" 2 "lc-once: the transition ran twice"
eq "$(sed -n 1p "$D/lc.log")" "$(sed -n 2p "$D/lc.log")" "lc-once: the second try is the same transition"

echo "── a transition that writes and then fails its read-back has recorded the landing ──"
setup "$TMP/lc-wrote"
run LC_WRITE_RC=2
eq "$RC" 0 "lc-wrote: exits 0"
eq "$(transitions)" 1 "lc-wrote: the transition is not written again"
has "$OUT" "wb reads merge_result=merged at $FEATURE" "lc-wrote: it says the bead reads the landing"
eq "$(jq -r '.[0] | [.status, .metadata.merge_result, .metadata.merged_sha] | join(" ")' "$D/bead.json")" "closed merged $FEATURE" "lc-wrote: the bead reads closed and merged at the landing"
eq "$(jq -r '.[0].notes' "$D/bead.json" | grep -c '^Merged to main at ')" 1 "lc-wrote: one note records the landing"
no_drain lc-wrote

echo "── the same, on the last try ──"
setup "$TMP/lc-wrote-last"
run LC_FAIL_TIMES=2 LC_WRITE_RC=2
eq "$RC" 0 "lc-wrote-last: exits 0"
eq "$(transitions)" 3 "lc-wrote-last: the third try is the one that writes"
eq "$(jq -r '.[0].metadata.merge_result // "none"' "$D/bead.json")" merged "lc-wrote-last: the bead reads merged"

echo "── a pause with a leading zero is read in base 10 ──"
for b in 08 010; do
  setup "$TMP/backoff-$b"
  run PATH="$TMP/sleepshim:$PATH" SLEEP_LOG="$D/sleeps" DIRECT_MERGE_PUSH_BACKOFF="$b" LC_FAIL_TIMES=1
  eq "$RC" 0 "backoff $b: exits 0"
  eq "$(transitions)" 2 "backoff $b: the transition is tried again after the first one fails"
  eq "$(cat "$D/sleeps" 2>/dev/null)" "$((10#$b))" "backoff $b: the pause before the second try is $((10#$b)) seconds"
done

echo "── a transition that does not land keeps the stamp, and the next patrol records it ──"
setup "$TMP/lcfail"
run LC_FAIL=1
eq "$RC" 1 "lcfail: exits 1"
eq "$(git -C "$D/origin.git" rev-parse main)" "$FEATURE" "lcfail: the landing stands"
has "$OUT" "so wb has landed, but the transition recording it as merged did not land" "lcfail: it says the work landed unrecorded"
has "$OUT" "wb keeps direct_landing_sha=$FEATURE" "lcfail: it says the bead keeps the stamp"
eq "$(transitions)" 3 "lcfail: the transition is tried three times"
eq "$(stamp)" "$FEATURE" "lcfail: the bead keeps the stamp"
no_drain lcfail
next_patrol
eq "$(git -C "$PREP" rev-parse HEAD)" "$FEATURE" "lcfail, next patrol: precondition, its prepare stages origin/main itself"
run
eq "$RC" 0 "lcfail, next patrol: exits 0"
has "$OUT" "already carries the prepared head" "lcfail, next patrol: it pushes nothing"
recorded_at "lcfail, next patrol" "$FEATURE"
no_drain "lcfail, next patrol"

echo "── the same, after origin/main moved on past the landing ──"
setup "$TMP/lcfail-later"
run LC_FAIL=1
eq "$RC/$(stamp)" "1/$FEATURE" "lcfail-later: the landing is unrecorded and the bead keeps the stamp"
git -C "$D/seed" fetch -q "$D/origin.git" main
git -C "$D/seed" checkout -q -B main FETCH_HEAD
LATER=$(commit "$D/seed" "landed after the unrecorded landing")
git -C "$D/seed" push -q "$D/origin.git" main
next_patrol
eq "$(git -C "$PREP" rev-parse HEAD)" "$LATER" "lcfail-later, next patrol: precondition, its prepare stages the later tip"
run
eq "$RC" 0 "lcfail-later, next patrol: exits 0"
recorded_at "lcfail-later, next patrol (the landing, not the later tip)" "$FEATURE"
eq "$(git -C "$D/origin.git" rev-parse main)" "$LATER" "lcfail-later, next patrol: origin/main stays at the later tip"

echo "── the same, when the bead does not read back: nothing is recorded, and the stamp stays ──"
setup "$TMP/unread"
run LC_FAIL=1
eq "$RC/$(stamp)" "1/$FEATURE" "unread: the landing is unrecorded and the bead keeps the stamp"
git -C "$D/seed" fetch -q "$D/origin.git" main
git -C "$D/seed" checkout -q -B main FETCH_HEAD
LATER=$(commit "$D/seed" "landed after the unrecorded landing")
git -C "$D/seed" push -q "$D/origin.git" main
next_patrol
# The stub writes each transition here, so one recorded at the later tip
# would clear the stamp.
run BD_SHOW_FAIL=1 LC_WRITE_RC=0
eq "$RC" 1 "unread, next patrol: exits 1"
has "$OUT" "but wb did not read back" "unread, next patrol: it says the bead did not read back"
no_transition "unread, next patrol"
eq "$(stamp)" "$FEATURE" "unread, next patrol: the bead keeps the stamp"
eq "$(git -C "$D/origin.git" rev-parse main)" "$LATER" "unread, next patrol: origin/main stays at the later tip"
no_drain "unread, next patrol"
run LC_WRITE_RC=0
eq "$RC" 0 "unread, once the bead reads back: exits 0"
recorded_at "unread, once the bead reads back (the landing, not the later tip)" "$FEATURE"
eq "$(stamp)" none "unread, once the bead reads back: the transition clears the stamp"

echo "── a read-back fetch that keeps failing keeps the stamp, and the next patrol records it ──"
setup "$TMP/fetch-down"
printf '#!/usr/bin/env bash\ntouch %q\n' "$D/pushed" > "$D/origin.git/hooks/post-receive"
chmod +x "$D/origin.git/hooks/post-receive"
run PATH="$TMP/gitshim:$PATH" FETCH_FAIL_MARK="$D/pushed" FETCH_FAIL_TIMES=100
eq "$RC" 1 "fetch-down: exits 1"
has "$OUT" "PUSH UNVERIFIED" "fetch-down: it says the push could not be read back"
eq "$(cat "$D/pushed.count" 2>/dev/null)" 3 "fetch-down: the read-back fetch is tried three times"
eq "$(git -C "$D/origin.git" rev-parse main)" "$FEATURE" "fetch-down: the landing stands"
eq "$(stamp)" "$FEATURE" "fetch-down: the bead keeps the stamp"
no_transition fetch-down
next_patrol
run
eq "$RC" 0 "fetch-down, next patrol: exits 0"
recorded_at "fetch-down, next patrol" "$FEATURE"

echo "── an unresolvable rig lands nothing ──"
setup "$TMP/nomatch"
run GC_RIG_ROOT= GC_RIG=no-such-rig
eq "$RC" 1 "nomatch: exits 1"
has "$OUT" "cannot resolve the rig root" "nomatch: it says why"
eq "$(git -C "$D/origin.git" rev-parse main)" "$BASE" "nomatch: nothing pushed"
no_transition nomatch
no_drain nomatch

echo "── no prepared head lands nothing ──"
setup "$TMP/noprep"
git -C "$D/rig" worktree remove --force "$PREP"
run
eq "$RC" 1 "noprep: exits 1"
has "$OUT" "no prep worktree is staged at $PREP" "noprep: it says why"
eq "$(git -C "$D/origin.git" rev-parse main)" "$BASE" "noprep: nothing pushed"
no_transition noprep

echo "── a prep worktree staged for another bead lands nothing ──"
setup "$TMP/otherbead"
"$SUT/refinery-workspace.sh" stage --rig-root "$D/rig" --branch polecat/wb --work other >/dev/null 2>&1
run
eq "$RC" 1 "otherbead: exits 1"
has "$OUT" "holds polecat/wb for other, not wb; nothing landed" "otherbead: it names the bead the prep worktree holds, and says nothing landed"
eq "$(git -C "$D/origin.git" rev-parse main)" "$BASE" "otherbead: nothing pushed"
eq "$(stamp)" none "otherbead: no stamp is written"
eq "$(wc -l < "$D/gc.log" | tr -d ' ')" 0 "otherbead: the check comes before any store call"
no_transition otherbead
no_drain otherbead

echo "── a prep worktree that records nothing lands nothing ──"
setup "$TMP/norecord"
git -C "$D/rig" worktree remove --force --force "$PREP"
git -C "$D/rig" worktree add -q -f --detach "$PREP" origin/polecat/wb
run
eq "$RC" 1 "norecord: exits 1"
has "$OUT" "records no bead and branch" "norecord: it says why"
eq "$(git -C "$D/origin.git" rev-parse main)" "$BASE" "norecord: nothing pushed"
eq "$(stamp)" none "norecord: no stamp is written"
no_transition norecord

echo "── usage ──"
for args in "" "--work wb" "--target main" "--work wb --target main --extra" "--work"; do
  # shellcheck disable=SC2086 # each case is a word list
  ( cd "$TMP" && "$SUT/direct-merge-push.sh" $args ) >/dev/null 2>&1
  eq "$?" 2 "usage: '$args' exits 2"
done

echo "-----"
echo "direct-merge-push: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
