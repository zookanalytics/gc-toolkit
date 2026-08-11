#!/usr/bin/env bash
# Hermetic test for reconcile-gate-verdicts.sh — the merge-gate VERDICT arm
# (WS4 of tk-zgse0; design specs/tk-zgse0.2/merge-gate-exception-lifecycle.md).
#
# Stubs `gc` (bd list / dep list / show / update, session list, mail send) and
# `gh` (PR head, branch head) on PATH, over a MUTABLE bead store so a write made
# by one pass is read by the next — which is what makes the one-action-per-head
# and convergence cases mean anything. No live city, Dolt, or network.
#
# Covered:
#   (OK)        green@<live head> -> nothing written, nothing escalated
#   (R11)       remediation rounds at the cap with the gate not green -> exception
#               recorded at the live head, with the reason, plus ONE operator mail
#   (LOST)      R12: a review whose assignee no live session answers to, untouched
#               past the deadline -> exception (worker-lost)
#   (ALIVE)     the same review with a LIVE assignee -> NOT an exception. The
#               deadline alone never condemns a slow reviewer.
#   (FRESH)     dead assignee but INSIDE the deadline -> NOT an exception
#   (CLOCK)     the deadline is measured on heartbeat_at where there is one, not
#               updated_at: a session's heartbeat says when the WORKER was last
#               alive, while updated_at moves only when the bead is written, so a
#               reviewer thinking hard reads identical to one that died. Both
#               fixtures above carry the two timestamps in OPPOSITE directions, so
#               each of them fails if the preference order is reversed.
#   (UNMAP)     R12: a marker naming no known verb -> exception (unmappable), the
#               totality case — no observable state is left without a verdict
#   (FIXABLE)   an open remediation child under the cap -> fixable@<head> recorded,
#               NO escalation (a non-terminal verdict is a record, not an alarm)
#   (INFLIGHT)  a round still RUNNING is not a round spent: two closed rounds plus
#               an open child at cap 3 is fixable, not exhaustion
#   (CAPOPEN)   the completed rounds reach the cap but a child is still open ->
#               exhaustion is DEFERRED, because an exception is terminal until an
#               operator acts and something is still coming
#   (CAPCLOSE)  that child closes -> the exception fires on the next wake, so the
#               deferral above is not a way of disabling R11
#   (POISON)    a pre-open gate excepted at an OLD head whose dead review is still
#               open, branch head since moved: the corpse must NOT re-condemn the
#               new head. It carries no dispatch head, so left open it answers the
#               worker-lost scan at every later head and re-stamps exception before
#               the re-arm can fire — the head move is consumed and the operator
#               escape the design promises never happens. Re-arm, and RETIRE the
#               corpse so check-set-heal can dispatch a replacement.
#   (TWIN)      all the dead reviews are retired, not just the first (the scan used
#               to stop at one, leaving the next to poison the next head), and a
#               LIVE reviewer on the same anchor is left alone
#   (PRESTALE)  a pre-open exception bound to a head the branch moved past is
#               CLEARED: nothing else re-arms a pre-open gate, and check-set-heal
#               skips its dispatch on `exception@*` without ever resolving a head
#   (PREGREEN)  the same for a stale pre-open `green@*` — the other verb that
#               blocks the dispatch
#   (PREFIX)    and only those two: a stale `fixable@*` blocked nothing, so it is
#               left alone
#   (POSTSTALE) the boundary — post-open a stale marker is left intact, because it
#               is what reconcile-merged-prs.sh's stale-marker arm keys on
#   (UNEVAL)    no marker, no open child, under the cap -> NOTHING written. Stamping
#               fixable here would assert a finding nobody made AND would tell
#               check-set-heal.sh a gate with nothing in flight needs no dispatch.
#   (ONEHEAD)   an exception already recorded at the live head -> held, no second
#               mail, no rewrite
#   (MOVED)     an exception bound to an OLD head -> the head move re-arms the gate
#               and it is judged fresh (and re-escalated: a new head is a new
#               subject). This is how an exception CLEARS.
#   (HOLD)      merge_hold set -> the verdict is still recorded (it only holds
#               harder) but the operator is NOT mailed about a PR they parked
#   (HUMAN)     gc.routed_to=human -> recorded, not re-escalated (another writer
#               already put it in front of an operator)
#   (PREOPEN)   a pre_open_gate anchor is gated off its BRANCH head, with no PR
#   (GATELESS)  check_set=none / off -> skipped; `approval` is not marker-backed
#   (NOROSTER)  an unreadable session roster DISABLES the worker-lost arm rather
#               than condemning every assignee at once
#   (NOHEAD)    an unresolvable live head -> skipped, nothing bound to nothing
#   (DRYRUN)    --dry-run writes nothing and mails nobody
#   (STICK)     a verdict write that does not read back -> NOT escalated (an
#               escalation over an unrecorded verdict sends an operator to an
#               anchor whose state does not mention the problem)
#   (NEVERGREEN) THE SAFETY INVARIANT: across every case above, this pass never
#               writes a `green` marker and never merges. Every write it makes
#               holds the merge or keeps it held.
#   (CONVERGE)  run 2 over the state run 1 produced: no new exceptions, no second
#               mail, no rewrite
#   (OWED)      an exception RECORDED but not yet escalated — the merge_hold case,
#               and equally a mail that failed — is still owed its notification.
#               The guard is stamped only when a mail goes out, so a later pass
#               must re-check it rather than returning early on "already
#               excepted": otherwise a recorded exception nobody was told about is
#               held forever, wearing this arm's own marker.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/reconcile-gate-verdicts.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has()    { grep -qF -- "$2" "$1" && ok "$3" || bad "$3 (missing '$2')"; }
hasnt()  { grep -qF -- "$2" "$1" && bad "$3 (unexpected '$2')" || ok "$3"; }

