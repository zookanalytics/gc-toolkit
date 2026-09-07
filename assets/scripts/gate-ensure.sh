#!/usr/bin/env bash
# gate-ensure — arm 1 of the merge cadence; caller: refinery-reconcile.sh.
# For every open pre_open_gate/pull_request anchor: canonicalize check_set
# (empty -> stamp the declared default; a list or `none` is left alone), clear
# any check.<g> that both fails the marker grammar and names a gate check_set
# does not declare (nothing else reads it, so nothing else could ever rewrite
# it), then ensure every declared unsettled gate is RAISABLE. A lane's state is
# DERIVED from the finding and review-outcome graph through lane-state.sh, the
# one helper merge.sh and pr-open.sh derive green through — never a stored
# check.<g> marker. A lane that derives green is settled; otherwise the lane
# owes a review, has one in flight, or the anchor is mid-change, and a fresh
# dispatch goes out only when QUIESCENCE holds: no review is dispatched while
# anything is acting on the anchor — an open must-fix finding on any lane, a
# fix unit in flight, a validation pass in flight, or a full review already in
# flight on the lane. That predicate is what forbids the same head being read
# twice. A dispatch stamps metadata + a blocks edge first (fail-closed), takes
# its body from review-dispatch-body.sh, then pours formula and route in one
# call (gc sling <review-pool> <bead> --on mol-review), pinned to the live head
# (signoff.sh binds the verdict) with fix_target_pool for the rework route.
# An unstamped orphan is adopted by its title, never twinned; a failed sling is
# never retried in-pass (a re-pour mints a second workflow root). Reach carried
# by the pour ALONE is qualified before it counts: a review whose workflow is
# spent (every step closed but the finalizer) can never produce a verdict, so
# it is escalated through escalate.sh under one deduped situation key rather
# than holding the anchor in silence. There is no dispatch ceiling: quiescence
# forbids the redundant round the ceiling used to bound, and the runaway shapes
# left — a reviewer that dies after claim, a fix unit filed with its edge
# reversed — stop the PR moving and are caught by liveness-sweep.sh's stale-gate
# pass, not by a count on the gate.
# Args: --default <check_set> --review-pool <pool> [--fix-pool <pool>].
# Exits: 0 (a dispatch failure leaves the gate armed, merge HELD); 3 = an
# anchor not made safe (unreadable enumeration/unpersisted stamp): merge held.
set -u

PROG="gate-ensure"
UNSAFE_RC=3
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

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
LIFECYCLE="$SCRIPTS_DIR/lifecycle.sh"
# The shared graph-derivation helpers: lane green (the settled state) and the
# anchor's open must-fix findings (quiescence clause a). Invoked as subprocesses
# so every reader derives the same way; a missing or unreadable one fails closed
# (holds the dispatch), never dispatches blind.
LANE_STATE="$SCRIPTS_DIR/lane-state.sh"
FINDING="$SCRIPTS_DIR/finding.sh"
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
  # gh writes its error body to STDOUT, and --jq on a body without .sha prints
  # "null" at rc=0, so neither the exit code nor the output alone separates a
  # head from a failure. Empty routes the callers to their "no head to test"
  # arms, which is the safe direction: an unread head cannot prove a branch
  # moved, and the next pass sees a merged anchor closed and out of scope.
  # The head is only ever compared against a marker oid, so it is held to that
  # same grammar.
  [ "$HAVE_GH" = 1 ] && [ -n "$ORIGIN_REPO" ] && [ -n "${1:-}" ] || return 0
  local out
  out=$(gh api --hostname "$ORIGIN_HOST" \
    "repos/$ORIGIN_REPO/commits/$1" --jq '.sha' 2>/dev/null) || return 0
  is_oid "$out" || return 0
  printf '%s\n' "$out"
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

