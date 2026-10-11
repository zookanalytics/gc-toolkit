#!/usr/bin/env bash
# demo-repo-artifact.test.sh — hermetic coverage of the demo check's
# repo-artifact modality: which committed visuals `candidates` finds for a
# change, and what `deliver` attaches.
#
# A fixture repository carries a base commit and a change on top of it, laid
# out so each reason (changed, named, near) and each exclusion has one visual
# that only it decides. The script runs under `env -i` with a PATH of a stub gh
# and gc plus a symlink farm of the tools it calls, so `deliver` goes through
# the real demo-deliver.sh and pr-post.sh and stops at the stub gh, which keeps
# a copy of every file it is asked to attach.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/demo-repo-artifact.sh"
[ -x "$SUT" ] || { echo "not found or not executable: $SUT" >&2; exit 2; }
command -v jq  >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git is required for this test" >&2; exit 2; }

FAIL=0
ok()    { if eval "$2"; then printf 'ok   - %s\n' "$1"; else printf 'FAIL - %s\n' "$1"; FAIL=1; fi; }
eq()    { if [ "$1" = "$2" ]; then printf 'ok   - %s\n' "$3"; else printf 'FAIL - %s\n     want: %s\n     got:  %s\n' "$3" "$2" "$1"; FAIL=1; fi; }
has()   { case "$2" in *"$1"*) printf 'ok   - %s\n' "$3" ;; *) printf 'FAIL - %s\n     wanted substring: %s\n     in: %s\n' "$3" "$1" "$2"; FAIL=1 ;; esac; }
hasnt() { case "$2" in *"$1"*) printf 'FAIL - %s\n     unwanted substring: %s\n     in: %s\n' "$3" "$1" "$2"; FAIL=1 ;; *) printf 'ok   - %s\n' "$3" ;; esac; }

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/demo-repo-artifact-test.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT
HOMEDIR="$TMPD/home"; mkdir -p "$HOMEDIR"
RUNTMP="$TMPD/runtmp"; mkdir -p "$RUNTMP"
CAPTURE="$TMPD/capture"; mkdir -p "$CAPTURE"

FARM="$TMPD/farm"; mkdir -p "$FARM"
for c in bash sed tr head tail grep git jq dirname awk sort mktemp rm cat cp; do
  p="$(command -v "$c")" || { echo "test setup: required tool '$c' not found" >&2; exit 2; }
  ln -s "$p" "$FARM/$c"
done
STUBS="$TMPD/stubs"; mkdir -p "$STUBS"

# gh stub: `gh --version` answers a version with --attach; `gh pr comment` logs
# its argv to $GHLOG, copies each --attach file into $CAPTURE, and prints a
# comment URL, or fails when $GH_STUB_FAIL is set.
cat >"$STUBS/gh" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo "gh version 2.102.0 (2026-09-30)"; exit 0; fi
printf '%s\n' "$*" >>"${GHLOG:?}"
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "comment" ]; then
  if [ -n "${GH_STUB_FAIL:-}" ]; then echo "stub gh: upload failed" >&2; exit 1; fi
  while [ $# -gt 0 ]; do
    if [ "$1" = "--attach" ] && [ $# -gt 1 ]; then cp "$2" "${CAPTURE:?}/"; fi
    shift
  done
  echo "https://github.com/acme/widgets/pull/77#issuecomment-1"
  exit 0
fi
exit 0
STUB
chmod +x "$STUBS/gh"

# gc stub: `gc rig list` names no rig, so the origin comes from GC_RIG_ROOT;
# `gc bd show` answers one bead whose description is $STUB_DESC and whose
# pr_number is 77, or fails when $STUB_SHOW_FAIL is set.
cat >"$STUBS/gc" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "rig" ] && [ "${2:-}" = "list" ]; then echo '{"rigs":[]}'; exit 0; fi
if [ "${1:-}" = "bd" ] && [ "${2:-}" = "show" ]; then
  [ -n "${STUB_SHOW_FAIL:-}" ] && { echo "stub gc: no such bead" >&2; exit 1; }
  jq -nc --arg id "${3:-}" --arg d "${STUB_DESC:-}" \
    '[{id:$id, title:"the anchor", description:$d, notes:null, metadata:{pr_number:"77"}}]'
  exit 0
fi
exit 0
STUB
chmod +x "$STUBS/gc"

# A broken awk, on PATH only for the case that asks for it: it fails the call
# that ranks the candidates, the one handed a visfile, and passes every other
# call to the real awk.
BROKEN="$TMPD/broken"; mkdir -p "$BROKEN"
cat >"$BROKEN/awk" <<STUB
#!/usr/bin/env bash
case " \$* " in *" visfile="*) echo "broken awk" >&2; exit 2 ;; esac
exec "$FARM/awk" "\$@"
STUB
chmod +x "$BROKEN/awk"