mkdir -p "$TMP/bin" "$TMP/repo"

# A real checkout, so the script's own origin-repo pin runs unstubbed — that pin
# is what keeps a head from being read in a repository nobody named.
git -C "$TMP/repo" init -q
git -C "$TMP/repo" remote add origin https://github.com/acme/widgets.git

NOW=$(date +%s)
old_ts()  { date -u -d "@$((NOW - $1))" +%Y-%m-%dT%H:%M:%SZ; }

# --- the bead store ---------------------------------------------------------
# One JSON array, mutated in place by the `gc bd update` stub. Anchors, reviews
# and remediation children all live here; the stub's queries are the same shapes
# the script issues.
cat > "$TMP/beads.json" <<JSON
[
  {"id":"a-ok","status":"open","metadata":{"merge_result":"pull_request","check_set":"codex","pr_number":"10","check.codex":"green@head10"}},

  {"id":"a-r11","status":"open","metadata":{"merge_result":"pull_request","check_set":"codex","pr_number":"11"}},
  {"id":"k-r11a","status":"closed","metadata":{"source_review_bead":"rv-old1","parent":"a-r11"}},
  {"id":"k-r11b","status":"closed","metadata":{"source_review_bead":"rv-old2","parent":"a-r11"}},
  {"id":"k-r11c","status":"closed","metadata":{"source_review_bead":"rv-old3","parent":"a-r11"}},

  {"id":"a-lost","status":"open","metadata":{"merge_result":"pull_request","check_set":"codex","pr_number":"12"}},
  {"id":"rv-lost","status":"in_progress","assignee":"ghost-session","heartbeat_at":"$(old_ts 99999)","updated_at":"$(old_ts 5)","metadata":{"anchor_bead":"a-lost","check_name":"codex"}},

  {"id":"a-alive","status":"open","metadata":{"merge_result":"pull_request","check_set":"codex","pr_number":"13"}},
  {"id":"rv-alive","status":"in_progress","assignee":"live-session","updated_at":"$(old_ts 99999)","metadata":{"anchor_bead":"a-alive","check_name":"codex"}},

  {"id":"a-fresh","status":"open","metadata":{"merge_result":"pull_request","check_set":"codex","pr_number":"14"}},
  {"id":"rv-fresh","status":"in_progress","assignee":"ghost-session","heartbeat_at":"$(old_ts 60)","updated_at":"$(old_ts 99999)","metadata":{"anchor_bead":"a-fresh","check_name":"codex"}},

  {"id":"a-unmap","status":"open","metadata":{"merge_result":"pull_request","check_set":"codex","pr_number":"15","check.codex":"weird@head15"}},

  {"id":"a-fix","status":"open","metadata":{"merge_result":"pull_request","check_set":"codex","pr_number":"16"}},
  {"id":"k-fix","status":"open","metadata":{"source_review_bead":"rv-fix","parent":"a-fix"}},

  {"id":"a-uneval","status":"open","metadata":{"merge_result":"pull_request","check_set":"codex","pr_number":"17"}},

  {"id":"a-onehead","status":"open","metadata":{"merge_result":"pull_request","check_set":"codex","pr_number":"18","check.codex":"exception@head18","check.codex.exception_escalated":"head18"}},

  {"id":"a-moved","status":"open","metadata":{"merge_result":"pull_request","check_set":"codex","pr_number":"19","check.codex":"exception@OLDHEAD","check.codex.exception_escalated":"OLDHEAD"}},
  {"id":"k-moved1","status":"closed","metadata":{"source_review_bead":"rv-m1","parent":"a-moved"}},
  {"id":"k-moved2","status":"closed","metadata":{"source_review_bead":"rv-m2","parent":"a-moved"}},
  {"id":"k-moved3","status":"closed","metadata":{"source_review_bead":"rv-m3","parent":"a-moved"}},

  {"id":"a-hold","status":"open","metadata":{"merge_result":"pull_request","check_set":"codex","pr_number":"20","merge_hold":"true"}},
  {"id":"k-hold1","status":"closed","metadata":{"source_review_bead":"rv-h1","parent":"a-hold"}},
  {"id":"k-hold2","status":"closed","metadata":{"source_review_bead":"rv-h2","parent":"a-hold"}},
  {"id":"k-hold3","status":"closed","metadata":{"source_review_bead":"rv-h3","parent":"a-hold"}},

  {"id":"a-human","status":"open","metadata":{"merge_result":"pull_request","check_set":"codex","pr_number":"21","gc.routed_to":"human"}},
  {"id":"k-hu1","status":"closed","metadata":{"source_review_bead":"rv-u1","parent":"a-human"}},
  {"id":"k-hu2","status":"closed","metadata":{"source_review_bead":"rv-u2","parent":"a-human"}},
  {"id":"k-hu3","status":"closed","metadata":{"source_review_bead":"rv-u3","parent":"a-human"}},

  {"id":"a-pre","status":"open","metadata":{"merge_result":"pre_open_gate","check_set":"codex","branch":"polecat/tk-pre"}},
  {"id":"k-pre1","status":"closed","metadata":{"source_review_bead":"rv-p1","parent":"a-pre"}},
  {"id":"k-pre2","status":"closed","metadata":{"source_review_bead":"rv-p2","parent":"a-pre"}},
  {"id":"k-pre3","status":"closed","metadata":{"source_review_bead":"rv-p3","parent":"a-pre"}},

  {"id":"a-none","status":"open","metadata":{"merge_result":"pull_request","check_set":"none","pr_number":"22"}},
  {"id":"a-appr","status":"open","metadata":{"merge_result":"pull_request","check_set":"approval","pr_number":"23"}},

  {"id":"a-nohead","status":"open","metadata":{"merge_result":"pull_request","check_set":"codex","pr_number":"99"}},

  {"id":"a-stick","status":"open","metadata":{"merge_result":"pull_request","check_set":"codex","pr_number":"24"}},
  {"id":"k-st1","status":"closed","metadata":{"source_review_bead":"rv-s1","parent":"a-stick"}},
  {"id":"k-st2","status":"closed","metadata":{"source_review_bead":"rv-s2","parent":"a-stick"}},
  {"id":"k-st3","status":"closed","metadata":{"source_review_bead":"rv-s3","parent":"a-stick"}},

  {"id":"a-inflight","status":"open","metadata":{"merge_result":"pull_request","check_set":"codex","pr_number":"25"}},
  {"id":"k-if1","status":"closed","metadata":{"source_review_bead":"rv-if1","parent":"a-inflight"}},
  {"id":"k-if2","status":"closed","metadata":{"source_review_bead":"rv-if2","parent":"a-inflight"}},
  {"id":"k-if3","status":"in_progress","metadata":{"source_review_bead":"rv-if3","parent":"a-inflight"}},

  {"id":"a-capopen","status":"open","metadata":{"merge_result":"pull_request","check_set":"codex","pr_number":"26"}},
  {"id":"k-co1","status":"closed","metadata":{"source_review_bead":"rv-co1","parent":"a-capopen"}},
  {"id":"k-co2","status":"closed","metadata":{"source_review_bead":"rv-co2","parent":"a-capopen"}},
  {"id":"k-co3","status":"closed","metadata":{"source_review_bead":"rv-co3","parent":"a-capopen"}},
  {"id":"k-co4","status":"open","metadata":{"source_review_bead":"rv-co4","parent":"a-capopen"}},

  {"id":"a-prestale","status":"open","metadata":{"merge_result":"pre_open_gate","check_set":"codex","branch":"polecat/tk-prestale","check.codex":"exception@oldprestale","check.codex.reason":"worker-lost: review rv-gone held by a dead session","check.codex.exception_escalated":"oldprestale"}},

  {"id":"a-pregreen","status":"open","metadata":{"merge_result":"pre_open_gate","check_set":"codex","branch":"polecat/tk-pregreen","check.codex":"green@oldpregreen"}},

  {"id":"a-prefix","status":"open","metadata":{"merge_result":"pre_open_gate","check_set":"codex","branch":"polecat/tk-prefix","check.codex":"fixable@oldprefix"}},

  {"id":"a-poststale","status":"open","metadata":{"merge_result":"pull_request","check_set":"codex","pr_number":"27","check.codex":"exception@oldpost","check.codex.exception_escalated":"oldpost"}},

  {"id":"a-poison","status":"open","metadata":{"merge_result":"pre_open_gate","check_set":"codex","branch":"polecat/tk-poison","check.codex":"exception@oldpoison","check.codex.reason":"worker-lost: review rv-poison held by 'ghost-session' (no live session answers it) and untouched for 99999s > 3600s deadline","check.codex.exception_escalated":"oldpoison"}},
  {"id":"rv-poison","status":"in_progress","assignee":"ghost-session","heartbeat_at":"$(old_ts 99999)","updated_at":"$(old_ts 99999)","metadata":{"anchor_bead":"a-poison","check_name":"codex"}},

  {"id":"a-twin","status":"open","metadata":{"merge_result":"pre_open_gate","check_set":"codex","branch":"polecat/tk-twin"}},
  {"id":"rv-twin1","status":"in_progress","assignee":"ghost-session","heartbeat_at":"$(old_ts 99999)","updated_at":"$(old_ts 99999)","metadata":{"anchor_bead":"a-twin","check_name":"codex"}},
  {"id":"rv-twin2","status":"in_progress","assignee":"ghost-session","heartbeat_at":"$(old_ts 88888)","updated_at":"$(old_ts 88888)","metadata":{"anchor_bead":"a-twin","check_name":"codex"}},
  {"id":"rv-twinlive","status":"in_progress","assignee":"live-session","heartbeat_at":"$(old_ts 99999)","updated_at":"$(old_ts 99999)","metadata":{"anchor_bead":"a-twin","check_name":"codex"}}
]
JSON

