#!/usr/bin/env bash
# finding.sh — the finding-bead primitive for the review cycle.
#
# A finding is a review objection with an identity of its own: a bead, not a
# line in a review body. It survives the rebase that destroys a commit oid, and
# one objection cannot be filed twice, because the cardinality is many findings
# to one fix unit — one work bead may answer three related findings and close
# them together. The bead's shape (docs/component-model.md, lifecycle.toml
# [metadata.review_findings]):
#
#   task_kind            finding
#   anchor_bead          the gating anchor
#   finding.lane         the lane whose review raised it, or `human`
#   finding.key          lane name + normalized locus + message; the dedup handle
#   finding.disposition  unvalidated | must-fix | deferred | declined
#   finding.source       machine:<lane> | human:<login>
#   finding.comment_id   the GitHub comment databaseId that raised it (stamped by
#                        pr-facts.sh for a human finding); the thread the write-back
#                        posts an owed decline reply into
#   finding.reply        the answer a declined HUMAN objection owes its raiser,
#                        set on `set-disposition declined --reply`; pr-facts.sh's
#                        write-back posts it to finding.comment_id's thread. A
#                        machine or no-objection decline owes none and sets it not.
#
# The interlock a finding places on its anchor is a graph edge, and the
# disposition picks the type (component-model I1: no wait lives only in a
# metadata string):
#
#   must-fix   finding --blocks anchor            holds the merge and the close
#   deferred   finding --discovered-from anchor   records provenance + the
#                                                 deferral reason, holds nothing
#   declined   no edge                            closed with the reason
#
# `blocks` is the type must-fix uses, and not because it is the only edge that
# blocks a close: merge.sh reads exactly `blocks` downward, so a finding held by
# any other type would leave the PR free to land with the objection still open.
# `discovered-from` is neither ready-blocking nor read by merge.sh's probes, so
# a deferred finding stays open across the merge holding nothing.
#
# The route never lives on a finding. A finding states an objection; the bead
# that is dispatched is the fix unit, which carries two `blocks` edges — one
# onto every finding it answers (the many-to-one relation and the close
# ordering), one onto the anchor (the routed live blocker merge.sh already
# reads). The finding edge is hung as the validator rules that finding
# must-fix, never at dispatch: a fix unit wired to a still-unvalidated finding
# would block the very close a later declined ruling needs, and bd refuses to
# close a blocked issue. Routing a finding would make each its own claim and
# break that cardinality.
#
# Verbs:
#   finding.sh key           --lane L --locus LOC --message MSG
#   finding.sh upsert        --anchor A --lane L --locus LOC --message MSG [--source S]
#   finding.sh set-disposition --finding F --anchor A --disposition D [--reason R] [--reply TEXT]
#   finding.sh wire-fix-unit --fix-unit FU --anchor A --findings F1,F2,...
#   finding.sh open-must-fix --anchor A [--lane L]
#   finding.sh close-unvalidated --anchor A --lane L [--reason R]
#   finding.sh close-answered --anchor A [--reason R]
#
# Callers: signoff.sh (upsert on request-changes, close-unvalidated on
# approve), the validator through set-disposition — which hangs the fix unit's
# edge onto a finding only as it rules that finding must-fix, so the fix unit
# blocks only the findings it must answer — and gate-ensure (open-must-fix
# computes quiescence; close-answered releases it once a fix unit lands). Exit
# 0 on success; a read verb exits 1 when its predicate is false, 2 when the
# store would not read.
set -uo pipefail

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub
_bd_lib_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$_bd_lib_dir/bd-lib.sh}" || { echo "cannot source bd-lib.sh beside this script" >&2; exit 1; }
warn() { echo "finding: $*" >&2; }

LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"
ALL_STATUSES="$LIVE_STATUSES,closed"

usage() {
  cat >&2 <<'USAGE'
usage:
  finding.sh key --lane <lane> --locus <locus> --message <msg>
  finding.sh upsert --anchor <id> --lane <lane> --locus <locus> --message <msg> [--source <src>]
  finding.sh set-disposition --finding <id> --anchor <id> --disposition must-fix|deferred|declined [--reason <r>] [--reply <text>]
  finding.sh wire-fix-unit --fix-unit <id> --anchor <id> --findings <id,id,...>
  finding.sh open-must-fix --anchor <id> [--lane <lane>]
  finding.sh close-unvalidated --anchor <id> --lane <lane> [--reason <r>]
  finding.sh close-answered --anchor <id> [--reason <r>]
USAGE
}

