#!/usr/bin/env bash
# Hermetic test for recover-stranded-branches.sh (tk-f69ay). Stubs `gc`, `git` and
# `gh` on PATH. No live city, Dolt, network or repository.
#
# The pass hands off COMPLETED work that reached origin and then stopped, because
# nothing in the city owns its next move: an open, UNASSIGNED, UNROUTED work bead
# whose branch is pushed and ahead of its target, with no PR and no live session
# behind its molecule. Covered:
#   (STRAND)   the canonical shape -> assigned to the refinery, branch+target
#              stamped, note appended, mayor mailed
#   (ORDER)    metadata is written BEFORE the assignee — the same order the done
#              sequence uses, so the refinery never sees the bead before the fields
#              it merges by are on it
#   (DEFAULT)  a bead with no target and a convoy with none either lands on the
#              repository default branch
#   (CONVOY)   a target the BEAD does not carry is taken from its input convoy —
#              an owned convoy lands its members on an integration branch, and
#              stamping `main` there would rebase the work onto the wrong base
#   (LIVEROOT) THE guard: a candidate whose molecule root records a LIVE session is
#              left alone. Verified live on tk-f69ay itself — a work bead is open
#              with assignee=null and no gc.routed_to for the WHOLE time its polecat
#              works it, so "unassigned" describes every in-flight molecule too and
#              only liveness separates a strand from work in progress
#   (LIVESTEP) the second liveness signal: the root records no live session, but one
#              of its live STEP beads is held by one — a re-claimed or re-nudged
#              molecule wears that shape
#   (DEADROOT) the converse: a molecule whose root session is gone IS handed off
#   (HASPR)    any pull request for the head, in ANY state, means a landing path
#              exists (or an operator closed one deliberately) -> left alone
#   (PRFAIL)   a gh lookup that FAILS is not "no PR" -> reported, never handed off
#   (NOBRANCH) a branch that is not on origin is unpublished work -> the witness's
#              worktree salvage owns it, this pass only reports
#   (NOBASE)   a target branch that is not on origin -> reported and ESCALATED; the
#              branch cannot be compared against a base that is not there
#   (BEHIND)   0 commits ahead of the target -> nothing left to land, left for the
#              refinery to reconcile, never handed off
#   (FRESH)    a tip younger than --min-age-minutes is work in motion, not a strand
#   (SKIPSET)  the non-candidates, each excluded by exactly one field: an assignee,
#              a gc.routed_to, a merge_result, a recorded PR, duplicate_of, a live
#              merge_hold, and a non-impl task_kind
#   (ROSTER)   an unreadable session roster hands off NOTHING — an unread roster
#              makes every running polecat look dead
#   (BEADS)    an unreadable live-bead listing does the same — without it no
#              molecule can be proved husked
#   (BOUND)    a bead already carrying the flag for this (branch, tip) is counted
#              but not re-warned and not re-mailed
#   (FAILED)   a handoff whose assignee does not read back exits NON-ZERO — a silent
#              exit 0 over a failed write is how this class of bug hides
#   (DRY)      --dry-run selects the same beads and issues no write at all
#   (NOCLOSE)  the pass never closes a bead and never rewrites status: only the
#              refinery closes a work bead, after verifying the merge
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/recover-stranded-branches.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { grep -q -- "$1" "$2" && ok "$3" || bad "$3 (not found: $1)"; }
hasnt() { grep -q -- "$1" "$2" && bad "$3 (unexpectedly found: $1)" || ok "$3"; }

mkdir -p "$TMP/bin"

NOW=$(date +%s)
OLD_EPOCH=$((NOW - 7200))     # 2h — comfortably past the 30m default
FRESH_EPOCH=$((NOW - 120))    # 2m — inside it
OLD_ISO=$(jq -rn --argjson e "$OLD_EPOCH" '$e | todate')
FRESH_ISO=$(jq -rn --argjson e "$FRESH_EPOCH" '$e | todate')

