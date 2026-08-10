#!/usr/bin/env bash
# doctor-finding-gate — the close-time gate for beads that name a `gc doctor`
# finding (tk-fwspr).
#
# THE FAILURE THIS EXISTS TO END. A bead is filed against a doctor finding, real
# work lands, the PR merges, the bead closes — and the check keeps firing. The
# ledger now says the defect is fixed and the only thing that disagrees is a
# doctor run nobody re-read. Observed three times in one day, on three
# independent findings, each in a different rig:
#
#   check-rig-scoped-orders-bound   tk-gi2pc closed (merged, PR#270); the finding
#                                   still reports "2 order(s)". Its successor
#                                   tk-5cgyk closed too (merged, PR#279) and the
#                                   finding STILL fires.
#   check-base-artifact-collision   gc-xdzml closed; the check still reports
#                                   "skipped — see gc-xdzml", naming the very
#                                   bead that was closed over it.
#   census-owner-liveness           gc-ddvrx closed 18:49Z (merged, PR#109); the
#                                   finding still reports the identical "8
#                                   dangling owner_bead reference(s)". The PR
#                                   improved the CHECK and re-pointed no row.
#
# Every one of them landed REAL work. None of them was a lie about the merge —
# they are lies about the FINDING, and they are produced by the same mechanism:
# the close is driven by the merge (close-on-land), and nothing between the merge
# and the close ever re-runs the check. "Merged" silently becomes "fixed".
#
# The remedy has to be mechanical. The deacon patrol already carries an
# INSTRUCTION to cross-check findings against beads and to treat a closed match
# as "the finding recurred after someone closed it"
# (formulas/mol-deacon-patrol.toml, system-health step) — and all three instances
# happened anyway, because an instruction is only as good as the pass that
# remembers it. This script is that instruction as code.
#
# WHAT IT DOES NOT DO: refuse the close. Under close-on-land `closed` means
# LANDED, and an anchor left open over a merged PR is the false record in the
# more dangerous direction (see reconcile-merged-prs.sh, close_anchor). So the
# gate takes the second arm the mayor's dispatch allowed — close WITH an explicit
# acknowledgement that the close is PARTIAL, and name the successor that carries
# the rest.
#
# SUBCOMMANDS
#   probe <bead-id>
#       Print, one per line, the names of doctor checks this bead names that are
#       STILL FIRING. Exit 0 = none (close is clean), 1 = at least one (close is
#       partial), 2 = indeterminate (say nothing, change nothing).
#
#   successor <check-name> [--pool <pool>] [--source <bead-id>]
#       Print the id of an OPEN bead tracking <check-name>, minting one routed to
#       <pool> if none exists. Convergent: at most one open successor per check
#       per store, because every bead it mints carries metadata.doctor_check and
#       the lookup is keyed on exactly that.
#
#   publish [<file>|-] [--cache <file>]
#       Install a `gc doctor --json` payload (a file, or stdin) at the shared
#       cache path `probe` reads. This is how the gate gets a warm payload
#       WITHOUT any caller paying for a doctor run: the deacon patrol already
#       runs `gc doctor --json` every patrol, and one pipe at the end of that
#       step is what makes the refinery's `--no-run` probe answerable.
#
#       Without it the arm is not degraded, it is INERT: `--no-run` + no cache
#       is INDETERMINATE at every close, forever, and the annotation this whole
#       script exists to produce never fires once. Path resolution lives HERE
#       rather than in the calling formula's prose so the writer and the reader
#       agree by construction — two copies of a four-branch fallback expression,
#       one of them in a doc an agent retypes, is a cache that silently misses.
#
# MATCHING — a bead "names" a check two ways, and the authoritative one is the
# intersection with what doctor ACTUALLY REPORTED, never the shape of the token:
#
#   1. metadata.doctor_check — explicit, comma- or space-separated. The
#      future-friendly hook a filer can set deliberately.
#   2. any whole token in the bead's title/description/notes that equals a
#      reported check name, either in full (`gc-toolkit:check-x`, how pack checks
#      are namespaced) or as the bare suffix (`check-x`).
#
# Rule 2 is deliberately intersected with the live payload rather than matched on
# a `check-*` regex, because prose is full of check-shaped tokens that name no
# check at all: the three instance beads above between them contain `check-name`,
# `check-scope`, and `check-liveness-sweep-wired` (a real check, and GREEN — the
# bead names two checks and only one of them fires). Reporting on shape would cry
# wolf on all three. Reporting on the intersection reports exactly the one that
# is still firing.
#
# It also means the bare-named builtin checks match — `census-owner-liveness`
# carries no `check-` prefix and no namespace, and is indistinguishable from
# ordinary hyphenated prose until the payload says it is a check name. That is
# the third instance above, so this is not a hypothetical class.
#
# THE PAYLOAD, AND WHY THERE IS A CACHE. `gc doctor` has no per-check selector
# (`gc doctor --help`: no --check flag) — the only way to ask whether one check
# fires is to run all ~147 of them, which takes minutes under city load
# (mol-deacon-patrol bounds it at 300s and warns that 120s is not enough). A
# close-time gate cannot pay that per close, so the payload is read, in order,
# from: --json <file>, $GC_DOCTOR_JSON, a fresh cache file, and only then a live
# run. The deacon patrol runs doctor every patrol anyway and now writes that same
# cache, so in a running city the gate is nearly always answering from a payload
# somebody else already paid for.
#
# A live run is attempted ONLY when the bead carries an explicit doctor_check or a
# `check-*`-shaped token, in EITHER shape a check-prefixed name arrives in — the
# bare `check-x` and the namespaced `gc-toolkit:check-x` that pack checks are
# actually reported under. That is the cheap pre-filter that says "there is
# plausibly something here", so a routine close never triggers a doctor run. With
# a warm cache the full intersection runs regardless, which is what gives the
# bare-named builtins their coverage. Cold cache + a check whose name carries no
# `check-` component at all (the bare builtins, `census-owner-liveness`) is the
# one gap, and it closes itself on the next patrol.
#
# FAIL-SOFT, ALWAYS. Every unreadable input — the bead, the payload, the ledger —
# exits 2 and prints nothing. The caller then behaves exactly as it did before
# this gate existed. An annotation that cannot be justified must not be invented:
# a false "still firing" files a successor bead against a defect that is fixed,
# and the whole point of the gate is that the ledger should stop asserting things
# nobody verified.
set -uo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: doctor-finding-gate.sh probe <bead-id> [--json <file>] [--cache <file>]
                                              [--ttl <seconds>] [--no-run]
       doctor-finding-gate.sh successor <check-name> [--pool <pool>]
                                                     [--source <bead-id>]
       doctor-finding-gate.sh publish [<file>|-] [--cache <file>]
