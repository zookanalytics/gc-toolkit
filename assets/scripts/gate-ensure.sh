#!/usr/bin/env bash
# gate-ensure — arm 1 of the merge cadence; caller: refinery-reconcile.sh.
# For every open pre_open_gate/pull_request anchor: canonicalize check_set
# (empty -> stamp the declared default; a list or `none` is left alone), clear
# any check.<g> that both fails the marker grammar and names a gate check_set
# does not declare (nothing else reads it, so nothing else could ever rewrite
# it), then ensure every declared unsettled gate is RAISABLE — marker green@ or
# exception@ the live branch head, a live routed/claimed review in flight, or
# a fresh dispatch: metadata + blocks edge stamped first (fail-closed), body
# from review-dispatch-body.sh, then formula and route in one call (gc sling
# <review-pool> <bead> --on mol-review), counted only after the pour's
# gc.execution_routed_to read-back. The dispatch pins reviewed_oid=<live
# head> (signoff.sh binds the verdict) and fix_target_pool (rework route).
# An unstamped orphan is adopted by its title, never twinned; a failed
# sling is never retried in-pass (a re-pour mints a second workflow root).
# Reach carried by the pour ALONE is qualified before it counts: a review
# whose workflow is spent (every step closed but the finalizer) can never
# produce a verdict, so it is escalated through escalate.sh under one deduped
# situation key rather than holding the anchor in silence.
# A head move past a recorded exception@ buys ONE dispatch through the
# dispatch_count cap.
# Args: --default <check_set> --review-pool <pool> [--fix-pool <pool>].
# Exits: 0 (a dispatch failure leaves the gate armed, merge HELD); 3 = an
# anchor not made safe (unreadable enumeration/unpersisted stamp): merge held.
set -u

PROG="gate-ensure"
UNSAFE_RC=3
scrub() { tr -d '\000-\010\013\014\016-\037'; }

DEFAULT_CHECK_SET="codex"
REVIEW_FORMULA="mol-review"
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
ESCALATOR="$SCRIPTS_DIR/escalate.sh"
WEDGE_KEY="review-wedge"

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
# The step/root reads below must see closed rows too: a spent chain is
# recognised by its closures, and one repeated --status flag keeps only the
# last value, so both halves ride a single comma list.
ALL_STATUSES="$LIVE_STATUSES,closed"

