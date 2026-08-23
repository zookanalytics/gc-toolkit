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
#   (DEPFAIL)  the convoy read fails CLOSED at both levels. A dep listing that did
#              not read, and a convoy bead that did not read, each reduce to the
#              same empty answer a dep-less/target-less bead gives — so taken at
#              face value they stamp the repository default over an owned convoy's
#              integration branch AND leave gate 6 with no convoy to test for
#              liveness. Both are reported, neither is handed off
#   (LIVEROOT) THE guard: a candidate whose molecule root records a LIVE session is
#              left alone. Verified live on tk-f69ay itself — a work bead is open
#              with assignee=null and no gc.routed_to for the WHOLE time its polecat
#              works it, so "unassigned" describes every in-flight molecule too and
#              only liveness separates a strand from work in progress
#   (LIVESTEP) the second liveness signal: the root records no live session, but one
#              of its live STEP beads is held by one — a re-claimed or re-nudged
#              molecule wears that shape
#   (LIVEMISS) liveness gates the REFUSALS too, not just the handoff: a live polecat
#              that has not pushed yet — `branch` stamped by workspace-setup, nothing
#              on origin — is left completely alone. The unpublished-branch refusal
#              used to return before liveness was ever consulted, so every
#              implementation outlasting the age gate was marked as vanished work
#   (RETRACT)  a `<branch>@missing` marker the branch now DISPROVES is cleared, on
#              any live bead carrying one — including a bead that has since been
#              handed to the refinery and so left the candidate set for good, which
#              is where the false marker would otherwise live forever
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
#   (REWORK)   a pre-open rework CHILD is not a strand. It wears the candidate
#              shape exactly — open, unassigned, unrouted, `branch` stamped —
#              because every field the filter rejects on lives on its
#              `parent-child` PARENT: an anchor at merge_result=pre_open_gate
#              carrying check.codex=fixable@<oid>. The child is left completely
#              alone, so `acting()` still holds on the anchor and its review gate
#              stays suppressed. A parent carrying NEITHER marker protects nothing,
#              and an unreadable parent fails closed — both when the listing
#              errors and when it returns a payload the filter cannot evaluate
#   (ONCE)     the recovery stamp is READ BACK, so a declined handoff cannot
#              re-arm. The refinery's hand-back restores the candidate shape and
#              bumps `updated_at`, which is all the age gate reads — so without a
#              once-marker the decline sets the loop PERIOD instead of breaking the
#              loop. Keyed by EQUALITY on `<branch>@<tip>`, so a branch that has
#              genuinely moved is still rescued
#   (SKIPSET)  the non-candidates, each excluded by exactly one field: an assignee,
#              a gc.routed_to, a merge_result, a recorded PR, duplicate_of, a live
#              merge_hold, and a non-impl task_kind
#   (ROSTER)   an unreadable session roster hands off NOTHING — an unread roster
#              makes every running polecat look dead
#   (BEADS)    an unreadable live-bead listing does the same — without it no
#              molecule can be proved husked
#   (BOUND)    a bead already carrying the flag for this (branch, tip) is counted
#              but not re-warned and not re-mailed
#   (ESCALATE) that bound is by (branch, tip) AND escalation class. Every refusal
#              writes the same marker, but only one of them summons a human, so a
#              quiet marker left by a transient read failure must not cancel the
#              escalation a later cycle owes — while an already-escalated tip is
#              neither re-escalated nor re-warned by a quieter refusal
#   (FAILED)   a handoff whose assignee does not read back exits NON-ZERO — a silent
#              exit 0 over a failed write is how this class of bug hides
#   (VERIFY)   a branch/target write that reports success and is NOT durable stops
#              the handoff BEFORE the assignee is written: an assignee that sticks
#              over a target that did not takes the bead out of the candidate set
#              (it is no longer unassigned) AND hands the refinery a branch to
#              rebase onto a missing base — an integration member onto main
#   (INPROG)   an in_progress strand is handed over as status=open. The refinery's
#              find-work polls `--assignee=$GC_AGENT --status=open`, so an
#              in_progress handoff is assigned to an actor that never polls it and,
#              being assigned, is no longer retryable by this pass either
#   (RELEASE)  a handoff whose fields are rolled back AFTER the assignee sticks
#              releases our own assignee, restoring the candidate shape so the next
#              cycle retries the whole handoff
#   (DRY)      --dry-run selects the same beads and issues no write at all
#   (NOCLOSE)  the pass never closes a bead: only the refinery closes a work bead,
#              after verifying the merge. The one status it writes is `open` — what
#              makes the bead visible to the refinery at all
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
  {"id":"b-mid-impl","status":"open","assignee":"","updated_at":"__OLD__",
   "metadata":{"branch":"polecat/b-mid-impl"}},
  {"id":"b-retract","status":"open","assignee":"","updated_at":"__OLD__",
   "metadata":{"branch":"polecat/b-retract","stranded_branch_flagged":"polecat/b-retract@missing"}},
  {"id":"b-handed","status":"open","assignee":"gc-toolkit/gc-toolkit.refinery","updated_at":"__OLD__",
   "metadata":{"branch":"polecat/b-handed","stranded_branch_flagged":"polecat/b-handed@missing"}},
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
  {"id":"b-metafail","status":"open","assignee":"","updated_at":"__OLD__",
   "metadata":{"branch":"polecat/b-metafail"}},
  {"id":"b-inprog","status":"in_progress","assignee":"","updated_at":"__OLD__",
   "metadata":{"branch":"polecat/b-inprog"}},
  {"id":"b-clobber","status":"open","assignee":"","updated_at":"__OLD__",
   "metadata":{"branch":"polecat/b-clobber"}},
  {"id":"b-depfail","status":"open","assignee":"","updated_at":"__OLD__",
   "metadata":{"branch":"polecat/b-depfail"}},
  {"id":"b-convfail","status":"open","assignee":"","updated_at":"__OLD__",
   "metadata":{"branch":"polecat/b-convfail"}},
  {"id":"b-offered","status":"open","assignee":"","updated_at":"__OLD__",
   "metadata":{"branch":"polecat/b-offered"}},
  {"id":"b-heldoffer","status":"open","assignee":"","updated_at":"__OLD__",
   "metadata":{"branch":"polecat/b-heldoffer"}},

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
   "metadata":{"gc.root_bead_id":"r-strand","gc.step_ref":"mol-polecat-work.load-context"}},
  {"id":"r-offered","status":"in_progress","assignee":"",
   "metadata":{"gc.input_convoy_id":"c-offered","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}},
  {"id":"r-heldoffer","status":"in_progress","assignee":"",
   "metadata":{"gc.input_convoy_id":"c-heldoffer","gc.routed_to":"gc-toolkit/gc-toolkit.polecat",
               "gc.session_name":"gc-toolkit__polecat-lx-dead"}}
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
b-mid-impl|c-live
b-retract|c-live
b-pr|c-strand
b-ghfail|c-strand
b-nobranch|c-strand
b-nobase|c-strand
b-behind|c-strand
b-fresh|c-strand
b-flagged|c-strand
b-fail|c-strand
b-metafail|c-strand
b-inprog|c-strand
b-clobber|c-strand
b-depfail|c-strand
b-convfail|c-unreadable
b-offered|c-offered
b-heldoffer|c-heldoffer
b-rework|c-strand
b-plainkid|c-strand
b-parentfail|c-strand
b-parentshape|c-strand
b-redo|c-strand
D

# convoy -> metadata.target (only the owned convoy carries one)
cat > "$TMP/convoy_targets" <<'C'
c-conv|integration/gc-2026
C

# bead -> its `parent-child` PARENT, and the two markers that decide whether that
# parent is carrying the child's next move: `child|parent|merge_result|check.codex`,
# with `-` meaning the key is absent. This is what `gc bd dep list <id>
# --direction=down --json` answers — the parent-child edge sits on the CHILD with
# the parent in the depends-on slot, so `--direction=up` (which the convoy gate
# reads) does NOT see it. b-plainkid is the discriminator: a parent carrying neither
# marker protects nothing, or the gate would be "any bead with a parent is exempt".
cat > "$TMP/parents" <<'PP'
b-rework|b-anchor|pre_open_gate|fixable@sha-anchor
b-plainkid|b-plainparent|-|-
PP

# branch -> sha on origin. A branch absent here does not exist on origin — which is
# what a live polecat's branch looks like right up until it pushes (b-mid-impl), and
# what the two @missing-flagged beads looked like when they were flagged. b-retract
# and b-handed have since pushed; b-flagged has not.
cat > "$TMP/remote" <<'R'
main|sha-main
integration/gc-2026|sha-int
polecat/b-retract|sha-retract
polecat/b-handed|sha-handed
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
polecat/b-metafail|sha-metafail
polecat/b-inprog|sha-inprog
polecat/b-clobber|sha-clobber
polecat/b-depfail|sha-depfail
polecat/b-convfail|sha-convfail
polecat/b-offered|sha-offered
polecat/b-heldoffer|sha-heldoffer
polecat/b-anchor|sha-anchor
polecat/b-plainkid|sha-plainkid
polecat/b-parentfail|sha-parentfail
polecat/b-parentshape|sha-parentshape
polecat/b-redo|sha-redo
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
sha-metafail|1
sha-inprog|2
sha-clobber|1
sha-depfail|1
sha-convfail|1
sha-offered|2
sha-heldoffer|2
sha-anchor|1
sha-plainkid|1
sha-parentfail|1
sha-parentshape|1
sha-redo|1
sha-redo2|3
A

# branch -> the `gh pr list` payload for it. Absent -> [] (no PR).
cat > "$TMP/prs" <<'P'
polecat/b-pr|[{"number":297,"state":"OPEN"}]
P

: > "$TMP/updates"
: > "$TMP/mail"
: > "$TMP/nudges"
: > "$TMP/state"

# --- gc stub ------------------------------------------------------------------
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
# The stub keeps DURABLE state: every write is recorded to $FAKE_STATE and `show`
# reduces it (last write wins), so a readback sees exactly what the writes did or
# did not apply. That is the whole point of the verified handoff — a `gc bd update`
# that reports success and is not durable has to be representable, or the guard
# against it cannot be tested.
state_of() { # <id> <key>
  awk -F'\t' -v i="$1" -v k="$2" '$1==i && $2==k{v=$3} END{print v}' "$FAKE_STATE"
}
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
        # c-unreadable models the nastier half of the convoy read: rc=0 with a
        # payload that is NOT the expected array. `.[0].metadata.target` reduces it
        # to the same empty string a convoy without a target produces, so only a
        # type check can tell "this convoy lands on main" from "this convoy did not
        # answer".
        if [ "$id" = "c-unreadable" ]; then
          printf '{"error":"resolving c-unreadable: connection refused","schema_version":1}\n'
          exit 0
        fi
        t=$(awk -F'|' -v c="$id" '$1==c{print $2; exit}' "$FAKE_CONVOY_TARGETS")
        if [ -n "$t" ]; then jq -n --arg t "$t" '[{metadata:{target:$t}}]'; else
          jq -n --arg s "$(state_of "$id" status)" --arg a "$(state_of "$id" assignee)" \
                --arg b "$(state_of "$id" branch)" --arg g "$(state_of "$id" target)" \
            '[{status:$s, assignee:$a, metadata:{branch:$b, target:$g}}]'
        fi ;;
      update)
        printf 'gc bd update %s\n' "$*" >> "$FAKE_UPDATES"
        id="$1"; shift
        pending=""
        for arg in "$@"; do
          if [ "$pending" = "meta" ]; then
            pending=""
            # b-metafail models a METADATA write that reports success and is not
            # durable — the case the pre-assign readback exists to catch.
            [ "$id" = "b-metafail" ] && continue
            printf '%s\t%s\t%s\n' "$id" "${arg%%=*}" "${arg#*=}" >> "$FAKE_STATE"
            continue
          fi
          case "$arg" in
            --set-metadata) pending="meta" ;;
            --status=*)
              printf '%s\t%s\t%s\n' "$id" "status" "${arg#--status=}" >> "$FAKE_STATE" ;;
            --assignee=*)
              # b-fail models an ASSIGNEE write that reports success and is not durable.
              [ "$id" = "b-fail" ] && continue
              printf '%s\t%s\t%s\n' "$id" "assignee" "${arg#--assignee=}" >> "$FAKE_STATE"
              # b-clobber models a ROLLBACK: the assignee sticks while the target
              # stamped just before it is lost. Only the POST-assign readback can
              # see this one — the pre-assign check passed on the same bead.
              [ "$id" = "b-clobber" ] \
                && printf '%s\t%s\t%s\n' "$id" "target" "" >> "$FAKE_STATE" ;;
          esac
        done ;;
      dep)
        # `dep list <id> --direction=up --json`   -> the convoys that TRACK the bead
        # `dep list <id> --direction=down --json` -> its `parent-child` PARENT
        id="$2"
        # b-depfail models the dep listing FAILING the way bd really fails it: an
        # error object on stdout with rc=1, which `.[]?.id` reduces to the same
        # empty string a dep-less bead produces.
        if [ "$id" = "b-depfail" ]; then
          printf '{"error":"resolving b-depfail: connection refused","schema_version":1}\n'
          exit 1
        fi
        case " $* " in
          *--direction=down*)
            # b-parentfail models the same failure one edge over: the parent listing
            # that did not read. An unread parent is not proof that no anchor stands
            # behind the bead, so it must not be taken as "no parent".
            if [ "$id" = "b-parentfail" ]; then
              printf '{"error":"resolving b-parentfail: connection refused","schema_version":1}\n'
              exit 1
            fi
            # b-parentshape is the NASTIER half, the one rc alone cannot catch: the
            # same error object at rc=0. `.[]?` reduces it to the very empty output a
            # parentless bead gives, so only a shape check tells "this bead has no
            # anchor" from "the parent listing did not answer".
            if [ "$id" = "b-parentshape" ]; then
              printf '{"error":"resolving b-parentshape: connection refused","schema_version":1}\n'
              exit 0
            fi
            prow=$(awk -F'|' -v b="$id" '$1==b{print; exit}' "$FAKE_PARENTS")
            if [ -z "$prow" ]; then printf '[]\n'; exit 0; fi
            pid=$(printf '%s' "$prow" | cut -d'|' -f2)
            pmr=$(printf '%s' "$prow" | cut -d'|' -f3)
            pcx=$(printf '%s' "$prow" | cut -d'|' -f4)
            jq -n --arg p "$pid" --arg mr "$pmr" --arg cx "$pcx" \
              '[{id: $p, dependency_type: "parent-child", status: "open",
                 metadata: ((if $mr == "-" then {} else {merge_result: $mr} end)
                            + (if $cx == "-" then {} else {"check.codex": $cx} end))}]'
            exit 0 ;;
        esac
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
export FAKE_PARENTS="$TMP/parents"
export FAKE_AHEAD="$TMP/ahead" FAKE_PRS="$TMP/prs" FAKE_UPDATES="$TMP/updates"
export FAKE_MAIL="$TMP/mail" FAKE_NUDGES="$TMP/nudges" FAKE_STATE="$TMP/state"
export FAKE_OLD_EPOCH="$OLD_EPOCH" FAKE_FRESH_EPOCH="$FRESH_EPOCH"
export GC_RIG="gc-toolkit" GC_AGENT="gc-toolkit/gc-toolkit.witness"

