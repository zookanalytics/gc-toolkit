#!/usr/bin/env bash
# refresh-skills.sh — refresh vendored external skills listed in skills.lock.toml.
#
# Walks skills.lock.toml, fetches each [[external]] entry's pinned source,
# validates SKILL.md frontmatter, and copies the skill into its vendor_at
# directory. Does not commit; produces a working-tree diff for review.
#
# Usage:
#   tools/refresh-skills.sh                # refresh every entry
#   tools/refresh-skills.sh --skill NAME   # refresh just one entry
#   tools/refresh-skills.sh --manifest PATH --pack-root PATH
#
# Exits 0 if all selected entries refreshed cleanly. Per-entry failures
# are logged and do not abort the run; the final exit is non-zero if any
# selected entry failed.

set -euo pipefail

# --------------------------------------------------------------------------
# argument parsing
# --------------------------------------------------------------------------

SKILL_FILTER=""
MANIFEST=""
PACK_ROOT=""

usage() {
    cat <<'USAGE'
Usage: refresh-skills.sh [options]

Options:
  --skill NAME          Refresh only the manifest entry with this name.
  --manifest PATH       Override the manifest path (default: <pack-root>/skills.lock.toml).
  --pack-root PATH      Override the pack root (default: parent of the script's directory).
  -h, --help            Print this help.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skill)        SKILL_FILTER="$2"; shift 2 ;;
        --skill=*)      SKILL_FILTER="${1#--skill=}"; shift ;;
        --manifest)     MANIFEST="$2"; shift 2 ;;
        --manifest=*)   MANIFEST="${1#--manifest=}"; shift ;;
        --pack-root)    PACK_ROOT="$2"; shift 2 ;;
        --pack-root=*)  PACK_ROOT="${1#--pack-root=}"; shift ;;
        -h|--help)      usage; exit 0 ;;
        *)              printf 'refresh-skills: unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACK_ROOT="${PACK_ROOT:-$(dirname "$SCRIPT_DIR")}"
MANIFEST="${MANIFEST:-$PACK_ROOT/skills.lock.toml}"

if [[ ! -f "$MANIFEST" ]]; then
    printf 'refresh-skills: manifest not found: %s\n' "$MANIFEST" >&2
    exit 1
fi

# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------

log()  { printf '[refresh-skills] %s\n' "$*"; }
warn() { printf '[refresh-skills] WARN: %s\n' "$*" >&2; }
err()  { printf '[refresh-skills] ERROR: %s\n' "$*" >&2; }

# Single parent under /tmp; cleaned on exit.
TMP_PARENT="/tmp/gc-toolkit-skill-refresh-$$"
mkdir -p "$TMP_PARENT"
trap 'rm -rf "$TMP_PARENT"' EXIT INT TERM

