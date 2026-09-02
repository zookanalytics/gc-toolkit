#!/usr/bin/env bash
# pr-open — arm 2 of the merge cadence: pre_open_gate -> pull_request.
# For each pre_open_gate anchor: adopt an existing OPEN or MERGED PR for the
# branch (flip only — never open a twin); a CLOSED-unmerged-only PR is a
# headstone — open a fresh PR noting the superseded one (unless the dead head
# IS the live head: that close was a decision about this exact commit).
# Otherwise: holds gate the create path; refuse a bead-local planning artifact
# aimed at the default branch with no convoy above it (the shared-input-artifact
# anti-pattern), naming the integration-branch remedy and escalating it once;
# require every marker-bearing gate the anchor's check_set declares to read
# green;
# `gh pr create` non-draft pinned to origin, body summarizing the polecat's
# `pr_summary` with the dispatch text demoted (the description only when no
# summary was carried), read back BY NUMBER, refuse a moved head, replay the
# recorded verdict as a COMMENT (never an approval);
# then ONE lifecycle.sh transition to pull_request carrying
# pr_url/pr_number/merged_target. Every failure leaves pre_open_gate.
# Caller: refinery-reconcile.sh. Fail-closed on identity; not set -e.
set -u

PROG="pr-open"
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub
SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
LIFECYCLE="$SCRIPTS_DIR/lifecycle.sh"

command -v gh >/dev/null 2>&1 || exit 0

# The repository every read and the create are pinned to — from the origin
# remote, never from gh (gh's current repo is the movable source this distrusts).
ORIGIN_HOST=""; ORIGIN_REPO=""; ORIGIN_REPO_Q=""
u=$(git remote get-url origin 2>/dev/null | tr -d '[:space:]')
case "$u" in
  git@github.com:*|https://github.com/*|ssh://git@github.com/*)
    ORIGIN_HOST="github.com"
    ORIGIN_REPO=$(printf '%s' "$u" | sed -e 's#^ssh://git@github.com/##' \
      -e 's#^git@github.com:##' -e 's#^https://github.com/##' -e 's#\.git$##' -e 's#/*$##') ;;
esac
case "$ORIGIN_REPO" in */*/*|/*|*/) ORIGIN_REPO="" ;; */*) : ;; *) ORIGIN_REPO="" ;; esac
if [ -z "$ORIGIN_REPO" ]; then
  echo "$PROG: cannot resolve this checkout's origin repository; NOTHING is opened this pass" >&2
  exit 0
fi
ORIGIN_REPO_Q="$ORIGIN_HOST/$ORIGIN_REPO"

url_repo_q() {
  printf '%s' "${1:-}" \
    | sed -n 's#^[A-Za-z][A-Za-z0-9+.-]*://\([^/][^/]*\)/\([^/][^/]*/[^/][^/]*\)/pull/[0-9].*#\1/\2#p'
}
pr_url_canon() {
  printf '%s\n' "${1:-}" \
    | grep -Eo '[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]]+/pull/[0-9]+' | tail -1
}
# Same truthiness rule at both call sites, named for what each one asks: a set
# marker HOLDS when the operator set it, and CONSENTS when it waives a guard.
is_set() {
  case "${1:-}" in ""|false|False|FALSE|0|null) return 1 ;; *) return 0 ;; esac
}
is_held() { is_set "${1:-}"; }

# The branch a bead lands on when nothing else names one. Derived per rig from
# origin/HEAD, the way refinery-reconcile.sh derives its graduation target, so
# a rig whose default branch is not `main` is not judged against `main`.
DEFAULT_BRANCH="${PR_OPEN_DEFAULT_BRANCH:-}"
if [ -z "$DEFAULT_BRANCH" ]; then
  DEFAULT_BRANCH=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)
  DEFAULT_BRANCH="${DEFAULT_BRANCH#origin/}"
fi
[ -n "$DEFAULT_BRANCH" ] || DEFAULT_BRANCH="main"

