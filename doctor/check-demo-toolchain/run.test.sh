#!/usr/bin/env bash
# Hermetic test for doctor/check-demo-toolchain/run.sh. The check probes the
# host toolchain, so the test controls the host: the check runs with a PATH of
# only a stub dir plus a minimal symlink farm of the coreutils it calls, never
# /usr/bin, so no host node, gc, ffmpeg, jq, uname, or Chromium is reachable and
# each case stubs back exactly what it means to be present. env -i keeps an
# ambient OPENAI_API_KEY, FFMPEG_BIN, GC_HOME, XDG_CACHE_HOME, or
# PLAYWRIGHT_BROWSERS_PATH from leaking in.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-check-demo-toolchain-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2')" ;; *) ok "$3" ;; esac; }

STUBS="$TMP/bin"; mkdir -p "$STUBS"
# jq is a linuxbrew binary, off the minimal PATH; the check needs it only on the
# ffmpeg-static branch (alongside gc), so symlink the real one in.
if command -v jq >/dev/null 2>&1; then ln -s "$(command -v jq)" "$STUBS/jq"; fi
# The check's PATH carries only the stub dir and a symlink farm of the coreutils
# it calls — never /usr/bin. A host Chromium (google-chrome / chromium-browser)
# lives in /usr/bin on CI runners, and the host's uname would pick the
# platform's cache layout for every case, so neither is reachable unless a case
# stubs it. With no uname the check takes its Linux layout.
COREUTILS="$TMP/coreutils"; mkdir -p "$COREUTILS"
for c in bash sed ls grep head; do
  p="$(command -v "$c")" || { echo "test setup: required coreutil '$c' not found" >&2; exit 2; }
  ln -s "$p" "$COREUTILS/$c"
done
TPATH="$STUBS:$COREUTILS"

clear_stubs() { rm -f "$STUBS/node" "$STUBS/ffmpeg" "$STUBS/gc" "$STUBS/chromium" "$STUBS/gh" "$STUBS/uname"; }
stub_node() { printf '#!/bin/sh\necho v%s\n' "$1" > "$STUBS/node"; chmod +x "$STUBS/node"; }
stub_ffmpeg() { printf '#!/bin/sh\nexit 0\n' > "$STUBS/ffmpeg"; chmod +x "$STUBS/ffmpeg"; }
stub_chromium() { printf '#!/bin/sh\nexit 0\n' > "$STUBS/chromium"; chmod +x "$STUBS/chromium"; }
stub_gh() { printf '#!/bin/sh\necho "gh version %s (2026-01-01)"\n' "$1" > "$STUBS/gh"; chmod +x "$STUBS/gh"; }
stub_uname() { printf '#!/bin/sh\necho %s\n' "$1" > "$STUBS/uname"; chmod +x "$STUBS/uname"; }
GC_CALLS="$TMP/gc-calls"
stub_gc_ss() { # stub_gc_ss <sprintshow-path> — each call appends its arguments to $GC_CALLS
  printf '#!/bin/sh\necho "$*" >> "%s"\nif [ "$1" = rig ]; then printf %s\x27{"rigs":[{"name":"sprintshow","path":"%s"}]}\x27; fi\n' "$GC_CALLS" '' "$1" > "$STUBS/gc"
  chmod +x "$STUBS/gc"
}
# Every tool but the browser and the key in place, so a case's one warning is
# the item it is about.
stub_rest() { clear_stubs; stub_node 22.18.0; stub_ffmpeg; stub_gh 2.99.0; }