# Normalize a locus or message into a rebase-stable token stream: lowercase,
# drop the line-number suffixes a rebase renumbers (`path:123`, `#L123`), and
# reduce every run of non-alphanumerics to one space. The result names no
# commit and no line, so the same objection keys the same after a rebase moves
# the code. What a locus normalizes to when the file is later renamed is the one
# case the design leaves open; this handles the common one, a diff that only
# renumbers.
normalize() {
  printf '%s' "${1:-}" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/#l[0-9]+//g; s/:[0-9]+/ /g' \
    | tr -c 'a-z0-9' ' ' \
    | tr -s ' ' \
    | sed -E 's/^ +//; s/ +$//'
}

# finding.key = <lane>:<12 hex of sha256(normalized locus + US + message)>. The
# lane prefix keeps two reviewers' findings at one locus distinct; the hash is
# the dedup handle re-raising an objection collides on. GitHub's own review and
# comment ids would not serve: a re-review re-raises a still-standing objection
# under a fresh id, so an id key twins it every pass where the content key
# re-adopts.
compute_key() {
  local lane="$1" locus="$2" msg="$3" nloc nmsg h
  nloc=$(normalize "$locus")
  nmsg=$(normalize "$msg")
  h=$(printf '%s\037%s' "$nloc" "$nmsg" | sha256sum | cut -c1-12)
  printf '%s:%s' "$lane" "$h"
}

