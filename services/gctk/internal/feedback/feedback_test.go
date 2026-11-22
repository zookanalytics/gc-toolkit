package feedback_test

import (
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/feedback"
)

// The adapter's tests run the pack's own definition, pr-post.sh's feedback-def
// from this checkout, through jq, so they pin that each question reaches the
// definition with the facts it weighs a post by. The definition's own cases are
// pr-post.test.sh's.

const (
	self    = "zook-bot"
	cutover = "2026-10-01T00:00:00Z"
	mark    = "<!-- gc:no-review -->"
)

// scripts is this checkout's assets/scripts.
func scripts(t *testing.T) string {
	t.Helper()
	dir, err := filepath.Abs("../../../../assets/scripts")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(dir, "pr-post.sh")); err != nil {
		t.Fatalf("pr-post.sh is not in %s: %v", dir, err)
	}
	return dir
}

// checkout is a rig's checkout whose default branch declares prefixes, or none
// when prefixes is empty.
func checkout(t *testing.T, declaration string) string {
	t.Helper()
	dir := t.TempDir()
	git := func(args ...string) {
		t.Helper()
		cmd := exec.Command("git", append([]string{"-C", dir, "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"}, args...)...)
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
	}
	git("init", "-q")
	if declaration != "" {
		if err := os.WriteFile(filepath.Join(dir, "not-for-review.toml"), []byte(declaration), 0o644); err != nil {
			t.Fatal(err)
		}
		git("add", "not-for-review.toml")
	}
	git("commit", "-q", "--allow-empty", "-m", "base")
	git("update-ref", "refs/remotes/origin/main", "HEAD")
	return dir
}

func load(t *testing.T, declaration string) *feedback.Rule {
	t.Helper()
	t.Setenv("GC_RIG_ROOT", "")
	r, err := feedback.Load(scripts(t), checkout(t, declaration))
	if err != nil {
		t.Fatal(err)
	}
	return r
}