# Fixtures: a browser cache with the headless-shell build a capture launches,
# one holding only the full chromium build, and an empty one.
BROWSERS_YES="$TMP/pw-yes"; mkdir -p "$BROWSERS_YES/chromium_headless_shell-1243"
BROWSERS_FULL="$TMP/pw-full"; mkdir -p "$BROWSERS_FULL/chromium-1243"
BROWSERS_NO="$TMP/pw-no"; mkdir -p "$BROWSERS_NO"
# A HOME with the key in .gc/secrets.env, and one without.
HOME_KEY="$TMP/home-key"; mkdir -p "$HOME_KEY/.gc"; printf 'OPENAI_API_KEY=sk-fixture-value\n' > "$HOME_KEY/.gc/secrets.env"
HOME_BARE="$TMP/home-bare"; mkdir -p "$HOME_BARE"
# HOMEs holding the build at Playwright's macOS default and at its Linux default.
HOME_MAC="$TMP/home-mac"; mkdir -p "$HOME_MAC/Library/Caches/ms-playwright/chromium_headless_shell-1243"
HOME_LINUX="$TMP/home-linux"; mkdir -p "$HOME_LINUX/.cache/ms-playwright/chromium_headless_shell-1243"
XDG_YES="$TMP/xdg-yes"; mkdir -p "$XDG_YES/ms-playwright/chromium_headless_shell-1243"
XDG_NO="$TMP/xdg-no"; mkdir -p "$XDG_NO"
# A sprintshow checkout whose ffmpeg-static binary is provisioned.
SS_FIX="$TMP/rigs/sprintshow"; mkdir -p "$SS_FIX/node_modules/ffmpeg-static"
printf '#!/bin/sh\n' > "$SS_FIX/node_modules/ffmpeg-static/ffmpeg"; chmod +x "$SS_FIX/node_modules/ffmpeg-static/ffmpeg"
# Checkouts for PLAYWRIGHT_BROWSERS_PATH=0, under which Playwright keeps its
# browsers in .local-browsers inside the playwright-core package the engine
# loads: an engine with the build (and ffmpeg-static), one without the build,
# one whose deps are not installed, one whose playwright carries its own nested
# playwright-core, and a rig whose package.json names some other app.
checkout() { # checkout <dir-name> <package name> — a checkout root with its package.json
  mkdir -p "$TMP/$1"; printf '{"name":"%s"}\n' "$2" > "$TMP/$1/package.json"; printf '%s' "$TMP/$1"
}
pw_core() { # pw_core <package dir> [build] — a playwright-core package, holding the build when asked
  mkdir -p "$1"; printf '{"name":"playwright-core"}\n' > "$1/package.json"
  [ "$#" -lt 2 ] || mkdir -p "$1/.local-browsers/chromium_headless_shell-1243"
}
ENGINE_YES="$(checkout engine-yes @zookanalytics/sprintshow)"; pw_core "$ENGINE_YES/node_modules/playwright-core" build
mkdir -p "$ENGINE_YES/node_modules/ffmpeg-static"; cp "$SS_FIX/node_modules/ffmpeg-static/ffmpeg" "$ENGINE_YES/node_modules/ffmpeg-static/ffmpeg"
ENGINE_NOBUILD="$(checkout engine-nobuild @zookanalytics/sprintshow)"; pw_core "$ENGINE_NOBUILD/node_modules/playwright-core"
ENGINE_NODEPS="$(checkout engine-nodeps @zookanalytics/sprintshow)"
ENGINE_NESTED="$(checkout engine-nested @zookanalytics/sprintshow)"; pw_core "$ENGINE_NESTED/node_modules/playwright-core"
pw_core "$ENGINE_NESTED/node_modules/playwright/node_modules/playwright-core" build
NOT_ENGINE="$(checkout not-engine some-other-app)"; pw_core "$NOT_ENGINE/node_modules/playwright-core" build

gc_home() { # gc_home <name> <secrets.env content> — a GC_HOME dir holding that secrets.env
  mkdir -p "$TMP/gchome-$1"; printf '%s' "$2" > "$TMP/gchome-$1/secrets.env"; printf '%s' "$TMP/gchome-$1"
}

run_env() { # run_env [VAR=value ...] — the check under exactly these variables
  env -i PATH="$TPATH" "$@" bash "$CHECK" 2>&1
}
run_check() { # run_check <home> <browsers-path> [KEY]
  local home="$1" pw="$2"
  if [ "$#" -ge 3 ]; then
    run_env HOME="$home" PLAYWRIGHT_BROWSERS_PATH="$pw" OPENAI_API_KEY="$3"
  else
    run_env HOME="$home" PLAYWRIGHT_BROWSERS_PATH="$pw"
  fi
}

