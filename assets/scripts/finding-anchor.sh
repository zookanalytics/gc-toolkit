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
# WHY THE LOOKUP LEADS WITH AN EXACT METADATA MATCH, NEVER A PROSE `bd search`.
# This is the constraint the mayor measured before it could defeat the fix, and
# it is the reason this script exists as a script rather than as three lines of
# formula prose telling an agent to "grep open beads first". `bd search` matches
# a CONTIGUOUS SUBSTRING, not tokens. Measured in rigs/gascity:
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
# cycles, and it is never composed out of prose from the message text — that is
# the query shape proven above to miss.
#
# WHAT THAT KEY DOES NOT COVER, AND THE TWO TIERS THAT FOLLOW FROM IT. A stamp
# only exists on beads minted since this script did. Every tracker filed before
# it is title-only — gc-b1n7a and gc-ltbm5 are open, track bd-backup-freshness,
# and carry neither finding_key nor doctor_check — so an exact-match-only lookup
# reads metadata absence as tracker absence and mints a third beside two live
# ones. And `bd` answers for ONE store, while these findings name databases and
# doctor checks belonging to no rig: both of those trackers live in rigs/gascity
# and are invisible to the identical query issued from rigs/gc-toolkit.
#
# So the lookup runs city-wide in two tiers: the exact metadata match in every
# store first, and only where that misses everywhere, a search for the SAME
# verbatim token against TITLES, adopting and stamping the oldest live hit. That
# second tier is not the prose query ruled out above — it is the identical single
# token, which the measurements above show hitting where a composed phrase does
# not, and it is reached only after the precise lookup has come back empty. The
# tiers are documented in full at their call sites below.
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
#
# WHY THE SWEEP IS CITY-WIDE AND NOT ONE STORE
#
# `bd` is pinned to a single store by BEADS_DIR, and the deacon patrols the
# whole city. Its findings are about a DATABASE or a doctor check, which belong
# to no rig in particular, while the beads already tracking them were filed
# wherever whoever noticed happened to be standing. Measured 2026-08-24: the two
# open trackers for `bd-backup-freshness` are gc-b1n7a and gc-ltbm5, both in
# rigs/gascity, and the identical `--metadata-field` query issued from
# rigs/gc-toolkit returns neither. A single-store lookup therefore answers
# "untracked" for a finding two open beads are tracking, mints a third, and
# escalates — the storm this script exists to end, wearing the look of a gate.
#
# The HQ/city store is addressed by PATH and the rig stores by NAME, because
# they are not interchangeable: `gc bd --rig` does not accept the HQ rig at all
# (`gc bd: rig "loomington" not found`), and that leg holds the `lx-*` beads
# this bug's own escalation storm was about.
# The AMBIENT store goes first, and that ordering is load-bearing rather than an
# optimisation. `doctor-finding-gate.sh` mints and reads its successors per
# store by design ("at most one open successor per check per store"), so a check
# whose tracker this script minted locally must keep resolving to that same
# local bead — otherwise the two scripts name different beads for one check and
# the convergence `--key doctor_check` exists to provide is lost. Looking here
# first means the sweep changes the answer ONLY when the ambient store has
# nothing, which is exactly the case this fix is about. It is also the fast
# path: the common lookup still costs one query.
STORES=("L:")
ENUM_OK=0
RIGS_JSON=$(gc rig list --json 2>/dev/null | tr -d '\000-\010\013\014\016-\037')
if printf '%s' "$RIGS_JSON" | jq -e '.rigs | type == "array"' >/dev/null 2>&1; then
  ENUM_OK=1
  while IFS='|' read -r r_name r_hq r_path; do
    [ -n "$r_name" ] || continue
    if [ "$r_hq" = "true" ]; then
      [ -n "$r_path" ] && STORES+=("C:$r_path")
    else
      STORES+=("R:$r_name")
    fi
  done <<EOF
