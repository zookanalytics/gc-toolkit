package gh

import (
	"errors"
	"strings"
	"testing"
)

// answers serves a recorded answer for each call by the path it names, and
// logs every call.
func answers(t *testing.T, byPath map[string]string, log *[]string) Runner {
	t.Helper()
	return func(args ...string) ([]byte, error) {
		*log = append(*log, strings.Join(args, " "))
		for _, a := range args {
			if body, ok := byPath[a]; ok {
				if body == "!" {
					return nil, errors.New("gh: HTTP 502")
				}
				return []byte(body), nil
			}
		}
		return nil, errors.New("gh: no recorded answer")
	}
}

// The default branch is read from the repository, and an answer naming none is
// an error.
func TestTheDefaultBranchIsTheRepositorys(t *testing.T) {
	var log []string
	c := NewWithRunner("github.com", answers(t, map[string]string{
		"repos/o/r":    `{"name":"r","default_branch":"main"}`,
		"repos/o/none": `{"name":"none"}`,
	}, &log))
	if b, err := c.DefaultBranch("o/r"); err != nil || b != "main" {
		t.Fatalf("DefaultBranch = %q, %v", b, err)
	}
	if log[0] != "api --hostname github.com repos/o/r" {
		t.Fatalf("the read ran %q", log[0])
	}
	if b, err := c.DefaultBranch("o/none"); err == nil {
		t.Fatalf("a repository naming no default branch read as %q", b)
	}
	if _, err := c.DefaultBranch("not-a-repo"); err == nil {
		t.Fatal("a name with no owner read as a repository")
	}
}

// The checks at a ref are every check run and every commit status across all
// their pages, at the commit the statuses name, and a page that carries no list
// of its checks fails the whole read.
func TestTheChecksAtARefAreEveryPage(t *testing.T) {
	var log []string
	c := NewWithRunner("github.com", answers(t, map[string]string{
		"repos/o/r/commits/main/check-runs?per_page=100": `{"total_count":3,"check_runs":[{"name":"go","conclusion":"success","head_sha":"abc"},{"name":"lint","conclusion":null,"head_sha":"abc"}]}
{"total_count":3,"check_runs":[{"name":"shell","conclusion":"failure","head_sha":"abc"}]}`,
		"repos/o/r/commits/main/status?per_page=100": `{"sha":"abcdef","statuses":[{"context":"ci/x","state":"error"}]}{"sha":"abcdef","statuses":[{"context":"ci/y","state":"success"}]}`,
	}, &log))
	h, err := c.HeadChecks("o/r", "main")
	if err != nil {
		t.Fatal(err)
	}
	if h.SHA != "abcdef" || len(h.Runs) != 3 || h.Runs[2].Conclusion != "failure" || h.Runs[1].Conclusion != "" ||
		len(h.Statuses) != 2 || h.Statuses[0].State != "error" || h.Statuses[1].Context != "ci/y" {
		t.Fatalf("HeadChecks = %+v", h)
	}
	if !strings.HasSuffix(log[0], "--paginate") || !strings.HasSuffix(log[1], "--paginate") {
		t.Fatalf("the reads ran %q, each to its last page", log)
	}
	for name, body := range map[string]string{
		"a page with no list": `{"total_count":1,"check_runs":[]}{"message":"rate limited"}`,
		"no page at all":      ``,
		"a read that failed":  `!`,
	} {
		var log []string
		c := NewWithRunner("github.com", answers(t, map[string]string{
			"repos/o/r/commits/main/check-runs?per_page=100": body,
			"repos/o/r/commits/main/status?per_page=100":     `{"sha":"abc","statuses":[]}`,
		}, &log))
		if h, err := c.HeadChecks("o/r", "main"); err == nil {
			t.Errorf("%s read as %+v", name, h)
		}
	}
}
