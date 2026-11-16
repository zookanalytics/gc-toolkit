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

// newestFeedback is the highest feedback id in each id space, by the
// definition, which reads the text of every post: a review, an inline comment
// or a conversation comment the intake counts. Of a review the intake counts
// only a message that comments or requests changes and carries text, so a
// review that approves counts nothing by its message, and neither does feedback
// the definition leaves out.
func newestFeedback(rule Feedback, self, since string, reviews []gh.Review, threads []gh.Thread, comments []gh.IssueComment) (NewestFeedback, error) {
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
		return NewestFeedback{}, err
	}
	var inline []feedback.Comment
	for _, t := range threads {
		for _, c := range t.Comments {
			inline = append(inline, commentOf(c))
		}
	}
	commentIDs, err := rule.Comments(self, since, inline)
	if err != nil {
		return NewestFeedback{}, err
	}
	var convo []feedback.Comment
	for _, c := range comments {
		convo = append(convo, feedback.Comment{ID: c.ID, Author: c.Author, Body: c.Body, CreatedAt: c.CreatedAt})
	}
	issueIDs, err := rule.IssueComments(self, since, convo)
	if err != nil {
		return NewestFeedback{}, err
	}
	return NewestFeedback{Review: newest(reviewIDs, 0, counted), Inline: newest(commentIDs, 0, nil),
		Conversation: newest(issueIDs, 0, nil)}, nil
}

// unhandled is one condition for each id space whose newest feedback the
// receipts do not cover: newer than the space's watermark and, for reviews and
// inline comments, past the mark the threads have answered through. The
// receipts are the store's and move when the intake routes feedback, so the
// compare is made at each read.
func unhandled(rc receipts, n NewestFeedback) []Condition {
	var out []Condition
	if id := newest([]int64{n.Review}, max(rc.review, rc.reviewAnswered), nil); id > 0 {
		out = append(out, Condition{Kind: KindFeedback,
			Detail: fmt.Sprintf("review %d is feedback past the review watermark that the intake has not handled", id)})
	}
	if id := newest([]int64{n.Inline}, max(rc.comment, rc.commentAnswered), nil); id > 0 {
		out = append(out, Condition{Kind: KindFeedback,
			Detail: fmt.Sprintf("inline comment %d is feedback past the comment watermark that the intake has not handled", id)})
	}
	if id := newest([]int64{n.Conversation}, rc.issueComment, nil); id > 0 {
		out = append(out, Condition{Kind: KindFeedback,
			Detail: fmt.Sprintf("conversation comment %d is feedback past the conversation watermark that the intake has not handled", id)})
	}
	return out
}

// unrouted is the ids of the inline comments that dismissing the reviews named
// would retire before the intake routes them, in id order: each is carried by
// one of those reviews, is feedback by the definition, which also leaves out a
// comment a dismissal already retired, and is newer than the comment watermark
// and the mark the threads have answered through. It is the rule a dismisser
// waits by (unrouted_comment_ids in assets/scripts/review-dismissal.sh), the
// definition applied to the comments it names.
func unrouted(rule Feedback, self, since string, rc receipts, threads []gh.Thread, reviews []int64) ([]int64, error) {
	var carried []feedback.Comment
	for _, t := range threads {
		for _, c := range t.Comments {
			if c.Review != nil && slices.Contains(reviews, c.Review.ID) {
				carried = append(carried, commentOf(c))
			}
		}
	}
	if len(carried) == 0 {
		return nil, nil
	}
	ids, err := rule.Comments(self, since, carried)
	if err != nil {
		return nil, err
	}
	floor := max(rc.comment, rc.commentAnswered)
	var out []int64
	for _, id := range ids {
		if id > floor {
			out = append(out, id)
		}
	}
	slices.Sort(out)
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
	return feedback.Review{ID: v.ID, Author: v.Author, Body: v.Body, State: v.State, SubmittedAt: v.SubmittedAt}
}

func commentOf(c gh.Comment) feedback.Comment {
	fc := feedback.Comment{ID: c.ID, Author: c.Author, Body: c.Body, CreatedAt: c.CreatedAt, Reactions: c.ViewerReactions}
	if c.Review != nil {
		fc.Review = &feedback.Review{ID: c.Review.ID, State: c.Review.State, SubmittedAt: c.Review.SubmittedAt}
	}
	return fc
}
