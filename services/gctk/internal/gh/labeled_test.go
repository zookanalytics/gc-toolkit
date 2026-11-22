package gh_test

import (
	"reflect"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
)

// A page of the search asks for the PRs in the repository that carry any label
// named, a hundred a page, and gives each PR's number and state and where the
// next page starts. The page after starts from that cursor.
func TestLabeledReadsOnePageOfTheSearch(t *testing.T) {
	c, r := client(
		[2]string{"after=cur1", `{"data":{"search":{"pageInfo":{"hasNextPage":false,"endCursor":"cur2"},
			"nodes":[{"number":3,"state":"MERGED"}]}}}`},
		[2]string{"search(type:ISSUE,first:100", `{"data":{"search":{"pageInfo":{"hasNextPage":true,"endCursor":"cur1"},
			"nodes":[{"number":9,"state":"OPEN"},{"number":5,"state":"CLOSED"}]}}}`},
	)
	first, err := c.Labeled("acme/widgets", []string{"status: working", "held: gate"}, "")
	if err != nil {
		t.Fatal(err)
	}
	want := gh.LabeledPage{PRs: []gh.LabeledPR{{Number: 9, State: "OPEN"}, {Number: 5, State: "CLOSED"}}, Next: "cur1"}
	if !reflect.DeepEqual(first, want) {
		t.Fatalf("the first page read as %+v, want %+v", first, want)
	}
	args := strings.Join(r.calls[0].args, " ")
	for _, want := range []string{"api --hostname github.com graphql",
		`-f q=repo:acme/widgets is:pr label:"status: working","held: gate"`} {
		if !strings.Contains(args, want) {
			t.Errorf("the search asks %q without %q", args, want)
		}
	}
	if strings.Contains(args, "after=") || strings.Contains(args, "--paginate") {
		t.Errorf("the first page names a cursor or pages on: %q", args)
	}
	last, err := c.Labeled("acme/widgets", []string{"status: working"}, first.Next)
	if err != nil {
		t.Fatal(err)
	}
	if want := (gh.LabeledPage{PRs: []gh.LabeledPR{{Number: 3, State: "MERGED"}}}); !reflect.DeepEqual(last, want) {
		t.Fatalf("the last page read as %+v, want %+v, with no cursor after it", last, want)
	}
}

// A page that does not answer whole is an error, never part of the results.
func TestLabeledRefusesAPageThatIsNotWhole(t *testing.T) {
	for _, tc := range []struct{ name, answer string }{
		{"an error", `PARTIAL:{"data":{"search":null},"errors":[{"message":"secondary rate limit"}]}`},
		{"no results", `{"data":{"search":null}}`},
		{"a result that is no PR", `{"data":{"search":{"pageInfo":{"hasNextPage":false},"nodes":[{}]}}}`},
		{"more with no cursor", `{"data":{"search":{"pageInfo":{"hasNextPage":true,"endCursor":""},"nodes":[]}}}`},
		{"gh failed", `ERR:gh: HTTP 502`},
	} {
		t.Run(tc.name, func(t *testing.T) {
			c, _ := client([2]string{"search(type:ISSUE", tc.answer})
			if page, err := c.Labeled("acme/widgets", []string{"status: working"}, ""); err == nil {
				t.Fatalf("the page read as %+v with no error", page)
			}
		})
	}
	c, r := client()
	for _, names := range [][]string{nil, {`status: "x"`}} {
		if _, err := c.Labeled("acme/widgets", names, ""); err == nil {
			t.Errorf("a search naming %q was asked", names)
		}
	}
	if _, err := c.Labeled("widgets", []string{"status: working"}, ""); err == nil {
		t.Error("a search of no owner/name was asked")
	}
	if len(r.calls) != 0 {
		t.Errorf("a refused search reached GitHub: %+v", r.calls)
	}
}
