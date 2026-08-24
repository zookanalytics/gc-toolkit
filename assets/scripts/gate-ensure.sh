#!/usr/bin/env bash
# gate-ensure — arm 1 of the merge cadence (refinery-reconcile.sh).
# For every open anchor in pre_open_gate/pull_request: canonicalize check_set
# (empty/absent -> stamp the declared default; a list or the `none` opt-out is
# left alone), then ensure every declared, non-green gate is RAISABLE: marker
# green at the live branch head, a live routed/claimed review bead in flight,
# or a fresh dispatch — stamp first (fail-closed), review bead body from
# review-dispatch-body.sh, metadata + blocks edge + direct gc.routed_to stamp
# (stamp-don't-sling: a bare sling would be hijacked by default_sling_formula),
# anchor link and route read back before the dispatch is counted. The dispatch
# pins reviewed_oid=<live head> so signoff.sh binds the verdict to the commit
# the review was dispatched for, and stamps fix_target_pool so a
# request-changes rework routes to the driver-derived pool. Before creating, a
# title probe adopts a created-but-unstamped orphan from a prior failed stamp
# instead of minting a twin every pass.
# Args: --default <check_set> --review-pool <pool> [--fix-pool <pool>].
# Exits: 0 ok (a dispatch failure leaves the gate armed and merge HELD);
# 3 = a gating anchor could not be made safe (unreadable enumeration, or a
# check_set stamp that did not persist) — the driver holds merge.sh this pass.
set -u

PROG="gate-ensure"
UNSAFE_RC=3
scrub() { tr -d '\000-\010\013\014\016-\037'; }

DEFAULT_CHECK_SET="codex"
REVIEW_POOL=""
FIX_POOL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --default)     DEFAULT_CHECK_SET="${2:-codex}"; shift 2 ;;
    --review-pool) REVIEW_POOL="${2:-}"; shift 2 ;;
    --fix-pool)    FIX_POOL="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

# Canonical check_set form: lowercase, whitespace/separators stripped.
cs_canon() { printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:],'; }
case "$(cs_canon "$DEFAULT_CHECK_SET")" in
  '')       DEFAULT_CHECK_SET="codex" ;;
  none|off) DEFAULT_CHECK_SET="none" ;;
esac

SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
BODY_EMITTER="$SCRIPTS_DIR/review-dispatch-body.sh"

# Origin pin for the live-head read; optional — an unresolvable origin or a
# missing gh degrades to treating a present marker as satisfiable.
ORIGIN_HOST=""; ORIGIN_REPO=""
u=$(git remote get-url origin 2>/dev/null | tr -d '[:space:]')
case "$u" in
  git@github.com:*|https://github.com/*|ssh://git@github.com/*)
    ORIGIN_HOST="github.com"
    ORIGIN_REPO=$(printf '%s' "$u" | sed -e 's#^ssh://git@github.com/##' \
      -e 's#^git@github.com:##' -e 's#^https://github.com/##' -e 's#\.git$##' -e 's#/*$##') ;;
