#!/usr/bin/env bash
# converse-fold.sh — resolve what a fresh visit's sitting is about and who
# holds it, so the caller can fold a duplicate into a live sibling instead of
# opening a second sitting on one topic.
#
# A standing scope (task_kind=triage-subject) carries one visit per distinct
# situation under a single continuation group, so the group is a bucket, not a
# topic. Keying the fold on the group alone folds unrelated sittings together
# (one lost) or folds two live sittings into each other (both lost). The TOPIC
# that decides sameness is a `key:`-prefixed escalation_key, else the subject;
# and the lowest-id tiebreak plus the tracks-edge recovery of an empty group
# stamp are each load-bearing.
#
# A fold never crosses stores. Folding closes the visit and moves any PR merge
# hold it carries onto the holder (visit-close.sh --into), and merge.sh reads a
# PR's merge holds from its own rig's store only, so a holder in another store
# would carry the hold where it holds nothing. A bead's id prefix names its
# store, so the holder is always a visit sharing this one's prefix. A visit is
# filed in its subject's own store (escalate.sh), so a live sitting on the same
# topic in another store is a misfile. It is reported, never folded into.
# assets/scripts/converse-fold-scope.test.sh runs this against every one of
# those shapes.
#
# Inputs (environment, or positional fallback):
#   VISIT    the visit bead just claimed (required; $1)
#   SUBJECT  its continuation group; may be empty and recovered here ($2)
# Output: four eval-able assignments on stdout, each value single-quoted so a
# caller can `eval` them without a metacharacter in the data becoming syntax —
#   SUBJECT=<recovered-or-passed group>
#   TOPIC=<what decides sameness>
#   HOLDER=<$VISIT when you hold it, the id of another visit in this one's
#           store to fold into it, EMPTY when this visit's own store did not
#           read (hold, do not fold)>
#   MISFILED=<the live visits on this topic, this one included, that sit in a
#           different store from their subject, space-separated; empty when
#           there are none or no rig carries the subject's prefix>
set -u

# The one definition of what subject a visit covers (its tracks-edge identity,
# gc.continuation_group stamp as fallback), shared with gc-helm.sh and the
# sweeps. Exposes $VISIT_IDENTITY_JQ.
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=visit-identity.sh
. "$HERE/visit-identity.sh" || { echo "converse-fold: cannot source visit-identity.sh from $HERE" >&2; exit 3; }

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

# >>> eval-safe-quote
# The caller evals the assignments below, and SUBJECT is a continuation group
# recovered from claim/metadata, so it can carry any byte.
# Single-quote every emitted value so eval reads it as one literal string: a
# group like `g;rm -rf x` stays data, never shell syntax. An embedded single
# quote becomes the '\'' idiom.
shq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
# <<< eval-safe-quote

# >>> bounded-store-read
# The scan below reads every rig's store, so one slow or hung Dolt
# server would otherwise wedge a converse claim. Bound each read; a store that
# does not answer in time is skipped like an unreadable one. No `timeout` on
# the box means no bound, as the ledger migrations do.
BOUND="${GC_FOLD_SCAN_TIMEOUT:-20}"
run_bounded() { if command -v timeout >/dev/null 2>&1; then timeout "$BOUND" "$@" </dev/null; else "$@" </dev/null; fi; }
# <<< bounded-store-read

VISIT="${VISIT:-${1:-}}"
SUBJECT="${SUBJECT:-${2:-}}"

[ -n "$VISIT" ] || { echo "converse-fold: a visit id is required (\$VISIT or arg 1)" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "converse-fold: jq is required" >&2; exit 2; }
command -v gc >/dev/null 2>&1 || { echo "converse-fold: gc is required" >&2; exit 2; }

V=$(gc bd show "$VISIT" --json | scrub)
# The claim reports the gc.continuation_group STAMP, and the stamp lands
# empty on a minority of visits while the `tracks` edge filed alongside
# it still carries the subject. Recover it from the edge before using it
# as a filter — every predicate below keys on it.
if [ -z "$SUBJECT" ]; then
  SUBJECT=$(printf '%s' "$V" | jq -r "$VISIT_IDENTITY_JQ"'(.[0] // {}) | visit_subject')