# --- Fixtures -----------------------------------------------------------------
# Candidate listing: what `gc bd list --has-metadata-key=branch` returns. Every row
# is a work bead carrying metadata.branch; the pass's own filter decides which of
# them are candidates at all.
#
# The SKIPSET rows are each excluded by exactly ONE field, so a filter clause that
# is dropped shows up as a specific bead being handed off rather than as a count.
cat > "$TMP/candidates.json" <<JSON
[
  {"id":"b-strand","status":"open","assignee":"","updated_at":"__OLD__",
   "metadata":{"branch":"polecat/b-strand"}},
  {"id":"b-conv","status":"open","assignee":null,"updated_at":"__OLD__",
   "metadata":{"branch":"polecat/b-conv"}},
  {"id":"b-live","status":"open","assignee":"","updated_at":"__OLD__",
   "metadata":{"branch":"polecat/b-live"}},
  {"id":"b-livestep","status":"open","assignee":"","updated_at":"__OLD__",
   "metadata":{"branch":"polecat/b-livestep"}},
  {"id":"b-pr","status":"open","assignee":"","updated_at":"__OLD__",
   "metadata":{"branch":"polecat/b-pr"}},
  {"id":"b-ghfail","status":"open","assignee":"","updated_at":"__OLD__",
   "metadata":{"branch":"polecat/b-ghfail"}},
  {"id":"b-nobranch","status":"open","assignee":"","updated_at":"__OLD__",
   "metadata":{"branch":"polecat/b-nobranch"}},
  {"id":"b-nobase","status":"open","assignee":"","updated_at":"__OLD__",
   "metadata":{"branch":"polecat/b-nobase","target":"integration/gone"}},
  {"id":"b-behind","status":"open","assignee":"","updated_at":"__OLD__",
   "metadata":{"branch":"polecat/b-behind"}},
  {"id":"b-fresh","status":"open","assignee":"","updated_at":"__FRESH__",
   "metadata":{"branch":"polecat/b-fresh"}},
  {"id":"b-flagged","status":"open","assignee":"","updated_at":"__OLD__",
   "metadata":{"branch":"polecat/b-flagged","stranded_branch_flagged":"polecat/b-flagged@missing"}},
  {"id":"b-fail","status":"open","assignee":"","updated_at":"__OLD__",
   "metadata":{"branch":"polecat/b-fail"}},

  {"id":"x-assigned","status":"open","assignee":"gc-toolkit__polecat-lx-1","updated_at":"__OLD__",
   "metadata":{"branch":"polecat/x-assigned"}},
  {"id":"x-routed","status":"open","assignee":"","updated_at":"__OLD__",
   "metadata":{"branch":"polecat/x-routed","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}},
  {"id":"x-stamped","status":"open","assignee":"","updated_at":"__OLD__",
   "metadata":{"branch":"polecat/x-stamped","merge_result":"pre_open_gate"}},
  {"id":"x-pr","status":"open","assignee":"","updated_at":"__OLD__",
   "metadata":{"branch":"polecat/x-pr","pr_number":"296"}},
  {"id":"x-dup","status":"open","assignee":"","updated_at":"__OLD__",
   "metadata":{"branch":"polecat/x-dup","duplicate_of":"b-strand"}},
  {"id":"x-hold","status":"open","assignee":"","updated_at":"__OLD__",
   "metadata":{"branch":"polecat/x-hold","merge_hold":"true"}},
  {"id":"x-review","status":"open","assignee":"","updated_at":"__OLD__",
   "metadata":{"branch":"polecat/x-review","task_kind":"review"}}
]
JSON
sed -i -e "s#__OLD__#$OLD_ISO#g" -e "s#__FRESH__#$FRESH_ISO#g" "$TMP/candidates.json"

# Live bead listing: the molecule map is built from this one call. Roots carry
# gc.input_convoy_id (verified live: they appear in the ordinary open/in_progress
# listing), step beads carry gc.root_bead_id plus the assignee that holds them.
cat > "$TMP/live.json" <<'JSON'
[
  {"id":"r-strand","status":"in_progress","assignee":"",
   "metadata":{"gc.input_convoy_id":"c-strand","gc.session_name":"gc-toolkit__polecat-lx-dead"}},
  {"id":"r-conv","status":"in_progress","assignee":"",
   "metadata":{"gc.input_convoy_id":"c-conv","gc.session_name":"gc-toolkit__polecat-lx-gone"}},
  {"id":"r-live","status":"in_progress","assignee":"",
   "metadata":{"gc.input_convoy_id":"c-live","gc.session_name":"gc-toolkit__polecat-lx-busy"}},
  {"id":"r-livestep","status":"in_progress","assignee":"",
   "metadata":{"gc.input_convoy_id":"c-livestep","gc.session_name":"gc-toolkit__polecat-lx-dead"}},
  {"id":"s-livestep","status":"in_progress","assignee":"gc-toolkit__polecat-lx-busy",
   "metadata":{"gc.root_bead_id":"r-livestep","gc.step_ref":"mol-polecat-work.implement"}},
  {"id":"s-dead","status":"in_progress","assignee":"gc-toolkit__polecat-lx-dead",
   "metadata":{"gc.root_bead_id":"r-strand","gc.step_ref":"mol-polecat-work.load-context"}}
]
JSON

# Live sessions. Only lx-busy is alive; lx-dead / lx-gone are absent from the
# roster entirely, which is what a reaped session looks like.
cat > "$TMP/sessions.json" <<'JSON'
{"sessions":[
  {"id":"lx-busy","session_name":"gc-toolkit__polecat-lx-busy","alias":"gc-toolkit/gc-toolkit.nux","state":"active","closed":false},
  {"id":"lx-witness","session_name":"gc-toolkit__witness","alias":"gc-toolkit/gc-toolkit.witness","state":"active","closed":false}
]}
JSON

# bead -> its input convoy (what `gc bd dep list <id> --direction=up` answers)
cat > "$TMP/deps" <<'D'
b-strand|c-strand
b-conv|c-conv
b-live|c-live
b-livestep|c-livestep
b-pr|c-strand
b-ghfail|c-strand
b-nobranch|c-strand
b-nobase|c-strand
b-behind|c-strand
b-fresh|c-strand
b-flagged|c-strand
b-fail|c-strand
D

# convoy -> metadata.target (only the owned convoy carries one)
cat > "$TMP/convoy_targets" <<'C'
c-conv|integration/gc-2026
C

# branch -> sha on origin. A branch absent here does not exist on origin.
cat > "$TMP/remote" <<'R'
main|sha-main
integration/gc-2026|sha-int
polecat/b-strand|sha-strand
polecat/b-conv|sha-conv
polecat/b-live|sha-live
polecat/b-livestep|sha-livestep
polecat/b-pr|sha-pr
polecat/b-ghfail|sha-ghfail
polecat/b-nobase|sha-nobase
polecat/b-behind|sha-behind
polecat/b-fresh|sha-fresh
polecat/b-fail|sha-fail
R

# sha -> commits ahead of its base
cat > "$TMP/ahead" <<'A'
sha-strand|2
sha-conv|1
sha-live|3
sha-livestep|1
sha-pr|1
sha-ghfail|1
sha-nobase|1
sha-behind|0
sha-fresh|1
sha-fail|4
A

# branch -> the `gh pr list` payload for it. Absent -> [] (no PR).
cat > "$TMP/prs" <<'P'
polecat/b-pr|[{"number":297,"state":"OPEN"}]
P

: > "$TMP/updates"
: > "$TMP/mail"
: > "$TMP/nudges"
: > "$TMP/assignees"

# --- gc stub ------------------------------------------------------------------
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
sub="$1"; shift
case "$sub" in
  bd)
    # bd_pinned inserts `--rig <rig>` immediately after `bd`.
    if [ "${1:-}" = "--rig" ]; then shift 2; fi
    op="$1"; shift
    case "$op" in
      list)
        # Matched with a case glob rather than `printf ... | grep -q`: this stub
        # inherits no pipefail, but the pack's check-pipefail-grep-q doctor check
        # is a textual scan and a stub is not worth a finding in it.
        case " $* " in
          *--type=session*)             printf '[]\n' ;;
          *--has-metadata-key=branch*)  cat "$FAKE_CANDIDATES" ;;
          *)
            [ -n "${FAKE_LIVE_FAIL:-}" ] && { echo "boom" >&2; exit 3; }
            cat "$FAKE_LIVE" ;;
        esac ;;
      show)
        id="$1"
        t=$(awk -F'|' -v c="$id" '$1==c{print $2; exit}' "$FAKE_CONVOY_TARGETS")
        if [ -n "$t" ]; then jq -n --arg t "$t" '[{metadata:{target:$t}}]'; else
          a=$(awk -F'\t' -v i="$id" '$1==i{r=$2} END{print r}' "$FAKE_ASSIGNEES")
          jq -n --arg a "$a" '[{assignee:$a, metadata:{}}]'
        fi ;;
      update)
        printf 'gc bd update %s\n' "$*" >> "$FAKE_UPDATES"
        id="$1"
        for arg in "$@"; do
          case "$arg" in
            --assignee=*)
              # b-fail models a write that reports success and is not durable.
              [ "$id" = "b-fail" ] && continue
              printf '%s\t%s\n' "$id" "${arg#--assignee=}" >> "$FAKE_ASSIGNEES" ;;
          esac
        done ;;
      dep)
        # `dep list <id> --direction=up --json`
        id="$2"
        c=$(awk -F'|' -v b="$id" '$1==b{print $2; exit}' "$FAKE_DEPS")
        if [ -n "$c" ]; then jq -n --arg c "$c" '[{id:$c, issue_type:"convoy"}]'; else printf '[]\n'; fi ;;
      *) : ;;
    esac ;;
  session)
    case "${1:-}" in
      list)
        [ -n "${FAKE_SESSIONS_FAIL:-}" ] && { echo "boom" >&2; exit 7; }
        cat "$FAKE_SESSIONS" ;;
      nudge) printf '%s\n' "$*" >> "$FAKE_NUDGES" ;;
      *) : ;;
    esac ;;
  mail) printf '%s\n' "$*" >> "$FAKE_MAIL" ;;
  *) : ;;