REFINERY="gc-toolkit/gc-toolkit.refinery"
# `run_as` takes the script to drive so the mutation cases below can run a copy of
# the pass with one guard cut out of it, against these same fixtures.
run_as() { local s="$1"; shift; "$s" --refinery "$REFINERY" --root "$TMP/repo" "$@" 2> "$TMP/err" > "$TMP/out"; }
run() { run_as "$SCRIPT" "$@"; }

# Cut one guard out of the pass and prove the cut LANDED. A mutation test whose sed
# silently matched nothing is a tautology — it asserts the fixture, not the guard.
MUTANT_PATH=""
mutant() { # <name> <sed-expression> -> sets MUTANT_PATH
  local name="$1"
  local expr="$2"
  local out="$TMP/mutants/$name.sh"
  mkdir -p "$TMP/mutants"
  sed -e "$expr" "$SCRIPT" > "$out"
  chmod +x "$out"
  if cmp -s "$SCRIPT" "$out"; then
    bad "(MUTANT) $name: the guard-removal expression matched nothing — the case below would prove nothing"
  else
    ok "(MUTANT) $name: the guard is cut out of the mutant"
  fi
  MUTANT_PATH="$out"
}

# --- pass 1: --dry-run --------------------------------------------------------
set +e
run --dry-run
DRY_RC=$?
set -e
eq "$DRY_RC" "0" "(DRY) dry run exits 0"
has "DRY-RUN would hand b-strand" "$TMP/out" "(DRY) selects the stranded bead"
has "DRY-RUN would hand b-conv" "$TMP/out" "(DRY) selects the convoy-targeted bead"
hasnt "b-live" "$TMP/out" "(DRY) does not select the live molecule"
# (OFFER) tk-vie5k. A molecule that is routed to a pool and has never been claimed
# has NO session to answer for it — that is what a queued pool offer looks like, and
# under pool saturation it is what every waiting rework child looks like. Salvage
# used to read the absent session as "no landing path" and hand the work back out
# from under a dispatch that was simply waiting its turn.
hasnt "would hand b-offered" "$TMP/out" \
      "(OFFER) a routed, never-claimed molecule is a pending offer, not a husk"
