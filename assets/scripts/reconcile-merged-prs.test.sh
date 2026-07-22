#!/usr/bin/env bash
# Hermetic test for reconcile-merged-prs.sh (close-on-land DETECT-ONLY observer).
#
# Stubs `gh` (PR state) and `gc` (bead-ledger list/close/update + mail) on PATH.
# No live city, Dolt, network, or real pull requests. The observer RECORDS merges
# it observes and ESCALATES discrepancies, but it has NO merge authority — the
# merge itself is the merge skill's job (merge-skill.sh, tested separately in
# merge-skill.test.sh). Covers the observer's dispositions + the no-merge
# invariant + convergence:
#   (1) PR merged              -> anchor CLOSED "Merged to <target> at <sha>"
#   (2) PR closed, unmerged    -> anchor flagged (merge_result=abandoned,
#                                 routed to human) + mayor escalated once
#   (3) PR open, ready          -> DETECT-ONLY: anchor left OPEN, the observer
#                                 never merges and never closes it
#   (4) PR open, draft          -> skipped (drafts retired; a stray draft is left alone)
#   (7) PR open, ready BUT live base != anchor target (retargeted after
#        publication) -> anchor flagged merge_result=retargeted + routed to
#        human + escalated once; never closed as landed
#   (8) PR merged BUT to a base != anchor target (retargeted) -> anchor NOT
#        closed as landed (would record a landing that never happened); flagged
#        retargeted + escalated once.
#   (9) PR open, CONFLICTING (stale base: the target was rewritten under it) ->
#        a rebase CHILD is filed against the anchor and routed to the fix pool,
#        the anchor STAYS gating (merge_result=pull_request untouched, so the
#        merge skill still lands it once the rebase clears), and the arm is
#        bounded to one rebase per head via stale_base_head.
#   (10) PR open, CONFLICTING but a rework/review child is already open for the
#        PR -> no second rebase child (it would race the one in flight).
#   (11) PR open, mergeable UNKNOWN (GitHub still computing) -> nothing: an
#        indeterminate reading must never be treated as a conflict.
#   (12) open PR whose bead is CLOSED (anchorless) -> reported + escalated ONCE,
#        bounded by an anchorless_flagged marker on the closed bead; never
#        merged, closed, or reopened (disposition is an operator call).
#   (13) open PR that a LIVE bead references (anchor or rework child) -> not a
#        finding; and the tracked-set match is exact, so PR#7 never satisfies
#        PR#77.
#   (14) open PR with NO bead in any state -> reported but NOT escalated (nothing
#        durable to bound a mail with, so it must not repeat every wake).
#   (15) zero gating anchors is NOT an early exit — the anchorless scan still
#        runs (zero anchors + open PRs is exactly the stranded state).
#   (INV) the observer NEVER runs `gh pr merge` for ANY anchor — no merge authority.
#   (5) convergence: closed / flagged / retargeted anchors leave the gating set,
#       so a second pass does not re-close, re-escalate, or re-flag them; the
#       stale-base anchor STAYS in the set (by design) and is held from re-filing
#       by its stale_base_head marker instead.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/reconcile-merged-prs.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { grep -q "$1" "$2" 2>/dev/null; }

mkdir -p "$TMP/bin"

# Gating anchors (gc bd list source): id|pr_number|merged_target|merge_hold|rebase_hold
# The two hold columns are optional (older rows omit them and read as unset).
#   bead-A merged to main            -> closed (observed merge recorded)
#   bead-B closed unmerged           -> flagged abandoned + escalated
#   bead-C open, ready               -> left OPEN (the merge skill lands it, not us)
#   bead-D open, draft               -> skipped
#   bead-H open, ready, retargeted   -> flagged retargeted + escalated, never closed
#   bead-I merged to wrong base      -> NOT closed as landed; flagged retargeted
#   bead-J open, CONFLICTING         -> rebase child filed + routed; STAYS gating
#   bead-K open, CONFLICTING, child in flight -> no second rebase child
#   bead-L open, mergeable UNKNOWN   -> nothing (indeterminate is not a conflict)
#   bead-M open, ready (turns CONFLICTING in run 4, which passes no --fix-pool)
#   bead-N open, CONFLICTING, merge_hold=true          -> (16) HELD, no force-push
#   bead-O open, CONFLICTING, rebase_hold=true         -> (17) HELD, no force-push
#   bead-P open, CONFLICTING, BLOCKED child rebase_hold-> (18) HELD, no force-push
#   bead-Q open, CONFLICTING, blocked child same BRANCH-> (19) no second child
#   bead-R open, CONFLICTING, HOOKED child same BRANCH -> (21) no second child
#   bead-S open, CONFLICTING, PINNED child same BRANCH -> (22) no second child
cat > "$TMP/anchors" <<'A'
bead-A|201|main
bead-B|202|main
bead-C|203|main
bead-D|204|main
bead-H|208|main
bead-I|209|main
bead-J|210|main
bead-K|211|main
bead-L|212|main
bead-M|213|main
bead-N|214|main|true|
bead-O|215|main||true
bead-P|216|main||
bead-Q|217|main||
bead-R|218|main||
bead-S|219|main||
A

# PR states (gh pr view source):
#   pr|state|mergedAt|isDraft|mergeOid|baseRefName|headRefName|headRefOid|mergeable|mergeStateStatus
#   201 merged to main            -> close anchor bead-A (mergedAt set = merge)
#   202 closed, unmerged          -> flag anchor bead-B + escalate
#   203 open, ready               -> observer leaves it (detect-only)
#   204 open, draft               -> skip
#   208 open, base=integration/foo != main -> retarget (flagged, never merged)
#   209 merged BUT to integration/foo != main -> retarget (NOT closed as landed)
#   210 open, CONFLICTING/DIRTY   -> stale base: rebase child routed to the pool
#   211 open, CONFLICTING/DIRTY, already has an open rework child -> no new child
#   212 open, UNKNOWN/UNKNOWN     -> still computing; must NOT read as a conflict
#   213 open, ready for now       -> rewritten to CONFLICTING before run 4
#   214 open, CONFLICTING/DIRTY, anchor merge_hold=true  -> held, NO rebase filed
#   215 open, CONFLICTING/DIRTY, anchor rebase_hold=true -> held, NO rebase filed
#   216 open, CONFLICTING/DIRTY, blocked child holds it  -> held, NO rebase filed
#   217 open, CONFLICTING/DIRTY, blocked child on branch -> skipped, NO 2nd child
#   218 open, CONFLICTING/DIRTY, HOOKED child on branch  -> skipped, NO 2nd child
#   219 open, CONFLICTING/DIRTY, PINNED child on branch  -> skipped, NO 2nd child
cat > "$TMP/prs" <<'P'
201|MERGED|2026-06-23T01:00:00Z|false|abc12345def67890|main|polecat/bead-A|head201|MERGEABLE|CLEAN
202|CLOSED||false||main|polecat/bead-B|head202|UNKNOWN|UNKNOWN
203|OPEN||false||main|polecat/bead-C|head203|MERGEABLE|BLOCKED
204|OPEN||true||main|polecat/bead-D|head204|MERGEABLE|BLOCKED
208|OPEN||false||integration/foo|polecat/bead-H|head208|MERGEABLE|BLOCKED
209|MERGED|2026-06-23T02:00:00Z|false|cafe1234abcd5678|integration/foo|polecat/bead-I|head209|MERGEABLE|CLEAN
210|OPEN||false||main|polecat/bead-J|head210|CONFLICTING|DIRTY
211|OPEN||false||main|polecat/bead-K|head211|CONFLICTING|DIRTY
212|OPEN||false||main|polecat/bead-L|head212|UNKNOWN|UNKNOWN
213|OPEN||false||main|polecat/bead-M|head213|MERGEABLE|BLOCKED
214|OPEN||false||main|polecat/bead-N|head214|CONFLICTING|DIRTY
215|OPEN||false||main|polecat/bead-O|head215|CONFLICTING|DIRTY
216|OPEN||false||main|polecat/bead-P|head216|CONFLICTING|DIRTY
217|OPEN||false||main|polecat/bead-Q|head217|CONFLICTING|DIRTY
218|OPEN||false||main|polecat/bead-R|head218|CONFLICTING|DIRTY
219|OPEN||false||main|polecat/bead-S|head219|CONFLICTING|DIRTY
P