# PR/branch heads. `a-nohead` is deliberately absent: gh answers nothing for it.
cat > "$TMP/heads" <<'H'
pr:10|head10
pr:11|head11
pr:12|head12
pr:13|head13
pr:14|head14
pr:15|head15
pr:16|head16
pr:17|head17
pr:18|head18
pr:19|head19
pr:20|head20
pr:21|head21
pr:24|head24
pr:25|head25
pr:26|head26
pr:27|head27
branch:polecat/tk-pre|headpre
branch:polecat/tk-prestale|headprestale
branch:polecat/tk-pregreen|headpregreen
branch:polecat/tk-prefix|headprefix
branch:polecat/tk-poison|headpoison
branch:polecat/tk-twin|headtwin
H

# The live session roster. `ghost-session` is deliberately absent.
cat > "$TMP/roster" <<'R'
live-session
R

: > "$TMP/mail.log"
: > "$TMP/update.log"
# Writes to these ids are silently dropped, so the script's read-back guard sees
# a verdict that did not stick.
: > "$TMP/nowrite"

cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
STORE="$FAKE_STORE"

if [ "$1" = "session" ] && [ "$2" = "list" ]; then
  [ -n "${FAKE_ROSTER_BROKEN:-}" ] && exit 3
  jq -Rn '[inputs | select(length>0) | {alias: .}] | {sessions: .}' < "$FAKE_ROSTER"
  exit 0