# (OFFER) the other side of the same clause, and the reason it is not just
# `claimable`: a molecule whose session is stamped HAS been claimed, and a husk keeps
# its route (clearing it is what quiescing does). Widen the clause to any routed root
# and this bead stops being salvageable — which is every husk in the store.
has "DRY-RUN would hand b-heldoffer" "$TMP/out" \
    "(OFFER) a routed molecule whose stamped session is dead is still a husk"
has "retracting the stale" "$TMP/out" "(RETRACT) --dry-run says what it would retract"
# Covers the retraction as much as the handoff: it is the one write in this pass
# that fires on beads the loop below never even examines.
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
has "gc bd update b-strand --status=open --assignee=gc-toolkit/gc-toolkit.refinery" "$TMP/updates" \
  "(STRAND) hands the bead to the refinery, open so the refinery's find-work sees it"
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

# (LIVEMISS): the ordering. b-mid-impl is a live polecat's bead in the state every
# implementation passes through — `branch` stamped by workspace-setup, nothing on
# origin until it pushes tens of minutes later — so it is BOTH unpublished and alive.
# Before liveness ran first, the unpublished-branch refusal returned before the guard
# was ever consulted and left `<branch>@missing` on healthy work, asserting that
# published work had vanished on a branch that had simply not been pushed yet.
hasnt "gc bd update b-mid-impl" "$TMP/updates" \
  "(LIVEMISS) a live polecat's unpushed branch is never flagged"
