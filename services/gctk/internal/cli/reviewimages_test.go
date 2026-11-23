package cli

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// imagesClone is a scratch clone whose origin is acme/widgets on GitHub, with
// a change on feature that edits one image and adds another, on a base that
// holds the first. It returns the clone, the base's commit and feature's head.
func imagesClone(t *testing.T) (dir, base, head string) {
	t.Helper()
	hermeticGit(t)
	dir = t.TempDir()
	treeGit(t, dir, "init", "-q", "-b", "main")
	treeGit(t, dir, "remote", "add", "origin", "git@github.com:acme/widgets.git")
	if err := os.MkdirAll(filepath.Join(dir, "shots"), 0o755); err != nil {
		t.Fatal(err)
	}
	base = treeCommit(t, dir, "shots/home.png", "home")
	treeGit(t, dir, "checkout", "-q", "-b", "feature")
	treeCommit(t, dir, "shots/home.png", "home, restyled")
	head = treeCommit(t, dir, "shots/about.png", "about")
	return dir, base, head
}

// fakeGH puts a gh on PATH that logs each call's arguments, one a line after a
// line naming the call, and answers as GitHub does for a comment, or fails.
func fakeGH(t *testing.T, fail bool) string {
	t.Helper()
	bin := t.TempDir()
	log := filepath.Join(bin, "gh.log")
	answer := "printf 'https://github.com/acme/widgets/pull/7#issuecomment-%s\\n' \"$$\"\n"
	if fail {
		answer = "echo 'HTTP 502: Bad Gateway' >&2\nexit 1\n"
	}
	stub := "#!/bin/sh\necho '== call' >> '" + log + "'\nprintf '%s\\n' \"$@\" >> '" + log + "'\n" + answer
	if err := os.WriteFile(filepath.Join(bin, "gh"), []byte(stub), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	return log
}

func runImages(t *testing.T, args ...string) (stdout, stderr string, code int) {
	t.Helper()
	var out, errb bytes.Buffer
	code = Run(append([]string{"review", "images"}, args...), "test", &out, &errb)
	return out.String(), errb.String(), code
}

// The command posts the change's images in one comment through the pack's
// writer of the city's posts, which pins the PR's repository and adds the
// city's mark, and names what it posted.
func TestReviewImagesPostsThroughTheWriterOfTheCitysPosts(t *testing.T) {
	dir, base, head := imagesClone(t)
	log := fakeGH(t, false)
	out, errs, code := runImages(t, "--pr", "https://github.com/acme/widgets/pull/7", "--base", "main", "--oid", head, "--repo", dir)
	if code != 0 {
		t.Fatalf("exit %d, stderr %s", code, errs)
	}
	raw, err := os.ReadFile(log)
	if err != nil {
		t.Fatal(err)
	}
	calls := string(raw)
	if strings.Count(calls, "== call") != 1 {
		t.Fatalf("gh was called %d times, want once:\n%s", strings.Count(calls, "== call"), calls)
	}
	for _, want := range []string{
		"pr\ncomment\n7\n--repo\ngithub.com/acme/widgets\n--body\n**Images in this change**, at " + head[:12] + ": 1 changed and 1 added.",
		`<img src="https://github.com/acme/widgets/raw/` + base + `/shots/home.png" alt="before: shots/home.png" width="350">`,
		`<img src="https://github.com/acme/widgets/raw/` + head + `/shots/about.png" alt="after: shots/about.png" width="350">`,
		"<!-- gc:city -->",
	} {
		if !strings.Contains(calls, want) {
			t.Errorf("the post lacks %q:\n%s", want, calls)
		}
	}
	if !strings.Contains(out, "https://github.com/acme/widgets/pull/7#issuecomment-") ||
		!strings.HasSuffix(out, "gctk review images: posted 1 comment on https://github.com/acme/widgets/pull/7: 1 changed and 1 added, in 1 group, at "+head+"\n") {
		t.Errorf("stdout does not name the comment and what posted:\n%s", out)
	}
}

// --dry-run prints each comment and posts nothing.
func TestReviewImagesDryRunPostsNothing(t *testing.T) {
	dir, _, head := imagesClone(t)
	log := fakeGH(t, false)
	out, errs, code := runImages(t, "--pr", "https://github.com/acme/widgets/pull/7", "--base", "main", "--oid", head, "--repo", dir, "--dry-run")
	if code != 0 {
		t.Fatalf("exit %d, stderr %s", code, errs)
	}
	if _, err := os.Stat(log); err == nil {
		t.Fatal("a dry run called gh")
	}
	if !strings.HasPrefix(out, "== comment 1 of 1\n**Images in this change**") ||
		!strings.Contains(out, "gctk review images: would post 1 comment on https://github.com/acme/widgets/pull/7: 1 changed and 1 added, in 1 group, at "+head) {
		t.Errorf("the dry run printed:\n%s", out)
	}
}

// A pull request of another repository than the clone's origin, and a change
// that touches no image, post nothing, and say why.
func TestReviewImagesPostsNothingItShouldNot(t *testing.T) {
	dir, base, head := imagesClone(t)
	log := fakeGH(t, false)
	_, errs, code := runImages(t, "--pr", "https://github.com/acme/other/pull/7", "--base", "main", "--oid", head, "--repo", dir)
	if code != 1 || !strings.Contains(errs, "is a pull request of github.com/acme/other, not of the repository the clone's origin names") {
		t.Errorf("a PR of another repository exited %d: %s", code, errs)
	}
	_, errs, code = runImages(t, "--pr", "https://github.com/acme/widgets/pull/7", "--base", base, "--oid", base, "--repo", dir)
	if code != 3 || !strings.Contains(errs, "adds, changes, moves or removes no image; nothing posted") {
		t.Errorf("a change to no image exited %d: %s", code, errs)
	}
	if _, err := os.Stat(log); err == nil {
		t.Fatal("gh was called")
	}
	_, errs, code = runImages(t, "--pr", "https://github.com/acme/widgets/issues/7", "--base", "main", "--oid", head, "--repo", dir)
	if code != 2 || !strings.Contains(errs, "is not a pull request's address") {
		t.Errorf("an address that is no pull request's exited %d: %s", code, errs)
	}
}

// A comment that does not post fails the command, naming it and the writer's
// last line.
func TestReviewImagesNamesACommentThatDidNotPost(t *testing.T) {
	dir, _, head := imagesClone(t)
	fakeGH(t, true)
	_, errs, code := runImages(t, "--pr", "https://github.com/acme/widgets/pull/7", "--base", "main", "--oid", head, "--repo", dir)
	if code != 1 || !strings.Contains(errs, "gctk review images: comment 1 of 1 did not post on https://github.com/acme/widgets/pull/7: exit 1: ") ||
		!strings.Contains(errs, "none posted") {
		t.Errorf("a failed post exited %d: %s", code, errs)
	}
}
