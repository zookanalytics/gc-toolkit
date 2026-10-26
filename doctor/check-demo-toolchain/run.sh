#!/usr/bin/env bash
# doctor/check-demo-toolchain — the demo:capture toolchain is resolvable.
# A narrated demo needs Node to run the SprintShow engine, ffmpeg to assemble,
# and OPENAI_API_KEY to voice the steps at capture time. Delivering the clip
# inline to its PR also needs gh >= 2.99.0 for 'gh pr comment --attach'. This
# check reports which of them are in place, as a readiness heads-up rather than
# an invariant. Every gap is a WARNING: a missing ffmpeg fails the capture until
# provisioned, a missing key downgrades it to the documented silent+captioned
# result, and a missing or too-old gh means a produced clip cannot be delivered
# inline, but none is a structural defect. It also reports whether
# VERCEL_AUTOMATION_BYPASS_SECRET reaches this environment, and warns only when
# the secrets file holds that key and this environment lacks it. It goes green
# once every item resolves.
# The browser is not an item: rig-demo-capture.sh installs it on every capture,
# through the engine's own Playwright.
# Read-only, probes the host only. Exit 0=OK 1=Warning 2=Error. stdout: a
# message line, then "  - detail" lines: the warnings, then notes that report a
# state and are no item. Never prints a key's value.

set -u

warnings=(); notes=()
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

# --- Keys: in this environment, where the engine reads them ----------------
# A session inherits a key from the supervisor's service env. gascity writes
# that env when 'gc supervisor install' writes the service file, and fills a key
# from ${GC_HOME:-~/.gc}/secrets.env only when the key is a provider credential,
# by a prefix such as OPENAI_, or when GC_SUPERVISOR_ENV names it in the
# environment the install runs in. The supervisor hands a key without such a
# prefix on to its sessions only while its own GC_SUPERVISOR_ENV names it, and
# the service env keeps that list only when the list names GC_SUPERVISOR_ENV
# too. A key placed in the file after the write reaches no session until the
# file is written again. The file probe follows gascity's dotenv grammar: an
# optional 'export ', spaces around '=', and a non-empty value, quoted or not.
# Presence only; no value is ever read into output.
secrets_file="${GC_HOME:-$HOME/.gc}/secrets.env"
in_secrets_file() { # in_secrets_file <KEY>: the file sets KEY to a non-empty value
    grep -Eq "^[[:space:]]*(export[[:space:]]+)?$1[[:space:]]*=[[:space:]]*([^\"'[:space:]]|\"[^\"]|'[^'])" "$secrets_file" 2>/dev/null
}
# opted_in <KEY>: this environment's GC_SUPERVISOR_ENV names KEY. gascity splits
# the list on commas, semicolons and whitespace.
opted_in() {
    local list="${GC_SUPERVISOR_ENV:-}"
    list=${list//[,;[:space:]]/ }
    case " $list " in
        *" $1 "*) return 0 ;;
    esac
    return 1
}

# --- OPENAI_API_KEY: voices the steps --------------------------------------
key_ok=""
if [ -n "${OPENAI_API_KEY:-}" ]; then
    key_ok="environment"
elif in_secrets_file OPENAI_API_KEY; then
    warnings+=("OPENAI_API_KEY is in $secrets_file but not in this environment, so a capture here is SILENT and captioned. Sessions get the key from the supervisor's service env, which gascity writes from that file when 'gc supervisor install' runs. Run it (it restarts the supervisor); sessions started after that carry the key.")
else
    warnings+=("OPENAI_API_KEY is not set (checked the environment and $secrets_file) — narration falls back to a SILENT, captioned clip, which is the documented degradation, not a failure. To voice the steps, put the key in $secrets_file and run 'gc supervisor install'.")
fi

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

# --- VERCEL_AUTOMATION_BYPASS_SECRET: reported, an item only when stranded --
# Vercel's Protection Bypass for Automation key, which lets automation past a
# deployment's Vercel sign-in. A city that serves no app behind that sign-in has
# no use for it, so a key set nowhere is a note and no item. A key the secrets
# file holds and this environment lacks is an item: it has no provider prefix,
# so it reaches sessions only through the GC_SUPERVISOR_ENV opt-in above.
vercel_key=VERCEL_AUTOMATION_BYPASS_SECRET
vercel_state=""
if [ -n "${VERCEL_AUTOMATION_BYPASS_SECRET:-}" ]; then
    vercel_state="environment"
elif in_secrets_file "$vercel_key" && opted_in "$vercel_key"; then
    warnings+=("$vercel_key is in $secrets_file and GC_SUPERVISOR_ENV here names it, but the key is not in this environment. gascity copies the key from that file into the supervisor's service env when 'gc supervisor install' runs with GC_SUPERVISOR_ENV naming it, so run the install again; sessions started after that carry the key.")
elif in_secrets_file "$vercel_key"; then
    warnings+=("$vercel_key is in $secrets_file but not in this environment. The key has no provider prefix, so gascity carries it from that file into sessions only when GC_SUPERVISOR_ENV names it in the environment 'gc supervisor install' runs in, and GC_SUPERVISOR_ENV here does not name it. Add the key, and GC_SUPERVISOR_ENV itself, to the GC_SUPERVISOR_ENV list the city's setup gives that install, then run the install again; sessions started after that carry the key.")
else
    vercel_state="not set"
    notes+=("$vercel_key is not set (checked the environment and $secrets_file). A key set nowhere is reported and not counted as an item.")
fi

if [ "${#warnings[@]}" -ne 0 ]; then
    echo "demo:capture toolchain incomplete — ${#warnings[@]} item(s) to provision"
    detail "${warnings[@]}"
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
echo "OK: demo:capture toolchain ready — Node $node_ok, ffmpeg ($ffmpeg_ok), OPENAI_API_KEY ($key_ok), gh $gh_ok, $vercel_key ($vercel_state)"
detail ${notes[@]+"${notes[@]}"}
exit 0