$(printf '%s' "$RIGS_JSON" | jq -r '.rigs[]
      | select((.beads // "initialized") == "initialized")
      | [.name, (.hq // false | tostring), (.path // "")]
      | join("|")' 2>/dev/null)
EOF
fi
# A store that could not be READ is not a store with nothing in it. Any leg that
# fails makes "absent from the whole city" unprovable, so the mint is refused
# below rather than run on a partial sweep — the same rule as the single-store
# version, applied to each leg. Losing the rig enumeration itself is the same
# class of failure: fall back to the ambient store so an existing tracker is
# still found, but never mint on what that one store alone could not see.
READ_FAILED=0
if [ "$ENUM_OK" != 1 ] || [ "${#STORES[@]}" -le 1 ]; then
  STORES=("L:")
  READ_FAILED=1
fi

# Route one `bd` invocation at one store. The spec prefix is the addressing
# mode, not decoration: `C:` is a path for the HQ store, `R:` a rig name, `L:`
# the ambient store BEADS_DIR already points at.
bd_store() { # bd_store <spec> <bd args...>
  local spec="$1"; shift
  case "$spec" in
    C:*) gc bd -C "${spec#C:}" "$@" ;;
    R:*) gc bd --rig "${spec#R:}" "$@" ;;
    *)   gc bd "$@" ;;
  esac
}

# Print one store's JSON array, or return 1 for a leg that could not be read.
# An error is not an empty result and the two must never collapse: `gc bd --rig`
# reports an unknown rig as PROSE on stdout with a zero exit, so the array-shape
# assertion — not the exit code — is what separates them. An empty store answers
# `[]`, which is an array and therefore an answer.
store_json() { # store_json <spec> <bd args...>
  local raw
  raw=$(bd_store "$@" 2>/dev/null | tr -d '\000-\010\013\014\016-\037')
  [ -n "$raw" ] || return 1
  printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  printf '%s' "$raw"
  return 0
}

# TIER 1 — the exact metadata match, in every store. This is the authoritative
# lookup and the only one that mints beads carry, so it runs first and alone
# decides the common case.
for spec in ${STORES[@]+"${STORES[@]}"}; do
  RAW=$(store_json "$spec" list --status=open,in_progress,blocked \
          --metadata-field "$KEY=$FINDING" --limit=20 --json) || { READ_FAILED=1; continue; }
  EXISTING=$(printf '%s' "$RAW" | jq -r '.[0].id // empty' 2>/dev/null)
  if [ -n "$EXISTING" ]; then
    printf '%s\n' "$EXISTING"
    exit 0
  fi
done

# TIER 2 — ADOPT A PRE-EXISTING TITLE-TOKEN TRACKER.
#
# Every tracker filed before this script existed is title-only: gc-b1n7a and
# gc-ltbm5 are open, track `bd-backup-freshness`, and carry no finding_key and no
# doctor_check (verified live 2026-08-24). Tier 1 cannot see them, so treating a
# metadata miss as absence mints a duplicate beside two live trackers and mails
# about it — exactly the false "no open bead in any store matches" that filed
# gc-woe2r. Metadata absence is absence of a STAMP, never absence of a TRACKER.
#
# THIS IS NOT THE PROSE QUERY THE HEADER RULES OUT, and the difference is the
# whole reason it is safe. What was measured to fail is a query composed out of a
# finding's MESSAGE — `bd search "backup freshness"` returns nothing for a title
# reading `bd-backup-freshness`, because matching is substring, not token. What
# runs here is the finding's OWN NAME, verbatim, the identical single token tier
# 1 looks up; the header's own measurements show that shape hitting
# (`bd search "bd-backup" -> gc-b1n7a gc-ltbm5`). Nothing is ever composed from
# prose, and this tier is reached only after the exact match has missed
# everywhere.
#
# A CANDIDATE ALREADY CLAIMED BY ANOTHER FINDING IS SKIPPED, and this is not a
# refinement — without it the tier regresses into the storm. Roll-up beads exist:
# lx-0ojcv is open and its title names FOUR findings at once (session-model,
# dolt-noms-size, bd-backup-freshness, pipefail-grep-q). The gate keys its stamp
# `escalated.<kind>` on the ANCHOR, so one anchor holds exactly one deacon
# escalation slot. Two findings sharing that bead do not merely dedupe into one
# notice — they overwrite each other's state fingerprint, each cycle reads the
# other's value as a CHANGED state, and both re-mail forever. So a bead already
# carrying finding_key/doctor_check for a DIFFERENT finding is not adopted; that
# finding mints its own tracker instead, and the roll-up stays the first one's.
#
# `bd search` matches TITLE and ID (its own help: "Text queries search titles"),
# so a bead that merely discusses the finding in its body is not a candidate —
# tk-mvc72 itself names `bd-backup-freshness` in its description and correctly
# does not match. The ID half is the trap: an ID-like query takes a prefix fast
# path, so `bd search "gc-b1n7a"` returns gc-b1n7a whose title holds no such
# token. Adopting that would anchor the escalation on an unrelated bead and MUTE
# the finding, which is worse than the storm. So every candidate is re-checked
# against its own title here, and the fast-path hit is dropped.
#
# Tier 2 runs even when a leg of tier 1 failed: FINDING a tracker is a valid
# answer no matter what else was unreadable, and refusing one that is demonstrably
# open would mute a tracked finding. Only the MINT below needs a complete sweep.
CANDS=""
for spec in ${STORES[@]+"${STORES[@]}"}; do
  RAW=$(store_json "$spec" search "$FINDING" --status open,in_progress,blocked \
          --limit 50 --json) || { READ_FAILED=1; continue; }
  HIT=$(printf '%s' "$RAW" | jq -r --arg f "$FINDING" --arg k "$KEY" '
          [ .[]
            | select(((.title // "") | ascii_downcase)
                     | contains($f | ascii_downcase))
            | select(
                ( [ (.metadata // {}) | .finding_key?, .doctor_check?, .[$k]? ]
                  | map(select(. != null and . != "" and . != $f))
                  | length ) == 0 )
          ]
          | sort_by(.created_at // "")
          | .[0] // empty
          | [(.created_at // ""), .id] | join("|")' 2>/dev/null)
  [ -n "$HIT" ] && CANDS="${CANDS}${HIT}|${spec}
"
done
# Oldest wins, city-wide. The choice has to be DETERMINISTIC, not merely
# reasonable: two open trackers for one finding is the observed state, and a
# rule that picks a different one per cycle re-mails under a new anchor every
# cycle. First-filed is the canonical tracker and sorts stably (created_at is
# RFC3339, so lexical order is chronological order).
BEST=$(printf '%s' "$CANDS" | grep -v '^[[:space:]]*$' | LC_ALL=C sort | head -1)
if [ -n "$BEST" ]; then
  ADOPT_REST=${BEST#*|}
  ADOPT_ID=${ADOPT_REST%%|*}
  ADOPT_SPEC=${ADOPT_REST#*|}
  # Stamp it so tier 1 owns it from the next cycle on. Unlike the mint below,
  # a failed stamp here is NOT fatal and must not be: the bead exists, the
  # title search that just found it is repeatable, and its oldest-first pick is
  # stable — so an unstamped adoption still converges on the same anchor every
  # cycle. A fresh mint has no such second route to itself, which is why that
  # one refuses to answer.
  if ! bd_store "$ADOPT_SPEC" update "$ADOPT_ID" \
         --set-metadata "$KEY=$FINDING" >/dev/null 2>&1; then
    echo "finding-anchor: adopted pre-existing tracker $ADOPT_ID for $KEY=$FINDING but could not stamp it; still usable as an anchor (the title lookup re-finds it), but stamp it to make the lookup exact: gc bd update $ADOPT_ID --set-metadata $KEY=$FINDING" >&2
  fi
  printf '%s\n' "$ADOPT_ID"
  exit 0
fi

# Nothing anywhere — but only a COMPLETE sweep proves that. Minting on a partial
# one is how a single transient error becomes a duplicate tracker every cycle,
# and then an escalation about it.
if [ "$READ_FAILED" != 0 ]; then
  echo "finding-anchor: could not read every store while looking for $KEY=$FINDING; NOT minting (a failed read is not an empty one) and NOT answering — retry next cycle" >&2
  exit 2
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
