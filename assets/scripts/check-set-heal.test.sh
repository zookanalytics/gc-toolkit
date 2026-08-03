#!/usr/bin/env bash
# Hermetic test for check-set-heal.sh (the refinery-boundary check-set
# normalization, tk-i48ca). Stubs `gc` (bead-ledger list/show/update/dep/create/
# session) on PATH. No live city, Dolt, network, or real pull requests.
#
# THE BUG. A hand-RECOVERED anchor never ran the merge-push step, so its check_set
# was never normalized: it reaches the refinery empty, merge-skill.sh reads empty
# as "no gates", and the PR merges with NO codex review. This pass runs BEFORE the
# merge skill and stamps the declared default on any gating anchor whose check_set
# is absent/empty, then dispatches the missing signoff so the armed gate is
# satisfiable. Only the explicit `none`/`off` sentinel is a real opt-out.
#
# Covered:
#   (EMPTY)  merge_result=pull_request, check_set="" -> stamp default + dispatch
#            signoff + BLOCKS edge + route to the codex pool.
#   (ABSENT) check_set key absent entirely -> same heal (absent == empty).
#   (SEP)    check_set=",,," names no gates -> healed (not a real gate list).
#   (NONE)   check_set="none" (the opt-out sentinel) -> LEFT ALONE, no dispatch.
#   (OFF)    check_set="off" -> LEFT ALONE.
#   (NORMAL) check_set="codex" -> LEFT ALONE (already normalized).
#   (GREEN)  empty check_set BUT check.codex already green -> stamp, NO dispatch
#            (the gate is already satisfiable).
#   (INFLGT) empty check_set BUT an open review already references the anchor ->
#            stamp, NO dispatch (reuse the in-flight review, never a twin).
#   (PREOPEN) a pre_open_gate anchor (no PR) with empty check_set -> stamp +
#            dispatch a BRANCH review (review_branch/review_base, no pr_number).
#   (ORDER)  the stamp is applied BEFORE the dispatch (fail-closed): the PR cannot
#            be left ungated-but-dispatched.
#   (STAMPFAIL) a stamp that does NOT persist is NOT counted healed and does NOT
#            dispatch — the anchor stays ungated and is retried, flagged once, and
#            the pass EXITS UNSAFE_RC (3) so the formula holds merge-skill.
#   (CONV)   a healed anchor (check_set_healed recorded, gate now satisfiable via
#            the dispatched review) is not re-stamped and not re-dispatched.
#   (RETRY)  a healed anchor whose dispatch FAILED last pass (healed recorded, gate
#            still unsatisfiable, nothing in flight) re-dispatches — the stamp did
#            not hide it from the satisfiability retry.
#   (LIVEOWN) a branch owned by a blocked / deferred / hooked / pinned child ->
#            NO dispatch (only `closed` releases a branch); an OPEN unrouted
#            non-review child is still inert -> DISPATCH.
#   (NOTE)   each re-gate's review_note is non-empty and carries THAT dispatch's
#            reason, and the same reason reaches the review BODY.
#   (MALFORMED) a non-empty marker that is not green@<hex oid> — `green`, `red`,
#            `green@`, `green@<junk>` — can never equal green@<live head>, so it
#            re-gates in BOTH sub-states and needs no head read; a well-formed
#            marker at the live head is untouched.
#   (DEADREV) a review that cannot raise THIS anchor's gate does not suppress the
#            re-gate: one whose anchor_bead write was lost (unrouted, unclaimed,
#            unattributable) and one that names ANOTHER anchor. A review naming
#            this anchor still suppresses it — no twins.
#   (PINNED) the live-head read carries BOTH halves of the origin pin — the `o/r`
#            path and the `--hostname` host — asserted on the argv gh was called
#            with, so a host word that expands to nothing fails by name.
#   (TERMINAL) a post-open anchor whose PR is MERGED or CLOSED is NOT re-gated
#            (that is reconcile-merged-prs.sh's to dispose of); an OPEN one still
#            is, an UNREADABLE state dispatches anyway (fail soft), and a pre-open
#            anchor is untouched by the guard and costs no PR read.
#   (ROUTEFAIL/REPAIR) a dropped gc.routed_to write is not counted as dispatched
#            and leaves the bead unrouted; the next pass re-routes the SAME bead.
#   (GATE)   the REAL formula wiring (heal-gates-merge, extracted from
#            mol-refinery-patrol.toml): a stamp-failing heal (rc=UNSAFE_RC) HOLDS
#            the merge-skill stub (no merge attempted); a clean heal lets it run.
#            This is the review tk-z4u2e finding #1 regression — a failed stamp used
#            to fall through to merge-skill in the SAME pass and merge un-reviewed.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/check-set-heal.sh"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-refinery-patrol.toml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { grep -q "$1" "$2" 2>/dev/null; }

mkdir -p "$TMP/bin"

# Gating anchors, one per line, across BOTH sub-states:
#   id|merge_result|check_set(literal, __ABSENT__ omits the key)|pr|branch|target|check.codex|check_set_healed
# check_set column values: EMPTY (a literal empty field), __ABSENT__ (omit the
# metadata key), or a real value. The stub reads the raw file each `gc bd list` so
# an `update` that rewrites check_set is reflected on the next pass (convergence).
cat > "$TMP/anchors" <<'A'
bead-EMPTY|pull_request|EMPTY|401|polecat/feat-empty|main||
bead-ABSENT|pull_request|__ABSENT__|402|polecat/feat-absent|main||
bead-SEP|pull_request|,,,|403|polecat/feat-sep|main||
bead-NONE|pull_request|none|404|polecat/feat-none|main||
bead-OFF|pull_request|off|405|polecat/feat-off|main||
bead-NORMAL|pull_request|codex|406|polecat/feat-normal|main|green@406406a|
bead-GREEN|pull_request|EMPTY|407|polecat/feat-green|main|green@407407a|
bead-INFLGT|pull_request|EMPTY|408|polecat/feat-inflgt|main||
bead-PREOPEN|pre_open_gate|EMPTY||polecat/feat-preopen|main||
A

# An open review already referencing bead-INFLGT (so the heal must NOT dispatch a
# twin). Format: review_id|anchor_bead|pr_number[|status|assignee]. The inflight
# lookup finds it via the pr_number and anchor_bead branches of inflight_for.
#
# anchor_bead is a real COLUMN, emitted only when non-empty, because whether a
# review names THIS anchor is what decides the identity half of the dedup: one that
# names another anchor is somebody else's, and one naming none (a lost write) is
# unroutable and unclaimable — neither may hold this gate (review tk-s8zx3 finding
# #3). A stub that stamped anchor_bead unconditionally could not express either.
cat > "$TMP/reviews" <<'R'
rev-inflgt|bead-INFLGT|408
R

# --- gc stub. ----------------------------------------------------------------
# bd list  : gating-anchor scans (merge_result=pull_request|pre_open_gate) built
#            from the anchors file (skipping any recorded as stamped in
#            $FAKE_STAMPED so a rewritten check_set is honoured next pass); the
#            in-flight lookups (pr_number=, anchor_bead=, branch=) from reviews;
#            the review-dedup lookups.
# bd show  : re-read check_set (from $FAKE_STAMPED overlay) + anchor_bead on a
#            review (from $FAKE_REVMETA).
# bd create: mint a review id, echo {"id":...}.
# bd update: record check_set stamps, routing, and review metadata.
# bd dep / session : record edges / no-op.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
[ "$1" = "bd" ] || { [ "$1" = "session" ] && exit 0; exit 0; }

# Current check_set for an anchor: the stamped overlay wins, else the anchors file
# (EMPTY/__ABSENT__ -> emitted as an empty metadata value; absent still absent).
cs_for() {
  local id="$1" v
  v=$(awk -F'\t' -v i="$id" '$1==i{print $2; found=1} END{if(!found)print "\x01"}' "$FAKE_STAMPED" 2>/dev/null)
  if [ "$v" != $'\x01' ]; then printf '%s' "$v"; return; fi
  awk -F'|' -v i="$id" '$1==i{print $3; exit}' "$FAKE_ANCHORS"
}
healed_for() {
  awk -F'\t' -v i="$1" '$1==i{print $2; exit}' "$FAKE_HEALED" 2>/dev/null
}