# The open finding on this anchor carrying this key, or empty. Dedup is against
# open findings only: a re-review while the objection still stands files
# nothing new, and an objection that recurs after its finding closed is a fresh
# one. Exits 2 (empty stdout) when the store would not read, so a caller can
# tell "no such finding" from "could not ask".
find_open_by_key() {
  local anchor="$1" key="$2" rows
  rows=$(bd_list --metadata-field anchor_bead="$anchor" --status="$LIVE_STATUSES") || return 2
  printf '%s' "$rows" | jq -r --arg k "$key" '
    [ .[] | select(((.metadata.task_kind // "") | tostring) == "finding")
          | select(((.metadata["finding.key"] // "") | tostring) == $k) ]
    | .[0].id // empty' 2>/dev/null
}

edge_exists() { # <blocker> blocks <blocked> ?  (reads the blocked's down-blockers)
  local blocker="$1" blocked="$2"
  bd_json dep list "$blocked" --direction=down -t blocks \
    | jq -e --arg b "$blocker" 'type == "array" and any(.[]?; .id == $b)' >/dev/null 2>&1
}

# The rework fix units answering <finding-lane>'s objections on <anchor>, one
# "<id> <status>" per line, across ALL statuses. A fix unit carries
# task_kind=rework. Two paths file one: signoff stamps source_review_bead on the
# child it files for a machine review's findings; pr-facts files one child per
# human batch, carrying the batch's review ids in source_review and no
# source_review_bead. A finding is answered by the child of its own lane, so match
# on the lane — a human finding takes the child with no source_review_bead, a
# machine finding the child that carries one — and no lane's finding is wired to
# another lane's child.
#
# Read by metadata (anchor_bead + task_kind=rework), not by the anchor's blocks
# edges: the fix-unit->anchor edge is itself sometimes absent, so an edge walk
# would miss the very landed fix unit the close-answered backstop must see. The
# --status is explicit because a bare metadata-field query is open-only, and a
# landed fix unit is closed. Non-zero rc = the ledger would not read.
_anchor_reworks() { # <anchor-id> <finding-lane>
  local rows
  rows=$(bd_list --metadata-field anchor_bead="$1" --status="$ALL_STATUSES") || return 2
  printf '%s' "$rows" | jq -r --arg lane "${2:-}" '
    .[]
    | select(((.metadata.task_kind // "") | tostring) == "rework")
    | select(
        if $lane == "human"
        then ((.metadata.source_review_bead // "") | tostring) == ""
        else ((.metadata.source_review_bead // "") | tostring) != ""
        end)
    | "\(.id) \((.status // "open") | ascii_downcase)"' 2>/dev/null
}

# The fix unit to hang a must-fix finding's close-ordering edge onto, or empty: a
# still-live one if any, else one that has already LANDED. The landed fallback is
# what makes the wiring reliable — the dispatch of a fix unit and the validator's
# must-fix ruling race, so a fix unit can close before its finding is ruled, and
# hanging the edge only to a live fix unit (the old behavior) then left the finding
# edge-less and wedged the re-gate. A landed fix unit still blocking the finding is
# closeable (bd refuses a close only on an OPEN blocker), so close-answered closes
# the finding on the next pass. Non-zero rc = the ledger would not read.
anchor_fix_unit() { # <anchor-id> <finding-lane>
  local rw id
  rw=$(_anchor_reworks "$1" "${2:-}") || return 2
  id=$(printf '%s\n' "$rw" | awk 'NF && $2!="closed" {print $1; exit}')
  [ -n "$id" ] || id=$(printf '%s\n' "$rw" | awk 'NF && $2=="closed" {print $1; exit}')
  [ -n "$id" ] && printf '%s\n' "$id"
  return 0
}

# How many fix units answer <finding-lane> on <anchor>, as "<n_live> <n_landed>".
# close-answered reads this to disambiguate an edge-less must-fix finding: a landed
# fix unit with none still live means the close-ordering edge was missed and the
# fix is on the branch, so the finding must close rather than wedge the re-gate; a
# live fix unit means the fix is still in flight and the finding holds; no fix unit
# at all means an objection nothing has answered yet, which also holds. Non-zero rc
# = the ledger would not read.
anchor_fix_unit_census() { # <anchor-id> <finding-lane>
  local rw
  rw=$(_anchor_reworks "$1" "${2:-}") || return 2
  printf '%s\n' "$rw" | awk 'NF{ if ($2=="closed") c++; else l++ } END{ print (l+0)" "(c+0) }'
}

# Remove every blocks edge INTO <finding> — the beads that block it. A finding
# being declined or reclassified deferred holds nothing and answers no work, so
# nothing may block it: a fix unit wired to it before the validator ruled (or an
# edge left from an earlier must-fix ruling this pass overturns) would refuse the
# close with "cannot close blocked issue" and stall the validator's triage.
# Idempotent and best-effort per edge — the caller's own guard fails closed if the
# subsequent close does not stick.
strip_inbound_blocks() { # <finding>
  local blockers b
  blockers=$(bd_json dep list "$1" --direction=down -t blocks \
    | jq -r 'if type == "array" then .[]?.id else empty end' 2>/dev/null)
  for b in $blockers; do
    [ -n "$b" ] || continue
    gc bd dep remove "$1" "$b" >/dev/null 2>&1 \
      || gc bd dep remove "$b" "$1" >/dev/null 2>&1 || true
  done
}

cmd_key() {
  local lane="" locus="" msg=""
  while [ $# -gt 0 ]; do case "$1" in
    --lane) lane="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --locus) locus="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --message) msg="${2:-}"; shift 2 || { usage; exit 1; } ;;
    *) warn "unknown arg '$1'"; usage; exit 1 ;;
  esac; done
  [ -n "$lane" ] && [ -n "$locus" ] && [ -n "$msg" ] || { warn "key needs --lane, --locus, --message"; exit 1; }
  compute_key "$lane" "$locus" "$msg"
}

cmd_upsert() {
  local anchor="" lane="" locus="" msg="" source=""
  while [ $# -gt 0 ]; do case "$1" in
    --anchor) anchor="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --lane) lane="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --locus) locus="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --message) msg="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --source) source="${2:-}"; shift 2 || { usage; exit 1; } ;;
    *) warn "unknown arg '$1'"; usage; exit 1 ;;
  esac; done
  [ -n "$anchor" ] && [ -n "$lane" ] && [ -n "$locus" ] && [ -n "$msg" ] \
    || { warn "upsert needs --anchor, --lane, --locus, --message"; exit 1; }
  [ -n "$source" ] || source="machine:$lane"
  local key existing
  key=$(compute_key "$lane" "$locus" "$msg")
  existing=$(find_open_by_key "$anchor" "$key"); local rc=$?
  if [ "$rc" -eq 2 ]; then
    warn "could not read findings on $anchor to dedup key $key; nothing filed"
    exit 2
  fi
  if [ -n "$existing" ]; then
    printf '%s\n' "$existing"   # re-raise: the existing finding, nothing created
    return 0
  fi
  # The title carries the human-readable objection; the locus and full message
  # live in the description. The key, not the title, is the dedup handle.
  local title desc id
  title="finding[$lane]: $(printf '%s' "$msg" | tr '\n' ' ' | cut -c1-120)"
  desc=$(printf 'Locus: %s\n\n%s\n\nRaised by %s reviewing anchor %s.' "$locus" "$msg" "$source" "$anchor")
  id=$(gc bd create "$title" -t task -d "$desc" --json 2>/dev/null | jq -r '.id // .[0].id // empty' 2>/dev/null)
  [ -n "$id" ] || { warn "could not create finding bead for key $key on $anchor"; exit 2; }
  gc bd update "$id" \
    --set-metadata task_kind=finding \
    --set-metadata anchor_bead="$anchor" \
    --set-metadata finding.lane="$lane" \
    --set-metadata finding.key="$key" \
    --set-metadata finding.disposition=unvalidated \
    --set-metadata finding.source="$source" >/dev/null 2>&1 || { warn "could not stamp finding $id metadata"; exit 2; }
  # A new finding changes this anchor's findings list; drop the per-pass bd_list
  # cache so a same-pass re-read sees it (pr-facts files a finding for a human
  # comment, then re-reads to wire its fix unit). No-op outside a reconcile pass.
  bd_cache_clear
  local got
  got=$(bd_json show "$id" | jq -r '(.[0].metadata["finding.key"] // "") | tostring' 2>/dev/null)
  [ "$got" = "$key" ] || { warn "finding $id key did not read back (got '$got', want '$key')"; exit 2; }
  printf '%s\n' "$id"
}

cmd_set_disposition() {
  local finding="" anchor="" disp="" reason="" reply=""
  while [ $# -gt 0 ]; do case "$1" in
    --finding) finding="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --anchor) anchor="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --disposition) disp="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --reason) reason="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --reply) reply="${2:-}"; shift 2 || { usage; exit 1; } ;;
    *) warn "unknown arg '$1'"; usage; exit 1 ;;
  esac; done
  [ -n "$finding" ] && [ -n "$anchor" ] && [ -n "$disp" ] \
    || { warn "set-disposition needs --finding, --anchor, --disposition"; exit 1; }
  case "$disp" in
    must-fix|deferred|declined) ;;
    *) warn "--disposition must be must-fix, deferred, or declined (got '$disp')"; exit 1 ;;
  esac
  gc bd update "$finding" --set-metadata finding.disposition="$disp" >/dev/null 2>&1 \
    || { warn "could not set finding.disposition=$disp on $finding"; exit 2; }
  case "$disp" in
    must-fix)
      # The hold merge.sh's blocker probe already reads. Idempotent: a re-run
      # over a finding already blocking the anchor adds no second edge.
      if ! edge_exists "$finding" "$anchor"; then
        gc bd dep "$finding" --blocks "$anchor" >/dev/null 2>&1 \
          || { warn "could not wire $finding --blocks $anchor for must-fix"; exit 2; }
      fi
      edge_exists "$finding" "$anchor" \
        || { warn "$finding does not block $anchor after must-fix wiring"; exit 2; }
      # The fix unit answers only the findings ruled must-fix, so its close-ordering
      # edge onto this finding is hung HERE, from the ruling — never at dispatch,
      # when the finding was still unvalidated and a later declined ruling could not
      # close it past that block. anchor_fix_unit returns a live fix unit, or the
      # one that already LANDED when the dispatch won the race with this ruling: a
      # landed fix unit still blocks the finding (bd refuses a close only on an OPEN
      # blocker), so close-answered closes the finding on the next pass rather than
      # leaving it edge-less and wedging the re-gate. Best-effort: the finding's own
      # anchor edge above is the hold, so a fix unit whose edge cannot be hung costs
      # the close ordering, never the merge hold. The anchor edge is the fix unit's
      # own (hung at dispatch), not re-hung here.
      local fu flane
      flane=$(bd_json show "$finding" | jq -r '(.[0].metadata["finding.lane"] // "") | tostring' 2>/dev/null)
      fu=$(anchor_fix_unit "$anchor" "$flane") || fu=""
      if [ -n "$fu" ] && ! edge_exists "$fu" "$finding"; then
        gc bd dep "$fu" --blocks "$finding" >/dev/null 2>&1 \
          || warn "could not hang fix unit $fu --blocks must-fix finding $finding; the finding's own anchor edge still holds the merge"
      fi
      ;;
    deferred)
      # Provenance only, holding nothing: discovered-from is neither
      # ready-blocking nor read by merge.sh, so a deferred finding stays open
      # across the merge. A must-fix -> deferred reclassification must first
      # retract the blocks edge the earlier disposition wired — merge.sh reads
      # blocks downward, so a surviving edge would keep a deferred finding
      # holding the merge it must not. Fail closed if it survives rather than
      # report a still-standing hold as cleared. Retract before adding
      # discovered-from so the removal cannot touch the provenance edge.
      if edge_exists "$finding" "$anchor"; then
        gc bd dep remove "$anchor" "$finding" >/dev/null 2>&1 \
          || gc bd dep remove "$finding" "$anchor" >/dev/null 2>&1 || true
      fi
      ! edge_exists "$finding" "$anchor" \
        || { warn "$finding still blocks $anchor after deferred reclassification"; exit 2; }
      # A deferred finding is fresh work picked up after the merge, answered by no
      # fix unit now, so drop any fix-unit edge a prior must-fix ruling hung onto it
      # — the deferral holds nothing and nothing may hold it. Retract before adding
      # the provenance edge so the strip cannot touch discovered-from.
      strip_inbound_blocks "$finding"
      gc bd dep add "$finding" "$anchor" --type discovered-from >/dev/null 2>&1 \
        || warn "could not wire $finding --discovered-from $anchor (deferred records provenance only)"
      # The deferral REASON is the whole justification for not fixing now, and
      # a deferred finding holds nothing — the bead is the only place whoever
      # picks it up after the merge can read why it was left. Record it the way
      # declined does, or the policy's "deferral needs a reason" is unenforced
      # prose: the caller passes one and nothing keeps it.
      local dnote="deferred"
      [ -n "$reason" ] && dnote="deferred: $reason"
      gc bd update "$finding" --append-notes "$dnote" >/dev/null 2>&1 \
        || warn "could not record the deferral reason on $finding"
      ;;
    declined)
      # No objection to answer: close it with the reason. A declined finding
      # holds nothing and nothing holds it, so drop BOTH sides before the close:
      # its own must-fix hold on the anchor (finding --blocks anchor), and every
      # blocker wired INTO it. The inbound strip is what the close depends on — a
      # fix unit wired onto this finding (from an earlier must-fix ruling, or a
      # dispatch that cross-wired before the validator ran) would make bd refuse
      # the close with "cannot close blocked issue" and stall the whole triage.
      if edge_exists "$finding" "$anchor"; then
        gc bd dep remove "$anchor" "$finding" >/dev/null 2>&1 \
          || gc bd dep remove "$finding" "$anchor" >/dev/null 2>&1 || true
      fi
      strip_inbound_blocks "$finding"
      # A declined HUMAN objection owes its raiser an answer on the PR: the
      # operator read the diff and objected, so overruling them in silence is the
      # gap the peer model closes. Stamp the owed reply BEFORE the close, and fail
      # closed if it does not stick — a finding closed without the reply the
      # caller asked for is a silent decline the write-back can no longer post,
      # and a closed finding is off the validator's unvalidated set so nothing
      # re-attempts it. A machine or no-objection decline passes no --reply and
      # owes nothing.
      if [ -n "$reply" ]; then
        gc bd update "$finding" --set-metadata finding.reply="$reply" >/dev/null 2>&1 \
          || { warn "could not stamp finding.reply on $finding; NOT closing (a silent decline)"; exit 2; }
      fi
      local note="declined"
      [ -n "$reason" ] && note="declined: $reason"
      gc bd update "$finding" --status=closed --append-notes "$note" >/dev/null 2>&1 \
        || { warn "could not close declined finding $finding"; exit 2; }
      ;;
  esac
}

cmd_wire_fix_unit() {
  local fu="" anchor="" findings=""
  while [ $# -gt 0 ]; do case "$1" in
    --fix-unit) fu="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --anchor) anchor="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --findings) findings="${2:-}"; shift 2 || { usage; exit 1; } ;;
    *) warn "unknown arg '$1'"; usage; exit 1 ;;
  esac; done
  [ -n "$fu" ] && [ -n "$anchor" ] || { warn "wire-fix-unit needs --fix-unit and --anchor"; exit 1; }
  # Edge onto the anchor: the routed live blocker merge.sh reads. Idempotent —
  # signoff.sh may have wired it already.
  if ! edge_exists "$fu" "$anchor"; then
    gc bd dep "$fu" --blocks "$anchor" >/dev/null 2>&1 \
      || { warn "could not wire fix unit $fu --blocks anchor $anchor"; exit 2; }
  fi
  # An edge onto every finding it answers: the many-to-one relation, and the
  # close ordering — bd refuses to close a blocked issue, so no finding closes
  # before the work answering it does.
  local f rc=0
  local IFS=','
  for f in $findings; do
    [ -n "$f" ] || continue
    if ! edge_exists "$fu" "$f"; then
      gc bd dep "$fu" --blocks "$f" >/dev/null 2>&1 || { warn "could not wire fix unit $fu --blocks finding $f"; rc=2; }
    fi
  done
  return "$rc"
}

