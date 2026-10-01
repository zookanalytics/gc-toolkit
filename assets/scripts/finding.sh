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
#   finding.sh close-resolved --anchor A --expected-head H [--reason R]
#
# Callers: signoff.sh (upsert on request-changes, close-unvalidated on
# approve), the validator through set-disposition — which hangs the fix unit's
# edge onto a finding only as it rules that finding must-fix, so the fix unit
# blocks only the findings it must answer — and gate-ensure (open-must-fix
# computes quiescence; close-answered releases it once a fix unit lands;
# close-resolved releases it once the human re-approves, the signal a fix unit
# landing cannot carry). Exit 0 on success; a read verb exits 1 when its
# predicate is false, 2 when the store would not read.
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
  finding.sh close-resolved --anchor <id> --expected-head <sha> [--reason <r>]
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
  rows=$(gc bd list --metadata-field anchor_bead="$anchor" --status="$LIVE_STATUSES" --limit=0 --json 2>/dev/null | scrub)
  printf '%s' "$rows" | jq -e 'type == "array"' >/dev/null 2>&1 || return 2
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

# The open fix unit answering <finding-lane>'s objections on <anchor>, or empty.
# A fix unit is a live blocks-dep child of the anchor carrying task_kind=rework.
# Two paths file one: signoff stamps source_review_bead on the child it files for
# a machine review's findings; pr-facts files one child per human batch, carrying
# the batch's review ids in source_review and no source_review_bead. A finding is
# answered by the child of its own lane, so match on the lane — a human finding
# takes the child with no source_review_bead, a machine finding the child that
# carries one — and no lane's finding is wired to another lane's child. must-fix
# wiring reads this to hang the close-ordering edge the fix unit's landing
# releases. Non-zero rc = the ledger would not read.
anchor_fix_unit() { # <anchor-id> <finding-lane>
  local raw
  raw=$(bd_json dep list "$1" --direction=down -t blocks) || return 2
  printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 2
  printf '%s' "$raw" | jq -r --arg ls "$LIVE_STATUSES" --arg lane "${2:-}" '
    ($ls | split(",")) as $live
    | [ .[]
        | select(((.status // "open") | ascii_downcase) as $st | ($live | index($st)) != null)
        | select(((.metadata.task_kind // "") | tostring) == "rework")
        | select(
            if $lane == "human"
            then ((.metadata.source_review_bead // "") | tostring) == ""
            else ((.metadata.source_review_bead // "") | tostring) != ""
            end)
        | .id ] | (.[0] // empty)' 2>/dev/null
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
      # close it past that block. Wire it when a fix unit stands on the anchor (a
      # visit-routed feedback batch has none). Best-effort: the finding's own anchor
      # edge above is the hold, so a fix unit whose edge cannot be hung costs the
      # close ordering, never the merge hold.
      local fu flane
      flane=$(bd_json show "$finding" | jq -r '(.[0].metadata["finding.lane"] // "") | tostring' 2>/dev/null)
      fu=$(anchor_fix_unit "$anchor" "$flane") || fu=""
      if [ -n "$fu" ] && ! edge_exists "$fu" "$finding"; then
        cmd_wire_fix_unit --fix-unit "$fu" --anchor "$anchor" --findings "$finding" >/dev/null 2>&1 \
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
  rows=$(gc bd list --metadata-field anchor_bead="$anchor" --status="$LIVE_STATUSES" --limit=0 --json 2>/dev/null | scrub)
  printf '%s' "$rows" | jq -e 'type == "array"' >/dev/null 2>&1 \
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
  rows=$(gc bd list --metadata-field anchor_bead="$anchor" --status="$LIVE_STATUSES" --limit=0 --json 2>/dev/null | scrub)
  printf '%s' "$rows" | jq -e 'type == "array"' >/dev/null 2>&1 || { warn "could not read findings on $anchor"; return 2; }
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
}

# A must-fix finding is closed once every fix unit answering it has landed. The
# fix unit blocks the finding (wire-fix-unit), and bd refuses to close a blocked
# issue, so the finding is closeable exactly when all its blockers have closed —
# which is the fix unit's landing (merge-push closes the rework once its commit
# is on the branch). Nothing else performs that close, so the finding otherwise
# stays open and holds the re-gate through quiescence, wedging a landed fix at
# pre_open_gate. gate-ensure runs this per anchor: the reader that computes
# quiescence and holds the re-gate is the one that releases it, so the two
# cannot disagree. A must-fix finding with no blocker is an objection no fix
# unit answers yet, and one still blocked by a live fix unit is left for that
# unit's landing — neither closes here.
cmd_close_answered() {
  local anchor="" reason=""
  while [ $# -gt 0 ]; do case "$1" in
    --anchor) anchor="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --reason) reason="${2:-}"; shift 2 || { usage; exit 1; } ;;
    *) warn "unknown arg '$1'"; usage; exit 1 ;;
  esac; done
  [ -n "$anchor" ] || { warn "close-answered needs --anchor"; exit 1; }
  local rows ids id note blk n_all n_live
  rows=$(gc bd list --metadata-field anchor_bead="$anchor" --status="$LIVE_STATUSES" --limit=0 --json 2>/dev/null | scrub)
  printf '%s' "$rows" | jq -e 'type == "array"' >/dev/null 2>&1 || { warn "could not read findings on $anchor"; return 2; }
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
    # warned every pass. A finding with no blocker at all has no fix unit yet.
    blk=$(bd_json dep list "$id" --direction=down -t blocks)
    printf '%s' "$blk" | jq -e 'type == "array"' >/dev/null 2>&1 \
      || { warn "could not read blockers of finding $id; leaving it open"; continue; }
    n_all=$(printf '%s' "$blk" | jq -r 'length' 2>/dev/null)
    n_live=$(printf '%s' "$blk" | jq -r '[ .[] | select(((.status // "open") | tostring | ascii_downcase) != "closed") ] | length' 2>/dev/null)
    [ "${n_all:-0}" -gt 0 ] && [ "${n_live:-1}" -eq 0 ] || continue
    gc bd update "$id" --status=closed --append-notes "$note" >/dev/null 2>&1 \
      || warn "could not close answered finding $id"
  done
}

# A human's re-approval of the PR validates that the objections that human
# raised are resolved, whatever route the fix took — a fix unit that landed, an
# out-of-band artifact attached to the PR, or the operator simply satisfied.
# close-answered reads only a fix unit landing, so an objection resolved any
# other way stays open holding the merge: the finding through its blocks edge and
# quiescence clause (a), the fix unit through clause (b). This closes the anchor's
# HUMAN-source objection beads once the recorded pr_posture reads approved.
#
# The posture gate is the signal. pr-facts.sh records the PR's review state as a
# dated pr_posture on the anchor every pass; `approved` means reviewDecision is
# APPROVED and no reviewer currently requests changes, pinned to the head a
# current review approved — the current-head approval evidence merge.sh's own
# gate stands on, so the closer and the merge agree on when a head is approved.
# Any other value (or an absent one, as on a pre-open anchor with no PR) closes
# nothing — the raiser has not re-approved, so there is no resolution to validate.
#
# The posture's head is the head the approval COVERS: pr-facts.sh pins an approved
# posture to the commit a current review approved, not to the live head, so a push
# after an approval leaves approved@<approved-head> — a head the live branch no
# longer matches. The close is gated on that pin equalling the branch's current
# head, passed as --expected-head, so a stale approval validates nothing. It closes
# nothing when either head is unreadable (an absent --expected-head, or a posture
# carrying no head) — an unread head cannot prove the approval is current, so the
# merge holds one more pass, the safe way.
#
# The scope is human-source beads, and that is load-bearing. reviewDecision
# speaks the human authority alone — a machine finding is a bead invisible to it —
# so a human approval closes the human's own objections and must not clear a
# machine correctness finding the human never addressed. merge.sh's blocker probe
# keeps holding on a machine finding's edge exactly as before.
#
# What closes: the human-batch fix unit (a live blocks-child of the anchor
# carrying no source_review_bead — the shape anchor_fix_unit reads for the human
# lane; a machine rework carries the bead) FIRST, because it blocks the findings
# and bd refuses to close a blocked issue; then each open human finding whose
# disposition is unvalidated or must-fix. A deferred finding holds nothing and is
# a tracked post-merge follow-up, so re-approval leaves it; a declined one is
# already closed. Each finding's inbound blocks edges are stripped before its
# close, so the close does not wait on a blocker the objection does not own — the
# finding wired to block behind an unrelated fix unit closes cleanly. Best-effort
# per bead, like close-answered; an unreadable store closes nothing and the merge
# stays held.
cmd_close_resolved() {
  local anchor="" reason="" expected_head=""
  while [ $# -gt 0 ]; do case "$1" in
    --anchor) anchor="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --reason) reason="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --expected-head) expected_head="${2:-}"; shift 2 || { usage; exit 1; } ;;
    *) warn "unknown arg '$1'"; usage; exit 1 ;;
  esac; done
  [ -n "$anchor" ] || { warn "close-resolved needs --anchor"; exit 1; }
  local posture
  posture=$(bd_json show "$anchor" | jq -r '(.[0].metadata.pr_posture // "") | tostring' 2>/dev/null)
  case "$posture" in
    approved|approved@*) ;;
    *) return 0 ;;
  esac
  # The approval is current only if its pinned head is the branch's live head.
  # pr_posture is <value>@<head>@<instant>, so the head is the second field; a
  # bare `approved` carries none. Close nothing when the pinned head is absent,
  # the live head is unreadable (empty --expected-head), or the two differ — a
  # stale approved@<old-head> left by a post-approval push must not close.
  local posture_head=""
  case "$posture" in *@*) posture_head="${posture#*@}"; posture_head="${posture_head%%@*}" ;; esac
  [ -n "$expected_head" ] && [ -n "$posture_head" ] && [ "$posture_head" = "$expected_head" ] || return 0
  local rows note
  rows=$(gc bd list --metadata-field anchor_bead="$anchor" --status="$LIVE_STATUSES" --limit=0 --json 2>/dev/null | scrub)
  printf '%s' "$rows" | jq -e 'type == "array"' >/dev/null 2>&1 || { warn "could not read beads on $anchor"; return 2; }
  note="resolved: raiser re-approved the PR (pr_posture=approved); the objection is validated resolved whatever route the fix took"
  [ -n "$reason" ] && note="$note ($reason)"
  # The human-batch fix unit(s): a blocks-child of the anchor carrying
  # task_kind=rework and no source_review_bead, the shape anchor_fix_unit reads
  # for the human lane (a machine rework carries the bead). Only an OPEN one is
  # closed: an open rework is routed-but-unclaimed, the wedge shape after an
  # out-of-band fix, and closing it also stops a polecat wasting a claim on work
  # the re-approval mooted. An in_progress rework has a live worker whose hand-off
  # will close it the normal way, and a blocked one is held for a reason; yanking
  # either would strand live or intentionally-held work, so both are left. A
  # non-array read leaves everything open rather than closing a finding whose fix
  # unit could not be enumerated.
  local blk fixids fu
  blk=$(bd_json dep list "$anchor" --direction=down -t blocks)
  if printf '%s' "$blk" | jq -e 'type == "array"' >/dev/null 2>&1; then
    fixids=$(printf '%s' "$blk" | jq -r '
      [ .[]
          | select(((.status // "open") | ascii_downcase) == "open")
          | select(((.metadata.task_kind // "") | tostring) == "rework")
          | select(((.metadata.source_review_bead // "") | tostring) == "")
          | .id ] | .[]' 2>/dev/null)
    for fu in $fixids; do
      [ -n "$fu" ] || continue
      gc bd update "$fu" --status=closed --append-notes "$note" >/dev/null 2>&1 \
        || warn "could not close human fix unit $fu on re-approval"
    done
  else
    warn "could not read $anchor's blockers; leaving the human fix unit open"
  fi
  # The human findings. Strip each one's inbound blocks before the close so it
  # does not wait on a blocker the objection does not own, and drop its own
  # blocks-anchor hold.
  local fids fid
  fids=$(printf '%s' "$rows" | jq -r '
    [ .[] | select(((.metadata.task_kind // "") | tostring) == "finding")
          | select(((.metadata["finding.source"] // "") | tostring) | startswith("human:"))
          | ((.metadata["finding.disposition"] // "") | tostring) as $d
          | select($d == "unvalidated" or $d == "must-fix") ]
    | .[].id' 2>/dev/null)
  for fid in $fids; do
    [ -n "$fid" ] || continue
    if edge_exists "$fid" "$anchor"; then
      gc bd dep remove "$anchor" "$fid" >/dev/null 2>&1 \
        || gc bd dep remove "$fid" "$anchor" >/dev/null 2>&1 || true
    fi
    strip_inbound_blocks "$fid"
    gc bd update "$fid" --status=closed --append-notes "$note" >/dev/null 2>&1 \
      || warn "could not close re-approved human finding $fid"
  done
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
  close-resolved)    cmd_close_resolved "$@" ;;
  *) warn "unknown verb '$VERB'"; usage; exit 1 ;;
esac