# --- the fixture repository ------------------------------------------------
REPO="$TMPD/repo"; mkdir -p "$REPO"
g() { git -C "$REPO" -c commit.gpgsign=false -c user.name=fixture -c user.email=fixture@example.com -c core.hooksPath=/dev/null "$@"; }
put() { mkdir -p "$(dirname "$REPO/$1")"; printf '%s' "$2" >"$REPO/$1"; }
g init -q -b main
g remote add origin https://github.com/acme/widgets.git

put README.md 'readme'
put logo.png 'png:logo'
put escape.png 'png:escape'
put docs/flow.md 'The flow.'
put docs/img/flow.svg '<svg>base</svg>'
put docs/img/old.gif 'gif:old'
put docs/shots/Shot.PNG 'png:shot'
put app/src/App.tsx 'export {}'
put app/src/button.PNG 'png:button'
put app/docs/board.png 'png:board'
put app/src/deep/x/y/far.png 'png:deep'
put named/target.png 'png:target'
put named/rel.png 'png:rel'
put named/only-bak.png 'png:only-bak'
put 'named/hash#1.png' 'png:hash'
put other/far.png 'png:other'
put deep1/deep2/deep3/deep4/code.txt 'code'
put lfs/pointer.png "$(printf 'version https://git-lfs.github.com/spec/v1\noid sha256:%064d\nsize 12\n' 0)"
ln -s img/flow.svg "$REPO/docs/link.png"
put zz/icons/list.txt 'icons'
for i in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25; do
  put "zz/icons/i$i.png" "png:icon$i"
done
g add -A && g commit -q -m base

# The change: edits a source file, adds a screenshot, deletes a visual, and adds
# doc lines that name visuals in every form the scan reads or must ignore.
g checkout -q -b feature
put app/src/App.tsx 'export const x = 1'
put specs/tk-1/screenshots/after.png 'png:after'
g rm -q docs/img/old.gif
cat >>"$REPO/docs/flow.md" <<'MD'

![flow](img/flow.svg)
![shot](shots/Shot.PNG)
![after](../specs/tk-1/screenshots/after.png)
See named/target.png.
An old copy sits at named/only-bak.png.bak, and ghost.png is gone.
An escape: ../../escape.png
MD
g add -A && g commit -q -m feature
FEATURE=$(g rev-parse HEAD)
SHORT=$(g rev-parse --short HEAD)

g checkout -q -b feature2
put docs/img/flow.svg '<svg>later</svg>'
g add -A && g commit -q -m later

g checkout -q -b far main
put deep1/deep2/deep3/deep4/code.txt 'code, edited'
g add -A && g commit -q -m far
FAR=$(g rev-parse HEAD)

g checkout -q -b icons main
put zz/icons/list.txt 'icons, edited'
g add -A && g commit -q -m icons
ICONS=$(g rev-parse HEAD)

# One added line carrying a 128 KiB run of path characters, the shape of an
# inlined data URI, then a name.
g checkout -q -b long main
awk 'BEGIN { s = "A"; while (length(s) < 131072) s = s s; printf "url(data:image/png;base64,%s) see logo.png\n", s }' \
  >>"$REPO/deep1/deep2/deep3/deep4/code.txt"
g add -A && g commit -q -m long
LONG=$(g rev-parse HEAD)
g checkout -q feature

