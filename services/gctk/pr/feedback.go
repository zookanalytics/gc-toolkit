package pr

import (
	"cmp"
	"fmt"
	"regexp"
	"slices"
	"strings"
	"unicode"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/feedback"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
)

// Feedback is the pack's one definition of feedback, which the feedback
// adapter's Rule applies and its fake answers: which posts are feedback that
// the city has not taken, among the inline comments a dismissal has not
// retired, and which review threads wait on the city's answer.
type Feedback interface {
	Untaken(self, since string, reviews []feedback.Review, inline, conversation []feedback.Comment) (feedback.Untaken, error)
	Awaiting(self, since string, threads []feedback.Thread) ([]string, error)
}

// countedReviewStates are the states of a review whose message the intake
// counts as a post: a comment, a request for changes and an approval. A
// dismissed review's message counts for nothing.
var countedReviewStates = []string{"COMMENTED", "CHANGES_REQUESTED", "APPROVED"}

// The kinds of a post.
const (
	PostReview       = "review"
	PostInline       = "inline"
	PostConversation = "conversation"
)

// Post is one post on a PR that is feedback the city has not taken: it carries
// neither of the city's marks. Kind is review, inline or conversation, ID its
// id in that space, Node its node id, which the take marks it by, and URL its
// address. State is a review's state, Path and Line an inline comment's file
// and the line it was made on (originalLine), Line 0 for a comment on a file
// as a whole, and Review the review that carried an inline comment.
type Post struct {
	Kind   string `json:"kind"`
	ID     int64  `json:"id"`
	Node   string `json:"node"`
	Author string `json:"author"`
	URL    string `json:"url"`
	State  string `json:"state,omitempty"`
	Path   string `json:"path,omitempty"`
	Line   int    `json:"line,omitempty"`
	Review int64  `json:"review,omitempty"`
}

// name is the post as a sentence names it.
func (p Post) name() string {
	switch p.Kind {
	case PostReview:
		return fmt.Sprintf("the message of review %d", p.ID)
	case PostInline:
		return fmt.Sprintf("inline comment %d", p.ID)
	}
	return fmt.Sprintf("conversation comment %d", p.ID)
}

// reason is the one line an ask names the post by, on PR number: its kind, its
// author, the PR, an inline comment's file and the line it was made on, and its
// URL, where a run reads the post as it stands. It holds nothing an edit of the
// post changes, so the take finds the ask it filed for the post (review.FileAsk)
// however often it runs, and postNamed reads the URL back.
func (p Post) reason(number int) string {
	who := p.Author
	if who == "" {
		who = "an account GitHub no longer names"
	}
	what := "Conversation comment"
	switch p.Kind {
	case PostReview:
		what = map[string]string{"APPROVED": "Approval message", "CHANGES_REQUESTED": "Request for changes"}[p.State]
		if what == "" {
			what = "Review"
		}
	case PostInline:
		what = "Inline comment"
	}
	where := ""
	if p.Kind == PostInline && p.Path != "" {
		where = " on " + p.Path
		if p.Line > 0 {
			where = fmt.Sprintf(" at %s line %d", p.Path, p.Line)
		}
	}
	return fmt.Sprintf("%s by %s on PR #%d%s: %s", what, who, number, where, p.URL)
}

// postFragment is the fragment of a post's URL on its PR: a review's, an inline
// comment's or a conversation comment's.
var postFragment = regexp.MustCompile(`^(pullrequestreview-|discussion_r|issuecomment-)[0-9]+$`)

// postNamed is the URL of the post on the PR at pr that an ask's reason names,
// as the take writes one (Post.reason), or "" when it names none.
func postNamed(reason, pr string) string {
	i := strings.LastIndex(reason, ": ")
	if i < 0 {
		return ""
	}
	url := strings.TrimSpace(reason[i+2:])
	base, frag, ok := strings.Cut(url, "#")
	if !ok || !postFragment.MatchString(frag) {
		return ""
	}
	h1, r1, n1, ok1 := record.ParseURL(base)
	h2, r2, n2, ok2 := record.ParseURL(pr)
	if !ok1 || !ok2 || identity(h1, r1, n1) != identity(h2, r2, n2) {
		return ""
	}
	return url
}

