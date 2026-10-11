#!/usr/bin/env bash
# bd-lib.sh — the guarded reads of the bead store, shared by every script that
# queries it, the one-write create every script files a stamped bead through,
# the metadata read-back that gates handing such a bead on, the close that
# unmakes a bead no reader can find, the validation pass's work order, and the
# gating-PR read the merge and pr-facts arms share. Sourced, never executed.
#
# A caller resolves this file beside itself and sources it, the way
# visit-identity.sh is sourced:
#   # shellcheck source=bd-lib.sh
#   . "${GC_BD_LIB:-$SCRIPT_DIR/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh" >&2; exit 1; }
#
# Every read goes through `gc bd`, never `bd`: `bd` takes its store from the
# ambient environment, so a stale one answers from the wrong store or trips the
# circuit breaker (tools/lint-learned.d/raw-bd-invocation.sh). The JSON is piped
# through `scrub`, which strips the C0 bytes a JSON string may not carry raw —
# one such byte aborts jq on the whole payload. `scrub` is a name resolved at
# call time, so the fenced copy below defines it for these helpers; a sourcing
# script keeps its own `# >>> control-char-scrub` block for its own direct
# scrubs, and the copies stay byte-identical (formula bodies carry no include
# mechanism, so an identical copy is the pack's sharing idiom for that block).

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

# bd_json <gc-bd-args...> — one `gc bd` read as JSON, control chars scrubbed.
bd_json() { gc bd "$@" --json 2>/dev/null | scrub; }

# bd_list memoization — opt-in, off by default.
#
# When GC_RECONCILE_BD_CACHE names a directory, bd_list serves a repeated query
# from a file in it instead of re-hitting the server. The refinery-reconcile
# order turns it on for one pass: it clears the whole cache before every arm,
# invalidates it (bd_cache_clear) at a write it then re-reads in the same arm,
# and removes the directory when the pass ends. The hard max age is the backstop
# for a clear a new arm forgets. When the variable is unset, every branch below
# is skipped and bd_list behaves exactly as it did before.

# Hard upper bound on a cached entry's age, in seconds. An older entry is
# refetched, so a cache a killed pass left on disk cannot answer a later one
# with stale rows.
GC_BD_CACHE_MAX_AGE=90

# _bd_norm_csv <csv> — the comma list sorted, so argument order does not matter.
_bd_norm_csv() { printf '%s' "$1" | tr ',' '\n' | LC_ALL=C sort | paste -sd, -; }

# _bd_cache_key <gc-bd-list-args...> — a stable digest of $PWD and the argument
# list. $PWD is in the key because `gc bd` answers from the store the cwd
# resolves, so two worktrees must not share an entry. A --status CSV is sorted
# first, so `--status=open,closed` and `--status=closed,open` are one entry.
_bd_cache_key() {
  local out="" a prev=""
  for a in "$@"; do
    case "$a" in
      --status=*) out="$out --status=$(_bd_norm_csv "${a#--status=}")" ;;
      *)
        if [ "$prev" = "--status" ]; then
          out="$out $(_bd_norm_csv "$a")"
        else
          out="$out $a"
        fi ;;
    esac
    prev="$a"
  done
  printf '%s\n%s' "$PWD" "$out" | sha256sum | cut -d' ' -f1
}

# _bd_cache_mtime <file> — epoch mtime, portable across GNU and BSD stat.
_bd_cache_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || printf '0'; }

# bd_cache_clear — drop every cached entry. A no-op when the cache is off or its
# directory is gone. Whole-directory, not per-key: a write that changes one
# anchor's rows also changes the enumerations and title probes keyed separately,
# and a pass issues few enough writes that clearing all of them costs nothing.
bd_cache_clear() {
  [ -n "${GC_RECONCILE_BD_CACHE:-}" ] && [ -d "${GC_RECONCILE_BD_CACHE}" ] || return 0
  find "$GC_RECONCILE_BD_CACHE" -mindepth 1 -maxdepth 1 -type f -delete 2>/dev/null || true
  return 0
}