USAGE
}

# Where a payload is cached between callers. The deacon patrol writes it; this
# script writes it after any live run of its own. Overridable for tests and for a
# city whose runtime dir is elsewhere.
default_cache() {
  if [ -n "${GC_DOCTOR_GATE_CACHE:-}" ]; then
    printf '%s' "$GC_DOCTOR_GATE_CACHE"
  elif [ -n "${GC_CITY_RUNTIME_DIR:-}" ]; then
    printf '%s' "$GC_CITY_RUNTIME_DIR/doctor-findings.json"
  elif [ -n "${GC_CITY:-}" ]; then
    printf '%s' "$GC_CITY/.gc/runtime/doctor-findings.json"
  else
    printf '%s' "${TMPDIR:-/tmp}/gc-doctor-findings.json"
  fi
}

# Seconds a cached payload stays usable. Long by design: the error a stale
# payload can make is a successor bead filed against a check that has since gone
# green, which a human or the next patrol disposes of in one step. The error a
# SHORT ttl makes is a multi-minute doctor run inside the refinery's idle loop.
DEFAULT_TTL=3600
# Bound on a live run, matching mol-deacon-patrol's own bound. Below ~300s the
# run returns rc 124 and an empty payload, which is indistinguishable from a
# wedged data plane.
DOCTOR_TIMEOUT="${GC_DOCTOR_GATE_TIMEOUT:-300}"