hasnt "b-mid-impl" "$TMP/err" "(LIVEMISS) nor warned about"
hasnt "b-mid-impl" "$TMP/mail" "(LIVEMISS) nor mailed about"
# It is not merely un-marked but un-REPORTED: the count below is unchanged by it,
# which is what separates "silently suppressed" from "never reached the refusal".
has "6 reported" "$TMP/out" "(LIVEMISS) and not counted as a refusal either"

# (RETRACT): a marker the branch now disproves is cleared. b-retract still looks like
# a candidate (its molecule is live, so nothing else happens to it) and b-handed does
# NOT — it was flagged mid-implementation and then handed to the refinery, which is
# the shape the marker was actually observed on, and an assignee takes a bead out of
# the candidate set for good.
has "gc bd update b-retract --unset-metadata stranded_branch_flagged" "$TMP/updates" \
  "(RETRACT) a stale @missing marker is retracted"
hasnt "gc bd update b-retract --status" "$TMP/updates" \
  "(RETRACT) retracting is not recovering — the live bead is not handed off"
has "gc bd update b-handed --unset-metadata stranded_branch_flagged" "$TMP/updates" \
  "(RETRACT) including on a bead that has left the candidate set"
has "retracting the stale 'polecat/b-handed@missing' marker" "$TMP/out" \
  "(RETRACT) and says which claim it is withdrawing"