esac
exit 0
GC

# --- git stub -----------------------------------------------------------------
cat > "$TMP/bin/git" <<'GIT'
#!/usr/bin/env bash
# Every call the pass makes is `git -C <root> ...`.
[ "${1:-}" = "-C" ] && shift 2
case "$1 ${2:-}" in
  "rev-parse --git-dir") printf '.git\n' ;;
  "remote get-url") printf 'https://github.com/zookanalytics/gc-toolkit.git\n' ;;
  "symbolic-ref --quiet") printf 'origin/main\n' ;;
  "ls-remote origin")
    ref="$3"; b="${ref#refs/heads/}"
    s=$(awk -F'|' -v b="$b" '$1==b{print $2; exit}' "$FAKE_REMOTE")
    [ -n "$s" ] && printf '%s\t%s\n' "$s" "$ref" ;;
  "cat-file -e")
    s="${3%%^*}"
    grep -q "|$s\$" "$FAKE_REMOTE" && exit 0 || exit 1 ;;
  "fetch --quiet") exit 0 ;;
  "log -1")
    s="$4"
    if [ "$s" = "sha-fresh" ]; then printf '%s\n' "$FAKE_FRESH_EPOCH"
    else printf '%s\n' "$FAKE_OLD_EPOCH"; fi ;;
  "rev-list --count")
    range="$3"; head="${range##*..}"
    awk -F'|' -v s="$head" '$1==s{print $2; exit}' "$FAKE_AHEAD" ;;
  *) exit 0 ;;