# Open PRs as `gh pr list` sees them (the anchorless scan's PR -> BEAD side):
#   pr|isDraft|headRefName|baseRefName
#   203 tracked by live anchor bead-C            -> not a finding
#   211 tracked by live anchor bead-K + child-K  -> not a finding
#   301 bead closed (dead-1)                     -> flagged + escalated once
#   302 no bead in any state                     -> flagged, NOT escalated
#   303 draft, bead closed (dead-3)              -> flagged (draft) + escalated
#   304 bead closed, marker ALREADY set          -> flagged, not re-escalated
#   77  no bead, but a live bead references PR#7 -> flagged (exact match, not
#                                                   swallowed by the "7" prefix)
cat > "$TMP/openprs" <<'O'
203|false|polecat/bead-C|main
211|false|polecat/bead-K|main
301|false|polecat/dead-1|main
302|false|somebody/manual-pr|main
303|true|polecat/dead-3|main
304|false|polecat/dead-4|main
77|false|polecat/dead-x|main
O

# Closed beads that still name a PR (the anchorless arm's bead resolution):
#   pr<TAB>bead-id<TAB>anchorless_flagged-marker<TAB>merge_result<TAB>created_at
# "-" means empty. It has to be a placeholder rather than an empty field: TAB is
# IFS *whitespace*, so bash collapses a run of them and an empty middle column
# would silently shift every field after it.
# PR#301 models the real shape: THREE closed beads name it — a review bead, a
# later "address findings" rework child, and the anchor that actually opened the
# PR. Both the rework child and the anchor carry merge_result, and the anchor is
# listed LAST, so only "oldest bead carrying merge_result" resolves it correctly.
# dead-4 is pre-flagged, so it must be reported but NOT re-escalated.
printf '%s\n' \
  '301	review-1	-	-	2026-01-02T00:00:00Z' \
  '301	rework-1	-	pull_request	2026-01-03T00:00:00Z' \
  '301	dead-1	-	pull_request	2026-01-01T00:00:00Z' \
  '303	dead-3	-	pull_request	2026-01-01T00:00:00Z' \
  '304	dead-4	304	pull_request	2026-01-01T00:00:00Z' \
  > "$TMP/dead"

: > "$TMP/closed"; : > "$TMP/abandoned"; : > "$TMP/retargeted"; : > "$TMP/mailbody"
: > "$TMP/automerge"; : > "$TMP/mail"; : > "$TMP/closelog"
: > "$TMP/created"; : > "$TMP/updates"; : > "$TMP/deps"; : > "$TMP/wakes"
: > "$TMP/staled"

# Rework/review children referencing a PR (the merge skill's in-flight set; the
# conflict arm reuses that query so it never races a rework already in flight).
#   pr<TAB>child-id<TAB>branch<TAB>status<TAB>rebase_hold
# The last three columns are optional; a missing status reads as `open` (the
# shape the older rows were written in). The arm appends its own children here as
# it files them, exactly as the real ledger would.
#   child-K   PR#211, open                 -> case (10): no second child
#   child-tiny PR#7                         -> puts "7" in the tracked set, the
#                                              fixture for case (13)'s exact-match
#                                              guard against open PR#77
#   child-P   PR#216, BLOCKED, rebase_hold -> case (18): the observed shape — a
#                                              keeper neutralised a runaway rebase
#                                              child by blocking it and setting
#                                              rebase_hold. It is invisible to a
#                                              status=open,in_progress probe.
#   child-Q   PR#999, BLOCKED, but names branch polecat/bead-Q -> case (19): the
#                                              branch dimension. Keyed by PR alone
#                                              it is missed; a force-push would
#                                              race it on the shared branch.
#   child-R   PR#998, HOOKED, names branch polecat/bead-R -> case (21): `hooked`
#                                              is a built-in wip status ("attached
#                                              to an agent's hook") — a child in it
#                                              is being worked RIGHT NOW, the most
#                                              dangerous moment to force-push under.
#   child-S   PR#997, PINNED, names branch polecat/bead-S -> case (22): the other
#                                              non-closed status the probe used to
#                                              omit. No rebase_hold on either: the
#                                              STATUS LIST alone must make them
#                                              visible, with no operator marker to
#                                              fall back on.
printf '%s\n' \
  '211	child-K' \
  '7	child-tiny' \
  '216	child-P	polecat/bead-P	blocked	true' \
  '999	child-Q	polecat/bead-Q	blocked	-' \
  '998	child-R	polecat/bead-R	hooked	-' \
  '997	child-S	polecat/bead-S	pinned	-' \
  > "$TMP/children"

FIX_POOL="test-rig/gc-toolkit.polecat"

