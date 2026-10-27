#!/usr/bin/env bash
# git-lib.sh — a branch's head on a repository's origin, read one way. Sourced,
# never executed.
#
# A script that pins a review to a branch's head, or resolves a branch's gates
# at it, reads that head from origin. Every read names the repository it runs
# in, since a caller's working directory can be another repository, whose
# origin carries none of the branch. Each head is taken from the line for the
# branch's exact ref: ls-remote matches each pattern it is given against the
# tail of a ref's name, so refs/heads/x also answers for refs/heads/a/refs/heads/x.
#
#   remote_branch_heads <repo> <branch>...
#       One ls-remote of <repo>'s origin for every <branch>. Prints
#       `<oid>\t<branch>` once for each branch origin carries, and nothing for
#       a branch it does not carry. Non-zero, with nothing printed, when origin
#       does not answer, so a caller can tell a branch origin lacks from a read
#       that failed.
#   remote_branch_head <repo> <branch>
#       The id of <branch>'s head on <repo>'s origin. Non-zero, with nothing
#       printed, when origin does not answer or does not carry the branch.
#
# Every git call runs through git_remote_run, which runs it as it is. A caller
# that bounds its calls redefines it after sourcing this file, as
# liveness-sweep.sh does with its per-call timeout.
#
# Callers: gate-ensure.sh, signoff.sh, converse-rework.sh, liveness-sweep.sh.
# Test: git-lib.test.sh.

git_remote_run() { "$@"; }

remote_branch_heads() { # <repo> <branch>...
  local repo="${1:-}" b listing want=""
  local refs=()
  [ -n "$repo" ] || return 1
  shift
  for b in "$@"; do
    [ -n "$b" ] || continue
    refs+=("refs/heads/$b")
    want="$want$b"$'\037'
  done
  [ "${#refs[@]}" -gt 0 ] || return 1
  listing=$(git_remote_run git -C "$repo" ls-remote origin "${refs[@]}" 2>/dev/null </dev/null) || return 1
  printf '%s\n' "$listing" | awk -F'\t' -v want="$want" '
    BEGIN { n = split(want, b, "\037"); for (i = 1; i <= n; i++) if (b[i] != "") ref["refs/heads/" b[i]] = b[i] }
    ($2 in ref) && !($2 in seen) { seen[$2] = 1; print $1 "\t" ref[$2] }'
}

remote_branch_head() { # <repo> <branch>
  local line
  [ -n "${2:-}" ] || return 1
  line=$(remote_branch_heads "${1:-}" "$2") || return 1
  [ -n "$line" ] || return 1
  printf '%s\n' "${line%%$'\t'*}"
}