# An open rework child already filed under <anchor>? Echoes its id. A rework
# child is a blocks-dep bead whose metadata carries a non-empty
# source_review_bead — exactly what signoff.sh's count_rework_children walks —
# and request-changes clears check.<g> and files exactly one such child, so a
# lane back to unreviewed with one of these still open is owed the rework
# landing, not a fresh review. Non-zero rc = the ledger could not answer; the
# caller holds the dispatch, the same as an unreadable in-flight-review lookup.
open_rework_child() { # <anchor-id>
  local raw
  raw=$(gc bd dep list "$1" --direction=down -t blocks --json 2>/dev/null | scrub)
  [ -n "$raw" ] || return 1
  printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  printf '%s' "$raw" | jq -r --arg ls "$LIVE_STATUSES" '
    ($ls | split(",")) as $live
    | [ .[]
        | select(((.status // "open") | ascii_downcase) as $st | ($live | index($st)) != null)
        | select(((.metadata.source_review_bead // "") | tostring) != "")
        | .id ] | (.[0] // empty)' 2>/dev/null
}

# An open validation pass on <anchor>? Echoes its id, else empty. A validation
# pass is a task_kind=validation bead (a mol-validate pour) whose anchor_bead is
# this anchor; while one is open every lane derives validating and no review may
# be dispatched — the validator rules the whole diff, so a review that read it
# now would read a state no one intends to ship. Non-zero rc = the ledger could
# not answer; the caller holds the dispatch, the same as an unreadable in-flight
# lookup.
open_validation_pass() { # <anchor-id>
  local raw
  raw=$(bd_list --metadata-field anchor_bead="$1" --status="$LIVE_STATUSES") || return 1
  printf '%s' "$raw" | jq -r '
    [ .[] | select(((.metadata.task_kind // "") | tostring) == "validation") ]
    | (.[0].id // empty)' 2>/dev/null
}

# Quiescence — the anchor-wide half of "no review while anything acts on the
# anchor", computed once per anchor and consulted before every dispatch (a fresh
# pour and a stranded re-sling alike). Sets three globals: quiesce_hold (non-empty
# = an actor is on the anchor, hold the dispatch), quiesce_reason (why, for the
# log), and quiesce_unreadable (a probe could not answer — fail closed, hold and
# retry next pass). The clauses, in order, first hold wins:
#   (a) an open must-fix finding on the anchor, on ANY lane    [finding.sh]
#   (b) a fix unit in flight resolving a finding on the anchor [open_rework_child]
#   (c) a validation pass in flight on the anchor              [open_validation_pass]
# Clause (d), a full review already in flight on THIS lane, is per-lane and stays
# with inflight_review at the dispatch site. Each clause is an open-bead query;
# none reads a check.<g> marker.
compute_quiescence() { # <anchor-id>
  quiesce_hold=""; quiesce_reason=""; quiesce_unreadable=0
  local mf rc fu vp
  # (a) open must-fix finding, any lane. A missing tool reads as unreadable, not
  # as an all-clear: dispatching against a diff whose findings cannot be read is
  # exactly the mid-change read quiescence exists to forbid.
  mf=$("$FINDING" open-must-fix --anchor "$1" 2>/dev/null); rc=$?
  case "$rc" in
    0) quiesce_hold=1; quiesce_reason="open must-fix finding $(printf '%s' "$mf" | head -1)"; return 0 ;;
    1) : ;;                              # readable, none open
    *) quiesce_unreadable=1; return 0 ;; # 2 unreadable, or the tool is missing
  esac
  # (b) fix unit in flight (a live blocks-dep child carrying source_review_bead).
  if ! fu=$(open_rework_child "$1"); then quiesce_unreadable=1; return 0; fi
  if [ -n "$fu" ]; then quiesce_hold=1; quiesce_reason="fix unit $fu in flight"; return 0; fi
  # (c) validation pass in flight.
  if ! vp=$(open_validation_pass "$1"); then quiesce_unreadable=1; return 0; fi
  if [ -n "$vp" ]; then quiesce_hold=1; quiesce_reason="validation pass $vp in flight"; return 0; fi
  return 0
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

# Count the workflow ROOTS a LIVE tracking convoy carries over a bead: >0 means
# a poured workflow still drives it and a second pour would mint a second root.
# The convoy alone is NOT that reach — a pour can mint the convoy and the tracks
# edge and then die before pouring the root, leaving a LIVE but EMPTY convoy that
# drives nothing; counting that as in flight holds the anchor forever. So the
# reach is the root, read the way pour_roots reads it (members via
# gc.input_convoy_id). Only a live convoy is consulted (a closed/dead pour is
# over and must not suppress the stranded re-sling); a dep row with no status
# field counts as live (fail-closed toward no-re-pour when the shape is unknown).
# A convoy's members are read across all statuses — a root the pour created is
# reach whether or not its chain has begun to close. Non-zero rc = a read failed
# and the count is unknown; the caller holds rather than re-sling blind.
tracked_roots() { # <bead-id>
  local raw ids rows n total=0
  raw=$(gc bd dep list "$1" --direction=up -t tracks --json 2>/dev/null | scrub)
  [ -n "$raw" ] || return 1
  printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  ids=$(printf '%s' "$raw" | jq -r '
    .[]
    | select((.issue_type // .type // "") == "convoy")
    | select(((.status // "open") | tostring) as $s
             | ($s == "open" or $s == "in_progress" or $s == "blocked"
                or $s == "deferred" or $s == "hooked" or $s == "pinned"))
    | .id' 2>/dev/null)
  # No LIVE tracking convoy at all is a readable zero, not a failed read:
  # nothing drives the review, so the caller re-slings it.
  [ -n "$ids" ] || { printf '0\n'; return 0; }
  while IFS= read -r c; do
    [ -n "${c:-}" ] || continue
    rows=$(bd_list --metadata-field "gc.input_convoy_id=$c" --status="$ALL_STATUSES") || return 1
    n=$(printf '%s' "$rows" | jq -r 'length' 2>/dev/null)
    case "$n" in ''|*[!0-9]*) return 1 ;; esac
    total=$((total + n))
  done <<CONVOYS
$ids
CONVOYS
  printf '%s\n' "$total"
}

# Judge a review whose only reach to the gate is a poured WORKFLOW: is that
# workflow live, spent, or unreadable? Two shapes arrive here for one question,
# so both take one answer — the poured arm's pour_spent probe:
#   - the exec-stamped "poured" review (reach == gc.execution_routed_to), and
#   - a stranded review (no exec stamp) that a LIVE tracking convoy's root shows
#     was poured with the stamp dropped.
# A live step chain is in flight (say so, do nothing else). A spent chain (every
# step closed but the finalizer) is wedged — the anchor holds for good with
# nothing open to say why, the one failure this arm cannot leave silent — so it
# is escalated once, after a one-pass hold. That hold is not politeness:
# mol-review's failure arm closes its chain BEFORE it restores the route, so a
# single read can catch a recovery mid-write and escalate a review that repairs
# itself moments later. An unreadable root or step enumeration is HELD without
# claiming a live pour — the merge stays held and the next pass re-probes.
# Reads the current anchor's loop context ($id $g $title $marker $branch $target
# $REVIEW_POOL $ESCALATOR $WEDGE_KEY $PROG) and bumps $wedged on a filed visit.
judge_pour_liveness() { # <review-bead-id>
  local rid="$1" spent_root="" spent_rc=0 rev_row seen rpool
  spent_root=$(pour_spent "$rid") || spent_rc=$?
  case "$spent_rc" in
    2) echo "$PROG: $id gate '$g' review $rid is driven by a live poured workflow; counted in flight, no re-pour" ;;
    0)
      rev_row=$(gc bd show "$rid" --json 2>/dev/null | scrub)
      seen=$(printf '%s' "$rev_row" | jq -r '.[0].metadata.wedge_seen_root // empty' 2>/dev/null)
      rpool=$(printf '%s' "$rev_row" | jq -r '
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
Review:   $rid (open; no route, no assignee)
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
  esac
}

meta_of() { # <row-json> <key>
  printf '%s' "$1" | jq -r --arg k "$2" '(.metadata[$k] // "") | tostring' 2>/dev/null
}

# Does <have> already record <want> in the dated shape <value>@<oid>@<instant>?
# The instant is lifecycle.sh's to keep or restamp, so any well-formed one
# answers yes; a value that is not yet dated does not.
recorded_verdict() { # <have> <want "value@oid">
  local rest="${1#"$2"@}"
  [ "$rest" != "${1:-}" ] || return 1
  case "$rest" in ''|*@*) return 1 ;; *) return 0 ;; esac
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
  # it. Clear it when it also fails the marker grammar: a word no lane state
  # names is not a state, and check-gate-integrity errors on it forever.
  # A well-formed marker survives — a narrowed check_set keeps its history.
  # A legacy exception@<oid> park is exempt from the sweep: until
  # migrate-lane-states.sh runs it is still an operator's park to retire, not
  # damage to clear, and clearing it silently would leave the migration
  # nothing to find.
  declared=",$(printf '%s' "$checkset" | tr -d '[:space:]'),"
  stray=$(printf '%s' "$row" | jq -r --arg d "$declared" '
    (.metadata // {}) | to_entries[]
    | select(.key | test("^check\\.[^.]+$"))
    | select((.value | type) == "string")
    | select((.value | test("^(unreviewed|reviewing|validating|fixing|green)$")) | not)
    | select((.value | test("^exception@")) | not)
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

  # The live head is no longer part of the classification — a lane state is a
  # state of the lane, and a commit landing on the branch does not change it.
  # It is still read once per anchor, for the dispatch pin the reviewer reads
  # and for the head the machine axis is dated at.
  # merge_result splits the two gating sub-states: a pre_open_gate anchor has no
  # PR yet, so no GitHub approval can back a lane there — the lane-state read
  # below passes --no-remote for it; a pull_request anchor may be human-approved.
  mr=$(meta_of "$row" merge_result)
  head=$(live_head_for "$branch")
  # The machine axis this pass reaches for the anchor as a whole. The gate loop
  # already derives each lane as green (settled) or short of green; these two
  # flags keep that answer instead of discarding it at the end of the iteration.
  #
  # The cap's wedge — shared with merge.sh's is_held arm — is evaluated once
  # HERE, per anchor, not inside the per-gate loop: the park sits on the
  # anchor's own merge_hold, not on any one lane, so a fully green capped
  # anchor (one gate hand-greened, or all of them) must still record the
  # wedge even though the loop below never reaches a hold check for it.
  # merge_hold's value must be the literal string "signoff_cap" — an
  # operator's own hold (merge_hold=true) beside a stale orphan signoff_cap
  # is not the cap's park.
  mach_wedge=0
  mach_progress=0
  if [ "$hold" = "signoff_cap" ] && [ -n "$(meta_of "$row" signoff_cap)" ]; then
    mach_wedge=1
  fi
  # Quiescence is anchor-wide and read at most once per anchor, lazily: the first
  # non-green lane to reach the dispatch decision computes it, and a fully green
  # anchor computes it once at the settle decision below (settling asserts nothing
  # is owed, which an open must-fix finding, fix unit, or validation pass
  # contradicts). compute_quiescence sets the three quiesce_* globals below.
  quiesce_computed=0
  quiesce_hold=""
  quiesce_reason=""
  quiesce_unreadable=0
  gates=$(printf '%s' "$checkset" | tr ',' '\n' | sed 's/[[:space:]]//g; /^$/d')
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    case "$(printf '%s' "$g" | tr '[:upper:]' '[:lower:]')" in
      none|off|approval) continue ;;  # approval is evidenced by GitHub review state
    esac
    # The marker is read for two legacy purposes only — never to classify the
    # lane. First, a legacy exception@ park: signoff.sh on main still refuses to
    # stamp over it and migrate-lane-states.sh has not yet rewritten it to
    # merge_hold=signoff_cap, so a review poured against the parked anchor would
    # be wasted reach — it reads as wedged and held. Second, the wedge
    # escalation's diagnostic line (judge_pour_liveness reads $marker). Both
    # retire with the round cap; the lane STATE is DERIVED below.
    marker=$(meta_of "$row" "check.$g")
    case "$marker" in
      exception@*)
        mach_progress=1
        mach_wedge=1
        echo "$PROG: $id gate '$g' carries a legacy park (check.$g=$marker); awaits migrate-lane-states.sh — no dispatch"
        held=$((held + 1)); continue ;;
    esac

    # Derive the lane's state from the finding and review-outcome graph, never a
    # marker: lane-state.sh is the one helper merge.sh and pr-open.sh derive green
    # through, so the readers agree. Green is settled — a non-superseded approve
    # review backs the lane — and a push moves no bead it reads, so green survives
    # new commits. A pre_open_gate anchor carries no PR, so no GitHub approval can
    # back a lane there. An unreadable derivation holds the dispatch (fail closed),
    # exactly as an unreadable in-flight lookup does; a missing helper reads the
    # same way rather than dispatching blind.
    if [ "$mr" = pull_request ]; then
      "$LANE_STATE" green --anchor "$id" --lane "$g"; lrc=$?
    else
      "$LANE_STATE" green --anchor "$id" --lane "$g" --no-remote; lrc=$?
    fi
    case "$lrc" in
      0) continue ;;  # green — settled, nothing owed
      1) : ;;         # not green — the lane owes a review, has one running, or the anchor is mid-change
      *) echo "$PROG: $id gate '$g' lane-state derivation unreadable (rc=$lrc); dispatching nothing (merge stays held, retry next pass)" >&2
         skipped=$((skipped + 1)); continue ;;
    esac
    why="lane '$g' does not derive green (no non-superseded approve review backs it)"

    # A lane short of green is what machine `progressing` names — not the outcome
    # of this particular attempt. A dispatch the operator hold defers, one held
    # for a retry, or one quiescence stays is still an anchor an automated actor
    # is due to act on, and the axis says so.
    mach_progress=1

    # Operator hold gates a re-dispatch (pipeline work toward landing); the armed
    # gate already holds the merge, so held-and-gated is safe. Whether this hold
    # IS the cap's park (wedged, not merely progressing) was already decided once
    # for the whole anchor, above.
    case "$hold" in
      ""|false|False|FALSE|0|null) : ;;
      *) echo "$PROG: $id gate '$g' needs raising ($why) but merge_hold is set (operator gate); no dispatch"
         held=$((held + 1)); continue ;;
    esac

    # Quiescence, anchor-wide, computed once (lazily) and consulted at both
    # dispatch sites below — the stranded re-sling and the fresh pour — so a
    # review never reads a diff mid-change. An unreadable probe holds every
    # dispatch for the anchor this pass. Clause (d), a review already in flight
    # on THIS lane, is inflight_review just below.
    if [ "$quiesce_computed" = 0 ]; then
      quiesce_computed=1
      compute_quiescence "$id"
    fi
    if [ "$quiesce_unreadable" = 1 ]; then
      echo "$PROG: $id quiescence probe unreadable; dispatching nothing for gate '$g' (merge stays held, retry next pass)" >&2
      skipped=$((skipped + 1)); continue
    fi

    if ! FOUND=$(inflight_review "$id" "$g"); then
      echo "$PROG: $id in-flight review lookup unreadable; dispatching nothing (merge stays held, retry next pass)" >&2
      skipped=$((skipped + 1)); continue
    fi
    if [ -n "$FOUND" ]; then
      case "$FOUND" in
        "stranded "*)
          # A review with no route, no pour and no claim is inert — unless a
          # live tracking convoy CARRIES A WORKFLOW ROOT. That root is a pour
          # whose exec stamp dropped, but the root ALONE is not proof the pour
          # still runs: its step chain may be live, spent (closed without a
          # verdict), or unreadable. So a tracked root is judged by the same
          # liveness check the poured arm uses — live counts in flight, spent
          # escalates, unreadable holds — not counted in flight on sight. A live
          # convoy with NO root drives nothing (a pour minted the convoy and the
          # tracks edge but died before the root), so that case, like a
          # never-poured one, is re-slung rather than held in flight forever.
          rid="${FOUND#stranded }"
          [ -n "$REVIEW_POOL" ] || { skipped=$((skipped + 1)); continue; }
          # Quiescence gates the re-sling too: re-routing an inert review pours a
          # read against the same mid-change diff a fresh dispatch would. Hold it
          # until the fix, validation pass, or must-fix finding clears.
          if [ -n "$quiesce_hold" ]; then
            mach_progress=1
            echo "$PROG: $id gate '$g' has a stranded review $rid but the anchor is quiesced ($quiesce_reason); no re-sling"
            held=$((held + 1)); continue
          fi
          if ! roots=$(tracked_roots "$rid"); then
            echo "$PROG: $id stranded review $rid pour probe unreadable; no re-pour (merge stays held, retry next pass)" >&2
            skipped=$((skipped + 1)); continue
          fi
          if [ "${roots:-0}" -gt 0 ] 2>/dev/null; then
            judge_pour_liveness "$rid"
            continue
          fi
          # Zero roots: a tracking convoy exists but carries no workflow root, so
          # nothing drives the review. Re-sling — this mints the FIRST root; the
          # empty convoy is left in place, contributing none to a later pass's
          # union.
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
          # re-claim, no assignee still holding it. Judge that workflow's
          # liveness the one way both arms do.
          judge_pour_liveness "${FOUND#poured }" ;;
        *) : ;;  # live review in flight — it will raise the gate
      esac
      continue
    fi

    # No in-flight review to raise the gate. Quiescence forbids a fresh dispatch
    # while a fix unit, a validation pass, or a must-fix finding is out — clause
    # (b) is exactly the rework child a request-changes filed, so the lane being
    # fixed reads as owed the fix, not a new review, and inflight_review never
    # sees that child (it is not a review bead). The predicate was computed
    # above; consult it here.
    if [ -n "$quiesce_hold" ]; then
      echo "$PROG: $id gate '$g' is quiesced ($quiesce_reason); the anchor is being acted on, so no review is dispatched"
      held=$((held + 1)); continue
    fi

    if [ -z "$REVIEW_POOL" ]; then
      echo "$PROG: $id gate '$g' is armed but no --review-pool was given; no dispatch (merge is HELD until one is)" >&2
      skipped=$((skipped + 1)); continue
    fi
    # No dispatch ceiling. GC_MAX_REVIEW_DISPATCHES and its dispatch_backstop
    # stamp were a convergence proxy — a converging PR could spend its budget on
    # redundant rounds and park on the board as a failure that never happened.
    # Quiescence above forbids the redundant round, so there is no budget left to
    # bound and no anchor carries a dispatch tally. The runaway shapes that remain
    # — a reviewer that dies after claim, a fix unit filed with its edge reversed
    # — stop the PR moving rather than spin the dispatcher, and a PR that stops
    # moving is caught by liveness-sweep.sh's stale-gate escalation, not a count
    # on the gate.

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
      echo "$PROG: WARN review $RID pour did not read back; merge stays held, retry next pass" >&2
      skipped=$((skipped + 1)); continue
    fi
    gc session wake "$REVIEW_POOL" >/dev/null 2>&1 || true
    gc session nudge "$REVIEW_POOL" "Review bead $RID for anchor $id" >/dev/null 2>&1 || true
    dispatched=$((dispatched + 1))
    echo "$PROG: $id dispatched review $RID for gate '$g' to $REVIEW_POOL — $why"
  done <<GATES
$gates
GATES

  # --- record the pass's own verdict on the anchor ------------------------------
  # The derivation above is reached once per pass. Recording it is what lets
  # a reader — the helm board — say whether an anchor is moving without
  # re-implementing this loop, and it costs no extra read: lifecycle.sh compares
  # against the bead it must fetch anyway.
  #
  # Only with a readable head. The value is head-pinned so a stale verdict can
  # never read as current, and a verdict pinned to nothing is not evidence.
  #
  # A wedged gate outranks a progressing one. The two can co-occur only on a
  # multi-gate check_set, and there the anchor still cannot land: the cap's park
  # holds every gate at once, so no amount of progress on the others moves it,
  # and the operator's move is the same one either way.
  if [ -n "$head" ]; then
    # Settling asserts nothing is owed, which is more than every lane deriving
    # green: an open must-fix finding, an in-flight fix unit, or a validation
    # pass acts on the anchor as a whole, not on a lane this loop visited. That
    # is quiescence, the predicate the dispatch decision already consults. A
    # fully green anchor lets the loop skip the lazy compute, so run it here
    # before settling and fail closed — a hold, or a probe that cannot answer,
    # is progressing, not settled.
    if [ "$mach_wedge" = 0 ] && [ "$mach_progress" = 0 ]; then
      if [ "$quiesce_computed" = 0 ]; then
        quiesce_computed=1
        compute_quiescence "$id"
      fi
      if [ -n "$quiesce_hold" ] || [ "$quiesce_unreadable" = 1 ]; then
        mach_progress=1
      fi
    fi
    if [ "$mach_wedge" = 1 ]; then mach="wedged-exception"
    elif [ "$mach_progress" = 1 ]; then mach="progressing"
    else mach="settled"
    fi
    #
    # --route carries the anchor's OWN route back. Recording a verdict is an
    # observation, not a routing decision, and an omitted --route would let a
    # detached state's default clear a route this pass never looked at.
    state=$(meta_of "$row" merge_result)
    # lifecycle.sh declines to write a transition that changes nothing, but it
    # has to re-read the anchor to find that out, and a per-anchor `gc bd show`
    # is the most expensive call this arm makes. The enumerated row already
    # carries the verdict, so the common pass — the same verdict at the same
    # head — is recognisable here for free. Only the full dated shape counts: a
    # bare <value>@<oid> still owes its instant, and that is a real write.
    if [ -n "$state" ] && ! recorded_verdict "$(meta_of "$row" "pr.machine")" "$mach@$head" \
       && ! "$LIFECYCLE" transition "$id" --to "$state" --expect "$state" \
         --route "$(meta_of "$row" "gc.routed_to")" \
         --set-dated "pr.machine=$mach@$head" >/dev/null; then
      echo "$PROG: WARN $id machine axis '$mach@$head' did not record; the board reads it as unknown until the next pass" >&2
    fi
  fi
done <<ROWS_EOF
$ROWS
ROWS_EOF

echo "$PROG: $stamped check_sets stamped, $cleared stray markers cleared, $dispatched reviews dispatched/re-routed, $held operator-held, $skipped held-for-retry, $wedged wedged/escalated, $unsafe UNSAFE"
if [ "$unsafe" -gt 0 ]; then
  echo "$PROG: UNSAFE — $unsafe anchor(s) visible to merge.sh and still ungated; exiting rc=$UNSAFE_RC so the driver holds merge.sh this pass" >&2
  exit "$UNSAFE_RC"
fi
exit 0