# One review row (id|anchor_bead|pr_number[|status|assignee]) -> the bead-shaped
# JSON array `gc bd list` returns, or `[]` for no match. Only NON-EMPTY identity
# fields are emitted, so a fixture can model a review whose anchor_bead write was
# lost (column blank) as distinct from one that names another anchor.
emit_review() {
  [ -n "${1:-}" ] || { printf '[]\n'; return; }
  printf '%s' "$1" | jq -R -c 'split("|")
    | {id: .[0], status: (if (.[3] // "") == "" then "open" else .[3] end),
       assignee: (.[4] // ""),
       metadata: ({task_kind: "review"}
                  + (if (.[1] // "") == "" then {} else {anchor_bead: .[1]} end)
                  + (if (.[2] // "") == "" then {} else {pr_number: .[2]} end))}
    | [.]'
}

case "$2" in
  list)
    case "$*" in
      *"merge_result=pull_request"*|*"merge_result=pre_open_gate"*)
        want=$(printf '%s' "$*" | sed -n 's/.*merge_result=\([a-z_]*\).*/\1/p')
        out=""
        while IFS='|' read -r id mr cs pr branch target codex healed hold; do
          [ -n "$id" ] || continue
          [ "$mr" = "$want" ] || continue
          # Live check_set: stamped overlay wins.
          live=$(cs_for "$id")
          # Emit the metadata object. An __ABSENT__ (and no stamp) omits check_set.
          csfield=""
          if [ "$live" != "__ABSENT__" ]; then
            [ "$live" = "EMPTY" ] && live=""
            csfield=$(printf ',"check_set":"%s"' "$live")
          fi
          # Live check_set_healed overlay.
          h=$(healed_for "$id"); [ -n "$h" ] || h="$healed"
          hfield=""; [ -n "$h" ] && hfield=$(printf ',"check_set_healed":"%s"' "$h")
          cxfield=""; [ -n "$codex" ] && cxfield=$(printf ',"check.codex":"%s"' "$codex")
          # The pr_url is the one the git stub's origin implies — `github.com/o/r` —
          # not a placeholder host. certify_pr_identity compares the bead's recorded
          # URL against the live one and REFUSES on a mismatch, and it now sits on the
          # dispatch path (the terminal-PR guard, review tk-w9ttd finding #2). A
          # fixture whose pr_url could never match would make every certification fail
          # for the wrong reason, so the fail-soft arm would be the only one any test
          # ever reached.
          prfield=""; [ -n "$pr" ] && prfield=$(printf ',"pr_number":"%s","pr_url":"https://github.com/o/r/pull/%s"' "$pr" "$pr")
          hdfield=""; [ -n "$hold" ] && hdfield=$(printf ',"merge_hold":"%s"' "$hold")
          obj=$(printf '{"id":"%s","title":"impl %s","metadata":{"merge_result":"%s","branch":"%s","merged_target":"%s"%s%s%s%s%s}}' \
            "$id" "$id" "$mr" "$branch" "$target" "$csfield" "$cxfield" "$hfield" "$prfield" "$hdfield")
          if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
        done < "$FAKE_ANCHORS"
        printf '[%s]\n' "$out" ;;
      # The in-flight probes. These emit REALISTIC bead rows — id + status +
      # metadata — not a bare {"id":...}: inflight_for now decides whether a
      # candidate will actually ACT on the gate (task_kind=review, or
      # in_progress, or pool-routed), so a row without those fields no longer
      # resembles the bead it stands for (tk-t46nq). Everything reachable through
      # the pr_number / anchor_bead probes IS a signoff review, so both emit
      # task_kind=review.
      *"pr_number="*)
        pnum=$(printf '%s' "$*" | sed -n 's/.*pr_number=\([0-9][0-9]*\).*/\1/p')
        row=$(awk -F'|' -v p="$pnum" '$3==p{print; exit}' "$FAKE_REVIEWS" 2>/dev/null)
        emit_review "$row" ;;
      *"anchor_bead="*)
        aid=$(printf '%s' "$*" | sed -n 's/.*anchor_bead=\([^ ]*\).*/\1/p')
        row=$(awk -F'|' -v a="$aid" '$2==a{print; exit}' "$FAKE_REVIEWS" 2>/dev/null)
        # Also honour a review minted THIS run (recorded in FAKE_REVMETA): it is a
        # review, it names this anchor, and it is unrouted until the route write
        # lands — exactly what the repair arm looks for on the next pass.
        if [ -z "$row" ]; then
          rid=$(awk -F'\t' -v a="$aid" '$2=="anchor_bead" && $3==a{print $1; exit}' "$FAKE_REVMETA" 2>/dev/null)
          [ -n "$rid" ] && row="$rid|$aid||open|"
        fi
        emit_review "$row" ;;
      # Branch-keyed probe: the rework children (and any sibling bead) that live on
      # an anchor's branch. Backed by $FAKE_BRANCHBEADS so a fixture can express
      # the exact discriminator this bug turns on — a rework still being WORKED vs
      # one already handed BACK.
      #   id|branch|status|task_kind|gc.routed_to|assignee
      #
      # ASSIGNEE IS A REAL COLUMN, and the handed-back fixtures fill it with the
      # refinery identity the refinery actually leaves there (review tk-w9ttd testing
      # gap). A hand-back is OPEN, unrouted and ASSIGNED BACK — three facts, of which
      # only the first two were modelled, so the row stood for a bead that does not
      # exist. That mattered in one direction: `acting()` deliberately does NOT read
      # assignee (a hand-back is assigned to the refinery precisely because the
      # refinery is DONE with it), and with the column blank a later change that
      # started treating assignee as liveness would suppress every re-gate in
      # production while this suite stayed green — the tk-t46nq park, re-introduced
      # invisibly. With the real value present, that change fails (HANDBACK) here.
      #
      # The --status list the caller asked for is HONOURED here, exactly as the real
      # `bd list` honours it. That is what makes the live-owner fixtures a real
      # regression: a probe that asks only for open,in_progress cannot see a
      # blocked/deferred/hooked/pinned branch owner at all, so the pass would
      # dispatch a review against a branch someone else still owns. A stub that
      # returned every row regardless of status would let the un-widened query pass.
      *"branch="*)
        br=$(printf '%s' "$*" | sed -n 's/.*branch=\([^ ]*\).*/\1/p')
        want_st=$(printf '%s' "$*" | sed -n 's/.*--status=\([^ ]*\).*/\1/p')
        out=""
        while IFS='|' read -r bid bbr bst btk brt basg; do
          [ -n "$bid" ] || continue
          [ "$bbr" = "$br" ] || continue
          if [ -n "$want_st" ]; then
            case ",$want_st," in *",$bst,"*) ;; *) continue ;; esac
          fi
          tkf=""; [ -n "$btk" ] && tkf=$(printf ',"task_kind":"%s"' "$btk")
          obj=$(printf '{"id":"%s","status":"%s","assignee":"%s","metadata":{"branch":"%s","gc.routed_to":"%s"%s}}' \
            "$bid" "$bst" "${basg:-}" "$bbr" "$brt" "$tkf")
          if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
        done < "$FAKE_BRANCHBEADS"
        printf '[%s]\n' "$out" ;;
      *) printf '[]\n' ;;
    esac ;;
  show)
    id="$3"
    cs=$(cs_for "$id")
    case "$cs" in EMPTY|__ABSENT__) cs="" ;; esac
    # EVERY metadata key recorded for this id, last write wins — not just
    # anchor_bead. route_review()'s read-back and the repair arm's unrouted-review
    # test both read gc.routed_to / task_kind back through `bd show`, so a stub that
    # only echoed anchor_bead would make the route read-back a tautology (always
    # empty -> every route "fails") and the repair arm untestable.
    # A REALISTIC row: id + status + assignee + metadata. `repair_review_routing`
    # re-routes only a review that is still OPEN, unclaimed and unrouted, and it
    # reads all three through `bd show` — a row carrying metadata alone would leave
    # status="" (never "open"), so every repair would refuse and the arm would be
    # untestable. Defaults are open/unclaimed; $FAKE_REVSTATE (id<TAB>status<TAB>
    # assignee) overrides, which is how the claimed-review guard is exercised.
    st=$(awk -F'\t' -v i="$id" '$1==i{print $2; exit}' "$FAKE_REVSTATE" 2>/dev/null)
    [ -n "$st" ] || st="open"
    asg=$(awk -F'\t' -v i="$id" '$1==i{print $3; exit}' "$FAKE_REVSTATE" 2>/dev/null)
    awk -F'\t' -v i="$id" '$1==i{v[$2]=$3} END{for (k in v) printf "%s\t%s\n", k, v[k]}' \
      "$FAKE_REVMETA" 2>/dev/null \
      | jq -R -s --arg cs "$cs" --arg id "$id" --arg st "$st" --arg asg "$asg" '
          [ split("\n")[] | select(length > 0) | split("\t")
            | {key: .[0], value: (.[1] // "")} ] | from_entries
          | (if $cs == "" then . else . + {check_set: $cs} end)
          | [{id: $id, status: $st, assignee: $asg, metadata: .}]' ;;
  create)
    # gc bd create "<title>" -t task [--body-file -] --json
    n=$(cat "$FAKE_SEQ" 2>/dev/null || echo 0); n=$((n + 1)); printf '%s' "$n" > "$FAKE_SEQ"
    # Capture the dispatched BODY (tk-jufvl). The review method arrives on stdin
    # via --body-file -; recording it per-bead is what lets the assertions below
    # prove the dispatch names a method instead of shipping a bare title.
    if printf '%s' "$*" | grep -q -- '--body-file -'; then
      cat > "$FAKE_BODIES/rev-new-$n" 2>/dev/null || true
    fi
    printf '{"id":"rev-new-%s"}\n' "$n" ;;
  update)
    id="$3"
    # Record a check_set stamp so the NEXT list/show reflects it (convergence).
    if printf '%s' "$*" | grep -q 'check_set='; then
      val=$(printf '%s' "$*" | sed -n 's/.*--set-metadata check_set=\([^ ]*\).*/\1/p')
      # Honour a deliberate stamp-fail injection: if this id is in FAKE_STAMPFAIL,
      # do NOT persist the check_set (simulate a lost ledger write).
      if ! grep -qx "$id" "$FAKE_STAMPFAIL" 2>/dev/null; then
        printf '%s\t%s\n' "$id" "$val" >> "$FAKE_STAMPED"
      fi
    fi
    if printf '%s' "$*" | grep -q 'check_set_healed='; then
      val=$(printf '%s' "$*" | sed -n 's/.*--set-metadata check_set_healed=\([^ ]*\).*/\1/p')
      printf '%s\t%s\n' "$id" "$val" >> "$FAKE_HEALED"
    fi
    if printf '%s' "$*" | grep -q 'check_set_heal_flagged='; then
      printf '%s\n' "$id" >> "$FAKE_FLAGGED"
    fi
    # Record review metadata (anchor_bead, routing, task_kind, review_branch,
    # review_note, ...) by walking the ARGUMENT VECTOR rather than "$*". A value
    # containing spaces — review_note carries a whole sentence — used to be
    # truncated at the first word by the old `sed` capture, so an assertion could
    # only prove that SOME review_note key was written, never that the reason
    # survived. The full value is recorded here so the fixtures can assert content.
    prev=""
    for arg in "$@"; do
      if [ "$prev" = "--set-metadata" ]; then
        k=${arg%%=*}; v=${arg#*=}
        case "$k" in
          anchor_bead|gc.routed_to|task_kind|check_name|review_branch|review_base|pr_number|pr_url|fix_target_pool|review_note)
            # Injected route-write failure ($FAKE_ROUTEFAIL non-empty): drop the
            # write, so the ledger never records the route and the script's
            # read-back sees the miss — the tk-3xy37 shape.
            if [ "$k" = "gc.routed_to" ] && grep -qs . "$FAKE_ROUTEFAIL"; then
              prev="$arg"; continue
            fi
            printf '%s\t%s\t%s\n' "$id" "$k" "$v" >> "$FAKE_REVMETA" ;;
        esac
      fi
      prev="$arg"
    done ;;
  dep)
    # gc bd dep <review> --blocks <anchor>
    rev="$3"; anchor=$(printf '%s' "$*" | sed -n 's/.*--blocks \([^ ]*\).*/\1/p')
    printf '%s\t%s\n' "$rev" "$anchor" >> "$FAKE_DEPS" ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

# --- git stub. ----------------------------------------------------------------
# `git remote get-url origin` is the ONE source the script trusts for "which
# repository is ours" — `live_head_for` pins its head read to it for the same reason
# `certify_pr_identity` pins its PR read (a bare `repos/{owner}/{repo}` resolves in
# whatever repository gh considers CURRENT). Answering it here is what makes the
# marker-vs-head fixtures exercise the real path instead of the unresolvable-origin
# fail-soft. $FAKE_NOORIGIN models a checkout with no usable origin.
cat > "$TMP/bin/git" <<'GIT'
#!/usr/bin/env bash
if [ "$1" = "remote" ] && [ "$2" = "get-url" ] && [ "$3" = "origin" ]; then
  [ -s "$FAKE_NOORIGIN" ] && exit 1
  printf 'https://github.com/o/r.git\n'; exit 0
