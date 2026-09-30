#!/usr/bin/env bash
# doctor/check-demo-toolchain — the demo:capture toolchain is resolvable.
# A narrated demo needs four things at capture time: Node to run the SprintShow
# engine, a Chromium build to drive, ffmpeg to assemble, and OPENAI_API_KEY to
# voice the steps; delivering the clip inline to its PR needs a fifth, gh >= 2.99.0
# for 'gh pr comment --attach'. Each is fetched on demand rather than assumed, so
# this check reports which are in place — it is a readiness heads-up, not an
# invariant. Every gap is a WARNING: a missing browser or ffmpeg fails the capture
# until provisioned, a missing key downgrades it to the documented silent+captioned
# result, and a missing or too-old gh means a produced clip cannot be delivered
# inline — but none is a structural defect. It goes green once all five resolve.
# Read-only, probes the host only. Exit 0=OK 1=Warning 2=Error. stdout: a
# message line, then "  - detail" lines. Never prints the key's value.

set -u

warnings=()
detail() { local v; for v in "$@"; do printf '  - %s\n' "$v"; done; }

# --- Node >= 22.18 (the engine's floor) ----------------------------------
node_ok=""
if command -v node >/dev/null 2>&1; then
    nodever=$(node --version 2>/dev/null | sed 's/^v//')
    major=${nodever%%.*}
    rest=${nodever#*.}; minor=${rest%%.*}
    case "$major" in ''|*[!0-9]*) major=0 ;; esac
    case "$minor" in ''|*[!0-9]*) minor=0 ;; esac
    if [ "$major" -gt 22 ] || { [ "$major" -eq 22 ] && [ "$minor" -ge 18 ]; }; then
        node_ok="$nodever"
    else
        warnings+=("Node $nodever is below the engine's floor of 22.18 — upgrade Node (the engine strips types natively and needs it).")
    fi
else
    warnings+=("Node not found — the SprintShow engine needs Node >= 22.18 to run.")
fi

# --- A Chromium build: the Playwright cache, or one on PATH ---------------
browser_ok=""
pw_cache="${PLAYWRIGHT_BROWSERS_PATH:-$HOME/.cache/ms-playwright}"
if ls -d "$pw_cache"/chromium* >/dev/null 2>&1; then
    browser_ok="Playwright cache"
elif command -v chromium >/dev/null 2>&1 || command -v chromium-browser >/dev/null 2>&1 \
     || command -v google-chrome >/dev/null 2>&1; then
    browser_ok="host Chromium"
fi
[ -n "$browser_ok" ] || warnings+=("No Chromium build found (looked in $pw_cache and on PATH) — install one: npx playwright install chromium-headless-shell (add --with-deps on a bare host).")

# --- ffmpeg: a host binary, FFMPEG_BIN, or the engine's ffmpeg-static -----
ffmpeg_ok=""
if command -v ffmpeg >/dev/null 2>&1; then
    ffmpeg_ok="host ffmpeg"
elif [ -n "${FFMPEG_BIN:-}" ] && [ -x "${FFMPEG_BIN:-}" ]; then
    ffmpeg_ok="FFMPEG_BIN"
elif command -v gc >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    ss_dir=$(gc rig list --json 2>/dev/null | jq -r '.rigs[]? | select(.name=="sprintshow") | .path // empty' 2>/dev/null | head -1)
    if [ -n "$ss_dir" ] && [ -x "$ss_dir/node_modules/ffmpeg-static/ffmpeg" ]; then
        ffmpeg_ok="ffmpeg-static (sprintshow engine)"
    fi
fi
[ -n "$ffmpeg_ok" ] || warnings+=("No ffmpeg resolvable — none on PATH, FFMPEG_BIN unset, and the engine's ffmpeg-static is not provisioned. Install a host ffmpeg, or run 'npm run provision:ffmpeg' in the engine checkout (npm >= 12 blocks its automatic install script).")

# --- OPENAI_API_KEY: the environment, or the host secrets file -----------
# Presence only; the value is never read into output.
key_ok=""
if [ -n "${OPENAI_API_KEY:-}" ]; then
    key_ok="environment"
elif [ -f "$HOME/.gc/secrets.env" ] && grep -q '^OPENAI_API_KEY=..*' "$HOME/.gc/secrets.env" 2>/dev/null; then
    key_ok="~/.gc/secrets.env"
fi
[ -n "$key_ok" ] || warnings+=("OPENAI_API_KEY is not set (checked the environment and ~/.gc/secrets.env) — narration falls back to a SILENT, captioned clip, which is the documented degradation, not a failure. Place the key to voice the steps.")

# --- gh >= 2.99.0: the floor for inline PR delivery ('gh pr comment --attach') ---
# 'gh pr comment --attach' (gh 2.99.0) uploads a clip to GitHub's user-attachments
# CDN and renders it inline, which is how a produced demo is delivered to its PR
# without committing it. Compare major.minor numerically: 2.101 is NOT below 2.99.
gh_ok=""
if command -v gh >/dev/null 2>&1; then
    ghver=$(gh --version 2>/dev/null | sed -n 's/^gh version \([0-9][0-9.]*\).*/\1/p' | head -1)
    ghmajor=${ghver%%.*}
    ghrest=${ghver#*.}; ghminor=${ghrest%%.*}
    case "$ghmajor" in ''|*[!0-9]*) ghmajor=0 ;; esac
    case "$ghminor" in ''|*[!0-9]*) ghminor=0 ;; esac
    if [ "$ghmajor" -gt 2 ] || { [ "$ghmajor" -eq 2 ] && [ "$ghminor" -ge 99 ]; }; then
        gh_ok="$ghver"
    else
        warnings+=("gh ${ghver:-unknown} is below 2.99.0 — 'gh pr comment --attach' (inline demo delivery to a PR) is unavailable; upgrade gh.")
    fi
else
    warnings+=("gh not found — 'gh pr comment --attach' delivers a produced demo inline to its PR; install gh >= 2.99.0.")
fi

if [ "${#warnings[@]}" -ne 0 ]; then
    echo "demo:capture toolchain incomplete — ${#warnings[@]} item(s) to provision before a narrated capture and inline delivery"
    detail "${warnings[@]}"
    exit 1
fi
echo "OK: demo:capture toolchain ready — Node $node_ok, Chromium ($browser_ok), ffmpeg ($ffmpeg_ok), OPENAI_API_KEY ($key_ok), gh $gh_ok"
exit 0
