package pr

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

// The scratch repositories stand in for a PR's branch and its target: a bare
// origin, up, the clone that pushes the target's history, and work, the
// checkout the branch is brought current in. work fetches each push of the
// target's history, as a rig's clone does, since a clone records no reflog
// of what it cloned. Git reads no config of the host's.

type scratch struct {
	t                *testing.T
	origin, up, work string
}

func newScratch(t *testing.T) *scratch {
	t.Helper()
	cfg := filepath.Join(t.TempDir(), "gitconfig")
	if err := os.WriteFile(cfg, nil, 0o644); err != nil {
		t.Fatal(err)
	}
	for k, v := range map[string]string{
		"GIT_CONFIG_GLOBAL": cfg, "GIT_CONFIG_NOSYSTEM": "1",
		"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.com",
		"GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.com",
	} {
		t.Setenv(k, v)
	}
	root := t.TempDir()
	s := &scratch{t: t, origin: filepath.Join(root, "origin.git"), up: filepath.Join(root, "up"), work: filepath.Join(root, "work")}
	s.git(root, "init", "-q", "--bare", s.origin)
	s.git(root, "clone", "-q", s.origin, s.up)
	s.git(s.up, "symbolic-ref", "HEAD", "refs/heads/main")
	s.git(root, "clone", "-q", s.origin, s.work)
	return s
}

// git runs git in dir and returns its output, trimmed.
func (s *scratch) git(dir string, args ...string) string {
	s.t.Helper()
	out, err := exec.Command("git", append([]string{"-C", dir}, args...)...).CombinedOutput()
	if err != nil {
		s.t.Fatalf("git %v: %v\n%s", args, err, out)
	}
	return strings.TrimSpace(string(out))
}

// commit writes files into dir and commits them, and returns the commit.
func (s *scratch) commit(dir, msg string, files map[string]string) string {
	s.t.Helper()
	for name, text := range files {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(text), 0o644); err != nil {
			s.t.Fatal(err)
		}
	}
	s.git(dir, "add", "-A")
	s.git(dir, "commit", "-q", "-m", msg)
	return s.git(dir, "rev-parse", "HEAD")
}

// push puts up's HEAD on origin's main, forced, as a sync that rewrites it
// pushes, and work fetches it.
func (s *scratch) push() string {
	s.t.Helper()
	s.git(s.up, "push", "-q", "--force", "origin", "HEAD:main")
	s.git(s.work, "fetch", "-q", "origin")
	return s.git(s.up, "rev-parse", "HEAD")
}

// branch cuts the branch pr in work from main.
func (s *scratch) branch() {
	s.t.Helper()
	s.git(s.work, "checkout", "-q", "-b", "pr", "origin/main")
}

// at is the text of path at rev in work, and false when rev holds no path.
func (s *scratch) at(rev, path string) (string, bool) {
	out, err := exec.Command("git", "-C", s.work, "show", rev+":"+path).Output()
	return string(out), err == nil
}

// shared is a file whose lines lie far enough apart that edits to two of them
// merge cleanly.
const shared = "a\nb\nc\nd\ne\nf\ng\nh\ni\n"

func edit(line, to string) string { return strings.Replace(shared, line+"\n", to+"\n", 1) }

// lineage is the target's history before a sync rewrites it: c0, the
// upstream commit both lineages hold, then the fork's own commits, f1, which
// the rewrite carries with a new resolution of fork.txt, and x1, which it
// drops.
type lineage struct{ c0, f1, x1 string }

func (s *scratch) oldLineage() lineage {
	s.t.Helper()
	var l lineage
	l.c0 = s.commit(s.up, "c0", map[string]string{"shared.txt": shared})
	l.f1 = s.commit(s.up, "f1", map[string]string{"fork.txt": "fork v1\n", "shared.txt": edit("a", "a-fork")})
	l.x1 = s.commit(s.up, "x1", map[string]string{"dropped.txt": "dropped\n"})
	s.push()
	return l
}

// rewrite moves main to c0 with an upstream commit on it, u1, and f1 carried
// again with fork.txt at version, and pushes it over the old history.
func (s *scratch) rewrite(c0, version string) string {
	s.t.Helper()
	s.git(s.up, "reset", "-q", "--hard", c0)
	s.commit(s.up, "u1", map[string]string{"shared.txt": edit("i", "i-up")})
	s.commit(s.up, "f1 again", map[string]string{"fork.txt": "fork " + version + "\n", "shared.txt": strings.Replace(edit("i", "i-up"), "a\n", "a-fork\n", 1)})
	return s.push()
}

