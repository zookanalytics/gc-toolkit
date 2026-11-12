package pr

import (
	"errors"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

const (
	head    = "abcdef1234567890"
	newHead = "0123456789abcdef"
)

var gates = []Gate{{"correctness", phasePreOpen}, {"triage", phasePreOpen}}

// anchor is the bead that owns the PR: on polecat/A, with a summary and a
// dispatch text.
func anchor(meta map[string]string) fake.Bead {
	m := map[string]string{"branch": "polecat/A", "target": "main", "check_set": "correctness,triage",
		"merge_result": "pull_request", "pr_summary": "Adds the widget."}
	for k, v := range meta {
		m[k] = v
	}
	return fake.Bead{ID: "A", Title: "feat: add the widget", Status: "open", Description: "Build the widget.",
		CreatedAt: "2026-01-01T00:00:00Z", Metadata: m}
}

func storeWith(beads ...fake.Bead) *fake.Store {
	s := fake.New()
	for _, b := range beads {
		s.Put(b)
	}
	return s
}

func compose(t *testing.T, s gcbd.Store, req Request) *Composition {
	t.Helper()
	got, err := Compose(ledger.New(s), "A", req)
	if err != nil {
		t.Fatal(err)
	}
	return got
}

func bodyOf(s string) *string { return &s }

// opened is the body a create of the anchor's PR wrote at head.
func opened(t *testing.T, s gcbd.Store) string {
	t.Helper()
	return compose(t, s, Request{Head: head, Opening: true, Gates: gates, Summary: true}).Body
}

func TestComposeANewPR(t *testing.T) {
	s := storeWith(anchor(nil))
	got := compose(t, s, Request{Head: head, Opening: true, Gates: gates, Summary: true,
		Supersedes: &Superseded{Number: "41", Head: "1234567890abcdef"}})
	if got.Title != "feat: add the widget (A)" {
		t.Errorf("title = %q", got.Title)
	}
	if got.Summary != Written {
		t.Errorf("summary = %q, want written", got.Summary)
	}
	for _, want := range []string{
		summaryOpen + "\n## Summary\n\nAdds the widget.\n",
		"- Gates `correctness,triage` signed off pre-open at `abcdef12`. For CI status, see the PR checks.\n",
		"- Supersedes #41 (closed unmerged at `12345678`); re-implemented and re-gated at `abcdef12`.\n" + summaryClose + "\n",
	} {
		if !strings.Contains(got.Body, want) {
			t.Errorf("body lacks %q:\n%s", want, got.Body)
		}
	}
	if got.BranchBeads != "" || len(s.Finds()) != 1 {
		t.Errorf("a composition that does not ask for the branch-beads section reads no beads but its own: %q, %v", got.BranchBeads, s.Finds())
	}

	t.Run("without its gates a new PR's region is not composed", func(t *testing.T) {
		got := compose(t, s, Request{Head: head, Opening: true, Summary: true})
		if got.Summary != NeedsGates || got.Body != "" {
			t.Errorf("(%q, %q), want needs-gates and no body", got.Summary, got.Body)
		}
	})
}

func TestComposeAnAdoptedPR(t *testing.T) {
	s := storeWith(anchor(nil))
	req := func(body string) Request {
		return Request{Head: head, Opening: true, Gates: gates, Summary: true, Body: bodyOf(body)}
	}

	t.Run("a region that says it already is current", func(t *testing.T) {
		body := "Operator note.\n\n" + opened(t, s)
		got := compose(t, s, req(body))
		if got.Summary != Current || got.Body != body {
			t.Errorf("(%q, %q)", got.Summary, got.Body)
		}
	})

	t.Run("a region that differs is written in place, the text around it kept", func(t *testing.T) {
		body := "Operator note.\n" + summaryOpen + "\n## Summary\n\nOld.\n" + summaryClose + "\nAfter.\n"
		got := compose(t, s, req(body))
		if got.Summary != Written {
			t.Fatalf("summary = %q", got.Summary)
		}
		if !strings.HasPrefix(got.Body, "Operator note.\n"+opened(t, s)) || !strings.HasSuffix(got.Body, summaryClose+"\nAfter.\n") {
			t.Errorf("body:\n%s", got.Body)
		}
	})

	t.Run("a body written before the markers has the region marked over its shape", func(t *testing.T) {
		body := "## Summary\n\nOld.\n\n## Refinery handoff\n\n- Issue: `A`\n- Gates `x` signed off pre-open at `11111111`; PR opened green.\nOperator text.\n"
		got := compose(t, s, req(body))
		if got.Summary != Written || got.Body != opened(t, s)+"Operator text.\n" {
			t.Errorf("(%q):\n%s", got.Summary, got.Body)
		}
	})

	for name, body := range map[string]string{
		"a hand-written body":   "My own words.\n",
		"a lone marker":         summaryOpen + "\n## Summary\n",
		"a closer above opener": summaryClose + "\n" + summaryOpen + "\n",
	} {
		t.Run(name+" is left as it stands", func(t *testing.T) {
			got := compose(t, s, req(body))
			if got.Summary != Unmanaged || got.Body != body {
				t.Errorf("(%q, %q)", got.Summary, got.Body)
			}
		})
	}

	t.Run("a region to write with no gates is left, and says so", func(t *testing.T) {
		body := summaryOpen + "\nOld.\n" + summaryClose + "\n"
		got := compose(t, s, Request{Head: head, Opening: true, Summary: true, Body: bodyOf(body)})
		if got.Summary != NeedsGates || got.Body != body {
			t.Errorf("(%q, %q)", got.Summary, got.Body)
		}
	})
}

func TestComposeAnOpenPR(t *testing.T) {
	refresh := func(s gcbd.Store, body, at string, g []Gate) *Composition {
		return compose(t, s, Request{Head: at, Gates: g, Summary: true, Body: bodyOf(body)})
	}

	t.Run("a PR merely opened keeps the facts it opened with", func(t *testing.T) {
		s := storeWith(anchor(nil))
		body := opened(t, s)
		if got := refresh(s, body, head, gates); got.Summary != Current || got.Body != body {
			t.Errorf("(%q, %q)", got.Summary, got.Body)
		}
	})

	t.Run("a restamped summary is written in, naming the head", func(t *testing.T) {
		s := storeWith(anchor(nil))
		body := "Above.\n" + opened(t, s) + "Below.\n"
		s.Put(anchor(map[string]string{"pr_summary": "Adds the widget, reworked."}))
		got := refresh(s, body, head, gates)
		if got.Summary != Written {
			t.Fatalf("summary = %q", got.Summary)
		}
		for _, want := range []string{"Above.\n" + summaryOpen + "\n## Summary\n\nAdds the widget, reworked.\n",
			"- Head `abcdef12`; gates `correctness,triage`; see the PR checks for current status.\n" + summaryClose + "\nBelow.\n"} {
			if !strings.Contains(got.Body, want) {
				t.Errorf("body lacks %q:\n%s", want, got.Body)
			}
		}
		if again := refresh(s, got.Body, head, gates); again.Summary != Current {
			t.Errorf("the written region reads %q on the next pass", again.Summary)
		}
	})

	t.Run("a head a rework moved is written in", func(t *testing.T) {
		s := storeWith(anchor(nil))
		got := refresh(s, opened(t, s), newHead, gates)
		if got.Summary != Written || !strings.Contains(got.Body, "- Head `01234567`;") {
			t.Errorf("(%q):\n%s", got.Summary, got.Body)
		}
	})

	t.Run("a region saying the PR opened green is written over", func(t *testing.T) {
		s := storeWith(anchor(nil))
		body := strings.Replace(opened(t, s), "- Gates `correctness,triage` signed off pre-open at `abcdef12`. For CI status, see the PR checks.",
			"- Gates `correctness,triage` signed off pre-open at `abcdef12`; PR opened green.", 1)
		if got := refresh(s, body, head, gates); got.Summary != Written || strings.Contains(got.Body, "opened green") {
			t.Errorf("(%q):\n%s", got.Summary, got.Body)
		}
	})

	t.Run("the opened-green words quoted outside the region's facts are no claim", func(t *testing.T) {
		claim := "- Gates `correctness` signed off pre-open at `abcdef12`; PR opened green."
		s := storeWith(anchor(map[string]string{"pr_summary": "Drops the line that read\n\n" + claim}))
		body := opened(t, s) + "\nOperator note quoting it:\n" + claim + "\n## Refinery handoff\n\n" + claim + "\n"
		if got := refresh(s, body, head, gates); got.Summary != Current || got.Body != body {
			t.Errorf("(%q):\n%s", got.Summary, got.Body)
		}
	})

	// tk-tefrxph: a summary that carries a collapsed section of its own, opened
	// on a line of its own, read up to the first `<details>` line never matched
	// the bead's, so every pass edited a body that had not changed.
	t.Run("a summary with its own collapsed section reads current once written", func(t *testing.T) {
		own := "Brief.\n\n<details>\n<summary>The account</summary>\n\nWhat changed.\n\n</details>"
		s := storeWith(anchor(map[string]string{"pr_summary": own}))
		body := opened(t, s)
		if got := refresh(s, body, head, gates); got.Summary != Current {
			t.Errorf("the region a create wrote reads %q", got.Summary)
		}
		s.Put(anchor(map[string]string{"pr_summary": own + "\n\nOne more line."}))
		got := refresh(s, body, head, gates)
		if got.Summary != Written {
			t.Fatalf("a restamp reads %q", got.Summary)
		}
		if again := refresh(s, got.Body, head, gates); again.Summary != Current || again.Body != got.Body {
			t.Errorf("the next pass reads %q", again.Summary)
		}
	})

	t.Run("the summary is read whole, not to a boundary inside it", func(t *testing.T) {
		s := storeWith(anchor(map[string]string{"pr_summary": "Brief.\n\n## Refinery handoff\n\nQuoted."}))
		body := opened(t, s)
		s.Put(anchor(map[string]string{"pr_summary": "Brief."}))
		if got := refresh(s, body, head, gates); got.Summary != Written {
			t.Errorf("a summary that shrank to its first boundary reads %q", got.Summary)
		}
	})

	t.Run("a summary quoting the dispatch section's opener reads as itself", func(t *testing.T) {
		quoting := "Brief.\n\n<details>\n" + dispatchOpener + "\n\nQuoted."
		s := storeWith(anchor(map[string]string{"pr_summary": quoting}))
		body := opened(t, s)
		if got := refresh(s, body, head, gates); got.Summary != Current {
			t.Errorf("the region a create wrote reads %q", got.Summary)
		}
		s.Put(anchor(map[string]string{"pr_summary": "Brief."}))
		if got := refresh(s, body, head, gates); got.Summary != Written {
			t.Errorf("a summary that shrank to the quoted opener reads %q", got.Summary)
		}
	})

	t.Run("a changed dispatch text is written in", func(t *testing.T) {
		s := storeWith(anchor(nil))
		body := opened(t, s)
		b := anchor(nil)
		b.Description = "Build the widget, and its stand."
		s.Put(b)
		if got := refresh(s, body, head, gates); got.Summary != Written || !strings.Contains(got.Body, "\nBuild the widget, and its stand.\n") {
			t.Errorf("(%q):\n%s", got.Summary, got.Body)
		}
	})

	t.Run("a head the summary quotes is not one the facts name", func(t *testing.T) {
		s := storeWith(anchor(map[string]string{"pr_summary": "Fixes what `01234567` broke."}))
		body := opened(t, s)
		if got := refresh(s, body, newHead, gates); got.Summary != Written {
			t.Errorf("reads %q", got.Summary)
		}
	})

	t.Run("a stale region with no gates is left, and says so", func(t *testing.T) {
		s := storeWith(anchor(nil))
		body := opened(t, s)
		if got := refresh(s, body, newHead, nil); got.Summary != NeedsGates || got.Body != body {
			t.Errorf("(%q, %q)", got.Summary, got.Body)
		}
	})

	t.Run("a current region needs no gates", func(t *testing.T) {
		s := storeWith(anchor(nil))
		body := opened(t, s)
		if got := refresh(s, body, head, nil); got.Summary != Current {
			t.Errorf("reads %q", got.Summary)
		}
	})

	t.Run("an open PR's body written before the markers is left as it stands", func(t *testing.T) {
		s := storeWith(anchor(nil))
		body := "## Summary\n\nOld.\n\n## Refinery handoff\n\n- Issue: `A`\n"
		if got := refresh(s, body, head, gates); got.Summary != Unmanaged || got.Body != body {
			t.Errorf("(%q, %q)", got.Summary, got.Body)
		}
	})

	t.Run("a body's carriage returns do not hide its markers", func(t *testing.T) {
		s := storeWith(anchor(nil))
		body := strings.ReplaceAll(opened(t, s), "\n", "\r\n")
		if got := refresh(s, body, head, gates); got.Summary != Current || strings.Contains(got.Body, "\r") {
			t.Errorf("(%q, %q)", got.Summary, got.Body)
		}
	})
}

func TestComposeTheTarget(t *testing.T) {
	for _, c := range []struct {
		name string
		meta map[string]string
		want string
	}{
		{"merged_target first", map[string]string{"merged_target": "integration/x", "target": "main"}, "integration/x"},
		{"an empty merged_target gives way", map[string]string{"merged_target": "", "target": "integration/y"}, "integration/y"},
		{"main when neither is recorded", map[string]string{"target": ""}, "main"},
	} {
		got := compose(t, storeWith(anchor(c.meta)), Request{Head: head, Opening: true, Gates: gates, Summary: true})
		if !strings.Contains(got.Body, "- Target: `"+c.want+"`\n") {
			t.Errorf("%s:\n%s", c.name, got.Body)
		}
	}
}

func TestComposeTheBranchBeads(t *testing.T) {
	rider := func(id, created string, meta map[string]string) fake.Bead {
		return fake.Bead{ID: id, Title: "rider " + id, Status: "closed", CreatedAt: created, Metadata: meta}
	}
	beads := func(s gcbd.Store, body string) *Composition {
		return compose(t, s, Request{BranchBeads: true, Body: bodyOf(body)})
	}

	t.Run("one bead's work is the PR's own, and gets no section", func(t *testing.T) {
		got := beads(storeWith(anchor(nil)), "Body.\n")
		if got.BranchBeads != Single || got.BranchBeadCount != 1 || got.Body != "Body.\n" {
			t.Errorf("(%q, %d, %q)", got.BranchBeads, got.BranchBeadCount, got.Body)
		}
	})

	t.Run("each record that puts a bead's work on the branch names it", func(t *testing.T) {
		s := storeWith(anchor(nil),
			rider("F", "2026-02-01T00:00:00Z", map[string]string{"fold_target": "polecat/A"}),
			rider("M", "2026-03-01T00:00:00Z", map[string]string{"branch": "polecat/M", "merged_target": "polecat/A", "merge_result": "merged"}),
			rider("H", "2026-04-01T00:00:00Z", map[string]string{"branch": "polecat/A", "gc.routed_to": "human"}),
			rider("R", "2026-05-01T00:00:00Z", map[string]string{"branch": "polecat/A", "gc.routed_to": "", "fold_target": "polecat/A"}),
		)
		got := beads(s, "Body.\n")
		want := "Body.\n\n" + beadsOpen + "\n## Beads on this branch\n\nEvery bead whose work is on `polecat/A`. " +
			"Approving this PR approves all of them.\n\n" +
			"- `A` — feat: add the widget _(opener)_\n" +
			"- `F` — rider F\n" +
			"- `M` — rider M _(merged in from `polecat/M`)_\n" +
			"- `H` — rider H\n" +
			"- `R` — rider R\n" + beadsClose + "\n"
		if got.BranchBeads != Written || got.BranchBeadCount != 5 || got.Body != want {
			t.Errorf("(%q, %d):\n%s", got.BranchBeads, got.BranchBeadCount, got.Body)
		}
		if again := beads(s, got.Body); again.BranchBeads != Current || again.Body != got.Body {
			t.Errorf("the next pass reads %q", again.BranchBeads)
		}
	})

	t.Run("a bead that put no work on the branch is left out", func(t *testing.T) {
		s := storeWith(anchor(nil),
			rider("P", "2026-02-01T00:00:00Z", map[string]string{"branch": "polecat/A", "gc.routed_to": "gc-toolkit/gc-toolkit.polecat"}),
			fake.Bead{ID: "D", Title: "dup", Status: "closed", Metadata: map[string]string{"branch": "polecat/A"},
				Edges: []gcbd.Edge{{Type: "duplicates", ID: "A"}}},
			rider("N", "2026-02-01T00:00:00Z", map[string]string{"branch": "polecat/A", "gc.work_outcome": "no-op"}),
			rider("O", "2026-02-01T00:00:00Z", map[string]string{"branch": "polecat/A", "work_outcome": "no-op"}),
			rider("U", "2026-02-01T00:00:00Z", map[string]string{"merged_target": "polecat/A", "merge_result": "pull_request"}),
			fake.Bead{ID: "G", Title: "gate", Status: "open", IssueType: "gate", Metadata: map[string]string{"branch": "polecat/A"}},
			fake.Bead{ID: "W", Title: "wisp", Status: "open", Ephemeral: true, Metadata: map[string]string{"branch": "polecat/A"}},
			fake.Bead{ID: "T", Title: "template", Status: "open", Template: true, Metadata: map[string]string{"fold_target": "polecat/A"}},
		)
		if got := beads(s, "Body.\n"); got.BranchBeads != Single || got.BranchBeadCount != 1 {
			t.Errorf("(%q, %d)", got.BranchBeads, got.BranchBeadCount)
		}
	})

	t.Run("a pool's child that carries a merge_result is an anchor of the branch", func(t *testing.T) {
		s := storeWith(anchor(nil), rider("C", "2026-02-01T00:00:00Z",
			map[string]string{"branch": "polecat/A", "gc.routed_to": "gc-toolkit/gc-toolkit.polecat", "merge_result": "pre_open_gate"}))
		if got := beads(s, "Body.\n"); got.BranchBeadCount != 2 {
			t.Errorf("count = %d", got.BranchBeadCount)
		}
	})

	two := storeWith(anchor(nil), rider("F", "2026-02-01T00:00:00Z", map[string]string{"fold_target": "polecat/A"}))

	t.Run("a section behind is written in place", func(t *testing.T) {
		body := "Body.\n" + beadsOpen + "\nold\n" + beadsClose + "\nAfter.\n"
		got := beads(two, body)
		if got.BranchBeads != Written || !strings.HasPrefix(got.Body, "Body.\n"+beadsOpen+"\n## Beads") ||
			!strings.HasSuffix(got.Body, "- `F` — rider F\n"+beadsClose+"\nAfter.\n") {
			t.Errorf("(%q):\n%s", got.BranchBeads, got.Body)
		}
	})

	t.Run("markers cut into another shape are left as they stand", func(t *testing.T) {
		body := "Body.\n" + beadsOpen + "\nold\n"
		if got := beads(two, body); got.BranchBeads != Unmanaged || got.Body != body {
			t.Errorf("(%q, %q)", got.BranchBeads, got.Body)
		}
	})

	t.Run("a read that fails leaves the section, and the rest is composed", func(t *testing.T) {
		s := &failing{Store: two, key: "fold_target"}
		body := opened(t, two)
		got := compose(t, s, Request{Head: newHead, Gates: gates, Summary: true, BranchBeads: true, Body: bodyOf(body)})
		if got.BranchBeads != Unread || got.Unread == nil || got.Summary != Written {
			t.Errorf("(%q, %v, %q)", got.BranchBeads, got.Unread, got.Summary)
		}
		if strings.Contains(got.Body, beadsOpen) {
			t.Errorf("a short list was published:\n%s", got.Body)
		}
	})
}

// failing fails each find that selects by key.
type failing struct {
	*fake.Store
	key string
}

func (f *failing) Find(q gcbd.Query) ([]gcbd.Bead, error) {
	if q.Key == f.key {
		return nil, &gcbd.ReadError{Reason: "simulated"}
	}
	return f.Store.Find(q)
}

func TestComposeABeadThatDoesNotRead(t *testing.T) {
	if _, err := Compose(ledger.New(fake.New()), "A", Request{Head: head, Summary: true}); err == nil {
		t.Error("a bead the store does not hold composed")
	}
	s := storeWith(anchor(nil))
	s.FindErr = errors.New("simulated")
	if _, err := Compose(ledger.New(s), "A", Request{Head: head, Summary: true}); err == nil {
		t.Error("a bead whose read failed composed")
	}
}

func TestParseGates(t *testing.T) {
	got := ParseGates("correctness\tpre-open\n\ndemo\topen-as-draft\nodd")
	want := []Gate{{"correctness", "pre-open"}, {"demo", "open-as-draft"}, {"odd", ""}}
	if len(got) != len(want) {
		t.Fatalf("%v", got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("%v, want %v", got, want)
		}
	}
	if ParseGates("") != nil {
		t.Error("an empty set names a gate")
	}
}