# --- Case 1: everything present → OK -------------------------------------
# gh 2.101.0 also proves the version compare is numeric: 2.101 is not below 2.99.
clear_stubs; stub_node 22.18.0; stub_ffmpeg; stub_gh 2.101.0
OUT="$(run_check "$HOME_KEY" "$BROWSERS_YES" sk-env-value)"; RC=$?
eq "$RC" 0 "case1: all present exits OK"
has "$OUT" "OK: demo:capture toolchain ready" "case1: reports ready"
has "$OUT" "Chromium (headless shell in $BROWSERS_YES)" "case1: names the browser cache it found"
has "$OUT" "OPENAI_API_KEY (environment)" "case1: key from environment wins"
has "$OUT" "gh 2.101.0" "case1: names the gh version (2.101 >= 2.99, numeric compare)"

# --- Case 2: nothing present → Warning naming all five -------------------
clear_stubs
OUT="$(run_check "$HOME_BARE" "$BROWSERS_NO")"; RC=$?
eq "$RC" 1 "case2: all absent exits Warning"
has "$OUT" "Node not found" "case2: warns on Node"
has "$OUT" "No chromium-headless-shell build in $BROWSERS_NO" "case2: warns on Chromium, naming the cache it read"
has "$OUT" "No ffmpeg resolvable" "case2: warns on ffmpeg"
has "$OUT" "OPENAI_API_KEY is not set (checked the environment and $HOME_BARE/.gc/secrets.env)" "case2: warns on key, naming the file it read"
has "$OUT" "put the key in $HOME_BARE/.gc/secrets.env and run 'gc supervisor install'" "case2: names where to place the key and how it reaches sessions"
has "$OUT" "gh not found" "case2: warns on gh"

# --- Case 3: ffmpeg only via the engine's ffmpeg-static → OK -------------
clear_stubs; stub_node 24.18.0; stub_gc_ss "$SS_FIX"; stub_gh 2.99.0
OUT="$(run_check "$HOME_KEY" "$BROWSERS_YES" sk-env-value)"; RC=$?
eq "$RC" 0 "case3: ffmpeg-static fallback satisfies ffmpeg"
has "$OUT" "ffmpeg-static (sprintshow engine)" "case3: names the engine fallback"

# --- Case 4: key only in $HOME/.gc/secrets.env → Warning: placed, not live ---
# With GC_HOME unset the file is $HOME/.gc/secrets.env, as gascity reads it. A
# key there but not in this environment reaches no session until the supervisor's
# service env is rewritten from it, so the capture here would be silent.
stub_rest
OUT="$(run_check "$HOME_KEY" "$BROWSERS_YES")"; RC=$?   # no OPENAI_API_KEY in env
eq "$RC" 1 "case4: key only in the secrets file exits Warning"
has "$OUT" "OPENAI_API_KEY is in $HOME_KEY/.gc/secrets.env but not in this environment" "case4: names the file that holds the key"
has "$OUT" "gc supervisor install" "case4: names the command that carries the key to sessions"
hasnt "$OUT" "is not set" "case4: does not report a placed key as missing"
hasnt "$OUT" "sk-fixture-value" "case4: never prints the key value"

# --- Case 5: node present but below the floor → Warning ------------------
clear_stubs; stub_node 20.5.0; stub_ffmpeg; stub_gh 2.99.0
OUT="$(run_check "$HOME_KEY" "$BROWSERS_YES" sk-env-value)"; RC=$?
eq "$RC" 1 "case5: old node exits Warning"
has "$OUT" "below the engine's floor" "case5: names the version floor"