# The path prefixes that hold bead-local planning content. docs/file-structure.md
# splits documentation in two: `docs/` is the central tier, authoritative about
# now and refreshed in place, which is what legitimately lands on the default
# branch on its own; `specs/<bead-id>/` is the local tier, the record of one
# bead's work. Only the local tier is listed. A rig that files its local tier
# elsewhere sets the env, and an empty value disables the guard.
PLANNING_PATHS="${PR_OPEN_PLANNING_PATHS-specs/}"
planning_prefixes() {
  printf '%s' "$PLANNING_PATHS" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; /^$/d'
  return 0
}

# Is this branch's whole diff bead-local planning content? 0 = yes, 1 = no,
# 2 = unanswered — the compare did not read, or it is longer than the endpoint
# will list, and a verdict from a partial file list is not a verdict.
diff_is_planning_only() { # <base> <head>
  local raw n prefixes p pre hit
  prefixes=$(planning_prefixes)
  [ -n "$prefixes" ] || return 1
  raw=$(gh api --hostname "$ORIGIN_HOST" "repos/$ORIGIN_REPO/compare/$1...$2" 2>/dev/null) || return 2
  raw=$(printf '%s' "$raw" | scrub)
  printf '%s' "$raw" | jq -e 'type == "object" and has("files")' >/dev/null 2>&1 || return 2
  n=$(printf '%s' "$raw" | jq -r '.files | length' 2>/dev/null)
  case "${n:-}" in ''|*[!0-9]*) return 2 ;; esac
  [ "$n" -gt 0 ] || return 1
  # The compare endpoint lists at most 300 files. At the cap the rest are
  # unseen, and a 300-file diff is not the shape this guards anyway.
  [ "$n" -lt 300 ] || return 2
  while IFS= read -r p; do
    [ -n "${p:-}" ] || continue
    hit=0
    while IFS= read -r pre; do
      [ -n "${pre:-}" ] || continue
      case "$p" in "$pre"*) hit=1; break ;; esac
    done <<< "$prefixes"
    [ "$hit" = 1 ] || return 1
  done <<< "$(printf '%s' "$raw" | jq -r '.files[]? | .filename // empty' 2>/dev/null)"
  return 0
}

# The nearest convoy above a bead, on stdout, empty when there is none.
# 1 = a read failed and the walk cannot answer. Mirrors the parent-chain walk
# gc sling resolves metadata.target through (gascity
# internal/sling/sling.go:913, BeadMetadataTarget, which stops at `b.Type ==
# "convoy"`): parent-child rows sit on the CHILD naming the parent, so the
# chain is followed one dependency read at a time. The synthetic one-child
# input convoy every sling creates is joined by `tracks`, not parent-child, so
# it is invisible here — which is right, it carries no integration branch.
convoy_above() { # <bead-id>
  local cur="$1" depth=0 rows found next
  while [ "$depth" -lt 8 ]; do
    rows=$(gc bd dep list "$cur" --direction=down --type=parent-child --json 2>/dev/null) || return 1
    rows=$(printf '%s' "$rows" | scrub)
    printf '%s' "$rows" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
    found=$(printf '%s' "$rows" | jq -r '[ .[]? | select((((.issue_type // "") | tostring)) == "convoy") | .id ] | .[0] // empty' 2>/dev/null)
    if [ -n "$found" ]; then printf '%s' "$found"; return 0; fi
    next=$(printf '%s' "$rows" | jq -r '[ .[]? | .id // empty ] | .[0] // empty' 2>/dev/null)
    [ -n "$next" ] || return 0
    cur="$next"; depth=$((depth + 1))
  done
  return 0
}

# Best-effort and deduped by situation: escalate.sh keeps exactly one open
# visit per key, so a refusal that stands for days reaches a person once
# rather than once per pass.
ESCALATE="$SCRIPTS_DIR/escalate.sh"
escalate() { # <subject> <key> <message>
  [ -x "$ESCALATE" ] || return 0
  "$ESCALATE" --subject "$1" --key "$2" --message "$3" >/dev/null 2>&1 || true
}

