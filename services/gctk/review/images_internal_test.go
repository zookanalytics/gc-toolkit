package review

import (
	"fmt"
	"os"
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	rtfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity/fake"
)

// The parts of a name that vary are the last ones that take few values,
// fewer than there are names, while every name keeps a part before them.
func TestVariantParts(t *testing.T) {
	var matrix []string
	for _, page := range []string{"account", "admin-users", "home"} {
		for _, theme := range []string{"dark", "light"} {
			for _, browser := range []string{"chromium", "webkit"} {
				matrix = append(matrix, page+"-"+theme+"-"+browser+"-linux.png")
			}
		}
	}
	var numbered []string
	for _, prefix := range []string{"x", "y"} {
		for i := 1; i <= maxVariants+1; i++ {
			numbered = append(numbered, fmt.Sprintf("%s-%d.png", prefix, i))
		}
	}
	for _, c := range []struct {
		why   string
		names []string
		want  int
	}{
		{"a theme, a browser and a platform vary across three pages", matrix, 3},
		{"names of one part keep it", []string{"library.png", "onboarding.png"}, 0},
		{"one name has nothing to vary across", []string{"home-dark.png"}, 0},
		{"a size varies across two icons", []string{"icon-16.png", "icon-32.png", "logo-16.png", "logo-32.png"}, 1},
		{"a part taking more values than a variant does names what the image shows", numbered, 0},
		{"a part with a value for each name names it", []string{"home-dark.png", "home-light.png"}, 0},
	} {
		if got := variantParts(c.names); got != c.want {
			t.Errorf("%s: %d parts vary, want %d", c.why, got, c.want)
		}
	}
	if got := stem("admin-users-dark-chromium-linux.png", 3); got != "admin-users" {
		t.Errorf("the stem of admin-users-dark-chromium-linux.png less 3 parts read %q", got)
	}
}

// Comments split where one would pass GitHub's limit on a comment's length:
// groups pack into as few comments as fit, a group too long for one comment
// splits into parts, the images it moves without a change among them, and
// each comment says which it is.
func TestImageCommentsSplitUnderTheLimit(t *testing.T) {
	head, base := strings.Repeat("a", 40), strings.Repeat("b", 40)
	im := Images{Head: head, MergeBase: base}
	for i := 0; i < 400; i++ {
		im.Changes = append(im.Changes, Image{Kind: ImageChanged,
			Path: fmt.Sprintf("tests/visual/__screenshots__/a-page-with-a-long-name-%03d-dark-desktop-chromium-linux.png", i)})
	}
	bodies := im.ImageComments("github.com", "acme/widgets")
	if len(bodies) < 2 {
		t.Fatalf("400 changed images fit in %d comment", len(bodies))
	}
	rows := 0
	for i, b := range bodies {
		if n := len(b); n > commentLimit-100 {
			t.Errorf("comment %d holds %d bytes, more than GitHub takes with the city's mark", i+1, n)
		}
		if !strings.Contains(b, fmt.Sprintf(" This is comment %d of %d.\n\n", i+1, len(bodies))) {
			t.Errorf("comment %d does not say which of %d it is", i+1, len(bodies))
		}
		if !strings.Contains(b, fmt.Sprintf(", part %d of %d</summary>", i+1, len(bodies))) {
			t.Errorf("comment %d does not name its part of the group", i+1)
		}
		rows += strings.Count(b, `alt="after: `)
	}
	if rows != 400 {
		t.Errorf("the comments show %d images, want 400", rows)
	}

	// With room for one group a comment, two small groups take two comments.
	two := Images{Head: head, MergeBase: base, Changes: []Image{
		{Kind: ImageAdded, Path: "a/one.png"}, {Kind: ImageAdded, Path: "b/two.png"}}}
	one := two.comments("github.com", "acme/widgets", 1500)
	if len(one) != 1 {
		t.Fatalf("two small groups took %d comments with room for both", len(one))
	}
	if got := two.comments("github.com", "acme/widgets", len(one[0])/2+50); len(got) != 2 {
		t.Fatalf("two groups with room for one a comment took %d comments", len(got))
	}

	// The images a group moves without a change split the same way, after its
	// rows, so a change that moves many images fits too.
	for _, c := range []struct {
		why            string
		changed, moved int
	}{
		{"a thousand images moved", 0, 1000},
		{"rows past one comment, then images moved", 150, 300},
	} {
		im := Images{Head: head, MergeBase: base}
		for i := 0; i < c.changed; i++ {
			im.Changes = append(im.Changes, Image{Kind: ImageChanged,
				Path: fmt.Sprintf("tests/visual/after/a-page-with-a-long-name-%04d-dark-desktop-chromium-linux.png", i)})
		}
		for i := 0; i < c.moved; i++ {
			name := fmt.Sprintf("an-unchanged-page-with-a-long-name-%04d-dark-desktop-chromium-linux.png", i)
			im.Changes = append(im.Changes, Image{Kind: ImageMoved, Path: "tests/visual/after/" + name, From: "tests/visual/before/" + name})
		}
		bodies := im.ImageComments("github.com", "acme/widgets")
		shown, moved := 0, 0
		for i, b := range bodies {
			if n := len(b); n > commentLimit-100 {
				t.Errorf("%s: comment %d holds %d bytes, more than GitHub takes with the city's mark", c.why, i+1, n)
			}
			shown += strings.Count(b, `alt="after: `)
			moved += strings.Count(b, " from <code>tests/visual/before/")
		}
		if len(bodies) < 2 || shown != c.changed || moved != c.moved {
			t.Errorf("%s: %d comments show %d images and name %d moved, want more than one showing %d and naming %d",
				c.why, len(bodies), shown, moved, c.changed, c.moved)
		}
	}
}