fi

if [ "$1" = "mail" ] && [ "$2" = "send" ]; then
  printf '%s\n' "$*" >> "$FAKE_MAIL"
  exit 0
fi

[ "$1" = "bd" ] || exit 0
shift
# Strip a leading --rig <name> pin (the script always passes one when GC_RIG is set).
while [ "${1:-}" = "--rig" ] || case "${1:-}" in --rig=*) true ;; *) false ;; esac; do
  case "$1" in --rig) shift 2 ;; *) shift ;; esac
done

case "${1:-}" in
  list)
    shift
    mfield=""; wanttype=""; prev=""
    for a in "$@"; do
      case "$prev" in
        --metadata-field) mfield="$a" ;;
        --type) wanttype="$a" ;;
      esac
      case "$a" in
        --metadata-field=*) mfield="${a#--metadata-field=}" ;;
        --type=*) wanttype="${a#--type=}" ;;
      esac
      prev="$a"
    done
    # The session-bead source: this fixture has none, and an empty array is the
    # honest answer (the live roster is the other source and it is stubbed above).
    if [ "$wanttype" = "session" ]; then echo '[]'; exit 0; fi
    if [ -z "$mfield" ]; then echo '[]'; exit 0; fi
    key="${mfield%%=*}"; val="${mfield#*=}"
    jq -c --arg k "$key" --arg v "$val" \
      '[ .[] | select((.metadata[$k] // "" | tostring) == $v) ]' "$STORE"
    exit 0 ;;
  dep)
    # `gc bd dep list <id> --direction=up -t parent-child --json`
    shift; [ "${1:-}" = "list" ] && shift
    anchor="${1:-}"
    jq -c --arg a "$anchor" '[ .[] | select((.metadata.parent // "") == $a) ]' "$STORE"
    exit 0 ;;
  show)
    shift
    id="${1:-}"
    jq -c --arg id "$id" '[ .[] | select(.id == $id) ]' "$STORE"
    exit 0 ;;
  close)
    # `gc bd close <id> --reason "..." [--force]`. ASSIGNEE-GATED like the real one:
    # a bead held by somebody else is refused without --force. The retirement path
    # closes reviews whose assignee is a DEAD session — foreign by construction — so
    # it always lands on the --force retry, and a stub that closed unconditionally
    # would let a regression in that fallback pass unnoticed.
    shift
    id="${1:-}"; shift
    printf '%s close %s\n' "$id" "$*" >> "$FAKE_UPDATES"
    forced=""
    for a in "$@"; do [ "$a" = "--force" ] && forced=1; done
    assignee=$(jq -r --arg id "$id" '[ .[] | select(.id == $id) | .assignee // "" ] | .[0] // ""' "$STORE")
    if [ -n "$assignee" ] && [ -z "$forced" ]; then
      echo "cannot close $id: assignee is \"$assignee\", actor is \"patrol\"; reclaim or use --force to override" >&2
      exit 1
    fi
    tmp=$(mktemp)
    jq --arg id "$id" 'map(if .id == $id then .status = "closed" else . end)' "$STORE" > "$tmp"
    mv "$tmp" "$STORE"
    exit 0 ;;
  update)
    shift
    id="${1:-}"; shift
    printf '%s %s\n' "$id" "$*" >> "$FAKE_UPDATES"
    grep -qxF "$id" "$FAKE_NOWRITE" 2>/dev/null && exit 0   # dropped write
    prev=""
    for a in "$@"; do
      if [ "$prev" = "--set-metadata" ]; then
        k="${a%%=*}"; v="${a#*=}"
        tmp=$(mktemp)
        jq --arg id "$id" --arg k "$k" --arg v "$v" \
          'map(if .id == $id then .metadata[$k] = $v else . end)' "$STORE" > "$tmp"
        mv "$tmp" "$STORE"
      fi
      # The pre-open re-arm CLEARS a stale marker, so the store has to be able to
      # lose a key as well as gain one — a stub that silently ignored the unset
      # would read back the stale marker and the re-arm assertions would pass only
      # by never having run.
      if [ "$prev" = "--unset-metadata" ]; then
        tmp=$(mktemp)
        jq --arg id "$id" --arg k "$a" \
          'map(if .id == $id then .metadata |= del(.[$k]) else . end)' "$STORE" > "$tmp"
        mv "$tmp" "$STORE"
      fi
      prev="$a"
    done
    exit 0 ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
