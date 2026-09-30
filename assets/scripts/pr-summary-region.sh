#!/usr/bin/env bash
# pr-summary-region.sh — compose the managed `## Summary` region of a PR body and
# splice it into a published body. Shared by the writer that opens a PR
# (pr-open.sh, the create and pre_open_gate-adoption paths) and the arm that keeps
# an already-open PR's body current with a reworked anchor summary (pr-stack.sh).
# Sourced, never executed.
#
# A caller resolves this file beside itself and sources it, the way bd-lib.sh is:
#   # shellcheck source=pr-summary-region.sh
#   . "${GC_PR_SUMMARY_LIB:-$SCRIPT_DIR/pr-summary-region.sh}" \
#     || { echo "$PROG: cannot source pr-summary-region.sh" >&2; exit 1; }
#
# The composed body lives between the markers below, an HTML-comment pair
# invisible in the rendered body. A create wraps its composition in them; every
# later refresh re-splices a freshly composed region into the markers the create
# left, so a reworked pr_summary reaches the published body without disturbing
# text an operator or another arm (pr-stack's own branch-beads section) added.
# One composer serves create, adoption and post-open refresh, so the three never
# diverge — which is also what lets a refresh compare its render against the body
# and skip an edit when nothing changed.

PRS_MARK_OPEN="<!-- gc:pr-summary -->"
PRS_MARK_CLOSE="<!-- /gc:pr-summary -->"

# The lanes a check_set declares, one per line. Same drop list merge.sh's
# lanes_of applies, so publishing and merging judge one anchor by one rule:
# none/off is the gateless-by-choice sentinel, and approval is evidenced by an
# external GitHub review, which cannot exist before the PR does. The drop test
# is case-insensitive; what survives keeps its case, because it names a lane.
gates_of() { # <check_set>
  printf '%s' "${1:-}" | tr ',' '\n' | sed 's/[[:space:]]//g; /^$/d' \
    | grep -Eiv '^(none|off|approval)$'
  return 0
}

# The region always writes its own `## Summary`, so a stored pr_summary that opens
# with a Summary heading of its own is stripped of it here rather than published
# under two. Only a bare `Summary` heading line goes; a heading carrying other
# words is real content and stays.
strip_summary_heading() { # <text>
  printf '%s' "$1" | awk '
    NR == 1 && $0 ~ /^[[:space:]]*#{1,6}[[:space:]]+[Ss]ummary[[:space:]]*$/ { s = 1; next }
    s && $0 ~ /^[[:space:]]*$/ { next }
    { s = 0; print }
  '
}

