#!/usr/bin/env bash
# finding-anchor — resolve the ONE open bead that tracks a recurring patrol
# finding, minting it if it does not exist yet (tk-mvc72).
#
# WHY THIS EXISTS. `escalation-gate.sh` ends escalation storms by stamping the
# bead an escalation is ABOUT, so a situation that stays true is mailed once
# instead of once per patrol cycle. That works for the witness and the refinery
# because their escalations are always about a bead already: an anchor, a work
# item, a PR's gating anchor. The deacon's are not. Its findings are about a
# DATABASE ("lx has no restorable backup") or a doctor check ("dolt-noms-size"),
# and there is no bead in the ledger with that name — so the deacon had nothing
# to pass as `--anchor` and went on mailing bare.
#
# It mailed NINE identical HIGH escalations for one already-tracked finding in a
# single day (2026-08-02, lx-9d6me): lx-wisp-zpf4p, h5bh9, br7jp, czs3b, ssui3,
# vrjp7, dbi56, 4v4zz, 48x69. Same sentence nine times, differing only in an age
# that ticked up. A mayor nudge asking it to stop did not stop it, which is the
# whole argument for this being code rather than a line of prose in a formula.
#
# THE COST IS BURIAL, NOT VOLUME. In the middle of those nine, the same patrol
# emitted `dolt-noms-size: lx 2.24 GB, largest of 5` — a third independent
# symptom of the same root cause and the most useful datapoint of the cycle. It
# arrived in its own mail, between duplicates, and was nearly lost. Under- and
# over-signalling fail identically: a real finding does not get read. The mayor
# re-confirmed the shape on 2026-08-24 with 26 messages in one cycle, ~6 of them
# re-escalations of already-tracked findings, dolt-noms-size again among them.
#
# WHY THE LOOKUP IS AN EXACT METADATA MATCH AND NEVER `bd search`. This is the
# constraint the mayor measured before it could defeat the fix, and it is the
# reason this script exists as a script rather than as three lines of formula
# prose telling an agent to "grep open beads first". `bd search` matches a
# CONTIGUOUS SUBSTRING of title/description, not tokens. Measured in
# rigs/gascity:
#
#     bd search "backup"                      -> gc-17rl4 gc-b1n7a gc-ltbm5
#     bd search "bd-backup"                   -> gc-b1n7a gc-ltbm5
#     bd search "bd-backup-freshness labels"  -> gc-b1n7a   (exact substring)
#     bd search "backup freshness"            -> (none)  text is "bd-backup-freshness"
#     bd search "embedded-store backup"       -> (none)  title has "embedded-store',"
#
# So a multi-word natural-language dedupe query returns ZERO for beads that
# plainly cover the finding, and the patrol then reports "no open bead in any
# store matches" in perfect good faith and escalates anyway. That happened live
# (lx-wisp-rxmg, lx-wisp-qwjr): both declared bd-backup-freshness untracked while
# gc-b1n7a AND gc-ltbm5 were open — gc-ltbm5 being itself a stop-re-escalating
# tracker filed for exactly this purpose. A duplicate (gc-woe2r) was filed on
# that false signal before anyone caught it.
#
# The key is therefore the finding's OWN NAME, verbatim, as a single token, in a
# metadata field. It is always present in the finding, it is stable across
# cycles, and it is what tracker beads already carry. It is never composed out of
# prose from the message text — that is the query shape proven above to miss.
#
# WHY A BEAD AND NOT A MARKER FILE. The su refinery's existing dedupe writes
# /tmp, and it fails in both directions at once (su-xgz2): it survives a session
# recycle, so a genuinely needed escalation is suppressed, and it dies on reboot,
# so the storm comes back. The state has to live where the state lives.
#
# WHAT THIS SCRIPT DELIBERATELY DOES NOT DO
#
#   It does not mail.        `escalation-gate.sh` decides that. This script only
#                            answers "what bead is this finding about?", which is
#                            the input the gate was missing.
#   It does not close.       A tracker whose condition cleared is closed by
#                            whoever fixed it, the same as any other bead.
#   It does not append per   The condition is re-observed every cycle, so an
#   cycle.                   append-per-tick is the same write amplification one
#                            layer down — a Dolt commit per tick instead of a
#                            mail per tick. The escalation trail lives in the
#                            gate's stamp, which is a single overwritten value.
#
# EXIT STATUS — 2 IS NOT 0, AND THE CALLER MUST NOT ESCALATE ON IT
#
#   0   an id was printed on stdout; use it as `--anchor`
#   2   INDETERMINATE — the ledger could not be read, or the mint failed. There
#       is no anchor, so there is nowhere to record that we escalated, so the
#       caller must NOT fall back to a bare `gc mail send`: that is precisely the
#       unbounded storm this exists to stop. Log it and let the next cycle retry.
#
# An unreadable ledger is NOT an empty one. Minting on a failed read is how a
# single transient error becomes a duplicate tracker every cycle, so a read that
# fails returns 2 rather than falling through to the mint.

