#!/usr/bin/env bash
# validate-skills.sh — check that the on-disk vendored skills match
# skills.lock.toml.
#
# Validation checks (errors unless noted):
#   * manifest parses, schema = 1
#   * every entry has the required fields and a known fetcher
#   * no two entries share the same vendor_at
#   * every vendor_at exists on disk with a SKILL.md inside
#   * every SKILL.md frontmatter has 'name' and 'description'
#   * every vendored-from marker on disk under skills/ or agents/*/skills/
#     traces back to a manifest entry (no orphaned vendored skills)
#   * pins that are not a tag or full SHA -> warning, not error
#
# Usage:
#   tools/validate-skills.sh                     # validate this pack
#   tools/validate-skills.sh --manifest PATH --pack-root PATH

set -euo pipefail

MANIFEST=""
PACK_ROOT=""

usage() {
    cat <<'USAGE'
Usage: validate-skills.sh [options]

Options:
  --manifest PATH       Override the manifest path (default: <pack-root>/skills.lock.toml).
  --pack-root PATH      Override the pack root (default: parent of the script's directory).
  -h, --help            Print this help.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --manifest)     MANIFEST="$2"; shift 2 ;;
        --manifest=*)   MANIFEST="${1#--manifest=}"; shift ;;
        --pack-root)    PACK_ROOT="$2"; shift 2 ;;
        --pack-root=*)  PACK_ROOT="${1#--pack-root=}"; shift ;;
        -h|--help)      usage; exit 0 ;;
        *)              printf 'validate-skills: unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACK_ROOT="${PACK_ROOT:-$(dirname "$SCRIPT_DIR")}"
MANIFEST="${MANIFEST:-$PACK_ROOT/skills.lock.toml}"

if [[ ! -f "$MANIFEST" ]]; then
    printf 'validate-skills: manifest not found: %s\n' "$MANIFEST" >&2
    exit 1
fi

log()  { printf '[validate-skills] %s\n' "$*"; }
warn() { printf '[validate-skills] WARN: %s\n' "$*" >&2; }
err()  { printf '[validate-skills] ERROR: %s\n' "$*" >&2; }

ALLOWED_FETCHERS="git"
ERRORS=0

