#!/usr/bin/env bash
# Hermetic test for reconcile-rig-checkouts.sh.
#
# Uses real temp git repos as stand-in rigs, a fake `gc` (a text-file bead
# ledger) and a fake escalate.sh (a call recorder) on PATH. No dependency on
# the live city, Dolt, an agent, or the network. Covers: (a) a clean-behind rig
# advances; (b) a diverged rig is NOT mutated and files exactly one reconcile
# bead; (c) a re-run does not duplicate that bead; (d) the bead auto-closes once
# the rig ff-s cleanly; (e) the HQ root is excluded; (f) a divergence is raised
# through escalate.sh, an advanced/HQ rig is not, and a recovered rig is not
# re-escalated; (g) a configured pool that does not route falls back to the
# human board; (h) an already-upstream divergence (SHA churn) auto-heals via
# reset --hard while a genuine divergence still escalates, RECONCILE_NO_AUTOHEAL
# disables the heal, and a dirty tracked file blocks it only when its content is
# not yet upstream; (i) a unique local merge commit (invisible to git cherry)
# fails the guard closed and escalates rather than being reset away; (j) an
# unreadable git status fails the guard closed rather than healing on an
# unproven-clean tree; (k) a path staged with local-only content whose worktree
# copy matches the remote fails the guard closed, so reset --hard cannot discard
# the staged content.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/reconcile-rig-checkouts.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-reconcile-rig-checkouts-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()   { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

commit() { echo "$2" > "$1/f.txt"; git -C "$1" add -A; git -C "$1" commit -qm "$2"; }
# count OPEN reconcile beads in the fake ledger for a given rig key.
open_count() { awk -F'|' -v k="$1" '$2==k && $3=="open"' "$TMP/ledger" 2>/dev/null | wc -l | tr -d ' '; }
# id of the OPEN reconcile bead for a rig key (empty if none).
bead_for()   { awk -F'|' -v k="$1" '$2==k && $3=="open"{print $1; exit}' "$TMP/ledger" 2>/dev/null; }
# escalate.sh calls recorded for a rig key, and the subject/pool of the first/last.
esc_count()   { awk -F'|' -v k="reconcile-diverged-$1" '$1==k' "$TMP/escalations" 2>/dev/null | wc -l | tr -d ' '; }
esc_subject() { awk -F'|' -v k="reconcile-diverged-$1" '$1==k{print $2; exit}' "$TMP/escalations" 2>/dev/null; }
esc_last_pool() { awk -F'|' -v k="reconcile-diverged-$1" '$1==k{p=$3} END{print p}' "$TMP/escalations" 2>/dev/null; }

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
  {"name":"loomington","path":"$TMP/hqrepo","hq":true},
  {"name":"alpha","path":"$TMP/alpha"},
  {"name":"beta","path":"$TMP/beta"}
]}
JSON
: > "$TMP/ledger"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
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
        printf '%s||open\n' "$id" >> "$FAKE_LEDGER"; printf '{"id":"%s"}\n' "$id" ;;
      update)
        id="$1"; shift; key=""
        while [ $# -gt 0 ]; do [ "$1" = "--set-metadata" ] && key="${2#reconcile_rig=}"; shift; done
        [ -n "$key" ] && sed -i "s/^${id}|[^|]*|/${id}|${key}|/" "$FAKE_LEDGER" ;;
      close) sed -i "s/^\($1\)|\([^|]*\)|open/\1|\2|closed/" "$FAKE_LEDGER" ;;
    esac ;;
  session) : ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

# Fake escalate.sh: record each call as `<key>|<subject>|<pool>` and, so the
# pool->human fallback can be exercised, exit non-zero for a pool named in
# FAKE_BAD_POOL — exactly as the real escalate.sh exits non-zero on a route no
# live agent claims.
cat > "$TMP/bin/escalate.sh" <<'ESC'
#!/usr/bin/env bash
subject=""; key=""; pool=""
while [ $# -gt 0 ]; do
  case "$1" in
    --subject) subject="${2:-}"; shift 2;;
    --key)     key="${2:-}";     shift 2;;
    --message) shift 2;;
    --pool)    pool="${2:-}";    shift 2;;
    *) shift;;
  esac
