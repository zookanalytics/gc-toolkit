package pr

import (
	"encoding/json"
	"flag"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// The goldens under testdata are the renders the shell composer
// (assets/scripts/pr-summary-region.sh and pr-stack.sh) produced for each case
// when this package replaced it. -update rewrites them from the code, for a
// change that means to move a render.
var update = flag.Bool("update", false, "rewrite the golden renders under testdata from the code")

func golden(t *testing.T, path, got string) {
	t.Helper()
	if *update {
		if err := os.WriteFile(path, []byte(got), 0o644); err != nil {
			t.Fatal(err)
		}
		return
	}
	want, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if got != string(want) {
		t.Errorf("%s:\n got: %q\nwant: %q", path, got, want)
	}
}

func readCases[T any](t *testing.T, path string) []T {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var out []T
	if err := json.Unmarshal(raw, &out); err != nil {
		t.Fatal(err)
	}
	return out
}

// Each case is a bead the region is composed from, read through the store the
// way a composition reads it, so the summary's and the dispatch text's
// trimming are pinned with the render.
func TestRegionRendersAsBefore(t *testing.T) {
	type regionCase struct {
		Name, Summary, Desc, ID, Branch, Target, Mode, Gates, Head string
		CheckSet                                                   string `json:"check_set"`
		SupNum                                                     string `json:"sup_num"`
		SupHead                                                    string `json:"sup_head"`
	}
	for _, c := range readCases[regionCase](t, "testdata/region-cases.json") {
		t.Run(c.Name, func(t *testing.T) {
			meta := map[string]string{"branch": c.Branch, "target": c.Target, "check_set": c.CheckSet}
			if c.Summary != "" {
				meta["pr_summary"] = c.Summary
			}
			store := fake.New()
			store.Put(fake.Bead{ID: c.ID, Title: "t", Status: "open", Description: c.Desc, Metadata: meta})
			req := Request{Head: c.Head, Opening: c.Mode == "open", Gates: gatesOf(c.Gates), Summary: true}
			if c.SupNum != "" {
				req.Supersedes = &Superseded{Number: c.SupNum, Head: c.SupHead}
			}
			got, err := Compose(ledger.New(store), c.ID, req)
			if err != nil {
				t.Fatal(err)
			}
			lines := textLines(got.Body)
			if len(lines) < 2 || lines[0] != summaryOpen || lines[len(lines)-1] != summaryClose {
				t.Fatalf("a PR not opened yet has the marked region as its body, got %q", got.Body)
			}
			golden(t, filepath.Join("testdata/region", c.Name+".golden"), text(lines[1:len(lines)-1]))
		})
	}
}

// gatesOf is a resolved gate set, empty rather than nil when it names none.
func gatesOf(s string) []Gate {
	if g := ParseGates(s); g != nil {
		return g
	}
	return []Gate{}
}

func TestTitleRendersAsBefore(t *testing.T) {
	type titleCase struct{ Title, Kind, ID, Want string }
	for _, c := range readCases[titleCase](t, "testdata/titles.json") {
		if got := Title(c.ID, c.Title, c.Kind); got != c.Want {
			t.Errorf("Title(%q, %q) = %q, want %q", c.Title, c.Kind, got, c.Want)
		}
	}
}

func TestBeadsSectionRendersAsBefore(t *testing.T) {
	type row struct {
		ID, Title string
		CreatedAt string            `json:"created_at"`
		Metadata  map[string]string `json:"metadata"`
	}
	type beadsCase struct {
		Name, Branch, Anchor string
		Ledger               []row
	}
	for _, c := range readCases[beadsCase](t, "testdata/beads-cases.json") {
		t.Run(c.Name, func(t *testing.T) {
			var beads []onBranch
			for _, r := range c.Ledger {
				beads = append(beads, onBranch{id: r.ID, title: r.Title, created: r.CreatedAt, branch: r.Metadata["branch"]})
			}
			golden(t, filepath.Join("testdata/beads", c.Name+".golden"), text(beadsSection(c.Branch, c.Anchor, beads)))
		})
	}
}

// The body edits around the sections: a region written in place, one marked
// over a body written before the markers existed, and the branch-beads section
// added or written in place, each beside text people added.
func TestBodyEditsAsBefore(t *testing.T) {
	region := textLines("## Summary\n\nNew summary.\n\n## Refinery handoff\n\n- Issue: `tk-a1`\n" +
		"- Head `abcdef12`; gates `correctness`; see the PR checks for current status.\n")
	beads := textLines("## Beads on this branch\n\nEvery bead whose work is on `polecat/A`. Approving this PR " +
		"approves all of them.\n\n- `A` — anchor _(opener)_\n- `B` — rider\n")
	in := func(name string) []string {
		raw, err := os.ReadFile(filepath.Join("testdata/body", name+".in"))
		if err != nil {
			t.Fatal(err)
		}
		return textLines(string(raw))
	}
	out := func(name string, lines []string) {
		golden(t, filepath.Join("testdata/body", name+".golden"), text(lines))
	}

	body := in("splice_region")
	if markers(body, summaryOpen, summaryClose) != markersOne {
		t.Fatal("splice_region carries one pair of markers")
	}
	out("splice_region", splice(body, summaryOpen, summaryClose, region))

	for _, name := range []string{"establish_legacy", "establish_no_bullets"} {
		got, ok := establish(in(name), region)
		if !ok {
			t.Fatalf("%s carries the shape written before the markers", name)
		}
		out(name, got)
	}
	for _, name := range []string{"establish_refused", "establish_no_handoff"} {
		if _, ok := establish(in(name), region); ok {
			t.Errorf("%s does not carry the shape written before the markers, yet a region was marked over it", name)
		}
	}

	out("append_beads", appendSection(in("append_beads"), beadsOpen, beadsClose, beads))
	out("append_empty", appendSection(in("append_empty"), beadsOpen, beadsClose, beads))
	body = in("splice_beads")
	if markers(body, beadsOpen, beadsClose) != markersOne {
		t.Fatal("splice_beads carries one pair of markers")
	}
	out("splice_beads", splice(body, beadsOpen, beadsClose, beads))
}

func TestMarkerShapes(t *testing.T) {
	for _, c := range []struct {
		name string
		body string
		want int
	}{
		{"one pair", "a\n" + summaryOpen + "\nx\n" + summaryClose + "\nb\n", markersOne},
		{"none", "a\nb\n", markersNone},
		{"a closer above its opener", summaryClose + "\nx\n" + summaryOpen + "\n", markersOther},
		{"a lone opener", summaryOpen + "\nx\n", markersOther},
		{"a lone closer", "x\n" + summaryClose + "\n", markersOther},
		{"two pairs", summaryOpen + "\na\n" + summaryClose + "\n" + summaryOpen + "\nb\n" + summaryClose + "\n", markersOther},
		{"an indented marker is not one", " " + summaryOpen + "\na\n" + summaryClose + "\n", markersOther},
	} {
		if got := markers(textLines(c.body), summaryOpen, summaryClose); got != c.want {
			t.Errorf("%s: markers = %d, want %d", c.name, got, c.want)
		}
	}
}

func TestTextLines(t *testing.T) {
	for _, c := range []struct {
		in   string
		want []string
	}{
		{"", nil},
		{"\n", []string{""}},
		{"a", []string{"a"}},
		{"a\n", []string{"a"}},
		{"a\n\n", []string{"a", ""}},
		{"a\nb", []string{"a", "b"}},
	} {
		if got := textLines(c.in); strings.Join(got, "|") != strings.Join(c.want, "|") || len(got) != len(c.want) {
			t.Errorf("textLines(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}
