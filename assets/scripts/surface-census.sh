#!/usr/bin/env bash
#
# surface-census.sh — the gc-toolkit operating-surface oracle.
#
# Prints the four measures the surface-shrink epic grades itself against, in a
# form that re-runs to the same numbers on demand. Run it at each batch close
# to read the surface and compute the delta.
#
#   bash assets/scripts/surface-census.sh            # human-readable report
#   bash assets/scripts/surface-census.sh --json     # machine-readable object
#   bash assets/scripts/surface-census.sh /path/repo # census a specific checkout
#
# It is one deliberate addition to the surface it measures: it counts itself
# among the source scripts, and excludes itself from the metadata-key and
# helper scans (its extraction patterns are not real key or helper usage).
#
# Measures and their definitions:
#
#   source_scripts   assets/scripts/*.sh that are not *.test.sh — the shell
#                    operating surface — with their total line count.
#
#   outside_startable  source scripts whose filename is referenced from the
#                    EXECUTION surface outside assets/scripts (the surfaces that
#                    can start a script: formulas, doctor, services, tools,
#                    orders, agents, template-fragments, packs, lifecycle,
#                    overlays, .github). A script referenced only in docs/specs
#                    is a documentation mention, not an entry point, and is
#                    reported separately; a script referenced nowhere outside
#                    the layer is internal-only.
#
#   metadata_keys    distinct bead-metadata keys the executable operating
#                    surface (assets/scripts + formulas + doctor) reads or
#                    writes, via --set-metadata / --unset-metadata / --metadata
#                    / --metadata-field flags and jq accessors (.metadata.KEY,
#                    .metadata["KEY"], metadata["KEY"]). "bare" keys carry no
#                    dotted namespace; "single_use" keys appear in exactly one
#                    file. services/ is excluded on purpose: its Go/TS
#                    .metadata is a different, non-bead structure.
#
#   drifted_helpers  shell function names defined in three or more source
#                    scripts — copy-pasted helpers that have drifted or will.
#
set -uo pipefail
export LC_ALL=C

SELF_REL="assets/scripts/surface-census.sh"

JSON=0
ROOT=""
for arg in "$@"; do
  case "$arg" in
    --json) JSON=1 ;;
    -h|--help) awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit 0 ;;
    *) ROOT="$arg" ;;
  esac
done
[ -n "$ROOT" ] || ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
[ -n "$ROOT" ] || { echo "surface-census: not in a git repo and no root given" >&2; exit 1; }
cd "$ROOT" || exit 1