# --- gh stub: pr view (emit state JSON), pr merge (record any merge attempt). --
# The `pr view` arm VALIDATES the requested `--json` fields against the set a
# supported gh actually exposes for a PR, and errors (exit 1, like real gh) on
# any unknown field. This is the regression guard for the field-shape bug:
# `merged` is NOT a pr-view field (`mergedAt` is), so a buggy
# `--json ...merged...` empties PR_JSON and the disposition matrix below fails —
# exactly the real-world failure where close-on-land silently closes nothing.
#
# The `pr merge` arm records to $FAKE_AUTOMERGE. The observer must NEVER reach it
# (it has no merge authority): the INV assertion below proves that file stays
# empty across the whole run. The merge skill's own test exercises real merges.
cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
case "$1 $2" in
  "pr view")
    num="$3"; shift 3
    fields=""
    while [ $# -gt 0 ]; do case "$1" in --json) fields="$2"; shift 2 ;; *) shift ;; esac; done
    # Supported `gh pr view --json` fields (subset; notably NOT `merged`).
    SUPPORTED=" number state mergedAt mergeCommit isDraft baseRefName headRefName headRefOid url title body author additions deletions mergeable mergeStateStatus "
    OIFS="$IFS"; IFS=','
    for f in $fields; do
      case "$SUPPORTED" in
        *" $f "*) : ;;
        *) IFS="$OIFS"; echo "Unknown JSON field: \"$f\"" >&2; exit 1 ;;
      esac
    done
    IFS="$OIFS"
    while IFS='|' read -r pr state mergedat isdraft oid base head headoid mergeable mergestate; do
      [ "$pr" = "$num" ] || continue
      jq -n --arg s "$state" --arg ma "$mergedat" --argjson d "$isdraft" \
            --arg o "$oid" --arg b "$base" --arg h "$head" --arg ho "$headoid" \
            --arg m "$mergeable" --arg ms "$mergestate" --arg n "$num" \
        '{state:$s, mergedAt:(if $ma=="" then null else $ma end), isDraft:$d,
          mergeCommit:(if $o=="" then null else {oid:$o} end), baseRefName:$b,
          headRefName:$h, headRefOid:$ho, mergeable:$m, mergeStateStatus:$ms,
          url:("https://github.com/acme/repo/pull/" + $n)}'
      exit 0
    done < "$FAKE_PRS"
    exit 0 ;;
  "pr list")
    # Open PRs, for the anchorless (PR -> BEAD) scan.
    out=""
    while IFS='|' read -r pr isdraft head base; do
      [ -n "$pr" ] || continue
      obj=$(jq -n --arg n "$pr" --argjson d "$isdraft" --arg h "$head" --arg b "$base" \
        '{number:($n|tonumber), url:("https://github.com/acme/repo/pull/" + $n),
          isDraft:$d, headRefName:$h, baseRefName:$b}')
      if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
    done < "$FAKE_OPENPRS"
    printf '[%s]\n' "$out"
    exit 0 ;;
  "pr merge")
    printf '%s\n' "$3" >> "$FAKE_AUTOMERGE" ;;
esac
exit 0
GH
chmod +x "$TMP/bin/gh"

# --- gc stub: bd list / create / close / update / dep + session + mail. -------
# bd list reflects state: a closed, flagged (abandoned), or retargeted anchor
# leaves the gating set, which is what makes the convergence assertion
# meaningful. A stale-base anchor deliberately does NOT leave it (the merge skill
# must keep watching the PR), so the gating rows carry the stale_base_head marker
# the conflict arm stamps — that marker, not the scan, is what bounds it.
# Two list shapes are modeled: the gating-anchor scan
# (`--metadata-field merge_result=pull_request`) and the conflict arm's
# in-flight-rework probe (`--metadata-field pr_number=<n>`).
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
if [ "$1" = "mail" ]; then
  shift; subj=""; body=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -s) subj="$2"; shift 2 ;;
      -m) body="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  printf '%s\n' "$subj" >> "$FAKE_MAIL"
  printf '%s\n' "$body" >> "$FAKE_MAILBODY"
  exit 0
fi
if [ "$1" = "session" ]; then
  [ "${2:-}" = "wake" ] && printf '%s\n' "${3:-}" >> "$FAKE_WAKES"
  exit 0