hasnt "gc bd update b-flagged" "$TMP/updates" \
  "(RETRACT) a marker whose branch is still absent from origin stands"

# (DEADROOT): the converse of LIVEROOT — b-strand's root session is absent from the
# roster, and it IS handed off (asserted above). Assert the discrimination directly:
# exactly five beads reach an assignee write — b-strand, b-conv, b-inprog, plus the
# two whose write is ATTEMPTED and then does not survive the readback (b-fail, whose
# assignee is not durable, and b-clobber, whose target is rolled back under it). Both
# belong in this count precisely because the pass DECIDED they were stranded.
# b-metafail is deliberately NOT here: its handoff is refused one step earlier.
# b-heldoffer joins them (tk-vie5k): its molecule IS routed to a pool, but the root
# carries a stamped session that is dead, so it has been claimed and abandoned — a
# husk, and husks keep their route. It is the negative control for the pending-offer
# clause; widen that clause to "routed" and this count drops back to six.
eq "$(grep -c 'assignee=gc-toolkit/gc-toolkit.refinery' "$TMP/updates")" "6" \
  "(DEADROOT) exactly the six dead-molecule beads reach a handoff"

# (VERIFY): the branch/target write reported success and was not durable, so the
# assignee is never written — the bead stays unassigned, i.e. still a candidate.
has "gc bd update b-metafail --set-metadata branch=polecat/b-metafail" "$TMP/updates" \
  "(VERIFY) the fields the refinery merges by are stamped first"
hasnt "gc bd update b-metafail --status" "$TMP/updates" \
  "(VERIFY) a metadata write that did not stick never reaches the assignee write"
has "the fields the refinery merges by did NOT stick" "$TMP/err" \
  "(VERIFY) and says why it refused"
has "b-metafail" "$TMP/err" "(VERIFY) naming the bead it left stranded"

# (INPROG): the refinery polls --status=open, so every handoff sets it — in the same
# write as the assignee, exactly as the done sequence does.
has "gc bd update b-inprog --status=open --assignee=gc-toolkit/gc-toolkit.refinery" \
  "$TMP/updates" "(INPROG) an in_progress strand is handed over as status=open"
eq "$(grep -c -- '--status=open --assignee=gc-toolkit/gc-toolkit.refinery' "$TMP/updates")" "6" \
  "(INPROG) every handoff sets status=open in the same write as the assignee"
has "RECOVERED b-inprog" "$TMP/out" "(INPROG) and the in_progress strand is recovered"

# (RELEASE): the target is rolled back AFTER the assignee sticks. Only the
# post-assign readback can see it, and the repair is to release OUR OWN assignee so
# the bead matches the candidate shape again next cycle.
has "gc bd update b-clobber --assignee=$" "$TMP/updates" \
  "(RELEASE) a clobbered handoff releases the assignee it just set"
has "handoff did NOT stick" "$TMP/err" "(RELEASE) and reports the mismatch"
hasnt "b-clobber could not be released" "$TMP/err" \
  "(RELEASE) a release that reads back clean needs no hand-repair warning"
hasnt "RECOVERED b-clobber" "$TMP/out" "(RELEASE) and it is never counted as recovered"

# (DEPFAIL): the two unreadable convoy facts. Both beads are otherwise PERFECT
# candidates — pushed, ahead, no PR, no live molecule — so the only thing that can
# hold either back is the read check itself. The assertion that matters is the
# absence of a target stamp: `target=main` on b-convfail is the un-retryable wrong
# handoff (an owned-convoy member recovered into a main PR, past the convoy
# boundary), and the pre-assign readback would only confirm that the wrong value
# stuck.
has "stranded_branch_flagged=polecat/b-depfail@sha-depfail" "$TMP/updates" \
  "(DEPFAIL) an unreadable dependency list flags the bead"
hasnt "gc bd update b-depfail --set-metadata branch=" "$TMP/updates" \
  "(DEPFAIL) and never stamps a guessed target on it"
hasnt "gc bd update b-depfail --status" "$TMP/updates" "(DEPFAIL) nor hands it off"
has "its upstream dependency list could not be read" "$TMP/err" \
  "(DEPFAIL) explains the refusal"
has "stranded_branch_flagged=polecat/b-convfail@sha-convfail" "$TMP/updates" \
  "(DEPFAIL) an unreadable convoy bead flags the bead too"
hasnt "gc bd update b-convfail --set-metadata branch=" "$TMP/updates" \
  "(DEPFAIL) an unread convoy never falls back to the repository default"
hasnt "gc bd update b-convfail --status" "$TMP/updates" \
  "(DEPFAIL) and the bead is never handed off on a guessed target"
has "its upstream convoy 'c-unreadable' could not be read" "$TMP/err" \
  "(DEPFAIL) naming the convoy that did not answer"

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
# 6 reported = b-ghfail + b-nobranch + b-nobase + b-flagged + b-depfail + b-convfail.
# The already-flagged bead is COUNTED (so a genuinely stuck bead never disappears
# from the summary) while issuing no second warning, marker or mail.
has "6 reported" "$TMP/out" "(BOUND) an already-flagged bead is still counted"
hasnt "gc bd update b-flagged" "$TMP/updates" "(BOUND) but is not re-marked"
hasnt "b-flagged" "$TMP/mail" "(BOUND) and not re-mailed"

