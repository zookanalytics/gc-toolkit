#!/usr/bin/env bash
# Hermetic test for reconcile-rig-checkouts.sh.
#
# Uses real temp git repos as stand-in rigs, a fake `gc` (a text-file bead
# ledger) and a fake human-gate.sh (a call recorder) on PATH. No dependency on
# the live city, Dolt, an agent, or the network. Covers: (a) a rig only behind
# its remote advances; (b) a diverged rig is NOT mutated, files exactly one
# reconcile bead that names what git refused, and is put to a person through
# human-gate.sh with a declared quiet window, while an advanced or HQ rig is
# not; (c) a re-run does not duplicate that bead; (d) the bead auto-closes once
# the rig fast-forwards cleanly, and its human gate is withdrawn as moot through
# human-gate.sh --retract in the same pass, with no fresh gate filed; (e) the
# HQ root is excluded; (f) a rig that blocks again after a clean sync files on
# a new subject bead; (g) the reset a diverged rig's bead hands a person
# refuses while an untracked or ignored file is in its way, and resets the
# checkout once it is cleared; (h) a rig only behind whose fast-forward git
# refuses, over a local change on a path the incoming commits rewrite, over an
# untracked or ignored file in their way, a copy of the incoming bytes
# included, or over a modified copy of a file they delete, is NOT mutated and
# escalates once, then recovers as in (d) and keeps a local change the
# fast-forward does not touch, while a clean copy of a file the incoming
# commits delete leaves with them; (i) a rig parked off the default branch is
# escalated once, left untouched and not counted advanced, and recovers as in
# (d) once back on it; (j) a recovered rig whose gate withdrawal fails keeps
# its subject open until a later withdrawal succeeds; (k) a rig whose fetch
# fails is skipped, with nothing touched or filed; (l) no escalation tells a
# person to run git reset --hard or --keep.
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
rigs_json() { # names... -> the rig list holds the HQ root plus these rigs
  local n
  { printf '{"rigs":[\n  {"name":"mycity","path":"%s","hq":true}' "$TMP/hqrepo"
    for n in "$@"; do printf ',\n  {"name":"%s","path":"%s"}' "$n" "$TMP/$n"; done
    printf '\n]}\n'; } > "$TMP/rigs.json"
}
# behind_rig NAME -> a clone on b1 of a remote whose main is b2. b1 tracks
# f.txt, cfg.txt and old.txt. b2 rewrites f.txt, deletes old.txt and adds
# new.txt holding "incoming".
behind_rig() {
  local s="$TMP/$1.src"
  git init -q -b main "$s"
  echo base > "$s/f.txt"; echo cfg > "$s/cfg.txt"; echo old > "$s/old.txt"
  git -C "$s" add -A; git -C "$s" commit -qm b1
  git clone -q --bare "$s" "$TMP/$1.git"
  git clone -q "$TMP/$1.git" "$TMP/$1"
  echo upstream > "$s/f.txt"; echo incoming > "$s/new.txt"; git -C "$s" rm -q old.txt
  git -C "$s" add -A; git -C "$s" commit -qm b2
  git -C "$s" push -q "$TMP/$1.git" main
}

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
rigs_json alpha beta
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
RUN1_OUT="$(bash "$SCRIPT")"
eq "$(git -C "$TMP/alpha" rev-parse HEAD)" "$REMOTE_HEAD" "clean-behind rig advances to origin"
eq "$(git -C "$TMP/beta"  rev-parse HEAD)" "$BETA_DIVERGED" "diverged rig is not mutated"
grep -q c3-local < <(git -C "$TMP/beta" log --oneline) && ok "diverged rig keeps local commit" || bad "diverged rig keeps local commit"
eq "$(open_count beta)"  "1" "diverged rig files exactly one reconcile bead"
eq "$(open_count alpha)" "0" "advanced rig files no reconcile bead"
eq "$(open_count mycity)" "0" "HQ root is excluded (not reconciled)"
eq "$RUN1_OUT" "reconcile-rig-checkouts: 1 advanced, 1 blocked" "the summary line counts the advanced and the blocked rigs"