# --- Case 6: no browser cache, a Chromium on PATH → still Warning --------
# Playwright launches its own build from its cache, never a browser on PATH.
stub_rest; stub_chromium
OUT="$(run_check "$HOME_KEY" "$BROWSERS_NO" sk-env-value)"; RC=$?
eq "$RC" 1 "case6: a Chromium on PATH does not satisfy the browser probe"
has "$OUT" "No chromium-headless-shell build in $BROWSERS_NO" "case6: names the missing headless-shell build"

# --- Case 7: gh below the delivery floor → Warning naming it -------------
clear_stubs; stub_node 22.18.0; stub_ffmpeg; stub_gh 2.98.0
OUT="$(run_check "$HOME_KEY" "$BROWSERS_YES" sk-env-value)"; RC=$?
eq "$RC" 1 "case7: old gh exits Warning"
has "$OUT" "gh 2.98.0 is below 2.99.0" "case7: names the gh floor with the version"
has "$OUT" "gh pr comment --attach" "case7: names the unavailable capability"

# --- Case 8: only the full chromium build → Warning ----------------------
# A headless launch needs chromium-headless-shell; the full build does not serve it.
stub_rest
OUT="$(run_check "$HOME_KEY" "$BROWSERS_FULL" sk-env-value)"; RC=$?
eq "$RC" 1 "case8: a cache with only the full chromium build exits Warning"
has "$OUT" "No chromium-headless-shell build in $BROWSERS_FULL" "case8: names the build a headless capture needs"

# --- Case 9: macOS reads ~/Library/Caches/ms-playwright → OK -------------
stub_rest; stub_uname Darwin
OUT="$(run_env HOME="$HOME_MAC" OPENAI_API_KEY=sk-env-value)"; RC=$?
eq "$RC" 0 "case9: macOS finds the build in ~/Library/Caches"
has "$OUT" "Chromium (headless shell in $HOME_MAC/Library/Caches/ms-playwright)" "case9: names the macOS cache"

# --- Case 10: macOS ignores a build under ~/.cache → Warning -------------
# Playwright on macOS never reads ~/.cache/ms-playwright.
stub_rest; stub_uname Darwin
OUT="$(run_env HOME="$HOME_LINUX" OPENAI_API_KEY=sk-env-value)"; RC=$?
eq "$RC" 1 "case10: macOS does not take a build under ~/.cache"
has "$OUT" "No chromium-headless-shell build in $HOME_LINUX/Library/Caches/ms-playwright" "case10: names the macOS cache it read"

# --- Case 11: Linux reads ~/.cache/ms-playwright → OK --------------------
stub_rest; stub_uname Linux
OUT="$(run_env HOME="$HOME_LINUX" OPENAI_API_KEY=sk-env-value)"; RC=$?
eq "$RC" 0 "case11: Linux finds the build in ~/.cache"
has "$OUT" "Chromium (headless shell in $HOME_LINUX/.cache/ms-playwright)" "case11: names the Linux cache"

# --- Case 12: Linux honors XDG_CACHE_HOME over ~/.cache ------------------
stub_rest; stub_uname Linux
OUT="$(run_env HOME="$HOME_BARE" XDG_CACHE_HOME="$XDG_YES" OPENAI_API_KEY=sk-env-value)"; RC=$?
eq "$RC" 0 "case12: XDG_CACHE_HOME holds the cache on Linux"
has "$OUT" "Chromium (headless shell in $XDG_YES/ms-playwright)" "case12: names the XDG cache"
OUT="$(run_env HOME="$HOME_LINUX" XDG_CACHE_HOME="$XDG_NO" OPENAI_API_KEY=sk-env-value)"; RC=$?
eq "$RC" 1 "case12: with XDG_CACHE_HOME set, a build under ~/.cache is not read"
has "$OUT" "No chromium-headless-shell build in $XDG_NO/ms-playwright" "case12: names the XDG cache it read"

