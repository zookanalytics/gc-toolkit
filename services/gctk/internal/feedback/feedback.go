// Package feedback is gctk's seam to the pack's one definition of feedback,
// the shell rule `pr-post.sh feedback-def` prints (docs/gctk-architecture.md,
// "The adapters"). Every reader of feedback applies that definition, the
// intake among them, so no reader carries the rule of its own: this adapter
// runs it through jq, as each shell reader does, and holds none of it. It
// answers which posts are feedback (gc_feedback), which inline comments a
// dismissal has not retired (live_comments) and which review threads wait on
// the city's answer (gc_thread_awaits_answer).
//
// The definition is loaded once, from the pack's scripts directory, in the
// rig's checkout, whose default branch declares the posts that are not for
// review. A read that does not run returns an error, never an answer, because
// a post wrongly read as no feedback lets a PR merge over it.
package feedback

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

// Rule is the definition, loaded. ctx ends every application of it, and can
// never end for a rule [Load] returned.
type Rule struct {
	def string
	ctx context.Context
}

// Review is a review, in the facts the definition weighs one by.
type Review struct {
	ID          int64
	Author      string
	Body        string
	State       string
	SubmittedAt string
}

// Comment is an inline comment or a conversation comment. Review is the review
// that carried an inline comment, nil for a conversation comment, and
// Reactions are the reactions the account the city posts as left on it.
type Comment struct {
	ID        int64
	Author    string
	Body      string
	CreatedAt string
	Review    *Review
	Reactions []string
}

// Thread is a review thread with its comments, oldest first.
type Thread struct {
	ID       string
	Resolved bool
	Comments []Comment
}

// ScriptsDir is the pack's scripts directory: GCTK_SCRIPTS_DIR when it is set,
// which gctk-resolve.sh exports, and otherwise the one `gc gc-toolkit
// scripts-dir` prints.
func ScriptsDir() (string, error) { return ScriptsDirContext(context.Background()) }

// ScriptsDirContext is [ScriptsDir] for a reader with a deadline: the gc it
// runs ends when ctx does, as [LoadContext] says.
func ScriptsDirContext(ctx context.Context) (string, error) {
	if dir := os.Getenv("GCTK_SCRIPTS_DIR"); dir != "" {
		return dir, nil
	}
	cmd := command(ctx, "gc", "gc-toolkit", "scripts-dir")
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if dir := strings.TrimSpace(string(out)); err == nil && dir != "" {
		return dir, nil
	}
	if err != nil && ctx.Err() != nil {
		return "", fmt.Errorf("feedback: the pack's scripts directory did not resolve: %w", context.Cause(ctx))
	}
	if msg := strings.TrimSpace(stderr.String()); msg != "" {
		return "", fmt.Errorf("feedback: the pack's scripts directory did not resolve: %s", msg)
	}
	return "", errors.New("feedback: the pack's scripts directory did not resolve: GCTK_SCRIPTS_DIR is unset and gc named none")
}

// Load reads the definition through pr-post.sh in scripts, run in checkout, a
// directory in the rig's checkout, so it holds the prefixes the rig declares.
func Load(scripts, checkout string) (*Rule, error) {
	return LoadContext(context.Background(), scripts, checkout)
}

// LoadContext is [Load] for a reader with a deadline, such as the helm board:
// the load, and every application of the rule it returns, ends when ctx does.
// Each command runs in a process group of its own, and once ctx is done the
// whole group is killed, so a reader whose deadline passed has stopped every
// process the definition started by the time it returns. pr-post.sh runs git,
// which can wait on a fetch in a partial clone, and a stop that killed bash
// alone would leave git holding the load's output. A command that has not
// started by then does not start, and one ctx ended returns ctx's cause.
func LoadContext(ctx context.Context, scripts, checkout string) (*Rule, error) {
	cmd := command(ctx, "bash", filepath.Join(scripts, "pr-post.sh"), "feedback-def")
	cmd.Dir = checkout
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil && ctx.Err() != nil {
		return nil, fmt.Errorf("feedback: pr-post.sh feedback-def: %w", context.Cause(ctx))
	}
	def := strings.TrimSpace(string(out))
	if err != nil || def == "" {
		msg := strings.TrimSpace(stderr.String())
		if msg == "" && err != nil {
			msg = err.Error()
		}
		return nil, fmt.Errorf("feedback: pr-post.sh feedback-def printed no definition: %s", msg)
	}
	return &Rule{def: def, ctx: ctx}, nil
}

// Reviews returns the ids of the reviews that are feedback.
func (r *Rule) Reviews(self, since string, reviews []Review) ([]int64, error) {
	rows := make([]map[string]any, 0, len(reviews))
	for _, v := range reviews {
		rows = append(rows, map[string]any{"id": v.ID, "user": login(v.Author), "body": v.Body,
			"state": v.State, "submitted_at": nullable(v.SubmittedAt)})
	}
	return r.ids(self, since, `[ .[] | select(gc_feedback($self; $since)) | .id ]`, rows)
}