# The divergence is put to a person through human-gate.sh, on the reconcile bead
# as subject; an advanced or HQ rig files nothing.
eq "$(esc_count beta)"  "1" "diverged rig files a human gate through human-gate.sh"
eq "$(esc_subject beta)" "$(bead_for beta)" "the gate's subject is the reconcile bead"
eq "$(esc_last_window beta)" "86400" "the call declares a day-long quiet window, since every pass detects the blocked rig again"
eq "$(esc_count alpha)" "0" "advanced rig files no gate"
eq "$(esc_count mycity)" "0" "HQ root files no gate"
# A still-diverged rig's gate stays open: nothing is withdrawn while the
# subject is unresolved.
eq "$(retract_count beta)" "0" "a still-diverged rig withdraws no gate"
eq "$(title_for beta)" "Reconcile: rigs/beta cannot fast-forward to origin/main" "the reconcile bead's title names the rig and the remote"
body_has beta '^fatal: Not possible to fast-forward, aborting\.$' \
  && ok "the diverged escalation names what git refused" \
  || bad "the diverged escalation names what git refused (got '$(body_for beta)')"
body_has beta '^hint:' && bad "the diverged escalation leaves out git's advice to merge or rebase" \
  || ok "the diverged escalation leaves out git's advice to merge or rebase"
body_has beta '^[0-9a-f]+ c3-local$' \
  && ok "the diverged escalation lists the local commit" \
  || bad "the diverged escalation lists the local commit (got '$(body_for beta)')"
grep -q "Subject bead $(bead_for beta) names what git refused and the steps to reset by hand" <<< "$(msg_for beta)" \
  && ok "the diverged gate's message points at its subject bead" \
  || bad "the diverged gate's message points at its subject bead (got '$(msg_for beta)')"

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

# --- The reset a diverged rig's bead hands a person. -------------------------
# The remote adds added.txt while beta holds an untracked added.txt of its own.
# The reset refuses while that file is in its way, also once beta ignores it,
# and resets beta to the remote once the file is moved aside.
echo theirs > "$SRC/added.txt"; git -C "$SRC" add added.txt; git -C "$SRC" commit -qm added
git -C "$SRC" push -q "$TMP/remote.git" main
REMOTE_HEAD="$(git -C "$TMP/remote.git" rev-parse main)"
echo mine > "$TMP/beta/added.txt"
bash "$SCRIPT" >/dev/null
read -r -a REMEDY <<< "$(remedy_for beta)"
eq "${REMEDY[*]:-}" "git -C $TMP/beta checkout --no-overwrite-ignore -B main origin/main" \
  "the diverged rig's bead hands a person a checkout that refuses rather than overwrites"
eq "$(remedy_rc)" "1" "the reset refuses while an untracked file is in its way"
eq "$(cat "$TMP/beta/added.txt")" "mine" "the refused reset leaves the untracked file as it was"
echo added.txt >> "$TMP/beta/.git/info/exclude"
eq "$(remedy_rc)" "1" "the reset refuses while an ignored file is in its way"
eq "$(cat "$TMP/beta/added.txt")" "mine" "the refused reset leaves the ignored file as it was"
mv "$TMP/beta/added.txt" "$TMP/beta-added.txt"
eq "$(remedy_rc)" "0" "the reset runs once the file in its way is moved aside"
eq "$(git -C "$TMP/beta" rev-parse HEAD)" "$REMOTE_HEAD" "the reset puts the checkout on the remote"
BETA_BEAD="$(bead_for beta)"
: > "$TMP/retractions"
bash "$SCRIPT" >/dev/null
eq "$(open_count beta)" "0" "the next pass closes the bead of a rig reset by hand"
eq "$(retract_subject beta)" "$BETA_BEAD" "the next pass withdraws the gate of a rig reset by hand"

