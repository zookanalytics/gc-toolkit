#!/usr/bin/env bash
# Hermetic test for reconcile-rig-checkouts.sh.
#
# Uses real temp git repos as stand-in rigs, a fake `gc` (a text-file bead
# ledger) and a fake human-gate.sh (a call recorder) on PATH. No dependency on
# the live city, Dolt, an agent, or the network. Covers: (a) a clean-behind rig
# advances; (b) a diverged rig is NOT mutated and files exactly one reconcile
# bead; (c) a re-run does not duplicate that bead; (d) the bead auto-closes once
# the rig ff-s cleanly, and its human gate is withdrawn as moot through
# human-gate.sh --retract in the same pass (a still-diverged rig withdraws
# nothing); (e) the HQ root is excluded; (f) a divergence is put to a person
# through human-gate.sh with a declared quiet window, an advanced/HQ rig is not,
# and a recovered rig is not asked about again; (g) a rig that blocks again
# after a clean sync files on a new subject bead; (h) an already-upstream divergence (SHA churn) auto-heals via
# a reset while a genuine divergence still escalates, RECONCILE_NO_AUTOHEAL
# disables the heal, and a dirty tracked file blocks it only when its content is
# not yet upstream; (i) a unique local merge commit (invisible to git cherry)
# fails the guard closed and escalates rather than being reset away; (j) an
# unreadable git status fails the guard closed rather than healing on an
# unproven-clean tree; (k) a path staged with local-only content whose worktree
# copy matches the remote fails the guard closed, so the reset cannot discard
# the staged content; (l) a rig root parked off the default branch (HEAD on a
# feature/integration branch ahead of origin) is surfaced and left untouched,
# not silently counted advanced by a no-op fast-forward; (m) the reset heal
# refuses when an untracked file sits on a path the remote tracks with other
# content; (n) a checkout that is only behind, blocked by local changes on the
# paths the fast-forward rewrites, pins them under
# refs/gc-toolkit/reconcile-set-aside/ and advances when each working copy is
# committed, upstream or on a pushed branch, keeping a dirty path the
# fast-forward does not touch, removes an untracked file on an added path that
# already holds the incoming content, and escalates untouched when a working
# copy or a staged edit is local-only or an untracked file on an added path
# holds other content; (o) the reset heal refuses before touching anything when
# untracked content sits in the way of the remote's tree: a directory where the
# remote has a file, a file under a directory the remote turns into a file, a
# file where the remote has a directory, or a nested repository where the remote
# has a path, while an untracked copy of a file the remote adds, inside an
# untracked directory, goes and the checkout heals; (p) the reset refuses rather
# than deletes or overwrites untracked content the guard's listing misses,
# including a name only case separates from the remote's on a file system that
# ignores case, and the escalation carries each error git gave with the paths
# git named; (q) the set-aside never touches a file behind an untracked symlink, and leaves
# an untracked file in a directory the fast-forward deletes where it is; (r) an
# ignored file counts as untracked content in the way: the fast-forward and the
# set-aside's retry refuse rather than overwrite one, the set-aside escalates
# one untouched and names it as ignored, an ignored copy of the incoming bytes
# goes and the checkout advances, the reset heal refuses one before touching
# anything and removes an ignored copy, and the reset refuses rather than
# overwrites one the guard's listing misses, including a name only case
# separates from the remote's on a file system that ignores case; (s) neither
# heal runs the rig's post-checkout hook, so a failing one neither stops nor
# escalates a heal, and the reset leaves the branch's upstream config as it is;
# (t) a diverged rig's escalation names what stopped the reset heal, a line for
# each finding, and hands a person steps to reset by hand that lose nothing once
# real work is saved: its checkout refuses while any one listed item is still in
# its way, an ignored file included, resets the checkout once each is cleared,
# and does not refuse over a local commit; (u) a checkout that is only behind
# keeps in place, byte for byte, each file the incoming commits stop tracking
# while the remote's tree ignores it, modified, clean or staged for deletion,
# one whose name starts with a colon included, pins a modified one first, and
# ends with git status empty, also when the remote starts tracking a file the
# checkout holds as an ignored copy of the same bytes; it keeps no path
# the remote's tree does not ignore, whatever the checkout ignores, no path the
# remote rewrites, writes under or writes a file above, and no path with a
# staged edit; a refused fast-forward puts the kept copies back; the next pass
# puts back a copy an interrupted pass left aside, also when it cannot fetch,
# and a copy waiting aside for a path that holds a file again blocks the keep;
# a regular file written on a kept path meanwhile with the copy's bytes takes
# the copy's place, and so does a second name for the copy, but a symlink to
# them does not, nor does the copy itself under another name for its
# directory; a copy never goes back through a symlinked directory, and copies
# their paths read through one stay aside, escalated, until the symlink goes;
# a copy that cannot go back, because something else was written on its path
# meanwhile, leaves both copies in place and keeps the rig escalated after a
# keep, a plain fast-forward, a reset heal or a pass already up to date, and on
# a blocked, parked or diverged checkout, until no copy waits aside, and a keep
# directory that cannot be listed escalates too; a failed read of the kept paths
# stops the fast-forward; RECONCILE_NO_AUTOHEAL turns the keep off; no
# escalation tells a person to run git reset --hard or --keep.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/reconcile-rig-checkouts.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-reconcile-rig-checkouts-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
# Host signing of commits and tags must not make this suite need a signing agent.
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false \
  GIT_CONFIG_KEY_1=tag.gpgsign GIT_CONFIG_VALUE_1=false

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()   { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

commit() { echo "$2" > "$1/f.txt"; git -C "$1" add -A; git -C "$1" commit -qm "$2"; }
# count OPEN reconcile beads in the fake ledger for a given rig key.
open_count() { awk -F'|' -v k="$1" '$2==k && $3=="open"' "$TMP/ledger" 2>/dev/null | wc -l | tr -d ' '; }
# id of the OPEN reconcile bead for a rig key (empty if none).
bead_for()   { awk -F'|' -v k="$1" '$2==k && $3=="open"{print $1; exit}' "$TMP/ledger" 2>/dev/null; }
# description of the OPEN reconcile bead for a rig key (empty if none).
body_for()   { local id; id="$(bead_for "$1")"; [ -n "$id" ] && cat "$TMP/ledger.$id.body" 2>/dev/null; }
# title of the OPEN reconcile bead for a rig key (empty if none).
title_for()  { local id; id="$(bead_for "$1")"; [ -n "$id" ] && cat "$TMP/ledger.$id.title" 2>/dev/null; }
# human-gate.sh filings recorded for a rig key, the subject of the first, and the
# quiet window the last one declared.
esc_count()   { awk -F'|' -v k="reconcile-diverged-$1" '$1==k' "$TMP/escalations" 2>/dev/null | wc -l | tr -d ' '; }
esc_subject() { awk -F'|' -v k="reconcile-diverged-$1" '$1==k{print $2; exit}' "$TMP/escalations" 2>/dev/null; }
esc_last_window() { awk -F'|' -v k="reconcile-diverged-$1" '$1==k{p=$3} END{print p}' "$TMP/escalations" 2>/dev/null; }
# the message of the last human-gate.sh filing for a rig key.
msg_for()     { cat "$TMP/escalations.reconcile-diverged-$1.msg" 2>/dev/null; }
# the checkout a diverged rig's subject bead hands a person on a line of its own.
remedy_for()  { sed -n 's/^ *\(git -C [^ ]* checkout .*\)$/\1/p' <<< "$(body_for "$1")"; }
# 0 when the checkout read into REMEDY from remedy_for runs, 1 when git refuses it.
remedy_rc()   { if ${REMEDY[@]+"${REMEDY[@]}"} >/dev/null 2>&1; then echo 0; else echo 1; fi; }
# 0 when the open reconcile bead for a rig key has a line matching an ERE.
body_has()    { grep -q -E -- "$2" <<< "$(body_for "$1")"; }
# human-gate.sh --retract calls recorded for a rig key, and the subject of the first.
retract_count()   { awk -F'|' -v k="reconcile-diverged-$1" '$1==k' "$TMP/retractions" 2>/dev/null | wc -l | tr -d ' '; }
retract_subject() { awk -F'|' -v k="reconcile-diverged-$1" '$1==k{print $2; exit}' "$TMP/retractions" 2>/dev/null; }

# --- Build a remote with two commits, then derive three checkouts. ----------
SRC="$TMP/src"; git init -q -b main "$SRC"; commit "$SRC" c1; commit "$SRC" c2
git clone -q --bare "$SRC" "$TMP/remote.git"

git clone -q "$TMP/remote.git" "$TMP/alpha"            # clean-behind: rewind to c1
git -C "$TMP/alpha" reset --hard -q HEAD~1
git clone -q "$TMP/remote.git" "$TMP/beta"             # diverged: own commit on c2
commit "$TMP/beta" c3-local
BETA_DIVERGED="$(git -C "$TMP/beta" rev-parse HEAD)"
git clone -q "$TMP/remote.git" "$TMP/hqrepo"           # diverged too, but is HQ -> skipped
commit "$TMP/hqrepo" c3-hq

commit "$SRC" c3-remote                                # advance the remote past c2
git -C "$SRC" push -q "$TMP/remote.git" main
REMOTE_HEAD="$(git -C "$TMP/remote.git" rev-parse main)"

# --- Fake gc + rig list (only the surface the script touches). ---------------
mkdir -p "$TMP/bin"
cat > "$TMP/rigs.json" <<JSON
{"rigs":[
  {"name":"mycity","path":"$TMP/hqrepo","hq":true},
  {"name":"alpha","path":"$TMP/alpha"},
  {"name":"beta","path":"$TMP/beta"}
]}
JSON
: > "$TMP/ledger"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
case "$1" in
  rig) cat "$FAKE_RIGS_JSON" ;;
  bd)
    shift; [ "$1" = "--rig" ] && shift 2; sub="$1"; shift
    case "$sub" in
      list)
        key=""; while [ $# -gt 0 ]; do [ "$1" = "--metadata-field" ] && key="${2#reconcile_rig=}"; shift; done
        id=$(awk -F'|' -v k="$key" '$2==k && $3=="open"{print $1; exit}' "$FAKE_LEDGER" 2>/dev/null)
        [ -n "$id" ] && printf '[{"id":"%s"}]\n' "$id" || printf '[]\n' ;;
      create)
        n=$(( $(wc -l < "$FAKE_LEDGER" 2>/dev/null || echo 0) + 1 )); id="esc-$n"
        printf '%s||open\n' "$id" >> "$FAKE_LEDGER"
        printf '%s\n' "$1" > "$FAKE_LEDGER.$id.title"
        while [ $# -gt 0 ]; do [ "$1" = "-d" ] && printf '%s\n' "$2" > "$FAKE_LEDGER.$id.body"; shift; done
        printf '{"id":"%s"}\n' "$id" ;;
      update)
        id="$1"; shift; key=""
        while [ $# -gt 0 ]; do
          [ "$1" = "--set-metadata" ] && key="${2#reconcile_rig=}"
          [ "$1" = "--title" ] && printf '%s\n' "$2" > "$FAKE_LEDGER.$id.title"
          [ "$1" = "--description" ] && printf '%s\n' "$2" > "$FAKE_LEDGER.$id.body"
          shift
        done
        [ -n "$key" ] && sed -i.bak "s/^${id}|[^|]*|/${id}|${key}|/" "$FAKE_LEDGER" && rm -f "$FAKE_LEDGER.bak" ;;
      close) sed -i.bak "s/^\($1\)|\([^|]*\)|open/\1|\2|closed/" "$FAKE_LEDGER" && rm -f "$FAKE_LEDGER.bak" ;;
    esac ;;
  session) : ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

# Fake human-gate.sh: record each filing as `<key>|<subject>|<quiet-window>`.
cat > "$TMP/bin/human-gate.sh" <<'ESC'
#!/usr/bin/env bash
subject=""; key=""; window=""; message=""; retract=0
while [ $# -gt 0 ]; do
  case "$1" in
    --retract) retract=1; shift;;
    --subject) subject="${2:-}"; shift 2;;
    --key)     key="${2:-}";     shift 2;;
    --message) message="${2:-}"; shift 2;;
    --quiet-window) window="${2:-}"; shift 2;;
    *) shift;;
  esac
done
# The withdrawal records apart from filings so the file counts stay exact; the
# real one resolves the open gate with a moot: reason (proven in
# human-gate.test.sh), and is a no-op success when none is open. It exits
# non-zero under FAKE_RETRACT_FAIL, as the real one does on an unreadable bead or
# a gate that did not resolve, so the caller's skip-close gate is testable.
if [ "$retract" = 1 ]; then
  printf '%s|%s\n' "$key" "$subject" >> "$FAKE_RETRACTIONS"
  [ -n "${FAKE_RETRACT_FAIL:-}" ] && exit 1
  exit 0
fi
printf '%s|%s|%s\n' "$key" "$subject" "$window" >> "$FAKE_ESCALATIONS"
printf '%s\n' "$message" > "$FAKE_ESCALATIONS.$key.msg"
exit 0
ESC
chmod +x "$TMP/bin/human-gate.sh"

export PATH="$TMP/bin:$PATH" FAKE_RIGS_JSON="$TMP/rigs.json" FAKE_LEDGER="$TMP/ledger"
export GC_RECONCILE_HUMAN_GATE_TOOL="$TMP/bin/human-gate.sh" FAKE_ESCALATIONS="$TMP/escalations"
export FAKE_RETRACTIONS="$TMP/retractions"
: > "$TMP/escalations"; : > "$TMP/retractions"

# --- Run 1: alpha advances, beta files a gate, hq is skipped. ----------------
bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/alpha" rev-parse HEAD)" "$REMOTE_HEAD" "clean-behind rig advances to origin"
eq "$(git -C "$TMP/beta"  rev-parse HEAD)" "$BETA_DIVERGED" "diverged rig is not mutated"
grep -q c3-local < <(git -C "$TMP/beta" log --oneline) && ok "diverged rig keeps local commit" || bad "diverged rig keeps local commit"
eq "$(open_count beta)"  "1" "diverged rig files exactly one reconcile bead"
eq "$(open_count alpha)" "0" "advanced rig files no reconcile bead"
eq "$(open_count mycity)" "0" "HQ root is excluded (not reconciled)"

# The divergence is put to a person through human-gate.sh, on the reconcile bead
# as subject; an advanced or HQ rig files nothing.
eq "$(esc_count beta)"  "1" "diverged rig files a human gate through human-gate.sh"
eq "$(esc_subject beta)" "$(bead_for beta)" "the gate's subject is the reconcile bead"
eq "$(esc_last_window beta)" "86400" "the call declares a day-long quiet window, since every pass detects the blocked rig again"
eq "$(esc_count alpha)" "0" "advanced rig files no gate"
eq "$(esc_count loomington)" "0" "HQ root files no gate"
# A still-diverged rig's gate stays open: nothing is withdrawn while the
# subject is unresolved.
eq "$(retract_count beta)" "0" "a still-diverged rig withdraws no gate"
body_has beta '^local commit not upstream: [0-9a-f]+ c3-local$' \
  && ok "the diverged escalation names the local commit that is not upstream" \
  || bad "the diverged escalation names the local commit that is not upstream (got '$(body_for beta)')"

# --- Run 2: idempotent — no duplicate reconcile bead. ------------------------
# human-gate.sh is called again (it dedups the gate on its own side, proven in
# its own test); the reconcile bead must not be duplicated.
bash "$SCRIPT" >/dev/null
eq "$(open_count beta)" "1" "re-run does not duplicate the reconcile bead"

# --- Run 3: rig resolved -> bead auto-closes, its moot gate is withdrawn, and
# no fresh gate is filed. -----------------------------------------------------
BETA_ESC_BEFORE="$(esc_count beta)"
BETA_BEAD="$(bead_for beta)"
: > "$TMP/retractions"
git -C "$TMP/beta" reset --hard -q origin/main
bash "$SCRIPT" >/dev/null
eq "$(open_count beta)" "0" "reconcile bead auto-closes after a clean fast-forward"
eq "$(esc_count beta)" "$BETA_ESC_BEFORE" "a recovered rig files no fresh gate"
eq "$(retract_count beta)" "1" "the recovered rig's gate is withdrawn as moot"
eq "$(retract_subject beta)" "$BETA_BEAD" "the withdrawal names the reconcile bead as its subject"

