#!/usr/bin/env bash
# Hermetic test for doctor/check-demo-toolchain/run.sh. The check probes the
# host toolchain, so the test controls the host: a restricted PATH
# ($STUBS:/usr/bin:/bin) excludes the real node, gc, ffmpeg, and jq, and each
# case stubs back exactly what it means to be present. env -i keeps an ambient
# OPENAI_API_KEY or FFMPEG_BIN from leaking in.

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
TPATH="$STUBS:/usr/bin:/bin"

clear_stubs() { rm -f "$STUBS/node" "$STUBS/ffmpeg" "$STUBS/gc" "$STUBS/chromium"; }
stub_node() { printf '#!/bin/sh\necho v%s\n' "$1" > "$STUBS/node"; chmod +x "$STUBS/node"; }
stub_ffmpeg() { printf '#!/bin/sh\nexit 0\n' > "$STUBS/ffmpeg"; chmod +x "$STUBS/ffmpeg"; }
stub_chromium() { printf '#!/bin/sh\nexit 0\n' > "$STUBS/chromium"; chmod +x "$STUBS/chromium"; }
stub_gc_ss() { # stub_gc_ss <sprintshow-path>
  printf '#!/bin/sh\nif [ "$1" = rig ]; then printf %s\x27{"rigs":[{"name":"sprintshow","path":"%s"}]}\x27; fi\n' '' "$1" > "$STUBS/gc"
  chmod +x "$STUBS/gc"
}

# Fixtures: a browser cache with a chromium build, and one without.
BROWSERS_YES="$TMP/pw-yes"; mkdir -p "$BROWSERS_YES/chromium-1243"
BROWSERS_NO="$TMP/pw-no"; mkdir -p "$BROWSERS_NO"
# A HOME with the key in secrets.env, and one without.
HOME_KEY="$TMP/home-key"; mkdir -p "$HOME_KEY/.gc"; printf 'OPENAI_API_KEY=sk-fixture-value\n' > "$HOME_KEY/.gc/secrets.env"
HOME_BARE="$TMP/home-bare"; mkdir -p "$HOME_BARE"
# A sprintshow checkout whose ffmpeg-static binary is provisioned.
SS_FIX="$TMP/rigs/sprintshow"; mkdir -p "$SS_FIX/node_modules/ffmpeg-static"
printf '#!/bin/sh\n' > "$SS_FIX/node_modules/ffmpeg-static/ffmpeg"; chmod +x "$SS_FIX/node_modules/ffmpeg-static/ffmpeg"

run_check() { # run_check <home> <browsers-path> [KEY]
  local home="$1" pw="$2"
  if [ "$#" -ge 3 ]; then
    env -i PATH="$TPATH" HOME="$home" PLAYWRIGHT_BROWSERS_PATH="$pw" OPENAI_API_KEY="$3" bash "$CHECK" 2>&1
  else
    env -i PATH="$TPATH" HOME="$home" PLAYWRIGHT_BROWSERS_PATH="$pw" bash "$CHECK" 2>&1
  fi
}

# --- Case 1: everything present → OK -------------------------------------
clear_stubs; stub_node 22.18.0; stub_ffmpeg
OUT="$(run_check "$HOME_KEY" "$BROWSERS_YES" sk-env-value)"; RC=$?
eq "$RC" 0 "case1: all present exits OK"
has "$OUT" "OK: demo:capture toolchain ready" "case1: reports ready"
has "$OUT" "OPENAI_API_KEY (environment)" "case1: key from environment wins"

# --- Case 2: nothing present → Warning naming all four -------------------
clear_stubs
OUT="$(run_check "$HOME_BARE" "$BROWSERS_NO")"; RC=$?
eq "$RC" 1 "case2: all absent exits Warning"
has "$OUT" "Node not found" "case2: warns on Node"
has "$OUT" "No Chromium build found" "case2: warns on Chromium"
has "$OUT" "No ffmpeg resolvable" "case2: warns on ffmpeg"
has "$OUT" "OPENAI_API_KEY is not set" "case2: warns on key"

# --- Case 3: ffmpeg only via the engine's ffmpeg-static → OK -------------
clear_stubs; stub_node 24.18.0; stub_gc_ss "$SS_FIX"
OUT="$(run_check "$HOME_KEY" "$BROWSERS_YES" sk-env-value)"; RC=$?
eq "$RC" 0 "case3: ffmpeg-static fallback satisfies ffmpeg"
has "$OUT" "ffmpeg-static (sprintshow engine)" "case3: names the engine fallback"

# --- Case 4: key only in ~/.gc/secrets.env → OK, sourced from the file ---
clear_stubs; stub_node 22.18.0; stub_ffmpeg
OUT="$(run_check "$HOME_KEY" "$BROWSERS_YES")"; RC=$?   # no OPENAI_API_KEY in env
eq "$RC" 0 "case4: key from secrets.env satisfies the probe"
has "$OUT" "OPENAI_API_KEY (~/.gc/secrets.env)" "case4: names the secrets file"
hasnt "$OUT" "sk-fixture-value" "case4: never prints the key value"

# --- Case 5: node present but below the floor → Warning ------------------
clear_stubs; stub_node 20.5.0; stub_ffmpeg
OUT="$(run_check "$HOME_KEY" "$BROWSERS_YES" sk-env-value)"; RC=$?
eq "$RC" 1 "case5: old node exits Warning"
has "$OUT" "below the engine's floor" "case5: names the version floor"

# --- Case 6: no browser cache, but a host Chromium on PATH → OK ----------
clear_stubs; stub_node 22.18.0; stub_ffmpeg; stub_chromium
OUT="$(run_check "$HOME_KEY" "$BROWSERS_NO" sk-env-value)"; RC=$?
eq "$RC" 0 "case6: host Chromium on PATH satisfies the browser probe"
has "$OUT" "Chromium (host Chromium)" "case6: names the host browser source"

echo "check-demo-toolchain: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