# The marker-bearing gates a check_set declares, one per line. Same drop list
# merge.sh's hold_gate applies, so publishing and merging judge one anchor by
# one rule: none/off is the gateless-by-choice sentinel, and approval is
# evidenced by an external GitHub review, which cannot exist before the PR
# does. The drop test is case-insensitive; what survives keeps its case,
# because it addresses a metadata key.
gates_of() { # <check_set>
  printf '%s' "${1:-}" | tr ',' '\n' | sed 's/[[:space:]]//g; /^$/d' \
    | grep -Eiv '^(none|off|approval)$'
  return 0
}

# Certify one PR row as this anchor's: right repo url, right head branch, OUR
# head repository (fork gap), not cross-repo, right base. 0=ours, 1=not ours,
# 2=unreadable (the caller must do nothing for the branch).
CERT_NUM=""; CERT_URL=""; CERT_STATE=""; CERT_HEAD_OID=""; CERT_MERGED_AT=""
certify_row() { # <id> <row-json> <branch> <target> [<want-num>]
  local id="$1" row="$2" br="$3" tgt="$4" want="${5:-}"
  local num url state base head hrepo cross goturl
  CERT_NUM=""; CERT_URL=""; CERT_STATE=""; CERT_HEAD_OID=""; CERT_MERGED_AT=""
  num=$(printf '%s' "$row" | jq -r '.number // "" | tostring' 2>/dev/null)
  url=$(printf '%s' "$row" | jq -r '.url // ""' 2>/dev/null)
  state=$(printf '%s' "$row" | jq -r '.state // ""' 2>/dev/null)
  base=$(printf '%s' "$row" | jq -r '.baseRefName // ""' 2>/dev/null)
  head=$(printf '%s' "$row" | jq -r '.headRefName // ""' 2>/dev/null)
  hrepo=$(printf '%s' "$row" | jq -r '
    ((.headRepositoryOwner.login // "") | tostring) as $o
    | ((.headRepository.name // "") | tostring) as $n
    | if $o == "" or $n == "" then "" else $o + "/" + $n end' 2>/dev/null)
  cross=$(printf '%s' "$row" | jq -r 'if has("isCrossRepository") then (.isCrossRepository | tostring) else "" end' 2>/dev/null)
  CERT_MERGED_AT=$(printf '%s' "$row" | jq -r '(.mergedAt // "") | tostring' 2>/dev/null)
  CERT_HEAD_OID=$(printf '%s' "$row" | jq -r '(.headRefOid // "") | tostring' 2>/dev/null)
  if [ -z "$url" ] || [ -z "$state" ] || [ -z "$base" ] || [ -z "$head" ] \
     || [ -z "$hrepo" ] || [ -z "$cross" ] || [ -z "$num" ] || [ -n "${num//[0-9]/}" ]; then
    echo "$PROG: $id branch '$br' — PR identity unreadable (num='$num' url='$url' state='$state' base='$base' head='$head' headrepo='$hrepo' cross='$cross'); NOTHING done this pass" >&2
    return 2
  fi
  goturl=$(pr_url_canon "$url")
  [ "$(url_repo_q "$goturl")" = "$ORIGIN_REPO_Q" ] || { echo "$PROG: $id PR#$num lives in '$(url_repo_q "$goturl")', not '$ORIGIN_REPO_Q'; not ours" >&2; return 1; }
  [ -z "$want" ] || [ "$num" = "$want" ] || { echo "$PROG: $id asked for PR#$want, PR#$num answered; not certified" >&2; return 1; }
  [ "$head" = "$br" ] || { echo "$PROG: $id PR#$num is opened from '$head', not '$br'; not ours" >&2; return 1; }
  [ "$hrepo" = "$ORIGIN_REPO" ] || { echo "$PROG: $id PR#$num head is in FORK '$hrepo'; the branch name matches, the work does not" >&2; return 1; }
  [ "$cross" = "false" ] || { echo "$PROG: $id PR#$num head identity contradicts itself (cross='$cross'); unreadable, NOTHING done" >&2; return 2; }
  [ "$base" = "$tgt" ] || { echo "$PROG: $id PR#$num targets '$base', not '$tgt'; not ours" >&2; return 1; }
  CERT_NUM="$num"; CERT_URL="$goturl"; CERT_STATE="$state"
  return 0
}

# The branch's PR among the certified rows: 0=adoptable (OPEN/MERGED in CERT_*),
# 1=none, 2=refuse (unreadable/collision), 3=dead only (DEAD_* set).
DEAD_NUM=""; DEAD_URL=""; DEAD_HEAD=""
find_pr() { # <id> <branch> <target>
  local id="$1" br="$2" tgt="$3" json rc row disp best_rank=99 bn="" bu="" bs=""
  DEAD_NUM=""; DEAD_URL=""; DEAD_HEAD=""
  json=$(gh pr list --head "$br" --state all --repo "$ORIGIN_REPO_Q" \
    --json number,url,state,mergedAt,baseRefName,headRefName,headRefOid,headRepository,headRepositoryOwner,isCrossRepository \
    --limit 100 2>/dev/null); rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$json" ] \
     || ! printf '%s' "$json" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "$PROG: $id could not read the PRs for '$br' (rc=$rc); not the same as none existing — NOTHING done" >&2
    return 2
  fi
  local n; n=$(printf '%s' "$json" | jq 'length' 2>/dev/null)
  case "$n" in ''|*[!0-9]*) return 2 ;; esac
  while IFS= read -r row; do
    [ -n "${row:-}" ] || continue
    certify_row "$id" "$row" "$br" "$tgt"
    case $? in 0) : ;; 2) return 2 ;; *) continue ;; esac
    case "$CERT_STATE" in
      OPEN)   disp=0 ;;
      MERGED) disp=1 ;;
      CLOSED)
        # mergedAt promotes CLOSED to merged (GitHub's REST shape for a landing).
        if [ -n "$CERT_MERGED_AT" ] && [ "$CERT_MERGED_AT" != "null" ]; then disp=1; else
          if [ -z "$DEAD_NUM" ] || [ "$CERT_NUM" -gt "$DEAD_NUM" ]; then
            DEAD_NUM="$CERT_NUM"; DEAD_URL="$CERT_URL"; DEAD_HEAD="$CERT_HEAD_OID"
          fi
          continue
        fi ;;
      *) echo "$PROG: $id PR#$CERT_NUM reports unmodeled state '$CERT_STATE'; NOTHING done" >&2; return 2 ;;
    esac
    if [ "$disp" -lt "$best_rank" ] || { [ "$disp" -eq "$best_rank" ] && [ "$CERT_NUM" -gt "${bn:-0}" ]; }; then
      best_rank="$disp"; bn="$CERT_NUM"; bu="$CERT_URL"; bs="$CERT_STATE"
    fi
  done <<ROWS