# --- Run 4: a rig that blocks again files on a new subject bead. ------------
# The old subject closed on the clean sync, so a new divergence is a new bead,
# and no answer given about the old one mutes its gate.
git -C "$TMP/beta" reset --hard -q "$BETA_DIVERGED"    # re-diverge beta
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null
eq "$(esc_count beta)" "1" "the re-diverged rig files one gate"
[ "$(esc_subject beta)" != "$BETA_BEAD" ] && [ -n "$(esc_subject beta)" ] \
  && ok "the gate is filed on a new subject bead, not the closed one" \
  || bad "the gate is filed on a new subject bead (got '$(esc_subject beta)', old '$BETA_BEAD')"

# ===========================================================================
# Auto-heal an already-upstream divergence (SHA churn from a rebase/squash/
# force-push): a reset is lossless, so the checkout re-syncs without a
# human. A genuine divergence still escalates, RECONCILE_NO_AUTOHEAL disables
# the heal, and a dirty tracked file blocks the heal only when its content is
# not yet upstream. Each rig below gets its own remote so its history rewrite is
# isolated. beta above already proves a genuine unique-commit divergence is left
# untouched; these cases exercise the new branch directly.
# ===========================================================================

# gamma sits on the pre-rewrite commit; origin carries the same tree under a new
# SHA (an amend/force-push), so ff refuses but git cherry finds nothing unique.
git init -q -b main "$TMP/gamma.src"; commit "$TMP/gamma.src" g1; commit "$TMP/gamma.src" g2
git clone -q --bare "$TMP/gamma.src" "$TMP/gamma.git"
git clone -q "$TMP/gamma.git" "$TMP/gamma"                       # gamma HEAD = g2 (pre-rewrite SHA)
GAMMA_OLD="$(git -C "$TMP/gamma" rev-parse HEAD)"
git -C "$TMP/gamma.src" commit -q --amend --no-edit --date "2020-01-01T00:00:00"  # g2': same tree/patch, new SHA
git -C "$TMP/gamma.src" push -qf "$TMP/gamma.git" main
GAMMA_REMOTE="$(git -C "$TMP/gamma.git" rev-parse main)"
echo keep-me > "$TMP/gamma/untracked.txt"                        # untracked; the reset must keep it

# delta: a genuine unique local commit whose content is not upstream -> escalate.
git init -q -b main "$TMP/delta.src"; commit "$TMP/delta.src" d1; commit "$TMP/delta.src" d2
git clone -q --bare "$TMP/delta.src" "$TMP/delta.git"
git clone -q "$TMP/delta.git" "$TMP/delta"
commit "$TMP/delta" d3-local                                     # a local commit...
DELTA_DIVERGED="$(git -C "$TMP/delta" rev-parse HEAD)"
commit "$TMP/delta.src" d3-remote                                # ...while origin advances elsewhere
git -C "$TMP/delta.src" push -q "$TMP/delta.git" main

cat > "$TMP/rigs.json" <<JSON
{"rigs":[
  {"name":"mycity","path":"$TMP/hqrepo","hq":true},
  {"name":"gamma","path":"$TMP/gamma"},
  {"name":"delta","path":"$TMP/delta"}
]}
JSON

# Escape hatch first: with auto-heal disabled, even an already-upstream rig is
# escalated and left untouched. This run files gamma's reconcile bead.
: > "$TMP/escalations"
RECONCILE_NO_AUTOHEAL=1 bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/gamma" rev-parse HEAD)" "$GAMMA_OLD" "RECONCILE_NO_AUTOHEAL leaves an already-upstream checkout unmutated"
eq "$(esc_count gamma)" "1" "RECONCILE_NO_AUTOHEAL escalates instead of healing"
eq "$(open_count gamma)" "1" "RECONCILE_NO_AUTOHEAL files a reconcile bead"
body_has gamma '^not examined: RECONCILE_NO_AUTOHEAL=1 turns the heals off$' \
  && ok "RECONCILE_NO_AUTOHEAL's diverged escalation says the checks did not run" \
  || bad "RECONCILE_NO_AUTOHEAL's diverged escalation says the checks did not run (got '$(body_for gamma)')"

# Now with auto-heal enabled (default): gamma resets to origin, keeps its
# untracked file, closes the bead the escape-hatch run filed, and is not
# re-escalated; delta's genuine divergence still escalates and is not mutated.
GAMMA_ESC_BEFORE="$(esc_count gamma)"
GAMMA_BEAD="$(bead_for gamma)"
: > "$TMP/retractions"
OUT="$(bash "$SCRIPT")"
eq "$(git -C "$TMP/gamma" rev-parse HEAD)" "$GAMMA_REMOTE" "already-upstream rig is reset to origin"
[ -f "$TMP/gamma/untracked.txt" ] && ok "auto-heal preserves untracked files" || bad "auto-heal preserves untracked files"
eq "$(open_count gamma)" "0" "auto-heal closes the open reconcile bead"
eq "$(esc_count gamma)" "$GAMMA_ESC_BEFORE" "auto-healed rig is not re-escalated"
eq "$(retract_count gamma)" "1" "the auto-healed rig's tracking visit is retracted as moot"
eq "$(retract_subject gamma)" "$GAMMA_BEAD" "the auto-heal retract names the reconcile bead as its subject"
eq "$(retract_count delta)" "0" "a still-diverged rig alongside retracts nothing"
grep -q '1 auto-healed' <<< "$OUT" && ok "summary line reports the auto-heal count" || bad "summary line reports the auto-heal count (got '$OUT')"
eq "$(git -C "$TMP/delta" rev-parse HEAD)" "$DELTA_DIVERGED" "a genuine unique-commit divergence is not mutated"
eq "$(open_count delta)" "1" "a genuine unique-commit divergence keeps its reconcile bead"
body_has delta '^local commit not upstream: [0-9a-f]+ d3-local$' \
  && ok "a pass that runs the reset heal rewrites the bead to name the local commit that is not upstream" \
  || bad "a pass that runs the reset heal rewrites the bead to name the local commit that is not upstream (got '$(body_for delta)')"

# epsilon: an already-upstream SHA churn PLUS a dirty tracked change whose
# content is NOT upstream -> the per-file guard blocks the heal and escalates.
git init -q -b main "$TMP/eps.src"; commit "$TMP/eps.src" ep1; commit "$TMP/eps.src" ep2
git clone -q --bare "$TMP/eps.src" "$TMP/eps.git"
git clone -q "$TMP/eps.git" "$TMP/epsilon"
EPS_HEAD="$(git -C "$TMP/epsilon" rev-parse HEAD)"
git -C "$TMP/eps.src" commit -q --amend --no-edit --date "2020-01-01T00:00:00"
git -C "$TMP/eps.src" push -qf "$TMP/eps.git" main               # SHA churn: ff refuses, cherry clean
echo local-wip > "$TMP/epsilon/f.txt"                            # dirty; differs from remote (f.txt=ep2)

cat > "$TMP/rigs.json" <<JSON
{"rigs":[
  {"name":"mycity","path":"$TMP/hqrepo","hq":true},
  {"name":"epsilon","path":"$TMP/epsilon"}
]}
JSON
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/epsilon" rev-parse HEAD)" "$EPS_HEAD" "a dirty tracked change not upstream blocks the heal"
eq "$(esc_count epsilon)" "1" "a dirty tracked change not upstream escalates"
eq "$(cat "$TMP/epsilon/f.txt")" "local-wip" "the un-upstreamed dirty change is left untouched"
body_has epsilon '^local-only content: f\.txt \(its working copy differs from origin/main\)$' \
  && ok "the escalation names the dirty path and why it is not proven upstream" \
  || bad "the escalation names the dirty path and why it is not proven upstream (got '$(body_for epsilon)')"

# zeta: the .husky case — an already-upstream divergence PLUS a dirty tracked
# file the checkout regenerated to the *upstream* content, so its per-file
# `git diff --quiet <remote>` is empty and the heal proceeds.
git init -q -b main "$TMP/zeta.src"
commit "$TMP/zeta.src" z1
echo H1 > "$TMP/zeta.src/hook.txt"; git -C "$TMP/zeta.src" add -A; git -C "$TMP/zeta.src" commit -qm z2
git clone -q --bare "$TMP/zeta.src" "$TMP/zeta.git"
git clone -q "$TMP/zeta.git" "$TMP/zeta"                         # zeta HEAD carries hook.txt=H1
git -C "$TMP/zeta.src" commit -q --amend --no-edit --date "2020-01-01T00:00:00"   # churn z2's SHA
echo H2 > "$TMP/zeta.src/hook.txt"; git -C "$TMP/zeta.src" add -A; git -C "$TMP/zeta.src" commit -qm z3
git -C "$TMP/zeta.src" push -qf "$TMP/zeta.git" main
ZETA_REMOTE="$(git -C "$TMP/zeta.git" rev-parse main)"
echo H2 > "$TMP/zeta/hook.txt"                                   # dirty vs HEAD(H1); already == remote(H2)

cat > "$TMP/rigs.json" <<JSON
{"rigs":[
  {"name":"mycity","path":"$TMP/hqrepo","hq":true},
  {"name":"zeta","path":"$TMP/zeta"}
]}
JSON
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/zeta" rev-parse HEAD)" "$ZETA_REMOTE" "an already-upstream dirty tracked file (diffs empty) still heals"
eq "$(esc_count zeta)" "0" "the already-upstream dirty file case is not escalated"

# eta: an already-upstream SHA churn whose local HEAD is a MERGE commit carrying
# tree content (evil.txt) that is NOT upstream. git cherry ignores merge commits,
# so the committed-content proof is incomplete: the guard must refuse via the
# merge check and escalate rather than reset the merge content away.
git init -q -b main "$TMP/eta.src"
commit "$TMP/eta.src" et1
git -C "$TMP/eta.src" checkout -q -b side
echo side-content > "$TMP/eta.src/side.txt"; git -C "$TMP/eta.src" add -A
git -C "$TMP/eta.src" commit -qm et-side
git -C "$TMP/eta.src" checkout -q main
git -C "$TMP/eta.src" merge -q --no-ff side -m et-merge          # merge commit; tree gains side.txt
git clone -q --bare "$TMP/eta.src" "$TMP/eta.git"
git clone -q "$TMP/eta.git" "$TMP/eta"                           # local HEAD = et-merge
echo evil > "$TMP/eta/evil.txt"; git -C "$TMP/eta" add -A
git -C "$TMP/eta" commit -q --amend --no-edit                    # local merge now carries evil.txt
ETA_LOCAL="$(git -C "$TMP/eta" rev-parse HEAD)"
git -C "$TMP/eta.src" commit -q --amend --no-edit --date "2020-01-01T00:00:00"  # churn the merge SHA upstream, WITHOUT evil.txt
git -C "$TMP/eta.src" push -qf "$TMP/eta.git" main

cat > "$TMP/rigs.json" <<JSON
{"rigs":[
  {"name":"mycity","path":"$TMP/hqrepo","hq":true},
  {"name":"eta","path":"$TMP/eta"}
]}
JSON
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/eta" rev-parse HEAD)" "$ETA_LOCAL" "a unique local merge commit blocks the heal (git cherry ignores merges)"
eq "$(esc_count eta)" "1" "a unique local merge commit escalates"
[ -f "$TMP/eta/evil.txt" ] && ok "the merge commit's unique tree content is preserved" || bad "the merge commit's unique tree content is preserved"
body_has eta '^local merge commit: [0-9a-f]+ et-merge \(git cherry does not compare a merge' \
  && ok "the escalation names the local merge commit" \
  || bad "the escalation names the local merge commit (got '$(body_for eta)')"

# theta: an already-upstream SHA churn where git status cannot be read. An
# unreadable status is not proof of a clean tree, so the dirty-tracked proof must
# fail closed and escalate rather than reset. A git shim on PATH fails
# `git status` and passes every other subcommand through to real git.
git init -q -b main "$TMP/theta.src"; commit "$TMP/theta.src" th1; commit "$TMP/theta.src" th2
git clone -q --bare "$TMP/theta.src" "$TMP/theta.git"
git clone -q "$TMP/theta.git" "$TMP/theta"
THETA_HEAD="$(git -C "$TMP/theta" rev-parse HEAD)"
git -C "$TMP/theta.src" commit -q --amend --no-edit --date "2020-01-01T00:00:00"  # SHA churn: ff refuses, cherry clean
git -C "$TMP/theta.src" push -qf "$TMP/theta.git" main

