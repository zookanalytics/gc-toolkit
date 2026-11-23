#!/usr/bin/env bash
# refuse.sh — the test floor. Every other name in this directory, and in
# harness/, is a symlink to this script, and each one refuses: it names the call
# on stderr and exits 127, the code of a command that is not installed.
#
# A hermetic test puts its stub gc, bd, gh or git in a directory at the front of
# PATH, and that directory is all that stands between the script under test and
# the real binary. It lives in the test's temp dir, so it can go while a script
# the test started is still running: a test killed by a signal its children do
# not get removes its temp dir from its EXIT trap. A PATH search that misses the
# stub finds the next directory instead. The real gc found there reaches the
# live city from the working directory, the real gh reaches GitHub, and the real
# git acts on the checkout.
#
# This directory is that next directory. A suite puts it at the front of PATH
# itself, by sourcing tools/test-floor.sh before anything else it runs, so the
# suite's own stubs land ahead of it whether tools/run-tests.sh runs the suite
# or a person does. The runner puts it at the front of PATH for every file it
# runs as well. harness_init in assets/scripts/test-harness.sh puts it, with
# harness/, directly beneath the stubs it writes. git sits in harness/ because
# only the harness stubs it; other suites run the real git over repositories
# they build. tools/test-floor.sh names this directory as ZDOTDIR too, so it
# holds no zsh startup file.
name="${0##*/}"
printf "test-floor: refused '%s %s': no stub answered it, and a test never reaches the real %s\n" \
  "$name" "${*:1:2}" "$name" >&2
exit 127
