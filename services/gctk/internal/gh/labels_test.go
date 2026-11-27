package gh_test

import (
	"reflect"
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
)

// A PR's labels are read from GitHub's REST API across every page, each label
// by its name.
func TestPullRequestLabelsReadsEveryPage(t *testing.T) {
	c, r := client([2]string{"repos/acme/widgets/issues/7/labels?per_page=100",
		`[{"name":"status: working","color":"1D76DB"},{"name":"bug"}][{"name":"held: gate"}]`})
	got, err := c.PullRequestLabels("acme/widgets", 7)
	if err != nil {
		t.Fatal(err)
	}
	if want := []string{"status: working", "bug", "held: gate"}; !slices.Equal(got, want) {
		t.Fatalf("the PR's labels read as %q, want %q", got, want)
	}
	if args := strings.Join(r.calls[0].args, " "); !strings.HasPrefix(args, "api --hostname github.com ") ||
		!strings.HasSuffix(args, " --paginate") {
		t.Errorf("the read asks %q", args)
	}
}

// A repository's labels are read across every page, each with its colour and
// its description.
func TestRepoLabelsReadsEveryPage(t *testing.T) {
	c, _ := client([2]string{"repos/acme/widgets/labels?per_page=100",
		`[{"name":"status: working","color":"1D76DB","description":"Workflow: busy."}][{"name":"bug","color":"d73a4a","description":null}]`})
	got, err := c.RepoLabels("acme/widgets")
	if err != nil {
		t.Fatal(err)
	}
	want := []gh.Label{{Name: "status: working", Color: "1D76DB", Description: "Workflow: busy."}, {Name: "bug", Color: "d73a4a"}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("the repository's labels read as %+v, want %+v", got, want)
	}
}

// A read of labels that does not answer whole is an error, never part of the
// labels.
func TestALabelReadThatIsNotWholeIsAnError(t *testing.T) {
	for _, tc := range []struct{ name, answer string }{
		{"no list", `{"message":"Not Found"}`},
		{"a null page", `null`},
		{"a label with no name", `[{"color":"1D76DB"}]`},
		{"a page that does not decode", `[{"name":"bug"}][`},
		{"no page", ``},
		{"gh failed", `ERR:gh: HTTP 502`},
	} {
		t.Run(tc.name, func(t *testing.T) {
			c, _ := client([2]string{"/labels?per_page=100", tc.answer})
			if got, err := c.PullRequestLabels("acme/widgets", 7); err == nil {
				t.Errorf("the PR's labels read as %q with no error", got)
			}
			if got, err := c.RepoLabels("acme/widgets"); err == nil {
				t.Errorf("the repository's labels read as %+v with no error", got)
			}
		})
	}
}

// Each write is one request that names the label by its name, escaped where it
// is part of the path, with every other value as a raw field.
func TestTheLabelWritesNameEachLabel(t *testing.T) {
	c, r := client([2]string{"api", "{}"})
	l := gh.Label{Name: "status: needs-review", Color: "1D76DB", Description: "Workflow: @settled; awaiting review."}
	for _, err := range []error{
		c.CreateLabel("acme/widgets", l),
		c.EditLabel("acme/widgets", l),
		c.AddLabels("acme/widgets", 7, []string{"status: needs-review", "held: gate"}),
		c.RemoveLabel("acme/widgets", 7, "status: working"),
	} {
		if err != nil {
			t.Fatal(err)
		}
	}
	want := [][]string{
		{"api", "--hostname", "github.com", "-X", "POST", "repos/acme/widgets/labels",
			"-f", "name=status: needs-review", "-f", "color=1D76DB", "-f", "description=Workflow: @settled; awaiting review."},
		{"api", "--hostname", "github.com", "-X", "PATCH", "repos/acme/widgets/labels/status:%20needs-review",
			"-f", "description=Workflow: @settled; awaiting review."},
		{"api", "--hostname", "github.com", "-X", "POST", "repos/acme/widgets/issues/7/labels",
			"-f", "labels[]=status: needs-review", "-f", "labels[]=held: gate"},
		{"api", "--hostname", "github.com", "-X", "DELETE", "repos/acme/widgets/issues/7/labels/status:%20working"},
	}
	for i, w := range want {
		if !slices.Equal(r.calls[i].args, w) {
			t.Errorf("write %d asked %q, want %q", i, r.calls[i].args, w)
		}
	}
}

// A write GitHub refuses returns gh's error.
func TestALabelWriteGitHubRefusesIsAnError(t *testing.T) {
	c, _ := client([2]string{"api", "ERR:gh: Label does not exist (HTTP 404)"})
	if err := c.RemoveLabel("acme/widgets", 7, "status: working"); err == nil || !gh.Refused(err) {
		t.Fatalf("a refused removal returned %v", err)
	}
	if err := c.AddLabels("acme/widgets", 7, []string{"held: gate"}); err == nil {
		t.Fatal("a refused add returned no error")
	}
}

// A request that names no label, no PR or no owner/name never reaches GitHub.
func TestALabelRequestThatNamesNothingIsRefused(t *testing.T) {
	c, r := client([2]string{"api", "{}"})
	for name, err := range map[string]error{
		"a create with no name":           c.CreateLabel("acme/widgets", gh.Label{Color: "1D76DB"}),
		"an edit with no name":            c.EditLabel("acme/widgets", gh.Label{Description: "x"}),
		"an add of no label":              c.AddLabels("acme/widgets", 7, nil),
		"an add of a blank label":         c.AddLabels("acme/widgets", 7, []string{"held: gate", " "}),
		"a removal with no name":          c.RemoveLabel("acme/widgets", 7, ""),
		"a removal on no PR":              c.RemoveLabel("acme/widgets", 0, "held: gate"),
		"a create in no repository":       c.CreateLabel("widgets", gh.Label{Name: "held: gate"}),
		"a read of no PR":                 func() error { _, err := c.PullRequestLabels("acme/widgets", 0); return err }(),
		"a read of no owner/name":         func() error { _, err := c.RepoLabels("acme"); return err }(),
		"an add to a PR in no owner/name": c.AddLabels("acme", 7, []string{"held: gate"}),
	} {
		if err == nil {
			t.Errorf("%s returned no error", name)
		}
	}
	if len(r.calls) != 0 {
		t.Fatalf("a refused request reached GitHub: %+v", r.calls)
	}
}