fi
[ "$1" = "bd" ] || exit 0
case "$2" in
  list)
    case "$*" in
      *"--status closed"*)
        # CLOSED bead that still names a PR — the anchorless arm's resolution of
        # "who used to own this PR". Must be matched BEFORE the generic
        # pr_number= arm below, which would otherwise swallow it and return the
        # live children instead.
        num=""
        for a in "$@"; do case "$a" in pr_number=*) num="${a#pr_number=}" ;; esac; done
        out=""
        while IFS="$(printf '\t')" read -r pr bid flagged mres created; do
          [ "$pr" = "$num" ] || continue
          [ "$flagged" = "-" ] && flagged=""
          [ "$mres" = "-" ] && mres=""
          obj=$(printf '{"id":"%s","created_at":"%s","metadata":{"pr_number":"%s","anchorless_flagged":"%s","merge_result":"%s"}}' \
                  "$bid" "$created" "$pr" "$flagged" "$mres")
          if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
        done < "$FAKE_DEAD"
        printf '[%s]\n' "$out" ;;
      *"--metadata-field branch="*|*"--metadata-field pr_number="*)
        # The conflict arm's pre-dispatch probe, keyed on pr_number OR branch.
        # Returns anchors AND rework children (the real ledger does not
        # distinguish them — merge_result does, and the arm filters on it), and
        # honors the requested --status list: a bead whose status the caller did
        # not ask for is INVISIBLE, exactly as in the ledger. That is what makes
        # the status list load-bearing — narrow the probe back to
        # open,in_progress and the blocked children below vanish, which is the
        # bug this guards (tk-gajop).
        # FAKE_PROBE_FAIL models a failed ledger read: empty output, NOT "[]",
        # exactly as a broken `gc bd list` behaves. The arm must fail CLOSED.
        [ -n "${FAKE_PROBE_FAIL:-}" ] && exit 0
        # FAKE_PROBE_SHAPE models the failure family an emptiness test cannot see:
        # a read that FAILED but still put something on stdout. Each shape defeats
        # a different guard, so each is asserted separately below — a guard no test
        # pins is a guard a later edit can delete silently, which is how the
        # `hooked` gap got in.
        #   error-rc1 — the observed shape, transcribed from the real thing
        #               (`gc bd list --metadata-field malformed --status open
        #               --json`): a JSON error OBJECT plus exit 1.
        #   error-rc0 — the same object arriving with a ZERO exit. Isolates the
        #               payload-shape guard: the exit-status guard cannot see this.
        #   array-rc1 — a well-formed, EMPTY array with a non-zero exit (the read
        #               died after emitting). Isolates the exit-status guard: the
        #               payload-shape guard cannot see this, and "[]" is precisely
        #               the value that legitimately means "nobody holds it".
        #   bad-array — an array of non-objects: passes the shape guard, then blows
        #               up the projection. Isolates the jq-status guard.
        #   object-map— the nastiest shape, and the only one the projection cannot
        #               catch: an OBJECT whose values are bead-shaped, e.g. a
        #               `--json` envelope keyed by id rather than a list. `.[]`
        #               happily iterates an object's values, so the projection
        #               SUCCEEDS and emits a well-formed row; only "is the payload
        #               an array?" rejects it. The row is a foreign ANCHOR
        #               (merge_result set, no rebase_hold) precisely so it passes
        #               both the frozen and in-flight filters — i.e. so the arm
        #               would DISPATCH on it, and the test cannot pass by accident.
        case "${FAKE_PROBE_SHAPE:-}" in
          error-rc1)  printf '{\n  "error": "invalid --metadata-field: expected key=value, got \\"malformed\\"",\n  "schema_version": 1\n}\n'; exit 1 ;;
          error-rc0)  printf '{\n  "error": "invalid --metadata-field: expected key=value, got \\"malformed\\"",\n  "schema_version": 1\n}\n'; exit 0 ;;
          array-rc1)  printf '[]\n'; exit 1 ;;
          bad-array)  printf '[1, 2]\n'; exit 0 ;;
          object-map) printf '{"other-anchor": {"id": "other-anchor", "metadata": {"merge_result": "pull_request"}}}\n'; exit 0 ;;
        esac
        key=""; val=""; sts=""; prev=""
        for a in "$@"; do
          case "$a" in
            pr_number=*) key="pr";     val="${a#pr_number=}" ;;
            branch=*)    key="branch"; val="${a#branch=}" ;;
          esac
          [ "$prev" = "--status" ] && sts="$a"
          prev="$a"
        done
        visible() { printf '%s' ",$sts," | grep -q ",$1,"; }
        out=""
        while IFS='|' read -r id pr target mhold rhold; do
          [ -n "$id" ] || continue
          grep -qx "$id" "$FAKE_CLOSED" 2>/dev/null && continue
          grep -qx "$id" "$FAKE_ABANDONED" 2>/dev/null && continue
          grep -qx "$id" "$FAKE_RETARGETED" 2>/dev/null && continue
          case "$key" in
            pr)     [ "$pr" = "$val" ] || continue ;;
            branch) [ "polecat/$id" = "$val" ] || continue ;;
          esac
          visible open || continue
          # Anchors carry merge_result — that is what marks them as NOT a rework
          # child, and the arm must exclude them on it (plus its own id).
          obj=$(printf '{"id":"%s","metadata":{"pr_number":"%s","branch":"polecat/%s","merge_result":"pull_request","rebase_hold":"%s"}}' \
                  "$id" "$pr" "$id" "$rhold")
          if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
        done < "$FAKE_ANCHORS"
        while IFS="$(printf '\t')" read -r pr cid cbranch cstatus crhold; do
          [ -n "$cid" ] || continue
          [ -n "$cstatus" ] && [ "$cstatus" != "-" ] || cstatus="open"
          [ "$cbranch" = "-" ] && cbranch=""
          [ "$crhold" = "-" ] && crhold=""
          case "$key" in
            pr)     [ "$pr" = "$val" ] || continue ;;
            branch) [ -n "$cbranch" ] && [ "$cbranch" = "$val" ] || continue ;;
          esac
          visible "$cstatus" || continue
          obj=$(printf '{"id":"%s","metadata":{"pr_number":"%s","branch":"%s","rebase_hold":"%s"}}' \
                  "$cid" "$pr" "$cbranch" "$crhold")
          if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
        done < "$FAKE_CHILDREN"
        printf '[%s]\n' "$out" ;;
      *"merge_result=pull_request"*)
        out=""
        while IFS='|' read -r id pr target mhold rhold; do
          [ -n "$id" ] || continue
          grep -qx "$id" "$FAKE_CLOSED" 2>/dev/null && continue
          grep -qx "$id" "$FAKE_ABANDONED" 2>/dev/null && continue
          grep -qx "$id" "$FAKE_RETARGETED" 2>/dev/null && continue
          staled=$(awk -F'\t' -v i="$id" '$1==i{print $2}' "$FAKE_STALED" 2>/dev/null | tail -1)
          obj=$(printf '{"id":"%s","metadata":{"pr_number":"%s","merged_target":"%s","branch":"polecat/%s","stale_base_head":"%s","merge_hold":"%s","rebase_hold":"%s"}}' \
                  "$id" "$pr" "$target" "$id" "$staled" "$mhold" "$rhold")
          if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
        done < "$FAKE_ANCHORS"
        printf '[%s]\n' "$out" ;;
      *"open,in_progress,blocked"*)
        # Every LIVE bead that names a PR: gating anchors still in the set, plus
        # open rework/review children. This is the tracked set the anchorless
        # scan subtracts from `gh pr list`. Matched AFTER the probe arms above:
        # the probe's own --status list is a superset of this string, so ordering
        # is what keeps a keyed probe from falling into this unkeyed scan.
        # FAKE_LIVE_FAIL models a failed ledger read (empty output, NOT "[]") so
        # the fail-closed guard can be exercised.
        [ -n "${FAKE_LIVE_FAIL:-}" ] && exit 0
        out=""
        while IFS='|' read -r id pr target mhold rhold; do
          [ -n "$id" ] || continue
          grep -qx "$id" "$FAKE_CLOSED" 2>/dev/null && continue
          grep -qx "$id" "$FAKE_ABANDONED" 2>/dev/null && continue
          grep -qx "$id" "$FAKE_RETARGETED" 2>/dev/null && continue
          obj=$(printf '{"id":"%s","metadata":{"pr_number":"%s"}}' "$id" "$pr")
          if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
        done < "$FAKE_ANCHORS"
        while IFS="$(printf '\t')" read -r pr cid cbranch cstatus crhold; do
          [ -n "$cid" ] || continue
          obj=$(printf '{"id":"%s","metadata":{"pr_number":"%s"}}' "$cid" "$pr")
          if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
        done < "$FAKE_CHILDREN"
        printf '[%s]\n' "$out" ;;
      *) printf '[]\n' ;;
    esac ;;
  create)
    # Mint a deterministic child id and echo it in `--json` shape.
    n=$(( $(wc -l < "$FAKE_CREATED") + 1 ))
    cid="fix-$n"
    printf '%s\t%s\n' "$cid" "$3" >> "$FAKE_CREATED"
    printf '{"id":"%s"}\n' "$cid" ;;
  close)
    id="$3"; shift 3
    reason=""
    while [ $# -gt 0 ]; do case "$1" in --reason) reason="$2"; shift 2 ;; *) shift ;; esac; done
    printf '%s\n' "$id" >> "$FAKE_CLOSED"
    printf '%s\t%s\n' "$id" "$reason" >> "$FAKE_CLOSELOG" ;;
  update)
    id="$3"
    printf '%s\t%s\n' "$id" "$*" >> "$FAKE_UPDATES"
    case "$*" in
      *merge_result=abandoned*)  printf '%s\n' "$id" >> "$FAKE_ABANDONED" ;;
      *merge_result=retargeted*) printf '%s\n' "$id" >> "$FAKE_RETARGETED" ;;
    esac
    # Mirror the metadata writes the ledger would make visible to later passes:
    # the anchor's stale_base_head marker, and a child joining the in-flight set
    # once it carries pr_number. The child's BRANCH is recorded alongside, since
    # the conflict arm probes that dimension too — a child written without one
    # would be invisible to the branch probe on the next pass.
    child_pr=""; child_branch=""
    for a in "$@"; do
      case "$a" in
        stale_base_head=*) printf '%s\t%s\n' "$id" "${a#stale_base_head=}" >> "$FAKE_STALED" ;;
        pr_number=*)       child_pr="${a#pr_number=}" ;;
        branch=*)          child_branch="${a#branch=}" ;;
        anchorless_flagged=*)
          # Mirror the escalation bound onto the closed bead, so a later pass
          # sees it and does not re-escalate.
          awk -F'\t' -v i="$id" -v v="${a#anchorless_flagged=}" \
              'BEGIN{OFS="\t"} $2==i{$3=v} {print}' "$FAKE_DEAD" > "$FAKE_DEAD.n" \
            && mv "$FAKE_DEAD.n" "$FAKE_DEAD" ;;
      esac
    done
    # "-" placeholders, never empty fields: TAB is IFS whitespace, so bash
    # collapses a run of them and an empty column would shift every field after
    # it (same convention as $FAKE_DEAD).
    if [ -n "$child_pr" ]; then
      [ -n "$child_branch" ] || child_branch="-"
      printf '%s\t%s\t%s\topen\t-\n' "$child_pr" "$id" "$child_branch" >> "$FAKE_CHILDREN"
    fi ;;
  dep)
    printf '%s\n' "$*" >> "$FAKE_DEPS" ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

