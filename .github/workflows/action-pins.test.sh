#!/usr/bin/env bash
# action-pins.test.sh — every action and reusable workflow that a file under
# .github/ uses is pinned to a full commit SHA.
#
# A tag or a branch names whatever commit its owner points it at, and the owner
# can move it, so a step that names an action by tag runs whatever code the tag
# reaches when the job starts. A full commit SHA names one commit, which cannot
# change. So a uses names an action or a reusable workflow as
# owner/repo[/path]@<the 40-hex commit SHA>, and a Docker image by its sha256
# digest. A SHA tells a reader nothing about the release it is, so the pin
# carries that release in a trailing comment, as in `@<sha> # v7.0.1`. A local
# action (./path) is this repository's own code at the commit the job checked
# out, and needs no pin.
#
# The scan reads every YAML file under .github/ with Psych, the YAML parser Ruby
# ships, and checks every key the parser reads as uses. YAML spells one key in
# many ways: quoted, with space before its colon, through escapes, inside a
# flow mapping, as an explicit ? key, or through an alias. A YAML parser reads
# each of them as the key uses, so the scan, which reads keys with one, checks
# each of them. A file that does not parse fails, and so does a uses whose
# value is not a string. A workflow added later is held to the rule with no
# edit here. The fixture cases first prove the scan tells a pin from a tag, a
# branch and a short SHA, and finds uses in each of those spellings.
#
# Hermetic: reads the repository's own files and the fixtures it writes. No
# network. Needs ruby, with the Psych it bundles.
#
# run-tests-scope: tree

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
GH_DIR="$ROOT/.github"

