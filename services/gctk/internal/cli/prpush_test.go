package cli

import (
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
)

// The sitting's push reads the store through the stub the bead holds tests use,
// and pushes through the pack's own branch-push.sh against a real origin. The
// proof's rules and the order of the draft and the push are pr's own tests, on
// the fakes.

// pushStore is a bead on the pending record that waits on a conversation in
// progress under the sitting rig/gc-toolkit.st-conv.
const pushStore = `[
 {"id":"st-1","status":"blocked","assignee":"rig/refinery","issue_type":"task",
  "metadata":{"merge_result":"pull_request_pending","branch":"polecat/st-1","pr_url":"https://github.com/acme/widgets/pull/7"},
  "dependencies":[{"id":"st-conv","dependency_type":"blocks","status":"in_progress"}]},
 {"id":"st-conv","status":"in_progress","issue_type":"task","assignee":"rig/gc-toolkit.st-conv"}
]`

// asSession makes this session the one whose alias is alias.
func asSession(t *testing.T, alias string) {
	t.Helper()
	for _, k := range []string{"GC_SESSION_NAME", "GC_SESSION_ID", "GC_AGENT"} {
		t.Setenv(k, "")
	}
	t.Setenv("GC_ALIAS", alias)
}

func TestPRPushUsage(t *testing.T) {
	for name, args := range map[string][]string{
		"no bead":        {"pr", "push"},
		"no holder":      {"pr", "push", "st-1"},
		"a blank holder": {"pr", "push", "st-1", "--held-by", " "},
	} {
		t.Run(name, func(t *testing.T) {
			if code := Run(args, "", io.Discard, io.Discard); code != 1 {
				t.Fatalf("exit %d, want the usage exit 1", code)
			}
		})
	}
}

// A push needs the pack's pusher, so a caller that names no scripts directory
// stops before anything is read or changed.
func TestPRPushNeedsThePacksPusherBeforeItReadsTheStore(t *testing.T) {
	asSession(t, "rig/gc-toolkit.st-conv")
	t.Setenv("GCTK_SCRIPTS_DIR", "")
	log := filepath.Join(t.TempDir(), "calls")
	t.Setenv("STUB_DB_LOG", log)
	_, errs, code := landingCmd(t, pushStore, "https://github.com/acme/widgets.git",
		"pr", "push", "st-1", "--held-by", "st-conv", "--db", t.TempDir())
	if code != 1 || !strings.Contains(errs, "GCTK_SCRIPTS_DIR names no pack scripts directory") {
		t.Fatalf("exit %d, stderr %q, want exit 1 naming GCTK_SCRIPTS_DIR", code, errs)
	}
	if _, err := os.Stat(log); err == nil {
		t.Fatal("the store was read before the pusher was found")
	}
}

// --check proves the holding from the store and changes nothing, and names
// the session that does not hold the conversation.
func TestPRPushCheckProvesTheHoldingFromTheStore(t *testing.T) {
	asSession(t, "rig/gc-toolkit.st-conv")
	out, errs, code := landingCmd(t, pushStore, "https://github.com/acme/widgets.git",
		"pr", "push", "st-1", "--held-by", "st-conv", "--check", "--db", t.TempDir())
	if code != 0 || !strings.Contains(out, "conversation st-conv holds its branch polecat/st-1, and nothing else writes it") {
		t.Fatalf("exit %d, stdout %q, stderr %q, want the holding", code, out, errs)
	}
	asSession(t, "rig/gc-toolkit.st-other")
	_, errs, code = landingCmd(t, pushStore, "https://github.com/acme/widgets.git",
		"pr", "push", "st-1", "--held-by", "st-conv", "--check", "--db", t.TempDir())
	if code != 3 || !strings.Contains(errs, "so this session does not hold it") {
		t.Fatalf("exit %d, stderr %q, want the refusal exit 3", code, errs)
	}
}

// Each stop the push or its proof makes has its own exit.
func TestPRPushExitsByWhatStoppedIt(t *testing.T) {
	for want, err := range map[int]error{
		3: &pr.PushRefusal{Bead: "st-1", Why: "it has no blocks edge onto conversation st-conv"},
		4: &pr.Moved{Branch: "polecat/st-1", Why: "it moved"},
		2: errors.New("gh: error connecting to api.github.com"),
	} {
		if got := pushFailed("st-1", err, io.Discard); got != want {
			t.Errorf("%v exits %d, want %d", err, got, want)
		}
	}
	if got := pushFailed("st-1", &pr.DraftRefusal{Bead: "st-1", Why: "the PR is not open"}, io.Discard); got != 3 {
		t.Errorf("a PR that is not open exits %d, want 3", got)
	}
}