# (SKIPSET): every non-candidate, each held back by exactly one field.
for x in x-assigned x-routed x-stamped x-pr x-dup x-hold x-review; do
  hasnt "gc bd update $x" "$TMP/updates" "(SKIPSET) $x is not a candidate"
done

# (NOCLOSE): the pass has no close path. `open` is the ONLY status it ever writes —
# what makes a recovered bead visible to the refinery — and closing one is the
# refinery's job, after it has verified the merge.
hasnt "bd close" "$TMP/updates" "(NOCLOSE) never closes a bead"
hasnt "\-\-status=closed" "$TMP/updates" "(NOCLOSE) never closes one by status either"
eq "$(grep -o -- '--status=[a-z_]*' "$TMP/updates" | sort -u | tr '\n' ' ')" "--status=open " \
  "(NOCLOSE) the only status it writes is open"
hasnt "close" "$TMP/nudges" "(NOCLOSE) never asks anyone else to close one"

# The refinery is nudged once, and only because this pass is not the refinery.
eq "$(grep -c 'gc-toolkit.refinery' "$TMP/nudges")" "1" "(STRAND) nudges the refinery once"

# --- pass 3: fail-safes -------------------------------------------------------
: > "$TMP/updates"; : > "$TMP/mail"; : > "$TMP/state"
set +e
FAKE_SESSIONS_FAIL=1 run
ROSTER_RC=$?
set -e
eq "$ROSTER_RC" "0" "(ROSTER) an unreadable roster is not a pass failure"
has "FAIL-SAFE" "$TMP/err" "(ROSTER) says it is failing safe"
hasnt "assignee=gc-toolkit/gc-toolkit.refinery" "$TMP/updates" \
  "(ROSTER) hands off nothing while the roster is unreadable"

: > "$TMP/updates"; : > "$TMP/mail"; : > "$TMP/state"
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
: > "$TMP/updates"; : > "$TMP/mail"; : > "$TMP/state"
set +e
FAKE_CANDIDATES="$TMP/candidates2.json" run
set -e
hasnt "gc bd update b-strand" "$TMP/updates" "(IDEM) a recovered bead is not recovered twice"
# Trailing space, like the b-pr / b-live assertions above: `b-conv` is a PREFIX of
# `b-convfail`, and an unanchored match would read that bead's flag write as a
# second recovery of this one.
hasnt "gc bd update b-conv " "$TMP/updates" "(IDEM) nor is the convoy-targeted one"

# --- pass 5: an escalating refusal is never silenced by a quieter one ---------
# (ESCALATE) `report_only` writes the SAME `branch@tip` marker for a transient read
# that did not answer (the dep listing, a convoy bead, `gh pr list`) as for the one
# refusal that mails the mayor. Suppressing on the tip alone therefore let a blip in
# one cycle cancel the escalation in the next: mark `branch@tip` because the dep list
# failed, then read it fine and discover the target branch is missing, and the
# escalating refusal returns at the suppression check having mailed nobody — branch
# still stranded, human-facing signal gone, nothing left but a summary count. Model
# exactly that ordering: b-nobase (missing target -> escalates) arrives already
# carrying the QUIET marker at its current tip.
jq -c 'map(if .id == "b-nobase"
           then .metadata.stranded_branch_flagged = "polecat/b-nobase@sha-nobase"
           else . end)' \
  "$TMP/candidates.json" > "$TMP/candidates3.json"
: > "$TMP/updates"; : > "$TMP/mail"; : > "$TMP/state"; : > "$TMP/nudges"
set +e
FAKE_CANDIDATES="$TMP/candidates3.json" run
set -e
has "STRANDED BRANCH: b-nobase" "$TMP/mail" \
  "(ESCALATE) a quiet same-tip marker does not cancel the escalation"
has "would land on 'integration/gone'" "$TMP/err" \
  "(ESCALATE) and the refusal is warned rather than swallowed"
has "stranded_branch_flagged=polecat/b-nobase@sha-nobase#escalated" "$TMP/updates" \
  "(ESCALATE) the marker is upgraded to record that a human was summoned"
# (RETRACT) only the `@missing` class is withdrawn. Every other marker names the TIP
# it was written at, so it expires on its own when the branch moves — and b-nobase's
# refusal (a target branch that is not on origin) is about something the branch's own
# publication says nothing about.
hasnt "gc bd update b-nobase --unset-metadata" "$TMP/updates" \
  "(RETRACT) a marker naming a real tip is never retracted"

# The bound itself survives: one escalation per (branch, tip), and an escalated tip
# also silences a QUIETER refusal at the same tip — the human is already looking at
# that commit, so a lower-class warning about it adds noise and no signal. Both
# beads are still COUNTED, exactly as (BOUND) requires of a suppressed report.
jq -c 'map(if .id == "b-nobase"
           then .metadata.stranded_branch_flagged = "polecat/b-nobase@sha-nobase#escalated"
           elif .id == "b-depfail"
           then .metadata.stranded_branch_flagged = "polecat/b-depfail@sha-depfail#escalated"
           else . end)' \
  "$TMP/candidates.json" > "$TMP/candidates4.json"