# --- A rig only behind whose fast-forward git refuses. ----------------------
# mu holds a local change on f.txt, which the incoming commits rewrite, and on
# cfg.txt, which they do not touch.
behind_rig mu
echo machine-local > "$TMP/mu/cfg.txt"
echo local-edit > "$TMP/mu/f.txt"
MU_HEAD="$(git -C "$TMP/mu" rev-parse HEAD)"
MU_REMOTE="$(git -C "$TMP/mu.git" rev-parse main)"
rigs_json mu
: > "$TMP/escalations"; : > "$TMP/retractions"
MU_OUT="$(bash "$SCRIPT")"
eq "$(git -C "$TMP/mu" rev-parse HEAD)" "$MU_HEAD" "a refused fast-forward leaves the checkout where it was"
eq "$(cat "$TMP/mu/f.txt")" "local-edit" "a refused fast-forward keeps the local change on the path it rewrites"
eq "$(esc_count mu)" "1" "a refused fast-forward escalates once"
eq "$(open_count mu)" "1" "a refused fast-forward files one reconcile bead"
eq "$MU_OUT" "reconcile-rig-checkouts: 0 advanced, 1 blocked" "a refused fast-forward counts as blocked"
body_has mu '^error: Your local changes to the following files would be overwritten by merge:$' \
  && body_has mu '^  f\.txt$' \
  && ok "the escalation names what git refused and the path it named" \
  || bad "the escalation names what git refused and the path it named (got '$(body_for mu)')"
body_has mu '^Please ' && bad "the escalation leaves out git's advice to commit or stash" \
  || ok "the escalation leaves out git's advice to commit or stash"
grep -q 'though it is only behind it' <<< "$(msg_for mu)" \
  && ok "the gate's message says the rig is only behind" \
  || bad "the gate's message says the rig is only behind (got '$(msg_for mu)')"
bash "$SCRIPT" >/dev/null
eq "$(open_count mu)" "1" "a refused fast-forward does not duplicate its bead on the next pass"
eq "$(retract_count mu)" "0" "a still-refused rig withdraws no gate"
MU_BEAD="$(bead_for mu)"
git -C "$TMP/mu" restore --source=HEAD --staged --worktree -- f.txt
bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/mu" rev-parse HEAD)" "$MU_REMOTE" "once the stray write is restored the rig fast-forwards"
eq "$(cat "$TMP/mu/cfg.txt")" "machine-local" "the fast-forward keeps a local change on a path it does not touch"
eq "$(open_count mu)" "0" "the recovered rig's bead closes"
eq "$(retract_count mu)" "1" "the recovered rig's gate is withdrawn once"
eq "$(retract_subject mu)" "$MU_BEAD" "the withdrawal names the recovered rig's bead"

# xi holds an untracked copy of the incoming new.txt, byte for byte; omicron an
# ignored new.txt of its own; pi a modified copy of old.txt, which the incoming
# commits delete; sigma a clean copy of old.txt.
for r in xi omicron pi sigma; do behind_rig "$r"; done
echo incoming > "$TMP/xi/new.txt"
echo machine-local > "$TMP/omicron/new.txt"; echo new.txt >> "$TMP/omicron/.git/info/exclude"
echo machine-local > "$TMP/pi/old.txt"
XI_HEAD="$(git -C "$TMP/xi" rev-parse HEAD)"
OMICRON_HEAD="$(git -C "$TMP/omicron" rev-parse HEAD)"
PI_HEAD="$(git -C "$TMP/pi" rev-parse HEAD)"
SIGMA_REMOTE="$(git -C "$TMP/sigma.git" rev-parse main)"
rigs_json xi omicron pi sigma
: > "$TMP/escalations"
bash "$SCRIPT" >/dev/null
eq "$(git -C "$TMP/xi" rev-parse HEAD)" "$XI_HEAD" "an untracked copy of the incoming bytes still refuses the fast-forward"
eq "$(cat "$TMP/xi/new.txt")" "incoming" "the untracked copy stays where it is"
eq "$(esc_count xi)" "1" "an untracked file in the way escalates once"
body_has xi '^error: The following untracked working tree files would be overwritten by merge:$' \
  && body_has xi '^  new\.txt$' \
  && ok "the escalation names the untracked file in the way" \
  || bad "the escalation names the untracked file in the way (got '$(body_for xi)')"
