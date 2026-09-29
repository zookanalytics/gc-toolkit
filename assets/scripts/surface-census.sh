#!/usr/bin/env bash
#
# surface-census.sh — the gc-toolkit operating-surface oracle.
#
# Prints the surface measures the surface-shrink epic grades itself against, in
# a form that re-runs to the same numbers on demand. Run it at each batch close
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
#                    operating surface — with their total line count. Each
#                    source script falls into exactly one entry-point class,
#                    assigned by the widest surface that references it:
#
#       outside_startable        referenced by filename from the EXECUTION
#                                surface outside assets/scripts (formulas,
#                                doctor, services, tools, orders, agents,
#                                template-fragments, packs, lifecycle, overlays,
#                                .github) — something outside the layer starts
#                                it.
#       called_by_other_scripts  not outside-startable, but referenced by
#                                another source script — live internal call
#                                surface.
#       docs_only                not startable and not called by a script, but
#                                named in docs/specs — a documentation mention.
#       unreferenced             named nowhere outside its own file — a
#                                dead-surface candidate.
#
#                    internal_only is the roll-up called_by_other_scripts +
#                    unreferenced: the scripts no external surface starts.
#
#   metadata_keys    distinct bead-metadata keys the executable operating
#                    surface (assets/scripts + tools + formulas + doctor) reads
#                    or writes, via --set-metadata / --unset-metadata /
#                    --metadata-field flags and jq accessors (.metadata.KEY,
#                    .metadata["KEY"], .metadata."KEY", metadata["KEY"]). "bare"
#                    keys carry no dotted namespace; the namespace breakdown
#                    counts keys per leading dotted segment ("bare" for the
#                    un-namespaced); "single_use" keys appear in exactly one
#                    file, and their sorted list is emitted. *.test.sh,
#                    full-line comments, and services/ are held out (fixture
#                    keys, prose-only mentions, and a non-bead Go/TS .metadata
#                    structure, respectively).
#
#   drifted_helpers  shell function names defined in three or more source
#                    scripts whose definitions are NOT all identical — copy-
#                    pasted helpers that have diverged. duplicated_helpers
#                    counts every name defined in 3+ files; a name whose copies
#                    are all identical (a deliberately kept-in-sync duplicate,
#                    some proven byte-identical by a test) counts there but is
#                    exempt from drift.
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

# ---- entry-point classes --------------------------------------------------
# Each source script is classified by the widest surface that references it, in
# priority order: an external entry point, else another source script, else a
# docs mention, else nothing. The four classes partition the source scripts
# exactly, so the epic can tell live internal surface from dead surface.
EXEC_DIRS="formulas doctor services tools orders agents template-fragments packs lifecycle overlays .github"
git grep -hoE '[A-Za-z0-9_.-]+\.sh' -- $EXEC_DIRS 2>/dev/null \
  | sed 's#.*/##' | sort -u | grep -Fxf "$TMP/src_names" > "$TMP/ref_exec" || true
git grep -hoE '[A-Za-z0-9_.-]+\.sh' -- docs specs '*.md' 2>/dev/null \
  | sed 's#.*/##' | sort -u | grep -Fxf "$TMP/src_names" > "$TMP/ref_doc" || true
