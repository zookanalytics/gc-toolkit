#!/usr/bin/env bash
# action-pins.test.sh — every action and reusable workflow that a file under
# .github/ uses is pinned to a full commit SHA.
#
# A tag or a branch names whatever commit its owner points it at, and the owner
# can move it, so a step that names an action by tag runs whatever code the tag
# reaches when the job starts. A full commit SHA names one commit, which cannot
# change. So a uses: names an action or a reusable workflow as
# owner/repo[/path]@<the 40-hex commit SHA>, and a Docker image by its sha256
# digest. A SHA tells a reader nothing about the release it is, so the pin
# carries that release in a trailing comment, as in `@<sha> # v7.0.1`. A local
# action (./path) is this repository's own code at the commit the job checked
# out, and needs no pin.
#
# The scan reads every YAML file under .github/, so a workflow added later is
# held to the rule with no edit here. A line that carries uses: in a form the
# scan cannot read fails, rather than passing unread. The fixture cases first
# prove the scan tells a pin from a tag, a branch and a short SHA.
#
# Hermetic: reads the repository's own files and the fixtures it writes. No
# network.
#
# run-tests-scope: tree

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
GH_DIR="$ROOT/.github"

[ -d "$GH_DIR" ] || { echo "action-pins.test.sh: cannot find .github at $GH_DIR" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-action-pins-test.XXXXXX")" || { echo "action-pins.test.sh: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

fail=0
note() { echo "action-pins.test.sh: FAIL — $1" >&2; fail=1; }

# scan <file>... — one "<file>\t<line>\t<kind>\t<value>" row for each line that
# carries uses: outside a comment. The kind is pin (a full commit SHA), digest
# (a Docker image by its sha256 digest), unnamed (either one with no trailing
# comment to name its release), local (./path), unpinned (any other ref, or
# none), or unreadable (uses: anywhere but as a key at the head of the line, or
# with no value on its line). The value is printed without its trailing comment
# or one pair of quotes around it. awk's regex intervals are not portable, so a
# SHA is checked by its length and its characters.
scan() {
    awk -v q="'" '
        function sha(s, n) { return length(s) == n && s ~ /^[0-9a-f]+$/ }
        function classify(v, at, ref) {
            if (v ~ /^\.\.?\//) return "local"
            if (v ~ /^docker:\/\//) {
                at = index(v, "@sha256:")
                return (at > 0 && sha(substr(v, at + 8), 64)) ? "digest" : "unpinned"
            }
            at = index(v, "@")
            if (at == 0) return "unpinned"
            ref = substr(v, at + 1)
            return sha(ref, 40) ? "pin" : "unpinned"
        }
        /^[[:space:]]*#/ { next }
        !/uses:/ { next }
        {
            kind = "unreadable"; v = $0
            sub(/^[[:space:]]+/, "", v)
            c = ""
            if (match($0, /^[[:space:]]*(-[[:space:]]+)?uses:/)) c = substr($0, RLENGTH + 1, 1)
            if (RSTART == 1 && (c == "" || c == " " || c == "\t")) {
                v = substr($0, RLENGTH + 1)
                sub(/^[[:space:]]+/, "", v)
                named = (v ~ /[[:space:]]#[[:space:]]*[^[:space:]]/)
                sub(/[[:space:]]+#.*$/, "", v)
                sub(/[[:space:]]+$/, "", v)
                f = substr(v, 1, 1)
                if (length(v) >= 2 && (f == "\"" || f == q) && substr(v, length(v), 1) == f)
                    v = substr(v, 2, length(v) - 2)
                if (v != "") kind = classify(v)
                if ((kind == "pin" || kind == "digest") && !named) kind = "unnamed"
            }
            print FILENAME "\t" FNR "\t" kind "\t" v
        }' "$@"
}

# The fixtures: one line per case, after the kind the scan must give it, and
# "none" for a line the scan must skip.
SHA=3d3c42e5aac5ba805825da76410c181273ba90b1
DIGEST=sha256:$(printf '%064d' 0 | tr 0 a)
n=0
while IFS='|' read -r want line; do
    n=$((n + 1))
    printf '%s\n' "$line" > "$TMP/case-$n.yml"
    got="$(scan "$TMP/case-$n.yml" | cut -f3)"
    [ "${got:-none}" = "$want" ] || note "the scan reads '$line' as ${got:-nothing}, not $want"
done <<EOF
pin|      - uses: actions/checkout@$SHA # v7.0.1
pin|      - uses: "actions/setup-go@$SHA" # v7.0.0
pin|      - uses: 'actions/setup-go@$SHA'  #v7.0.0
pin|    uses: octo-org/ci/.github/workflows/build.yml@$SHA # v1.2.0
local|      - uses: ./.github/actions/setup
digest|      - uses: docker://alpine@$DIGEST # 3.20
unnamed|      - uses: actions/checkout@$SHA
unnamed|      - uses: "actions/checkout@$SHA" #
unnamed|      - uses: docker://alpine@$DIGEST
unpinned|      - uses: actions/checkout@$SHA#v7.0.1
unpinned|      - uses: actions/checkout@v7
unpinned|      - uses: actions/checkout@v7.0.1 # $SHA
unpinned|      - uses: 'actions/checkout@main'
unpinned|      - uses: actions/checkout@${SHA:0:7}
unpinned|      - uses: actions/checkout@${SHA}0
unpinned|      - uses: actions/checkout
unpinned|      - uses: docker://alpine:3.20
unpinned|    uses: octo-org/ci/.github/workflows/build.yml@v1
unreadable|      - uses:
unreadable|      - {uses: actions/checkout@v4}
unreadable|        run: echo "uses: actions/checkout@v4"
none|      # - uses: actions/checkout@v4
EOF

# The real files. With no file or no uses: read, every check below would pass
# having checked nothing, so either one fails.
FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(find "$GH_DIR" -type f \( -name '*.yml' -o -name '*.yaml' \) | sort)
[ "${#FILES[@]}" -gt 0 ] || note "found no YAML file under .github/ to scan"

read_count=0
while IFS=$'\t' read -r file line kind value; do
    where="${file#"$ROOT"/}:$line"
    case "$kind" in
        pin|digest|local) read_count=$((read_count + 1)) ;;
        unnamed)
            read_count=$((read_count + 1))
            note "$where pins '$value' with no trailing comment naming its release, so a reader cannot tell which release runs" ;;
        unpinned)
            read_count=$((read_count + 1))
            note "$where uses '$value', which is not pinned to a full commit SHA (or, for a Docker image, a sha256 digest), so its owner can change what it runs" ;;
        *)
            note "$where carries uses: in a form this scan cannot read, so its pin goes unchecked: $value" ;;
    esac
done < <([ "${#FILES[@]}" -eq 0 ] || scan "${FILES[@]}")
[ "$read_count" -gt 0 ] || note "read no uses: in the YAML files under .github/, so no pin was checked"

if [ "$fail" -ne 0 ]; then
    echo "action-pins.test.sh: FAILED" >&2
    exit 1
fi
echo "action-pins.test.sh: OK ($read_count uses: read in ${#FILES[@]} files)"