# file_age_seconds <path> — seconds since mtime, or empty if it cannot be read.
# GNU and BSD stat disagree on the flag, and neither is guaranteed here.
file_age_seconds() {
  local f="$1" mtime="" now
  now=$(date +%s 2>/dev/null) || return 1
  mtime=$(stat -c %Y "$f" 2>/dev/null) \
    || mtime=$(stat -f %m "$f" 2>/dev/null) \
    || return 1
  case "$mtime" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$((now - mtime))"
}

# payload_ok <file> — a payload is usable only if it parses AND carries the
# `.results` array. This is mol-deacon-patrol's own schema assertion, and for the
# same reason: `jq '.checks[]'` over a renamed payload returns nothing rather
# than failing, so a drifted schema reads as "every check is green" — the gate
# would then certify every close as clean, silently, which is the exact failure
# it was built to stop.
payload_ok() {
  [ -s "$1" ] || return 1
  jq -e 'type == "object" and (.results | type == "array")' "$1" >/dev/null 2>&1
}

# install_cache <src> <cache> — put a VALIDATED payload at the shared cache path.
# Write beside the target and rename, so no reader can ever observe a partial
# file: a truncated payload still parses, and every check missing from it reads
# as green — the gate would then certify closes it never evaluated, which is the
# precise failure it exists to stop. `mv` within one directory is atomic, which
# is why the temp file is `$cache.$$` and not a `mktemp` somewhere else.
install_cache() {
  local src="$1" cache="$2" dir tmp
  dir=$(dirname "$cache" 2>/dev/null) || return 1
  [ -n "$dir" ] || return 1
  mkdir -p "$dir" 2>/dev/null || return 1
  tmp="$cache.$$"
  if cp "$src" "$tmp" 2>/dev/null && mv -f "$tmp" "$cache" 2>/dev/null; then
    return 0
  fi
  rm -f "$tmp" 2>/dev/null
  return 1
}

