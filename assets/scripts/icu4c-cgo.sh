#!/usr/bin/env bash
# icu4c-cgo.sh — the cgo flags a Go compile needs to find ICU on macOS. Sourced,
# never executed.
#
# services/helm links ICU through Dolt's go-icu-regex, a cgo package, so every
# compile of it needs ICU's headers. Without them the helm-svc build and the
# go vet in tools/lint.sh stop at `'unicode/regex.h' file not found`.
# Off macOS the system libicu is on the default search path. On macOS,
# Homebrew installs icu4c keg-only, so its headers and libraries are on no
# default search path, and neither the supervisor's environment nor an agent
# session sets a CGO flag. The flags are worked out here, once, and each caller
# hands them to its own compile.
#
#   icu4c_cgo_flags <prog>
#     Sets ICU4C_CGO_CPPFLAGS and ICU4C_CGO_LDFLAGS, starting from the caller's
#     CGO_CPPFLAGS and CGO_LDFLAGS. On macOS it asks `brew --prefix icu4c`.
#     When that prefix holds an include/ directory, it appends
#     -I<prefix>/include and -L<prefix>/lib and names the prefix on stdout.
#     Otherwise the flags stay as they were, and stderr names the missing
#     prerequisite. Off macOS brew is never asked. Each message starts with
#     <prog>. Returns 0.
#
# Callers: assets/scripts/gc-helm-build.sh and tools/lint.sh.

icu4c_cgo_flags() { # <prog>
    local prog="$1" prefix=""
    ICU4C_CGO_CPPFLAGS="${CGO_CPPFLAGS:-}"
    ICU4C_CGO_LDFLAGS="${CGO_LDFLAGS:-}"
    [ "$(uname -s 2>/dev/null || true)" = "Darwin" ] || return 0
    prefix="$(brew --prefix icu4c 2>/dev/null || true)"
    # brew prints a formula's prefix whether or not it is installed; an
    # include/ under it is what says icu4c is there.
    if [ -n "$prefix" ] && [ -d "$prefix/include" ]; then
        ICU4C_CGO_CPPFLAGS="${ICU4C_CGO_CPPFLAGS:+$ICU4C_CGO_CPPFLAGS }-I$prefix/include"
        ICU4C_CGO_LDFLAGS="${ICU4C_CGO_LDFLAGS:+$ICU4C_CGO_LDFLAGS }-L$prefix/lib"
        echo "$prog: cgo builds against icu4c at $prefix"
    else
        echo "$prog: found no installed icu4c through brew on PATH; go-icu-regex needs its headers to build on macOS (brew install icu4c)" >&2
    fi
    return 0
}