# A live review bead already owed to <anchor> for gate <g>? Echoes its id.
# Poured (gc.execution_routed_to), routed, or claimed counts; an open,
# unclaimed, unrouted, unpoured one is stranded — echoed with a "stranded "
# tag for the repair arm. Reach that rests on the pour ALONE is echoed with a
# "poured " tag: nothing but that workflow can raise the gate, so the wedge
# arm has to ask whether it is still running. Non-zero = the ledger could not
# answer; the caller holds the dispatch.
inflight_review() { # <anchor-id> <gate>
  local raw
  raw=$(bd_list --metadata-field anchor_bead="$1" --status="$LIVE_STATUSES") || return 1
  printf '%s' "$raw" | jq -r --arg g "$2" '
    [ .[]
      | select(((.metadata.task_kind // "") | tostring) == "review")
      | select(((.metadata.check_name // "") | tostring) == $g)
      | . + {routed:  (((.metadata["gc.routed_to"] // "") | tostring) != ""),
             poured:  (((.metadata["gc.execution_routed_to"] // "") | tostring) != ""),
             claimed: (((.assignee // "") | tostring) != "")}
      | . + {reach: (.routed or .poured or .claimed)} ]
    | sort_by(if .reach then 0 else 1 end)
    | (.[0] // empty)
    | (if (.reach | not) then ("stranded " + .id)
       elif (.poured and (.routed | not) and (.claimed | not)) then ("poured " + .id)
       else .id end)' 2>/dev/null
}

# The roots of every workflow poured over <review-bead>, one per line, via the
# tracking convoy each pour mints. A re-pour mints a SECOND root, so all of
# them must be judged — one spent root proves nothing while a sibling runs.
# Non-zero = the linkage could not be read.
pour_roots() { # <review-bead-id>
  local raw ids rows out=""
  raw=$(gc bd dep list "$1" --direction=up -t tracks --json 2>/dev/null | scrub)
  [ -n "$raw" ] || return 1
  printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  ids=$(printf '%s' "$raw" | jq -r '
    .[] | select((.issue_type // .type // "") == "convoy") | .id' 2>/dev/null)
  [ -n "$ids" ] || return 1
  while IFS= read -r c; do
    [ -n "${c:-}" ] || continue
    rows=$(bd_list --metadata-field "gc.input_convoy_id=$c" --status="$ALL_STATUSES") || return 1
    out="$out$(printf '%s' "$rows" | jq -r '.[].id' 2>/dev/null)
"
  done <<CONVOYS
$ids
CONVOYS
  out=$(printf '%s' "$out" | sed '/^$/d')
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}

# Is every workflow poured over <review-bead> SPENT — each step closed but the
# finalizer, which is the control-dispatcher's? A spent chain is terminal:
# nothing re-offers a closed step, so no verdict can still be coming. An open
# step is the opposite reading — a live claim, or a husk the re-offer path
# will pick up — and either way not this arm's business.
# Echoes the spent root. rc: 0 spent · 2 still driven · 1 unanswerable.
pour_spent() { # <review-bead-id>
  local roots rows n live last=""
  roots=$(pour_roots "$1") || return 1
  while IFS= read -r r; do
    [ -n "${r:-}" ] || continue
    rows=$(bd_list --metadata-field "gc.root_bead_id=$r" --status="$ALL_STATUSES") || return 1
    n=$(printf '%s' "$rows" | jq -r 'length' 2>/dev/null)
    case "$n" in ''|*[!0-9]*) return 1 ;; esac
    # A root whose steps do not enumerate says nothing about the pour.
    [ "$n" -gt 0 ] || return 1
    live=$(printf '%s' "$rows" | jq -r '
      [ .[]
        | select(((((.metadata["gc.step_ref"] // "") | tostring)
                   | endswith(".workflow-finalize")) | not))
        | select(((.status // "open") | tostring) != "closed") ] | length' 2>/dev/null)
    case "$live" in ''|*[!0-9]*) return 1 ;; esac
    [ "$live" -gt 0 ] && return 2
    last="$r"
  done <<ROOTS
$roots
ROOTS
  [ -n "$last" ] || return 1
  printf '%s' "$last"
}

# The pour retires gc.routed_to and stamps gc.execution_routed_to in its
# place; that stamp is the dispatch read-back.
pour_ok() { # <bead-id> <pool>
  local got
  got=$(gc bd show "$1" --json 2>/dev/null | scrub \
    | jq -r '.[0].metadata["gc.execution_routed_to"] // empty' 2>/dev/null)
  [ "$got" = "${2:-}" ]
}

# Count the LIVE tracking convoys over a bead: >0 means a poured workflow
# still drives it and a second pour would mint a second root. A dep row with
# no status field counts (fail-closed toward no-re-pour when the shape is
# unknown); a closed/dead convoy does not — that pour is over and must not
# suppress the stranded re-sling. Non-zero rc = the probe could not answer.
tracking_convoys() { # <bead-id>
  local raw
  raw=$(gc bd dep list "$1" --direction=up -t tracks --json 2>/dev/null | scrub)
  [ -n "$raw" ] || return 1
  printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  printf '%s' "$raw" | jq -r '[ .[] | select((.issue_type // .type // "") == "convoy") | select(((.status // "open") | tostring) as $s | ($s == "open" or $s == "in_progress" or $s == "blocked" or $s == "deferred" or $s == "hooked" or $s == "pinned")) ] | length' 2>/dev/null
}

meta_of() { # <row-json> <key>
  printf '%s' "$1" | jq -r --arg k "$2" '(.metadata[$k] // "") | tostring' 2>/dev/null
}

# The oid half of the marker grammar <green|fixable|exception>@<40-hex>.
is_oid() { # <string>
  local v="${1:-}"
  case "$v" in *[!0-9a-f]*|"") return 1 ;; esac
  [ "${#v}" -eq 40 ]
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

stamped=0; dispatched=0; held=0; unsafe=0; skipped=0; wedged=0; cleared=0
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
  # --- retire markers no arm of the cadence can ever rewrite ------------------
  # merge.sh and the gates loop below both read only the gates named in
  # check_set, so a check.<g> outside it governs nothing and nothing rewrites
  # it. Clear it when it also fails the marker grammar: a verdict bound to no
  # valid oid is not evidence, and check-gate-integrity errors on it forever.
  # A well-formed marker survives (a narrowed check_set keeps its history), and
  # exception@ is the operator's to retire.
  declared=",$(printf '%s' "$checkset" | tr -d '[:space:]'),"
  stray=$(printf '%s' "$row" | jq -r --arg d "$declared" '
    (.metadata // {}) | to_entries[]
    | select(.key | test("^check\\.[^.]+$"))
    | select((.value | type) == "string")
    | select((.value | test("^exception@")) | not)
    | select((.value | test("^(green|fixable)@[0-9a-f]{40}$")) | not)
    | (.key | sub("^check\\."; "")) as $g
    | select(($d | contains("," + $g + ",")) | not)
    | .key' 2>/dev/null)
  while IFS= read -r k; do
    [ -n "${k:-}" ] || continue
    was=$(meta_of "$row" "$k")
    gc bd update "$id" --unset-metadata "$k" \
      --append-notes "gate-ensure: cleared $k=\"$was\" — check_set '$checkset' does not declare that gate and the marker is not a well-formed verdict, so no signoff or merge could ever act on it." \
      >/dev/null 2>&1 </dev/null
    still=$(gc bd show "$id" --json </dev/null 2>/dev/null | scrub \
      | jq -r --arg k "$k" '.[0].metadata[$k] // empty' 2>/dev/null)
    if [ -n "$still" ]; then
      echo "$PROG: WARN $id $k still reads '$still' after the clear; retry next pass" >&2
    else
      cleared=$((cleared + 1))
      echo "$PROG: $id cleared undeclared malformed gate marker $k=\"$was\" (check_set '$checkset')"
    fi
  done <<STRAY
$stray
STRAY

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
    # Classify: a verdict verb bound to the live head (or bound with no head to
    # test) is settled; everything else needs something able to raise it.
    stale_exception=0
    case "$marker" in
      green@*)
        oid="${marker#green@}"
        if [ -n "$head" ]; then
          [ "$oid" = "$head" ] && continue
          why="check.$g is green@$oid but branch '$branch' has advanced to $head"
        elif is_oid "$oid"; then
          continue  # head unreadable: a well-formed green stays satisfiable
        else
          # No head can ever equal a malformed oid, so the soft pass above would
          # settle this gate forever on a marker that is not evidence.
          why="check.$g is green@$oid, which is no 40-hex oid, and '$branch' has no readable head — nothing could ever satisfy it"
        fi ;;
      exception@*)
        oid="${marker#exception@}"
        if [ -z "$head" ] || [ "$oid" = "$head" ]; then continue; fi
        stale_exception=1  # the cap check below reads this
        why="check.$g is exception@$oid but branch '$branch' has advanced to $head" ;;
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
          # A review with no route, no pour and no claim is inert — unless a
          # tracking convoy shows a pour already drives it (exec stamp
          # dropped): then a re-pour would mint a second workflow root, so it
          # counts as in flight. Only a never-poured one is re-slung.
          rid="${FOUND#stranded }"
          [ -n "$REVIEW_POOL" ] || { skipped=$((skipped + 1)); continue; }
          if ! convoys=$(tracking_convoys "$rid"); then
            echo "$PROG: $id stranded review $rid convoy probe unreadable; no re-pour (merge stays held, retry next pass)" >&2
            skipped=$((skipped + 1)); continue
          fi
          if [ "${convoys:-0}" -gt 0 ] 2>/dev/null; then
            echo "$PROG: $id gate '$g' review $rid is convoy-tracked (a pour already drives it); counted in flight, no re-pour"
            continue
          fi
          gc sling ${GC_RIG:+--rig "$GC_RIG"} "$REVIEW_POOL" "$rid" --on "$REVIEW_FORMULA" >/dev/null 2>&1
          if pour_ok "$rid" "$REVIEW_POOL"; then
            gc session wake "$REVIEW_POOL" >/dev/null 2>&1 || true
            dispatched=$((dispatched + 1))
            echo "$PROG: $id gate '$g' had a STRANDED review $rid (open, unclaimed, unrouted, never poured); re-slung to $REVIEW_POOL with $REVIEW_FORMULA"
          else
            echo "$PROG: $id stranded review $rid re-sling to $REVIEW_POOL did not read back; merge stays held, retry next pass" >&2
            skipped=$((skipped + 1))
          fi ;;
        "poured "*)
          # Reach rests on the pour alone: no route left for the pool to
          # re-claim, no assignee still holding it. If that workflow is spent
          # the gate is wedged — the anchor holds for good with nothing open
          # to say why, which is the one failure this arm cannot leave silent.
          # The hold for a second sighting is not politeness: mol-review's
          # failure arm closes its chain BEFORE it restores the route, so a
          # single read can catch a recovery mid-write and escalate a review
          # that repairs itself moments later.
          rid="${FOUND#poured }"
          spent_root=""
          spent_rc=0
          spent_root=$(pour_spent "$rid") || spent_rc=$?
          case "$spent_rc" in
            2) : ;;
            0)
              row=$(gc bd show "$rid" --json 2>/dev/null | scrub)
              seen=$(printf '%s' "$row" | jq -r '.[0].metadata.wedge_seen_root // empty' 2>/dev/null)
              rpool=$(printf '%s' "$row" | jq -r '
                .[0].metadata.review_pool // .[0].metadata["gc.execution_routed_to"] // empty' 2>/dev/null)
              [ -n "$rpool" ] || rpool="$REVIEW_POOL"
              if [ "$seen" != "$spent_root" ]; then
                gc bd update "$rid" --set-metadata wedge_seen_root="$spent_root" >/dev/null 2>&1
                echo "$PROG: $id gate '$g' review $rid looks WEDGED (workflow $spent_root spent, no verdict, no route); holding one pass before escalating"
              elif [ ! -x "$ESCALATOR" ]; then
                echo "$PROG: $id gate '$g' review $rid is WEDGED (workflow $spent_root spent) but $ESCALATOR is missing; repair by hand: gc bd update $rid --set-metadata gc.routed_to=$rpool" >&2
              else
                "$ESCALATOR" --subject "$rid" --key "$WEDGE_KEY" --message \
"Review $rid is wedged: its poured workflow finished without a verdict, so gate '$g' on $id is held with nothing driving it.

Anchor:   $id — $title
Gate:     check.$g is ${marker:-absent}
Branch:   $branch -> $target
Review:   $rid (open, poured to $rpool; no route, no assignee)
Workflow: $spent_root — every step closed but the finalizer

The reviewing agent closed its step chain without calling signoff.sh and
without restoring the review bead's route, so no verdict can still be coming
and the merge is held indefinitely.

Two repairs, either of which clears the hold:
  return it to the pool as a formula-less review, the shape mol-review
  documents for exactly this recovery —
    gc bd update $rid --set-metadata gc.routed_to=$rpool
  or drop the abandoned round and let the next pass dispatch a fresh review —
    gc bd close $rid" >/dev/null \
                  && { wedged=$((wedged + 1)); echo "$PROG: $id gate '$g' review $rid is WEDGED (workflow $spent_root spent); escalated [$WEDGE_KEY]"; } \
                  || echo "$PROG: $id gate '$g' review $rid is WEDGED (workflow $spent_root spent) but the escalation did not file; retry next pass" >&2
              fi ;;
            *) echo "$PROG: $id gate '$g' review $rid pour-liveness probe unreadable; no escalation this pass (merge stays held)" >&2 ;;
          esac ;;
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
    # That exception IS the record of the spend, so the rounds behind it cannot
    # also refuse a dispatch the head move has since earned. Nothing self-feeds:
    # signoff's cap arm files no rework child, so only an actor outside the
    # cadence can move that head again.
    dcount=$(meta_of "$row" dispatch_count)
    case "$dcount" in ''|*[!0-9]*) dcount=0 ;; esac
    if [ "$dcount" -ge "${GC_MAX_REVIEW_ROUNDS:-3}" ]; then
      if [ "$stale_exception" = 0 ]; then
        echo "$PROG: $id gate '$g' has spent $dcount dispatch round(s) against a cap of ${GC_MAX_REVIEW_ROUNDS:-3}; no further dispatch (merge stays held)"
        skipped=$((skipped + 1)); continue
      fi
      echo "$PROG: $id gate '$g' is past the cap ($dcount/${GC_MAX_REVIEW_ROUNDS:-3}) but the branch advanced past exception@$oid; dispatching one re-gate at $head"
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
        echo "$PROG: WARN dispatch note unavailable ($BODY_EMITTER); dispatching a title-only review" >&2
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
      --set-metadata review_pool="$REVIEW_POOL" \
      ${head:+--set-metadata reviewed_oid="$head"} \
      ${FIX_POOL:+--set-metadata fix_target_pool="$FIX_POOL"} >/dev/null 2>&1
    gc bd dep "$RID" --blocks "$id" >/dev/null 2>&1 \
      || echo "$PROG: WARN could not attach review $RID as a blocks-dep of $id (anchor_bead persists the link)" >&2
    # The anchor link is what lets the signoff find the gate to stamp; verify it
    # BEFORE the pour, or a claimed half-stamped review can never discharge.
    got=$(gc bd show "$RID" --json 2>/dev/null | scrub | jq -r '.[0].metadata.anchor_bead // empty')
    if [ "$got" != "$id" ]; then
      echo "$PROG: WARN review $RID did not record anchor_bead=$id; not slung, merge stays held, retry next pass" >&2
      skipped=$((skipped + 1)); continue
    fi
    # One sling, no retry: a re-pour mints a second workflow root. A pour that
    # does not read back is held; the next pass's stranded arm probes for its
    # tracking convoy before deciding to re-sling.
    gc sling ${GC_RIG:+--rig "$GC_RIG"} "$REVIEW_POOL" "$RID" --on "$REVIEW_FORMULA" >/dev/null 2>&1
    if ! pour_ok "$RID" "$REVIEW_POOL"; then
      echo "$PROG: WARN review $RID pour did not read back; dispatch NOT counted, merge stays held, retry next pass" >&2
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

echo "$PROG: $stamped check_sets stamped, $cleared stray markers cleared, $dispatched reviews dispatched/re-routed, $held operator-held, $skipped held-for-retry, $wedged wedged/escalated, $unsafe UNSAFE"
if [ "$unsafe" -gt 0 ]; then
  echo "$PROG: UNSAFE — $unsafe anchor(s) visible to merge.sh and still ungated; exiting rc=$UNSAFE_RC so the driver holds merge.sh this pass" >&2
  exit "$UNSAFE_RC"
fi
exit 0