export PATH="$TMP/bin:$PATH"
export FAKE_ANCHORS="$TMP/anchors" FAKE_PRS="$TMP/prs" \
       FAKE_CLOSED="$TMP/closed" FAKE_ABANDONED="$TMP/abandoned" \
       FAKE_RETARGETED="$TMP/retargeted" \
       FAKE_AUTOMERGE="$TMP/automerge" FAKE_MAIL="$TMP/mail" FAKE_CLOSELOG="$TMP/closelog" \
       FAKE_CREATED="$TMP/created" FAKE_UPDATES="$TMP/updates" FAKE_DEPS="$TMP/deps" \
       FAKE_WAKES="$TMP/wakes" FAKE_STALED="$TMP/staled" FAKE_CHILDREN="$TMP/children" \
       FAKE_OPENPRS="$TMP/openprs" FAKE_DEAD="$TMP/dead" FAKE_MAILBODY="$TMP/mailbody"

# --- Run 1: the disposition matrix. ------------------------------------------
OUT1="$(bash "$SCRIPT" --fix-pool "$FIX_POOL")"

has '^bead-A$' "$TMP/closed" && ok "(1) merged PR -> anchor closed" \
                             || bad "(1) merged PR -> anchor closed"
grep -q 'Merged to main at abc12345' "$TMP/closelog" \
  && ok "(1) close reason names target + short merge sha" \
  || bad "(1) close reason names target + short merge sha (got: $(cat "$TMP/closelog"))"
has '^bead-B$' "$TMP/abandoned" && ok "(2) closed-unmerged PR -> anchor flagged" \
                                || bad "(2) closed-unmerged PR -> anchor flagged"
eq "$(grep -c 'out-of-band close of PR#202' "$TMP/mail")" "1" \
   "(2) out-of-band close escalates to mayor once"
has '^bead-C$' "$TMP/closed" && bad "(3) ready anchor must NOT be closed by the observer" \
                             || ok "(3) ready PR -> anchor left OPEN (detect-only; merge skill lands it)"
has '^bead-D$' "$TMP/closed" && bad "(4) draft anchor must NOT be closed" \
                             || ok "(4) draft PR -> anchor not closed"
# (7) retargeted open PR: flagged + escalated, never closed.
has '^bead-H$' "$TMP/retargeted" && ok "(7) retargeted open anchor flagged merge_result=retargeted" \
                                 || bad "(7) retargeted open anchor flagged merge_result=retargeted"
has '^bead-H$' "$TMP/closed" && bad "(7) retargeted open anchor must NOT be closed" \
                             || ok "(7) retargeted open anchor not closed as landed"
eq "$(grep -c 'PR#208 retargeted' "$TMP/mail")" "1" "(7) retarget escalates to mayor once"
# (8) merged-to-wrong-base: NOT closed as landed, flagged retargeted.
has '^bead-I$' "$TMP/closed" && bad "(8) merged-to-wrong-base anchor must NOT be closed" \
                             || ok "(8) merged-to-wrong-base anchor not closed as landed"
has '^bead-I$' "$TMP/retargeted" && ok "(8) merged-to-wrong-base anchor flagged retargeted" \
                                 || bad "(8) merged-to-wrong-base anchor flagged retargeted"
eq "$(grep -c 'PR#209 retargeted' "$TMP/mail")" "1" "(8) merged-to-wrong-base escalates once"

# (9) stale base: a conflicted PR gets a rebase CHILD routed to the fix pool, and
# the anchor STAYS gating so the merge skill still lands it after the rebase.
eq "$(grep -c 'Rebase PR#210' "$TMP/created")" "1" "(9) conflicted PR -> one rebase child filed"
grep -q "gc.routed_to=$FIX_POOL" "$TMP/updates" \
  && ok "(9) rebase child routed to the fix pool" \
  || bad "(9) rebase child routed to the fix pool (got: $(cat "$TMP/updates"))"
grep -q 'existing_pr=https://github.com/acme/repo/pull/210' "$TMP/updates" \
  && ok "(9) rebase child reworks the EXISTING PR (existing_pr set)" \
  || bad "(9) rebase child must carry existing_pr so no second PR is opened"
J_UPDATES=$(grep '^bead-J' "$TMP/updates" || true)
printf '%s\n' "$J_UPDATES" | grep -q 'stale_base_head=head210' \
  && ok "(9) anchor marked stale_base_head at the detected head" \
  || bad "(9) anchor marked stale_base_head at the detected head (got: $J_UPDATES)"
printf '%s\n' "$J_UPDATES" | grep -q 'merge_result=' \
  && bad "(9) anchor must KEEP merge_result=pull_request (the merge skill still lands it)" \
  || ok "(9) anchor keeps merge_result=pull_request (stays gating, unlike retarget/abandon)"
has '^bead-J$' "$TMP/closed" && bad "(9) conflicted anchor must NOT be closed" \
                             || ok "(9) conflicted anchor not closed"
grep -q 'fix-1 bead-J' "$TMP/deps" \
  && ok "(9) rebase child linked parent-child under the anchor" \
  || bad "(9) rebase child linked parent-child under the anchor (got: $(cat "$TMP/deps"))"
