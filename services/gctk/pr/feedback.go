package pr

import (
	"cmp"
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
	f, err := feedbackOf(rule, self, since, reviews, threads, comments)
	if err != nil {
		return NewestFeedback{}, err
	}
	return f.newest(), nil
}

// feedbackIDs are the posts the definition reads as feedback, in each id
// space: the reviews, of which the intake counts those in counted, the inline
// comments and the conversation comments.
type feedbackIDs struct {
	reviews, inline, conversation []int64
	counted                       map[int64]bool
}

// newest is the highest feedback id in each id space.
func (f feedbackIDs) newest() NewestFeedback {
	return NewestFeedback{Review: newest(f.reviews, 0, f.counted), Inline: newest(f.inline, 0, nil),
		Conversation: newest(f.conversation, 0, nil)}
}

// feedbackOf applies the definition to every post of the PR, once in each id
// space.
func feedbackOf(rule Feedback, self, since string, reviews []gh.Review, threads []gh.Thread, comments []gh.IssueComment) (feedbackIDs, error) {
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
		return feedbackIDs{}, err
	}
	var inline []feedback.Comment
	for _, t := range threads {
		for _, c := range t.Comments {
			inline = append(inline, commentOf(c))
		}
	}
	commentIDs, err := rule.Comments(self, since, inline)
	if err != nil {
		return feedbackIDs{}, err
	}
	var convo []feedback.Comment
	for _, c := range comments {
		convo = append(convo, feedback.Comment{ID: c.ID, Author: c.Author, Body: c.Body, CreatedAt: c.CreatedAt})
	}
	issueIDs, err := rule.IssueComments(self, since, convo)
	if err != nil {
		return feedbackIDs{}, err
	}
	return feedbackIDs{reviews: reviewIDs, inline: commentIDs, conversation: issueIDs, counted: counted}, nil
}

// approvals is each review among reviews that approves and has not been
// dismissed, whoever gave it, in id order, with the newest feedback comment it
// carries among threads (newestCarried). The definition reads an inline comment
// alone, so the comments a dismissal of the review would retire unread are
// those, past the comment watermark (unrouted).
func approvals(reviews []gh.Review, threads []gh.Thread, inline []int64) []Approval {
	out := []Approval{}
	for _, v := range reviews {
		if v.State != "APPROVED" {
			continue
		}
		out = append(out, Approval{ID: v.ID, Author: v.Author, Commit: v.Commit, Inline: newestCarried(v.ID, threads, inline)})
	}
	slices.SortFunc(out, func(a, b Approval) int { return cmp.Compare(a.ID, b.ID) })
	return out
}

// newestCarried is the newest of the inline comments review carries among
// threads that inline, the feedback ids of the inline comments, names, or 0
// when it carries none.
func newestCarried(review int64, threads []gh.Thread, inline []int64) int64 {
	var top int64
	for _, t := range threads {
		for _, c := range t.Comments {
			if c.Review != nil && c.Review.ID == review && c.ID > top && slices.Contains(inline, c.ID) {
				top = c.ID
			}
		}
	}
	return top
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

// unrouted is the newest inline comment of each approval named that a
// dismissal would retire before the intake routes it, in id order: feedback by
// the definition, carried by the approval, and newer than the comment
// watermark and the mark the threads have answered through. It is the rule a
// dismisser waits by (unrouted_comment_ids in
// assets/scripts/review-dismissal.sh), over the newest such comment each
// approval keeps: the saved read's, or the act's own read's (readUnrouted).
func unrouted(rc receipts, targets []Approval) []int64 {
	floor := max(rc.comment, rc.commentAnswered)
	var out []int64
	for _, a := range targets {
		if a.Inline > floor {
			out = append(out, a.Inline)
		}
	}
	slices.Sort(out)
	return slices.Compact(out)
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