esac
case "$ORIGIN_REPO" in */*/*|/*|*/) ORIGIN_REPO="" ;; */*) : ;; *) ORIGIN_REPO="" ;; esac
[ -n "$ORIGIN_REPO" ] || ORIGIN_HOST=""
HAVE_GH=0; command -v gh >/dev/null 2>&1 && HAVE_GH=1

live_head_for() { # <branch> -> sha, or nothing when unanswerable
  [ "$HAVE_GH" = 1 ] && [ -n "$ORIGIN_REPO" ] && [ -n "${1:-}" ] || return 0
  gh api --hostname "$ORIGIN_HOST" "repos/$ORIGIN_REPO/commits/$1" --jq '.sha' 2>/dev/null
}

# Guarded list read: non-zero means "could not tell", never "nothing there".
bd_list() {
  local raw rc
  raw=$(gc bd list "$@" --limit=0 --json 2>/dev/null); rc=$?
  [ "$rc" -eq 0 ] && [ -n "$raw" ] || return 1
  raw=$(printf '%s' "$raw" | scrub)
  printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  printf '%s' "$raw"
}

LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"

# A live review bead already owed to <anchor> for gate <g>? Echoes its id.
# Routed or claimed counts (a claim consumes gc.routed_to); an open, unclaimed,
# unrouted one is stranded — echoed with a "stranded " tag for the route repair.
# Non-zero = the ledger could not answer; the caller holds the dispatch.
inflight_review() { # <anchor-id> <gate>
  local raw
  raw=$(bd_list --metadata-field anchor_bead="$1" --status="$LIVE_STATUSES") || return 1
  printf '%s' "$raw" | jq -r --arg g "$2" '
    [ .[]
      | select(((.metadata.task_kind // "") | tostring) == "review")
      | select(((.metadata.check_name // "") | tostring) == $g)
      | . + {reach: (((((.metadata["gc.routed_to"] // "") | tostring) != "")
                      or (((.assignee // "") | tostring) != "")))} ]
    | sort_by(if .reach then 0 else 1 end)
    | (.[0] // empty)
    | (if .reach then .id else ("stranded " + .id) end)' 2>/dev/null
}

read_route() { # <bead-id> -> "review_pool|gc.routed_to|assignee"
  gc bd show "$1" --json 2>/dev/null | scrub \
    | jq -r '.[0] | [(.metadata.review_pool // ""),
                     (.metadata["gc.routed_to"] // ""),
                     (.assignee // "")] | join("|")' 2>/dev/null
}

route_ok() { # <triple> <pool>
  local state="${1:-}" pool="${2:-}" p r a
  [ -n "$state" ] || return 1
  IFS='|' read -r p r a <<< "$state"
  [ "$p" = "$pool" ] || return 1
  [ -n "$a" ] || [ "$r" = "$pool" ] || return 1
  return 0
}

meta_of() { # <row-json> <key>
  printf '%s' "$1" | jq -r --arg k "$2" '(.metadata[$k] // "") | tostring' 2>/dev/null
}

# --- enumerate the gating set (both sub-states); unreadable = cannot vouch ------
ROWS=""
for MR in pre_open_gate pull_request; do
  if ! RAW=$(bd_list --status=open --metadata-field merge_result="$MR"); then
    echo "$PROG: the '$MR' gating enumeration is unreadable; cannot vouch that every visible anchor is gated — holding merge for the pass (rc=$UNSAFE_RC)" >&2
    exit "$UNSAFE_RC"
  fi
  [ "$RAW" = "[]" ] && continue
  PART=$(printf '%s' "$RAW" | jq -c '.[]' 2>/dev/null)
  [ -n "$PART" ] && ROWS="$ROWS$PART
"
done
[ -n "$ROWS" ] || { echo "$PROG: no gating anchors"; exit 0; }

stamped=0; dispatched=0; held=0; unsafe=0; skipped=0
while IFS= read -r row; do
  [ -n "${row:-}" ] || continue
  id=$(printf '%s' "$row" | jq -r '.id // empty')
  [ -n "$id" ] || continue
  branch=$(meta_of "$row" branch)
  target=$(meta_of "$row" merged_target)
  [ -n "$target" ] || target=$(meta_of "$row" target)
  [ -n "$target" ] || target="main"
  title=$(printf '%s' "$row" | jq -r '.title // ""')
  checkset=$(meta_of "$row" check_set)
  hold=$(meta_of "$row" merge_hold)
  canon=$(cs_canon "$checkset")

  # --- canonicalize: empty is "never normalized", stamp the default first ------
  if [ -z "$canon" ]; then
    gc bd update "$id" --set-metadata check_set="$DEFAULT_CHECK_SET" \
      --append-notes "gate-ensure: check_set was absent/empty; stamped the declared default '$DEFAULT_CHECK_SET' so the anchor cannot merge ungated." \
      >/dev/null 2>&1
    got=$(gc bd show "$id" --json 2>/dev/null | scrub \
      | jq -r '.[0].metadata.check_set // empty' 2>/dev/null)
    if [ "$got" != "$DEFAULT_CHECK_SET" ]; then
      # Visible to merge.sh and still ungated: the one condition that must hold
      # the merge for the whole pass.
      echo "$PROG: $id check_set stamp did NOT persist (have '${got:-<empty>}'); anchor is visible and UNGATED" >&2
      unsafe=$((unsafe + 1)); continue
    fi
    stamped=$((stamped + 1))
    checkset="$DEFAULT_CHECK_SET"
    canon=$(cs_canon "$checkset")
    echo "$PROG: $id had no normalized check_set; stamped '$DEFAULT_CHECK_SET'"
  fi
  case "$canon" in none|off) continue ;; esac

  head=""
  head_read=0
  gates=$(printf '%s' "$checkset" | tr ',' '\n' | tr -d '[:space:]' | sed '/^$/d')
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    case "$(printf '%s' "$g" | tr '[:upper:]' '[:lower:]')" in
      none|off|approval) continue ;;  # approval is evidenced by GitHub review state
    esac
    marker=$(meta_of "$row" "check.$g")
    if [ "$head_read" = 0 ]; then head=$(live_head_for "$branch"); head_read=1; fi
    # Classify: green at the live head (or green with no head to test) and
    # exception@ are settled; everything else needs something able to raise it.
    case "$marker" in
      green@*)
        oid="${marker#green@}"
        if [ -z "$head" ] || [ "$oid" = "$head" ]; then continue; fi
        why="check.$g is green@$oid but branch '$branch' has advanced to $head" ;;
      exception@*) continue ;;  # terminal until an operator acts
      "") why="check.$g is absent (never reviewed, or cleared by a REQUEST_CHANGES signoff)" ;;
      fixable@*) why="check.$g is '$marker' (remediation was in flight); re-dispatching unless one still is" ;;
      *) why="check.$g is '$marker', which names no verdict verb the contract knows; a fresh signoff rewrites it" ;;
    esac

    # Operator hold gates a re-dispatch (pipeline work toward landing); the
    # armed gate already holds the merge, so held-and-gated is safe.
    case "$hold" in
      ""|false|False|FALSE|0|null) : ;;
      *) echo "$PROG: $id gate '$g' needs raising ($why) but merge_hold is set (operator gate); no dispatch"
         held=$((held + 1)); continue ;;
    esac

    if ! FOUND=$(inflight_review "$id" "$g"); then
      echo "$PROG: $id in-flight review lookup unreadable; dispatching nothing (merge stays held, retry next pass)" >&2
      skipped=$((skipped + 1)); continue
    fi
    if [ -n "$FOUND" ]; then
      case "$FOUND" in
        "stranded "*)
          # A review that lost its route is inert, not in flight: re-offer it.
          rid="${FOUND#stranded }"
          [ -n "$REVIEW_POOL" ] || { skipped=$((skipped + 1)); continue; }
          gc bd update "$rid" --set-metadata gc.routed_to="$REVIEW_POOL" \
            --set-metadata review_pool="$REVIEW_POOL" >/dev/null 2>&1
          if route_ok "$(read_route "$rid")" "$REVIEW_POOL"; then
            gc session wake "$REVIEW_POOL" >/dev/null 2>&1 || true
            dispatched=$((dispatched + 1))
            echo "$PROG: $id gate '$g' had a STRANDED review $rid (open, unclaimed, unrouted); re-routed to $REVIEW_POOL"
          else
            echo "$PROG: $id stranded review $rid re-route to $REVIEW_POOL did not verify; merge stays held, retry next pass" >&2
            skipped=$((skipped + 1))
          fi ;;
        *) : ;;  # live review in flight — it will raise the gate
      esac
      continue
    fi

    if [ -z "$REVIEW_POOL" ]; then
      echo "$PROG: $id gate '$g' is armed but no --review-pool was given; no dispatch (merge is HELD until one is)" >&2
      skipped=$((skipped + 1)); continue
    fi
    # Convergence cap: dispatch_count on the anchor bounds review rounds; at the
    # cap the merge stays held and signoff.sh records the exception verdict.
    dcount=$(meta_of "$row" dispatch_count)
    case "$dcount" in ''|*[!0-9]*) dcount=0 ;; esac
    if [ "$dcount" -ge "${GC_MAX_REVIEW_ROUNDS:-3}" ]; then
      echo "$PROG: $id gate '$g' has spent $dcount dispatch round(s) against a cap of ${GC_MAX_REVIEW_ROUNDS:-3}; no further dispatch (merge stays held)"
      skipped=$((skipped + 1)); continue
    fi

    # Orphan adoption BEFORE create: a bead this arm created whose stamp then
    # failed carries the deterministic title but no anchor_bead — invisible to
    # inflight_review, so re-creating would mint a twin every pass. Adopt it
    # instead. An unreadable probe dispatches nothing (retry next pass).
    RID_TITLE="Review branch $branch -> $target:"
    if ! orphans=$(bd_list --status=open --title-contains "$RID_TITLE"); then
      echo "$PROG: $id orphan-review probe unreadable; dispatching nothing (merge stays held, retry next pass)" >&2
      skipped=$((skipped + 1)); continue
    fi
    RID=$(printf '%s' "$orphans" | jq -r '
      [ .[] | select(((.metadata.anchor_bead // "") | tostring) == "") | .id ] | .[0] // empty' 2>/dev/null)
    if [ -n "$RID" ]; then
      echo "$PROG: $id adopting unstamped review orphan $RID for gate '$g' (created by a prior pass whose stamp failed)"
    else
      body=""
      [ -x "$BODY_EMITTER" ] && body=$("$BODY_EMITTER" --note "$why" 2>/dev/null) || body=""
      if [ -n "$body" ]; then
        RID=$(printf '%s' "$body" \
          | gc bd create "$RID_TITLE $title" -t task --body-file - --json 2>/dev/null \
          | jq -r '.id // empty' 2>/dev/null)
      else
        echo "$PROG: WARN review method unavailable ($BODY_EMITTER); dispatching a title-only review" >&2
        RID=$(gc bd create "$RID_TITLE $title" -t task --json 2>/dev/null \
          | jq -r '.id // empty' 2>/dev/null)
      fi
    fi
    if [ -z "$RID" ]; then
      echo "$PROG: $id could not create the review bead for gate '$g'; merge stays held, retry next pass" >&2
      skipped=$((skipped + 1)); continue
    fi
    # reviewed_oid pins the dispatch head (signoff binds the verdict to it);
    # fix_target_pool routes a request-changes rework to the derived pool.
    gc bd update "$RID" \
      --set-metadata task_kind=review \
      --set-metadata check_name="$g" \
      --set-metadata anchor_bead="$id" \
      --set-metadata review_branch="$branch" \
      --set-metadata review_base="$target" \
      ${head:+--set-metadata reviewed_oid="$head"} \
      ${FIX_POOL:+--set-metadata fix_target_pool="$FIX_POOL"} >/dev/null 2>&1
    gc bd dep "$RID" --blocks "$id" >/dev/null 2>&1 \
      || echo "$PROG: WARN could not attach review $RID as a blocks-dep of $id (anchor_bead persists the link)" >&2
    # The anchor link is what lets the signoff find the gate to stamp; verify it
    # BEFORE routing, or a claimed half-stamped review can never discharge.
    got=$(gc bd show "$RID" --json 2>/dev/null | scrub | jq -r '.[0].metadata.anchor_bead // empty')
    if [ "$got" != "$id" ]; then
      echo "$PROG: WARN review $RID did not record anchor_bead=$id; not routed, merge stays held, retry next pass" >&2
      skipped=$((skipped + 1)); continue
    fi
    gc bd update "$RID" \
      --set-metadata gc.routed_to="$REVIEW_POOL" \
      --set-metadata review_pool="$REVIEW_POOL" >/dev/null 2>&1
    if ! route_ok "$(read_route "$RID")" "$REVIEW_POOL"; then
      gc bd update "$RID" \
        --set-metadata gc.routed_to="$REVIEW_POOL" \
        --set-metadata review_pool="$REVIEW_POOL" >/dev/null 2>&1
    fi
    if ! route_ok "$(read_route "$RID")" "$REVIEW_POOL"; then
      echo "$PROG: WARN review $RID route to $REVIEW_POOL did not verify; dispatch NOT counted, merge stays held, retry next pass" >&2
      skipped=$((skipped + 1)); continue
    fi
    gc bd update "$id" --set-metadata dispatch_count="$((dcount + 1))" >/dev/null 2>&1 || true
    gc session wake "$REVIEW_POOL" >/dev/null 2>&1 || true
    gc session nudge "$REVIEW_POOL" "Review bead $RID for anchor $id" >/dev/null 2>&1 || true
    dispatched=$((dispatched + 1))
    echo "$PROG: $id dispatched review $RID for gate '$g' to $REVIEW_POOL — $why"
  done <<GATES
$gates
GATES
done <<ROWS_EOF
$ROWS
ROWS_EOF

echo "$PROG: $stamped check_sets stamped, $dispatched reviews dispatched/re-routed, $held operator-held, $skipped held-for-retry, $unsafe UNSAFE"
if [ "$unsafe" -gt 0 ]; then
  echo "$PROG: UNSAFE — $unsafe anchor(s) visible to merge.sh and still ungated; exiting rc=$UNSAFE_RC so the driver holds merge.sh this pass" >&2
  exit "$UNSAFE_RC"
fi
exit 0
