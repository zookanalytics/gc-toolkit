package review_test

import (
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/review"
)

// long is text long enough that a small edit leaves a moved file similar
// enough for git to call it moved.
var long = strings.Repeat("an image's bytes stand in here\n", 40)

// imageRepo is a scratch repository whose main holds images in shots/ and
// whose branch feature changes them every way a change can, after which main
// changes an image of its own. It returns the repository, the commit feature
// branches from, and feature's head.
func imageRepo(t *testing.T) (dir, base, head string) {
	t.Helper()
	dir = newRepo(t)
	base = commit(t, dir, map[string]string{
		"shots/home-dark-desktop.png":  "home dark desktop",
		"shots/home-light-desktop.png": "home light desktop",
		"shots/old-name.png":           "moved as it is",
		"shots/renamed.png":            long + "v1",
		"shots/gone.png":               "removed",
		"shots/exec.png":               "mode only",
		"docs/readme.md":               "text",
	})
	run(t, dir, "checkout", "-q", "-b", "feature")
	run(t, dir, "mv", "shots/old-name.png", "shots/new-name.png")
	run(t, dir, "mv", "shots/renamed.png", "shots/renamed-2.png")
	if err := os.Chmod(filepath.Join(dir, "shots/exec.png"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink("home-light-desktop.png", filepath.Join(dir, "shots/link.png")); err != nil {
		t.Fatal(err)
	}
	run(t, dir, "add", "shots/exec.png", "shots/link.png")
	head = commit(t, dir, map[string]string{
		"shots/home-dark-desktop.png":  "home dark desktop, restyled",
		"shots/about-dark-desktop.png": "about dark desktop",
		"shots/renamed-2.png":          long + "v2",
		"shots/gone.png":               "",
		"shots/a b#1.png":              "a name a URL escapes",
		"docs/readme.md":               "text, edited",
		"Logo.PNG":                     "a logo",
	})
	run(t, dir, "checkout", "-q", "main")
	commit(t, dir, map[string]string{"shots/home-light-desktop.png": "main's own change"})
	return dir, base, head
}

// The change is the three-dot diff a review reads: what feature does to the
// images, from the commit it branches from, and nothing main did since. A file
// is an image by its extension in any case, a symlink is none, and a change of
// mode alone changes no image.
func TestReadImagesReadsWhatTheChangeDoesToEachImage(t *testing.T) {
	dir, base, head := imageRepo(t)
	im, err := review.ReadImages(dir, "main", head)
	if err != nil {
		t.Fatal(err)
	}
	if im.Head != head || im.MergeBase != base {
		t.Fatalf("head %s and merge base %s, want %s and %s", im.Head, im.MergeBase, head, base)
	}
	want := []review.Image{
		{Kind: review.ImageAdded, Path: "Logo.PNG"},
		{Kind: review.ImageAdded, Path: "shots/a b#1.png"},
		{Kind: review.ImageAdded, Path: "shots/about-dark-desktop.png"},
		{Kind: review.ImageRemoved, Path: "shots/gone.png"},
		{Kind: review.ImageChanged, Path: "shots/home-dark-desktop.png"},
		{Kind: review.ImageMoved, Path: "shots/new-name.png", From: "shots/old-name.png"},
		{Kind: review.ImageChanged, Path: "shots/renamed-2.png", From: "shots/renamed.png"},
	}
	if !reflect.DeepEqual(im.Changes, want) {
		t.Fatalf("changes\n got %+v\nwant %+v", im.Changes, want)
	}
	if got := im.Counts(); got != "2 changed, 3 added, 1 removed and 1 moved" {
		t.Errorf("counts read %q", got)
	}
}

// A commit or a base that names no commit is refused by the flag that named it.
func TestReadImagesRefusesWhatNamesNoCommit(t *testing.T) {
	dir, _, head := imageRepo(t)
	if _, err := review.ReadImages(dir, "main", "nonesuch"); err == nil || !strings.Contains(err.Error(), `--oid "nonesuch" names no commit`) {
		t.Errorf("an --oid naming no commit answered %v", err)
	}
	if _, err := review.ReadImages(dir, "nonesuch", head); err == nil || !strings.Contains(err.Error(), `--base "nonesuch" names no commit`) {
		t.Errorf("a --base naming no commit answered %v", err)
	}
}

// A change that touches no image reads none, and shows nothing.
func TestAChangeWithNoImageShowsNothing(t *testing.T) {
	dir := newRepo(t)
	commit(t, dir, map[string]string{"a.png": "a", "b.md": "b"})
	head := commit(t, dir, map[string]string{"b.md": "b, edited"})
	im, err := review.ReadImages(dir, "HEAD~1", head)
	if err != nil {
		t.Fatal(err)
	}
	if len(im.Changes) != 0 || im.ImageComments("github.com", "acme/widgets") != nil {
		t.Fatalf("a change to no image read %+v", im.Changes)
	}
}

// Images in one directory group by the stem their names share once the parts
// that vary across the directory drop, such as a theme, a device, a browser
// and a platform, so each page's pictures sit together. A directory whose
// images share no stem is one group.
func TestImagesGroupByTheStemTheirNamesShare(t *testing.T) {
	dir := newRepo(t)
	files := map[string]string{"goldens/dark/library.png": "l", "goldens/dark/onboarding.png": "o"}
	for _, page := range []string{"account", "admin-users", "home"} {
		for _, theme := range []string{"dark", "light"} {
			for _, device := range []string{"desktop", "phone"} {
				for _, browser := range []string{"chromium", "webkit"} {
					files["e2e/screenshots/"+page+"-"+theme+"-"+device+"-"+browser+"-linux.png"] = page + theme + device + browser
				}
			}
		}
	}
	commit(t, dir, files)
	head := commit(t, dir, map[string]string{
		"e2e/screenshots/account-dark-desktop-chromium-linux.png":   "restyled",
		"e2e/screenshots/account-light-phone-webkit-linux.png":      "restyled",
		"e2e/screenshots/admin-users-dark-desktop-webkit-linux.png": "restyled",
		"goldens/dark/library.png":                                  "restyled",
		"goldens/dark/onboarding.png":                               "restyled",
	})
	im, err := review.ReadImages(dir, "HEAD~1", head)
	if err != nil {
		t.Fatal(err)
	}
	var got []string
	for _, g := range im.Groups() {
		var names []string
		for _, c := range g.Images {
			names = append(names, filepath.Base(c.Path))
		}
		got = append(got, g.Dir+" "+g.Stem+": "+strings.Join(names, ","))
	}
	want := []string{
		"e2e/screenshots account: account-dark-desktop-chromium-linux.png,account-light-phone-webkit-linux.png",
		"e2e/screenshots admin-users: admin-users-dark-desktop-webkit-linux.png",
		"goldens/dark : library.png,onboarding.png",
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("groups\n got %q\nwant %q", got, want)
	}
}

// Each comment shows a changed image before, at the merge base, and after, at
// the head, from the address GitHub serves each committed file from in the
// PR's repository; an added one after alone, a removed one before alone, and
// a moved one by name. A path is escaped for the address and for the page.
func TestImageCommentsShowEachImageBeforeAndAfter(t *testing.T) {
	dir, base, head := imageRepo(t)
	im, err := review.ReadImages(dir, "main", head)
	if err != nil {
		t.Fatal(err)
	}
	bodies := im.ImageComments("github.com", "acme/widgets")
	if len(bodies) != 1 {
		t.Fatalf("%d comments, want 1", len(bodies))
	}
	body := bodies[0]
	raw := func(commit, p string) string { return "https://github.com/acme/widgets/raw/" + commit + "/" + p }
	for _, want := range []string{
		"**Images in this change**, at " + head[:12] + ": 2 changed, 3 added, 1 removed and 1 moved, in 2 groups. " +
			"A before is the image at " + base[:12] + ", the commit the change branches from, and an after the image at " + head[:12] + ".",
		"| Before, at " + base[:12] + " | After, at " + head[:12] + " |\n|---|---|\n",
		"| <code>home-dark-desktop.png</code> | |\n" +
			`| <img src="` + raw(base, "shots/home-dark-desktop.png") + `" alt="before: shots/home-dark-desktop.png" width="350"> | ` +
			`<img src="` + raw(head, "shots/home-dark-desktop.png") + `" alt="after: shots/home-dark-desktop.png" width="350"> |`,
		"| <code>about-dark-desktop.png</code> | |\n| *not in the base* | " +
			`<img src="` + raw(head, "shots/about-dark-desktop.png") + `" alt="after: shots/about-dark-desktop.png" width="350"> |`,
		`| <img src="` + raw(base, "shots/gone.png") + `" alt="before: shots/gone.png" width="350"> | *removed* |`,
		"| <code>renamed-2.png</code>, moved from <code>shots/renamed.png</code> | |\n" +
			`| <img src="` + raw(base, "shots/renamed.png") + `" alt="before: shots/renamed.png" width="350"> | ` +
			`<img src="` + raw(head, "shots/renamed-2.png") + `" alt="after: shots/renamed-2.png" width="350"> |`,
		"Moved without a change: <code>new-name.png</code> from <code>shots/old-name.png</code>.",
		`<img src="` + raw(head, "shots/a%20b%231.png") + `" alt="after: shots/a b#1.png" width="350">`,
		"<summary>the repository's top directory · 1 added</summary>",
		"<summary><code>shots/</code> · 2 changed, 2 added, 1 removed and 1 moved</summary>",
	} {
		if !strings.Contains(body, want) {
			t.Errorf("the comment lacks %q:\n%s", want, body)
		}
	}
	// Six images to see, more than a page opens, so every group is closed.
	if strings.Contains(body, "<details open>") || strings.Count(body, "<details>") != 2 {
		t.Errorf("a change showing six images opened a group:\n%s", body)
	}
}

// A change that shows few images opens its groups, so a reader sees them
// without a click.
func TestAFewImagesShowOpen(t *testing.T) {
	dir := newRepo(t)
	commit(t, dir, map[string]string{"a.png": "a"})
	head := commit(t, dir, map[string]string{"a.png": "a, edited", "b.png": "b"})
	im, err := review.ReadImages(dir, "HEAD~1", head)
	if err != nil {
		t.Fatal(err)
	}
	body := im.ImageComments("github.com", "acme/widgets")[0]
	if !strings.Contains(body, "<details open>\n<summary>the repository's top directory · 1 changed and 1 added</summary>") {
		t.Errorf("two images did not show open:\n%s", body)
	}
}

// A PR shows a change's images only when it is a PR of the repository the
// clone's origin names, whose commits the images are drawn from, and a change
// that touches no image has nothing to show.
func TestShowImagesRefusesWhatItCannotShow(t *testing.T) {
	dir, base, head := imageRepo(t)
	run(t, dir, "remote", "add", "origin", "git@github.com:acme/widgets.git")
	_, err := review.ShowImages(dir, "https://github.com/acme/other/pull/7", "github.com", "acme/other", 7, base, head)
	if err == nil || !strings.Contains(err.Error(), "is a pull request of github.com/acme/other, not of the repository the clone's origin names") {
		t.Errorf("a PR of another repository answered %v", err)
	}
	_, err = review.ShowImages(dir, "https://github.com/acme/widgets/pull/7", "github.com", "acme/widgets", 7, base, base)
	if !errors.Is(err, review.ErrNoImages) {
		t.Errorf("a change to no image answered %v", err)
	}
	show, err := review.ShowImages(dir, "https://github.com/acme/widgets/pull/7", "github.com", "acme/widgets", 7, "main", head)
	if err != nil {
		t.Fatal(err)
	}
	if len(show.Comments) != 1 || !strings.HasPrefix(show.Summary(), "1 comment on https://github.com/acme/widgets/pull/7: ") ||
		!strings.HasSuffix(show.Summary(), " at "+head) {
		t.Errorf("a PR of the origin's repository shows %d comments: %s", len(show.Comments), show.Summary())
	}
}