# parse_manifest — emit one record per logical assignment.
#
#   ENTRY <idx>            marks the start of an [[external]] block
#   <key>=<value>          one per non-comment, non-blank assignment in the
#                          current section (preceded by ENTRY for external
#                          blocks; preceded by TOP for the top-level)
#
# Only [[external]] blocks and top-level assignments are surfaced. Other
# sections (none defined in v1) are skipped silently.
parse_manifest() {
    local file="$1"
    local section="top"
    local idx=-1
    local lineno=0
    local raw key val
    while IFS= read -r raw || [[ -n "$raw" ]]; do
        lineno=$((lineno + 1))
        # strip leading whitespace
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
        # key = value
        if [[ "$trimmed" =~ ^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            val="${BASH_REMATCH[2]}"
            # strip inline comment when value is not quoted
            if [[ "$val" != \"* ]]; then
                val="${val%%#*}"
            fi
            # trim trailing whitespace
            val="${val%"${val##*[![:space:]]}"}"
            # strip surrounding double-quotes
            if [[ "$val" == \"*\" ]]; then
                val="${val:1:${#val}-2}"
            fi
            case "$section" in
                top)        printf 'TOP_%s=%s\n' "$key" "$val" ;;
                entry:*)    printf '%s=%s\n' "$key" "$val" ;;
            esac
        else
            warn "manifest line $lineno not recognized: $trimmed"
        fi
    done < "$file"
}

require_field() {
    local entry_name="$1" field="$2" value="$3"
    if [[ -z "$value" ]]; then
        err "entry '${entry_name:-?}': required field missing: $field"
        return 1
    fi
}

ref_is_sha() {
    [[ "$1" =~ ^[0-9a-f]{40}$ ]]
}

ref_is_tag_or_sha() {
    ref_is_sha "$1" && return 0
    # heuristic: tags often look like vX.Y.Z or release-X.Y; treat anything
    # that isn't an obvious branch name as a tag. The validator emits a
    # warning if it can't confirm, so this stays permissive.
    [[ "$1" =~ ^v?[0-9]+(\.[0-9]+)+([\.-][A-Za-z0-9._-]+)?$ ]]
}

# fetch_git SOURCE REF DEST — clone SOURCE at REF into DEST.
fetch_git() {
    local source="$1" ref="$2" dest="$3"
    if git clone --quiet --depth=1 --branch="$ref" --single-branch "$source" "$dest" 2>/dev/null; then
        return 0
    fi
    # Fall back to a full clone for SHA pins (--branch rejects raw SHAs).
    rm -rf "$dest"
    git clone --quiet "$source" "$dest"
    ( cd "$dest" && git checkout --quiet "$ref" )
}

# verify_frontmatter SKILL_MD — return 0 if frontmatter has name + description.
verify_frontmatter() {
    local skill_md="$1"
    if [[ ! -f "$skill_md" ]]; then
        err "SKILL.md not found at $skill_md"
        return 1
    fi
    local first
    first="$(sed -n '1p' "$skill_md")"
    if [[ "$first" != "---" ]]; then
        err "SKILL.md missing opening '---': $skill_md"
        return 1
    fi
    local close_line
    close_line="$(awk 'NR>1 && /^---[[:space:]]*$/ { print NR; exit }' "$skill_md")"
    if [[ -z "$close_line" ]]; then
        err "SKILL.md missing closing '---': $skill_md"
        return 1
    fi
    local fm
    fm="$(sed -n "2,$((close_line - 1))p" "$skill_md")"
    if ! grep -qE '^name:[[:space:]]*\S' <<<"$fm"; then
        err "SKILL.md frontmatter missing 'name:' field: $skill_md"
        return 1
    fi
    if ! grep -qE '^description:[[:space:]]*\S' <<<"$fm"; then
        err "SKILL.md frontmatter missing 'description:' field: $skill_md"
        return 1
    fi
    return 0
}

# inject_marker SKILL_MD SOURCE REF — write or update the vendored-from
# comment immediately after the frontmatter close.
inject_marker() {
    local skill_md="$1" source="$2" ref="$3"
    local today
    today="$(date -u +%Y-%m-%d)"
    local marker="<!-- vendored from ${source}@${ref} on ${today} by skills.lock.toml -->"
    local close_line
    close_line="$(awk 'NR>1 && /^---[[:space:]]*$/ { print NR; exit }' "$skill_md")"
    if [[ -z "$close_line" ]]; then
        err "inject_marker: no frontmatter close in $skill_md"
        return 1
    fi
    local tmp
    tmp="$(mktemp "$TMP_PARENT/skillmd.XXXXXX")"
    # Frontmatter lines 1..close_line.
    sed -n "1,${close_line}p" "$skill_md" > "$tmp"
    printf '\n%s\n' "$marker" >> "$tmp"
    # Body: drop any previous vendored-from marker line so re-runs do not stack.
    local body_start=$((close_line + 1))
    sed -n "${body_start},\$p" "$skill_md" \
        | sed -E '/^<!-- vendored from .+ by skills\.lock\.toml -->$/d' \
        >> "$tmp"
    # Truncate-and-rewrite the original so the existing inode + mode are
    # preserved (mktemp's 600 mode would otherwise leak through mv).
    cat "$tmp" > "$skill_md"
    rm -f "$tmp"
}

# strip_plugin_cruft DEST — remove Claude-plugin distribution metadata.
strip_plugin_cruft() {
    local dest="$1"
    rm -rf "$dest/.claude-plugin"
    rm -f "$dest/plugin.json" "$dest/marketplace.json"
}

# process_entry — refresh one [[external]] entry. Reads named globals
# populated by the main loop; returns 0 on success, non-zero on failure.
process_entry() {
    local name="${E_name:-}"
    local source="${E_source:-}"
    local ref="${E_ref:-}"
    local fetcher="${E_fetcher:-}"
    local subpath="${E_subpath:-}"
    local vendor_at="${E_vendor_at:-}"
    local license="${E_license:-}"
    local notes="${E_notes:-}"

    local missing=0
    require_field "$name" name      "$name"      || missing=1
    require_field "$name" source    "$source"    || missing=1
    require_field "$name" ref       "$ref"       || missing=1
    require_field "$name" fetcher   "$fetcher"   || missing=1
    require_field "$name" vendor_at "$vendor_at" || missing=1
    require_field "$name" license   "$license"   || missing=1
    if [[ $missing -ne 0 ]]; then
        return 1
    fi

    if [[ "$fetcher" != "git" ]]; then
        err "entry '$name': unsupported fetcher '$fetcher' (v1 supports 'git' only)"
        return 1
    fi

    if [[ "$vendor_at" != */ ]]; then
        err "entry '$name': vendor_at must end in '/': $vendor_at"
        return 1
    fi

    if ! ref_is_tag_or_sha "$ref"; then
        warn "entry '$name': ref '$ref' is not a tag or full SHA — pin is non-deterministic"
    fi

    local clone_dir="$TMP_PARENT/$name"
    log "[$name] fetching $source @ $ref"
    if ! fetch_git "$source" "$ref" "$clone_dir"; then
        err "entry '$name': git fetch failed"
        return 1
    fi

    local src="$clone_dir"
    if [[ -n "$subpath" ]]; then
        src="$clone_dir/$subpath"
    fi
    if [[ ! -d "$src" ]]; then
        err "entry '$name': subpath not found in source: $subpath"
        return 1
    fi
    if [[ ! -f "$src/SKILL.md" ]]; then
        err "entry '$name': SKILL.md not found at $src/SKILL.md"
        return 1
    fi
    if ! verify_frontmatter "$src/SKILL.md"; then
        err "entry '$name': frontmatter validation failed"
        return 1
    fi

    local dest="$PACK_ROOT/$vendor_at"
    # vendor_at always ends in /, so strip trailing slash for rm -rf safety.
    local dest_clean="${dest%/}"
    # Refuse to touch the pack root itself (defense-in-depth).
    if [[ "$dest_clean" == "$PACK_ROOT" || -z "$dest_clean" ]]; then
        err "entry '$name': vendor_at resolves to pack root; refusing"
        return 1
    fi
    log "[$name] vendoring into $vendor_at"
    rm -rf "$dest_clean"
    mkdir -p "$dest_clean"
    # Copy contents of src (including dotfiles) into dest.
    cp -r "$src/." "$dest_clean/"
    # Drop the embedded .git in case `cp` pulled it in via subpath = "".
    rm -rf "$dest_clean/.git"
    strip_plugin_cruft "$dest_clean"

    if ! inject_marker "$dest_clean/SKILL.md" "$source" "$ref"; then
        err "entry '$name': marker injection failed"
        return 1
    fi

    log "[$name] ok (license=$license${notes:+, $notes})"
    return 0
}

# --------------------------------------------------------------------------
# main loop
# --------------------------------------------------------------------------

current_idx=""
schema=""
total=0
selected=0
processed=0
failed_names=()

reset_entry() {
    unset E_name E_source E_ref E_fetcher E_subpath E_vendor_at E_license E_notes
}

flush_entry() {
    if [[ -z "$current_idx" ]]; then
        return 0
    fi
    total=$((total + 1))
    if [[ -n "$SKILL_FILTER" && "${E_name:-}" != "$SKILL_FILTER" ]]; then
        reset_entry
        return 0
    fi
    selected=$((selected + 1))
    if process_entry; then
        processed=$((processed + 1))
    else
        failed_names+=("${E_name:-<idx:$current_idx>}")
    fi
    reset_entry
}

reset_entry

while IFS= read -r record; do
    if [[ "$record" == "ENTRY "* ]]; then
        flush_entry
        current_idx="${record#ENTRY }"
        continue
    fi
    if [[ "$record" == "TOP_schema="* ]]; then
        schema="${record#TOP_schema=}"
        continue
    fi
    if [[ -z "$current_idx" ]]; then
        # ignore top-level keys other than schema
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
        *) warn "unknown field in entry $current_idx: ${record%%=*}" ;;
    esac
done < <(parse_manifest "$MANIFEST")
flush_entry

if [[ -z "$schema" ]]; then
    err "manifest missing 'schema' top-level field"
    exit 1
fi
if [[ "$schema" != "1" ]]; then
    err "unsupported manifest schema: $schema (expected 1)"
    exit 1
fi

if [[ -n "$SKILL_FILTER" && $selected -eq 0 ]]; then
    err "no manifest entry matched --skill=$SKILL_FILTER"
    exit 1
fi

log "summary: $processed/$selected refreshed; $total total in manifest"
if [[ ${#failed_names[@]} -gt 0 ]]; then
    err "failed entries: ${failed_names[*]}"
    exit 1
fi

# Run the validator over the result so a successful refresh leaves the
# tree in a known-good state.
log "running validator"
"$SCRIPT_DIR/validate-skills.sh" --manifest "$MANIFEST" --pack-root "$PACK_ROOT"