// The PR's own change: pr.txt and line e of shared.txt.
func (s *scratch) ownChange() string {
	s.t.Helper()
	text, _ := s.at("HEAD", "shared.txt")
	return s.commit(s.work, "the PR", map[string]string{"pr.txt": "pr\n", "shared.txt": strings.Replace(text, "e\n", "e-pr\n", 1)})
}

func bring(t *testing.T, dir string) *BroughtCurrent {
	t.Helper()
	cur, err := BringCurrent(dir, "main")
	if err != nil {
		t.Fatalf("BringCurrent: %v", err)
	}
	return cur
}

// changed lists the paths whose content differs between a and b in work.
func (s *scratch) changed(a, b string) []string {
	s.t.Helper()
	out := s.git(s.work, "diff", "--name-only", a, b)
	if out == "" {
		return nil
	}
	return strings.Split(out, "\n")
}

func TestBringCurrentOverARewriteMergesFromTheTargetTheBranchTookLast(t *testing.T) {
	s := newScratch(t)
	old := s.oldLineage()
	s.branch()
	head := s.ownChange()
	tip := s.rewrite(old.c0, "v2")

	// The control: from git's own base, c0, the branch's copy of the old
	// history counts as its own change. fork.txt, which the PR never touched,
	// conflicts, and dropped.txt, which the rewrite dropped, comes back.
	plain := exec.Command("git", "-C", s.work, "merge-tree", "--write-tree", "--name-only", "--no-messages", head, tip)
	out, err := plain.Output()
	var ee *exec.ExitError
	if !errors.As(err, &ee) || ee.ExitCode() != 1 {
		t.Fatalf("plain merge-tree: %v, want the conflict exit 1\n%s", err, out)
	}
	lines := strings.Split(strings.TrimSpace(string(out)), "\n")
	if !slices.Contains(lines[1:], "fork.txt") {
		t.Fatalf("the plain merge conflicts in %v, want fork.txt among them", lines[1:])
	}
	if _, held := s.at(lines[0], "dropped.txt"); !held {
		t.Fatal("the plain merge does not bring dropped.txt back, so the scratch does not reproduce the rewrite")
	}

	cur := bring(t, s.work)
	if cur.Held || cur.Tip != tip || cur.Default != old.c0 || cur.Base != old.x1 || cur.Supersede == "" {
		t.Fatalf("BringCurrent = %+v, want tip %s from %s, the commit the branch took last, over git's base %s", cur, tip, old.x1, old.c0)
	}
	if len(cur.Conflicts) != 0 {
		t.Fatalf("conflicts %v, want none: only the PR's own change meets the target's", cur.Conflicts)
	}
	if got := s.git(s.work, "rev-parse", cur.Supersede+"^@"); got != tip+"\n"+old.x1 {
		t.Errorf("the superseding commit's parents are %q, want the tip then the base", got)
	}
	if s.git(s.work, "rev-parse", cur.Supersede+"^{tree}") != s.git(s.work, "rev-parse", tip+"^{tree}") {
		t.Error("the superseding commit's tree is not the tip's")
	}
	if got := s.git(s.work, "rev-parse", "HEAD^@"); got != head+"\n"+cur.Supersede || cur.Head != s.git(s.work, "rev-parse", "HEAD") {
		t.Errorf("HEAD's parents are %q and Head is %s, want the merge of %s and the superseding commit", got, cur.Head, head)
	}
	if got := s.changed(tip, "HEAD"); !slices.Equal(got, []string{"pr.txt", "shared.txt"}) {
		t.Errorf("the merge differs from the tip in %v, want only the PR's own files", got)
	}
	if text, _ := s.at("HEAD", "shared.txt"); text != strings.Replace(strings.Replace(edit("i", "i-up"), "a\n", "a-fork\n", 1), "e\n", "e-pr\n", 1) {
		t.Errorf("shared.txt is %q, want the tip's with the PR's line", text)
	}
	if _, held := s.at("HEAD", "dropped.txt"); held {
		t.Error("dropped.txt, which the rewrite dropped, came back")
	}
	if got := s.git(s.work, "show", "--remerge-diff", "--format=", "HEAD"); got != "" {
		t.Errorf("git show --remerge-diff shows %q, want nothing, since nothing was resolved by hand", got)
	}
	msg := s.git(s.work, "log", "-1", "--format=%B", "HEAD")
	if !strings.HasPrefix(msg, "Merge origin/main at "+tip[:12]+" from "+old.x1[:12]) ||
		!strings.Contains(msg, cur.Supersede[:12]) || !strings.Contains(msg, old.c0[:12]) {
		t.Errorf("the merge's message names neither its base nor the superseding commit:\n%s", msg)
	}
	if got := s.git(s.work, "log", "-1", "--format=%s", cur.Supersede); got != "Supersede "+old.x1[:12]+" with origin/main at "+tip[:12] {
		t.Errorf("the superseding commit's subject is %q", got)
	}

	// The next bring-current, with no rewrite since, is a plain merge.
	merged := cur.Head
	s.commit(s.up, "u2", map[string]string{"up2.txt": "u2\n"})
	tip2 := s.push()
	next := bring(t, s.work)
	if next.Supersede != "" || next.Base != tip {
		t.Fatalf("BringCurrent after the rewrite was taken = %+v, want a plain merge from %s", next, tip)
	}
	if got := s.git(s.work, "rev-parse", "HEAD^@"); got != merged+"\n"+tip2 {
		t.Errorf("HEAD's parents are %q, want %s then the tip", got, merged)
	}
	if got := s.changed(tip2, "HEAD"); !slices.Equal(got, []string{"pr.txt", "shared.txt"}) {
		t.Errorf("the second merge differs from the tip in %v, want only the PR's own files", got)
	}
	if got := s.git(s.work, "log", "-1", "--format=%B", "HEAD"); got != "Merge origin/main at "+tip2[:12] {
		t.Errorf("the plain merge's message is %q", got)
	}
}