cmd_open_must_fix() {
  local anchor="" lane=""
  while [ $# -gt 0 ]; do case "$1" in
    --anchor) anchor="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --lane) lane="${2:-}"; shift 2 || { usage; exit 1; } ;;
    *) warn "unknown arg '$1'"; usage; exit 1 ;;
  esac; done
  [ -n "$anchor" ] || { warn "open-must-fix needs --anchor"; exit 1; }
  local rows ids
  rows=$(bd_list --metadata-field anchor_bead="$anchor" --status="$LIVE_STATUSES") \
    || { warn "could not read findings on $anchor"; return 2; }
  ids=$(printf '%s' "$rows" | jq -r --arg lane "$lane" '
    [ .[] | select(((.metadata.task_kind // "") | tostring) == "finding")
          | select(((.metadata["finding.disposition"] // "") | tostring) == "must-fix")
          | select($lane == "" or ((.metadata["finding.lane"] // "") | tostring) == $lane) ]
    | .[].id' 2>/dev/null)
  if [ -n "$ids" ]; then
    printf '%s\n' "$ids"
    return 0
  fi
  return 1
}

cmd_close_unvalidated() {
  local anchor="" lane="" reason=""
  while [ $# -gt 0 ]; do case "$1" in
    --anchor) anchor="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --lane) lane="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --reason) reason="${2:-}"; shift 2 || { usage; exit 1; } ;;
    *) warn "unknown arg '$1'"; usage; exit 1 ;;
  esac; done
  [ -n "$anchor" ] && [ -n "$lane" ] || { warn "close-unvalidated needs --anchor and --lane"; exit 1; }
  # A lane found clean answers its own still-unruled findings: close the
  # unvalidated ones the lane raised. A validated finding (must-fix, deferred,
  # declined) belongs to the validator and is left alone; a finding a fix unit
  # still blocks refuses to close and is left for that unit's landing.
  local rows ids id note
  rows=$(bd_list --metadata-field anchor_bead="$anchor" --status="$LIVE_STATUSES") || { warn "could not read findings on $anchor"; return 2; }
  ids=$(printf '%s' "$rows" | jq -r --arg lane "$lane" '
    [ .[] | select(((.metadata.task_kind // "") | tostring) == "finding")
          | select(((.metadata["finding.disposition"] // "") | tostring) == "unvalidated")
          | select(((.metadata["finding.lane"] // "") | tostring) == $lane) ]
    | .[].id' 2>/dev/null)
  note="resolved: lane $lane found clean"
  [ -n "$reason" ] && note="$note — $reason"
  for id in $ids; do
    gc bd update "$id" --status=closed --append-notes "$note" >/dev/null 2>&1 || true
  done
  # Closed findings leave the LIVE set; drop the per-pass bd_list cache so a
  # same-pass re-read does not still see them. No-op outside a reconcile pass.
  bd_cache_clear
}

# A must-fix finding is closed once every fix unit answering it has landed. The
# fix unit blocks the finding (wire-fix-unit), and bd refuses to close a blocked
# issue, so the finding is closeable exactly when all its blockers have closed —
# which is the fix unit's landing (merge-push closes the rework once its commit
# is on the branch). Nothing else performs that close, so the finding otherwise
# stays open and holds the re-gate through quiescence, wedging a landed fix at
# pre_open_gate. gate-ensure runs this per anchor: the reader that computes
# quiescence and holds the re-gate is the one that releases it, so the two
# cannot disagree. A finding still blocked by a live fix unit is left for that
# unit's landing. A finding with NO blocker edge is the ambiguous case: usually
# an objection no fix unit answers yet (left open), but also the shape a missed
# close-ordering edge leaves behind when a fix landed — so it is closed only when
# the lane's fix unit census shows one landed and none still live, the same fact
# the edge would have carried.
cmd_close_answered() {
  local anchor="" reason=""
  while [ $# -gt 0 ]; do case "$1" in
    --anchor) anchor="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --reason) reason="${2:-}"; shift 2 || { usage; exit 1; } ;;
    *) warn "unknown arg '$1'"; usage; exit 1 ;;
  esac; done
  [ -n "$anchor" ] || { warn "close-answered needs --anchor"; exit 1; }
  local rows ids id note cnote blk n_all n_live flane census c_live c_landed
  rows=$(bd_list --metadata-field anchor_bead="$anchor" --status="$LIVE_STATUSES") || { warn "could not read findings on $anchor"; return 2; }
  ids=$(printf '%s' "$rows" | jq -r '
    [ .[] | select(((.metadata.task_kind // "") | tostring) == "finding")
          | select(((.metadata["finding.disposition"] // "") | tostring) == "must-fix") ]
    | .[].id' 2>/dev/null)
  [ -n "$ids" ] || return 0
  note="resolved: fix unit landed — every blocker closed, so the objection's fix is on the branch"
  [ -n "$reason" ] && note="$note ($reason)"
  for id in $ids; do
    # The finding's blocks-blockers are its fix units. Read them with status so a
    # still-live one leaves the finding open rather than being attempted and
    # warned every pass.
    blk=$(bd_json dep list "$id" --direction=down -t blocks)
    printf '%s' "$blk" | jq -e 'type == "array"' >/dev/null 2>&1 \
      || { warn "could not read blockers of finding $id; leaving it open"; continue; }
    n_all=$(printf '%s' "$blk" | jq -r 'length' 2>/dev/null)
    n_live=$(printf '%s' "$blk" | jq -r '[ .[] | select(((.status // "open") | tostring | ascii_downcase) != "closed") ] | length' 2>/dev/null)
    cnote="$note"
    if [ "${n_all:-0}" -gt 0 ]; then
      # Edges present: close exactly when every fix unit answering it has landed.
      [ "${n_live:-1}" -eq 0 ] || continue
    else
      # No blocker edge at all. This is the shape a missed close-ordering edge
      # leaves (anchor_fix_unit was open-only, so a fix unit that closed before the
      # ruling was never wired), and also the shape of a live objection no fix unit
      # has answered yet. The lane's fix-unit census tells them apart: close only
      # when one has LANDED and none is still live. A live fix unit (fix in flight)
      # or no fix unit (unanswered objection) leaves the finding holding. An
      # unreadable census leaves it open.
      flane=$(printf '%s' "$rows" | jq -r --arg id "$id" '.[] | select(.id == $id) | (.metadata["finding.lane"] // "") | tostring' 2>/dev/null)
      census=$(anchor_fix_unit_census "$anchor" "$flane") || continue
      c_live="${census%% *}"; c_landed="${census##* }"
      { [ "${c_live:-0}" -eq 0 ] && [ "${c_landed:-0}" -gt 0 ]; } || continue
      cnote="resolved: fix unit landed (no close-ordering edge; matched by lane $flane) — the objection's fix is on the branch"
      [ -n "$reason" ] && cnote="$cnote ($reason)"
    fi
    gc bd update "$id" --status=closed --append-notes "$cnote" >/dev/null 2>&1 \
      || warn "could not close answered finding $id"
  done
  # Closed findings leave the LIVE set; drop the per-pass bd_list cache so the
  # same-pass re-read (gate-ensure recomputes quiescence right after) does not
  # still see them. No-op outside a reconcile pass.
  bd_cache_clear
}

[ $# -ge 1 ] || { usage; exit 1; }
VERB="$1"; shift
case "$VERB" in
  key)               cmd_key "$@" ;;
  upsert)            cmd_upsert "$@" ;;
  set-disposition)   cmd_set_disposition "$@" ;;
  wire-fix-unit)     cmd_wire_fix_unit "$@" ;;
  open-must-fix)     cmd_open_must_fix "$@" ;;
  close-unvalidated) cmd_close_unvalidated "$@" ;;
  close-answered)    cmd_close_answered "$@" ;;
  *) warn "unknown verb '$VERB'"; usage; exit 1 ;;
esac