: > "$TMP/updates"; : > "$TMP/mail"; : > "$TMP/state"; : > "$TMP/nudges"
set +e
FAKE_CANDIDATES="$TMP/candidates4.json" run
set -e
hasnt "STRANDED BRANCH: b-nobase" "$TMP/mail" \
  "(ESCALATE) but the same tip is never escalated twice"
hasnt "gc bd update b-nobase" "$TMP/updates" "(ESCALATE) nor re-marked"
hasnt "would land on 'integration/gone'" "$TMP/err" "(ESCALATE) nor re-warned"
hasnt "gc bd update b-depfail" "$TMP/updates" \
  "(ESCALATE) an escalated tip suppresses a quieter refusal at the same tip too"
has "6 reported" "$TMP/out" "(ESCALATE) every suppressed refusal is still counted"

# --- pass 6: a rework child is queued, not stranded --------------------------
# (REWORK) The shape that produced this guard (tk-6tlcu, live on tk-kbb8s/tk-y3tks):
# the refinery's pre-open gate found fixable findings, filed a rework CHILD, and
# parked the anchor. The child is open, unassigned, unrouted and carries `branch` —
# the candidate shape, in full — because `merge_result`, the PR fields and the holds
# all live on the anchor. Grabbing it does more than waste a handoff: the assignee
# write breaks `gc.execution_routed_to != "" AND assignee == ""`, which is the only
# way a queued child satisfies check-set-heal's `acting()`, so each grab
# un-suppresses the anchor's review gate and burns a round against an unchanged head.
cat > "$TMP/candidates-rework.json" <<JSON
[
  {"id":"b-rework","status":"open","assignee":"","updated_at":"__OLD__",
   "metadata":{"branch":"polecat/b-anchor","gc.routed_to":"",
               "gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat"}},
  {"id":"b-plainkid","status":"open","assignee":"","updated_at":"__OLD__",
   "metadata":{"branch":"polecat/b-plainkid"}},
  {"id":"b-parentfail","status":"open","assignee":"","updated_at":"__OLD__",
   "metadata":{"branch":"polecat/b-parentfail"}},
  {"id":"b-parentshape","status":"open","assignee":"","updated_at":"__OLD__",
   "metadata":{"branch":"polecat/b-parentshape"}}
]
JSON
sed -i -e "s#__OLD__#$OLD_ISO#g" "$TMP/candidates-rework.json"

: > "$TMP/updates"; : > "$TMP/mail"; : > "$TMP/state"; : > "$TMP/nudges"
set +e
FAKE_CANDIDATES="$TMP/candidates-rework.json" run
set -e
# Not merely "not handed off" but NOT WRITTEN TO AT ALL, which is the property the
# guard exists for: `gc.execution_routed_to` set with the assignee still empty is the
# only way a queued child satisfies check-set-heal's `acting()`, so any write that
# lands an assignee on it un-suppresses the anchor's review gate.
hasnt "b-rework" "$TMP/updates" \
  "(REWORK) a rework child whose anchor is parked is never written to — so acting() still holds on that anchor"
hasnt "b-rework" "$TMP/mail" "(REWORK) nor is a human summoned about it"
has "b-rework is a rework child of b-anchor (merge_result=pre_open_gate, check.codex=fixable@sha-anchor)" \
  "$TMP/out" "(REWORK) and the refusal names the anchor and both markers"
# The discriminator: a parent carrying NEITHER marker protects nothing, or the gate
# would read as "any bead with a parent is exempt" and strand every child forever.
has "gc bd update b-plainkid --status=open --assignee=$REFINERY" "$TMP/updates" \
  "(REWORK) a child whose parent carries neither marker is still recovered"
# And the read itself fails closed, exactly as the convoy listing above does.
has "stranded_branch_flagged=polecat/b-parentfail@sha-parentfail" "$TMP/updates" \
  "(REWORK) an unreadable parent listing flags the bead"
hasnt "gc bd update b-parentfail --assignee" "$TMP/updates" \
  "(REWORK) and never hands it off on an unread parent"
has "its parent-child parent could not be established" "$TMP/err" \
  "(REWORK) explaining the refusal"
# Both halves of the read, exactly as (DEPFAIL) covers both halves of the convoy
# read: rc=1 above, and here an error object at rc=0 — which `.[]?` reduces to the
# same empty answer a parentless bead gives. Failing open on it would grab the very
# bead this gate exists to protect.
has "stranded_branch_flagged=polecat/b-parentshape@sha-parentshape" "$TMP/updates" \
  "(REWORK) a parent listing that reads but does not EVALUATE flags the bead too"
hasnt "gc bd update b-parentshape --assignee" "$TMP/updates" \
  "(REWORK) and is never taken for 'this bead has no anchor'"