func TestBringCurrentWithNoRewriteMergesTheTargetItself(t *testing.T) {
	s := newScratch(t)
	old := s.oldLineage()
	s.branch()
	head := s.ownChange()
	s.commit(s.up, "u1", map[string]string{"shared.txt": strings.Replace(edit("i", "i-up"), "a\n", "a-fork\n", 1)})
	tip := s.push()

	cur := bring(t, s.work)
	if cur.Supersede != "" || cur.Base != old.x1 || cur.Default != old.x1 || len(cur.Conflicts) != 0 {
		t.Fatalf("BringCurrent = %+v, want a plain merge from git's base %s", cur, old.x1)
	}
	if got := s.git(s.work, "rev-parse", "HEAD^@"); got != head+"\n"+tip {
		t.Errorf("HEAD's parents are %q, want the branch then the tip", got)
	}

	held := bring(t, s.work)
	if !held.Held || held.Head != "" || s.git(s.work, "rev-parse", "HEAD") != cur.Head {
		t.Errorf("BringCurrent on a HEAD that holds the tip = %+v, want it held and nothing merged", held)
	}
}

func TestBringCurrentOverTwoRewritesGoesFromTheFirstLineage(t *testing.T) {
	s := newScratch(t)
	old := s.oldLineage()
	s.branch()
	s.ownChange()
	// The clone fetches the second lineage, and the branch never takes it.
	s.rewrite(old.c0, "v2")
	u1 := s.git(s.up, "rev-parse", "HEAD~1")
	s.git(s.up, "reset", "-q", "--hard", u1)
	s.commit(s.up, "f1 a third time", map[string]string{"fork.txt": "fork v3\n", "shared.txt": strings.Replace(edit("i", "i-up"), "a\n", "a-fork\n", 1)})
	tip := s.push()

	cur := bring(t, s.work)
	if cur.Base != old.x1 || cur.Supersede == "" || len(cur.Conflicts) != 0 {
		t.Fatalf("BringCurrent = %+v, want a clean merge from %s, the first lineage's commit the branch took", cur, old.x1)
	}
	if got := s.changed(tip, "HEAD"); !slices.Equal(got, []string{"pr.txt", "shared.txt"}) {
		t.Errorf("the merge differs from the tip in %v, want only the PR's own files", got)
	}
}