# --- Case 13: PLAYWRIGHT_BROWSERS_PATH replaces the platform default -----
stub_rest; stub_uname Darwin
OUT="$(run_env HOME="$HOME_MAC" PLAYWRIGHT_BROWSERS_PATH="$BROWSERS_NO" OPENAI_API_KEY=sk-env-value)"; RC=$?
eq "$RC" 1 "case13: PLAYWRIGHT_BROWSERS_PATH wins over ~/Library/Caches"
has "$OUT" "No chromium-headless-shell build in $BROWSERS_NO" "case13: names the PLAYWRIGHT_BROWSERS_PATH cache"

# --- Case 14: the secrets file is $GC_HOME's, not $HOME/.gc's -------------
stub_rest
GCH="$(gc_home key 'OPENAI_API_KEY=sk-fixture-value
')"
OUT="$(run_env HOME="$HOME_BARE" GC_HOME="$GCH" PLAYWRIGHT_BROWSERS_PATH="$BROWSERS_YES")"; RC=$?
eq "$RC" 1 "case14: a key in GC_HOME's secrets file is placed, not live"
has "$OUT" "OPENAI_API_KEY is in $GCH/secrets.env but not in this environment" "case14: reads GC_HOME/secrets.env when HOME/.gc has none"
hasnt "$OUT" "sk-fixture-value" "case14: never prints the key value"
GCB="$(gc_home bare '')"
OUT="$(run_env HOME="$HOME_KEY" GC_HOME="$GCB" PLAYWRIGHT_BROWSERS_PATH="$BROWSERS_YES")"; RC=$?
eq "$RC" 1 "case14: a key only in HOME/.gc is not gascity's when GC_HOME is elsewhere"
has "$OUT" "OPENAI_API_KEY is not set (checked the environment and $GCB/secrets.env)" "case14: names GC_HOME's file as the one checked"

# --- Case 15: the file probe follows gascity's dotenv grammar ------------
stub_rest
for form in 'export OPENAI_API_KEY=sk-fixture-value' '  OPENAI_API_KEY = "sk-fixture-value"' "OPENAI_API_KEY='sk-fixture-value'"; do
  GCH="$(gc_home form "$form
")"
  OUT="$(run_env HOME="$HOME_BARE" GC_HOME="$GCH" PLAYWRIGHT_BROWSERS_PATH="$BROWSERS_YES")"
  has "$OUT" "OPENAI_API_KEY is in $GCH/secrets.env" "case15: a set key reads as placed: $form"
  hasnt "$OUT" "sk-fixture-value" "case15: never prints the key value: $form"
done
for form in 'OPENAI_API_KEY=' 'OPENAI_API_KEY=""' "OPENAI_API_KEY=''" '# OPENAI_API_KEY=sk-fixture-value' 'OPENAI_API_KEY_OLD=sk-fixture-value'; do
  GCH="$(gc_home form "$form
")"
  OUT="$(run_env HOME="$HOME_BARE" GC_HOME="$GCH" PLAYWRIGHT_BROWSERS_PATH="$BROWSERS_YES")"
  has "$OUT" "OPENAI_API_KEY is not set" "case15: no usable key reads as not set: $form"
done

# --- Case 16: PLAYWRIGHT_BROWSERS_PATH=0 reads the engine's .local-browsers ---
# Not a directory named "0", and not the platform cache: Playwright keeps the
# browsers inside the playwright-core package the engine loads.
stub_rest; stub_uname Darwin; stub_gc_ss "$ENGINE_YES"
OUT="$(run_env HOME="$HOME_BARE" PLAYWRIGHT_BROWSERS_PATH=0 OPENAI_API_KEY=sk-env-value)"; RC=$?
eq "$RC" 0 "case16: =0 finds the build in the engine's playwright-core/.local-browsers"
has "$OUT" "Chromium (headless shell in $ENGINE_YES/node_modules/playwright-core/.local-browsers)" "case16: names the engine's .local-browsers"
stub_gc_ss "$ENGINE_NOBUILD"
OUT="$(run_env HOME="$HOME_MAC" PLAYWRIGHT_BROWSERS_PATH=0 OPENAI_API_KEY=sk-env-value)"; RC=$?
eq "$RC" 1 "case16: =0 does not take a build in ~/Library/Caches"
has "$OUT" "No chromium-headless-shell build in $ENGINE_NOBUILD/node_modules/playwright-core/.local-browsers" "case16: names the .local-browsers it read"
has "$OUT" "install one: cd $ENGINE_NOBUILD && PLAYWRIGHT_BROWSERS_PATH=0 npx playwright install chromium-headless-shell" "case16: installs from the engine checkout under the same setting"
hasnt "$OUT" "build in 0" "case16: never reads 0 as a directory"