eq "$(git -C "$TMP/omicron" rev-parse HEAD)" "$OMICRON_HEAD" "an ignored file in the way refuses the fast-forward"
eq "$(cat "$TMP/omicron/new.txt")" "machine-local" "the fast-forward never overwrites an ignored file"
eq "$(esc_count omicron)" "1" "an ignored file in the way escalates once"
body_has omicron '^  new\.txt$' \
  && ok "the escalation names the ignored file in the way" \
  || bad "the escalation names the ignored file in the way (got '$(body_for omicron)')"
eq "$(git -C "$TMP/pi" rev-parse HEAD)" "$PI_HEAD" "a modified copy of a file the incoming commits delete refuses the fast-forward"
eq "$(cat "$TMP/pi/old.txt")" "machine-local" "the modified copy stays as it is"
eq "$(esc_count pi)" "1" "a modified copy of a deleted file escalates once"
eq "$(git -C "$TMP/sigma" rev-parse HEAD)" "$SIGMA_REMOTE" "a clean copy of a file the incoming commits delete does not stop the fast-forward"
[ ! -e "$TMP/sigma/old.txt" ] && ok "the clean copy leaves the working tree with the commits that delete it" \
  || bad "the clean copy leaves the working tree with the commits that delete it"
eq "$(esc_count sigma)" "0" "a rig the fast-forward advances files no gate"

# --- A rig parked off the default branch. ----------------------------------
# kappa: an agent checked out an integration branch in the rig root and left a
# seed commit on it, ahead of origin/main. `merge --ff-only origin/main`
# reports "Already up to date", so a HEAD-blind reconciler counts it advanced;
# the parked-off-default check must surface it instead, mutating nothing.
git init -q -b main "$TMP/kappa.src"; commit "$TMP/kappa.src" k1; commit "$TMP/kappa.src" k2
git clone -q --bare "$TMP/kappa.src" "$TMP/kappa.git"
git clone -q "$TMP/kappa.git" "$TMP/kappa"                       # on main == origin/main
git -C "$TMP/kappa" checkout -q -b integration/seed origin/main  # park off the default branch
echo seed > "$TMP/kappa/seed.txt"; git -C "$TMP/kappa" add -A; git -C "$TMP/kappa" commit -qm seed
KAPPA_PARKED="$(git -C "$TMP/kappa" rev-parse HEAD)"
rigs_json kappa
: > "$TMP/escalations"; : > "$TMP/retractions"
KAPPA_OUT="$(bash "$SCRIPT")"
eq "$(git -C "$TMP/kappa" rev-parse HEAD)" "$KAPPA_PARKED" "a rig parked off the default branch is not mutated"
eq "$(git -C "$TMP/kappa" symbolic-ref --short HEAD)" "integration/seed" "a parked rig is left on its branch, not force-moved"
eq "$(esc_count kappa)" "1" "a rig parked off the default branch is escalated"
eq "$(open_count kappa)" "1" "a rig parked off the default branch files a reconcile bead"
eq "$KAPPA_OUT" "reconcile-rig-checkouts: 0 advanced, 1 blocked" "a parked rig is not counted as advanced"
body_has kappa '^rigs/kappa is parked off main — its live checkout HEAD is on integration/seed\.$' \
  && ok "the parked escalation names the branch the HEAD is on" \
  || bad "the parked escalation names the branch the HEAD is on (got '$(body_for kappa)')"
bash "$SCRIPT" >/dev/null
eq "$(open_count kappa)" "1" "a parked rig does not duplicate its bead on the next pass"
KAPPA_BEAD="$(bead_for kappa)"
git -C "$TMP/kappa" checkout -q main
bash "$SCRIPT" >/dev/null
eq "$(open_count kappa)" "0" "a rig back on its default branch closes its bead"
eq "$(retract_count kappa)" "1" "a rig back on its default branch has its gate withdrawn once"
eq "$(retract_subject kappa)" "$KAPPA_BEAD" "the withdrawal names the parked rig's bead"

