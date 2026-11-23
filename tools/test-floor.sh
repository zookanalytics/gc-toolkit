#!/usr/bin/env bash
# test-floor.sh — puts the test floor, tools/test-floor, at the front of PATH.
# Sourced, never run. Every *.test.sh sources it right after it sets HERE,
# before anything else it runs, with the path from its own directory:
#
#   . "$HERE/../../tools/test-floor.sh" || exit 2
#
# A stub directory the suite puts in front of PATH afterwards then has the floor
# beneath it, where gc, bd and gh refuse (tools/test-floor/refuse.sh). That is
# the PATH tools/run-tests.sh gives every file, so a suite run directly resolves
# those names as a run through the runner does. A script under test that misses
# a stub, because the suite's temp dir went while it ran or because no stub
# answers the call, is refused there rather than handed the real gc, which
# reaches the live city from the working directory.
#
# The floor is ZDOTDIR as well, and it holds no zsh startup file, so a zsh the
# suite starts reads none of the host user's, such as a .zshenv that puts
# Homebrew's git and gh ahead of the stubs and of the floor. A zsh started under
# env -i loses ZDOTDIR and reads the passwd home's .zshenv, so it needs -f.
#
# A tree without the floor does not run: the suite exits 2 here.

_test_floor="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/test-floor" 2>/dev/null && pwd)" || _test_floor=""
if [ -z "$_test_floor" ] || [ ! -x "$_test_floor/gc" ]; then
  echo "test-floor.sh: no test floor beside ${BASH_SOURCE[0]}, so nothing would stand between a suite's stubs and the real gc, bd and gh; not running" >&2
  exit 2
fi
export PATH="$_test_floor:$PATH" ZDOTDIR="$_test_floor"
unset _test_floor