grep -qx "$FIX_POOL" "$TMP/wakes" && ok "(9) fix pool woken for the rebase" \
                                  || bad "(9) fix pool woken for the rebase"
eq "$(grep -c 'PR#210' "$TMP/mail")" "0" "(9) a routable conflict does not escalate to mayor"

# (10) a rework/review child is already open for PR#211 -> do not race it.
eq "$(grep -c 'Rebase PR#211' "$TMP/created")" "0" \
   "(10) conflicted PR with a rework child in flight -> no second rebase child"
# (11) UNKNOWN is GitHub still computing, not a conflict.
eq "$(grep -c 'Rebase PR#212' "$TMP/created")" "0" \
   "(11) mergeable=UNKNOWN never treated as a conflict"
eq "$(grep -c 'Rebase PR#203' "$TMP/created")" "0" \
   "(11) a ready (non-conflicted) PR gets no rebase child"

# --- (16)-(19) operator holds veto the force-push dispatch. -------------------
# This arm does not merge, it DISPATCHES A FORCE-PUSH to a live pool, so every
# marker that holds the gentler merge must hold it too. Before this, none of the
# four shapes below was read: merge-skill.sh refused to merge a merge_hold anchor
# and, seconds later in the same pass, this arm used that same anchor to route a
# rebase (tk-gajop). Each case asserts BOTH halves — no child filed, and the hold
# is announced — because a silent skip is indistinguishable from a missed anchor.

# (16) merge_hold on the anchor: an operator gate on landing is necessarily a
# gate on rewriting the branch underneath it.
eq "$(grep -c 'Rebase PR#214' "$TMP/created")" "0" \
   "(16) anchor merge_hold -> NO rebase child filed (no force-push dispatched)"
printf '%s\n' "$OUT1" | grep -q "bead-N — PR#214 conflicted (stale base) but merge_hold set" \
  && ok "(16) merge_hold hold is announced, naming the operator gate" \
  || bad "(16) merge_hold hold reason (got: $OUT1)"

# (17) rebase_hold on the anchor: the narrower "do not rebase this branch".
eq "$(grep -c 'Rebase PR#215' "$TMP/created")" "0" \
   "(17) anchor rebase_hold -> NO rebase child filed"
printf '%s\n' "$OUT1" | grep -q "bead-O — PR#215 conflicted (stale base) but rebase_hold set" \
  && ok "(17) anchor rebase_hold hold is announced" \
  || bad "(17) anchor rebase_hold hold reason (got: $OUT1)"

# (18) THE OBSERVED DEFECT. A keeper neutralised a runaway rebase child by
# BLOCKING it and setting rebase_hold=true. The old probe asked for
# status=open,in_progress only, so that child was invisible and the arm filed a
# second one on the very next pass — two live children on one branch, a
# concurrent force-push race. Both halves matter: the blocked child must be
# VISIBLE (status list) and its rebase_hold must be READ (the veto).
eq "$(grep -c 'Rebase PR#216' "$TMP/created")" "0" \
   "(18) BLOCKED child with rebase_hold -> NO second rebase child on its branch"
printf '%s\n' "$OUT1" | grep -q "child-P holds branch 'polecat/bead-P' with rebase_hold" \
  && ok "(18) hold reason names the holding child and the branch it protects" \
  || bad "(18) blocked-child rebase_hold hold reason (got: $OUT1)"

# (19) The branch dimension. child-Q names PR#999 — keyed on pr_number alone it
# is missed entirely — but it holds branch polecat/bead-Q, which is what a
# force-push actually collides on. This is the shape a PR carrying two anchors
# produces: the per-ANCHOR stale_base_head marker cannot dedupe across anchors,
# so only the branch probe sees the sibling.
eq "$(grep -c 'Rebase PR#217' "$TMP/created")" "0" \
   "(19) live child on the same BRANCH under another PR -> no second rebase child"

# (21)(22) EVERY non-closed status owns the branch, not just the ones an operator
# reaches for. `closed` is the only status in the `done` category; the probe's
# status list is a hand-maintained complement of it, so any status left out is an
# invisible branch owner and therefore a second force-push. `hooked` is the sharp
# case — it means a child is attached to an agent's hook, i.e. being worked right
# now — and neither child below carries rebase_hold, so nothing but the status
# list can save them.
eq "$(grep -c 'Rebase PR#218' "$TMP/created")" "0" \
   "(21) HOOKED child on the same branch -> no second rebase child (no force-push race)"
eq "$(grep -c 'Rebase PR#219' "$TMP/created")" "0" \
   "(22) PINNED child on the same branch -> no second rebase child"

# --- (12)(13)(14) anchorless open PRs: the PR -> BEAD direction. --------------
# (12) closed bead + open PR: the close-on-publish blind spot. Reported and
# escalated exactly once, bounded by a marker on the closed bead.
printf '%s\n' "$OUT1" | grep -q 'ANCHORLESS PR#301' \
  && ok "(12) open PR whose bead is CLOSED is reported as anchorless" \
  || bad "(12) open PR whose bead is CLOSED is reported as anchorless (got: $OUT1)"
eq "$(grep -c 'anchorless open PR#301' "$TMP/mail")" "1" \
   "(12) anchorless PR escalated to mayor once"
grep '^dead-1' "$TMP/updates" | grep -q 'anchorless_flagged=301' \
  && ok "(12) escalation bounded by an anchorless_flagged marker on the closed bead" \
  || bad "(12) escalation bounded by an anchorless_flagged marker (got: $(grep dead-1 "$TMP/updates" || true))"
# Resolution must land on the bead that OPENED the PR — not a review bead (no
# merge_result) and not a later rework child (same marker, newer).
grep -q '^review-1' "$TMP/updates" \
  && bad "(12) review bead must not be marked in place of the anchor" \
  || ok "(12) anchor resolved over a review bead that names the same PR"
grep -q '^rework-1' "$TMP/updates" \
  && bad "(12) later rework child must not be marked in place of the opening anchor" \
  || ok "(12) oldest merge_result bead wins over a later rework child sharing the marker"
grep -q 'anchorless open PR#301 (bead dead-1 is closed)' "$TMP/mail" \
  && ok "(12) escalation names the anchor bead the operator must reopen" \
  || bad "(12) escalation names the anchor bead (got: $(grep 301 "$TMP/mail" || true))"
grep -q 'dead-1, review-1, rework-1' "$TMP/mailbody" \
  && ok "(12) escalation lists every closed bead naming the PR, oldest first" \
  || bad "(12) escalation lists every closed bead naming the PR (got: $(grep -o 'All:.*' "$TMP/mailbody" || true))"
# Detect + surface ONLY: the arm must not close, reopen, or otherwise dispose.
has '^dead-1$' "$TMP/closed" && bad "(12) anchorless arm must NOT close anything" \
                             || ok "(12) anchorless arm closes nothing (detect + surface only)"