cat > "$TMP/rigs.json" <<JSON
{"rigs":[
  {"name":"mycity","path":"$TMP/hqrepo","hq":true},
  {"name":"theta","path":"$TMP/theta"}
]}
JSON
: > "$TMP/escalations"
REAL_GIT="$(PATH="${PATH#"$TMP/bin:"}" command -v git)"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/git" <<GITSHIM
for a in "\$@"; do [ "\$a" = "status" ] && exit 128; done
exec "$REAL_GIT" "\$@"
GITSHIM
chmod +x "$TMP/bin/git"
bash "$SCRIPT" >/dev/null
rm -f "$TMP/bin/git"
eq "$(git -C "$TMP/theta" rev-parse HEAD)" "$THETA_HEAD" "an unreadable git status blocks the heal (fail closed)"
eq "$(esc_count theta)" "1" "an unreadable git status escalates instead of healing"
body_has theta '^could not read git status$' \
  && ok "the escalation says the status could not be read" \
  || bad "the escalation says the status could not be read (got '$(body_for theta)')"

# iota: an already-upstream SHA churn PLUS a tracked path staged with local-only
# content whose worktree copy was then restored to the upstream bytes. git status
# reports it (MM f.txt), but the per-file worktree diff against the remote is
# empty, so a worktree-only proof counts it clean and the reset would discard
# the staged content. The proof must also compare the staged index against the
# remote (git diff --cached) and refuse. Twin of the zeta case, which heals
# because the dirty content is genuinely upstream; here only the worktree is.
git init -q -b main "$TMP/iota.src"; commit "$TMP/iota.src" i1; commit "$TMP/iota.src" i2
git clone -q --bare "$TMP/iota.src" "$TMP/iota.git"
git clone -q "$TMP/iota.git" "$TMP/iota"                         # iota HEAD carries f.txt=i2
IOTA_LOCAL="$(git -C "$TMP/iota" rev-parse HEAD)"
git -C "$TMP/iota.src" commit -q --amend --no-edit --date "2020-01-01T00:00:00"  # churn i2's SHA, tree unchanged
git -C "$TMP/iota.src" push -qf "$TMP/iota.git" main
printf 'staged-local-only\n' > "$TMP/iota/f.txt"; git -C "$TMP/iota" add f.txt    # index: local-only content
echo i2 > "$TMP/iota/f.txt"                                     # worktree: restored to the upstream bytes

cat > "$TMP/rigs.json" <<JSON
{"rigs":[
  {"name":"mycity","path":"$TMP/hqrepo","hq":true},
  {"name":"iota","path":"$TMP/iota"}
]}
JSON
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/iota" rev-parse HEAD)" "$IOTA_LOCAL" "staged local-only content (hidden by an upstream-matching worktree) blocks the heal"
eq "$(esc_count iota)" "1" "staged local-only content escalates instead of healing"
eq "$(git -C "$TMP/iota" show :f.txt)" "staged-local-only" "the staged local-only content is left untouched"
body_has iota '^local-only content: f\.txt \(its staged copy matches neither HEAD nor origin/main\)$' \
  && ok "the escalation names the path whose staged copy is not proven upstream" \
  || bad "the escalation names the path whose staged copy is not proven upstream (got '$(body_for iota)')"

# kappa: the rig root parked off the default branch — an agent checked out an
# integration branch in the rig root and left a seed commit on it, ahead of
# origin/main. `merge --ff-only origin/main` reports "Already up to date", so a
# HEAD-blind reconciler counts it advanced; the parked-off-default check must
# surface it instead, mutating nothing.
git init -q -b main "$TMP/kappa.src"; commit "$TMP/kappa.src" k1; commit "$TMP/kappa.src" k2
git clone -q --bare "$TMP/kappa.src" "$TMP/kappa.git"
git clone -q "$TMP/kappa.git" "$TMP/kappa"                       # on main == origin/main
git -C "$TMP/kappa" checkout -q -b integration/seed origin/main  # park off the default branch
echo seed > "$TMP/kappa/seed.txt"; git -C "$TMP/kappa" add -A; git -C "$TMP/kappa" commit -qm seed
KAPPA_PARKED="$(git -C "$TMP/kappa" rev-parse HEAD)"

cat > "$TMP/rigs.json" <<JSON
{"rigs":[
  {"name":"mycity","path":"$TMP/hqrepo","hq":true},
  {"name":"kappa","path":"$TMP/kappa"}
]}
JSON
: > "$TMP/escalations"
KAPPA_OUT="$(bash "$SCRIPT")"
eq "$(git -C "$TMP/kappa" rev-parse HEAD)" "$KAPPA_PARKED" "a rig parked off the default branch is not mutated"
eq "$(git -C "$TMP/kappa" symbolic-ref --short HEAD)" "integration/seed" "a parked rig is left on its branch, not force-moved"
eq "$(esc_count kappa)" "1" "a rig parked off the default branch is escalated"
eq "$(open_count kappa)" "1" "a rig parked off the default branch files a reconcile bead"
grep -q '0 advanced' <<< "$KAPPA_OUT" && ok "a parked rig is not counted as advanced" || bad "a parked rig is not counted as advanced (got '$KAPPA_OUT')"

# lambda: a recovered rig whose visit retract FAILS must keep its reconcile
# subject OPEN. open_bead lists open beads only (no --all), so the subject is the
# only handle the next patrol has to retry the retract; closing it after a failed
# retract would strand the human-routed visit unretractable — the phantom demand
# this change exists to clear. A later pass whose retract succeeds closes it.
git init -q -b main "$TMP/lambda.src"; commit "$TMP/lambda.src" l1; commit "$TMP/lambda.src" l2
git clone -q --bare "$TMP/lambda.src" "$TMP/lambda.git"
git clone -q "$TMP/lambda.git" "$TMP/lambda"                     # HEAD = l2 (pre-rewrite SHA)
git -C "$TMP/lambda.src" commit -q --amend --no-edit --date "2020-01-01T00:00:00"  # same tree, new SHA
git -C "$TMP/lambda.src" push -qf "$TMP/lambda.git" main
LAMBDA_REMOTE="$(git -C "$TMP/lambda.git" rev-parse main)"

cat > "$TMP/rigs.json" <<JSON
{"rigs":[
  {"name":"mycity","path":"$TMP/hqrepo","hq":true},
  {"name":"lambda","path":"$TMP/lambda"}
]}
JSON

# File lambda's reconcile bead first (auto-heal disabled: escalate, don't heal).
: > "$TMP/escalations"; : > "$TMP/retractions"
RECONCILE_NO_AUTOHEAL=1 bash "$SCRIPT" >/dev/null
eq "$(open_count lambda)" "1" "lambda files a reconcile bead while diverged"
LAMBDA_BEAD="$(bead_for lambda)"

# Auto-heal enabled but the retract fails: lambda heals, the retract is attempted,
# and because it did not land the subject is NOT closed.
: > "$TMP/retractions"
FAKE_RETRACT_FAIL=1 bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/lambda" rev-parse HEAD)" "$LAMBDA_REMOTE" "lambda still heals to origin even when the retract fails"
eq "$(retract_count lambda)" "1" "a retract is attempted on the healed rig"
eq "$(open_count lambda)" "1" "a FAILED retract leaves the reconcile subject OPEN as the retry handle"
eq "$(bead_for lambda)" "$LAMBDA_BEAD" "the same subject stays open — no fresh bead is filed"

# Next patrol, the retract succeeds: the still-open subject is re-found and closed.
: > "$TMP/retractions"
bash "$SCRIPT" >/dev/null
eq "$(retract_count lambda)" "1" "the next patrol retries the retract on the still-open subject"
eq "$(open_count lambda)" "0" "a successful retract finally closes the subject"

rigs_json() { # names... -> the rig list holds the HQ root plus these rigs
  local n
  { printf '{"rigs":[\n  {"name":"mycity","path":"%s","hq":true}' "$TMP/hqrepo"
    for n in "$@"; do printf ',\n  {"name":"%s","path":"%s"}' "$n" "$TMP/$n"; done
    printf '\n]}\n'; } > "$TMP/rigs.json"
}

# rho: an already-upstream SHA churn whose rewritten origin also adds new.txt,
# while the checkout holds an untracked new.txt with other content. A reset
# would overwrite it, so the reset guard refuses and escalates.
git init -q -b main "$TMP/rho.src"; commit "$TMP/rho.src" r1; commit "$TMP/rho.src" r2
git clone -q --bare "$TMP/rho.src" "$TMP/rho.git"
git clone -q "$TMP/rho.git" "$TMP/rho"                           # HEAD = r2 (pre-rewrite SHA)
RHO_LOCAL="$(git -C "$TMP/rho" rev-parse HEAD)"
git -C "$TMP/rho.src" commit -q --amend --no-edit --date "2020-01-01T00:00:00"   # churn r2's SHA
echo theirs > "$TMP/rho.src/new.txt"; git -C "$TMP/rho.src" add new.txt; git -C "$TMP/rho.src" commit -qm r3
git -C "$TMP/rho.src" push -qf "$TMP/rho.git" main
echo mine > "$TMP/rho/new.txt"
rigs_json rho
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/rho" rev-parse HEAD)" "$RHO_LOCAL" "an untracked file the reset would overwrite blocks the reset heal"
eq "$(cat "$TMP/rho/new.txt")" "mine" "the untracked file the reset would overwrite is left untouched"
eq "$(esc_count rho)" "1" "an untracked file the reset would overwrite escalates"
body_has rho '^untracked in the way: new\.txt \(the reset would write over or remove it' \
  && ok "the escalation names the untracked file in the reset's way" \
  || bad "the escalation names the untracked file in the reset's way (got '$(body_for rho)')"

# The reset writes the remote's whole tree, so untracked content is in its way
# on a path where the remote has a file, under a directory the remote turns into
# a file, or where the remote has a directory. churned_rig builds each case: the
# checkout sits on c2, whose SHA the remote rewrote, and the case stages what
# the remote's c3 adds in <name>.src before push_churn publishes it. Each case
# that refuses also holds same.txt, an untracked copy of a file c3 adds, which
# the heal would remove before resetting; it is still there only if the guard
# refused before anything moved.
churned_rig() { # name -> a clone on c2 of a remote that amended c2
  local s="$TMP/$1.src"
  git init -q -b main "$s"; commit "$s" c1
  mkdir -p "$s/a/b"; echo t > "$s/a/b/t"; echo top > "$s/a/top"; commit "$s" c2
  git clone -q --bare "$s" "$TMP/$1.git"
  git clone -q "$TMP/$1.git" "$TMP/$1"
  git -C "$s" commit -q --amend --no-edit --date "2020-01-01T00:00:00"
}
push_churn() { # name -> commit what <name>.src holds as c3 and force-push it
  git -C "$TMP/$1.src" add -A; git -C "$TMP/$1.src" commit -qm c3
  git -C "$TMP/$1.src" push -qf "$TMP/$1.git" main
}
refused_untouched() { # name subject -> the heal escalated before it removed anything
  [ -f "$TMP/$1/same.txt" ] && ok "$2 is refused before the heal removes anything" || bad "$2 is refused before the heal removes anything"
  eq "$(esc_count "$1")" "1" "$2 escalates"
}

# tau: the remote adds a file named new while the checkout holds an untracked
# directory new/, which a reset would have to delete to write the file.
churned_rig tau
echo theirs > "$TMP/tau.src/new"; echo same > "$TMP/tau.src/same.txt"; push_churn tau
mkdir "$TMP/tau/new"; echo mine > "$TMP/tau/new/keep"; echo same > "$TMP/tau/same.txt"
TAU_LOCAL="$(git -C "$TMP/tau" rev-parse HEAD)"
rigs_json tau
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/tau" rev-parse HEAD)" "$TAU_LOCAL" "an untracked directory where the remote has a file blocks the reset heal"
eq "$(cat "$TMP/tau/new/keep" 2>/dev/null)" "mine" "the untracked directory's file is left untouched"
refused_untouched tau "an untracked directory where the remote has a file"
body_has tau '^untracked in the way: new/keep ' \
  && ok "the escalation names the file in the untracked directory the reset would delete" \
  || bad "the escalation names the file in the untracked directory the reset would delete (got '$(body_for tau)')"

# upsilon: the remote turns the tracked directory a/b into a file while the
# checkout holds an untracked a/b/c. git lists c on its own, because a/b holds
# tracked files, so only the directory above it shows what is in the way.
churned_rig upsilon
git -C "$TMP/upsilon.src" rm -q -r a/b; echo now-a-file > "$TMP/upsilon.src/a/b"
echo same > "$TMP/upsilon.src/same.txt"; push_churn upsilon
echo mine > "$TMP/upsilon/a/b/c"; echo same > "$TMP/upsilon/same.txt"
UPSILON_LOCAL="$(git -C "$TMP/upsilon" rev-parse HEAD)"
rigs_json upsilon
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/upsilon" rev-parse HEAD)" "$UPSILON_LOCAL" "an untracked file under a directory the remote turns into a file blocks the reset heal"
eq "$(cat "$TMP/upsilon/a/b/c" 2>/dev/null)" "mine" "the untracked file under that directory is left untouched"
refused_untouched upsilon "an untracked file under a directory the remote turns into a file"

# phi: the remote adds foo/bar while the checkout holds an untracked file foo.
churned_rig phi
mkdir "$TMP/phi.src/foo"; echo bar > "$TMP/phi.src/foo/bar"; echo same > "$TMP/phi.src/same.txt"; push_churn phi
echo mine > "$TMP/phi/foo"; echo same > "$TMP/phi/same.txt"
PHI_LOCAL="$(git -C "$TMP/phi" rev-parse HEAD)"
rigs_json phi
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/phi" rev-parse HEAD)" "$PHI_LOCAL" "an untracked file where the remote has a directory blocks the reset heal"
eq "$(cat "$TMP/phi/foo" 2>/dev/null)" "mine" "the untracked file where the remote has a directory is left untouched"
refused_untouched phi "an untracked file where the remote has a directory"

# chi: the remote adds sub/readme where the checkout holds a nested repository.
# git does not look inside a nested repository, so whatever the remote writes
# there counts as in the way.
churned_rig chi
mkdir "$TMP/chi.src/sub"; echo theirs > "$TMP/chi.src/sub/readme"; echo same > "$TMP/chi.src/same.txt"; push_churn chi
git init -q "$TMP/chi/sub"; echo mine > "$TMP/chi/sub/readme"; echo same > "$TMP/chi/same.txt"
CHI_LOCAL="$(git -C "$TMP/chi" rev-parse HEAD)"
rigs_json chi
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/chi" rev-parse HEAD)" "$CHI_LOCAL" "a nested repository where the remote has a path blocks the reset heal"
eq "$(cat "$TMP/chi/sub/readme" 2>/dev/null)" "mine" "the nested repository's file is left untouched"
refused_untouched chi "a nested repository where the remote has a path"

# psi: the checkout's untracked docs/ holds x, a byte-for-byte copy of the file
# the remote adds there, and notes, which the remote does not track. The copy
# goes, since the reset writes the same bytes back, notes stays, and the
# checkout heals.
churned_rig psi
mkdir "$TMP/psi.src/docs"; echo added > "$TMP/psi.src/docs/x"; push_churn psi
mkdir "$TMP/psi/docs"; echo added > "$TMP/psi/docs/x"; echo mine > "$TMP/psi/docs/notes"
PSI_REMOTE="$(git -C "$TMP/psi.git" rev-parse main)"
rigs_json psi
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/psi" rev-parse HEAD)" "$PSI_REMOTE" "an untracked copy of a file the remote adds, inside an untracked directory, does not block the reset heal"
eq "$(cat "$TMP/psi/docs/notes" 2>/dev/null)" "mine" "an untracked file the remote does not track survives the reset"
eq "$(git -C "$TMP/psi" status --porcelain)" "?? docs/notes" "the copied path is tracked after the reset"
eq "$(esc_count psi)" "0" "an untracked copy of a file the remote adds is not escalated"

# omega: the guard's untracked listing comes back empty, so it sees nothing in
# the way of the remote's files new and two.txt. The reset's git checkout checks
# the working tree itself and refuses rather than delete the directory new/ or
# overwrite the untracked two.txt. git gives a separate error for each, and the
# escalation carries both with the paths they name. A git shim on PATH empties
# `git ls-files` and passes every other subcommand to real git.
churned_rig omega
echo theirs > "$TMP/omega.src/new"; echo theirs > "$TMP/omega.src/two.txt"; push_churn omega
mkdir "$TMP/omega/new"; echo mine > "$TMP/omega/new/keep"; echo mine > "$TMP/omega/two.txt"
OMEGA_LOCAL="$(git -C "$TMP/omega" rev-parse HEAD)"
rigs_json omega
: > "$TMP/escalations"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/git" <<GITSHIM
for a in "\$@"; do [ "\$a" = "ls-files" ] && exit 0; done
exec "$REAL_GIT" "\$@"
GITSHIM
chmod +x "$TMP/bin/git"
bash "$SCRIPT" >/dev/null
rm -f "$TMP/bin/git"
eq "$(cat "$TMP/omega/new/keep" 2>/dev/null)" "mine" "untracked content the guard's listing misses is not deleted by the reset"
eq "$(git -C "$TMP/omega" rev-parse HEAD)" "$OMEGA_LOCAL" "a reset git refuses leaves the checkout where it was"
eq "$(esc_count omega)" "1" "a reset git refuses escalates"
eq "$(cat "$TMP/omega/two.txt" 2>/dev/null)" "mine" "an untracked file the guard's listing misses is not overwritten by the reset"
body_has omega '^git checkout --no-overwrite-ignore --no-track -B main origin/main refused: ' \
  && ok "the escalation says git refused the reset" \
  || bad "the escalation says git refused the reset (got '$(body_for omega)')"
body_has omega 'error: Updating the following directories would lose untracked files in them:$' \
  && body_has omega 'error: The following untracked working tree files would be overwritten by checkout:$' \
  && body_has omega '^  new$' && body_has omega '^  two\.txt$' \
  && ok "the escalation carries each error git refused the reset with, and each path it named" \
  || bad "the escalation carries each error git refused the reset with, and each path it named (got '$(body_for omega)')"
body_has omega '^(Please |Aborting$)' \
  && bad "the escalation leaves out git's advice on switching branches (got '$(body_for omega)')" \
  || ok "the escalation leaves out git's advice on switching branches"

# casefold: an untracked Readme where the remote adds README. On a file system
# that ignores case they are one file, which the guard's listing does not
# match, and the reset's git checkout refuses rather than overwrite it; where
# case matters they are two files and the reset heals. Either way Readme keeps
# its bytes.
churned_rig casefold
echo theirs > "$TMP/casefold.src/README"; push_churn casefold
echo mine > "$TMP/casefold/Readme"
rigs_json casefold
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null
eq "$(cat "$TMP/casefold/Readme" 2>/dev/null)" "mine" "an untracked file only case separates from a file the remote adds keeps its bytes"

# both: a local commit that is not upstream, and an untracked file where the
# remote adds one. The escalation names each, not only the first check that
# failed.
churned_rig both
echo theirs > "$TMP/both.src/new.txt"; push_churn both
echo work > "$TMP/both/work.txt"; git -C "$TMP/both" add work.txt; git -C "$TMP/both" commit -qm both-local
echo mine > "$TMP/both/new.txt"
rigs_json both
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null
body_has both '^local commit not upstream: [0-9a-f]+ both-local$' && body_has both '^untracked in the way: new\.txt ' \
  && ok "the escalation names every check that stopped the reset heal" \
  || bad "the escalation names every check that stopped the reset heal (got '$(body_for both)')"
# A person who moves new.txt aside but skips step 1 loses the local commit from
# the branch: the handed checkout does not refuse over one, which is why the
# steps save real work first.
BOTH_LOCAL="$(git -C "$TMP/both" rev-parse HEAD)"
read -ra REMEDY <<< "$(remedy_for both)"
mv "$TMP/both/new.txt" "$TMP/both-new.txt.saved" 2>/dev/null || true
eq "$(remedy_rc)" "0" "the handed checkout does not refuse over a local commit that is not upstream"
git -C "$TMP/both" merge-base --is-ancestor "$BOTH_LOCAL" HEAD 2>/dev/null \
  && bad "the handed checkout moves the branch off a local commit, so only step 1 keeps it" \
  || ok "the handed checkout moves the branch off a local commit, so only step 1 keeps it"

# handed: the remote's rewritten history adds new.txt, same.txt and copy.cfg
# and rewrites a/top. The checkout holds an untracked new.txt with other
# content, which stops the reset heal. It also holds what the heal would have
# cleared itself: an unstaged a/top already holding the remote's bytes, an
# untracked copy of same.txt, and an ignored copy of copy.cfg. A person follows
# the steps the escalation hands them. Leaving any one listed item in place
# costs a refusal, and the reset lands once every listed item is cleared. The
# next pass then closes the bead.
churned_rig handed
echo theirs > "$TMP/handed.src/new.txt"; echo same > "$TMP/handed.src/same.txt"; echo copy > "$TMP/handed.src/copy.cfg"
echo top2 > "$TMP/handed.src/a/top"; push_churn handed
echo mine > "$TMP/handed/new.txt"; echo same > "$TMP/handed/same.txt"; echo top2 > "$TMP/handed/a/top"
printf '%s\n' copy.cfg >> "$TMP/handed/.git/info/exclude"; echo copy > "$TMP/handed/copy.cfg"
HANDED_REMOTE="$(git -C "$TMP/handed.git" rev-parse main)"
rigs_json handed
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null
eq "$(esc_count handed)" "1" "an untracked file in the reset's way escalates beside what the heal would clear"
body_has handed '^dirty, already upstream: a/top \(its working copy holds what origin/main holds there\)$' \
  && body_has handed '^untracked, already upstream: same\.txt \(it holds what origin/main holds there\)$' \
  && body_has handed '^ignored, already upstream: copy\.cfg \(git status does not list it, and it holds what origin/main holds there\)$' \
  && ok "the escalation names what the heal would have staged or removed before resetting" \
  || bad "the escalation names what the heal would have staged or removed before resetting (got '$(body_for handed)')"
HANDED_REMEDY="git -C $TMP/handed checkout --no-overwrite-ignore -B main origin/main"
eq "$(remedy_for handed)" "$HANDED_REMEDY" "the diverged escalation hands a person a checkout that refuses what is in its way"
grep -qF -- "$HANDED_REMEDY" <<< "$(msg_for handed)" \
  && ok "the diverged visit message hands a person the same checkout" \
  || bad "the diverged visit message hands a person the same checkout (got '$(msg_for handed)')"
grep -qF -- "git -C $TMP/handed restore --source=HEAD --staged --worktree -- <path>" <<< "$(body_for handed)" \
  && ok "the diverged escalation hands a person the restore for a dirty path already upstream" \
  || bad "the diverged escalation hands a person the restore for a dirty path already upstream (got '$(body_for handed)')"
read -ra REMEDY <<< "$(remedy_for handed)"
# Each refusal below has one listed item left in the checkout's way, so that
# item alone is what the checkout refuses.
mv "$TMP/handed/new.txt" "$TMP/handed-new.txt.saved" 2>/dev/null || true
mv "$TMP/handed/same.txt" "$TMP/handed-same.txt.saved" 2>/dev/null || true
mv "$TMP/handed/copy.cfg" "$TMP/handed-copy.cfg.saved" 2>/dev/null || true
eq "$(remedy_rc)" "1" "the handed checkout refuses while a dirty path it rewrites is not restored"
eq "$(cat "$TMP/handed/a/top")" "top2" "a refused handed checkout leaves the dirty path as it was"
git -C "$TMP/handed" restore --source=HEAD --staged --worktree -- a/top 2>/dev/null || true
mv "$TMP/handed-same.txt.saved" "$TMP/handed/same.txt" 2>/dev/null || true
eq "$(remedy_rc)" "1" "the handed checkout refuses while an untracked copy it writes over is in its way"
rm -f "$TMP/handed/same.txt"
mv "$TMP/handed-copy.cfg.saved" "$TMP/handed/copy.cfg" 2>/dev/null || true
eq "$(remedy_rc)" "1" "the handed checkout refuses while an ignored copy it writes over is in its way"
eq "$(cat "$TMP/handed/copy.cfg")" "copy" "a refused handed checkout leaves the ignored copy as it was"
rm -f "$TMP/handed/copy.cfg"
eq "$(remedy_rc)" "0" "the handed checkout runs once every listed item is cleared"
eq "$(git -C "$TMP/handed" rev-parse HEAD)" "$HANDED_REMOTE" "the handed steps reset the checkout once each is done"
eq "$(git -C "$TMP/handed" status --porcelain)" "" "the checkout is clean after the handed reset"
bash "$SCRIPT" >/dev/null
eq "$(open_count handed)" "0" "the pass after a person's reset closes the bead"

# ===========================================================================
# Set aside what blocks a checkout that is only behind. HEAD is an ancestor of
# origin, so ff-only refuses only over local changes on the paths the incoming
# commits rewrite. Each rig below gets its own remote: base commit b1 carries
# f.txt and cfg.txt, the checkout sits on b1, and origin's b2 rewrites f.txt
# alone, so a local cfg.txt edit stands in for machine-local config the
# fast-forward does not touch.
# ===========================================================================
behind_rig() { # name -> a clone on b1 of a remote whose main is b2
  local s="$TMP/$1.src"
  git init -q -b main "$s"
  echo base > "$s/f.txt"; echo cfg > "$s/cfg.txt"
  git -C "$s" add -A; git -C "$s" commit -qm b1
  git clone -q --bare "$s" "$TMP/$1.git"
  git clone -q "$TMP/$1.git" "$TMP/$1"
  echo upstream > "$s/f.txt"; git -C "$s" commit -qam b2
  git -C "$s" push -q "$TMP/$1.git" main
  git -C "$TMP/$1" fetch -q origin
}
set_aside_refs() { git -C "$TMP/$1" for-each-ref --format='%(refname)' refs/gc-toolkit/reconcile-set-aside/; }
# mu: a stray staged copy of content no ref holds, with the working copy still
# equal to HEAD, plus a local cfg.txt edit the fast-forward does not touch. The
# reset heal cannot help: cfg.txt differs from origin. The set-aside pins
# the staged copy, restores f.txt, fast-forwards, and leaves cfg.txt alone.
behind_rig mu
printf 'stray-staged\n' > "$TMP/mu/f.txt"; git -C "$TMP/mu" add f.txt
echo base > "$TMP/mu/f.txt"                                      # working copy back to HEAD: MM f.txt
echo machine-local > "$TMP/mu/cfg.txt"
MU_HEAD="$(git -C "$TMP/mu" rev-parse HEAD)"
MU_REMOTE="$(git -C "$TMP/mu.git" rev-parse main)"
rigs_json mu
: > "$TMP/escalations"; : > "$TMP/retractions"
RECONCILE_NO_AUTOHEAL=1 bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/mu" rev-parse HEAD)" "$MU_HEAD" "RECONCILE_NO_AUTOHEAL leaves a blocked behind checkout unmutated"
eq "$(git -C "$TMP/mu" show :f.txt)" "stray-staged" "RECONCILE_NO_AUTOHEAL leaves the staged copy in place"
eq "$(esc_count mu)" "1" "RECONCILE_NO_AUTOHEAL escalates a blocked behind checkout"
MU_BEAD="$(bead_for mu)"
MU_OUT="$(bash "$SCRIPT")"
eq "$(git -C "$TMP/mu" rev-parse HEAD)" "$MU_REMOTE" "a behind checkout blocked by a staged-only change fast-forwards"
eq "$(cat "$TMP/mu/f.txt")" "upstream" "the blocking path carries the fast-forwarded content"
eq "$(cat "$TMP/mu/cfg.txt")" "machine-local" "a dirty path the fast-forward does not rewrite is left as it is"
# A missing pin reads as a ref that cannot resolve; an empty one would make
# `git show :<path>` read the index instead.
MU_REF="$(set_aside_refs mu)"
[ -n "$MU_REF" ] && ok "the set-aside is pinned under refs/gc-toolkit/reconcile-set-aside/" || bad "the set-aside is pinned under refs/gc-toolkit/reconcile-set-aside/"
eq "$(git -C "$TMP/mu" show "${MU_REF:-refs/gc-toolkit/absent}^2:f.txt" 2>/dev/null)" "stray-staged" "the pin's second parent keeps the staged copy"
eq "$(git -C "$TMP/mu" show "${MU_REF:-refs/gc-toolkit/absent}:cfg.txt" 2>/dev/null)" "machine-local" "the pin also keeps every other dirty path's working copy"
eq "$(esc_count mu)" "1" "a set-aside heal raises no fresh escalation"
eq "$(open_count mu)" "0" "a set-aside heal closes the open reconcile bead"
eq "$(retract_count mu)" "1" "a set-aside heal retracts the tracking visit as moot"
eq "$(retract_subject mu)" "$MU_BEAD" "the set-aside retract names the reconcile bead"
grep -q '1 auto-healed' <<< "$MU_OUT" && ok "the summary counts a set-aside as an auto-heal" || bad "the summary counts a set-aside as an auto-heal (got '$MU_OUT')"

# nu: a stray `git checkout <branch> -- f.txt` staged AND wrote a pushed branch's
# copy. The working copy is neither HEAD nor origin/main, but a remote-tracking
# ref's history carries it, so the copy is set aside and the checkout advances.
behind_rig nu
git -C "$TMP/nu.src" checkout -q -b feature HEAD~1
echo feature-copy > "$TMP/nu.src/f.txt"; git -C "$TMP/nu.src" commit -qam feature
git -C "$TMP/nu.src" push -q "$TMP/nu.git" feature
git -C "$TMP/nu" fetch -q origin
git -C "$TMP/nu" checkout -q origin/feature -- f.txt              # index and working copy = feature
NU_REMOTE="$(git -C "$TMP/nu.git" rev-parse main)"
rigs_json nu
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/nu" rev-parse HEAD)" "$NU_REMOTE" "a working copy a pushed branch carries is set aside and the checkout advances"
NU_REF="$(set_aside_refs nu)"
eq "$(git -C "$TMP/nu" show "${NU_REF:-refs/gc-toolkit/absent}:f.txt" 2>/dev/null)" "feature-copy" "the pin keeps the pushed branch's working copy"
eq "$(esc_count nu)" "0" "a working copy a pushed branch carries is not escalated"

# xi: a local edit on a path the fast-forward rewrites, found in no ref. It may
# be machine-local config or real work, so nothing moves and the stall escalates.
behind_rig xi
echo local-edit > "$TMP/xi/f.txt"
XI_HEAD="$(git -C "$TMP/xi" rev-parse HEAD)"
rigs_json xi
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/xi" rev-parse HEAD)" "$XI_HEAD" "a local-only working copy on a rewritten path blocks the set-aside"
eq "$(cat "$TMP/xi/f.txt")" "local-edit" "the local-only working copy is left untouched"
eq "$(esc_count xi)" "1" "a local-only working copy on a rewritten path escalates"
eq "$(open_count xi)" "1" "a local-only working copy on a rewritten path files a reconcile bead"
eq "$(set_aside_refs xi)" "" "a refused set-aside pins nothing"

# omicron: staging the local edit proves nothing about it either.
behind_rig omicron
echo staged-local-edit > "$TMP/omicron/f.txt"; git -C "$TMP/omicron" add f.txt
OMICRON_HEAD="$(git -C "$TMP/omicron" rev-parse HEAD)"
rigs_json omicron
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/omicron" rev-parse HEAD)" "$OMICRON_HEAD" "a staged local-only edit on a rewritten path blocks the set-aside"
eq "$(git -C "$TMP/omicron" show :f.txt)" "staged-local-edit" "the staged local-only edit is left untouched"
eq "$(esc_count omicron)" "1" "a staged local-only edit on a rewritten path escalates"

# pi: an untracked file on a path the fast-forward adds. Nothing proves it
# expendable, so nothing moves and the stall escalates.
behind_rig pi
echo added > "$TMP/pi.src/new.txt"; git -C "$TMP/pi.src" add new.txt; git -C "$TMP/pi.src" commit -qm b3
git -C "$TMP/pi.src" push -q "$TMP/pi.git" main
git -C "$TMP/pi" fetch -q origin                                 # still on b1, now behind b2 and b3
echo mine > "$TMP/pi/new.txt"
PI_HEAD="$(git -C "$TMP/pi" rev-parse HEAD)"
rigs_json pi
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/pi" rev-parse HEAD)" "$PI_HEAD" "an untracked file on a path the fast-forward adds blocks the set-aside"
eq "$(cat "$TMP/pi/new.txt")" "mine" "the untracked file in the way is left untouched"
eq "$(esc_count pi)" "1" "an untracked file in the way escalates"

# sigma: the untracked file in the way already holds the bytes origin adds
# there, and no tracked path is dirty. The fast-forward writes those bytes back,
# so the file goes and the checkout advances, with nothing to pin.
behind_rig sigma
echo added > "$TMP/sigma.src/new.txt"; git -C "$TMP/sigma.src" add new.txt; git -C "$TMP/sigma.src" commit -qm b3
git -C "$TMP/sigma.src" push -q "$TMP/sigma.git" main
git -C "$TMP/sigma" fetch -q origin                              # still on b1, now behind b2 and b3
echo added > "$TMP/sigma/new.txt"
SIGMA_REMOTE="$(git -C "$TMP/sigma.git" rev-parse main)"
rigs_json sigma
: > "$TMP/escalations"
SIGMA_OUT="$(bash "$SCRIPT")"
eq "$(git -C "$TMP/sigma" rev-parse HEAD)" "$SIGMA_REMOTE" "an untracked copy of the content the fast-forward adds goes, and the checkout advances"
eq "$(git -C "$TMP/sigma" status --porcelain)" "" "the added path is tracked after the fast-forward"
eq "$(esc_count sigma)" "0" "an untracked copy of the content the fast-forward adds is not escalated"
eq "$(set_aside_refs sigma)" "" "with no tracked path set aside, nothing is pinned"
grep -q '1 auto-healed' <<< "$SIGMA_OUT" && ok "the summary counts the removal as an auto-heal" || bad "the summary counts the removal as an auto-heal (got '$SIGMA_OUT')"

# symlinked: an untracked symlink d points at a directory outside the checkout
# whose x holds the bytes the fast-forward adds at d/x. git does not look behind
# a symlink, so d itself is what sits in the way, and nothing outside the
# checkout is touched.
behind_rig symlinked
mkdir "$TMP/symlinked.src/d"; echo added > "$TMP/symlinked.src/d/x"
git -C "$TMP/symlinked.src" add -A; git -C "$TMP/symlinked.src" commit -qm b3
git -C "$TMP/symlinked.src" push -q "$TMP/symlinked.git" main
git -C "$TMP/symlinked" fetch -q origin                          # still on b1, now behind b2 and b3
mkdir "$TMP/outside"; echo added > "$TMP/outside/x"; ln -s "$TMP/outside" "$TMP/symlinked/d"
SYMLINKED_HEAD="$(git -C "$TMP/symlinked" rev-parse HEAD)"
rigs_json symlinked
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null
eq "$(cat "$TMP/outside/x" 2>/dev/null)" "added" "a file behind an untracked symlink is never removed"
eq "$(git -C "$TMP/symlinked" rev-parse HEAD)" "$SYMLINKED_HEAD" "an untracked symlink where the fast-forward adds a directory blocks the set-aside"
eq "$(esc_count symlinked)" "1" "an untracked symlink where the fast-forward adds a directory escalates"

# gone: the fast-forward deletes the tracked directory gone/, which also holds an
# untracked u, while a stray staged copy blocks f.txt. The fast-forward writes
# nothing where it deletes, so u is not in its way: it stays, and the checkout
# advances.
g="$TMP/gone.src"; git init -q -b main "$g"
echo base > "$g/f.txt"; mkdir "$g/gone"; echo t > "$g/gone/t"
git -C "$g" add -A; git -C "$g" commit -qm b1
git clone -q --bare "$g" "$TMP/gone.git"; git clone -q "$TMP/gone.git" "$TMP/gone"
echo upstream > "$g/f.txt"; git -C "$g" rm -q -r gone; git -C "$g" commit -qam b2
git -C "$g" push -q "$TMP/gone.git" main; git -C "$TMP/gone" fetch -q origin
echo mine > "$TMP/gone/gone/u"
printf 'stray-staged\n' > "$TMP/gone/f.txt"; git -C "$TMP/gone" add f.txt
echo base > "$TMP/gone/f.txt"                                    # working copy back to HEAD: MM f.txt
GONE_REMOTE="$(git -C "$TMP/gone.git" rev-parse main)"
rigs_json gone
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/gone" rev-parse HEAD)" "$GONE_REMOTE" "an untracked file in a directory the fast-forward deletes does not block the set-aside"
eq "$(cat "$TMP/gone/gone/u" 2>/dev/null)" "mine" "the untracked file in the deleted directory stays"
eq "$(esc_count gone)" "0" "an untracked file in a directory the fast-forward deletes is not escalated"

# ===========================================================================
# Ignored files. A rig ignores machine-local state, such as its bd config and
# credentials, so an ignored file in the way of what a move writes counts like
# any other untracked content. Each checkout below ignores its paths through
# its own .git/info/exclude, as a machine-local rule does, and the remote starts
# tracking one of them. git merge --ff-only and git reset --keep would both
# overwrite such a file.
# ===========================================================================
ignore_local() { printf '%s\n' "$2" >> "$TMP/$1/.git/info/exclude"; }
behind_adds() { # name path content -> the remote's b3 adds <path> holding <content>
  printf '%s\n' "$3" > "$TMP/$1.src/$2"
  git -C "$TMP/$1.src" add -- "$2"; git -C "$TMP/$1.src" commit -qm b3
  git -C "$TMP/$1.src" push -q "$TMP/$1.git" main
  git -C "$TMP/$1" fetch -q origin
}
empty_ls_files() { # a git shim on PATH that empties `git ls-files`
  { printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/git" <<GITSHIM
for a in "\$@"; do [ "\$a" = "ls-files" ] && exit 0; done
exec "$REAL_GIT" "\$@"
GITSHIM
  chmod +x "$TMP/bin/git"
}

# ignored: the fast-forward adds local.cfg, which the checkout holds as an
# ignored file with other content. The fast-forward refuses, and the set-aside
# escalates with the file untouched, naming it as ignored, since git status
# does not list it.
behind_rig ignored
behind_adds ignored local.cfg theirs
ignore_local ignored local.cfg; echo mine > "$TMP/ignored/local.cfg"
IGNORED_HEAD="$(git -C "$TMP/ignored" rev-parse HEAD)"
rigs_json ignored
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/ignored" rev-parse HEAD)" "$IGNORED_HEAD" "an ignored file on a path the fast-forward adds blocks it"
eq "$(cat "$TMP/ignored/local.cfg")" "mine" "the ignored file in the fast-forward's way is left untouched"
eq "$(esc_count ignored)" "1" "an ignored file in the fast-forward's way escalates"
grep -q 'ignored and in the way: local.cfg' <<< "$(body_for ignored)" \
  && ok "the escalation names the blocking file as ignored" || bad "the escalation names the blocking file as ignored (got '$(body_for ignored)')"

# ignoreddir: the fast-forward adds a file named cache where the checkout holds
# an ignored directory cache/, which writing the file would delete.
behind_rig ignoreddir
behind_adds ignoreddir cache theirs
ignore_local ignoreddir cache/; mkdir "$TMP/ignoreddir/cache"; echo mine > "$TMP/ignoreddir/cache/keep"
IGNOREDDIR_HEAD="$(git -C "$TMP/ignoreddir" rev-parse HEAD)"
rigs_json ignoreddir
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/ignoreddir" rev-parse HEAD)" "$IGNOREDDIR_HEAD" "an ignored directory where the fast-forward adds a file blocks it"
eq "$(cat "$TMP/ignoreddir/cache/keep" 2>/dev/null)" "mine" "the ignored directory's file is left untouched"
eq "$(esc_count ignoreddir)" "1" "an ignored directory in the fast-forward's way escalates"

# ignoredcopy: the ignored local.cfg already holds the bytes the fast-forward
# adds, so it goes and the checkout advances. An ignored file the fast-forward
# does not write, state/db, stays.
behind_rig ignoredcopy
behind_adds ignoredcopy local.cfg theirs
ignore_local ignoredcopy local.cfg; echo theirs > "$TMP/ignoredcopy/local.cfg"
ignore_local ignoredcopy state/; mkdir "$TMP/ignoredcopy/state"; echo keep > "$TMP/ignoredcopy/state/db"
IGNOREDCOPY_REMOTE="$(git -C "$TMP/ignoredcopy.git" rev-parse main)"
rigs_json ignoredcopy
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/ignoredcopy" rev-parse HEAD)" "$IGNOREDCOPY_REMOTE" "an ignored copy of the content the fast-forward adds goes, and the checkout advances"
eq "$(git -C "$TMP/ignoredcopy" status --porcelain)" "" "the ignored copy's path is tracked after the fast-forward"
eq "$(cat "$TMP/ignoredcopy/state/db" 2>/dev/null)" "keep" "an ignored file the fast-forward does not write stays"
eq "$(esc_count ignoredcopy)" "0" "an ignored copy of the content the fast-forward adds is not escalated"

# ignoredretry: a stray staged f.txt blocks the fast-forward, and the remote
# also adds local.cfg, which the checkout holds as an ignored file with other
# content. With the untracked listing emptied, the set-aside pins and restores
# f.txt and retries, and the retry refuses rather than overwrite local.cfg.
behind_rig ignoredretry
behind_adds ignoredretry local.cfg theirs
printf 'stray-staged\n' > "$TMP/ignoredretry/f.txt"; git -C "$TMP/ignoredretry" add f.txt
echo base > "$TMP/ignoredretry/f.txt"                            # working copy back to HEAD: MM f.txt
ignore_local ignoredretry local.cfg; echo mine > "$TMP/ignoredretry/local.cfg"
IGNOREDRETRY_HEAD="$(git -C "$TMP/ignoredretry" rev-parse HEAD)"
rigs_json ignoredretry
: > "$TMP/escalations"
empty_ls_files
bash "$SCRIPT" >/dev/null
rm -f "$TMP/bin/git"
eq "$(git -C "$TMP/ignoredretry" rev-parse HEAD)" "$IGNOREDRETRY_HEAD" "the set-aside's retry refuses an ignored file the listing misses"
eq "$(cat "$TMP/ignoredretry/local.cfg")" "mine" "the ignored file the retry would overwrite is left untouched"
IGNOREDRETRY_REF="$(set_aside_refs ignoredretry)"
eq "$(git -C "$TMP/ignoredretry" show "${IGNOREDRETRY_REF:-refs/gc-toolkit/absent}^2:f.txt" 2>/dev/null)" "stray-staged" "the refused retry leaves the staged copy pinned"
eq "$(esc_count ignoredretry)" "1" "a refused retry escalates"

# churnignored: the remote's rewritten history adds local.cfg, which the
# checkout holds as an ignored file with other content. The reset heal refuses
# before anything moves.
churned_rig churnignored
echo theirs > "$TMP/churnignored.src/local.cfg"; echo same > "$TMP/churnignored.src/same.txt"; push_churn churnignored
ignore_local churnignored local.cfg; echo mine > "$TMP/churnignored/local.cfg"; echo same > "$TMP/churnignored/same.txt"
CHURNIGNORED_LOCAL="$(git -C "$TMP/churnignored" rev-parse HEAD)"
rigs_json churnignored
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/churnignored" rev-parse HEAD)" "$CHURNIGNORED_LOCAL" "an ignored file on a path the remote adds blocks the reset heal"
eq "$(cat "$TMP/churnignored/local.cfg")" "mine" "the ignored file in the reset's way is left untouched"
refused_untouched churnignored "an ignored file on a path the remote adds"
body_has churnignored '^ignored and in the way: local\.cfg \(git status does not list it, the reset would' \
  && ok "the diverged escalation names the blocking file as ignored" \
  || bad "the diverged escalation names the blocking file as ignored (got '$(body_for churnignored)')"
# With the untracked copy the escalation lists cleared and the ignored file
# left in place, the checkout the escalation hands a person refuses rather than
# overwrites it.
body_has churnignored '^untracked, already upstream: same\.txt ' \
  && ok "the escalation lists the untracked copy a reset by hand must clear" \
  || bad "the escalation lists the untracked copy a reset by hand must clear (got '$(body_for churnignored)')"
rm -f "$TMP/churnignored/same.txt"
read -ra REMEDY <<< "$(remedy_for churnignored)"
eq "$(remedy_rc)" "1" "the handed checkout refuses an ignored file in its way"
eq "$(cat "$TMP/churnignored/local.cfg")" "mine" "the handed checkout leaves the ignored file's bytes"
eq "$(git -C "$TMP/churnignored" rev-parse HEAD)" "$CHURNIGNORED_LOCAL" "a refused handed checkout leaves the checkout where it was"

# churnignoredcopy: the ignored local.cfg already holds the remote's bytes, so
# it goes and the checkout heals. An ignored file the remote does not track,
# state/db, stays.
churned_rig churnignoredcopy
echo theirs > "$TMP/churnignoredcopy.src/local.cfg"; push_churn churnignoredcopy
ignore_local churnignoredcopy local.cfg; echo theirs > "$TMP/churnignoredcopy/local.cfg"
ignore_local churnignoredcopy state/; mkdir "$TMP/churnignoredcopy/state"; echo keep > "$TMP/churnignoredcopy/state/db"
CHURNIGNOREDCOPY_REMOTE="$(git -C "$TMP/churnignoredcopy.git" rev-parse main)"
rigs_json churnignoredcopy
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/churnignoredcopy" rev-parse HEAD)" "$CHURNIGNOREDCOPY_REMOTE" "an ignored copy of a file the remote adds does not block the reset heal"
eq "$(git -C "$TMP/churnignoredcopy" status --porcelain)" "" "the ignored copy's path is tracked after the reset"
eq "$(cat "$TMP/churnignoredcopy/state/db" 2>/dev/null)" "keep" "an ignored file the remote does not track survives the reset"
eq "$(esc_count churnignoredcopy)" "0" "an ignored copy of a file the remote adds is not escalated"

# churnignoredunlisted: the guard's listing comes back empty, so it sees nothing
# in the way of the remote's local.cfg. The reset's git checkout runs with
# --no-overwrite-ignore and refuses rather than overwrite the ignored file.
churned_rig churnignoredunlisted
echo theirs > "$TMP/churnignoredunlisted.src/local.cfg"; push_churn churnignoredunlisted
ignore_local churnignoredunlisted local.cfg; echo mine > "$TMP/churnignoredunlisted/local.cfg"
CHURNIGNOREDUNLISTED_LOCAL="$(git -C "$TMP/churnignoredunlisted" rev-parse HEAD)"
rigs_json churnignoredunlisted
: > "$TMP/escalations"
empty_ls_files
bash "$SCRIPT" >/dev/null
rm -f "$TMP/bin/git"
eq "$(cat "$TMP/churnignoredunlisted/local.cfg")" "mine" "an ignored file the guard's listing misses is not overwritten by the reset"
eq "$(git -C "$TMP/churnignoredunlisted" rev-parse HEAD)" "$CHURNIGNOREDUNLISTED_LOCAL" "a reset that would overwrite an ignored file leaves the checkout where it was"
eq "$(esc_count churnignoredunlisted)" "1" "a reset that would overwrite an ignored file escalates"

# churnignoredcase: an ignored Readme.cfg where the remote adds README.cfg. On a
# file system that ignores case they are one file, which the guard's listing
# does not match, and the reset's git checkout refuses rather than overwrite it;
# where case matters they are two files and the reset heals. Either way
# Readme.cfg keeps its bytes.
churned_rig churnignoredcase
echo theirs > "$TMP/churnignoredcase.src/README.cfg"; push_churn churnignoredcase
ignore_local churnignoredcase Readme.cfg; echo mine > "$TMP/churnignoredcase/Readme.cfg"
rigs_json churnignoredcase
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null
eq "$(cat "$TMP/churnignoredcase/Readme.cfg" 2>/dev/null)" "mine" "an ignored file only case separates from a file the remote adds keeps its bytes"

# ===========================================================================
# Hooks. git checkout and git restore run the post-checkout hook and exit with
# its status, so the heals run them with the rig's hooks off. Each checkout
# below points core.hooksPath at a post-checkout hook that records its run and
# fails.
# ===========================================================================
mkdir -p "$TMP/failhooks"
printf '#!/bin/sh\necho "post-checkout $*" >> "%s"\nexit 1\n' "$TMP/hookruns" > "$TMP/failhooks/post-checkout"
chmod +x "$TMP/failhooks/post-checkout"

# churnhooked: an already-upstream SHA churn on a branch with no upstream
# config. The reset heal moves it to the remote, runs no hook, and leaves the
# upstream config unset.
churned_rig churnhooked
echo theirs > "$TMP/churnhooked.src/new.txt"; push_churn churnhooked
git -C "$TMP/churnhooked" config core.hooksPath "$TMP/failhooks"
git -C "$TMP/churnhooked" branch -q --unset-upstream
CHURNHOOKED_REMOTE="$(git -C "$TMP/churnhooked.git" rev-parse main)"
rigs_json churnhooked
: > "$TMP/escalations"; : > "$TMP/hookruns"
bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/churnhooked" rev-parse HEAD)" "$CHURNHOOKED_REMOTE" "a failing post-checkout hook does not stop the reset heal"
eq "$(esc_count churnhooked)" "0" "a reset heal under a failing post-checkout hook is not escalated"
eq "$(cat "$TMP/hookruns")" "" "the reset heal runs no hook"
eq "$(git -C "$TMP/churnhooked" config --get branch.main.merge || true)" "" "the reset heal leaves the branch's upstream config as it is"

# hookedbehind: a stray staged f.txt blocks the fast-forward, as in mu. The
# set-aside pins and restores it with no hook run, and the checkout advances.
behind_rig hookedbehind
printf 'stray-staged\n' > "$TMP/hookedbehind/f.txt"; git -C "$TMP/hookedbehind" add f.txt
echo base > "$TMP/hookedbehind/f.txt"                            # working copy back to HEAD: MM f.txt
git -C "$TMP/hookedbehind" config core.hooksPath "$TMP/failhooks"
HOOKEDBEHIND_REMOTE="$(git -C "$TMP/hookedbehind.git" rev-parse main)"
rigs_json hookedbehind
: > "$TMP/escalations"; : > "$TMP/hookruns"
bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/hookedbehind" rev-parse HEAD)" "$HOOKEDBEHIND_REMOTE" "a failing post-checkout hook does not stop the set-aside heal"
eq "$(esc_count hookedbehind)" "0" "a set-aside under a failing post-checkout hook is not escalated"
eq "$(cat "$TMP/hookruns")" "" "the set-aside heal runs no hook"

# ===========================================================================
# Kept paths. The remote stops tracking .beads/config.yaml and
# .beads/metadata.json and ignores them, as a repository does once gascity owns
# its bd config. The fast-forward would delete each working copy, or refuse
# over a modified one, so the checkout keeps each in place untracked instead.
# untrack_rig builds a clone on u1, which tracks both files through exceptions
# to .beads/*, of a remote whose u2 untracks them under the top .gitignore
# given as $2 and, with $3, a .beads/.gitignore holding $3.
# ===========================================================================
untrack_rig() { # name top-gitignore [beads-gitignore]
  local s="$TMP/$1.src"
  git init -q -b main "$s"; mkdir -p "$s/.beads"
  printf '.beads/*\n!.beads/config.yaml\n!.beads/metadata.json\n' > "$s/.gitignore"
  echo cfg > "$s/.beads/config.yaml"; echo meta > "$s/.beads/metadata.json"; echo base > "$s/f.txt"
  git -C "$s" add -A; git -C "$s" commit -qm u1
  git clone -q --bare "$s" "$TMP/$1.git"
  git clone -q "$TMP/$1.git" "$TMP/$1"
  printf '%s\n' "$2" > "$s/.gitignore"
  if [ -n "${3:-}" ]; then printf '%s\n' "$3" > "$s/.beads/.gitignore"; git -C "$s" add -f .beads/.gitignore; fi
  git -C "$s" rm -q --cached .beads/config.yaml .beads/metadata.json
  echo upstream > "$s/f.txt"; git -C "$s" add .gitignore f.txt; git -C "$s" commit -qm u2
  git -C "$s" push -q "$TMP/$1.git" main
  git -C "$TMP/$1" fetch -q origin
}
gascity_writes() { printf 'dolt.mode: server\n' >> "$TMP/$1/.beads/config.yaml"; }
GASCITY_CFG=$'cfg\ndolt.mode: server'
# the number of kept copies waiting aside in a checkout.
kept_waiting() { find "$TMP/$1/.git/gc-toolkit-reconcile-kept" -type f 2>/dev/null | wc -l | tr -d ' '; }

# untracked: the live gc-toolkit checkout's shape. gascity's modified bd config
# and a clean metadata.json stay in place byte for byte, untracked and ignored,
# and the modified one is pinned before it moves. The remote's u3 also starts
# tracking identity.toml, which the checkout holds as an ignored copy of the
# same bytes. The same pass removes that copy before the fast-forward, which
# writes it back, or the fast-forward would refuse over it.
untrack_rig untracked '.beads/*'
printf '.beads/*\n!.beads/identity.toml\n' > "$TMP/untracked.src/.gitignore"
echo 'id = "rig"' > "$TMP/untracked.src/.beads/identity.toml"
git -C "$TMP/untracked.src" add .gitignore .beads/identity.toml; git -C "$TMP/untracked.src" commit -qm u3
git -C "$TMP/untracked.src" push -q "$TMP/untracked.git" main; git -C "$TMP/untracked" fetch -q origin
echo 'id = "rig"' > "$TMP/untracked/.beads/identity.toml"
gascity_writes untracked
UNTRACKED_REMOTE="$(git -C "$TMP/untracked.git" rev-parse main)"
rigs_json untracked
: > "$TMP/escalations"
UNTRACKED_OUT="$(bash "$SCRIPT")"
eq "$(git -C "$TMP/untracked" rev-parse HEAD)" "$UNTRACKED_REMOTE" "a fast-forward that stops tracking an ignored, modified file lands"
eq "$(cat "$TMP/untracked/.beads/config.yaml" 2>/dev/null)" "$GASCITY_CFG" "the modified file stays in place unchanged"
eq "$(cat "$TMP/untracked/.beads/metadata.json" 2>/dev/null)" "meta" "a clean file the fast-forward would delete stays in place"
eq "$(git -C "$TMP/untracked" status --porcelain)" "" "the kept files are untracked and ignored, so git status is empty"
eq "$(git -C "$TMP/untracked" ls-files .beads)" ".beads/identity.toml" "the kept files are no longer tracked, and the file the remote starts tracking is"
eq "$(cat "$TMP/untracked/.beads/identity.toml" 2>/dev/null)" 'id = "rig"' "the ignored copy the remote starts tracking ends with its bytes"
UNTRACKED_REF="$(set_aside_refs untracked)"
eq "$(git -C "$TMP/untracked" show "${UNTRACKED_REF:-refs/gc-toolkit/absent}:.beads/config.yaml" 2>/dev/null)" "$GASCITY_CFG" "the modified kept file is pinned before it moves"
eq "$(kept_waiting untracked)" "0" "no kept copy is left waiting aside"
[ ! -e "$TMP/untracked/.git/gc-toolkit-reconcile-kept" ] && ok "the emptied keep directory is removed" || bad "the emptied keep directory is removed"
eq "$(esc_count untracked)" "0" "keeping the files in place is not escalated"
grep -q '1 auto-healed' <<< "$UNTRACKED_OUT" && ok "the summary counts the keep as an auto-heal" || bad "the summary counts the keep as an auto-heal (got '$UNTRACKED_OUT')"

# untrackedclean: both files are clean, so a plain fast-forward would succeed
# and delete them. A .gitignore inside .beads/ ignores them on the remote.
untrack_rig untrackedclean '' '*'
UNTRACKEDCLEAN_REMOTE="$(git -C "$TMP/untrackedclean.git" rev-parse main)"
rigs_json untrackedclean
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/untrackedclean" rev-parse HEAD)" "$UNTRACKEDCLEAN_REMOTE" "a fast-forward that would delete clean files the remote stops tracking and ignores lands"
eq "$(cat "$TMP/untrackedclean/.beads/config.yaml" 2>/dev/null)" "cfg" "a clean kept file stays in place"
eq "$(cat "$TMP/untrackedclean/.beads/metadata.json" 2>/dev/null)" "meta" "every clean kept file stays in place"
eq "$(git -C "$TMP/untrackedclean" status --porcelain)" "" "a .gitignore below the top directory ignores the kept files"
eq "$(set_aside_refs untrackedclean)" "" "with nothing modified, nothing is pinned"
eq "$(esc_count untrackedclean)" "0" "keeping clean files in place is not escalated"

# untrackedstagedgone: a person already ran git rm --cached on metadata.json.
# Its staged deletion matches the remote, so it is kept too.
untrack_rig untrackedstagedgone '.beads/*'
git -C "$TMP/untrackedstagedgone" rm -q --cached .beads/metadata.json
UNTRACKEDSTAGEDGONE_REMOTE="$(git -C "$TMP/untrackedstagedgone.git" rev-parse main)"
rigs_json untrackedstagedgone
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/untrackedstagedgone" rev-parse HEAD)" "$UNTRACKEDSTAGEDGONE_REMOTE" "a file already staged for deletion is kept and the checkout advances"
eq "$(cat "$TMP/untrackedstagedgone/.beads/metadata.json" 2>/dev/null)" "meta" "the file staged for deletion stays in place"
eq "$(git -C "$TMP/untrackedstagedgone" status --porcelain)" "" "the file staged for deletion ends untracked and ignored"

# untrackednotignored: the remote deletes the modified file but its tree does
# not ignore it. The checkout's own exclude file, a global excludes file and a
# git template's exclude file all ignore .beads/, and none of them counts, so
# the stall escalates with nothing moved.
untrack_rig untrackednotignored '*.swp'
gascity_writes untrackednotignored
ignore_local untrackednotignored .beads/
mkdir -p "$TMP/template/info"; echo .beads/ > "$TMP/template/info/exclude"; echo .beads/ > "$TMP/global-excludes"
UNTRACKEDNOTIGNORED_HEAD="$(git -C "$TMP/untrackednotignored" rev-parse HEAD)"
rigs_json untrackednotignored
: > "$TMP/escalations"
GIT_TEMPLATE_DIR="$TMP/template" GIT_CONFIG_COUNT=3 GIT_CONFIG_KEY_2=core.excludesFile GIT_CONFIG_VALUE_2="$TMP/global-excludes" \
  bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/untrackednotignored" rev-parse HEAD)" "$UNTRACKEDNOTIGNORED_HEAD" "a deleted path the remote's tree does not ignore is not kept, whatever the checkout ignores"
eq "$(cat "$TMP/untrackednotignored/.beads/config.yaml" 2>/dev/null)" "$GASCITY_CFG" "the modified file the remote does not ignore is left untouched"
eq "$(git -C "$TMP/untrackednotignored" ls-files .beads/metadata.json)" ".beads/metadata.json" "a refused fast-forward leaves the clean file tracked"
eq "$(esc_count untrackednotignored)" "1" "a modified file the remote deletes without ignoring it escalates"
body_has untrackednotignored '^local-only content: \.beads/config\.yaml ' \
  && ok "the escalation names the modified file as local-only content" \
  || bad "the escalation names the modified file as local-only content (got '$(body_for untrackednotignored)')"

# untrackedrewritten: the remote ignores .beads/* but rewrites config.yaml
# rather than deleting it, so it stays tracked and the stall escalates.
s="$TMP/untrackedrewritten.src"; git init -q -b main "$s"; mkdir -p "$s/.beads"
printf '.beads/*\n!.beads/config.yaml\n' > "$s/.gitignore"; echo cfg > "$s/.beads/config.yaml"
git -C "$s" add -A; git -C "$s" commit -qm u1
git clone -q --bare "$s" "$TMP/untrackedrewritten.git"; git clone -q "$TMP/untrackedrewritten.git" "$TMP/untrackedrewritten"
printf '.beads/*\n' > "$s/.gitignore"; echo cfg2 > "$s/.beads/config.yaml"
git -C "$s" add -f .gitignore .beads/config.yaml; git -C "$s" commit -qm u2
git -C "$s" push -q "$TMP/untrackedrewritten.git" main; git -C "$TMP/untrackedrewritten" fetch -q origin
gascity_writes untrackedrewritten
UNTRACKEDREWRITTEN_HEAD="$(git -C "$TMP/untrackedrewritten" rev-parse HEAD)"
rigs_json untrackedrewritten
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/untrackedrewritten" rev-parse HEAD)" "$UNTRACKEDREWRITTEN_HEAD" "a modified file the remote rewrites rather than deletes is not kept"
eq "$(cat "$TMP/untrackedrewritten/.beads/config.yaml" 2>/dev/null)" "$GASCITY_CFG" "the modified file the remote rewrites is left untouched"
eq "$(esc_count untrackedrewritten)" "1" "a modified file the remote rewrites escalates"

# untrackedstagededit: a staged edit of config.yaml matches neither HEAD nor the
# remote, so the path is left to the set-aside's proof, which escalates it.
untrack_rig untrackedstagededit '.beads/*'
printf 'staged-edit\n' > "$TMP/untrackedstagededit/.beads/config.yaml"; git -C "$TMP/untrackedstagededit" add .beads/config.yaml
UNTRACKEDSTAGEDEDIT_HEAD="$(git -C "$TMP/untrackedstagededit" rev-parse HEAD)"
rigs_json untrackedstagededit
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/untrackedstagededit" rev-parse HEAD)" "$UNTRACKEDSTAGEDEDIT_HEAD" "a staged edit of a path the remote stops tracking blocks the fast-forward"
eq "$(git -C "$TMP/untrackedstagededit" show :.beads/config.yaml 2>/dev/null)" "staged-edit" "the staged edit is left untouched"
body_has untrackedstagededit '^local-only content: \.beads/config\.yaml ' \
  && ok "the escalation names the staged edit as local-only content" \
  || bad "the escalation names the staged edit as local-only content (got '$(body_for untrackedstagededit)')"

# untrackedretry: the remote also adds local.cfg, which the checkout holds as an
# ignored file with other content. With the untracked listing emptied, the keep
# moves the files aside and the fast-forward refuses rather than overwrite
# local.cfg, so the kept copies go back and the stall escalates.
untrack_rig untrackedretry '.beads/*'
behind_adds untrackedretry local.cfg theirs
gascity_writes untrackedretry
ignore_local untrackedretry local.cfg; echo mine > "$TMP/untrackedretry/local.cfg"
UNTRACKEDRETRY_HEAD="$(git -C "$TMP/untrackedretry" rev-parse HEAD)"
rigs_json untrackedretry
: > "$TMP/escalations"
empty_ls_files
bash "$SCRIPT" >/dev/null
rm -f "$TMP/bin/git"
eq "$(git -C "$TMP/untrackedretry" rev-parse HEAD)" "$UNTRACKEDRETRY_HEAD" "a refused fast-forward leaves the checkout where it was"
eq "$(cat "$TMP/untrackedretry/.beads/config.yaml" 2>/dev/null)" "$GASCITY_CFG" "a refused fast-forward puts the modified kept file back"
eq "$(cat "$TMP/untrackedretry/.beads/metadata.json" 2>/dev/null)" "meta" "a refused fast-forward puts the clean kept file back"
eq "$(git -C "$TMP/untrackedretry" ls-files .beads | tr '\n' ' ')" ".beads/config.yaml .beads/metadata.json " "a refused fast-forward leaves the kept files tracked"
eq "$(cat "$TMP/untrackedretry/local.cfg")" "mine" "the ignored file the fast-forward would overwrite is left untouched"
eq "$(kept_waiting untrackedretry)" "0" "a refused fast-forward leaves no kept copy waiting aside"
eq "$(esc_count untrackedretry)" "1" "a refused fast-forward after the keep escalates"
body_has untrackedretry 'each kept copy went back on its path' \
  && ok "the escalation says the kept copies went back" \
  || bad "the escalation says the kept copies went back (got '$(body_for untrackedretry)')"

# untrackedleftover: a pass was interrupted while the kept files waited aside.
# The next pass puts them back, keeps them, and fast-forwards.
untrack_rig untrackedleftover '.beads/*'
gascity_writes untrackedleftover
mkdir -p "$TMP/untrackedleftover/.git/gc-toolkit-reconcile-kept/.beads"
mv "$TMP/untrackedleftover/.beads/config.yaml" "$TMP/untrackedleftover/.beads/metadata.json" "$TMP/untrackedleftover/.git/gc-toolkit-reconcile-kept/.beads/"
UNTRACKEDLEFTOVER_REMOTE="$(git -C "$TMP/untrackedleftover.git" rev-parse main)"
rigs_json untrackedleftover
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null 2>&1
eq "$(git -C "$TMP/untrackedleftover" rev-parse HEAD)" "$UNTRACKEDLEFTOVER_REMOTE" "the pass after an interrupted keep fast-forwards"
eq "$(cat "$TMP/untrackedleftover/.beads/config.yaml" 2>/dev/null)" "$GASCITY_CFG" "a copy an interrupted pass left aside goes back on its path"
eq "$(cat "$TMP/untrackedleftover/.beads/metadata.json" 2>/dev/null)" "meta" "every copy an interrupted pass left aside goes back"
eq "$(kept_waiting untrackedleftover)" "0" "no copy is left waiting aside after the next pass"
eq "$(git -C "$TMP/untrackedleftover" status --porcelain)" "" "the files put back end untracked and ignored"

# untrackedoffline: the same interrupted pass, but the next pass cannot fetch.
# Putting the kept files back needs no network, so they go back anyway, and
# nothing else moves.
untrack_rig untrackedoffline '.beads/*'
gascity_writes untrackedoffline
mkdir -p "$TMP/untrackedoffline/.git/gc-toolkit-reconcile-kept/.beads"
mv "$TMP/untrackedoffline/.beads/config.yaml" "$TMP/untrackedoffline/.beads/metadata.json" "$TMP/untrackedoffline/.git/gc-toolkit-reconcile-kept/.beads/"
git -C "$TMP/untrackedoffline" remote set-url origin "$TMP/absent.git"
UNTRACKEDOFFLINE_HEAD="$(git -C "$TMP/untrackedoffline" rev-parse HEAD)"
rigs_json untrackedoffline
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null 2>&1
eq "$(cat "$TMP/untrackedoffline/.beads/config.yaml" 2>/dev/null)" "$GASCITY_CFG" "a pass that cannot fetch still puts back a copy an interrupted pass left aside"
eq "$(cat "$TMP/untrackedoffline/.beads/metadata.json" 2>/dev/null)" "meta" "a pass that cannot fetch puts back every copy left aside"
eq "$(kept_waiting untrackedoffline)" "0" "a pass that cannot fetch leaves no copy waiting aside"
eq "$(git -C "$TMP/untrackedoffline" rev-parse HEAD)" "$UNTRACKEDOFFLINE_HEAD" "a pass that cannot fetch moves nothing else"
eq "$(git -C "$TMP/untrackedoffline" status --porcelain)" " M .beads/config.yaml" "the files put back are tracked again, as before the interrupted pass"

# untrackedrefilled: something writes config.yaml while its kept copy waits
# aside, here a post-merge hook. The fast-forward lands, but the copy does not
# go back over the new file, and HEAD no longer tracks the path, so no later
# keep finds it. Both copies stay, and the rig stays escalated, on that pass and
# on the next, already up to date, until nothing waits aside. A subject a
# refusal filed first is kept open too, and retitled.
untrack_rig untrackedrefilled '.beads/*'
gascity_writes untrackedrefilled
mkdir -p "$TMP/refillhooks"
printf '#!/bin/sh\nmkdir -p .beads && echo refilled > .beads/config.yaml\n' > "$TMP/refillhooks/post-merge"
chmod +x "$TMP/refillhooks/post-merge"
git -C "$TMP/untrackedrefilled" config core.hooksPath "$TMP/refillhooks"
UNTRACKEDREFILLED_REMOTE="$(git -C "$TMP/untrackedrefilled.git" rev-parse main)"
UNTRACKEDREFILLED_WAIT="$TMP/untrackedrefilled/.git/gc-toolkit-reconcile-kept/.beads/config.yaml"
rigs_json untrackedrefilled
: > "$TMP/escalations"; : > "$TMP/retractions"
RECONCILE_NO_AUTOHEAL=1 bash "$SCRIPT" >/dev/null
UNTRACKEDREFILLED_BEAD="$(bead_for untrackedrefilled)"
eq "$(title_for untrackedrefilled)" "Reconcile: rigs/untrackedrefilled cannot fast-forward to origin/main" "a refused fast-forward files its subject as one that cannot fast-forward"
UNTRACKEDREFILLED_OUT="$(bash "$SCRIPT" 2>/dev/null)"
eq "$(git -C "$TMP/untrackedrefilled" rev-parse HEAD)" "$UNTRACKEDREFILLED_REMOTE" "a fast-forward whose kept copy cannot go back still lands"
eq "$(cat "$TMP/untrackedrefilled/.beads/config.yaml" 2>/dev/null)" "refilled" "the file written on the kept path meanwhile is left as it is"
eq "$(cat "$UNTRACKEDREFILLED_WAIT" 2>/dev/null)" "$GASCITY_CFG" "the kept copy that cannot go back waits aside unchanged"
eq "$(cat "$TMP/untrackedrefilled/.beads/metadata.json" 2>/dev/null)" "meta" "a kept copy whose path stayed empty goes back"
eq "$(bead_for untrackedrefilled)" "$UNTRACKEDREFILLED_BEAD" "a set-aside that leaves a kept copy waiting aside keeps the subject open"
eq "$(retract_count untrackedrefilled)" "0" "a set-aside that leaves a kept copy waiting aside retracts nothing"
eq "$(esc_count untrackedrefilled)" "2" "a kept copy that cannot go back escalates"
eq "$(title_for untrackedrefilled)" "Reconcile: rigs/untrackedrefilled holds a kept file it could not put back" "the open subject is retitled for the copy waiting aside"
body_has untrackedrefilled "^\.beads/config\.yaml waits at .*/untrackedrefilled/\.git/gc-toolkit-reconcile-kept/\.beads/config\.yaml: something else was written on " \
  && ok "the subject names the copy waiting aside and where it waits" \
  || bad "the subject names the copy waiting aside and where it waits (got '$(body_for untrackedrefilled)')"
grep -q '0 auto-healed, 1 blocked' <<< "$UNTRACKEDREFILLED_OUT" \
  && ok "the summary counts a rig with a copy waiting aside as blocked" \
  || bad "the summary counts a rig with a copy waiting aside as blocked (got '$UNTRACKEDREFILLED_OUT')"
UNTRACKEDREFILLED_OUT="$(bash "$SCRIPT" 2>/dev/null)"
eq "$(cat "$TMP/untrackedrefilled/.beads/config.yaml" 2>/dev/null)/$(cat "$UNTRACKEDREFILLED_WAIT" 2>/dev/null)" "refilled/$GASCITY_CFG" "the next pass keeps both copies"
eq "$(bead_for untrackedrefilled)" "$UNTRACKEDREFILLED_BEAD" "the next pass, already up to date, keeps the subject open"
eq "$(retract_count untrackedrefilled)" "0" "the next pass retracts nothing while a kept copy waits aside"
eq "$(esc_count untrackedrefilled)" "3" "the next pass escalates again"
grep -q '0 advanced, 0 auto-healed, 1 blocked' <<< "$UNTRACKEDREFILLED_OUT" \
  && ok "the next pass counts the rig as blocked, not advanced" \
  || bad "the next pass counts the rig as blocked, not advanced (got '$UNTRACKEDREFILLED_OUT')"
# A person keeps the copy that waits aside: the file on its path goes elsewhere.
git -C "$TMP/untrackedrefilled" config --unset core.hooksPath
mv "$TMP/untrackedrefilled/.beads/config.yaml" "$TMP/untrackedrefilled.refilled"
UNTRACKEDREFILLED_OUT="$(bash "$SCRIPT" 2>/dev/null)"
eq "$(cat "$TMP/untrackedrefilled/.beads/config.yaml" 2>/dev/null)" "$GASCITY_CFG" "once its path is free, the next pass puts the copy back"
grep -q '1 advanced, 0 auto-healed, 0 blocked' <<< "$UNTRACKEDREFILLED_OUT" \
  && ok "once the copy is back, the pass counts the rig as advanced" \
  || bad "once the copy is back, the pass counts the rig as advanced (got '$UNTRACKEDREFILLED_OUT')"
eq "$(kept_waiting untrackedrefilled)" "0" "once the copy is back, none waits aside"
eq "$(open_count untrackedrefilled)" "0" "the subject closes once no kept copy waits aside"
eq "$(retract_count untrackedrefilled)" "1" "the subject's tracking visit is retracted once no kept copy waits aside"
eq "$(git -C "$TMP/untrackedrefilled" status --porcelain)" "" "the copy put back ends untracked and ignored"

# untrackedsame: the writer puts the kept copy's own bytes on its path. That
# file loses nothing to the copy, so the copy goes and the keep heals.
untrack_rig untrackedsame '.beads/*'
gascity_writes untrackedsame
mkdir -p "$TMP/samehooks"
cat > "$TMP/samehooks/post-merge" <<'HOOK'
#!/bin/sh
mkdir -p .beads && printf 'cfg\ndolt.mode: server\n' > .beads/config.yaml
HOOK
chmod +x "$TMP/samehooks/post-merge"
git -C "$TMP/untrackedsame" config core.hooksPath "$TMP/samehooks"
UNTRACKEDSAME_REMOTE="$(git -C "$TMP/untrackedsame.git" rev-parse main)"
rigs_json untrackedsame
: > "$TMP/escalations"
UNTRACKEDSAME_OUT="$(bash "$SCRIPT" 2>/dev/null)"
eq "$(git -C "$TMP/untrackedsame" rev-parse HEAD)" "$UNTRACKEDSAME_REMOTE" "a fast-forward whose kept path is written with the same bytes meanwhile lands"
eq "$(cat "$TMP/untrackedsame/.beads/config.yaml" 2>/dev/null)" "$GASCITY_CFG" "the kept path holds the kept bytes"
eq "$(kept_waiting untrackedsame)" "0" "a copy whose bytes its path holds again does not wait aside"
eq "$(esc_count untrackedsame)" "0" "a kept path written with the same bytes meanwhile is not escalated"
grep -q '1 auto-healed, 0 blocked' <<< "$UNTRACKEDSAME_OUT" \
  && ok "the summary counts the keep as an auto-heal" \
  || bad "the summary counts the keep as an auto-heal (got '$UNTRACKEDSAME_OUT')"

# untrackedrelinked: while git fast-forwards, something moves the directory the
# kept copies wait in onto .beads and leaves a symlink to it in its place, here
# a post-merge hook. Each path then holds its own copy, and the copy aside is
# that same file under another name for its directory, so removing it would
# empty the path. Both files stay on their paths unchanged.
untrack_rig untrackedrelinked '.beads/*'
gascity_writes untrackedrelinked
mkdir -p "$TMP/relinkhooks"
cat > "$TMP/relinkhooks/post-merge" <<'HOOK'
#!/bin/sh
mv .git/gc-toolkit-reconcile-kept/.beads .beads && ln -s ../../.beads .git/gc-toolkit-reconcile-kept/.beads
HOOK
chmod +x "$TMP/relinkhooks/post-merge"
git -C "$TMP/untrackedrelinked" config core.hooksPath "$TMP/relinkhooks"
UNTRACKEDRELINKED_REMOTE="$(git -C "$TMP/untrackedrelinked.git" rev-parse main)"
rigs_json untrackedrelinked
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null 2>&1
eq "$(git -C "$TMP/untrackedrelinked" rev-parse HEAD)" "$UNTRACKEDRELINKED_REMOTE" "a fast-forward whose kept copies move back under another name lands"
eq "$(cat "$TMP/untrackedrelinked/.beads/config.yaml" 2>/dev/null)/$(cat "$TMP/untrackedrelinked/.beads/metadata.json" 2>/dev/null)" "$GASCITY_CFG/meta" "a copy aside that is its path's own file under another name is not removed"

# untrackedstale: an earlier pass left a copy of config.yaml aside, and a file
# was written on its path since. The copy stays aside, and the keep refuses
# rather than overwrite it, naming where it waits.
untrack_rig untrackedstale '.beads/*'
gascity_writes untrackedstale
mkdir -p "$TMP/untrackedstale/.git/gc-toolkit-reconcile-kept/.beads"; echo older > "$TMP/untrackedstale/.git/gc-toolkit-reconcile-kept/.beads/config.yaml"
UNTRACKEDSTALE_HEAD="$(git -C "$TMP/untrackedstale" rev-parse HEAD)"
rigs_json untrackedstale
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null 2>&1
eq "$(git -C "$TMP/untrackedstale" rev-parse HEAD)" "$UNTRACKEDSTALE_HEAD" "a copy waiting aside for a path that holds a file again blocks the keep"
eq "$(cat "$TMP/untrackedstale/.beads/config.yaml" 2>/dev/null)" "$GASCITY_CFG" "the file on the path is left untouched"
eq "$(cat "$TMP/untrackedstale/.git/gc-toolkit-reconcile-kept/.beads/config.yaml" 2>/dev/null)" "older" "the copy waiting aside is left untouched"
eq "$(git -C "$TMP/untrackedstale" ls-files .beads/metadata.json)" ".beads/metadata.json" "the blocked keep leaves the other file tracked"
eq "$(esc_count untrackedstale)" "1" "a copy waiting aside that blocks the keep escalates"
body_has untrackedstale "an earlier pass's copy of it waits at .*/\.git/gc-toolkit-reconcile-kept/\.beads/config\.yaml" \
  && ok "the escalation names where the earlier copy waits" \
  || bad "the escalation names where the earlier copy waits (got '$(body_for untrackedstale)')"
body_has untrackedstale "^\.beads/config\.yaml waits at .*/untrackedstale/\.git/gc-toolkit-reconcile-kept/\.beads/config\.yaml: something else was written on " \
  && ok "a blocked keep's subject lists the copy waiting aside" \
  || bad "a blocked keep's subject lists the copy waiting aside (got '$(body_for untrackedstale)')"

# untrackedtree: the remote ignores and deletes the clean file cache but tracks
# cache/x in its place, and ignores a/b while turning its directory a into a
# file. Neither path can stay, so neither is kept: the checkout fast-forwards as
# plain git does, and no copy waits aside.
s="$TMP/untrackedtree.src"; git init -q -b main "$s"; mkdir -p "$s/a"
echo c > "$s/cache"; echo b > "$s/a/b"; git -C "$s" add -A; git -C "$s" commit -qm u1
git clone -q --bare "$s" "$TMP/untrackedtree.git"; git clone -q "$TMP/untrackedtree.git" "$TMP/untrackedtree"
printf 'cache\na/b\n' > "$s/.gitignore"; git -C "$s" rm -q cache a/b
mkdir -p "$s/cache"; echo x > "$s/cache/x"; echo a > "$s/a"
git -C "$s" add -f .gitignore cache/x a; git -C "$s" commit -qm u2
git -C "$s" push -q "$TMP/untrackedtree.git" main; git -C "$TMP/untrackedtree" fetch -q origin
UNTRACKEDTREE_REMOTE="$(git -C "$TMP/untrackedtree.git" rev-parse main)"
rigs_json untrackedtree
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null 2>&1
eq "$(git -C "$TMP/untrackedtree" rev-parse HEAD)" "$UNTRACKEDTREE_REMOTE" "a deleted path the remote writes under or above is not kept"
eq "$(cat "$TMP/untrackedtree/cache/x" 2>/dev/null)/$(cat "$TMP/untrackedtree/a" 2>/dev/null)" "x/a" "the fast-forward writes what the remote has there"
eq "$(kept_waiting untrackedtree)" "0" "no copy waits aside for a path the remote writes under or above"

# untrackedabsent: metadata.json's working copy is already gone, so there is
# nothing of it to keep, while config.yaml is kept and the checkout advances.
untrack_rig untrackedabsent '.beads/*'
rm -f "$TMP/untrackedabsent/.beads/metadata.json"
UNTRACKEDABSENT_REMOTE="$(git -C "$TMP/untrackedabsent.git" rev-parse main)"
rigs_json untrackedabsent
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/untrackedabsent" rev-parse HEAD)" "$UNTRACKEDABSENT_REMOTE" "a path with no working copy is not kept, and the checkout advances"
eq "$(cat "$TMP/untrackedabsent/.beads/config.yaml" 2>/dev/null)" "cfg" "the other file is kept"
eq "$(git -C "$TMP/untrackedabsent" status --porcelain)" "" "the path with no working copy ends untracked"

# untrackedcolon: the remote stops tracking and ignores a clean file whose name
# starts with a colon, which check-ignore would read as pathspec magic. The file
# is kept like any other.
s="$TMP/untrackedcolon.src"; git init -q -b main "$s"
echo x > "$s/:!x"; git -C "$s" add -A; git -C "$s" commit -qm u1
git clone -q --bare "$s" "$TMP/untrackedcolon.git"; git clone -q "$TMP/untrackedcolon.git" "$TMP/untrackedcolon"
printf '/:!x\n' > "$s/.gitignore"; git --literal-pathspecs -C "$s" rm -q --cached ':!x'
git -C "$s" add .gitignore; git -C "$s" commit -qm u2
git -C "$s" push -q "$TMP/untrackedcolon.git" main; git -C "$TMP/untrackedcolon" fetch -q origin
UNTRACKEDCOLON_REMOTE="$(git -C "$TMP/untrackedcolon.git" rev-parse main)"
rigs_json untrackedcolon
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/untrackedcolon" rev-parse HEAD)" "$UNTRACKEDCOLON_REMOTE" "a path whose name starts with a colon is read as a path, and the checkout advances"
eq "$(cat "$TMP/untrackedcolon/:!x" 2>/dev/null)" "x" "a file whose name starts with a colon is kept in place"
eq "$(git -C "$TMP/untrackedcolon" status --porcelain)" "" "the kept file whose name starts with a colon ends untracked and ignored"
eq "$(esc_count untrackedcolon)" "0" "keeping a file whose name starts with a colon is not escalated"

# leftoverdir: an interrupted pass left a copy of cfg aside, and a directory now
# sits on its path. The copy stays aside rather than land inside the directory,
# and the checkout still fast-forwards, but the rig stays escalated while the
# copy waits.
behind_rig leftoverdir
mkdir -p "$TMP/leftoverdir/.git/gc-toolkit-reconcile-kept" "$TMP/leftoverdir/cfg"; echo older > "$TMP/leftoverdir/.git/gc-toolkit-reconcile-kept/cfg"
LEFTOVERDIR_REMOTE="$(git -C "$TMP/leftoverdir.git" rev-parse main)"
rigs_json leftoverdir
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null 2>&1
eq "$(git -C "$TMP/leftoverdir" rev-parse HEAD)" "$LEFTOVERDIR_REMOTE" "a copy left aside does not stop a fast-forward that keeps nothing"
[ ! -e "$TMP/leftoverdir/cfg/cfg" ] && ok "a copy left aside never lands inside a directory on its path" || bad "a copy left aside never lands inside a directory on its path"
eq "$(cat "$TMP/leftoverdir/.git/gc-toolkit-reconcile-kept/cfg" 2>/dev/null)" "older" "a copy that cannot go back stays aside"
eq "$(esc_count leftoverdir)" "1" "a plain fast-forward escalates while a kept copy waits aside"
body_has leftoverdir "^This pass: rigs/leftoverdir fast-forwarded cleanly to origin/main\.$" \
  && ok "the subject says what the pass did" \
  || bad "the subject says what the pass did (got '$(body_for leftoverdir)')"
body_has leftoverdir "^cfg waits at .*/leftoverdir/\.git/gc-toolkit-reconcile-kept/cfg: something else was written on " \
  && ok "the subject names a copy that waits aside for a path a directory holds" \
  || bad "the subject names a copy that waits aside for a path a directory holds (got '$(body_for leftoverdir)')"
grep -q 'and the next pass puts the copy back' <<< "$(msg_for leftoverdir)" \
  && ok "the visit says how a person settles a copy waiting aside" \
  || bad "the visit says how a person settles a copy waiting aside (got '$(msg_for leftoverdir)')"

# churnleftover: an already-upstream SHA churn, with a copy of cfg an
# interrupted pass left aside while cfg holds a file again. The reset heal
# lands, and the rig stays escalated while the copy waits.
churned_rig churnleftover
echo theirs > "$TMP/churnleftover.src/new.txt"; push_churn churnleftover
mkdir -p "$TMP/churnleftover/.git/gc-toolkit-reconcile-kept"; echo older > "$TMP/churnleftover/.git/gc-toolkit-reconcile-kept/cfg"
echo newer > "$TMP/churnleftover/cfg"
CHURNLEFTOVER_REMOTE="$(git -C "$TMP/churnleftover.git" rev-parse main)"
rigs_json churnleftover
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null 2>&1
eq "$(git -C "$TMP/churnleftover" rev-parse HEAD)" "$CHURNLEFTOVER_REMOTE" "a copy left aside does not stop the reset heal"
eq "$(cat "$TMP/churnleftover/cfg")/$(cat "$TMP/churnleftover/.git/gc-toolkit-reconcile-kept/cfg" 2>/dev/null)" "newer/older" "the reset heal keeps both copies"
eq "$(esc_count churnleftover)" "1" "a reset heal escalates while a kept copy waits aside"
body_has churnleftover "^This pass: rigs/churnleftover auto-healed: already-upstream, reset to origin/main\.$" \
  && ok "the subject says the reset heal landed" \
  || bad "the subject says the reset heal landed (got '$(body_for churnleftover)')"

# divergedleftover: a genuine divergence, a local commit no ref holds, with a
# copy waiting aside. The reset heal stops, and the subject names both.
churned_rig divergedleftover
echo theirs > "$TMP/divergedleftover.src/new.txt"; push_churn divergedleftover
commit "$TMP/divergedleftover" local-only
mkdir -p "$TMP/divergedleftover/.git/gc-toolkit-reconcile-kept" "$TMP/divergedleftover/cfg"; echo older > "$TMP/divergedleftover/.git/gc-toolkit-reconcile-kept/cfg"
DIVERGEDLEFTOVER_HEAD="$(git -C "$TMP/divergedleftover" rev-parse HEAD)"
rigs_json divergedleftover
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null 2>&1
eq "$(git -C "$TMP/divergedleftover" rev-parse HEAD)" "$DIVERGEDLEFTOVER_HEAD" "a genuine divergence with a copy waiting aside is not reset"
body_has divergedleftover '^local commit not upstream: [0-9a-f]+ local-only$' \
  && ok "a diverged checkout's subject names what stopped the reset heal beside a copy waiting aside" \
  || bad "a diverged checkout's subject names what stopped the reset heal beside a copy waiting aside (got '$(body_for divergedleftover)')"
body_has divergedleftover "^cfg waits at .*/divergedleftover/\.git/gc-toolkit-reconcile-kept/cfg: something else was written on " \
  && ok "a diverged checkout's subject lists the copy waiting aside" \
  || bad "a diverged checkout's subject lists the copy waiting aside (got '$(body_for divergedleftover)')"

# leftoverabove: a copy waits for sub/cfg while a file sits at sub, so it cannot
# go back though nothing sits on its own path. The subject says so.
behind_rig leftoverabove
mkdir -p "$TMP/leftoverabove/.git/gc-toolkit-reconcile-kept/sub"; echo older > "$TMP/leftoverabove/.git/gc-toolkit-reconcile-kept/sub/cfg"
echo file > "$TMP/leftoverabove/sub"
rigs_json leftoverabove
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null 2>&1
eq "$(cat "$TMP/leftoverabove/.git/gc-toolkit-reconcile-kept/sub/cfg" 2>/dev/null)/$(cat "$TMP/leftoverabove/sub")" "older/file" "a copy that a file above its path keeps aside stays there, and the file stays"
body_has leftoverabove "^sub/cfg waits at .*/leftoverabove/\.git/gc-toolkit-reconcile-kept/sub/cfg: it could not go back on its path$" \
  && ok "the subject says a copy with nothing on its path could not go back" \
  || bad "the subject says a copy with nothing on its path could not go back (got '$(body_for leftoverabove)')"

# leftoverlink: a copy waits for cfg, and cfg is now a symlink to the copy
# itself, so the two read the same bytes. A symlink is no copy of the file, so
# the copy stays aside rather than be removed under the link.
behind_rig leftoverlink
mkdir -p "$TMP/leftoverlink/.git/gc-toolkit-reconcile-kept"; echo older > "$TMP/leftoverlink/.git/gc-toolkit-reconcile-kept/cfg"
ln -s .git/gc-toolkit-reconcile-kept/cfg "$TMP/leftoverlink/cfg"
rigs_json leftoverlink
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null 2>&1
eq "$(cat "$TMP/leftoverlink/.git/gc-toolkit-reconcile-kept/cfg" 2>/dev/null)" "older" "a copy whose path holds a symlink to its bytes stays aside"
eq "$(esc_count leftoverlink)" "1" "a copy whose path holds a symlink to its bytes escalates"

# leftoverlinkdir: an interrupted keep left config.yaml and metadata.json aside,
# and .beads is now a symlink to the directory where they wait, so each path
# reads its own copy. Removing a copy would take it from the runtime too, so
# both stay aside and the rig escalates. Once the symlink is removed, the next
# pass puts both copies back and keeps them.
untrack_rig leftoverlinkdir '.beads/*'
gascity_writes leftoverlinkdir
LEFTOVERLINKDIR_KEPT="$TMP/leftoverlinkdir/.git/gc-toolkit-reconcile-kept/.beads"
mkdir -p "$LEFTOVERLINKDIR_KEPT"
mv "$TMP/leftoverlinkdir/.beads/config.yaml" "$TMP/leftoverlinkdir/.beads/metadata.json" "$LEFTOVERLINKDIR_KEPT/"
rmdir "$TMP/leftoverlinkdir/.beads"; ln -s .git/gc-toolkit-reconcile-kept/.beads "$TMP/leftoverlinkdir/.beads"
LEFTOVERLINKDIR_REMOTE="$(git -C "$TMP/leftoverlinkdir.git" rev-parse main)"
rigs_json leftoverlinkdir
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null 2>&1
eq "$(cat "$LEFTOVERLINKDIR_KEPT/config.yaml" 2>/dev/null)/$(cat "$LEFTOVERLINKDIR_KEPT/metadata.json" 2>/dev/null)" "$GASCITY_CFG/meta" "copies their paths read through a symlinked directory stay aside unchanged"
eq "$(esc_count leftoverlinkdir)" "1" "copies their paths read through a symlinked directory escalate"
body_has leftoverlinkdir "^\.beads/config\.yaml waits at .*/leftoverlinkdir/\.git/gc-toolkit-reconcile-kept/\.beads/config\.yaml, and .*/leftoverlinkdir/\.beads/config\.yaml reads this copy itself through the symlink .*/leftoverlinkdir/\.beads: deleting or moving the copy takes it from the runtime too" \
  && ok "the subject says the path reads the copy itself through the symlink" \
  || bad "the subject says the path reads the copy itself through the symlink (got '$(body_for leftoverlinkdir)')"
rm "$TMP/leftoverlinkdir/.beads"
bash "$SCRIPT" >/dev/null 2>&1
eq "$(cat "$TMP/leftoverlinkdir/.beads/config.yaml" 2>/dev/null)/$(cat "$TMP/leftoverlinkdir/.beads/metadata.json" 2>/dev/null)" "$GASCITY_CFG/meta" "once the symlink is removed, the next pass puts both copies back"
eq "$(git -C "$TMP/leftoverlinkdir" rev-parse HEAD)" "$LEFTOVERLINKDIR_REMOTE" "once the symlink is removed, the copies are kept and the checkout advances"
eq "$(kept_waiting leftoverlinkdir)" "0" "once the symlink is removed, no copy waits aside"
eq "$(open_count leftoverlinkdir)" "0" "the subject closes once the copies are back"

# leftoverlinkaway: copies wait for d/sub/a and d/sub/b, and d/sub is now a
# symlink to a directory outside the checkout, which holds a file b with the
# copy's bytes. A copy never goes back through a symlinked directory, so a does
# not go there, the copy of b is not removed for the bytes found there, and the
# rig escalates.
behind_rig leftoverlinkaway
LEFTOVERLINKAWAY_KEPT="$TMP/leftoverlinkaway/.git/gc-toolkit-reconcile-kept/d/sub"
mkdir -p "$LEFTOVERLINKAWAY_KEPT" "$TMP/leftoverlinkaway/d" "$TMP/leftoverlinkaway.away"
echo a > "$LEFTOVERLINKAWAY_KEPT/a"; echo b > "$LEFTOVERLINKAWAY_KEPT/b"; echo b > "$TMP/leftoverlinkaway.away/b"
ln -s "$TMP/leftoverlinkaway.away" "$TMP/leftoverlinkaway/d/sub"
rigs_json leftoverlinkaway
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null 2>&1
eq "$(cat "$LEFTOVERLINKAWAY_KEPT/a" 2>/dev/null)/$(cat "$LEFTOVERLINKAWAY_KEPT/b" 2>/dev/null)" "a/b" "copies whose paths sit behind a symlinked directory stay aside"
[ ! -e "$TMP/leftoverlinkaway.away/a" ] && ok "a copy never goes back through a symlinked directory" || bad "a copy never goes back through a symlinked directory"
eq "$(esc_count leftoverlinkaway)" "1" "copies whose paths sit behind a symlinked directory escalate"
body_has leftoverlinkaway "^d/sub/b waits at .*/leftoverlinkaway/\.git/gc-toolkit-reconcile-kept/d/sub/b: .*/leftoverlinkaway/d/sub is a symlink, and a kept copy never goes back through one$" \
  && ok "the subject names the symlinked directory a copy does not go back through" \
  || bad "the subject names the symlinked directory a copy does not go back through (got '$(body_for leftoverlinkaway)')"

# leftoverlinkdeep: a copy waits for d/sub/a, and d/sub is now a symlink to the
# directory where it waits, while d is a plain directory. The path reads the copy
# itself through its own directory, not its top one, so the copy stays aside and
# its line says the path reads it.
behind_rig leftoverlinkdeep
LEFTOVERLINKDEEP_KEPT="$TMP/leftoverlinkdeep/.git/gc-toolkit-reconcile-kept/d/sub"
mkdir -p "$LEFTOVERLINKDEEP_KEPT" "$TMP/leftoverlinkdeep/d"; echo a > "$LEFTOVERLINKDEEP_KEPT/a"
ln -s ../.git/gc-toolkit-reconcile-kept/d/sub "$TMP/leftoverlinkdeep/d/sub"
rigs_json leftoverlinkdeep
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null 2>&1
eq "$(cat "$LEFTOVERLINKDEEP_KEPT/a" 2>/dev/null)" "a" "a copy its path reads through a symlinked subdirectory stays aside"
eq "$(esc_count leftoverlinkdeep)" "1" "a copy its path reads through a symlinked subdirectory escalates"
body_has leftoverlinkdeep "^d/sub/a waits at .*/leftoverlinkdeep/\.git/gc-toolkit-reconcile-kept/d/sub/a, and .*/leftoverlinkdeep/d/sub/a reads this copy itself through the symlink .*/leftoverlinkdeep/d/sub: " \
  && ok "the subject says a path below a symlinked subdirectory reads the copy itself" \
  || bad "the subject says a path below a symlinked subdirectory reads the copy itself (got '$(body_for leftoverlinkdeep)')"

# leftoverhardlink: a pass was interrupted between linking a copy and removing
# its first name, so cfg and the copy aside are one file under two names. The
# copy aside goes, cfg keeps the bytes, and nothing escalates.
behind_rig leftoverhardlink
echo older > "$TMP/leftoverhardlink/cfg"
mkdir -p "$TMP/leftoverhardlink/.git/gc-toolkit-reconcile-kept"; ln "$TMP/leftoverhardlink/cfg" "$TMP/leftoverhardlink/.git/gc-toolkit-reconcile-kept/cfg"
rigs_json leftoverhardlink
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null 2>&1
eq "$(cat "$TMP/leftoverhardlink/cfg" 2>/dev/null)" "older" "a path that is a second name of its copy keeps the bytes"
eq "$(kept_waiting leftoverhardlink)" "0" "a copy whose path is a second name of it does not wait aside"
eq "$(esc_count leftoverhardlink)" "0" "a copy whose path is a second name of it is not escalated"

# unreadablekept: part of the keep directory cannot be read, so nothing proves
# no copy waits there. The rig escalates though its fast-forward lands. Root
# reads the directory anyway, so the case needs another user.
if [ "$(id -u)" -eq 0 ]; then
  ok "an unreadable keep directory escalates (skipped: running as root)"
else
  behind_rig unreadablekept
  mkdir -p "$TMP/unreadablekept/.git/gc-toolkit-reconcile-kept/locked"; echo older > "$TMP/unreadablekept/.git/gc-toolkit-reconcile-kept/locked/cfg"
  chmod 000 "$TMP/unreadablekept/.git/gc-toolkit-reconcile-kept/locked"
  UNREADABLEKEPT_REMOTE="$(git -C "$TMP/unreadablekept.git" rev-parse main)"
  rigs_json unreadablekept
  : > "$TMP/escalations"
  bash "$SCRIPT" >/dev/null 2>&1
  chmod 755 "$TMP/unreadablekept/.git/gc-toolkit-reconcile-kept/locked"
  eq "$(git -C "$TMP/unreadablekept" rev-parse HEAD)" "$UNREADABLEKEPT_REMOTE" "an unreadable keep directory does not stop the fast-forward"
  eq "$(esc_count unreadablekept)" "1" "an unreadable keep directory escalates"
  body_has unreadablekept "^could not list the kept copies waiting under .*/unreadablekept/\.git/gc-toolkit-reconcile-kept$" \
    && ok "the subject says the keep directory could not be listed" \
    || bad "the subject says the keep directory could not be listed (got '$(body_for unreadablekept)')"
fi

# parkedleftover: a parked checkout with a copy waiting aside. Its subject
# names the copy beside the parked HEAD, and its visit says a copy waits.
behind_rig parkedleftover
git -C "$TMP/parkedleftover" checkout -q -b feature
mkdir -p "$TMP/parkedleftover/.git/gc-toolkit-reconcile-kept"; echo older > "$TMP/parkedleftover/.git/gc-toolkit-reconcile-kept/cfg"
mkdir -p "$TMP/parkedleftover/cfg"
rigs_json parkedleftover
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null 2>&1
eq "$(esc_count parkedleftover)" "1" "a parked checkout with a copy waiting aside escalates once"
body_has parkedleftover "^cfg waits at .*/parkedleftover/\.git/gc-toolkit-reconcile-kept/cfg: something else was written on " \
  && ok "a parked checkout's subject names the copy waiting aside" \
  || bad "a parked checkout's subject names the copy waiting aside (got '$(body_for parkedleftover)')"
grep -q 'A kept copy also waits under .*/parkedleftover/\.git/gc-toolkit-reconcile-kept' <<< "$(msg_for parkedleftover)" \
  && ok "a parked checkout's visit says a kept copy waits aside" \
  || bad "a parked checkout's visit says a kept copy waits aside (got '$(msg_for parkedleftover)')"

# untrackedunread: the read of the remote's .gitignore files fails, so nothing
# proves the clean files are not kept paths. The fast-forward, which would
# delete them, does not run, and the stall escalates.
untrack_rig untrackedunread '.beads/*'
UNTRACKEDUNREAD_HEAD="$(git -C "$TMP/untrackedunread" rev-parse HEAD)"
rigs_json untrackedunread
: > "$TMP/escalations"
TMPDIR="$TMP/absent" bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/untrackedunread" rev-parse HEAD)" "$UNTRACKEDUNREAD_HEAD" "a failed read of the kept paths stops the fast-forward"
eq "$(cat "$TMP/untrackedunread/.beads/metadata.json" 2>/dev/null)" "meta" "a failed read of the kept paths deletes nothing"
eq "$(esc_count untrackedunread)" "1" "a failed read of the kept paths escalates"
body_has untrackedunread "^could not make a scratch repository to read the remote's \.gitignore files$" \
  && ok "the escalation says the read failed" \
  || bad "the escalation says the read failed (got '$(body_for untrackedunread)')"

# untrackedunreadstray: the same failed read, with a stray write of f.txt that
# the set-aside could heal. The set-aside does not run either, since its
# fast-forward would delete the clean files the read could not judge.
untrack_rig untrackedunreadstray '.beads/*'
echo upstream > "$TMP/untrackedunreadstray/f.txt"
UNTRACKEDUNREADSTRAY_HEAD="$(git -C "$TMP/untrackedunreadstray" rev-parse HEAD)"
rigs_json untrackedunreadstray
: > "$TMP/escalations"
TMPDIR="$TMP/absent" bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/untrackedunreadstray" rev-parse HEAD)" "$UNTRACKEDUNREADSTRAY_HEAD" "a failed read of the kept paths stops the set-aside heal too"
eq "$(git -C "$TMP/untrackedunreadstray" ls-files .beads/metadata.json)" ".beads/metadata.json" "a failed read of the kept paths leaves the clean files tracked when a stray write blocks the fast-forward"
body_has untrackedunreadstray "^could not make a scratch repository to read the remote's \.gitignore files$" \
  && ok "the escalation names the failed read, not the stray write" \
  || bad "the escalation names the failed read, not the stray write (got '$(body_for untrackedunreadstray)')"

# untrackednoheal: RECONCILE_NO_AUTOHEAL=1 turns the keep off, so the
# fast-forward runs as plain git and deletes the clean files.
untrack_rig untrackednoheal '.beads/*'
UNTRACKEDNOHEAL_REMOTE="$(git -C "$TMP/untrackednoheal.git" rev-parse main)"
rigs_json untrackednoheal
: > "$TMP/escalations"
RECONCILE_NO_AUTOHEAL=1 bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/untrackednoheal" rev-parse HEAD)" "$UNTRACKEDNOHEAL_REMOTE" "RECONCILE_NO_AUTOHEAL fast-forwards over a path the remote stops tracking"
[ ! -e "$TMP/untrackednoheal/.beads/metadata.json" ] && ok "RECONCILE_NO_AUTOHEAL keeps nothing in place" || bad "RECONCILE_NO_AUTOHEAL keeps nothing in place"

# No subject bead or visit message this suite filed tells a person to run a
# reset that overwrites what is in its way.
RESET_TOLD="$(grep -l -E 'reset --(hard|keep)' "$TMP"/ledger.*.body "$TMP"/escalations.*.msg 2>/dev/null || true)"
eq "$RESET_TOLD" "" "no escalation tells a person to run git reset --hard or --keep"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