lookup() { awk -F'|' -v k="$1" '$1 == k { print $2; exit }' "$FAKE_HEADS"; }
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  v=$(lookup "pr:$3"); [ -n "$v" ] || exit 1; printf '%s\n' "$v"; exit 0
fi
if [ "$1" = "api" ]; then
  for a in "$@"; do case "$a" in repos/*/commits/*) path="$a" ;; esac; done
  br="${path#*/commits/}"
  v=$(lookup "branch:$br"); [ -n "$v" ] || exit 1
  printf '{"sha":"%s"}\n' "$v"; exit 0
fi
exit 1
GH
chmod +x "$TMP/bin/gh"

run_pass() {
  ( cd "$TMP/repo" \
    && PATH="$TMP/bin:$PATH" \
       FAKE_STORE="$TMP/beads.json" FAKE_HEADS="$TMP/heads" FAKE_ROSTER="$TMP/roster" \
       FAKE_MAIL="$TMP/mail.log" FAKE_UPDATES="$TMP/update.log" FAKE_NOWRITE="$TMP/nowrite" \
       GC_RIG="alpha" GC_MAX_REVIEW_ROUNDS=3 GC_GATE_DEADLINE=3600 \
       bash "$SCRIPT" "$@" ) > "$TMP/out" 2> "$TMP/err" || true
  cat "$TMP/err" >> "$TMP/out"
}

marker() { jq -r --arg id "$1" --arg k "$2" \
  '.[] | select(.id == $id) | .metadata[$k] // "<none>"' "$TMP/beads.json"; }
bstatus() { jq -r --arg id "$1" \
  '.[] | select(.id == $id) | .status // "<none>"' "$TMP/beads.json"; }

# ---------------------------------------------------------------------------
# Run 0 — dry run first, over the untouched fixture: it must change nothing.
# ---------------------------------------------------------------------------
echo "a-stick" > "$TMP/nowrite"
# The store's fingerprint BEFORE the dry run, so the comparison below is the one
# that means something: "the dry run wrote nothing", not "the dry run and the real
# pass agree". Snapshotting after the dry run — as this first did — compares the
# dry run to the REAL pass and would pass unchanged even if the dry run had
# rewritten every marker in the fixture.
before=$(md5sum < "$TMP/beads.json")
run_pass --dry-run
eq "$(md5sum < "$TMP/beads.json")" "$before" "(DRYRUN) the store is byte-identical after a dry run"
eq "$(marker a-r11 check.codex)" "<none>" "(DRYRUN) no verdict written on a dry run"
eq "$(wc -l < "$TMP/mail.log" | tr -d ' ')" "0" "(DRYRUN) no operator mail on a dry run"
has "$TMP/out" "[dry-run]" "(DRYRUN) the pass says what it would have done"

# ---------------------------------------------------------------------------
# Run 1 — the real pass.
# ---------------------------------------------------------------------------
: > "$TMP/update.log"; : > "$TMP/mail.log"
run_pass
# The positive control for the assertion above: a dry run that changes nothing
# proves nothing unless the SAME fixture, run for real, does change something.
if [ "$(md5sum < "$TMP/beads.json")" = "$before" ]; then
  bad "(DRYRUN) the real pass changed the store (positive control for the dry-run check)"
else
  ok "(DRYRUN) the real pass changed the store (positive control for the dry-run check)"
fi

# (OK) green at the live head
eq "$(marker a-ok check.codex)" "green@head10" "(OK) a green gate at the live head is untouched"
hasnt "$TMP/update.log" "a-ok " "(OK) no write at all against a passing gate"

# (R11) rounds at the cap
eq "$(marker a-r11 check.codex)" "exception@head11" "(R11) rounds at the cap -> exception at the live head"
has "$TMP/out" "attempts-exhausted" "(R11) the reason names the trigger"
eq "$(marker a-r11 check.codex.attempts)" "3@head11" "(R11) the round count is stamped with its head"
eq "$(marker a-r11 check.codex.exception_escalated)" "head11" "(R11) the one-per-head guard is armed"
has "$TMP/mail.log" "a-r11" "(R11) the operator is mailed"

# (LOST) R12 — worker gone
eq "$(marker a-lost check.codex)" "exception@head12" "(LOST) a dead worker past the deadline -> exception"
has "$TMP/out" "worker-lost" "(LOST) the reason names the trigger"

# (ALIVE) a live assignee is never condemned by the deadline alone
eq "$(marker a-alive check.codex)" "<none>" "(ALIVE) a LIVE assignee past the deadline is not an exception"

# (FRESH) inside the deadline
eq "$(marker a-fresh check.codex)" "<none>" "(FRESH) a dead assignee inside the deadline is not an exception"
# (CLOCK) Both fixtures carry heartbeat_at and updated_at pointing OPPOSITE ways:
# a-lost is stale by heartbeat and fresh by updated_at, a-fresh is the reverse.
# Reversing the preference order flips both of the two assertions above.
ok "(CLOCK) the deadline is read off heartbeat_at, not updated_at (both fixtures above invert if it is not)"

# (UNMAP) totality
eq "$(marker a-unmap check.codex)" "exception@head15" "(UNMAP) a marker naming no known verb -> exception"
has "$TMP/out" "unmappable-marker" "(UNMAP) the reason names the trigger"