fi
exit 0
GIT
chmod +x "$TMP/bin/git"

# --- gh stub. -----------------------------------------------------------------
# Two reads are stubbed:
#
#   gh api repos/<owner>/<repo>/commits/<branch> --jq .sha  — a branch's LIVE head,
#     for the marker-vs-head test (tk-t46nq). Backed by $FAKE_HEADS (branch<TAB>sha);
#     a branch with no entry exits non-zero and prints nothing, which is exactly the
#     "head unresolvable / no gh" fail-soft path.
#
#   gh pr view <n> --repo <host/owner/repo> --json ...     — the PR identity+state
#     `certify_pr_identity` certifies, which the terminal-PR guard on the dispatch
#     path now depends on (review tk-w9ttd finding #2). Backed by $FAKE_PRS
#     (number<TAB>state<TAB>headRefName); a number with no entry FAILS the view,
#     which is the unreadable-state fixture.
#
# Both reads are checked for their PIN, not just their subject. A read that is not
# pinned to the origin-derived repository answers for a repository that is not ours,
# and the head or state it returns would gate the wrong work.
#
# THE HOST HALF OF THE PIN IS ENFORCED HERE, not only the `o/r` half (review tk-w9ttd
# finding #1). `o/r` names one repository PER HOST, so a stub that accepted the path
# and ignored `--hostname` would pass a script that dropped the host word entirely —
# which is precisely the regression this file must catch, and precisely the one it
# used to miss. `${ORIGIN_HOST:+--hostname ...}` deletes itself SILENTLY when the
# variable is empty, so nothing but this check stands between a lost host pin and a
# green suite. Arguments are scanned rather than positional — `--hostname`, `--repo`
# and `--jq` may sit on either side of the subject.
#
# Every invocation is logged to $FAKE_GHLOG so a test can assert on the pin DIRECTLY,
# by argv, rather than only through the behaviour a refusal happens to produce.
cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_GHLOG" 2>/dev/null || true

# Scan for the pinning flags wherever they sit.
host=""; repo_flag=""; prev=""
for a in "$@"; do
  case "$prev" in
    --hostname) host="$a" ;;
    --repo)     repo_flag="$a" ;;
  esac
  prev="$a"
done

if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  num="$3"
  # HOST-QUALIFIED `--repo`, the form certify_pr_identity pins with.
  [ "$repo_flag" = "github.com/o/r" ] || exit 1
  row=$(awk -F'\t' -v n="$num" '$1==n{print; exit}' "$FAKE_PRS" 2>/dev/null)
  [ -n "$row" ] || exit 1
  st=$(printf '%s' "$row" | cut -f2)
  hd=$(printf '%s' "$row" | cut -f3)
  printf '{"state":"%s","baseRefName":"main","url":"https://github.com/o/r/pull/%s","headRefName":"%s","headRepositoryOwner":{"login":"o"},"headRepository":{"name":"r"}}\n' \
    "$st" "$num" "$hd"
  exit 0
fi

[ "$1" = "api" ] || exit 0
shift
path=""
for a in "$@"; do
  case "$a" in */commits/*) path="$a"; break ;; esac
done
[ -n "$path" ] || exit 1
repo=$(printf '%s' "$path" | sed -n 's|^repos/\(.*\)/commits/.*$|\1|p')
[ "$repo" = "o/r" ] || exit 1
[ "$host" = "github.com" ] || exit 1
ref=$(printf '%s' "$path" | sed -n 's|.*/commits/\(.*\)$|\1|p')
[ -n "$ref" ] || exit 1
sha=$(awk -F'\t' -v b="$ref" '$1==b{print $2; exit}' "$FAKE_HEADS" 2>/dev/null)
[ -n "$sha" ] || exit 1
printf '%s\n' "$sha"
GH
chmod +x "$TMP/bin/gh"

: > "$TMP/stamped"; : > "$TMP/healed"; : > "$TMP/flagged"; : > "$TMP/revmeta"
: > "$TMP/deps"; : > "$TMP/stampfail"; echo 0 > "$TMP/seq"
: > "$TMP/branchbeads"; : > "$TMP/heads"; : > "$TMP/routefail"
: > "$TMP/noorigin"; : > "$TMP/revstate"; : > "$TMP/prs"; : > "$TMP/ghlog"
mkdir -p "$TMP/bodies"

export PATH="$TMP/bin:$PATH"
export FAKE_ANCHORS="$TMP/anchors" FAKE_REVIEWS="$TMP/reviews" \
       FAKE_STAMPED="$TMP/stamped" FAKE_HEALED="$TMP/healed" \
       FAKE_FLAGGED="$TMP/flagged" FAKE_REVMETA="$TMP/revmeta" FAKE_DEPS="$TMP/deps" \
       FAKE_STAMPFAIL="$TMP/stampfail" FAKE_SEQ="$TMP/seq" FAKE_BODIES="$TMP/bodies" \
       FAKE_BRANCHBEADS="$TMP/branchbeads" FAKE_HEADS="$TMP/heads" \
       FAKE_ROUTEFAIL="$TMP/routefail" FAKE_NOORIGIN="$TMP/noorigin" \
       FAKE_REVSTATE="$TMP/revstate" FAKE_PRS="$TMP/prs" FAKE_GHLOG="$TMP/ghlog"

# --- Run 1. -------------------------------------------------------------------
RC1=0
OUT1="$(bash "$SCRIPT" \
  --default 'codex' \
  --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
  --fix-pool 'gc-toolkit/gc-toolkit.polecat')" || RC1=$?
eq "$RC1" "0" "(EXIT) a pass with no failed stamp exits 0 (merge-skill not held)"

# (EMPTY) empty check_set -> stamped codex.
grep -q '^bead-EMPTY	codex$' "$TMP/stamped" \
  && ok "(EMPTY) empty check_set stamped with the declared default 'codex'" \
  || bad "(EMPTY) empty check_set must be stamped codex (got: $(cat "$TMP/stamped"))"
# ...and a signoff dispatched (routed to the codex pool, anchor_bead recorded).
grep -q '	anchor_bead	bead-EMPTY$' "$TMP/revmeta" \
  && ok "(EMPTY) signoff dispatched with anchor_bead=bead-EMPTY" \
  || bad "(EMPTY) signoff must record anchor_bead (got: $(cat "$TMP/revmeta"))"
grep -q '	gc.routed_to	gc-toolkit/gc-toolkit.polecat-codex$' "$TMP/revmeta" \
  && ok "(EMPTY) signoff routed to the codex pool" || bad "(EMPTY) signoff routed to codex pool"

# (ABSENT) absent check_set key heals the same as empty.
grep -q '^bead-ABSENT	codex$' "$TMP/stamped" \
  && ok "(ABSENT) absent check_set key stamped codex (absent == empty)" \
  || bad "(ABSENT) absent check_set must heal"

# (SEP) separator-only names no gates -> healed.
grep -q '^bead-SEP	codex$' "$TMP/stamped" \
  && ok "(SEP) separator-only ',,,' stamped codex (names no gates)" \
  || bad "(SEP) separator-only must heal"

# (NONE)/(OFF) the opt-out sentinel is LEFT ALONE — never stamped, never dispatched.
has '^bead-NONE	' "$TMP/stamped" && bad "(NONE) opt-out sentinel must NOT be stamped" \
                                  || ok "(NONE) opt-out 'none' left alone (not stamped)"
grep -q '	anchor_bead	bead-NONE$' "$TMP/revmeta" && bad "(NONE) opt-out must NOT dispatch a signoff" \
                                                    || ok "(NONE) opt-out 'none' -> no signoff dispatched"
has '^bead-OFF	' "$TMP/stamped" && bad "(OFF) opt-out 'off' must NOT be stamped" \
                                 || ok "(OFF) opt-out 'off' left alone"

# (NORMAL) an already-normalized anchor is untouched.
has '^bead-NORMAL	' "$TMP/stamped" && bad "(NORMAL) already-normalized anchor must NOT be re-stamped" \
                                    || ok "(NORMAL) already-normalized 'codex' left alone"
grep -q '	anchor_bead	bead-NORMAL$' "$TMP/revmeta" && bad "(NORMAL) must NOT dispatch a twin signoff" \
                                                       || ok "(NORMAL) already-normalized -> no dispatch"

# (GREEN) empty check_set BUT check.codex already green -> stamp, NO dispatch.
grep -q '^bead-GREEN	codex$' "$TMP/stamped" \
  && ok "(GREEN) empty+green anchor still stamped codex (audit trail)" \
  || bad "(GREEN) empty+green anchor must be stamped"
grep -q '	anchor_bead	bead-GREEN$' "$TMP/revmeta" && bad "(GREEN) already-green gate must NOT dispatch" \
                                                     || ok "(GREEN) already-green gate -> stamp only, no dispatch"

# (INFLGT) empty check_set BUT an open review already references the anchor ->
# stamp, NO twin dispatch.
grep -q '^bead-INFLGT	codex$' "$TMP/stamped" \
  && ok "(INFLGT) empty anchor with in-flight review still stamped" \
  || bad "(INFLGT) empty anchor must be stamped"
grep -q '	anchor_bead	bead-INFLGT$' "$TMP/revmeta" && bad "(INFLGT) in-flight review must NOT be twinned" \
                                                       || ok "(INFLGT) in-flight review reused -> no twin dispatch"

# (PREOPEN) a pre_open_gate anchor heals + dispatches a BRANCH review.
grep -q '^bead-PREOPEN	codex$' "$TMP/stamped" \
  && ok "(PREOPEN) pre_open_gate anchor stamped codex" || bad "(PREOPEN) pre-open anchor must heal"
grep -q '	review_branch	polecat/feat-preopen$' "$TMP/revmeta" \
  && ok "(PREOPEN) pre-open signoff carries review_branch (BRANCH review, no PR)" \
  || bad "(PREOPEN) pre-open signoff must review the branch"
# The pre-open review must NOT carry a pr_number (no PR yet).
awk -F'\t' '$2=="anchor_bead" && $3=="bead-PREOPEN"{print $1}' "$TMP/revmeta" | while read -r rid; do
  grep -q "^$rid	pr_number	" "$TMP/revmeta" && echo "PREOPEN_HAS_PR" || true
done | grep -q PREOPEN_HAS_PR && bad "(PREOPEN) pre-open review must NOT carry pr_number" \
                              || ok "(PREOPEN) pre-open review has no pr_number (correct)"