GHLOG="$TMPD/gh.log"
# run [STUB_DESC=..] [STUB_SHOW_FAIL=1] [GH_STUB_FAIL=1] [RANK_FAIL=1] -- <sut args...>
# Combined stdout and stderr are returned. Each call starts with an empty gh
# log, an empty capture dir and an empty TMPDIR.
run() {
  local desc="" showfail="" ghfail="" rankfail=""
  while [ $# -gt 0 ]; do
    case "$1" in
      STUB_DESC=*)      desc="${1#*=}" ;;
      STUB_SHOW_FAIL=*) showfail="${1#*=}" ;;
      GH_STUB_FAIL=*)   ghfail="${1#*=}" ;;
      RANK_FAIL=*)      rankfail="${1#*=}" ;;
      --) shift; break ;;
      *) break ;;
    esac
    shift
  done
  : >"$GHLOG"; rm -rf "${CAPTURE:?}"/* "${RUNTMP:?}"/*
  ( cd "$REPO" && env -i \
      PATH="${rankfail:+$BROKEN:}$STUBS:$FARM" HOME="$HOMEDIR" GC_RIG_ROOT="$REPO" TMPDIR="$RUNTMP" \
      GHLOG="$GHLOG" CAPTURE="$CAPTURE" STUB_DESC="$desc" STUB_SHOW_FAIL="$showfail" \
      GH_STUB_FAIL="$ghfail" \
      bash "$SUT" "$@" 2>&1 )
}
lines() { printf '%s\n' "$@"; }
TAB=$(printf '\t')
blob() { g cat-file blob "$1:$2"; }

# --- candidates ------------------------------------------------------------

echo "# each visual is listed once under its strongest reason, in reason then distance order"
out="$(run STUB_DESC="The board now shows named/rel.png." -- candidates --base main --oid "$FEATURE" --anchor tk-anchor)"; rc=$?
eq "$rc" 0 "candidates exits 0 when it lists something"
want="$(lines \
  "changed${TAB}specs/tk-1/screenshots/after.png" \
  "named${TAB}docs/img/flow.svg" \
  "named${TAB}docs/shots/Shot.PNG" \
  "named${TAB}named/rel.png" \
  "named${TAB}named/target.png" \
  "near${TAB}app/src/button.PNG" \
  "near${TAB}escape.png" \
  "near${TAB}logo.png" \
  "near${TAB}app/docs/board.png" \
  "near${TAB}lfs/pointer.png" \
  "near${TAB}named/hash#1.png" \
  "near${TAB}named/only-bak.png" \
  "near${TAB}other/far.png")"
eq "$out" "$want" "changed, then named, then near by step count; a changed visual the doc also names stays changed; the deleted gif, the symlink, the unknown ghost.png and the three-step far.png are absent"

echo "# the anchor's text is a source of named visuals"
out="$(run -- candidates --base main --oid "$FEATURE")"; rc=$?
eq "$rc" 0 "candidates without --anchor exits 0"
has "near${TAB}named/rel.png" "$out" "without the anchor, named/rel.png is only near"
hasnt "named${TAB}named/rel.png" "$out" "…and is not named"

echo "# an anchor that cannot be read is said, and the rest of the search stands"
out="$(run STUB_SHOW_FAIL=1 -- candidates --base main --oid "$FEATURE" --anchor tk-anchor)"; rc=$?
eq "$rc" 0 "an unreadable anchor still exits 0"
has "could not read anchor tk-anchor" "$out" "it says the anchor was not searched"
has "changed${TAB}specs/tk-1/screenshots/after.png" "$out" "the diff's own reasons still list"

echo "# --repo may name a subdirectory: paths stay relative to the repository root"
out_sub="$(run -- candidates --base main --oid "$FEATURE" --repo "$REPO/app/src")"
out_top="$(run -- candidates --base main --oid "$FEATURE")"
eq "$out_sub" "$out_top" "a subdirectory --repo lists the same root-relative paths"

echo "# a change with no visual changed, named or within two steps exits 3"
out="$(run -- candidates --base main --oid "$FAR")"; rc=$?
eq "$rc" 3 "nothing near the change exits 3"
has "no visual at $FAR is changed, named or near the diff" "$out" "it says nothing was found"
hasnt "${TAB}" "$out" "and lists nothing"

echo "# a ranking that fails is said, not taken for an empty list"
out="$(run RANK_FAIL=1 -- candidates --base main --oid "$FEATURE")"; rc=$?
eq "$rc" 1 "a failed ranking exits 1"
has "ranking the candidates failed" "$out" "it says the ranking failed"
hasnt "no visual at" "$out" "…and does not report an empty list"
eq "$(ls -A "$RUNTMP")" "" "a failed ranking leaves nothing in TMPDIR"

echo "# a long run of path characters is scanned in linear time"
start=$SECONDS
out="$(run -- candidates --base main --oid "$LONG")"; rc=$?
elapsed=$((SECONDS - start))
eq "$out" "named${TAB}logo.png" "the name after a 128 KiB data URI is found"
ok "the scan takes seconds, not minutes (took ${elapsed}s)" "[ '$elapsed' -lt 60 ]"

echo "# near is capped, nearest first, and the cut is counted"
out="$(run -- candidates --base main --oid "$ICONS")"; rc=$?
eq "$rc" 0 "a capped list exits 0"
listed="$(printf '%s\n' "$out" | grep -c "^near${TAB}")"
eq "$listed" 20 "at most 20 near visuals are listed"
has "near${TAB}zz/icons/i20.png" "$out" "the nearest come first: the icons beside the change"
hasnt "zz/icons/i21.png" "$out" "the 21st is cut"
hasnt "logo.png" "$out" "farther visuals are cut before nearer ones"
has "7 more visual(s) near the diff not listed" "$out" "the count cut is reported"

echo "# arguments and commits are checked"
out="$(run -- candidates --oid "$FEATURE")"; rc=$?
eq "$rc" 2 "a missing --base is a usage error"
out="$(run -- candidates --base main --oid "$FEATURE" --bogus)"; rc=$?
eq "$rc" 2 "an unknown flag is a usage error"
out="$(run -- candidates --base main --oid)"; rc=$?
eq "$rc" 2 "a flag with no value is a usage error"
out="$(run -- candidates --base main --oid 0000000000000000000000000000000000000000)"; rc=$?
eq "$rc" 1 "an oid that is not a commit exits 1"
has "is not a commit" "$out" "it names the bad commit"
out="$(run -- candidates --base no-such-branch --oid "$FEATURE")"; rc=$?
eq "$rc" 1 "a base that does not resolve exits 1"
out="$(run)"; rc=$?
eq "$rc" 2 "no subcommand is a usage error"
out="$(run -- explode)"; rc=$?
eq "$rc" 2 "an unknown subcommand is a usage error"
leftover="$(ls -A "$RUNTMP")"
eq "$leftover" "" "candidates leaves nothing in TMPDIR"

# --- deliver -----------------------------------------------------------------

echo "# deliver attaches the visual as the commit stores it, through demo-deliver.sh"
printf 'uncommitted edit' >"$REPO/docs/img/flow.svg"
out="$(run -- deliver --path docs/img/flow.svg --oid "$FEATURE" --subject tk-sub)"; rc=$?
eq "$rc" 0 "deliver exits 0"
GH="$(cat "$GHLOG")"
has "pr comment 77" "$GH" "it comments on the subject's PR"
has "--repo github.com/acme/widgets" "$GH" "the post is pinned to our origin"
has "--attach $RUNTMP/" "$GH" "the attachment is a file written for this delivery"
has "The committed visual \`docs/img/flow.svg\` as of $SHORT" "$GH" "the default body names the path and the commit"
has "<!-- gc:city -->" "$GH" "the post carries the city's mark, so it went through pr-post.sh"
ok "the attachment keeps the file's name" "[ -f '$CAPTURE/flow.svg' ]"
eq "$(cat "$CAPTURE/flow.svg" 2>/dev/null)" "$(blob "$FEATURE" docs/img/flow.svg)" "the bytes are the reviewed commit's, not the working tree's edit"
has "delivered docs/img/flow.svg as of $SHORT" "$out" "it reports the delivery"
eq "$(ls -A "$RUNTMP")" "" "the written file is removed after delivery"
g checkout -q -- docs/img/flow.svg

echo "# the bytes come from --oid, not from a later commit"
out="$(run -- deliver --path docs/img/flow.svg --oid "$FEATURE" --subject tk-sub)"; rc=$?
eq "$(cat "$CAPTURE/flow.svg" 2>/dev/null)" "<svg>base</svg>" "an older --oid delivers its own version"
out="$(run -- deliver --path docs/img/flow.svg --oid feature2 --subject tk-sub)"; rc=$?
eq "$(cat "$CAPTURE/flow.svg" 2>/dev/null)" "<svg>later</svg>" "a later --oid delivers the later version"

echo "# a leading ./ is accepted"
out="$(run -- deliver --path ./docs/shots/Shot.PNG --oid "$FEATURE" --subject tk-sub)"; rc=$?
eq "$rc" 0 "./ path delivers"
ok "the upper-case visual is attached" "[ -f '$CAPTURE/Shot.PNG' ]"

echo "# a '#' in the name is not handed to gh, which reads it as alt text"
out="$(run -- deliver --path 'named/hash#1.png' --oid "$FEATURE" --subject tk-sub)"; rc=$?
eq "$rc" 0 "a name with '#' delivers"
ok "the attached name has no '#'" "[ -f '$CAPTURE/hash_1.png' ]"
eq "$(cat "$CAPTURE/hash_1.png" 2>/dev/null)" "png:hash" "…and carries the committed bytes"

echo "# --body overrides the default"
out="$(run -- deliver --path logo.png --oid "$FEATURE" --subject tk-sub --body "the new logo")"; rc=$?
eq "$rc" 0 "a custom body delivers"
GH="$(cat "$GHLOG")"
has "the new logo" "$GH" "the custom body is used"
hasnt "The committed visual" "$GH" "the default is not"

echo "# refusals post nothing"
out="$(run -- deliver --path docs/flow.md --oid "$FEATURE" --subject tk-sub)"; rc=$?
eq "$rc" 1 "a file GitHub does not show inline is refused"
has "is not an image or video" "$out" "it says why"
eq "$(cat "$GHLOG")" "" "nothing is posted for it"
out="$(run -- deliver --path docs/img/old.gif --oid "$FEATURE" --subject tk-sub)"; rc=$?
eq "$rc" 1 "a visual the commit no longer has is refused"
has "is not a file at $FEATURE" "$out" "it says the file is not at the commit"
out="$(run -- deliver --path docs/img --oid "$FEATURE" --subject tk-sub)"; rc=$?
eq "$rc" 1 "a directory is refused"
out="$(run -- deliver --path lfs/pointer.png --oid "$FEATURE" --subject tk-sub)"; rc=$?
eq "$rc" 1 "a Git LFS pointer is refused"
has "Git LFS" "$out" "it names Git LFS"
eq "$(cat "$GHLOG")" "" "nothing is posted for the pointer"
out="$(run -- deliver --path docs/link.png --oid "$FEATURE" --subject tk-sub)"; rc=$?
eq "$rc" 1 "a symlink is refused"
has "is a symlink" "$out" "it says the path is a symlink"
out="$(run -- deliver --path ../escape.png --oid "$FEATURE" --subject tk-sub)"; rc=$?
eq "$rc" 1 "a path outside the root is refused"
has "must be a path from the repository root" "$out" "it says the path must be root-relative"
out="$(run -- deliver --path /logo.png --oid "$FEATURE" --subject tk-sub)"; rc=$?
eq "$rc" 1 "an absolute path is refused"
eq "$(cat "$GHLOG")" "" "nothing is posted for a bad path"
out="$(run -- deliver --path logo.png --oid "$FEATURE")"; rc=$?
eq "$rc" 2 "a missing --subject is a usage error"
out="$(run -- deliver --oid "$FEATURE" --subject tk-sub)"; rc=$?
eq "$rc" 2 "a missing --path is a usage error"

echo "# a failed attach is demo-deliver.sh's failure, passed through"
out="$(run GH_STUB_FAIL=1 -- deliver --path logo.png --oid "$FEATURE" --subject tk-sub)"; rc=$?
eq "$rc" 1 "a gh failure exits 1"
hasnt "delivered logo.png" "$out" "no delivery is reported"
eq "$(ls -A "$RUNTMP")" "" "the written file is removed after a failed delivery too"

echo
if [ "$FAIL" -eq 0 ]; then echo "PASS: all demo-repo-artifact assertions passed"; else echo "FAIL: demo-repo-artifact had failures"; fi
exit "$FAIL"
