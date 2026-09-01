#!/usr/bin/env bash
# cutover-2026-08 — one-shot cutover tooling for the 2026-08 rewrite (PR #465).
# DISPOSABLE: delete this script and the runbook once the cutover is done.
# Job: `sweep` performs the ledger surgery the old system left behind, per rig —
# strip deleted healer-bookkeeping keys from open beads, retire pre-rewrite
# graph.v2 molecules (their poured formula text calls deleted scripts), and
# repair pre-cutover closed beads — so check-state-space and
# check-closed-implies-landed pass. `verify` runs the post-restart checks:
# helm build freshness, doctor, order registration, seed-audit note.
# DEFAULT IS DRY-RUN: sweep reports what would change; --apply writes, every
# write is read back, and a second --apply run finds nothing to do.
# Caller: the outside agent following specs/2026-08-rewrite/cutover-runbook.md,
# with the bd data plane up (sweep) / the restarted city up (verify).
# Usage: cutover-2026-08.sh sweep [--apply] [--rig <name>] | verify
# Exit: sweep 0 clean, 1 operator-attention items remain; verify 0 green, 1 not.
set -u

PROG="cutover-2026-08"
SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PACK_DIR="$(cd "$SCRIPTS_DIR/../.." && pwd)"
BOUND="${GC_CUTOVER_TIMEOUT:-60}"

# Keys deleted from the metadata registry along with their healer writers.
HEALER_KEYS="check_set_healed check_set_heal_flagged merge_result_healed \
merge_result_heal_flagged merge_result_pr_state reopened_not_landed \
stranded_branch_flagged stranded_branch_recovered stale_gate_head \
stale_gate_nopool_head stale_base_head anchorless_flagged \
assignee_noncanonical close_failures close_escalated gate_verdict_condemned \
reconcile_rig"
LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"

run_bounded() { if command -v timeout >/dev/null 2>&1; then timeout "$BOUND" "$@" </dev/null; else "$@" </dev/null; fi; }
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

RIG_DB=""
bd_list() { # guarded array read from the current rig store
  local raw rc
  raw=$(run_bounded gc bd list "$@" --json --limit 0 --db "$RIG_DB" 2>/dev/null); rc=$?
  [ "$rc" -eq 0 ] && [ -n "$raw" ] || return 1
  raw=$(printf '%s' "$raw" | scrub)
  printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  printf '%s' "$raw"
}
bd_show() { run_bounded gc bd show "$1" --json --db "$RIG_DB" 2>/dev/null | scrub; }
bd_update() { run_bounded gc bd update "$@" --db "$RIG_DB" >/dev/null 2>&1; }
meta_of() { bd_show "$1" | jq -r --arg k "$2" '.[0].metadata[$k] // ""' 2>/dev/null; }
status_of() { bd_show "$1" | jq -r '.[0].status // ""' 2>/dev/null; }
blocked_now() { # 0 while an open blocker (or an unreadable probe) holds the bead
  local rows
  rows=$(run_bounded gc bd dep list "$1" --direction=down -t blocks --json --db "$RIG_DB" 2>/dev/null | scrub)
  printf '%s' "$rows" | jq -e 'type == "array"' >/dev/null 2>&1 || return 0
  printf '%s' "$rows" | jq -e '[ .[] | select((.status // "open") != "closed") ] | length > 0' >/dev/null 2>&1
}
origin_of() { # <checkout> — host/owner/repo of its origin, empty if unresolvable
  local u r
  u=$(git -C "$1" remote get-url origin 2>/dev/null | tr -d '[:space:]')
  case "$u" in
    git@github.com:*|https://github.com/*|ssh://git@github.com/*)
      r=$(printf '%s' "$u" | sed -e 's#^ssh://git@github.com/##' \
        -e 's#^git@github.com:##' -e 's#^https://github.com/##' -e 's#\.git$##' -e 's#/*$##') ;;
    *) r="" ;;
  esac
  case "$r" in */*/*|/*|*/) r="" ;; */*) : ;; *) r="" ;; esac
  [ -n "$r" ] && printf 'github.com/%s' "$r"
}
url_repo_q() { printf '%s' "${1:-}" | sed -n 's#^[A-Za-z][A-Za-z0-9+.-]*://\([^/][^/]*\)/\([^/][^/]*/[^/][^/]*\)/pull/[0-9].*#\1/\2#p'; }