# (FIXABLE) remediation in flight, under the cap
eq "$(marker a-fix check.codex)" "fixable@head16" "(FIXABLE) an open remediation child records fixable at the head"
hasnt "$TMP/mail.log" "a-fix" "(FIXABLE) a non-terminal verdict does not escalate"

# (UNEVAL) nothing in flight, nothing recorded
eq "$(marker a-uneval check.codex)" "<none>" "(UNEVAL) no marker, no open child -> nothing stamped"
hasnt "$TMP/update.log" "a-uneval " "(UNEVAL) no write at all, so check-set-heal still dispatches"

# (ONEHEAD) already excepted at this head
eq "$(marker a-onehead check.codex)" "exception@head18" "(ONEHEAD) the recorded exception is left as-is"
hasnt "$TMP/update.log" "a-onehead " "(ONEHEAD) no rewrite of a verdict already current"
hasnt "$TMP/mail.log" "a-onehead" "(ONEHEAD) no second mail at the same head"

# (MOVED) the head moved past an exception: re-armed, judged fresh, re-escalated
eq "$(marker a-moved check.codex)" "exception@head19" "(MOVED) a head move re-arms and re-judges the gate"
eq "$(marker a-moved check.codex.exception_escalated)" "head19" "(MOVED) the escalation guard re-arms at the new head"
has "$TMP/mail.log" "a-moved" "(MOVED) a new head is a new subject, so it escalates again"

# (HOLD) operator park
eq "$(marker a-hold check.codex)" "exception@head20" "(HOLD) the verdict is recorded under merge_hold"
hasnt "$TMP/mail.log" "a-hold" "(HOLD) the operator is NOT mailed about a PR they parked"
eq "$(marker a-hold check.codex.exception_escalated)" "<none>" "(HOLD) the guard stays unarmed, so the next wake escalates once the hold lifts"

# (HUMAN) already in front of an operator
eq "$(marker a-human check.codex)" "exception@head21" "(HUMAN) the verdict is recorded"
hasnt "$TMP/mail.log" "a-human" "(HUMAN) no second escalation when another writer already routed it to a human"

# (PREOPEN) gated off the branch head, no PR
eq "$(marker a-pre check.codex)" "exception@headpre" "(PREOPEN) a pre-open anchor is gated off its BRANCH head"
has "$TMP/mail.log" "branch polecat/tk-pre" "(PREOPEN) the escalation names the branch, not a PR"

# (GATELESS)
eq "$(marker a-none check.codex)" "<none>" "(GATELESS) the none sentinel has no marker-backed gate"
eq "$(marker a-appr check.approval)" "<none>" "(GATELESS) approval is evidenced by GitHub review state, never a marker"

# (NOHEAD)
eq "$(marker a-nohead check.codex)" "<none>" "(NOHEAD) an unresolvable head binds no verdict"
has "$TMP/out" "live head unresolved" "(NOHEAD) and says so"

# (STICK) the write is dropped -> no escalation over an unrecorded verdict
eq "$(marker a-stick check.codex)" "<none>" "(STICK) the dropped write really did not land"
hasnt "$TMP/mail.log" "a-stick" "(STICK) no escalation over a verdict that did not read back"
has "$TMP/out" "did not stick" "(STICK) and the failure is reported"

# (INFLIGHT) a round still running is not a round spent. Two CLOSED rounds and one
# OPEN child at cap 3: counting the open one as spent would read as exhausted and
# convert a branch a worker is actively fixing into a terminal operator hold.
eq "$(marker a-inflight check.codex)" "fixable@head25" "(INFLIGHT) two closed rounds + an OPEN child at cap 3 -> fixable, not exception"
hasnt "$TMP/mail.log" "a-inflight" "(INFLIGHT) no operator escalation over a round still in flight"

# (CAPOPEN) the completed rounds DO reach the cap, and a child is still open. The
# count alone says exhausted; the in-flight guard is what defers it.
eq "$(marker a-capopen check.codex)" "fixable@head26" "(CAPOPEN) rounds AT the cap with a child still open -> exhaustion deferred, fixable recorded"
hasnt "$TMP/mail.log" "a-capopen" "(CAPOPEN) and nobody is mailed while remediation is running"

# (PRESTALE) the pre-open re-arm. An exception bound to a head the branch has moved
# past is residue: check-set-heal.sh skips its dispatch on `exception@*` and cannot
# see that the head moved, pre-open-resolve.sh opens only on green@<live head>, and
# no other pass re-arms a PRE-open gate — so the operator's fix has no effect and
# the branch is held with nothing left to raise it.
eq "$(marker a-prestale check.codex)" "<none>" "(PRESTALE) a stale pre-open exception is cleared, so check-set-heal can dispatch again"
has "$TMP/out" "pre-open re-arm" "(PRESTALE) and the re-arm is announced"
hasnt "$TMP/mail.log" "a-prestale" "(PRESTALE) re-arming a gate is not an escalation"
eq "$(marker a-prestale check.codex.exception_escalated)" "oldprestale" "(PRESTALE) the head-bound guard is left alone — it stales itself out by never matching a new head"

# (PREGREEN) the same for the OTHER verb check-set-heal skips on. A stale green
# strands a pre-open branch identically: no dispatch, and no PR because
# pre-open-resolve.sh requires green at the LIVE branch head.
eq "$(marker a-pregreen check.codex)" "<none>" "(PREGREEN) a stale pre-open green is cleared too"