grep '^dead-1' "$TMP/updates" | grep -q 'status' \
  && bad "(12) anchorless arm must NOT reopen the closed bead" \
  || ok "(12) anchorless arm never reopens the closed bead (disposition is the operator's)"
# A draft is still invisible to every automated path, so it is still a finding —
# labelled so the operator can weight it.
printf '%s\n' "$OUT1" | grep -q 'ANCHORLESS PR#303 (draft)' \
  && ok "(12) anchorless draft PR reported and labelled as a draft" \
  || bad "(12) anchorless draft PR reported and labelled (got: $OUT1)"
# Already-escalated: keep reporting (still stranded), do not re-mail.
printf '%s\n' "$OUT1" | grep -q 'ANCHORLESS PR#304' \
  && ok "(12) already-flagged anchorless PR still reported each pass" \
  || bad "(12) already-flagged anchorless PR still reported each pass"
eq "$(grep -c 'anchorless open PR#304' "$TMP/mail")" "0" \
   "(12) already-flagged anchorless PR is not re-escalated"

# (13) a PR any LIVE bead references is tracked by something -> not a finding.
printf '%s\n' "$OUT1" | grep -q 'ANCHORLESS PR#203' \
  && bad "(13) PR tracked by a live gating anchor must not be flagged" \
  || ok "(13) PR tracked by a live gating anchor is not flagged"
printf '%s\n' "$OUT1" | grep -q 'ANCHORLESS PR#211' \
  && bad "(13) PR tracked by a live rework child must not be flagged" \
  || ok "(13) PR tracked by a live rework child is not flagged"
printf '%s\n' "$OUT1" | grep -q 'ANCHORLESS PR#77' \
  && ok "(13) tracked-set match is exact — PR#77 not satisfied by tracked PR#7" \
  || bad "(13) tracked-set match is exact — PR#77 not satisfied by tracked PR#7 (got: $OUT1)"

# (14) no bead in any state: report it, but never mail — there is nothing
# durable to bound the escalation, so mailing would repeat every wake forever.
printf '%s\n' "$OUT1" | grep -q 'ANCHORLESS PR#302' \
  && ok "(14) open PR with no bead in any state is reported" \
  || bad "(14) open PR with no bead in any state is reported (got: $OUT1)"
eq "$(grep -c 'anchorless open PR#302' "$TMP/mail")" "0" \
   "(14) unboundable (no-bead) finding is reported but never escalated"

printf '%s\n' "$OUT1" | grep -q '5 anchorless open PRs' \
  && ok "run 1 summary reports 5 anchorless open PRs" \
  || bad "run 1 summary anchorless count (got: $OUT1)"

# (INV) NO MERGE AUTHORITY: the observer must never call `gh pr merge` for ANY
# anchor — the seam that the auto-merge retirement turns on. $FAKE_AUTOMERGE
# stays empty across the entire run (ready, draft, retargeted, merged alike).
eq "$(wc -l < "$TMP/automerge" | tr -d ' ')" "0" \
   "(INV) observer never runs 'gh pr merge' (detect-only, no merge authority)"

# Summary counters + the absence of any auto-merge wording.
printf '%s\n' "$OUT1" | grep -q "1 closed, 1 abandoned" \
  && ok "run 1 summary reports 1 closed, 1 abandoned" \
  || bad "run 1 summary (got: $OUT1)"
printf '%s\n' "$OUT1" | grep -q "2 retargeted" \
  && ok "run 1 summary reports 2 retargeted" \
  || bad "run 1 summary retargeted count (got: $OUT1)"
printf '%s\n' "$OUT1" | grep -qi "auto-merge" \
  && bad "run 1 summary must not mention auto-merge (it was retired)" \
  || ok "run 1 summary makes no mention of auto-merge"

# --- Regression guard (field shape): only gh-supported --json fields. ---------
# The stub models real gh: it REJECTS `merged` (the field the original bug
# requested) and ACCEPTS the script's real field set. The disposition matrix
# above already exercises this end-to-end (the script would skip every anchor on
# a rejected field); these direct probes document the contract so a reintroduced
# `merged` fails loudly with an obvious message.
gh pr view 201 --json merged >/dev/null 2>&1 \
  && bad "(6) gh stub must REJECT unsupported field 'merged' (models real gh)" \
  || ok "(6) unsupported --json field 'merged' rejected (guards the field-shape bug)"
gh pr view 201 --json state,mergedAt,mergeCommit,isDraft,baseRefName >/dev/null 2>&1 \
  && ok "(6) the script's --json field set is accepted by the gh stub" \
  || bad "(6) the script's --json field set must be accepted"

# --- Run 2: convergence. Closed / flagged / retargeted anchors leave the set. -
MAIL_BEFORE=$(wc -l < "$TMP/mail" | tr -d ' ')
bash "$SCRIPT" --fix-pool "$FIX_POOL" >/dev/null
eq "$(grep -c '^bead-A$' "$TMP/closed")" "1" "(5) merged anchor not re-closed on second pass"
eq "$(wc -l < "$TMP/mail" | tr -d ' ')" "$MAIL_BEFORE" "(5) flagged + retargeted anchors not re-escalated on second pass"
eq "$(grep -c 'Rebase PR#210' "$TMP/created")" "1" \
   "(5) stale-base anchor stays in the gating set but files no second rebase child"
eq "$(grep -c 'anchorless open PR#301' "$TMP/mail")" "1" \
   "(12) anchorless PR not re-escalated on a second pass (marker converged)"

# --- Run 3: the marker is what bounds it, and it re-arms when the head moves. --
# Close the rebase child (as the patrol does on hand-back) so the in-flight guard
# no longer applies — the stale_base_head marker alone must hold the arm.
awk -F'\t' '$1 != "210"' "$TMP/children" > "$TMP/children.next"
mv "$TMP/children.next" "$TMP/children"
bash "$SCRIPT" --fix-pool "$FIX_POOL" >/dev/null
eq "$(grep -c 'Rebase PR#210' "$TMP/created")" "1" \
   "(9) same head, child closed -> stale_base_head alone bounds it to one rebase"
# The polecat pushed: same conflict, NEW head -> a genuinely new stall, so re-arm.
sed 's/^210|\(.*\)|head210|/210|\1|head210b|/' "$TMP/prs" > "$TMP/prs.next"
mv "$TMP/prs.next" "$TMP/prs"
bash "$SCRIPT" --fix-pool "$FIX_POOL" >/dev/null
eq "$(grep -c 'Rebase PR#210' "$TMP/created")" "2" \
   "(9) head moved and still conflicting -> arm re-fires for the new head"