$(printf '%s' "$json" | jq -c '.[]' 2>/dev/null)
ROWS
  if [ -z "$bn" ]; then
    [ -n "$DEAD_NUM" ] && return 3
    if [ "$n" -gt 0 ]; then
      echo "$PROG: $id branch '$br' matched $n PR(s) and none is ours (name collision); NOTHING done" >&2
      return 2
    fi
    return 1
  fi
  CERT_NUM="$bn"; CERT_URL="$bu"; CERT_STATE="$bs"
  return 0
}

flip() { # <id> <url> <num> <target> — ONE atomic lifecycle transition
  "$LIFECYCLE" transition "$1" --to pull_request --expect pre_open_gate \
    --set "pr_url=$2" --set "pr_number=$3" --set "merged_target=$4" \
    >/dev/null 2>&1
}

# --- enumerate ------------------------------------------------------------------
ANCHORS=$(gc bd list --status=open --metadata-field merge_result=pre_open_gate \
  --limit=0 --json 2>/dev/null); rc=$?
if [ "$rc" -ne 0 ] || [ -z "$ANCHORS" ] \
   || ! printf '%s' "$ANCHORS" | scrub | jq -e 'type == "array"' >/dev/null 2>&1; then
  echo "$PROG: could not enumerate pre-open anchors (rc=$rc); failing loudly rather than reporting a false all-clear" >&2
  exit 1