done
printf '%s|%s|%s\n' "$key" "$subject" "$pool" >> "$FAKE_ESCALATIONS"
[ -n "$pool" ] && [ "$pool" = "${FAKE_BAD_POOL:-}" ] && exit 1
exit 0
ESC
chmod +x "$TMP/bin/escalate.sh"

export PATH="$TMP/bin:$PATH" FAKE_RIGS_JSON="$TMP/rigs.json" FAKE_LEDGER="$TMP/ledger"
export GC_RECONCILE_ESCALATE_TOOL="$TMP/bin/escalate.sh" FAKE_ESCALATIONS="$TMP/escalations"
: > "$TMP/escalations"

# --- Run 1: alpha advances, beta escalates, hq is skipped. -------------------
bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/alpha" rev-parse HEAD)" "$REMOTE_HEAD" "clean-behind rig advances to origin"
eq "$(git -C "$TMP/beta"  rev-parse HEAD)" "$BETA_DIVERGED" "diverged rig is not mutated"
grep -q c3-local < <(git -C "$TMP/beta" log --oneline) && ok "diverged rig keeps local commit" || bad "diverged rig keeps local commit"
eq "$(open_count beta)"  "1" "diverged rig files exactly one reconcile bead"
eq "$(open_count alpha)" "0" "advanced rig files no reconcile bead"
eq "$(open_count loomington)" "0" "HQ root is excluded (not reconciled)"

# The divergence is raised through escalate.sh, on the reconcile bead as subject;
# an advanced or HQ rig raises nothing.
eq "$(esc_count beta)"  "1" "diverged rig is escalated through escalate.sh"
eq "$(esc_subject beta)" "$(bead_for beta)" "escalation subject is the reconcile bead"
eq "$(esc_last_pool beta)" "" "default escalation names no pool (human helm board)"
eq "$(esc_count alpha)" "0" "advanced rig is not escalated"
eq "$(esc_count loomington)" "0" "HQ root is not escalated"

# --- Run 2: idempotent — no duplicate reconcile bead. ------------------------
# escalate.sh is called again (it dedups the visit on its own side, proven in
# its own test); the reconcile bead must not be duplicated.
bash "$SCRIPT" >/dev/null
eq "$(open_count beta)" "1" "re-run does not duplicate the reconcile bead"

# --- Run 3: rig resolved -> bead auto-closes, no fresh escalation. -----------
BETA_ESC_BEFORE="$(esc_count beta)"
git -C "$TMP/beta" reset --hard -q origin/main
bash "$SCRIPT" >/dev/null
eq "$(open_count beta)" "0" "reconcile bead auto-closes after a clean fast-forward"
eq "$(esc_count beta)" "$BETA_ESC_BEFORE" "a recovered rig is not re-escalated"

# --- Run 4: a configured pool that does not route falls back to human. -------
git -C "$TMP/beta" reset --hard -q "$BETA_DIVERGED"    # re-diverge beta
: > "$TMP/escalations"
RECONCILE_ESCALATION_POOL="rig/absent.pool" FAKE_BAD_POOL="rig/absent.pool" \
  bash "$SCRIPT" >/dev/null
eq "$(esc_count beta)" "2" "an unroutable pool triggers a second, fallback escalate call"
eq "$(esc_last_pool beta)" "" "the fallback escalation carries no pool (human helm board)"

# ===========================================================================
# Auto-heal an already-upstream divergence (SHA churn from a rebase/squash/
# force-push): reset --hard is lossless, so the checkout re-syncs without a
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
echo keep-me > "$TMP/gamma/untracked.txt"                        # untracked; reset --hard must keep it

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
  {"name":"loomington","path":"$TMP/hqrepo","hq":true},
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