# bd_list <gc-bd-list-args...> — a guarded array read. --limit=0 so a
# client-side filter sees every row; a non-zero exit or a non-array (an errored
# ledger) returns non-zero without printing, so a caller reads "could not tell"
# rather than an empty "none". stdin is /dev/null so a `gc bd list` inside a
# `while read` loop cannot consume the loop's own driving input.
#
# With GC_RECONCILE_BD_CACHE set, a fresh entry for this ($PWD, args) is served
# verbatim and a validated result is stored. Only a rc=0 JSON array is ever
# cached, so the "could not tell" contract is unchanged: a server error is never
# served and never stored.
bd_list() {
  local raw rc cache_file="" cached age
  if [ -n "${GC_RECONCILE_BD_CACHE:-}" ] && [ -d "${GC_RECONCILE_BD_CACHE}" ]; then
    cache_file="$GC_RECONCILE_BD_CACHE/$(_bd_cache_key "$@").json"
    if [ -f "$cache_file" ]; then
      age=$(( $(date +%s) - $(_bd_cache_mtime "$cache_file") ))
      if [ "$age" -ge 0 ] && [ "$age" -le "$GC_BD_CACHE_MAX_AGE" ]; then
        cached=$(cat "$cache_file" 2>/dev/null) && { printf '%s' "$cached"; return 0; }
      fi
    fi
  fi
  raw=$(gc bd list "$@" --limit=0 --json </dev/null 2>/dev/null); rc=$?
  [ "$rc" -eq 0 ] && [ -n "$raw" ] || return 1
  raw=$(printf '%s' "$raw" | scrub)
  printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  if [ -n "$cache_file" ]; then
    printf '%s' "$raw" > "$cache_file.$$.tmp" 2>/dev/null \
      && mv -f "$cache_file.$$.tmp" "$cache_file" 2>/dev/null \
      || rm -f "$cache_file.$$.tmp" 2>/dev/null
  fi
  printf '%s' "$raw"
}