# --- A recovered rig whose gate withdrawal fails. ----------------------------
# lambda must keep its reconcile subject OPEN. open_bead lists open beads only
# (no --all), so the subject is the only handle the next patrol has to retry the
# withdrawal; closing it after a failed one would strand a gate nobody can
# withdraw. A later pass whose withdrawal succeeds closes it.
git init -q -b main "$TMP/lambda.src"; commit "$TMP/lambda.src" l1; commit "$TMP/lambda.src" l2
git clone -q --bare "$TMP/lambda.src" "$TMP/lambda.git"
git clone -q "$TMP/lambda.git" "$TMP/lambda"
commit "$TMP/lambda" l3-local                                    # diverge
commit "$TMP/lambda.src" l3-remote
git -C "$TMP/lambda.src" push -q "$TMP/lambda.git" main
LAMBDA_REMOTE="$(git -C "$TMP/lambda.git" rev-parse main)"
rigs_json lambda
: > "$TMP/escalations"; : > "$TMP/retractions"
bash "$SCRIPT" >/dev/null
eq "$(open_count lambda)" "1" "lambda files a reconcile bead while diverged"
LAMBDA_BEAD="$(bead_for lambda)"

# A person resets lambda, but the withdrawal fails: lambda advances, the
# withdrawal is attempted, and because it did not land the subject is NOT
# closed.
git -C "$TMP/lambda" reset --hard -q origin/main
: > "$TMP/retractions"
FAKE_RETRACT_FAIL=1 bash "$SCRIPT" >/dev/null 2>&1
eq "$(git -C "$TMP/lambda" rev-parse HEAD)" "$LAMBDA_REMOTE" "lambda is on origin"
eq "$(retract_count lambda)" "1" "a withdrawal is attempted on the recovered rig"
eq "$(open_count lambda)" "1" "a FAILED withdrawal leaves the reconcile subject OPEN as the retry handle"
eq "$(bead_for lambda)" "$LAMBDA_BEAD" "the same subject stays open — no fresh bead is filed"

# Next patrol, the withdrawal succeeds: the still-open subject is re-found and closed.
: > "$TMP/retractions"
bash "$SCRIPT" >/dev/null
eq "$(retract_count lambda)" "1" "the next patrol retries the withdrawal on the still-open subject"
eq "$(open_count lambda)" "0" "a successful withdrawal finally closes the subject"

# --- A rig whose fetch fails. -----------------------------------------------
# rho's origin is gone, so its pass skips it: nothing moves and nothing is filed.
behind_rig rho
echo local-edit > "$TMP/rho/f.txt"
git -C "$TMP/rho" remote set-url origin "$TMP/absent.git"
RHO_HEAD="$(git -C "$TMP/rho" rev-parse HEAD)"
rigs_json rho
: > "$TMP/escalations"; : > "$TMP/retractions"
RHO_OUT="$(bash "$SCRIPT")"
eq "$(git -C "$TMP/rho" rev-parse HEAD)" "$RHO_HEAD" "a rig whose fetch fails is not moved"
eq "$(cat "$TMP/rho/f.txt")" "local-edit" "a rig whose fetch fails keeps its local change"
eq "$(esc_count rho)" "0" "a rig whose fetch fails files no gate"
eq "$(open_count rho)" "0" "a rig whose fetch fails files no reconcile bead"
eq "$(retract_count rho)" "0" "a rig whose fetch fails withdraws nothing"
eq "$RHO_OUT" "reconcile-rig-checkouts: 0 advanced, 0 blocked" "a rig whose fetch fails is counted neither advanced nor blocked"

# No subject bead or gate message this suite filed tells a person to run a
# reset that overwrites what is in its way.
RESET_TOLD="$(grep -l -E 'reset --(hard|keep)' "$TMP"/ledger.*.body "$TMP"/escalations.*.msg 2>/dev/null || true)"
eq "$RESET_TOLD" "" "no escalation tells a person to run git reset --hard or --keep"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