# MUTATION: cut the parent walk out and the same fixture must be grabbed. Without
# this the case above would also pass against a pass that skips b-rework for some
# unrelated reason — a fixture that is not a candidate at all proves nothing.
# shellcheck disable=SC2016  # the $ is sed's, not the shell's — single quotes are required
mutant no-parent-walk 's/if \[ -n "\$PARENT_GUARD" \]; then/if false; then/'
MUT_PARENT="$MUTANT_PATH"
: > "$TMP/updates"; : > "$TMP/mail"; : > "$TMP/state"; : > "$TMP/nudges"
set +e
FAKE_CANDIDATES="$TMP/candidates-rework.json" run_as "$MUT_PARENT"
set -e
has "gc bd update b-rework --status=open --assignee=$REFINERY" "$TMP/updates" \
  "(REWORK) MUTANT: with the parent walk removed the rework child IS grabbed"

# --- pass 7: a declined handoff does not re-arm ------------------------------
# (ONCE) Run the pass TWICE over the same bead, with the refinery's decline in
# between. The decline clears the assignee and hands the bead back, restoring the
# candidate shape exactly — and the hand-back itself bumps `updated_at`, which is
# all the age gate reads. So the decline set the loop PERIOD rather than breaking
# the loop, and the bead returned every --min-age-minutes forever (observed twice
# on tk-kbb8s). The stamp was always written; nothing ever read it back.
cat > "$TMP/candidates-once.json" <<JSON
[
  {"id":"b-redo","status":"open","assignee":"","updated_at":"__OLD__",
   "metadata":{"branch":"polecat/b-redo"}}
]
JSON
sed -i -e "s#__OLD__#$OLD_ISO#g" "$TMP/candidates-once.json"

: > "$TMP/updates"; : > "$TMP/mail"; : > "$TMP/state"; : > "$TMP/nudges"
set +e
FAKE_CANDIDATES="$TMP/candidates-once.json" run
set -e
has "gc bd update b-redo --status=open --assignee=$REFINERY" "$TMP/updates" \
  "(ONCE) the first pass recovers the bead"
has "stranded_branch_recovered=polecat/b-redo@sha-redo" "$TMP/updates" \
  "(ONCE) and stamps the tip it recovered it at"

# The hand-back, modelled from the stamp the pass ACTUALLY wrote rather than a
# hand-typed copy of it: that is what proves the writer and the reader agree on the
# key, which is the whole defect — the stamp was correct and simply never read.
STAMP=$(sed -n 's/.*stranded_branch_recovered=\([^ ]*\).*/\1/p' "$TMP/updates")
eq "$STAMP" "polecat/b-redo@sha-redo" "(ONCE) the stamp the guard reads is the stamp the pass writes"
jq -c --arg s "$STAMP" 'map(.metadata.stranded_branch_recovered = $s)' \
  "$TMP/candidates-once.json" > "$TMP/candidates-once2.json"

: > "$TMP/updates"; : > "$TMP/mail"; : > "$TMP/state"; : > "$TMP/nudges"
set +e
FAKE_CANDIDATES="$TMP/candidates-once2.json" run
set -e
hasnt "gc bd update b-redo" "$TMP/updates" \
  "(ONCE) the second pass does not hand the same tip off again"
hasnt "b-redo" "$TMP/mail" "(ONCE) nor re-mails the mayor about it"
has "declining to re-arm" "$TMP/out" "(ONCE) and says why it declined"

# EQUALITY, not a blacklist: the same bead with the same marker, on a branch that
# has since moved, is a genuinely new strand and must still be rescued. Without
# this the marker would retire the bead permanently on its first decline.
sed -e 's#^polecat/b-redo|sha-redo$#polecat/b-redo|sha-redo2#' "$TMP/remote" > "$TMP/remote2"
: > "$TMP/updates"; : > "$TMP/mail"; : > "$TMP/state"; : > "$TMP/nudges"
set +e
FAKE_REMOTE="$TMP/remote2" FAKE_CANDIDATES="$TMP/candidates-once2.json" run
set -e
has "gc bd update b-redo --status=open --assignee=$REFINERY" "$TMP/updates" \
  "(ONCE) a branch that has MOVED since the stamp is rescued again"
has "stranded_branch_recovered=polecat/b-redo@sha-redo2" "$TMP/updates" \
  "(ONCE) and the marker is re-keyed to the new tip"

# MUTATION: cut the once-marker out and the declined bead is grabbed a second time.
# Tested on its own fixture, where the parent walk cannot also be holding it back —
# two guards in series mask each other, and both mutants would read green.
# shellcheck disable=SC2016  # the $ is sed's, not the shell's — single quotes are required
mutant no-once-marker \
  's/if \[ -n "\$HEAD_SHA" \] && \[ "\$RECOVERED" = "\$BRANCH@\$HEAD_SHA" \]; then/if false; then/'
MUT_ONCE="$MUTANT_PATH"
: > "$TMP/updates"; : > "$TMP/mail"; : > "$TMP/state"; : > "$TMP/nudges"
set +e
FAKE_CANDIDATES="$TMP/candidates-once2.json" run_as "$MUT_ONCE"
set -e
has "gc bd update b-redo --status=open --assignee=$REFINERY" "$TMP/updates" \
  "(ONCE) MUTANT: with the once-marker removed the declined bead IS re-armed"

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