# Now with auto-heal enabled (default): gamma resets --hard to origin, keeps its
# untracked file, closes the bead the escape-hatch run filed, and is not
# re-escalated; delta's genuine divergence still escalates and is not mutated.
GAMMA_ESC_BEFORE="$(esc_count gamma)"
OUT="$(bash "$SCRIPT")"
eq "$(git -C "$TMP/gamma" rev-parse HEAD)" "$GAMMA_REMOTE" "already-upstream rig is reset --hard to origin"
[ -f "$TMP/gamma/untracked.txt" ] && ok "auto-heal preserves untracked files" || bad "auto-heal preserves untracked files"
eq "$(open_count gamma)" "0" "auto-heal closes the open reconcile bead"
eq "$(esc_count gamma)" "$GAMMA_ESC_BEFORE" "auto-healed rig is not re-escalated"
grep -q '1 auto-healed' <<< "$OUT" && ok "summary line reports the auto-heal count" || bad "summary line reports the auto-heal count (got '$OUT')"
eq "$(git -C "$TMP/delta" rev-parse HEAD)" "$DELTA_DIVERGED" "a genuine unique-commit divergence is not mutated"
eq "$(open_count delta)" "1" "a genuine unique-commit divergence keeps its reconcile bead"

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
  {"name":"loomington","path":"$TMP/hqrepo","hq":true},
  {"name":"epsilon","path":"$TMP/epsilon"}
]}
JSON
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/epsilon" rev-parse HEAD)" "$EPS_HEAD" "a dirty tracked change not upstream blocks the heal"
eq "$(esc_count epsilon)" "1" "a dirty tracked change not upstream escalates"
eq "$(cat "$TMP/epsilon/f.txt")" "local-wip" "the un-upstreamed dirty change is left untouched"

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
  {"name":"loomington","path":"$TMP/hqrepo","hq":true},
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
  {"name":"loomington","path":"$TMP/hqrepo","hq":true},
  {"name":"eta","path":"$TMP/eta"}
]}
JSON
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/eta" rev-parse HEAD)" "$ETA_LOCAL" "a unique local merge commit blocks the heal (git cherry ignores merges)"
eq "$(esc_count eta)" "1" "a unique local merge commit escalates"
[ -f "$TMP/eta/evil.txt" ] && ok "the merge commit's unique tree content is preserved" || bad "the merge commit's unique tree content is preserved"

# theta: an already-upstream SHA churn where git status cannot be read. An
# unreadable status is not proof of a clean tree, so the dirty-tracked proof must
# fail closed and escalate rather than reset --hard. A git shim on PATH fails
# `git status` and passes every other subcommand through to real git.
git init -q -b main "$TMP/theta.src"; commit "$TMP/theta.src" th1; commit "$TMP/theta.src" th2
git clone -q --bare "$TMP/theta.src" "$TMP/theta.git"
git clone -q "$TMP/theta.git" "$TMP/theta"
THETA_HEAD="$(git -C "$TMP/theta" rev-parse HEAD)"
git -C "$TMP/theta.src" commit -q --amend --no-edit --date "2020-01-01T00:00:00"  # SHA churn: ff refuses, cherry clean
git -C "$TMP/theta.src" push -qf "$TMP/theta.git" main

cat > "$TMP/rigs.json" <<JSON
{"rigs":[
  {"name":"loomington","path":"$TMP/hqrepo","hq":true},
  {"name":"theta","path":"$TMP/theta"}
]}
JSON
: > "$TMP/escalations"
REAL_GIT="$(PATH="${PATH#"$TMP/bin:"}" command -v git)"
cat > "$TMP/bin/git" <<GITSHIM
#!/usr/bin/env bash
for a in "\$@"; do [ "\$a" = "status" ] && exit 128; done
exec "$REAL_GIT" "\$@"
GITSHIM
chmod +x "$TMP/bin/git"
bash "$SCRIPT" >/dev/null
rm -f "$TMP/bin/git"
eq "$(git -C "$TMP/theta" rev-parse HEAD)" "$THETA_HEAD" "an unreadable git status blocks the heal (fail closed)"
eq "$(esc_count theta)" "1" "an unreadable git status escalates instead of healing"

# iota: an already-upstream SHA churn PLUS a tracked path staged with local-only
# content whose worktree copy was then restored to the upstream bytes. git status
# reports it (MM f.txt), but the per-file worktree diff against the remote is
# empty, so a worktree-only proof counts it clean and reset --hard would discard
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
  {"name":"loomington","path":"$TMP/hqrepo","hq":true},
  {"name":"iota","path":"$TMP/iota"}
]}
JSON
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/iota" rev-parse HEAD)" "$IOTA_LOCAL" "staged local-only content (hidden by an upstream-matching worktree) blocks the heal"
eq "$(esc_count iota)" "1" "staged local-only content escalates instead of healing"
eq "$(git -C "$TMP/iota" show :f.txt)" "staged-local-only" "the staged local-only content is left untouched"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