func TestUntakenReviews(t *testing.T) {
	r := load(t, "")
	got, err := r.Untaken(self, cutover, []feedback.Review{
		{ID: 1, Author: "operator", Body: "rename this", State: "COMMENTED", SubmittedAt: "2026-11-12T01:00:00Z"},
		{ID: 2, Author: self, Body: "verdict\n\n<!-- gc:city -->", State: "COMMENTED", SubmittedAt: "2026-11-12T01:00:00Z"},
		{ID: 3, Author: self, Body: "an unmarked review", State: "COMMENTED", SubmittedAt: "2026-09-01T00:00:00Z"},
		{ID: 4, Author: self, Body: "an unmarked review after the cutover", State: "COMMENTED", SubmittedAt: "2026-11-12T01:00:00Z"},
		{ID: 5, Author: "preview", Body: mark + "\nSchema diff", State: "COMMENTED", SubmittedAt: "2026-11-12T01:00:00Z"},
		{ID: 6, Author: "operator", Body: "approved, but rename X", State: "APPROVED", SubmittedAt: "2026-11-12T01:00:00Z"},
	}, nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	if want := []int64{1, 4, 6}; !reflect.DeepEqual(got.Reviews, want) {
		t.Fatalf("untaken %v, want %v: the city's marked review, its review before the cutover and a review not for review are not feedback", got.Reviews, want)
	}
}

// A post the city has taken carries its EYES, and one it owes nothing more its
// THUMBS_UP. Either takes the post out of the untaken ones, whatever its kind,
// and any other reaction the city's account left takes nothing.
func TestAPostTheCityMarkedIsTaken(t *testing.T) {
	r := load(t, "")
	at := "2026-11-12T01:00:00Z"
	carrier := &feedback.Review{ID: 100, State: "COMMENTED", SubmittedAt: at}
	got, err := r.Untaken(self, cutover,
		[]feedback.Review{
			{ID: 1, Author: "operator", Body: "a", State: "COMMENTED", SubmittedAt: at, Reactions: []string{"EYES"}},
			{ID: 2, Author: "operator", Body: "b", State: "COMMENTED", SubmittedAt: at, Reactions: []string{"HEART"}},
		},
		[]feedback.Comment{
			{ID: 10, Author: "operator", Body: "c", CreatedAt: at, Review: carrier, Reactions: []string{"THUMBS_UP"}},
			{ID: 11, Author: "operator", Body: "d", CreatedAt: at, Review: carrier},
		},
		[]feedback.Comment{
			{ID: 20, Author: "operator", Body: "e", CreatedAt: at, Reactions: []string{"EYES", "THUMBS_UP"}},
			{ID: 21, Author: "operator", Body: "f", CreatedAt: at},
		})
	if err != nil {
		t.Fatal(err)
	}
	want := feedback.Untaken{Reviews: []int64{2}, Inline: []int64{11}, Conversation: []int64{21}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("untaken %+v, want %+v", got, want)
	}
}

func TestUntakenCommentsADismissalRetiredAreNotFeedback(t *testing.T) {
	r := load(t, "")
	got, err := r.Untaken(self, cutover, nil, []feedback.Comment{
		{ID: 10, Author: "operator", Body: "live", CreatedAt: "2026-11-12T01:00:00Z",
			Review: &feedback.Review{ID: 100, State: "COMMENTED", SubmittedAt: "2026-11-12T01:00:00Z"}},
		{ID: 11, Author: "operator", Body: "retired", CreatedAt: "2026-11-12T01:00:00Z",
			Review: &feedback.Review{ID: 101, State: "DISMISSED", SubmittedAt: "2026-11-12T01:00:00Z"}},
		{ID: 12, Author: self, Body: "drafted before the cutover, submitted after it", CreatedAt: "2026-09-01T00:00:00Z",
			Review: &feedback.Review{ID: 102, State: "COMMENTED", SubmittedAt: "2026-11-12T01:00:00Z"}},
	}, nil)
	if err != nil {
		t.Fatal(err)
	}
	if want := []int64{10, 12}; !reflect.DeepEqual(got.Inline, want) {
		t.Fatalf("untaken %v, want %v: a dismissal retires its comment, and a comment is dated by its review's submission", got.Inline, want)
	}
}

func TestUntakenConversationCommentsReadTheRigsDeclaration(t *testing.T) {
	comments := []feedback.Comment{
		{ID: 20, Author: "vercel", Body: "[vc]: #abc\nThe latest updates.", CreatedAt: "2026-11-12T01:00:00Z"},
		{ID: 21, Author: "operator", Body: "one more thing", CreatedAt: "2026-11-12T01:00:00Z"},
	}
	declared := load(t, "[[marker]]\nprefix = \"[vc]: #\"\n")
	got, err := declared.Untaken(self, cutover, nil, nil, comments)
	if err != nil {
		t.Fatal(err)
	}
	if want := []int64{21}; !reflect.DeepEqual(got.Conversation, want) {
		t.Fatalf("untaken %v, want %v on a rig that declares the prefix", got.Conversation, want)
	}
	got, err = load(t, "").Untaken(self, cutover, nil, nil, comments)
	if err != nil {
		t.Fatal(err)
	}
	if want := []int64{20, 21}; !reflect.DeepEqual(got.Conversation, want) {
		t.Fatalf("untaken %v, want %v on a rig that declares nothing", got.Conversation, want)
	}
}

func TestAwaiting(t *testing.T) {
	r := load(t, "")
	ask := feedback.Comment{Author: "operator", Body: "why?", CreatedAt: "2026-11-12T01:00:00Z",
		Review: &feedback.Review{State: "COMMENTED", SubmittedAt: "2026-11-12T01:00:00Z"}}
	answer := feedback.Comment{Author: self, Body: "because\n\n<!-- gc:city -->", CreatedAt: "2026-11-12T02:00:00Z",
		Review: &feedback.Review{State: "COMMENTED", SubmittedAt: "2026-11-12T02:00:00Z"}}
	handled := ask
	handled.Reactions = []string{"THUMBS_UP"}
	got, err := r.Awaiting(self, cutover, []feedback.Thread{
		{ID: "asked", Comments: []feedback.Comment{ask}},
		{ID: "answered", Comments: []feedback.Comment{ask, answer}},
		{ID: "asked-again", Comments: []feedback.Comment{ask, answer, ask}},
		{ID: "resolved", Resolved: true, Comments: []feedback.Comment{ask}},
		{ID: "handled", Comments: []feedback.Comment{answer, handled}},
	})
	if err != nil {
		t.Fatal(err)
	}
	if want := []string{"asked", "asked-again"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("awaiting %v, want %v", got, want)
	}
}

// A thread holds only the city's own posts when each of its posts is the
// city's: under its login and marked, or under its login from before the
// cutover. An unmarked post under the city's login after the cutover is a
// person's, as is a post under any other login, and a resolved thread is none
// that waits to be resolved.
func TestOwnThreads(t *testing.T) {
	r := load(t, "")
	finding := feedback.Comment{Author: self, Body: "a finding\n\n<!-- gc-writeback -->", CreatedAt: "2026-11-12T01:00:00Z",
		Review: &feedback.Review{State: "COMMENTED", SubmittedAt: "2026-11-12T01:00:00Z"}}
	early := feedback.Comment{Author: self, Body: "an unmarked finding", CreatedAt: "2026-09-01T00:00:00Z",
		Review: &feedback.Review{State: "COMMENTED", SubmittedAt: "2026-09-01T00:00:00Z"}}
	late := early
	late.CreatedAt = "2026-11-12T01:00:00Z"
	late.Review = &feedback.Review{State: "COMMENTED", SubmittedAt: "2026-11-12T01:00:00Z"}
	person := feedback.Comment{Author: "operator", Body: "why?", CreatedAt: "2026-11-12T02:00:00Z",
		Review: &feedback.Review{State: "COMMENTED", SubmittedAt: "2026-11-12T02:00:00Z"}}
	got, err := r.OwnThreads(self, cutover, []feedback.Thread{
		{ID: "marked", Comments: []feedback.Comment{finding}},
		{ID: "before-the-cutover", Comments: []feedback.Comment{early, finding}},
		{ID: "unmarked-after-the-cutover", Comments: []feedback.Comment{late}},
		{ID: "answered-by-a-person", Comments: []feedback.Comment{finding, person}},
		{ID: "resolved", Resolved: true, Comments: []feedback.Comment{finding}},
		{ID: "empty"},
	})
	if err != nil {
		t.Fatal(err)
	}
	if want := []string{"marked", "before-the-cutover"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("the city's own threads %v, want %v", got, want)
	}
}

func TestLoadFailsWithNoDefinition(t *testing.T) {
	if _, err := feedback.Load(t.TempDir(), t.TempDir()); err == nil {
		t.Fatal("loaded a definition from a directory with no pr-post.sh")
	}
}

func TestScriptsDirNamesGCTKScriptsDir(t *testing.T) {
	t.Setenv("GCTK_SCRIPTS_DIR", "/the/pack/scripts")
	if got, err := feedback.ScriptsDir(); err != nil || got != "/the/pack/scripts" {
		t.Fatalf("got %q, %v", got, err)
	}
}