TMP=$(mktemp -d "${TMPDIR:-/tmp}/gctk-surface-census.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

# ---- source scripts -------------------------------------------------------
git ls-files 'assets/scripts/*.sh' | grep -v '\.test\.sh$' | sort > "$TMP/src_paths"
sed 's#.*/##' "$TMP/src_paths" | sort -u > "$TMP/src_names"
SRC_N=$(wc -l < "$TMP/src_paths")
SRC_LINES=0
if [ "$SRC_N" -gt 0 ]; then
  SRC_LINES=$(xargs cat < "$TMP/src_paths" | wc -l | tr -d ' ')
fi

# ---- outside-startable entry points ---------------------------------------
EXEC_DIRS="formulas doctor services tools orders agents template-fragments packs lifecycle overlays .github"
git grep -hoE '[A-Za-z0-9_.-]+\.sh' -- $EXEC_DIRS 2>/dev/null \
  | sed 's#.*/##' | sort -u | grep -Fxf "$TMP/src_names" > "$TMP/exec_ref" || true
git grep -hoE '[A-Za-z0-9_.-]+\.sh' -- docs specs '*.md' 2>/dev/null \
  | sed 's#.*/##' | sort -u | grep -Fxf "$TMP/src_names" > "$TMP/doc_ref" || true
cat "$TMP/exec_ref" "$TMP/doc_ref" | sort -u > "$TMP/any_out"
EXEC_START=$(wc -l < "$TMP/exec_ref")
DOC_ONLY=$(comm -13 "$TMP/exec_ref" "$TMP/doc_ref" | wc -l)
INTERNAL=$(comm -13 "$TMP/any_out" "$TMP/src_names" | wc -l)

# ---- metadata keys --------------------------------------------------------
# Scan the executable operating surface (all shell/toml, so full-line comments
# start with #). *.test.sh and the census script itself are excluded: tests
# carry fixture keys, and the census's own patterns are not real key usage.
# Full-line comments are stripped before extraction — a key only mentioned in
# prose is documented, not used. Keys are collected per file as "path<TAB>key"
# so single-use (one-file) keys can be counted.
MD_SCAN="assets/scripts formulas doctor"
git ls-files -- $MD_SCAN 2>/dev/null \
  | grep -vE '\.test\.sh$' | grep -vFx "$SELF_REL" > "$TMP/md_files"
while IFS= read -r f; do
  s=$(grep -vE '^[[:space:]]*#' "$f" 2>/dev/null) || true
  {
    # writes and --metadata-field filters always assign KEY=value
    printf '%s\n' "$s" | grep -oE 'set-metadata "?[A-Za-z0-9_.]+='   | sed -E 's/^set-metadata "?//; s/=$//'
    printf '%s\n' "$s" | grep -oE 'metadata-field "?[A-Za-z0-9_.]+=' | sed -E 's/^metadata-field "?//; s/=$//'
    # unset names a key with no value
    printf '%s\n' "$s" | grep -oE 'unset-metadata "?[A-Za-z0-9_.]+'  | sed -E 's/^unset-metadata "?//'
    # jq reads: .metadata["KEY"] / metadata["KEY"], dotted .metadata.KEY, and
    # quoted dotted .metadata."KEY" (used for keys that carry their own dots)
    printf '%s\n' "$s" | grep -oE 'metadata\["[A-Za-z0-9_.]+"\]'     | sed -E 's/^metadata\["//; s/"\]$//'
    printf '%s\n' "$s" | grep -oE '\.metadata\."[A-Za-z0-9_.]+"'     | sed -E 's/^\.metadata\."//; s/"$//'
    printf '%s\n' "$s" | grep -oE '\.metadata\.[A-Za-z0-9_]+'        | sed -E 's/^\.metadata\.//'
  } | sort -u | sed "s#^#${f}\t#"
done < "$TMP/md_files" \
  | awk -F'\t' 'NF==2 && $2!="" && $2!="v1" && $2!="v2"' | sort -u > "$TMP/fk"
cut -f2 "$TMP/fk" | sort -u > "$TMP/keys"
MD_TOTAL=$(wc -l < "$TMP/keys")
MD_BARE=$(grep -vc '\.' "$TMP/keys" || true)
MD_SINGLE=$(cut -f2 "$TMP/fk" | sort | uniq -c | awk '$1==1' | wc -l)

# ---- drifted helpers ------------------------------------------------------
while IFS= read -r f; do
  [ "$f" = "$SELF_REL" ] && continue
  grep -hoE '^[[:space:]]*(function[[:space:]]+[A-Za-z_][A-Za-z0-9_]*|[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\))' "$f" 2>/dev/null \
    | sed -E 's/^[[:space:]]*function[[:space:]]+//; s/^[[:space:]]*//; s/[[:space:]]*\(\)$//' \
    | sort -u
done < "$TMP/src_paths" | sort | uniq -c | awk '$1>=3' | sort -rn > "$TMP/drift" || true
DRIFT=$(wc -l < "$TMP/drift")

# ---- report ---------------------------------------------------------------
if [ "$JSON" = 1 ]; then
  printf '{\n'
  printf '  "source_scripts": %d,\n' "$SRC_N"
  printf '  "source_lines": %d,\n' "$SRC_LINES"
  printf '  "outside_startable": %d,\n' "$EXEC_START"
  printf '  "docs_only": %d,\n' "$DOC_ONLY"
  printf '  "internal_only": %d,\n' "$INTERNAL"
  printf '  "metadata_keys": %d,\n' "$MD_TOTAL"
  printf '  "metadata_keys_bare": %d,\n' "$MD_BARE"
  printf '  "metadata_keys_single_use": %d,\n' "$MD_SINGLE"
  printf '  "drifted_helpers": %d\n' "$DRIFT"
  printf '}\n'
else
  printf 'gc-toolkit operating-surface census (%s)\n\n' "$ROOT"
  printf '  source scripts .............. %4d  (%d lines; assets/scripts/*.sh, excluding *.test.sh)\n' "$SRC_N" "$SRC_LINES"
  printf '  outside-startable ........... %4d  entry points referenced from the execution surface\n' "$EXEC_START"
  printf '    docs-only mentions ........ %4d  referenced only in docs/specs\n' "$DOC_ONLY"
  printf '    internal-only ............. %4d  referenced nowhere outside assets/scripts\n' "$INTERNAL"
  printf '  metadata keys ............... %4d  distinct bead-metadata keys (assets/scripts + formulas + doctor)\n' "$MD_TOTAL"
  printf '    un-namespaced (bare) ...... %4d  no dotted namespace\n' "$MD_BARE"
  printf '    single-use ................ %4d  referenced in exactly one file\n' "$MD_SINGLE"
  printf '  drifted helpers ............. %4d  shell functions defined in 3+ source scripts\n' "$DRIFT"
  printf '\n'
fi