fi
ANCHORS=$(printf '%s' "$ANCHORS" | scrub)
[ "$ANCHORS" != "[]" ] || { echo "$PROG: no pre-open anchors"; exit 0; }

opened=0; flipped=0; held=0; skipped=0
while IFS= read -r row; do
  [ -n "${row:-}" ] || continue
  id=$(printf '%s' "$row" | jq -r '.id // empty')
  branch=$(printf '%s' "$row" | jq -r '.metadata.branch // empty')
  target=$(printf '%s' "$row" | jq -r '.metadata.merged_target // .metadata.target // empty')
  [ -n "$target" ] || target="main"
  if [ -z "$id" ] || [ -z "$branch" ]; then skipped=$((skipped + 1)); continue; fi

  SUP_NUM=""; SUP_URL=""; SUP_HEAD=""
  find_pr "$id" "$branch" "$target"
  case $? in
    0)
      if flip "$id" "$CERT_URL" "$CERT_NUM" "$target"; then
        flipped=$((flipped + 1))
        echo "$PROG: $id branch '$branch' already has PR#$CERT_NUM ($CERT_STATE); flipped to pull_request"
      else
        echo "$PROG: $id PR#$CERT_NUM adoption transition failed; anchor stays pre_open_gate (retry next pass)" >&2
        skipped=$((skipped + 1))
      fi
      continue ;;
    2) skipped=$((skipped + 1)); continue ;;
    3) SUP_NUM="$DEAD_NUM"; SUP_URL="$DEAD_URL"; SUP_HEAD="$DEAD_HEAD" ;;  # dead only: create path
    *) : ;;  # none: create path
  esac

  # Operator holds gate the create (publishing) path only — adoption above is
  # not a publish, and downstream gates honor the same markers.
  hold=$(printf '%s' "$row" | jq -r '.metadata.merge_hold // empty')
  rhold=$(printf '%s' "$row" | jq -r '.metadata.rebase_hold // empty')
  if is_held "$hold" || is_held "$rhold"; then
    echo "$PROG: $id branch '$branch' held (merge_hold='$hold' rebase_hold='$rhold'); no PR opened"
    held=$((held + 1)); continue
  fi

  # The shared-input-artifact guard. A decisions doc, a carve doc, a spec that
  # several polecats need before any of them can produce mergeable work is not
  # bead-local content the default branch should carry on its own: the operator
  # is handed a document with nothing to review it against, and the children
  # meant to consume it have no branch to consume it from. The dispatch
  # doctrine names it the anti-pattern (agents/mechanik/prompt.template.md,
  # "Dispatch doctrine: an owned convoy is the PR unit").
  #
  # Every condition below has to hold, and each one spares a population that
  # must keep publishing: a doc riding with code is an ordinary PR, a `docs/`
  # refresh is the central tier doing its job, an anchor whose target is not
  # the default branch is already landing somewhere else, and a graduation
  # anchor — the convoy bead itself, carrying `integration/<id>` into the
  # default branch — is this doctrine's own end state. The convoy-ancestor
  # condition is the doctrine's shape rather than a proof of one: a convoy
  # that names no target hands its children no integration branch and still
  # exempts them here. Judged at the create path, so an adoption or an
  # operator hold never reaches it.
  if [ "$target" = "$DEFAULT_BRANCH" ] \
     && ! is_set "$(printf '%s' "$row" | jq -r '.metadata.planning_artifact_ok // empty')" \
     && ! is_set "$(printf '%s' "$row" | jq -r '.metadata.graduation // empty')" \
     && [ "$(printf '%s' "$row" | jq -r '(.issue_type // "") | tostring')" != "convoy" ]; then
    CONVOY_ABOVE=$(convoy_above "$id"); walk_rc=$?
    if [ "$walk_rc" -ne 0 ]; then
      echo "$PROG: $id branch '$branch' — convoy-ancestor walk unreadable; the planning-artifact guard did not evaluate and the create proceeds" >&2
    elif [ -z "$CONVOY_ABOVE" ]; then
      diff_is_planning_only "$target" "$branch"; diff_rc=$?
      if [ "$diff_rc" -eq 2 ]; then
        echo "$PROG: $id branch '$branch' — compare against '$target' unreadable or over the file cap; the planning-artifact guard did not evaluate and the create proceeds" >&2
      elif [ "$diff_rc" -eq 0 ]; then
        echo "$PROG: $id branch '$branch' is a planning artifact aimed at '$DEFAULT_BRANCH': every changed path is under '$PLANNING_PATHS' and no convoy stands above the anchor; no PR opened"
        echo "$PROG:   remedy — seed the artifact on an owned convoy's integration branch and land the children onto that branch:"
        echo "$PROG:     CONVOY=\$(gc convoy create '<initiative>' --owned --target integration/<convoy-id> --json | jq -r .convoy_id)"
        echo "$PROG:     push integration/<convoy-id> carrying the artifact, then: gc bd dep add $id \"\$CONVOY\" --type=parent-child"
        echo "$PROG:     gc bd update $id --set-metadata target=integration/<convoy-id>"
        echo "$PROG:   land it on '$DEFAULT_BRANCH' deliberately instead: gc bd update $id --set-metadata planning_artifact_ok=true"
        escalate "$id" "planning-artifact-to-default-branch" \
          "$id is ready to open a PR onto $DEFAULT_BRANCH whose whole diff is bead-local planning content under $PLANNING_PATHS, with no convoy above it. No PR was opened, and the anchor stays at pre_open_gate until one of the two moves below is made.