set -uo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: finding-anchor.sh <finding-name> --title <title> [--key <metadata-key>]
                         [--body <body>] [--pool <route>] [--label <label>]

  <finding-name>  the finding's own name, verbatim, as a single token
                  (e.g. dolt-noms-size, dolt-backup-manifest:lx). This is the
                  dedupe key; never compose it out of prose.
  --title         title for the bead if one has to be minted (required)
  --key           metadata field holding the finding name.
                  Default "finding_key". Pass "doctor_check" for a `gc doctor`
                  finding, so this converges on the SAME bead that
                  doctor-finding-gate.sh mints and reads.
  --body          description for the bead if one has to be minted
  --pool          gc.routed_to value for a minted bead
  --label         label to add to a minted bead (repeatable)

Prints the bead id on stdout and exits 0. Exits 2 if it could not determine one.
USAGE
}

FINDING=""
TITLE=""
KEY="finding_key"
BODY=""
POOL=""
LABELS=()

# A flag whose value is missing EATS THE NEXT FLAG: `--title --pool p` would
# otherwise store "--pool" as the title and mint a bead named after a flag. Every
# value-taking option is checked the same way, before it consumes anything.
require_value() {
  if [ "$#" -lt 2 ] || case "$2" in --*) true ;; *) false ;; esac; then
    echo "finding-anchor: $1 requires a value" >&2
    return 1
  fi
  return 0
}

FINDING="${1:-}"
case "$FINDING" in
  ""|-h|--help|--*) usage; exit 2 ;;
esac
shift

while [ $# -gt 0 ]; do
  case "$1" in
    --title) require_value "$@" || exit 2; TITLE="$2"; shift 2 ;;
    --key)   require_value "$@" || exit 2; KEY="$2";   shift 2 ;;
    --body)  require_value "$@" || exit 2; BODY="$2";  shift 2 ;;
    --pool)  require_value "$@" || exit 2; POOL="$2";  shift 2 ;;
    --label) require_value "$@" || exit 2; LABELS+=("$2"); shift 2 ;;
    -h|--help) usage; exit 2 ;;
    *) echo "finding-anchor: unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done

if [ -z "$TITLE" ]; then
  echo "finding-anchor: --title is required (it is what a minted bead is called)" >&2
  exit 2
fi

# The key becomes the left side of `--set-metadata "<key>=<value>"`, so a key
# carrying '=' would split the pair at the wrong place and stamp a field nothing
# ever reads back — a tracker that is invisible to its own lookup, i.e. a fresh
# mint every cycle. Hyphens are rejected for the same reason escalation-gate
# rejects them in --kind: bd metadata keys do not accept them (tk-cp6of).
case "$KEY" in
  *[!A-Za-z0-9._]*|"")
    echo "finding-anchor: --key must be non-empty and contain only [A-Za-z0-9._] (got '$KEY')" >&2
    exit 2 ;;
esac

# The finding name is a metadata VALUE and the whole dedupe turns on it round-
# tripping byte-identically. Whitespace is the one class that does not: it is
# what a prose-composed key looks like, and it is exactly what the mayor's
# measurement above proves must never become the key.
case "$FINDING" in
  *[[:space:]]*)
    echo "finding-anchor: the finding name must be a single token with no whitespace (got '$FINDING'); use the finding's own name field verbatim, never a phrase composed from its message" >&2
    exit 2 ;;
esac