# (PREFIX) and only those two. `fixable@<old>` does not block check-set-heal's
# dispatch, so it strands nothing and is left for the fixable record to overwrite.
eq "$(marker a-prefix check.codex)" "fixable@oldprefix" "(PREFIX) a stale pre-open fixable is NOT cleared — it never blocked the dispatch"

# (POSTSTALE) the scope boundary. Post-open, the stale marker is what
# reconcile-merged-prs.sh's stale-marker arm keys on to file the re-review; clearing
# it here would take the evidence away from the arm that already heals it.
eq "$(marker a-poststale check.codex)" "exception@oldpost" "(POSTSTALE) a stale POST-open marker is left to reconcile-merged-prs.sh's stale-marker arm"
hasnt "$TMP/update.log" "a-poststale " "(POSTSTALE) no write at all against it"

# (POISON) THE REGRESSION for the P1 in review tk-bjyld. A pre-open gate excepted
# at an OLD head, with the dead review that caused it STILL OPEN, and the branch
# head since moved: exactly the state an operator produces by doing what the design
# tells them to do — fix the branch and let the head move.
#
# A review bead records no dispatch head, so before the fix this corpse answered
# the worker-lost scan again at the NEW head and re-stamped `exception@<new head>`
# before the pre-open re-arm further down could clear anything. The head move was
# consumed on every wake, the gate never re-armed, and `exception` was terminal
# FULL STOP rather than "terminal until the input changes" — the operator escape
# the design promises did not exist. Two halves are needed and both are asserted:
# suppress the re-condemnation so the re-arm runs, and RETIRE the corpse so
# check-set-heal.sh stops reading it as a signoff already in flight and can
# dispatch the replacement that raises the gate.
eq "$(marker a-poison check.codex)" "<none>" "(POISON) a stale dead review does NOT re-condemn the new head; the gate re-arms instead"
eq "$(bstatus rv-poison)" "closed" "(POISON) and the dead review is retired, so check-set-heal stops reading it as a signoff in flight"
eq "$(marker rv-poison gate_verdict_condemned)" "headpoison" "(POISON) marked as well as closed, so even a refused close cannot spend a second condemnation"
hasnt "$TMP/mail.log" "a-poison" "(POISON) re-arming is not an escalation — the operator is not re-mailed for doing what they were asked"
has "$TMP/out" "retired dead review rv-poison" "(POISON) the retirement is announced"
has "$TMP/update.log" "--force" "(POISON) bd close is assignee-gated on a dead session's bead, so the retirement takes the --force retry"

# (TWIN) the scan takes ALL the dead reviews, not just the first. It used to break
# at the first match, so a second corpse stayed open and condemned the NEXT head by
# itself — the same poisoning, one bead over. A LIVE reviewer sharing the anchor is
# never swept up in it, and with no stale exception to suppress it a first-ever
# condemnation still fires normally.
eq "$(marker a-twin check.codex)" "exception@headtwin" "(TWIN) a first-ever worker-lost condemnation still fires (no stale exception to suppress it)"
eq "$(bstatus rv-twin1)" "closed" "(TWIN) the first dead review is retired"
eq "$(bstatus rv-twin2)" "closed" "(TWIN) and so is the second — the scan no longer stops at the first"
eq "$(bstatus rv-twinlive)" "in_progress" "(TWIN) but a LIVE reviewer on the same anchor is left strictly alone"
eq "$(marker rv-twinlive gate_verdict_condemned)" "<none>" "(TWIN) and is not marked either"

# (NEVERGREEN) the safety invariant
hasnt "$TMP/update.log" "green@" "(NEVERGREEN) the pass never writes a green marker"
hasnt "$TMP/update.log" "merge_result" "(NEVERGREEN) the pass never touches the gating marker"

# ---------------------------------------------------------------------------
# Run 2 — convergence over the state run 1 produced.
# ---------------------------------------------------------------------------
: > "$TMP/update.log"; : > "$TMP/mail.log"
run_pass
hasnt "$TMP/mail.log" "a-r11" "(CONVERGE) no second mail for an exception already escalated at this head"
hasnt "$TMP/mail.log" "a-moved" "(CONVERGE) nor for the re-armed one"
hasnt "$TMP/update.log" "a-r11 " "(CONVERGE) no rewrite of a verdict already current"
eq "$(marker a-fix check.codex)" "fixable@head16" "(CONVERGE) the fixable record is stable"
hasnt "$TMP/update.log" "a-fix " "(CONVERGE) and is not rewritten every wake"
hasnt "$TMP/update.log" "a-prestale " "(CONVERGE) a re-armed pre-open gate is not re-cleared on every wake"
eq "$(marker a-capopen check.codex)" "fixable@head26" "(CONVERGE) the deferred cap stays fixable while its child is open"
hasnt "$TMP/mail.log" "a-capopen" "(CONVERGE) and still does not escalate"
hasnt "$TMP/update.log" "rv-poison " "(CONVERGE) a retired review is not re-retired on every wake"
eq "$(marker a-poison check.codex)" "<none>" "(CONVERGE) and the re-armed pre-open gate stays re-armed — the corpse is gone, so nothing re-condemns it"
hasnt "$TMP/mail.log" "a-poison" "(CONVERGE) still no escalation for it"