# ---------------------------------------------------------------- sweep ------
sweep() {
  local APPLY=0 ONLY_RIG=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --apply) APPLY=1; shift ;;
      --rig) ONLY_RIG="${2:-}"; shift 2 ;;
      *) echo "$PROG: unknown sweep argument '$1'" >&2; exit 2 ;;
    esac
  done
  local MODE="DRY-RUN (no writes; pass --apply to perform them)"
  [ "$APPLY" -eq 1 ] && MODE="APPLY"
  echo "$PROG sweep — $MODE"

  local rigs_raw rigs_rc scopes
  rigs_raw=$(run_bounded gc rig list --json 2>/dev/null); rigs_rc=$?
  scopes=$(printf '%s' "$rigs_raw" | jq -r '.rigs[]? | select((.path // "") != "")
      | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path, ((.suspended // false) | tostring)]
      | join("\u001f")' 2>/dev/null)
  if [ "$rigs_rc" -ne 0 ] || [ -z "$scopes" ]; then
    echo "$PROG: \`gc rig list --json\` failed (rc=$rigs_rc) or listed no rig paths; nothing to sweep against" >&2
    exit 1
  fi

  local total_attention=0 summary=""
  local rig_name rig_path suspended
  while IFS=$'\037' read -r rig_name rig_path suspended; do
    [ -n "$rig_path" ] || continue
    [ -z "$ONLY_RIG" ] || [ "$rig_name" = "$ONLY_RIG" ] || continue
    local label="${rig_name:-<city>}"
    if [ "$suspended" = "true" ]; then
      echo "$label: skipped (suspended — querying its store would auto-start an orphan Dolt server)"
      continue
    fi
    RIG_DB="$rig_path/.beads"
    local stripped=0 retired=0 repaired=0 attention=0
    echo "== rig $label ($RIG_DB) =="

    # --- (a) strip deleted healer-bookkeeping keys from OPEN beads ------------
    local open_raw rows keys_csv
    keys_csv=$(printf '%s' "$HEALER_KEYS" | tr -s ' ' ',')
    if ! open_raw=$(bd_list --status open); then
      echo "$label: could not list open beads — this store was NOT swept" >&2
      attention=$((attention + 1)); open_raw="[]"
    fi
    rows=$(printf '%s' "$open_raw" | jq -r --arg keys "$keys_csv" '
      ($keys | split(",")) as $hk
      | .[]? | . as $b
      | [ (($b.metadata // {}) | keys[]) | select(. as $k | ($hk | index($k)) != null) ] as $present
      | select(($present | length) > 0)
      | [(($b.id // "?") | tostring), ($present | join(","))] | join("\u001f")' 2>/dev/null)
    local id keys k args left
    while IFS=$'\037' read -r id keys; do
      [ -n "$id" ] || continue
      if [ "$APPLY" -ne 1 ]; then
        echo "  would strip [$keys] from open bead $id"
        stripped=$((stripped + 1)); continue
      fi
      args=()
      for k in $(printf '%s' "$keys" | tr ',' ' '); do args+=(--unset-metadata "$k"); done
      if ! bd_update "$id" ${args[@]+"${args[@]}"}; then
        echo "  $id: healer-key strip FAILED; keys still present" >&2
        attention=$((attention + 1)); continue
      fi
      left=""
      for k in $(printf '%s' "$keys" | tr ',' ' '); do
        [ -z "$(meta_of "$id" "$k")" ] || left="$left $k"
      done
      if [ -n "$left" ]; then
        echo "  $id: strip read-back FAILED — still carries:$left" >&2
        attention=$((attention + 1))
      else
        echo "  stripped [$keys] from open bead $id"
        stripped=$((stripped + 1))
      fi
    done <<< "$rows"

    # --- (b) retire pre-cutover molecules (stale poured text by definition) ---
    local live_raw roots root kids kid pass progress touched
    if ! live_raw=$(bd_list --status "$LIVE_STATUSES"); then
      echo "$label: could not list live beads for molecule retirement" >&2
      attention=$((attention + 1)); live_raw="[]"
    fi
    roots=$(printf '%s' "$live_raw" | jq -r '
      .[]? | select(((.metadata["gc.kind"] // "") | tostring) as $k | $k == "workflow" or $k == "wisp")
      | (.id // "?") | tostring' 2>/dev/null)
    for root in $roots; do
      if [ "$APPLY" -ne 1 ]; then
        kids=$(printf '%s' "$live_raw" | jq -r --arg r "$root" '
          [ .[]? | select(((.metadata["gc.root_bead_id"] // "") | tostring) == $r) | .id ] | length' 2>/dev/null)
        echo "  would retire molecule $root (${kids:-0} live step/control beads, then the root; work beads untouched)"
        retired=$((retired + 1)); continue
      fi
      pass=0
      while :; do
        pass=$((pass + 1)); [ "$pass" -le 10 ] || break
        kids=$(bd_list --status "$LIVE_STATUSES" 2>/dev/null | jq -r --arg r "$root" '
          [ .[]? | select(((.metadata["gc.root_bead_id"] // "") | tostring) == $r) | .id ] | .[]' 2>/dev/null)
        [ -n "$kids" ] || break
        progress=0
        while IFS= read -r kid; do
          [ -n "$kid" ] || continue
          # Never a work bead: steps/controls carry no branch or merge_result.
          if [ -n "$(meta_of "$kid" branch)" ] || [ -n "$(meta_of "$kid" merge_result)" ]; then
            echo "  $root: $kid carries work-bead metadata; REFUSING to close it" >&2
            attention=$((attention + 1)); continue
          fi
          blocked_now "$kid" && continue
          if bd_update "$kid" --status=closed --set-metadata gc.outcome=cutover-retired \
             && [ "$(status_of "$kid")" = "closed" ] \
             && [ "$(meta_of "$kid" gc.outcome)" = "cutover-retired" ]; then
            echo "  retired step/control $kid (molecule $root, pass $pass)"
            progress=$((progress + 1))
          else
            echo "  $root: close of $kid failed or did not read back; will retry next pass" >&2
          fi
        done <<< "$kids"
        [ "$progress" -gt 0 ] || break
      done
      touched=$(bd_list --status "$LIVE_STATUSES" 2>/dev/null | jq -r --arg r "$root" '
        [ .[]? | select(((.metadata["gc.root_bead_id"] // "") | tostring) == $r) | .id ] | length' 2>/dev/null)
      if [ "${touched:-1}" != "0" ]; then
        echo "  OPERATOR: molecule $root still has ${touched:-?} unclosable step/control beads after $pass passes" >&2
        attention=$((attention + 1)); continue
      fi
      if bd_update "$root" --status=closed --set-metadata gc.outcome=cutover-retired \
         && [ "$(status_of "$root")" = "closed" ] \
         && [ "$(meta_of "$root" gc.outcome)" = "cutover-retired" ]; then
        echo "  retired molecule root $root"
        retired=$((retired + 1))
      else
        echo "  OPERATOR: molecule root $root did not close cleanly" >&2
        attention=$((attention + 1))
      fi
    done

    # --- (c) repair pre-cutover closed-bead state (check-closed-implies-landed)
    local closed_raw origin mr num prurl pjson state oid
    origin=$(origin_of "$rig_path")
    if ! closed_raw=$(bd_list --status closed --has-metadata-key merge_result); then
      echo "$label: could not list closed anchors — repairs NOT evaluated" >&2
      attention=$((attention + 1)); closed_raw="[]"
    fi
    rows=$(printf '%s' "$closed_raw" | jq -r '
      .[]? | (.metadata // {}) as $m
      | ((($m.merge_result // "") | tostring)) as $mr
      | select($mr == "pull_request" or $mr == "pre_open_gate"
               or ($mr == "merged" and (($m.merged_sha // "") | tostring) == ""))
      | [((.id // "?") | tostring), $mr,
         (($m.pr_number // "") | tostring), (($m.pr_url // "") | tostring)]
      | join("\u001f")' 2>/dev/null)
    while IFS=$'\037' read -r id mr num prurl; do
      [ -n "$id" ] || continue
      if [ "$mr" = "merged" ]; then
        # merged with no evidence: the old system closed it before recording.
        if [ "$APPLY" -ne 1 ]; then
          echo "  would set merged_sha=unverified:pre-rewrite on closed bead $id"
          repaired=$((repaired + 1))
        elif bd_update "$id" --set-metadata merged_sha=unverified:pre-rewrite \
             && [ "$(meta_of "$id" merged_sha)" = "unverified:pre-rewrite" ]; then
          echo "  $id: recorded merged_sha=unverified:pre-rewrite"
          repaired=$((repaired + 1))
        else
          echo "  $id: merged_sha repair failed read-back" >&2; attention=$((attention + 1))
        fi
        continue
      fi
      case "$num" in ''|*[!0-9]*) num=$(printf '%s' "$prurl" | sed -n 's#.*/pull/\([0-9][0-9]*\).*#\1#p') ;; esac
      if [ -z "$num" ]; then
        echo "  OPERATOR: closed bead $id carries merge_result=$mr with NO PR identity — decide its terminal state by hand" >&2
        attention=$((attention + 1)); continue
      fi
      if [ -z "$origin" ] || ! command -v gh >/dev/null 2>&1; then
        echo "  OPERATOR: closed bead $id (PR#$num) — no origin/gh available to verify; left untouched" >&2
        attention=$((attention + 1)); continue
      fi
      pjson=$(run_bounded gh pr view "$num" --repo "$origin" --json state,mergeCommit,url 2>/dev/null | scrub)
      state=$(printf '%s' "$pjson" | jq -r '.state // ""' 2>/dev/null)
      if [ -z "$pjson" ] || [ -z "$state" ] \
         || [ "$(url_repo_q "$(printf '%s' "$pjson" | jq -r '.url // ""' 2>/dev/null)")" != "$origin" ]; then
        echo "  OPERATOR: closed bead $id — PR#$num read failed or identity did not certify; left untouched" >&2
        attention=$((attention + 1)); continue
      fi
      case "$state" in
        MERGED)
          oid=$(printf '%s' "$pjson" | jq -r '.mergeCommit.oid // ""' 2>/dev/null)
          [ -n "$oid" ] || oid="unverified:PR#$num"
          if [ "$APPLY" -ne 1 ]; then
            echo "  would repair closed bead $id: merge_result=$mr -> merged, merged_sha=$oid"
            repaired=$((repaired + 1))
          elif bd_update "$id" --set-metadata merge_result=merged --set-metadata "merged_sha=$oid" \
               && [ "$(meta_of "$id" merge_result)" = "merged" ] \
               && [ "$(meta_of "$id" merged_sha)" = "$oid" ]; then
            echo "  $id: PR#$num is MERGED; recorded merged + merged_sha=$oid"
            repaired=$((repaired + 1))
          else
            echo "  $id: merged repair failed read-back" >&2; attention=$((attention + 1))
          fi ;;
        CLOSED)
          if [ "$APPLY" -ne 1 ]; then
            echo "  would repair closed bead $id: merge_result=$mr -> abandoned (PR#$num closed unmerged)"
            repaired=$((repaired + 1))
          elif bd_update "$id" --set-metadata merge_result=abandoned \
               && [ "$(meta_of "$id" merge_result)" = "abandoned" ]; then
            echo "  $id: PR#$num closed unmerged; recorded merge_result=abandoned"
            repaired=$((repaired + 1))
          else
            echo "  $id: abandoned repair failed read-back" >&2; attention=$((attention + 1))
          fi ;;
        OPEN)
          echo "  OPERATOR DECISION REQUIRED: closed bead $id sits over OPEN PR#$num ($origin) — a closed anchor over a live PR is not a repair this script may invent; bead left UNTOUCHED. Reopen the anchor or close the PR, then re-run." >&2
          attention=$((attention + 1)) ;;
        *)
          echo "  OPERATOR: closed bead $id — PR#$num in unexpected state '$state'; left untouched" >&2
          attention=$((attention + 1)) ;;
      esac
    done <<< "$rows"

    summary="$summary$(printf '%-24s %13s %18s %15s %9s' "$label" "$stripped" "$retired" "$repaired" "$attention")\n"
    total_attention=$((total_attention + attention))
  done <<< "$scopes"

  echo
  printf '%-24s %13s %18s %15s %9s\n' "RIG" "KEYS-STRIPPED" "MOLECULES-RETIRED" "CLOSES-REPAIRED" "OPERATOR"
  printf '%b' "$summary"
  if [ "$total_attention" -gt 0 ]; then
    echo "$PROG sweep: $total_attention item(s) need the operator (see OPERATOR lines above)"
    exit 1
  fi
  echo "$PROG sweep: clean"
  exit 0
}

# --------------------------------------------------------------- verify ------
verify() {
  local fails=0

  # (i) Helm: the launcher never builds, so a served binary older than
  # services/helm silently renders yesterday's board — the staleness that has
  # burned the operator before. Build+deploy, then prove freshness by mtime.
  if ! "$SCRIPTS_DIR/gc-helm-build.sh" --deploy; then
    echo "FAIL: gc-helm-build.sh --deploy failed"; fails=$((fails + 1))
  else
    local sv state_root="" city="" rel="" mod="$PACK_DIR/services/helm" binf stale
    state_root="${GC_SERVICE_STATE_ROOT:-}"
    if [ -z "$state_root" ]; then
      sv=$(run_bounded gc service list --json 2>/dev/null | scrub)
      city=$(printf '%s' "$sv" | jq -r '.city_path // empty' 2>/dev/null)
      rel=$(printf '%s' "$sv" | jq -r 'first(.services[]? | select((.service_name // .name) == "helm") | .state_root // empty) // empty' 2>/dev/null)
      case "$rel" in /*) state_root="$rel" ;; "") : ;; *) [ -n "$city" ] && state_root="$city/$rel" ;; esac
    fi
    if [ -z "$state_root" ]; then
      echo "NOTE: helm state root unresolved (no helm service?); staleness not proven"
    else
      binf="$state_root/bin/helm-svc"
      stale=$(find "$mod" -name node_modules -prune -o \( -name '*.go' -o -name go.mod -o -name go.sum -o -path "$mod/web/dist/*" \) -newer "$binf" -print -quit 2>/dev/null)
      if [ ! -x "$binf" ]; then
        echo "FAIL: deployed helm binary $binf missing"; fails=$((fails + 1))
      elif [ -n "$stale" ]; then
        echo "FAIL: deployed helm binary is OLDER than $stale — the dashboard would serve stale code"; fails=$((fails + 1))
      else
        echo "ok: helm binary newer than every services/helm source"
      fi
      if [ -e "$state_root/restart-pending" ]; then
        echo "FAIL: restart-pending marker PRESENT — a published binary is not yet serving"; fails=$((fails + 1))
      else
        echo "ok: no restart-pending marker (published binary is serving)"
      fi
    fi
  fi

  # (ii) doctor: print every non-ok result.
  local draw bad
  draw=$(timeout 300 gc doctor --json 2>/dev/null | scrub)
  if [ -z "$draw" ]; then
    echo "FAIL: \`gc doctor --json\` returned nothing"; fails=$((fails + 1))
  else
    bad=$(printf '%s' "$draw" | jq -r '
      (if type == "array" then . else (.checks // .results // []) end)
      | .[]? | select((((.status // .result // "") | tostring) | ascii_downcase) != "ok")
      | "  - " + ((.name // .check // "?") | tostring) + ": "
        + ((.status // .result // "?") | tostring) + " " + ((.message // "") | tostring)' 2>/dev/null)
    if [ -n "$bad" ]; then
      echo "FAIL: doctor reports non-ok checks:"; printf '%s\n' "$bad"; fails=$((fails + 1))
    else
      echo "ok: gc doctor all green"
    fi
  fi

  # (iii) every pack order registered (names = orders/*.toml basenames).
  local oraw f name missing=""
  oraw=$(run_bounded gc order list --json 2>/dev/null)
  [ -n "$oraw" ] || oraw=$(run_bounded gc order list 2>/dev/null)
  for f in "$PACK_DIR"/orders/*.toml; do
    [ -e "$f" ] || continue
    name=$(basename "$f" .toml)
    grep -qF -- "$name" <<< "$oraw" || missing="$missing $name"
  done
  if [ -z "$oraw" ]; then
    echo "FAIL: \`gc order list\` returned nothing"; fails=$((fails + 1))
  elif [ -n "$missing" ]; then
    echo "FAIL: pack orders NOT registered:$missing"; fails=$((fails + 1))
  else
    echo "ok: all $(ls "$PACK_DIR"/orders/*.toml 2>/dev/null | wc -l | tr -d ' ') pack orders registered"
  fi

  # (iv) seed-audit stub is fine at runtime; it renders on first dev clone.
  if [ ! -e "$PACK_DIR/generated/seed-audit/INDEX.md" ]; then
    echo "note: generated/seed-audit is still the README stub (renders on first dev clone; not required for runtime)"
  fi

  if [ "$fails" -gt 0 ]; then echo "$PROG verify: $fails check(s) failed"; exit 1; fi
  echo "$PROG verify: all green"
  exit 0
}

case "${1:-}" in
  sweep)  shift; sweep "$@" ;;
  verify) shift; verify "$@" ;;
  *) echo "usage: $PROG sweep [--apply] [--rig <name>] | verify" >&2; exit 2 ;;
esac