command -v jq >/dev/null 2>&1 || {
  echo "finding-anchor: jq is not on PATH; cannot read the ledger" >&2
  exit 2
}

# THE LOOKUP.
#
# ONE comma-separated --status, never repeated flags: `bd list` silently keeps
# only the LAST -s/--status it is given, so `--status=open --status=in_progress`
# is an in_progress-only query wearing the look of a union — and the `open`
# tracker it cannot see is the common case.
#
# Every non-closed status counts, not just `open`: a tracker a pool has CLAIMED
# is in_progress, and a second one minted beside it is the duplicate this lookup
# exists to prevent.
#
# `tr -d` strips control characters BEFORE jq: bead notes carry raw escapes from
# prose, and one of those kills the parse. Losing the parse must never look like
# losing the tracker — that would mint a duplicate AND escalate on it.
RAW=$(gc bd list --status=open,in_progress,blocked \
        --metadata-field "$KEY=$FINDING" --limit=20 --json 2>/dev/null \
      | tr -d '\000-\010\013\014\016-\037')

if [ -z "$RAW" ]; then
  echo "finding-anchor: could not read the ledger for $KEY=$FINDING; NOT minting (a failed read is not an empty one) and NOT answering — retry next cycle" >&2
  exit 2
fi
if ! printf '%s' "$RAW" | jq -e 'type == "array"' >/dev/null 2>&1; then
  echo "finding-anchor: ledger query for $KEY=$FINDING did not return a JSON array; NOT minting — retry next cycle" >&2
  exit 2
fi

EXISTING=$(printf '%s' "$RAW" | jq -r '.[0].id // empty' 2>/dev/null)
if [ -n "$EXISTING" ]; then
  printf '%s\n' "$EXISTING"
  exit 0
fi

# THE MINT. Reached only on a ledger that was read successfully and holds no live
# tracker for this finding.
if [ -z "$BODY" ]; then
  BODY="Filed mechanically by the patrol escalation gate (assets/scripts/finding-anchor.sh, tk-mvc72)
because \`$KEY=$FINDING\` had no open bead tracking it.

This bead is the anchor the escalation is recorded against: escalation-gate.sh
stamps it, so this finding is mailed once per distinct situation instead of once
per patrol cycle. Close it when the condition is actually fixed — while it is
open, it is what keeps the patrol quiet about a finding somebody already knows."
fi

ID=$(printf '%s' "$BODY" \
     | gc bd create "$TITLE" -t task --body-file - --json 2>/dev/null \
     | jq -r '.id // .[0].id // empty' 2>/dev/null)
# A title-only bead is a degraded but honest tracker; a MISSING one leaves the
# caller with no anchor at all.
if [ -z "$ID" ]; then
  ID=$(gc bd create "$TITLE" -t task --json 2>/dev/null \
       | jq -r '.id // .[0].id // empty' 2>/dev/null)
fi
if [ -z "$ID" ]; then
  echo "finding-anchor: could not mint a tracker for $KEY=$FINDING; NOT answering — retry next cycle" >&2
  exit 2
fi

# Built as an ARRAY, not as `${var:+--set-metadata "k=$v"}`. That expansion is
# word-split AFTER substitution and its inner quotes are never re-processed, so
# the optional flags would arrive carrying literal `"` characters in their values
# — a route stamped as `"gc-toolkit/gc-toolkit.polecat"` matches no pool.
META=(--set-metadata "$KEY=$FINDING")
[ -z "$POOL" ] || META+=(--set-metadata "gc.routed_to=$POOL")
for l in ${LABELS[@]+"${LABELS[@]}"}; do
  META+=(--label "$l")
done

# THE STAMP IS THE TRACKER. A bead minted without it is invisible to the very
# lookup above, so the next cycle mints another one, and the storm returns as a
# bead storm. If it cannot be written, say so and answer INDETERMINATE rather
# than handing back an id that will not dedupe anything.
if ! gc bd update "$ID" "${META[@]}" >/dev/null 2>&1; then
  echo "finding-anchor: minted $ID but could not stamp $KEY=$FINDING on it; it will not dedupe and must not be used as an anchor. Stamp it by hand: gc bd update $ID --set-metadata $KEY=$FINDING" >&2
  exit 2
fi

printf '%s\n' "$ID"
exit 0