# --- Case 17: =0 follows Node to a playwright-core nested under playwright ---
# The engine's playwright package requires playwright-core, and Node takes the
# copy in playwright's own node_modules over the engine's.
stub_rest; stub_gc_ss "$ENGINE_NESTED"
OUT="$(run_env HOME="$HOME_BARE" PLAYWRIGHT_BROWSERS_PATH=0 OPENAI_API_KEY=sk-env-value)"; RC=$?
eq "$RC" 0 "case17: =0 takes the nested playwright-core Node loads first"
has "$OUT" "Chromium (headless shell in $ENGINE_NESTED/node_modules/playwright/node_modules/playwright-core/.local-browsers)" "case17: names the nested package's .local-browsers"

# --- Case 18: =0 with the engine's deps not installed → Warning ----------
stub_rest; stub_gc_ss "$ENGINE_NODEPS"
OUT="$(run_env HOME="$HOME_BARE" PLAYWRIGHT_BROWSERS_PATH=0 OPENAI_API_KEY=sk-env-value)"; RC=$?
eq "$RC" 1 "case18: =0 with no playwright-core installed exits Warning"
has "$OUT" "No playwright-core package in $ENGINE_NODEPS/node_modules" "case18: names the missing package"
has "$OUT" "cd $ENGINE_NODEPS && npm install && PLAYWRIGHT_BROWSERS_PATH=0 npx playwright install chromium-headless-shell" "case18: installs the deps, then the browser"

# --- Case 19: =0 with no local engine checkout → Warning: unchecked ------
# Without the checkout a capture runs npx's copy of the published engine, whose
# playwright-core this check cannot see. A sprintshow rig whose package.json
# names some other app is not the engine, so it is not looked in either.
stub_rest   # no gc, so no rig to find
OUT="$(run_env HOME="$HOME_BARE" PLAYWRIGHT_BROWSERS_PATH=0 OPENAI_API_KEY=sk-env-value)"; RC=$?
eq "$RC" 1 "case19: =0 with no engine checkout exits Warning"
has "$OUT" "which this check cannot see, so the browser is unchecked" "case19: says the browser is unchecked"
hasnt "$OUT" "No chromium-headless-shell build" "case19: does not report a browser it could not look for as missing"
stub_gc_ss "$NOT_ENGINE"
OUT="$(run_env HOME="$HOME_BARE" PLAYWRIGHT_BROWSERS_PATH=0 OPENAI_API_KEY=sk-env-value)"; RC=$?
eq "$RC" 1 "case19: a sprintshow rig that is not the engine exits Warning"
has "$OUT" "the browser is unchecked" "case19: does not look in a rig that is not the engine"

# --- Case 20: the browser and ffmpeg probes share one 'gc rig list' -------
# With no host ffmpeg, both probes need the sprintshow rig; the lookup runs once.
clear_stubs; stub_node 22.18.0; stub_gh 2.99.0; stub_gc_ss "$ENGINE_YES"
: > "$GC_CALLS"
OUT="$(run_env HOME="$HOME_BARE" PLAYWRIGHT_BROWSERS_PATH=0 OPENAI_API_KEY=sk-env-value)"; RC=$?
eq "$RC" 0 "case20: the engine checkout serves both the browser and ffmpeg"
has "$OUT" "ffmpeg (ffmpeg-static (sprintshow engine))" "case20: ffmpeg comes from the engine checkout"
eq "$(grep -c '^rig list' "$GC_CALLS")" 1 "case20: one 'gc rig list' call serves both probes"

echo "check-demo-toolchain: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