parse_manifest() {
    local file="$1"
    local section="top"
    local idx=-1
    local lineno=0
    local raw key val
    while IFS= read -r raw || [[ -n "$raw" ]]; do
        lineno=$((lineno + 1))
        local trimmed="${raw#"${raw%%[![:space:]]*}"}"
        case "$trimmed" in
            ""|"#"*) continue ;;
        esac
        if [[ "$trimmed" == "[[external]]" ]]; then
            idx=$((idx + 1))
            section="entry:$idx"
            printf 'ENTRY %d\n' "$idx"
            continue
        fi
        if [[ "$trimmed" == \[* ]]; then
            section="other"
            continue
        fi
        if [[ "$trimmed" =~ ^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            val="${BASH_REMATCH[2]}"
            if [[ "$val" != \"* ]]; then
                val="${val%%#*}"
            fi
            val="${val%"${val##*[![:space:]]}"}"
            if [[ "$val" == \"*\" ]]; then
                val="${val:1:${#val}-2}"
            fi
            case "$section" in
                top)        printf 'TOP_%s=%s\n' "$key" "$val" ;;
                entry:*)    printf '%s=%s\n' "$key" "$val" ;;
            esac
        else
            err "manifest line $lineno not recognized: $trimmed"
            ERRORS=$((ERRORS + 1))
        fi
    done < "$file"
}

ref_is_sha() {
    [[ "$1" =~ ^[0-9a-f]{40}$ ]]
}

ref_is_tag_or_sha() {
    ref_is_sha "$1" && return 0
    [[ "$1" =~ ^v?[0-9]+(\.[0-9]+)+([\.-][A-Za-z0-9._-]+)?$ ]]
}

verify_frontmatter() {
    local skill_md="$1"
    if [[ ! -f "$skill_md" ]]; then
        return 1
    fi
    local first
    first="$(sed -n '1p' "$skill_md")"
    [[ "$first" == "---" ]] || return 1
    local close_line
    close_line="$(awk 'NR>1 && /^---[[:space:]]*$/ { print NR; exit }' "$skill_md")"
    [[ -n "$close_line" ]] || return 1
    local fm
    fm="$(sed -n "2,$((close_line - 1))p" "$skill_md")"
    grep -qE '^name:[[:space:]]*\S' <<<"$fm" || return 1
    grep -qE '^description:[[:space:]]*\S' <<<"$fm" || return 1
    return 0
}

# Build a list of vendor_at paths we've seen (for collision + orphan checks).
declare -A SEEN_VENDOR_AT=()
declare -A MANIFEST_NAMES=()

current_idx=""
schema=""
total=0

reset_entry() { unset E_name E_source E_ref E_fetcher E_subpath E_vendor_at E_license E_notes; }

check_entry() {
    if [[ -z "$current_idx" ]]; then
        return 0
    fi
    total=$((total + 1))
    local entry_id="entry[$current_idx]${E_name:+ '$E_name'}"

    local missing=0
    for f in name source ref fetcher vendor_at license; do
        local var="E_$f"
        if [[ -z "${!var:-}" ]]; then
            err "$entry_id: required field missing: $f"
            ERRORS=$((ERRORS + 1))
            missing=1
        fi
    done
    if [[ $missing -ne 0 ]]; then
        reset_entry
        return 0
    fi

    if [[ -n "${MANIFEST_NAMES[$E_name]:-}" ]]; then
        err "$entry_id: duplicate name '$E_name' (also at ${MANIFEST_NAMES[$E_name]})"
        ERRORS=$((ERRORS + 1))
    else
        MANIFEST_NAMES["$E_name"]="$entry_id"
    fi

    case " $ALLOWED_FETCHERS " in
        *" $E_fetcher "*) ;;
        *)
            err "$entry_id: unsupported fetcher '$E_fetcher' (v1 supports: $ALLOWED_FETCHERS)"
            ERRORS=$((ERRORS + 1))
            ;;
    esac

    if [[ "$E_vendor_at" != */ ]]; then
        err "$entry_id: vendor_at must end in '/': $E_vendor_at"
        ERRORS=$((ERRORS + 1))
    fi
    if [[ "$E_vendor_at" == /* ]]; then
        err "$entry_id: vendor_at must be relative to the pack root: $E_vendor_at"
        ERRORS=$((ERRORS + 1))
    fi
    if [[ "$E_vendor_at" == *..* ]]; then
        err "$entry_id: vendor_at must not contain '..': $E_vendor_at"
        ERRORS=$((ERRORS + 1))
    fi

    if [[ -n "${SEEN_VENDOR_AT[$E_vendor_at]:-}" ]]; then
        err "$entry_id: vendor_at collides with ${SEEN_VENDOR_AT[$E_vendor_at]} ($E_vendor_at)"
        ERRORS=$((ERRORS + 1))
    else
        SEEN_VENDOR_AT["$E_vendor_at"]="$entry_id"
    fi

    if ! ref_is_tag_or_sha "$E_ref"; then
        warn "$entry_id: ref '$E_ref' is not a tag or full SHA — non-deterministic pin"
    fi

    # On-disk checks.
    local dest="$PACK_ROOT/${E_vendor_at%/}"
    if [[ ! -d "$dest" ]]; then
        err "$entry_id: vendor_at directory does not exist: $E_vendor_at"
        ERRORS=$((ERRORS + 1))
    elif [[ ! -f "$dest/SKILL.md" ]]; then
        err "$entry_id: SKILL.md missing under $E_vendor_at"
        ERRORS=$((ERRORS + 1))
    else
        if ! verify_frontmatter "$dest/SKILL.md"; then
            err "$entry_id: SKILL.md frontmatter invalid at $E_vendor_at (must have name + description)"
            ERRORS=$((ERRORS + 1))
        fi
    fi

    reset_entry
}

reset_entry

while IFS= read -r record; do
    if [[ "$record" == "ENTRY "* ]]; then
        check_entry
        current_idx="${record#ENTRY }"
        continue
    fi
    if [[ "$record" == "TOP_schema="* ]]; then
        schema="${record#TOP_schema=}"
        continue
    fi
    if [[ -z "$current_idx" ]]; then
        continue
    fi
    case "$record" in
        name=*)      E_name="${record#name=}" ;;
        source=*)    E_source="${record#source=}" ;;
        ref=*)       E_ref="${record#ref=}" ;;
        fetcher=*)   E_fetcher="${record#fetcher=}" ;;
        subpath=*)   E_subpath="${record#subpath=}" ;;
        vendor_at=*) E_vendor_at="${record#vendor_at=}" ;;
        license=*)   E_license="${record#license=}" ;;
        notes=*)     E_notes="${record#notes=}" ;;
        *)
            err "entry[$current_idx]: unknown field: ${record%%=*}"
            ERRORS=$((ERRORS + 1))
            ;;
    esac
done < <(parse_manifest "$MANIFEST")
check_entry

if [[ -z "$schema" ]]; then
    err "manifest missing 'schema' top-level field"
    ERRORS=$((ERRORS + 1))
elif [[ "$schema" != "1" ]]; then
    err "unsupported manifest schema: $schema (expected 1)"
    ERRORS=$((ERRORS + 1))
fi

# Orphan check: every on-disk vendored-from marker must trace to a manifest entry.
# Search skills/ and agents/*/skills/ for SKILL.md files carrying the marker.
orphan_check() {
    local roots=()
    [[ -d "$PACK_ROOT/skills" ]] && roots+=("$PACK_ROOT/skills")
    if [[ -d "$PACK_ROOT/agents" ]]; then
        # Each agent's skills dir, if present.
        while IFS= read -r -d '' agent_skills; do
            roots+=("$agent_skills")
        done < <(find "$PACK_ROOT/agents" -mindepth 2 -maxdepth 2 -type d -name skills -print0 2>/dev/null)
    fi
    if [[ ${#roots[@]} -eq 0 ]]; then
        return 0
    fi
    while IFS= read -r -d '' skill_md; do
        if ! grep -qE '^<!-- vendored from .+ by skills\.lock\.toml -->$' "$skill_md"; then
            continue
        fi
        # Compute vendor_at relative to PACK_ROOT, with trailing slash.
        local dir relpath
        dir="$(dirname "$skill_md")"
        relpath="${dir#"$PACK_ROOT/"}/"
        if [[ -z "${SEEN_VENDOR_AT[$relpath]:-}" ]]; then
            err "orphan: $relpath has a vendored-from marker but is not listed in $MANIFEST"
            ERRORS=$((ERRORS + 1))
        fi
    done < <(find "${roots[@]}" -type f -name SKILL.md -print0 2>/dev/null)
}

orphan_check

log "checked $total manifest entries; $ERRORS error(s)"
if [[ $ERRORS -ne 0 ]]; then
    exit 1
fi
exit 0