esac
exit 0
GIT

# --- gh stub ------------------------------------------------------------------
cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
# `gh pr list --repo <slug> --head <branch> --state all --json ... --limit 10`
head=""
while [ $# -gt 0 ]; do
  case "$1" in --head) head="$2"; shift 2 ;; *) shift ;; esac
done
[ "$head" = "polecat/b-ghfail" ] && { echo "gh: boom" >&2; exit 1; }
p=$(awk -F'|' -v b="$head" '$1==b{ $1=""; sub(/^\|/,""); print; exit }' "$FAKE_PRS")
if [ -n "$p" ]; then printf '%s\n' "$p"; else printf '[]\n'; fi
exit 0
GH

chmod +x "$TMP/bin/gc" "$TMP/bin/git" "$TMP/bin/gh"

export PATH="$TMP/bin:$PATH"
export FAKE_CANDIDATES="$TMP/candidates.json" FAKE_LIVE="$TMP/live.json"
export FAKE_SESSIONS="$TMP/sessions.json" FAKE_DEPS="$TMP/deps"
export FAKE_CONVOY_TARGETS="$TMP/convoy_targets" FAKE_REMOTE="$TMP/remote"
export FAKE_AHEAD="$TMP/ahead" FAKE_PRS="$TMP/prs" FAKE_UPDATES="$TMP/updates"
export FAKE_MAIL="$TMP/mail" FAKE_NUDGES="$TMP/nudges" FAKE_ASSIGNEES="$TMP/assignees"
export FAKE_OLD_EPOCH="$OLD_EPOCH" FAKE_FRESH_EPOCH="$FRESH_EPOCH"
export GC_RIG="gc-toolkit" GC_AGENT="gc-toolkit/gc-toolkit.witness"