# Internal call surface: references between source scripts. The referencing set
# is the non-test source scripts minus the census itself; a script naming
# itself (usage text) is not a caller of itself, so pairs where the referencing
# file IS the referenced script are dropped.
: > "$TMP/ref_as"
grep -vFx "$SELF_REL" "$TMP/src_paths" > "$TMP/ref_src_files" || true
if [ -s "$TMP/ref_src_files" ]; then
  xargs grep -oHE '[A-Za-z0-9_.-]+\.sh' < "$TMP/ref_src_files" 2>/dev/null \
    | awk -F: 'NR==FNR { src[$0]=1; next }
               { rp=$1; sub(/.*\//,"",rp); m=$2; sub(/.*\//,"",m);
                 if ((m in src) && rp != m) print m }' "$TMP/src_names" - \
    | sort -u > "$TMP/ref_as" || true
fi

EXEC_START=$(wc -l < "$TMP/ref_exec")
comm -23 "$TMP/ref_as" "$TMP/ref_exec" > "$TMP/cls_cbo"
CBO=$(wc -l < "$TMP/cls_cbo")
sort -u "$TMP/ref_exec" "$TMP/ref_as" > "$TMP/out_or_as"
comm -23 "$TMP/ref_doc" "$TMP/out_or_as" > "$TMP/cls_doc"
DOC_ONLY=$(wc -l < "$TMP/cls_doc")
sort -u "$TMP/ref_exec" "$TMP/ref_as" "$TMP/ref_doc" > "$TMP/any_ref"
comm -23 "$TMP/src_names" "$TMP/any_ref" > "$TMP/cls_unref"
UNREF=$(wc -l < "$TMP/cls_unref")
INTERNAL=$((CBO + UNREF))

# ---- metadata keys --------------------------------------------------------
# Scan the executable operating surface (all shell/toml, so full-line comments
# start with #). *.test.sh and the census script itself are excluded: tests
# carry fixture keys, and the census's own patterns are not real key usage.
# Full-line comments are stripped before extraction — a key only mentioned in
# prose is documented, not used. Keys are collected per file as "path<TAB>key"
# so single-use (one-file) keys can be counted and listed.
MD_SCAN="assets/scripts tools formulas doctor"
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
cut -f2 "$TMP/fk" | sort | uniq -c | awk '$1==1 {print $2}' | sort > "$TMP/single_keys"
MD_SINGLE=$(wc -l < "$TMP/single_keys")
# namespace breakdown: keys grouped by their leading dotted segment, "bare" for
# the un-namespaced. Emitted as "namespace<TAB>count", sorted by namespace.
awk '{ n=$0; if (index(n,".")>0) { sub(/\..*/,"",n) } else { n="bare" } print n }' "$TMP/keys" \
  | sort | uniq -c | awk '{print $2"\t"$1}' | sort > "$TMP/ns"

# ---- drifted helpers ------------------------------------------------------
# A helper "drifts" when the same function name is defined in 3+ source scripts
# and its definitions are not all identical. Each definition's body is captured
# by brace-depth from the opening brace to the matching close, then whitespace-
# normalized so indentation and line breaks do not read as differences; the
# remaining token stream is the body signature. A name with one distinct
# signature across its copies is a kept-in-sync duplicate (exempt); two or more
# signatures is drift.
: > "$TMP/defs"
BODY_AWK='
function finish(   t) {
  if (name != "") {
    t = body
    gsub(/[[:space:]]+/, " ", t)
    sub(/^ /, "", t); sub(/ $/, "", t)
    print name "\t" FILENAME "\t" t
  }
  infn = 0; name = ""; body = ""; depth = 0
}
FNR == 1 { infn = 0; name = ""; body = ""; depth = 0 }
{
  line = $0
  if (infn == 0) {
    if (line ~ /^[[:space:]]*function[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*(\(\))?[[:space:]]*\{/ ||
        line ~ /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)[[:space:]]*\{/) {
      nm = line
      sub(/^[[:space:]]*/, "", nm)
      sub(/^function[[:space:]]+/, "", nm)
      sub(/[[:space:]]*\(\).*/, "", nm)
      sub(/[[:space:]]*\{.*/, "", nm)
      name = nm; infn = 1; depth = 0; body = ""
      rest = substr(line, index(line, "{"))
      seg = substr(rest, 2)
      t1 = rest; o = gsub(/[{]/, "", t1); t2 = rest; c = gsub(/[}]/, "", t2)
      depth += o - c
      body = body " " seg
      if (depth <= 0) finish()
    }
    next
  }
  seg = line
  t1 = line; o = gsub(/[{]/, "", t1); t2 = line; c = gsub(/[}]/, "", t2)
  depth += o - c
  body = body " " seg
  if (depth <= 0) finish()
}
'
while IFS= read -r f; do
  [ "$f" = "$SELF_REL" ] && continue
  awk "$BODY_AWK" "$f" >> "$TMP/defs" 2>/dev/null || true
done < "$TMP/src_paths"
awk -F'\t' '
{
  name=$1; file=$2; body=$3
  fkey=name SUBSEP file; if (!(fkey in fseen)) { fseen[fkey]=1; nfiles[name]++ }
  bkey=name SUBSEP body; if (!(bkey in bseen)) { bseen[bkey]=1; nbodies[name]++ }
}
END { for (n in nfiles) if (nfiles[n] >= 3) print n "\t" nbodies[n] }' "$TMP/defs" \
  | sort > "$TMP/dup_bodies"
DUP=$(wc -l < "$TMP/dup_bodies")
awk -F'\t' '$2 >= 2 {print $1}' "$TMP/dup_bodies" | sort > "$TMP/drifted_names"
DRIFT=$(wc -l < "$TMP/drifted_names")

# ---- report ---------------------------------------------------------------
if [ "$JSON" = 1 ]; then
  printf '{\n'
  printf '  "source_scripts": %d,\n' "$SRC_N"
  printf '  "source_lines": %d,\n' "$SRC_LINES"
  printf '  "outside_startable": %d,\n' "$EXEC_START"
  printf '  "called_by_other_scripts": %d,\n' "$CBO"
  printf '  "docs_only": %d,\n' "$DOC_ONLY"
  printf '  "unreferenced": %d,\n' "$UNREF"
  printf '  "internal_only": %d,\n' "$INTERNAL"
  printf '  "metadata_keys": %d,\n' "$MD_TOTAL"
  printf '  "metadata_keys_bare": %d,\n' "$MD_BARE"
  printf '  "metadata_keys_single_use": %d,\n' "$MD_SINGLE"
  printf '  "metadata_namespaces": {'
  if [ -s "$TMP/ns" ]; then
    printf '\n'; first=1
    while IFS=$'\t' read -r nsname nscount; do
      [ -n "$nsname" ] || continue
      if [ "$first" = 1 ]; then first=0; else printf ',\n'; fi
      printf '    "%s": %d' "$nsname" "$nscount"
    done < "$TMP/ns"
    printf '\n  }'
  else
    printf '}'
  fi
  printf ',\n'
  printf '  "metadata_single_use_keys": ['
  if [ -s "$TMP/single_keys" ]; then
    printf '\n'; first=1
    while IFS= read -r k; do
      [ -n "$k" ] || continue
      if [ "$first" = 1 ]; then first=0; else printf ',\n'; fi
      printf '    "%s"' "$k"
    done < "$TMP/single_keys"
    printf '\n  ]'
  else
    printf ']'
  fi
  printf ',\n'
  printf '  "duplicated_helpers": %d,\n' "$DUP"
  printf '  "drifted_helpers": %d,\n' "$DRIFT"
  printf '  "drifted_helper_names": ['
  if [ -s "$TMP/drifted_names" ]; then
    printf '\n'; first=1
    while IFS= read -r h; do
      [ -n "$h" ] || continue
      if [ "$first" = 1 ]; then first=0; else printf ',\n'; fi
      printf '    "%s"' "$h"
    done < "$TMP/drifted_names"
    printf '\n  ]\n'
  else
    printf ']\n'
  fi
  printf '}\n'
else
  printf 'gc-toolkit operating-surface census (%s)\n\n' "$ROOT"
  printf '  source scripts .............. %4d  (%d lines; assets/scripts/*.sh, excluding *.test.sh)\n' "$SRC_N" "$SRC_LINES"
  printf '    outside-startable ......... %4d  referenced from the execution surface outside assets/scripts\n' "$EXEC_START"
  printf '    called-by-other-scripts ... %4d  invoked only by another source script\n' "$CBO"
  printf '    docs-only mentions ........ %4d  named only in docs/specs\n' "$DOC_ONLY"
  printf '    unreferenced .............. %4d  named nowhere outside its own file\n' "$UNREF"
  printf '  metadata keys ............... %4d  distinct bead-metadata keys (assets/scripts + tools + formulas + doctor)\n' "$MD_TOTAL"
  printf '    un-namespaced (bare) ...... %4d  no dotted namespace\n' "$MD_BARE"
  printf '    single-use ................ %4d  referenced in exactly one file\n' "$MD_SINGLE"
  printf '  drifted helpers ............. %4d  functions in 3+ source scripts whose bodies differ\n' "$DRIFT"
  printf '    duplicated (3+ files) ..... %4d  functions defined in 3+ source scripts (drift + kept-in-sync)\n' "$DUP"
  printf '\n'
  printf '  metadata namespace breakdown (keys per leading segment):\n'
  if [ -s "$TMP/ns" ]; then
    while IFS=$'\t' read -r nsname nscount; do
      [ -n "$nsname" ] || continue
      printf '    %-26s %4d\n' "$nsname" "$nscount"
    done < "$TMP/ns"
  else
    printf '    (none)\n'
  fi
  printf '\n'
  printf '  single-use metadata keys (one file only):\n'
  if [ -s "$TMP/single_keys" ]; then
    while IFS= read -r k; do
      [ -n "$k" ] || continue
      printf '    %s\n' "$k"
    done < "$TMP/single_keys"
  else
    printf '    (none)\n'
  fi
  printf '\n'
  printf '  drifted helper names (differing bodies in 3+ scripts):\n'
  if [ -s "$TMP/drifted_names" ]; then
    while IFS= read -r h; do
      [ -n "$h" ] || continue
      printf '    %s\n' "$h"
    done < "$TMP/drifted_names"
  else
    printf '    (none)\n'
  fi
  printf '\n'
fi