// A comment that does not post ends the post. The error names it and the
// comments that posted, which stay on the PR, and what the writer printed for
// those comes back.
func TestPostNamesTheCommentThatDidNotPostAndThoseThatDid(t *testing.T) {
	var bodies []string
	rt := &rtfake.Runtime{OnScript: func(c rtfake.Call) gascity.Result {
		body, err := os.ReadFile(c.Args[len(c.Args)-1])
		if err != nil {
			t.Errorf("the writer was handed no comment to post: %v", err)
		}
		bodies = append(bodies, string(body))
		if len(bodies) == 2 {
			return gascity.Result{Code: 1, Output: "HTTP 502: Bad Gateway"}
		}
		return gascity.Result{Output: fmt.Sprintf("https://github.com/acme/widgets/pull/7#issuecomment-%d\n", len(bodies))}
	}}
	show := ImagesOnPR{Comments: []string{"one", "two", "three"}, PR: "https://github.com/acme/widgets/pull/7",
		host: "github.com", repo: "acme/widgets", number: 7}
	printed, err := show.Post(rt)
	if err == nil || !strings.Contains(err.Error(), "comment 2 of 3 did not post on https://github.com/acme/widgets/pull/7: ") ||
		!strings.HasSuffix(err.Error(), "; comments 1 to 1 posted") {
		t.Errorf("a post that failed at its second comment answered %v", err)
	}
	if !slices.Equal(printed, []string{"https://github.com/acme/widgets/pull/7#issuecomment-1"}) {
		t.Errorf("the writer's lines for the comments that posted are %q", printed)
	}
	if !slices.Equal(bodies, []string{"one", "two"}) {
		t.Errorf("the writer was handed %q", bodies)
	}
	calls := rt.Scripts()
	want := []string{"comment", "--repo", "github.com/acme/widgets", "--pr", "7", "--body-file"}
	if len(calls) != 2 || calls[0].Name != "pr-post.sh" || len(calls[0].Args) != len(want)+1 || !slices.Equal(calls[0].Args[:len(want)], want) {
		t.Errorf("the post made the calls %+v", calls)
	}
}
