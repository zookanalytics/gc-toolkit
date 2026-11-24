# The repository's two test commands, run from its root. tools/test.sh says
# what each one runs.
#
#   make test             every test in the repository
#   make test-affected    the tests the change since BASE can affect
#
# BASE is the ref a change is read against, origin/main unless given.
# RUN_TESTS_FLAGS holds options for tools/run-tests.sh, such as the -j and
# --seconds CI passes.

BASE ?= origin/main
RUN_TESTS_FLAGS ?=

.PHONY: test test-affected

test:
	tools/test.sh all $(RUN_TESTS_FLAGS)

test-affected:
	tools/test.sh affected $(BASE) $(RUN_TESTS_FLAGS)