Remedy: seed the artifact on an owned convoy's integration branch and land the children onto that branch —
  CONVOY=\$(gc convoy create '<initiative>' --owned --target integration/<convoy-id> --json | jq -r .convoy_id)
  gc bd dep add $id \"\$CONVOY\" --type=parent-child
  gc bd update $id --set-metadata target=integration/<convoy-id>
Or land it on $DEFAULT_BRANCH deliberately: gc bd update $id --set-metadata planning_artifact_ok=true
Branch: $branch"
        held=$((held + 1)); continue
      fi
    fi
  fi

  # The gate: every gate the anchor's own check_set declares reads green. Same
  # predicate merge.sh applies at the merge, so one anchor is judged by one rule
  # at both transitions. The head below is what the PR is opened at, not what
  # the gate is measured against — green is a state of the lane.
  HEAD_JSON=$(gh api --hostname "$ORIGIN_HOST" "repos/$ORIGIN_REPO/commits/$branch" 2>/dev/null)
  head_oid=$(printf '%s' "$HEAD_JSON" | jq -r '.sha // empty' 2>/dev/null)
  if [ -z "$head_oid" ]; then
    echo "$PROG: $id branch '$branch' head unresolved; skip (retry next pass)" >&2
    skipped=$((skipped + 1)); continue
  fi
  checkset=$(printf '%s' "$row" | jq -r '.metadata.check_set // ""')
  # Empty is never the gateless opt-out: that is the 'none' sentinel. Empty
  # means never normalized, and gate-ensure — arm 1 of this same pass — stamps
  # the declared default. Publishing under it would open the PR ungated.
  if [ -z "$(printf '%s' "$checkset" | tr -d '[:space:],')" ]; then
    echo "$PROG: $id branch '$branch' has no normalized check_set (empty is never the 'none' opt-out); no PR opened — gate-ensure stamps the default"
    held=$((held + 1)); continue
  fi
  UNGREEN=""; UNGREEN_HAVE=""
  while IFS= read -r g; do
    [ -n "${g:-}" ] || continue
    marker=$(printf '%s' "$row" | jq -r --arg k "check.$g" '.metadata[$k] // empty')
    [ "$marker" = "green" ] && continue
    UNGREEN="$g"; UNGREEN_HAVE="${marker:-unreviewed}"; break
  done <<GATES
