package pr

import (
	"fmt"
	"slices"
	"strconv"
	"strings"
	"unicode"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/feedback"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
)

// Feedback is the pack's one definition of feedback, which the feedback
// adapter's Rule applies and its fake answers: which reviews and comments are
// feedback, which inline comments a dismissal has not retired, and which review
// threads wait on the city's answer.
type Feedback interface {
	Reviews(self, since string, reviews []feedback.Review) ([]int64, error)
	Comments(self, since string, comments []feedback.Comment) ([]int64, error)
	IssueComments(self, since string, comments []feedback.Comment) ([]int64, error)
	Awaiting(self, since string, threads []feedback.Thread) ([]string, error)
}

// countedReviewStates are the states of a review whose message the intake
// counts as feedback, as pr-facts.sh counts it (counted_review_ids).
var countedReviewStates = []string{"COMMENTED", "CHANGES_REQUESTED"}

// receipts are the anchor's records of the feedback the intake has handled:
// the watermark of each id space, and the marks through which the review
// threads have answered the reviews and the inline comments.
type receipts struct {
	review, comment, issueComment   int64
	reviewAnswered, commentAnswered int64
}

// mark reads a receipt. A value that is not a whole number reads as 0.
func mark(v string) int64 {
	n, err := strconv.ParseInt(v, 10, 64)
	if err != nil || n < 0 {
		return 0
	}
	return n
}

// unhandled is one condition for each id space that holds feedback the
// receipts do not cover: a review, an inline comment or a conversation comment
// that the intake counts, newer than its space's watermark and, for reviews and
// inline comments, past the mark the threads have answered through. The intake
// counts what the definition reads as feedback, and of a review only a message
// that comments or requests changes and carries text, so a review that approves
// holds nothing by its message, and neither does feedback the definition
// leaves out.
func unhandled(rule Feedback, self, since string, rc receipts, reviews []gh.Review, threads []gh.Thread, comments []gh.IssueComment) ([]Condition, error) {
	var revs []feedback.Review
	counted := map[int64]bool{}
	for _, v := range reviews {
		revs = append(revs, reviewOf(v))
		if slices.Contains(countedReviewStates, v.State) && strings.TrimFunc(v.Body, unicode.IsSpace) != "" {
			counted[v.ID] = true
		}
	}
	reviewIDs, err := rule.Reviews(self, since, revs)
	if err != nil {
		return nil, err
	}
	var inline []feedback.Comment
	for _, t := range threads {
		for _, c := range t.Comments {
			inline = append(inline, commentOf(c))
		}
	}
	commentIDs, err := rule.Comments(self, since, inline)
	if err != nil {
		return nil, err
	}
	var convo []feedback.Comment
	for _, c := range comments {
		convo = append(convo, feedback.Comment{ID: c.ID, Author: c.Author, Body: c.Body, CreatedAt: c.CreatedAt})
	}
	issueIDs, err := rule.IssueComments(self, since, convo)
	if err != nil {
		return nil, err
	}
	var out []Condition
	if id := newest(reviewIDs, max(rc.review, rc.reviewAnswered), counted); id > 0 {
		out = append(out, Condition{Kind: KindFeedback,
			Detail: fmt.Sprintf("review %d is feedback past the review watermark that the intake has not handled", id)})
	}
	if id := newest(commentIDs, max(rc.comment, rc.commentAnswered), nil); id > 0 {
		out = append(out, Condition{Kind: KindFeedback,
			Detail: fmt.Sprintf("inline comment %d is feedback past the comment watermark that the intake has not handled", id)})
	}
	if id := newest(issueIDs, rc.issueComment, nil); id > 0 {
		out = append(out, Condition{Kind: KindFeedback,
			Detail: fmt.Sprintf("conversation comment %d is feedback past the conversation watermark that the intake has not handled", id)})
	}
	return out, nil
}

// newest is the highest id above floor among ids, of those only names when it
// is not nil, or 0 when there is none.
func newest(ids []int64, floor int64, only map[int64]bool) int64 {
	var top int64
	for _, id := range ids {
		if id > floor && id > top && (only == nil || only[id]) {
			top = id
		}
	}
	return top
}

// awaiting is one condition for each review thread that waits on the city's
// answer, by the definition.
func awaiting(rule Feedback, self, since string, threads []gh.Thread) ([]Condition, error) {
	var ts []feedback.Thread
	for _, t := range threads {
		ft := feedback.Thread{ID: t.ID, Resolved: t.Resolved}
		for _, c := range t.Comments {
			ft.Comments = append(ft.Comments, commentOf(c))
		}
		ts = append(ts, ft)
	}
	ids, err := rule.Awaiting(self, since, ts)
	if err != nil {
		return nil, err
	}
	var out []Condition
	for _, id := range ids {
		out = append(out, Condition{Kind: KindThread, Value: id, Detail: fmt.Sprintf("review thread %s waits on the city's answer", id)})
	}
	return out, nil
}

func reviewOf(v gh.Review) feedback.Review {
	return feedback.Review{ID: v.ID, Author: v.Author, Body: v.Body, State: v.State, SubmittedAt: v.SubmittedAt}
}

func commentOf(c gh.Comment) feedback.Comment {
	fc := feedback.Comment{ID: c.ID, Author: c.Author, Body: c.Body, CreatedAt: c.CreatedAt, Reactions: c.ViewerReactions}
	if c.Review != nil {
		fc.Review = &feedback.Review{ID: c.Review.ID, State: c.Review.State, SubmittedAt: c.Review.SubmittedAt}
	}
	return fc
}