[ -d "$GH_DIR" ] || { echo "action-pins.test.sh: cannot find .github at $GH_DIR" >&2; exit 2; }
ruby -e 'require "psych"' 2>/dev/null \
    || { echo "action-pins.test.sh: needs ruby with Psych, its YAML parser, to read the workflows" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-action-pins-test.XXXXXX")" || { echo "action-pins.test.sh: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

fail=0
note() { echo "action-pins.test.sh: FAIL — $1" >&2; fail=1; }

# scan <file>... — one "<file>\t<line>\t<kind>\t<value>" row for each key a
# YAML parser reads as uses, at the line the key starts on. The kind is pin (a
# full commit SHA), digest (a Docker image by its sha256 digest), unnamed
# (either one with no trailing comment to name its release), local (./path),
# unpinned (any other ref, or none), or unreadable (a value that is not a
# string, or a file that does not parse). The value is the string the parser
# reads, without quotes or a comment, and an unreadable row's value says why it
# is unreadable. A file the scan cannot read gets a row of its own, and the scan
# goes on to the next file. It exits non-zero only when it stops before the last
# file.
scan() {
    ruby - "$@" <<'RUBY'
require 'psych'

def classify(v)
  return 'local' if v.start_with?('./', '../')
  if v.start_with?('docker://')
    at = v.index('@sha256:')
    return at && v[(at + 8)..-1] =~ /\A[0-9a-f]{64}\z/ ? 'digest' : 'unpinned'
  end
  at = v.index('@')
  at && v[(at + 1)..-1] =~ /\A[0-9a-f]{40}\z/ ? 'pin' : 'unpinned'
end

def row(path, line, kind, text)
  puts [path, line, kind, text.gsub(/[\t\n\r]/, "\t" => '\t', "\n" => '\n', "\r" => '\r')].join("\t")
end

ARGV.each do |path|
  begin
    src = File.binread(path).force_encoding('UTF-8')
    stream = Psych.parse_stream(src)
    # libyaml ends a line at \r\n, \r, \n, NEL, LS and PS, so the source is
    # split the same way to read the text after a value on its line.
    lines = src.split(/\r\n|[\r\n\u{85}\u{2028}\u{2029}]/, -1)
    anchors = {}
    resolve = lambda { |n| n.is_a?(Psych::Nodes::Alias) ? anchors[n.anchor] : n }
    check = lambda do |key, value|
      v = resolve.call(value)
      unless v.is_a?(Psych::Nodes::Scalar)
        row(path, key.start_line + 1, 'unreadable', 'the value of uses is not a string')
        next
      end
      kind = classify(v.value)
      if %w[pin digest].include?(kind)
        rest = lines[value.end_line].to_s[value.end_column..-1].to_s
        kind = 'unnamed' unless rest =~ /\A[ \t]+#[ \t]*\S/
      end
      row(path, key.start_line + 1, kind, v.value)
    end
    walk = lambda do |node|
      next if node.is_a?(Psych::Nodes::Alias)
      anchors[node.anchor] = node if node.respond_to?(:anchor) && node.anchor
      if node.is_a?(Psych::Nodes::Mapping)
        node.children.each_slice(2) do |key, value|
          walk.call(key)
          k = resolve.call(key)
          check.call(key, value) if k.is_a?(Psych::Nodes::Scalar) && k.value == 'uses'
          walk.call(value)
        end
      else
        node.children.to_a.each { |c| walk.call(c) }
      end
    end
    walk.call(stream)
  rescue Psych::SyntaxError => e
    row(path, e.line, 'unreadable', "the file does not parse as YAML (#{[e.problem, e.context].compact.join(' ')})")
  rescue StandardError => e
    row(path, 0, 'unreadable', "the scan failed on the file (#{e.class}: #{e.message})")
  end
end
RUBY
}

# The fixtures: one case per line, after the kinds the scan must give it in
# order, joined by commas, and "none" for a case with no uses key. A \n in a
# case starts a new line. LS is the Unicode line separator, which ends a line
# for libyaml.
SHA=3d3c42e5aac5ba805825da76410c181273ba90b1
DIGEST=sha256:$(printf '%064d' 0 | tr 0 a)
LS=$(printf '\342\200\250')
n=0
CASES=()
WANTS=()
while IFS='|' read -r want yaml; do
    n=$((n + 1))
    printf '%s\n' "${yaml//\\n/$'\n'}" > "$TMP/case-$n.yml"
    CASES[n]="$yaml"
    WANTS[n]="$want"
done <<EOF
pin|      - uses: actions/checkout@$SHA # v7.0.1
pin|      - uses: "actions/setup-go@$SHA" # v7.0.0
pin|      - uses: 'actions/setup-go@$SHA'  #v7.0.0
pin|    uses: octo-org/ci/.github/workflows/build.yml@$SHA # v1.2.0
pin|      - "uses": actions/checkout@$SHA # v7.0.1
pin|# a comment the line separator ends:$LS\n      - uses: actions/checkout@$SHA # v7.0.1
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
unpinned|      - uses:
unpinned|      - "uses": actions/checkout@v4
unpinned|      - 'uses': actions/checkout@v4
unpinned|      - uses : actions/checkout@v4
unpinned|      - "\x75ses": actions/checkout@v4
unpinned|      - "\u0075ses": actions/checkout@v4
unpinned|      - {uses: actions/checkout@v4}
unpinned|      - {"uses":"actions/checkout@v4"}
unpinned|      - ? uses\n        : actions/checkout@v4
unpinned|      - uses:\n          actions/checkout@v4
unpinned|      - uses: >-\n          actions/checkout@v4
unpinned|x: &key uses\nsteps:\n  - *key : actions/checkout@v4
unpinned|x: &ref actions/checkout@v4\nsteps:\n  - uses: *ref
pin,unpinned|- &key uses: actions/checkout@$SHA # v7.0.1\n- *key : actions/checkout@v4
unreadable|      - uses: {name: checkout}
unreadable|      - uses: "actions/checkout@v4
none|      # - uses: actions/checkout@v4
none|        run: 'echo "uses: actions/checkout@v4"'
none|        run: |\n          uses: actions/checkout@v4
EOF

scan "$TMP"/case-*.yml > "$TMP/case-rows" || note "the scan stopped before the last fixture"
for ((i = 1; i <= n; i++)); do
    got="$(awk -F'\t' -v f="$TMP/case-$i.yml" '$1 == f { k = k (k == "" ? "" : ",") $3 } END { print k }' "$TMP/case-rows")"
    [ "${got:-none}" = "${WANTS[i]}" ] || note "the scan reads '${CASES[i]}' as ${got:-nothing}, not ${WANTS[i]}"
done

# The real files. With no file or no uses read, every check below would pass
# having checked nothing, so either one fails.
FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(find "$GH_DIR" -type f \( -name '*.yml' -o -name '*.yaml' \) | sort)
[ "${#FILES[@]}" -gt 0 ] || note "found no YAML file under .github/ to scan"

: > "$TMP/rows"
[ "${#FILES[@]}" -eq 0 ] || scan "${FILES[@]}" > "$TMP/rows" || note "the scan stopped before the last YAML file under .github/"
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
            note "$where cannot be checked for a pin: $value" ;;
    esac
done < "$TMP/rows"
[ "$read_count" -gt 0 ] || note "read no uses in the YAML files under .github/, so no pin was checked"

if [ "$fail" -ne 0 ]; then
    echo "action-pins.test.sh: FAILED" >&2
    exit 1
fi
echo "action-pins.test.sh: OK ($read_count uses read in ${#FILES[@]} files)"
