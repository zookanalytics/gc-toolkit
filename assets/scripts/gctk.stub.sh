#!/usr/bin/env bash
# gctk.stub.sh — `gctk bead`, for the suites of the scripts that call it. A
# suite points GCTK_BIN at this file, so a caller's write goes through the
# suite's own `gc`, and the caller's cases decide what it does with each exit.
# services/gctk/internal/cli/bead_test.go proves the command reads a write that
# exited 0 and did not land as a miss; a caller's suite names the miss here
# instead of faking a lost write.
#
# `bead <verb> <args>...` drops the command's own --verify and
# --verify-key <key>, runs `gc bd <verb> <args>...` and exits with its status.
# A create asked to --verify asks gc bd for --json, as the command does.
# GCTK_STUB_MISS lists, space-separated, the calls that exit 3, as a write that
# exited 0 and did not read back: `all`, a verb (update, close, create, dep), a
# verb and the first id it names, as <verb>:<id>, or ~<text>, a call whose
# arguments carry <text>, for two writes to one bead. A missed create runs, and
# its reply passes through, since the bead it filed is one its caller learns of
# from that reply. Any other missed call runs no write. Each call is appended to
# GCTK_STUB_LOG, when it is set, as one line of its arguments, each followed by
# "|". Any other subcommand goes to GCTK_STUB_NEXT when it names a binary, and
# is refused with exit 2 otherwise, as a binary without it refuses it.
set -u

if [ -n "${GCTK_STUB_LOG:-}" ]; then
  { for a in "$@"; do printf '%s|' "$a"; done; echo; } >> "$GCTK_STUB_LOG"
fi

if [ "${1:-}" != bead ]; then
  [ -z "${GCTK_STUB_NEXT:-}" ] || exec "$GCTK_STUB_NEXT" "$@"
  echo "gctk.stub.sh: unknown subcommand '${1:-}'" >&2
  exit 2
fi
shift

verb="${1:-}"
case "$verb" in
  update|close|create) shift ;;
  dep) shift; verb="dep ${1:-}"; shift || true ;;
  *) echo "gctk.stub.sh: unknown verb '$verb'" >&2; exit 2 ;;
esac

args=(); verify=""; json=""
while [ $# -gt 0 ]; do
  case "$1" in
    --verify) verify=1 ;;
    --verify-key) verify=1; shift ;;
    --verify-key=*) verify=1 ;;
    *) [ "$1" != --json ] || json=1; args+=("$1") ;;
  esac
  shift
done
[ "$verb" != create ] || [ -z "$verify" ] || [ -n "$json" ] || args+=(--json)

first="${args[0]:-}"
case "$first" in -*) first="" ;; esac
miss=""
for m in ${GCTK_STUB_MISS:-}; do
  case "$m" in
    all|"${verb%% *}") miss=1 ;;
    "${verb%% *}:$first") [ -n "$first" ] && miss=1 ;;
    "~"?*) case " ${args[*]} " in *"${m#\~}"*) miss=1 ;; esac ;;
  esac
done

if [ -n "$miss" ]; then
  if [ "$verb" = create ]; then
    gc bd create ${args[@]+"${args[@]}"} || exit $?
  fi
  echo "gctk bead $verb: gc bd exited 0, but the write did not read back, and nothing was repaired (gctk.stub.sh: GCTK_STUB_MISS)" >&2
  exit 3
fi
# shellcheck disable=SC2086  # $verb is one or two words
gc bd $verb ${args[@]+"${args[@]}"}