func TestBringCurrentLeavesAConflictInGitsMergeState(t *testing.T) {
	s := newScratch(t)
	old := s.oldLineage()
	s.branch()
	head := s.commit(s.work, "the PR", map[string]string{"shared.txt": strings.Replace(edit("i", "i-pr"), "a\n", "a-fork\n", 1)})
	s.rewrite(old.c0, "v2")

	cur := bring(t, s.work)
	if !slices.Equal(cur.Conflicts, []string{"shared.txt"}) || cur.Supersede == "" || cur.Head != "" {
		t.Fatalf("BringCurrent = %+v, want it stopped on shared.txt alone, where the PR and the target meet", cur)
	}
	if got := s.git(s.work, "rev-parse", "MERGE_HEAD"); got != cur.Supersede {
		t.Errorf("MERGE_HEAD is %s, want the superseding commit %s", got, cur.Supersede)
	}
	if got := s.git(s.work, "rev-parse", "HEAD"); got != head {
		t.Errorf("HEAD moved to %s", got)
	}

	// A second call refuses the unfinished merge and changes nothing.
	_, err := BringCurrent(s.work, "main")
	var refused *CurrentRefusal
	if !errors.As(err, &refused) || !strings.Contains(err.Error(), "middle of a merge") {
		t.Fatalf("BringCurrent mid-merge: %v, want a refusal naming the unfinished merge", err)
	}

	resolved := strings.Replace(edit("i", "i-pr-up"), "a\n", "a-fork\n", 1)
	if err := os.WriteFile(filepath.Join(s.work, "shared.txt"), []byte(resolved), 0o644); err != nil {
		t.Fatal(err)
	}
	s.git(s.work, "add", "shared.txt")
	file := filepath.Join(t.TempDir(), "msg")
	if err := os.WriteFile(file, []byte(cur.Message+"\nshared.txt: kept both lines.\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	s.git(s.work, "commit", "-q", "-F", file)
	if got := s.git(s.work, "show", "--remerge-diff", "--format=", "--name-only", "HEAD"); got != "shared.txt" {
		t.Errorf("git show --remerge-diff names %q, want the file resolved by hand alone", got)
	}
}

func TestBringCurrentSignsTheSupersedingCommitWhenTheCloneSigns(t *testing.T) {
	keygen, err := exec.LookPath("ssh-keygen")
	if err != nil {
		t.Skip("no ssh-keygen to make a signing key")
	}
	s := newScratch(t)
	old := s.oldLineage()
	s.branch()
	s.ownChange()
	key := filepath.Join(t.TempDir(), "key")
	if out, err := exec.Command(keygen, "-q", "-t", "ed25519", "-N", "", "-f", key).CombinedOutput(); err != nil {
		t.Fatalf("ssh-keygen: %v\n%s", err, out)
	}
	s.git(s.work, "config", "gpg.format", "ssh")
	s.git(s.work, "config", "user.signingkey", key)
	s.git(s.work, "config", "commit.gpgSign", "true")
	s.rewrite(old.c0, "v2")

	cur := bring(t, s.work)
	for name, c := range map[string]string{"superseding commit": cur.Supersede, "merge": cur.Head} {
		if c == "" || !strings.Contains(s.git(s.work, "cat-file", "-p", c), "\ngpgsig ") {
			t.Errorf("the %s %q is not signed", name, c)
		}
	}
}

func TestBringCurrentRefusesWhatItCouldNotMergeSafely(t *testing.T) {
	s := newScratch(t)
	old := s.oldLineage()
	s.branch()
	s.ownChange()
	s.rewrite(old.c0, "v2")
	before := s.git(s.work, "rev-parse", "refs/remotes/origin/main")
	// origin moves on, and only a fetch would show work.
	s.commit(s.up, "u2", map[string]string{"up2.txt": "u2\n"})
	s.git(s.up, "push", "-q", "origin", "HEAD:main")

	if err := os.WriteFile(filepath.Join(s.work, "pr.txt"), []byte("edited\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	_, err := BringCurrent(s.work, "main")
	var refused *CurrentRefusal
	if !errors.As(err, &refused) || !strings.Contains(err.Error(), "pr.txt") {
		t.Fatalf("BringCurrent on uncommitted work: %v, want a refusal that lists it", err)
	}
	if got := s.git(s.work, "rev-parse", "refs/remotes/origin/main"); got != before {
		t.Errorf("the refusal fetched origin/main to %s", got)
	}
	s.git(s.work, "checkout", "-q", "--", "pr.txt")

	s.git(s.work, "checkout", "-q", "--orphan", "lone")
	s.commit(s.work, "lone", map[string]string{"lone.txt": "lone\n"})
	if _, err := BringCurrent(s.work, "main"); !errors.As(err, &refused) || !strings.Contains(err.Error(), "no history") {
		t.Fatalf("BringCurrent on a HEAD with no history in common: %v, want a refusal", err)
	}
}