REFINERY="gc-toolkit/gc-toolkit.refinery"
run() { "$SCRIPT" --refinery "$REFINERY" --root "$TMP/repo" "$@" 2> "$TMP/err" > "$TMP/out"; }

# --- pass 1: --dry-run --------------------------------------------------------
set +e
run --dry-run
DRY_RC=$?
set -e
eq "$DRY_RC" "0" "(DRY) dry run exits 0"
has "DRY-RUN would hand b-strand" "$TMP/out" "(DRY) selects the stranded bead"
has "DRY-RUN would hand b-conv" "$TMP/out" "(DRY) selects the convoy-targeted bead"
hasnt "b-live" "$TMP/out" "(DRY) does not select the live molecule"
eq "$(wc -l < "$TMP/updates")" "0" "(DRY) issues no bead update at all"
eq "$(wc -l < "$TMP/mail")" "0" "(DRY) sends no mail"

# --- pass 2: the real pass ----------------------------------------------------
set +e
run
RC=$?
set -e

eq "$RC" "1" "(FAILED) a handoff that does not read back makes the pass exit non-zero"

# (STRAND) + (ORDER): metadata first, assignee second, both for the same bead.
STRAND_LINES=$(grep -n 'gc bd update b-strand' "$TMP/updates" | head -2)
META_LINE=$(printf '%s\n' "$STRAND_LINES" | grep -c 'set-metadata branch=polecat/b-strand' || true)
eq "$META_LINE" "1" "(STRAND) stamps branch on the recovered bead"
has "gc bd update b-strand --set-metadata branch=polecat/b-strand --set-metadata target=main" "$TMP/updates" \
  "(DEFAULT) target falls back to the repository default branch"
has "gc bd update b-strand --assignee=gc-toolkit/gc-toolkit.refinery" "$TMP/updates" \
  "(STRAND) hands the bead to the refinery"
FIRST=$(grep -n 'gc bd update b-strand' "$TMP/updates" | head -1)
case "$FIRST" in
  *set-metadata*) ok "(ORDER) metadata is written before the assignee" ;;
  *) bad "(ORDER) metadata is written before the assignee (first write was: $FIRST)" ;;
esac
has "stranded_branch_recovered=polecat/b-strand@sha-strand" "$TMP/updates" \
  "(STRAND) records the recovery marker at the reviewed tip"
has "append-notes" "$TMP/updates" "(STRAND) appends its note, never replaces"
hasnt "\-\-notes " "$TMP/updates" "(STRAND) never uses replacing --notes"
has "STRANDED BRANCH RECOVERED: b-strand" "$TMP/mail" "(STRAND) mails the mayor once"

# (CONVOY): the target the bead does not carry comes from its owned convoy.
has "gc bd update b-conv --set-metadata branch=polecat/b-conv --set-metadata target=integration/gc-2026" \
  "$TMP/updates" "(CONVOY) target is taken from the input convoy, not the default branch"

# (LIVEROOT) / (LIVESTEP): untouched, in every observable way.
hasnt "gc bd update b-live " "$TMP/updates" "(LIVEROOT) a live molecule root is never written to"
hasnt "gc bd update b-livestep" "$TMP/updates" "(LIVESTEP) a live step holder is never written to"
hasnt "b-live@" "$TMP/updates" "(LIVEROOT) no marker is left on live work"

# (DEADROOT): the converse of LIVEROOT — b-strand's root session is absent from the
# roster, and it IS handed off (asserted above). Assert the discrimination directly:
# exactly three beads reach an assignee write — b-strand, b-conv, and b-fail, whose
# write is ATTEMPTED and then does not read back (that is the (FAILED) case, and it
# belongs in this count precisely because the pass decided it was stranded).
eq "$(grep -c 'assignee=gc-toolkit/gc-toolkit.refinery' "$TMP/updates")" "3" \
  "(DEADROOT) exactly the three dead-molecule beads reach a handoff"

# (HASPR) / (PRFAIL) / (NOBRANCH) / (NOBASE) / (BEHIND) / (FRESH)
hasnt "gc bd update b-pr " "$TMP/updates" "(HASPR) a branch with an open PR is left alone"
has "already has #297 OPEN" "$TMP/out" "(HASPR) says which PR it found"
has "stranded_branch_flagged=polecat/b-ghfail@sha-ghfail" "$TMP/updates" \
  "(PRFAIL) a failed PR lookup flags the bead"
