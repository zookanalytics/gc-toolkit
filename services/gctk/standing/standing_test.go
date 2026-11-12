package standing

import (
	"encoding/json"
	"slices"
	"strings"
	"testing"
)

// The compiled-in definition reads as kinds.json holds it: every key a kind,
// sorted, and nothing else.
func TestKindsAreTheDefinitionsKeys(t *testing.T) {
	var byKind map[string]string
	if err := json.Unmarshal(definition, &byKind); err != nil {
		t.Fatal(err)
	}
	var want []string
	for k := range byKind {
		want = append(want, k)
	}
	slices.Sort(want)
	if got := Kinds(); len(got) == 0 || !slices.Equal(got, want) {
		t.Fatalf("Kinds() = %v, want the definition's keys %v", got, want)
	}
	got := Kinds()
	got[0] = "changed"
	if Kinds()[0] == "changed" {
		t.Error("Kinds() hands out the package's own list")
	}
}

// Every listed kind is a standing record's, and nothing else is: not an empty
// or absent task_kind, a near miss, a kind in another case, or an ordinary
// kind.
func TestIs(t *testing.T) {
	for _, k := range Kinds() {
		if !Is(k) {
			t.Errorf("Is(%q) = false for a listed kind", k)
		}
		for _, near := range []string{k + "s", " " + k, k + " ", strings.ToUpper(k)} {
			if Is(near) {
				t.Errorf("Is(%q) = true for a near miss of %q", near, k)
			}
		}
	}
	for _, k := range []string{"", "review", "rework", "finding", "observation"} {
		if Is(k) {
			t.Errorf("Is(%q) = true", k)
		}
	}
}

// A definition that does not hold kinds with text is refused, never read as
// fewer kinds.
func TestParseRefusesWhatIsNoDefinition(t *testing.T) {
	for name, raw := range map[string]string{
		"not json":          `{`,
		"an array":          `["a"]`,
		"null":              `null`,
		"no kind":           `{}`,
		"an empty kind":     `{"": "a record"}`,
		"a blank record":    `{"a": "  "}`,
		"a record not text": `{"a": 1}`,
	} {
		if got, err := parse([]byte(raw)); err == nil {
			t.Errorf("%s: parse(%s) = %v, want an error", name, raw, got)
		}
	}
	got, err := parse([]byte(`{"b": "a record", "a": "another"}`))
	if err != nil || !slices.Equal(got, []string{"a", "b"}) {
		t.Errorf("parse = %v, %v, want both kinds sorted", got, err)
	}
}