// untakenOf is each post among a PR's reviews, review threads and conversation
// comments that is feedback the city has not taken, by the definition rule
// applies from since as the account self acts as: a review in a state the
// intake counts whose message is not blank, an inline comment no dismissal
// retired, and a conversation comment, each carrying neither of the city's
// marks. It is the one reading of which posts the city has not taken, which the
// one-PR update saves, the landing order's take files and marks, and a
// withdrawal waits on. They come in that order of kinds, each kind by id.
func untakenOf(rule Feedback, self, since string, reviews []gh.Review, threads []gh.Thread, comments []gh.IssueComment) ([]Post, error) {
	var revs []feedback.Review
	byReview := map[int64]gh.Review{}
	for _, v := range reviews {
		if slices.Contains(countedReviewStates, v.State) && strings.TrimFunc(v.Body, unicode.IsSpace) != "" {
			revs = append(revs, reviewOf(v))
			byReview[v.ID] = v
		}
	}
	var inline []feedback.Comment
	byInline := map[int64]gh.Comment{}
	for _, t := range threads {
		for _, c := range t.Comments {
			inline = append(inline, commentOf(c))
			byInline[c.ID] = c
		}
	}
	var convo []feedback.Comment
	byConvo := map[int64]gh.IssueComment{}
	for _, c := range comments {
		convo = append(convo, feedback.Comment{ID: c.ID, Author: c.Author, Body: c.Body, CreatedAt: c.CreatedAt,
			Reactions: c.ViewerReactions})
		byConvo[c.ID] = c
	}
	got, err := rule.Untaken(self, since, revs, inline, convo)
	if err != nil {
		return nil, err
	}
	out := []Post{}
	for _, id := range sorted(got.Reviews) {
		if v, ok := byReview[id]; ok {
			out = append(out, Post{Kind: PostReview, ID: id, Node: v.NodeID, Author: v.Author, URL: v.URL, State: v.State})
		}
	}
	for _, id := range sorted(got.Inline) {
		if c, ok := byInline[id]; ok {
			p := Post{Kind: PostInline, ID: id, Node: c.NodeID, Author: c.Author, URL: c.URL, Path: c.Path, Line: c.OriginalLine}
			if c.Review != nil {
				p.Review = c.Review.ID
			}
			out = append(out, p)
		}
	}
	for _, id := range sorted(got.Conversation) {
		if c, ok := byConvo[id]; ok {
			out = append(out, Post{Kind: PostConversation, ID: id, Node: c.NodeID, Author: c.Author, URL: c.URL})
		}
	}
	return out, nil
}

// sorted is ids in order, each once.
func sorted(ids []int64) []int64 {
	out := slices.Clone(ids)
	slices.Sort(out)
	return slices.Compact(out)
}

// approvals is each review among reviews that approves and has not been
// dismissed, whoever gave it, in id order.
func approvals(reviews []gh.Review) []Approval {
	out := []Approval{}
	for _, v := range reviews {
		if v.State == "APPROVED" {
			out = append(out, Approval{ID: v.ID, Author: v.Author, Commit: v.Commit})
		}
	}
	slices.SortFunc(out, func(a, b Approval) int { return cmp.Compare(a.ID, b.ID) })
	return out
}

// unhandled is one condition for each post among untaken, the posts of the PR
// that are feedback the city has not taken, each of which waits for the take
// to file its ask and mark it. Once the post is marked, its ask holds the PR as
// any wait of the bead's own does.
func unhandled(untaken []Post) []Condition {
	var out []Condition
	for _, p := range untaken {
		out = append(out, Condition{Kind: KindFeedback, Value: p.URL,
			Detail: fmt.Sprintf("%s is feedback the city has not taken", p.name())})
	}
	return out
}

// unrouted is each post among untaken that dismissing targets would retire
// before the take files its ask: the message of an approval among targets,
// which a dismissal takes out of the reviews the intake counts, and an inline
// comment such an approval carries, which a dismissal retires (live_comments).
// It is the rule a dismisser waits by, over the posts the act's own read of the
// PR's reviews and review threads found untaken (readUnrouted).
func unrouted(targets []Approval, untaken []Post) []Post {
	target := func(id int64) bool { return slices.ContainsFunc(targets, func(a Approval) bool { return a.ID == id }) }
	var out []Post
	for _, p := range untaken {
		if (p.Kind == PostReview && target(p.ID)) || (p.Kind == PostInline && p.Review != 0 && target(p.Review)) {
			out = append(out, p)
		}
	}
	return out
}

// awaiting is the ids of the review threads that wait on the city's answer, by
// the definition.
func awaiting(rule Feedback, self, since string, threads []gh.Thread) ([]string, error) {
	var ts []feedback.Thread
	for _, t := range threads {
		ft := feedback.Thread{ID: t.ID, Resolved: t.Resolved}
		for _, c := range t.Comments {
			ft.Comments = append(ft.Comments, commentOf(c))
		}
		ts = append(ts, ft)
	}
	return rule.Awaiting(self, since, ts)
}

func reviewOf(v gh.Review) feedback.Review {
	return feedback.Review{ID: v.ID, Author: v.Author, Body: v.Body, State: v.State, SubmittedAt: v.SubmittedAt,
		Reactions: v.ViewerReactions}
}

func commentOf(c gh.Comment) feedback.Comment {
	fc := feedback.Comment{ID: c.ID, Author: c.Author, Body: c.Body, CreatedAt: c.CreatedAt, Reactions: c.ViewerReactions}
	if c.Review != nil {
		fc.Review = &feedback.Review{ID: c.Review.ID, State: c.Review.State, SubmittedAt: c.Review.SubmittedAt}
	}
	return fc
}