# --- Run 4: no fix pool -> escalate to human rather than file an unroutable ---
# child. Flip PR#213 to CONFLICTING and run with no --fix-pool.
sed 's/^213|.*/213|OPEN||false||main|polecat\/bead-M|head213|CONFLICTING|DIRTY/' "$TMP/prs" > "$TMP/prs.next"
mv "$TMP/prs.next" "$TMP/prs"
bash "$SCRIPT" >/dev/null
eq "$(grep -c 'Rebase PR#213' "$TMP/created")" "0" \
   "(9) no fix pool -> no unroutable rebase child is filed"
eq "$(grep -c 'PR#213 conflicted (stale base) with no fix pool' "$TMP/mail")" "1" \
   "(9) no fix pool -> escalated to mayor once"
M_UPDATES=$(grep '^bead-M' "$TMP/updates" || true)
printf '%s\n' "$M_UPDATES" | grep -q 'gc.routed_to=human' \
  && ok "(9) no fix pool -> anchor routed to human" \
  || bad "(9) no fix pool -> anchor routed to human (got: $M_UPDATES)"

# --- Run 5: zero gating anchors must NOT short-circuit the anchorless scan. ---
# Before the anchorless arm this pass returned early on an empty gating set. That
# is the worst possible place to go blind: zero live anchors WITH open PRs is
# precisely the stranded state the scan exists to surface.
: > "$TMP/anchors"
printf '305|false|polecat/dead-5|main\n' > "$TMP/openprs"
OUT5="$(bash "$SCRIPT" --fix-pool "$FIX_POOL")"
printf '%s\n' "$OUT5" | grep -q 'no gating anchors' \
  && ok "(15) empty gating set still reported" \
  || bad "(15) empty gating set still reported (got: $OUT5)"
printf '%s\n' "$OUT5" | grep -q 'ANCHORLESS PR#305' \
  && ok "(15) anchorless scan runs even with zero gating anchors" \
  || bad "(15) anchorless scan runs even with zero gating anchors (got: $OUT5)"

# --- Run 6: fail CLOSED when the live-bead read fails. -----------------------
# An empty ledger read is indistinguishable from "no bead tracks anything". If
# the scan trusted it, EVERY open PR would be flagged and escalated at once — a
# mail storm out of a transient Dolt blip. It must report nothing instead.
MAIL_BEFORE6=$(wc -l < "$TMP/mail" | tr -d ' ')
printf '306|false|polecat/dead-6|main\n' > "$TMP/openprs"
OUT6="$(FAKE_LIVE_FAIL=1 bash "$SCRIPT" --fix-pool "$FIX_POOL" 2>/dev/null)"
printf '%s\n' "$OUT6" | grep -q 'ANCHORLESS' \
  && bad "(14) failed live-bead read must not flag anything (fail closed)" \
  || ok "(14) failed live-bead read flags nothing (fail closed, no mail storm)"
eq "$(wc -l < "$TMP/mail" | tr -d ' ')" "$MAIL_BEFORE6" \
   "(14) failed live-bead read escalates nothing"
printf '%s\n' "$OUT6" | grep -q '0 anchorless open PRs' \
  && ok "(14) failed live-bead read reports a zero anchorless count" \
  || bad "(14) failed live-bead read reports a zero anchorless count (got: $OUT6)"

# --- (20) an unreadable rework probe must fail CLOSED. -----------------------
# The probe is the only thing standing between a conflicted PR and a dispatched
# force-push, so a FAILED read of it must never be mistaken for "nobody holds
# this branch". PR#216 and PR#217 are the live cases: both are held only by a
# bead the probe would have to return, so if the failure reads as "empty" the arm
# files a rebase child for each — dispatching exactly the force-push the operator
# froze. A deferred rebase costs one pass; an un-vetoed force-push is not
# recoverable by retry.
# Run 5 emptied the gating set to prove the anchorless scan still runs; restore
# the two anchors this case needs (neither carries stale_base_head — they have
# only ever exited the arm through a hold, before the stamp — so both reach the
# probe on this pass).
printf '%s\n' 'bead-P|216|main||' 'bead-Q|217|main||' > "$TMP/anchors"
CREATED_BEFORE7="$(wc -l < "$TMP/created" | tr -d ' ')"
OUT7="$(FAKE_PROBE_FAIL=1 bash "$SCRIPT" --fix-pool "$FIX_POOL" 2>/dev/null)"
eq "$(wc -l < "$TMP/created" | tr -d ' ')" "$CREATED_BEFORE7" \
   "(20) failed rework probe files NO rebase child (fail closed, no force-push)"
eq "$(grep -c 'Rebase PR#216' "$TMP/created")" "0" \
   "(20) failed probe -> still no child for the branch a keeper froze"
eq "$(grep -c 'Rebase PR#217' "$TMP/created")" "0" \
   "(20) failed probe -> still no child for the shared-branch PR"
printf '%s\n' "$OUT7" | grep -q '0 stale-base rebases routed' \
  && ok "(20) failed probe routes no rebases at all" \
  || bad "(20) failed probe must route zero rebases (got: $OUT7)"

# --- (23) a probe that FAILS WITH OUTPUT must also fail CLOSED. ---------------
# Case (20) covers the failure that is easy to spot: no output at all. These are
# the ones that are not. `gc ... --json` reports its own errors as a non-empty
# JSON object on stdout, so "did anything come back?" answers YES for a read that
# wholly failed; the object then yields zero rows through the projection and the
# arm concludes the branch is unowned.
#
# Each shape below defeats every guard except one, so each pins a DIFFERENT guard
# and none of them can be deleted without a red test. Same fixtures as (20) —
# PR#216 and PR#217 are held ONLY by beads the probe would have to return — so any
# shape that reads as "empty" force-pushes over exactly the freeze an operator
# just set. `[]` with a zero exit is NOT in this list: that is the legitimate
# "nobody holds it" answer, and cases (9)-(11) already cover it.
for shape in error-rc1 error-rc0 array-rc1 bad-array object-map; do
  CREATED_BEFORE8="$(wc -l < "$TMP/created" | tr -d ' ')"
  OUT8="$(FAKE_PROBE_SHAPE="$shape" bash "$SCRIPT" --fix-pool "$FIX_POOL" 2>/dev/null)"
  eq "$(wc -l < "$TMP/created" | tr -d ' ')" "$CREATED_BEFORE8" \
     "(23/$shape) unreadable probe files NO rebase child (fail closed)"
  eq "$(grep -c 'Rebase PR#216' "$TMP/created")" "0" \
     "(23/$shape) still no child for the branch a keeper froze"
  eq "$(grep -c 'Rebase PR#217' "$TMP/created")" "0" \
     "(23/$shape) still no child for the shared-branch PR"
  printf '%s\n' "$OUT8" | grep -q '0 stale-base rebases routed' \
    && ok "(23/$shape) routes no rebases at all" \
    || bad "(23/$shape) must route zero rebases (got: $OUT8)"
done

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
