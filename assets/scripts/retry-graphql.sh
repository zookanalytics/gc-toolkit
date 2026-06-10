#!/bin/sh
# retry-graphql.sh — run a command with bounded exponential backoff.
#
# Usage: retry-graphql.sh CMD [ARG...]
#
# Runs CMD with its arguments, retrying on failure with growing backoff
# (2s, 4s, 8s, capped at 8s). Returns 0 as soon as one attempt succeeds;
# returns non-zero only after the retry budget is exhausted — a genuine,
# persistent failure worth escalating.
#
# Motivation: GitHub GraphQL mutations (e.g. `gh pr ready`, which calls
# markPullRequestReadyForReview) intermittently return transient failures —
# a flaky 401, a timeout, a transient server error — that self-heal within
# seconds. A bare one-shot call strands state on such a blip (a fully-reviewed
# PR left in draft). Wrapping the call here lets a self-healing blip recover
# silently while a persistent failure still surfaces. POSIX sh, no new deps.
#
# Retry budget: the GC_GRAPHQL_RETRY_MAX env var is the single source of truth
# for the attempt count; the default literal appears exactly once, below.
set -eu

MAX_ATTEMPTS="${GC_GRAPHQL_RETRY_MAX:-5}"

if [ "$#" -eq 0 ]; then
  echo "usage: retry-graphql.sh CMD [ARG...]" >&2
  exit 2
fi

_attempt=1
_delay=2
while :; do
  if "$@"; then
    exit 0
  fi
  if [ "$_attempt" -ge "$MAX_ATTEMPTS" ]; then
    exit 1
  fi
  echo "retry-graphql: '$*' failed (attempt $_attempt/$MAX_ATTEMPTS); retrying in ${_delay}s" >&2
  sleep "$_delay"
  _attempt=$((_attempt + 1))
  _delay=$((_delay * 2))
  if [ "$_delay" -gt 8 ]; then
    _delay=8
  fi
done