# ---------------------------------------------------------------------------
# Run 2b — the merge_hold lifts. The exception is already recorded and current at
# this head, so the "already excepted" path is the one taken — and it still owes
# an escalation, because run 1 deliberately did not stamp the guard while parked.
# ---------------------------------------------------------------------------
jq 'map(if .id == "a-hold" then .metadata |= del(.merge_hold) else . end)' "$TMP/beads.json" > "$TMP/b1" \
  && mv "$TMP/b1" "$TMP/beads.json"
: > "$TMP/update.log"; : > "$TMP/mail.log"
run_pass
has "$TMP/mail.log" "a-hold" "(OWED) the suppressed escalation fires once the operator hold lifts"
eq "$(marker a-hold check.codex.exception_escalated)" "head20" "(OWED) and the guard is armed only now"
eq "$(marker a-hold check.codex)" "exception@head20" "(OWED) the verdict itself is not re-written"
hasnt "$TMP/mail.log" "a-r11" "(OWED) an exception already escalated at this head is still not re-mailed"

# ---------------------------------------------------------------------------
# Run 3 — an unreadable session roster must DISABLE the worker-lost arm, not
# condemn every assignee at once.
# ---------------------------------------------------------------------------
jq 'map(if .id == "a-lost" then .metadata |= del(."check.codex") else . end)' "$TMP/beads.json" > "$TMP/b2" \
  && mv "$TMP/b2" "$TMP/beads.json"
: > "$TMP/update.log"; : > "$TMP/mail.log"
( cd "$TMP/repo" \
  && PATH="$TMP/bin:$PATH" \
     FAKE_STORE="$TMP/beads.json" FAKE_HEADS="$TMP/heads" FAKE_ROSTER="$TMP/roster" \
     FAKE_MAIL="$TMP/mail.log" FAKE_UPDATES="$TMP/update.log" FAKE_NOWRITE="$TMP/nowrite" \
     FAKE_ROSTER_BROKEN=1 \
     GC_RIG="alpha" GC_MAX_REVIEW_ROUNDS=3 GC_GATE_DEADLINE=3600 \
     bash "$SCRIPT" ) > "$TMP/out" 2>&1 || true
eq "$(marker a-lost check.codex)" "<none>" "(NOROSTER) an unreadable roster does not condemn a dead-looking assignee"
has "$TMP/out" "roster unreadable" "(NOROSTER) and the disabled arm is announced"

# ---------------------------------------------------------------------------
# Run 4 — the last remediation child closes. Deferring exhaustion while a round
# was in flight must not SUPPRESS it: with nothing left coming, the completed
# rounds are past the cap and the exception fires on the very next wake. Without
# this the (CAPOPEN) fix would be indistinguishable from disabling R11.
# ---------------------------------------------------------------------------
jq 'map(if .id == "k-co4" then .status = "closed" else . end)' "$TMP/beads.json" > "$TMP/b3" \
  && mv "$TMP/b3" "$TMP/beads.json"
: > "$TMP/update.log"; : > "$TMP/mail.log"
run_pass
eq "$(marker a-capopen check.codex)" "exception@head26" "(CAPCLOSE) once the last round closes, exhaustion fires — the deferral was not a suppression"
has "$TMP/out" "attempts-exhausted" "(CAPCLOSE) with the reason that names the trigger"
has "$TMP/mail.log" "a-capopen" "(CAPCLOSE) and the operator is mailed then, not before"
eq "$(marker a-capopen check.codex.attempts)" "4@head26" "(CAPCLOSE) the stamped count is the COMPLETED rounds"

# ---------------------------------------------------------------------------
# The verdict contract itself, extracted and exercised as the pass runs it.
# ---------------------------------------------------------------------------
sed -n '/# >>> gate-verdict-contract/,/# <<< gate-verdict-contract/p' "$SCRIPT" > "$TMP/contract.sh"
# shellcheck disable=SC1091
. "$TMP/contract.sh"
eq "$(gate_verdict 'green@abc' abc)"     "ok"          "(CONTRACT) green at the live head is ok"
eq "$(gate_verdict 'green@abc' xyz)"     "unevaluated" "(CONTRACT) a head move drops OK to unevaluated"
eq "$(gate_verdict 'fixable@abc' abc)"   "fixable"     "(CONTRACT) fixable at the live head"
eq "$(gate_verdict 'fixable@abc' xyz)"   "unevaluated" "(CONTRACT) a head move drops fixable too"
eq "$(gate_verdict 'exception@abc' abc)" "exception"   "(CONTRACT) exception at the live head"
eq "$(gate_verdict 'exception@abc' xyz)" "unevaluated" "(CONTRACT) a head move re-arms an exception"
eq "$(gate_verdict '' abc)"              "unevaluated" "(CONTRACT) an absent marker is unevaluated, not unmappable"
eq "$(gate_verdict 'weird@abc' abc)"     "unmappable"  "(CONTRACT) an unknown verb is unmappable — R12"
eq "$(gate_verdict 'green' abc)"         "unmappable"  "(CONTRACT) a verb with no head is unmappable"
eq "$(gate_verdict 'green@abc' '')"      "unevaluated" "(CONTRACT) with no live head nothing can be shown current"
eq "$(gate_members 'codex, approval ,none')" "codex"   "(CONTRACT) approval and the none sentinel are not marker-backed"
eq "$(gate_members 'CODEX')"             "CODEX"       "(CONTRACT) case is preserved — merge-skill keys the marker as written"
eq "$(gate_members 'none')"              ""            "(CONTRACT) a gateless set declares no marker-backed gate"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