$(gates_of "$checkset")
GATES
  if [ -n "$UNGREEN" ]; then
    echo "$PROG: $id branch '$branch' check '$UNGREEN' is '$UNGREEN_HAVE', not green; held"
    held=$((held + 1)); continue
  fi

  # A dead PR closed at EXACTLY this head was a decision about this commit;
  # reopening it would repeat every pass. An unreadable dead head refuses too.
  if [ -n "$SUP_NUM" ]; then
    if [ -z "$SUP_HEAD" ]; then
      echo "$PROG: $id branch '$branch' has only closed PR#$SUP_NUM and its head is unreadable; NOTHING opened (operator must repair)" >&2
      skipped=$((skipped + 1)); continue
    fi
    if [ "$SUP_HEAD" = "$head_oid" ]; then
      echo "$PROG: $id branch '$branch' — PR#$SUP_NUM was closed unmerged at this same head ($head_oid); not reopening a human's decision" >&2
      skipped=$((skipped + 1)); continue
    fi
  fi

  # --- create, pinned and non-draft ----------------------------------------------
  title=$(printf '%s' "$row" | jq -r '.title // empty')
  desc=$(printf '%s' "$row" | jq -r '.description // empty')
  # The summary is the polecat's account of the diff, carried in pr_summary by
  # the refinery handoff. The anchor's description is dispatch text — what the
  # work was asked to do, addressed to the agent that did it and never revised
  # once the diff exists — so it is demoted to a collapsed section and stands
  # in as the summary only when the handoff carried no account. Whitespace is
  # the absent case, as it is for check_set above.
  summary=$(printf '%s' "$row" | jq -r '.metadata.pr_summary // empty')
  [ -n "$(printf '%s' "$summary" | tr -d '[:space:]')" ] || summary=""
  BODY=$(mktemp) || { echo "$PROG: cannot create a temp file for the PR body" >&2; exit 1; }
  {
    echo "## Summary"; echo
    if [ -n "$summary" ]; then printf '%s\n' "$summary"
    elif [ -n "$desc" ]; then printf '%s\n' "$desc"
    else printf 'Refinery handoff for `%s`.\n' "$id"; fi
    if [ -n "$summary" ] && [ -n "$desc" ]; then
      echo; echo "<details>"; echo "<summary>Dispatch — what this work was asked to do</summary>"; echo
      printf '%s\n' "$desc"
      echo; echo "</details>"
    fi
    echo; echo "## Refinery handoff"; echo
    printf -- '- Issue: `%s`\n- Source branch: `%s`\n- Target: `%s`\n' "$id" "$branch" "$target"
    GREENED=$(gates_of "$checkset" | paste -sd, -)
    if [ -n "$GREENED" ]; then
      printf -- '- Gates `%s` signed off pre-open at `%.8s`; PR opened green.\n' "$GREENED" "$head_oid"
    else
      printf -- '- Anchor declares no pre-open gate (`check_set=%s`); opened at `%.8s`.\n' "$checkset" "$head_oid"
    fi
    [ -n "$SUP_NUM" ] && printf -- '- Supersedes #%s (closed unmerged at `%.8s`); re-implemented and re-gated at `%.8s`.\n' \
      "$SUP_NUM" "$SUP_HEAD" "$head_oid"
  } > "$BODY"
  CREATED_URL=$(pr_url_canon "$(gh pr create --repo "$ORIGIN_REPO_Q" --base "$target" \
    --head "$branch" --title "$title ($id)" --body-file "$BODY" 2>/dev/null || true)")
  rm -f "$BODY"
  if [ -z "$CREATED_URL" ]; then
    echo "$PROG: $id branch '$branch' PR create produced nothing; skip (retry next pass)" >&2
    skipped=$((skipped + 1)); continue
  fi
  if [ "$(url_repo_q "$CREATED_URL")" != "$ORIGIN_REPO_Q" ]; then
    echo "$PROG: $id create answered '$CREATED_URL' outside '$ORIGIN_REPO_Q'; NOTHING stamped" >&2
    skipped=$((skipped + 1)); continue
  fi
  PR_NUMBER=$(printf '%s' "$CREATED_URL" | sed -n 's#.*/pull/\([0-9][0-9]*\)$#\1#p')
  # Read the created PR back BY NUMBER and certify it; refuse a moved head — the
  # contract is that a PR is gate-green at birth.
  NEW_JSON=$(gh pr view "$PR_NUMBER" --repo "$ORIGIN_REPO_Q" \
    --json number,url,state,baseRefName,headRefName,headRefOid,headRepository,headRepositoryOwner,isCrossRepository 2>/dev/null)
  if [ -z "$NEW_JSON" ] || ! certify_row "$id" "$NEW_JSON" "$branch" "$target" "$PR_NUMBER"; then
    echo "$PROG: $id opened PR#$PR_NUMBER but could not certify it; NOTHING stamped, anchor stays pre_open_gate (adopted next pass)" >&2
    skipped=$((skipped + 1)); continue
  fi
  if [ "$CERT_HEAD_OID" != "$head_oid" ]; then
    echo "$PROG: $id opened PR#$PR_NUMBER at head '${CERT_HEAD_OID:-?}', not the reviewed '$head_oid' (the branch moved); NOTHING stamped — the moved head re-gates" >&2
    skipped=$((skipped + 1)); continue
  fi

  # Replay the recorded verdict as a COMMENT — the city never approves (#185).
  REVIEW_ID=$(gc bd list --metadata-field task_kind=review --metadata-field anchor_bead="$id" \
    --status=closed,open,in_progress --limit=0 --json 2>/dev/null | scrub \
    | jq -r 'sort_by(.updated_at // .created_at) | last | .id // empty' 2>/dev/null)
  VERDICT=""
  [ -n "$REVIEW_ID" ] && VERDICT=$(gc bd show "$REVIEW_ID" --json 2>/dev/null | scrub \
    | jq -r '.[0].notes // ""' 2>/dev/null)
  if [ -n "$VERDICT" ]; then
    gh pr comment "$PR_NUMBER" --repo "$ORIGIN_REPO_Q" \
      --body "$(printf 'Pre-open signoff (comment-only — not an approval):\n\n%s' "$VERDICT")" >/dev/null 2>&1 || true
  else
    gh pr comment "$PR_NUMBER" --repo "$ORIGIN_REPO_Q" \
      --body "Pre-open gates signed off at \`${head_oid:0:8}\` (comment-only — not an approval)." >/dev/null 2>&1 || true
  fi
  [ -n "$SUP_NUM" ] && gh pr comment "$SUP_NUM" --repo "$ORIGIN_REPO_Q" \
    --body "Superseded by #$PR_NUMBER: branch \`$branch\` was re-implemented and re-gated at \`${head_oid:0:8}\`." >/dev/null 2>&1 || true

  if flip "$id" "$CERT_URL" "$CERT_NUM" "$target"; then
    opened=$((opened + 1))
    echo "$PROG: $id opened PR#$PR_NUMBER for '$branch' at ${head_oid:0:8} (check_set '$checkset' green)${SUP_NUM:+, superseding closed PR#$SUP_NUM}; flipped to pull_request"
  else
    echo "$PROG: $id opened PR#$PR_NUMBER but did NOT reach pull_request; anchor stays pre_open_gate and adopts this PR next pass" >&2
    skipped=$((skipped + 1))
  fi
done <<ANCHORS_EOF
$(printf '%s' "$ANCHORS" | jq -c '.[]' 2>/dev/null)
ANCHORS_EOF

echo "$PROG: $opened opened, $flipped flipped, $held held, $skipped skipped"
exit 0