# The region's contents, no markers: an integration-checkpoint banner when the
# target is under integration/, then the ## Summary a reviewer reads first, the
# dispatch text demoted below it when both exist, and the refinery handoff facts.
#
# The last handoff bullet states the gate posture, and its wording is the one
# thing that turns on the mode. `open` (create and pre_open_gate adoption) records
# that the declared gates signed off pre-open at this head and the PR opened green
# — a fact true at that moment. `refresh` (an already-open PR whose anchor summary
# a rework restamped) must not repeat that claim at the reworked head: the gates
# have not re-signed-off there, and one of them may be actively requesting
# changes. It names the current head and points to the PR's own checks for the
# live status instead.
compose_managed() { # <summary> <desc> <id> <branch> <target> <checkset> <head_oid> <sup_num> <sup_head> [<mode>]
  local summary="$1" desc="$2" id="$3" branch="$4" target="$5" checkset="$6" head_oid="$7" sup_num="$8" sup_head="$9"
  local mode="${10:-open}"
  local greened
  # A standing banner leads the region when the base is an integration branch, so a
  # reviewer reads it before the diff: approving mints this phase into
  # integration/<convoy-id> and main does not move, the broader review running at
  # graduation. Set here where the base is known; the base: label on the PR list is
  # its counterpart (pr-status-label.sh mark-base). specs/tk-6bji7k.9/decision.md.
  # Single-quoted printf keeps the markdown backticks literal, never a command sub.
  case "$target" in
    integration/*)
      echo '> [!IMPORTANT]'
      printf '> **This pull request merges into `%s`, not `main`.**\n' "$target"
      echo '>'
      printf '%s\n' '> Approving it mints this phase into the convoy integration branch, and `main` does not move. The broader review runs at graduation, when the integration branch is carried to `main`.'
      echo
      ;;
  esac
  echo "## Summary"; echo
  if [ -n "$summary" ]; then strip_summary_heading "$summary"
  elif [ -n "$desc" ]; then printf '%s\n' "$desc"
  else printf 'Refinery handoff for `%s`.\n' "$id"; fi
  if [ -n "$summary" ] && [ -n "$desc" ]; then
    echo; echo "<details>"; echo "<summary>Dispatch — what this work was asked to do</summary>"; echo
    printf '%s\n' "$desc"
    echo; echo "</details>"
  fi
  echo; echo "## Refinery handoff"; echo
  printf -- '- Issue: `%s`\n- Source branch: `%s`\n- Target: `%s`\n' "$id" "$branch" "$target"
  greened=$(gates_of "$checkset" | paste -sd, -)
  if [ "$mode" = refresh ]; then
    if [ -n "$greened" ]; then
      printf -- '- Head `%.8s`; gates `%s`; see the PR checks for current status.\n' "$head_oid" "$greened"
    else
      printf -- '- Head `%.8s`; anchor declares no pre-open gate (`check_set=%s`).\n' "$head_oid" "$checkset"
    fi
  else
    if [ -n "$greened" ]; then
      printf -- '- Gates `%s` signed off pre-open at `%.8s`; PR opened green.\n' "$greened" "$head_oid"
    else
      printf -- '- Anchor declares no pre-open gate (`check_set=%s`); opened at `%.8s`.\n' "$checkset" "$head_oid"
    fi
  fi
  [ -n "$sup_num" ] && printf -- '- Supersedes #%s (closed unmerged at `%.8s`); re-implemented and re-gated at `%.8s`.\n' \
    "$sup_num" "$sup_head" "$head_oid"
  return 0
}

# The `## Summary` body carried inside the region already: the lines a compose put
# under `## Summary`, up to the dispatch `<details>` or the `## Refinery handoff`
# heading that follows. A post-open refresh compares this against the anchor's
# current pr_summary to tell a stale region (rework) from a current one, so it
# rewrites the region only when the published summary is actually behind — never
# on a PR that was merely opened, whose region still reads accurate. The compose
# writes one blank between the summary body and the next section; command
# substitution trims trailing newlines on both sides, so the comparison is exact.
prs_region_summary() { # <body-file>
  awk -v o="$PRS_MARK_OPEN" -v c="$PRS_MARK_CLOSE" '
    $0 == o { inreg = 1; next }
    $0 == c { inreg = 0; next }
    !inreg { next }
    !seen && $0 ~ /^##[ \t]+Summary[ \t]*$/ { seen = 1; skipblank = 1; next }
    seen && skipblank { skipblank = 0; if ($0 ~ /^[ \t]*$/) next }
    seen && !done {
      if ($0 == "<details>" || $0 ~ /^##[ \t]+Refinery handoff[ \t]*$/) { done = 1; next }
      n++; line[n] = $0
    }
    END { for (i = 1; i <= n; i++) print line[i] }
  ' "$1"
}

# What stands between the markers already, or empty when they are absent. The body
# this reads is \r-stripped first (GitHub re-wraps a stored body with CRLF).
prs_current_section() { # <body-file>
  awk -v o="$PRS_MARK_OPEN" -v c="$PRS_MARK_CLOSE" '
    $0 == o { f = 1; next }
    $0 == c { f = 0; next }
    f { print }
  ' "$1"
}

# 0 = exactly one well-formed pair (replace in place); 1 = neither marker (a body a
# create wrote before these markers existed); 2 = any other shape (a lone marker, a
# second pair, a close above its open) — a body cut into a shape this cannot reason
# about.
prs_marker_state() { # <body-file>
  local o c oi ci
  o=$(grep -cxF "$PRS_MARK_OPEN" "$1" 2>/dev/null || true)
  c=$(grep -cxF "$PRS_MARK_CLOSE" "$1" 2>/dev/null || true)
  [ "$o" = 0 ] && [ "$c" = 0 ] && return 1
  { [ "$o" = 1 ] && [ "$c" = 1 ]; } || return 2
  oi=$(grep -nxF "$PRS_MARK_OPEN" "$1" | head -1 | cut -d: -f1)
  ci=$(grep -nxF "$PRS_MARK_CLOSE" "$1" | head -1 | cut -d: -f1)
  [ "$oi" -lt "$ci" ] || return 2
  return 0
}

# The body with the section replaced between its markers.
prs_splice_in_place() { # <body-file> <section-file> <out-file>
  awk -v o="$PRS_MARK_OPEN" -v c="$PRS_MARK_CLOSE" -v s="$2" '
    $0 == o { print; while ((getline l < s) > 0) print l; close(s); f = 1; next }
    $0 == c { print; f = 0; next }
    !f { print }
  ' "$1" > "$3"
}

# Establish the region in a body a create wrote before these markers existed. That
# create put the managed content first — `## Summary`, the demoted dispatch, then
# the `## Refinery handoff` bullet block — so wrap a freshly composed region in the
# markers over exactly that prefix and keep whatever follows it: an operator note,
# pr-stack's own marked section. The handoff block is contiguous (compose writes no
# blank between its bullets), so the first line after it that is not a `- ` bullet
# ends the prefix. Exits nonzero, having written nothing usable, when the body does
# not carry that prefix (no `## Summary`, or no `## Refinery handoff` after it), so
# the caller holds rather than mangle a shape it did not write.
prs_establish_region() { # <body-file> <section-file> <out-file>
  awk -v o="$PRS_MARK_OPEN" -v c="$PRS_MARK_CLOSE" -v s="$2" '
    BEGIN { state = "lead"; opened = 0 }
    state == "lead" {
      if ($0 ~ /^##[ \t]+Summary[ \t]*$/) {
        print o
        while ((getline line < s) > 0) print line
        close(s)
        print c
        opened = 1
        state = "to_handoff"
        next
      }
      print; next                        # keep anything before the managed prefix
    }
    state == "to_handoff" {               # drop the stale summary/dispatch block
      if ($0 ~ /^##[ \t]+Refinery handoff[ \t]*$/) state = "handoff_head"
      next
    }
    state == "handoff_head" {
      if ($0 ~ /^[ \t]*$/) next           # the blank after the handoff heading
      if ($0 ~ /^-[ \t]/) { state = "bullets"; next }
      state = "tail"; print; next         # no bullets — everything here is tail
    }
    state == "bullets" {                  # the contiguous handoff bullet block
      if ($0 ~ /^-[ \t]/) next
      state = "tail"; print; next         # first non-bullet ends the managed prefix
    }
    state == "tail" { print }
    END { exit (opened && state != "to_handoff") ? 0 : 1 }
  ' "$1" > "$3"
}
