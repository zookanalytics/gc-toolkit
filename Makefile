# The repository's commands, run from its root.
#
#   make test             every test in the repository
#   make test-affected    the tests the change since BASE can affect
#   make build            compile every Go package
#   make lint             the repository's lint, over the change since BASE
#
# tools/test.sh says what each test command runs, and tools/lint-change.sh what
# make lint runs.
#
# BASE is the ref a change is read against, origin/main unless given.
# RUN_TESTS_FLAGS holds options for tools/run-tests.sh, such as the -j and
# --seconds CI passes.
#
# Every command runs the Go release go.mod names, whichever go is first on
# PATH. GOTOOLCHAIN names the release, so a go of another release runs that one
# instead, and downloads it the first time. The release is go.mod's toolchain
# line, else go and the version on its go line, as actions/setup-go reads it for
# CI and go_release in assets/scripts/gc-build.sh for the city's binaries. A
# GOTOOLCHAIN given on make's command line wins.

BASE ?= origin/main
RUN_TESTS_FLAGS ?=

GO_RELEASE := $(shell awk '/^toolchain[ \t]/ && $$2 ~ /^go[0-9]+\.[0-9]+(\.[0-9]+|rc[0-9]+)$$/ { t = $$2 } /^go[ \t]/ && $$2 ~ /^[0-9]+\.[0-9]+\.[0-9]+$$/ { g = "go" $$2 } END { print (t != "" ? t : g) }' go.mod)
ifeq ($(GO_RELEASE),)
$(error go.mod names no Go release: no toolchain line such as "toolchain go1.27.4", and no go line such as "go 1.27.4")
endif
export GOTOOLCHAIN := $(GO_RELEASE)

.PHONY: test test-affected build lint

test:
	tools/test.sh all $(RUN_TESTS_FLAGS)

test-affected:
	tools/test.sh affected $(BASE) $(RUN_TESTS_FLAGS)

build:
	go build ./...

lint:
	tools/lint-change.sh $(BASE)