fi
# The TOPIC decides sameness, and it is not always a bead: an escalate.sh
# visit carries its situation in escalation_key, which is the only stamp
# that tells two findings of one bucket apart. The `key:` prefix keeps a
# key and a bead id from ever comparing equal. This one definition computes
# the topic of this visit and of every sibling it is compared against.
TOPIC_JQ='
  def topic($subject):
    (.metadata.escalation_key // "") as $k
    | if $k != "" then "key:" + $k else $subject end;'
TOPIC=$(printf '%s' "$V" | jq -r --arg s "$SUBJECT" "$TOPIC_JQ"'(.[0] // {}) | topic($s)')
TOPIC="${TOPIC:-$SUBJECT}"
MISFILED=""
if [ -z "$SUBJECT" ]; then
  # Neither recording resolved. With an empty $s every predicate below
  # degenerates to matching every empty-group visit — an unstamped visit's
  # topic falls back to $s and matches as well — and the lowest-id
  # tiebreak would fold this sitting into one about an unrelated subject.
  # You are the holder.
  HOLDER="$VISIT"
else
  # The id prefix is the store. The holder must share this visit's prefix, and
  # a correctly filed visit shares its subject's.
  VISIT_PREFIX="${VISIT%%-*}"
  SUBJECT_PREFIX="${SUBJECT%%-*}"
  # The scan reads the in_progress listing, the live sittings, of every rig's
  # store: this visit's own for the holder, and every other one for a sitting on
  # this topic that was filed in the wrong store.
  SCOPES=$(run_bounded gc rig list --json 2>/dev/null | scrub \
    | jq -r '.rigs[]? | select((.path // "") != "")
             | [.path, ((.suspended // false) | tostring), (.prefix // "")] | join("\u001f")' 2>/dev/null)
  if [ -z "$SCOPES" ]; then
    # gc rig list named no store, so this visit's own store can be neither found
    # nor read. Resolve EMPTY, which the caller reads as hold — never a fold on
    # an unread listing.
    HOLDER=""
  else
    UNION=""
    OWN_RIGS=0; OWN_READ=0; SUBJECT_STORE=0
    while IFS=$'\037' read -r rig_path suspended prefix; do
      [ -n "$rig_path" ] || continue
      own=0
      if [ -n "$prefix" ] && [ "$prefix" = "$VISIT_PREFIX" ]; then
        own=1; OWN_RIGS=$((OWN_RIGS + 1))
      fi
      if [ -n "$prefix" ] && [ "$prefix" = "$SUBJECT_PREFIX" ]; then SUBJECT_STORE=1; fi
      # A suspended rig has no live session to hold a sitting, and querying its
      # store would auto-start an orphan Dolt server.
      [ "$suspended" = "true" ] && continue
      rows=$(run_bounded gc bd list --db "$rig_path/.beads" --status=in_progress --json --limit=0 2>/dev/null | scrub)
      if printf '%s' "$rows" | jq -e 'type=="array"' >/dev/null 2>&1; then
        [ "$own" -eq 1 ] && OWN_READ=1
        UNION="$UNION$rows
"
      else
        # Another store that did not read can hide only a misfile, which goes
        # unreported this pass. This visit's own store is the one a holder must
        # live in, so its failing to read is decided below.
        echo "converse-fold: store $rig_path/.beads did not read; its in_progress visits are absent from this scan" >&2
      fi
    done <<SCOPES_EOF
$SCOPES
SCOPES_EOF
    # The live sittings on this topic in every store read, this visit included,
    # sorted for the lowest-id tiebreak. A sibling wears the same flaky stamp,
    # so ITS subject is read the shared way.
    SCAN=$(printf '%s' "$UNION" | jq -s -c --arg s "$SUBJECT" --arg t "$TOPIC" --arg v "$VISIT" \
        --arg vp "$VISIT_PREFIX" --arg sp "$SUBJECT_PREFIX" --argjson sk "$SUBJECT_STORE" \
        "$VISIT_IDENTITY_JQ$TOPIC_JQ"'
        def store: split("-")[0];
        [ (add // [])[]
          | select((.metadata.task_kind // "")=="visit")
          | (visit_subject) as $cg
          | select($cg==$s)
          | select(topic($s)==$t)
          | select((.assignee // "")!="")
          | (.id // "") | strings | select(. != "") ]
        + [$v] | unique
        | { holder: (map(select(store == $vp)) | .[0]),
            cross: map(select(store != $vp)),
            misfiled: (if $sk == 1 then map(select(store != $sp)) else [] end) }' 2>/dev/null)
    if [ "$OWN_RIGS" -ne 1 ] || [ "$OWN_READ" -ne 1 ]; then
      # A holder can only be a visit in this one's own store, and that store did
      # not read (or no single rig carries its prefix), so nothing proves who
      # holds the sitting. Hold rather than fold.
      echo "converse-fold: no single readable store carries $VISIT's prefix '$VISIT_PREFIX', so no holder can be proven; hold, do not fold" >&2
      HOLDER=""
    else
      HOLDER=$(printf '%s' "$SCAN" | jq -r '.holder // empty' 2>/dev/null)
    fi
    printf '%s' "$SCAN" | jq -r '.cross[]?' 2>/dev/null | while IFS= read -r peer; do
      [ -n "$peer" ] || continue
      echo "converse-fold: $peer is a live sitting on $SUBJECT [$TOPIC] in another store; a fold never crosses stores, so it is not this sitting's holder" >&2
    done
    MISFILED=$(printf '%s' "$SCAN" | jq -r '.misfiled // [] | join(" ")' 2>/dev/null)
    if [ -n "$MISFILED" ]; then
      echo "converse-fold: misfiled outside the store of their subject $SUBJECT (prefix '$SUBJECT_PREFIX'): $MISFILED. Nothing that reads that store sees them, merge.sh's PR merge holds included." >&2
    fi
  fi
fi

printf 'SUBJECT=%s\n' "$(shq "$SUBJECT")"
printf 'TOPIC=%s\n' "$(shq "$TOPIC")"
printf 'HOLDER=%s\n' "$(shq "$HOLDER")"
printf 'MISFILED=%s\n' "$(shq "$MISFILED")"