# (ORDER) fail-closed: the stamp must be applied BEFORE the dispatch. A stamped +
# routed anchor proves the order held (routing is the last write); assert every
# dispatched anchor was also stamped.
DISPATCHED_ANCHORS=$(awk -F'\t' '$2=="anchor_bead"{print $3}' "$TMP/revmeta" | sort -u)
order_ok=1
for a in $DISPATCHED_ANCHORS; do
  grep -q "^$a	" "$TMP/stamped" || order_ok=0
done
[ "$order_ok" = 1 ] && ok "(ORDER) every dispatched anchor was stamped first (fail-closed)" \
                    || bad "(ORDER) a signoff was dispatched for an UNSTAMPED anchor"

# (BLOCKS) each dispatched review is linked BLOCKS its anchor.
grep -q '	bead-EMPTY$' "$TMP/deps" \
  && ok "(BLOCKS) dispatched review BLOCKS its anchor (gate-as-dep)" \
  || bad "(BLOCKS) review must BLOCK the anchor"

# (METHOD) EVERY dispatched signoff carries the review METHOD in its body
# (tk-jufvl). A title-only review bead names no method, so the reviewing polecat
# matches one out of its own skill catalog — the drift that ran a 6-persona
# fan-out at ~4.7M tokens per review. The body is what closes that vacuum, and it
# must be on every dispatch, PRE-OPEN as well as post-open.
DISPATCH_COUNT=$(awk -F'\t' '$2=="anchor_bead"{print $1}' "$TMP/revmeta" | sort -u | wc -l | tr -d ' ')
BODY_COUNT=$(find "$TMP/bodies" -type f | wc -l | tr -d ' ')
eq "$BODY_COUNT" "$DISPATCH_COUNT" "(METHOD) every dispatched signoff was created with a body"
method_ok=1; nofanout_ok=1; gate_ok=1
for b in "$TMP"/bodies/*; do
  [ -f "$b" ] || continue
  grep -qF 'signoff-review' "$b" || method_ok=0
  grep -qF 'Do NOT spawn' "$b" || nofanout_ok=0
  grep -qF 'green@' "$b" || gate_ok=0
done
[ "$BODY_COUNT" -gt 0 ] && [ "$method_ok" = 1 ] \
  && ok "(METHOD) every dispatched body names the signoff-review method" \
  || bad "(METHOD) a dispatched review body did not name the method"
[ "$BODY_COUNT" -gt 0 ] && [ "$nofanout_ok" = 1 ] \
  && ok "(METHOD) every dispatched body forbids subagent/persona fan-out" \
  || bad "(METHOD) a dispatched review body did not forbid fan-out"
[ "$BODY_COUNT" -gt 0 ] && [ "$gate_ok" = 1 ] \
  && ok "(METHOD) every dispatched body states the green@<oid> gate contract" \
  || bad "(METHOD) a dispatched review body did not state the gate contract"
# The PRE-OPEN dispatch specifically (it is the arm with no PR to fall back on).
PREOPEN_REV=$(awk -F'\t' '$2=="anchor_bead" && $3=="bead-PREOPEN"{print $1; exit}' "$TMP/revmeta")
if [ -n "$PREOPEN_REV" ] && [ -f "$TMP/bodies/$PREOPEN_REV" ]; then
  grep -qF 'signoff-review' "$TMP/bodies/$PREOPEN_REV" \
    && ok "(METHOD) the PRE-OPEN branch review also carries the method" \
    || bad "(METHOD) the PRE-OPEN branch review must carry the method"
else
  bad "(METHOD) no body captured for the PRE-OPEN dispatch"
fi

# Summary: 6 healed (EMPTY, ABSENT, SEP, GREEN, INFLGT, PREOPEN), and the opt-outs
# / normal untouched.
printf '%s\n' "$OUT1" | grep -q '6 healed' \
  && ok "run 1 summary reports 6 healed" || bad "run 1 summary healed count (got: $OUT1)"
printf '%s\n' "$OUT1" | grep -q '2 explicit opt-out' \
  && ok "run 1 summary reports 2 explicit opt-out" || bad "run 1 summary opt-out count (got: $OUT1)"

# --- Run 2: convergence. Healed anchors are not re-stamped; dispatched gates are
#     satisfiable (the review minted in run 1 is now in flight), so no re-dispatch.
: > "$TMP/revmeta2"; cp "$TMP/revmeta" "$TMP/revmeta.r1"
STAMPS_BEFORE=$(wc -l < "$TMP/stamped")
OUT2="$(bash "$SCRIPT" \
  --default 'codex' \
  --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
  --fix-pool 'gc-toolkit/gc-toolkit.polecat')"
STAMPS_AFTER=$(wc -l < "$TMP/stamped")
eq "$STAMPS_BEFORE" "$STAMPS_AFTER" "(CONV) no anchor re-stamped on the second pass"
printf '%s\n' "$OUT2" | grep -q '0 healed' \
  && ok "(CONV) run 2 heals nothing (all already normalized)" || bad "(CONV) run 2 must heal 0 (got: $OUT2)"
# The run-1 dispatched reviews are now in flight (recorded in FAKE_REVMETA and
# resolvable by anchor_bead), so run 2 dispatches no twins for them.
NEW_DISPATCH=$(comm -13 <(sort -u "$TMP/revmeta.r1") <(sort -u "$TMP/revmeta") | grep -c 'anchor_bead' || true)
eq "$NEW_DISPATCH" "0" "(CONV) no twin signoff dispatched on the second pass"

# --- Run 3: RETRY after a dispatch that failed. A previously-healed anchor whose
#     gate is still unsatisfiable (healed recorded, no marker, nothing in flight)
#     must re-dispatch — the stamp did NOT hide it from the satisfiability retry.
cat > "$TMP/anchors" <<'A'
bead-STRAND|pull_request|codex|409|polecat/feat-strand|main||codex
A
# healed recorded (run happened before) but NO review exists for it and NO marker.
: > "$TMP/reviews"; : > "$TMP/revmeta"; : > "$TMP/stamped"; : > "$TMP/deps"
bash "$SCRIPT" \
  --default 'codex' \
  --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
  --fix-pool 'gc-toolkit/gc-toolkit.polecat' >/dev/null
grep -q '	anchor_bead	bead-STRAND$' "$TMP/revmeta" \
  && ok "(RETRY) a healed anchor with an unsatisfiable gate re-dispatches the signoff" \
  || bad "(RETRY) healed-but-stranded anchor must re-dispatch (got: $(cat "$TMP/revmeta"))"
# It must NOT be re-stamped (check_set already 'codex').
has '^bead-STRAND	' "$TMP/stamped" && bad "(RETRY) already-normalized healed anchor must NOT be re-stamped" \
                                    || ok "(RETRY) healed anchor not re-stamped (check_set already normal)"

# --- Run 4: STAMPFAIL. A stamp that does not persist is NOT counted healed and
#     does NOT dispatch; the anchor is flagged once and retried.
cat > "$TMP/anchors" <<'A'
bead-FAIL|pull_request|EMPTY|410|polecat/feat-fail|main||
A
: > "$TMP/reviews"; : > "$TMP/revmeta"; : > "$TMP/stamped"; : > "$TMP/healed"
: > "$TMP/flagged"; : > "$TMP/deps"; echo 'bead-FAIL' > "$TMP/stampfail"
RC4=0
OUT4="$(bash "$SCRIPT" \
  --default 'codex' \
  --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
  --fix-pool 'gc-toolkit/gc-toolkit.polecat')" || RC4=$?
grep -q '	anchor_bead	bead-FAIL$' "$TMP/revmeta" && bad "(STAMPFAIL) a failed stamp must NOT dispatch a signoff" \
                                                    || ok "(STAMPFAIL) failed stamp -> no signoff dispatched (fail-closed)"
has '^bead-FAIL$' "$TMP/flagged" && ok "(STAMPFAIL) failed stamp flags the anchor once" \
                                 || bad "(STAMPFAIL) failed stamp must flag the anchor"
printf '%s\n' "$OUT4" | grep -q '0 healed' \
  && ok "(STAMPFAIL) a non-persisting stamp is NOT counted healed" || bad "(STAMPFAIL) must report 0 healed (got: $OUT4)"
# The unsafe exit: a still-ungated anchor must make the pass exit UNSAFE_RC (3) so
# the formula holds merge-skill this pass (review tk-z4u2e finding #1).
eq "$RC4" "3" "(STAMPFAIL) a failed stamp makes the pass exit UNSAFE rc=3"

# --- Run 5: a gateless-BY-CONFIG rig (--default none) heals to the sentinel, NOT
#     codex, and dispatches NOTHING — the repair restores declared intent.
cat > "$TMP/anchors" <<'A'
bead-CFGNONE|pull_request|EMPTY|411|polecat/feat-cfgnone|main||
A
: > "$TMP/reviews"; : > "$TMP/revmeta"; : > "$TMP/stamped"; : > "$TMP/healed"
: > "$TMP/flagged"; : > "$TMP/deps"; : > "$TMP/stampfail"
bash "$SCRIPT" --default 'none' --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' >/dev/null
grep -q '^bead-CFGNONE	none$' "$TMP/stamped" \
  && ok "(CFGNONE) a --default none rig heals empty -> the 'none' sentinel (declared intent)" \
  || bad "(CFGNONE) --default none must stamp the sentinel (got: $(cat "$TMP/stamped"))"
grep -q '	anchor_bead	bead-CFGNONE$' "$TMP/revmeta" && bad "(CFGNONE) a gateless rig must NOT dispatch a signoff" \
                                                       || ok "(CFGNONE) gateless-by-config -> no signoff dispatched"

# --- Run 5b: FAIL-SOFT method (tk-jufvl). If review-dispatch-body.sh cannot be
#     found — an older pack checkout, a partial deploy — the dispatch must STILL
#     happen. An un-dispatched signoff leaves the armed gate unsatisfiable and
#     holds the merge forever, which is strictly worse than a title-only bead. So
#     the missing emitter degrades to today's behaviour and WARNs; it never
#     aborts the heal. Proven against the REAL script copied into a directory
#     with no emitter beside it (no test-only env hook in the product code).
SOFT="$TMP/soft"; mkdir -p "$SOFT"
cp "$SCRIPT" "$SOFT/check-set-heal.sh"; chmod +x "$SOFT/check-set-heal.sh"
cat > "$TMP/anchors" <<'A'
bead-SOFT|pull_request|EMPTY|412|polecat/feat-soft|main||
A
: > "$TMP/reviews"; : > "$TMP/revmeta"; : > "$TMP/stamped"; : > "$TMP/healed"
: > "$TMP/flagged"; : > "$TMP/deps"; : > "$TMP/stampfail"
rm -f "$TMP"/bodies/*
RC5B=0
SOFT_ERR="$TMP/soft.err"
bash "$SOFT/check-set-heal.sh" --default 'codex' \
  --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
  --fix-pool 'gc-toolkit/gc-toolkit.polecat' >/dev/null 2>"$SOFT_ERR" || RC5B=$?
eq "$RC5B" "0" "(FAILSOFT) a missing method emitter does not fail the heal pass"
grep -q '	anchor_bead	bead-SOFT$' "$TMP/revmeta" \
  && ok "(FAILSOFT) the signoff is STILL dispatched without the emitter (gate stays satisfiable)" \
  || bad "(FAILSOFT) a missing emitter must not suppress the dispatch"
grep -q '	gc.routed_to	gc-toolkit/gc-toolkit.polecat-codex$' "$TMP/revmeta" \
  && ok "(FAILSOFT) the title-only fallback review is still routed" \
  || bad "(FAILSOFT) fallback review must still be routed"
grep -q 'TITLE-ONLY' "$SOFT_ERR" \
  && ok "(FAILSOFT) WARNs loudly that the dispatch carries no method" \
  || bad "(FAILSOFT) missing emitter must WARN (got: $(cat "$SOFT_ERR"))"

# --- Run 6: FORMULA GATING (heal-gates-merge). The finding this rework closes
#     (review tk-z4u2e #1): a stamp that did not persist used to exit 0, so the
#     formula ran merge-skill.sh in the SAME pass and the still-ungated anchor
#     merged un-reviewed. Extract the REAL gating snippet from the formula and
#     drive the REAL check-set-heal.sh into it with a merge-skill STUB — a
#     stamp-failing heal must HOLD the merge; a clean heal must let it run.
GATE="$(awk '
  /# >>> heal-gates-merge/ {f=1; next}
  /# <<< heal-gates-merge/ {f=0}
  f' "$TOML")"
[ -n "$GATE" ] \
  && ok "(GATE) heal-gates-merge snippet extracted from the formula" \
  || bad "(GATE) heal-gates-merge markers missing or renamed in the formula"
# Template-free so it executes directly (the {{...}} args are hoisted ABOVE the
# markers in the formula).
printf '%s' "$GATE" | grep -q '{{' \
  && bad "(GATE) extracted snippet still contains a {{template}} — hoist the args above the markers" \
  || ok "(GATE) heal-gates-merge snippet is template-free (executable verbatim)"

# Stub SCRIPTS_DIR: the REAL heal (symlinked) + a merge-skill STUB that records if
# it ran + a no-op pre-open-resolve. SCRIPTS_DIR must NOT be the real assets dir, or
# the real merge-skill.sh would run.
GSD="$TMP/scripts"; mkdir -p "$GSD"
ln -sf "$SCRIPT" "$GSD/check-set-heal.sh"
printf '#!/usr/bin/env bash\necho ran >> "$MERGE_SENTINEL"\nexit 0\n' > "$GSD/merge-skill.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$GSD/pre-open-resolve.sh"
chmod +x "$GSD/merge-skill.sh" "$GSD/pre-open-resolve.sh"
export MERGE_SENTINEL="$TMP/merge-ran"

# Build the runner: the env prologue IS expanded ($GSD resolves) but the extracted
# snippet is written via `printf %s` so its $? / ${...} survive verbatim (an
# unquoted heredoc would command-substitute them at build time).
{
  printf 'set -u\n'
  printf 'SCRIPTS_DIR=%q\n' "$GSD"
  printf "CHECK_SET_HEAL_ARGS=( --default codex --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' --fix-pool 'gc-toolkit/gc-toolkit.polecat' )\n"
  printf '%s\n' "$GATE"
  printf 'echo "MERGE_SKILL_HELD=$MERGE_SKILL_HELD"\n'
} > "$TMP/gaterun.sh"

# 6a: stamp FAILS -> real heal exits UNSAFE -> merge-skill is HELD (never runs).
cat > "$TMP/anchors" <<'A'
bead-GATEFAIL|pull_request|EMPTY|420|polecat/feat-gatefail|main||
A
: > "$TMP/reviews"; : > "$TMP/revmeta"; : > "$TMP/stamped"; : > "$TMP/healed"
: > "$TMP/flagged"; : > "$TMP/deps"; echo 'bead-GATEFAIL' > "$TMP/stampfail"
: > "$MERGE_SENTINEL"
GATEOUT="$(bash "$TMP/gaterun.sh" 2>/dev/null)"
[ -s "$MERGE_SENTINEL" ] && bad "(GATE-FAIL) merge-skill RAN despite an unsafe heal — ungated merge NOT prevented" \
                         || ok "(GATE-FAIL) an unsafe heal HELD merge-skill (no merge attempted)"
printf '%s\n' "$GATEOUT" | grep -q 'MERGE_SKILL_HELD=1' \
  && ok "(GATE-FAIL) the formula recorded MERGE_SKILL_HELD=1" \
  || bad "(GATE-FAIL) the formula did not set MERGE_SKILL_HELD (got: $GATEOUT)"

# 6b: stamp SUCCEEDS -> real heal exits 0 -> merge-skill RUNS.
: > "$TMP/reviews"; : > "$TMP/revmeta"; : > "$TMP/stamped"; : > "$TMP/healed"
: > "$TMP/flagged"; : > "$TMP/deps"; : > "$TMP/stampfail"
: > "$MERGE_SENTINEL"
GATEOUT2="$(bash "$TMP/gaterun.sh" 2>/dev/null)"
[ -s "$MERGE_SENTINEL" ] && ok "(GATE-OK) a clean heal lets merge-skill run" \
                         || bad "(GATE-OK) merge-skill did NOT run after a clean heal (got: $GATEOUT2)"
printf '%s\n' "$GATEOUT2" | grep -q 'MERGE_SKILL_HELD=0' \
  && ok "(GATE-OK) the formula recorded MERGE_SKILL_HELD=0" \
  || bad "(GATE-OK) the formula MERGE_SKILL_HELD should be 0 (got: $GATEOUT2)"

# --- Run 7: RE-GATE an ALREADY-NORMALIZED anchor (tk-t46nq). ------------------
# The bug: the satisfiability sweep was reachable only through the heal path, so
# an anchor the formula normalized normally (check_set=codex, no
# check_set_healed) was counted "already normalized" and its marker was never
# examined. A REQUEST_CHANGES signoff CLEARS check.codex and files a rework
# child; when that child lands and is handed back, the anchor holds a normal
# check_set, NO marker, and nothing in flight — and every automated pass looked
# away (this one skipped it; pre-open-resolve.sh can only HOLD; merge-skill.sh
# never sees a pre-open anchor). It parked until a human hand-dispatched the
# re-gate: four times inside one patrol on 2026-08-01.
#
# Fixtures, all with a NORMAL check_set (no healed mark) so every one of them
# would have been skipped outright before this fix:
#   RG-PRE   pre_open_gate, marker ABSENT, nothing in flight  -> DISPATCH (branch)
#   RG-POST  pull_request,  marker ABSENT, nothing in flight  -> DISPATCH (PR)
#   RG-BACK  pre_open_gate, marker ABSENT, rework child HANDED BACK (open,
#            unrouted, sitting on the anchor's branch)        -> DISPATCH
#   RG-WORK  pre_open_gate, marker ABSENT, rework child STILL BEING WORKED
#            (in_progress on the branch)                      -> NO dispatch
#   RG-POOL  pre_open_gate, marker ABSENT, rework child pool-ROUTED, unclaimed
#                                                             -> NO dispatch
#   RG-STALE pre_open_gate, green@OLD but the branch moved     -> DISPATCH
#   RG-FRESH pre_open_gate, green@<live head>                  -> NO dispatch
#   RG-PSTAL pull_request,  green@OLD, head moved -> NO dispatch (that is
#            reconcile-merged-prs.sh's stale-gate arm, which carries merge_hold
#            and one-re-review-per-head guards this pass does not)
#   RG-NOGH  pre_open_gate, green@OLD but the head will NOT resolve -> NO
#            dispatch (fail soft: a marker stays satisfiable without a head)
#   RG-HOLD  pre_open_gate, marker ABSENT, but merge_hold set -> NO dispatch
#            (operator gate; a re-gate is work toward landing, so it honours the
#            same hold reconcile-merged-prs.sh's stale-gate arm honours)
cat > "$TMP/anchors" <<'A'
RG-PRE|pre_open_gate|codex||polecat/rg-pre|main||
RG-POST|pull_request|codex|420|polecat/rg-post|main||
RG-BACK|pre_open_gate|codex||polecat/rg-back|main||
RG-WORK|pre_open_gate|codex||polecat/rg-work|main||
RG-POOL|pre_open_gate|codex||polecat/rg-pool|main||
RG-STALE|pre_open_gate|codex||polecat/rg-stale|main|green@a11a11a|
RG-FRESH|pre_open_gate|codex||polecat/rg-fresh|main|green@c33c33c|
RG-PSTAL|pull_request|codex|421|polecat/rg-pstal|main|green@a11a11a|
RG-NOGH|pre_open_gate|codex||polecat/rg-nogh|main|green@a11a11a|
RG-HOLD|pre_open_gate|codex||polecat/rg-hold|main|||1
RG-HEALHOLD|pre_open_gate|EMPTY||polecat/rg-healhold|main|||1
A
# The branch-resident beads. RG-BACK's child is the exact hand-back shape the
# refinery leaves behind: still OPEN, gc.routed_to cleared, and ASSIGNED BACK to the
# refinery — inert, because the only thing that would re-raise the gate is the
# dispatch this pass is deciding whether to make. The assignee is spelled out rather
# than left blank: it is the field most likely to be mistaken for liveness later, and
# a blank one would let that mistake pass this suite (see the branch probe above).
cat > "$TMP/branchbeads" <<'B'
rework-back|polecat/rg-back|open|||gc-toolkit/gc-toolkit.refinery
rework-work|polecat/rg-work|in_progress|||gc-toolkit__polecat-lx-88888
rework-pool|polecat/rg-pool|open||gc-toolkit/gc-toolkit.polecat|
B
# Live heads. RG-STALE/RG-PSTAL moved past a11a11a; RG-FRESH is still at its
# reviewed commit; RG-NOGH is deliberately absent so the stub exits non-zero.
printf 'polecat/rg-stale\tb22b22b\npolecat/rg-fresh\tc33c33c\npolecat/rg-pstal\tb22b22b\n' > "$TMP/heads"
: > "$TMP/reviews"; : > "$TMP/revmeta"; : > "$TMP/stamped"; : > "$TMP/healed"
: > "$TMP/flagged"; : > "$TMP/deps"; : > "$TMP/stampfail"; rm -f "$TMP"/bodies/*
OUT7="$(bash "$SCRIPT" \
  --default 'codex' \
  --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
  --fix-pool 'gc-toolkit/gc-toolkit.polecat')"

dispatched_for() { grep -q "	anchor_bead	$1\$" "$TMP/revmeta"; }

dispatched_for RG-PRE \
  && ok "(REGATE) already-normalized PRE-OPEN anchor with no marker re-dispatches the signoff" \
  || bad "(REGATE) pre-open anchor with an absent marker must re-dispatch (got: $(cat "$TMP/revmeta"))"
dispatched_for RG-POST \
  && ok "(REGATE) already-normalized POST-OPEN anchor with no marker re-dispatches the signoff" \
  || bad "(REGATE) post-open anchor with an absent marker must re-dispatch"
# The core regression: a handed-back rework child must NOT suppress the dispatch.
dispatched_for RG-BACK \
  && ok "(HANDBACK) a rework child already handed back does NOT count as in-flight — re-gate dispatched" \
  || bad "(HANDBACK) handed-back rework child wrongly suppressed the re-gate — the tk-t46nq park"
dispatched_for RG-WORK \
  && bad "(INFLIGHT) a rework still in_progress must suppress the dispatch (its branch is about to move)" \
  || ok "(INFLIGHT) rework still being worked -> no dispatch"
dispatched_for RG-POOL \
  && bad "(INFLIGHT) a pool-routed unclaimed rework must suppress the dispatch" \
  || ok "(INFLIGHT) pool-routed rework awaiting a claim -> no dispatch"
# Marker-vs-live-head, and the ownership split with reconcile-merged-prs.sh.
dispatched_for RG-STALE \
  && ok "(STALE) pre-open marker green at a head that MOVED re-dispatches (no other pass can see it)" \
  || bad "(STALE) stale pre-open marker must re-dispatch"
dispatched_for RG-FRESH \
  && bad "(FRESH) a marker green at the LIVE head must NOT dispatch" \
  || ok "(FRESH) marker green at the live head -> gate satisfiable, no dispatch"
dispatched_for RG-PSTAL \
  && bad "(SPLIT) a stale POST-OPEN marker belongs to reconcile-merged-prs.sh — dispatching here twins it" \
  || ok "(SPLIT) stale post-open marker left to reconcile's stale-gate arm (no twin)"
dispatched_for RG-NOGH \
  && bad "(HEADFAIL) an unresolvable head must fail SOFT — a present marker stays satisfiable" \
  || ok "(HEADFAIL) unresolvable branch head -> present marker treated as satisfiable (no dispatch)"
# THE HOST PIN, asserted on the ARGV of the head read itself (review tk-w9ttd
# finding #1). The behavioural consequence is already covered — the gh stub refuses a
# read that arrives without `--hostname github.com`, so a dropped pin also fails
# (STALE) — but that failure reads as "the stale marker did not re-gate" and points at
# the wrong code. This names the defect directly. It is a REGRESSION, not a
# refinement: `live_head_for` resolved the repo through a command substitution, so
# ORIGIN_HOST was set in a subshell, read back empty in the parent, and
# `${ORIGIN_HOST:+--hostname "$ORIGIN_HOST"}` expanded to NOTHING — the read fell back
# to gh's default host (GH_HOST, or github.com) with no error anywhere.
# `|| true`: this file runs under `set -euo pipefail`, so a grep that matches NOTHING
# fails the pipeline (pipefail) and the assignment aborts the WHOLE suite — turning
# "this assertion failed" into "the remaining assertions never ran", which is the one
# failure mode a regression suite must not have. No match is a legitimate outcome here;
# it is exactly what a regression looks like, and it must be REPORTED.
GH_HEAD_READ=$(grep 'commits/polecat/rg-stale' "$TMP/ghlog" 2>/dev/null | head -1 || true)
[ -n "$GH_HEAD_READ" ] \
  && ok "(PINNED) the marker-vs-head test actually read the branch head through gh" \
  || bad "(PINNED) no gh head read was recorded for RG-STALE"
printf '%s' "$GH_HEAD_READ" | grep -q -- '--hostname github.com' \
  && ok "(PINNED) the head read carries the origin HOST pin, not just the o/r path" \
  || bad "(PINNED) live_head_for must pass --hostname from the ORIGIN it resolved; a hostless read answers on whatever host GH_HOST names (got: '$GH_HEAD_READ')"
printf '%s' "$GH_HEAD_READ" | grep -q 'repos/o/r/commits/' \
  && ok "(PINNED) the head read is pinned to the origin-derived repository" \
  || bad "(PINNED) head read must name repos/o/r (got: '$GH_HEAD_READ')"
# The operator hold, and the deliberate asymmetry between the two paths.
dispatched_for RG-HOLD \
  && bad "(HOLD) a re-gate must honour merge_hold (a review on a held PR is spent quota)" \
  || ok "(HOLD) merge_hold suppresses the re-gate (operator gate)"
dispatched_for RG-HEALHOLD \
  && ok "(HOLD) merge_hold does NOT suppress the HEAL path — an ungated anchor must be armed regardless" \
  || bad "(HOLD) a held-but-UNGATED anchor must still heal+dispatch: it would merge un-reviewed once the hold lifts"
grep -q '^RG-HEALHOLD	codex$' "$TMP/stamped" \
  && ok "(HOLD) the held ungated anchor is still stamped (fail-closed beats the hold)" \
  || bad "(HOLD) held ungated anchor must still be stamped"
# The re-gate path never stamps check_set. RG-HEALHOLD is the only anchor here
# with an un-normalized check_set, so it is the only heal — every other fixture
# arrives already normalized and must leave with its check_set untouched.
printf '%s\n' "$OUT7" | grep -q '1 healed' \
  && ok "(REGATE) only the un-normalized anchor heals; re-gates stamp no check_set" \
  || bad "(REGATE) exactly 1 heal expected on the re-gate pass (got: $OUT7)"
STAMPED7=$(cut -f1 "$TMP/stamped" | sort -u | tr '\n' ' ')
eq "$STAMPED7" "RG-HEALHOLD " "(REGATE) no already-normalized anchor was re-stamped"
# The counters separate a re-gate from a heal-path dispatch.
printf '%s\n' "$OUT7" | grep -q '5 signoffs dispatched (4 of them re-gated)' \
  && ok "(REGATE) the summary counts 4 re-gates distinctly from heals" \
  || bad "(REGATE) summary must report 4 of 5 dispatches re-gated (got: $OUT7)"
# The reviewer is told WHY it was woken — without it a re-gate reads as a
# duplicate of the signoff that already ran. Asserted PER RE-GATED REVIEW and on
# the note's CONTENT: an unscoped `grep review_note` over the whole fixture set
# proves nothing, because it passes as long as ANY one dispatch wrote the key —
# every true re-gate could have lost its reason and the assertion would still be
# green. Scope to a known re-gate (RG-PRE, the absent-marker case; RG-STALE, the
# moved-head case) and require the reason itself.
note_for() { # <anchor> -> the review_note recorded on the review dispatched for it
  local rev
  rev=$(awk -F'\t' -v a="$1" '$2=="anchor_bead" && $3==a{print $1; exit}' "$TMP/revmeta")
  [ -n "$rev" ] || return 0
  awk -F'\t' -v r="$rev" '$1==r && $2=="review_note"{print $3; exit}' "$TMP/revmeta"
}
RGPRE_NOTE="$(note_for RG-PRE)"
RGSTALE_NOTE="$(note_for RG-STALE)"
[ -n "$RGPRE_NOTE" ] \
  && ok "(NOTE) the absent-marker re-gate records a NON-EMPTY review_note" \
  || bad "(NOTE) RG-PRE's re-gate must record a non-empty review_note"
printf '%s' "$RGPRE_NOTE" | grep -q 'absent' \
  && ok "(NOTE) the absent-marker re-gate's note states the marker was absent" \
  || bad "(NOTE) RG-PRE note must say the marker was absent (got: '$RGPRE_NOTE')"
[ -n "$RGSTALE_NOTE" ] \
  && ok "(NOTE) the stale-marker re-gate records a NON-EMPTY review_note" \
  || bad "(NOTE) RG-STALE's re-gate must record a non-empty review_note"
printf '%s' "$RGSTALE_NOTE" | grep -q 'a11a11a' && printf '%s' "$RGSTALE_NOTE" | grep -q 'b22b22b' \
  && ok "(NOTE) the stale-marker re-gate's note names the reviewed OID and the live head" \
  || bad "(NOTE) RG-STALE note must name both shas (got: '$RGSTALE_NOTE')"
# ...and the same reason reaches the bead BODY, not only its metadata. The body is
# what a reviewer actually reads; a reason parked in metadata alone leaves the
# re-gate looking like a duplicate of the signoff that already ran.
RGSTALE_REV=$(awk -F'\t' '$2=="anchor_bead" && $3=="RG-STALE"{print $1; exit}' "$TMP/revmeta")
if [ -n "$RGSTALE_REV" ] && [ -f "$TMP/bodies/$RGSTALE_REV" ]; then
  grep -qF 'Context from the dispatch' "$TMP/bodies/$RGSTALE_REV" \
    && grep -qF 'b22b22b' "$TMP/bodies/$RGSTALE_REV" \
    && ok "(NOTE) the re-gate reason is carried in the review BODY as well as metadata" \
    || bad "(NOTE) the re-gate body must carry the dispatch reason"
else
  bad "(NOTE) no body captured for the RG-STALE re-gate"
fi
# A re-gate is still a real signoff: pre-open reviews the BRANCH, post-open the PR.
grep -q '	review_branch	polecat/rg-pre$' "$TMP/revmeta" \
  && ok "(REGATE) the pre-open re-gate reviews the BRANCH compare-range" \
  || bad "(REGATE) pre-open re-gate must carry review_branch"
RGPOST_REV=$(awk -F'\t' '$2=="anchor_bead" && $3=="RG-POST"{print $1; exit}' "$TMP/revmeta")
grep -q "^$RGPOST_REV	pr_number	420\$" "$TMP/revmeta" \
  && ok "(REGATE) the post-open re-gate reviews the PR" \
  || bad "(REGATE) post-open re-gate must carry pr_number"

# --- Run 8: the re-gate converges. The review dispatched in run 7 is now in
#     flight, so a second pass must not twin it — the same convergence run 2
#     proves for the heal path.
cp "$TMP/revmeta" "$TMP/revmeta.r7"
bash "$SCRIPT" \
  --default 'codex' \
  --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
  --fix-pool 'gc-toolkit/gc-toolkit.polecat' >/dev/null
NEW_REGATE=$(comm -13 <(sort -u "$TMP/revmeta.r7") <(sort -u "$TMP/revmeta") | grep -c 'anchor_bead' || true)
eq "$NEW_REGATE" "0" "(REGATE-CONV) the dispatched re-gate is in flight -> no twin on the next pass"

# --- Run 9: LIVE BRANCH OWNERS. ----------------------------------------------
# `closed` is the only status that releases a branch. A child an operator PARKED
# (blocked/deferred), one sitting on an agent's hook, or a pinned one still OWNS
# the branch — reconcile-merged-prs.sh enumerates exactly that set (LIVE_STATUSES)
# before it force-pushes, for the same reason. The re-gate sweep's in-flight probe
# asked only for open,in_progress, so every one of these owners was INVISIBLE to
# it: the pass would dispatch a codex signoff against a branch that is frozen, on
# a hook, or otherwise owned by unresolved rework — reviewing a commit that is not
# final and spending codex quota to do it.
#
# LO-FREE is the control: the handed-back rework shape (status exactly `open`,
# unrouted, not a review) is the ONE live-status bead that is genuinely inert, and
# it must STILL dispatch. Widening the status set must not re-break tk-t46nq.
cat > "$TMP/anchors" <<'A'
LO-BLOCK|pre_open_gate|codex||polecat/lo-block|main||
LO-DEFER|pre_open_gate|codex||polecat/lo-defer|main||
LO-HOOK|pre_open_gate|codex||polecat/lo-hook|main||
LO-PIN|pre_open_gate|codex||polecat/lo-pin|main||
LO-FREE|pre_open_gate|codex||polecat/lo-free|main||
A
# LO-FREE's child carries the refinery assignee for the same reason RG-BACK's does:
# it is the hand-back control, and a blank assignee would make it agree with the
# suppressed cases by accident rather than by rule.
cat > "$TMP/branchbeads" <<'B'
rework-block|polecat/lo-block|blocked|||
rework-defer|polecat/lo-defer|deferred|||
rework-hook|polecat/lo-hook|hooked|||
rework-pin|polecat/lo-pin|pinned|||
rework-free|polecat/lo-free|open|||gc-toolkit/gc-toolkit.refinery
B
: > "$TMP/reviews"; : > "$TMP/revmeta"; : > "$TMP/stamped"; : > "$TMP/healed"
: > "$TMP/flagged"; : > "$TMP/deps"; : > "$TMP/stampfail"; : > "$TMP/heads"
rm -f "$TMP"/bodies/*
bash "$SCRIPT" \
  --default 'codex' \
  --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
  --fix-pool 'gc-toolkit/gc-toolkit.polecat' >/dev/null
for owner in BLOCK:blocked DEFER:deferred HOOK:hooked PIN:pinned; do
  a="LO-${owner%%:*}"; st="${owner##*:}"
  dispatched_for "$a" \
    && bad "(LIVEOWN) a $st rework child still owns the branch — no signoff may be dispatched over it" \
    || ok "(LIVEOWN) $st branch owner suppresses the re-gate (branch is not free)"
done
dispatched_for LO-FREE \
  && ok "(LIVEOWN) an OPEN unrouted non-review child is still inert — the re-gate dispatches (tk-t46nq intact)" \
  || bad "(LIVEOWN) widening the status set must NOT re-suppress the handed-back rework case"

# --- Run 10: ROUTE PERSISTENCE + REPAIR. -------------------------------------
# gc.routed_to is what makes a review claimable. Writing it best-effort — without
# reading it back — is the one failure that strands the gate FOREVER: the review is
# created (so the in-flight probe counts it, being a task_kind=review) but no pool
# can claim it, so every later pass suppresses its own dispatch and waits on a bead
# nothing can action. Nothing else owns the pre-open re-gate, so nothing recovers
# it. This is the tk-3xy37 finding, whose repair contract reconcile-merged-prs.sh
# already carries (arm_stale_gate + the unrouted-review repair arm).
#
# 10a: the route write is DROPPED. The dispatch must NOT be reported, and the bead
#      must be left unrouted rather than counted as sent.
cat > "$TMP/anchors" <<'A'
RT-PRE|pre_open_gate|codex||polecat/rt-pre|main||
A
: > "$TMP/reviews"; : > "$TMP/revmeta"; : > "$TMP/stamped"; : > "$TMP/healed"
: > "$TMP/flagged"; : > "$TMP/deps"; : > "$TMP/stampfail"; : > "$TMP/branchbeads"
rm -f "$TMP"/bodies/*
echo 'ALL' > "$TMP/routefail"
RT_ERR="$TMP/rt.err"; RC10=0
OUT10="$(bash "$SCRIPT" \
  --default 'codex' \
  --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
  --fix-pool 'gc-toolkit/gc-toolkit.polecat' 2>"$RT_ERR")" || RC10=$?
eq "$RC10" "0" "(ROUTEFAIL) a failed route is best-effort (rc=0): the anchor is gated, not ungated"
dispatched_for RT-PRE \
  && ok "(ROUTEFAIL) the review bead itself was still created and anchored" \
  || bad "(ROUTEFAIL) the review should exist (only its route failed)"
grep -q '	gc.routed_to	' "$TMP/revmeta" \
  && bad "(ROUTEFAIL) the route did not persist — nothing may record it as routed" \
  || ok "(ROUTEFAIL) no route recorded (the write was dropped)"
printf '%s\n' "$OUT10" | grep -q '0 signoffs dispatched' \
  && ok "(ROUTEFAIL) an unrouted review is NOT counted as dispatched" \
  || bad "(ROUTEFAIL) must report 0 dispatched (got: $OUT10)"
grep -q "did not record gc.routed_to" "$RT_ERR" \
  && ok "(ROUTEFAIL) WARNs that the route did not persist" \
  || bad "(ROUTEFAIL) must WARN on a dropped route (got: $(cat "$RT_ERR"))"

# 10b: the next pass REPAIRS it — re-routes the SAME bead, never a twin. Without
#      the repair arm the in-flight probe would find this inert review and skip
#      forever, which is precisely the silent hold.
: > "$TMP/routefail"
cp "$TMP/revmeta" "$TMP/revmeta.r10a"
OUT10B="$(bash "$SCRIPT" \
  --default 'codex' \
  --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
  --fix-pool 'gc-toolkit/gc-toolkit.polecat')"
grep -q '	gc.routed_to	gc-toolkit/gc-toolkit.polecat-codex$' "$TMP/revmeta" \
  && ok "(REPAIR) the unrouted signoff is re-routed on the next pass" \
  || bad "(REPAIR) an unrouted signoff must be repaired (got: $(cat "$TMP/revmeta"))"
RT_REVS=$(awk -F'\t' '$2=="anchor_bead" && $3=="RT-PRE"{print $1}' "$TMP/revmeta" | sort -u | wc -l | tr -d ' ')
eq "$RT_REVS" "1" "(REPAIR) the repair re-routes the SAME review — no twin dispatched"
# A repair IS a dispatch: the signoff reaches the pool on this pass, having been
# created on the last one. It is reported as such, and named STRANDED so the log
# says which of the two it was.
printf '%s\n' "$OUT10B" | grep -q 'had a STRANDED signoff .* re-routed to' \
  && ok "(REPAIR) the pass names the re-route as a repair of a stranded signoff" \
  || bad "(REPAIR) must report the stranded re-route (got: $OUT10B)"
printf '%s\n' "$OUT10B" | grep -q '1 signoffs dispatched' \
  && ok "(REPAIR) the repaired signoff counts as dispatched — it is claimable now" \
  || bad "(REPAIR) must count the repair as 1 dispatched (got: $OUT10B)"

# --- Run 11: MALFORMED MARKERS (review tk-s8zx3 finding #2). ------------------
# A non-empty check.codex was treated as "present, therefore satisfiable" unless a
# live-head comparison said otherwise — and that comparison only ever ran on a
# `green@<oid>` value. So `green`, `red`, `green@` and `green@<not-an-oid>` fell
# straight through to the satisfiable exit, in BOTH sub-states. None of them can
# ever clear the merge: merge-skill.sh compares the marker for STRING EQUALITY
# against `green@<live head>`. And nothing else repairs them —
# reconcile-merged-prs.sh's stale-gate arm matches `green@<non-empty oid>` too, so
# it never sees these either. The anchor parked: gate armed, no dispatch, no
# escalation, no merge. Both sub-states re-gate now, and dispatching post-open
# cannot twin reconcile's arm precisely because that arm never acts on this shape.
#
#   MAL-BARE  pre_open_gate, check.codex=green      -> DISPATCH
#   MAL-RED   pull_request,  check.codex=red        -> DISPATCH
#   MAL-AT    pre_open_gate, check.codex=green@     -> DISPATCH (empty oid)
#   MAL-JUNK  pull_request,  check.codex=green@nope -> DISPATCH (oid is not hex)
#   MAL-OK    pre_open_gate, green@<live head>      -> NO dispatch (control: the
#             well-formed value still reads as satisfiable)
cat > "$TMP/anchors" <<'A'
MAL-BARE|pre_open_gate|codex||polecat/mal-bare|main|green|
MAL-RED|pull_request|codex|430|polecat/mal-red|main|red|
MAL-AT|pre_open_gate|codex||polecat/mal-at|main|green@|
MAL-JUNK|pull_request|codex|431|polecat/mal-junk|main|green@nope|
MAL-OK|pre_open_gate|codex||polecat/mal-ok|main|green@d44d44d|
A
printf 'polecat/mal-ok\td44d44d\n' > "$TMP/heads"
: > "$TMP/reviews"; : > "$TMP/revmeta"; : > "$TMP/stamped"; : > "$TMP/healed"
: > "$TMP/flagged"; : > "$TMP/deps"; : > "$TMP/branchbeads"; rm -f "$TMP"/bodies/*
OUT11="$(bash "$SCRIPT" \
  --default 'codex' \
  --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
  --fix-pool 'gc-toolkit/gc-toolkit.polecat')"
for m in MAL-BARE MAL-RED MAL-AT MAL-JUNK; do
  dispatched_for "$m" \
    && ok "(MALFORMED) $m re-gates — its marker can never equal green@<live head>" \
    || bad "(MALFORMED) $m must re-gate: a malformed marker holds the merge forever"
done
dispatched_for MAL-OK \
  && bad "(MALFORMED) a WELL-FORMED marker at the live head must still be satisfiable" \
  || ok "(MALFORMED) control: green@<live head> is untouched by the well-formedness rule"
# The reviewer is told which value was rejected — "re-gated" with no reason reads
# as a duplicate of the signoff that already ran.
MALBARE_NOTE="$(note_for MAL-BARE)"
printf '%s' "$MALBARE_NOTE" | grep -q "green@<oid> form" \
  && ok "(MALFORMED) the re-gate reason names the form the merge gate requires" \
  || bad "(MALFORMED) note must explain the malformed marker (got: '$MALBARE_NOTE')"
# No live head is consulted to reach this verdict: whatever the head is, the value
# cannot match it. MAL-BARE/MAL-AT have no entry in $TMP/heads at all, so a rule
# that needed one would have fallen soft into "satisfiable" and dispatched nothing.
printf '%s\n' "$OUT11" | grep -q '4 of them re-gated' \
  && ok "(MALFORMED) all four malformed markers re-gate without a head read" \
  || bad "(MALFORMED) expected 4 re-gates (got: $OUT11)"

# --- Run 12: a review that cannot raise THIS gate must not suppress it. -------
# (review tk-s8zx3 finding #3.) The in-flight probes key on pr_number and branch,
# which are not this anchor's identity — a review surfaced by them may be about
# something else entirely, and suppressing on one is not a delay but a permanent
# hold, because nothing re-examines the decision. Two mechanically reachable
# shapes, both of which used to park the anchor:
#
#   DEAD-DROP  a review carrying this anchor's pr_number and task_kind=review, but
#              whose anchor_bead write was LOST — it is unrouted and unclaimed, so
#              no polecat can claim it and `repair_review_routing` will not touch
#              it (it cannot be attributed to any anchor). It can never stamp any
#              gate. -> DISPATCH.
#   DEAD-OTHER a review that names ANOTHER anchor while carrying this PR's number.
#              It will stamp that anchor's gate, never this one. -> DISPATCH.
#   DEAD-LIVE  the control: a review that names THIS anchor. -> NO dispatch.
cat > "$TMP/anchors" <<'A'
DEAD-DROP|pull_request|codex|440|polecat/dead-drop|main||
DEAD-OTHER|pull_request|codex|441|polecat/dead-other|main||
DEAD-LIVE|pull_request|codex|442|polecat/dead-live|main||
A
# id|anchor_bead|pr_number|status|assignee — the blank anchor_bead IS the fixture.
cat > "$TMP/reviews" <<'R'
rev-dropped||440|open|
rev-foreign|SOMEONE-ELSE|441|open|
rev-live|DEAD-LIVE|442|open|
R
: > "$TMP/revmeta"; : > "$TMP/stamped"; : > "$TMP/healed"; : > "$TMP/flagged"
: > "$TMP/deps"; : > "$TMP/heads"; : > "$TMP/branchbeads"; rm -f "$TMP"/bodies/*
OUT12="$(bash "$SCRIPT" \
  --default 'codex' \
  --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
  --fix-pool 'gc-toolkit/gc-toolkit.polecat')"
dispatched_for DEAD-DROP \
  && ok "(DEADREV) a review whose anchor_bead was lost is inert — it does not suppress the re-gate" \
  || bad "(DEADREV) DEAD-DROP must re-gate: nothing can route, claim or attribute that review"
dispatched_for DEAD-OTHER \
  && ok "(DEADREV) a review naming ANOTHER anchor does not hold this one's gate" \
  || bad "(DEADREV) DEAD-OTHER must re-gate: that review stamps somebody else's anchor"
dispatched_for DEAD-LIVE \
  && bad "(DEADREV) a review that names THIS anchor must still suppress the dispatch (no twins)" \
  || ok "(DEADREV) control: a review naming this anchor is in flight — no twin dispatched"
printf '%s\n' "$OUT12" | grep -q '2 of them re-gated' \
  && ok "(DEADREV) exactly the two unactionable reviews are re-gated past" \
  || bad "(DEADREV) expected 2 re-gates (got: $OUT12)"

# --- Run 13: TERMINAL PRs are not re-gated (review tk-w9ttd finding #2). ------
# This pass runs BEFORE reconcile-merged-prs.sh in the same patrol, and the widened
# satisfiability sweep reaches post-open anchors it never used to examine. An ABSENT
# marker is the NORMAL shape behind a MERGED PR — the signoff that cleared it has
# nothing left to re-stamp — so without a state check the sweep dispatches a codex
# review, in real quota, for a pull request nobody can merge, and routes an inert
# review child into the codex pool ahead of the observer that was about to close the
# anchor. Same for a PR an operator CLOSED out of band, which needs an escalation,
# not a reviewer.
#
#   TP-MERGED  pull_request, marker ABSENT, PR MERGED   -> NO dispatch
#   TP-CLOSED  pull_request, marker ABSENT, PR CLOSED   -> NO dispatch
#   TP-MALF    pull_request, marker MALFORMED, PR MERGED -> NO dispatch (the
#              malformed arm reaches the same guard; it is the marker that is
#              unmeetable, but the PR is what makes the review pointless)
#   TP-OPEN    pull_request, marker ABSENT, PR OPEN     -> DISPATCH (the control:
#              the guard must not suppress the case tk-t46nq exists to fix)
#   TP-UNREAD  pull_request, marker ABSENT, PR state UNREADABLE -> DISPATCH. The
#              guard fails SOFT in the dispatch direction on purpose: one wasted
#              review that reconcile disposes of the same pass is cheaper than
#              re-creating the park, and a gh-less rig must behave exactly as it did
#              before the guard existed.
#   TP-PRE     pre_open_gate, marker ABSENT             -> DISPATCH (no PR to be
#              terminal; the guard must not touch the pre-open path at all)
cat > "$TMP/anchors" <<'A'
TP-MERGED|pull_request|codex|450|polecat/tp-merged|main||
TP-CLOSED|pull_request|codex|451|polecat/tp-closed|main||
TP-MALF|pull_request|codex|452|polecat/tp-malf|main|green@|
TP-OPEN|pull_request|codex|453|polecat/tp-open|main||
TP-UNREAD|pull_request|codex|454|polecat/tp-unread|main||
TP-PRE|pre_open_gate|codex||polecat/tp-pre|main||
A
# number<TAB>state<TAB>headRefName. TP-UNREAD is deliberately ABSENT so the view
# fails — the unreadable-state fixture. The head refs match each anchor's branch
# because certify_pr_identity refuses a PR opened from another branch, and a
# certification that failed for THAT reason would take the fail-soft arm and prove
# nothing about the states below.
printf '450\tMERGED\tpolecat/tp-merged\n451\tCLOSED\tpolecat/tp-closed\n452\tMERGED\tpolecat/tp-malf\n453\tOPEN\tpolecat/tp-open\n' > "$TMP/prs"
: > "$TMP/reviews"; : > "$TMP/revmeta"; : > "$TMP/stamped"; : > "$TMP/healed"
: > "$TMP/flagged"; : > "$TMP/deps"; : > "$TMP/heads"; : > "$TMP/branchbeads"
: > "$TMP/ghlog"; rm -f "$TMP"/bodies/*
OUT13="$(bash "$SCRIPT" \
  --default 'codex' \
  --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
  --fix-pool 'gc-toolkit/gc-toolkit.polecat' 2>"$TMP/err13")"
dispatched_for TP-MERGED \
  && bad "(TERMINAL) a MERGED PR must not be re-gated — the review lands on work nobody can merge, ahead of the observer that closes the anchor" \
  || ok "(TERMINAL) merged PR -> no signoff dispatched (reconcile-merged-prs.sh disposes of it)"
dispatched_for TP-CLOSED \
  && bad "(TERMINAL) a CLOSED PR must not be re-gated — it needs an escalation, not a reviewer" \
  || ok "(TERMINAL) closed PR -> no signoff dispatched"
dispatched_for TP-MALF \
  && bad "(TERMINAL) the malformed-marker arm must reach the terminal guard too" \
  || ok "(TERMINAL) malformed marker on a merged PR -> still no dispatch"
dispatched_for TP-OPEN \
  && ok "(TERMINAL) control: an OPEN PR with an absent marker still re-gates" \
  || bad "(TERMINAL) the guard must NOT suppress an open PR — that is the tk-t46nq park"
dispatched_for TP-UNREAD \
  && ok "(TERMINAL) an unreadable PR state fails SOFT — the signoff is dispatched anyway" \
  || bad "(TERMINAL) suppressing on an unreadable state re-creates the park this sweep ends"
dispatched_for TP-PRE \
  && ok "(TERMINAL) a pre-open anchor has no PR to be terminal — re-gate unaffected" \
  || bad "(TERMINAL) the terminal-PR guard must not touch the pre-open path"
printf '%s\n' "$OUT13" | grep -q '3 of them re-gated' \
  && ok "(TERMINAL) exactly the three non-terminal anchors re-gate" \
  || bad "(TERMINAL) expected 3 re-gates (got: $OUT13)"
# The operator is TOLD why the anchor was passed over, and who owns it now — a
# silent skip on a gating anchor is indistinguishable from the park.
printf '%s\n' "$OUT13" | grep -q 'TP-MERGED (PR#450) needs a re-gate.*MERGED' \
  && ok "(TERMINAL) the skip names the anchor, the PR and its terminal state" \
  || bad "(TERMINAL) the skip must be logged with the PR state (got: $OUT13)"
printf '%s\n' "$OUT13" | grep -q 'reconcile-merged-prs.sh' \
  && ok "(TERMINAL) the skip names the pass that owns the disposition" \
  || bad "(TERMINAL) the skip must say which pass disposes of the anchor"
grep -q 'TP-UNREAD.*dispatching the signoff anyway' "$TMP/err13" \
  && ok "(TERMINAL) the fail-soft dispatch says what it did about the unreadable state" \
  || bad "(TERMINAL) an unreadable state must warn AND say the signoff went out anyway (got: $(cat "$TMP/err13"))"
# The state read is PINNED, exactly as the head read is: `gh pr view <n> --repo
# <host>/<owner>/<repo>`. Unpinned, the number answers in whatever repository gh
# considers current, and a FOREIGN closed PR would suppress a signoff this anchor
# genuinely needs — a park caused by the very guard meant to prevent waste.
GH_PR_READ=$(grep '^pr view 450' "$TMP/ghlog" 2>/dev/null | head -1 || true)   # see (PINNED)
printf '%s' "$GH_PR_READ" | grep -q -- '--repo github.com/o/r' \
  && ok "(TERMINAL) the PR state read is pinned host-qualified to this checkout's origin" \
  || bad "(TERMINAL) certify_pr_identity must pin the state read (got: '$GH_PR_READ')"
# A pre-open anchor must not cost a PR read at all — it has no PR.
grep -q 'pr view.*polecat/tp-pre' "$TMP/ghlog" 2>/dev/null \
  && bad "(TERMINAL) a pre-open anchor must not trigger a PR state read" \
  || ok "(TERMINAL) no PR read is made for the pre-open anchor"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