hasnt "gc bd update b-ghfail --assignee" "$TMP/updates" "(PRFAIL) and never hands it off"
has "the pull-request lookup for 'polecat/b-ghfail'" "$TMP/err" "(PRFAIL) explains the refusal"
has "does not exist on origin" "$TMP/err" "(NOBRANCH) reports an unpublished branch"
hasnt "gc bd update b-nobranch --assignee" "$TMP/updates" "(NOBRANCH) never hands off unpublished work"
has "which does not exist on origin" "$TMP/err" "(NOBASE) reports a missing target branch"
has "STRANDED BRANCH: b-nobase" "$TMP/mail" "(NOBASE) escalates the one refusal a human must resolve"
hasnt "gc bd update b-behind" "$TMP/updates" "(BEHIND) an already-landed branch is left for the refinery"
has "0 commits ahead" "$TMP/out" "(BEHIND) says so"
hasnt "gc bd update b-fresh" "$TMP/updates" "(FRESH) work younger than the age gate is untouched"

# (BOUND): already flagged for this exact (branch, tip) -> no second warning, no
# second mail, no repeated marker write.
# 4 reported = b-ghfail + b-nobranch + b-nobase + b-flagged. The already-flagged
# bead is COUNTED (so a genuinely stuck bead never disappears from the summary)
# while issuing no second warning, marker or mail.
has "4 reported" "$TMP/out" "(BOUND) an already-flagged bead is still counted"
hasnt "gc bd update b-flagged" "$TMP/updates" "(BOUND) but is not re-marked"
hasnt "b-flagged" "$TMP/mail" "(BOUND) and not re-mailed"

# (SKIPSET): every non-candidate, each held back by exactly one field.
for x in x-assigned x-routed x-stamped x-pr x-dup x-hold x-review; do
  hasnt "gc bd update $x" "$TMP/updates" "(SKIPSET) $x is not a candidate"
done

# (NOCLOSE): the pass has no close path and never rewrites status.
hasnt "bd close" "$TMP/updates" "(NOCLOSE) never closes a bead"
hasnt "\-\-status=" "$TMP/updates" "(NOCLOSE) never rewrites status"
hasnt "close" "$TMP/nudges" "(NOCLOSE) never asks anyone else to close one"

# The refinery is nudged once, and only because this pass is not the refinery.
eq "$(grep -c 'gc-toolkit.refinery' "$TMP/nudges")" "1" "(STRAND) nudges the refinery once"

# --- pass 3: fail-safes -------------------------------------------------------
: > "$TMP/updates"; : > "$TMP/mail"
set +e
FAKE_SESSIONS_FAIL=1 run
ROSTER_RC=$?
set -e
eq "$ROSTER_RC" "0" "(ROSTER) an unreadable roster is not a pass failure"
has "FAIL-SAFE" "$TMP/err" "(ROSTER) says it is failing safe"
hasnt "assignee=gc-toolkit/gc-toolkit.refinery" "$TMP/updates" \
  "(ROSTER) hands off nothing while the roster is unreadable"

: > "$TMP/updates"; : > "$TMP/mail"
set +e
FAKE_LIVE_FAIL=1 run
BEADS_RC=$?
set -e
eq "$BEADS_RC" "0" "(BEADS) an unreadable live-bead listing is not a pass failure"
has "FAIL-SAFE" "$TMP/err" "(BEADS) says it is failing safe"
hasnt "assignee=gc-toolkit/gc-toolkit.refinery" "$TMP/updates" \
  "(BEADS) hands off nothing while molecules cannot be proved husked"

# --- pass 4: idempotence ------------------------------------------------------
# After a real pass the recovered beads carry an assignee, so they are no longer
# candidates. Model that by re-running against a listing with the assignee applied.
jq -c 'map(if .id == "b-strand" or .id == "b-conv"
           then .assignee = "gc-toolkit/gc-toolkit.refinery" else . end)' \
  "$TMP/candidates.json" > "$TMP/candidates2.json"
: > "$TMP/updates"; : > "$TMP/mail"
set +e
FAKE_CANDIDATES="$TMP/candidates2.json" run
set -e
hasnt "gc bd update b-strand" "$TMP/updates" "(IDEM) a recovered bead is not recovered twice"
hasnt "gc bd update b-conv" "$TMP/updates" "(IDEM) nor is the convoy-targeted one"

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