# bd_live_children — the live beads hung on each anchor through anchor_bead:
# its reviews, validation passes, findings, rework children and visits, in one
# read of the store. Prints one line per anchor that has any:
#   <anchor>\t<child ids, sorted, comma-joined>\t<1 when one is a rework child, else 0>
# A walking arm compares the id list with what it saw at its last visit, so a
# child that opened or closed since then shows without a read per anchor.
# Non-zero without output = the store did not answer.
bd_live_children() {
  local rows
  rows=$(bd_list --status=open,in_progress,blocked,deferred,hooked,pinned \
           --has-metadata-key anchor_bead) || return 1
  printf '%s' "$rows" | jq -r '
    [ .[] | { a: ((.metadata.anchor_bead // "") | tostring), id: ((.id // "") | tostring),
              rw: (((.metadata.task_kind // "") | tostring) == "rework") }
          | select(.a != "" and .id != "") ]
    | group_by(.a)[]
    | [ .[0].a, (map(.id) | sort | join(",")), (if any(.[]; .rw) then "1" else "0" end) ]
    | @tsv' 2>/dev/null
}

# bd_create [--select <keys>] <metadata-json> <gc-bd-create-args...> — file one
# bead with its metadata in the same write, and print its id.
#
# The metadata a bead is born with is what its readers select it by: its
# task_kind, the anchor it hangs on, the key its producer dedups on. Written in
# a second `update --set-metadata`, it is missing whenever that write fails or
# the create's id never comes back. No reader can see such a bead, so nothing
# closes it, and the producer's next run files a stamped twin beside it.
# `gc bd create --metadata` lands the payload in the bead's own row insert, so
# the bead exists with its metadata or not at all.
#
# <metadata-json> must be a JSON object with at least one key. Anything else is
# refused before a create runs, so this helper never files a bead with no
# metadata. The other arguments are `gc bd create`'s own: the title, -t, -d or
# --body-file - (stdin reaches the create), --status, --notes, --db and the
# rest. The helper adds --metadata and --json.
#
# The bead is read back from the store the create wrote, and every key must
# read back with the value written. A bead short of a key is written the whole
# payload once more and read back again (bd_meta_ensure). Nobody can have taken
# a bead this call has only just filed, so that write lands on no one's work.
#
# --select names, comma-joined, the payload keys the caller's own probe finds
# the bead by, and the caller keeps that list beside the probe. A bead still
# short of one of them after the second write is one no later run can find,
# while an edge it carries can still hold its anchor, so it is closed
# (bd_unmake) and reported as nothing filed. With no --select, a bead is closed
# only when it is still short of every key. A --select key the payload does not
# carry is refused before a create runs.
#
# Returns:
#   0  filed, and every key read back. Prints the id.
#   1  nothing a reader can find was filed. Either the payload or --select was
#      refused, or bd refused the create (its reason goes to stderr), or no id
#      came back, or the bead stayed short of a --select key, or of every key,
#      and was closed (gc.outcome=abandoned) so that no reader meets it. A
#      create whose reply was lost can still have landed whole, so a caller
#      that files again first looks for the bead the way its own dedup does.
#   2  filed, but the read-back could not be made or did not show every key as
#      written. Prints the id. The bead carries every --select key, or some key
#      with no --select, so the caller's next run can find it, and a caller
#      hands it on only once bd_meta_ensure has made it whole.
bd_create() {
  local sel="" meta db="" prev="" a reply id row got short lost="" err
  if [ "${1:-}" = "--select" ]; then sel="${2:-}"; shift 2 || true; fi
  meta="${1:-}"
  shift || true
  printf '%s' "$meta" | jq -e 'type == "object" and length > 0' >/dev/null 2>&1 \
    || { echo "bd_create: refusing to file a bead without a metadata object; nothing filed" >&2; return 1; }
  meta=$(printf '%s' "$meta" | jq -c . 2>/dev/null) \
    || { echo "bd_create: could not normalize the metadata payload; nothing filed" >&2; return 1; }
  if [ -n "$sel" ] && ! printf '%s' "$meta" | jq -e --arg s "$sel" \
       '. as $m | ($s | split(",")) | all(.[]; . as $k | $m | has($k))' >/dev/null 2>&1; then
    echo "bd_create: --select '$sel' names a key the payload does not carry; nothing filed" >&2
    return 1
  fi
  # The read-back, the second write and the close go to the store the create
  # wrote.
  for a in "$@"; do
    [ "$prev" = "--db" ] && db="$a"
    case "$a" in --db=*) db="${a#--db=}" ;; esac
    prev="$a"
  done
  reply=$(gc bd create "$@" --metadata "$meta" --json 2>/dev/null | scrub)
  bd_cache_clear
  id=$(printf '%s' "$reply" | jq -r 'if type == "array" then (.[0].id // empty) else (.id // empty) end' 2>/dev/null)
  if [ -z "$id" ] || [ "$id" = "null" ]; then
    err=$(printf '%s' "$reply" | jq -r 'if type == "object" then (.error // empty) else empty end' 2>/dev/null)
    echo "bd_create: bd create returned no id${err:+: $err}" >&2
    return 1
  fi
  row=$(bd_json show "$id" ${db:+--db "$db"} </dev/null)
  got=$(bd_meta_judge "$id" "$meta" "$row")
  [ "${got%%$'\t'*}" = landed ] && { printf '%s\n' "$id"; return 0; }
  if short=$(bd_meta_ensure --row "$row" "$id" "$meta" ${db:+--db "$db"}); then
    printf '%s\n' "$id"
    return 0
  fi
  if [ "$short" != unreadable ]; then
    if [ -n "$sel" ]; then
      lost=$(jq -rn --arg s "$sel" --arg q "$short" \
        '($q | split(",")) as $q | [ $s | split(",")[] | select(. as $k | any($q[]; . == $k)) ] | join(",")' 2>/dev/null)
    elif [ "$short" = "$(printf '%s' "$meta" | jq -r 'keys_unsorted | join(",")' 2>/dev/null)" ]; then
      lost="$short"
    fi
  fi
  if [ -n "$lost" ]; then
    if bd_unmake "$id" "Unmade by bd_create: this bead did not read back carrying $lost, which its producer finds it by, so no reader could find it. Its producer files it afresh." ${db:+--db "$db"}; then
      echo "bd_create: $id did not read back carrying $lost, so no reader could find it; closed it, nothing filed" >&2
    else
      echo "bd_create: $id did not read back carrying $lost, so no reader can find it, and it would not close; whatever its edges hold stays held until it is closed by hand" >&2
    fi
    return 1
  fi
  echo "bd_create: $id was filed but its metadata did not read back as written (short: $short)" >&2
  printf '%s\n' "$id"
  return 2
}

# bd_meta_judge <id> <metadata-json> <show-json> — how a bead carries a metadata
# payload, judged from a `gc bd show --json` reply the caller already holds, with
# no read of its own. Prints one line: a verdict, a tab, and the payload's keys
# that do not read back with the value written, comma-joined.
#   landed      every key reads back as written
#   bare        the bead carries none of the payload's keys
#   partial     some key is missing, or reads back with another value
#   unreadable  the reply does not hold the bead
# A value compares as its text, jq's tostring of it, because bd keeps a create's
# string values as strings while a --set-metadata write of the same key can
# store a number, a boolean or null. So "42" matches 42 and "false" matches
# false, while false, null and the empty string each match only themselves.
bd_meta_judge() {
  local id="${1:-}" meta="${2:-}" row="${3:-}" out
  out=$(printf '%s' "$row" | jq -r --arg id "$id" --argjson m "$meta" '
    if type == "array" and ((.[0].id // "") == $id) then
      ((.[0].metadata // {}) | if type == "object" then . else {} end) as $got
      | [ $m | to_entries[] | . as $e
          | select((($got | has($e.key))
                    and (($got[$e.key] | tostring) == ($e.value | tostring))) | not)
          | .key ] as $short
      | (if ($short | length) == 0 then "landed"
         elif ($m | keys | all(.[]; . as $k | ($got | has($k)) | not)) then "bare"
         else "partial" end) + "\t" + ($short | join(","))
    else "unreadable\t" end' 2>/dev/null)
  if [ -n "$out" ]; then printf '%s\n' "$out"; else printf 'unreadable\t\n'; fi
}

# bd_meta_readback <id> <metadata-json> [gc-bd-args...] — bd_meta_judge on a
# fresh read of the bead. The trailing arguments reach `gc bd show`, so the read
# follows the --db a write named.
bd_meta_readback() {
  local id="${1:-}" meta="${2:-}"
  shift 2 || true
  bd_meta_judge "$id" "$meta" "$(bd_json show "$id" "$@" </dev/null)"
}

# bd_meta_ensure [--row <show-json>] <id> <metadata-json> [gc-bd-args...] — make
# a bead that already exists carry a payload before its caller hands it on. The
# payload is judged against the bead: against --row, a `gc bd show --json` reply
# the caller already read, or else against a fresh read. When any key is short,
# every key is written in one update and read back again. Returns 0 once every
# key reads back as written. Otherwise prints the keys still short,
# comma-joined, or "unreadable" when the bead itself did not read back, and
# returns 1. A bead that does not read back before the write is not written:
# nothing then shows who holds it. The trailing arguments reach the read, the
# write and the read-back alike, so a --db sends all three to that store.
#
# A route or a sling makes a bead someone's work order, so a caller gates that
# act on this check and not on the exit of the write that filed the bead:
# bd_create prints the id of a bead whose read-back fell short (its rc 2), and
# `gc bd update` can exit 0 without writing. The write ignores bd's claim guard,
# so a caller runs this only on a bead nobody has taken.
bd_meta_ensure() {
  local row="" seen="" id meta got kv sets=()
  if [ "${1:-}" = "--row" ]; then row="${2:-}"; seen=1; shift 2 || true; fi
  id="${1:-}"; meta="${2:-}"
  shift 2 || true
  if [ -n "$seen" ]; then got=$(bd_meta_judge "$id" "$meta" "$row")
  else got=$(bd_meta_readback "$id" "$meta" "$@"); fi
  case "${got%%$'\t'*}" in
    landed) return 0 ;;
    unreadable) printf 'unreadable\n'; return 1 ;;
  esac
  while IFS= read -r -d '' kv; do
    sets+=(--set-metadata "$kv")
  done < <(printf '%s' "$meta" | jq -j 'to_entries[] | "\(.key)=\(.value | if type == "string" then . else tojson end)\u0000"' 2>/dev/null)
  if [ "${#sets[@]}" -gt 0 ]; then
    gc bd update "$id" "$@" "${sets[@]}" </dev/null >/dev/null 2>&1 || true
    bd_cache_clear
    got=$(bd_meta_readback "$id" "$meta" "$@")
    [ "${got%%$'\t'*}" = landed ] && return 0
  fi
  if [ "${got%%$'\t'*}" = unreadable ]; then printf 'unreadable\n'; else printf '%s\n' "${got#*$'\t'}"; fi
  return 1
}

# bd_unmake <id> <note> [gc-bd-args...] — close a bead its producer filed but no
# reader can find, so that nothing it carries holds anything. The close carries
# gc.outcome=abandoned and appends <note>, which names who unmade it and why.
# The trailing arguments reach the close and its read-back, so a --db sends both
# to that store. Returns 0 once the bead reads back closed, 1 otherwise: the
# update's exit cannot say, because `gc bd update` can exit 0 without writing.
bd_unmake() {
  local id="${1:-}" note="${2:-}" st
  shift 2 || true
  gc bd update "$id" "$@" --status=closed --set-metadata gc.outcome=abandoned --append-notes "$note" \
    </dev/null >/dev/null 2>&1 || true
  bd_cache_clear
  st=$(bd_json show "$id" "$@" </dev/null | jq -r --arg id "$id" '
    if type == "array" and ((.[0].id // "") == $id)
    then ((.[0].status // "") | tostring | ascii_downcase) else "" end' 2>/dev/null)
  [ "$st" = closed ]
}

# bd_unmake_orphans <select-keys> <title> <note> [gc-bd-args...] — close what a
# producer that stamped a bead in a second write after its create left behind:
# an open bead with that producer's <title> in its own, which nobody has taken
# (no assignee, no route, no pour) and which is short of a key in
# <select-keys>, the comma-joined keys the producer's probe finds its beads by.
# No probe can find such a bead, yet a blocks edge it carries still holds its
# anchor, and the producer files a whole bead beside it. bd_create never leaves
# one, so this finds only beads filed the older way. Each is closed through
# bd_unmake and its id printed. Returns 1 when the listing did not answer, else
# 0. The trailing arguments reach the listing and the closes.
bd_unmake_orphans() {
  local sel="${1:-}" title="${2:-}" note="${3:-}" rows oid
  shift 3 || true
  rows=$(bd_list --status=open --title-contains "$title" "$@") || return 1
  while IFS= read -r oid; do
    [ -n "$oid" ] || continue
    bd_unmake "$oid" "$note" "$@" && printf '%s\n' "$oid"
  done < <(printf '%s' "$rows" | jq -r --arg s "$sel" --arg t "$title" '
    ($s | split(",")) as $sel
    | .[]
    | select(((.status // "") | tostring | ascii_downcase) == "open")
    | select(((.title // "") | tostring) | contains($t))
    | select(((.assignee // "") | tostring) == "")
    | ((.metadata // {}) | if type == "object" then . else {} end) as $m
    | select((($m["gc.routed_to"] // "") | tostring) == "")
    | select((($m["gc.execution_routed_to"] // "") | tostring) == "")
    | select(any($sel[]; (($m[.] // "") | tostring) == ""))
    | .id' 2>/dev/null)
  return 0
}

# The keys a validation pass is found by: signoff.sh's machine-lane probe and
# pr-facts.sh's human-lane probe both select a pass by its task_kind, its anchor
# and its lane, so a pass short of one of them is one neither can find.
# shellcheck disable=SC2034  # read by the scripts that source this file
VALIDATION_SELECT="task_kind,anchor_bead,check_name"

# validation_work_order <anchor> <lane> <reviewed-oid> — the metadata a
# validation pass carries, the shape mol-validate reads. task_kind, anchor_bead
# and check_name are VALIDATION_SELECT. check_name is the lane: mol-validate
# rules the findings whose finding.lane matches it. reviewed_oid pins the head
# the batch was produced at, which mol-validate needs to back a machine lane; an
# empty <reviewed-oid> leaves the pin out.
validation_work_order() {
  jq -nc --arg a "${1:-}" --arg l "${2:-}" --arg o "${3:-}" \
    '{task_kind: "validation", anchor_bead: $a, check_name: $l}
     + (if $o == "" then {} else {reviewed_oid: $o} end)' 2>/dev/null
}

# The gating-PR read. The merge arm (merge.sh) and the pr-facts arm
# (pr-facts.sh) both read each gating PR and decide on its merge state, so they
# read it with one field set and the two arms see the same facts.
# gh_pr_view_settled re-reads a PR whose merge state answered UNKNOWN, and
# merge.sh calls it before it judges a candidate's merge state.

# The pinned read's field set. pr-facts.sh asks for it plus labels. A re-read
# asks for the set its pinned read asked for, so the two answers compare field
# for field.
# shellcheck disable=SC2034  # read by the scripts that source this file
PR_FIELDS="state,isDraft,baseRefName,headRefName,headRefOid,headRepository,headRepositoryOwner,isCrossRepository,mergeStateStatus,mergeable,reviewDecision,url"

# GitHub computes a PR's mergeability lazily. The first read after the PR's base
# moves answers UNKNOWN and starts the computation, which finishes within
# seconds, and a PR nobody reads stays UNKNOWN. A re-read that answers a
# computed state decides its PR. One that answers UNKNOWN again spends one of
# the MERGE_STATE_REREADS that one run of the sourcing script gets, and an arm's
# run is one pass. Once they are spent, no PR is re-read for the rest of the run.
# So a computation stalled across the repository costs a pass at most
# MERGE_STATE_REREADS reads that decide nothing, however many PRs answer
# UNKNOWN. A PR's first re-read goes out at once, because its pinned read
# already started the computation, and each later one waits
# MERGE_STATE_REREAD_SECS.
MERGE_STATE_REREADS="${MERGE_STATE_REREADS:-3}"
MERGE_STATE_REREAD_SECS="${MERGE_STATE_REREAD_SECS:-5}"
case "$MERGE_STATE_REREADS" in ''|*[!0-9]*) MERGE_STATE_REREADS=3 ;; esac
case "$MERGE_STATE_REREAD_SECS" in ''|*[!0-9]*) MERGE_STATE_REREAD_SECS=5 ;; esac
MERGE_STATE_REREADS_SPENT=0

# gh_pr_view_settled <pr-number> <repo> <fields> <pinned-json> — read again a PR
# whose pinned read, <pinned-json> asked with --json <fields>, answered an
# UNKNOWN merge state. Sets PR_REREADS to the number of re-reads made, and
# returns:
#   0  a re-read answered a computed state. PR_REREAD_JSON holds that answer and
#      PR_REREAD_STATE its mergeStateStatus.
#   1  the state is still UNKNOWN and the run's re-reads are spent, by this PR's
#      re-reads or, with PR_REREADS=0, by earlier ones.
#   2  a re-read differs from the pinned read in a field other than
#      mergeStateStatus, mergeable and reviewDecision, so the PR changed after
#      the caller judged it. PR_REREAD_CHANGED names each such field with its
#      pinned and re-read values.
#   3  a re-read failed: gh exited non-zero, or printed nothing or something
#      other than a JSON object. That says nothing about the merge state, so it
#      spends nothing and is not reported as UNKNOWN.
# shellcheck disable=SC2034  # the PR_REREAD_* results are the caller's to read
gh_pr_view_settled() {
  local n="$1" repo="$2" fields="$3" pinned="$4" again verdict
  PR_REREADS=0; PR_REREAD_JSON=""; PR_REREAD_STATE=""; PR_REREAD_CHANGED=""
  while [ "$MERGE_STATE_REREADS_SPENT" -lt "$MERGE_STATE_REREADS" ]; do
    [ "$PR_REREADS" -eq 0 ] || sleep "$MERGE_STATE_REREAD_SECS"
    PR_REREADS=$((PR_REREADS + 1))
    again=$(gh pr view "$n" --repo "$repo" --json "$fields" 2>/dev/null) || return 3
    [ -n "$again" ] || return 3
    verdict=$(jq -rn --arg q "'" --argjson a "$pinned" --argjson b "$again" '
      def pinned: del(.mergeStateStatus, .mergeable, .reviewDecision);
      if ($b | type) != "object" then "unreadable"
      else
        [ ([$a, $b] | map(pinned | keys[]) | unique)[] as $k
          | select($a[$k] != $b[$k])
          | "\($k) \($q)\($a[$k] | tostring)\($q) -> \($q)\($b[$k] | tostring)\($q)" ] as $changed
        | if ($changed | length) > 0 then "changed " + ($changed | join(", "))
          else "state " + (($b.mergeStateStatus // "") | tostring) end
      end' 2>/dev/null) || return 3
    case "$verdict" in
      "changed "*) PR_REREAD_CHANGED="${verdict#changed }"; return 2 ;;
      "state "|"state UNKNOWN") MERGE_STATE_REREADS_SPENT=$((MERGE_STATE_REREADS_SPENT + 1)) ;;
      "state "*) PR_REREAD_JSON="$again"; PR_REREAD_STATE="${verdict#state }"; return 0 ;;
      *) return 3 ;;
    esac
  done
  return 1
}