// treeGit runs git in dir with no global or system config and a fixed identity,
// and returns its trimmed output.
func treeGit(t *testing.T, dir string, args ...string) string {
	t.Helper()
	c := exec.Command("git", append([]string{"-C", dir}, args...)...)
	c.Env = append(os.Environ(), "GIT_AUTHOR_NAME=t", "GIT_AUTHOR_EMAIL=t@example.com",
		"GIT_COMMITTER_NAME=t", "GIT_COMMITTER_EMAIL=t@example.com")
	out, err := c.CombinedOutput()
	if err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
	return strings.TrimSpace(string(out))
}

// treeCommit commits a change to file in dir and returns the commit.
func treeCommit(t *testing.T, dir, file, text string) string {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, file), []byte(text), 0o644); err != nil {
		t.Fatal(err)
	}
	treeGit(t, dir, "add", file)
	treeGit(t, dir, "commit", "-q", "-m", "change "+file)
	return treeGit(t, dir, "rev-parse", "HEAD")
}

// The checkout pushes its HEAD through the pack's branch-push.sh, reads work no
// commit holds, and takes nothing onto a branch that holds a commit it does
// not, until it holds that commit too.
func TestTheSittingsCheckoutPushesThroughThePacksPusher(t *testing.T) {
	cfg := filepath.Join(t.TempDir(), "gitconfig")
	if err := os.WriteFile(cfg, nil, 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("GIT_CONFIG_GLOBAL", cfg)
	t.Setenv("GIT_CONFIG_NOSYSTEM", "1")
	scripts, err := filepath.Abs("../../../../assets/scripts")
	if err != nil {
		t.Fatal(err)
	}
	t.Setenv("GCTK_SCRIPTS_DIR", scripts)
	const b = "polecat/st-1"
	root := t.TempDir()
	origin := filepath.Join(root, "origin.git")
	treeGit(t, root, "init", "-q", "--bare", origin)
	other := filepath.Join(root, "other")
	treeGit(t, root, "clone", "-q", origin, other)
	treeGit(t, other, "checkout", "-q", "-b", b)
	treeCommit(t, other, "a.txt", "one\n")
	treeGit(t, other, "push", "-q", "origin", b)
	tr := filepath.Join(root, "tree")
	treeGit(t, root, "clone", "-q", origin, tr)
	treeGit(t, tr, "checkout", "-q", "--detach", "origin/"+b)

	s, err := newSittingTree(tr)
	if err != nil {
		t.Fatal(err)
	}
	if left, err := s.Uncommitted(); err != nil || left != "" {
		t.Fatalf("a clean checkout lists %q, %v", left, err)
	}
	mine := treeCommit(t, tr, "a.txt", "two\n")
	if err := os.WriteFile(filepath.Join(tr, "loose.txt"), []byte("x\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if left, err := s.Uncommitted(); err != nil || !strings.Contains(left, "loose.txt") {
		t.Fatalf("work no commit holds lists %q, %v", left, err)
	}
	if err := os.Remove(filepath.Join(tr, "loose.txt")); err != nil {
		t.Fatal(err)
	}
	if err := s.Push(b); err != nil {
		t.Fatalf("the push read %v", err)
	}
	if got := treeGit(t, origin, "rev-parse", b); got != mine {
		t.Fatalf("origin's %s is %s, want the checkout's %s", b, got, mine)
	}

	treeGit(t, other, "pull", "-q", "origin", b)
	theirs := treeCommit(t, other, "b.txt", "theirs\n")
	treeGit(t, other, "push", "-q", "origin", b)
	treeCommit(t, tr, "c.txt", "mine\n")
	var moved *pr.Moved
	if err := s.Push(b); !errors.As(err, &moved) {
		t.Fatalf("a push onto a branch that moved read %v", err)
	}
	if got := treeGit(t, origin, "rev-parse", b); got != theirs {
		t.Fatalf("origin's %s is %s, want the other writer's %s kept", b, got, theirs)
	}
	treeGit(t, tr, "merge", "-q", "--no-edit", "origin/"+b)
	if err := s.Push(b); err != nil {
		t.Fatalf("the push after the merge read %v", err)
	}
	if got, head := treeGit(t, origin, "rev-parse", b), treeGit(t, tr, "rev-parse", "HEAD"); got != head {
		t.Fatalf("origin's %s is %s, want the checkout's %s", b, got, head)
	}
}
