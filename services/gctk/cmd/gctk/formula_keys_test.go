package main

import (
	"errors"
	"fmt"
	"maps"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"testing"

	"github.com/pelletier/go-toml/v2"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// The pack's metadata-key registry and its formulas, from this package's
// directory.
const (
	lifecyclePath = "../../../../lifecycle/lifecycle.toml"
	formulasDir   = "../../../../formulas"
)

// Every key a formula writes is pack state, so the metadata-key registry holds
// it: a [metadata.*] group of lifecycle/lifecycle.toml, or the declaration of
// the gctk domain that owns it. A formula writes a key in a step's metadata
// table, which Gas City copies onto the step's bead when it pours the formula,
// and in the shell of its text, through bd's --set-metadata, --unset-metadata
// and a create's --metadata. A write whose key cannot be read fails here too,
// so no key passes unseen.
func TestKeyRegistryHoldsEveryKeyAFormulaWrites(t *testing.T) {
	raw, err := os.ReadFile(lifecyclePath)
	if err != nil {
		t.Fatal(err)
	}
	reg, err := readRegistry(raw, ledger.Registry())
	if err != nil {
		t.Fatal(err)
	}
	paths, err := filepath.Glob(filepath.Join(formulasDir, "*.toml"))
	if err != nil || len(paths) == 0 {
		t.Fatalf("no formula found in %s (%v)", formulasDir, err)
	}
	read := 0
	for _, path := range paths {
		raw, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		name := "formulas/" + filepath.Base(path)
		writes, err := formulaWrites(raw)
		if err != nil {
			t.Errorf("%s: %v", name, err)
			continue
		}
		read += len(writes)
		for _, w := range writes {
			switch {
			case w.key == "":
				t.Errorf("%s, %s: %s writes a key that cannot be read: name the key literally, as the flag's argument, as a key of the JSON or jq object --metadata takes, or in such an object assigned once to the variable --metadata takes, in the same text", name, w.where, w.text)
			case !reg.holds(w.key):
				t.Errorf("%s, %s writes %s, which the metadata-key registry does not hold: register it in a [metadata.*] group of lifecycle/lifecycle.toml, or declare it in the gctk domain that owns it", name, w.where, w.key)
			}
		}
	}
	if read == 0 {
		t.Fatal("no metadata write was read from any formula, so nothing was checked")
	}
}

// registry is the metadata-key registry. An entry of a lifecycle.toml group
// that ends in * holds every key that starts with what comes before it. A
// declaration registers only the name of a key its domain owns: a key declared
// with ledger.ReadOnly stays in lifecycle.toml while its writer is outside a
// domain, and the ledger writes only a key's current spelling, never an alias.
type registry struct {
	keys     map[string]bool
	prefixes []string
}

func readRegistry(lifecycle []byte, declared []ledger.Entry) (registry, error) {
	var doc struct {
		Metadata map[string]struct {
			Keys []string `toml:"keys"`
		} `toml:"metadata"`
	}
	if err := toml.Unmarshal(lifecycle, &doc); err != nil {
		return registry{}, fmt.Errorf("lifecycle.toml: %w", err)
	}
	reg := registry{keys: map[string]bool{}}
	for _, group := range doc.Metadata {
		for _, k := range group.Keys {
			if prefix, ok := strings.CutSuffix(k, "*"); ok {
				reg.prefixes = append(reg.prefixes, prefix)
			} else {
				reg.keys[k] = true
			}
		}
	}
	if len(reg.keys) == 0 {
		return registry{}, errors.New("lifecycle.toml's [metadata.*] groups list no key")
	}
	for _, e := range declared {
		if e.Owner != "" {
			reg.keys[e.Name] = true
		}
	}
	return reg, nil
}

func (r registry) holds(key string) bool {
	if r.keys[key] {
		return true
	}
	for _, prefix := range r.prefixes {
		if strings.HasPrefix(key, prefix) {
			return true
		}
	}
	return false
}

// formulaWrite is a key a formula writes and where: a step's metadata table,
// or a text that writes it. A write whose key cannot be read has no key, and
// its text instead.
type formulaWrite struct {
	where, key, text string
}

var (
	// metadataKey is a key the reader takes as written. A key built from a
	// variable or a formula var, or a placeholder such as <key>, is none.
	metadataKey = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_.-]*$`)
	// metadataFlag finds bd's flags that write metadata, each with the byte
	// after it. A flag followed by a letter, digit, _ or - is a longer flag,
	// such as --metadata-field, which reads.
	metadataFlag = regexp.MustCompile(`--(set-metadata|unset-metadata|metadata)([^A-Za-z0-9_-]|$)`)
	setArg       = regexp.MustCompile(`^["']?([A-Za-z_][A-Za-z0-9_.-]*)=`)
	unsetArg     = regexp.MustCompile(`^(["']?)([A-Za-z_][A-Za-z0-9_.-]*)(["']?)(?:[\s;|&)]|$)`)
	varArg       = regexp.MustCompile(`^("?)\$(\{?)([A-Za-z_][A-Za-z0-9_]*)(\}?)("?)(?:[\s;|&)]|$)`)
	// objectArg is the object --metadata takes: a JSON literal in single
	// quotes, or the program of a jq call that builds it, which is the call's
	// last argument and its only one in single quotes.
	objectArg   = regexp.MustCompile(`^(?:'([^']*)'|"?\$\(\s*jq\s[^']*'([^']*)'\s*\))`)
	objectEntry = regexp.MustCompile(`^\s*(?:([A-Za-z_][A-Za-z0-9_]*)|"([^"\\]*)")\s*:`)
)

// formulaWrites reads every metadata write in a formula. A metadata table is a
// step's wherever the step sits, whether a formula's, a child's, a loop body's
// or a template's, except the formula's own, which Gas City keeps for
// inspection and never copies onto a bead (its formula.Formula.Metadata), and
// one under the formula's vars, which defines a var. Every string of the
// formula is read for bd's flags.
func formulaWrites(raw []byte) ([]formulaWrite, error) {
	var doc map[string]any
	if err := toml.Unmarshal(raw, &doc); err != nil {
		return nil, err
	}
	var out []formulaWrite
	var walk func(v any, where string, steps bool)
	walk = func(v any, where string, steps bool) {
		switch v := v.(type) {
		case string:
			out = append(out, shellWrites(v, where)...)
		case []any:
			for i, e := range v {
				walk(e, where+"["+elementName(e, i)+"]", steps)
			}
		case map[string]any:
			for _, k := range slices.Sorted(maps.Keys(v)) {
				at := k
				if where != "" {
					at = where + "." + k
				}
				if table, ok := v[k].(map[string]any); ok && k == "metadata" && steps {
					for _, key := range slices.Sorted(maps.Keys(table)) {
						if metadataKey.MatchString(key) {
							out = append(out, formulaWrite{where: at, key: key})
						} else {
							out = append(out, formulaWrite{where: at, text: strconv.Quote(key)})
						}
					}
					continue
				}
				walk(v[k], at, steps)
			}
		}
	}
	for _, k := range slices.Sorted(maps.Keys(doc)) {
		walk(doc[k], k, k != "metadata" && k != "vars")
	}
	return out, nil
}

// elementName names an array's element by its id, as a step has one, or else
// by its index.
func elementName(e any, i int) string {
	if m, ok := e.(map[string]any); ok {
		if id, ok := m["id"].(string); ok && id != "" {
			return id
		}
	}
	return strconv.Itoa(i)
}

// shellWrites reads the keys bd's flags write in a text, once the shell's
// line continuations are joined.
func shellWrites(text, where string) []formulaWrite {
	text = strings.ReplaceAll(text, "\\\n", "")
	var out []formulaWrite
	for _, loc := range metadataFlag.FindAllStringSubmatchIndex(text, -1) {
		arg := ""
		switch text[loc[4]:loc[5]] {
		case "=":
			arg = text[loc[5]:]
		case " ", "\t":
			arg = strings.TrimLeft(text[loc[5]:], " \t")
		}
		keys, ok := flagKeys(text[loc[2]:loc[3]], arg, text)
		if !ok {
			line, _, _ := strings.Cut(text[loc[0]:], "\n")
			out = append(out, formulaWrite{where: where, text: line})
			continue
		}
		for _, k := range keys {
			out = append(out, formulaWrite{where: where, key: k})
		}
	}
	return out
}

// flagKeys reads the keys one flag writes from its argument, and says whether
// it could. --metadata's variable is read from its one assignment in text.
func flagKeys(flag, arg, text string) ([]string, bool) {
	switch flag {
	case "set-metadata":
		if m := setArg.FindStringSubmatch(arg); m != nil {
			return []string{m[1]}, true
		}
		return nil, false
	case "unset-metadata":
		if m := unsetArg.FindStringSubmatch(arg); m != nil && m[1] == m[3] {
			return []string{m[2]}, true
		}
		return nil, false
	}
	if m := varArg.FindStringSubmatch(arg); m != nil {
		if m[1] != m[5] || (m[2] == "") != (m[4] == "") {
			return nil, false
		}
		assigned := regexp.MustCompile(`(?m)^[ \t]*(?:export[ \t]+|local[ \t]+)?`+regexp.QuoteMeta(m[3])+`=(.*)$`).FindAllStringSubmatch(text, -1)
		if len(assigned) != 1 {
			return nil, false
		}
		arg = assigned[0][1]
	}
	return objectKeys(arg)
}

// objectKeys reads the keys of the object a --metadata argument gives, each a
// name or a string with nothing interpolated, as JSON and jq write them. A key
// jq computes, such as ($k), is none, and so is a program that only starts and
// ends with a brace, such as {a: $x} + {b: 1}.
func objectKeys(arg string) ([]string, bool) {
	m := objectArg.FindStringSubmatch(arg)
	if m == nil {
		return nil, false
	}
	inner, ok := strings.CutPrefix(strings.TrimSpace(m[1]+m[2]), "{")
	if !ok {
		return nil, false
	}
	if inner, ok = strings.CutSuffix(inner, "}"); !ok {
		return nil, false
	}
	entries, ok := topLevelFields(inner)
	if !ok {
		return nil, false
	}
	if strings.TrimSpace(inner) == "" {
		return nil, true
	}
	var keys []string
	for _, entry := range entries {
		e := objectEntry.FindStringSubmatch(entry)
		if e == nil || !metadataKey.MatchString(e[1]+e[2]) {
			return nil, false
		}
		keys = append(keys, e[1]+e[2])
	}
	return keys, true
}

// topLevelFields splits s at each comma outside a string and outside any
// bracket, and says whether every bracket s opens it closes, in order.
func topLevelFields(s string) ([]string, bool) {
	var fields []string
	depth, start, quoted := 0, 0, false
	for i := 0; i < len(s); i++ {
		switch c := s[i]; {
		case quoted && c == '\\':
			i++
		case c == '"':
			quoted = !quoted
		case quoted:
		case c == '(' || c == '[' || c == '{':
			depth++
		case c == ')' || c == ']' || c == '}':
			if depth--; depth < 0 {
				return nil, false
			}
		case c == ',' && depth == 0:
			fields = append(fields, s[start:i])
			start = i + 1
		}
	}
	return append(fields, s[start:]), depth == 0 && !quoted
}

// Each way a formula writes a key reads as that key, at the step it sits in,
// whether the step is a formula's, a child's, a loop's or a template's. What
// only reads metadata, the formula's own metadata and a var's definition read
// as no write.
func TestAFormulaWritesAKeyInEachForm(t *testing.T) {
	writes, err := formulaWrites([]byte(`
formula = "mol-fx"
description = "Its runs end with gc bd update X --set-metadata top.prose=1."

[metadata]
"formula.own" = "never copied onto a bead"

[vars.metadata]
description = "a var named metadata"

[[steps]]
id = "one"
description = """
gc bd update "$B" --set-metadata plain=1 --set-metadata "quoted=2" --set-metadata='equals=3' \\
  --set-metadata \\
  continued=4
gc bd update "$B" --unset-metadata gone --unset-metadata "gone.quoted";
gc bd create t --metadata '{"literal.a":"x","literal_b":{"inner":1}}' --json
gc bd create t --metadata "$(jq -nc --arg t "$BR" '{target: $t, "jq.quoted": "a, b", nested: {inner: 1}}')"
  META='{"from_var":"y"}'
gc bd create t --metadata "$META"
gc bd list --metadata-field read.field=1 --has-metadata-key=read.key
"""
metadata = { "step.key" = "v", bare_key = "w" }

[[steps.children]]
id = "child"
metadata = { "child.key" = "v" }

[[steps]]
id = "looped"
[steps.loop]
count = 2
[[steps.loop.body]]
id = "body"
metadata = { "body.key" = "v" }

[[template]]
id = "tmpl"
metadata = { "template.key" = "v" }
`))
	if err != nil {
		t.Fatal(err)
	}
	var got []string
	for _, w := range writes {
		got = append(got, w.where+" "+w.key)
	}
	want := []string{
		"description top.prose",
		"steps[one].children[child].metadata child.key",
		"steps[one].description plain",
		"steps[one].description quoted",
		"steps[one].description equals",
		"steps[one].description continued",
		"steps[one].description gone",
		"steps[one].description gone.quoted",
		"steps[one].description literal.a",
		"steps[one].description literal_b",
		"steps[one].description target",
		"steps[one].description jq.quoted",
		"steps[one].description nested",
		"steps[one].description from_var",
		"steps[one].metadata bare_key",
		"steps[one].metadata step.key",
		"steps[looped].loop.body[body].metadata body.key",
		"template[tmpl].metadata template.key",
	}
	if !slices.Equal(got, want) {
		t.Errorf("the writes read as\n%s\nwant\n%s", strings.Join(got, "\n"), strings.Join(want, "\n"))
	}
}

// A write whose key cannot be read is reported, with its text, never taken for
// no write.
func TestAWriteWhoseKeyCannotBeReadIsReported(t *testing.T) {
	writes, err := formulaWrites([]byte(`
[[steps]]
id = "bad"
description = """
gc bd update "$B" --set-metadata "$KV"
gc bd update "$B" --set-metadata "{{key}}=v"
gc bd update "$B" --set-metadata "<key>=<value>"
gc bd update "$B" --set-metadata "gc.var.$NAME=v"
gc bd update "$B" --unset-metadata "$K"
gc bd update "$B" --unset-metadata 'mismatched"
gc bd create t --metadata "$NOWHERE"
TWICE='{"a":1}'
TWICE='{"b":1}'
gc bd create t --metadata "$TWICE"
gc bd create t --metadata '{"<key>": 1}'
gc bd create t --metadata "$(jq -nc --arg k "$K" '{($k): 1}')"
gc bd create t --metadata "$(jq -nc --arg k "$K" '{"\\($k)": 1}')"
gc bd create t --metadata "$(jq -nc --arg t "$T" '{target: $t} + {other: 1}')"
gc bd create t --metadata
"""
metadata = { "{{var}}" = "v" }
`))
	if err != nil {
		t.Fatal(err)
	}
	var got []string
	for _, w := range writes {
		if w.key != "" {
			t.Errorf("%s read as writing %s", w.where, w.key)
		}
		got = append(got, w.where+" "+w.text)
	}
	want := []string{
		`steps[bad].description --set-metadata "$KV"`,
		`steps[bad].description --set-metadata "{{key}}=v"`,
		`steps[bad].description --set-metadata "<key>=<value>"`,
		`steps[bad].description --set-metadata "gc.var.$NAME=v"`,
		`steps[bad].description --unset-metadata "$K"`,
		`steps[bad].description --unset-metadata 'mismatched"`,
		`steps[bad].description --metadata "$NOWHERE"`,
		`steps[bad].description --metadata "$TWICE"`,
		`steps[bad].description --metadata '{"<key>": 1}'`,
		`steps[bad].description --metadata "$(jq -nc --arg k "$K" '{($k): 1}')"`,
		`steps[bad].description --metadata "$(jq -nc --arg k "$K" '{"\($k)": 1}')"`,
		`steps[bad].description --metadata "$(jq -nc --arg t "$T" '{target: $t} + {other: 1}')"`,
		`steps[bad].description --metadata`,
		`steps[bad].metadata "{{var}}"`,
	}
	if !slices.Equal(got, want) {
		t.Errorf("the unreadable writes read as\n%s\nwant\n%s", strings.Join(got, "\n"), strings.Join(want, "\n"))
	}
}

// The registry is the keys lifecycle.toml's [metadata.*] groups list, a
// wildcard holding its namespace, and the keys a gctk domain owns. A key named
// outside a group's keys, a key a domain only reads and an alias are not
// registered.
func TestTheRegistryHoldsLifecycleTomlsGroupsAndTheKeysADomainOwns(t *testing.T) {
	reg, err := readRegistry([]byte(`
# "in.comment" names a key only in a comment.
[holds]
keys = ["outside.group"]

[metadata.one]
keys = ["exact.key", "ns.*"]
`), []ledger.Entry{
		{Name: "owned.key", Owner: "pr/record", Aliases: []string{"legacy_alias"}},
		{Name: "read.only", Readers: []string{"listing"}},
	})
	if err != nil {
		t.Fatal(err)
	}
	for key, want := range map[string]bool{
		"exact.key": true, "ns.anything": true, "owned.key": true,
		"exact": false, "ns": false, "in.comment": false, "outside.group": false,
		"read.only": false, "legacy_alias": false,
	} {
		if reg.holds(key) != want {
			t.Errorf("the registry holds %s: %v, want %v", key, !want, want)
		}
	}
	if _, err := readRegistry([]byte("[holds]\nkeys = [\"x\"]\n"), nil); err == nil {
		t.Error("a lifecycle.toml whose [metadata.*] groups list no key read as a registry")
	}
}