// Comments returns the ids of the inline comments that no dismissal retired and
// that are feedback, each dated by the review that carried it.
func (r *Rule) Comments(self, since string, comments []Comment) ([]int64, error) {
	revs := []map[string]any{}
	seen := map[int64]bool{}
	rows := make([]map[string]any, 0, len(comments))
	for _, c := range comments {
		row := map[string]any{"id": c.ID, "user": login(c.Author), "body": c.Body, "created_at": nullable(c.CreatedAt)}
		if c.Review != nil {
			row["pull_request_review_id"] = c.Review.ID
			if !seen[c.Review.ID] {
				seen[c.Review.ID] = true
				revs = append(revs, map[string]any{"id": c.Review.ID, "state": c.Review.State,
					"submitted_at": nullable(c.Review.SubmittedAt)})
			}
		}
		rows = append(rows, row)
	}
	return r.ids(self, since, `(input) as $revs | input
  | [ live_comments($revs)[] | select(gc_feedback($self; $since)) | .id ]`, revs, rows)
}

// IssueComments returns the ids of the conversation comments that are feedback.
func (r *Rule) IssueComments(self, since string, comments []Comment) ([]int64, error) {
	rows := make([]map[string]any, 0, len(comments))
	for _, c := range comments {
		rows = append(rows, map[string]any{"id": c.ID, "user": login(c.Author), "body": c.Body,
			"created_at": nullable(c.CreatedAt)})
	}
	return r.ids(self, since, `[ .[] | select(gc_feedback($self; $since)) | .id ]`, rows)
}

// Awaiting returns the ids of the review threads that wait on the city's
// answer.
func (r *Rule) Awaiting(self, since string, threads []Thread) ([]string, error) {
	nodes := make([]map[string]any, 0, len(threads))
	for _, t := range threads {
		posts := make([]map[string]any, 0, len(t.Comments))
		for _, c := range t.Comments {
			groups := []map[string]any{}
			for _, x := range c.Reactions {
				groups = append(groups, map[string]any{"content": x, "viewerHasReacted": true})
			}
			post := map[string]any{"author": login(c.Author), "body": c.Body, "createdAt": nullable(c.CreatedAt),
				"pullRequestReview": nil, "reactionGroups": groups}
			if c.Review != nil {
				post["pullRequestReview"] = map[string]any{"state": c.Review.State, "submittedAt": nullable(c.Review.SubmittedAt)}
			}
			posts = append(posts, post)
		}
		nodes = append(nodes, map[string]any{"id": t.ID, "isResolved": t.Resolved,
			"comments": map[string]any{"nodes": posts}})
	}
	out, err := r.run(self, since, `[ .[] | select(gc_thread_awaits_answer($self; $since)) | .id ]`, nodes)
	if err != nil {
		return nil, err
	}
	var ids []string
	if err := json.Unmarshal(out, &ids); err != nil {
		return nil, fmt.Errorf("feedback: the threads' answer did not decode: %w", err)
	}
	return ids, nil
}

// ids runs program over inputs and reads the ids it prints.
func (r *Rule) ids(self, since, program string, inputs ...any) ([]int64, error) {
	out, err := r.run(self, since, program, inputs...)
	if err != nil {
		return nil, err
	}
	var ids []int64
	if err := json.Unmarshal(out, &ids); err != nil {
		return nil, fmt.Errorf("feedback: the answer did not decode: %w", err)
	}
	return ids, nil
}

// run applies the definition and program to inputs through jq, each input one
// JSON document on its standard input. A program over more than one input
// reads them with `input`, so jq starts with no input of its own.
func (r *Rule) run(self, since, program string, inputs ...any) ([]byte, error) {
	var in bytes.Buffer
	enc := json.NewEncoder(&in)
	for _, v := range inputs {
		if err := enc.Encode(v); err != nil {
			return nil, fmt.Errorf("feedback: an input did not encode: %w", err)
		}
	}
	args := []string{"-c", "--arg", "self", self, "--arg", "since", since}
	if len(inputs) > 1 {
		args = append(args, "-n")
	}
	args = append(args, r.def+"\n"+program)
	cmd := command(r.ctx, "jq", args...)
	cmd.Stdin = &in
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		if r.ctx.Err() != nil {
			return nil, fmt.Errorf("feedback: jq: %w", context.Cause(r.ctx))
		}
		if msg := strings.TrimSpace(stderr.String()); msg != "" {
			return nil, fmt.Errorf("feedback: jq: %s", msg)
		}
		return nil, fmt.Errorf("feedback: jq: %w", err)
	}
	return out, nil
}

// stopGrace is how long a command stopped by its context may hold its output
// open before the wait for it gives up. The stop kills every process the
// command started, so only one that left the command's process group can hold
// it that long.
const stopGrace = 2 * time.Second

// command is the command that runs name with args and ends when ctx does, as
// [LoadContext] says. A context that can never end, the one [Load] and
// [ScriptsDir] give, runs it in gctk's own process group, where a signal to
// that group stops it with gctk: the order runner's stop of a landing pass
// that outlives its timeout, or a terminal's Ctrl-C.
func command(ctx context.Context, name string, args ...string) *exec.Cmd {
	if ctx.Done() == nil {
		return exec.Command(name, args...)
	}
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error { return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL) }
	cmd.WaitDelay = stopGrace
	return cmd
}

// login is an author as the definition reads one, null when GitHub names none.
func login(name string) any {
	if name == "" {
		return nil
	}
	return map[string]string{"login": name}
}

// nullable is an instant GitHub left unset as null, which the definition
// passes over for the next instant it dates a post by.
func nullable(s string) any {
	if s == "" {
		return nil
	}
	return s
}