cmd_probe() {
  local bead="" json="" cache="" ttl="$DEFAULT_TTL" norun=""
  bead="${1:-}"; shift || true
  [ -n "$bead" ] || { usage; return 2; }
  while [ $# -gt 0 ]; do
    case "$1" in
      --json)  json="${2:-}";  if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
      --cache) cache="${2:-}"; if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
      --ttl)   ttl="${2:-}";   if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
      --no-run) norun=1; shift ;;
      *) shift ;;
    esac
  done
  case "$ttl" in ''|*[!0-9]*) ttl="$DEFAULT_TTL" ;; esac
  [ -n "$cache" ] || cache="$(default_cache)"

  command -v jq >/dev/null 2>&1 || return 2

  # --- the bead, read ONCE. ---------------------------------------------------
  # Control characters are stripped before jq for the same reason every other
  # pass here does it: a note carrying a raw control byte makes `bd show --json`
  # unparseable, and a gate that silently reads nothing certifies the close as
  # clean.
  local row
  row=$(gc bd show "$bead" --json 2>/dev/null | tr -d '\000-\010\013\014\016-\037')
  [ -n "$row" ] || return 2
  jq -e 'type == "array" and length > 0' <<<"$row" >/dev/null 2>&1 || return 2

  # Explicit names first — these are a deliberate declaration and are matched
  # even when doctor never reported a check by that name (a check can stop being
  # REGISTERED, which is not the same as being fixed; the caller still deserves
  # to hear that the bead named something the payload cannot account for). They
  # are, however, only reported when they are actually firing — see the jq below,
  # where an explicit name absent from the payload matches nothing.
  local explicit text
  explicit=$(jq -r '.[0].metadata.doctor_check // "" | tostring' <<<"$row" 2>/dev/null)
  text=$(jq -r '.[0] | [(.title // ""), (.description // ""), (.notes // "")]
                       | map(tostring) | join(" ")' <<<"$row" 2>/dev/null)

  # Normalize both sides to space-delimited tokens over the character class a
  # check name is drawn from ([A-Za-z0-9:_-]). Everything else becomes a
  # separator, so `specs/tk-gi2pc/rig-scoped-order.md` yields three tokens and
  # `"check-x"` in quotes yields one. Whole-token matching is what keeps
  # `check-set` from matching `check-set-heal`.
  local norm
  norm=" $(printf '%s %s' "$text" "$explicit" | tr -c 'A-Za-z0-9:_-' ' ' | tr -s ' ') "

  # --- the cheap pre-filter, and it ONLY decides whether to pay for a run. -----
  # A `check-*`-shaped token or an explicit declaration says "plausibly about a
  # check". It is never used to REPORT — reporting is the payload intersection
  # below — so its false positives cost a lookup, not a finding.
  #
  # BOTH shapes, because a check-prefixed name arrives in two: the bare `check-x`
  # and the namespaced `gc-toolkit:check-x` that pack checks are actually reported
  # under. The intersection below already treats the namespaced form as a check
  # name (it matches in full, or on the bare suffix after the last colon), so a
  # pre-filter that recognized only ` check-` made the two halves of this script
  # disagree about what a check name looks like — and the disagreement failed in
  # the one direction that is invisible. A bead naming nothing but a full
  # namespaced token was NOT plausible, so with a cold cache and `--no-run` the
  # probe fell through to the clean return below instead of the indeterminate one:
  # rc 0, no output, and a refinery close arm that neither annotates the close nor
  # counts it as unevaluated. A namespaced pack-check anchor could close as
  # verified-clean at the exact moment the gate had verified nothing — the
  # silent-inert failure this whole script exists to end.
  #
  # Both patterns still require the `check-` prefix itself, which is what keeps
  # the filter cheap: a token is plausible because a check name begins right
  # there, either at a word boundary or straight after a namespace colon. An
  # ordinary colon token buys nothing — a `18:55Z` timestamp out of a mayor note,
  # a bare `https:` left by a normalized url — so a routine close still pays for
  # no doctor run.
  local plausible=""
  [ -n "$explicit" ] && plausible=1
  [ -z "$plausible" ] && case "$norm" in *" check-"*|*":check-"*) plausible=1 ;; esac

  # --- resolve a payload. ------------------------------------------------------
  local payload="" ran=""
  if [ -n "$json" ]; then
    payload_ok "$json" || return 2
    payload="$json"
  elif [ -n "${GC_DOCTOR_JSON:-}" ] && payload_ok "${GC_DOCTOR_JSON}"; then
    payload="${GC_DOCTOR_JSON}"
  else
    local age
    age=$(file_age_seconds "$cache" 2>/dev/null)
    if [ -n "$age" ] && [ "$age" -le "$ttl" ] && payload_ok "$cache"; then
      payload="$cache"
    elif [ -z "$plausible" ]; then
      # Nothing cached, and nothing about this bead suggests a check to look for.
      # CLEAN, not unknown — and the ordering matters: tested after --no-run, a
      # cold-cache caller would report every routine close as indeterminate and
      # bury the one bead that really did name a check.
      return 0
    elif [ -n "$norun" ]; then
      # Plausible, but this caller may not spend minutes finding out. Say
      # INDETERMINATE rather than clean: a caller that cannot evaluate the gate
      # deserves to know the gate did not run, or the absence of an annotation
      # reads as a verified-clean close.
      return 2
    else
      # The live run. `gc doctor` exits 1 when findings exist — that is the
      # NORMAL case here and must not be read as failure; only the payload's
      # shape decides whether it is usable.
      local tmp
      tmp=$(mktemp 2>/dev/null) || return 2
      timeout "$DOCTOR_TIMEOUT" gc doctor --json >"$tmp" 2>/dev/null
      if payload_ok "$tmp"; then
        payload="$tmp"; ran="$tmp"
        # Publish it for the next caller — the same install the `publish`
        # subcommand performs, through the same function, so a live run and a
        # patrol hand-off cannot disagree about where the cache lives.
        install_cache "$tmp" "$cache" || true
      else
        rm -f "$tmp" 2>/dev/null
        return 2
      fi
    fi
  fi

  # --- intersect. --------------------------------------------------------------
  # A check is FIRING when its status is not one of the settled-green states.
  # Written as an exclusion, not an inclusion of {error,warning}: an unknown
  # future status must read as firing, because the gate's job is to refuse to
  # certify what it cannot verify.
  local matched
  matched=$(jq -r --arg norm "$norm" '
      [ .results[]?
        | select((.name // "") != "")
        | select(((.status // "") | ascii_downcase) as $s
                 | ([ "ok", "pass", "passed", "skipped", "fixed", "n/a", "na" ]
                    | index($s)) | not)
        | .name ]
      | unique
      | map(select(. as $n
            | ($norm | contains(" " + $n + " "))
              or (($n | split(":") | last) as $bare
                  | $bare != $n and ($norm | contains(" " + $bare + " ")))))
      | .[]' "$payload" 2>/dev/null)

  [ -z "$ran" ] || rm -f "$ran" 2>/dev/null

  [ -n "$matched" ] || return 0
  printf '%s\n' "$matched"
  return 1
}

cmd_successor() {
  local check="" pool="" source_bead=""
  check="${1:-}"; shift || true
  [ -n "$check" ] || { usage; return 2; }
  while [ $# -gt 0 ]; do
    case "$1" in
      --pool)   pool="${2:-}";        if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
      --source) source_bead="${2:-}"; if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
      *) shift ;;
    esac
  done
  command -v jq >/dev/null 2>&1 || return 2

  # An OPEN bead already tracking this check. Keyed on the metadata this script
  # stamps, so the lookup is exact — a text search would match the very beads
  # whose closes produced the finding in the first place, and re-"find" a
  # successor that is closed and did not fix it.
  #
  # Every non-closed status counts as a live successor, not just `open`: a
  # successor that a pool has CLAIMED is in_progress, and a second one minted
  # beside it is the duplicate-dispatch this lookup exists to prevent.
  #
  # ONE comma-separated --status, never repeated flags: `bd list` silently keeps
  # only the LAST -s/--status it is given (its own --help says so), so
  # `--status=open --status=in_progress` is an in_progress-only query wearing the
  # look of a union — and the `open` successor it cannot see is the common case.
  local existing raw
  raw=$(gc bd list --status=open,in_progress,blocked \
          --metadata-field "doctor_check=$check" --limit=20 --json 2>/dev/null \
        | tr -d '\000-\010\013\014\016-\037')
  # An unreadable ledger is NOT an empty one. Minting on a failed read is how one
  # transient error becomes a duplicate successor every pass.
  if [ -n "$raw" ]; then
    jq -e 'type == "array"' <<<"$raw" >/dev/null 2>&1 || return 2
    existing=$(jq -r '.[0].id // empty' <<<"$raw" 2>/dev/null)
    if [ -n "$existing" ]; then printf '%s\n' "$existing"; return 0; fi
  else
    return 2
  fi

  local title body id
  title="doctor check $check still fires after its fix bead closed"
  body="$(cat <<EOF
\`gc doctor\` still reports **$check** as a live finding after a bead filed
against it closed. Filed mechanically by the close-time doctor-finding gate
(assets/scripts/doctor-finding-gate.sh, tk-fwspr)${source_bead:+ when $source_bead closed}.

The predecessor's work is not in question — it merged. What is in question is
whether it CLOSED THE FINDING, and doctor says it did not. That gap is the whole
reason this bead exists: three separate findings reached this state on
2026-08-10 (check-rig-scoped-orders-bound, check-base-artifact-collision,
census-owner-liveness) because "merged" was read as "fixed" and nobody re-ran
the check.

## What to do

1. Re-run the check and read its current message and details:
   \`gc doctor --json | jq '.results[] | select(.name == "$check")'\`
2. If it is GREEN now, close this bead — the finding was resolved between the
   predecessor's merge and now, and this bead is a false alarm the gate is
   supposed to produce rather than suppress.
3. If it still fires, fix what it is actually reporting. Read the predecessor's
   diff first: the recurring failure mode is a PR that improves the CHECK
   without remediating the STATE it checks (census-owner-liveness, PR#109).
4. Before closing, re-run the check again. This bead carries
   \`metadata.doctor_check=$check\`, so the gate will annotate its own close the
   same way if the finding outlives it.
EOF
)"
  id=$(printf '%s' "$body" \
       | gc bd create "$title" -t task --body-file - --json 2>/dev/null \
       | jq -r '.id // empty' 2>/dev/null)
  # A title-only bead is a degraded but honest successor; a MISSING one is a
  # close that names a successor that does not exist.
  [ -n "$id" ] || id=$(gc bd create "$title" -t task --json 2>/dev/null \
                       | jq -r '.id // empty' 2>/dev/null)
  [ -n "$id" ] || return 2

  # Built as an ARRAY, not as `${var:+--set-metadata "k=$v"}`. That expansion is
  # word-split AFTER substitution and its inner quotes are never re-processed, so
  # the optional flags would arrive carrying literal `"` characters in their
  # values — a route stamped as `"gc-toolkit/gc-toolkit.polecat"` matches no pool.
  local -a meta=(--set-metadata "doctor_check=$check")
  [ -z "$source_bead" ] || meta+=(--set-metadata "doctor_finding_predecessor=$source_bead")
  [ -z "$pool" ] || meta+=(--set-metadata "gc.routed_to=$pool")
  gc bd update "$id" "${meta[@]}" >/dev/null 2>&1 || true
  printf '%s\n' "$id"
  return 0
}

cmd_publish() {
  local src="" cache=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --cache) cache="${2:-}"; if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
      -) src="-"; shift ;;
      *) [ -n "$src" ] || src="$1"; shift ;;
    esac
  done
  command -v jq >/dev/null 2>&1 || return 2
  [ -n "$cache" ] || cache="$(default_cache)"

  # Buffer first — stdin is not seekable and the validation below has to read the
  # payload before any part of it is allowed near the cache path.
  local tmp rc=2
  tmp=$(mktemp 2>/dev/null) || return 2
  if [ -n "$src" ] && [ "$src" != "-" ]; then
    cat -- "$src" >"$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 2; }
  else
    cat >"$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 2; }
  fi

  # VALIDATE BEFORE INSTALLING, and refuse rather than install something
  # doubtful. The caller is the deacon patrol, whose own doctor run can come back
  # empty (rc 124 at its 300s bound) or schema-drifted after a `gc` upgrade — and
  # its rule for both is "NOT reporting clean". This is that rule at the cache
  # boundary: an empty payload installed here would answer every later probe with
  # "no check is firing", turning a wedged doctor run into a city-wide all-clear.
  # Refusing leaves the previous cache in place and the gate merely INDETERMINATE.
  if payload_ok "$tmp" && install_cache "$tmp" "$cache"; then
    printf '%s\n' "$cache"
    rc=0
  fi
  rm -f "$tmp" 2>/dev/null
  return "$rc"
}

case "${1:-}" in
  probe)     shift; cmd_probe "$@" ;;
  successor) shift; cmd_successor "$@" ;;
  publish)   shift; cmd_publish "$@" ;;
  *) usage; exit 2 ;;
esac
